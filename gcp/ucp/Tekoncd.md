# Tekton（tektoncd）是什么

> 一句话结论：**Tekton 是一个云原生开源的 CI/CD 框架，把 GitOps 风格的"流水线"以 Kubernetes 原生 CRD 的形式跑在任意云（AWS/GCP/Azure）或本地集群上，用 YAML 声明代替 Jenkins/GitLab CI 那类脚本式流水线。**

## 核心组成

| 组件 | 作用 |
|---|---|
| **Tekton Pipelines** | 核心。用 `Task` / `Pipeline` / `TaskRun` / `PipelineRun` 等 CRD 声明构建、测试、部署步骤，替代脚本化的 job 定义。 |
| **Tekton Chains** | 为产物（镜像、制品）生成签名、SBOM 与 provenance（来源证明）。 |
| **Tekton Results** | 把 TaskRun 的日志/结果写入集中存储，便于查询与 UI 展示。 |
| **Tekton CLI (`tkn`)** | 命令行工具：创建/查看 Pipeline、管理触发等。 |
| **Tekton Hub / Catalog** | 社区共享的 Task 目录（类似 CI 的 action marketplace）。 |
| **Tekton Triggers** | 由 Git webhook 等事件触发 Pipeline。 |

## 特点 / 定位

- 属于 **CNCF 孵化项目**，与 Argo CD 属同门（Argo CD 管"部署"，Tekton 管"构建+部署流水线"）。
- **Kubernetes 原生**：本身以 Operator / CRD 形式安装，所有流水线都是集群里的 Pod，能天然复用 K8s 的权限、伸缩、密钥管理。
- **云厂商中立**：不绑定任何云，也可在本地集群（kind / k3d）跑，适合自建 CI 平台或做"内部 CI 底座"。
- 代价：需要 K8s 集群和一定的学习成本（YAML 冗长）；常与 Argo CD、Flux 等 GitOps 工具组合使用。

## 典型场景

自建 CI 平台（如企业内部统一流水线）、把单体 Jenkins/GitLab CI 迁到 K8s 上、多云环境下用同一套流水线定义、以及需要为产物做供应链安全（签名/SBOM）的团队。

## 与相近方案对比

- **Jenkins / GitLab CI**：以脚本/Job 配置为中心；Tekton 以 K8s 资源声明为中心。
- **GitHub Actions / GitLab CI**：SaaS 或平台绑定；Tekton 自托管、云中立。
- **Argo Workflows**：更偏通用 DAG 工作流编排；Tekton 专注 CI/CD 场景，生态与 Triggers/Hub 更完善。
- **Argo CD**：只做 GitOps 持续部署，不做构建流水线，通常与 Tekton 搭配使用。
