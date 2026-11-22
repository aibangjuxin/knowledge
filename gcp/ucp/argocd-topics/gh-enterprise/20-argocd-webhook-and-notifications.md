# 20 · Argo CD 内置 Webhook 与 Notifications

> **直接回答**：
> 「GitHub 推了代码，Argo CD 怎么立刻知道？」
> 「部署成功了，怎么让 GitHub 上也看到（不用 Actions）？」
>
> **一句话结论**
> ★ 这两件事 Argo CD **自带**，都不需要 Actions、也不需要你写代码：
> ① **`/api/webhook`** —— GitHub push → Argo CD **立刻刷新**（把 3 分钟轮询降到秒级）。
>    ⚠️ **它只 refresh，不 apply**——同步仍然由自动收敛或外部驱动决定。
> ② **Notifications `service.github`** —— Argo CD 把同步结果**写回 GitHub**
>    （commit status / check run / deployment / PR 评论）。
>    ★ 这是"所有 trigger 都走 GitHub"闭环的**旁路**，也是无 Actions 体系的关键一环。

---

## 目录

| 章节 | 内容 |
|---|---|
| [`1](#1-勘误webhook-路径变了) | ★ 勘误：v3.5.6 只有 `/api/webhook` |
| [`2](#2-webhook-到底做了什么) | webhook 的真实语义（只 refresh） |
| [`3](#3-webhook-完整配置) | GitHub 侧 + Argo CD 侧 + 验证 |
| [`4](#4-notifications-四件套) | trigger / template / subscription / service |
| [`5](#5-回写-githubservicegithub) | ★ 把结果写回 GitHub 的四种通道 |
| [`6](#6-与-cr-check-的职责切分) | 三个 App 的权限边界 |
| [`7](#7-配置清单) | 可直接 apply 的 YAML |
| [`8](#8-坑清单) | 12 条坑 |

---

## 1. ★ 勘误：webhook 路径变了

**当前清单事实**（Argo CD v3.5.6，本仓库 `install.yaml` 对应版本）：

```
# upstream server/server.go:1263
mux.HandleFunc("/api/webhook", acdWebhookHandler.Handler)
```

**官方文档**（上游 v3.5.6 `docs/operator-manual/webhook.md`）也明确写：

> The payload URL configured in the Git provider should use the `/api/webhook` endpoint of your Argo CD instance
> (e.g. `https://argocd.example.com/api/webhook`).

| 写法 | 状态 |
|---|---|
| `https://argocd.example.com/api/webhook` | ✅ **v3.5.6 正确** |
| `https://argocd.example.com/api/webhook/github` | ❌ **v3.x 已不存在**（这是 v2.x 时代的路径） |

> ⚠️ **本仓库既有多处文档写的是 `/api/webhook/github`**
> （如 `argocd-admin-guide.md`、`argocd-application-guide.md`、`poc-argocd-git-to-apply-trigger.md`、
> `git-apps/12-webhook-push-vs-pull.md`、`git-apps/webhook-and-backend-service.md`）。
> **按 v3.5.6 部署时，请改用 `/api/webhook`**，否则 webhook 静默不生效（表现为"延迟没降下来"）。
>
> **部署前验证项**：在你们环境里直接探一下，两个路径都试：
```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' -d '{}' \
  https://argocd.example.com/api/webhook
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' -d '{}' \
  https://argocd.example.com/api/webhook/github
```
> 返回 **404** 的那个就是旧路径。

---

## 2. webhook 到底做了什么

**官方保证**（上游 `docs/operator-manual/webhook.md`）：

> Argo CD polls Git/OCI/Helm repositories **every three minutes** to detect changes to the manifests.
> To eliminate this delay from polling, the API server can be configured to receive webhook events.

| 问题 | 答案 |
|---|---|
| webhook 会**执行同步**吗？ | ❌ **不会**。webhook 的动作是 **refresh**（重新拉取 manifests + 重算 diff） |
| 那什么时候 apply？ | 由 `syncPolicy.automated` 决定（自动收敛），或由外部 driver 调 API 触发 |
| 能处理哪些事件？ | Git provider 的 push 类事件；GHCR 的 package 事件；**不支持 PR 事件** |
| 能区分分支和同名 tag 吗？ | ❌ 官方明确：**不区分**。push 到分支 `x` 也会刷新 `targetRevision: refs/tags/x` 的应用 |
| 支持哪些 Git provider？ | GitHub、GitLab、Bitbucket、Bitbucket Server、Azure DevOps、Gogs |
| 有鉴权吗？ | 共享 secret（**可选**）；不配也会处理——因为 payload 只导致 refresh，不产生副作用 |

> ★ **正确的心智模型**：
> ```
> webhook  =  "Git 变了，你不用再等了，现在就重新看一眼"
> auto-sync = "看完发现不一样，自动改"
> driver   = "看完发现不一样，我替你按按钮"
> ```
> 三者**串联**，不是替代关系。

---

## 3. webhook 完整配置

### 3.1 GitHub 侧（Repository webhook 或 Organization webhook）

| 项 | 值 | 说明 |
|---|---|---|
| Payload URL | `https://<argocd-host>/api/webhook` | ★ 见 `1 勘误 |
| Content type | `application/json` | ★ **必须是 json**；默认的 form-urlencoded **不被支持** |
| Secret | 任意值 | 与 Argo CD 侧一致 |
| Events | **Push events** | PR 事件不适用 |
| SSL | 有效证书 | GitHub 对无效证书会拒绝投递 |

> ★ **组织级 vs 仓库级**：Org webhook 一次覆盖所有仓库 → **强烈推荐 Org 级**，
> 否则新增仓库要手工补 webhook（这正是既有 [`11-github-app-concepts`](../git-apps/11-github-app-concepts.md) 讲的"安装/订阅/凭据/应用"四层拆解中的第二层）。

### 3.2 Argo CD 侧

```bash
# 共享 secret 放在 argocd-secret（官方推荐的 key）
kubectl -n argocd patch secret argocd-secret --type merge -p \
  '{"stringData":{"webhook.github.secret":"<与 GitHub 一致>"}}'
```

**或者**放到别的 Secret（官方支持的替代写法）：

```yaml
# data 的 key 以 $ 开头：$<secret_name>:<key_in_that_secret>
# ★ 该 Secret 必须带 label app.kubernetes.io/part-of: argocd
apiVersion: v1
kind: Secret
metadata:
  name: argocd-webhook-secret
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
stringData:
  github.secret: <与 GitHub 一致>
# → argocd-secret 里写：webhook.github.secret: "$argocd-webhook-secret:github.secret"
```

**限流保护**（官方建议，防 DDoS）：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  webhook.maxPayloadSizeMB: "10"   # 默认 50MB
```

> ★ **强烈建议配 secret**：官方原话——"If Argo CD is publicly accessible,
> then configuring a webhook secret is recommended to prevent a DDoS attack."
> 原因是 **`/api/webhook` 端点没有速率限制保护**。

### 3.3 验证

```bash
# ① 看 Argo CD 是否收到事件（argocd-server 日志）
kubectl -n argocd logs deploy/argocd-server | grep -i webhook | tail -20

# ② 确认 Application 被刷新（refresh 后 status.sync.revision 变化）
argocd app get <APP> --core

# ③ 确认延迟下降：push 后 <10s 内 Application 变成 OutOfSync
#    （对比：不配 webhook 时是 120s + 最多 60s jitter）
```

---

## 4. Notifications 四件套

**官方保证**（上游 `docs/operator-manual/notifications/`）：

| 对象 | 放在哪 | 作用 | 谁能改 |
|---|---|---|---|
| **Trigger** | `argocd-notifications-cm` 的 `trigger.<name>` | **什么时候**发（表达式谓词） | 管理员 |
| **Template** | `argocd-notifications-cm` 的 `template.<name>` | **发什么**（内容 + 各服务的 payload） | 管理员 |
| **Subscription** | Application / AppProject 上的 annotation | **谁订阅**（哪个服务/收件人） | 应用属主 |
| **Service** | `argocd-notifications-cm` 的 `service.<name>` | **怎么发**（Slack/Webhook/GitHub…） | 管理员 |

**官方 catalog 的 8 个 trigger**（**当前清单事实**，实测 `notifications_catalog/install.yaml`）：

| trigger | 触发条件（官方定义） |
|---|---|
| `on-created` | Application 被创建 |
| `on-deleted` | Application 被删除 |
| `on-deployed` | 同步成功 **且** 健康 == Healthy（带 `oncePer: app.status.sync.revision`） |
| `on-health-degraded` | 健康状态变为 degraded |
| `on-sync-failed` | 同步失败 |
| `on-sync-running` | 同步开始 |
| `on-sync-status-unknown` | 同步状态变为 Unknown |
| `on-sync-succeeded` | 同步成功 |

安装 catalog：

```bash
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml
```

> ⚠️ **注意**：catalog 里的 trigger/template 写在 `argocd-notifications-cm` 里，
> **这个 ConfigMap 是你们的"声明面"** → 用 GitOps 管理它（Argo CD 自己管它）。
> 但要注意：**别让 Argo CD 管自己所有的通知配置**（改了会立刻生效，可能刷屏）。

---

## 5. ★ 回写 GitHub：`service.github`

**官方保证**（上游 `docs/operator-manual/notifications/services/github.md`）：
`service.github` 用 **GitHub App** 身份工作，支持**四种回写通道**：

| 通道 | template 里的字段 | 落到 GitHub 的什么 | 用途 |
|---|---|---|---|
| **Commit status** | `github.status` | commit 上的状态（`state`/`label`/`targetURL`） | 在 commit 页面显示"部署成功/失败" |
| **Check run** | `github.checkRun` | check run（`name`/`status`/`conclusion`/`output`） | ★ **可以作为 required status check** |
| **Deployment** | `github.deployment` | deployment + deployment status（`environment`/`environmentURL`/`reference`） | ★ **配合 `required_deployments` 规则** |
| **PR comment** | `github.pullRequestComment` | PR 评论（带 `commentTag`，**upsert** 不刷屏） | 在 PR 上留部署结论 |

**参数**（官方）：

| 参数 | 说明 |
|---|---|
| `appID` | GitHub App ID |
| `installationID` | App installation ID |
| `privateKey` | App 私钥（放在 `argocd-notifications-secret`） |
| `enterpriseBaseURL` | **GHES 必填**，形如 `https://git.example.com/api/v3` |
| `maxIdleConns` / `maxIdleConnsPerHost` / `maxConnsPerHost` / `idleConnTimeout` | 连接池调优（可选） |

> ★ **Enterprise 自建版（GHES）注意**：官方明确标注
> "Specifying `/api/v3` in the `enterpriseBaseURL` is required until
> argoproj/notifications-engine#205 is resolved."
> → **GHES 必须带 `/api/v3` 后缀**。

**最小可用 template**：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.github: |
    appID: <app-id>
    installationID: <installation-id>
    privateKey: $github-privateKey
    # GHES 自建版才需要：
    # enterpriseBaseURL: https://git.example.com/api/v3

  template.app-deployed: |
    message: |
      Application {{.app.metadata.name}} 已部署新版本。
    github:
      repoURLPath: "{{.app.spec.source.repoURL}}"
      revisionPath: "{{.app.status.operationState.syncResult.revision}}"
      status:
        state: success
        label: "continuous-delivery/{{.app.metadata.name}}"
        targetURL: "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}"
      checkRun:
        name: "continuous-delivery/{{.app.metadata.name}}"
        details_url: "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}"
        status: completed
        conclusion: success
        output:
          title: "Argo CD 部署 {{.app.metadata.name}}"
          summary: "同步完成且健康检查通过。"
      deployment:
        state: success
        environment: production
        environmentURL: "https://{{.app.metadata.name}}.example.com"
        reference: "{{.app.status.operationState.syncResult.revision}}"
      pullRequestComment:
        content: |
          部署完成：{{.app.metadata.name}} @ {{.app.status.operationState.syncResult.revision}}
        commentTag: "continuous-delivery/{{.app.metadata.name}}"
```

**订阅**（打在 Application 或 AppProject 的 annotation 上）：

```yaml
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-deployed.github: ""
    notifications.argoproj.io/subscribe.on-sync-failed.github: ""
    notifications.argoproj.io/subscribe.on-sync-succeeded.github: ""
```

### 5.1 ★ 这解决了什么

| 没有它 | 有它 |
|---|---|
| 部署失败了，要人去 Argo CD UI 查 | commit 上直接看到 red |
| GitHub 上看不出"这个 PR 到底部署了没" | PR 上有部署结论评论（upsert，不刷屏） |
| 无法用 `required_deployments` 规则 | deployment 状态可被 ruleset 要求 |

> ⚠️ **官方限制**：commit status API 对**同一 SHA + 同一 context** 最多 1000 次尝试，
> 超过后返回 422；notification engine 会忽略这类错误并把通知标记为已完成。
> → **不要把 context 设成随时间变化的值**（比如带时间戳），否则很快撞上限。

---

## 6. 与 CR Check 的职责切分

**三个 GitHub App，三条线，互不越界**：

| App | 权限 | 干什么 | 不干什么 |
|---|---|---|---|
| **CR Check** | Checks: Write、Pull requests: Read | **判定合规**，写 check run | 不碰 deployment、不读集群 |
| **Argo CD（读代码）** | Contents: Read | 拉 manifests | 不写 check |
| **Argo CD Notifications** | Commit statuses: Write、Deployments: Write、Checks: Write、Pull requests: Write | **回写执行结果** | 不判定合规 |

> ★ **为什么 Notifications 要单独一个 App？**
> 因为它需要 **Deployments: Write** 和 **Commit statuses: Write**，
> 而 CR Check 只需要 Checks: Write。
> **权限越小，攻击面越小**；把"判定"和"播报"混在一个 App 里，
> 就等于给裁判发了一张"发合格证"的权限。

---

## 7. 配置清单

```bash
# ① GitHub App 侧：新建一个 App，权限 =
#      Commit statuses: Read & Write
#      Deployments: Read & Write
#      Checks: Read & Write
#      Pull requests: Read & Write
#      Contents: Read（读 repoURL 用）
#    订阅事件：不需要（Notifications 是主动写，不是被动收）

# ② 私钥放 Secret（用 kubectl create secret 更省事）
kubectl -n argocd create secret generic argocd-notifications-secret \
  --from-literal=github-privateKey=\$(cat github-private-key.pem) \
  --dry-run=client -o yaml | kubectl apply -f -

# ③ webhook secret
kubectl -n argocd patch secret argocd-secret --type merge -p \
  '{"stringData":{"webhook.github.secret":"<secret>"}}'

# ④ catalog + service + template（见 `4、`5）

# ⑤ 验证
kubectl -n argocd logs deploy/argocd-notifications-controller | tail -30
argocd app get <APP> --core   # 看 status 上有没有 notified.notifications.argoproj.io 注解
```

> ★ **注意**：`notified.notifications.argoproj.io` 注解在 `argocd-cm` 的
> `resource.customizations.ignoreResourceUpdates.argoproj.io_Application` 里被显式忽略
> （**当前清单事实**，实测 `install.yaml`）→ 所以它**不会**造成 Application 一直 OutOfSync。
> 这是一个容易踩的坑：如果你改了这段配置，Application 会永远显示 OutOfSync。

---

## 8. 坑清单

| # | 坑 | 后果 | 规避 |
|---|---|---|---|
| 1 | 用 `/api/webhook/github` | webhook 静默失效，延迟还是 3 分钟 | 见 `1 勘误，**实测两个路径** |
| 2 | Content type 用了默认 form-urlencoded | 事件解析失败 | 必须是 `application/json` |
| 3 | 只在仓库级配 webhook | 新仓库漏配 | 用 **Org 级 webhook** |
| 4 | 不配 webhook secret | 端点无速率限制，可被刷 | 配 secret + `webhook.maxPayloadSizeMB` |
| 5 | 以为 webhook 会触发同步 | 延迟降了但没人 apply | 明确 webhook=refresh；同步看 `automated`/driver |
| 6 | 以为 webhook 能处理 PR 事件 | PR 触发不了任何东西 | webhook 只吃 push；PR 判定交给 CR Check |
| 7 | 同名分支与 tag 互相刷新 | 应用被意外刷新 | 官方已知行为；分支/tag 命名区分开 |
| 8 | Notifications 的 GitHub App 权限给太大 | 攻击面大 | 拆成独立 App，只给 4 个写权限 |
| 9 | GHES 忘了 `/api/v3` 后缀 | 调 GitHub API 失败 | 按官方文档带 `/api/v3` |
| 10 | context 里带时间戳 | 撞 1000 次上限后静默失败 | context 用稳定值（如 `continuous-delivery/<app>`） |
| 11 | PR 评论不设 `commentTag` | 每次部署刷一条新评论 | 必须设 tag（upsert 语义） |
| 12 | 改了 `resource.customizations` 导致 Application 永远 OutOfSync | 全量应用假性 diff | 保留 `install.yaml` 里那段默认配置 |

---

## 关联文档

- 上一级：[`18 总体框架`](./18-framework-github-first-gitops.md)
- 无 Actions 的回写需求：[`19 替代方案矩阵`](./19-no-actions-alternative-matrix.md)
- 同步开关：[`21 同步窗口与自动同步`](./21-sync-windows-and-auto-sync.md)
- 部署保护与 merge queue：[`25 GitHub Environments`](./25-github-environments-and-deployment-protection.md)
- 既有：`git-apps/webhook-and-backend-service.md`（GitHub webhook ↔ 后端服务的心智模型）
