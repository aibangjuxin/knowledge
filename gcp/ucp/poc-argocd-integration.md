# ArgoCD × Crossplane 集成链路详解

> 配套文档：`poc-minimax.md`（PoC 总体方案）。
> 本文专门回答一个问题：**Git 仓库里提交的 XR YAML，是怎么"流"到 Crossplane Core 并变成云上集群的？**
>
> 所有版本、字段、API 路径均已在线核实（核实来源见附录 A）。标注 `【待核实】` 的为环境相关项。

---

## 0. 先回答你的问题

**ArgoCD 和 Crossplane Core 之间，没有任何直接连接。**

这是整件事最关键、也最容易误解的一点。常见的错误心智模型是：

```
❌ 错误：Git → ArgoCD →（HTTP 调用 / webhook / 自定义插件）→ Crossplane Core → GCP
```

实际的心智模型是：

```
✅ 正确：Git → ArgoCD ─┐
                       ├→ Kubernetes API Server ←┴→ Crossplane Core → Provider → GCP
         （写入 XR）    │        （唯一总线）      （读取 XR，写 MR）
```

拆开说三句话：

1. **ArgoCD 不认识 Crossplane。** 它眼里只有一个普通 YAML 文件和一个 CRD 实例
   （`GKECluster`）。它不知道有 Composition、有 Provider、也不关心你后面怎么调谐。
2. **Crossplane Core 不认识 ArgoCD。** 它眼里只有一个 `GKECluster` 对象出现在
   `team-a` 这个 namespace 里，于是按 XRD 定义的契约去渲染 Composition。
3. **两者唯一的"契约"就是 XR 这个对象本身**，外加 Kubernetes API Server 的
   watch 机制。谁写 `spec`、谁写 `status`，靠的是字段所有权天然分开。

所以所谓"打通"，**不是建立一条 ArgoCD → Crossplane 的通信链路**，
而是把 **同一个 API Server 上的两个写者**的职责边界划清楚：

| 角色 | 写什么 | 读什么 |
|---|---|---|
| ArgoCD | XR 的 `spec` + `metadata` | XR 的 `spec`（做 diff） |
| Crossplane Core | XR 的 `status`、MR 对象、Composition 相关对象 | XR 的 `spec` |
| Provider | MR 的 `status.atProvider` | MR 的 `spec.forProvider` |

> 换句话说：**ArgoCD 是 XR 的"写入者"，Crossplane 是 XR 的"响应者"。**
> 通道就是 API Server 的 watch 事件流，不需要任何额外接线。

---

## 1. 全景：四个控制平面、一条总线

```mermaid
graph TB
    subgraph Devs[开发者]
        D1["改 YAML → git commit → Pull Request"]
    end
    subgraph Git[Git 服务器]
        G1["ucp-platform 仓库<br/>teams/&lt;team&gt;/&lt;project&gt;/*.yaml"]
    end
    subgraph ArgoNS["argocd namespace"]
        A1["repo-server<br/>git clone / 缓存 manifest"]
        A2["application-controller<br/>★ diff + apply"]
        A3["applicationset-controller<br/>生成 Application"]
    end
    subgraph CP["Crossplane 控制集群 · GKE Standard"]
        API["K8s API Server<br/>★ 唯一总线"]
        X1["crossplane-system<br/>crossplane Pod<br/>（XR 控制器）"]
        X2["crossplane-system<br/>function-go-templating Pod"]
        X3["crossplane-system<br/>provider-gcp-container Pod"]
        XR["XR: GKECluster"]
        MR["MR: Cluster + NodePool"]
    end
    subgraph GCP["GCP"]
        C1["container.googleapis.com"]
        C2["GKE 集群 (Standard)"]
    end

    D1 --> G1
    G1 <-.git fetch.-> A1
    A3 -.读 Git 目录.-> G1
    A3 --> A2
    A1 --> A2
    A2 ==>|① apply XR<br/>K8s API| API
    API ==>|② watch 事件| X1
    X1 --> API
    X1 <-->|③ RunFunctionRequest| X2
    X1 -->|④ 创建 MR| API
    API ==>|⑤ watch MR| X3
    X3 ==>|⑥ WI token 调 GCP API| C1
    C1 --> C2
    X3 ==>|⑦ 回写 MR.status| API
    API ==>|⑧ XR.status.conditions| X1
    X1 --> API
```

**标注的 ①–⑧ 就是全部的"接线点"。** 除此以外没有任何自定义通道。

---

## 2. 通信矩阵（这是本文最该记住的一张表）

| # | 源 | 目标 | 通道 / 协议 | 需要的凭据 | 谁来配 | 失败表现 |
|---|---|---|---|---|---|---|
| ① | 开发者 | Git 服务器 | HTTPS / SSH | 个人 Git 凭据 | 开发者自己 | PR 推不上去 |
| ② | `argocd-repo-server` | Git 服务器 | HTTPS / SSH | repo credential Secret | 平台 | Application 报 `Unknown repo` / `authentication required` |
| ③ | `argocd-application-controller` | K8s API Server | HTTPS（Kube API） | **集群内 SA token**（同集群）<br/>或 **cluster Secret / kubeconfig**（跨集群） | 平台 | `rpc error: code = Unavailable` / `Forbidden` |
| ④ | `crossplane` Pod | K8s API Server | HTTPS（Kube API） | `crossplane-system/crossplane` SA + ClusterRoleBinding（Helm 自动建） | Helm chart 自动 | Crossplane Pod 起不来 / XR 不调谐 |
| ⑤ | `function-go-templating` Pod | 收到 `RunFunctionRequest`（stdin/stdout） | gRPC over stdin/stdout | 无（Function 由 Core 拉起） | Core 自动 | Composition 渲染失败 |
| ⑥ | `provider-gcp-container` Pod | `container.googleapis.com` | HTTPS（REST） | **Workload Identity**：GSA token | 平台 + 云治理方 | Provider `Unhealthy` / `403` |
| ⑦ | `provider-gcp-container` Pod | K8s API Server | HTTPS（Kube API） | Provider 自己的 SA（由 DRC 固定名） | Helm/DRC | MR 不更新 status |

**注意 ③ 和 ④ 是两条独立的通道，各自持有自己的 K8s 凭据。**
ArgoCD 用 `argocd-application-controller` 的 SA；Crossplane 用 `crossplane` 的 SA。
它们互不相识，也不需要互相授权。

### 2.1 那"Git 提交后请求到达 Crossplane"到底发生了什么？

只有两步，没有第三步：

1. ArgoCD 把 YAML **apply 成一个 API 对象**（XR）——到这里"请求"就已经送达了；
2. Crossplane Core 的 informer **收到 watch 事件**，调谐这个 XR。

watch 事件是 Kubernetes 内置的，**不需要 Crossplane 订阅 Git、不需要 webhook、
不需要 ArgoCD 暴露回调地址**。这就是整套设计能保持简单的根本原因。

---

## 3. ArgoCD 侧：到底要提供哪些东西

### 3.1 ArgoCD 装在哪？两种拓扑，先选一个

| | 方案 A：同集群（**PoC 推荐**） | 方案 B：独立 GitOps 集群（生产推荐） |
|---|---|---|
| ArgoCD 位置 | Crossplane 控制集群的 `argocd` namespace | 另一个独立的 GKE 集群 |
| `destination.server` | `https://kubernetes.default.svc` | Crossplane 集群的 API Server 地址 |
| 目标集群凭据 | **不需要额外凭据**，用 ArgoCD 自己的集群内 SA | 需要 `argocd.argoproj.io/secret-type: cluster` 的 Secret |
| 优点 | 零配置，最快跑通；PoC 不必多运维一个集群 | **控制集群可以从零重建**；ArgoCD 的可用性不受 Crossplane 集群影响 |
| 缺点 | 控制集群整体挂掉时，GitOps 也没了，无法自举恢复；ArgoCD 与 Crossplane 在同一信任域 | 多一套集群要运维；需要管目标集群凭据 |
| 建议 | **PoC 阶段用 A**，阶段 3（安全 / 恢复）后评估迁 B | 生产形态 |

> 判据很直接：**Crossplane 控制集群如果整体丢失，你是否还需要一个东西把整套装回来？**
> 如果答案是"是"，那 ArgoCD 就不能和 Crossplane 住在同一个集群里。
> 但对 PoC 而言，先在同集群把链路跑通更重要。

**方案 B 的目标集群凭据**（提前备好，PoC 用不到）：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: crossplane-control-plane
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: crossplane-control-plane
  server: https://<crossplane-cluster-endpoint>
  # 建议用专用 SA 的短期 token，而不是 admin kubeconfig
  config: |
    {
      "bearerToken": "<token>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64 CA>"
      }
    }
```

对应 Application 的 `destination` 改为：

```yaml
destination:
  name: crossplane-control-plane      # 引用上面那个 Secret
  namespace: team-a-project-a
```

### 3.2 ArgoCD 内部谁干活

| 组件 | 职责 | 在本方案中是否关键 |
|---|---|---|
| `argocd-repo-server` | 负责 `git clone` / `git fetch`，渲染并缓存 manifest | 关键（拉取 Git） |
| `argocd-application-controller` | **核心**：watch `Application` 对象 + 目标集群资源，算 diff，执行 apply / prune | **最关键**（真正写入 XR 的组件） |
| `argocd-applicationset-controller` | 读 Git 目录结构，批量生成 `Application` | 关键（多团队多项目） |
| `argocd-server` | UI / API / CLI | 可选 |
| `argocd-redis` | 缓存 | 基础设施 |
| `argocd-dex` | SSO | 可选 |

> ArgoCD 3.x 的 `manifests/install.yaml` 已包含 `applicationset-controller`
> （`manifests/base/kustomization.yaml` 中有 `./applicationset-controller` 一项），
> 装完请用 `kubectl get pods -n argocd | grep applicationset` 确认。

### 3.3 `Application` CRD：把"Git 路径"和"集群目标"连起来的连接器

这是整条链路上**唯一需要你手工写对的 YAML**。它只有 4 个关键字段：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: team-a-project-a
  namespace: argocd
spec:
  source:                          # ① 从哪拿
    repoURL: git@github.com:<org>/ucp-platform.git
    targetRevision: main
    path: teams/team-a/project-a   # ← Git 里的目录

  destination:                     # ② 到哪去
    server: https://kubernetes.default.svc   # 同集群；跨集群改为 name: <cluster-secret>
    namespace: team-a-project-a

  syncPolicy:                      # ③ 什么时候同步
    automated:
      prune: false                 # 关键：见 §6.3
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    - PruneLast=true

  project: team-a                  # ④ 权限边界，见 §3.5
```

`source.path` 与 `destination.namespace` 的对应关系由 **ApplicationSet** 决定（见下节）。

### 3.4 ApplicationSet：一次生成多个 Application

ApplicationSet 做的事就是：**按 Git 目录结构批量生成 Application**。
这正好匹配"每个团队 × 每个项目一个 namespace"的需求。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: team-a-xr
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: git@github.com:<org>/ucp-platform.git
      revision: main
      directories:
      - path: teams/team-a/*        # 每个子目录 = 一个 Application
  template:
    metadata:
      name: 'team-a-{{path.basename}}'
    spec:
      project: team-a
      source:
        repoURL: git@github.com:<org>/ucp-platform.git
        targetRevision: main
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'   # ← 目录名即 namespace 名
      syncPolicy:
        automated:
          prune: false
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
        - ServerSideApply=true
```

仓库布局与生成结果一一对应：

```
teams/team-a/project-a/gkecluster.yaml   → Application: team-a-project-a
                                           → namespace: project-a
teams/team-a/project-b/gkecluster.yaml   → Application: team-a-project-b
                                           → namespace: project-b
```

> **命名一致性要求**：目录名 = namespace 名 = AppProject `destinations` 里允许的 namespace。
> 三处必须完全一致，否则 ArgoCD 会被 AppProject 拒绝（详见 §6.2）。

### 3.5 AppProject：团队的权限边界

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-a
  namespace: argocd
  namespaceMetadata:
    name: team-a            # 允许创建的 namespace
  sourceRepos:
  - '*'
  destinations:
  - namespace: project-a
    server: https://kubernetes.default.svc
  - namespace: project-b
    server: https://kubernetes.default.svc
  clusterResourceWhitelist: []          # 团队不得创建集群级资源
  namespaceResourceWhitelist:
  - group: platform.example.org
    kind: GKECluster
  namespaceResourceBlacklist:
  - group: '*'
    kind: '*'                            # 白名单之外一律拒绝
```

注意这里用 **`namespaceResourceWhitelist` + 全局 blacklist** 的组合：
只有 `platform.example.org/GKECluster` 这一种资源、且只在白名单 namespace 里才被允许。
团队即使往仓库里塞一个 `ClusterRole`，ArgoCD 也会拒绝同步。

### 3.6 Git 仓库凭据（私有仓库必须配）

| 仓库类型 | 配置方式 | Secret 标签 |
|---|---|---|
| 公开仓库 | 无需凭据，`repoURL` 直接用 `https://github.com/org/repo.git` | — |
| 私有仓库（HTTPS） | 用户名 + PAT / token | `argocd.argoproj.io/secret-type: repository` |
| 凭据模板（多仓库） | `argocd-repo-creds` ConfigMap，按 URL 前缀匹配 | — |
| 私有仓库（SSH） | SSH 私钥 | `argocd.argoproj.io/secret-type: repo-creds` |
| GitHub App | `argocd-repo-creds` ConfigMap，`githubApp` 字段 | — |

```yaml
# argocd namespace
apiVersion: v1
kind: Secret
metadata:
  name: repo-ucp-platform
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: git@github.com:<org>/ucp-platform.git
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
```

> SSH 场景还要配 `argocd-ssh-known-hosts-cm`，否则 ArgoCD 会因为 host key 校验失败而拉不到仓库。

### 3.7 ArgoCD 对目标集群的权限

ArgoCD 用**自己的 SA**（`argocd-application-controller`）向目标集群提交资源。
同集群部署时，它默认只有 `argocd` namespace 内的权限，
要写 `team-a-project-a` 就必须显式授权：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-xr-writer
rules:
- apiGroups: ["platform.example.org"]
  resources: ["gkeclusters"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-xr-writer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-xr-writer
subjects:
- kind: ServiceAccount
  name: argocd-application-controller
  namespace: argocd
```

> 更严格的做法是把上面的 ClusterRole + RoleBinding 下沉到每个项目 namespace，
> 而不是给一个集群级 ClusterRoleBinding。PoC 阶段用上面的写法即可，阶段 3 再收紧。

### 3.8 `argocd-cm`：哪些**真要配**，哪些已经内置

这一节需要更正一个常见误解。Crossplane 官方文档要求配三项：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  application.resourceTrackingMethod: annotation
  resource.exclusions: |
    - apiGroups: ["*"]
      kinds: [ProviderConfigUsage]
  resource.customizations: |
    "*.upbound.io/*":
      health.lua: |
        ...
```

逐项核实结论（针对 **ArgoCD v3.5.6**）：

| 配置项 | 是否需要 | 说明 |
|---|---|---|
| `application.resourceTrackingMethod: annotation` | **需要（显式写）** | ArgoCD 默认值就是 `annotation`，但显式写出来可防升级 / 防被覆盖。Crossplane 官方也明确要求。 |
| `resource.exclusions`（隐藏 `ProviderConfigUsage`） | **建议配** | 每个 MR 会生成一个 ProviderConfigUsage，量大了会拖慢 ArgoCD UI 和 API Server。 |
| `resource.customizations` 的 health.lua | **新版已内置，不必配** | ArgoCD v3.5.6 的 `resource_customizations/` 下**自带** `_.upbound.io/_/health.lua` 和 `_.crossplane.io/_/health.lua`（`_` = 任意 group），内容即从 Crossplane 官方文档移植而来。**只有 ArgoCD < 3.x 才需要手工贴这段 lua。** |

另外两项在 CRD 多时值得配：

```yaml
# argocd-application-controller Deployment
env:
- name: ARGOCD_K8S_CLIENT_QPS
  value: "300"          # 默认 50
```

### 3.9 安装与验收（可执行）

```bash
# 1) 装 ArgoCD（PoC 用同集群）
kubectl create namespace argocd
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-application-controller --timeout=300s
kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=300s

# 2) 确认 ApplicationSet controller 确实在跑
kubectl -n argocd get pods | grep applicationset

# 3) 确认 Crossplane Core 与 ArgoCD 互不干扰
kubectl -n crossplane-system get pods
kubectl -n crossplane-system get providers,functions
```

**PoC 阶段的验收顺序（严格按这个顺序，能快速定位问题域）**

| 步骤 | 操作 | 期望 | 不期望说明 |
|---|---|---|---|
| A | `kubectl -n argocd get applications` | Application 变 `Synced=True` | ArgoCD 侧还没通 |
| B | `kubectl -n team-a-project-a get gkeclusters` | XR 存在 | ArgoCD 没写进去 |
| C | `kubectl -n team-a-project-a describe gkeclusters <name>` | 有 Composition 名称、有 `Ready` condition | Crossplane 没接管 |
| D | `kubectl -n team-a-project-a get clusters.container.gcp.m.upbound.io` | MR 出现并 `Ready` | Composition 没渲染出 MR |
| E | `kubectl -n team-a-project-a get nodepools.container.gcp.m.upbound.io` | NodePool MR 出现 | 模板缺 NodePool |
| F | `gcloud container clusters list` | 集群存在且 `RUNNING` | GCP 侧问题（IAM / API / 配额） |

---

## 4. Crossplane 侧：需要提供什么

### 4.1 为什么 Core 用 Helm 装，而不是交给 ArgoCD 管？

这是**鸡生蛋**问题：

> ArgoCD 要先存在于集群里，才能同步任何东西。
> 如果 Crossplane Core 也由 ArgoCD 同步，那么第一次安装 ArgoCD 之后，
> 你还得手工"用 ArgoCD 装 ArgoCD 之外的东西"——而且 ArgoCD 自己的 Application
> 也要有人来创建。

因此标准的引导顺序是：

```
第 0 层（Terraform / Helm，手工一次性）：GKE 控制集群 → ArgoCD → Crossplane Core
第 1 层（ArgoCD 托管）：Provider / Function / ProviderConfig / XRD / Composition / MRAP
第 2 层（ArgoCD 托管，团队 PR）：XR
```

`poc-minimax.md` 里写的"Terraform + Helm 装 Core，ArgoCD 管其余"就是这个意思。

> 进阶做法：用 **ArgoCD 自举**（ArgoCD 用 Helm 自己管自己，Core 由 ArgoCD 的
> self-managed Application 接管）。生产上常见，但 PoC 阶段徒增复杂度，不建议。

### 4.2 Core 的 K8s 权限从哪来

Helm chart 会建好这一套（v2.4.3 已核实）：

```yaml
# clusterrole.yaml（chart 自带）
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: crossplane
  labels:
    app: crossplane
aggregationRule:
  clusterRoleSelectors:
  - matchLabels:
      rbac.crossplane.io/aggregate-to-crossplane: "true"
```

这个 ClusterRole 是**聚合角色**：任何打了
`rbac.crossplane.io/aggregate-to-crossplane: "true"` 标签的 ClusterRole 都会被合并进去。

所以如果你自己加了新的 MR 类型或 CRD，要让 Crossplane 能操作它，标准做法是：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: mytype:aggregate-to-crossplane
  labels:
    rbac.crossplane.io/aggregate-to-crossplane: "true"
rules:
- apiGroups: ["my.example.org"]
  resources: ["mytypes"]
  verbs: ["*"]
```

这正是 `poc-minimax.md` 里提到的那条规则。**注意：RBAC Manager 默认开启时，
它会为每个 XRD / 每个 Provider 自动生成这些聚合角色，你手写的会和它们并存。**

### 4.3 Core 要监听哪些 namespace？—— 全集群，不用配

这是很多人的疑问："XR 建在 `team-a-project-a`，Crossplane 会不会看不见？"

**不会，也不需要配置。** 原因：

1. `crossplane` 这个 ClusterRole 通过 ClusterRoleBinding 绑到 `crossplane` SA
   （chart 自带），权限是**集群级**的；
2. Crossplane Core 用 cluster-scoped 的 informer list/watch 所有 XR 类型；
3. RBAC Manager 会为每个 namespace 补齐细粒度的 Role，但它是在**已有对象**上补权限，
   不是限制 Core 的监听范围。

> 对比：v1 的 **Claim** 机制需要 `claimNames` 和 namespace 绑定；
> v2 的 `scope: Namespaced` XRD 没有这层额外配置——XR 建在哪个 namespace，
> Core 就管到哪个 namespace。

### 4.4 Provider / Function 的身份与 RBAC

| 组件 | K8s 身份 | 云身份 | 由谁创建 |
|---|---|---|---|
| Crossplane Core | `crossplane-system/crossplane`（chart 建） | 无 | Helm chart |
| Function | `crossplane-system/<func>-<revision>`（自动） | 无 | Core 自动拉起 |
| Provider | `crossplane-system/<prov>-<revision>`（自动） | **GSA**（Workload Identity） | Core 自动拉起，SA 名由 `DeploymentRuntimeConfig.serviceAccountTemplate.metadata.name` 固定 |

**关键**：`DeploymentRuntimeConfig` 里必须固定 SA 名，否则 Provider 每次升级
SA 名都变，Workload Identity 的 IAM 绑定全部失效：

```yaml
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata:
  name: gcp-wi
spec:
  serviceAccountTemplate:
    metadata:
      name: provider-gcp          # ← 固定名，IAM 绑定才稳定
      annotations:
        iam.gke.io/gcp-service-account: crossplane-sa@<control-project>.iam.gserviceaccount.com
  deploymentTemplate:
    spec:
      selector: {}
      template:
        spec:
          serviceAccountName: provider-gcp
```

Function 默认不需要额外的 K8s 权限（通过 stdin/stdout 拿输入）。
只有当 Function 要读 `EnvironmentConfig` 或使用 extra resources 时才需要额外授权。

### 4.5 XRD 的 scope 决定 MR 的 scope → 决定命名空间隔离

这条链路很多人会绕晕。一次说清：

```
XRD spec.scope: Namespaced
        ↓
Composition 组合出的 MR 默认也是 Namespaced
        ↓
MR 的 apiVersion 用命名空间版：container.gcp.m.upbound.io/v1beta1
        ↓
MR 落在 XR 所在的 namespace（team-a-project-a）
        ↓
providerConfigRef 默认指向名为 default 的 ClusterProviderConfig（集群级）
```

如果 XRD 是 `scope: Cluster`，MR 就得用 `container.gcp.upbound.io/v1beta2`，
MR 会落在集群级，`providerConfigRef` 也变成集群级引用。

本方案选 **`scope: Namespaced`**：团队天然按 namespace 隔离，
删团队 namespace 就等于清理该团队所有 MR。

---

## 5. 端到端时序

```mermaid
sequenceDiagram
    autonumber
    participant Dev as 开发者
    participant Git as Git 仓库
    participant RS as argocd-repo-server
    participant AC as argocd-application-controller
    participant API as K8s API Server
    participant XP as Crossplane Core
    participant FN as function-go-templating
    participant PV as provider-gcp-container
    participant GCP as GCP API

    Dev->>Git: T0 push + PR 合并
    RS->>Git: T1 git fetch（轮询或 webhook）
    AC->>RS: T2 取 manifest
    AC->>API: T3 apply XR（带 argocd.argoproj.io/tracking-id）
    API-->>XP: T4 watch 事件：XR 新增
    XP->>FN: T5 RunFunctionRequest(observed XR)
    FN-->>XP: T6 返回 2 份期望 MR（Cluster + NodePool）
    XP->>API: T7 创建 MR 对象
    API-->>PV: T8 watch 事件：MR 新增
    PV->>GCP: T9 用 WI token 调 container.googleapis.com
    GCP-->>PV: T10 返回集群创建中
    PV->>API: T11 回写 MR.status.atProvider
    API-->>XP: T12 watch MR
    XP->>API: T13 回写 XR.status.conditions
```

### 逐拍说明

| 拍 | 谁在做什么 | 你会看到什么 |
|---|---|---|
| T1 | repo-server 拉取 commit | ArgoCD UI 的 Application 出现新 commit hash |
| T2 | repo-server 渲染目录里的 YAML | — |
| T3 | controller 对比 live vs desired，apply | `kubectl get gkeclusters -n team-a-project-a` 出现对象 |
| T4 | Crossplane 的 informer 收到 ADDED | XR 上出现 `crossplane.io/composition-resource-name` 之类的注解 |
| T5 | Core 调用 Function（gRPC over stdin/stdout） | `kubectl logs -n crossplane-system deploy/crossplane` |
| T6 | Function 返回 MR 期望 | — |
| T7 | Core 创建 MR | `kubectl get clusters.container.gcp.m.upbound.io -n team-a-project-a` |
| T8 | Provider 的 informer 收到 ADDED | Provider Pod 日志开始 apply |
| T9–T11 | Provider 调 GCP，回写 status | `gcloud container clusters list` 出现集群，MR 的 `Ready=True` |
| T12–T13 | Core 把 MR 状态聚合成 XR condition | XR `status.conditions[Ready].status=True` |

### 延迟预期

| 环节 | 典型延迟 | 能否更快 |
|---|---|---|
| Git → ArgoCD 发现 commit | **默认 2 分钟**（轮询） | 配 ArgoCD webhook（GitHub/GitLab → ArgoCD API），降到秒级 |
| ArgoCD → API Server | 秒级 | — |
| API Server → Crossplane 调谐 | **秒级**（v2 默认开启 realtime compositions） | 已是最优 |
| Crossplane → Provider 调谐 | 秒级（watch） | — |
| **GKE 集群真正建好** | **5–10 分钟** | 云端耗时，无法优化 |

> **realtime compositions 是 v2 相对 v1 最大的体验差异之一**：v1 靠 `pollInterval`
> 定期轮询（默认 1 分钟），v2 默认 watch 驱动，改动基本秒级反映到 XR。

---

## 6. 六个必须知道的交互细节

### 6.1 字段所有权：ArgoCD 只碰 `spec`，Crossplane 只碰 `status`

这是整套设计能共存的根基。ArgoCD 的 diff 基于
`last-applied-configuration` 注解做三方合并：

```
   last-applied (ArgoCD 写过的)      live (实际)        desired (Git 里的)
            ↓                            ↓                    ↓
                      ArgoCD 算差异 → apply
```

- Crossplane 写 `status` 和 `status.atProvider` → 这些字段**不在** `last-applied` 里
  → 不构成 diff；
- Crossplane 写的临时注解（如 `crossplane.io/external-create-pending`）在创建完成后
  会被移除 → 只造成短暂的 OutOfSync；
- ArgoCD 写 `spec` → Crossplane **不会**改 XR 的 `spec`（只读），所以不会打架。

**反过来说**：如果有人直接 `kubectl edit xr` 改了 `spec`，ArgoCD 的 `selfHeal: true`
会在下一次同步时把它改回 Git 里的版本。这正是我们要的行为。

### 6.2 namespace 覆盖规则（最容易踩的坑）

ArgoCD 官方对 `destination.namespace` 的定义是：

> The namespace will only be set for namespace-scoped resources that **have not set a value for .metadata.namespace**

也就是说：

| XR YAML 里 | ArgoCD 实际写入到 | `destination.namespace` 的作用 |
|---|---|---|
| **不写** `metadata.namespace` | `destination.namespace` | 生效 |
| 写了 `metadata.namespace: team-a` | **`team-a`**（manifest 优先） | **被忽略** |

**所以必须二选一，不能混着来：**

✅ 推荐：**XR YAML 不写 `metadata.namespace`**，namespace 完全由
`destination.namespace`（= ApplicationSet 的 `{{path.basename}}`）决定。
这样 AppProject 的 `destinations` 白名单、仓库目录名、实际 namespace 三者天然一致。

❌ 常见错误：ApplicationSet 用 `namespace: '{{path.basename}}'`（= `project-a`），
但 XR YAML 里写死了 `metadata.namespace: team-a` → ArgoCD 实际写到 `team-a`，
而 AppProject 只放行了 `project-a` → **Application 直接被拒，XR 永远创建不出来**。

> `poc-minimax.md` §3.3 的 XR 示例里写了 `metadata.namespace: team-a`，
> 与 ApplicationSet 的 `{{path.basename}}` 冲突。**实施时请按本节的推荐方案二选一修正。**

### 6.3 `prune`：删掉 Git 文件 = 删掉云上集群（最大的风险）

这是 GitOps 落到云资源上最锋利的一把刀。链路是：

```
Git 里删掉 XR 文件
   → ArgoCD 发现 desired 中少了这个对象
   → 自动同步执行 prune，DELETE 掉 XR 对象
   → Crossplane 看到 XR 被删 → 级联删除 MR
   → Provider 执行删除 → GCP 上的 GKE 集群没了
```

三个可选档位，按业务决定：

| 档位 | ArgoCD 侧 | Crossplane 侧 | 效果 | 适用 |
|---|---|---|---|---|
| **A. 只增不删**（推荐默认） | `prune: false` | `deletionPolicy: Delete` | Git 删文件 **不会** 删集群；XR 仍在集群里，需要显式 `kubectl delete xr` 才真正删 | PoC / 生产默认 |
| B. 孤儿化 | `prune: true` | MR `deletionPolicy: Orphan` | Git 删文件 → XR 删 → **云资源保留**（变孤儿，需人工清理） | 下线但保留数据 |
| C. 全量跟随 | `prune: true` | MR `deletionPolicy: Delete` | Git 删文件 = 云集群消失 | **仅限测试环境** |

另外 `allowEmpty` 默认是 `false`，这会阻止"把仓库目录清空"导致的全量删除——
这一层保护是默认开的，别去关它。

> 无论选哪档，都建议在团队仓库加一条 CI 检查：
> **删除 XR 文件的 PR 必须打上 `deletes-resource` 标签 + 平台团队审批**。

### 6.4 `selfHeal` 的语义

`selfHeal: true` = 当集群里的对象和 Git 不一致时，ArgoCD 主动改回 Git 的版本。

对 XR 而言，这意味着：

- 有人 `kubectl edit xr` 改了 `spec` → ArgoCD 改回去 ✅（想要的行为）
- Crossplane 改了 `status` → ArgoCD 不动 ✅（字段所有权分离）
- 有人 `kubectl delete xr` → ArgoCD **不会**重建（自愈只针对"对象还在但内容漂移"，
  彻底删除后 ArgoCD 会把它当作"desired 中存在但 live 中缺失"重新创建——**确实会重建**，
  然后 Crossplane 又去把云集群建一遍）

最后一条要小心：**手工 `kubectl delete xr` 在 `selfHeal: true` 下会被 ArgoCD 撤销**，
XR 复活 → Crossplane 重建云集群（或者因为 `deletionPolicy` 而行为不同）。
这是"想删却删不掉"的经典困惑，删除请走 §6.3 的显式流程。

### 6.5 CRD 还没建好时，ArgoCD 会先失败一次

XRD 会生成一个 CRD。如果团队在 XRD 还没 apply 成功时就提了 XR，
ArgoCD 会报：

```
Failed to load target state: failed to create unstructured: no matches for kind "GKECluster"
```

这是**正常的引导顺序问题**，ArgoCD 的自动同步默认会重试 5 次
（5s / 10s / 20s / 40s / 80s 退避），CRD 建好后即恢复。

治理方式：

- 平台流水线先 apply XRD / Composition，**再**开放团队提交 XR 的入口；
- ApplicationSet 的 `syncPolicy.retry` 调大（例如 `limit: 10`）；
- 团队仓库加 pre-commit / CI 校验：本地 `crossplane render` 能过才允许合并。

### 6.6 渲染校验放 CI，不要放 ArgoCD

`crossplane render` 可以在**不连集群**的情况下用 Docker 跑 Function，
本地预览 Composition 会渲染成什么。这是把"渲染失败"挡在 PR 之前的最有效手段：

```bash
crossplane render xr.yaml composition.yaml functions.yaml
```

CI 里加一步 `crossplane render` + `kubeconform`，比在 ArgoCD 里看报错快得多。

---

## 7. 排查手册

| 症状 | 最可能的原因 | 排查命令 |
|---|---|---|
| Application 卡在 `Unknown` | repo 凭据不对 / SSH host key 未配 | `kubectl -n argocd logs deploy/argocd-repo-server \| grep -i error` |
| Application `OutOfSync`，diff 里 XR 一直存在 | `metadata.namespace` 与 `destination.namespace` 冲突 | `kubectl -n argocd get application <name> -o yaml` 看 destination 与 AppProject |
| Application `Progressing` / `Failed` | AppProject 白名单没放行该 kind/namespace | `kubectl -n argocd describe appproject team-a` |
| XR 存在但 `status.conditions` 为空 | Composition 没匹配上（`compositionRef` / `defaultCompositionRef` 未设） | `kubectl -n <ns> describe gkeclusters <name>` |
| XR 有 `Ready=False`，reason 是 `CannotResolveReferences` | NodePool 的 `clusterRef` 解析不到 Cluster | 看 NodePool MR 的 events |
| MR 一直 `Creating` | Provider 没装好 / WI 未生效 | `kubectl -n crossplane-system get providers` + `kubectl -n crossplane-system logs deploy/provider-gcp-container-xxx` |
| MR `Synced=False`，报 403 | 目标 Project 没给 GSA 授权 / API 未启用 | `gcloud projects get-iam-policy <target-project>` |
| 云上集群建出来但没有节点 | Standard 集群漏了 `removeDefaultNodePool` + NodePool MR | `kubectl -n <ns> get nodepools.container.gcp.m.upbound.io` |
| ArgoCD UI 卡顿 / API Server QPS 打满 | 没配 `resource.exclusions`，QPS 没调 | `kubectl -n argocd get cm argocd-cm -o yaml` |
| Git 删了文件但集群还在（且 `prune: false`） | 这是预期行为，见 §6.3 | — |
| 想删却删不掉 | `selfHeal: true` 把 XR 复活了 | 见 §6.4 |

---

## 8. 落地清单（按顺序做，每步都有验收）

### 第 1 天：让 ArgoCD 能说话

| # | 动作 | 验收 |
|---|---|---|
| 1 | ArgoCD 装进控制集群 | `kubectl -n argocd get pods` 全 Running，含 applicationset-controller |
| 2 | 配 `argocd-cm`：`resourceTrackingMethod` + `resource.exclusions` | `kubectl -n argocd get cm argocd-cm -o yaml` |
| 3 | `ARGOCD_K8S_CLIENT_QPS=300` 加到 application-controller | `kubectl -n argocd set env deploy/argocd-application-controller ARGOCD_K8S_CLIENT_QPS=300` |
| 4 | 配 Git 仓库凭据 Secret | `argocd repo list`（CLI）能列出仓库且状态 Connected |

### 第 2 天：让 ArgoCD 能写 XR

| # | 动作 | 验收 |
|---|---|---|
| 5 | 建 `argocd-xr-writer` ClusterRole + Binding | `kubectl auth can-i create gkeclusters.platform.example.org --as=system:serviceaccount:argocd:argocd-application-controller` 返回 yes |
| 6 | 建 `AppProject: team-a` | `kubectl -n argocd get appproject team-a` |
| 7 | 建 `ApplicationSet: team-a-xr` | `kubectl -n argocd get applicationset team-a-xr` → `NUMBER GENERATED` = 目录数 |
| 8 | 仓库里放一个测试 XR，**不写 `metadata.namespace`** | Application 变 Synced，XR 出现在 `project-a` namespace |

### 第 3 天：让 Crossplane 接管

| # | 动作 | 验收 |
|---|---|---|
| 9 | XRD / Composition / ProviderConfig 由平台 ArgoCD App 托管 | `kubectl get xrd,composition,clusterproviderconfig` |
| 10 | Provider `HEALTHY=True` | `kubectl -n crossplane-system get providers` |
| 11 | 提交 XR | MR（Cluster + NodePool）出现并 Ready |
| 12 | 集群出现 | `gcloud container clusters list` → RUNNING |
| 13 | 反向验证：直接 `kubectl edit xr` 改 label | ArgoCD 把它改回去（selfHeal 生效） |
| 14 | 反向验证：`kubectl patch mr --type=merge` 改云上标签 | Crossplane 把它纠正回去（漂移修复生效） |

---

## 附录 A. 核实来源

| 核实项 | 来源 |
|---|---|
| ArgoCD 最新稳定版 v3.5.6（2026-10-20） | `api.github.com/repos/argoproj/argo-cd/releases` |
| ArgoCD 内置 `_.upbound.io` / `_.crossplane.io` health.lua | `argoproj/argo-cd` v3.5.6 `resource_customizations/` 目录 |
| ArgoCD 3.x install.yaml 含 applicationset-controller | `argoproj/argo-cd` v3.5.6 `manifests/base/kustomization.yaml` |
| `destination.namespace` 的覆盖规则 | `argoproj/argo-cd` v3.5.6 `docs/operator-manual/application.yaml` |
| `syncPolicy` / `syncOptions` 默认值 | 同上 |
| `ServerSideApply=true` 支持 | `argoproj/argo-cd` v3.5.6 `controller/sync.go` |
| 集群凭据 Secret 结构 | `argoproj/argo-cd` v3.5.6 `docs/operator-manual/declarative-setup.md` |
| repo / repo-creds Secret 标签 | `argoproj/argo-cd` `docs/user-guide/private-repositories.md` |
| `resourceTrackingMethod` 默认值 = annotation | `argoproj/argo-cd` `docs/user-guide/resource_tracking.md` |
| Crossplane 与 ArgoCD 的三项官方建议 | `crossplane/docs` v2.4 `guides/crossplane-with-argo-cd.md` |
| Crossplane Core 的聚合 ClusterRole 机制 | `crossplane/crossplane` v2.4.3 `cluster/charts/crossplane/templates/clusterrole.yaml` |
| RBAC Manager 职责 | 同上 `templates/rbac-manager-clusterrole.yaml` |
| `provider.defaultActivations`（默认 MRAP 生成方式） | 同上 `templates/deployment.yaml` + `values.yaml` |
| Crossplane v2 realtime compositions 默认开启 | `crossplane/crossplane` v2.4.0 release notes |

---

## 附录 B. 与 `poc-minimax.md` 的差异说明

本文在核实过程中发现主文档有 3 处需要修订（**尚未修改主文档，等你确认**）：

| # | 位置 | 现写法 | 应改为 |
|---|---|---|---|
| 1 | §3.3 / §3.4 | ApplicationSet 用 `namespace: '{{path.basename}}'`，XR YAML 写 `metadata.namespace: team-a` | 二选一（推荐 XR 不写 namespace）；见本文 §6.2 |
| 2 | §3.4 | 要求配 `resource.customizations` 的 health.lua | ArgoCD ≥ 3.x 已内置 `_.upbound.io` / `_.crossplane.io`，**不需要配**；见本文 §3.8 |
| 3 | §4.5.8 | MRAP 收敛方式标 `【待核实】` | Helm 值 `provider.defaultActivations` 直接控制默认 MRAP；见本文附录 A |
