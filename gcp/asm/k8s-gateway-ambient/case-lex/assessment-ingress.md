# assessment-ingress.md — Ingress 流量到业务 Pod 的所有可行路径

> **作者**: architect-gcp Bot
> **日期**: 2026-09-25
> **背景**: yaml-assessment.md §Q1 提到你设计 `02-network-policies.yaml` NP-7 选 waypoint pod 作为
>         podSelector,**意图是 "ingress 流量只走 waypoint 这条路"**。
>         本文档探索**不走 waypoint 的备选实现路径**,做完整对比。
>
> **方法**: 综合 Istio 1.30 / 1.31 官方文档、Solo 1.30.x 文档、同仓库 10-waypoint-gateway-coexistence.md。

---

## 0. TL;DR

| 路径 | 是否推荐 | 主要场景 | ingress-use-waypoint label |
|---|---|---|---|
| **P1: ingress GW → 直接到业务 pod**(绕过 waypoint) | ⚠️ 默认行为 | 无 L7 拦截需求的简单 mesh | 无 |
| **P2: ingress GW → waypoint → 业务 pod** | ✅ **本场景在用** | 入口 L7 AuthZ / header 路由 / 统一访问控制 | true (ns) / waypoint (explicit) |
| **P3: ingress GW → ztunnel-only → 业务 pod**(无 waypoint, ambient L4 only) | ⭐⭐⭐ **备选最值得评估** | 只想要 mTLS 加密,不需要 L7 拦截 | 无 (但 ambient) |
| **P4: 把 ingress Gateway 本身迁 ambient**(用 kgateway/agentgateway) | ⛔ 不推荐 | 未来 1.31+ Solo agentgateway 落地 | 复杂 |
| **P5: sidecar-skip-waypoint annotation**(跨模式兼容) | ⭐ niche | 跨 sidecar/ambient 集群互通 | 无 |

**结论**: 你的 P2 设计是对的,前提是 `ENABLE_INGRESS_WAYPOINT_ROUTING=true` 已开启(详见 §4.1)。

**如果想避免 waypoint 复杂度**,**P3 (ambient L4 only) 是最干净的备选** —— 业务 ns 取消 waypoint,
ingress 直接到业务 pod,经 ztunnel mTLS 加密,不经过任何 L7 拦截。

---

## 1. 当前 P2 设计的具体流量路径

按你现在的 NS 配置 (`istio.io/ingress-use-waypoint: waypoint`) + waypoint 已 enroll:

```
┌──────────┐    ┌───────────────┐    ┌─────────────────────┐    ┌──────────────────┐
│ Internet │ →  │ GCP LB        │ →  │ Ingress GW          │ →  │ ztunnel (src)    │
│  客户端   │    │ + CloudArmor  │    │ (lex-gw-int ns,     │    │  节点 A          │
│          │    │               │    │  sidecar envoy)     │    │                  │
└──────────┘    └───────────────┘    └─────────────────────┘    └──────────────────┘
                                                                     │ HBONE tunnel
                                                                     │ (over mTLS)
                                                                     ▼
                                          ┌──────────────────────────────────────┐
                                          │ ztunnel (dst) — 业务 pod 所在节点    │
                                          │  解密后识别 "目标服务 in             │
                                          │   ba000000-lex-int, has waypoint"    │
                                          │  → 路由到 waypoint                    │
                                          └──────────────────────────────────────┘
                                             │ HBONE (15008)
                                             ▼
                                          ┌──────────────────────┐
                                          │ waypoint pod         │
                                          │ (L7 拦截: AuthZ/    │
                                          │  header/重写等)      │
                                          └──────────────────────┘
                                             │ HTTP/2 (业务端口)
                                             ▼
                                          ┌──────────────────────┐
                                          │ 业务 pod (8080)      │
                                          │ (透明收到业务请求)   │
                                          └──────────────────────┘
```

**关键事实**:
- ingress GW 自己仍在 sidecar 模式(envoy sidecar in lex-gw-int ns)
- ingress GW → 业务 pod 的链路,过**两次 ztunnel**(源节点 + 目标节点)+ 一次 waypoint
- L7 拦截只在 waypoint 执行(由 ingress-use-waypoint label 触发)

---

## 2. 备选路径分析

### P1: ingress GW → 业务 pod(绕过 waypoint)

**配置**: **不打 `istio.io/ingress-use-waypoint` label**,或不部署 waypoint。

**流量路径**:
```
Internet → GCP LB → Ingress GW (sidecar envoy) → ztunnel (src) 
  → ztunnel (dst, decrypts) → 业务 pod (8080)
```

**AuthZ 状态**: 
- 业务 pod 上的 AuthZ 不拦截 ingress 流量(因为 ingress 不经 waypoint)
- 只有业务 pod 之间的 mesh 流量才受 AuthZ 控制
- ingress GW 上自己可以挂 AuthZ(targetRef = ingress GW)

**适用场景**:
- 业务 ns 没有 L7 拦截需求(纯 mTLS 加密)
- 入口访问控制**完全在 ingress GW 那一层完成**(HTTPRoute 路由 + ingress GW 上的 AuthZ)

**不适用**:
- 业务要求入口流量也走统一的 mesh 策略(统一审计)
- 想避免 ingress GW 和业务 ns 两边维护两套 AuthZ

**评估你的场景**: 你的业务有 L7 拦截需求 → **P1 不够用**,继续用 P2。

---

### P3: ambient L4 only(推荐备选)

**配置**: 不部署 waypoint,**取消 `istio.io/use-waypoint` label**,只保留 `dataplane-mode=ambient`。

**流量路径**:
```
Internet → GCP LB → Ingress GW → ztunnel (src) → ztunnel (dst) → 业务 pod
                       (直接到业务 pod,不绕 waypoint)
```

**与 P1 的关键差异**:
- P1: ingress GW 自身侧车 envoy 处理 mTLS,然后**直连**业务 pod
- P3: ingress GW 看到目的 IP 是业务 pod,**通过 ztunnel** 走 HBONE 隧道 → ztunnel 解密后 → 业务 pod
- 业务 pod 上的 iptables **仍重定向 15008 给 ztunnel**,所以 NetPol 仍要 allow 15008

**AuthZ 状态**: 
- **完全不能挂 AuthZ**(因为没有 waypoint 拦截点)
- 入口 L7 拦截必须全部在 ingress GW 上完成
- 业务 ns 内 mesh 流量也无 L7 拦截(纯 L4 mTLS)

**适用场景**:
- **只需要 mTLS 加密,不需 L7 拦截**
- 业务间不需要 HTTP-level 控制(只信任网络层)
- 想避免 waypoint 的 HA / PDB / 维护成本

**你的场景评估**: 如果你**不需要**对入口流量做 mesh 级 AuthZ(header 路由 / JWT / IP 限制),
P3 是**最干净最简单的备选**。可以省掉:
- waypoint Deployment / Service / PDB
- 02-NP-5-netpol.yaml (ingress to waypoint)
- 02-network-policies.yaml NP-5/NP-6 (waypoint ↔ 业务 pod)
- 03-mesh-security.yaml AuthZ-2 (ingress to waypoint)

但要保留:
- 02-NP-7 (ingress to 业务 pod,绕过 waypoint)
- PA STRICT(ambient 下默认 mTLS 仍生效)
- 业务 pod 的 NetPol allow 15008

---

### P4: ingress GW 本身迁 ambient(kgateway / agentgateway)

**配置**: 
- 卸载现有 sidecar 模式 ingress GW
- 部署 kgateway (Solo) 或 agentgateway (Solo 1.30+,PILOT_ENABLE_AGENTGATEWAY=true)
- 入口流量从 LB 直接到 ztunnel,再到业务 pod / waypoint

**流量路径**:
```
Internet → LB → kgateway (ztunnel 注入) → ztunnel → waypoint → 业务 pod
```

**关键事实**(来自 Solo 1.31.x 文档):
> "kgateway does not originate HBONE. Instead, it has a ztunnel and is treated like a mesh client."
> — Solo docs

**适用场景**:
- 整个集群统一 ambient 数据面
- 想用 Solo agentgateway 的高级能力

**不适用**:
- 你目前 ingress GW 已经在 sidecar 模式跑稳定
- agentgateway 在 1.30 仍是 alpha(PILOT_ENABLE_AGENTGATEWAY=true)
- 迁移成本:ListenerSet 多租户、HTTPRoute 配置都要重审

**评估你的场景**: ⛔ **不推荐**。ListenerSet 是 sidecar 模式设计,迁 ambient 会破坏现有架构。

---

### P5: sidecar-skip-waypoint annotation

**配置**: 在 ServiceEntry 上加 `solo.io/sidecar-skip-waypoint: "true"` annotation。

**适用场景**:
- **跨 sidecar/ambient 集群互通** —— 一边是 sidecar,一边是 ambient
- 防止 sidecar proxy 把 traffic 误转到 waypoint

**你的场景**: 你 ingress GW 在 sidecar,业务 ns 在 ambient,**这是 sidecar → ambient 的标准场景**。
但 ingress GW 是 K8s Gateway API Gateway,**不是 ServiceEntry**,所以这个 annotation 不直接适用。

**间接相关**: 你的 03-mesh-security.yaml AuthZ-2 用 `targetRefs: waypoint` + `principals` 限制来源,
实质上**已经实现了 P5 的意图** —— 不让 sidecar ingress GW 误调业务 pod,而是只允许它通过 waypoint 走。

---

## 3. 路径对比矩阵

| 维度 | P1 (无 ingress-use-waypoint) | P2 (你当前设计) | P3 (ambient L4 only) | P4 (kgateway) |
|---|---|---|---|---|
| **waypoint 必要性** | 不需要 | 需要 | **不需要** | 需要 |
| **L7 拦截入口流量** | ❌ | ✅ | ❌ | ✅ |
| **L7 拦截 mesh 内** | ✅ (业务 ns 内部) | ✅ | ❌ | ✅ |
| **mTLS 入口↔业务** | ✅ (envoy sidecar mTLS) | ✅ | ✅ | ✅ |
| **复杂度** | 低 | **中** | **最低** | 高 |
| **HA 维护** | 只需 ingress GW | ingress GW + waypoint | 只需 ingress GW | kgateway + waypoint |
| **故障域** | 入口 biz 大 | 入口 + waypoint | 入口 | kgateway + waypoint |
| **多租户隔离** | ingress GW 上做 | **统一在 waypoint 上做** ⭐ | ingress GW 上做 | 统一在 waypoint |
| **NS label** | `dataplane-mode=ambient` + (可选) `use-waypoint` | + `ingress-use-waypoint=waypoint` | 仅 `dataplane-mode=ambient` | + `ingress-use-waypoint` |

---

## 4. 关键约束与陷阱(无论选哪条路径都要看)

### 4.1 `ENABLE_INGRESS_WAYPOINT_ROUTING` 必须开启

**P2 路径的前置条件**:

> "The control plane only applies this behavior when `ENABLE_INGRESS_WAYPOINT_ROUTING` is enabled
> for istiod; it defaults to false."
> — [Istio Waypoint 官方文档](https://istio.io/v1.30/docs/ambient/usage/waypoint/)

**意思是**:
- 即使你在 NS 上打了 `istio.io/ingress-use-waypoint: waypoint` label
- 如果 istiod 的 env 里 `ENABLE_INGRESS_WAYPOINT_ROUTING` 默认是 **false**
- **label 不生效**,ingress 流量还是默认绕过 waypoint
- 你的集群必须**显式开启**这个 flag

**怎么验证集群上是否开启**:

```bash
kubectl get deploy istiod -n istio-system \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_INGRESS_WAYPOINT_ROUTING")]}{"\n"}'
```

**怎么开启**(Helm values):

```yaml
# values-istiod.yaml
meshConfig:
  enableIngressWaypointRouting: true
```

或在 istiod Deployment env 里加:

```yaml
env:
  - name: ENABLE_INGRESS_WAYPOINT_ROUTING
    value: "true"
```

**影响 P2 选型**: 如果你的集群没开,你的 NP-7 / AuthZ-2 / ingress-use-waypoint label 全部不生效,
ingress 流量走 P1 默认行为,NS 的 waypoint **实际不被 ingress 调用**(只有 mesh 内东西向走)。

→ **这是你 NP-7 选 waypoint podSelector 的隐含前提**: 你**确认**集群 ENABLE_INGRESS_WAYPOINT_ROUTING 已开。

---

### 4.2 NP-7 "选 waypoint pod" 的语义

你的 NP-7:
```yaml
podSelector:
  matchLabels:
    gateway.networking.k8s.io/gateway-name: waypoint-int
ingress:
  - from:
    - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: lex-gw-int}}
      podSelector:       {matchLabels: {gateway.networking.k8s.io/gateway-name: lex-gw-int}}
    ports:
      - port: 15008
```

**语义解读**:
- podSelector 选 **waypoint pod**(被这条规则 apply 的对象)
- 允许来自 ingress GW ns 的**任何 pod** → 到 **waypoint pod 的 15008**

**问题**:
- NP-7 这条规则**只控制 waypoint 的 ingress 端口** —— 不控制业务 pod 直接被 ingress 访问
- 如果用 P1 (不打 ingress-use-waypoint label),ingress GW 的请求**直接到业务 pod 8080**,不走 waypoint
  → 业务 pod 上的 ingress 受其他规则约束(NP-8 same-namespace + istio 默认 NetworkPolicy)
- **NP-7 是 "ingress to waypoint" 的 L4 firewall,不是 "ingress to 业务 pod"**

**所以你的"只走 waypoint"的实现** = 三层防护:
1. **NS label** `ingress-use-waypoint=waypoint` → 告诉 ztunnel: ingress 流量必须经 waypoint
2. **NetPol** NP-7 → 控制 waypoint 的 15008 ingress(不控制业务 pod)
3. **AuthZ** AuthZ-2 → L7 层面强制 "ingress GW SA → waypoint"

→ 三层**互相依赖**。任何一层失效,ingress 流量可能"漏"到业务 pod 直接路径。

---

### 4.3 业务 pod 真的不会被 ingress 直接访问吗?

需要验证:**业务 pod 在不绕 waypoint 时,NetPol 是否真的挡住?**

假设某天 `ENABLE_INGRESS_WAYPOINT_ROUTING` flag 被 reset 成 false,或者 `ingress-use-waypoint` label 被打错,
ingress GW 直接 forward 到业务 pod:

| 防护层 | 是否生效 |
|---|---|
| **业务 pod ingress** | 受 02-NP-7 (现在选 waypoint,**不** apply 业务 pod) |
|  | 受 NP-8 same-namespace (业务 pod 选 `businessId=ba000000`,ingress GW 的 ns label 不匹配 → 拒绝) ✅ |
| **业务 pod 上 AuthZ** | `deny-all` + `allow-from-waypoint-to-workloads` (只 allow waypoint SA) ✅ |
| **PA STRICT** | ambient 下默认 mTLS,ingress GW 需 mesh 内 — 你的 ingress GW 是 mesh ✅ |

**结论**: 即使 `ingress-use-waypoint` label 失效,**还有 NP-8 + AuthZ 双层兜底**,ingress 流量**不会直接到业务 pod**。
这是合理的纵深防御。

**但要注意**: 
- NP-8 用 `namespaceSelector: {businessId: ba000000}`,**如果任何 ingress 路径的 namespace 被打这个 label 就会绕过**
- 建议: 把 NP-8 改成 `podSelector: {}` (精确限制本 ns),见 yaml-assessment.md §H-3

---

## 5. 建议矩阵

### 5.1 如果你坚持 P2(当前)

**确认清单**:
- [ ] istiod env 含 `ENABLE_INGRESS_WAYPOINT_ROUTING=true`
- [ ] NS 上有 `istio.io/dataplane-mode=ambient` + `istio.io/ingress-use-waypoint=waypoint` + `istio.io/use-waypoint=waypoint`
- [ ] waypoint Gateway READY=True
- [ ] ingress GW 在 mesh 内(默认是)
- [ ] NP-7 选 waypoint pod + from 限制 ingress GW ✅ (已修)
- [ ] NP-8 改成 `podSelector: {}` 更稳
- [ ] AuthZ-2 `targetRefs: waypoint` + `principals: ingress GW SA`
- [ ] AuthZ-3 allow from waypoint SA 到业务 pod

### 5.2 如果你想简化到 P3(放弃 L7 入口拦截)

**改动**:
1. **删** `istio.io/use-waypoint` 和 `istio.io/ingress-use-waypoint` 两个 label(00- 命名空间)
2. **删** 01-waypoint-int.yaml 的 waypoint Gateway(及 PDB)
3. **删** 02-NP-5-netpol.yaml(ingress-to-waypoint)
4. **改** 02-network-policies.yaml:
   - NP-5: 删 (无 waypoint)
   - NP-6: 删 (无 waypoint)
   - NP-7: podSelector 改 `{}`,不限定 from namespace
5. **删** 03-mesh-security.yaml AuthZ-2(无 waypoint 不需要 allow ingress to waypoint)
6. **改** AuthZ-3: 加 allow from ingress GW SA 到业务 pod(targetRef = 业务 Service)

**保留**:
- PA STRICT(ambient 默认 mTLS)
- AuthZ-3 deny-all + allow-from-waypoint(如果保留 waypoint)+ allow-ingress-direct

**好处**:
- 省掉 waypoint 全部运维(2 副本 + PDB + 滚动升级)
- NetPol 减半
- 入口拦截责任全部在 ingress GW 上的 HTTPRoute / AuthZ

**坏处**:
- 入口流量**没有统一 mesh 策略** —— ingress GW 上配错规则 = 安全洞
- 业务 ns 的审计覆盖不到入口流量

---

## 6. 反向 — 哪些场景会让 P2 失效

| 场景 | P2 是否能工作 | 备用 |
|---|---|---|
| `ENABLE_INGRESS_WAYPOINT_ROUTING` 误改回 false | ❌ 走 P1 | 用 NP-8 + AuthZ 兜底 |
| 业务 pod 被打 `istio.io/dataplane-mode=`(删 ambient) | ❌ ingress 流量绕 mesh | NP-7 仍允许,业务 pod 没 mTLS 兜底 |
| waypoint Deployment 全部 NotReady | ❌ 入口流量堆积 → 504 | 加 PDB minAvailable: 2 / 多副本 |
| ingress GW ns label `businessId=ba000000` 被误打 | ❌ 跨 ns 兜底失效 | NP-8 改 `podSelector: {}` |
| ingress GW SA 被改名 | ❌ AuthZ-2 不匹配 → RBAC deny | 同步改 AuthZ-2 principals |

---

## 7. 严格定义 vs 简化解释

| 概念 | 简化 | 严格来源 |
|---|---|---|
| `ENABLE_INGRESS_WAYPOINT_ROUTING` | "让 ingress 走 waypoint 的开关" | "The control plane only applies this behavior when `ENABLE_INGRESS_WAYPOINT_ROUTING` is enabled for istiod; it defaults to false." — Istio Waypoint docs |
| `istio.io/ingress-use-waypoint` | "ingress 走 waypoint label" | "Set `istio.io/ingress-use-waypoint=true` to direct ingress traffic through the same waypoint as the mesh traffic" — Istio Waypoint docs |
| `istio.io/use-waypoint` | "东西向走 waypoint" | "All in-mesh pod requests to services in that namespace traverse the waypoint for L7 processing." — Solo docs |
| waypoint 的 ServiceAccount | "waypoint-int SA" | Istio controller 1.27+ **默认用 `default` SA**(常见陷阱),不是 `waypoint-int` |

---

## 8. References

- [Istio Waypoint 1.30 官方文档](https://istio.io/v1.30/docs/ambient/usage/waypoint) — 权威流量路径
- [Istio Sidecar → Ambient Migration Guide](https://istio.io/latest/docs/ambient/install/migrate-from-sidecar/) — 迁移陷阱
- [Solo 1.30.x Waypoints](https://docs.solo.io/istio/1.30.x/ambient/waypoints/configuration) — `waypoint-for` 完整 label 矩阵
- [Solo 1.31.x kgateway](https://docs.solo.io/istio/1.31.x/resiliency/failover/components/kgateway) — kgateway 不走 HBONE
- 同仓库 `10-waypoint-gateway-coexistence.md` §1.1 — ingress 流量默认行为
- 同仓库 `19-solo-agentgateway-ambient-install.md` §6 — agentgateway / XFCC 重写
- 同仓库 `07-feature-status-1.30.3.md` §Ingress — 1.30.3 已知约束
- [K8s Gateway API spec](https://gateway-api.sigs.k8s.io/api-types/gateway/) — `allowedRoutes.from` 语义

---

*Generated by architect-gcp Bot — 路径分析基于 1.30 文档,集群具体行为需 `ENABLE_INGRESS_WAYPOINT_ROUTING` flag 验证。*