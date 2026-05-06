# K8sReplicaLimits 限制 Deployment/ReplicaSet 副本数

## 概述

`K8sReplicaLimits` 限制 Kubernetes workload（如 Deployment、ReplicaSet）的副本数量，防止单个应用消耗过多集群资源或导致过度冗余。

---

## 核心概念

### 模板信息

| 属性 | 值 |
|------|-----|
| **ConstraintTemplate Name** | `k8sreplicalimits` |
| **Kind** | `K8sReplicaLimits` |
| **来源** | [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general/replicalimits) |

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `min` | integer | 最少副本数 |
| `max` | integer | 最多副本数 |

---

## Rego 逻辑解析

```rego
package k8sreplicalimits

violation[{"msg": msg}] {
  input.review.kind.kind == "Deployment"
  input.review.kind.group == "apps"
  replicas := input.review.object.spec.replicas
  input.parameters.min
  replicas < input.parameters.min
  msg := sprintf("Deployment <%v> replicas must be at least %v, got %v",
    [input.review.object.metadata.name, input.parameters.min, replicas])
}

violation[{"msg": msg}] {
  input.review.kind.kind == "Deployment"
  input.review.kind.group == "apps"
  replicas := input.review.object.spec.replicas
  input.parameters.max
  replicas > input.parameters.max
  msg := sprintf("Deployment <%v> replicas must be at most %v, got %v",
    [input.review.object.metadata.name, input.parameters.max, replicas])
}
```

---

## 完整 Constraint YAML

### 限制副本数范围

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sReplicaLimits
metadata:
  name: replica-limits
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "ReplicaSet"]
    excludedNamespaces:
    - kube-system
  parameters:
    min: "1"    # 最少 1 个副本
    max: "10"   # 最多 10 个副本
```

### 生产环境：最小副本保障

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sReplicaLimits
metadata:
  name: production-replica-limits
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
    excludedNamespaces:
    - kube-system
    - monitoring
  parameters:
    min: "2"    # 生产环境最少 2 副本，保证高可用
    max: "50"
```

### 仅设置最大副本数

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sReplicaLimits
metadata:
  name: max-replicas-only
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    max: "5"
    # 不设置 min → 不限制最少副本
```

---

## 应用命令

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sReplicaLimits
metadata:
  name: replica-limits
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    min: "1"
    max: "10"
EOF

# 查看
kubectl get k8sreplicalimits

# 查看 violations
kubectl get k8sreplicalimits replica-limits \
  -o jsonpath='{.status.violations}' | jq '.'
```

---

## 测试：触发违规

### 测试 1：副本数超过最大值

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oversized-app
spec:
  replicas: 100    # 超过 max: 10 → 触发 violation
  selector:
    matchLabels:
      app: myapp
  template:
    spec:
      containers:
      - name: myapp
        image: nginx
```

### 测试 2：副本数低于最小值

```yaml
spec:
  replicas: 0    # 低于 min: 1 → 触发 violation
```

---

## 实际应用场景

### 场景 1：开发环境成本控制

```
dev namespace:
  min: 1, max: 2   → 节省资源

prod namespace:
  min: 2, max: 50  → 保证高可用
```

### 场景 2：配合 HPA 使用

HPA（水平 Pod 自动扩缩容）可以动态调整副本数。建议设置一个合理的 max 值：

```yaml
# Deployment
spec:
  replicas: 3      # 初始 3 副本
---
# HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
spec:
  maxReplicas: 20   # ← 必须 <= K8sReplicaLimits 的 max
  minReplicas: 2
```

### 场景 3：StatefulSet 副本限制

```yaml
match:
  kinds:
  - apiGroups: ["apps"]
    kinds: ["Deployment", "ReplicaSet", "StatefulSet"]
```

---

## 常见问题

### Q1: HPA 会触发这个 Constraint 吗？

不会。HPA 修改 `spec.replicas` 字段时，会触发 Gatekeeper 校验（因为是 UPDATE 操作）。如果 HPA 试图扩容超过 max，Gatekeeper 会阻止。

### Q2: 如何同时管理多个 workload 类型？

```yaml
match:
  kinds:
  - apiGroups: ["apps"]
    kinds: ["Deployment", "ReplicaSet", "StatefulSet"]
```

### Q3: min=0 有什么风险？

`min=0` 允许副本数归零，可能导致服务中断。一般生产环境设置 `min >= 1`。

---

## 快速命令参考

```bash
# 应用
kubectl apply -f k8sreplicalimits.yaml

# 查看
kubectl get k8sreplicalimits

# 查看 violations
kubectl get k8sreplicalimits <name> \
  -o jsonpath='{.status.violations}' | jq

# 删除
kubectl delete k8sreplicalimits <name>
```

---

## 源文件路径

- ConstraintTemplate: `library/general/replicalimits/template.yaml`
- Samples: `library/general/replicalimits/samples/`
