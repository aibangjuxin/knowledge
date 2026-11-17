# Argo CD 镜像重建与 CVE 修复 —— 「Buildpack 式」路线的可行性与落地设计

> 编写日期：2026-11-17
> 场景：把 Argo CD 及其运行时依赖镜像（`argocd` / `dex` / `redis`）从公共仓库 relocate 到内部 GAR
> （`us-east4-docker.pkg.dev/projectID-capus-prod/containers/`），并解决扫描出来的 CVE / CWE violation。
>
> 关联文档（本文是它们的**补充**，不重复）：
> - [how-to-maintain-upstream-images.md](./how-to-maintain-upstream-images.md) —— 分支控制面 + GAR 制品面的总体架构、L1/L2 修复分级
> - [how-to-autofix-cve.md](./how-to-autofix-cve.md) —— 闭环框架、验证契约（差分 + 冒烟）、T1–T5 分类
> - [how-to-fix-cve-with-base-image-constraints.md](./how-to-fix-cve-with-base-image-constraints.md) —— base 受限时的准入流程
> - [how-to-fix-dex-base-image.md](./how-to-fix-dex-base-image.md) —— Dex 的单 case Runbook
> - [how-to-use-dependabot.md](./how-to-use-dependabot.md) —— 依赖层自动化
> - [cve-cwe.md](./cve-cwe.md) —— 台账主键与根因模型
> - [../../devops/buildpacks/imgutil.md](../../devops/buildpacks/imgutil.md) —— `imgutil` 库：CNB 生态的镜像操作层（本文「Buildpack 式」一节的技术底座）
>
> ⚠️ **占位符约定（本文所有仓库路径均为占位符，不是真实值）**：
> `projectID` = GCP 项目号占位符、`capus-prod` = 内部制品仓库路径占位符、`us-east4` = 区域示例、
> `<digest>` / `<sha>` / `<owner>` 等尖括号内容 = 待填占位符。
> **本仓库对外可见，禁止写入真实项目号、机构名、工号等内部标识**；
> 提交前统一替换为占位符（与 `gcp/asm/diagram/` 下的既有写法保持一致）。

---

## 0. 结论摘要

| 问题 | 结论 |
|---|---|
| **能不能用 Buildpack 的思路解决 violation / CWE** | **能，而且对 Argo CD / Dex 成本极低** —— 因为上游 Dockerfile 就是公开配方，你只要 fork 那份 Dockerfile + 改版本号。不需要自己写 buildpack。 |
| **「都是 Go 包」这个前提成立吗** | **只对一半**。Argo CD、Dex 是 Go；**Redis 是 C**（官方镜像从 `redis-x.y.z.tar.gz` 编译，还带 jemalloc 的 sed patch）。三个镜像不能走同一条路线。 |
| **Go 重建有什么独特优势** | Go 二进制静态链接（Argo CD `CGO_ENABLED` 默认 0）→ **OS 层 CVE 与业务二进制无关**，扫描器报的 OS finding 可以只靠换 base 解决；Go 层 CVE 则**能用 `go version -m` 直接读出嵌入的模块版本**，判定「是否受影响、能否 bump」是确定性的，不靠猜。 |
| **什么才是真正的「Buildpack 式」场景** | **你只有预编译产物、没有上游 Dockerfile** 的资产（Istio `proxyv2`/Envoy、`ztunnel`/Rust）。那时 pack 能把 tarball 直接打成层；Argo CD 反而**用不上 pack**（上游 Dockerfile 已经是最好的配方）。 |
| **Git 仓库怎么建** | 推荐**独立仓库 `platform-images`**（不是继续在业务仓库里加分支）：`assets/` + `recipes/` + `lock/` + `state.yaml` + `evidence/`。Git 里只放**配方与状态**，二进制放 GAR。 |
| **CWE 真来了怎么修** | 走 §5 的**五分类归因 → 决策树 → 改一行 → 重建 → 扫描差分 → 晋级 digest**。Go 依赖类基本是「改 `go.mod` 一行 + 重建」；OS 类是「改 base digest」；前端是「改 `pnpm-workspace.yaml` 的 overrides」。 |
| **最容易被忽略的一件事** | Argo CD 的 `gitops-engine` 是**独立 module**（`replace github.com/argoproj/argo-cd/gitops-engine/v3 => ./gitops-engine`）。**只改根 `go.mod` 会漏掉它**，而且它是历史 CVE 高发区。 |
| **上游已经在用「replace 躲 CVE」** | 是的。`v3.6.1` 的 `go.mod` 里就有 `gopkg.in/yaml.v2 => v2.4.0 // Avoid CVE-2022-3064`。这就是我们要抄的模式。 |
| **Redis 怎么办** | **不要重建**。优先「换形态」：① 升到更新的官方 tag（官方自己会 bump alpine）；② HA 场景直接用 GCP Memorystore 托管 Redis，镜像问题从根上消失。重建 C 代码的收益远低于成本。 |

---

## 1. 前提校正：三个镜像不是同一类东西

你的原始判断是「这三个都是 Argo CD 安装/运行所需的组件镜像」。这个分类是对的，但**修复路线**上它们分属三类：

| 镜像 | 组件 | 语言/构建 | 上游 Dockerfile | CVE 主要来源 | 推荐路线 |
|---|---|---|---|---|---|
| `quay.io/argoproj/argocd` | Argo CD 主镜像（server / repo-server / controller / notifications / applicationset / dex-proxy 等） | **Go 1.27**（`make argocd-all`）+ **Node/pnpm** 构建 UI | ✅ 公开，3~4 个 stage | ① ubuntu 里的 OS 包（`git`/`gpg`/`openssh-client`/`tini`/`ca-certificates`）② Go module（`golang.org/x/crypto`、`x/net`、`golang-jwt/jwt`、`grpc`、`k8s.io/*`…）③ 镜像里额外塞进去的 **helm / kustomize / git-lfs 三个 Go 二进制** ④ pnpm 前端依赖 | **从源码重建**（首选） |
| `ghcr.io/dexidp/dex` | 可选 SSO/OIDC | **Go + `CGO_ENABLED=1`**（动态链接 musl） | ✅ 公开，`tonistiigi/xx` 跨编译 | ① alpine 包 ② Go module ③ **因为 CGO=1，OS 层的 libc/musl CVE 会真的打到 dex 二进制上** | **从源码重建** |
| `public.ecr.aws/docker/library/redis` | 缓存 / 通知队列 | **C**（官方镜像从 `redis-7.2.13.tar.gz` 编译，含 jemalloc 的 `sed` patch） | ✅ 公开但极脆弱 | ① alpine/debian 包 ② redis 自身 CVE | **不重建**：升官方 tag 或换成托管服务 |

> ⚠️ 一个必须记住的差别：
> **Argo CD 是静态 Go 二进制（无 libc）**，所以「扫描器报的 OS CVE」和「业务代码」是两件事，改 base 就行；
> **Dex 是动态链接（musl）**，OS 层 finding 的影响面更大，不能简单当噪声忽略。
> 这直接决定了 §5.2 的归因表要分开处理。

### 1.1 三者的角色差异（决定要不要都自己维护）

| 组件 | 是否 Argo CD 安装必需 | 我们真的要重建它吗 |
|---|---|---|
| `argocd` | ✅ 必需（核心） | **要**。核心资产，必须自己可重建、可打补丁、可出 SBOM。 |
| `dex` | ⚠️ 可选（启用 Dex SSO 时需要） | **要，但优先级次之**。它是可选依赖，很多团队根本没启用 —— 先确认我们到底有没有在用（§9 待确认第 1 条），没用就干脆不引入。 |
| `redis` | ⚠️ 可选（HA / 缓存场景需要） | **大概率不要**。见 §4.3。 |

---

## 2. 「Buildpack 式重建」到底指什么

### 2.1 三套技术的对应关系

```
pack build（CNB）                          Dockerfile 多阶段            我们要的效果
─────────────────────────────────          ────────────────────        ──────────────────
detect  探测项目类型/选 buildpack     ≈     决定用哪个 builder 镜像   选 golang:1.27.x / node:26.x
build   跑 buildpack，产出 layers     ≈     RUN make argocd-all       产出 dist/argocd*
export  组装成镜像并推送             ≈     COPY --from=build + 推送   COPY --from=build ... + push
─────────────────────────────────────────────────────────────────────────────────────────
pack 的价值：把「源码 → 镜像」标准化，但需要 builder 镜像 + lifecycle，产出可复现性更难保证
Dockerfile 的价值：配方完全可见、可审计、可逐行改 —— 对「精确修一个 CVE」更合适
```

### 2.2 和 `imgutil` 的关系（为什么这套方法在 CNB 世界里成立）

`imgutil`（见 [../../devops/buildpacks/imgutil.md](../../devops/buildpacks/imgutil.md)）把镜像操作抽象成：

- `local` / `remote` / `layout` 三个后端 —— 同一套逻辑，可以落到 daemon、registry、OCI layout；
- `AddLayer` / `ReuseLayer` / `AddOrReuseLayerWithHistory` —— **层复用**，这正是增量构建（复用上一版应用层、只换基础层）的原语；
- `Rebase(baseTopLayerDiffID, newBase)` —— **换基础镜像而应用层 diffID 不变**。

> **我们要做的「CVE 修复」，本质就是 `Rebase` 的工程化版本**：
> 保持「应用层」不动（或者重新编译出等价的应用层），只把「有漏洞的层」换掉。
> 只不过在 Go 项目里，「有漏洞的层」往往就在**编译产物内部**（依赖版本被编进了二进制），
> 所以必须**重新编译**而不是简单换层 —— 这是 Go 与「拷贝预编译二进制」类资产（Istio）的根本差别。

### 2.3 什么时候用哪条路（选型表）

| 资产形态 | 例子 | 推荐路线 | 成本 |
|---|---|---|---|
| 上游 Dockerfile 公开、源码可编译、**纯 Go** | Argo CD、Dex | **抄上游 Dockerfile + 改版本**（本文主线） | 低（小时级） |
| 上游 Dockerfile 公开，但产物是**预编译二进制**（Bazel/Rust/C++） | Istio `proxyv2` / `ztunnel` | **L1 重打包**：复用 GCS 预编译产物，改 OS/base 层 | 中 |
| 依赖**闭源或商业组件**，无法重编译 | 商业 APM agent、部分 DB 镜像 | **派生镜像覆盖**：`FROM upstream` + `COPY --from` 替换单个文件 | 极低 |
| **无源码、无 Dockerfile**（只有 tarball） | 一些闭源 SDK 镜像 | **`pack` 或等价工具把 tarball 打成层**（这才是 pack 主场） | 低 |
| OS 层 CVE（base 过期） | 任意镜像 | **换 base digest / dist-upgrade** | 极低 |
| Go 依赖 CVE | Argo CD、Dex | **bump `go.mod` + 重建**（或 `replace` 强制版本） | 低 |
| C/原生依赖 CVE | Redis | **换版本 / 换形态**（重建不划算） | — |

> **一句话结论**：你说的「用 Buildpack 的逻辑解决」方向对，但**对 Argo CD 这类资产，pack 是过度设计**。
> 真正该借的是 **Buildpack 的世界观**（把镜像当作「可重建的产物」而不是「下载的黑盒」），
> 而不是它的工具。

---

## 3. Git 仓库怎么建

### 3.1 两种组织方式

| 方案 | 形态 | 优点 | 缺点 | 适用 |
|---|---|---|---|---|
| **A. 独立仓库**（推荐） | `internal/platform-images` 一个仓库，目录按组件分 | ① 权限可以独立给（只给镜像维护者）② 审计面小（只有镜像配方）③ 不会被业务 PR 淹没 ④ CI 触发规则简单 | 需要新建仓、可能要处理账号/仓库策略 | 资产 ≥ 3 个，且有专职维护者 |
| **B. 分支控制面**（现有文档的方案） | 在已有仓库上开 `images/production` 分支 | 不新建仓 | 分支保护策略和业务分支打架；权限粒度差；PR 噪音 | 资产少、还没成体系 |

> 现有文档 [how-to-maintain-upstream-images.md](./how-to-maintain-upstream-images.md) 走的是 B。
> 当 Argo CD + Dex + 后续更多资产进来、且涉及「谁能改镜像配方」这种敏感权限时，
> **切到 A（独立仓）更干净**。两者不冲突：B 的目录结构可以直接搬进 A。

### 3.2 推荐仓库结构

```
platform-images/                      # 独立仓库,只放配方与状态,不放二进制
├── README.md                         # 这个仓库是干什么的、怎么改一次 CVE
├── AGENTS.md                         # 给 AI Agent 的约束(可选,但很值)
├── CODEOWNERS                       # images/* → 平台镜像组
├── .github/                          # 或公司 Git 平台等价物
│   ├── CODEOWNERS
│   └── workflows/
│       ├── build.yaml                # 构建 → 推 GAR → 触发扫描
│       └── scan-diff.yaml            # 差分 + 产出证据
│
├── assets/                           # ① 资产定义(唯一真相源)
│   ├── argocd.yaml
│   ├── dex.yaml
│   └── redis.yaml
│
├── recipes/                          # ② 我们的 Dockerfile(改上游配方的地方)
│   ├── argocd/
│   │   ├── Dockerfile                # 从上游 v3.6.1 Dockerfile 抄改而来
│   │   ├── README.md                 # 与上游 Dockerfile 的 diff 说明
│   │   └── patches/                  # 需要打源码补丁时放这里
│   │       └── 0001-xxx.patch
│   ├── dex/
│   │   └── Dockerfile
│   └── redis/
│       └── Dockerfile                # 仅做 base 替换/加固,不做源码重编译
│
├── lock/                             # ③ 精确锁定(可复现的关键)
│   ├── argocd-v3.6.1.lock.yaml       # 上游 tag/commit + base digest + go.sum 指纹
│   ├── dex-v2.44.0.lock.yaml
│   └── redis-7.2.13.lock.yaml
│
├── state.yaml                        # ④ 状态机 + finding 台账 + 豁免(唯一真相源)
├── evidence/                         # ⑤ 证据链(扫描报告/差分/审批,脱敏后)
│   └── argocd/
│       └── 2026-11-17-v3.6.1-rebase-ubuntu2604/
│           ├── scan-baseline.json
│           ├── scan-candidate.json
│           ├── diff.json
│           └── approval.md
└── ci/                               # ⑥ 流水线定义(若用平台原生而非 GitHub Actions)
    ├── build.yaml
    └── scan.yaml
```

### 3.3 各文件职责与示例

**`assets/argocd.yaml` —— 资产定义**

```yaml
apiVersion: images.internal/v1
kind: ImageAsset
metadata:
  name: argocd
spec:
  role: required              # required | optional | candidate
  upstream:
    repo: https://github.com/argoproj/argo-cd
    tag: v3.6.1
    commit: "<填 upstream commit sha>"     # 必须 pin,不能只写 tag
    license: Apache-2.0
  artifact:
    # 生产引用一律用 digest,不用可变 tag
    repository: us-east4-docker.pkg.dev/projectID-capus-prod/containers/argocd
    digest: "sha256:<构建后回填>"
    platforms: [linux/amd64, linux/arm64]
  build:
    recipe: recipes/argocd/Dockerfile
    lock: lock/argocd-v3.6.1.lock.yaml
  runtime:
    user: 999                  # argocd
    entrypoint: ["/usr/bin/tini", "--"]
    ports: [8080, 8081, 8082, 8083]
  consumers:
    - gke://argocd/argocd-server
    - gke://argocd/argocd-repo-server
status:
  lifecycle_state: VERIFIED   # TRACKED|VULNERABLE|FIXING|VERIFYING|BLOCKED|VERIFIED|EOL|RETIRED
  owner: platform-images
  last_scan: 2026-11-17
```

**`lock/argocd-v3.6.1.lock.yaml` —— 精确锁定**

```yaml
upstream:
  tag: v3.6.1
  commit: "<sha>"
  dockerfile_sha256: "<上游该 tag 的 Dockerfile 文件哈希>"
base:
  runtime: ubuntu:26.04@sha256:2260313b31c8c011cd2eebe725008efac1b3982be73eb71348ea2648d2c0e09b
  builder: golang:1.27.4@sha256:08bcb99a38f85a265f9a93d1d3323e2440eec333380f3ea26ee0dec9264bb41c
  node: node:26.13.1@sha256:e18c3ccdf7d71619990b0e85639f506e2028a95410999cab24cc373cbd10e0ac
go:
  toolchain: go1.27.4
  module: github.com/argoproj/argo-cd/v3
  go_sum_sha256: "<go.sum 哈希>"
  gitops_engine_go_sum_sha256: "<gitops-engine/go.sum 哈希>"   # 别忘了嵌套 module
```

**`state.yaml` —— 状态机与 finding 台账**（格式沿用 [how-to-autofix-cve.md](./how-to-autofix-cve.md) §3.2）

```yaml
assets:
  argocd:
    lifecycle_state: VERIFIED
    current_digest: "sha256:..."
    findings:
      - id: CVE-2025-XXXXX
        source: os-package        # os-package | go-module | go-stdlib | npm | misconfig
        component: git
        severity: HIGH
        status: FIXED
        fixed_by: "base rebase → ubuntu:26.04"
        evidence: evidence/argocd/2026-11-17-.../diff.json
    waivers:
      - id: CVE-2025-YYYYY
        reason: "调用路径不可达(govulncheck 确认),Go 二进制静态链接不受影响"
        expires: 2026-12-17        # 必须有到期时间,见验证契约 §4.4
        approver: "<安全负责人>"
```

### 3.4 Git 侧的分支与权限模型

| 分支/标签 | 含义 | 谁能写 | 谁能合 |
|---|---|---|---|
| `main` | 配方与状态的当前状态 | 镜像维护者 | 需 1 个 reviewer + CI 通过 |
| `release/<asset>-<upstream-version>` | 正在为某个上游版本做 CVE 修复 | 镜像维护者 | — |
| `tag: <asset>-v<ver>-<date>` | **已验证通过的配方快照**（对应一个已扫描的 digest） | 只读 | — |

配套：

- **CODEOWNERS**：`recipes/**` 与 `state.yaml` 归平台镜像组；改这两处的 PR 必须该组 review。
- **分支保护**：`main` 禁止 force push；PR 必须通过 `build + scan + diff` 流水线。
- **一次 PR 只改一类**（沿用 [how-to-autofix-cve.md](./how-to-autofix-cve.md) §9.2 的反模式约束）：
  「升 base」和「升依赖」不要混在一个 PR 里，否则出问题无法二分定位。

---

## 4. 三个镜像各怎么做

### 4.1 Argo CD —— 从上游 Dockerfile 到内部 Dockerfile

**上游 `master` 的 Dockerfile 结构（2026-11-17 实测拉取）**：

| Stage | 内容 | 关键点 |
|---|---|---|
| `builder` | `golang:1.27.4`，装 `helm`/`kustomize`/`git-lfs` | 三个 Go 二进制会被塞进最终镜像 |
| `argocd-base` | `ubuntu:26.04`，`apt-get dist-upgrade`，装 `git`/`tini`/`ca-certificates`/`gpg`/`openssh-client` | **OS 包来源**；`dist-upgrade` 破坏可复现性 |
| `argocd-ui` | `node:26.13.1` + corepack + pnpm，产出 `dist/app` | **必须在 `$BUILDPLATFORM` 上构建**（架构无关），否则多架构镜像资产名不一致（上游注释已说明） |
| `argocd-build` | `golang:1.27.4`，`go mod download` → `make argocd-all` | 产出 `dist/argocd*` |
| 最终 | `FROM argocd-base`，`COPY --from=argocd-build .../dist/argocd* /usr/local/bin/`，建 9 个软链接，`USER 999` | 运行时镜像 ≈ **upstream base + 4 个二进制层** |

**七处必要改动**：

| # | 改动 | 为什么 | 风险 |
|---|---|---|---|
| 1 | base 镜像**用 digest pin**（上游已 pin，照抄） | 防止 base 被重推导致镜像不可复现 | 低 |
| 2 | 去掉或替换 `apt-get dist-upgrade -y` | **它是可复现性的破口**：同一个 Dockerfile 今天明天构建结果不同。要么固定 snapshot，要么改成「显式指定要升级的包版本」 | 中（可能与上游有安全补丁差距，需在证据里说明） |
| 3 | builder 镜像 digest pin（Go 版本决定 stdlib CVE） | Go stdlib CVE 只能靠换工具链修 | 低 |
| 4 | **依赖 bump 时同时改两个 module** | `gitops-engine` 是嵌套 module：`replace github.com/argoproj/argo-cd/gitops-engine/v3 => ./gitops-engine` | **高（最常漏）** |
| 5 | 无上游修复时用 `replace` 强制版本 | 上游已有先例：`gopkg.in/yaml.v2 => v2.4.0 // Avoid CVE-2022-3064` | 中（需长期维护，登记 `expiry`） |
| 6 | 前端 CVE 用 `pnpm-workspace.yaml` 的 `overrides` | Argo CD 的 UI 是 pnpm workspace；上游注释明确警告 pnpm 自管版本会破坏 Dependabot/Snyk 对 lockfile 的解析 | 低 |
| 7 | **把 `go.mod` / `go.sum` 拷进最终镜像** | 学 Dex 的做法（上游注释：`Copy module files for CVE scanning / dependency analysis`）—— 让扫描器能解析出 Go 依赖树，而不是只看到一个黑盒二进制 | 极低 |

**内部 Dockerfile 骨架**（结构照抄上游，只改上面 7 处；`ARG` 全部给默认值保证可独立构建）：

```dockerfile
# recipes/argocd/Dockerfile
# 派生自 upstream argoproj/argo-cd @ v3.6.1 的 Dockerfile
# 差异见 recipes/argocd/README.md
ARG BASE_IMAGE=ubuntu:26.04@sha256:2260313b31c8c011cd2eebe725008efac1b3982be73eb71348ea2648d2c0e09b
ARG GO_IMAGE=golang:1.27.4@sha256:08bcb99a38f85a265f9a93d1d3323e2440eec333380f3ea26ee0dec9264bb41c
ARG NODE_IMAGE=node:26.13.1@sha256:e18c3ccdf7d71619990b0e85639f506e2028a95410999cab24cc373cbd10e0ac
ARG ARGOCD_VERSION=v3.6.1
ARG ARGOCD_COMMIT=<upstream commit sha>

# ---------- builder ----------
FROM ${GO_IMAGE} AS builder
WORKDIR /tmp
COPY hack/install.sh hack/tool-versions.sh ./
COPY hack/installers installers
RUN ./install.sh helm && INSTALL_PATH=/usr/local/bin ./install.sh kustomize && ./install.sh git-lfs

# ---------- base ----------
FROM ${BASE_IMAGE} AS argocd-base
LABEL org.opencontainers.image.source="https://github.com/argoproj/argo-cd"
LABEL org.opencontainers.image.version="${ARGOCD_VERSION}"
USER root
ENV ARGOCD_USER_ID=999 DEBIAN_FRONTEND=noninteractive
ARG GIT_APT_VERSION=1:2.53.0-1ubuntu1
# 【改动 2】上游这里是 `apt-get dist-upgrade -y`;我们改为显式列出要升级的包,或直接删掉并靠 §6 的 snapshot 机制
RUN groupadd -g $ARGOCD_USER_ID argocd && \
    useradd -r -u $ARGOCD_USER_ID -g argocd argocd && \
    mkdir -p /home/argocd && chown argocd:0 /home/argocd && chmod g=u /home/argocd && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
        git=${GIT_APT_VERSION} tini ca-certificates gpg gpg-agent tzdata connect-proxy openssh-client && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/*
COPY hack/gpg-wrapper.sh hack/git-verify-wrapper.sh entrypoint.sh /usr/local/bin/
COPY --from=builder /usr/local/bin/helm /usr/local/bin/helm
COPY --from=builder /usr/local/bin/kustomize /usr/local/bin/kustomize
COPY --from=builder /usr/local/bin/git-lfs /usr/local/bin/git-lfs
RUN git lfs install --skip-repo --system && ln -s /usr/local/bin/entrypoint.sh /usr/local/bin/uid_entrypoint.sh
WORKDIR /app/config
RUN mkdir -p tls gpg/source gpg/keys && chown argocd gpg/keys && chmod 0700 gpg/keys
ENV USER=argocd
ENV GRPC_ENABLE_TXT_SERVICE_CONFIG=false

# ---------- UI(必须架构无关) ----------
FROM --platform=$BUILDPLATFORM ${NODE_IMAGE} AS argocd-ui
WORKDIR /src
COPY ["ui/package.json", "ui/pnpm-lock.yaml", "ui/pnpm-workspace.yaml", "./"]
RUN npm install -g corepack@0.34.6 && corepack enable && pnpm install --frozen-lockfile
COPY ["ui/", "."]
ENV ARGO_VERSION=latest
RUN NODE_ENV='production' NODE_ONLINE_ENV='online' NODE_OPTIONS=--max_old_space_size=8192 pnpm build

# ---------- 编译 ----------
FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS argocd-build
WORKDIR /go/src/github.com/argoproj/argo-cd
ARG ARGOCD_COMMIT
COPY go.* ./
RUN mkdir -p gitops-engine
COPY gitops-engine/go.* ./gitops-engine      # 【改动 4】嵌套 module 的依赖要一起下载
RUN go mod download
COPY . .
COPY --from=argocd-ui /src/dist/app /go/src/github.com/argoproj/argo-cd/ui/dist/app
ARG TARGETOS TARGETARCH GIT_TAG BUILD_DATE GIT_TREE_STATE
RUN GIT_COMMIT=$ARGOCD_COMMIT GIT_TREE_STATE=$GIT_TREE_STATE GIT_TAG=$GIT_TAG \
    BUILD_DATE=$BUILD_DATE GOOS=$TARGETOS GOARCH=$TARGETARCH make argocd-all

# ---------- 最终镜像 ----------
FROM argocd-base
ENTRYPOINT ["/usr/bin/tini", "--"]
COPY --from=argocd-build /go/src/github.com/argoproj/argo-cd/dist/argocd* /usr/local/bin/
# 【改动 7】把 module 文件带进镜像,让扫描器能解析 Go 依赖树(Dex 上游同样做法)
COPY --from=argocd-build /go/src/github.com/argoproj/argo-cd/go.mod /go/src/github.com/argoproj/argo-cd/go.sum /usr/local/share/argocd/
USER root
RUN ln -s /usr/local/bin/argocd /usr/local/bin/argocd-server && \
    ln -s /usr/local/bin/argocd /usr/local/bin/argocd-repo-server && \
    ln -s /usr/local/bin/argocd /usr/local/bin/argocd-cmp-server && \
    ln -s /usr/local/bin/argocd /usr/local/bin/argocd-application-controller && \
    ln -s /usr/local/bin/argocd /usr/local/bin/argocd-dex && \
    ln -s /usr/local/bin/argocd /usr/local/bin/argocd-notifications && \
    ln -s /usr/local/bin/argocd /usr/local/bin/argocd-applicationset-controller && \
    ln -s /usr/local/bin/argocd /usr/local/bin/argocd-k8s-auth && \
    ln -s /usr/local/bin/argocd /usr/local/bin/argocd-commit-server
USER $ARGOCD_USER_ID
```

**必须保留不能动的三样东西**（动了就会出诡异问题）：

1. **`ENTRYPOINT ["/usr/bin/tini", "--"]`** —— tini 负责 PID 1 信号转发与僵尸回收，去掉后 Argo CD 滚动更新时会卡住；
2. **`USER 999`（argocd）** —— 非 root 是安全基线要求，也是准入策略的检查项；
3. **9 个软链接** —— Helm chart / Kustomize 里用的是 `argocd-server`、`argocd-repo-server` 这些名字，缺一个就起不来。

### 4.2 Dex —— 同构，但 CGO 是关键差异

上游 Dockerfile 结构（实测）：`xx` 跨编译 → `golang:1.27.4-alpine3.24` 构建（`CGO_ENABLED=1`）→ `alpine:3.24.4` 运行时 → 从 distroless 拷 CA 证书 → `USER dex:dex`(1001)。

| 要点 | 说明 |
|---|---|
| **`CGO_ENABLED=1`** | dex 二进制**动态链接 musl**。这意味着 alpine 的 libc/openlsa 类 CVE **会真的影响 dex**，不能按「Go 静态链接」那套逻辑当噪声处理。 |
| 跨编译要用 `xx` | 不能简单 `GOOS/GOARCH` 交叉编译（需要 cgo 时必须用 `xx-clang`） |
| `git-lfs` / `gomplate` | dex 镜像里还塞了 `gomplate`（模板渲染）和其他工具，每个都是独立 Go 二进制，也是 CVE 来源 |
| 改造方式与 Argo CD 完全同构 | 抄上游 Dockerfile → 改 base digest → bump `go.mod` → 加 `replace` → 拷 `go.mod/go.sum` 进镜像 |

> 现有 [how-to-fix-dex-base-image.md](./how-to-fix-dex-base-image.md) 已经把「换 base」这条路径走完了（alpine 3.21 EOL → 3.24）。
> 本文补充的是**「从源码重建 Dex」这条路径**，用于 alpine 本身没有修复版本、或某个 Go 依赖必须 bump 的场景。

### 4.3 Redis —— 为什么它应该走另一条路

官方镜像的构建方式：`alpine` 里下载 `redis-7.2.13.tar.gz` → 编译 → **用 `sed` 给 jemalloc 打补丁** → 装运行时依赖 → 删掉构建依赖。

这意味着「重建 Redis 镜像」= **重编译 C 代码 + 复刻上游的 jemalloc sed patch**，成本高、脆弱、且几乎必然与上游漂移。

| 路线 | 做法 | 评价 |
|---|---|---|
| **R1. 升官方 tag（推荐）** | 用更新的 `redis:7.x-alpine` 官方 tag 重新 relocate | 官方自己会 bump alpine 与 patch CVE，**我们零维护**。先查我们当前用的 tag 是不是已经 EOL/有 CVE |
| **R2. 换托管服务（HA 场景最优）** | Argo CD HA 的缓存/通知队列直接用 **GCP Memorystore for Redis**，删掉 redis 这一段 Deployment | 镜像问题**从根上消失**，还省一套 HA 运维。值得优先评估 |
| **R3. 自建 base + 复用官方二进制层** | `FROM alpine:3.24` + `COPY --from=redis:7.2-alpine /usr/local/bin/redis-server ...` | 只换 OS 层，不重编译。**比 R1 更可控，但需要自己承担 redis 上游 CVE** |
| **R4. 从源码重建** | 复刻官方 Dockerfile | ❌ 不推荐：成本最高、收益最低 |

> **决策建议**：先跑一次 §5.1 的定位，确认 redis 到底报了什么。
> 如果只是 alpine 包过期 → 走 R1（当天能上）。
> 如果是 redis 自身 CVE → 优先 R2，其次 R3。
> **无论哪条，先确认我们真的需要自建 redis**（Argo CD 非 HA 部署通常可以不带 redis）。

---

## 5. CWE 来了怎么办 —— 一小时 SOP

### 5.1 Step 0：定位（5 分钟）

```bash
# 1) 在 Artifact Analysis 里查这个 digest 的扫描结果
gcloud artifacts docker images list-vulnerabilities \
  us-east4-docker.pkg.dev/projectID-capus-prod/containers/argocd@sha256:<digest> \
  --location=us-east4 --format=json > /tmp/findings.json

# 2) 或本地用 Trivy 快速看（迭代用）
trivy image --severity HIGH,CRITICAL \
  us-east4-docker.pkg.dev/projectID-capus-prod/containers/argocd@sha256:<digest>

# 3) 拉下来看层、base、当前嵌入的 Go 依赖版本
docker pull --platform linux/amd64 \
  us-east4-docker.pkg.dev/projectID-capus-prod/containers/argocd@sha256:<digest>
docker inspect --format '{{json .RootFS.Layers}}' \
  us-east4-docker.pkg.dev/projectID-capus-prod/containers/argocd@sha256:<digest>
```

**第一件事永远是「归因」，不是「修复」**。同一个 CVE ID，在不同层，修法完全不同。

### 5.2 Step 1：归因（五分类判定表）

| 类别 | 特征 | 判定命令 | 修法归属 |
|---|---|---|---|
| **① OS / base 包** | 扫描结果 `Target` 是 `ubuntu`/`alpine` 的包名 | `trivy ... \| grep -i ubuntu`；或看 `image basis` | 换 base / 卸包（见 [how-to-fix-cve-with-base-image-constraints.md](./how-to-fix-cve-with-base-image-constraints.md)） |
| **② Go stdlib** | CVE 指向 Go 本身（`net/http`、`crypto/tls`、`archive/zip`…） | `go version -m <binary>` 看 `go1.x.x`；或 `govulncheck` | **升 Go 工具链**（builder 镜像 digest） |
| **③ Go 第三方 module** | CVE 指向具体 module（如 `golang.org/x/crypto`） | `go version -m /usr/local/bin/argocd`（读 `dep` 段） | **bump `go.mod` / 加 `replace`** |
| **④ 前端 npm/pnpm** | CVE 指向 npm 包 | `pnpm audit`；SBOM 里的 npm 段 | `pnpm-workspace.yaml` 的 `overrides` |
| **⑤ 镜像配置类 violation（不是 CVE）** | 「以 root 运行」「缺 HEALTHCHECK」「用了 latest tag」「无 SBOM」 | 检查 Dockerfile / 准入策略 | 改 Dockerfile（`USER`、加 `HEALTHCHECK`、digest pin） |

**Go 二进制依赖版本怎么读（最有用的一条命令）**：

```bash
# 在容器里读嵌入的 module 列表(不需要源码!)
docker run --rm --entrypoint=go <image> version -m /usr/local/bin/argocd 2>/dev/null \
  || docker run --rm --entrypoint=/usr/local/bin/argocd <image> version -m /usr/local/bin/argocd
```

输出里 `dep` 段就是**这个二进制实际编进去的依赖版本** —— 这是「我们的镜像到底有没有这个 CVE」的第一手证据，
比看扫描器结论更可靠（扫描器可能因为拿不到 module 信息而误判）。

**可达性分析（降误报的关键）**：Go 静态二进制可以用 `govulncheck` 做符号级可达性判断，
很多「module 有漏洞」在 Argo CD 里**根本没被调用**。这类应走 VEX/豁免而不是硬修
（豁免必须带到期时间，见 [how-to-autofix-cve.md](./how-to-autofix-cve.md) §4.4）。

### 5.3 Step 2：决策树

| 上游有修复版本吗 | 能自己打补丁吗 | 走哪条 | 成本 |
|---|---|---|---|
| ✅ 有，且已发布新版 | — | **升上游版本**（`argocd` → v3.6.x 最新 patch）→ 重建 | 最低，**首选** |
| ✅ 有，但只在 master | — | 回到上游仓库确认 patch 是否已 backport；没有就等 | 低 |
| ❌ 无修复 | ✅ 模块是开源的 | **`vendor` + 打 patch**（`patches/*.patch`），或用 `replace` 指向我们自己的 fork | 中，需登记 `expiry` 与 `upstream_target` |
| ❌ 无修复 | ❌ 闭源 | **换 base / 卸包 / VEX 豁免** | 低 |
| — | — | 判定为**误报或不可达** | 走 VEX，带到期时间 |

### 5.4 Step 3：动手（每类改哪一行）

| 类别 | 改哪里 | 具体动作 |
|---|---|---|
| ① OS 包 | `recipes/<asset>/Dockerfile` 的 base 段 | 换 `BASE_IMAGE` digest；或卸掉不需要的包（如不用 gpg 就卸 `gpg`） |
| ② Go stdlib | `lock/*.lock.yaml` 的 `builder` | 换 builder 镜像 digest 到更新的 Go；同步 `toolchain` |
| ③ Go module | 源码仓的 `go.mod` / `go.sum`（**上游 fork**） | `go get <mod>@<fixed> && go mod tidy`；**同时改 `gitops-engine/go.mod`** |
| ③ 无修复 | `go.mod` 加 `replace` | 例：`replace gopkg.in/yaml.v2 => gopkg.in/yaml.v2 v2.4.0`（上游先例） |
| ④ 前端 | `ui/pnpm-workspace.yaml` | 加 `overrides:`；跑 `pnpm install` 后更新 lockfile |
| ⑤ 配置 violation | `recipes/<asset>/Dockerfile` | 加 `USER`、加 `HEALTHCHECK`、所有 `FROM` 用 digest |

### 5.5 Step 4：重建 → 扫描 → 差分

**这一步的完整契约（差分必须是同 DB 同批次、必须加运行时冒烟、出口码确定）见
[how-to-autofix-cve.md](./how-to-autofix-cve.md) 第 4 章**，此处只给最短路径：

```bash
# 1) 构建(多架构,节点架构对齐)
docker buildx build --platform linux/amd64,linux/arm64 \
  -f recipes/argocd/Dockerfile \
  -t us-east4-docker.pkg.dev/projectID-capus-prod/containers/argocd:3.6.1-internal-1 \
  --push .

# 2) 拿到新 digest(后面所有步骤都绑这个 digest)
DIGEST=$(gcloud artifacts docker images describe \
  us-east4-docker.pkg.dev/projectID-capus-prod/containers/argocd:3.6.1-internal-1 \
  --location=us-east4 --format='value(image_summary.digest)')

# 3) baseline 与 candidate 用同一批 DB 扫
gcloud artifacts docker images scan <old-digest> --location=us-east4 --format=json
gcloud artifacts docker images scan <new-digest> --location=us-east4 --format=json
# 用完全限定资源名取报告:
#   projects/<P>/locations/us-east4/operations/<ID>

# 4) 差分 + 运行时冒烟(见验证契约 §4.1/§4.2)
```

### 5.6 Step 5：晋级 digest + 灰度 + 回滚

```bash
# 晋级:更新 assets/argocd.yaml 的 digest 与 state.yaml,合 main
# 灰度:先改一个副本(Argo CD 的 server/repo-server 分开灰度)
kubectl -n argocd set image deployment/argocd-server argocd=<new-digest>
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s

# 回滚:把 digest 改回旧值即可(旧 digest 的镜像必须还没被 GC)
kubectl -n argocd set image deployment/argocd-server argocd=<old-digest>
```

> **部署侧铁律**：Kustomize / Helm 里引用镜像**一律写 digest**，不写 tag。
> tag 是给人看的，digest 才是身份。（配合 Binary Authorization 做准入，见 §7。）

---

## 6. 可复现性的三个破口

| 破口 | 出处 | 后果 | 对策 |
|---|---|---|---|
| **`apt-get dist-upgrade -y`** | Argo CD `argocd-base` 阶段 | 同一份 Dockerfile 今天明天构建结果不同 → **digest 不可复现** | 换成固定 snapshot 源，或显式列出要升级的包版本，并在证据里记录当时的包版本 |
| **`:latest` 隐式引用** | 任何未 pin 的 `FROM` | base 漂移，CVE 突然出现或突然消失 | 所有 `FROM` 一律 `@sha256:`（上游已做，我们要保持） |
| **UI 与架构耦合** | Argo CD `argocd-ui` 阶段 | 若在目标架构上构建 UI，多架构镜像的 asset 文件名会不一致，集群里不同节点返回不同 hash → 前端 404 | UI 阶段必须 `--platform=$BUILDPLATFORM`（上游注释已明确说明），**这条不能改** |

补充：`ui/pnpm-workspace.yaml` 的 `overrides` 与 pnpm 自管版本会破坏 lockfile 解析（上游注释已警告），
我们加 override 时要用固定 pnpm 版本（`corepack` + `packageManager` 字段锁定）。

---

## 7. 证据链与准入

| 环节 | 做什么 | 工具 |
|---|---|---|
| **SBOM** | 每个 digest 对应一份 SPDX/CycloneDX | 上游 Argo CD 用 `spdx-sbom-generator` + `sigs.k8s.io/bom` 生成 SPDX —— **我们的重建镜像必须复刻这一步**，否则准入拿不到 SBOM |
| **Provenance** | SLSA3 溯源（构建来源可追） | 上游用 `slsa-framework/slsa-github-generator`；我们内部 CI 需要等价的产出（可用 `slsa-github-generator` 或 `cosign attest`） |
| **签名** | 镜像签名 | `cosign sign` / KMS；配合 GAR 的 Artifact Analysis |
| **准入** | 只允许「已验证 digest」进 GKE | GCP **Binary Authorization**，按 digest 白名单 + 证明（attestation）策略 |
| **防复发** | 每次重建自动触发扫描 + 差分 | 流水线：build → push → scan → diff → 出证据 → 等人工晋级 |
| **台账** | 状态与豁免 | `state.yaml` + SCC（Security Command Center） |

> **注意上游的一个能力**：Argo CD 官方支持 **fork release**（仓库变量 `ENABLE_FORK_RELEASES=true` +
> `IMAGE_NAMESPACE` / `IMAGE_REPOSITORY`），可以用官方流水线直接产出**我们自己命名空间**的镜像，
> 并自动带 SLSA provenance + SPDX SBOM。
> **如果公司允许在 GitHub 上跑 CI，这比自己搭内部流水线省事得多**；
> 如果不允许（见 [how-to-maintain-upstream-images.md](./how-to-maintain-upstream-images.md) 的假设），
> 就在内部 CI 复刻同样的产出（build → push GAR → scan → diff → 人工审批）。

---

## 8. 落地路线

| Phase | 内容 | 产出 | 工作量 |
|---|---|---|---|
| **Phase 0** 现状盘点 | ① 确认 argocd/dex/redis 三个镜像**当前实际版本与 digest** ② 确认哪些真的在用（dex？redis？）③ 对三个 digest 跑一次扫描，拿到 CVE 清单 ④ 确认哪些 finding 来自 base、哪些来自 Go 依赖 | 一张 CVE 清单 + 一份「谁在用」结论 | 0.5 天 |
| **Phase 1** 只做 relocate | **不重建**，把现有 digest 原样推到 GAR，Helm/Kustomize 改指内部地址 | 内部可用的镜像仓库 | 0.5 天 |
| **Phase 2** 重建 Argo CD | 抄上游 Dockerfile → 改 7 处 → buildx 多架构构建 → 扫描 → 差分 → 冒烟 → 晋级 | `recipes/argocd/Dockerfile` + 一个通过验证的 digest | 2–3 天 |
| **Phase 3** 建立流水线 | build → push GAR → 触发 Artifact Analysis → 取报告 → 差分 → 人工审批 → 回写 `state.yaml` | 流水线 + 证据归档 | 3–5 天 |
| **Phase 4** 铺开 | Dex 走同构路径；Redis 按 §4.3 决策；其余资产按 [how-to-maintain-upstream-images.md](./how-to-maintain-upstream-images.md) 接入 | 全量资产在册 | 视资产数 |

> **建议**：Phase 1 一定要先做完。**relocate 和重建是两件事**，
> 先让内部仓库能用了，再谈「自己能修 CVE」——否则 Phase 2 一旦卡住，业务侧连镜像都拉不到。

---

## 9. 待确认清单

| # | 待确认 | 为什么重要 | 怎么查 |
|---|---|---|---|
| 1 | **我们到底启用了 Dex 吗？** | 决定 Dex 是否值得进重建流程 | `kubectl -n argocd get cm argocd-cm -o yaml \| grep -i dex`；Helm values 里的 `sso.provider` |
| 2 | **我们用自建 Redis 还是托管？** | 决定要不要重建 Redis | `kubectl -n argocd get sts`；Helm values 的 `redis.enabled` |
| 3 | 内部 GAR 仓库是否已有 `argocd` / `dex` / `redis` 三个路径？tag 规范是什么？ | 决定 `assets/*.yaml` 的写法 | `gcloud artifacts repositories list --location=us-east4` |
| 4 | Argo CD 内部实际部署版本（v3.6.1？还是别的） | 决定从哪个上游 tag 抄 Dockerfile | `kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}'` |
| 5 | 公司是否允许在 GitHub 上跑 CI（决定用不用上游 fork release） | 决定流水线形态 | 安全/合规确认 |
| 6 | 内网 base 镜像源（是否有 snapshot 源） | 决定 §6 的破口怎么补 | 基础设施确认 |
| 7 | 准入策略是否已启用 Binary Authorization | 决定 §7 能否闭环 | `gcloud artifacts docker images list --project=...` |

---

## 附录 A —— 关键命令速查

```bash
# ---------- 定位 ----------
gcloud artifacts docker images list-vulnerabilities <repo>@<digest> --location=us-east4 --format=json
trivy image --severity HIGH,CRITICAL <repo>@<digest>
docker inspect --format '{{json .RootFS.Layers}}' <repo>@<digest>

# ---------- 读 Go 二进制的依赖版本(判断"我们到底有没有这个 CVE") ----------
go version -m <image>:/usr/local/bin/argocd        # 需要镜像里有 go,否则 docker cp 出来本地读
go version -m ./argocd                              # 本地读法

# ---------- 构建 ----------
docker buildx build --platform linux/amd64,linux/arm64 \
  -f recipes/argocd/Dockerfile -t <repo>:3.6.1-internal-1 --push .

# ---------- 扫描与差分 ----------
gcloud artifacts docker images scan <repo>@<digest> --location=us-east4 --format=json
gcloud artifacts docker images list-vulnerabilities <repo>@<digest> --location=us-east4

# ---------- 依赖 bump(在 fork 源码仓里) ----------
go get golang.org/x/crypto@v0.58.1 && go mod tidy
(cd gitops-engine && go get golang.org/x/net@<fixed> && go mod tidy)   # 别忘了嵌套 module

# ---------- 部署 ----------
kubectl -n argocd set image deployment/argocd-server argocd=<repo>@<digest>
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
```

## 附录 B —— 参考

- 上游 Argo CD Dockerfile：<https://raw.githubusercontent.com/argoproj/argo-cd/master/Dockerfile>
- 上游 Argo CD 发布流水线（fork release / SBOM / SLSA）：<https://raw.githubusercontent.com/argoproj/argo-cd/master/.github/workflows/release.yaml>
- 上游 Argo CD `go.mod`（v3.6.1，含 `replace` 躲 CVE 的先例）：<https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/go.mod>
- 上游 Dex Dockerfile：<https://raw.githubusercontent.com/dexidp/dex/master/Dockerfile>
- 上游 Redis Dockerfile：<https://raw.githubusercontent.com/docker-library/redis/master/7.2/alpine/Dockerfile>
- `imgutil`（CNB 镜像操作层）：<https://github.com/buildpacks/imgutil>
- CNB 规范：<https://buildpacks.io>
