# GCP 上自动修复 CVE / Violation —— 可行性探索与方案设计

> 探索日期：2026-11-05
> 目标读者：平台/安全工程团队
>
> **本目录的三份文档怎么配合看：**
>
> | 文档 | 回答什么问题 |
> |---|---|
> | **本文（how-to-autofix-cve.md）** | 总体方案：怎么把「检测 → 修复 → 验证」做成一个可信的闭环？验证契约怎么定？AI 该做什么、不该做什么？ |
> | **[how-to-use-dependabot.md](./how-to-use-dependabot.md)** | 依赖层怎么自动化：Dependabot 装不装、怎么配、怎么和你们的 GAR/Artifact Analysis 闭环接起来（**含完整 CI 链**） |
> | **[how-to-fix-dex-base-image.md](./how-to-fix-dex-base-image.md)** | 具体 case 的可执行 runbook：dex 的 alpine 3.21 EOL 到底怎么修（Phase 0–4、验证、回滚、防复发） |
>
> 关联：[cve-cwe.md](./cve-cwe.md)（CVE 与 CWE 的分工）、[../how-to-fix-violation/](../how-to-fix-violation/)（已有的检测工具与 CI 集成资料）
>
> 本文只做**方案**（流程 + 架构 + 工具选型 + 验证契约），**不含可执行脚本**。所有 gcloud 命令均在本机 `gcloud 526.0.1` 上验证过命令与参数存在性；标注「需实测」的表示效果需在你们项目里跑一次确认。

---

## 0. TL;DR

**结论：可行，但要把"AI 修 CVE"这件事拆成两个完全不同的能力。**

| 能力 | 谁来做 | 可自动化程度 |
|---|---|---|
| **判断哪里错了、该改成什么** | LLM / Agent | 高 —— 这是 AI 真正的价值所在 |
| **真的把文件改掉、把镜像构建出来、把漏洞验掉** | 确定性脚本 + 云上流水线 | 高 —— 纯机械操作，不需要 AI |

所以正确的形态不是"让 AI 去修漏洞"，而是：

> **让 AI 当 triager 和 planner，让脚本当唯一的写入者，让 GAR 的扫描结果当唯一的裁判。**

三句话讲完整闭环：

1. **检测**：Artifact Analysis（GAR 自带漏洞扫描）给出漏洞清单，SCC 汇总成台账。
2. **修复**：Agent 读 finding → 定位到 Dockerfile / `go.mod` / `pom.xml` 的具体行 → 生成修复补丁（**只在分支上改**）。
3. **验证**：改完 → 构建 → 推 GAR（staging tag）→ **重新调 Artifact Analysis 扫这个新 digest** → 与基线做差分 → 只有差分满足契约才算"修好了" → 才开 PR / 才允许进生产。

最关键的一条设计原则（下面第 4 章展开）：

> **"修复成功"的判据必须是云上扫描器的输出，不能是本地扫描，也不能是 AI 的判断。**
> 如果扫描器没跑完、DB 降级了、覆盖不全 —— 一律算"未验证"，不许报绿。

---

## 1. 先把 "violation" 拆开：不同类型，修法完全不同

这是整个方案的起点。你们遇到的 `os(alpine) 3.21 support end of life` 和 Java/Go 应用里的 CVE，**根因层级不同、修复动作不同、风险等级不同**，混在一起做自动化是错的。

| # | 类型 | 典型形态 | 根因在哪 | 修复动作 | 自动化风险 | 建议自动化级别 |
|---|---|---|---|---|---|---|
| **T1** | **OS 生命周期 / Base image EOL** | `os(alpine) version (3.21) support end of life on 2026-11-01` | `Dockerfile` 的 `FROM` | 升 base 镜像 tag（+ 重建） | **低**（升 patch/次版本） | 🟢 全自动（测试通过即合并） |
| **T2** | **OS 包 CVE**（base image 内的包） | `CVE-xxxx in openssl 3.x` | base image 内已装的包 | base 镜像升级 **或** 构建时 `apk upgrade` | 低–中 | 🟢 自动出 PR |
| **T3** | **语言依赖 CVE**（Go modules / Maven / npm） | `CVE-xxxx in golang.org/x/net vX` | `go.mod` / `go.sum` / `pom.xml` | 升依赖版本 | **中**（可能有 API 破坏） | 🟡 自动出 PR + 人工评审 |
| **T4** | **运行时 / stdlib CVE** | Go stdlib CVE、JRE CVE | Go toolchain / JRE base image | `toolchain` 指令 / 升 JRE | 中–高 | 🟡 自动出 PR + 人工评审 |
| **T5** | **应用代码缺陷（CWE）** | 不安全反序列化、路径穿越 | 业务源码 | 改代码 | **高** | 🔴 只出建议，不自动合并 |

**这张表对应 `cve-cwe.md` 的核心结论**：台账用 CVE，根因治理用 CWE。T1–T4 是 **SCA（成分分析）** 领域，可以高度自动化；T5 是 **SAST/代码审计** 领域，必须人工把关。

### 1.1 一个必须先澄清的点：T1 不是 CVE

`alpine 3.21 support end of life on 2026-11-01` **没有 CVE 编号，也就没有 "fixed version"**。它是**生命周期（lifecycle）问题**：

- Alpine 3.21 的最后补丁是 `3.21.9`，EOL 后官方不再出补丁 → **在这个版本上再怎么 `apk upgrade` 也修不掉**；
- 唯一的修法是**换 base 镜像的大版本**（3.21 → 3.22/3.23/3.24）；
- 而"什么时候该换"这件事，**是日历驱动的，不是漏洞驱动的** → 所以它天然适合用自动化守护（Dependabot / Renovate / 定期巡检），而不是等扫描器报出来再修。

Alpine 支持周期实测数据（`endoflife.date/api/alpine-linux.json`，2026-11-05 取）：

| Alpine | EOL 日期 | 最新 patch |
|---|---|---|
| 3.21 | **2026-11-01（4 天前）** | 3.21.9 |
| 3.22 | 2027-05-01 | 3.22.7 |
| 3.23 | 2027-11-01 | 3.23.7 |
| 3.24 | **2028-06-01** | 3.24.3 |

> 你们这个 dex 镜像的 EOL 日期 `2026-11-01 00:00:00+00` 与 Alpine 官方 EOL 表**完全吻合**，可以确认就是 Alpine 3.21 生命周期检查。

### 1.2 另一个必须澄清的点：谁拥有这个 Dockerfile

| 情况 | 能不能自动修 | 说明 |
|---|---|---|
| 镜像有**你们自己的 Dockerfile**（自有服务） | ✅ 能 | Agent 直接改 `FROM` 行 |
| 镜像是**第三方上游**（如 `dexidp/dex`），你们只是 build 了一份推到自己 GAR | ⚠️ 间接 | 不能改上游，但可以**用上游源码 + 你们的 Dockerfile 重建** |
| 镜像是**纯上游拉取**（直接 pull 到 GAR） | ❌ 不能 | 只能：换上游版本 / 换变体 / 迁移到自建 |

你给的例子属于第二种：**dex 上游的 Dockerfile 里 `ARG BASE_IMAGE=alpine`，而且同时提供 `alpine` 和 `distroless` 两个 variant**（见 §5.1 实测）—— 这意味着"升 base"这件事在 dex 上是完全可行的，而且**连 OS 包都能一起消掉**（distroless 变体几乎没有 OS 包）。

---

## 2. GCP 原生能力盘点：闭环需要什么，你已经有什么

修复闭环对平台能力有 5 个硬性要求。GCP 原生能力**全部覆盖**，这是本方案可行的最大前提。

| 环节 | 需要的能力 | GCP 原生实现 | 验证状态 |
|---|---|---|---|
| **① 检测** | 扫镜像，找 OS 包 + 语言依赖漏洞 | **Artifact Analysis**（GAR 内建） | ✅ 命令已验证 |
| | 漏洞台账 / 优先级 / 影响面 | **Security Command Center** | ✅ 命令已验证 |
| | SBOM（溯源、license、影响面分析） | Artifact Analysis SBOM | ✅ API 已验证 |
| **② 构建** | 产出新镜像 | **Cloud Build** / 本地 `docker buildx` | ✅ |
| **③ 推送** | 推到受控仓库 | **Artifact Registry** | ✅ |
| **④ 验证** | 对**新镜像**重新扫描并做差分 | **Artifact Analysis on-demand scanning** | ✅ 关键能力 |
| **⑤ 门禁** | 阻止有漏洞的镜像进生产 | **Binary Authorization**（含 continuous validation） | ✅ 命令已验证 |

### 2.1 Artifact Analysis —— 本方案的核心依赖

GAR 内建的漏洞扫描（Artifact Analysis），**这是"推上去就能拿到 violation 报告"的那条路**。

**按需扫描（on-demand scanning）—— 我们要用的就是它：**

```bash
# 扫 GAR 里的镜像（--remote 表示镜像在远端仓库）
gcloud artifacts docker images scan \
  europe-west2-docker.pkg.dev/myproject/containers/dex@sha256:23f4f869... \
  --remote --location=europe

# 异步模式：立刻返回，后续轮询
gcloud artifacts docker images scan <IMAGE> --remote --location=europe --async

# 轮询扫描操作是否完成
gcloud artifacts docker images get-operation <OPERATION_NAME>

# 列出这次扫描发现的漏洞
gcloud artifacts docker images list-vulnerabilities \
  projects/myproject/locations/europe/scans/<SCAN_ID>
```

**已验证的关键事实：**

- `--location` 取值为 `asia` / `europe` / `us` —— 你们镜像在 `europe-west2`，**用 `--location=europe`**；
- **扫描的 package type 包含 `GO` / `MAVEN` / `NPM` / `PYTHON` / `RUST` 等语言依赖**，也就是说 **Artifact Analysis 本身就能覆盖你们的 Go 和 Java 依赖 CVE**，不一定要引入第三方扫描器；
- 支持扫**本地镜像**（不加 `--remote`），本地迭代阶段很方便；
- `--skip-package-types` 可跳过某类包（提速用）。

**已扫描镜像的直接查询：**

```bash
gcloud artifacts docker images describe <IMAGE@sha256:...> \
  --show-package-vulnerability \
  --show-sbom-references \
  --show-provenance
```

**开启漏洞扫描（在仓库级别）：**

```bash
gcloud artifacts repositories update myproject/containers --allow-vulnerability-scanning
```

> ⚠️ **需实测**：本机 SDK 526.0.1 的 `gcloud artifacts repositories update` 只暴露了 `--allow-vulnerability-scanning`，
> **没有** 连续扫描（push 时自动扫）和 SBOM 生成的对应 flag。
> 这两项通常在 **Console → Artifact Registry → 仓库 → 设置** 里开关，或走 Container Analysis API
> （`containeranalysis.googleapis.com/v1beta1/projects/*/locations/*/repositories`）。
> 建议动作：先在 Console 确认你们仓库现在这三项的开关状态，这是 Phase 0 的第一件事。

**底层 API（做自动化时用）：**

```
projects.locations.occurrences.list          # 按 kind 过滤取漏洞/包/部署记录
projects.locations.occurrences.getVulnerabilitySummary
projects.locations.resources.exportSBOM
projects.locations.resources.generatePackagesSummary
```

### 2.2 Security Command Center —— 台账与影响面

```bash
gcloud scc findings list --project=myproject \
  --filter='state="ACTIVE" AND category="CONTAINER_VULNERABILITY"' \
  --format=json
```

SCC 的价值不在"扫描"（那是 Artifact Analysis 的活），而在：

- **台账**：一条 finding 对应一个资源 + 一个漏洞，可以挂到 GKE 工作负载上；
- **影响面**：知道哪个 GKE Deployment / Pod 正在跑这个有问题的镜像 → 决定优先级；
- **状态流转**：修复后 finding 应该自动关闭 —— 这是"闭环"的客观证据。

### 2.3 Binary Authorization —— 防回归

修完之后，如果不加门禁，下一个 base image EOL 会再来一次。两个层次：

- **准入策略（Admission Policy）**：没通过 attestation 的镜像不许进集群；
- **Continuous Validation**：周期性检查集群里正在跑的镜像是否出现新漏洞 → **发现即拦截**。

```bash
gcloud container binauthz attestors list
gcloud container binauthz policy get <POLICY> --format=json
```

> ⚠️ 需要确认你们是否已启用，以及是否用了 Kritis / cosign attestation 链路。**这是 Phase 5 的事**，但架构上要先留好位置。

### 2.4 一张图：闭环涉及的所有 GCP 组件

```
                    ┌──────────────────────────────┐
                    │  Artifact Analysis (GAR)     │
                    │  ├ on-demand scan            │
                    │  ├ continuous scanning       │
                    │  └ SBOM                      │
                    └───────┬──────────────┬───────┘
                            │ findings     │ scan 结果
                            ▼              ▲
   ┌────────────┐   ┌──────────────┐  ┌───┴──────────────┐
   │ SCC 台账    │──▶│  Agent 编排   │  │ 差分 & 门禁判定   │
   │ (优先级)   │   │ (plan only)  │──▶│ (确定性脚本)     │
   └────────────┘   └──────┬───────┘  └──────────────────┘
                           │ 补丁
                           ▼
                    ┌──────────────┐
                    │ 源码仓库      │  Dockerfile / go.mod / pom.xml
                    │ (分支上改)    │
                    └──────┬───────┘
                           │ build
                           ▼
   ┌────────────────────────────────────────────┐
   │ Cloud Build / docker buildx              │
   └──────────────────┬─────────────────────────┘
                      │ push → GAR (staging tag)
                      ▼
              ┌───────────────────┐
              │  新 digest         │
              └─────────┬─────────┘
                        │ 重新扫描（同一 DB / 同一时段）
                        └──────────▶ 回到 Artifact Analysis
```

---

## 3. 总体架构：Agent 驱动的修复闭环

### 3.1 角色分工（最重要的一张表）

| 角色 | 职责 | **能不能改东西** |
|---|---|---|
| **Scanner**（Artifact Analysis / Trivy / Grype） | 提供事实：哪个包、哪个版本、哪个 CVE、有没有修复版本 | ❌ 只读 |
| **Policy Engine**（确定性规则） | 分类 T1–T5、决定自动化级别、设门禁阈值 | ❌ 只读 |
| **Planner**（LLM/Agent） | 读 finding + 读源码 → 判断"改哪个文件的哪一行"、评估破坏性、写 PR 描述 | ❌ **只读**（只产出计划） |
| **Executor**（确定性脚本） | 唯一有写权限的角色：应用补丁、构建、推送、扫描、差分 | ✅ **唯一写入权** |
| **Judge**（差分器） | 比较 baseline vs candidate 扫描结果 → 通过/不通过 | ❌ 只读，但**是裁判** |
| **Human** | T3/T4/T5 的最终审批、T1 之外的风险决策 | ✅ |

> **为什么要这么分**：AI 会"自信地说修好了"，但它没有能力验证一个 CVE 在新镜像里真的消失了。让 AI 同时当运动员和裁判是这个方案最容易失败的地方。**裁判必须是扫描器。**

### 3.2 状态机

```
DISCOVER ──▶ TRIAGE ──▶ PLAN ──▶ PATCH ──▶ BUILD ──▶ PUSH ──▶ SCAN ──▶ DIFF ──▶ VERIFY
    │           │         │        │         │        │       │        │        │
    │           │         │        │         │        │       │        │        ├─▶ ✅ PR（verified）
    │           │         │        │         │        │       │        │        │      → 人工评审 → 合并 → 部署
    │           │         │        │         │        │       │        │        └─▶ ⚠️ PARTIAL（部分修复 / 需人工）
    │           │         │        │         │        │       │        └─▶ ❌ REGRESSION（引入新漏洞）→ 自动回滚
    │           │         │        │         │        │       └─▶ ❌ SCAN_FAILED（扫描失败/超时）→ 未验证
    │           │         │        │         │        └─▶ ❌ BUILD_FAILED → 换版本重试 / 升级人工
    │           │         │        │         └─▶ ❌ PATCH_FAILED → 人工
    │           │         │        └─▶ 🔴 T5 → 人工
    │           │         └─▶ 策略拒绝（无修复版本 / 风险过高）→ 人工
    │           └─▶ 无对应源码 / 无法定位 → 人工
    └─▶ 无扫描器 → 人工
```

### 3.3 两条硬性规则（所有实现的共同约束）

**规则 A：Fail-closed（覆盖率不可信时一律判不通过）**

借鉴 `submariner-io/shipyard` 的 sentinel 文件模式，它做得非常对，值得直接抄：

```
build-failed      → 构建失败，扫描只覆盖了源码，stdlib CVE 看不见 → 不得报 clean
network-broken    → 扫描器 DB 下载失败（DNS/代理）→ 结果不可信 → 不得报 clean
scanner-degraded  → 用了陈旧 DB → 不得报 clean
coverage-unknown  → 二进制被 UPX 压缩 / 非 release 编译 → stdlib 覆盖不全 → 不得报 clean
scan-transient    → 扫描器自身网络错误 → 结果不可信 → 不得报 clean
```

**规则 B：Verify-then-Promote（同 digest）**

> **被验证的镜像，必须就是最终上生产的那个镜像（同一个 digest）。**

这条极容易被违反，典型翻车方式：

1. Agent 在本地 `docker build` 验证 ✅
2. 合并 PR → Cloud Build 重新构建 → 产出**另一个 digest**（base image 解析时间、构建时间戳、buildx 版本都可能不同）
3. 部署了新 digest，但**验证的是另一个 artifact**

**正确做法**：只构建一次（CI 里构建 → 推 GAR → 扫这个 digest → 差分通过 → 提升这个 digest 到 release tag / 让 K8s 用这个 digest）。**验证过的 digest 就是被部署的 digest。**

---

## 4. 验证契约（整个方案的核心）

这一章是"方案可行"与"方案不可行"的分界线。**如果验证契约设计错了，后面全是自动化幻觉。**

### 4.1 差分必须是"同 DB、同批次"的对齐比较

朴素做法是"扫描新镜像 → 看目标 CVE 还在不在"。**这个做法有漏洞**：

- 扫描间隔几十分钟，DB 里可能新增了别的 CVE → 误判"引入新漏洞"；
- 或者 DB 降级/延迟 → 误判"已修复"。

**正确做法：baseline 和 candidate 在同一次运行里、用同一个扫描器、同一份 DB 扫两次。**

```
baseline  = 当前线上 digest（旧镜像）→ scan
candidate = 新构建的 digest（新镜像）  → scan
diff      = compare(baseline, candidate)
```

差分的三条判定（全部满足才算 VERIFIED）：

| # | 判定 | 说明 |
|---|---|---|
| **D1** | **目标命中消失** | 本次要修的那条 finding（CVE + package + layer）在 candidate 中**不存在** |
| **D2** | **无新增** | `candidate.findings ⊆ baseline.findings`（同一 DB 前提下）。新增项数 = 0 |
| **D3** | **digest 变了** | candidate digest ≠ baseline digest。证明确实重建了（防止"改了个 tag 但镜像没变"） |

> **D2 的例外处理**：如果同一批次里 DB 恰好更新了，导致 baseline 里没而 candidate 里有的项，需要**重跑 baseline 扫描**再比，而不是直接放行。实现上就是"DB 版本变了就重扫 baseline"。

### 4.2 还要加一道"运行时冒烟"

镜像编译通过 ≠ 运行正常。升 base 镜像（尤其 alpine 大版本、distroless 切换、musl/glibc 变化）常常是**编译期没事、运行期炸**。

因此再加一条：

| # | 判定 | 说明 |
|---|---|---|
| **D4** | **冒烟测试通过** | 容器能启动、关键 endpoint 有响应、日志无 panic、配置能加载 |

**D4 是 T1/T2 自动化能否"自动合并"的分水岭。** 没有 D4，T1 最多只能自动出 PR。

### 4.3 判定结果与出口码

沿用 `shipyard` 的出口码语义（这个约定很干净，值得抄）：

| 出口码 | 含义 | 后续动作 |
|---|---|---|
| `0` | 全部目标已修复且 VERIFIED（D1–D4 全过） | 开 PR（按类型决定是否自动合并） |
| `2` | **部分修复 / 基础设施失败 / 门禁不通过** | 开 PR 但标注 partial，或不开 PR；**绝不自动合并** |
| `1` | 配置或调用错误（skill setup error） | 修配置重跑 |
| `3` | 无可用修复版本 / 超出自动化范围 | 转人工，SCC 上打标签并附完整上下文 |

> 注意 `2` 这个码覆盖了三种很不一样的情况（partial / infra / gate）。`shipyard` 也是这么粗的。如果我们要做得更好，建议**内部细分**（比如 `10/11/12`），但对外仍映射到 `2`，保持与现有 skill 生态兼容。

### 4.4 "忽略"必须有到期时间

总有一些 CVE 是**没有修复版本**的（厂商 wontfix / disputed / EOL 分支不再更新）。这些必须有"忽略"记录，但：

- 必须带**明确的 package 选择器**（不能是全局正则）；
- 必须带**到期时间**（如 `fix-state: temporary, expires: 2026-12-31`）；
- 必须带**理由**（wontfix / 不可达 / 已有补偿控制）；
- 到期自动回到待办。

这是 `shipyard` 里做得很到位的一点（`ignore.sh` 强制要求 `--fix-state` / `--permanent`，且自动生成的忽略项都带 auto-expiring 的 `fix-state`），**直接抄这个约束**。

---

## 5. 三类可自动修复的具体做法

### 5.1 T1/T2：OS 与 Base Image（含 dex 实测案例）

> 📄 **本节的完整可执行版本在 [how-to-fix-dex-base-image.md](./how-to-fix-dex-base-image.md)** —— 含现状盘点命令、三个候选方案对比、Phase 0–4 逐步执行、验证契约、回滚、防复发、以及"为什么 Dependabot 修不了这个 case"。本节只保留设计要点。

#### 5.1.1 你们的 dex 案例，完整走一遍

**输入（你给的）：**
```
europe-west2-docker.pkg.dev/myproject/containers/dex@sha256:23f4f869a06398b79eceb5266ad6e522a894fc18163e5e37a810666e51aaf2ae
built from os(alpine) version (3.21), support end of life on 2026-11-01 00:00:00+00
```

**Step 0 —— 确认 finding 来源（别跳过）**

这条 finding 的文案不像标准 CVE 格式。先确定它是谁报出来的：

- SCC 里的哪一类 finding / 哪个 source？
- 还是 Artifact Analysis 的 Grafeas occurrence？
- 还是第三方（Snyk / Black Duck / Wiz / Trivy 的生态检查）？

不同来源，字段结构和"修复语义"不一样。**如果它来自第三方工具且 Artifact Analysis 复现不出来，那整个"推 GAR → 拿报告 → 验证"的闭环就不成立**，方案要改。这一步必须在写任何代码之前做完。

**Step 1 —— 定位 Dockerfile 与 base**

```bash
# 1) 确认镜像的 base 镜像链（GCP 原生：image basis）
gcloud artifacts docker images describe \
  europe-west2-docker.pkg.dev/myproject/containers/dex@sha256:23f4f869... \
  --show-image-basis

# 2) 本地拉下来看镜像层和标签
docker pull europe-west2-docker.pkg.dev/myproject/containers/dex@sha256:23f4f869...
docker history --no-trunc europe-west2-docker.pkg.dev/myproject/containers/dex@sha256:23f4f869...
```

**Step 2 —— 查上游现状（实测结论）**

上游 `dexidp/dex` 的 `Dockerfile`（2026-11-05 实测 master）：

```dockerfile
ARG BASE_IMAGE=alpine            # ← base 可通过 build arg 切换
...
FROM alpine:3.24.3@sha256:be26... AS stager
FROM gcr.io/distroless/static-debian13:nonroot@sha256:25ac... AS distroless
FROM $BASE_IMAGE                 # ← 最终形态由 BASE_IMAGE 决定
```

**实测结论（对本方案非常有利）：**

1. **上游已经不在 alpine 3.21 了** —— master 已经用 `alpine:3.24.3`（EOL 2028-06-01）；
2. **上游提供 `alpine` 和 `distroless` 两个 variant**（见 `.github/workflows/artifacts.yaml` 的 `matrix.variant`）；
3. 上游 Dockerfile 里专门有一行注释：
   ```dockerfile
   # Copy module files for CVE scanning / dependency analysis.
   COPY --from=builder /usr/local/src/dex/go.mod /usr/local/src/dex/go.sum ./
   ```
   → **Go 依赖也一并暴露给了 SCA 工具**，SCA 覆盖是完整的；
4. 上游还配了 syft SBOM + cosign 签名（`anchore/sbom-action`、`sigstore/cosign-installer`）和 Trivy DB 缓存 workflow → 说明上游自己在用 SCA 闭环。

**Step 3 —— 三条可选修法**

| 方案 | 动作 | OS 漏洞残留 | 风险 | 推荐度 |
|---|---|---|---|---|
| **A. 跟上游** | 升 dex 版本到用 `alpine:3.24.3` 的 release | 少 | 低 | ⭐⭐⭐ 首选 |
| **B. 重建 + 换 base** | 用现有源码，build 时 `--build-arg BASE_IMAGE=alpine:3.24.3`（或更新） | 少 | 低 | ⭐⭐ |
| **C. 切 distroless** | `--build-arg BASE_IMAGE=distroless` | **几乎没有 OS 包** | 中（distroless 无 shell，很多工具链会挂） | ⭐⭐ 强烈推荐评估 |

> **C 值得单独强调**：你们这个 dex 是 OIDC provider，跑在 GKE 里，**不需要 shell 调试**的场景很常见。切到 distroless 后，Alpine EOL 问题**从根上消失**，而且镜像体积和攻击面都小一个量级。这是一个"一次投入，长期免疫"的决策，比每次跟 EOL 日期赛跑划算得多。
>
> ⚠️ distroless 的坑：没有 `/bin/sh`、没有 `apk`、用户是 `nonroot`（uid 65532）；dex 自己的 Dockerfile 里 `COPY --from=user-setup /etc/passwd` 覆盖了用户，需要确认挂载卷权限、ConfigMap/Secret 挂载路径、以及 `/var/dex` 的写权限。

**Step 4 —— 重建 + 推送 + 扫描（闭环的机械部分）**

```bash
# 用 buildx 构建多架构（跟 GKE 节点架构对齐）
docker buildx build \
  --platform linux/amd64 \
  --build-arg BASE_IMAGE=distroless \
  -t europe-west2-docker.pkg.dev/myproject/containers/dex:cve-fix-001 \
  --push .

# 拿到新 digest（重要：后面所有验证都绑定这个 digest）
NEW_DIGEST=$(gcloud artifacts docker images describe \
  europe-west2-docker.pkg.dev/myproject/containers/dex:cve-fix-001 \
  --format='value(image_summary.digest)')
```

**Step 5 —— 验证（按第 4 章契约）**

```bash
# baseline 与 candidate 用同一批 DB 扫
gcloud artifacts docker images scan <OLD_IMAGE@digest> --remote --location=europe
gcloud artifacts docker images scan <NEW_IMAGE@digest> --remote --location=europe
# 轮询直到两次都完成
gcloud artifacts docker images get-operation <OP>
# 取漏洞列表
gcloud artifacts docker images list-vulnerabilities projects/myproject/locations/europe/scans/<SCAN_ID>
```

差分判定 D1–D3，然后跑冒烟（D4）。

**Step 6 —— 别忘了更新 GKE 清单（最常被漏掉的一步）**

新 digest 出来了，**K8s 的 Deployment 必须换成新 digest**，否则老镜像还在跑，扫描器看到的是"新的已修"但集群里跑的是"旧的有洞"。

```bash
# 1) 找出谁在跑这个镜像
kubectl get deploy,sts,ds -A -o json | \
  jq -r '.items[] | select(.spec.template.spec.containers[].image | contains("containers/dex")) |
         "\(.kind)/\(.metadata.namespace)/\(.metadata.name)"'

# 2) 换 digest（建议：仓库里用 kustomize/ Helm 管 image digest，不要手改）
# 3) 灰度 → 全量
kubectl rollout status deploy/<name> -n <ns>
```

> **这一步也必须进自动化流程**，否则会出现"SCC finding 自动关了但集群还在跑旧镜像"的假闭环 —— 因为 SCC 的 finding 是基于**部署中的资源**关联的。

**Step 7 —— 防复发**

- Dockerfile 里把 base 镜像**按 digest 钉住**（`alpine:3.24.3@sha256:...`），但**同时**用一个注释或 renovate/dependabot 配置跟踪 tag 升级；
- 配置 **Dependabot / Renovate 的 `docker` ecosystem** → 上游 base tag 有新版就自动出 PR；
- 配置一条**定期巡检**（每月）：查所有 GAR 镜像的 base OS 是否命中 EOL 列表 → 这条比"等扫描器报"更早。

---

### 5.2 T3/T4：Go 依赖

Go 生态的自动化修复**已经有成熟方案**，而且**最值得借鉴的就是你找到的那个 shipyard skill**（详见第 6 章）。

**修复路径：**

| 场景 | 动作 | 关键语义 |
|---|---|---|
| 第三方模块 CVE | `go get module@fixed_version` → `go mod tidy` → 更新 `go.sum` / vendor | 可能是 major 升级 → API 破坏 |
| 间接依赖 CVE | `go get` 提升到需要的最低版本 | 可能连带升级一堆 |
| Go stdlib CVE | `go.mod` 里加 **`toolchain go1.24.x`** | ⚠️ **不要动 `go` 指令** |

> **`toolchain` vs `go` 这个细节是 Go 修复里最容易踩的坑**（`shipyard` 的文档专门开了一节讲）：
> `go` 指令是**最低语言版本**，会被下游所有依赖它的模块继承，改它会强制下游一起升级、并且破坏 `GOTOOLCHAIN=local` 的构建；
> `toolchain` 指令**只为本模块选择编译器版本**，本地构建会忽略它。所以 stdlib 修复**只设 `toolchain`**。
> 另外，如果构建镜像（builder image）里的 Go 版本低于修复所需版本 → 需要一并升级 builder 镜像，否则 CI 编不过。

**验证：** 编译 + 单测 + **扫编译产物二进制**（Grype 能从二进制里读出 stdlib 版本，只扫源码是看不见 stdlib CVE 的）→ 这是 `shipyard` 花大力气处理的点（它甚至会检测 UPX 压缩的二进制并标记 coverage-unknown）。

---

### 5.3 T3/T4：Java 依赖

Java 的情况比 Go 麻烦一档：Maven/Gradle 的依赖解析、传递依赖、shade/assembly 产物、Spring Boot 的 fat jar 都让"升一个依赖"的后果更难预测。

**可用工具（实测确认）：**

| 工具 | 能力 | 备注 |
|---|---|---|
| **OSV-Scanner v2 `fix`** | ✅ **支持 Maven `pom.xml` 的 `override` 策略**（也支持 npm lockfile/manifest） | ⚠️ **不支持 Go**（Go 只能扫描不能自动修）；官方警告：在不受信任的项目上运行有风险 |
| **Renovate** | `maven` / `gradle` manager + vulnerability alerts | 生成 PR，成熟度最高 |
| **Dependabot** | `maven` / `gradle` / `docker` / `gomod` ecosystem | 生成 PR；`docker` ecosystem 会更新 Dockerfile 的 `FROM`（这正是 T1 的自动化手段） |
| **OWASP Dependency-Check** | 只检测不修复 | 适合做独立第二意见 |
| **Trivy / Grype** | 扫 jar / pom / fat jar | 检测层 |

**推荐组合（Java）：**

1. **日常版本升级** → Dependabot 或 Renovate 自动开 PR（成熟、稳）；
2. **CVE 定向修复** → Renovate 的 vulnerability alerts（按 advisory 精确升到修复版本）；
3. **无 PR 产出时** → 用 `osv-scanner fix -M pom.xml --strategy=override` 生成候选，人工评审；
4. **检测层双保险** → Artifact Analysis（已覆盖 MAVEN package type）+ Trivy/Grype 交叉验证。

> ⚠️ **OSV-Scanner `fix` 在 Maven 上用的是 `override`**（在 `<dependencyManagement>` 里强制版本）。这能"锁死"版本，但会让版本升级变得不透明 —— 需要团队约定：是接受 override，还是把 override 固化后手工整理回正常声明。**建议只在自动修复 PR 里临时用 override，合入前整理**，否则依赖升级会变成永久的 override 堆。

**Java 特有的额外风险（必须写进门禁）：**

- **Java 运行时（JReleases）**：JDK 本身有 CVE，来源是 base image（JDK 基础镜像），走 T2 路径；
- **Shaded/Relocated JAR**：某些 shade 插件会把依赖打进 fat jar 并改包名 → SCA 工具**可能扫不出来**（扫描器看不到被 relocate 的类）→ 属于 coverage-unknown，要显式处理；
- **Spring Boot 的 BOM**：升一个 starter 可能连锁升级整个 Spring Boot 家族 → 破坏性远大于 Go 的单模块升级。

---

### 5.4 T5：应用代码（CWE）

**这一类不进自动修复流水线。**

AI 可以做的是：
- 把 SAST/渗透报告里的 CWE 定位到具体代码位置；
- 生成候选补丁；
- 写清楚根因和影响面。

但**合并必须人工**。理由回到 `cve-cwe.md`：修好一个 CVE ≠ 修好这个 CWE；AI 很容易"在出问题的那个文件打个补丁"，而同一个弱点的其他调用点还留着 —— 反而制造了"已修复"的假象，这比不修更危险。

---

## 6. 现有 Skill 评估

### 6.1 `submariner-io/shipyard` 的 `cve-fix`（重点评估）

**安装方式（已验证 `npx skills` CLI 支持）：**

```bash
# 只装这一个 skill
npx skills add https://github.com/submariner-io/shipyard --skill cve-fix

# 装到指定 agent（OpenCode 走 .agents/skills/）
npx skills add https://github.com/submariner-io/shipyard --skill cve-fix -a opencode

# 全局装（OpenCode 全局路径 ~/.config/opencode/skills/）
npx skills add https://github.com/submariner-io/shipyard --skill cve-fix -a opencode -g
```

> `npx skills` 支持的 agent 清单里包含 `opencode`（项目路径 `.agents/skills/`，全局 `~/.config/opencode/skills/`），OpenCode 官方文档：<https://opencode.ai/docs/skills>。
> 注意：`skills` CLI 默认**是符号链接**到 agent 目录，加 `--copy` 会变成拷贝（改动不会自动同步）。

**实测结构**（`git clone --depth 1 --filter=blob:none --sparse` 后查看）：

```
skills/cve-fix/
├── SKILL.md              # 22KB，极详细的工作流 + Known Limitations
├── Makefile              # make fix REPO=... BRANCH=... / make all / make test
├── repos.yaml.example    # 多仓库注册表
├── agents/openai.yaml
├── subagents/            # 三个只读校验子代理
│   ├── existing-entries / fix-availability / scan-regression / yaml-integrity
└── scripts/
    ├── fix-all.sh        # 55KB 主编排
    ├── fix-package.sh    # 43KB 依赖版本修复
    ├── fix-stdlib.sh     # 9KB  stdlib / toolchain 修复
    ├── scan.sh           # Grype 扫描
    ├── ignore.sh         # 忽略策略（带 fix-state 过期机制）
    ├── review.sh + review-prompt.md
    ├── detect.sh         # 17KB 自动探测 build/test/clean 命令
    ├── read-config.py    # .cve-fix.yaml 解析
    ├── lib.sh            # 145KB
    └── test-lib.sh       # 556KB
```

#### ✅ 它做得很好的地方（建议直接吸收的设计）

1. **LLM 是只读审查者，不是写入者** —— 文档明确写：*"deterministic shell handlers are the only mutation authority"*。LLM 只解释兼容性/发布策略决策，不能改依赖、Git 状态、ignore 或报告。
2. **sentinel 文件的 fail-closed 模式**（§4 规则 A）—— build 失败、网络断、DB 降级、覆盖率未知 → 一律拒绝报"clean"。这是整个 skill 里最值得抄的部分。
3. **扫描前后对比 + 回滚**：修一个 advisory 不允许引入另一个；更新后重新比对，发现新 finding 就**回滚这次更新**（包括 vendor 树和未跟踪文件）。
4. **优雅降级的 LLM 审查**：claude/codex CLI 没装时退化成"确定性证据"，并且**不会把未确认的结果当成 clean**。
5. **ignore 策略严谨**：仓库级 / module 级作用域不能共存；自动生成的 ignore 一定带**自动过期的 fix-state** + 精确 package 选择器；直接调 `ignore.sh` 不给 `--fix-state`/`--no-fix`/`--permanent` 就**无法创建永久忽略**。
6. **`toolchain` 而非 `go`**：Go stdlib 修复的语义细节（第 5.2 节），处理得比我预期的细致得多，还考虑了 `GOTOOLCHAIN=local`、builder image 版本兼容性、pre-module `+incompatible`、Go workspace（`GOWORK=off` + `go work sync`）。
7. **PR 就绪门禁**：commit 缺 `Signed-off-by:` → 不出 PR 命令；base 分支在运行期间移动 → 不出 PR 命令（**不静默 rebase**）；有 `make licensecheck` 就跑，失败则不出 PR；出现无关文件变更 → 不出 PR。
8. **多仓库并行**：`repos.yaml` 注册表 + 每仓库一个 worker + worker 自己清理子进程 + 禁止跨 worker 的粗暴进程清理。
9. **详尽的 Known Limitations**：诚实地列出每个不确定的地方怎么办（转 NEEDS_REVIEW 而不是硬猜）。

#### ❌ 不适合你们的地方

| 问题 | 说明 |
|---|---|
| **只支持 Go** | `fix-package.sh` / `fix-stdlib.sh` 全部围绕 `go.mod` / `go.sum` / `vendor/` / `go mod tidy`。**Java、Maven、Node 全部不支持。** |
| **完全不管镜像** | 不扫容器镜像、不改 Dockerfile、不推 GAR、不验证 Artifact Analysis 的扫描结果。**这正是你们的主场景。** |
| **Make-centric** | 默认探测 `make build` / `make unit` / `make test`；虽然 `.cve-fix.yaml` 可覆盖，但你们的构建多半是 `docker build` 或 `cloud build` |
| **Dapper 专有逻辑** | `detect.sh` 里有大段 `submariner-io/shipyard` 的 Dapper/Makefile.inc 探测，是上游生态专有 |
| **体量过大** | `lib.sh` 145KB + `test-lib.sh` 556KB ≈ 700KB shell。fork 和维护成本很高，bash 4+ 依赖、macOS 还得单独装 bash 和 coreutils（`timeout` 名字是 `gtimeout`，脚本路径还有坑） |
| **PR 目标写死 GitHub** | 生成的是 `git push` + `gh pr create` |
| **PR 只到源码层** | 停在了 "PR 命令已打印"，**没有"构建镜像 → 推 GAR → 扫镜像 → 验证"这一段** —— 而这正是你们需要的核心 |

#### 结论

> **这是一个优秀的「Go 依赖 CVE 自动修复」参考实现，但它不是「GAR 镜像 violation 自动修复」方案。**
>
> - **Go 仓库** → 可以直接用（`npx skills add ... --skill cve-fix`），先跑起来看效果；
> - **你们的镜像级场景** → 它的**设计模式**（尤其是 fail-closed sentinel、只读 LLM、ignore 过期机制、PR 就绪门禁）值得逐条移植，但**代码不适合 fork**（Go 专有 + 体量过大 + 不涉及镜像）。
>
> **建议：借设计，不抄代码。** 新写一个 GCP 专用的 `gcp-cve-fix`，用 Python（不是 shell）实现，控制在 500–1500 行。

---

### 6.2 其他候选 skill（skills.sh 检索结果）

> 📄 **Dependabot 的完整使用手册（安装、配置、私有 registry、CI 集成、AI agent、选型决策）在 [how-to-use-dependabot.md](./how-to-use-dependabot.md)** —— 本节只做 skill 生态的横向对比。

2026-11-05 用 `skills.sh` API 检索（`cve` / `vulnerability` / `dependency-fix` / `container security` / `osv` / `trivy` / `sbom` / `renovate` / `dependabot` / `supply chain` / `gcp` 等关键词）：

| Skill | 安装量* | 定位 | 对你们场景的适用性 |
|---|---|---|---|
| `submariner-io/shipyard/cve-fix` | — | Go 依赖 + stdlib 自动修复，含完整验证门禁 | ⭐⭐⭐ **Go 场景直接用**；设计范式全部可借鉴 |
| `github/awesome-copilot/dependabot` | 4437 | Dependabot **配置**指南（生态、分组、冷却期、auto-triage） | ⭐⭐ 用来配 Dependabot；**它不是修复器**，是配置文档 |
| `vtmocanu/skills/upgrade-advisor` | 287 | **升级前风险评估**：读 changelog 全文 → grep 分类 breaking change → 对照真实代码用法 → 输出 safe / stay-put / blocked 判定 | ⭐⭐⭐ **强烈推荐作为「破坏性变更评审」环节**，正好补上 T3/T4 的风险判断 |
| `agentsecops/secopsagentkit`（`sca-trivy` / `container-grype` / `sbom-syft` / `container-hadolint` / `secrets-gitleaks` / `iac-checkov`） | 40（单 skill） | 一整套 SecOps 工具使用手册（含 Trivy、Grype、Syft、Hadolint、Gitleaks、Checkov、Nuclei、DefectDojo、BlackDuck） | ⭐⭐ **检测层的现成手册**；不含修复逻辑，可直接当内部 runbook |
| `snyk/studio-recipes/snyk-fix` | 404 | Snyk 自动修复 | ⭐ 商业依赖；Snyk 能覆盖容器 OS 包，对 T2 有价值，但要评估合规/成本 |
| `igbuend/grimbard/osv-scanner` 等 OSV 类 | 9–13 | OSV-Scanner 用法 | ⭐⭐ **OSV-Scanner v2 自带 `fix` 命令（Maven override / npm）**，即使 skill 本身一般，工具本身值得直接用 |
| `mukul975/anthropic-cybersecurity-skills`（trivy 系列 / SBOM 系列 / CVE 情报系列） | 121–456 | Trivy 扫描、SBOM 分析、CVE 研究、KEV 排序 | ⭐⭐ 工具用法 + **CVE 优先级（KEV/EPSS）** 有用 |
| `owasp/secure-agent-playbook/sca-audit` | 318 | SCA 审计流程 | ⭐⭐ 流程参考 |
| `alirezarezvani/claude-skills/dependency-auditor` | 707 | 依赖审计 | ⭐ 思路参考 |
| `jwynia/agent-skills/dependency-scan` | 365 | 依赖扫描 | ⭐ 思路参考 |
| `trailofbits/skills/supply-chain-risk-auditor` | 8733 | 供应链风险审计 | ⭐⭐ 流程参考（偏审计，非修复） |
| `github/awesome-copilot/agent-supply-chain` | 1125 | 供应链安全 | ⭐⭐ 流程参考 |

\* 安装量来自 skills.sh 检索接口（2026-11-05），**仅作流行度参考，不代表质量**。

**候选 skill 生态的结论：**

> **skills.sh 上"能改代码修 CVE"的 skill 基本只有 shipyard 的 cve-fix 一个（且只支持 Go）。**
> 其余 90% 是**扫描器用法手册**（Trivy / Grype / Syft / OSV / Semgrep）或**流程文档**（Dependabot 配置、供应链审计、升级风险评估）。
>
> 这说明了一件重要的事：**这个方向上没有"装个 skill 就完事"的银弹。**
> 工具层（Trivy/Grype/OSV/Dependabot/Renovate）都是现成的，**缺的是把它们串成闭环、并加上 GCP 特有环节（推 GAR → 扫镜像 → 差分）的那一层** —— 这一层必须自建。

---

## 7. 自建 Skill 规格：`gcp-cve-fix`

### 7.1 定位

> 输入：一条或一批 violation（来自 SCC / Artifact Analysis / 人工）
> 输出：一个带**验证证据**的 PR（源码 + 镜像 + 清单 digest 三者一致），或者一条"转人工"的完整上下文。

### 7.2 目录结构

```
gcp-cve-fix/
├── SKILL.md                     # 工作流说明（面向 Agent）
├── config/
│   └── gcp-cve-fix.example.yaml # 项目配置模板
└── scripts/
    ├── discover.sh              # ① 找出所有 GAR 镜像 ↔ GKE 工作负载 ↔ 源码仓库 的对应关系
    ├── scan-gar.sh              # ② 调 Artifact Analysis，输出 normalized findings JSON
    ├── triage.py                # ③ 分类 T1–T5 + 选策略 + 定门禁阈值（纯规则）
    ├── plan-prompt.md           # ④ 给 LLM 的只读计划模板（含证据清单）
    ├── apply/
    │   ├── fix_base_image.py    # ⑤a 改 Dockerfile FROM
    │   ├── fix_gomod.sh         # ⑤b Go 依赖
    │   └── fix_maven.py         # ⑤c Maven 依赖
    ├── build.sh                 # ⑥ 构建（本地 buildx 或 gcloud builds submit）
    ├── push.sh                  # ⑦ 推 GAR staging tag，输出新 digest
    ├── verify.py                # ⑧ 轮询扫描 + 差分 D1–D3 + 冒烟 D4 + 判定
    └── deliver.py               # ⑨ 生成 PR（含证据表）+ 更新 K8s manifest digest
```

> 全部用 **Python 3 + `gcloud` 子进程调用**，不用 bash。理由：JSON 处理、API 调用、表格生成在 Python 里是一等公民；bash 在这个规模上会重蹈 `shipyard` 的 700KB 老路。

### 7.3 项目配置 schema（草案）

```yaml
# gcp-cve-fix.yaml（放在源码仓库根目录）
gcp:
  project: myproject
  location: europe-west2          # GAR 仓库位置
  analysis_location: europe       # Artifact Analysis 分析位置（asia/europe/us）

image:
  repository: europe-west2-docker.pkg.dev/myproject/containers/dex
  dockerfile: ./Dockerfile
  context: .
  platform: linux/amd64
  build_args:
    BASE_IMAGE: distroless       # ← dex 的 base 切换开关
  build_command: >-
    docker buildx build --platform ${platform}
    --build-arg BASE_IMAGE=${BASE_IMAGE}
    -t ${staging_tag} --push .
  build_engine: local            # local | cloud-build

build:
  test_command: make unit
  smoke_test:
    command: ./hack/smoke.sh
    timeout: 300

gates:
  max_new_findings: 0            # D2：不允许引入新 finding
  block_categories: [OS, GO, MAVEN, NPM]
  allow_severities: [CRITICAL, HIGH, MEDIUM]   # 更低的不进流水线
  require_smoke: true            # D4

manifests:                       # 部署清单（digest 要一起更新）
  - path: k8s/dex/deployment.yaml
    image_key: spec.template.spec.containers[0].image

policy:
  auto_merge: [T1, T2]           # T3/T4/T5 只出 PR 不自动合并
  require_signoff: true
  ignore_expiry_days: 90
```

### 7.4 LLM 的使用边界（写进 SKILL.md 的硬约束）

**LLM 可以做：**

- 读 finding + 读源码 → 判断改哪个文件的哪一行；
- 判断某个依赖升级是否 API 破坏（结合 changelog 和真实调用点）；
- 解释为什么某个 finding 无法修复；
- 生成 PR 描述、风险说明、回归测试建议。

**LLM 不可以做：**

- 直接改文件（改文件只能由 Executor 脚本做，且必须在 git 分支上）；
- 声明"漏洞已修复"（只有 verify.py 能说这句话）；
- 创建 / 修改 / 永久化 ignore 条目；
- 绕过任何 gate；
- 决定自动合并。

> 这条边界的具体实现方式，直接抄 `shipyard` 的模式：**给 LLM 预取好的证据，让它返回结构化文本；所有 mutation 走确定性 shell/python handler。**

---

## 8. 落地路线图

### Phase 0 —— 可见性（1 周，不写代码）

| # | 动作 | 产出 |
|---|---|---|
| 0.1 | **确认那条 alpine EOL finding 的确切来源**（SCC？第三方？） | 决定闭环是否成立。**这是 go/no-go 关卡** |
| 0.2 | 盘点所有 GAR 仓库的三个开关：漏洞扫描 / 连续扫描 / SBOM 生成 | 一张表：哪些仓库漏了 |
| 0.3 | 建立 `GAR 镜像 ↔ GKE 工作负载 ↔ 源码仓库` 的对应关系 | 台账（后面所有自动化的输入） |
| 0.4 | 在 SCC 里建好 finding 的分类/优先级 | 台账能按优先级排 |
| 0.5 | 手工跑通一次「升级 base → 重建 → 推 GAR → `gcloud artifacts docker images scan --remote` → 拿到结果」 | **验证闭环可行** |

> Phase 0.5 是真正的 go/no-go。如果 Artifact Analysis 扫不出你们关心的 OS EOL 类 finding，或者扫描延迟不可接受，整个方案要重新设计。

### Phase 1 —— 手工闭环跑通 T1（1–2 周）

拿 dex 这个 EOL case 完整手工走一遍 §5.1 的 7 步：
- 升 base / 切 distroless
- 重建 → 推 GAR staging tag
- 扫描 → 差分（此时手工比）
- 冒烟
- 更新 K8s manifest digest → 灰度 → 全量
- 确认 SCC finding 关闭

**产出**：一份"手工 runbook"，它就是 Phase 2 要自动化的脚本。

### Phase 2 —— `gcp-cve-fix` v0（2–3 周）

只做 **T1（base image EOL）** 这一类，最简单、最机械、最容易验证：
- `scan-gar.sh` + `triage.py` + `fix_base_image.py` + `build.sh` + `push.sh` + `verify.py` + `deliver.py`
- 只自动出 PR，**先不自动合并**
- 在 2–3 个仓库上试点

**验收标准**：连续跑 3 次，全部 D1–D4 通过，人工评审 PR 的耗时 < 5 分钟/次。

### Phase 3 —— Go 依赖（T3/T4）

两条路并行：
- **路线 A（省事）**：直接用 `submariner-io/shipyard/cve-fix` 装到 OpenCode，先在 Go 仓库上跑通，把它的输出接到我们的 `verify.py`（它的 rescan gate 只覆盖源码/二进制，**我们的镜像验证是它没有的那一段**）；
- **路线 B（可控）**：按 `shipyard` 的设计自己写 `fix_gomod.sh` + `fix-stdlib.sh`（重点抄它的 `toolchain` 语义、indirect dependency 处理、vendor 同步、ignore 过期机制）。

推荐 **先 A 后 B**：A 能立刻产生价值，同时暴露出 B 需要解决的真实问题。

### Phase 4 —— Java 依赖（T3/T4）

- 日常升级：Dependabot / Renovate（不是我们的问题，交给它们）
- CVE 定向修复：Renovate vulnerability alerts + OSV-Scanner v2 `fix`（Maven override）
- 我们的 skill 只负责：**跑完之后自动做镜像级验证 + 清单 digest 更新**（这块是 Dependabot/Renovate 都没有的）

### Phase 5 —— 门禁与防复发

- Binary Authorization：准入策略 + continuous validation
- Base OS EOL 定期巡检（早于扫描器报出来）
- 依赖版本巡检（定期全量扫，防漏网）
- 指标看板：MTTR、自动修复占比、回归率、EOL 提前量

---

## 9. 风险、边界与反模式

### 9.1 明确的能力边界

| 做不到 | 为什么 | 怎么办 |
|---|---|---|
| 修复**没有补丁**的 CVE | 厂商 wontfix / disputed / EOL 分支 | 走 ignore 流程（带到期时间 + 补偿控制），转风险接受 |
| 修复**第三方上游镜像**里的 OS 漏洞（除非自建） | 你改不了上游 | 换上游版本 / 换变体 / 迁移到自建 / 迁移到 distroless |
| 修复**应用代码**（T5） | 风险太高 | AI 只出建议，人工合并 |
| 保证**"零漏洞"** | 扫描器 DB 有延迟，新 CVE 随时发布 | 承诺"扫描时点已知的漏洞已清零"，而不是"永远没有漏洞" |
| 修复**已经 EOL 的上游软件**本身 | 上游不再维护 | 换产品 / 长期支持版本 |

### 9.2 反模式清单（评审时对照检查）

| ❌ 反模式 | 为什么有害 | ✅ 正确做法 |
|---|---|---|
| AI 改完直接说"已修复" | 没有任何客观证据 | 只有扫描器差分能说"已修复" |
| 用本地扫描结果当验收 | 本地 DB 版本不同、覆盖不同 | 用**同一个镜像 digest** 在 GAR 上扫 |
| 修了镜像但没改 K8s manifest | 集群还在跑旧镜像，假闭环 | manifest digest 更新是流程的**必选步骤** |
| "修一个引入一个"还合入 | 用一个 CVE 换另一个 CVE | D2 门禁：新 finding > 0 → 自动回滚 |
| 扫描失败 / DB 降级当成"没有漏洞" | 把不确定当确定 | fail-closed：不可信 = 未修复 |
| 永久 ignore 掩盖无法修复的 CVE | 台账变绿，风险还在 | ignore 必须带到期时间和理由 |
| base image 大版本跳跃（3.21 → 3.24）不冒烟 | 编译过但运行炸 | D4 冒烟必过 |
| AI 自动合并 T3/T4 的 PR | 破坏性变更无声进入生产 | T1/T2 才允许自动合并 |
| 一个 PR 里混改 base image + 依赖 + 代码 | 出问题无法二分定位 | **一次 PR 只改一类** |

### 9.3 一个容易被低估的收益

除了"修 CVE"，这套机制顺带解决了一个更难的问题：

> **让"这个镜像到底是什么"变得可查询。** SBOM + Artifact Analysis + manifest digest 绑定之后，每个线上 Deployment 都能回答："我跑的这个镜像，包含哪些包、哪些已知漏洞、上次扫描是什么时候"。这是后续所有安全运营的基础设施。

---

## 10. 附录

### 10.1 核心命令速查（本机 `gcloud 526.0.1` 已验证）

```bash
# ---- 漏洞扫描 ----
gcloud artifacts docker images scan <IMAGE> --remote --location=europe
gcloud artifacts docker images scan <IMAGE> --remote --location=europe --async
gcloud artifacts docker images get-operation <OPERATION>
gcloud artifacts docker images list-vulnerabilities projects/<p>/locations/europe/scans/<id>

# ---- 镜像元信息 ----
gcloud artifacts docker images describe <IMAGE@digest> --show-package-vulnerability
gcloud artifacts docker images describe <IMAGE@digest> --show-sbom-references --show-provenance
gcloud artifacts docker images describe <IMAGE@digest> --show-image-basis
gcloud artifacts docker images list --include-tags

# ---- 仓库设置 ----
gcloud artifacts repositories update <repo> --allow-vulnerability-scanning

# ---- 安全台账 ----
gcloud scc findings list --project=<p> --filter='state="ACTIVE" AND category="CONTAINER_VULNERABILITY"'

# ---- 门禁 ----
gcloud container binauthz attestors list
gcloud container binauthz policy get <policy> --format=json

# ---- 构建 ----
gcloud builds submit --config=<file>       # Cloud Build
docker buildx build --platform linux/amd64 -t <tag> --push .   # 本地

# ---- 运行时确认 ----
kubectl get deploy,sts,ds -A -o json | jq -r '...'   # 谁在跑这个镜像
kubectl rollout status deploy/<name> -n <ns>
```

### 10.2 工具选型速查

| 场景 | 推荐 | 备选 |
|---|---|---|
| 容器漏洞扫描（权威） | **Artifact Analysis** | Trivy / Grype（做第二意见） |
| 语言依赖扫描 | Artifact Analysis（GO/MAVEN/NPM） | OSV-Scanner、OWASP Dependency-Check |
| 依赖自动升级（日常） | Dependabot / Renovate | — |
| CVE 定向修复（Go） | shipyard cve-fix / 自建 | `go get` + `govulncheck` |
| CVE 定向修复（Java） | Renovate vulnerability alerts、**OSV-Scanner v2 `fix`**（Maven override） | 手工 |
| 破坏性变更评估 | `vtmocanu/skills/upgrade-advisor` | AI 读 changelog |
| SBOM | Artifact Analysis SBOM、`syft` | `trivy --format cyclonedx` |
| 签名 | cosign + Binary Authorization | — |
| Go stdlib 漏洞 | `govulncheck` + `toolchain` 指令 | — |

### 10.3 参考链接

- Shipyard cve-fix：<https://github.com/submariner-io/shipyard/tree/devel/skills/cve-fix>
- 该 skill 的 SKILL.md：<https://github.com/submariner-io/shipyard/blob/devel/skills/cve-fix/SKILL.md>
- skills.sh 检索：<https://skills.sh/> ／ CLI：`npx skills find <query>`、`npx skills add <repo> --skill <name> -a opencode`
- skills CLI 支持的 agent 清单：<https://github.com/vercel-labs/skills/blob/main/docs/agents.md>
- OpenCode Skills：<https://opencode.ai/docs/skills>
- Artifact Analysis 文档：<https://cloud.google.com/artifact-registry/docs/artifact-analysis>
- Container Analysis API（含 `exportSBOM` / `getVulnerabilitySummary`）：<https://cloud.google.com/container-analysis/api/reference>
- SCC Findings：<https://cloud.google.com/security-command-center/docs/how-to-find-and-manage-findings>
- Binary Authorization：<https://cloud.google.com/binary-authorization/docs/overview>
- OSV-Scanner（v2 `fix` 命令）：<https://github.com/google/osv-scanner>
- Grype：<https://github.com/anchore/grype>
- Trivy：<https://github.com/aquasecurity/trivy>
- Alpine 生命周期：<https://endoflife.date/alpine>
- dex 上游（含 `ARG BASE_IMAGE` / alpine+distroless variant）：<https://github.com/dexidp/dex/blob/master/Dockerfile>
- Renovate：<https://docs.renovatebot.com/>
- Dependabot 配置参考：<https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file>

---

## 11. 下一步（需要你确认的 4 件事）

| # | 问题 | 为什么阻塞 |
|---|---|---|
| 1 | **那条 alpine 3.21 EOL finding 是哪个工具报出来的？**（SCC / Artifact Analysis / 第三方） | 决定闭环是否成立（Phase 0.5） |
| 2 | **你们的 dex 镜像是自己 build 的 Dockerfile，还是 pull 上游推到自己 GAR 的？** | 决定能改 base 还是必须换上游版本 |
| 3 | **GAR 仓库的「漏洞扫描 / 连续扫描 / SBOM 生成」现在开了哪些？** | 决定检测层要不要补 |
| 4 | **源码仓库在哪、用什么 CI（Jenkins / GitHub Actions / Cloud Build）、能不能跑 PR？** | 决定 skill 的交付形态和 Phase 2 的工作量 |

> 建议的第一次动手：**在 Phase 0.5 上花半天**，手工跑一次「升级 base → 重建 → 推 GAR → `gcloud artifacts docker images scan --remote` → 拿到结果」。
> 只要这一步通了，后面就是把 4 个 Phase 各自的机械动作脚本化 —— 那才是 AI 真正该干的活。
