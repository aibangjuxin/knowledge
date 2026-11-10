# 从 kubernetes-sigs/prow 的 PR 管理机制，看 GitHub 门禁该怎么设计

> **本文目的**：拆解 `kubernetes-sigs/prow` 仓库里真实运行的 PR 管理机制，
> 提炼出**可以直接抄到我们自己的 CR Check / GitHub App 门禁里**的设计。
>
> **取材方式**：直接读 GitHub API 的真实数据（PR 列表、bot 评论、commit status、label 定义、
> Prow 源码），不是靠印象。所有关键结论都附了可复现命令（见 §附录 B）。
>
> **一句话结论**
> Prow 最有价值的不是"它很强"，而是它把**"这个 PR 现在为什么不能合并"**
> 变成了一个**永远存在、永远准确、人和机器都能读**的东西：
> 一组 `do-not-merge/*` 标签 + 一个 `tide` 聚合 context。
> 我们做 CR Check 时，缺的就是这一层"可解释性"。

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-这次到底看了什么) | 这次到底看了什么（数据来源与限制） |
| [§1](#1-prow-的-pr-管理全景) | Prow 的 PR 管理全景 |
| [§2](#2--值得学习的-13-个设计) | ★ **值得学习的 13 个设计**（逐条：现象 → 证据 → 为什么 → 怎么抄） |
| [§3](#3-值得警惕--不要盲目抄的地方) | 值得警惕 / 不要盲目抄的地方 |
| [§4](#4-映射到我们的-cr-check行动清单) | 映射到我们的 cr-check（行动清单） |
| [§5](#5-附录-a证据速查) | 附录 A：证据速查 |
| [§6](#6-附录-b复现命令) | 附录 B：复现命令 |

---

## 0. 这次到底看了什么

### 0.1 看的数据

| 对象 | 范围 |
|---|---|
| **PR 列表** | `kubernetes-sigs/prow` 全部 open PR（约 30 个），提取 title / author / labels / draft |
| **PR #1026** | `Require rationale for /retest, /retest-required, and /override` —— **完整读了 PR body + 全部 bot 评论** |
| **PR #1028** | `secretutil: censor the values inside JSON and INI secrets` —— 非成员 PR 的完整 bot 评论链 |
| **PR #1008 / #987 / #816 / #808** | 覆盖 `do-not-merge/*`、`needs-rebase`、`lifecycle/stale`、draft 等状态 |
| **PR #1065 / #1058** | 已合并 PR 的 `tide` status，对比"未合并"时的样子 |
| **commit status** | 上述 PR head SHA 上的**全部** status（`tide` / `pull-prow-*` / `EasyCLA` / `deploy/netlify`）|
| **Prow 源码** | `pkg/labels/labels.go`、`pkg/plugins/lgtm/lgtm.go`、`pkg/plugins/approve/approve.go`、`pkg/plugins/hold/hold.go`、`pkg/tide/status.go`、`pkg/config/tide.go` |

### 0.2 一个必须先说清楚的事实：Prow 用的是 **commit status**，不是 **check run**

实测 #1026 head SHA 的 check-runs 只有 netlify 的三个（`Redirect rules` / `Header rules` / `Pages changed`），
**Prow 自己的 context 一个 check run 都没有**。再看 commit status：

```
tide | pending | Not mergeable. Needs approved, lgtm labels.
EasyCLA | success | EasyCLA check passed. You are authorized to contribute.
deploy/netlify | success | Deploy Preview ready!
pull-prow-verify-lint | success | Job succeeded.   BaseSHA:6c4d88e3b73e434d7acc03395ec337fa2b3f1fad
pull-prow-unit-test | success | Job succeeded.   BaseSHA:6c4d88e3b73e434d7acc03395ec337fa2b3f1fad
pull-prow-unit-test-race-detector-nonblocking | success | ...
pull-prow-image-build-test | success | ...
pull-prow-integration | success | ...
```

> ⚠️ **这不代表"status 比 check run 好"**。Prow 是 2016 年的设计，
> `status` 的表达能力（没有 `external_id`、没有 output 结构、没有 `in_progress` 语义）确实弱于 check run。
> **我们要抄的是它的"语义模型"，不是它的"传输载体"。**

### 0.3 一个没能取到的数据（诚实说明）

`gh api repos/kubernetes-sigs/prow/branches/main/protection` 返回 **404 Not Found**，
`master` 同样 404 —— 因为**当前 token 对该仓库没有 admin 权限**，无法读取 branch protection 配置。

→ **所以本文没有断言 "kubernetes-sigs/prow 的 main 分支上 required status checks 具体配了哪些 context"。**
本文关于门禁的结论，全部来自**实际观测到的 status 行为**（`tide` 的 state/description 随 PR 状态变化），
而不是来自配置文件。后者我在 §2.1 用 Prow 源码（`pkg/tide/status.go`）交叉验证了。

---

## 1. Prow 的 PR 管理全景

### 1.1 三个组件，各管一段

```
    GitHub 事件
        │
        ▼
┌───────────────────────┐
│  hook                 │  收到 webhook → 交给一串「插件」处理
│  (事件 → 插件)         │  插件 = approve / lgtm / hold / ok-to-test /
│                       │          trigger / override / assign / label / ...
└───────────────────────┘
        │ 产生副作用：加/删 label、发评论、起 CI
        ▼
┌───────────────────────┐      ┌──────────────────┐
│  tide                 │─────▶│  merge pool      │  算出「哪些 PR 现在可以合」
│  (合并队列 + 门禁判定) │      │  (按优先级排队)   │  直接自动合并
└───────────────────────┘      └──────────────────┘
        │ 写一个聚合 status
        ▼
   tide context (pending / success)  ←── 这就是门禁
```

**关键**：hook 负责"把状态写出来"，tide 负责"读状态并决定能不能合"。
**两者通过 GitHub 上可见的 label / status 通信**，而不是通过内部 RPC。

### 1.2 状态的载体：label（持久）+ status（瞬时）

Prow 的全部 PR 状态都落在两个 GitHub 原生载体上：

| 载体 | 特性 | Prow 用来存 |
|---|---|---|
| **Label** | 持久、人可见、跨 bot 重启不丢、可被任何 App 读 | `approved`、`lgtm`、`ok-to-test`、`do-not-merge/hold` … |
| **Commit status** | 绑 SHA、瞬时、CI 语义 | `tide`（聚合门禁）、`pull-prow-*`（具体 CI） |

> ★ **这一层设计是 Prow 最值得学的地方**：
> **状态放在 GitHub 上，不放在 bot 的内存里。**
> hook 挂了、重启了、被换副本了，状态还在。
> 这一点直接对应我们 `git-apps/cr-check/` 里 "`recheck.Registry` 是进程内内存 → Pod 重启后重扫静默失效" 的问题。

### 1.3 Prow 的 label 体系（`pkg/labels/labels.go` 实测）

**（a）所有"阻塞合并"的原因集中在 `do-not-merge/` 前缀下**：

```
do-not-merge/blocked-paths
do-not-merge/cherry-pick-not-approved
do-not-merge/contains-merge-commits
do-not-merge/hold
do-not-merge/invalid-owners-file
do-not-merge/release-note-label-needed
do-not-merge/work-in-progress
```

**（b）其它语义前缀各自成族**：

```
kind/*                kind/bug, kind/feature, kind/deprecation
area/*                area/tide, area/plugins, area/deck, area/peribolos …
size/*                size/XS, size/S, size/M, size/L, size/XL, size/XXL
lifecycle/*           lifecycle/active, lifecycle/frozen, lifecycle/rotten, lifecycle/stale
bugzilla/*            bugzilla/severity-{urgent,high,med,low}, bugzilla/valid-bug …
triage/*              triage/accepted
```

**（c）单值状态**：`approved`、`lgtm`、`ok-to-test`、`needs-ok-to-test`、`needs-rebase`、
`cncf-cla: yes`、`cncf-cla: no`、`release-note`、`release-note-none`、`cherry-pick-approved` …

### 1.4 一张状态图（实测归纳）

```
                    ┌──────────────────────────────────────┐
                    │            非成员 PR                    │
                    └──────────────────────────────────────┘
                                 │
                    开 PR → needs-ok-to-test
                                 │  成员说 "/ok-to-test"
                                 ▼
                             ok-to-test        ←── ★ trust gate（"可以跑 CI 了"）
                                 │
                    跑 CI → 提交者 /lgtm 或 owner /approve
                                 ▼
              ┌──────────────┴──────────────┐
        非成员自批准                    真正的 owner 批准
              │                              │
              │  （不算数）                    ▼
              │                          approved
              │                              │
              └──────────────┬───────────────┘
                             ▼
                     lgtm（或 approved+其他）
                             │
                             ▼
              ┌──────────────────────────────┐
              │  tide context = success       │
              │  "In merge pool."             │
              └──────────────────────────────┘
                             │
                 但只要出现任何一个：
              do-not-merge/hold
              do-not-merge/work-in-progress
              needs-rebase
              do-not-merge/release-note-label-needed
              ...
                             ▼
              ┌──────────────────────────────┐
              │  tide context = pending       │
              │  "Not mergeable. Needs X labels." │
              └──────────────────────────────┘
```

**★ 关键洞察**：
**"能否合并"不是一个布尔量，而是多个独立约束的合取。**
Prow 把每个约束拆成一个独立的 label，
于是"为什么不能合"天然就是**可列举、可展示、可组合**的。

---

## 2. ★ 值得学习的 13 个设计

---

### 2.1 用「一个聚合 context」做门禁，并且 description 直接说缺什么

**现象**

`tide` 是**唯一**的合并门禁 context。它的 `description` 随 PR 状态精确变化：

| PR 状态 | tide state | tide description |
|---|---|---|
| #1028 缺批准 | `pending` | `Not mergeable. Needs approved, lgtm labels.` |
| #1008 缺 lgtm | `pending` | `Not mergeable. Needs lgtm label.` |
| #1006 缺 approved | `pending` | `Not mergeable. Needs approved label.` |
| #995 / #1013 | `pending` | `Not mergeable. Needs approved, lgtm labels.` |
| #1065 已入合并池 | `success` | `In merge pool.` |
| #1058 已合并 | `success` | （description 清空）|

**源码验证**（`pkg/tide/status.go`）：

```go
statusInPool               = "In merge pool."
statusInPoolDespiteBlocked = "In merge pool (despite BLOCKED)."
statusNotInPool            = "Not mergeable.%s"

// 缺 label 时
desc = fmt.Sprintf(" Needs %s label.",  trunced[0])
desc = fmt.Sprintf(" Needs %s labels.", strings.Join(trunced, ", "))

// 有不该有的 label 时
desc = fmt.Sprintf(" Should not have %s label.",  trunced[0])
desc = fmt.Sprintf(" Should not have %s labels.", strings.Join(trunced, ", "))

// GitHub 侧 blocked 时
desc = " Blocked by GitHub (branch rulesets or protection)"
```

**★ 还有一个隐藏但极重要的细节**：

```go
// fixing label issues takes precedence over status contexts
```

**label 问题优先于 CI context 问题上报**。
也就是说，用户看到的是"最该先解决的那个"，而不是一堆并列的错误。

**为什么好**

1. **required status check 只需要配一个 context**（`tide`），不必把 `approved`、`lgtm`、几十个 `pull-prow-*` 全列进 branch protection。
2. **description 是给人看的**。GitHub 的 status 行会直接显示这段文字 →
   用户在 PR 页面上**一眼就知道该干什么**，不用去翻文档。
3. **聚合 context 的 value 可以随时改**（加一个新维度进去），
   而 branch protection 配置**一个字都不用动**。
   → 这是"可扩展的门禁"。

**怎么抄**

- 我们的 CR Check 如果要同时表达"CR 号有效 + CR 可执行 + 在维护窗口内"，
  **不要**做成三个 required status check（GitHub 的 required check 列表会越来越长、互相遮蔽），
  而应该做成**一个聚合 check**，description 写清"缺什么"。
- 具体做法：
  ```go
  // 把三个维度的失败原因收集起来，按优先级排序，只报最该解决的那个
  desc := "Not ready to merge. "
  desc += "Needs a valid CR reference. "   // ← 最优先
  desc += "CR must be in executable state. "
  desc += "Outside the maintenance window."
  ```
- **同时把维度拆成独立 label**（见 2.2），这样 label 能给 CI 脚本用，context 能给人看。

---

### 2.2 用 `do-not-merge/*` 命名空间承载**所有**阻塞原因

**现象**

见 §1.3(a)：七个不同性质的阻塞原因，全在 `do-not-merge/` 前缀下。
实测 PR 标签组合：

```
#1008: approved, do-not-merge/hold, size/XXL, area/peribolos, area/documentation
#987 : approved, do-not-merge/work-in-progress, size/L, area/tide      (draft=true)
#808 : kind/bug, ok-to-test, needs-rebase, lifecycle/stale, size/L, area/plugins   (mergeable=false)
```

注意 **#808 同时有 `needs-rebase` 和 `lifecycle/stale`** ——
**多个阻塞原因可以共存**，不会被互相覆盖。

**为什么好**

1. **前缀即语义**：`do-not-merge/*` = "有它就不能合"。新增一个阻塞维度，
   只要起个同前缀的 label，**判定逻辑一行都不用改**（前缀匹配即可）。
2. **可组合**：hold + needs-rebase 可以同时在；这正好对应现实——
   "既冲突了，又被人 hold 了"。
3. **人可见**：PR 页面的标签栏就是当前状态的完整快照。
   不需要点进 bot 评论、不需要查数据库。
4. **机器可读**：任何 GitHub App / CI 脚本都能 `GET /issues/{n}/labels` 拿到全部状态。
   → **这是"状态外置"的极致：GitHub 成了状态存储。**

**怎么抄**

给 CR Check 设计一个同构的标签族：

```
cr-check/hold            有人 hold，禁止合并
cr-check/invalid-cr      CR 号无效或不存在
cr-check/cr-not-ready    CR 还没到可执行状态
cr-check/out-of-window   不在维护窗口内
cr-check/stale-approval  CR 已被撤销/过期
```

**并且**：判定逻辑写成 **"存在任一 `cr-check/*` 阻塞标签 → 不通过"**，
而不是为每个原因写一个独立的 required check。

**⚠️ 配套动作**：GitHub 的 label 名不能事后改名（改了等于删旧加新，历史会断），
所以**前缀一旦定下就别改**。Prow 的 `do-not-merge/` 从 2017 年用到现在没变过。

---

### 2.3 ★ 结论必须和**代码内容**绑定（tree hash 机制）

**这是我认为 Prow 最精妙的一个设计。**

**现象**

Prow 的 `lgtm` 插件在 `synchronize`（推送新 commit）事件里的处理（`pkg/plugins/lgtm/lgtm.go`）：

```go
const (
    addLGTMLabelNotification   = "LGTM label has been added.  <details>Git tree hash: %s</details>"
    removeLGTMLabelNoti        = "New changes are detected. LGTM label has been removed."
)

func handlePullRequest(log, gc, config, pe) error {
    if pe.PullRequest.Merged { return nil }
    if pe.Action != github.PullRequestActionSynchronize { return nil }
    ...
    // ① 从 bot 自己的历史评论里，找回最后一次 LGTM 时记录的 tree hash
    for _, v := range slices.Backward(comments) {          // ← 倒序遍历
        m := addLGTMLabelNotificationRe.FindStringSubmatch(comment.Body)
        if botUserChecker(comment.User.Login) && m != nil && comment.UpdatedAt.Equal(comment.CreatedAt) {
            lastLgtmTreeHash = m[1]
            break
        }
    }
    // ② 取当前 commit 的 tree hash
    commit, _ := gc.GetSingleCommit(org, repo, pe.PullRequest.Head.SHA)
    treeHash := commit.Commit.Tree.SHA
    // ③ 内容没变 → 保留 LGTM
    if treeHash == lastLgtmTreeHash {
        log.Infof("Keeping LGTM label as the tree-hash remained the same: %s", treeHash)
        return nil
    }
    // ④ 内容变了 → 撤销 LGTM + 重新请求 review + 发评论
    removeLGTMAndRequestReview(gc, org, repo, number, getLogins(pe.PullRequest.Assignees), opts.StoreTreeHash)
    return gc.CreateComment(org, repo, number, removeLGTMLabelNoti)
}
```

**实测印证**（#1008 的 bot 评论）：

```
kubernetes-prow[bot] [2026-11-03T10:57:05Z]
New changes are detected. LGTM label has been removed.
```

**为什么这个设计特别妙**

| 维度 | 说明 |
|---|---|
| **绑定的是 tree hash 而不是 commit SHA** | ★ 纯 rebase / merge 上游 / cherry-pick 会改 SHA 但**不改内容**。用 SHA 判定会**误伤**（白白撤销批准），用 tree hash 判定则**内容真的变了才撤销** |
| **版本写在 bot 自己的评论里** | 用 GitHub 天然持久化的载体存版本，**不需要数据库** |
| **靠正则从历史评论里反解** | bot 的评论就是状态存储，天然幂等（同一评论不会重复写） |
| **`comment.UpdatedAt.Equal(comment.CreatedAt)`** | ★ 防止被人**编辑过**的 bot 评论被当成有效版本记录 —— 一个很细但很正确的防御 |
| **倒序遍历 + 第一个命中就 break** | 取"最后一次"批准，而不是"任意一次" |
| **撤销时顺带 `RequestReview` 重新请求 review** | 状态失效的同时把动作也带上了，不只是"打个标记" |

**怎么抄（直接对应我们 CR Check 的核心问题）**

我们的 CR Check 有一个同样的病：
**结论（"CR 有效、可以发版"）和代码版本脱钩了。**

具体场景：
```
10:00  PR #42 判定通过 ✅（CR #100 有效，在维护窗口内）
10:30  有人往 PR 里 push 了一个 commit（改了业务代码，但 CR 状态没变）
       ★ 我们的 check 仍然挂在旧 SHA 上 → 门禁放行
       ★ 而且如果新 SHA 上没有 cr-check，required check 反而会挡住 —— 取决于门禁怎么配
```

**建议照抄 Prow 的做法**：

1. **判定结果里必须带上"我基于哪个内容版本做的判定"**：
   ```go
   // 别只记 commit SHA —— 要记 tree hash
   type Verdict struct {
       Repo, PRNumber string
       HeadSHA    string   // 给 GitHub 用（check 挂在哪个 commit 上）
       TreeSHA    string   // ★ 给"结论是否仍然有效"用
       PolicyVersion string
       Conclusion string
   }
   ```
2. **新 commit 到达时，比较 tree hash**：
   - tree hash 变了 → **必须重判**，并且**主动把旧结论作废**
   - tree hash 没变（纯 rebase） → **不要重判，也不要作废**（省 CI，也省开发者耐心）
3. **把版本写进 bot 评论 / check output**，用 `<!-- META={...} -->` 这种可解析格式（见 2.9）。

> 这条是本文与 [`how-to-atomic-idempotency.md`](./how-to-atomic-idempotency.md) 里
> "L2 业务键 = (repo, check_name, head_sha)" 的**重要补充**：
> **`head_sha` 是"这次判定针对哪个 commit"，而 `tree_sha` 才是"结论是否还成立"。**
> 用 SHA 做"是否需要重算"的判断，在 rebase 场景下会浪费大量 CI。

---

### 2.4 状态失效时**同时**撤销标记 + 重新请求 review + 留痕

**现象**

见 2.3 的 `removeLGTMAndRequestReview`：

```go
func removeLGTMLabelAndRequestReview(...) error {
    gc.RemoveLabel(org, repo, number, LGTMLabel)        // ① 撤标记
    if storeTreeHash {
        gc.RequestReview(org, repo, number, logins)     // ② 重新请求 review
    }
    gc.CreateComment(org, repo, number, removeLGTMLabelNoti)  // ③ 留痕
}
```

**为什么好**

撤掉 `lgtm` 只是"关掉一盏灯"；**重新 request review 才是"把球传回去"**。
而且留一条评论，让所有相关的人**在 PR 时间线上看到发生了什么、什么时候发生的**。

**怎么抄**

CR Check 的结论失效时（比如 CR 被撤销、CR 被重开、维护窗口结束），
不要只把 check 改成失败，要：
- 改 check 结论（让门禁生效）
- 在 PR 上留一条说明（谁、什么时候、为什么作废）
- 如果是"需要人重新确认"，把 CR 的负责人重新 assign 回去

---

### 2.5 审批粒度跟着**改动的文件路径**走（OWNERS 模型）

**现象**

`kubernetes-sigs/prow/OWNERS`：

```yaml
approvers:
  - cblecker
  - petr-muller
  - matthyx
  - droslean
  - krzyzacy
  - smg247
emeritus_approvers:
  - alvaroaleman
  - cjwagner
  - stevekuznetov
  - timwangmusic
```

而 bot 评论会**精确列出缺哪个目录的批准**：

```
[APPROVALNOTIFIER] This PR is **NOT APPROVED**

This pull-request has been approved by: cvas22 (Author self-approved)
**Once this PR has been reviewed and has the lgtm label**, please assign droslean for approval.

<details open>
Needs approval from an approver in each of these files:

- **[pkg/OWNERS](https://github.com/kubernetes-sigs/prow/blob/main/pkg/OWNERS)**

Approvers can indicate their approval by writing `/approve` in a comment
Approvers can cancel approval by writing `/approve cancel` in a comment
</details>
<!-- META={"approvers":["droslean"]} -->
```

> ★ 注意最后那行 `<!-- META={"approvers":["droslean"]} -->` —— 见 §2.9。

**已通过时的样子**（#1008）：

```
[APPROVALNOTIFIER] This PR is **APPROVED**

This pull-request has been approved by: hoxhaeris (Author self-approved), petr-muller (Approved)

<details >
Needs approval from an approver in each of these files:

- ~~[OWNERS](...)~~ [petr-muller]     ← 删除线表示已满足
</details>
<!-- META={"approvers":[]} -->        ← ★ 空数组 = 已满足
```

**为什么好**

- **责任跟着代码走**：改了 `pkg/` 就找 `pkg/OWNERS` 里的人，改了根目录就找根 `OWNERS` 里的人。
- **多人要求时可以并行**：每个 OWNERS 文件独立要求一个 approver，不串行。
- **自助批准不算数**：注释里明确写 `Author self-approved`，
  并且"一旦有人批准，请 assign droslean" —— **作者自己点的赞不会解锁门禁**。

**怎么抄**

我们的 CR Check 如果要做到"**改了什么，就得谁批**"，
可以为不同路径配置不同的 CR 审批人：

```yaml
cr_check:
  rules:
    - path: "services/payment/**"    # 支付相关改动
      required_approvers: ["payment-owners"]
    - path: "services/**"
      required_approvers: ["backend-owners"]
```

**注意 Prow 的一个细节**：评论里给的是**具体的人**（`droslean`）而不是一个组。
这是"**给出下一步的具体动作**"（见 §2.8）。

---

### 2.6 trust gate 与 merge gate **分离**

**现象**

PR #1028（作者 `cvas22` 是**非成员**）的完整 bot 评论链：

```
kubernetes-prow[bot] [2026-10-22T22:09:22Z]
Welcome @cvas22! 🎉 ... Please refer to our pull request process documentation ...

kubernetes-prow[bot] [2026-10-22T22:09:23Z]
[APPROVALNOTIFIER] This PR is **NOT APPROVED**
This pull-request has been approved by: cvas22 (Author self-approved)
**Once this PR has been reviewed and has the lgtm label**, please assign droslean for approval.

kubernetes-prow[bot] [2026-10-22T22:09:24Z]
Hi @cvas22. Thanks for your PR.

I'm waiting for a kubernetes-sigs member to verify that this patch is reasonable to test.
If it is, they should reply with `/ok-to-test` on its own line.
Until that is done, I will not automatically test new commits in this PR, but the usual
testing commands by org members will still work.

Regular contributors should join the org to skip this step.

Once the patch is verified, the new status will be reflected by the `ok-to-test` label.
```

标签变化：`needs-ok-to-test`（红）→ 成员说 `/ok-to-test` → `ok-to-test`（绿）。

**为什么这是两个独立的门**

| | trust gate | merge gate |
|---|---|---|
| **问的问题** | "这个补丁**值得**跑 CI 吗？" | "这个 PR **可以合**吗？" |
| **门禁形式** | label（`ok-to-test`） | status context（`tide`） |
| **谁能解** | org 成员 | owner / approver |
| **不解的后果** | **不跑 CI**（省算力，不是安全门） | **不能合**（安全门） |
| **对非成员 PR** | 必须解 | 必须解 |

**★ 关键理解**：
`ok-to-test` **不是**安全门，是**成本门**。
它挡的是"恶意 PR 触发大量 CI 烧配额"。
把它和真正的合并门混在一起，会让"CI 没跑"和"CI 失败"变成同一种阻塞，用户会困惑。

**怎么抄**

我们的场景里有一个天然对应：

| 维度 | Prow | CR Check 对应 |
|---|---|---|
| 成本门 | `ok-to-test`（非成员 PR 要人背书才跑 CI） | "外部贡献者的 PR 要维护者先确认才判定" |
| 安全门 | `tide` + `approved` + `lgtm` | "CR 有效 + 可执行 + 在窗口内" |
| 撤销门 | `do-not-merge/hold` | "有人 hold" |

**明确写在文档/UI 里，避免用户误以为"只要 CI 跑了就能合"。**

---

### 2.7 排他标签前缀（exclusive label prefixes）

**现象**（PR #799 `feat(label): support configurable exclusive label sets`）

> When a label matching an exclusive prefix is added, any existing label with the same prefix on the issue or PR is automatically removed.

```
Current labels:  priority/backlog
                 kind/bug

User adds:       /priority important-soon

↓  自动移除:      priority/backlog

Final labels:    priority/important-soon
                 kind/bug
```

**为什么好**

有些维度**天然互斥**（一个 PR 只能有一个优先级、一个类型、一个状态）。
如果允许同时存在 `priority/backlog` 和 `priority/important-soon`，
**任何读 label 的脚本都要自己去定义"哪个优先"** → 逻辑分散、容易出错。

**排他前缀把这个约定下沉到了写入端**：谁写 label 谁保证一致性。
**读者不需要懂优先级规则，只需要读 label。**

**怎么抄**

我们写 CR Check 的结论 label 时，同理：

```
cr-check/status/valid        ← 判定通过
cr-check/status/invalid-cr   ← CR 无效
cr-check/status/not-ready    ← CR 未就绪
cr-check/status/out-of-window
```

**这四个必须互斥** → 写的时候必须"先删同前缀旧的，再加新的"。

⚠️ **实现注意**：GitHub 的 label API **没有"原子地替换同前缀标签"**。
必须 **先删后加**（不能先加后删），否则中间态会出现两个同前缀 label，
而且 Prow 的实现就是这个顺序（"Remove conflicting labels before applying a new exclusive label"）。

---

### 2.8 ★ 命令要带「理由」（`require_rationale`）—— 而且是**在原生处理之前**拦

**现象**（PR #1026，本 PR 本身就是这个功能的实现）

PR body 里的完整策略说明：

```yaml
require_rationale:
  my-org/my-repo:
    retest:
      min_length: 20
    retest-required:
      min_length: 20
    override:
      min_length: 30
```

**验收语义**（作者在 PR body 里列的规则）：

> - Every occurrence of a protected command needs its own rationale, so a second `/override` without one blocks the whole comment.
> - A rationale must not start with `/`, and a rationale on the following lines ends at the next line starting with `/`, so other commands cannot pass as a rationale.
> - Same-line rationales are only accepted in repositories with a policy for that command.
> - Runs after the existing trust (`/retest`, `/retest-required`) and authorization (`/override`) checks. **Untrusted or unauthorized users get the existing response.**
> - **Comments from Prow's own bot are exempt; other bots and apps are treated like users.**

**实测验证**（作者在一个公开的 scratch 仓库上跑的真实验证，见 §附录 A）：

| 输入 | 结果 |
|---|---|
| `/retest flaky` | ❌ Blocked：`too short (5 of 20)` |
| `/retest <长理由>` | ✅ ProwJob created，**且理由被剥掉后再走 trigger 的正常解析** |
| `/retest` + 下一行理由（CRLF、空行） | ✅ ProwJob created |
| `/retest /lgtm! looks good to me` | ❌ Rejected：**理由不能以 `/` 开头** |
| `/retest` + 下一行 `/lgtm! ...` | ❌ Blocked：**以 `/` 开头的行结束理由**，所以没有理由 |
| `/override unit -- <理由>` 后跟裸 `/override unit` | ❌ Blocked：**每一次出现都要理由**，两个 override 都没执行，`unit` 保持失败 |
| `/override unit -- <理由>` | ✅ Overridden：`unit` → `success` |
| 裸 `/override unit`（来自 Prow 自己的 bot） | ✅ 跳过理由门（bot 豁免），随后被原有 admin 权限检查拒绝 |
| 未配置该策略的仓库 | ✅ 行为完全不变 |

**★ 为什么这个设计值得抄**

1. **"没有理由就不许操作"是审计的最低要求。**
   `/override` 的本质是**人在绕过机器判定**。绕过如果不需要说明，
   门禁就随时可以被人绕过去，而且事后无法追责。
2. **"每一次出现都要理由"** —— 不是"这条评论里有一个理由就行"。
   这防止了"一条评论里夹带 5 个无理由的 override"。
3. **理由不能以 `/` 开头 / 遇到 `/` 开头的行就结束** ——
   防止 `/lgtm` 之类命令**伪装成理由**混过去。
4. **在原生处理之前拦截** —— 拦在前面就不会产生任何副作用
   （"No CI job was queued." / "neither override is applied"）。
   **先做副作用再校验顺序是错的。**

**怎么抄**

我们的 CR Check 里如果有"人工放行 / override"能力（大概率要有），
**必须**要求 override 附带理由，并且：

- 理由存到 PR 评论里（**人可读、不可删除**）；
- 理由的长度/格式有下限；
- 理由**不能是另一条命令**；
- **override 本身必须留痕**：谁、什么时候、为什么、绕过了哪个维度。

> 这一条正好补上 [`how-to-atomic-idempotency.md`](./how-to-atomic-idempotency.md) §9 里
> "check run + comment + label 不能原子生效" 的运维缺口：
> **人工干预是唯一无法自动化的环节，必须靠"留痕"来兜底。**

---

### 2.9 ★ 失败信息要精确到**可执行**

**现象**

Prow 的报错文案（来自 PR #1026 的 PR body，逐字引用）：

```
/retest
```

> Rationale required for `/retest` in this repository. No CI job was queued.
>
> Add a rationale of at least 20 non-whitespace Unicode code points after the command on the same line, or on the next line.

```
/retest flaky
```

> Rationale for `/retest` is too short (got 5 non-whitespace Unicode code points; need at least 20). No CI job was queued.

**为什么好**

| 要素 | 做法 |
|---|---|
| **说清楚发生了什么** | "Rationale is too short" —— 不是 "Invalid command" |
| **给出实际的量** | `got 5 non-whitespace Unicode code points; need at least 20` —— 不是 "too short" |
| **说清楚单位** | "non-whitespace Unicode code points"，不是 "characters"（中文标点算不算？用户会猜） |
| **说清楚后果** | "No CI job was queued." —— 明确告诉用户"你的操作没生效，但也没坏" |
| **说清楚怎么修** | "Add a rationale of at least 20 ... after the command on the same line, or on the next line." |
| **给出正例** | PR body 里同时给 accepted / rejected 的对照示例 |

**★ 最后一条最关键**："No CI job was queued" 这一句，
把"我拒绝了"和"我执行了一半"清楚区分开。
用户不会误以为命令生效了。

**怎么抄**

CR Check 的 check output 应该长这样：

```
❌ CR Check 未通过

[CR 引用无效]
  PR body 中未找到合法的 CR 号（期望形如 cr/1234，或 PR 标题包含 [CR-1234]）。
  本次扫描到 2 个疑似字符串："cr/12"、"#1234"。
  → 请修正 PR 描述或 title 后重新提交，或用 /cr-check override -- <理由> 放行。

[不在维护窗口内]
  当前时间 2026-11-10 14:30 (UTC+8)，维护窗口为 22:00-02:00。
  → 请等待窗口开启，或联系 @release-managers 走例外流程。

判定依据：policy_version=3f2a1c9，CR 平台快照时间 2026-11-10T06:29:11Z
```

要素：**问题分类 → 证据 → 下一步动作 → 依据版本**。

---

### 2.10 ★ **自己的错误输出不能被自己当命令解析**（作者踩过的真实坑）

**现象**

PR #1026 作者在 body 里写的：

> ### Bug found and fixed in an earlier run
>
> An earlier live run found that **the override plugin acted on the bot's own rationale error comment**.
> The comment's example began with a column-0 `/override …` line, and the override plugin does not skip bot-authored comments.
> **A bot account authorized to override could have overridden the example context on its own.**
>
> The examples are now rendered as quoted code blocks (`>``` ` …), the same way `FormatResponseRaw` quotes user comments.
> **A regression test asserts that no rationale error comment contains a line starting with `/`.**
> A handler test replays the bot's real response as an authorized user and asserts that nothing changes.

**这个 bug 是什么**

```
用户写了一条格式不对的评论
    ↓
Prow 的 rationale 插件判定失败，**发出一条报错评论**
    ↓
报错评论里为了举例，包含了 `/override pull-e2e-aws -- ...` 这样的示例
    ↓
★ override 插件扫到这条评论（自己的输出！），发现里面有 `/override` 命令
    ↓
★ 而且这个 bot 账号**有 override 权限** → 它执行了自己的示例命令
```

**★ 这是一个非常通用的失败模式**：
**任何"解析命令"的系统，都要保证自己的输出不会被自己解析。**
它在小规模下表现为"bot 偶尔会莫名其妙执行一下"，
在有权限的 bot 上就是**自我提权**。

**怎么抄**

1. **报错评论里的示例必须用引用代码块包裹**（`> ``` `），让命令不在行首。
2. **加一条回归测试**："断言报错评论里不含任何以 `/` 开头的行"。
3. **再加一条 handler 测试**："把 bot 的真实响应当成授权用户的评论重放，断言什么都不会发生"。
4. 更根本的做法：**解析时跳过自己发的评论**（按 bot user id 过滤）。
   注意 Prow 这里**故意不跳过**（"other bots and apps are treated like users"），
   而是用"输出格式"来保证安全 —— 因为**别的 bot 也可能有权限**，
   跳过自己的 bot 挡不住"别的有权限的 bot 触发自己的报错"。

> ★ 这个案例直接对应我们 CR Check 的一个待设计点：
> **如果 CR Check 会解析 PR 评论里的 `/cr-check override` 命令，
> 那么它的报错评论绝不能包含看起来像命令的示例。**
> 我们的实现（`internal/rules/` 那套）目前还没有"从评论里读命令"的能力，
> **但这是迟早要加的功能，现在就该把这条约束写进设计。**

---

### 2.11 bot 评论里嵌**机器可读**的元数据（`<!-- META=... -->`）

**现象**

```
<!-- META={"approvers":["droslean"]} -->
<!-- META={"approvers":[]} -->
```

**为什么好**

1. **人类看到的是渲染后的漂亮文本，机器读到的是 JSON。**
   同一个载体，两种消费者，互不干扰。
2. **状态存在 GitHub 上，跨重启、跨副本、跨实例都有效**（见 §2.3 的 tree hash 用法）。
3. **HTML 注释在 Markdown 渲染后不可见**，不污染阅读体验。

**怎么抄**

我们的 check output / bot 评论里可以放：

```markdown
<!-- META={"policy_version":"3f2a1c9","evaluated_at":"2026-11-10T06:29:11Z","tree_sha":"a1b2c3...","dims":{"cr_ref":"invalid","cr_state":"n/a","window":"outside"}} -->
```

这样：
- 人看渲染后的文字；
- 脚本（比如生成周报、审计、幂等判定）读 META。

**★ 与 §2.3 联动**：
Prow 正是用这个机制把 tree hash 存进评论，
然后下一次 `synchronize` 时**用正则从历史评论里反解回来** —— 这是一个完整的"无数据库状态机"。

---

### 2.12 配置即代码 + 校验 + **热生效**

**现象**（PR #1026 body 的 "Example: opting a repository in after this merges"）

> ### 1. Add a `require_rationale` entry for the repository
> Add the policy to the repository's plugin config. You can use the central `plugins.yaml` or a supplemental `_pluginconfig.yaml`; this PR allows `require_rationale` in supplemental files.
> ...
> - Keys are exact `org/repo` names. **There is no org-level inheritance.**
> - `retest`, `retest-required`, and `override` are independent: protect any combination, each with its own `min_length`.
> - `min_length` defaults to 20 when omitted.
> - **A repository can be configured in only one config file. A second entry for the same repository fails config loading.**
>
> ### 3. Roll out
> - **`checkconfig` validates the entry.** It rejects keys that aren't `org/repo`, commands other than `retest`, `retest-required`, and `override`, and a negative `min_length`.
> - **Once merged, the config reaches `hook` through the instance's normal config sync (for example `updateconfig`). No redeploy is needed.**
> - To turn the policy off, remove the entry.

**★ 三个值得抄的点**

| 点 | 说明 |
|---|---|
| **配置有专门的校验工具**（`checkconfig`） | 配置错误在**提交时**就被拒，而不是运行时才炸 |
| **热生效** | "the config reaches hook through the instance's normal config sync... **No redeploy is needed**" |
| **配置粒度明确** | 精确到 `org/repo`，**明确没有 org 级继承**，重复配置直接加载失败 |

**怎么抄**

1. **CR Check 的策略配置放 Git（仓库里），不要放环境变量。**
   - 变更走 PR → review → merge，天然有审计
   - 策略版本 = **文件内容的 blob SHA** → 天然是单调且精确的版本号
2. **提供一个 `cr-check checkconfig` 之类的校验命令**，
   在 CI 里跑：配置格式错、仓库名不存在、min_length 非法 → 直接 fail。
3. **配置热生效**：hook 定期 reload 配置文件；读到新 blob SHA → 触发重算（见下）。

> ★ 这条与 [`how-to-atomic-idempotency.md`](./how-to-atomic-idempotency.md) §8 的 L3 层直接对应：
> **Prow 的做法等价于 `policy_version = 配置文件 blob SHA`，
> 而且它明确"策略变更无需重启" → 变更后必然要重算存量结论。**

---

### 2.13 Draft PR 跳过 CI，但**明确告诉用户怎么手动触发**

**现象**（PR #1026 的第一条 bot 评论）

```
kubernetes-prow[bot] [2026-10-21T10:54:39Z]
Skipping CI for Draft Pull Request.
If you want CI signal for your change, please convert it to an actual PR.
You can still manually trigger a test run with `/test all`
```

**为什么好**

- **省 CI 配额**（Prow 跑在 GKE 上，PR 数量大，Draft 往往很多）。
- **但没有"闷声不跑"**：明确告诉用户"我没跑"、"为什么"、"怎么手动跑"。
- **给出了逃生口**（`/test all`）—— 不至于让 Draft PR 的作者卡死。

**怎么抄**

CR Check 可以同样处理 Draft PR：
- Draft 状态 → **跳过判定**，或判定为"不阻塞"（但要显式说明）
- 一定要在 PR 上留一条："Draft PR 跳过了 CR 校验，转成正式 PR 后自动生效。"

> ⚠️ **注意别照抄成"闷声跳过"**：Prow 是**明说**的。

---

### 2.14 机器人评论要给出「**下一步具体做什么**」

**现象**

多个 bot 评论都遵循同一模式：**说明状态 + 给出具体下一步 + 给出具体的人**。

```
#1028 APPROVALNOTIFIER:
  "**Once this PR has been reviewed and has the lgtm label**, please assign droslean for approval."
                                    ^^^^^^^^^^ 具体动作  ^^^^^^^^ 具体的人

#1028 ok-to-test:
  "they should reply with `/ok-to-test` on its own line"
  "Regular contributors should join the org to skip this step."

#1028 welcome:
  "Please refer to our pull request process documentation..."
  "Here is the bot commands documentation..."
  "If you are having difficulty getting your pull request seen, please follow
   the recommended escalation practices..."
```

**为什么好**

Bot 评论是**唯一一定会被读**的沟通渠道。
只报状态不给出路的 bot，用户就只能去问人。

**怎么抄**

CR Check 的失败评论（§2.9 的模板）必须包含一条：
**"接下来请做 X，或者联系 Y"** —— 而且 X 和 Y 都要具体。

---

## 3. 值得警惕 / 不要盲目抄的地方

| # | Prow 的做法 | 为什么不能直接抄 | 我们该怎么做 |
|---|---|---|---|
| 1 | **用 commit status 而非 check run** | status 没有 `external_id`、没有结构化 output、没有 `in_progress` 语义；**GitHub 现在推荐 check run** | **抄语义模型，不抄传输载体**。我们用 check run |
| 2 | **tide 自动合并**（merge pool） | 自动化合并的风险模型和我们的场景完全不同：我们是"发布门禁"，不是"合并门禁" | 只抄"聚合 context + 清晰 description"，**不抄自动合并** |
| 3 | **label 数量巨大**（几十个） | 噪音；新人面对 `do-not-merge/invalid-owners-file` 会懵 | 少而精。我们的 CR Check 控制在 5 个 label 以内 |
| 4 | **`do-not-merge/*` 语义靠前缀约定** | GitHub 没有"label 组"概念，全靠约定 | 我们要有**文档 + 校验命令**兜底，别只靠约定 |
| 5 | **审批基于 OWNERS + 路径** | 模型复杂（多目录、多 owner、emeritus） | 先做**单级审批**（一个角色即可放行），路径级审批作为后续 |
| 6 | **`/override` 由 admin 权限把关** | 我们的场景里 override 的授权模型还没定 | **先定义清楚授权模型**，再开放 override |
| 7 | **Prow 的 bot 有相当权限** | 我们如果照抄"bot 能 override"，就是 §2.10 那个自我提权坑 | **bot 永远不能放行自己的检查**；放行必须由真人做，且留痕 |
| 8 | **`ok-to-test` 这类"成本门"混在 PR 状态里** | 容易让用户误以为"CI 跑了 = 可以合" | 在文档/UI 里**明确区分**成本门和安全门 |
| 9 | **lgtm/approved 二元批准** | 我们的 CR 语义是"CR 平台上的变更单"，跟"人审代码"不是一回事 | 不要硬套 approved/lgtm，要建模成"**CR 状态**" |

---

## 4. 映射到我们的 cr-check（行动清单）

> 按"性价比"排序。**P1 = 立刻能做，收益大；P2 = 需要设计；P3 = 锦上添花。**

### P1 —— 立刻做

| # | 行动 | 抄自 | 对应我们的哪个文件 |
|---|---|---|---|
| 1 | **结论里记录 `tree_sha`**（不只是 `head_sha`），用于判断"结论是否仍然成立" | §2.3 | `internal/rules/`、`internal/check/writer.go` |
| 2 | **新 commit 到达时比较 tree hash**：内容没变（纯 rebase）→ 不重算、不作废；内容变了 → 重算并作废旧结论 | §2.3 | `internal/webhook/handler.go` |
| 3 | **判定结果用 label 落盘**（`cr-check/status/*`），互斥，且**先删后加** | §2.7 | `internal/check/writer.go`（新增 label 写入） |
| 4 | **check output 写成"分类 → 证据 → 下一步 → 依据版本"** | §2.9 | `internal/rules/` 的输出构造 |
| 5 | **多个判定维度聚合成一个 check**，别做成多个 required check | §2.1 | `internal/check/writer.go` |
| 6 | **输出里嵌 `<!-- META={...} -->`**（policy_version / tree_sha / 各维度结果 / 判定时间） | §2.11 | `internal/check/writer.go` |

### P2 —— 需要设计

| # | 行动 | 抄自 | 说明 |
|---|---|---|---|
| 7 | **引入 `do-not-merge/*` 式前缀约定**：`cr-check/hold`、`cr-check/invalid-cr`、`cr-check/out-of-window`… 判定逻辑 = "存在任一 `cr-check/*` → 不通过" | §2.2 | 配合 P1#3 |
| 8 | **override 必须带理由**，且理由要：不能以 `/` 开头、长度下限、**每一次出现都要**、存进评论留痕 | §2.8 | 新增 `internal/commands/` 模块 |
| 9 | **override 只能由真人做**，bot 永远不能放行自己的检查 | §2.8 + §2.10 | 授权模型要显式设计 |
| 10 | **报错评论里不能出现行首 `/`** —— 加回归测试断言 | §2.10 | 配合 P2#8 |
| 11 | **策略配置放 Git 仓库**，版本 = blob SHA；提供校验命令；**热生效 + 变更触发重算** | §2.12 | 对应 L3 policy_version |
| 12 | **Draft PR 跳过判定，但显式留痕** | §2.13 | 省配额 |

### P3 —— 锦上添花

| # | 行动 | 抄自 |
|---|---|---|
| 13 | **首次 PR 的欢迎评论**（引导文档 + bot 命令表） | §2.14 |
| 14 | **失败评论里指名道姓给下一步和联系人** | §2.14 |
| 15 | **按改动路径分级审批**（后期） | §2.5 |
| 16 | **tide 式"聚合 context 描述随状态变化"** | §2.1 |

### 与现有文档的联动

```
how-to-atomic-idempotency.md   ← 幂等/原子性/去重/重扫
          │
          │  §2.3 补充：L2 键要用 tree_sha 判断"是否需要重算"
          │  §2.8 补充：override 是人工兜底，必须留痕
          │  §8   对应：policy_version = 配置文件 blob SHA
          ▼
prow-pulls.md（本文）            ← 可解释性 / 状态外置 / 人机双读
```

---

## 5. 附录 A：证据速查

| 证据 | 位置 | 证明了什么 |
|---|---|---|
| PR #1026 body "Examples / Accepted / Rejected" | https://github.com/kubernetes-sigs/prow/pull/1026 | `require_rationale` 的完整语义与文案 |
| PR #1026 body "Bug found and fixed in an earlier run" | 同上 | ★ bot 解析自己输出的自提权 bug 及修法 |
| PR #1026 body "Roll out" | 同上 | 配置即代码 + `checkconfig` + 热生效 |
| PR #1028 评论 "I'm waiting for a kubernetes-sigs member to verify..." | https://github.com/kubernetes-sigs/prow/issues/1028 | trust gate（`ok-to-test`）与 merge gate 分离 |
| PR #1008 评论 "New changes are detected. LGTM label has been removed." | https://github.com/kubernetes-sigs/prow/issues/1008 | 新提交 → 撤销旧批准 |
| PR #1008 评论 "Needs approval from an approver in each of these files: ~~OWNERS~~ [petr-muller]" | 同上 | 路径级审批 + 满足后删除线 + META 空数组 |
| PR #1026 评论 "Skipping CI for Draft Pull Request." | https://github.com/kubernetes-sigs/prow/issues/1026 | Draft 跳过 CI 但明说 |
| `tide` status 观测（#1026/#1028/#1008/#1006/#1013/#995/#1065/#1058） | commit status API | 聚合 context 的 state/description 语义 |
| `pkg/labels/labels.go` | https://github.com/kubernetes-sigs/prow/blob/main/pkg/labels/labels.go | `do-not-merge/*` 等 label 全集 |
| `pkg/plugins/lgtm/lgtm.go` | https://github.com/kubernetes-sigs/prow/blob/main/pkg/plugins/lgtm/lgtm.go | tree hash 机制 + 撤销批准 + 重新请求 review |
| `pkg/tide/status.go` | https://github.com/kubernetes-sigs/prow/blob/main/pkg/tide/status.go | description 文案生成 + "label 问题优先" |
| `pkg/config/tide.go` | https://github.com/kubernetes-sigs/prow/blob/main/pkg/config/tide.go | required / missing labels 互斥校验 |
| PR #799 body | https://github.com/kubernetes-sigs/prow/pull/799 | 排他标签前缀 |
| `OWNERS` | https://github.com/kubernetes-sigs/prow/blob/main/OWNERS | approvers / emeritus_approvers |

---

## 6. 附录 B：复现命令

```bash
# ① 看 PR 列表及其标签（label 是 Prow 的状态载体）
gh pr list --repo kubernetes-sigs/prow --state open --limit 30 \
  --json number,title,author,labels,isDraft

# ② 看某个 PR 的全部 bot 评论
gh api repos/kubernetes-sigs/prow/issues/1026/comments --paginate \
  --jq '.[] | "─── \(.user.login) [\(.created_at)]\n\(.body)\n"'

# ③ 看 head SHA 上的 commit status（Prow 的门禁在这里）
sha=$(gh api repos/kubernetes-sigs/prow/pulls/1026 --jq .head.sha)
gh api repos/kubernetes-sigs/prow/commits/$sha/status \
  --jq '.statuses[] | "\(.context) | \(.state) | \(.description) | \(.target_url)"'

# ④ 对比：check runs（Prow 自己一个都没有，只有 netlify 用 check run）
gh api repos/kubernetes-sigs/prow/commits/$sha/check-runs \
  --jq '.check_runs[] | "\(.name) | \(.app.slug) | \(.status)/\(.conclusion)"'

# ⑤ 看 tide context 在不同 PR 上的 description
for n in 1028 1008 1006 1013 995 1065 1058; do
  sha=$(gh api repos/kubernetes-sigs/prow/pulls/$n --jq .head.sha)
  echo -n "#$n : "
  gh api repos/kubernetes-sigs/prow/commits/$sha/status \
    --jq '.statuses[] | select(.context=="tide") | "\(.state) — \(.description)"'
done

# ⑥ 读 Prow 的 label 常量表
gh api repos/kubernetes-sigs/prow/contents/pkg/labels/labels.go --jq .content | base64 -d

# ⑦ 读 lgtm 插件的 tree hash 机制
gh api repos/kubernetes-sigs/prow/contents/pkg/plugins/lgtm/lgtm.go --jq .content | base64 -d \
  | sed -n '417,500p'

# ⑧ 读 tide 的 description 生成逻辑
gh api repos/kubernetes-sigs/prow/contents/pkg/tide/status.go --jq .content | base64 -d \
  | sed -n '180,230p'

# ⑨ ⚠️ 会 404：需要对该仓库的 admin 权限
gh api repos/kubernetes-sigs/prow/branches/main/protection
```

---

## 7. 小结

如果只带走三句话：

1. **★ 状态要外置到 GitHub（label + status），不要放在 bot 的内存里。**
   Prow 靠这个做到了进程重启、副本切换后状态不丢、结论永远可查。
   —— 我们的 `recheck.Registry` 现在是进程内内存，是同一个毛病的另一种表现。

2. **★ "为什么不能合并"必须是可列举、可展示、可组合的。**
   Prow 把它拆成 `do-not-merge/*` 标签 + 一个 `tide` 聚合 context，
   并让 description 直接说出缺什么。
   —— 我们的 CR Check 现在只有 pass/fail，**这是最大的产品差距**。

3. **★ 结论必须绑定代码内容（tree hash），否则会拿着旧结论放行新代码。**
   Prow 用 bot 评论里的 tree hash 做到了纯 rebase 不误伤、内容真变才作废。
   —— 这是我们从"能跑"到"可信"必须补的一环。

---

## 相关文档

| 文档 | 关系 |
|---|---|
| [`how-to-atomic-idempotency.md`](./how-to-atomic-idempotency.md) | 幂等/原子性/去重/重扫 —— 本文补它的"可解释性"和"内容绑定" |
| [`how-to-using-git-apps.md`](./how-to-using-git-apps.md) | 装好 App 之后仓库侧要做什么 |
| [`install-git-apps.md`](./install-git-apps.md) | Org 级 vs 仓库级 vs 分支 |
| [`git-apps/14-rulesets-and-gitapp-gate.md`](./git-apps/14-rulesets-and-gitapp-gate.md) | 门禁侧：check 怎么变成"必须通过" |
| [`git-apps/cr-check/`](./git-apps/cr-check/) | Go 实现（§4 行动清单的对象） |
