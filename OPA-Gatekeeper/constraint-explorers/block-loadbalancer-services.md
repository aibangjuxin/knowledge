# K8sBlockLoadBalancer 禁止 LoadBalancer Service

## 概述

`K8sBlockLoadBalancer` 是一个简单但关键的 Constraint，用于**阻止用户在集群中创建 `type: LoadBalancer` 的 Service**。

在云原生架构中，LoadBalancer Service 会向云厂商申请公网 IP 和负载均衡器，具有真实的财务成本和安全攻击面。默认允许任何人创建 LoadBalancer 是危险的。

---

## 核心概念

### 这个 Constraint 做什么

```
用户尝试创建:
apiVersion: v1
kind: Service
spec:
  type: LoadBalancer   ← 被阻止

拒绝理由: "User is not allowed to create service of type LoadBalancer"
```

### 模板信息

| 属性 | 值 |
|------|-----|
| **ConstraintTemplate Name** | `k8sblockloadbalancer` |
| **Kind** | `K8sBlockLoadBalancer` |
| **版本** | 1.0.0 |
| **来源** | [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general/block-loadbalancer-services) |

---

## Rego 逻辑解析

```rego
package k8sblockloadbalancer

violation[{"msg": msg}] {
  input.review.kind.kind == "Service"
  input.review.object.spec.type == "LoadBalancer"
  msg := "User is not allowed to create service of type LoadBalancer"
}
```

解读：
1. `input.review` 是 Gatekeeper 注入的 AdmissionRequest 对象
2. `input.review.kind.kind` 取出资源的 Kind（这里是 `Service`）
3. `input.review.object.spec.type` 取出 Service 的 type 字段
4. 如果 type == `"LoadBalancer"` → 返回 violation，拒绝创建

**这个 Rego 没有参数**，是纯粹的"禁止型"约束，无法通过 YAML 配置参数来调整行为（不同于 `K8sRequiredLabels` 可以配置 label key）。

---

## 完整 Constraint YAML

### 最简版本（deny 模式）

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockLoadBalancer
metadata:
  name: block-all-loadbalancer-services
spec:
  enforcementAction: deny     # 阻止创建
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
```

### dryrun 模式（先审计，不阻止）

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockLoadBalancer
metadata:
  name: block-all-loadbalancer-services-dryrun
spec:
  enforcementAction: dryrun   # 只记录，不阻止
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
```

---

## 应用命令

```bash
# 应用 deny 版本
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockLoadBalancer
metadata:
  name: block-all-loadbalancer-services
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
EOF

# 应用 dryrun 版本（先审计）
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockLoadBalancer
metadata:
  name: block-all-loadbalancer-services-dryrun
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
EOF
```

---

## 验证 Constraint

```bash
# 查看已创建的约束
kubectl get k8sblockloadbalancer

# 查看详细状态和 violations
kubectl describe k8sblockloadbalancer block-all-loadbalancer-services

# 查看 violations（dryrun 模式下）
kubectl get k8sblockloadbalancer block-all-loadbalancer-services-dryrun \
  -o jsonpath='{.status.violations}' | jq '.'
```

---

## 测试：触发违规

```bash
# 尝试创建一个 LoadBalancer Service
kubectl run lb-test --image=nginx --port=80 --type=LoadBalancer

# 预期结果（deny 模式）：
# Error from server: admission webhook "validation.gatekeeper.sh" denied the request:
# User is not allowed to create service of type LoadBalancer
```

---

## 实际应用场景

### 场景 1：严格网络隔离

在金融、政务等高安全要求环境中，不允许任何公网暴露。通过 Gatekeeper 阻止所有 LoadBalancer，强制使用 Ingress / Gateway API 等更可控的暴露方式。

```
K8sBlockLoadBalancer (deny)
  ↓
所有流量必须通过 Ingress / Gateway API
  ↓
Cloud Armor / WAF 统一防护
```

### 场景 2：成本控制

LoadBalancer 在各大云厂商都是按小时计费。阻止开发者随意创建 LoadBalancer，由平台团队统一管理。

### 场景 3：GKE + Network Policy 组合

配合 GKE 的 USC（微服务服务账号）和 Network Policy，阻止不合规的服务暴露。

---

## 常见问题

### Q1: 一定要完全阻止 LoadBalancer 吗？

不一定。可以在 dryrun 模式下运行一段时间，审计现有的 LoadBalancer Service，确认业务影响后再切换到 deny。

### Q2: 如何允许特定命名空间使用 LoadBalancer？

当前模板**不支持参数化**，无法通过配置允许特定 namespace。如果需要更灵活的控制，需要基于此模板自定义修改 Rego（添加 `excludedNamespaces` 或 `allowedNamespaces` 参数）。

自定义修改示例思路：

```rego
# 添加 allowedNamespaces 参数的修改思路
violation[{"msg": msg}] {
  input.review.kind.kind == "Service"
  input.review.object.spec.type == "LoadBalancer"
  namespace := input.review.namespace
  not input.parameters.allowedNamespaces[_] == namespace
  msg := "LoadBalancer not allowed in this namespace"
}
```

### Q3: ClusterIP / NodePort 会被阻止吗？

**不会**。这个模板只检查 `spec.type == "LoadBalancer"`，ClusterIP 和 NodePort 不受影响。

### Q4: 阻止后业务需要 LoadBalancer 怎么办？

引导使用 Ingress 或 Gateway API。GKE 上推荐使用 Gateway API + Google Cloud Load Balancer：

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
spec:
  gatewayClassName: gke-l7-global-external-managed
```

---

## 与 K8sBlockNodePort 的关系

这两个 Constraint 通常**配合使用**，共同限制 Service 的暴露方式：

| Constraint | 阻止的 Service 类型 |
|------------|-------------------|
| `K8sBlockLoadBalancer` | `type: LoadBalancer` |
| `K8sBlockNodePort` | `type: NodePort` |

**推荐组合**：

```yaml
# 组合1: 完全阻止（仅允许 ClusterIP）
K8sBlockLoadBalancer (deny)
K8sBlockNodePort (deny)

# 组合2: 只阻止 LoadBalancer（NodePort 可用于内部集群通信）
K8sBlockLoadBalancer (deny)
# K8sBlockNodePort 不启用
```

---

## 快速命令参考

```bash
# 应用
kubectl apply -f k8sblockloadbalancer.yaml

# 查看约束
kubectl get k8sblockloadbalancer

# 查看 violations
kubectl get k8sblockloadbalancer <name> -o jsonpath='{.status.violations}' | jq

# 删除
kubectl delete k8sblockloadbalancer <name>

# 切换为 deny（从 dryrun）
kubectl patch k8sblockloadbalancer <name> \
  --type=merge -p '{"spec":{"enforcementAction":"deny"}}'
```

---

## 源文件路径

- ConstraintTemplate: `library/general/block-loadbalancer-services/template.yaml`
- Samples: `library/general/block-loadbalancer-services/samples/`
