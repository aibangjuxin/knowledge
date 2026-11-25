# 用 Cloud Build 做 PR 门禁：仓库里的 CI 配置 → PR 上的 Checks

> **TL;DR（先回答你的 4 个问题）**
>
> | 你的问题 | 答案 |
> | :--- | :--- |
> | ① 仓库里的 `ci-test.yaml` 和文档里的 `cloudbuild.yaml` 语法一致吗？ | **完全一致**——它们是**同一套 Cloud Build build config schema**，文件名随便起。差别只在字段名：你的 `command: [...]` 要写成 `args: [...]`（或 `script:`），你的 `name: "Install test dependencies"` 是**步骤名**，而 Cloud Build 的 `name:` 是**要跑的 builder 镜像**。Trigger 用 `--build-config=ci-test.yaml` 指向它即可。 |
> | ② 要在 GitHub 里配 webhook 地址、指向 GCP 的 trigger 吗？ | **官方集成（GitHub App / Developer Connect）下不需要**——webhook 由 Google 自动装到你的 repo 上，你只在 GCP 侧建 trigger。只有走「Webhook trigger + GitHub 原生 Webhook」这种野路子才要手动贴 URL（且 payload 格式受限，见 [§3.5](#35-路线-bwebhook-trigger--github-原生-webhook)）。 |
> | ③ PR 模式怎么联动？ | Trigger 选 **Pull Request** 事件，`--pull-request-pattern` 匹配的是**目标分支（base branch）**，PR 一开/一更新就自动建一次 build。 |
> | ④ PR 上的 **Checks** 怎么实现？ | **Cloud Build 构建结束后自动回写结果到 GitHub**（check run / commit status），挂在 PR 上 → PR 页面出现 **Checks** 标签 → 再把这条 check 设成 **branch protection 的 required status check**，就变成"不通过不能合并"的硬门禁。**你不需要写任何代码**。 |

---

## 目录

1. [场景还原：我们到底要造什么](#1-场景还原我们到底要造什么)
2. [仓库侧：CI 配置文件长什么样](#2-仓库侧ci-配置文件长什么样)
3. [GCP 侧：配一次，之后不用再管](#3-gcp-侧配一次之后不用再管)
4. [PR 上的 Checks 到底是怎么来的（核心）](#4-pr-上的-checks-到底是怎么来的核心)
5. ["每个 PR 有自己的逻辑" 的四个实现层次](#5-每个-pr-有自己的逻辑的四个实现层次)
6. [安全：PR 是不可信输入](#6-安全pr-是不可信输入)
7. [排错手册](#7-排错手册)
8. [端到端 checklist](#8-端到端-checklist)
9. [官方文档与配套阅读](#9-官方文档与配套阅读)

---

## 1. 场景还原：我们到底要造什么

### 1.1 用一句话描述

> 我们要改某个 **GET 接口的响应行为**（response story）→ 提一个 **Pull Request** → **自动触发** GCP 上的一次 Cloud Build 构建（跑 helm lint/render、python 集群测试、bash bootstrap 测试）→ 构建结果**自动回写**成 PR 上的一条 **Check** → **Check 不绿就不让合并**。

### 1.2 全景时序（谁触发谁）

```
 开发者          GitHub                GCP (Cloud Build)
    │              │                        │
    │ git push     │                        │
    ├─────────────>│                        │
    │              │ ① PR opened/synchronize│
    │              │    事件 → webhook ────>│
    │              │                        │ ② Trigger 命中
    │              │                        │    (repo + PR 事件
    │              │                        │     + base 分支正则)
    │              │                        │
    │              │                        │ ③ 控制面 clone 源码
    │              │<── installation token ─┤
    │              │                        │    (拉的是 GitHub 生成的
    │              │                        │     PR 临时合并结果)
    │              │                        │
    │              │                        │ ④ 拉起临时 VM
    │              │                        │    按 ci-test.yaml 逐步执行
    │              │                        │    (install → helm → py → bash)
    │              │                        │
    │              │ ⑤ 回写 check 结果 ─────┤
    │              │<───────────────────────┤
    │              │                        │
    │              │ ⑥ PR 页面出现 Checks    │
    │              │    ✔ / ✘ / ⏳          │
    │              │                        │
    │              │ ⑦ branch protection：   │
    │              │    check 不绿 → 禁止 merge│
    ▼
```

### 1.3 四个"角色"，别搞混

| 角色 | 存在哪 | 干什么 |
| :--- | :--- | :--- |
| **① CI 配置**（你的 `ci-test.yaml`） | **Git 仓库里** | 声明"跑哪些步骤"——这是**唯一的事实源** |
| **② Trigger** | **GCP 侧**（一个 API 资源） | 声明"什么事件 → 跑哪份配置、用哪个 SA" |
| **③ GitHub App / connection** | GitHub 侧 + GCP 侧 | 收 webhook、授权 Cloud Build 读源码 |
| **④ Check（结果）** | GitHub 上 PR 页面 | 构建结束后自动出现的绿勾/红叉 |

> **你问的"webhook 地址就是 GCP 工程里对应的 cloud build trigger"**——严格说是不成立的：
> **trigger 是 GCP 侧的一条规则，它没有"地址"**；有地址的是 **webhook 接收端点**。
> 官方集成里，GitHub App 自动把事件 POST 到 Google 的接收端点，你既不用看也不用填这个 URL。
> 详见 [§3.5](#35-路线-bwebhook-trigger--github-原生-webhook)。

---

## 2. 仓库侧：CI 配置文件长什么样

### 2.1 你原本的写法（通用 CI DSL）

```yaml
steps:
  - name: Install test dependencies
    command: ["bash", "scripts/utils/install_ci_dependencies.sh"]
  - name: Helm lint and render
    command: ["make", "test-helm"]
  - name: Cluster onboarding tests
    command: ["make", "test-python"]
  - name: Bootstrap script tests
    command: ["make", "test-bash"]
```

### 2.2 翻译成 Cloud Build schema（字段对照表）

| 你的 DSL | Cloud Build | 说明 |
| :--- | :--- | :--- |
| `steps[].name`（步骤名） | **`id`** | 步骤的**标识**，供 `waitFor` 引用；`name` 语义不同 |
| — | **`steps[].name`** | **builder 镜像**（必填），如 `ubuntu:22.04`、`gcr.io/cloud-builders/gcloud` |
| `steps[].command: [a, b]` | **`args: [a, b]`** | 传给镜像 entrypoint 的参数；想跑 shell 用 `entrypoint: bash` + `args: ['-c', '...']` |
| `steps[].command`（单行 shell） | **`script: |`** | 多行脚本，等价于 `bash -c` |
| `steps[].working_dir` | **`dir`** | 相对 `/workspace` 的路径 |
| `steps[].env` | `env: ['K=V']` | 环境变量 |
| `steps[].depends_on` | **`waitFor: ['<id>']`** | 依赖的上游 step |
| — | `allowFailure: true` | 该步失败不中断整个 build（**不影响 Check 变红**，只是不阻塞后续） |
| — | `timeout: '600s'` | 单步超时（整体超时用顶层 `timeout:`） |

> ⚠️ **最容易错的一条**：Cloud Build 的 `steps[].name` **不是步骤名，是镜像**。
> 步骤名/描述请放到 `id`（或 `name` 之外的自定义字段会被忽略）。

### 2.3 可直接用的 `ci-test.yaml`（Cloud Build schema）

```yaml
# ci-test.yaml —— PR CI 用（放仓库根目录）
#
# 这个文件就是"CI 的唯一事实源"：
#   · Cloud Build：gcloud builds submit --config ci-test.yaml
#   · 本地开发：   make ci-test  ->  bash scripts/ci/run-ci-test.sh
steps:
  # ── 0) 安装测试依赖 ───────────────────────────────
  # 注意：step 之间**只有 /workspace 是共享的**，
  #       所以依赖必须装进 /workspace 下面的目录，
  #       否则下一个 step（新容器）根本看不到。
  - name: 'ubuntu:22.04'
    id: 'install-deps'
    entrypoint: bash
    args:
      - 'scripts/utils/install_ci_dependencies.sh'
    env:
      - 'CI_DEPS_PREFIX=/workspace/.ci-deps'
      - 'HOME=/workspace/.ci-home'
    timeout: '600s'

  # ── 1) Helm lint + render ─────────────────────────
  - name: 'ubuntu:22.04'
    id: 'helm-lint-render'
    entrypoint: bash
    args: ['-c', 'make test-helm']
    env:
      - 'PATH=/workspace/.ci-deps/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
      - 'HOME=/workspace/.ci-home'
      - 'CI=true'
    waitFor: ['install-deps']
    timeout: '900s'

  # ── 2) 集群 onboarding 测试 ───────────────────────
  - name: 'ubuntu:22.04'
    id: 'cluster-onboarding'
    entrypoint: bash
    args: ['-c', 'make test-python']
    env:
      - 'PATH=/workspace/.ci-deps/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
      - 'HOME=/workspace/.ci-home'
      - 'CI=true'
    waitFor: ['install-deps']
    timeout: '1200s'

  # ── 3) bootstrap 脚本测试 ─────────────────────────
  - name: 'ubuntu:22.04'
    id: 'bootstrap-tests'
    entrypoint: bash
    args: ['-c', 'make test-bash']
    env:
      - 'PATH=/workspace/.ci-deps/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
      - 'HOME=/workspace/.ci-home'
      - 'CI=true'
    waitFor: ['install-deps']
    timeout: '900s'

# ── 全局 ─────────────────────────────────────────────
timeout: '1800s'
serviceAccount: 'projects/$PROJECT_ID/serviceAccounts/gcb-ci@$PROJECT_ID.iam.gserviceaccount.com'

substitutions:
  _HELM_CHART_DIR: 'charts/'
  _CLUSTER_NAME: 'example-cluster'

options:
  machineType: 'E2_HIGHCPU_8'
  diskSizeGb: '30'
  logging: 'CLOUD_LOGGING_ONLY'
  env:
    - 'CI=true'
    - 'HELM_CHART_DIR=${_HELM_CHART_DIR}'
```

> **为什么每步都重复写 `PATH`**：每个 step 是一个**全新容器**，
> 只有 `/workspace` 挂载共享；`$PATH`、`$HOME`、`/usr/local/bin` 都不共享。
> 所以 `install-deps` 必须把 helm / pytest / bats 装到 `/workspace/.ci-deps`，
> 后续 step 再把 `PATH` 指过去。这是 Cloud Build CI 里最常见的"第二个 step 说命令找不到"的原因。

> **为什么不用 YAML anchor（`&ci_env` / `*ci_env`）复用 env**：Cloud Build 的 build config 文档没有承诺
> 支持 YAML anchor 与 alias，展开写虽然啰嗦一点，但换台机器 / 换个解析器也一定能跑通。

### 2.4 配套的 Makefile 与安装脚本

```makefile
# Makefile
HELM_CHART_DIR ?= charts/
.PHONY: ci-test test-helm test-python test-bash

ci-test:
	@bash scripts/ci/run-ci-test.sh

test-helm:
	helm lint $(HELM_CHART_DIR)
	helm template release $(HELM_CHART_DIR) > /dev/null

test-python:
	pytest -q tests/

test-bash:
	bats tests/bootstrap/
```

```bash
# scripts/utils/install_ci_dependencies.sh
#!/usr/bin/env bash
set -euo pipefail

PREFIX="${CI_DEPS_PREFIX:-/workspace/.ci-deps}"
mkdir -p "${PREFIX}/bin" "${HOME:-/workspace/.ci-home}"

# helm
curl -fsSL https://get.helm.sh/helm-v3.15.4-linux-amd64.tar.gz \
  | tar -xz -C /tmp
install -m 0755 /tmp/linux-amd64/helm "${PREFIX}/bin/helm"

# python / pytest
python3 -m pip install --user --upgrade pip
python3 -m pip install --user pytest

# bash 测试框架（bats）—— 装到 PREFIX 里才能跨 step 复用
git clone --depth 1 https://github.com/bats-core/bats-core /tmp/bats-core
install -m 0755 /tmp/bats-core/bin/bats "${PREFIX}/bin/bats"
```

> **建议**：依赖安装写成**幂等 + 装进 `/workspace`** 的脚本，
> 这样本地跑和 Cloud Build 跑用的是同一份脚本，不会出现"本地过、CI 挂"。

### 2.5 想保留你原来的 DSL？—— 做一个转换器

如果你不想改 `ci-test.yaml` 的写法（要跟别的 CI 工具共用一份配置），
可以把**它当事实源**，在提交前/构建时转换一次：

```python
# scripts/ci/render-cloudbuild.py（放进仓库）
#!/usr/bin/env python3
"""把通用 CI DSL 转成 Cloud Build build config。"""
import sys
import yaml

BUILDER = "ubuntu:22.04"          # 跑 bash/make 用的基础镜像
SHARED_ENV = [
    "PATH=/workspace/.ci-deps/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "HOME=/workspace/.ci-home",
]


def main() -> None:
    src = yaml.safe_load(open(sys.argv[1]))
    steps = []
    for i, s in enumerate(src.get("steps", [])):
        cmd = s["command"]
        step = {
            "name": BUILDER,
            "id": s.get("id") or f"step-{i}",
            "entrypoint": cmd[0],
            "args": cmd[1:],
            "env": SHARED_ENV + [f"{k}={v}" for k, v in (s.get("env") or {}).items()],
        }
        if s.get("working_dir"):
            step["dir"] = s["working_dir"]
        steps.append(step)
    yaml.safe_dump({"steps": steps, "timeout": "1800s"}, sys.stdout)


if __name__ == "__main__":
    main()
```

用法：

```bash
python3 scripts/ci/render-cloudbuild.py ci-test.yaml > /tmp/cloudbuild.yaml
gcloud builds submit --config /tmp/cloudbuild.yaml --region=asia-northeast1
```

> **取舍**：转换器方案多一层间接性（调试时要看生成物），**除非你确实有多套 CI 消费同一份 DSL，
> 否则直接把 `ci-test.yaml` 写成 Cloud Build schema 更省事**（本仓库 `examples/` 下就是这种写法）。

---

## 3. GCP 侧：配一次，之后不用再管

> **前置**：仓库已经"连上"Cloud Build 了。
> 连接方式（1st gen GitHub App / 2nd gen Developer Connect / GitHub Enterprise）
> 完整步骤见 **[how-to-github-trigger-cloud-build.md](how-to-github-trigger-cloud-build.md)** §4 / §5 / §7。
> 下面假设连接已完成，只讲 **PR trigger** 这一步。

### 3.1 建 PR Trigger（2nd gen / Developer Connect，推荐）

```bash
gcloud builds triggers create github \
  --name=pr-ci-test \
  --region=asia-northeast1 \
  --repository=projects/<PROJECT_ID>/locations/asia-northeast1/connections/<CONN>/repositories/<REPO> \
  --pull-request-pattern='^main$' \
  --build-config=ci-test.yaml \
  --service-account=projects/<PROJECT_ID>/serviceAccounts/gcb-ci@<PROJECT_ID>.iam.gserviceaccount.com \
  --comment-control=COMMENTS_DISABLED \
  --include-logs-with-status \
  --no-require-approval
```

### 3.2 建 PR Trigger（1st gen / Cloud Build GitHub App）

```bash
gcloud builds triggers create github \
  --name=pr-ci-test \
  --region=global \
  --repo-owner=<OWNER> \
  --repo-name=<REPO> \
  --pull-request-pattern='^main$' \
  --build-config=ci-test.yaml \
  --service-account=projects/<PROJECT_ID>/serviceAccounts/gcb-ci@<PROJECT_ID>.iam.gserviceaccount.com \
  --comment-control=COMMENTS_DISABLED
```

> **两个 generation 的差别只有"怎么指定仓库"和"region 能不能是 `global`"**，
> PR 相关的参数（`--pull-request-pattern` / `--comment-control`）完全一致。

### 3.3 关键参数逐个解释

| 参数 | 作用 | 建议 |
| :--- | :--- | :--- |
| `--build-config=ci-test.yaml` | **仓库里**的构建配置路径 | 相对**仓库根目录**，不是本地路径 |
| `--pull-request-pattern='^main$'` | 匹配 **base branch**（PR 要合并进去的目标分支） | `^main$` 只匹配 `main`；写 `main` 会连 `main-hotfix` 一起匹配 |
| `--comment-control` | `COMMENTS_DISABLED` / `COMMENTS_ENABLED` / `COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY` | **默认是 `COMMENTS_ENABLED`**——即必须有人敲 `/gcbrun` 才跑。想"PR 一开就跑"，必须显式写 `COMMENTS_DISABLED` |
| `--include-logs-with-status` | 把**构建日志**回传进 GitHub 的 check run 结果里（PR 上直接看日志） | 强烈建议开；但日志过大可能被截断 |
| `--included-files='^(charts/\|tests/\|scripts/)'` | 只有改动命中这些 glob 才触发 | 用来跳过纯文档 PR，省 build-minute |
| `--ignored-files='^(docs/\|.*\.md$)'` | 改动命中就**不**触发 | 同上，二选一用 |
| `--require-approval` | 构建进 `QUEUED` 等人点确认 | **CI/测试不要开**（会让每个 PR 都卡在排队）；**生产发布才开** |
| `--service-account` | 执行构建的身份 | **PR trigger 用独立的低权限 SA**（见 §6） |
| `--substitutions=_A=1,_B=2` | 自定义变量 | 只能覆盖 trigger 里已存在的 `_XXX` key |

### 3.4 也可以用 trigger 配置文件（YAML）

```yaml
# trigger.yaml
name: pr-ci-test
region: asia-northeast1
serviceAccount: projects/<PROJECT_ID>/serviceAccounts/gcb-ci@<PROJECT_ID>.iam.gserviceaccount.com
github:
  owner: <OWNER>          # 1st gen 用；2nd gen 用 repository 字段
  name: <REPO>
  pullRequest:
    branch: '^main$'      # base branch 正则
filename: ci-test.yaml
includeBuildLogs: true
```

```bash
gcloud builds triggers create github --trigger-config=trigger.yaml
```

### 3.5 路线 B：Webhook trigger + GitHub 原生 Webhook

只有你**明确要走"自己贴 URL"这条路**时才用：

```bash
# 1) secret 放 Secret Manager
printf '%s' '<strong-random-secret>' | gcloud secrets create cb-webhook-secret --data-file=-

# 2) 建 webhook trigger
gcloud builds triggers create webhook \
  --name=pr-ci-webhook --region=asia-northeast1 \
  --webhook-auth-secret=projects/<PROJECT_ID>/secrets/cb-webhook-secret/versions/latest \
  --build-config=ci-test.yaml \
  --service-account=projects/<PROJECT_ID>/serviceAccounts/gcb-ci@<PROJECT_ID>.iam.gserviceaccount.com
```

GitHub 侧 `Settings → Webhooks` 里填 Payload URL（Cloud Build 给出的那个）+ Secret + `application/json`。

⚠️ **两个硬伤**：

1. **Payload 格式被 Cloud Build 固定死**，GitHub 原生 webhook 的 payload 对不上，必须先转换：

   ```json
   {
     "ref": "refs/heads/main",
     "sha": "<真实 commit SHA>",
     "repository": {
       "name": "my-repo",
       "url": "https://github.com/OWNER/my-repo"
     }
   }
   ```

2. **PR 事件拿不到 base branch / PR 号 / head SHA**，也很难做"PR 门禁"语义。

> **结论**：PR 门禁场景**一律用 GitHub App / Developer Connect**（§3.1 / §3.2）。

### 3.6 验证三板斧

```bash
# 1) trigger 配置对不对
gcloud builds triggers describe pr-ci-test --region=asia-northeast1

# 2) 有没有 build 被创建
gcloud builds list --region=asia-northeast1 --limit=5

# 3) 某个 build 的每一步状态
gcloud builds describe <BUILD_ID> --region=asia-northeast1
gcloud builds log <BUILD_ID> --region=asia-northeast1
```

---

## 4. PR 上的 Checks 到底是怎么来的（核心）

### 4.1 GitHub 的两个机制，别混

| | **Commit Status**（旧） | **Check Run**（新） |
| :--- | :--- | :--- |
| API | `POST /repos/{o}/{r}/statuses/{sha}` | `POST /repos/{o}/{r}/check-runs` |
| 标识 | `context`（字符串，如 `gcb/pr-ci-test`） | `name` + `check_suite` |
| 能不能分组 | 不能 | 能（check suite → PR 上一个"检查项"） |
| 能不能带日志/注释 | 不能 | 能（`output.summary` / `output.text`） |
| PR 页面显示 | Checks 标签下的一条记录 | Checks 标签下的一条记录 |
| 能当 required check | ✅ 可以 | ✅ 可以 |

**GitHub 的 PR 页面把两者统一渲染在 "Checks" 标签下**——所以你看到的那一栏，
底下既可能是 status，也可能是 check run。

### 4.2 Cloud Build 是怎么回写的

Cloud Build 的 GitHub 集成在构建开始/结束时会**自动**把状态回写到对应 commit：

| 构建状态 | 回写到 GitHub 的状态 |
| :--- | :--- |
| `QUEUED` / `WORKING` | `pending`（转圈） |
| `SUCCESS` | `success`（绿勾 ✅） |
| `FAILURE` | `failure`（红叉 ❌） |
| `INTERNAL_ERROR` / `TIMEOUT` | `error` / `failure` |

三个要点：

1. **PR 触发时，构建的是 GitHub 生成的"临时合并结果"**（PR head + base 最新代码），
   所以测到的是"你的改动 + 目标分支"的组合——**这正是 CI 想要的语义**。
2. **回写是 Cloud Build 做的，不需要你写代码、不需要 GitHub Actions**。
3. **check 的名字 / context 里带 trigger 名**（形如 `gcb/pr-ci-test` 或 `<App 名> / <trigger 名>`），
   **准确名字查一次就知道，别猜**：

   ```bash
   # PR 页面上的所有 check
   gh pr checks <PR_NUMBER>

   # 底层：这个 commit 上有哪些 check run / status
   gh api repos/<OWNER>/<REPO>/commits/<SHA>/check-runs --jq '.check_runs[] | {name, status, conclusion}'
   gh api repos/<OWNER>/<REPO>/commits/<SHA>/status --jq '.statuses[] | {context, state}'
   ```

### 4.3 一个 trigger = 一个 check

> **这是最关键的一条认知**：
> **一次 build 结束 = PR 上的一条 check**。
> 你 `ci-test.yaml` 里写 4 个 step（helm / python / bash / install），
> 在 PR 上**不会**变成 4 条 check，而是**1 条**（4 个 step 的总体结果）。

为什么？因为 Cloud Build 是"**一次构建 → 一个结果 → 一次回写**"，
它不会把每个 step 拆成独立的 check 回写。

### 4.4 想要"多个 check"怎么办（三选一）

| 方案 | 做法 | 优点 | 缺点 |
| :--- | :--- | :--- | :--- |
| **A. 多 trigger**（推荐） | 每个测试组建一个 trigger + 一份 config：`pr-ci-helm`、`pr-ci-python`、`pr-ci-bash` | 天然并行、各自独立重跑、可分别设 required | trigger 数量膨胀；每个 trigger 一次 build-minute |
| **B. 一个 build 内分组** | 保持一个 trigger，在 `ci-test.yaml` 里用 `allowFailure` / `waitFor` 组织，再在最后一步把分组结果汇总成一个结论 | 只有 1 个 build，成本低 | **PR 上仍然只有 1 条 check**；看不到"哪组挂了"的独立红叉 |
| **C. 自己写 Check** | 用 Checks API（`gh api` / `curl`）在构建脚本里创建 check run | 完全自定义（多条 check、注释、耗时） | 要自己处理 token、幂等、失败态上报；**放弃 Cloud Build 的自动回写** |

> **实战建议**：先做 **A**（3 个 trigger，PR 上 3 条独立 check，required 时也最直观）。
> 需求变复杂（要矩阵、要在 PR 里写评论）再考虑 **C**。

### 4.5 把它变成"硬门禁"：branch protection

Cloud Build 回写 check 只是"显示出来"，**要禁止合并**还得让 GitHub 强制它。

**控制台路径**：`Settings → Branches → Branch protection rules → Add rule`
→ Target branch: `main` → 勾 **Require status checks to pass** → 搜索并勾上 **Cloud Build 的那条 check**。

**CLI 等价写法**（`gh`）：

```bash
gh api -X PUT repos/<OWNER>/<REPO>/branches/main/protection \
  -F 'required_status_checks[strict]=true' \
  -F 'required_status_checks[contexts][]=gcb/pr-ci-test' \
  -F 'enforce_admins=true' \
  -F 'required_pull_request_reviews[required_approving_review_count]=1' \
  -F 'required_pull_request_reviews[dismiss_stale_reviews]=true'
```

四个必须知道的坑：

1. **`contexts[]` 必须和 GitHub 上显示的 check 名一字不差**。
   先开一个 PR 让它跑一次，用 `gh pr checks` 把名字抄下来。
2. **`strict=true`** = 必须先把 base 分支更新到最新才能合（避免"测试的是旧 base"）。
3. **check 没跑出来 ≠ 通过**。trigger 挂掉 / CI 没触发 → PR 永远卡住（这正是"门禁"想要的，
   但排查时先确认 trigger 活着）。
4. **PR 页面的 "Re-run jobs" 按钮只对 GitHub Actions 生效**。
   Cloud Build 要重跑：在 Cloud Build 控制台 **History → Retry**，或重新 push，
   或让 collaborator 再敲一次 `/gcbrun`。

---

## 5. "每个 PR 有自己的逻辑" 的四个实现层次

> 你的原话：**"看起来我对每一个 pull request 可以加对应的逻辑，是不是这样？"**
> 答：**是的，但"每个 PR"是 trigger 层的语义，"PR 之间不同的逻辑"要靠下面四层来实现。**

| 层次 | 按什么分叉 | 怎么实现 | 例子 |
| :--- | :--- | :--- | :--- |
| **① 目标分支** | PR 要合并进哪个分支 | trigger 上的 `--pull-request-pattern`（base branch 正则） | `^main$` 走完整 CI；`^release/.*$` 只走 smoke test |
| **② 改动的文件路径** | 这次 PR 改了哪些文件 | `--included-files` / `--ignored-files`（glob） | 只改 `docs/` → 不触发 build，省钱 |
| **③ 环境 / 参数** | 这次 CI 跑在什么环境 | trigger 的 `--substitutions=_ENV=xxx` + config 里的 `condition:` | `condition: '$_ENV == "prod"'` 挡住生产动作 |
| **④ PR 属性**（作者、标签、标题） | PR 本身带的信息 | ⚠️ **Cloud Build 不支持** | 需要 GitHub Actions 或自建 Checks API |

**一个 trigger 同时带 base 分支正则 + 文件过滤 + substitution 的例子**：

```bash
gcloud builds triggers create github \
  --name=pr-ci-test --region=asia-northeast1 \
  --repository=projects/<PROJECT_ID>/locations/asia-northeast1/connections/<CONN>/repositories/<REPO> \
  --pull-request-pattern='^main$' \
  --included-files='^(charts/|tests/|scripts/|Makefile)' \
  --build-config=ci-test.yaml \
  --substitutions=_ENV=dev \
  --service-account=projects/<PROJECT_ID>/serviceAccounts/gcb-ci@<PROJECT_ID>.iam.gserviceaccount.com \
  --comment-control=COMMENTS_DISABLED
```

**config 里用 substitution 做条件**：

```yaml
steps:
  - name: 'ubuntu:22.04'
    id: 'helm-lint-render'
    entrypoint: bash
    args: ['-c', 'make test-helm']
    condition: '$_ENV != "skip-helm"'
```

> ⚠️ **PR 场景的 `$BRANCH_NAME` 有坑**：PR 触发时它指向哪个分支（base 还是 head）
> 在不同场景下容易搞混。**要按分支分叉，请用 trigger 上的正则（层次 ①），不要在 config 里比较 `$BRANCH_NAME`。**
> 要拿 PR 的 head SHA / head 分支做逻辑，Cloud Build 没有现成变量，
> 得自己 `git` 查询或改用 GitHub Actions。

---

## 6. 安全：PR 是不可信输入

**从 fork 提的 PR 是最大的攻击面**：PR 作者可以改你的 `ci-test.yaml`，
让构建去偷 SA 凭据、读 Secret、往你的环境里写东西。

| 措施 | 怎么做 |
| :--- | :--- |
| **PR trigger 用独立的低权限 SA** | 只给 `roles/logging.logWriter` + `roles/storage.objectUser` + `roles/storage.bucketViewer`（+ 确实要写产物时给 `artifactregistry.writer` 写到**临时仓库**）。**不给** `secretmanager.secretAccessor`、**不给** 部署权限 |
| **PR 的 config 里不含 secret substitution** | PR trigger 用的 config 不带任何 `_SECRET_XXX` |
| **敏感值走 Secret Manager，不走 substitution** | substitution 会明文写进构建元数据和日志 |
| **限制 builder 镜像** | 用固定的 `ubuntu:22.04` / `gcr.io/cloud-builders/*`，别让 PR 自选镜像 |
| **对外 PR 要人工放行** | `--comment-control=COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY`：外部贡献者的 PR 必须由 collaborator 敲 `/gcbrun` 才跑 |
| **CI 不碰生产** | PR 只跑 test/render；部署永远由 push 到 `main` 的独立 trigger（或 Cloud Deploy）来做 |

> **完整的加固清单**见 [how-to-github-trigger-cloud-build.md](how-to-github-trigger-cloud-build.md) §11。

---

## 7. 排错手册

### 7.1 分层定位

```
第 1 层：PR 开了，但**根本没有 build**？
   -> webhook 通路 / trigger 匹配问题
     检查：App 是否装到本 repo、connection 是否 ACTIVE、
           --pull-request-pattern 是否匹配 base 分支、
           --comment-control 是否要求 /gcbrun、
           --included-files 是否把改动全过滤掉了
        ↓ 有 build 了
第 2 层：build 创建了但**拉不到源码**？
   -> 身份授权问题
     检查：App 的 Contents: read 权限、2nd gen 的 connectionUser、repo 是否在授权列表
        ↓ 源码拉到了
第 3 层：某个 step **失败**？
   -> 构建本身
     检查：gcloud builds log、SA 角色、PATH 是否跨 step 共享、依赖装到哪了
        ↓ 构建成功
第 4 层：构建成功了但 **PR 上没有 check**？
   -> 回写链路 / 挂载的 commit 不对
     检查：gh pr checks、gh api .../commits/SHA/check-runs、
           PR 是不是被 base 分支过滤掉了、是不是被 require-approval 卡在 QUEUED
```

### 7.2 症状对照表

| 现象 | 根因 | 处理 |
| :--- | :--- | :--- |
| **PR 开了没反应，也没有 build** | `--comment-control` 默认 `COMMENTS_ENABLED`，要有人敲 `/gcbrun` | 加 `--comment-control=COMMENTS_DISABLED`，或让 collaborator 敲 `/gcbrun` |
| **PR 开了没反应** | `--pull-request-pattern` 写的是 head 分支而不是 base 分支 | 该参数匹配的是**目标分支**，用 `gh pr view --json baseRefName` 确认 |
| **改了 docs 就没 build** | `--included-files` / `--ignored-files` 过滤掉了 | 调整 glob |
| **PR 上有 check，但一直转圈** | 构建卡在 `QUEUED`（并发配额满 / `--require-approval`） | `gcloud builds list` 看排队；CI trigger 不要开 `--require-approval` |
| **PR 上有 check，但名字不是我以为的** | context 里带 trigger 名 / App 名 | `gh pr checks` 看准确名字，再填进 branch protection |
| **PR 上完全不显示 check** | App 没装 / 没授权到这个 repo / region 不一致 | GitHub → Settings → Developer settings → GitHub Apps 检查安装范围；`gcloud builds connections describe` 看 ACTIVE |
| **第二个 step 说 `make: command not found`** | 依赖装在了 step 容器里（不在 `/workspace`），或 `PATH` 没带上 | 装到 `/workspace/.ci-deps`，后续 step `env` 里写 `PATH` |
| **本地过、CI 挂** | 本地有工具链、CI 镜像里没有 | 把依赖安装写进仓库脚本，CI 与本地共用 |
| **build 成功但 Check 是红的** | 某个 step 失败但被 `allowFailure` 掩盖 / 退出码非 0 | `gcloud builds describe` 看每个 step 的 `exitCode` |
| **PR 的合并按钮一直禁用** | required check 没上报 | 先确认 trigger 活着、check 名对得上 |
| **想重跑但按钮无效** | "Re-run jobs" 只对 GitHub Actions 生效 | Cloud Build 控制台 History → Retry，或重新 push |

---

## 8. 端到端 checklist

**A. 仓库侧**

- [ ] `ci-test.yaml` 用的是 **Cloud Build schema**（`steps[].name` 是镜像、`command` → `args`/`script`）
- [ ] 依赖安装脚本把工具装进 `/workspace` 下，后续 step 的 `PATH` 指过去
- [ ] `Makefile` 里 `test-helm` / `test-python` / `test-bash` 三个目标存在且本地可跑
- [ ] 顶层 `timeout` 和 `serviceAccount` 写好了

**B. GCP 侧**

- [ ] 仓库已连接（1st gen 或 2nd gen，见 how-to 文档 §4/§5）
- [ ] 专用 build SA 已建，且**不是** `{PROJECT_NUMBER}@system.gserviceaccount.com`
- [ ] build SA 角色最小化（见 §6）
- [ ] `gcloud builds triggers describe pr-ci-test` 里 repo / pull-request-pattern / build-config / SA 都对
- [ ] `--comment-control` 明确写了（别吃默认值）
- [ ] `--include-logs-with-status` 已开（PR 上直接看日志）

**C. 端到端**

- [ ] 开一个 PR → `gcloud builds list` 里出现新 build
- [ ] `gcloud builds describe` 里每个 step 都绿
- [ ] PR 页面 **Checks** 标签出现这条 check
- [ ] 故意写坏一个测试 → check 变红 → 日志能定位到失败 step
- [ ] branch protection 已把这条 check 设为 required → 红的 PR 合不进去
- [ ] 绿的 PR 能合

---

## 9. 官方文档与配套阅读

| 主题 | 链接 |
| :--- | :--- |
| Build config schema（`steps` / `args` / `waitFor` …） | https://cloud.google.com/build/docs/build-config |
| 内置 substitution 变量 | https://cloud.google.com/build/docs/configuring-builds/substitute-variable-values |
| Cloud Builders 镜像列表 | https://cloud.google.com/build/docs/cloud-builders |
| PR / GitHub 触发器（2nd gen） | https://cloud.google.com/build/docs/automating-builds/github/build-repos-from-github |
| GitHub App 触发器（1st gen） | https://cloud.google.com/build/docs/automating-builds/create-github-app-triggers |
| Developer Connect | https://cloud.google.com/developer-connect/docs/overview |
| GitHub **Checks API**（自己写 check 时） | https://docs.github.com/en/rest/checks/runs |
| GitHub **Commit Status API** | https://docs.github.com/en/rest/commits/statuses |
| GitHub 分支保护 / required status checks | https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches |

**配套阅读（同目录）**

- [how-to-github-trigger-cloud-build.md](how-to-github-trigger-cloud-build.md) —— **GitHub ↔ Cloud Build 的完整打通**：GitHub App 原理、1st/2nd gen 选型、源码拉取链路、IAM 全景、GitHub 企业版（内网打通 / 自签 CA）、加固清单、排错手册
- [cloudbuild-guide.md](cloudbuild-guide.md) —— Cloud Build 主文档：Schema 速查、CLI 速查、成本配额
- [examples/ci-test-pr.yaml](examples/ci-test-pr.yaml) —— 本文 `ci-test.yaml` 的可复制模板
