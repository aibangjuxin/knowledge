# Argo CD 进阶用法与管理员手册

> 配套文档：`poc-argocd-integration.md`（Argo CD × Crossplane 集成链路）、`poc-argocd-git-to-apply-trigger.md`（Git 变更 → Argo CD → apply 的逐阶段触发链路）、`argocd-api.md`（Argo CD v3.5.6 API 参考）。
> 本文回答一个问题：**我已经跑通了"改 Git → 自动部署"，接下来往哪走，以及作为一个 Argo CD 管理员我需要掌握什么。**
>
> 版本基准：Argo CD **v3.5.6**（与同目录 `install.yaml` 及兄弟文档一致）。标注 `【待核实】` 的是与你当前环境强相关、需要你自己确认的项。

---

## 0. 先回答你的问题

**你现在做的是 Argo CD 的"第 1 步"，不是入门，而是生产化的起点。**

你当前的状态对照一下：

| 你已经做到的 | 你还没碰的（也就是"高级用法"的真正内容） |
|---|---|
| 装好 Argo CD（`argocd` namespace） | RBAC 分组（`role:admin` / `role:readonly` / 自定义角色 / SSO group 映射） |
| Argo CD 可访问（UI / API） | AppProject（团队边界、集群/命名空间白名单、项目级角色） |
| GitHub 仓库打通，凭证已配 | ApplicationSet（1 → N 个应用、批量生成、多环境） |
| 手工创建 1 个 `Application`，部署到业务 namespace | 同步策略进阶（`automated` / `selfHeal` / `prune` / `syncOptions` / waves / hooks） |
| 改 Git YAML 能自动部署 | 通知（Webhook / 审批 / 订阅）、可观测性（Metrics / Events / Grafana） |
| 只部署到 Argo CD 所在的同一个集群 | 跨集群（cluster secret）、多环境（参数化 destination）、环境晋级 |
| — | 安全基线、最小权限、凭据轮换、审计、灾备、升级 |

**核心结论（先记住这三条，其余都是细节）：**

1. **Argo CD 的"高级"不在于单个 Application 的字段，而在于三类对象的组合**：
   `ApplicationSet`（生成） → `AppProject`（约束） → `Application`（部署）。
   你现在只有第三类。
2. **权限模型是两层**：`argocd-rbac-cm` 的全局 Casbin 策略（用户在 Argo CD 里能做什么）
   × `AppProject` 的项目边界（应用能部署到哪里、哪些资源能动）。
   团队化管控的核心就是把这两层拆开：**平台团队管第一层，业务团队管第二层**。
3. **管理员的主要工作量不在部署，而在"控制爆炸半径"**：资源删除（prune）、
   越权（跨集群 / 跨项目）、凭据泄漏、漂移（drift）、以及"谁能点同步"。
   后面所有章节都会围绕这四件事展开。

---

## 1. Argo CD 能力全景地图

### 1.1 CRD：四类对象各管一段

| CRD | 作用 | 你现在用了吗 |
|---|---|---|
| `Application` | 一个 Git 路径 → 一个目标集群/namespace 的部署定义 | ✅ 已用 |
| `ApplicationSet` | 按 generator（git/list/cluster/matrix）批量**生成** `Application` 对象 | ❌ |
| `AppProject` | 项目级边界：允许的源仓库、目标集群、允许操作的资源类型、项目角色 | ❌ |
| `ApplicationTemplate`（在 ApplicationSet 里内联） | 生成的 `Application` 的模板（YAML 片段） | ❌ |
| `Workflow`（Argo Workflows，可选） | CI/审批流，与 Argo CD hook 配合做人工审批门禁 | ❌ |

关键点：**ApplicationSet 只生成 `Application` 对象，不生成业务资源**。
它永远是"元数据层"，真正的部署仍然由 application-controller 完成。
所以 `ApplicationSet` 的价值是"消除重复"，不是"改变部署语义"。

### 1.2 ConfigMap / Secret：控制面配置面

| 名称 | 管什么 | 什么时候动它 |
|---|---|---|
| `argocd-cm` | 全局行为：SSO/DEX 配置、`url`、`resource.customizations`（health/diff lua）、`resource.exclusions` | 接入 SSO、加自定义健康检查时 |
| `argocd-rbac-cm` | **权限**：`policy.default`、`policy.csv`、`scopes` | 一定要动，做用户分组 |
| `argocd-secret` | 本地 admin 初始密码、SSO 密钥、session 密钥 | 首次安装后改密码 |
| `argocd-tls-certs` | TLS 证书（多集群 ca 证书也在各 secret 里） | 接私有 CA 时 |
| `argocd-notifications-cm` | 通知模板、trigger、subscription | 做 Webhook 通知时 |
| `argocd-notifications-secret` | 通知渠道凭据（Slack token、webhook secret） | 同上 |
| repo secret / `repo-creds` | Git 仓库读写凭证 | 私有仓库 |

### 1.3 组件分工（决定了"出问题时找谁"）

| 组件 | 端口 | 职责 | 排查入口 |
|---|---|---|---|
| `argocd-server` | 443 / 8080 / 8083(metrics) | UI、API、CLI、webhook 接收 | `kubectl -n argocd logs deploy/argocd-server` |
| `argocd-application-controller` | 8082(metrics) | diff / apply / prune / 状态回写 | `kubectl -n argocd logs deploy/argocd-application-controller` |
| `argocd-repo-server` | 8081(metrics) | git fetch、模板渲染、缓存 | `kubectl -n argocd logs deploy/argocd-repo-server` |
| `argocd-applicationset-controller` | 7000(metrics) | 跑 generator、生成 `Application` | `kubectl -n argocd logs deploy/argocd-applicationset-controller` |
| `argocd-redis` | 6379 | 缓存 + 集群协调 | Redis 挂 = 全局写操作失败 |
| `argocd-dex` | 5556/5557/5558 | 默认 SSO | 登录异常时 |

> 排查顺序永远是：**Application 对象状态 → application-controller 日志 → repo-server 日志**。
> repo-server 报错基本等于"渲染失败"（YAML 语法、Helm/Kustomize 参数、base path 错）。

---

## 2. RBAC：用户分组与权限模型

这是你问的"用户分组"的正主。Argo CD 的 RBAC 有三个正交的维度：

```
权限 = ① 角色（role:admin / role:readonly / 项目角色 / 自定义 Casbin 角色）
     × ② 对象范围（全局 / 某个 AppProject / 某个 Application）
     × ③ 动作（get / create / sync / override / delete / action/*）
```

### 2.1 内置角色

| 角色 | 能做什么 | 给谁 |
|---|---|---|
| `role:admin` | 全部权限，包括改 RBAC 配置、创建 cluster secret | **平台管理员，1~2 人** |
| `role:readonly` | 只读所有 Application / AppProject | 审计者、业务方默认角色 |

除这两个内置角色外，其他角色都是**自定义 Casbin 角色**，通过 `policy.csv` 定义。

### 2.2 `argocd-rbac-cm` 两种策略格式

Argo CD 同时支持两种格式，**新项目推荐用内置的 `policy.csv`**
（`policy.default` + `policy.csv` 组合），它和 Argo CD RBAC 文档里的对象模型一一对应，
不需要理解 Casbin 底层语法。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  # 没匹配到任何策略的用户，走这里。生产环境不要写 role:admin
  policy.default: role:readonly

  policy.csv: |
    # ---------- 平台组 ----------
    # g, <subject>, <role>  把主体绑定到角色
    g, platform-admins, role:admin
    g, sre-oncall, role:admin

    # ---------- 业务开发者：只管自己项目的应用 ----------
    g, team-a-devs, project-role:team-a:developer

    # ---------- 只读观察者 ----------
    g, auditors, role:readonly

    # ---------- 对象级精细授权（可选，最小权限收口） ----------
    # p, <subject>, <role>, <objectType>, <objectName>, <action>
    # p, team-a-devs, team-a-devs, applications, team-a/*, sync
    # p, team-a-devs, team-a-devs, applications, team-a/*, action/test
```

语法要点（这是最容易踩的地方）：

| 记号 | 含义 |
|---|---|
| `g, <subject>, <role>` | 把 subject（用户 / 组 / ServiceAccount）加入角色 |
| `p, <subject>, <role>, <object>, <objectName>, <action>` | 精确授予某个对象的某个动作 |
| `<object>` | `applications` / `appProjects` / `projects` / `clusters` / `repositories` / `accounts` / `certificates` / `gpgkeys` |
| `<objectName>` | 支持通配：`*`（全部）、`team-a/*`（某 project 下全部） |
| `<action>` | `get` / `create` / `update` / `delete` / `sync` / `override` / `action/test` / `action/run` |

**注意区分两类同名角色：**

- 全局角色：`role:admin`、`role:readonly`（在 `argocd-rbac-cm` 里定义）
- 项目角色：`projects.<projectName>.roles.<roleName>`（在 `AppProject` 里定义，
  权限天然被限制在该 project 内）

### 2.3 接入 SSO 用户分组（你说的"用户分组"的实际落地）

Argo CD 不会自动知道"你公司里有个叫 `team-a-devs` 的组"。需要三步：

**第 1 步：SSO 身份源（IdP）把组信息放进 token claim。**

- 用 Dex：配 `dex.config`（`argocd-cm`），在 connector 里带上组；
- 用 Keycloak / Okta / Azure AD 等：走 `oidc.config` 或 `sso.config`，
  确认 IdP 端给 Argo CD 配的 client 开启了 groups claim。

**第 2 步：让 Argo CD 把 groups claim 读进 token。**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  scopes: |
    - groups
```

**第 3 步：在 `argocd-rbac-cm` 里把组映射到角色。**

```yaml
data:
  policy.csv: |
    g, team-a-devs, project-role:team-a:developer
    g, team-b-devs, project-role:team-b:developer
    g, platform-admins, role:admin
```

这样一来，**你不需要在 Argo CD 里一个一个建用户**：
IdP 里把人加进组 → 权限自动生效；人离职被移出组 → 权限自动回收。
这就是"用户分组"真正想解决的问题。

> 【待核实】你当前若还没接 SSO，用的是本地 `admin` 账号 + `argocd-secret` 里的初始密码。
> 生产环境第一步应该切到 SSO + `policy.default: role:readonly`，
> 否则默认 admin 账号一旦泄漏即等于全平台沦陷。

### 2.4 项目级角色（配合 AppProject 使用）

`AppProject` 里可以直接定义角色，token 由 Argo CD 签发，供 CI 用 API 触发同步：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-a
  namespace: argocd
spec:
  description: 业务 A 团队的应用边界
  sourceRepos:
    - https://github.com/myorg/team-a.git
  destinations:
    - server: https://kubernetes.default.svc
      namespace: team-a-*
  roles:
    - name: developer
      description: 可同步本项目内的应用
      policies:
        - p, proj:team-a:developer, applications, sync, team-a/*, allow
        - p, proj:team-a:developer, applications, action/test, team-a/*, allow
        - p, proj:team-a:developer, applications, get, team-a/*, allow
      jwtTokens:
        - expiration: "24h"
          subject: team-a-ci
```

拿到 token 后，CI 里就能用**只针对该项目**的权限操作，
而不是给 CI 一个全局 admin token。

```bash
# 项目角色 token 的获取与使用
TOKEN=$(curl -s -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" \
  http://argocd.example.com/api/v1/projects/team-a/roles/developer/token | jq -r .token)

argocd app sync team-a-api --grpc-web --server argocd.example.com \
  --header "Authorization: Bearer $TOKEN"
```

### 2.5 API Token：给人用的，不要拿来做 CI

Argo CD v3.x 有三类 token（细节见 `argocd-api.md`）：

| Token | 签发方式 | 用途 |
|---|---|---|
| 会话 token | `POST /api/v1/session`（用户名密码登录） | UI/CLI 会话 |
| 账号 API token | `POST /api/v1/account/{name}/token`，需 `accounts.<name>: apiKey` scope | 自动化、个人 API 访问 |
| 项目角色 token | `POST /api/v1/projects/{project}/roles/{role}/token` | CI 触发同步（**推荐 CI 用这个**） |

---

## 3. AppProject：团队的权限边界

`AppProject` 是 Argo CD 里**唯一能限制"应用能碰哪些集群 / 命名空间 / 资源类型"的原生机制**。
没有它，任何有 `sync` 权限的用户都可以把应用指到任意集群、任意 namespace。

### 3.1 一份可直接用的 AppProject

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-a
  namespace: argocd
spec:
  description: 团队 A：只允许部署到 team-a-* 命名空间，禁止碰集群级资源

  # 允许的源仓库（支持通配）
  sourceRepos:
    - https://github.com/myorg/team-a.git
    - https://github.com/myorg/shared-libs.git

  # 允许的目标（server = 集群 API 地址；in-cluster 场景写 https://kubernetes.default.svc）
  destinations:
    - server: https://kubernetes.default.svc
      namespace: team-a
    - server: https://kubernetes.default.svc
      namespace: team-a-*
    # 生产集群单独列出来，不写通配
    - server: https://prod-cluster.example.com
      namespace: team-a-prod

  # 集群级资源白名单（不放任何东西 = 禁止创建 CRD / Namespace / ClusterRole 等）
  clusterResourceWhitelist: []
  clusterResourceBlacklist:
    - group: "*"
      kind: "*"
    - group: "rbac.authorization.k8s.io"
      kind: ClusterRole
    - group: "rbac.authorization.k8s.io"
      kind: ClusterRoleBinding

  # 命名空间级资源黑名单
  namespaceResourceWhitelist: []
  namespaceResourceBlacklist:
    - group: "*"
      kind: Secret
    - group: "networking.k8s.io"
      kind: Ingress
    - group: "policy"
      kind: PodDisruptionBudget

  # 自动给部署的 namespace 打标签（配合 quota / cost 归集）
  namespaceMetadata:
    - name: team
      value: team-a
    - name: managed-by
      value: argocd

  # 孤儿资源巡检
  orphanedResources:
    monitor:
      enabled: true
    ignore:
      - kind: Pod
        name: "*"
    delete:
      - kind: ConfigMap
        name: "*"
```

> `orphanedResources.delete` 只建议用于**确定由 Argo CD 管理、且删了不会丢数据**的类型
> （ConfigMap、Secret 这类可重建对象）。不要对 CR、PV、Database 这类对象开启自动删除。

### 3.2 字段效果对照

| 字段 | 拦什么 | 不配的后果 |
|---|---|---|
| `sourceRepos` | 非授权仓库的同步 | 任何人可从自己的仓库同步 |
| `destinations` | 未授权集群 / namespace | 横向移动到别的团队环境 |
| `clusterResourceWhitelist` / `Blacklist` | 集群级资源（Namespace、CRD、ClusterRole、StorageClass…） | 业务方能改集群级配置，影响全平台 |
| `namespaceResourceWhitelist` / `Blacklist` | 命名空间内特定资源类型 | 业务方能写 Secret / 改 Ingress |
| `namespaceMetadata` | 给目标 namespace 自动注入标签/注解 | 无法按团队做成本与配额归集 |
| `roles` | 项目级 token 与权限 | CI 只能拿全局 token |
| `orphanedResources` | 残留资源巡检与清理 | 被 prune 掉的应用资源堆积在集群里 |

> `whitelist` 与 `blacklist` 同时存在时：**对集群级资源，blacklist 优先**；
> 一旦 `clusterResourceWhitelist` 非空，就变成"只允许列表内"的白名单语义。

### 3.3 把 Application 绑到 AppProject

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: team-a-api
  namespace: argocd
spec:
  project: team-a          # ← 这一行是边界的关键
  source:
    repoURL: https://github.com/myorg/team-a.git
    path: apps/api
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: team-a
```

绑定后，`Application` 的 `destination` 若超出 `AppProject.destinations`，
同步会直接失败并给出明确报错。这比"事后审计"有效得多。

---

## 4. ApplicationSet：把 1 个应用变成 N 个

你现在是手工创建 `Application`。当你有 3 个环境 / 5 个服务 / 2 个集群时，
手工创建就变成了负担和漂移来源。ApplicationSet 解决这个。

### 4.1 Git 目录生成器（最常用）

假设仓库结构是：

```
team-a/
├── apps/
│   ├── api/            → 生成 team-a-api
│   ├── worker/         → 生成 team-a-worker
│   └── web/            → 生成 team-a-web
└── shared/
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: team-a-apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/myorg/team-a.git
        revision: main
        directories:
          - path: apps/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: team-a
      source:
        repoURL: https://github.com/myorg/team-a.git
        path: '{{path}}'
        targetRevision: main
      destination:
        server: https://kubernetes.default.svc
        namespace: 'team-a-{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
        retry:
          limit: 5
          backoff:
            duration: 10s
            factor: 2
            maxDuration: 3m
```

要点：

- `template.metadata.name` 必须唯一，`{{path.basename}}` 是唯一可靠的目录名占位符；
  若目录名含非法字符，用 `{{path.basenameNormalized}}`。
- `template.spec.source.repoURL` 和 `path` 里的 `{{path}}` 由 generator 注入；
  **generator 的 `repoURL` 与 template 的 `repoURL` 可以不同**（多仓库场景用得上）。
- `syncPolicy` 写在 `template` 里，对所有生成的应用生效；写在单个
  `Application` 上则覆盖 template。
- `CreateNamespace=true` 让 Argo CD 自动建目标 namespace，是多 namespace 场景最省事的开关。

### 4.2 多仓库场景：一个应用引用多个源

如果基础组件来自另一个仓库（如 `shared-libs`），用多源写法：

```yaml
  source:
    - repoURL: https://github.com/myorg/team-a.git
      path: '{{path}}'
      targetRevision: main
    - repoURL: https://github.com/myorg/shared-libs.git
      targetRevision: main
      ref: shared
```

`ref:` 表示"把第二个源以该名字挂载"，配合 Helm 的
`valueFiles: ['values.yaml']` 使用。

### 4.3 按分支生成多环境（环境晋级的基础）

```yaml
generators:
  - git:
      repoURL: https://github.com/myorg/team-a.git
      revision: '{{branch}}'
      branches:
        - main
        - staging
        - production
template:
  metadata:
    name: 'team-a-api-{{branch}}'
  spec:
    source:
      repoURL: https://github.com/myorg/team-a.git
      path: apps/api
      targetRevision: '{{branch}}'
    destination:
      server: https://kubernetes.default.svc
      namespace: 'team-a-{{branch}}'
```

但更推荐的做法是：**环境差异放 `values`，不要复制 YAML**。

### 4.4 参数化 values（推荐的环境差异管理）

```yaml
generators:
  - list:
      elements:
        - environment: dev
          server: https://kubernetes.default.svc
        - environment: prod
          server: https://prod-cluster.example.com
  - git:
      repoURL: https://github.com/myorg/team-a.git
      revision: main
      directories:
        - path: apps/api
template:
  metadata:
    name: 'team-a-api-{{environment}}'
  spec:
    project: team-a
    source:
      repoURL: https://github.com/myorg/team-a.git
      path: apps/api
      targetRevision: main
      helm:
        valueFiles:
          - values.yaml
        parameters:
          - name: environment
            value: '{{environment}}'
    destination:
      server: '{{server}}'
      namespace: 'team-a-{{environment}}'
```

好处：一个 `apps/api` 目录 + 一份 `values-<env>.yaml`，
ApplicationSet 自动生成 dev/prod 两个应用，不需要维护两份 manifest。

### 4.5 matrix generator：多集群 × 多应用

```yaml
generators:
  - matrix:
      generators:
        - git:
            repoURL: https://github.com/myorg/team-a.git
            revision: main
            directories:
              - path: apps/*
        - cluster:
            selector:
              matchLabels:
                argocd.argoproj.io/secret-type: cluster
```

### 4.6 渐进式同步（Progressive Sync）

ApplicationSet 的 `progressive` 字段按批次逐步同步：

```yaml
spec:
  progressive:
    steps:
      - maxSurge: 1
        maxUnavailable: 0
        pauseDuration: 30s
      - maxSurge: 2
        maxUnavailable: 1
```

适合"先把 1 个集群升到新版本，观察没问题再全量"的灰度节奏。

### 4.7 ApplicationSet 的安全要点

| 要点 | 说明 |
|---|---|
| 生成器只产生 `Application` | 真正的资源仍由 application-controller 应用，权限边界不变 |
| 必须设唯一 `template.metadata.name` | 否则互相覆盖，症状是应用"随机消失" |
| `spec.template.spec.project` 建议显式写 | 否则落到 `default` project，等于没有边界 |
| ApplicationSet 本身是 CRD | 可以被它自己的 Application 管理（app-of-apps），但要防循环依赖 |

---

## 5. 同步策略与高级同步语义

### 5.1 `syncPolicy` 三个核心开关

```yaml
syncPolicy:
  automated:
    prune: true        # Git 里删掉文件 → 集群里删掉资源
    selfHeal: true     # 集群里被手工改了 → 自动改回 Git 的状态
    allowEmpty: false  # 允许部署一个空应用（把整个 app 的资源删光）
  syncOptions:
    - CreateNamespace=true
  retry:
    limit: 5
    backoff:
      duration: 10s
      factor: 2
      maxDuration: 3m
```

语义澄清（这是最常见的误解点）：

| 开关 | 触发的方向 | 风险 |
|---|---|---|
| `automated` | Git 变 → 自动 apply | 无 |
| `automated.prune` | Git 删 → 集群删 | **高**：删错文件等于删生产资源 |
| `automated.selfHeal` | 集群漂移 → 改回 Git | 中：会覆盖控制台里的临时改动 |
| `automated.allowEmpty` | 允许"空"部署 | **极高**：等价于删除该 app 全部资源 |

**建议的启用节奏**：先只开 `automated`（不带 prune），
观察一到两周确认 diff 逻辑正确，再开 `prune`；`allowEmpty` 在生产一律不开。

### 5.2 `syncOptions` 常用项

| Option | 作用 | 建议 |
|---|---|---|
| `CreateNamespace=true` | 目标 namespace 不存在时自动创建 | 多 namespace 场景必开 |
| `ServerSideApply=true` | 用 SSA 提交，避免和已有 controller 抢字段 | **推荐开**（见 §9） |
| `Replace=true` | 强制 replace 上报（如 Service 改 `clusterIP`） | 按需，慎用 |
| `RespectIgnoreDifferences=true` | 同步时忽略 `ignoreDifferences` 里列出的字段差异 | 与 diff 定制配合 |
| `ApplyOutOfSyncOnly=true` | 只 apply 处于 OutOfSync 的资源 | 大应用可降低 API 压力 |
| `PruneLast=true` | 把 prune 放到最后执行 | 减少中间态断裂 |
| `Validate=true` | 提交前用 API Server 做 dry-run 校验 | **推荐开** |
| `Prune=false` | 该应用整体禁止 prune（项目级强制） | 关键服务可加 |

### 5.3 Sync Waves：控制资源创建顺序

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  annotations:
    argocd.argoproj.io/sync-wave: "10"
---
apiVersion: v1
kind: Service
metadata:
  name: api
  annotations:
    argocd.argoproj.io/sync-wave: "20"
```

波次规则：

- 数字小的先同步，**同一 wave 内并行**；
- 上一波全部健康后，才进入下一波（健康判定对 CRD 走 `health.lua` 或 `status.conditions`）；
- 没写 wave 默认为 `0`；
- **wave 顺序错误会导致 "connection refused" / "no endpoints" 类假故障**，
  例如 Service 早于 Deployment 就绪。

### 5.4 Hooks：把 Argo CD 接进发布流水线

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: registry.example.com/migrate:1.4.2
          command: ["/bin/migrate", "up"]
```

| Hook | 何时执行 | 典型用途 |
|---|---|---|
| `PreSync` | 同步资源**之前** | DB migration、预热、配置校验 |
| `Sync` | 与资源**同时** | 初始化任务、注册中心上报 |
| `SyncFail` | 同步失败时 | 告警、回滚脚本 |
| `PostSync` | 同步**成功**后 | 冒烟测试、通知下游、刷新 CDN |
| `Skip` | 只手动触发时执行 | 手工排障脚本 |

`hook-delete-policy` 常用值：`BeforeHookCreation`（重跑前删旧的）、
`HookSucceeded`（成功后删）、`HookFailed`（失败后删）。

Hooks 在 **prune 时默认不会被删除**（避免误删审计痕迹），
需要显式 `HookSucceeded` 才会清理。

### 5.5 Argo Workflows + Hooks = 人工审批门禁

在 Hook 类型的 Workflow 里加入 `suspend` 节点，Argo CD 会把它置为等待状态，
人工在 UI 上 approve 后才继续。这是最常见的"生产环境必须审批"实现方式。

### 5.6 幂等与重复同步

Argo CD 的 apply 本身是幂等的（先 diff，再 apply 差异）。
但以下情况会导致"每次同步都有 diff"（永远 OutOfSync）：

- 控制器（如 controller-runtime 写入的字段、operator 改的 status）改动了资源；
- 有 `ignoreDifferences` 但没开 `RespectIgnoreDifferences=true`；
- CRD 没有 health 脚本，Argo CD 认为它"未就绪"，反复重试。

处理方式见 §6.4 和 §6.5。

---

## 6. 高级 GitOps 模式

### 6.1 App of Apps：根应用管理所有应用

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-apps
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/myorg/gitops.git
    path: bootstrap
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

`bootstrap/` 目录里放 ApplicationSet / AppProject 的定义，
根应用同步后子应用自动出现。

**App of Apps 的两个已知坑：**

1. **同步顺序**：根应用同步时子应用刚被创建，状态是 `OutOfSync`，
   需要等子应用自己完成首次同步 —— 根应用不会级联等待子应用健康。
2. **循环依赖**：根应用管理子应用，若子应用又管理着 Argo CD 自身 → 循环。
   务必确保根应用不管理"管理 Argo CD 自身的那个应用"。

### 6.2 单仓库多目录的推荐布局

```
gitops/
├── bootstrap/              # AppProject、ApplicationSet、根应用
├── apps/
│   ├── team-a/
│   │   ├── api/
│   │   └── worker/
│   └── team-b/
├── environments/
│   ├── dev/
│   ├── staging/
│   └── prod/
└── shared/
    └── kustomize/          # base
```

原则：**应用定义与环境分离**（`apps/` 与 `environments/` 分开），
同一个应用通过 kustomize overlay 渲染出不同环境，避免"复制粘贴 N 份 YAML"。

### 6.3 环境晋级（Promotion）

GitOps 里"晋级"不是复制 YAML，而是**改引用**：

```
staging 的 ApplicationSet → 指向 apps/team-a/api + values/staging
prod   的 ApplicationSet → 指向 apps/team-a/api + values/prod
```

晋级动作 = 把 prod 的 GitOps 提交更新。好处是 prod 的变更完全可审计、可回滚。

### 6.4 定制 diff（消除"永远 OutOfSync"）

在 `argocd-cm` 里给特定资源写 diff 定制：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  resource.customizations.diff.nginx.ingress.kubernetes.io_ Ingress: |
    local d = {}
    -- 忽略 controller 写入的 annotation
    d["metadata"]["annotations"] = nil
    return d
```

也可用 `resource.customizations.ignoreDifferences.<group>_<kind>` 声明忽略字段：

```yaml
  resource.customizations.ignoreDifferences.admissionregistration.k8s.io_ValidatingWebhookConfiguration: |
    jqPathExpressions:
      - '.webhooks[]?.clientConfig.caBundle'
```

对应到 Application 上也可以逐个配 `spec.ignoreDifferences`：

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas        # HPA 在改，不要被 Argo CD 改回去
      managedFieldsManagers:
        - name: horizontal-pod-autoscaler
```

> `ignoreDifferences` 只影响**比较**，要让它在 apply 时也生效，
> 需要加 `syncOptions: [RespectIgnoreDifferences=true]`。

### 6.5 自定义健康检查（health.lua）

Argo CD 内置了常见 CRD 的健康检查；对自定义 CRD 需要自己写：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  resource.customizations.health.example.com_MyApp: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.phase ~= nil then
        hs.status = "Progressing"
        if obj.status.phase == "Ready" then
          hs.status = "Healthy"
        end
        if obj.status.phase == "Failed" then
          hs.status = "Degraded"
        end
      else
        hs.status = "Healthy"
      end
    else
      hs.status = "Progressing"
    end
    return hs
```

不加健康脚本的后果：**sync wave 会被卡住**（下一波等上一波"健康"），
表现为"应用一直 Progressing"。

> Argo CD v3.x 已内置 `_.upbound.io` / `_.crossplane.io` 的 health 脚本，
> Crossplane 场景不需要自己配（见 `poc-argocd-integration.md`）。

### 6.6 漂移检测（Drift Detection）

- **自愈漂移**：开 `automated.selfHeal`，Argo CD 周期性对比并改回。
- **只报警不自动改**：不开 `selfHeal`，靠 notifications 的 `on-degraded` /
  `on-sync-status-unknown` 触发告警，人工判断。

生产环境建议：**非核心应用开 selfHeal，核心应用只报警**。
理由：selfHeal 会把控制台上的临时排障动作（如临时改副本数）直接抹掉。

### 6.7 "切换环境"到底改什么

这是初学者最容易混淆的地方。你在 UI 上看到"一个应用部署到某处"，
但 Argo CD 内部其实是**三个正交的坐标**：

```
一个应用落在哪 = ① 哪个集群（destination.server / destination.name）
              × ② 哪个 namespace（destination.namespace）
              × ③ 什么配置（values / 参数 / 分支）
```

所谓"切换环境"，就是改其中一到两个坐标。对应的正确做法：

| 你要切换的 | 在 Argo CD 里改什么 | Git 里改什么 | 推荐程度 |
|---|---|---|---|
| 同集群，换 namespace（dev → test） | `destination.namespace` | 不改 | ✅ 可行，但目标要换 |
| 同集群，换环境（dev → prod），namespace 也换 | `destination.namespace` + values | values 文件 / 参数 | ✅ 推荐 |
| 同集群，换环境，namespace 不变（同名不同集群） | 换集群 | values 文件 | ✅ 推荐 |
| 换集群（A → B） | `destination.server`（或 `name`） | 不改 | ✅ 推荐 |
| 换配置版本 | `targetRevision` / branch | 改分支或 tag | ✅ 推荐 |

**不该做的做法**：直接在 UI 上改 `destination`。
因为 Application 本身由 Git 管理（或开了 selfHeal），UI 的改动会被改回去，
或者造成"Git 里是 A、集群里是 B"的漂移。**所有环境切换都应该表达成一次 Git 提交。**

### 6.8 同一套 Git 部署到多个集群/多个环境

这是"一套代码多套部署"的标准解法，用 ApplicationSet 参数化目标：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: team-a-fleet
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          # dev：和 Argo CD 同集群
          - cluster: in-cluster
            server: https://kubernetes.default.svc
            namespace: team-a-dev
            env: dev
          # prod：远端集群
          - cluster: prod-cluster
            server: https://prod-cluster.example.com
            namespace: team-a-prod
            env: prod
  template:
    metadata:
      name: 'team-a-api-{{cluster}}'
    spec:
      project: team-a
      source:
        repoURL: https://github.com/myorg/team-a.git
        path: apps/api
        targetRevision: main
        helm:
          valueFiles:
            - 'values-{{env}}.yaml'
      destination:
        server: '{{server}}'
        namespace: '{{namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

要点：

- `list` generator 里的元素字段会变成模板变量，命名随意；
- `destination.server` 只能填 URL，**不能填集群名**；要用名字就在模板里写
  `destination.name: '{{cluster}}'`；
- `AppProject.destinations` 必须同时列出 A 和 B 两个目标（§7.4）；
- 每个集群都要有自己的 cluster secret 和 B 集群侧的 RBAC。

如果集群数量多、且都是"已注册"的关系，改用 `cluster` generator 更省事：

```yaml
generators:
  - cluster:
      selector:
        matchLabels:
          argocd.argoproj.io/secret-type: cluster
          env: production     # 只挑带这个 label 的集群
template:
  spec:
    destination:
      name: '{{name}}'
      namespace: 'team-a-{{name}}'
```

### 6.9 环境切换的完整链路（含一个容易漏的坑）

以"把应用从 A 集群的 dev 切到 B 集群的 prod"为例，完整链路是：

```
① 在 A 的 argocd namespace 注册 B：cluster secret（§7.2）
② 在 B 建受限 SA + RBAC（§7.3）
③ 打通 A → B 的控制面网络（§7.5）
④ AppProject.destinations 放行 B（§7.4）
⑤ 改 Git：更新 ApplicationSet 的 list/cluster 参数 + values-prod.yaml
⑥ Merge → Argo CD 检测到 diff → 在 B 上 apply
```

**第 ⑥ 步之后的清理，最容易被忘掉：**

Argo CD 的资源追踪是**按集群分别记录**的。把 `destination` 从 A 改到 B 之后，
A 集群里那份资源**不会自动消失**（即使开了 `prune`）——因为对 Argo CD 来说，
它已经"不认识"A 集群里的那些资源了，它们变成了孤儿。

必须手工清理：

```bash
# 在 A 集群上查残留（tracking-id 的值形如 <app>/<group>/<kind>/<name>）
kubectl get deploy,svc,cm,secret -A -o json | \
 jq -r '.items[] | select(.metadata.annotations["argocd.argoproj.io/tracking-id"] != null) | "\(.kind) \(.metadata.namespace)/\(.metadata.name)"'
```

更好的做法：**A 和 B 各维护一个独立的 Application**，由 ApplicationSet 分别生成。
这样两个集群的资源归属清晰，清理时也只需删掉其中一个 Application（配上 prune）。

---

## 7. 多集群与凭据管理

### 7.0 先回答：Argo CD 在 A 集群，要部署到 B 集群，要单独配置吗？

**要，但只有四件事，而且 B 集群里不需要装 Argo CD。**

很多人第一反应是"是不是要在 B 里也装一套 Argo CD"——**不需要**。
Argo CD 的控制面（server / application-controller / repo-server）全部留在 A 集群，
B 集群里只会有两样东西：

1. 被管理的业务资源；
2. 一个给 Argo CD 用的、权限受限的 ServiceAccount。

```
        Git 仓库
           │  ① repo-server 拉取 + 渲染
           ▼
┌──────────────────────────────┐
│  Cluster A                   │
│  ┌────────────────────────┐  │
│  │ Argo CD 控制面          │  │
│  │ server / controller /   │  │
│  │ repo-server             │  │
│  └────────────────────────┘  │
│        │                     │
│        │ ② 访问 B 的 K8s API  │
│        │    凭据 = cluster    │
│        │    secret（在 A 里） │
└────────┼─────────────────────┘
         │  ③ apply
         ▼
┌──────────────────────────────┐
│  Cluster B                   │
│  API Server                  │
│    └── namespace/team-a      │  ← 资源真正落地的地方
│    └── SA: argocd-deployer   │  ← Argo CD 在 B 上的身份
└──────────────────────────────┘
```

需要单独做的四件事（缺一件就不通）：

| # | 要做的事 | 在哪里做 | 不做的后果 |
|---|---|---|---|
| 1 | **网络可达**：A 里的 Argo CD Pod 能访问 B 的 API Server endpoint | GCP 网络（VPC peering / NAT / PSC） | `i/o timeout`、`connection refused` |
| 2 | **集群凭据**：在 A 的 `argocd` namespace 里放一个 `cluster` secret | Argo CD（K8s Secret） | `cluster "prod" not found` |
| 3 | **边界放行**：`AppProject.destinations` 里写上 B 的 server + namespace | Argo CD（AppProject） | `do not match any of the allowed destinations` |
| 4 | **目标集群权限**：B 里给 Argo CD 一个受限 SA | B 集群（RBAC） | `not permitted` / `forbidden` |

**Application 侧只有一行变化**：`spec.destination.server`（或 `spec.destination.name`）
从 A 改成 B。其余（Git 路径、渲染、sync 策略）完全复用。

> 备选方案：如果 A → B 的网络根本打不通（例如跨 VPC 且不允许 peering），
> 可以让 B 集群里跑 [argocd-agent](https://github.com/argoproj-labs/argocd-agent)（独立项目），
> 由 B 侧的 agent 主动去 A 拉取配置。此时 A 侧需要开启 apps-in-any-namespace 并给 agent 签发 token。
> 【待核实】该方案与 v3.5.6 的兼容性需按 argocd-agent 官方文档确认。

### 7.1 目标集群的两种写法

```yaml
spec:
  destination:
    server: https://prod-cluster.example.com   # 多集群
    namespace: team-a
```

```yaml
spec:
  destination:
    server: https://kubernetes.default.svc     # in-cluster（Argo CD 就在目标集群里）
    namespace: team-a
```

in-cluster 场景下 `server` 仍需填写（写 `https://kubernetes.default.svc`），
Argo CD 会识别并使用集群内的 SA 凭据。

也可以用集群**名字**（`destination.name`），即 cluster secret 里的 `name` 字段：

```yaml
spec:
  destination:
    name: prod-cluster                          # 引用 cluster secret 的 name
    namespace: team-a
```

> `Application.spec.destination` 里 `server` 和 `name` **二选一**（CRD 描述：
> "must be set if Server is not set"）。用 `name` 的好处是 Git 里的目标地址
> 不随集群 URL 变化，环境晋级时更干净。
>
> 注意 `AppProject.spec.destinations[]` 的语义**不同**：官方文档明确写的是
> "Destination clusters can be identified by `server`, `name`, or both"，
> 两者同时写表示"URL 和集群名都要匹配上"，属于更严格的收口。

### 7.2 注册 B 集群：cluster secret

这是第 2 件事，也是跨集群的**唯一硬性新增对象**。

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cluster-prod
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
stringData:
  name: prod-cluster
  server: https://prod-cluster.example.com
  config: |
    {
      "bearerToken": "<service-account-token>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64-ca>"
      }
    }
```

规则：

- label 必须是 `argocd.argoproj.io/secret-type: cluster`；
- 名字约定 `cluster-<name>`，其中 `name` 会出现在 UI 的 Cluster 列表里，
  也是 `destination.name` 要引用的值；
- **绝不要把 cluster-admin kubeconfig 直接塞进来**。

cluster secret 支持的字段（Argo CD 官方定义）：

| 字段 | 必填 | 含义 |
|---|---|---|
| `name` | ✅ | 集群名，`destination.name` 引用它 |
| `server` | ✅ | B 集群的 API Server URL |
| `config` | ✅ | 凭据（bearerToken / TLS / exec / AWS role-arn 等） |
| `namespaces` | ❌ | 逗号分隔的可访问 namespace 列表；**一旦设置，集群级资源默认被忽略** |
| `clusterResources` | ❌ | `"true"` / `"false"`，仅在限制了 `namespaces` 时生效 |
| `project` | ❌ | 把该集群限定到某个项目（项目级集群） |

CLI 方式注册（**仅用于 PoC，慎用于生产**）：

```bash
# 在 Argo CD 所在的 A 集群上执行，用 B 集群的 kubeconfig
argocd cluster add prod-cluster --kubeconfig /path/to/b-kubeconfig
```

`argocd cluster add` 会在 **B 集群**的 `kube-system` 里创建 `argocd-manager` SA，
并绑定到 **cluster-admin 级别的权限**（官方文档明确提示这是高权限操作）。
生产环境请跳过这一步，手工创建受限 SA（见 §7.3），再把它的 token 填进 secret。

### 7.3 B 集群侧的最小权限 SA

目标集群里建一个专用 SA，只授予它需要的权限：

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-deployer
  namespace: team-a
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argocd-deployer
  namespace: team-a
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
---
# 只在需要 CreateNamespace=true 时才给 Namespace 创建权限（集群级）
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-namespace-creator
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-namespace-creator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argocd-namespace-creator
subjects:
  - kind: ServiceAccount
    name: argocd-deployer
    namespace: team-a
```

拿到 token 后填进 A 集群的 cluster secret：

```bash
# 在 B 集群上取 token
K8S_TOKEN=$(kubectl -n team-a create token argocd-deployer --duration=8760h)

# 换算成 base64 后写入 A 的 secret
K8S_TOKEN_B64=$(printf '%s' "$K8S_TOKEN" | base64 | tr -d '\n')
```

> `argocd-deployer` 能不能删对象，直接决定了 `prune` 的爆炸半径。
> 收紧它，是最有效的"防手滑"手段。

> ⚠️ **token 有效期**：`kubectl create token` 生成的是 **bound token**，
> 默认只有 1 小时有效期（K8s 1.24+ 还会自动给 SA 创建短时 token）。
> 直接把它塞进 cluster secret，到期后跨集群同步会突然全线失败。
> 生产上三选一：
> ① 用传统的长效 ServiceAccount token Secret（`kubernetes.io/service-account-token` 类型，缺点是不会自动轮换）；
> ② 用 External Secrets / Secret Manager 定期刷新这个 cluster secret；
> ③ 用 `exec` 凭据模式（`config.exec`），让 Argo CD 通过外部命令动态取凭据。

### 7.4 AppProject 必须把 B 集群放行（第 3 件事）

只注册 cluster secret 不改 AppProject，跨集群同步会被直接拒绝：

```yaml
spec:
  destinations:
    # A 集群（in-cluster）
    - server: https://kubernetes.default.svc
      namespace: team-a
    # B 集群
    - server: https://prod-cluster.example.com
      namespace: team-a
      name: prod-cluster
```

报错长这样：

```
InvalidSpecError: spec.destination.server https://prod-cluster.example.com
in project team-a does not match any of the allowed destinations
```

更严格的做法是同时写 `server` 和 `name`（官方示例就是
`server: https://kubernetes.default.svc` + `name: in-cluster`），
这样只有 URL 和集群名都对应上才算命中边界。

再进一步，可以开启**项目级集群**：

```yaml
spec:
  # 只有本项目的应用才能用 project 字段等于 team-a 的集群 secret
  permitOnlyProjectScopedClusters: true
```

配合 cluster secret 里的 `project: team-a` 字段使用，
效果是"这个集群只属于 team-a 这个项目"，其他项目即使知道集群名也用不了。

### 7.5 GKE 上的网络前提（第 1 件事，实践中最容易卡住的一环）

Argo CD 的 Pod 跑在 A 集群的节点上，它访问 B 的 API Server 走的是 **A 节点的网络**，
不是 Argo CD 自己的网络。所以要看的是"**A 的节点能不能访问 B 的控制面**"。

| B 集群的控制面类型 | A 侧需要满足 | server 怎么填 |
|---|---|---|
| 公有 endpoint（默认） | A 的节点能出公网（Cloud NAT），且 B 的 **authorized networks** 放行 A 的出口 CIDR | `https://<CLUSTER_ENDPOINT>` |
| 私有 endpoint（private cluster） | A 与 B 同 VPC，或 VPC peering / Cloud VPN / Interconnect，且能路由到 B 的控制面私有 IP | `https://<PRIVATE_ENDPOINT_IP>` |
| Private Service Connect | A 所在 VPC 能访问 B 的 PSC endpoint；DNS 型 endpoint 需 PSC 解析 | `https://<CLUSTER_ENDPOINT>` 或 DNS endpoint |

需要注意的坑：

- **VPC peering 不支持传递路由**。A → peering → B 走不通时，
  改用共享 VPC（Shared VPC）或 Transit Gateway。
- **控制平面全局访问（control plane global access）** 关闭时，
  跨区域访问私有 endpoint 会失败，需要在 B 上打开。
- **GKE 托管的服务网段**（如 `34.118.224.0/20` 等）容易和 peering 网段冲突，
  建 peering 前先核对两边 CIDR。
- **A 的节点没有外部 IP**（私有节点池）时，必须有 Cloud NAT，否则连公有 endpoint 也不通。

在 A 集群里直接验证连通性（最快的排障手段）：

```bash
kubectl -n argocd run netcheck --rm -it --restart=Never \
  --image=curlimages/curl -- \
  curl -sv --connect-timeout 10 https://<B_CLUSTER_ENDPOINT>:443/version
```

能返回 `{"major":"1",...}` 就说明网络通；超时就是网络问题，与 Argo CD 配置无关。

### 7.6 跨集群的常见错误对照

| 报错 | 根因 | 处理 |
|---|---|---|
| `cluster "prod-cluster" not found` | secret 名字不叫 `cluster-<name>`，或 label 缺失 | `kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=cluster` |
| `does not match any of the allowed destinations` | AppProject 没放行 B | 补 §7.4 |
| `dial tcp ...: i/o timeout` | A → B 网络不通 | 走 §7.5 的 `netcheck` |
| `tls: failed to verify certificate` | `caData` 不对 / 用了错误的 endpoint | GKE 集群用集群 CA 证书；或改用 DNS endpoint |
| `namespaces is forbidden` | 目标集群 SA 缺该 namespace 的权限 | 补 B 集群 RoleBinding |
| 同步"成功"但资源没出现在 B | `destination` 没真正改，或资源 YAML 里写死了 `metadata.namespace` | `argocd app get --show-operation` 看实际目标集群 |

### 7.7 仓库凭据

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  url: https://github.com/myorg
  username: git
  password: <PAT>
  type: git
```

### 7.8 用 Workload Identity 代替静态 token（GKE 上推荐）

GKE 上建议让 Argo CD 通过 Workload Identity 访问 GCP（如 Secret Manager、
Cloud Build 集成），而不是长期 token。

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-deployer
  namespace: argocd
  annotations:
    iam.gke.io/gcp-service-account: argocd@myproject.iam.gserviceaccount.com
---
apiVersion: iam.gke.io/v1
kind: IAMServiceAccountBinding
metadata:
  name: argocd-wi
  namespace: argocd
spec:
  serviceAccountName: argocd-deployer
  gcpServiceAccount: argocd@myproject.iam.gserviceaccount.com
  project: myproject
```

并把 `argocd-repo-server` 绑到该 SA：

```bash
kubectl -n argocd annotate sa argocd-repo-server \
  iam.gke.io/gcp-service-account=argocd@myproject.iam.gserviceaccount.com
```

配合 `argocd-cm` 里的 `k8s.secrets.gcsp.enabled: "true"` 使用。

---

## 8. 通知与可观测性

### 8.1 notifications 最小可用配置

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.webhook.github: |
    url: https://api.github.com/repos/myorg/gitops/dispatches
    headers:
      - name: Authorization
        value: "Bearer <PAT>"

  template.app-deployed: |
    message: |
      应用 {{.app.metadata.name}} 同步完成（{{.app.status.sync.status}}）
      提交时间：{{.app.status.operationState.finishedAt}}

  trigger.on-sync-succeeded: |
    - when: app.status.sync.status == 'Synced'
      send: [app-deployed]

  trigger.on-degraded: |
    - when: app.status.health.status == 'Degraded'
      send: [app-deployed]

  subscriptions: |
    - recipients:
        - slack:argocd-alerts
      triggers:
        - on-sync-succeeded
        - on-degraded
```

凭据放 `argocd-notifications-secret`（Slack token、Webhook secret 等）。

### 8.2 按应用订阅通知

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: team-a-api
  namespace: argocd
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: argocd-alerts
    notifications.argoproj.io/subscribe.on-degraded.slack: argocd-alerts
```

### 8.3 GitHub Webhook 触发 Argo CD（降低延迟）

GitHub 仓库 → Settings → Webhooks：

```
Payload URL: https://argocd.example.com/api/webhook/github
Content type: application/json
Secret: <与 argocd-cm 中 webhook secret 一致>
```

效果：从默认 **120s + 60s jitter** 的 resync 周期，降到**秒级**。
对 CI/CD 反馈链路来说，这个提升非常直观。

### 8.4 观测面

| 手段 | 入口 | 看什么 |
|---|---|---|
| Metrics | `argocd-server:8083/metrics`、`application-controller:8082/metrics`、`repo-server:8081/metrics` | reconcile 次数、diff 大小、API 调用量、git 操作耗时 |
| Events | `kubectl -n argocd get events --sort-by=.lastTimestamp` | 应用级事件（webhook 收到、sync 开始/结束） |
| Grafana | Argo CD 自带 dashboard JSON | 同步延迟、失败率 |
| kubectl | `kubectl -n argocd get applications -A` | 全局状态一览 |
| CLI | `argocd app list` / `argocd app get <name>` | 单应用排查 |

CLI 的"全局视角"写法（直连集群内 server）：

```bash
argocd app --core list \
  --core-instance=argocd-server.argocd.svc.cluster.local \
  -o wide
```

一次看全所有命名空间的应用状态：

```bash
kubectl -n argocd get applications -A \
  -o custom-columns=\
'NS:.metadata.namespace,NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REV:.status.sync.revision'
```

---

## 9. 安全基线

按优先级排列，前三条是必须的：

| # | 基线 | 做法 |
|---|---|---|
| 1 | **默认最小权限** | `policy.default: role:readonly`；admin 账号只留 1~2 个且强制 SSO + MFA |
| 2 | **SSO + 分组** | 不在 Argo CD 里建用户，权限由 IdP 组驱动（见 §2.3） |
| 3 | **AppProject 边界** | 每个团队一个 project，`destinations` 收敛，`clusterResourceWhitelist` 留空 |
| 4 | **prune 分级** | 核心应用 `syncOptions: [Prune=false]`；生产 namespace 整体禁 prune |
| 5 | **ServerSideApply** | `syncOptions: [ServerSideApply=true]`，减少与 controller 抢字段导致的冲突 |
| 6 | **Secret 不进 Git** | 凭据放 `argocd-secret` / `argocd-notifications-secret` / External Secrets；Git 里只放引用 |
| 7 | **ClusterRole 收窄** | 目标集群 SA 只给必要 verbs；禁删权限可单独用 `Prune=false` 兜底 |
| 8 | **exec plugin 管控** | exec plugin 能在目标集群跑任意命令，等于绕过全部 RBAC，只在受控场景开启 |
| 9 | **TLS** | Argo CD 前置 HTTPS（GLB / Ingress 终止）；集群间证书用 `argocd-tls-certs` |
| 10 | **审计** | 开启 Cloud Audit Logs；关键项目用项目角色 token，便于按主体追责 |

### 9.1 复核当前配置的命令

```bash
# 当前默认角色与策略
kubectl -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.policy\.default}'; echo
kubectl -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.policy\.csv}'

# 本地账号清单
argocd account list

# 集群凭据 secret（确认没有把 admin kubeconfig 塞进来）
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=cluster

# 各项目的边界
kubectl -n argocd get appprojects -o wide
```

---

## 10. 管理员日常运维

### 10.1 升级

```bash
# 1) 先备份
kubectl -n argocd get applications -A -o yaml > backup/applications.yaml
kubectl -n argocd get applicationsets -A -o yaml > backup/applicationsets.yaml
kubectl -n argocd get appprojects -o yaml > backup/appprojects.yaml
kubectl -n argocd get cm argocd-cm argocd-rbac-cm -o yaml > backup/cm.yaml
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=cluster -o yaml > backup/clusters.yaml

# 2) 升级（apply 新版 install.yaml / Helm upgrade）
kubectl apply -n argocd -f install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m
kubectl -n argocd rollout status deploy/argocd-application-controller --timeout=5m
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=5m
```

**升级前必看**：本目录 `install.yaml` 对应的版本（v3.5.6）。
跨大版本升级（v2 → v3）有 CRD 结构变化，必须先读 release notes。

### 10.2 备份与恢复

必须备份的对象：

| 对象 | 命令 |
|---|---|
| Applications | `kubectl -n argocd get applications -A -o yaml` |
| ApplicationSets | `kubectl -n argocd get applicationsets -A -o yaml` |
| AppProjects | `kubectl -n argocd get appprojects -o yaml` |
| 各类 ConfigMap | `kubectl -n argocd get cm argocd-cm argocd-rbac-cm argocd-notifications-cm -o yaml` |
| 集群 / 仓库凭据 | `kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=cluster -o yaml` |
| Argo CD 自身定义 | 存进 Git（app-of-apps），这才是真正的"可恢复" |

**核心原则：Argo CD 自身必须由 Git 管理**。
只有 Application 的状态可以随时重建，Argo CD 的配置不能。

### 10.3 高可用

| 组件 | HA 做法 |
|---|---|
| `argocd-server` | 多副本 + PDB + Service（默认就有） |
| `argocd-application-controller` | 多副本（leader election），注意主备切换期可能短暂重复 reconcile |
| `argocd-repo-server` | 多副本 + 独立副本数（渲染是 CPU 密集型） |
| `argocd-redis` | 官方 HA chart 或托管 Redis；单副本是单点 |
| `argocd-applicationset-controller` | 多副本；生成逻辑必须幂等，`generateName` 不要冲突 |

### 10.4 巡检清单（建议每周跑一次）

```bash
# 1) 非健康应用
kubectl -n argocd get applications -A \
  -o jsonpath='{range .items[?(@.status.health.status!="Healthy")]}{.metadata.namespace}{"/"}{.metadata.name}{"  "}{.status.health.status}{"\n"}{end}'

# 2) 长期 OutOfSync（疑似 diff 定制缺失）
kubectl -n argocd get applications -A \
  -o jsonpath='{range .items[?(@.status.sync.status=="OutOfSync")]}{.metadata.name}{"  "}{.status.sync.status}{"\n"}{end}'

# 3) 落在 default project 的应用（应该很少）
kubectl -n argocd get applications -A \
  -o jsonpath='{range .items[?(@.spec.project=="default")]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}'

# 4) 集群凭据清单
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=cluster
```

### 10.5 命名空间清理

删掉一个 Application 后，它在集群里创建的资源**不会自动消失**（除非开了 prune）。
残留资源排查：

```bash
# 找出不带 Argo CD tracking 注解的资源（粗略筛选）
kubectl get deploy,svc,cm -A -o json | \
 jq -r '.items[] | select(.metadata.annotations["argocd.argoproj.io/tracking-id"] == null) | "\(.kind) \(.metadata.namespace)/\(.metadata.name)"'
```

配合 `AppProject.orphanedResources.monitor` 做常态化巡检。

---

## 11. 分阶段落地路线图

不要一次做完。按下面 4 个阶段推进，每阶段都有明确的验收标准。

### 阶段 1（第 1 周）：权限与边界

| 动作 | 验收 |
|---|---|
| 接 SSO（已有 Dex 或 Keycloak），`argocd-cm` 加 `scopes: [groups]` | 用组账号登录，UI 显示组名 |
| `argocd-rbac-cm` 设 `policy.default: role:readonly`，写 `policy.csv` | 业务账号看不到其他项目 |
| 建 `AppProject`（每团队一个），把现有 Application 挂上 `spec.project` | 越界 destination 的应用同步直接失败 |
| 本地 admin 账号禁用或改强密码 | `argocd account list` 中无多余 admin |

### 阶段 2（第 2 周）：ApplicationSet

| 动作 | 验收 |
|---|---|
| 把现有手写 Application 改成 ApplicationSet（git directories generator） | 删掉一个目录，对应 Application 自动消失 |
| 引入 `values` 参数化，消除环境间 YAML 复制 | `environments/` 下不再有重复 manifest |
| 给 template 加 `spec.project` | 所有生成的应用都在正确 project 下 |

### 阶段 3（第 3 周）：同步语义与发布门禁

| 动作 | 验收 |
|---|---|
| 补 `syncOptions: [CreateNamespace=true, ServerSideApply=true, Validate=true]` | 新 namespace 无需手工创建 |
| 给资源加 `sync-wave`，修好 wave 顺序 | 消除 "connection refused" 类偶发故障 |
| 接 PreSync/PostSync hook（migration + 冒烟） | 迁移失败时同步整体失败并告警 |
| 谨慎开 `prune`（先在一个非核心应用试） | 删 Git 文件能正确删集群资源，且不会误删 |

### 阶段 4（第 4 周）：通知与观测

| 动作 | 验收 |
|---|---|
| 配 `argocd-notifications-cm`（Slack / 企微 Webhook）+ subscriptions | 同步失败能收到通知 |
| 配 GitHub Webhook → `/api/webhook/github` | 改 Git 后 10s 内开始同步 |
| 导入 Grafana dashboard + Prometheus 抓取 metrics | 能在面板上看到同步延迟与失败率 |
| 建立每周巡检脚本（第 10.4 节） | 巡检脚本可重复执行 |

### 阶段 5（按需）：跨集群与多环境

| 动作 | 验收 |
|---|---|
| 注册目标集群（B）的 cluster secret | UI 的 Clusters 列表能看到 B |
| B 集群建受限 SA + RBAC | `kubectl auth can-i --as=system:serviceaccount:team-a:argocd-deployer -n team-a create deploy` 通过 |
| A → B 控制面网络打通 | `netcheck` 能返回 `/version` |
| AppProject 放行 B | 越界 destination 不再报错，但 B 未注册时仍报错（证明边界生效） |
| ApplicationSet 参数化集群 + namespace | 一次提交生成多环境应用 |

---

## 12. 排障速查表

| 症状 | 最可能的原因 | 处理 |
|---|---|---|
| Application 一直 `Progressing` | CRD 缺 health.lua，或 wave 顺序错误 | 看 controller 日志的 health 相关行；补健康检查 |
| Application 一直 `OutOfSync` | 控制器改了字段，diff 未忽略 | 加 `ignoreDifferences` 或 `resource.customizations.diff` |
| 同步报 `not permitted` | 目标集群 SA 权限不足 | 补 RBAC；确认 `destination.server` 与 secret 匹配 |
| 同步报 `destination namespace not allowed` | AppProject `destinations` 未覆盖 | 改 AppProject 或改 destination |
| `spec.source.repoURL` 拉取失败 | 仓库凭证 / 私钥 / CA 问题 | 检查 repo-creds secret；查 repo-server 日志 |
| Sync 一直 `Unknown` | repo-server 渲染失败 | `argocd app get <name>` 看 render error；检查 Helm/Kustomize 参数 |
| 同步成功但资源没出现 | `destination.namespace` 与资源内 `metadata.namespace` 冲突 | 统一只由 destination 决定 namespace |
| 部分资源被删 | prune 生效 | 立刻 `argocd app undo`；检查 Git 是否误删文件 |
| UI 登录后立刻掉线 | session secret 变更 / Redis 问题 | 检查 `argocd-secret`、redis Pod 状态 |
| 应用同步慢（>1 分钟） | 走的是 120s resync 而非 webhook | 配 GitHub Webhook |
| 通知不触发 | trigger 条件不匹配 / secret 缺失 | 检查 `argocd-notifications-cm`；查 notifications controller 日志 |
| 跨集群同步报 `cluster not found` | cluster secret 名字/label 不对 | §7.6 |
| 跨集群同步报 `not match any of the allowed destinations` | AppProject 没放行目标集群 | §7.4 |
| 跨集群同步 `i/o timeout` | A 节点到 B 控制面网络不通 | §7.5 的 `netcheck` |
| 换了 destination 后旧集群资源还在 | 资源追踪按集群记录，旧集群成孤儿 | §6.9 的清理步骤 |

---

## 附录 A. 核实来源

| 结论 | 来源 |
|---|---|
| Argo CD 版本 v3.5.6 | 本目录 `install.yaml`、`argocd-api.md` |
| 内置角色 `role:admin` / `role:readonly` | `argoproj/argo-cd` `docs/user-guide/rbac.md` |
| `policy.csv` / `policy.default` / `scopes: [groups]` | 同上 `docs/user-guide/rbac.md`、`docs/operator-manual/argocd-cm.yaml` |
| 项目角色 token API | 同目录 `argocd-api.md`（`POST /api/v1/projects/{project}/roles/{role}/token`） |
| `AppProject` 字段（sourceRepos / destinations / whitelist / blacklist / namespaceMetadata / roles / orphanedResources） | `argoproj/argo-cd` `docs/user-guide/projects.md` |
| ApplicationSet generator 类型与模板变量 | `argoproj/argo-cd` `docs/operator-manual/applicationset.yaml` |
| `syncOptions` 全部取值 | `argoproj/argo-cd` `docs/user-guide/sync-options.md` |
| Hook 名称与 `hook-delete-policy` | `argoproj/argo-cd` `docs/user-guide/resource_hooks.md` |
| `resource.customizations` health/diff/ignoreDifferences | `argoproj/argo-cd` `docs/operator-manual/argocd-cm.yaml` |
| 集群 / repo-creds secret 标签与结构 | `argoproj/argo-cd` `docs/operator-manual/declarative-setup.md`、`docs/user-guide/private-repositories.md` |
| cluster secret 字段（`name` / `server` / `namespaces` / `clusterResources` / `project`） | `argoproj/argo-cd` `docs/operator-manual/declarative-setup.md`（Clusters 章节） |
| `argocd cluster add` 会在目标集群创建 `argocd-manager` SA（高权限） | `argoproj/argo-cd` `docs/operator-manual/cluster-management.md`、`docs/operator-manual/security.md` |
| `destination.name` 与 `destination.server` 互斥；in-cluster 用 `https://kubernetes.default.svc` 或 `in-cluster` | `argoproj/argo-cd` `docs/getting_started.md`、`docs/user-guide/application-specification.md` |
| ApplicationSet `cluster` generator 与 `matchLabels` 选择器 | `argoproj/applicationset` `docs/Generators-Cluster.md` |
| `CreateNamespace=true` 在目标集群创建 namespace | `argoproj/argo-cd` `docs/user-guide/sync-options.md` |
| GKE 私有集群控制面可达性、VPC peering 无传递路由、control plane global access | Google Cloud 文档 `kubernetes-engine/docs/concepts/network-isolation`、`docs/how-to/network-isolation` |
| notifications trigger / subscription 格式 | `argoproj/argo-cd` `docs/operator-manual/notifications.yaml` |
| GitHub webhook 端点 `/api/webhook/github` | `argoproj/argo-cd` `docs/operator-manual/webhook.md` |
| 默认 resync 120s + 60s jitter、ApplicationSet requeue 3min | 同目录 `poc-argocd-git-to-apply-trigger.md`（已核实） |
| `resourceTrackingMethod` 默认 annotation、SSA 支持、namespace 覆盖规则 | 同目录 `poc-argocd-integration.md`（已核实） |
| Argo CD v3.x 内置 `_.upbound.io` / `_.crossplane.io` health.lua | 同上 |

> 【待核实】以下需要按你的实际环境确认：
> ① 目标集群 API 地址（`destination.server` 用 `https://kubernetes.default.svc` 还是外部地址）；
> ② 你的 GitHub 仓库 URL 与目录结构（生成器里的 `path` 要对齐）；
> ③ SSO 是用现成的 Dex 还是另接 Keycloak/Okta；
> ④ 运行时 namespace 的实际命名（是否带环境后缀）；
> ⑤ 若要跨集群：A 与 B 的控制面类型（公有 / 私有 / PSC）、是否同 VPC、是否已开 control plane global access。

---

## 附录 B. 与同目录其他 Argo CD 文档的关系

| 文档 | 定位 | 与本文的关系 |
|---|---|---|
| `poc-argocd-integration.md` | Argo CD × Crossplane 的控制平面分工、字段所有权、`prune`/`selfHeal` 语义细节 | 本文 §5 / §6 是它的"通用化"版本，Crossplane 专用细节看它 |
| `poc-argocd-git-to-apply-trigger.md` | Git 提交 → webhook/resync → reconcile → apply → 下游 controller 的逐阶段链路 | 本文 §8.3 / §12 引用了它的延迟与排障结论 |
| `argocd-api.md` | Argo CD v3.5.6 API 参考（认证、token、projects） | 本文 §2.5 的 token 说明以它为准 |
| `argo-api-claude.md` | API 场景下的调用约定 | 与本文互补 |
| `argocd-application-guide.md` | `Application` CRD 字段详解 + 9 个示例 YAML | 本文 §3.3 的 Application 最小示例以它为准；字段语义已对上游 v3.5.6 核对 |

### B.1 三者的组合用法

```
本文（管理与治理视角）
  ├─ §2 RBAC / §3 AppProject  → 谁能改什么、边界在哪
  ├─ §4 ApplicationSet        → 用声明代替手工创建
  ├─ §5 同步语义 + §7 凭据    → 部署行为与爆炸半径
  └─ §8 通知 + §10 运维       → 日常可运营

poc-argocd-integration.md   → 多控制面协作时的字段所有权与下游调谐
poc-argocd-git-to-apply-trigger.md → 出问题时定位卡在哪个阶段
```
