# 从 GitHub 到 Cloud Build：打通「push → 构建镜像 → 推 Artifact Registry」的完整链路

> **TL;DR**
>
> 这条链路里有 **3 个独立的「身份」** 和 **2 个可选的接入姿势**，搞清楚它们，整条流程就是透明的：
>
> - **身份 ①**：GitHub App（装在你 repo 上的那个"机器人"）——负责**收 webhook** 和**给 Cloud Build 授权读源码**。
> - **身份 ②**：Cloud Build **Trigger**（GCP 侧的一条规则）——把「事件」映射成「一次构建」。
> - **身份 ③**：**Build Service Account**（GCP 侧的机器人）——在构建 VM 上执行 step、推镜像到 Artifact Registry。
>
> 两条推荐路线：
> - **路线 A（1st gen）**：用 Google 托管的 **Cloud Build GitHub App**，控制台点几下就能跑通，**最快**。缺点：region 只能是 `global`，GitHub App 归 Google 管。
> - **路线 B（2nd gen）**：用 **Developer Connect** 建 `connection` + `repository`，**企业规范推荐**。缺点：region 不可改、必须先授权 GitHub。
>
> 关键认知：**GitHub 侧什么都不用装**（不需要 Jenkins agent、不需要自建 runner）。Cloud Build 的构建跑在 **GCP 的临时 VM** 上，GitHub 只负责"喊一嗓子"。

---

## 目录

1. [需求还原与路线选型](#1-需求还原与路线选型)
2. [整条链路的原理：一次 push 到底发生了什么](#2-整条链路的原理一次-push-到底发生了什么)
3. [必懂概念：GitHub App 到底是什么](#3-必懂概念github-app-到底是什么)
4. [路线 A：1st gen（Cloud Build GitHub App）](#4-路线-a1st-gencloud-build-github-app)
5. [路线 B：2nd gen（Developer Connect）★ 企业推荐](#5-路线-b2nd-gendeveloper-connect-企业推荐)
6. [路线 C：不用 GitHub App 的两条替代路径](#6-路线-c不用-github-app-的两条替代路径)
7. [**场景变体：GitHub 企业版（GitHub Enterprise）**](#7-场景变体github-企业版github-enterprise)
8. [构建配置与产物落地：镜像 / JAR 分别推到哪](#8-构建配置与产物落地镜像--jar-分别推到哪)
9. [IAM 身份全景表](#9-iam-身份全景表)
10. [GitHub 场景下的内置 substitutions](#10-github-场景下的内置-substitutions)
11. [生产化加固清单](#11-生产化加固清单)
12. [排错手册](#12-排错手册)
13. [端到端验收 checklist](#13-端到端验收-checklist)
14. [官方文档](#14-官方文档)

---

## 1. 需求还原与路线选型

### 1.1 你的需求（翻译成技术语言）

```
① 源码在 GitHub（github.com/OWNER/REPO）
② 希望「有人 push 到 main」这一事件，自动触发一次构建
③ 构建做的事：拉代码 → 测试 → 构建 Docker 镜像
④ 产物落地：镜像推到 Artifact Registry（你说的"推送到对应的 JAR 里面"）
              —— 下面 §8 会同时覆盖「镜像 → AR」和「真的 JAR → AR Maven 仓库」两种
```

### 1.2 三条路线的对比

| | 路线 A：1st gen | 路线 B：2nd gen（Developer Connect）★ | 路线 C：GitHub Actions / Webhook |
| :--- | :--- | :--- | :--- |
| **连接 GitHub 的方式** | 控制台安装 Google 托管的 **Cloud Build GitHub App** | 先建 **Developer Connect connection**（会新建一个 GitHub App），授权后再建 repository | 不用 App：Actions 用 OIDC 换 GCP 凭证；Webhook 用裸 HTTP POST |
| **GitHub App 谁来装** | 你装 Google 的 App（App 属于 Google） | 你装 **Developer Connect 创建的 App**（App 属于你的 org，可自审、可审计） | 不需要 |
| **trigger region** | 可用 `global` | **必须指定具体 region**，且 connection / repository / trigger **三者 region 一致**，**创建后不可改** | Actions 侧不涉及 |
| **需要的额外 API** | 仅 `cloudbuild` | 额外 `developerconnect` | `iamcredentials`（WIF） |
| **仓库访问凭据** | Google 内部持有，你看不到 | Developer Connect 托管的 GitHub App installation token | Actions 用 WIF token |
| **PR 上有 Check 状态** | ✅ 自动写 commit status | ✅ 同等能力 | 取决于你写不写 status API |
| **上手速度** | **最快**（控制台 5 分钟） | 中（需装 App + 授权 + 建 3 个资源） | 中（要自己写 Actions + 配 WIF） |
| **企业治理 / 审计** | 一般（App 归属 Google 个人体系） | **好**（App 归属你的 org，可统一管控） | 好 |
| **适合** | 个人项目、学习、快速验证 | **生产项目、多仓库、多团队** | 已有 Actions 体系 / 不想引入 GCP trigger |

> **⚠️ 上表假设源码在 `github.com`。**
> 如果你的代码在 **GitHub Enterprise（企业版）**，事情会多出 4 件事：**App 要自己建、私钥要自己管、内网要打通（Service Directory）、自签 CA 要上传**。
> 完整拆解见 **[§7 场景变体：GitHub 企业版](#7-场景变体github-企业版github-enterprise)**。

### 1.3 我的建议

| 场景 | 选 |
| :--- | :--- |
| 先跑通、验证 `cloudbuild.yaml` 对不对 | **先 `gcloud builds submit` 手动跑一次**（连 trigger 都不建），跑通再上 trigger |
| 单仓库、单团队 | 路线 A（够用） |
| 多仓库 / 要审计 / 以后要接 GitLab、Bitbucket | **路线 B**（Developer Connect 是统一入口，接 GitLab/Bitbucket 也走它） |
| 已经在用 GitHub Actions | 路线 C-1 |
| **代码在 GitHub Enterprise Server（自建、内网）** | 路线 B'（§7.3），**不要用路线 C**——官方明确 manual / PubSub trigger 无法通过 Cloud Build 集成构建 GHE 仓库 |

> **不要跳过手动跑通**这一步。`gcloud builds submit` 只需要 1 条命令，能把 80% 的问题（YAML 写错、IAM 缺角色、Dockerfile 崩）在 2 分钟内暴露出来；而建 trigger + 装 App 失败时的报错信息要模糊得多。

---

## 2. 整条链路的原理：一次 push 到底发生了什么

### 2.1 时序全景

```
  开发者            GitHub              GitHub App            GCP 侧
    │                 │                    │                    │
    │ git push        │                    │                    │
    ├────────────────>│                    │                    │
    │                 │ ① git 接受 push    │                    │
    │                 │ ② 触发事件分发     │                    │
    │                 │──────webhook─────>│                    │
    │                 │                    │                    │
    │                 │                    │ ③ GitHub App 收到   │
    │                 │                    │    push 事件        │
    │                 │                    │    （带签名）        │
    │                 │                    │                    │
    │                 │                    │ ④ 投递到 Cloud     │
    │                 │                    │    Build / DC 端点  │
    │                 │                    │───────────────────>│
    │                 │                    │                    │ ⑤ Cloud Build
    │                 │                    │                    │    匹配 Trigger
    │                 │                    │                    │    (repo+event+branch)
    │                 │                    │                    │
    │                 │                    │                    │ ⑥ 克隆源码
    │                 │  <── 用 installation token 拉取 ─────────│
    │                 │                    │                    │
    │                 │                    │                    │ ⑦ 源码打包 →
    │                 │                    │                    │  gs://{PROJECT}_cloudbuild/source
    │                 │                    │                    │
    │                 │                    │                    │ ⑧ 拉起临时 VM
    │                 │                    │                    │    拉起 build SA 权限
    │                 │                    │                    │ ⑨ 逐步跑 step
    │                 │                    │                    │    (每个 step 一个容器)
    │                 │                    │                    │ ⑩ 推镜像 →
    │                 │                    │                    │    Artifact Registry
    │                 │                    │                    │
    │                 │                    │                    │ ⑪ Build 状态回写
    │                 │  <── commit status / check run ─────────┤
```

### 2.2 三个必须搞清的「身份」

这是整条链路里最容易懵的地方。**三个身份各管一段，互不替代**：

| 身份 | 存在哪 | 干什么 | 凭证形态 |
| :--- | :--- | :--- | :--- |
| **① GitHub App** | 装在你的 GitHub org / repo 上 | ① 订阅 `push` / `pull_request` 事件 ② 授予 Cloud Build 读源码的权限 | **Installation Token**（JWT 换来的，1 小时过期，Google 侧自动刷新，你永远看不到它） |
| **② Cloud Build Trigger** | GCP 侧（一个 API 资源） | 把「事件 + 仓库 + 分支正则」映射成「跑哪份 build config、用哪个 SA、带哪些 substitution」 | 无（它只是规则） |
| **③ Build Service Account** | GCP IAM | 在构建 VM 上**执行** step、推镜像、读 Secret | GCP 短期 access token（由 metadata server 自动下发） |

> **常见误解纠正**：
> - 「GitHub App 是把代码交给 Cloud Build 的」——不对，App 只是**授权 + 通知**，源码是 Cloud Build **主动去 clone** 的（用 installation token）。
> - 「Trigger 是装在 GitHub 上的东西」——不对，Trigger **只存在于 GCP**。GitHub 上你只会看到一个 App 和一条 webhook 订阅。
> - 「构建是在 GitHub 的 runner 上跑的」——不对，构建跑在 **GCP 的临时 Compute Engine VM** 上，GitHub 的 runner 空间完全无关。

### 2.3 源码是怎么"进到"构建 VM 的（源码中转站）

Cloud Build **不是**让构建 VM 直接去 GitHub clone。真实链路是：

```
GitHub ──(Cloud Build 用 installation token clone)──> Cloud Build 的控制面
                                                     │
                                                     ├─> 打包成 tar
                                                     └─> 上传到 gs://{PROJECT_ID}_cloudbuild/source
                                                                  │
                                                                  ▼
                                          临时构建 VM 从这个 GCS 桶下载解压到 /workspace
```

**三个直接后果**（排错时经常踩）：

1. 构建默认需要 **`roles/storage.objectUser`**（往源码桶写）+ **`roles/storage.bucketViewer`**（从日志桶读）。
2. 你的源码会在 GCS 里留一份副本 —— 敏感仓库要意识到这点。
3. **`$COMMIT_SHA` 是精确的那个 commit**。PR 触发时它是 **merge commit 的 SHA**（GitHub 侧生成的虚拟合并提交），不是 PR 分支 head 的 SHA。

---

## 3. 必懂概念：GitHub App 到底是什么

用户问的「GitHub 里面需要一个 Git App 来对应 Trigger」，核心就是理解 GitHub App 这套机制。

### 3.1 GitHub App vs OAuth App vs PAT

| | GitHub App | OAuth App | Personal Access Token |
| :--- | :--- | :--- | :--- |
| 安装粒度 | **装到 org / repo**（Installation） | 装到个人账号 | 属于某个人 |
| 权限粒度 | 按 **repository 权限 × 事件类型** 细粒度 | 粗（scope 列表） | 粗，且通常是全仓库读写 |
| 有效期 | installation token **1 小时**，自动刷新 | access token 可撤销 | 到期手动换 |
| 身份 | **机器人身份**（bot），非个人 | 个人 | 个人 |
| 审计 | GitHub 里能看到"哪个 App 装在哪个 repo" | - | - |
| 典型用途 | **CI 机器人**（Cloud Build / Vercel / Sentry 都是这样） | 第三方应用代表用户操作 | 个人脚本 |
| **Cloud Build 用哪个** | ✅ **GitHub App** | ❌ | ❌ |

> **结论**：Cloud Build 用 GitHub App 而不是 PAT，是**安全设计的必然**：不需要把你的个人 token 交给 GCP，且可以只授予"读源码"这一个权限，还能做到"某个 App 只对某一个 repo 生效"。

### 3.2 一个 GitHub App 的三个实体

```
GitHub App（注册在 GitHub 上）
  ├── app_id            应用编号
  ├── private_key       私钥（用来签 JWT）
  ├── permissions       声明它想要什么权限（Contents: read 等）
  └── events            声明它想听什么事件（push / pull_request / ...）
        │
        └── Installation（把它装到某个 org / repo 的动作）
              ├── installation_id
              └── → 换出 Installation Token（JWT 换 token，1h 有效）
```

### 3.3 Cloud Build 场景需要的权限 / 事件

| 权限 | 需要吗 | 用途 |
| :--- | :--- | :--- |
| Metadata: Read-only | ✅ **必需** | GitHub 强制要求，所有 App 都有 |
| Contents: Read-only | ✅ **必需** | **clone 源码** |
| Pull requests: Read-only | 视情况 | PR 触发器读取 PR 信息 |
| Commit statuses / Checks: Write | 视情况 | 在 PR 上回写 "Cloud Build 通过/失败" 状态；`/gcbrun` 手动放行功能**需要写权限** |
| Actions: Read-only | 视情况 | 只在需要读 workflow 状态时 |

订阅事件：

| 事件 | 触发器类型 |
| :--- | :--- |
| `push` | push 到分支 / push tag |
| `pull_request` | PR 打开/更新/关闭 |
| `pull_request_review` | PR review（配合 comment-control） |

### 3.4 App 的两种拥有方式（这是 A/B 路线的本质差异）

| | 路线 A（1st gen） | 路线 B（2nd gen） |
| :--- | :--- | :--- |
| App 的拥有者 | **Google**（App 叫 "Cloud Build GitHub App"） | **你的 GitHub org**（每建一个 Developer Connect connection 就生成一个 App） |
| 私钥在哪 | Google 的服务器里，**你看不到** | 你在 GitHub 装 App 时，GitHub 生成并把私钥交给 Developer Connect（存在 GCP 内部） |
| 你要做的 | 控制台点「Install App」，选 repo | 建 connection → 跳 GitHub 装 App → 授权 |
| 审计归属 | 装在哪个 org 由 Google 侧统一管理 | **你自己的 org 能看到全部 App 清单** |

> 实践含义：路线 B 每次建 connection 都会在 GitHub 上留下一个 App 记录，**要定期清理不用的 connection**，否则 org 的 App 列表会越来越脏。

---

## 4. 路线 A：1st gen（Cloud Build GitHub App）

### 4.1 原理

Google 已经把 GitHub App 那套（App + 私钥 + token 刷新）全部做好了。你只需要：

1. 在 Cloud Build 控制台点「Connect Repository」；
2. GitHub 那边弹出「安装 Cloud Build GitHub App」的页面，你选 **哪个 org + 哪些 repo**；
3. 装完，Cloud Build 就知道「这个 repo 可以被我读」；
4. 你在 Cloud Build 里建 Trigger，指向这个 repo。

### 4.2 完整配置流程

**Step 1 — 前置检查**

```bash
gcloud config set project <PROJECT_ID>

gcloud services enable \
  cloudbuild.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com

# 确认项目已开通结算（否则 build 直接失败）
gcloud billing projects describe <PROJECT_ID>
```

**Step 2 — 建 Artifact Registry 仓库（存镜像）**

```bash
gcloud artifacts repositories create my-app \
  --repository-format=docker \
  --location=asia-northeast1 \
  --description="my-app images"

# 拿到仓库地址，形如：
# asia-northeast1-docker.pkg.dev/<PROJECT_ID>/my-app
```

**Step 3 — 建专用 Build Service Account（别用默认 SA）**

```bash
PROJECT_ID=<PROJECT_ID>
SA=gcb-builder@${PROJECT_ID}.iam.gserviceaccount.com

gcloud iam service-accounts create gcb-builder \
  --display-name="Cloud Build Builder"

for ROLE in roles/logging.logWriter \
            roles/storage.objectUser \
            roles/storage.bucketViewer \
            roles/artifactregistry.writer; do
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:${SA}" --role="$ROLE"
done

# 你自己需要能 actAs 这个 SA，才能在 trigger 里指定它
gcloud iam service-accounts add-iam-policy-binding ${SA} \
  --member="user:<你的邮箱>" --role="roles/iam.serviceAccountUser"
```

> **两个系统身份别搞混**（见 [cloudbuild-guide.md](cloudbuild-guide.md) §8.3）：
> - `{PROJECT_NUMBER}@system.gserviceaccount.com` —— **默认构建 SA**，老项目里带 Editor 权限，**别用**。
> - `service-{PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com` —— Cloud Build 的**服务代理**，负责建 GCS 源码桶、生成 provenance attestation。你不用管它。

**Step 4 — 写 `cloudbuild.yaml`**（放进 repo 根目录）

见 §8。

**Step 5 — 先手动跑通（关键！别跳过）**

```bash
gcloud builds submit --config cloudbuild.yaml \
  --region=asia-northeast1 \
  --substitutions=_REGION=asia-northeast1,_REPO=my-app

gcloud builds log <BUILD_ID> --region=asia-northeast1
```

**Step 6 — 连接 GitHub 仓库**

控制台路径：**Cloud Build → Triggers → 右上角「连接仓库 / Connect Repository」**

1. 选 **GitHub (Cloud Build GitHub App)**；
2. 点「Continue to Authenticate」→ 跳到 GitHub；
3. 选 **组织 / 个人账号** → 勾选要授权的 **repo**（只勾你要构建的那一个，least privilege）；
4. 同意权限（Contents: Read-only 等）→ 装好；
5. 回到 Cloud Build，选中刚连上的 repo → Connect → Done。

验证：

```bash
# 1st gen 用的是这个命令（注意是 builds repos，不是 builds repositories）
gcloud builds repos list --project=<PROJECT_ID>
```

**Step 7 — 建 Trigger**

```bash
gcloud builds triggers create github \
  --name=my-app-build \
  --region=global \
  --repo-owner=<OWNER> \
  --repo-name=<REPO> \
  --branch-pattern='^main$' \
  --build-config=cloudbuild.yaml \
  --service-account=projects/<PROJECT_ID>/serviceAccounts/gcb-builder@<PROJECT_ID>.iam.gserviceaccount.com \
  --substitutions=_REGION=asia-northeast1,_REPO=my-app

# 校验
gcloud builds triggers describe my-app-build --region=global
gcloud builds triggers list --region=global
```

**Step 8 — 验证**

```bash
# 在 repo 里改个 README，推上去
git commit -am "test trigger" && git push

# 看有没有 build 被创建
gcloud builds list --region=global --limit=5
```

### 4.3 路线 A 的限制

- region 一般用 `global`，**无法迁到具体 region**（GitHub App 连接是全局的）。
- 无法同时接 GitLab / Bitbucket（那些要走 Developer Connect）。
- App 归属 Google，企业审计视角不够清晰。

---

## 5. 路线 B：2nd gen（Developer Connect）★ 企业推荐

### 5.1 原理

Developer Connect 是 GCP 里的一个**通用「代码托管连接层」**。它帮你把「GitHub 上的某个 repo」和「GCP 里的某个资源」绑起来，并且把 GitHub App 的私钥安全地托管在 GCP 内部（走 CMEK 加密的 Secret）。

三个资源的层次：

```
Developer Connect Connection   「我和 GitHub 之间的信任关系」
        │                        （含 GitHub App + installation）
        ▼
Cloud Build Repository          「我的某个具体 repo」
        │                        （connection + remote-uri）
        ▼
Cloud Build Trigger              「什么事件 → 构建什么」
                                 （必须引用上面那个 repository）
```

**region 铁律**：`connection` / `repository` / `trigger` **必须在同一个 region**，且 **region 创建后不可改**（跟 1st gen 的 trigger 一样）。

### 5.2 完整配置流程

**Step 1 — 启用 API + 授权 IAM**

```bash
gcloud services enable \
  cloudbuild.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  developerconnect.googleapis.com \
  iam.googleapis.com
```

需要建一个**给 connection 用的 SA**（跟 build SA 是两个角色，别混）：

```bash
PROJECT_ID=<PROJECT_ID>
DC_SA=devconnect-sa@${PROJECT_ID}.iam.gserviceaccount.com

gcloud iam service-accounts create devconnect-sa \
  --display-name="Developer Connect for Cloud Build"

# connection 的 SA 需要这个角色（Developer Connect 用来存状态、拉源码）
gcloud iam service-accounts add-iam-policy-binding ${DC_SA} \
  --member="serviceAccount:${DC_SA}" \
  --role="roles/developerconnect.serviceAgent" \
  --project=<PROJECT_ID>

# 你（操作者）需要能管 connection
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:<你的邮箱>" \
  --role="roles/developerconnect.connectionAdmin"
```

> `roles/developerconnect.connectionUser` 是「使用这个 connection 建 trigger」的权限 —— 建 trigger 的人需要它，或者把它授予 build SA / Cloud Build 服务代理。

**Step 2 — 建 Connection**

```bash
gcloud builds connections create my-conn --region=asia-northeast1
```

命令会返回一个 **授权 URL**（形如 `https://console.cloud.google.com/...`）。用浏览器打开它：

1. 选 GitHub；
2. **会引导你创建一个新的 GitHub App**（属于你的 org）并安装到目标 repo；
3. 同意权限（Contents read / Metadata read / PR read 等）；
4. 授权完成后回到 GCP，connection 变成 **ACTIVE**。

```bash
# 确认状态
gcloud builds connections describe my-conn --region=asia-northeast1
gcloud builds connections list --region=asia-northeast1
```

> **connection 状态不是 ACTIVE** → 多半是 GitHub 侧 App 没装完 / 权限没给够 / App 被卸载。回 GitHub 的 **Settings → Developer settings → GitHub Apps** 检查那个 App 的状态和授权的 repo。

**Step 3 — 建 Repository（绑定到 connection）**

```bash
gcloud builds repositories create my-repo \
  --connection=my-conn \
  --region=asia-northeast1 \
  --remote-uri=https://github.com/<OWNER>/<REPO>.git

gcloud builds repositories describe my-repo --region=asia-northeast1
```

**Step 4 — 建 Trigger（引用 repository）**

```bash
gcloud builds triggers create github \
  --name=my-app-build \
  --region=asia-northeast1 \
  --repository=projects/<PROJECT_ID>/locations/asia-northeast1/connections/my-conn/repositories/my-repo \
  --branch-pattern='^main$' \
  --build-config=cloudbuild.yaml \
  --service-account=projects/<PROJECT_ID>/serviceAccounts/gcb-builder@<PROJECT_ID>.iam.gserviceaccount.com \
  --substitutions=_REGION=asia-northeast1,_REPO=my-app \
  --require-approval=false
```

**Step 5 — 验证**

```bash
gcloud builds triggers describe my-app-build --region=asia-northeast1
gcloud builds triggers list --region=asia-northeast1

# 手动触发一次（不依赖 GitHub，先验证 trigger 本身是好的）
gcloud builds triggers run my-app-build --region=asia-northeast1 --branch=main
```

然后再 push 一次，验证 webhook 通路。

### 5.3 路线 B 的排查要点

| 现象 | 检查 |
| :--- | :--- |
| `gcloud builds triggers create` 报找不到 repository | region 不一致（connection 在 A 区、trigger 建在 B 区）→ 三者必须同区 |
| trigger 建好了但 push 不触发 | connection 状态不是 ACTIVE；GitHub App 被卸载；branch-pattern 正则不匹配 |
| build 创建了但拉不到源码 | build 执行身份缺 `roles/developerconnect.connectionUser`；或 GitHub App 没被授予该 repo 访问权 |
| 私有 repo 拉取失败 | App 权限只有 Metadata，没有 Contents: read |

### 5.4 1st gen 与 2nd gen 的资源对照

| 资源 | 1st gen 命令 | 2nd gen 命令 |
| :--- | :--- | :--- |
| 列仓库 | `gcloud builds repos list` | `gcloud builds repositories list --region=R` |
| 建 trigger | `gcloud builds triggers create github --repo-owner --repo-name` | `gcloud builds triggers create github --repository=projects/.../locations/R/connections/C/repositories/Repo` |
| region | `global`（或任意） | **必须具体 region**，且不可变 |

---

## 6. 路线 C：不用 GitHub App 的两条替代路径

### 6.1 路线 C-1：GitHub Actions 调 Cloud Build API

思路：**不让 Cloud Build 收 webhook，而是让 GitHub Actions 主动调 Cloud Build API**。GitHub Actions 用 OIDC（Workload Identity Federation）换 GCP 短期凭证，不需要存任何 key。

先配 WIF（Workload Identity Pool + Provider，信任 `repo:<OWNER>/<REPO>`）：

```bash
gcloud iam workload-identity-pools create github-pool \
  --location=global --display-name="GitHub OIDC pool"

gcloud iam workload-identity-pools providers create github-provider \
  --location=global \
  --workload-identity-pool=github-pool \
  --provider-id=github \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='<OWNER>/<REPO>'"

# 允许 GitHub 的 OIDC token 冒充 build SA
gcloud iam service-accounts add-iam-policy-binding \
  projects/<PROJECT_ID>/serviceAccounts/gcb-builder@<PROJECT_ID>.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/attribute.repository/<OWNER>/<REPO>"
```

然后在 repo 里加 `.github/workflows/build.yml`：

```yaml
name: build
on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write          # 关键：允许 OIDC 换 token

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github-pool/providers/github
          service_account: gcb-builder@<PROJECT_ID>.iam.gserviceaccount.com
      - uses: google-github-actions/setup-gcloud@v2
      - run: |
          gcloud builds submit \
            --config cloudbuild.yaml \
            --region=asia-northeast1 \
            --substitutions=_REGION=asia-northeast1,_REPO=my-app
```

**这条路的取舍**：

- ✅ 不需要在 GitHub 装 App，IAM 全在 GCP 侧，审计清晰。
- ❌ 多了一层：Actions runner 有配额和出网限制；构建上下文要额外传。
- ❌ 失去了 Cloud Build 原生的 **PR check 状态回写**（要自己写）。
- ❌ 用 `gcloud builds submit` 是**手动提交**，不享受 trigger 的审批（`--require-approval`）、不写 `TRIGGER_NAME` 等 trigger 上下文 substitution。若要保留，用 `gcloud builds triggers run my-app-build --branch=${{ github.ref_name }}`。

### 6.2 路线 C-2：Cloud Build Webhook Trigger + GitHub 原生 Webhook

最原始的做法：不用 App，用 GitHub 仓库设置里的 **Webhooks** 直接 POST 到 Cloud Build 的 webhook trigger 端点。

```bash
# 1) 先在 Secret Manager 里放 webhook secret
echo -n 'your-strong-random-secret' | \
  gcloud secrets create cloudbuild-webhook-secret --data-file=-

# 2) 建 webhook trigger
gcloud builds triggers create webhook \
  --name=my-app-webhook \
  --region=asia-northeast1 \
  --webhook-auth-secret=projects/<PROJECT_ID>/secrets/cloudbuild-webhook-secret/versions/latest \
  --build-config=cloudbuild.yaml \
  --service-account=projects/<PROJECT_ID>/serviceAccounts/gcb-builder@<PROJECT_ID>.iam.gserviceaccount.com
```

GitHub 侧 Webhook 的 **Payload URL** 填 Cloud Build 给出的 URL，**Secret** 填同一个值，**Content type** 选 `application/json`，事件选 **Push events**，Payload URL 里带上 `?secret=<secret>`。

**Payload 必须符合 Cloud Build 的固定格式**（这一点最容易踩）：

```json
{
  "ref": "refs/heads/main",
  "sha": "0000000000000000000000000000000000000000",
  "repository": {
    "name": "my-repo",
    "url": "https://github.com/OWNER/my-repo"
  }
}
```

> **注意**：`sha` 必须填**真实 commit SHA**（Cloud Build 会照着它去 checkout），GitHub 原生 webhook 的 `after` 字段才是它，但 payload 结构对不上 → 所以实际做法是用 GitHub 的 **Workflow 或第三方 action** 把 payload 转成上面这个格式再 POST。**这条路维护成本高，一般不推荐**，除非你已有 webhook 中转层。

---

## 7. 场景变体：GitHub 企业版（GitHub Enterprise）

> 这一章回答你说的「企业版是不是有不一样的地方」。**是的，而且差别比想象的大**——
> 但要分清楚：**GitHub Enterprise Cloud** 和 **GitHub Enterprise Server** 是两回事，
> 绝大部分「企业版」的坑都来自后者（自建、内网、SAML SSO）。

### 7.1 先分清三种「企业版」

| 形态 | 域名 | App 装在哪 | 网络可达性 | Cloud Build 支持 |
| :--- | :--- | :--- | :--- | :--- |
| **GitHub.com** | `github.com` | GitHub.com 公共市场 | 公网 | 1st gen + 2nd gen（§4 / §5） |
| **GitHub Enterprise Cloud** | `ghe.com` | 同 GitHub.com，但受企业策略管控 | 公网 | **走标准流程**，只是策略更严（App 安装需管理员、SAML 强制、仓库策略） |
| **GitHub Enterprise Server** | `ghe.corp.internal`（自建） | **你的 GHE 实例上**（org owner 操作） | **通常在内网**，Google 访问不到 | 1st gen（`githubEnterpriseConfigs`）+ 2nd gen（`connections create github-enterprise`） |

> **一句话区分**：
> - **GHE Cloud** = 托管版，企业策略差异 → 基本照抄 §5 就行。
> - **GHE Server** = 自建版 → **本章 §7.3 / §7.4 才是重点**，额外多出「网络打通」「自签 CA」「App 私钥自管」「SAML 授权」四件事。

### 7.2 GHE Server 的 8 个不同点（速览表）

| 维度 | GitHub.com | GitHub Enterprise Server |
| :--- | :--- | :--- |
| **App 注册位置** | GitHub.com 应用市场 | **你的 GHE 实例**（`https://ghe.corp.internal/settings/apps/new`） |
| **App 私钥** | Google 托管，你看不到 | **你自己生成并保管**（RSA PEM，存 Secret Manager） |
| **App 安装权限** | 仓库协作者即可 | **必须是 org owner**；若启用 SAML SSO，还需域账号授权 |
| **Connection 是否能 global** | 1st gen 可以 `global` | **不能，必须指定 region**（connection 永远有 region） |
| **Webhook URL** | App 订阅自动配置 | **手工配**，且 region 必须与 connection 一致 |
| **TLS 证书** | 公共 CA | **可能是自签 CA** → 需要 `--ssl-ca-file` |
| **源码可达性** | 公网直连 | **必须能被 Google 访问** → Service Directory / PSC / 公网暴露 |
| **Manual / PubSub trigger** | 支持 | **不支持**（官方明确：无法通过 Cloud Build 集成构建 GHE 仓库） |

### 7.3 路线 B'：2nd gen + GitHub Enterprise Server（★ 推荐）

#### 7.3.1 原理

2nd gen 的 GHE connection 就是一个 `developerconnect` 连接，配置类型从 `githubConfig` 换成 **`githubEnterpriseConfig`**，额外多了三个字段：

```
github_enterprise_config {
  host_uri                        = "https://ghe.corp.internal"   # GHE 实例地址
  private_key_secret_version     = ".../secrets/ghe-private-key/versions/1"
  webhook_secret_secret_version  = ".../secrets/ghe-webhook-secret/versions/1"
  app_id / app_slug / app_installation_id
  ssl_ca_certificate / service_directory (内网时)
}
```

**App 私钥和 webhook secret 存放在你自己项目的 Secret Manager 里**，Cloud Build 的服务代理（`service-{PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com`）有权限读取。这是与 GitHub.com 最大的区别：**凭据的生命周期归你管**（→ 私钥要定期轮换，见 §7.6）。

#### 7.3.2 前置准备

```bash
gcloud services enable \
  cloudbuild.googleapis.com \
  developerconnect.googleapis.com \
  secretmanager.googleapis.com \
  servicedirectory.googleapis.com      # 仅内网 GHE 需要
```

#### 7.3.3 在 GHE 上手工创建 GitHub App

**方式 A：让 Cloud Build 引导你创建（最简单）**

直接跑创建命令，它会返回一个 URL，点开后在 GHE 上完成 App 创建与安装：

```bash
gcloud builds connections create github-enterprise my-ghe-conn \
  --project=<PROJECT_ID> \
  --region=asia-northeast1 \
  --host-uri=https://ghe.corp.internal

# → 打印一个安装链接，浏览器打开，在 GHE 上创建并安装 App
```

**方式 B：自己先建好 App，再用参数一步到位（推荐，可 IaC 化）**

在 GHE 上：`Settings → Developer settings → GitHub Apps → New GitHub App`

| 表单项 | 填什么 |
| :--- | :--- |
| **GitHub App Name** | 任意，如 `gcb-builder` |
| **Homepage URL** | 你的 GHE 实例地址 |
| **Expire user authorization tokens** | **取消勾选**（官方要求） |
| **Webhook → Active** | ✅ 勾选 |
| **Webhook → Webhook URL** | `https://cloudbuild.googleapis.com/v2/projects/{PROJECT_NUMBER}/locations/{REGION}/connections:processWebhook` |
| **Webhook → Webhook secret** | 自己生成的随机串，**记下来** |
| **Repository permissions** | `Checks`: Read & write · `Contents`: Read & write · `Issues`: Read-only · `Metadata`: Read-only · `Commit statuses`: Read-only · `Pull requests`: Read-only |
| **Subscribe to events** | Check run · Check suite · Commit comment · Issue comment · Pull request · Pull request review comment · Push · Repository |
| **Any account** | 勾选（允许任意 user/org 安装） |

> ⚠️ **Webhook URL 里的 REGION 必须和 connection 的 region 完全一致**，否则事件投递会被丢弃。这是最常见的 GHE 配置错误之一。
>
> ⚠️ 注意官方给的权限清单里 **Contents 是 Read & write**（比 GitHub.com 场景宽）。如果你只想要只读，建议在 GHE 策略层收紧。

创建后拿到三个东西：

| 东西 | 在哪找 | 用途 |
| :--- | :--- | :--- |
| **App ID** | App 页面顶部 | `--app-id` |
| **App slug** | App 页面 URL 最后一段（`https://ghe.corp.internal/settings/apps/{slug}`） | `--app-slug` |
| **私钥 PEM** | App 页面 → Private keys → Generate private key → 下载的 `.pem` | 存 Secret Manager |
| **Installation ID** | 安装后 URL 最后一段（`.../settings/installations/{id}`） | `--app-installation-id` |

#### 7.3.4 凭据入 Secret Manager

```bash
# App 私钥
gcloud secrets create ghe-app-private-key --data-file=./ghe-app.pem

# Webhook secret
printf '%s' '<your-webhook-secret>' | gcloud secrets create ghe-webhook-secret --data-file=-

# Cloud Build 服务代理需要能读这两个 secret
for S in ghe-app-private-key ghe-webhook-secret; do
  gcloud secrets add-iam-policy-binding $S \
    --member="serviceAccount:service-<PROJECT_NUMBER>@gcp-sa-cloudbuild.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
done
```

> **这一步漏了** → connection 建得出来，但拉源码 / 收 webhook 会报权限错误。

#### 7.3.5 建 connection

```bash
gcloud builds connections create github-enterprise my-ghe-conn \
  --project=<PROJECT_ID> \
  --region=asia-northeast1 \
  --host-uri=https://ghe.corp.internal \
  --app-id=<APP_ID> \
  --app-slug=<APP_SLUG> \
  --app-installation-id=<INSTALLATION_ID> \
  --private-key-secret-version=projects/<PROJECT_ID>/secrets/ghe-app-private-key/versions/1 \
  --webhook-secret-secret-version=projects/<PROJECT_ID>/secrets/ghe-webhook-secret/versions/1

# 验证
gcloud builds connections describe my-ghe-conn --region=asia-northeast1
```

看 `installationState` 字段：

| 值 | 含义 |
| :--- | :--- |
| `COMPLETE` | ✅ 装好了，可以建 repository |
| 其他值 | 输出里会带一个**继续安装的链接**，点开完成剩余步骤 |

> **注意**：用「方式 B」传全了 App 参数建出来的 connection 直接就是 `COMPLETE`；用「方式 A」的浏览器流程，建完后 `installationState` 可能还是非 `COMPLETE`，需要点它给的链接补完。

#### 7.3.6 建 repository + trigger

```bash
gcloud builds repositories create my-repo \
  --connection=my-ghe-conn \
  --region=asia-northeast1 \
  --remote-uri=https://ghe.corp.internal/<ORG>/<REPO>.git

gcloud builds triggers create github \
  --name=ghe-build \
  --region=asia-northeast1 \
  --repository=projects/<PROJECT_ID>/locations/asia-northeast1/connections/my-ghe-conn/repositories/my-repo \
  --branch-pattern='^main$' \
  --build-config=cloudbuild.yaml \
  --service-account=projects/<PROJECT_ID>/serviceAccounts/gcb-builder@<PROJECT_ID>.iam.gserviceaccount.com
```

**和 GitHub.com 唯一的差别**：`--remote-uri` 用的是 **GHE 域名**，其余参数结构完全一致。

### 7.4 内网 GHE：网络怎么打通（GHE Server 的核心难点）

GHE Server 一般装在企业内网，Google 的机器访问不到。**两个方向要分别打通**：

```
方向 ①  Cloud Build 控制面  ──拉源码──▶  GHE 实例
         （Google → 你的内网）        需要：Service Directory / PSC / 公网暴露

方向 ②  GHE 实例  ──推 webhook──▶  Cloud Build 接收端点
         （你的内网 → Google）        需要：GHE 出网能到 cloudbuild.googleapis.com
```

> **只通一个方向**的典型症状：
> - 只有 ① 通 → **代码能拉到，但 push 不触发**（因为 webhook 送不出去）
> - 只有 ② 通 → **push 能触发，但 build 拉不到代码**

#### 7.4.1 方案 A：Service Directory（官方推荐）

Service Directory 让 Google 的服务通过一个**受控的 IP 段**访问你 VPC 外的地址。

**关键事实**：Service Directory 访问 VPC 外主机使用固定 IP 段 **`35.199.192.0/19`**。
→ **你的防火墙必须放行这个段**，且该段要通过 **Cloud VPN / Cloud Interconnect** 路由回内网。

**Step 1 — 授权 Cloud Build 服务代理**

```bash
export PROJECT_NUMBER=$(gcloud projects describe <PROJECT_ID> --format="value(projectNumber)")
export CB_SA="service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com"

# 能看到 Service Directory 里的服务
gcloud projects add-iam-policy-binding <SDS_PROJECT_ID> \
  --member="serviceAccount:${CB_SA}" --role="roles/servicedirectory.viewer"

# 能通过 PSC 访问网络资源
gcloud projects add-iam-policy-binding <NETWORK_PROJECT_ID> \
  --member="serviceAccount:${CB_SA}" --role="roles/servicedirectory.pscAuthorizedService"
```

> 报 `service account not found`？说明 Cloud Build 服务代理还没被创建，去 IAM 页面手动建一下。

**Step 2 — 建 namespace / service / endpoint**

```bash
# namespace 的 location 必须与 connection 的 region 一致
gcloud service-directory namespaces create my-ns \
  --location=asia-northeast1 --project=<SDS_PROJECT_ID>

gcloud service-directory services create ghe-svc \
  --namespace=my-ns --location=asia-northeast1

gcloud service-directory endpoints create ghe-ep \
  --namespace=my-ns \
  --service=ghe-svc \
  --location=asia-northeast1 \
  --address=<GHE_INSTANCE_IP> \
  --port=443 \
  --network=projects/<NETWORK_PROJECT_ID>/locations/global/networks/<NETWORK>
```

**Step 3 — 建 connection 时带上 Service Directory + 自签 CA**

```bash
gcloud builds connections create github-enterprise my-ghe-conn \
  --project=<PROJECT_ID> \
  --region=asia-northeast1 \
  --host-uri=https://ghe.corp.internal \
  --service-directory-service=projects/<SDS_PROJECT_ID>/locations/asia-northeast1/namespaces/my-ns/services/ghe-svc \
  --ssl-ca-file=./ghe-ca.pem \
  --app-id=<APP_ID> --app-slug=<APP_SLUG> --app-installation-id=<INSTALLATION_ID> \
  --private-key-secret-version=projects/<PROJECT_ID>/secrets/ghe-app-private-key/versions/1 \
  --webhook-secret-secret-version=projects/<PROJECT_ID>/secrets/ghe-webhook-secret/versions/1
```

**证书要求**：自签 CA 文件**不超过 10 KB**，格式为 PEM（`.pem` / `.cer` / `.crt`）。留空则用默认 CA 集合。

#### 7.4.2 方案 B：用内部负载均衡器

如果 `35.199.192.0/19` 路由不过去，可以起一个**内部 LB**（HTTPS 或 TCP）指向 GHE：

- Service Directory endpoint 的 `--address` 填 **LB 转发规则的 IP**（而不是 GHE 实例 IP）
- TCP LB 时**不需要** SSL 证书的私钥
- HTTPS LB 时需要 **hybrid connectivity NEG**（混合连接网络端点组）指向 GHE

#### 7.4.3 方案 C：Private Pool（只解决「构建」不解决「拉源码」）

要在内网里**跑构建**（比如访问内网 Maven/Nexus registry），需要建 **Private Pool**：

```bash
gcloud builds worker-pools create my-pool \
  --region=asia-northeast1 \
  --network=projects/<NETWORK_PROJECT_ID>/locations/global/networks/<NETWORK> \
  --subnet=projects/<NETWORK_PROJECT_ID>/regions/asia-northeast1/subnetworks/<SUBNET>
```

然后在 `cloudbuild.yaml` 里指定：

```yaml
options:
  pool:
    name: projects/<PROJECT_ID>/locations/asia-northeast1/workerPools/my-pool
```

> ⚠️ **易混点**：
> - **Private Pool** 管的是「**构建 VM 在哪、能访问什么内网资源**」——它**不影响源码拉取**（拉源码是 Cloud Build **控制面**做的，不在构建 VM 上）。
> - **Service Directory** 管的是「**控制面能不能访问 GHE**」。
> - 两者是**正交的**，内网 GHE 场景通常**两个都要配**。

### 7.5 路线 A'：1st gen + GitHub Enterprise

1st gen 为 GHE 提供了一个**独立资源类型** `githubEnterpriseConfigs`：

```
projects/{project_id}/locations/{location_id}/githubEnterpriseConfigs/{config_id}
```

里面记录「Cloud Build 怎么访问你的 GHE」：host URI、OAuth client id/secret、webhook URL + secret、App 安装信息。

**配置流程**

1. **GHE 上建 OAuth App**（用于授权）：`Settings → Developer settings → OAuth Apps → New OAuth App`，填 Cloud Build 的 homepage 与 callback URL，拿到 Client ID / Client Secret。
2. **GHE 上建 GitHub App**（用于收事件）：权限和事件同 §7.3.3，Webhook URL 填 `https://cloudbuild.googleapis.com/v2/projects/{PROJECT_NUMBER}/locations/{REGION}/connections:processWebhook`，生成并保存私钥与 webhook secret。
3. **控制台建 Enterprise Config**：`Cloud Build → Settings → Connections → Add connection → GitHub Enterprise`，填 GHE 地址、client id/secret、webhook secret、CA 证书。
4. **在 GHE 上安装 App**（org owner 账号）。
5. **建 trigger**（注意参数组变了）：

```bash
gcloud builds triggers create github \
  --name=ghe-build \
  --region=global \
  --repo-owner=<GHE_ORG> \
  --repo-name=<REPO> \
  --enterprise-config=projects/<PROJECT_ID>/locations/global/githubEnterpriseConfigs/<CONFIG_ID> \
  --branch-pattern='^main$' \
  --build-config=cloudbuild.yaml \
  --service-account=projects/<PROJECT_ID>/serviceAccounts/gcb-builder@<PROJECT_ID>.iam.gserviceaccount.com
```

> ⚠️ `--enterprise-config` **必须与 `--repo-owner/--repo-name` 成对使用**（gcloud 的参数组就是这么约束的）。
>
> ⚠️ **1st gen 没有对应的 gcloud 命令** —— `githubEnterpriseConfigs` 只能在**控制台**或 **REST API** 创建。

**1st vs 2nd gen 在 GHE 场景下的取舍**

| | 1st gen + GHE | 2nd gen + GHE |
| :--- | :--- | :--- |
| 配置入口 | 控制台为主（无 gcloud 命令） | **全 gcloud / Terraform** |
| 私钥保管 | Google 侧 | **你的 Secret Manager**（可轮换、可审计） |
| 内网支持 | 有限 | **Service Directory / 自签 CA / PSC 全支持** |
| 私有仓库管理 | 靠 GHE 自己 | 可在 Cloud Build 控制台统一管 |
| **建议** | 只在「完全内网 + 无 DevOps 团队 + 想快速跑通」时用 | **生产环境一律走这个** |

### 7.6 GHE 特有的坑（速查表）

| 现象 | 根因 | 处理 |
| :--- | :--- | :--- |
| **push 不触发，但代码能拉到** | webhook 方向（GHE → Google）不通 | 放行 GHE 出网到 `cloudbuild.googleapis.com`；或用中转 |
| **触发了但拉不到源码（超时）** | 拉源码方向（Google → GHE）不通 | Service Directory / PSC / 公网暴露；检查防火墙放行 `35.199.192.0/19` |
| `installationState` 不是 `COMPLETE` | App 没装完 / SAML 授权没过 | 看 describe 输出里的链接，点开补完 |
| `x509: certificate signed by unknown authority` | GHE 用自签 CA | `--ssl-ca-file=ca.pem`（≤10KB，PEM） |
| `x509: certificate is valid for X, not Y` | `--host-uri` 与证书 SAN 不匹配 | 改用证书里的域名做 host-uri |
| webhook 收不到事件 | webhook URL 的 REGION 与 connection region 不一致 | 两者必须一致 |
| webhook 返回 401/403 | webhook secret 不一致 | GHE 上 App 的 secret 与 Secret Manager 里的版本要对上 |
| 拉源码报 permission denied（App 已装） | 只装了 org 没勾具体 repo | GHE 上重装 App 时**选中 repo** |
| App 安装报 SAML 相关错 | GHE 启用了 SAML SSO，安装 App 需域账号授权 | 用 org owner 域账号装，或在 GHE 管理后台配 SAML group 权限 |
| 私钥相关报错 | 用了 SSH key 而非 RSA PEM | 要 **PEM 格式的 RSA 私钥**（`-----BEGIN RSA PRIVATE KEY-----`） |
| 私钥过期后连接失效 | GHE App 私钥有有效期 | 生成新 key → 更新 Secret 版本 → 重建/更新 connection |
| `Manual trigger` / `Pub/Sub trigger` 对 GHE 无效 | **官方限制**：这两种 trigger 无法通过 Cloud Build 集成构建 GHE 仓库 | 改用 push / PR trigger；或用 inline build config 自己 clone |
| 建 repository 报找不到 | region 不一致 | connection / repository / trigger **三者同区** |
| SA 报 `secretmanager` 权限错 | Cloud Build 服务代理没有读私钥的权限 | 给两个 secret 加 `roles/secretmanager.secretAccessor` |
| Private Pool 里构建失败 | trigger region 与 Private Pool region 不一致 | 两者必须同区 |

### 7.7 GHE 场景 checklist

**网络**

- [ ] 确认形态：GHE Cloud 还是 GHE Server
- [ ] GHE 实例能被 Google 访问（公网 / Service Directory / PSC 三选一）
- [ ] 防火墙放行 `35.199.192.0/19`（走 Service Directory 时）
- [ ] `35.199.192.0/19` 已通过 Cloud VPN / Interconnect / LB 路由到 GHE
- [ ] GHE 能出网到 `cloudbuild.googleapis.com`（webhook 方向）
- [ ] 需要内网构建资源时，Private Pool 已建且 region 与 trigger 一致

**凭据与 App**

- [ ] GHE 上 GitHub App 已创建，权限 / 事件按 §7.3.3 配好
- [ ] Webhook URL 的 region 与 connection region 一致
- [ ] App 已安装到 org，**且勾选了目标 repo**
- [ ] App ID / slug / installation ID 已记录
- [ ] 私钥（PEM）与 webhook secret 已存 Secret Manager
- [ ] Cloud Build 服务代理对这两个 secret 有 `roles/secretmanager.secretAccessor`
- [ ] 自签 CA 已准备（≤10KB，PEM）

**GCP 侧**

- [ ] `gcloud builds connections describe` → `installationState = COMPLETE`
- [ ] repository 的 `--remote-uri` 用的是 GHE 域名
- [ ] connection / repository / trigger 三者 region 一致
- [ ] build SA 有 `roles/developerconnect.connectionUser`
- [ ] Cloud Build 服务代理有 `roles/servicedirectory.viewer` + `roles/servicedirectory.pscAuthorizedService`

**验证**

- [ ] 手动 `gcloud builds triggers run` 能成功
- [ ] push 能触发（说明 webhook 方向通）
- [ ] build 能拉到源码（说明拉取方向通）
- [ ] PR 页面有 Cloud Build check status

### 7.8 用 Terraform 管理 GHE connection（IaC 场景）

GHE 的 connection 涉及 3 个 secret + 2 条 IAM，最适合用 Terraform 一次性搞定：

```hcl
terraform {
  required_providers {
    google = {}
  }
}

locals {
  cb_service_agent = "service-${var.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# ── 私钥 secret ────────────────────────────────
resource "google_secret_manager_secret" "private_key" {
  project   = var.project_id
  secret_id = "ghe-app-private-key"
  replication { auto {} }
}

resource "google_secret_manager_secret_version" "private_key" {
  secret      = google_secret_manager_secret.private_key.id
  secret_data = file("private-key.pem")
}

# ── webhook secret ─────────────────────────────
resource "google_secret_manager_secret" "webhook_secret" {
  project   = var.project_id
  secret_id = "ghe-webhook-secret"
  replication { auto {} }
}

resource "google_secret_manager_secret_version" "webhook_secret" {
  secret      = google_secret_manager_secret.webhook_secret.id
  secret_data = var.ghe_webhook_secret
}

# ── 授权 Cloud Build 服务代理读 secret ──────────
data "google_iam_policy" "sa_secret_accessor" {
  binding {
    role    = "roles/secretmanager.secretAccessor"
    members = ["serviceAccount:${local.cb_service_agent}"]
  }
}

resource "google_secret_manager_secret_iam_policy" "pk" {
  project      = var.project_id
  secret_id    = google_secret_manager_secret.private_key.secret_id
  policy_data  = data.google_iam_policy.sa_secret_accessor.policy_data
}

resource "google_secret_manager_secret_iam_policy" "whs" {
  project      = var.project_id
  secret_id    = google_secret_manager_secret.webhook_secret.secret_id
  policy_data  = data.google_iam_policy.sa_secret_accessor.policy_data
}

# ── GHE connection ──────────────────────────────
resource "google_cloudbuildv2_connection" "ghe" {
  project  = var.project_id
  location = var.region
  name     = "my-ghe-conn"

  github_enterprise_config {
    host_uri                       = var.ghe_host_uri
    private_key_secret_version    = google_secret_manager_secret_version.private_key.id
    webhook_secret_secret_version = google_secret_manager_secret_version.webhook_secret.id
    app_id                         = var.ghe_app_id
    app_slug                       = var.ghe_app_slug
    app_installation_id            = var.ghe_installation_id
  }

  depends_on = [
    google_secret_manager_secret_iam_policy.pk,
    google_secret_manager_secret_iam_policy.whs,
  ]
}

# ── repository ─────────────────────────────────
resource "google_cloudbuildv2_repository" "repo" {
  project           = var.project_id
  name              = "my-repo"
  location          = var.region
  parent_connection = google_cloudbuildv2_connection.ghe.name
  remote_uri        = var.ghe_repo_uri
}
```

> **私钥轮换**：换 key 时只需更新 `google_secret_manager_secret_version`（新增一个版本），然后 `terraform apply` 重建 connection 即可 —— 这正是 2nd gen 把凭据放 Secret Manager 的价值。

---

## 8. 构建配置与产物落地：镜像 / JAR 分别推到哪

### 8.1 Artifact Registry 仓库类型速查

| 你要存的东西 | AR 仓库类型 | 创建命令 | 仓库地址 | 推送方式 |
| :--- | :--- | :--- | :--- | :--- |
| Docker 镜像 | `docker` | `--repository-format=docker` | `R-docker.pkg.dev/PROJECT/REPO` | `docker push` |
| **JAR / WAR（Maven）** | `maven` | `--repository-format=maven` | `R-maven.pkg.dev/PROJECT/REPO` | `mvn deploy` |
| npm 包 | `npm` | `--repository-format=npm` | `R-npm.pkg.dev/PROJECT/REPO` | `npm publish` |
| Python 包 | `python` | `--repository-format=python` | `R-python.pkg.dev/PROJECT/REPO` | `twine upload` |
| 任意文件 | `generic` | `--repository-format=generic` | `R-maven/…-generic.pkg.dev/PROJECT/REPO` | `gcloud storage cp` |

> 你说的「把 Image 推送到对应的 JAR 里面」——严格讲是推到 **Artifact Registry**（简称 AR）。下面 7.2 给镜像、7.3 给真的 JAR 产物，两条都覆盖。

### 8.2 形态 ①：构建镜像 → 推 Artifact Registry（最常见）

```yaml
# cloudbuild.yaml —— 放 repo 根目录
steps:
  # 1) 测试（可选）
  - name: 'node:20'
    id: 'test'
    dir: 'app/'
    script: |
      npm ci
      npm test

  # 2) 构建镜像
  - name: 'gcr.io/cloud-builders/docker'
    id: 'build'
    args:
      - 'build'
      - '-t'
      - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:$COMMIT_SHA'
      - '-t'
      - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:latest'
      - '.'

  # 3) 推送
  - name: 'gcr.io/cloud-builders/docker'
    id: 'push'
    args:
      - 'push'
      - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:$COMMIT_SHA'
      - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:latest'
    waitFor: ['build']

# images: 里列出来的镜像，Cloud Build 会在构建后自动 push
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

**三条硬规则**：

1. `images:` 里列了 → Cloud Build **自动 push**。不在 `images:` 里，即使 step 里 push 了也能成功，但语义不清晰，且 **`$COMMIT_SHA` 之外的隐式行为不成立**。
2. **tag 用 `$COMMIT_SHA`**，不要只打 `latest` —— `latest` 会被覆盖，无法回溯。
3. **不要在同一个 trigger 里既 build 又 deploy 生产**。生产发布应该拆成 Cloud Deploy（见 §11）。

现成模板：[`examples/docker-to-cloudrun.yaml`](examples/docker-to-cloudrun.yaml)、[`examples/nodejs-test-deploy.yaml`](examples/nodejs-test-deploy.yaml)。

### 8.3 形态 ②：构建 JAR → 推 Artifact Registry Maven 仓库

如果你说的「JAR」是指 Java 包本身（不是镜像），那产物落地是 AR 的 **Maven 仓库**：

```bash
gcloud artifacts repositories create my-app-maven \
  --repository-format=maven \
  --location=asia-northeast1 \
  --description="my-app jars"
```

```yaml
steps:
  # 1) 打包 jar
  - name: 'gcr.io/cloud-builders/mvn'
    id: 'mvn'
    args:
      - '-B'
      - '-DskipTests'
      - 'package'
    env:
      - 'MAVEN_OPTS=-Dmaven.repo.local=/workspace/.m2'

  # 2) 发布到 AR Maven 仓库
  - name: 'gcr.io/cloud-builders/mvn'
    id: 'deploy'
    args:
      - 'org.apache.maven.plugins:maven-deploy-plugin:3.1.1:deploy'
      - '-Durl=https://${_REGION}-maven.pkg.dev/$PROJECT_ID/${_REPO}'
      - '-DrepositoryId=artifact-registry'
      - '-DaltDeploymentRepository=artifact-registry::default::${_REGION}-maven.pkg.dev/$PROJECT_ID/${_REPO}'
    waitFor: ['mvn']

substitutions:
  _REGION: 'asia-northeast1'
  _REPO: 'my-app-maven'
```

关键点：

- AR Maven 仓库必须用**标准 Maven 布局**（`groupId/artifactId/version/`）。所以 `pom.xml` 的 `<groupId>` / `<artifactId>` / `<version>` 决定了 jar 落在仓库里的哪个路径 —— **版本号必须唯一**，重复发布会 409。
- AR Maven 仓库**不支持** snapshot 语义，需要每次发版改 `<version>`。
- 客户端从 AR 拉包需要 `settings.xml` 认证：
  ```bash
  gcloud auth configure-maven \
    --repository-url=https://asia-northeast1-maven.pkg.dev/<PROJECT_ID>/my-app-maven \
    --username=oauth2accesstoken \
    --password=$(gcloud auth print-access-token)
  ```
- 拉取权限：`roles/artifactregistry.reader`；推送权限：`roles/artifactregistry.writer`。

现成模板：[`examples/java-maven.yaml`](examples/java-maven.yaml)。

### 8.4 形态 ③：一个 build 同时出镜像 + JAR

```yaml
steps:
  - name: 'gcr.io/cloud-builders/mvn'
    id: 'mvn'
    args: ['-B', 'package', '-DskipTests']

  # 把 jar 塞进镜像（Dockerfile 里 COPY target/*.jar app.jar）
  - name: 'gcr.io/cloud-builders/docker'
    id: 'docker'
    args:
      - 'build'
      - '-t'
      - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:$COMMIT_SHA'
      - '.'

  # 同时把 jar 本身也发到 AR Maven 仓库
  - name: 'gcr.io/cloud-builders/mvn'
    id: 'mvn-deploy'
    args:
      - 'org.apache.maven.plugins:maven-deploy-plugin:3.1.1:deploy'
      - '-Durl=https://${_REGION}-maven.pkg.dev/$PROJECT_ID/${_REPO}'
      - '-DrepositoryId=artifact-registry'
      - '-DaltDeploymentRepository=artifact-registry::default::${_REGION}-maven.pkg.dev/$PROJECT_ID/${_REPO}'
    waitFor: ['mvn']

  - name: 'gcr.io/cloud-builders/docker'
    id: 'docker-push'
    args:
      - 'push'
      - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:$COMMIT_SHA'
    waitFor: ['docker']

images:
  - '${_REGION}-docker.pkg.dev/$PROJECT_ID/${_REPO}/${_SERVICE}:$COMMIT_SHA'
```

---

## 9. IAM 身份全景表

一条完整链路跑通，**下面每一行都要对**。少一行就会在某个特定环节报 `PERMISSION_DENIED`。

### 9.1 人的角色（操作者）

| 角色 | 干什么 | 需要 |
| :--- | :--- | :--- |
| `roles/cloudbuild.builds.editor` | 跑 build、管 trigger | ✅ |
| `roles/iam.serviceAccountUser` | 让 trigger / build 冒用指定 SA | ✅（指定 build SA 时必需） |
| `roles/developerconnect.connectionAdmin` | 建/删 connection（仅 2nd gen） | 路线 B |
| `roles/developerconnect.connectionUser` | 用 connection 建 trigger | 路线 B |
| `roles/artifactregistry.writer` | 手动推镜像 | 视情况 |
| `roles/serviceusage.serviceUsageAdmin` | 启用 API | 只需一次 |
| `roles/iam.serviceAccountAdmin` | 建 SA | 只需一次 |

### 9.2 Build Service Account（构建时用）

| 角色 | 干什么 | 是否必需 |
| :--- | :--- | :--- |
| `roles/logging.logWriter` | 写构建日志 | ✅ |
| `roles/storage.objectUser` | 往 `gs://{PROJECT}_cloudbuild/source` 写源码包 | ✅ |
| `roles/storage.bucketViewer` | 读日志桶 | ✅ |
| `roles/artifactregistry.writer` | 推镜像 / 发 Maven 包 | ✅（有产物时） |
| `roles/secretmanager.secretAccessor` | 读 Secret Manager 里的敏感值 | 需要密钥时 |
| `roles/run.admin` / `roles/container.developer` | 部署到 Cloud Run / GKE | 部署时 |
| `roles/developerconnect.connectionUser` | 拉源码（2nd gen） | 路线 B 必查 |

### 9.3 Developer Connect Connection SA（路线 B）

| 角色 | 干什么 |
| :--- | :--- |
| `roles/developerconnect.serviceAgent` | Developer Connect 托管 GitHub App 凭据、拉源码、写状态桶 |
| `roles/developerconnect.privateServiceAgent` | 走 Private Pool / 私网时额外需要 |

### 9.4 GHE 场景额外需要的角色（§7）

| 授予对象 | 角色 | 干什么 | 不配的后果 |
| :--- | :--- | :--- | :--- |
| **Cloud Build 服务代理** | `roles/secretmanager.secretAccessor`（**授权在具体的 secret 上**，不是项目级） | 读 App 私钥 + webhook secret | connection 建得出来但拉源码 / 收 webhook 失败 |
| **Cloud Build 服务代理** | `roles/servicedirectory.viewer` | 读取 Service Directory 里的 GHE 服务 | 找不到 GHE 地址 |
| **Cloud Build 服务代理** | `roles/servicedirectory.pscAuthorizedService` | 通过 PSC 访问网络资源 | 能看到服务但连不上 |
| **Build SA / 触发器创建者** | `roles/developerconnect.connectionUser` | 用 connection 拉源码 | 触发后拉代码 403 |

> 前三条都是授给 **`service-{PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com`**，不是你的 build SA —— 很容易搞错授错对象。详细命令见 §7.4.1。

### 9.5 系统身份（不用你管，但要知道是谁）

| 身份 | 干什么 |
| :--- | :--- |
| `service-{PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com` | Cloud Build 服务代理：建 GCS 源码桶、生成 provenance attestation、创建构建资源 |
| `{PROJECT_NUMBER}@system.gserviceaccount.com` | **旧的默认构建 SA**（带 Editor 权限）—— **别用**，换掉它 |

---

## 10. GitHub 场景下的内置 substitutions

这些变量由 Cloud Build 在**触发时**注入，GitHub 场景下最有用的：

| 变量 | 值 | 用途 |
| :--- | :--- | :--- |
| `$COMMIT_SHA` | 完整 40 位 commit SHA | **打镜像 tag 首选**（可追溯、可回滚） |
| `$SHORT_SHA` | 前 7 位 | tag 名短一点 |
| `$BRANCH_NAME` | 分支名（**tag 触发时为空**） | `condition:` 分支判断 |
| `$TAG_NAME` | tag 名（仅 tag 触发） | 版本号发布 |
| `$REPO_NAME` | 仓库名 | 多仓库共用一套 config |
| `$REPO_OWNER` | 仓库 owner | 同上 |
| `$TRIGGER_NAME` | trigger 名 | 区分多条 trigger |
| `$BUILD_ID` | build ID | 日志关联 |
| `$PROJECT_ID` / `$PROJECT_NUMBER` | 项目 | 拼镜像地址 |
| `$REVISION_ID` | 修订 ID | 一般用不上 |
| `_XXX` | **自定义**（必须 `_` 开头） | 环境/仓库名等 |

**几个容易踩的点**：

1. **PR 触发时 `$COMMIT_SHA` 是 merge commit 的 SHA**，不是 PR head 的 SHA。想拿 PR head，用 `$TRIGGER_BUILD_CONFIG_PATH`? 不对 —— 正确的是 PR 场景用 `pull_request` 事件时另建一个专用 trigger，或者用 `options.substitutionOption: ALLOW_LOOSE` + 自定义 substitution 传入 head SHA。
2. **`$BRANCH_NAME` 在 tag trigger 里是空字符串** → 用它做 `condition` 会全 false。
3. **runtime 不能新增 substitution key**：`gcloud builds triggers run --substitutions=_NEW=xxx` 只有在 trigger 定义时已有 `_NEW` 才有效，否则报错。
4. **自定义 substitution 必须带 `_` 前缀**，否则被忽略。

---

## 11. 生产化加固清单

### 11.1 触发与审批

```bash
gcloud builds triggers create github \
  ... \
  --require-approval=true          # 生产 trigger 必须开
```

- **生产 trigger 开 `--require-approval`**：build 进 `QUEUED` 等人点确认。
- **PR 触发器配 `--comment-control`**：PR 作者要打 `/gcbrun` 才跑（需要 GitHub App 的写权限）。
- **dev/staging/prod 用不同 trigger**，靠 `condition:` 或不同 substitution 区分，**不要用同一份 config 硬编码环境**。

```yaml
steps:
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: gcloud
    args: ['run', 'deploy', '${_SERVICE}', '--image=...:$COMMIT_SHA', '--quiet']
    condition: '$BRANCH_NAME == "main" && $_ENV == "prod"'
```

### 11.2 PR / 不可信代码的安全

**从 fork 来的 PR 是最大的攻击面**：PR 作者可以改 `cloudbuild.yaml` 和 `Dockerfile` 来偷你的 SA 凭据。

| 措施 | 说明 |
| :--- | :--- |
| **PR trigger 用独立的低权限 SA** | 只给 `artifactregistry.writer`（写到临时仓库）+ `logging.logWriter`，不给 Secret、不给部署权限 |
| **不触发部署的分支** | `condition` 挡住 `main` 以外的部署 |
| **不暴露 Secret 给 PR** | PR trigger 用**不含 secret substitution** 的 config |
| **禁止 `sh` 步骤跑不可信脚本** | 尽量用固定 builder 镜像 + 受控 args |
| **考虑 Private Pool** | 构建跑在 VPC 内，能挡外网，也能接内网 registry |

> 完整讨论见 [how-to-autofix-cve-with-cloud-build.md](how-to-autofix-cve-with-cloud-build.md) 里的规则 3。

### 11.3 产物不可变与可追溯

| 措施 | 怎么做 |
| :--- | :--- |
| **tag 用 `$COMMIT_SHA`** | 每个 commit 唯一 tag，永不覆盖 |
| **关闭 AR 的 mutable tag** | AR Docker 仓库设置里禁用可变 tag（Terraform：`docker_config { mutable_tags { enabled = false } }`） |
| **部署用 digest 不用 tag** | `--image=R-docker.pkg.dev/P/R/I@sha256:...`，杜绝 tag 漂移 |
| **启用 provenance** | Cloud Build 构建并推送镜像时会生成构建来源证明 attestation，可配 Binary Authorization 强制校验 |
| **GAR 清理策略** | 给仓库配 cleanup policy（按 tag / 天数），避免仓库无限膨胀 |

### 11.4 密钥管理

```bash
# 敏感值放 Secret Manager，不要放 substitution
gcloud secrets create my-db-password --data-file=./secret.txt

# build SA 需要读权限
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:gcb-builder@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

在 `cloudbuild.yaml` 里通过环境变量读取：

```yaml
env:
  - 'DB_PASSWORD=$(gcloud secrets versions access latest --secret=my-db-password)'
```

> **substitution 会被写进日志和构建元数据**，**绝不要把密码放在 `_XXX` 里**。

### 11.5 成本与配额

| 项 | 值 |
| :--- | :--- |
| 免费额度 | 每个 billing account **每月 2,500 build-minute**（**仅 `e2-standard-2` 机型**） |
| 单价 | `e2-standard-2` ≈ $0.006/分钟（以官方 pricing 页为准），**排队不计费**，出流量另计 |
| Default Pool 并发 | 10（可申请到 30） |
| 单构建 step 上限 | 300 |
| 省钱手段 | Docker layer cache、选对 machineType、PR 只做 test 不 build 镜像、`timeout` 设小一点 |

### 11.6 监控告警

```bash
# 失败的 build
gcloud builds list --filter='status=FAILURE' --region=asia-northeast1 --limit=20
```

建议加一条 Cloud Monitoring 告警：build 失败率 > X% 或连续 N 次失败。

---

## 12. 排错手册

> **代码在 GitHub Enterprise Server？** 先看 **[§7.6 GHE 特有的坑](#7-场景变体github-企业版github-enterprise)**——那里的症状表专治「代码能拉到但 push 不触发」「触发了但拉不到源码」这类双向网络问题。

### 12.1 分层定位法（别瞎试）

```
第 1 层：build 都没被创建？
   → 问题在 GitHub → Cloud Build 的 webhook 通路
     检查：connection 状态 / trigger region / branch-pattern / App 权限
        ↓ 有 build 了
第 2 层：build 创建了但拉不到源码？
   → 问题在"身份授权"
     检查：App 的 Contents 权限 / 2nd gen 的 connectionUser / repo 是否在授权列表
        ↓ 源码拉到了
第 3 层：step 跑失败了？
   → 问题在构建本身
     检查：cloudbuild.yaml / Dockerfile / SA 角色 / 网络出口
        ↓ 构建成功
第 4 层：产物没落地？
   → 问题在推送
     检查：images: 声明 / artifactregistry.writer / AR 仓库格式
```

### 12.2 症状对照表

| 现象 | 根因 | 处理 |
| :--- | :--- | :--- |
| **push 了但没有 build** | App 没装 / 没授权到这个 repo | GitHub → Settings → Developer settings → GitHub Apps → 检查安装范围 |
| **push 了但没有 build** | `branch-pattern` 正则不匹配 | `^main$` 只匹配 `main`；`main` 会匹配 `main`、`main-hotfix` |
| **push 了但没有 build** | trigger region 和 connection region 不一致（2nd gen） | 三者统一 region |
| **build 创建了但立刻失败** | build SA 权限不足 | `gcloud builds describe <ID>` 看具体 denied 的资源，补角色 |
| **拉源码 403/404** | App 只有 Metadata 权限 | 补 Contents: read；私有 repo 还要确认 App 在 org 内安装 |
| **拉源码 403（2nd gen）** | 缺 `roles/developerconnect.connectionUser` | 给 build 执行身份加上 |
| **构建成功但镜像没推上去** | `images:` 没声明 | 加进 `images:` |
| **`docker push` denied** | 缺 `roles/artifactregistry.writer` | 补角色 |
| **mvn deploy 409** | 版本号已存在 | 换 `<version>`（AR Maven 不支持 snapshot 语义） |
| **构建一直 QUEUED** | 并发配额用尽 | `gcloud builds list` 看排队；提配额 |
| **trigger region 改不了** | **创建后不可变** | 删了重建（注意 2nd gen 要重建 connection/repository/trigger 三层） |
| **substitution 传不进去** | runtime 不能新增 key | 只能覆盖 trigger 里已定义的 `_XXX` |
| **部署步骤没执行** | `condition` 不匹配 | `$BRANCH_NAME` 在 tag trigger 里为空；PR 场景字段不同 |
| **私有 Maven 仓库拉不到** | 客户端没配 `settings.xml` | `gcloud auth configure-maven` |
| **App 报 "This app is not authorized"** | App 被 owner 撤销 | 重新授权 |

### 12.3 三板斧

```bash
gcloud builds describe <BUILD_ID> --region=<REGION>   # 每个 step 的 status / exitCode / timing
gcloud builds log <BUILD_ID> --region=<REGION>          # 完整 stdout/stderr
gcloud builds list --filter='status=FAILURE' --region=<REGION>

# trigger 层
gcloud builds triggers describe <NAME> --region=<REGION>
gcloud builds triggers list --region=<REGION>

# 2nd gen 层
gcloud builds connections describe <CONN> --region=<REGION>
gcloud builds repositories describe <REPO> --region=<REGION>
gcloud builds repositories list --region=<REGION>
```

### 12.4 在 GitHub 侧看

- **PR / commit 页面上的状态检查**：能看到 Cloud Build 的 check status → 说明 webhook **已经送到**，问题在 Cloud Build 侧。
- **完全没有状态检查** → webhook 根本没送出去 → 问题在 App 安装 / 授权 / region。
- **Settings → Developer settings → GitHub Apps** → 能看到 Cloud Build / Developer Connect 装在哪个 org、授权了哪些 repo、权限是什么。

---

## 13. 端到端验收 checklist

按顺序打勾，全绿就说明整条链路打通了。

**A. 基础能力**

- [ ] `gcloud services list --enabled | grep -E 'cloudbuild|artifactregistry'` → 三个 API 都在
- [ ] 项目已绑定 billing account
- [ ] Artifact Registry 仓库已建（docker / maven，按需）
- [ ] 专用 build SA 已建，且**不是** `{PROJECT_NUMBER}@system.gserviceaccount.com`
- [ ] build SA 有：logging.logWriter、storage.objectUser、storage.bucketViewer、artifactregistry.writer
- [ ] 你的账号有 iam.serviceAccountUser

**B. 构建本身（不涉及 GitHub）**

- [ ] `gcloud builds submit --config cloudbuild.yaml` 成功
- [ ] `gcloud builds log` 里每个 step 都绿
- [ ] 产物在 AR 里能拉到：`gcloud artifacts docker images list ...` / `gcloud artifacts repositories describe`
- [ ] 镜像 tag 包含 `$COMMIT_SHA`

**C. GitHub 通路**

- [ ] GitHub 上能看到 Cloud Build / Developer Connect 的 App
- [ ] App 的授权范围**包含目标 repo**（不是只装了 org 没勾 repo）
- [ ] App 权限里有 Contents: Read-only
- [ ] `gcloud builds connections describe`（2nd gen）→ state = ACTIVE
- [ ] `gcloud builds repositories list` 能看到你的 repo
- [ ] `gcloud builds triggers describe` → repo / branch-pattern / service-account / substitution 全部正确

**D. 端到端**

- [ ] 往 main push 一次 → `gcloud builds list` 里出现新 build
- [ ] `gcloud builds describe` 里 `SUBSTITUTION` 段能看到 `$COMMIT_SHA` 被替换成真实 SHA
- [ ] PR 页面显示 Cloud Build 的 check status（走 PR trigger 时）
- [ ] 镜像在 AR 里存在且 tag = commit SHA
- [ ] 失败时能查到日志；失败 build 有告警

**E. 安全加固（上线前）**

- [ ] 生产 trigger 开了 `--require-approval`
- [ ] PR trigger 用独立的低权限 SA
- [ ] 没有把密码放在 substitution 里
- [ ] 部署用 digest 而不是 tag
- [ ] AR 仓库配了 cleanup policy

**F. GitHub Enterprise 场景（仅 GHE Server 需要）**

见 §7.7 的完整清单，核心三件事：

- [ ] **拉源码方向通**：Cloud Build → GHE（Service Directory / PSC / 公网）
- [ ] **webhook 方向通**：GHE → `cloudbuild.googleapis.com`
- [ ] `gcloud builds connections describe` → `installationState = COMPLETE`

---

## 14. 官方文档

### 基础

- Cloud Build 总览：https://cloud.google.com/build/docs/overview
- 自动化触发器（总入口）：https://cloud.google.com/build/docs/automate-builds
- Build config schema：https://cloud.google.com/build/docs/build-config
- Cloud Builders 列表：https://cloud.google.com/build/docs/cloud-builders
- IAM 角色参考：https://cloud.google.com/build/docs/access-control
- 区域与配额：https://cloud.google.com/build/locations ｜ https://cloud.google.com/build/quotas
- 定价：https://cloud.google.com/build/pricing

### GitHub / GitHub Enterprise（§4–§7）

| 主题 | 链接 |
| :--- | :--- |
| **GitHub.com：连接仓库（2nd gen）** | https://cloud.google.com/build/docs/automating-builds/github/connect-repo-github |
| **GitHub.com：从仓库构建（2nd gen）** | https://cloud.google.com/build/docs/automating-builds/github/build-repos-from-github |
| **GitHub.com：GitHub App 触发器（1st gen）** | https://cloud.google.com/build/docs/automating-builds/create-github-app-triggers |
| **GHE：连接主机（2nd gen）** | https://cloud.google.com/build/docs/automating-builds/github/connect-host-github-enterprise |
| **GHE：连接仓库（2nd gen）** | https://cloud.google.com/build/docs/automating-builds/github/connect-repo-github-enterprise |
| **GHE：从仓库构建（触发器）** | https://cloud.google.com/build/docs/automating-builds/github/build-repos-from-github-enterprise |
| **GHE：私有网络（Service Directory）** | https://cloud.google.com/build/docs/automating-builds/github/build-repos-from-github-enterprise-private-network |
| Developer Connect 概览 | https://cloud.google.com/developer-connect/docs/overview |
| Service Directory 概览 | https://cloud.google.com/service-directory/docs/overview |
| GitHub App 官方文档 | https://docs.github.com/en/apps |

### 产物

- AR 仓库总览：https://cloud.google.com/artifact-registry/docs/repositories
- AR Docker 仓库：https://cloud.google.com/artifact-registry/docs/docker
- **AR Java / Maven 仓库**：https://cloud.google.com/artifact-registry/docs/java/store-java
- AR Maven 认证：https://cloud.google.com/artifact-registry/docs/java/authentication
- AR 清理策略：https://cloud.google.com/artifact-registry/docs/repositories/cleanup-policy

### 供应链安全

- Binary Authorization：https://cloud.google.com/binary-authorization/docs/overview
- GitHub App 官方文档：https://docs.github.com/en/apps

### 配套阅读

- [cloudbuild-guide.md](cloudbuild-guide.md) —— Cloud Build 主文档（概念 / Schema / CLI / 配额 / 排错）
- [how-to-autofix-cve-with-cloud-build.md](how-to-autofix-cve-with-cloud-build.md) —— CVE 自动修复闭环（构建产物的供应链安全）
- [gcp-cloud-build-concepts.md](gcp-cloud-build-concepts.md) —— 英文概念全景（GitHub 集成 / Pipeline 集成 / 最佳实践）
- [examples/](examples/) —— 可直接改用的 `cloudbuild.yaml` 模板
