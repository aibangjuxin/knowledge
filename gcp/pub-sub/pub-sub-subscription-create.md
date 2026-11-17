# Pub/Sub Subscription 创建失败：`request is prohibited by organization's policy` 问题分析

## 一、问题分析

你遇到的错误是：

ERROR: Failed to create subscription: request is prohibited by organization’s policy

关键信息有两点：

1. **错误来自 Organization Policy（组织策略）**
2. **你“单独创建 subscription 没问题”，但用当前这条命令会失败**

这几乎可以确定：  
👉 **不是 Pub/Sub 本身权限问题，而是某个“特定配置项”触发了 Org Policy 限制**。

你的命令是：

```bash
gcloud pubsub subscriptions create sub-name \
  --topic=TOPIC_NAME \
  --ack-deadline=600 \
  --push-endpoint=https://domain/api/v1/alert \
  --push-auth-service-account=our-project@project.iam.gserviceaccount.com
```
其中 最容易触发组织策略的，只有 Push Subscription 相关配置。

⸻

二、最常见的几个 Org Policy 限制点（按命中概率排序）

1️⃣ 禁止创建 Push Subscription

最常见原因

很多组织会明确禁止使用 Push 模式（原因包括 SSRF、防止数据外送、Webhook 风险等）。

相关 Org Policy（逻辑层面）：
	•	禁止 pushConfig 类型的 subscription
	•	或只允许 pull subscription

为什么你“单独创建 subscription 没问题”？

因为你很可能测试的是：

gcloud pubsub subscriptions create sub-name --topic=TOPIC_NAME

➡️ 默认是 Pull Subscription
➡️ 没触发策略

而一旦加上：

--push-endpoint=...

就直接命中 Org Policy 🚫

⸻

2️⃣ 限制 Push Endpoint 必须是 特定域名 / 内部地址

很多组织会限制 Push Endpoint，例如：
	•	❌ 禁止公网域名
	•	❌ 禁止非 allowlist 域名
	•	✅ 只允许：
	•	*.run.app
	•	*.cloudfunctions.net
	•	内部 HTTPS LB
	•	指定公司域名

你的 endpoint 是：

https://domain/api/v1/alert

如果 domain：
	•	是公网域名
	•	或不在组织 allowlist 中

👉 会直接被 Org Policy 拦截

典型组织策略逻辑：

Only allow Pub/Sub push endpoints to approved domains

⸻

3️⃣ 禁止 Push Subscription 使用 Service Account OIDC

你使用了：

--push-auth-service-account=our-project@project.iam.gserviceaccount.com

这会触发 OIDC Token 注入 行为：
	•	Pub/Sub → 生成 OIDC token
	•	Audience = push endpoint
	•	使用指定 Service Account

很多组织会限制：
	•	❌ Pub/Sub 使用自定义 SA 进行 OIDC
	•	❌ 跨项目 SA
	•	❌ 非特定 SA

即使：
	•	SA 本身存在
	•	IAM 权限正确

Org Policy 仍然可以直接禁止这种行为

⸻

4️⃣ 跨 Project / 跨 Boundary 行为被禁止

常见隐性场景：

项目	内容
Project A	Pub/Sub Topic
Project B	Push Endpoint（LB / Cloud Run）
SA	位于 Project C

这种 跨 Project + Push + SA 的组合，非常容易被 Org Policy 拦。

即便你是 Org Admin，也可能被 Folder 级别策略 限制。

⸻

5️⃣ ack-deadline=600 本身 ❌（概率较低）

一般不会，但在极端安全组织里可能存在：
	•	限制最大 ack deadline
	•	防止消息长时间未 ack

但如果你 pull subscription + ack 600 没问题
那基本可以排除这个因素。

⸻

三、快速定位是哪一个参数触发的（推荐做法）

Step 1：逐步拆解命令（非常关键）

# 1. 纯 Pull（你已验证 OK）
gcloud pubsub subscriptions create sub-test \
  --topic=TOPIC_NAME

# 2. 加 push endpoint，不加 auth
gcloud pubsub subscriptions create sub-test \
  --topic=TOPIC_NAME \
  --push-endpoint=https://domain/api/v1/alert

# 3. 再加 push-auth-service-account
gcloud pubsub subscriptions create sub-test \
  --topic=TOPIC_NAME \
  --push-endpoint=https://domain/api/v1/alert \
  --push-auth-service-account=our-project@project.iam.gserviceaccount.com

❗ 哪一步开始失败，就是 Org Policy 的命中点。

⸻

四、如何确认具体是哪个 Org Policy？

方式一：查看 Audit Log（最靠谱）

让有权限的人查：
	•	Logs Explorer
	•	Resource: Pub/Sub Subscription
	•	Severity: ERROR
	•	查看 orgpolicy 或 constraints/*

通常会看到类似：

violates constraints/xxx.xxx

这条 constraint 名字就是答案。

⸻

方式二：列出项目继承的 Org Policy（只读）

gcloud org-policies list --project=PROJECT_ID

重点关注包含关键词的 constraint，例如：
	•	pubsub
	•	iam
	•	external
	•	domain
	•	serviceAccount

⸻

五、现实可落地的解决方案建议

✅ 方案 1：改用 Pull Subscription（最稳）

如果平台允许：
	•	用 Pull
	•	后端服务自己拉
	•	或通过 Dataflow / Cloud Run Job 转发

➡️ 100% 绕开 Push 相关 Org Policy

⸻

✅ 方案 2：Push 到 GCP 原生服务域名

例如：
	•	Cloud Run（*.run.app）
	•	Cloud Functions
	•	Internal HTTPS LB

通常这些在 allowlist 里。

⸻

✅ 方案 3：由平台统一创建 Push Subscription

在很多平台型组织中：
	•	用户 ❌ 不允许创建 Push Sub
	•	平台 ✅ 有专用项目 / SA / 域名

👉 你这个场景 非常符合“平台统一治理”的典型设计

⸻

六、一句话总结（给你拿去对外解释用）

这个错误不是权限问题，而是命中了组织级的安全策略。
单独创建 subscription 没问题，是因为那是 Pull 模式；
一旦使用 Push Endpoint / OIDC Service Account，就会被 Org Policy 禁止。

如果你愿意，我可以帮你模拟一份“平台侧标准 Pub/Sub Push 设计规范”，用来和安全 / Governance 团队对齐，直接可落地。