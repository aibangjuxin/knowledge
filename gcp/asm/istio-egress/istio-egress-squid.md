# GKE Private Cluster 中基于 Istio Egress Gateway + Squid 的 SaaS 出站方案

## 1. Goal and Constraints

### 目标

在 `GKE Standard Private Cluster` 中实现下面这条受控出站链路：

```text
Pod -> sidecar -> Istio Egress Gateway -> Squid explicit forward proxy -> SaaS
```

并满足：

- 按 `SaaS FQDN` 做 allow-list
- 按 `Kubernetes ServiceAccount` 做授权
- 业务 Pod 不可直接访问公网或 Squid
- `SaaS2` 需要客户端 mTLS，客户端证书由 egress gateway 代发
- 可观测、可审计、可验证

### 已知前提

- 集群类型：`GKE Standard`
- 出口代理：`Squid explicit forward proxy`，监听 `3128`
- `SaaS1 / SaaS3`：普通 HTTPS
- `SaaS2`：要求客户端 mTLS，且 `SNI=api.saas2.com`

### 关键修正

这里的 `Squid:3128` 不是透明 TCP relay。

对 Squid 默认 forward proxy 模式来说：

- `HTTP` 需要标准 proxy request
- `HTTPS` 通常需要 `HTTP CONNECT host:443`

所以：

- 不能把 `3128` 当成普通上游 `TCP/TLS` 端口
- `egress gateway` 必须具备“对 Squid 发显式代理请求”的能力

---

## 2. Recommended Architecture (Squid-aware)

### 推荐分层

- `Istio/ASM` 负责：
  - FQDN allow-list
  - sidecar 到 egress gateway 的强制路径
  - 基于 `ServiceAccount` 的授权
  - egress gateway 的证书管理
- `EnvoyFilter` 负责：
  - 把 egress gateway 的上游访问改造成 `CONNECT to Squid`
  - 必要时打开 `CONNECT` 支持或补充 forward-proxy 行为
- `Squid` 负责：
  - 显式代理转发
  - ACL
  - access log
- `NetworkPolicy + 节点/VPC` 负责：
  - non-bypassable

### 流量模型拆开看

#### SaaS1 / SaaS3

```text
App HTTPS -> sidecar
sidecar -> egress gateway
egress gateway -> CONNECT api.saasX.com:443 -> Squid:3128
CONNECT 隧道建立后 -> 原始 TLS 流进隧道 -> SaaS
```

这个路径最自然。

因为：

- App 仍然访问原始域名
- egress gateway 可以用下游 `SNI` 做授权
- Squid 只看见 `CONNECT api.saasX.com:443`
- SaaS 的真实 TLS 仍然是端到端穿过 CONNECT tunnel

#### SaaS2

你要求的是：

```text
App -> egress gateway
egress gateway 代表应用发 client mTLS
然后仍然经过 Squid
```

这比 `SaaS1 / SaaS3` 难很多。

因为这里不是简单透传：

- egress gateway 需要先跟 Squid 建 `CONNECT api.saas2.com:443`
- 然后在 CONNECT tunnel 里，再由 gateway 主动发起到 `api.saas2.com` 的 TLS 握手
- 这个 TLS 握手里还要带客户端证书、私钥、CA、SNI

这已经不再是“只靠标准 Istio 路由 CRD”能优雅搞定的事情。

---

## 3. What Still Works with Standard Istio CRDs

下面这些能力依然适合继续用标准 Istio CRD：

### 3.1 FQDN allow-list

- `ServiceEntry`
- `outboundTrafficPolicy: REGISTRY_ONLY`

作用：

- 只把允许访问的 SaaS 注册进 mesh
- 未注册域名不允许出站

### 3.2 强制所有业务 Pod 先到 egress gateway

- `VirtualService`
- `Gateway`
- `DestinationRule`（内部 `ISTIO_MUTUAL`）

作用：

- sidecar 不能直接去外部
- 所有命中的 SaaS 流量先送到 egress gateway

### 3.3 按 ServiceAccount 授权

- `AuthorizationPolicy`

作用：

- 在 egress gateway 看到 `source.principal`
- 对 `SaaS1 / SaaS3` 用 `connection.sni`
- 对明文 HTTP 场景可用 `hosts`

### 3.4 Network 强封禁

- `NetworkPolicy`
- 节点池/VPC firewall/NAT 约束

作用：

- apps namespace Pod 只能到 egress gateway
- egress gateway 只能到 Squid
- 业务节点不能直接公网出口

---

## 4. What Requires EnvoyFilter or Custom Gateway Behavior

### 4.1 SaaS1 / SaaS3 通过 Squid 的 CONNECT tunnel

这是最明确必须用 `EnvoyFilter` 的部分。

原因：

- 标准 `VirtualService` 只能“路由到 Squid”
- 但 Squid 要的不是“被动接收一条 TLS 流”
- Squid 要的是 `CONNECT api.saas1.com:443`

这里最关键的官方能力是：

- Envoy `tcp_proxy` 支持 `tunneling_config`
- 可以把 TCP payload 封装进上游 `HTTP CONNECT`
- `hostname` 可以动态使用 `%REQUESTED_SERVER_NAME%:443`

这意味着理论上可以做出下面这种网关行为：

```text
收到下游到 api.saas1.com 的 TLS
按 SNI 匹配到对应 filter chain
用 tcp_proxy.tunneling_config 向 Squid 发 CONNECT api.saas1.com:443
CONNECT 成功后，把下游 TLS 流原样塞进 tunnel
```

这是 `SaaS1 / SaaS3` 的推荐落地路径。

### 4.2 SaaS2 的 client mTLS through Squid

这是全方案里最复杂的一块。

严格来说你要同时满足：

1. gateway 代表应用发客户端证书
2. SNI 必须是 `api.saas2.com`
3. 仍然必须走 `Squid explicit proxy`

这通常意味着 gateway 需要：

- 先完成到 Squid 的 `CONNECT api.saas2.com:443`
- 再在隧道里发起到目标 SaaS 的 TLS origination
- 该 TLS origination 还要带 `client cert`

这类组合在设计上是可想象的，但实施上通常需要：

- 自定义 `EnvoyFilter`
- 对 HCM / route / cluster / tcp_proxy / CONNECT 路径做更深的 Envoy 配置
- 明确测试 gateway 中 `TLS origination + upstream CONNECT tunneling` 的组合行为

### 结论

对 `SaaS2`，我建议把要求拆成两个级别：

#### Level 1: 推荐 V1

- `SaaS1 / SaaS3` 经 `egress gateway -> Squid CONNECT`
- `SaaS2` 暂时走 `egress gateway -> direct mTLS to SaaS2`

优点：

- 快速可落地
- 保留大部分架构目标
- 避免在第一版就把所有复杂性叠到一起

缺点：

- `SaaS2` 不是“所有 SaaS 都经过 Squid”

#### Level 2: 严格版

- `SaaS1 / SaaS3 / SaaS2` 全都必须经过 Squid

优点：

- 完全满足统一出口要求

缺点：

- `SaaS2` 需要高级 Envoy 定制
- 复杂度显著上升
- 变更和排障成本高

---

## 5. Recommended V1 for Production

### 推荐结论

如果你现在的目标是“在生产里先做一版可靠可交付的方案”，我建议：

```text
SaaS1 / SaaS3:
Pod -> sidecar -> egress gateway -> Squid CONNECT -> SaaS

SaaS2:
Pod -> sidecar -> egress gateway -> direct client mTLS -> SaaS2
```

然后再用网络和策略明确区分：

- `SaaS1 / SaaS3` 必须经 Squid
- `SaaS2` 作为带 client cert 的特殊例外，直接由 egress gateway 发起

### 为什么这是更稳的 V1

- `SaaS1 / SaaS3` 的语义和 Squid 完全匹配
- `SaaS2` 的 client mTLS 不需要再叠加一层 Squid CONNECT 复杂度
- 这样仍然保留了：
  - `ServiceAccount` 授权
  - FQDN allow-list
  - non-bypassable
  - 统一审计入口

如果业务或安全策略坚持“所有 SaaS 包括 SaaS2 都必须经过 Squid”，那就进入 `Advanced / Enterprise` 方案，而不是 V1。

---

## 6. Implementation Shape

### 6.1 标准 Istio 资源

继续保留：

- `ServiceEntry`
- `Gateway`
- `VirtualService`
- `DestinationRule`
- `AuthorizationPolicy`
- `NetworkPolicy`

用途不变。

### 6.2 额外新增的 Envoy 层能力

对 `SaaS1 / SaaS3`：

- 在 egress gateway 上补 `EnvoyFilter`
- 让匹配到对应 `SNI` 的 TCP 监听链路使用：
  - `tcp_proxy`
  - `tunneling_config.hostname: "%REQUESTED_SERVER_NAME%:443"`
  - upstream 指向 Squid cluster

对 `SaaS2`：

- 如果走推荐 V1：不经 Squid，直接继续用 gateway TLS origination
- 如果走严格版：需要更高级的 Envoy 组合配置，不能只靠现有那套 YAML

### 6.3 Squid 侧需要的配合

Squid 至少要明确下面几件事：

- 只允许来自 egress gateway 节点/Pod 网段的访问
- 只允许 `CONNECT` 到允许的目的端口，例如 `443`
- 用 ACL 控制允许的目的域名或域名分类
- access.log 记录 `CONNECT api.saas1.com:443` 这类审计线索

注意：

- Squid 看见的是 egress gateway 的源地址，不是原始业务 Pod 的身份
- 所以“按 ServiceAccount 授权”仍然应该留在 Istio egress gateway 侧做

---

## 7. Authorization Model

### Istio 侧

推荐继续在 egress gateway 做：

- `API1 -> SaaS1`
- `API2 -> SaaS1 + SaaS2`
- `API3 -> SaaS3`
- `API4 -> deny all`

判断依据：

- `SaaS1 / SaaS3`：`source.principal + connection.sni`
- `SaaS2`：`source.principal + host`

### Squid 侧

Squid 不负责识别 `ServiceAccount`。

Squid 更适合做：

- 来源网段 ACL
- 目的端口 ACL
- 目的域名 ACL
- 审计日志

所以职责分工应该是：

- `Istio` 决定“谁可以访问哪个 SaaS”
- `Squid` 决定“egress gateway 这个统一出口能代理哪些域名/端口”

---

## 8. Validation

### 验证 SaaS1 / SaaS3

你要同时看到两类证据：

1. egress gateway 日志中，策略命中和授权命中正常
2. Squid access.log 中出现：

```text
CONNECT api.saas1.com:443
CONNECT api.saas3.com:443
```

### 验证 SaaS2

如果是推荐 V1：

- egress gateway 成功拿到 client cert
- 目标 SaaS2 握手成功
- Squid 日志里不会出现 SaaS2 的 CONNECT

如果是严格版：

- 需要同时验证：
  - Squid 出现 `CONNECT api.saas2.com:443`
  - SaaS2 的 client mTLS 成功
  - SNI 正确为 `api.saas2.com`

### 验证 non-bypassable

- apps Pod 直接访问 Squid：失败
- apps Pod 直接访问公网：失败
- 只有 egress gateway 能访问 Squid

---

## 9. Final Recommendation

### 推荐落地顺序

1. 先把 `SaaS1 / SaaS3` 做成 `egress gateway -> Squid CONNECT`
2. 把 `ServiceAccount` 授权和 `NetworkPolicy` 一起收紧
3. `SaaS2` 先以“gateway direct mTLS exception”上线
4. 如果后续必须做到 “SaaS2 也必须经过 Squid”，再单独做高级 Envoy 方案

### 为什么这么排

因为这条路径把复杂度按真实风险排序了：

- `Squid + CONNECT tunneling` 是清晰且可验证的
- `client mTLS through explicit proxy` 是组合复杂度最高、最容易卡在细节上的部分

---

## 10. References

- [Envoy TCP Proxy Filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/listeners/network_filters/tcp_proxy_filter)
- [Envoy TcpProxy proto](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/network/tcp_proxy/v3/tcp_proxy.proto.html)
- [Envoy HTTP Dynamic Forward Proxy](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/http/http_proxy)
- [Envoy Dynamic Forward Proxy Filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/dynamic_forward_proxy_filter)
- [Envoy Route Components](https://www.envoyproxy.io/docs/envoy/latest/api-v3/config/route/v3/route_components.proto.html)
- [Squid `http_port`](https://www.squid-cache.org/Doc/config/http_port/)
- [Istio Egress Gateways](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-gateway/)
- [Istio Egress Gateway TLS Origination](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-gateway-tls-origination/)
- [Istio AuthorizationPolicy Reference](https://istio.io/latest/docs/reference/config/security/authorization-policy/)
- [Istio Authorization Conditions Reference](https://istio.io/latest/docs/reference/config/security/conditions/)
- [GKE NetworkPolicy](https://cloud.google.com/kubernetes-engine/docs/how-to/network-policy)
