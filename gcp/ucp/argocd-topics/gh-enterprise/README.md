# gh-enterprise/ · Argo CD × GitHub Enterprise 深度定制专题

> **副标题**：把「所有 trigger 都走 GitHub」「不用 GitHub Actions」「Argo CD 既能自动也能手动」
> 这三件事，拆成**五层**、**一张触发矩阵**、**一组开关**，然后逐层落地。
>
> **一句话结论**
> ★ 你的方向是对的，但**「Argo CD 有一个开关」这个说法需要拆成三个开关**：
> ① **时间维度** → `AppProject.spec.syncWindows`（允许/禁止同步的时间窗）
> ② **自动维度** → `Application.spec.syncPolicy.automated.enabled`（要不要自动收敛）
> ③ **驱动维度** → 外部 CD driver（谁来按下按钮）
> 只做其中一个，就会出现「要么全自动、要么全手动」的尴尬。三个一起用，才有"默认 sync on，需要时手动"的精确语义。

---

## 目录

| # | 文档 | 直接回答 |
|---|---|---|
| ★ | **[18 · 总体框架](./18-framework-github-first-gitops.md)** | 「整个方案长什么样？五层怎么分工？哪些 trigger 走哪条路？先做什么后做什么？」<br>含：五层模型（变更/门禁/批准/交付/准入）、**GitHub 事件 → 消费者 → 动作** 全矩阵、<br>**三种同步模式对比**（纯自动 / 外部驱动 / 混合）、三个开关的组合表、<br>落地顺序 M0–M6、**与既有 40+ 篇文档的映射表**、待拍板清单 |
| ★ | **[19 · 不用 GitHub Actions 的替代方案](./19-no-actions-alternative-matrix.md)** | 「Actions 不让用，那原来靠 Action 做的检查怎么办？」<br>含：Actions 能力 → 替代实现**逐条矩阵**（Ruleset 原生 / GitHub App check / Argo CD 侧 / 外部系统）、<br>哪些**能力直接消失**（`required_workflows`、`merge_group` 事件触发的 CI）、<br>YAML 与 Kustomize 校验怎么搬家、迁移路线 P0–P5 |
| ★ | **[20 · Argo CD 内置 Webhook 与 Notifications](./20-argocd-webhook-and-notifications.md)** | 「GitHub 推了代码，Argo CD 怎么立刻知道？结果怎么回写 GitHub？」<br>含：**`/api/webhook` 完整配置**（含 v3.5.6 勘误）、webhook 只 refresh 不 apply 的真相、<br>Notifications 的 trigger/template/subscription/service 四件套、<br>★ **`service.github` 把同步结果回写 GitHub**（commit status / check run / deployment / PR 评论）、<br>与 CR Check 的职责切分 |
| ★ | **[21 · 同步窗口与自动同步开关](./21-sync-windows-and-auto-sync.md)** | 「默认 sync on，但有时候要手动」怎么实现？<br>含：`syncWindows` 全字段（allow/deny、`manualSync`、`syncOverrun`、`timeZone`、`andOperator`）、<br>判定规则（**deny 覆盖 allow**）、**自动同步的 5 个子开关**与幂等语义、<br>★ **v3.5.6 事实：sync window 只在 AppProject 上，没有 Application 级**、三种"开关"实现路径对比 |
| | [22 · Resource Hooks 与同步阶段](./22-resource-hooks-and-sync-phases.md) | 「能不能把校验放到集群里做，而不是只在 GitHub 上做？」<br>含：四个阶段（PreSync/Sync/SyncFail/PostSync）、sync waves、hook 资源与删除策略、<br>★ **PreSync Hook 作为集群内门禁**、与 GitHub 侧门禁的取舍矩阵 |
| ★ | **[23 · CD Driver：用 API 驱动 Argo CD 同步](./23-cd-driver-and-argocd-api-sync.md)** | 「CD pipeline 怎么替 Argo CD 按下同步按钮？」<br>含：Driver 架构与状态机、Argo CD API 触发同步、**幂等键设计**、<br>RBAC 最小权限、失败重试/死信/**降级策略**（driver 挂了怎么办）、<br>★ **「减少 GKE 压力」到底指什么**（三个可能含义 + 各自解法） |
| | [24 · GKE 集群纳管与 GCP Project 治理](./24-gke-fleet-and-gcp-project-governance.md) | 「所有 GCP Project 都用 Argo CD 管，怎么做？」<br>含：Crossplane 停用后的三条路（Config Connector / Terraform / 手工）、<br>★ **Project 的删除风险与护栏**、集群注册（v3 形态 cluster secret）、<br>Workload Identity、目录结构与 AppSet 生成、风险清单 |
| ★ | **[26 · Makefile × Argo CD](./26-makefile-in-gitops.md)** | 「同事提的 Makefile 能不能用？有什么实用功能？」<br>含：Make ↔ Argo CD 概念对照、**四个集成点**（统一入口 / CMP / Hook / 审批证据）、<br>**15 个 Make 特性在 GitOps 里的用途**、6 条红线、★ **已落地的 gitops-layout/Makefile**（实测通过） |
| ★ | **[27 · 集群纳管的模板生成](./27-cluster-onboarding-and-fleet-templates.md)** | 「Argo CD 当长期 control plane，新集群要生成 YAML，Makefile 能简化吗？」<br>含：现状盘点（**模板生成已存在**）、**4 个增量**（入口 / **fleet 对账** / 批量 / 干跑）、<br>source vs credential 切分、**纳管 vs 生灭的边界**、决策表、★ **已落地并实测的 fleet.py** |
| | [25 · GitHub Environments 与部署保护](./25-github-environments-and-deployment-protection.md) | 「Approve 这一步放在 GitHub 的哪个位置最合适？」<br>含：Environment / required reviewers / wait timer / custom protection rules、<br>★ `required_deployments` ruleset 规则、**merge queue / merge train** 机制与无 Actions 的可行性、<br>审批链设计、API 端点清单、验证命令 |

---

## 阅读顺序

```
① 18（框架）  →  ② 21（三个开关）  →  ③ 19（无 Actions 怎么办）
                                            ↓
                    ④ 20（webhook/通知） → ⑤ 22（hook 门禁） → ⑥ 23（CD driver）
                                            ↓
                    ⑦ 25（GitHub 侧审批）  →  ⑧ 26（Makefile 收口） →  ⑨ 24（GCP/GKE 纳管）
                                                                          ↓
                                                                   27（集群纳管模板生成）
```

- **只想拿结论** → 只读 [18](./18-framework-github-first-gitops.md) 的 `2 五层模型 + `4 触发矩阵 + `9 待拍板清单。
- **要动手** → 18 → 21 → 19 → 20，然后按 `9 的 M0 顺序做。

---

## 与既有文档的关系

本系列**不重复**既有内容，只补三类东西：

| 类型 | 说明 |
|---|---|
| **补概念** | 既有文档只在 API 字段表里出现过、从未解释过的：`syncWindows` / `merge_queue` / deployment protection / Config Connector / Notifications / **Makefile 在 GitOps 里的定位** / **fleet（集群清单）视角与对账** |
| **纠事实** | v3.5.6 的 `/api/webhook`（既有文档写的 `/api/webhook/github` 已不存在）、`syncWindows` 只在 AppProject 上 |
| **接场景** | 把「GitHub-first + 无 Actions + 手动/自动可切」这三件事接成一个**能落地的整体方案** |

既有文档索引见 [`../README.md`](../README.md)；全库总览见 [`../../SUMMARY.md`](../../SUMMARY.md)。

---

## 标注约定

沿用本仓库的四类标注：

| 标注 | 含义 |
|---|---|
| **官方保证** | 已核对上游 `argoproj/argo-cd` **v3.5.6** 源码 / 文档，或 GitHub 官方文档 |
| **当前清单事实** | 从本仓库 `install.yaml`（Argo CD v3.5.6 官方清单）实测提取 |
| **推荐实现** | 本文档给出的方案建议 |
| **部署前验证项** | 因环境/版本差异需自行核对（附核对命令） |

---

## 关键事实速查（本系列）

```yaml
# Argo CD v3.5.6 · Application CRD 的 spec 全部字段（实测 install.yaml）
destination, ignoreDifferences, info, project, revisionHistoryLimit,
source, sourceHydrator, sources, syncPolicy
# ★ 没有 spec.syncWindows —— 同步窗口只在 AppProject 上

# Argo CD v3.5.6 · syncPolicy 的子字段（实测）
automated.{enabled, prune, selfHeal, allowEmpty}
retry.{limit, backoff.{duration, factor, maxDuration}, refresh}
syncOptions[]

# Argo CD v3.5.6 · AppProject CRD 的 spec 全部字段（实测）
clusterResourceBlacklist, clusterResourceWhitelist, description,
destinationServiceAccounts, destinations, namespaceResourceBlacklist,
namespaceResourceWhitelist, orphanedResources, permitOnlyProjectScopedClusters,
roles, signatureKeys, sourceIntegrity, sourceNamespaces, sourceRepos, syncWindows

# Argo CD v3.5.6 · Webhook 路由（实测 server/server.go:1263）
mux.HandleFunc("/api/webhook", acdWebhookHandler.Handler)
# ★ 只有 /api/webhook，没有 /api/webhook/github

# Argo CD v3.5.6 · Notifications 官方 catalog 的 trigger（实测 notifications_catalog/install.yaml）
on-created, on-deleted, on-deployed, on-health-degraded,
on-sync-failed, on-sync-running, on-sync-status-unknown, on-sync-succeeded

# Argo CD v3.5.6 · notifications service.github 支持的回写通道（实测官方文档）
commit status / check run / deployment / pull request comment
```
