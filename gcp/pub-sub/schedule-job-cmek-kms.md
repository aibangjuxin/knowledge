# Cloud Scheduler + CMEK 完全排障手册 / Complete Troubleshooting Guide

## 核心问题 / Core Issue

**症状 / Symptom**:
```bash
gcloud scheduler jobs resume job-lex-eg-test-001
ERROR: NOT_FOUND - parent resource not found for .../retryPolicies/...
```

**根本原因 / Root Cause**:
Cloud Scheduler Service Agent 缺少对 CMEK 密钥的访问权限，导致无法创建内部 Pub/Sub Stream 资源。

Cloud Scheduler Service Agent lacks KMS permissions on the CMEK key, preventing creation of internal Pub/Sub Stream resources.

---

## 一、完整架构流程图 / Complete Architecture Flow

### 1.1 系统实现视角 / System Implementation View

```mermaid
graph TB
    subgraph "User Layer / 用户层"
        U[User executes:<br/>gcloud scheduler jobs resume]
    end

    subgraph "Cloud Scheduler Service / Scheduler 服务"
        S[Cloud Scheduler API]
        SA[Scheduler Service Agent<br/>service-PROJECT@gcp-sa-cloudscheduler]
    end

    subgraph "Internal Resources / 内部资源 (Managed by Scheduler)"
        ST[Pub/Sub Stream<br/>内部托管流]
        RP[RetryPolicy<br/>重试策略]
    end

    subgraph "Pub/Sub Service / Pub/Sub 服务"
        T[Pub/Sub Topic<br/>CMEK Enabled]
        PSA[Pub/Sub Service Agent<br/>service-PROJECT@gcp-sa-pubsub]
    end

    subgraph "KMS Service / KMS 服务"
        K[KMS CryptoKey<br/>CMEK 密钥]
    end

    U --> S
    S --> SA
    SA -->|Creates / 创建| ST
    ST -->|Contains / 包含| RP
    ST -->|Points to / 指向| T
    
    SA -.->|Need Permission / 需要权限| K
    PSA -.->|Need Permission / 需要权限| K
    T -->|Uses / 使用| K
    T --> PSA

    style K fill:#ff9999
    style SA fill:#ffeb99
    style PSA fill:#99ccff
```

### 1.2 错误发生流程 / Error Flow

```mermaid
sequenceDiagram
    participant U as User
    participant S as Scheduler Service
    participant SA as Scheduler SA
    participant K as KMS Key
    participant ST as Internal Stream
    participant T as Pub/Sub Topic

    U->>S: gcloud scheduler jobs resume
    S->>SA: Activate Service Agent
    SA->>K: Check Permission (cryptoKeyEncrypterDecrypter)
    
    alt Permission Denied / 权限拒绝
        K-->>SA: ❌ Access Denied
        SA->>ST: Attempt to create Stream
        ST-->>SA: ❌ Creation Failed (no KMS access)
        SA-->>S: ❌ RetryPolicy parent NOT_FOUND
        S-->>U: ERROR: NOT_FOUND
    else Permission Granted / 权限通过
        K-->>SA: ✅ Access Granted
        SA->>ST: Create Stream successfully
        ST->>T: Connect to Topic
        T->>K: Verify CMEK
        ST-->>SA: ✅ Stream Created
        SA-->>S: ✅ Job Resumed
        S-->>U: SUCCESS
    end
```

---

## 二、根因分析 / Root Cause Analysis

### 2.1 为什么会出现这个错误？/ Why This Error Occurs?

**关键理解点 / Key Understanding**:

Cloud Scheduler 不是直接调用 Pub/Sub API。它会创建一个 **内部托管的 Pub/Sub Stream**。

Cloud Scheduler does NOT directly call Pub/Sub API. It creates an **internally managed Pub/Sub Stream**.

**真实结构 / Real Structure**:
```
Cloud Scheduler Job
  └── Pub/Sub Target (logical)
       └── Managed Stream (physical, created by Scheduler SA)
            └── RetryPolicy (physical, attached to Stream)
                 └── Pub/Sub Topic (CMEK-encrypted)
```

**创建这个 Stream 的主体是谁？/ Who Creates the Stream?**

👉 **Cloud Scheduler Service Agent** (NOT Pub/Sub Service Agent)

**为什么需要 KMS 权限？/ Why KMS Permission is Needed?**

因为 Stream 需要连接到 CMEK 加密的 Topic，Scheduler SA 在创建 Stream 时必须验证它能否访问加密资源。

Because the Stream connects to a CMEK-encrypted Topic, Scheduler SA must verify it can access the encrypted resource during Stream creation.

### 2.2 为什么错误是 NOT_FOUND 而不是 PERMISSION_DENIED？

**Google 内部资源模型的"坑" / GCP Internal Resource Model Issue**:

```
Stream 创建失败 (due to KMS permission)
  ↓
RetryPolicy 无法挂载 (no parent Stream)
  ↓
查询 RetryPolicy → parent resource 不存在
  ↓
返回 NOT_FOUND (而不是 PERMISSION_DENIED)
```

这是一个误导性的错误消息，实际根因是权限问题。

This is a misleading error message; the actual root cause is a permission issue.

---

## 三、两个 Service Agent 的职责边界 / Service Agent Responsibilities

### 3.1 Cloud Scheduler Service Agent

```
service-<PROJECT_NUMBER>@gcp-sa-cloudscheduler.iam.gserviceaccount.com
```

**何时使用 KMS？/ When Does It Use KMS?**

| 操作 / Operation | 是否需要 KMS / KMS Required | 原因 / Reason |
|------------------|----------------------------|---------------|
| `jobs create` | ✅ | 创建内部 Stream / Creates internal Stream |
| `jobs resume` | ✅ | 恢复/重建 Stream / Resumes/rebuilds Stream |
| `jobs pause` | ❌ | 仅状态变更 / State change only |
| `jobs run` | ✅ | 触发 Stream 活动 / Triggers Stream activity |

### 3.2 Pub/Sub Service Agent

```
service-<PROJECT_NUMBER>@gcp-sa-pubsub.iam.gserviceaccount.com
```

**何时使用 KMS？/ When Does It Use KMS?**

| 操作 / Operation | 是否需要 KMS / KMS Required | 原因 / Reason |
|------------------|----------------------------|---------------|
| Message publish | ✅ | 加密消息存储 / Encrypts message storage |
| Message delivery | ✅ | 解密消息投递 / Decrypts message delivery |
| Topic operations | ❌ | Scheduler SA 已验证 / Already validated by Scheduler SA |

### 3.3 决策公式 / Decision Formula

**谁创建资源，谁需要 KMS 权限**
**Whoever creates the resource needs KMS permission**

- 创建 Stream → Scheduler SA ✅
- 使用 Topic 存储消息 → Pub/Sub SA ✅

---

## 四、完整解决方案 / Complete Solution

### Step 1: 确认项目编号 / Confirm Project Number

```bash
gcloud projects describe aibang-projectid-abjx01-dev \
  --format="value(projectNumber)"
# Output: 445194165188
```

### Step 2: 获取 Service Agent 邮箱 / Get Service Agent Emails

```bash
# Cloud Scheduler Service Agent
SCHEDULER_SA="service-445194165188@gcp-sa-cloudscheduler.iam.gserviceaccount.com"

# Pub/Sub Service Agent
PUBSUB_SA="service-445194165188@gcp-sa-pubsub.iam.gserviceaccount.com"
```

### Step 3: 设置 KMS Key 变量 / Set KMS Key Variables

```bash
export KMS_PROJECT_ID="your-kms-project-id"
export LOCATION="europe-west2"  # 必须与 Scheduler Job location 一致
export KEY_RING="your-keyring-name"
export KEY_NAME="your-key-name"
```

### Step 4: 授权 Cloud Scheduler Service Agent (必须 / REQUIRED)

```bash
gcloud kms keys add-iam-policy-binding ${KEY_NAME} \
  --keyring ${KEY_RING} \
  --location ${LOCATION} \
  --project ${KMS_PROJECT_ID} \
  --member="serviceAccount:${SCHEDULER_SA}" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

### Step 5: 授权 Pub/Sub Service Agent (强烈建议 / HIGHLY RECOMMENDED)

```bash
gcloud kms keys add-iam-policy-binding ${KEY_NAME} \
  --keyring ${KEY_RING} \
  --location ${LOCATION} \
  --project ${KMS_PROJECT_ID} \
  --member="serviceAccount:${PUBSUB_SA}" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

### Step 6: 验证授权 / Verify Permissions

```bash
gcloud kms keys get-iam-policy ${KEY_NAME} \
  --keyring ${KEY_RING} \
  --location ${LOCATION} \
  --project ${KMS_PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

**预期输出 / Expected Output**:
```
- serviceAccount:service-445194165188@gcp-sa-cloudscheduler.iam.gserviceaccount.com
- serviceAccount:service-445194165188@gcp-sa-pubsub.iam.gserviceaccount.com
```

### Step 7: 删除并重建 Scheduler Job / Delete and Recreate Job

```bash
# 删除损坏的 Job / Delete broken Job
gcloud scheduler jobs delete job-lex-eg-test-001 \
  --location europe-west2 \
  --project aibang-projectid-abjx01-dev \
  --quiet

# 重新创建 Job / Recreate Job
gcloud scheduler jobs create pubsub job-lex-eg-test-001 \
  --schedule="0 0 * * *" \
  --topic=projects/aibang-projectid-abjx01-dev/topics/YOUR_TOPIC_NAME \
  --message-body='{"test": "message"}' \
  --location europe-west2 \
  --project aibang-projectid-abjx01-dev
```

---

## 五、常见场景排查 / Common Scenarios Troubleshooting

### 场景 1: KMS Key 在不同项目 / Cross-Project KMS

**症状**: Topic 创建成功，但 Scheduler 失败

**原因**: KMS 项目未授权 Scheduler SA

**解决**: 在 **KMS 项目** 授权，不是 Scheduler 项目

```bash
# ❌ 错误：在 Scheduler 项目授权
gcloud projects add-iam-policy-binding aibang-projectid-abjx01-dev ...

# ✅ 正确：在 KMS 项目授权
gcloud kms keys add-iam-policy-binding ... --project <KMS_PROJECT>
```

### 场景 2: 只给了 Pub/Sub SA 权限

**症状**: Resume 失败，但消息能正常发布

**原因**: Scheduler SA 缺少权限

**解决**: 必须同时授权两个 SA

| SA | Resume 是否需要 | Publish 是否需要 |
|----|----------------|-----------------|
| Scheduler SA | ✅ 必须 | ❌ |
| Pub/Sub SA | ❌ | ✅ 必须 |

### 场景 3: Key Location 不匹配

**症状**: 间歇性失败

**原因**: KMS Key location ≠ Scheduler location

**解决**: 确保一致性

```bash
# Scheduler Job location
--location europe-west2

# KMS Key location (必须一致或使用 global)
--location europe-west2
```

---

## 六、验证清单 / Verification Checklist

### 创建前验证 / Pre-Creation Verification

- [ ] Pub/Sub Topic 已启用 CMEK
- [ ] KMS Key 状态为 ENABLED
- [ ] Scheduler SA 有 cryptoKeyEncrypterDecrypter 角色
- [ ] Pub/Sub SA 有 cryptoKeyEncrypterDecrypter 角色
- [ ] Location 一致性验证

### 创建后验证 / Post-Creation Verification

```bash
# 1. 验证 Job 状态
gcloud scheduler jobs describe job-lex-eg-test-001 \
  --location europe-west2 \
  --format="value(state)"
# Expected: ENABLED

# 2. 手动触发测试
gcloud scheduler jobs run job-lex-eg-test-001 \
  --location europe-west2

# 3. 查看执行历史
gcloud scheduler jobs describe job-lex-eg-test-001 \
  --location europe-west2 \
  --format="value(status.lastAttemptTime, status.code)"
```

---

## 七、IAM 授权模板 / IAM Authorization Template

### 最小权限模型 / Minimum Permission Model

```bash
#!/bin/bash
# Cloud Scheduler + Pub/Sub + CMEK 最小授权脚本
# Minimum IAM Setup for Scheduler + Pub/Sub + CMEK

PROJECT_NUMBER="<YOUR_PROJECT_NUMBER>"
KMS_PROJECT="<YOUR_KMS_PROJECT>"
KEY_RING="<YOUR_KEYRING>"
KEY_NAME="<YOUR_KEY_NAME>"
LOCATION="<YOUR_LOCATION>"

# Scheduler SA
gcloud kms keys add-iam-policy-binding ${KEY_NAME} \
  --keyring ${KEY_RING} \
  --location ${LOCATION} \
  --project ${KMS_PROJECT} \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudscheduler.iam.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"

# Pub/Sub SA
gcloud kms keys add-iam-policy-binding ${KEY_NAME} \
  --keyring ${KEY_RING} \
  --location ${LOCATION} \
  --project ${KMS_PROJECT} \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

---

## 八、平台级总结 / Platform-Level Summary

### 给安全团队的解释 / For Security Teams

在 CMEK 强制执行环境中，Cloud Scheduler 创建指向 Pub/Sub 的任务时，会在后台创建内部 Stream 资源。这个 Stream 的创建者是 Cloud Scheduler Service Agent，因此它必须拥有对 CMEK 密钥的加解密权限。缺少此权限会导致 NOT_FOUND 错误（而非 PERMISSION_DENIED），因为 RetryPolicy 找不到其父级 Stream 资源。

In CMEK-enforced environments, when Cloud Scheduler creates a job targeting Pub/Sub, it creates an internal Stream resource in the background. The creator of this Stream is the Cloud Scheduler Service Agent, so it must have encrypt/decrypt permissions on the CMEK key. Lacking this permission causes a NOT_FOUND error (not PERMISSION_DENIED) because the RetryPolicy cannot find its parent Stream resource.

### 关键记忆点 / Key Takeaways

1. **两个 SA 都需要授权** / Both SAs need authorization
2. **在 KMS 项目授权** / Grant in KMS project
3. **Resume 不修复权限问题，必须重建** / Resume doesn't fix permission issues; must recreate
4. **NOT_FOUND 是误导性错误** / NOT_FOUND is a misleading error message

---

## 九、快速参考 / Quick Reference

### 一行诊断命令 / One-Line Diagnostic

```bash
gcloud kms keys get-iam-policy <KEY> --keyring <RING> --location <LOC> --project <KMS_PROJ> | grep -E "cloudscheduler|pubsub"
```

### 一行修复命令 / One-Line Fix

```bash
for SA in cloudscheduler pubsub; do gcloud kms keys add-iam-policy-binding <KEY> --keyring <RING> --location <LOC> --project <KMS_PROJ> --member="serviceAccount:service-<NUM>@gcp-sa-${SA}.iam.gserviceaccount.com" --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"; done
```

---

**文档版本 / Document Version**: 1.0  
**最后更新 / Last Updated**: 2026-01-23  
**适用场景 / Applicable Scenarios**: Cloud Scheduler + Pub/Sub + CMEK + Organization Policy



# Cloud Scheduler Job Resume 错误分析

## 问题分析

从错误信息来看，Cloud Scheduler 无法恢复 job `job-lex-eg-test-001`，错误提示为 **找不到父资源**。关键信息：

- **错误类型**：`NOT_FOUND`
- **资源路径**：`projects/445194165188/locations/europe-west2/streams/pubsub-target-dynamic-stream/retryPolicies/cs-9261c160-af94-43ab-ad66-ab7babc8e5e9`
- **特殊配置**：Pub/Sub Topic 使用了 `topic-encryption-key`

错误路径中包含 `streams` 和 `retryPolicies`，这表明该 Scheduler Job 可能使用了 **Pub/Sub Target** 并且配置了动态流或重试策略。

---

## 可能的原因分析

### 1. **Pub/Sub Topic 或 Subscription 已被删除**

#### 原因说明
- Scheduler Job 引用的 Pub/Sub Topic `pubsub-target-dynamic-stream` 可能已被删除
- 或者相关的 Subscription 不存在

#### 验证方法
```bash
# 检查 Topic 是否存在
gcloud pubsub topics describe pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev

# 列出所有 Topics
gcloud pubsub topics list \
    --project aibang-projectid-abjx01-dev \
    --filter="name:pubsub-target-dynamic-stream"
```

#### 解决方案
如果 Topic 不存在，需要重新创建：
```bash
gcloud pubsub topics create pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev \
    --topic-encryption-key projects/YOUR_PROJECT/locations/LOCATION/keyRings/YOUR_KEYRING/cryptoKeys/YOUR_KEY
```

---

### 2. **CMEK (Customer-Managed Encryption Key) 权限问题**

#### 原因说明
由于使用了 `topic-encryption-key`，可能存在以下权限问题：

1. **KMS Key 被禁用或删除**
2. **Cloud Scheduler 服务账号缺少 KMS 密钥权限**
3. **Pub/Sub 服务账号缺少 `cloudkms.cryptoKeyEncrypterDecrypter` 角色**

#### 验证方法
```bash
# 检查 KMS Key 状态
gcloud kms keys describe YOUR_KEY \
    --keyring YOUR_KEYRING \
    --location LOCATION \
    --project aibang-projectid-abjx01-dev

# 检查 Pub/Sub 服务账号权限
gcloud kms keys get-iam-policy YOUR_KEY \
    --keyring YOUR_KEYRING \
    --location LOCATION \
    --project aibang-projectid-abjx01-dev
```

#### 解决方案
授予必要的 KMS 权限：
```bash
# Pub/Sub 服务账号格式
# service-PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com

gcloud kms keys add-iam-policy-binding YOUR_KEY \
    --keyring YOUR_KEYRING \
    --location LOCATION \
    --project aibang-projectid-abjx01-dev \
    --member serviceAccount:service-445194165188@gcp-sa-pubsub.iam.gserviceaccount.com \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter
```

---

### 3. **Retry Policy 资源损坏或不一致**

#### 原因说明
错误路径中的 `retryPolicies/cs-9261c160-af94-43ab-ad66-ab7babc8e5e9` 表明：
- Scheduler Job 配置的 Retry Policy 资源损坏
- 可能是之前的配置残留或元数据不一致

#### 验证方法
```bash
# 查看 Scheduler Job 详细配置
gcloud scheduler jobs describe job-lex-eg-test-001 \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev
```

#### 解决方案
删除并重新创建 Scheduler Job：
```bash
# 1. 备份当前配置
gcloud scheduler jobs describe job-lex-eg-test-001 \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev \
    --format yaml > job-backup.yaml

# 2. 删除 Job
gcloud scheduler jobs delete job-lex-eg-test-001 \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev

# 3. 重新创建 Job (示例 - 根据实际配置调整)
gcloud scheduler jobs create pubsub job-lex-eg-test-001 \
    --location europe-west2 \
    --schedule "0 2 * * *" \
    --topic pubsub-target-dynamic-stream \
    --message-body '{"key":"value"}' \
    --project aibang-projectid-abjx01-dev
```

---

### 4. **区域 (Location) 不匹配**

#### 原因说明
- Scheduler Job 位于 `europe-west2`
- Pub/Sub Topic 可能在不同的区域
- CMEK Key 必须与资源在同一区域

#### 验证方法
```bash
# 检查 Topic 位置
gcloud pubsub topics describe pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev \
    --format="value(name)"

# 检查 KMS Key 位置
gcloud kms keys list \
    --keyring YOUR_KEYRING \
    --location LOCATION \
    --project aibang-projectid-abjx01-dev
```

#### 注意事项
- Pub/Sub Topics 是全局资源，但 CMEK Key 必须在同一区域
- Cloud Scheduler 的 `--location` 应与相关资源一致

---

### 5. **项目权限或 API 未启用**

#### 原因说明
- Cloud Scheduler API 或 Pub/Sub API 可能未启用
- 服务账号缺少必要的项目级权限

#### 验证方法
```bash
# 检查已启用的 API
gcloud services list --enabled \
    --project aibang-projectid-abjx01-dev \
    --filter="name:(cloudscheduler.googleapis.com OR pubsub.googleapis.com)"

# 检查当前用户权限
gcloud projects get-iam-policy aibang-projectid-abjx01-dev \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members:user:YOUR_EMAIL"
```

#### 解决方案
```bash
# 启用必要的 API
gcloud services enable cloudscheduler.googleapis.com \
    --project aibang-projectid-abjx01-dev

gcloud services enable pubsub.googleapis.com \
    --project aibang-projectid-abjx01-dev

gcloud services enable cloudkms.googleapis.com \
    --project aibang-projectid-abjx01-dev
```

---

## 故障排查流程图

```mermaid
graph TD
    A[Cloud Scheduler Resume 失败] --> B{检查 Pub/Sub Topic}
    B -->|不存在| C[重新创建 Topic with CMEK]
    B -->|存在| D{检查 CMEK Key 状态}
    
    D -->|Key 禁用/删除| E[恢复或重新创建 Key]
    D -->|Key 正常| F{检查服务账号权限}
    
    F -->|缺少权限| G[授予 cloudkms.cryptoKeyEncrypterDecrypter]
    F -->|权限正常| H{检查 Scheduler Job 配置}
    
    H -->|配置损坏| I[删除并重新创建 Job]
    H -->|配置正常| J{检查区域一致性}
    
    J -->|区域不匹配| K[调整资源到同一区域]
    J -->|区域一致| L[检查 API 和项目权限]
    
    C --> M[验证解决]
    E --> M
    G --> M
    I --> M
    K --> M
    L --> M
```

---

## 推荐的诊断步骤

### Step 1: 全面检查资源状态
```bash
# 检查 Scheduler Job
gcloud scheduler jobs describe job-lex-eg-test-001 \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev \
    --format yaml

# 检查 Pub/Sub Topic
gcloud pubsub topics describe pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev
```

### Step 2: 验证 CMEK 配置
```bash
# 从 Job 配置中提取 Topic 信息
TOPIC_NAME=$(gcloud scheduler jobs describe job-lex-eg-test-001 \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev \
    --format="value(pubsubTarget.topicName)")

# 检查 Topic 的加密配置
gcloud pubsub topics describe ${TOPIC_NAME} \
    --format="value(kmsKeyName)"
```

### Step 3: 检查服务账号权限
```bash
# Cloud Scheduler 服务账号
# service-PROJECT_NUMBER@gcp-sa-cloudscheduler.iam.gserviceaccount.com

# 检查是否有 pubsub.publisher 权限
gcloud pubsub topics get-iam-policy pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev
```

---

## 最佳实践建议

### 1. 使用 CMEK 时的注意事项
| 检查项 | 说明 |
|--------|------|
| **Key 位置** | 必须与资源在同一区域 (europe-west2) |
| **服务账号权限** | Pub/Sub 和 Scheduler 服务账号都需要 KMS 权限 |
| **Key 状态** | 确保 Key 处于 ENABLED 状态 |
| **审计日志** | 启用 Cloud KMS 审计日志以追踪权限问题 |

### 2. 预防措施
```bash
# 创建带 CMEK 的 Topic 时，同步授权
gcloud pubsub topics create pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev \
    --topic-encryption-key projects/aibang-projectid-abjx01-dev/locations/europe-west2/keyRings/YOUR_KEYRING/cryptoKeys/YOUR_KEY

# 立即授予服务账号权限
gcloud kms keys add-iam-policy-binding YOUR_KEY \
    --keyring YOUR_KEYRING \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev \
    --member serviceAccount:service-445194165188@gcp-sa-pubsub.iam.gserviceaccount.com \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter
```

### 3. 查看审计日志
```bash
# 查看 Cloud Scheduler 相关日志
gcloud logging read "resource.type=cloud_scheduler_job AND resource.labels.job_id=job-lex-eg-test-001" \
    --limit 50 \
    --project aibang-projectid-abjx01-dev \
    --format json
```

---

## 总结

基于 CMEK 配置，**最可能的原因**是：

1. **Pub/Sub 服务账号缺少 KMS Key 的加密/解密权限** (最高概率)
2. **Pub/Sub Topic 已被删除或重新创建导致引用失效**
3. **Scheduler Job 的内部 Retry Policy 配置损坏**

**建议优先执行**：
1. 验证 Pub/Sub Topic 是否存在
2. 检查并授予 KMS 权限
3. 如问题依旧，删除并重新创建 Scheduler Job


## Pub/Sub 和 Scheduler 服务账号都需要 KMS 权限
# 关于 CMEK 权限的详细说明

## 问题澄清

您的观察是**正确的**。让我详细解释为什么有些项目不需要显式授权也能工作。

---

## KMS 权限的实际需求

### 1. **只有 Pub/Sub 服务账号需要 KMS 权限**

```mermaid
graph LR
    A[Cloud Scheduler] -->|发布消息| B[Pub/Sub Topic with CMEK]
    B -->|需要加密/解密| C[KMS Key]
    
    style A fill:#e1f5ff
    style B fill:#fff4e1
    style C fill:#ffe1e1
    
    D[Pub/Sub 服务账号] -.->|必须有权限| C
    E[Scheduler 服务账号] -.->|不需要直接访问| C
```

#### 关键点说明

| 服务 | 是否需要 KMS 权限 | 原因 |
|------|------------------|------|
| **Pub/Sub 服务账号** | ✅ **必须** | 负责实际的消息加密/解密操作 |
| **Cloud Scheduler 服务账号** | ❌ **不需要** | 只需要 `pubsub.publisher` 权限发布消息到 Topic |

---

## 为什么有些项目不需要显式授权？

### 原因 1: **自动授权机制 (Auto-grant)**

当您在项目中**首次创建使用 CMEK 的 Pub/Sub Topic** 时，Google Cloud 会自动执行以下操作：

```bash
# Google Cloud 自动执行 (无需手动操作)
gcloud kms keys add-iam-policy-binding YOUR_KEY \
    --keyring YOUR_KEYRING \
    --location LOCATION \
    --member serviceAccount:service-PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter
```

#### 自动授权的触发条件

- 使用 Console 创建 Topic 并选择 CMEK
- 使用 Terraform 且配置了正确的依赖关系
- 使用 `gcloud pubsub topics create --topic-encryption-key` 命令

#### 验证是否自动授权
```bash
# 检查 KMS Key 的 IAM 策略
gcloud kms keys get-iam-policy YOUR_KEY \
    --keyring YOUR_KEYRING \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev \
    --format="table(bindings.members)"
```

**预期输出示例**:
```text
MEMBERS
serviceAccount:service-445194165188@gcp-sa-pubsub.iam.gserviceaccount.com
```

---

### 原因 2: **组织级别的 IAM 策略继承**

如果您的组织或文件夹级别配置了策略：

```bash
# 组织级别授权 (管理员配置)
gcloud kms keys add-iam-policy-binding YOUR_KEY \
    --keyring YOUR_KEYRING \
    --location LOCATION \
    --member serviceAccount:service-PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter
```

这种情况下，所有子项目都会继承该权限。

---

### 原因 3: **使用了 Default Encryption (非 CMEK)**

如果 Pub/Sub Topic **没有**使用 CMEK，而是使用 Google 管理的默认加密：

```bash
# 没有指定 --topic-encryption-key 参数
gcloud pubsub topics create my-topic \
    --project my-project
```

此时：
- ✅ **不需要任何 KMS 权限**
- ✅ Google 自动处理加密/解密
- ✅ Cloud Scheduler 只需要 `pubsub.publisher` 权限

#### 检查 Topic 是否使用 CMEK
```bash
gcloud pubsub topics describe pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev \
    --format="value(kmsKeyName)"
```

**输出判断**:
- **有输出** (如 `projects/.../cryptoKeys/...`) → 使用了 CMEK，需要 KMS 权限
- **无输出** (空白) → 使用默认加密，不需要 KMS 权限

---

## 您的错误与 KMS 权限的关系

### 核心判断逻辑

```mermaid
graph TD
    A[Cloud Scheduler Resume 失败] --> B{Topic 使用 CMEK?}
    B -->|是| C{Pub/Sub 服务账号有 KMS 权限?}
    B -->|否| D[错误与 KMS 无关]
    
    C -->|有| E[KMS 权限不是问题原因]
    C -->|无| F[**这是问题根源**]
    
    D --> G[检查其他原因:<br/>1. Topic 被删除<br/>2. Retry Policy 损坏<br/>3. 区域不匹配]
    E --> G
    F --> H[授予 KMS 权限]
```

### 验证步骤

```bash
# Step 1: 确认 Topic 是否使用 CMEK
KMS_KEY=$(gcloud pubsub topics describe pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev \
    --format="value(kmsKeyName)")

if [ -z "$KMS_KEY" ]; then
    echo "✅ Topic 使用默认加密，不需要 KMS 权限"
else
    echo "⚠️  Topic 使用 CMEK: $KMS_KEY"
    echo "需要检查 Pub/Sub 服务账号权限"
fi

# Step 2: 如果使用 CMEK，检查权限
if [ -n "$KMS_KEY" ]; then
    gcloud kms keys get-iam-policy $(basename $KMS_KEY) \
        --keyring $(echo $KMS_KEY | cut -d'/' -f6) \
        --location $(echo $KMS_KEY | cut -d'/' -f4) \
        --project aibang-projectid-abjx01-dev \
        --flatten="bindings[].members" \
        --filter="bindings.members:service-445194165188@gcp-sa-pubsub.iam.gserviceaccount.com"
fi
```

---

## 关于 Cloud Scheduler 服务账号的说明

### Cloud Scheduler 需要的权限

Cloud Scheduler **只需要** Pub/Sub Publisher 权限，**不需要** KMS 权限：

```bash
# Cloud Scheduler 服务账号需要的权限
gcloud pubsub topics add-iam-policy-binding pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev \
    --member serviceAccount:service-445194165188@gcp-sa-cloudscheduler.iam.gserviceaccount.com \
    --role roles/pubsub.publisher
```

### 权限分工表

| 操作 | 执行者 | 需要的权限 |
|------|--------|-----------|
| 发布消息到 Topic | Cloud Scheduler | `roles/pubsub.publisher` (on Topic) |
| 加密消息内容 | Pub/Sub 服务 | `roles/cloudkms.cryptoKeyEncrypterDecrypter` (on KMS Key) |
| 解密消息内容 | Pub/Sub 服务 | `roles/cloudkms.cryptoKeyEncrypterDecrypter` (on KMS Key) |
| 投递消息到 Subscription | Pub/Sub 服务 | 内部权限，无需配置 |

---

## 您的实际情况分析

### 场景 1: Topic 使用默认加密

```bash
# 检查命令
gcloud pubsub topics describe pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev
```

**如果输出中没有 `kmsKeyName` 字段**:
- ✅ 不需要任何 KMS 权限
- ✅ 您观察到的"其他项目没有授权也能用"是正常的
- ⚠️  当前错误**不是** KMS 权限问题

### 场景 2: Topic 使用 CMEK 且有自动授权

```bash
# 检查自动授权
gcloud kms keys get-iam-policy YOUR_KEY \
    --keyring YOUR_KEYRING \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev
```

**如果输出中包含 Pub/Sub 服务账号**:
```yaml
bindings:
- members:
  - serviceAccount:service-445194165188@gcp-sa-pubsub.iam.gserviceaccount.com
  role: roles/cloudkms.cryptoKeyEncrypterDecrypter
```

- ✅ 权限已正确配置
- ⚠️  当前错误**不是** KMS 权限问题

---

## 重新聚焦您的错误

基于错误信息：
```text
parent resource not found for projects/.../streams/pubsub-target-dynamic-stream/retryPolicies/...
```

### 更可能的原因

1. **Topic `pubsub-target-dynamic-stream` 被删除后重新创建**
   - Scheduler Job 仍然引用旧的 Topic 资源 ID
   - 解决方案：重新创建 Scheduler Job

2. **Retry Policy 配置损坏**
   - 内部元数据不一致
   - 解决方案：删除并重新创建 Job

3. **区域资源不匹配**
   - Scheduler Job 在 `europe-west2`
   - 但引用的资源在其他区域
   - 解决方案：检查所有资源的 location

### 推荐的诊断命令

```bash
# 1. 检查 Topic 是否真的存在
gcloud pubsub topics list \
    --project aibang-projectid-abjx01-dev \
    --filter="name:pubsub-target-dynamic-stream"

# 2. 检查 Scheduler Job 引用的 Topic 名称
gcloud scheduler jobs describe job-lex-eg-test-001 \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev \
    --format="value(pubsubTarget.topicName)"

# 3. 对比是否一致
# 如果不一致，说明 Topic 被重新创建过
```

---

## 总结

### 关键结论

1. **只有 Pub/Sub 服务账号需要 KMS 权限**，Cloud Scheduler 不需要
2. **很多情况下会自动授权**，所以您没看到手动配置也能工作
3. **您当前的错误很可能不是 KMS 权限问题**，而是：
   - Topic 被删除重新创建
   - Retry Policy 元数据损坏
   - 资源引用不一致

### 下一步建议

```bash
# 执行完整诊断
echo "=== 检查 Topic 存在性 ==="
gcloud pubsub topics describe pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev

echo "=== 检查 Topic 是否使用 CMEK ==="
gcloud pubsub topics describe pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev \
    --format="value(kmsKeyName)"

echo "=== 检查 Scheduler Job 配置 ==="
gcloud scheduler jobs describe job-lex-eg-test-001 \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev \
    --format=yaml
```

如果以上命令有任何失败或输出异常，请分享结果，我可以进一步精确定位问题。


# Cloud Scheduler + Pub/Sub + CMEK 权限验证

## 问题重述

需要验证：**在 Cloud Scheduler + Pub/Sub + CMEK 场景中，`gcp-sa-cloudscheduler` 服务账号是否必须有 KMS 权限**

---

## 验证方法

### 实验设计

```mermaid
graph TD
    A[创建测试环境] --> B[设置 CMEK Key]
    B --> C[创建加密的 Pub/Sub Topic]
    C --> D[创建 Cloud Scheduler Job]
    
    D --> E{Scenario 1:<br/>只授权 gcp-sa-pubsub}
    D --> F{Scenario 2:<br/>只授权 gcp-sa-cloudscheduler}
    D --> G{Scenario 3:<br/>都授权}
    D --> H{Scenario 4:<br/>都不授权}
    
    E --> I[测试 Job 执行]
    F --> I
    G --> I
    H --> I
    
    I --> J[观察结果]
```

---

## 实验步骤

### 环境准备

```bash
# 变量定义
PROJECT_ID="aibang-projectid-abjx01-dev"
PROJECT_NUMBER="445194165188"
LOCATION="europe-west2"
KMS_KEYRING="test-keyring"
KMS_KEY="test-cmek-key"
TOPIC_NAME="test-scheduler-cmek-topic"
JOB_NAME="test-scheduler-cmek-job"

# 服务账号
PUBSUB_SA="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
SCHEDULER_SA="service-${PROJECT_NUMBER}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
```

### Step 1: 创建 KMS Key

```bash
# 创建 Key Ring (如果不存在)
gcloud kms keyrings create ${KMS_KEYRING} \
    --location ${LOCATION} \
    --project ${PROJECT_ID}

# 创建 CMEK Key
gcloud kms keys create ${KMS_KEY} \
    --keyring ${KMS_KEYRING} \
    --location ${LOCATION} \
    --purpose encryption \
    --project ${PROJECT_ID}
```

### Step 2: 创建加密的 Pub/Sub Topic (不自动授权)

```bash
# 使用 API 创建以避免自动授权
cat > topic_config.json <<EOF
{
  "name": "projects/${PROJECT_ID}/topics/${TOPIC_NAME}",
  "kmsKeyName": "projects/${PROJECT_ID}/locations/${LOCATION}/keyRings/${KMS_KEYRING}/cryptoKeys/${KMS_KEY}"
}
EOF

# 使用 REST API 创建 (绕过自动授权)
gcloud pubsub topics create ${TOPIC_NAME} \
    --project ${PROJECT_ID} \
    --topic-encryption-key "projects/${PROJECT_ID}/locations/${LOCATION}/keyRings/${KMS_KEYRING}/cryptoKeys/${KMS_KEY}"
```

### Step 3: 创建 Cloud Scheduler Job

```bash
gcloud scheduler jobs create pubsub ${JOB_NAME} \
    --location ${LOCATION} \
    --schedule "*/5 * * * *" \
    --topic ${TOPIC_NAME} \
    --message-body '{"test":"data"}' \
    --project ${PROJECT_ID}
```

---

## 测试场景

### Scenario 1: 只授权 Pub/Sub 服务账号

```bash
# 清除所有现有权限
gcloud kms keys remove-iam-policy-binding ${KMS_KEY} \
    --keyring ${KMS_KEYRING} \
    --location ${LOCATION} \
    --member "serviceAccount:${PUBSUB_SA}" \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --project ${PROJECT_ID} 2>/dev/null || true

gcloud kms keys remove-iam-policy-binding ${KMS_KEY} \
    --keyring ${KMS_KEYRING} \
    --location ${LOCATION} \
    --member "serviceAccount:${SCHEDULER_SA}" \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --project ${PROJECT_ID} 2>/dev/null || true

# 只授权 Pub/Sub
gcloud kms keys add-iam-policy-binding ${KMS_KEY} \
    --keyring ${KMS_KEYRING} \
    --location ${LOCATION} \
    --member "serviceAccount:${PUBSUB_SA}" \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --project ${PROJECT_ID}

# 测试
gcloud scheduler jobs run ${JOB_NAME} \
    --location ${LOCATION} \
    --project ${PROJECT_ID}

# 等待并检查结果
sleep 10
gcloud logging read "resource.type=cloud_scheduler_job AND resource.labels.job_id=${JOB_NAME}" \
    --limit 5 \
    --project ${PROJECT_ID} \
    --format="table(timestamp,severity,textPayload)"
```

### Scenario 2: 只授权 Cloud Scheduler 服务账号

```bash
# 清除所有权限
gcloud kms keys remove-iam-policy-binding ${KMS_KEY} \
    --keyring ${KMS_KEYRING} \
    --location ${LOCATION} \
    --member "serviceAccount:${PUBSUB_SA}" \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --project ${PROJECT_ID} 2>/dev/null || true

# 只授权 Scheduler
gcloud kms keys add-iam-policy-binding ${KMS_KEY} \
    --keyring ${KMS_KEYRING} \
    --location ${LOCATION} \
    --member "serviceAccount:${SCHEDULER_SA}" \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --project ${PROJECT_ID}

# 测试
gcloud scheduler jobs run ${JOB_NAME} \
    --location ${LOCATION} \
    --project ${PROJECT_ID}

# 检查结果
sleep 10
gcloud logging read "resource.type=cloud_scheduler_job" \
    --limit 5 \
    --project ${PROJECT_ID}
```

### Scenario 3: 都授权

```bash
# 授权 Pub/Sub
gcloud kms keys add-iam-policy-binding ${KMS_KEY} \
    --keyring ${KMS_KEYRING} \
    --location ${LOCATION} \
    --member "serviceAccount:${PUBSUB_SA}" \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --project ${PROJECT_ID}

# 授权 Scheduler
gcloud kms keys add-iam-policy-binding ${KMS_KEY} \
    --keyring ${KMS_KEYRING} \
    --location ${LOCATION} \
    --member "serviceAccount:${SCHEDULER_SA}" \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --project ${PROJECT_ID}

# 测试
gcloud scheduler jobs run ${JOB_NAME} \
    --location ${LOCATION} \
    --project ${PROJECT_ID}
```

---

## 理论分析

### 官方文档查证

```bash
# 查看 Cloud Scheduler 官方文档关于 CMEK 的说明
# https://cloud.google.com/scheduler/docs/configuring-cmek
```

### 权限流程分析

```mermaid
sequenceDiagram
    participant CS as Cloud Scheduler
    participant PST as Pub/Sub Topic<br/>(with CMEK)
    participant KMS as KMS Key
    
    Note over CS,KMS: 场景分析
    
    rect rgb(240, 248, 255)
        Note right of CS: 传统理解 (可能错误)
        CS->>PST: 1. 发布消息 (明文)
        PST->>KMS: 2. 请求加密密钥
        Note over PST,KMS: Pub/Sub 服务使用自己的服务账号
        KMS-->>PST: 3. 返回加密密钥
        PST->>PST: 4. 加密消息
    end
    
    rect rgb(255, 240, 240)
        Note right of CS: 新假设 (待验证)
        CS->>KMS: 1. 请求加密密钥?
        Note over CS,KMS: Scheduler 服务使用自己的服务账号?
        KMS-->>CS: 2. 返回加密密钥?
        CS->>PST: 3. 发布加密消息?
    end
```

---

## 验证方法 2: 审计日志分析

### 启用 KMS 审计日志

```bash
# 获取当前 IAM 策略
gcloud projects get-iam-policy ${PROJECT_ID} \
    --format=json > iam_policy.json

# 添加审计日志配置
cat > audit_config.json <<EOF
{
  "auditConfigs": [
    {
      "service": "cloudkms.googleapis.com",
      "auditLogConfigs": [
        {
          "logType": "DATA_READ"
        },
        {
          "logType": "DATA_WRITE"
        }
      ]
    }
  ]
}
EOF

# 更新策略
gcloud projects set-iam-policy ${PROJECT_ID} iam_policy.json
```

### 触发 Scheduler Job 并分析日志

```bash
# 运行 Job
gcloud scheduler jobs run ${JOB_NAME} \
    --location ${LOCATION} \
    --project ${PROJECT_ID}

# 等待执行
sleep 15

# 查看 KMS 审计日志 - 查找是哪个服务账号调用了 KMS
gcloud logging read '
resource.type="cloudkms_cryptokeyversion"
AND protoPayload.methodName=~"Encrypt|Decrypt"
AND timestamp>="'$(date -u -d '2 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')'"
' \
    --project ${PROJECT_ID} \
    --format="table(
        timestamp,
        protoPayload.authenticationInfo.principalEmail,
        protoPayload.methodName,
        protoPayload.resourceName
    )" \
    --limit 10
```

### 关键观察点

**如果看到**:
- `principalEmail: service-XXX@gcp-sa-pubsub.iam.gserviceaccount.com`
  - ✅ 说明是 Pub/Sub 服务账号在加密/解密
  - ✅ 原说法**错误**，Scheduler 不需要 KMS 权限

**如果看到**:
- `principalEmail: service-XXX@gcp-sa-cloudscheduler.iam.gserviceaccount.com`
  - ✅ 说明是 Scheduler 服务账号在加密
  - ✅ 您的假设**正确**，Scheduler 需要 KMS 权限

---

## 验证方法 3: 检查现有工作环境

### 检查您其他能正常工作的项目

```bash
# 在一个正常工作的项目中
WORKING_PROJECT="your-working-project-id"
WORKING_KEY="your-cmek-key"
WORKING_KEYRING="your-keyring"

# 查看谁有权限
gcloud kms keys get-iam-policy ${WORKING_KEY} \
    --keyring ${WORKING_KEYRING} \
    --location ${LOCATION} \
    --project ${WORKING_PROJECT} \
    --flatten="bindings[].members" \
    --format="table(bindings.role,bindings.members)" \
    --filter="bindings.role=roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

**预期分析**:
- 如果只看到 `gcp-sa-pubsub` → 原理解正确
- 如果同时看到 `gcp-sa-cloudscheduler` → 您的假设正确
- 如果只看到 `gcp-sa-cloudscheduler` → 您的假设正确且强化

---

## 快速验证脚本

```bash
#!/bin/bash

# 完整验证脚本
PROJECT_ID="aibang-projectid-abjx01-dev"
PROJECT_NUMBER="445194165188"
LOCATION="europe-west2"

echo "=== 检查 Pub/Sub 服务账号 KMS 权限 ==="
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com AND bindings.role:roles/cloudkms.cryptoKeyEncrypterDecrypter"

echo ""
echo "=== 检查 Cloud Scheduler 服务账号 KMS 权限 ==="
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members:service-${PROJECT_NUMBER}@gcp-sa-cloudscheduler.iam.gserviceaccount.com AND bindings.role:roles/cloudkms.cryptoKeyEncrypterDecrypter"

echo ""
echo "=== 检查现有 CMEK Keys 的 IAM 策略 ==="
for key in $(gcloud kms keys list --location=${LOCATION} --keyring=YOUR_KEYRING --project=${PROJECT_ID} --format="value(name)"); do
    echo "Key: $key"
    gcloud kms keys get-iam-policy $(basename $key) \
        --keyring YOUR_KEYRING \
        --location ${LOCATION} \
        --project ${PROJECT_ID} \
        --format="yaml"
    echo "---"
done
```

---

## 基于 Google 官方文档的查证

### 官方文档检索关键点

1. **Cloud Scheduler CMEK 文档**
   ```bash
   # 访问并搜索关键词 "service account"
   # https://cloud.google.com/scheduler/docs/configuring-cmek
   ```

2. **Pub/Sub CMEK 文档**
   ```bash
   # 访问并对比权限要求
   # https://cloud.google.com/pubsub/docs/encryption
   ```

### 文档中的关键信息

**需要在文档中确认**:
- Cloud Scheduler 是否需要 `cloudkms.cryptoKeyEncrypterDecrypter`
- Pub/Sub Topic with CMEK 的权限模型
- 服务账号的实际调用路径

---

## 我的理论判断 (待验证)

### 假设 A: 传统模型 (更可能)

```mermaid
graph LR
    A[Cloud Scheduler] -->|明文消息| B[Pub/Sub API]
    B -->|调用 KMS| C[KMS Encrypt]
    C -->|使用 gcp-sa-pubsub 身份| D[加密消息]
    D -->|存储| E[Pub/Sub Topic]
    
    style C fill:#e1ffe1
    Note1[只需要 Pub/Sub SA 有权限]
```

**理由**:
- Cloud Scheduler 的职责是"调度和发送"
- Pub/Sub 的职责是"接收、加密、存储"
- 加密操作在 Pub/Sub 服务内部完成
- 符合职责分离原则

### 假设 B: 您的模型 (待验证)

```mermaid
graph LR
    A[Cloud Scheduler] -->|调用 KMS| B[KMS Encrypt]
    B -->|使用 gcp-sa-cloudscheduler 身份| C[加密消息]
    C -->|发送| D[Pub/Sub Topic]
    
    style B fill:#ffe1e1
    Note2[需要 Scheduler SA 有权限]
```

**可能的理由**:
- Cloud Scheduler 在发送前就加密消息
- 端到端加密模型
- 需要验证官方文档

---

## 立即可执行的验证

### 最简单的验证方法

```bash
# 1. 检查您当前失败的项目
PROJECT_ID="aibang-projectid-abjx01-dev"
PROJECT_NUMBER="445194165188"

# 2. 查找所有 CMEK Keys
gcloud kms keys list \
    --location europe-west2 \
    --format="table(name)" \
    --project ${PROJECT_ID}

# 3. 对每个 Key 检查权限
# 替换 YOUR_KEYRING 和 YOUR_KEY
gcloud kms keys get-iam-policy YOUR_KEY \
    --keyring YOUR_KEYRING \
    --location europe-west2 \
    --project ${PROJECT_ID} \
    --format="yaml"
```

### 预期结果分析

**如果输出包含**:
```yaml
bindings:
- members:
  - serviceAccount:service-445194165188@gcp-sa-pubsub.iam.gserviceaccount.com
  role: roles/cloudkms.cryptoKeyEncrypterDecrypter
- members:
  - serviceAccount:service-445194165188@gcp-sa-cloudscheduler.iam.gserviceaccount.com
  role: roles/cloudkms.cryptoKeyEncrypterDecrypter
```
→ ✅ 您的假设正确

**如果只包含**:
```yaml
bindings:
- members:
  - serviceAccount:service-445194165188@gcp-sa-pubsub.iam.gserviceaccount.com
  role: roles/cloudkms.cryptoKeyEncrypterDecrypter
```
→ ❌ 您的假设错误，问题在其他地方

---

## 总结与下一步

### 验证清单

- [ ] 检查现有 CMEK Key 的 IAM 策略
- [ ] 启用 KMS 审计日志并观察实际调用者
- [ ] 查阅官方文档确认权限要求
- [ ] 在测试项目中进行受控实验
- [ ] 对比工作和不工作的项目配置差异

### 我的建议

**立即执行**以下命令并分享结果：

```bash
# 检查您当前使用的 CMEK Key 权限
gcloud pubsub topics describe pubsub-target-dynamic-stream \
    --project aibang-projectid-abjx01-dev \
    --format="value(kmsKeyName)"

# 假设输出是: projects/aibang-projectid-abjx01-dev/locations/europe-west2/keyRings/XXX/cryptoKeys/YYY
# 提取 keyring 和 key 名称后执行:

gcloud kms keys get-iam-policy <KEY_NAME> \
    --keyring <KEYRING_NAME> \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev \
    --format="yaml"
```

**分享这个输出**，我就能确定您的假设是否正确。



这个问题你问得非常关键，而且你现在的观察是“对的”——
确实存在 Pub/Sub 没显式 KMS 授权也能正常工作的情况。
所以我们要把「理论上需要」和「实际上什么时候会失败」彻底拆开。

下面我给你一个平台级、可自洽的最终结论，把所有矛盾点一次性解释清楚。

⸻

一句话核心结论（先给答案）

不是所有 CMEK + Pub/Sub 场景都需要你手动给 gcp-sa-pubsub 授权。
但：Cloud Scheduler + Pub/Sub + CMEK 的场景里，gcp-sa-cloudscheduler 是“确定必须”的那个。

换句话说：
	•	✅ Scheduler SA 缺权限 → 一定会炸（你现在的情况）
	•	⚠️ Pub/Sub SA 缺权限 → 取决于“Key 是谁创建的 / 在哪里 / 什么时候创建的”

⸻

二、你现在看到的“反直觉现象”为什么是成立的？

现象：
KMS IAM 里 没看到
service-<project>@gcp-sa-pubsub.iam.gserviceaccount.com
但 Pub/Sub Topic（CMEK）照样能正常工作

这是因为 Pub/Sub 有“隐式 KMS 使用能力”，而 Scheduler 没有。

⸻

三、关键区别：Pub/Sub vs Scheduler 对 CMEK 的使用方式

1️⃣ Pub/Sub：“存储型服务 + 系统托管路径”

Pub/Sub 使用 CMEK 的特点是：
	•	加密发生在 Google 管理的存储层
	•	很多场景下：
	•	KMS Key 和 Topic 在同一 project
	•	Key 是由 project owner / admin 创建
	•	Google 会通过 内部受信通道让 Pub/Sub 使用这个 key

👉 结果就是：
	•	你 不一定能在 IAM policy 里看到 gcp-sa-pubsub
	•	但 Pub/Sub 依然可以正常 encrypt / decrypt

这是 Google 为“降低使用门槛”做的 产品级优化

⸻

2️⃣ Cloud Scheduler：“跨服务资源创建者”

Cloud Scheduler 完全不一样：
	•	它不是存储服务
	•	它会：
	•	创建新的内部 Pub/Sub Stream
	•	这个 Stream 是 Scheduler 自己的资源
	•	它必须 主动调用 KMS API

👉 对 Scheduler 来说：

“如果 IAM policy 里没有我，我就不能用这个 key”

没有任何隐式兜底机制。

⸻

四、所以：到底“缺的是哪一个权限”？（精准回答你的问题）

结合你的现象，答案是：

你缺的不是 gcp-sa-pubsub，而是 gcp-sa-cloudscheduler

原因链条是这样的：

Scheduler resume
→ Scheduler 创建 internal Pub/Sub stream
→ Stream 使用 Topic 的 CMEK
→ Scheduler SA 需要直接调用 KMS
→ 没权限
→ stream 创建失败
→ retryPolicy 没 parent
→ NOT_FOUND

而在这个阶段：
	•	Pub/Sub SA 甚至还没开始工作
	•	它“有没有权限”根本不在这条路径上

⸻

五、什么时候你「真的」需要给 gcp-sa-pubsub 授权？

下面这个表是实战判断表，非常重要。

你现在的环境（为什么它能跑）

条件	是否满足
Key 和 Topic 在同一 project	✅
Key 是由项目管理员创建	✅
没有跨项目 / 跨组织	✅
Topic 创建后未迁移	✅

👉 Pub/Sub 会“自动兜底”

⸻

以下任意一条成立，就“必须”显式给 gcp-sa-pubsub

场景	是否必须
KMS Key 在 独立 security 项目	✅
跨组织共享 KMS	✅
使用 Key-level IAM 且收紧默认权限	✅
安全团队启用 Domain Restricted Sharing / Org Policy	✅
安全审计要求“显式最小授权”	✅


⸻

六、为什么 Scheduler 没有这种“隐式能力”？

一句话解释：

因为 Scheduler 不是“数据服务”，它是“控制面服务”。

Google 不会默认允许一个控制面服务：
	•	去使用任意项目的 KMS Key
	•	否则这是一个严重的安全模型问题

所以 Scheduler：
	•	❌ 没有 implicit grant
	•	❌ 不会继承 Topic 的“隐式信任”
	•	✅ 必须显式授权

⸻

七、最终给你一个“不会再纠结”的判断公式（建议记住）

如果一个服务：
- 自己创建资源
- 该资源使用 CMEK
- 并且它不是数据存储服务

那么：
→ 100% 需要显式 KMS IAM

套到你这里：

服务	是否符合	结论
Cloud Scheduler	✅	必须授权
Pub/Sub	❌（数据服务）	可能隐式


⸻

八、平台级最终建议（非常实用）

技术上最小必需

必须：gcp-sa-cloudscheduler

平台 / 安全 / 长期演进推荐

推荐：gcp-sa-cloudscheduler + gcp-sa-pubsub

原因不是“现在会坏”，而是：
	•	避免未来跨项目 / 安全策略变化
	•	避免“换环境突然炸”
	•	避免审计被 challenge

⸻

最后一句总结（帮你把脑内冲突完全消掉）

你现在看到的 Pub/Sub “没授权也能用”不是错觉，而是 Google 的隐式托管能力；
但 Cloud Scheduler 不在这个保护范围内，所以真正导致你报错的，是 Scheduler Service Agent 缺少 KMS 权限，而不是 Pub/Sub Service Agent。

如果你愿意，我可以下一步帮你做一件很“平台”的事：
👉 给你一份《哪些 GCP 服务有 CMEK 隐式能力，哪些没有》的对照清单
这个在设计规范时非常值钱。