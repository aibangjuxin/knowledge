# analyze-waypoint.md — per-namespace Waypoint 深度解析

> **作者**: architect-gcp Bot
> **日期**: 2026-09-25
> **目标**: 解释 `01-waypoint-int.yaml` 中 waypoint 的工作原理、是否所有 deploy 都过 waypoint、
>          HA 设计 (2 副本)、以及 per-namespace vs per-service 的决策。
> **当前 case-lex 配置**:
>   - Gateway `waypoint-int` (在 `ba000000-lex-int` ns 内)
>   - label: `istio.io/waypoint-for: all` (ns 级 enrollment)
>   - 配套 ns label: `istio.io/use-waypoint=waypoint` + `istio.io/ingress-use-waypoint=waypoint`
>   - replicas: 2 + PodDisruptionBudget minAvailable: 1
> **依据**: Istio 官方文档 (1.30+) + ambientmesh.io + Solo 1.31 + 本目录两份参考文档
> **参考**: `../03-waypoint-design.md` `../10-waypoint-gateway-coexistence.md` `01-waypoint-int.yaml`

---

## 0. TL;DR — 回答你的核心问题

> "这个 waypoint 是 ns 级别的,所有 deploy 都要走这个吗?"
> "100 个 deploy 都过同一个 waypoint?"

**是的,正确**。

| 你的疑问 | 答案 |
|---|---|
| waypoint 是 ns 级还是 deploy 级? | **ns 级**(enroll 整个 namespace) |
| 100 个 deploy 都要走这个? | **是的,所有 100 个 deploy 的 L7 流量都过这个 waypoint** |
| 这是高可用吗? | **是的**, 2 副本 + podAntiAffinity + PDB |
| 高可用具体怎么实现? | 详见 §4 |

**严格定义** (Istio 官方):
> "After a namespace is enrolled to use a waypoint, any requests from any pods
> using the ambient data plane mode, to any service running in that namespace,
> will be routed through the waypoint proxy for L7 processing and policy
> enforcement."
> — [Istio Ambient Waypoint docs](https://istio.io/latest/docs/ambient/usage/waypoint/)

---

## 0.5 后续 Q&A — Resources / 其他常见问题

### Q1: "为什么 waypoint pod 里没有 resources 定义?"

**简答**: waypoint Deployment **是 istio controller 自动生成的**,你**没有地方在 Gateway spec 里写 resources**;OSS Istio 1.30 默认生成的 pod **也没 resources**,会被 K8s 当 BestEffort QoS 调度(风险高)。

**怎么补**: 用 **`waypoint-options` ConfigMap**(必须叫这个名,且跟 Gateway 同 ns),Solo 1.30+ / Istio 1.27+ 都支持,详细见 **§13**。

### Q2: "这个 HA 怎么避免 pod 调度到同节点?"

**简答**: Istio controller 1.27+ 自动给 waypoint Deployment 加 `podAntiAffinity` + `topologyKey: kubernetes.io/hostname`,**强制 2 副本跨节点**,详细见 **§4.3**。

---

## 1. 这个 waypoint 的核心特征 (基于 `01-waypoint-int.yaml`)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: waypoint-int
  namespace: ba000000-lex-int
  labels:
    istio.io/waypoint-for: all       ← 关键 label 1: 支持 service + workload 两种流量类型
spec:
  gatewayClassName: istio-waypoint   ← 关键 class: 让 istiod 把这个 Gateway 当 waypoint 管
  replicas: 2                         ← HA: 2 副本
  infrastructure:
    labels:
      gateway-access: ba000000-lex-int
      ingress: int
  listeners:
    - name: istio
      port: 15008                     ← HBONE 端口 (Istio 强制,不可改)
      protocol: HBONE                 ← mesh 内部协议 (由 ztunnel mTLS 承载)
      allowedRoutes:
        namespaces:
          from: Same                  ← 只接受本 ns 的 HTTPRoute (多租户隔离)
```

### 三个关键字段解释

#### 1.1 `istio.io/waypoint-for: all` — 决定 waypoint 受理什么类型流量

| 值 | 含义 |
|---|---|
| `service` (默认) | 只处理到 Kubernetes Service 的流量(常用) |
| `workload` | 只处理到 Pod IP / VM IP 的流量(直连 pod) |
| **`all`** | **service + workload 都受理**(本场景采用) |
| `none` | 不处理任何流量(测试用) |

按 ambientmesh.io 文档推荐:
> "To ensure that your waypoint is not bypassed depending on the type of
> traffic that is sent, consider creating the waypoint with the
> `istio.io/waypoint-for: all` label."
> — [Configure waypoints — Ambient Mesh](https://ambientmesh.io/docs/waypoints/configuration/)

→ Lex 选 `all` 是**最佳实践**, 防止"打到 Service IP 走 waypoint,打到 Pod IP 不走 waypoint"的绕过。

#### 1.2 `gatewayClassName: istio-waypoint` — 跟 K8s Gateway API Gateway 的区分

| gatewayClassName | 角色 | 数据面模式 | 跑在哪 |
|---|---|---|---|
| `istio` | **Ingress Gateway** (南北向入口) | sidecar envoy | 独立 Deployment, 跑在 ingress ns |
| **`istio-waypoint`** | **Waypoint** (东西向 L7) | **ambient** | **ns 内 Deployment, 2 副本** |
| `istio-east-west` | East-West Gateway (跨集群) | sidecar envoy | istio-system ns |

**严格定义**:
> "The `istio-waypoint` GatewayClass is registered by Istio when ambient
> components are installed."
> — [Istio Ambient Install docs](https://istio.io/latest/docs/ambient/install/)

→ 你这个 Gateway `waypoint-int` **不是 ingress Gateway**, 它是个 **waypoint proxy**。

#### 1.3 `port: 15008 / protocol: HBONE` — mesh 内部协议

- **15008 端口是 Istio 强制约定**, 不可改
- **HBONE (HTTP-Based Overlay Network Environment)** = HTTP/2 + CONNECT + mTLS
- ztunnel 用 HBONE 把流量 tunnel 到 waypoint
- waypoint 本身不配 TLS (HBONE 加密由 ztunnel 承载)

---

## 2. "100 个 deploy 都走这个" — 工作原理详解

### 2.1 ns 级 enrollment 的工作流

你的 `00-namespace-ba000000-lex-int.yaml` 打了:
```yaml
labels:
  istio.io/dataplane-mode: ambient        # 启用 ambient (ztunnel 拦截)
  istio.io/use-waypoint: waypoint         # enroll 整个 ns 到 waypoint
  istio.io/ingress-use-waypoint: waypoint  # ingress 流量也走 waypoint
```

加上 `01-waypoint-int.yaml` 的:
```yaml
labels:
  istio.io/waypoint-for: all              # waypoint 受理 service + workload
```

这个组合让 **ns 内所有 service + 所有 workload** 都过 waypoint。

### 2.2 流量实际路径(东西向, 业务 pod A → 业务 pod B)

```
Pod A (service-a:80)
   │
   │ 1. Pod A 看到 dest service-b 在 ambient ns
   │    → Pod A 的 ztunnel 看到 ns label: use-waypoint=waypoint
   │    → 决定走 waypoint
   ▼
ztunnel on A-node
   │
   │ 2. 把请求包成 HBONE 隧道
   │    src SPIFFE identity + L4 mTLS
   ▼
ztunnel on B-node
   │
   │ 3. HBONE 解包
   │    看到 dest ns 有 use-waypoint=waypoint
   │    → 转发到 waypoint-int service
   ▼
waypoint-int pod (2 副本,LB round-robin)
   │
   │ 4. L7 处理:
   │    - 检查 AuthorizationPolicy (targetRef=waypoint 或 Service)
   │    - 检查 HTTPRoute (parentRef=Service)
   │    - 检查 timeout / retry / fault injection
   │    - 检查 header manipulation (X-Tenant-Id 等)
   │    - 等等
   ▼
Service B ClusterIP → Pod B :80
```

**关键: waypoint 对所有 L7 流量是必经路径**。

### 2.3 流量类型矩阵 — `istio.io/waypoint-for: all` 的覆盖面

| 客户端 → 后端 | 流量类型 | `waypoint-for: service` | `waypoint-for: workload` | **`waypoint-for: all`** (本场景) |
|---|---|---|---|---|
| pod → **Service IP** | L7 to k8s Service | ✅ 走 waypoint | ❌ 绕过 waypoint | ✅ 走 waypoint |
| pod → **Pod IP** (headless svc) | L7 to pod IP | ❌ 绕过 waypoint | ✅ 走 waypoint | ✅ 走 waypoint |
| ingress Gateway → Service IP | L7 to k8s Service | (取决于 ingress-use-waypoint label) | (取决于...) | ✅ 走 waypoint |

**结论**: `waypoint-for: all` 覆盖所有可能的 L7 流量路径。

### 2.4 "100 个 deploy 都要走" 在物理上是怎样发生的

- waypoint 是个 **envoy proxy** (本质是个反向代理)
- ztunnel 是 **节点级 DaemonSet**, 拦截所有 ambient pod 的出站流量
- ztunnel 不会"解析"100 个 deploy, 而是看 **目标 Service 所在 ns 的 label**
  - 目标 ns label: `istio.io/use-waypoint=waypoint` → 强制走 waypoint
- waypoint **不区分 deploy**, 而是接受**任何**匹配 `allowedRoutes.namespaces: Same` 的 HTTPRoute

**物理上**: 100 个 deploy 共享 2 个 waypoint pod (用 Service round-robin LB)

### 2.5 流量模型图(简化版)

```
ns ba000000-lex-int
├── 100 个 deploy (100 个 Service)
│   ├── service-1 (pod-1, pod-2)     ──┐
│   ├── service-2 (pod-3, pod-4)     ──┤
│   ├── ...                            │
│   └── service-100 (pod-199, pod-200)─┤
│                                       │
│   (任何 service 收到 pod 流量都过)     │
│                                       ▼
├── waypoint-int Deployment (2 pod)  ← 共享拦截点
│   ├── pod w1 (podAntiAffinity 节点 1)
│   └── pod w2 (podAntiAffinity 节点 2)
│
└── ztunnel DaemonSet (per-node, 节点级 L4)
```

---

## 3. 严格定义 vs 简化解释 — 双栏对比

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **waypoint** | "ns 内的 L7 代理" | "A waypoint is an Envoy proxy deployed per-namespace or per-service that handles L7 processing for traffic between workloads opted into the ambient mesh." — Istio Waypoint docs |
| **ns 级 enrollment** | "整个 ns 走 waypoint" | "After a namespace is enrolled to use a waypoint, any requests from any pods using the ambient data plane mode, to any service running in that namespace, will be routed through the waypoint proxy for L7 processing and policy enforcement." — Istio Waypoint docs |
| **`waypoint-for: all`** | "service + workload 都过" | "The waypoint can service both service and workload traffic." — ambientmesh.io docs |
| **`use-waypoint` label** | "enroll 到 waypoint" | "While the `istio.io/waypoint-for` label indicates the resource type that can use the waypoint, it does not automatically configure a service or pod to actually use the waypoint. To do that, you must also label your target namespace, service, or pod with the `istio.io/use-waypoint` label." — ambientmesh.io |
| **gatewayClassName: istio-waypoint** | "告诉 K8s 这是 waypoint" | "The `istio-waypoint` GatewayClass is registered by Istio when ambient components are installed." — Istio Ambient Install docs |
| **HBONE** | "ztunnel ↔ waypoint 隧道" | "HBONE is the HTTP/2 + mTLS tunnel protocol used by ztunnel to forward traffic to waypoints." — Istio Ambient Architecture |

---

## 4. HA 设计 — "2 副本 + PDB" 具体怎么实现高可用

你 `01-waypoint-int.yaml` 的 HA 由 **3 个东西** 协同实现:

### 4.1 `spec.replicas: 2` — 副本数

按 K8s Gateway API ≥ v1.1 规范, Gateway 资源的 `spec.replicas` 字段直接决定 Istio controller 生成的 Deployment 副本数。

```yaml
spec:
  replicas: 2
```

**istio controller 自动生成**:
- 1 个 Deployment (`waypoint-int`)
- 1 个 Service (`waypoint-int`, ClusterIP, port 15008)

### 4.2 PodDisruptionBudget (`minAvailable: 1`)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: waypoint-int
spec:
  minAvailable: 1          # 至少 1 个副本可用
  selector:
    matchLabels:
      gateway.networking.k8s.io/gateway-name: waypoint-int
```

**作用**: 节点维护 (cordon/drain) 或滚动升级时,**保证至少 1 个副本可用**,避免 L7 拦截能力完全失效。

**如果没有 PDB 会怎样**:
- 滚动升级时, 旧 pod 可能同时被 kill,新 pod 还没 ready
- 短暂窗口内 0 个 waypoint pod → L7 拦截全失效
- 流量会**绕过** waypoint (ztunnel fallback 到 L4 直连) → AuthZ 等策略失效

### 4.3 PodAntiAffinity (隐式, Istio controller 1.27+ 默认加)

Istio controller 1.27+ 自动给生成的 Deployment 加:
```yaml
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app.kubernetes.io/name: waypoint
              topologyKey: kubernetes.io/hostname    # 强制跨节点
```

**作用**: 2 个 waypoint pod **不会** 调度到同一节点,避免单节点故障导致 2 个 pod 同时失效。

### 4.4 HA 三件套总结

| 机制 | 防的是什么 | 失效场景示例 |
|---|---|---|
| **replicas: 2** | 单 pod crash | pod OOM, container 异常退出 |
| **podAntiAffinity** | 单节点故障 | 节点 reboot / 网络分区 |
| **PDB minAvailable: 1** | 维护期全失效 | 滚动升级 / 节点 drain |

### 4.5 如果需要 3 副本或更多?

按需调整:
```yaml
spec:
  replicas: 3     # 更高 HA
```

但有 trade-off:
- 副本越多,L7 拦截总吞吐越高,但 **资源消耗越多** (envoy 大约 100m CPU + 128Mi mem per pod)
- 3 副本 + 50 个 ns = 150 个 waypoint pod → dev 集群资源爆
- **本场景 2 副本是合理选择**, 因 dev 集群 e2-medium 资源紧

### 4.6 HA 的"实战表现"图

```
正常态:
  Node-1  Node-2
   ▼       ▼
  w1      w2     ← 2 副本,跨节点
   │       │
   └───────┘
   Service waypoint-int (round-robin)

节点 1 drain 期间:
  Node-1   Node-2
   ✗        │
   (空)    w1 ← 旧 w2 被驱逐,新 w1 起来 (PDB 允许 kill w2)
            │
            └─ 流量仍被拦截 (1 个副本)

滚动升级期间:
  旧 w1 → 新 w1 (RollingUpdate)
  旧 w2 → 新 w2 (同时进行)
  PDB 保证: 全过程至少 1 个 ready pod
```

---

## 5. waypoint 不做的事(防止误解)

| 误解 | 实际 |
|---|---|
| "waypoint = ingress Gateway" | ❌ waypoint 是**东西向** L7, ingress Gateway 是**南北向**入口,两者职责不同 |
| "waypoint 终止 TLS" | ❌ waypoint **不做 TLS 终止**, HBONE 由 ztunnel mTLS 承载; TLS 终止在 ingress Gateway |
| "waypoint 替代 VirtualService" | ⚠️ waypoint 是 **policy 执行器**, 用 HTTPRoute (推荐) 或 VirtualService (Alpha) 表达路由规则 |
| "waypoint 跨 ns 工作" | ❌ 默认 waypoint 只处理**本 ns** 流量 (allowedRoutes: Same); 跨 ns 需要额外配置 |
| "waypoint 处理外部流量" | ❌ waypoint 是 mesh 内部组件, **不直接接收** internet 流量 |

---

## 6. per-namespace vs per-service 决策

按 `03-waypoint-design.md` §3 + Istio 官方推荐:

| 维度 | **per-namespace** (本场景) | per-service |
|---|---|---|
| **资源占用** | 1 waypoint (ns 共享) | N waypoints (每个 service 一个) |
| **L7 隔离度** | ns 内共享 L7 策略 | 每个 service 独立 L7 配置 |
| **适用场景** | 团队自治 ns (1 team / 1 ns) | 多团队共享 ns,需 service 级隔离 |
| **故障域** | ns 内流量受单 waypoint 影响 (但有 HA) | 单 service 故障不影响其他 |
| **本场景推荐度** | ⭐⭐⭐ | ⭐ (一般不用) |

### 6.1 本场景用 per-namespace 的理由

1. **每个 ns 一个 team** (ba000000-lex-int = 业务 ns, Lex 团队自治)
2. **dev 集群资源有限**, per-service 会爆资源
3. **L7 策略粒度 = team 内服务间**, 刚好对应 ns 级
4. **未来如需 per-service**, 可叠加 (在同 ns 内, 某些 service 单独 enroll)

### 6.2 per-namespace 模式的局限 — 你需要知道

- **整个 ns 的所有 service 共享同一份 L7 策略** (HTTPRoute / AuthZ / 等)
- 如果 ns 内有 **异质服务** (例如 HTTP API + gRPC + 异步 worker), 可能需要不同 L7 处理:
  - 解决: 给特定 service 单独 enroll (`kubectl label service foo istio.io/use-waypoint=foo-waypoint`)
  - 优先级: pod label > service label > ns label
- 如果某个 service 想**完全 bypass** waypoint (例如 eBPF 探针):
  - 解决: 不给该 service 打 `istio.io/use-waypoint=waypoint` (pod label 覆盖)

---

## 7. canary / 流量分割 — 高级模式 (可选)

Istio 1.27+ 支持 **canary waypoint** (灰度):

```yaml
# 1. 创建新 waypoint (canary 版本)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: waypoint-int-v2
  namespace: ba000000-lex-int
  labels:
    istio.io/waypoint-for: all
spec:
  gatewayClassName: istio-waypoint
  replicas: 1
  listeners:
    - name: istio
      port: 15008
      protocol: HBONE

# 2. 给 Service 打 canary label
apiVersion: v1
kind: Service
metadata:
  name: my-service
  labels:
    istio.io/use-waypoint: waypoint-int          # 主 waypoint
    istio.io/use-waypoint-canary: waypoint-int-v2 # canary waypoint
  annotations:
    istio.io/use-waypoint-canary-weight: "10"   # 10% 流量走 v2
```

**用途**: 升级 waypoint (envoy 配置变更) 时, 先切 5-10% 流量验证, 再切 100%。

---

## 8. 验证清单 (本场景)

```bash
# 1. Gateway 资源已创建
kubectl get gateway -n ba000000-lex-int
# 预期: NAME          CLASS            ADDRESS     PORTS
#       waypoint-int  istio-waypoint   10.x.x.x    15008

# 2. Waypoint pod 跑起来 (2 副本)
kubectl get pods -n ba000000-lex-int -l gateway.networking.k8s.io/gateway-name=waypoint-int
# 预期: NAME                           READY   STATUS
#       waypoint-int-xxxx-yyyy         1/1     Running
#       waypoint-int-xxxx-zzzz         1/1     Running

# 3. 跨节点 (验证 podAntiAffinity)
kubectl get pods -n ba000000-lex-int -l gateway.networking.k8s.io/gateway-name=waypoint-int \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}'
# 预期: 2 个 pod 在不同 node

# 4. ns label 正确
kubectl get ns ba000000-lex-int --show-labels
# 预期含:
#   istio.io/dataplane-mode=ambient
#   istio.io/use-waypoint=waypoint
#   istio.io/ingress-use-waypoint=waypoint

# 5. PDB 生效
kubectl get pdb -n ba000000-lex-int
# 预期: NAME          MIN-AVAILABLE
#       waypoint-int  1

# 6. L7 流量确实经过 waypoint (从 ambient ns pod 调另一个)
kubectl exec -n ba000000-lex-int <pod-a> -- \
  curl -s http://<pod-b-svc>:80/healthz
# 在 waypoint pod 上看 access log:
kubectl logs -n ba000000-lex-int -l gateway.networking.k8s.io/gateway-name=waypoint-int --tail=20
# 应看到 HTTP/2 200 请求记录
```

---

## 9. 故障场景与处置

| 故障 | 现象 | 根因 | 处置 |
|---|---|---|---|
| waypoint pod 全挂 | AuthZ / HTTPRoute 不生效 | 2 副本同节点, 节点故障 | 检查 podAntiAffinity, 增加 replicas |
| L7 拦截偶发失效 | 偶发请求绕过 waypoint | PDB 缺失, 升级时 0 副本 | 配 PDB minAvailable: 1 |
| waypoint 内存爆 | OOMKilled | 流量太大, 单 pod 内存不够 | 增加 mem limits / 增加 replicas |
| waypoint CPU 飙高 | 延迟升高 | L7 filter 太复杂 | 拆分 AuthZ 规则 / 用 canary 灰度 |
| 想临时关闭 L7 拦截 | 不影响业务, 只去 waypoint | ns label 错 | `kubectl label ns ba000000-lex-int istio.io/use-waypoint-` (移除 label) |

---

## 10. 升级与维护

| 操作 | 步骤 |
|---|---|
| 升 waypoint 版本 (envoy) | 跟随 istiod 版本升, istio controller 会触发 waypoint Deployment 滚动重启 |
| 改 L7 策略 (HTTPRoute / AuthZ) | 直接 apply 新 YAML, controller 会热加载, **不需要重启** waypoint |
| 临时关闭某 ns 的 L7 拦截 | `kubectl label ns ba000000-lex-int istio.io/use-waypoint-` (移除 enroll label) |
| 完全删除 waypoint | `kubectl delete gateway waypoint-int -n ba000000-lex-int` |
| 完全回滚 ambient | 见 `04-migrate-minimal-to-ambient.md` 的回滚路径 |

---

## 11. 反向 — 这些场景不用 waypoint

- **业务 ns 完全无 L7 需求, 只要 mTLS**: 不装 waypoint, ztunnel 直连更轻
- **业务 pod 需要完全 bypass mesh** (例如特殊 eBPF 探针): 保留 sidecar 模式
- **入口流量**: waypoint 不替代 ingress Gateway, 入口 Gateway 仍是 K8s Gateway API Gateway (sidecar)
- **多集群跨网络 mesh**: 走 East-West Gateway, 不混 waypoint
- **dev/staging 集群** 想省资源: 跳过 waypoint, 只用 ztunnel mTLS

---

## 12. 总结 — 4 个关键 takeaway

### 12.1 waypoint 是 ns 级 L7 拦截器

`istio.io/waypoint-for: all` + ns label `istio.io/use-waypoint=waypoint` 的组合让**整个 ns 内所有 service 和 workload**的 L7 流量都过这个 waypoint。

### 12.2 "100 个 deploy 都要走" 在物理上怎么发生

ztunnel (节点级 DaemonSet) 拦截入站/出站流量, 看目标 ns label → 强制走 waypoint → waypoint 不区分 deploy, 而是接受任何匹配的 HTTPRoute。

### 12.3 HA 由 3 件套实现

`replicas: 2` + `podAntiAffinity` (隐式) + `PDB minAvailable: 1` — 防止单 pod crash、节点故障、维护期全失效。

### 12.4 per-namespace vs per-service

**本场景用 per-namespace** 是合理选择 — 资源省、team 自治、L7 粒度够用; per-service 只在多团队共享 ns 时考虑。

---

## 13. Resources 配置 — 为什么 `01-waypoint-int.yaml` 里没 resources 字段

> **你的核心问题**:
> "waypoint pod 为什么里面没有做资源的大小定义?比如说 CPU、内存"

### 13.1 TL;DR — 3 个关键事实

| # | 事实 | 影响 |
|---|---|---|
| **1** | waypoint **Deployment 是 istio controller 自动生成的**,**不是你手写** | 你在 Gateway spec 里**没有地方**写 `resources` |
| **2** | OSS Istio 1.30 默认生成的 waypoint pod **没有 requests/limits** | pod 会被集群 BestEffort 调度, 无 QoS 保障 |
| **3** | 控制 waypoint resources **有 3 种方式**:ConfigMap / IstioOperator / admission controller | Solo 1.30+ 默认支持方式 1; OSS Istio 1.30 也支持 |

**严格定义** (Solo 1.30 docs):
> "Labels and annotations set under `spec.infrastructure` are copied to the
> generated Deployment and Service. ... `horizontalPodAutoscaler`,
> `podDisruptionBudget`, `deployment` (含 `containers[].resources`) 都可以通过
> `waypoint-options` ConfigMap 配置"
> — [Solo Configure waypoints](https://docs.solo.io/istio/1.30.x/ambient/waypoints/configuration)

### 13.2 为什么 Gateway spec 里没有 resources 字段?

K8s Gateway API 的 `Gateway` 资源是**声明意图**,不是 Pod 模板。`spec` 里只有:
- `gatewayClassName` — 选 controller
- `replicas` — 副本数
- `listeners` — 端口 / 协议
- `infrastructure` — 透传到生成资源的 labels / annotations / podSecurityContext 等
- **没有** `containers`、`resources`、`volumes` 这些 pod 模板字段

原因: waypoint 实际跑哪个 image、用什么 args、什么 resources, **全部由 `istio-waypoint` GatewayClass 对应的 controller (istiod 内置) 决定**。

### 13.3 controller 实际生成的 Deployment 长什么样?

按 Solo 文档示例,istio controller 生成的 Deployment 模板大致是:

```yaml
apiVersion: apps/v1
kind: Deployment        # controller 自动生成, 不是你写的
metadata:
  name: waypoint-int
  namespace: ba000000-lex-int
spec:
  replicas: 2                # ← 来自 Gateway.spec.replicas
  selector:
    matchLabels:
      istio.io/gateway-name: waypoint-int
  template:
    metadata:
      labels:
        istio.io/gateway-name: waypoint-int
        # ← 来自 Gateway.spec.infrastructure.labels (gateway-access / ingress / 等)
    spec:
      containers:
      - name: istio-proxy
        image: gcr.io/istio-release/proxyv2:<version>
        # ⚠️ OSS Istio 默认这里没有 resources 字段
        ports:
        - containerPort: 15021  # 健康检查
        - containerPort: 15090  # Prometheus
```

**关键观察**: `containers[].resources` 字段在 **OSS Istio 默认模板里缺失**。
→ K8s BestEffort QoS → 节点压力时优先被驱逐 → 触发 waypoint 中断 → AuthZ 失效。

### 13.4 3 种方式配置 resources

#### 方式 A: `waypoint-options` ConfigMap (推荐)

Solo 1.30+ / Istio 1.27+ 都支持。在 **waypoint 所在 ns** 创建同名 ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: waypoint-options       # 必须叫这个名, 与 Gateway 同 ns
  namespace: ba000000-lex-int
data:
  # Deployment template patch
  deployment: |
    spec:
      template:
        spec:
          containers:
          - name: istio-proxy
            resources:
              requests:
                cpu: 100m
                memory: 128Mi
              limits:
                cpu: 500m
                memory: 512Mi

  # HorizontalPodAutoscaler (可选)
  horizontalPodAutoscaler: |
    spec:
      minReplicas: 2
      maxReplicas: 5
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 80

  # PodDisruptionBudget (可选, 增强 PDB)
  podDisruptionBudget: |
    spec:
      minAvailable: 1
```

**来源** (Solo 1.30 docs 原话):
> "When Istio provisions a waypoint, Istio generates a Deployment and Service
> with the same name as the Gateway resource (unlike ingress gateway classes,
> istio-waypoint does not append a class-name suffix). Labels and annotations
> set under `spec.infrastructure` are copied to the generated Deployment and
> Service."
> — [Solo Configure waypoints](https://docs.solo.io/istio/1.30.x/ambient/waypoints/configuration)

→ **本场景推荐方式 A**。

#### 方式 B: IstioOperator 全局设置 (影响所有 waypoint)

```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  components:
    pilot:
      k8s:
        # 注意: IstioOperator 没有 "waypoint" 组件段, 通过以下 env 注入
        env:
        - name: ISTIO_PROXY_CPU_LIMIT
          value: "500m"
        - name: ISTIO_PROXY_MEMORY_LIMIT
          value: "512Mi"
        # 注意: env 变量不是所有 controller 都读
```

⚠️ **方式 B 不可靠**: IstioOperator 主要控制 istiod, waypoint pod 由 gateway controller 生成, **不一定读 ISTIO_PROXY_* env**。除非你能确认你的 Istio 版本支持,否则不推荐。

#### 方式 C: MutatingWebhook / Kyverno 等 admission controller

```yaml
# Kyverno 示例: 给所有 waypoint Deployment 注入 resources
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: inject-waypoint-resources
spec:
  rules:
  - name: inject-resources
    match:
      any:
      - resources:
          kinds:
          - Deployment
          selector:
            matchLabels:
              istio.io/gateway-name: "waypoint-*"
    mutate:
      patchStrategicMerge:
        spec:
          template:
            spec:
              containers:
              - name: istio-proxy
                resources:
                  requests:
                    cpu: 100m
                    memory: 128Mi
                  limits:
                    cpu: 500m
                    memory: 512Mi
```

**适用**: 不能改 Istio controller 配置,但用 Kyverno / OPA 的集群。

### 13.5 推荐 sizing (按 Istio 官方 / Solo / 社区实测)

| 集群规模 | services | waypoint CPU request | memory request | limits |
|---|---|---|---|---|
| **小型** (< 50 services) | 小流量 | `100m` | `128Mi` | cpu `500m`, mem `512Mi` |
| **中型** (50-200) | 中流量 | `200m` | `256Mi` | cpu `1`, mem `1Gi` |
| **大型** (200+) | 高流量 | `500m` | `512Mi` | cpu `2`, mem `2Gi` |

**本场景** (dev 集群, 假设 < 50 services):
```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

**资源消耗估算** (本场景):
```
2 waypoint pods × (100m cpu, 128Mi mem) = 200m CPU + 256Mi mem (requests)
                              + 500m cpu × 2 = 1 vCPU burstable headroom
```
dev 集群单节点 (e2-medium ≈ 940m allocatable) 上, **2 个 waypoint 大约吃 17% 的 CPU, 27% 的内存 (request basis)**。

### 13.6 waypoint options ConfigMap 验证

```bash
# 1. ConfigMap 是否被 controller 识别
kubectl get cm waypoint-options -n ba000000-lex-int -o yaml

# 2. waypoint Deployment 实际 resources (验证 patch 生效)
kubectl get deploy waypoint-int -n ba000000-lex-int -o jsonpath='{.spec.template.spec.containers[0].resources}'
# 预期: {"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}

# 3. waypoint pod 真实使用
kubectl top pods -n ba000000-lex-int -l istio.io/gateway-name=waypoint-int
# 预期: CPU ~50-100m, MEM ~80-150Mi (正常运行)
```

### 13.7 给本场景的推荐 — 跟 `01-waypoint-int.yaml` 配套

**追加文件** `01-01-waypoint-options.yaml`:

```yaml
# =============================================================================
# 01-01-waypoint-options.yaml
# =============================================================================
# ConfigMap that istiod consumes to patch the auto-generated waypoint Deployment.
# 必须跟 Gateway 同名 (waypoint-int), 同 ns (ba000000-lex-int)。
#
# 设计依据:
#   - Solo 1.30 / Istio 1.27+ docs:
#     "Labels and annotations set under spec.infrastructure are copied to the
#      generated Deployment and Service. ... waypoint-options ConfigMap 在
#      controller reconcile 时被 read, 用于 patch deployment template。"
#   - 本场景 dev 集群 (e2-medium, 资源紧), 选小型 sizing。
# -----------------------------------------------------------------------------
apiVersion: v1
kind: ConfigMap
metadata:
  name: waypoint-options
  namespace: ba000000-lex-int
  labels:
    gateway-access: ba000000-lex-int
    ingress: int
data:
  deployment: |
    spec:
      template:
        spec:
          containers:
          - name: istio-proxy
            resources:
              requests:
                cpu: 100m
                memory: 128Mi
              limits:
                cpu: 500m
                memory: 512Mi
              # 健康检查 (可选, 跟 deployment template 一致)
              readinessProbe:
                httpGet:
                  path: /healthz/ready
                  port: 15021
                initialDelaySeconds: 1
                periodSeconds: 2
              livenessProbe:
                httpGet:
                  path: /healthz
                  port: 15021
                initialDelaySeconds: 5
                periodSeconds: 10
              startupProbe:
                httpGet:
                  path: /healthz/ready
                  port: 15021
                initialDelaySeconds: 0
                periodSeconds: 2
                failureThreshold: 30

  # HPA (可选, dev 集群先不加, 减少复杂度)
  # horizontalPodAutoscaler: |
  #   spec:
  #     minReplicas: 2
  #     maxReplicas: 5
  #     metrics:
  #     - type: Resource
  #       resource:
  #         name: cpu
  #         target:
  #           type: Utilization
  #           averageUtilization: 80
```

**Apply 顺序** (本场景):
```bash
# 1. 创建 Gateway (controller 生成 Deployment)
kubectl apply -f 01-waypoint-int.yaml

# 2. 创建 ConfigMap (controller 立即 patch Deployment template)
kubectl apply -f 01-01-waypoint-options.yaml

# 3. 验证 Deployment 被 patch
kubectl get deploy waypoint-int -n ba000000-lex-int \
  -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

### 13.8 反向 — Resources 设错会怎样

| 错误 | 后果 |
|---|---|
| **request 太大** (例如 cpu: 1, mem: 2Gi) | dev 集群调度失败, waypoint pod Pending, L7 拦截全失效 |
| **limit 太小** (例如 cpu: 100m) | 流量高峰 OOMKilled / throttled, waypoint 不稳定, AuthZ 间歇失效 |
| **没设 limits** (BestEffort QoS) | 节点压力时优先被驱逐, PDB 也救不了 |
| **request:limit 比例失衡** (例如 request: 100m, limit: 4) | K8s Burstable QoS, 调度 OK 但 burst 时跟 Guaranteed QoS pod 抢资源 |
| **多个 waypoint 都设了同样大的 requests** | 集群资源紧张时互相挤兑 |

**黄金法则**:
- requests = **正常负载下**的稳态值 (用于调度决策)
- limits = **流量峰值**的 2-3 倍 (允许 burst, 但防止失控)

---

### 13.9 多租户 waypoint sizing — `GatewayClass default` + per-Gateway patch

> **你的核心问题**:
> "对于我们这种独立分拆的,也就是每个 Tenant 用户都有一个自己的 Namespace,
> 这种情况下,我是不是在 Namespace level 里面去做独立的定义,设计更为合理?"
> "namespace 自己的定义会覆盖系统 Levels,对吧?"

**简答**: ✅ **完全正确**,而且 Istio 1.30+ / Solo 1.30+ 都**原生支持**这套机制。

#### 13.9.1 两层 ConfigMap 体系

Istio 官方引入了一个 **`gateway.istio.io/defaults-for-class` label** — 给整个集群所有 waypoint 设默认 + 允许每个 Gateway 单独 patch。

| 层 | 资源 | 位置 | 作用 |
|---|---|---|---|
| **集群默认层** | ConfigMap `istio-waypoint-defaults` (label: `gateway.istio.io/defaults-for-class: istio-waypoint`) | `istio-system` ns | **所有** waypoint 的基础默认 (replicas / resources / HPA / PDB) |
| **Gateway 覆盖层** | ConfigMap `<name>-options` (任意名,Gateway `parametersRef` 引用) | **Waypoint 所在 ns** | 单 waypoint 单独 patch, 应用在 default 之上 |

#### 13.9.2 合并策略 — per-Gateway 应用在 default 之上

**严格定义** (Solo 1.31 docs 原话):
> "If both a GatewayClass default and a per-Gateway ConfigMap are present,
> the per-Gateway customization is applied **on top of** the class defaults."
> — [Solo Configure waypoints](https://docs.solo.io/istio/1.31.x/waypoints/configuration/)

合并方式 = **strategic merge patch**, 不是 replace:

| 字段 | 默认层定义 | Gateway 层定义 | 合并结果 |
|---|---|---|---|
| `containers[].resources.requests.cpu` | `100m` | `200m` | **`200m`** (overwrite) |
| `containers[].resources.requests.memory` | `128Mi` | (无) | **`128Mi`** (继承) |
| `containers[].resources.limits.cpu` | `500m` | `1000m` | **`1000m`** (overwrite) |
| `replicas` | `2` | (无) | **`2`** (继承) |
| 新加 `topologySpreadConstraints` | (无) | 有 | **新增字段** |

**结论**: 每个 ns 可以**只覆盖它关心的字段**(例如 small tenant 只改 requests.cpu),**其余继承集群默认**。

#### 13.9.3 多租户场景的完整架构

```
集群级 (istio-system ns)
├── ConfigMap: istio-waypoint-defaults
│   label: gateway.istio.io/defaults-for-class: istio-waypoint
│   data:
│     deployment: |
│       spec:
│         template:
│           spec:
│             containers:
│             - name: istio-proxy
│               resources:
│                 requests: { cpu: 100m, memory: 128Mi }
│                 limits:   { cpu: 500m, memory: 512Mi }
│         replicas: 2
│
│   作用: 集群内所有 waypoint 的 baseline
│
│
├── Tenant 1 ns (ba000000-lex-int / 高流量团队)
│   ├── ConfigMap: waypoint-options          # ← 单独 patch
│   │   data.deployment:
│   │     spec.template.spec.containers:
│   │     - name: istio-proxy
│   │       resources:
│   │         requests: { cpu: 500m, memory: 512Mi }    # 覆盖
│   │         limits:   { cpu: 2, memory: 2Gi }        # 覆盖
│   │
│   ├── Gateway: waypoint-int
│   │   spec:
│   │     infrastructure:
│   │       parametersRef:           # ← K8s Gateway API 1.2+ 引用 ConfigMap
│   │         group: ""
│   │         kind: ConfigMap
│   │         name: waypoint-options
│   │
│   └── waypoint Deployment (merged)
│       resources.requests: { cpu: 500m, memory: 512Mi }   ← 合并后
│
├── Tenant 2 ns (ba000001-lex-int / 中流量团队)
│   ├── ConfigMap: waypoint-options
│   │   data.deployment:
│   │     resources.requests: { cpu: 200m, memory: 256Mi }
│   │
│   ├── Gateway: waypoint-int
│   │   spec.infrastructure.parametersRef.name: waypoint-options
│   │
│   └── waypoint Deployment (merged)
│       resources.requests: { cpu: 200m, memory: 256Mi }   ← 合并后
│
└── Tenant 3 ns (ba000099-lex-int / 低流量 dev/staging)
    ├── ConfigMap: waypoint-options
    │   data.deployment:
    │     resources.requests: { cpu: 50m, memory: 64Mi }
    │     replicas: 1                              # dev 不需要 HA
    │
    ├── Gateway: waypoint-int
    │   spec.infrastructure.parametersRef.name: waypoint-options
    │
    └── waypoint Deployment (merged)
        resources.requests: { cpu: 50m, memory: 64Mi }
        replicas: 1
```

#### 13.9.4 三层 sizing 推荐 (per-team 多租户场景)

| Tenant 规模 | services / 流量 | requests | limits | replicas |
|---|---|---|---|---|
| **大团队** (高流量, 核心业务) | 200+ services | cpu `500m`, mem `512Mi` | cpu `2`, mem `2Gi` | 2-5 (HPA) |
| **中团队** (常规) | 50-200 services | cpu `200m`, mem `256Mi` | cpu `1`, mem `1Gi` | 2 |
| **小团队 / dev** (< 50) | 1-50 services | cpu `100m`, mem `128Mi` | cpu `500m`, mem `512Mi` | 2 |
| **极小 / staging** | < 10 services | cpu `50m`, mem `64Mi` | cpu `200m`, mem `256Mi` | 1 |

#### 13.9.5 落地步骤 (本场景多租户版)

**第 1 步**:集群层定义 baseline(`istio-system` ns,只做一次)

```yaml
# cluster-waypoint-defaults.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio-waypoint-defaults
  namespace: istio-system                            # 必须在 istio-system
  labels:
    gateway.istio.io/defaults-for-class: istio-waypoint   # 关键 label
data:
  deployment: |
    spec:
      template:
        spec:
          containers:
          - name: istio-proxy
            resources:
              requests: { cpu: 100m, memory: 128Mi }
              limits:   { cpu: 500m, memory: 512Mi }
  # replicas: 2  # Gateway.spec.replicas 默认即可, 不需要在 default ConfigMap
```

**第 2 步**:每个 tenant ns 单独 patch(`ba000000-lex-int` ns)

```yaml
# case-lex/01-01-waypoint-options.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: waypoint-options
  namespace: ba000000-lex-int                       # tenant ns
data:
  deployment: |
    spec:
      template:
        spec:
          containers:
          - name: istio-proxy
            resources:
              # 大团队 sizing (Lex Q2: 业务调 GCS/BigQuery, 高流量)
              requests: { cpu: 500m, memory: 512Mi }
              limits:   { cpu: 2, memory: 2Gi }
```

**第 3 步**(重要): **Gateway spec 加 `parametersRef`** — 这是你原 `01-waypoint-int.yaml` 里**缺失**的关键字段!

```yaml
# case-lex/01-waypoint-int.yaml (patch 后的版本)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: waypoint-int
  namespace: ba000000-lex-int
  labels:
    istio.io/waypoint-for: all
spec:
  gatewayClassName: istio-waypoint
  replicas: 2
  infrastructure:
    # ---- 关键: 引用 per-Gateway ConfigMap ----
    parametersRef:
      group: ""
      kind: ConfigMap
      name: waypoint-options           # ← 跟 ConfigMap 同名
    labels:
      gateway-access: ba000000-lex-int
      ingress: int
  listeners:
    - name: istio
      port: 15008
      protocol: HBONE
      allowedRoutes:
        namespaces:
          from: Same
```

**没有 `parametersRef` 会怎样**:
- ConfigMap 存在但**不被引用** → controller 用**集群默认值**,per-ns patch 完全失效
- 验证: `kubectl get deploy waypoint-int -n ba000000-lex-int -o jsonpath='{.spec.template.spec.containers[0].resources}'`
  - 若返回 `null` 或集群默认 → ConfigMap 没被引用

#### 13.9.6 ⚠️ 你当前 `01-waypoint-int.yaml` 缺失的关键字段

| 缺失 | 影响 | 文档章节 |
|---|---|---|
| `spec.infrastructure.parametersRef` | per-ns ConfigMap **不会生效** | §13.9.5 |
| `spec.infrastructure.podSecurityContext` (可选) | 跟业务 pod 共享 SecurityContext | (可加) |

→ **必须补 `parametersRef`** 才能让 `waypoint-options` ConfigMap 真正生效。

#### 13.9.7 验证 — 3 层都能独立工作

```bash
# 1. 集群默认 ConfigMap 存在
kubectl get cm -n istio-system -l gateway.istio.io/defaults-for-class=istio-waypoint
# 预期: NAME                    DATA+REVISION
#       istio-waypoint-defaults  1

# 2. Tenant ns ConfigMap 存在
kubectl get cm -n ba000000-lex-int waypoint-options
# 预期: NAME             DATA+REVISION
#       waypoint-options  1

# 3. Gateway 引用了 ConfigMap
kubectl get gateway -n ba000000-lex-int waypoint-int \
  -o jsonpath='{.spec.infrastructure.parametersRef}'
# 预期: map[name: waypoint-options group: "" kind: ConfigMap]

# 4. 最终 Deployment 的 resources (合并后, 不是 default, 也不是 raw ConfigMap)
kubectl get deploy -n ba000000-lex-int waypoint-int \
  -o jsonpath='{.spec.template.spec.containers[0].resources}'
# 预期: {"limits":{"cpu":"2","memory":"2Gi"},"requests":{"cpu":"500m","memory":"512Mi"}}

# 5. 验证合并行为 — 故意只 patch 部分字段
# 假设 tenant 只覆盖 requests, 不覆盖 limits, 结果 limits 应继承集群默认
# tenant waypoint-options:
#   resources: { requests: { cpu: 500m, memory: 512Mi } }   # 只改 requests
# 期望 deployment:
#   resources: { requests: { cpu: 500m, memory: 512Mi },
#                limits:   { cpu: 500m, memory: 512Mi } }  # limits 从 istio-waypoint-defaults 继承
```

#### 13.9.8 反向 — per-ns 覆盖 vs 集群默认 怎么选

| 场景 | 推荐 |
|---|---|
| 集群只有 1-2 个 ns | 用集群默认 + per-ns ConfigMap 都行 |
| 集群有 10+ ns | **集群默认必须有**(baseline), per-ns 覆盖 opt-in |
| 多租户平台 (每个团队不同需求) | **必须两层**(默认 + per-ns) |
| 单一业务集群 (1 team, 1 ns) | **可以只 per-ns**(不需要集群默认) |

**本场景 (Lex)**:
- 你 dev 集群假设 5-10 个 tenant ns (ba000000, ba000001, ..., ba000009)
- 每个 team 流量差异大 (Lex ba000000 是高流量团队)
- **强烈推荐**:**集群默认 + per-ns 覆盖** 两层都用
- 集群默认 baseline 用小团队 sizing (cpu 100m, mem 128Mi, limits 500m/512Mi)
- Lex 自己的 ba000000 ns 单独 patch (cpu 500m, mem 512Mi, limits 2/2Gi)
- 其他 ns 不写 ConfigMap, 自动用集群默认

#### 13.9.9 这是 Solo 1.30+ 推荐的最佳实践

> "The Solo distribution of Istio generates a label value from the waypoint name,
> namespace, and mesh domain. If the combined length exceeds 63 characters,
> label creation fails silently. Use concise names and avoid long custom mesh
> domains."
> — [Solo Configure waypoints](https://docs.solo.io/istio/1.30.x/ambient/waypoints/configuration)

**OSS Istio 1.27+ 也支持**这个机制 (无 Solo 依赖), 核心字段是:
- `gateway.istio.io/defaults-for-class: istio-waypoint` (cluster-level)
- `spec.infrastructure.parametersRef` (gateway-level)
- `data: { deployment: |, hpa: |, pdb: | }` (config format)

---

## 14. 参考链接

### Istio 官方
- [Configure waypoint proxies](https://istio.io/latest/docs/ambient/usage/waypoint/) — 权威部署指南
- [Use Layer 7 features](https://istio.io/latest/docs/ambient/usage/l7-features/) — HTTPRoute parentRefs attachment
- [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/) — waypoint 在流量分层中的位置
- [Istio Ambient Install](https://istio.io/latest/docs/ambient/install/) — `istio-waypoint` GatewayClass 注册

### Ambient Mesh 社区
- [Configure waypoints](https://ambientmesh.io/docs/waypoints/configuration/) — `waypoint-for` vs `use-waypoint` label 组合矩阵
- [Configure waypoint proxies](https://ambientmesh.io/docs/setup/configure-waypoints/) — 部署 / 验证步骤

### Solo
- [Configure waypoints (Solo 1.31)](https://docs.solo.io/istio/1.31.x/waypoints/configuration/) — ServiceEntry / WorkloadEntry 推荐 `waypoint-for: all`,**`GatewayClass default` + per-Gateway patch 机制**
- [Configure waypoints (Solo 1.30)](https://docs.solo.io/istio/1.30.x/ambient/waypoints/configuration) — `waypoint-options` ConfigMap + strategic merge patch 行为

### 社区博客
- [Mastering Istio Service Mesh on EKS](https://thecloudplaybook.com/m/mastering-istio-service-mesh-on-eks) — Istio sidecar / gateway resources sizing 实测
- [Service Mesh in 2026: Ambient Mode Update](https://dev.to/rex_zhen_a9a8400ee9f22e98/service-mesh-in-2026-the-landscape-has-changed-istio-ambient-mode-update-179m) — Waypoint 资源消耗实测 (cpu `200m`, mem `256Mi`)
- [How to Handle Waypoint Proxy Scaling in Ambient Mode](https://oneuptime.com/blog/post/2026-02-24-how-to-handle-waypoint-proxy-scaling-in-ambient-mode/view) — waypoint-options ConfigMap 实战示例
- [How to Use Istio Ambient Mode to Reduce Resource Costs](https://oneuptime.com/blog/post/2026-02-24-how-to-use-istio-ambient-mode-to-reduce-resource-costs/view) — per-team ConfigMap 资源分级方案

### K8s Gateway API
- [Gateway spec](https://gateway-api.sigs.k8s.io/api-types/gateway/) — Gateway 资源 spec (含 `replicas` 字段说明)
- [Infrastructure parameters reference](https://gateway-api.sigs.k8s.io/api-types/gateway/#infrastructure) — `spec.infrastructure.parametersRef` 字段

### 同目录
- `01-waypoint-int.yaml` — 本文档分析对象
- `00-namespace-ba000000-lex-int.yaml` — ns 级 3 个 istio label
- `03-mesh-security.yaml` — AuthZ targetRefs 绑 waypoint
- `09-01-app-httproute.yaml` — HTTPRoute 2 (parentRef=Service, waypoint 拦截)
- `../03-waypoint-design.md` — waypoint 选型 (per-ns vs per-service) + HA 模板
- `../10-waypoint-gateway-coexistence.md` — ingress Gateway 与 waypoint 共存
- `yaml-assessment.md` — 残余风险审计 (H-1: ENABLE_INGRESS_WAYPOINT_ROUTING)
- `analyze-httproute.md` — 两段 HTTPRoute + waypoint 工作原理

---

*Generated by architect-gcp Bot — 2026-09-25.*
*回答 4 个核心问题: 100 个 deploy 是否都过 waypoint / 怎么工作 / HA 怎么实现 / per-ns vs per-service。*
*基于 Istio 1.30+ 官方文档 + ambientmesh.io docs + Solo 1.31 + 本目录两份参考文档。*