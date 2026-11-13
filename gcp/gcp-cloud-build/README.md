# Cloud Build

GCP 的托管式 CI/CD（serverless）。提交 `cloudbuild.yaml` → Cloud Build 在临时 Compute Engine VM 上逐步执行 Docker 容器 → 产出制品（容器镜像 / jar / npm 包 / 任意文件）→ 推到 Artifact Registry 或 GCS。

## 目录内容

| 文件 | 内容 |
| :--- | :--- |
| [`cloudbuild-guide.md`](cloudbuild-guide.md) | **主文档**：是什么 / 能产出什么 / 上手全流程 / API 与 IAM 清单 / Schema 速查 / CLI 速查 / 成本配额 / 安全 / 排错 |
| [`gcp-cloud-build-concepts.md`](gcp-cloud-build-concepts.md) | 概念与生态全景（英文）：核心概念、GitHub 集成、Pipeline 集成选项、收益与最佳实践 |
| [`examples/`](examples/) | 可直接改用的 `cloudbuild.yaml` 模板 |

## examples/

| 文件 | 场景 |
| :--- | :--- |
| `docker-to-cloudrun.yaml` | Docker 镜像 → Artifact Registry → Cloud Run（最常见） |
| `nodejs-test-deploy.yaml` | npm ci / lint / test → 镜像 → 推送（多 step 依赖、allowFailure） |
| `java-maven.yaml` | Maven 构建 jar → 发布到 Artifact Registry Maven 仓库 |
| `golang-binary.yaml` | 编译 Go 静态二进制 → 打包 → 上传 GCS（非镜像类产物） |
| `terraform-plan-only.yaml` | Terraform **只 plan 不 apply**（IaC 安全基线） |
| `pubsub-trigger.yaml` | Pub/Sub 事件触发的构建 |

## 5 分钟速览

```bash
# 0) 选项目 + 启用 API（最小集）
gcloud config set project <PROJECT_ID>
gcloud services enable cloudbuild.googleapis.com compute.googleapis.com \
  artifactregistry.googleapis.com --project=<PROJECT_ID>

# 1) 写 cloudbuild.yaml（见 examples/）
cat > cloudbuild.yaml <<'EOF'
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/my-app/app:$COMMIT_SHA', '.']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/my-app/app:$COMMIT_SHA']
images:
  - 'asia-northeast1-docker.pkg.dev/$PROJECT_ID/my-app/app:$COMMIT_SHA'
EOF

# 2) 手动跑一次
gcloud builds submit --config cloudbuild.yaml --region=asia-northeast1

# 3) 看日志
gcloud builds log <BUILD_ID> --region=asia-northeast1

# 4) 自动化：建 trigger
gcloud builds triggers create github \
  --name=my-app-build --region=asia-northeast1 \
  --repo-owner=<OWNER> --repo-name=<REPO> \
  --branch-pattern='^main$' --build-config=cloudbuild.yaml
```

## 关键事实速记

- **API 最小集**：`cloudbuild` + `compute` + `artifactregistry`（+ `storage`）。部署再加 `run` / `container` / `clouddeploy`。
- **两个系统身份**：默认构建 SA `{PROJECT_NUMBER}@system.gserviceaccount.com`（别用）、服务代理 `service-{PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com`。
- **region 创建后不可改**（trigger / build 都一样）。
- **substitution 只能覆盖已存在的 key**，不能运行时新增。
- **产物必须写进 `images:`** 才会被自动推送。
- **成本**：每个 billing account 每月 2,500 免费 build-minute（仅 `e2-standard-2`）；`e2-standard-2` $0.006/分钟，排队不计费，出流量另计。
- **配额**：Default Pool 并发构建 10（可调至 30）；单构建最多 300 个 step。
- **安全**：专用 SA + 生产触发器开 `--require-approval` + 敏感值走 Secret Manager + 部署用 digest 而非 tag。
