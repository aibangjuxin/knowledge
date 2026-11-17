# Argo CD：`ApplicationSet` vs `Application` 对比

> 一句话结论：**`Application` 是"同步一件东西"的工单，`ApplicationSet` 是"批量生产工单"的模板机。**
> 真正往集群里 apply 资源的，永远是 `Application`；`ApplicationSet` 自己不同步任何东西。
>
> 版本基准：Argo CD **v3.5.6**（与本目录 `install.yaml` 一致）
> 配套阅读：`argocd-application-guide.md`（`Application` 字段详解）、
> `argocd-topics/05-appset.md`（`ApplicationSet` 批量分发实战）

---

## 1. 各自是什么

### `Application`（`argoproj.io/v1alpha1`）

Argo CD 的核心 CRD。一张**工单**：从哪个仓库的哪个路径取清单、同步到哪个集群的哪个
namespace、是否自动同步。它本身不含执行逻辑，是 `argocd-application-controller`
watch 的对象——controller 读 Git、算 diff、执行 apply/prune，把结果写回 `status`。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: team-a-api
  namespace: argocd
spec:
  project: team-a
  source:
    repoURL: https://github.com/example/platform.git
    targetRevision: main
    path: apps/api
  destination:
    server: https://kubernetes.default.svc
    namespace: team-a
```

### `ApplicationSet`（`argoproj.io/v1alpha1`）

Argo CD 的**元控制器 CRD**。它包含两部分：

1. **generators**（生成器）：告诉你"要生成哪些"——可以是 Git 仓库目录、已注册集群列表、
   静态元素列表、多个生成器的笛卡尔积（matrix）等。
2. **template**（模板）：一个 `Application` 的模板骨架，用 `{{.xxx}}` 占位符。

`argocd-applicationset-controller`（本仓库 `install.yaml:30899` 起）持续比对生成器
的输出与现有 `Application`，**新增/更新/删除**生成的 `Application`。生成的 Application
带 ownerReference，指向所属的 ApplicationSet。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform-apps
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/example/platform.git
      revision: main
      directories:
      - path: apps/*        # apps/api、apps/web → 两个 Application
  template:
    metadata:
      name: '{{.path.basename}}'
    spec:
      project: team-a      # ← 必须显式写
      source:
        repoURL: https://github.com/example/platform.git
        targetRevision: main
        path: '{{.path.path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: team-a
```

---

## 2. 关系图

```
┌──────────────────────────┐
│ AppProject（边界）        │  定义"能操作哪些源/目标/资源类型"
└─────────────┬────────────┘
              │ template.spec.project（逻辑引用，非 owner）
              ▼
┌──────────────────────────┐
│ ApplicationSet（元控制器）  │  generators（生成什么）+ template（怎么生成）
└─────────────┬────────────┘
              │ ownerReference（父 → 子）
              ▼
┌──────────────────────────┐
│ Application × N（工单）    │  真正被 application-controller 执行同步
└─────────────┬────────────┘
              ▼
        目标集群的资源
```

- `AppProject → ApplicationSet`：**逻辑引用**。删 AppProject 不会级联删 ApplicationSet
  及其产物（除非 ApplicationSet 本身被删）。
- `ApplicationSet → Application`：**ownerReference**。删 ApplicationSet → 删它生成的
  Application → 若 Application 上有 finalizer `resources-finalizer.argocd.argoproj.io`，
  还会**级联删除目标集群里的资源**。生产环境删除前务必确认
  `preserveResourcesOnDeletion: true`。
- `Application` 也可以**完全独立于** ApplicationSet 手工创建，两者不是必须成对出现。

---

## 3. 逐项对比

| 维度 | `Application` | `ApplicationSet` |
|---|---|---|
| **定位** | 同步单元（工单） | 元控制器（工单工厂） |
| **谁消费它** | `argocd-application-controller` | `argocd-applicationset-controller` |
| **自己会同步资源吗** | ✅ 会（apply/prune 到目标集群） | ❌ 不会，只生成/维护 `Application` |
| **典型数量** | 一个应用 × 一个环境 × 一个集群 = 1 个 | 1 个 → 生成 N 个 |
| **里面的"源"字段名** | `spec.source`（含 repoURL / path / targetRevision） | `spec.generators`（输入）+ `spec.template`（里面的 `template.spec.source`） |
| **分支/版本写在哪** | `spec.source.targetRevision` | `spec.template.spec.source.targetRevision`（批量改只改这一处） |
| **模板渲染** | 无 | `{{.xxx}}`；推荐 `goTemplate: true` + `goTemplateOptions: ["missingkey=error"]` |
| **status 含义** | 同步状态（OutOfSync/Synced）、健康度、资源树 | 生成结果状态（`resources` 列表、生成数量、报错信息） |
| **删除行为** | 删 Application（带 finalizer）→ 删目标集群资源 | 删 AppSet → 删所有生成的 Application（→ 可能删集群资源） |
| **权限要求** | 可按项目/团队授权给普通用户 | **上游建议仅管理员**可创建/修改/删除 |
| **典型用途** | 单个应用手动管理 | 一次管理 N 个"应用 × 环境 × 集群" |

### 一句话对照记忆

| | `Application` | `ApplicationSet` |
|---|---|---|
| 比喻 | **工单** | **工单模板 + 批量下发器** |
| 变一个分支要改几处 | 这一个 Application | 模板一处，所有产物跟着变 |
| 产出 | 集群里的资源 | `Application` 对象 |

---

## 4. 什么时候用哪个

| 场景 | 选择 |
|---|---|
| 只有 1–2 个应用，环境固定不变 | 直接用 `Application`（更简单，无需多一个控制器参与） |
| 同一套应用要发到 dev/staging/prod 多个环境 | ✅ `ApplicationSet`（List/Matrix 生成器） |
| 同一套应用要发到多个集群 | ✅ `ApplicationSet`（Cluster 生成器 + `matchLabels` 过滤） |
| Git 里加一个目录就自动多一个应用 | ✅ `ApplicationSet`（Git 生成器 + `directories`） |
| 每个 PR 一个预览环境 | ✅ `ApplicationSet`（Pull Request 生成器） |
| 只需要改一个应用的分支/路径 | 改 `Application`（或改 AppSet 模板，二选一别两边都改） |

> ⚠️ 常见反模式：一个环境只有一个应用也硬上 ApplicationSet。除非你需要"改模板批量生效"
> 的收益，否则多一层生成器就多一层排障成本。

---

## 5. 生命周期差异（最容易踩的地方）

| 操作 | 直接创建的 `Application` | `ApplicationSet` 生成的 `Application` |
|---|---|---|
| 改 Git 里的清单 | 自动同步（若开 `automated`） | 自动同步 |
| 改分支 | 要改每个 Application | 改模板一处，全部生效 |
| 删掉 Git 里的目录 | 资源被 prune（若 `prune: true`） | Git 生成器不再产出该目录 → Application 被删 → 资源可能级联删除 ⚠️ |
| 删 ApplicationSet | — | 所有产物一起消失 ⚠️⚠️ |
| 手改生成的 Application | 会被 AppSet 下一次 reconcile **覆盖回去** | 改了也留不住 |

> 结论：**不要手改 ApplicationSet 生成的 Application**，它是"派生产物"，
> 一切变更走模板或生成器数据源（Git）。

安全建议（与 `argocd-topics/05-appset.md` 一致）：

1. `template.spec.project` **必须显式写**。不写就是 `default` 项目，而 `default` 默认
   允许任意源、任意目标、任意资源类型——这是重大安全风险。
2. 只允许管理员操作 ApplicationSet（K8s RBAC + Argo CD `policy.csv`）。
3. 模板化 `project` 时，必须控制好生成器的所有数据源（Git 写权限、集群 label 修改权限）。
4. 删除前确认 `preserveResourcesOnDeletion: true`。

---

## 6. 速查命令

```bash
# 看 ApplicationSet 本身
kubectl -n argocd get applicationset
kubectl -n argocd describe applicationset platform-apps

# 看某个 AppSet 生成了哪些 Application
kubectl -n argocd get applications -l argocd.argoproj.io/application-set-name=platform-apps

# 关键安全检查：有没有产物落到最宽松的 default 项目（应该为空）
kubectl -n argocd get applications -o jsonpath='{range .items[?(@.spec.project=="default")]}{.metadata.name}{"\n"}{end}'

# 检查渲染结果是否为空字符串（模板变量写错时的典型症状）
kubectl -n argocd get application api -o jsonpath='{.spec.source.path}{"\n"}'

# CLI
argocd appset list
argocd appset get platform-apps
```

---

## 7. 常见误解

| 误解 | 事实 |
|---|---|
| "ApplicationSet 会直接把资源 apply 到集群" | ❌ 它只生成 `Application`，同步由 application-controller 执行 |
| "有了 ApplicationSet 就不需要 Application 了" | ❌ ApplicationSet 的产物**就是** Application，删掉 AppSet 产物也没了 |
| "Application 继承 AppProject 的全部权限" | ❌ AppProject 定义**资源约束**；**谁能操作**这些 Application 由 Argo CD RBAC 决定 |
| "AppSet → Application 是级联删除链" | ✅ 是的（ownerReference）；而 AppProject → AppSet **不是** |
| "生成的 Application 我可以手改" | ❌ 会被 reconcile 覆盖 |
| "改分支要改 N 个 Application" | ✅ 手写的话要改 N 个；用 AppSet 只改模板一处 |

---

## 8. 关联文档

| 主题 | 文档 |
|---|---|
| `Application` 字段逐个解释、创建方式、坑位 | [`argocd-application-guide.md`](./argocd-application-guide.md) |
| ApplicationSet 批量分发实战：生成器选型、Matrix/Merge、安全约束 | [`argocd-topics/05-appset.md`](./argocd-topics/05-appset.md) |
| AppProject / RBAC 三层权限模型 | [`argocd-topics/04-appproject-rbac.md`](./argocd-topics/04-appproject-rbac.md) |
| 可复制的 ApplicationSet 示例 | [`argocd-topics/examples/applicationset-matrix.yaml`](./argocd-topics/examples/applicationset-matrix.yaml) · [`examples/argocd-application/`](./examples/argocd-application/) |
| ApplicationSet 相关排障 | [`argocd-topics/09-troubleshooting.md`](./argocd-topics/09-troubleshooting.md) |
