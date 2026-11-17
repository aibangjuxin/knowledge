# Cloud Build 实操指南（GCP）

> **TL;DR**
>
> Cloud Build 是 GCP 的**托管式 CI/CD**（serverless）：你交一份 `cloudbuild.yaml`，它拉代码 → 在 Docker 容器里跑一串 build step → 产出制品（容器镜像 / Java 包 / npm 包 / Go module / 任意文件）→ 推到 Artifact Registry 或 GCS。
>
> - **最小可用路径**：启 `cloudbuild.googleapis.com` → 写 `cloudbuild.yaml` → `gcloud builds submit --config cloudbuild.yaml` → 看日志。
> - **产物最常见**：容器镜像（推 Artifact Registry），其次是 jar/war、npm/pypi 包、Go module、静态文件。
> - **API 只多不少**：除了 `cloudbuild.googleapis.com`，实际还会需要 `compute`（构建跑在 Compute Engine VM 上）、`artifactregistry`（存镜像）、以及你**部署目标**对应的 `run` / `container` / `clouddeploy`。
> - **两个坑**：`--region` 对 trigger **创建后不可改**；substitution **只能覆盖已存在的 key**，不能新增。

---

## 目录

1. [Cloud Build 是什么](#1-cloud-build-是什么)
2. [一次 Build 的完整生命周期](#2-一次-build-的完整生命周期)
3. [它能 Build 出什么](#3-它能-build-出什么)
4. [触发方式：6 种 Trigger](#4-触发方式6-种-trigger)
5. [上手全流程（Step 0 → Step 7）](#5-上手全流程step-0--step-7)
6. [API 启用清单](#6-api-启用清单)
7. [IAM 角色清单](#7-iam-角色清单)
8. [cloudbuild.yaml Schema 速查](#8-cloudbuildyaml-schema-速查)
9. [CLI 命令速查](#9-cli-命令速查)
10. [成本与配额](#10-成本与配额)
11. [安全最佳实践](#11-安全最佳实践)
12. [常见坑与排错](#12-常见坑与排错)
13. [与相邻产品的分工](#13-与相邻产品的分工)

---

## 1. Cloud Build 是什么

一句话：**Google Cloud 托管的 CI/CD 执行引擎**。

官方定义：*"Cloud Build is a service that executes your builds on Google Cloud. It can import source code from Cloud Storage, GitLab, GitHub, or Bitbucket, execute a build to your specifications, and produce artifacts such as Docker containers or Java archives."*

### 心智模型：5 个核心对象

| 对象 | 是什么 | 你要写什么 |
| :--- | :--- | :--- |
| **Build** | 一次构建执行。有唯一 Build ID，有状态（`QUEUED`/`WORKING`/`SUCCESS`/`FAILURE`/`CANCELLED`） | — |
| **Step** | 构建的最小单元。**每个 step 是一个独立的 Docker 容器**（`docker run` 语义），共享 `/workspace` 挂载 | `name`（builder 镜像）、`args`、`env`、`script` |
| **Builder** | step 使用的镜像。分三类：官方内置、社区贡献、自定义 | `name: gcr.io/cloud-builders/docker` |
| **Trigger** | 触发规则。把「事件」映射到「一次 build」 | 事件类型 + 仓库 + build config 路径 |
| **Pool** | 构建 worker 池。Default Pool（默认，有公网出口）或 Private Pool（可访问 VPC） | `options.pool` |

### 关键特性

- **每个 step 一个容器**：step 之间靠 `/workspace` 目录交换文件，靠名为 `cloudbuild` 的本地 Docker 网络互相通信。
- **每次构建都是全新的临时环境**：Cloud Build 为每次 build 拉起一台新 VM，构建结束即销毁（ephemeral）。→ 保证「干净构建」，杜绝上次构建残留文件污染。
- **Build 的 VM 跑在 Compute Engine 上**，所以 `compute.googleapis.com` 是隐式依赖。
- **默认有公网出口**（Default Pool）。要访问内网资源（私有 Git、內部 registry、数据库）必须用 **Private Pool**。
- **SLSA Level 3 支持**：Cloud Build 可为容器镜像生成 build provenance（构建来源证明），配合 Binary Authorization 做供应链管控。
- **CMEK by default**：构建时的临时磁盘用**每次构建独立生成的临时密钥**加密，密钥用完即毁。

---

## 2. 一次 Build 的完整生命周期

```
① 准备源码 + 构建配置
       │
       ▼
② 写 cloudbuild.yaml（YAML/JSON）
       │
       ▼
③ 提交构建
   ├─ 手动：gcloud builds submit
   ├─ 触发器：push / PR / tag / PubSub / Webhook
   └─ API：POST projects/{p}/builds
       │
       ▼
④ Cloud Build 执行
   ├─ 源码拉取（从 Git / GCS / CSR）
   │    └─ 中转：gs://{PROJECT_ID}_cloudbuild/source
   ├─ 拉起构建 worker（Compute Engine VM，临时）
   ├─ 逐步执行 steps（每步一个容器）
   ├─ 产物输出
   │    ├─ images[]      → Artifact Registry / GCR
   │    └─ artifacts{}   → GCS 路径
   └─ 日志
        ├─ Cloud Logging（默认）
        └─ gs://{PROJECT_NUMBER}.cloudbuild-logs.googleusercontent.com/
       │
       ▼
⑤ 结果
   ├─ 状态：SUCCESS / FAILURE
   ├─ Build History 页面 / gcloud builds log
   └─ 触发器可再链下一环（如 Pub/Sub 通知 → Cloud Deploy）
```

### 源码中转站（容易忽略的一点）

Cloud Build 不是直接从 Git 拉代码跑在构建机上，而是：
**Git → GCS（staging）→ 构建 worker 解压到 `/workspace`**。

所以你会看到 `gs://{PROJECT_ID}_cloudbuild/source` 这个桶。副作用是：**构建默认有 GCS 读写权限**，且源码在 GCS 里留有副本。

---

## 3. 它能 Build 出什么

`cloudbuild.yaml` 的 schema 里有 5 类产物字段：

| 字段 | 产物 | 落地位置 |
| :--- | :--- | :--- |
| `images[]` | **容器镜像** | Artifact Registry (`*.pkg.dev`) 或 GCR (`gcr.io`) |
| `artifacts.objects` | **任意文件**（二进制、tar.gz、报告） | GCS 路径 `gs://bucket/path` |
| `mavenArtifacts[]` | **Java 包**（jar/war/aar） | Maven 仓库（Artifact Registry Maven 仓库） |
| `pythonPackages[]` | **Python 包**（wheel/sdist） | PyPI 仓库（Artifact Registry） |
| `npmPackages[]` | **npm 包** | npm 仓库（Artifact Registry） |
| `goModules[]` | **Go module** | Go module proxy / GCS |

> 官方 overview 文档的表述是 *"produce artifacts such as Docker containers or Java archives"*，但实际能力远不止——`images` / `artifacts` / `mavenArtifacts` / `pythonPackages` / `npmPackages` / `goModules` 六类都有。

### 更重要的：它能「做什么」而不只是「产出什么」

Cloud Build 本质是「在 GCP 上执行任意容器命令」的编排器，所以常见用法远超打包：

| 场景 | 怎么实现 |
| :--- | :--- |
| 跑单元测试 / 覆盖率 | step 跑 `npm test` / `mvn test` / `go test ./...` |
| 静态检查 | eslint / golangci-lint / spotbugs / `gcloud beta container images scan` |
| 漏洞扫描 | Artifact Analysis（`gcr.io/cloud-builders/gcloud` 的 `container images scan`） |
| 构建容器镜像 | `gcr.io/cloud-builders/docker` 的 `build` + `push` |
| 部署到 Cloud Run | `gcloud run deploy` step |
| 部署到 GKE | `gcr.io/cloud-builders/gke-deploy` 或 `kubectl apply` |
| 部署到 GCE | `gcloud compute instances create/update` |
| 部署到 Firebase / Cloud Functions | `gcloud functions deploy` / `firebase deploy` |
| 基础设施即代码 | `terraform plan` / `terraform apply`（**注意**：见 §12 的坑） |
| 创建发布 PR | `gcloud builds triggers run` + GitHub API |
| 制品归档 | `gsutil cp` 到 GCS |

### 内置 Builder 镜像

官方维护，路径前缀 `gcr.io/cloud-builders/`：

| Builder | 用途 |
| :--- | :--- |
| `gcr.io/cloud-builders/docker` | `docker build` / `docker push` |
| `gcr.io/cloud-builders/gcloud` | 跑 `gcloud` 命令 |
| `gcr.io/google.com/cloudsdktool/cloud-sdk` | 新版 Cloud SDK（官方新文档推荐，配合 `entrypoint: gcloud`） |
| `gcr.io/cloud-builders/git` | git 操作 |
| `gcr.io/cloud-builders/mvn` | Maven 构建 |
| `gcr.io/cloud-builders/gradle` | Gradle 构建 |
| `gcr.io/cloud-builders/bazel` | Bazel 构建 |
| `gcr.io/cloud-builders/gke-deploy` | 部署到 GKE |
| `gcr.io/cloud-builders/gsutil` | GCS 操作 |
| `gcr.io/cloud-builders/curl` | HTTP 请求 |
| `gcr.io/cloud-builders/npm` / `node` / `python` / `go` | 各语言工具链 |
| `gcr.io/cloud-builders/docker-compose` | 社区：跑 compose 集成测试 |

社区贡献（`cloud-builders-community`，**需先自己 build 并推到 Artifact Registry**）：
`docker-compose` / `helm` / `pack`（Cloud Native Buildpacks） / `packer`（做 VM 镜像） / `harness-chaos` / `remote-builder`。

自定义 builder：任何镜像都行。约定是源码挂在 `/workspace`，工作目录也是 `/workspace`。

---

## 4. 触发方式：6 种 Trigger

`gcloud builds triggers create <TYPE>` 支持的类型（gcloud 526.0.1 实测）：

| 类型 | 子命令 | 说明 |
| :--- | :--- | :--- |
| GitHub | `github` | 支持 1st gen（`--repo-name/--repo-owner`）与 2nd gen（`--repository`） |
| GitLab | `gitlab` | 仅 2nd gen（`--repository`） |
| Bitbucket Cloud | `bitbucket-cloud` | 2nd gen |
| Bitbucket Data Center | `bitbucket-data-center` | 2nd gen |
| Bitbucket Server | `bitbucketserver` | |
| Cloud Source Repositories | `cloud-source-repositories` | Google 自家 Git |
| 手动 | `manual` | 只靠 `gcloud builds triggers run` 触发 |
| Pub/Sub | `pubsub` | 消息事件；支持 `--subscription-filter`（CEL） |
| Webhook | `webhook` | 外部 HTTP POST；需 Secret Manager 里的 secret |

事件类型（同一 trigger 上）：**push 到分支** / **push tag** / **Pull Request**（可配 `--comment-control` 要求 owner 敲 `/gcbrun`）/ **手动** / **PubSub** / **Webhook**。

### 1st gen vs 2nd gen（选型要点）

| | 1st gen | 2nd gen |
| :--- | :--- | :--- |
| 连接方式 | Cloud Build GitHub App（控制台点选） | **Developer Connect**（`gcloud builds connections` + `gcloud builds repositories`） |
| 触发器 region | 支持 `global` | **必须指定具体 region**（`global` 不支持） |
| 需要的 API | 仅 `cloudbuild` | 额外需要 `developerconnect.googleapis.com` |
| 适用 | 快速上手、GitHub.com | 企业规范、需要与 Cloud Run/ADC 共享同一连接 |

> **建议**：新项目直接上 2nd gen（Developer Connect），因为 1st gen 的 GitHub App 是 Google 个人账号体系，企业治理上不推荐。但 2nd gen 必须先定 region（**不可改**）。

---

## 5. 上手全流程（Step 0 → Step 7）

### Step 0：前置检查

```bash
# gcloud 版本
gcloud version

# 认证
gcloud auth login
gcloud auth application-default login

# 选项目
gcloud config set project <PROJECT_ID>
```

**前置条件**：
- 项目必须**已开通结算（billing）**，否则 build 会直接失败。
- 你需要有 `serviceusage.services.enable` 权限（Owner 或 `roles/serviceusage.serviceUsageAdmin`）。

### Step 1：确认 Cloud Build 是否已启用

三种确认方式（任选其一）：

```bash
# ① 看 API 列表里有没有 cloudbuild
gcloud services list --enabled --project=<PROJECT_ID> \
  --format="value(config.name)" | grep -E 'cloudbuild|artifactregistry'

# ② 直接问 Cloud Build（最准）
gcloud builds list --project=<PROJECT_ID> --limit=5
#   正常 → 空列表
#   报 INVALID_ARGUMENT / SERVICE_DISABLED → API 没开
#   报 PERMISSION_DENIED / USER_PROJECT_DENIED → 权限不够，不是没开

# ③ 控制台：Cloud Build → History，能打开且不弹「Enable API」即为已启用
```

> **注意**：控制台左侧导航**总是**能看到 Cloud Build 入口（未启用时点进去会提示启用）。**「菜单里有」≠「API 已启用」**，务必用上面 ① / ② 验证。

### Step 2：启用 API（按需，见 §6 完整清单）

```bash
# 最小集：构建 + 产物存储
gcloud services enable \
  cloudbuild.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com

# 如果还要部署
gcloud services enable run.googleapis.com          # Cloud Run
gcloud services enable container.googleapis.com     # GKE
gcloud services enable clouddeploy.googleapis.com   # Cloud Deploy
```

### Step 3：建 Artifact Registry 仓库（存镜像用）

```bash
gcloud artifacts repositories create my-app \
  --repository-format=docker \
  --location=asia-northeast1 \
  --description="my-app images"

gcloud artifacts repositories list --location=asia-northeast1
```

### Step 4：建专用 Service Account（强烈建议，不要用默认 SA）

```bash
# 建 SA
gcloud iam service-accounts create gcb-builder \
  --display-name="Cloud Build Builder"

# 绑角色（最小权限）
PROJECT_ID=<PROJECT_ID>
SA=gcb-builder@${PROJECT_ID}.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA}" \
  --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA}" \
  --role="roles/storage.objectUser"          # 源码 staging / 日志桶
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA}" \
  --role="roles/storage.bucketViewer"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA}" \
  --role="roles/artifactregistry.writer"      # 推镜像
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA}" \
  --role="roles/cloudbuild.builds.editor"     # 允许它自己触发后续构建

# 需要部署时再加
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA}" --role="roles/run.admin"
```

> 用 Cloud Build 时，需要 `iam.serviceAccounts.actAs` 才能以该 SA 身份运行 build。
> 人（你的账号）也要有这个权限，才能 `--service-account` 指定它：
> `gcloud iam service-accounts add-iam-policy-binding ${SA} --member="user:<你的邮箱>" --role="roles/iam.serviceAccountUser"`

### Step 5：写 `cloudbuild.yaml`

最常见的三种模板见 [`examples/`](examples/) 目录。

```yaml
steps:
  # 1) 跑测试
  - name: 'node:20'
    dir: app/
    script: |
      npm ci
      npm test

  # 2) 构建镜像
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'build'
      - '-t'
      - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:$COMMIT_SHA'
      - '-t'
      - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:latest'
      - '.'

  # 3) 推送（tag 用 $COMMIT_SHA 保证可追溯）
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'push'
      - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:$COMMIT_SHA'
      - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:latest'

  # 4) 部署到 Cloud Run（只在 main 分支）
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: gcloud
    args:
      - 'run'
      - 'deploy'
      - '${_SERVICE}'
      - '--image=${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:$COMMIT_SHA'
      - '--region=${_REGION}'
      - '--platform=managed'
    condition: '$BRANCH_NAME == "main"'

# 声明要推送的镜像（没有这行 Cloud Build 不会自动 push）
images:
  - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:$COMMIT_SHA'
  - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:latest'

substitutions:
  _REGION: 'asia-northeast1'
  _REPO: 'my-app'
  _SERVICE: 'my-service'

options:
  machineType: 'E2_HIGHCPU_8'
  diskSizeGb: 100
  logging: 'CLOUD_LOGGING_ONLY'

timeout: '1200s'

serviceAccount: 'projects/$PROJECT_ID/serviceAccounts/gcb-builder@$PROJECT_ID.iam.gserviceaccount.com'
```

**`cloudbuild.yaml` 三个必知规则**：
1. 提交时默认找仓库根目录的 `cloudbuild.yaml`（`--config` 可改）。
2. `images:` 里列出的镜像 Cloud Build 会在构建后**自动 push**；不在 `images:` 里的话即使 step 里 push 了也只是一次普通操作（不影响结果，但语义不清晰）。
3. 用户自定义 substitution **必须以 `_` 开头**。

### Step 6A：手动跑一次（先验证，再自动化）

```bash
# 在项目根目录（有 cloudbuild.yaml 的地方）
gcloud builds submit --config cloudbuild.yaml \
  --region=asia-northeast1 \
  --substitutions=_REGION=asia-northeast1,_REPO=my-app,_SERVICE=my-service
```

```bash
# 看状态
gcloud builds list --region=asia-northeast1 --limit=5

# 实时跟日志（最重要的一条命令）
gcloud builds log <BUILD_ID> --region=asia-northeast1

# 看详情（含每个 step 的耗时）
gcloud builds describe <BUILD_ID> --region=asia-northeast1
```

首次跑通后再上 trigger。

### Step 6B：建 Trigger

```bash
# GitHub 1st gen
gcloud builds triggers create github \
  --name=my-app-build \
  --region=asia-northeast1 \
  --repo-owner=<OWNER> \
  --repo-name=<REPO> \
  --branch-pattern='^main$' \
  --build-config=cloudbuild.yaml \
  --service-account=projects/<PROJECT_ID>/serviceAccounts/gcb-builder@<PROJECT_ID>.iam.gserviceaccount.com \
  --substitutions=_REGION=asia-northeast1,_REPO=my-app,_SERVICE=my-service

# 校验
gcloud builds triggers describe my-app-build --region=asia-northeast1
gcloud builds triggers list --region=asia-northeast1
```

2nd gen（Developer Connect）：

```bash
# 1) 建 connection（需先在控制台或用 gcloud 完成 SCM 授权）
gcloud builds connections create my-conn --region=asia-northeast1
gcloud builds connections describe my-conn --region=asia-northeast1

# 2) 建 repository（绑定到 connection）
gcloud builds repositories create my-repo \
  --connection=my-conn --region=asia-northeast1 \
  --remote-uri=https://github.com/<OWNER>/<REPO>.git

# 3) 建 trigger
gcloud builds triggers create github \
  --name=my-app-build \
  --region=asia-northeast1 \
  --repository=projects/<PROJECT_ID>/locations/asia-northeast1/connections/my-conn/repositories/my-repo \
  --branch-pattern='^main$' \
  --build-config=cloudbuild.yaml
```

### Step 7：手动触发与结果查看

```bash
# 手动触发（只能覆盖 trigger 里已定义的 substitution）
gcloud builds triggers run my-app-build \
  --region=asia-northeast1 \
  --branch=main \
  --substitutions=_SERVICE=my-service-canary

# 按 tag / commit SHA 触发
gcloud builds triggers run my-app-build --region=asia-northeast1 --tag=v1.2.0
gcloud builds triggers run my-app-build --region=asia-northeast1 --sha=<40位SHA>

# 取消正在跑的构建
gcloud builds cancel <BUILD_ID> --region=asia-northeast1
```

控制台路径：
- **Cloud Build → History**：所有构建历史 + 日志 + 制品
- **Cloud Build → Triggers**：管理触发器
- **Cloud Build → Dashboard**：成功率和耗时概览

---

## 6. API 启用清单

### 6.1 最小必需集（任何 Cloud Build 项目）

| API | 必需？ | 为什么 |
| :--- | :--- | :--- |
| `cloudbuild.googleapis.com` | ✅ **必需** | Cloud Build 核心服务。不开则一切不可用 |
| `compute.googleapis.com` | ✅ **强烈建议** | 构建 worker 是 Compute Engine VM；官方 quickstart 明确要求启用 Compute Engine API |
| `storage.googleapis.com` | ✅ 实际必需 | 源码 staging 到 `gs://{PROJECT_ID}_cloudbuild/source`，日志落 GCS（通常自动启用） |

### 6.2 按产物类型

| API | 何时需要 |
| :--- | :--- |
| `artifactregistry.googleapis.com` | 推镜像到 Artifact Registry（**推荐路径**，取代 GCR） |
| `containerregistry.googleapis.com` | 只有还用 GCR（`gcr.io`）才需要（GCR 已停止新项目使用） |
| `cloudbuildregional.googleapis.com` | 使用区域化构建资源（区域 worker pool）时的配套 |
| `iamcredentials.googleapis.com` | 用 SA impersonation 时 |
| `iam.googleapis.com` | 管理 SA / 绑角色 |

### 6.3 按触发器类型

| API | 何时需要 |
| :--- | :--- |
| `developerconnect.googleapis.com` | **2nd gen 仓库连接**（Developer Connect）：GitHub/GitLab/Bitbucket 2nd gen |
| `sourcerepo.googleapis.com` | Cloud Source Repositories 触发器 |
| `pubsub.googleapis.com` | Pub/Sub 触发器；构建结果发到 Pub/Sub topic；`options.pubsubTopic` |
| `secretmanager.googleapis.com` | Webhook 触发器的 secret；build config 里从 Secret Manager 取值（`secrets`） |

### 6.4 按部署目标

| API | 目标 |
| :--- | :--- |
| `run.googleapis.com` | Cloud Run（Service / Job） |
| `container.googleapis.com` | GKE / GKE Autopilot |
| `clouddeploy.googleapis.com` | Cloud Deploy（多环境晋级） |
| `cloudfunctions.googleapis.com` | Cloud Functions |
| `firebase.googleapis.com` | Firebase Hosting / Functions |
| `binaryauthorization.googleapis.com` | Binary Authorization（供应链准入） |
| `containeranalysis.googleapis.com` | Artifact Analysis（漏洞扫描） |
| `binaryauthorization` 对应的 `policy` 资源 | 见上 |

### 6.5 一键命令（推荐基线）

```bash
PROJECT_ID=<PROJECT_ID>

gcloud services enable \
  cloudbuild.googleapis.com \
  compute.googleapis.com \
  storage.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  logging.googleapis.com \
  --project=$PROJECT_ID

# 需要接 GitHub 2nd gen 再加
gcloud services enable developerconnect.googleapis.com --project=$PROJECT_ID

# 需要接 GitHub 1st gen（GitHub App）：仅 cloudbuild 即可

# 需要 Pub/Sub / Webhook 触发器再加
gcloud services enable pubsub.googleapis.com secretmanager.googleapis.com --project=$PROJECT_ID
```

---

## 7. IAM 角色清单

### 7.1 人的角色（操作者）

| 角色 | 用途 |
| :--- | :--- |
| `roles/cloudbuild.builds.viewer` | 看构建历史/日志（只读） |
| `roles/cloudbuild.builds.editor` | 提交构建、创建/运行触发器（**最常用**） |
| `roles/cloudbuild.admin` | 含 worker pool / connection / trigger 的完整管理 |
| `roles/cloudbuild.connectionAdmin` | 管理 Developer Connect connection |
| `roles/serviceusage.serviceUsageAdmin` | 启用 API |
| `roles/iam.serviceAccountUser` | 以指定 SA 身份运行 build（`iam.serviceAccounts.actAs`） |
| `roles/storage.objectUser` / `roles/storage.bucketViewer` | 触发器配置需要（官方 automate-builds 指南列出） |

### 7.2 构建用的 Service Account（BYOSA）

| 角色 | 用途 |
| :--- | :--- |
| `roles/cloudbuild.builds.editor` | 允许该 SA 自己发起后续构建（链式触发） |
| `roles/logging.logWriter` | 写日志 |
| `roles/storage.objectUser` + `roles/storage.bucketViewer` | 源码 staging、日志桶读写 |
| `roles/artifactregistry.writer` | 推镜像 |
| `roles/run.admin` | 部署 Cloud Run |
| `roles/container.developer` | 部署 GKE |
| `roles/compute.admin` | 部署 GCE（**权限很大，慎给**） |

### 7.3 两个系统身份，别搞混

| 身份 | 作用 |
| :--- | :--- |
| `{PROJECT_NUMBER}@system.gserviceaccount.com` | **默认构建 SA**（legacy）。开启 Cloud Build API 时自动创建，不建议直接用 |
| `service-{PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com` | **Cloud Build Service Agent**。启用 API 时自动创建，代表 Cloud Build 服务本身操作资源 |

查默认 SA：
```bash
gcloud builds get-default-service-account --project=<PROJECT_ID>
```

---

## 8. cloudbuild.yaml Schema 速查

官方 [Build 配置文件 schema](https://cloud.google.com/build/docs/build-config) 的完整字段（YAML）：

```yaml
# ── 步骤 ──────────────────────────────────────
steps:
  - name: string                # builder 镜像（必填）
    args: [string, ...]         # 传给 entrypoint 的参数
    env: [string, ...]          # 环境变量，格式 KEY=VALUE
    secretEnv: string           # 从 Secret Manager 注入的 secret 列表
    volumes: object(Volume)     # 挂载 volume
    allowFailure: boolean       # 失败是否不中断构建
    allowExitCodes: [int, ...]  # 允许的退出码
    dir: string                 # 工作目录（相对 /workspace）
    id: string                  # step id，供 waitFor 引用
    waitFor: [string, ...]      # 依赖的 step id
    entrypoint: string          # 覆盖镜像默认 entrypoint
    timeout: string             # 该 step 超时，如 300s
    script: string              # 多行脚本，等价于 bash -c
    automapSubstitutions: boolean
    results: object(Results)    # 产出物

# ── 全局 ──────────────────────────────────────
timeout: string                 # 整体超时，如 1200s
queueTtl: string                # 排队最长时间
logsBucket: string              # 日志桶
serviceAccount: string          # 执行构建的 SA
tags: [string, ...]             # 自定义标签
substitutions: map              # 自定义变量（_ 前缀）
secrets: object(Secret)         # Secret Manager 密钥挂载
availableSecrets: object(Secrets)

# ── 产物 ──────────────────────────────────────
images: [string, ...]
artifacts:
  objects:
    location: string            # gs://bucket/path
    paths: [string, ...]
    timeout: string
  mavenArtifacts: [...]
  pythonPackages: [...]
  npmPackages: [...]
  goModules: [...]

# ── 执行选项 ──────────────────────────────────
options:
  env: [string, ...]
  secretEnv: string
  volumes: object(Volume)
  machineType: enum(MachineType)     # E2_HIGHCPU_8 / N1_HIGHCPU_16 ...
  diskSizeGb: string
  sourceProvenanceHash: enum(HashType)  # NONE / SHA256 / MD5
  substitutionOption: enum(SubstitutionOption)  # ALLOW_LOOSE / ALLOW_MISSING / STRICT
  dynamicSubstitutions: boolean     # 运行时才做 substitution（用于不能提前展开的场景）
  automapSubstitutions: boolean
  logStreamingOption: enum(LogStreamingOption)
  logging: enum(LoggingMode)        # GCS_ONLY / CLOUD_LOGGING_ONLY / NONE
  defaultLogsBucketBehavior: enum(DefaultLogsBucketBehavior)
  pool: object(PoolOption)          # {name: private-pool-id}
  pubsubTopic: string
  requestedVerifyOption: enum(RequestedVerifyOption)
  workerRelease: string
```

### 内置 substitution 变量

| 变量 | 含义 |
| :--- | :--- |
| `$PROJECT_ID` | 触发构建的项目 ID |
| `$BUILD_ID` | 构建 ID |
| `$PROJECT_NUMBER` | 项目数字 ID |
| `$REPO_NAME` | 仓库名 |
| `$BRANCH_NAME` | 分支名（触发器上下文） |
| `$TAG_NAME` | tag 名 |
| `$COMMIT_SHA` | 完整 commit SHA |
| `$SHORT_SHA` | 短 SHA |
| `$REVISION_ID` | revision ID |
| `$TRIGGER_NAME` | 触发器名 |
| `$BUILD_ID` | 构建 ID |
| `_XXX` | 用户自定义（必须 `_` 前缀） |

---

## 9. CLI 命令速查

```bash
# ── 提交 ──
gcloud builds submit --config cloudbuild.yaml --region=<REGION>
gcloud builds submit --tag gcr.io/<PROJECT>/<IMAGE>            # 极简 docker 构建
gcloud builds submit --config=cloudbuild.yaml \
  --substitutions=_ENV=prod,_TAG=v1.0 \
  --service-account=projects/<P>/serviceAccounts/<SA> \
  --timeout=1800s --machine-type=E2_HIGHCPU_8 --disk-size=200

# ── 查看 ──
gcloud builds list --region=<REGION> --limit=20
gcloud builds list --filter='status=FAILURE' --region=<REGION>
gcloud builds describe <BUILD_ID> --region=<REGION>
gcloud builds log <BUILD_ID> --region=<REGION>              # 实时跟日志
gcloud builds log <BUILD_ID> --region=<REGION> --stream     # 显式流式

# ── 触发器 ──
gcloud builds triggers list --region=<REGION>
gcloud builds triggers describe <NAME> --region=<REGION>
gcloud builds triggers run <NAME> --region=<REGION> --branch=main
gcloud builds triggers update github <NAME> --region=<REGION> \
  --update-substitutions=_TAG=v2
gcloud builds triggers delete <NAME> --region=<REGION>

# ── 其它 ──
gcloud builds cancel <BUILD_ID> --region=<REGION>
gcloud builds get-default-service-account --project=<P>
gcloud builds connections list --region=<REGION>
gcloud builds repositories list --connection=<CONN> --region=<REGION>
gcloud builds worker-pools list --region=<REGION>
```

---

## 10. 成本与配额

### 计费模型（以官方 pricing 页为准，2026-11 核对）

- 计费单位是 **build-minute**，构建处于 `QUEUED` 状态**不计费**，秒级按实际秒数计费。
- **每个 billing account 每月 2,500 个免费 build-minute**（促销额度，仅限 default pool 的 `e2-standard-2`）。
- 网络出流量（egress）按标准费率另计。

| 机型 | vCPU | 内存 | 单价 (USD/分钟) |
| :--- | :--- | :--- | :--- |
| `e2-medium` | 1 | 4 GB | $0.003 |
| `e2-standard-2` | 2 | 8 GB | **$0.006**（Quick Start 推荐） |
| `e2-highcpu-8` | 8 | 8 GB | $0.0156 |
| `e2-highcpu-32` | 32 | 32 GB | $0.0624 |
| `n1-highcpu-8` / `n1-highcpu-32` | — | — | 与 e2-highcpu 同价 |

> ⚠️ 网上流传的「$0.0034/分钟、每天 120 免费分钟」是**旧版文档**。当前官方是 **2,500 分钟/月**。

- 额外 SSD：前 100 GB 免费，最多可申请 4000 GB，按 GiB·小时计费。

### 配额

| 配额 | 默认值 | 可否提升 | 范围 |
| :--- | :--- | :--- | :--- |
| Default Pool 并发构建数 | **10**（可调到 30） | 可调 | global region |
| Default Pool 并发 E2 CPU | 5–100 | 否，需用 private pool | per region |
| Private Pool 并发 CPU | 依项目而定（E2/N2D 最高 2400，C3 最高 300） | 可提 | per region |
| 每个构建的 step 数 | 300 | 否 | — |
| 每个构建的镜像数 | 700 | 否 | — |
| 每个 step 的 args 数 | 100 | 否 | — |

**成本优化**：
- 默认 `e2-standard-2`；编译型项目（Java/Go/前端）用 `E2_HIGHCPU_8`。
- 用 `--no-cache` / Kaniko 缓存策略权衡构建时长 vs 缓存成本。
- `logging: CLOUD_LOGGING_ONLY` 避免 GCS 日志桶存储费。
- 构建里不要 `sleep` / 等人工输入，纯烧钱。

---

## 11. 安全最佳实践

1. **绝不用默认 SA 跑生产构建**。默认 SA `{PROJECT_NUMBER}@system.gserviceaccount.com` 权限过大且不受你控制。
2. **拆分 build SA 与 deploy SA**。构建只给 `artifactregistry.writer`；部署用另一条流水线 + `--require-approval` 人工卡点。
3. **生产触发器开 `--require-approval`**：`gcloud builds triggers run` 或控制点确认后才真正跑。
4. **substitution 里的敏感值走 Secret Manager**，不要写进 `cloudbuild.yaml`：
   ```yaml
   availableSecrets:
     secretManager:
       - versionName: projects/<P>/secrets/db-pass/versions/latest
         env: 'DB_PASSWORD'
   ```
5. **用 `substitutionOption: STRICT`** 防止变量拼错被静默吞掉。
6. **镜像用 digest 而非 tag 部署**（`@sha256:...`），避免 tag 被覆盖。
7. **开启 Binary Authorization**：Cloud Build 生成的 provenance 才有意义，否则任何本地 `docker push` 都能冒充。
8. **敏感构建放 Private Pool**，同时满足内网访问与网络隔离。
9. **审计**：`roles/auditviewer` + Cloud Audit Logs + Cloud Logging 的 build 日志。
10. **不要在 build step 里 `gcloud auth` 用自己的账号**——用 `--service-account` / SA impersonation。

---

## 12. 常见坑与排错

| 现象 | 原因 | 处理 |
| :--- | :--- | :--- |
| `INVALID_ARGUMENT: Project ... not found or deleted` | API 未启用，或项目号/项目 ID 写错 | `gcloud services list --enabled \| grep cloudbuild` |
| `USER_PROJECT_DENIED` | 账号对该项目无权限 | 换个有权限的账号/项目；别拿 placeholder 项目 ID 试 |
| 构建一直 `QUEUED` | 并发配额用尽（默认 10） | 等、或提配额、或换 region |
| 构建成功但镜像没推上去 | `images:` 里没声明 | 把镜像加进 `images:` |
| 部署步骤没执行 | `condition` 不匹配 | 检查 `$BRANCH_NAME`；PR 场景用 `$COMMIT_SHA` 等 |
| trigger 改了 region 改不了 | **region 创建后不可变** | 删了重建，或用 `gcloud builds triggers import` 迁移 |
| substitution 传不进去 | runtime 不能新增 key | 只能覆盖 trigger 里已定义的 `_XXX` |
| `docker push` 报 denied | SA 缺 `artifactregistry.writer` | 补角色 |
| 拉不到私有 Git | Default Pool 无内网 | 换 Private Pool 或 2nd gen + Developer Connect |
| 步骤报 `not found` | 用了已下线的 builder 镜像 | 换 `gcr.io/google.com/cloudsdktool/cloud-sdk` 等现行镜像 |
| `terraform apply` 在 build 里搞乱生产 | CI 凭证即部署权限 | 生产用 Cloud Deploy / 独立审批流；至少用 workspace + plan-only |
| 日志看不到 | `logging: NONE` 或区域不匹配 | 检查 `options.logging` 与 `--region` 一致 |

**排错三板斧**：
```bash
gcloud builds describe <BUILD_ID> --region=<REGION>   # 看每个 step 的 status / exitCode
gcloud builds log <BUILD_ID> --region=<REGION>          # 看完整 stdout/stderr
gcloud builds list --filter='status=FAILURE' --region=<REGION>
```

---

## 13. 与相邻产品的分工

| 需求 | 用什么 |
| :--- | :--- |
| 编译 / 测试 / 打包 | **Cloud Build** |
| 容器镜像存储 | **Artifact Registry**（不要再用 GCR） |
| 漏洞扫描 | **Artifact Analysis**（在 build 里调） |
| 构建来源证明 + 部署准入 | **Binary Authorization** |
| 多环境（dev→staging→prod）晋级 | **Cloud Deploy**（Cloud Build 只负责构建出制品） |
| 内网构建 | **Private Pool** |
| 接外部 Git 平台 | **Developer Connect**（2nd gen） |
| 日志 / 指标 / 告警 | **Cloud Logging** / **Cloud Monitoring** |
| 编排多个云 | **Cloud Build + Terraform / Config Controller** |

**推荐流水线形态**：

```
Git push
  → Cloud Build Trigger（build SA，只做 test + build + push image）
  → Artifact Registry（tag = $COMMIT_SHA）
  → Cloud Deploy（staging）→ 验证 → Cloud Deploy（prod）
  → Binary Authorization 校验 provenance
```

Cloud Build **只做 build**，不要在同一个 step 里既构建又直接改生产环境——那样就没有审批点了。

---

## 官方文档

- 总览：https://cloud.google.com/build/docs/overview
- Build config schema：https://cloud.google.com/build/docs/build-config
- Cloud Builders：https://cloud.google.com/build/docs/cloud-builders
- 自动化触发器：https://cloud.google.com/build/docs/automate-builds
- Docker 快速上手：https://cloud.google.com/build/docs/build-push-docker-image
- 部署 Cloud Run：https://cloud.google.com/build/docs/deploying-builds/deploy-cloud-run
- 部署 GKE：https://cloud.google.com/build/docs/deploying-builds/deploy-gke
- 区域：https://cloud.google.com/build/docs/locations
- 配额：https://cloud.google.com/build/quotas
- 定价：https://cloud.google.com/build/docs/pricing
- REST API：https://cloud.google.com/build/docs/api/reference/rest
