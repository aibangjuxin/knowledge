⸻

GCP mTLS Migration - Drop-in Session Notes | GCP mTLS 迁移简报

📌 Session Agenda | 会议议程
	•	Background | 背景介绍
	•	Migration Goals | 迁移目标
	•	Architecture Changes | 架构变更
	•	Next Steps & Q&A | 后续计划和问答环节

⸻

🔍 Background | 背景介绍

EN:
In our current environment, mutual TLS (mTLS) is implemented at the TCP layer for secure communication between clients and backend services. However, this architecture has limitations in terms of flexibility, certificate management, and compatibility with Google Cloud’s native security features. For example, with TCP-based mTLS, we are unable to apply more advanced Cloud Armor rules and controls.
翻译如下：
ZH:

在我们现有的环境中，客户端与后端服务之间采用基于 TCP 层的 mTLS 进行安全通信。然而，这种架构在灵活性、证书管理以及与 Google Cloud 原生安全特性的兼容性方面存在一定的限制。比如基于TCP我们无法做更多cloud Armor规则的控制

⸻

🎯 Migration Goals | 迁移目标

EN:
	•	Move from TCP-based mTLS to HTTPS-based mTLS.
	•	Use Google Cloud Load Balancer as a unified entry point.
	•	Simplify client certificate validation using TrustConfig.
    •	We will build a new component and name it imrp. Its main function is to validate CN.
	•	Enhance observability, scalability, and security.

ZH:
	•	将现有 TCP 层的 mTLS 迁移至 HTTPS 层的 mTLS。
	•	以 Google Cloud Load Balancer（GLB）作为统一入口。
	•	利用 TrustConfig 简化客户端证书的验证流程。
    •	我们将构建一个新的组件，命名为 imrp。其主要功能是验证 CN。
	•	提升可观测性、可扩展性及整体安全性。

⸻

🛠 Architecture Changes | 架构变更

EN:
The new architecture introduces the following changes:
	•	GLB terminates HTTPS + mTLS at the edge.
	•	Certificate Authority (CA) management is done via Certificate Manager’s TrustConfig.
	•	Multiple client CAs are supported.
	•	Cloud Armor policies enforce IP allowlist and additional security controls.
	•	Backend services (e.g. GKE/Nginx) no longer handle certificate validation directly.

ZH:
新的架构主要变更包括：
	•	在边缘由 Google Cloud Load Balancer 终止 HTTPS + mTLS 连接。
	•	使用 Certificate Manager 的 TrustConfig 管理 CA。
	•	支持多个客户端 CA。
	•	利用 Cloud Armor 实现 IP 白名单及其他安全策略。
	•	后端服务（如 GKE/Nginx）不再直接处理证书校验逻辑。

⸻

📈 Benefits | 收益

EN:
	•	Centralized mTLS enforcement
	•	Simplified onboarding of new clients
	•	Improved scalability and maintainability
	•	Stronger security posture with Google-native tools

ZH:
	•	实现集中式 mTLS 管控
	•	简化新客户端接入流程
	•	提升系统可扩展性和可维护性
	•	利用 Google 原生工具增强安全防护能力

⸻

📌 Next Steps | 后续步骤

EN:
	•	Continue onboarding teams to the new architecture
	•	Provide guides and automation for client certificate management
	•	Monitor and optimize based on feedback

ZH:
	•	持续协助各团队接入新架构
	•	提供证书管理的文档和自动化工具
	•	基于反馈持续优化架构方案

⸻

🙋 Q&A | 问答环节

Feel free to raise any questions or concerns.
欢迎大家提出问题或建议。

⸻

以下是一些 Q&A 环节中用户可能提出的问题，以及你作为主讲者可以使用的 中英文对照回答，方便你现场应答：

⸻

❓ Q1: 迁移后客户端需要做哪些改动？

EN: What changes are required on the client side after the migration?

答复 / Answer:
ZH: 客户端需要支持基于 HTTPS 的双向 TLS。我们会提供新的根证书以及示例配置，帮助团队完成接入。
EN: Clients need to support mutual TLS over HTTPS. We’ll provide the new root CA and sample configurations to help teams onboard smoothly.

⸻

❓ Q2: 新架构如何支持多个 CA？

EN: How does the new architecture support multiple Certificate Authorities (CAs)?

答复 / Answer:
ZH: 我们在 Certificate Manager 的 TrustConfig 中可以配置多个受信任的 CA，这样可以支持来自不同组织或团队签发的客户端证书。
EN: We can configure multiple trusted CAs in Certificate Manager’s TrustConfig, allowing support for client certificates issued by different organizations or teams.

⸻

❓ Q3: Cloud Armor 在新架构中是怎么用的？

EN: How is Cloud Armor used in the new setup?

答复 / Answer:
ZH: 在新的 HTTPS 架构下，Cloud Armor 可以应用在 URL、IP、Geo 等维度进行访问控制，这是之前基于 TCP 层做不到的。
EN: In the new HTTPS-based setup, Cloud Armor can be used to enforce access control based on URL, IP, and geo-location—something that was not possible in the TCP-based approach.

⸻

❓ Q4: 这次迁移会不会影响现有服务？

EN: Will this migration affect existing services?

答复 / Answer:
ZH: 现有服务会保持运行。我们采用的是渐进式迁移策略，确保每个客户端在完成验证和测试后再切换到新架构。
EN: Existing services will continue to run. We’re using a gradual migration strategy, ensuring that each client switches to the new architecture only after validation and testing.

⸻

❓ Q5: 如何验证客户端是否已正确接入新架构？

EN: How can clients verify that they’ve successfully connected to the new setup?

答复 / Answer:
ZH: 我们提供了专门的测试入口和日志反馈机制，您可以通过返回状态码和 header 验证是否已完成 mTLS 验证。
EN: We provide a dedicated test endpoint and logging mechanism. Clients can verify successful mTLS connection based on the response status code and headers.

⸻

❓ Q6: 如果我的客户端证书快过期了怎么办？

EN: What should I do if my client certificate is about to expire?

答复 / Answer:
ZH: 我们建议尽早更新证书。后续我们也会提供自动过期提醒或更新工具，减少人工操作。
EN: We recommend renewing your certificate in advance. We also plan to provide automated reminders or tools to simplify the renewal process.


客户端不需要做其他操作,我们会将目前环境中的Root证书和中间键证书导入到Trust Configs 
我们SRE团队将对证书的过期性进行监控.
Self Service的更新也在也在同步进行,我们会更新对应的pipeline提供用户自主更新证书

The client does not need to perform any other operations; we will import the Root certificate and intermediate key certificate from the current environment into Trust Configs.  
Our SRE team will monitor the expiration of the certificates.  
Updates to Self Service are also being carried out simultaneously, and we will update the corresponding pipeline to allow users to update certificates independently.


