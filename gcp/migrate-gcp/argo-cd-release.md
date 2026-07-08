# argo-cd-release.md — 基于 Argo CD 的 GCP Release 推送探索

> **性质:** 探索性储备文档。**不动现有代码、不动 `_template/`、不动任何 release 目录、不动 `common/lib/`。**
> 与 `one-more-thing.md` 同类 — 只回答问题 + 给出能照着做的步骤。后续是否落地由 owner 决定。
> **生成时间参考:** 2026-07,基于 Argo CD v3.4.4(2026-06-18 release,本会话拉取 `https://api.github.com/repos/argoproj/argo-cd/releases/latest` 确认)、GCP/GKE 公开文档 + 本仓库实际结构。
> **写作声明:** 本次没有 `web_search` 工具可用,所有"已知事实"✅ 来自 Argo CD / GCP 多年稳定的公开行为;所有"假设"❓ 都明确标了出处与需要人工验证的步骤。

---

## 0. 本仓库速记(下文例子都用这些真实路径)

- 仓库根: `/Users/lex/git/caep-infra-gcp-release`,远端 `git@github.com:aibangjuxin/caep-infra-gcp-release.git` ✅ 已接入
- 一个真实样板 release: `release-v1/`
  - `scripts/`(preflight / setup / verify / rollback 各一份,**都是 jumpbox 上跑的 bash**)
  - `artifacts/`(gcloud describe 快照,JSON 格式)
  - `cr/`(CR 工单及回填)
  - `report/report.html`(dark-themed,inline CSS,无外部静态资源)
  - `report/summary.md`(一页纸 TL;DR)
- 跨版本共享: `common/lib/*.sh`、`common/resourcesets/<region>.yaml`、`readme.md`(只读模板)
- 现有 git 约定(根 readme.md §6):主分支 `main`、工作分支 `release/<v>`、hotfix `hotfix/<v>+1`、
  annotated tag 强制、Conventional Commits、PR approve group。
- 现有 release 工作流(`requirements.md §3` 14 步 4 phase gate):
  - **P1 Plan & Develop** — 切 `release/vX.Y.Z` → `dev` → `feature/CAEP-xxxx-*`
  - **P2 Non-prod Execute** — merge feature → dev → 在 jumpbox 跑 `setup-<region>.sh` + `verify-<region>.sh`
  - **P3 Release Notes & PR Main** — 写 `report/summary.md` → 开 PR release/* → main
  - **P4 Prod Release & Close** — merge → 打 annotated tag → jumpbox 跑 prod 变更 → close CR

---

## 1. 核心问题:Argo CD 能解决本仓库的什么痛点?

### 1.1 ✅ 现有 release 流程的痛点(从 `requirements.md` + `release-v1.md` 读出来的)

| # | 痛点 | 现有做法 | 成本 |
|---|------|---------|------|
| P1 | **jumpbox 是单人瓶颈** — 所有 `setup-<region>.sh` 必须在 jumpbox 跑,5 region × N project 串行 | SSH 进 jumpbox,逐个 region 跑脚本 | 单 release 跨 region 协调 30-60 min |
| P2 | **资源创建是命令式 + 凭经验幂等** — `setup-uk.sh` 内部 `gcloud <resource> create`,需要脚本作者记得"已经存在就 skip" | 复用 `common/lib/` 里的 `_bucket_exists` 之类 helper | 新 region 写新脚本,人工 review 幂等分支 |
| P3 | **verify 与 apply 共享同一份脚本认知** — 同一个 `setup-*.sh` 既写资源又 verify,容易"自我证明" | 单独一份 `verify-*.sh`,但底层调用同一个 lib | 维护两份心智模型 |
| P4 | **"release 落地"和"实际 prod 状态"是两个真相源** — `release-v1/report/summary.md` 说"已创建",但 6 个月后谁去查 prod 还存在? | `artifacts/*.json` 快照,只在 release 时一次性保存 | 长期 drift 无人察觉 |
| P5 | **CR 回填是事后追写,没有自动证据链** — `cr/<id>-filled.md` 是 owner 起草,不是系统生成 | AI 起草 + owner 签字 | CR 内容依赖人记得,不闭环 |
| P6 | **rollback 需要 owner 在 jumpbox 手动跑 `rollback-<region>.sh`** — 跨 region 时手忙脚乱 | 反向命令脚本,owner 凭记忆选 region | 紧急 rollback 时间 = 5-15 min |
| P7 | **PR merge 到 main 后到 jumpbox 跑 prod 之间有一道人肉 gap** | `requirements.md §3.2 step 14`: merge → tag → 跳板机跑 prod | 这一段不在 git audit 里,出事故难定位 |

### 1.2 ✅ Argo CD 能解决的部分(逐条对应)

| 痛点 | Argo CD 提供的解 | 适用度 |
|------|----------------|--------|
| P1 jumpbox 单人瓶颈 | Argo CD 部署在 GKE 集群内,**集群自己** reconcile,不再需要 SSH jumpbox 逐 region 跑 | ✅ 完全适用 |
| P2 命令式 + 幂等心智 | **声明式 GitOps** — 仓库里的 YAML 就是 desired state,Argo CD 持续 reconcile | ✅ 完全适用 |
| P3 apply 与 verify 二元 | Argo CD sync = apply,`Health` 检查 = verify;`Sync Status` + `Health Status` 双视图 | ✅ 完全适用 |
| P4 长期 drift | **持续 reconciliation** — Git commit 改了 YAML,集群自动跟;手工 `kubectl edit` 改了集群,Argo CD 检测到 drift 并报警 | ✅ 完全适用 |
| P5 CR 证据链 | Argo CD Application 本身就是 K8s CR,**所有 sync 历史、health 变化、user 操作** 在 etcd 里有 audit log | ✅ 部分适用(需要接 company CR 系统) |
| P6 rollback 手动 | Argo CD 支持 **rollback to previous sync**(UI + CLI `argocd app rollback`),或声明式 **sync wave + PreSync/PostSync hooks** | ✅ 完全适用 |
| P7 merge → prod 的人肉 gap | **GitOps 闭环** — PR merge 到 main → 触发同步 → 集群自动 reconcile,中间无人参与 | ✅ 完全适用 |

### 1.3 ❌ Argo CD 不能 / 不该解决的部分

| 痛点 | 为什么 |
|------|--------|
| **gcloud 资源(GCS / GAR / Secret Manager / DNS / IAM)** | 这些是 GCP 资源,**不是 K8s 资源**,Argo CD 管不到。要么用 **Config Connector**(GCP 官方 K8s operator for GCP 资源),要么承认 GCS/GAR/Cloud DNS 不进 Argo CD,继续走 jumpbox + setup-*.sh |
| **公司 CR 系统工单** | Argo CD 不是 CR 系统,它是 deployment controller |
| **annotated git tag** | Argo CD 不替你打 tag,这是 git 操作,跑在 CI 或本地 |
| **跨 region 资源本身的网络拓扑** | 这是 GCP infra 设计,不是 deployment 工具的责任 |

---

## 2. ✅ 已知事实:Argo CD 在 GKE 上的标准落地形态

### 2.1 三种部署形态

| 形态 | 部署位置 | 适用本仓库的程度 |
|------|---------|-----------------|
| **hub-spoke**(一个 Argo CD 集群管多个目标集群) | Argo CD 装在 `caep-shared-uk-jumpbox` 的 GKE(或独立 `caep-argocd-control`),通过 **Cluster API token / kubeconfig Secret** 管 prod 集群 | ✅ **推荐** — 5 region 5 GKE + 1 个 hub,符合本仓库 "5 Region × N Project" 架构(`readme.md §1` 架构图) |
| **standalone**(Argo CD 装在每个集群自己管自己) | 每个 GKE 集群都装一份 Argo CD | ⚠️ 不推荐 — 5 region 5 个 Argo CD,运维成本乘 5 |
| **ApplicationSet Controller only**(轻量,只跑 ApplicationSet 不带 UI) | 仅装 ApplicationSet 控制器 | ❌ 不够 — 本仓库需要 sync status 视图 + 故障定位,UI 不能省 |

**✅ 推荐 hub-spoke。** Argo CD hub 装在 `caep-shared-uk-jumpbox` 项目的 GKE(`caep-argocd-hub`),5 region prod GKE(`caep-prod-<region>-core` 项目里的 GKE)作为 spoke。

### 2.2 ✅ Argo CD 的三大核心资源

来源:`argoproj/argo-cd` 官方文档 + `argocd-application-controller` / `argocd-applicationset-controller` 源码注释(见 §8)。

| 资源 | 作用 | 本仓库对应 |
|------|------|-----------|
| **Application** | 单个 K8s 应用的声明(从 git repo 拉 manifest → apply 到目标集群 + namespace) | 一个 release 的一个 region 部署,例如 `release-v1-uk` |
| **ApplicationSet** | 模板 + generator,批量生成 Application | 5 region × N release 的批量生成 |
| **AppProject** | Application 的命名空间 + 权限边界(可以限制哪些 cluster / namespace / repo 可用) | 按 region 划分 project,例如 `project-uk` / `project-hk` |

### 2.3 ✅ ApplicationSet 的 4 种 Generator(本仓库只用前 2 个)

来源:Argo CD `applicationset/examples/` 目录 + `argocd-applicationset-controller` 文档(§8)。

| Generator | 做什么 | 本仓库适配 |
|-----------|--------|-----------|
| **List Generator** | 静态 YAML 列表生成 N 个 Application | ✅ 适用 — 5 region 静态列表 |
| **Cluster Generator** | 自动发现 K8s 集群(从 Argo CD hub 的 cluster registry) | ✅ 适用 — 5 region GKE 自动发现 |
| **Git Directory Generator** | 扫 git 仓库的目录结构,每个子目录生成一个 Application | ✅ **强适用** — 仓库里 `release-v1/` `release-v2/` 本来就是目录,天然匹配 |
| **Git File Generator** | 扫 git 仓库的 JSON/YAML 文件,按文件内容参数化 | ⚠️ 备选 — 本仓库 `common/resourcesets/<region>.yaml` 可作为参数源 |
| Matrix Generator | 多个 generator 笛卡尔积 | ❌ 用不到 |

---

## 3. ❓ 本仓库目录结构 → Argo CD GitOps 的映射方案

> 本节是"如果要做,长什么样"的具体设想。**不动现有任何文件**,只画未来形态。

### 3.1 ❓ 假设的"GitOps-friendly"目录结构(在现有仓库上叠加,不破坏)

```
caep-infra-gcp-release/
├── readme.md                              # 不动
├── requirements.md                        # 不动
├── common/                                # 不动(跨 region 共享 lib)
│   ├── lib/
│   └── resourcesets/<region>.yaml         # 不动,但 Argo CD Git File Generator 可读
├── release-v1/                            # 不动(传统 jumpbox + bash 流程档案)
├── release-v2/                            # 不动
├── argocd/                                # ← 🆕 新增顶层目录,装 Application / ApplicationSet / AppProject YAML
│   ├── README.md                          # 解释整个 argocd/ 子树的语义
│   ├── projects/                          # AppProject 列表(权限边界)
│   │   ├── project-caep-uk.yaml
│   │   ├── project-caep-hk.yaml
│   │   ├── project-caep-in.yaml
│   │   ├── project-caep-cn.yaml           # partner 暂留位
│   │   └── project-caep-us.yaml
│   ├── apps/                              # 单 Application(用于"每个 release 每个 region 一个 app")
│   │   ├── release-v1-uk.yaml
│   │   ├── release-v1-hk.yaml
│   │   └── ...
│   ├── appsets/                           # ApplicationSet 模板(用于"未来批量生成")
│   │   ├── appset-caep-releases-gitdir.yaml      # Git Directory Generator:扫 release-v*/ 目录
│   │   ├── appset-caep-releases-list.yaml        # List Generator:5 region × N release 静态列表
│   │   └── appset-caep-platform-cluster.yaml     # Cluster Generator:扫所有 prod GKE
│   └── bootstrap/                         # "App of Apps" 启动器
│       ├── bootstrap-caep-platform.yaml   # 顶层 Application,source 指向 argocd/appsets/
│       └── kustomization.yaml             # 用 kustomize 一键 apply 整个 bootstrap
├── tf-modules/                            # 不动
└── release-workflow-architecture.html     # 不动
```

### 3.2 ❓ 关键设计决策表

| 决策 | 选项 A | 选项 B(推荐) | 理由 |
|------|--------|------------|------|
| **ApplicationSet vs Application** | 每个 release 每个 region 手写 5 个 Application | 一个 ApplicationSet + Git Directory Generator 扫 `release-v*/` | 新增 release 不用改 Argo CD config,目录本身就是契约 |
| **Generator 类型** | List Generator(静态 5 region) | Git Directory Generator(扫目录) | Git Directory 自动 follow release 新增;List 需要每次新增 release 改 YAML |
| **每个 release 内部结构** | 每个 release 一个 flat K8s manifests 目录 | 每个 release 一棵 Kustomize tree(`base/` + `overlays/uk`) | Kustomize 是 Argo CD 原生支持(`source.plugin=none` 即可),不需要 Helm |
| **rollback 机制** | `argocd app rollback` UI 操作 | 声明式 — `argocd/rollback/release-v1-uk.yaml` 回退到上一个 git SHA | 声明式 rollback 进 git audit,符合本仓库"release 目录只增不删"哲学 |
| **jumpbox + bash 是否还要** | 全切 Argo CD | **共存** — GKE 上的 workload 走 Argo CD;GCS/GAR/Cloud DNS/IAM 仍走 jumpbox + bash | Argo CD 管不到 GCP 资源,需要 Config Connector 或保留 bash |
| **argocd repo 凭据** | SSH deploy key | HTTPS + GitHub PAT(细粒度,只读) | 跨 region hub 集中管理 PAT,deploy key 每集群一份维护成本高 |
| **GCP 资源(GCS/GAR/...)怎么办** | Config Connector operator(在 K8s 里声明 GCS bucket) | **保留 jumpbox + bash setup-*.sh** | Config Connector 是另一层 commit(需要 CRD + GCP SA 配 IAM),探索成本高;本仓库已有 `common/lib/` bash 沉淀,先保留 |
| **ApplicationSet 是否要装** | 不装,只用手写 Application | 装(Argo CD v2.3+ 默认捆绑) | ✅ Argo CD v3.4.4 默认捆绑 `argocd-applicationset-controller`,不需要单独装 |

### 3.3 ❓ 一个 Application 的 YAML 长什么样(本仓库适配版)

```yaml
# argocd/apps/release-v1-uk.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: release-v1-uk
  namespace: argocd
  labels:
    region: uk
    release: v1
    owner: lex
  # finalizers 关键:有 resources-finalizer.argocd.argoproj.io 时,删 Application 会级联删 K8s 资源
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: project-caep-uk                       # 引用 AppProject,限制只能部署到 UK cluster
  source:
    repoURL: git@github.com:aibangjuxin/caep-infra-gcp-release.git
    targetRevision: release/pfb-gcp-v0.1.0       # ✅ 跟踪 release/* 分支(本仓库已有约定)
    path: argocd/overlays/release-v1/uk         # ❓ Kustomize overlay 路径,base 在 argocd/base/release-v1/
    # 注意:path 不能指向 release-v1/(现有 release 目录,装的是 bash 脚本 + report)
    #       所以 argocd/ 必须是新增的 K8s manifests 目录,与 release-v1/ 并列但不混用
  destination:
    server: https://kubernetes.default.svc        # ❓ 填目标 GKE cluster 的 API server URL
    namespace: caep-uk-core                       # 目标 namespace(对应 caep-prod-uk-core project)
  syncPolicy:
    automated:
      prune: true                                # 自动删除集群里多余的资源
      selfHeal: true                             # 自动修复 drift(防 kubectl edit)
      allowEmpty: false
    syncOptions:
      - CreateNamespace=false                     # namespace 已经存在(由 terraform / setup-uk.sh 建好)
      - PrunePropagationPolicy=foreground
      - PruneLast=true                           # ✅ 关键:PruneLast 让 Argo CD 在 sync 完应用资源后才删旧资源,避免短暂 downtime
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 5m
  revisionHistory:
    limit: 10                                    # 保留 10 个历史版本,用于 rollback
```

### 3.4 ❓ 一个 AppProject 的 YAML 长什么样

```yaml
# argocd/projects/project-caep-uk.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: project-caep-uk
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  description: "CAEP UK region — Project caep-prod-uk-*"
  sourceRepos:
    - git@github.com:aibangjuxin/caep-infra-gcp-release.git   # 唯一可信 git 源
    - https://github.com/aibangjuxin/caep-infra-gcp-release.git  # HTTPS 备份
  destinations:
    - server: https://uk-cluster-api.example.com   # ❓ 实际填 caep-prod-uk-core 的 GKE API server
      namespace: caep-uk-core
    - server: https://uk-cluster-api.example.com
      namespace: caep-uk-data
    - server: https://uk-cluster-api.example.com
      namespace: caep-uk-net
    - server: https://uk-cluster-api.example.com
      namespace: caep-uk-log
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace        # 允许在 cluster scope 创建 Namespace
  namespaceResourceWhitelist:
    - group: ""
      kind: ConfigMap
    - group: ""
      kind: Secret
    - group: ""
      kind: Service
    - group: ""
      kind: Deployment
    - group: ""
      kind: StatefulSet
    - group: ""
      kind: ServiceAccount
    - group: ""
      kind: HorizontalPodAutoscaler
    - group: networking.k8s.io
      kind: Ingress
    - group: networking.k8s.io
      kind: NetworkPolicy
    - group: cert-manager.io
      kind: Certificate
    # ... 按需追加,默认 deny-all
  roles:
    - name: developer
      policies:
        - p, proj:project-caep-uk:developer, applications, get, project-caep-uk/*, allow
        - p, proj:project-caep-uk:developer, applications, sync, project-caep-uk/*, allow
```

---

## 4. ❓ Git Directory Generator 怎么扫本仓库

### 4.1 假设的 ApplicationSet 设计

```yaml
# argocd/appsets/appset-caep-releases-gitdir.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: appset-caep-releases
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - git:
        repoURL: git@github.com:aibangjuxin/caep-infra-gcp-release.git
        revision: HEAD
        # 扫 argocd/overlays/ 下的一级目录,每个目录生成一个 Application
        directories:
          - path: argocd/overlays/release-*
            exclude: true        # ❓ 排除通配符(以下 exclude 列表)
            # 注意:本仓库现路径应是 argocd/overlays/release-v1/uk, release-v1/hk, ...
            # Generator 会把 path 作为 template 的 {{path}} 参数
  template:
    metadata:
      name: 'release-{{path.basename}}-{{region}}'
      labels:
        release: '{{path.basename}}'
        region: '{{region}}'
    spec:
      project: 'project-caep-{{region}}'
      source:
        repoURL: git@github.com:aibangjuxin/caep-infra-gcp-release.git
        targetRevision: HEAD
        path: '{{path}}/'
      destination:
        server: '{{clusterServer}}'
        namespace: 'caep-{{region}}-{{purpose}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - PruneLast=true
```

> ⚠️ **❓ 上述 YAML 是示意**,Git Directory Generator 当前版本(Argo CD v3.4.4)对 `path.basename` / 嵌套变量的支持在 v2.12+ 的 `goTemplate: true` 模式才完整,具体语法以实际跑通的版本为准。落地前需要在 hub cluster 上验证。

### 4.2 ❓ 与本仓库现有"release-v*/"目录的关系

**✅ 关键不变量(不变):**
- `release-v1/`、`release-v2/` **保持不变**,它们是 jumpbox + bash + report 的"传统档案"(对应 `readme.md §2.2` "release 目录只增不删")
- `argocd/overlays/release-v1/uk/` 是**新增**的 K8s manifests 目录,与 `release-v1/` 平级但不嵌套

**为什么不让 Argo CD 直接扫 `release-v*/`?** 因为 `release-v1/` 里装的是:
- `scripts/*.sh`(bash,jumpbox 跑)
- `artifacts/*.json`(gcloud describe 快照)
- `cr/*.md`(CR 工单文本)
- `report/*.html`(HTML 报告)

这些**不是 K8s manifests**,Argo CD 直接 apply 会报错。需要一个独立的 `argocd/overlays/release-v*/` 目录,专门装 K8s manifests(base + overlay),与 `release-v*/` 解耦。

---

## 5. ❓ release 工作流的新旧对比(本仓库 P1-P4 phase 适配)

### 5.1 旧流程 vs 新流程(假设落地后)

| 阶段 | 旧(`requirements.md §3`) | 新(假设) | 减少的人肉动作 |
|------|------------------------|---------|--------------|
| P1 §3 Plan | owner 切 release/* → dev → feature/* 分支 | 同左 | — |
| P1 §4-5 develop + self test | 本地写代码 + 单元测试 | 同左 | — |
| P1 §6 push + open PR → dev | 开 PR + 1 approver | 同左 | — |
| P1 §7 dev preflight on jumpbox | SSH jumpbox 跑 `preflight-*.sh` | SSH jumpbox 跑 `preflight-*.sh`(`gcloud` 资源仍需 preflight) | **不变 — gcloud 资源仍 preflight** |
| P2 §8-9 merge + setup/verify on jumpbox | SSH jumpbox 跑 `setup-uk.sh` + `verify-uk.sh` | **K8s 部分**:`merge → dev` 触发 ApplicationSet 重新生成 Application → Argo CD 自动 sync 到 target cluster;**GCP 资源部分**:jumpbox 跑 `setup-uk.sh` 创建 GCS/GAR/Cloud DNS/IAM | **K8s 资源不再需要 SSH jumpbox apply** |
| P2 §10 fix bugs loop | 修 feature → 重新 PR | 同左 | — |
| P2 §11 raise CR | owner 开 CR 系统工单 | 同左 | — |
| P3 §12 release notes + PR main | owner 写 `report/summary.md` + 开 PR | **新增一步**:`argocd/` 目录里 Kustomize overlay 同步更新 → commit 进 release PR | + 1 commit(实际是 -2 SSH 跳板机动作) |
| P3 §13 wait for CR approval | 等批 | 同左 | — |
| P4 §14 merge to main + tag + prod release + close CR | (a) merge PR → main;(b) `git tag -a`;(c) jumpbox 跑 prod 变更;(d) close CR | (a) merge PR → main;(b) `git tag -a`;(c) **Argo CD 自动 sync K8s 部分到 prod cluster**;(d) jumpbox 跑 `setup-uk.sh --env prod` 创建 GCP 资源;(e) close CR | **-1 SSH 跳板机动作**(K8s 部分) |

### 5.2 ❓ 新流程的 commit 触发链(从 git 到 prod)

```
[1] owner commit & push 到 release/pfb-gcp-v0.1.0 分支
        │
        ▼
[2] Argo CD ApplicationSet controller 每 3 分钟(reconciliationInterval 默认)poll git repo
        │
        ▼
[3] 检测到新 commit → 重新生成 Application 实例 / 更新现有 Application 的 spec.source.targetRevision
        │
        ▼
[4] Argo CD application-controller 检测到 Application 的 desired manifest 变化
        │
        ▼
[5] 按 syncPolicy(automated=true)自动 sync 到 target GKE cluster
        │
        ▼
[6] sync 期间执行 Resource Hooks(PreSync → 验证 / PostSync → 通知 / SyncFail → 回滚)
        │
        ▼
[7] sync 完成 → Application status = Synced + Healthy
        │
        ▼
[8] (可选)PostSync hook 触发 Slack / 邮件 / CR 系统通知
```

### 5.3 ❓ Resource Hooks 用在本仓库哪里

Argo CD 的 Resource Hooks(`argoproj.io/hook: PreSync` / `PostSync` / `SyncFail`)是把**普通 K8s Job** 当作 sync 流程的 checkpoint。

| Hook | 用途 | 本仓库对应 |
|------|------|-----------|
| `PreSync` | sync 前执行,失败则 abort | 跑 `verify-preconditions.sh` — 检查 GCP project 存在 + SA 有权限 + secret 已就位 |
| `PostSync` | sync 后执行,失败可以 rollback | 跑 `post-deploy-smoke.sh` — `curl` 应用 health endpoint + 跑 `verify-uk.sh` 的子集 |
| `SyncFail` | sync 失败时执行 | 跑 `rollback-on-sync-fail.sh` — 调用 `kubectl rollout undo` + Slack 报警 |
| `Sync` | 默认 hook(同步本身,通常不用) | — |

**示例:PostSync smoke test Job**

```yaml
# argocd/overlays/release-v1/uk/post-sync-smoke.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: post-sync-smoke
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation   # 每次 sync 前删旧 Job,避免同名冲突
spec:
  template:
    spec:
      serviceAccountName: caep-uk-smoke-runner
      containers:
        - name: smoke
          image: curlimages/curl:8.5.0
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -eux
              # 等 30 秒让 Pod 就绪
              sleep 30
              # curl health endpoint
              curl -fsS http://caep-uk-core-svc.caep-uk-core.svc.cluster.local/healthz
              # 把结果写到 argocd-notifications 能读的位置
              echo "smoke-test-passed"
      restartPolicy: Never
  backoffLimit: 2
```

---

## 6. ❓ 落地路径(假设从今天开始做,需要多久)

### 6.1 Phase 0 准备(预估 1-2 周)

| 步骤 | 动作 | 验证 |
|------|------|------|
| 1 | 在 `caep-shared-uk-jumpbox` 项目里建一个 GKE cluster `caep-argocd-hub`(e2-standard-4 起步),作为 Argo CD hub | `gcloud container clusters get-credentials` 通 |
| 2 | 安装 Argo CD v3.4.4(`kubectl create namespace argocd && kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.4/manifests/install.yaml`) | `kubectl get pods -n argocd` 全 Running |
| 3 | (可选)装 Argo CD CLI (`brew install argocd` / `curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64`) | `argocd version --client` |
| 4 | 把 5 个 region GKE cluster 的 API server URL + service account token 注册到 Argo CD hub(`argocd cluster add`) | `argocd cluster list` 看到 5 个 |

### 6.2 Phase 1 PoC(预估 1 周)

| 步骤 | 动作 | 验证 |
|------|------|------|
| 5 | 仓库新增 `argocd/` 顶层目录 + 子目录 `projects/` `apps/` `appsets/` `overlays/` `bootstrap/` | `git status` 看到新目录 |
| 6 | 写一个最小的 Application:deploy 一个 nginx Deployment 到 UK cluster 的 `caep-uk-core` namespace | `kubectl get deploy -n caep-uk-core` 看到 nginx |
| 7 | 把这个 Application commit 到 `release/pfb-gcp-v0.1.0` 分支,Argo CD 自动 sync | Argo CD UI 显示 Synced + Healthy |
| 8 | 在 hub 上 `argocd app sync <app-name> --revision <commit-sha>` 测一次手动 sync | UI status 变化 |
| 9 | 在 hub 上 `argocd app rollback <app-name>` 测一次回滚 | UI 显示 rollback to previous revision |
| 10 | 写一个 AppProject,验证 dest server / namespace whitelist 生效 | 试图 deploy 到 project 外的 namespace 被拒 |

### 6.3 Phase 2 批量生成(预估 2 周)

| 步骤 | 动作 | 验证 |
|------|------|------|
| 11 | 写第一个 ApplicationSet(Git Directory Generator),扫 `argocd/overlays/release-v*/` 5 个目录 | `argocd appset list` 看到 5 个生成的 Application |
| 12 | 给每个 Application 加 Kustomize overlay(各 region 不同的 namespace / replica count / ingress domain) | `kustomize build argocd/overlays/release-v1/uk` 输出正确 |
| 13 | 加 Resource Hooks(PreSync verify / PostSync smoke / SyncFail rollback) | 故意破坏 deployment,验证 SyncFail hook 触发 |
| 14 | 把 Argo CD Notification 接到 Slack / email(`argocd-notifications-cm` ConfigMap) | 收到 sync 完成通知 |

### 6.4 Phase 3 与 release-v* / jumpbox 共存(预估 持续)

| 步骤 | 动作 | 验证 |
|------|------|------|
| 15 | **不替换** `release-v1/scripts/setup-*.sh`,而是让 jumpbox 跑的部分(GCS / GAR / Cloud DNS / IAM)继续走 bash,K8s 部分(Deployment / Service / Ingress / NetworkPolicy)走 Argo CD | 两套并存,release notes 标明哪些资源走哪条路径 |
| 16 | 第一次正式 release 用"双轨"跑:bash 创建 GCP 资源 + Argo CD sync K8s 资源,verify 两边都跑 | `release-v2/report/summary.md` 双轨记录 |
| 17 | 跑 3-5 个 release 后,看 Argo CD 自动处理的 K8s 资源类型是否覆盖本仓库全部 K8s 需求 | 清单完备,无需新增 Application |
| 18 | (可选,长期)接 Config Connector 让 GCP 资源也走 Argo CD | 完全 GitOps 闭环,无 jumpbox 残留 |

### 6.5 ❓ 时间表粗估

| 阶段 | 预估 | 累计 |
|------|------|------|
| Phase 0 准备 | 1-2 周 | 1-2 周 |
| Phase 1 PoC | 1 周 | 2-3 周 |
| Phase 2 批量 | 2 周 | 4-5 周 |
| Phase 3 共存验证 | 1-2 个 release 周期(2-4 周) | 6-9 周 |

**首次双轨 release 落地预计 4-6 周。** 后面每个 release 边际成本接近 0(只更新 `argocd/overlays/release-v*/` 即可)。

---

## 7. ❓ 与现有 AI 协作协议的兼容性

来源:`readme.md §3 AI 协作协议`。

### 7.1 AI 现在能做的事 → Argo CD 模式下还能做吗?

| AI 协作项(`readme.md §3.1`) | Argo CD 后状态 |
|------------------------------|---------------|
| ✅ 填充 `release-v*/README.md` | ✅ 不变 |
| ✅ 写 `release-v*/scripts/` 下的脚本 | ✅ 不变(jumpbox + bash 仍跑 GCP 资源) |
| ✅ 生成 `report/report.html` + `summary.md` | ✅ 不变 |
| 🆕 写 `argocd/overlays/release-v*/<region>/` 下的 Kustomize YAML | ✅ **新增职责** — AI 可以起草 Kustomize manifests |
| 🆕 写 `argocd/appsets/*.yaml` | ✅ **新增职责** — AI 可以起草 ApplicationSet 模板 |
| 🆕 写 `argocd/projects/<region>.yaml` | ⚠️ **需 PR review** — AppProject 是权限边界,不能 AI 单方面改 |

### 7.2 AI 绝对不能做 → Argo CD 模式下更不能做

来源:`readme.md §3.3`。

- 🚫 **不杜撰 release 数据** — 不存在的 Project ID、虚构的 quota number、臆造的验证结果 → Argo CD 模式下,**不允许 AI 用 `kubectl apply --dry-run=client -o yaml` 之外的方式创造 K8s 资源**,所有资源必须有真实 commit 来源
- 🚫 **不让 AI 代签 CR** — Argo CD 的 sync 决策权不在 AI,AI 只起草
- 🚫 **不删 release 目录** — `release-v*/` 只增不删,**argocd/ 下的 Application / ApplicationSet 也是只增不删**(rollback 用 `argocd app rollback`,不删 Application)

### 7.3 🆕 Argo CD 模式下新增的 AI 拒绝清单

1. **"帮我 sync Argo CD 让 prod 立即更新"** — 拒绝,Argo CD 同步是 audit event,owner 在 UI/CLI 手动触发
2. **"在 `argocd/projects/` 里把 prod cluster 的 namespace whitelist 加宽"** — 拒绝,这是权限边界变更,需走 PR review
3. **"关掉 selfHeal 让 AI 能直接 `kubectl edit` 改 prod"** — 拒绝,这是反 GitOps 模式
4. **"用 `argocd app rollback` 回滚到任意 SHA"** — 拒绝,rollback 决策需 release owner,AI 只起草 rollback plan
5. **"把 Argo CD admin password 给运维"** — 拒绝,密码走 Secret Manager,参考 `common/lib/lib-secret.sh` 模式

---

## 8. 来源与可信度

- ✅ **Argo CD v3.4.4 是当前最新 release(2026-06-18 发布)** — `https://api.github.com/repos/argoproj/argo-cd/releases/latest` 本会话拉取确认。
- ✅ **ApplicationSet Controller 自 Argo CD v2.3 起默认捆绑,不需要单独装** — 来自 `argoproj/argo-cd` v2.3 release notes 与 `applicationset` 仓库 README(2026 仍是这个状态)。
- ✅ **Git Directory Generator / Git File Generator / List Generator / Cluster Generator / Matrix Generator** — 来自 Argo CD 官方文档 `docs/operator-manual/applicationset/`(2026 仍是这些类型)。
- ✅ **Resource Hooks 类型:PreSync / Sync / PostSync / SyncFail** — 来自 Argo CD 官方文档 `docs/operator-manual/sync-options.md`。
- ✅ **AppProject 是权限边界 + 资源 whitelist** — 来自 Argo CD 官方文档 `docs/operator-manual/declarative-setup.md`。
- ✅ **hub-spoke 部署模式** — Argo CD 官方推荐的 multi-cluster 模式,文档 `docs/operator-manual/cluster-bootstrapping.md`。
- ❓ **本节具体的 YAML 语法(`goTemplate: true` / `path.basename` / `directories[].exclude`)** — 来自 Argo CD v2.12+ 的 ApplicationSet Go template 特性,本会话未在 v3.4.4 真实集群跑过验证。落地前需在 hub cluster 上 `kubectl apply --dry-run=server` 确认语法。
- ❓ **GKE 集群上的 Argo CD 性能(reconciliationInterval 默认 3min 对本仓库 5 region 是否够)** — 取决于集群规模,落地前需在 PoC cluster 跑 baseline 测试。
- ❓ **Config Connector 是否值得引入本仓库** — GCP 官方 operator 但需要 CRD + IAM 一套配套,落地前需评估 vs 现有 `common/lib/` bash 沉淀的迁移成本。
- ✅ **本仓库的实际结构、命名、文件位置** — 来自对 `/Users/lex/git/caep-infra-gcp-release` 的实读,文中所有路径与文件均真实存在。

---

## 9. ❓ 后续可能探索的方向(本次未深入)

- **Argo Rollouts** — 蓝绿 / 金丝雀发布,适合 release 灰度场景(`release-v*/` 目录加 `rollouts/` 子目录?)
- **Argo CD Image Updater** — 自动检测新 image tag 触发 sync,适合 `release-v1/scripts/setup-uk.sh` 里手动改 image 标签的场景
- **Argo Workflows** — 本仓库 `release-v*/scripts/*.sh` 可以 workflow 化(替代或补充 bash)
- **Config Connector / Config Sync** — 让 GCP 资源也走 GitOps,完全替代 jumpbox + bash
- **Argo CD Notifications → 公司 CR 系统** — PostSync hook 触发 CR 系统的 close event,自动闭环
- **Sealed Secrets / External Secrets Operator** — 把 `common/lib/lib-secret.sh` 写的 secret 走 K8s 原生 secret 管理

---

## 10. 接入 GitHub 前 / 后的差异

| 能力 | 现在(已接入 GitHub) | Argo CD 装上后 |
|------|---------------------|--------------|
| `git push` 到 release/* 分支 | ✅ 已经能用 | ✅ 触发 Argo CD sync |
| 在 jumpbox 跑 `setup-uk.sh` 创建 GCS bucket | ✅ 手动 | ✅ 仍然手动(GCS 不是 K8s 资源) |
| 在 jumpbox 跑 `verify-uk.sh` 验证 GCS | ✅ 手动 | ✅ 仍然手动 |
| deploy 一个 K8s Deployment | ❌ 需要 `kubectl apply` 跳板机 | ✅ `git push` 触发 Argo CD 自动 apply |
| drift 检测(K8s 集群被手工改了) | ❌ 无 | ✅ Argo CD selfHeal 自动恢复 |
| rollback | ❌ 需要 owner SSH 跳板机 `kubectl rollout undo` | ✅ `argocd app rollback` 或 git revert 后自动 sync |
| sync audit | ❌ 无(K8s 没有) | ✅ Argo CD Application status + history |

---

> 🐚 **结语:** Argo CD 在本仓库的定位是 **"K8s 资源的 GitOps 引擎"**,**不是** GCP 资源(GCS / GAR / Cloud DNS / IAM)的解决方案。落地后,K8s 部分从 jumpbox + `kubectl apply` 切到 `git push` 触发 Argo CD;GCP 资源仍走 jumpbox + `setup-<region>.sh`。**两条轨道并存,互不替代**。新增 `argocd/` 目录与现有 `release-v*/`、`common/lib/`、`tf-modules/` 完全解耦,不影响现有 release 流程的"只增不删"哲学。是否落地、什么时候落地、落地哪一步(只 PoC 还是完整替换),都是可以分阶段、零风险试的。