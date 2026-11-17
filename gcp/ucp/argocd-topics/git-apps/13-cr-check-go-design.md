# 13 · CR Check（Go）的设计与实现评估

> 📌 **本文已有可运行实现** → [`cr-check/`](./cr-check/)
> 30 秒跑起来：`cd cr-check && make run`，然后 `./scripts/send-test-event.sh`。
> 本文是**设计与评估**，代码是**落地**，两者规则 ID（R1–R7 / R6w）一一对应。

> **本文回答三个问题**
> 1. **我们要做的这个东西，边界在哪里？**（做哪些、不做哪些）
> 2. **Go 代码怎么组织？**（包结构、接口、数据模型、端点契约）
> 3. **要花多少功夫？风险在哪？**（工作量、里程碑、风险表）

> **需求回顾（一句话版）**
> 部署到 **PRD 环境**的每一个 PR，必须携带一个**变更单（CR）编号**；
> 该 CR 必须在**内部 CR 管理平台**上处于**可执行的 Implement（已审核通过）状态**；
> 且合并/部署必须落在**Maintenance Window（维护窗口）**内。
> 不满足 → **PR 合不了**。

> **前置阅读**
> [`Develop-git-apps.md`](./Develop-git-apps.md)（可行性评估、规则表 R1–R13a、时间窗口难点）、
> [`webhook-and-backend-service.md`](./webhook-and-backend-service.md)（服务怎么跑起来）、
> [`12-webhook-push-vs-pull.md`](./12-webhook-push-vs-pull.md)（push 模型的契约）

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-tldr) | TL;DR：8 条结论 |
| [§1](#1-需求边界做什么与不做什么) | 需求边界（做/不做） |
| [§2](#2-总体架构) | 架构图 + 一次 PR 的完整时序 |
| [§3](#3-go-项目结构) | 目录结构与每个包的职责 |
| [§4](#4-核心接口设计) | Go 接口定义（可直接抄） |
| [§5](#5-数据模型) | 内部规范化模型 + CR 平台状态机映射 |
| [§6](#6-规则引擎设计) | 收集式 vs 快速失败、规则接口、可扩展性 |
| [§7](#7-http-端点契约) | 端点、状态码、幂等、超时预算 |
| [§8](#8-配置模型) | `policy.yaml` 完整示例（含 PRD / Maintenance Window） |
| [§9](#9-部署形态) | GKE 清单要点 + HA |
| [§10](#10-依赖选型) | Go 依赖与版本策略 |
| [§11](#11-测试策略) | 单测 / 契约测试 / 端到端 / 绕过测试 |
| [§12](#12-可观测性) | 指标、日志、审计三条线 |
| [§13](#13-安全) | 凭据、验签、暴露面、轮换 |
| [§14](#14-里程碑与工作量) | M0–M5 里程碑与工作量估算 |
| [§15](#15-风险清单) | 风险表 |
| [§16](#16-结论与建议) | 结论 |
| [§17](#17-关联文档) | 关联文档 |

---

## 0. TL;DR

1. **要做的是一个"有状态的服务"，不是一个"webhook 转发器"。** 它的核心资产是
   **「PR 当前状态 → 是否合规」这个判定函数**，以及围绕它的可靠性工程。
2. **不要自己造 GitHub 协议层。** 验签、token 换取、Check Run 写入都有成熟库
   （`ghinstallation` + `go-github`）。**你要写的是业务规则。**
3. **规则引擎用「收集式」（collect-all）而不是「快速失败」。** 因为需求要求
   *"check 详情里写明哪条规则不通过、缺什么"* —— 快速失败只能告诉用户第一条问题。
4. **判定必须基于「当前 PR 快照」，不是「事件 payload」。** 事件会乱序、会重复。
5. **判定必须异步。** 先 ACK 再入队；同步查 CR 平台极易超过 GitHub 的 10 秒预算。
6. **时间窗口必须有第二个触发源。** Webhook 管不了"时间过去了"。
   → **定时重扫重评**（必做）+ **CR 平台回调**（有则更好）+ **Merge Queue**（成熟期）。
7. **必须自建"事件兜底"。** GitHub 不会自动重投失败的 webhook 投递
   （见 [`12-webhook-push-vs-pull.md`](./12-webhook-push-vs-pull.md) §6.4）。
   **定时重扫是必做项，不是可选项。**
8. **写 check 只能写 `success` / `failure` / `action_required`。**
   `neutral` / `skipped` **被 GitHub 当作通过** → 等于开门。

---

## 1. 需求边界：做什么与不做什么

### 1.1 环境口径先定死

> 需求里出现了 **PRD**。请注意它和 **prod** 是两个不同的环境，
> 这直接决定"哪些分支受管控"和"CR 平台的目标环境值"。

| 环境 | 含义 | 是否受 CR Check 管控 | 典型分支 | CR 平台 `targetEnv` 取值 |
|---|---|---|---|---|
| `dev` | 开发自测 | ❌ | `feature/*`、`develop` | `dev` |
| **`prd`** | **预发布 / 准生产** | ✅ **必须**（需求明确） | `release/prd`、`main`（若 main 直接对 PRD） | `prd` |
| `prod` | 生产 | ✅（建议同时启用） | `release/prod` | `prod` |

> ★ **必须和 CR 管理平台对齐 `targetEnv` 的取值字面量**
> （`prd` / `pre-prod` / `staging` / `PRE`？）。
> 这是 M0 阶段第一个要问清楚的问题（见 [`Develop-git-apps.md`](./Develop-git-apps.md) §13 的 Q1/Q3/Q21）。

### 1.2 做 / 不做

| | 做什么 | 说明 |
|---|---|---|
| ✅ **做** | 接收 `pull_request` 事件 | 唯一的入站通道 |
| ✅ **做** | 解析**唯一** CR 编号 | label / body marker / commit trailer（建议多写） |
| ✅ **做** | 查询 CR 管理平台 | 存在性、状态、审批、目标环境、有效期、artifact |
| ✅ **做** | 按规则集判定 | R1–R13a |
| ✅ **做** | 写 Check Run（同名覆盖） | `cr/prod-validation` |
| ✅ **做** | 定时重扫重评 | ★ 兜底 + 窗口过期检测 |
| ✅ **做** | 审计留痕 | 判定结论写回 CR 平台 / 日志 / 独立审计存储 |
| ✅ **做** | 写 PR 评论（可选） | 把失败原因贴在 PR 上，比只看 check 友好 |
| — | **不做** | **审批 CR** —— 审批是人的动作，App 只能校验 |
| — | **不做** | **执行部署** —— 部署是 Argo CD 的事 |
| — | **不做** | **存 CR 状态** —— CR 平台是真相源，我们只读 |
| — | **不做** | **自己造 GitHub App 框架** | 用现成库 |
| — | **不做** | **通用工作流引擎** | 规则是代码，不是 DAG |

### 1.3 MVP 范围（建议第一版只做这些）

```
✅ webhook 接收 + 验签 + 幂等
✅ 按 base 分支过滤（只管 prd / prod 分支）
✅ 解析唯一 CR 号（label + body 两种载体）
✅ 查 CR 平台：存在 / 状态 / 目标环境 / 有效期
✅ Maintenance Window 判定
✅ 写同名 check（success / failure），output 逐条列失败原因
✅ 定时重扫重评（兜底 + 窗口过期）
✅ 基础指标 + 告警
❌ （第二版）artifact 一致性校验
❌ （第二版）PR 评论
❌ （第二版）Merge Queue / merge_group
❌ （第三版）紧急通道 break-glass
```

> ★ **MVP 一定要包含"定时重扫"**。
> 没有它，"窗口过期仍能合并"就是一个**静默存在**的漏洞 —— 没有报错、没有告警。

---

## 2. 总体架构

### 2.1 组件图

```
                     ┌──────────────────────────────────────────┐
                     │        GitHub（公网）                     │
                     │  · 仓库 + PR + 分支保护                    │
                     │  · GitHub App "CR Check"（Installation）   │
                     └───────────────┬──────────────────────────┘
                                     │ ① 入站 webhook（HMAC 签名）
                                     ▼
        ┌────────────────────────────────────────────────────────┐
        │              CR Check 服务（Go，跑在 GKE）                │
        │                                                        │
        │  ┌────────────┐   ┌──────────────┐   ┌────────────┐  │
        │  │ webhook    │──▶│ 判定流水线    │──▶│ checks     │  │
        │  │ verify     │   │ rules        │   │ writer     │  │
        │  │ dedup      │   │ R1–R13a      │   │ (覆盖同名)  │  │
        │  │ dispatch   │   └──────┬───────┘   └─────┬──────┘  │
        │  └────────────┘          │                 │ ② 出站   │
        │                        ▼                 ▼         │
        │              ┌─────────────────┐   ┌──────────────┐  │
        │              │ cr-client       │   │ GitHub API   │  │
        │              │ (HTTP → 平台)    │   │ (checks)     │  │
        │              └─────────────────┘   └──────────────┘  │
        │                        ▲                             │
        │  ┌────────────┐       │        ┌──────────────┐     │
        │  │ 队列        │       │        │ recheck      │     │
        │  │ (Redis)    │◀──────┘        │ scheduler    │     │
        │  └────────────┘                │ (定时重扫)     │     │
        │                               └──────────────┘     │
        └────────────────────────────────────────────────────────┘
```

### 2.2 一次 PR 的完整时序

```
Dev  → GitHub : 提 PR，填 cr/1234
GitHub → CR Check : POST /github/webhook (pull_request.opened)
CR Check : 验签 ✓ → 去重 ✓ → 入队 ✓ → 200 ACK（~50ms）
CR Check worker : 读 PR 快照 → 查 CR 平台 → 跑规则
CR Check : POST check-runs { name: "cr/prod-validation", head_sha, conclusion }
GitHub : PR 上显示 ✓ / ✗ + 失败原因
Dev  → GitHub : 点 Merge
GitHub : 分支保护检查 required check（+ 来源 App）→ 通过 → 合并
```

### 2.3 部署形态（推荐）

```
GKE 集群
├── namespace: cr-check
│   ├── Deployment/cr-check        （replicas ≥ 2）
│   ├── Service/cr-check           （ClusterIP，port 80 → targetPort 8080）
│   ├── Ingress/cr-check           （host: cr-check.example.com, path: /github/webhook）
│   ├── ConfigMap/cr-check-policy  （规则数据：分支映射 / 窗口 / 阈值）
│   └── Secret/cr-check-secrets    （私钥 / webhook secret / CR 平台 token）
├── Redis（复用现有或新建）         ← 幂等去重 + 队列
└── Cloud NAT（或节点已有出网）      ← 访问 api.github.com 与 CR 平台
```

---

## 3. Go 项目结构

```
cr-check/
├── cmd/
│   └── server/
│       └── main.go              # 组装依赖、启动 HTTP、优雅退出
├── internal/
│   ├── config/
│   │   ├── config.go            # policy.yaml 加载 + 校验
│   │   └── config_test.go
│   ├── webhook/
│   │   ├── handler.go           # HTTP 入口：验签 → 去重 → 分发 → ACK
│   │   ├── signature.go         # HMAC-SHA256 验签
│   │   ├── events.go            # 事件类型 → 内部事件结构体
│   │   └── handler_test.go
│   ├── github/
│   │   ├── client.go            # installation client 工厂（带缓存）
│   │   ├── checks.go            # upsertCheck / markInProgress
│   │   ├── pulls.go             # 读 PR 快照、changed files
│   │   └── ratelimit.go         # 退避重试（应对 secondary rate limit）
│   ├── crplatform/              # ★ CR 管理平台客户端
│   │   ├── client.go            # HTTP 调用 + 超时 + 重试
│   │   ├── types.go             # 平台响应 → 内部规范化模型
│   │   └── client_test.go
│   ├── rules/
│   │   ├── engine.go            # 规则编排（collect-all）
│   │   ├── rule.go              # Rule 接口 + 结果类型
│   │   ├── extract.go           # 解析唯一 CR 号（label/body/trailer）
│   │   ├── window.go            # Maintenance Window 判定
│   │   ├── policy.go            # 分支→环境映射、状态白名单
│   │   └── *_test.go
│   ├── check/
│   │   └── writer.go            # 写 check 的统一入口（幂等覆盖 + 两阶段）
│   ├── recheck/
│   │   ├── scheduler.go         # 定时重扫
│   │   └── index.go             # 受管 PR 索引（从 GitHub 重建）
│   ├── audit/
│   │   └── sink.go              # 审计写回（CR 平台 / 日志）
│   ├── queue/
│   │   └── redis.go             # Redis Stream / List 队列
│   └── observability/
│       ├── metrics.go           # Prometheus 指标
│       └── logging.go           # 结构化日志字段
├── deploy/                      # K8s 清单（Argo CD 管理）
├── config/policy.yaml           # 规则数据（改这里不用发版）
├── Dockerfile
└── .github/workflows/ci.yml
```

> ★ **`internal/crplatform` 是"外部依赖适配层"**：
> 把 CR 平台的响应结构收敛成一个内部模型（`rules` 包只认内部模型）。
> 这样平台改字段时，只需要改一个包。

---

## 4. 核心接口设计

### 4.1 内部规范化模型（规则层唯一依赖的东西）

```go
// internal/crplatform/types.go

// ChangeRequest 是 CR 管理平台的规范化视图。
// 规则层只依赖这个结构，不依赖平台原始响应。
type ChangeRequest struct {
	Number    string        // "1234"
	Status    Status        // 规范化后的状态（见 5.2）
	Requester string        // 提单人（GitHub login 或平台账号）
	Approvers []Approval    // 已批准的审批记录
	TargetEnv string        // "prd" / "prod" / "dev"
	ValidFrom time.Time     // 生效时间（含）
	ValidTo   time.Time     // 失效时间（不含）
	Artifacts []string      // 预期改动的配置项 / artifact（可选，见 R5b）
	URL       string        // 平台页面链接（写进 check output 便于跳转）
}

type Approval struct {
	Approver  string
	DecidedAt time.Time
	Decision  string // "approve" / "reject"
}

// Status 是规范化后的状态枚举。
type Status string

const (
	StatusUnknown    Status = "unknown"
	StatusDraft      Status = "draft"
	StatusReviewing  Status = "reviewing"
	StatusApproved   Status = "approved"   // 审核通过
	StatusImplement  Status = "implement"   // ★ 需求说的"可执行的 implement 状态"
	StatusRejected   Status = "rejected"
	StatusCancelled  Status = "cancelled"
	StatusExpired    Status = "expired"
)

// IsExecutable 表示"允许作为部署依据"。
func (s Status) IsExecutable() bool {
	return s == StatusApproved || s == StatusImplement
}
```

### 4.2 CR 平台客户端

```go
// internal/crplatform/client.go

type Client interface {
	// Get 按编号查询变更单。
	// 返回 (nil, nil) 表示"平台确认不存在"（业务不通过）；
	// 返回 error 表示"查询失败"（系统异常，必须 fail-closed）。
	Get(ctx context.Context, number string) (*ChangeRequest, error)

	// RecordAudit 把判定结论写回平台（可失败时只记日志，不阻塞判定）。
	RecordAudit(ctx context.Context, rec AuditRecord) error
}

type HTTPClient struct {
	baseURL string
	token   string
	http    *http.Client // 带超时
}
```

> ★ **`(nil, nil)` vs `error` 的区分是整个设计的关键**：
> - `nil, nil` → CR 不存在 → **业务不通过** → check = `failure`，理由明确
> - `error` → 平台超时/5xx → **系统异常** → check = `failure`（**不得写 success/neutral**）+ 告警

### 4.3 规则引擎

```go
// internal/rules/rule.go

// Result 是一条规则的判定结果。
type Result struct {
	ID      string // "R3"
	Passed  bool
	Message string // 失败时给出可读的、可操作的说明
}

// Rule 是单条规则。规则之间无依赖，按顺序执行，**收集全部结果**。
type Rule interface {
	ID() string
	// Evaluate 返回该规则的判定结果。
	// ctxErr 表示"外部依赖异常"，与"规则不通过"语义不同。
	Evaluate(ctx context.Context, in Input) Result
}

// Input 是判定的全部输入。
type Input struct {
	PR       *github.PullRequest
	CR       *ChangeRequest   // 可能为 nil（CR 不存在）
	CRNumber string
	Now      time.Time
	Policy   *config.Policy
}
```

```go
// internal/rules/engine.go

// Engine 按顺序执行全部规则，收集所有结果。
func (e *Engine) Evaluate(ctx context.Context, in Input) (Outcome, error) {
	results := make([]Result, 0, len(e.rules))
	for _, r := range e.rules {
		results = append(results, r.Evaluate(ctx, in))
	}
	outcome := Outcome{Results: results}
	outcome.OK = allPassed(results)
	return outcome, nil
}

type Outcome struct {
	OK      bool
	Results []Result
	SystemError error // 非 nil 表示系统异常（fail-closed）
}

// Render 把结果渲染成 check output 的 Markdown。
func (o Outcome) Render() string { /* 逐条列出通过/失败的规则 */ }
```

> ★ **为什么是 collect-all 而不是 fail-fast**：
> 需求 R10 明确要求"check 详情里写明**哪条规则**不通过、缺什么"。
> fail-fast 只能告诉用户第一条问题 → 用户改完再提交 → 又撞上第二条 → 体验极差。
> **一次把问题全列出来**，是这个门禁好不好用的分水岭。

### 4.4 Check 写入器

```go
// internal/check/writer.go

type Writer interface {
	// MarkInProgress 把 check 置为"评估中"。
	// 作用：① 同 SHA 重评时旧 success 不会冒充新结论；
	//       ② in_progress 不算通过 → 评估期间合并被正确阻断。
	MarkInProgress(ctx context.Context, owner, repo, sha string) error

	// Complete 写终态结论（覆盖同名 check）。
	Complete(ctx context.Context, owner, repo, sha string, o rules.Outcome) error
}
```

> ⚠️ **写 check 的三条铁律**（写在代码注释里也要写）：
> 1. **同名覆盖**（先查同名 → Update，没有才 Create）。否则新旧结论并存，GitHub 可能取到旧的。
> 2. **绝不写 `neutral` / `skipped`** —— GitHub 把它们当作"通过"，等于开门。
> 3. **系统异常写 `failure` 或 `action_required`**，绝不写 `success`。

### 4.5 幂等存储与队列

```go
// internal/queue/redis.go

type Store interface {
	// Seen/Remember 做投递去重（幂等键 = X-GitHub-Delivery）。
	Seen(ctx context.Context, deliveryID string) (bool, error)
	Remember(ctx context.Context, deliveryID string, ttl time.Duration) error

	// Enqueue 投递判定任务。
	Enqueue(ctx context.Context, job Job) error
	// Dequeue 消费判定任务。
	Dequeue(ctx context.Context) (Job, error)
}
```

> ★ **多副本下用内存 Map 做去重是错的**：
> 副本 A 处理过的 delivery，副本 B 不知道 → 重复处理 → 重复写 check。
> **必须用 Redis（或 DB）**。

### 4.6 重扫调度器

```go
// internal/recheck/scheduler.go

// Scheduler 定期重扫受管分支上未合并的 PR，重新判定并覆盖 check。
// 作用：
//   ① 兜底 GitHub 不会自动重投的失败投递（事件丢失）
//   ② 解决"Maintenance Window 过期但旧 success 仍能合并"的漏洞
type Scheduler struct {
	interval time.Duration
	branches []string
	github   PullLister
	engine   *rules.Engine
	writer   check.Writer
}
```

---

## 5. 数据模型

### 5.1 CR 编号的解析（多载体）

```
优先级（建议）：
1. commit trailer   "Change-Request: 1234"   ← 部署侧也能读到，事后可追溯
2. PR label         "cr/1234"                ← 最机读，机器友好
3. PR body marker   "Change-Request: 1234"   ← 人友好，可固化在 PR 模板里
```

**规则 R1a：必须且只能解析出唯一一个 CR 号。**

```
0 个  → failure："PR 未携带变更单号（需要 label cr/<编号>、body 的 Change-Request: 字段，或 commit trailer）"
N 个  → failure："解析出多个变更单号 [1234, 5678]，一个 PR 必须且只能关联一个变更单"
```

> ★ **多载体必须做"一致性检查"**：
> 如果 label 写 `cr/1234` 而 trailer 写 `cr/5678` → 这是**冲突**，必须报错，不能"取优先级最高的那个"。
> 冲突通常意味着有人复制粘贴错了 PR 模板。

### 5.2 CR 平台状态 → 规范化状态的映射

> 平台的状态名各不相同，必须显式映射，**不要把平台字符串直接透传**。

| 平台状态（示例） | 规范化 | 可执行？ | 备注 |
|---|---|---|---|
| `Draft` / `草稿` | `draft` | ❌ | |
| `Reviewing` / `审批中` | `reviewing` | ❌ | |
| `Approved` / `已批准` | `approved` | ✅ | |
| **`Implement` / `实施中` / `可执行`** | **`implement`** | ✅ | ★ **需求指定的"可执行"状态** |
| `Rejected` / `已驳回` | `rejected` | ❌ | |
| `Cancelled` / `已取消` | `cancelled` | ❌ | |
| `Expired` / `已过期` | `expired` | ❌ | |
| 其他未知值 | `unknown` | ❌ | ⚠️ **未知状态必须 fail-closed**（不能当成可执行） |

```go
// internal/rules/policy.go

// AllowedStatuses 是"允许作为部署依据"的状态集合，来自配置。
// ★ 未在集合内的状态一律视为不合规（fail-closed）。
func (p *Policy) IsExecutableStatus(s crplatform.Status) bool {
	for _, allowed := range p.AllowedExecutableStatuses {
		if s == allowed {
			return true
		}
	}
	return false
}
```

> ★ **"未知状态 = 不通过"是安全默认**。
> 如果平台新增了一个状态而我们没更新映射 → fail-closed（挡住合并）；
> 反过来（默认放行）→ 门禁被悄悄打开。**永远选 fail-closed。**

---

## 6. 规则引擎设计

### 6.1 规则清单（对应 [`Develop-git-apps.md`](./Develop-git-apps.md) §1.2）

| ID | 规则 | 判定位置 | 失败信息示例 |
|---|---|---|---|
| **R0b** | base 分支必须命中受管集合（`release/prd`、`release/prod`…） | 过滤器 | 非目标分支直接忽略（**不产生 check**） |
| **R1** | PR 必须携带 CR 号 | `extract` | "PR 未携带变更单号" |
| **R1a** | 必须且只能有**一个** CR 号 | `extract` | "解析出多个变更单号 [...]" |
| **R2** | CR 在平台存在 | `crplatform` | "变更单 1234 不存在" |
| **R3** | CR 状态可执行（Approved / Implement） | `policy` | "变更单 1234 当前状态为 Draft，需要 Approved 或 Implement" |
| **R4** | 审批充分（≥ N 位、不含提单人、审批人在授权组） | `rules` | "变更单 1234 审批人 1 位，需要至少 2 位" |
| **R5** | 目标环境匹配（CR.targetEnv ↔ 分支映射） | `policy` | "变更单 1234 目标环境为 prod，但本 PR 目标分支对应 prd" |
| **R5b** | artifact 与实际改动一致 | `rules` | （MVP 可关） |
| **R6** | CR 有效期覆盖当前时刻 | `window` | "变更单 1234 已过期（有效期至 2025-01-02 12:00:00+08:00）" |
| **R7** | CR 未被其他 PR 占用 | `rules` | "变更单 1234 已被 PR #123 使用" |
| **R8** | 紧急通道（break-glass） | `rules` | 放行但强制留痕 |
| **R9** | 全部通过 → `success` | `engine` | — |
| **R10** | 输出逐条说明 | `engine.Render()` | — |
| **R11** | 审计留痕 | `audit` | — |
| **R12** | 部署侧可追溯 | commit trailer + 发布侧 | — |
| **R13** | 系统异常不得写成功 | `check.Writer` | "门禁系统异常，本次判定未完成" |
| **R13a** | 先置 in_progress 再写终态 | `check.Writer` | — |

### 6.2 Maintenance Window 判定

需求里有**两个不同的时间概念**，必须分清：

| 概念 | 来源 | 判定方式 | 规则 |
|---|---|---|---|
| **① CR 有效期** | CR 平台的 `validFrom` / `validTo` | `now ∈ [validFrom, validTo]` | R6 |
| **② Maintenance Window** | **平台侧的固定发布窗口**（如每周二 02:00–04:00） | 当前时刻落在窗口内 | R6w |

```
① CR 有效期：  "这张 CR 还能用吗"        → 来自 CR 平台
② 维护窗口：    "现在允许部署吗"          → 来自配置（policy.yaml）或 CR 平台
```

> ★ **①和②都要判**：
> 只判① → 在 CR 有效期内但半夜 3 点也能合（违反维护窗口）；
> 只判② → 窗口内但 CR 已过期也能合。
> **两个都要过。**

```go
// internal/rules/window.go

// MaintenanceWindow 表示一个按周重复的发布窗口。
type MaintenanceWindow struct {
	Env    string          // "prd"
	Days   []time.Weekday  // 周一~周五
	Start  string          // "02:00"（本地时间）
	End    string          // "04:00"
	TZ     string          // IANA 名，如 "Asia/Shanghai"
}

// Contains 判断 now 是否落在窗口内。
// ★ 必须处理"跨零点"的情况（start > end，如 22:00 → 02:00）。
func (w MaintenanceWindow) Contains(now time.Time) (bool, error) {
	loc, err := time.LoadLocation(w.TZ) // ★ IANA 名，不要硬编码 UTC 偏移
	if err != nil {
		return false, fmt.Errorf("时区配置错误 %q: %w", w.TZ, err)
	}
	n := now.In(loc)
	hh, mm := clockOf(n)
	if !containsDay(w.Days, n.Weekday()) {
		return false, nil
	}
	start, end := parseHM(w.Start), parseHM(w.End)
	switch {
	case start < end:
		return hh >= start && hh < end, nil
	default: // 跨零点
		return hh >= start || hh < end, nil
	}
}
```

> ⚠️ **时区必须用 IANA 名**（`Asia/Shanghai`），不能用 `time.FixedZone("CST", 8*3600)`。
> 后者会把 DST 规则写死 —— 现在看不出问题，换个时区或改了夏令时规则就会算错。

### 6.3 规则的扩展性

规则引擎要能被"不改代码就加一条规则"地扩展一部分：

```yaml
# policy.yaml —— 阈值与例外放配置，判定逻辑放代码
cr:
  allowedExecutableStatuses: [approved, implement]
  minApprovals: 2
  forbidSelfApproval: true
  approverGroups: ["sre-leads", "platform-oncall"]
  requireApproverGroups: true
  uniqueAcrossPRs: true
  emergencyLabel: "emergency/break-glass"
  emergencyRequiresAudit: true
windows:
  - env: prd
    days: [Mon, Tue, Wed, Thu, Fri]
    start: "02:00"
    end: "04:00"
    tz: Asia/Shanghai
```

> ★ **分界线**：
> **阈值 / 名单 / 映射表** → 配置（改配置走 PR + Argo CD sync，分钟级生效）；
> **判定逻辑本身**（怎么算"审批充分"）→ 代码（改代码要走 CI + 部署）。
> 把逻辑写死在 YAML 里 → 复杂规则没法表达；把阈值写死在代码里 → 改一个数要发版。**分开。**

---

## 7. HTTP 端点契约

| 端点 | 方法 | 用途 | 对外暴露 |
|---|---|---|---|
| `/github/webhook` | POST | GitHub 事件入口 | ✅ 公网 |
| `/healthz` | GET | 存活探针 | 内部（或公网但无敏感信息） |
| `/readyz` | GET | 就绪探针（**含"能拿到 installation token"**） | 内部 |
| `/metrics` | GET | Prometheus 指标 | 内部 |

### 7.1 `/github/webhook` 的处理顺序

```go
func (h *Handler) handleWebhook(w http.ResponseWriter, r *http.Request) {
	// ① 限流 + 请求体大小限制（防洪泛 / 内存打爆）
	// ② 验签：X-Hub-Signature-256（hmac.Equal）
	//    失败 → 401（GitHub 侧记为投递失败）
	// ③ 幂等：X-GitHub-Delivery 去重
	//    重复 → 200 直接返回
	// ④ 事件白名单：
	//    pull_request / pull_request_review / check_run / merge_group / installation
	//    其他 → 200 忽略
	// ⑤ 入队 → 立刻 200（★ 绝不在这里同步调外部系统）
}
```

**状态码约定**：

| 情况 | 返回 | GitHub 的解读 |
|---|---|---|
| 验签失败 | `401` | 投递失败（说明 secret 不一致 —— 这是配置错误，应该告警） |
| 事件类型不关心 | `200` | 投递成功 |
| 幂等命中 | `200` | 投递成功 |
| 入队成功 | `200` | 投递成功 |
| 入队失败（Redis 挂了） | `500` | 投递失败（GitHub **不会自动重投** → 需要我们自己的兜底） |

> ★ **"入队失败返回 500 但没有自动重试"** 是个陷阱：
> 这时事件就丢了 → **定时重扫是唯一兜底**。
> 所以队列和判定服务的可用性必须监控，且**队列不可用时应该告警**。

### 7.2 超时预算

| 环节 | 预算 |
|---|---|
| webhook handler 总耗时 | **< 2 秒**（只做验签 + 去重 + 入队） |
| 判定任务 | 60 秒（可调） |
| CR 平台调用 | 5 秒 |
| GitHub API 单次调用 | 10 秒 |

---

## 8. 配置模型

> ★ **原则：阈值 / 名单 / 映射表放配置（改配置走 PR + Argo CD sync，分钟级生效）；
> 判定逻辑本身放代码（改代码要走 CI + 部署）。**
> 把逻辑写死在 YAML 里 → 复杂规则没法表达；把阈值写死在代码里 → 改一个数要发版。**分开。**

### 8.1 完整示例

```yaml
# config/policy.yaml（挂 ConfigMap 进 Pod；改规则数据不用重新发版）

# ── 全局 ────────────────────────────────────────────────
timezone: Asia/Shanghai          # ★ IANA 名，不要硬编码 UTC 偏移
checkName: cr/prod-validation    # ★ 必须与分支保护里的 required check 名逐字符一致

# ── 环境与分支 ──────────────────────────────────────────
# ★ 环境口径：dev / prd / prod
#   prd = 预发布（需求明确："部署到 PRD 必须经过 CR Check"）
#   ⚠️ targetEnv 的字面量必须与 CR 管理平台对齐（prd? PRD? pre-prod? staging?）
managedBranches:                 # ★ 受管 basebranch 集合（R0b 过滤）
  - release/prd
  - release/prod
  # - main                    # 若 main 直接对 PRD，需加入
branchEnvMap:                    # base 分支 → 环境（R5 目标环境匹配）
  release/prd: prd
  release/prod: prod
  main: prd
  "": dev                        # 其余分支一律不管控

# ── 变更单（CR）规则 ───────────────────────────────────
cr:
  # ★ 可执行状态白名单（需求："状态已经是可执行的 implement 状态"）
  #   ⚠️ 白名单之外的状态一律 fail-closed（未知状态 = 不通过）
  allowedExecutableStatuses: [approved, implement]
  minApprovals: 2
  forbidSelfApproval: true
  approverGroups: ["sre-leads", "platform-oncall"]
  requireApproverGroups: true
  uniqueAcrossPRs: true          # R7：同一 CR 不能被两个 PR 同时占用
  # CR 号的三个载体（多写 + 冲突检测）
  labelPattern: "^cr/[0-9]+$"
  bodyMarker: "Change-Request:"
  trailerKey: "Change-Request"

# ── Maintenance Window（固定发布时段）────────────────────
# ★ 与 CR 平台返回的 validFrom/validTo 是**两个独立的时间条件**，两者都要判
windows:
  - env: prd
    days: [Mon, Tue, Wed, Thu, Fri]
    start: "02:00"
    end: "04:00"                  # ★ 开区间：[start, end)
    tz: Asia/Shanghai
  - env: prod
    days: [Mon, Tue, Wed, Thu, Fri]
    start: "02:00"
    end: "04:00"
    tz: Asia/Shanghai

# ── 紧急通道（break-glass）─────────────────────────────
emergency:
  label: "emergency/break-glass"
  requiresAudit: true            # ★ 放行但必须留痕 + 事后复查
```

### 8.2 配置里的四个易错点

| # | 易错点 | 后果 |
|---|---|---|
| 1 | 漏配 `managedBranches` | 受管分支的 PR 不出 check → **门禁缺口**（且不会有任何报错） |
| 2 | `branchEnvMap` 里的环境值与平台 `targetEnv` 字面量不一致 | R5 永远不通过（或永远通过） |
| 3 | `windows` 只配了一个环境 | PRD 有窗口、prod 没有 → prod 全天可合并 |
| 4 | `allowedExecutableStatuses` 漏了平台新增的状态 | 未知状态被当成不通过（**这是对的**，fail-closed）；<br>但反过来若代码里"默认放行"→ **门禁被悄悄打开** |

---

## 9. 部署形态

### 9.1 HA

```yaml
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0        # ★ 滚动更新期间不减少可用副本
      maxSurge: 1
```
```
+ PDB（minAvailable: 1）
+ readinessProbe 要检查"能拿到 installation token"（否则私钥/网络故障时 Pod 仍 Ready → 请求全失败）
+ HPA（CPU 或 RPS）
```

### 9.2 出网

```
CR Check 需要访问：
  · api.github.com      → 写 check run、读 PR 快照
  · <CR 平台地址>       → 查变更单
→ 节点需要出网（Cloud NAT 或节点已有公网 IP）
→ ★ 出站不通 = 门禁静默失效（见 12-webhook-push-vs-pull.md §7）
```

### 9.3 公网入口

```
GKE Ingress（或 Gateway）
  host: cr-check.example.com
  path: /github/webhook
  → Service cr-check:80 → Deployment containerPort 8080
TLS：Google 托管证书（Certificate Manager）或 cert-manager
     ★ 必须是被信任的证书链，自签不行
DNS：pr-gate.example.com → 静态 IP
```

---

## 10. 依赖选型

| 库 | 用途 | 备注 |
|---|---|---|
| `github.com/google/go-github/vXX` | REST API（PR、Checks） | ★ 官方维护 |
| `github.com/bradleyfalzon/ghinstallation/v2` | 私钥 → JWT → installation token（**自动续期**）+ 验签辅助 | ★ 别手写 JWT |
| `github.com/redis/go-redis/v9` | 幂等去重 + 队列 | 可换成 Cloud Tasks / Pub/Sub |
| `github.com/prometheus/client_golang` | 指标 | |
| `go.uber.org/zap` 或 `log/slog` | 结构化日志 | Go 1.21+ 可用 `slog` |
| `sigs.k8s.io/yaml` | 配置解析 | |
| `github.com/stretchr/testify` | 测试 | |

**版本策略**：
```
· Go 1.22+（用 slog，减少依赖）
· 依赖版本锁在 go.sum
· 定期（每月）govulncheck 扫漏洞
· 镜像 tag 用 commit SHA 或 vX.Y.Z，不用 latest
```

---

## 11. 测试策略

| 层级 | 测什么 | 怎么测 |
|---|---|---|
| **单测** | 规则函数、CR 号解析、窗口判定（含**跨零点**、DST、边界时刻） | 表驱动测试；`now` 作为参数注入，**不读系统时钟** |
| **契约测试** | 我们对 CR 平台的请求格式 / 对平台响应的解析 | 用 **httptest.Server** 录放真实响应样本；平台改了字段能立刻发现 |
| **GitHub 交互测试** | 验签、事件分发、check 覆盖 | 用 `ghinstallation` 的测试 transport 或 httptest mock GitHub API |
| **端到端** | 提 PR → 看到 check → 合不了 | 用一个 **测试 App + 测试仓库 + 假 CR 平台**，在 CI 里跑 |
| **绕过测试** ★ | 五条绕过路径（见下） | 定期演练 |

### 10.1 ★ 必测的边界用例

```
□ 恰好在窗口开始时刻（应通过）
□ 恰好在窗口结束时刻（应不通过，结束是开区间）
□ 跨零点的窗口（22:00 → 02:00），01:00 应通过，03:00 应不通过
□ DST 切换日（配置用 IANA 时区时尤其重要）
□ CR 有效期正好等于 now（边界）
□ 解析出 0 个 / 1 个 / 2 个 / 3 个 CR 号
□ label 与 trailer 冲突（必须报冲突，不能静默取优先级）
□ CR 平台返回 500 / 超时 → 必须 fail-closed（**绝不能写 success**）
□ CR 平台返回未知状态 → 必须 fail-closed
□ 平台返回 200 但 body 是空 / 非法 JSON → fail-closed
```

### 10.2 ★ 五条绕过路径（上线前必测）

```
① 绕过 PR 直接 push 生产分支        → 分支保护 / 令牌权限 是否挡住？
② 绕过 App，直接 kubectl apply      → 准入控制（Gatekeeper/VAP）是否挡住？
③ 绕过门禁，手动触发 Argo CD sync   → AppProject disableManualSync + Argo CD RBAC？
④ 拿一张别的环境的 CR 来合并        → R5 目标环境匹配 是否挡住？
⑤ 改 CR Check 自己的代码 / 配置     → CODEOWNERS + 双人复核 是否挡住？
```

---

## 12. 可观测性

### 11.1 指标（Prometheus）

| 指标 | 类型 | 用途 |
|---|---|---|
| `cr_check_webhook_received_total{event,action}` | counter | 入站量 |
| `cr_check_webhook_rejected_total{reason}` | counter | 验签失败 / 限流 |
| `cr_check_jobs_total{result}` | counter | 判定任务数（success/failure/system_error） |
| `cr_check_rule_failed_total{rule_id}` | counter | ★ **哪条规则最常拦人**（→ 优化体验的抓手） |
| `cr_check_evaluation_duration_seconds` | histogram | 判定耗时 |
| `cr_check_crplatform_requests_total{result}` | counter | CR 平台调用 |
| `cr_check_crplatform_errors_total` | counter | CR 平台错误率 |
| `cr_check_github_api_errors_total{code}` | counter | GitHub API 错误（含 403/429 限流） |
| `cr_check_checks_written_total` | counter | check 写回数 |
| `cr_check_recheck_scanned` / `cr_check_recheck_flipped` | counter | ★ 重扫发现了几条"结论翻转"（= 事件丢失的量度） |
| `cr_check_queue_depth` | gauge | 队列积压 |
| `cr_check_github_rate_limit_remaining` | gauge | GitHub 配额余量 |

> ★ **`cr_check_recheck_flipped` 是最有价值的一个指标**：
> 它直接度量"**有多少 PR 的结论是重扫才发现的**"= 事件丢失率。
> 这个数字如果长期 > 0，说明 webhook 链路有漏洞。

### 11.2 日志（结构化）

```json
{
  "ts": "2025-01-02T03:14:15Z",
  "level": "info",
  "msg": "evaluation complete",
  "delivery_id": "72d3162e-...",
  "repo": "acme/platform",
  "pr": 42,
  "head_sha": "abc123...",
  "base_ref": "release/prd",
  "env": "prd",
  "cr_number": "1234",
  "outcome": "failure",
  "failed_rules": ["R3", "R6w"],
  "duration_ms": 412
}
```

> ★ 日志里**必须**有 `delivery_id` / `pr` / `head_sha` / `cr_number` —— 否则事后排查无从下手。

### 11.3 审计

```
每次判定产生一条审计记录：
  { 时间, 操作者(系统), PR, head_sha, 分支, 环境, CR 号, 命中规则, 结论, 判定时刻, 有效期 }
写回：
  ① CR 管理平台（如果平台有"备注/流转记录"接口）
  ② 结构化日志（可被日志系统长期保存）
  ③ 可选：独立的审计存储（数据库 / GCS）
```

---

## 13. 安全

| 项 | 要求 |
|---|---|
| **Webhook 验签** | `X-Hub-Signature-256` + `hmac.Equal`（防时序攻击） |
| **凭据** | 私钥 / webhook secret / CR 平台 token → **Secret Manager** → External Secrets → K8s Secret。**绝不入 Git、绝不打进镜像** |
| **App 权限** | `Metadata: Read` + `Pull requests: Read` + `Checks: Write`。**绝不 `Contents: Write`**（能改代码 = 能绕门禁） |
| **分支保护** | required check **限定来源 App**（防同名 check 伪造） |
| **凭据轮换** | GitHub 后台生成新私钥 → 更新 Secret → 重启 → 删旧私钥（GitHub 支持一段时间内两个私钥并存） |
| **公网暴露面** | 只暴露 `/github/webhook`；`/metrics`、`/readyz` 放内网或加鉴权 |
| **限流** | 单 IP 速率限制；`http.MaxBytesReader` 限制请求体 |
| **代码仓库隔离** | CR Check 的代码在**独立仓库**，CODEOWNERS + 双人复核 + 保护分支 |
| **递归风险** | 改 CR Check 代码的 PR → 走**另一条**路径（人工双人复核），不能自己审自己 |

---

## 14. 里程碑与工作量

> 假设：**1 名熟悉 Go 的工程师**，熟悉 Kubernetes / Argo CD，不熟悉 CR 平台内部。

| 阶段 | 内容 | 产出 | 工作量 | 验收 |
|---|---|---|---|---|
| **M0 决策** | 定死：环境口径（prd/prod）、受管分支清单、CR 号载体、CR 状态白名单、Maintenance Window 定义、审批规则 | 一份《门禁规则说明》+ `policy.yaml` 初稿 | 2–3 人日（**含沟通**） | 需求方签字 |
| **M1 平台对接** | CR 平台客户端 + 契约测试 | `internal/crplatform` | 3–5 人日 | 能查到 CR、状态映射表覆盖平台全部状态 |
| **M2 服务骨架** | 签名/去重/分发/ACK + 部署清单 + 指标 | 可部署的最小服务 | 3–4 人日 | Ingress 200、healthz 通过、队列通 |
| **M3 判定 + check** | 规则引擎 + check 写入（两阶段） | 能出 check | 5–7 人日 | PR 上出现 ✓/✗，失败原因可读 |
| **M4 重扫 + 告警** | 定时重扫、指标、告警、审计 | ★ 兜底能力 | 3–4 人日 | **窗口关闭后已有绿勾的 PR 合不了** |
| **M5 上强制** | 分支保护（required check + 来源 App） | 门禁生效 | 1–2 人日 | 不合规 PR 合不了 |
| **M6 测试与演练** | 单测补齐、绕过测试、熔断演练 | 测试报告 | 4–6 人日 | 五条绕过路径全部按预期 |
| **M7 增强** | artifact 一致性、PR 评论、Merge Queue | — | 按需 | — |

**合计 MVP（M0–M5）≈ 17–25 人日**（不含 M6 测试）。

> ★ **和 [`Develop-git-apps.md`](./Develop-git-apps.md) §6.3 的估算（1200–1700 行 Go）是对得上的**：
> 按 30–40 行/人日（含测试、清单、文档），17–25 人日 ≈ 600–1000 行。合理。

---

## 15. 风险清单

| # | 风险 | 影响 | 概率 | 缓解 |
|---|---|---|---|---|
| 1 | **窗口过期后仍能合并**（check 缓存） | ★ 门禁被静默绕过 | 高 | 定时重扫（必做）+ Merge Queue + CR 平台回调 |
| 2 | **事件丢失**（GitHub 不自动重投） | PR 上没结论 → 全员卡住或绕过 | 中 | 定时重扫 + 投递失败巡检 |
| 3 | **CR 平台不可用** | 全员合不了（fail-closed） | 中 | 超时 + 退避 + 熔断开关（**须预先约定由谁执行**）+ 告警 |
| 4 | **出网不通** | 写不回 check → 门禁静默失效 | 中 | Cloud NAT + "读到但没写出"独立告警 |
| 5 | **CR 号解析歧义** | 放行了错误的 CR | 中 | R1a 唯一性 + 载体冲突检测 |
| 6 | **平台新增状态未映射** | 未知状态被当可执行 → 门禁被打开 | 中 | 未知状态 fail-closed + 平台变更通知机制 |
| 7 | **同名 check 被伪造** | 门禁被绕过 | 低 | 分支保护限定来源 App |
| 8 | **改了门禁自己的代码** | 门禁形同虚设 | 中 | 独立仓库 + CODEOWNERS + 双人复核 |
| 9 | **维护窗口时区错误** | 该拦的没拦 / 不该拦的拦了 | 中 | IANA 时区 + 跨零点与 DST 单测 |
| 10 | **配额打满** | 重扫失败 → 兜底失效 | 低 | 配额预算 + 限速 + 指标告警 |

---

## 16. 结论与建议

### 15.1 三条最重要的建议

```
① 事件驱动 + 轮询兜底，双轨并行上线。
   先"只报不拦"（M2–M4）跑 1–2 个迭代，确认事件丢失率 ≈ 0，再上强制（M5）。

② 定时重扫是 MVP 的必备件，不是优化项。
   它同时解决"事件丢失"和"窗口过期"两个漏洞 —— 投入产出比最高。

③ 规则收集式（collect-all），失败信息写成人能行动的话。
   "变更单 1234 当前状态为 Draft，需要 Approved 或 Implement"
   比 "check failed" 有用一百倍。
```

### 15.2 落地顺序

```
第 1 周   M0 决策（和需求方 + CR 平台方对齐口径）
第 2 周   M1 + M2（CR 平台客户端 + 服务骨架，能收到事件、能查 CR）
第 3 周   M3（规则 + check 出结论）
第 4 周   M4（重扫 + 告警）+ M5（分支保护上强制）
第 5 周   M6（绕过测试 + 熔断演练 + 上线）
```

### 15.3 现在最该问的 5 个问题

```
Q1  CR 平台的 targetEnv 字面量是什么？prd / pre-prod / staging / PRD？
Q2  平台的状态枚举有哪些？"可执行"对应哪个值？是否就叫 Implement？
Q3  Maintenance Window 定义在哪：平台侧（每个 CR 自带）还是我们配置（固定时段）？
Q4  CR 号写在 PR 的哪里？label / body / trailer？平台是否有强制的填写位置？
Q5  受管分支清单：PRD 分支叫什么？生产分支叫什么？
```

---

## 17. 关联文档

| 主题 | 文档 |
|---|---|
| **★ 可运行的 Go 实现**（代码 / 配置 / 清单 / 本地验证手册） | [`cr-check/`](./cr-check/) |
| 可行性评估、规则表 R0–R13a、时间窗口三种建模 | [`Develop-git-apps.md`](./Develop-git-apps.md) |
| Webhook 是什么、服务怎么跑起来、配置清单、故障速查 | [`webhook-and-backend-service.md`](./webhook-and-backend-service.md) |
| **外部交互模型：pull vs push、六个新契约、迁移路线** | [`12-webhook-push-vs-pull.md`](./12-webhook-push-vs-pull.md) |
| GitHub App 概念、Installation、三层门禁 | [`11-github-app-concepts.md`](./11-github-app-concepts.md) |
| Repository Secret 与 Argo CD 侧的 GitHub App 用法 | [`../07-repository-githubapp.md`](../07-repository-githubapp.md) |

### 标注

| 标注 | 内容 |
|---|---|
| **官方保证** | installation token 5000 次/小时；webhook 投递超时 10 秒；失败投递不自动重投；`skipped`/`neutral` 算通过；一个 App 一个 Webhook URL；Checks API 需 `Checks: write` |
| **本设计推荐** | collect-all 规则引擎；先 ACK 再异步；定时重扫为 MVP 必备；check 同名覆盖；系统异常 fail-closed；未知状态 fail-closed；policy.yaml 与代码分离；PRD 作为独立环境 |
| **需实测 / 部署前验证** | Argo CD 实际轮询间隔与 jitter；git over HTTPS 是否计入 installation 配额；私有仓库 `merge_group` 可用性；CR 平台是否支持回调与审计写回接口；GKE Ingress/托管证书形态 |
