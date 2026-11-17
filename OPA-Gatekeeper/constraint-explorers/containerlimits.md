# K8sContainerLimits 容器资源限制详解

## 概述

`K8sContainerLimits` 是 Gatekeeper 库中最重要、最实用的 Constraint 之一。它**强制要求所有容器必须设置 CPU 和内存 limits**，并可限制最大允许值。

没有资源限制的容器是 Kubernetes 集群的"定时炸弹"——一个失控的容器可以耗尽节点的所有资源，影响同节点上的其他 Pod。

---

## 核心概念

### 这个 Constraint 做什么

```
检查每个 Pod 的每个容器：
  ├── 必须有 resources.limits.memory
  ├── 必须有 resources.limits.cpu
  └── limits 值不能超过配置的 max 值

如果不满足 → violation
```

### 模板信息

| 属性 | 值 |
|------|-----|
| **ConstraintTemplate Name** | `k8scontainerlimits` |
| **Kind** | `K8sContainerLimits` |
| **版本** | 1.1.0 |
| **来源** | [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general/containerlimits) |

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `cpu` | string | 最大允许的 CPU limit（不含单位，如 `"4"` 表示 4 核）。设为 `-1` 可禁用 |
| `memory` | string | 最大允许的内存 limit（如 `"16Gi"`）。不支持 `-1` 禁用 |
| `exemptImages` | array[string] | 豁免的镜像列表（支持 `*` 前缀匹配） |

---

## Rego 核心逻辑

```rego
# 1. 检查容器是否有 limits
missing(obj, field) = true {
  not obj[field]
}
missing(obj, field) = true {
  obj[field] == ""
}

# 2. 检查容器是否被豁免
import data.lib.exempt_container.is_exempt

# 3. 检查是否超过 max 值
output_review_input(review)          # 从 input 获取 container 信息
containers[container]                # 遍历所有容器

# 4. 对于非豁免容器，执行检查
violation[{"msg": msg}] {
  container := containers[_]
  not is_exempt(container.image, exempt_images)
  missing(container.resources.limits, "cpu")
  msg := "Container <name> does not have CPU limit"
}

violation[{"msg": msg}] {
  container := containers[_]
  not is_exempt(container.image, exempt_images)
  missing(container.resources.limits, "memory")
  msg := "Container <name> does not have memory limit"
}

violation[{"msg": msg}] {
  container := containers[_]
  not is_exempt(container.image, exempt_images)
  cpu := container.resources.limits.cpu
  not compare(cpu, "<=", input.parameters.cpu)
  msg := sprintf("Container <name> CPU limit %v is higher than the maximum allowed of %v", [cpu, input.parameters.cpu])
}
```

---

## 完整 Constraint YAML

### 基础版本：必须设置 limits，不设上限

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-must-have-limits
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    - gmp-system
  parameters:
    # 不设置 cpu/memory 意味着只强制要求有 limits，不限制最大值
    # 设置为 -1 或空表示不限制
    cpu: "-1"
    memory: "-1"
```

### 生产版本：强制 limits 并设置最大值

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-production
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    - gmp-system
    - monitoring
  parameters:
    cpu: "4"       # 最多 4 核
    memory: "16Gi" # 最多 16Gi
    exemptImages:   # 豁免这些镜像
    - "gke.gcr.io/*"
    - "registry.k8s.io/pause*"
```

### 豁免特定镜像

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-with-exempt
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    cpu: "8"
    memory: "32Gi"
    exemptImages:
    - "gcr.io/google_containers/pause*"    # K8s pause 容器
    - "eks.amazonaws.com/pause*"           # AWS pause 容器
    - "registry.cn-hangzhou.aliyuncs.com/*" # 阿里云基础镜像
```

---

## 应用命令

```bash
# 应用
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-must-have-limits
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
  parameters:
    cpu: "4"
    memory: "16Gi"
    exemptImages:
    - "gke.gcr.io/*"
EOF

# 查看约束
kubectl get k8scontainerlimits

# 查看 violations
kubectl get k8scontainerlimits container-must-have-limits \
  -o jsonpath='{.status.violations}' | jq '.'

# 详细描述
kubectl describe k8scontainerlimits container-must-have-limits
```

---

## 测试：触发违规

### 测试 1：完全没有 limits

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: no-limits-pod
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
    # 无 resources 字段 → 触发 violation
```

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: no-limits-pod
spec:
  containers:
  - name: nginx
    image: nginx:latest
EOF

# 预期拒绝:
# Container <nginx> does not have memory limit
# Container <nginx> does not have CPU limit
```

### 测试 2：有 limits 但超过最大值

```yaml
containers:
- name: nginx
  image: nginx:latest
  resources:
    limits:
      cpu: "8"      # 超过 max 4 → 触发 violation
      memory: "32Gi" # 超过 max 16Gi → 触发 violation
```

---

## 实际应用场景

### 场景 1：多租户集群资源保护

在多租户集群中，每个租户的 namespace 设置资源配额（ResourceQuota），但租户内部的 Pod 仍然可能没有 limits。`K8sContainerLimits` 强制所有容器都设置 limits，配合 ResourceQuota 防止资源耗尽。

```
Namespace quota: 100 CPU / 200Gi memory
  ↑
  └── K8sContainerLimits: 强制每个容器有 limits
        └── ResourceQuota: 限制 namespace 总配额
```

### 场景 2：开发/生产差异化策略

```
dev namespace: K8sContainerLimits (cpu: "8", memory: "32Gi", dryrun)
prod namespace: K8sContainerLimits (cpu: "4", memory: "16Gi", deny)
```

### 场景 3：豁免基础组件

```yaml
parameters:
  exemptImages:
  - "gke.gcr.io/*"                    # GKE 系统组件
  - "registry.k8s.io/pause*"          # Pause 容器
  - "sha256*"                          # SHA 固定的镜像是安全的
```

---

## 资源格式说明

### CPU 格式

| 格式 | 示例 | 说明 |
|------|------|------|
| 整数（millicores） | `"1000"` | 1000m = 1 核 |
| 浮点数 | `"0.5"` | 0.5 核 |
| 小数 millicores | `"500m"` | 500 millicores |

### Memory 格式

| 格式 | 示例 |
|------|------|
| Ei, Pi, Ti, Gi, Mi, Ki | `"16Gi"`, `"512Mi"`, `"1Gi"` |
| E, P, T, G, M, K（Power of 2） | `"16G"`, `"512M"` |
| 字节数 | `"17179869184"` |

---

## 与 K8sRequiredLabels 的协同

这两个 Constraint 经常配合使用，作为 Pod 入场的"最低门槛"：

```yaml
# 必须有标签
K8sRequiredLabels
  labels:
  - key: "app"
  - key: "environment"
  - key: "team"

# 必须有资源限制
K8sContainerLimits
  cpu: "8"
  memory: "32Gi"

# 两者缺一不可
# → 没有标签 → 拒绝
# → 没有 limits → 拒绝
```

---

## 快速命令参考

```bash
# 应用
kubectl apply -f k8scontainerlimits.yaml

# 查看
kubectl get k8scontainerlimits

# 查看 violations
kubectl get k8scontainerlimits <name> \
  -o jsonpath='{.status.violations}' | jq

# 查看某个 namespace 的 violations
kubectl get k8scontainerlimits <name> \
  -o jsonpath='{.status.violations}' | jq '.[] | select(.namespace == "my-ns")'

# 切换模式
kubectl patch k8scontainerlimits <name> \
  --type=merge -p '{"spec":{"enforcementAction":"dryrun"}}}'

# 删除
kubectl delete k8scontainerlimits <name>
```

---

## 源文件路径

- ConstraintTemplate: `library/general/containerlimits/template.yaml`
- Samples: `library/general/containerlimits/samples/`
  - `container-must-have-limits/`
  - `container-ignore-cpu-limits/`
