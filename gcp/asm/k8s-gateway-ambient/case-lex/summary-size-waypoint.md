# summary-size-waypoint.md — Waypoint Sizing 知识点总结

> **作者**: architect-gcp Bot
> **日期**: 2026-09-25
> **范围**: 高度浓缩 — 9 条核心知识点
> **配套长文**: `analyze-waypoint.md` (§13 + §13.9 详细展开)
> **来源**: Solo 1.30/1.31 官方文档 + Istio 1.30+ 官方文档 + K8s Gateway API 1.2+ 规范

---

## 1. 核心问题

Waypoint Deployment 是 **istio controller 自动生成的**, 你**没有地方**在 `Gateway` spec 里直接写 `resources` / `containers` / `volumes` 这些 Pod 模板字段。

```
你的 Gateway YAML                   istio controller 自动生成
─────────────────                   ──────────────────
kind: Gateway                  ──►   kind: Deployment
spec:                                  spec:
  replicas: 2                            replicas: 2      ✓ (传递)
  listeners: [...]                       containers:
                                         - name: istio-proxy
                                           image: ...
                                           # ⚠️ resources 默认没有
```

---

## 2. 三层 sizing 设计 (Istio 1.30+ 原生支持)

| 层 | 资源 | 位置 | 作用 |
|---|---|---|---|
| **集群默认层** | ConfigMap `istio-waypoint-defaults` (label: `gateway.istio.io/defaults-for-class: istio-waypoint`) | `istio-system` ns | 所有 waypoint 的 baseline |
| **Gateway 覆盖层** | ConfigMap `<name>-options` | Waypoint 所在 ns | 单 waypoint patch |
| **物理 pod 层** | 由 controller 生成的 Deployment | 集群内 | 实际跑 |

合并方式 = **strategic merge patch**, 不是 replace:
- ns 层只写 `requests` → `limits` 仍**继承**集群 default
- ns 层完全不写 ConfigMap → 自动用集群 default

---

## 3. 控制 waypoint resources 的 3 种方式

| 方式 | 推荐度 | 适用 |
|---|---|---|
| **A. `waypoint-options` ConfigMap + `spec.infrastructure.parametersRef`** | ⭐⭐⭐ | Solo 1.30+ / OSS Istio 1.27+, 多租户场景 |
| **B. IstioOperator 全局 env** | ⭐ | 仅影响 istiod, waypoint 不一定读 |
| **C. Kyverno / OPA admission controller** | ⭐⭐ | 不能改 Istio controller 的集群 |

### 方式 A 核心 3 件套

```yaml
# 1. Gateway 引用 ConfigMap
spec:
  infrastructure:
    parametersRef:
      group: ""
      kind: ConfigMap
      name: waypoint-options    # ← 必须

# 2. ConfigMap 在 waypoint 同 ns
apiVersion: v1
kind: ConfigMap
metadata:
  name: waypoint-options
  namespace: <waypoint-ns>
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

# 3. (可选) 集群默认 ConfigMap
metadata:
  name: istio-waypoint-defaults
  namespace: istio-system
  labels:
    gateway.istio.io/defaults-for-class: istio-waypoint
```

---

## 4. 推荐 sizing (按集群规模)

| 集群规模 | waypoint requests | waypoint limits | replicas |
|---|---|---|---|
| **小型** (< 50 services) | cpu `100m`, mem `128Mi` | cpu `500m`, mem `512Mi` | 2 |
| **中型** (50-200) | cpu `200m`, mem `256Mi` | cpu `1`, mem `1Gi` | 2 |
| **大型** (200+) | cpu `500m`, mem `512Mi` | cpu `2`, mem `2Gi` | 2-5 (HPA) |

### 多租户 per-team 场景

| Tenant 规模 | requests | limits | replicas |
|---|---|---|---|
| **大团队** (Lex ba000000, 高流量) | cpu `500m`, mem `512Mi` | cpu `2`, mem `2Gi` | 2-5 (HPA) |
| 中团队 (50-200 svc) | cpu `200m`, mem `256Mi` | cpu `1`, mem `1Gi` | 2 |
| 小团队 / dev | cpu `100m`, mem `128Mi` | cpu `500m`, mem `512Mi` | 2 |
| 极小 / staging | cpu `50m`, mem `64Mi` | cpu `200m`, mem `256Mi` | 1 |

---

## 5. ⚠️ 黄金法则

- **requests** = 正常负载下的稳态值 (用于调度决策)
- **limits** = 流量峰值的 2-3 倍 (允许 burst, 防止失控)
- **request:limit 比例失衡** (例如 request: 100m, limit: 4) → Burstable QoS, burst 时跟 Guaranteed pod 抢资源
- **没设 limits** (BestEffort QoS) → 节点压力时优先被驱逐, PDB 也救不了

---

## 6. 5 种 resources 设错的后果

| 错误 | 后果 |
|---|---|
| request 太大 | 调度失败, waypoint pod Pending, L7 拦截全失效 |
| limit 太小 | 流量高峰 OOMKilled / throttled, AuthZ 间歇失效 |
| 没设 limits | BestEffort QoS, 节点压力时优先被驱逐 |
| request:limit 比例失衡 | Burstable QoS, 跟 Guaranteed pod 抢资源 |
| 多 waypoint 同样大 requests | 集群资源紧张时互相挤兑 |

---

## 7. ⚠️ 多租户场景的关键陷阱

> 你原 `01-waypoint-int.yaml` **缺** `spec.infrastructure.parametersRef` 字段。
> 没这个字段, ConfigMap **存在但不被引用**, per-ns 覆盖完全失效!

```yaml
spec:
  infrastructure:
    parametersRef:           # ← 必须显式加
      group: ""
      kind: ConfigMap
      name: waypoint-options
```

---

## 8. 验证命令 (5 条)

```bash
# 1. 集群默认 ConfigMap
kubectl get cm -n istio-system -l gateway.istio.io/defaults-for-class=istio-waypoint

# 2. tenant ns ConfigMap
kubectl get cm -n ba000000-lex-int waypoint-options

# 3. Gateway 引用了 ConfigMap
kubectl get gateway -n ba000000-lex-int waypoint-int \
  -o jsonpath='{.spec.infrastructure.parametersRef}'

# 4. 最终 Deployment 的 resources (合并后)
kubectl get deploy -n ba000000-lex-int waypoint-int \
  -o jsonpath='{.spec.template.spec.containers[0].resources}'

# 5. waypoint pod 真实使用
kubectl top pods -n ba000000-lex-int -l istio.io/gateway-name=waypoint-int
```

---

## 9. 一句话总结

> **Waypoint size = 集群默认 ConfigMap (baseline) + per-ns ConfigMap (patch, 应用在 baseline 之上) + Gateway `parametersRef` (引用), 三层联动; OSS Istio 1.27+ / Solo 1.30+ 原生支持, 多租户场景下 per-team sizing 是合理设计。**

---

## 参考链接

### 官方文档
- [Solo Configure waypoints (1.31)](https://docs.solo.io/istio/1.31.x/waypoints/configuration/) — **`GatewayClass default` + per-Gateway patch 机制**
- [Solo Configure waypoints (1.30)](https://docs.solo.io/istio/1.30.x/ambient/waypoints/configuration) — `waypoint-options` ConfigMap + strategic merge patch
- [Istio Configure waypoint proxies](https://istio.io/latest/docs/ambient/usage/waypoint/) — 权威部署指南

### K8s Gateway API
- [Gateway spec](https://gateway-api.sigs.k8s.io/api-types/gateway/) — Gateway 资源 spec
- [Infrastructure parameters reference](https://gateway-api.sigs.k8s.io/api-types/gateway/#infrastructure) — `spec.infrastructure.parametersRef` 字段

### 同目录
- `analyze-waypoint.md` — 详细展开(13 节, 含工作原理 + HA 设计 + per-ns/per-service + canary + Resources 配置完整版)
- `01-waypoint-int.yaml` — 当前 waypoint Gateway YAML (注意缺 `parametersRef`, 见 §7)
- `00-namespace-ba000000-lex-int.yaml` — ns 级 3 个 istio label
- `03-mesh-security.yaml` — AuthZ targetRefs 绑 waypoint

---

*Generated by architect-gcp Bot — 2026-09-25.*
*9 条核心知识点总结 — 浓缩自 analyze-waypoint.md §13 + §13.9。*