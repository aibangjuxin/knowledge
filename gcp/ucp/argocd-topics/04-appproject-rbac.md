# 04 · AppProject 与权限模型

> 核心问题：**`AppProject` 是不是 Kubernetes 权限边界？什么时候需要多个 `AppProject`？**
> 答案：**不是**。它是"资源约束边界"。权限由三层共同构成，缺一不可。

---

## 1. 三层权限边界

```
┌─────────────────────────────────────────────────────────────┐
│ 第 1 层：Argo CD RBAC（Casbin，`argocd-rbac-cm`）            │
│ 管：谁（用户/组）能对哪个 Application / Project 做哪个动作      │
│ 不管：集群里实际资源长什么样                                  │
├─────────────────────────────────────────────────────────────┤
│ 第 2 层：AppProject（`spec.sourceRepos` / `destinations` /   │
│         `clusterResourceWhitelist` / `namespaceResource*List`）│
│ 管：这个项目里的 Application 允许从哪同步到哪、能创建什么资源     │
│ 不管：谁能操作这个项目里的 Application ← 这是第 1 层的职责     │
├─────────────────────────────────────────────────────────────┤
│ 第 3 层：Kubernetes RBAC（Argo CD 使用的 ServiceAccount）     │
│ 管：Argo CD 实际调用 K8s API 时能创建/修改/删除什么            │
│ 不管：Git 里写的是什么、AppProject 允许什么                    │
└─────────────────────────────────────────────────────────────┘
```

**三者互不替代。** 典型错误：

| 错误做法 | 为什么错 |
|---|---|
| "我建了 AppProject 限定了 namespace，所以只有这个项目能部署到那里" | ❌ 谁都能创建指向该 namespace 的 Application（只要第 1 层允许） |
| "我在 Argo CD 里禁用了 admin，所以安全了" | ❌ Argo CD 用的 SA 可能权限过大，能操作所有 namespace |
| "AppProject 里 sourceRepos 限定了仓库，所以安全了" | ❌ 仓库白名单不限制**用户**能不能提交对该仓库的变更 |

---

## 2. 第 1 层：Argo CD RBAC 详解

### 2.1 配置文件位置

**`argocd-rbac-cm`**（不是 `argocd-cm`）：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    ...
  policy.default: role:authenticated
  scopes: '[groups, email]'
  policy.matchMode: 'glob'
```

### 2.2 内置角色

| 角色 | 权限 |
|---|---|
| `role:readonly` | 对所有资源只读 |
| `role:admin` | 对所有资源无限制 |

**没有内置的"最小权限"角色**——`policy.default` 用 `role:readonly` 会让所有已认证用户
读到全部 Application。需要自己定义（见 §2.6）。

### 2.3 策略语法

```
p, subject, resource, action, object, effect
g, subject, inherited-subject
```

| 字段 | 取值 | 说明 |
|---|---|---|
| `resource` | `applications`、`applicationsets`、`projects`、`repositories`、`clusters`、`logs`、`exec` | 可操作的对象类型 |
| `action` | `get`、`create`、`update`、`delete`、`sync`、`override`、`*` | 动作 |
| `object` | `*` / `<project>/*` / `<project>/<app>` / `<app>` | 作用范围 |
| `effect` | `allow` / `deny` | |

上游 RBAC 文档给出的示例：

```text
p, my-org:team-alpha, applications, sync, my-project/*, allow
g, my-org:team-beta, role:admin
```

### 2.4 项目级权限的两种写法

**写法 A（全局策略里直接写项目范围）：**

```text
p, my-org:team-alpha, applications, sync, my-project/*, allow
```

**写法 B（在 AppProject 的 `roles` 里定义，项目角色名固定为 `proj:<项目名>:<角色名>`）：**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-beta-project
spec:
  roles:
  - name: admin
    description: Admin privileges to team-beta project
    policies:
    - p, proj:team-beta-project:admin, applications, *, team-beta-project/*, allow
    groups:
    - my-org:team-beta
```

Argo CD 会在运行时动态生成下面两条 Casbin 规则：

```text
p, proj:team-beta-project:admin, applications, *, team-beta-project/*, allow
g, my-org:team-beta, proj:team-beta-project:admin
```

> ⚠️ **上游明确警告**：policy 里的角色名**必须**符合 `proj:<project-name>:<role-name>`
> 格式，否则在 Argo CD 授权过程中**不生效**。
> 上游文档原话：*"It is very important that policy roles follow the pattern
> `proj:<project-name>:<role-name>` or they won't be effective."*

**写法 B 的优势**：权限跟着 AppProject 走。AppProject 被删除，权限自动消失，
不需要额外清理 RBAC 规则。

### 2.5 `g` 的匹配语义（易踩坑）

上游 RBAC 文档指出 Casbin 的 `g` 匹配是**双向穿透**的：

```text
g, my-local-user, role:admin
```

如果某个 SSO 用户的 scope 里恰好有个值叫 `my-local-user`，
**这个 SSO 用户也会获得 `role:admin`**。

上游建议：**不要**用可能与 SSO claim 冲突的名字（如用户名、邮箱）作为 `g` 的 subject。
用带命名空间的组名（如 `my-org:team-beta`）。

### 2.6 `policy.default` 的正确用法

上游明确：

> When a user is authenticated in Argo CD, it will be granted the role specified
> in `policy.default`.

**并且默认权限无法被 `deny` 规则阻止。** 这是 `policy.default` 最反直觉的地方——
你不能用 `deny` 去收回它已经给出的权限。

**推荐：自建最小权限默认角色**

```yaml
data:
  policy.csv: |
    # 最小权限：只允许读
    p, role:authenticated, applications, get, *, allow
    p, role:authenticated, projects, get, *, allow
    p, role:authenticated, repositories, get, *, allow
    p, role:authenticated, clusters, get, *, allow

    # 团队授权
    g, devops-admin, role:admin
    g, devops-dev, role:authenticated

    # 项目级
    p, devops-dev, applications, sync, dev/*, allow

  policy.default: role:authenticated
```

### 2.7 `policy.matchMode`

```yaml
  policy.matchMode: 'glob'   # 默认 glob，也可 'regex'
```

`glob` 支持 `*` 通配。`regex` 用于复杂匹配。**改这个会改变所有已有策略的解释方式**，
切换前务必用 `argocd rbac list` 对比。

---

## 3. 第 2 层：AppProject 详解

### 3.1 完整字段

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-alpha
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io    # 可选：删除时级联删除资源
spec:
  # ① 允许的源仓库（支持 glob 和 ! 取反）
  sourceRepos:
  - 'https://github.com/example/team-alpha-*'
  - '!https://github.com/example/team-alpha-legacy'

  # ② 允许的源 namespace（Argo CD 仓库内的目录作为 source）
  sourceNamespaces:
  - 'apps/team-alpha'

  # ③ 允许的目标（server + namespace）
  destinations:
  - server: 'https://kubernetes.default.svc'
    namespace: team-alpha-dev
  - server: 'https://kubernetes.default.svc'
    namespace: team-alpha-prod
  - server: '*'
    namespace: team-alpha-sandbox

  # ④ 集群级资源白名单（group + kind + name）
  clusterResourceWhitelist:
  - group: 'cert-manager.io'
    kind: Certificate
  - group: ''
    kind: Namespace
    name: 'team-alpha-*'

  # ⑤ 集群级资源黑名单
  clusterResourceBlacklist:
  - group: ''
    kind: Namespace
    name: 'kube-*'
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRoleBinding

  # ⑥ 命名空间级资源白名单
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'

  # ⑦ 命名空间级资源黑名单
  namespaceResourceBlacklist:
  - group: 'rbac.authorization.k8s.io'
    kind: Role
  - group: 'rbac.authorization.k8s.io'
    kind: RoleBinding

  # ⑧ 项目角色（见 §2.4 写法 B）
  roles:
  - name: admin
    policies:
    - p, proj:team-alpha:admin, applications, *, team-alpha/*, allow
    groups:
    - devops-team-alpha
```

### 3.2 白名单/黑名单的匹配语义（重要）

**Argo CD 的逻辑是"默认允许，黑名单拒绝"**，不是"默认拒绝，白名单允许"。

具体来说（据上游 projects 文档）：
- `clusterResourceWhitelist` / `namespaceResourceWhitelist`
  列出的是**明确允许**的资源类型；**不在白名单里的资源默认被拒绝**
- `clusterResourceBlacklist` / `namespaceResourceBlacklist`
  列出的是**明确拒绝**的；黑名单优先于白名单

**必须成对配置**。典型安全配置：

```yaml
spec:
  # 集群级资源：只允许少量特定类型
  clusterResourceWhitelist:
  - group: 'cert-manager.io'
    kind: Certificate
  - group: 'cert-manager.io'
    kind: Issuer
  - group: 'apiextensions.k8s.io'
    kind: CustomResourceDefinition

  # 命名空间级资源：全允许
  namespaceResourceWhitelist:
  - group: '*'
    kind: '*'

  # 但禁止在命名空间内创建 RBAC（提权路径）
  namespaceResourceBlacklist:
  - group: 'rbac.authorization.k8s.io'
    kind: Role
  - group: 'rbac.authorization.k8s.io'
    kind: RoleBinding
```

> ⚠️ **禁止 `Role` / `RoleBinding` / `ClusterRoleBinding` 是关键**。
> 否则用户可以在自己的 namespace 里创建绑定到高权限 ServiceAccount 的
> RoleBinding —— 这是 Kubernetes 环境下最常见的**横向/纵向提权路径**。
> 这是 `AppProject` 真正发挥安全价值的地方。

### 3.3 `default` 项目必须收紧

上游文档说明：`default` 项目自动创建，且**默认是最宽松的**：

```yaml
spec:
  sourceRepos:
  - '*'
  destinations:
  - namespace: '*'
    server: '*'
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
```

**收紧它**（上游给出的官方做法）：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
spec:
  sourceRepos: []
  sourceNamespaces: []
  destinations: []
  namespaceResourceBlacklist:
  - group: '*'
    kind: '*'
```

> 上游明确提示：改完之后，**任何使用 `default` 项目的 Application 都会被拒绝**，
> 直到你显式把它移到更宽松的项目。
> **所以这是有破坏性的操作**——必须先把所有 Application 迁走。

### 3.4 `finalizers` 的副作用

```yaml
  finalizers:
  - resources-finalizer.argocd.argoproj.io
```

加上这个 finalizer 后，**删除 AppProject 会级联删除该项目的所有资源**。
误删项目 = 删业务。**生产环境慎用**，或至少在加之前确认 GitOps 能恢复。

---

## 4. 第 3 层：Kubernetes RBAC

Argo CD 操作目标集群时用的是**注册集群时指定的 ServiceAccount**。

### 4.1 最小权限示例

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-deployer-team-alpha
  namespace: argocd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argocd-deployer-team-alpha
  namespace: team-alpha
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets", "services", "serviceaccounts", "persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
# 明确禁止提权
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings"]
  verbs: []
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argocd-deployer-team-alpha
  namespace: team-alpha
subjects:
- kind: ServiceAccount
  name: argocd-deployer-team-alpha
  namespace: argocd
roleRef:
  kind: Role
  name: argocd-deployer-team-alpha
  apiGroup: rbac.authorization.k8s.io
```

### 4.2 注册集群时指定 SA

```bash
argocd cluster add gke-dev \
  --service-account-issuer=https://container.googleapis.com/v1 \
  --service-account-key-file=./gke-dev.key
```

或用 Secret 声明式管理（推荐，见 [`07-repository-githubapp.md`](./07-repository-githubapp.md) §4）：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gke-dev-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
stringData:
  name: gke-dev
  server: https://<ENDPOINT>   # GKE 集群 API endpoint
  config: |
    {
      "bearerToken": "<GKE_ACCESS_TOKEN>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<BASE64_CA_CERT>"
      }
    }
```

> GKE 上推荐的鉴权方式是 **Workload Identity**（用 GKE 的 metadata server
> 取短期 token，无需长期 ServiceAccount JSON key）。此处保留 Bearer Token 形式
> 只是为了说明 Secret 结构，实际部署请用 Workload Identity。

---

## 5. 什么时候需要多个 AppProject

### 5.1 判断标准

**需要拆分的信号（满足任一即拆）：**

| # | 信号 | 例子 |
|---|---|---|
| 1 | 目标 namespace 不同 | dev / prod 分开 |
| 2 | 源仓库集合不同 | team-a 用 `repo-a/*`，team-b 用 `repo-b/*` |
| 3 | 资源白名单/黑名单不同 | team-a 要 CRD，team-b 不许 |
| 4 | 权限集合不同 | 需要不同的项目角色成员 |
| 5 | 集群不同 | 不同 GKE 集群 |
| 6 | 生命周期/审批流程不同 | prod 需要额外审批（用 sync window / 多签） |

**不该拆分的信号：**

| 场景 | 正确做法 |
|---|---|
| 只是"每个应用一个项目" | ❌ 不要。Application 本身有 `spec.project`，但项目是**边界**，不是**标签** |
| 环境不同但权限相同 | 一个项目 + 不同 namespace 即可 |
| 只是想分组显示 | 用 `AppProject` 的 label / annotation，或用 ApplicationSet 的 `metadata.labels` |
| 团队不同但边界相同 | 不同的 `roles.groups` 就够，不必拆项目 |

### 5.2 常见拆分粒度

| 粒度 | 数量 | 适用 |
|---|---|---|
| **按团队** | 每个团队 1 个 | 最常见，边界清晰，权限差异明显 |
| **按团队 × 环境** | 团队数 × 环境数 | dev/prod 权限或资源限制不同时 |
| **按团队 × 环境 × 集群** | 更多 | 多集群且边界严格隔离时 |
| **一个都不拆**（只有 default） | 1 | ❌ 不推荐，default 太宽松 |

**推荐起点**：**按团队拆**，每个团队一个项目；等 prod 权限需要单独收紧时，
再把 prod 拆出来。**不要一上来就按环境 × 集群矩阵拆**——项目数爆炸后没人能维护。

### 5.3 拆分时的命名约定

```
<team>-<env>              例：platform-dev, platform-prod
```

**Argo CD 有隐式约定**：`AppProject` 名字里的 `-` 会被解析。
具体规则：项目名 `foo-bar` 会自动生成 `foo-bar` 和 `foo` 两个项目
（子项目继承父项目的 destination / sourceRepos 等限制），
这叫 **project inheritance**。

> ⚠️ **实践建议**：用 `-` 分隔时要清楚这个继承行为。
> 上游 `docs/user-guide/projects.md` 有 "Project Inheritance" 章节说明。
> 如果不想要继承行为，用 `platform_dev`（下划线）而不是 `platform-dev`。
> **这是容易踩的坑**——命名之前先确认你们的约定。

---

## 6. 完整落地示例

见 [`examples/appproject-multi-env.yaml`](./examples/appproject-multi-env.yaml)。

---

## 7. 验证

```bash
# ① 看项目列表和各自的 destination
argocd proj list
argocd proj get platform-dev

# ② 看项目角色
argocd proj role list platform-dev
argocd proj role get platform-dev admin

# ③ 看全局 RBAC 规则
argocd rbac list

# ④ 验证某个 Application 落到了哪个项目
argocd app get <app-name> | grep -i project

# ⑤ 验证权限边界：用一个受限账号尝试越权
argocd app sync <other-team-app>   # 应该被拒

# ⑥ 验证 AppProject 约束：destinations 之外的 namespace 应该被拒
#    在 Application 里指定一个未授权的 destination.namespace，同步时应报错

# ⑦ 验证 K8s RBAC：检查 Argo CD 用的 SA 实际权限
kubectl auth can-i --as=system:serviceaccount:argocd:argocd-deployer-team-alpha \
  create rolebindings -n team-alpha      # 应该返回 no
kubectl auth can-i --as=system:serviceaccount:argocd:argocd-deployer-team-alpha \
  create deployments -n team-alpha        # 应该返回 yes
```

---

## 8. 排障

| 现象 | 根因 | 处理 |
|---|---|---|
| 用户看不到某个 Application | 第 1 层没给权限 | 查 `argocd-rbac-cm` 的 `policy.csv` + `scopes` |
| 用户看到 Application 但不能同步 | action 不含 `sync` | 补 `p, <group>, applications, sync, <project>/*, allow` |
| 项目角色不生效 | 角色名不符合 `proj:<proj>:<role>` 格式 | 严格按格式改 |
| 用户意外拥有 `role:admin` | `g` 的 subject 撞上了 SSO claim | 换用带命名空间的组名 |
| `policy.default` 的权限收不回来 | 默认权限不能被 `deny` 阻止 | 改 `policy.default` 指向自建最小角色 |
| 同步时报 "not permitted" | 第 3 层 K8s RBAC 不足 | 补 ServiceAccount 权限 |
| Application 报 "destination not allowed" | 第 2 层 `destinations` 不含目标 | 补 AppProject 的 destinations |
| Application 报 "resource not permitted" | 不在白名单 / 命中黑名单 | 调 `clusterResourceWhitelist` / `namespaceResource*List` |
| 删了项目资源全没了 | AppProject 有 `finalizers` | 从 AppProject 里去掉 `resources-finalizer.argocd.argoproj.io` |
| 改名后项目行为诡异 | `-` 触发了 project inheritance | 确认是否需要继承；用 `_` 或明确配置 |

---

## 9. 关联文档

| 主题 | 文档 |
|---|---|
| 组映射与 `scopes` | [`03-dex-ldap-sso.md`](./03-dex-ldap-sso.md) |
| ApplicationSet 如何选项目 | [`05-appset.md`](./05-appset.md) |
| 集群凭据与 ServiceAccount | [`07-repository-githubapp.md`](./07-repository-githubapp.md) |
| Gatekeeper 补第 2 层的漏洞 | [`06-opa-gatekeeper-impact.md`](./06-opa-gatekeeper-impact.md) |
