---
name: gatekeeper-multi-tenant-governance
description: OPA Gatekeeper 多租户命名空间治理与资源配额异常处理。当需要在多租户 K8s 环境中使用 Gatekeeper 实现差异化的资源配额管理、处理特殊租户超额需求、或设计 per-tenant Namespace 隔离策略时使用。包含豁免机制、GitOps 审批流、容量规划等最佳实践。
category: gcp
---

# Gatekeeper Multi-Tenant Governance — 多租户治理最佳实践

## 何时使用

用户要求处理以下问题时使用：
- 多租户环境下资源配额差异化配置
- 特殊租户需求超出全局限制的处理方案
- Per-tenant Namespace 场景下的 Constraint 设计
- 租户配额申请与审批流程设计

## 核心文档

| 文档 | 说明 |
|------|------|
| `gatekeeper-best-practices-resource-mapping.md` | 11 种授权资源类型 → Gatekeeper 策略映射指南 |
| `multi-tenant-resource-quota-exception-handling.md` | 资源配额异常处理完整方案（含 per-tenant 章节） |

## Per-Tenant Namespace 场景核心模式

### 场景定义

```
传统模式: Namespace = 功能分区 (dev/staging/prod)
Per-Tenant 模式: Namespace = 租户边界 (team-a/team-b/team-c/...)
```

### 推荐方案: 方案 F (GitOps Per-Tenant Constraint)

每个租户 NS 有独立的 Constraint YAML 文件，通过 GitOps 统一管理：

```
policy-library/
├── constraints/
│   ├── _templates/
│   └── tenants/
│       ├── team-ai-training/
│       │   └── container-limits.yaml    # 16C64Gi
│       ├── team-bigdata/
│       │   └── container-limits.yaml    # 8C32Gi
│       └── _defaults/
│           └── container-limits.yaml    # 默认 4C8Gi
```

### 差异化 Constraint 模板

```yaml
# 默认租户 Constraint
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

---

# 特殊租户 Constraint (通过 namespaceSelector 匹配)
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
    exemptImages:
    - "nvidia/*"
```

## 豁免机制 (Exemptions)

| 方式 | 说明 | 适用场景 |
|------|------|---------|
| `excludedNamespaces` | 整个 Namespace 豁免 | 系统组件、特殊业务单元 |
| `exemptImages` | 特定镜像豁免 | 基础设施镜像、已知合规镜像 |
| `labelSelector` | 按资源标签豁免 | 特定 Deployment 需要特殊处理 |

```yaml
# 资源标签豁免 (Gatekeeper v3.12+)
spec:
  match:
    labelSelector:
      matchExpressions:
      - key: quota-exempt
        operator: DoesNotExist  # 不带此标签的资源才受限制
```

## 新增租户自动化脚本

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
```

## 方案对比

| 方案 | 复杂度 | 适用场景 | 推荐度 |
|------|--------|---------|--------|
| 方案 E: ConfigMap 配额表 | ⭐⭐⭐ | >50 租户，动态配额 | ⭐⭐⭐ |
| 方案 F: GitOps Per-Tenant | ⭐⭐⭐⭐ | <50 租户，声明式管理 | ⭐⭐⭐⭐ |
| 方案 G: 混合策略 | ⭐⭐⭐ | 全局安全网 + 租户豁免 | ⭐⭐⭐ |

## 核心原则

1. **全局限制是安全网**，不应该频繁调整
2. **特殊需求通过豁免机制处理**，而不是放宽全局限制
3. **所有豁免都需要审计追踪**，避免成为安全漏洞
4. **Per-Tenant 场景**: 每个租户 NS 可以有自己专属的 Constraint，通过 GitOps 统一管理

## Git 提交流程

```bash
cd /Users/lex/git/gcp
git add OPA-Gatekeeper/
git commit -m "docs: add/update gatekeeper multi-tenant governance docs"
git push
```

## 相关 Skill

- `gatekeeper-constraints`: ConstraintTemplate 探索文档编写规范（`constraint-explorers/` 目录）
- `architectrue`: GKE/GCP 架构总览，包含 Gatekeeper 选型指南
