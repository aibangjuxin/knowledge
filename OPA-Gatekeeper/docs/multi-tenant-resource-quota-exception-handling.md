# Multi-Tenant Resource Quota Exception Handling

> **文档版本**: 1.0.0
> **更新日期**: 2026-05-04
> **目标读者**: 平台架构师、SRE、DevOps 工程师
> **问题域**: 全局限制 vs 特殊租户超额需求的处理方案

---

## 1. 问题定义

### 1.1 场景描述

```
┌─────────────────────────────────────────────────────────────────┐
│                    平台全局 Constraint                            │
│                   CPU Max: 4  |  Memory Max: 8Gi                   │
└─────────────────────────────────────────────────────────────────┘
                              │
           ┌──────────────────┴──────────────────┐
           ▼                                     ▼
    ┌─────────────┐                      ┌─────────────┐
    │ 普通租户 NS  │                      │ 特殊租户 NS  │
    │ 需求: 2C4Gi │                      │ 需求: 4C10Gi │
    │  ✅ 通过    │                      │ ❌ 拒绝 (10Gi>8Gi) │
    └─────────────┘                      └─────────────┘
```

### 1.2 核心矛盾

| 维度 | 说明 |
|------|------|
| **平台统一性** | 全局限制确保资源公平分配、防止滥用 |
| **业务特殊性** | 特殊业务（大数据、AI训练）确实需要更多资源 |
| **治理与效率** | 限制太严影响业务灵活性；太松失去治理意义 |

---

## 2. 解决方案概览

### 2.1 四种方案对比

| 方案 | 原理 | 适用场景 | 复杂度 |
|------|------|---------|--------|
| **A. Namespace 分层隔离** | 按 NS 创建差异化 Constraints | 已知特殊租户 | ⭐ 低 |
| **B. 豁免 (Exemption) 机制** | 对特定资源临时/永久豁免 | 遗留系统、紧急需求 | ⭐ 低 |
| **C. 申请审批流程** | 提交申请 → 审批 → 自动注入豁免 | 规范化多租户治理 | ⭐⭐ 中 |
| **D. Constraint 模板变量** | 使用 CRD 参数注入差异化配置 | 动态配额场景 | ⭐⭐⭐ 高 |

### 2.2 推荐路径

```
已知特殊租户?
    ├── YES → 方案 A (Namespace 分层) + 方案 B (豁免)
    └── NO (需要临时处理)?
        ├── 紧急 → 方案 B (快速豁免)
        └── 规范 → 方案 C (申请审批)
```

---

## 3. 方案 A: Namespace 分层隔离

### 3.1 核心思想

**不要试图用一套 Constraint 满足所有场景**。按 Namespace 创建不同的 Constraints，每个 NS/租户组有自己的限制参数。

### 3.2 实现方式

```yaml
# ================================================================
# 普通租户 Namespace: 4C8Gi
# ================================================================

# Constraint 1: 普通命名空间限制
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-standard
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
    # 只匹配标注了 tier=standard 的 namespace
    namespaceSelector:
      matchExpressions:
      - key: tier
        operator: In
        values:
        - standard
  parameters:
    cpu: "4"
    memory: "8Gi"
    exemptImages:
    - "gcr.io/distroless/*"

---
# Namespace 标签配置
apiVersion: v1
kind: Namespace
metadata:
  name: team-frontend
  labels:
    tier: standard    # 使用 standard 限制
---
apiVersion: v1
kind: Namespace
metadata:
  name: team-backend
  labels:
    tier: standard
```

```yaml
# ================================================================
# 特殊租户 Namespace: 8C16Gi
# ================================================================

# Constraint 2: 特殊命名空间限制
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-special
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
    # 匹配标注了 tier=special 的 namespace
    namespaceSelector:
      matchExpressions:
      - key: tier
        operator: In
        values:
        - special
  parameters:
    cpu: "8"
    memory: "16Gi"
    exemptImages:
    - "gcr.io/distroless/*"

---
# Namespace 标签配置
apiVersion: v1
kind: Namespace
metadata:
  name: team-ai-training
  labels:
    tier: special    # 使用 special 限制
```

### 3.3 Namespace 标签设计

```bash
# 给特殊租户打标签
kubectl label namespace team-ai-training tier=special --overwrite
kubectl label namespace team-bigdata tier=special --overwrite
kubectl label namespace team-ml tier=special --overwrite
```

### 3.4 优缺点

| 优点 | 缺点 |
|------|------|
| ✅ 简单直观 | ❌ 需要提前规划 Namespace 分类 |
| ✅ 多租户隔离清晰 | ❌ 特殊租户数量增加时维护成本上升 |
| ✅ 不影响全局 Constraint | ❌ 不能动态调整（需要改 YAML + apply） |

---

## 4. 方案 B: 豁免 (Exemption) 机制

### 4.1 Exemption 的三种方式

| 方式 | 说明 | 使用场景 |
|------|------|---------|
| `excludedNamespaces` | 整个 Namespace 豁免 | 系统组件、特殊业务单元 |
| `exemptImages` | 特定镜像豁免 | 基础设施镜像、已知合规镜像 |
| `labelSelector` | 按资源标签豁免 | 特定 Deployment 需要特殊处理 |

### 4.2 方式 1: Namespace 级别豁免

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-global
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    - istio-system
    # 特殊租户完全豁免（整个 NS 不受限制）
    - team-ai-training
    - team-bigdata
  parameters:
    cpu: "4"
    memory: "8Gi"
```

**⚠️ 注意**: `excludedNamespaces` 会让该 NS 下的**所有**资源都不受限制。

### 4.3 方式 2: 镜像级别豁免

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-global
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    cpu: "4"
    memory: "8Gi"
    # 只有这些镜像可以超过限制
    exemptImages:
    - "gcr.io/distroless/*"
    - "*.internal.company.com/base/*"    # 内部基础镜像
    - "nvidia/*"                          # GPU 镜像通常需要更多内存
```

### 4.4 方式 3: 资源标签豁免 (Gatekeeper v3.12+)

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-global
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
    # 只检查有特定标签的资源
    labelSelector:
      matchExpressions:
      # 不带豁免标签的资源才受限制
      - key: quota-exemption
        operator: DoesNotExist
  parameters:
    cpu: "4"
    memory: "8Gi"
```

**使用方式**:

```bash
# 需要特殊配额的 Deployment，添加豁免标签
kubectl label deployment my-special-app quota-exemption=approved --overwrite

# 这个 Deployment 将不受全局 8Gi 限制（因为 DoesNotExist 不匹配）
```

### 4.5 方式 4: 临时豁免 (带过期时间)

Gatekeeper 原生不支持"临时豁免"（过期自动失效），但可以通过以下方式实现：

```bash
# 方法: 结合 Namespace 标签 + 定期清理脚本

# 1. 给需要临时豁免的 NS 打上过期日期标签
kubectl label namespace team-temp-project \
  exemption-until=2026-06-01 \
  --overwrite

# 2. 创建 CronJob 定期检查并清理过期豁免
# (见下方脚本)
```

**清理过期豁免的脚本**:

```bash
#!/bin/bash
# cleanup-expired-exemptions.sh

EXPIRED_NAMESPACES=$(kubectl get ns -l "exemption-until" -o jsonpath='{.items[*].metadata.name}')

for NS in $EXPIRED_NAMESPACES; do
  EXPIRY=$(kubectl get ns $NS -o jsonpath='{.metadata.labels.exemption-until}')
  if [[ "$(date -d $EXPIRY +%s)" -lt "$(date +%s)" ]]; then
    echo "Removing exemption from namespace: $NS"
    kubectl label namespace $NS exemption-until-
    kubectl annotate namespace $NS exemption-removed="$(date)"
  fi
done
```

### 4.6 豁免的权限控制

```yaml
# RBAC: 只有特定角色可以添加豁免标签
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: quota-exemption-manager
rules:
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list", "update", "patch"]
  resourceNames: []  # 可以操作所有 namespace
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: quota-exemption-managers
subjects:
- kind: Group
  name: platform-admins
roleRef:
  kind: Role
  name: quota-exemption-manager
```

---

## 5. 方案 C: 申请审批流程

### 5.1 完整工作流

```
┌─────────────────────────────────────────────────────────────────┐
│                     租户: 申请更多配额                            │
│                     kubectl apply quota-request.yaml             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     平台: 审批流程                                 │
│              (人工审批 或 自动化规则审批)                            │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
        ┌──────────┐                   ┌──────────┐
        │ ✅ 批准   │                   │ ❌ 拒绝   │
        └──────────┘                   └──────────┘
              │                               │
              ▼                               ▼
    添加豁免标签/更新Constraint          通知租户拒绝原因
    (自动化注入)                         (邮件/消息通知)
```

### 5.2 申请 CRD 设计

```yaml
# 自定义 ResourceQuotaRequest CRD
apiVersion: v1
kind: CustomResourceDefinition
metadata:
  name: quotarequests.platform.example.com
spec:
  group: platform.example.com
  names:
    kind: QuotaRequest
    listKind: QuotaRequestList
  scope: Namespaced
---
apiVersion: platform.example.com/v1
kind: QuotaRequest
metadata:
  name: team-ai-memory-increase
spec:
  namespace: team-ai-training
  requestedResources:
  - kind: Deployment
    containerLimits:
      cpu: "8"
      memory: "16Gi"
  reason: "AI 模型训练需要大内存容器，当前 8Gi 不足以支持 13B 模型"
  duration: 30d          # 临时申请，30 天后过期
  approvers:
  - platform-team@company.com
status:
  state: pending        # pending / approved / rejected / expired
  reviewedAt: ""
  reviewedBy: ""
  reviewComment: ""
```

### 5.3 审批 Controller 实现逻辑

```python
# quota-approval-controller.py (伪代码)

def reconcile_quota_request(request):
    # 1. 检查申请合理性
    if not is_justified(request):
        reject(request, "Insufficient justification")
        return
    
    # 2. 检查资源配额是否充足
    if not has_available_quota(request):
        reject(request, "Insufficient cluster resources")
        return
    
    # 3. 临时批准 (duration 设置)
    if request.spec.duration:
        approve_temporary(request)
        schedule_expiry(request)
    else:
        approve_permanent(request)
    
    # 4. 注入豁免
    apply_exemption(request)

def apply_exemption(request):
    ns = request.spec.namespace
    
    if request.spec.duration:
        # 临时豁免: 添加带过期时间的标签
        label_expiry = datetime.now() + timedelta(days=request.spec.duration)
        kubectl.label.namespace(
            ns,
            f"quota-exempt-until={label_expiry.strftime('%Y-%m-%d')}",
            "--overwrite"
        )
    else:
        # 永久豁免: 更新 Constraint
        update_constraint_for_namespace(ns, request.spec.requestedResources)
```

### 5.4 简化版: GitOps 审批流

如果没有开发完整的 CRD 控制器，可以用 GitHub PR 流程替代：

```bash
# 1. 租户提交 PR 到 policy-exceptions 目录
# policy-exceptions/team-ai-training/exception.yaml

apiVersion: v1
kind: Namespace
metadata:
  name: team-ai-training
  labels:
    # 临时豁免 (示例: 30天)
    quota-exempt-until: "2026-06-04"
---
# 或永久豁免特定 Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: large-memory-app
  namespace: team-ai-training
  labels:
    quota-exempt: "approved-by-platform-team-2026-05"
spec:
  # ...

# 2. 平台团队 Code Review + 审批合并

# 3. ArgoCD/Flux 自动同步到集群
```

---

## 6. 方案 D: 动态 Constraint 参数 (高级)

### 6.1 外部数据源方案

```rego
# K8sContainerLimits 模板可以改造为从外部数据源读取配额

package containerlimits

# 从 ConfigMap 读取 namespace 特定的限制
quota_ns(ns) = quota {
  data.storageclass.mapping[ns] = quota
}

violation[{"msg": msg}] {
  container := containers[_]
  ns := input.review.namespace
  quota := quota_ns(ns)
  
  not is_exempt(container.image)
  missing(container.resources.limits, "cpu")
  
  msg := sprintf("Container %v in namespace %v must have CPU limit (namespace quota: %v)", 
    [container.name, ns, quota.cpu])
}

# 从 ConfigMap 读取配额映射
data_storageclass_mapping = {ns: quota |
  cm := data.external.data["namespace-quotas"]
  quota := cm.quota[ns]
}
```

### 6.2 ConfigMap 配置

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: namespace-quotas
  namespace: gatekeeper-system
data:
  quotas: |
    {
      "team-frontend": {"cpu": "4", "memory": "8Gi"},
      "team-backend": {"cpu": "4", "memory": "8Gi"},
      "team-ai-training": {"cpu": "8", "memory": "16Gi"},
      "team-bigdata": {"cpu": "16", "memory": "32Gi"}
    }
```

**⚠️ 警告**: 外部数据源方案需要修改 ConstraintTemplate Rego 代码，复杂度较高，建议作为最后手段。

---

## 7. 实际推荐组合

### 7.1 推荐: 方案 A + 方案 B 组合

```
日常运营推荐配置:

1. Namespace 标签分层 (方案 A)
   ├── tier: standard  → 4C8Gi
   ├── tier: special   → 8C16Gi  
   └── tier: gpu       → 8C32Gi (GPU 专用)

2. 紧急豁免通道 (方案 B)
   └── exemptImages 包含所有已知合规镜像
```

### 7.2 namespaceSelector 完整示例

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-tiered
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    # 通过 namespaceSelector 实现分层
    namespaceSelector:
      matchExpressions:
      # 排除已明确配置特殊限制的 namespace
      - key: tier
        operator: NotIn
        values:
        - special
        - gpu
  parameters:
    # 默认限制: 4C8Gi
    cpu: "4"
    memory: "8Gi"
    exemptImages:
    - "gcr.io/distroless/*"
    - "nvidia/*"
```

```yaml
# 特殊租户独立 Constraint
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-special
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
    namespaceSelector:
      matchExpressions:
      - key: tier
        operator: In
        values:
        - special
        - gpu
  parameters:
    # 特殊限制: 8C16Gi 或 8C32Gi
    cpu: "8"
    memory: "16Gi"
    exemptImages:
    - "gcr.io/distroless/*"
    - "nvidia/*"
```

---

## 8. 决策树

```
需要处理特殊配额需求?
    │
    ├── 租户已知，可以提前规划?
    │   ├── YES → 给 Namespace 打标签 + 创建专用 Constraint (方案 A)
    │   └── NO ↓
    │
    ├── 紧急情况，需要快速放行?
    │   ├── YES → 添加 exemptImages 或 excludedNamespaces (方案 B)
    │   └── NO ↓
    │
    ├── 需要规范化、审计追踪?
    │   ├── YES → GitOps PR 审批流程 (方案 C)
    │   └── NO ↓
    │
    └── 动态配额，频繁变化?
        └── YES → 外部数据源方案 (方案 D，慎用)
```

---

## 10. Per-Tenant Namespace 场景最佳实践

### 10.1 场景定义

当 **每个 Namespace 对应一个独立租户/team** 时，治理模式发生了本质变化：

```
传统模式: Namespace = 功能分区 (dev/staging/prod)
Per-Tenant 模式: Namespace = 租户边界 (team-a/team-b/team-c/...)

特点:
├── 租户数量多 (可能 50+ namespaces)
├── 每个租户需求差异大
├── 资源配额需求各不相同
└── 需要灵活的差异化治理机制
```

### 10.2 核心挑战

| 挑战 | 说明 |
|------|------|
| **数量庞大** | 几十上百个租户 NS，无法用简单的 tier 分类 |
| **需求多样** | AI 训练需要 32Gi，Web 服务可能只需要 1Gi |
| **变化频繁** | 新租户加入、旧租户释放、配额调整 |
| **一致性要求** | 既要差异化管理，又要平台整体可控 |

### 10.3 推荐方案: 租户配额 Map + 自适应 Constraint

#### 方案 E: ConfigMap 租户配额表 (推荐)

**核心思想**: 所有租户配额集中存储在 ConfigMap 中，单个 Constraint 根据 namespace 动态读取。

```yaml
# ConfigMap: 存储所有租户的配额配置
apiVersion: v1
kind: ConfigMap
metadata:
  name: tenant-resource-quotas
  namespace: gatekeeper-system
data:
  quotas.yaml: |
    # 默认配额
    default:
      cpu: "4"
      memory: "8Gi"
    
    # 租户特定配额 (覆盖默认)
    tenants:
      team-ai-training:
        cpu: "16"
        memory: "64Gi"
        exemptImages:
        - "nvidia/*"
      team-bigdata:
        cpu: "8"
        memory: "32Gi"
      team-ml:
        cpu: "8"
        memory: "32Gi"
        gpu: "2"
      team-frontend:
        cpu: "2"
        memory: "4Gi"
      # 新租户只需在此添加
```

**Constraint 改造 (需要修改 Rego)**:

```rego
# K8sContainerLimits 改造版: 从 ConfigMap 读取 per-tenant 配额
package containerlimits

import future.keywords.if

# 从 data 获取租户配额
default quota := {"cpu": "4", "memory": "8Gi"}

quota := {"cpu": cpu, "memory": mem} {
    ns := input.review.namespace
    data.storageclass.mapping.quotas.tenants[ns]
    t := data.storageclass.mapping.quotas.tenants[ns]
    cpu := t.cpu
    mem := t.memory
}

violation[{"msg": msg}] {
    container := containers[_]
    not is_exempt(container.image, exempt_images)
    missing(container.resources.limits, "cpu")
    msg := sprintf(
        "Container %v does not have CPU limit. Namespace quota: %v",
        [container.name, quota]
    )
}

violation[{"msg": msg}] {
    container := containers[_]
    not is_exempt(container.image, exempt_images)
    missing(container.resources.limits, "memory")
    msg := sprintf(
        "Container %v does not have memory limit. Namespace quota: %v",
        [container.name, quota]
    )
}

exempt_images := images {
    ns := input.review.namespace
    data.storageclass.mapping.quotas.tenants[ns].exemptImages
    images := data.storageclass.mapping.quotas.tenants[ns].exemptImages
} else := []
```

**⚠️ 注意事项**: 修改 ConstraintTemplate Rego 需要谨慎，建议：
1. 在 dev 环境先测试
2. 保留原版 Template 作为备份
3. 做好版本记录

---

#### 方案 F: GitOps + Per-Tenant Constraint 文件 (更安全)

**核心思想**: 每个租户 NS 有自己的 Constraint YAML 文件，通过 GitOps 统一管理。

```
policy-library/
├── constraints/
│   ├── _templates/           # 共享模板
│   │   └── k8scontainerlimits-template.yaml
│   │
│   └── tenants/              # 每个租户一个目录
│       ├── team-ai-training/
│       │   └── container-limits.yaml    # 16C64Gi
│       ├── team-bigdata/
│       │   └── container-limits.yaml    # 8C32Gi
│       ├── team-frontend/
│       │   └── container-limits.yaml    # 2C4Gi
│       └── _defaults/
│           └── container-limits.yaml    # 默认 4C8Gi
```

**默认 Constraint**:

```yaml
# constraints/tenants/_defaults/container-limits.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-default
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
  parameters:
    cpu: "4"
    memory: "8Gi"
```

**特殊租户 Constraint**:

```yaml
# constraints/tenants/team-ai-training/container-limits.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-team-ai-training
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
    namespaceSelector:
      matchExpressions:
      - key: tenant-name
        operator: In
        values:
        - team-ai-training
  parameters:
    cpu: "16"
    memory: "64Gi"
    exemptImages:
    - "nvidia/*"
    - "gcr.io/distroless/*"
```

**Namespace 标签配置**:

```yaml
# team-ai-training NS 配置
apiVersion: v1
kind: Namespace
metadata:
  name: team-ai-training
  labels:
    tenant-name: team-ai-training    # 租户标识
    # 不用 tier 标签，因为每个租户都是独立的
```

**GitOps 工作流**:

```
1. 新租户申请配额 → 提交 PR 到 policy-library/constraints/tenants/team-new/
2. 平台审核 PR → 检查配额合理性、集群资源充足性
3. PR 合并 → ArgoCD/Flux 自动同步到集群
4. Constraint 自动创建 → Gatekeeper 立即生效
```

**新增租户自动化脚本**:

```bash
#!/bin/bash
# create-tenant-constraint.sh

TENANT_NAME=$1
CPU_LIMIT=${2:-4}
MEMORY_LIMIT=${3:-8Gi}

mkdir -p "constraints/tenants/${TENANT_NAME}"

cat > "constraints/tenants/${TENANT_NAME}/container-limits.yaml" <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-${TENANT_NAME}
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
    namespaceSelector:
      matchExpressions:
      - key: tenant-name
        operator: In
        values:
        - ${TENANT_NAME}
  parameters:
    cpu: "${CPU_LIMIT}"
    memory: "${MEMORY_LIMIT}"
EOF

echo "Created constraint for tenant: ${TENANT_NAME}"
echo "CPU: ${CPU_LIMIT}, Memory: ${MEMORY_LIMIT}"
```

```bash
# 使用示例
./create-tenant-constraint.sh team-ai-training 16 64Gi
./create-tenant-constraint.sh team-bigdata 8 32Gi
./create-tenant-constraint.sh team-new 2 4Gi   # 默认配额
```

---

#### 方案 G: 混合策略 (全局安全网 + 租户豁免)

**核心思想**: 
- 保留全局 Constraint 作为安全网（硬限制）
- 租户特殊需求通过豁免机制处理
- 简化管理，减少 Constraint 数量

```
┌─────────────────────────────────────────────────────────────────┐
│                    全局 Constraint (安全网)                       │
│              CPU Max: 4  |  Memory Max: 8Gi                       │
│              enforcementAction: deny                             │
└─────────────────────────────────────────────────────────────────┘
                              │
           ┌──────────────────┴──────────────────┐
           ▼                                     ▼
    普通租户 NS                            特殊租户 NS
    (无豁免标签)                           (带豁免标签)
    4C8Gi 限制生效                          quota-exempt: approved
                                               │
                                               ▼
                                    应用自己的 8C16Gi 配置
                                    (通过 ArgoCD 管理的 Constraint)
```

**实现方式**:

```bash
# 给特殊租户 NS 添加豁免标签
kubectl label namespace team-ai-training quota-exempt=approved --overwrite

# 全局 Constraint 忽略带此标签的 NS
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-global
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    # 排除已豁免的租户 NS
    labelSelector:
      matchExpressions:
      - key: quota-exempt
        operator: DoesNotExist
  parameters:
    cpu: "4"
    memory: "8Gi"
```

**租户级别 Constraint**:

```yaml
# 租户自己的 Constraint (由 ArgoCD 管理)
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: container-limits-team-ai-training
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    namespaceSelector:
      matchExpressions:
      - key: tenant-name
        operator: In
        values:
        - team-ai-training
  parameters:
    cpu: "16"
    memory: "64Gi"
```

---

### 10.4 方案对比 (Per-Tenant 场景)

| 方案 | 优点 | 缺点 | 推荐度 |
|------|------|------|--------|
| **方案 E: ConfigMap Map** | 集中管理，动态生效 | 需要修改 Template Rego | ⭐⭐⭐ |
| **方案 F: GitOps Per-Tenant** | 声明式，版本可控，审计友好 | 文件数量多 (N 个租户 = N 个文件) | ⭐⭐⭐⭐ |
| **方案 G: 混合策略** | 简单，全局安全网不变 | 两层管理，稍复杂 | ⭐⭐⭐ |

### 10.5 Per-Tenant 场景推荐工作流

```
新租户入驻流程:

1. Platform 团队收到租户资源需求
   ├── 评估需求合理性
   ├── 检查集群总资源容量
   └── 确认配额 (如: 16C64Gi)

2. GitOps: 创建租户资源
   ├── 创建 Namespace (tenant-name label)
   ├── 创建租户专属 Constraint (如需要)
   ├── 创建 RBAC 权限
   └── 提交 PR

3. PR 合并后自动生效
   └── ArgoCD Sync → Gatekeeper 生效

4. 租户开始部署
   └── 受租户专属 Constraint 限制
```

```
租户配额调整流程:

1. 租户提交配额调整申请
2. Platform 审核 (合理性 + 容量)
3. GitOps: 修改 Constraint 参数
4. 提交 PR → Review → Merge
5. ArgoCD Sync → 实时生效
```

---

### 10.6 容量规划建议

当租户数量增长到一定规模时，需要考虑集群整体容量：

```yaml
# 集群总容量检查 Constraint (防止所有租户同时达峰)
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sClusterCapacityCheck
metadata:
  name: cluster-capacity-check
spec:
  enforcementAction: dryrun  # 先审计，不阻止
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Namespace"]
  parameters:
    # 集群总 CPU 上限
    totalCpuLimit: "256"
    # 集群总内存上限
    totalMemoryLimit: "1024Gi"
    # 单租户最大占比 (防止单租户占满集群)
    maxTenantRatio: 0.2  # 20%
```

---

### 10.7 总结: Per-Tenant Namespace 场景

| 租户规模 | 推荐方案 |
|---------|---------|
| < 20 租户 | **方案 F** (GitOps Per-Tenant) |
| 20-50 租户 | **方案 G** (混合策略) |
| > 50 租户 | **方案 E** (ConfigMap) + 容量规划 |
| 任何规模 | **方案 B** (豁免) 作为快速通道 |

**核心原则**:
1. **每个租户独立 Namespace** → 每个租户可以有独立的 Constraint
2. **GitOps 管理所有配置** → PR 审批 = 变更审计
3. **全局安全网不变** → 防止任何租户耗尽集群资源
4. **配额调整走流程** → 不是改全局 Constraint，而是为租户创建/调整专属 Constraint

---

## 11. Cluster-Level vs Namespace-Level 策略分配

### 11.1 问题定义

当设计 Gatekeeper 策略时，一个核心问题是：**这条规则应该在 Cluster 级别生效，还是 Namespace 级别生效？**

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cluster-Level Constraint                       │
│                         (作用于整个集群)                            │
│                                                                     │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│   │  NS-A    │  │  NS-B    │  │  NS-C    │  │  NS-D    │        │
│   │ team-a    │  │ team-b   │  │ team-c   │  │ team-d   │        │
│   └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
│   ← ────────────────── 同一套规则 ────────────────── →            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   Namespace-Level Constraint                      │
│                       (仅作用于特定 NS)                            │
│                                                                     │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│   │  NS-A    │  │  NS-B    │  │  NS-C    │  │  NS-D    │        │
│   │ team-a   │  │ team-b   │  │ team-c   │  │ team-d   │        │
│   │  规则-A  │  │  规则-B  │  │  规则-C  │  │  规则-D  │        │
│   └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
│   ← 差异化规则，各自独立 ─                                          │
└─────────────────────────────────────────────────────────────────┘
```

### 11.2 判断决策树

```
这条规则应该在哪里生效？

    │
    ├── 规则作用于 Kubernetes 集群级别的资源?
    │   ├── Namespace、StorageClass、ClusterRole、ClusterRoleBinding
    │   ├── PersistentVolume、CustomResourceDefinition
    │   └── 答案 → 必须 Cluster-Level
    │
    ├── 这是一条安全基线/合规要求，必须对所有租户一致?
    │   ├── PSP 安全策略、禁止 privileged 容器
    │   ├── 强制 HTTPS、禁止公网暴露
    │   └── 答案 → 必须 Cluster-Level
    │
    ├── 这个规则如果太严格会影响部分租户业务?
    │   ├── 资源限制 (CPU/Memory)
    │   ├── 副本数限制
    │   └── 答案 → Namespace-Level (允许差异化)
    │
    ├── 不同租户对该规则有合理的差异化需求?
    │   ├── AI 训练需要 64Gi 内存，普通 Web 只需要 4Gi
    │   ├── 特殊业务需要更多副本数
    │   └── 答案 → Namespace-Level (Per-tenant)
    │
    └── 这是平台提供的"可选能力"，租户可选择是否启用?
        └── 答案 → Namespace-Level (租户自选)
```

### 11.3 判断维度分析

#### 维度 1: 规则性质

| 规则性质 | 推荐级别 | 原因 |
|---------|---------|------|
| **安全基线** | Cluster-Level | 安全策略必须一致，不能有漏洞 |
| **合规要求** | Cluster-Level | 监管要求统一适用 |
| **资源配额** | Namespace-Level | 租户需求差异，需要灵活配置 |
| **业务策略** | Namespace-Level | 不同租户有不同业务需求 |
| **可观测性** | Namespace-Level | 租户自主选择 |

#### 维度 2: 变更频率

| 变更频率 | 推荐级别 | 原因 |
|---------|---------|------|
| **几乎不变** | Cluster-Level | 安全基线不需要频繁调整 |
| **经常调整** | Namespace-Level | 租户配额调整不应该影响全局 |
| **动态变化** | Namespace-Level + ConfigMap | 需要程序化动态调整 |

#### 维度 3: 影响范围

| 影响范围 | 推荐级别 | 原因 |
|---------|---------|------|
| **全局资源** | Cluster-Level | 如 Namespace 创建、StorageClass |
| **单租户资源** | Namespace-Level | 如 Deployment、Pod |
| **跨租户协作** | Cluster-Level | 需要全局协调 |

### 11.4 策略分级映射表

基于你已有的授权资源，以下是推荐的 Cluster/Namespace 分级：

#### 必须 Cluster-Level 的策略

| 策略 | Constraint | 原因 |
|------|-----------|------|
| **PSP Baseline** | K8sPSPBaseline | 安全基线，集群统一 |
| **禁止 Privileged 容器** | K8sPSPPrivilegedContainer | 安全红线 |
| **禁止 HostPID/IPC** | K8sPSPHostNamespace | 安全隔离 |
| **强制 Ingress HTTPS** | K8sHttpsOnly | 合规要求 |
| **禁止 LoadBalancer** | K8sBlockLoadBalancer | 公网暴露风险 |
| **禁止 NodePort** | K8sBlockNodePort | 端口暴露风险 |
| **StorageClass 白名单** | K8sStorageClass | 存储治理 |
| **Required Labels (基础)** | K8sRequiredLabels | 必须的元数据标签 |

#### 建议 Namespace-Level 的策略

| 策略 | Constraint | 租户差异化原因 |
|------|-----------|--------------|
| **Container CPU 限制** | K8sContainerLimits | AI/大数据需要更多 CPU |
| **Container Memory 限制** | K8sContainerLimits | ML 训练需要大内存 |
| **Replica 数量上限** | K8sReplicaLimits | 不同服务规模不同 |
| **Required Labels (业务)** | K8sRequiredLabels | team/owner 等业务标签 |
| **Required Probes** | K8sRequiredProbes | 可选，取决于服务类型 |
| **HPA 副本范围** | K8sHPABounds | 租户业务规模差异 |

#### 可选 Namespace-Level 的策略

| 策略 | Constraint | 说明 |
|------|-----------|------|
| **NetworkPolicy** | K8sNetworkPolicies | 租户可选择网络隔离策略 |
| **PodDisruptionBudget** | K8sRequiredPDB | 关键应用可选 |
| **Image 白名单** | K8sAllowedRepos | 不同租户使用不同镜像源 |

### 11.5 实际配置示例

#### Cluster-Level 配置 (全局安全基线)

```yaml
# Cluster-Level: 安全基线约束
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPBaseline
metadata:
  name: cluster-psp-baseline
spec:
  enforcementAction: deny    # 强制执行
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet", "ReplicaSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
    # 不排除任何 namespace，作用于全集群
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sHttpsOnly
metadata:
  name: cluster-https-only
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["networking.k8s.io"]
      kinds: ["Ingress"]
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockLoadBalancer
metadata:
  name: cluster-block-lb
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockNodePort
metadata:
  name: cluster-block-nodeport
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
```

#### Namespace-Level 配置 (租户差异化配额)

```yaml
# Namespace-Level: 默认租户配额
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: ns-default-container-limits
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    # 只作用于没有特殊标签的 namespace
    namespaceSelector:
      matchExpressions:
      - key: tier
        operator: NotIn
        values:
        - special
        - gpu
  parameters:
    cpu: "4"
    memory: "8Gi"
---
# Namespace-Level: 特殊租户配额
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: ns-special-container-limits
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
    namespaceSelector:
      matchExpressions:
      - key: tier
        operator: In
        values:
        - special
        - gpu
  parameters:
    cpu: "16"
    memory: "64Gi"
    exemptImages:
    - "nvidia/*"
```

### 11.6 层级叠加与冲突处理

当 Cluster-Level 和 Namespace-Level 同时存在时：

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cluster-Level Constraint                        │
│                        CPU Max: 4 (deny)                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Namespace-Level Constraint                       │
│                   CPU Max: 16 (tier=special)                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    实际生效规则: 取更严格的限制
                    即: min(Cluster, Namespace) = 4
                    
                    ⚠️ 如果 Namespace 设置 16 > Cluster 设置 4
                       实际仍然是 4，不会突破 Cluster 上限
```

**冲突处理原则**:

| 场景 | 处理方式 |
|------|---------|
| Cluster: 4C, NS: 8C | **Cluster 胜出** — 全局安全网优先级高 |
| Cluster: deny, NS: exempt | **Cluster 胜出** — 安全策略不可豁免 |
| Cluster: dryrun, NS: deny | **各自生效** — audit + enforcement 并行 |

**结论**: Cluster-Level 是安全上限，Namespace-Level 不能突破。

### 11.7 分层架构推荐

```
┌─────────────────────────────────────────────────────────────────┐
│                    Layer 0: 绝对红线 (不可突破)                    │
│                                                                     │
│   Cluster-Level Only, enforcementAction: deny                      │
│   ├── 禁止 privileged 容器                                         │
│   ├── 禁止 hostPID/hostIPC                                        │
│   ├── 禁止 LoadBalancer (除非明确申请)                              │
│   └── 强制 Ingress HTTPS                                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Layer 1: 安全基线 (建议统一)                       │
│                                                                     │
│   Cluster-Level, enforcementAction: deny/warn                      │
│   ├── PSP Baseline 所有检查项                                       │
│   ├── StorageClass 白名单                                          │
│   ├── Required Labels (基础标签)                                   │
│   └── 禁止 NodePort (可选)                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Layer 2: 资源治理 (差异化)                          │
│                                                                     │
│   Namespace-Level, 每个租户可配置不同值                              │
│   ├── Container CPU/Memory Limits                                 │
│   ├── Replica 数量上限                                            │
│   └── HPA 副本范围                                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Layer 3: 业务策略 (可选)                            │
│                                                                     │
│   Namespace-Level, 租户自选                                         │
│   ├── Required Probes                                             │
│   ├── NetworkPolicy                                              │
│   ├── PodDisruptionBudget                                        │
│   └── Image 白名单                                                │
└─────────────────────────────────────────────────────────────────┘
```

### 11.8 管理复杂度权衡

| 分层方式 | 管理复杂度 | 灵活性 | 推荐场景 |
|---------|----------|--------|---------|
| **全部 Cluster-Level** | 低 | 低 | 租户少、需求一致 |
| **全部 Namespace-Level** | 中 | 高 | 多租户、需要差异化 |
| **分层 (推荐)** | 中 | 高 | 绝大多数场景 |

**关键洞察**:

- **安全类 → Cluster-Level**: 简单、不易出错、强制统一
- **配额类 → Namespace-Level**: 差异化需求、灵活调整
- **混合场景 → Layered Approach**: 分层设计，Layer 0 > Layer 1 > Layer 2

### 11.9 总结: Cluster vs Namespace 选择

| 判断问题 | 如果是 Yes → 选择 | 如果是 No → 继续判断 |
|---------|-----------------|-------------------|
| 这是安全基线或合规要求？ | **Cluster-Level** | ↓ |
| 不同租户可能有合理差异化需求？ | **Namespace-Level** | ↓ |
| 规则作用于集群级资源 (NS/SC/PV)？ | **Cluster-Level** | Namespace-Level |
| 规则太严格会影响部分租户业务？ | **Namespace-Level** | Cluster-Level |

**最终推荐分层结构**:

```
Cluster-Level (安全基线):
├── PSP Baseline / Restricted
├── HTTPS 强制
├── LoadBalancer/NodePort 禁止
├── StorageClass 白名单
└── 基础 Required Labels

Namespace-Level (资源治理):
├── Container Limits (差异化配额)
├── Replica Limits (租户规模)
├── HPA Bounds (业务峰值)
└── 业务 Required Labels

Namespace-Level (可选):
├── Required Probes
├── NetworkPolicy
└── Image Whitelist
```

---

## 9. 总结

| 场景 | 推荐方案 |
|------|---------|
| 已知特殊租户，提前分类 | **方案 A** (Namespace 标签分层) |
| 遗留系统，无法修改 | **方案 B** (excludedNamespaces) |
| 平台级规范化治理 | **方案 C** (GitOps PR 审批) |
| 需要动态调整 | **方案 A + CronJob 清理** |
| **Per-Tenant NS (每租户独立 NS)** | **方案 F/G** (GitOps Per-Tenant Constraint) |
| **Cluster vs Namespace 策略分配** | **分层设计** (第11章) |

**核心原则**:
1. **全局限制是安全网**，不应该频繁调整
2. **特殊需求通过豁免机制处理**，而不是放宽全局限制
3. **所有豁免都需要审计追踪**，避免成为安全漏洞
4. **Per-Tenant 场景**: 每个租户 NS 可以有自己专属的 Constraint，通过 GitOps 统一管理
5. **策略级别分配**: 安全基线 → Cluster-Level；资源配额 → Namespace-Level

---

*文档维护: 如有更新建议，请提交 PR 或联系平台团队。*
*版本更新: v1.2.0 - 新增第10章 Per-Tenant Namespace 场景最佳实践、第11章 Cluster vs Namespace 策略分配*
