# 双入口 GLB (mTLS + TLS) 架构设计与流量拓扑文档

本文档详细记录了 **双入口 GLB (mTLS + TLS) 共享单 IDMZ PSC NEG 架构** 的完整流量路径、设计原理与组件配置规范。配合 [multip-tls-mtls-flow.html](file:///Users/lex/git/gcp/ingress/public-mtls-global-ingress/flow/multip-tls-mtls-flow.html) 架构图使用，可通过本说明逆推并绘制出全套架构与数据流图。

---

## 核心设计摘要 (Architecture Summary)

1. **双入口设计 (Dual GLB Entry)**：
   * **mTLS 入口**：`mtls.caep.uk`（独立 IP_A，包含客户端证书 TLS 握手）。
   * **TLS 入口**：`tls.caep.uk`（独立 IP_B，普通单向 TLS 握手，无客户端证书）。
2. **URL Map 简化**：
   * 两个 GLB 均保留证书 Header 注入功能，但移除了所有 Path 匹配规则，仅做域名与证书终结。
3. **多租户 Cloud Armor 隔离**：
   * 每个 GLB 后挂载 3 个团队专属的 Backend Service (`bs1`, `bs2`, `bs3`)，分别绑定各自团队的 Cloud Armor 安全策略 (`cloudarmor-team1/2/3`)。
4. **共享 IDMZ PSC NEG 跨项目桥接 (核心重点)**：
   * 两个 GLB 下属的全部 6 个 Backend Service 汇聚至**同一个创建在 IDMZ 网络内的 PSC NEG** (`idmz-psc-neg`)。
   * 通过 GCP 背骨网加密 PSC Tunnel 跨项目穿透至 Master 项目的 `Service Attachment`。
5. **Master Nginx MIG 统一接收**：
   * 运行在 VM 上的 Nginx 节点池统一侦听 443 端口，根据 SNI FQDN 区分 `tls.caep.uk` 与 `mtls.caep.uk`，透传 `proxy_pass` 至 K8s Gateway VIP。
6. **K8s Gateway & ListenerSet 分流**：
   * K8s Gateway 包含两个 ListenerSet（ListenerSet A 负责 `tls.caep.uk`，ListenerSet B 负责 `mtls.caep.uk`）。
7. **HTTPRoute SAN Header 动态校验 (mTLS 与 TLS 唯一逻辑差异)**：
   * **mTLS 路径**：HTTPRoute 校验由 GLB 注入的客户端证书 SAN Header（`X-Client-Cert-Chain-Verified = true` 且 `X-Client-Cert-DNSName-SANs = <team-SAN-base64>`），不匹配则直接拒连。
   * **TLS 路径**：HTTPRoute 仅做 Path 匹配，无 Header 校验要求。
8. **Kong Gateway 强制统一网关**：
   * 所有公网 HTTPS 流量（不论 mTLS 或 TLS）最终均汇聚至 Kong DP 网关，再路由至各团队 Runtime Namespace 隔离的 Pod。

---

## 7 层架构分层详解 (7-Zone Layered Architecture)

```
[ Zone 1: 外部客户端层 ]
       │
       ├─► (mTLS Client w/ Client Cert) ──► mtls.caep.uk (IP_A)
       └─► (TLS Client w/o Cert)       ──► tls.caep.uk  (IP_B)
       │
[ Zone 2: GCP 双 GLB 入口层 (Tenant Project) ]
       ├─► mtls-GLB (mTLS 终结 + 客户端证书 Header 注入)
       │      ├─ mtls-team1-bs ──► cloudarmor-team1 policy
       │      ├─ mtls-team2-bs ──► cloudarmor-team2 policy
       │      └─ mtls-team3-bs ──► cloudarmor-team3 policy
       │
       └─► tls-GLB (单向 TLS 终结, 无 Client Cert)
              ├─ tls-team1-bs  ──► cloudarmor-team1 policy
              ├─ tls-team2-bs  ──► cloudarmor-team2 policy
              └─ tls-team3-bs  ──► cloudarmor-team3 policy
       │
       ▼ (6 个 BS 统一汇聚)
[ Zone 3: IDMZ 跨项目网络桥 (IDMZ VPC) ] ◄── ⚠️ 重点: 单一共享 PSC NEG
       └─► idmz-psc-neg (创建于 IDMZ VPC, 挂载至 Master Service Attachment)
              │ (Google Backbone Encrypted Tunnel)
              ▼
[ Zone 4: Master Project Nginx MIG 层 ]
       └─► Service Attachment ──► Master Nginx MIG (VM Fleet)
              └─► nginx.conf (域名 SNI 识别, proxy_pass 转发至 K8s Gateway VIP)
              │
              ▼
[ Zone 5: K8s Gateway + ListenerSet 层 ]
       └─► Istio / GKE Gateway (K8s Gateway VIP)
              ├─ ListenerSet A (hostname: tls.caep.uk)
              └─ ListenerSet B (hostname: mtls.caep.uk)
              │
              ▼
[ Zone 6: HTTPRoute 分叉层 (核心安全逻辑分水岭) ]
       ├─► HTTPRoute tls-team1/2/3 (parentRef: ListenerSet A, Path 匹配, 无 Header 校验)
       └─► HTTPRoute mtls-team1/2/3 (parentRef: ListenerSet B, 强制校验 SAN Header)
              │
              ▼ (6 条 Routes 汇聚)
[ Zone 7: 服务网格与租户运行时 (Tenant Runtime NS) ]
       └─► Kong Gateway (Kong DP) ──► team1/team2/team3 Runtime Services & Pods
```

---

## 各 Zone 组件职责与配置规范

### Zone 1: 外部客户端层 (External Clients)
* **`ext-mtls-client`**：持有合法 Client Cert 的客户端，访问 `https://mtls.caep.uk`。在 TLS 握手阶段向 GLB 提供客户端证书。
* **`ext-tls-client`**：普通 Web / API 客户端，访问 `https://tls.caep.uk`。仅进行标准单向 TLS 握手。

---

### Zone 2: GCP 双 GLB 入口层 (Tenant Project)
架构采用两个独立的 External Managed HTTPS Load Balancer：
1. **`mtls-GLB`**：
   * **IP / 域名**：绑定专属公网 IP_A，证书为 `mtls.caep.uk`。
   * **mTLS 配置**：开启 `Client Certificate Validation`。
   * **Header 注入**：GLB 验证客户端证书后，将客户端证书校验状态及 SAN 信息注入到 HTTP Request Header：
     * `X-Client-Cert-Chain-Verified: "true"`
     * `X-Client-Cert-DNSName-SANs: <base64(SAN)>`
   * **后端挂载**：挂载 3 个 Backend Service (`mtls-team1-bs`, `mtls-team2-bs`, `mtls-team3-bs`)，分别绑定 `cloudarmor-team1/2/3` 防护策略。
2. **`tls-GLB`**：
   * **IP / 域名**：绑定专属公网 IP_B，证书为 `tls.caep.uk`。
   * **TLS 配置**：仅做单向 TLS 终结，不请求、不校验客户端证书。
   * **后端挂载**：挂载 3 个 Backend Service (`tls-team1-bs`, `tls-team2-bs`, `tls-team3-bs`)，绑定对应的 Cloud Armor 策略。

---

### Zone 3: IDMZ 跨项目网络桥 (IDMZ VPC) ⚠️
* **`idmz-psc-neg`**：
  * **创建位置**：位于 **IDMZ VPC**（非 Tenant VPC，也非 Master VPC）。
  * **共享特性**：整个架构中仅存在 **1 个共享的 PSC NEG** 实例。Zone 2 中的全部 6 个 Backend Service (3 个 mTLS BS + 3 个 TLS BS) 统一将此 PSC NEG 作为 Endpoint 挂载。
  * **跨项目传输**：PSC NEG 连接 Master 项目中的 `Service Attachment`，流量通过 Google Backbone 内部加密隧道传输。

---

### Zone 4: Master Project Nginx MIG 层
Master 项目接收到 PSC 隧道流量后，入口为 VM-based Nginx MIG 集群：
* **`Service Attachment`**：配置租户项目的 SA / Project 允许列表。
* **`Master Nginx MIG`**：运行 Nginx 代理，`nginx.conf` 保持双 `server {}` 块处理 SNI 分流：

```nginx
# TLS 路径
server {
    listen 443 ssl;
    server_name tls.caep.uk default_server;

    ssl_certificate     /etc/nginx/certs/tls-caep-uk.crt;
    ssl_certificate_key /etc/nginx/certs/tls-caep-uk.key;

    proxy_pass https://<K8S_GW_VIP>:443;
    proxy_ssl_server_name on;
}

# mTLS 路径
server {
    listen 443 ssl;
    server_name mtls.caep.uk;

    ssl_certificate     /etc/nginx/certs/mtls-caep-uk.crt;
    ssl_certificate_key /etc/nginx/certs/mtls-caep-uk.key;

    proxy_pass https://<K8S_GW_VIP>:443;
    proxy_ssl_server_name on;
}
```

---

### Zone 5: K8s Gateway + ListenerSet 层
基于 K8s Gateway API (Istio 实现)：
* **`k8s-gateway`**：暴露统一内网 VIP (`<K8S_GW_VIP>`)。
* **`ListenerSet A`**：侦听 `hostname: tls.caep.uk`，终结内部 TLS 握手，下发流量至 TLS HTTPRoute。
* **`ListenerSet B`**：侦听 `hostname: mtls.caep.uk`，终结内部 TLS 握手，下发流量至 mTLS HTTPRoute。

---

### Zone 6: HTTPRoute 分叉层 (mTLS 与 TLS 核心差异)

此层是 mTLS 路径与 TLS 路径在业务路由层面的**唯一逻辑差异点**：

#### 1. TLS HTTPRoute (无 Header 校验)
仅根据 URL Path 进行常规路由匹配：
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: tls-team1
spec:
  parentRefs:
    - name: k8s-gateway
      sectionName: listener-tls-a
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /team1
      backendRefs:
        - name: kong-dp
          port: 443
```

#### 2. mTLS HTTPRoute (强制 SAN Header 匹配)
充分利用 Zone 2 中 GLB 终结 mTLS 时注入的 HTTP Header，在 Gateway 层进行细粒度的团队 SAN 身份鉴权：
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: mtls-team1
spec:
  parentRefs:
    - name: k8s-gateway
      sectionName: listener-mtls-b
  rules:
    - matches:
        - headers:
            - type: Exact
              name: X-Client-Cert-Chain-Verified
              value: "true"
            - type: Exact
              name: X-Client-Cert-DNSName-SANs
              value: "<team1-SAN-base64>"
          path:
            type: PathPrefix
            value: /team1
      backendRefs:
        - name: kong-dp
          port: 443
```
> 💡 **设计关键点**：由于最前端 mTLS GLB 已经完成了 Client Cert 校验并注入了 `X-Client-Cert-DNSName-SANs`，后端的 HTTPRoute 无需直接解密客户端证书，即可通过标准的 `RequestHeader` 匹配机制实现基于证书 SAN 的多租户访问控制（Mismatch 则直接拒绝）。

---

### Zone 7: 服务网格层与租户运行时 (Kong DP → Runtime)
* **`Kong DP` (Kong Data-Plane)**：
  * Zone 6 中的全部 6 个 HTTPRoute（3 个 TLS + 3 个 mTLS）统一将 `backendRef` 指向 Kong DP。
  * 所有公网 HTTPS 流量必须强制经过 Kong DP 进行统一的网关策略（限流、鉴权、日志、插件）处理。
* **`Runtime NS`**：
  * 租户业务运行在独立 Namespace 中 (`team1-runtime`, `team2-runtime`, `team3-runtime`)，由 Kong DP 根据路由规则分发至各 team 的 Service 及 Pod 实例。

---

## 图文对应与校验查验表

| 序号 | 架构层级 (Zone) | 核心组件 | 关键属性 / 配置要点 | 拓扑流向说明 |
| :--- | :--- | :--- | :--- | :--- |
| 1 | **Zone 1** | `ext-mtls-client` / `ext-tls-client` | 独立域名与 Client Cert 区分 | mTLS 走 `mtls.caep.uk`，TLS 走 `tls.caep.uk` |
| 2 | **Zone 2** | `mtls-GLB` & `tls-GLB` | 双 IP / 独立 Cert / Header 注入 / 无 Path Rule | 下挂 6 个专属 BS 绑定 Cloud Armor 策略 |
| 3 | **Zone 3** | `idmz-psc-neg` ⚠️ | **位于 IDMZ VPC**，6 个 BS 共享单个 PSC NEG | 经 PSC 隧道穿越项目边界接入 Master 项目 |
| 4 | **Zone 4** | `Master Nginx MIG` | VM Fleet，双 `server {}` 块代理 | proxy_pass 统一送入 K8s Gateway VIP |
| 5 | **Zone 5** | `K8s Gateway` | ListenerSet A (tls) / ListenerSet B (mtls) | 区分 Hostname 分发给对应的 HTTPRoute |
| 6 | **Zone 6** | `HTTPRoute` (TLS / mTLS) | mTLS 路由强制匹配 `X-Client-Cert-DNSName-SANs` | 实现 SAN 级身份鉴权，不匹配拒绝访问 |
| 7 | **Zone 7** | `Kong DP` → Runtime | 统一后端网关，隔离 Namespace 服务 | 终结链路并送达各 Team Pod |

---

## 关联文件
* **可交互矢量架构图**：[multip-tls-mtls-flow.html](file:///Users/lex/git/gcp/ingress/public-mtls-global-ingress/flow/multip-tls-mtls-flow.html)
