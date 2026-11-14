# Cloud Build

GCP 的托管式 CI/CD（serverless）。提交 `cloudbuild.yaml` → Cloud Build 在临时 Compute Engine VM 上逐步执行 Docker 容器 → 产出制品（容器镜像 / jar / npm 包 / 任意文件）→ 推到 Artifact Registry 或 GCS。

## 目录内容

| 文件 | 内容 |
| :--- | :--- |
| [`cloudbuild-guide.md`](cloudbuild-guide.md) | **主文档**：是什么 / 能产出什么 / 上手全流程 / API 与 IAM 清单 / Schema 速查 / CLI 速查 / 成本配额 / 安全 / 排错 |
| [**`how-to-github-trigger-cloud-build.md`**](how-to-github-trigger-cloud-build.md) | **GitHub → Cloud Build 端到端打通**：GitHub App 原理、1st gen / 2nd gen 两条路线选型、源码拉取链路、IAM 身份全景、产物落地（镜像 / JAR）、**GitHub 企业版场景（自建 GHE / 内网打通 / 自签 CA）**、加固清单、排错手册 |
| [**`how-to-autofix-cve-with-cloud-build.md`**](how-to-autofix-cve-with-cloud-build.md) | **CVE 自动修复闭环**：Cloud Build 在修复流水线里的角色、改 Dockerfile 的修补映射表、三种落地形态、报告怎么拿、差分判定、12 个 CVE 场景特有的坑 |
| [`gcp-cloud-build-concepts.md`](gcp-cloud-build-concepts.md) | 概念与生态全景（英文）：核心概念、GitHub 集成、Pipeline 集成选项、收益与最佳实践 |
| [`examples/`](examples/)) | 可直接改用的 `cloudbuild.yaml` 模板 |

## examples/

### 通用 CI/CD

| 文件 | 场景 |
| :--- | :--- |
| `docker-to-cloudrun.yaml` | Docker 镜像 → Artifact Registry → Cloud Run（最常见） |
| `nodejs-test-deploy.yaml` | npm ci / lint / test → 镜像 → 推送（多 step 依赖、allowFailure） |
| `java-maven.yaml` | Maven 构建 jar → 发布到 Artifact Registry Maven 仓库 |
| `golang-binary.yaml` | 编译 Go 静态二进制 → 打包 → 上传 GCS（非镜像类产物） |
| `terraform-plan-only.yaml` | Terraform **只 plan 不 apply**（IaC 安全基线） |
| `pubsub-trigger.yaml` | Pub/Sub 事件触发的构建 |

### CVE 自动修复（详见 [how-to-autofix-cve-with-cloud-build.md](how-to-autofix-cve-with-cloud-build.md)）

| 文件 | 场景 |
| :--- | :--- |
| `cve-verify-pipeline.yaml` | **形态 C**：构建 → 推送 → 扫 baseline → 扫 candidate → 差分 D1–D4 → 报告归档 → 退出码即门禁 |
| `cve-fix-base-image.yaml` | **T1/T1'**：换 base 镜像（含 distroless variant），修复 base OS EOL |
| `cve-fix-os-packages.yaml` | **T2'**：构建时升级 OS 包（次优方案，含三个陷阱说明） |
| `cve-fix-go-deps.yaml` | **T3/T4**：patch 依赖 → 构建 → 推送（含 `toolchain` vs `go` 的正确处理） |

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

## CVE 自动修复场景的三条硬规则

1. **规则 B（Verify-then-Promote）**：被验证的 digest 必须就是被部署的 digest。Cloud Build 构建一次 → 同一个 digest 被扫、被部署 → 结构上不可能违反。
2. **`--location` 是分析多区域**（`us`/`europe`/`asia`），**不是 GAR 仓库位置**。baseline 和 candidate 必须用同一个。
3. **Dockerfile 是可执行代码**：跑不可信 PR 的 Dockerfile 时，build SA 权限必须压到最低（只能写一个 staging 仓库）。
