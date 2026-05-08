# GKE Secret Manager 集成深度分析

> **文档版本**: 1.1.0
> **更新日期**: 2026-05-07
> **状态**: 深度技术分析
> **分类**: Internal — Safe to Share
> **官方参考**: `cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component`

---

## §1 功能概述

### 1.1 官方名称：Secret Manager add-on for GKE

GKE Secret Manager add-on 是 Google 官方提供的 GKE 与 Secret Manager 集成方案，核心基于开源 **Kubernetes Secrets Store CSI Driver** + **Google Secret Manager Provider** 构建。

> "The integration between Secret Manager and Google Kubernetes Engine (GKE) lets you store sensitive data such as passwords and certificates used by GKE clusters as secrets in Secret Manager."

**关键机制：** 通过 CSI 卷挂载方式，将 Secret Manager 中的 secret 直接暴露为 Pod 容器文件系统中的文件，应用无需编写任何代码即可读取。

**官方文档路径：**
- `cloud.google.com/secret-manager/docs/secret-manager-managed-csi-component`
- GKE Console → 集群详情 → Security → Secret Manager

### 1.2 与你现有 SMS 平台的关系

| 维度 | 你的 SMS 2.0 平台 | Secret Manager add-on for GKE |
|------|-----------------|------------------------------|
| **架构层次** | 应用层（代码内调用 Secret Manager API） | 基础设施层（CSI Driver 自动挂载） |
| **实现方式** | Init 容器或应用代码调用 SDK | Pod Volume Mount（CSI 类型） |
| **Secret 位置** | 应用自行读取到内存或 /opt/secrets | CSI Driver 写入 Pod 容器文件系统 |
| **Workload Identity** | ✅ 必须（RT GSA 方案） | ✅ 必须（自动使用 Pod 的 WI） |
| **代码改造** | 需要（SDK 调用） | 无需代码改造（YAML 配置即可） |
| **自动旋转** | 需要应用自行实现 | 支持配置自动旋转（Auto-rotation） |

**结论：Secret Manager add-on 是一个补充层，不是替代你的 SMS 平台。两者可共存，但功能有重叠。**

---

## §2 技术架构

### 2.1 CSI Driver 工作原理

```
┌─────────────────────────────────────────────────────────────────────┐
│                          GKE Cluster                                │
│                                                                     │
│  ┌──────────┐    ┌────────────────────────────────┐              │
│  │   Pod    │───▶│  Secrets Store CSI Driver       │              │
│  │          │    │  Driver: secrets-store-gke.csi.k8s.io          │
│  │          │◀───│  (GKE Managed DaemonSet)       │              │
│  └──────────┘    └────────────────────────────────┘              │
│       │                        │                                   │
│       │ volume mount          │ Workload Identity (WI)            │
│       ▼                        ▼                                   │
│  /var/secrets/           K8s SA (via WI)                         │
│  (容器文件系统)                  │                                   │
│                           ┌────┴─────────────────────┐            │
│                           │  IAM: secretAccessor    │            │
│                           │  principal://iam.googleapis.com/...    │            │
│                           └────────────────────────────┘            │
│                                          │                         │
│                                          ▼                         │
│                               ┌──────────────────┐                 │
│                               │ Secret Manager   │                 │
│                               │ (GCP)            │                 │
│                               └──────────────────┘                 │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 关键组件说明

| 组件 | 名称 | 说明 |
|------|------|------|
| **CSI Driver** | `secrets-store-gke.csi.k8s.io` | GKE 托管的 DaemonSet，在每个节点运行 |
| **Provider** | `gke` | Secret Manager add-on 专用 provider（不是开源的 `gcpsm`） |
| **CRD** | `SecretProviderClass` | 定义要挂载哪些 secret 及挂载路径 |
| **Volume** | CSI 类型 | Pod 中声明的卷，引用 SecretProviderClass |

**重要修正：**
- Driver 名称是 `secrets-store-gke.csi.k8s.io`（不是开源的 `secretstore.csi.k8s.io`）
- Provider 是 `gke`（不是开源 CSI Driver 的 `gcpsm`）
- 这是 GKE **完全托管**的 add-on，不是用户手动安装的 CSI Driver

### 2.3 Pod 配置示例

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  namespace: my-namespace
spec:
  serviceAccountName: my-app-ksa  # 必须与 WI 绑定的 KSA
  containers:
  - image: my-app:latest
    name: app
    volumeMounts:
    - mountPath: "/var/secrets"   # secret 挂载到此路径
      name: mysecret
      readOnly: true
  volumes:
  - name: mysecret
    csi:
      driver: secrets-store-gke.csi.k8s.io   # GKE 托管 driver
      readOnly: true
      volumeAttributes:
        secretProviderClass: "my-secret-class"  # 对应 SecretProviderClass
  # Standard 集群需要，Autopilot 不需要（自动支持）
  nodeSelector:
    iam.gke.io/gke-metadata-server-enabled: "true"
```

### 2.4 SecretProviderClass 配置

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: my-secret-class
spec:
  provider: gke              # GKE 托管 provider（不是 gcpsm）
  parameters:
    secrets: |
      - resourceName: "projects/PROJECT_ID/secrets/my-secret/versions/latest"
        path: "db-password.txt"   # 挂载后的文件名
      - resourceName: "projects/PROJECT_ID/secrets/my-api-key/versions/1"
        path: "api-key.txt"
```

**注意：** 参数名是 `path`（不是开源 CSI Driver 的 `fileName`）。

### 2.5 自动旋转（Auto-rotation）

这是 Secret Manager add-on 的重要特性：

> "Auto-rotation of mounted secrets lets applications automatically receive updated secrets without requiring a restart or manual intervention."

| 特性 | 说明 |
|------|------|
| **触发方式** | 定时轮询 Secret Manager，检测到新版本自动同步 |
| **配置参数** | `secret-manager-rotation-interval` + `enable-secret-manager-rotation` |
| **最低版本** | GKE 1.32.2-gke.1059000 或更高 |
| **优势** | Secret 轮换时 Pod 无需重启即可获得新值 |

---

## §3 前置条件

| 要求 | 说明 |
|------|------|
| **GKE 版本** | ≥ 1.27.14-gke.1042001 |
| **节点镜像** | Container-Optimized OS 或 Ubuntu |
| **Windows 节点** | ❌ 不支持 |
| **Secret Manager API** | 必须启用 |
| **GKE API** | 必须启用 |
| **Workload Identity** | Standard 集群必须启用；Autopilot 默认已启用 |
| **操作系统** | 仅支持 Linux 节点 |

### 3.1 验证 Add-on 安装状态

```bash
gcloud container clusters describe CLUSTER_NAME \
  --location LOCATION | grep secretManagerConfig -A 4
```

输出示例（已启用）：
```yaml
secretManagerConfig:
  enabled: true
```

---

## §4 安全评估矩阵

### 4.1 启用（Enable）的安全优势

| 优势 | 说明 | 风险缓解等级 |
|------|------|------------|
| **集中审计** | Secret Manager 记录所有 API 访问日志（Cloud Logging） | 🟢 高 |
| **IAM 统一授权** | 通过 Workload Identity + IAM roles/secretmanager.secretAccessor 控制访问 | 🟢 高 |
| **无 K8s Secret 泄露** | 不需要在 etcd 中存储 Kubernetes Secret | 🟢 高 |
| **版本管理** | Secret Manager 原生支持版本轮换 + Auto-rotation | 🟡 中 |
| **CMEK 加密** | 可使用客户管理的密钥加密 Secret Manager | 🟢 高 |
| **最小权限** | Pod 只挂载其需要的 specific secret（非全量获取） | 🟡 中 |
| **无需代码改造** | YAML 配置即可，遗留应用可直接使用 | 🟡 中 |

### 4.2 启用（Enable）的安全风险

| 风险 | 说明 | 风险等级 |
|------|------|---------|
| **节点文件系统** | Secret 以文件形式存在于容器文件系统，同节点其他 Pod 理论上可访问（容器隔离边界） | 🔴 高 |
| **CSI Driver 攻击面** | CSI Driver DaemonSet 需要特权访问 | 🔴 高 |
| **Pod 范围共享** | 同一 SecretProviderClass 的 Pod 都可访问相同 secret | 🟡 中 |
| **旋转延迟** | Auto-rotation 有间隔期，非实时同步 | 🟡 中 |
| **运维复杂性** | 两套 secret 管理方式增加维护和审计成本 | 🟡 中 |

### 4.3 禁用（Disable）的安全优势

| 优势 | 说明 |
|------|------|
| **强制应用层获取** | 应用必须通过代码调用 Secret Manager API，无法直接挂载文件 |
| **审计粒度更细** | 每次 secret 访问都是独立的 API 调用，日志记录完整 |
| **无节点文件泄露** | Secret 不会以文件形式存在于任何节点上 |
| **现有 SMS 体系完整** | 你的 SMS 2.0 平台已完整实现应用层 secret 管理 |

### 4.4 禁用（Disable）的代价

| 代价 | 说明 |
|------|------|
| **无法使用 CSI 卷挂载** | 不使用 CSI 方式挂载 secret |
| **遗留应用改造** | 旧有应用需要代码改造才能使用 Secret Manager API |

---

## §5 与你现有 SMS 平台的对比

### 5.1 你的 SMS 2.0 架构（应用层获取）

```
Pod 启动 → Init Container / Application Code
         → 调用 Secret Manager API (Workload Identity)
         → 获取 secret → 应用使用（内存或 /opt/secrets）
```

**安全特点：**
- Secret 只存在于应用内存中（可选择写入 /opt/secrets）
- 每一次 access 都是独立的 API 调用，完全审计
- 应用自行决定何时读取、缓存策略
- 需要代码改造（SDK 调用）

### 5.2 Secret Manager add-on（基础设施层挂载）

```
Pod 启动 → CSI Driver 拦截
         → 通过 Pod Workload Identity 调用 Secret Manager API
         → 将 secret 写入 /var/secrets/<path>
         → 应用以文件形式读取
```

**安全特点：**
- Secret 以文件存在于容器文件系统
- Pod 重启前通过 Auto-rotation 可自动获取新版本
- 审计日志在 Secret Manager API 层面
- YAML 配置即可，无需代码改动
- Auto-rotation 支持，无需 Pod 重启

### 5.3 Auto-rotation 对比

| 维度 | SMS 2.0（应用层） | Secret Manager add-on |
|------|-----------------|---------------------|
| **轮换触发** | 应用自行检测版本并重新读取 | CSI Driver 定时轮询并同步 |
| **Pod 无感轮换** | 需要应用自行实现 | ✅ 支持（需配置） |
| **最低版本要求** | 无 | GKE 1.32.2+ |

---

## §6 IAM 授权详解

### 6.1 Workload Identity 绑定方式（官方）

Secret Manager add-on 使用 **principal 格式**的 IAM member 标识，与传统 WI 绑定方式不同：

```bash
# 正确的 principal 格式（GKE 官方推荐）
gcloud secrets add-iam-policy-binding SECRET_NAME \
    --role=roles/secretmanager.secretAccessor \
    --member=principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/KSA_NAME
```

**参数说明：**
- `PROJECT_NUMBER`：Google Cloud 项目的数字 ID（不是项目 ID）
- `PROJECT_ID`：项目 ID（如 `my-gcp-project`）
- `NAMESPACE`：Kubernetes 命名空间
- `KSA_NAME`：Kubernetes ServiceAccount 名称

### 6.2 获取项目数字 ID

```bash
gcloud projects describe PROJECT_ID --format="value(projectNumber)"
```

### 6.3 验证 WI 绑定

```bash
# 验证 KSA annotation
kubectl get sa KSA_NAME -n NAMESPACE -o yaml | grep iam.gke.io

# 测试是否能访问 Secret Manager
kubectl run -it --rm test-secret \
  --image=google/cloud-sdk:slim \
  --serviceaccount=KSA_NAME \
  -n NAMESPACE \
  -- gcloud secrets list
```

---

## §7 安全建议

### 7.1 建议：保持禁用（Disable）

基于以下原因，**建议保持 Disable**：

1. **你的 SMS 2.0 体系已完整覆盖安全需求**
   - Workload Identity ✅
   - 集中审计（Cloud Logging）✅
   - 细粒度 IAM 授权（per-RT GSA）✅
   - 应用层 secret 管理 ✅
   - 手动版本轮换控制 ✅

2. **CSI 卷挂载的安全风险高于你的当前方案**
   - Secret 文件在容器文件系统中（即使在容器内，也比纯内存访问风险更高）
   - CSI Driver 攻击面
   - Pod 范围共享同一 secret

3. **运维复杂性增加**
   - 两套 secret 获取方式需要两套维护流程
   - 审计和排查复杂度翻倍
   - 需要额外管理 SecretProviderClass CRD

4. **Secret Manager add-on 的最佳适用场景**
   - 快速迁移无代码改造的遗留应用（Java/Python 等老程序）
   - 临时/测试环境
   - 非敏感但需要集中管理的配置（如 API endpoints、feature flags）
   - 有大量微服务需要统一 secret 管理且难以逐一改造的场景

### 7.2 如果决定启用

```bash
# 1. 验证 GKE 版本（需 >= 1.27.14-gke.1042001）
gcloud container clusters describe CLUSTER_NAME \
  --location LOCATION --format="value(currentMasterVersion)"

# 2. 确保 Workload Identity 已启用
gcloud container clusters describe CLUSTER_NAME \
  --location LOCATION --format="value(workloadIdentityConfig.workloadPool)"

# 3. 启用 Secret Manager add-on（通过 Console）
# GKE Console → Cluster → Security → Secret Manager → Enable

# 4. 为 KSA 绑定 IAM 权限（使用 principal 格式）
gcloud secrets add-iam-policy-binding my-secret \
    --role=roles/secretmanager.secretAccessor \
    --member=principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/KSA_NAME

# 5. 验证 add-on 安装状态
gcloud container clusters describe CLUSTER_NAME \
  --location LOCATION | grep secretManagerConfig -A 4
```

### 7.3 强制要求（无论启用还是禁用）

| 要求 | 说明 |
|------|------|
| **Workload Identity 必须启用** | 禁止使用 Service Account Key 文件 |
| **最小权限原则** | 只授予 `roles/secretmanager.secretAccessor`，不授予 admin |
| **Secret Manager audit logging** | 确保所有 secret 访问都有 Cloud Logging 记录 |
| **NetworkPolicy** | 限制 Pod 出站流量，只允许必要端点 |
| **Pod Security Standards** | 使用 `baseline` 或 `restricted` PSS |

---

## §8 GKE Console 配置路径

```
GKE Console → Clusters → 选择集群 → Security
                                    ↓
                          Secret Manager: [Disable ▼]
                          ☑️ Enable Secret Manager
                          ☐ Configure auto-rotation (可选)
```

**关于 Auto-rotation 配置：**
- Rotation interval：旋转间隔（如 1）
- Rotation interval unit：单位（minutes / hours / days）
- 需 GKE ≥ 1.32.2

---

## §9 总结

| 评估项 | 结论 |
|--------|------|
| **官方名称** | Secret Manager add-on for GKE |
| **CSI Driver** | `secrets-store-gke.csi.k8s.io`（GKE 托管） |
| **Provider** | `gke` |
| **最低 GKE 版本** | 1.27.14-gke.1042001 |
| **Auto-rotation 版本** | ≥ 1.32.2-gke.1059000 |
| **与现有 SMS 关系** | 可共存，非替代关系 |
| **建议** | **Disable**（保持现有 SMS 2.0 体系） |
| **核心原因** | CSI 卷挂载安全风险高于应用层 API 获取，且你的 SMS 2.0 已完整覆盖需求 |
| **最佳启用场景** | 大规模遗留应用迁移，无法逐个改造代码的场景 |

**一句话结论：** 你的 SMS 2.0 体系通过应用层 API 调用已完整、安全地解决了 Secret Manager 访问问题。Secret Manager add-on 的 Auto-rotation 是亮点，但 CSI 卷挂载引入的节点文件系统风险和运维复杂性使其对你目前的需求而言弊大于利。**建议保持禁用。**
