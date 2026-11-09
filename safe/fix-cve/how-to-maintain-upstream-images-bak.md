# 上游镜像持续维护方案 —— 从 Git 分支控制面到 GAR 制品面的闭环

> 编写日期：2026-11-09
> 关联文档：
> - [how-to-autofix-cve.md](./how-to-autofix-cve.md) —— 整体闭环、角色边界、状态机、验证契约（**本文的框架来源**）
> - [how-to-use-dependabot.md](./how-to-use-dependabot.md) —— 依赖层自动化、GAR OIDC、PR 门禁
> - [how-to-fix-cve-with-base-image-constraints.md](./how-to-fix-cve-with-base-image-constraints.md) —— base 受限时的准入与 Dockerfile 精简
> - [how-to-fix-dex-base-image.md](./how-to-fix-dex-base-image.md) —— 单个 case 的 Runbook 样例
> - [cve-cwe.md](./cve-cwe.md) —— CVE/CWE 台账与根因模型
>
> **本文定位**：解决一个具体的设计问题——
> 我们要在内部维护一批「从开源社区获取、部署到 GKE」的镜像（Istio 四个组件、Argo CD 等），
> 这些镜像有 CVE 和 violation 需要定期修复，
> 但**源码不在我们手里、GitHub 上不能跑 CI、制品要进 GAR**。
> 本文给出这个场景下的完整实现方案：Git 分支怎么组织、资产怎么定义、
> 修复策略怎么选、不同语言的补丁怎么写、CI 怎么编排、验证怎么判。

---

## 0. 结论摘要

| 问题 | 结论 |
|---|---|
| **Git 分支里存什么** | 只存**镜像定义与构建配方**：来源（upstream repo + commit）、版本锁定（`istio.deps` / lockfile / base digest）、Dockerfile、状态与生命周期、扫描与豁免记录、证据链。**不存 OCI 二进制**（那是 GAR 的职责） |
| **控制面 vs 制品面** | Git 分支 = **控制面**（意图 + 配方 + 状态机）；GAR = **制品面**（镜像 + SBOM + 扫描报告）。两者用 **digest** 绑定，永不用可变 tag 绑定 |
| **能不能只靠 Dependabot** | **不能**。Dependabot 的 `docker` ecosystem 只做 version updates，**不支持 CVE security updates**，也不支持 `ARG BASE_IMAGE` 间接引用，更不支持 OS 包级 CVE。Go/Maven/Gradle 可以用 security updates，但结果只是 PR，**后面还要走构建 → 推送 → 扫描 → 差分** |
| **Istio 修复的真实成本在哪** | 在 **Envoy（Bazel）** 和 **ztunnel（Rust/Cargo）** 的重新编译，不在镜像层。Istio 官方 `Dockerfile.*` 只是**包装层**：拷贝已构建好的二进制。分两级：**L1 重打包**（复用 GCS 预编译产物，改 OS/base 层，便宜）与 **L2 重编译**（改源码依赖，Envoy 极贵） |
| **修复策略优先级** | 升级上游补丁版本 → 依赖升级（Dependabot/Renovate） → 源码补丁（fork 固定版本） → 构建覆盖（ldflags/vendor） → 换 base → 重建 Dockerfile → 派生补丁镜像。**越靠前越便宜、越不容易产生长期分叉** |
| **GitHub 不能跑 CI 怎么办** | 完全不依赖 GitHub CI。用内部 CI（本文用占位名 **`Powerline`**）拉起自建 runner，构建 → 推 GAR → 触发 Artifact Analysis 扫描 → 取报告 → 差分 → 人工审批 → 合并回分支。**GitHub 只做 PR 评审和分支保护**，不做构建 |
| **"待修复" 怎么表达** | 每个资产有 `lifecycle_state`：`TRACKED` / `VULNERABLE` / `FIXING` / `VERIFYING` / `BLOCKED` / `VERIFIED` / `EOL` / `RETIRED`。分支里的 `state.yaml` 就是唯一真相源，CI/部署从中读取 |
| **什么时候能部署** | 只有 `VERIFIED` 状态 + 通过 D1–D4 差分验证 + 人工审批的 digest，才允许进 GKE。Binary Authorization 按 digest 做准入 |
| **本方案最核心的一条** | **一次构建、一次推送、一次扫描**（Verify-then-Promote）。CI 推送的那个 digest 必须就是被扫描、被差分、被部署的那个 digest。不允许"扫一个、推另一个" |

---

## 1. 问题定义与范围

### 1.1 我们实际在维护什么

首批资产（Istio 四个组件 + Argo CD），以用户给出的内部镜像名为准：

```
soloio-img/ztunnel:1.30.3-distroless
soloio-img/pilot:1.30.3-distroless
soloio-img/install-cni:1.30.3-distroless
soloio-img/proxyv2:1.30.3-distroless
```

**已实测的对应关系（2026-11-09）**：这四个 `1.30.3-distroless` tag 在 **Docker Hub `istio/*`** 与 **`registry.istio.io/release/*`** 上**逐字一致的 manifest digest**：

| 组件 | `1.30.3-distroless` digest (sha256) | `1.30.8-distroless` digest (sha256) |
|---|---|---|
| `pilot` | `eba09c5000a8a4b7ea114caae5ff42cfa3a782e60e1fb73e37db55da71cc151c` | `9d332c4b24b25b3da2416c8e3506cb17779d67633e811fa4aeca70e5915f9927` |
| `proxyv2` | `2f59eaf91e15213e50d91c7951c81073695872d6b17b82e146773695f24b1c6e` | `ff17cf1cb0a9659eac744b7398b17797996b723e1962d94d3b6a85f670e36bf8` |
| `ztunnel` | `de46b51da2de6c013f867590c4ad7a5849681dc2faa74e8584e699a877cd932a` | `79de3e4a3ab2fa495508987de7713027b2d8e85100bde0a0b42f859d810e0421` |
| `install-cni` | `ff7964e88c98261d30814c9a903ae05335bbca56bb0f56a254b343a453b02e5a` | `8b25c66a2930cf2f991f99f504586ca64ebc36857137f10de3541590fe1822bc` |

> ⚠️ **待确认**：`soloio-img` 这个 Docker Hub 组织在**公共 API 上返回 `count: 0`**，匿名 registry 返回 `401 UNAUTHORIZED`。
> 这意味着它要么是**企业内部/私有组织**，要么是**已迁移或已废弃**的名字。
> 公共 `soloio` 组织下的 `pilot`/`proxyv2`/`ztunnel`/`proxy` 仓库虽然存在，但**均无 `1.30.x` tag**。
> **在拿到内部 registry 的真实地址和 digest 之前，上表只是"官方镜像侧的参照"，不能断言内部镜像内容与之相同。**
> 这件事必须在 Phase 0 用一次内部 `docker pull` + `sha256sum` 核实（见 §14 待确认清单第 1 条）。

### 1.2 三层事实（不要混为一谈）

| 层 | 内容 | 存放位置 | 谁负责 |
|---|---|---|---|
| **上游源码层** | `istio/istio`、`istio/proxy`、`istio/ztunnel`、`argoproj/argo-cd` 的代码 | 上游 GitHub / 我们 fork | 上游维护者；我们 fork 后自己维护补丁 |
| **控制面层** | 镜像定义、版本锁定、配方、状态、豁免、证据 | **企业内部 Git 分支** | 我们 |
| **制品面层** | OCI 镜像、SBOM、扫描报告、签名 | **GAR（Artifact Registry）** | 我们 + Google Artifact Analysis |

**关键点**：用户提出的"把安装包下载下来放在 Git Branch 里"——**只对控制面成立**。
OCI layer（gzip tar，几十到几百 MB）放 Git 是错误做法：仓库膨胀、diff 无意义、二进制审计靠不住、Git LFS 又引入新的一套信任问题。
Git 里放的是**配方**，配方产出的二进制放 GAR。

### 1.3 六条不可动摇的原则

1. **单一真相源**：资产状态只有一份，在分支里的 `state.yaml`。GAR 上的标签不表达"状态"。
2. **digest 绑定一切**：资产身份 = `GAR_REPO@digest`。tag 只用于人类阅读和"指针晋级"。
3. **一次构建一次扫描**：CI 产出的 digest 就是被扫描和被部署的 digest（Verify-then-Promote）。
4. **fail-closed**：构建失败、扫描器降级、覆盖未知、扫描瞬态错误 → 全部判失败，不允许"看起来干净就放行"。
5. **不产生不可控分叉**：fork 只作为**临时手段**，每个 fork 资产必须登记 `fork_of` / `fork_reason` / `expiry` / `upstream_target`，到期自动回到"跟上游"。
6. **机器判据唯一**：扫描器输出是修复是否成功的**唯一机器判据**。Agent 负责判断和规划，人工负责最终裁决，但不能替代扫描器。

---

## 2. 总体架构

### 2.1 三个存储位置

```
┌─────────────────────────────────────────────────────────────────┐
│  控制面：internal-git / branch: images/production               │
│                                                                 │
│   assets/                                                        │
│     istio-pilot.yaml        ← 资产定义（唯一真相）               │
│     istio-proxyv2.yaml                                             │
│     istio-ztunnel.yaml                                              │
│     istio-install-cni.yaml                                         │
│     argocd.yaml                                                   │
│   recipes/            ← 我们的 Dockerfile 覆盖层                  │
│     istio/pilot/Dockerfile                                          │
│     istio/ztunnel/Dockerfile                                        │
│     argocd/Dockerfile                                              │
│   lock/               ← 精确锁定（istio.deps / lockfile / digests） │
│     istio-1.30.8.istio.deps                                         │
│     argocd-v3.6.1.go.sum                                             │
│   state.yaml          ← 资产状态机 + finding 台账 + 豁免           │
│   evidence/           ← 扫描报告、差分结果、审批记录（脱敏后）      │
│   ci/                 ← Powerline 流水线定义                        │
└───────────────────────────────┬─────────────────────────────────┘
                                │ digest 引用
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  制品面：GAR  europe-west2-docker.pkg.dev/[PROJECT]/containers   │
│     upstream-mirror/   (Remote Repository, 缓存上游)                 │
│     internal/          (Standard Repository, 我们自己构建的)        │
│                                                                 │
│     internal/istio/pilot  @sha256:...  (tag: 1.30.8-istio.3)       │
│         └─ SBOM (Artifact Analysis)                                │
│         └─ Vulnerability report                                     │
└───────────────────────────────┬─────────────────────────────────┘
                                │ 按 digest 部署
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  运行面：GKE                                                        │
│     Deployment/StatefulSet 里写 image: repo@sha256:...             │
│     Binary Authorization 按 digest 准入                             │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 一次修复的完整数据流（10 步）

```
 ① 发现       Artifact Analysis 扫描 / 上游安全公告 / 定期巡检
       ↓
 ② 登记       写 state.yaml：asset + finding（CVE ID 为主键）
       ↓
 ③ 定级       判 T1..T5（OS EOL / OS 包 / 语言依赖 / runtime / 应用代码）
       ↓
 ④ 选策略     升级上游？依赖升级？源码补丁？换 base？重打包？
       ↓
 ⑤ 出配方     写/改 Dockerfile + lock 文件，产出 candidate 定义
       ↓
 ⑥ 构建       Powerline 跑 buildx → 推 GAR → 拿到 digest
       ↓
 ⑦ 扫描       对该 digest 触发 Artifact Analysis，取报告
       ↓
 ⑧ 差分       同扫描器、同 DB 批次：baseline vs candidate → D1..D4
       ↓
 ⑨ 审批       人工评审 PR（Agent 生成的补丁 + 证据链）
       ↓
 ⑩ 晋级       合并到 images/production → 更新 state → GKE 按 digest 部署
```

这与 [how-to-autofix-cve.md](./how-to-autofix-cve.md) 的九阶段状态机
（`DISCOVER → TRIAGE → PLAN → PATCH → BUILD → PUSH → SCAN → DIFF → VERIFY`）一致，
差别只在于「①发现」的上游来源是**我们自己维护的资产清单**，而不是"某个集群里恰好跑着的镜像"。

### 2.3 状态机

#### 2.3.1 修复流程状态（单个 finding）

沿用既有契约，不改：

```
DISCOVER → TRIAGE → PLAN → PATCH → BUILD → PUSH → SCAN → DIFF → VERIFY
```

- 任何阶段失败 → 停在当前阶段，资产 `lifecycle_state` 置 `BLOCKED`，**不推进**
- `BUILD`/`PUSH`/`SCAN` 任一失败 = fail-closed
- 只有 `VERIFY` 全部通过（D1–D4）才允许进入人工审批

#### 2.3.2 资产生命周期状态（新增，`lifecycle_state`）

| 状态 | 含义 | 进入条件 | 允许部署 |
|---|---|---|---|
| `TRACKED` | 已纳管，无未修 finding | 登记完成 + 首次扫描通过 | ✅ |
| `VULNERABLE` | 存在未修 finding | TRIAGE 完成并定级 | ❌ |
| `FIXING` | 正在出补丁/构建 | PLAN 通过 | ❌ |
| `VERIFYING` | 已推送，等待扫描与差分 | PUSH 成功 | ❌ |
| `BLOCKED` | 修复受阻（需人工决策/需上游） | 任意阶段失败且需介入 | ❌ |
| `VERIFIED` | 修复通过 D1–D4，已审批 | VERIFY 通过 + 人工审批 | ✅ |
| `EOL` | 上游版本已 EOL，必须升级 | 版本生命周期检查命中 | ❌ |
| `RETIRED` | 资产下线 | 人工决策 | ❌ |

**状态流转图**：

```
   TRACKED ──finding──▶ VULNERABLE ──plan──▶ FIXING ──build ok──▶ VERIFYING
      ▲                    │                     │                      │
      │                    │                     └──build fail──▶ BLOCKED
      │                    │                                            │
      │                    └──判定为上游问题/需 fork──▶ BLOCKED          │
      │                                                           scan+diff
      │                                                             ok│  fail
      │                                                              ▼    ▼
      └────────────────────── 合并/晋级 ◀── VERIFIED ◀── 人工审批      │
                              │                                        │
                              └──新 finding──▶ VULNERABLE ◀───────────┘

   EOL（版本生命周期到期强制进入）──升级成功──▶ TRACKED
   RETIRED（人工终止）
```

---

## 3. Git 分支策略

### 3.1 分支布局

不要把所有东西放一个分支，也不要为每个镜像开一个分支。**按"变更性质"分层**：

| 分支 | 内容 | 保护 | PR 要求 |
|---|---|---|---|
| `images/production` | **已批准部署**的资产定义 + 配方 + 状态 | 禁止直推，必须走 PR + 审批 | 需 D1–D4 证据 + 人工审批 |
| `images/staging` | 候选修复（candidate）定义 | 禁止直推 | 需 CI 跑通；可无人工审批（但不得部署） |
| `images/fork/<asset>-<version>` | 长期 fork 的源码补丁集（真正要改代码时） | 禁止直推 | 需评审；必须带 `expiry` |

**关键决策：为什么不是"一个镜像一个分支"？**

- 镜像多（Istio 4 个 + Argo + 后续更多），分支会爆炸，跨镜像的统一升级（Istio 四个组件必须版本一致）无法表达。
- Istio 四个组件**必须同版本同 digest 集合**，它们之间有严格的兼容矩阵（pilot ↔ proxyv2 ↔ ztunnel ↔ install-cni）。
- 单一 `images/production` 分支天然表达"这批镜像是一个发布单元"。

### 3.2 目录结构

```
images/production/
├── README.md                       # 这个分支是什么、怎么用、边界
├── assets/                         # 资产定义（唯一真相源）
│   ├── istio-pilot.yaml
│   ├── istio-proxyv2.yaml
│   ├── istio-ztunnel.yaml
│   ├── istio-install-cni.yaml
│   └── argocd.yaml
├── recipes/                        # 构建配方（我们改写/覆盖上游 Dockerfile 的部分）
│   ├── istio/
│   │   ├── pilot/Dockerfile
│   │   ├── proxyv2/Dockerfile
│   │   ├── ztunnel/Dockerfile
│   │   └── install-cni/Dockerfile
│   └── argocd/Dockerfile
├── lock/                           # 精确锁定
│   ├── istio/
│   │   ├── istio.deps              # proxy / ztunnel 的上游 commit
│   │   └── base-versions.yaml      # BASE_VERSION / base digest
│   └── argocd/
│       ├── go.sum
│       └── pnpm-lock.yaml
├── state.yaml                      # 资产状态 + finding 台账 + 豁免
├── evidence/                       # 证据（扫描/差分/审批，脱敏）
│   └── <asset>/<date>-<scan-id>.json
└── ci/
    ├── powerline-istio.yaml        # CI 流水线定义（占位平台名）
    ├── powerline-argocd.yaml
    └── common/
        ├── diff-gate.sh            # D1..D4 差分判定
        └── promote.sh              # 晋级到 production
```

### 3.3 权限模型

| 角色 | 读 | 写 `recipes/` `lock/` | 写 `state.yaml` | 合并 `images/production` | 推 GAR |
|---|---|---|---|---|---|
| **平台工程（我们）** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **上游同步机器人** | ✅ | ❌ | ✅（仅状态字段） | ❌ | ❌ |
| **CI runner** | ✅ | ❌ | ❌ | ❌ | ✅（仅 `internal/`） |
| **应用团队** | ✅ | ❌ | ❌（仅申请豁免） | ❌ | ❌ |
| **审批人（安全/架构）** | ✅ | ❌ | ✅（仅豁免/审批结论） | ✅ | ❌ |

**强制点**：
- CI runner 的 GAR 凭据**只能推 `internal/`**，不能删、不能改 `upstream-mirror/`。
- `upstream-mirror/` 的写权限只在同步机器人手里。
- 审批人**不能**同时是补丁作者（职责分离，对应既有文档的 Human 权限边界）。

---

## 4. 来源锁定（provenance pinning）

这是整个方案的地基。**没有精确锁定，"重建"就是"重建了另一个东西"**。

### 4.1 四层锁定

| 层 | 锁定对象 | 载体 | Istio 实例 |
|---|---|---|---|
| **L1 应用源码** | upstream repo + commit SHA | `lock/istio/istio.deps` | `istio/istio` @ `1.30.8` tag → commit |
| **L2 子项目源码** | proxy/ztunnel 各自的 commit SHA | `istio.deps` 内的 `PROXY_REPO_SHA` / `ZTUNNEL_REPO_SHA` | `1.30.8`: proxy `16f21841fa6b55f5b8c982593c4a4adc87392491`；ztunnel `e06c445c6aa280ee0ce8c57062ce18686fa4bf0e` |
| **L3 基础镜像** | base 仓库 + tag + digest | `lock/istio/base-versions.yaml` | `BASE_VERSION=1.30-2026-11-04T19-02-08`；`release/iptables` / `release/distroless` |
| **L4 构建工具链** | Go/Rust/Node 版本 + 工具版本 | CI 镜像 digest + `tool-versions` | Go `1.27.3`、Rust `1.90`+edition 2024、Node `24.17.0`+Corepack `0.34.6` |

**Istio 各版本的 `istio.deps` 实测值**：

| Istio 版本 | proxy SHA | ztunnel SHA |
|---|---|---|
| `1.30.3` | `81864a1cd5099d2f9e1289bfc604f4b200b2b27c` | `a45c62f8d09a78eaa5228afcea6c7d3a06269b2c` |
| `1.30.4` | `ce177c56fe75661f16b654e2f164d4ab02058222` | `75e02620710b18c99e89351503f35cba428fc5fd` |
| `1.30.8` | `16f21841fa6b55f5b8c982593c4a4adc87392491` | `e06c445c6aa280ee0ce8c57062ce18686fa4bf0e` |

**`BASE_VERSION` 实测值**：

| 源 | `BASE_VERSION` |
|---|---|
| `1.30.3` | `master-2026-04-09T19-02-13` |
| `1.30.8` | `1.30-2026-11-04T19-02-08` |
| `release-1.30` HEAD | `1.30-2026-11-05T19-01-59` |

**`release-1.30` 分支默认 `TAG ?= $(shell git rev-parse --verify HEAD)`**，
`HUB ?= istio` —— 意味着**上游的构建默认 tag 就是 commit SHA**。这是个好设计，
我们内部也应当沿用（见 §11.1 的 `tag` 字段规范）。

### 4.2 Istio 镜像的实际配方（已读取原文）

**`tools/docker.yaml` 的映射关系**（这是上游的构建调度表）：

| target | Dockerfile |
|---|---|
| `proxyv2` | `pilot/docker/Dockerfile.proxyv2` |
| `pilot` | `pilot/docker/Dockerfile.pilot` |
| `install-cni` | `cni/deployments/kubernetes/Dockerfile.install-cni` |
| `ztunnel` | `pilot/docker/Dockerfile.ztunnel` |

**`Dockerfile.pilot` 的真实结构**（实测原文）：

```dockerfile
ARG BASE_DISTRIBUTION=debug
ARG BASE_VERSION=latest
ARG ISTIO_BASE_REGISTRY=registry.istio.io/release

FROM ${ISTIO_BASE_REGISTRY}/base:${BASE_VERSION} AS debug
FROM ${ISTIO_BASE_REGISTRY}/distroless:${BASE_VERSION} AS distroless
FROM ${BASE_DISTRIBUTION:-debug}

ARG TARGETARCH
COPY ${TARGETARCH:-amd64}/pilot-discovery /usr/local/bin/pilot-discovery
USER 1337:1337
ENTRYPOINT ["/usr/local/bin/pilot-discovery"]
```

**`Dockerfile.proxyv2` 的真实结构**（实测原文）：

```dockerfile
ARG BASE_DISTRIBUTION=debug
ARG BASE_VERSION=latest
ARG ISTIO_BASE_REGISTRY=registry.istio.io/release

FROM ${ISTIO_BASE_REGISTRY}/base:${BASE_VERSION} AS debug
FROM ${ISTIO_BASE_REGISTRY}/iptables:${BASE_VERSION} AS distroless
FROM ${BASE_DISTRIBUTION:-debug}

WORKDIR /
ARG proxy_version
ARG SIDECAR=envoy
COPY envoy_bootstrap.json /var/lib/istio/envoy/envoy_bootstrap_tmpl.json
ARG TARGETARCH
COPY ${TARGETARCH:-amd64}/${SIDECAR} /usr/local/bin/${SIDECAR}
ENV ISTIO_META_ISTIO_PROXY_SHA=$proxy_version
ARG TARGETARCH
COPY ${TARGETARCH:-amd64}/pilot-agent /usr/local/bin/pilot-agent
ENTRYPOINT ["/usr/local/bin/pilot-agent"]
```

**由此得出四个极其重要的事实**：

1. **`pilot` 用 `release/distroless`；`proxyv2`/`ztunnel`/`install-cni` 用 `release/iptables`。**
   → 四个组件**不共用同一个 base**，base 层 CVE 要分别修。
2. **`distroless` 分支的 base 不是 `gcr.io/distroless/*`**，而是 Istio 自己构建发布的
   `registry.istio.io/release/distroless`（`Dockerfile.distroless` 的真实基础源是**固定 digest 的 Chainguard static**）。
   → 想换 base，得先走**自建 base 的准入流程**，不是简单改一行 `FROM`。
3. **`iptables` base 是 Wolfi/melange 配方**（`docker/iptables.yaml`），包集合：
   `ca-certificates-bundle`、`glibc`、`iptables`、`ip6tables`、`libnetfilter_conntrack`、`libnfnetlink`、`libmnl`、`libgcc`、`nftables-slim`，run-as `65532`。
   → **OS 包 CVE 应该修 melange 配方（`docker/iptables.yaml`），而不是在 Dockerfile 里 `apk upgrade`**。
4. **`Dockerfile.*` 只是"包装层"**：拷贝的是**已经编译好的二进制**（`pilot-discovery` / `envoy` / `pilot-agent` / `ztunnel`）。
   → 想改应用层 CVE（Envoy、ztunnel 的 Rust 依赖），**必须回到上游源码重新编译**，Dockerfile 层改不了。

### 4.3 Istio 的两级构建模型（本方案的成本分界线）

```
                    ┌─────────────────────────────────────────┐
   L1 重打包        │  GCS 预编译产物（按 SHA 固定）             │
   （便宜）         │  istio-build/proxy/envoy-alpha-<SHA>.tar.gz │
                    │  istio-build/ztunnel/ztunnel-<SHA>-<arch>  │
                    └──────────────┬──────────────────────────┘
                                   │ COPY
                    ┌──────────────▼──────────────────────────┐
                    │  Dockerfile.proxyv2 / .ztunnel / .pilot    │
                    │  （我们可以在这一层覆盖）                    │
                    └──────────────┬──────────────────────────┘
                                   │ buildx
                    ┌──────────────▼──────────────────────────┐
                    │  GAR internal/istio/*  @digest             │
                    └─────────────────────────────────────────┘

   L2 重编译        │  istio/proxy（Bazel/Envoy）—— 极贵，数小时起  │
   （昂贵）         │  istio/ztunnel（Cargo/Rust）—— 中等          │
                    │  istio/istio（Go）—— 中等                  │
                    └─────────────────────────────────────────┘
```

**实测确认的预编译 artifact URL 模板**（已验证 HTTP 200）：

```
https://storage.googleapis.com/istio-build/proxy/envoy-alpha-<PROXY_REPO_SHA>.tar.gz
https://storage.googleapis.com/istio-build/ztunnel/ztunnel-<ZTUNNEL_REPO_SHA>-<arch>
```

**决策规则（写进资产定义的 `strategy_policy`）**：

| finding 类型 | 默认层级 | 理由 |
|---|---|---|
| OS 包 CVE（T2）| **L1** | 改 melange 配方或换 base 重建，不动二进制 |
| base OS EOL（T1）| **L1** | 同上 |
| Go 应用依赖 CVE（T3，pilot/argocd）| **L2（Go）** | Go 编译相对便宜 |
| Rust 依赖 CVE（T3，ztunnel）| **L2（Cargo）** | 中等成本 |
| Envoy CVE（T3/T4，proxyv2）| **优先升 Istio 版本**；L2（Bazel）成本极高 | Envoy Bazel 构建时间和资源开销巨大，**自建 Envoy 不是默认选项** |
| 应用代码缺陷（T5，CWE）| 不进自动流水线 | 只能生成候选补丁，**强制人工合并** |

> **重要判断**：Envoy 的 CVE 在实践中**绝大多数能靠升 Istio 补丁版解决**（Istio 会更新 `istio.deps` 指向已修的 proxy SHA）。
> 所以我们的核心策略应该是：**保持跟上游，把"自建 Envoy"留作最后手段**。

### 4.4 Argo CD 的锁定点（实测）

**`argoproj/argo-cd@v3.6.1` 的 Dockerfile 构建链**：

| 阶段 | 内容 | 锁定点 |
|---|---|---|
| base | `ubuntu:26.04@sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b` | digest |
| builder | `golang:1.27.3@sha256:957861185dbf29d93668ace41e011d091c6e779953d47f0316ef2cc58e28fe2b` | digest |
| UI | `node:24.17.0@sha256:032e78d7e54e352129831743737e3a83171d9cc5b5896f411649c597ce0b11ea` + Corepack `0.34.6` | digest + 工具版本 |
| UI 包管理 | **pnpm workspace**，`packageManager: pnpm@12.3.4`，`pnpm install --frozen-lockfile` | `pnpm-lock.yaml` + `pnpm-workspace.yaml` |
| Go 构建 | `make argocd-all` | `go.mod` + `go.sum` |

**Argo CD `v3.2.0`（历史样例）**：Go `1.25.0`、Node `23.0.0` + **Yarn**、`make argocd-all`。
→ 从 v3.2 到 v3.6.1 **包管理器从 Yarn 换成了 pnpm**。这直接决定 Node 侧修复配方（§7.4）。

**UI 构建的一个重要细节**：UI 在 `$BUILDPLATFORM` 上构建，然后**把同一份 `dist` 复制到各目标架构**。
→ 避免混合架构集群下资源文件 hash 分叉。**我们的重建必须保留这个特性**，否则多架构镜像的 UI 资源不一致。

---

## 5. 发现机制

### 5.1 三个发现来源

| 来源 | 触发时机 | 覆盖范围 | 工具 |
|---|---|---|---|
| **A. 制品扫描**（主）| 纳管时一次 + 每次推送 + 定期全量巡检 | 我们 GAR 里的所有 digest | `gcloud artifacts docker images scan` |
| **B. 上游公告**（补充）| 订阅 Istio / Argo CD / OS 发行版安全公告 | 未部署但将来会用的版本 | RSS/邮件 → Agent 解析 |
| **C. 内部 violation 规则** | 定时（如每日）| 政策规则（如"必须有 SBOM"、"禁止 root"）| 内部 violation 扫描器（**待确认**） |

**A 的命令契约**（已核对 `gcloud` help）：

```bash
# 同步扫描（阻塞直到出报告）
gcloud artifacts docker images scan \
  europe-west2-docker.pkg.dev/[PROJECT]/containers/internal/istio/pilot@sha256:<DIGEST> \
  --remote --location=europe

# 异步扫描（CI 里推荐）
gcloud artifacts docker images scan \
  europe-west2-docker.pkg.dev/[PROJECT]/containers/internal/istio/pilot@sha256:<DIGEST> \
  --remote --location=europe --async
# → 返回 operation name
gcloud artifacts docker images get-operation <OPERATION_NAME>

# 取漏洞清单
gcloud artifacts docker images list-vulnerabilities \
  projects/[PROJECT]/locations/europe/scans/<SCAN_ID>

# 取 SBOM
gcloud artifacts sbom export --uri=<IMAGE@DIGEST> --location=europe
gcloud artifacts sbom list --uri=<IMAGE@DIGEST> --location=europe
gcloud artifacts sbom load --uri=<IMAGE@DIGEST> --location=europe
```

> ⚠️ **注意 `--location` 是区域级**：`europe` / `asia` / `us`。GAR 仓库是区域化的
> （`europe-west2`），扫描要在对应区域发起。

### 5.2 巡检节奏

| 频率 | 动作 | 耗时量级 |
|---|---|---|
| 每次推送到 `internal/` | 自动扫描 + 差分 | 分钟级（异步）|
| 每日 | 全量扫描 `internal/` 所有 digest，比对上次报告 | 小时级（后台）|
| 每周 | 扫描 `upstream-mirror/` 里的最新上游版本，看上游修了什么 | 小时级 |
| 每月 | 上游公告解析（Istio/Argo/CVE 源）+ 版本生命周期检查 | 分钟级 |

### 5.3 台账（finding 记录）

**CVE ID 是台账主键**（见 [cve-cwe.md](./cve-cwe.md)）：
- 同一 CVE 影响多个资产 → 一条 finding 记录，多条 asset 关联
- CWE 用于**根因分类**（决定修复策略走 T1..T5 哪条路），不用于去重

**记录字段（最小集）**：

```yaml
- id: CVE-2026-111943
  cwe: CWE-XXX                # 根因语言
  type: T3                    # T1 OS EOL / T2 OS 包 / T3 语言依赖 / T4 runtime / T5 应用代码
  affected_assets:
    - istio-proxyv2
    - istio-pilot
  detected_by: artifact-analysis
  detected_at: 2026-11-09
  upstream_advisory: ISTIO-SECURITY-2026-008
  fixed_by:
    upstream_version: 1.30.8
    internal_digest: null
  status: OPEN                # OPEN / IN_PROGRESS / FIXED / ACCEPTED
  ignore:
    enabled: false
    # 忽略必须精确到 package selector，不能整镜像忽略
    package_selector: null
    reason: null
    fix_state: null           # FIXED / NOT_AFFECTED / WILL_NOT_FIX / COMPENSATING_CONTROL
    expires_at: null          # 到期自动回到 OPEN
```

> **忽略项的四要素**（沿用既有契约）：精确 package selector、理由、`fix-state`、到期时间。
> 缺任何一项 → 视为无效忽略，fail-closed。

---

## 6. 修复策略决策树

### 6.1 七种策略对比

| # | 策略 | 成本 | 长期分叉风险 | 适用 finding | 主要风险 |
|---|---|---|---|---|---|
| **S1** | **升级上游补丁版本** | 最低 | 无 | 全部（如果上游已修）| 引入上游新变更，需回归测试 |
| **S2** | **依赖升级**（Dependabot/Renovate/OSV）| 低 | 低 | T3 | 只改依赖版本，可能 API 破坏 |
| **S3** | **源码补丁**（fork 固定版本）| 中~高 | **高** | T3/T4/T5 | 分叉漂移，需长期维护 |
| **S4** | **构建覆盖**（ldflags / vendor / build arg）| 中 | 中 | T3/T4 | 可能与源码不一致 |
| **S5** | **换基础镜像** | 中 | 低 | T1/T2 | base 准入、兼容性、功能缺失 |
| **S6** | **重建 Dockerfile**（同源码同 base，改打包）| 中 | 低 | T1/T2/T4 | 需要能重建；依赖可获得 |
| **S7** | **派生补丁镜像**（FROM 上游镜像 + 覆盖层）| 低 | 中 | T2 | 层叠膨胀；漏洞可能来自上游层 |
| **S8** | **不修**（豁免/接受风险）| 零 | 无 | 全部 | **必须有豁免流程和到期时间** |

### 6.2 决策顺序（严格按序，先匹配先生效）

```
① 上游是否已有修复版本？
   ├─ 是 → S1（升级上游）。【默认答案】
   └─ 否 ↓
② 是否只是依赖版本问题，且 lockfile 可自动更新？
   ├─ 是 → S2（Dependabot/OSV/Renovate）
   └─ 否 ↓
③ 是否能在不改源码的前提下解决？
   ├─ 是（build override / vendor）→ S4
   └─ 否 ↓
④ 是否是 base/OS 层问题？
   ├─ 是 → S5 或 S6（换 base 需走准入流程）
   └─ 否 ↓
⑤ 是否是应用代码缺陷（T5/CWE）？
   ├─ 是 → **不进自动流水线**，只生成候选补丁，人工评审合并
   └─ 否 ↓
⑥ 是否能 fork 固定版本？
   ├─ 是 → S3（必须登记 fork 元信息 + expiry）
   └─ 否 → S8（走豁免流程，带到期时间）
```

**"上游是否已有修复版本"的查询方法**（不要靠猜）：
- Istio：查官方安全公告（`ISTIO-SECURITY-YYYY-NNN`）的 affected ranges
- Argo CD：查 GitHub Advisory Database / release notes
- OS 包：查发行版安全公告 + 上游 melange/wolfi 配方版本

### 6.3 具体案例：Istio `1.30.3` 的现状（实测）

**已捕获的 Istio 安全公告（2026-11-09）**：

| 公告 | 日期 | CVSS | 受影响范围 | `1.30.3` | `1.30.8` |
|---|---|---|---|---|---|
| `ISTIO-SECURITY-2026-006` | 2026-08-27 | 7.7 | `1.30.0 – 1.30.3` | **受影响** | 不在范围 |
| `ISTIO-SECURITY-2026-007` | 2026-10-15 | 9.2 | `1.30.0 – 1.30.5` | **受影响** | 不在范围 |
| `ISTIO-SECURITY-2026-008` | 2026-10-21 | — (`CVE-2026-111943`) | `1.30.0 – 1.30.6` | **受影响** | 不在范围 |
| `ISTIO-SECURITY-2026-009` | 2026-11-06 | 8.2 | `1.30.0 – 1.30.7` | **受影响** | 不在范围 |

**结论**：`1.30.3` 同时命中 **4 份公告**。`1.30.8` 不在任何一份的 affected range 内。

> ⚠️ **不能写成"`1.30.8` 已 clean"**。公告只说明 `1.30.8` **修复了这些特定 CVE**，
> 是否还有其他 violation/CVE **必须由我们自己的扫描器在同一个 DB 批次下判定**。
> 这正是 D1/D2 差分契约存在的意义。

**推荐动作（对应策略 S1）**：

```bash
# 1. 在 lock/ 更新到 1.30.8 的 istio.deps 与 base-versions
#    PROXY_REPO_SHA   = 16f21841fa6b55f5b8c982593c4a4adc87392491
#    ZTUNNEL_REPO_SHA = e06c445c6aa280ee0ce8c57062ce18686fa4bf0e
#    BASE_VERSION     = 1.30-2026-11-04T19-02-08
#
# 2. 用上游 tools/docker 编排构建（L1 重打包）
#    ./tools/docker --save        # 本地产物
#    ./tools/docker --push        # 推 registry
#    HUB=... TAG=... ./tools/docker   # 覆盖 hub/tag
#
# 3. 推 GAR 后按 §5.1 扫描，差分验证 D1-D4
```

---

## 7. 按语言的修复配方

### 7.1 通用流程

```
① 定位 finding 的精确坐标
   （OS 包？语言依赖？runtime？应用代码？）
   ↓
② 确认它落在哪一层（源码层 / 依赖层 / base 层 / 打包层）
   ↓
③ 在**对应层**出补丁，不要在错误的层修
   ↓
④ 本地最小复现：构建出候选镜像
   ↓
⑤ 扫描候选 digest，与 baseline 做同批次差分
   ↓
⑥ D1..D4 全过 → 人工审批 → 合并
```

**核心原则：修在正确的层。**
OS 包 CVE 去改 Go 依赖是浪费；Envoy 的 C++ 漏洞去改 `FROM` 是错位。

### 7.2 Go（`pilot-discovery` / `argocd` server / `pilot-agent`）

**finding 定位**：
```bash
# 从最终二进制反查依赖版本（不是扫源码！）
go version -m /usr/local/bin/pilot-discovery
# 输出包含所有依赖的 module version → 与 CVE 库比对
```

**修复动作**：

| 场景 | 动作 | 注意 |
|---|---|---|
| 第三方库 CVE | `go get <module>@<fixed_version>` → `go mod tidy` → 更新 `go.sum`（必要时 `go mod vendor`）| **必须同时更新 `go.sum` 和 vendor 目录**，否则构建不可复现 |
| **Go stdlib / runtime CVE** | 设 `toolchain go1.x.y`，**不要改 `go` 指令** | `go 1.24` 是语言版本语义，改它会改变编译行为；`toolchain` 才是选编译器版本 |
| builder 过旧 | 升级 CI builder 镜像到含修复后 stdlib 的版本 | 升级后**必须重新扫描最终二进制**，不能只扫源码 |
| 无法升 toolchain（需保持语言版本）| 视为上游阻塞 → 走 S1 升上游，或 S8 豁免 | 不要试图用 `replace` 指向非官方 stdlib |

**验证要点**：
- Go 二进制的漏洞**不在源码 SBOM 里**，只在最终二进制的 build info 里。
  → **必须扫描最终镜像**，扫源码仓库没有意义。
- 交叉编译后仍需确认 `go version -m` 的输出符合预期。

**Istio 场景的具体位置**：
`pilot-discovery` 和 `pilot-agent` 由 `istio/istio` 仓库的 `go.mod` 构建。
修 Go 依赖 = **L2 重编译**，在 `istio/istio` 的 fork 上改 `go.mod` → `make pilot-discovery pilot-agent`。

### 7.3 Rust / Cargo（`ztunnel`）

**已确认的源码参数**（`istio/ztunnel` @ `e06c445c6aa280ee0ce8c57062ce18686fa4bf0e`）：

```toml
edition = "2024"
rust-version = "1.90"      # MSRV
```
默认 feature 含 `tls-aws-lc`；依赖含 `rustls`、`ring`、`openssl`、`jemalloc` 等。
仓库有 `Cargo.lock`（已确认 HTTP 200）。

**修复动作**：

```bash
# 1. 升级有 CVE 的 crate
cargo update -p <crate> --precise <fixed_version>

# 2. 若上游版本不可用，临时用 patch / 替换源
#    [patch.crates-io]
#    <crate> = { git = "https://...", rev = "<sha>" }

# 3. 本地审计
cargo audit          # 查 RustSec advisory DB
cargo deny check     # 查 licenses / bans / sources

# 4. 重建
cargo build --release --locked
```

**必须保留的东西**（容易踩坑）：
- **`Cargo.lock`** —— 必须提交并锁定；`--locked` 保证构建时不会偷偷升级。
- **feature 集合** —— `tls-aws-lc` 这类 feature 切换会改变 TLS 实现，
  换掉 provider 可能引入行为差异（AWS-LC ↔ ring ↔ openssl）。**不要为了绕 CVE 随手换 feature**。
- **Git 依赖的来源锁定** —— `Cargo.toml` 里有 git 依赖
  （如 `boring-rustls-provider` 指向 `github.com/janrueth/boring-rustls-provider`），
  必须固定 `rev`，不要用 `branch` 或 `master`。
- **MSRV `1.90`** —— Rust 依赖经常抬高 MSRV。升级 crate 时要确认 CI 的 Rust 版本够新；
  不够就升级 CI 的 Rust 版本（这是 L4 锁定项，要同步更新 `lock/`）。

**验证要点**：
- **Rust 的依赖版本信息默认不进镜像 SBOM**（Rust 二进制不像 Go 那样内嵌依赖清单）。
  → ztunnel 的依赖漏洞**主要靠 `cargo audit` 在源码层发现**，而不是靠镜像扫描器。
  这是一个**重要的盲区**，必须在资产定义里显式登记：`audit_mode: source-cargo-audit`。
- 镜像扫描器对 ztunnel 只能看到 OS 包层（Wolfi 的 glibc/iptables 等），看不到 Rust crate。

### 7.4 Node.js / NPM / PNPM（`argocd` UI）

**已确认的现状**（`argo-cd@v3.6.1`）：
- Node `24.17.0`、Corepack `0.34.6`、`packageManager: pnpm@12.3.4`
- pnpm **workspace**（`ui/pnpm-workspace.yaml` + `ui/pnpm-lock.yaml`）
- 构建命令：`pnpm install --frozen-lockfile` → `pnpm build`
- UI 在 `$BUILDPLATFORM` 构建，产物 `dist` 复制到各目标架构

**修复动作**：

```bash
# 1. 定位漏洞包
pnpm audit --json
# 或用 OSV-Scanner / npm audit 交叉确认

# 2. 升级（有 fixed version 时）
pnpm update <pkg>@<fixed_version> --filter <workspace-pkg>

# 3. 无 fixed version 时用 override（pnpm 特有，跨 workspace 生效）
#    pnpm-workspace.yaml:
#    overrides:
#      <pkg>: "<fixed_version>"

# 4. 验证 lockfile 一致性（关键！）
pnpm install --frozen-lockfile   # 必须成功，否则 lockfile 与 package.json 不一致
```

**必须遵守的约束**：

| 约束 | 原因 |
|---|---|
| `pnpm-lock.yaml` 和 `pnpm-workspace.yaml` **必须一起更新** | workspace override 写在 `pnpm-workspace.yaml`，lockfile 在 `pnpm-lock.yaml` |
| **必须用 `--frozen-lockfile` 验证** | 否则 CI 会静默重新解析依赖，产出与 PR 里不一样的镜像 |
| **`packageManager` 字段锁死 pnpm 版本** | Corepack 会按此字段选版本；改动它等于换包管理器 |
| **UI 在 `$BUILDPLATFORM` 构建** | 保留这个特性，否则多架构镜像 UI 资源 hash 分叉 |
| **Argo UI 是 git 依赖**（`argoproj/argo-ui` @ 固定 commit）| git 依赖的漏洞不在 npm advisory 库覆盖范围内，需单独核对上游 commit |

**扫描盲区**：
- npm 依赖最终进的是 `dist/` 静态资源。镜像扫描器**看不到** npm 依赖（它们已打包进 JS）。
- → UI 的漏洞发现**必须在构建期用 `pnpm audit` + OSV-Scanner 扫 lockfile**，而不是靠镜像扫描。
- 这是 Argo CD 资产的 `audit_mode: source-lockfile` 注册项。

### 7.5 Python

**通用配方**（工具链需按企业仓库确认）：

```bash
# 1. 定位
pip-audit --requirement requirements.txt     # 或
uv pip compile --generate-hashes  # 哈希锁定的编译式锁定

# 2. 升级
pip-compile --upgrade-package <pkg>==<fixed_version> requirements.in

# 3. 验证
pip install --require-hashes -r requirements.txt && pip-audit
```

**必须遵守**：
- **锁文件 + 哈希**：用 `pip-compile --generate-hashes` 或 `uv` 的哈希锁定。
  没有哈希的 requirements 文件在 CI 里等于"每次构建都可能不一样"。
- **区分 wheel 与 sdist**：优先用 wheel（可复现、更少构建依赖）。
  sdist 会在构建时拉源码，可能引入构建期 CVE（**构建时 CVE 是真实攻击面**，CI runner 也在扫描范围内）。
- **构建期依赖**（pip/setuptools/wheel）本身要有版本上限和审计。
- **应用层漏洞（T5）**不进自动流水线。

### 7.6 OS / 基础镜像层（T1/T2）

见 [how-to-fix-cve-with-base-image-constraints.md](./how-to-fix-cve-with-base-image-constraints.md)（完整方案）。
本方案补充**Istio 特有的两点**：

**① Wolfi/melange 配方层（`iptables` base）**

`docker/iptables.yaml` 是 melange 配方，定义了包集合和 run-as `65532`。
**修 OS 包 CVE 的正确位置是这个配方，不是 Dockerfile**：

```yaml
# docker/iptables.yaml（示意）
package:
  name: iptables
  version: <wolfi-version>
  environment:
    contents:
      - ca-certificates-bundle
      - glibc
      - iptables
      - ip6tables
      - libnetfilter_conntrack
      - libnfnetlink
      - libmnl
      - libgcc
      - nftables-slim
```

→ 升级 Wolfi 上游版本 → 重新构建 base → 重建四个组件镜像。
这是 **L1** 路径，但**要重跑 4 个镜像的构建**。

**② Chainguard static base（`distroless` base）**

`Dockerfile.distroless` 的真实基础源是**固定 digest 的 Chainguard static**。
换 base 需要走**自建 base 准入**流程（同步 → 固定 digest → SBOM → 签名 → Binary Authorization 信任 → catalog 纳管）。
**不能简单把 `FROM` 改成 `gcr.io/distroless/static-debian12:nonroot`**：
那会丢掉 Istio 特定的配置/用户/CA bundle，且**我们已确认这不是 Istio 1.30 的实际路径**。

**③ base 受限时的两条路**（既有文档结论，此处重申）：

| 情况 | 路径 |
|---|---|
| OS 已 EOL | **必须引入仍受支持的新 base**，原地 `apk upgrade` 修不掉 |
| 需要引入新 base | 走**准入流程**（base catalog 纳管 + digest 固定 + SBOM + 签名 + 信任配置）|
| 无法引入新 base | 走 **Dockerfile 精简**（移除不需要的包），但需先证明包不可达/不需要功能，且 D4 升级为**功能级验证** |

---

## 8. CI 流水线设计

### 8.1 构建契约（每个镜像都必须满足）

| # | 契约 | 检查方式 |
|---|---|---|
| C1 | **多架构**：`linux/amd64` + `linux/arm64`（GKE 集群架构）| manifest list 含两个平台 |
| C2 | **digest 唯一**：一次构建产出一个 manifest list digest | 记录并断言 |
| C3 | **可复现**：同 lock 文件同构建产出同 digest（或至少同 SBOM）| 记录 build metadata |
| C4 | **来源可溯**：SBOM 中包含源码 commit、依赖版本 | SBOM 检查 |
| C5 | **无凭据**：镜像内无 `.npmrc`/token/`.git-credentials` | 扫描 + 人工抽查 |
| C6 | **最小权限**：非 root 运行（Istio 四个组件均满足）| `USER` 指令检查 |
| C7 | **tag 不可变**：tag 只在晋级时打，且 tag → digest 一对一 | GAR 策略 |

### 8.2 Powerline 流水线（占位平台名 `Powerline`）

> ⚠️ **`Powerline` 是本文使用的内部 CI 平台占位名**，实际平台待确认。
> 流水线结构与平台无关，可映射到 Jenkins / GitLab CI / Tekton / Cloud Build。

```
stages:
  - name: prepare          # 从分支 checkout lock + recipe，解析变量
  - name: build            # buildx 多架构构建（本地缓存/远端缓存）
  - name: push             # 推 GAR internal/ → 拿到 digest
  - name: scan             # Artifact Analysis 异步扫描
  - name: diff             # 同批次差分 → D1..D4
  - name: evidence         # 写 evidence/，产出 PR 到 images/staging
  - name: approve          # 人工审批（PR 门禁）
  - name: promote          # 合并 → images/production → 更新 state.yaml
```

**核心设计：`push` 之后立刻拿 digest，后续所有步骤都用这个 digest。**

```yaml
# 示例：Powerline 流水线片段（平台无关伪代码）
stages:
  build:
    image: builder-pinned@sha256:<BUILDER_DIGEST>   # L4 锁定
    steps:
      - checkout branch=images/staging
      - resolve:
          # 从 lock/ 读变量，不允许硬编码在流水线里
          source lock/istio/istio.deps
          source lock/istio/base-versions.yaml
      - build:
          cmd: |
            docker buildx build \
              --platform linux/amd64,linux/arm64 \
              --build-arg BASE_VERSION="${BASE_VERSION}" \
              --build-arg BASE_DISTRIBUTION=distroless \
              --build-arg ISTIO_BASE_REGISTRY="${ISTIO_BASE_REGISTRY}" \
              -f recipes/istio/pilot/Dockerfile \
              --target pilot \
              --tag "${GAR}/internal/istio/pilot:${TAG}" \
              --iidfile /tmp/iid \
              --metadata-file /tmp/meta \
              --push .
          # 关键：--metadata-file 给出 manifest digest
      - export_digest:
          from: /tmp/meta
          as: IMAGE_DIGEST

  scan:
    steps:
      - scan:
          cmd: |
            gcloud artifacts docker images scan \
              "${GAR}/internal/istio/pilot@${IMAGE_DIGEST}" \
              --remote --location=europe --async
          # 保存 operation name，轮询 get-operation
      - poll_until_complete

  diff:
    steps:
      - diff:
          baseline: state.yaml#assets[istio-pilot].current_digest
          candidate: "${IMAGE_DIGEST}"
          same_db_batch: true      # 强制：同扫描器、同 DB 批次
          checks: [D1, D2, D3, D4]
          script: ci/common/diff-gate.sh
          # 退出码 0=pass 1=fail 2=scan-error 3=unknown → 2/3 一律 fail-closed
```

### 8.3 构建工具链

| 阶段 | 工具 | 版本锁定 |
|---|---|---|
| 多架构构建 | buildx / kaniko / buildah | builder 镜像 digest |
| Go 编译 | Go toolchain | `toolchain go1.x.y` + builder digest |
| Rust 编译 | Cargo + rustup | `rust-version` MSRV + builder digest |
| Node 构建 | Node + Corepack + pnpm | Node digest + `packageManager` 字段 |
| 扫描 | Artifact Analysis | 无（托管服务）|
| 差分 | 自研 `diff-gate.sh` | 脚本版本写进 evidence |

**Go 的 `GOTOOLCHAIN` 陷阱**：
Go 1.21+ 会**自动下载** `go.mod` 里 `toolchain` 指定的版本。
在 CI 里必须**预装**该版本并设 `GOTOOLCHAIN=local`，
否则构建会临时下载（网络不确定 + 版本漂移 + 无法离线复现）。

### 8.4 GAR 仓库布局

```
europe-west2-docker.pkg.dev/[PROJECT]/containers/
├── upstream-mirror/           # Remote Repository：缓存上游 Istio/Argo 镜像
│   ├── istio-release/        # remote: registry.istio.io/release
│   └── argocd/               # remote: quay.io/argoproj
└── internal/                  # Standard Repository：我们自己构建的
    ├── istio/
    │   ├── pilot/
    │   ├── proxyv2/
    │   ├── ztunnel/
    │   └── install-cni/
    └── argocd/
```

**Remote Repository 的价值与风险**：

| | 价值 | 风险 |
|---|---|---|
| Remote | 上游新版本发布即可拉取，便于**先扫描再决定是否重建** | **digest 是否与上游完全一致需要实测验证**；缓存策略会引入本地副本 |

> ⚠️ **未验证**：GAR Remote Repository 是否严格保持上游 digest。
> **验证方法**：从 `upstream-mirror/` 拉取后计算 digest，与上游 registry 公布的 digest 对比。
> **如果不一致**，就不能把 Remote 当作"上游镜像的等价副本"，只能当作"候选来源"，
> 真正的部署镜像仍必须由我们自己构建并推 `internal/`。

**关键原则**：**部署到 GKE 的必须是 `internal/` 里我们自己构建并扫描过的 digest。**
`upstream-mirror/` 只用于对比和侦察。

### 8.5 循环迭代

用户描述的流程是对的，但要精确化：

```
① 改 recipe/lock（本地）
② 提交 PR 到 images/staging
③ Powerline: build → push → scan → diff
④ 拿到报告：
   - diff 失败 → 看 D1/D2 具体差异 → 改 recipe → 重来
   - diff 通过 → 进人工审批
⑤ 人工审批通过 → 合并到 images/production
⑥ 更新 state.yaml → 部署到 GKE（按 digest）
```

**这是"迭代"，不是"反复构建"**。每一次迭代都留下：
- 一条 commit（recipe 变更）
- 一份 evidence（扫描 + 差分 + 审批）

这让整个修复过程**可审计、可回溯、可交接**。

---

## 9. 验证契约（D1–D4）

沿用 [how-to-autofix-cve.md](./how-to-autofix-cve.md) 的契约，不改语义：

| 检查 | 含义 | 判定 |
|---|---|---|
| **D1** | 目标 finding **消失** | 该 CVE/package 在 candidate 的报告中不再出现 |
| **D2** | candidate 的 findings **是 baseline 的子集** | 没有引入新的 finding（允许因升级而自然消失的项）|
| **D3** | **digest 变化** | candidate digest ≠ baseline digest（防"构建其实没生效"）|
| **D4** | **运行时冒烟通过** | Pod 能起来 + 关键路径可用 |

**D4 的分级**（修复 base/Dockerfile 时必须升级到功能级）：

| 变更类型 | D4 最低要求 |
|---|---|
| 纯依赖升级（应用行为不变）| Pod Ready + 健康检查通过 |
| base 替换 / Dockerfile 精简 | **功能级**：关键 API 调用成功、配置解析正确、业务请求成功 |
| 应用二进制重编译（Go/Rust）| 功能级 + 版本/配置兼容性检查 |
| Envoy 变更 | **数据面**验证：sidecar 注入、配置下发、请求转发、mTLS |

**同批次约束**：
> baseline 和 candidate **必须使用同一个扫描器、同一个漏洞数据库批次**。
> DB 更新后，baseline 必须重扫，否则 D1/D2 的对比无效。

**退出码**（`diff-gate.sh`）：

| 码 | 含义 | CI 行为 |
|---|---|---|
| `0` | D1–D4 全部通过 | 继续 |
| `1` | 有检查项不通过 | 失败，输出差异明细 |
| `2` | 扫描器错误 / 报告不可用 | **fail-closed** |
| `3` | 状态未知（例如扫描器降级、DB 批次不一致）| **fail-closed** |

**fail-closed 清单**（任何一条命中 → 整体判失败）：

- 构建失败
- 推送失败或 digest 未确定
- 扫描器返回错误 / 报告缺失
- 扫描器降级到未知模式
- 漏洞 DB 批次与 baseline 不一致且未重扫 baseline
- finding 的 package **覆盖范围未知**（无法判定 D1）
- 忽略项缺少四要素（selector / reason / fix-state / expires_at）或已过期
- D4 冒烟未执行或失败

---

## 10. 部署到 GKE

### 10.1 按 digest 引用（不是 tag）

```yaml
# Deployment
spec:
  template:
    spec:
      containers:
        - name: pilot-discovery
          image: europe-west2-docker.pkg.dev/[PROJECT]/containers/internal/istio/pilot@sha256:<DIGEST>
```

**为什么必须 digest**：
- tag 可变，digest 不可变。扫描过的是 digest，部署的必须是同一个 digest。
- tag 只在 `state.yaml` 里作为"人类可读指针"存在。

### 10.2 灰度与回滚

| 阶段 | 动作 | 回滚 |
|---|---|---|
| 灰度 1 | 单个 canary DaemonSet/Deployment 用新 digest | 改回旧 digest（state.yaml 里的 `previous_digest`）|
| 灰度 2 | 单节点池 / 单 namespace 升级 | 同上 |
| 全量 | 全部替换 | 同上 |

**回滚必须只改一个字段**：digest。分支上的 `state.yaml` 保留 `current_digest` 和 `previous_digest`，
回滚 = 把 Deployment 的 image 换回 `previous_digest`，不需要重新构建。

### 10.3 Binary Authorization

- **准入策略按 digest 白名单**：只有经过审批的 digest 才允许运行。
- 未审批的 digest → 拒绝。
- 策略变更走审批（策略本身是权限边界）。
- **信任链**：GAR 的 attestation / 签名 → Binary Authorization 信任配置。
  （待确认：我们是否启用 `GAR attestation` 和自定义 verifier。）

### 10.4 与漏洞台账的联动

- 部署记录的 digest 要回写 `state.yaml`。
- SCC（Security Command Center）里的 `CONTAINER_VULNERABILITY` finding 与 `state.yaml` 做对账。
- **对账差异告警**：GAR 里有但 state 里没有的 digest = 未纳管资产 → 告警。

---

## 11. 资产定义 Schema

### 11.1 `assets/istio-pilot.yaml`（示例）

```yaml
apiVersion: images.internal/v1
kind: ImageAsset
metadata:
  name: istio-pilot
  owner: platform-networking
  created: 2026-11-09

spec:
  component: pilot
  ecosystem: istio

  # ---- 来源锁定（L1/L2/L3/L4）----
  upstream:
    repo: github.com/istio/istio
    tag: 1.30.8                       # L1: 应用源码
    commit: <PINNED_COMMIT>
    sub_projects:                     # L2: 子项目 commit
      proxy: 16f21841fa6b55f5b8c982593c4a4adc87392491
      ztunnel: e06c445c6aa280ee0ce8c57062ce18686fa4bf0e
    lock_file: lock/istio/istio.deps
  base:                                # L3: 基础镜像
    registry: registry.istio.io/release
    distribution: distroless          # pilot 用 distroless；proxyv2/ztunnel/install-cni 用 iptables
    version: 1.30-2026-11-04T19-02-08
    digest: null                      # 首次构建后回填
  toolchain:                           # L4: 构建工具链
    go: 1.27.3
    builder_digest: null

  # ---- 构建 ----
  build:
    recipe: recipes/istio/pilot/Dockerfile
    orchestrator: upstream             # 上游 tools/docker 编排，我们只覆盖 recipe
    upstream_entrypoint: tools/docker
    platforms: [linux/amd64, linux/arm64]

  # ---- 制品 ----
  artifacts:
    gar_repository: europe-west2-docker.pkg.dev/[PROJECT]/containers/internal/istio/pilot
    tag_policy: immutable               # tag 一旦打上不改写
    current_digest: null
    previous_digest: null
    sbom: null

  # ---- 审计模式（关键：不同生态的发现来源不同）----
  audit:
    image_scan: true                    # OS 层：Artifact Analysis
    source_scan: false
    source_scanner: null                # ztunnel=cargo audit；argocd-ui=pnpm audit；go=osv-scanner
    lockfile: null

  # ---- 策略 ----
  strategy_policy:
    prefer_upstream: true               # 优先 S1
    allow_source_rebuild: true          # 允许 L2
    allow_base_swap: false               # 换 base 需要走准入流程
    forbidden:
      - pin_to_tag_only
      - skip_diff_verification

  # ---- 生命周期 ----
  lifecycle:
    state: TRACKED
    upstream_eol: null
    next_review: 2026-12-09

  # ---- fork 登记（S3 时必填）----
  fork:
    enabled: false
    fork_of: null
    reason: null
    expiry: null
    upstream_target: null
```

### 11.2 字段要点

| 字段 | 必填 | 约束 |
|---|---|---|
| `spec.upstream.commit` | 是 | 必须是 40 位 SHA，不能是 branch |
| `spec.base.digest` | 首次构建后 | base 一旦确定即固定；换 base 走准入流程 |
| `spec.audit.source_scanner` | 视生态 | Rust/Node/Python 必须填，因为镜像扫描器看不到这些依赖 |
| `spec.lifecycle.state` | 是 | 枚举值，见 §2.3.2 |
| `spec.fork.expiry` | fork 时必填 | **到期自动回到"跟上游"**，不靠人记得 |
| `spec.strategy_policy.forbidden` | 是 | 至少包含 `pin_to_tag_only` |

### 11.3 `state.yaml`（顶层汇总）

```yaml
assets:
  - name: istio-pilot
    lifecycle_state: VERIFIED
    current_digest: sha256:<...>
    previous_digest: sha256:<...>
    last_scan_id: <SCAN_ID>
    last_db_batch: <BATCH_ID>
    last_verified_at: 2026-11-09
    open_findings: 0
    exceptions: []
```

---

## 12. Dependabot 在本方案中的准确定位

**结论：Dependabot 是"依赖版本变更的信号源"，不是"修复流水线"。**

### 12.1 生态支持（实测结论）

| 生态 | Dependabot 能做什么 | 不能做什么 |
|---|---|---|
| **Docker** | **只有 version updates**（改 `FROM` 的 tag）| **不支持 CVE security updates**；不解析 `ARG BASE_IMAGE` 间接引用；不处理 OS 包 |
| **Go modules** | ✅ 支持 security updates | 只产 PR，不构建、不扫描、不推 GAR |
| **Maven / Gradle** | ✅ 支持 security updates | 同上 |
| **npm / pnpm** | ✅ 支持（但需配 workspace）| 跨 workspace override 需要 `pnpm-workspace.yaml` 配合 |
| **Cargo** | ❌ 无官方支持 | 用 `cargo audit` + 自建脚本 |
| **Python** | ⚠️ 支持有限 | 用 `pip-audit` / OSV-Scanner 更可靠 |
| **Wolfi/melange** | ❌ | 改配方 |

### 12.2 在本方案中的正确用法

```
Dependabot（GitHub）→ 生成 PR（改 lockfile / Dockerfile tag）
        ↓
我们的 CI 在 PR 上跑：构建 → 推 GAR → 扫描 → 差分
        ↓
D1-D4 通过 → 人工审批 → 合并
```

**所以 Dependabot 的价值在于**：它替我们**发现并提出**依赖升级，
但**通过标准必须是我们自己的 D1–D4**，而不是"Dependabot PR 已合并"。

### 12.3 已知的 Dependabot 局限（实测）

- `docker` ecosystem **没有 security updates**（这在既有文档中已被反复确认）。
- 间接 base 引用（`ARG BASE_IMAGE`）**解析不到**。
  - Argo CD 的 Dockerfile 用 `ARG BASE_IMAGE`，所以 Dependabot 对它无效。
  - **Istio 的 Dockerfile 同样用 `ARG BASE_VERSION` + `ARG ISTIO_BASE_REGISTRY`** → 同样解析不到。
- Dependabot PR `#15103` 的实验开关 `docker_digest_only_update_suppression`：
  开启后**同 tag 的 digest-only 更新会被视为"已是最新"**（抑制噪音）；
  tag 推进时仍会更新 digest。
  - ⚠️ 该开关在企业环境是否默认可用，**待确认**。
  - 这个特性对我们其实**很合适**：我们已经在 lock 里固定 digest，
    digest 漂移应该由我们自己的巡检发现，而不是靠 Dependabot 提 PR。

### 12.4 对我们的具体建议

| 场景 | 工具 |
|---|---|
| Go 依赖 CVE | Dependabot（security updates）+ 我们的 CI |
| Argo CD UI npm 依赖 | Dependabot 或 Renovate（配 pnpm workspace）|
| Istio `ARG BASE_VERSION` 升级 | **不用 Dependabot**，用我们自己的"上游版本巡检"机器人 |
| ztunnel Cargo 依赖 | `cargo audit` + 自建 PR 机器人 |
| Wolfi/melange base | 自建：监控 Wolfi 版本 → 改 `docker/iptables.yaml` → 重建 |
| Argo CD `ARG BASE_IMAGE` 升级 | **不用 Dependabot**，自建巡检 |

> **结论**：我们**不能把 Dependabot 当作主要机制**。
> 它只覆盖 Go/npm/maven 三块，且只到"提 PR"为止。
> 其余（base 版本、Cargo、melange、Argo 的 `ARG BASE_IMAGE`）必须自建巡检机器人。

---

## 13. 落地路线图

### Phase 0 —— 事实确认（1–2 天）⚠️ **必须先做**

**目标**：把 §14 待确认清单里的"必须实测"项全部变成事实。没有这一步，后面全是猜测。

1. **确认内部镜像的真实来源**
   ```bash
   docker pull <内部地址>/ztunnel:1.30.3-distroless
   docker inspect --format='{{index .RepoDigests 0}}' <内部地址>/ztunnel:1.30.3-distroless
   # 与 §1.1 官方 digest 对比，确认是否一致
   ```
2. **确认内部 registry 地址**：是 GAR 的哪个仓库？是否已有 `upstream-mirror`？
3. **确认扫描器**：Artifact Analysis 是唯一裁判吗？内部 violation 扫描器是什么、输出什么格式？
4. **确认 CI 平台**：`Powerline` 对应哪个系统？支持多架构构建和自定义 runner 吗？
5. **确认 Argo CD 版本**：我们实际部署的是哪个版本？（本文以 `v3.6.1` 为参照）

**交付物**：`assets/*.yaml` 的第一版（`current_digest` 已填、来源已确认）。

### Phase 1 —— 控制面落地（3–5 天）

1. 建 `images/production` / `images/staging` 分支 + 分支保护
2. 建目录结构（§3.2）
3. 写 `assets/*.yaml`（5 个资产）
4. 写 `state.yaml` 初始台账
5. **首次全量扫描** `internal/` 现有 digest，生成 baseline 报告

**验收**：任何人 `git clone` 后能读懂每个镜像的来源、版本、状态和已知问题。

### Phase 2 —— 构建闭环打通（1–2 周）

1. 先做**最容易的一个**：`install-cni`（纯 Go，无 Envoy，最小）
   - 用上游 `tools/docker` 编排
   - 跑通 buildx 多架构 → 推 GAR → 扫描 → 差分
2. 再做 `pilot`（Go）
3. 再做 `ztunnel`（Rust）
4. 最后做 `proxyv2`（Envoy 预编译产物；如需 L2 则最贵）

**验收**：CI 能在 `images/staging` 上跑通完整 8 阶段流水线，产出 evidence。

### Phase 3 —— 差分门禁 + 审批（1 周）

1. 实现 `diff-gate.sh`（D1–D4 + 退出码 0/1/2/3）
2. 接入 PR 门禁
3. 实现人工审批流

**验收**：一个"故意注入 vulnerability 的"PR 会被门禁挡住。

### Phase 4 —— 常态巡检（1 周）

1. 上游版本巡检机器人（Istio/Argo/Wolfi/Node/Rust/Go）
2. 每日内部全量扫描
3. CVE 公告订阅 → Agent 生成 triage 报告
4. SCC 对账告警

### Phase 5 —— 常态化修复演练（持续）

- 每季度做一次**完整演练**：从"发现公告"到"GKE 部署新 digest"全流程，计时。
- 这是唯一能证明流程真的能用的方法。

---

## 14. 待确认事项

### 必须实测（Phase 0 阻塞项）

| # | 事项 | 为什么重要 | 怎么测 |
|---|---|---|---|
| 1 | **内部镜像的真实 registry 地址和 digest** | §1.1 表格只是官方参照；`soloio-img` 公共 API 返回 `count:0` + 匿名 `401` | 内部 `docker pull` + `docker inspect` 取 RepoDigests |
| 2 | **内部镜像与官方 `istio/*:1.30.3-distroless` 是否同一内容** | 决定能否直接用官方镜像作为重建基线 | 对比 digest + layer 列表 |
| 3 | **GAR 已有仓库与权限** | 决定 Remote/Standard 怎么建 | `gcloud artifacts repositories list` |
| 4 | **Artifact Analysis 的区域和配额** | 扫描要在正确区域发起 | `gcloud artifacts docker images scan --help` + 试跑 |
| 5 | **violation 扫描器是谁、输出什么** | 是"扫描器唯一裁判"原则的落地 | 内部确认 |
| 6 | **CI 平台（`Powerline`）的真实能力** | 多架构构建、缓存、私有网络访问 | 内部确认 |
| 7 | **Argo CD 实际版本** | 决定 Node 是 Yarn 还是 pnpm | 看 GKE Deployment |
| 8 | **Base Image 准入流程** | 换 base 的前置条件 | 内部确认 |

### 已知但未验证

| # | 事项 |
|---|---|
| 9 | GAR Remote Repository 是否严格保持上游 digest |
| 10 | `ISTIO-SECURITY-2026-008` 的单独 fixed-version 文本（目前只有 affected range）|
| 11 | `1.30.8` 是否还有其他未公告的 violation —— **必须由我们自己的扫描器判定** |
| 12 | `istio/proxy` 的完整 Envoy/Bazel 构建在内部 CI 的成本与可复现性 |
| 13 | `gcloud artifacts sbom export/list/load` 对目标 GAR 镜像的实际产出 |
| 14 | `docker_digest_only_update_suppression` 在企业环境是否可用 |
| 15 | Binary Authorization 的信任链配置（是否启用 attestation verifier）|
| 16 | IAM / KMS 角色划分（谁能推 `internal/`、谁能审批、谁能改策略）|
| 17 | 严重度分级与 SLA（每个 T 类型多久内必须修完）|
| 18 | 豁免审批流程与到期提醒机制 |
| 19 | `istio/ztunnel` 是否使用 `cargo-auditable`（影响 Rust 依赖能否被镜像扫描器发现）—— **实测 grep 结果：Cargo.toml 中无 `auditable` 相关配置**，倾向"不可发现" |
| 20 | Argo CD UI 的 `argo-ui` git 依赖固定 commit 是否有已知 CVE |

---

## 15. 反模式（明确不要做）

| ❌ 反模式 | 为什么错 | ✅ 正确做法 |
|---|---|---|
| 把 OCI 镜像 tar 存进 Git | 仓库膨胀、diff 无意义、审计靠不住 | Git 存配方，GAR 存二进制 |
| 用 tag 部署 | tag 可变，扫的和跑的可能不是一个 | 一律 digest |
| "扫一个、推另一个" | 验证结论无效 | Verify-then-Promote |
| 在 Dockerfile 里 `apk upgrade` 修 OS CVE | 修的是层不是源，下次重建丢失 | 改 melange 配方 / 换 base |
| 修了源码但不扫最终二进制 | Go/Rust/Node 依赖不在源码 SBOM 里 | 扫最终镜像 + 源码双轨 |
| 整镜像忽略漏洞 | 掩盖问题 | 精确到 package selector + 到期时间 |
| fork 后不管 | 分叉漂移，越维护越贵 | 登记 `expiry`，到期回上游 |
| 让 Agent 直接合并 T5 补丁 | 应用代码缺陷需人判断 | 人工合并是强制的 |
| Dependabot PR 一合并就部署 | 没经过构建/扫描/差分 | Dependabot 只提供信号 |
| 在 `images/production` 直推 | 绕过门禁 | 分支保护 + 审批 |
| 给 `ARG BASE_IMAGE` / `ARG BASE_VERSION` 期望 Dependabot 能改 | 它解析不到间接引用 | 自建巡检机器人 |

---

## 16. 一句话总结

> **Git 分支是控制面，GAR 是制品面，digest 是两者之间唯一的契约。**
>
> 修复流程 = 「发现 → 定级 → 选策略（优先跟上游）→ 出配方 → 构建 → 推送 → 扫描 → 同批次差分 → 人工审批 → 按 digest 晋级」。
>
> Dependabot 只是其中一个环节的信号源；GitHub 只是 PR 评审场所；真正的修复能力在
> **「我们能不能用精确锁定的来源，把镜像原样重建出来，并在同一条 digest 上证明漏洞真的消失了」**。
>
> 能重建 → 修复是工程问题。
> 不能重建 → 只能等上游，那所有自动化都只是"看得见"而不是"修得掉"。

---

## 附录 A —— 关键实测数据（2026-11-09）

### A.1 Istio 镜像 digest

| 组件 | `1.30.3` | `1.30.8` | `1.30.8-distroless` |
|---|---|---|---|
| `pilot` | `6b37817f7f8f8e0f6f6fffc832c44ae4d7e50feec7ef7f1f3719638d1bbdc45a` | `2870bd69cfe503eca0f703d6d17511daaae2167012d418297054f735a05bc8f2` | `9d332c4b24b25b3da2416c8e3506cb17779d67633e811fa4aeca70e5915f9927` |
| `proxyv2` | `485c87f71654b14e89911a9424a208d92b347b59c2bfefdc9707aaa83fe5618e` | `a40d8ac073a342b07a748e6c81675636b298cd3e9bd6a7eb14036187b052d350` | `ff17cf1cb0a9659eac744b7398b17797996b723e1962d94d3b6a85f670e36bf8` |
| `ztunnel` | `140bc279e202f63ea1c68cabe6e3a65b12be7ecd1944142c3476e4fbccb749bf` | `c0e474c4761606abb802970a3d2343563edfb190a622f9c765956ac92c5bad12` | `79de3e4a3ab2fa495508987de7713027b2d8e85100bde0a0b42f859d810e0421` |
| `install-cni` | `6eff4c23a5b82516eadc356c554bfac303c46c3cecfd47d637f0a5f6b368983b` | `68b717422f9a81ddc27528d105866408ed5f32f9a0f8f64b43214cca1f90d68e` | `8b25c66a2930cf2f991f99f504586ca64ebc36857137f10de3541590fe1822bc` |

`1.30.3-distroless`（Docker Hub `istio/*` 与 `registry.istio.io/release/*` 逐字一致）：
pilot `eba09c50…`、proxyv2 `2f59eaf9…`、ztunnel `de46b51d…`、install-cni `ff7964e8…`（完整值见 §1.1）。

### A.2 Istio 基础镜像

- `release/base` ← `ubuntu:noble`
- `release/distroless` ← 固定 digest 的 Chainguard static
  `sha256:fc42af33e643f20d08baf03cddcc1c02ba57052dfb02edb0d79f3fc47bcea8d9`
- `release/iptables` ← Wolfi/melange 配方（`docker/iptables.yaml`），支持 `x86_64` / `aarch64`
- `pilot` → `release/distroless`；`proxyv2`/`ztunnel`/`install-cni` → `release/iptables`

### A.3 Istio 构建入口

```bash
./tools/docker --save              # 本地保存
./tools/docker --push              # 推送
DOCKER_TARGETS=docker.pilot ./tools/docker    # 指定 target
HUB=<registry> TAG=<tag> ./tools/docker        # 覆盖 hub / tag
```
`TAG ?= $(shell git rev-parse --verify HEAD)`（默认 = commit SHA）；`HUB ?= istio`。

### A.4 Argo CD `v3.6.1` 摘要

| 项 | 值 |
|---|---|
| 发布时间 | `2026-11-04T13:21:06Z` |
| base | `ubuntu:26.04@sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b` |
| Go | `1.27.3@sha256:957861185dbf29d93668ace41e011d091c6e779953d47f0316ef2cc58e28fe2b` |
| Node | `24.17.0@sha256:032e78d7e54e352129831743737e3a83171d9cc5b5896f411649c597ce0b11ea` |
| Corepack | `0.34.6` |
| pnpm | `12.3.4`（`ui/package.json` 的 `packageManager` 字段）|
| Go 构建 | `make argocd-all` |
| UI 构建 | `$BUILDPLATFORM` 上构建 → 同一份 `dist` 复制到各目标架构 |

维护版本：`v3.3.19`、`v3.4.13`、`v3.5.7`；`v3.2.0`（历史样例）：Go `1.25.0`、Node `23.0.0` + Yarn。

---

## 附录 B —— 相关文档

| 文档 | 用途 |
|---|---|
| [how-to-autofix-cve.md](./how-to-autofix-cve.md) | 闭环框架、角色边界、状态机、验证契约、T1–T5 修复细则、`gcp-cve-fix.yaml` 草案 |
| [how-to-use-dependabot.md](./how-to-use-dependabot.md) | Dependabot 配置、GAR OIDC、PR 门禁、SCC/Artifact Analysis 分工 |
| [how-to-fix-cve-with-base-image-constraints.md](./how-to-fix-cve-with-base-image-constraints.md) | base 受限时的准入流程与 Dockerfile 精简、VEX、base catalog、EOL 巡检 |
| [how-to-fix-dex-base-image.md](./how-to-fix-dex-base-image.md) | 单 case Runbook 的写法样例 |
| [cve-cwe.md](./cve-cwe.md) | CVE 台账主键与 CWE 根因模型 |
| `../how-to-fix-violation/` | violation 扫描/修复/CI 集成现有材料 |
