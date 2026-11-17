# 05 · ApplicationSet 批量分发

> 目标：**不为每个环境手工创建 Application**，用 ApplicationSet 从 Git 自动生成。

---

## 1. AppProject → ApplicationSet → Application 的关系

```
┌─────────────────────────────┐
│  AppProject                 │  ← 边界：允许的源 / 目标 / 资源类型 / 项目角色
│  (命名空间: argocd)          │     定义"能做什么"
└──────────────┬──────────────┘
               │ 逻辑引用（不是 ownerReference）
               │ template.spec.project: "platform-dev"
               ▼
┌─────────────────────────────┐
│  ApplicationSet             │  ← 模板 + 生成器
│  (命名空间: argocd)          │     定义"生成什么、生成到哪"
└──────────────┬──────────────┘
               │ 生成（带 ownerReference）
               ▼
┌─────────────────────────────┐
│  Application × N            │  ← 真实同步单元
│  (命名空间: argocd)          │     每个有自己的 targetRevision / destination
└─────────────────────────────┘
```

### ⚠️ 三个必须纠正的常见误解

| 误解 | 事实 |
|---|---|
| "Application 继承 AppProject 的全部权限" | ❌ AppProject 定义**资源约束**；**谁能操作**这些 Application 由 Argo CD RBAC 决定。两者独立 |
| "`AppProject → ApplicationSet → Application` 是 owner 链" | ❌ **不是**。AppProject 与 ApplicationSet 之间**没有** ownerReference，是纯粹的逻辑引用。AppProject 被删，Application 不会级联删除（除非 ApplicationSet 本身被删） |
| "ApplicationSet 的模板里不写 `project`，会继承 ApplicationSet 所在的项目" | ❌ **不写就是 `default` 项目**。`default` 默认是最宽松的（任意源、任意目标、任意资源类型）——这是重大安全风险 |

**上游 Security 文档的原话（务必读）**：

> It's important to pay special attention to ApplicationSets where the `project`
> field is templated. A malicious user with write access to the generator's source
> of truth [...] could create Applications under Projects with insufficient
> restrictions. A malicious user with the ability to create an Application under an
> unrestricted Project (like the `default` Project) could take control of Argo CD
> itself by, for example, modifying its RBAC ConfigMap.

---

## 2. 生成器选型

| 生成器 | 用途 | 何时选它 |
|---|---|---|
| **List** | 硬编码元素列表 | 最简单；环境数量固定且很少变 |
| **Cluster** | 遍历 Argo CD 已注册的集群 | 多集群分发；用 label selector 过滤 |
| **Git** | 遍历 Git 仓库目录 / 文件 | **最常用**：仓库里加个目录就自动多一个 Application |
| **Matrix** | 多个子生成器的**笛卡尔积** | 应用 × 集群 的组合分发 |
| **Merge** | 多个子生成器按 key **合并** | 不同维度信息拼接到一个 Application |
| **SCM Provider** | SCM Provider 定义的集群 | 用 Cluster API 动态拉集群 |
| **Pull Request** | 每个 PR 一个 Application | PR 环境预览 |
| **OCI** | 从 OCI registry 拉 Application | 应用模板打包分发 |
| **Plugin** | 自定义生成器 | 特殊逻辑 |

### 2.1 Matrix vs Merge —— 最需要分清的两个

| | **Matrix** | **Merge** |
|---|---|---|
| 语义 | 笛卡尔积（A × B × C） | 按 key 合并（A + B，key 相同的合到一起） |
| 子生成器之间 | **完全独立**，各出各的参数集 | 需要有**共同的 merge key** |
| 参数冲突 | 每个子生成器的参数都会出现在结果里，**同名会覆盖**（后一个赢） | 同 key 的值合并成一个参数集 |
| 典型用途 | 「这个 Git 目录下的 5 个应用 × 3 个集群 = 15 个 Application」 | 「基础集群清单 + 环境覆盖清单 = 每环境一份完整配置」 |

**上游 Merge 文档的关键限制：**

1. **每个生成器必须写在独立的数组元素里**（虽然 K8s API 校验会通过，但 controller 报错）
2. **不支持子生成器上的 `template` 覆盖**
3. **组合型生成器（Matrix/Merge）只能嵌套一层**（merge 里不能再 merge）
4. **`goTemplate: true` 时不支持嵌套值合并**

> ⚠️ 第 1 条特别容易踩：写成 `- merge: {generators: [{list: ...}, {git: ...}]}`
> 会被 controller 报错。正确写法是：
> ```yaml
> generators:
> - merge:
>     generators:
>     - list:
>         elements: [...]
>     - git:
>         repoURL: ...
> ```

---

## 3. 完整实现

完整可复制示例见 [`examples/applicationset-matrix.yaml`](./examples/applicationset-matrix.yaml)。

### 3.1 方案 A：Git generator + Cluster generator + Matrix

**目标**：Git 里 `apps/*` 下每个目录生成一个 Application，部署到所有打了
`env=dev` 标签的集群。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform-apps
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]   # 缺参数直接报错，不要静默生成空字符串
  generators:
  - matrix:
      generators:
      # 子生成器 1：Git 目录
      - git:
          repoURL: https://github.com/example/platform.git
          revision: main
          directories:
          - path: apps/*
      # 子生成器 2：Argo CD 已注册集群（按 label 过滤）
      - clusters:
          selector:
            matchLabels:
              env: dev
              argocd.argoproj.io/secret-type: cluster
  template:
    metadata:
      name: '{{.path.basename}}-{{.name}}'
      labels:
        app.kubernetes.io/part-of: platform
    spec:
      project: platform-dev            # ← 必须显式写！
      source:
        repoURL: https://github.com/example/platform.git
        targetRevision: main
        path: '{{.path.path}}'
      destination:
        server: '{{.server}}'
        namespace: '{{.path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

**参数来源对照：**

| 模板变量 | 来自 |
|---|---|
| `{{.path.path}}` | Git generator 的目录路径 |
| `{{.path.basename}}` | Git generator 的目录名 |
| `{{.name}}` | Cluster generator 的集群名 |
| `{{.server}}` | Cluster generator 的集群 API 地址 |

> `{{.server}}` 与 `{{.name}}` 是 Cluster generator 特有的。Git generator 产出
> `path` 系列参数，Cluster generator 产出 `name` / `server` / `metadata` 等参数。

### 3.2 方案 B：Git generator + List（环境维度）

**目标**：Git 里 `envs/dev/apps/*` 的目录结构决定环境，同一套应用按环境分发。

```
platform/
├── apps/
│   ├── api/
│   └── web/
└── envs/
    ├── dev/
    │   └── values.yaml
    └── prod/
        └── values.yaml
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform-env-apps
  namespace: argocd
spec:
  goTemplate: true
  generators:
  - git:
      repoURL: https://github.com/example/platform.git
      revision: main
      directories:
      - path: apps/*
  - list:
      elements:
      - env: dev
        namespace: platform-dev
        project: platform-dev
        valuesPath: envs/dev/values.yaml
      - env: prod
        namespace: platform-prod
        project: platform-prod
        valuesPath: envs/prod/values.yaml
  template:
    metadata:
      name: '{{.path.basename}}-{{.env}}'
    spec:
      project: '{{.project}}'
      source:
        repoURL: https://github.com/example/platform.git
        targetRevision: main
        path: '{{.path.path}}'
        helm:
          valueFiles:
          - '${{.valuesPath}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.namespace}}'
```

**注意 `valueFiles` 里的 `${{` 写法**——这是 Helm 变量和 Argo CD 模板变量的
转义约定：双写 `$` 表示"这是 Helm 的模板，不是 Argo CD 的"。

> ⚠️ **`syncPolicy.automated.prune` / `selfHeal` 不能模板化。**
> ApplicationSet CRD 里这两个字段的类型是 `boolean`
> （依据本仓库 `install.yaml:8007-8018`，v3.5.6 官方清单），
> 写成 `prune: '{{.prune}}'` 会被 API server 以
> “must be of type boolean” 拒绝。
>
> **后果**：无法用一个 ApplicationSet + 模板区分「dev 自动 selfHeal、prod 不自动」。
> **解法**：同步策略不同的环境**拆成不同的 ApplicationSet**，
> 用 git 文件生成器的 `selector`（JMESPath，如 `env == "prod"`）过滤环境清单。
> 完整示例见 [`examples/applicationset-matrix.yaml`](./examples/applicationset-matrix.yaml) 末尾「变体」。

### 3.3 方案 C：Merge generator（基础 + 覆盖）

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform-merged
  namespace: argocd
spec:
  goTemplate: true
  generators:
  - merge:
      generators:
      # 基础：所有集群
      - clusters:
          selector:
            matchLabels:
              argocd.argoproj.io/secret-type: cluster
      # 覆盖：只有 staging 集群有额外参数
      - list:
          elements:
          - name: staging
            extraReplicas: '3'
  template:
    metadata:
      name: '{{.name}}'
    spec:
      project: platform
      source:
        repoURL: https://github.com/example/platform.git
        targetRevision: main
        path: 'deploy/{{.name}}'
      destination:
        server: '{{.server}}'
        namespace: '{{.name}}'
```

### 3.4 `goTemplate` 的取舍

| | `goTemplate: false`（默认） | `goTemplate: true` |
|---|---|---|
| 语法 | `{{path}}` | `{{.path.basename}}` |
| 缺参数时 | 渲染成空字符串，**静默出错** | 配合 `goTemplateOptions: ["missingkey=error"]` **直接报错** |
| 能力 | 只能取顶层参数 | 完整 Go text/template：函数、管道、字段访问 |

**推荐一律用 `goTemplate: true` + `missingkey=error`。**
默认模式下参数名写错会渲染成空路径，产生的 Application 报 "path not found"，
排查起来非常浪费时间。

---

## 4. 生成的 Application 如何选择 AppProject

**唯一入口是 `template.spec.project`。**

```yaml
  template:
    spec:
      project: platform-dev        # 硬编码
```
或
```yaml
  template:
    spec:
      project: '{{.project}}'      # 从生成器参数来
```

### 4.1 三种策略

| 策略 | 写法 | 适用 | 风险 |
|---|---|---|---|
| **硬编码** | `project: platform-dev` | 一个 AppSet 只服务一个项目 | ⭐ **最安全，推荐** |
| **模板化（受控）** | `project: 'platform-{{.env}}'` | 项目名可预测，来源受控 | 中。必须确保生成器所有来源都被管理员控制 |
| **模板化（开放）** | `project: '{{.project}}'`，值来自 Git | ❌ **不要在生产用** | 高。恶意 commit 可把 Application 投递到宽松项目 |

**上游 Security 文档的要求**：

> If the `project` field is not hard-coded in an ApplicationSet's template, then
> admins *must* control all sources of truth for the ApplicationSet's generators.

即：**用了模板化 `project`，就必须严格控制生成器的所有数据来源**
（Git 仓库写权限、集群 label、List 元素的修改权限）。

### 4.2 生成的 Application 的权限从哪来

生成的 Application 落在 `platform-dev` 项目后：

- 它受 **AppProject `platform-dev`** 的源/目标/资源约束
- 但**谁能操作这个 Application**，取决于 **Argo CD RBAC** 里有没有
  `p, <group>, applications, *, platform-dev/*, allow` 这样的规则

**这正是三层模型在 ApplicationSet 场景下的体现**——见
[`04-appproject-rbac.md`](./04-appproject-rbac.md) §1。

### 4.3 生成物不自动继承项目角色

**常见误解**：把 `devops-team-alpha` 加进 AppProject 的 `roles.groups`，
以为 ApplicationSet 生成的 Application 就自动对这个组开放了。

**不对。** AppProject 的 `roles` 定义的是"**该项目的成员**"，即
`proj:<project>:<role>` 这个角色。而"谁是这个项目的成员"由
**AppProject 里的 `roles[].groups`** 决定 —— 这一步是对的。

但**用户能不能看到 / 操作 ApplicationSet 生成的 Application**，
由 Argo CD RBAC 全局策略决定。**推荐在全局 `argocd-rbac-cm` 里加一条**：

```yaml
  policy.csv: |
    p, devops-team-alpha, applications, *, platform-dev/*, allow
```

这样就不必在每个 AppProject 里重复写 `roles`。

---

## 5. 安全约束（上游 ApplicationSet Security 文档）

### 5.1 只有管理员能管理 ApplicationSet

上游原文：

> For these reasons, **only admins** may be given permission (via Kubernetes RBAC
> or any other mechanism) to create, update, or delete ApplicationSets.

**理由**（上游列举）：
1. ApplicationSet 可以在任意 Project 下创建 Application
2. 可以瞬间创建/删除任意数量的 Application
3. **git generator 能读取 Argo CD 命名空间里的 Secret，并把它们发到任意 URL**
   （作为 `api` 字段的 auth header）。这个功能本意是给 SCM provider 授权用的，
   但可以被滥用

**实施**：

```yaml
# 只允许特定组操作 ApplicationSet
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-appset-manager
rules:
- apiGroups: ["argoproj.io"]
  resources: ["applicationsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

同时在 `argocd-rbac-cm` 里：

```yaml
  policy.csv: |
    p, devops-platform, applicationsets, *, *, allow
```

### 5.2 即使非管理员不能建 AppSet，也要控制数据源

上游原文：

> Even if non-admins can't create ApplicationSet resources, they may be able to
> affect the behavior of ApplicationSets.

具体风险：**有 Git 仓库写权限的人，一次恶意 commit 就能生成成千上万个
Application**，拖垮 ApplicationSet controller 和 Application controller，
还可能触发 SCM provider 的速率限制。

**缓解**：
- 限制谁能 push 到 ApplicationSet 的源仓库
- 用 `List` 生成器时元素数量可控（Git generator 天然不可控）
- 监控 Application 数量异常增长

### 5.3 `preserveResourcesOnDeletion`

```yaml
  template:
    metadata:
      name: '{{.path.basename}}'
    spec:
      preserveResourcesOnDeletion: true
```

加上这个，删除 Application 时**不会**删除目标集群里的资源。

**上游 Application-Deletion 文档的行为**：

| 场景 | `preserveResourcesOnDeletion` | 结果 |
|---|---|---|
| 删 Application（该字段 true） | true | 集群资源保留 |
| 删 Application（该字段 false 或未设） | — | **集群资源被级联删除** ⚠️ |
| 删 ApplicationSet | 取决于生成的 Application 上该字段 | 生成的 Application 被删 → 连带资源 |

> ⚠️ **删 ApplicationSet 前先确认**：
> 1. 生成的 Application 上有 `preserveResourcesOnDeletion: true` 吗？
> 2. AppProject 上有 `resources-finalizer.argocd.argoproj.io` 吗？
> 3. 目标集群里的资源你确定可以删吗？

---

## 6. Progressive Syncs（渐进式同步）

多集群渐进式分发（上游 `Progressive-Syncs.md`）：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: progressive
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          argocd.argoproj.io/secret-type: cluster
  progressiveSync:
    appsyncOrder: '{{.name}}'          # 排序依据
    appsyncWave: 1                      # 波次
  template:
    metadata:
      name: '{{.name}}'
    spec:
      syncPolicy:
        syncOptions:
        - CreateNamespace=true
```

配合 `Application` 的 `spec.syncPolicy` 中的 `retry` 和
`status.operationState` 中的 phase 字段，controller 会等前一个波次成功才推进。

> Progressive Syncs 是相对较新的特性，上游标注了版本要求。
> 实施前确认你的 Argo CD 版本支持（v3.5.6 应该支持，但建议先在测试集群验证）。

---

## 7. 验证

```bash
# ① AppSet 是否健康
kubectl -n argocd get applicationset
kubectl -n argocd describe applicationset platform-apps

# ② 生成了哪些 Application
kubectl -n argocd get applications -l argocd.argoproj.io/application-set-name=platform-apps

# ③ 每个 Application 落在哪个 project（重点检查有没有落到 default！）
kubectl -n argocd get applications -o custom-columns='NAME:.metadata.name,PROJECT:.spec.project'

# ④ 检查 AppSet controller 日志里的生成错误
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-applicationset-controller --tail=100

# ⑤ 检查生成的 Application 的 spec 是否被正确渲染（没有空字符串）
kubectl -n argocd get application platform-apps-dev-api -o jsonpath='{.spec.source.path}{"\n"}'
kubectl -n argocd get application platform-apps-dev-api -o jsonpath='{.spec.destination.namespace}{"\n"}'

# ⑥ 检查是否有 Application 落在 default project（应该是 0）
kubectl -n argocd get applications -o jsonpath='{range .items[?(@.spec.project=="default")]}{.metadata.name}{"\n"}{end}'
```

---

## 8. 排障

| 现象 | 根因 | 处理 |
|---|---|---|
| 生成的 Application 报 "path not found" | 模板变量名写错，默认模式下渲染成空字符串 | 开 `goTemplate: true` + `missingkey=error`；核对变量名（Git → `.path.*`，Cluster → `.name` / `.server`） |
| 所有 Application 都落在 `default` 项目 | `template.spec.project` 没写 | **必须显式写** `project` |
| `goTemplate` 下参数取不到 | 用了 `{{.path}}` 而非 `{{.path.path}}` | Go template 是结构化访问，需要完整路径 |
| Merge generator 报错 | 多个生成器写在了同一个数组元素里 | 每个生成器独立成 `- xxx:` 元素 |
| Matrix 结果数量爆炸 | 子生成器组合数太大 | 检查 Git 目录数 × 集群数 |
| `valuesFiles` 里的 `{{.xxx}}` 被 Argo CD 渲染掉了 | Argo CD 与 Helm 模板变量冲突 | 用 `${{.xxx}}`（双写 `$`） |
| AppSet 状态正常但 Application 没创建 | ApplicationSet 控制器无权访问 Git 仓库 | 检查 Repository Secret；见 [`07-repository-githubapp.md`](./07-repository-githubapp.md) |
| 删了 AppSet，集群资源全没了 | 生成的 Application 没设 `preserveResourcesOnDeletion` | 加该字段；**已经删了只能从 Git 重新 apply 恢复** |
| 生成的 Application 没权限操作 | Argo CD RBAC 没给对应组权限 | 在 `argocd-rbac-cm` 加 `p, <group>, applications, *, <project>/*, allow` |
| Git generator 读不到仓库里的目录 | 路径 glob 不对 / 目录里没有 kustomization.yaml | 确认 `path` 匹配；目录需含 `kustomization.yaml` 或 `Chart.yaml` |
| 大量 Application 导致 controller 压力大 | 生成器数据源不受控 | 限制 Git 仓库写权限；见 §5.2 |

---

## 9. 关联文档

| 主题 | 文档 |
|---|---|
| AppProject 与 RBAC 的三层边界 | [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| Git 仓库凭据（Git generator 依赖） | [`07-repository-githubapp.md`](./07-repository-githubapp.md) |
| `Application` 字段详解 | [`../argocd-application-guide.md`](../argocd-application-guide.md) |
| `ApplicationSet` vs `Application` 概念对比（更简短） | [`../argocd-applicationset-vs-application.md`](../argocd-applicationset-vs-application.md) |
| 已有 Application 示例 | [`../examples/argocd-application/09-applicationset-team.yaml`](../examples/argocd-application/09-applicationset-team.yaml) |
