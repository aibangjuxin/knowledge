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

## Q&A: Why does a Scheduler Job error relate to KMS? / 问答：为什么 Scheduler 任务报错与 KMS 有关？

**User Question / 用户疑问**:
> "I see all the verification steps are related to Pub/Sub. But my error is with the **Cloud Scheduler Job**. Are these two directly related?
> I verified `roles/cloudscheduler.serviceAgent` and my account is listed. Why does it relate to the Pub/Sub KMS permissions?"
>
> “我看到所有的验证过程都是跟 Pub/Sub 有关的。但其实我的报错是 **Cloud Scheduler Job** 的问题。这两个有直接关系吗？
> 我检查了 `roles/cloudscheduler.serviceAgent`，我的账号也在里面。那它跟 KMS 那个有什么关系呢？”

**Answer / 解答**:

Yes, they are directly related. The `NOT_FOUND` error you are seeing is a symptom of the **integration failure** between Scheduler and Pub/Sub, not a failure of the Scheduler Service Agent itself.
是的，它们有直接关系。您看到的 `NOT_FOUND` 错误是 Scheduler 与 Pub/Sub **集成失败** 的症状，而不是 Scheduler 服务代理本身的故障。

### 1. The "Hidden" Chain of Trust / “隐藏”的信任链
When Cloud Scheduler targets Pub/Sub, it does not just "send" a message into the void. It must establish a authenticated connection stream to the specific Topic.
当 Cloud Scheduler 以 Pub/Sub 为目标时，它不仅仅是向虚空“发送”一条消息。它必须建立一个通往特定主题（Topic）的经过验证的连接流。

*   **Organization Policy Enforcement**: Your environment enforces `restrictNonCmekServices`. This means **DATA** cannot exist or be transmitted unless encrypted with your Key.
    *   **组织策略强制执行**: 您的环境强制执行了 `restrictNonCmekServices`。这意味着除非使用您的密钥加密，否则**数据**无法存在或传输。
*   **The Bottleneck**: The Pub/Sub Topic is the "Data Holder". Because of the policy, the Topic **MUST** be encrypted.
    *   **瓶颈所在**: Pub/Sub 主题是“数据持有者”。由于策略原因，该主题**必须**被加密。

### 2. Why the Service Agent Matters / 为什么服务代理很重要
You checked `cloudscheduler.serviceAgent`, which manages the *Scheduler Control Plane* (creating jobs, etc.). However, the actual encryption/decryption of the message payload happens at the **Pub/Sub layer**.
您检查了 `cloudscheduler.serviceAgent`，它管理 *Scheduler 控制平面*（创建任务等）。然而，消息负载的实际加密/解密发生在 **Pub/Sub 层**。

*   **Scenario A: Topic is NOT Encrypted (Non-CMEK)**
    *   The Org Policy immediately **blocks** the connection creation. Scheduler tries to create an internal stream -> Policy says "No" -> Scheduler returns `NOT_FOUND` (Generic error for "I couldn't create my backend").
    *   **场景 A: 主题未加密 (非 CMEK)**: 组织策略立即**阻止**连接创建。Scheduler 尝试创建内部流 -> 策略拒绝 -> Scheduler 返回 `NOT_FOUND`（“无法创建后端”的通用错误）。

*   **Scenario B: Topic IS Encrypted, but Pub/Sub Agent lacks KMS Role**
    *   The Topic exists, but it is **broken**. Pub/Sub tries to accept the message but cannot access the Key to verify/encrypt it. The "Handshake" fails. Scheduler again fails to attach to the topic.
    *   **场景 B: 主题已加密，但 Pub/Sub 代理缺少 KMS 角色**: 主题存在，但**已损坏**。Pub/Sub 尝试接收消息，但无法访问密钥进行验证/加密。“握手”失败。Scheduler 再次无法连接到主题。

### Summary / 总结
The `NOT_FOUND` error is misleading. It effectively means:
> "I (Scheduler) tried to connect to your Pub/Sub Topic to prepare for sending messages, but the connection was rejected or the resource was unreachable due to Policy/Encryption configurations."
这个 `NOT_FOUND` 错误具有误导性。它的实际含义是：
> “我 (Scheduler) 尝试连接到您的 Pub/Sub 主题以准备发送消息，但由于 策略/加密 配置，连接被拒绝或资源无法通过验证。”

**Fix**: Ensure the Topic is CMEK-encrypted **AND** the Pub/Sub Service Agent (not just the Scheduler Agent) has access to the Key.
**修复**: 确保主题是 CMEK 加密的，**并且** Pub/Sub 服务代理（不仅仅是 Scheduler 代理）拥有访问密钥的权限。

## Final Solution: Why "Resume" Still Fails? / 最终解决方案：为什么 “Resume” 仍然失败？

**Scenario / 场景**:
> "I have enabled CMEK for my Pub/Sub Topic, and I confirmed all permissions are correct. But when I run `gcloud scheduler jobs resume`, it **STILL** fails with `NOT_FOUND`."
>
> “我已经为 Pub/Sub 主题启用了 CMEK，并确认所有权限都正确。但是当我运行 `gcloud scheduler jobs resume` 时，它**仍然**失败并报错 `NOT_FOUND`。”

**Root Cause / 根本原因**:
**Stale Internal State / 内部状态陈旧**
When a Cloud Scheduler job is paused (or fails creation) due to a policy violation (like missing CMEK), its internal link to the backend (the "RetryPolicy" resource mentioned in the error) is often never successfully created or is marked as permanently broken.
当 Cloud Scheduler 任务因策略违规（如缺少 CMEK）而暂停（或创建失败）时，其指向后端的内部链接（错误信息中提到的 "RetryPolicy" 资源）通常从未成功创建，或者被标记为永久损坏。

Running `resume` only attempts to unpause the *existing* job definition, which points to a **non-existent or invalid backend resource**. It does **not** trigger a re-provisioning of the underlying infrastructure link.
运行 `resume` 仅仅尝试取消暂停 *现有的* 任务定义，而该定义指向一个 **不存在或无效的后端资源**。它 **不会** 触发底层基础设施链接的重新预配。

**The Fix: Recreate, Don't Resume / 解决方法：重建，不要恢复**
You **MUST** delete and recreate the job to force Cloud Scheduler to establish a *new* compliance check and create a *new* backend connection.
您 **必须** 删除并重建该任务，以强制 Cloud Scheduler 建立 *新的* 合规性检查并创建 *新的* 后端连接。

### Definitive Solution Steps / 最终解决步骤

1.  **Delete the Broken Job / 删除损坏的任务**:
    ```bash
    gcloud scheduler jobs delete job-lex-eg-test-001 \
        --location europe-west2 \
        --project aibang-projectid-abjx01-dev \
        --quiet
    ```

2.  **Verify Topic is Ready (CMEK Enabled) / 验证主题就绪 (CMEK 已启用)**:
    ```bash
    gcloud pubsub topics describe [TOPIC_NAME] \
        --project aibang-projectid-abjx01-dev \
        --format="value(kmsKeyName)"
    # Ensure it returns your Key ID / 确保它返回您的 Key ID
    ```

3.  **Create a NEW Job / 创建一个新任务**:
    ```bash
    gcloud scheduler jobs create pubsub job-lex-eg-test-001 \
        --schedule="* * * * *" \
        --topic=[TOPIC_NAME] \
        --message-body="{\"test\": \"payload\"}" \
        --location europe-west2 \
        --project aibang-projectid-abjx01-dev
    ```

**Result / 结果**:
The new job will initiate a fresh connection request. Since the Topic is now encrypted and permissions are correct, the connection will succeed, and the job will be created in `ENABLED` state immediately.
新任务将发起一个新的连接请求。由于主题现在已加密且权限正确，连接将成功，任务将立即以 `ENABLED` 状态创建。

## Q&A: Where is the CMEK parameter in Cloud Scheduler? / 问答：Cloud Scheduler 的 CMEK 参数在哪里？

**User Question / 用户疑问**:
> "I don't see any CMEK-related parameter when creating the Cloud Scheduler job. So how does it map to the encryption? Why does recreating it fix the mapping?"
>
> “我在创建 Cloud Scheduler 任务时，并没有看到任何跟 CMEK 有关的参数。那么它是如何映射到加密的呢？为什么重新创建就能修复这个映射关系？”

**Answer / 解答**:
You are correct, the Scheduler Job itself does not have a `--kms-key` flag. The dependency is **implicit** (隐式的).
你说的对，Scheduler 任务本身没有 `--kms-key` 标志。这种依赖关系是 **隐式的**。

1.  **The "Target" Holds the Requirements / “目标”持有要求**:
    The CMEK requirement lives on the **Pub/Sub Topic**, not the Scheduler Job. The Org Policy checks: "Is the data destination encrypted?"
    CMEK 要求存在于 **Pub/Sub 主题** 上，而不是 Scheduler 任务上。组织策略检查的是：“数据目的地是否已加密？”

2.  **The "Mapping" is the Link / “映射”即是链接**:
    When you run `jobs create ... --topic=[TOPIC_NAME]`, you are creating a **Link**.
    *   **Creation Time**: Scheduler tries to "handshake" with the Topic.
    *   **The Check**: GCP checks "Is `[TOPIC_NAME]` compliant with Org Policy?" and "Does Scheduler have permission to write to this encrypted Topic?"
    *   **If Success**: The internal link is built.
    *   **If Failure**: The job is saved as "FAILED/PAUSED," and the link is **never built**.

    一旦你运行 `jobs create ... --topic=[TOPIC_NAME]`，你就是在创建一个 **链接**。
    *   **创建时**: Scheduler 尝试与 Topic “握手”。
    *   **检查**: GCP 检查 “`[TOPIC_NAME]` 是否符合组织策略？” 以及 “Scheduler 是否有权限向这个加密的 Topic 写入？”
    *   **如果成功**: 内部链接建立。
    *   **如果失败**: 任务被保存为 “失败/暂停” 状态，且链接 **从未建立**。

3.  **Why "Resume" Fails vs. "Recreate" Works / 为什么 “Resume” 失败而 “Recreate” 成功**:
    *   **Resume**: Only flips the status of the *existing* job object. It assumes the link is already built. If the link was never built (because it failed initially), Resume tries to wake up a "dead" link and fails with `NOT_FOUND`.
    *   **Recreate**: Forces the entire "Handshake" process to run again from scratch. Since you fixed the Topic and IAM permissions, this new handshake will succeed.

    *   **Resume**: 仅仅翻转 *现有* 任务对象的状态。它假设链接已经建立。如果链接从未建立（因为初始失败），Resume 试图唤醒一个“死”链接，因此报错 `NOT_FOUND`。
    *   **Recreate**: 强制从头开始再次运行整个“握手”过程。由于你已经修复了 Topic 和 IAM 权限，这次新的握手将会成功。
```
