# Waypoint 详解：Ambient 模式下的 L7 策略执行器

> **文档定位**：解释 Istio Ambient 模式中 **Waypoint** 的概念、架构、部署方式及其在 GKE + Gloo Mesh 环境中的作用。
>
> **前置知识**：建议先阅读 [Ambient.md](./Ambient.md) 了解 Ambient 模式与 Sidecar 的区别。
>
> Waypoint 是 Istio Ambient 模式（无 sidecar 服务网格）中的 L7 代理组件，用于处理命名空间或服务级别的第 7 层流量管理，如路由、授权和流量策略。 [solo](https://www.solo.io/blog/istio-ambient-waypoint-proxy-deployment-model-explained)

在您提供的单 GKE 集群架构中，Waypoint 部署在每个命名空间或每个服务级别，作为集中式 Envoy 代理实例，与 ztunnel（L4 数据平面）协作，而应用 Pod 无需注入 sidecar。 [oneuptime](https://oneuptime.com/blog/post/2026-02-24-per-namespace-waypoint-proxies-ambient-mode/view)

这种设计简化了部署，提高资源效率：gloo-platform 管理控制平面，istiod 配置 Istio，istio-cni 和 ztunnel 处理节点级网络，Waypoint 则针对特定范围优化 L7 功能。 [kgateway](https://kgateway.dev/blog/extend-istio-ambient-kgateway-waypoint/)
## 部署模式
- **按命名空间**：默认模式，每个团队命名空间一个 Waypoint，所有服务共享（如服务 A、B、C 通过单一代理处理入站流量），用 `istioctl waypoint apply --enroll-namespace` 创建。 [solo](https://www.solo.io/blog/istio-ambient-waypoint-proxy-deployment-model-explained)
- **按服务**：更细粒度，每个服务独立 Waypoint，适合隔离需求高的场景。 [github](https://github.com/istio/istio/discussions/56372)
- 优势：比传统 sidecar 更轻量，支持多命名空间共享以节省资源。 [solo](https://www.solo.io/blog/istio-ambient-waypoint-proxy-deployment-model-explained)
## 优势与配置
Waypoint 提升了 Ambient 模式的灵活性，无需 Pod 重启即可启用 L7 功能（如 VirtualService）。 [oneuptime](https://oneuptime.com/blog/post/2026-02-24-per-namespace-waypoint-proxies-ambient-mode/view)

配置示例：调整资源限额以匹配流量，如 CPU 200m-1000m、内存 128Mi-512Mi。 [oneuptime](https://oneuptime.com/blog/post/2026-02-24-per-namespace-waypoint-proxies-ambient-mode/view)

在 GKE 上，与 Gloo Platform 结合，提供管理平面支持整个 mesh。 [hashicorp](https://www.hashicorp.com/en/resources/building-deploying-applications-to-kubernetes-with-gitlab-and-hashicorp-waypoint)

---

## 1. 问题：Ambient 模式下 L7 策略谁来处理？

在 Ambient 模式中，流量拦截从 Pod 内部（Sidecar）迁移到了**节点级（ztunnel）**。ztunnel 负责：

- **L4 处理**：mTLS 加密、证书分发、TCP 连接管理
- **简单转发**：将流量从一个 Pod 转发到另一个 Pod

但 Istio 的价值不止于"转发"，还包括**L7 策略**：

- `AuthorizationPolicy`（L7 授权）
- `RequestTimeout`（超时）
- `RetryPolicy`（重试）
- `CorsPolicy`（跨域）
- HTTP 路由规则（路径重写、Header 改写等）

**这些 L7 能力需要一个专门的代理来执行**，这就是 **Waypoint** 的角色。

---

## 2. 核心定义：Waypoint 是什么？

**Waypoint** 是 Ambient 模式下的一种专用 L7 代理（Envoy），用于处理需要 L7 策略的流量。

```
┌──────────────────────────────────────────────────────────────┐
│ Ambient 模式下的流量分层                                      │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ 入口流量（Ingress → Service）                           ││
│  │ L7 路由、重写、CORS 等 → Waypoint（入口）              ││
│  └─────────────────────────────────────────────────────────┘│
│                           ↓                                  │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ 服务间流量（Service-to-Service）                        ││
│  │                                                         ││
│  │ 需要 L7 策略（AuthZ、超时、重试）？                     ││
│  │     ↓ 是                                               ││
│  │ Waypoint（Per-Namespace 或 Per-Service）               ││
│  │                                                         ││
│  │ 仅需 L4 mTLS？                                         ││
│  │     ↓ 否                                               ││
│  │ ztunnel 直连（无 Waypoint）                            ││
│  └─────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────┘
```

### Waypoint 的职责

| 职责            | 说明                                                 |
| --------------- | ---------------------------------------------------- |
| **L7 协议解析** | 解析 HTTP/GRPC，理解 URI、Header、Method             |
| **L7 策略执行** | 执行 AuthorizationPolicy、RetryPolicy、TimeoutPolicy |
| **可观测性**    | 收集 HTTP 指标（延迟、状态码、请求量）               |
| **按需部署**    | 只在需要 L7 能力的命名空间/服务部署，不影响其他流量  |

---

## 3. 架构图：Waypoint 在集群中的位置

```
                    Internet
                        │
                        ▼
        ┌───────────────────────────────┐
        │      GLB / Cloud Armor        │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │    Gloo Gateway / Ingress     │
        │    (替代 ASM Ingress GW)      │
        └───────────────────────────────┘
                        │
                        ▼
        ┌───────────────────────────────┐
        │    Single GKE Cluster         │
        │                               │
        │  ┌─────────────────────────┐  │
        │  │ Management Plane        │  │
        │  │ - gloo-mesh-mgmt-server │  │
        │  │ - gloo-mesh-agent       │  │
        │  │ - gloo-ui               │  │
        │  └─────────────────────────┘  │
        │                               │
        │  ┌─────────────────────────┐  │
        │  │ Control Plane           │  │
        │  │ - istiod               │  │
        │  └─────────────────────────┘  │
        │                               │
        │  ┌─────────────────────────┐  │
        │  │ CNI / Node Agent        │  │
        │  │ - istio-cni             │  │
        │  └─────────────────────────┘  │
        │                               │
        │  ┌─────────────────────────┐  │
        │  │ Node-Level Proxy        │  │
        │  │ - ztunnel (DaemonSet)   │  │
        │  │   处理 L4 mTLS          │  │
        │  │   每节点 1 个 Pod       │  │
        │  └─────────────────────────┘  │
        │               │               │
        │               ▼               │
        │  ┌─────────────────────────┐  │
        │  │ Namespace-Level Proxy   │  │
        │  │ - waypoint              │  │
        │  │   处理 L7 策略          │  │
        │  │   Per-Namespace/Service │  │
        │  │   (Deployment, 2 rep)   │  │
        │  └─────────────────────────┘  │
        │               │               │
        │               ▼               │
        │  ┌─────────────────────────┐  │
        │  │ App Pods (NO Sidecar)   │  │
        │  │ - app container         │  │
        │  │ - (无 istio-proxy)      │  │
        │  └─────────────────────────┘  │
        └───────────────────────────────┘
```

---

## 4. Waypoint vs Sidecar：对比

| 维度         | Sidecar 模式            | Ambient + Waypoint                                           |
| ------------ | ----------------------- | ------------------------------------------------------------ |
| **部署位置** | 每个 Pod 内（共享进程） | 节点级（ztunnel）+ 命名空间级（Waypoint）                    |
| **L4 处理**  | Sidecar（每个 Pod）     | ztunnel（节点级）                                            |
| **L7 处理**  | Sidecar（每个 Pod）     | Waypoint（按需，命名空间级）                                 |
| **资源消耗** | O(N)，N=Pod 数量        | O(1) for ztunnel + O(M) for Waypoint，M=需要 L7 的命名空间数 |
| **升级影响** | 升级 Sidecar 需重启 Pod | ztunnel 升级不影响 Pod，Waypoint 升级仅影响 L7 流量          |
| **适用场景** | 全量 L7 策略            | 仅需要 L7 策略的命名空间                                     |

### 关键洞察

> **在 Sidecar 模式下，每个 Pod 都处理 L7，即使 90% 的流量不需要任何 L7 策略。**
>
> **在 Ambient + Waypoint 模式下，只有需要 L7 策略的命名空间才部署 Waypoint，其他命名空间仅由 ztunnel 处理 L4 mTLS。**

---

## 5. Waypoint 的工作原理

### 5.1 流量路径（需要 L7 策略时）

```
Pod A (app container)
       │ localhost
       ▼
ztunnel (Pod A 所在节点)
       │ L4 mTLS，HBONE 隧道
       ▼
Waypoint (Namespace A)
       │ L7 策略检查（AuthZ、超时、重试）
       ▼
ztunnel (Pod B 所在节点)
       │ L4 mTLS，HBONE 隧道
       ▼
Pod B (app container)
```

### 5.2 流量路径（仅需 L4 mTLS 时）

```
Pod A (app container)
       │ localhost
       ▼
ztunnel (Pod A 所在节点)
       │ L4 mTLS 直连
       ▼
ztunnel (Pod B 所在节点)
       │ L4 mTLS 直连
       ▼
Pod B (app container)

（无 Waypoint 介入）
```

### 5.3 HBONE 协议

Waypoint（和 ztunnel）之间使用 **HBONE**（HTTP-Based Overlay Network Environment）通信：

- 基于 HTTP/2 + mTLS
- 端点间通过 ztunnel 建立隧道
- 支持 Prometheus 指标抓取

---

## 6. 部署 Waypoint

### 6.1 前提条件

1. 命名空间已启用 Ambient 模式：
   ```bash
   kubectl label namespace <ns> istio.io/dataplane-mode=ambient --overwrite
   ```

2. Istio 版本支持 Ambient（1.19+，推荐 1.27+）

### 6.2 使用 istioctl 部署（推荐）

```bash
# 为命名空间部署 Waypoint
istioctl waypoint apply -n <namespace> --enroll-namespace

# 示例：为 team-a-runtime 部署 Waypoint
istioctl waypoint apply -n team-a-runtime --enroll-namespace
```

**作用**：
1. 创建名为 `waypoint` 的 Gateway 资源
2. 创建对应的 Deployment 和 Service
3. 给命名空间打上 `istio.io/use-waypoint=waypoint` 标签

### 6.3 使用 Gateway API 部署

```yaml
# waypoint.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: waypoint
  namespace: team-a-runtime
  labels:
    # 关键标签：标记此 Gateway 为 Waypoint
    istio.io/waypoint-for: service
spec:
  # 使用 Istio 的 Waypoint GatewayClass
  gatewayClassName: istio-waypoint
  listeners:
    - name: mesh
      port: 15008
      protocol: HBONE
```

```bash
kubectl apply -f waypoint.yaml

# 同时标记命名空间使用 Waypoint
kubectl label namespace team-a-runtime istio.io/use-waypoint=waypoint --overwrite
```

### 6.4 验证 Waypoint 部署

```bash
# 查看 Waypoint Gateway
kubectl get gateway -n team-a-runtime

# 预期输出：
# NAME      CLASS              ADDRESS          PORTS
# waypoint  istio-waypoint     10.x.x.x         15008

# 查看 Waypoint Pod
kubectl get pods -n team-a-runtime -l app.kubernetes.io/name=waypoint

# 预期输出：
# NAME                             READY   STATUS    RESTARTS   AGE
# waypoint-xxxxxxxxx-xxxxx         1/1     Running   0          1m
# waypoint-xxxxxxxxx-xxxxx         1/1     Running   0          1m

# 查看命名空间标签
kubectl get ns team-a-runtime --show-labels

# 预期：包含 istio.io/dataplane-mode=ambient 和 istio.io/use-waypoint=waypoint
```

---

## 7. 回滚 Waypoint

### 7.1 删除 Waypoint（保留命名空间）

```bash
# 方式 1：删除 Gateway 资源
kubectl delete gateway waypoint -n team-a-runtime

# 方式 2：移除标签
kubectl label namespace team-a-runtime istio.io/use-waypoint-
```

### 7.2 完全退出 Ambient 模式

```bash
# 移除命名空间的 Ambient 标签
kubectl label namespace team-a-runtime istio.io/dataplane-mode-
```

---

## 8. Waypoint 与 Gloo Mesh 的关系

### 8.1 Gloo Mesh 管理面

Gloo Mesh 企业版提供统一的管理界面和 CRD 抽象：

| Gloo Mesh CRD    | Istio 原始资源        | Waypoint 中的执行位置     |
| ---------------- | --------------------- | ------------------------- |
| `VirtualGateway` | `Gateway`             | Gloo Gateway（入口）      |
| `RouteTable`     | `VirtualService`      | Waypoint（L7 路由）       |
| `TrafficPolicy`  | `DestinationRule`     | Waypoint（负载均衡、TLS） |
| `AccessPolicy`   | `AuthorizationPolicy` | Waypoint（L7 授权）       |

### 8.2 Gloo Mesh CRD 到 Waypoint 的映射

```
VirtualGateway (入口)  → Gloo Gateway Pod
RouteTable             → Waypoint (L7 路由)
TrafficPolicy          → Waypoint (L4/L7 策略)
AccessPolicy           → Waypoint (L7 AuthZ)
```

### 8.3 Waypoint 的自动创建

在 Gloo Mesh 中，当配置了以下资源时，会自动为对应命名空间创建 Waypoint：

- `RouteTable` 配置了路径匹配、Header 改写等 L7 规则
- `AccessPolicy` 配置了基于身份/IP 的授权
- `RetryPolicy` 或 `TimeoutPolicy`

---

## 9. 最佳实践

### 9.1 按需启用 Waypoint

> **不要为所有命名空间一刀切启用 Waypoint**

- 仅对**需要 L7 策略**的命名空间部署 Waypoint
- 仅需要 L4 mTLS 的命名空间可以不部署 Waypoint，由 ztunnel 直连

### 9.2 高可用配置

Waypoint 建议配置 2+ 副本和高可用反亲和性：

```yaml
# Waypoint 高可用示例（在 Gateway spec 中）
spec:
  replicas: 2
  podTemplate:
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: waypoint
          topologyKey: kubernetes.io/hostname
```

### 9.3 升级注意事项

- **不要同时升级** ingress gateway 和所有 waypoint
- 升级前检查 PodDisruptionBudget（PDB）
- 建议使用滚动升级策略

### 9.4 命名空间标签速查

```bash
# 查看所有命名空间的状态
kubectl get ns -L istio.io/dataplane-mode,istio.io/use-waypoint
```

| dataplane-mode | use-waypoint | 状态                 |
| -------------- | ------------ | -------------------- |
| `ambient`      | `waypoint`   | Ambient + L7 策略    |
| `ambient`      | （无）       | Ambient + 仅 L4 mTLS |
| （无）         | （无）       | 未加入 Ambient       |

---

## 10. 故障排查

### 10.1 Waypoint 未生成

```bash
# 检查命名空间标签
kubectl get ns <ns> --show-labels | grep istio

# 检查 istiod 日志
kubectl logs -n istio-system deploy/istiod | grep waypoint
```

### 10.2 流量未经过 Waypoint

```bash
# 确认 Waypoint 已部署
kubectl get gateway -n <ns>

# 检查 Envoy 配置
istioctl proxy-config endpoints <waypoint-pod> -n <ns>
```

### 10.3 L7 策略不生效

```bash
# 确认 AccessPolicy 存在
kubectl get accesspolicy -n <ns>

# 查看 Waypoint 日志
kubectl logs -n <ns> deploy/waypoint -c waypoint | grep -i "denied\|403"
```

---

## 11. 参考命令速查

```bash
# ─── 部署 ───────────────────────────────
istioctl waypoint apply -n <namespace> --enroll-namespace

# ─── 查看 ───────────────────────────────
kubectl get gateway -n <namespace>                    # Waypoint Gateway
kubectl get pods -n <namespace> -l app.kubernetes.io/name=waypoint  # Waypoint Pod
kubectl get ns -L istio.io/dataplane-mode,istio.io/use-waypoint    # 命名空间状态

# ─── 删除 ───────────────────────────────
kubectl delete gateway waypoint -n <namespace>
kubectl label namespace <namespace> istio.io/use-waypoint-

# ─── 诊断 ───────────────────────────────
istioctl waypoint verify -n <namespace>
kubectl describe gateway waypoint -n <namespace>
```

---

## 12. 参考资料

- [Istio Ambient 模式文档](https://istio.io/latest/docs/ambient/)
- [Istio Waypoint 配置](https://istio.io/latest/docs/ambient/usage/waypoint/)
- [Gloo Mesh Ambient 模式](https://docs.solo.io/gloo-mesh-enterprise/latest/ambient/)
- [Gateway API Waypoint](https://gateway-api.sigs.k8s.io/)

---

*文档版本：适用于 Istio 1.27+，Gloo Mesh EE 2.x*
*更新日期：2026-04-25*