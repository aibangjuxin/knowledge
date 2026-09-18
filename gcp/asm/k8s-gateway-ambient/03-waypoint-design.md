# Waypoint 设计决策 — per-namespace vs per-service 与 HA

> **TL;DR**:
> - Waypoint 是 ambient 的 **L7 策略执行器**(AuthorizationPolicy / VirtualService / HTTPRoute 等)
> - **per-namespace** = 一个 namespace 一个 waypoint,适合 90% 场景,**本场景推荐**
> - **per-service** = 每个 Service 一个 waypoint,粒度更细,但成本翻倍,**只在多团队共享 ns 时用**
> - HA 标准:waypoint Deployment 2 副本 + podAntiAffinity(节点级)+ PDB
> - 入口 Gateway (K8s Gateway API) ≠ waypoint,**两者职责不同**,本篇只讲 waypoint

---

## 1. Waypoint 在哪里:它与已有组件的关系

```text
你的 Gateway 现有结构(已落地)
└─ K8s Gateway API Gateway (gatewayClassName: istio)
   ├─ Ingress 流量入口 = sidecar 模式跑 envoy
   ├─ ListenerSet 多租户
   └─ HTTPRoute / TCPRoute 等

Ambient 引入后(本目录探索)
└─ istiod (配置大脑)
   ├─ istio-cni (节点拦截)
   ├─ ztunnel (节点 L4 mTLS)
   └─ waypoint (L7 策略执行器)  ← 本篇核心
      ├─ per-namespace 模式(推荐)
      └─ per-service 模式(可选)
```

**关键区分**:

| 组件 | 角色 | 谁部署 | 在哪跑 |
|---|---|---|---|
| **K8s Gateway API Gateway** | **南北向**入口(L7 路由 + TLS 终止) | 你的 ListenerSet 多租户 | 独立 Deployment,跑在 ingress ns |
| **waypoint** | **东西向**L7 策略(AuthZ / 重试 / 超时) | 每个 ns 1 个 | ns 内 Deployment,2 副本 |
| **ztunnel** | **东西向**L4 mTLS | 每节点 | DaemonSet |

---

## 2. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **waypoint** | namespace 内的 L7 代理 | "A waypoint is an Envoy proxy deployed per-namespace or per-service that handles L7 processing for traffic between workloads opted into the ambient mesh." — [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/) |
| **per-namespace** | 1 ns 1 waypoint | "When enrolled with `--enroll-namespace`, a waypoint serves all services in the namespace." — [Istio waypoint apply](https://istio.io/latest/docs/reference/commands/istioctl/#istioctl-waypoint-apply) |
| **per-service** | 1 service 1 waypoint | "A Gateway with `istio.io/waypoint-for: service` label and a service-targeted listener enrolls only that service." — Istio Waypoint 文档 |
| **gatewayClassName: istio-waypoint** | 告诉 K8s Gateway API 这是 waypoint | "The `istio-waypoint` GatewayClass is registered by Istio when ambient components are installed." — [Istio Ambient Install](https://istio.io/latest/docs/ambient/install/) |
| **HBONE** | ztunnel ↔ waypoint 隧道协议 | "HBONE is the HTTP/2 + mTLS tunnel protocol used by ztunnel to forward traffic to waypoints." — [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/) |

---

## 3. per-namespace vs per-service:选哪个

| 维度 | per-namespace | per-service |
|---|---|---|
| **资源占用** | 1 waypoint(ns 共享) | N waypoints(每个 service) |
| **L7 隔离度** | ns 内共享 L7 策略 | 每个 service 独立 L7 配置 |
| **适用场景** | 团队自治 ns(1 team / 1 ns) | 多团队共享 ns,需要 service 级隔离 |
| **配置复杂度** | 低 | 高(每个 waypoint 独立 Gateway CR) |
| **故障域** | ns 内流量全部受单 waypoint 影响 | 单 service 故障不影响其他 |
| **HA 推荐副本** | 2 | 1-2(资源更敏感) |
| **本场景推荐度** | ⭐⭐⭐ | ⭐ (一般不用) |

### 本场景推荐 per-namespace 的理由

1. 你已有 ListenerSet 多租户 = ns 边界清晰(每个 team 一个 ns)
2. dev 集群资源有限(e2-medium),per-service 会爆资源
3. 你的 L7 策略粒度 = "team 内服务间",刚好对应 ns 级
4. 未来如需 per-service 隔离,**可叠加**(在同 ns 内,某些 service 单独 enroll)

---

## 4. 部署方式:3 选 1

### 方式 A:`istioctl waypoint apply`(最简)

```bash
# 给某个 ns 部署 waypoint,自动 enroll 该 ns 所有 service
istioctl waypoint apply -n team-a-runtime --enroll-namespace
```

**做了什么**:
1. 创建 Gateway 资源 `waypoint`(`gatewayClassName: istio-waypoint`)
2. 创建对应 Deployment(2 副本)+ Service
3. 给 ns 打 label `istio.io/use-waypoint=waypoint`

### 方式 B:显式 Gateway YAML(可审计)

```yaml
# waypoint-team-a.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: waypoint
  namespace: team-a-runtime
  labels:
    istio.io/waypoint-for: service     # 关键 label
spec:
  gatewayClassName: istio-waypoint     # 关键 className
  listeners:
    - name: mesh
      port: 15008                      # HBONE 端口(Istio 强制)
      protocol: HBONE
      # 注意:waypoint 不配 TLS,这是 mesh 内部协议
```

```bash
kubectl apply -f waypoint-team-a.yaml

# 重要:显式 enroll ns(方式 A 自动做,方式 B 要手动)
kubectl label namespace team-a-runtime istio.io/use-waypoint=waypoint --overwrite
```

### 方式 C:Helm chart(批量部署)

```bash
# Istio 提供 waypoint chart,适合一次部署多个 ns
helm upgrade --install waypoint-team-a oci://gcr.io/istio-release/charts/waypoint \
  --namespace team-a-runtime \
  --create-namespace \
  --version 1.30.3
```

---

## 5. HA 设计:Deployment 模板

> 来源:`~/git/knowledge/gcp/asm/gloo/waypoint.md` §9.2,适配你 K8s Gateway API 模式。

### 5.1 副本数:2(标准)

```yaml
# 通过 K8s Gateway API 的 spec.replicas 设置(Gateway API ≥ v1.1 支持)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: waypoint
  namespace: team-a-runtime
  labels:
    istio.io/waypoint-for: service
spec:
  gatewayClassName: istio-waypoint
  replicas: 2                 # HA 标准
  listeners:
    - name: mesh
      port: 15008
      protocol: HBONE
```

### 5.2 反亲和(防双副本同节点)

waypoint 由 Istio controller 根据 Gateway 自动生成 Deployment,
但 controller 1.27+ 已经默认加 podAntiAffinity。
如果你用 Helm 或手动管理,显式加:

```yaml
podTemplate:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: waypoint
          topologyKey: kubernetes.io/hostname    # 强制跨节点
```

### 5.3 PDB(PodDisruptionBudget)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: waypoint
  namespace: team-a-runtime
spec:
  minAvailable: 1              # 至少 1 个副本可用
  selector:
    matchLabels:
      app.kubernetes.io/name: waypoint
```

### 5.4 资源配额

| 维度 | 推荐值(每个 waypoint pod) |
|---|---|
| requests.cpu | 100m |
| requests.memory | 128Mi |
| limits.cpu | 500m |
| limits.memory | 512Mi |

本场景 dev 集群(每节点 940m allocatable)的预算:
- 2 个 ns 各 1 waypoint = 2 × 2 pod × 100m = 400m(还剩 ~540m 给 ztunnel + istiod + 业务)

---

## 6. 验证清单

```bash
# 1. Gateway 资源已创建
kubectl get gateway -n team-a-runtime
# 预期:
# NAME      CLASS            ADDRESS     PORTS
# waypoint  istio-waypoint   10.x.x.x    15008

# 2. Waypoint pod 跑起来
kubectl get pods -n team-a-runtime -l app.kubernetes.io/name=waypoint
# 预期:2/2 Running

# 3. ns label 正确
kubectl get ns team-a-runtime --show-labels
# 预期含:
#   istio.io/dataplane-mode=ambient
#   istio.io/use-waypoint=waypoint

# 4. L7 流量确实经过 waypoint
# (从一个 ambient ns 的 pod 打另一个 ambient ns 的 pod)
kubectl exec -n team-a-runtime <pod-a> -- \
  curl -s http://<pod-b-svc>:80/healthz

# 在 waypoint pod 上看 access log(应该出现上面请求)
kubectl logs -n team-a-runtime -l app.kubernetes.io/name=waypoint --tail=20
# 应看到 HTTP/2 200 请求记录
```

---

## 7. 升级与维护

| 操作 | 步骤 |
|---|---|
| 升 waypoint 版本 | 跟随 istiod 版本,改 `tag` 字段 + `helm upgrade ztunnel`(它不影响 waypoint,waypoint 滚动重启由 controller 触发) |
| 临时禁用某 waypoint | `kubectl label namespace team-a-runtime istio.io/use-waypoint-`(移除 enroll label) |
| 删除 waypoint | `kubectl delete gateway waypoint -n team-a-runtime` |
| 完全回滚 | 见 04 文 runtime-migration |

---

## 8. 反向:Waypoint 不适用的情况

- 业务 ns **完全无 L7 需求,只需要 mTLS**:可不部署 waypoint,ztunnel 直连更轻
- 业务 pod 需要**完全绕过 mesh**(极少见,如特殊 eBPF 探针):保留 sidecar 模式
- 入口流量(L7 路由):waypoint 不替代 ingress Gateway,**入口 Gateway 仍是 K8s Gateway API Gateway**

---

## 9. 本场景的 waypoint 蓝图

> dev 集群当前/计划结构:

```text
istio-system ns
└─ istiod (2 rep)
└─ istio-cni DaemonSet
└─ ztunnel DaemonSet

业务 ns(假设 2 个)
├─ team-a-runtime ns
│  ├─ label: istio.io/dataplane-mode=ambient
│  ├─ label: istio.io/use-waypoint=waypoint
│  ├─ waypoint Gateway (2 rep pod)
│  ├─ app pods (无 sidecar)
│  └─ AuthorizationPolicy / PeerAuthentication (用 targetRefs 绑 waypoint)
└─ team-b-runtime ns (同上)

ingress ns(不变)
├─ abjx-gw-int Gateway (gatewayClassName: istio,sidecar 模式)
└─ ListenerSet 多租户
```

---

## 10. References

- [Istio Waypoint 官方](https://istio.io/latest/docs/ambient/usage/waypoint/) — 权威部署指南
- [Istio Ambient Install](https://istio.io/latest/docs/ambient/install/) — `istio-waypoint` GatewayClass 注册
- [K8s Gateway API spec](https://gateway-api.sigs.k8s.io/api-types/gateway/) — Gateway 资源 spec(含 `replicas` 字段说明)
- [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/) — waypoint 在流量分层中的位置
- [Solo blog: Waypoint 部署模型](https://www.solo.io/blog/istio-ambient-waypoint-proxy-deployment-model-explained) — per-ns vs per-service 的对比
- 同仓库 `~/git/knowledge/gcp/asm/gloo/waypoint.md` — 已有 Waypoint 详解(本篇在它的基础上给出**本场景**的精简版 + HA 模板)