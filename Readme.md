以下是基于您这一年的提问总结的工作环境信息以及常用的提示词描述，已整理为 Markdown 格式，方便您导出和使用：

```markdown
# 个人工作环境与常用提示词总结

## 个人工作环境信息
### 技术领域
- **操作系统**: Linux
- **主要技术栈**: GCP (Google Cloud Platform)、Kubernetes (K8S)、GKE、Kong Gateway
- **编程语言与工具**: 
  - JDK 17
  - BigQuery、Firestore、Google Buckets、Google Artifact Registry (GAR)
  - Harbor、Airflow、Cyberflows
  - GitHub 和 Jira (用于 Onboarding 流程)

### 网络架构
- **服务结构**: 
  - 流程: `Client > Nginx > Kong Gateway (GW) > Kong Runtime (RT) > 外部 API`
- **安全策略**:
  - 使用 Google Secret Manager 管理密钥
  - Google 内部 DNS 实施白名单机制
  - 定期刷新虚拟机实例的组件和主机
  - 使用 Cloud Armor 配置 External 和 Internal 服务的安全规则
  - 对 GAR 的高风险镜像进行扫描，限制其部署到生产环境

### 项目与目标
- **核心职责**: 
  - 构建并优化 API 平台
  - 通过 GKE 和 CICD Pipeline 完成自动化 Release 部署
  - 开发 API Quota 管理系统，基于 Firestore 实现
  - 提升 GKE Ingress 和 Gateway 的知识并优化平台
  - 在虚拟机与容器服务中提升性能、响应效率与安全性
- **优化目标**:
  - 强化 API 管理和资源分配
  - 优化 Pipeline 错误诊断流程
  - 利用 AI 集成提升用户体验和流程效率

---

## 常用的提示词和问题模式
### 网络与协议
- 如何诊断并解决特定网络错误（如特定域名并发请求失败）？
- Kubernetes 集群中如何配置和优化服务通信？
- TCP/HTTP 协议在特定场景下的性能优化方法？

### GCP/GKE
- 在 GKE 上如何安全部署 API？
- 如何在 GKE 中构建和管理多环境 Pipeline？
- GKE Ingress 和 Gateway 的具体配置和优化案例？

### 安全与资源管理
- 如何基于 Firestore 记录和管理 API 的 Quota？
- 如何对高风险镜像进行扫描并限制部署？
- 定期刷新虚拟机组件与主机的最佳实践？

### 流程与工具集成
- CICD Pipeline 报错分析与自动生成解决方法的最佳实践？
- 如何结合 Harbor 和 Airflow 实现自动化 Release 部署？
- 如何通过 Jira 和 GitHub 集成优化 Onboarding 流程？

### 技术学习与实践
- 关于 K8S Ingress 和 Gateway 配置，有哪些实用学习资源？
- 如何改进基于 GCP 平台的文档？

---

## 总结
这一年来，您主要关注于 **API 平台的优化、GCP/GKE 的应用与管理、CICD 流程的集成和安全管理**，同时在网络与协议调优方面也展现了丰富的兴趣。您提问的核心主题可以归纳为 **架构优化、安全保障、自动化流程、资源与配额管理**。

```

您可以直接复制此文档并使用。如果需要补充其他细节，请告诉我！