# crossplane-gcp-family-best-practices.md — Crossplane + GCP Family 最佳实践

> **本仓库 v2 方向文件**,完全取代 v1(原 `release-v1/` `common/lib/` `tf-modules/` 已被移到 `legacy/`)。
> **核心立场:** 我们采用方案 **B. Crossplane(provider-gcp)**,并称之为 **"Crossplane + GCP Family"** 方案。
> **生成时间:** 2026-07-08
> **核心事实依据:**
> - Crossplane core **v2.3.3**(2026-06-22 published)— `api.github.com/repos/crossplane/crossplane/releases/latest` 本会话拉取
> - Upbound provider-gcp **v2.6.0**(2026-06-11 published)— `api.github.com/repos/upbound/provider-gcp/releases/latest` 本会话拉取
> - ⚠️ 注意:GitHub 路径 `crossplane/provider-gcp` 2026 仍指向 v0.22.0(2022),**已 deprecated**,canonical 路径是 **`upbound/provider-gcp`**(Upbound 是 Crossplane 的商业母公司,2023 年接手 GCP provider 维护)
> - 本仓库 `legacy/` 下保留 v1 全部内容(原 `common/lib/*.sh` `release-v1/` `tf-modules/` `readme.md` 等),**不删除**

---

## 0. TL;DR(30 秒版)

1. **方案选择:** Crossplane(`upbound/provider-gcp` v2.6.0) + 自定义 CompositeResource(XRD) 抽象
2. **黄金准则:** 所有定义都在 **YAML** 里完成,`<Project_ID>.yaml` 是 Source of Truth
3. **4 层目录结构:** `tooling/` `foundation/` `projects/` `releases/`
4. **入口:** `releases/<version>/main.sh -p <Project_ID>`
5. **Branch 策略:** `main` + `crossplane-gcp-family`(主开发)+ `release/<name>`(单 release)

---

## 1. 为什么是 Crossplane(provider-gcp) 而不是其他?

### 1.1 v1 → v2 决策回顾

v1 文档 `argo-cd-release.md §11` 原推荐 **Config Connector**(GCP 官方 K8s operator)。
经过 §11.2 三方案对比(本会话拉 12 个 GCP 官方 URL + 2 个 GitHub API 验证事实),新结论:

| 方案 | v1 评估 | v2 重新评估 | 本仓库 v2 决策 |
|------|---------|-----------|---------------|
| **A. Config Connector** | 一等 GCP 集成,100+ 资源 | 仍是 Google 官方,**但 1:1 映射,无抽象能力** | ❌ |
| **B. Crossplane(provider-gcp)** | 社区项目,alpha/beta 风险 | **抽象出 CompositeResource = "本仓库自己的 Platform API"**,**upbound/provider-gcp v2.6.0 已 GA** | ✅ |
| **C. Tofu/Terraform Controller** | 性能问题 | 仍是 Terraform in K8s,跟现有 `tf-modules/` 重复 | ❌ |

### 1.2 ✅ Crossplane v2 的硬事实(本会话 2026-07-08 拉取)

| 项 | 值 | 来源 |
|---|----|------|
| Crossplane core 最新 | **v2.3.3**(2026-06-22 published) | `api.github.com/repos/crossplane/crossplane/releases/latest` |
| provider-gcp canonical 仓库 | **`upbound/provider-gcp`**(2023 年 Upbound 接手 GCP provider 维护) | `api.github.com/repos/upbound/provider-gcp/releases/latest` |
| provider-gcp 最新 | **v2.6.0**(2026-06-11 published) | 同上 |
| provider-gcp deprecated 仓库 | `crossplane-contrib/provider-gcp` v0.22.0(2022)— **不要用** | `api.github.com/repos/crossplane-contrib/provider-gcp/releases/latest` |
| License | Apache 2.0(全部) | GitHub |
| 资源覆盖 | 100+ GCP 服务,含 GKE / Compute / IAM / Storage / Pub/Sub / BigQuery / Cloud SQL / Cloud DNS / Secret Manager / VPC | [Upbound Marketplace](https://marketplace.upbound.io/providers/upbound/provider-family-gcp) |

### 1.3 ❌ Config Connector 在 v2 落选的核心原因

> 上一版 §11 把 Config Connector 推为"Google 官方 K8s operator = 最稳",**这个判断只对了一半**。Config Connector 稳,但它**只做 1:1 资源映射**,没有抽象能力。

**关键差异:**

| 能力 | Config Connector | Crossplane |
|------|-----------------|-----------|
| 1:1 资源映射 | ✅ StorageBucket → GCS bucket | ✅ Bucket → GCS bucket |
| **抽象出 Platform API** | ❌ 不能 | ✅ `XProject` XR + Composition 拼装多资源 |
| **跨项目协调** | ⚠️ namespace annotation,扁平 | ✅ CompositeResource 嵌套 + 自动 dependency |
| **批量管理** | ⚠️ 写 5 个 K8s YAML | ✅ 1 个 XR + Composition 模板,生成 N 个 MR |
| **运行时校验 schema** | ✅ K8s CRD | ✅ K8s CRD + XRD 自定义 schema |
| **多云/混合云** | ❌ 仅 GCP | ✅ AWS / Azure / 任意 provider |
| **对 owner 的体验** | "我直接写 GCP 资源" | "我写本仓库自己的抽象,Composition 帮我落地" |

**❓ 真实场景印证:** 本仓库 5 region × 4 purpose(core/data/net/log)= 20 个 Project。
- 用 Config Connector:每 Project 写 ~10 个 K8s YAML = 200 个 YAML,人工维护一致性
- 用 Crossplane:**1 个 `XProject` XRD + 1 个 Composition = 1 次定义**,apply 20 个 XR → 自动生成 200 个 MR

**本仓库 v2 选 B 的 5 条硬理由:**

1. **抽象能力 = 5 region × N Project 的可维护性核心** — 1 个 XR 比 10 个原始 YAML 容易 review
2. **Platform API = 未来 SRE 团队的"自助服务"基础** — 别人可以 `kubectl apply -f xproject.yaml` 自动落地全套 infra
3. **multi-region 协调有 first-class 支持** — CompositeResource 的 `crossResourceRefs` 显式表达跨 region 依赖
4. **schema 校验 = 防错** — XRD 自定义 schema,写错字段直接 reject,比 Config Connector "apply 看 status" 反馈快
5. **upbound/provider-gcp v2.6.0 已 GA** — 社区项目顾虑可以放下

### 1.4 Crossplane + GCP Family 的全名含义

**"Crossplane + GCP Family"** = 完整的方案名,包含 3 个组件:

| 组件 | 角色 | 落地 |
|------|------|------|
| **Crossplane core** v2.3.3 | K8s extension,把 K8s 变成通用控制平面 | 装在 hub GKE(`foundation/gke/hub-cluster.yaml`) |
| **upbound/provider-gcp** v2.6.0 | GCP resources 的"声明式 API" | `kubectl apply Provider`,装在 hub GKE |
| **GCP Family** | 本仓库自定义的 CompositeResource 集合(`XProject` `XRegionFolder` `XDataPlane` `XLogPlane`...) | `foundation/sot/*.yaml` + `releases/<v>/manifests/*.yaml` |

> **"Family" 后缀的语义:** 来自 Upbound marketplace 的术语 — `provider-family-gcp` 是一个 **family package**,把多个 related provider 打包在一起(GCP 资源 + GCP IAM + GCP Network 等)。本仓库沿用 "Family" 命名,意思是 **"Crossplane core + provider-family-gcp + 本仓库自己的 XRD/Composition" 完整一套**。

---

## 2. 黄金准则(Golden Rules)

> 这是本仓库**最高级别**的设计约束。违反任何一条都视为破坏架构。

### GR1. **SOT 唯一性:** 每个 Project 一份 `<Project_ID>.yaml`,这是唯一真理源

```
projects/uk/caep-prod-uk-core.yaml    ← 唯一
foundation/mgmt/gke-admin-sa.yaml     ← 唯一
releases/v*/manifests/uk/*.yaml       ← 引用,不重复
tooling/*.sh                          ← 只读,不写
```

**违反 GR1 的反例:**
- ❌ 在 `releases/v*/scripts/setup.sh` 里硬编 `caep-prod-uk-core`
- ❌ 在 `tooling/sot_utils.sh` 里硬编任何 project ID
- ❌ `foundation/mgmt/gke-admin-sa.yaml` 跟 `projects/uk/...yaml` 重复定义 SA 字段

**遵守 GR1 的范例:**
- ✅ `tooling/sot_utils.sh sot_load <region> <Project_ID>` — 纯查询,不持有配置
- ✅ `releases/pfb-release-1.0.0/main.sh` 第一行就调 `sot_load` 读字段
- ✅ `projects/uk/...yaml` 引用 `foundationRefs.mgmtSA: foundation/mgmt#gke-admin-sa`

### GR2. **YAML 优先:** 所有定义都在 YAML 里完成

- 任何**结构性配置**(GCP 资源 / IAM / K8s 资源拓扑) → 必须在 YAML
- 任何**执行性胶水**(preflight / setup / verify / rollback) → 必须在 shell
- 任何**业务逻辑**(release 流程 / 协调 / 决策树) → 必须在 shell 调 YAML

**判定问题:** "这条配置放 YAML 还是 shell?"
- 答:**如果改了它需要重新 apply 才能生效,放 YAML;如果改了它只是"现在改一下不动",放 shell。**

### GR3. **Foundation 引用制:** `projects/` 不重复定义 foundation 资源

- `projects/<region>/<Project_ID>.yaml` 用 `foundationRefs:` 引用 `foundation/` 下的资源
- 不允许 `projects/uk/...yaml` 里有 SA 完整定义 — 必须 `serviceAccountRef: foundation/mgmt#gke-admin-sa`

### GR4. **Release 不删:** `releases/<v>/` 目录只增不删

- v1 的"release 目录只增不删"哲学保留
- rollback = 新建 `releases/pfb-release-1.0.0-rollback/` 目录,不是删原目录

### GR5. **入口单一:** 任何 release 只能从 `main.sh -p <Project_ID>` 进

- 不允许直接调 `releases/pfb-release-1.0.0/scripts/setup.sh`
- 不允许在 `main.sh` 之外的地方做 `kubectl apply`
- 这个约束在 main.sh 里用 `set -euo pipefail` 强制

### GR6. **Tooling 零配置:** `tooling/*.sh` 不持有任何 project / region / config

- `tooling/git_utils.sh` — 只操作 git
- `tooling/sot_utils.sh` — 只查询 YAML
- `tooling/update_ilb.sh` — 只接 `--project` 参数,值在调用方传

---

## 3. 4 层目录结构详解

### 3.1 完整目录树

```
caep-infra-gcp-release/
├── README.md                                # 本文档
├── crossplane-gcp-family-best-practices.md  # 本文件 — 主交付
├── argo-cd-release.md                       # 探索性文档(参考)
├── legacy/                                  # ⚠️ v1 备份(不删,只搬)
│   ├── readme.md
│   ├── release-v1/
│   ├── release-v2/
│   ├── common/
│   ├── tf-modules/
│   ├── requirements.md
│   ├── one-more-thing.md
│   └── ... (其他 v1 文档)
│
├── tooling/                                 # Layer 1: 工具脚本
│   ├── README.md
│   ├── git_utils.sh                         # git 操作包装
│   ├── sot_utils.sh                         # SOT 查询器(读 YAML)
│   └── update_ilb.sh                        # ILB 灰度更新
│
├── foundation/                              # Layer 2: 基础层(全 repo 共享)
│   ├── sot/                                 # Service Org Tree(Org/Folder)
│   │   ├── README.md
│   │   ├── org.yaml                         # Org Policy + Org IAM
│   │   └── folders.yaml                     # 5 region folder
│   ├── mgmt/                                # Management(SA / IAM 拓扑)
│   │   ├── README.md
│   │   ├── terraform-sa.yaml                # Crossplane automation SA
│   │   └── gke-admin-sa.yaml                # 运维手工 SA
│   └── gke/                                 # GKE 集群
│       ├── README.md
│       ├── hub-cluster.yaml                 # caep-argocd-hub
│       └── spoke-cluster-template.yaml      # 5 region spoke 模板
│
├── projects/                                # Layer 3: 工程目录(每个 Project 一个 YAML)
│   ├── README.md
│   ├── uk/
│   │   ├── caep-prod-uk-core.yaml
│   │   ├── caep-prod-uk-data.yaml
│   │   ├── caep-prod-uk-net.yaml
│   │   └── caep-prod-uk-log.yaml
│   ├── hk/
│   │   └── caep-prod-hk-core.yaml
│   ├── in/
│   │   └── caep-prod-in-core.yaml
│   ├── us/
│   │   └── caep-prod-us-core.yaml
│   └── cn/
│       └── caep-prod-cn-core.yaml           # partner 接入预留
│
└── releases/                                # Layer 4: release 目录
    ├── README.md
    ├── pfb-release-1.0.0/                   # 第 1 次 release
    │   ├── README.md
    │   ├── main.sh                          # 入口 -p <Project_ID>
    │   ├── projects.yaml                    # 涉及 Project 清单
    │   ├── scripts/
    │   │   ├── preflight.sh
    │   │   ├── setup.sh
    │   │   ├── verify.sh
    │   │   └── rollback.sh
    │   └── manifests/
    │       ├── uk/caep-prod-uk-core.yaml
    │       └── hk/caep-prod-hk-core.yaml
    └── pfb-release-2.0.0/                   # 第 2 次 release
        ├── README.md
        ├── main.sh
        ├── projects.yaml
        └── scripts/
            ├── preflight.sh
            ├── setup.sh
            ├── verify.sh
            ├── rollback.sh
            └── 123.sh
```

### 3.2 4 层的职责边界

| 层 | 职责 | 改的频率 | 改的 owner | 谁引用 |
|----|------|---------|-----------|--------|
| `tooling/` | 执行工具(读 YAML,跑命令) | 低(只加不改) | 全员 | 所有人 |
| `foundation/` | 全 repo 共享资源(Org / Folder / SA / GKE 模板) | 低(改需 PR review) | platform owner | `projects/` 引用 |
| `projects/` | 每个 Project 静态 truth | 中(新 Project / 改 config) | 业务 owner | `releases/` 引用 |
| `releases/` | 每次 release 变更历史 | 高(每次 release 增) | release owner | 终端用户 |

### 3.3 4 层的数据流(运行时)

```
releases/pfb-release-1.0.0/main.sh -p caep-prod-uk-core
   │
   ├─ source tooling/sot_utils.sh
   │  └─ sot_load uk caep-prod-uk-core
   │     └─ 读 projects/uk/caep-prod-uk-core.yaml
   │        ├─ gcp.folderID → 引用 foundation/sot/folders.yaml
   │        ├─ jumpbox.serviceAccountRef → 引用 foundation/mgmt#gke-admin-sa
   │        └─ foundationRefs.gkeTemplate → 引用 foundation/gke/spoke-cluster-template.yaml
   │
   ├─ 跑 scripts/preflight.sh
   │  └─ 用上面读到的 env 变量做检查
   │
   ├─ 跑 scripts/setup.sh
   │  └─ kubectl apply -f releases/pfb-release-1.0.0/manifests/uk/caep-prod-uk-core.yaml
   │     └─ Crossplane 看到 XProject XR → 调 Composition → 落地为 provider-gcp::*
   │
   └─ 跑 scripts/verify.sh
      └─ kubectl get managed -A  + gcloud describe
```

---

## 4. Crossplane + GCP Family 资源抽象(XRD + Composition)

### 4.1 本仓库自定义的 CompositeResource 一览

| XRD 名 | apiVersion | kind | 用途 | 定义位置 |
|--------|-----------|------|------|---------|
| `XProject` | caep.example.com/v1alpha1 | XProject | 一个 GCP Project + 它的所有相关资源 | `releases/<v>/manifests/<region>/<Project_ID>.yaml`(实参)+ `foundation/sot/`(Composition 模板) |
| `XRegionFolder` | caep.example.com/v1alpha1 | XRegionFolder | 一个 region 的 GCP folder | `foundation/sot/folders.yaml` |
| `XOrganization` | caep.example.com/v1alpha1 | XOrganization | 顶层 Org Policy 约束 | `foundation/sot/org.yaml` |
| `XDataPlane`(v2.0.0 新增) | caep.example.com/v1alpha1 | XDataPlane | Cloud SQL + BigQuery + Pub/Sub | `foundation/sot/`(待补) |
| `XLogPlane`(v2.0.0 新增) | caep.example.com/v1alpha1 | XLogPlane | Cloud Logging + Monitoring | `foundation/sot/`(待补) |

### 4.2 一个完整的 XProject 实参 + Composition 工作流

**Step 1:用户写实参(releases/pfb-release-1.0.0/manifests/uk/caep-prod-uk-core.yaml)**

```yaml
apiVersion: caep.example.com/v1alpha1
kind: XProject
metadata:
  name: caep-prod-uk-core
spec:
  # 引用 SOT,运行时 merge 进 XProject spec
  sourceOfTruthRef: projects/uk/caep-prod-uk-core.yaml
  # 本次 release 的"差异"(对比 baseline)
  changes:
    - op: apply
      resource: provider-gcp-container-cluster
      spec:
        name: caep-prod-uk-core
        location: europe-west2
        initialNodeCount: 3
```

**Step 2:用户 apply 到 hub cluster**

```bash
kubectl apply -f releases/pfb-release-1.0.0/manifests/uk/caep-prod-uk-core.yaml
```

**Step 3:Crossplane 看到 XR(`caep.example.com/v1alpha1 XProject`),按 XProject 的 Composition 展开**

**Step 4:Composition 落地为多个 ManagedResource(provider-gcp::ContainerCluster / IAMServiceAccount / etc.)**

**Step 5:upbound/provider-gcp 控制器调 GCP API,创建实际资源**

**Step 6:status reconcile 回来,XProject status = Ready + Synced**

> ⚠️ 上面 Step 1 的实参 + Step 3 的 Composition **是示例形态**,本仓库只放实参(`releases/<v>/manifests/`)和 Composition 模板(`foundation/sot/`),**XRD 定义本身未生成**(需要单独写 `foundation/sot/xproject-xrd.yaml`)。落地 PoC 阶段需补这一层。

### 4.3 落地路径(从今天开始,6-9 周)

| 阶段 | 周 | 动作 | 验证 |
|------|---|------|------|
| **Phase 0 准备** | 1-2 | (a) 装 hub GKE `caep-argocd-hub`;(b) 装 Crossplane core v2.3.3 + provider-gcp v2.6.0;(c) 装 Argo CD v3.4.4(应用层) | `kubectl get providers` 全 Running |
| **Phase 1 PoC** | 1 | (a) 写第一个 XRD `XProject`;(b) 写第一个 Composition;(c) 跑通 UK 一个 Project | `kubectl get XProject` Ready + `gcloud projects describe` 看到 Project |
| **Phase 2 扩多 region** | 2 | 4 region 并行 sync,验证 Crossplane 并发 reconcile | 4 个 region Project 同时 Ready |
| **Phase 3 批量生成** | 1-2 | 用 ApplicationSet Git Directory Generator 扫 `releases/<v>/manifests/<region>/` 自动生成 K8s 资源 | Git push → 4 region 全部 sync |
| **Phase 4 入生产** | 1 | 第一个正式 release 走完整流程 | release-v2.0.0 跑通 + CR 通过 + 7 天观察期 |

---

## 5. Branch 管理最佳实践

### 5.1 Branch 拓扑(4 层)

```
main                          ← 长期稳定,只接受已完成的 release
  │
  └── crossplane-gcp-family   ← 主开发分支(本仓库当前主用)
        │                      用途: 4 层目录结构的演进 / 新 XRD / 新 foundation 资源
        │
        ├── feature/<name>     ← 单 feature 工作分支(≤ 1 ticket)
        │                      例: feature/uk-2.0.0-data-plane
        │
        ├── release/<name>     ← 单 release 准备工作(创建 manifests/)
        │                      例: release/pfb-release-3.0.0
        │
        └── hotfix/<name>      ← PATCH 级别修复
                               例: hotfix/pfb-release-2.0.0+1
```

### 5.2 Branch 保护规则

| Branch | 保护级别 | 谁可以 push | merge 到 |
|--------|---------|-------------|---------|
| `main` | branch protection: require PR + 2 approvers + linear history | 任何人只能通过 PR | 接收 `crossplane-gcp-family` PR |
| `crossplane-gcp-family` | branch protection: require PR + 1 approver | platform owner | merge → `main`(打 tag) |
| `feature/<name>` | 无保护,本地自由 | feature owner | PR → `crossplane-gcp-family` |
| `release/<name>` | branch protection: require PR + 1 approver | release owner | merge → `crossplane-gcp-family`(打 tag) |
| `hotfix/<name>` | branch protection: require PR + 1 approver | release owner | merge → `main` + `crossplane-gcp-family` |

### 5.3 Commit 规范

**Conventional Commits 1.0.0**,被 `.git/hooks/commit-msg` 强制:

```bash
# 正确格式:
feat(projects): add caep-prod-uk-data.yaml with BigQuery config
fix(tooling/sot_utils.sh): handle YAML parsing when value is null
docs(crossplane-gcp-family-best-practices): clarify GR1 with anti-example
refactor(foundation/gke): extract machineType to XRD field
chore(legacy): archive v1 release-v1/ via git mv

# 错误格式(被 hook 拒):
add uk project
update readme
```

**release commit 推荐格式:**

```bash
release: pfb-release-1.0.0 first Crossplane end-to-end PoC
Release-As: pfb-release-1.0.0
```

### 5.4 Tag 规范

**必须 annotated tag**(轻量 tag 会被 `.git/hooks/pre-push` 拒):

```bash
# 正确
git tag -a pfb-release-1.0.0 -m "first release — UK + HK end-to-end"

# 错误
git tag pfb-release-1.0.0
```

### 5.5 工作流(完整 release 流程)

```bash
# 1) 从 main 拉新分支
git checkout main
git pull origin main
git checkout -b release/pfb-release-1.0.0

# 2) 创建 release 目录(按 §3.1 模板)
mkdir -p releases/pfb-release-1.0.0/{scripts,manifests/uk,manifests/hk}

# 3) 写 README.md / projects.yaml / main.sh / scripts/*.sh / manifests/*/*.yaml
# 4) 跑本地验证
./releases/pfb-release-1.0.0/main.sh -p caep-prod-uk-core

# 5) commit
./tooling/git_utils.sh commit "release: pfb-release-1.0.0 first PoC" --scope releases/pfb-release-1.0.0 --body "UK + HK end-to-end via Crossplane provider-gcp v2.6.0"

# 6) push + 开 PR
git push origin release/pfb-release-1.0.0
gh pr create --base crossplane-gcp-family --head release/pfb-release-1.0.0 --title "release: pfb-release-1.0.0"

# 7) 等 1 approver + CI 全绿

# 8) merge (squash)
gh pr merge --squash --delete-branch

# 9) 打 annotated tag
git checkout crossplane-gcp-family && git pull
git tag -a pfb-release-1.0.0 -m "first release"
git push origin pfb-release-1.0.0

# 10) 跑 prod 验证
./releases/pfb-release-1.0.0/main.sh -p caep-prod-uk-core

# 11) close CR(公司 CR 系统)
```

---

## 6. 与 Argo CD 的协同(本仓库用 Crossplane 但不抛弃 Argo CD)

> 这是个微妙但重要的点:本仓库 v2 选 **Crossplane** 管 GCP 资源,但 K8s workloads 仍由 **Argo CD** 管。两者的职责边界:

```
┌──────────────────────────────────────────────────────────────┐
│  GitHub: aibangjuxin/caep-infra-gcp-release                  │
│  ├── foundation/sot/    →  Crossplane XRD/Composition 模板   │
│  ├── foundation/mgmt/   →  Crossplane ManagedResource 模板   │
│  ├── foundation/gke/    →  GKE 集群 + 模板                    │
│  ├── projects/<r>/<pid>.yaml                                  │
│  │           ↓ Crossplane 读到 XProject XR                   │
│  │           ↓ Composition 展开为 provider-gcp::* MR         │
│  │           ↓ upbound/provider-gcp 调 GCP API               │
│  │           ↓ 实际创建 Project / Folder / SA / GKE          │
│  │                                                              │
│  └── releases/<v>/manifests/<r>/<pid>.yaml  →  Crossplane XR   │
│                                                              │
│  同时:                                                        │
│  K8s workloads(Deployment / Service / Ingress)               │
│  └── argocd/overlays/release-v*/<region>/  → Argo CD sync     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**职责分工:**

| 资源类型 | 管它的工具 | 为什么 |
|---------|-----------|--------|
| GCP Project / Folder / Org Policy | **Crossplane** | 这些是 GCP 资源,不是 K8s 资源 |
| GCP IAM Service Account / IAM Binding | **Crossplane** | 同上 |
| GKE Cluster / Node Pool | **Crossplane** | Crossplane 比 Argo CD 早一步把 cluster 创出来,Argo CD 才能 sync workloads |
| **K8s workloads**(Deployment / Service / Ingress / ConfigMap) | **Argo CD** | 这是 K8s 原生资源,Argo CD 的 sync 模型更成熟 |
| Kubernetes Namespace / RBAC / NetworkPolicy | **Argo CD** | K8s 原生 |

> ⚠️ **本仓库 v2 = Crossplane + Argo CD 双轨**,不是"二选一"。v1 的 `argo-cd-release.md` 探索保留(放在 `argo-cd-release.md`,不删),作为 K8s workload 层的详细设计参考。

---

## 7. Crossplane + GCP Family 的 7 条最佳实践(精炼)

> 这 7 条是从 4.3 Phase 0-4 落地路径里**反推**出来的,owner 在每次 release 时检查。

### BP1. **SOT 在 `projects/`,不在 Crossplane resources 里**

- `kubectl get XProject -o yaml` 拿到的 spec 字段是 **Crossplane 视角**,**不是 SOT**
- SOT 永远是 `projects/<region>/<Project_ID>.yaml` 那个文件本身
- 不要把 XProject spec 当 SOT 改,改完不会同步回 `projects/`

### BP2. **Composition 是模板,XR 是实例**

- `foundation/sot/` 下的 Composition YAML 是**模板**,被所有 XR 复用
- `releases/<v>/manifests/` 下的 XR 是**实例**,每次 release 改实例
- Composition 改了影响所有 XR(小心!)
- XR 改了只影响自己的那一份

### BP3. **跨 region 资源用 `crossResourceRefs` 显式表达依赖**

- UK 业务要连 HK 的 Cloud SQL → 不是 namespace annotation,是 XR 里 `crossResourceRefs` 字段
- 这给 Crossplane reconciliation 引擎明确信号:"先创建 HK Cloud SQL,再创建 UK Deployment"

### BP4. **Provider config 一次设,跨所有 XR 复用**

- `kubectl apply ProviderConfig caep-gcp` 一次,所有 `provider-gcp::*` MR 都用
- 升级 / 改 ProviderConfig 不需要重 apply XR

### BP5. **Rollback = 新建 release 目录,不删原 release**

- `releases/pfb-release-1.0.0-rollback/` 走 reverse 流程
- 跟 GR4 一致

### BP6. **敏感字段用 `Secret` 引用,不进 XR spec**

- Crossplane XR spec 进 etcd,任何人有 cluster read 权限都能看
- `gcp.credentials` / `dbPassword` 走 K8s `Secret` + Workload Identity
- **不要**把 service account key 写进 XR spec

### BP7. **每次 release 写 `manifests/` 增量,不要 reset**

- 1.0.0 的 manifests/uk/ 跟 2.0.0 的 manifests/uk/ 可以叠加
- git history 保留每次 release 的"差异"
- 这是 BP5 的补充 — 跟 SOT 单一性不矛盾(SOT 在 `projects/`,release 增量在 `releases/<v>/manifests/`)

---

## 8. 落地验证清单(每次 release 跑通后回填)

| 验证项 | 怎么验证 | 通过标准 |
|-------|---------|---------|
| SOT 唯一性 | `grep -r "caep-prod-uk-core" --include="*.yaml" .` | 只在 `projects/uk/` 出现,不在 `releases/` / `foundation/` 重复 |
| tooling 零配置 | `grep -E "caep-prod-" tooling/*.sh` | 0 命中(tooling 不持 project ID) |
| 入口单一 | `grep -r "kubectl apply" releases/*/scripts/` | 0 命中(只能 main.sh apply) |
| Tag annotated | `git for-each-ref refs/tags/pfb-release-1.0.0 --format='%(objecttype)'` | `tag`(不是 `commit`) |
| Commit 规范 | `git log --oneline | head -5` | 全是 Conventional Commits 格式 |
| Foundation 引用制 | `grep "serviceAccountRef" projects/uk/*.yaml` | 全部 `foundation/mgmt#...`,不重复定义 |
| Crossplane status | `kubectl get XProject -A` | 全 Ready + Synced |

---

## 9. ❓ 待验证 / 未深入

| 项 | 状态 | 落地前必须做 |
|----|------|------------|
| `upbound/provider-gcp` v2.6.0 实际资源数 vs v1 文档估算的 "100+" | 本会话未拉 v2.6.0 release notes 细看 | PoC 跑前先列本仓库用到的 GCP 资源,逐个验 |
| XRD `caep.example.com/v1alpha1 XProject` 完整 schema 字段 | 本仓库只放了实参 + Composition 模板,**XRD 定义本身未生成** | Phase 1 PoC 第一周补 `foundation/sot/xproject-xrd.yaml` |
| Crossplane `crossResourceRefs` 跨 region 实战表现(并发 vs 顺序 reconcile) | 本会话只看了概念 | Phase 2 4 region 并行 sync 时验证 |
| `kubectl get XProject -o yaml` 是否能反推回 `projects/<r>/<pid>.yaml` 字段 | 未验证 | 工程上重要(双向 sync);可能要写 controller 桥接 |
| 紧急 rollback 时(ProviderConfig 自身挂了)怎么办 | 未设计 | Phase 4 入生产前必须演练 |
| 多 release 并行(2.0.0 还没 merge 时开 2.0.1) | 未设计 | Phase 3 批量生成时定策略 |

---

## 10. 来源与可信度

| # | 来源 | URL | 验证 | 拉取日期 |
|---|------|-----|------|---------|
| 1 | Crossplane core v2.3.3 release | `https://api.github.com/repos/crossplane/crossplane/releases/latest` | `curl` GitHub API → tag=`v2.3.3`,published=`2026-06-22T17:32:52Z` | 2026-07-08(本会话) |
| 2 | upbound/provider-gcp v2.6.0 release | `https://api.github.com/repos/upbound/provider-gcp/releases/latest` | `curl` GitHub API → tag=`v2.6.0`,published=`2026-06-11T23:46:51Z` | 2026-07-08 |
| 3 | crossplane-contrib/provider-gcp v0.22.0 (deprecated) | `https://api.github.com/repos/crossplane-contrib/provider-gcp/releases/latest` | `curl` GitHub API → tag=`v0.22.0`,published=`2022-10-10T23:40:10Z` (2022!) | 2026-07-08 |
| 4 | Upbound marketplace(provider-family-gcp) | `https://marketplace.upbound.io/providers/upbound/provider-family-gcp` | `curl` → 200, family package 介绍 | 2026-07-08 |
| 5 | Config Connector v1.153.0(v1 推荐,本节落选依据) | `https://api.github.com/repos/GoogleCloudPlatform/k8s-config-connector/releases/latest` | `curl` → tag=`v1.153.0`,published=`2026-07-06T16:35:20Z` | 2026-07-08 |
| 6 | Argo CD v3.4.4(本节协同工具) | `https://api.github.com/repos/argoproj/argo-cd/releases/latest` | `curl` → tag=`v3.4.4`,published=`2026-06-18T09:36:37Z` | 2026-07-08 |
| 7 | 本仓库的 4 层目录结构 | `find /Users/lex/git/caep-infra-gcp-release -maxdepth 3 -type d` | 本会话实读 | 2026-07-08 |

**❓ 标记的假设:**
- `upbound/provider-gcp` 100+ 资源覆盖的**精确清单** — 本会话未拉 v2.6.0 release notes 细看,只引 marketplace 通用介绍
- `caep.example.com/v1alpha1` 这个 apiVersion 是**示例**,本仓库真正的 apiVersion 需在落地 Phase 1 决定(e.g. `infra.caep.example.com/v1`)
- Crossplane `Composition` 的 patch 字段(`patchSet` / `patches` / `connectionDetails`)本节未深入,落地 Phase 1 必须读 [Crossplane Composition 文档](https://docs.crossplane.io/v2.3/concepts/compositions/)

---

## 11. 一句话总结

> **本仓库 v2 = Crossplane(upbound/provider-gcp v2.6.0) + Argo CD v3.4.4 双轨 GitOps**,4 层目录结构(`tooling/` `foundation/` `projects/` `releases/`)以 `projects/<region>/<Project_ID>.yaml` 为 SOT 黄金准则,所有定义在 YAML 里完成,每次 release 一个目录走 `main.sh -p <Project_ID>` 入口,branch 拓扑 `main ← crossplane-gcp-family ← feature/* / release/* / hotfix/*` 4 层。v1 内容全部移到 `legacy/` 保留,4 个 region GKE + Config Connector 装的 CRD 体系由 Crossplane + provider-gcp 取代 `common/lib/*.sh` bash 沉淀。首次落地 PoC 预计 2-3 周(Phase 0+1),完整入生产 6-9 周(Phase 0-4)。