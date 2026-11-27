# Docker 化：SMS Secret Onboarding 镜像

> 配套：[../README.md](../README.md)（POC 逻辑与配置字段）
> 相关：[../../../gke/gcloud-auth-login-docker.md](../../../gke/gcloud-auth-login-docker.md)（gcloud 凭据方案）

---

## 1. 你的流程评估

### 1.1 结论：**方向正确，但有 3 个必须改的点**

| 你的设计 | 评价 | 说明 |
|---|---|---|
| main.py 作为唯一入口 | ✅ **正确且推荐** | 容器 ENTRYPOINT 就是它，CI/脚本只认一个入口 |
| 各步骤拆成独立脚本 | ✅ **正确** | 每个步骤能单独跑、单独测、单独替换 |
| 源码打进镜像，运行时解压执行 | ⚠️ **可行但别默认用** | 见 1.3 |
| 镜像 immutable，配置运行时注入 | ✅ **正确** | 这是 12-factor 的标准做法 |
| `docker run -e env -e username -e secret ...` | ✅ **正确，但要区分两类变量** | 见 1.4 |

### 1.2 ✅ 你的思路里做对的部分

1. **入口单一**：调用方（CI / Jenkins / 人）永远只调 `main.py`，不用关心有几个步骤。
2. **步骤自治**：`secret_api_onboarding.py` / `secret_api_create.py` 各自独立，
   既能被 main 调，也能单独 `python3 xxx.py --config xxx.json` 调试。
3. **配置外置**：JSON 骨架在镜像里，运行时用 `-v` 挂载或 `-e` 覆盖 → 同一镜像跑不同环境。
4. **镜像不可变**：镜像一旦 build 完就不改，所有变化通过运行时输入表达。这是很好的实践。

### 1.3 ⚠️ 三个必须改的点

#### 改动 1：Python SDK 不读 gcloud auth login 的凭据（最关键）

**实测结论**：

| 命令 | 写到哪 | 谁会读 |
|---|---|---|
| `gcloud auth login` | `$CLOUDSDK_CONFIG/credentials.db` | **只有 gcloud CLI** |
| `gcloud auth application-default login` | `$CLOUDSDK_CONFIG/application_default_credentials.json` | **Python SDK（google-auth）** |
| `GOOGLE_APPLICATION_CREDENTIALS` | 指向的 json 文件 | **Python SDK，优先级最高** |

实测输出（装好 google-auth 后）：

```
ADC path        = /tmp/jumpbox-cfg/application_default_credentials.json
ADC exists?     = False
credentials.db? = True
```

> **你的 jumpbox 流程（`gcloud auth login --no-launch-browser`）只解决了 gcloud CLI 的凭据，
> 容器里的 Python 脚本仍然拿不到凭据。**

**解决方案**（`docker/auth.sh` 已封装）：

```bash
# 生成 Python SDK 可用的 ADC（推荐）
./docker/auth.sh              # → gcloud auth application-default login --no-launch-browser

# 两条都要（gcloud CLI + Python SDK）
./docker/auth.sh --both
```

运行时挂载：

```bash
-v "$HOME/.config/gcloud-jumpbox:/root/.config/gcloud:ro" \
-e GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json
```

#### 改动 2：源码 zip 进镜像 —— 建议默认不用

你说的"把源码打成 zip 放进镜像，启动时解压执行"我实现了（`--bundle` 模式），
但**建议默认用 layered（直接 COPY）**：

| | layered（直接 COPY） | bundle（zip） |
|---|---|---|
| 构建速度 | 快，层缓存友好 | 多一次打包 |
| 镜像体积 | 略小 | 多一个 zip |
| 启动速度 | 直接可用 | 多一次解压（几十 ms） |
| 换代码 | **必须重新 build** | 同上（zip 也是 build 时打进去的） |
| 调试 | `docker run --entrypoint sh` 直接看源码 | 还要解压才知道里面是什么 |

**关键**：既然 zip 也是 build 时打进去的，**它并不能让"同一个镜像跑不同版本代码"**——
除非你把 zip 改成**运行时挂载**（`-v ./source.zip:/tmp/source.zip`），
那时 zip 模式才有意义（一个通用 runtime 镜像 + 多个代码包）。

**结论**：
- 常规发版 → **layered**（简单、快）
- 需要"一个 runtime 镜像跑多个代码包" → bundle 且**运行时挂载 zip**（不是打进镜像）

```bash
# 方式 1：layered（推荐）
./docker/build.sh --version 1.2.3

# 方式 2：bundle打进镜像
./docker/build.sh --bundle --version 1.2.3

# 方式 3：bundle 运行时挂载（真正的"镜像不变，代码可换"）
./docker/build.sh --version 1.2.3                    # 先 build 一个 runtime 镜像
docker run --rm \
  -v "$PWD/source.zip:/tmp/source.zip:ro" \
  -v "$PWD/app/config:/app/config:ro" \
  sms-secret-onboarding:1.2.3 run --config-dir /app/config
```

#### 改动 3：--entrypoint gcloud 那个命令只解决"授权"，不是"运行"

你给的：

```bash
docker run --rm -it ... --entrypoint /root/google-cloud-sdk/bin/gcloud jumpbox:latest auth login --no-launch-browser
```

这是**授权容器**（jumpbox），产出凭据到宿主机目录。
但**运行容器**是另一个镜像（Python + main.py），两者通过**同一个凭据目录**关联：

```
┌────────────────────┐         ┌────────────────────┐
│ 授权容器 jumpbox    │         │ 运行容器 sms-secret │
│ (gcloud CLI)       │         │ (python + main.py) │
│                    │         │                    │
│ gcloud auth        │  写入   │ GOOGLE_APPLICATION_│
│ application-default│ ──────► │ CREDENTIALS → ADC  │
│ login              │         │                    │
└────────────────────┘         └────────────────────┘
          │                                │
          └────► ~/.config/gcloud-jumpbox ◄─┘
                  （共享的凭据目录，bind mount）
```

### 1.4 -e 环境变量：要分两类

你列的 `-e env -e username -e secret -e releaseverison -e images` 里混了两种东西：

**A. 会进 config 的（覆盖 JSON 字段）** —— 影响业务逻辑：

| 环境变量 | → config 字段 | 类型 |
|---|---|---|
| `TARGET_ENV` | `targetEnv` | string |
| `REGION` | `region` | string |
| `TEAM_NAME` | `teamName` | string |
| `API_NAME` | `apiName` | string |
| `TICKET_NUM` | `ticketNum` | string |
| `SECRET_PROJECT_ID` | `secretProjectId` | string |
| `PROJECT_GCP_SA` | `projectGcpSa` | string |
| `IAM_ENABLE` | `iamEnable` | bool |
| `UPDATE_SECRET_ACCESS` | `updateSecretAccess` | bool |
| `GRANT_GROUP_ACCESSOR` | `grantGroupAccessor` | bool |
| `EIM_APP_ID` | `eimAppId` | string |
| `CHANGE_FILE_NAME` | `changeFileName` | string |
| `TRIGGER_JOB_TIMEOUT` | `triggerJobTimeout` | int |
| `SOURCE_VERSION` | `sourceVersion` | int |
| `JENKINS_PROJECT_NAME` | `jenkinsProjectName` | string |

**B. 只进日志的（不影响逻辑，用于审计追溯）**：

```
RELEASE_VERSION   发布版本
RELEASE_BY        发布人
BUILD_TIME        构建时间
```

> ⚠️ **`secret` 这个变量名很危险**。密钥**绝对不要**用 `-e` 传：
> `docker inspect` 能看到，CI 日志也可能记录。
> 密钥请用 **文件挂载** 或 **Secret Manager 本身**（本项目的意义）。
> POC 里 payload 走 `--payload-from-file`（文件路径），不是环境变量。

---

## 2. 目录结构

```
ob/
├── app/                          # ← 镜像里的一切（代码）
│   ├── main.py                   # ★ 统一入口（orchestrator）
│   ├── common.py                 # 公共库（配置/日志/SM 客户端/ADC 探测）
│   ├── steps/
│   │   ├── secret_api_onboarding.py   # 步骤 1（可单独运行）
│   │   └── secret_api_create.py       # 步骤 2（可单独运行）
│   ├── config/
│   │   ├── ob.example.json
│   │   └── secret.create.json
│   └── requirements.txt
│
├── docker/                       # ← 镜像构建 + 运行脚本
│   ├── Dockerfile                # 镜像定义
│   ├── .dockerignore
│   ├── entrypoint.sh             # 容器入口（解 bundle + 打印环境 + exec main.py）
│   ├── build.sh                  # 构建脚本（layered / bundle）
│   ├── auth.sh                   # 授权脚本（产出 ADC）
│   ├── run.sh                    # 运行封装
│   └── README.md                 # ← 本文
│
└── README.md                     # POC 逻辑说明
```

**为什么这样分**：

- `app/` = **会被 COPY 进镜像的东西**。改这里 → 重新 build。
- `docker/` = **构建与运行工具**。不进镜像。
- 配置文件放在 `app/config/`：**作为默认值进镜像**（这样裸跑也能起来），
  但运行时用 `-v` 挂载覆盖 → 同一镜像跑不同配置。

---

## 3. 流程图

![SMS Secret Onboarding 发布与运行流程](release-ob-flow.html)

交互式 HTML（可缩放、悬停看细节、暗色模式）：[release-ob-flow.html](release-ob-flow.html)

该图由 Archify 从 candidate.json 生成，源文件在 ../.archify/workflow-release-ob-flow-*/。

```
宿主机构建/授权 ──▶ docker run ──▶ entrypoint.sh ──▶ main.py ──▶ 两个步骤 ──▶ Secret Manager
      │                   │                                       │
      │                   └── 挂载 config + ADC 凭据卷 ──┘          └── 失败分支：配置错误 / 凭据类型不匹配
      └── gcloud auth application-default login（产出 ADC json）
```

---

## 4. 快速开始

```bash
cd /Users/lex/git/knowledge/gcp/secret-manage/ob

# ① 构建（layered，推荐）
./docker/build.sh --version 0.1.0

# ② 授权（生成 Python SDK 可用的 ADC，只需一次）
./docker/auth.sh

# ③ 干跑（不调 API）
./docker/run.sh --dry-run

# ④ 真跑
./docker/run.sh

# ⑤ 环境变量覆盖
TARGET_ENV=prod API_NAME=myapi ./docker/run.sh

# ⑥ 只跑一步
./docker/run.sh run --only onboarding
```

---

## 5. 完整 docker run 命令

### 5.1 授权（一次性）

```bash
mkdir -p "$HOME/.config/gcloud-jumpbox"

docker run --rm -it \
  --platform linux/amd64 \
  -e CLOUDSDK_CONFIG=/root/.config/gcloud \
  -v "$HOME/.config/gcloud-jumpbox:/root/.config/gcloud" \
  --entrypoint /root/google-cloud-sdk/bin/gcloud \
  jumpbox:latest \
  auth application-default login --no-launch-browser
#                              ↑↑↑ 注意是 application-default
```

### 5.2 运行

```bash
docker run --rm \
  --platform linux/amd64 \
  -e CLOUDSDK_CONFIG=/root/.config/gcloud \
  -e GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json \
  -e TARGET_ENV=prod \
  -e API_NAME=myapi \
  -e RELEASE_VERSION=0.1.0 \
  -e RELEASE_BY="$(git config user.name)" \
  -v "$HOME/.config/gcloud-jumpbox:/root/.config/gcloud:ro" \
  -v "$PWD/app/config:/app/config:ro" \
  sms-secret-onboarding:0.1.0 \
  run --config-dir /app/config
```

---

## 6. main.py 的命令

```
python3 main.py run  --config-dir DIR [--only onboarding,create] [--project ID]
                    [--dry-run] [-v] [--keep-going] [--runtime-dir DIR]
                    [--strict-config]
python3 main.py list          # 列出可用步骤 + 环境变量映射
python3 main.py env           # 打印解析后的最终配置（CI 自检）
```

| 参数 | 作用 |
|---|---|
| `--only onboarding,create` | 只跑指定步骤 |
| `--project ID` | 覆盖 GCP project id |
| `--dry-run` | 不调 API，只打印 |
| `--keep-going` | 某步失败后继续跑后续步骤 |
| `--strict-config` | 配置必须来自 `--config-dir`，找不到就报错（**CI 建议开**），不回退到镜像内置默认 |

| 命令 | 用途 |
|---|---|
| `run` | 执行 pipeline（默认） |
| `list` | 自检：有哪些步骤、环境变量怎么映射 |
| `env` | 自检：当前环境最终解析出的配置是什么 |

**退出码**（实测）：

| 退出码 | 含义 |
|---|---|
| `0` | 成功 |
| `1` | 执行异常（步骤跑挂了） |
| `2` | 配置/参数错误（配置文件缺失、JSON 非法、步骤名写错） |
| `130` | 被中断（Ctrl-C） |

---

## 7. 配置优先级

```
命令行 --project        （最高）
  ▲
环境变量 TARGET_ENV 等
  ▲
配置文件 app/config/*.json
  ▲
代码里的默认值
```

main.py 的处理流程：

```
1. 读 config json
2. 应用环境变量覆盖        → applied 明细会打日志
3. 应用 --project 覆盖
4. 物化成临时 json (/tmp/.runtime_<step>.json)
5. 子进程调用步骤脚本 --config <临时json>
6. 删除临时 json
```

> 步骤脚本本身**只认 `--config <file>`**，完全不知道环境变量的存在。
> 这样每个步骤既能被 main 调，也能被人直接调用，两条路径行为一致。

---

## 8. 安全清单

| 事项 | 做法 |
|---|---|
| 密钥 | ❌ 绝不 `-e` 传；用文件挂载或直接写进 SM |
| 凭据目录 | `:ro` 只读挂载进容器 |
| 镜像里 | 不放配置、不放凭据、不放 payload |
| payload 日志 | ⚠️ POC 会打印 payload 前 32 字节，**真实实现必须去掉** |
| 日志 | 不要 `set -x` 打印环境变量 |
| 镜像 tag | 用版本号，不用 `latest`（`latest` 无法回滚） |
| 镜像扫描 | CI 里加 `docker scan` / trivy |

---

## 9. CI 集成示例

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="$(git describe --tags --always)"
IMAGE="sms-secret-onboarding:$VERSION"

# 构建
./docker/build.sh --version "$VERSION"

# 干跑自检（不调 API）
IMAGE="$IMAGE" ./docker/run.sh --dry-run

# 真跑
IMAGE="$IMAGE" \
TARGET_ENV=prod \
API_NAME="$API_NAME" \
RELEASE_VERSION="$VERSION" \
RELEASE_BY="$GIT_AUTHOR" \
./docker/run.sh
```

---

## 10. 还没做的（POC 边界）

| 没做 | 说明 |
|---|---|
| 真实 IAM 调用 | 建 SA / 绑角色目前只打印 |
| 真实 metadata 写入 | yaml 只读不写 |
| Jenkins 触发 | 只打印 |
| payload 真实来源 | 用占位串或 `--payload-from-file` |
| 幂等 / 重试 | secret 已存在应复用；网络失败应重试 |
| 健康检查 | Dockerfile 没写 `HEALTHCHECK` |
| 非 root 运行 | 现在是 root，生产应建专用用户 |
| 日志脱敏 | payload 目前会打印 |

---

## 11. 参考

- [../README.md](../README.md) — POC 逻辑与配置字段
- [../../../gke/gcloud-auth-login-docker.md](../../../gke/gcloud-auth-login-docker.md) — gcloud 凭据 / Jumpbox 模式
- [../../../gke/gcloud-auth-login.md](../../../gke/gcloud-auth-login.md) — GCP 认证方式全景
- Docker 官方 multi-stage / layer cache: https://docs.docker.com/build/building/multi-stage/
