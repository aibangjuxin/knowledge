# Vertex AI — BYOC 模式

> **TL;DR**: Vertex AI 支持你**自带容器**跑训练、推理、Pipeline 组件、Batch Prediction。本目录是端到端实战指南。
>
> 通用 BYOC 概念（Dockerfile 模板、镜像设计、CI/CD 通用模式）见 [`../../cloud/docker/byoc/`](../../cloud/docker/byoc/)。**本目录专注 Vertex AI 平台的特殊合约和集成。**

---

## 1. 为什么 Vertex AI + BYOC

Vertex AI 提供三类使用方式：

| 模式 | 适用 | 你的工作量 |
|---|---|---|
| **AutoML** | 表格/图像/文本的标准化训练 | 零代码 |
| **Pre-built container** | 主流框架（PyTorch/TF/scikit-learn）跑训练和推理 | 写训练脚本 + 调 gcloud |
| **Custom container (BYOC)** | 自定义 CUDA/框架/预处理/业务逻辑 | 写 Dockerfile + 训练脚本 + 部署 YAML |

**用 BYOC 的理由**：
- 框架版本不匹配 Vertex AI prebuilt（私有 PyTorch fork、特定 CUDA）
- 业务预处理不在 prebuilt 容器内能跑（PDF parsing、专有 codec）
- 需要 Vertex AI 编排 + 自家推理代码
- 需要严格的依赖锁定（生产一致性）

**别用 BYOC 的理由**：
- 标准 PyTorch 训练 + 推理 → prebuilt 容器 + 自定义代码就够
- 一次性实验 → 笔记本跑就行
- 团队没有 Docker 经验 → 维护成本超过收益

---

## 2. Vertex AI 支持 BYOC 的服务

| 服务 | BYOC 用途 | 入口环境变量 |
|---|---|---|
| **Custom Training Job** | 自定义训练容器 | `AIP_TRAINING_DATA_URI`, `AIP_MODEL_DIR`, `AIP_CHECKPOINT_DIR`, `TF_CONFIG` |
| **Custom Prediction** | 自定义推理容器 | `AIP_HTTP_PORT`, `AIP_HEALTH_ROUTE`, `AIP_PREDICT_ROUTE`, `AIP_STORAGE_URI`, `AIP_MODEL_DIR` |
| **Custom Job (batch)** | 一次性批处理 | (无 AIP_*，自由定义) |
| **Vertex AI Pipelines** | KFP 组件作为容器 | 输入通过命令行参数或 `kfp.dsl` 注入 |
| **Ray on Vertex AI** | Ray cluster 节点 | 自定义 ray image |
| **Vector Search** | 自定义 embedding 容器 | 输入/输出 JSON |

> 本目录重点覆盖 **Custom Training** 和 **Custom Prediction**（90% 实际场景），其他服务按需扩展。

---

## 3. 决策树

```
任务类型？
  │
  ├── 训练 (一次性或周期性)
  │   ├── 单机、prebuilt 框架 → 用 prebuilt container（不 BYOC）
  │   ├── 单机、自定义依赖 → Custom Training BYOC，见 byoc-training.md
  │   ├── 多机分布式 → Custom Training + 多 worker pool，见 byoc-training.md §3
  │   └── 超参搜索 → Custom Training + HyperparameterTuningJob
  │
  ├── 在线推理
  │   ├── 简单 PyTorch/TF → prebuilt prediction container
  │   ├── 自定义预处理 / 业务逻辑 → Custom Prediction BYOC，见 byoc-prediction.md
  │   └── 高 QPS + GPU → Custom Prediction + GPU 类型
  │
  ├── 批处理推理
  │   └── Custom Job (BYOC) + batch 输入 GCS
  │
  └── ML Pipeline
      └── KFP v2 + 自定义组件 = BYOC container，见 byoc-iam-cicd.md §4
```

---

## 4. 通用架构

```
[Dev 端]
  Source Code + Dockerfile
        ↓
  Cloud Build (或 GitHub Actions)
        ↓
  Artifact Registry: us-docker.pkg.dev/PROJECT/REPO/image:tag
        ↓
[Vertex AI 端]
  Custom Training Job (BYOC)        Custom Prediction (BYOC)
        ↓                                   ↑
  GCS: gs://BUCKET/training-data/    GCS: gs://BUCKET/model/
        ↓                                   ↓
  GCS: gs://BUCKET/model-output/     Endpoint (HTTPS)
                                            ↓
                                       Client Request
```

**Region 一致性原则**：
- Cloud Build build 的 image 推到 **同 region** 的 Artifact Registry
- Custom Job / Endpoint 部署在 **同 region**（避免跨 region 拉镜像延迟）
- GCS bucket 在 **同 region**（数据本地性）

---

## 5. 文档索引

| 文件 | 内容 |
|---|---|
| [`byoc-training.md`](./byoc-training.md) | Custom Training 端到端：单/多机、checkpoint、HPT、Dockerfile、gcloud CLI |
| [`byoc-prediction.md`](./byoc-prediction.md) | Custom Prediction 端到端：FastAPI、模型加载、autoscaling、A/B、gcloud CLI |
| [`byoc-iam-cicd.md`](./byoc-iam-cicd.md) | IAM / Workload Identity / VPC-SC + Cloud Build pipeline + 常见 gotcha |

---

## 6. 关键 takeaway

> **Vertex AI BYOC 的核心 trade-off**：你拿到平台编排能力（job 调度、endpoint autoscaling、A/B、监控）+ 自己负责所有运行时细节。
>
> **不要**把整个项目都 BYOC——只在 **prebuilt 容器不满足的边界** 上做。prebuilt 能跑就 prebuilt，**省 Dockerfile 维护成本**。

---

## 相关

- 上级：[`../README.md`](../README.md)
- 通用 BYOC：[`../../cloud/docker/byoc/`](../../cloud/docker/byoc/)
- Artifact Registry：GCP 容器镜像管理
- Workload Identity：GKE 里的 SA 联邦模式（参考 `../gke/`）
