# 25 · GitHub Environments 与部署保护

> **直接回答**：「Approve 这一步放在 GitHub 的哪个位置最合适？」
> 「Argo CD 部署完了，怎么让 GitHub 知道'这次部署到 production 成功了'？」
>
> **一句话结论**
> ★ GitHub 的 **Environment** 就是"部署目标"的抽象（production / staging / …），
> 它带**保护规则**（required reviewers / wait timer / branch policy / 自定义保护规则），
> 并且能产生 **deployment 对象**——这正好是 Argo CD Notifications `service.github` 能写的东西。
> ★ 所以闭环是：
> **Argo CD 部署 → 写 deployment → GitHub 的 deployment 状态变 success/failure
> → ruleset 的 `required_deployments` 可以要求它 → 环境审批人把关。**

---

## 目录

| 章节 | 内容 |
|---|---|
| [`1](#1-先把三个environment分清) | GitHub Environment ≠ K8s Namespace ≠ Argo CD AppProject |
| [`2](#2-environment-的四种保护) | required reviewers / wait timer / branch policy / 自定义规则 |
| [`3](#3-deployment-对象) | 事实、状态机、谁创建 |
| [`4](#4-与-argo-cd-联动notifications-的-deployment-字段) | ★ Notifications service.github 的 deployment 字段 |
| [`5](#5-required_deployments-规则) | ruleset 侧怎么要求部署成功 |
| [`6](#6-merge-queue-与-merge-train) | 官方机制 + 无 Actions 的可行性 |
| [`7](#7-审批链设计) | 谁在哪一层批 |
| [`8](#8-api-端点清单) | 可直接调用的接口 |
| [`9](#9-验证命令) | 探针 |
| [`10](#10-坑清单) | 10 条 |

---

## 1. 先把三个 environment 分清

| 概念 | 属于谁 | 作用 | 配错了会怎样 |
|---|---|---|---|
| **GitHub Environment** | GitHub | 一个"**部署目标**"的名字 + 保护规则 + deployment 记录 | ruleset 的 `required_deployments` 引用不到 |
| **K8s Namespace** | 集群 | 资源隔离 | Argo CD 目标搞错 → 部署到错环境 |
| **Argo CD AppProject** | Argo CD | 权限边界 + 同步窗口 + 资源白名单 | 权限越界 / 同步被窗口拦住 |

> ★ **三者名字常常一样（都叫 `production`）→ 极易混淆。**
> 建议在文档与变量命名上区分：
> GitHub 环境用 `gh-env:production`、K8s 用 `ns:prod`、Argo CD 项目用 `proj:platform-prod`。

---

## 2. Environment 的四种保护

| 保护 | 作用 | 谁能配 | 适合 |
|---|---|---|---|
| **Required reviewers** | 部署前必须有人批准（可按分支/标签区分） | Org/Repo 管理员 | ★ **生产环境的人工闸** |
| **Wait timer** | 批准后等待 N 分钟才允许部署 | 管理员 | 留出"发现问题还能取消"的窗口 |
| **Branch policy** | 只允许特定分支/标签部署到这个环境 | 管理员 | "只有 `main` 能上 production" |
| **Custom deployment protection rules** | ★ **自定义审批逻辑**（Enterprise 能力） | Org 管理员 | 接入外部系统（如 CR 平台）做判定 |

**自定义部署保护规则（Enterprise）**：

- 官方接口形态（**部署前验证项**，以你们版本为准）：
```bash
GET  /repos/{owner}/{repo}/environments/{env}/deployment_protection_rules
POST /repos/{owner}/{repo}/environments/{env}/deployment_protection_rules
DELETE /repos/{owner}/{repo}/environments/{env}/deployment_protection_rules/{id}
```
- 典型用法：**"只有当 CR 平台返回该变更单已批准时才允许部署"**——
  这正是既有 [`11 Part B`](../git-apps/11-github-app-concepts.md) 讨论的"三层门禁"里的第三层。

> ★ **重要判断**：
> 如果你们的审批权威在 **CR 平台**（见 [`18 `9 Q2`](./18-framework-github-first-gitops.md)），
> 那么"自定义部署保护规则"的价值是**让 GitHub 也知道同一个结论**，
> 而不是把审批逻辑复制一份到 GitHub。
> → **规则单一来源**：CR 平台判定，GitHub 只是"引用"这个结论。

---

## 3. deployment 对象

**实测事实**（`gh api /repos/argoproj/argo-cd/deployments?per_page=1` 返回）：

```json
{
  "id": 433823024,
  "sha": "b80f8cdca80db10f1624936080702c71cb5feaaa",
  "ref": "b80f8cdca80db10f1624936080702c71cb5feaaa",
  "environment": "github-pages",
  "task": "deploy",
  "created_at": "2021-10-06T17:55:15Z"
}
```

| 字段 | 含义 | 在我们方案里的来源 |
|---|---|---|
| `sha` | 部署的是哪个 commit | ★ **必须等于 CR 审批的那个 SHA** |
| `ref` | 部署的 ref（分支/tag/SHA） | 同上 |
| `environment` | 部署到哪个环境名 | ★ 必须与 ruleset 的 `required_deployments.environment_name` **完全一致** |
| `task` | 任务名（deploy / …） | 固定 `deploy` |
| `created_at` | 创建时间 | — |

**deployment_status**（单独的对象）：`state`（`pending` / `in_progress` / `success` / `failure` / `error`）、
`environment_url`、`log_url`、`description`。

**谁创建 deployment？**

| 创建者 | 场景 |
|---|---|
| **Argo CD Notifications `service.github`** | ★ **推荐**：部署真的完成后才写（语义最准） |
| CR Check / driver | 需要"提前占位"（先 pending，成功后改 success）时 |
| 人 / 脚本 | 兜底 |

> ★ **推荐用 Notifications 写**（见 `4），因为它拿到的是 Argo CD 的
> **真实 operation 结果**（`status.operationState.phase` + `syncResult.revision`）。

---

## 4. ★ 与 Argo CD 联动（Notifications 的 deployment 字段）

**官方保证**（上游 `docs/operator-manual/notifications/services/github.md`），template 支持：

```yaml
template.app-deployed: |
  github:
    repoURLPath: "{{.app.spec.source.repoURL}}"
    revisionPath: "{{.app.status.operationState.syncResult.revision}}"
    deployment:
      state: success
      environment: production
      environmentURL: "https://{{.app.metadata.name}}.example.com"
      logURL: "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true"
      requiredContexts: []
      autoMerge: true
      transientEnvironment: false
      reference: "{{.app.status.operationState.syncResult.revision}}"
```

| 字段 | 说明 | ★ 注意点 |
|---|---|---|
| `state` | deployment 状态 | `success` / `failure` / `error` / `in_progress` / `pending` |
| `environment` | 目标环境名 | ★ **必须与 GitHub Environment 名逐字一致**（大小写敏感） |
| `environmentURL` | 部署后的地址 | 会显示在 GitHub 上 |
| `logURL` | 日志链接 | 指向 Argo CD 的应用页（`?operation=true` 展开操作详情） |
| `requiredContexts` | 部署依赖的 check | 配合 `required_deployments` |
| `autoMerge` | 是否自动把分支推进到被部署的 SHA | 官方默认 **true**；★ **部署旧版本时要显式设 false** |
| `transientEnvironment` | 是否为临时环境 | false = 真实环境名 |
| `reference` | 部署的引用 | 不设则用 revision |

> ★ **`autoMerge` 是个容易踩的坑**：
> 官方原文——"Automerge is optional and `true` by default for github deployments to ensure the requested ref is
> up-to-date with the default branch. Setting this option to `false` is required if you would like to deploy older refs."
> → **如果要部署历史版本，必须写 `autoMerge: false`**，否则 GitHub 会把分支指针推到部署的 SHA。

**失败时也要写**（别只写成功）：

```yaml
# 建议再准备一个 template.app-sync-failed
github:
  deployment:
    state: failure
    environment: production
    logURL: "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true"
```

---

## 5. `required_deployments` 规则

**规则形态**（既有 [`examples/rulesets-enterprise/00-enterprise-capabilities.md`](../examples/rulesets-enterprise/00-enterprise-capabilities.md) 已列为基础能力）：

```jsonc
{
  "type": "required_deployments",
  "parameters": {
    "required_deployment_environments": ["production"]
  }
}
```

**它的语义**：合并到目标分支前，**名为 `production` 的环境必须有一个成功的 deployment**。

**三个必须对上的东西**（★ 最常见的失效原因）：

```
ruleset.environment_name  ==  deployment.environment  ==  Notifications template 里的 environment
```

> ⚠️ 如果 Notifications 写的 environment 是 `prod`，
> 而 ruleset 要求的是 `production` → **规则永远不满足 → 所有 PR 卡死**。
> ★ 把这三个名字写进同一个配置文件（甚至同一个常量），别手写两遍。

---

## 6. merge queue 与 merge train

### 6.1 官方机制（GitHub 官方文档 `managing-a-merge-queue`）

| 机制 | 说明 |
|---|---|
| **临时分支** | 队列里的 PR 会被合并成一个临时分支，前缀 `gh-readonly-queue/{base_branch}`，**SHA 与 PR 不同** |
| **merge_group 事件** | 每次组队都会发这个事件，等待 CI 报告 check |
| **Build concurrency** | 同时派发的 `merge_group` 数量上限（1–100） |
| **Only merge non-failing pull requests** | 关掉后，队列中**前面的 PR 检查失败也不阻塞**后面的（只有最后一个必须通过） |
| **Status check timeout** | 等待 CI 的超时 |
| **Merge limits** | 每批最小/最大 PR 数 + 等待最小批量的超时 |
| **Jumping to the top** | 插队 → **会触发整队重建**（提交图断裂），滥用会拖慢合并 |

### 6.2 无 Actions 时的可行性（结论见 [`19 `5.2`](./19-no-actions-alternative-matrix.md)）

| 方案 | 可行性 | 建议 |
|---|---|---|
| GitHub App 订阅 `merge_group` | ⚠️ 需实测（探针见 [`19 `5.1`](./19-no-actions-alternative-matrix.md)） | 第二期再试 |
| 外部 CI 监听 `gh-readonly-queue/*` | ✅ 官方文档明确支持第三方 CI 这么做 | 有外部 CI 时可选 |
| **不用 merge queue** | ✅ | ★ **第一期推荐**；用 Argo CD 同步窗口 + ApplicationSet 渐进同步做串行化 |

> ★ **"merge train"** 这个词在 GitHub 语境里通常指 **merge queue**
> （把多个 PR 组队批量合并）。
> GitHub 的术语是 **merge queue**（队列），不是 train；
> 文档里说 merge train 时，说的就是它。

---

## 7. 审批链设计

**推荐的分层**（每层只回答一个问题）：

| 层 | 问题 | 谁 | GitHub 上的载体 |
|---|---|---|---|
| ① 规则合规 | 格式/命名/评审数对吗？ | **机器**（Ruleset + CR Check） | check run / ruleset |
| ② 变更授权 | 有没有人批这个变更单？ | **CR 平台**（权威） | CR Check 的 check run 结果 |
| ③ 部署授权 | 现在允许上 production 吗？ | **人**（Environment required reviewers） | environment approval |
| ④ 执行 | 谁按下按钮？ | driver / 自动收敛 | Argo CD operation |
| ⑤ 结果 | 成功了吗？ | Argo CD | deployment / commit status |

**一条重要的分工原则**：

> ★ **②③ 不要都放在 GitHub**。
> 如果 CR 平台是变更单的权威系统，那么 GitHub Environment 的审批应该是
> **"最后一道、且可跳过"的人工闸**（比如只对 prod、只对高危变更），
> 而不是把同一件事问两遍。
>
> 反过来，如果你们希望 **GitHub 就是唯一入口**（不引入 CR 平台的深度耦合），
> 那就用 **Environment required reviewers + 自定义保护规则**，把 CR 平台的查询做进自定义规则里。

---

## 8. API 端点清单

| 用途 | 端点 |
|---|---|
| 列环境 | `GET /repos/{owner}/{repo}/environments` |
| 建/改环境 | `PUT /repos/{owner}/{repo}/environments/{env}` |
| 环境保护规则 | `GET/POST /repos/{owner}/{repo}/environments/{env}/deployment_protection_rules` |
| 部署列表 | `GET /repos/{owner}/{repo}/deployments` |
| 创建部署 | `POST /repos/{owner}/{repo}/deployments` |
| 部署状态 | `POST /repos/{owner}/{repo}/deployments/{id}/statuses` |
| Ruleset 列表 | `GET /repos/{owner}/{repo}/rulesets` |
| Ruleset 详情（★ 含 rules） | `GET /repos/{owner}/{repo}/rulesets/{ruleset_id}` |
| 某分支上生效的规则（★ 权威） | `GET /repos/{owner}/{repo}/rules/branches/{branch}` |

> ⚠️ **Ruleset 的坑**（既有 [`16 `2.5`](../git-apps/16-ruleset-install-runbook.md) 已记录）：
> `GET .../rulesets` **不返回 rules 内容**，必须按 id 再查一次；
> 而"这个分支上到底生效了什么"要看 `/rules/branches/{branch}`。
> → **验收一定要用最后那个接口**，否则会得出"规则装上了"的错误结论。

---

## 9. 验证命令

```bash
# ① 环境与保护规则
gh api repos/<ORG>/<REPO>/environments --jq '.environments[].name'
gh api repos/<ORG>/<REPO>/environments/production/deployment_protection_rules \
  --jq '.protection_rules[] | {type, reviewers, wait_timer}'

# ② 最近的 deployment（看 environment 名是否与 ruleset 对得上）
gh api repos/<ORG>/<REPO>/deployments?per_page=5 \
  --jq '.[] | {id, environment, sha, ref, created_at}'

# ③ deployment 状态
gh api repos/<ORG>/<REPO>/deployments/<id>/statuses --jq '.[0] | {state, environment_url}'

# ④ ruleset 里是否要求了部署
gh api repos/<ORG>/<REPO>/rulesets --jq '.[].id' | while read id; do
  gh api "repos/<ORG>/<REPO>/rulesets/$id" --jq '.rules[]? | select(.type=="required_deployments")'
done

# ⑤ ★ 权威口径：这个分支上实际生效的规则
gh api repos/<ORG>/<REPO>/rules/branches/main --jq '.[] | {ruleset_source_type, ruleset_source}'
```

---

## 10. 坑清单

| # | 坑 | 后果 | 规避 |
|---|---|---|---|
| 1 | environment 名大小写/拼写不一致 | `required_deployments` 永远不满足 → PR 全卡 | 三个名字用**同一个常量** |
| 2 | Notifications 只写成功、不写失败 | 部署失败了，GitHub 上还是旧的 success | 成功与失败**都写** |
| 3 | `autoMerge` 没设 false | 部署历史版本时 GitHub 把分支指针推走 | 显式 `autoMerge: false` |
| 4 | 部署的 `sha` 不是审批的那个 SHA | "批的是 A，装的是 B" | revision 取 `operationState.syncResult.revision`，并与 CR 号比对 |
| 5 | 用 `GET /rulesets` 判断规则是否生效 | 看不到 rules → 误判"装上了" | 用 `/rules/branches/{branch}` |
| 6 | Environment 审批人离职 | 没人能批 → 卡死 | 定期巡审 reviewer 列表 |
| 7 | 同时用 required reviewers 和自定义规则 | 双重等待 / 逻辑冲突 | 二选一，或明确优先级 |
| 8 | 把 CR 平台的批准逻辑复制进 GitHub | 两套实现不一致 | 单一来源（`7） |
| 9 | merge queue 的临时分支被当成真分支 | 脚本误触发 | 过滤 `gh-readonly-queue/*` |
| 10 | 把 GitHub Environment 当成 K8s Namespace | 部署到错环境 | 命名区分（`1） |

---

## 关联文档

- 上一级：[`18 总体框架`](./18-framework-github-first-gitops.md)
- 无 Actions 的影响：[`19 替代方案矩阵`](./19-no-actions-alternative-matrix.md)
- 回写 GitHub 的实现：[`20 Notifications service.github`](./20-argocd-webhook-and-notifications.md)
- Ruleset 咬合（既有）：[`git-apps/14-rulesets-and-gitapp-gate.md`](../git-apps/14-rulesets-and-gitapp-gate.md)
- Ruleset 验收（既有）：[`git-apps/16-ruleset-install-runbook.md`](../git-apps/16-ruleset-install-runbook.md)
- 企业版能力矩阵（既有）：[`examples/rulesets-enterprise/00-enterprise-capabilities.md`](../examples/rulesets-enterprise/00-enterprise-capabilities.md)
