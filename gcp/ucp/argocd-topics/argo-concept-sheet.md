# Argo CD 概念速查表（Concept Sheet）

> **定位**：一页看懂 Argo CD 的核心对象、组织关系，以及本方案里
> `bootstrap/` 目录的职责。
> **不是**逐字段手册 —— 字段细节见 [`04-appproject-rbac.md`](./04-appproject-rbac.md)、
> [`05-appset.md`](./05-appset.md)、[`03-dex-ldap-sso.md`](./03-dex-ldap-sso.md)。
>
> **版本基线**：Argo CD v3.5.6

---

## 0. 一页速览

| # | 概念 | 一句话定义 | 是什么（K8s 资源 / 进程 / 目录） | 存在哪 | 谁的上下游 |
|---|---|---|---|---|---|
| 1 | **Application** | 一个应用的**真实同步单元** | CRD `argoproj.io/v1alpha1/Application` | `argocd` 命名空间 | 被 ApplicationSet 生成；被 AppProject 约束 |
| 2 | **ApplicationSet** | **模板 + 生成器**，按规则批量造 Application | CRD `argoproj.io/v1alpha1/ApplicationSet` | `argocd` 命名空间 | 生成 Application；**引用** AppProject |
| 3 | **AppProject** | **资源约束边界**：允许的源仓库 / 目标集群 / namespace / 资源类型 / 项目角色 | CRD `argoproj.io/v1alpha1/AppProject` | `argocd` 命名空间 | 被 Application（及 ApplicationSet 模板）**逻辑引用** |
| 4 | **Root Application**（App of Apps） | 指向 `bootstrap/` 的那个 Application，负责把其它定义"种"出来 | 普通 Application | `argocd` 命名空间 | 同步 `bootstrap/` → 生成 AppProject / ApplicationSet → 再生成 Application |
| 5 | **Repository** | Git 仓库元信息 + **访问凭据**（GitHub App / PAT / SSH key） | CRD `argoproj.io/v1alpha1/Repository` | `argocd` 命名空间 | 被 Application 的 `spec.source.repoURL` 使用 |
| 6 | **Cluster Secret** | 一个**已注册目标集群**的连接信息（server / CA / token） | Secret（`argocd.argoproj.io/secret-type: cluster`） | `argocd` 命名空间 | 被 `clusters` 生成器遍历、被 AppProject 的 `destinations` 匹配 |
| 7 | **Dex** | **身份联合代理 / 翻译官**：对上是 OIDC Provider，对下接 LDAP / GitHub / SAML | Deployment `argocd-dex-server` | `argocd` 命名空间 | Argo CD `→` Dex `→` 企业 LDAP |
| 8 | **OIDC** | 标准的 OAuth2 / OpenID Connect 认证协议 —— **Argo CD 唯一原生支持的登录方式** | 协议 | — | Argo CD 与 Dex 之间的契约 |
| 9 | **LDAP / AD** | 企业内部的账号 / 部门 / **Groups** 存储 | 外部系统 | 企业侧 | Dex 查询账号密码与组信息 |
| 10 | **RBAC** | **谁能操作哪个 Application / Project**（Casbin 策略） | ConfigMap `argocd-rbac-cm` | `argocd` 命名空间 | 与 AppProject **正交**，两者都要有 |
| 11 | **`bootstrap/`** | Git 仓库里的**引导目录**：放 AppProject / ApplicationSet / 根应用定义 | Git 目录 | Git 仓库 | Root Application 的 `spec.source.path` 指向它 |

---

## 1. 三个核心 CRD 的组织关系

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

### 1.1 关系表

| 从 → 到 | 关系类型 | 载体字段 | 生命周期影响 | 反向可见性 |
|---|---|---|---|---|
| AppProject → ApplicationSet | **逻辑引用**（弱） | `spec.template.spec.project` | **删 AppProject 不会**级联删除 ApplicationSet / Application | Application 的 `spec.project` 字段可见 |
| ApplicationSet → Application | **ownerReference**（强） | controller 自动写入 | **删 ApplicationSet 会**级联删除它生成的 Application | Application `metadata.ownerReferences` 指向 AppSet |
| Application → AppProject | 归属 | `spec.project` | — | Argo CD 用它做资源白名单校验 |
| Application → Repository | 引用 | `spec.source.repoURL` | — | 决定用哪份凭据拉代码 |
| Application → Cluster Secret | 引用 | `spec.destination.server` | — | 决定往哪个集群写 |

### 1.2 三个最容易踩的误解

| 误解 | 事实 |
|---|---|
| "Application 继承了 AppProject 的全部权限" | ❌ AppProject 定义**资源约束**；**谁能操作**这些 Application 由 `argocd-rbac-cm` 决定。两者独立 |
| "`AppProject → AppSet → Application` 是 owner 链" | ❌ AppProject 与 AppSet 之间**没有** ownerReference，是纯逻辑引用 |
| "ApplicationSet 模板里不写 `project`，会继承 ApplicationSet 所在项目" | ❌ **不写就是 `default` 项目**，而 `default` 默认最宽松 → 严重安全风险 |

> 完整论证见 [`05-appset.md`](./05-appset.md) §1。

---

## 2. 身份层：Dex / OIDC / LDAP

### 2.1 链路

```
[ 用户浏览器 ] ──1. 点击登录──> [ Argo CD ]
                                      │ 2. 302 重定向到 Dex 的 /auth
                                      ▼
                                 [ Dex Server ]  (OIDC Provider)
                                      │ 3. 查询用户 / 校验密码 / 读取 Groups
                                      ▼
                              [ 企业 LDAP / AD ]
                                      │ 4. 签发含 email + groups 的 ID Token
                                      ▼
                                 [ Argo CD ] ──5. 用 groups claim 查 RBAC──> UI
```

### 2.2 概念表

| 概念 | 属于哪一侧 | 作用 | 不做什么 |
|---|---|---|---|
| **OIDC** | Argo CD ↔ Dex 之间的协议 | 把"登录成功"变成一张**带 claims 的 ID Token** | 不负责验证企业密码 |
| **Dex** | 身份联合代理 | 上：暴露标准 OIDC 给 Argo CD；下：连 LDAP / GitHub / SAML 等 | 不存业务数据，**1 副本**（内存数据库） |
| **LDAP / AD** | 企业侧 | 存员工账号、密码、部门、**Groups** | 不懂 OIDC |
| **groups claim** | Token 内的一段 | 承载"用户属于哪些组"，是**组 → 角色**映射的唯一桥梁 | — |
| **RBAC (`argocd-rbac-cm`)** | Argo CD 内 | `g, <group>, role:admin` 等策略，决定谁能看/同步哪些 Application | 不约束资源类型 |

### 2.3 三个必须分开的动作（顺序不能反）

| # | 动作 | 配置位置 | 作用 |
|---|---|---|---|
| ① | 让组进 Token | 模式 A（OIDC 直连）：IdP 侧配置 + `requestedIDTokenClaims` / `enableUserInfoGroups`；模式 B（Dex+OIDC）：connector 里的 `insecureEnableGroups` + `scopes`；模式 C（Dex+LDAP）：`groupSearch` | Token 里带上 `groups` |
| ② | 组 → 角色 | `argocd-rbac-cm` 的 `policy.csv` | `devops-admin` → `role:admin` |
| ③ | 禁用内置 admin | `argocd-cm` 的 `admin.enabled: "false"` | 关闭本地 `admin` 账号 |

**先 ①② → 验证外部管理员能登录且有权限 → 再 ③。** 反过来做会把所有人锁在门外。

> 细节与 break-glass 恢复路径见 [`03-dex-ldap-sso.md`](./03-dex-ldap-sso.md)。

---

## 3. 本方案的管理拓扑

### 3.1 目标形态

```
                    ┌───────────────────────────┐
                    │   中央 Argo CD（控制面）    │
                    └─────────────┬─────────────┘
                                  │  只有一个 Root Application
                                  │  spec.source.path = bootstrap/
                                  ▼
        ┌───────────────────────────────────────────────┐
        │              bootstrap/ （Git 目录）            │
        │  appprojects/  applicationsets/  clusters/      │
        └───────────────────────────────────────────────┘
                     │                    │
        ┌────────────▼─────────┐   ┌──────▼──────────────────┐
        │  ApplicationSet × M  │   │  ApplicationSet × M     │
        │  （每个组件一个）      │   │  （每个组件一个）        │
        └────────────┬─────────┘   └──────┬──────────────────┘
                     │  组件 × 集群 = N 个 Application
      ┌──────────────┼──────────────┬───────────────┐
      ▼              ▼              ▼               ▼
 ┌─────────┐   ┌─────────┐    ┌─────────┐    ┌─────────┐
 │ dev-1   │   │ dev-2   │    │ prod-1  │    │ prod-1  │
 │ (Application) │ (Application) │ (Application) │ (Application)
 └────┬────┘   └────┬────┘    └────┬────┘    └────┬────┘
      └──────────────┴──────────────┴───────────────┘
                     │  destination.server / namespace
                     ▼
              各个目标集群（Cluster Secret 注册）
```

### 3.2 拓扑约定表

| 约定 | 含义 | 落地方式 |
|---|---|---|
| **一个中央 Argo CD** | 所有组件、所有集群的 Application 都由它生成与同步 | 控制面集群内一套 Argo CD（可 HA） |
| **一个 Root Application** | 唯一的"入口"，指向 `bootstrap/` | `spec.source.path: bootstrap`，`automated.prune + selfHeal` |
| **每个组件一个 ApplicationSet** | 组件 = 一个可独立启停、可独立同步的单元 | `applicationsets/<component>.yaml` |
| **每个集群 × 每个组件 = 一个 Application** | 矩阵展开后的每一个格子 | ApplicationSet 的 generator 自动展开 |
| **文件存在即启用该组件** | 组件的启用状态由 **Git 里有没有这个文件**决定 | Git generator 遍历目录；删文件 → AppSet 不再生成 / 被 prune |
| **新增集群 / 新增组件都不手写 Application** | 一切由 Git 文件驱动 | 改 Git → Argo CD 自动收敛 |
| **AppProject 独立裁决** | 仓库 / 目标集群 / namespace / 资源类型是否放行 | 每个 Application 的 `spec.project` 指向对应 AppProject |
| **集群 Secret 标签不参与组件选择** | 组件的取舍只由 Git 决定，cluster label **不是**组件开关 | 见下方 §3.4 |

### 3.3 组件启停的真相（文件存在即启用）

| 操作 | Git 动作 | Argo CD 反应 | 是否需要手写 Application |
|---|---|---|---|
| **启用新组件** | 新增 `bootstrap/applicationsets/<component>.yaml` + `apps/<component>/` | Root App 同步 → 新的 ApplicationSet 出现 → 生成 N 个 Application | ❌ 不需要 |
| **停用某组件** | 删除 `bootstrap/applicationsets/<component>.yaml` | AppSet 被 prune → 它生成的 Application 随之级联删除 → 集群资源被 prune | ❌ 不需要 |
| **新增目标集群** | 新增集群声明文件 + 注册 Cluster Secret | AppSet 生成多一个 Application（指向新集群） | ❌ 不需要 |
| **改组件的分支/镜像版本** | 改 ApplicationSet 模板的 `targetRevision` / values | 全部相关 Application 一起改 | ❌ 不需要 |
| **改单集群的例外** | 改该集群对应的 Application | —— | ⚠️ 手写会被 AppSet 覆盖，需走 overlay / 单独 AppSet |

> ⚠️ **停用组件的风险**：AppSet 删除会级联删除 Application，Application 消失时若
> `prune: true`，目标集群上的资源**也会被删除**。停用前确认 `syncPolicy` 与
> `prune` 的组合。

> 📄 上表的**可运行实现**见 [`examples/gitops-layout/`](./examples/gitops-layout/)：
> 「每组件一个 AppSet + 每集群一份组件启用清单 + Kustomize overlay 分环境」。

### 3.4 集群 Secret 标签的边界（重要，别误解）

| 问题 | 答案 |
|---|---|
| Cluster Secret 上的 label（如 `env=dev`）是干什么的？ | 给 **`clusters` 生成器**做 selector 过滤用："只遍历打了 `env=dev` 标签的集群" |
| 它能决定"这个集群装不装某个组件"吗？ | ❌ **不能**。标签只能筛**集群集合**，不能筛**组件集合** |
| 那组件是怎么被选中的？ | ✅ 由 **Git 里的文件 / 目录**决定（Git generator）。文件在 → 这个组件就有 Application；文件不在 → 没有 |
| 想让"某集群不装某组件"怎么办？ | 在 Git 里维护**显式的启用清单**（如 `bootstrap/clusters/<cluster>/components/<name>.yaml`，一个文件 = 一个「集群 × 组件」组合），用 **Git 文件生成器**逐个展开 |
| Cluster Secret 本身怎么来？ | 手工 `argocd cluster add`，或**声明式**把 Secret YAML 放进 Git（注意私钥入库风险） |

> 一句话：**组件维度 = Git 说了算；集群维度 = Git（或 cluster label）说了算；
> 两个维度由 ApplicationSet 的 generator 组合。**

### 3.5 生成器选型（决定"组件 × 集群"如何展开）

| 生成器 | 输入 | 输出参数 | 什么时候用 |
|---|---|---|---|
| **List** | 硬编码元素 | 任意键值 | 集群数很少、几乎不变 |
| **Git（directories）** | 仓库目录 | `.path.path` / `.path.basename` | **组件清单**：目录 = 组件 |
| **Git（files）** | 仓库文件 | 文件内容里的字段 | **集群清单**：每个文件 = 一个集群 + 其启用组件列表 |
| **Clusters** | 已注册的 Cluster Secret | `.name` / `.server` | 需要按 label 筛集群 |
| **Matrix** | 多个生成器 | 笛卡尔积 | 组件 × 集群 的全组合 |
| **Merge** | 多个生成器 | 按 `mergeKeys` 合并 | 想要"清单交集"而不是全组合 |
| **SCM Provider** | Cluster API 托管的集群 | 集群参数 | 集群由 CAPI 动态创建 |

> **全组合 vs 交集**：Matrix 是 `M × N` 全展开；Merge 可以做到"Git 清单里写了什么
> 就是什么"。集群多、组件多时优先用 Merge，避免生成一堆空 Application。
> 详见 [`05-appset.md`](./05-appset.md) §2。

---

## 4. `bootstrap/` 目录是干什么的

### 4.1 一句话

> **`bootstrap/` = Argo CD 的"引导层"目录。Root Application 只同步这一个目录，
> 而这一个目录里的内容，会催生出整套 AppProject / ApplicationSet / Application。**

### 4.2 它承担的三件事

| # | 职责 | 说明 |
|---|---|---|
| ① | **声明边界** | 放 AppProject 定义 —— 谁能从哪个仓库、同步到哪个集群/namespace、能动哪些资源类型 |
| ② | **声明生成** | 放 ApplicationSet 定义 —— 组件 × 集群 的展开规则、模板、目标版本 |
| ③ | **声明入口** | Root Application 本身（或它的等价物），`spec.source.path` 指向本目录 |

### 4.3 目录里能放什么

| 路径 / 文件 | 资源类型 | 谁读它 | 作用 | 注意事项 |
|---|---|---|---|---|
| `bootstrap/applicationsets/<component>.yaml` | ApplicationSet | Root App 同步后交给 AppSet controller | 组件的生成规则与模板 | `template.spec.project` **必须显式写** |
| `bootstrap/appprojects/<env>.yaml` | AppProject | 同上 | 资源约束边界 | 收紧 `default` 是**破坏性操作** |
| `bootstrap/root-application.yaml` | Application | Root App 同步后 Argo CD 认领 | 指向 `bootstrap/` 本身，形成自举 | ⚠️ 自引用易成环，见 §4.5 |
| `bootstrap/clusters/<cluster>/components/<name>.yaml` | **不是 K8s 资源**（自定义结构） | AppSet 的 Git 文件生成器 | 「该集群启用该组件」的清单 | ⚠️ 会被根应用当资源 apply → 必须用 `kustomization.yaml` 排除，见 §4.5 |
| `bootstrap/repositories.yaml` | Repository | Argo CD repo-server | Git 凭据（GitHub App / PAT） | 私钥建议 Sealed Secrets / SOPS |
| `bootstrap/kustomization.yaml` | Kustomize | Root App 的构建 | **限定根应用到底 apply 哪些资源** | 只列 Argo CD 资源，别把非资源清单文件列进去 |

> 📄 **可运行的完整示例**：[`examples/gitops-layout/`](./examples/gitops-layout/)
> （含 `bootstrap/` + `apps/` + 离线展开预览脚本 + 集群清单校验脚本）

> 📄 **集群清单目录的完整说明**（命名约定、多 GCP Project、多集群、
> 每集群一份独立配置、OPA / Gateway 落位、规模化演进）见
> [`examples/gitops-layout/bootstrap/clusters/README.md`](./examples/gitops-layout/bootstrap/clusters/README.md)

### 4.4 `bootstrap/` 与其它目录的分工（推荐布局）

```
gitops/
├── bootstrap/            # ← 引导层：AppProject / ApplicationSet / 集群清单 / 根应用
│   ├── appprojects/
│   ├── applicationsets/
│   └── clusters/
├── apps/                 # ← 组件本体：每个组件一个目录（kustomize / helm）
│   ├── nginx/
│   └── api/
├── environments/         # ← 环境差异：values / overlay
│   ├── dev/
│   └── prod/
└── shared/               # ← 公共 base
```

| 目录 | 放什么 | 谁改 |
|---|---|---|
| `bootstrap/` | 元数据层（"要什么"） | 平台团队 |
| `apps/` | 组件本体（"怎么做"） | 组件 owner |
| `environments/` | 环境差异（"在哪做"） | 平台 + 组件 owner |

**原则：定义与环境分离。** 组件定义只写一份，环境差异用 overlay，
不复制粘贴 N 份 YAML。

### 4.5 `bootstrap/` 的已知坑

| 坑 | 表现 | 处理 |
|---|---|---|
| **同步顺序** | Root App 同步完，生成的子 Application 状态还是 `OutOfSync` | 正常：Root App **不级联等待**子应用健康，子 App 自己会同步 |
| **循环依赖** | Root App 管子 App，子 App 又回头管 Argo CD 自身 | 确保“管理 Argo CD 自身的那个 Application”**不在** Root App 管理范围内 |
| **prune 误删** | 删掉一个 ApplicationSet 文件 → 它生成的 Application 全部消失 → 集群资源被 prune | 模板里开 `preserveResourcesOnDeletion: true`；停用组件前先确认影响面 |
| **混入非资源文件** | `bootstrap/` 里有集群清单等**非 K8s 资源**的 YAML → 目录源递归扫描后报错 `failed to generate manifest for source` | 用 `bootstrap/kustomization.yaml` 显式列出要 apply 的资源（参考示例） |
| **boolean 不能模板化** | `syncPolicy.automated.prune: '{{.prune}}'` 会被 API server 拒掉（CRD 里这两个字段是 `boolean`） | 不做按环境差异化；prod 要人工审批就**拆一个 prod 专用 ApplicationSet**（用 `selector: 'env == "prod"'` 过滤） |
| **项目不存在** | 根应用引用的 AppProject 还没创建 → 首次同步报 `project not found` | 先 apply AppProject，再 apply 根应用 |
| **集群清单手抄漂移** | `clusters/<c>/components/*.yaml` 里 server/env/project 抄错 → 同步被拒或静默渲染到错的环境 | 提交前跑 `examples/gitops-layout/validate-clusters.py`（校验字段、与 `cluster.yaml` 一致性、destinations 覆盖、渲染路径存在） |
| **集群层 overlay 循环引用** | `overlays/<env>/<cluster>/` 里 `resources: [..]` → Kustomize 报 `cycle detected` | 用兄弟目录：`overlays/env/<env>/` + `overlays/cluster/<cluster>/` |

---

## 5. 一次变更的完整链路

| 步骤 | 谁发起 | Git 动作 | Argo CD 内部发生了什么 | 用户可见结果 |
|---|---|---|---|---|
| 1 | 开发者 | PR 改 `apps/nginx/values.yaml` | Root App 检出 → 生成的 Application 检测到 diff → OutOfSync | UI 上该 Application 变黄 |
| 2 | Argo CD | — | auto-sync 触发 → 拉取 → diff → apply 到目标集群 | 集群资源更新 |
| 3 | 开发者 | PR 合并到 `main` | webhook 通知 repo-server → 立即重算 | 秒级收敛 |
| 4 | 开发者 | 新增 `apps/redis/` 目录 | Git generator 枚举到新目录 → 生成新 Application → 自动同步 | 集群上出现 Redis |
| 5 | 平台 | 新增集群文件 + 注册 Cluster Secret | generator 多产出一个参数集 → 新 Application 指向新集群 | 新集群被纳管 |

---

## 6. 速查：概念 → 权限归属

| 问题 | 答案 | 配置在哪 |
|---|---|---|
| 谁能点"同步"这个 Application？ | Argo CD RBAC | `argocd-rbac-cm` → `policy.csv` |
| 这个 Application 允许从哪个仓库拉？ | AppProject | `AppProject.spec.sourceRepos` |
| 允许同步到哪个集群 / namespace？ | AppProject | `AppProject.spec.destinations` |
| 允许创建哪些资源类型？ | AppProject | `clusterResourceWhitelist` / `namespaceResourceWhitelist` |
| 这个 Application 属于哪个项目？ | Application 自己的字段 | `Application.spec.project` |
| Argo CD 本身写集群的权限有多大？ | K8s RBAC / ServiceAccount | 集群内 Argo CD 的 SA 绑定 |
| 组件要不要装？ | **Git 文件** | `bootstrap/` 里的文件在不在 |
| 这个集群要不要装某些组件？ | **Git 清单**（或 cluster label 筛集群） | `bootstrap/clusters/*.yaml` |
| 谁能登录？ | Dex + OIDC + LDAP | `argocd-cm` → `dex.config` |
| 登录后属于什么角色？ | RBAC + groups claim | `argocd-rbac-cm` + `dex.config.scopes` |

---

## 7. 关联文档

| 想了解 | 看 |
|---|---|
| AppProject 字段细节 / 三层权限模型 | [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| ApplicationSet 生成器全表 / 模板写法 | [`05-appset.md`](./05-appset.md) |
| Dex 配置 / LDAP 组 / 禁用 admin | [`03-dex-ldap-sso.md`](./03-dex-ldap-sso.md) |
| ApplicationSet vs Application 对比 | [`../argocd-applicationset-vs-application.md`](../argocd-applicationset-vs-application.md) |
| Application 字段详解 | [`../argocd-application-guide.md`](../argocd-application-guide.md) |
| App of Apps / bootstrap 目录（管理员手册原文） | [`../argocd-admin-guide.md`](../argocd-admin-guide.md) §6.1–6.2 |
| 可复制的 AppProject / ApplicationSet 示例 | [`examples/`](./examples/) |
| **完整 GitOps 仓库骨架（bootstrap + apps + 集群清单 + 展开预览）** | [`examples/gitops-layout/`](./examples/gitops-layout/) |
