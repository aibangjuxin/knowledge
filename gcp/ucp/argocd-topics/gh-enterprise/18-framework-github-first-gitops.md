# 18 · 总体框架：GitHub-first 的 GitOps 控制面

> **直接回答**：「所有 trigger 都走 GitHub」「不用 Actions」「Argo CD 默认 sync on 但有时手动」
> 「GCP Project 全部由 Argo CD 纳管」—— 这几件事怎么拼成一个**能落地**的整体？
>
> **一句话结论**
> ★ 把它拆成**五层**，每层只回答一个问题：
> **L1 谁改了 → L2 合不合规 → L3 批不批 → L4 谁来执行 → L5 集群允不允许**。
> 层与层之间只通过**状态**（GitHub 上的 check / 环境 / commit）交互，**不直接调用**——
> 这就是「所有 trigger 都走 GitHub」的实现方式：
> **GitHub 是唯一的总线，Argo CD 是执行器，CR Check 是裁判。**

---

## 目录

| 章节 | 内容 |
|---|---|
| [`1](#1-先把约束翻译成硬事实) | 把「需求」翻译成 6 条硬约束 |
| [`2](#2-五层模型) | **五层模型**（本文核心） |
| [`3](#3-三个开关) | **三个开关**：时间 / 自动 / 驱动 |
| [`4](#4-触发矩阵) | **GitHub 事件 → 消费者 → 动作** 全矩阵 |
| [`5](#5-三种同步模式) | 纯自动 / 外部驱动 / 混合 —— 对比与选择 |
| [`6](#6-端到端时序) | 两条端到端时序（自动 / 手动） |
| [`7](#7-权限与信任边界) | 每个身份持有什么权限，为什么 |
| [`8](#8-落地顺序) | M0–M6 里程碑 |
| [`9](#9-待拍板清单) | **需要你拍板的 8 件事** |
| [`10](#10-与既有文档的映射) | 与既有 40+ 篇文档的映射表 |

---

## 1. 先把约束翻译成硬事实

你描述的方向里，藏着 6 条**互相咬合**的硬约束。它们不是需求，是**必须同时成立**的前提。

| # | 你说的 | 翻译成硬事实 | 对应概念 |
|---|---|---|---|
| C1 | 所有 trigger 都走 GitHub | GitHub 上必须有**可被机器读到的状态**（check run / commit status / environment / deployment），否则下游无法"触发" | [`25](./25-github-environments-and-deployment-protection.md) |
| C2 | Actions 可能不让用 | 所有 CI 检查必须**下沉到 GitHub 原生规则**或**上浮到自研 GitHub App**；没有 runner 就没有 workflow | [`19](./19-no-actions-alternative-matrix.md) |
| C3 | CR Check 校验 + Approve | 判定必须**产出 GitHub 上可被 ruleset 引用的一等公民**（required status check 的 context 名） | [`19](./19-no-actions-alternative-matrix.md) · [`11](../git-apps/14-rulesets-and-gitapp-gate.md) |
| C4 | Argo CD 统一纳管 GCP Project | 需要一个**把 GCP 资源变成 K8s CRD 的东西**（Crossplane 已停用 → Config Connector） | [`24](./24-gke-fleet-and-gcp-project-governance.md) |
| C5 | 默认 sync on，但有时手动 | "开关"不是一个，是**三个**：时间窗 / 自动 / 驱动 | [`21](./21-sync-windows-and-auto-sync.md) |
| C6 | 减少 GKE 压力，用 CD pipeline 做同步 | 需要一个**外部驱动者**（driver）用 API 按下同步按钮，且必须**幂等 + 可降级** | [`23](./23-cd-driver-and-argocd-api-sync.md) |

> ⚠️ **最容易踩的坑**：C2 和 C3 咬在一起。
> **required status check 必须由某个"能在 GitHub 上写 check"的实体产出。**
> 如果 Actions 被禁，这个实体就只能是**你自己的 GitHub App**（CR Check）。
> 也就是说：**CR Check 不只是"判官"，它同时是整个无 Actions 体系的"CI 运行时"**。
> 这是本轮架构里最重要的一个结论。

---

## 2. 五层模型

```
┌──────────────────────────────────────────────────────────────┐
│ L1 变更产生层  GitHub PR / branch / tag                        │
│    人改代码 → push → 开 PR                                     │
└───────────────┬──────────────────────────────────────────────┘
                │ (push / pull_request 事件)
                ▼
┌──────────────────────────────────────────────────────────────┐
│ L2 门禁判定层  "合不合规"                                     │
│    ① GitHub Ruleset 原生规则（服务端执行，无 runner）          │
│    ② CR Check（自研 GitHub App → check run）                  │
│    ③ Argo CD 侧静态校验（渲染失败 = 同步失败）                │
└───────────────┬──────────────────────────────────────────────┘
                │ (check run / status / mergeable 状态)
                ▼
┌──────────────────────────────────────────────────────────────┐
│ L3 批准层  "批不批"                                            │
│    ① required reviews（人）                                   │
│    ② CR 平台状态（CR 已批准 / 在维护窗口内）                   │
│    ③ GitHub Environment 部署保护（environment required reviewers）│
│    ④ merge queue（批量合并前再验一次）                        │
└───────────────┬──────────────────────────────────────────────┘
                │ (merge 事件 / deployment 事件 / 手动 approve)
                ▼
┌──────────────────────────────────────────────────────────────┐
│ L4 交付执行层  "谁来执行"                                       │
│    ① GitHub webhook → Argo CD /api/webhook（刷新，不执行）      │
│    ② CD Driver（自研）→ Argo CD API（执行同步）                │
│    ③ Argo CD 自动收敛（automated.enabled）                    │
│    ④ 同步窗口 / sync wave / hook 决定顺序与放行                │
└───────────────┬──────────────────────────────────────────────┘
                │ (apply 到集群)
                ▼
┌──────────────────────────────────────────────────────────────┐
│ L5 集群准入层  "集群允不允许"                                    │
│    Gatekeeper / GKE Policy Controller / OPA Admission          │
└──────────────────────────────────────────────────────────────┘
```

### 2.1 每一层的"职责边界"

| 层 | 只负责 | **明确不负责** | 失败时的表现 |
|---|---|---|---|
| L1 变更产生 | 产生一个**可被追溯到人**的变更 | 不判断合规 | 没有 PR 就没东西可判 |
| L2 门禁判定 | 判定**规则**层面的合规 | 不批准、不部署 | check 失败 → merge 按钮变灰 |
| L3 批准 | 判定**授权**层面的放行 | 不执行 | 合并被阻止 / 部署被挂起 |
| L4 交付执行 | 把 Git 的**期望**变成集群的**现实** | 不判断合不合规 | Application 停在 OutOfSync / OperationFailed |
| L5 集群准入 | 判定**资源**能否写入集群 | 不管流程 | 同步报 403，Argo CD 显示 degraded |

### 2.2 ★ 为什么必须是"五层"而不是"两层"

**两层方案（GitHub 门禁 + Argo CD 部署）有 3 个结构性缺陷**：

| 缺陷 | 说明 | 五层怎么解 |
|---|---|---|
| **门禁和批准混在一起** | "格式不对"和"没人批"是两种完全不同的拒绝 | L2 判规则、L3 判授权，失败信息可分别定位 |
| **没有"排队"** | 10 个人同时改同一个集群，Argo CD 会并发同步，互相打架 | L3 的 merge queue + L4 的 sync window |
| **执行结果回不去** | 部署失败了，GitHub 上看不到 → 只能人肉去 Argo CD UI 查 | L4 的 Notifications service.github 把结果写回 commit / check / deployment |

---

## 3. 三个开关

> **直接回答**：「Argo CD 有一个对应的开关，比如说它默认是 sync on，可能就会手动来。」

这句话里的"开关"其实**不是一个开关**，而是三个**正交**的维度。
只有把它们组合起来，才能表达"默认自动，但受控地手动"。

| 开关 | 维度 | 载体 | 粒度 | 语义 | 详见 |
|---|---|---|---|---|---|
| **S1 时间开关** | 什么时候 | AppProject.spec.syncWindows | 项目级 | 允许/禁止同步的时间窗 | [`21](./21-sync-windows-and-auto-sync.md) |
| **S2 自动开关** | 要不要自动 | Application.spec.syncPolicy.automated.enabled | 应用级 | Git 与集群不一致时，Argo CD 是否自动收敛 | [`21](./21-sync-windows-and-auto-sync.md) |
| **S3 驱动开关** | 谁来按按钮 | CD Driver 的运行模式 / 策略 | 全局或按应用 | 外部系统是否代替 Argo CD 触发同步 | [`23](./23-cd-driver-and-argocd-api-sync.md) |

### 3.1 组合表（**这张表就是"默认 sync on，偶尔手动"的完整答案**）

| 组合 | S1 时间窗 | S2 自动 | S3 驱动 | 实际行为 | 适用 |
|---|---|---|---|---|---|
| **A 全自动** | 无窗口 | enabled: true | 关 | Git 一变，Argo CD 立刻收敛 | dev / 低风险应用 |
| **B 自动 + 窗口护栏** | allow 窗口 + manualSync | enabled: true | 关 | 平时自动；窗口外禁止同步；窗口内可人工兜底 | **生产应用（推荐默认）** |
| **C 自动 + 禁止窗** | deny 窗口 | enabled: true | 关 | 平时自动；窗口内**连人工也默认禁止**（除非 manualSync: true） | 变更冻结期 |
| **D 全手动（声明式但不自执行）** | 无窗口 | enabled: false | 关 | Argo CD 只报 diff，**不执行**；人点 Sync | 首次试点 / 高危应用 |
| **E 外部驱动** | 无窗口或 allow 窗口 | enabled: false | 开 | 由 CD Driver 在满足条件后调 API 触发同步 | **"减少 GKE 压力"的落点** |
| **F 混合（推荐终态）** | allow 窗口 + manualSync | dev true / prod false | 开（仅 prod） | dev 全自动；prod 由 driver 按策略驱动，窗口内可人工 | ★ 长期目标形态 |

> ★ **推荐 F 的理由**：
> - **dev** 追求快 → automated.enabled: true，CI 挂了立刻能看到 diff；
> - **prod** 追求可控 → 自动收敛关掉，由 driver 在**校验通过 + 批准完成 + 窗口内**三个条件都满足时才调 API；
> - **人工兜底**永远保留 → manualSync: true，driver 挂了、窗口判断错了，人还能在 UI 上点一下。
>
> ⚠️ **S2 是 per-Application 的**，而 **S1 是 per-AppProject 的**（v3.5.6 没有 Application 级 syncWindows，**当前清单事实**）。
> 这意味着：**同一个项目里的应用共享时间窗**。如果一个项目里既有"必须随时可同步"的应用，
> 又有"只能在窗口内同步"的应用，**必须拆成两个 AppProject**（见 [`21](./21-sync-windows-and-auto-sync.md) `6）。

---
## 4. 触发矩阵

> **直接回答**：「所有 trigger 都走 GitHub」——具体哪些 GitHub 事件，交给谁，产生什么动作。

### 4.1 事件矩阵（**这是本方案的路由表**）

| GitHub 事件 | 消费者 | 动作 | 需要 Actions？ | 文档 |
|---|---|---|---|---|
| push | Argo CD（/api/webhook） | 刷新匹配的 Application（**不执行同步**） | ❌ | [`20](./20-argocd-webhook-and-notifications.md) |
| push | CR Check | 若该 push 需要 CR 校验 → 触发判定 | ❌ | [`13](../git-apps/13-cr-check-go-design.md) |
| pull_request (opened/synchronize) | CR Check | 跑 R0–R13a 规则 → 写 check run | ❌ | [`13](../git-apps/13-cr-check-go-design.md) |
| pull_request | GitHub Ruleset | 服务端规则判定（命名/评审/线性历史…） | ❌ | [`14](../git-apps/14-rulesets-and-gitapp-gate.md) |
| pull_request (review) | GitHub | 满足 reviewer 数 → 解锁 merge | ❌ | [`14](../git-apps/14-rulesets-and-gitapp-gate.md) |
| deployment / deployment_status | CD Driver | 判定"是否该同步" → 调 Argo CD API | ❌ | [`23](./23-cd-driver-and-argocd-api-sync.md) |
| merge_group | CR Check / 外部校验器 | 在**合并组**上重跑校验并写 check | ⚠️ 见 [`19](./19-no-actions-alternative-matrix.md) `5 | [`25](./25-github-environments-and-deployment-protection.md) |
| check_run / check_suite | 外部系统 | 消费校验结论 | ❌ | — |
| installation / installation_repositories | Argo CD | 凭据自动扩缩（App 装到新仓库） | ❌ | [`07](../07-repository-githubapp.md) |
| repository_dispatch | 任意外部服务 | 手动触发一次流程 | ❌ | [`19](./19-no-actions-alternative-matrix.md) |
| workflow_run | — | **不可用**（Actions 被禁） | — | — |
| workflow_dispatch | — | **不可用** | — | — |

### 4.2 ★ 三条"主干道"与一条"旁路"

```
主干道 ①  变更 ──push──▶ Argo CD /api/webhook ──▶ refresh ──┐
主干道 ②  变更 ──PR───▶ CR Check ──▶ check run ──▶ 批准 ──▶ merge
                                                              │
主干道 ③  merge ──push──▶ /api/webhook ──▶ refresh ──▶ 自动收敛 or Driver 同步
                                                              │
旁路     Argo CD 同步结果 ──Notifications service.github──▶ commit status / check / deployment
```

- **①②③ 必须同时存在**，缺一层就会出现"能合但没部署"或"能部署但没审计"。
- **旁路不是可选的**：它是 C1（所有 trigger 都走 GitHub）的**闭环**——
>   没有旁路，GitHub 上永远看不到"这次到底部署成功没有"。

---

## 5. 三种同步模式

| 维度 | A 纯自动 | E 外部驱动 | F 混合 |
|---|---|---|---|
| 谁触发 apply | Argo CD 内部 controller | CD Driver → Argo CD API | 按环境分 |
| 延迟 | 刷新延迟（webhook 秒级 / 轮询 120s±60s） | driver 处理延迟 + API 往返 | 同左/右 |
| **幂等责任** | Argo CD（按 commit SHA 去重） | **Driver（必须自己设计幂等键）** | 两者都要 |
| 审计 | Git commit + Argo CD operationState | Git commit + driver 日志 + Argo CD operationState | 完整 |
| driver 挂掉 | **无影响**（自动收敛继续） | **全部停止**（除非有降级） | prod 停、dev 继续 |
| 对 GKE 的压力 | 持续轮询 + 持续 diff | 事件驱动，**空闲时零轮询**（可调大 reconciliation） | 按环境 |
| 适合 | dev、低风险 | prod、高频变更、需精确控制的场景 | ★ 推荐 |
| 实现复杂度 | 低 | 中（要写服务、要幂等、要降级） | 中 |

### 5.1 "减少 GKE 压力"的三种可能含义（**先定义，再优化**）

| 可能含义 | 实际是什么 | 对应解法 |
|---|---|---|
| **M-1 Argo CD 轮询开销** | 每个 Application 每 ~2–3 分钟拉一次 Git、做一次 diff | ① 配 /api/webhook（秒级刷新）② 调大 argocd-cm 的 timeout.reconciliation ③ 用 ApplicationSet 减少 Application 数量 |
| **M-2 目标集群 API 压力** | Argo CD 对每个目标集群持续 watch + apply | ① 集群数多 → 用 ApplicationSet 批量但**减少 App 数量** ② 调大 reconciliation ③ 关闭 selfHeal（selfHeal 会持续写回） |
| **M-3 控制面（Argo CD 所在 GKE）的资源压力** | Argo CD 的 CPU/内存被 diff 吃满 | ① driver 移到**集群外**（Cloud Run）② 调大 reconciliation + webhook 驱动 ③ 拆分控制集群 |

> ★ **建议**：在动手前先确认你指的是哪一条。
> **M-1/M-2 用 timeout.reconciliation + webhook 就能解决 80%**；
> **M-3 才需要"CD pipeline 外部化"**这个大动作。
> 把 M-3 当成 M-1 来做，会白花两周。详见 [`23](./23-cd-driver-and-argocd-api-sync.md) `2。

---

## 6. 端到端时序

### 6.1 自动模式（A / B）

```
人            GitHub            CR Check        Argo CD           集群
│ 改代码       │                  │               │                │
├─push───────▶│                  │               │                │
│              ├─push事件───────▶│ (刷新)        │                │
│              │                  │               │                │
├─开PR───────▶│                  │               │                │
│              ├─pull_request───▶│ 跑规则        │                │
│              │◀─check run: ✔───┤               │                │
│              │                  │               │                │
├─approve────▶│ (review)         │               │                │
├─merge──────▶│                  │               │                │
│              ├─push事件────────────────────────────────▶ /api/webhook
│              │                  │               ├─refresh──────▶│
│              │                  │               ├─diff         │
│              │                  │               ├─(自动收敛)────▶│ apply
│              │◀── Notifications service.github ───────────────┤
│              │   commit status: success / deployment: success │
```

### 6.2 外部驱动模式（E / F，prod）

```
人       GitHub      CR Check      CR 平台      Driver        Argo CD       集群
│改代码   │            │             │            │             │             │
├push───▶│            │             │            │             │             │
├PR─────▶│            │             │            │             │             │
│         ├pull_req──▶│            │            │             │             │
│         │◀─check────┤ 查 CR 状态  │            │             │             │
│         │            ├───────────▶│            │             │             │
│         │            │◀─approved──┤            │             │             │
│         │◀─check: ✔─┤ (含窗口判定)            │             │             │
├approve▶│ (review)   │             │            │             │             │
├merge──▶│            │             │            │             │             │
│         ├─push────────────────────────────────────────▶ /api/webhook
│         │            │             │            ├─refresh────────▶│
│         │            │             │            │  (driver 收到 push/merge)
│         │            │             │            ├─查状态: 已批准? 窗口内? revision 未同步?
│         │            │             │            ├─幂等键命中? → 跳过
│         │            │             │            ├─POST /api/v1/applications/{name}/sync
│         │            │             │            │             ├─apply─────▶│
│         │◀──────────── Notifications service.github ────────────┤
```

---

## 7. 权限与信任边界

| 身份 | 持有什么 | 为什么 | 绝不能持有什么 |
|---|---|---|---|
| **人（开发者）** | push / 开 PR / 评论 | 产生变更 | 直接改集群；改 ruleset |
| **人（审批者）** | review approve / environment approve | 授权 | 同上 |
| **CR Check App** | Checks: Write、Pull requests: Read、Metadata: Read | 写 check run | **Contents: Write**（不写代码）、**Administration: Write**（不改 ruleset） |
| **Argo CD（GitHub App）** | Contents: Read（读仓库）、Administration: Read | 拉取 manifests | Checks: Write（不该参与判定） |
| **Argo CD Notifications（GitHub App）** | Commit statuses: Write、Deployments: Write、Checks: Write、PR: Write | **回写执行结果** | Contents: Write |
| **CD Driver** | Argo CD API token（只读 + sync）+ 读 GitHub 状态 | 触发同步 | 改 ruleset、改代码 |
| **Argo CD（对集群）** | 目标集群 SA：只 apply 允许的 kind | 收敛集群 | cluster-admin（生产 AppProject 绝不给） |

> ★ **一条铁律**：**写 check 的**和**执行部署的**必须不是同一个 App。
> 否则"自己给自己发合格证"。CR Check 只判合规，Argo CD 只执行。

---

## 8. 落地顺序

| 里程碑 | 目标 | 关键交付物 | 完成判据 |
|---|---|---|---|
| **M0 能力实测** | 知道你们环境到底支持什么 | ruleset 探针表（已有脚本）、Actions 是否真禁、merge queue 是否可用 | 一张"可用/不可用"表贴进 PR |
| **M1 门禁闭环** | PR 合不合规，机器说了算 | CR Check 上线 + check run 稳定 + ruleset 引用它的 context | 不合规 PR **合不了**（联调验证） |
| **M2 状态回写** | 部署结果看得见 | Notifications service.github + webhook + /api/webhook | commit 上能看到 success/failure |
| **M3 开关落地** | 默认自动 + 受控手动 | syncWindows + automated.enabled + AppProject 拆分 | 窗口外同步被拒（UI 显示 red/orange/green） |
| **M4 驱动落地** | prod 由 driver 驱动 | CD Driver + 幂等 + 降级 | driver 停掉不影响 dev；prod 停止且不误同步 |
| **M5 GCP 纳管** | Project/集群统一管 | Config Connector 或等价方案 + cluster secret 声明化 | 新增一个集群只改 Git |
| **M6 收口** | 可运维 | 审计、告警、巡检、Runbook | 一次完整演练（回滚 + 恢复） |

> ⚠️ **顺序不能颠倒**：M3 依赖 M2（否则窗口拦住了但没人知道为什么），
> M4 依赖 M3（driver 必须知道窗口规则），M5 可与 M4 并行。

---

## 9. 待拍板清单

> **这 8 件事需要你（或架构组）拍板**，每件都给了我的建议。

| # | 问题 | 影响 | 我的建议 |
|---|---|---|---|
| **Q1** | Actions 是**完全禁用**，还是**不许用托管 runner**（可自建）？ | 决定 merge queue / required_workflows 能否用 | 先问清楚。若只禁托管 runner，自建 runner + Actions 仍可用，M2 会简单很多 |
| **Q2** | "Approve" 的**权威来源**是 CR 平台还是 GitHub Environment？ | 决定 CR Check 与 GitHub 的耦合点 | **CR 平台为准**（它是变更单系统），GitHub Environment 只做**二次人工闸** |
| **Q3** | 维护窗口以**谁的时间为准**？时区？ | syncWindows.timeZone 与 CR 平台窗口必须一致 | 全公司统一 **UTC** 存储，展示层转本地时区；CR 平台与 Argo CD 必须同源 |
| **Q4** | driver 挂了，prod 是**停**还是**退回全自动**？ | 降级策略：安全性 vs 可用性 | **分级**：dev 退回全自动；prod 停 + 告警（生产宁停勿乱） |
| **Q5** | GCP Project 的**创建/删除**是否纳入 Argo CD？ | 跨平面治理边界 | **只纳管"配置"（IAM/策略/配额），不纳管"创建/删除"**（见 [`24](./24-gke-fleet-and-gcp-project-governance.md) `2） |
| **Q6** | CR Check 是**复用现有 Go 服务**还是**新写一个**？ | 工作量与耦合 | **复用**（已有 webhook/规则引擎/check writer），只加"通知 driver"这一条出向调用 |
| **Q7** | Argo CD 与 GitHub 之间的**延迟目标**是多少？ | 决定是否必须上 driver | dev < 30s、prod < 5min。达不到 prod 目标才需要 driver |
| **Q8** | 是否要**跨组织/跨 Org 的 GitHub App 安装**？ | Installation 生命周期管理 | 先做**单 Org 全量安装** + 最小权限 App |

---

## 10. 与既有文档的映射

> 让你知道**新文档补的是哪一块**，以及**老文档继续有效的是哪一块**。

| 层 | 新文档 | 既有文档（继续有效） |
|---|---|---|
| L1 变更产生 | — | [`git-apps/11`](../git-apps/11-github-app-concepts.md) |
| L2 门禁判定 | [`19](./19-no-actions-alternative-matrix.md) | [`14`](../git-apps/14-rulesets-and-gitapp-gate.md) · [`15`](../git-apps/15-commit-message-cr-prefix.md) · [`16`](../git-apps/16-ruleset-install-runbook.md) · [`examples/rulesets-enterprise`](../examples/rulesets-enterprise/README.md) |
| L3 批准 | [`25](./25-github-environments-and-deployment-protection.md) | [`11 Part B`](../git-apps/11-github-app-concepts.md) · [`prow-pulls`](../prow-pulls.md) |
| L4 交付执行 | [`20](./20-argocd-webhook-and-notifications.md) · [`21](./21-sync-windows-and-auto-sync.md) · [`22](./22-resource-hooks-and-sync-phases.md) · [`23](./23-cd-driver-and-argocd-api-sync.md) | [`05`](../05-appset.md) · [`app-of-apps`](../app-of-apps.md) · [`08`](../08-implementation-playbook.md) |
| L5 集群准入 | — | [`06`](../06-opa-gatekeeper-impact.md) · [`../../gke/opa-gatekeeper/`](../../../gke/opa-gatekeeper/README.md) |
| 横切（身份/权限） | — | [`03`](../03-dex-ldap-sso.md) · [`04`](../04-appproject-rbac.md) · [`07`](../07-repository-githubapp.md) |
| 横切（工具选型） | — | [`10`](../10-argo-workflows-evaluation.md) · [`argo-event`](../argo-event.md) · [`flux`](../../flux.md) · [`Tekoncd`](../../Tekoncd.md) |

---

## 关联文档

- 本系列索引：[`README.md`](./README.md)
- 全库总览：[`../../SUMMARY.md`](../../SUMMARY.md)
- Argo CD 专题总索引：[`../README.md`](../README.md)
