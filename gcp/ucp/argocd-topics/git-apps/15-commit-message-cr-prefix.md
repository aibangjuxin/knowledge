# 15 · 最小示例：commit message 必须以 `CR123456` 开头（Ruleset 怎么配）

> **副标题**：一个能直接抄的最小方案 —— 两条 Ruleset + 一个本地 hook + 三层判定模型。
>
> **一句话结论**
> **格式**由 GitHub Ruleset 的 `commit_message_pattern` 强制，
> **真实性**（这个 CR 号真的存在、已批准、目标环境对得上）由我们的 **CR Check（GitHub App）** 强制。
> 两层缺一不可：只配 Ruleset → 谁都能编一个 `CR999999` 混过去；
> 只配 App → 格式千奇百怪，脚本没法解析。
>
> **前置阅读**
> [`14-rulesets-and-gitapp-gate.md`](./14-rulesets-and-gitapp-gate.md)（Ruleset 零基础 + 与 App 的耦合）、
> [`13-cr-check-go-design.md`](./13-cr-check-go-design.md)（R1–R13a 规则表）、
> [`cr-check/`](./cr-check/)（可运行实现）。

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-tldr) | TL;DR：8 条结论 |
| [§1](#1-需求与两个例子) | **需求 + 两个例子**（正例 / 反例） |
| [§2](#2-三层判定模型l1--l2--l3) | 三层判定模型：L1 本地 hook / L2 Ruleset / L3 CR Check App |
| [§3](#3-怎么落地两条路线先选对再动手) | **怎么落地：两条路线**（metadata 规则 vs CI check）+ 两条 ruleset JSON |
| [§4](#4-正则怎么写re2) | 正则怎么写：RE2 / `^` / `$` / 无 lookahead / `operator: regex` |
| [§5](#5-三个必须知道的官方事实) | ★ **三个必须知道的官方事实**（计划限制 / squash 语义 / push 语义） |
| [§6](#6-与-cr-check-app-的分工) | 与 CR Check App 的分工 + R1 解析器扩展（可选） |
| [§7](#7-本地模拟不连-github-就能跑) | **本地模拟**：模拟器 + commit-msg hook |
| [§8](#8-落地步骤与验收) | 落地步骤与验收 |
| [§9](#9-没有-enterprise-时的降级方案★-个人账号直接看这里) | 没有 Enterprise 时的降级方案（★ 个人账号直接看这里） |
| [§10](#10-坑清单) | 坑清单 |
| [§11](#11-关联文档) | 关联文档 |

---

## 0. TL;DR

1. **你的例子完全可用**：`CR123456 release: pfb-gcp-v0.1.0: github app`
   → 对应的规则是 `commit_message_pattern`，模式 = `^CR[0-9]{6}(\s|$)`。

2. **但要注意大小写**：`cr123456` 不通过（GitHub 的 RE2 默认区分大小写）。
   要兼容小写就把模式写成 `^[Cc][Rr][0-9]{6}(\s|$)` —— 建议不要，**统一大写更好审计**。

3. **★ 最容易踩的坑不是正则，是 squash merge。**
   官方明确：squash 合并时校验的是**合并后那个 commit 的 message**（默认 = `PR 标题 + (#PR号)`）。
   → **所以 PR 标题也必须以 `CR123456` 开头**，否则你会遇到"每个 commit 都合规，合并却被拒"。

4. **★ 第二个坑：这条规则需要 GitHub Enterprise 计划。**
   官方原文："Organizations on a GitHub Enterprise plan can access additional rules to control how commit metadata must be formatted."
   → Team 计划请看 [§9 降级方案](#9-没有-enterprise-时的降级方案★-个人账号直接看这里)（CI check / PR 标题模板 / label）。

5. **★ 第三个坑：push 不会被拒绝，是"分支指针不更新"。**
   官方原文：*"the push is not rejected, but the branch or tag they are targeting is not updated"*
   → 提交会进仓库但 **unreachable**（能通过 URL 访问、不在分支历史里）→ 必须 rebase 改历史才能推上去。

6. **两层强制，缺一不可**：

   | 层 | 管什么 | 谁实现 |
   |---|---|---|
   | 格式 | `CR` + 6 位数字开头 | Ruleset `commit_message_pattern` |
   | 真实性 | 这个 CR 存在吗？已批准吗？环境对吗？ | CR Check App（R1–R7） |

7. **建议配两条 Ruleset**：
   `feature/**`（push 时就拦，给开发者即时反馈）+ `main` / `release/**`（merge 前的最终兜底）。
   官方提醒：metadata 规则**会增加摩擦**，只施加在有限分支上。

8. **本地 hook 不是替代品，是加速器**：
   服务端规则是权威（本地 hook 可以没有、可以被绕过），本地 hook 只是把反馈从"push 时"提前到"commit 时"。

---

## 1. 需求与两个例子

### 1.1 规则定义

```
每个 commit 的 subject（第一行）必须匹配：  ^CR[0-9]{6}(\s|$)

含义：CR + 恰好 6 位数字，后面要么是空白，要么就是结尾。
```

| 项 | 值 |
|---|---|
| CR 号形态 | `CR` + 6 位数字（`CR123456`） |
| 位置 | **subject 开头**（不是 commit trailer） |
| 后面接什么 | 任意描述（例：`release: pfb-gcp-v0.1.0: github app`） |
| 大小写 | **必须大写 `CR`**（RE2 默认区分大小写） |
| 适用分支 | `feature/**`（提前拦）+ `main` / `release/**`（merge 前兜底） |

> ⚠️ **与现有 `policy.yaml` 的差异**：
> 现在 CR Check 的 R1 只认三个载体：`label cr/1234` / body 的 `Change-Request: 1234` / commit trailer。
> 你这个 `CR123456 release: ...` 是**第四种载体**（subject 前缀），
> 落地时需要扩展解析器（[§6.2](#62-可选增强让-r1-也认-cr-前缀)）。

### 1.2 ★ 两个例子

#### 例子 A · 正例

```bash
git commit -m "CR123456 release: pfb-gcp-v0.1.0: github app"
```

| 层 | 结果 | 说明 |
|---|---|---|
| L1 本地 hook | ✅ | subject 匹配 `^CR[0-9]{6}(\s|$)` |
| L2 Ruleset | ✅ | commit message 满足模式；push 正常更新 ref |
| L3 CR Check App | ✅ | 解析出 CR 号 `123456` → 查 CR 平台 → 存在 / `implement` / 2 位审批人 / 目标环境匹配 → 写绿勾 |
| squash merge | ✅ | 最终 commit message = `CR123456 release: pfb-gcp-v0.1.0: github app (#42)` → 仍匹配 |

#### 例子 B · 反例

```bash
git commit -m "release: pfb-gcp-v0.1.0: github app"     # ← 缺 CR 前缀
```

| 层 | 结果 | 说明 |
|---|---|---|
| L1 本地 hook | ❌ 拦截 | commit 阶段就报错，提示正确格式 |
| L2 Ruleset | ❌ 拦截 | `git push` 时 **ref 不更新**（commit 变成 unreachable） |
| L3 CR Check App | ❌ 拦截 | PR 上没有 `cr/prod-validation` 绿勾 → 合不了 |
| squash merge | ❌ | — |

> ★ **注意 L2 的失败形态**：
> 不是 "push 被拒绝"，而是"**push 成功但分支没动**"。
> 新手看到 `git push` 报了个奇怪的错、但 `git log` 里没有自己的 commit，多半就是撞上了这条规则。

#### 例子 C · 格式对、CR 号是假的（★ 只有 L3 能拦）

```bash
git commit -m "CR999999 release: pfb-gcp-v0.1.0: github app"
```

| 层 | 结果 | 说明 |
|---|---|---|
| L1 / L2 | ✅ **都过** | 格式完全合法 —— 谁都能编一个号 |
| L3 CR Check App | ❌ | "变更单 999999 在 CR 平台上不存在" |

> ★ **这就是"格式"和"真实性"必须分两层的原因**。
> Ruleset 只认字符串形状；只有查了中央 CR 平台的 App 才知道这个号是不是真的。

---

## 2. 三层判定模型（L1 / L2 / L3）

```
   开发者 git commit -m "CR123456 ..."
        │
        ├─ L1 本地 commit-msg hook ─────────► 秒级反馈（可绕过，不是权威）
        │
   git push
        │
        ├─ L2 GitHub Ruleset ──────────────► 服务端权威：ref 不更新 / merge 被拒
        │     commit_message_pattern
        │
   开 PR → 标题也要带 CR 前缀（squash 会用它生成最终 commit message）
        │
        ├─ L3 CR Check (GitHub App) ───────► 写 check run：CR 真伪 / 状态 / 审批 / 窗口
        │
   点 Merge
        │
        └─ GitHub 平台逐条评估：L2 的所有规则 + L3 产出的那个绿勾
             → 全过才放行
```

| 层 | 谁实现 | 权威性 | 失败形态 | 覆盖的能力 |
|---|---|---|---|---|
| **L1** | `.githooks/commit-msg` | ❌ 非权威（可绕过） | commit 被拒 | 提前反馈 |
| **L2** | Ruleset `commit_message_pattern` | ✅ **权威** | ref 不更新 / merge 拒绝 | **格式** |
| **L3** | CR Check App | ✅ **权威** | check 变红 | **真实性** |

> ★ **一句话**：**L1 让人别犯错，L2/L3 让人错不了。**
> 只有 L2/L3 才是门禁；L1 只是体面。

---

## 3. 怎么落地：两条路线，先选对再动手

> ★ **动手前先确认你在哪条路线上** —— 选错会白干：
>
> | | 路线 A · **metadata 规则** | 路线 B · **CI check**（通用） |
> |---|---|---|
> | 能力 | `commit_message_pattern` | GitHub Actions job |
> | 可用条件 | ★ **Enterprise 计划 + 组织账号** | **所有计划 + 个人账号** |
> | 拦截时机 | push（ref 不更新）/ merge | PR 打开/更新时（status check 变红） |
> | 产出 | ruleset 直接含格式规则 | check `cr-prefix` → 被 `required_status_checks` 引用 |
> | 状态 | 若不满足可用条件 → **UI 导入会静默丢弃**（ruleset 变空壳） | 总是可用 |
>
> ★ **实测结论（非 Enterprise 个人账号）**：
> `commit_message_pattern` / `branch_name_pattern` / `merge_queue` / push ruleset
> → API 直接 `422 Invalid rule`；**UI 导入则静默丢弃** → ruleset 显示 active 但 `rules: []` → 什么都不拦。
> 详见 [`16-ruleset-install-runbook.md`](./16-ruleset-install-runbook.md) §2.5。

### 3.1 路线 B（通用，推荐先走这条）· CI check + required_status_checks

三件套：

```
① CI workflow   → examples/rulesets/workflows/cr-prefix-check.yaml
② ruleset       → examples/rulesets/06-repo-feature-conventions.json（功能分支）
                   examples/rulesets/07-commit-message-cr-prefix-protected.json（主分支）
③ 绑定          → ruleset 的 required_status_checks 写 {"context": "cr-prefix"}
```

**为什么这样组合**：

| 层 | 谁实现 | 权威性 |
|---|---|---|
| 格式（`^CR[0-9]{6}`） | CI 的 `cr-prefix` check | ✅ 服务端、不可绕过（PR 不绿就合不了） |
| 真实性（CR 存在/已批准） | CR Check App 的 `cr/prod-validation` | ✅ 服务端 |

> ★ 两条 required status check 各管一件事，互不替代：
> `cr-prefix` 管**格式**，`cr/prod-validation` 管**真假**。

**一键安装（CI workflow + PR）**：

```bash
cd examples/rulesets

# ⚠️ 需要 workflow scope（GitHub 不允许用没有该 scope 的 token 创建 .github/workflows/）
gh auth refresh -s workflow

# 建分支 + 提交 workflow + 开 PR
./install-ci-check.sh --owner <owner> --repo <repo>
```

**两条 ruleset 的关键内容**（完整文件见上面的链接）：

```jsonc
// 07-commit-message-cr-prefix-protected.json（主分支）
{
  "name": "main-branch-guard",
  "target": "branch",
  "enforcement": "disabled",              // ★ 先 disabled，CI 进 main 后再 active
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash", "merge"] } },
    { "type": "required_status_checks", "parameters": {
        "required_status_checks": [ { "context": "cr-prefix" } ],
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": true } }
  ]
}
```

> ★ **`pull_request.parameters` 的字段必须齐全**（少一个 → API 422，报错信息完全看不出缺什么）。
> 上面这 5 个字段是官方 schema 里的必填项。

### 3.2 路线 A（Enterprise 组织）· metadata 规则

如果你们有 Enterprise 组织账号，直接用 metadata 规则（更省事、不用维护 CI）：

```jsonc
// 组织级 ruleset（★ conditions 必须同时含 repository_name + ref_name）
{
  "name": "commit-message-cr-prefix-protected",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "repository_name": { "include": ["platform-*"], "exclude": [] },
    "ref_name": { "include": ["refs/heads/main"], "exclude": [] }
  },
  "rules": [
    { "type": "commit_message_pattern", "parameters": {
        "name": "commit message 必须以 CR<6位数字> 开头",
        "negate": false,
        "operator": "regex",
        "pattern": "^CR[0-9]{6}(\\s|$)" } }
  ]
}
```

下发（组织级端点）：

```bash
cd examples/rulesets
CR_CHECK_APP_ID=<App ID> ./apply-rulesets.sh --scope org --owner <org>
```

### 3.3 两条路线的对比

| | 路线 A（metadata） | 路线 B（CI） |
|---|---|---|
| 拦截"本地提交" | ❌ 拦不到（本地 commit 是纯本地动作） | ❌ 同样拦不到 |
| 拦截"不合规 push" | ✅ ref 不更新 | ⚠️ 不拦 push（CI 只在 PR 上跑）→ 靠 `pull_request` 规则保证只能经 PR 合入 |
| 拦"不合规的 PR" | ✅ merge 被拒 | ✅ check 变红，merge 被拒 |
| 需要额外维护 | 无 | 一个 workflow 文件 |
| 需要什么权限 | Enterprise 组织 owner | 仓库 admin + `workflow` scope |

> ★ **建议两条一起上**：
> 路线 A 拦 push，路线 B 拦 PR；两者都失效时，L1 本地 hook 兜底。

---

## 4. 正则怎么写（RE2）

### 4.1 GitHub 的正则约束（官方原文核对）

| 约束 | 官方说法 | 对我们的影响 |
|---|---|---|
| **引擎是 RE2**（Go 正则） | "Rulesets support RE2 syntax" | 不能用反向引用；用 Python/PCRE 写的规则可能在这里行为不同 |
| **默认不跨行** | "regular expressions in metadata restrictions do not consider multiple lines of text" | `^` 匹配**整个 message 的开头**（= subject 开头）✅ 正好我们要的 |
| **要跨行得显式加 `(?m)`** | "start your expression with `(?m)`" | 我们不需要 |
| **不支持负向预查 `?!`** | "The negative lookahead assertion, denoted `?!`, is not supported" | ★ 别写 `(?!release)` 这种；要用"必须不含"请用 `negate: true` + "Must not match" |
| **正向前瞻 `?` 支持** | "you can use the positive lookahead assertion" | 可用但我们不需要 |
| **行尾锚点用 `\n?$` 而不是 `$`** | "use `\n?$` rather than `$` alone" | 我们用 `(\s|$)`，其中 `\s` 已经覆盖了"后面有内容"的情况 |
| **正则默认关闭** | "Metadata restrictions do not accept regex patterns by default. To enable this, select the *Must match a given regex pattern*" | API 里 = `operator: "regex"` |

### 4.2 我们的模式为什么是 `^CR[0-9]{6}(\s|$)`

```
^            开头（RE2 默认不跨行 → 就是 subject 开头）
CR           字面量，大写
[0-9]{6}     恰好 6 位数字
(\s|$)       后面必须是空白或结束
             → "CR123456" 合法
             → "CR123456xxx" 不合法（没有分隔）
             → "CR12345" 不合法（只有 5 位）
```

> ⚠️ **一个容易犯的错**：写成 `^CR[0-9]+` 就放行了 `CR1`、`CR123`。
> **位数必须是 `{6}`** —— 位数是 CR 号体系的一部分。

### 4.3 常见变体

| 需求 | 模式 |
|---|---|
| 允许大小写 | `^[Cc][Rr][0-9]{6}(\s|$)` |
| 要求必须有描述 | `^CR[0-9]{6}\s+\S` |
| 要求描述里也带版本号 | `^CR[0-9]{6}\s+.*release:\s+\S+` |
| **只要包含** CR 号（不要求开头） | `CR[0-9]{6}`（去掉 `^`） |

---

## 5. ★ 三个必须知道的官方事实

### 5.1 事实一：metadata 规则需要 GitHub Enterprise 计划

官方原文（About rulesets · Available rules）：

> *"Organizations on a GitHub Enterprise plan can access additional rules to control how commit metadata must be formatted."*

| 能力 | 个人账号（User） | Team 计划（组织） | Enterprise 计划（组织） |
|---|---|---|---|
| 仓库级 ruleset（PR / status check / 禁直推…） | ✅ | ✅ | ✅ |
| **组织级 ruleset** | ❌（个人账号没有组织） | ✅ | ✅ |
| **commit message / 分支名 / tag 名 元数据规则** | ❌ | ❌ | ✅ |
| **merge queue 规则** | ❌ | ❌ | ✅（私有仓库） |
| **push ruleset（禁密钥扩展名…）** | ❌ | ❌ | ✅ |

> ★ **实测（个人账号，非 Enterprise）**：
> `commit_message_pattern` / `branch_name_pattern` / `merge_queue` / push ruleset
> → API 直接 `422 Invalid rule`；
> **UI 导入则静默丢弃** → ruleset 显示 `active` 但 `rules: []` → **什么都不拦**。
> → 所以个人账号请走 [§3.1 路线 B（CI check）](#31-路线-b通用推荐先走这条--ci-check--required_status_checks)。

> ★ **这是本方案最大的前置条件**。没有 Enterprise → 走 [§9 降级方案](#9-没有-enterprise-时的降级方案★-个人账号直接看这里)。

### 5.2 事实二：squash merge 时到底校验谁（★ 最容易踩）

官方文档里有两段描述，**指向不同结论**，必须都看：

> **（Note，位于 Metadata restrictions 章节开头）**
> *"If you squash merge a branch, all commits on that branch must meet any metadata requirements for the base branch."*

> **（Important considerations，同章节更靠后）**
> *"If you use squash merges, the individual commits in the pull request are ignored. Instead, restrictions are only validated against the metadata of the single, resulting merge commit. The pull request page validates this information before the merge is allowed, ensuring the final commit is compliant."*

**两段合起来读，安全结论是**：

```
① base 分支（如 main）的 metadata 规则在 merge 那一刻一定会被校验   ← 两段都同意
② 被校验的对象是"最终那个 commit message"（squash 的结果）              ← 后一段明确
③ 因此：最终 commit message = PR 标题 + " (#PR号)"（GitHub 默认）
   → ★ PR 标题必须带 CR 前缀
```

> ★ **这解释了一个高频困惑**：
> "我每个 commit 都合规，为什么 PR 还是合不了？"
> 答案：**PR 标题没带 `CR` 前缀**。squash 时 GitHub 用 PR 标题生成最终 commit message，
> 那个 message 不合规 → 合并被拦。

**应对（两条，一起做）**：

```
① PR 模板里把标题写死成：  CR<编号> <描述>
   （GitHub 的 PR 模板支持 {{title}} 前缀，或用组织级模板强制）
② 或者在合并时手工编辑 commit message（GitHub squash 合框里有 "Edit commit message"）
   —— 但这依赖人 remembering，★ 不推荐当唯一手段
```

### 5.3 事实三：push 时不是"拒绝"，而是"ref 不更新"

官方原文：

> *"Metadata restrictions block 'ref updates.' If a contributor pushes work that includes a commit that doesn't meet the requirements, **the push is not rejected, but the branch or tag they are targeting is not updated**. Technically, the commits still enter your repository: the commits will be 'retrievable' … but not 'reachable'."*

**对开发者的实际影响**：

```
git push
  → git 报错（类似 "remote: refusing to update ref" / "pre-receive hook declined"）
  → 但 git log origin/feature/x 里 **看不到** 自己的 commit
  → commit 其实已经在 GitHub 上了（能通过 URL 访问），只是不在分支历史里
  → 要修：git commit --amend 改 message（或 rebase 整条链）再 push
```

> ★ **这条规则不追溯存量历史**：
> 官方明确 *"they are not enforced against the existing history"*。
> → 加规则前的老 commit 不用清洗 ✅。

---

## 6. 与 CR Check App 的分工

### 6.1 分工表

| 关注点 | 谁来管 | 理由 |
|---|---|---|
| CR 号的**字符串形状**（`CR` + 6 位） | **Ruleset** `commit_message_pattern` | 纯格式，GitHub 原生就能判 |
| CR 号**是否真实存在** | **CR Check App**（R2） | 只有中央 CR 平台知道 |
| CR 是否**已批准/可执行** | **CR Check App**（R3/R4） | 同上 |
| CR 的**目标环境**是否匹配分支 | **CR Check App**（R5） | 同上 |
| 是否在**维护窗口**内 | **CR Check App**（R6w） | Ruleset 没有时间维度 |
| commit message 的**其余部分**（描述质量） | **CI / 人工评审** | Ruleset 只管开头那串 |

> ★ **别把"真实性"塞进 Ruleset**：
> Ruleset 是静态字符串匹配，它查不了你的 CR 平台。

### 6.2 （可选增强）让 R1 也认 `CR` 前缀

现在 [`cr-check/internal/rules/extract.go`](./cr-check/internal/rules/extract.go) 只认
`label cr/1234` / body marker / trailer 三种载体。
若要把 `CR123456` 前缀作为**第四种载体**，最小改动是：

**① `policy.yaml` 加一段**：

```yaml
cr:
  # ★ 新增：subject 前缀载体（与 Ruleset 的 commit_message_pattern 保持一致）
  subjectPattern: "^CR([0-9]{6})(\\s|$)"
```

**② `extract.go` 加一个解析器**（示意）：

```go
// 在 ExtractCRNumbers 里追加：subject 前缀
if subjectPattern != "" {
    if re, err := regexp.Compile(subjectPattern); err == nil {
        if m := re.FindStringSubmatch(subject); m != nil {
            out.add(strings.TrimSpace(m[1]), "subject")
        }
    }
}
```

**③ 调用方把 PR 的 commit subject 传进来**（需要 webhook handler 拉一次 commit 列表，
或直接用 `pull_request` 事件里的 `pull_request.head.sha` 调 `GET /repos/{o}/{r}/commits/{sha}`）。

> ⚠️ **代价与收益**：
> - 收益：不用再让开发者手动贴 `cr/1234` label / 改 PR 模板；commit 里一个号搞定。
> - 代价：多一次 GitHub API 调用；**多一个载体 = 多一处冲突来源**（R1a 唯一性检查会更常报错）。
> - ★ **建议**：**label 仍然是主载体**（最机读、最好审计），
>   subject 前缀作为**兜底/辅助**（人看得见、部署侧 `git log` 能追溯）。
>   两者不一致时**必须报冲突**，不能静默取优先级。

---

## 7. 本地模拟（不连 GitHub 就能跑）

### 7.1 模拟器：三层判定一起看

文件：[`examples/rulesets/simulate-commit-gate.py`](../examples/rulesets/simulate-commit-gate.py)

```bash
cd examples/rulesets

# 跑两个正反例
python3 simulate-commit-gate.py

# 跑全部内置例子（含"格式对但 CR 号是假的"）
python3 simulate-commit-gate.py --all

# 试自己的 message
python3 simulate-commit-gate.py "CR123456 release: pfb-gcp-v0.1.0: github app"
```

它做三件事：

```
① 从 07-*.json 里**读出** commit_message_pattern 的正则（单一真相源，改 JSON 即刻生效）
② 依次跑 L1（hook 同样的正则）/ L2（Ruleset）/ L3（模拟查 CR 平台的假数据）
③ 额外模拟 squash merge：把 PR 标题拼成 "标题 (#42)" 再判一次
   → 专门用来暴露"commit 合规但 PR 标题不合规"的坑
```

> ★ **模拟器与 Ruleset 共用同一份正则** → 不会出现"文档写的和配置跑的不一样"。
> 退出码：内置例子全部符合预期 → `0`；否则 `1`（可以直接进 CI）。

### 7.2 本地 commit-msg hook

文件：[`examples/rulesets/commit-msg-hook.sh`](../examples/rulesets/commit-msg-hook.sh)

```bash
# 安装到仓库（推荐用 core.hooksPath，不污染 .git/hooks）
mkdir -p .githooks
cp examples/rulesets/commit-msg-hook.sh .githooks/commit-msg
chmod +x .githooks/commit-msg
git config core.hooksPath .githooks
```

效果：

```
$ git commit -m "release: pfb-gcp-v0.1.0: github app"

✗ commit message 不合规

  你的 subject : release: pfb-gcp-v0.1.0: github app
  要求的格式  : CR<6位数字> <任意描述>

  ✅ 正确示例  : git commit -m "CR123456 release: pfb-gcp-v0.1.0: github app"
  ...
```

> ★ **hook 的正则必须与 Ruleset 逐字符一致**（`^CR[0-9]{6}(\s|$)`）。
> 两边不一致 → 开发者本地过了、服务器不过 → 白折腾。
> → 可以把这条一致性也做成断言（`validate-rulesets.py` 目前只校验 ruleset 侧）。

> ⚠️ **本地跳过 ≠ 服务端放行**：
> `SKIP_CR_PREFIX=1 git commit -m "..."` 只跳过本地检查，**GitHub 侧照样拦**。
> 这是设计如此 —— 本地 hook 不是安全边界。

---

## 8. 落地步骤与验收

| 步 | 做什么 | 验收 |
|---|---|---|
| **1** | 确认计划支持 metadata 规则（Enterprise） | UI 里新建 ruleset 能看到 "Restrict commit metadata" |
| **2** | 定死 CR 号形态（位数、大小写） | 写入 `policy.yaml` 的 `subjectPattern`，两边一致 |
| **3** | 建 Ruleset（先 `enforcement: disabled`） | `gh api orgs/<org>/rulesets` 能查到 |
| **4** | 装本地 hook | 手写一个不合规 message → commit 被拒 |
| **5** | 配 PR 模板：标题前缀 `CR<编号> <描述>` | 新建 PR 时标题已带前缀 |
| **6** | 联调（★ 必做） | ① 不合规的 PR → 合不了；② 合规的 PR → 能合；③ **PR 标题不带前缀** → 确认被拒 |
| **7** | 改 `active` | 同上再验一次 |
| **8** | 观察一周 | 不合规的 push 次数、`git log` 里 unreachable commit 的数量 |

### ★ 验收脚本（第 6 步的具体做法）

```bash
# ① 建一个不合规的分支
git checkout -b feature/CAEP-0001-test-cr-prefix
echo "x" > README.tmp && git add README.tmp
git commit -m "test: 不带 CR 前缀"          # ← 本地 hook 应直接拒绝
# 若你还没装 hook，绕过它：
SKIP_CR_PREFIX=1 git commit -m "test: 不带 CR 前缀"
git push -u origin feature/CAEP-0001-test-cr-prefix
#   → 预期：push 报错，且 origin/feature/CAEP-0001-test-cr-prefix 没有这个 commit

# ② 改成合规的再推
git commit --amend -m "CR123456 test: 带 CR 前缀"
git push -u origin feature/CAEP-0001-test-cr-prefix
#   → 预期：正常推送

# ③ 开 PR，标题故意不带前缀
#   → 预期：★ merge 被拒（squash 后的 commit message 不合规）
# ④ 改标题为 "CR123456 test: 带 CR 前缀" 再合
#   → 预期：合入
```

---

## 9. 没有 Enterprise 时的降级方案（★ 个人账号直接看这里）

| 方案 | 做法 | 强度 | 成本 |
|---|---|---|---|
| **A. CI check**（★ 个人账号的唯一可行路径） | GitHub Actions 里一个 job 遍历 PR 的 commit message，不合规就 `exit 1` → 产生 status check → 用 `required_status_checks` 强制 | ★ 与 Ruleset 等价（服务端、不可绕过） | 一个 20 行的 workflow |
| **B. PR 标题模板** | 组织级 PR 模板把标题前缀写死；不靠机器校验，靠流程 | 弱（人可改） | 零 |
| **C. label 载体** | 沿用现有 R1 的 `cr/1234` label，不动 commit message | 中（label 也能被改，但改动会在 PR 里留痕） | 零 |
| **D. 本地 hook 单独用** | 只有 L1，无服务端强制 | 弱（可绕过） | 零 |

> ★ **方案 A 的最小 workflow**：

```yaml
# .github/workflows/cr-prefix.yaml
name: cr-prefix
on: pull_request
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: 校验每个 commit 的 subject
        run: |
          bad=$(git log --format=%s ${{ github.event.pull_request.base.sha }}..${{ github.event.pull_request.head.sha }} \
                | grep -Ev '^CR[0-9]{6}(\s|$)' || true)
          if [ -n "$bad" ]; then
            echo "不合规的 commit："; echo "$bad"; exit 1
          fi
      - name: 校验 PR 标题（squash 用）
        run: |
          echo "${{ github.event.pull_request.title }}" | grep -Eq '^CR[0-9]{6}(\s|$)' \
            || { echo "PR 标题必须以 CR<6位数字> 开头"; exit 1; }
```

> ★ **方案 A 的关键优势**：它产生的 status check 可以被 `required_status_checks` 强制，
> **而 `required_status_checks` 在 Team 计划上就有** → 不需要 Enterprise。

---

## 10. 坑清单

| # | 坑 | 现象 | 解法 |
|---|---|---|---|
| 1 | 以为 commit 合规就万事大吉 | squash merge 被拒 | ★ PR 标题也要带 `CR` 前缀（§5.2） |
| 2 | 计划不支持 metadata 规则 | UI 里找不到 "Restrict commit metadata" | Enterprise；否则用 §9 方案 A |
| 3 | 正则写成 `^CR[0-9]+` | `CR1`、`CR123` 都能混过去 | 用 `{6}` 锁死位数 |
| 4 | 忘了 `operator: "regex"` | 规则没生效 | API 里必须显式写 `operator: "regex"`（默认不是正则） |
| 5 | 用 `^` 配了 `(?m)` | 行为和你想的不同 | 默认**不跨行**，`^` 就是 subject 开头 |
| 6 | 写了负向预查 `(?!)` | RE2 不支持 → 规则报错或不生效 | 改用 `negate: true` |
| 7 | 行尾用 `$` 而不是 `\n?$` | 部分 push 路径判定异常 | 官方明确要求 `\n?$` |
| 8 | 以为 push 会被拒绝 | push "成功"了但分支没动 | 官方语义是"ref 不更新"，commit 变成 unreachable → 要 amend/rebase |
| 9 | 以为规则会追溯存量历史 | 老 commit 报错 | 官方明确：**只管新增的 commit** |
| 10 | 忘了 `repository_name` 条件 | 组织级 ruleset 报 422 / 作用范围不对 | 组织级必须同时给 `repository_name` + `ref_name` |
| 11 | 本地 hook 正则和 Ruleset 不一致 | 本地过了服务器不过 | 两边同源；最好把一致性做成断言 |
| 12 | 在所有分支上加这条规则 | 开发者体验极差（官方明确提醒会增加摩擦） | 只加在 `feature/**` + 受保护分支；其余靠 hook |
| 13 | 以为只有一条规则就够了 | 编个 `CR999999` 就混过去 | 还要 L3（CR Check App）查真伪 |
| 14 | R1 解析器没加 subject 载体 | 格式合规但 App 解析不到 CR 号 → check 红 | §6.2 扩展 `extract.go` |
| 15 | 把 CR 号写进正文而不是开头 | `^` 不匹配 | 必须是 subject 第一行 |

---

## 11. 关联文档

| 主题 | 文档 |
|---|---|
| ★ Ruleset 零基础 + 与 App 的唯一耦合点 | [`14-rulesets-and-gitapp-gate.md`](./14-rulesets-and-gitapp-gate.md) |
| R1–R13a 规则表 / 载体与冲突检测 | [`13-cr-check-go-design.md`](./13-cr-check-go-design.md) §5.1 |
| CR 号解析的实现（`extract.go`） | [`cr-check/internal/rules/extract.go`](./cr-check/internal/rules/extract.go) |
| ★ 可运行的 Ruleset 配置 + 契约静态检查 | [`examples/rulesets/`](../examples/rulesets/) |
| ★ 本地模拟器 | [`examples/rulesets/simulate-commit-gate.py`](../examples/rulesets/simulate-commit-gate.py) |
| ★ 本地 commit-msg hook | [`examples/rulesets/commit-msg-hook.sh`](../examples/rulesets/commit-msg-hook.sh) |

### 标注

| 标注 | 内容 |
|---|---|
| **官方保证** | metadata 规则需 Enterprise 计划；RE2 语法 / 默认不跨行 / 不支持负向预查 / 支持正向前瞻；`\n?$` 约定；正则需显式选择 "Must match a given regex pattern"；squash 合并时校验最终 commit message；push 时 ref 不更新而非拒绝；不追溯存量历史；元数据规则会增加摩擦、建议只施加在有限分支 |
| **推荐实现** | 两条 ruleset（feature 提前拦 + 受保护分支兜底）；模式 `^CR[0-9]{6}(\s|$)`；PR 标题同格式；本地 hook 与 Ruleset 同源正则；label 为主载体、subject 前缀为辅助 |
| **需实测 / 部署前验证项** | 你们所在计划的 metadata 规则可用性；squash 合并时 GitHub 到底按"PR 标题"还是"可编辑的最终 message"判定（文档两段表述有歧义，建议按 §8 的验收脚本实测）；`commit_message_pattern` 在**仓库级** ruleset 中是否也可提交（API schema 里有，但官方表述是组织级能力） |
