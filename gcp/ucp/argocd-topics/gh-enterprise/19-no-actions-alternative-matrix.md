# 19 · 不用 GitHub Actions 的替代方案

> **直接回答**：「我们用企业版 GitHub，Actions 这些动作可能就不让使用。那原来靠 Action 做的事怎么办？」
>
> **一句话结论**
> ★ Actions 被禁**不会让门禁消失**，只会让门禁**换执行者**。四类去处：
> ① **GitHub 原生规则**（Ruleset，服务端执行，**不需要 runner**）——
>    这是最该优先用的，因为**它无法被绕过**（不受仓库里文件被篡改影响）。
> ② **自研 GitHub App 写 check run**（CR Check 已经在做，扩展它）。
> ③ **Argo CD 侧**（渲染失败 = 同步失败；Gatekeeper 准入）。
> ④ **集群外系统**（你写的 Go 服务 / 内部平台）。
>
> ⚠️ **真正会消失的能力只有两个**：`required_workflows`（本质就是 Actions）和
> **由 `merge_group` 事件触发的 CI**（merge queue 必须有 CI 报告 check）。详见 `5。

---

## 目录

| 章节 | 内容 |
|---|---|
| [`1](#1-先确认-actions-到底是"禁"还是"限") | 先问清楚问题的边界 |
| [`2](#2-四类去处) | 四类替代执行者 + 能力对照 |
| [`3](#3-逐条替代矩阵) | **Action 用途 → 替代实现** 逐条对照 |
| [`4](#4-校验搬家到哪) | YAML / Kustomize / 镜像 tag 这类校验怎么搬 |
| [`5](#5-真正消失的两个能力) | required_workflows 与 merge queue |
| [`6](#6-迁移路线) | P0–P5 |
| [`7](#7-坑清单) | 12 条坑 |

---

## 1. 先确认 Actions 到底是"禁"还是"限"

这个问题不问清楚，后面全是白工。三种可能，后果完全不同：

| 情况 | 含义 | 影响 |
|---|---|---|
| **L1 完全禁用** | 任何 workflow 都不能跑 | 本文档的完整矩阵适用 |
| **L2 禁用托管 runner**（只允许自建 runner） | workflow 仍可跑，但 runner 由你们自己运维 | **最省事**：CR-prefix 之类的 Action 可以保留（见既有 [`06-dev-branch-guard-x-cr-prefix-action`](../examples/rulesets/06-dev-branch-guard-x-cr-prefix-action.md)） |
| **L3 禁用 Actions 但保留 Codespaces / 其它 CI** | 需要外部 CI 平台 | 见 `3 中"外部 CI"一列 |

> ★ **判定方法**（把结果贴进 PR）：
```bash
# 看组织策略里有没有禁 Actions
gh api /orgs/<ORG>/actions/permissions 2>&1 | head -20
gh api /orgs/<ORG>/actions/permissions/selected-actions 2>&1 | head -20

# 看有没有自建 runner（allowed_actions / runner_groups）
gh api /orgs/<ORG>/actions/runner-groups 2>&1 | head -20
```
>
> **部署前验证项**：企业策略的字段随版本变化，以你们 Enterprise 管理后台
> 「Settings → Policies → Actions」为准。

---

## 2. 四类去处

| 去处 | 执行者 | 需要 runner？ | 能否被绕过 | 适合的检查 |
|---|---|---|---|---|
| ① **Ruleset 原生规则** | GitHub 服务端 | ❌ | **不能**（存在 GitHub 侧，不在仓库里） | 命名规范、评审数、线性历史、必需 check、必需部署、必需签名 |
| ② **GitHub App 写 check** | 你的 Go 服务 | ❌（自己跑） | 需防"App 没被调用"（见 `7 坑 3） | CR 合规、跨系统业务校验 |
| ③ **Argo CD / K8s 侧** | Argo CD + 准入控制器 | ❌ | 需防"绕过 Argo CD" | 渲染正确性、schema、策略 |
| ④ **外部 CI / 平台** | 你们的 CI | 视情况 | 取决于接入方式 | 需要真实构建/测试的检查 |

### 2.1 选型原则（**按"能不能被绕过"排序，不是按"好不好写"排序**）

```
优先级 1 ── Ruleset 原生规则（服务端、不可绕过）
优先级 2 ── 集群准入（Gatekeeper；绕过 Argo CD 也绕不过）
优先级 3 ── GitHub App check（可绕过 App，但 ruleset 的 required check 能卡住 merge）
优先级 4 ── 外部 CI（最灵活，最容易被"没跑就合"绕过）
```

> ★ **一句话**：**能用 Ruleset 表达的，不要用 Action 表达。**
> 因为 Ruleset 活在 GitHub 服务端，而 workflow 文件活在仓库里——
> **能改 workflow 文件的人，就能改掉检查规则**（这正是既有 [`11 Part B`](../git-apps/11-github-app-concepts.md) 讲的"规则与代码分离"的递归问题）。

---

## 3. 逐条替代矩阵

| 原来用 Action 做的事 | 替代实现 | 执行者 | 备注 |
|---|---|---|---|
| **commit message 必须以 CR 开头** | Ruleset `commit_message_pattern` | GitHub 服务端 | ★ Enterprise 能力；见既有 [`15`](../git-apps/15-commit-message-cr-prefix.md) |
| **分支命名规范** | Ruleset `branch_name_pattern` | GitHub 服务端 | Enterprise |
| **tag 命名规范** | Ruleset `tag_name_pattern` | GitHub 服务端 | Enterprise |
| **必须走 PR / 禁直推** | Ruleset `pull_request` + 禁直推 | GitHub 服务端 | 所有计划可用 |
| **至少 N 个 reviewer** | Ruleset `pull_request.required_approving_review_count` | GitHub 服务端 | — |
| **禁强推 / 禁删分支** | Ruleset `non_fast_forward` / `deletion` | GitHub 服务端 | — |
| **线性历史** | Ruleset `required_linear_history` | GitHub 服务端 | — |
| **必需 check 通过才能合** | Ruleset `required_status_checks`（context = CR Check 的 check 名） | GitHub 服务端 | ★ **耦合点只有一个：context 名** |
| **必须部署成功才能合** | Ruleset `required_deployments` | GitHub 服务端 | 环境名必须与实际 deployment 的 environment 一致，见 [`25](./25-github-environments-and-deployment-protection.md) |
| **PR 标题含 CR 号** | **无原生规则** → CR Check 的 check run 内校验 | CR Check | Actions 时代常用 `pull_request_target` + 脚本，禁 Actions 后必须挪进 App |
| **YAML 语法检查** | ① Argo CD 渲染（解析失败即同步失败）② CR Check 内调用解析库 ③ 外部 CI | 组合 | 见 `4 |
| **Kustomize build 校验** | ① 外部 CI ② Argo CD repo-server 渲染失败 ③ 仓库内既有静态检查脚本（手动/CI 触发） | 组合 | 见 `4 |
| **Helm template 校验** | 同上 | 组合 | — |
| **镜像必须有 tag、不能 latest** | **Gatekeeper / Policy Controller 准入** | K8s 准入 | ★ **这才是正确的位置**：它管的是"集群里最终跑的东西"，不是"提交的内容" |
| **改动了 prod 目录要两个 reviewer** | Ruleset `pull_request` + CODEOWNERS（按路径） | GitHub 服务端 | 既有 [`prow-pulls`](../prow-pulls.md) `2.5 的 OWNERS 思路 |
| **跑单测 / 集成测试** | **外部 CI**（无法用 Ruleset 表达） | 外部系统 | Actions 被禁 → 这部分能力**真的没了**，除非有别的 runner |
| **发布制品 / 构建镜像** | 外部 CI / GCP 云构建 | 外部系统 | — |
| **自动打 tag 发版** | 外部系统 + GitHub App API | 外部 | — |
| **通知团队"PR 已合并"** | Ruleset 不可做；用 **Argo CD Notifications `service.github`** 回写 + PR comment；或外部系统用 GitHub API | 外部 | — |
| **"部署成功"变成 GitHub 上的绿色勾** | **Argo CD Notifications `service.github`**（写 commit status / check run / deployment） | Argo CD 侧 | ★ **无 Actions 的关键替代**，见 [`20](./20-argocd-webhook-and-notifications.md) |

---

## 4. 校验搬家到哪

三类"内容校验"（YAML 语法、Kustomize 渲染、镜像 tag）**没有 Ruleset 原生对应物**。三种去处：

### 4.1 方案 A：放进 Argo CD（"渲染失败 = 同步失败"）

- **原理**：Argo CD repo-server 渲染 manifests 时，模板/语法错误会让 Application 进入 `ComparisonError` / `Unknown`，**同步根本不会发生**。
- **优点**：零额外组件；校验点就在"真正要部署的那份 YAML"上。
- **缺点**：**太晚了**——已经 merge 了才发现渲染失败。
- **推荐用法**：作为**最后一道防线**，不是第一道。

### 4.2 方案 B：放进 CR Check（GitHub App 里调用解析库）

- **原理**：CR Check 收到 PR 事件后，直接在 Go 进程里做 YAML/Kustomize 解析，把结果写进 check run。
- **优点**：**在 merge 前**拦截；不需要 runner；逻辑与规则引擎同一处，便于统一。
- **缺点**：需要在 CR Check 里引入渲染依赖（kustomize/helm 的 Go 库或调用它们的 CLI）；
  **大仓库渲染耗时长** → 需要超时与缓存。
- **推荐用法**：★ **第一道防线**（小仓库直接渲染；大仓库只做语法级检查）。

### 4.3 方案 C：外部 CI（保留原 Actions 语义，但 runner 换地方）

- 把 workflow 改成由**外部系统**（你们的 CI / Tekton / Jenkins）执行，GitHub 只当"被调度的 API"。
- GitHub → 外部系统的触发方式（**都不需要 Actions**）：
  ① **repository_dispatch**：外部系统轮询或 GitHub App 转发；
  ② **GitHub App webhook**：外部服务订阅 pull_request 事件；
  ③ **Argo CD Notifications `service.webhook`**：Argo CD 主动调外部系统。

> ★ **选型建议**：
> | 你的情况 | 选 |
> |---|---|
> | 仓库小、校验轻（YAML 语法、命名、镜像 tag） | **B（CR Check）+ A（Argo CD 兜底）** |
> | 仓库大、要跑真实测试 | **C**，且**必须**接受"merge 前不一定跑过"的风险，用 A 兜底 |
> | 只想管镜像 tag / 资源配额 | **Gatekeeper 准入**（不是 GitHub 侧） |

---

## 5. 真正消失的两个能力

### 5.1 `required_workflows`（Ruleset 的"组织级强制 CI"）

- **官方保证**：`required_workflows` 是 Enterprise 的 rule type，作用是"组织级强制所有仓库在 PR 上跑某个仓库里的 workflow"。
- **致命点**：workflow 就是 Actions。**Actions 被禁 → 这条规则没有意义**。
- **替代**：**没有等价物**。
  - "组织级强制"这个诉求 → 改用**组织级 Ruleset** + required_status_checks（context 指向 CR Check 的 check 名）；
  - "强制跑某个仓库的 workflow" → 改成**强制跑某个 GitHub App**（CR Check 就是那个 App）。

### 5.2 merge queue 的 `merge_group` 事件

**merge queue 的机制**（GitHub 官方文档）：

1. PR 进入队列后，GitHub 创建一个**临时分支**（前缀 `gh-readonly-queue/{base_branch}`），
   里面包含**目标分支最新内容 + 队列中排在它前面的所有 PR 的改动**。
2. GitHub 发出 `merge_group` 事件，**等待 CI 报告 check**。
3. required checks 全绿 → 合并；某个 check 失败 → 那个 PR 被移出队列，其后的队列重建。

**没有 Actions 时的三种可能**：

| 方案 | 做法 | 可行性 | 备注 |
|---|---|---|---|
| **Q1 GitHub App 订阅 merge_group** | App 收到 merge_group 事件 → 在**合并组那个 SHA** 上跑校验 → 写 check run | ⚠️ **需实测**：App 能否订阅 merge_group、check run 能否报到 merge_group 的 ref 上 | ★ 优先试这个，探针见 `5.1 |
| **Q2 外部 CI 监听临时分支** | 外部系统 watch `gh-readonly-queue/*` 分支 | ✅ 可行（GitHub 官方文档明确说明第三方 CI 就是这么做的） | 但需要外部系统有 git 读权限 |
| **Q3 不用 merge queue** | 放弃队列，改用**同步窗口 + Argo CD 串行化** | ✅ 一定能做 | ★ **兜底方案**：Argo CD 侧本来就要做串行/窗口控制 |

> ★ **强烈建议**：**先别把 merge queue 放进第一期**。
> 合并队列解决的是"批量合并时的竞态"，
> 而你们的核心诉求是"**校验 + 批准 + 可控执行**"——
> 前者用 **Ruleset + CR Check** 就能满足 90%。
> merge queue 属于**第二期优化**，且在没有 Actions 时它需要 Q1/Q2 额外投入。
>
> **兜底**：用 **Argo CD 的 sync window + ApplicationSet 渐进同步**在集群侧做串行化（见 [`21](./21-sync-windows-and-auto-sync.md) 与 [`05-appset `6 Progressive Syncs`](../05-appset.md)）。

#### 5.1 Q1 的探针命令（**部署前验证项**）

```bash
# ① App 能否收到 merge_group？（在 App 后台 Webhook 事件里勾选 merge_group 后）
#    往 PR 分支 push 一个 commit，把 PR 加进队列，看 App 是否收到事件
gh api /repos/<ORG>/<REPO>/pulls/<PR>/merge --method PUT -f merge_method=squash 2>&1 | head

# ② 队列里的临时分支（合并组）在哪
gh api /repos/<ORG>/<REPO>/branches --paginate --jq '.[].name' | grep 'gh-readonly-queue'

# ③ check run 要报到哪个 ref？（合并组分支名，而不是 PR 分支名）
gh api /repos/<ORG>/<REPO>/commits/gh-readonly-queue%2Fmain/check-runs --jq '.check_runs[].name' 2>&1 | head
```

---

## 6. 迁移路线

| 阶段 | 目标 | 动作 | 完成判据 |
|---|---|---|---|
| **P0 摸底** | 知道哪些检查现在依赖 Action | 列出仓库里所有 `.github/workflows/*`，逐个标注"谁在依赖它" | 一张清单 |
| **P1 保留原生** | 把能上 Ruleset 的搬上去 | commit/branch/tag 命名、评审数、必需 check | 不合规 PR 合不了 |
| **P2 扩 CR Check** | 把剩下能搬的搬进 App | PR 标题校验、YAML 语法、基础渲染 | check run 覆盖清单里的每一项 |
| **P3 换执行者** | 真正需要构建/测试的，交给外部系统 | 外部 CI 或 GitLab/Jenkins 回调 | 旧的 workflow 文件全部删除或标注"已弃用" |
| **P4 补兜底** | 集群侧兜底 | Gatekeeper 加镜像 tag / 配额 / 必填标签规则 | 故意提交违规资源会被拒 |
| **P5 清账** | 确认没有残留依赖 | 全仓 grep workflow 引用；检查 ruleset 里没有指向已删 workflow 的 required check | **required check 的 context 必须仍被某个 check run 产出** |

> ⚠️ **P5 最容易漏**：删掉 workflow 之后，如果某个 ruleset 还在要求它的 check 名，
> **那个 check 永远不会出现 → 所有 PR 永远卡住**（或者反过来，规则被静默丢弃）。
> 这正是既有 [`16 `2.5`](../git-apps/16-ruleset-install-runbook.md) 说的"规则装上了却什么都不拦"的镜像问题。

---

## 7. 坑清单

| # | 坑 | 后果 | 规避 |
|---|---|---|---|
| 1 | 以为"禁 Actions = 没有 CI" | 门禁被悄悄删掉 | 用 `probe-enterprise-capabilities.sh` 实测（既有脚本） |
| 2 | 把规则从 Ruleset 挪到 App check，**没同步挪 required_status_checks** | 检查存在但没人要求它 | 改完必须联调验证"真的合不了" |
| 3 | CR Check **没被调用**时 silently pass | 门禁形同虚设 | App 侧要有"心跳"：定时自检 + check run 写入失败要告警 |
| 4 | commit message 规则用 `contains` 而不是 ^ 锚定 | "fix CR123456" 也通过 | 用 `^CR[0-9]{6}(\s|$)` 锚定（既有 [`15`](../git-apps/15-commit-message-cr-prefix.md)） |
| 5 | squash merge 时校验的是**合并后的 message** | 单个 commit 合规但合并后不合规 | 明确规则针对"最终落到目标分支的 commit" |
| 6 | 镜像 tag 校验放在 GitHub 侧 | 有人直推/外部系统改集群时失效 | 放 Gatekeeper（集群侧才管得住） |
| 7 | 大仓库在 App 里做完整渲染 | webhook 10s 超时、内存爆 | 只做语法级检查；完整渲染交给外部 CI 或 Argo CD |
| 8 | 删了 workflow 但 ruleset 还在要求它 | 所有 PR 卡死 | P5 清账 + 定期巡检 |
| 9 | check run 的 **context 名**改了 | ruleset 引用失效（静默） | context 名写进配置并**契约校验**（既有 `validate-rulesets.py`） |
| 10 | 以为 Ruleset 能校验文件内容 | 做不到 | 内容校验必须靠 App / 外部 CI / 准入控制器 |
| 11 | merge queue 在无 Actions 下没检查可等 | 队列把没校验的改动合进去 | 不用 merge queue，或先做 `5.1 Q1 探针 |
| 12 | 用 GitHub App 写 check 时用了过期 token | 间歇性失败、难排查 | token 定期轮换 + 失败重试 + 监控（既有 [`how-to-atomic-idempotency`](../how-to-atomic-idempotency.md)） |

---

## 关联文档

- 上一级：[`18 总体框架`](./18-framework-github-first-gitops.md)
- Ruleset 能力矩阵（既有）：[`examples/rulesets-enterprise/00-enterprise-capabilities.md`](../examples/rulesets-enterprise/00-enterprise-capabilities.md)
- Ruleset × App 咬合（既有）：[`git-apps/14-rulesets-and-gitapp-gate.md`](../git-apps/14-rulesets-and-gitapp-gate.md)
- 部署顺序（既有）：[`16-ruleset-install-runbook.md`](../git-apps/16-ruleset-install-runbook.md)
- 执行结果回写：[`20 Argo CD Webhook 与 Notifications`](./20-argocd-webhook-and-notifications.md)
