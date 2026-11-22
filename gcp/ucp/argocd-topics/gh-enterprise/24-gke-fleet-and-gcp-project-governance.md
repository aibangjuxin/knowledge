# 24 · GKE 集群纳管与 GCP Project 治理

> **直接回答**：「我们所有 GCP Project 的管理以后可能都要用 Argo CD 来做对应的 Control 和部署。」
> 「跨云那块 Crossplane 已经不用了，那 GCP 这一侧用什么补上？」
>
> **一句话结论**
> ★ Crossplane 停用后，GCP 侧有**三条路**：
> ① **Config Connector（CGP）** —— 把 GCP 资源变成 K8s CRD，**由 Argo CD 同步**（最"GitOps"）；
> ② **Terraform + Argo CD** —— 用 Terraform 写 GCP，Argo CD 只管"跑 Terraform"（用 hook）；
> ③ **手工 / gcloud 脚本** —— 只纳管集群与应用，Project 本身不动。
>
> ★ **强烈建议走 ③ → ① 的渐进路线**，并且：
> **只纳管"配置"（IAM、预算、服务启用、策略），不纳管"Project 的创建与删除"。**
> 理由见 `4：Project 的删除是不可逆的爆炸半径。

---

## 目录

| 章节 | 内容 |
|---|---|
| [`1](#1-先划治理边界) | 纳管什么 / 不纳管什么 |
| [`2](#2-三条路对比) | Config Connector vs Terraform vs 手工 |
| [`3](#3-config-connector-是什么) | 事实、版本、可用 CRD、身份 |
| [`4](#4-★-project-纳管的风险与护栏) | 不可逆操作清单 |
| [`5](#5-gke-集群纳管) | cluster secret、跳过 reconcile、Workload Identity |
| [`6](#6-目录结构与生成) | 与既有 gitops-layout 对齐 |
| [`7](#7-凭据模型) | 仓库凭据 vs 集群凭据 |
| [`8](#8-风险清单) | 12 条 |

---

## 1. 先划治理边界

**推荐边界**（对应 [`18 `9 Q5`](./18-framework-github-first-gitops.md)）：

| 对象 | 纳管？ | 理由 |
|---|---|---|
| **Project 的创建 / 删除** | ❌ **不纳管** | 删除 project 会连带删除其下**所有资源**（部分需 30 天回收），不可逆 |
| Project 的**标签、预算、API 启用** | ✅ 纳管 | 可逆、价值高 |
| **Folder 结构** | ⚠️ 谨慎纳管 | 层级调整影响面大；建议**只读展示 + 人工变更** |
| **IAM 绑定 / SA / WI** | ✅ 纳管 | ★ 这是最容易出错、最该进 Git 的部分 |
| **GKE 集群定义** | ⚠️ 建议**不纳管创建** | 集群创建/删除代价高；纳管"集群里的工作负载"即可 |
| **集群注册到 Argo CD** | ✅ 纳管（**只加不删**） | 见 `5 |
| 集群里的**应用与配置** | ✅ ★ **核心** | 这才是 Argo CD 的主战场 |
| **配额 / 组织策略 / Org Policy** | ⚠️ 部分纳管 | Org Policy 影响全组织，建议人工 + 审计 |

> ★ **一句话**：**Argo CD 管"配置"，人管"边界"。**
> 越靠近"资源的存在/消失"，越不要交给自动化。

---

## 2. 三条路对比

| 维度 | ① Config Connector | ② Terraform + Argo CD | ③ 手工 / gcloud |
|---|---|---|---|
| 形态 | GCP 资源 = CRD，Argo CD 直接 apply | Terraform 代码 + Argo CD 用 hook 跑 terraform | 人执行 gcloud |
| 与 Argo CD 的契合度 | ★★★★★ **原生** | ★★★☆☆（要 hook + 状态文件） | ★★☆☆☆ |
| 状态与漂移处理 | ★ 集群里就有 status | ★ 需 terraform state（后端要锁） | ❌ 无 |
| 幂等 | ✓ | ✓ | ❌ |
| 删除保护 | 有 CRD 语义，可加准入策略 | ★ terraform 生命周期可控 | ❌ |
| 学习成本 | 中（要懂 CRD 引用机制） | 中高（要管 state） | 低 |
| 适合 | **IAM、预算、服务启用、标签** | 复杂、需条件/多 provider 的场景 | Project/Cluster 本身的生灭 |

> ★ **推荐组合**：**③ 管边界 + ① 管配置 + Argo CD 管应用**。
> Terraform 只在"Config Connector 覆盖不到"的少数场景作为补充。

---

## 3. Config Connector 是什么

### 3.1 事实（**官方仓库实测**）

| 项 | 值 |
|---|---|
| 仓库 | `GoogleCloudPlatform/k8s-config-connector`（★ 1096，2026-11-21 有更新） |
| 最新 release | **v1.161.0**（2026-11-16） |
| 性质 | Google 官方的 **Kubernetes → GCP** 控制器；内部用 Terraform provider 实现，但对外是 **CRD** |
| API 组 | `cnrm.cloud.google.com`（资源多为一组） |

### 3.2 关心的几类 CRD（**源码实测**，`apis/<group>/v1beta1/`）

| 组 | Kind | 用途 |
|---|---|---|
| `resourcemanager` | **Folder**、**Project** | 组织结构、Project（★ 高危，见 `4） |
| `iam` | **IAMPolicy**、**IAMPolicyMember**、**IAMPartialPolicy**、**IAMDenyPolicy**、**IAMAuditConfig** | 权限治理 ★ 最该纳管的部分 |
| `billingbudgets` | **Budget** | 预算告警 |
| `serviceusage` | **Service** | 启用 API（`servicemanagement.googleapis.com`） |

> ★ 这四个组正好覆盖"Project 治理"的日常需求。
> **部署前验证项**：支持的资源清单会随版本变化，
> 以官方 <https://cloud.google.com/config-connector/docs/supported-resources> 为准。

### 3.3 身份

Config Connector 用 **Workload Identity** 以某个 GSA 的身份操作 GCP：

```
GSA（平台身份）──Workload Identity──▶ KSA（config-connector 在 K8s 里）
                                          │
                                          ▼
                              调用 GCP API 改 Project / IAM
```

> ★ **最小权限**：GSA 只给"要纳管的那几个 Project"的 IAM 权限，
> **不要给 org 级角色**。否则 controller 一旦被攻破，爆炸半径是整个组织。

### 3.4 一个最小例子

```yaml
apiVersion: iam.cnrm.cloud.google.com/v1beta1
kind: IAMPolicyMember
metadata:
  name: api-prod-ci-deployer
spec:
  resourceRef:
    apiGroup: resourcemanager.cnrm.cloud.google.com
    kind: Project
    externalName: my-project-prod
  role: roles/run.invoker
  member:
    serviceAccount:
      email: ci-deployer@my-project-prod.iam.gserviceaccount.com
```

> ★ 注意 `resourceRef.externalName` 这种 **"引用"** 机制：
> Config Connector 用它来表达"资源之间的依赖"，
> 也能避免"先删后建"的顺序问题（详见官方 `ConfigureResourceReferences`）。

---

## 4. ★ Project 纳管的风险与护栏

### 4.1 不可逆操作清单

| 操作 | 后果 | 能不能撤 |
|---|---|---|
| **删除 Project** | 项目内**所有资源**被删除（部分进入 30 天回收期，部分**立即不可恢复**） | 部分可恢复，但**强烈不建议依赖** |
| **删除 Folder** | 其下所有子 Folder / Project 一起没了 | 难恢复 |
| **删除 IAMPolicyMember** | 权限被收（可能是某个服务唯一的权限） | 可重新加 |
| **改 Org Policy** | 影响**整个组织** | 可改回，但期间影响面巨大 |
| **关闭 API** | 该 API 下所有资源行为异常 | 可重新启用 |

### 4.2 五条护栏（**建议全部实施**）

| 护栏 | 做法 |
|---|---|
| **G1 不在 Argo CD 里声明 Project/Folder 的删除** | 只在"创建"路径使用，**删除走人工流程**；或用 Gatekeeper 禁止这些 CRD 的 delete 操作 |
| **G2 准入拦截** | Gatekeeper 规则：对 `resourcemanager.cnrm.cloud.google.com` 的 Project/Folder，**禁止 delete**（只允许 create/update） |
| **G3 环境隔离** | 平台 Dev 的 Argo CD 只能管"非生产 Project"；生产 Project 由另一套实例管（爆炸半径分离） |
| **G4 删除走"两段式"** | 第一次提交只改标签为 `deletion-intent: true`，第二次（人工审批后）才真正删 |
| **G5 审计** | 所有 Project/Folder 的变更走 PR → CR Check → 批准；Git 历史即审计 |

### 4.3 Gatekeeper 示例（禁止删除 Project）

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDenyPolicy
metadata:
  name: deny-cnp-project-delete
spec:
  match:
    kinds:
      - apiGroups: ["resourcemanager.cnrm.cloud.google.com"]
        kinds: ["Project", "Folder"]
  validation:
    message: "GCP Project / Folder 的删除必须走人工变更流程（见 `4.2 G4）"
    denied:
      conditions:
        - key: "{{ request.operation }}"
          operator: NotEquals
          value: "DELETE"
```

> ★ 把它和 [`06-opa-gatekeeper-impact.md `5`](../06-opa-gatekeeper-impact.md) 的
> `resource.customizations` 配合：让 Argo CD 能正确显示被 Gatekeeper 拒绝的资源状态。

---

## 5. GKE 集群纳管

### 5.1 集群注册（v3 形态）

**官方保证**（上游 `docs/operator-manual/cluster-management.md` + 既有 [`07-repository-githubapp.md `6`](../07-repository-githubapp.md)）：

```bash
# CLI 注册（一次性）
argocd cluster add <context-name>

# 声明式：cluster secret（标签 argocd.argoproj.io/secret-type: cluster）
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=cluster
```

**集群 secret 的关键字段**：

| 字段 | 说明 |
|---|---|
| `server` | 目标集群 apiserver 地址 |
| `config.bearerToken` | SA token（**不推荐长期 token**） |
| `config.tlsClientConfig` | CA / 证书 / insecure |
| `project` | 该集群归属的 AppProject（★ 权限边界） |
| `name` | 集群在 Argo CD 里的名字（**destination.name** 用它） |

### 5.2 ★ "跳过 reconcile"（重要的运维开关）

**官方保证**（上游 `docs/operator-manual/cluster-management.md`）：

```bash
# 让 Argo CD 停止对某个集群的所有应用做同步（但集群仍可见）
kubectl -n argocd annotate secret <cluster-secret-name> \
  argocd.argoproj.io/skip-reconcile=true

# 恢复
kubectl -n argocd annotate secret <cluster-secret-name> \
  argocd.argoproj.io/skip-reconcile-
```

> ★ **用途**：集群要下线/维护/网络割接时，**先把流量掐掉**，
> 而不是去一个个停 Application。
> ★ 这也是"减少 GKE 压力"的**另一个开关**：临时跳过一批集群。

### 5.3 Workload Identity（Argo CD → 目标 GKE）

推荐链路：

```
Argo CD（控制面 GKE）
   │  用平台 GSA 的身份，签发目标集群的 KSA token
   ▼
目标 GKE 的 KSA（绑定目标项目的 GSA）
   │
   ▼
Argo CD 用这个身份访问目标集群 apiserver
```

**优点**：目标集群里**不存长期 token**；权限在 GCP 侧可审计、可撤销。

**风险**：Workload Identity 链路（尤其是 GKE 1.24+ 的 Workload Identity Federation）
配置繁琐，**是最容易在半夜出问题的部分**。建议：
① 先用 service account token 跑通链路；
② 再切 WI；③ 保留一个 break-glass 的静态 token（在 Secret 里，标注有效期）。

---

## 6. 目录结构与生成

与既有 [`examples/gitops-layout/`](../examples/gitops-layout/) 对齐：

```
gitops/
├── bootstrap/
│   ├── appprojects/            # 边界层（含 syncWindows）
│   ├── applicationsets/        # 生成层
│   ├── repositories/           # 仓库凭据
│   └── root-application.yaml
├── clusters/                   # ★ 集群清单（AppSet 的输入，不是 Argo CD 资源）
│   ├── dev-01/cluster.yaml
│   └── prod-01/cluster.yaml
├── gcp/                         # ★ 新增：GCP 侧配置（Config Connector CR）
│   ├── projects/
│   │   └── my-project-prod/
│   │       ├── iam-members.yaml
│   │       ├── budget.yaml
│   │       └── services.yaml
│   └── folders/
└── apps/                       # 业务应用
```

**生成逻辑**：

| 清单 | 谁生成 | 生成器 |
|---|---|---|
| 每个集群上的每个组件 | ApplicationSet | `clusters` generator + `git` generator（既有 [`05-appset.md`](../05-appset.md)） |
| 每个 Project 的 IAM/预算 | ApplicationSet（matrix：project × 资源类型） | `list` + `matrix` |
| cluster secret | **手工创建一次**（★ 不建议自动生成——它含凭据） | — |

> ★ **为什么 cluster secret 不自动生成？**
> 因为它含**凭据**（token / CA），而 Argo CD 同步的是**声明**。
> 正确做法：**cluster secret 手工创建 + 打标签 + 纳入巡检**（检查是否与集群清单一致）。
> 这正是既有 [`helm-cross-repository.md `3`](../helm-cross-repository.md) 讲的"凭据属于控制面，不属于仓库"的延伸。

---

## 7. 凭据模型

| 凭据 | 归属 | 怎么管 |
|---|---|---|
| **仓库凭据**（读 GitHub 仓库） | Argo CD 的 `Repository` CR | GitHub App 凭据（既有 [`07`](../07-repository-githubapp.md)）；私钥放 `argocd-secret` |
| **集群凭据**（写目标集群） | Argo CD 的 cluster secret | ★ **Workload Identity 优先**；退路是 SA token |
| **Config Connector 身份**（改 GCP） | CGP 的 KSA → GSA | Workload Identity |
| **通知回写 GitHub** | Notifications 的 GitHub App | 私钥放 `argocd-notifications-secret`（见 [`20 `7`](./20-argocd-webhook-and-notifications.md)） |
| **driver 的 Argo CD token** | Argo CD 服务账号 | `argocd-accounts.cd-driver`（见 [`23 `3.1`](./23-cd-driver-and-argocd-api-sync.md)） |

> ★ **一条原则**：**Git 里永远不出现凭据明文**。
> 仓库里只放"引用"（cluster 名、project id、SA email），
> 凭据一律走 Secret + 外部密钥管理（Secret Manager / SOPS / Sealed Secrets）。

---

## 8. 风险清单

| # | 坑 | 后果 | 规避 |
|---|---|---|---|
| 1 | 把 Project 的删除写进 Git | **一次性删掉整个项目** | `4.2 五条护栏 + Gatekeeper |
| 2 | 用 Config Connector 的 GSA 给 org 级角色 | 爆炸半径 = 整个组织 | GSA 只给单 Project 权限 |
| 3 | Argo CD 管 Cluster 的创建/删除 | 集群被重建 → 数据/配置丢失 | 集群生灭走人工 |
| 4 | cluster secret 里放长期 token | 凭据泄漏且难察觉 | Workload Identity；定期轮换 |
| 5 | cluster secret 与 `clusters/cluster.yaml` 不同步 | 应用指向不存在的集群 | 巡检脚本比对两者 |
| 6 | 用 `automated.prune: true` 管 GCP 侧 CR | ★ **自动删掉 IAM/预算** | GCP 侧一律不 prune |
| 7 | 把 cluster secret 放进 Git 仓库 | 凭据泄漏 | 手工创建 + 巡检 |
| 8 | 没有 `skip-reconcile` 逃生开关 | 集群维护时无法快速止血 | 记住这个注解 |
| 9 | Config Connector 版本不固定 | 升级引入 CRD 变更 | 版本固定；升级先在 dev 验证 |
| 10 | CGP 的 CRD 数量多 | API Server 压力 | 只装需要的 group（core/hub 分离安装） |
| 11 | Workload Identity 配置错误 | 半夜同步全失败 | 先静态 token 跑通再切 WI；保留 break-glass |
| 12 | 把"删除保护"寄托在 Argo CD | 保护不住（那是 provider 概念，不是 K8s） | ★ 用 Gatekeeper + 两段式删除 |

---

## 关联文档

- 上一级：[`18 总体框架`](./18-framework-github-first-gitops.md)
- 集群凭据（仓库侧）：[`07 Repository 凭据与 GitHub App`](../07-repository-githubapp.md)
- 准入护栏：[`06 OPA 与 Gatekeeper`](../06-opa-gatekeeper-impact.md)
- 仓库骨架：[`examples/gitops-layout/`](../examples/gitops-layout/README.md)
- 既有 Gatekeeper 资料（优先复用）：[`../../gke/opa-gatekeeper/`](../../../gke/opa-gatekeeper/README.md)
- 既有 GKE 运维：[`../../gke/`](../../../gke/README.md)
