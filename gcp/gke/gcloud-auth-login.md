# gcloud auth login 自动化探索（Docker / CI / 无浏览器环境）

> **问题**：写 Dockerfile 时执行 `gcloud auth login` 会卡住——它需要弹浏览器、需要人工点确认、甚至需要二次验证（2FA / reCAPTCHA）。容器里既没有浏览器也没有人，那怎么做"自动化"？
>
> **结论先行**：`gcloud auth login` 这条路本身没有纯脚本化解法（OAuth 浏览器流程 + Google 人机校验）。但"用个人账号（user credentials）在 Docker/CI 里跑 gcloud"这个目标是可以做到的——只要把"登录动作"和"用凭据动作"解耦。
>
> 验证环境：Google Cloud SDK 526.0.1 (core 2025.06.10)，macOS。文中所有 `--help` 输出与运行结果均在本机实测。
>
> 📌 **实战篇**：若你要的是"在 Docker 里以个人账号跑 gcloud"，直接看 [gcloud-auth-login-docker.md](gcloud-auth-login-docker.md)（Jumpbox 模式：容器内交互授权 + 凭据落宿主机 + 后续容器免交互复用）。

---

## 目录

- [1. 根因：为什么 gcloud auth login 无法脚本化](#1-根因为什么-gcloud-auth-login-无法脚本化)
- [2. 认证方式全景图](#2-认证方式全景图)
- [3. 方案详解](#3-方案详解)
- [4. Docker 落地模板](#4-docker-落地模板)
- [5. 选型决策树](#5-选型决策树)
- [6. 安全红线](#6-安全红线)
- [7. 排错 FAQ](#7-排错-faq)
- [8. 参考](#8-参考)

---

## 1. 根因：为什么 gcloud auth login 无法脚本化

`gcloud auth login` 走的是 **OAuth 2.0 授权码流程（Authorization Code + PKCE）**。完整链路：

```
gcloud auth login
  ├─ 本地起临时端口 (loopback) 监听回调
  ├─ 打开浏览器 → accounts.google.com/o/oauth2/auth?client_id=32555940559...&code_challenge=...
  ├─ 人工输入账号密码 / 通过 2FA / 过 reCAPTCHA
  ├─ Google 回调 → 拿到 authorization code
  └─ code + code_verifier 换 refresh_token，写入 ~/.config/gcloud/credentials.db
```

实测 `--no-launch-browser` 打印出的 URL：

```
https://accounts.google.com/o/oauth2/auth?response_type=code
  &client_id=32555940559.apps.googleusercontent.com
  &redirect_uri=https%3A%2F%2Fsdk.cloud.google.com%2Fauthcode.html
  &scope=openid+...userinfo.email+...cloud-platform+...
  &state=...&code_challenge=...&code_challenge_method=S256
  &token_usage=remote&access_type=offline
```

不可自动化的三个硬点：

| 环节 | 为什么脚本搞不定 |
|---|---|
| **凭据输入** | 账号密码 / Passkey / 短信码，Google 不提供"服务账号密码登录"这种 API |
| **人机校验** | 登录页有 reCAPTCHA / reCAPTCHA Enterprise 风控，自动浏览器极易被判为 bot |
| **consent 授权** | 未授权过的应用需要在 consent 页点"允许"，作用域越大越敏感 |

> **结论**：不要试图"自动化 gcloud auth login"。要自动化的是**"让容器拿到一份可用的凭据"**。凭据一旦拿到，后续所有 gcloud 命令都是无状态的。

### 关键澄清：gcloud auth login 不是唯一入口

很多人误以为"gcloud 只能用登录"。实际上支持的凭据类型远不止一种：

```bash
gcloud auth login                                          # 用户凭据（OAuth，浏览器）
gcloud auth activate-service-account --key-file=key.json    # SA 密钥
gcloud auth login --cred-file=cred.json                     # 外部账号凭据 / SA 密钥（免交互）
gcloud auth login --login-config=login.json                 # Workforce 联邦（浏览器 SSO）
gcloud auth print-access-token                              # 打印 token
gcloud config set auth/credential_file_override=xx.json     # 直接指定凭据文件
export CLOUDSDK_AUTH_ACCESS_TOKEN=ya29...                   # 直接注入 token
```

---

## 2. 认证方式全景图

| # | 方案 | 交互性 | 密钥落地 | 适用场景 | 推荐度 |
|---|---|---|---|---|---|
| A | Service Account 密钥 (JSON) | 无 | 是（长期） | 自建 CI / 离线环境 | ⭐⭐ 需改进 |
| B | Workload Identity Federation | 无 | 否 | CI (GitHub/GitLab)、AWS、Azure、任意 OIDC | ⭐⭐⭐⭐⭐ |
| C | SA 模拟 (Impersonation) | 无 | 否 | 已有身份想换成 SA 权限 | ⭐⭐⭐⭐⭐ |
| D | Workforce Identity Federation | 浏览器 SSO | 否 | 企业员工/合作方登录 GCP | ⭐⭐⭐⭐ |
| E | 自有 OAuth Client + refresh_token | 首次人工 | 是（refresh token） | 想复用"个人身份"跑容器 | ⭐⭐⭐⭐ |
| F | Access Token 注入 | 无 | 否（短期） | 本机已登录，临时喂给容器 | ⭐⭐⭐ |
| G | 挂载 ~/.config/gcloud | 无 | 是（凭据库） | 本地开发容器 | ⭐⭐⭐ |
| H | `--no-launch-browser` / `--no-browser` | 半自动 | 否 | SSH 跳板机、无浏览器服务器 | ⭐⭐⭐ |
| I | Headless 浏览器自动点 | 全自动 | 是 | 一次性造凭据 | ⭐ 不推荐 |
| J | Metadata Server | 无 | 否 | GCE/GKE/Cloud Run/Cloud Build | ⭐⭐⭐⭐⭐ |

---

## 3. 方案详解

### 3.1 方案 A：Service Account 密钥（用户已知）

```bash
# 创建
gcloud iam service-accounts create ci-runner \
  --display-name="CI Runner" --project=my-proj

# 授权
gcloud projects add-iam-policy-binding my-proj \
  --member="serviceAccount:ci-runner@my-proj.iam.gserviceaccount.com" \
  --role="roles/developer"

# 下发密钥
gcloud iam service-accounts keys create ./key.json \
  --iam-account=ci-runner@my-proj.iam.gserviceaccount.com

# 使用
gcloud auth activate-service-account --key-file=./key.json
# 或（仅客户端库）
export GOOGLE_APPLICATION_CREDENTIALS=/path/key.json
```

**问题**：

- 密钥**长期有效**（最长 90 天，可手动禁用），一旦泄漏 = 权限泄漏，无法追溯具体调用方
- 审计日志里全是同一个 SA，区分不出"谁在用"
- Google 已明确推动"无密钥"方向（组织策略可禁用 SA key 创建）

**改进（同一个 SA，零密钥）**：

```bash
# 让调用方只持有"生成 token"权限，而不是持有密钥
gcloud iam service-accounts add-iam-policy-binding \
  ci-runner@my-proj.iam.gserviceaccount.com \
  --role="roles/iam.serviceAccountTokenCreator" \
  --member="serviceAccount:my-caller@my-proj.iam.gserviceaccount.com"

# 调用方（已有任意身份）直接换 token
gcloud auth print-access-token --impersonate-service-account=ci-runner@my-proj.iam.gserviceaccount.com

# 或让整个 gcloud 配置生效
gcloud config set auth/impersonate_service_account ci-runner@my-proj.iam.gserviceaccount.com
```

> 实测：`gcloud auth print-access-token --impersonate-service-account=xxx@p.iam.gserviceaccount.com` 会输出
> `WARNING: This command is using service account impersonation. All API calls will be executed as [xxx@p.iam.gserviceaccount.com].`
> ——**这个 flag 是 global flag，直接跟在子命令后即可**（不需要放在命令前）。

### 3.2 方案 B：Workload Identity Federation（外部身份免密钥）

**这是目前 Google 推荐的"CI / 跨云"标准解法。** 核心思想：把已有的外部身份（GitHub OIDC token、AWS 角色、K8s SA token）兑换成 GCP 短期 token，全程不落任何长期密钥。

支持的 provider 类型（实测 `gcloud iam workload-identity-pools providers --help`）：

```
create-aws     # AWS（含 IMDSv2）
create-oidc    # 任意 OIDC IdP（GitHub / GitLab / Azure DevOps / Argo ...）
create-saml    # 企业 SAML
create-x509    # 证书
```

#### 3.2.1 GitHub Actions 示例（最常见）

```bash
# 1) 建 pool + OIDC provider
gcloud iam workload-identity-pools create pool \
  --project=my-proj --location=global \
  --display-name="CI Pool" --id=ci-pool

gcloud iam workload-identity-pools providers create-oidc \
  --project=my-proj --location=global \
  --workload-identity-pool=ci-pool \
  --display-name="GitHub" --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='my-org/my-repo'"

# 2) 允许 impersonation（不落地 SA 密钥）
gcloud iam service-accounts add-iam-policy-binding \
  ci-runner@my-proj.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/my-proj/locations/global/workloadIdentityPools/ci-pool/attribute.repository/my-org/my-repo"

# 3) 生成 external account 凭据配置
gcloud iam workload-identity-pools create-cred-config \
  --project=my-proj --location=global \
  --workload-identity-pool=ci-pool --provider=github \
  --output-file=/tmp/cred.json \
  --service-account=ci-runner@my-proj.iam.gserviceaccount.com \
  --service-account-token-lifetime-seconds=3600
```

CI 里：

```yaml
# .github/workflows/ci.yml
permissions:
  id-token: write          # 关键：让 GitHub 签发 OIDC token
  contents: read
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-python@v5
  - run: |
      python - <<'PY'
      import os,urllib.request,json
      url=os.environ["ACTIONS_ID_TOKEN_URL"]
      req=urllib.request.Request(url,headers={"Authorization":"Bearer "+os.environ["ACTIONS_ID_TOKEN"]})
      open("/tmp/oidc.txt","w").write(json.load(urllib.request.urlopen(req))["value"])
      PY
  - run: |
      gcloud iam workload-identity-pools create-cred-config \
        --project=my-proj --location=global \
        --workload-identity-pool=ci-pool --provider=github \
        --output-file=/tmp/cred.json \
        --credential-source-type=file --credential-source-file=/tmp/oidc.txt \
        --service-account=ci-runner@my-proj.iam.gserviceaccount.com
      gcloud auth login --cred-file=/tmp/cred.json
      gcloud container clusters get-credentials my-cluster --region=asia-east1
```

也可以直接用官方 action：`google-github-actions/auth@v2`。

#### 3.2.2 凭据配置的三种 credential source

实测 `gcloud iam workload-identity-pools create-cred-config --help` 支持：

| 参数 | 用途 |
|---|---|
| `--credential-source-type=file` | 从文件读 subject token（GitHub Actions / GKE projected token） |
| `--credential-source-type=url` | 从 URL 拉 token（CI 提供 `ACTIONS_ID_TOKEN_URL` 这类接口） |
| `--credential-source-type=executable` | 执行外部命令拿 token（`--executable-command` / `--executable-output-file`） |

#### 3.2.3 AWS 示例

```bash
gcloud iam workload-identity-pools providers create-aws \
  --project=my-proj --location=global \
  --workload-identity-pool=ci-pool --display-name="AWS" \
  --issuer-uri="https://sts.amazonaws.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.aws_role=assertion.arn" \
  --attribute-condition="assertion.arn=='arn:aws:iam::123456789012:role/my-role'"
```

### 3.3 方案 C：Service Account 模拟（Impersonation）

在 GCP 内部（已有 workload identity pool）特别好用。规则：

- 调用方只需在目标 SA 上有 `roles/iam.serviceAccountTokenCreator`
- 目标 SA 持有真正的业务权限
- token 生命周期短（默认 3600s，可配 `--service-account-token-lifetime-seconds`）
- 审计日志同时记录"原始身份 + 被模拟身份"，可追溯

```bash
# 直接取 token
TOKEN=$(gcloud auth print-access-token --impersonate-service-account=target@proj.iam.gserviceaccount.com)

# 或者全局设置
gcloud config set auth/impersonate_service_account target@proj.iam.gserviceaccount.com
gcloud projects list   # 之后所有命令都以 target 身份执行

# 链式模拟（A -> B -> C）
gcloud config set auth/impersonate_service_account "a@p.iam.gserviceaccount.com,b@p.iam.gserviceaccount.com"
```

> `auth/impersonate_service_account` 是 gcloud 正规 property，支持逗号分隔的 delegation chain，**无需任何 SA 密钥**。

### 3.4 方案 D：Workforce Identity Federation（企业员工 SSO）

面向"不在 GCP 组织内、但需要用 Google 账号登录"的合作方 / 员工。与 WIF 的区别：

| | Workload Identity Federation | Workforce Identity Federation |
|---|---|---|
| 主体 | 工作负载（CI / 虚机 / Pod） | 人（员工 / 合作方） |
| 登录方式 | 程序化换 token | **浏览器 SSO**（因此仍需人） |
| 池前缀 | `projects/<num>/locations/global/workloadIdentityPools/` | `locations/global/workforcePools/` |
| 配置生成 | `create-cred-config` | `create-login-config` |

```bash
gcloud iam workforce-pools create workforce-pool \
  --project=my-proj --location=global --display-name="Partners"

gcloud iam workforce-pools providers create-oidc \
  --project=my-proj --location=global \
  --workforce-pool=workforce-pool --display-name="Partner IdP" \
  --issuer-uri="https://idp.example.com" \
  --attribute-mapping="google.subject=assertion.sub" \
  --client-id=... --client-secret=...

gcloud iam workforce-pools create-login-config \
  locations/global/workforcePools/workforce-pool/providers/partner-idp \
  --output-file=login-config.json

# 使用（走浏览器 SSO）
gcloud auth login --login-config=login-config.json
```

> 结论：**Workforce 仍然是浏览器流程，不能自动化**。它的价值是"让外部人能登录而不用被加进你的 GCP 组织"，不是"无人值守"。

### 3.5 方案 E：自有 OAuth Client + refresh_token（"application" 方式）

这是"**还有什么类似 application 的方式**"的最佳答案。

原理：gcloud 自带的 OAuth client id 是 `32555940559.apps.googleusercontent.com`（Google 官方，所有人共用，有配额限制）。你可以**创建自己的 OAuth 客户端（Desktop App 类型）**，用它做一次人工登录，拿到 `refresh_token`，之后完全无人值守地用 refresh_token 换 access token。

#### 3.5.1 创建自己的 client

GCP Console → APIs & Services → Credentials → Create credentials → OAuth client ID → **Application type: Desktop app**。

拿到 `client_id` / `client_secret`，写成 JSON（`installed` 类型，**顶层只能有这一个 key**）：

```json
{
  "installed": {
    "client_id": "xxxx.apps.googleusercontent.com",
    "client_secret": "xxxx",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token"
  }
}
```

> 源码依据：`googlecloudsdk/api_lib/auth/util.py` 的 `AssertClientSecretIsInstalledType()` 明确断言"JSON 必须只有一个 `installed` 属性"，否则抛 `InvalidClientSecretsError`。

#### 3.5.2 用它登录并落 ADC

```bash
gcloud auth application-default login \
  --client-id-file=./client_secret.json \
  --scopes=openid,https://www.googleapis.com/auth/cloud-platform \
  --no-launch-browser
```

结果写入 `~/.config/gcloud/application_default_credentials.json`：

```json
{
  "client_id": "xxxx.apps.googleusercontent.com",
  "client_secret": "xxxx",
  "refresh_token": "1//0eXXXX...",
  "type": "authorized_user",
  "quota_project_id": "my-proj"
}
```

**这个 JSON 就是可以喂给容器的"个人身份凭据"**：

```bash
docker run -v $PWD/adc.json:/secrets/adc.json:ro \
  -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/adc.json \
  my-image gcloud projects list
```

#### 3.5.3 为什么不直接用 gcloud 默认 client？

| 维度 | gcloud 默认 client | 自有 client |
|---|---|---|
| 配额 | 全 Google 用户共用，有 project-level quota | 独立配额 |
| 审计 | 混在一起 | 可在 Console 单独看 |
| 可吊销 | 不可单独吊销 | 可在 Console 一键删除 |
| 用途标记 | 通用 | 建议填 Application home URL / Logo，标注用途 |

#### 3.5.4 纯 Python / 无 gcloud 场景

不想装 gcloud，直接用 google-auth：

```python
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials

creds = Credentials.from_authorized_user_file("adc.json")
if not creds.valid:
    creds.refresh(Request())
print(creds.token)
```

或者直接手写 `authorized_user` 格式的 JSON（这就是 ADC 的格式）：

```json
{
  "type": "authorized_user",
  "client_id": "xxxx.apps.googleusercontent.com",
  "client_secret": "xxxx",
  "refresh_token": "1//0eXXXX..."
}
```

#### 3.5.5 自有 client 的 token 流程（curl 版，参考）

```bash
# 1. 拿到 code（人工在浏览器完成）
AUTH_URL="https://accounts.google.com/o/oauth2/auth?client_id=CLIENT_ID&redirect_uri=urn:ietf:wg:oauth:2.0:oob&response_type=code&scope=openid+https://www.googleapis.com/auth/cloud-platform&access_type=offline&prompt=consent"

# 2. 换 refresh_token
curl -s -X POST https://oauth2.googleapis.com/token \
  -d "client_id=CLIENT_ID&client_secret=CLIENT_SECRET&code=CODE&grant_type=authorization_code&redirect_uri=urn:ietf:wg:oauth:2.0:oob"
```

> 注：Google 已逐步关闭 OOB（`urn:ietf:wg:oauth:2.0:oob`）流程，新应用应使用 loopback redirect，或直接用 gcloud 的 `--no-launch-browser`（redirect 到 `https://sdk.cloud.google.com/authcode.html`）。

### 3.6 方案 F：Access Token 直接注入

**最短路径**，适合"本机已经 gcloud auth login 过，只是想让容器临时用一下"。

```bash
# 宿主机取 token（有效期 3600s）
TOKEN=$(gcloud auth print-access-token)

# 注入容器（gcloud 原生支持）
docker run -e CLOUDSDK_AUTH_ACCESS_TOKEN="$TOKEN" my-image gcloud projects list

# 或者走文件
gcloud auth print-access-token > /tmp/token.txt
docker run -v /tmp/token.txt:/tmp/token.txt:ro \
  my-image gcloud --access-token-file=/tmp/token.txt projects list
# 也可持久化到 config：
gcloud config set auth/access_token_file /tmp/token.txt
```

> 实测确认：设置 `CLOUDSDK_AUTH_ACCESS_TOKEN=fake-token` 后，`gcloud projects list` 的报错信息里明确写着
> *"This command is authenticated with an access token from the CLOUDSDK_AUTH_ACCESS_TOKEN environment variable."*
> —— 说明这条路径**完全生效**，且会**绕过**账号库与 active account 检查。

**缺点**：token 只有 1 小时，长任务要自己续；token 泄露 = 1 小时的完全权限。

### 3.7 方案 G：挂载宿主机 gcloud 配置目录

把宿主机已登录好的凭据库整个挂进容器。

凭据实际位置（macOS / Linux 一致，Windows 是 `%APPDATA%\gcloud`）：

```
~/.config/gcloud/
├── credentials.db          # SQLite，表 credentials，key=account，value=JSON（含 refresh_token）
├── legacy_credentials/<email>/   # 旧版凭据
├── access_tokens.db        # access token 缓存
├── configurations/         # named configurations
├── active_config
└── application_default_credentials.json   # ADC（仅 ADC login 时生成）
```

```bash
docker run \
  -v ~/.config/gcloud:/root/.config/gcloud \
  -e CLOUDSDK_CONFIG=/root/.config/gcloud \
  my-image gcloud projects list
```

> 实测 `~/.config/gcloud/credentials.db` 是 SQLite，表结构 `credentials(account TEXT PRIMARY KEY, value TEXT)`，value 是含 `client_id`/`client_secret`/`refresh_token`/`rapt_token` 的 JSON。

**⚠️ 安全提示**：这等于把宿主机**所有 GCP 账号的 refresh token** 交给容器。生产环境请改用方案 E（只给一个 ADC json）或方案 B（零密钥）。

### 3.8 方案 H：--no-launch-browser / --no-browser 人工桥接

这两个 flag 常被误解为"自动化"，实际是"**换个地方让人工完成**"。

#### --no-launch-browser（同一台机器，人工两步）

实测输出：

```
Go to the following link in your browser, and complete the sign-in prompts:

    https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=32555940559...

Once finished, enter the verification code provided in your browser:
```

流程：命令行打印 URL → 自己在任意浏览器打开 → Google 回调到 `sdk.cloud.google.com/authcode.html` 页面显示一段 code → 复制粘贴回终端。

**可以半脚本化**（把 code 从管道喂进去）：

```bash
# 终端 1：拿 URL
gcloud auth login --no-launch-browser 2>&1 | tee /tmp/gcloud_login.log

# 浏览器完成登录，拿到 code

# 终端 2：把 code 喂进去（必须走 stdin）
echo "$AUTH_CODE" | gcloud auth login --no-launch-browser
```

> 实测：`echo 4/xxx-DUMMY | gcloud auth login --no-launch-browser` → 报 `(gcloud.auth.login) (invalid_grant) Bad Request`，说明**管道喂 code 是可行机制**，只是 code 本身无效。
> 反之，如果完全不喂输入（stdin EOF），会直接 `ERROR: gcloud crashed (EOFError): EOF when reading a line` —— **Docker 里没有 stdin 就是这样崩**。

#### --no-browser（跨机器 bootstrap）

实测输出：

```
You are authorizing gcloud CLI without access to a web browser. Please run the following
command on a machine with a web browser and copy its output back here. Make sure the
installed gcloud version is 372.0.0 or newer.

gcloud auth login --remote-bootstrap="https://accounts.google.com/o/oauth2/auth?..."

Enter the output of the above command:
```

流程：

1. 无浏览器机器跑 `gcloud auth login --no-browser` → 得到 `--remote-bootstrap="URL"`
2. **有浏览器的机器**（需 gcloud ≥ 372）执行该命令 → 打印一个带 code 的 URL
3. 把这个 URL 贴回第 1 步的终端

**这是 SSH 跳板机 / 无桌面 Linux 服务器的标准解法**，但仍需人工。

#### 变通：端口转发假装"有浏览器"

容器内跑 gcloud（它会起 loopback 回调服务），把端口转发到宿主机，宿主机浏览器访问 `http://localhost:<port>`。

注意 gcloud 的临时回调端口是**随机**的，需要先从日志里读到端口号。

### 3.9 方案 I：Headless 浏览器自动点（可行但脆弱）

技术路线：Playwright / Puppeteer 起 headless Chrome → 打开 `accounts.google.com` → 填账号密码 → 过 reCAPTCHA → 取 code。

**实测/已知障碍**：

1. **reCAPTCHA / reCAPTCHA Enterprise**：Google 登录页风控对 headless 几乎必拦
2. **2FA**：TOTP 可自动填，SMS / push 确认无法自动化
3. **consent 页**：自建 OAuth client 首次登录要人工点"允许"
4. **账号风控**：连续失败会触发账号锁定 / 2FA 升级
5. **条款风险**：自动化 Google 登录可能违反 ToS，企业账号通常还有 session 管控

**可接受的用法**：一次性在自己机器上造一份 `authorized_user` JSON（方案 E），后续全交给机器。**不要**每次运行都跑 headless 浏览器。

### 3.10 方案 J：托管环境走 Metadata Server

在 GCP 托管运行时（GCE / GKE / Cloud Run / Cloud Build / Cloud Functions / GKE Autopilot）里，**根本不需要 login**：

```bash
# Cloud Run / GCE / GKE 节点上
gcloud projects list   # 直接就能用，走 metadata server

# 显式留空即用 metadata server
export GOOGLE_APPLICATION_CREDENTIALS=
```

- Cloud Run：绑定 runtime service account，实例自带 SA
- Cloud Build：构建服务账号自带（`PROJECT_NUMBER@cloudbuild.gserviceaccount.com`），可自定义
- GKE（Workload Identity）：Pod 挂 KSA → 绑 GCP SA

GKE 集群开启 Workload Identity Federation：

```bash
gcloud container clusters update my-cluster \
  --region=asia-east1 \
  --workload-pool=projects/my-proj/locations/global/workloadIdentityPools/pool-id
```

kubectl 认证插件（`gke-gcloud-auth-plugin`，SDK 自带，在 `bin/`）内部就是调 `gcloud auth print-access-token`，所以**只要 gcloud 有凭据，kubectl 就有了**。

---

## 4. Docker 落地模板

### 4.1 基础镜像

```dockerfile
FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine

# 或 Debian 版
# FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:latest

ENV CLOUDSDK_CORE_DISABLE_PROMPTS=1
WORKDIR /work
ENTRYPOINT ["gcloud"]
CMD ["projects", "list"]
```

镜像 tag 可选：`alpine` / `slim` / `latest` / `buster`。CI 里建议用 **digest 锁定**避免漂移。

### 4.2 模板 A：自建 OAuth refresh_token（个人身份，推荐）

```dockerfile
FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine
ENV CLOUDSDK_CORE_DISABLE_PROMPTS=1
WORKDIR /work

# 凭据运行时挂载，绝不写进镜像层
ENTRYPOINT ["gcloud"]
CMD ["projects", "list"]
```

```bash
# 一次性：本机造凭据（人工一次）
gcloud auth application-default login \
  --client-id-file=./client_secret.json \
  --scopes=openid,https://www.googleapis.com/auth/cloud-platform
cp ~/.config/gcloud/application_default_credentials.json ./adc.json

# 运行
docker run --rm \
  -v $PWD/adc.json:/secrets/adc.json:ro \
  -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/adc.json \
  gcloud-demo gcloud projects list
```

> 进阶：用 docker secret / K8s Secret / Vault 挂载，别留在宿主机明文目录。

### 4.3 模板 B：Access Token 注入（临时）

```bash
TOKEN=$(gcloud auth print-access-token)
docker run --rm -e CLOUDSDK_AUTH_ACCESS_TOKEN="$TOKEN" gcloud-demo gcloud projects list
```

### 4.4 模板 C：Service Account 密钥（传统，注意风险）

```dockerfile
FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine
ENV CLOUDSDK_CORE_DISABLE_PROMPTS=1
WORKDIR /work

# 更好：运行时用 BuildKit secret，而不是 COPY
ENTRYPOINT ["gcloud"]
CMD ["projects", "list"]
```

```bash
# BuildKit secret，密钥不进镜像层
docker build --secret id=sa_key,src=./key.json -t gcloud-demo .
```

### 4.5 模板 D：SA 模拟（容器里零密钥）

```bash
# 宿主机持有 impersonation 权限
TOKEN=$(gcloud auth print-access-token --impersonate-service-account=ci-runner@my-proj.iam.gserviceaccount.com)
docker run --rm -e CLOUDSDK_AUTH_ACCESS_TOKEN="$TOKEN" gcloud-demo gcloud projects list
```

### 4.6 模板 E：挂载宿主机凭据库（本地开发）

```bash
docker run --rm \
  -v ~/.config/gcloud:/root/.config/gcloud \
  -e CLOUDSDK_CONFIG=/root/.config/gcloud \
  gcloud-demo gcloud projects list
```

### 4.7 模板 F：Jumpbox 模式（容器内授权 + 宿主机凭据中枢）⭐ 贴近实战

这是**在 Docker 里以某个 Google 用户账号身份跑 gcloud**、且凭据要**跨容器复用**时的推荐形态。

核心思路：**把"浏览器授权"和"消费凭据"解耦** —— 凭据落到宿主机一个独立目录，所有容器挂载同一目录即自动复用。

```bash
# ① 预建宿主机凭据目录（避免被 Docker 以 root 创建）
mkdir -p "$HOME/.config/gcloud-jumpbox"

# ② 容器内交互式授权（一次性）
#    -it 让 stdin 保持打开，否则 gcloud 读验证码会 EOFError 崩溃
#    --no-launch-browser 打印 URL，人工复制到浏览器完成授权，
#    页面显示 code 后粘贴回终端
#    -v 把凭据目录挂进去，授权产物（refresh_token）落在宿主机
docker run --rm -it \
  --platform linux/amd64 \
  -e CLOUDSDK_CONFIG=/root/.config/gcloud \
  -v "$HOME/.config/gcloud-jumpbox:/root/.config/gcloud" \
  --entrypoint /root/google-cloud-sdk/bin/gcloud \
  jumpbox:latest \
  auth login --no-launch-browser

# ③ 后续所有命令：免交互、无需 --no-launch-browser、无需 -it
docker run --rm \
  -e CLOUDSDK_CONFIG=/root/.config/gcloud \
  -v "$HOME/.config/gcloud-jumpbox:/root/.config/gcloud" \
  --entrypoint /root/google-cloud-sdk/bin/gcloud \
  jumpbox:latest \
  projects list
```

**为什么 `--no-launch-browser` 适合容器**（实测）：它的 `redirect_uri` 是
`https://sdk.cloud.google.com/authcode.html`（**远端**），不是默认流程的 `http://localhost:8085/`（本地回调）。
所以容器**不需要 `docker run -p` 暴露任何端口**。

**推荐封装**（放 ~/.zshrc），后续一条命令搞定：

```bash
export GCLOUD_JUMPBOX_CONFIG="$HOME/.config/gcloud-jumpbox"

# 交互式（仅 auth login 用）
gcloud-jumpbox-i() {
  docker run --rm -it \
    -e CLOUDSDK_CONFIG=/root/.config/gcloud \
    -v "$GCLOUD_JUMPBOX_CONFIG:/root/.config/gcloud" \
    --entrypoint /root/google-cloud-sdk/bin/gcloud \
    jumpbox:latest "$@"
}

# 非交互（日常命令；不要带 -it，否则 CI 或管道里报 the input device is not a TTY）
gcloud-jumpbox() {
  docker run --rm \
    -e CLOUDSDK_CONFIG=/root/.config/gcloud \
    -v "$GCLOUD_JUMPBOX_CONFIG:/root/.config/gcloud" \
    --entrypoint /root/google-cloud-sdk/bin/gcloud \
    jumpbox:latest "$@"
}

gcloud-jumpbox-login() { gcloud-jumpbox-i auth login --no-launch-browser "$@"; }
```

> **完整版**（含自动弹浏览器、验证清单、坑位清单、kubectl 打通、凭据生命周期）见
> [gcloud-auth-login-docker.md](gcloud-auth-login-docker.md)。

### 4.8 关键环境变量速查

| 变量 | 作用 | 注意 |
|---|---|---|
| `GOOGLE_APPLICATION_CREDENTIALS` | 指定凭据 JSON 路径 | **仅**客户端库 & `gcloud auth application-default print-access-token` 生效；**裸 gcloud 命令不生效**（实测报 "You do not currently have an active account selected"） |
| `CLOUDSDK_AUTH_ACCESS_TOKEN` | 直接注入 access token | 裸 gcloud 命令生效，优先级最高 |
| `CLOUDSDK_CONFIG` | 改 gcloud 配置目录 | 容器里改路径用这个 |
| `CLOUDSDK_ACTIVE_CONFIG_NAME` | 切换 named configuration | 多环境隔离用 |
| `CLOUDSDK_CORE_DISABLE_PROMPTS=1` | 禁止交互提示 | CI/Docker 必设，否则命令会 hang 等输入 |
| `CLOUDSDK_CORE_PROJECT` | 默认 project | 等价 `--project` |
| `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE` | 让 gcloud CLI 用指定凭据文件 | 等价 `gcloud config set auth/credential_file_override` |

> **GOOGLE_APPLICATION_CREDENTIALS 的坑（实测）**：
> ```bash
> GOOGLE_APPLICATION_CREDENTIALS=./key.json gcloud projects list
> # → ERROR: You do not currently have an active account selected.
> ```
> 裸 `gcloud <api>` 命令**不读**这个变量。要让 gcloud CLI 用它，得：
> ```bash
> gcloud config set auth/credential_file_override ./key.json
> # 或
> export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE=./key.json
> ```
> 实测 `gcloud config set auth/credential_file_override /tmp/fake_adc.json` 后，`gcloud auth print-access-token` 确实去尝试刷新该文件里的 refresh_token（报 `invalid_client` 说明确实读了）。

### 4.9 绝不要在 Dockerfile 里做的事

```dockerfile
# ❌ 绝对不要
RUN gcloud auth login
RUN gcloud auth application-default login
COPY key.json /root/key.json     # 密钥进镜像层，docker history 可见
ENV GOOGLE_APPLICATION_CREDENTIALS=/root/key.json
```

原因：

1. 构建机需要浏览器 + 人工交互，CI 必挂
2. 密钥留在镜像层（`docker history` / layer tar 里可提取），后续 `RUN rm` 也删不掉
3. 镜像会推到 registry，等于密钥公开

**正确做法**：构建时只放 gcloud 本身，运行时用 **BuildKit secret** / **volume mount** / **环境变量注入** 凭据。

---

## 5. 选型决策树

```
你的容器需要 GCP 凭据
│
├─ 运行在 GCP 托管环境（GKE / Cloud Run / Cloud Build / GCE）？
│  └─ ✅ Metadata Server / Workload Identity（方案 J）—— 什么都不用做
│
├─ 在 CI（GitHub Actions / GitLab / Jenkins）？
│  ├─ 有 OIDC token 能力？
│  │  └─ ✅ 方案 B：Workload Identity Federation（+ 方案 C 模拟）—— 推荐
│  └─ 没有？
│     └─ 方案 A（SA key）+ Secret 存储，或 方案 C（用 CI 平台身份模拟）
│
├─ 本机开发，只是想让容器能调 gcloud？
│  ├─ 临时用一下 → ✅ 方案 F（注入 access token）
│  ├─ 长期复用个人身份 → ✅ 方案 E（自建 OAuth client + refresh token）
│  └─ 图方便 → 方案 G（挂载 ~/.config/gcloud），⚠️ 安全风险
│
├─ 必须以"某个具体的人"的权限操作（审计要求）？
│  └─ ✅ 方案 E（refresh token 属于个人账号，审计可追溯）
│      或 方案 D（Workforce SSO，仍需浏览器）
│
└─ 无浏览器服务器 / 跳板机，需要偶尔人工登一次？
   └─ ✅ 方案 H（--no-launch-browser / --no-browser）
```

**一句话总结**：

| 场景 | 直接用 |
|---|---|
| CI 无人值守 | WIF（方案 B）+ SA 模拟（方案 C） |
| Docker 里用个人账号 | 自建 OAuth client + refresh_token（方案 E） |
| 只想快速跑一次 | Access Token 注入（方案 F） |
| GCP 内部 | 什么都不做（方案 J） |

---

## 6. 安全红线

| 做法 | 风险 | 正确做法 |
|---|---|---|
| 密钥/Credentials 写进 Dockerfile | 镜像层泄露 | BuildKit secret / 运行时挂载 |
| 把 `~/.config/gcloud` 整个挂进容器 | 泄露所有账号 refresh token | 只给单个 ADC json |
| 长效 access token 硬编码 | 1h 权限裸奔 | 运行时注入 + 定期轮换 |
| 长期 SA key 不轮换 | 最长 90 天无限期有效 | 改用 impersonation / WIF |
| 用个人账号跑生产流水线 | 离职即断、审计混乱 | 独立 SA + 最小角色 |
| Headless 浏览器自动登 Google | 触发风控 / 锁号 / ToS | 只做一次性凭据生成 |
| 未设 `CLOUDSDK_CORE_DISABLE_PROMPTS` | CI 静默 hang | 所有自动化环境必设 |

**IAM 最佳实践**：

- 用 SA 就建专用 SA，**不要**用 `owner`
- 跨项目时在**资源项目**上授权，不要用组织级 Owner
- 授予 `roles/iam.serviceAccountTokenCreator` 而非 `roles/iam.serviceAccountUser`（后者权限更大）
- 开启组织策略禁止 SA key 创建（`constraints/iam.disableServiceAccountKeyCreation`）

---

## 7. 排错 FAQ

**Q: `gcloud auth login` 在 Docker 里报 `ERROR: gcloud crashed (EOFError): EOF when reading a line`**
A: 没有 stdin（交互输入）。必须改用非交互方案（方案 B/E/F/J）。临时缓解：`docker run -i` + `echo CODE | gcloud auth login --no-launch-browser`。

**Q: 提示 "API has not been used in project ... before or it is disabled"**
A: 缺 quota project。加 `X-Goog-User-Project` 头，或 `gcloud auth application-default set-quota-project my-proj`（需 ADC 已存在且账号有 `serviceusage.services.use`）。

**Q: `gcloud auth login` 报 `invalid_client: The OAuth client was not found.`**
A: 凭据文件里的 `client_id` 无效，或用了自建 client 但格式不是 `installed` 类型。

**Q: `--client-id-file` 报 `Client ID file ... is not a valid JSON file` / `Expected a JSON object with a single property for an "installed" application`**
A: JSON 顶层必须只有 `installed` 一个 key（源码 `AssertClientSecretIsInstalledType` 断言）。

**Q: 容器里 gcloud 报 `gcloud: command not found` 但本地正常**
A: 镜像里 `PATH` 没包含 `/google-cloud-sdk/bin`。用官方镜像或显式 `ENV PATH=/google-cloud-sdk/bin:$PATH`。

**Q: 怎么知道当前 gcloud 用的是哪种凭据？**
A: `gcloud auth list`、`gcloud config list`、以及报错信息会说明来源（例如 "authenticated with an access token from the CLOUDSDK_AUTH_ACCESS_TOKEN environment variable"）。

**Q: `--no-browser` 提示需要 gcloud 372.0 或更高？**
A: `--remote-bootstrap` 协议在 372 引入。升级两端 gcloud，或改用 `--no-launch-browser`（人工两步）。

**Q: SA key 有个数上限吗？**
A: 每个 SA 最多 10 个 key；每个项目最多 20 个 SA。

**Q: 想让容器里的 `kubectl` 能连 GKE？**
A: `gcloud container clusters get-credentials` 依赖 `gke-gcloud-auth-plugin`（SDK 自带，在 `bin/`）。确保 PATH 里有它，且 gcloud 本身有凭据。

**Q: `gcloud auth print-access-token --impersonate-service-account` 报 "expected one argument"？**
A: 少了 `=`。必须写成 `--impersonate-service-account=SA@proj.iam.gserviceaccount.com`。

---

## 8. 参考

官方文档：

- Authorizing: https://cloud.google.com/sdk/docs/authorizing
- Workload Identity Federation: https://cloud.google.com/iam/docs/workload-identity-federation
- Workforce Identity Federation: https://cloud.google.com/iam/docs/workforce-identity-federation
- Service account impersonation: https://cloud.google.com/iam/docs/impersonating-service-accounts
- ADC: https://cloud.google.com/docs/authentication/production
- GKE Workload Identity: https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity

本地源码（`/opt/homebrew/share/google-cloud-sdk/lib/googlecloudsdk/`）：

- `api_lib/auth/util.py` — `_CreateGoogleAuthClientConfig`、`AssertClientSecretIsInstalledType`
- `command_lib/auth/flags.py` — `--no-browser` / `--no-launch-browser` / `--remote-bootstrap` 定义
- `core/properties.py` — `auth/access_token_file`、`auth/credential_file_override`、`auth/impersonate_service_account`
- `core/credentials/store.py` — `CLOUDSDK_AUTH_ACCESS_TOKEN` 处理
- `command_lib/ai/docker/run.py` — 官方自己怎么把 ADC 挂进 Docker（参考 `_DockerRunOptions`）

### 相关文档（本仓库）

- [workload-identify.md](workload-identify.md) — GKE Workload Identity annotation 配置
- [connect-gke.md](connect-gke.md) — 连接 GKE 集群
- [gke-secret-manager.md](gke-secret-manager.md) — Secret Manager
- [gcloud-auth-login-docker.md](gcloud-auth-login-docker.md) — **Docker 场景实战**：容器内交互授权 + 凭据落宿主机 + 后续容器免交互复用（Jumpbox 模式）
