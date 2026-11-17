# K8sRequiredProbes 强制健康检查探针

## 概述

`K8sRequiredProbes` 强制所有容器必须配置 **readinessProbe** 和/或 **livenessProbe**。没有健康检查的容器在 Kubernetes 中是危险的——负载均衡器可能将流量发送到尚未启动完成的 Pod，或发送到已崩溃的 Pod。

---

## 核心概念

### 这个 Constraint 做什么

```
检查每个容器:
  └── 必须配置指定类型的探针

必须: readinessProbe 或 livenessProbe（可配置）
探针类型: tcpSocket, exec, httpGet（可配置）
```

### 模板信息

| 属性 | 值 |
|------|-----|
| **ConstraintTemplate Name** | `k8srequiredprobes` |
| **Kind** | `K8sRequiredProbes` |
| **版本** | 1.0.1 |
| **来源** | [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general/requiredprobes) |

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `probes` | array[string] | 必须配置的探针列表，如 `["readinessProbe", "livenessProbe"]` |
| `probeTypes` | array[string] | 探针必须包含的字段类型，如 `["tcpSocket", "exec", "httpGet"]` |

---

## Rego 核心逻辑

```rego
package k8srequiredprobes

probe_type_set = probe_types {
    probe_types := {type | type := input.parameters.probeTypes[_]}
}

violation[{"msg": msg}] {
    not is_update(input.review)              # 探针字段不可变，UPDATE 操作跳过
    container := input.review.object.spec.containers[_]
    probe := input.parameters.probes[_]
    probe_is_missing(container, probe)        # 检查探针是否存在
    msg := get_violation_message(container, input.review, probe)
}

probe_is_missing(ctr, probe) = true {
    not ctr[probe]                           # 容器没有该探针字段
}

probe_is_missing(ctr, probe) = true {
    probe_field_empty(ctr, probe)            # 探针存在但字段为空
}

probe_field_empty(ctr, probe) = true {
    probe_fields := {field | ctr[probe][field]}
    diff_fields := probe_type_set - probe_fields
    count(diff_fields) == count(probe_type_set)  # 探针没有任何指定类型的字段
}

# 特殊处理 UPDATE 操作（探针字段不可变）
is_update(review) {
    review.operation == "UPDATE"
}
```

---

## 完整 Constraint YAML

### 最严格：同时要求 readinessProbe 和 livenessProbe

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredProbes
metadata:
  name: require-all-probes
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
  parameters:
    probes:
    - "readinessProbe"    # 必须有就绪探针
    - "livenessProbe"     # 必须有存活探针
    probeTypes:
    - "tcpSocket"
    - "exec"
    - "httpGet"
```

### 只要求 livenessProbe（允许无 readinessProbe）

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredProbes
metadata:
  name: require-liveness-probe
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
  parameters:
    probes:
    - "livenessProbe"
    probeTypes:
    - "tcpSocket"
    - "exec"
    - "httpGet"
```

### 只要求 readinessProbe（适用于有外部依赖的服务）

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredProbes
metadata:
  name: require-readiness-probe
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    probes:
    - "readinessProbe"
    probeTypes:
    - "tcpSocket"
    - "exec"
    - "httpGet"
```

### startupProbe（K8s 1.16+）也纳入要求

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredProbes
metadata:
  name: require-all-probes-with-startup
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
  parameters:
    probes:
    - "readinessProbe"
    - "livenessProbe"
    - "startupProbe"
    probeTypes:
    - "tcpSocket"
    - "exec"
    - "httpGet"
```

---

## 应用命令

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredProbes
metadata:
  name: require-all-probes
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    probes:
    - "readinessProbe"
    - "livenessProbe"
    probeTypes:
    - "tcpSocket"
    - "exec"
    - "httpGet"
EOF

# 查看
kubectl get k8srequiredprobes

# 查看 violations
kubectl get k8srequiredprobes require-all-probes \
  -o jsonpath='{.status.violations}' | jq '.'
```

---

## 测试：触发违规

### 测试 1：完全没有探针

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: no-probe-pod
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
    # 无 readinessProbe
    # 无 livenessProbe

# 预期拒绝:
# Container <nginx> in your <Pod> <no-probe-pod> has no <readinessProbe>
# Container <nginx> in your <Pod> <no-probe-pod> has no <livenessProbe>
```

### 测试 2：有探针但类型不符合要求

如果 `probeTypes: ["httpGet"]` 但探针是 `tcpSocket`：

```yaml
containers:
- name: app
  image: myapp:v1
  readinessProbe:
    tcpSocket:        # ← tcpSocket 类型
      port: 8080
    initialDelaySeconds: 5
    periodSeconds: 10

# 如果 probeTypes 只允许 httpGet，上面的 tcpSocket 会被拒绝
```

### 测试 3：探针存在但配置不完整

```yaml
# 探针字段存在但是空的 → 触发 violation
readinessProbe: {}    # 空对象 → 不满足任何 probeType

# 必须有实际的探针配置
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
```

### 测试 4：合规的 Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: healthy-app
spec:
  containers:
  - name: app
    image: myapp:v1
    ports:
    - containerPort: 8080
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 10
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 15
      periodSeconds: 20
# ✓ 通过
```

---

## 实际应用场景

### 场景 1：生产环境必须双探针

```
生产环境:
  K8sRequiredProbes (deny)
    probes: [readinessProbe, livenessProbe]
    probeTypes: [httpGet, tcpSocket]

开发环境:
  K8sRequiredProbes (dryrun)
    只记录，不阻止
```

### 场景 2：数据库等有状态服务

```yaml
# 数据库服务通常只需要 readinessProbe，不需要 livenessProbe
probes: [readinessProbe]
```

### 场景 3：JVM 应用（使用 exec）

```yaml
# Java/JVM 应用常用 exec 探针检查健康端点
parameters:
  probes: [readinessProbe, livenessProbe]
  probeTypes: [tcpSocket, exec, httpGet]
  # 允许 exec 类型（如 check_cluster_health.sh）
```

---

## 探针类型说明

Kubernetes 支持三种探针类型：

### httpGet — HTTP GET 请求

```yaml
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
    httpHeaders:
    - name: X-Custom-Header
      value: "value"
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3
```

### tcpSocket — TCP 端口检查

```yaml
readinessProbe:
  tcpSocket:
    port: 5432
  initialDelaySeconds: 5
  periodSeconds: 10
```

### exec — 执行命令

```yaml
livenessProbe:
  exec:
    command:
    - cat
    - /tmp/healthy
  initialDelaySeconds: 15
  periodSeconds: 20
```

---

## 与 K8sContainerLimits 的协同

这两个 Constraint 经常配合使用，作为 Pod 入场的"最低门槛"：

```yaml
# 必须有探针
K8sRequiredProbes
  probes: [readinessProbe, livenessProbe]

# 必须有资源限制
K8sContainerLimits
  cpu: "4"
  memory: "16Gi"

# 两者缺一不可 → 没有探针 → 拒绝
#                   没有 limits → 拒绝
```

---

## 常见问题

### Q1: probeTypes 是必需的吗？

如果不设置 `probeTypes`，Constraint 只检查探针字段是否存在，不检查类型。如果设置了 `probeTypes`，探针必须包含其中至少一种类型。

### Q2: UPDATE 操作为什么不检查探针？

探针字段在 Pod 创建后不可修改（Pod 的 spec 是不可变的）。UPDATE 操作时如果检查探针，所有已存在的 Pod 更新都会失败。

### Q3: 哪些 namespace 需要排除？

```yaml
excludedNamespaces:
- kube-system           # 系统组件
- gatekeeper-system    # Gatekeeper 自身
- istio-system         # Istio 注入的 sidecar
- cert-manager         # cert-manager
```

> ⚠️ 注意：排除系统 namespace 后，业务 namespace 必须强制探针，否则无法创建 Pod。

### Q4: sidecar 容器需要探针吗？

Istio/Envoy sidecar 本身不需要应用层探针，但如果 sidecar 在 `spec.containers` 中而不是 `spec.initContainers`，Gatekeeper 也会检查它。可以用 `excludedNamespaces` 或自定义 Rego 来处理。

---

## 快速命令参考

```bash
# 应用
kubectl apply -f k8srequiredprobes.yaml

# 查看
kubectl get k8srequiredprobes

# 查看 violations
kubectl get k8srequiredprobes <name> \
  -o jsonpath='{.status.violations}' | jq

# 查看某个 namespace 的违规 Pod
kubectl get k8srequiredprobes require-all-probes \
  -o jsonpath='{.status.violations}' \
  | jq '.[] | select(.namespace == "my-ns")'

# 更新探针要求
kubectl patch k8srequiredprobes require-all-probes \
  --type=merge \
  -p '{"spec":{"parameters":{"probes":["readinessProbe"]}}}'

# 删除
kubectl delete k8srequiredprobes <name>
```

---

## 源文件路径

- ConstraintTemplate: `library/general/requiredprobes/template.yaml`
- Samples: `library/general/requiredprobes/samples/`
