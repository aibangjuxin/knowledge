# how-to-atomic-idempotency · 开发 GitHub App（如 CR Check）时的原子性与幂等性

> **副标题**：GitHub 的 webhook 是"至少一次投递、可能乱序、可能并发、不自动重投"，
> 而它的 API "既没有事务、也没有 upsert"。那我们凭什么保证"一个 PR 只有一个结论、且这个结论是对的"？
>
> **一句话结论**
> **不要追求 exactly-once（做不到），要追求 "effectively-once"：
> 用 `X-GitHub-Delivery` 挡住"同一事件重复到达"，
> 用 `(repo, check_name, head_sha)` 这个业务键保证"同一目标只有一个 check run、且内容收敛"，
> 用 `in_progress → completed` 的两段式让"中间态"永远表现为"未通过"（fail-closed）。**
> 幂等键选错，是这类系统 90% 的线上事故的根因。

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-tldr) | TL;DR：10 条 |
| [§1](#1-先把原子性幂等性在本场景下的确切含义钉死) | 先把"原子性""幂等性"在本场景下的确切含义钉死 |
| [§2](#2-github-给了什么--没给什么事实基础) | **GitHub 给了什么 / 没给什么（事实基础）** |
| [§3](#3--幂等键怎么选三层键) | ★ **幂等键怎么选：三层键** |
| [§4](#4--原子性你能控制的最小事务单元) | ★ **原子性：你能控制的最小事务单元** |
| [§5](#5--写入侧的竞态toctou与三种修法) | ★ **写入侧的竞态（TOCTOU）与三种修法** |
| [§6](#6-并发与乱序版本号与分布式锁) | 并发与乱序：版本号与分布式锁 |
| [§7](#7-崩溃恢复状态不能卡死) | 崩溃恢复：状态不能卡死 |
| [§8](#8-策略变更的原子性) | 策略变更的原子性（policy version） |
| [§9](#9-副作用的原子性outbox-模式) | 副作用的原子性：Outbox 模式 |
| [§10](#10-配额背压与降级) | 配额、背压与降级 |
| [§11](#11--怎么证明你的实现真的是幂等的) | ★ **怎么证明你的实现真的是幂等的（测试矩阵）** |
| [§12](#12-对现有-cr-check-实现的差距分析) | **对现有 `git-apps/cr-check/` 实现的差距分析** |
| [§13](#13-反模式) | 反模式 |
| [§14](#14-一页速查清单) | 一页速查清单 |
| [§15](#15-官方文档--本仓库文档) | 官方文档 + 本仓库文档 |

---

## 0. TL;DR

1. **Exactly-once 做不到**。GitHub 是 **at-least-once** 投递 + **无序** + **可并发**，
   写入侧**没有事务、没有 upsert、没有 `Idempotency-Key` 头**。
2. **两个词在本文的确切含义**：
   - **幂等** = 同一输入重复执行 N 次，**对外可见的最终状态**与执行 1 次相同（不是"函数只跑一次"）。
   - **原子** = 任何时刻从外部观察，状态都是"旧的完整态"或"新的完整态"，**看不到撕裂的中间态**。
3. **幂等键要分三层，用途完全不同**：
   | 层 | 键 | 挡什么 |
   |---|---|---|
   | L1 | `X-GitHub-Delivery` | 同一事件重复投递 / 重放攻击 |
   | L2 | `(repo_id, check_name, head_sha)` | 同一目标出现多个 check run / 结论不一致 |
   | L3 | `policy_version` | 策略变了但结论没重算 |
4. **只用 L1 是不够的**——`synchronize` 事件每次 SHA 都不同，
   L1 会让**每次推送都判定一次**，而 L2 才能保证"一个 SHA 只有一个结论"。
5. **只用 L2 也是不够的**——策略改了之后，同一个 SHA 的正确结论已经变了，
   必须靠 L3 让系统知道"要重算"。
6. **两段式写入是这里的"原子性"关键**：
   `in_progress` → `completed`。
   因为 **`in_progress` 不算通过**（只有 `success`/`skipped`/`neutral` 算通过），
   所以**任何中途崩溃都表现为"拦住合并"而不是"放行合并"**——这就是 fail-closed。
7. **写入侧天然有 TOCTOU**：`POST /check-runs` **永远新建**（201），
   没有"按 name 覆盖"。任何"先 list 再 create/update"的写法都有竞态。
   → 用 `external_id` 做业务键 + 分布式锁 + 兜底用 suite 的 get-or-create。
8. **`POST /check-suites` 是 GitHub 唯一给你的幂等写原语**：
   套件已存在返回 **200**，新建返回 **201**。这是免费的 get-or-create，务必利用。
9. **判定的真相来源必须是"当前 PR 快照"，不是事件 payload**。
   事件会乱序、会陈旧、可能根本不重投（GitHub **不自动重投失败投递**）。
10. **最后一道兜底是定时重扫**。因为 required status check 是"按 head SHA 查已存在的结论"，
    GitHub **不会在 merge 时刻重新执行你的规则**——维护窗口关了、CR 被撤了，
    那个绿 check 还在，就会被放行。**只有重扫能救。**

---

## 1. 先把"原子性""幂等性"在本场景下的确切含义钉死

这两个词在分布式语境下被用得很含混，先约定清楚，否则后面的方案无法评判。

### 1.1 幂等（Idempotency）

> **定义**：操作 `f` 是幂等的，当且仅当 `f(f(x)) ≡ f(x)`（对**可观测的最终状态**而言）。

**关键澄清**：幂等 **≠ "只执行一次"**。

| 说法 | 对不对 | 说明 |
|---|---|---|
| "幂等 = 保证函数只被调用一次" | ❌ | 那是"互斥/恰好一次"，而且**做不到**（进程崩溃后你无法知道"到底执行没执行"）|
| "幂等 = 重复执行不产生额外副作用" | ⚠️ 不完整 | 重复执行**可以**产生副作用，只要**副作用是同一个、且可重放** |
| "幂等 = 重复执行后，最终状态与执行一次相同" | ✅ | **本文采用这个定义** |

**在 GitHub App 场景的具体化**：

```
"把判定结论写进 PR" 这个动作，必须满足：

   写一次   → PR 上有 1 个 cr-check，conclusion = failure
   写两次   → PR 上仍然只有 1 个 cr-check，conclusion = failure
   写一百次 → PR 上仍然只有 1 个 cr-check，conclusion = failure
   中间崩溃 → PR 上要么没有 cr-check，要么有 1 个 cr-check（不能有 2 个）
```

### 1.2 原子性（Atomicity）

> **定义**：一个操作是原子的，当且仅当**任何并发观察者**都只能看到"操作前"或"操作后"，
> 看不到中间撕裂状态。

**在 GitHub App 场景的具体化**：

```
写结论 = 一次状态迁移：  (无结论) ──► (in_progress) ──► (success | failure)

"原子"的要求：
  ① 不会同时存在两个 cr-check（一半旧一半新）
  ② 不会存在"conclusion=success 但 output 里写的是 failure 的理由"
  ③ 不会存在"check 说通过了，但配套的 comment 没发"这类撕裂
```

**这里最容易踩的误解**：不要把"原子性"理解成数据库 ACID。
**GitHub 不给你事务**，你唯一能争取的原子性是：

| 原子性层级 | GitHub 给不给 | 你的手段 |
|---|---|---|
| 单个 check run 的状态迁移 | ✅ 给（`PATCH` 是原子的） | 用 `PATCH`，不要用"删了再建" |
| **同一 (name, sha) 下只有一个 check run** | ❌ 不给 | `external_id` + 锁 + 收敛式写入 |
| 多个 check run + comment + label 一起生效 | ❌ 不给 | **Outbox + 最终一致**（§9）|
| 多个 GitHub 仓库之间 | ❌ 不给 | 别设计成需要跨仓库原子 |

---

## 2. GitHub 给了什么 / 没给什么（事实基础）

> 以下都是**实测/官方文档核对过**的事实，不是经验之谈。括号里是来源。

### 2.1 投递侧（webhook → 你的服务）

| 事实 | 对设计的影响 |
|---|---|
| **至少一次投递**。同一事件可能被投递多次（手动 Redeliver、服务超时被判定失败后重投）| 处理逻辑必须幂等 |
| **`X-GitHub-Delivery` 是投递 GUID**；官方 best practice 明确建议用它"确保每个投递对每个事件唯一"，**用来防重放攻击** | ★ 它就是 L1 幂等键 |
| **"If you request a redelivery, the `X-GitHub-Delivery` header will be the same as in the original delivery."** | ★ **重投的 GUID 不变** ⇒ 用 GUID 去重能正确折叠"重投" |
| **"GitHub does not automatically redeliver failed deliveries."** | ⇒ **事件丢了就是丢了**，必须自建兜底（定时重扫 + 失败投递巡检）|
| **只能重投过去 3 天内的投递**（UI 与 API 都是）| ⇒ 宕机超过 3 天，事件**永久丢失**，只能靠重扫 |
| **必须在 10 秒内返回 2XX**，否则 GitHub 断开连接并判定投递失败 | ⇒ 必须"先 ACK，后异步" |
| **不保证顺序** | ⇒ 不能假设事件按发生顺序到达 |
| **投递可能并发**（大 PR 合并时几十个事件同时到）| ⇒ 处理逻辑要线程/副本安全 |
| 官方提供了"自动重投失败投递"的**脚本范式**（用 App 的 JWT 调 GitHub App webhook deliveries API）| ⇒ 我们可以自己实现"自动重投"，但**去重仍必须自己做** |

### 2.2 写入侧（你的服务 → GitHub Checks API）

| 端点 | 语义 | 原子性 |
|---|---|---|
| `POST /repos/{owner}/{repo}/check-runs` | **永远新建**，返回 **201** | ❌ 没有 upsert |
| `PATCH /repos/{owner}/{repo}/check-runs/{check_run_id}` | 更新既有 run，返回 200 | ✅ 单 run 状态迁移是原子的 |
| **`POST /repos/{owner}/{repo}/check-suites`** | **"套件已存在" → 200；"新建" → 201** | ✅ **★ GitHub 唯一的幂等写原语（get-or-create）** |
| `GET /repos/{owner}/{repo}/check-runs?check_name=&status=&filter=latest\|all&app_id=` | 查已有 run；默认 `filter=latest` | 只读 |
| `POST /repos/{owner}/{repo}/check-runs/{id}/rerequest` | 201；403（不可 rerequest 或不属于本 App）；422 | — |
| `check_run` webhook 的 action | `created` / `completed` / **`requested_action`** / **`rerequested`** | ⇒ **用户点"重新运行"也会打到你** |

**`external_id` 的官方定义**："A reference for the run on the integrator's system."
（中文：本次运行在集成方系统里的一个引用标识。）
→ **这是 GitHub 留给你放业务键的地方**，也是你事后反查"这个 run 是不是我写的"的唯一凭据。

**`conclusion` 的合法枚举**（官方 API schema）：
`action_required` / `cancelled` / `failure` / `neutral` / `success` / `skipped` / `stale` / `timed_out`

> 官方备注：**"You cannot change a check run conclusion to `stale`, only GitHub can set this."**
> → 你的 App **永远写不出 `stale`**，也就无法用"过期"来表达"这个结论已经不准了"，
> 只能自己重写一个新结论。

### 2.3 消费侧（required status check 怎么取）

| 事实 | 对设计的影响 |
|---|---|
| GitHub 取 **该 head SHA + 该名称下"最新"的 check run** 的结论 | ⇒ 同名多 run 时"最新"说了算 ⇒ **重复创建是安全的**（只要内容一致），**不一致就是灾难** |
| 通过的结论集合是 `success` / `skipped` / `neutral` | ⇒ **`in_progress` / `queued` / `action_required` / `failure` / `timed_out` 都会挡住合并** ⇒ 这就是 fail-closed 的机制基础 |
| required status check **按 head SHA 查已存在的结论**，**merge 时刻不会重新执行你的规则** | ⇒ ★ **必须定时重扫**（否则维护窗口关了 / CR 被撤了，旧绿结论仍会放行）|
| 配置 required status check 时，可以选"哪个 App 是这个状态的**预期来源**"，但前提是 **"该 App 最近设置过这个 check"** | ⇒ **必须先让 App 跑出第一个 check，再去配门禁**；且**必须锁定来源 App**（否则任何有写权限的人都能伪造同名 check 骗绿）|

### 2.4 GitHub **没有**给你的东西

| 缺失 | 后果 | 补法 |
|---|---|---|
| 没有多资源事务 | check run + comment + label 不能原子生效 | Outbox（§9）|
| 没有 `Idempotency-Key` 请求头 | 不能靠 HTTP 层去重 | 自己算幂等键 + 自己去重 |
| 没有"按 name upsert check run"的 API | 重复创建可能发生 | `external_id` + 锁 + 收敛 |
| 不自动重投失败投递 | 事件永久丢失 | 定时重扫 + 失败投递巡检 |
| 不保证顺序 | 结论可能基于陈旧状态 | 版本号 + 重读快照（§6）|
| 没有"让 App 声明结论新鲜度"的机制 | 旧结论会一直有效 | 重扫 + 主动改写 |

---

## 3. ★ 幂等键怎么选：三层键

**这是整篇文章最重要的一节。** 幂等键选错，后面全是补丁。

### 3.1 三层键的分工

```
┌──────────────────────────────────────────────────────────────┐
│ L1  投递层键  =  X-GitHub-Delivery                           │
│     语义：「这是同一次事件投递」                              │
│     挡：重复投递 / 重放攻击 / Redeliver                       │
│     生命周期：短期（TTL 24h~7d）                              │
│     ⚠️ 挡不住"不同投递但同一目标"                              │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│ L2  目标层键  =  (repo_id, check_name, head_sha)             │
│     语义：「这个 PR 的这个 commit 的这个检查，应该只有一个结论」 │
│     挡：并发写导致的重复 check run / 结论不一致                │
│     生命周期：与 PR 同生命周期                                │
│     ★ 这是"最终一致"的锚点                                    │
└──────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────┐
│ L3  版本层键  =  policy_version（或 rule_set_hash）          │
│     语义：「在这个策略版本下，这个结论才是对的」                │
│     挡：策略改了但结论没重算                                   │
│     生命周期：策略版本的生命周期                               │
└──────────────────────────────────────────────────────────────┘
```

### 3.2 为什么 L1 不够（用 cr-check 的真实场景推演）

```
10:00  开发者 push commit A
       → 事件 E1 (delivery=d1, sha=A) 到达
10:00  开发者 push commit B
       → 事件 E2 (delivery=d2, sha=B) 到达
10:00  开发者给 PR 打 label cr/1234
       → 事件 E3 (delivery=d3, sha=B) 到达
```

| 键 | E1 | E2 | E3 | 结果 |
|---|---|---|---|---|
| **只用 L1** | 处理(sha=A) | 处理(sha=B) | 处理(sha=B) | ✅ 正确 |
| | | | | ⚠️ 但如果 E2/E3 **乱序**（E3 先到、E2 后到），E3 判出"无 CR 号 → 失败"，E2 后到又判"有 CR 号 → 成功"——**只要 E2 的结论是基于 payload 且 payload 里没有 label，就会判错** |

**这就是"判定必须基于当前 PR 快照，而不是事件 payload"的根因**：
`synchronize` 事件的 payload 里**没有**后来才加的 label；
`labeled` 事件的 payload 里**没有**最新的 commit SHA。

→ **正确做法**：任何事件到达，都**重新读一次 PR 的当前状态**（`GET /repos/{o}/{r}/pulls/{n}`），
用**快照**做判定。这样无论事件怎么乱序、怎么重复，结论都基于同一份"当前真相"。

### 3.3 为什么 L2 也不够

策略改了（比如维护窗口从 22:00-02:00 改成 21:00-03:00），但 PR 的 SHA 没变。
L2 的键 `(repo, name, sha)` 没变 ⇒ 系统认为"已经判过了" ⇒ **结论不更新**。

→ L3：`policy_version` 参与键，或者更简单地：
**判定结果里记录 policy_version；重扫时发现 `policy_version != 当前版本` 就重算。**

```go
// L3 的落地形态：结论带版本，重扫时比对
type Verdict struct {
    Repo          string
    CheckName     string
    HeadSHA       string
    PolicyVersion string   // ★ L3
    Conclusion    string
    EvaluatedAt   time.Time
}
```

### 3.4 三层键的完整实现（L1 必须用"一次原子操作"）

> ⚠️ **常见的错误实现**：先 `Seen(key)` 再 `Remember(key)` —— **这是两次调用，不是原子的**。
> 两个并发副本（甚至同一个副本的两个 goroutine）可能同时看到"没 seen 过"，然后都去处理。

```go
// ❌ 错误：Seen + Remember 两次调用，中间有竞态窗口
seen, _ := store.Seen(ctx, key)
if seen { return nil }
... 处理 ...
store.Remember(ctx, key, ttl)

// ✅ 正确：一次原子操作，"插入成功"= "我是第一个"
ok, err := store.MarkIfAbsent(ctx, key, ttl)   // Redis: SET key 1 NX EX ttl
if !ok { return nil }   // 已被别人处理过
```

Redis 实现：

```go
// MarkIfAbsent 用 SET NX 实现原子的"首次占位"。
// 返回 true 表示本次调用是第一个拿到该 key 的。
func (s *RedisStore) MarkIfAbsent(ctx context.Context, key string, ttl time.Duration) (bool, error) {
    res, err := s.client.SetNX(ctx, s.prefix+key, "1", ttl).Result()
    if err != nil {
        return false, fmt.Errorf("redis setnx: %w", err)
    }
    return res, nil
}
```

> **但要小心一个坑**：`SET NX` 占位成功 ≠ 业务处理成功。
> 如果占位后进程崩溃，这个 key 会占着 TTL，导致**重投被误判为"已处理"**而永久丢失。
>
> **两种修法（按你的容忍度选）**：
> - **A（推荐，弱一致）**：占位用**短 TTL**（如 5 分钟），处理完成后再写一个**长 TTL** 的"已完成"标记。
>   崩溃后短 TTL 到期，重投仍会被处理。
> - **B（强一致）**：占位与业务写在**同一个数据库事务**里（见 §9 Outbox）。

```go
// A 方案：两段式标记
func (h *Handler) claim(ctx context.Context, delivery string) (bool, error) {
    // ① 短 TTL 占位：防止并发重复处理
    ok, err := h.Store.MarkIfAbsent(ctx, "inflight:"+delivery, 5*time.Minute)
    if err != nil || !ok {
        return false, err
    }
    // ② 长 TTL 完成标记：真正处理过
    done, err := h.Store.Seen(ctx, "done:"+delivery)
    if err != nil { return false, err }
    if done { return false, nil }
    return true, nil
}
// 处理成功后：Remember("done:"+delivery, 7*24h) + 删除 inflight
```

---

## 4. ★ 原子性：你能控制的最小事务单元

### 4.1 check run 的状态机

```
                  ┌──────────────┐
   (不存在) ────► │  in_progress │ ────► │ completed            │
                  │  (进行中)    │        │ conclusion =         │
                  └──────────────┘        │   success / failure / │
                          ▲                │   neutral / skipped / │
                          └────────────────│   action_required /  │
                            (重评时)        │   timed_out / cancelled│
                                           └───────────────────────┘

   ★ in_progress / queued 都不算"通过"
   ★ 所以任何时刻只要不是 completed，就是"拦住合并"
```

**两段式写入为什么是这个场景的原子性基石**：

| 单段（直接写 completed） | 两段（先 in_progress 再 completed） |
|---|---|
| 重评期间，旧的 `success` 还在 → **新结论还没算完，旧结论仍放行** ❌ | 重评一开始就把 check 置为 `in_progress` → **立刻挡住合并**，直到新结论出来 ✅ |
| "读到的是哪个结论"有歧义 | 状态迁移是 `PATCH`，单 run 原子 ✅ |

**代码里已有的正确直觉**（`git-apps/cr-check/internal/check/writer.go`）：

```go
// MarkInProgress 把 check 置为"评估中"。
// 作用：① 同 SHA 重评时旧 success 不会冒充新结论；
//       ② in_progress 不属于 successful/skipped/neutral → 合并被正确阻断。
```
✅ 这个设计是对的，**要保留**。

### 4.2 但两段式有个反面：卡死

```
in_progress ──(进程被 kill / 判定抛异常 / 网络中断)──► 永远 in_progress
                                                       ↓
                                        PR 永远合不了，且没人知道
```

**这是"fail-closed"的代价：安全，但会误伤。**

必须配套两个机制：

| 机制 | 作用 | 实现 |
|---|---|---|
| **① 卡死检测 + 接管** | 发现 `in_progress` 超过阈值（如 10 分钟）→ 重算 | 定时扫 `GET /check-runs?status=in_progress` 或本地状态表 |
| **② 判定异常必须落终态** | 判定失败也要写一个终态（而不是留着 in_progress）| 判定出错 → 写 `conclusion=action_required` 或 `failure` + 说明 |

> ⚠️ **强烈建议**：判定出错时写 **`action_required`** 而不是 `failure`。
> `action_required` 表示"需要人介入"，语义上比"你的 PR 不合规"更准确，
> 而且它**同样不通过**（保持 fail-closed）。

```go
func (h *Handler) Complete(ctx context.Context, ref check.Ref, out rules.Outcome, evalErr error) error {
    if evalErr != nil {
        // 判定失败：也必须落终态，不能停在 in_progress
        return h.Writer.Complete(ctx, ref, rules.Outcome{
            OK:        false,
            Conclusion: "action_required",
            Summary:   "判定失败（内部错误）：" + evalErr.Error(),
        })
    }
    return h.Writer.Complete(ctx, ref, out)
}
```

### 4.3 GitHub 给的唯一幂等写原语：check suite

```http
POST /repos/{owner}/{repo}/check-suites
{ "head_sha": "d6fde92930d4715a2b49857d24b940956b26d2d3" }

→ 200  Response when the suite already exists   ← ★ 幂等
→ 201  Response when the suite was created
```

**用法**：把它当成 `GET-OR-CREATE` 的原子原语。

```go
// GetOrCreateSuite 是 GitHub 提供的原子 get-or-create。
// 200 = 已存在（拿到 id），201 = 新建（拿到 id）。
// ⚠️ go-github v88 的签名：opts 是 *CreateCheckSuiteOptions，HeadSHA 是普通 string。
func GetOrCreateSuite(ctx context.Context, cl *gogithub.Client, owner, repo, sha string) (int64, error) {
    suite, _, err := cl.Checks.CreateCheckSuite(ctx, owner, repo, &gogithub.CreateCheckSuiteOptions{
        HeadSHA: sha,
    })
    if err != nil {
        return 0, fmt.Errorf("创建 check suite: %w", err)
    }
    return suite.GetID(), nil
}
```

> ⚠️ 注意：**suite 是按 (repo, head_sha) 的**，不是按 check name 的。
> 它保证"一个 SHA 只有一个 suite"，**不能**保证"一个 name 只有一个 run"。
> 但它给了你一个**稳定的容器 id**，可以在 suite 维度做查找与去重。

---

## 5. ★ 写入侧的竞态（TOCTOU）与三种修法

### 5.1 竞态长什么样

GitHub **没有**"按 name upsert check run"的 API。任何实现都只能这样：

```
① GET /check-runs?check_name=X        ← 读
② if 找到 → PATCH /check-runs/{id}    ← 写
   else    → POST /check-runs         ← 写
```

**问题**：① 和 ② 之间没有原子性。

```
时刻  副本 A                          副本 B
─────────────────────────────────────────────────────────────
 t1   GET → 没找到 X
 t2                                  GET → 没找到 X
 t3   POST → 创建 run #1
 t4                                  POST → 创建 run #2   ← ★ 两个同名 run！
```

**后果**（记住 GitHub 的取用规则：**取最新的那个**）：
- 两个 run 内容一致 → 无害（取到哪个都一样）✅
- 两个 run 内容**不一致** → **随机取到一个** → **门禁结果随机** ❌❌❌

**这就是"要么保证只有一个 run，要么保证所有 run 内容一样"的原因。**

### 5.2 当前 `cr-check` 实现的现状

`git-apps/cr-check/internal/check/writer.go` 的 `upsert()`：

```go
existing, _, err := cl.Checks.ListCheckRunsForRef(ctx, ref.Owner, ref.Repo, ref.SHA, nil)
for _, r := range existing.CheckRuns {
    if r.GetName() != ref.Name { continue }
    ...UpdateCheckRun(r.GetID(), opts)   // 找到就更新
    return err
}
...CreateCheckRun(opts)                  // 没找到就新建
```

- ✅ **方向正确**（同名覆盖，而不是每次新建）
- ⚠️ **存在 TOCTOU**：上面的 t1/t2/t3 竞态
- ⚠️ **`external_id` 完全没用上** → 无法反查"这个 run 是不是我写的"
- ⚠️ `ListCheckRunsForRef` **没带 `check_name` 过滤** → 把该 SHA 上所有 run 都拉回来再在内存里过滤
  （GitHub 的 `filter` 默认是 `latest`，但**没有 name 过滤**时行为需要实测确认，建议显式传 `check_name`）

### 5.3 三种修法

#### 修法 1（推荐）：`external_id` 业务键 + 分布式锁 + 收敛式写入

```go
// ── L2 业务键：确定性、可反查 ──────────────────────────────
// 同一个 (repo, check_name, head_sha) 永远算出同一个 external_id。
// 用途：① 事后反查"这个 run 是不是我写的"；② 区分"我的 run"和"别人伪造的同名 run"。
//
// ⚠️ Ref 里需要额外带一个 RepoID（GitHub 的数字仓库 ID，比 owner/repo 字符串更稳定：
//    仓库改名/转移时 owner/repo 会变，数字 ID 不变）。
func ExternalID(repoID int64, checkName, headSHA string) string {
    h := sha256.Sum256([]byte(fmt.Sprintf("%d|%s|%s", repoID, checkName, headSHA)))
    return hex.EncodeToString(h[:])[:32]
}

// ── 幂等 upsert ─────────────────────────────────────────────
// 关键：读到的既有 run，如果 external_id 与我们一致 → 一定更新它；
//       如果 external_id 不一致（说明是别人伪造的同名 run）→ 不要动它，另建一个带我们 external_id 的。
func (w *GitHubWriter) upsert(ctx context.Context, ref Ref, status, conclusion, title, summary string) error {
    cl, err := w.factory.Client(InstallationIDFromContext(ctx))
    if err != nil { return err }

    extID := ExternalID(ref.RepoID, ref.Name, ref.SHA)
    output := &gogithub.CheckRunOutput{Title: &title, Summary: &summary}

    // ① 查同名 run（显式带 check_name）
    opts := &gogithub.ListCheckRunsOptions{
        CheckName: gogithub.String(ref.Name),
        Filter:    gogithub.String("all"),   // 要 all，否则可能漏掉历史的
    }
    list, _, err := cl.Checks.ListCheckRunsForRef(ctx, ref.Owner, ref.Repo, ref.SHA, opts)
    if err != nil { return fmt.Errorf("列出已有 check run: %w", err) }

    // ② 优先更新"external_id 匹配"的那一个（那才是我们的 run）
    var target *gogithub.CheckRun
    for i := range list.CheckRuns {
        if list.CheckRuns[i].GetExternalID() == extID {
            target = &list.CheckRuns[i]
            break
        }
    }

    if target != nil {
        u := &gogithub.UpdateCheckRunOptions{
            Name: ref.Name, Status: &status, Output: output, ExternalID: &extID,
        }
        if conclusion != "" { u.Conclusion = &conclusion }
        if status == "completed" { u.CompletedAt = &gogithub.Timestamp{Time: time.Now()} }
        _, _, err = cl.Checks.UpdateCheckRun(ctx, ref.Owner, ref.Repo, target.GetID(), u)
        return err
    }

    // ③ 没有我们的 run → 新建（带上 external_id）
    c := &gogithub.CreateCheckRunOptions{
        Name: ref.Name, HeadSHA: ref.SHA, Status: &status, Output: output, ExternalID: &extID,
    }
    if conclusion != "" { c.Conclusion = &conclusion }
    if status == "completed" { c.CompletedAt = &gogithub.Timestamp{Time: time.Now()} }
    _, _, err = cl.Checks.CreateCheckRun(ctx, ref.Owner, ref.Repo, c)
    return err
}
```

#### 修法 2：分布式锁（消除 TOCTOU 窗口）

```go
// key = (repo, check_name, head_sha)，保证同一目标同一时刻只有一个写入者。
// TTL 必须 > 一次写入的最长耗时（含重试），否则锁先过期 → 竞态重现。
lockKey := fmt.Sprintf("cr-check:lock:%d|%s|%s", ref.RepoID, ref.Name, ref.SHA)

ok, err := locks.Acquire(ctx, lockKey, 30*time.Second)
if err != nil { return err }
if !ok {
    // 拿不到锁：说明有别人在写 → 稍后重试（不要直接跳过，否则可能永远不写）
    return retryLater(ctx, ref)
}
defer locks.Release(ctx, lockKey)

return w.upsertLocked(ctx, ref, status, conclusion, title, summary)
```

> ⚠️ **锁 TTL 的取舍**：
> - TTL 太短 → 锁过期后别人进来 → 竞态重现
> - TTL 太长 → 持锁者崩溃后，别人要等很久 → 判定延迟
> - **建议**：TTL = 30s；拿不到锁时**不要放弃**，改成"延迟重试"（退避后重试 3 次）
>
> ⚠️ **锁不是万能的**：它防的是"并发写"，防不了"网络分区导致的脑裂"。
> 所以**修法 1 的收敛式写入必须同时做**——锁是优化，`external_id` + 内容收敛才是正确性。

#### 修法 3：接受"可能多个 run"，但保证内容收敛（最简单、最稳）

```go
// 每次都 PATCH 已存在的那一个；找不到就 POST。
// 即使并发创建了 2 个同名 run，它们的 conclusion 也必然相同
//（因为结论只由 (repo, head_sha, policy_version) 决定，是纯函数）。
// → GitHub 取"最新的"那个，取到哪个都一样。
```

> **什么时候修法 3 就够了？**
> 当**判定是纯函数**时：`conclusion = f(PR 当前快照, policy)`。
> 同样的输入必然得到同样的输出 ⇒ 多个 run 内容一致 ⇒ 取最新的那个也无害。
>
> **什么时候不够？**
> 当判定里掺了**非确定性**（时间窗口边界、CR 平台的瞬时状态、外部 API 的抖动）时。
> 这时必须上修法 1 + 修法 2。

**本项目的情况**：cr-check 的判定依赖 **CR 平台的实时状态**和**维护窗口的时间边界**，
→ **不是纯函数** ⇒ 修法 1 + 修法 2 都要做。

---

## 6. 并发与乱序：版本号与分布式锁

### 6.1 乱序的两种形态

| 形态 | 例子 | 危害 |
|---|---|---|
| **同一 PR，不同 SHA，乱序到达** | `synchronize(sha=B)` 先于 `synchronize(sha=A)` 到达 | 给旧 SHA 写结论（无害，因为结论绑 SHA）<br>但如果共享状态被污染 → 有害 |
| **同一 PR，同一 SHA，不同 action，乱序到达** | `labeled` 先于 `synchronize` 到达 | ★ **基于 payload 判定就会判错** |

**核心防御：判定输入 = 当前 PR 快照，不是事件 payload。**

```go
// ❌ 错误：直接用事件 payload 里的 PR 信息
pr := rules.PRInfo{
    BaseRef: ev.PullRequest.Base.Ref,
    HeadSHA: ev.PullRequest.Head.SHA,
    Labels:  labelsOf(ev.PullRequest.Labels),
    Body:    ev.PullRequest.Body,
}

// ✅ 正确：重新拉一次 PR 的当前状态
pr, err := gh.GetPullRequest(ctx, owner, repo, number)
if err != nil { return err }   // 拉不到 → 重试，别用旧数据
```

> ⚠️ **这会让每次事件多一次 API 调用**。配额要算进去（§10）。
> 折中：只对**会影响判定的 action** 重拉（`synchronize` / `labeled` / `unlabeled` / `edited` / `opened` / `reopened`），
> 对 `closed` / `assigned` 之类直接忽略。

### 6.2 共享状态的版本号

如果你的系统里有一张"PR 当前状态"的表（不只是 check run），它就是乱序的受害者。

```go
type PRState struct {
    Repo        string
    PRNumber    int
    HeadSHA     string    // ★ 版本号：单调递增的事实来源
    Conclusion  string
    PolicyVersion string  // ★ L3
    UpdatedAt   time.Time
}

// 保存时做"单调检查"：只接受不比当前版本旧的写入。
func (s *Store) SaveVerdict(ctx context.Context, v Verdict) error {
    cur, err := s.Get(ctx, v.Repo, v.PRNumber)
    if err != nil { return err }
    if cur != nil && isStale(v, cur) {
        // v 是更旧的版本 → 丢弃，不覆盖当前状态
        return nil
    }
    return s.Put(ctx, v)
}

// isStale：head_sha 不同就比"是否是当前 PR 的 head"；policy_version 用语义化版本比较。
func isStale(v, cur Verdict) bool {
    if v.HeadSHA != cur.HeadSHA {
        return true    // 不是当前 head → 陈旧
    }
    return cmpVersion(v.PolicyVersion, cur.PolicyVersion) < 0
}
```

> ★ **关键点**：**check run 本身不需要"陈旧保护"**——
> 因为每个 SHA 有自己的 check run，写旧 SHA 的结论**不会污染**当前 SHA 的结论。
> 需要陈旧保护的是**跨 SHA 的共享状态**（比如你的数据库里那张 PR 表、你的缓存）。

### 6.3 分布式锁 vs 单调收敛

| | 分布式锁 | 单调收敛（版本号） |
|---|---|---|
| 防什么 | 并发写同一目标 | 乱序写同一目标 |
| 粒度 | `(repo, name, sha)` | 状态记录 |
| 失效模式 | 锁过期 / 脑裂 | 版本比较逻辑写错 |
| 依赖 | Redis 等共享存储 | 无 |
| **建议** | **两者都做**：锁是性能优化 | 版本比较才是正确性保证 |

---

## 7. 崩溃恢复：状态不能卡死

### 7.1 崩溃点分析

把处理一个事件的完整链路拆开，逐点问"在这里 kill -9 会怎样"：

| # | 崩溃点 | 后果 | 恢复机制 | 现状 |
|---|---|---|---|---|
| 1 | 收到请求、还没 ACK | GitHub 判定投递失败（>10s）→ **会被人手动重投** | 重投 + L1 去重 | ✅ |
| 2 | ACK 之后、还没入队 | 事件永久丢失 | ★ 定时重扫 | ⚠️ 依赖重扫 |
| 3 | 入队后、还没开始处理 | 事件丢失（若是进程内队列，Pod 重启即丢）| ★ 外部队列 / 重扫 | ⚠️ 现状是进程内 chan |
| 4 | 处理中、还没写 `in_progress` | PR 上没有结论 → **挡住合并**（fail-closed）✅ | 重扫 | ✅ |
| 5 | 写了 `in_progress`、还没写终态 | **PR 永远卡住**（没人知道）| ★ 卡死检测 + 重扫 | ❌ **缺** |
| 6 | 写完终态、还没 ACK | 重投 → L1 挡住；或重投 → 重算（幂等）| L1 去重 | ✅ |
| 7 | 写完终态、还没记"已完成" | 重投 → 重新算一遍 → 幂等收敛 | L1 去重 + L2 收敛 | ✅ |

**第 5 点是当前实现最大的缺口。**

### 7.2 卡死检测与接管

```go
// 卡死阈值：超过这个时间还是 in_progress，就认为判定者挂了。
const StuckInProgressAfter = 10 * time.Minute

// 在定时重扫里顺带做：
func (s *Scheduler) DetectAndTakeOver(ctx context.Context) {
    // 方式 A（需要外部存储）：扫自己的状态表
    for _, v := range s.Store.ListInflight(ctx) {
        if time.Since(v.StartedAt) > StuckInProgressAfter {
            s.Logger.Warn("★ 检测到卡死的 in_progress，准备接管",
                "repo", v.Repo, "sha", v.SHA, "since", v.StartedAt)
            s.Eval(ctx, v.PR)   // 重算并写终态
        }
    }

    // 方式 B（无外部存储）：查 GitHub 上处于 in_progress 的 run
    //   GET /repos/{o}/{r}/check-runs?status=in_progress&check_name=<name>
    //   —— 但要逐仓库查，API 调用量大；只在"有用户报障"时手动用。
}
```

### 7.3 定时重扫是**必需品**，不是可选项

理由（回到 §2.3）：**required status check 是"按 head SHA 查已存在的结论"**，
GitHub **不会在 merge 时刻重新执行你的规则**。

```
10:00  CR 有效 + 在维护窗口内 → 判定 success ✅（绿 check 写进 GitHub）
10:05  维护窗口关闭
10:30  有人点 Merge
       GitHub 看到 head SHA 上有个绿 check → 放行 ❌❌❌
```

**只有重扫能救。** 而重扫同时还兜底了"事件丢失"（因为 GitHub 不自动重投）。

**重扫的三个前提**（缺一不可）：

| 前提 | 为什么 | 现状 |
|---|---|---|
| ① 知道要扫哪些 PR | 没有名单就无从扫起 | ⚠️ **现状是进程内 `Registry` → Pod 重启就丢** |
| ② 能拉到 PR 当前状态 | 判定必须基于快照 | ⚠️ 现状无 PR 重拉 |
| ③ 重扫有配额预算 | 5000 次/小时（见 §10）| 需设计 |

**①②的修法**：**不要依赖进程内内存**。启动时从 GitHub **重建**名单：

```go
// 启动时（和定时）从 GitHub 反查受管分支上的 open PR，重建 registry。
func (s *Scheduler) RebuildRegistry(ctx context.Context) error {
    for _, branch := range s.Cfg.ManagedBranches {
        prs, _, err := s.GH.ListPullRequests(ctx, s.Owner, s.Repo, &gogithub.ListOptions{
            State: "open", Base: branch, PerPage: 100,
        })
        if err != nil { return err }
        for _, pr := range prs {
            s.Registry.Add(rules.PRInfoFrom(pr))   // ★ 从 GitHub 重建，不靠内存
        }
    }
    return nil
}
```

> ★ **这是"重启后仍能自愈"的关键**：
> 有了它，Pod 重启 → registry 空 → 重建 → 所有受管 PR 重新进入重扫范围。
> **没有它，重启 = 定时重扫静默失效**，而你不会收到任何告警。

---

## 8. 策略变更的原子性

### 8.1 问题

```
12:00  policy v1：维护窗口 22:00-02:00
       PR #42 判定 success ✅
14:00  你把 policy 改成 v2：维护窗口 21:00-03:00
       ★ PR #42 的 SHA 没变，L2 键没变 → 系统认为"已判过" → 结论不更新
       ★ 而且 v2 下这个 PR 本来还是 success（窗口更宽）→ 这次侥幸没事
       ★ 但如果 v2 是"收紧"（比如新增"必须 2 个审批人"），结论就应该是 failure —— 却还是旧的 success
```

### 8.2 解法：结论带版本，重扫时比对

```go
type Verdict struct {
    Repo, PRNumber, HeadSHA, CheckName string
    PolicyVersion string     // ★
    Conclusion    string
    EvaluatedAt   time.Time
}

// 重扫时：只有"策略版本变了"或"SHA 变了"才重算
func (s *Scheduler) NeedReeval(v Verdict, curPolicyVersion string) bool {
    return v.PolicyVersion != curPolicyVersion || v.HeadSHA != s.CurrentHeadSHA(v)
}
```

### 8.3 策略怎么读？—— 要带版本/ETag

如果策略来自 GitHub 仓库里的配置文件（很常见）：

```go
// 读配置时记下 blob SHA（= 策略版本）
file, _, _, err := gh.Repositories.GetContents(ctx, owner, repo, path, nil)
// file.GetSHA() 是 Git blob 的 SHA —— 它就是天然的 policy_version
policyVersion := file.GetSHA()
```

如果策略来自 ConfigMap：

```go
// 用 resourceVersion（K8s 会单调递增）
policyVersion := cm.ResourceVersion
```

**好处**：
- 策略版本是**免费的、单调的、精确的**；
- 写进 check run 的 `output.summary` 里，**运维在 GitHub UI 上就能看到"这个结论是基于哪个版本的策略"**；
- 结论和策略版本一一对应 ⇒ 审计链路完整。

### 8.4 策略中途变更怎么办

判定过程可能长达几秒（要查 CR 平台）。期间策略可能变了。

```
t0  读 policy v1
t1  查 CR 平台（耗时 3s）
t2  ★ 这期间 policy 变成 v2
t3  算出结论（基于 v1）
t4  写 check run，标 policy_version=v1
```

**两种处理**：

| 策略 | 说明 |
|---|---|
| **乐观**：写 v1 的结论，但下轮重扫发现版本落后 → 重算 | 简单；结论最终会收敛 |
| **悲观**：写之前重新读一次 policy 版本，不一致就丢弃本次结果重算 | 更严格；多一次读 |

**推荐乐观**——因为有重扫兜底，且重扫周期通常是分钟级。

---

## 9. 副作用的原子性：Outbox 模式

### 9.1 问题

假设你的 App 不只写 check run，还要：
- 在 PR 上留 comment（说明为什么失败）
- 打/去 label（`cr/invalid`）
- 通知 Slack / 飞书

**GitHub 没有多资源事务**。你可能出现：

```
check run = failure ✅   已写入
comment   = 没发出去 ❌  （API 报错 / 进程崩溃）
```

→ 开发者看到"红色失败但没有说明"，体验极差；反过来（comment 发了但 check 没写）
更糟：看起来有解释，但**门禁没拦住**。

### 9.2 Outbox 模式

```
① 在一个数据库事务里：
     INSERT INTO outbox (id, kind, payload, created_at) VALUES (...)

② 事务提交后：
     - 写 check run（幂等，靠 external_id）
     - 写 comment（幂等：先查再发，或用 marker）
     - 打 label（幂等：先查现有 label）

③ Outbox relay 定期扫描未完成的 outbox 行 → 重试发送
   → 发送成功后标记 done
```

**为什么这是"原子"的**：不是让 GitHub 的副作用原子，
而是让**"我打算做什么"这件事**原子（一次事务写入），
然后**最终一致地**把它做出来（relay 可重试）。

**关键点：**
- outbox 行的**唯一键** = 业务键，保证同一目标只入队一次
- relay 必须**幂等**（重发 comment 不能出现两条）
- relay 必须有**退避 + 死信**

### 9.3 comment 的幂等（容易漏）

GitHub 的 comment API **没有幂等键**。重复发会出现两条一样的评论。

```go
// 发之前先查有没有同 marker 的评论
const MarkerPrefix = "<!-- cr-check:"

func (w *GitHubWriter) EnsureComment(ctx context.Context, ref Ref, marker, body string) error {
    // ① 查现有评论
    comments, _, err := w.cl.Issues.ListComments(ctx, ref.Owner, ref.Repo, ref.PRNumber, nil)
    if err != nil { return err }
    for _, c := range comments {
        if strings.Contains(c.GetBody(), marker) {
            return nil    // 已经有了 → 幂等返回
        }
    }
    // ② 没有才发
    _, _, err = w.cl.Issues.CreateComment(ctx, ref.Owner, ref.Repo, ref.PRNumber, &gogithub.IssueComment{
        Body: gogithub.String(marker + body),
    })
    return err
}
```

> 更省事的做法：**用 label 而不是 comment** 表达状态（label 是集合，天然幂等）。
> 或者把详细说明只放在 check run 的 `output.summary` 里（`PATCH` 是原子的，天然幂等），
> **comment 只在必要的人类可读场景用**。

---

## 10. 配额、背压与降级

### 10.1 官方限额（实测核对）

| 主体 | 限额 |
|---|---|
| **installation access token** | **基础 5,000 次/小时**；装在 GHEC 上是 15,000/小时 |
| installation 规模加成 | 仓库 >20 个：每个 +50/小时；组织用户 >20 个：每个 +50/小时；**上限 12,500/小时** |
| 并发（二次限流）| 有独立约束，需退避 |

> ⚠️ **"读取 PR 当前快照"会显著吃配额**：
> 每次事件多一次 `GET /pulls/{n}`，每次重扫多 N 次。
> 5000/小时的 installation，如果管 50 个仓库 × 每仓 20 个 open PR，
> **一次全量重扫就吃掉 1000 次**，一小时最多重扫 5 轮。**必须做预算。**

### 10.2 预算化重扫

```go
type ScanBudget struct {
    Limit      int           // 本轮最多多少次 API 调用
    Used       int
    PerRepoCap int
}

func (s *Scheduler) RunOnce(ctx context.Context, budget ScanBudget) {
    for _, e := range s.Registry.List() {
        if budget.Used >= budget.Limit {
            s.Logger.Warn("重扫预算用尽，本轮提前结束", "scanned", budget.Used)
            return   // ★ 剩余的下一轮再扫（轮转，不要每次都从第一个开始）
        }
        ...
    }
}
```

**轮转扫描**（避免每次都从列表头开始，饿死尾部）：

```go
// 用一个游标持久化，重扫从游标继续
start := s.Cursor.Load()
prs := s.Registry.List()[start:]
s.Cursor.Store((start + len(prs)) % len(s.Registry.List()))
```

### 10.3 降级策略

| 情况 | 降级动作 |
|---|---|
| 配额耗尽 / 命中二次限流 | 退避（指数 + 抖动），**不要忙等** |
| CR 平台挂了 | 写 `action_required`（**不是** success），并告警 |
| GitHub API 5xx | 重试 3 次（指数退避），仍失败 → 进死信 + 告警 |
| 判定超时 | 写 `action_required` + 告警（**不要留在 in_progress**） |

> ★ **一条铁律**：
> **任何情况下，都不能因为"系统自己的问题"而让 check 变成"通过"。**
> 判定失败 → `action_required` / `failure` / `timed_out`，**永远不要 success**。
> 这就是 fail-closed 在代码里的落法。

---

## 11. ★ 怎么证明你的实现真的是幂等的

"我觉得它幂等"没有意义。**必须用测试证明。**

### 11.1 测试矩阵

| # | 场景 | 注入方式 | 期望 |
|---|---|---|---|
| T1 | **同一 delivery 投递 N 次** | 重放同一 payload + 同一 `X-GitHub-Delivery` N 次 | 只处理 1 次；PR 上只有 1 个 check run；副作用只有 1 份 |
| T2 | **同一事件、不同 delivery GUID** | 手工构造两个不同 GUID 的相同 payload | 处理 2 次，但**最终状态相同**（幂等收敛）；仍然只有 1 个 check run |
| T3 | **乱序投递** | 先投 `labeled`，后投 `synchronize`（反序）| 结论基于**当前快照**，与顺序无关 |
| T4 | **并发投递** | 50 个 goroutine 同时投同一个 PR 的不同事件 | 只有 1 个 check run；conclusion 唯一 |
| T5 | **崩溃注入** | 在"写 in_progress 后"、"写终态前" kill -9 | 重启后重扫能补上终态；PR 最终能合 |
| T6 | **策略变更** | 判定中途改 policy | 结论带 policy_version；下轮重扫会重算 |
| T7 | **配额耗尽** | mock API 返回 403 rate limit | 退避重试；**绝不写成 success** |
| T8 | **CR 平台报错** | mock 返回 500 | 写 `action_required`；**不是** success；**不是**卡在 in_progress |
| T9 | **App 被卸载后重装** | 换 installation_id | 老结论不串味；新 installation 正常工作 |
| T10 | **同名伪造 check** | 手工创建一个同名但 external_id 不同的 run | 我们的写入不覆盖它；或明确只信自己的（见 §5.3 修法 1）|

### 11.2 T1 的可执行样例（用仓库现有代码）

仓库里已经有 `git-apps/cr-check/internal/webhook/handler_test.go` 和 `scripts/send-test-event.sh`，可以直接扩：

```go
// 幂等性测试：同一个 delivery 投 3 次，只应处理 1 次。
func TestHandler_IdempotentOnSameDelivery(t *testing.T) {
    h, lw := newTestHandler(t)
    body := payload("1234", "release/prd")

    for i := 0; i < 3; i++ {
        code, _ := post(h, body, "same-delivery-guid")
        if code != http.StatusOK {
            t.Fatalf("第 %d 次投递返回 %d", i, code)
        }
    }

    // 断言：只产生 1 次"完成"写入（而不是 3 次）
    var completed int
    for _, r := range lw.All() {
        if r.Status == "completed" {
            completed++
        }
    }
    if completed != 1 {
        t.Fatalf("期望 1 次完成写入，实际 %d 次", completed)
    }
}
```

> ⚠️ **注意**：这个测试之所以能通过，是因为 `MemoryStore` 是进程内的。
> 生产用 Redis 时，**必须多副本测试**（两个 Pod 同时接同一个 delivery）。

### 11.3 混沌测试（在预发环境）

```bash
# 1) 重放：把同一个 delivery 打 5 次
for i in $(seq 5); do
  curl -sS -X POST http://cr-check/github/webhook \
    -H 'X-GitHub-Event: pull_request' \
    -H 'X-GitHub-Delivery: fixed-guid-001' \
    -H 'X-Hub-Signature-256: sha256=...' \
    --data-binary @payload.json
done

# 2) 崩溃注入：判定进行中杀掉 Pod
kubectl delete pod -l app=cr-check --grace-period=0 --force   # SIGKILL

# 3) 观察：PR 上有几个同名 check run？结论是 success 还是别的？
gh api repos/<ORG>/<REPO>/commits/<SHA>/check-runs \
  --jq '.check_runs[] | {name, external_id, conclusion, started_at, completed_at}'
```

**观测指标（建议做成 dashboard）**：

| 指标 | 含义 | 告警阈值 |
|---|---|---|
| `check_runs_per_sha` | 同一 SHA 同名 run 的个数 | **> 1 就告警**（说明竞态发生了）|
| `stuck_in_progress_count` | 卡在 in_progress 超过 10 分钟的 run 数 | > 0 告警 |
| `verdict_flip_count` | 重扫时结论发生翻转的次数 | 持续增长 = 事件丢失率上升 |
| `duplicate_suppressed_total` | 被 L1 去重挡掉的重复投递数 | 突增 = GitHub 在重投（你的服务可能超时了）|
| `redelivery_gap_seconds` | 事件发生到结论写入的延迟 | P99 > 60s 告警 |

---

## 12. 对现有 `cr-check` 实现的差距分析

> 基于 `git-apps/cr-check/` 当前代码（2026-11-09）。**不是否定，是"补齐清单"。**

| # | 现状 | 问题 | 建议 | 优先级 |
|---|---|---|---|---|
| 1 | `handler.go:122` `Seen` + `handler.go:136` `Remember` **两次调用** | ★ **非原子**：并发重复处理 | 改成一次 `SET NX`（§3.4）| 🔴 高 |
| 2 | `check/writer.go` `upsert()` **先 list 后 create** | ★ **TOCTOU 竞态**，可能产生两个同名 run | 加 `external_id` + 锁（§5.3）| 🔴 高 |
| 3 | `external_id` **完全没用** | 无法反查"这个 run 是不是我写的"；无法区分伪造的同名 run | 写入 `external_id = H(repo, name, sha)`（§5.3 修法 1）| 🔴 高 |
| 4 | 判定**完全基于事件 payload**（`handler.go` 无 PR 重拉） | ★ **与本仓库自己的设计原则冲突**（`13-cr-check-go-design.md` §0 明确写"判定必须基于当前 PR 快照"）| 判定前 `GET /pulls/{n}`（§6.1）| 🔴 高 |
| 5 | `recheck.Registry` 是**进程内内存** | ★ **Pod 重启后重扫静默失效**（且无告警）| 启动时从 GitHub 重建名单（§7.3）| 🔴 高 |
| 6 | `MarkInProgress` 与 `Complete` 之间崩溃 → **卡在 in_progress** | PR 永久卡住，无人察觉 | 卡死检测 + 接管（§7.2）| 🟠 中 |
| 7 | 判定异常时**没有落终态**的路径 | 可能停在 in_progress | 写 `action_required`（§4.2）| 🟠 中 |
| 8 | `queue.Queue` 是**进程内 chan** | Pod 重启在途任务丢失 | 换 Redis Streams / PubSub / Cloud Tasks | 🟠 中 |
| 9 | 无 **policy_version** | 策略收紧后旧结论不会重算 | 结论带版本 + 重扫比对（§8）| 🟠 中 |
| 10 | 无 **Outbox** | check run / comment / label 可能不一致 | 需要多副作用时再上（§9）| 🟡 低 |
| 11 | `ListCheckRunsForRef` **未带 `check_name` 过滤** | 拉回该 SHA 上所有 run 再内存过滤 | 显式传 `check_name` | 🟡 低 |
| 12 | 无幂等性测试 | 上面 10 条的 bug 全部靠运气躲过 | 按 §11.1 补 T1–T10 | 🟠 中 |

**已经做对的（保留）**：

| 现状 | 为什么对 |
|---|---|
| ✅ `MarkInProgress` → `Complete` 两段式 | in_progress 不算通过 ⇒ fail-closed（§4.1）|
| ✅ `upsert()` 方向是"同名覆盖"而不是"每次新建" | 避免新旧结论并存 |
| ✅ `recheck` 定时重扫组件存在 | 这是**唯一**能救"GitHub 不重投"和"结论过期"的机制（§7.3）|
| ✅ `recheck` 的 `Flipped` 计数 | 正好是"事件丢失率"的探针（§11.3）|
| ✅ 去重存储接口抽象成 `Store`，并注明多副本要用 Redis | 方向对（但实现要改成原子操作，见 #1）|

---

## 13. 反模式

| ❌ 反模式 | 为什么错 | ✅ 正确做法 |
|---|---|---|
| 先 `Seen` 再 `Remember` | 两次调用，中间有竞态窗口 | 一次原子 `SET NX` |
| 每次都 `POST /check-runs` 新建 | 同名多 run，GitHub 取"最新"，结论随机 | 同名 upsert + `external_id` + 锁 |
| 用事件 payload 做判定 | 事件乱序/陈旧，payload 不是真相 | 重新拉 PR 当前快照 |
| 只按 `X-GitHub-Delivery` 去重 | 挡不住"不同事件同一目标" | L1 + L2 双层 |
| 判定失败就返回 500 | check 停在 in_progress，PR 永久卡住 | 落终态 `action_required` |
| 判定失败时写 `success` | **把系统故障变成放行** | 永远 fail-closed |
| 依赖 GitHub 重投 | **GitHub 不自动重投** | 定时重扫 + 失败投递巡检 |
| 以为 required status check 会"每次 merge 都重跑" | 它只看 head SHA 上**已有的**结论 | 定时重扫刷新结论 |
| 策略改了不重算 | 旧结论继续放行 | policy_version + 重扫比对 |
| 只在内存里保存受管 PR 名单 | Pod 重启 → 重扫静默失效 | 启动时从 GitHub 重建 |
| 只在单副本测试幂等 | 分布式下才暴露 | 多副本并发测试 |
| comment 直接发，不查重 | 重投 → 两条一样的评论 | 先查 marker，或用 label |
| 把"锁"当正确性保证 | 锁会过期、会脑裂 | 锁 + `external_id` + 内容收敛（双保险）|
| 把 in_progress 当"通过" | 它其实是"未判定" | 只有 `success`/`skipped`/`neutral` 算通过 |

---

## 14. 一页速查清单

**幂等键**
```
□ L1 = X-GitHub-Delivery，用原子 SET NX 占位（不是 Seen+Remember 两次调用）
□ L2 = (repo_id, check_name, head_sha) 写进 external_id
□ L3 = policy_version（blob SHA / resourceVersion）写进 output.summary
□ 崩溃后不永久占坑：短 TTL 占位 + 长 TTL 完成标记
```

**判定**
```
□ 判定输入 = 当前 PR 快照（重新 GET pulls/{n}），不是事件 payload
□ 只对会影响判定的 action 重拉，省配额
□ 判定失败 → 写 action_required（不是 success，不是留在 in_progress）
□ 共享状态写入做单调性检查（head_sha / policy_version）
```

**写入**
```
□ 先 in_progress 再 completed（fail-closed）
□ 同名 upsert；并发下用 external_id + 锁双保险
□ ListCheckRunsForRef 显式带 check_name
□ 副作用（comment/label）先查重；优先用 label / check output
```

**恢复**
```
□ 定时重扫是必需品（GitHub 不重投 + 结论会过期）
□ 受管 PR 名单从 GitHub 重建，不依赖进程内存
□ 卡死 in_progress 检测 + 接管
□ 重扫有配额预算 + 轮转游标（不饿死尾部）
□ 失败投递巡检（可选：GitHub App webhook deliveries API + App JWT）
```

**验证**
```
□ T1 同 delivery 重放 → 只处理 1 次
□ T3 乱序 → 结论与顺序无关
□ T4 并发 → 只有 1 个 check run
□ T5 崩溃注入 → 重扫能补终态
□ T7 配额耗尽 → 退避，绝不写 success
□ 指标：check_runs_per_sha / stuck_in_progress / verdict_flip / duplicate_suppressed
```

---

## 15. 官方文档 + 本仓库文档

### 官方文档

| 主题 | 链接 |
|---|---|
| **Webhook 最佳实践（含 X-GitHub-Delivery 防重放）** | https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks |
| **处理 webhook 投递失败（"GitHub 不自动重投"）** | https://docs.github.com/en/webhooks/using-webhooks/handling-failed-webhook-deliveries |
| **自动重投失败投递（App JWT 脚本范式）** | https://docs.github.com/en/webhooks/using-webhooks/automatically-redelivering-failed-deliveries-for-a-github-app-webhook |
| **重新投递 webhook（只能重投过去 3 天）** | https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/redelivering-webhooks |
| **Webhook 事件与 payload（check_run 的 action 列表）** | https://docs.github.com/en/webhooks/webhook-events-and-payloads |
| **REST API · Check runs（external_id / conclusion 枚举）** | https://docs.github.com/en/rest/checks/runs |
| **REST API · Check suites（幂等 get-or-create）** | https://docs.github.com/en/rest/checks/suites |
| **以 installation 身份认证（换 token，1 小时过期）** | https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation |
| **保护分支 / 必需状态检查（expected source）** | https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches |
| **REST API 速率限制（installation 5000/h 与规模加成）** | https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api |
| REST API · Apps / Installations | https://docs.github.com/en/rest/apps/apps · https://docs.github.com/en/rest/apps/installations |

### 本仓库文档

| 文档 | 用途 |
|---|---|
| [`git-apps/12-webhook-push-vs-pull.md`](./git-apps/12-webhook-push-vs-pull.md) | **★ 六个投递契约**（幂等/顺序/超时/重试/暴露面/配额）—— 本文的事实底座 |
| [`git-apps/13-cr-check-go-design.md`](./git-apps/13-cr-check-go-design.md) | CR Check 设计（幂等存储、端点契约、风险表）|
| [`git-apps/webhook-and-backend-service.md`](./git-apps/webhook-and-backend-service.md) | 安装 → Webhook → 后端的完整链路 |
| [`git-apps/14-rulesets-and-gitapp-gate.md`](./git-apps/14-rulesets-and-gitapp-gate.md) | 门禁侧：check 怎么变成"必须通过" |
| [`git-apps/16-ruleset-install-runbook.md`](./git-apps/16-ruleset-install-runbook.md) | 门禁配完之后怎么验证真的拦得住 |
| [`git-apps/cr-check/`](./git-apps/cr-check/) | **★ 可运行的 Go 实现**（本文 §12 的差距分析对象）|
| [`how-to-using-git-apps.md`](./how-to-using-git-apps.md) | 装好 App 之后仓库侧要做什么 |
| [`install-git-apps.md`](./install-git-apps.md) | Org 级 vs 仓库级 vs 分支 |
