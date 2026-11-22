# 26 · Makefile × Argo CD：在 GitOps 里能做什么、不能做什么

> **直接回答**：「同事提了用 Makefile 管理 Argo CD 的行为，这可行吗？
> Makefile 在 Argo CD 的流程里有没有特别好用、实用的功能？」
>
> **一句话结论**
> ★ **可行，而且值得做——但要把它放在正确的位置。**
> Makefile 在这个体系里是**「人的入口」和「仓库的可执行文档」**：
> ① 把散落的检查/渲染/运维脚本**收口成一个入口**（`make ci`）；
> ② 让评审人**本地一键复现** CI 的判定；
> ③ 作为 **Argo CD 的 manifest 生成器（CMP）** 或 **集群内 Hook 的执行体**。
>
> ⚠️ **但它不能当服务端门禁**——「谁跑的 make」决定了它的权威性；
> 真正的强制力仍然在 **Ruleset + required status check**（见 [`19`](./19-no-actions-alternative-matrix.md)）。
> 一句话：**Make 管「怎么做事」，GitHub 管「准不准做」，Argo CD 管「做完没有」。**

---

## 目录

| 章节 | 内容 |
|---|---|
| [`1](#1-先把-make-和-argocd-的心智模型对齐) | 概念对照表 + 最根本的一条差异 |
| [`2](#2-同事这个-makefile-用了什么) | 拆解 daydayup/Makefile：哪些能搬，哪些要改 |
| [`3](#3-★-四个真正能落地的集成点) | **P1 统一入口 / P2 CMP / P3 Hook / P4 审批证据** |
| [`4](#4-★-makefile-特有实用功能清单) | **15 个功能 → 在 GitOps 里的具体用途** |
| [`5](#5-红线不能做什么) | 6 条明确的不可能 |
| [`6](#6-落地步骤) | 4 步，从今天就能做第一步 |
| [`7](#7-附录可直接用的-makefile) | ★ 给 gitops-layout 仓库的完整 Makefile |
| [`8](#8-坑清单) | 12 条 |

---

## 1. 先把 Make 和 Argo CD 的心智模型对齐

| 概念 | Make | Argo CD | 说明 |
|---|---|---|---|
| **期望** | target（目标文件） | Application / 资源清单 | "想要什么" |
| **依赖** | 依赖文件 | ApplicationSet / sync wave | "先做什么后做什么" |
| **要不要执行** | 时间戳比较（目标比依赖旧？）、`.PHONY`（总是执行） | diff（Git ≠ 集群？）+ `automated.enabled` | ★ **两者判断依据完全不同** |
| **执行** | shell 命令 | controller 调 K8s API | — |
| **预览** | `make -n`（干跑） | `argocd app diff` / sync `--dry-run` | ★ **语义高度相似** |
| **失败处理** | 目标失败 → 停（默认） | operation failed → 状态写回 | 都是"失败即停" |
| **并行** | `make -j` | 同 wave 并发 | — |
| **中间产物** | 中间文件（可被删） | hook 资源（按 delete-policy 删） | — |

### 1.1 ★ 最根本的一条差异

> **Make 的世界模型是「文件 + 时间戳」，Argo CD 的世界模型是「内容 + 实际状态」。**

这带来一个**必须记住的坑**：

| 场景 | Make 的判断 | Argo CD 的判断 |
|---|---|---|
| 有人改了 Git 里一个 YAML，但**内容完全没变** | ★ **Make 认为"没变"**（内容没变） | ★ **Argo CD 认为"没变"**（diff 为空 → Synced） |
| 有人改了集群里的资源 | Make **完全不知道** | Argo CD 发现 OutOfSync → selfHeal |
| 从 Git 全新 clone 出来 | ★ **所有文件时间戳相同** → Make 认为"都是最新的" → **什么都不做** | Argo CD 正常 diff |

> ⚠️ **推论**：
> **不要用 Make 的时间戳去判断"Git 内容是不是新版本"。**
> 在 GitOps 里，"新版本"的唯一权威是 **commit SHA**。
> → 如果要用 make 做"生成"，**幂等键必须是内容哈希或 SHA，不是时间戳**。

---

## 2. 同事这个 Makefile 用了什么

参照 [`daydayup/Makefile`](../../../../go/daydayup/Makefile)（140 行）与
[`daydayup/using-make.md`](../../../../go/daydayup/using-make.md)（Make 原理笔记）。

| 用到的能力 | 在 daydayup 里的作用 | 搬到 GitOps 仓库里对应什么 |
|---|---|---|
| `.DEFAULT_GOAL := help` | 默认打帮助，不误伤 | ★ 同样重要：新人跑 `make` 不该触发部署 |
| `## 注释` + `help` 目标 | 自文档 | ★ 同款：`make help` 就是"仓库的操作手册" |
| `?=` 变量 | `GO ?= go` 可被环境覆盖 | ★ 换成 `KUBECTL ?= kubectl` / `ARGOCD ?= argocd`，CI 与本地可各自覆盖 |
| `.PHONY` | 目标不是真实文件 | ★ **必须**：`ci`/`lint`/`sync` 没有对应文件，不加会被当成"已存在" |
| `$(wildcard)` | 动态发现 `dNN` 目录 | ★ 动态发现 `apps/*/`、`clusters/*/` |
| `ifeq` + `command -v` | 工具不在就降级 | ★ 工具探测：没装 kubectl/helm 就跳过对应检查 |
| `%` 模式规则 + `MAKECMDGOALS` | `make new slices` 吞掉多余参数 | `make sync APP=api-prod` / `make render app=nginx` |
| `exit 1` | 参数缺失直接失败 | 同款 |

> ★ **结论**：同事这个 Makefile 的**风格**（自文档 + 工具探测 + 优雅失败）
> **完全适合** GitOps 仓库。真正要改的是**内容**——
> 把"跑 Go 测试"换成"跑 GitOps 的静态检查 / 渲染 / Argo CD 操作"。

---

## 3. ★ 四个真正能落地的集成点

### P1 · 统一入口（**最推荐，第一天就能做**）

**做什么**：把仓库里散落的检查脚本收口成 `make ci` / `make lint` / `make render`。

本仓库现状（[`examples/gitops-layout/`](../examples/gitops-layout/README.md)）：
**11 个检查工具、11 种调用方式**，新人要读文档才知道怎么跑。

```bash
# 现在
./ci-check.sh
python3 appset-simulator.py --json
python3 render-check.py --only nginx
kubectl kustomize bootstrap
python3 ../check-doc-links.py --path ../..

# 有了 Makefile 之后
make ci          # 全跑
make ci-quick    # 跳过要 kubectl 的
make preview     # 看看会生成哪些 Application
make docs-check  # 只查文档链接
```

**为什么在你们的场景里特别重要**：
Actions 被禁之后（见 [`19`](./19-no-actions-alternative-matrix.md)），
**"CI"这件事需要一个与 CI 无关的统一入口**——
无论最终由 CR Check、外部 CI、还是新人本地来跑，**跑的都是同一个 `make ci`**。
→ **Makefile 是"CI 配置"与"检查逻辑"之间的解耦层。**

**判定标准**：`make ci` 的退出码 = 0/非 0，与 `ci-check.sh` 完全一致 → 可直接被任何执行器包一层。

---

### P2 · CMP：让 Make 成为 Argo CD 的 manifest 生成器

**这是唯一一种"make 真正进入 Argo CD 内部执行路径"的方式。**

**官方保证**（upstream v3.5.6 `docs/operator-manual/config-management-plugins.md`）：
CMP（Config Management Plugin）v2 以 **sidecar** 形式跑在 `argocd-repo-server` 里，
配置文件在 sidecar 的 `/home/argocd/cmp-server/config/plugin.yaml`，
提供 `init` / `generate` / `discover` 三个命令。

**`generate` 的契约（官方原文要点）**：
- 在 **Application 的 source 目录**里执行；
- **stdout 只能是合法的 K8s YAML/JSON**；
- **非 0 退出码 = manifest 生成失败**；
- 日志写 **stderr**（会显示在 UI），错误信息也会送到 UI（**别打印敏感信息**）。

**用 make 做 `generate` 的最小配置**：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ConfigManagementPlugin
metadata:
  name: make-generator
spec:
  version: v1.0
  init:
    command: [make]
    args: ["init"]
  generate:
    command: [make]
    args: ["manifests"]
  discover:
    find:
      glob: "**/Makefile"
```

**优点**：
- ★ **Git 里只有"源"，集群里是"产物"** —— 真正的 single source of truth；
- 复杂生成逻辑（多份 YAML 拼装、模板渲染）不必硬塞进 Kustomize/Helm；
- 同一份 Makefile 也能在本地跑（`make manifests`），**本地所见 = 集群所得**。

**代价（必须先想清楚）**：

| 代价 | 说明 |
|---|---|
| **失去"人可读"的 YAML** | 评审时看的是 Makefile，不是最终 YAML → **评审难度上升** |
| **Argo CD 的 diff 变了** | Argo CD 看到的是 CMP 产出的 manifest，不是 Git 里的 YAML |
| **超时** | 官方：CMP 受 `argocd-cmd-params-cm` 的 `server.repo.server.timeout.seconds`（默认 60s）与 sidecar 的 `ARGOCD_EXEC_TIMEOUT`（默认 90s）约束 |
| **★ 空产物 + prune = 删资源** | 官方明确警告："If a CMP renders blank manifests, and `prune` is set to `true`, Argo CD will automatically remove resources." → **generate 失败必须让退出码非 0** |
| **管道吞错误** | 官方提醒 `kustomize build . | cat` 不会传错误 → 用 `set -o pipefail` |
| **缓存** | 官方：repo-server 会把 CMP 错误缓存在 Redis，**改完要 Hard Refresh** |
| **一个 Application 只能有一个 CMP** | 官方限制 |

> ★ **判断标准**：**只有当你的 manifests 确实无法用 Kustomize/Helm 表达时，才上 CMP。**
> 如果只是想"少写点 YAML"，Kustomize + `resources` 更合适。
> CMP 是**最后手段**，不是"更酷的 Kustomize"。

---

### P3 · Hook：让 Make 在集群里跑

**做什么**：把"迁移脚本 / 备份 / 数据初始化"这类**有副作用的动作**，
做成 **PreSync hook**，容器里跑 `make migrate`。

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: "{{.app.metadata.name}}-migrate"
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    argocd.argoproj.io/sync-wave: "-1"
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: <your-registry>/app-tooling:v1.2.3   # 镜像里带 make + 源码
          args: ["make", "migrate"]
```

**优点**：★ **失败的副作用不会留下**——PreSync 失败，Sync 阶段**根本不执行**（见 [`22`](./22-resource-hooks-and-sync-phases.md)）。

**要求**：
- 镜像里要有 `make`（Alpine：`apk add make`）；
- 脚本要**幂等**（重试时不能重复执行副作用）；
- 不要把凭据写进 Makefile，用 Secret 注入。

---

### P4 · 生成物作为"审批证据"（**容易被忽略，但很有价值**）

**场景**：审批人想在点"批准"之前，**看到这次变更真正会落到集群里的样子**。

**做法**：
```bash
# 本地 / CR Check 里生成真实产物
make manifests APP=api-prod > /tmp/rendered.yaml
# 作为 PR 评论贴上去（CR Check 已有 PR 写权限）
gh pr comment <PR> --body-file /tmp/rendered.yaml
```

**为什么值得做**：
- GitOps 里**"提交的是源、部署的是产物"**，审批人看源 ≠ 看产物；
- 产物贴到 PR 上 → **审批依据可追溯、可 diff、可复现**；
- 和 CR 体系天然契合：**变更单里引用的产物 = 审批人看的那份**。

> ★ 这条不需要任何 Argo CD 改动，**但它是 Make 在 GitOps 里价值最高的一种用法**：
> **把"不可见的部署结果"变成"可见的审批材料"。**

---

## 4. ★ Makefile 特有实用功能清单

> 回答"有没有特别好用或实用的功能"——以下每一项都在 GitOps 里有明确用途。

| # | 特性 | 语法 | 在 GitOps 里的用途 |
|---|---|---|---|
| **1** | ★ **干跑** | `make -n` | ★ **预览"会发生什么"**，与 Argo CD 的 diff/dry-run 语义一致。改完 Makefile 先 `make -n` 确认不会误触发部署 |
| **2** | ★ **失败不留半成品** | `.DELETE_ON_ERROR:` | 生成产物时，**中途失败不会留下半个 YAML** 被提交/被部署 |
| **3** | **总是执行** | `.PHONY: ci lint` | 目标没有对应文件时**必须**声明，否则 Make 认为"已经是最新的"而跳过 |
| **4** | **变量可覆盖** | `KUBECTL ?= kubectl` | 本地用本地 kubectl、CI 用别的版本；**同一份 Makefile 多环境复用** |
| **5** | **动态发现** | `$(wildcard apps/*)` | 自动为每个 app 生成目标，不用手写 N 个 target |
| **6** | **工具探测与降级** | `ifeq ($(shell command -v helm),)` | 没装 helm 就跳过并**明确告知**，而不是报错退出 |
| **7** | **模式规则** | `%-render: ; $(KUSTOMIZE) build $(@D)` | 一个规则覆盖所有 app/overlay |
| **8** | **并行** | `make -j4` | 渲染多个组件时并行（注意：并行下输出会交错，**别同时写 stdout**） |
| **9** | **禁止并行** | `.NOTPARALLEL:` | 涉及共享状态（同一个 kubeconfig、同一份 output）时 |
| **10** | **多文件拆分** | `include mk/ci.mk` | 把检查/渲染/运维拆成多个文件，避免单文件膨胀 |
| **11** | **吞掉多余参数** | `MAKECMDGOALS` | `make sync api-prod` 这种"动词+宾语"写法 |
| **12** | ★ **单个 shell 执行** | `.ONESHELL:` | 多行脚本用同一个 shell（管道、条件更自然），但**失败行为要自己控制** |
| **13** | **静默命令** | `@command` | 不把命令本身打进日志（输出更干净） |
| **14** | **显示命令但不执行** | `+command` | 与 `-n` 相反：只打印，**适合生成"给人抄的命令"** |
| **15** | **哨兵文件** | `.stamp: ; touch $@` | 标记"某一步做过"，避免重复执行昂贵步骤 |

> ★ **在 GitOps 里最被低估的是第 1 条（干跑）和第 2 条（`.DELETE_ON_ERROR`）**：
> - `make -n` 让你在**执行任何有副作用的目标前**先看一遍；
> - `.DELETE_ON_ERROR` 直接消灭"生成了一半的 YAML 被提交"这类事故。


---

## 5. 红线：不能做什么

| # | 不能 | 为什么 | 该用什么 |
|---|---|---|---|
| **R1** | ★ **把 `make ci` 当服务端强制门禁** | "谁跑的 make"决定权威性：本地跑 = 可跳过；GitHub 上没有 check run = ruleset 无从引用 | **Ruleset + required status check**（CR Check 产出的 check） |
| **R2** | 在 Argo CD **自动同步路径**里做副作用操作 | 自动同步会重试；副作用被重复执行 = 事故 | 副作用放 **PreSync hook**（幂等 + 失败即停） |
| **R3** | 用 make 的**时间戳**判断"Git 内容是不是新的" | clone 后时间戳相同 → 判断失真 | **commit SHA / 内容哈希** |
| **R4** | 同一份内容**既存源又存产物**（生成后提交） | 两份真相 → 漂移、评审困惑、"谁改的"歧义 | 要么纯源（CMP），要么纯产物（生成后提交且**只保留产物**） |
| **R5** | 把 Makefile 当**审计日志** | make 不记录谁在什么环境跑的 | Git 历史 / check run / Argo CD operationState |
| **R6** | 在 Makefile 里写**凭据** | 明文进 Git | Secret / External Secrets / Secret Manager |

> ★ **一句话**：Make 的产物是**便利性**（更快、更一致、更少踩坑），
> 不是**权威性**（谁都不能绕过）。
> 凡是"必须无法绕过"的地方，一律交给 GitHub 与 Argo CD。

---

## 6. 落地步骤

| 步 | 做什么 | 产出 | 验收 |
|---|---|---|---|
| **S1**（半天） | 给 GitOps 仓库加一个 Makefile，把现有脚本收口 | `Makefile` + `make help` | 新人 `make help` 就能跑全部检查 |
| **S2**（半天） | 把 `make ci` 接到**真正的执行点** | ① CR Check 在 webhook 里调 `make ci`（**Actions 禁用时的首选**）② 或外部 CI 调 `make ci` | 不合规 PR **合不了**（联调验证） |
| **S3**（1 天） | 把 `make` 的输出变成 **check run 的 summary** | check run 里带失败项清单 | 审批人不用去本地复现就能看到"哪一项挂了" |
| **S4**（可选） | 用 `make manifests` 生成**产物作为 PR 评论** | 审批人看得到真实部署内容 | PR 上有产物 diff |
| **S5**（谨慎） | 评估是否需要 **CMP** | plugin.yaml + sidecar | **先回答**：Kustomize/Helm 真的做不到吗？ |

> ★ **S2 的关键**：Actions 禁用后，`make ci` 必须有**服务端执行点**。
> 你们已经有一个现成的：**CR Check（自研 GitHub App）**。
> → 它收到 PR 事件 → 拉代码 → 跑 `make ci` → 把结果写成 check run。
> 这条路**不需要任何 CI 平台**，而且 check run 的 context 名可以固定，
> ruleset 直接引用（见 [`19 `3`](./19-no-actions-alternative-matrix.md) 与
> [`git-apps/14`](../git-apps/14-rulesets-and-gitapp-gate.md)）。

---

## 7. 附录：可直接用的 Makefile

> 位置：**`argocd-topics/examples/gitops-layout/Makefile`（已落地）**
> 风格与 [`daydayup/Makefile`](../../../../go/daydayup/Makefile) 保持一致。
>
> ✅ **已实测**（本机，Argo CD v3.5.6 仓库）：
>
> | 命令 | 结果 |
> |---|---|
> | `make help` | 正常输出，且 **动态列出了 5 个 app**（api / gatekeeper / gateway / nginx / redis） |
> | `make apps` | 正常 |
> | `make lint` | **退出码 0**（4 个检查工具全过） |
> | `make sync APP=api-prod`（不给 REV） | ★ **正确拒绝**（退出码非 0，打印"必须显式指定 REV"） |
> | `make -n sync APP=api-prod REV=deadbeef` | 只打印命令、**不执行**（干跑） |
>
> ⚠️ 需要 `kubectl` 的目标（`render` / `bootstrap`）在没装 kubectl 的机器上会失败，
> 这与既有 `ci-check.sh --quick` 的降级策略一致。

```make
# =============================================================================
#  gitops-layout/Makefile —— 这个仓库的统一入口
# -----------------------------------------------------------------------------
#  为什么要它：
#    这个仓库有 12 个检查/脚手架工具、12 种调用方式。新人记不住，
#    CI 也得在 workflow 里抄一遍参数。Makefile 把它们收口成**一个入口**：
#      make help          看所有命令
#      make ci            跑全部检查（提交前 / CI 都跑这个）
#      make ci-quick      跳过需要 kubectl 的（没装 kubectl 也能跑）
#      make preview       看看会生成哪些 Application
#      make render        渲染所有 overlay（kubectl kustomize build）
#      make bootstrap     验证根应用能不能 build
#      make sync          触发 Argo CD 同步（必须显式给 APP 和 REV）
#      make doctor        Argo CD 集群体检（只读）
#
#  集群纳管（fleet）：
#      make new-cluster   加一个集群（生成 YAML，不碰凭据）
#      make enable-comp   给集群加一个组件
#      make cluster-check 集群清单自检
#      make fleet-list    集群 × 组件矩阵
#      make fleet-drift   ★ 对账：Git 声明 vs Argo CD 实际注册
#
#  设计原则（和 daydayup/Makefile 一致）：
#    ① .DEFAULT_GOAL := help  —— 敲 make 不该误触发任何有副作用的事
#    ② 工具不在就降级并说明  —— 不因为没装 helm 就整个失败
#    ③ 变量用 ?=            —— 本地与 CI 可以各自覆盖
#    ④ 有副作用的目标一律 .PHONY
# =============================================================================

SHELL        := /bin/bash
PY           ?= python3
KUBECTL      ?= kubectl
ARGOCD       ?= argocd
HELM         ?= helm

# 目录（脚本自己算的，这里保持一致）
LAYOUT_DIR   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
EXAMPLES_DIR := $(abspath $(LAYOUT_DIR)/..)
TOPICS_DIR   := $(abspath $(EXAMPLES_DIR)/..)

# 动态发现
APPS         := $(sort $(notdir $(wildcard $(LAYOUT_DIR)/apps/*)))
OVERLAYS     := $(wildcard $(LAYOUT_DIR)/apps/*/overlays/*/kustomization.yaml)

.DEFAULT_GOAL := help

# ★ 生成物中途失败不要留半成品
.DELETE_ON_ERROR:
# ★ 涉及共享状态的目标不要并行
.NOTPARALLEL: sync render-all

.PHONY: help ci ci-quick lint preview docs-check render render-all bootstrap \
        sync status doctor apps clean \
        new-cluster enable-comp cluster-check fleet-list fleet-drift

help: ## 显示所有命令
	@echo "gitops-layout —— 统一入口"
	@echo ""
	@echo "── 检查 ─────────────────────────────────────────────"
	@echo "  make ci            跑全部检查（11 项）"
	@echo "  make ci-quick      跳过需要 kubectl 的检查"
	@echo "  make lint          只跑配置/规则契约检查（不需要 kubectl）"
	@echo "  make preview       预览会生成哪些 Application"
	@echo "  make docs-check    检查文档链接与锚点"
	@echo "  make render        渲染所有 overlay 并丢弃输出"
	@echo "  make bootstrap     验证根应用能不能 build"
	@echo ""
	@echo "── Argo CD ──────────────────────────────────────────"
	@echo "  make sync          同步（用法：make sync APP=api-prod REV=<sha>）"
	@echo "  make status        看应用状态（用法：make status APP=api-prod）"
	@echo "  make doctor        Argo CD 集群体检（只读）"
	@echo ""
	@echo "── 集群纳管 ─────────────────────────────────────────"
	@echo "  make new-cluster   加集群（加 DRY_RUN=1 只预览不落盘）"
	@echo "                        PROJECT=acme-dev SERVER=https://... COMPONENTS=\"nginx api\""
	@echo "  make enable-comp   加组件：make enable-comp CLUSTER=dev-03 COMPONENT=nginx"
	@echo "  make cluster-check 集群清单 + AppSet 一致性自检"
	@echo "  make fleet-list    集群 × 组件矩阵"
	@echo "  make fleet-drift   ★ 对账：Git 声明 vs Argo CD 实际注册"
	@echo ""
	@echo "可用 APP: $(APPS)"

# ── 检查 ────────────────────────────────────────────────────────────────────
ci: ## 跑全部检查
	@./ci-check.sh

ci-quick: ## 跳过需要 kubectl 的检查
	@./ci-check.sh --quick

lint: ## 只跑不需要 kubectl 的检查
	@$(PY) "$(EXAMPLES_DIR)/validate-examples.py"
	@$(PY) "$(EXAMPLES_DIR)/rulesets/validate-rulesets.py"
	@$(PY) "$(EXAMPLES_DIR)/rulesets/simulate-commit-gate.py" --all
	@$(PY) "$(EXAMPLES_DIR)/check-doc-links.py" --path "$(TOPICS_DIR)"

preview: ## 预览会生成哪些 Application
	@$(PY) "$(LAYOUT_DIR)/preview-appset.py"

docs-check: ## 检查文档链接与锚点
	@$(PY) "$(EXAMPLES_DIR)/check-doc-links.py" --path "$(TOPICS_DIR)"

# ── 渲染 ────────────────────────────────────────────────────────────────────
render: ## 渲染所有 overlay（只验证，不落盘）
ifeq ($(KUBECTL),)
	@echo "✗ 没有 kubectl"; exit 1
endif
	@for f in $(OVERLAYS); do \
		echo "── $$f"; \
		$(KUBECTL) kustomize "$$(dirname $$f)" > /dev/null || exit 1; \
	done

render-all: ## 渲染所有 overlay 并打印产物
	@for f in $(OVERLAYS); do \
		echo "── $$f"; \
		$(KUBECTL) kustomize "$$(dirname $$f)" || exit 1; \
	done

bootstrap: ## 验证根应用能 build
	@$(KUBECTL) kustomize "$(LAYOUT_DIR)/bootstrap" > /dev/null && echo "✓ bootstrap 可以 build"

apps: ## 列出应用
	@for a in $(APPS); do echo "  $$a"; done

# ── Argo CD ─────────────────────────────────────────────────────────────────
# ★ 同步必须显式给 APP 和 REV：绝不"同步到最新"。
#   理由见 gh-enterprise/23（driver 的幂等键 = app + revision）。
sync: ## 同步（make sync APP=api-prod REV=<sha>）
ifeq ($(APP),)
	@echo "用法: make sync APP=<name> REV=<sha>"; exit 1
endif
ifeq ($(REV),)
	@echo "★ 必须显式指定 REV（不要同步到 latest）"; exit 1
endif
	@$(ARGOCD) app sync "$(APP)" --revision "$(REV)" --prune=false

status: ## 看应用状态（make status APP=api-prod）
ifeq ($(APP),)
	@echo "用法: make status APP=<name>"; exit 1
endif
	@$(ARGOCD) app get "$(APP)" --core

doctor: ## Argo CD 集群体检（只读）
	@bash "$(EXAMPLES_DIR)/argocd-health.sh"

# ── 集群纳管（fleet）──────────────────────────────────────────────────────────
# ★ 这些目标只生成**声明**（YAML），绝不碰凭据。
#   Cluster Secret 含凭据 → 必须手工在 Argo CD 里注册（见 new-cluster.sh 第 ④ 步）。
new-cluster: ## 加集群（make new-cluster NAME=dev-03 ENV=dev PROJECT=... SERVER=... COMPONENTS="nginx api"）
ifeq ($(NAME),)
	@echo "用法: make new-cluster NAME=<cluster> ENV=<dev|stg|prod> PROJECT=<gcp-project> SERVER=<url> [COMPONENTS=\"a b\"]"; exit 1
endif
ifeq ($(ENV),)
	@echo "★ 必须指定 ENV（dev/stg/prod）"; exit 1
endif
ifeq ($(SERVER),)
	@echo "★ 必须指定 SERVER（Kubernetes API 地址，必须与 Cluster Secret 一致）"; exit 1
endif
	@args=""; for c in $(COMPONENTS); do args="$$args --component $$c"; done; \
	"$(LAYOUT_DIR)/new-cluster.sh" \
		--name "$(NAME)" \
		--env "$(ENV)" \
		$(if $(PROJECT),--project "$(PROJECT)",) \
		--server "$(SERVER)" \
		$(if $(NAMESPACE),--namespace "$(NAMESPACE)",) \
		$(if $(DRY_RUN),--dry-run,) \
		$$args

enable-comp: ## 加组件（make enable-comp CLUSTER=dev-03 COMPONENT=nginx）
ifeq ($(CLUSTER),)
	@echo "用法: make enable-comp CLUSTER=<name> COMPONENT=<component>"; exit 1
endif
ifeq ($(COMPONENT),)
	@echo "用法: make enable-comp CLUSTER=<name> COMPONENT=<component>"; exit 1
endif
	@"$(LAYOUT_DIR)/enable-component.sh" --cluster "$(CLUSTER)" --component "$(COMPONENT)" $(if $(DRY_RUN),--dry-run,)

cluster-check: ## 集群清单 + AppSet 一致性自检
	@$(PY) "$(LAYOUT_DIR)/validate-clusters.py"
	@$(PY) "$(LAYOUT_DIR)/appset-simulator.py" | tail -20

fleet-list: ## 集群 × 组件矩阵
	@$(PY) "$(LAYOUT_DIR)/fleet.py" list

fleet-drift: ## ★ 对账：Git 声明 vs Argo CD 实际注册（FLEET_STRICT=1 时有差异即失败）
	@$(PY) "$(LAYOUT_DIR)/fleet.py" drift $(if $(FLEET_STRICT),--strict,)

clean: ## 清理临时产物
	@rm -rf .tmp out
```

### 7.1 用法要点

| 场景 | 命令 |
|---|---|
| 新人第一次进仓库 | `make help` → `make ci-quick` |
| 提交前 | `make ci` |
| 想看这次改动会生成什么 | `make preview` |
| 只改了一个 app，想快速验证 | `make render-only APP=nginx`（把 `render` 改成接受 `ONLY` 变量） |
| 紧急上生产 | `make sync APP=api-prod REV=<审批过的 sha>` |
| 排查同步卡住 | `make status APP=api-prod` → `make doctor` |

> ★ **`make sync` 刻意要求显式 REV**，不是为了麻烦，
> 而是把 [`23 CD Driver`](./23-cd-driver-and-argocd-api-sync.md) 里最危险的那个坑
> （"不传 revision → 同步了没审批的版本"）**在工具层面就堵死**。

---

## 8. 坑清单

| # | 坑 | 后果 | 规避 |
|---|---|---|---|
| 1 | 忘了 `.PHONY` | 目标"已存在" → 静默跳过 | 所有无对应文件的目标都列进 `.PHONY` |
| 2 | `make ci` 的退出码被管道吞掉 | CI 永远绿 | `set -o pipefail`；检查 `$?` |
| 3 | 工具探测写成 `command -v` 在**解析阶段**执行 | 每个目标都探测一次（慢） | 用 `$(shell command -v x)` 缓存成变量（同事的 Makefile 已这么写） |
| 4 | 用 make 的**时间戳**当"内容变没变" | 判断失真 | 用 SHA / 哈希 |
| 5 | 生成物没加 `.DELETE_ON_ERROR` | 半个 YAML 被提交 | 加它 |
| 6 | `make sync` 不给 REV | 同步了没审批的版本 | 强制要求 REV（同 `7.1`） |
| 7 | `make sync` 用了 `--prune=true` | 误删资源 | 默认 false，prune 单独审批 |
| 8 | 在 Makefile 里写凭据 | 泄漏进 Git | Secret 注入 |
| 9 | `make -j` 下多个目标同时写 stdout | 输出交错、看不出谁失败 | 并行时各写各的文件；或 `.NOTPARALLEL` |
| 10 | 用 `%` 模式规则但**文件真的存在** | 规则被跳过（同事的 using-make.md `3.7 已记） | 文件型目标用显式规则或 `.PHONY` |
| 11 | `make` 的默认目标是 help 之前，误把部署目标放在第一个 | 敲 `make` 就部署了 | `.DEFAULT_GOAL := help` + 有副作用的目标都 `.PHONY` |
| 12 | 把 `make ci` 当门禁但**没人跑** | 门禁形同虚设 | 必须有服务端执行点（CR Check / 外部 CI）+ ruleset 引用 check |

---

## 关联文档

- 上一级：[`18 总体框架`](./18-framework-github-first-gitops.md)
- Actions 禁用后的执行点：[`19 替代方案矩阵`](./19-no-actions-alternative-matrix.md)
- 同步开关（sync 的前置条件）：[`21 同步窗口与自动同步`](./21-sync-windows-and-auto-sync.md)
- 集群内 Hook：[`22 Resource Hooks 与同步阶段`](./22-resource-hooks-and-sync-phases.md)
- CD Driver（make 版 sync 的"正规军"对照）：[`23 CD Driver`](./23-cd-driver-and-argocd-api-sync.md)
- 本仓库的检查工具箱：[`../examples/README.md`](../examples/README.md) · [`../examples/gitops-layout/README.md`](../examples/gitops-layout/README.md)
- Make 原理笔记（同事写的，很好）：[`../../../../go/daydayup/using-make.md`](../../../../go/daydayup/using-make.md)
- Make 范例（同风格）：[`../../../../go/daydayup/Makefile`](../../../../go/daydayup/Makefile)
