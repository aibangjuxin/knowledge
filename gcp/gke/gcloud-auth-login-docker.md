# Docker 场景下的 gcloud 用户授权（Jumpbox 模式）

> 配套文档：[gcloud-auth-login.md](gcloud-auth-login.md)（认证方式全景与原理）
>
> 本文只解决一件事：**在 Docker 里以"某个 Google 用户账号"的身份跑 gcloud / kubectl，且凭据要跨容器复用。**

---

## 目录

- [1. 需求还原与拆解](#1-需求还原与拆解)
- [2. 架构：凭据放在宿主机，容器挂载消费](#2-架构凭据放在宿主机容器挂载消费)
- [3. 方案 A（用户已实现）：容器内授权 + 挂载持久化](#3-方案-a用户已实现容器内授权--挂载持久化)
- [4. 方案 B（推荐）：宿主机授权 + 容器消费](#4-方案-b推荐宿主机授权--容器消费)
- [5. 方案 C：容器内授权 + 自动弹浏览器](#5-方案-c容器内授权--自动弹浏览器)
- [6. 封装：让后续所有容器命令复用该账号](#6-封装让后续所有容器命令复用该账号)
- [7. 实测验证清单](#7-实测验证清单)
- [8. 坑位清单](#8-坑位清单)
- [9. 安全与生命周期](#9-安全与生命周期)
- [10. 延伸场景](#10-延伸场景)

---

## 1. 需求还原与拆解

原始诉求：

> 进 `gcloud auth login` 时肯定有一个交互过程：会弹出一个窗口，然后我们需要复制对应的 URL 去做授权。然后需要把这个存储的凭证放在本地或者 Docker 容器里边，让后续的动作去操作它。核心目的是**授权的时候能弹窗验证 → 拿到授权 → 后续 Docker 里所有命令操作都走这个账号**。

拆成 4 个可独立验证的子目标：

| # | 子目标 | 归属 | 本文档方案 |
|---|---|---|---|
| S1 | 交互式授权（浏览器 + 人工确认 + 2FA） | 必须有人 | 方案 A/B/C |
| S2 | 凭据落到**可跨容器复用**的位置 | 宿主机目录 | 方案 A/B/C |
| S3 | 后续容器里的 gcloud 命令**自动使用**该凭据、无需再次交互 | 容器配置 | 第 6 节封装 |
| S4 | 凭据失效/撤销时能干净地重来 | 运维 | 第 9 节 |

**关键认知**（决定了整个方案形状）：

> 浏览器授权这一步**必须发生在"能看到浏览器的地方"**（人或 headless 浏览器）。
> 但**消费凭据**这一步可以发生在任何地方。
> 所以"授权"和"用凭据"必须解耦——这正是本方案把宿主机目录作为凭据中枢的原因。

---

## 2. 架构：凭据放在宿主机，容器挂载消费

```
                    一次性 / 按需
   ┌──────────────┐   人工授权    ┌─────────────────────────────┐
   │  宿主机       │──────────────▶│ ~/.config/gcloud-jumpbox/    │
   │  (有浏览器)   │              │  ├── credentials.db         │◀── 授权产物
   │              │              │  ├── access_tokens.db       │    (SQLite, 含
   │  或容器内      │              │  ├── configurations/        │     refresh_token)
   │  gcloud CLI   │              │  │   └── config_default      │
   └──────────────┘              │  └── active_config          │
          │                      └─────────────────────────────┘
          │                                    ▲
          │  docker run -v                      │ bind mount
          │                                    │
          │                      ┌─────────────────────────────┐
          └─────────────────────▶│ 容器 jumpbox                │
                                 │  CLOUDSDK_CONFIG=            │
                                 │    /root/.config/gcloud      │
                                 │  ← 所有 gcloud 命令自动用    │
                                 │    挂载进来的凭据             │
                                 └─────────────────────────────┘
```

### 为什么用独立目录 `~/.config/gcloud-jumpbox`，而不是直接挂 `~/.config/gcloud`

| 理由 | 说明 |
|---|---|
| **隔离** | 容器只拿到这一份凭据，不会顺手拿到你本机所有账号的 refresh token |
| **可丢弃** | 出问题直接 `rm -rf ~/.config/gcloud-jumpbox`，本机 gcloud 毫发无损 |
| **多套并行** | 可以同时维护 `gcloud-jumpbox`（个人）、`gcloud-jumpbox-ci`（CI）等多套 |
| **容器内路径一致** | 容器里 `CLOUDSDK_CONFIG=/root/.config/gcloud` 是 gcloud 的默认路径，零心智负担 |

### 凭据目录里到底有什么（实测）

```
~/.config/gcloud-jumpbox/
├── credentials.db          # SQLite：表 credentials(account TEXT PRIMARY KEY, value TEXT)
│                           #   value = {client_id, client_secret, refresh_token, rapt_token, ...}
├── access_tokens.db        # access token 缓存（自动续期会回写这里）
├── configurations/
│   └── config_default      # [core] account=xxx / project=yyy
└── active_config           # 当前激活的 configuration 名
```

> 实测 `credentials.db` 的表结构：`credentials(account TEXT PRIMARY KEY, value TEXT)`，`value` 是含 `refresh_token` 的 JSON。

### 实测：挂载这个目录后，容器里的 gcloud 免交互可用

```bash
# 模拟"把宿主机目录挂进容器"
CLOUDSDK_CONFIG=/tmp/jumpbox-cfg gcloud auth list
#   ACTIVE  ACCOUNT
#   *       aibangjuxin@gmail.com

CLOUDSDK_CONFIG=/tmp/jumpbox-cfg gcloud projects list --format='value(projectId)'
#   gen-lang-client-0384224383
#   glowing-net-233102
#   ...（真实返回了项目列表）
```

**关键**：第 2 次及以后的命令**不需要 `--no-launch-browser`、不需要 `-it`、不需要任何交互**。

---

## 3. 方案 A（用户已实现）：容器内授权 + 挂载持久化

### 3.1 你的原始命令逐行拆解

```bash
mkdir -p "$HOME/.config/gcloud-jumpbox"

docker run --rm -it \
  --platform linux/amd64 \
  -e CLOUDSDK_CONFIG=/root/.config/gcloud \
  -v "$HOME/.config/gcloud-jumpbox:/root/.config/gcloud" \
  --entrypoint /root/google-cloud-sdk/bin/gcloud \
  jumpbox:latest \
  auth login --no-launch-browser
```

| 参数 | 作用 | 去掉会怎样 |
|---|---|---|
| `mkdir -p "$HOME/.config/gcloud-jumpbox"` | 预建宿主机凭据目录 | Docker 会自动创建，但**属主是 root**，后续宿主机读写会别扭 |
| `--rm` | 容器用完即删 | 残留僵尸容器堆积 |
| `-it` | **分配 TTY + 保持 stdin 打开** | ⚠️ **这是交互能工作的关键**。没有 `-i` 则 stdin 关闭，gcloud 读验证码时直接 `EOFError: EOF when reading a line` 崩溃 |
| `--platform linux/amd64` | 强制 amd64（Apple Silicon 上走 Rosetta/qemu 模拟） | 自建镜像只有 amd64 时必须加；有原生 arm64 镜像则去掉更快 |
| `-e CLOUDSDK_CONFIG=/root/.config/gcloud` | 指定 gcloud 配置目录 = 挂载点 | gcloud 会退回 `/root/.config/gcloud` 默认值（碰巧相同），但**显式写更清晰**，且防止镜像改 HOME |
| `-v "$HOME/.config/gcloud-jumpbox:/root/.config/gcloud"` | **凭据中枢**：宿主机目录 ↔ 容器配置目录 | 凭据随容器一起销毁 → 每次都要重新授权 |
| `--entrypoint /root/google-cloud-sdk/bin/gcloud` | 覆盖镜像 ENTRYPOINT，直接跑 gcloud | 取决于你镜像的 ENTRYPOINT 是什么 |
| `jumpbox:latest` | 你的自建镜像 | — |
| `auth login --no-launch-browser` | 走"auth proxy"流程：不弹浏览器，打印 URL，人工复制后在**浏览器**完成授权，页面显示 code，复制回终端粘贴 | 见下方说明 |

### 3.2 `--no-launch-browser` 到底发生了什么（实测）

gcloud 打印到 **stderr**：

```
Go to the following link in your browser, and complete the sign-in prompts:

    https://accounts.google.com/o/oauth2/auth?response_type=code
      &client_id=32555940559.apps.googleusercontent.com
      &redirect_uri=https%3A%2F%2Fsdk.cloud.google.com%2Fauthcode.html
      &scope=openid+...userinfo.email+...cloud-platform+...
      &state=...&code_challenge=...&code_challenge_method=S256
      &prompt=consent&token_usage=remote&access_type=offline
```

然后在 **stdout** 等待：

```
Once finished, enter the verification code provided in your browser:
```

流程闭环：

```
容器内 gcloud 打印 URL ──▶ 你复制到宿主浏览器
                          │
                          ├─ 登录 + 2FA + consent 确认（人工）
                          │
                          ▼
              Google 回调 sdk.cloud.google.com/authcode.html
              （注意：不是 localhost 回调，所以容器不需要暴露任何端口！）
                          │
                          ▼
              页面显示一段 verification code
                          │
              你复制 code ──▶ 粘贴回容器终端 stdin
                          │
                          ▼
              gcloud 用 code + code_verifier 换 refresh_token
              → 写入挂载目录的 credentials.db  ✅
```

> **重点**：`--no-launch-browser` 的 `redirect_uri` 是 `https://sdk.cloud.google.com/authcode.html`（远端），**不是** `http://localhost:8085/`（本地回调）。
> 所以容器**不需要端口映射、不需要 `docker run -p`**，这是它比默认浏览器流程更适合容器的原因。
> 对比默认 `gcloud auth login`（实测输出 `redirect_uri=http://localhost:8085/`）——那种需要浏览器能回连容器的 8085 端口，容器场景下基本不可能。

### 3.3 跑完之后

```bash
# 宿主机验证凭据已落盘
ls -la "$HOME/.config/gcloud-jumpbox"
sqlite3 "$HOME/.config/gcloud-jumpbox/credentials.db" "select account from credentials;"

# 验证凭据可用（在宿主机直接用同一份配置）
CLOUDSDK_CONFIG="$HOME/.config/gcloud-jumpbox" gcloud auth list
CLOUDSDK_CONFIG="$HOME/.config/gcloud-jumpbox" gcloud projects list
```

### 3.4 这个方案的优点与代价

**优点**

- ✅ 容器内 gcloud 版本、配置、证书与后续使用环境**完全一致**（不会出现"宿主机能用、容器里不能用"）
- ✅ 凭据不出宿主机磁盘，不进镜像层
- ✅ 后续所有容器挂同一个目录即自动复用

**代价**

- ⚠️ 只能"手动复制 URL + 手动粘贴 code"，**URL 不会自动弹窗**
- ⚠️ `-it` 意味着必须占着一个终端；没法在 CI / 后台脚本里跑
- ⚠️ Apple Silicon 上 `--platform linux/amd64` 走模拟，性能损失明显

---

## 4. 方案 B（推荐）：宿主机授权 + 容器消费

既然宿主机已经有 gcloud（你的机器上就有：`/opt/homebrew/bin/gcloud`，SDK 526.0.1），**授权这步完全没必要放进容器**。

### 4.1 一次性授权（宿主机，能弹浏览器）

```bash
export CLOUDSDK_CONFIG="$HOME/.config/gcloud-jumpbox"
mkdir -p "$CLOUDSDK_CONFIG"

gcloud auth login --no-launch-browser
# 复制 URL → 浏览器授权 → 复制 code → 粘贴回终端
```

甚至可以**自动开浏览器**（macOS）：

```bash
#!/usr/bin/env bash
# gcloud-login-jumpbox.sh —— 宿主机授权，自动开浏览器
set -euo pipefail

CFG="${GCLOUD_JUMPBOX_CONFIG:-$HOME/.config/gcloud-jumpbox}"
mkdir -p "$CFG"

LOG="$(mktemp -t gcloud-auth.XXXXXX)"

# 后台盯 URL，一旦出现就用系统默认浏览器打开
(
  for _ in $(seq 1 60); do
    url="$(grep -o 'https://accounts.google.com/o/oauth2/auth?[^ ]*' "$LOG" 2>/dev/null | head -1)"
    if [ -n "$url" ]; then
      echo ">>> 正在打开浏览器: ${url:0:60}..."
      case "$(uname)" in
        Darwin) open "$url" ;;
        Linux)  xdg-open "$url" ;;
        *)      echo "请手动打开: $url" ;;
      esac
      break
    fi
    sleep 0.5
  done
) &
WATCH_PID=$!

set +e
CLOUDSDK_CONFIG="$CFG" gcloud auth login --no-launch-browser 2>"$LOG"
RC=$?
set -e

kill "$WATCH_PID" 2>/dev/null || true
grep -o 'https://accounts.google.com/o/oauth2/auth?[^ ]*' "$LOG" | head -1
rm -f "$LOG"
exit $RC
```

> 实测确认：授权 URL 走 **stderr**，交互提示走 **stdout**。所以脚本里必须 `2>"$LOG"` 才能抓到 URL。

### 4.2 容器消费（完全无交互）

```bash
docker run --rm \
  -e CLOUDSDK_CONFIG=/root/.config/gcloud \
  -v "$HOME/.config/gcloud-jumpbox:/root/.config/gcloud" \
  --entrypoint /root/google-cloud-sdk/bin/gcloud \
  jumpbox:latest \
  projects list
```

**没有 `-it`、没有 `--no-launch-browser`、没有任何交互**，直接出结果。

### 4.3 A vs B 对比

| 维度 | 方案 A（容器内授权） | 方案 B（宿主机授权） |
|---|---|---|
| gcloud 版本一致性 | ✅ 完全一致 | ⚠️ 宿主机 SDK 版本可能与镜像不同 |
| 浏览器交互体验 | 手动复制 URL | ✅ 可自动开浏览器 |
| CI / 脚本友好 | ❌ 需要 TTY | ✅ 可脚本化 |
| 调试难度 | 容器内，出问题难查 | ✅ 宿主机直接跑 |
| 凭据产出 | 相同 | 相同 |
| 适用 | 环境强绑定容器 | **通用首选** |

> **推荐**：日常用 B；只有在"宿主机没装 gcloud"或"必须保证版本完全一致"时才用 A。

---

## 5. 方案 C：容器内授权 + 自动弹浏览器

想同时满足"在容器内授权"和"自动弹窗"，可以用 `tee` 把容器输出复制一份出来给宿主监控。

### 5.1 原理

`docker run -it` 会把容器的 stdout/stderr **合并**输出到宿主终端，所以没法靠重定向区分两个流。
解决：在**容器内**用 shell 把 gcloud 的输出 `tee` 一份到挂载出来的文件里：

```bash
# 容器内：
gcloud auth login --no-launch-browser 2>&1 | tee /out/auth.log
```

- `2>&1`：合并两个流 → 都能进 tee
- `|` 只重定向 stdout，**stdin 仍然是终端** → `input()` 能正常读 code
- 宿主监控 `/out/auth.log` 抓 URL → 自动 open

### 5.2 完整脚本

```bash
#!/usr/bin/env bash
# gcloud-jumpbox-login.sh —— 容器内授权 + 宿主自动弹浏览器
set -euo pipefail

CFG="${GCLOUD_JUMPBOX_CONFIG:-$HOME/.config/gcloud-jumpbox}"
IMAGE="${GCLOUD_JUMPBOX_IMAGE:-jumpbox:latest}"
PLATFORM="${GCLOUD_JUMPBOX_PLATFORM:-linux/amd64}"
GCLOUD_BIN="${GCLOUD_JUMPBOX_BIN:-/root/google-cloud-sdk/bin/gcloud}"
OUT_DIR="$(mktemp -d -t gcloud-jumpbox.XXXXXX)"

mkdir -p "$CFG"
: > "$OUT_DIR/auth.log"

# 后台：盯 URL 自动开浏览器
(
  for _ in $(seq 1 120); do
    url="$(grep -o 'https://accounts.google.com/o/oauth2/auth?[^ ]*' "$OUT_DIR/auth.log" 2>/dev/null | head -1)"
    if [ -n "$url" ]; then
      echo ">>> 打开浏览器: ${url:0:70}..."
      case "$(uname)" in
        Darwin) open "$url" ;;
        Linux)  xdg-open "$url" ;;
      esac
      break
    fi
    sleep 0.5
  done
) &
WATCH_PID=$!

docker run --rm -it \
  --platform "$PLATFORM" \
  -e CLOUDSDK_CONFIG=/root/.config/gcloud \
  -v "$CFG:/root/.config/gcloud" \
  -v "$OUT_DIR:/out" \
  --entrypoint /bin/sh \
  "$IMAGE" \
  -c "$GCLOUD_BIN auth login --no-launch-browser 2>&1 | tee /out/auth.log"

kill "$WATCH_PID" 2>/dev/null || true
rm -rf "$OUT_DIR"
```

### 5.3 代价

- 容器镜像需要 `/bin/sh`（alpine/distroless 之外的都行，distroless 没有 shell 就不行）
- `--platform linux/amd64` 模拟 + 浏览器交互，整体偏慢
- 复杂度明显高于方案 B

---

## 6. 封装：让后续所有容器命令复用该账号

目标：以后在容器里跑任何 gcloud / kubectl 命令，**自动**带上正确的挂载和环境变量。

### 6.1 Shell 函数（推荐，放 ~/.bashrc 或 ~/.zshrc）

```bash
# ~/.zshrc

# Jumpbox 凭据目录
export GCLOUD_JUMPBOX_CONFIG="$HOME/.config/gcloud-jumpbox"

# 交互式（需要 TTY）：用于 auth login 之类
gcloud-jumpbox-i() {
  docker run --rm -it \
    --platform "${GCLOUD_JUMPBOX_PLATFORM:-linux/amd64}" \
    -e CLOUDSDK_CONFIG=/root/.config/gcloud \
    -v "$GCLOUD_JUMPBOX_CONFIG:/root/.config/gcloud" \
    --entrypoint "${GCLOUD_JUMPBOX_BIN:-/root/google-cloud-sdk/bin/gcloud}" \
    "${GCLOUD_JUMPBOX_IMAGE:-jumpbox:latest}" \
    "$@"
}

# 非交互（默认）：用于日常命令，避免 -it 在 CI/管道里报 "the input device is not a TTY"
gcloud-jumpbox() {
  docker run --rm \
    --platform "${GCLOUD_JUMPBOX_PLATFORM:-linux/amd64}" \
    -e CLOUDSDK_CONFIG=/root/.config/gcloud \
    -v "$GCLOUD_JUMPBOX_CONFIG:/root/.config/gcloud" \
    --entrypoint "${GCLOUD_JUMPBOX_BIN:-/root/google-cloud-sdk/bin/gcloud}" \
    "${GCLOUD_JUMPBOX_IMAGE:-jumpbox:latest}" \
    "$@"
}

# 一次性授权（容器内）
gcloud-jumpbox-login() {
  gcloud-jumpbox-i auth login --no-launch-browser "$@"
}
```

用法：

```bash
gcloud-jumpbox projects list
gcloud-jumpbox config get-value core/project
gcloud-jumpbox container clusters get-credentials my-cluster --region=asia-east1
gcloud-jumpbox auth list
```

### 6.2 封装成独立脚本（便于 CI / 其他项目引用）

```bash
#!/usr/bin/env bash
# gcloud-jumpbox —— 在 jumpbox 容器里执行 gcloud 命令
set -euo pipefail

CFG="${GCLOUD_JUMPBOX_CONFIG:-$HOME/.config/gcloud-jumpbox}"
IMAGE="${GCLOUD_JUMPBOX_IMAGE:-jumpbox:latest}"
PLATFORM="${GCLOUD_JUMPBOX_PLATFORM:-linux/amd64}"
GCLOUD_BIN="${GCLOUD_JUMPBOX_BIN:-/root/google-cloud-sdk/bin/gcloud}"

[ -d "$CFG" ] || { echo "凭据目录不存在: $CFG（先跑 gcloud-jumpbox-login）" >&2; exit 1; }

exec docker run --rm \
  --platform "$PLATFORM" \
  -e CLOUDSDK_CONFIG=/root/.config/gcloud \
  -v "$CFG:/root/.config/gcloud" \
  --entrypoint "$GCLOUD_BIN" \
  "$IMAGE" \
  "$@"
```

### 6.3 认证状态自检

放进脚本或 CI 的前置检查：

```bash
#!/usr/bin/env bash
# gcloud-jumpbox-check —— 检查挂载的凭据是否还有效
set -euo pipefail
CFG="${GCLOUD_JUMPBOX_CONFIG:-$HOME/.config/gcloud-jumpbox}"

if [ ! -f "$CFG/credentials.db" ]; then
  echo "❌ 未找到 credentials.db，需要先执行 gcloud-jumpbox-login" >&2
  exit 1
fi

ACCOUNT="$(CLOUDSDK_CONFIG="$CFG" gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)"
if [ -z "$ACCOUNT" ]; then
  echo "❌ 没有 active account，需要 gcloud-jumpbox-login" >&2
  exit 1
fi

if CLOUDSDK_CONFIG="$CFG" gcloud projects list --format='value(projectId)' >/dev/null 2>&1; then
  echo "✅ 凭据有效，当前账号: $ACCOUNT"
else
  echo "⚠️  凭据可能已失效（refresh token 被撤销/过期），需要重新 gcloud-jumpbox-login" >&2
  exit 1
fi
```

### 6.4 让 kubectl 也能用（容器内）

`gke-gcloud-auth-plugin` 随 SDK 一起装在 `bin/`，它内部就是调 `gcloud auth print-access-token`。
所以只要容器里 PATH 含 `/root/google-cloud-sdk/bin`，kubectl 的认证插件就能工作：

```bash
docker run --rm \
  -e CLOUDSDK_CONFIG=/root/.config/gcloud \
  -e PATH=/root/google-cloud-sdk/bin:$PATH \
  -v "$HOME/.config/gcloud-jumpbox:/root/.config/gcloud" \
  -v "$HOME/.kube:/root/.kube" \
  jumpbox:latest \
  kubectl get nodes
```

> 注意：`gke-gcloud-auth-plugin` 需要访问集群 API Server；跨网络场景可能需要 `--network host` 或 VPN。此处仅说明凭据链路打通，网络另议。

---

## 7. 实测验证清单

按顺序执行，每步都应通过：

```bash
# ① 宿主机凭据目录已建
ls -ld "$HOME/.config/gcloud-jumpbox"

# ② 授权后 credentials.db 存在且有账号
sqlite3 "$HOME/.config/gcloud-jumpbox/credentials.db" "select account from credentials;"

# ③ active account 已设置
cat "$HOME/.config/gcloud-jumpbox/configurations/config_default"
#   [core]
#   account = your@gmail.com
#   project = your-project

# ④ 宿主机用这份配置能调 API
CLOUDSDK_CONFIG="$HOME/.config/gcloud-jumpbox" gcloud projects list --format='value(projectId)' | head

# ⑤ 容器里免交互可用
gcloud-jumpbox projects list --format='value(projectId)' | head

# ⑥ 容器里 auth list 显示 active 账号
gcloud-jumpbox auth list

# ⑦ token 能打印出来（说明 refresh 链路正常）
gcloud-jumpbox auth print-access-token | head -c 40; echo

# ⑧ 重复登录不会重新触发浏览器（有凭据时自动复用）
gcloud-jumpbox-login
#   WARNING: Re-using locally stored credentials for [your@gmail.com].
#   You are now logged in as [your@gmail.com].
```

> ⑧ 的行为已实测：`gcloud auth login <ACCOUNT>` 在本地已有该账号凭据时，会直接复用并只打印 warning，**不会**重新走浏览器流程。
> 所以"授权"命令是**幂等**的，日常可以放心反复执行。

---

## 8. 坑位清单

| # | 坑 | 现象 | 解法 |
|---|---|---|---|
| 1 | **缺 `-i`** | `ERROR: gcloud crashed (EOFError): EOF when reading a line` | 加 `-it`（交互）或 `echo CODE | gcloud ...`（管道） |
| 2 | **`docker run -it` 在 CI 里报错** | `the input device is not a TTY` | 后续命令用**不带 `-it`** 的封装；授权只在本地交互做 |
| 3 | **`-t` 合并 stdout/stderr** | 宿主脚本抓不到 URL | 容器内 `2>&1 | tee /out/x.log`，或改用方案 B（宿主机授权） |
| 4 | **URL 走 stderr，prompt 走 stdout** | 脚本 `> file` 抓不到 URL | 必须 `2>file` 或 `2>&1` |
| 5 | **凭据目录被 root 创建** | 宿主机上属主是 root，`rm` 报 permission denied | 宿主侧预先 `mkdir -p`；或 `sudo chown -R $USER` |
| 6 | **并发跑多个容器** | SQLite `database is locked` | 串行执行；或给每个容器独立 `CLOUDSDK_CONFIG` |
| 7 | **Apple Silicon 强制 amd64** | 慢 5-10 倍 | 换原生 arm64 镜像，去掉 `--platform`；或本地用方案 B |
| 8 | **镜像里 gcloud 路径不对** | `exec: /root/google-cloud-sdk/bin/gcloud: not found` | 先 `docker run --rm --entrypoint sh jumpbox:latest -c 'which gcloud; ls /'` 探测 |
| 9 | **distroless 镜像没有 shell** | 方案 C 的 `--entrypoint /bin/sh` 失败 | 方案 C 需要带 shell 的镜像 |
| 10 | **`--no-launch-browser` 的 redirect 是远端** | 以为要 `-p 8085` | **不需要端口映射**，别加 |
| 11 | **refresh token 被撤销** | 之前正常突然报权限错 | `gcloud-jumpbox auth revoke <account>` + 重新授权 |
| 12 | **多账号时 active 选错** | 用错账号操作 | `gcloud-jumpbox config set account <email>` |
| 13 | **忘了 `CLOUDSDK_CONFIG`** | 容器用默认路径，找不到凭据 | 封装里永远带上这个 env |
| 14 | **凭据目录被 git 追踪** | refresh token 泄漏 | `echo gcloud-jumpbox/ >> .gitignore` |

---

## 9. 安全与生命周期

### 9.1 凭据的敏感度

`credentials.db` 里的 `refresh_token` **等价于账号密码**：拿到就能长期换取 access token。

防护：

```bash
chmod 700 "$HOME/.config/gcloud-jumpbox"
chmod 600 "$HOME/.config/gcloud-jumpbox"/*.db
```

- ❌ 绝不进 Git（加 `.gitignore`）
- ❌ 绝不 `docker commit` 进镜像
- ❌ 绝不 base64 后塞进 Dockerfile ENV
- ✅ 只放宿主机目录，容器运行时挂载

### 9.2 生命周期

| 事件 | 动作 |
|---|---|
| 授权成功 | `credentials.db` 写入 refresh_token，长期有效 |
| access token 过期（1h） | gcloud 用 refresh_token **自动续期**，无需人工 |
| refresh token 被撤销（改密码 / `gcloud auth revoke` / 管理员操作） | 后续命令报权限错 → 重新走一次授权 |
| 用户离职 / 机器移交 | `rm -rf ~/.config/gcloud-jumpbox` + 到 Google 账号安全页撤销 |
| 项目权限变更 | 凭据本身不用动，重新 IAM 授权即可（token 会带上新权限） |

### 9.3 撤销

```bash
# 在容器里撤销
gcloud-jumpbox auth revoke your@gmail.com

# 或直接在宿主机
CLOUDSDK_CONFIG="$HOME/.config/gcloud-jumpbox" gcloud auth revoke your@gmail.com

# 彻底清除
rm -rf "$HOME/.config/gcloud-jumpbox"
```

---

## 10. 延伸场景

### 10.1 客户端库（Python / Go / Java）需要 ADC

gcloud CLI 用的凭据和客户端库的 ADC **不是同一份**。客户端库要用 ADC：

```bash
# 宿主机生成 ADC（一次性，人工）
gcloud auth application-default login --no-launch-browser

# 拿到 ADC json，容器里用
docker run --rm \
  -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/adc.json \
  -v "$HOME/.config/gcloud-jumpbox/adc.json:/secrets/adc.json:ro" \
  my-app
```

> ⚠️ 提醒：**裸 `gcloud <api>` 命令不读 `GOOGLE_APPLICATION_CREDENTIALS`**（实测报 `You do not currently have an active account selected`）。
> gcloud CLI 要用它，必须 `gcloud config set auth/credential_file_override=...` 或设 `CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE`。
> 详见 [gcloud-auth-login.md](gcloud-auth-login.md) 第 4.7 节。

### 10.2 多环境隔离

用 named configuration：

```bash
gcloud-jumpbox config configurations create prod
gcloud-jumpbox config configurations activate prod
gcloud-jumpbox config set project prod-project
```

或用多套凭据目录：

```bash
GCLOUD_JUMPBOX_CONFIG="$HOME/.config/gcloud-prod"  gcloud-jumpbox projects list
GCLOUD_JUMPBOX_CONFIG="$HOME/.config/gcloud-dev"   gcloud-jumpbox projects list
```

### 10.3 多用户共用一台跳板机

每个用户用自己的 `GCLOUD_JUMPBOX_CONFIG`，容器内路径一致，互不干扰：

```bash
# user-a
GCLOUD_JUMPBOX_CONFIG=/home/user-a/.config/gcloud-jumpbox
```

### 10.4 无需交互的 CI（推荐 WIF 而非本方案）

本方案本质是"**把人的身份搬进机器**"，适合内部开发机 / 跳板机。
真正的 CI 应该用 **Workload Identity Federation**（OIDC 换 token，零密钥、可审计、可自动吊销），详见 [gcloud-auth-login.md](gcloud-auth-login.md) 第 3.2 节。

---

## 参考

- [gcloud-auth-login.md](gcloud-auth-login.md) — 认证方式全景（含 WIF / Impersonation / 自有 OAuth Client 等）
- Google 官方 Authorizing 文档: https://cloud.google.com/sdk/docs/authorizing
- GKE Workload Identity: https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
- 源码（本地 SDK）：`lib/googlecloudsdk/core/credentials/flow.py`
  - `RemoteLoginWithAuthProxyFlow` —— `--no-launch-browser` 的实现，含"redirect 到 sdk.cloud.google.com 显示 code"的注释
  - `PromptForAuthCode` —— 读 code 的地方（`input()`，所以需要 stdin）
- 源码：`lib/googlecloudsdk/api_lib/auth/util.py`
  - `_Login()` 分支逻辑：`no_browser` / `remote_bootstrap` / `no_launch_browser` / `can_launch_browser` 的选择顺序
