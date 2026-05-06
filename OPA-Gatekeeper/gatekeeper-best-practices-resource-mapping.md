# Gatekeeper Best Practices - Resource Mapping Guide

> **文档版本**: 1.0.0
> **更新日期**: 2026-05-04
> **目标读者**: 平台架构师、SRE、DevOps 工程师
> **适用范围**: GKE + 阿里云 ACK 多集群环境

---

## 1. 概述

本文档基于你已授权的 Kubernetes 资源类型，映射到对应的 Gatekeeper 策略，提供完整的最佳实践指导。

### 1.1 已授权资源一览

| 资源类型 | API Group | 说明 |
|---------|-----------|------|
| Deployment | apps | 无状态工作负载 |
| StatefulSet | apps | 有状态工作负载 |
| CronJob | batch | 定时任务 |
| Job | batch | 一次性任务 |
| HorizontalPodAutoscaler | autoscaling | 自动扩缩容 |
| StorageClass | storage.k8s.io | 存储类 |
| PersistentVolumeClaim | core | 持久卷声明 |
| ReplicationController | core | 副本控制器 |
| Ingress | networking.k8s.io | HTTP/HTTPS 路由 |
| NetworkPolicy | networking.k8s.io | 网络策略 |
| PodDisruptionBudget | policy | Pod 中断预算 |

### 1.2 资源分类矩阵

```
┌─────────────────────────────────────────────────────────────────┐
│                    按用途分类的推荐策略                            │
├─────────────────┬───────────────────────────────────────────────┤
│ 工作负载安全      │ Container Limits / Required Labels / PSP    │
│ 网络安全          │ Ingress HTTPS / NetworkPolicy / Block LB/NP  │
│ 资源治理          │ Replica Limits / StorageClass / HPA Limits   │
│ 变更控制          │ Immutable Fields / PDB Validation            │
│ 可观测性          │ Required Probes / Labels                     │
└─────────────────┴───────────────────────────────────────────────┘
```

---

## 2. 工作负载类资源 (Deployment / StatefulSet / Job / CronJob)

### 2.1 资源共性分析

| 资源 | 是否含 Pod Spec | 是否含容器 | 是否有 Label | 是否有 Replica |
|------|----------------|-----------|-------------|----------------|
| Deployment | ✅ | ✅ | ✅ | ✅ |
| StatefulSet | ✅ | ✅ | ✅ | ✅ (固定名称) |
| Job | ✅ | ✅ | ✅ | ❌ (并行度可控) |
| CronJob | ✅ (JobTemplate) | ✅ | ✅ | ❌ |

### 2.2 推荐策略组合

#### 策略 1: K8sRequiredLabels - 强制标签

**目标**: 确保所有工作负载携带必要的元标签

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: workload-must-have-required-labels
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
    labels:
    - key: "app"
    - key: "environment"
      allowedRegex: "^(prod|staging|dev|test)$"
    - key: "team"
      allowedRegex: "^(frontend|backend|platform|data|ml)$"
    - key: "cost-center"
```

**最佳实践**:
- `app`: 标识应用名称
- `environment`: 强制值枚举，防止 `prod` 误写为 `production`
- `team`: 方便归属和权限隔离
- `cost-center`: 成本归集（金融场景必备）

---

#### 策略 2: K8sContainerLimits - 容器资源限制

**目标**: 防止无限制资源占用

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: workload-container-limits
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
  parameters:
    cpu: "8"           # 最大 8 核
    memory: "32Gi"      # 最大 32Gi
    exemptImages:
    - "gcr.io/distroless/*"  # 豁免最小化镜像
    - "registry.example.com/internal/*"
```

**参数建议**:

| 环境 | CPU Max | Memory Max | 说明 |
|------|---------|------------|------|
| dev | 4 | 16Gi | 开发环境宽松 |
| staging | 8 | 32Gi | 预生产环境 |
| prod | 16 | 64Gi | 生产环境 |

---

#### 策略 3: K8sReplicaLimits - 副本数限制

**目标**: 防止意外大规模扩缩容

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sReplicaLimits
metadata:
  name: workload-replica-limits
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
  parameters:
    ranges:
    - min: 1
      max: 10
      targetKind: Deployment
    - min: 1
      max: 5
      targetKind: StatefulSet
```

**最佳实践**:
- Deployment: `1-10` 副本适合大多数应用
- StatefulSet: `1-5` 副本（状态ful 通常更谨慎）
- Job: 不设副本限制（由 `parallelism` 控制）

---

#### 策略 4: K8sRequiredProbes - 健康检查探针

**目标**: 确保服务可观测和自愈

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredProbes
metadata:
  name: workload-required-probes
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    excludedNamespaces:
    - kube-system
    - istio-system
  parameters:
    probes:
    - readinessProbe
    - livenessProbe
    probeTypes:
    - tcpSocket
    - httpGet
    - exec
    exemptImages:
    - "*pause*"           # pause 容器豁免
    - "busybox*"          # 工具镜像豁免
```

**最佳实践**:
- Deployment: 必须有 `readinessProbe` + `livenessProbe`
- StatefulSet: 通常需要 `readinessProbe`（标识初始准备完成）
- Job/CronJob: 通常不需要探针（执行完就结束）
- 排除 `istio-system`：Istio 自动注入的 sidecar 会有自己的健康检查

---

#### 策略 5: K8sPSPBaseline - Pod 安全基线

**目标**: 强制基本安全隔离

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPBaseline
metadata:
  name: workload-psp-baseline
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet", "ReplicaSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
    excludedNamespaces:
    - kube-system
  parameters:
    exemptImages:
    - "gcr.io/distroless/*"
```

**PSP Baseline 检查项**:

| 检查项 | 说明 | 风险等级 |
|--------|------|---------|
| K8sPSPPrivilegedContainer | 禁止 privileged 容器 | 🔴 高 |
| K8sPSPHostNamespace | 禁止共享 host PID/IPC | 🔴 高 |
| K8PSPAllowPrivilegeEscalationContainer | 禁止特权升级 | 🔴 高 |
| K8sPSPReadOnlyRootFilesystem | 要求只读根文件系统 | 🟡 中 |
| K8sPSPCapabilities | 限制 Linux Capabilities | 🟡 中 |

---

## 3. 存储类资源 (StorageClass / PersistentVolumeClaim)

### 3.1 存储资源映射

```
StorageClass (存储类定义)
    │
    └── PersistentVolumeClaim (存储使用声明)
              │
              └── Pod 挂载使用
```

### 3.2 推荐策略: K8sStorageClass - 存储类限制

**目标**: 强制使用approved的存储类

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sStorageClass
metadata:
  name: allowed-storage-class
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["PersistentVolumeClaim"]
  parameters:
    allowedStorageClasses:
    - "standard"           # GCP 默认 HDD
    - "ssd"               # GCP SSD
    - "regional-ssd"      # 区域冗余 SSD
    - "ack-standard"      # 阿里云标准盘
    - "ack-ssd"           # 阿里云 SSD
```

**最佳实践**:

| 存储类 | 适用场景 | 成本等级 |
|--------|---------|---------|
| standard / ack-standard | 日志、临时存储 | 💰 低 |
| ssd / ack-ssd | 数据库、中间件 | 💰💰 中 |
| regional-ssd | 数据安全要求高的生产数据 | 💰💰💰 高 |

**注意**: StorageClass 本身是集群级别资源，通常由管理员预先定义好，不需要频繁创建。

---

## 4. 网络类资源 (Ingress / NetworkPolicy)

### 4.1 推荐策略: K8sHttpsOnly - 强制 HTTPS

**目标**: 禁止 HTTP 明文传输

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sHttpsOnly
metadata:
  name: ingress-https-only
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["networking.k8s.io"]
      kinds: ["Ingress"]
  parameters:
    tlsOptional: false  # false = 必须有 TLS 配置
```

**最佳实践**:
- `tlsOptional: false` — 所有 Ingress 必须配置 TLS
- 配合 `kubectl get ingress -A` 审计现有 HTTP 入口
- 考虑强制 `spec.tls[].secretName` 必须引用真实存在的 Secret

---

### 4.2 推荐策略: K8sNetworkPolicy - 命名空间级隔离

**目标**: 微服务间默认拒绝，精细化放行

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sNetworkPolicies
metadata:
  name: namespace-must-have-network-policy
spec:
  enforcementAction: dryrun  # 初始用 dryrun，逐步收紧
  match:
    kinds:
    - apiGroups: ["networking.k8s.io"]
      kinds: ["NetworkPolicy"]
  parameters:
    # 检查是否限制了入口/出口流量
    allowEmpty: false
```

**推荐网络策略模板**:

```yaml
# 默认拒绝所有入口流量
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress

---
# 默认拒绝所有出口流量
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
spec:
  podSelector: {}
  policyTypes:
  - Egress
```

**分环境策略**:

| 环境 | 建议 | 原因 |
|------|------|------|
| dev | dryrun | 快速迭代，减少阻碍 |
| staging | warn | 记录违规但不阻止 |
| prod | deny | 严格执法 |

---

### 4.3 推荐策略: K8sBlockLoadBalancer / NodePort

**目标**: 防止意外公网暴露

```yaml
# 禁止 LoadBalancer Service
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockLoadBalancer
metadata:
  name: block-loadbalancer-service
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
    excludedNamespaces:
    - ingress-nginx    # 保留 ingress controller
    - cert-manager     # TLS 自动化需要

---
# 禁止 NodePort Service
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockNodePort
metadata:
  name: block-nodeport-service
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Service"]
    excludedNamespaces:
    - kube-system
```

**最佳实践**:
- 生产环境强烈建议 `deny` LoadBalancer/NodePort
- 通过 Ingress 或 Gateway API 统一入口
- 例外 namespace 需要经过安全评审

---

## 5. 自动扩缩容资源 (HorizontalPodAutoscaler)

### 5.1 HPA 资源分析

HPA 本身不创建容器，但它控制 Deployment/StatefulSet 的副本数。

| 特性 | 说明 |
|------|------|
| 控制目标 | Deployment/ReplicaSet/StatefulSet |
| 指标类型 | CPU、内存、自定义指标 |
| 副本范围 | 由 `minReplicas` / `maxReplicas` 控制 |

### 5.2 推荐策略: HPA 边界校验 (自定义 Rego)

**目标**: 防止 HPA 配置错误导致资源浪费或服务不可用

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sHPABounds
metadata:
  name: hpa-replica-bounds
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: ["autoscaling"]
      kinds: ["HorizontalPodAutoscaler"]
    excludedNamespaces:
    - kube-system
  parameters:
    minReplicas: 1
    maxReplicas: 50
    # 建议 maxReplicas 不超过节点数的 1/3
```

**最佳实践**:

| 场景 | minReplicas | maxReplicas | 说明 |
|------|-------------|-------------|------|
| 关键服务 | 3 | 20 | 高可用保障 |
| 普通服务 | 1 | 10 | 成本优先 |
| Job 驱动的 HPA | 1 | 5 | 批处理作业 |

**与 ReplicaLimits 配合**:
- HPA `maxReplicas` ≤ Deployment `spec.replicas` 上限
- 两个策略协同避免冲突

---

## 6. Pod 中断预算 (PodDisruptionBudget)

### 6.1 PDB 资源分析

| 特性 | 说明 |
|------|------|
| 保护对象 | Deployment 的 Pod |
| 约束方式 | `minAvailable` 或 `maxUnavailable` |
| 触发场景 | 节点维护、驱赶、扩缩容 |

### 6.2 推荐策略: PDB 存在性检查 (自定义 Rego)

**目标**: 关键应用必须有 PDB 保护

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredPDB
metadata:
  name: critical-app-must-have-pdb
spec:
  enforcementAction: dryrun  # 初始审计
  match:
    kinds:
    - apiGroups: ["policy"]
      kinds: ["PodDisruptionBudget"]
    # 标签选择器可以针对特定应用
    labelSelector:
      matchLabels:
        pdb-required: "true"
  parameters:
    # 对于无标签选择器的 PDB，必须配置 minAvailable 或 maxUnavailable
    requirePdb: true
```

**最佳实践**:

| 应用类型 | 推荐 PDB 配置 | 说明 |
|---------|--------------|------|
| 无状态服务 | `minAvailable: 50%` | 允许一半 Pod 同时中断 |
| 有状态服务 | `minAvailable: N-1` | 保留最少实例 |
| 单副本 | ❌ 不需要 PDB | 反正只有一个 |

**强制 vs 审计**:
- `prod` 环境: `deny` — 新建关键应用必须带 PDB
- `dev/staging`: `dryrun` — 记录但不阻止

---

## 7. 综合部署清单

### 7.1 分环境部署顺序

```
Phase 1: 审计阶段 (1-2周)
    │
    ├── K8sRequiredLabels (dryrun)
    ├── K8sContainerLimits (dryrun)
    ├── K8sReplicaLimits (dryrun)
    ├── K8sHPABounds (dryrun)
    └── K8sRequiredProbes (dryrun)
    │
    ▼
Phase 2: 警告阶段 (1周)
    │
    ├── 收集 Phase 1 数据
    ├── 与团队沟通修复计划
    └── 将 dryrun 改为 warn (部分策略)
    │
    ▼
Phase 3: 强制执行 (持续)
    │
    ├── prod: dryrun → deny
    ├── staging: dryrun → warn
    └── dev: 保持 dryrun
```

### 7.2 推荐 Constraints 部署顺序

```bash
# Step 1: 标签策略 (最早部署)
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: workload-required-labels
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
  parameters:
    labels:
    - key: "app"
    - key: "environment"
      allowedRegex: "^(prod|staging|dev|test)$"
EOF

# Step 2: 资源限制
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sContainerLimits
metadata:
  name: workload-container-limits
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
  parameters:
    cpu: "8"
    memory: "32Gi"
EOF

# Step 3: 网络策略
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sHttpsOnly
metadata:
  name: ingress-https-only
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: ["networking.k8s.io"]
      kinds: ["Ingress"]
EOF

# Step 4: 安全基线
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPBaseline
metadata:
  name: workload-psp-baseline
spec:
  enforcementAction: dryrun
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment", "StatefulSet"]
    - apiGroups: ["batch"]
      kinds: ["Job", "CronJob"]
EOF
```

### 7.3 分环境参数对照表

| Constraint | dev | staging | prod |
|-----------|-----|---------|------|
| K8sRequiredLabels | dryrun | warn | deny |
| K8sContainerLimits | dryrun | deny | deny |
| K8sReplicaLimits | dryrun | warn | deny |
| K8sRequiredProbes | dryrun | warn | deny |
| K8sHPABounds | dryrun | dryrun | deny |
| K8sHttpsOnly | dryrun | deny | deny |
| K8sPSPBaseline | dryrun | warn | deny |
| K8sBlockLoadBalancer | dryrun | deny | deny |
| K8sBlockNodePort | dryrun | deny | deny |
| K8sStorageClass | dryrun | deny | deny |

---

## 8. 故障排查与验证

### 8.1 常用验证命令

```bash
# 查看所有 Constraints 状态
kubectl get constraints

# 查看单个 Constraint 的 Violations
kubectl get k8srequiredlabels workload-required-labels -o jsonpath='{.status.violations}' | jq '.'

# 查看审计结果（定期任务）
kubectl logs -n gatekeeper-system deployment/gatekeeper-audit --tail=100

# 查看 Controller 实时拦截
kubectl logs -n gatekeeper-system deployment/gatekeeper-controller-manager --tail=100 | grep -E "denied|violation"

# 模拟测试 Constraint
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  labels:
    app: test
spec:
  containers:
  - name: nginx
    image: nginx:latest
EOF

# 查看模拟结果
kubectl get k8scontainerlimits workload-container-limits -o jsonpath='{.status.violations}' | jq '.'
```

### 8.2 Violation 修复流程

```
发现 Violation
    │
    ├── 资源属于 kube-system/gatekeeper-system?
    │   └── 是 → 添加到 excludedNamespaces
    │
    ├── 资源是新创建的但缺少标签?
    │   └── 是 → 添加对应 labels 后重新 apply
    │
    ├── 资源是遗留资源?
    │   └── 是 → 评估是否可以修改，或豁免该 namespace
    │
    └── 资源明确违规?
        └── 是 → 强制模式下拒绝，dev模式下记录审计
```

### 8.3 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `ConstraintTemplate not found` | 模板未安装 | `kubectl apply -f` 模板 YAML |
| `kind not found` | ConstraintTemplate 名称不匹配 | 检查 `kind:` 是否来自已有 Template |
| `enforcementAction invalid` | 只支持 `deny`/`dryrun`/`warn` | 修正为合法值 |
| 大量 Violations 突然出现 | 审计周期触发 | 正常现象，用 `dryrun` 观察 |

---

## 9. 参考链接

| 资源 | URL |
|------|-----|
| Gatekeeper 官方 | https://open-policy-agent.github.io/gatekeeper/ |
| Gatekeeper Library | https://github.com/open-policy-agent/gatekeeper-library |
| PSP 模板库 | https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/pod-security-policy |
| 本地约束探索文档 | `constraint-explorers/README.md` |
| 选型对比文档 | `gke-policy-controller-with-gatekeeper.md` |

---

## 10. 附录: 自定义扩展

### 10.1 创建自定义 ConstraintTemplate

如需针对特定业务场景的策略，可以创建自定义 Template：

```yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: k8srequiredenvvars
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredEnvVars
      validation:
        openAPIV3Schema:
          properties:
            envVars:
              type: array
              items:
                type: string
  targets:
    - target: admission
      rego: |
        package k8srequiredenvvars
        
        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not container.env
          msg := "Container must have env vars defined"
        }
```

### 10.2 豁免 (Exemptions) 最佳实践

```yaml
# 豁免正则匹配镜像
parameters:
  exemptImages:
  - "gcr.io/distroless/*"     # 最小化镜像
  - "*.example.com/internal/*" # 内部镜像
  - "sha256:*"                # 特定 SHA 镜像

# 豁免特定 Namespace
spec:
  match:
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    - istio-system
    - cert-manager
```

---

*文档维护: 如有更新建议，请提交 PR 或联系平台团队。*
