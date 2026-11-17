# Istio 1.30 Ambient Feature 状态矩阵 — GA / Beta / Alpha 完整清单

> **TL;DR**:
> - **核心 ambient(ztunnel + waypoint 基础)**:**Stable** ✅,1.30 可生产
> - **`VirtualService` 仍 Alpha** ⚠️ — 1.30 ambient 下必须迁到 `HTTPRoute`,这是硬规则
> - **`AuthorizationPolicy` + `PeerAuthentication`**:**Stable**,大部分场景可用
> - **Multicluster ambient**:**Beta**(1.29 起),Multi-network **Beta**,但 single-network multicluster **仍 Alpha**
> - **1.30 patch(1.30.1 / 1.30.2 / 1.30.3)全是 bug 修复**,无新功能;**1.30.3 修了一个 istiod scalability bug**(`AMBIENT_SCOPED_ADDRESS_PUSHES`)
> - **生产可行性结论**:1.30.3 适合 dev / staging,**生产 Multicluster ambient 仍建议等 1.31+**

---

## 0. 文档定位

> 来源:
> - [Istio 1.30 Feature Status](https://istio.io/latest/docs/releases/feature-status/) — 权威 feature 矩阵
> - [Istio 1.30 Release Notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30/) — 1.30 GA
> - [Istio 1.30.1 Patch Notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.1)
> - [Istio 1.30.2 Patch Notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.2)
> - [Istio 1.30.3 Patch Notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.3)
> - [Istio Ambient Multi-Network Multicluster Beta Blog](https://istio.io/latest/blog/2026/ambient-multinetwork-multicluster-beta/)
> - [Solo Enterprise for Istio 1.30 Changelog](https://docs.solo.io/istio/1.30.x/reference/changelog/release-notes/)

本文是**决策型**文档,不写安装细节;只回答"**能不能上生产**"+"**什么时候该升**"。

---

## 1. 完整 Feature 矩阵(Istio 1.30)

### 1.1 Ambient 核心组件

| Feature | 状态 | 备注 |
|---|---|---|
| **ztunnel:Core** | **Stable** ✅ | 节点级 mTLS 数据面 |
| **Waypoints:Core** | **Stable** ✅ | L7 策略执行器 |
| **Waypoints:DestinationRule** | **Stable** ✅ | 负载均衡 / TLS 配置 |
| **Waypoints:VirtualService** | **Alpha** ⚠️ | **1.30 仍 Alpha**,生产别用 |
| **Waypoints:Cross-namespace usage** | **Beta** | waypoint 跨 ns 接管 |
| **Waypoints:Gateway API Stable Channel**(HTTPRoute,GRPCRoute) | **Stable** ✅ | K8s Gateway API 标准资源 |
| **Waypoints:Gateway API Experimental Channel**(TLSRoute, TCPRoute) | **Alpha** ⚠️ | 仅实验 |
| **Waypoints:WasmPlugin(WebAssembly)** | **Alpha** ⚠️ | 仅实验 |
| **AuthorizationPolicy** | **Stable** ✅ | 全场景可用 |
| **PeerAuthentication** | **Stable** ✅ | 但 DISABLE 在 ambient 下无效 |
| **RequestAuthentication** | **Beta** | JWT 验证,大部分场景可用 |
| **DNS Proxying** | **Beta** | ambient dnsCapture 必走 |
| **Dual Stack / IPv6** | **Beta** | 双栈支持 |
| **Multi-network multicluster** | **Beta** | 1.29 起 Beta |
| **Single-network multicluster** | **Alpha** ⚠️ | **仍 Alpha** |
| **Baggage based telemetry** | **Alpha** ⚠️ | 需 `AMBIENT_ENABLE_BAGGAGE` flag |

### 1.2 控制面与升级

| Feature | 状态 | 备注 |
|---|---|---|
| **Kubernetes:Envoy Installation** | Stable | |
| **Kubernetes:Istio Control Plane Installation** | Stable | |
| **Multicluster Mesh**(传统 sidecar) | Beta | |
| **External Control Plane** | Beta | |
| **In-Place Control Plane Upgrade** | Beta | 单 revision 升级 |
| **Helm Installation** | Beta | 官方推荐 Helm 拆 chart |
| **Revision Based Upgrade** | Beta | 本目录 05 文核心 |
| **Revision Tags** | Beta | `istioctl tag` 命令 |
| **Basic Configuration Resource Validation** | Beta | |
| **ClusterTrustBundle resource support** | Experimental | |
| **IPv6 Support** | Alpha | |
| **Dual Stack IPv4/IP6** | Beta | |
| **Distroless base images** | Stable | 你用 `1.30.3-distroless` ✅ |
| **Virtual Machine Integration** | Beta | |

### 1.3 Gateway & Traffic Management

| Feature | 状态 | 备注 |
|---|---|---|
| Protocols:HTTP1.1/HTTP2/gRPC/TCP | Stable | |
| Protocols:Websockets/MongoDB | Stable | |
| Traffic Control:label/content based routing | Stable | |
| Resilience:timeouts/retries/circuit breaker | Stable | |
| Gateway:Ingress/Egress for all protocols | Stable | |
| Gateway Injection | Beta | |
| TLS termination / SNI Support | Stable | |
| SNI multiple certs at ingress | Stable | |
| Locality load balancing | Beta | |
| Custom filters in Envoy | Alpha | |
| Sidecar API | Stable | |
| DNS Proxying | Beta | |
| Kubernetes Gateway APIs for ingress | Stable | |
| Kubernetes Gateway APIs for mesh | Stable | |
| Gateway Network Topology configuration | Alpha | |
| Kubernetes Gateway API Inference Extension | Beta | |
| Wildcard hosts in ServiceEntry for TLS | Alpha | |
| Kubernetes Multi-Cluster Service (MCS) Discovery | Experimental | |

---

## 2. 1.30 相对 1.29 的新增 / 变更(本场景相关)

| 改动 | 含义 | 来源 |
|---|---|---|
| **CIDR address in ServiceEntry** | ambient 下 ServiceEntry 支持 CIDR 端点,IP 段无需逐 workload 列出 | [1.30 release notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30/) |
| **XFCC synthesis at waypoints** | waypoint 可选合成 `x-forwarded-client-cert`,带 `ambient.istio.io/xfcc-include-client-identity: "true"` annotation | 同上 |
| **Configurable HBONE window sizing** | `PILOT_HBONE_INITIAL_STREAM_WINDOW_SIZE` / `CONNECTION_WINDOW_SIZE` 调高吞吐 | 同上 |
| **Tokio runtime metrics in ztunnel** | ztunnel 暴露 tokio runtime metrics,看每个 ztunnel 实例资源 | 同上 |
| **New sidecar-to-ambient migration guide** | 官方提供 step-by-step 迁移指南,**明确说"sidecar 和 ambient 可共存"** | 同上 |
| **WaypointBound status on WorkloadEntry** | WorkloadEntry 报告是否已绑 waypoint | 同上 |
| **dnsPolicy / dnsConfig on ztunnel chart** | 非标准 DNS 环境配置 | 同上 |
| **useAppArmorAnnotation on istio-cni chart** | AppArmor 集成,默认 true | 同上 |
| **TLSRoute 正式 GA**(不需 feature flag) | 1.30 起 TLSRoute 不再需要 `PILOT_ENABLE_ALPHA_GATEWAY_API=true` | 同上 |
| **Multi-network multicluster 改进** | 1.29 引入 Beta,1.30 继续强化遥测 / 连接性 | [Multi-Network Blog](https://istio.io/latest/blog/2026/ambient-multinetwork-multicluster-beta/) |
| **agentgateway 实验性支持** | `PILOT_ENABLE_AGENTGATEWAY=true` 启用 `istio-agentgateway` GatewayClass,**仅 AI/MCP 工作负载** | [1.30 release notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30/) |

### 1.30 Patch 修的关键 Bug

| Patch | 修复 | 严重度 |
|---|---|---|
| **1.30.1** | Multi-network ambient 下 ingress 到对端 waypoint 不通的 bug | 🟠 中(影响多集群部署) |
| **1.30.1** | istio-cni agent 并发 map write panic(同节点同时加 2 个 pod 时) | 🔴 高(crash) |
| **1.30.1** | `consistentHash` + endpoint 更新后 ring 不重建(envoy regression) | 🟡 中 |
| **1.30.1** | `publishNotReadyAddresses` + traffic distribution 预设导致 ztunnel 把流量发给 not-ready 端点 | 🟠 中 |
| **1.30.2** | (未公开细节,主要为 robustness 修复) | - |
| **1.30.3** | `EXIT_ON_ZERO_ACTIVE_CONNECTIONS` 在 ambient ingress gateway 不触发 | 🟡 低 |
| **1.30.3** | istiod scalability 改进:XDS scoped push from Address changes(`AMBIENT_SCOPED_ADDRESS_PUSHES`,默认开启) | 🟢 正向 |
| **1.30.3** | 新增 `PILOT_NODE_UNTAINT_CONTROLLERS_TAINT_NAME`,默认 `cni.istio.io/not-ready` | 🟢 正向 |

**`AMBIENT_SCOPED_ADDRESS_PUSHES` 是 1.30.3 最重要的改进**:
> "Improved istiod scalability in ambient mode by scoping XDS pushes from workload/service Address changes to only the affected waypoints, instead of pushing to all waypoints and proxies."
>
> — [1.30.3 release notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.3)

直白说:**1.30.0 → 1.30.3 升完后,大规模 ambient 集群(>100 waypoint)的 istiod CPU 下降明显**。这是 dev 集群感知不到的改进,**生产规模才感知**。

---

## 3. 本场景使用 1.30.3 的可行性结论

### 3.1 dev 集群(当前 dev-lon-cluster-xxxxxx)

| 需求 | 可行性 |
|---|---|
| 单集群 ambient | ✅ **完全可行**(Stable 全覆盖) |
| Helm 拆分安装 | ✅ **可行**(Helm installation Beta 已稳) |
| 双 revision canary 升级 | ✅ **可行**(Revision Based Upgrade Beta) |
| per-namespace waypoint | ✅ **完全可行**(Stable) |
| per-service waypoint | ✅ **完全可行**(Stable) |
| AuthorizationPolicy / PeerAuthentication | ✅ **完全可行**(Stable) |
| NetworkPolicy + ambient 协同 | ✅ **可行**(15008 端口必须显式 allow,见 08 文) |
| RequestAuthentication(JWT) | ✅ **可行**(Beta,生产足够) |
| **VirtualService L7 路由** | ❌ **不可行 — 仍 Alpha** |
| **HTTPRoute L7 路由** | ✅ **推荐做法**(本场景硬推荐) |
| Multicluster ambient | ⚠️ **不可行**(Multi-network Beta,但 Single-network 仍 Alpha) |

### 3.2 生产集群(未来)

| 需求 | 推荐版本 |
|---|---|
| 单集群 ambient | **1.30.3 OK**(但关注 1.31,会有新 feature) |
| 多集群 ambient(单网络) | ⚠️ **等 1.31+**(Alpha 不上生产) |
| 多网络 ambient | ⚠️ **谨慎**(Beta,1.29 才 Beta,需充分测试) |
| Agentgateway / AI workload | ❌ **等 1.32+**(Alpha,不生产) |

### 3.3 何时升级 1.30.3 → 1.31+

- **现在别急升 1.31**(刚出,bug 多)
- **1.31.3 / 1.31.4 时考虑**(patch release 后 1-2 个月)
- 关注 [Istio 1.31 release notes](https://istio.io/latest/news/releases/1.31.x/announcing-1.31/) 看 feature 进度

---

## 4. 1.30 已知会"咬人"的边界

| 边界 | 详情 |
|---|---|
| **L7 策略 zero-downtime 迁移不支持** | "Zero-downtime migration with L7 policies is **not currently supported**. Plan a maintenance window." — [Istio Sidecar to Ambient migration guide](https://istio.io/latest/docs/ambient/install/migrate-from-sidecar/) |
| **selector → targetRefs 需手工迁移** | "Policies enforced by a waypoint must use `targetRefs` pointing to a Service or Gateway, not a pod selector. You cannot reuse selector based L7 policies as is." — 同上 |
| **ingress 流量默认绕过 waypoint** | "By default, ingress-originated traffic will not use the destination service waypoint, even when `istio.io/use-waypoint` is set on the service or namespace. To direct ingress traffic through the same waypoint as the mesh traffic, set `istio.io/ingress-use-waypoint=true`." — [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/) |
| **PeerAuthentication DISABLE 不支持** | "Any PeerAuthentication with mode: DISABLE must be removed or changed before migration, as ambient mode always enforces mTLS between mesh workloads." — Migration guide |
| **STRICT/PERMISSIVE 迁移后变冗余** | "PeerAuthentication with mode STRICT or PERMISSIVE are not blockers, but become redundant after migration: ambient mode enforces mTLS via ztunnel regardless. You can safely remove them after migration." — Migration guide |
| **DNS Capture 开启需 CNI 正确配置** | `ambient.dnsCapture=true` 是 helm value,但运行时需 CNI 正确插入规则 |
| **Multicluster ambient 多网络仍 Beta** | "We welcome your bug reports ... remember this feature is in beta status and not ready for production use." — [Ambient Multi-Network Blog](https://istio.io/latest/blog/2026/ambient-multinetwork-multicluster-beta/) |

---

## 5. Solo 企业版 vs 上游 Istio 1.30 差异(仅参考)

> Solo 在 1.30 加了一堆 alpha 企业 feature,本场景不直接相关,但值得知道存在:

| Solo Enterprise Feature | 状态 | 用途 |
|---|---|---|
| **L4 ztunnel-native egress** | Alpha | ztunnel 内置 L4 egress 策略,无需独立 proxy |
| **agentgateway as waypoint** | Alpha | 用 agentgateway 替代 envoy 跑 waypoint(AI workload) |
| **EC2 ambient mesh integration** | Alpha | EC2 VM 加入 ambient mesh(`istioctl ec2 add-workload`) |
| **VM workload 多实例** | Alpha | 单 VM 跑多 workload,共享 ztunnel |
| **CEL-based authorization** | Alpha | `EnterpriseAgentgatewayPolicy` 用 CEL 表达式 |
| **Workload Identity Tokens(WIMSE)** | Alpha | 跨信任边界传 SPIFFE token |
| **Solo UI** | Alpha | 新 mesh 管理 UI(替代旧 UI) |

> ⚠️ 本场景用的是上游 Istio 1.30.3,**不是 Solo Enterprise 分发**。这些 Solo feature 与本目录文档无关。
> Solo feature 在: [Solo 1.30 release notes](https://docs.solo.io/istio/1.30.x/reference/changelog/release-notes/)

---

## 6. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **Stable** | 生产可用 | "Dependable, production hardened." — [Istio Feature Status](https://istio.io/latest/docs/releases/feature-status/) |
| **Beta** | 可生产但有限制 | "Used to vet a solution in production without committing to it in the long term, to assess its viability, performance, usability, etc. Targeted at all users." — 同上 |
| **Alpha** | 不生产 | "Used to get feedback on a design or feature. Targeted at developers and expert users." — 同上 |
| **Experimental** | 早期实验 | "Feature is under active development and user facing APIs may change. Users should deploy experimental features with extreme caution." — 同上 |
| **Feature Status vs Version Status** | 两回事 | Feature Status 是 feature 自身的成熟度;Version Status 是版本(如 1.30)整体的稳定度。一个 1.30 版本里可以同时有 Stable / Beta / Alpha 多个 feature。 |

---

## 7. 给你的下一步建议

| 时间窗口 | 动作 |
|---|---|
| **现在** | 用 1.30.3 跑 dev 集群 ambient(02-04 文),**单集群** |
| **1-2 个月后** | 关注 [Istio 1.31 release notes](https://istio.io/latest/news/releases/1.31.x/),看是否有 ambient 改进 |
| **生产前** | 重新评估 1.30.x patch 版本,优先选 latest patch(目前是 1.30.3) |
| **多集群时** | 等 1.31+ / 1.32+,Multi-network ambient 才"可生产" |
| **agentgateway / AI workload** | 不在本目录范围,等 Solo 企业版或 Istio 上游到 Beta |

---

## 8. References

- [Istio 1.30 Feature Status(权威矩阵)](https://istio.io/latest/docs/releases/feature-status/) — 本文表格全部来源
- [Istio 1.30.0 Release Announcement](https://istio.io/latest/news/releases/1.30.x/announcing-1.30/)
- [Istio 1.30 Change Notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30/change-notes)
- [Istio 1.30.1 Patch Notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.1)
- [Istio 1.30.3 Patch Notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.3)
- [Istio Sidecar → Ambient Migration](https://istio.io/latest/docs/ambient/install/migrate-from-sidecar/) — 官方迁移指南
- [Istio Ambient Multi-Network Multicluster Beta Blog](https://istio.io/latest/blog/2026/ambient-multinetwork-multicluster-beta/)
- [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/) — ingress traffic 默认绕过 waypoint 的来源
- [Solo Enterprise for Istio 1.30](https://docs.solo.io/istio/1.30.x/reference/changelog/release-notes/) — Solo 分发