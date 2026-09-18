# Istio Image Tag 自动化升级方案 — SRE 常规任务设计

> **TL;DR**:
> - **目标**:把 "pilot / proxyv2 / ztunnel / install-cni image tag 升级" 从手动 `helm upgrade` 变成 **SRE 的常规自动化任务**
> - **核心工具**:**ArgoCD Image Updater**(写回 Git)或 **Flux Image Automation**(写回 Git)
> - **关键边界**:**只升 patch tag**(1.30.3 → 1.30.4),**minor 版本切换需走双 revision canary**(05 文)
> - **本场景特殊点**:Istio image tag 是 `1.30.3-distroless` 复合形式(版本号 + variant),automation 工具需正确解析

---

## 0. 文档定位与上下游关系

> 来源:基于本目录 `05-upgrade-strategies.md`(升级机制)+ `02-install-ambient-helm.md`(Helm 拆分)+ `12-revision-canary-mtls-compat.md`(证书兼容)

| 本篇讨论 | 上游/下游 |
|---|---|
| **本篇焦点**:常规 patch tag 自动升级(SRE 任务) | ← `05-upgrade-strategies.md` 讲升级机制 |
| | → `02-install-ambient-helm.md` 讲 Helm 安装 |
| **不在本篇**:minor 版本切换(1.30 → 1.31)— 那需要双 revision canary | 详见 `05-upgrade-strategies.md` §6 路径 D |
| **不在本篇**:大版本升级(1.30 → 2.x)— Istio 没大版本,只有 minor | N/A |

---

## 1. 核心问题 — 把 image tag 升级变成 SRE 常规任务

### 1.1 现状痛点(假设没有 automation)

```
T0:  Istio 1.30.3 跑着
     image tags: pilot=1.30.3-distroless, proxyv2=1.30.3-distroless,
                 ztunnel=1.30.3-distroless, install-cni=1.30.3-distroless

T1:  Istio 官方发 1.30.4(CVE fix)
     SRE 需要:
       1. 知道这件事(订阅 release / 看 CVE)
       2. 检查兼容性(05 文 §3 / release notes)
       3. 在 values.yaml 改 tag 4 个
       4. 跑 helm upgrade
       5. 监控 istiod / ztunnel pod 状态
       6. 出问题回滚

T2:  Istio 官方发 1.30.5
     重复 T1 全流程

→ 重复性高 / 易遗漏 / 不可审计
```

### 1.2 目标(SRE 自动化后)

```
T0:  Istio 1.30.3 跑着
T1:  Istio 官方发 1.30.4
     Automation 工具:
       1. 自动检测 GAR 上 1.30.4-distroless tag
       2. 自动写回 values.yaml(commit)
       3. ArgoCD/Flux 检测到 Git 变化 → 自动 sync
       4. Helm chart 触发 pod 滚动升级
       5. SRE 看监控确认

T2:  Istio 官方发 1.30.5
     完全自动化(同上)
```

**SRE 的工作变成**:
- 监控 / 异常处理
- 兼容性确认(手动,但自动化工具会**暂停**在写回前等 review)
- 偶尔的 manual override

---

## 2. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **Patch tag 升级** | "1.30.3 → 1.30.4 这种小幅升级" | "A patch release updates the third digit of semantic versioning (`x.y.Z`); intended for backwards-compatible bug fixes and security patches." — [Semantic Versioning](https://semver.org/) |
| **Image tag automation** | "监听 image tag 变化 → 自动写回 Git" | "Image automation controllers poll container registries for new tags matching a pattern, and when found, update the image reference either directly against the running resource or by committing back to Git." — [ArgoCD Image Updater docs](https://argo-cd.readthedocs.io/en/stable/user-guide/image_updater/) |
| **GitOps write-back** | "工具自动 commit 到 Git" | "Git write-back commits the change to the actual source repo, maintaining GitOps consistency where every deployed change traces back to a Git commit." — [ArgoCD Image Updater](https://thecloudpanda.com/blog/argocd-image-updater) |
| **`semver` strategy** | "只升同 major.minor 的最新 patch" | "SemVer: Updates to the highest allowed version within defined constraints." — [ArgoCD Image Updater docs](https://pcg.io/insights/argocd-image-updater) |
| **Distroless variant** | "基础镜像名后缀" | "The Istio images have a -distroless variant suffix; the chart's `variant` value must match the tag suffix to use the correct image variant." — [Istio ztunnel chart](https://github.com/istio/istio/blob/master/manifests/charts/ztunnel/values.yaml) |

---

## 3. 2 个候选方案对比

| 维度 | **ArgoCD Image Updater** | **Flux Image Automation** |
|---|---|---|
| **核心思路** | ArgoCD 副控制器,监听 registry → 自动写回 Git | Flux 副控制器,`ImageUpdateAutomation` CRD + `ImagePolicy` |
| **Git write-back 方式** | 直接 commit 到 Git repo(annotation 配置)| `ImageUpdateAutomation.spec.push` + Git credentials |
| **Helm values 定位** | 通过 `manifestTargets` 配置 Helm values path | 通过 YAML 注释 setter(`# {"$imagepolicy": "..."}`)|
| **策略配置** | Annotation 在 Application 上 | 独立 `ImagePolicy` + `ImageUpdateAutomation` CRD |
| **已知支持度** | ArgoCD 全平台 | Flux 全平台(GitOps Toolkit)|
| **与本场景契合** | 已有 ListenerSet + HTTPRoute,如果未来上 ArgoCD 可用 | HelmRelease 是 Flux 原生 model,需要先迁到 Flux |
| **学习曲线** | 中(annotation 多)| 中(CRD 多)|
| **本场景推荐** | ⭐⭐⭐(假设未来用 ArgoCD 部署业务)| ⭐⭐(若未来上 Flux,这是更好的选择)|

### 3.1 决定选哪个

```
你未来用什么 GitOps 工具?
  │
  ├─ ArgoCD(假设)
  │   └─ ✅ ArgoCD Image Updater
  │
  ├─ Flux
  │   └─ ✅ Flux Image Automation
  │
  ├─ 不用 GitOps,直接 Helm + CI/CD
  │   └─ ❌ Image Updater 不适用
  │      改用:CI/CD pipeline + skopeo watch + 自动 commit
  │
  └─ 还没决定
      └─ ⚠️ 推荐先选 GitOps 工具,再选 image updater
```

> 本场景**当前 dev 集群没用 GitOps**(`k8s-gateway/` 都是 `kubectl apply`),所以**本篇假设未来上 ArgoCD**(符合主流),同时给 Flux 方案作对照。

---

## 4. 方案 A:ArgoCD Image Updater(推荐)

### 4.1 架构概览

```
┌────────────────────────────────────────────────────────────────┐
│                         GAR(GCP Artifact Registry)              │
│  Image tags: pilot:1.30.3-distroless, 1.30.4-distroless, ...   │
└───────────────┬────────────────────────────────────────────────┘
                │ Image Updater controller 轮询
                ↓
┌────────────────────────────────────────────────────────────────┐
│  ArgoCD Image Updater(独立 deployment)                        │
│  - 监听 image list annotation                                   │
│  - 检测新 tag                                                  │
│  - 写回 Git commit 到 values.yaml                              │
└───────────────┬────────────────────────────────────────────────┘
                │ commit
                ↓
┌────────────────────────────────────────────────────────────────┐
│  Git repo(Istio Helm values)                                   │
│  values/istiod.yaml 的 tag 字段被更新                          │
└───────────────┬────────────────────────────────────────────────┘
                │ Git webhook / 轮询
                ↓
┌────────────────────────────────────────────────────────────────┐
│  ArgoCD Application                                            │
│  - 检测到 Git 变化 → 触发 sync                                  │
│  - Helm upgrade istiod  release                                │
└───────────────┬────────────────────────────────────────────────┘
                │ Helm upgrade
                ↓
┌────────────────────────────────────────────────────────────────┐
│  Cluster                                                       │
│  istiod Deployment pod 滚动重启                                │
│  image: pilot:1.30.4-distroless                                │
└────────────────────────────────────────────────────────────────┘
```

### 4.2 安装 Image Updater

> ArgoCD Image Updater 是独立部署,不在 ArgoCD core 内。

```bash
# 在 argocd namespace 中,通过 ArgoCD 的 sidecar 方式安装
# 或单独 helm install(推荐)

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 安装 Image Updater(需要 v1.0+ 才能用 CRD 模式,本场景要求 v1.0+)
helm upgrade --install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --version <latest>
```

### 4.3 配置 GAR registry 凭证

> GAR 用 **workload identity**(GKE 推荐)或 **Service Account JSON key**。

**方式 1:Workload Identity(推荐)**

```yaml
# Service Account for Image Updater
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-image-updater
  namespace: argocd
  annotations:
    iam.gke.io/gcp-service-account: <GSA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com
---
# IAM binding:GSA → KSA
# gcloud iam service-accounts add-iam-policy-binding ...
```

**方式 2:JSON key(传统)**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gar-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
type: Opaque
stringData:
  username: _json_key
  password: |
    { "type": "service_account", "project_id": "...", ... }
```

### 4.4 配置 ArgoCD Application 注解(Image Updater)

> **本场景有 4 个 Istio component,每个一个 Application**:
> - `istio-base` → chart `base`
> - `istiod` → chart `istiod`
> - `istio-cni` → chart `cni`
> - `ztunnel` → chart `ztunnel`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: istiod
  namespace: argocd
  annotations:
    # ── Image Updater 配置 ──
    # 列出要监听的 images(alias=imageName)
    argocd-image-updater.argoproj.io/image-list: |
      pilot=europe-west2-docker.pkg.dev/aibang-12345678-ajbx-dev/containers/pilot
    # 策略:semver(只升 patch)
    argocd-image-updater.argoproj.io/pilot.update-strategy: semver
    # 限定 tag pattern(避免误升 dev/rc tag)
    argocd-image-updater.argoproj.io/pilot.allow-tags: regexp:^1\.30\.[0-9]+-distroless$
    # Git write-back 配置
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/git-branch: main
    # 写回位置:Helm values
    argocd-image-updater.argoproj.io/pilot.helm.image-name: pilot
    argocd-image-updater.argoproj.io/pilot.helm.image-tag: tag
spec:
  project: istio
  source:
    repoURL: git@github.com:your-org/istio-helm-values.git
    targetRevision: main
    path: values/istiod/
  destination:
    server: https://kubernetes.default.svc
    namespace: istio-system
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
```

### 4.5 完整 4 个 Application 模板

| Application | image alias | chart | image-list | allow-tags |
|---|---|---|---|---|
| **istio-base** | (无 image,纯 CRD)| `base` | (留空)| N/A |
| **istiod** | `pilot` | `istiod` | `pilot=.../pilot` | `^1\.30\.[0-9]+-distroless$` |
| **istio-cni** | `install-cni` | `cni` | `install-cni=.../install-cni` | `^1\.30\.[0-9]+-distroless$` |
| **ztunnel** | `ztunnel` | `ztunnel` | `ztunnel=.../ztunnel` | `^1\.30\.[0-9]+-distroless$` |

> **注意**:每个 Application 的 `allow-tags` 限定到 1.30.x 范围,**避免误升 minor**(1.31、2.0)。

### 4.6 Git write-back 文件格式

> Image Updater 默认写到一个**独立文件** `.argocd-source-<app-name>.yaml`,ArgoCD 用它覆盖 chart values。

```yaml
# 自动生成的文件(由 Image Updater commit 到 Git repo)
# .argocd-source-istiod.yaml
helm:
  parameters:
    - name: tag
      value: 1.30.4-distroless    # ← Image Updater 自动更新
      forceString: true
```

### 4.7 完整执行流程

```
T1 自动化全流程(无 SRE 介入):

1. Istio 1.30.4 release → GAR push pilot:1.30.4-distroless

2. Image Updater 检测:
   - 每 1-2 分钟轮询 GAR
   - 匹配 allow-tags pattern ✓
   - 策略 semver 决定:1.30.4 > 1.30.3 ✓ 升

3. Image Updater 写回:
   - git commit "Image Updater: bump istiod to 1.30.4-distroless"
   - 推到 values repo main 分支

4. ArgoCD 检测 Git 变化:
   - 自动 sync
   - helm upgrade istiod release
   - values tag = 1.30.4-distroless

5. K8s 滚动升级:
   - istiod Deployment pod 替换
   - 旧 pod 终止 → 新 pod 启动

6. (可选)SRE 看监控:
   - istiod pod ready
   - 控制面 metric 正常
```

---

## 5. 方案 B:Flux Image Automation(对照方案)

### 5.1 架构概览

> Flux Image Automation 用 `ImagePolicy` + `ImageUpdateAutomation` CRD。

```text
GAR → image-reflector-controller(轮询) → image-automation-controller(写回 Git)
                                              ↓
                                    HelmRelease 自动 reconcile
```

### 5.2 HelmRelease 上加 setter

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: istiod
  namespace: istio-system
spec:
  chart:
    spec:
      chart: istiod
      version: "1.30.x"
      sourceRef:
        kind: HelmRepository
        name: istio
  values:
    global:
      hub: europe-west2-docker.pkg.dev/aibang-12345678-ajbx-dev/containers
    pilot:
      # ↓↓ setter 标记 ↓↓
      tag: 1.30.3-distroless  # {"$imagepolicy": "flux-system:istio-images:tag"}
```

### 5.3 ImagePolicy + ImageUpdateAutomation

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: istio-images
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: istio-pilot-repo
  policy:
    semver:
      range: ">=1.30.0 <1.31.0"   # 限定 1.30.x 范围
---
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: istio-automation
  namespace: flux-system
spec:
  interval: 30m
  sourceRef:
    kind: GitRepository
    name: flux-system
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxbot@example.com
        name: Flux Image Bot
      messageTemplate: "Image: update {{ .Updated.Object.spec.tag }}"
    push:
      branch: main
  update:
    path: ./clusters/dev
    strategy: Setters
```

> 来源:[Flux Image Update Guide](https://fluxcd.io/flux/guides/image-update/)

---

## 6. 关键边界与策略

### 6.1 **不允许自动升 minor 版本**

```
策略设定:allow-tags = "^1\\.30\\.[0-9]+-distroless$"

自动升:1.30.3 → 1.30.4 ✓ (同 patch line)
自动升:1.30.4 → 1.30.5 ✓
禁止升:1.30.5 → 1.31.0 ✗ (pattern 不匹配,需手动改 strategy)
```

**为什么?** minor 版本切换(如 1.30 → 1.31)是**重大变更**,可能:
- API 变更(虽然 Istio 1.30.x 内 minor 兼容性稳定)
- 配置文件 schema 变化
- 证书 / RBAC 改动
- → **必须走双 revision canary**(05 文 §6 路径 D),不能自动化

### 6.2 **distroless variant 处理**

> Istio image tag 格式:`<version>-distroless`(如 `1.30.3-distroless`)

```yaml
# ArgoCD Image Updater
argocd-image-updater.argoproj.io/pilot.allow-tags: regexp:^1\.30\.[0-9]+-distroless$
#                                                                  ^^^^^^^^^^
#                                                          variant 必须匹配

# 错误示范:不限定 variant 可能拉到 1.30.3-debug 镜像
argocd-image-updater.argoproj.io/pilot.allow-tags: regexp:^1\.30\.[0-9]+$
```

### 6.3 **同步 vs 异步**

| 模式 | 行为 | 适用 |
|---|---|---|
| **同步**(默认)| Image Updater 检测新 tag → 立即写回 Git → ArgoCD 立即 sync | dev 集群,可接受快迭代 |
| **异步(推荐)** | Image Updater 写回 Git,但 **PR 形式**(需 SRE approve)| 生产环境,审计必需 |

**异步配置**(写到 PR 形式):

```yaml
metadata:
  annotations:
    argocd-image-updater.argoproj.io/write-back-method: git:secret:argocd/git-creds
    # 写回路径用 GitHub PR API
    argocd-image-updater.argoproj.io/github-app-id: "<GITHUB_APP_ID>"
    argocd-image-updater.argoproj.io/write-back-target: pullrequest
```

> 来源:[ArgoCD Image Updater docs](https://argo-cd.readthedocs.io/en/stable/user-guide/image_updater/)

### 6.4 **多环境策略**

| 环境 | Image Updater 策略 | 备注 |
|---|---|---|
| **dev** | 完全自动(`write-back-method: git:direct`)| 失败立即回滚 |
| **staging** | 自动 PR,SRE merge 后生效 | 半自动 |
| **prod** | **手动 tag 决策**,Image Updater 只给建议 | 关键场景 |

### 6.5 **rollback 机制**

```
Image Updater 的回滚机制 = Git revert + ArgoCD sync

# 1. 看 Image Updater 历史
git log --author="argocd-image-updater" --oneline

# 2. Revert 上次自动 commit
git revert <commit-sha>

# 3. ArgoCD 自动 sync 旧版本
```

---

## 7. 本场景的具体配置清单

### 7.1 Image Updater 安装

```bash
# 在 argocd namespace 装 Image Updater
helm upgrade --install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --version 0.15.0   # 2026-09 当前 latest
```

### 7.2 4 个 Application 模板

> 见 §4.5 表格。每 Application 一个 YAML 文件,放 `apps/istio/` 目录。

### 7.3 GAR registry 认证

> 用 Workload Identity(GKE 推荐):

```bash
# 1. 创建 GSA
gcloud iam service-accounts create argocd-image-updater \
  --project=aibang-12345678-ajbx-dev

# 2. 给 GSA GAR 读权限
gcloud projects add-iam-policy-binding aibang-12345678-ajbx-dev \
  --member="serviceAccount:argocd-image-updater@aibang-12345678-ajbx-dev.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"

# 3. 允许 KSA 使用 GSA(Workload Identity binding)
gcloud iam service-accounts add-iam-policy-binding \
  argocd-image-updater@aibang-12345678-ajbx-dev.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:aibang-12345678-ajbx-dev.svc.id.goog[argocd/argocd-image-updater]"

# 4. KSA annotation
kubectl annotate serviceaccount argocd-image-updater -n argocd \
  iam.gke.io/gcp-service-account=argocd-image-updater@aibang-12345678-ajbx-dev.iam.gserviceaccount.com
```

### 7.4 监控 / 告警

```yaml
# Prometheus rules
groups:
- name: istio-image-updater
  rules:
  - alert: ImageUpdaterStale
    expr: time() - argocd_image_updater_last_run_timestamp > 600  # 10 分钟无动作
    for: 5m
    annotations:
      summary: "Image Updater 卡住,可能 GAR 凭证过期"
  - alert: ImageUpdaterNoNewTag
    expr: time() - argocd_image_updater_last_applied_commit_timestamp > 2592000  # 30 天未升
    for: 1d
    annotations:
      summary: "Image Updater 30 天未应用新 tag,可能 allow-tags pattern 太严"
```

---

## 8. 严格定义 vs 简化解释(关键限定)

| 限定 | 说明 |
|---|---|
| **不允许跨 minor 自动升** | allow-tags pattern 必须 lock 到当前 minor(如 `^1\.30\.`);minor 切换需手动 |
| **distroless 必须锁定** | allow-tags 必须带 `-distroless` 后缀 |
| **写回目标有 3 种** | `git:direct`(直接 commit)/ `git:secret` / `pullrequest`(PR 形式)|
| **Helm values path 配置** | `manifestTargets` 或 setter 必须正确指向 tag 字段 |
| **Image Updater 独立 namespace** | 默认装在 argocd namespace,但 KSA 必须有 GAR 访问权限 |
| **Workload Identity 是 GKE 推荐** | 避免 JSON key 长期存放 |

---

## 9. 决策树 — 我该用哪种方案?

```
当前 GitOps 工具?
  │
  ├─ ArgoCD
  │   └─ ✅ ArgoCD Image Updater(本篇主推)
  │
  ├─ Flux
  │   └─ ✅ Flux Image Automation(§5)
  │
  ├─ 没用 GitOps
  │   ├─ 选 ArgoCD → 上述推荐
  │   ├─ 选 Flux → 上述推荐
  │   └─ 不选 GitOps → ❌ Image Updater 不适用
  │                改用:CI/CD pipeline + skopeo watch + commit
  │
  └─ 多个工具并存
      └─ ⚠️ Image Updater 必须与 chart 渲染工具匹配
```

---

## 10. 反向:不能做什么

| 场景 | 限制 |
|---|---|
| **跨 GAR 自动迁移 image** | Image Updater 只升 tag,不能换 repo |
| **大版本 Istio 1.x → 2.x 自动升** | 不存在(目前 Istio 只 minor 演进)|
| **跨 cluster 一键升级** | 每集群独立 Image Updater |
| **自动回滚** | 没有 — Image Updater 只 commit,需要 ArgoCD sync 配合 |
| **动态改变 chart 配置** | Image Updater 只动 image tag,不动其他 values |

---

## 11. 本场景与上游文档的关系

### 11.1 与 `05-upgrade-strategies.md` 的关系

| 场景 | 05 文 | 17 文(本篇)|
|---|---|---|
| **patch tag 自动升**(1.30.3 → 1.30.4)| §4 路径 B(手动 `helm upgrade`)| ✅ **本篇主推自动化** |
| **minor 版本切换**(1.30 → 1.31)| §6 路径 D(双 revision canary)| ⚠️ **本篇明确禁止自动升** |
| **升 ztunnel 不动 istiod** | §7(独立升级组件)| ✅ **本篇 4 个独立 Application** |

### 11.2 与 `02-install-ambient-helm.md` 的关系

| 场景 | 02 文 | 17 文 |
|---|---|---|
| **Helm values 写什么** | §4.1 完整 4 个 values 文件 | §7 给出 Image Updater annotations |
| **Helm chart 来源** | `oci://gcr.io/istio-release/charts/base` 等 | 同上(Image Updater 不管 chart 来源)|

### 11.3 与 `12-revision-canary-mtls-compat.md` 的关系

| 场景 | 12 文 | 17 文 |
|---|---|---|
| **patch 升 cert 兼容性** | §1 信任链不变 | ✅ **自动 patch 升不破坏 mTLS** |
| **minor 升 cert 兼容性** | §2 trust domain 不变 | ⚠️ **本篇不允许自动升** |

---

## 12. SRE 的日常 runbook

### 12.1 日常(自动化跑着)

```
1. 早上看监控:Image Updater 健康 + 最近 commit 列表
2. 看 Prometheus:Image Updater metric
3. 看 ArgoCD UI:Applications 都是 Synced
```

### 12.2 收到 Istio 新 release 时

```
1. 看 release notes(security advisory / breaking change)
2. 决定:
   - 仅 CVE fix → 等待自动化升
   - minor 版本 → 触发双 revision canary 流程(05 文 §6)
3. 不需要手动改 values.yaml
```

### 12.3 异常处理

| 症状 | 处理 |
|---|---|
| Image Updater 写回失败 | 看 git credentials;看 Workload Identity binding |
| ArgoCD sync 失败 | 看 Application status;手动 sync 一次 |
| istiod pod CrashLoopBackOff | 立刻 `kubectl rollout undo deployment istiod`(image tag 会回到上一版)|
| ztunnel DaemonSet 异常 | `kubectl rollout undo daemonset ztunnel` |
| 多次自动升后问题 | `git revert` 上次 commit + ArgoCD sync |

---

## 13. References

### 13.1 ArgoCD Image Updater 权威来源

- [ArgoCD Image Updater docs](https://argo-cd.readthedocs.io/en/stable/user-guide/image_updater/) — 官方文档
- [ArgoCD Image Updater v1.0 CRD](https://burrell.tech/blog/argo-cd-image-updater) — 新型 `ImageUpdater` CRD
- [Automated Image Updates Guide](https://thecloudpanda.com/blog/argocd-image-updater) — write-back 详解
- [ArgoCD Image Updater Review 2026](https://devopsboys.com/blog/argocd-image-updater-review-2026) — 2026 现状
- [CI to GitOps Handoff](https://aloknecessary.in/blogs/ci-to-gitops-handoff) — Image Updater vs CI commits 对比

### 13.2 Flux Image Automation 权威来源

- [Flux Image Update Guide](https://fluxcd.io/flux/guides/image-update/) — 官方教程
- [Flux Helm Integration](https://github.com/fluxcd/flux/blob/8292179855e15370fb3d3b03135a61b54f00ae42/site/helm-integration.md) — HelmRelease setter
- [ImageUpdateAutomations CRD](https://fluxcd.io/flux/components/image/imageupdateautomations/) — CRD 字段权威

### 13.3 Istio chart 字段权威来源

- [Istio ztunnel chart values](https://github.com/istio/istio/blob/master/manifests/charts/ztunnel/values.yaml) — `tag` / `variant` 字段
- [Artifact Hub ztunnel](https://artifacthub.io/packages/helm/istio-official/ztunnel?modal=values) — 1.28-1.32 版本清单
- [Istio Release Schedule](https://istio.io/latest/news/releases/) — patch 频率(约 6-8 周一次 minor,每月 patch)

### 13.4 本目录关联文档

- `02-install-ambient-helm.md` — Helm 4 release 拆分安装
- `05-upgrade-strategies.md` — 升级机制总览(minor 切换走双 revision)
- `07-feature-status-1.30.3.md` — 1.30.x feature 状态
- `12-revision-canary-mtls-compat.md` — 双 revision mTLS 兼容
- `ADR-LOCAL-001-migrate-minimal-to-ambient.md` — Phase 3 升 1.31 走双 revision
- `PERSONAL-FOCUS-LIST.md` — Lex 个人关注清单

---

## 14. 关键认知 checklist(自测)

| # | 问题 | 答案要点 |
|---|---|---|
| 1 | **本场景用 ArgoCD Image Updater 还是 Flux Image Automation?** | 取决于 GitOps 工具选型;ArgoCD → Image Updater / Flux → Image Automation |
| 2 | **patch tag 自动升的边界?** | 只升 `^1\.30\.[0-9]+-distroless$`;minor 切换手动 |
| 3 | **GAR 凭证怎么配?** | Workload Identity(GKE 推荐)或 JSON key |
| 4 | **写回 Git 还是 PR?** | dev 直接 commit;prod 用 PR(需 SRE approve)|
| 5 | **回滚怎么做?** | `git revert` 上次 commit + ArgoCD sync |
| 6 | **distroless variant 怎么锁?** | allow-tags pattern 必须带 `-distroless` 后缀 |
| 7 | **本篇不覆盖什么?** | minor 版本切换(走 05 文 §6 双 revision canary)|

> 自测 7/7 = 已掌握;5-6 = 大部分懂;≤ 4 = 重读 §4-6

---

## 15. 总结 — 自动化升级的 4 步落地

```
Step 1: 选 GitOps 工具
   - ArgoCD(本篇主推)或 Flux
   - 本场景目前没用,Phase 2 时落地

Step 2: 装 Image Updater
   - helm install argocd-image-updater
   - 配 GAR Workload Identity

Step 3: 为 4 个 Istio component 建 Application
   - istio-base / istiod / istio-cni / ztunnel
   - 加 image-list annotations
   - allow-tags 限定 patch 范围

Step 4: 监控 + runbook
   - Prometheus rule:Image Updater 健康
   - SRE 看监控,异常处理
   - 准备回滚预案(git revert)

→ 之后 Istio patch 升级 = 零人工干预(自动 commit + ArgoCD sync + Helm upgrade)
```