# bootstrap/ · 引导层（Bootstrap Layer）

> **这个目录是整套 GitOps 体系的「起搏器」**。
>
> Argo CD 有一条自己打自己脑袋的链条：
> *没有 Application，Argo CD 就什么都不会同步；*
> *而 Application 又必须写在 Git 里、由 Argo CD 去拉。*
>
> `bootstrap/` 就是用来**打破这个死循环**的那一层：
> 它是**唯一**需要「手动点火」的地方，点完火之后它自己管自己。

---

## 目录

- [1. 一句话说清 bootstrap 是什么](#1-一句话说清-bootstrap-是什么)
- [2. 它到底做了哪三件事](#2-它到底做了哪三件事)
- [3. 目录里每个文件的作用](#3-目录里每个文件的作用)
- [4. 从零到一：完整时序](#4-从零到一：完整时序)
- [5. kustomization.yaml：根应用到底 apply 什么](#5-kustomizationyaml：根应用到底-apply-什么)
- [6. root-application.yaml：自举与它的两个坑](#6-root-applicationyaml：自举与它的两个坑)
- [7. 三层引用关系（谁引用谁）](#7-三层引用关系（谁引用谁）)
- [8. bootstrap **不**做什么](#8-bootstrap-不做什么)
- [9. 改 bootstrap 的规矩](#9-改-bootstrap-的规矩)
- [10. 首次安装顺序 & 常见失败对照表](#10-首次安装顺序--常见失败对照表)
- [11. 相关文档](#11-相关文档)

---

## 1. 一句话说清 bootstrap 是什么

> **Root Application 只同步 `bootstrap/` 这一个目录；
> 而这个目录里的内容，会催生出整套 AppProject / ApplicationSet / Application。**

把它想成「三层洋葱」的最外层皮：

```
┌───────────────────────────────────────────────────────────────┐
│ ③ 应用层：真正干活的东西                                      │
│    Application × N（每个集群 × 组件一个）                       │
│    → 去 apps/ 里取清单，同步到目标集群                          │
├───────────────────────────────────────────────────────────────┤
│ ② 生成层：谁去生成 ③                                         │
│    ApplicationSet × M                                         │
│    → 读 Git 里的 clusters/*/components/*.yaml，批量生成 ③      │
├───────────────────────────────────────────────────────────────┤
│ ① 边界层：能做什么                                            │
│    AppProject × K（源仓库 / 目标 / 资源类型 / 谁能动）         │
│    → ③ 里的每个 Application 都受它约束                          │
├───────────────────────────────────────────────────────────────┤
│ ⓪ 引导层：bootstrap/  ← 就是你在看的这个目录                  │
│    声明边界（AppProject）+ 声明生成（AppSet）+ 声明入口        │
│    （Root Application）+ 声明事实来源（clusters/）              │
└───────────────────────────────────────────────────────────────┘
```

**「bootstrap」这个名字的来历**：它就是操作系统里的 *bootstrap loader* ——
「引导程序」。系统上电时还没有任何用户态程序，CPU 先跑一段极小的、只负责把
真正的加载器搬起来的代码。

在 Argo CD 这里同理：
- `bootstrap/` 是那段**极小的引导代码**（只有几个 CR）；
- 第一次必须**手工**把它 apply 进去（就像 BIOS 自检后要你手动引导）；
- 之后它自己把自己同步、自己维护（自举，self-hosting）；
- 并且它**生出**了后面两层。

> ⭐ 一句话记忆：**`bootstrap/` = 唯一需要手工点火的目录 + 整套体系的定义文件。**

---

## 2. 它到底做了哪三件事

| # | 职责 | 具体落在哪 | 少了会怎样 |
|---|---|---|---|
| ① | **声明边界**（能做什么） | `appprojects/*.yaml` | Application 落到 `default` 项目 → `default` 是**最宽松**的（任意源、任意目标、任意资源类型）→ 严重安全风险 |
| ② | **声明生成**（生成什么、生成到哪） | `applicationsets/*.yaml` | 每个集群每个组件都要手写 Application → 集群一多就没法维护 |
| ③ | **声明入口**（从哪开始） | `root-application.yaml` + `kustomization.yaml` | 没有根应用 → 下面那些 AppProject/AppSet 永远不会被 apply，等于什么都没配 |

外加两件"事实与凭据"：

| # | 职责 | 落在哪 | 说明 |
|---|---|---|---|
| ④ | **仓库凭据** | `repositories.yaml` | Argo CD 去哪拉代码、拿什么凭据 |
| ⑤ | **集群事实来源** | `clusters/**` | **不是** Argo CD 资源，是给 AppSet 读的数据（详见 [`clusters/README.md`](./clusters/README.md)） |

---

## 3. 目录里每个文件的作用

```
bootstrap/
├── kustomization.yaml          ←  ⭐ 决定「根应用到底 apply 哪些资源」
├── root-application.yaml       ←  ⭐ 根应用（App of Apps 入口）+ 自举
├── repositories.yaml           ←    Git 凭据（GitHub App / PAT / 无凭据 http）
├── appprojects/                ←  ① 边界层
│   ├── platform.yaml           ←      父项目（公共约束，被子项目继承）
│   ├── platform-dev.yaml       ←      dev 环境边界
│   └── platform-prod.yaml      ←      prod 环境边界
├── applicationsets/            ←  ② 生成层
│   ├── component-nginx.yaml    ←      环境级组件（path 用 {{.env}}）
│   ├── component-api.yaml
│   ├── component-redis.yaml
│   ├── component-gatekeeper.yaml  ←   集群级组件（path 用 {{.cluster}}）
│   ├── component-gateway.yaml     ←   集群级组件
│   └── _alternatives/          ←      备选方案（**不在** kustomization.yaml 里 → 不生效）
│       └── component-nginx-merge.yaml
└── clusters/                   ←  ⑤ 事实来源（**永远不 apply**）
    ├── README.md               ←      ⭐ 集群清单的完整说明
    ├── _templates/             ←      复制模板（*.example 后缀）
    ├── dev-01/ dev-02/ prod-01/ prod-02/
    │   ├── cluster.yaml        ←        集群元信息
    │   └── components/*.yaml   ←        组件开关（文件存在 = 启用）
```

| 文件 | 谁读它 | 读了干什么 |
|---|---|---|
| `kustomization.yaml` | Root Application（Kustomize 构建器） | 决定这次同步 apply 哪些 CR。**这是"开关面板"** |
| `root-application.yaml` | Argo CD（它是根应用自己） | 指向 `bootstrap/` 目录 → 触发整个体系 |
| `repositories.yaml` | repo-server | 去哪拉代码、用什么凭据 |
| `appprojects/*` | Argo CD 校验器 + Casbin | 限制源 / 目标 / 资源类型 / 谁能操作 |
| `applicationsets/*` | ApplicationSet controller | 批量生成 Application |
| `clusters/**` | ApplicationSet 的 **git 文件生成器** | 提供「哪个集群、哪个组件、装到哪」 |
| `applicationsets/_alternatives/**` | （没人读） | 备选模板，需要时才手动登记进 `kustomization.yaml` |

---

## 4. 从零到一：完整时序

```
                     ┌──────────────────────────────────────────┐
   ① 手动点火        │  kubectl apply -f bootstrap/root-application.yaml
   （唯一一次手工）   └────────────────────┬─────────────────────┘
                                        │
                                        ▼
                     ┌──────────────────────────────────────────┐
   ② 根应用同步       │  Root Application 同步 bootstrap/ 目录
                     │  → Kustomize 按 kustomization.yaml 构建
                     └────────────────────┬─────────────────────┘
                                        │
              ┌─────────────────────────┼─────────────────────────┐
              ▼                         ▼                         ▼
      ┌───────────────┐         ┌───────────────┐         ┌───────────────┐
      │ AppProject ×3 │         │ ApplicationSet│         │  Repository   │
      │  （边界层）    │         │  ×5（生成层）  │         │  （凭据）      │
      └───────────────┘         └───────┬───────┘         └───────────────┘
                                        │
                    ┌───────────────────┴───────────────────┐
                    │ git 文件生成器扫 Git：                  │
                    │ bootstrap/clusters/*/components/*.yaml │
                    └───────────────────┬───────────────────┘
                                        ▼
                     ┌──────────────────────────────────────────┐
   ③ 批量生成         │  Application × N（每个 集群 × 组件 一个）  │
                     │  nginx-dev-01 / nginx-prod-01 / …        │
                     └────────────────────┬─────────────────────┘
                                          ▼
                     ┌──────────────────────────────────────────┐
   ④ 各自同步         │  每个 Application 去 apps/<c>/overlays/…  │
                     │  渲染 Kustomize → apply 到目标集群         │
                     └──────────────────────────────────────────┘
```

> ⚠️ **注意时序里的三个「先后」**（踩过的人都知道）：
>
> | 先后 | 违反后的报错 |
> |---|---|
> | AppProject **先于**根应用 | `project not found`（根应用引用的 `platform` 项目还不存在） |
> | Repository **先于**根应用同步 | repo-server 拉不到代码 → Application 一直 `Unknown`/`ComparisonError` |
> | Cluster Secret **先于**子应用同步 | `Unable to connect to server`（目标集群还没注册） |

### 4.1 自举：根应用管自己

```
        ┌──────────────────────────────┐
        │ Root Application             │
        │  source.path = bootstrap     │
        │  destination = 控制面集群自己 │
        └───────────┬──────────────────┘
                    │ 同步
                    ▼
        ┌──────────────────────────────┐
        │ bootstrap/ 目录              │
        │  ├─ AppProject ×3            │
        │  ├─ ApplicationSet ×5        │
        │  ├─ Repository               │
        │  └─ root-application.yaml ◄──┼──┐ 就是它自己
        └──────────────────────────────┘  │
                    ▲                    │
                    └────────────────────┘
                    改根应用的分支/path，走 PR，Argo CD 自己同步自己
```

> `root-application.yaml` 也放在 `bootstrap/` 里并被 `kustomization.yaml` 登记，
> 就是为了让它**自己管自己**：改分支、改 path、开启自动同步，都走 Git PR，
> 而不是有人 kubectl patch。

---

## 5. kustomization.yaml：根应用到底 apply 什么

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - appprojects/platform.yaml
  - appprojects/platform-dev.yaml
  - appprojects/platform-prod.yaml
  - applicationsets/component-nginx.yaml
  - applicationsets/component-api.yaml
  - applicationsets/component-redis.yaml
  - applicationsets/component-gatekeeper.yaml
  - applicationsets/component-gateway.yaml
  - repositories.yaml
  - root-application.yaml
# ❌ 故意不列 clusters/：那是 AppSet 的输入数据，不是 Argo CD 资源
# ❌ 也不列 applicationsets/_alternatives/：那是备选方案，现在不启用
```

### 为什么这个文件是**整个 bootstrap 里最重要的一个**

因为 `bootstrap/` 里**混着两类东西**：

| 类别 | 文件 | 是不是 K8s 资源 |
|---|---|---|
| Argo CD 的 CR | `appprojects/*`、`applicationsets/*`、`repositories.yaml`、`root-application.yaml` | ✅ 是 |
| 数据 | `clusters/**`（cluster.yaml / components/*.yaml） | ❌ **不是** |

如果不加这个文件，Argo CD 的目录源会**递归扫描整个 `bootstrap/`**，
把 `clusters/dev-01/components/nginx.yaml` 也当成 K8s 资源去解析 →
`failed to generate manifest for source` → 整个 bootstrap 同步失败。

> 🔑 **记住这条规则**：`bootstrap/` 里新增任何东西，
> 问自己一句「它是 CR 吗？」—— 是 → 登记进 `kustomization.yaml`；
> 不是 → 千万别登记。

### 想验证根应用到底 apply 什么

```bash
kubectl kustomize bootstrap | grep -E '^kind:|^  name:'
# 应该正好 10 个：3 AppProject + 5 ApplicationSet + 1 Repository + 1 Application
```

---

## 6. root-application.yaml：自举与它的两个坑

```yaml
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
    path: bootstrap            # ← 只同步这一个目录
  destination:
    server: https://kubernetes.default.svc   # ← 控制面集群自己
    namespace: argocd
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=false, ServerSideApply=true]
  preserveResourcesOnDeletion: true
```

### 坑 1：Chicken-and-egg（先有鸡还是先有蛋）

根应用**自己**也要被 Argo CD 拉取 → Argo CD 得先存在才能拉它 → 但 Argo CD 得先有
Application 才工作。

**解法**：第一次**手工** apply 一下，之后交给它自己：

```bash
kubectl apply -f bootstrap/root-application.yaml   # ← 全流程唯一一次手工操作
```

### 坑 2：`destination.server` 指错 → 循环依赖

```yaml
destination:
  server: https://kubernetes.default.svc   # ✅ 控制面集群（Argo CD 自己所在）
  # server: <某个业务集群>                   # ❌ 根应用会被同步到业务集群，
  #                                           #   业务集群的 Argo CD 又去拉根应用 → 成环
```

> 规则：**管理 Argo CD 自身的那个 Application，不应该出现在被它管理的范围里。**

### 坑 3：`prune` 把边界层一起删了

如果根应用被删除或同步失败时 prune 生效，`AppProject` / `ApplicationSet` 会**一起消失**，
整套体系瞬间塌掉。所以模板里统一开：

```yaml
preserveResourcesOnDeletion: true   # 删除 Application 时保留集群里的资源
```

---

## 7. 三层引用关系（谁引用谁）

| 关系 | 机制 | 是不是 ownerReference | 删上游会怎样 |
|---|---|---|---|
| Application → AppProject | **逻辑引用**（`spec.project` 写名字） | ❌ 不是 | AppProject 被删，Application 还在，但**校验会失败**（project 不存在） |
| ApplicationSet → Application | **ownerReference** | ✅ 是 | AppSet 被删 → 它生成的 Application **全部级联删除** → 集群资源被 prune |
| Application → Git 目录 | `spec.source.path` | —— | 目录改名 → Application 同步失败 |
| Application → 集群 | `spec.destination.server` | —— | 集群没注册 → `Unable to connect` |

> ⚠️ 特别注意第 2 行：**删掉一个 AppSet 文件 = 删掉它生成的所有 Application**。
> 停用组件的正确姿势：
> ① 删 `clusters/<cluster>/components/<name>.yaml`（只停一个集群）
> ② 或删 `applicationsets/component-<name>.yaml`（停所有集群）——
>    两种情况都因为模板里的 `preserveResourcesOnDeletion: true` 而**保留集群资源**，
>    需要人工清理。

---

## 8. bootstrap **不**做什么

| 不做 | 为什么 | 在哪做 |
|---|---|---|
| ❌ 不安装 Argo CD 本身 | Argo CD 自己不在自己的管理范围内 | Helm / kubectl（见 [`../demo.sh`](../demo.sh) STEP 02） |
| ❌ 不管理集群生命周期 | 集群是"被管的"，不是"管的" | Terraform / Crossplane（另起流水线） |
| ❌ 不注册集群（Cluster Secret） | Cluster Secret 含凭据，不适合进 Git | `argocd cluster add` 或独立的 Secret 清单 |
| ❌ 不放业务代码 | 组件本体有独立 owner | `apps/<component>/` |
| ❌ 不放集群的"每集群一份配置" | 那里只放"开关" | `apps/<component>/overlays/cluster/<cluster>/` |
| ❌ 不管命名空间的创建 | `CreateNamespace=true` 由同步策略负责 | —— |

> 一句话：**bootstrap 管的是「Argo CD 怎么管别人」，不管「别人怎么管东西」。**

---

## 9. 改 bootstrap 的规矩

### 9.1 常见改动 → 怎么做

| 我要… | 改哪里 | 要不要动 `kustomization.yaml` |
|---|---|---|
| 加一个组件 | 新建 `applicationsets/component-<name>.yaml` + `apps/<name>/` | ✅ 要登记 |
| 改某个集群装不装某组件 | `clusters/<cluster>/components/<name>.yaml` 增/删文件 | ❌ 不用 |
| 加一个集群 | 新建 `clusters/<cluster>/` + 注册 Cluster Secret + AppProject 加 destinations | ❌ 不用（但要改 `appprojects/`） |
| 收紧权限 | 改 `appprojects/*.yaml` | ❌ 不用 |
| 换代码分支 | 改 AppSet 模板的 `source.targetRevision` | ❌ 不用 |
| 切 Merge 生成器 | 用 `applicationsets/_alternatives/` 里的模板，**手动登记**进 `kustomization.yaml`，同时精简 `clusters/*/components/*.yaml` | ✅ 要登记 |
| 换 Git 仓库 | 改 `repositories.yaml` + 所有 `repoURL` | ❌ 不用 |

### 9.2 提交前跑一遍

```bash
cd examples/gitops-layout

python3 validate-clusters.py     # 集群清单一致性（字段/路径/destinations）
python3 preview-appset.py        # 会生成哪些 Application
kubectl kustomize bootstrap >/dev/null && echo "bootstrap build OK"
```

> `validate-clusters.py` 能提前抓到的典型错误：
> 少字段（`missingkey=error` → **整个 AppSet** 报错）、
> server 抄错（`Unable to connect`）、
> project 抄错（`not match any of the allowed destinations`）、
> 集群级 overlay 引用了错的环境层（**静默**跑错环境，最危险）。

---

## 10. 首次安装顺序 & 常见失败对照表

### 10.1 首次安装（生产）

```bash
# 0. Argo CD 已装好，且 admin 密码已拿到
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# 1. 登录
argocd login <argocd-server> --username admin --password '<password>'

# 2. 仓库凭据（GitHub App / PAT）
kubectl apply -f bootstrap/repositories.yaml

# 3. ★ 边界层必须先建（否则根应用报 project not found）
kubectl apply -f bootstrap/appprojects/

# 4. ★ 根应用点火（唯一一次手工）
kubectl apply -f bootstrap/root-application.yaml

# 5. 之后交给它自己；用 CLI 看进展
argocd app list -o wide
argocd appset list
```

> 第 4 步之后，`bootstrap/` 里的 AppProject / ApplicationSet 会被自动 apply，
> Application 会被自动生成，集群资源会被自动同步 —— **你只负责改 Git**。

### 10.2 常见失败对照表

| 现象 | 根因 | 处理 |
|---|---|---|
| `failed to generate manifest for source` | `bootstrap/` 里混进了非 K8s 资源（`clusters/**`） | `kustomization.yaml` 限定只列 CR |
| `project not found` | AppProject 还没建，根应用就开始同步 | 先 `apply appprojects/`，再建根应用 |
| AppSet 存在但**一个 Application 都没有** | `clusters/*/components/*.yaml` 路径不对 / 字段缺失 | `missingkey=error` 会整片报错，看 AppSet 事件 |
| Application 一直 `Unknown` | repo-server 拉不到仓库 | 检查 `repositories.yaml` 凭据、`Repository` 状态 |
| Application `Unable to connect to server` | 目标集群没注册 | `argocd cluster add` 或创建 Cluster Secret |
| 同步报 `not match any of the allowed destinations` | AppProject 的 `destinations` 没覆盖该集群 | 补 `destinations`（`validate-clusters.py` 会查） |
| 同步报 `not permitted` | 资源类型不在 AppProject 白名单 | 补 `clusterResourceWhitelist` / `namespaceResourceWhitelist` |
| 删了个 AppSet，所有应用都消失 | ownerReference 级联删除 | 停用组件用「删 components 文件」；模板里保留 `preserveResourcesOnDeletion: true` |
| 根应用删了，AppProject 也跟着没了 | prune 生效 | 模板里开 `preserveResourcesOnDeletion: true` |
| 应用停在 `OutOfSync`，集群里啥也没有 | Gatekeeper 拒绝（webhook deny） | 看 `status.conditions[].message`；见 [`../../06-opa-gatekeeper-impact.md`](../../../06-opa-gatekeeper-impact.md) |

---

## 11. 相关文档

| 主题 | 文档 |
|---|---|
| **本目录的详细说明** | 你正在读的这份 |
| **集群清单**（命名约定 / 多 project / 每集群独立配置） | [`./clusters/README.md`](./clusters/README.md) |
| **整体骨架与操作顺序** | [`../README.md`](../README.md) |
| **整条链路流程图**（PR → 门禁 → 点火 → 同步） | [`../bootstrap-flow.md`](../bootstrap-flow.md) |
| **命令行跑通全流程的 Demo** | [`../demo.sh`](../demo.sh) |
| AppProject / RBAC 详解 | [`../../04-appproject-rbac.md`](../../../04-appproject-rbac.md) |
| ApplicationSet 生成器选型 | [`../../05-appset.md`](../../../05-appset.md) |
| OPA / Gatekeeper 对 Argo CD 的影响面 | [`../../06-opa-gatekeeper-impact.md`](../../../06-opa-gatekeeper-impact.md) |
| Git 凭据（GitHub App） | [`../../07-repository-githubapp.md`](../../../07-repository-githubapp.md) |
| 概念速查表 | [`../../argo-concept-sheet.md`](../../../argo-concept-sheet.md) §4 |
