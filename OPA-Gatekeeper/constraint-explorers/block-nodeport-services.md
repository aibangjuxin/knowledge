# K8sBlockNodePort 禁止 NodePort Service

## 概述

`K8sBlockNodePort` 阻止在集群中创建 `type: NodePort` 的 Service。

NodePort 在每个 Kubernetes 节点上打开一个静态端口（30000-32767），使得任何知道节点 IP 的人都可以访问服务。这在金融、政务等高安全要求环境中是不可接受的。

---

## 核心概念

### 这个 Constraint 做什么

```
用户尝试创建:
apiVersion: v1
kind: Service
spec:
  type: NodePort      ← 被阻止
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080

拒绝理由: "User is not allowed to create service of type NodePort"
```

### 模板信息

| 属性 | 值 |
|------|-----|
| **ConstraintTemplate Name** | `k8sblocknodeport` |
| **Kind** | `K8sBlockNodePort` |
| **版本** | 1.0.0 |
| **来源** | [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general/block-nodeport-services) |

---

## Rego 逻辑解析

```rego
package k8sblocknodeport

violation[{"msg": msg}] {
  input.review.kind.kind == "Service"
  input.review.object.spec.type == "NodePort"
  msg := "User is not allowed to create service of type NodePort"
}
```

与 `K8sBlockLoadBalancer` 的逻辑几乎完全一致——都是检查 `spec.type` 字段。

---

## 完整 Constraint YAML

### deny 模式（阻止创建）

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockNodePort
metadata:
  name: block-all-nodeport-services
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
```

### dryrun 模式（先审计）

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockNodePort
metadata:
  name: block-all-nodeport-services-dryrun
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
```

---

## 应用命令

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockNodePort
metadata:
  name: block-all-nodeport-services
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
EOF
```

---

## 验证 Constraint

```bash
# 查看约束
kubectl get k8sblocknodeport

# 查看 violations（dryrun 模式）
kubectl get k8sblocknodeport block-all-nodeport-services-dryrun \
  -o jsonpath='{.status.violations}' | jq '.'

# 查看详细
kubectl describe k8sblocknodeport block-all-nodeport-services
```

---

## 测试：触发违规

```bash
# 尝试创建 NodePort Service
kubectl create ns nodeport-test
kubectl run nodeport-test --image=nginx -n nodeport-test \
  --port=80 --expose --type=NodePort

# 如果有 NodePort Service（用已有服务修改）
kubectl patch svc <existing-svc> -n <namespace> \
  -p '{"spec":{"type":"NodePort"}}'

# 预期结果（deny 模式）：
# Error from server: admission webhook "validation.gatekeeper.sh" denied the request:
# User is not allowed to create service of type NodePort
```

---

## 实际应用场景

### 场景 1：与 K8sBlockLoadBalancer 组合

```
推荐组合（严格模式）:
├── K8sBlockLoadBalancer (deny)  ← 阻止 LoadBalancer
└── K8sBlockNodePort (deny)       ← 阻止 NodePort

效果: 所有 Service 只能是 ClusterIP，
      外部访问必须走 Ingress / Gateway API
```

### 场景 2：仅阻止 NodePort，允许 LoadBalancer

在某些环境中，需要 LoadBalancer 做云厂商对接（CLB/ALB），但 NodePort 因为安全风险需要被阻止：

```
宽松模式:
├── K8sBlockNodePort (deny)   ← 阻止 NodePort
└── K8sBlockLoadBalancer (不启用)
```

### 场景 3：允许特定命名空间使用 NodePort

与 `K8sBlockLoadBalancer` 类似，当前模板不支持命名空间白名单。如果需要白名单，需要自定义 Rego：

```rego
# 自定义: 允许特定命名空间使用 NodePort
violation[{"msg": msg}] {
  input.review.kind.kind == "Service"
  input.review.object.spec.type == "NodePort"
  namespace := input.review.namespace
  not count(allowed_ns) > 0
  msg := "NodePort not allowed in this namespace"
} {
  input.review.kind.kind == "Service"
  input.review.object.spec.type == "NodePort"
  namespace := input.review.namespace
  allowed_ns := {"monitoring", "ingress"}
  not allowed_ns[namespace]
  msg := sprintf("NodePort only allowed in namespaces: %v", [allowed_ns])
}
```

---

## 与 LoadBalancer 的对比

| 对比维度 | K8sBlockLoadBalancer | K8sBlockNodePort |
|---------|---------------------|-----------------|
| **阻止的类型** | `type: LoadBalancer` | `type: NodePort` |
| **成本影响** | 高（云厂商 LB 按小时计费） | 低（仅占用节点端口） |
| **安全攻击面** | 高（公网 IP + LB） | 中（节点 IP + 固定端口） |
| **典型用户** | 平台安全团队 | 平台安全 + 网络团队 |
| **Rego 复杂度** | 极简 | 极简 |

---

## 快速命令参考

```bash
# 应用
kubectl apply -f k8sblocknodeport.yaml

# 查看约束
kubectl get k8sblocknodeport

# 查看 violations
kubectl get k8sblocknodeport <name> \
  -o jsonpath='{.status.violations}' | jq

# 删除
kubectl delete k8sblocknodeport <name>

# 切换模式
kubectl patch k8sblocknodeport <name> \
  --type=merge -p '{"spec":{"enforcementAction":"deny"}}}'
```

---

## 源文件路径

- ConstraintTemplate: `library/general/block-nodeport-services/template.yaml`
- Samples: `library/general/block-nodeport-services/samples/`
