明白了，我会帮你把上面的内容严格按照 GitHub 标准 Markdown 格式重新整理，包括：
	•	使用规范的二级标题（##）划分结构，如 "流程概述"、"流程图"、"脚本示例"、"注意事项"。
	•	Mermaid 流程图独立成节，并且符合 mermaid 包裹规则。
	•	所有代码示例用标准的 bash 或 ``` 格式包裹。
	•	表格使用标准 Markdown 表格语法，且列对齐良好。
	•	不包含多余的注释或不规范字符，保证复制后直接可以在 GitHub 上渲染正确。
	•	不额外生成 TOC（目录），除非你后续另有要求。

我这就帮你格式化好。

基于存储桶白名单自动创建或更新 Cloud Armor 规则的用户 Onboarding 流程

流程概述

在用户接入（Onboarding）场景下，本流程通过读取存储于 Google Cloud Storage（GCS）中存储桶中的“白名单”配置文件，自动创建或更新 Google Cloud Armor 的安全策略规则。具体来说，当有新用户需要接入系统时，相关的允许访问信息（例如用户的 IP 地址、域名等）会被生成并写入指定的 GCS 存储桶。随后，预先部署的 Cloud Function 脚本将被触发，读取该白名单文件并使用 Cloud Armor API 自动创建或更新相应的安全策略规则，从而放行这些新用户的流量。整个流程实现端到端自动化，避免了手动配置安全规则的繁琐操作。

主要流程如下：
	•	用户提交 Onboarding 请求后，系统生成对应的允许列表（白名单）配置文件。
	•	将白名单文件上传至特定的 GCS 存储桶，触发 Cloud Function 事件。
	•	Cloud Function 读取存储桶中的白名单内容，并调用 Cloud Armor 的 API 接口，自动创建或更新安全策略（Security Policy）及其内的规则。
	•	最终，新用户的访问请求因新增或更新的 Cloud Armor 规则而被允许或拦截，实现安全自动化接入。

流程图

下图示例展示了基于存储桶白名单自动创建或更新 Cloud Armor 规则的完整 Onboarding 流程：

flowchart TD
    A[用户提交 Onboarding 需求] --> B[生成并上传白名单文件至存储桶]
    B --> C[触发 Cloud Function]
    C --> D[Cloud Function 读取白名单配置]
    D --> E[调用 Cloud Armor API]
    E --> F[创建或更新安全策略规则]
    F --> G[流程结束]

流程图说明：
	•	用户提交 Onboarding 需求： 管理员或自动化系统发起新的用户接入申请。
	•	生成并上传白名单文件： 系统根据申请生成允许列表（如 IP 地址清单），并将文件上传到 GCS 的指定存储桶。
	•	触发 Cloud Function： 存储桶文件变更触发预先部署的 Cloud Function。
	•	读取白名单配置： Cloud Function 读取存储桶中的白名单文件内容。
	•	调用 Cloud Armor API： Cloud Function 解析白名单数据后，调用 Google Cloud Armor 的 API 创建或更新安全策略规则。
	•	创建或更新安全策略规则： 根据白名单动态生成的规则被添加到 Cloud Armor 安全策略中，以放行对应的用户流量。

脚本示例

以下示例展示了在 Bash 脚本中执行主要操作的常用命令。请根据具体环境和安全策略名称进行相应修改和替换。

示例 1：上传白名单文件至 GCS 存储桶

# 将本地的 white_list.txt 上传到指定的 GCS 存储桶
gsutil cp white_list.txt gs://my-whitelist-bucket/path/to/white_list.txt

示例 2：更新 Cloud Armor 安全策略规则

# 假设安全策略名为 USER-ONBOARDING-POLICY，以下命令更新其规则
gcloud compute security-policies rules update 100 \
    --security-policy=USER-ONBOARDING-POLICY \
    --action=allow \
    --src-ip-ranges="203.0.113.0/24,198.51.100.0/24" \
    --description="更新 Onboarding 白名单"

示例 3：创建新的安全策略及规则（如果策略不存在）

# 创建新的 Cloud Armor 安全策略
gcloud compute security-policies create USER-ONBOARDING-POLICY \
    --description="用户 Onboarding 白名单策略"

# 在策略中创建允许规则（优先级设为100）
gcloud compute security-policies rules create 100 \
    --security-policy=USER-ONBOARDING-POLICY \
    --action=allow \
    --src-ip-ranges="203.0.113.0/24,198.51.100.0/24" \
    --description="允许 Onboarding 白名单 IP"

下面的表格列出了上述脚本中使用的常见命令及其功能简介：

脚本命令	描述
gsutil cp <本地路径> gs://<bucket>/<路径>/	上传本地文件到 GCS 存储桶
gcloud compute security-policies create	创建 Cloud Armor 安全策略
gcloud compute security-policies rules create	向策略中添加新的安全规则
gcloud compute security-policies rules update	更新已有安全策略规则

注意事项
	•	权限配置： 确保执行脚本的服务账号（例如 Cloud Function 的服务账号）拥有读取 GCS 存储桶和更新 Cloud Armor 的相应权限。例如需要 roles/storage.objectViewer、roles/cloudfunctions.invoker、roles/compute.securityAdmin 等权限。以下表格列出了各组件所需的 IAM 角色：

资源组件	需要的 IAM 角色	说明
GCS 存储桶	roles/storage.objectViewer	读取白名单文件
Cloud Function	roles/cloudfunctions.invoker	执行触发函数
Cloud Armor 安全策略	roles/compute.securityAdmin	更新安全策略


	•	安全策略命名： 建议预先创建 Cloud Armor 安全策略并统一命名（如 USER-ONBOARDING-POLICY），或者在脚本中进行判断后动态创建。命名、项目和地区要保持一致，避免混淆。
	•	优先级管理： Cloud Armor 安全策略中的规则有优先级（priority）字段，请合理设置，避免与已有规则冲突。通常，将允许访问的白名单规则设置较低的优先级值（优先级值越低优先级越高）。
	•	存储桶触发条件： Cloud Function 应配置为仅针对特定存储桶和文件路径触发，避免对其他文件操作做出响应。同时，可通过前缀（prefix）和后缀（suffix）过滤器提高触发准确性。
	•	白名单文件格式： 确定白名单文件格式（如文本、JSON 或 YAML），并在 Cloud Function 脚本中按对应格式解析。确保文件内容格式正确且不为空，以免导致脚本错误。
	•	日志和监控： 建议在 Cloud Function 中添加日志记录，并监控 Cloud Armor 安全策略的变更，以便追踪自动更新的情况。如果发生错误，可通过日志排查问题。
	•	测试验证： 在生产环境中部署前，先在测试环境中进行验证。确保新的安全策略规则仅允许预期的流量通过，不会意外影响其他服务或造成安全风险。