# 23 · CD Driver：用 Argo CD API 驱动同步

> **直接回答**：「我们会考虑为了减少 GKE 的压力，采用一些对应的 CD pipeline 来做 Argo CD 的同步。」
> 「这个 pipeline 具体怎么设计？它和 Argo CD 怎么配合？它挂了怎么办？」
>
> **一句话结论**
> ★ driver 就是一个**拿着 Argo CD token、按策略调用 sync API 的小服务**。
> 它的三个核心设计点：
> ① **幂等键** = `(app, revision, prune)` —— 同一个键只触发一次；
> ② **触发源** = GitHub 事件（push / deployment）+ 周期性巡检（兜底）；
> ③ **降级策略** = driver 挂了就"停"还是"退回自动"——**必须提前拍板**（见 `7）。
>
> ⚠️ **先看 [`18 `5.1`](./18-framework-github-first-gitops.md)**：
> 「减少 GKE 压力」有三种含义，**只有第三种（M-3 控制面资源压力）才真的需要 driver**。
> 如果你的痛点是 M-1/M-2，**调 `timeout.reconciliation` + 配 webhook 就够了**，不用写服务。

---

## 目录

| 章节 | 内容 |
|---|---|
| [`1](#1-先确认真的需要-driver) | 三种压力 → 三种解法 |
| [`2](#2-driver-架构) | 组件、数据流、部署形态 |
| [`3](#3-argo-cd-api-怎么调) | 认证 + 触发同步 + 查状态 |
| [`4](#4-幂等设计) | ★ 幂等键、状态机、去重 |
| [`5](#5-触发源) | GitHub 事件 + 巡检兜底 |
| [`6](#6-失败处理) | 重试、死信、可观测性 |
| [`7](#7-降级策略) | ★ driver 挂了怎么办 |
| [`8](#8-与-cr-check-的关系) | 复用还是新写 |
| [`9](#9-坑清单) | 12 条坑 |

---

## 1. 先确认真的需要 driver

| 压力类型 | 症状 | 最省事的解法 | 需要 driver？ |
|---|---|---|---|
| **M-1 轮询开销** | Argo CD 一直在拉 Git、算 diff，CPU 高 | ① 配 `/api/webhook` ② 调大 `timeout.reconciliation` ③ 减少 Application 数量 | ❌ |
| **M-2 目标集群 API 压力** | 目标集群 apiserver 被打爆 | ① 调大 reconciliation ② 关 `selfHeal` ③ 合并 Application | ❌ |
| **M-3 控制面资源压力** | Argo CD 所在 GKE 资源不够 / 想把控制面移出集群 | driver 跑到 **Cloud Run** 或独立集群 | ✅ |

**调大 reconciliation 的做法**（**当前清单事实**：默认 120s + 60s jitter）：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  timeout.reconciliation: "600s"   # 10 分钟一轮
```

> ★ 配合 webhook（秒级刷新），**用户体验几乎不变，但轮询量降到 1/5**。

---

## 2. driver 架构

```
┌──────────────┐   webhook    ┌──────────────┐   Argo CD API   ┌─────────────┐
│   GitHub     │────────────▶│  CD Driver   │────────────────▶│  Argo CD    │
│ (push/deploy)│             │ (幂等+策略)   │◀────────────────│ (refresh)   │
└──────────────┘             └──────┬───────┘   status 轮询     └──────┬──────┘
                                    │                                  │
                    ┌───────────────┴──────────────┐                   ▼
                    │ 决策输入：                   │            ┌─────────────┐
                    │  · CR 平台：已批准？          │            │   集群      │
                    │  · 维护窗口：现在在内？        │            └─────────────┘
                    │  · Argo CD：窗口允许同步？     │
                    │  · 幂等：这条 (app,rev) 同步过？│
                    └──────────────────────────────┘
```

### 2.1 组件清单

| 组件 | 职责 | 备注 |
|---|---|---|
| **Webhook 端点** | 收 GitHub 事件 | 验签（HMAC）、幂等去重、快速返回 200 |
| **策略评估器** | 读 CR 平台 / Argo CD 状态，做决策 | 规则放配置，不放代码 |
| **Argo CD 客户端** | 调 API：查状态、触发同步 | 带重试与超时 |
| **幂等存储** | 记录"哪个 (app, revision) 已经触发过" | Redis / DB；**不要用内存**（多副本会失效） |
| **巡检器** | 周期性扫描"应该同步但没同步"的 | 兜底：webhook 丢了也能补上 |
| **可观测** | 指标 + 日志 + 告警 | 见 `6.3 |

### 2.2 部署形态

| 形态 | 优点 | 缺点 | 适合 |
|---|---|---|---|
| **Argo CD 同集群（Deployment）** | 简单、能直接读 K8s | **不能减轻 M-3**（还在同一个 GKE） | 只做"审批门禁"，不图减压 |
| **独立 GKE 集群** | 隔离 | 多一套集群成本 | 中大型组织 |
| **Cloud Run** | ★ **弹性、按请求计费、天然与 Argo CD 控制面解耦** | 无状态（幂等状态要外置）、冷启动 | ★ **推荐**：M-3 的正解 |

> ★ **推荐组合**：driver 跑在 **Cloud Run**，
> 幂等状态放 **Cloud SQL / Firestore**（或 Memorystore Redis），
> 定时巡检用 Cloud Scheduler 触发。

---

## 3. Argo CD API 怎么调

> API 全量清单见既有 [`argocd-api.md`](../../argocd-api.md)；这里只列 driver 真正用到的。

### 3.1 认证（两种）

| 方式 | 做法 | 适用 |
|---|---|---|
| **用户名密码换 token** | `POST /api/v1/session`（body: `username`/`password`）→ 拿 `token` → 后续带 `Authorization: Bearer <token>` | 简单，但有密码轮换问题 |
| **服务账号 token** | K8s Secret `argocd-accounts.<account>`，label `account.token: <account>`；token 明文在 data 里 | ★ **推荐**：可轮换、可撤销、不存密码 |

```bash
# 创建 driver 专用的 Argo CD 账号 + token
kubectl -n argocd create secret generic argocd-accounts.cd-driver \
  --from-literal=token="$(openssl rand -hex 32)" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret argocd-accounts.cd-driver account.token=cd-driver --overwrite
```

### 3.2 最小权限策略

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    p, role:readonly, applications, get, proj:platform-prod/*, allow
    p, role:readonly, applications, get, proj:platform-prod/*, allow
    p, role:cd-driver, applications, sync, proj:platform-prod/*, allow
    p, role:cd-driver, applications, action/argoproj.io/Rollback, proj:platform-prod/*, allow
    g, cd-driver, role:cd-driver
```

> ★ **注意两个要点**：
> ① **只授权到具体 project**（`proj:platform-prod/*`），不要给全量；
> ② **只给 `applications, sync`**（+ 可选的 rollback），
> **不要给 `applications, update`**——那等于让 driver 改 Application 的 spec，
> 会绕过"Git 是唯一真相"。

### 3.3 三个核心调用

```bash
BASE=https://argocd.example.com
TOKEN=<service-account-token>

# ① 查状态（决策前必须查）
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/v1/applications/platform-prod/api-prod" | jq '{
    sync:     .status.sync.status,
    rev:      .status.sync.revision,
    health:   .status.health.status,
    opPhase:  .status.operationState.phase,
    opRev:    .status.operationState.syncResult.revision
  }'

# ② 触发同步（★ revision 一定要指定，否则会同步到"最新"）
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/v1/applications/platform-prod/api-prod/sync?revision=<SHA>&prune=false&dryRun=false"

# ③ 查同步结果（轮询 operationState）
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/v1/applications/platform-prod/api-prod" | jq '.status.operationState.phase'
```

> ⚠️ **不指定 `revision` 是最危险的写法**：Argo CD 会同步到它认为的"当前 revision"，
> 可能与你审批的那个 SHA 不一致。
> ★ **driver 必须永远传显式的 revision**。

---

## 4. 幂等设计

### 4.1 幂等键

```
idempotency key = (application name, application namespace, target revision SHA, prune flag)
```

| 为什么这样选 | 说明 |
|---|---|
| 为什么带 revision | 同一个应用的**不同版本**是**不同的意图**，必须各同步一次 |
| 为什么带 prune | 同一个 revision，"带 prune"和"不带 prune"是**两种不同的操作**（prune 会删资源） |
| 为什么带 app namespace | 同一个名字可能存在于不同 namespace（Application in any namespace 模式） |
| 为什么不带时间戳 | 时间戳会让每次调用都是新键 → 幂等失效 |

> ★ 与既有 [`how-to-atomic-idempotency.md `3 `三层幂等键`](../how-to-atomic-idempotency.md) 一致：
> **业务键（app+rev）→ 操作键（+prune）→ 实例键（+尝试次数）**。

### 4.2 状态机

```
      ┌──────────┐  触发（webhook/巡检）
      │ PENDING  │◀──────────────────────────┐
      └────┬─────┘                           │
           │ 决策：允许？                      │ 巡检（兜底）
      ┌────▼─────┐  否                      │
      │ SKIPPED  │───────────────────────────┤
      └──────────┘                           │
           │ 是                              │
      ┌────▼─────┐  POST /sync              │
      │ SYNCING  │──────────┐                │
      └────┬─────┘          │                │
           │ operationState  │                │
      ┌────▼────────────┐   │                │
      │ SUCCEEDED/FAILED │───┘ 写幂等存储（终态）
      └─────────────────┘
```

| 状态 | 含义 | 幂等键是否已记录 |
|---|---|---|
| PENDING | 已受理，未决策 | ❌ |
| SKIPPED | 决策为"不满足条件" | ❌（**不记录**，条件变了还要能再触发） |
| SYNCING | 已调 API，等结果 | ✅（记录，防止重复触发） |
| SUCCEEDED / FAILED | 终态 | ✅（终态，FAILED 也记录——**否则会无限重试同一个坏版本**） |

> ⚠️ **FAILED 要不要重试？**
> - **应用层失败**（配置错误、准入被拒）→ **不自动重试**，等人改代码（新的 revision 会产生新键）。
> - **瞬时失败**（网络、quota、集群不可达）→ **可重试**，但要**退避 + 上限**。
> → 区分方式：看 `operationState.message` / 失败原因分类；或干脆"失败不重试，靠巡检 + 新提交"。

### 4.3 去重的实现

| 方案 | 说明 |
|---|---|
| **Redis SETNX** | `SETNX idem:<key> 1 EX 86400`，成功返回 false 就跳过。**多副本安全** |
| **数据库唯一索引** | 表 `(app, ns, rev, prune)` 唯一键；插入冲突即跳过。**最可靠** |
| **内存 map** | ❌ 多副本会失效、重启会丢 → **不要用** |

> ★ **巡检兜底**必须能处理"webhook 丢了"的情况：
> 巡检器扫描"Git 最新 revision ≠ Argo CD 已同步 revision 且满足条件"的 Application，主动触发。

---

## 5. 触发源

| 触发源 | 事件 | 优点 | 缺点 |
|---|---|---|---|
| **GitHub push**（webhook → driver） | 代码合并后 | 及时 | 可能**在批准流程之外**（比如直推分支） |
| **GitHub deployment / deployment_status** | 部署对象状态变化 | ★ **语义最贴切**：deployment 就是"要部署了" | 需要先创建 deployment（谁创建？） |
| **CR 平台 webhook** | 变更单被批准 | ★ **批准即触发**，最精确 | 引入第三方依赖 |
| **GitHub repository_dispatch** | 手动触发 | 人工兜底 | 手动 |
| **周期巡检** | 定时 | ★ **兜底必备** | 延迟 |

> ★ **推荐组合**：**CR 平台批准事件（主）+ push（辅）+ 巡检（兜底）**。
> 若 CR 平台不方便提供 webhook，就用 **push + 巡检**，并在 driver 里查 CR 平台状态。

---

## 6. 失败处理

### 6.1 重试策略

| 失败类型 | 处理 |
|---|---|
| GitHub API 调用失败 | 指数退避重试（1s → 2s → 4s，上限 5 次） |
| Argo CD API 返回 "another operation is already in progress" | **不重试**，等当前 operation 结束（轮询 `operationState`） |
| Argo CD API 5xx | 退避重试 |
| 策略评估失败（CR 平台不可达） | ★ **fail-closed**（不触发同步）+ 告警；**不要 fail-open** |
| 同步本身失败（应用层） | 不重试（见 `4.2） |

### 6.2 死信

| 机制 | 说明 |
|---|---|
| **死信队列** | 连续失败 N 次的 (app, rev) 进死信表，人工处理 |
| **告警** | 死信产生时告警到 Slack/邮件（用 Argo CD Notifications 的 webhook service 也能做） |
| **人工重放** | 提供一个 CLI/API：`POST /driver/replay?key=...` |

### 6.3 可观测性（最小集）

| 指标 | 用途 |
|---|---|
| `driver_triggers_total{result}` | 触发了多少次 / 跳过多少 / 失败多少 |
| `driver_sync_duration_seconds` | 从事件到同步完成 |
| `driver_sync_failures_total{reason}` | 失败原因分布 |
| `driver_idempotent_skips_total` | 幂等拦截了多少次（**这个数字高说明 webhook 重复投递多**） |
| `driver_degraded` | 是否处于降级状态（=1 表示自动同步兜底中） |

> ★ **必须有一个"心跳"**：driver 定期自检并写一个 commit status / check run，
> 这样"driver 挂了"这件事本身在 GitHub 上是**可见的**——
> 否则就是"静默不部署"（既有 [`12-webhook-push-vs-pull.md `7`](../git-apps/12-webhook-push-vs-pull.md) 讲的"出站不通 = 门禁静默失效"的镜像问题）。

---

## 7. 降级策略

**必须在写代码之前拍板**（对应 [`18 `9 Q4`](./18-framework-github-first-gitops.md)）：

| 策略 | 行为 | 优点 | 缺点 | 推荐 |
|---|---|---|---|---|
| **D1 停**（fail-stop） | driver 挂 → prod 不再同步 | ★ **安全**：宁停勿乱 | 变更被卡住 | ★ **prod 默认** |
| **D2 退回自动** | driver 挂 → 打开 `automated.enabled` | 可用性高 | ★ **失去"批准后才部署"的保证** | dev 默认 |
| **D3 混合（推荐）** | dev → D2；prod → D1 | 分级 | 要维护两套 | ★ **推荐终态** |

**D3 的实现**：

```yaml
# prod 的 Application：自动同步关闭，只等 driver
spec:
  syncPolicy:
    automated:
      enabled: false
---
# dev 的 Application：自动同步开启，driver 不介入
spec:
  syncPolicy:
    automated:
      enabled: true
```

> ★ **降级必须可观测**：driver 挂掉时，
> 要在 GitHub 上留下"我挂了，prod 已停止同步"的信号（心跳 check 失败 / 告警 / commit status）。

---

## 8. 与 CR Check 的关系

| 方案 | 做法 | 评价 |
|---|---|---|
| **R1 新写一个 driver 服务** | 独立 Go 服务 | 代码重复（webhook、GitHub 客户端、验签、队列都要重写） |
| **R2 ★ 在 CR Check 里加一个"通知 driver"模块** | CR Check 已经有：webhook 端点、GitHub 客户端、验签、队列、规则引擎、审计 sink | ★ **推荐**：只加"决策 + 调 Argo CD API"两块 |
| **R3 把 driver 放进 Argo CD 的 hook（PreSync）** | 让 Argo CD 自己调 CR 平台 | ★ 值得考虑：少一个服务，但"批准后才部署"的语义要靠 hook 表达 |

> ★ **推荐 R2**：既有 [`cr-check/`](../git-apps/cr-check/) 已经具备
> webhook / 验签 / 规则引擎 / check writer / 指标 / 审计 sink，
> **再加一个出向调用（调 Argo CD API）成本最低**。
>
> ⚠️ 但要注意**职责边界**：CR Check 是"判官"，
> 如果它同时是"执行触发者"，就出现"自己批准自己执行"的问题。
> → 缓解：**决策逻辑仍在 CR 平台**（CR Check 只是查询 + 转发），
> 且 **Argo CD 的同步窗口**作为第二道独立防线。

---

## 9. 坑清单

| # | 坑 | 后果 | 规避 |
|---|---|---|---|
| 1 | 调 sync API **不传 revision** | 同步了没审批的版本 | 永远传显式 revision |
| 2 | driver 权限给 `applications, update` | driver 能改 Application spec，绕过 Git | 只给 `sync` |
| 3 | 幂等状态放内存 | 多副本/重启后失效 → 重复同步 | Redis / DB |
| 4 | FAILED 也无限重试 | 同一个坏版本反复打集群 | 失败即终态，靠新 revision |
| 5 | 策略评估失败时 fail-open | 条件查不到就放行 | **fail-closed** |
| 6 | 没有巡检兜底 | webhook 丢了就永远不同步 | 周期巡检 |
| 7 | 没有心跳 | driver 挂了没人知道 | 心跳 + 告警 |
| 8 | 开了 `automated.enabled: false` 却以为"没变化" | 同步永远不发生 | 见 [`21 `8 坑 1`](./21-sync-windows-and-auto-sync.md) |
| 9 | 同时开自动同步和 driver | **两次同步互相打架** | 二选一，或用 `automated.enabled: false` |
| 10 | driver 与 Argo CD 装在同一个 GKE | ★ **没减轻 M-3** | 要减压就装到集群外 |
| 11 | 用 `dryRun=false` 但没考虑 prune | 误删资源 | prune 默认 false，单独审批 |
| 12 | 没考虑 `syncOverrun` | 窗口结束时同步被腰斩 | 与窗口配置保持一致（见 [`21 `5.3`](./21-sync-windows-and-auto-sync.md)） |

---

## 关联文档

- 上一级：[`18 总体框架`](./18-framework-github-first-gitops.md)
- 同步窗口（driver 必须尊重）：[`21 同步窗口与自动同步`](./21-sync-windows-and-auto-sync.md)
- 无 Actions 的替代：[`19 替代方案矩阵`](./19-no-actions-alternative-matrix.md)
- 幂等与原子性（既有）：[`how-to-atomic-idempotency.md`](../how-to-atomic-idempotency.md)
- API 参考（既有）：[`argocd-api.md`](../../argocd-api.md)
