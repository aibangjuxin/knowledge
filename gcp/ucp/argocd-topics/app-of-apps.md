# App of Apps（应用套应用）· Argo CD 的「批量下发」模式

> **本文回答**
> 1. **App of Apps 是个什么东西？**（一句话 + 一张图）
> 2. **它解决什么问题？**（GitOps 的"先有鸡还是先有蛋"死循环）
> 3. **它到底能实现什么？**（四个具体能力）
> 4. **它和 ApplicationSet 什么关系？**（官方推荐哪个）
> 5. **怎么落地？**（官方 Helm 模板法 + 一份真实产品案例）
> 6. **有哪些坑？**（权限、级联删除、diff 噪音）
>
> **资料来源**
> - Argo CD 官方文档 · Cluster Bootstrapping（`App Of Apps Pattern (Alternative)` 一节）
>   <https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/>
> - Imperva / Thales 官方文档 · *Use the App-of-Apps Pattern with Argo CD*（Elastic WAF 2.1.1+）
>   <https://docs-cybersec.thalesgroup.com/bundle/elastic-waf/page/argo-apps.htm>
>
> **版本基线**：本仓库 `install.yaml` 为 Argo CD **v3.5.6**；
> 官方文档中"删除子应用行为一致化"是 **v3.2+** 的能力。

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-一句话) | 一句话定义 + 全景图 |
| [§1](#1-它解决什么问题gitops-的先有鸡还是先有蛋) | 死循环问题 |
| [§2](#2-它到底能实现什么) | 四个具体能力 |
| [§3](#3-工作原理两层同步) | 两层同步链路 + 时序 |
| [§4](#4-官方推荐applicationset-还是-app-of-apps) | 两者对比与选型 |
| [§5](#5-官方实现helm-模板化子应用) | 官方最小实现（Helm） |
| [§6](#6-真实案例elastic-waf-的-app-of-apps) | Imperva Elastic WAF 案例 |
| [§7](#7-踩坑清单) | 权限 / 级联删除 / diff 噪音 / 自举 |
| [§8](#8-在我们仓库里它长什么样) | 与 `bootstrap/` 的对应关系 |
| [§9](#9-要点速查) | 一页速查表 |
| [§10](#10-关联文档) | 关联文档 + 官方链接 |

---

## 0. 一句话

```
App of Apps = 让「一个 Argo CD Application」去管理「一批别的 Application」。

父应用（Root App）本身不部署任何业务资源，它只负责把子 Application 的
定义从 Git 里"种"到集群里；子应用再各自去同步自己那部分工作负载。
```

**它是什么**：一种 **GitOps 编排模式**，不是 Argo CD 的新 CRD、不需要装任何插件。
实现它的东西就是普通的 `Application` CRD —— 父应用的 `spec.source.path`
指向一个目录，那个目录里装的全是被渲染出来的 `Application` YAML。

**它不是什么**：

| 它不是 | 说明 |
|---|---|
| 不是新组件 | 不需要 `helm install` 任何 chart，Argo CD 自带 |
| 不是新 API | 就是 `Application` 的 `kind` 换了个用法 |
| 不是"应用编排引擎" | 它不管依赖顺序（除非靠 Argo CD 的 health/waves 间接实现），不管数据流 |
| 不是 ApplicationSet 的替代品 | 它俩是**平级**的两种批量方案，官方把 App of Apps 列为 *Alternative* |

**全景图**：

```
┌───────────────────────────────────────────────────────────┐
│  Git 仓库                                                  │
│                                                            │
│   bootstrap/                                               │
│    ├── root-app.yaml        ← 父应用（自己也是一个 App）     │
│    ├── child-a.yaml         ← 子应用定义（Application CR）   │
│    ├── child-b.yaml         ← 子应用定义                    │
│    └── child-c.yaml         ← 子应用定义                    │
└───────────────┬───────────────────────────────────────────┘
                │  父应用同步（apply）
                ▼
┌───────────────────────────────────────────────────────────┐
│  Argo CD 控制面                                             │
│                                                            │
│   ┌────────────────┐                                       │
│   │ Parent App     │  ← 同步完 → 状态 InSync               │
│   └───────┬────────┘                                       │
│           │ 制造出                                         │
│           ▼                                                │
│   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐     │
│   │ Child App A  │ │ Child App B  │ │ Child App C  │     │
│   │  (OutOfSync) │ │  (OutOfSync) │ │  (OutOfSync) │     │
│   └──────┬───────┘ └──────┬───────┘ └──────┬───────┘     │
└──────────┼───────────────┼─────────────────┼──────────────┘
           │ 各自同步       │                 │
           ▼               ▼                 ▼
      ┌─────────┐     ┌─────────┐       ┌─────────┐
      │ 工作负载 │     │ 工作负载 │       │ 工作负载 │
      │ Deployment/…    │ …       │       │ …       │
      └──────────────────────────────┘
```

---

## 1. 它解决什么问题（GitOps 的"先有鸡还是先有蛋"）

Argo CD 的工作模型是"**Application 的定义必须先在集群里存在，Argo CD 才会去同步它指向的东西**"。
于是有一个天然的死循环：

```
❌ 想装应用 A
   → A 的 Application 定义在 Git 里
      → 但没人告诉 Argo CD 去读这个 Git
         → 需要一个 Application 来指向这个 Git
            → 而这个 Application 的定义……也在 Git 里
               → 🔁 回到起点
```

**App of Apps 就是打破这个循环的那一层**：

```
✅ 手动点火一次（第一次，也是唯一一次）
   kubectl apply -f root-app.yaml     ← 或 argocd app create + argocd app sync
      ↓
   父应用开始同步 bootstrap/ 目录
      ↓
   把子 Application 的定义 apply 到集群 → 鸡有了
      ↓
   子应用各自同步自己的工作负载 → 蛋有了
      ↓
   此后完全自举，不需要人再管
```

官方文档对这件事的原话是"**There's no one particular pattern to solve this problem**"
—— 写脚本批量 `argocd app create`、或者手工点，都能解决。
App of Apps 只是其中**声明式、可版本化、可审计**的一种。

---

## 2. 它到底能实现什么

这是本文的核心问题。展开成四条具体能力：

### 能力 ①：一次同步，铺开一整套应用

父应用一个目录 → 一次 sync → N 个子 Application 全部出现。

- 你在 Git 里新增一个 `child-d.yaml` 并合并 → 父应用自动同步 → `child-d` 出现
- 你在 Git 里删除 `child-d.yaml` → 父应用同步（`prune: true`）→ `child-d` 及其工作负载被清理

**场景**：一个新集群要装 10 个东西（ingress、网关、监控、证书、数据库…），
一次提交全部搞定，而不是 `for` 循环调 10 次 `argocd app create`。

### 能力 ②：把"环境 × 组件"的矩阵变成文件树

子应用的数量可以任意组合，环境维度用**目录**表达，组件维度用**文件名**表达。

```
appofapp/
├── ewaf.yaml            ← 根应用：管理 ewaf/* 下的所有环境
├── nginx.yaml           ← 根应用：管理 ingress/* 下的所有环境
└── webapp.yaml
ewaf/
├── dev-ewaf.yaml
├── stage-ewaf.yaml
└── prod-ewaf.yaml
ingress/
├── dev-nginx.yaml
├── stage-nginx.yaml
└── prod-nginx.yaml
```

> 上面这套目录结构直接来自 Imperva 官方文档（§6），不是我编的。

**你得到的东西**：加环境 = 加一个 YAML 文件；停用某环境 = 删一个 YAML 文件。
全部走 Git，不需要碰 Argo CD UI。

### 能力 ③：让不同环境走不同的同步策略

因为**每个子应用是独立的 CR**，它可以有自己的 `syncPolicy`：

| 环境 | auto-sync | 理由（来自 Elastic WAF 官方建议） |
|---|---|---|
| Dev | ✅ 开启 | 快速迭代 |
| Stage | ❌ 关闭 | 手工同步，可控测试 |
| Prod | ❌ 关闭 | 只手工同步，需校验与审批 |

父应用可以统一开 auto-sync（负责"把子应用创建出来"），
而子应用各自决定"是否自动同步业务资源" —— **两层策略解耦**。

### 能力 ④：把版本晋级（promotion）变成 Git 操作

因为子应用里的 `targetRevision` 就是 Git 的分支/tag/commit：

```bash
# dev 验证通过后，把同一个版本晋级到 stage
git checkout stage && git merge dev && git push origin stage

# prod 上线后打 tag，留痕可追溯
git tag release-ewaf-v2.3.0 && git push origin release-ewaf-v2.3.0
```

Dev → Stage → Prod 的推进 = Git 分支合并，不是"复制粘贴一遍 YAML 然后改版本号"。

---

## 3. 工作原理：两层同步

理解 App of Apps 只有一条链：**父应用同步的是"Application 的 YAML"，不是业务资源。**

```
① 父应用 sync
   读 Git → 渲染 manifest → 对比集群现状 → apply
   集群里多出来的是 Application CR（子应用）
   ↓
② 子应用（Argo CD 的 application-controller 独立处理）
   各自读自己的 source → 渲染业务 manifest → sync 到 destination 集群
```

### 关键细节：父应用 InSync ≠ 一切就绪

官方文档明确指出：

> The parent app will appear as in-sync but the child apps will be out of sync.

原因很直白：父应用只负责"创建子应用"，子应用刚被创建时还没同步过业务资源，
所以它们是 `OutOfSync`。**首次铺开时需要再触发一次子应用的同步**：

```bash
# 按标签批量同步子应用
argocd app sync -l app.kubernetes.io/instance=apps
```

UI 里则是：按 `app.kubernetes.io/instance` 标签过滤 → 全选 OutOfSync → Sync。

> 💡 想"分波次"铺开（先基础设施、再业务），用 Argo CD 的 **health assessment / sync waves**，
> 见官方文档 *health assessment of Applications*。

---

## 4. 官方推荐：ApplicationSet 还是 App of Apps？

官方 **Cluster Bootstrapping** 文档的结构很明确：

```
Cluster Bootstrapping
├── Application Sets and cluster labels (recommended)   ← 首选
└── App Of Apps Pattern (Alternative)                  ← 备选
```

### 两者对比

| 维度 | ApplicationSet（官方推荐） | App of Apps |
|---|---|---|
| **本质** | 一个 CRD 负责**生成** Application | 父 Application 负责**生成** Application |
| **子应用数量怎么定** | 由 **generator** 算出（cluster / git / list / matrix …） | 由 **Git 里的文件数**决定 |
| **多环境多集群** | 一条 matrix generator 展开 | 每个格子手写一个 YAML |
| **模板能力** | `goTemplate` + Sprig（**不需要 Helm**） | 取决于你用什么渲染（Helm / Kustomize / 裸 YAML） |
| **新增一个环境** | 改 cluster secret 标签 | 加一个 YAML 文件 |
| **权限边界** | 生成的 Application 受 AppProject 约束 | ⚠️ **父应用源仓库的 push 权限 = admin 权限** |
| **删除的级联性** | AppSet 被删 → 生成的 Application 级联删除 | 父应用被删 → 子应用是否级联删除**取决于 finalizer** |

### 怎么选（官方文档的建议 + 我的归纳）

```
❓ 你的子应用集合能靠"标签 / 目录 / 列表"算出来？
   ├─ 能  → ✅ 用 ApplicationSet（官方推荐）
   │         没有模板引擎依赖，天然支持"删文件即停用"
   └─ 不能（每个子应用的 source/结构差异大、需要 Helm 渲染出复杂 YAML）
          → ✅ 用 App of Apps
```

**官方选型原话（应用集那节）**：
> We recommend to look at ApplicationSets and more specifically the cluster generator
> which can handle most typical scenarios.

**但是** —— 两种模式在本仓库是**可以叠加**的：
父应用指向 `bootstrap/`，`bootstrap/` 里同时放 AppSet 定义和少量手写 Application，
这正是 [`examples/gitops-layout/bootstrap/`](./examples/gitops-layout/bootstrap/) 的做法。

---

## 5. 官方实现：Helm 模板化子应用

Argo CD 官方给的最小实现用 **Helm**（因为子应用的 YAML 需要参数化，比如目标集群地址）。

### 5.1 仓库结构

```
├── Chart.yaml              # 样板
├── templates
│   ├── guestbook.yaml      # 子应用 1
│   ├── helm-dependency.yaml
│   ├── helm-guestbook.yaml
│   └── kustomize-guestbook.yaml
└── values.yaml             # 默认参数
```

### 5.2 `templates/guestbook.yaml` —— 子应用长这样

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io     # ⭐ 级联删除的开关
spec:
  destination:
    namespace: argocd
    server: {{ .Values.spec.destination.server }}   # ⭐ 由 values 参数化
  project: default
  source:
    path: guestbook
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
  syncPolicy:
    automated:
      prune: true
```

> 💡 `finalizers: resources-finalizer.argocd.argoproj.io` ——
> **没有它，父应用被删时子应用不会跟着删**（也就不会删掉集群里的业务资源）。
> 这是一个很容易漏、漏了就出事的一行。详见 §7.2。

### 5.3 `values.yaml` —— 参数化目标集群

```yaml
spec:
  destination:
    server: https://kubernetes.default.svc
```

同一份模板，靠 values 渲染出"部署到不同集群"的子应用。

### 5.4 `targetRevision` 的三种写法与语义

| 写法 | 行为 | 什么时候用 |
|---|---|---|
| 固定 commit SHA | 子应用**只**在这个 SHA 变时才更新 | 生产、要求可复现 |
| 分支名（如 `main`） | 分支一动，所有子应用就动 | 开发环境 |
| `HEAD` | 同分支，且跟随默认分支 | 不推荐（漂移） |

官方建议：
> Fix the revision to a specific Git commit SHA to make sure that, even if the child apps
> repo changes, the app will only change when the parent app change that revision.

### 5.5 点火

```bash
argocd app create apps \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/argoproj/argocd-example-apps.git \
    --path apps
argocd app sync apps
```

---

## 6. 真实案例：Elastic WAF 的 App of Apps

> 来源：Imperva / Thales 官方文档 *Use the App-of-Apps Pattern with Argo CD*
> （Elastic WAF 2.1.1 及以后）。这是一个**厂商给出推荐结构**的例子，
> 说明 App of Apps 不只是玩具，它在真实产品交付里长什么样。

### 6.1 它在做什么

```
根应用 root-ewaf
├── ewaf-dev    → Helm chart imperva-stack 2.1.1 + values_dev.yaml
├── ewaf-stage  → 同一 chart + values_stage.yaml
├── ewaf-prod   → 同一 chart + values_prod.yaml
```

关键点：**同一个 Helm chart，三套 values，跨三个集群**，
而且**values 文件和 Application 定义在同一个 Git 仓库的不同目录**：

```yaml
sources:
- repoURL: https://<internal-helm-repo>
  targetRevision: 2.1.1          # ⭐ chart 版本在这里固定
  chart: imperva-stack
  helm:
    releaseName: ewaf
    valueFiles:
      - $values/values/ewaf/values_dev.yaml    # ⭐ 引用第二个 repo 的文件
- repoURL: https://github.com/<org>/argocd_env.git
  targetRevision: main
  ref: values                    # ⭐ 第二个 source 纯粹用来传 values
```

> 这里用了 **多源 Application（`sources`）**：`$values` 是个特殊 ref，
> 指向另一个 source 的目录，用来把 values 文件喂给 Helm。
> 详见 [`helm-cross-repository.md`](./helm-cross-repository.md)。

### 6.2 部署顺序（有依赖关系时怎么办）

Imperva 给出的新环境上线顺序：

```
① Webapp    先装业务应用和后端服务
② Ingress   再装 ingress controller（比如 NGINX）
③ Elastic WAF 最后装，负责在前面插入安全与策略层
```

并且**明确要求把 ingress controller 的 auto-sync 关掉**：

> Elastic WAF may modify ingress-related manifests, and auto-syncing ingress could
> overwrite those changes.

也就是：**两个控制器抢同一份资源，后写的赢**。这种冲突 App of Apps 解决不了，
只能靠"关掉 auto-sync + 手工同步"绕开。**这是它的真实局限。**

### 6.3 升级流程：分阶段晋级

```
Dev   → 改 dev-ewaf.yaml 的 targetRevision → 跑回归 + 集成测试
Stage → Dev 通过后，把同一版本晋级到 stage（合并分支或改配置）
Prod  → Stage 稳定后晋级到 prod → 打 tag（如 release-ewaf-v2.3.0）留痕
```

这就是 §2 能力 ④ 的实例化。

### 6.4 它的最佳实践清单

| # | 实践 | 说明 |
|---|---|---|
| 1 | 所有 Argo CD manifest 放**同一个仓库**版本控制 | 单一事实来源 |
| 2 | 每个环境用**独立的 values 文件**（`values/<component>/values_<env>.yaml`） | 环境差异只落在 values，不落在 Application 定义 |
| 3 | **关闭** ingress controller 的 auto-sync | 避免与 EWAF 互相覆盖 |
| 4 | **关闭** stage / prod 的 auto-sync | 手工审批 |
| 5 | 新 chart 版本**必须先在 Dev 验证** | 再晋级 |
| 6 | 用 **branch / tag** 表示环境状态 | `main` / `stage` / `prod` |

### 6.5 常用命令

```bash
argocd app sync <app-name>          # 手工同步
argocd app get  <app-name>          # 看状态
git checkout stage && git merge dev && git push origin stage   # 版本晋级
kubectl get pods -n <TARGET_NAMESPACE>                        # 确认 Pod Ready
```

---

## 7. 踩坑清单

### 7.1 ⚠️ 权限：App of Apps 是 admin-only 工具

这是官方文档用 **WARNING** 框标出来的一条，措辞很重：

> **App of Apps is an admin-only tool**
>
> The ability to create Applications in arbitrary Projects is an admin-level capability.
> Only admins should have push access to the parent Application's source repository.
> Admins should review pull requests to that repository, paying particular attention to the
> `project` field in each Application. Projects with access to the namespace in which Argo CD
> is installed effectively have admin-level privileges.

翻译成能落地的检查项：

| 检查项 | 为什么 |
|---|---|
| 父应用的源仓库**只允许 admin push** | 谁能往里加一个 `Application` YAML，谁就能在任意 Project 下创建 Application |
| 审 PR 时**重点看每个子应用的 `spec.project`** | `project: default` 和 `project: prod` 的权限完全不同 |
| 注意"能访问 Argo CD 所在 namespace 的 Project" | 这类 Project **实质上拥有 admin 权限** |
| 别把父应用仓库开放给租户自助提交 | 租户可以借此越权创建 Application |

**和 ApplicationSet 的对比**：ApplicationSet 的生成规则受 AppProject 约束；
App of Apps 的子应用 `project` 字段是**字面量**，写在 YAML 里，绕过 AppSet 模板的收敛。

### 7.2 ⚠️ 级联删除：finalizer 决定一切

```yaml
metadata:
  finalizers:
  - resources-finalizer.argocd.argoproj.io
```

| 组合 | 删父应用时发生什么 |
|---|---|
| 子应用**有** finalizer | 子应用被删 → 子应用管理的集群资源也被删（**级联清理**） |
| 子应用**没有** finalizer | 子应用留下 → 集群里的业务资源留下（**孤儿**） |

**这是双刃剑**：

- 想要"父应用删了，集群里干干净净" → 加 finalizer
- 想"父应用删了，集群资源先留着" → 不加 finalizer，或者父应用上设
  `preserveResourcesOnDeletion: true`（本仓库 `bootstrap/root-application.yaml` 就是这么做的）

### 7.3 diff 噪音：子应用老显示 OutOfSync

Argo CD 会往子应用的 metadata 上写 `argocd.argoproj.io/refresh` 注解、
也会改 `spec.operation`，这些都会让父应用看到 diff。官方给的解法：

```yaml
spec:
  syncPolicy:
    syncOptions:
    - RespectIgnoreDifferences=true
  ignoreDifferences:
  - group: "*"
    kind: "Application"
    jsonPointers:
    - /spec/syncPolicy/automated          # 允许手工关掉子应用的 auto-sync
    - /metadata/annotations/argocd.argoproj.io~1refresh
    - /operation
```

用途：调试时手工改子应用的 auto-sync，不让父应用把它判成"漂移"。

### 7.4 删除子应用的行为（v3.2+）

Argo CD **v3.2 起**，从 Applications 列表删、或从父应用的 Resource Tree 删，
行为已经一致化，并支持**非级联（orphan）删除**来保留被管理的资源。
细节见官方文档 *Deleting Applications in the UI*。

### 7.5 它解决不了的事

| 问题 | 为什么 |
|---|---|
| **依赖顺序** | App of Apps 不理解"A 依赖 B"。要么靠 health/waves 间接做，要么手工分批 sync |
| **两个控制器抢同一份资源** | 只会"后写的赢"（§6.2 的 ingress vs EWAF） |
| **海量子应用的可读性** | 50 个集群 × 10 个组件 = 500 个 YAML，靠人写不现实 → 这正是 ApplicationSet 的战场 |
| **权限收敛** | 子应用的 `project` 是字面量，不像 AppSet 那样被模板收敛 |

---

## 8. 在我们仓库里它长什么样

本仓库 [`examples/gitops-layout/bootstrap/`](./examples/gitops-layout/bootstrap/) 用的就是
**App of Apps + ApplicationSet 混合**：

```yaml
# bootstrap/root-application.yaml（节选）
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-bootstrap
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/example/platform.git
    targetRevision: main
    path: bootstrap                 # ⭐ 父应用只同步这一个目录
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
  preserveResourcesOnDeletion: true  # ⭐ 根应用被删时不连带删 AppProject/AppSet
```

对应关系：

| App of Apps 概念 | 本仓库的实现 |
|---|---|
| 父应用（Root App） | `bootstrap/root-application.yaml` |
| 子应用定义 | `bootstrap/applicationsets/*.yaml`（用 AppSet 代替手写 N 个 Application） |
| 边界定义 | `bootstrap/appprojects/*.yaml` |
| `bootstrap/clusters/` | **不是** K8s 资源，是 AppSet generator 的输入数据，靠 `kustomization.yaml` 排除 |

> ⚠️ 特别注意：我们的父应用**同步的是 AppSet 而不是 Application**——
> 这是 App of Apps 的一个合法变体：**父应用同步"生成器"，生成器再生成子应用**。
> 好处是子应用不必手写、可以用 cluster label 做矩阵展开；
> 代价是多了一层间接，排查问题时得顺着两层看。

详见 [`bootstrap/README.md`](./examples/gitops-layout/bootstrap/README.md) 与
[`argo-concept-sheet.md`](./argo-concept-sheet.md)。

---

## 9. 要点速查

| 问题 | 答案 |
|---|---|
| 它是什么？ | 一种 GitOps 编排模式，用普通 `Application` CR 实现，无需新组件 |
| 它解决什么？ | 打破"Application 的定义也得靠 Application 来下发"的死循环 |
| 谁能实现什么？ | 父应用 → 创建子应用；子应用 → 同步业务资源。**两层解耦** |
| 官方推荐它吗？ | ❌ 官方推荐 **ApplicationSet**（cluster generator），App of Apps 列为 *Alternative* |
| 什么时候该用它？ | 子应用集合算不出来（结构差异大 / 需要 Helm 渲染出复杂 YAML） |
| 什么时候别用？ | 大量矩阵展开 → 用 AppSet；需要细粒度权限收敛 → 用 AppSet |
| 最大风险？ | **父应用仓库的 push 权限 ≈ admin 权限**（能创建任意 Project 的 Application） |
| 最容易漏的一行？ | `finalizers: [resources-finalizer.argocd.argoproj.io]`（决定级联删除） |
| 首次铺开要做什么？ | 手动 apply 父应用 → 父应用同步出子应用 → **再手动 sync 一次子应用** |
| 父应用 InSync 就绪了吗？ | 没有。子应用此时通常是 OutOfSync，需要 `argocd app sync -l app.kubernetes.io/instance=<parent>` |

---

## 10. 关联文档

| 主题 | 文档 |
|---|---|
| Argo CD 核心对象速查（含 Root Application 一行） | [`argo-concept-sheet.md`](./argo-concept-sheet.md) |
| ApplicationSet vs Application 对比 | [`../argocd-applicationset-vs-application.md`](../argocd-applicationset-vs-application.md) |
| ApplicationSet 批量分发详解 | [`05-appset.md`](./05-appset.md) |
| 跨 Git 仓库渲染（Helm 多源 / `$values` ref） | [`helm-cross-repository.md`](./helm-cross-repository.md) |
| ApplicationSet 自身用 Helm 渲染 | [`appset-helm-Rendering.md`](./appset-helm-Rendering.md) |
| `bootstrap/` 引导层详解（父应用怎么点火、自举的坑） | [`examples/gitops-layout/bootstrap/README.md`](./examples/gitops-layout/bootstrap/README.md) |
| 可运行的仓库骨架示例 | [`examples/gitops-layout/`](./examples/gitops-layout/) |
| 交互图解：Bootstrap 全链路 | [`../diagrams/argocd-bootstrap-flow.html`](../diagrams/argocd-bootstrap-flow.html) |

### 官方链接

| 主题 | 链接 |
|---|---|
| Cluster Bootstrapping（App of Apps 一节） | <https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/#app-of-apps-pattern-alternative> |
| ApplicationSet Generators（cluster generator） | <https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Cluster/> |
| Deleting Applications in the UI（v3.2+ 删除行为） | <https://argo-cd.readthedocs.io/en/latest/user-guide/app_deletion/> |
| Diff customization（`ignoreDifferences`） | <https://argo-cd.readthedocs.io/en/latest/user-guide/diffing/> |
| Imperva Elastic WAF · App of Apps 实践 | <https://docs-cybersec.thalesgroup.com/bundle/elastic-waf/page/argo-apps.htm> |
