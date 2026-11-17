# 个人版 ↔ 企业版 · 差异对照（差距是什么 / 值不值 / 怎么部署）

> **副标题**：把 [`examples/rulesets/`](../rulesets/)（个人版）和
> [`examples/rulesets-enterprise/`](../rulesets-enterprise/)（企业版）放在一起看，
> 回答三个问题：**① 差在哪 ② 差在哪值得不值得 ③ 我该从哪一步开始部署**。
>
> **一句话结论**
> 差距不在"规则更严"，而在**执行面**：
> 个人版的规则是**一个仓库一道门**（配错了只影响一个仓库），
> 企业版的规则是**整个组织一道门**（配错了全组织一起卡，而组织级 ruleset 只有 org owner 能改）。
> → 企业版换来的三样东西：**组织级治理面、服务端格式门禁（metadata）、push 阶段的内容门禁**。

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-tldr) | TL;DR：差距的 6 句话 |
| [§1](#1-先分清三种版) | 先分清三种"版"（User / Team / Enterprise） |
| [§2](#2-能力对照表（rule-type-级别）) | ★ 能力对照表（rule type 级）+ 每条值不值 |
| [§3](#3-治理模型差异（谁能改--叠加--豁免--审计）) | 治理模型差异：谁能改 / 叠加 / 豁免 / 审计 |
| [§4](#4-失败模式差异) | ★ 失败模式差异：为什么企业版"配错一次"贵得多 |
| [§5](#5-成本与收益) | 成本与收益：钱花在哪、改造量多大、运维量多大 |
| [§6](#6-决策树你们该走哪条路) | 决策树：你们该走哪条路 |
| [§7](#7-迁移路径（个人版已有的怎么平移）) | ★ 迁移路径：个人版已有的东西怎么平移 |
| [§8](#8-常见误解) | 常见误解 |
| [§9](#9-关联文档) | 关联文档 |

---

## 0. TL;DR

1. **★ 最值钱的一条：治理面从"仓库"变成"组织"。**
   个人版改一条规则 = 改一个仓库；企业版改一条规则 = 改**所有仓库**。
   代价是**只有 org owner 能改**（连平台组自己都改不了）→ 熔断权限必须提前分配。

2. **★ 第二条：格式门禁从"CI 时刻"挪到"服务端 push 时刻"。**
   个人版：`commit_message_pattern` **用不了**（API 422 / UI 静默丢弃），
   只能靠 CI check 在 PR 上打红叉。
   企业版：GitHub 原生 metadata 规则，**push 那一刻就判**。

3. **★ 第三条：内容门禁（密钥 / 大文件 / 凭据）在 push 阶段就有了。**
   个人版的 `05-push-secrets.json` 在个人账号上**是装饰品**（push ruleset 不可用）。
   企业版它是真实生效的第一道防线。

4. **★ 第四条：失败模式变了。**
   个人版配错 = 一个仓库的门禁失效（静默）；企业版配错 = 全组织一起失效或一起卡死。
   → 企业版**必须**补上：能力实测（probe）+ 15 条契约校验 + 漂移检测 + 熔断 runbook。

5. **★ 第五条：metadata 规则的失败形态是"ref 不更新"，不是"push 被拒"。**
   开发者会看到"push 成功了但分支没动"。→ 企业版**强烈建议**装本地 hook，
   把反馈从"push 之后要改历史"提前到"commit 之前"。

6. **★ 第六条：企业版可以不要 CI。**
   个人版**必须**有 CI（否则格式完全没人管）；企业版有原生 metadata 规则，
   CI 退化成"给人看的信号"，是可选项。

---

## 1. 先分清三种"版"

| | **User（个人账号）** | **组织 + Team/Pro 计划** | **组织 + Enterprise** |
|---|---|---|---|
| 有组织吗 | ❌ 没有 | ✅ | ✅ |
| 组织级 ruleset | ❌ | ✅ | ✅ |
| 谁能改组织级 ruleset | —— | ★ org owner | ★ org owner |
| 仓库级 ruleset | ✅ | ✅ | ✅ |
| metadata 规则 | ❌ | ❌（私有仓库） | ✅ |
| push ruleset | ❌ | ❌ | ✅ |
| merge queue | ❌ | ❌（私有仓库） | ✅ |
| 我们的落地策略 | **走 CI 路线** | **走 CI 路线** | **走 metadata 路线**（+ CI 兜底） |

> ★ **公开仓库的 metadata 规则较宽松**（官方对 public repo 放开了不少能力），
> 上表按"**私有仓库**"这个最严格的口径写。
> → 无论你们是什么计划，**以 `probe-enterprise-capabilities.sh` 的实测结果为准**。

---

## 2. 能力对照表（rule type 级别）

### 2.1 基础门禁（两版都有）

| rule type | 个人版 | 企业版 | 我们用它做什么 |
|---|---|---|---|
| `pull_request` | ✅ | ✅ | 必须走 PR、reviewer 数、合并方式 |
| `deletion` / `non_fast_forward` | ✅ | ✅ | 禁删分支、禁强推 |
| `required_linear_history` | ✅ | ✅ | 线性历史（squash 的前提） |
| `required_status_checks` | ✅ | ✅ | `cr/prod-validation`（CR Check App 产出） |
| `required_deployments` | ✅ | ✅ | 部署环境必须成功 |

> 这一层**没有能力差距**，只有"下发面"差距：个人版逐仓库，企业版组织级一次下发。

### 2.2 ★ Enterprise 独有的能力（差距的主体）

| rule type | 个人版 | 企业版 | 解决什么问题 | 值不值 | 部署动作 |
|---|---|---|---|---|---|
| **`commit_message_pattern`** | ❌ | ✅ | CR 号格式在**服务端**强制 | ★★★★★ 这是企业版最核心的收益 | `02-org-commit-message-convention.json` |
| **`branch_name_pattern`** | ❌ | ✅ | 分支命名规范在服务端强制 | ★★★★☆ 规范类问题越早拦越省事 | `03-org-branch-name-convention.json` |
| **`tag_name_pattern`** | ❌ | ✅ | 发布 tag 命名规范 | ★★★☆☆ 发布可追溯 | `04-org-tag-name-convention.json` |
| **push ruleset**（`target: push`） | ❌ | ✅ | 密钥 / 大文件 / 凭据在**进仓库前**被挡 | ★★★★★ 一次配置，全组织生效 | `07-org-push-guard.json` |
| **`block_credential_changes`** | ❌ | ✅ | 扫描提交内容里的凭据 | ★★★★☆ 防"密钥推上去了才发现" | 同上 |
| **`merge_queue`** | ❌ | ✅ | 合入前批量跑 CI，避免"合一个坏一次" | ★★★★☆ 大团队值；小团队收益有限 | `06-org-merge-queue.json` |
| **`required_signatures`** | ❌ | ✅ | 生产分支必须签名提交 | ★★★☆☆ 取决于你们的合规要求 | `05-org-prod-branch-gate.json` |
| **`required_workflows`** | ❌ | ✅（GHEC） | 组织级强制"必须跑哪条 CI" | ★★★☆☆ 防"CI 被删了" | `08-org-required-workflows.json` |
| **code scanning ruleset** | ❌ | ✅（需 GHAS） | 扫描结果不过不许合 | ★★★☆☆ 取决于有没有买 GHAS | `09-org-code-scanning.json` |
| **Rule insights（规则命中统计）** | ❌ | ✅ | 度量"哪条规则最常被拦" | ★★★☆☆ 治理成熟后才有意义 | Org 设置页（无需配置） |

> ★ **`push ruleset` 是个人版最大的"假象"**：
> 个人版目录里也有 `05-push-secrets.json`，但在个人账号上
> **API 422 / UI 静默丢弃** → 它在个人版里**一条都不执行**。
> → 这是"个人版目录看起来很全、实际差很多"最典型的一处。

### 2.3 治理能力（非 rule type，但影响巨大）

| 能力 | 个人版 | 企业版 | 说明 |
|---|---|---|---|
| **改规则的权限** | 仓库 admin | ★ **组织级只有 org owner** | 企业版最大的组织约束 |
| **规则叠加** | 仓库级之间取最严 | 组织级 + 仓库级**取最严**（仓库级只能加严） | 仓库级永远不能"放松"组织级 |
| **豁免（bypass）** | 少用 | ★ **必须显式登记**（本目录 `bypassAllowlist`） | 企业版要求"豁免可见、可审计" |
| **按仓库分层** | ❌ | ✅ `repository_name` 模式 | 生产仓库严、沙箱仓库松 |
| **自定义属性筛选** | ❌ | ✅ `repository_property` | 按"是否生产库"这类标签自动分级 |
| **审计** | 仓库级历史 | ★ 组织级历史 + 审计日志（企业功能） | 出事能追到人 |
| **批量下发** | 脚本逐仓库 | ★ 脚本按分层批量 + GitOps | 省的是"重复劳动" |
| **漂移检测** | 自己写 | ★ 落地成 workflow | 有人改 UI 就报警 |

---

## 3. 治理模型差异（谁能改 / 叠加 / 豁免 / 审计）

### 3.1 谁能改

```
个人版：仓库 admin 就能改           → 改错了自己就能恢复
企业版：组织级 ruleset = org owner  → ★ 改错了要等 owner 恢复
```

> ★ **企业版必做的一件事**：**提前**把熔断权限交给值班的人。
> 否则一次误伤 = 组织级卡死 + 等 owner = 停摆。

### 3.2 叠加语义

```
GitHub 对同一分支上命中的所有 ruleset 取【并集】（最严的生效）
    组织级 org-baseline       （所有仓库的默认分支：PR + 1 reviewer）
  + 组织级 org-prod-branch-gate（生产仓库的 main：PR + 2 reviewer + CR Check + 签名）
  + 仓库级 repo-dev-branch-gate（dev：PR + 1 reviewer + ci/build-and-test）
  → 目标分支上最终生效的规则 = 以上全部
```

> ★ 所以企业版可以"**分层下发**"：
> 组织级给基线，仓库级给特例 —— **仓库级永远只能加严**。
> ★ 别指望用仓库级 ruleset 去"放松"组织级要求（那是不允许的）。

### 3.3 豁免

个人版很少用 bypass。企业版**必须**有（不然出事没法操作），但**必须留痕**：

```yaml
# enterprise-profile.yaml
bypassAllowlist:
  - actorId: 1234
    actorType: "Integration"      # 或 Team / User / RepositoryRole
    reason: "Dependabot 自动提交，无 CR 号"
```

> ★ 校验器（E10）会拒绝**没有登记**的 `bypass_mode: always` ——
> "谁都能绕过"和"只有登记过的才能绕过"差一个数量级。

### 3.4 审计

```
个人版：ruleset 的版本历史（仓库级）
企业版：组织级 ruleset 历史 + 组织审计日志 + 绕过记录（谁在什么时候绕过了哪条规则）
```

> ★ 熔断时用 `disabled` 而不是删除 —— 保留历史 = 保留证据。

---

## 4. 失败模式差异

### 4.1 个人版的失败模式

| 症状 | 根因 | 影响面 |
|---|---|---|
| ruleset 显示 active 但 `rules: []` | 非 Enterprise 静默丢弃 metadata 规则 | **一个仓库** |
| 合不了，但看不出为什么 | `pull_request.parameters` 字段不全 → 422 | 一个仓库 |
| 规则"配了但没生效" | 分支名不在 `ref_name.include` | 一个仓库 |

### 4.2 企业版的失败模式（★ 贵得多）

| 症状 | 根因 | 影响面 |
|---|---|---|
| 全组织默认分支同时卡死 | 组织级 `pull_request` 参数写错 / App 没跑过 check run | **所有仓库** |
| 全组织的门禁同时失效（最可怕） | metadata 规则被静默丢弃 → `rules: []` → 看起来 active | **所有仓库** |
| push ruleset 没生效 → 密钥进了仓库 | push ruleset 在你们计划上不可用（版本/计划问题） | **所有仓库** |
| 有人改了 UI，全组织放松了 | 没有漂移检测 | **所有仓库**，且发现延迟 |

### 4.3 企业版的四个防线（对应本目录的四个工具）

```
① 能力实测    probe-enterprise-capabilities.sh  → "我们到底支持哪些 rule type"
② 契约校验    validate-rulesets.py (E1–E15)    → "配置之间自不自洽"
③ 灰度下发    disabled → 联调 → active          → "先只在一个仓库上生效"
④ 漂移检测    workflows/rulesets-drift.yaml     → "有人绕过流程改了吗"
```

> ★ **顺序不能颠倒**：③ 之前一定要过 ①②。

---

## 5. 成本与收益

| 维度 | 个人版 | 企业版 |
|---|---|---|
| **订阅** | 免费 | ★ Enterprise Cloud 按 seat 计费 / GHES 自建年费 |
| **改造量** | 一个仓库 + 一个 workflow | 策略仓库 + `admin:org` token + 分层清单 + 熔断 runbook |
| **日常运维** | 几乎无 | ★ 漂移检测（每天）、熔断值班、能力升级核对（GHES 升级可能改变可用能力） |
| **组织约束** | 无 | ★ 组织级 ruleset 只有 owner 能改 |
| **收益** | 一个仓库的门禁 | ★ 全组织的门禁 + 格式在服务端强制 + 内容在 push 阶段被挡 + 可度量 |
| **风险** | 配错 = 一个仓库 | ★ 配错 = 全组织 |

> ★ **决策要点**：
> 如果你们只有 1–2 个仓库、2–3 个人，**Enterprise 不划算**——
> 个人版的 CI 路线已经能覆盖"格式 + 必须走 PR + 必须过 CI"这三件事。
> Enterprise 的价值在**仓库数 × 人数**上来之后才明显。

---

## 6. 决策树：你们该走哪条路

```
你们是个人账号 / 没有组织？
└─ 是 → 走个人版（examples/rulesets/）
        ★ 05-push-secrets.json 不可用，别浪费时间
        ★ 格式门禁只能靠 CI

你们有组织，但只有 Team/Pro 计划？
└─ 是 → 走个人版的组织级部分（01 可以升到 org 级）
        ★ metadata / push ruleset 仍不可用
        ★ 格式门禁只能靠 CI
        → 本目录的 02/03/04/07/08/09 全部不能用（会 422 或静默失效）

你们是 Enterprise Cloud / GHES？
└─ 是 → ★ 先跑探针（probe-enterprise-capabilities.sh）
        → 按探针结果，只开启"可用"的那些 ruleset
        → 按 enterprise-rollout.md 分阶段下发
```

---

## 7. 迁移路径（个人版已有的怎么平移）

| 个人版文件 | 企业版对应 | 变化 |
|---|---|---|
| `01-org-baseline.json` | `01-org-baseline.json` | 基本一致（企业版多 `required_review_thread_resolution`） |
| `02-repo-dev-branches.json` | `10-repo-dev-branches.json` | 一致 |
| `03-repo-release-branches.json` | `11-repo-release-branches.json` | 一致 |
| `04-repo-prod-branches.json` | `05-org-prod-branch-gate.json` | ★ **从仓库级升到组织级** + 加签名 + 按仓库分层 |
| `05-push-secrets.json` | `07-org-push-guard.json` | ★ **个人版里是死规则**（不可用）→ 企业版才真正生效；加凭据扫描 |
| `06-repo-feature-conventions.json` | `12-repo-feature-conventions.json` | ★ 去掉 `cr-prefix` check（企业版由 metadata 规则管格式） |
| `07-commit-message-cr-prefix-protected.json` | `02-org-commit-message-convention.json` | ★ **从"CI check"变成"服务端 metadata 规则"** |
| `workflows/cr-prefix-check.yaml` | `workflows/cr-prefix-check.yaml` | 保留，但从"必需"降级为"可选体验层" |
| `commit-msg-hook.sh` | `commit-msg-hook.sh` | ★ 正则改为从企业版 ruleset 里读（同源） |
| `apply-rulesets.sh` | `apply-rulesets.sh` | ★ 变成"组织级 + 按分层批量 + profile 驱动" |
| `validate-rulesets.py`（C1/C2/C3） | `validate-rulesets.py`（E1–E15） | ★ 从 3 条契约扩到 15 条（多了能力/一致性/治理） |
| —— | `03/04/…-branch-name / tag-name` | ★ **企业版新增**（个人版没有对应能力） |
| —— | `06-org-merge-queue.json` | ★ 企业版新增 |
| —— | `08/09-…required-workflows / code-scanning` | ★ 企业版新增（可选） |
| —— | `probe-enterprise-capabilities.sh` | ★ 企业版新增（个人版靠"实测踩坑"，企业版靠探针） |
| —— | `workflows/rulesets-drift.yaml` | ★ 企业版新增（个人版的漂移在 runbook 里只是模板） |

### 7.1 平移时最容易踩的三处

1. **CI check 变成 metadata 规则后，失败形态变了**
   个人版：PR 上一个红叉（清楚）。
   企业版：push 时 **ref 不更新**（"push 成功了但分支没动"，开发者一脸懵）。
   → **必须**同时装 `commit-msg-hook.sh` + `branch-name-hook.sh`。

2. **组织级 ruleset 配错 = 全组织卡死**
   → 永远先 `disabled`，永远先在**一个测试仓库**上联调。

3. **squash 的坑一模一样**
   → PR 标题也必须带 CR 前缀。个人版就踩过，企业版不会免疫。

---

## 8. 常见误解

| # | 误解 | 事实 |
|---|---|---|
| 1 | "买了 Enterprise，metadata 规则就一定能用" | ★ **不一定**：还取决于 GHES 版本 / 公开还是私有仓库 → **先跑探针** |
| 2 | "个人版的 `05-push-secrets.json` 在个人账号上也有用" | ❌ push ruleset 不可用 → **静默丢弃**，一条都不执行 |
| 3 | "UI 导入不报错 = 规则生效了" | ❌ UI 会**静默丢弃**不认识的 rule type → ruleset 变空壳 |
| 4 | "仓库级 ruleset 可以放松组织级要求" | ❌ 只能**加严** |
| 5 | "metadata 规则会把 push 拒绝掉" | ❌ 是 **ref 不更新**（commit 变 unreachable） |
| 6 | "企业版可以把 CI 删了" | 可以，但**删了就没"看得见的失败"** → 建议留作体验层 |
| 7 | "组织级 ruleset 我们平台组自己就能改" | ❌ 只有 **org owner** |
| 8 | "加了 ruleset 就等于安全了" | ❌ metadata 只管**格式**，真实性（CR 号存在吗）仍要 **CR Check App** |
| 9 | "签名提交 = 身份可信" | 只保证**未被篡改**，不保证**提交者身份**（那要看签名密钥管理） |
| 10 | "merge queue 能替代 required checks" | ❌ 两者都要；queue 解决的是"合一个坏一次" |

---

## 9. 关联文档

| 主题 | 文档 |
|---|---|
| ★ 企业版规则集（本目录） | [`examples/rulesets-enterprise/`](../rulesets-enterprise/) |
| ★ 企业版能力矩阵 / GHES 版本 | [`00-enterprise-capabilities.md`](../rulesets-enterprise/00-enterprise-capabilities.md) |
| ★ 企业版落地步骤 | [`enterprise-rollout.md`](../rulesets-enterprise/enterprise-rollout.md) |
| 个人版规则集（对照基准） | [`examples/rulesets/`](../rulesets/) |
| Ruleset × GitHub App 完整方案 | [`git-apps/14-rulesets-and-gitapp-gate.md`](../../git-apps/14-rulesets-and-gitapp-gate.md) |
| commit message 规范原理（含 squash 语义） | [`git-apps/15-commit-message-cr-prefix.md`](../../git-apps/15-commit-message-cr-prefix.md) |
| 安装 Runbook（通用，含报错对照表） | [`git-apps/16-ruleset-install-runbook.md`](../../git-apps/16-ruleset-install-runbook.md) |
