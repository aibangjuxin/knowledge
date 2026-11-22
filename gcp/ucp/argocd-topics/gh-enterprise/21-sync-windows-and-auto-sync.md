# 21 · 同步窗口与自动同步开关

> **直接回答**：「Argo CD 有一个对应的开关，比如说它默认是 sync on，可能就会手动来。」
>
> **一句话结论**
> ★ 这个"开关"在 Argo CD v3.5.6 里是**两个不同层级的字段**：
> ① **`Application.spec.syncPolicy.automated.enabled`** —— 要不要**自动收敛**（per-Application）
> ② **`AppProject.spec.syncWindows`** —— **什么时候**允许同步（per-AppProject）
> ★ **v3.5.6 没有 Application 级的 syncWindows**（实测 CRD，见 `1）——
> 所以"时间窗"是**项目级共享**的，这是最容易被忽略的结构性约束。

---

## 目录

| 章节 | 内容 |
|---|---|
| [`1](#1-先钉死事实字段在哪) | CRD 实测：字段归属 |
| [`2](#2-自动同步的五个子开关) | `automated.enabled/prune/selfHeal/allowEmpty` + `retry` |
| [`3](#3-自动同步的幂等语义) | 官方定义的 6 条语义（**最容易误解的部分**） |
| [`4](#4-同步窗口全字段) | `syncWindows` 每个字段干什么 |
| [`5](#5-窗口的判定规则) | allow / deny 的优先级 + `manualSync` + `syncOverrun` |
| [`6](#6-实现默认自动偶尔手动) | ★ 三种实现路径 + 选择建议 |
| [`7](#7-项目拆分建议) | 为什么你可能需要多个 AppProject |
| [`8](#8-坑清单) | 12 条坑 |

---

## 1. 先钉死事实：字段在哪

**当前清单事实**（实测本仓库 `install.yaml`，Argo CD v3.5.6）：

| CRD | spec 的**全部**字段 |
|---|---|
| **Application** | `destination` · `ignoreDifferences` · `info` · `project` · `revisionHistoryLimit` · `source` · `sourceHydrator` · `sources` · `syncPolicy` |
| **AppProject** | `clusterResourceBlacklist` · `clusterResourceWhitelist` · `description` · `destinationServiceAccounts` · `destinations` · `namespaceResourceBlacklist` · `namespaceResourceWhitelist` · `orphanedResources` · `permitOnlyProjectScopedClusters` · `roles` · `signatureKeys` · `sourceIntegrity` · `sourceNamespaces` · `sourceRepos` · **`syncWindows`** |

**两个推论**：

1. ★ **`syncWindows` 只在 AppProject 上。** 想给单个 Application 单独设窗口 →
   **必须给它单独建一个 AppProject**（见 `7）。
2. Application 的 `syncPolicy` 里**只有** `automated` / `retry` / `syncOptions` / `managedNamespaceMetadata`，
   没有别的开关。

---

## 2. 自动同步的五个子开关

**官方保证**（上游 `docs/user-guide/auto_sync.md`）：

```yaml
spec:
  syncPolicy:
    automated:
      enabled: true      # ★ 显式开关；null 等同于 true
      prune: true        # 自动删除"Git 里已不存在"的资源
      selfHeal: true     # 集群被改了，自动改回去
      allowEmpty: true   # 允许"零资源"（与 prune 搭配的安全阀）
    retry:
      limit: 5           # 重试次数，-1 = 无限
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
      refresh: true      # 重试时用最新 revision 而不是最初那个
    syncOptions: []      # 见下
```

| 开关 | 官方语义（原文大意） | 什么时候开 | 什么时候别开 |
|---|---|---|---|
| `enabled` | "Enable allows apps to explicitly control automated sync"；设为 **false** 时，即使配了 prune/selfHeal/allowEmpty **也不自动同步** | 显式写出来，让"关"也有明确记录 | — |
| `prune` | "whether to delete resources from the cluster that are not found in the sources anymore"（**默认 false**） | 应用生命周期明确、且删了能重建 | ★ **不可逆资源**（PV、数据库、对象存储桶）绝不能开 |
| `selfHeal` | "revert resources back to their desired state upon modification in the cluster"（**默认 false**） | 期望"Git 是唯一真相" | 集群里有**自动注入**的字段（sidecar 注入的注解、autoscaler 写的 status） |
| `allowEmpty` | "AllowEmpty allows apps have zero live resources" | 与 prune 搭配，防止"删光" | — |
| `retry` | 指数退避重试 | 依赖的资源可能短暂不可用（网络、quota） | 想"失败就停、人工介入"时**不配** |

> ★ **官方原文的重要一句**：
> "Setting the `spec.syncPolicy.automated.enabled` flag to **null** will be treated as if automated sync is enabled."
> → **不写 `automated` ≠ 关闭自动同步**；
> **不写 `automated.enabled: false` 才是关闭**。
> 这就是"想关自动同步却没关掉"的最常见原因。

### 2.1 `syncOptions` 常用值

| 选项 | 作用 | 什么时候用 |
|---|---|---|
| `CreateBeforeDelete` | 先建后删 | 有状态服务滚动更新时避免空窗 |
| `Replace=true` | 用新对象替换旧对象 | 某些资源不支持原地更新 |
| `ServerSideApply=true` | 走 SSA | 字段冲突多、字段所有权复杂时 |
| `RespectIgnoreDifferences=true` | 同步时也忽略 diff | 配了 `ignoreDifferences` 却还是反复 OutOfSync 时 |
| `ApplyOutOfSyncOnly=true` | 只应用 OutOfSync 的资源 | 大应用同步慢时提速 |
| `PruneLast=true` | 先应用后 prune | 避免先删后建造成的空窗 |
| `PrunePropagationPolicy=orphan` | prune 时保留被删资源的子资源 | 有 finalizer 的资源 |

> ★ **联动坑**：`ignoreDifferences` **只影响 diff 显示**，
> 要让同步也忽略，必须同时加 `RespectIgnoreDifferences=true`
> （既有 [`argocd-application-guide.md `11`](../../argocd-application-guide.md) 坑表已记录）。

---

## 3. 自动同步的幂等语义

**官方保证**（上游 `docs/user-guide/auto_sync.md` `Automated Sync Semantics`）——

这一节是**最容易被误解**的部分，逐条翻译：

| 官方语义 | 含义 | 对我们的影响 |
|---|---|---|
| "An automated sync will only be performed if the application is **OutOfSync**" | Synced / 报错状态下**不会**自动同步 | 同步失败后**不会自动重试**（除非配了 `retry`） |
| "will only attempt one synchronization per unique combination of **commit SHA1 and application parameters**" | ★ 同一个 SHA + 同样参数**只同步一次** | ★ **Argo CD 自带幂等**——driver 不需要重复判断"这个 SHA 同步过没有" |
| "If the most recent successful sync in the history was already performed against the same commit-SHA and parameters, a second sync will not be attempted, **unless `selfHeal` flag is set to true**" | 开 selfHeal 后会再同步一次 | selfHeal 是"持续收敛"的开关 |
| "If the `selfHeal` flag is set to true, then the sync will be attempted again after **self-heal timeout** (5 seconds by default)" | selfHeal 最短 5 秒一次 | 高频自愈会持续写集群 |
| "Automatic sync will not reattempt a sync if the previous sync attempt against the same commit-SHA and parameters had **failed**" | ★ **失败的 SHA 不会自动重试** | → 这正是要配 `retry` 的理由 |
| "**Rollback cannot be performed against an application with automated sync enabled**" | ★ **开了自动同步就不能回滚** | 生产上要么关自动同步，要么放弃"一键回滚" |
| "The automatic sync interval is determined by the `timeout.reconciliation` value in the `argocd-cm` ConfigMap, which defaults to **120s with added jitter of 60s**" | 默认 2–3 分钟一轮 | 这就是"减少 GKE 压力"可以下手的地方 |

> ★ **对 CD Driver 的直接影响**：
> 因为 Argo CD **自带**"同 SHA 只同步一次"的幂等，
> driver 的幂等键可以设计得**更简单**——
> 但**不能完全依赖它**：driver 重复调 API 会让 Argo CD 返回 "another operation is already in progress"，
> 所以 driver 仍需要**自己的**去重（见 [`23](./23-cd-driver-and-argocd-api-sync.md)）。

---

## 4. 同步窗口全字段

**官方保证**（上游 `docs/user-guide/sync_windows.md` + CRD 实测）：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform-prod
spec:
  syncWindows:
    - kind: allow                 # allow | deny
      schedule: "0 9 * * *"       # cron
      duration: 8h                # 窗口长度
      timeZone: "Asia/Shanghai"   # 时区（可选，默认 UTC）
      applications: ["*"]         # 按 Application 名
      namespaces: ["prod-*"]      # 按目标 namespace
      clusters: ["prod-*"]         # 按目标集群
      andOperator: false          # false = 多条件 OR；true = AND
      manualSync: true            # 窗口禁止时，是否仍允许"人工点同步"
      syncOverrun: true           # 已在跑的同步是否允许越窗完成
      description: "CR123456 prod 变更窗口"
```

| 字段 | 作用 | 坑 |
|---|---|---|
| `kind` | `allow`（只在这个窗口里能同步）/ `deny`（这个窗口里不能同步） | ★ **deny 覆盖 allow** |
| `schedule` | cron 表达式，**窗口开始**的时刻 | 5 段还是 6 段？官方 CLI 示例里出现过 6 段（`* * * * * *`），**以你们版本实测为准** |
| `duration` | 窗口长度 | — |
| `timeZone` | 时区 | ★ **必须与 CR 平台的窗口时区一致**，否则"批准了但 Argo CD 说不在窗口内" |
| `applications` / `namespaces` / `clusters` | 三个选择器，**支持通配符** | 匹配的是 **Application 名 / 目标 namespace / 目标集群**（`destination.name` 与 `destination.server`） |
| `andOperator` | 默认 **OR**（任一选择器命中即生效）；true 则必须**全部**命中 | ★ 想要"既要在这个集群、又是这个 namespace"必须显式开 AND |
| `manualSync` | 窗口禁止时，**人工点同步**是否放行 | ★ 这就是你要的"有时手动"的开关 |
| `syncOverrun` | 已在运行的同步是否允许**跨窗完成** | 见 `5.3 |
| `description` | 自由文本（官方建议写 ticket 号） | ★ 写上 CR 号，排查时一眼看出是谁批的 |

---

## 5. 窗口的判定规则

### 5.1 官方规则（逐条）

| 情形 | 结果 |
|---|---|
| **没有**任何窗口匹配该 Application | ✅ 允许同步 |
| 有匹配的 `allow` 窗口 | ⏸️ **只有** allow 窗口处于 active 时才允许 |
| 有匹配的 `deny` 窗口 | ❌ deny 窗口 active 时**全部拒绝** |
| allow 与 deny **同时** active | ❌ **deny 覆盖 allow** |

### 5.2 UI 与 CLI 的呈现

**官方**：UI 面板用颜色表示状态 —— **Red: sync denied**、**Orange: manual allowed**、**Green: sync allowed**。

```
Name:               guestbook
Project:            default
SyncWindow:         Sync Denied
Assigned Windows:   deny:0 2 * * *:1h,allow:0 2 3 3 3:1h
Sync Policy:        Automated
```

> ★ **运维价值**：UI 上的**橙色**状态 = "现在同步被窗口挡着，但人点一下就能过"。
> 这就是"默认 sync on，偶尔手动"在 UI 上的**可视形态**。

### 5.3 `syncOverrun`（官方原表）

| 过渡场景 | 结果 |
|---|---|
| 无窗口 → deny（带 overrun） | ✅ 继续（deny 支持 overrun） |
| 无窗口 → deny（不带 overrun） | ❌ **阻断** |
| allow(带 overrun) → deny(带 overrun) | ✅ 继续 |
| allow(带 overrun) → deny(不带 overrun) | ❌ **阻断** |
| allow(不带 overrun) → deny(带 overrun) | ✅ 允许（开始时就是允许的） |
| allow(不带 overrun) → deny(不带 overrun) | ❌ 阻断 |
| allow(带 overrun) → allow 结束 | ✅ 继续 |
| 多个 allow 都带 overrun → 全部结束 | ✅ 继续 |
| 多个 allow，有一个不带 overrun → 全部结束 | ❌ 阻断 |

> ★ 关键规则：**"所有相关的窗口都必须支持 overrun"**才允许越窗完成。
> → **配置时要么全开、要么全关**，混合是最容易出错的写法。

---

## 6. 实现"默认自动，偶尔手动"

### 6.1 三种实现路径

| 路径 | 配置 | 行为 | 适合 |
|---|---|---|---|
| **P1 allow 窗口 + `manualSync: true`** | `automated.enabled: true` + allow 窗口 | 平时自动；窗口外**禁止**（连自动也停）；窗口内人工可过 | ★ **推荐的默认**：既有自动化护栏，又留人工出口 |
| **P2 deny 窗口** | `automated.enabled: true` + deny 窗口 | 平时自动；窗口内**禁止**（除非 `manualSync: true` 才放行人工） | 变更冻结期、大促、审计期 |
| **P3 关自动 + 外部驱动** | `automated.enabled: false` + driver | Argo CD 只报 diff；由 driver 按策略触发 | 需要"批准后才部署"的严格模型（见 [`23](./23-cd-driver-and-argocd-api-sync.md)） |

### 6.2 ★ 完整示例（P1：生产应用）

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform-prod
spec:
  sourceRepos:
    - "https://github.com/<ORG>/gitops-*.git"
  destinations:
    - namespace: "prod-*"
      server: "https://kubernetes.default.svc"
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
  # ★ 每天 09:00–17:00 允许同步；窗口外禁止，但人工点同步仍放行
  syncWindows:
    - kind: allow
      schedule: "0 9 * * *"
      duration: 8h
      timeZone: "Asia/Shanghai"
      applications: ["*"]
      manualSync: true
      syncOverrun: true
      description: "每日生产变更窗口"
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api-prod
spec:
  project: platform-prod          # ★ 必须显式写（否则落到 default）
  source:
    repoURL: "https://github.com/<ORG>/gitops-prod.git"
    targetRevision: main
    path: apps/api
  destination:
    server: "https://kubernetes.default.svc"
    namespace: prod-api
  syncPolicy:
    automated:
      enabled: true
      prune: false               # ★ 生产慎开
      selfHeal: false            # ★ 关掉，减少对集群的持续写
    retry:
      limit: 3
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 5m
```

### 6.3 配置窗口的三种方式

```bash
# ① CLI
argocd proj windows add platform-prod \
  --kind allow --schedule "0 9 * * *" --duration 8h --applications "*" \
  --manual-sync --sync-overrun

argocd proj windows list platform-prod
argocd proj windows enable-manual-sync platform-prod <ID>
argocd proj windows disable-manual-sync platform-prod <ID>
argocd proj windows enable-sync-overrun platform-prod <ID>
argocd proj windows update platform-prod <ID> --namespaces default,kube-system,prod1

# ② UI（Application 页面 → Sync window 面板）

# ③ 声明式（AppProject YAML）—— ★ 推荐：进 Git、进 review
```

> ⚠️ **CLI 改的窗口不会进 Git** → 下次 Argo CD 同步 AppProject 时会被覆盖。
> **窗口必须写在 AppProject 的 YAML 里**（这也是"Git 是唯一真相"的体现）。

### 6.4 选择建议

| 场景 | 推荐 |
|---|---|
| 生产应用，要自动化但受窗口约束 | **P1**（allow + manualSync） |
| 变更冻结期 | **P2**（deny 窗口，临时加） |
| "必须先批准才部署" | **P3** + driver（[`23](./23-cd-driver-and-argocd-api-sync.md)） |
| dev 应用 | 无窗口 + `automated.enabled: true` |

---

## 7. 项目拆分建议

因为 **`syncWindows` 是项目级的**，下面这个需求**必须拆项目**：

> "`api-prod` 只能每天 9–17 点同步，但 `gateway-prod` 需要随时能同步。"

| 方案 | 做法 | 评价 |
|---|---|---|
| **拆成两个 AppProject** | `platform-prod-windowed`（带 allow 窗口）+ `platform-prod-always`（无窗口） | ★ **正确做法**；但要注意 **RBAC 要分别配**（既有 [`04-appproject-rbac`](../04-appproject-rbac.md)） |
| 一个项目 + `applications` 选择器 | 一个窗口只匹配 `api-*` | ★ **可行**（窗口支持按应用名通配）→ **不用拆项目** |
| 一个项目 + 两个窗口 | allow(`api-*`) + allow(`gateway-*`, 无时间限制?) | ✗ **不行**：allow 窗口必须有 schedule |

> ★ **关键洞察**：`syncWindows.applications` 支持通配符，
> 所以**大多数情况下不需要拆 AppProject**——
> 只要不同应用的时间要求能用"**应用名模式**"区分。
> **只有当"同一批应用、不同集群/不同 namespace"的窗口要求不同时**，才需要拆。

---

## 8. 坑清单

| # | 坑 | 后果 | 规避 |
|---|---|---|---|
| 1 | 以为 `automated: {}` 等于关闭 | **自动同步照常跑** | 必须写 `enabled: false` |
| 2 | 在 Application 上找 `syncWindows` | 字段不存在，写了被 API 拒绝 | 窗口只在 AppProject |
| 3 | 不写 `automated` | 默认**开着**自动同步 | 显式写 `enabled: true/false` |
| 4 | deny 与 allow 同时 active，期望 allow 优先 | 被拒 | **deny 覆盖 allow** |
| 5 | `manualSync` 没开，窗口外连人工都点不动 | 紧急变更被卡死 | 关键项目开 `manualSync: true` |
| 6 | `syncOverrun` 有的开有的不开 | 长同步被中途阻断 | **全开或全关** |
| 7 | `timeZone` 与 CR 平台不一致 | "批了但同步不了" | 统一时区；两处都写清楚 |
| 8 | 用 CLI 加窗口 | **不进 Git**，被 Argo CD 覆盖 | 写进 AppProject YAML |
| 9 | `andOperator` 默认是 OR 却按 AND 想 | 窗口命中的范围比想象大 | 需要 AND 时显式开 |
| 10 | 生产开了 `prune: true` | **删掉不可逆资源**（PV、桶、DB） | 生产默认 false |
| 11 | 开了自动同步还想"一键回滚" | 官方明确：**不支持** | 要回滚能力就关自动同步，用 driver |
| 12 | `selfHeal: true` 在有 sidecar 注入的集群上 | 无限循环 diff + 持续写 | 用 `ignoreDifferences` + `RespectIgnoreDifferences` |

---

## 关联文档

- 上一级：[`18 总体框架`](./18-framework-github-first-gitops.md)
- 窗口判定与执行：[`23 CD Driver`](./23-cd-driver-and-argocd-api-sync.md)
- 集群内门禁（另一种"手动"）：[`22 Resource Hooks`](./22-resource-hooks-and-sync-phases.md)
- 既有：[`05-appset.md `6 Progressive Syncs`](../05-appset.md)（渐进式同步）
- 既有：[`argocd-admin-guide.md `5 同步策略与高级同步语义`](../../argocd-admin-guide.md)
