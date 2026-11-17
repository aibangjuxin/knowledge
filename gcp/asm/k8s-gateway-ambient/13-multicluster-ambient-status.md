# Multicluster Ambient Mesh — 1.30 现状与生产可用性评估

> **TL;DR**:
> - **Single-network multicluster ambient**:**Alpha** ⚠️,1.30 不可生产
> - **Multi-network multicluster ambient**:**Beta**,1.29 起 Beta,1.30 强化遥测,**"not ready for production use"** 是官方原话
> - **east-west gateway 在 ambient 模式下用 double-HBONE**(与传统 sidecar 的 TLS passthrough 不同)
> - **本场景 dev 集群是单集群,multicluster 不在范围内**;本文作为**未来扩展的知识储备**

---

## 0. 状态总览(1.30)

| 类型 | 状态 | 1.30 起变化 | 生产可用性 |
|---|---|---|---|
| **Single-network multicluster ambient** | **Alpha** ⚠️ | 1.30 持续 Alpha | ❌ 不可生产 |
| **Multi-network multicluster ambient** | **Beta** | 1.29 Beta → 1.30 强化 | ⚠️ 谨慎(官方说"not ready for production") |
| **传统 sidecar multicluster** | **Beta** | 长期 Beta | ✅ 多年生产稳定 |
| **East-West Gateway for ambient** | Beta | 1.30 支持 double-HBONE | ⚠️ 与 ambient 同状态 |

> 来源:[Istio Ambient Multi-Network Multicluster Blog](https://istio.io/latest/blog/2026/ambient-multinetwork-multicluster-beta/) — "Remember, this feature is in beta status and not ready for production use."

---

## 1. multicluster ambient 的关键差异

### 1.1 拓扑

```
┌─────────────────────────────────────────────────────────────────┐
│                  Multi-Network Multicluster                     │
│                                                                 │
│  Cluster 1 (network1, GCP project A)         Cluster 2 (network2, project B)
│  ┌───────────────────────────────┐          ┌───────────────────────────────┐
│  │  ambient 组件                 │          │  ambient 组件                 │
│  │  - istiod                    │          │  - istiod                    │
│  │  - istio-cni                 │          │  - istio-cni                 │
│  │  - ztunnel                   │          │  - ztunnel                   │
│  │  - waypoint                  │          │  - waypoint                  │
│  │                               │          │                              │
│  │  East-West Gateway            │          │  East-West Gateway            │
│  │  (double-HBONE Terminate)    │◄────────►│  (double-HBONE Terminate)    │
│  │  gatewayClassName:           │  LB ↔ LB │  gatewayClassName:           │
│  │  istio-east-west             │          │  istio-east-west             │
│  └───────────────────────────────┘          └───────────────────────────────┘
│                                                                 │
│  mesh ID: my-mesh (两集群共享)                                       │
│  cluster name: c1                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 East-West Gateway 关键差异

```yaml
# ambient east-west gateway(与传统 sidecar 不同!)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-eastwestgateway
  namespace: istio-system
  labels:
    topology.istio.io/network: "network1"   # ← 标记网络
spec:
  gatewayClassName: istio-east-west
  listeners:
    - name: mesh
      port: 15008                            # ← HBONE 端口
      protocol: HBONE
      tls:
        mode: Terminate                      # ← 关键:Terminate 而非 Passthrough
        options:
          gateway.istio.io/tls-terminate-mode: ISTIO_MUTUAL  # ← double-HBONE
```

**关键**:
- **传统 sidecar** east-west gateway = TLS passthrough(envoy 之间直传)
- **ambient** east-west gateway = Terminate + re-encrypt(双 HBONE:ingress ztunnel → EW GW 解密 → re-encrypt 到 egress ztunnel)
- **依赖**:HBONE baggage headers(1.30 用 `AMBIENT_ENABLE_BAGGAGE=true` flag 启用)传递 peer metadata

### 1.3 istiod 部署差异

```yaml
# multi-network 多集群:每个集群独立装 istiod + ambient
# 需设置环境变量开启 multi-network 模式

apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: ambient
  components:
    pilot:
      k8s:
        env:
          - name: AMBIENT_ENABLE_MULTI_NETWORK
            value: "true"                    # ← 多网络 mode
          - name: AMBIENT_ENABLE_BAGGAGE
            value: "true"                    # ← baggage headers(传 peer metadata)
  values:
    global:
      meshID: my-mesh
      multiCluster:
        clusterName: cluster1
        network: network1
```

**每个集群都需要**:
- 独立装 ambient 组件
- 设置 `AMBIENT_ENABLE_MULTI_NETWORK=true`
- 设置 `meshID` 一致
- 设置 `multiCluster.clusterName` 唯一
- 设置 `multiCluster.network` 唯一

---

## 2. 1.30 的改进

### 2.1 1.29 → 1.30 的具体改动

| 改动 | 来源 |
|---|---|
| **HBONE baggage headers 增强** | "HBONE protocol is now enriched with baggage headers, allowing waypoint and ztunnel to exchange peer information transparently through east-west gateways." — [1.29→1.30 blog](https://istio.io/latest/blog/2026/ambient-multinetwork-multicluster-beta/) |
| **Ingress gateways & waypoint 直接路由到远端集群** | "Ingress gateways and waypoint proxies can now route requests directly to remote clusters." — 同上 |
| **1.30.1 patch:multi-network ambient 路由 bug 修复** | "Fixed an issue where multi-network ambient did not route to the waypoint when the ingress on one network called a service on a different network, even when the Service was configured with `istio.io/ingress-use-waypoint`." — [1.30.1 patch notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.1) |
| **Tokio metrics in ztunnel** | 1.30 改进 ztunnel 可观测性,多集群下排查更容易 |

### 2.2 仍存在的限制

| 限制 | 影响 |
|---|---|
| **Single-network multicluster 仍 Alpha** | 同 VPC / peering 的多集群 ambient 不稳定 |
| **East-West Gateway 端点偏好** | "The east-west gateway may give preference to a specific endpoint during a certain time span. This may have some impact on how load from requests coming from a different network is distributed between endpoints." — [blog](https://istio.io/latest/blog/2026/ambient-multinetwork-multicluster-beta/) |
| **Baggage headers 需 flag 启用** | `AMBIENT_ENABLE_BAGGAGE=true`,默认 off |

---

## 3. 本场景的状态

**dev 集群是单集群,不涉及 multicluster**。但本文作为**未来扩展**的参考:

| 未来场景 | 推荐 |
|---|---|
| dev 集群保持单集群 | ✅ 不动 multicluster |
| dev 集群加 staging 集群(同 VPC) | ⚠️ 等 1.31+ / 1.32+,Single-network multicluster ambient 才稳定 |
| dev + staging 跨 VPC 联邦 | ⚠️ 等 Istio 官方说 "ready for production",**目前不可生产** |
| 生产 + 多区域容灾 | ❌ 用传统 sidecar multicluster(Beta 多年稳定) |

---

## 4. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **multi-network multicluster** | 跨 VPC 多集群 mesh | "Istio mesh spanning multiple clusters across different networks (e.g., different VPCs or cloud providers), with east-west gateways handling cross-cluster traffic." — Istio docs |
| **single-network multicluster** | 同 VPC 多集群 mesh | "Istio mesh spanning multiple clusters within the same network (e.g., peered VPCs), with direct pod-to-pod connectivity across clusters." — Istio docs |
| **double-HBONE** | 双向 HBONE 隧道 | "EW gateway receives HBONE traffic, terminates the mTLS session, then re-encrypts with HBONE to forward to the egress cluster's ztunnel." — [Istio ambient multi-network docs](https://istio.io/latest/docs/ambient/install/multicluster/multi-primary_multi-network/) |
| **mesh ID** | "mesh 标识" | "A mesh ID is a unique identifier for the mesh; all clusters sharing the same mesh ID are part of the same logical mesh." — Istio docs |

---

## 5. 反向:什么时候用 multicluster ambient

| 场景 | 推荐 |
|---|---|
| 单集群 | 不涉及 multicluster |
| 多集群但同 VPC | 等 single-network ambient GA(1.31+?) |
| 多集群跨 VPC | 等 multi-network ambient GA(1.31+?) |
| 强需求 multicluster mesh | 用传统 sidecar 多集群(Beta,生产可用) |

---

## 6. 监控与诊断

### 6.1 multi-network ambient 的关键 metric

```bash
# 1. EW Gateway 健康
kubectl get svc -n istio-system istio-eastwestgateway
# 应有 EXTERNAL-IP

# 2. ztunnel 是否捕获跨集群流量
kubectl logs ds/ztunnel -n istio-system | grep -E "cross-cluster|remote"

# 3. waypoint 是否看到远端流量
kubectl logs -n team-a-runtime -l app.kubernetes.io/name=waypoint | \
  grep -E "remote.*spiffe|cross-cluster"
```

### 6.2 故障排查命令

```bash
# 检查 ambient multi-network 是否启用
kubectl exec -n istio-system deploy/istiod -- \
  printenv | grep -E "AMBIENT|MULTI"

# 检查 baggage 是否开启
kubectl exec -n istio-system deploy/istiod -- \
  printenv AMBIENT_ENABLE_BAGGAGE
# 期望:true

# 检查跨集群 SPIFFE 信任
istioctl proxy-config secret <pod> -n <ns> | grep spiffe
```

---

## 7. References

- [Istio Ambient Multi-Network Multicluster Blog (1.29 起 Beta)](https://istio.io/latest/blog/2026/ambient-multinetwork-multicluster-beta/)
- [Istio Ambient Multi-Network Install](https://istio.io/latest/docs/ambient/install/multicluster/multi-primary_multi-network/)
- [Istio 1.30.1 Patch Notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.1) — multi-network 路由 bug fix
- [Istio 1.30 Feature Status](https://istio.io/latest/docs/releases/feature-status/) — Single-network ambient 仍 Alpha
- [Istio Multicluster Install](https://istio.io/latest/docs/setup/install/multicluster/) — 传统 sidecar multicluster(对比)
- [Istio HBONE](https://istio.io/latest/docs/ambient/architecture/hbone/) — HBONE 协议细节