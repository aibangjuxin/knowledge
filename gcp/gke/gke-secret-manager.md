# GKE Secret Manager 集成深度分析

## §1 功能概述

### 1.1 什么是 GKE Secret Manager 集成

GKE Secret Manager 集成是 GKE 集群级别的一个安全功能（通过 Security 页面配置），允许将 GCP Secret Manager 中存储的 secret 以 **CSI (Container Storage Interface) 卷** 的形式挂载到 Pod 内部。

> "Secret Manager allows you to access the secret stored in Secret Manager as volumes mounted in Kubernetes pods"

**官方文档路径（截至本文撰写时）：**
- `cloud.google.com/kubernetes-engine/docs/how-to/integrate-secret-manager`
- GKE Console → 集群详情 → Security → Secret Manager

### 1.2 与你现有 SMS 平台的关系

| 维度 | 你的 SMS 2.0 平台 | GKE Secret Manager CSI |
|------|-----------------|----------------------|
| **架构层次** | 应用层（代码内调用 Secret Manager API） | 基础设施层（CSI Driver 自动挂载） |
| **实现方式** | Init 容器或应用代码调用 SDK | Pod Volume Mount（csi 类型） |
| **Secret 位置** | 应用自行读取到内存或 /opt/secrets | CSI Driver 写入 Pod 文件系统 |
| **Workload Identity** | ✅ 必须（你的 RT GSA 方案） | ✅ 必须 |
| **迁移复杂度** | 已有完整体系 | 可共存，非替代关系 |

**结论：GKE Secret Manager CSI 是一个补充层，不是替代你的 SMS 平台。**

---

## §2 技术架构

### 2.1 CSI Driver 工作原理

```
┌─────────────────────────────────────────────────────────────┐
│                        GKE Cluster                          │
│                                                             │
│  ┌──────────┐    ┌──────────────────┐    ┌──────────────┐  │
│  │   Pod    │───▶│  CSI Secret Store │───▶│ Secret       │  │
│  │          │    │  Driver (DaemonSet)│    │ Manager API  │  │
│  └──────────┘    └──────────────────┘    └──────────────┘  │
│       │                  │                                    │
│       │ volume mount     │ Workload Identity                  │
│       ▼                  ▼                                    │
│  /etc/secrets/      K8s SA ──annotation──▶ GCP SA            │
│  (tmpfs on node)                                   │         │
│                                                   ▼         │
│                                          IAM: secretAccessor│
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Pod 配置示例

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  serviceAccountName: my-app-ksa  # 必须是 Workload Identity 已绑定的 KSA
  containers:
  - name: app
    image: my-app:latest
    volumeMounts:
    - name: db-password
      mountPath: /etc/secrets
      readOnly: true
  volumes:
  - name: db-password
    csi:
      driver: secretstore.csi.k8s.io          # 必须为 secretstore.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: "sm-secret-class" # 对应 SecretProviderClass
```

### 2.3 SecretProviderClass 配置

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: sm-secret-class
spec:
  provider: gcpsm          # Google Cloud Secret Manager provider
  parameters:
    secrets: |
      - resourceName: "projects/PROJECT_ID/secrets/my-secret/versions/latest"
        fileName: "db-password"   # 挂载后的文件名
```

---

## §3 安全评估矩阵

### 3.1 启用（Enable）的安全优势

| 优势 | 说明 | 风险缓解等级 |
|------|------|------------|
| **集中审计** | Secret Manager 记录所有 API 访问日志（Cloud Logging） | 🟢 高 |
| **IAM 统一授权** | 通过 Workload Identity + IAM roles/secretmanager.secretAccessor 控制访问 | 🟢 高 |
| **无 K8s Secret 泄露风险** | 不需要在 etcd 中存储 Kubernetes Secret | 🟢 高 |
| **版本管理** | Secret Manager 原生支持版本轮换 | 🟡 中 |
| **自动同步** | CSI Driver 自动将 Secret Manager 中的 secret 同步到 Pod | 🟡 中 |
| **最小权限落地** | Pod 只挂载它需要的 specific secret，非全量获取 | 🟡 中 |

### 3.2 启用（Enable）的安全风险

| 风险 | 说明 | 风险等级 |
|------|------|---------|
| **Node 文件系统持久化** | Secret 以文件形式存在于节点 tmpfs 中，同节点其他 Pod 可能访问（节点隔离依赖 GKE 节点安全） | 🔴 高 |
| **CSI Driver 攻击面** | CSI Driver DaemonSet 以特权容器运行在每个节点上 | 🔴 高 |
| **Pod 范围扩大** | 持有正确 ServiceAccount 的 Pod 都可以访问同一个 Secret（无法细粒度到 Pod 级别） | 🟡 中 |
| **旋转延迟** | Secret Manager 中的轮换不会立即反映到已挂载的 Pod（依赖 sync interval） | 🟡 中 |
| **密钥管理复杂性** | 两套密钥管理体系（SMS 平台 + CSI）增加运维和审计难度 | 🟡 中 |
| **节点被攻陷** | 如果节点被攻陷，tmpfs 中的 secret 文件可被读取 | 🔴 高 |

### 3.3 禁用（Disable）的安全优势

| 优势 | 说明 |
|------|------|
| **强制应用层获取** | 应用必须通过代码调用 Secret Manager API，无法直接挂载文件 |
| **审计粒度更细** | 每次 secret 访问都是一次 API 调用，日志记录完整 |
| **无节点文件系统泄露** | Secret 不会以文件形式存在于任何节点上 |
| **现有 SMS 体系完整** | 你的 SMS 2.0 平台已完整实现应用层 secret 管理 |

### 3.4 禁用（Disable）的安全代价

| 代价 | 说明 |
|------|------|
| **无法使用 CSI 卷挂载** | 不使用 CSI 方式挂载 secret |
| **功能限制** | 如果未来有 Pod 需要 CSI 卷方式访问 Secret Manager，则不可用 |

---

## §4 与你现有 SMS 平台的对比

### 4.1 你的 SMS 2.0 架构（应用层获取）

```
Pod 启动 → Init Container / Application Code
         → 调用 Secret Manager API (Workload Identity)
         → 获取 secret → 应用使用
```

**安全特点：**
- Secret 只存在于应用内存中（可选择写入 /opt/secrets）
- 每一次 access 都是独立的 API 调用，完全审计
- 应用自行决定何时读取、缓存策略
- 需要代码改造（SDK 调用）

### 4.2 GKE Secret Manager CSI（基础设施层挂载）

```
Pod 启动 → CSI Driver 拦截
         → 通过 Workload Identity 调用 Secret Manager API
         → 将 secret 写入 /etc/secrets/<fileName>
         → Pod 以文件形式读取
```

**安全特点：**
- Secret 以文件存在于节点 tmpfs
- Pod 重启前不会自动获取新版本 secret
- 审计日志在 Secret Manager API 层面
- YAML 配置即可，无需代码改动

### 4.3 共存方案

```
┌────────────────────────────────────────────────────┐
│                  GKE Cluster                       │
│                                                     │
│  Pod A (传统应用)                                   │
│  └── 使用你的 SMS 2.0 → 应用层获取 secret            │
│                                                     │
│  Pod B (新迁移应用)                                  │
│  └── 使用 GKE Secret Manager CSI → 卷挂载 secret     │
│                                                     │
│  两者共用同一个 RT GSA + Workload Identity         │
│  IAM 层面统一授权                                    │
└────────────────────────────────────────────────────┘
```

---

## §5 安全建议

### 5.1 建议：保持禁用（Disable）

基于以下原因，**建议保持 Disable**：

1. **你的 SMS 2.0 体系已完整覆盖安全需求**
   - Workload Identity ✅
   - 集中审计（Cloud Logging）✅
   - 细粒度 IAM 授权（per-RT GSA）✅
   - 应用层 secret 管理 ✅

2. **CSI 卷挂载的安全风险高于你的当前方案**
   - Secret 文件在节点 tmpfs 中
   - CSI Driver 攻击面
   - Pod 级别无法进一步细分权限

3. **运维复杂性增加**
   - 两套 secret 获取方式需要两套维护流程
   - 审计和排查复杂度翻倍
   - 需要额外管理 SecretProviderClass CRD

4. **GKE Secret Manager CSI 的适用场景**
   - 快速迁移无代码改造的遗留应用
   - 临时/测试环境
   - 非敏感配置的简化管理

### 5.2 如果决定启用

如果经过评估后决定启用，请确保：

```bash
# 1. 启用前：确保 Workload Identity 已正确配置
gcloud container clusters describe CLUSTER_NAME \
  --format="value(workloadIdentityConfig.workloadPool)"

# 2. 启用 GKE Secret Manager Addon（通过 Console 或 gcloud）
# 注意：启用后不可逆，需要谨慎评估

# 3. 为每个需要访问的 RT GSA 授予最小权限
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:my-rt-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# 4. 创建 SecretProviderClass（只授予必要的 secret）
# 5. 启用审计日志
gcloud logging write secrets-access-log "Secret accessed" \
  --severity=INFO \
  --log-name=secret-manager-access
```

### 5.3 强制要求（无论启用还是禁用）

| 要求 | 说明 |
|------|------|
| **Workload Identity 必须启用** | 禁止使用 Service Account Key 文件 |
| **RT GSA 最小权限原则** | 只授予 `roles/secretmanager.secretAccessor`，不授予 admin |
| **Secret Manager audit logging** | 确保所有 secret 访问都有 Cloud Logging 记录 |
| **NetworkPolicy** | 限制 Pod 出站流量，只允许必要端点 |
| **Pod Security Standards** | 使用 `baseline` 或 `restricted` PSS |

---

## §6 GKE Console 配置路径

```
GKE Console → Clusters → 选择集群 → Security
                                    ↓
                          Secret Manager: [Disable ▼]
```

**配置位置截图示意：**
- 路径：`Container Kubernetes Engine → Clusters → <cluster-name> → Security`
- 选项：`Secret Manager` → `Disable` / `Enable`

**注意：** 启用后集群将安装 `Secret Store CSI Driver` DaemonSet 到所有节点。

---

## §7 总结

| 评估项 | 结论 |
|--------|------|
| **功能定位** | CSI 卷挂载方式的 Secret Manager 集成，非替代 SMS 平台 |
| **与现有 SMS 关系** | 可共存，但功能重叠 |
| **建议** | **Disable**（保持现有 SMS 2.0 体系） |
| **启用条件** | 有大量遗留应用需要快速迁移且可接受节点文件存储风险 |
| **核心风险** | Secret 文件存在于节点 tmpfs，CSI Driver 攻击面 |

**一句话结论：** 你的 SMS 2.0 体系已经通过应用层 API 调用的方式完整、安全地解决了 Secret Manager 访问问题。GKE Secret Manager CSI 是一个补充选项，但会带来额外的安全攻击面和运维复杂性。**建议保持禁用。**
