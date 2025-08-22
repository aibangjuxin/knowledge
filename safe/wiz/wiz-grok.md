Wiz 是一个云原生应用保护平台 (CNAPP)，专注于云安全扫描和风险管理。它通过 agentless（无代理）方法扫描云环境（如 AWS、Azure、GCP），帮助识别漏洞、配置错误、秘密泄露、恶意软件等风险。公司采购 Wiz 后，可以快速集成到 GCP 环境中，包括 GKE（Google Kubernetes Engine）和 deployment 中的容器。Wiz 的核心优势是无需安装代理即可提供全面可见性，同时支持运行时保护。以下是基于官方文档和相关资源的总结，我会逐步解释基本的知识、部署过程、具体功能区别，以及 API 和 pipeline 集成。

### 基本的知识
Wiz 通过 API 连接到云提供商，构建一个“安全图”（Security Graph），将云资源（如 VM、容器、数据库）、身份、漏洞和配置关联起来，帮助优先级排序风险。它支持多云环境，特别适合 GCP，包括 Compute Engine、Cloud Storage、Cloud SQL 和 GKE。Wiz 的扫描是 agentless 的，意味着无需在每个资源上安装软件，只需授予 Wiz 读取权限即可扫描。 在 GKE 和 deployment container 中，Wiz 可以扫描容器镜像、运行时行为，并集成到 CI/CD 流程中，确保从开发到生产的安全。

### 在 GCP 和 GKE 中的应用与使用
1. **连接 GCP 环境**：
   - 在 Wiz 控制台中，添加 GCP 项目：提供服务账户密钥或使用 OAuth 授权 Wiz 访问 GCP API（如 Compute、Storage、GKE）。
   - 这会自动扫描整个 GCP 环境，包括 GKE 集群的节点、pod 和 deployment。

2. **针对 GKE 和 deployment container**：
   - **Agentless 扫描**：直接扫描 GKE 集群的镜像、配置和元数据，无需修改 deployment。Wiz 会检查容器中的 OS 包、应用依赖、秘密（如 API 密钥），并识别暴露的风险（如公开端口）。
   - **Runtime Sensor**：如果你需要运行时保护，需要在 GKE 集群中部署 Wiz 的轻量级传感器（基于 eBPF）。这会监控容器内的进程、网络流量和文件访问。
   - 在 deployment 中应用：Wiz 可以与你的 YAML 文件集成，确保容器在部署前扫描；运行时传感器可以作为 sidecar 或 daemon set 添加到 pod 中。

Wiz 支持 GCP 的原生工具集成，如与 Google Cloud Security Command Center 结合，提供统一视图。

### 部署过程示例
部署 Wiz 相对简单，通常在几分钟内完成。以下是大概流程，聚焦于 agentless 扫描和 runtime sensor 的自动执行。

1. **Agentless 扫描的部署和自动执行**：
   - **步骤**：
     - 在 Wiz 门户创建账户并连接 GCP（输入项目 ID 和凭证）。
     - Wiz 会自动通过 GCP API 扫描资源：每隔几小时（可配置）运行扫描，收集库存、配置和漏洞数据。
     - 无需手动干预；扫描是周期性的，支持 webhook 通知警报。
   - **在 GKE 中的应用**：扫描会覆盖 GKE 集群的镜像仓库（如 Artifact Registry），检查 deployment 中的容器镜像。无需代理，所以对性能影响最小。

2. **Runtime Sensor 的部署和自动执行**：
   - **步骤**：
     - 使用 Helm chart 部署：运行 `helm install wiz-sensor wiz/sensor --set admission.enabled=true` 在 GKE 集群中安装 daemon set。
     - 配置 webhook 以自动注入传感器到新 pod。
     - 传感器会实时监控运行时事件（如进程启动、网络连接），并将数据发送回 Wiz 云平台。
   - **自动执行**：一旦部署，传感器会持续运行，支持自动响应（如隔离恶意容器）。在 deployment 中，你可以添加注解（如 `wiz.io/inject-sensor: true`）来启用。

整个过程 agentless 部分无需重启资源；runtime sensor 部署后，重启 pod 即可生效。

### 无代理扫描能拿到哪些信息
Agentless 扫描通过云 API 和快照方式收集数据，主要聚焦静态分析。典型信息包括：
- **漏洞和软件包**：OS 层、应用依赖（如 Python/Ruby 包）的 CVE 漏洞。
- **配置和合规**：资源配置（如 IAM 角色、网络 ACL）、误配置（如公开存储桶）。
- **敏感数据**：秘密、API 密钥、证书；在 GCP 中，包括 Cloud Storage 中的数据元数据、Cloud SQL 表。
- **库存和身份**：所有资源列表（如 VM、pod）、用户/服务账户权限。
- **恶意软件**：扫描镜像中的已知恶意文件。
- **其他**：网络暴露、合规检查（如 CIS 基准）。

扫描覆盖 100% 资源，无盲点，但不包括实时进程数据。

### 无代理扫描和 Runtime Sensor 的具体区别
Wiz 采用混合方法：agentless 为基础，runtime sensor 为增强。以下是比较表格：

| 方面          | 无代理扫描 (Agentless) | Runtime Sensor (Agent-based) |
|---------------|-------------------------|------------------------------|
| **部署方式** | 无需安装代理，通过 API 连接云提供商 | 需要部署轻量级 eBPF 传感器到主机/容器 |
| **覆盖范围** | 静态资源：镜像、配置、库存、漏洞、秘密 | 动态行为：进程、网络流量、文件访问、运行时威胁 |
| **性能影响** | 最小（无驻留软件） | 低（轻量级），但需资源分配 |
| **优势**     | 简单、可扩展、快速部署、全覆盖无盲点 | 实时检测和响应（如终止恶意进程） |
| **局限**     | 无实时监控，只能周期性扫描 | 需要管理传感器，潜在兼容性问题 |
| **用例**     | 初始可见性和风险评估 | 生产环境威胁检测和阻断 |
| **GKE 示例** | 扫描 deployment 镜像的漏洞 | 监控 pod 内网络连接，检测入侵 |

总体上，agentless 更适合入门和大规模环境，而 runtime sensor 提供深度保护。许多团队从 agentless 开始，然后添加 sensor。

### API 调用和基于 Pipeline 的工作
是的，Wiz 提供 API 和 CLI 支持直接调用执行扫描，并集成到 CI/CD pipeline 中。

- **API 调用**：Wiz 的 GraphQL API 允许查询库存、触发扫描、获取报告。例如，使用 API 扫描特定容器镜像或 GCP 资源。你可以从 Wiz 门户生成 API 密钥，然后用 curl 或 SDK 调用（如 `POST /graphql` 查询漏洞）。支持自动化脚本执行扫描。

- **Pipeline 集成**：
  - Wiz 支持 GitHub Actions、Jenkins、CircleCI 等 pipeline。
  - **示例工作**：在 CI/CD 中添加 Wiz 步骤，扫描 IaC（Terraform/YAML）、代码仓库或容器镜像。如果扫描失败，可阻塞部署。
  - 使用 Wiz CLI：如 `wiz scan --image your-container-image` 在 pipeline 中运行。
  - 在 GKE deployment pipeline 中：集成到 Google Cloud Build，扫描镜像后推送到 GKE。
  - 好处：实现 shift-left 安全，早发现风险；支持与 Harness 或 Buildkite 的模板集成。

如果需要更详细的代码示例或特定配置，建议查看 Wiz 官方文档（wiz.io/docs）或联系支持团队。