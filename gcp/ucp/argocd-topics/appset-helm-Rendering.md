# 06 · ApplicationSet 的 Helm 渲染（CP 仓库 → Tenant 仓库）

> 目标：把「**ApplicationSet 本身是由 Helm 渲染出来的**」这件事讲透：
> 谁渲染谁、模板在哪一层生效、两层模板引擎打架时怎么转义、
> 集群信息仓库（Tenant Repository）怎么接进来。

配套可运行示例：[`examples/appset-helm/`](./examples/appset-helm/)

---

## 0. 场景与术语

### 0.1 一句话场景

> Argo CD 控制面（CP）的 Git 仓库里放一个 **Helm chart**；
> 这个 chart 渲染出 **ApplicationSet**；
> ApplicationSet 的生成器去读**另一个仓库**（Tenant Repository / 集群清单仓库），
> 那里写着「我要纳管哪些集群、每个集群装什么」；
> 最终每个集群得到一个 **Application**（Cluster Application），
> 应用内容用 Helm 渲染，值来自该集群自己的 values 文件。

```
┌──────────────────────────────────────────────────────────────┐
│  CP Repository（控制面仓库）                                  │
│  charts/platform-cp/                                         │
│    values.yaml   ← 租户清单（project / 仓库地址 定在这儿）      │
│    templates/    ← 渲染出 AppProject + ApplicationSet         │
└───────────────┬──────────────────────────────────────────────┘
                │ Argo CD: helm template（repo-server）
                ▼
┌──────────────────────────────────────────────────────────────┐
│  ApplicationSet CR（集群里）                                  │
│  generators: git → Tenant Repository                         │
│  template:    这里是「AppSet 模板」语法（不是 Helm 语法）      │
└───────────────┬──────────────────────────────────────────────┘
                │ ApplicationSet controller: Go template
                ▼
┌──────────────────────────────────────────────────────────────┐
│  Application × N（每集群 × 每应用 一个）                      │
│  source.helm.valueFiles → Tenant Repository 里的集群 values    │
└───────────────┬──────────────────────────────────────────────┘
                │ Argo CD repo-server: helm template（第二层 Helm）
                ▼
              目标集群
```

### 0.2 三个角色，别搞混

| 角色 | 是谁 | 放什么 | 谁读它 |
|---|---|---|---|
| **CP Repository**（控制面仓库） | Argo CD 管理员 | CP 的 Helm chart、租户清单、AppProject、RBAC 片段 | Argo CD repo-server（渲染） |
| **Tenant Repository**（租户/集群仓库） | 各租户 / 平台运维 | 集群元信息（`clusters/*/cluster.yaml`）、应用 chart、每集群的 values | ApplicationSet 生成器 + repo-server |
| **集群本身** | — | K8s 集群 | Argo CD 需要它注册成 cluster secret 才能投递 |

> ⚠️ **谁有权 push CP 仓库 = 谁有权在 Argo CD 里创建任意 Application。**
> Helm chart 的 `templates/` 是任意模板逻辑，等价于代码执行面。
> 见 [§8 安全](#8-安全)。

### 0.3 两种「Helm 渲染」，最容易混

| | **H1：Helm 渲染出 ApplicationSet** | **H2：ApplicationSet 生成的 Application 用 Helm 渲染** |
|---|---|---|
| 谁的模板 | CP chart 的 `templates/*.yaml` | Application 的 `spec.source.helm`（目标应用自己的 chart） |
| 发生在 | CP 仓库渲染时 | Application 被同步时（repo-server） |
| 模板语法 | Helm 语法 | **目标 chart 的** Helm 语法 |
| 本文档 | ✅ 主线 | §4.7 顺带讲清 |

本文主线是 **H1**，同时把 H2 串起来 —— 因为它们会在**同一个文件里相遇**（chart 里的 ApplicationSet 模板里写着 `source.helm.valueFiles`）。

### 0.4 本文假设的版本

- Argo CD **v3.x**（仓库 `install.yaml` 为 v3.5.6 官方清单）
- Helm **v3**（chart 语法；Helm 4 行为一致）
- ApplicationSet **goTemplate 模式**（`spec.goTemplate: true`）

---

## 1. 三层模板引擎的边界

**这是全文最重要的一张表。** 同一段文本可能被三个引擎依次看到。

| 顺序 | 引擎 | 作用对象 | 语法 | 出错时的表现 |
|---|---|---|---|---|
| ① | **Helm**（repo-server） | CP chart 的 `templates/*.yaml` | `{{ .Values.x }}` | 渲染成空串 / `nil pointer evaluating interface {}.x` |
| ② | **ApplicationSet controller**（Go template） | ApplicationSet 的 `spec.template`（以及 generator 里的 `template`） | `{{ .xxx }}` | 渲染成空串 / `missingkey=error` 时直接报错 |
| ③ | **Helm**（repo-server，再来一次） | 目标应用的 chart | `{{ .Values.x }}` | 应用渲染失败，Application 报 `ComparisonError` |

**关键推论：① 和 ② 会作用在同一段文本上。**

CP chart 模板里写的这一行：

```yaml
      name: '{{ .app.path.basename }}-{{ .cluster.path.basename }}'
```

在 ① 阶段，Helm 看到 `{{ .app.path.basename }}`，认为这是**自己的**表达式 →
`.app` 在 Helm 的上下文里不存在 → **渲染成空串**（`name: '--'`）或者直接报错。

于是 ② 阶段拿到的是空字符串 → Application 名字变成 `--`，或者
`missingkey=error` 直接让整个 AppSet 报错。

**上游对这个问题的原文**（`docs/operator-manual/applicationset/Template.md`）：

> ApplicationSet uses the same templating notation as Helm (`{{}}`).
> When Helm renders the chart templates, it will also process the template
> meant for ApplicationSet rendering. If the ApplicationSet template uses a
> function like:
> ```yaml
>     metadata:
>       name: '{{ "guestbook" | normalize }}'
> ```
> Helm will throw an error like: `function "normalize" not defined`.
> If the ApplicationSet template uses a generator parameter like:
> ```yaml
>     metadata:
>       name: '{{.cluster}}-guestbook'
> ```
> Helm will silently replace `.cluster` with an empty string.
>
> To avoid those errors, write the template as a Helm string literal. For example:
> ```yaml
>     metadata:
>       name: '{{`{{ .cluster | normalize }}`}}-guestbook'
> ```
> This _only_ applies if you use Helm to deploy your ApplicationSet resources.

### 1.1 ⚠️ 纠正一个流传很广的写法：`${{ }}`

很多资料（包括本仓库早期版本）会说：

> 「双写 `$` 表示这是 Helm 的模板，不是 Argo CD 的」→ 写 `valueFiles: - '${{.valuesPath}}'`」

**这个说法在当前 Argo CD 里是错的。** 实测（`goTemplate: true` 的 Go template 引擎）：

```go
// 输入："valueFiles: - '${{ .valuesPath }}'"，params: valuesPath=clusters/dev/values.yaml
// 输出："valueFiles: - '$clusters/dev/values.yaml'"
```

**`$` 会被原样留下**，变成一个不存在的路径 → `values file not found`。
（`goTemplate: false` 的 fasttemplate 引擎同理：它只认 `{{tag}}` 这一段，
前面的 `$` 同样是普通文本。）

上游代码里 `valueFiles` 唯一与 `$` 有关的语义是**多源引用**：

```go
// reposerver/repository/repository.go
if !strings.HasPrefix(valueFile, "$") {
    continue
}
refVar, _, _ := strings.Cut(valueFile, "/")   // $values/xxx.yaml → 引用 ref: values 那个源
```

即 `$values/xxx.yaml` 里的 `$` 表示「**这个文件在 `ref: values` 那个源里**」，
和「转义」没有任何关系（见 [§4.8](#48-值文件路径跨目录跨仓库)）。

**正确写法对照表：**

| 想表达的意思 | ❌ 错 | ✅ 对 |
|---|---|---|
| ApplicationSet 模板变量 | `'${{.valuesPath}}'` | `'{{.valuesPath}}'`（AppSet controller 会替换） |
| Helm 自己的模板（在 chart 里） | — | `{{ .Values.x }}` |
| chart 里要**原样保留** AppSet 模板 | `{{.x}}` | `{{`{{ .x }}`}}`（Helm 字符串字面量） |

> 📌 上面这条纠正同时修正了
> [`05-appset.md`](./05-appset.md) §3.2 的说法（那里把 `${{.valuesPath}}`
> 写成了「Helm / Argo CD 转义约定」）。

---

## 2. Helm chart 里放 ApplicationSet：转义写法

### 2.1 三种写法

**写法 1（推荐）：Helm 字符串字面量** —— 直接照抄上游文档的写法：

```yaml
      name: '{{`{{ .app.path.basename }}-{{ .cluster.path.basename }}`}}'
```

渲染结果：`name: '{{ .app.path.basename }}-{{ .cluster.path.basename }}'`（一个字没动）。

**写法 2：helper 封装**（同一段转义要用很多次时）：

```yaml
{{/* _helpers.tpl */}}
{{- define "platform-cp.appsetVar" -}}
{{`{{ .`}}{{ . }}{{` }}`}}
{{- end -}}
```

```yaml
      name: '{{ include "platform-cp.appsetVar" "app.path.basename" }}-{{ include "platform-cp.appsetVar" "cluster.path.basename" }}'
```

渲染结果同上。示例见
[`examples/appset-helm/cp-chart/templates/_helpers.tpl`](./examples/appset-helm/cp-chart/templates/_helpers.tpl)。

**写法 3：拆文件** —— ApplicationSet 不放在 chart 里，chart 只渲染「数据」。

把租户清单渲染成一个 YAML 文件，再让 ApplicationSet 用 **Git file generator**
去读它（见 [§6](#6-模式-c让-appset-自己去-tenant-仓库发现集群)）。
代价：多一跳，且 ApplicationSet 自己还是得写在某个地方。

### 2.2 ⚠️ YAML 注释里的 `{{ }}` 也会被 Helm 解析

这是实测踩到的坑（`helm template` 直接报 `unexpected <.> in operand`）：

```yaml
  template:
    metadata:
      # '{{`...`}}' = Helm 字符串字面量      ← ❌ 注释里的 {{ }} 也被解析，报错
      name: '{{`{{ .app.path.basename }}`}}'
```

Helm 不区分「模板」和「注释」——它只扫描文本里的 `{{`。注释里的
`{{`...`}}` 会被当成动作，`.app` 不是合法 Go 表达式 → 解析错误。

**要么注释里别写裸大括号，要么用 Helm 自己的块注释：**

```yaml
{{- /*
  这里可以放心写 {{ .xxx }}，因为 Helm 注释不参与渲染
*/ -}}
```

示例文件里两种都用了：
[`examples/appset-helm/cp-chart/templates/applicationset-cluster-apps.yaml`](./examples/appset-helm/cp-chart/templates/applicationset-cluster-apps.yaml)。

### 2.3 转义自检

**转义写错时的三种症状：**

| 症状 | 原因 |
|---|---|
| `helm template` 报 `nil pointer evaluating interface {}.app` | 没转义，Helm 把 AppSet 变量当自己的了 |
| `helm template` 报 `unexpected <.> in operand` | 注释里有裸 `{{ }}`；或转义多套了一层反引号 |
| 渲染出来的 YAML 里 `name: '--'` / `path: ''` | 没转义，Helm 静默替换成空串（最阴的一种） |

**本地必须跑一次渲染再提交：**

```bash
helm template platform-cp examples/appset-helm/cp-chart | less
# 或者用仓库里准备好的检查脚本
./examples/appset-helm/render-check.sh
```

---

## 3. 仓库拓扑：CP Repository 与 Tenant Repository

### 3.1 目录结构

**CP Repository（控制面仓库）**

```
platform/
├── charts/
│   └── platform-cp/                 ← ⭐ CP 的 chart
│       ├── Chart.yaml
│       ├── values.yaml              ← 租户清单
│       └── templates/
│           ├── appproject-tenant.yaml
│           └── applicationset-cluster-apps.yaml
└── ...
```

**Tenant Repository（租户/集群仓库）**

```
tenant-cluster/
├── clusters/                        ← 集群事实来源
│   ├── dev-01/
│   │   ├── cluster.yaml             ← 集群元信息（file generator 读它）
│   │   └── values.yaml              ← 该集群的 Helm 覆盖值
│   └── prod-01/
│       ├── cluster.yaml
│       └── values.yaml
└── apps/                            ← 应用本体（所有集群共用一份）
    └── nginx/
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
```

### 3.2 谁读谁

| 读取方 | 读什么 | 凭据 |
|---|---|---|
| Argo CD repo-server | CP 仓库的 chart | CP 仓库的 Repository Secret |
| ApplicationSet controller | Tenant 仓库的目录/文件（生成器） | **Tenant 仓库自己的 Repository Secret**（另一份） |
| Argo CD repo-server | Tenant 仓库的应用 chart + values | 同上（同一个 Secret） |

> ⚠️ **CP 里必须同时有 CP 仓库和 Tenant 仓库的凭据。**
> 只配了 CP 仓库 → AppSet 状态正常但生成不出 Application
> （`Failed to generate application for param` / generator 报 auth 错误）。
> 凭据配置见 [`07-repository-githubapp.md`](./07-repository-githubapp.md)。
>
> 💡 **Tenant 仓库不需要是 public** —— 没配凭据时 Argo CD 会退化成
> **匿名 clone**（那才是 public 才够用的场景）。
> 凭据是**按仓库 URL** 配的，和「哪个仓库引用了它」无关；
> 原理与完整时序见
> [`helm-cross-repository.md`](./helm-cross-repository.md) §3。

### 3.3 仓库边界 = 安全边界

| 仓库 | 谁能 push | 推错了会怎样 |
|---|---|---|
| **CP Repository** | 只有平台管理员 | 能创建任意 Application、改任意 AppProject/RBAC → **等于给 Argo CD 后门** |
| **Tenant Repository** | 租户 / 平台运维 | 能决定「往哪些集群、装什么、值是多少」；**不能**改 project 和 RBAC（因为那些在 CP 侧硬编码） |

这条边界就是整套设计的核心价值：
**tenant 仓库的内容永远不应该能决定「这个 Application 归哪个 AppProject 管」。**

> ⚠️ 但边界不是自动的 —— **Argo CD 手里有几把钥匙，chart 就能指向哪几个仓库**。
> 谁能 push CP 仓库，谁就能让 Argo CD 去 clone 它有凭据的任意仓库
> （混淆代理风险）→ 缓解手段见
> [`helm-cross-repository.md`](./helm-cross-repository.md) §7.2。

---

## 4. 模式 A：CP chart → ApplicationSet → Application（主线）

### 4.1 chart 的 values.yaml（租户清单）

```yaml
# examples/appset-helm/cp-chart/values.yaml
tenants:
  - id: tenant-a
    repoURL: https://github.com/example/tenant-cluster.git
    revision: main
    project: tenant-a          # ⭐ AppProject / ApplicationSet 的 project 都用它
    appsPath: "apps/*"
    clustersPath: "clusters/*/cluster.yaml"
```

**这一份 values 就是「管理员控制面」的全部输入。**
`project` 在这里定，就意味着 tenant 仓库改不动它。

### 4.2 AppProject 模板（边界）

```yaml
# examples/appset-helm/cp-chart/templates/appproject-tenant.yaml
{{- range $t := .Values.tenants }}
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: {{ $t.project }}
  namespace: argocd
spec:
  description: "Tenant {{ $t.id }} 的资源边界"
  sourceRepos:
    - {{ $t.repoURL | quote }}
  destinations:
    - server: '*'
      namespace: '*'
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
  roles:
    - groups:
        - tenant-{{ $t.id }}-team
      server: '*'
      namespace: '*'
      sourceRepos:
        - {{ $t.repoURL | quote }}
{{- end }}
```

> 生产环境建议把 `destinations` 收紧成具体集群
> （`server: https://example-dev-01.k8s.example.internal`），
> 以及给 `clusterResourceWhitelist` 明确白名单。
> 边界怎么定见 [`04-appproject-rbac.md`](./04-appproject-rbac.md)。

### 4.3 ApplicationSet 模板（核心）

```yaml
# examples/appset-helm/cp-chart/templates/applicationset-cluster-apps.yaml
{{- range $t := .Values.tenants }}
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: {{ $t.id }}-cluster-apps
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: platform-cp
    platform.cp/tenant: {{ $t.id }}
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]

  generators:
    # ⚠️ 必须用 matrix 包裹（理由见 §4.4 末尾）
    - matrix:
        generators:
          # ① 应用清单：tenant 仓库里 apps/* 每个目录 = 一个应用
          - git:
              repoURL: {{ $t.repoURL | quote }}
              revision: {{ $t.revision | default "main" | quote }}
              pathParamPrefix: app
              directories:
                - path: {{ $t.appsPath | default "apps/*" | quote }}

          # ② 集群清单：tenant 仓库里 clusters/*/cluster.yaml 每个文件 = 一个集群
          - git:
              repoURL: {{ $t.repoURL | quote }}
              revision: {{ $t.revision | default "main" | quote }}
              pathParamPrefix: cluster
              files:
                - path: {{ $t.clustersPath | default "clusters/*/cluster.yaml" | quote }}

  template:
    metadata:
      name: '{{`{{ .app.path.basename }}-{{ .cluster.path.basename }}`}}'
      labels:
        platform.cp/tenant: {{ $t.id }}
    spec:
      # ⭐ project 硬编码在 CP 侧（管理员控制），绝不从 tenant 仓库读
      project: {{ $t.project | quote }}

      source:
        repoURL: {{ $t.repoURL | quote }}
        targetRevision: {{ $t.revision | default "main" | quote }}
        path: '{{`{{ .app.path.path }}`}}'
        helm:
          valueFiles:
            - '../../clusters/{{`{{ .cluster.path.basename }}`}}/values.yaml'

      destination:
        server: '{{`{{ .server }}`}}'
        namespace: '{{`{{ .namespace }}`}}'

      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true

      # 删 Application 时保留集群里的资源
      preserveResourcesOnDeletion: true
{{- end }}
```

完整文件：
[`examples/appset-helm/cp-chart/templates/applicationset-cluster-apps.yaml`](./examples/appset-helm/cp-chart/templates/applicationset-cluster-apps.yaml)

### 4.4 参数从哪来（对照表）

| 模板变量 | 来源 | 说明 |
|---|---|---|
| `.app.path.path` | 目录生成器（`apps/*`） | 应用在 tenant 仓库里的路径，如 `apps/nginx` |
| `.app.path.basename` | 目录生成器 | 应用名，如 `nginx` |
| `.cluster.path.basename` | 文件生成器（`clusters/*/cluster.yaml`） | **集群目录名**，如 `dev-01` |
| `.cluster.path.path` | 文件生成器 | 集群目录路径，如 `clusters/dev-01` |
| `.server` | `cluster.yaml` 的顶层字段 | 集群 API Server |
| `.namespace` | `cluster.yaml` 的顶层字段 | 目标命名空间 |
| `.env` / `.gcpProject` … | `cluster.yaml` 的其他顶层字段 | 想带什么带什么 |

**两个容易搞错的点（都已核对上游源码）：**

1. **`pathParamPrefix` 只影响 `.path.*` 系列参数。**
   文件生成器会把 `cluster.yaml` 里的 key **平铺到参数最外层**
   （`maps.Copy(params, objectFound)`），所以是 `.server` 而不是 `.cluster.server`。
2. **两个 Git 生成器做 Matrix 时必须用 `pathParamPrefix` 区分**，
   否则两边的 `.path.*` 会撞车（上游原文：
   *"Using this option is necessary in a Matrix generator where both child
   generators are Git generators (to avoid conflicts when merging the child
   generators' items)."*）。

### 4.4.1 ⚠️ 并列写两个生成器 ≠ 笛卡尔积

**这是最容易写错的地方。** Argo CD 的 controller 是**逐个生成器**跑模板的：

```go
// applicationset/controllers/template/template.go
for _, requestedGenerator := range applicationSetInfo.Spec.Generators {
    t, err := generators.Transform(requestedGenerator, ...)
    for _, p := range t {
        app, err := renderer.RenderTemplateParams(tmplApplication, ..., p, ...)
```

也就是说：

```yaml
  generators:
    - git: {directories: {path: "apps/*"}}           # ← 单独跑一遍模板
    - git: {files: {path: "clusters/*/cluster.yaml"}} # ← 再单独跑一遍模板
```

**不是**「apps × clusters 的笛卡尔积」，而是：

- 第一遍：参数里只有 `.app.*`，模板里的 `.cluster.path.basename` 取不到
  → 开了 `missingkey=error` 就是**整批报错**；
- 第二遍：参数里只有 `.server` / `.cluster.*`，`.app.path.basename` 取不到 → 同样报错。

**要笛卡尔积必须用 `matrix`：**

```yaml
  generators:
    - matrix:
        generators:
          - git: {..., pathParamPrefix: app, directories: {path: "apps/*"}}
          - git: {..., pathParamPrefix: cluster, files: {path: "clusters/*/cluster.yaml"}}
```

matrix 的实现（`applicationset/generators/matrix.go`）就是两层循环 +
参数合并（`mergo.Merge`），所以是真正的 N×M。

> 📌 合并时**第一个子生成器的参数优先**（`mergo.WithOverride` 先合 b 再合 a）。
> 所以别让两个子生成器产出同名字段。

### 4.5 渲染结果长什么样

`helm template platform-cp examples/appset-helm/cp-chart` 的产物（节选）：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tenant-a-cluster-apps
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - matrix:
        generators:
          - git:
              repoURL: "https://github.com/example/tenant-cluster.git"
              revision: "main"
              pathParamPrefix: app
              directories:
                - path: "apps/*"
          - git:
              repoURL: "https://github.com/example/tenant-cluster.git"
              revision: "main"
              pathParamPrefix: cluster
              files:
                - path: "clusters/*/cluster.yaml"
  template:
    metadata:
      name: '{{ .app.path.basename }}-{{ .cluster.path.basename }}'   # ← 还在！等 AppSet controller
    spec:
      project: "tenant-a"
      source:
        repoURL: "https://github.com/example/tenant-cluster.git"
        targetRevision: "main"
        path: '{{ .app.path.path }}'
        helm:
          valueFiles:
            - '../../clusters/{{ .cluster.path.basename }}/values.yaml'
      destination:
        server: '{{ .server }}'
        namespace: '{{ .namespace }}'
```

**注意 `name:` 那行 —— 它必须还是 `{{ ... }}`。**
如果这里已经是 `nginx-dev-01`，说明 Helm 越权渲染了 AppSet 模板
（要么是转义没做，要么是变量名写错被渲染成空）。

### 4.6 生成出来的 Application

AppSet controller 处理后（`apps/nginx` × `dev-01`/`prod-01`）：

| Application | source.path | valueFiles | destination |
|---|---|---|---|
| `nginx-dev-01` | `apps/nginx` | `../../clusters/dev-01/values.yaml` | `https://example-dev-01.k8s.example.internal` / `platform` |
| `nginx-prod-01` | `apps/nginx` | `../../clusters/prod-01/values.yaml` | `https://example-prod-01.k8s.example.internal` / `platform` |

### 4.7 第三层：Application 的 Helm 渲染

到这里才是 **H2**（目标应用自己的 Helm 渲染）：

```bash
# 等价于 Argo CD 在 repo-server 里做的事
helm template nginx tenant-repo/apps/nginx \
  -f tenant-repo/clusters/dev-01/values.yaml
```

**值的优先级**（上游 `docs/user-guide/helm.md`）：

```
parameters  >  values  >  valueFiles  >  chart 自带的 values.yaml
```

多个 `valueFiles` 之间：**列表里越靠后优先级越高**。

所以这套结构的值来源是：

```
chart 默认值（apps/nginx/values.yaml）
   ↑ 被覆盖
集群覆盖值（clusters/<cluster>/values.yaml）   ← valueFiles
   ↑ 被覆盖
（可选）Application spec.source.helm.parameters / values
```

### 4.8 值文件路径跨目录跨仓库

**规则（上游 + 源码核对）：**

- `valueFiles` 的路径**相对于 `source.path`**（即应用 chart 所在目录）；
- 解析后必须落在**同一个仓库根内** —— 仓库根是安全边界。
  源码：`util/io/path/resolved.go` → `"file '%s' resolved to outside repository root"`；
- 因此 `../../clusters/dev-01/values.yaml` **合法**
  （`source.path = apps/nginx` → 回到仓库根 → 进 `clusters/`）。

**跨仓库取 values**（chart 在仓库 A、values 在仓库 B）要用多源：

```yaml
  sources:
    - repoURL: https://github.com/example/app-repo.git
      path: apps/nginx
      targetRevision: main
    - repoURL: https://github.com/example/tenant-cluster.git
      targetRevision: main
      ref: values          # ← 定义 $values 前缀
  # valueFiles 里用 $values/... 引用第二个源
```

详见上游
[`docs/user-guide/multiple_sources.md`](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)。

---

## 5. 模式 B：CP chart 直接渲染 Cluster Application（不生成器）

**什么时候选它**：集群数量少且基本不变，想在 CP 仓库里**一眼看到**
「一集群一个 Application」，不需要 Git 驱动的自动发现。

```yaml
# examples/appset-helm/cp-chart/templates/application-cluster-bootstrap.yaml
{{- range $c := .Values.clusters }}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-{{ $c.name }}
  namespace: argocd
spec:
  project: platform-cp
  source:
    repoURL: https://github.com/example/tenant-cluster.git
    targetRevision: main
    path: "clusters/{{ $c.name }}/bootstrap"
    helm:
      valueFiles:
        - "values.yaml"
  destination:
    server: https://kubernetes.default.svc
    namespace: cluster-bootstrap
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
  preserveResourcesOnDeletion: true
{{- end }}
```

**这个 Application 是「集群引导程序」**：负责建集群 + 把集群注册进 Argo CD。

> ⚠️ **顺序要求**：集群引导 Application 成功（集群 secret 已存在）之后，
> AppSet 生成的、指向该集群的 Application 才能 sync。
> 否则报 `error getting cluster by server "..."`（源码：
> `util/argo/argo.go` → `GetDestinationCluster`）。

**代价**：集群清单在 CP 仓库和 tenant 仓库各写一份 → 两处维护。

---

## 6. 模式 C：让 AppSet 自己去 tenant 仓库发现集群

模式 A 的生成器已经指向 tenant 仓库了；如果**连 CP chart 都不想要**
（集群清单完全由 tenant 仓库决定），可以把 ApplicationSet 直接写成普通 YAML
放在 CP 仓库里（不是 chart 模板），生成器仍然读 tenant 仓库。

好处：**没有双模板问题**（ApplicationSet 不经过 Helm）。
坏处：租户清单和租户仓库地址写死在 CP 仓库的普通 YAML 里，改租户要改 CP 仓库。

```yaml
# 直接放在 CP 仓库里（不走 Helm）
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tenant-a-cluster-apps
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - git:
        repoURL: https://github.com/example/tenant-cluster.git
        revision: main
        files:
          - path: "clusters/*/cluster.yaml"
  template:
    metadata:
      name: '{{.path.basename}}'
    spec:
      project: tenant-a            # ⭐ 仍然硬编码
      source:
        repoURL: https://github.com/example/tenant-cluster.git
        targetRevision: main
        path: "apps/{{.path.basename}}"     # apps/dev-01/ ...
        helm:
          valueFiles:
            - "values.yaml"                  # apps/dev-01/values.yaml
      destination:
        server: '{{.server}}'
        namespace: '{{.namespace}}'
```

> 📌 模式 C 的 tenant 仓库布局是「**每集群一份应用**」（`apps/dev-01/`），
> 和模式 A 的「**应用共享 + values 按集群分**」（`apps/nginx/` + `clusters/dev-01/values.yaml`）不同。
> 两种布局都能work，选哪种取决于你想不想让所有集群跑同一个 chart。

### 6.1 三种模式怎么选

| | A：chart → AppSet | B：chart → Application | C：AppSet（不经 chart） |
|---|---|---|---|
| 租户清单在哪 | CP chart 的 values | CP chart 的 values | tenant 仓库 |
| 双模板问题 | ⚠️ 有（要转义） | 无（不写 AppSet 模板） | 无 |
| 新增集群要改哪 | CP chart values + tenant 仓库 | CP chart values（+ tenant 仓库） | 只改 tenant 仓库 |
| 新增应用要改哪 | 只改 tenant 仓库 | 只改 tenant 仓库 | 只改 tenant 仓库 |
| 适合 | 租户多、要批量生成 | 集群少且固定 | 只要 AppSet 语义，不要 Helm |

**默认选 A**（用户问的就是这个），并且：

- 集群清单**只写在 tenant 仓库**（别在 CP values 里再抄一遍）；
- CP chart 的 values 只放「**租户级**」配置（仓库地址、project 名）。

---

## 7. templatePatch：连 boolean 也能模板化

[`05-appset.md`](./05-appset.md) §3.2 说过：
`syncPolicy.automated.prune` / `selfHeal` 在 CRD 里是 `boolean`，
**不能**写成 `'{{.prune}}'`（会被 API server 以 "must be of type boolean" 拒绝）。

**`templatePatch` 可以绕过这个限制** —— 因为它渲染的是 YAML 文本片段，
不是 CRD 的强类型字段。上游例子：

```yaml
spec:
  goTemplate: true
  generators:
    - list:
        elements:
          - cluster: engineering-dev
            autoSync: true
            prune: true
  template:
    metadata:
      name: '{{ .nameNormalized }}-deployment'
    spec:
      project: "default"
      ...
  templatePatch: |
    spec:
      source:
        helm:
          valueFiles:
          {{- range $valueFile := .valueFiles }}
            - {{ $valueFile }}
          {{- end }}
      {{- if .autoSync }}
        syncPolicy:
          automated:
            prune: {{ .prune }}
      {{- end }}
```

⚠️ 上游三条 IMPORTANT：

1. `templatePatch` **只在 `goTemplate: true` 时可用**；
2. **`spec.project` 不支持在 `templatePatch` 里改**
   （project 只能在 `spec.template.spec.project` 里定 → 更加说明 project 要硬编码）；
3. `templatePatch` 能注入任意内容 → **参数来源必须可信**
   （上游建议用 `toJson` 转义后再拼）。

> 📌 **在 CP chart 里写 `templatePatch` 要格外小心**：
> `templatePatch` 的内容本身是 Helm 模板的一部分，
> 里面的 `{{- if .autoSync }}` 等表达式是**给 ApplicationSet controller** 的，
> 所以在 chart 里必须转义成 `` {{`{{- if .autoSync }}`}} ``，
> 而 `{{- range ... }}` 这类**Helm 自己要用的**控制流不能转义。
> 两者混在一个文件里很容易写错 —— 建议 `templatePatch` 单独放一个模板文件。

---

## 8. 安全

### 8.1 CP 仓库 = 策略执行面

Helm chart 的 `templates/` 是**任意模板逻辑**（能算、能循环、能拼字符串）。
能 push CP 仓库的人，可以：

- 渲染出指向**任意仓库**的 Application（→ 从 Argo CD 里偷 Secret 再外发）；
- 渲染出落到 `default` 项目的 Application（→ 改 `argocd-rbac-cm` → 接管 Argo CD）；
- 渲染出指向任意集群的 Application（→ 在生产集群里创建任意资源）。

**对策：**

| 措施 | 做法 |
|---|---|
| 仓库写权限 | CP 仓库只给平台管理员；tenant 仓库给租户 |
| 仓库凭据 | 用 GitHub App / 按仓库最小权限，不用共享 PAT；见 [`07-repository-githubapp.md`](./07-repository-githubapp.md) |
| 变更审计 | CP 仓库的 PR 必须走 CR（变更单）流程，见 [`git-apps/14-rulesets-and-gitapp-gate.md`](./git-apps/14-rulesets-and-gitapp-gate.md) |
| 渲染结果审计 | `helm template` 结果可以在 CI 里 diff，防止"偷偷多渲染一个 App" |

### 8.2 project 必须硬编码在 CP 侧

见 [`05-appset.md`](./05-appset.md) §4：模板化 `project` 时，
**所有生成器数据源都必须由管理员控制**。
本方案里 `project` 来自 CP chart 的 values（管理员控制），
tenant 仓库改不动 —— 这就是安全边界。

### 8.3 集群必须先注册

`destination.server` 必须在 Argo CD 里能找到对应的 cluster secret，
否则 sync 直接失败（`error getting cluster by server`）。
tenant 仓库里的 `cluster.yaml` 写的是「期望的地址」，
**注册动作**（创建 cluster secret）由集群引导流程负责。

### 8.4 凭据不要进 values

`values.yaml` 在 Git 里 = 明文。
Secret 用 Secret Manager + External Secrets / CSI，
或至少 SOPS 加密；见 [`06-opa-gatekeeper-impact.md`](./06-opa-gatekeeper-impact.md) 里的 Secrets 管理部分。

### 8.5 删除时的破坏性

`preserveResourcesOnDeletion: true` **要加在生成的 Application 上**
（也就是写进 ApplicationSet 的 `spec.template.spec`）。
否则删掉 AppSet → 生成的 Application 被删 → **集群里的资源被级联删除**。

---

## 9. 验证

```bash
# ① CP chart 渲染出来的 ApplicationSet 是否还保留着 AppSet 模板
helm template platform-cp examples/appset-helm/cp-chart | \
  grep -n "name: '{{"          # 应该还能看到 {{ ... }}

# ② 一次跑完所有转义检查
./examples/appset-helm/render-check.sh

# ③ AppSet 是否健康、有没有生成 Application
kubectl -n argocd get applicationset
kubectl -n argocd get applications -l argocd.argoproj.io/application-set-name=tenant-a-cluster-apps

# ④ 每个 Application 落在哪个 project（重点：有没有落到 default！）
kubectl -n argocd get applications -o custom-columns='NAME:.metadata.name,PROJECT:.spec.project'

# ⑤ 生成的 Application 的 source / destination 是否被正确渲染
kubectl -n argocd get application nginx-dev-01 -o jsonpath='{.spec.source.path}{"\n"}'
kubectl -n argocd get application nginx-dev-01 -o jsonpath='{.spec.destination.server}{"\n"}'
kubectl -n argocd get application nginx-dev-01 -o jsonpath='{.spec.source.helm.valueFiles}{"\n"}'

# ⑥ 目标集群能不能解析（注册了没）
kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster

# ⑦ AppSet controller 的报错
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-applicationset-controller --tail=100
```

---

## 10. 排障

| 现象 | 根因 | 处理 |
|---|---|---|
| `helm template` 报 `nil pointer evaluating interface {}.app` | chart 里没转义 AppSet 模板 | 用 `{{`{{ .x }}`}}` 包起来 |
| `helm template` 报 `unexpected <.> in operand` | YAML 注释里出现了裸 `{{ }}`；或反引号多套一层 | 注释改用 `{{/* */}}`；核对转义层数 |
| 渲染出来的 ApplicationSet 里 `name: '--'` | Helm 静默把变量渲染成空串 | 同第一行；渲染结果必须肉眼确认 |
| Application 名字变成 `--` / `path` 为空 | AppSet 侧变量名写错 + 没开 `missingkey=error` | `goTemplate: true` + `goTemplateOptions: ["missingkey=error"]` |
| 变量取不到（`.cluster.server` 空） | file generator 的字段是**平铺**的，不是嵌套 | 用 `.server`，不是 `.cluster.server`；`pathParamPrefix` 只管 `.path.*` |
| Matrix 里两个 Git 生成器参数冲突 | 两边都产出 `.path.*` | 给每个子生成器加 `pathParamPrefix` |
| 只生成了一部分 Application / 报 `map has no entry for key` | 并列写了两个生成器（不是笛卡尔积），模板里的另一半变量取不到 | 用 `matrix` 包裹；见 §4.4.1 |
| `values file not found` | 路径相对 `source.path` 算错了 | 路径相对 `source.path`；`../../` 可以，别出仓库根 |
| 值文件路径变成 `$clusters/...` | 用了 `${{ }}` 写法（**不是**转义约定） | 改成 `{{ }}`；见 §1.1 |
| AppSet 状态正常但没有 Application | Argo CD 没有 tenant 仓库的凭据 | 配 Repository Secret / GitHub App |
| Application 报 `error getting cluster by server` | 目标集群没在 Argo CD 注册 | 先跑集群引导（mode B），或手工 `argocd cluster add` |
| Application 报 `ComparisonError` | 第三层 Helm 渲染失败（values 缺 key 等） | `helm template` 本地复现；检查 values 覆盖顺序 |
| 改了 chart 但 AppSet 没变 | Argo CD 缓存 / chart 没被重新渲染 | `argocd app get <cp-app> --refresh`；确认 CP Application 的 `source.helm.valueFiles` 指向了新 values |
| 生成的 Application 全落在 `default` 项目 | `template.spec.project` 没写或渲染空了 | `project` 必须在 CP 侧硬编码；用 §9 ④ 检查 |

---

## 11. 落地清单

- [ ] CP chart 里凡是给 ApplicationSet 用的 `{{ }}`，都用 `` {{`...`}}` `` 转义
- [ ] YAML 注释里没有裸 `{{ }}`
- [ ] `project` 在 CP 侧硬编码（不在 tenant 仓库里）
- [ ] AppSet 开了 `goTemplate: true` + `missingkey=error`
- [ ] Matrix 里多个 Git 生成器各带 `pathParamPrefix`
- [ ] `valueFiles` 路径相对 `source.path`，且在仓库根内
- [ ] `preserveResourcesOnDeletion: true` 写进了 `spec.template.spec`
- [ ] CP 仓库的写权限只给管理员；tenant 仓库给租户
- [ ] CP 仓库配了 GitHub App / 最小权限凭据；tenant 仓库同理
- [ ] 集群引导流程先跑，注册好 cluster secret
- [ ] `helm template` 进了 CI（diff 评审渲染结果）
- [ ] 生成的 Application 数量有监控（异常增长 = 有人在批量投递）

---

## 12. 关联文档

| 主题 | 文档 |
|---|---|
| ApplicationSet 生成器 / 模板语法全表 | [`05-appset.md`](./05-appset.md) |
| AppProject / RBAC 边界 | [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| Repository 凭据（GitHub App） | [`07-repository-githubapp.md`](./07-repository-githubapp.md) |
| 排障总表 | [`09-troubleshooting.md`](./09-troubleshooting.md) |
| 本文的可运行示例 | [`examples/appset-helm/`](./examples/appset-helm/) |
| **跨仓库渲染的原理（Helm vs Argo CD）** | [`helm-cross-repository.md`](./helm-cross-repository.md) |
| CP 仓库的仓库骨架（bootstrap / clusters 清单） | [`examples/gitops-layout/`](./examples/gitops-layout/) |
| 上游 ApplicationSet 模板文档（含 Helm 转义） | [Argo CD 官方文档](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Template/) |
| 上游 Helm 参数化与多源 | [Argo CD 官方文档](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/) |
