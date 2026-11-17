# BYOC — Bring Your Own Container

> **TL;DR**: 在托管平台上**不**用平台自带的 runtime 镜像，**自己 build & push 一个容器**给平台跑。
> 适用范围：ML 训练/推理、应用部署、CI/CD runner、Edge compute。

---

## 1. 什么是 BYOC

托管平台（Vertex AI、Cloud Run、SageMaker、App Runner、GitHub Actions、Cloudflare Containers 等）通常提供两种使用方式：

| 模式 | 平台负责 | 你负责 |
|---|---|---|
| **Managed runtime** | 选 runtime、装依赖、跑代码 | 只上传代码 / notebook |
| **BYOC (Bring Your Own Container)** | 提供执行沙箱（CPU/网络/调度） | 提供完整可运行的容器镜像 |

BYOC 的核心 trade-off：**更多控制权 ⇄ 更多责任**。

---

## 2. 适用场景 ✅

- **自定义依赖**：CUDA 版本、私有 Python 包、内核模块、specific glibc
- **跨环境一致性**：本地、CI、生产用同一个 image，行为可复现
- **平台 runtime 不支持你的栈**：例如 SageMaker 默认 framework 不覆盖某个模型框架
- **重型冷启动可接受**：镜像 pull 几十秒不影响业务（批处理、夜间任务）
- **已有 Dockerfile 资产**：内部 golden image、shared base image 复用

---

## 3. 不适用场景 ❌

| 场景 | 理由 |
|---|---|
| 简单 HTTP API | 平台 managed runtime 更快上线、零 Dockerfile 维护 |
| 强依赖 cold-start latency | 镜像大 = 首次拉取慢；managed runtime 通常预热 |
| 团队没容器化经验 | 维护 Dockerfile + CI + Registry 的成本会超过收益 |
| 想要"无服务器"的免运维体验 | BYOC 把容器运维责任搬到了你身上 |

---

## 4. 平台一览

| 平台 | 典型用途 | 关键约束 |
|---|---|---|
| **Vertex AI Training** | 分布式训练 | 镜像必须能启动训练入口；多机时支持 gRPC 协调 |
| **Vertex AI Prediction** | 在线推理 | 必须监听 `AIP_HTTP_PORT`（默认 8080），实现 `/health` + `/predict` |
| **Cloud Run** | 容器化 HTTP 服务 | 必须监听 `$PORT`（平台注入），HTTP/1.1 或 HTTP/2 |
| **App Runner** | 容器化 Web 服务 | 类似 Cloud Run，更宽松但 AWS 生态 |
| **Cloud Run Jobs** | 批处理 | 任务跑完即退出，必须显式 exit 0/非 0 |
| **SageMaker** | ML 训练/推理 | 必须实现 `/ping`（健康）+ `/invocations`（推理） |
| **Azure ML** | ML 训练/推理 | 类似 SageMaker |
| **Databricks Container Services** | 集群初始化 | cluster 启动时跑 container，做环境配置 |
| **GitHub Actions** | CI runner | `container:` directive，job 在容器内执行 |
| **GitLab CI** | CI runner | `image:` directive |
| **Cloud Build** | 构建步骤 | 每个 step 一个镜像，按顺序执行 |
| **Cloudflare Containers** | Edge compute | 边缘节点拉镜像跑；注意延迟 + 镜像大小 |
| **AWS Lambda** | Serverless | 自定义 runtime 时用 container image（最大 10GB） |
| **Fly.io / Render / Railway** | App 部署 | Dockerfile-driven；类似托管 PaaS |

---

## 5. BYOC 生命周期

```mermaid
graph LR
  A[Source + Dockerfile] --> B[CI Build]
  B --> C[Image: myapp:v1.2.3]
  C --> D[Registry Push]
  D --> E[Platform 拉取镜像]
  E --> F[运行在托管沙箱]
  
  style A fill:#1a1a2e,stroke:#00d9ff
  style B fill:#1a1a2e,stroke:#00d9ff
  style C fill:#1a1a2e,stroke:#f9a826
  style D fill:#1a1a2e,stroke:#f9a826
  style E fill:#1a1a2e,stroke:#a855f7
  style F fill:#1a1a2e,stroke:#a855f7
```

> **关键决策点**：
> - **Build 一次 vs 多次**：build-once-promote-across-envs。CI 出 image → dev/staging/prod 都拉同一个 digest
> - **Tag 策略**：`v1.2.3` + `@sha256:...` 双标签，便于人读 + 机器校验
> - **Registry 选址**：同 region 减少拉取延迟；多 region 部署用 geo-replication

---

## 6. 文档结构

本目录下的详细文档：

- [`best-practices.md`](./best-practices.md) — 镜像设计、体积、安全、可观测、CI/CD 集成的工程实践
- [`platforms.md`](./platforms.md) — 各平台（Vertex AI / Cloud Run / SageMaker / ...）的 BYOC 特例和 gotcha
- [`dockerfile-templates.md`](./dockerfile-templates.md) — 经过验证的 Dockerfile 模板（Python / Node / Go / ML）

---

## 7. 核心 takeaway

> **BYOC 不是"用了就高级"，是用"换更可控 + 责任前移"换"灵活 + 跨环境一致 + 自定义栈"。**
> 当 managed runtime 满足需求时，**别** BYOC。当你确实需要，把"build 一次 + immutable digest + 健康检查 + 平台合约"这四条打齐。

---

## 相关

- 上级目录：[`../README.md`](../README.md) (Docker 知识库索引)
- 同级：[`../multistage-builds/`](../multistage-builds/) (多阶段构建模板)
- 通用概念：[`../../../concept/`](../../../concept/)
- GCP-specific：[`../../../gcp/vertex-ai/`](../../../gcp/) (Vertex AI 子目录)
