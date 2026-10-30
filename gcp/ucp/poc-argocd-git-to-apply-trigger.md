# ArgoCD Git → Apply 触发链路详解

> 配套文档：`poc-argocd-integration.md`（总体链路与 Crossplane 侧）、`poc-minimax.md`（PoC 方案）。
>
> 本文专门回答一个问题：**改了 Git 里的 YAML，到底经过哪几步才会真正变成集群里的 XR？**
>
> **事实来源分层**：
> 1. **项目事实**：`poc-argocd-integration.md` 原文与本仓库 `/Users/lex/git/gcp/` 的实际内容 —— 优先级最高。
> 2. **通用机制**：Argo CD **v3.5.6** 上游源码与官方文档（已逐行核对，见附录 A）—— 只用于解释机制，不用于替代项目事实。
> 3. `【待核实】` = 依赖实际集群/仓库状态，必须在目标环境实测确认。

---

## 0. 一句话答案

**改了 feature branch 的 YAML，不会触发部署。**

本方案里 `ApplicationSet.generators[].git.revision: main` 与 `Application.spec.source.targetRevision: main` **两处都写死 `main`**（`poc-argocd-integration.md` §3.3 第 207 行、§3.4 第 243/253 行）。PR 未合并前，改动既不在 generator 的扫描范围内，也不在 Application 的同步 revision 内。

**合并进 `main` 之后**链路是：

```
Git push/merge main
  └─▶ ① refresh    控制器得知"有新 commit"，重新解析 revision
        └─▶ ② reconcile  repo-server 取该 revision 的 manifest，算出 desired
              └─▶ ③ apply   application-controller diff live vs desired → 写 API Server
                    └─▶ ④ Crossplane  watch XR → Composition → MR → Provider → GCP
```

---

## 1. 先把三个"名字很像"的东西拆开

这是整篇文档最该先记住的一张表。三者名字高度相似，但**类别、职责、边界完全不同**：

| 名字 | 类别 | 职责 | **明确不负责** |
|---|---|---|---|
| `argocd-application-controller` | **组件（Deployment/Pod）** | watch `Application` 对象 + 目标集群资源，算 diff，执行 **apply / prune**，回写 `Application.status` | 不生成 Application；不决定同步策略；不碰 Git |
| `Application` | **CRD 对象**（每团队×项目一个） | 绑定「Git repoURL + path + targetRevision」→「集群 + namespace」，声明 `syncPolicy` | 不含任何执行逻辑，**本身不会改集群** |
| `ApplicationSet` | **CRD 对象** | 跑 **generator**（本方案：Git generator 扫目录树），**批量创建/更新 `Application` 对象** | **不拉 manifest、不 diff、不 apply**、不感知集群实际状态 |

> **精确职责边界（逐条对照上游源码）：**
>
> - **`applicationset-controller`** = *generator runner*。
>   输入：generator 参数 + Git 目录树。输出：Application 对象的期望形态。
>   上游 `controller/appsetcontroller/ac-as.go` 的主循环是「跑 generator → `createOrUpdateInCluster` 创建/更新 `Application` 对象」，
>   **代码里没有任何 apply 到目标集群的路径**。
>
> - **`repo-server`** = *Git/manifest 服务*。
>   输入：repoURL + revision + path。输出：渲染后的 manifest + commit SHA，**带缓存**。
>
> - **`application-controller`** = *reconciler*。
>   输入：Application 期望态 + 集群实际态。输出：apply/prune 操作 + `Application.status`。

**三个组件互相不能替代：**
- `applicationset-controller` 挂了 → 没有 Application 对象 → `application-controller` 无事可做；
- `application-controller` 挂了 → Application 对象存在但永远不会 apply；
- `repo-server` 挂了 → 两者都拿不到 manifest。

---

## 2. 三个阶段必须分开谈

最容易被混为一谈的地方。「ArgoCD 自动同步」其实横跨三个**独立**阶段，各自有不同的触发源和失败表现：

| 阶段 | 干什么 | 触发源 | 失败表现 |
|---|---|---|---|
| **① refresh** | 让控制器知道"有新 commit" | Git webhook **或** 周期 resync | 无感，只是延迟累积 |
| **② reconcile** | 解析 targetRevision → 取 manifest → 算 desired vs live | Application 事件 / 周期 resync | `OutOfSync` / `Unknown` / `ComparisonError` |
| **③ apply** | 把 desired 写进 API Server | `syncPolicy.automated` 开启且 OutOfSync | `SyncError` / 资源 `Pending` |
| **④ Crossplane 响应** | XR → MR → GCP → status 回写 | API Server watch 事件 | XR `Ready=False` |

**关键认知：webhook 只影响阶段 ① 的延迟，不决定 ②③④ 是否发生。**

丢掉 webhook → 退化为周期轮询（见 §3.1 的三个周期），**不会永久卡住**。这是 Argo CD 声明式设计的基础：所有状态最终由 reconcile 收敛，不依赖消息送达。

---

## 3. 阶段 ①：谁让 Argo CD 知道 `main` 变了

**这一节有三条独立的路径，且它们是三个不同的组件在跑 —— 这是最容易搞混的地方。**

### 3.1 路径一：ApplicationSet 的 webhook（`applicationset-controller` 自己的）

上游 v3.5.6 的 `manifests/install.yaml` 里确实存在一个**独立的 ClusterIP Service**：

```yaml
kind: Service
metadata:
  name: argocd-applicationset-controller
  labels:
    app.kubernetes.io/component: applicationset-controller
spec:
  ports:
  - name: webhook
    port: 7000
    protocol: TCP
    targetPort: webhook
  - name: metrics
    port: 8080
    protocol: TCP
    targetPort: metrics
  selector:
    app.kubernetes.io/name: argocd-applicationset-controller
```

对应 Deployment 里的容器端口：`containerPort: 7000`（name `webhook`）、`containerPort: 8080`（name `metrics`）。

**重要区别**（上游 `docs/operator-manual/applicationset/Generators-Git.md` 原文明确写了）：

> The ApplicationSet controller webhook **does not use the same API server webhook**.
> ApplicationSet exposes a webhook server as a **service of type ClusterIP**.
> An ApplicationSet specific **Ingress** resource needs to be created to expose this service to the webhook source.

所以：
- ApplicationSet webhook 端点 = `argocd-applicationset-controller:7000/api/webhook`（ClusterIP，**需要自建 Ingress** 才能从 Git provider 访问）。
- Argo CD API server webhook 端点 = `argocd-server:80|443/api/webhook`（Service 端口 80→8080 / 443→8080）。

**两套 webhook 是不同的东西、不同的 Service、不同的用途。**

ApplicationSet webhook 的匹配逻辑（上游 `applicationset/webhook/webhook.go`）：

```go
// webhook.go: HandleEvent
appSetList := &v1alpha1.ApplicationSetList{}
h.client.List(ctx, appSetList, ...)          // 列出所有 ApplicationSet
for _, appSet := range appSetList.Items {
    for _, gen := range appSet.Spec.Generators {
        shouldRefresh = shouldRefreshGitGenerator(gen.Git, gitGenInfo) || ...
        if shouldRefresh { break }
    }
    if shouldRefresh {
        refreshApplicationSet(h.client, &appSet)   // 打 refresh 注解，触发立即重生成
    }
}
```

匹配判据（上游 `webhook.go` `genRevisionHasChanged`）：

```go
func genRevisionHasChanged(gen *v1alpha1.GitGenerator, revision string, touchedHead bool) bool {
    targetRev := webhook.ParseRevision(gen.Revision)
    if targetRev == "HEAD" || targetRev == "" {   // revision is head
        return touchedHead                          // 只有推默认分支才刷新
    }
    return targetRev == revision || gen.Revision == revision
}
```

> **对本方案的直接推论**：本方案 `git.revision: main`（不是 `HEAD`），
> 所以只有 **`main` 分支**的 push 事件才会触发 ApplicationSet 重新生成。
> **feature branch 的 push 会匹配不上 → 不刷新 → 不生成任何东西。**
> 这从源码层面确认了 §0 的结论。

Webhook 事件类型（上游 `webhook.go` `Handler`）：支持 GitHub（`X-GitHub-Event`）、GitLab（`X-Gitlab-Event`）、Azure DevOps（`X-Vss-Activityid`）；未知事件返回 400。
GitHub 时 Content-Type 必须为 `application/json`（`application/x-www-form-urlencoded` 不支持）。

### 3.2 路径二：ApplicationSet 的周期 requeue（兜底，**默认 3 分钟**）

上游 `applicationset/generators/interface.go`（v3.5.6）：

```go
const (
    DefaultRequeueAfter = 3 * time.Minute
)

func getDefaultRequeueAfter() time.Duration {
    // Default is 3 minutes, min is 1 second, max is 1 year
    return env.ParseDurationFromEnv("ARGOCD_APPLICATIONSET_CONTROLLER_REQUEUE_AFTER",
                                    DefaultRequeueAfter, 1*time.Second, 8760*time.Hour)
}
```

Git generator 的取值（上游 `applicationset/generators/git.go`）：

```go
func (g *GitGenerator) GetRequeueAfter(appSetGenerator *v1alpha1.ApplicationSetGenerator) time.Duration {
    if appSetGenerator.Git.RequeueAfterSeconds != nil {
        return time.Duration(*appSetGenerator.Git.RequeueAfterSeconds) * time.Second
    }
    return getDefaultRequeueAfter()      // 默认 3 分钟
}
```

- **默认 3 分钟**，可用环境变量 `ARGOCD_APPLICATIONSET_CONTROLLER_REQUEUE_AFTER` 全局覆盖（范围 1s ~ 8760h）。
- 也可在 generator 上按 generator 覆盖：`git.requeueAfterSeconds`（上游示例值 `180`）。
- **注意方向性**：requeue 是 ApplicationSet controller 的**兜底轮询**，独立于 webhook。webhook 丢了，最多延迟 3 分钟收敛，**不会永久卡住**。

### 3.3 路径三：application-controller 的周期 resync（**默认 120 秒 + 60 秒 jitter**）

上游 `cmd/argocd-application-controller/commands/argocd_application_controller.go`（v3.5.6）：

```go
defaultAppResyncPeriod          = 120   // 秒
defaultAppResyncPeriodJitter    = 60    // 秒
defaultAppHardResyncPeriod      = 0     // 0 = 关闭
defaultRepoErrorGracePeriod     = defaultAppResyncPeriod + defaultAppResyncPeriodJitter  // 180

command.Flags().Int64Var(&appResyncPeriod, "app-resync",
    int64(env.ParseDurationFromEnv("ARGOCD_RECONCILIATION_TIMEOUT",
        defaultAppResyncPeriod*time.Second, ...).Seconds()),
    "Time period in seconds for application resync.")
command.Flags().Int64Var(&appHardResyncPeriod, "app-hard-resync",
    int64(env.ParseDurationFromEnv("ARGOCD_HARD_RECONCILIATION_TIMEOUT",
        defaultAppHardResyncPeriod*time.Second, ...).Seconds()), ...)
command.Flags().Int64Var(&appResyncJitter, "app-resync-jitter",
    int64(env.ParseDurationFromEnv("ARGOCD_RECONCILIATION_JITTER",
        defaultAppResyncPeriodJitter*time.Second, ...).Seconds()), ...)
```

同时 `argocd-cm` 的 `timeout.reconciliation`（上游 `docs/operator-manual/argocd-cm.yaml` v3.5.6 默认值）：

```yaml
# Application reconciliation timeout is the amount of time spent before Argo tries to discover if a new manifests
# version got published to the repository. Reconciliation by timeout is disabled if timeout is set to 0.
# Two minutes by default with additional jitter.
# For the argocd-repo-server this setting defines the expiration value for cached git revisions.
timeout.reconciliation: 120s
timeout.reconciliation.jitter: 60s
```

**注意 `timeout.reconciliation` 一字两义**（官方注释写得很清楚）：
- 对 **application-controller**：周期性 reconcile 的间隔（120s + 最多 60s jitter）。
- 对 **repo-server**：**cached git revisions 的过期时间**。

> 这解释了 §4.2 里"刚 merge 的提交不会立刻出现"的现象 —— 那是 repo-server 的 git revision 缓存没过期。

### 3.4 三条路径汇总

| 路径 | 组件 | 默认间隔 | 环境变量 / 字段 | 作用对象 |
|---|---|---|---|---|
| ApplicationSet webhook | `argocd-applicationset-controller`（:7000） | 事件驱动 | `argocd-secret` 里 `webhook.github.secret` | 重新生成 `Application` |
| ApplicationSet requeue | `applicationset-controller` | **180s** | `ARGOCD_APPLICATIONSET_CONTROLLER_REQUEUE_AFTER` / `git.requeueAfterSeconds` | 重新生成 `Application` |
| Application resync | `application-controller` | **120s + 60s jitter** | `ARGOCD_RECONCILIATION_TIMEOUT` / `ARGOCD_RECONCILIATION_JITTER` / `timeout.reconciliation` | 刷新 manifest + diff + apply |
| Argo CD API webhook | `argocd-server`（:80/:443） | 事件驱动 | 同上 secret | 刷新 `Application` |

> **本方案的延迟预期**（`poc-argocd-integration.md` §5 第 631 行写的是"默认 2 分钟"）：
> 源码级结论是 **application-controller 侧 120s + 最多 60s jitter ≈ 2~3 分钟**，
> 与 POC 的表述一致；**ApplicationSet 侧是 180s**，只影响"新建/删除项目目录"这类需要重新生成 Application 的场景。

### 3.5 手工触发（排障必备）

```bash
# 刷新 Application（重新拉 manifest + diff）
kubectl annotate application <name> -n argocd argocd.argoproj.io/refresh=hard --overwrite

# 刷新 ApplicationSet（重新跑 generator）
kubectl annotate applicationset <name> -n argocd argocd.argoproj.io/refresh=hard --overwrite

# CLI 等价物
argocd app get <name> --refresh
argocd appset get <name> --refresh
```

上游 `ac-as.go` 证实 ApplicationSet 支持 refresh 注解，且只在**新添加**该注解时立即 requeue：

```go
// Requeue only when the refresh annotation is newly added to the ApplicationSet.
_, oldHasRefreshAnnotation := appSetOld.Annotations[common.AnnotationApplicationSetRefresh]
_, newHasRefreshAnnotation := appSetNew.Annotations[common.AnnotationApplicationSetRefresh]
if oldHasRefreshAnnotation && !newHasRefreshAnnotation { return false }
```

---

## 4. 阶段 ②：repo-server 解析与渲染

### 4.1 输入输出

- 输入：`Application.spec.source.repoURL` + **`targetRevision`** + `path`。
- `targetRevision: main` → repo-server 解析 `main` 当前 commit SHA → 拉取/复用该 SHA 的 manifest。
- 输出：渲染后的 manifest + commit SHA，**带缓存**。

### 4.2 缓存（这是"merge 了却没反应"的常见原因）

`timeout.reconciliation: 120s` 对 repo-server 而言就是 **cached git revisions 的过期时间**（上游注释原文）。
所以刚 merge 的提交可能不会**立刻**出现 —— 等缓存过期，或手工 `refresh=hard`。

同时 repo-server 还有一层 **rendered manifests 缓存**（按 revision + path 复用渲染结果），避免每次全量渲染。

### 4.3 repo-server 不决定是否 apply

它只是"内容供应方"。是否同步由 `application-controller` 依据 `Application.spec.syncPolicy` 判断。

---

## 5. 阶段 ③：application-controller 的 diff + apply

- 它 watch `Application` 对象 + 目标集群的 live 资源。
- 两者不一致 → 状态变 `OutOfSync` → 若 `syncPolicy.automated` 开启 → 执行同步。

本方案的 `syncPolicy`（`poc-argocd-integration.md` §3.3 第 215-220 行）：

```yaml
syncPolicy:
  automated:
    prune: false      # 不自动删（避免删掉 Git 文件 = 删云上集群）
    selfHeal: true    # live 被手工改回 → 自动改回 Git 状态
  syncOptions:
  - CreateNamespace=true
  - ServerSideApply=true
  - PruneLast=true
```

**`selfHeal` 与 `prune` 的准确语义**（详见 `poc-argocd-integration.md` §6.3、§6.4）：

| | 触发条件 | 行为 |
|---|---|---|
| `selfHeal: true` | live 资源被**手工改掉** | Argo CD 把它**改回 Git 的期望值** |
| `prune: false` | Git 里**删掉了**文件 | **不删**集群资源 → 资源残留，需人工清理 |

> ⚠️ **注意 `prune: false` 带来的一个副作用**：手工 `kubectl delete xr` 会被 `selfHeal: true` **撤销**（XR 被 Argo CD 复活）。这是 `poc-argocd-integration.md` §6.4 明确写过的坑。

**`ServerSideApply=true`**：字段所有权交给 K8s 决定，避免 Argo CD 与其他 SSA 客户端互相抢字段。
**`CreateNamespace=true`**：目标 namespace 不存在时自动创建（省掉手工建 ns）。

### 5.1 apply 的目标就是普通 K8s 资源 —— 包括 XR

Argo CD **完全不知道 Crossplane 存在**。它 apply 的目标是一个普通的 CR（`GKECluster`，一个 XRD 定义的复合资源）。
Crossplane 的存在对 Argo CD 而言不可见、也不需要可见。

---

## 6. 阶段 ④：Crossplane 接手 —— "唯一总线"的准确含义

### 6.1 状态回路

```
Argo CD apply XR (GKECluster)
   └─▶ K8s API Server（唯一总线）
         └─▶ Crossplane Core 的 informer 收到 ADDED/MODIFIED
               └─▶ function-go-templating（gRPC over stdin/stdout）→ 得到期望 MR（Cluster + NodePool）
                     └─▶ 写 API Server
                           └─▶ provider-gcp-container watch MR → Workload Identity token → container.googleapis.com
                                 └─▶ Provider 回写 MR.status.atProvider
                                       └─▶ Core 聚合 MR 状态 → 回写 XR.status.conditions
                                             └─▶ Argo CD watch 到 live 变化 → Application.status 更新
```

### 6.2 "K8s API Server 是唯一总线"到底是什么意思

**它不表示各控制器互相 RPC 调用。** 它的含义是：

- 四个控制平面（Git / Argo CD / Crossplane / GCP）**不建立点对点连接**；
- 它们的**唯一交汇点**是 Kubernetes API Server；
- 每个控制平面通过 **API Server 声明期望状态（write spec）** 和 **监听实际状态（watch）** 来协作；
- 一个控制平面**不需要知道**另一个控制平面的存在，也不需要对方的 API。

因此在本方案里：

| 谁 | 写什么 | 读什么 |
|---|---|---|
| Argo CD | XR 的 `spec` / `metadata` | XR 的 `status`（用于算 diff） |
| Crossplane Core | MR 的 `spec`、XR 的 `status` | XR 的 `spec` |
| Provider | MR 的 `status.atProvider` | MR 的 `spec` |
| Git | YAML 文件 | — |

**字段所有权天然分离**（`poc-argocd-integration.md` §6.1 第 644 行起）：Argo CD 只碰 `spec`，Crossplane 只碰 `status` → **不需要任何额外接线**。

### 6.3 Argo CD 是怎么"看到" Crossplane 的变化的

不是靠回调。Argo CD 通过 watch 同一批资源感知到 live 状态变了，用于计算 OutOfSync / health。
反过来，**如果有人直接 `kubectl edit xr` 改了 `spec`**，Argo CD 的 `selfHeal: true` 会把它改回去（`poc-argocd-integration.md` §6.1、§6.4）。

---

## 7. `revision` 与 `targetRevision` —— 必须分清

这是全文最容易出错的地方。四个字段，两个组件：

| 字段 | 所属对象 | 作用 | 本方案取值 |
|---|---|---|---|
| `ApplicationSet.spec.generators[].git.revision` | ApplicationSet | generator **扫描哪个 revision 的目录树**（决定生成/删除哪些 Application） | `main`（原文档 §3.4 第 243 行） |
| `ApplicationSet.spec.template.spec.source.targetRevision` | ApplicationSet 模板 | 生成出的 Application **同步哪个 revision** | `main`（原文档 §3.4 第 253 行） |
| `Application.spec.source.targetRevision` | Application（实际对象） | **实际同步哪个 revision**（可被单独改；ApplicationSet 下次 reconcile 可能覆盖回去） | `main`（原文档 §3.3 第 207 行） |
| `ApplicationSet.spec.generators[].git.requeueAfterSeconds` | ApplicationSet | generator 周期 requeue 间隔（**这是兜底，不是 webhook**） | **未配置 → 默认 180s** |

**两者可以不同**，常见的另一种设计：

- `generator.revision: main` + `template.targetRevision: '{{.branch}}'` → 按 `main` 的目录结构生成，但每个分支一个 Application（分支预览）。
- 本方案**两者都是 `main`**，所以分支内容不进生产。

---

## 8. 四类 Git 变化的真实行为

| 变化 | ApplicationSet 动作 | Application 动作 | 结果 |
|---|---|---|---|
| **(a)** 在 `main` 上修改**已纳管目录**里的 YAML | 无需重新生成（目录树没变） | main SHA 变 → OutOfSync → apply | ✅ **部署** |
| **(b)** 在 `main` 上**新增/删除项目目录** | generator 发现目录树变化 → **创建/删除 Application**（最多等 180s 或 webhook） | 新 Application 开始同步 | ✅ 新项目上线 / ⚠️ 删目录时按 `preserveResourcesOnDeletion` 等策略处理 |
| **(c)** 修改 feature branch / PR 内容 | generator 不扫该分支 → 不生成 | targetRevision 是 `main` → 不看该分支 | ❌ **不部署**（预期行为） |
| **(d)** PR 合并进 `main` | 视目录树是否变化 | main SHA 变 → apply | ✅ **部署** |

### 8.1 PR 的三个关键澄清

1. **PR 分支不会被 webhook 触发部署。**
   ApplicationSet webhook 的 `genRevisionHasChanged` 要求 `gen.Revision == revision`（即 `main`），feature branch 匹配不上。

2. **未合并的 PR 永远不会成为部署源。**
   无论是 generator 的扫描 revision，还是 Application 的 `targetRevision`，都是 `main`。PR 内容不在任何一者的范围内。

3. **PR 合并后，是 `main` 的新 commit SHA 触发 apply**，不是"PR 事件"触发的。
   合并动作本身只是让 `main` 前进了一个 SHA；后续流程与"直接 push 到 main"完全一致。

---

## 9. PR 预览怎么加（本方案未配）

上游 v3.5.6 的 **Pull Request generator** 可以让每个 PR 生成一个独立 Application。

上游 `applicationset/generators/pull_request.go`：

```go
const (
    DefaultPullRequestRequeueAfter = 30 * time.Minute
)

func (g *PullRequestGenerator) GetRequeueAfter(...) time.Duration {
    // Return a requeue default of 30 minutes, if no default is specified.
    if appSetGenerator.PullRequest.RequeueAfterSeconds != nil {
        return time.Duration(*appSetGenerator.PullRequest.RequeueAfterSeconds) * time.Second
    }
    return DefaultPullRequestRequeueAfter
}
```

> **注意 PR generator 的默认 requeue 是 30 分钟**（比 Git generator 的 3 分钟长得多）—— 想及时感知 PR 变更必须显式配 `requeueAfterSeconds` 或配 webhook。

上游文档示例（`docs/operator-manual/applicationset/Generators-Pull-Request.md`）：

```yaml
spec:
  generators:
    - pullRequest:
        github:
          owner: <org>
          repo: ucp-platform
          # tokenRef: ...   # GitHub App token / SCM provider
  template:
    spec:
      source:
        repoURL: git@github.com:<org>/ucp-platform.git
        targetRevision: '{{.head_sha}}'      # v3.5.6 文档示例
        path: 'teams/{{.path.*}}'
```

可用模板变量包括：`head_sha`（PR 头提交 SHA）、`author`、`branch` 等（上游文档第 444 行起）。

**代价（必须提前决策）：**

| 代价 | 说明 |
|---|---|
| Application 数量线性增长 | 每个 PR 一个 Application → application-controller 负载与 API Server 压力上升（上游默认 `--status-processors 20`、`--operation-processors 10`） |
| 命名空间打架 | PR Application 与 main Application 若写同一个 namespace，可能互相覆盖 → **必须用独立 namespace**（如 `pr-1234`）或独立集群 |
| 凭据面变大 | 需要 GitHub App / SCM provider token + webhook 配置 |
| 删除语义复杂 | PR 关闭后 Application 是否自动删除、集群资源是否残留，要额外策略 |

> **建议**：POC 阶段**不做 PR 自动部署**。用「PR 预览环境（独立集群或独立 namespace）+ PR generator」并严格限流；或维持现状，靠 CI 渲染校验 + 人工合并验证。

---

## 10. 项目现状核对：**到底配没配 `Application` / `ApplicationSet`？**

### 10.1 设计层面：**配了**

`poc-argocd-integration.md` 里给出了完整的三个对象：

| 对象 | 位置 | 状态 |
|---|---|---|
| `Application` CRD | 原文档 §3.3（第 194-227 行） | ✅ 有完整 YAML，含 `targetRevision: main` / `prune: false` / `selfHeal: true` / `ServerSideApply=true` |
| `ApplicationSet` CRD | 原文档 §3.4（第 228-277 行） | ✅ 有完整 YAML，Git generator + `directories: teams/team-a/*` + 模板 `targetRevision: main` |
| `AppProject` | 原文档 §3.5（第 279-308 行） | ✅ 团队权限边界 |
| Git 凭据 | 原文档 §3.6（第 309-338 行） | ✅ 私有仓库必配 |

### 10.2 仓库落地层面：**还没落地**

实测 `/Users/lex/git/gcp/` 全仓库：

```bash
$ grep -rl --include='*.yaml' --include='*.yml' -E 'kind:\s*(ApplicationSet|Application)\b' .
（无输出 —— 0 命中）

$ find . -name '*.yaml' -o -name '*.yml' | grep -v '/\.git/' | wc -l
118
```

- 全仓库 **118 个 YAML**，**0 个** `kind: Application` 或 `kind: ApplicationSet`。
- `/Users/lex/git/gcp/ucp/` 目录下只有 4 个 `.md` 文档（`poc-argocd-integration.md`、`poc-minimax.md`、`poc.md`、`requirement.md`），**没有任何 manifest**。

**结论：方案在设计层面完整，但尚未落成可下发到集群的实际对象。**

> 这也意味着：Mermaid 图里的 `applicationset-controller` 节点**只是架构角色标注**，不是"集群里已存在这个对象"。二者不能混为一谈。

### 10.3 验收命令（在 Argo CD 集群执行）

```bash
# 1) ApplicationSet 是否存在
kubectl get applicationsets -n argocd
kubectl get applicationset team-a-xr -n argocd -o yaml | yq '.spec.generators, .spec.template.spec.source'

# 2) Application 是否被生成
kubectl get applications -n argocd
kubectl get application team-a-project-a -n argocd \
  -o jsonpath='{.spec.source.targetRevision}{"\n"}{.status.sync.status}{"\n"}{.status.health.status}{"\n"}'

# 3) 确认 generator 真的在跑 + requeue 间隔
kubectl logs -n argocd deploy/argocd-applicationset-controller --tail=100 | grep -i -E 'generator|requeue'

# 4) 确认 application-controller 在周期 reconcile
kubectl logs -n argocd deploy/argocd-application-controller --tail=100 | grep -i -E 'reconciliation|compare|result'

# 5) 确认 repo-server 缓存与解析
kubectl logs -n argocd deploy/argocd-repo-server --tail=100 | grep -i -E 'manifest|revision|cache'

# 6) 确认两套 webhook Service 都在（appset :7000 / server :80,:443）
kubectl get svc -n argocd | grep -E 'argocd-server|applicationset'
kubectl get svc -n argocd argocd-applicationset-controller -o jsonpath='{.spec.ports}{"\n"}'

# 7) 确认实际的 resync / requeue 生效值（可能被环境变量改过）
kubectl get deploy -n argocd argocd-application-controller -o yaml | grep -A1 -E 'ARGOCD_RECONCILIATION_TIMEOUT|ARGOCD_RECONCILIATION_JITTER'
kubectl get cm -n argocd argocd-cm -o yaml | grep -E 'timeout.reconciliation'
```

---

## 11. 失败与恢复矩阵

| 症状 | 根因 | 判定命令 | 恢复动作 |
|---|---|---|---|
| Git 已合并，集群 10 分钟没变 | webhook 丢失 → 等周期 resync（120s+60s jitter / appset 180s） | `kubectl logs -n argocd deploy/argocd-application-controller \| grep reconciliation` | 手工 `refresh=hard`；修 Git webhook |
| Application 状态仍是旧 commit SHA | repo-server manifest / git revision 缓存（`timeout.reconciliation` = 120s） | `kubectl logs -n argocd deploy/argocd-repo-server \| grep cache` | 等缓存过期或 `refresh=hard` |
| Application 根本没出现 | generator 没跑到 / 目录树不匹配 / webhook 没到 appset | `kubectl get applicationsets -n argocd`；appset controller 日志 | 校验 `repoURL`、`revision`、`directories` glob、仓库凭据；确认 appset webhook Ingress 通 |
| `ComparisonError` / `SyncError` | CRD/XRD 未装、字段非法、RBAC 不足 | `kubectl describe application <name>` | 先装 XRD/CRD，再 `argocd app sync` |
| live 资源被手工改了 | `selfHeal: true` 会**改回** | `kubectl get application <name> -o jsonpath='{.status}'` | 等自动 heal；必要时 `sync` |
| 手工 `kubectl delete xr` 后 XR 又回来了 | `selfHeal: true` **会撤销删除** | `kubectl get xr -A` | 这是预期行为；真要删需先改 `selfHeal` 或从 Git 移除 |
| Git 删了文件，资源还在 | `prune: false` 的**预期结果** | 对比 Git 目录与集群资源 | 人工确认后删除，或为特定 App 单独开 prune |
| PR 合并了但没部署 | PR 内容从未进入 `main`；或 `targetRevision` 不是 `main` | `kubectl get application -o jsonpath='{.spec.source.targetRevision}'` | 确认分支策略；需要预览则加 PR generator |
| 只有"新增项目"不生效，"改已有项目"正常 | ApplicationSet generator 没重新跑（requeue 180s / webhook 未达） | `kubectl logs -n argocd deploy/argocd-applicationset-controller \| grep requeue` | `kubectl annotate applicationset ... argocd.argoproj.io/refresh=hard` |

---

## 12. 落地建议（按优先级）

1. **先把对象建出来再谈自动化**
   把原文档 §3.3 / §3.4 / §3.5 / §3.6 的 YAML 落成实际 manifest（建议放 `ucp-platform` 的 `argocd/` 目录，用 **App of Apps** 统一管）。
   **当前仓库 0 个 manifest = 链路根本还没闭环。**

2. **明确 revision 策略并写进文档**
   当前"只认 main"是隐含的。至少在 `ApplicationSet` 注释和团队规范里写明：
   > 变更必须合入 `main` 才生产；feature branch 仅用于 PR 评审。

3. **两套 webhook 都要配，且别搞混**
   - `argocd-server` 的 `/api/webhook` → 刷新 **Application**（降 apply 延迟）。
   - `argocd-applicationset-controller:7000` 的 `/api/webhook` → 刷新 **ApplicationSet**（降"新增项目"延迟），**需要自建 Ingress**（ClusterIP）。
   - **周期兜底必须保留**：ApplicationSet 180s、application-controller 120s(+60s jitter)。**不要把 webhook 当唯一触发源。**

4. **分清四个旋钮，别对症下药**
   | 旋钮 | 默认 | 管什么 |
   |---|---|---|
   | `ARGOCD_APPLICATIONSET_CONTROLLER_REQUEUE_AFTER` | 180s | appset generator 重新生成 Application |
   | `ARGOCD_RECONCILIATION_TIMEOUT` / `timeout.reconciliation` | 120s | app-controller 周期 reconcile + repo-server git revision 缓存 |
   | `ARGOCD_RECONCILIATION_JITTER` | 60s | 上述的 jitter |
   | `timeout.reconciliation.jitter` | 60s | 同上（cm 侧） |

5. **`prune` 保持 `false` 起步**
   等"目录删除 → 资源清理"有明确审批与保护名单后，再逐项目放开。同时在团队规范里写明 `selfHeal: true` 会撤销手工删除。

6. **CI 做渲染校验**（Argo CD 侧不负责）
   `argocd app diff` / `kustomize build` / `kubeconform` + Crossplane XRD schema 校验，PR 上给出 diff 预览。

7. **PR 预览单独决策**
   先手工/临时 namespace 验证，再考虑 PR generator。必须同时定下 namespace 隔离策略，避免 PR 与 main 打架。注意 PR generator 默认 requeue 是 **30 分钟**，需显式调小或配 webhook。

8. **`Application` 对象不要长期手工改**
   ApplicationSet reconcile 会覆盖被改动的字段。确需长期偏离，用**另一个独立的 Application**，或用 `ignoreDifferences`。

9. **可观测性**
   给 `Application` 打上 `team`/`project` 标签；用 `argocd app list` 做巡检；把 `status.sync.status=OutOfSync` 与 `health.status=Degraded` 做成告警。

10. **命名一致性**（原文档 §3.4 已强调，此处再钉一次）
    `目录名 = namespace 名 = AppProject.destination 允许值`。三处不一致 → Argo CD 直接拒绝同步。

---

## 13. 速查：一次 merge 的完整链路

```
1.  Dev push feature/x → PR → review → merge → main
2.  Git provider → argocd-server:/api/webhook          （刷新 Application，秒级）
    或 → argocd-applicationset-controller:7000/api/webhook（刷新 ApplicationSet）
    或 等周期：app-controller 120s(+60s jitter) / appset 180s
3.  application-controller refresh：解析 targetRevision=main → 得到新 commit SHA
4.  repo-server：取该 SHA + path 的 manifest（渲染缓存命中则复用；git revision 缓存 120s）
5.  application-controller：diff desired vs live → OutOfSync
6.  syncPolicy.automated 开启 → apply（CreateNamespace / ServerSideApply / PruneLast）
7.  K8s API Server：XR (GKECluster) 被创建/更新
8.  Crossplane Core watch → composition(function-go-templating) → MR (Cluster + NodePool)
9.  provider-gcp-container watch MR → WI token → container.googleapis.com
10. Provider 回写 MR.status.atProvider → Core 聚合 → XR.status.conditions
11. Argo CD watch 到 live 变化 → Application.status 更新为 Synced / Healthy
```

**任何一步断了都不会"自动补偿到正确"**，需要按 §11 矩阵定位。

---

## 附录 A. 核实来源

### 项目内（优先级最高）

| 来源 | 位置 |
|---|---|
| Argo CD 组件职责表 | 原文档 §3.2（第 179-192 行） |
| `Application` CRD YAML（`targetRevision: main` / `prune: false` / `selfHeal: true` / `ServerSideApply=true`） | 原文档 §3.3（第 194-227 行） |
| `ApplicationSet` CRD YAML（Git generator `revision: main` + `directories: teams/team-a/*` + 模板 `targetRevision: main`） | 原文档 §3.4（第 228-277 行） |
| `AppProject` | 原文档 §3.5（第 279-308 行） |
| Git 凭据 | 原文档 §3.6（第 309-338 行） |
| 目标集群权限 | 原文档 §3.7（第 339-374 行） |
| `argocd-cm` 哪些真要配 | 原文档 §3.8（第 375-412 行） |
| 端到端时序 | 原文档 §5（第 581-626 行） |
| **延迟预期表（"Git → ArgoCD 发现 commit 默认 2 分钟"）** | 原文档 §5（第 627-638 行） |
| 字段所有权（ArgoCD 只碰 spec / Crossplane 只碰 status） | 原文档 §6.1（第 644-663 行） |
| `prune` 风险矩阵（A 只增不删 / B 孤儿化 / C 全量跟随） | 原文档 §6.3（第 690-715 行） |
| `selfHeal` 语义 | 原文档 §6.4（第 716-731 行） |
| 排查手册 | 原文档 §7（第 763-780 行） |
| 仓库实测：`grep -rl -E 'kind:\s*(ApplicationSet|Application)\b'` → 0 命中；118 个 YAML | `/Users/lex/git/gcp/` |

### 上游 Argo CD v3.5.6（缓存在 scratch，未写入项目目录）

| 结论 | 来源 |
|---|---|
| `DefaultRequeueAfter = 3 * time.Minute`；`getDefaultRequeueAfter()` 读 `ARGOCD_APPLICATIONSET_CONTROLLER_REQUEUE_AFTER`（1s~8760h） | `applicationset/generators/interface.go` |
| Git generator 优先用 `git.requeueAfterSeconds`，否则 3 分钟 | `applicationset/generators/git.go` |
| PR generator 默认 30 分钟（`DefaultPullRequestRequeueAfter`） | `applicationset/generators/pull_request.go` |
| ApplicationSet webhook：独立 handler、事件类型、repoURL/revision 匹配、refresh 注解 | `applicationset/webhook/webhook.go` |
| `genRevisionHasChanged`：`revision: HEAD` 只在 touchedHead 时刷新；否则精确匹配 | 同上 |
| appset-controller 主循环 = generator + `createOrUpdateInCluster`（无 apply 路径）；refresh 注解触发 requeue | `controller/appsetcontroller/ac-as.go` |
| ApplicationSet **有独立 ClusterIP webhook Service，端口 7000**；argocd-server Service 为 80→8080 / 443→8080 | `manifests/install.yaml` (v3.5.6) |
| app-controller `--app-resync` 默认 120s、`--app-resync-jitter` 60s、`--app-hard-resync` 0、`--status-processors` 20、`--operation-processors` 10 | `cmd/argocd-application-controller/commands/argocd_application_controller.go` |
| `timeout.reconciliation: 120s` + `timeout.reconciliation.jitter: 60s`；repo-server 侧表示 cached git revisions 过期时间 | `docs/operator-manual/argocd-cm.yaml` |
| Argo CD API server webhook：`sourceRevisionHasChanged` 按 `targetRevision` 匹配 | `util/webhook/webhook.go` |
| ApplicationSet webhook 与 API server webhook **不是同一个**；appset 是 ClusterIP + 自建 Ingress | `docs/operator-manual/applicationset/Generators-Git.md` |
| Git generator `revision` / `requeueAfterSeconds` / webhook 配置示例 | 同上 |
| PR generator 示例（`targetRevision: '{{.head_sha}}'`、默认 30 分钟轮询） | `docs/operator-manual/applicationset/Generators-Pull-Request.md` |
| Argo CD API server webhook 端点与语义 | `docs/operator-manual/webhook.md` |

### 环境相关（需实测确认）

- 实际的 `ARGOCD_RECONCILIATION_TIMEOUT` / `ARGOCD_RECONCILIATION_JITTER` / `ARGOCD_APPLICATIONSET_CONTROLLER_REQUEUE_AFTER` 生效值（可能被改过）。
- Argo CD API server 与 ApplicationSet webhook Ingress 是否已配置、Git provider 侧 webhook 是否已指向正确端点。
- 目标集群里 `Application` / `ApplicationSet` / `AppProject` 对象的实际存在情况（§10.3 的验收命令）。

---

## 附录 B. 与 `poc-argocd-integration.md` 的关系

本文件是 `poc-argocd-integration.md` 的**下钻**，不替代它：

- 总体链路、四个控制平面、"唯一总线"的完整叙述 → 看 `poc-argocd-integration.md` §1、§2、§4。
- **Git 变更 → Argo CD → apply 的逐阶段触发链路** → 看本文 §2、§3、§4、§5。
- Argo CD 与 Crossplane 的六个交互细节（字段所有权、namespace 覆盖、prune、selfHeal、CRD 未就绪、渲染校验） → 看 `poc-argocd-integration.md` §6。
- 端到端时序与延迟预期 → 本文 §13 与 `poc-argocd-integration.md` §5 互为印证（本文把"2 分钟"细化成了 app-controller 120s(+60s jitter) 与 appset 180s 两个不同旋钮）。

### 本文档对原文的两处补充/修正

1. **补充**：原文档 §5 只说"Git → ArgoCD 默认 2 分钟"，未区分是谁在轮询。源码级结论是**两个独立旋钮** —— application-controller 120s(+60s jitter) 与 applicationset-controller 180s（见 §3.4）。
2. **修正**：原文未提到 **ApplicationSet 有独立的 webhook Service（ClusterIP:7000）**，容易让人误以为 ApplicationSet 只能靠轮询。实际上两套 webhook（appset 的 `:7000` 与 argocd-server 的 `:80/:443`）是不同端点、不同用途，需分别配置（见 §3.1）。