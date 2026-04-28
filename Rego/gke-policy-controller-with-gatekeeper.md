# GKE Policy Controller vs Standalone Gatekeeper 选型指南

## 1. 背景与需求

你的实际场景：
- **当前环境**：GKE（Google Kubernetes Engine）
- **未来环境**：阿里云 ACK（原生 Kubernetes）
- **核心诉求**：启用 OPA Gatekeeper 实现策略即代码（Policy as Code）
- **关注点**：Rego 策略的可移植性、维护性、跨云一致性

---

## 2. 产品定位对比

| 维度 | GKE Policy Controller | Standalone Gatekeeper |
|------|----------------------|----------------------|
| **本质** | GCP 原生托管的 Gatekeeper | 独立开源项目（CNCF） |
| **安装方式** | GKE 集群一键启用 / Fleet 管理 | 手动 helm/kubectl 部署 |
| **版本更新** | 随 GKE 版本绑定，延迟较慢 | 独立迭代，更新快 |
| **维护负担** | Google 托管，无需手动升级 | 需要自行维护升级 |
| **预置策略库** | ✅ 100+ GCP 官方策略 | ❌ 需自行编写 |
| **Dashboard** | GCP Console 原生集成 | 需自行搭建 |
| **审计日志** | Cloud Logging 原生集成 | 需自行配置 |
| **多云支持** | 仅 GKE | 任意 K8s 集群 |

---

## 3. 核心差异详解

### 3.1 安装与运维

**GKE Policy Controller**

```bash
# 通过 GKE 集群启用（控制台或 CLI）
gcloud container clusters update my-cluster \
  --enable-policy-controller \
  --region=us-central1

# 或通过 Fleet 管理（推荐多集群场景）
gcloud container fleet policy-controller enable
```

**Standalone Gatekeeper**

```bash
# Helm 部署
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --set auditInterval=300 \
  --set validationInterval=300
```

### 3.2 预置策略库

**GKE Policy Controller** 提供开箱即用的策略：

| 类别 | 策略名称 | 功能 |
|------|----------|------|
| **安全** | CIS Kubernetes Benchmark | K8s 安全基线 |
| **安全** | No Public IPs | 禁止公网 IP |
| **安全** | No Privileged Containers | 禁止特权容器 |
| **标签** | Require labels | 强制标签校验 |
| **网络** | Restrict External IPs | 限制 External IPs |
| **资源** | Container Limits | 强制资源限制 |

**Standalone Gatekeeper** 无预置，需自行编写或从社区获取。

### 3.3 策略格式兼容性

**两者完全兼容** —— GKE Policy Controller 基于 Gatekeeper，二者使用相同的：

- `ConstraintTemplate` (v1 / v1beta1)
- `Constraint` (v1beta1 / v1)
- Rego 语法

这意味着：**同一套 Rego 代码可以直接在两者间复用**。

---

## 4. Rego 策略可移植性分析

### 4.1 跨平台复用的前提条件

要让 Rego 策略在 GKE 和阿里云 ACK 间完全复用，需满足：

| 条件 | 说明 |
|------|------|
| **Gatekeeper 版本一致** | v3.12+ 推荐，v3.9+ 基本兼容 |
| **ConstraintTemplate API 版本** | 使用 `templates.gatekeeper.sh/v1` |
| **Kubernetes API 版本** | 使用 `constraints.gatekeeper.sh/v1beta1` 或 `v1` |
| **无 GCP 特定依赖** | 避免使用 `data.admissionregistration.k8s.io` 等 GCP 特有路径 |

### 4.2 GKE 和阿里云 ACK 的差异

| 维度 | GKE | 阿里云 ACK |
|------|-----|------------|
| **Gatekeeper 支持** | 原生集成 Policy Controller | 需手动部署 |
| **K8s 版本** | 1.26+ 默认禁用 shell | 自行选择版本 |
| **网络策略** | Calico / Cilium | Terway |
| **RBAC 集成** | GCP IAM | RAM 权限体系 |

### 4.3 推荐策略结构（最大化可移植性）

```
policy-library/
├── templates/              # ConstraintTemplate 模板（跨集群复用）
│   ├── K8sContainerLimits/
│   ├── GKEResourceWhitelist/
│   └── RequireLabels/
├── constraints/            # Constraint 实例（按集群差异化配置）
│   ├── gke/
│   │   ├── prod-constraints.yaml
│   │   └── dev-constraints.yaml
│   └── aliyun/
│       ├── prod-constraints.yaml
│       └── dev-constraints.yaml
└── scripts/
    └── deploy.sh           # 统一部署脚本
```

---

## 5. 多云架构建议

### 5.1 推荐方案：Standalone Gatekeeper

**理由**：

1. **跨云一致性**：同一套 Gatekeeper 部署方式，同时覆盖 GKE 和 ACK
2. **版本可控**：不受 GCP 版本绑定限制
3. **策略统一**：一套 Rego 代码，多集群复用
4. **社区活跃**：CNCF 项目，长期可维护

### 5.2 GKE 上的特殊处理

在 GKE 上启用 Standalone Gatekeeper 而非 Policy Controller：

```yaml
# 通过 Gatekeeper Operator 部署（推荐）
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: gatekeeper-operator
  namespace: operators
spec:
  channel: stable
  name: gatekeeper-operator
  source: operatorhubio-catalog
```

或在 GKE 上直接使用 helm：

```bash
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --version 3.14.0
```

### 5.3 阿里云 ACK 上的部署

```bash
# ACK 集群连接配置
kubectl config use-context my-aliyun-cluster

helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace
```

### 5.4 GitOps 统一管理

推荐使用 **GitOps** 方式（ArgoCD / Flux）统一管理跨集群策略：

```yaml
# ArgoCD Application 示例
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gatekeeper-policies
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/policy-library.git
    targetRevision: main
    path: constraints/prod
  destination:
    server: https://35.197.xxx.xxx   # GKE cluster
    namespace: gatekeeper-system
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gatekeeper-policies-aliyun
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/myorg/policy-library.git
    targetRevision: main
    path: constraints/prod
  destination:
    server: https://my-aliyun-cluster.cn-hangzhou.alicontainer.com
    namespace: gatekeeper-system
```

---

## 6. 迁移路径（如果已使用 GKE Policy Controller）

### 6.1 从 Policy Controller 迁移到 Standalone Gatekeeper

**步骤 1**：在 GKE 上关闭 Policy Controller

```bash
gcloud container clusters update my-cluster \
  --disable-policy-controller \
  --region=us-central1
```

**步骤 2**：安装 Standalone Gatekeeper（版本 ≥ 当前 Policy Controller 版本）

```bash
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace
```

**步骤 3**：验证 ConstraintTemplate 兼容性

```bash
# 导出现有策略
kubectl get constrainttemplate -A -o yaml > existing-templates.yaml

# 在新环境应用（通常无需修改）
kubectl apply -f existing-templates.yaml
```

### 6.2 导出 GKE Policy Controller 预置策略

GKE Policy Controller 的预置策略源码可从 [GitHub](https://github.com/open-policy-agent/gatekeeper-library) 获取：

```bash
# 克隆策略库
git clone https://github.com/open-policy-agent/gatekeeper-library.git

# 选择性应用需要的策略
kubectl apply -f gatekeeper-library/library/
```

---

## 7. 选型决策矩阵

| 场景 | 推荐 | 理由 |
|------|------|------|
| **仅使用 GKE** | GKE Policy Controller | 原生集成，维护成本低 |
| **多云（GKE + ACK）** | Standalone Gatekeeper | 策略统一，跨平台复用 |
| **强合规要求（金融/政务）** | Standalone Gatekeeper | 版本可控，审计方便 |
| **快速 POC** | GKE Policy Controller | 一键启用，预置策略丰富 |
| **需要最新 Gatekeeper 功能** | Standalone Gatekeeper | 独立迭代更快 |

---

## 8. Rego 编写最佳实践

### 8.1 模板设计原则

1. **参数化**：通过 Constraint 的 `spec.match` 和自定义参数实现灵活配置
2. **版本锁定**：使用 `spec.crd.spec.validation` 明确 API 版本
3. **清晰错误信息**：返回有意义的 `msg`，便于用户理解和修复

### 8.2 跨平台兼容示例

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
  targets:
    - target: admission.k8s.gatekeeper.sh
      lib: lib/helpers.rego   # 辅助函数（需在各集群同步）
      rego: |
        package k8srequiredlabels

        violation{"message": msg} {
          input.review.kind.kind == "Deployment"
          not input.review.object.metadata.labels["app"]
          msg := "Deployment must have 'app' label"
        }
```

### 8.3 避免 GCP 特定写法

```rego
# ❌ 避免：依赖 GCP 特定数据
data.google_storage_bucket.example

# ✅ 推荐：使用 Kubernetes 原生数据
input.review.namespace
input.review.object.metadata.labels
```

---

## 9. 总结与建议

### 9.1 最终建议

| 你的情况 | 建议方案 |
|----------|----------|
| **当前 GKE，未来上阿里云** | Standalone Gatekeeper |
| **需要预置策略快速落地** | GKE Policy Controller 先用，后期迁移 |
| **强多云一致性要求** | Standalone Gatekeeper + GitOps |

### 9.2 下一步行动

1. **确定策略管理方案**：是否采用 GitOps 统一管理
2. **编写核心策略**：基于你的 `GKEResourceWhitelist` 需求
3. **验证跨集群兼容**：在 GKE 和 ACK 环境分别测试
4. **建立审计机制**：定期巡检策略覆盖率和合规率

### 9.3 推荐学习路径

- [ ] 阅读 [Gatekeeper 官方文档](https://open-policy-agent.github.io/gatekeeper/)
- [ ] 参考 [Gatekeeper Library](https://github.com/open-policy-agent/gatekeeper-library) 预置策略
- [ ] 部署第一套 Standalone Gatekeeper 到测试集群
- [ ] 编写并测试你的第一个自定义 Rego 策略