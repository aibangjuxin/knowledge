# UCP 文档总览（SUMMARY）

> **这份文档回答**：「这个目录里到底有哪些文档？每一篇讲的是什么？我该按什么顺序读？」
>
> **一句话结论**
> ★ 这是一套围绕 **Argo CD × GitHub** 的 **GitOps 控制面**知识库：
> 上游是 **GitHub Enterprise（门禁与审批）**，下游是 **GKE / GCP（执行与治理）**，
> 中间由 **Argo CD** 收敛；**Crossplane 已停用**（历史文档保留为背景）。
> 最新方向（GitHub-first、禁用 Actions、自动/手动可切）集中在
> **[`argocd-topics/gh-enterprise/`](argocd-topics/gh-enterprise/README.md)**。

---

## 目录

| 章节 | 内容 |
|---|---|
| [`1](#1-一分钟版这套文档在做什么) | 一分钟版 |
| [`2](#2-全库地图) | 六个分区 + 各自的定位 |
| [`3](#3-逐篇说明) | **每篇文档的标题与内容解释** |
| [`4](#4-本轮新增与勘误) | 新增 9 篇 + 2 处事实勘误 |
| [`5](#5-三条阅读路线) | 按角色的阅读路径 |
| [`6](#6-术语速查) | 30 个术语的一句话解释 |
| [`7](#7-待验证清单) | 需要在真实环境核对的事项 |

---

## 1. 一分钟版：这套文档在做什么

| 层 | 做什么 | 主要文档 |
|---|---|---|
| **需求与选型** | 为什么做、边界在哪、用什么工具 | `requirement.md` · `next-steps-roadmap.md` · `argocd-topics/00-architecture-no-crossplane.md` · `flux.md` · `Tekoncd.md` |
| **Argo CD 用法** | 怎么装、怎么配、怎么排障 | `argocd-topics/ 00–10` · `argocd-admin-guide.md` · `argocd-application-guide.md` · `argocd-cli-guide.md` · `argocd-api.md` |
| **GitHub 门禁** | 怎么用 Ruleset + GitHub App 卡住不合规的 PR | `argocd-topics/git-apps/` · `argocd-topics/examples/rulesets*/` · `prow-pulls.md` · `sigs.md` |
| **★ 新方向** | GitHub-first、禁 Actions、自动/手动可切 | **`argocd-topics/gh-enterprise/`（18–25）** |
| **可运行资产** | YAML、Go 代码、静态检查脚本 | `argocd-topics/examples/` · `argocd-topics/git-apps/cr-check/` · `examples/` · `scripts/` |
| **历史（已废弃）** | Crossplane 方案的背景记录 | `poc.md` · `poc-minimax.md` · `poc-argocd-*.md` |

---

## 2. 全库地图

```
ucp/
├── README.md                     ← 入口：本目录怎么读
├── SUMMARY.md                    ← ★ 你正在读的这份：全库总览
├── requirement.md                ← 原始需求（跨云统一控制面）
├── next-steps-roadmap.md         ← 知识探索路线图（历史）
│
├── argocd-topics/                ← ★ 当前有效方案
│   ├── 00–10（12 篇）             ← Argo CD 生产化专题
│   ├── argo-concept-sheet.md      ← 概念速查表
│   ├── app-of-apps.md             ← App of Apps 模式
│   ├── appset-helm-Rendering.md   ← AppSet 的 Helm 渲染
│   ├── helm-cross-repository.md   ← 跨仓库渲染原理
│   ├── argo-event.md              ← Argo Events 评估
│   ├── how-to-*.md                ← 操作型 how-to
│   ├── git-apps/                  ← 自研 GitHub App（CR Check）专题 8 篇 + 代码
│   ├── gh-enterprise/             ← ★★ 本轮新增：新方向 8 篇 + 索引
│   └── examples/                  ← 可复制示例 + 静态检查工具箱
│
├── argocd-*.md                   ← Argo CD 参考手册（API/CLI/Application/AppSet）
├── kustomize-concept.md / Kustomize.md   ← Kustomize
├── flux.md / Tekoncd.md / probot.md      ← 横向选型
├── how-to-manual-build-argocd-windows.md ← 本地工具链
├── poc*.md                       ← ★ 历史：Crossplane 方案（仅背景）
├── diagrams/ eli5/               ← 图解（HTML）
├── install.yaml                  ← Argo CD v3.5.6 官方清单（事实来源）
└── scripts/                      ← 验收与 CI 脚本
```

---

## 3. 逐篇说明

> 格式：**文档 → 标题 → 讲什么 → 什么时候读**
> 状态标记：✅ 当前有效 · ⚠️ 历史背景（Crossplane 已停用）

### 3.1 入口与总览

| 文档 | 标题 | 讲什么 | 什么时候读 |
|---|---|---|---|
| [README.md](./README.md) | UCP · 统一控制平面（Argo CD × Crossplane） | 本目录的导航页：怎么读、文档清单、版本基线（Argo CD v3.5.6）、脚本用法 | **每次进来先看这里** |
| [SUMMARY.md](./SUMMARY.md) | UCP 文档总览 | ★ 本文：全库逐篇解释 + 阅读路线 + 术语表 | 想了解"全貌"时 |
| [requirement.md](./requirement.md) | requirement | 原始需求原文：平台方/开发方边界、ownership 表、跨云控制面、推进阶段 | 回顾"为什么做" |
| [next-steps-roadmap.md](./next-steps-roadmap.md) | UCP · 下一步知识探索路线图 | 当时的缺口清单与两周日历（**已被本轮 gh-enterprise 系列接续**） | 看历史决策脉络 |

### 3.2 Argo CD 生产化专题（`argocd-topics/）✅

| 文档 | 标题 | 讲什么 | 什么时候读 |
|---|---|---|---|
| [00-architecture-no-crossplane.md](./argocd-topics/00-architecture-no-crossplane.md) | 00 · 总体架构与决策记录 | 为什么拒绝 Crossplane、目标架构、组件清单、部署前必查项、风险清单 | 架构评审、答疑"为什么不用 Crossplane" |
| [01-redis-persistence.md](./argocd-topics/01-redis-persistence.md) | 01 · Redis 与持久化 | **三种 Redis 是三件事**（内部缓存 / HA / 业务），各自要不要持久化；GKE PVC 方案 | 有人问"Redis 要不要加盘" |
| [02-ha.md](./argocd-topics/02-ha.md) | 02 · 高可用架构 | 副本数、**三条硬约束**（API_SERVER_REPLICAS 必须匹配、dex 1 副本、sentinel 固定 3）、故障域 | 规划生产部署 |
| [03-dex-ldap-sso.md](./argocd-topics/03-dex-ldap-sso.md) | 03 · SSO 身份打通 | OIDC 直连 / Dex+OIDC / Dex+LDAP 三种模式；组怎么进 token、组怎么映射角色、怎么安全禁用 admin | 接入 SSO、排查"登录了但没权限" |
| [04-appproject-rbac.md](./argocd-topics/04-appproject-rbac.md) | 04 · AppProject 与权限模型 | **三层权限**：Argo CD RBAC × AppProject × K8s RBAC；policy.csv 语法与陷阱 | 设计权限边界 |
| [05-appset.md](./argocd-topics/05-appset.md) | 05 · ApplicationSet 批量分发 | 五种 generator 的输入输出、goTemplate 要点、**template.spec.project 必须显式写**、渐进式同步 | 批量铺开应用 |
| [06-opa-gatekeeper-impact.md](./argocd-topics/06-opa-gatekeeper-impact.md) | 06 · OPA 与 Gatekeeper 的影响面 | **三层 OPA 语义**（同步前检查 / 外部引擎 / 准入 webhook）、CR health check 配置 | 接入准入控制 |
| [07-repository-githubapp.md](./argocd-topics/07-repository-githubapp.md) | 07 · Repository 凭据、GitHub App 与目标分支 | "为什么分支不能改"（分支属于 Application 而非 Repository）、GitHub App 三要素、凭据轮换 | 配仓库凭据 |
| [08-implementation-playbook.md](./argocd-topics/08-implementation-playbook.md) | 08 · 实施顺序与验收手册 | 9 个阶段，每阶段：前置条件 → 命令 → 验收标准 → 回滚 | ★ **动手落地时按它走** |
| [09-troubleshooting.md](./argocd-topics/09-troubleshooting.md) | 09 · 排障手册 | 按**现象**索引的 10 类问题 | 出问题时第一本翻它 |
| [10-argo-workflows-evaluation.md](./argocd-topics/10-argo-workflows-evaluation.md) | 10 · Argo Workflows 概念梳理与引入评估 | 对象模型、执行模型、局限性、**结论：不引入** | 有人提议"用 Workflows 做发布"时 |
| [argo-concept-sheet.md](./argocd-topics/argo-concept-sheet.md) | Argo CD 概念速查表 | 一页看懂 11 个核心概念、三者关系图、身份链路、bootstrap 目录 | ★ **第一次看这套文档** |
| [app-of-apps.md](./argocd-topics/app-of-apps.md) | App of Apps 模式 | 父子 Application 两层同步、打破"先有鸡还是先有蛋"、真实案例与踩坑 | 需要"一次铺开整套应用"时 |
| [appset-helm-Rendering.md](./argocd-topics/appset-helm-Rendering.md) | 06 · ApplicationSet 的 Helm 渲染 | 三层模板引擎边界、**转义写法**、CP→Tenant 仓库拓扑 | AppSet 用 Helm 渲染时 |
| [helm-cross-repository.md](./argocd-topics/helm-cross-repository.md) | 07 · 跨仓库渲染的原理 | "跨仓库不是 Helm 的能力"；**凭据模型**（按 URL 匹配、project 优先）；broker 心智模型 | 多仓库 GitOps 拓扑 |
| [argo-event.md](./argocd-topics/argo-event.md) | Argo Events 是什么 | EventBus/EventSource/Sensor/Trigger；**结论：本期不引入** | 有人提议"用事件总线"时 |

### 3.3 GitHub 门禁专题（`argocd-topics/git-apps/）✅

| 文档 | 标题 | 讲什么 | 什么时候读 |
|---|---|---|---|
| [git-apps/README.md](./argocd-topics/git-apps/README.md) | git-apps/ · 自研 GitHub App（CR Check）专题 | 8 篇的阅读顺序、核心链路一图、代码在哪 | 进入这个专题的入口 |
| [11-github-app-concepts.md](./argocd-topics/git-apps/11-github-app-concepts.md) | 11 · GitHub App 概念梳理 ＋ 生产变更加闸 | Part A：GitHub App 到底是什么、四个 URL 的关系；Part B：把"必须有变更单"拆成 R0–R12 规则 + 三层门禁；Part C：Workflows 能不能干这事 | ★ **理解 GitHub App 与门禁设计的核心** |
| [12-webhook-push-vs-pull.md](./argocd-topics/git-apps/12-webhook-push-vs-pull.md) | 12 · 从「拉」到「推」 | pull vs push 的量化对比、**push 模式的六个新契约**（幂等/乱序/超时/不重试/暴露面/配额）、扇出拓扑 | 写 webhook 服务之前 |
| [13-cr-check-go-design.md](./argocd-topics/git-apps/13-cr-check-go-design.md) | 13 · CR Check（Go）的设计与实现评估 | 需求边界、架构、包结构、**Go 接口定义**、规则引擎、端点契约、**M0–M5 ≈ 17–25 人日** | 要写这个服务时 |
| [14-rulesets-and-gitapp-gate.md](./argocd-topics/git-apps/14-rulesets-and-gitapp-gate.md) | 14 · Rulesets × GitHub App：合并门禁怎么落地 | Ruleset 零基础、25 条规则、**唯一耦合点 integration_id**、4 种静默失效、Merge Queue、18 条坑 | ★ **配置合并门禁的主文档** |
| [15-commit-message-cr-prefix.md](./argocd-topics/git-apps/15-commit-message-cr-prefix.md) | 15 · commit message 必须以 CR123456 开头 | 三层判定模型（L1 hook/L2 Ruleset/L3 App）、RE2 正则、**squash merge 到底校验谁**、本地模拟器 | 实现 commit 格式门禁 |
| [16-ruleset-install-runbook.md](./argocd-topics/git-apps/16-ruleset-install-runbook.md) | 16 · Ruleset 安装与生效 Runbook | 组织级 vs 仓库级、**安装六步顺序**、★ **实测诊断"规则装上了却不拦"**、三层验证 | ★ **下发 ruleset 时照着做** |
| [17-probot-apps.md](./argocd-topics/git-apps/17-probot-apps.md) | 11 · Probot 是什么 | Probot 是写 App 的 Node 脚手架；GitHub App vs PAT vs Actions 选型；Probot vs 我们的 Go 版 | 有人提议"用 Probot 更快"时 |
| [Develop-git-apps.md](./argocd-topics/git-apps/Develop-git-apps.md) | Develop-git-apps · 自研 GitHub App | 可行性评估（自研 vs Actions vs 纯配置）、**R0–R13a 规则表**、24 条工程坑、**M0–M7 路线图** | ★ **立项评估** |
| [webhook-and-backend-service.md](./argocd-topics/git-apps/webhook-and-backend-service.md) | Webhook 与后端服务 | Webhook 是什么、它和你的服务什么关系、**Git → 生效的完整 8 步**、K8s 清单、故障速查 | 部署 webhook 服务 |
| [cr-check/README.md](./argocd-topics/git-apps/cr-check/README.md) | CR Check · Go 实现 | ★ **可运行的代码**：30 秒跑起来、目录结构、端点、本地验证手册 | ★ **先跑起来再读设计** |
| [how-to-atomic-idempotency.md](./argocd-topics/how-to-atomic-idempotency.md) | 开发 GitHub App 时的原子性与幂等性 | 幂等键三层、TOCTOU 竞态与三种修法、Outbox 模式、**怎么证明真的幂等** | ★ **写 driver / 改判定时必读** |
| [how-to-using-git-apps.md](./argocd-topics/how-to-using-git-apps.md) | 装好 GitHub App 之后仓库怎么用它 | App 装好后事件怎么流、**实测发现 cr-check 是 private App**、仓库要做的 4 件事 | 装完 App 之后 |
| [install-git-apps.md](./argocd-topics/install-git-apps.md) | 在 Org / 仓库上安装 GitHub App | 三种装法、**五条 UI 路径**、为什么不能按分支装、对 Argo CD 的影响 | 安装 App |
| [prow-pulls.md](./argocd-topics/prow-pulls.md) | 从 Prow 的 PR 管理机制看门禁设计 | **值得抄的 13 个设计**（do-not-merge 命名空间、结论绑定 tree hash、信任门与合并门分离…）+ 值得警惕的地方 | 设计自己的门禁时借鉴 |
| [sigs.md](./argocd-topics/sigs.md) | Kubernetes SIGs 生态地图 | 210 个仓库的生态地图、**值得借鉴的 8 个设计**（字段所有权模型、cli-utils inventory…） | 找设计范式时 |

### 3.4 ★ 本轮新增：GitHub Enterprise 深度定制（`argocd-topics/gh-enterprise/）✅

| 文档 | 标题 | 讲什么 | 什么时候读 |
|---|---|---|---|
| [gh-enterprise/README.md](./argocd-topics/gh-enterprise/README.md) | Argo CD × GitHub Enterprise 深度定制专题 | 本系列索引、阅读顺序、**关键事实速查** | 入口 |
| [18-framework-github-first-gitops.md](./argocd-topics/gh-enterprise/18-framework-github-first-gitops.md) | 18 · 总体框架：GitHub-first 的 GitOps 控制面 | ★ **五层模型**（变更/门禁/批准/交付/准入）、**三个开关**、**GitHub 事件→消费者→动作 全矩阵**、三种同步模式对比、M0–M6 里程碑、**8 个待拍板问题** | ★★ **先读这篇** |
| [19-no-actions-alternative-matrix.md](./argocd-topics/gh-enterprise/19-no-actions-alternative-matrix.md) | 19 · 不用 GitHub Actions 的替代方案 | 先分清"禁"还是"限"；**四类去处**（Ruleset 原生 / App check / Argo CD 侧 / 外部 CI）；**逐条替代矩阵**；**真正消失的两个能力**（required_workflows、merge_group CI） | ★★ **Action 被禁时必读** |
| [20-argocd-webhook-and-notifications.md](./argocd-topics/gh-enterprise/20-argocd-webhook-and-notifications.md) | 20 · Argo CD 内置 Webhook 与 Notifications | ★ **勘误：v3.5.6 只有 /api/webhook**；webhook 只 refresh 不 apply；Notifications 四件套；★ **service.github 把结果写回 GitHub**（commit status/check/deployment/PR 评论） | ★★ **配 webhook 与通知时** |
| [21-sync-windows-and-auto-sync.md](./argocd-topics/gh-enterprise/21-sync-windows-and-auto-sync.md) | 21 · 同步窗口与自动同步开关 | ★ **CRD 实测：syncWindows 只在 AppProject**；自动同步 5 个子开关；**官方幂等语义 6 条**；窗口判定规则（deny 覆盖 allow）；**三种实现"默认自动偶尔手动"的路径** | ★★ **实现那个"开关"时** |
| [22-resource-hooks-and-sync-phases.md](./argocd-topics/gh-enterprise/22-resource-hooks-and-sync-phases.md) | 22 · Resource Hooks 与同步阶段 | 四个阶段（PreSync/Sync/SyncFail/PostSync）、wave 排序、**PreSync 作为集群内门禁**、两种门禁的取舍矩阵 | 需要在集群侧卡一道时 |
| [23-cd-driver-and-argocd-api-sync.md](./argocd-topics/gh-enterprise/23-cd-driver-and-argocd-api-sync.md) | 23 · CD Driver：用 Argo CD API 驱动同步 | ★ **先确认真的需要 driver**（三种"压力"）；driver 架构；Argo CD API 认证与调用；**幂等键设计**；重试/死信/可观测；**降级策略（挂了怎么办）** | ★★ **要写 CD pipeline 时** |
| [24-gke-fleet-and-gcp-project-governance.md](./argocd-topics/gh-enterprise/24-gke-fleet-and-gcp-project-governance.md) | 24 · GKE 集群纳管与 GCP Project 治理 | 治理边界表；**Config Connector 事实与可用 CRD**；★ **Project 删除风险与五条护栏**；cluster secret 与 skip-reconcile；Workload Identity | ★★ **纳管 GCP 时** |
| [25-github-environments-and-deployment-protection.md](./argocd-topics/gh-enterprise/25-github-environments-and-deployment-protection.md) | 25 · GitHub Environments 与部署保护 | 三个 environment 别混；四种保护；deployment 对象事实；**与 Notifications 联动**；required_deployments 规则；merge queue 机制；审批链分层 | ★★ **把 Approve 放对位置时** |

### 3.5 Argo CD 参考手册 ✅

| 文档 | 标题 | 讲什么 | 什么时候读 |
|---|---|---|---|
| [argocd-admin-guide.md](./argocd-admin-guide.md) | Argo CD 进阶用法与管理员手册 | 全景能力地图、RBAC、AppProject、同步语义、跨集群、通知、**分阶段实施表** | ★ **最全的一本，管理员必读** |
| [argocd-application-guide.md](./argocd-application-guide.md) | Application 资源详解 | 字段逐个解释、9 个示例、四种创建方式、**坑位速查表** | 写/改 Application 时 |
| [argocd-applicationset-vs-application.md](./argocd-applicationset-vs-application.md) | ApplicationSet vs Application | 定位、生命周期、**删除风险**、何时用哪个 | 选型时 |
| [argocd-cli-guide.md](./argocd-cli-guide.md) | Argo CD CLI 实战手册 | 版本对齐、连接与认证、常用命令 | 日常操作 |
| [argocd-api.md](./argocd-api.md) | Argo CD v3.5.6 API 接口参考 | REST/gRPC 全量清单、请求体、调用示例 | 要写自动化脚本时 |
| [argo-api-claude.md](./argo-api-claude.md) | Argo CD v3.5.6 API 接口清单 | 上一份的另一版整理（**内容高度重叠**） | 备用 |
| [Kustomize.md](./Kustomize.md) | Kustomize × Argo CD | Kustomize 解决什么、Argo CD 四层集成、**10 个常见坑** | 用 Kustomize 时 |
| [kustomize-concept.md](./kustomize-concept.md) | Kustomize 入门手册 | 概念、base/overlay、学习路线 | ★ **Kustomize 新手先读这篇** |
| [how-to-manual-build-argocd-windows.md](./how-to-manual-build-argocd-windows.md) | 在 Windows 上安装 Argo CD CLI | go install 为何必然失败、下载二进制、Scoop、源码编译、Pod 内 CLI | Windows 开发机 |
| [flux.md](./flux.md) | Argo CD vs Flux | 逐维度对比、**Flux 有而 Argo CD 没有的 3 件事**、迁移成本 | 有人提议换 Flux 时 |
| [Tekoncd.md](./Tekoncd.md) | Tekton（tektoncd）是什么 | 组成、定位、典型场景 | 有人提议用 Tekton 时 |
| [probot.md](./probot.md) | Probot 是什么 | Probot 核心模型、生态、**Go vs Probot 逐项对比** | 选型参考 |

### 3.6 示例、脚本与图解 ✅

| 文档 / 目录 | 标题 | 讲什么 | 什么时候读 |
|---|---|---|---|
| [argocd-topics/examples/README.md](./argocd-topics/examples/README.md) | examples/ · 可复制示例 ＋ 静态检查工具箱 | **七个静态检查工具**（YAML 语法、AppSet 模拟、渲染检查、集群清单校验、文档链接检查…）+ 脚手架 | ★ **提交前跑一遍** |
| [examples/gitops-layout/README.md](./argocd-topics/examples/gitops-layout/README.md) | Argo CD · GitOps 仓库骨架示例 | **完整仓库骨架**（bootstrap/ + apps/ + 集群清单）+ 一键 demo | 搭自己的 GitOps 仓库时 |
| [.../bootstrap/README.md](./argocd-topics/examples/gitops-layout/bootstrap/README.md) | bootstrap/ · 引导层 | 引导层做哪三件事、每个文件的作用、**改 bootstrap 的规矩** | 理解自举 |
| [.../bootstrap/clusters/README.md](./argocd-topics/examples/gitops-layout/bootstrap/clusters/README.md) | bootstrap/clusters/ · 集群清单 | 集群清单放什么、不放什么、6 个必填字段、三层 overlay | 加新集群 |
| [.../bootstrap-flow.md](./argocd-topics/examples/gitops-layout/bootstrap-flow.md) | Argo CD · Bootstrap 完整流程图 | **七阶段 mermaid 流程图**（PR 门禁 → 点火 → 自举 → 生成 → 同步 → 巡查） | ★ **理解全链路** |
| [.../examples/appset-helm/README.md](./argocd-topics/examples/appset-helm/README.md) | 示例：ApplicationSet 由 Helm 渲染 | 三条命令走一遍 + 这套样例表达的三个结论 | 配合 appset-helm-Rendering |
| [examples/argocd-application/README.md](./examples/argocd-application/README.md) | Application 示例集 | 9 个可直接改造的 Application/AppSet YAML + 改写红线 | 抄 YAML |
| [examples/rulesets/README.md](./argocd-topics/examples/rulesets/README.md) | examples/rulesets/ | Ruleset 配置 + **契约静态检查**（C1/C2/C3 断言）+ 下发与回滚 | 用仓库级 ruleset |
| [.../rulesets/06-dev-branch-guard-x-cr-prefix-action.md](./argocd-topics/examples/rulesets/06-dev-branch-guard-x-cr-prefix-action.md) | 06 Ruleset × cr-prefix Action 联合工作详解 | 两个文件怎么咬合（context == job name）、**五个已确认的缺口** | ⚠️ **依赖 Actions**；Actions 被禁时参考 [`19`](./argocd-topics/gh-enterprise/19-no-actions-alternative-matrix.md) |
| [.../rulesets/ruleset-action-sample.md](./argocd-topics/examples/rulesets/ruleset-action-sample.md) | Ruleset × Action 全套实验手册 | 四个实验（不合规被拦 / 合规放行 / 标题与 commit 不一致 / base 有 workflow head 没有） | ⚠️ **依赖 Actions** |
| [.../rulesets-enterprise/README.md](./argocd-topics/examples/rulesets-enterprise/README.md) | examples/rulesets-enterprise/ | **企业版组织级治理**：文件清单、60 秒跑起来、**部署六步顺序**、验收 | ★ **企业版主入口** |
| [.../00-enterprise-capabilities.md](./argocd-topics/examples/rulesets-enterprise/00-enterprise-capabilities.md) | 00 · 企业版能力矩阵 | **rule type × 计划**矩阵、★ **先跑探针（实测优先于文档）**、GHES 版本差异 | ★ **动手前先测能力** |
| [.../personal-vs-enterprise.md](./argocd-topics/examples/rulesets-enterprise/personal-vs-enterprise.md) | 个人版 ↔ 企业版 差异对照 | 三种"版"的区别、能力对照、治理模型差异、**决策树** | 评估要不要上企业版 |
| [.../enterprise-rollout.md](./argocd-topics/examples/rulesets-enterprise/enterprise-rollout.md) | 企业版落地 Runbook | 阶段 0 准备 → 阶段 1 实测 → 阶段 2 契约校验 → 阶段 3 灰度 | ★ **照着推企业版** |
| [diagrams/](./diagrams/index.html) | 交互图解 | 三个核心 CRD 关系图、Bootstrap 全链路图 | 给人讲的时候 |
| [eli5/](./eli5/index.html) | 给非工程师看的图解 | 5 张通俗 HTML（Crossplane / GitHub App / 三件朋友 / merge-to-apply / 团队边界） | 对外沟通 |
| [scripts/](./scripts/) | verify-poc.sh · ci-validate.sh | 对活集群的只读验收；对 manifests 的 PR 门禁 | CI 接入 |

### 3.7 历史文档（含 Crossplane，已停用）⚠️

| 文档 | 标题 | 讲什么 | 说明 |
|---|---|---|---|
| [poc.md](./poc.md) | Crossplane 最小 PoC | 一个控制集群管理其他 Project 的 GKE | ⚠️ 仅背景 |
| [poc-minimax.md](./poc-minimax.md) | UCP 统一云平台 — Crossplane PoC 方案 | 总体方案、版本矩阵、RACI、9 步实施 | ⚠️ 仅背景 |
| [poc-argocd-integration.md](./poc-argocd-integration.md) | ArgoCD × Crossplane 集成链路 | 四个控制平面、通信矩阵、字段所有权、prune/selfHeal | ⚠️ 仅背景 |
| [poc-argocd-git-to-apply-trigger.md](./poc-argocd-git-to-apply-trigger.md) | ArgoCD Git → Apply 触发链路 | 三个阶段、谁让 Argo CD 知道 main 变了、渲染与 diff | ✅ **概念仍有效**，但 webhook 路径需按 [`20 `1`](./argocd-topics/gh-enterprise/20-argocd-webhook-and-notifications.md) 勘误 |
| [session-token-usage.md](./argocd-topics/session-token-usage.md) | 会话 Token 用量报告 | 某次会话的 token 消耗分析 | 归档性质 |

---

## 4. 本轮新增与勘误

### 4.1 新增（9 个文件，`argocd-topics/gh-enterprise/`）

| 文件 | 解决什么问题 |
|---|---|
| `README.md` | 新系列索引 + 关键事实速查 |
| `18-framework-github-first-gitops.md` | **整体框架**：五层模型 + 三个开关 + 触发矩阵 |
| `19-no-actions-alternative-matrix.md` | **Actions 被禁**的逐条替代方案 |
| `20-argocd-webhook-and-notifications.md` | webhook 路径勘误 + Notifications 回写 GitHub |
| `21-sync-windows-and-auto-sync.md` | **"开关"的三个字段**：syncWindows / automated.enabled / 驱动 |
| `22-resource-hooks-and-sync-phases.md` | 集群内门禁（PreSync hook） |
| `23-cd-driver-and-argocd-api-sync.md` | **CD pipeline** 的完整设计（幂等、降级、可观测） |
| `24-gke-fleet-and-gcp-project-governance.md` | **GCP Project 纳管**（Config Connector）+ 护栏 |
| `25-github-environments-and-deployment-protection.md` | **Approve 放哪** + merge queue |

### 4.2 勘误（2 处，均已在新文档中标明）

| # | 旧写法 | 正确 | 依据 |
|---|---|---|---|
| **E1** | `/api/webhook/github` | **`/api/webhook`** | upstream v3.5.6 `server/server.go:1263` 只有这一个路由；官方 `docs/operator-manual/webhook.md` 同 |
| **E2** | 以为 `syncWindows` 可以写在 Application 上 | **只在 `AppProject` 上** | 实测本仓库 `install.yaml` 的 Application CRD spec 字段清单 |

> ⚠️ 既有多处文档仍写着 `/api/webhook/github`（`argocd-admin-guide.md`、`argocd-application-guide.md`、
> `poc-argocd-git-to-apply-trigger.md`、`git-apps/12`、`git-apps/webhook-and-backend-service.md`）。
> **本轮未批量改写历史文档**（避免破坏既有锚点与 diff），
> 请以 [`20 `1`](./argocd-topics/gh-enterprise/20-argocd-webhook-and-notifications.md) 为准，
> 部署前用 `curl` 探一下两个路径。

### 4.3 本轮核对过的外部事实（可复核）

| 事实 | 来源 | 快照时间 |
|---|---|---|
| Argo CD v3.5.6 的 webhook 路由只有 `/api/webhook` | upstream `server/server.go:1263` | 2026-11-22 |
| Application CRD 无 `syncWindows`；AppProject 有 | 本仓库 `install.yaml` 实测 | 2026-11-22 |
| Notifications catalog 的 8 个 trigger | upstream `notifications_catalog/install.yaml` | 2026-11-22 |
| `service.github` 支持 commit status / check run / deployment / PR 评论 | upstream `docs/operator-manual/notifications/services/github.md` | 2026-11-22 |
| 官方 sync window 判定规则与 `syncOverrun` 转换表 | upstream `docs/user-guide/sync_windows.md` | 2026-11-22 |
| 官方自动同步幂等语义 6 条 | upstream `docs/user-guide/auto_sync.md` | 2026-11-22 |
| merge queue 的临时分支前缀 `gh-readonly-queue/{base}` 与各项设置 | github/docs `managing-a-merge-queue.md` | 2026-11-22 |
| Config Connector 仓库 `k8s-config-connector`、release `v1.161.0` | GitHub API 实测 | 2026-11-22 |
| CGP 的 `resourcemanager` / `iam` / `billingbudgets` / `serviceusage` 四组 CRD | 仓库 `apis/<group>/v1beta1/` 实测 | 2026-11-22 |

---

## 5. 三条阅读路线

### 路线 A · 第一次系统了解（2–3 小时）

```
argocd-topics/argo-concept-sheet.md
   → argocd-topics/00-architecture-no-crossplane.md
   → argocd-topics/05-appset.md
   → argocd-topics/examples/gitops-layout/README.md
   → gh-enterprise/18-framework-github-first-gitops.md
```

### 路线 B · 要落地 GitHub-first 门禁（1–2 周）

```
gh-enterprise/18（框架） → 19（无 Actions） → 20（webhook/回写）
   → git-apps/14（Ruleset 咬合） → git-apps/16（安装验收）
   → git-apps/cr-check/README.md（跑起来）
   → gh-enterprise/25（Environments）
```

### 路线 C · 要做生产化交付（2 周）

```
argocd-topics/08（实施手册）
   → 03（SSO） → 04（权限） → 07（凭据）
   → gh-enterprise/21（开关） → 23（driver） → 24（GCP 纳管）
   → argocd-topics/09（排障）
```

---

## 6. 术语速查

| 术语 | 一句话 |
|---|---|
| **Application** | Argo CD 的核心 CRD：一份 Git 期望 + 一个目标集群位置 |
| **ApplicationSet** | 用 generator 批量生成 Application 的控制器 |
| **AppProject** | 权限边界 + 资源白名单 + **同步窗口**的容器 |
| **App of Apps** | 父 Application 管理子 Application 的模式 |
| **bootstrap/** | GitOps 仓库的引导层（自举起点） |
| **Root Application** | 指向 bootstrap 目录的那一个 Application |
| **Repository CR** | Argo CD 里"如何读这个仓库"的凭据对象（**不含分支**） |
| **cluster secret** | Argo CD 里"如何访问这个集群"的凭据对象 |
| **automated.enabled** | 要不要自动收敛（per-Application 的开关） |
| **syncWindows** | 允许/禁止同步的时间窗（per-AppProject 的开关） |
| **manualSync** | 窗口禁止时，人工点同步是否放行 |
| **syncOverrun** | 已在跑的同步能否跨窗完成 |
| **sync wave** | 同一阶段内的执行顺序 |
| **Resource Hook** | 挂在 PreSync/Sync/PostSync/SyncFail 阶段的资源（通常是 Job） |
| **Webhook（Argo CD 侧）** | GitHub push → Argo CD 的刷新通道（**只 refresh，不 apply**） |
| **Notifications** | Argo CD 的通知引擎（trigger / template / subscription / service） |
| **service.github** | 让 Argo CD 把结果写回 GitHub 的通知服务 |
| **Ruleset** | GitHub 服务端的仓库/组织规则（**不需要 runner**） |
| **required_status_checks** | 合并前必须通过的 check（context 名是唯一耦合点） |
| **required_deployments** | 合并前必须成功部署到指定 Environment 的规则 |
| **Environment** | GitHub 的"部署目标"抽象，带审批保护 |
| **deployment** | GitHub 上"某次部署"的记录对象 |
| **merge queue** | 把多个 PR 组队批量合并（临时分支 gh-readonly-queue/*） |
| **merge_group** | 合并组事件；**没有 CI 就没有它** |
| **GitHub App** | 访问 GitHub 的"机器人身份"（App + Installation + Private Key） |
| **check run** | GitHub 上可被 ruleset 引用的检查结果 |
| **CR Check** | 本项目的自研 GitHub App：判定 PR 是否符合变更单要求 |
| **CD Driver** | 外部驱动者：用 Argo CD API 按策略触发同步的服务 |
| **幂等键** | driver 的去重键 = (app, ns, revision, prune) |
| **Config Connector** | Google 官方的 GCP→K8s CRD 控制器（CGP） |
| **Workload Identity** | GCP 的无长期密钥身份联邦机制 |
| **Gatekeeper / Policy Controller** | 集群准入层：决定资源能否写入 |
| **OPA / Conftest** | 策略引擎；Gatekeeper 是它的一种落地形态 |
| **CR（变更单）** | 内部变更管理平台上的工单，是审批的权威来源 |
| **maintenance window** | 维护窗口；必须与 syncWindows 用**同一时区** |

---

## 7. 待验证清单

> 这些是**必须在你们真实环境核对**的事项（新文档里都给了具体命令）：

| # | 事项 | 在哪 |
|---|---|---|
| 1 | Actions 是"完全禁用"还是"禁托管 runner" | [`19 `1`](./argocd-topics/gh-enterprise/19-no-actions-alternative-matrix.md) |
| 2 | 企业版 ruleset 能力实测表 | [`00-enterprise-capabilities`](./argocd-topics/examples/rulesets-enterprise/00-enterprise-capabilities.md) |
| 3 | webhook 路径（`/api/webhook` vs 旧路径） | [`20 `1`](./argocd-topics/gh-enterprise/20-argocd-webhook-and-notifications.md) |
| 4 | GitHub App 能否订阅 `merge_group` | [`19 `5.1`](./argocd-topics/gh-enterprise/19-no-actions-alternative-matrix.md) |
| 5 | 自定义部署保护规则接口与计划要求 | [`25 `2`](./argocd-topics/gh-enterprise/25-github-environments-and-deployment-protection.md) |
| 6 | Config Connector 支持的资源清单与版本 | [`24 `3`](./argocd-topics/gh-enterprise/24-gke-fleet-and-gcp-project-governance.md) |
| 7 | 目标集群 StorageClass、节点池、是否已装 Policy Controller | [`00 `5`](./argocd-topics/00-architecture-no-crossplane.md) |

---

## 关联文档

- 入口：[`README.md`](./README.md)
- Argo CD 专题索引：[`argocd-topics/README.md`](./argocd-topics/README.md)
- 新方向专题：[`argocd-topics/gh-enterprise/README.md`](./argocd-topics/gh-enterprise/README.md)
- 兄弟目录：Gatekeeper [`../gke/opa-gatekeeper/`](../gke/opa-gatekeeper/README.md) · GKE 运维 [`../gke/`](../gke/README.md)
