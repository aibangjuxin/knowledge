# K8sImmutableFields 禁止修改特定字段（自定义模板）

## 概述

`immutablefields` 模式用于**保护特定字段在资源创建后不被修改**。这是 Gatekeeper 原生不提供但实际需求强烈的功能。

常见的不可变字段场景：
- `Deployment.spec.replicas` — 防止生产环境随意扩缩容
- `Service.spec.type` — 防止 ClusterIP 被改为 LoadBalancer
- `Ingress.spec.rules` — 防止修改入口规则
- `metadata.annotations` — 防止删除或修改关键注解

---

## 为什么 gatekeeper-library 没有这个模板

Gatekeeper 官方认为 `immutablefields` 属于**变更控制**范畴，而非**策略合规**范畴。这是合理的架构划分——OPA Rego 擅长复杂条件判断，但字段不可变检查有更原生的方式：

| 方式 | 工具 | 适用场景 |
|------|------|---------|
| **Admission Webhook** | Gatekeeper Mutation | 注入默认值、修改请求 |
| **变更控制** | OPA Gatekeeper | 阻止非法变更 |
| **字段锁定** | Kubernetes 1.18+ | `fields` 字段只读 |

Gatekeeper 官方推荐使用 **OPA Gatekeeper 的 `mutation` + `constraint** 组合来实现不可变字段需求**。

---

## 实现方式一：Rego Constraint（推荐）

### 约束模板设计思路

```
原理:
  1. Gatekeeper 接收 admissionRequest
  2. 如果 operation == "CREATE" → 跳过检查（新建资源可以通过）
  3. 如果 operation == "UPDATE" → 检查被修改的字段
  4. 如果被修改的字段在禁止列表中 → violation
```

### 自定义 ConstraintTemplate

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8simmutablefields
  annotations:
    metadata.gatekeeper.sh/title: "Immutable Fields"
    metadata.gatekeeper.sh/version: 1.0.0
    description: >-
      Prevents modifications to specified fields after resource creation.
spec:
  crd:
    spec:
      names:
        kind: K8sImmutableFields
      validation:
        openAPIV3Schema:
          type: object
          properties:
            fieldSpecs:
              type: array
              description: "List of field specs to protect from modification"
              items:
                type: object
                properties:
                  apiGroups:
                    type: array
                    description: "APIGroups to match (e.g. [\"apps\", \"\"])"
                    items:
                      type: string
                  kinds:
                    type: array
                    description: "Kinds to match (e.g. [\"Deployment\", \"StatefulSet\"])"
                    items:
                      type: string
                  fields:
                    type: array
                    description: "Field paths to protect (e.g. [\"spec.replicas\", \"spec.selector\"])"
                    items:
                      type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8simmutablefields

        # 获取被修改字段的路径
        get_field_path(paths, path) = true {
          paths[_] = path
        }

        # 检查是否为 UPDATE 操作
        is_update(review) {
          review.operation == "UPDATE"
        }

        violation[{"msg": msg}] {
          is_update(input.review)

          field_spec := input.parameters.fieldSpecs[_]
          group_matches(field_spec, input.review)
          kind_matches(field_spec, input.review)

          old_obj := input.review.oldObject
          new_obj := input.review.object

          field := field_spec.fields[_]
          old_value := get_value(old_obj, field)
          new_value := get_value(new_obj, field)

          not equal(old_value, new_value)

          msg := sprintf("Field <%v> on <%v> <%v> is immutable and cannot be changed from %v to %v",
            [field, input.review.kind.kind, input.review.object.metadata.name, old_value, new_value])
        }

        group_matches(spec, review) {
          group := review.kind.group
          groups := spec.apiGroups
          groups[_] == group
        }

        group_matches(spec, review) {
          count(spec.apiGroups) == 0
        }

        kind_matches(spec, review) {
          spec.kinds[_] == review.kind.kind
        }

        # 递归获取嵌套字段值
        get_value(obj, field) = value {
          parts := split(field, ".")
          value := obj
          not missing(obj, parts)
        }

        missing(obj, []) = false
        missing(obj, [h | t]) = true {
          not is_object(obj)
        }
        missing(obj, [h | t]) = true {
          is_object(obj)
          not obj[h]
        }
        missing(obj, [h | t]) = true {
          is_object(obj)
          value := obj[h]
          missing(value, t)
        }

        is_object(obj) {
          is_object := startswith(typeof(obj), "object")
        }

        typeof(x) = type {
          type := typeof(x)
        }

        equal(a, b) {
          a == b
        }

        # 获取嵌套字段的实际值
        get_value(obj, field) = value {
          parts := split(field, ".")
          value := obj
          count(parts) > 0
          value := navigate(obj, parts)
        }

        navigate(obj, []) = obj
        navigate(obj, [h | t]) = value {
          obj[h]
          navigate(obj[h], t) = value
        }
```

---

## 实现方式二：按资源类型的常用不可变字段

### 约束 1：Deployment.replicas 不可变

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sImmutableFields
metadata:
  name: deployment-replicas-immutable
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    fieldSpecs:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet", "ReplicaSet"]
      fields: ["spec.replicas"]
```

### 约束 2：Service.spec.type 不可变

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sImmutableFields
metadata:
  name: service-type-immutable
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
  parameters:
    fieldSpecs:
    - apiGroups: [""]
      kinds: ["Service"]
      fields:
      - "spec.type"
      - "spec.selector"
```

### 约束 3：Namespace annotations 不可变

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sImmutableFields
metadata:
  name: namespace-annotations-immutable
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Namespace"]
  parameters:
    fieldSpecs:
    - apiGroups: [""]
      kinds: ["Namespace"]
      fields:
      - "metadata.annotations"
```

### 约束 4：Ingress host 不可变

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sImmutableFields
metadata:
  name: ingress-host-immutable
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["networking.k8s.io"]
      kinds: ["Ingress"]
  parameters:
    fieldSpecs:
    - apiGroups: ["networking.k8s.io"]
      kinds: ["Ingress"]
      fields:
      - "spec.rules"
      - "spec.tls"
```

---

## 实际应用场景

### 场景 1：保护生产环境副本数

```
production namespace:
  deployment.spec.replicas → immutable

→ 开发者无法通过 kubectl scale 调整生产副本数
→ 强制通过 CI/CD 流水线 + 审批流程变更
```

### 场景 2：防止 Service 暴露方式被修改

```
生产环境中，以下修改被阻止:
  Service.spec.type: ClusterIP → LoadBalancer  ← 阻止
  Service.spec.type: NodePort → LoadBalancer    ← 阻止
  Service.spec.selector 变更                    ← 阻止

→ 强制通过平台团队管理 Service 暴露策略
```

### 场景 3：保护配置注解不被删除

```yaml
# 某些注解代表合规配置，删除它们会破坏合规
metadata:
  annotations:
    config.kubernetes.io/index: "managed"
    istio.io/rev: "1.16"
    config.internal.company.com/team: "platform"
    config.internal.company.com/cost-center: "cc-12345"
```

---

## 测试：触发违规

### 测试 1：修改 Deployment replicas

```bash
# 创建 Deployment
kubectl create deployment nginx --image=nginx --replicas=3

# 尝试修改副本数（触发 violation）
kubectl scale deployment nginx --replicas=10

# 预期拒绝:
# Error from server: admission webhook "validation.gatekeeper.sh" denied the request:
# Field <spec.replicas> on <Deployment> <nginx> is immutable and cannot be changed from 3 to 10
```

### 测试 2：修改 Service type

```bash
# 创建 ClusterIP Service
kubectl expose deployment nginx --port=80 --type=ClusterIP --name=nginx-svc

# 尝试改为 LoadBalancer（触发 violation）
kubectl patch service nginx-svc -p '{"spec":{"type":"LoadBalancer"}}'

# 预期拒绝:
# Field <spec.type> on <Service> <nginx-svc> is immutable and cannot be changed from ClusterIP to LoadBalancer
```

---

## 组合策略：多层防护

不可变字段约束通常与其他安全策略配合使用：

```yaml
# 1. Service 类型不可变（Gatekeeper Constraint）
K8sImmutableFields
  fields: ["spec.type"]

# 2. 阻止 LoadBalancer Service（Gatekeeper Constraint）
K8sBlockLoadBalancer
  enforcementAction: deny

# 3. NetworkPolicy 限制出流量（K8s Network Policy）
#   配合 Cloud Armor 统一防护

组合效果:
  → Service type 不可改
  → LoadBalancer 本身就被阻止
  → 即使通过其他方式改了 type，也会被 NetworkPolicy 拦截
```

---

## K8s 原生字段管理（1.18+）

Kubernetes 1.18 引入了 **Field Selector** 和 **部分字段只读** 支持。对于某些字段，可以使用原生机制：

### 使用 ImmutableRsourceVersion（防止意外修改）

```yaml
# Deployment 的 spec 是完全不可变的
# 只能通过 kubectl replace 或触发新的 Rollout
kubectl replace -f deployment.yaml
kubectl rollout restart deployment/nginx
```

### 使用 PSP/UserName + RBAC 限制

```yaml
# RBAC: 只允许特定 ServiceAccount 修改特定字段
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployment-viewer
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
  # 不包含 "update" 或 "patch" → 只能读，不能改
```

---

## 常见问题

### Q1: immutablefields 和 Mutation 有什么区别？

| 能力 | Constraint | Mutation |
|------|-----------|----------|
| 阻止非法创建 | ✅ | ❌ |
| 阻止非法修改 | ✅ | ❌ |
| 修改请求内容 | ❌ | ✅ |
| 设置默认值 | ❌ | ✅ |

**两者互补**：Mutation 设置初始值，Constraint 确保后续不可变。

### Q2: UPDATE 操作如何获取旧值？

Gatekeeper 的 `input.review.oldObject` 包含资源更新前的完整对象。Constraint 可以对比新旧对象来判断哪些字段被修改。

### Q3: 如何只保护特定 namespace 的字段？

```yaml
spec:
  match:
    namespaces:
    - production
    - staging
    excludedNamespaces:
    - kube-system
```

### Q4: 与 K8s 原生 FieldManager 冲突吗？

不冲突。Gatekeeper 是 Admission Webhook，在 FieldManager 之前拦截。Gatekeeper 拒绝的请求不会到达 etcd，也就不会被 FieldManager 处理。

---

## 快速命令参考

```bash
# 应用自定义模板
kubectl apply -f k8simmutablefields-template.yaml

# 应用约束
kubectl apply -f k8simmutablefields-deployment-replicas.yaml

# 查看约束
kubectl get k8simmutablefields

# 查看 violations
kubectl get k8simmutablefields deployment-replicas-immutable \
  -o jsonpath='{.status.violations}' | jq

# 删除
kubectl delete k8simmutablefields deployment-replicas-immutable
kubectl delete constrainttemplate k8simmutablefields
```

---

## 注意事项

1. **此模板为自定义实现**：gatekeeper-library 官方库中没有 `immutablefields` 模板，需手动创建

2. **生产环境建议**：将不可变字段策略与 CI/CD 流程结合，确保通过审批流的修改不受阻止

3. **Rego 复杂度**：上述 Rego 包含递归字段遍历，生产使用前建议充分测试

4. **K8s 版本兼容**：确保 Gatekeeper 版本支持 `input.review.oldObject`（Gatekeeper v3.0+）
