# Cloud Scheduler Resume Failure: NOT_FOUND / Cloud Scheduler 恢复失败：资源未找到

## Problem Description / 问题描述

**English**:
Attempting to resume a Cloud Scheduler job fails with a `NOT_FOUND` error indicating a missing parent resource. The error references an internal `retryPolicies` resource, which typically suggests the link between Cloud Scheduler and its backend Pub/Sub topic is broken or failed to provision.

**Chinese**:
尝试恢复（Resume）Cloud Scheduler 任务时失败，报错 `NOT_FOUND`，提示缺少父级资源。错误信息中引用的 `retryPolicies` 资源通常表明 Cloud Scheduler 与其后端 Pub/Sub 主题之间的连接已断开，或在创建时未能成功预配。

### Command Executed / 执行的命令

```bash
gcloud scheduler jobs resume job-lex-eg-test-001 \
    --location europe-west2 \
    --project aibang-projectid-abjx01-dev
```

### Error Output / 错误输出

```text
ERROR: (gcloud.scheduler.jobs.resume) NOT_FOUND: Resource 'parent resource not found for projects/445194165188/locations/europe-west2/streams/pubsub-target-dynamic-stream/retryPolicies/cs-9261c160-af94-43ab-ad66-ab7babc8e5e9' was not found.

- '@type': type.googleapis.com/google.rpc.ResourceInfo
  resourceName: parent resource not found for projects/445194165188/locations/europe-west2/streams/pubsub-target-dynamic-stream/retryPolicies/cs-9261c160-af94-43ab-ad66-ab7babc8e5e9
```

## Context & Analysis / 背景与分析

### Organization Policy / 组织策略

**English**:
The user suspected the Organization Policy `constraints/gcp.restrictNonCmekServices` might be the cause.
Running the check command yielded the following output:
```yaml
constraint: constraints/gcp.restrictNonCmekServices
etage: BwvUSrnG=
```
**Analysis**:
This output confirms that the policy exists but **no specific rule is defined at the Project level**.
- **Inheritance**: In GCP, if a project does not explicitly define a policy, it **inherits** the effective policy from its parent (Folder or Organization).
- **Conclusion**: Since the `NOT_FOUND` error persists and relates to resource restrictions, it confirms that the **Organization Level enforces this policy**, and the project is inheriting that strict enforcement. This effectively blocks Cloud Scheduler from creating non-CMEK Pub/Sub publishers.

**Chinese**:
用户怀疑组织策略 `constraints/gcp.restrictNonCmekServices` 可能是导致问题的原因。
运行检查命令后得到的输出如上所示。
**分析**:
该输出确认策略存在，但**在项目级别没有定义具体的规则**。
- **继承机制**: 在 GCP 中，如果项目没有显式定义策略，它将**继承**来自父级（文件夹或组织）的有效策略。
- **结论**: 既然出现了与资源限制相关的 `NOT_FOUND` 错误，这证实了**组织级别（Organization Level）强制执行了该策略**，而当前项目继承了这一严格限制。这实际上阻止了 Cloud Scheduler 创建非 CMEK 加密的 Pub/Sub 发布者。

## Troubleshooting Guide / 排查指南

**English**:
The `NOT_FOUND` error on resume typically means the Scheduler Job exists in the frontend, but its internal backend resources failed to provision due to the CMEK policy.

**Chinese**:
恢复任务时出现的 `NOT_FOUND` 错误通常意味着 Scheduler 任务在前端存在（可见），但其内部后端资源因 CMEK 策略而预配失败。

### Step 1: Verify Pub/Sub Topic CMEK Configuration / 验证 Pub/Sub 主题 CMEK 配置

**English**:
If `gcp.restrictNonCmekServices` is enforced, the target Pub/Sub topic **MUST** be encrypted with a Customer Managed Encryption Key (CMEK).

**Chinese**:
如果强制执行了 `gcp.restrictNonCmekServices`，则目标 Pub/Sub 主题**必须**使用客户管理加密密钥 (CMEK) 进行加密。

1.  **Check Key Assignment / 检查密钥分配**:
    ```bash
    gcloud pubsub topics describe [TOPIC_NAME] \
        --project aibang-projectid-abjx01-dev \
        --format="value(kmsKeyName)"
    ```
    *If empty, the topic is non-compliant. / 如果为空，则主题不合规。*

2.  **Create Compliant Topic / 创建合规主题**:
    ```bash
    gcloud pubsub topics create [TOPIC_NAME] \
        --topic-encryption-key=[KEY_RESOURCE_ID] \
        --project aibang-projectid-abjx01-dev
    ```

### Step 2: Recreate the Cloud Scheduler Job / 重建 Cloud Scheduler 任务

**English**:
A job in this "NOT_FOUND" state cannot be fixed by editing. You must delete and recreate it, pointing to a verified, CMEK-encrypted topic.

**Chinese**:
处于这种 "NOT_FOUND" 状态的任务通常无法通过编辑修复。必须删除并重建该任务，并确保其指向一个已验证且经过 CMEK 加密的主题。

1.  **Delete Failed Job / 删除失败的任务**:
    ```bash
    gcloud scheduler jobs delete job-lex-eg-test-001 \
        --location europe-west2 \
        --project aibang-projectid-abjx01-dev
    ```

2.  **Recreate Job / 重建任务**:
    ```bash
    gcloud scheduler jobs create pubsub job-lex-eg-test-001 \
        --schedule="* * * * *" \
        --topic=[TOPIC_NAME] \
        --message-body="Test Payload" \
        --location europe-west2 \
        --project aibang-projectid-abjx01-dev
    ```

### Step 3: Verify Service Permissions / 验证服务权限

**English**:
For Pub/Sub to use the KMS key, its Service Agent must have the `cloudkms.cryptoKeyEncrypterDecrypter` role.

**Chinese**:
### Step 3: Verify & Grant Service Permissions / 验证并授予服务权限

**English**:
For Pub/Sub to use the KMS key, its Service Agent must have the `cloudkms.cryptoKeyEncrypterDecrypter` role on the specific key. Follow these detailed steps to verify and grant permissions.

**Chinese**:
为了让 Pub/Sub 能够使用 KMS 密钥，其服务代理（Service Agent）必须在指定密钥上拥有 `cloudkms.cryptoKeyEncrypterDecrypter` 角色。请按照以下详细步骤进行验证和授权。

#### 1. Setup Environment Variables / 设置环境变量
Define the variables first to make subsequent commands easier to copy-paste. / 首先定义变量，以便后续命令更易于复制粘贴。

```bash
# Replace with your actual values / 请替换为实际值
export PROJECT_ID="aibang-projectid-abjx01-dev"
export LOCATION="europe-west2"
export KEY_RING="[YOUR_KEY_RING_NAME]"
export KEY_NAME="[YOUR_KEY_NAME]"
```

#### 2. Get Pub/Sub Service Agent / 获取 Pub/Sub 服务代理
Retrieve the dedicated service account email for Pub/Sub in your project. / 获取您项目中 Pub/Sub 的专用服务账号邮箱。

```bash
PUBSUB_SA=$(gcloud beta services identity create --service=pubsub.googleapis.com --project $PROJECT_ID --format="value(email)")

echo "Pub/Sub Service Agent: $PUBSUB_SA"
# Output example: service-123456789@gcp-sa-pubsub.iam.gserviceaccount.com
```

#### 3. Check Existing Permissions / 检查现有权限
Verify if the Key already has the correct binding for this Service Agent. / 验证该密钥是否已对该服务代理进行了正确的绑定。

```bash
gcloud kms keys get-iam-policy $KEY_NAME \
    --location $LOCATION \
    --keyring $KEY_RING \
    --project $PROJECT_ID \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/cloudkms.cryptoKeyEncrypterDecrypter AND bindings.members:serviceAccount:$PUBSUB_SA" \
    --format="table(bindings.role, bindings.members)"
```
*   **If output implies "Listed 0 items" / 如果输出显示 "Listed 0 items"**: Permission is MISSING. Go to step 4. / 权限缺失，请执行第4步。
*   **If output lists the role and member / 如果输出列出了角色和成员**: Permission EXISTS. You can skip step 4. / 权限已存在，可以跳过第4步。

#### 4. Grant IAM Role / 授予 IAM 角色
If the permission was missing, grant it now. / 如果权限缺失，请立即授予。

```bash
gcloud kms keys add-iam-policy-binding $KEY_NAME \
    --location $LOCATION \
    --keyring $KEY_RING \
    --project $PROJECT_ID \
    --member "serviceAccount:$PUBSUB_SA" \
    --role "roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

#### 5. Final Verification / 最终验证
Run a full policy check to confirm the binding is active. / 运行完整的策略检查以确认绑定已生效。

```bash
gcloud kms keys get-iam-policy $KEY_NAME \
    --location $LOCATION \
    --keyring $KEY_RING \
    --project $PROJECT_ID \
    --format="table(bindings.role, bindings.members)" \
    --filter="bindings.role:roles/cloudkms.cryptoKeyEncrypterDecrypter"
```
*Ensure `serviceAccount:...` for Pub/Sub appears in the list. / 确保 Pub/Sub 的 `serviceAccount:...` 出现在列表中。*

#### 6. Verify IAM Role / 验证 IAM 角色
```bash
gcloud kms keys describe [KEY_NAME] \
    --location [LOCATION] \
    --keyring [KEYRING] \
    --format="value(plaintext)"
```
