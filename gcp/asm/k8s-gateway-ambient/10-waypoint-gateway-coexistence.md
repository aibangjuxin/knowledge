# Ambient Waypoint 与 K8s Gateway API 共存 — 入口 / 出口 / 东西向路由分层

> **TL;DR**:
> - 你已有的 **K8s Gateway API Gateway**(`gatewayClassName: istio`,sidecar 模式跑 envoy)**与 ambient waypoint 共存** — 两者职责不同
> - 但有个**重要默认行为**:ingress gateway 的流量**默认绕过 waypoint**(不执行 L7 策略)
> - 要让 ingress 流量走 waypoint 必须显式 `istio.io/ingress-use-waypoint: true` 在 Service / Namespace 上
> - VirtualService **仍 Alpha** — 必须迁 `HTTPRoute`

---

## 0. 三种 Gateway / Waypoint 角色矩阵

> 来源:
> - [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/)
> - [Istio Ambient Multi-Network Multicluster](https://istio.io/latest/docs/ambient/install/multicluster/multi-primary_multi-network/)
> - [Istio Deep Dive Coexistence Blog](https://istio.io/latest/blog/2023/traffic-for-ambient-and-sidecar/)

| 资源类型 | 角色 | 数据面模式 | 跑在哪 |
|---|---|---|---|
| **Ingress Gateway**(`gatewayClassName: istio`) | **南北向**(外部 → cluster) | **sidecar 模式** | 独立 Deployment,跑 envoy |
| **Egress Gateway**(`gatewayClassName: istio`) | **南北向**(cluster → 外部) | sidecar 模式 | 同上 |
| **East-West Gateway**(`gatewayClassName: istio-east-west`) | **东西向**(cluster → cluster) | sidecar 模式 | 跨集群 mesh |
| **Waypoint**(`gatewayClassName: istio-waypoint`) | **东西向 + L7**(pod → pod) | **ambient** | 每个 ns/service 1 个 |

**关键区分**:
- 3 个 istio Gateway = **南北向入口/出口**(仍 sidecar 模式)
- waypoint = **东西向 L7 策略**(ambient 模式,1.30 才稳定)

**两者职责不重叠,自然共存**。

---

## 1. 入口 Gateway 流量默认绕过 waypoint

### 1.1 行为表

| `istio.io/use-waypoint` on Service/Namespace | `istio.io/ingress-use-waypoint` on Service/Namespace | 入口流量行为 |
|---|---|---|
| 未设 | 未设 | ingress 流量**不**走 waypoint |
| `=waypoint` | 未设 | ingress 流量**不**走 waypoint(默认) |
| `=waypoint` | `=true` | ingress 流量走 waypoint ✅ |
| 未设 | `=true` | ingress 流量走 waypoint ✅(强制) |

> 来源原文: "By default, ingress-originated traffic will not use the destination service waypoint, even when `istio.io/use-waypoint` is set on the service or namespace. To direct ingress traffic through the same waypoint as the mesh traffic, set `istio.io/ingress-use-waypoint=true` on the Kubernetes Service, or on the Namespace to apply to all services in that namespace (supported starting with Istio 1.25)." — [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/)

### 1.2 本场景的影响

> 你的 `k8s-gateway/03-gateway/abjx-gw-int.yaml` 是 **ingress Gateway**,跑 envoy (sidecar)。

切 ambient 后:
- **东西向流量**(业务 pod → 业务 pod)→ 走 waypoint,执行 L7 策略 ✅
- **南北向流量**(外部 → ingress Gateway → 业务 pod)→ **默认不**走 waypoint ⚠️

**后果**:
- 入口 Gateway 来的请求**不受** AuthorizationPolicy / RequestAuthentication 控制
- 入口 Gateway 来的请求**不受** waypoint 的 retry / timeout / fault injection 控制

### 1.3 解决方案

```yaml
# 方案 A:给整个 namespace 强制 ingress 走 waypoint
apiVersion: v1
kind: Namespace
metadata:
  name: team-a-runtime
  labels:
    istio.io/dataplane-mode: ambient
    istio.io/ingress-use-waypoint: "true"     # ← 关键
```

```yaml
# 方案 B:给特定 Service 强制(粒度更细)
apiVersion: v1
kind: Service
metadata:
  name: api-public
  namespace: team-a-runtime
  labels:
    istio.io/ingress-use-waypoint: "true"     # ← 只对 api-public 强制
```

---

## 2. ambient + sidecar 同集群共存(本场景就是混合的)

> 来源: [Istio Deep Dive: Coexistence of Ambient and Sidecar](https://istio.io/latest/blog/2023/traffic-for-ambient-and-sidecar/)

### 2.1 同集群混合目录可行性

| ns A | ns B | 跨 ns 流量行为 |
|---|---|---|
| **ambient** | **ambient** | ztunnel → ztunnel(可能经 waypoint) ✅ |
| **ambient** | **sidecar** | ztunnel → B 的 envoy ✅(需 B 是 mesh 内) |
| **sidecar** | **ambient** | A 的 envoy → ztunnel(可能经 waypoint) ✅ |
| **sidecar** | **sidecar** | envoy → envoy(原 sidecar 模式) ✅ |

**结论**:**混合部署完全可行**,Istio 官方文档明确推荐 sidecar→ambient 迁移期用这种方式。

### 2.2 本场景的具体混合

```
你的 dev 集群现状(切 ambient 前)
├─ istio-system:istiod (control plane)
├─ abjx-gw-int:1× ingress Gateway(sidecar 模式)
├─ abjx-listenerset-int:ListenerSet
└─ team-*-runtime:业务 ns(sidecar 注入)

切 ambient 后(本目录 04 文流程)
├─ istio-system:istiod + istio-cni + ztunnel (混合控制面)
├─ abjx-gw-int:ingress Gateway **仍 sidecar 模式**(继续)
├─ abjx-listenerset-int:ListenerSet (不变)
└─ team-*-runtime:业务 ns(可逐 ns 迁 ambient)
```

→ **ingress Gateway 不变**,**业务 ns 逐个迁 ambient**,**完全可逆**。

---

## 3. ingress Gateway 是否需要迁移到 ambient?

### 3.1 不迁移的理由

| 优势 | 详情 |
|---|---|
| **入口流量稳定** | sidecar ingress gateway 是 K8s Gateway API 标准做法,大量文档支持 |
| **ListenerSet 多租户** | 你已用 ListenerSet 做多租户,与 waypoint 不冲突 |
| **避免破坏** | 切 ambient 可能导致 ingress 流量中断 |
| **TLS 终止** | 入口 Gateway 做 TLS 终止是常规,waypoint 不做 TLS 终止 |

### 3.2 迁移到 ambient 的理由

| 优势 | 详情 |
|---|---|
| **统一数据面** | 集群内全是 ambient,运维更简单 |
| **资源节省** | 入口 Gateway 的 envoy 占资源,可去掉 |

**本场景推荐**:**入口 Gateway 不迁 ambient**,保持 sidecar 模式。

### 3.3 如果未来要迁入口 Gateway 到 ambient

istio 1.30 没单独的"ambient ingress Gateway" 概念。要把入口迁到 ambient,有 2 种做法:

| 做法 | 复杂度 |
|---|---|
| 用 Gloo Gateway / kgateway 等替代品 | 中(架构改动) |
| 用 `agentgateway` GatewayClass(`PILOT_ENABLE_AGENTGATEWAY=true`) | 中(Alpha,不生产) |

**目前都不推荐**。

---

## 4. 多集群 ambient 与 Gateway

### 4.1 1.30 状态

| 类型 | 状态 | 备注 |
|---|---|---|
| **Single-network multicluster ambient** | **Alpha** ⚠️ | 同 VPC / peering |
| **Multi-network multicluster ambient** | **Beta** | 跨 VPC(1.29 起 Beta,1.30 强化) |
| **East-West Gateway for ambient** | Beta | `gatewayClassName: istio-east-west`,HBONE listener on 15008 |

### 4.2 East-West Gateway 关键差异

```yaml
# ambient 用的 east-west gateway,关键差异:tls mode = Terminate (double-HBONE)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-eastwestgateway
  namespace: istio-system
  labels:
    topology.istio.io/network: "network1"
spec:
  gatewayClassName: istio-east-west
  listeners:
    - name: mesh
      port: 15008
      protocol: HBONE
      tls:
        mode: Terminate
        options:
          gateway.istio.io/tls-terminate-mode: ISTIO_MUTUAL
```

`tls-terminate-mode: ISTIO_MUTUAL` = double-HBONE(ingress ztunnel → EW GW 解密 → re-encrypt 到 egress ztunnel)。

**与传统 east-west gateway 不同**:传统是 TLS passthrough,ambient 是 Terminate + re-encrypt。

### 4.3 本场景现状

你 dev 集群是**单集群**,**目前不考虑 multicluster**。但 04 文 §5 升级策略里涉及 canary,需要 future-proof:

```bash
# 跨集群 canary 时,每个集群独立装 ambient 组件,通过 EW Gateway 联通
# 当前不必做,但 ADR 里需提及
```

---

## 5. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **`istio.io/ingress-use-waypoint`** | "ingress 流量走 waypoint" | "Set `istio.io/ingress-use-waypoint=true` to direct ingress traffic through the same waypoint as the mesh traffic; supported starting with Istio 1.25." — [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/) |
| **`gatewayClassName: istio`** | "Ingress Gateway" | Istio 默认 GatewayClass,跑在 `istio-ingressgateway` Deployment(sidecar envoy) |
| **`gatewayClassName: istio-waypoint`** | "Waypoint Gateway" | Istio waypoint GatewayClass,生成 per-ns Deployment(envoy) |
| **`gatewayClassName: istio-east-west`** | "East-West Gateway" | 跨集群 mesh 用,1.30 ambient 模式下需 double-HBONE |

---

## 6. 本场景推荐拓扑

```text
                    Internet
                       │
                       ▼
        ┌──────────────────────────────┐
        │ GCP External Load Balancer    │
        │ + Cloud Armor                 │
        └──────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │ Ingress Gateway              │  ← K8s Gateway API Gateway
        │ gatewayClassName: istio      │    sidecar 模式(沿用现有)
        │ (envoy Deployment)           │    ListenerSet 多租户
        │ abjx-gw-int namespace        │
        └──────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │ team-*-runtime ns            │  ← ambient 模式(04 文迁)
        │   istio.io/dataplane-mode=ambient
        │   istio.io/ingress-use-waypoint=true  ← 关键:让 ingress 走 waypoint
        │   waypoint (per-ns, 2 rep)  │
        │   ztunnel (per-node)        │
        │   istio-cni (per-node)      │
        │   app pods (无 sidecar)     │
        └──────────────────────────────┘
```

**关键决策**:
1. **入口 Gateway 保留 sidecar 模式**(不迁 ambient)
3. **业务 ns 迁 ambient**
4. **业务 ns 显式 `istio.io/ingress-use-waypoint=true`**,让 ingress 流量也走 waypoint

---

## 7. 反向:什么场景下不要用 waypoint

| 场景 | 推荐 |
|---|---|
| 不需要 L7 策略的纯 mTLS 集群 | 不装 waypoint,只用 ztunnel |
| 入口流量不需要 waypoint 拦截 | 不设 `ingress-use-waypoint` |
| 想保留 VirtualService L7 路由 | sidecar 模式(ambient 下 VirtualService Alpha) |
| 多集群跨网络 mesh | 走 EW Gateway,不混 waypoint |

---

## 8. References

- [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/) — ingress 流量默认行为
- [Istio Deep Dive: Coexistence](https://istio.io/latest/blog/2023/traffic-for-ambient-and-sidecar/) — ambient + sidecar 混合拓扑
- [Istio Ambient Multi-Network Multicluster](https://istio.io/latest/docs/ambient/install/multicluster/multi-primary_multi-network/) — East-West Gateway ambient 配置
- [Istio Ambient Multi-Network Blog](https://istio.io/latest/blog/2026/ambient-multinetwork-multicluster-beta/) — 1.29 Beta 起源
- 同仓库 `~/git/gcp/gateway-2.0/k8s-gateway/03-gateway/abjx-gw-int.yaml` — 你现有的 ingress Gateway
- 同仓库 `~/git/knowledge/gcp/asm/gloo/gke-ambient-waypoint.md` §5.9 — Gloo 视角的入口建议