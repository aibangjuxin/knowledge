# K8s 资源管理中的 Revision 类机制 — 云原生生态横向对比

> **TL;DR**:
> - "revision" 这个词在 **K8s / 云原生生态里有 ≥ 6 种不同含义**,**不是 K8s Gateway 独有**
> - 它们**实现机制各异**,但**底层模式相同**:**(selector / label / tag) + 间接引用 + 历史回溯**
> - Istio revision 借用了 **Deployment ReplicaSet 滚动升级 + Helm Release revision + namespace label** 的组合
> - **本场景现状**:同时涉及 4 种 revision(API resourceVersion + Deployment revision + Helm release revision + Istio control plane revision)

---

## 0. 这篇文档要解决什么

> Lex 在读 `15-istio-revision-mechanism-explained.md` 后追问:
>
> "**revision 关于这个,其实我还有另外一层意思,不仅仅是基于这一个 k8s Gateway 的管理,我的意思是对 K8s 本身来说,这个资源或者说这个东西 K8s 资源管理机制 那还有一些什么其他的用途**"
>
> "**这个能不能引申到其他类似这样的管理上面去?或者它本来就是一个标准的资源,只是 K8s Gateway 也借用了它这种功能**"
>
> **本文档的目标**:
> 1. **澄清 "revision" 这个词在云原生生态里的多种含义** — 不是 K8s Gateway 独有
> 2. **横向对比 6+ 种 revision 机制** — 找出共同模式
> 3. **说明 Istio revision 借用了哪些已有机制**
> 4. **本场景涉及哪些 revision 维度**

---

## 1. 6 种 Revision 机制一览表(横向对比)

| # | 机制 | 来源 | 标识方式 | 核心用途 | 本场景是否涉及 |
|---|---|---|---|---|---|
| **1** | **API Object `metadata.resourceVersion`** | K8s 原生 API | 整数/字符串 | 乐观并发控制、Watch 起点 | ✅ **每次更新 Deployment 都涉及** |
| **2** | **API Object `metadata.generation`** | K8s 原生 API | 整数(从 1 开始) | 跟踪 spec 变更、reconciliation 用 |
| **3** | **Deployment Revision**(`kubectl rollout history`) | K8s `apps/v1` | 整数(从 1 开始)| Pod Template 滚动版本、回滚 | ✅ **业务 pod 滚动更新时涉及** |
| **4** | **Helm Release Revision** | Helm | 整数(从 1 开始)| Chart 安装历史、回滚 | ✅ **每次 `helm upgrade/istioctl install` 都涉及** |
| **5** | **ArgoCD Application Revision** | ArgoCD | Git commit SHA | GitOps 状态版本、回滚 | ⚠️ 当前不用(可能未来)|
| **6** | **Istio Control Plane Revision**(`istio.io/rev`) | Istio | 字符串标签 | 多 control plane 共存、零中断升级 | ⚠️ 当前不用,**Phase 3 启用** |
| **7** | **OCI Image Tag / Digest** | OCI / Docker | 字符串(版本号或 SHA256) | 镜像版本、不可变引用 | ✅ **每个 pod 都引用镜像** |
| **8** | **Database Migration Version** | Flyway / Liquibase | 整数 | schema 版本控制 | ⚠️ 应用层(本目录不涉及)|

> 来源:综合 [K8s API Conventions](https://github.com/kubernetes/community/blob/main/contributors/devel/sig-architecture/api-conventions.md) + [kubectl rollout undo](https://jorijn.com/en/knowledge-base/kubernetes/deployments/kubernetes-deployment-rollback) + [Helm docs](https://helm.sh/) + [ArgoCD docs](https://argo-cd.readthedocs.io/) + Istio docs

---

## 2. 严格定义 vs 简化解释(各 8 个)

### 2.1 API Object `metadata.resourceVersion`

| 简化解释 | 严格定义 |
|---|---|
| **"K8s 资源的内部版本号"** | "An opaque value that represents the internal version of this object that can be used by clients to determine when objects have changed. May be used for optimistic concurrency, change detection, and the watch operation on a resource or set of resources." — [K8s API Conventions](https://github.com/kubernetes/community/blob/main/contributors/devel/sig-architecture/api-conventions.md) |
| **"etcd mod_revision"** | "The resourceVersion is currently backed by etcd's mod_revision. However, it's important to note that the application should *not* rely on the implementation details of the versioning system maintained by Kubernetes." — 同上 |
| **"乐观并发"** | "Kubernetes leverages the concept of *resource versions* to achieve optimistic concurrency. When a record is about to be updated, its version is checked against a pre-saved value, and if it doesn't match, the update fails with a StatusConflict (HTTP status code 409)." — 同上 |
| **"Watch 起点"** | "'Watch' operations specify resourceVersion using a query parameter. It is used to specify the point at which to begin watching the specified resources." — 同上 |

### 2.2 API Object `metadata.generation`

| 简化解释 | 严格定义 |
|---|---|
| **"spec 变更计数器"** | "In some objects, generation is incremented by the server as part of persisting writes affecting the `spec` of an object." — [Stack Overflow](https://stackoverflow.com/questions/47100389/what-is-the-difference-between-a-resourceversion-and-a-generation) |
| **"reconciliation 触发器"** | "metadata.generation is an integer that tracks spec changes. It is primarily used by controllers to detect when the desired state has changed so that it can begin the reconciliation process to make the actual state match the desired state." — 同上 |
| **"observedGeneration 记录已处理"** | "Some objects' `status` fields have an `observedGeneration` subfield for controllers to persist the generation that was last acted on." — 同上 |

### 2.3 Deployment Revision

| 简化解释 | 严格定义 |
|---|---|
| **"Deployment 的滚动版本号"** | "A Kubernetes Deployment Revision is an auto-incrementing version number created every time the Pod Template changes. Update the container image? New Revision. Change an environment variable? New Revision. Tweak resource limits? New Revision." — [Kubernetes Revision Deep Dive](https://smartinfralog.com/posts/kubernetes-revisionreference-guide) |
| **"对应一个 ReplicaSet"** | "Each change creates a new ReplicaSet, and that ReplicaSet gets tagged with the next Revision number. Old ReplicaSets stick around (up to revisionHistoryLimit), which is what makes rollback possible." — 同上 |
| **"kubectl rollout undo 用"** | "The fastest rollback is one command: `kubectl rollout undo deployment/myapp`. This tells the Deployment controller to switch back to the previous ReplicaSet." — [K8s Rollback](https://jorijn.com/en/knowledge-base/kubernetes/deployments/kubernetes-deployment-rollback) |

### 2.4 Helm Release Revision

| 简化解释 | 严格定义 |
|---|---|
| **"Helm 装/升一次 +1"** | "Helm maintains a release history for each installation. Each `helm install` or `helm upgrade` creates a new revision. `helm history <release>` lists them; `helm rollback <release> <revision>` reverts." — [Helm docs](https://helm.sh/docs/helm/helm_history/) |
| **"存的是 Kubernetes manifest 快照"** | "Helm releases are stored as Secrets (in classic v3) or as a separate database with the v2-to-v3 migration. Each revision stores the full rendered manifest, so rollback is essentially `kubectl apply` the old manifest." — Helm docs |
| **"Helm 2 / Helm 3 存储位置不同"** | "Helm 2 stored releases in ConfigMaps by default (Tiller-managed); Helm 3 stores releases as Secrets in the release namespace." — Helm migration docs |

### 2.5 ArgoCD Application Revision

| 简化解释 | 严格定义 |
|---|---|
| **"Git commit SHA"** | "Argo CD uses the argocd.argoproj.io/tracking-id annotation (or label) to identify which application instance manages the resource. The `source.targetRevision` field is the Git commit SHA." — [ArgoCD resource tracking](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_tracking/) |
| **"GitOps 历史"** | "Argo CD stores the application's history including sync status, revision, and timestamp. Each sync is a new entry." — ArgoCD docs |
| **"对比差异源"** | "The Argo CD application controller periodically compares Git state against the live state, running the `helm template <CHART>` command to generate the helm manifests." — [ArgoCD docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/) |

### 2.6 Istio Control Plane Revision

| 简化解释 | 严格定义 |
|---|---|
| **"istiod 的实例标识 + ns selector"** | "A revision is a label applied to istiod (and dependent charts) that namespaces opt into via the `istio.io/rev` label." — [Istio Canary Upgrades](https://istio.io/latest/docs/setup/upgrade/canary/) |
| **"Feature Status: Beta"** | "Name: `istio.io/rev`. Feature Status: Beta. Resource Types: Namespace, Gateway, Pod." — [Istio Resource Labels](https://istio.io/latest/docs/reference/config/labels/) |
| **"Revision Tag 是间接别名"** | "Revision tags allow for the creation of mutable aliases referring to control plane revisions for sidecar injection." — [istioctl/pkg/tag/tag.go](https://github.com/istio/istio/blob/master/istioctl/pkg/tag/tag.go) |

### 2.7 OCI Image Tag / Digest

| 简化解释 | 严格定义 |
|---|---|
| **"镜像版本标签"** | "An image is identified by its name and tag. `nginx:1.25.0` vs `nginx:latest`. Tags are mutable; a tag can be repushed." — [OCI spec](https://github.com/opencontainers/distribution-spec/blob/main/spec.md) |
| **"digest 不可变"** | "A digest is a SHA256 hash of the image content; immutable. Recommended for production: `nginx@sha256:abc123...`." — OCI spec |
| **"pod 引用镜像"** | "In Kubernetes, `imagePullPolicy: IfNotPresent` checks tag; `Always` always pulls; digest reference skips tag check." — K8s docs |

---

## 3. 核心抽象 — 6 种 Revision 的共同模式

> 这才是 Lex 想要的 "**Revision 类机制**" 的上位概念。

```
┌─────────────────────────────────────────────────────────────┐
│  Revision 类机制的通用抽象                                  │
│                                                             │
│  ┌──────────────┐                                          │
│  │ 标识(Identity)│   一个名字 / 数字 / hash                  │
│  └──────┬───────┘                                          │
│         ↓                                                  │
│  ┌──────────────┐                                          │
│  │ 状态快照(State)│   spec / manifest / commit / config    │
│  └──────┬───────┘                                          │
│         ↓                                                  │
│  ┌──────────────┐                                          │
│  │ 选择器(Selector)│  label / tag / branch / version       │
│  └──────┬───────┘                                          │
│         ↓                                                  │
│  ┌──────────────┐                                          │
│  │ 路由机制(Routing)│  consumer 用 selector 找到当前状态     │
│  └──────┬───────┘                                          │
│         ↓                                                  │
│  ┌──────────────┐                                          │
│  │ 历史保留(History)│  N 个旧版本可回滚(可配置)             │
│  └──────┬───────┘                                          │
│         ↓                                                  │
│  ┌──────────────┐                                          │
│  │ 演进(Evolution)│  新版本 / 新 revision                  │
│  └──────────────┘                                          │
└─────────────────────────────────────────────────────────────┘
```

### 3.1 各机制在 6 维度上的对比

| 机制 | 标识 | 状态快照 | 选择器 | 路由 | 历史 | 演进 |
|---|---|---|---|---|---|---|
| **resourceVersion** | 整数(etcd)| 完整对象 | (无)| Watch 起点 | (无内置)| 自动 +1 |
| **generation** | 整数 | spec 字段 | (无) | controller 触发 reconcile | (无)| spec 变 +1 |
| **Deployment Rev** | 整数 | Pod Template + ReplicaSet | Deployment selector | Service 路由到 Pod | `revisionHistoryLimit`(默认 10)| spec 变 +1 |
| **Helm Release Rev** | 整数 | rendered manifest | release name | Kubernetes 资源 | Secret(默认保留所有)| `helm upgrade` +1 |
| **ArgoCD App Rev** | Git SHA | Git commit 状态 | Application name + ns | controller 同步 | History of sync | Git push |
| **Istio CP Rev** | 字符串标签 | istiod 实例 + webhook | `istio.io/rev` ns label | 标签选 webhook / Service | (无内置,手动保留)| `istioctl install --revision=X` |
| **OCI Tag** | 字符串 | 镜像 layer | image name + tag | container runtime | 仓库永久保留 | push 新镜像 |
| **OCI Digest** | SHA256 | 不可变镜像 | digest | container runtime | 永久 | push 新镜像 |

### 3.2 共同模式的 3 个特征

```
✅ 特征 1:标识是字符串/整数
  - 都有"我是谁"概念(整数、字符串、hash)
  - 客户端不需要解析具体值,只比对

✅ 特征 2:选择器(selector) + 间接引用
  - consumer 通过 selector(tag/label/name) 找到"当前"的资源
  - 改了 selector 指向 = 不改资源 = 切流

✅ 特征 3:历史保留 + 可回滚
  - 旧版本不是"删除",而是"保留 N 个 + 当前 1 个"
  - rollback = 切 selector 指向旧版本
```

---

## 4. Istio Revision 借用了哪些已有机制?

> **关键洞察**:Istio revision **不是发明新概念**,而是**组合了 3 种已有 K8s 原生机制**:

| Istio revision 用到的底层机制 | 来源 | 借用方式 |
|---|---|---|
| **Namespace label 作 selector** | K8s 原生 | `istio.io/rev=<rev>` 选 webhook / 选 istiod |
| **MutatingWebhookConfiguration 拦截** | K8s 原生 admissionregistration | 每个 revision 注册独立 webhook,namespaceSelector 限定 |
| **Service name 路由** | K8s 原生 Service | `istiod-<rev>` Service 是负载均衡 + DNS 解析目标 |
| **Deployment 多副本管理** | K8s 原生 | 每个 revision 是独立 Deployment |
| **Selector + label 间接引用** | K8s 原生 selector 模式 | 改 label = 切流(继承自 Service / NetworkPolicy) |

### 4.1 Istio 没"发明"任何东西

```
K8s 原生 selector 模式 ─────┐
K8s 原生 MutatingWebhook ───┼──→  Istio revision 机制
K8s 原生 Service 路由 ──────┤
K8s 原生 Deployment 多副本 ─┘
        ↑
        + Revision Tag(可变别名)
        + namespace label 约定
        + chart 渲染时给 Deployment 加 suffix
```

### 4.2 与 Deployment Revision 的对比(让人更懂)

```
Deployment Rev 机制:
  - 1 个 Deployment 名字
  - N 个 ReplicaSet(每个对应一个 revision)
  - Deployment 通过 selector 路由到当前活跃 ReplicaSet
  - 旧的 ReplicaSet 保留(默认 10 个)

Istio Rev 机制:
  - 1 个"逻辑控制面"(istiod 的概念)
  - N 个 istiod 实例(每个 revision 一个)
  - Namespace 通过 `istio.io/rev` label 路由到当前活跃 istiod
  - 老的 istiod 保留(手动)

→ 完全是同一个模式!只是粒度从 "Pod Template" 上升到 "Control Plane"。
```

---

## 5. K8s 资源管理视角 — revision 用在哪些 K8s 机制?

> 这部分直接回答 Lex 的问题:**"K8s 资源管理机制中的 revision 还有哪些用途"**

### 5.1 K8s 原生 API 层(最底层)

| 机制 | 用途 | 本场景示例 |
|---|---|---|
| **`resourceVersion`** | etcd 并发控制 + Watch | 每次 `kubectl apply` 触发 |
| **`generation`** | controller reconciliation 触发 | Deployment controller 看 generation 变化 |
| **`observedGeneration`** | controller 标记已处理的 spec | status 字段记录 |
| **API group/version**(`apps/v1` vs `apps/v1beta1`)| K8s API 演进 | HTTPRoute `gateway.networking.k8s.io/v1` |

### 5.2 Controller / Operator 层

| 机制 | 用途 | 本场景示例 |
|---|---|---|
| **Deployment Revision** | Pod Template 滚动回滚 | `kubectl rollout undo deployment/team-a-app` |
| **StatefulSet Controller Revision** | 有状态 pod 滚动 | 不涉及 |
| **DaemonSet Controller Revision** | 节点守护进程滚动 | ztunnel 升级时会触发 |
| **Job Controller** | 任务执行 | 不涉及 |

### 5.3 GitOps / 包管理层

| 机制 | 用途 | 本场景示例 |
|---|---|---|
| **Helm Release Revision** | Chart 安装历史 | `helm history istiod -n istio-system` |
| **ArgoCD Application Revision** | GitOps 同步历史 | 不涉及(没用 ArgoCD)|
| **Kustomize Image Tag** | 镜像版本管理 | 不涉及 |
| **Operator Lifecycle Manager(OLM)Subscription** | Operator 升级 | 不涉及 |

### 5.4 Service Mesh / API Gateway 层(本场景核心)

| 机制 | 用途 | 本场景示例 |
|---|---|---|
| **Istio Control Plane Revision** | 多 istiod 并存 + 零中断升级 | `istio.io/rev=1-31-canary` |
| **Istio Revision Tag** | 可变别名 | `prod-stable → 1-9-5` |
| **K8s Gateway API `gatewayClassName`** | 选 controller | `istio` / `istio-waypoint` |
| **K8s Gateway API ListenerSet** | 多租户 Gateway 切片 | 本场景已用 |
| **Knative Revision** | Serverless 版本 | 不涉及 |
| **Tekton PipelineRun** | CI/CD 任务版本 | 不涉及 |

### 5.5 应用 / 数据层

| 机制 | 用途 | 本场景示例 |
|---|---|---|
| **OCI Image Tag / Digest** | 镜像版本 | `proxyv2:1.30.3-distroless` |
| **Database Migration Version** | schema 版本 | 不涉及(应用层)|
| **API Versioning** | REST/GraphQL API 版本 | `/v1` `/v2` |
| **Semantic Versioning** | 库版本 | Istio 1.30.3 |
| **Git Commit SHA** | 代码版本 | 镜像 build source |

---

## 6. 同一个模式 — Selector + History 的体现

> 不管哪种 revision,本质都是这个模式:

```
1. 有多个版本存在(并行 / 历史保留)
2. 用 selector(标签 / 名字 / hash)路由到"当前活跃"版本
3. 改 selector 指向 = 切换 = "零中断"
4. 旧版本不删,留作回滚 / 调试 / 验证
```

### 6.1 这个模式在 6 种机制里长什么样

| 机制 | selector | 路由对象 | 改 selector 的效果 |
|---|---|---|---|
| **Deployment Rev** | `kubectl rollout undo` | Deployment 切到旧 ReplicaSet | 业务 pod 回滚 |
| **Helm Release Rev** | `helm rollback <rel> <rev>` | release 切到旧 manifest | K8s 资源回滚 |
| **ArgoCD App Rev** | Application `sync --revision` | controller 切到旧 Git commit | K8s 资源回滚 |
| **Istio CP Rev** | `kubectl label ns X istio.io/rev=Y` | namespace 切到新 istiod | 业务 pod 下次重启连新 istiod |
| **OCI Image Tag** | `kubectl set image ...=image:v2` | Pod 切到新镜像 | 业务 pod 滚动 |
| **Knative Rev** | Knative Route 切 traffic | 切流量百分比 | 业务流量切流 |

### 6.2 为什么这个模式普遍?

```
根本原因:K8s / 云原生的核心是 "声明式 + immutable + 间接引用"

声明式 → "我要什么状态",由 controller 调谐
immutable → 旧版本不能改,只能新建 + 切
间接引用 → selector 不是直接绑定,而是通过 label 匹配

→ 任何需要"演进 + 回滚"的系统,都会演化出类似的 selector+history 模式
```

---

## 7. K8s 生态里"Revision-like"模式一览(横向生态)

> 不仅 K8s 内部,云原生生态也大量使用这个模式:

| 生态 | 机制 | selector | history | 来源 |
|---|---|---|---|---|
| **K8s 原生** | Deployment Revision | Pod selector | ReplicaSet 保留 | apps/v1 |
| **K8s 原生** | resourceVersion | (无 selector) | (无) | etcd |
| **Helm** | Release Revision | release name | Secret 保留 | Helm v3 |
| **ArgoCD** | Application Revision | Git SHA | sync history | ArgoCD |
| **Istio** | Control Plane Revision | `istio.io/rev` ns label | chart-managed | Istio 1.6+ |
| **Knative** | Revision | Knative Route traffic | Knative controller | Knative |
| **Tekton** | PipelineRun | Pipeline name | TaskRun history | Tekton |
| **Crossplane** | Composite Resource | composition | XRD | Crossplane |
| **FluxCD** | HelmRelease | chart version | GitOps sync | FluxCD |
| **Prometheus** | Recording Rule | metric name | rules file | Prometheus |
| **Envoy** | xDS resource version | cluster_name + version | (无) | Envoy xDS |

**结论**:**这个模式是云原生的"通用语言"** — Istio 借用,Knative / ArgoCD / FluxCD 都在用,本质就是 **"多版本 + selector 路由 + 历史保留"**。

---

## 8. 本场景涉及哪些 Revision?(实际清单)

> 用一张表理清:dev 集群操作 Istio 时,**每一步涉及哪几种 revision**。

| 操作 | resourceVersion | generation | Deployment Rev | Helm Rev | ArgoCD Rev | Istio Rev | OCI Tag |
|---|---|---|---|---|---|---|---|
| `kubectl apply -f` 业务 Deployment | ✅ | ✅ | ✅(影响) | ❌ | ❌ | ❌ | ✅ |
| `kubectl rollout restart deployment/X` | ✅ | ❌ | ✅(不变,只是 restart)| ❌ | ❌ | ❌ | ❌ |
| `helm upgrade istiod ...` | ✅ | ✅(chart) | ✅(Deployment 改 image)| ✅(helm)| ❌ | ⚠️(看是否新 revision)| ✅(image tag)|
| `istioctl install --set profile=minimal` | ✅ | ❌ | ✅(改 chart)| ❌ | ❌ | ⚠️(默认 revision="") | ✅ |
| `kubectl label ns X istio.io/rev=Y` | ✅ | ❌ | ❌ | ❌ | ❌ | ✅(切 revision)| ❌ |
| `kubectl rollout history deploy/X` | ✅ | ✅ | ✅(展示 revision)| ❌ | ❌ | ❌ | ✅(看 image)|
| `kubectl get pod -o yaml` 看 metadata | ✅ | ✅ | ✅ | ❌ | ❌ | ✅(看 istio rev)| ✅ |

**本场景**:**5 种 revision 都在用**(resourceVersion / generation / Deployment Rev / Helm Rev / OCI Tag);**2 种暂未用**(ArgoCD Rev / Istio Rev)— 后者在 Phase 3 启用,前者可能永远不用(看用 GitOps 选型)。

---

## 9. 决策树 — 我应该理解 / 关注哪个 Revision?

```
我的工作 / 关注点在?
  │
  ├─ 写 K8s 控制器 / Operator
  │   └─ 必懂: resourceVersion / generation / observedGeneration
  │
  ├─ 部署业务应用 + 回滚
  │   └─ 必懂: Deployment Rev(`kubectl rollout history/undo`)
  │      + OCI Image Tag(用 digest 锁定版本)
  │
  ├─ 用 Helm 管 K8s 资源
  │   └─ 必懂: Helm Release Rev(`helm history/rollback`)
  │
  ├─ 用 GitOps(ArgoCD / FluxCD)
  │   └─ 必懂: Git Commit SHA + ArgoCD/FluxCD Sync History
  │
  ├─ 用 Istio mesh
  │   └─ 必懂: Istio Control Plane Rev(本目录 15 文)
  │
  └─ 多控制器 / 多版本共存
      └─ 必懂: K8s 原生 selector + label + immutable 模式
```

---

## 10. 反向:Revision 机制不能做什么

| 场景 | 限制 |
|---|---|
| **跨 namespace 共用 revision** | revision 通常 ns 作用域(除了 Istio mesh 跨 ns)|
| **横跨多个 control plane / 多集群** | 单 revision 不能跨集群(需 multicluster 联邦) |
| **历史无限保留** | 各机制都有保留上限(Deployment 默认 10 / Helm 默认全留)|
| **跨 API 版本回滚** | 不同 `apiVersion`(如 `v1` vs `v1beta1`)不能 rollback,只能迁移 |
| **运行时改 immutable 字段** | revision 设计的初衷就是 immutable,要改 = 建新 |

---

## 11. 与"Git / 数据库 / 配置中心"的对比

> 跨领域的 revision 模式对比,加深理解:

| 领域 | revision 标识 | 选择器 | 历史保留 | 演进 |
|---|---|---|---|---|
| **Git** | SHA | branch / tag | 永久 | commit |
| **K8s Deployment** | 整数 | Deployment name | 默认 10 | Pod Template 变 |
| **Helm Release** | 整数 | release name | Secret 永久 | `helm upgrade` |
| **Istio CP** | 字符串标签 | `istio.io/rev` ns label | 手动 | chart 重装 |
| **OCI Image** | tag / digest | image name + tag | 仓库永久 | `docker push` |
| **MySQL binlog** | log sequence | position | (永久)| 事务 |
| **etcd rev** | etcd mod_revision | (无)| etcd compact | KV 写 |

---

## 12. References

### 12.1 K8s 资源管理权威来源

- [K8s API Conventions: resourceVersion / generation](https://github.com/kubernetes/community/blob/main/contributors/devel/sig-architecture/api-conventions.md) — `metadata.resourceVersion` 与 `metadata.generation` 权威定义
- [K8s ObjectMeta reference](https://kubernetes.io/docs/reference/kubernetes-api/definitions/object-meta-v1-meta/) — `resourceVersion` 字段文档
- [K8s API Concepts: resourceVersion](https://kubernetes.io/docs/reference/using-api/api-concepts/) — Watch / List 语义
- [K8s Deployment Rollback](https://jorijn.com/en/knowledge-base/kubernetes/deployments/kubernetes-deployment-rollback) — `kubectl rollout undo` 详解
- [Kubernetes Revision Deep Dive](https://smartinfralog.com/posts/kubernetes-revisionreference-guide) — Deployment revision 实战陷阱
- [Stack Overflow: resourceVersion vs generation](https://stackoverflow.com/questions/47100389/what-is-the-difference-between-a-resourceversion-and-a-generation) — 经典 Q&A

### 12.2 生态工具

- [Helm docs](https://helm.sh/docs/) — Release Revision
- [ArgoCD Resource Tracking](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_tracking/) — Application + tracking-id
- [ArgoCD High Availability](https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/) — controller 行为
- [OCI Distribution Spec](https://github.com/opencontainers/distribution-spec/blob/main/spec.md) — Image tag / digest
- [Istio Resource Labels](https://istio.io/latest/docs/reference/config/labels/) — `istio.io/rev` 权威
- [Istio Canary Upgrades](https://istio.io/latest/docs/setup/upgrade/canary/) — Istio Rev 详解
- [Istio Revision Tags Blog](https://istio.io/latest/blog/2021/revision-tags/) — Revision Tag 起源

### 12.3 本目录关联文档

- `15-istio-revision-mechanism-explained.md` — Istio revision 详解(本文档是其上位扩展)
- `05-upgrade-strategies.md` — Helm Release + Istio Rev 双 canary 升级
- `12-revision-canary-mtls-compat.md` — Istio Rev 的 mTLS 兼容
- `ADR-LOCAL-001-migrate-minimal-to-ambient.md` — Phase 3 升 1.31 用 Istio Rev
- `PERSONAL-FOCUS-LIST.md` — Lex 个人关注清单

---

## 13. 关键认知 checklist(自测)

读完本文后,你能回答下列问题吗?

| # | 问题 | 答案要点 |
|---|---|---|
| 1 | **revision 在云原生生态里有多少种含义?** | ≥ 6 种(resourceVersion / generation / Deployment Rev / Helm Rev / ArgoCD Rev / Istio Rev / OCI Tag)|
| 2 | **`resourceVersion` 与 `generation` 区别?** | `resourceVersion` = 任何修改 +1(乐观并发用);`generation` = 仅 spec 修改 +1(controller 触发 reconcile)|
| 3 | **Istio revision 是 K8s 原生概念吗?** | 不是 — 它是 K8s selector + label + MutatingWebhook 的组合应用 |
| 4 | **Deployment Revision 与 Istio Revision 的本质共性?** | 都是 "selector + history + 间接引用" 模式 |
| 5 | **本场景涉及哪些 revision?** | 5 种(resourceVersion / generation / Deployment Rev / Helm Rev / OCI Tag)+ 2 种待启用(ArgoCD / Istio Rev)|
| 6 | **revision 类机制的"通用模式"是什么?** | (1)标识 (2)状态快照 (3)selector 路由 (4)历史保留 (5)演进 |

> 自测 6/6 = 已掌握;4-5 = 大部分懂;≤ 3 = 重读 §3-5

---

## 14. 终极洞察 — Revision 模式为何普遍

> 这部分是 Lex 想要的"上位概念"的最后一击。

**K8s / 云原生的 3 个核心哲学**决定了 revision 模式必然普遍:

1. **声明式(Declarative)**
   - "我描述想要什么状态" — 不告诉系统"怎么做"
   - controller 调谐(actual state → desired state)
   - → **演进必须通过修改 desired state 触发**,不是"修补 actual"

2. **不可变(Immutable)**
   - 旧资源不能改,只能新建 + 切 selector
   - → **历史保留是天然设计**,不是额外开销

3. **间接引用(Indirection)**
   - selector 不是硬编码,而是 label 匹配
   - → **切换 = 改 label**,不需重建对象

```
这 3 个原则共同决定了:
  演进 = "建新 + 切 selector"
  回滚 = "切回旧 selector"
  历史 = "旧版本不删"

→ revision 模式不是"特性",是这套哲学的**必然推论**。
```

**所以**:Istio revision、K8s Deployment revision、Helm release revision、ArgoCD Git revision… **形式各异,本质相同**。**理解了 selector+history 模式,就理解了云原生的"版本管理"哲学**。