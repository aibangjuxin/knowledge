# 12 · 外部接口交互模型的变化：从「拉（pull）」到「推（push）」

> **本文回答一个问题**
> 装了 GitHub App / 配了 Webhook 之后，**我们和 GitHub 之间的交互逻辑到底变了什么？**
>
> 你的原话（完全正确）：
> > "过去如果没有这个外部接口，我这个 Argo CD 不停地去读我的 GitHub，
> > 对 GitHub 是一个访问量的增加。但是如果有这个 Webhook，
> > 他看到我的 Git 的 branch 里面有了变化之后，
> > 他去我的对应的 Webhook 对应的这个 URL 下发通知，
> > 告诉我的 Argo CD 它的 GitHub 的配置变了，或者说是文件做了对应的更新。"
>
> **一句话结论**
> **接口方向反转了：以前是「我们主动去 GitHub 拉」，现在是「GitHub 主动来我们这边推」。**
> 这不是"少写了几行配置"，而是**换了一套契约**：幂等、超时、顺序、失败语义、
> 公网暴露面全部要重新设计。

> **本文分三部分**
> - **Part A（§0–§5）**：旧模型 vs 新模型，量化对比
> - **Part B（§6–§10）**：push 模型带来的**六个新契约**（这是最容易漏的部分）
> - **Part C（§11–§14）**：扇出架构、迁移路线、风险清单

---

## 0. 先把结论摆出来

| | 旧模型（pull / 轮询） | 新模型（push / Webhook） |
|---|---|---|
| **谁发起** | 我们（Argo CD repo-server） | **GitHub** |
| **方向** | 我们 → `api.github.com` / git 远端 | GitHub → 我们的公网 HTTPS 端点 |
| **频率** | 定时（默认 ~120s + jitter，按仓库数 × Application 数放大） | 事件驱动（有事才发） |
| **我们需要的网络** | **出站**（Cloud NAT / 节点出网） | **入站**（公网 DNS + Ingress + TLS）**+ 出站**（回写 check / 查 PR） |
| **故障表现** | 拉不到 → 重试 → 延迟变大（**自愈**） | 收不到 → **事件永久丢失**（**不自愈**） |
| **幂等要求** | 无（每次都是新的拉取） | **必须有**（GitHub 会重复投递） |
| **顺序保证** | 无所谓（总是拉最新） | **无保证**（事件可能乱序到达） |
| **配额消耗** | 高（持续消耗） | 低（只在有事时消耗） |

> ★ **最关键的一行**：
> 轮询模式下"拉不到就下次再拉"，**天然自愈**；
> Webhook 模式下"没收到就是永远收不到"，**天然不自愈**。
> 这就是为什么 §7 整节都在讲"事件丢了怎么办"。

---

## 1. Part A · 旧模型：轮询（pull）

### 1.1 Argo CD 侧发生了什么

```
Application controller（默认 180s reconciliation）
        │
        ▼
repo-server 需要知道"仓库有没有新提交"
        │
        ▼
git ls-remote / fetch   ← 这一步要访问 GitHub（用 installation token 或 PAT）
        │
        ▼
有变化 → 重新 clone / 渲染 manifest → 比对 live state → sync
```

> ★ **注意**：轮询的**成本不是线性于"用户操作次数"，而是线性于
> 「受管仓库数 × 该仓库上的 Application 数 × 时间」**。
> 10 个仓库 × 每个仓库 5 个 Application × 每 120 秒一次 ≈ 每分钟 2.5 次 git 探测，
> 一天就是几千次。**即使半夜没人改代码，它照样在跑。**

### 1.2 对 GitHub 的影响

| 影响项 | 说明 |
|---|---|
| **API 配额消耗** | GitHub App 的 installation token 走 REST API 的配额：**每个 installation 每小时 5000 次请求**（官方保证）。Webhook 模式下，PR/Check/Commit 相关的读操作由事件 payload 直接携带，**几乎不再消耗 REST 配额** |
| **git 传输层请求** | `ls-remote` / `fetch` 属于 Git over HTTPS，**与 REST API 配额是不同维度**；但同样消耗 GitHub 的基础设施与速率限制 |
| **可观测性** | GitHub 侧看到的是持续不断的匿名/机器人 git 流量 |
| **延迟** | 最坏情况 = 一个轮询周期 + 渲染 + 同步时间（默认 ~2–3 分钟量级） |

### 1.3 轮询不是坏事

> ⚠️ **不要把"有 Webhook"理解成"可以关掉轮询"。**

| 场景 | 没有 Webhook 会怎样 |
|---|---|
| Webhook 投递失败 | 事件**永久丢失** → 部署停在旧版本，**没有任何自愈** |
| GitHub 侧事件系统抖动 | 同上 |
| 集群长时间不可用导致服务没起 | 恢复后**错过的所有事件都不会补发** |

**因此 Argo CD 官方文档的建议一直是：Webhook 用于"降低延迟"，轮询作为"兜底保底"。**
本仓库既有结论也一致（见 [`11-github-app-concepts.md`](./11-github-app-concepts.md) §5.2）。

---

## 2. Part A · 新模型：Webhook（push）

### 2.1 方向反转

```
        ┌──────────────────────────────────────────────┐
        │  旧（pull）                                   │
        │  Argo CD repo-server ──git ls-remote──▶ GitHub │
        │  Argo CD repo-server ──GET /commits──▶ GitHub  │
        └──────────────────────────────────────────────┘

        ┌──────────────────────────────────────────────┐
        │  新（push）                                   │
        │  GitHub ──POST /api/webhook/github──▶ Argo CD  │
        │  GitHub ──POST /github/webhook─────▶ CR Check  │
        └──────────────────────────────────────────────┘
```

### 2.2 一个 push 事件的完整生命周期

```
 ① 用户 push / 提 PR
        │  GitHub 内部状态变更
        ▼
 ② GitHub 事件系统：查出"谁订阅了这个事件"
        │  → 找到 CR Check 的 installation
        ▼
 ③ GitHub 对每个订阅者发一次 HTTP POST
        │  POST https://pr-gate.example.com/github/webhook
        │  X-GitHub-Event: pull_request
        │  X-GitHub-Delivery: <uuid>        ← 幂等键
        │  X-Hub-Signature-256: sha256=...  ← 验签
        ▼
 ④ 我们的服务
        │  验签 → 去重 → 解析 → 判定 → 回写 check run
        ▼
 ⑤ GitHub 的 Check API（出站，用 installation token）
        │  POST /repos/{o}/{r}/check-runs
        ▼
 ⑥ PR 页面出现 ✓ / ✗；分支保护据此决定能否 merge
```

> ★ **第 ③ 步和第 ⑤ 步方向相反**：
> 入站是 GitHub 推给我们，出站是我们推给 GitHub。
> **两个方向都要能通**，只通一个就会出现"收到了但写不回"或"写得回但收不到"。

### 2.3 对 GitHub 的影响（收益侧）

| 收益 | 说明 |
|---|---|
| **REST 配额大幅下降** | PR 详情、commit 列表这些查询不再需要我们主动拉 —— **事件 payload 里已经带了**。只有"额外查一次"（如读 changed files、查 CR 平台）才走 API |
| **延迟从分钟级降到秒级** | 门禁体验从"等两分钟"变成"几秒" |
| **只处理真正发生的事** | 无变更时零消耗 |
| **可扩展到多消费者** | 同一个事件可以被 N 个订阅者分别消费（见 §11） |

---

## 3. Part A · 量化对比

### 3.1 延迟

| 环节 | 轮询 | Webhook |
|---|---|---|
| 发现仓库变化 | 0 ~ 轮询周期（默认 ~120s + jitter） | **秒级**（< 1s 到数秒） |
| 门禁 check 出结论 | + 判定耗时 | + 判定耗时（相同） |
| **用户感知** | **"我合不了，等一会儿再试"** | **"我合不了，因为 CR-1234 是 Draft"** |

> ★ 门禁场景下这个差别是**体验级**的：
> 轮询模式下开发者会反复点 merge、反复刷新页面，**最后大家都会养成"多等两分钟"的习惯**，
> 门禁的存在感被延迟稀释。

### 3.2 GitHub API 请求量

| 消费者 | 轮询模式（估算） | Webhook 模式 |
|---|---|---|
| Argo CD 探测仓库 | `git ls-remote` × (仓库数 × App 数) × (86400 / 120) | 由事件触发，**降一个数量级以上** |
| Argo CD 渲染结果 | 变更时才发生 | 变更时才发生（相同） |
| CR Check 读 PR 详情 | — | 事件 payload 已含大部分；仅 `changed files` 需另查 |
| CR Check 写 check run | — | 每次判定 1 次 `POST /check-runs` + 1 次 `ListCheckRunsForRef`（用于覆盖同名） |

> ⚠️ **标注**：installation token 的 **5000 次/小时** 是 REST API 维度的官方限制；
> **git over HTTPS 的请求不计入 REST API 配额**，但仍有各自的速率限制。
> 具体的 git 层行为请以你们实测为准（见 §14 验证项）。

### 3.3 故障半径对比

| 故障 | 轮询 | Webhook |
|---|---|---|
| 我们的服务挂了 | 下次轮询时恢复即可（**自愈**） | **事件全丢**（不自愈）；需人工 Redeliver 或定时重扫 |
| GitHub 事件系统异常 | 影响很小（我们不依赖它） | **事件丢失**（需定时重扫兜底） |
| 网络中断 | 轮询重试即可 | 入站断了 = 收不到；出站断了 = 写不回 check（**静默失效**） |
| 证书过期 | 无影响 | **所有投递失败**（且不自动重试） |

---

## 4. Part A · 「外部接口」的契约变化清单

> 这是本文最实用的一张表。**从 pull 换到 push，下列每一项都必须重新设计。**

| 维度 | Pull 时代的做法 | Push 时代必须做的事 |
|---|---|---|
| **幂等性** | 天然幂等（每次重新拉） | **必须做**：`X-GitHub-Delivery` 去重，重复投递不能产生重复副作用 |
| **乱序** | 不存在（总是最新） | **必须处理**：`synchronize` 可能比 `labeled` 先到 → 判定要基于"当前 PR 快照"而不是"事件内容" |
| **超时预算** | 拉取超时可以慢慢重试 | **≤10 秒**：GitHub 只等 10 秒，超时记投递失败 → **先 ACK 再异步处理** |
| **失败重试** | 自己控制节奏 | **GitHub 不会自动重投** → 必须自建重试/死信/定时重扫 |
| **公开暴露面** | 无（只需出站） | **必须公网 HTTPS + 域名 + 证书** → 攻击面从 0 变成 1 |
| **鉴权方向** | 我们的凭据（token）保护我们 | **对方不知道我们是谁** → 靠 webhook secret 的 HMAC 验签 |
| **负载形态** | 固定、可预测 | **突发**（大 PR 合并时可能几十个事件同时到）→ 需要并发控制 |
| **可观测性** | 指标来自我们自己（轮询次数） | **要额外监控 GitHub 侧的投递失败**（App 后台 Recent Deliveries 没有 API 告警） |
| **幂等副作用** | 无 | 写 check run 必须"覆盖同名"而不是"新建"（否则新旧结论并存，GitHub 取到旧的） |

---

## 5. Part A · 三个必须分清的"事件"

| 事件 | 含义 | 谁关心 |
|---|---|---|
| **GitHub → 我们的 webhook 投递** | "某件事发生了"的通知 | CR Check（PR 门禁）、Argo CD（应用刷新） |
| **我们的判定 → GitHub 的 Check Run** | "我判定这个 PR 合不合规"的结论 | 分支保护（强制力） |
| **我们 → Argo CD 的 sync 触发** | "把这个应用同步到目标态" | Argo CD |

> ★ **三者不是一回事。**
> 装了 App ≠ 有门禁；写出 check ≠ 能拦住 merge；
> 拦住 merge ≠ 拦住 kubectl 直接改集群。
> 参见 [`11-github-app-concepts.md`](./11-github-app-concepts.md) §11.3 的三道闸。

---

## 6. Part B · Push 模型下的六个新契约

### 6.1 契约一：至少一次投递（at-least-once）+ 必须幂等

GitHub 对同一个事件**可能投递多次**（重试机制、手动 Redeliver、事件系统重放）。

```
处理方式：
  deliveryID := r.Header.Get("X-GitHub-Delivery")
  if seen.Contains(deliveryID) { return 200 }   // 已经处理过
  seen.Add(deliveryID, ttl=24h)
  ... 真正的处理 ...
```

- 去重存储：Redis（推荐，多副本共享）/ DB / 内存 TTL（**多副本下会失效**）
- ⚠️ **快速 ACK 模式下必须自己做幂等** —— 因为 GitHub 不会因为"你返回了 200"而重投，
  但**因为超时/5xx 而重投**时你要能挡住。

### 6.2 契约二：10 秒超时预算 → 必须"先 ACK，再异步"

```
❌ 同步处理：验签 → 查 CR 平台 → 写 check → 返回 200
   风险：CR 平台慢 3 秒 + GitHub API 慢 2 秒 = 超时 → 投递失败 → 开发者看不到结论

✅ 异步处理：验签 → 去重 → 入队 → 立刻返回 200
            后台 worker：判定 → 写 check run
```

| 权衡 | 说明 |
|---|---|
| 好处 | 永远在超时预算内返回；判定逻辑可以慢慢调；便于重试 |
| 代价 | **必须自建可靠队列**（GitHub 不帮你重试）；进程崩溃会丢在途事件 |
| 队列选型 | 轻量：Redis Stream / Redis List + BRPOP；重型：Cloud Tasks / Pub/Sub |

> ★ **判据**：**判定逻辑要调外部系统（CR 平台）→ 一律异步。**
> 只在本地读 payload 的纯计算 → 可以同步。

### 6.3 契约三：事件可能乱序、可能缺失

```
时间线（乱序到达）：
  t0  push 新提交            → 事件 A (synchronize)
  t1  加 label cr/1234       → 事件 B (labeled)
  t2  到达顺序：B 先到，A 后到
```

**错误做法**：按事件 payload 里的内容判定（用 B 的 payload 判断 label，用 A 的 payload 判断代码）。
**正确做法**：**每次都读"当前 PR 快照"再判定**（用 GitHub API `GET /pulls/{n}`，或用事件里
`pull_request` 对象的**最新**字段 + 必要时补查一次）。

> 推论：**判定必须以"当前状态"为准，而不是"事件发生时的状态"**。
> 这也顺便解决了"PR 又 push 了一次，旧 success 冒充新结论"的问题 ——
> 只要每次都写**同名 check 覆盖**，最新的结论就是唯一有效的。

### 6.4 契约四：投递失败不会自动重试

GitHub 官方明确说明：**失败的 webhook 投递不会自动重投**，只能在 UI 里手动 Redeliver。

```
后果：
  · 服务短暂重启 → 这段时间的事件永久丢失
  · 证书过期一晚上 → 昨晚所有事件丢失
  · 网络抖动 → 零星事件丢失
```

**必须有的兜底机制（按优先级）**：

| 兜底 | 做法 | 覆盖的场景 |
|---|---|---|
| **① 定时重扫** | 每 N 分钟用 GitHub API 列出"受管生产分支上仍 open 的 PR"，重跑判定并覆盖 check | ★ **覆盖面最广**（能补齐所有丢失事件） |
| **② 主动拉取 CR 平台** | CR 平台支持回调时，窗口开/关、状态变更时主动通知我们 | 消除"时间流逝"类触发（见 §8.2） |
| **③ 手动 Redeliver** | 运维从 GitHub 后台重投 | 单点补救 |
| **④ 定期自检** | 巡检"有 check 结论的 PR 是否都已合并/关闭"，异常告警 | 发现漏判 |

> ★ **① 定时重扫是必做项**，而且它同时解决了 §8.2 的"时间窗口过期"问题。
> 一举两得。

### 6.5 契约五：我们变成了一个公网服务

```
Pull 时代：我们的出站端口暴露给 GitHub 的白名单 IP
Push 时代：我们的入站 443 暴露给互联网
```

**安全清单**：

| 项 | 要求 |
|---|---|
| **只暴露一个路径** | `/github/webhook`（其余路径返回 404） |
| **必须验签** | `X-Hub-Signature-256`，用 `hmac.Equal`（防时序攻击） |
| **限流** | 单 IP 速率限制；防 webhook 洪泛 |
| **请求体大小限制** | `http.MaxBytesReader`（防内存打爆） |
| **TLS** | 必须是**被信任**的证书链（自签不行）；建议用 Google 托管证书自动续期 |
| **凭据不落盘** | 私钥 / webhook secret 走 Secret Manager → External Secrets |
| **内部管理面分离** | `/metrics`、`/readyz` 等运维端点**不要**挂在同一个公网 host 上（或加网络策略） |

### 6.6 契约六：出站配额与并发限制

| 限制 | 值 | 影响 |
|---|---|---|
| **installation token REST 配额** | 5000 次/小时 / 每个 installation（官方保证） | 定时重扫 + 写 check 都在消耗它 |
| **并发连接数** | REST API 有并发上限（secondary rate limit） | 大批量重扫要限速 + 退避 |
| **二次限流（secondary rate limit）** | 触发后返回 403/429 + `Retry-After` | 必须实现指数退避（见 [`Develop-git-apps.md`](./Develop-git-apps.md) §8 坑 18） |

> ★ **重扫的配额预算要算清楚**：
> 假设 50 个 open 生产 PR，每 5 分钟重扫一次 = 12 次/小时 × 50 PR × 2 次 API（读 PR + 写 check）
> = 1200 次/小时。**在 5000 配额内，但只剩 76% 余量** —— 必须加监控和限流。

---

## 7. Part B · 出站不通 = 门禁静默失效

```
入站通（收到事件）+ 出站不通（写不回 check）
   → PR 上永远没有 check
   → 分支保护等一个永远不会出现的 check
   → 表现：所有人都"合不了"，但没人知道为什么
```

**这是最常见的翻车点**，必须单独监控：

| 指标 | 阈值示例 | 动作 |
|---|---|---|
| `cr_gate_webhook_received_total{event}` | — | 观察 |
| `cr_gate_webhook_delivery_fail`（GitHub 侧投递失败率） | > 1% | 告警 |
| `cr_gate_github_api_errors_total` | 出站错误率 > 1% | 告警 |
| `cr_gate_checks_written_total` vs `cr_gate_evaluations_total` | 差值持续增大 | **告警（写回失败）** |
| `cr_gate_readyz` | 非 1 | 告警 |

> ★ **"读到了但没写出去" 必须是一个独立的告警指标**，
> 不能靠"PR 上没 check"这种间接现象去发现。

---

## 8. Part B · 两个「push 模式也管不到」的场景

### 8.1 事件驱动覆盖的是"有人做了某个动作"

```
有人 push 了        → 有事件 ✅
有人改了 label      → 有事件 ✅
有人合并了          → 有事件 ✅

但：
时间过去了（窗口关闭）→ 没事件 ❌
CR 平台把状态改成 Rejected → 我们不知道（除非它回调我们）❌
```

### 8.2 窗口过期这个"经典漏洞"

```
10:00  CR 有效 → 判定 success ✅
10:05  Maintenance Window 关闭
10:30  有人点 Merge
       → GitHub 看到 head SHA 上有个绿 check → 放行 ❌❌❌
```

**根因**：required status check 是**按 head SHA 查已有结论**，不会在 merge 时刻重新执行规则。

**Push 模型下唯一的解法就是"自己造一个触发源"**：

| 解法 | 触发源 | 延迟 |
|---|---|---|
| **定时重扫重评** | 内部 cron | ≤ 轮询间隔 |
| **Merge Queue** | GitHub 的 `merge_group` 事件（**这是唯一一个 GitHub 主动在合并时刻发的事件**） | 精确 |
| **CR 平台回调** | 平台侧推"窗口开/关、状态变更" | 实时（需平台支持） |

> 详见 [`Develop-git-apps.md`](./Develop-git-apps.md) §7.2–§7.3。

---

## 9. Part C · 扇出：同一个事件，多个消费者

### 9.1 三种拓扑

```
拓扑 A：各建各的 App（推荐）
┌──────────┐  push 事件   ┌──────────────┐
│  GitHub  │─────────────▶│ Argo CD App  │ (形态A，只要 token，可不订阅)
└────┬─────┘              └──────────────┘
     │  pull_request 事件
     ▼
┌──────────┐
│  GitHub  │─────────────▶┌──────────────┐
└──────────┘              │ CR Check App │ → 写 check run
                          └──────────────┘

拓扑 B：网关路由
┌──────────┐   ┌──────────┐  ┌────────┐  ┌──────────┐
│  GitHub  │──▶│  Router  │─▶│ ArgoCD │  │CR Check  │
└──────────┘   └──────────┘  └────────┘  └──────────┘
                （按 X-GitHub-Event 分流）

拓扑 C：单 App + 内部透传
┌──────────┐   ┌──────────────────┐   ┌────────┐
│  GitHub  │──▶│ CR Check 后端    │──▶│ ArgoCD │
└──────────┘   │ （收到 push 原样  │   └────────┘
                │  转发给 Argo CD） │
                └──────────────────┘
```

| 拓扑 | 优点 | 缺点 | 适用 |
|---|---|---|---|
| **A · 两个 App** | ✅ 权限面分离干净（Argo CD 要 `Contents:Read`，CR Check 绝不能有 `Contents:Write`）；互不影响 | 多维护一个 App | ✅ **默认选它** |
| **B · 网关** | 一个入口，扩展性好 | 网关本身成了关键路径与单点；要额外维护 | 消费者 ≥ 3 |
| **C · 透传** | 最省事（几十行代码） | **CR Check 挂了会同时影响秒级同步**；两个 App 混用凭据 | 快速 POC |

> ★ **拓扑 A 的一个额外好处**：Argo CD 用的那个 App 是**形态 A**（只用 token clone 仓库），
> 它其实**根本不需要订阅 webhook 事件** —— 可以直接取消订阅，
> 把 Webhook 位置整个腾给 CR Check（见 [`Develop-git-apps.md`](./Develop-git-apps.md) §12.2）。

### 9.2 谁该订阅什么事件

| 消费者 | 订阅的事件 | 不订阅会怎样 |
|---|---|---|
| **Argo CD** | `push`（可选；取消订阅则退化为纯轮询） | 延迟变大（**不是故障**） |
| **CR Check** | `pull_request`（`opened/synchronize/reopened/labeled/unlabeled/ready_for_review`）<br>`pull_request_review`（可选）<br>`check_run`（`rerequested`）<br>`merge_group`（用 Merge Queue 时）<br>`installation`（装卸时清理本地状态） | ★ **漏判 = 门禁缺口（安全问题）** |
| **通知服务** | `pull_request`、`pull_request_review` | 只是少通知 |

> ⚠️ **两类 App 对"漏订阅"的容忍度完全不同**：
> Argo CD 漏订阅 → 只是慢；CR Check 漏订阅 → **门禁被绕过**。

---

## 10. Part C · 迁移路线（从轮询平滑切到 Webhook）

> ⚠️ **推荐双轨并行**，不要一次性切换。

| 阶段 | 做什么 | 验收 |
|---|---|---|
| **P0 现状** | 纯轮询 | 基线：记录部署延迟、API 请求量 |
| **P1 并行** | 装 App、配 Webhook、**但轮询保持原样** | Webhook 路径可用；对比两条路径的结果一致 |
| **P2 观察** | 跑 1–2 个迭代，监控：投递失败率、事件丢失（重扫 vs 事件的差异）、API 请求量下降幅度 | 事件丢失率 ≈ 0 |
| **P3 切换** | 关闭 Argo CD 的 App 事件订阅（保留轮询兜底）；把 CR Check 置为 required check | 门禁生效；轮询仍在（兜底） |
| **P4 降频** | 轮询间隔从 120s 调到 5–10 分钟（仍兜底） | 延迟无明显变化；API 请求量显著下降 |
| **P5 收尾** | 只在必要时保留高频轮询；完善重扫兜底 | — |

> ★ **P1 阶段一定要做"事件 vs 重扫"的结果比对**：
> 对同一个 PR，分别用事件路径和重扫路径判定，比对 check 结论是否一致。
> 这是验证"事件没丢、判定没跑偏"的唯一可靠方法。

---

## 11. Part C · 反模式清单

| 反模式 | 为什么错 | 正确做法 |
|---|---|---|
| **"有 Webhook 就不用轮询了"** | 事件会丢，丢了不自愈 | 轮询降频保底 + 定时重扫 |
| **"Webhook URL 填 Argo CD 的地址就够了"** | 那是 Argo CD 的 App；CR Check 需要读 PR + 写 check，权限面不同 | 建两个 App（拓扑 A） |
| **"在 handler 里同步查 CR 平台再写 check"** | 极易超过 10 秒 → 投递失败 | 先 ACK 再异步（§6.2） |
| **"每次都 CreateCheckRun 新建一个"** | 同名多个 check 并存，GitHub 可能取到旧的 | 查同名 → Update 覆盖 |
| **"系统异常时写 neutral / skipped"** | GitHub 把 `skipped`/`neutral` **当作通过** → 门禁直接失效 | 只能写 `failure` / `action_required` |
| **"公网入口和运维端点共用一个 host"** | 攻击面扩大 | 运维端点放内网，或加鉴权 |
| **"自签证书"** | GitHub 要求有效证书链 | Google 托管证书 / cert-manager |
| **"凭据写进 Git / 打进镜像"** | 整个 App 权限泄露 | Secret Manager + External Secrets |
| **"定时重扫不限速"** | 打爆 installation token 配额 | 限并发 + 指数退避 + 预算监控 |

---

## 12. Part C · 一句话总结

```
Pull 时代：  我们定时去问 GitHub "有变化吗"        → 持续消耗、延迟高、自愈
Push 时代：  GitHub 有事主动来敲我们的门            → 零消耗、秒级、**不自愈**

⇒ 换模型 = 换契约：
   幂等、顺序、超时、重试、暴露面、配额，六个都要重新设计。
⇒ 并且必须保留一条 pull 通道（轮询 / 定时重扫）作为兜底。
```

---

## 13. 关联文档

| 主题 | 文档 |
|---|---|
| Webhook URL 是什么、你的 Go 服务怎么跑起来 | [`webhook-and-backend-service.md`](./webhook-and-backend-service.md) |
| 自研 App 的可行性、规则表、Go 骨架、时间窗口难点 | [`Develop-git-apps.md`](./Develop-git-apps.md) |
| GitHub App 概念 / Installation / 三层门禁 | [`11-github-app-concepts.md`](./11-github-app-concepts.md) |
| CR Check 的 Go 服务设计与实现评估 | [`13-cr-check-go-design.md`](./13-cr-check-go-design.md) |
| Argo CD 触发链路细节 | [`../09-troubleshooting.md`](../09-troubleshooting.md) |

---

## 14. 标注与待验证项

| 标注 | 内容 |
|---|---|
| **官方保证** | ① GitHub App installation token 的 REST API 限额 **5000 次/小时/每个 installation**；② Webhook 投递超时 **10 秒**；③ **失败的投递不会自动重投**；④ 保存 webhook 时 GitHub 发 `ping` 事件校验可达性；⑤ required status check 为 `successful`/`skipped`/`neutral` **都算通过**；⑥ 一个 App 只有一个 Webhook URL |
| **工程常识** | 幂等键用 `X-GitHub-Delivery`；先 ACK 后异步；同步查外部系统必超 10s；去重存储多副本必须共享（Redis）；重扫要做配额预算 |
| **本仓库事实** | `argocd-server` 8080 容器端口、`argocd-applicationset-controller` 7000/8080（来自 `install.yaml`） |
| **需实测 / 部署前验证** | ① Argo CD 的实际轮询间隔与 jitter（不同版本默认值不同，以你们集群的 `argocd-cmd-params-cm` / 实测为准）；② git over HTTPS 的请求是否计入 installation token 的 REST 配额（**与 REST API 是不同维度**，具体行为需实测）；③ GitHub 是否有 webhook 投递失败的官方 API（目前主要靠 UI 手动 Redeliver，需要自建巡检）；④ 私有仓库的 `merge_group` 事件可用性；⑤ 你们 CR 平台是否支持回调（决定 §8.2 能否用实时解法） |
