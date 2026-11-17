# K8sRequiredLabels 完整指南

## 概述

`K8sRequiredLabels` 是一个 Constraint，用于强制要求 Kubernetes 资源必须包含指定的 Labels。本文档通过这个 Constraint 来详细解释 Policy Controller 的工作原理和使用方式。

---

## 核心概念

### ConstraintTemplate vs Constraint

| 概念                   | 说明                                                |
| ---------------------- | --------------------------------------------------- |
| **ConstraintTemplate** | 策略模板，定义逻辑（Rego 代码），告诉系统"如何检查" |
| **Constraint**         | 策略实例，定义参数和目标，告诉系统"检查什么"        |

**类比：**
- ConstraintTemplate = 类定义（蓝图）
- Constraint = 类实例（具体对象）

### K8sRequiredLabels 工作流程

```
┌─────────────────────────────────────────────────────────────────┐
│                     ConstraintTemplate: k8srequiredlabels        │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Rego 逻辑:                                                   ││
│  │ 1. 获取资源已有的 labels                                     ││
│  │ 2. 获取约束要求的 labels                                     ││
│  │ 3. 比较，找出缺失的 labels                                   ││
│  │ 4. 如果有缺失，返回 violation                                 ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Constraint: require-common-labels            │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ parameters:                                                  ││
│  │   labels:                                                    ││
│  │   - key: "app"                                               ││
│  │   - key: "environment"                                       ││
│  │     allowedRegex: "^(prod|staging|dev)$"                    ││
│  │                                                               ││
│  │ match:                                                        ││
│  │   kinds:                                                      ││
│  │   - apiGroups: ["apps"]                                       ││
│  │     kinds: ["Deployment"]                                     ││
│  │                                                               ││
│  │ enforcementAction: dryrun                                    ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Step 1: 创建 Constraint

### YAML 定义

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-common-labels
spec:
  enforcementAction: dryrun       # dryrun=记录不阻止, deny=阻止
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    labels:
    - key: "app"                  # 必须包含 app label
    - key: "environment"          # 必须包含 environment label
      allowedRegex: "^(prod|staging|dev)$"  # 可选: 值必须匹配正则
```

### 解释

| 字段                          | 说明                                                  |
| ----------------------------- | ----------------------------------------------------- |
| `kind: K8sRequiredLabels`     | 这个 Kind 来自 ConstraintTemplate `k8srequiredlabels` |
| `name: require-common-labels` | 这个具体策略的名称                                    |
| `enforcementAction: dryrun`   | 当前是审计模式，只记录不阻止                          |
| `match.kinds`                 | 只检查 Deployment 资源                                |
| `parameters.labels`           | 要求必须包含 `app` 和 `environment` 两个 label        |

### 应用命令

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-common-labels
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    labels:
    - key: "app"
    - key: "environment"
      allowedRegex: "^(prod|staging|dev)$"
EOF
```

---

## Step 2: 验证 Constraint 已创建

### 查看 Constraint 列表

```bash
kubectl get k8srequiredlabels
```

**输出:**
```
NAME                   ENFORCEMENT-ACTION   TOTAL-VIOLATIONS
require-common-labels  dryrun               12
```

### 查看详细信息

```bash
kubectl describe k8srequiredlabels require-common-labels
```

**输出:**
```
Name:         require-common-labels
Namespace:
Labels:       <none>
Annotations:  <none>
API Version:  constraints.gatekeeper.sh/v1beta1
Kind:         K8sRequiredLabels
Metadata:
  Creation Timestamp:  2026-04-29T07:51:01Z
  Resource Version:    1777449913202415017
  UID:                 8b61df4f-71e7-4746-a70c-cfdb20ab1bb0
Spec:
  Enforcement Action:  dryrun
  Match:
    Kinds:
      API Groups:
        apps
      Kinds:
        Deployment
  Parameters:
    Labels:
      Key:            app
      Allowed Regex:  ^(prod|staging|dev)$
      Key:            environment
Status:
  Audit Timestamp:    2026-04-29T08:05:00Z
  Total Violations:   12
  By Pod:
    - ID:                 gatekeeper-audit-57b4b9bbf9-n69g7
      Constraint UID:     8b61df4f-71e7-4746-a70c-cfdb20ab1bb0
      Enforced:           true
      Observed Generation:  1
      Operations:
        - audit
        - status
    - ID:                 gatekeeper-controller-manager-79ff65dddb-rm2q6
      Constraint UID:     8b61df4f-71e7-4746-a70c-cfdb20ab1bb0
      Enforced:           true
      Observed Generation:  1
      Operations:
        - webhook
```

### 查看完整 YAML

```bash
kubectl get k8srequiredlabels require-common-labels -o yaml
```

---

## Step 3: 查看 Violations (违规报告)

### 简单汇总

```bash
kubectl get k8srequiredlabels require-common-labels -o custom-columns=NAME:.metadata.name,ACTION:.spec.enforcementAction,VIOLATIONS:.status.totalViolations
```

**输出:**
```
NAME                   ACTION    VIOLATIONS
require-common-labels  dryrun    12
```

### 查看所有 Violations

```bash
kubectl get k8srequiredlabels require-common-labels -o jsonpath='{.status.violations}'
```

**输出 (格式化后):**
```json
[
  {
    "enforcementAction": "dryrun",
    "group": "apps",
    "kind": "Deployment",
    "message": "you must provide labels: {\"app\", \"environment\"}",
    "name": "rule-evaluator",
    "namespace": "gmp-system",
    "version": "v1"
  },
  {
    "enforcementAction": "dryrun",
    "group": "apps",
    "kind": "Deployment",
    "message": "Label <environment: demo> does not satisfy allowed regex: ^(prod|staging|dev)$",
    "name": "nginx-deployment",
    "namespace": "policy-controller-demo",
    "version": "v1"
  },
  ...
]
```

### 用 jq 美化输出

```bash
kubectl get k8srequiredlabels require-common-labels -o json | jq '.status.violations[] | {namespace, name, message}'
```

**输出:**
```json
{
  "namespace": "gmp-system",
  "name": "rule-evaluator",
  "message": "you must provide labels: {\"app\", \"environment\"}"
}
{
  "namespace": "policy-controller-demo",
  "name": "nginx-deployment",
  "message": "Label <environment: demo> does not satisfy allowed regex: ^(prod|staging|dev)$"
}
```

### 分析 Violations

当前环境有 **12 个违规**，分为两类：

| 类型            | 说明                                     | 例子                                                                      |
| --------------- | ---------------------------------------- | ------------------------------------------------------------------------- |
| **缺少 Labels** | 资源没有 `app` 和/或 `environment` label | `kube-dns` 缺少两个 label                                                 |
| **值不匹配**    | label 存在但值不符合 regex               | `nginx-deployment` 的 `environment: demo` 不符合 `^(prod\|staging\|dev)$` |

---

## Step 4: 导出报告

### 导出为 YAML

```bash
kubectl get k8srequiredlabels require-common-labels -o yaml > require-common-labels-report.yaml
```

### 导出 Violations 为 JSON

```bash
kubectl get k8srequiredlabels require-common-labels -o jsonpath='{.status.violations}' | jq '.' > violations.json
```

### 导出所有 Constraints 的 Violations

```bash
kubectl get constraint --all-namespaces -o yaml > all-constraints-report.yaml
```

---

## Step 5: 修改 Constraint

### 切换为 deny 模式 (阻止)

```bash
kubectl patch k8srequiredlabels require-common-labels \
  --type=merge \
  -p '{"spec":{"enforcementAction":"deny"}}'
```

### 切换回 dryrun 模式

```bash
kubectl patch k8srequiredlabels require-common-labels \
  --type=merge \
  -p '{"spec":{"enforcementAction":"dryrun"}}'
```

### 更新 parameters

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-common-labels
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
    excludedNamespaces:           # 新增: 排除系统 namespace
    - kube-system
    - kube-public
    - gatekeeper-system
  parameters:
    labels:
    - key: "app"
    - key: "environment"
      allowedRegex: "^(prod|staging|dev)$"
    - key: "owner"                # 新增: 要求 owner label
EOF
```

---

## Step 6: 删除 Constraint

```bash
kubectl delete k8srequiredlabels require-common-labels
```

---

## 工作原理详解

### Gatekeeper 的两个组件

| 组件                              | Pod                                 | 职责               |
| --------------------------------- | ----------------------------------- | ------------------ |
| **gatekeeper-audit**              | `gatekeeper-audit-xxx`              | 周期性审计现有资源 |
| **gatekeeper-controller-manager** | `gatekeeper-controller-manager-xxx` | 实时拦截 API 请求  |

### Admission 流程 (实时拦截)

```
用户/程序: kubectl apply deployment.yaml
                    │
                    ▼
Kubernetes API Server
                    │
                    ▼
┌───────────────────────────────────────┐
│  Gatekeeper Webhook (mutating/validating)  │
│                                       │
│  1. 收到 Deployment 创建请求           │
│  2. 发送给 gatekeeper-controller      │
│  3. 检查是否有匹配的 Constraints       │
│  4. 执行 Rego 逻辑                     │
│  5. 如果违反 且 enforcementAction=deny │
│     → 拒绝请求                         │
│  6. 如果违反 且 enforcementAction=dryrun│
│     → 允许请求，但记录 violation       │
│  7. 如果符合 → 允许请求                │
└───────────────────────────────────────┘
                    │
                    ▼
        创建成功/拒绝 + 记录 violation
```

### Audit 流程 (定期检查)

```
gatekeeper-audit pod (每60秒执行一次)
                    │
                    ▼
扫描集群中所有现有资源
(只检查 spec.match 中匹配的资源类型)
                    │
                    ▼
对每个 Deployment:
  1. 检查是否有 app 和 environment labels
  2. 检查 environment 值是否匹配 regex
  3. 记录 violation (如果有)
                    │
                    ▼
更新 Constraint 的 status.violations
                    │
                    ▼
violations 可通过 kubectl 查询
```

---

## 常见用法示例

### 只要求 app label (不限制值)

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-app-label
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Namespace"]
  parameters:
    labels:
    - key: "app"
```

### 要求带正则校验

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-environment-label
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
    excludedNamespaces:
    - kube-system
  parameters:
    labels:
    - key: "environment"
      allowedRegex: "^(prod|staging|dev|test)$"
    - key: "team"
      allowedRegex: "^(frontend|backend|platform|data)$"
```

### 检查所有资源类型

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-cost-center
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: ["*"]
      kinds: ["*"]
  parameters:
    labels:
    - key: "cost-center"
    - key: "team"
```

---

## 快速命令参考

```bash
# 查看所有 K8sRequiredLabels 约束
kubectl get k8srequiredlabels

# 查看单个约束详情
kubectl get k8srequiredlabels <name> -o yaml

# 查看约束状态和violations
kubectl describe k8srequiredlabels <name>

# 查看violations数量
kubectl get k8srequiredlabels <name> -o jsonpath='{.status.totalViolations}'

# 查看所有violations
kubectl get k8srequiredlabels <name> -o jsonpath='{.status.violations}' | jq '.'

# 修改enforcementAction
kubectl patch k8srequiredlabels <name> -p '{"spec":{"enforcementAction":"deny"}}'

# 删除约束
kubectl delete k8srequiredlabels <name>

# 查看约束对应的Template
kubectl get constrainttemplate k8srequiredlabels

# 查看Template详情(包含Rego代码)
kubectl get constrainttemplate k8srequiredlabels -o yaml | grep -A 50 "rego:"
```

---

## 查看其他资源类型的约束

### 列出所有 Constraint 资源

```bash
# 方式1: 查看所有 kind 的 constraints
kubectl get constraint --all-namespaces

# 方式2: 只看某种 kind
kubectl get k8spspprivilegedcontainer
kubectl get k8sblockloadbalancer
kubectl get k8scontainerlimits
kubectl get k8srequiredresources
```

### Constraint 资源类型对应表

| Constraint Kind             | 来自 Template               | 用途                      |
| --------------------------- | --------------------------- | ------------------------- |
| `K8sRequiredLabels`         | `k8srequiredlabels`         | 要求必填 labels           |
| `K8sPSPPrivilegedContainer` | `k8spspprivilegedcontainer` | 禁止特权容器              |
| `K8sBlockLoadBalancer`      | `k8sblockloadbalancer`      | 阻止 LoadBalancer Service |
| `K8sContainerLimits`        | `k8scontainerlimits`        | 限制容器资源              |
| `K8sRequiredResources`      | `k8srequiredresources`      | 要求资源限制              |
| `K8sAllowedRepos`           | `k8sallowedrepos`           | 限制允许的镜像仓库        |

---

## 问题排查

### 约束未生效

```bash
# 1. 确认约束存在
kubectl get k8srequiredlabels require-common-labels

# 2. 确认 Gatekeeper pods 运行正常
kubectl get pods -n gatekeeper-system

# 3. 确认 webhook 配置存在
kubectl get validatingwebhookconfigurations gatekeeper-validating-webhook-configuration

# 4. 查看 Gatekeeper 日志
kubectl logs -n gatekeeper-system -l app=gatekeeper --tail=50
```

### 查看为什么某个资源没被检查

```bash
# 1. 确认资源类型匹配
kubectl get k8srequiredlabels require-common-labels -o jsonpath='{.spec.match}'

# 2. 确认 namespace 未被排除
# 查看约束的 excludedNamespaces
kubectl get k8srequiredlabels require-common-labels -o jsonpath='{.spec.match.excludedNamespaces}'

# 3. 手动测试该资源是否有 violation
# 查看该资源是否在 violation 列表中
kubectl get k8srequiredlabels require-common-labels -o jsonpath='{.status.violations[*].name}' | tr ' ' '\n' | grep <resource-name>
```

---

## 完整资源流转图

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              用户操作                                         │
│                         kubectl apply -f deployment.yaml                     │
└──────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                          Kubernetes API Server                                │
└──────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                    Gatekeeper Validating Webhook                              │
│                                                                               │
│   对于 CREATE/UPDATE 请求:                                                    │
│   1. 拦截请求                                                                 │
│   2. 提取资源对象 (Deployment)                                                │
│   3. 查找匹配的 Constraints (kind=K8sRequiredLabels)                          │
│   4. 调用 gatekeeper-controller-manager pod                                   │
│   5. 执行 Rego 逻辑检查 labels                                                │
│   6. 根据 enforcementAction 决定:                                             │
│      - deny: 返回拒绝错误                                                     │
│      - dryrun: 记录 violation，允许请求                                        │
│      - warn: 返回警告，允许请求                                                │
└──────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
              请求被拒绝                            请求被允许
              (如果 deny)                         + violation 被记录
                                                     │
                                                     ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                        Gatekeeper Audit (每60秒)                              │
│                                                                               │
│   周期性扫描集群所有现有资源:                                                  │
│   1. 获取所有 Deployment                                                      │
│   2. 检查每个 Deployment 的 labels                                            │
│   3. 对比 Constraint 参数                                                     │
│   4. 记录新的 violations                                                      │
│   5. 更新 Constraint status                                                   │
└──────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                       查询 Violations                                         │
│                                                                               │
│   kubectl get k8srequiredlabels require-common-labels -o yaml                │
│   kubectl describe k8srequiredlabels require-common-labels                    │
│   kubectl get k8srequiredlabels require-common-labels -o jsonpath='...'      │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Namespace 级别 vs Cluster 级别 Constraints

### 问题

> Q: Constraint 是应用在整个集群还是特定命名空间？如果想只针对某个命名空间生效怎么做？

### 答案

**Constraint 本身没有 "Namespace" 属性**，但可以通过 `spec.match` 来控制作用域。

### match 配置详解

```yaml
spec:
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
    namespaces:              # 可选: 限定只在这些命名空间中检查
    - policy-controller-demo
    excludedNamespaces:      # 可选: 排除这些命名空间
    - kube-system
    - kube-public
```

| 配置                                              | 效果                                                   |
| ------------------------------------------------- | ------------------------------------------------------ |
| 不指定 `namespaces` 且不指定 `excludedNamespaces` | **集群级别** - 检查所有命名空间                        |
| 指定 `namespaces: [ns1, ns2]`                     | **命名空间级别** - 只检查指定的命名空间                |
| 指定 `excludedNamespaces: [ns1]`                  | **排除模式** - 检查除指定外的所有命名空间              |
| 两者都指定                                        | `namespaces` 优先，`excludedNamespaces` 在其基础上排除 |

### 验证实验

**场景**: 创建一个只针对 `policy-controller-demo` 命名空间的约束

**Step 1: 删除全局约束**
```bash
kubectl delete k8srequiredlabels require-common-labels
```

**Step 2: 创建命名空间级别的约束**
```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-labels-for-demo-namespace
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
    namespaces:
    - policy-controller-demo
  parameters:
    labels:
    - key: "app"
    - key: "environment"
      allowedRegex: "^(prod|staging|dev|demo)$"
EOF
```

**Step 3: 查看约束**
```bash
kubectl get k8srequiredlabels require-labels-for-demo-namespace -o yaml
```

**输出:**
```yaml
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups:
      - apps
      kinds:
      - Deployment
    namespaces:
    - policy-controller-demo           # <-- 只限定这个命名空间
  parameters:
    labels:
    - key: app
    - allowedRegex: ^(prod|staging|dev|demo)$
      key: environment
```
- explain
```yaml
  parameters:
    labels:
    - key: "app"                            # 规则 1：检查标签的 [键] 是否存在
    - key: "environment"                    # 规则 2：检查标签的 [键]
      allowedRegex: "^(prod|staging|dev|demo)$" # 检查上面那个键对应的 [值] 是否匹配正则
详细解释：
key: "app":
这行代码告诉 Policy Controller：“我要求资源必须拥有一个名为 app 的标签（Key）”。它不关心这个 app 的值是什么，只要有这个 Key 就行。

你的 Pod 状态： app=nginx。
结果： 匹配成功。
key: "environment" + allowedRegex:
这两行是组合逻辑。它告诉 Policy Controller：

必须有一个标签键名为 environment。
而且这个标签的值 (Value) 必须符合正则表达式 ^(prod|staging|dev|demo)$。
你的 Pod 状态： environment=demo。
结果： 匹配成功（因为 demo 在正则允许的范围内）
```

**Step 4: 验证只检查目标命名空间**

查看 violations:
```bash
kubectl get k8srequiredlabels require-labels-for-demo-namespace -o custom-columns=NAME:.metadata.name,VIOLATIONS:.status.totalViolations
```

**输出:**
```
NAME                                    VIOLATIONS
require-labels-for-demo-namespace      0


kubectl get pod -n policy-controller-demo --show-labels
NAME                               READY   STATUS    RESTARTS   AGE     LABELS
nginx-deployment-d5ff86d69-74grg   1/1     Running   0          7h16m   app=nginx,environment=demo,owner=platform-team,pod-template-hash=d5ff86d69,topology.kubernetes.io/region=europe-west2,topology.kubernetes.io/zone=europe-west2-a
nginx-deployment-d5ff86d69-kzbn5   1/1     Running   0          7h16m   app=nginx,environment=demo,owner=platform-team,pod-template-hash=d5ff86d69,topology.kubernetes.io/region=europe-west2,topology.kubernetes.io/zone=europe-west2-a

为什么你的 Deployment 是符合要求的？
我们来看一下你 kubectl get pod 输出的实际标签：
LABELS: app=nginx, environment=demo, ...

检查 app: 你的 Pod 有 app=nginx。Key 是 app，规则通过。
检查 environment: 你的 Pod 有 environment=demo。
Key 是 environment（存在）。
Value 是 demo（符合正则 ^(prod|staging|dev|demo)$）。规则通过。
结论： 因为你的 Pod 标签完全满足了这两个约束条件，所以 VIOLATIONS（违规数）为 0
```

说明 `policy-controller-demo` 命名空间中的 `nginx-deployment` (有 `app=nginx, environment=demo`) 符合规则。

**Step 5: 验证其他命名空间不受影响**

在 `default` 命名空间创建一个没有 labels 的 Deployment:
```bash
kubectl create deployment bad-deployment --image=nginx --namespace=default
```

再次检查约束:
```bash
kubectl get k8srequiredlabels require-labels-for-demo-namespace -o custom-columns=NAME:.metadata.name,VIOLATIONS:.status.totalViolations
```

**输出:**
```
NAME                                    VIOLATIONS
require-labels-for-demo-namespace      0
```

**结论**: `default` 命名空间的 `bad-deployment` 没有被检查，因为约束只限定在 `policy-controller-demo`。

清理测试资源:
```bash
kubectl delete deployment bad-deployment --namespace=default
```

### 总结

| 模式               | 配置方式                          | 作用范围                   |
| ------------------ | --------------------------------- | -------------------------- |
| **Cluster 级别**   | `match` 中不指定 `namespaces`     | 整个集群所有命名空间       |
| **Namespace 级别** | `match.namespaces: [ns1, ns2]`    | 只检查指定命名空间         |
| **排除模式**       | `match.excludedNamespaces: [ns1]` | 检查除指定外的所有命名空间 |

**实际使用建议**:
- 安全策略 (如禁止特权容器) 通常用 `excludedNamespaces` 排除系统命名空间
- 业务标签策略可以用 `namespaces` 针对特定业务命名空间
- 全局合规要求 (如 PCI-DSS) 通常是集群级别

---

## 当前环境约束状态

**已创建的约束:**
```bash
kubectl get k8srequiredlabels -A
```

**输出:**
```
NAME                                 NAMESPACE   ENFORCEMENT-ACTION   TOTAL-VIOLATIONS
require-labels-for-demo-namespace               dryrun               0
```

**约束详情:**
- 名称: `require-labels-for-demo-namespace`
- 作用域: `policy-controller-demo` 命名空间
- 目标资源: `Deployment`
- 强制要求: `app` 和 `environment` labels
- `environment` 值必须匹配: `^(prod|staging|dev|demo)$`
- 当前状态: 0 violations (符合规则)