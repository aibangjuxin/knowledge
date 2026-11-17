# Argo CD 专题文档

Kubernetes 原生 GitOps 落地指南 —— 从架构选型到生产运维的完整参考。

> **设计前提**
> - 全部方案基于 **Kubernetes 原生 CRD + Operator + GitOps**，**不使用 Crossplane**
> - 权威事实来源是本仓库的 `install.yaml`（Argo CD 官方清单）与上游源码/文档
> - 每个结论标注了来源性质：**官方保证** / **当前清单事实** / **推荐实现** / **部署前验证项**

---

## 阅读顺序

### 第一次看这套文档

```
00 → 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10 → 11
```

### 深入（可选）

```
git-apps/ 8 篇（自研 GitHub App / CR Check 专题）
  → prow-pulls（Prow 怎么设计合并门）
    → sigs（sigs 生态里还有哪些范式值得抄）
```

### 只想解决一个具体问题

| 你的问题 | 看哪篇 |
|---|---|
| 为什么不用 Crossplane？整体架构长什么样？ | [00](./00-architecture-no-crossplane.md) |
| Redis 到底要不要持久化？业务 Redis 怎么改？ | [01](./01-redis-persistence.md) |
| 高可用怎么配？副本数、Redis HA、坑在哪？ | [02](./02-ha.md) |
| OIDC / LDAP 怎么打通 SSO？组怎么进 Token？怎么禁用 admin？ | [03](./03-dex-ldap-sso.md) |
| AppProject 边界、RBAC 角色、K8s ServiceAccount？ | [04](./04-appproject-rbac.md) |
| ApplicationSet 批量分发怎么写？各 generator 边界？ | [05](./05-appset.md) |
| ApplicationSet 和 Application 到底什么关系？ | [对比速查：ApplicationSet vs Application](../argocd-applicationset-vs-application.md) |
| **先搞懂所有核心概念和 `bootstrap/` 目录是干嘛的** | [**argo-concept-sheet.md**](./argo-concept-sheet.md) |
| 用了 OPA/Gatekeeper 会影响 Argo CD 吗？ | [06](./06-opa-gatekeeper-impact.md) |
| GitHub App 凭据怎么配？**想改分支改哪里？** | [07](./07-repository-githubapp.md) |
| 从零到生产的实施顺序和回滚步骤？ | [08](./08-implementation-playbook.md) |
| 出问题了怎么查？ | [09](./09-troubleshooting.md) |
| 要不要引入 Argo Workflows？结论是什么？ | [10](./10-argo-workflows-evaluation.md) |
| **Argo Events 是什么？它和 Workflows / Argo CD 什么关系？我们要不要它？** | [argo-event](./argo-event.md) |
| GitHub App 的 Public Link / Home URL / Webhook URL 是啥关系？源码在哪？ | [11](./git-apps/11-github-app-concepts.md) |
| **PR 合并到生产前必须有变更单（CR）——规则写在哪？GitHub App 能做吗？** | [11](./git-apps/11-github-app-concepts.md) §11–§19 |
| **GitHub Rulesets 零基础 + 和 CR Check 怎么咬合 + 分支保护怎么分层配** | [14](./git-apps/14-rulesets-and-gitapp-gate.md) |
| **commit message 必须以 `CR123456` 开头 —— 最小 Ruleset 示例（可模拟）** | [15](./git-apps/15-commit-message-cr-prefix.md) |
| **JSON 怎么装到 GitHub 上才会生效？（安装 Runbook）** | [16](./git-apps/16-ruleset-install-runbook.md) |
| **我要自己用 Go 写一个 GitHub App 后端，代码怎么跑起来？Webhook URL 和我的服务什么关系？** | [webhook-and-backend-service](./git-apps/webhook-and-backend-service.md) |
| **装了 App / 配了 Webhook 之后，和 GitHub 的交互逻辑到底变了什么？** | [12](./git-apps/12-webhook-push-vs-pull.md) |
| **CR Check（Go）的详细设计：包结构 / 接口 / 端点 / 里程碑 / 工作量** | [13](./git-apps/13-cr-check-go-design.md) |
| **★ GitHub Rulesets 怎么配？怎么和 GitHub App 联合成合并门禁？** | [14](./git-apps/14-rulesets-and-gitapp-gate.md) |
| **★ CR Check 的 Go 代码在哪？怎么本地跑起来验证？** | [cr-check](./git-apps/cr-check/) |
| **Probot 是什么？为什么我们不用它？** | [17](./git-apps/17-probot-apps.md) |
| **Prow 的 PR 门禁怎么设计的？哪些能直接抄到 CR Check？** | [prow-pulls](./prow-pulls.md) |
| **Kubernetes SIGs 生态地图？哪些设计范式值得抄？** | [sigs](./sigs.md) |

---

## 文档清单

### [概念速查表](./argo-concept-sheet.md)

**先看这一篇**，一页看懂 Argo CD 核心对象与本方案的组织关系。

含：11 个核心概念速查表（Application / AppSet / AppProject / Root App /
Dex / OIDC / LDAP / Repository / Cluster Secret / RBAC）、
三者关系图与生命周期、身份链路、本方案拓扑（中央 Argo CD + Root App +
组件 × 集群矩阵）、**`bootstrap/` 目录能放什么**、变更链路、权限归属速查。

---

### [00 · 架构选型：不使用 Crossplane](./00-architecture-no-crossplane.md)

Kubernetes 原生 GitOps 的能力边界、为什么拒绝 Crossplane、
CRD/Operator 的落地方式、方案对比表、被否决方案记录。

**适合**：架构评审、方案选型答疑。

---

### [01 · Redis 与持久化](./01-redis-persistence.md)

**核心澄清**：三种 Redis 是三件不同的事。

| 类型 | 是什么 | 要持久化吗 |
|---|---|---|
| `argocd-redis` | Argo CD 内部缓存 | **不要** —— 官方设计如此 |
| Argo CD HA Redis | 3 master + 3 sentinel + HAProxy | **不要** —— 同上 |
| 业务 Redis | 你的应用通过 YAML 部署在 GKE 上的 | **要** —— 除非确认是纯缓存 |

含：`install.yaml` 事实核对、GKE StorageClass 选择、
StatefulSet + `volumeClaimTemplates` 改造、Memorystore 方案对比。

---

### [02 · 高可用部署](./02-ha.md)

副本数配置、三个必须记住的约束：

1. `ARGOCD_API_SERVER_REPLICAS` 必须 == `argocd-server` 的 `replicas`
2. `dex-server` **必须 1 副本**（内存数据库）
3. 官方 Redis HA 的 sentinel **不支持扩缩容**

含：滚动更新、gRPC 消息上限、登录限流误拒的排障。

---

### [03 · SSO 身份打通（OIDC 直连 / Dex / LDAP）](./03-dex-ldap-sso.md)

**先选模式**（有 OIDC 就别装 Dex），再按四个**相互独立**的动作做：

```
① 打通登录链路（oidc.config / dex.config）
② 组进入 OIDC Token
③ 组映射为 Argo CD 角色（policy.csv）
④ 禁用内置 admin 账号
```

含：**OIDC 直连**完整配置（`oidc.config` 字段全表、groups claim 三条路径、
Okta/Entra/Keycloak/Auth0/Google 差异表、`sub` vs `email` vs `groups` 的主体语义、
PKCE / `refreshTokenThreshold` / device code 登录）、
`dex.config`（LDAP + OIDC）完整配置、组开关的真实语义澄清
（`insecureEnableGroups` / `scopes` 只对 **OIDC connector** 有效）、
`bindPW` 的 `$` 转义陷阱、组名大小写敏感、离职人员权限回收、
**锁死后的 break-glass 恢复路径**。

---

### [04 · AppProject 与 RBAC](./04-appproject-rbac.md)

三层权限模型：

```
Argo CD RBAC（谁能操作 Application）
   × AppProject（能操作哪些资源）
   × K8s RBAC / ServiceAccount（Argo CD 实际写集群的权限）
```

含：内置角色表、`policy.csv` 语法、`proj:<project>:<role>` 格式、
`policy.default` 无法被 deny 收回的陷阱、
项目名 `-` 触发继承的坑、ServiceAccount 最小权限清单。

---

### [05 · ApplicationSet 批量分发](./05-appset.md)

替代「每个环境手工建 Application」。

| Generator | 输入 | 输出 |
|---|---|---|
| `git` | 仓库目录 | `.path.path` / `.path.basename` |
| `clusters` | 已注册集群 | `.name` / `.server` |
| `list` | 静态元素 | 任意键值 |
| `matrix` | 多个生成器 | 笛卡尔积 |
| `merge` | 多个生成器 | 按 `mergeKeys` 合并 |

含：`goTemplate` + `missingkey=error` 的必要性、
**`template.spec.project` 必须显式写**（否则落到 `default` 最宽松项目）、
Merge 生成器的数组结构陷阱、批量改分支的正确入口。

---

### [06 · OPA 与 Gatekeeper 对 Argo CD 的影响面](./06-opa-gatekeeper-impact.md)

三个层次要分清，混为一谈会导致方案选错：

| 层次 | 触发时机 | 失败后果 |
|---|---|---|
| Argo CD 同步前 OPA 检查 | sync 之前 | 拒绝同步，Application 停在 OutOfSync |
| 外部策略引擎 | 独立触发 | 与 Argo CD 无直接关系 |
| Admission Webhook / Gatekeeper | K8s API 写入时 | 拒绝资源写入，同步报 403 |

含：CR 的 health check 配置（否则 `selfHeal` 空转）、
`excludedNamespaces` 排除 `argocd` 自身、
`failurePolicy` 从 `Ignore` 切 `Fail` 的观察期流程。

---

### [07 · Repository 凭据与 GitHub App](./07-repository-githubapp.md)

**直接回答**：「创建了 GitHub App 类型的 Repository 后，为什么没法编辑 Branch？」

**因为分支不是 Repository 的属性。** 它属于 `Application.spec.source.targetRevision`。

含：Repository 对象完整字段表（来自上游 `util/db/repository_secrets.go`）、
GitHub App 三要素（App ID / Installation ID / Private Key）、
声明式管理 Repository Secret、凭据轮换流程、
GitHub App 私钥的正确注入方式。

---

### [08 · 实施顺序与验收手册](./08-implementation-playbook.md)

9 个阶段，每阶段有：前置条件 → 命令 → 验收标准 → 回滚方式。

**两个硬性依赖**：
- 阶段 3（组映射）验证通过 → 才能做阶段 4（禁用 admin），否则会锁死
- 阶段 5（AppProject 边界）→ 才能做阶段 6（批量分发）

---

### [09 · 排障手册](./09-troubleshooting.md)

按**现象**索引，10 个类别：身份 / 同步 / ApplicationSet / 凭据 /
OPA / Diff / 权限 / Redis / HA。

附一键体检脚本 `argocd-health.sh`（见文末 §10）。

---

### [10 · Argo Workflows 概念梳理与引入评估](./10-argo-workflows-evaluation.md)

**核心结论**：**不引入** Argo Workflows 作为我们 API 交付链路的发布执行器。

含：Argo Workflows 的对象模型与 9 种模板类型、执行模型（每 step 一个 Pod）、
组件拓扑、与 Argo CD 的正交关系（声明式收敛 vs 命令式执行）、
特性清单、局限性（controller 不能水平扩展 / v4 引入 DB / CRD 需 server-side apply / 双控制环风险）、
「受治理发布执行器」12 项能力映射表、A/B/C 三个方案、
复评触发条件清单、部署前验证项。

---

### [argo-event · Argo Events 概念说明](./argo-event.md)

**直接回答**：「Argo Events 是个什么东西？它和 Argo Workflows / Argo CD 怎么分工？」

**Argo Events = K8s 原生的"事件总线 + 事件路由"：`EventSource → EventBus → Sensor → EventBus → Trigger`。**

含：四个核心对象拆解（EventBus / EventSource / Sensor / Trigger）、
一条事件的完整旅程、内置 GitHub 事件源与 `schedule` 事件源、
与 Argo Workflows / Argo CD 的三方对照、官方文档的指向、
最小可用 YAML（EventBus + GitHub EventSource + Sensor + HTTP Trigger）、
落到 CR Check 场景的三种接线方式与"**为什么我们不需要它**"、
8 条运维坑、决策表。

**结论：本期不引入。** 它只做"事件路由"，替代不了业务逻辑；
我们只有 1 个事件源 + 1 个消费者，普通 Go 服务更直接。

---

### [11 · GitHub App 概念梳理 ＋ 生产变更加闸](./git-apps/11-github-app-concepts.md)

**分两部分：**

**Part A（§0–§10）概念**

**直接回答**：「GitHub App 的 Public Link / Home URL / Webhook URL 是什么关系？
App 的源代码在哪？Webhook 是不是就是发布的地方？」

**GitHub App 不是"应用"，是"访问 GitHub 的身份（机器人）"。**

含：App / Installation / Private Key 三件套、四个 URL 的职责对照表、
"源码在哪"的三种含义辨析、「源代码管理在 Webhook 里配置」的四层拆解
（Installation → Webhook 订阅 → Repository Secret → Application）、
webhook 在发布链路里的真实位置（只影响延迟，不决定是否同步）、
本仓库两套 webhook 端点（appset:7000 vs server:80/443）的取舍。

**Part B（§11–§19）场景：GKE 生产变更加闸**

**直接回答**：「PR merge 到生产前必须有一个合规的 Change Request，
这套东西在哪实现？GitHub App 能不能做？」

**GitHub App 能实现"卡合并"这一半，但它不是法官也不是狱警。**

含：术语消歧（变更单 / CustomResource / ClusterRole）、
需求拆解成 R0–R12 可编码规则、"在哪里实现"的五位置对比、
**三层门禁架构**（GitHub 合并门 → Argo CD 同步门 → K8s 准入门）、
GitHub App 实现清单（权限/事件/check 命名/幂等/验签）、
变更单用 CRD 实现时的审批子资源与 CEL/Gatekeeper 约束、
校验器部署形态（GKE Ingress vs Cloud Run）与"一个 App 一个 Webhook URL"的解法、
规则与代码的分离（防"改规则绕过门禁"的递归问题）、
11 个常见坑 + 五条绕过路径验收 + M0–M6 分阶段落地。

**Part C（§20–§25）评估：Argo Workflows 能不能干这件事？**

**直接回答**：「这件事是不是也该由 Argo Workflows 干？Workflows 和 GitHub App 怎么配合？」

**Workflows 能顶"审批怎么流转"，顶不了"合不合规"和"卡不卡 merge"。**

含：与 [`10`](./10-argo-workflows-evaluation.md) 结论的区分（发布执行器 vs 审批编排器）、
三种方案对比（CRD+Gatekeeper / CRD+Workflows / Workflows 端到端）、
R0–R12 能力映射、三方接线图与 9 个真实坑（CR 号=Workflow 名、resume 权限=suspend 挂数天、
双控制环、每步一 Pod…）、审批复杂度 L1/L2/L3 分级决策、复评触发条件清单、
以及 doc 10 T6 已命中的标注。

---

### [git-apps/ · 自研 GitHub App（CR Check）专题](./git-apps/README.md)

> **背景**：要在 GKE 上自研一个 Go 写的 GitHub App（**CR Check**），
> 对“PR 是否有合规变更单（CR）”做门禁：PR 必须携带 CR 号，
> CR 在内部 CR 管理平台上处于**可执行（implement/approved）状态**，
> 且合并必须落在 **Maintenance Window** 内。
>
> **本目录 8 篇文档按这个顺序读：**

| # | 文档 | 直接回答 |
|---|---|---|
| 1 | [`Develop-git-apps.md`](./git-apps/Develop-git-apps.md) | “要不要自研？自研要写多少代码？时间窗口难在哪？”<br>含：可行性评估（自研 vs Actions vs 纯配置）、R0–R13a 规则表、需求「6.1 合并门禁流程」八步映射、Go 技术栈与目录结构、24 条工程坑、实施路线图 M0–M7 |
| 2 | [`webhook-and-backend-service.md`](./git-apps/webhook-and-backend-service.md) | “Webhook 到底是什么？我写的 Go 服务怎么变成一个 GitHub 能访问到的 URL？”<br>含：一页纸总结 + 完整流程图、Webhook vs 后端服务、**Git → 生效的完整 8 步**、K8s 清单、配置清单、故障速查、本地调试 |
| 3 | [`12-webhook-push-vs-pull.md`](./git-apps/12-webhook-push-vs-pull.md) | “有了 Webhook 之后，和 GitHub 的交互逻辑到底变了什么？”<br>含：pull vs push 量化对比、**push 模式下的六个新契约**（幂等/乱序/10s 超时/不自动重试/暴露面/配额）、扇出拓扑、迁移路线 P0–P5、反模式清单 |
| 4 | [`13-cr-check-go-design.md`](./git-apps/13-cr-check-go-design.md) | “Go 代码怎么组织？要写哪些接口？怎么测？要多久？”<br>含：需求边界（MVP）、架构图、包结构、**Go 接口定义**、数据模型与状态机映射、规则引擎、端点契约、`policy.yaml` 全量示例、测试策略、指标、**M0–M5 ≈ 17–25 人日**、10 条风险表 |
| 5 | [`14-rulesets-and-gitapp-gate.md`](./git-apps/14-rulesets-and-gitapp-gate.md) | “Rulesets 零基础 + 和 CR Check 怎么咬合 + 分支保护怎么分层配？”<br>含：Ruleset 五个组成部分与**分层叠加取最严**、25 条 API 规则清单、**唯一耦合点 `integration_id`**、**4 种静默失效**、分层 ruleset 完整 JSON、与 release 流程 14 步逐条映射、**Ruleset 表达不了的约束**、Merge Queue、18 条坑 |
| 6 | [`15-commit-message-cr-prefix.md`](./git-apps/15-commit-message-cr-prefix.md) | “commit message 必须以 `CR123456` 开头 —— 最小示例怎么配？”<br>含：两个例子（正/反）、三层判定模型（L1 hook / L2 Ruleset / L3 App）、**两条最小 ruleset JSON**、RE2 正则约束、**★ squash merge 到底校验谁**、★ metadata 规则需 Enterprise、本地模拟器、降级方案 |
| 7 | [`16-ruleset-install-runbook.md`](./git-apps/16-ruleset-install-runbook.md) | “JSON 怎么装上去才生效？”<br>含：组织级/仓库级端点差异、**安装六步顺序**、UI 导入 / `gh api` / IaC / GitOps 四条路径、**★ PUT 全量替换的坑**、**三层验证**、熔断纪律、权限矩阵、报错对照表 |
| 8 | [`17-probot-apps.md`](./git-apps/17-probot-apps.md) | “Probot 是什么？我们为什么不用它？”<br>含：Probot = 写 GitHub App 的 Node.js 脚手架、GitHub App vs PAT vs Actions 选型、**App/webhook/`context.octokit` 核心概念**、Hello World 源码、`APP_ID`/`WEBHOOK_SECRET`/`PRIVATE_KEY` 三个环境变量与部署形态、生态现成 app 清单、**Probot vs 我们的 Go 版 CR Check 逐项对照** |
| ★ | [`cr-check/`](./git-apps/cr-check/) | **★ 可运行的 Go 实现**（本文档集的代码部分）<br>CR Check 服务完整代码 + 策略配置 + K8s 清单 + 测试脚本<br>**30 秒跑起来** → [`cr-check/README.md`](./git-apps/cr-check/README.md) §0 |
| ★ | [`examples/rulesets/`](./examples/rulesets/) | **★ 可直接下发的 Ruleset 配置 + 契约检查**<br>5 份 ruleset JSON + `apply-rulesets.sh` + `validate-rulesets.py`（C1/C2/C3 断言） |

**四句话记住这套东西：**

```
① GitHub App = 身份（机器人） + 你自己服务器上的一个后端服务。
② Webhook URL = 事件通知的收件地址；
   自研场景下它**就是**你部署的 Go 服务的公网地址（Ingress + 域名 + TLS）。
③ App 只是“哨兵 + 报数员”，真正拦住 merge 的是 GitHub 分支保护的 required status checks。
④ GitHub Rulesets = 强制力那一层的现代写法。它与 App 只有一个耦合点：
   required_status_checks 的 context（= policy.yaml 的 checkName）+ integration_id（来源 App）。
   ★ 接错 → 门禁静默失效 → 见 doc 14 §4.5 与 examples/rulesets/validate-rulesets.py。
```

---

### [prow-pulls · 从 kubernetes-sigs/prow 的 PR 管理机制，看 GitHub 门禁该怎么设计](./prow-pulls.md)

> **背景**：上面 8 篇讲的是「**我们自己怎么造**」，
> 这一篇讲的是「**业界最成熟的门禁系统怎么设计**」——Prow 是 K8s 社区自己的 CI/CD 系统，
> 它的合并门（tide）跑在几千个 PR 上，踩过的坑比我们都多。

**直接回答**：「Prow 是怎么让『这个 PR 现在为什么不能合并』变成一个
**永远存在、永远准确、人和机器都能读**的东西的？哪些能直接抄？」

**Prow 最有价值的不是"它很强"，而是它的「可解释性」——而这正是我们 CR Check 缺的一层。**

取材方式：直接读 GitHub API 的真实数据（PR 列表、bot 评论、commit status、label 定义、Prow 源码），
所有关键结论附可复现命令（见附录 B）。

含：★ **值得学习的 13 个设计**（逐条：现象 → 证据 → 为什么 → 怎么抄）——
聚合 context 且说明「缺什么」（§2.1）、`do-not-merge/*` 命名空间承载所有阻塞原因（§2.2）、
**结论必须绑定 tree hash**（§2.3）、状态失效时同步撤销标记+重请 review+留痕（§2.4）、
**审批粒度跟着改动路径走**（OWNERS 模型，§2.5）、trust gate 与 merge gate 分离（§2.6）、
命令必须带理由且**在原生处理之前拦**（§2.8）、失败信息精确到可执行（§2.9）、
**自己的错误输出不能被自己当命令解析**（§2.10）、bot 评论嵌机器可读元数据（§2.11）、
配置即代码 + 热生效（§2.12）；值得警惕的地方（§3）→ 映射到 CR Check 的 P1/P2/P3 行动清单（§4）。

> ⚠️ 诚实说明：Prow 用的是 **commit status**，**不是** check run（§0.2）——
> 这也是我们为什么自研 App + 走 check run 那条路时，不能照抄 Prow 的关键差异点。

---

### [sigs · Kubernetes SIGs 生态地图，以及我们能借鉴什么](./sigs.md)

> **背景**：`kubernetes-sigs` 是 K8s 社区所有「**没进核心仓库、但已成事实标准**」项目的落地处。
> **该抄的是它的设计范式，不是它的项目清单。**

**直接回答**：「除了 Prow，这 210 个仓库里还有哪些设计值得抄到 GitOps / CR Check 上？」

**sigs 值得学的不是"用哪个项目"，而是"它怎么把一个生态项目做成事实标准"。**

取材方式：直接读 GitHub API 真实数据（仓库清单、topics、license、star、
`kubernetes/community` 的 `sigs.yaml`、各仓库 README 原文），**数据快照 2026-11-10**。

含：组织结构三层拆解与 `sigs.yaml` 机制（§1）、**210 个仓库生态地图**（§2）、
八个能力域（§3）、★ **值得借鉴的 8 个设计**（§4）——
**声明式 API + 独立 provider**（Cluster API / Gateway API / CSI，§4.1）、
**先有 conformance 再长生态**（§4.2）、**Kueue AdmissionCheck：外部系统参与准入决策的状态机**（§4.3）、
**cli-utils inventory：显式记录"这次 apply 了什么"**（§4.4）、
**structured-merge-diff 的字段所有权模型**（§4.5）、kubectl-validate 与服务端同源（§4.6）、
**时间线版本化**（§4.7）、Prow 的定位索引（§4.8）；
值得警惕的地方（§5）→ 行动清单 P1/P2/P3（§6）+ 证据速查与复现命令（§7–§8）。

> 📌 两篇的关系：[`prow-pulls.md`](./prow-pulls.md) 拆 Prow 的 **13 个门禁设计**，
> [`sigs.md`](./sigs.md) 拆 sigs 里**其它仓库**的设计（§4.1–§4.7）并补上 Prow 的定位（§4.8），
> **不重复**那 13 条。建议按 `prow-pulls` → `sigs` 的顺序读。

---

## 可复制示例

全部位于 [`examples/`](./examples/)，可直接 `kubectl apply`。

| 文件 | 用途 | 关键注意事项 |
|---|---|---|
| [`dex-ldap-config.yaml`](./examples/dex-ldap-config.yaml) | Dex + LDAP 完整配置（模式 C） | 组进 token 靠 `groupSearch`（**不靠** `insecureEnableGroups`） |
| [`argocd-rbac-cm.yaml`](./examples/argocd-rbac-cm.yaml) | 组 → 角色映射 | `scopes` 必须含 `groups`；`policy.default` 不能被 deny 收回 |
| [`appproject-multi-env.yaml`](./examples/appproject-multi-env.yaml) | 多环境项目边界 | 收紧 `default` 是破坏性操作 |
| [`applicationset-matrix.yaml`](./examples/applicationset-matrix.yaml) | 批量分发（Matrix/List/Merge） | `template.spec.project` 必须显式写 |
| [`argocd-repositories-githubapp.yaml`](./examples/argocd-repositories-githubapp.yaml) | Repository Secret | 目标分支**不在这里** |
| [`redis-statefulset-pvc.yaml`](./examples/redis-statefulset-pvc.yaml) | 业务 Redis 持久化改造 | 这是**业务** Redis，不是 Argo CD 内部 Redis |
| [`gitops-layout/`](./examples/gitops-layout/) | **完整 GitOps 仓库骨架**：`bootstrap/` + `apps/` + 集群组件清单 + 静态检查工具箱 | `bootstrap/` 里的非资源清单必须用 `kustomization.yaml` 排除 |
| [`gitops-layout/bootstrap-flow.md`](./examples/gitops-layout/bootstrap-flow.md) | **Bootstrap 完整流程图**：PR 门禁 → 点火 → 自举 → 生成 → 同步 → 巡查（七阶段 mermaid） | 手动只有阶段 0 和阶段 2 |
| [`ha-values-override.yaml`](./examples/ha-values-override.yaml) | HA 升级 values | `ARGOCD_API_SERVER_REPLICAS` 必须与副本数一致 |
| [`argocd-health.sh`](./examples/argocd-health.sh) | 一键体检脚本（只读） | 退出码 0=正常，1=有异常，2=环境不可用 |
| [`session-token-usage.md`](./session-token-usage.md) | 本次会话的 Token 用量报告 | 300 次 API 调用 / 约 16.4M token，含优化诊断 |

> ⚠️ **所有示例中的凭据均为 `[REDACTED]`**。
> 实际部署请用 Sealed Secrets / SOPS / External Secrets。

---

## ⭐ 静态检查工具箱（提交前跑一遍）

[`examples/`](./examples/) 里不只有示例，还有一整套**能把文档里的最佳实践变成可执行检查**的工具。
它们**不需要集群**，纯靠 Git 里的文件就能跑 → 可以直接进 CI 的 PR 检查。

```bash
cd examples/gitops-layout
./ci-check.sh          # ⭐ 一键跑完全部检查
```

| 工具 | 抓什么 |
|---|---|
| [`validate-examples.py`](./examples/validate-examples.py) | `policy.default=role:readonly`、`scopes` 少 `groups`、明文密码、HA 副本数不一致… |
| [`appset-simulator.py`](./examples/gitops-layout/appset-simulator.py) | Application **重名**、project 不存在、destination 不被允许、模板变量缺失 |
| [`render-check.py`](./examples/gitops-layout/render-check.py) | overlay 渲染失败（cycle detected）、selector 与 pod labels 对不上、镜像没打 tag |
| [`validate-clusters.py`](./examples/gitops-layout/validate-clusters.py) | 集群清单字段漂移（`server` / `env` 抄错） |
| [`check-doc-links.py`](./examples/check-doc-links.py) | 文档链接与**锚点**断裂 |
| [`new-cluster.sh`](./examples/gitops-layout/new-cluster.sh) / [`enable-component.sh`](./examples/gitops-layout/enable-component.sh) | 加集群 / 开关组件的脚手架（自动保持字段一致） |
| [`demo.sh`](./examples/gitops-layout/demo.sh) | 端到端 Demo：建集群 → 装 Argo CD → 建 AppProject/AppSet/App → 同步 → 验证 |

完整说明见 [`examples/README.md`](./examples/README.md)。

---

## 关键事实速查

### Argo CD 内部 Redis（`install.yaml:32441-32522`）

```yaml
# 实测事实：
#   volumes:      无
#   volumeMounts: 无
#   args:         --save "" --appendonly no
```

**准确表述**：未挂载持久卷，且**未配置 `emptyDir`**。
不是「用的是 emptyDir」——这两者不同，且结论**不能**推广到 HA Redis 或业务 Redis。

### 目标分支归属

```
Repository Secret  →  仓库地址 + 访问凭据 + 归属项目
Application        →  spec.source.targetRevision  ← 分支在这里
ApplicationSet     →  template.spec.source.targetRevision  ← 批量改这里
```

### 三个必须记住的 HA 约束

1. `ARGOCD_API_SERVER_REPLICAS` == `argocd-server.replicas`
2. `dex-server` 保持 1 副本
3. Redis sentinel 固定 3 副本

---

## 关联资源

| 资源 | 位置 | 说明 |
|---|---|---|
| Gatekeeper 完整部署资料 | [`../../gke/opa-gatekeeper/`](../../gke/opa-gatekeeper/) | **优先复用**，不要另建一套 |
| Argo CD 官方清单 | [`../install.yaml`](../install.yaml) | Redis 事实来源 |
| 上游调研缓存 | `~/.hermes/profiles/architecture/cache/scratch/upstream/argocd-research/` | 上游 RBAC / ConfigMap / Repository 源码提取结果（**本地缓存，不在仓库内**） |
| Argo CD 管理员指南 | [`../argocd-admin-guide.md`](../argocd-admin-guide.md) | 已有总览文档 |
| Application 字段详解 | [`../argocd-application-guide.md`](../argocd-application-guide.md) | |
| CLI 指南 | [`../argocd-cli-guide.md`](../argocd-cli-guide.md) | |

---

## 使用约定

文档中的内容按以下四类标注，实施前请按需验证：

| 标注 | 含义 | 验证方式 |
|---|---|---|
| **官方保证** | 上游文档或源码明确写明 | 已核对上游 `master` 分支 |
| **当前清单事实** | 从本仓库 `install.yaml` 实测提取 | 可用 `grep`/`kubectl` 复核 |
| **推荐实现** | 本文档给出的方案建议 | 按示例 apply 后验证 |
| **部署前验证项** | 因环境差异需自行核对 | 见文档内标注的官方链接 |
