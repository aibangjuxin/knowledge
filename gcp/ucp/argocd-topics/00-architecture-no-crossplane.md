# 00 · 总体架构与决策记录

## 1. 决策摘要

| # | 决策 | 状态 | 理由 |
|---|---|---|---|
| D1 | **不使用 Crossplane** | 已定 | 明确要求。Argo CD 保留 |
| D2 | 云资源供给改用 **K8s 原生 CRD + Operator/Controller** | 已定 | 满足"主要都是一些 K8sCR"的要求；Operator 跑在集群内，`status.conditions` 做状态机 |
| D3 | 组合/环境差异用 **Helm values / Kustomize overlay** | 已定 | Argo CD 原生渲染能力，Argo CD 之外无额外运行时依赖 |
| D4 | 逐资源鉴权用 **Workload Identity + GCP Service Account** | 已定 | 替代 Crossplane Provider 的云账号管理；K8s 原生支持 |
| D5 | Argo CD 自身的 Redis **不挂持久卷** | 已定 | 见 [`01-redis-persistence.md`](./01-redis-persistence.md) |
| D6 | 业务 Redis 改 **StatefulSet + PVC**（或 Memorystore） | 待实施 | 与 Argo CD 内部 Redis 完全无关，见同文档 |
| D7 | 禁用内置 `admin`，用 `devops-admin` 组授权 | 已定 | 两个独立动作，见 [`03-dex-ldap-sso.md`](./03-dex-ldap-sso.md) |
| D8 | 权限边界分三层（Argo CD RBAC / AppProject / K8s RBAC） | 已定 | 见 [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| D9 | 用 ApplicationSet 批量分发，**不**为每个环境手建 Application | 已定 | 见 [`05-appset.md`](./05-appset.md) |
| D10 | 集群级治理靠 **Gatekeeper Admission Webhook**，同步前检查作为补充 | 已定 | 见 [`06-opa-gatekeeper-impact.md`](./06-opa-gatekeeper-impact.md) |
| D11 | Repository / GitHub App 凭据 **声明式管理**，目标分支归 Application | 已定 | 见 [`07-repository-githubapp.md`](./07-repository-githubapp.md) |

---

## 2. 目标架构

```
                            ┌──────────────────────────────────┐
                            │           Git (单一事实源)         │
                            │  · 业务服务 manifest (Kustomize)   │
                            │  · 环境差异 (values / overlay)     │
                            │  · CRD + Operator 部署             │
                            │  · AppProject / ApplicationSet     │
                            └───────────────┬──────────────────┘
                                            │  Argo CD 拉取
                    ┌───────────────────────┴───────────────────────┐
                    │              Argo CD (GKE, 3 副本 HA)         │
                    │                                               │
                    │  argocd-server ───┐                           │
                    │  argocd-repo-server│                          │
                    │  argocd-application-controller (分片)          │
                    │  argocd-applicationset-controller             │
                    │  argocd-redis (HA: 3 master + 3 sentinel)    │
                    │  argocd-dex-server (内存库, 走 LDAP)          │
                    └───────────────────────┬───────────────────────┘
                                            │
              ┌─────────────────────────────┼──────────────────────────┐
              │                             │                          │
      ┌───────▼────────┐          ┌────────▼────────┐        ┌────────▼────────┐
      │  GKE (目标集群) │          │  GKE (目标集群)  │        │  GKE (目标集群)  │
      │  应用 namespace │          │  应用 namespace  │        │  应用 namespace  │
      │                │          │                │        │                │
      │  ┌──────────┐  │          │  ┌──────────┐  │        │  ┌──────────┐  │
      │  │ CRD 实例  │  │          │  │ CRD 实例  │  │        │  │ CRD 实例  │  │
      │  │ + Operator│ │          │  │ + Operator│ │        │  │ + Operator│ │
      │  └──────────┘  │          │  └──────────┘  │        │  └──────────┘  │
      └────────────────┘          └────────────────┘        └────────────────┘
                    ▲                                            ▲
                    │  Admission: Gatekeeper Webhook           │
                    │  (违规资源被 API Server 直接拒绝)         │
      ┌─────────────┴──────────────────────────────────────────┴─────┐
      │  IAM / Dex ──LDAP──▶ 身份源                                  │
      │  groups claim ──▶ argocd-rbac-cm ──▶ Casbin 鉴权              │
      └───────────────────────────────────────────────────────────────┘
```

### 关键数据流

1. **身份**：用户 → Argo CD → Dex → LDAP 认证 → Dex 签发 ID Token（含 `groups`）→ Argo CD 用 `groups` claim 做 Casbin 匹配
2. **交付**：ApplicationSet 从 Git 读目录 → 生成 Application → Application 渲染 Git 里的 manifest → 提交到目标集群
3. **治理**：Gatekeeper Webhook 在 API Server 接纳阶段拦截违规资源
4. **状态**：Argo CD 通过 diff 目标集群实际状态与期望状态，决定是否同步

---

## 3. 能力映射：Crossplane 移除后由谁接手

| 原 Crossplane 职责 | 接手方案 | 落地要点 |
|---|---|---|
| 定义云资源 CR（Composition / XRD） | **原生 CRD**（`apiextensions.k8s.io/v1`） | CRD 只描述 schema；控制器逻辑由 Operator 提供 |
| 组合多个资源 | **Helm values 分环境** 或 **Kustomize overlay** | Argo CD 原生渲染；Argo CD 之外无额外运行时 |
| 资源供给 / reconcile | **Operator / Controller**（Deployment 或 StatefulSet） | 状态写 `status.conditions`，Argo CD 的 health check 可读 |
| 云账号 / Provider 管理 | **Workload Identity Federation + GCP Service Account** | 每个 CRD Controller 用自己的 KSA → GSA，避免共用凭据 |
| 多集群下发 | **ApplicationSet 的 Cluster generator** | 见 [`05-appset.md`](./05-appset.md) |
| 跨集群资源编排 | Argo CD **Cluster generator** + **多集群 secret** | 目标集群注册为 `argocd.argoproj.io/secret-type: cluster` |
| 资源配额 / 治理 | **Gatekeeper / GKE Policy Controller** | 仓库已有完整资料库：[`../../gke/opa-gatekeeper/`](../../gke/opa-gatekeeper/) |
| 漂移检测与自愈 | **Argo CD `selfHeal: true`** + Gatekeeper 准入 | 两层职责不同，见 [`06-opa-gatekeeper-impact.md`](./06-opa-gatekeeper-impact.md) |
| 真正的云资源编排（**非** K8s 资源） | **Terraform Cloud / Atlantis / Config Controller** | 这类资源 Argo CD 不适合直接管，用 GitOps 化 IaC |

### 一条硬边界

> **Argo CD 只管 Kubernetes API 能创建的资源。**
> VPC、Subnet、Cloud SQL 实例、GCS Bucket 这类"集群里不存在的资源"，
> Argo CD 无法 apply，必须走 IaC 工具。这是移除 Crossplane 后最大的能力缺口，
> 替代方案是 Terraform Cloud / Atlantis，而不是硬塞给 Argo CD。

---

## 4. 组件清单与副本数

| 组件 | 类型 | 建议副本 | 说明 |
|---|---|---|---|
| `argocd-server` | Deployment | 3 | 副本数**必须**与 `ARGOCD_API_SERVER_REPLICAS` 同步改 |
| `argocd-repo-server` | Deployment | 3 | 注意 repo-server 有单实例 manifest 生成锁 |
| `argocd-application-controller` | StatefulSet | 3 | 按 `--shard` 分片，副本数变化需调整 shard |
| `argocd-dex-server` | Deployment | 1 | **内存数据库**，多副本数据可能不一致 |
| `argocd-redis` | Deployment（单实例模式） | 1 | 无 volume，见 [`01-redis-persistence.md`](./01-redis-persistence.md) |
| `redis-ha`（HA 模式） | StatefulSet + Service | 3 master + 3 sentinel | 官方 chart，见 [`02-ha.md`](./02-ha.md) |

详细约束见 [`02-ha.md`](./02-ha.md)。

---

## 5. 部署前必查项（本轮无法实查，目标集群 API 返回 403）

```bash
# 1) 集群里实际存在哪些 StorageClass（不要照抄文档里的名字）
kubectl get storageclass
#   注意：GKE 官方文档中确认存在 standard-rwo，但你的集群是否默认启用需实查

# 2) 节点池与区域（HA 的故障域设计需要）
gcloud container node-pools list --cluster <CLUSTER> --region <REGION>
gcloud container clusters describe <CLUSTER> --region <REGION> \
  --format='value(locations,currentMasterVersion,network,privateClusterConfig)'

# 3) 现有 StorageClass 的默认标记
kubectl get storageclass -o custom-columns='NAME:.metadata.name,DEFAULT:.metadata.annotations.storageclass\.kubernetes\.io/is-default-class,PROVISIONER:.provisioner,MODE:.volumeBindingMode'

# 4) 是否已装 Gatekeeper / Policy Controller
kubectl get validatingwebhookconfiguration | grep -i gatekeeper
kubectl get pods -n gatekeeper-system 2>/dev/null

# 5) Dex 的 storage 后端类型（决定是否需要额外 RBAC）
kubectl get cm argocd-cm -n argocd -o jsonpath='{.data.dex\.config}' | head -40
```

---

## 6. 风险清单

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | 禁用 `admin` 后无人能进 Argo CD | 完全锁死 | **先**验证 `devops-admin` 组映射生效，**再**禁用 admin；保留 break-glass 手段（见 [`03-dex-ldap-sso.md`](./03-dex-ldap-sso.md) §7） |
| R2 | `policy.default` 权限无法被 `deny` 收回 | 默认权限过宽 | 用最小权限 `role:authenticated` 自定义角色，不要用 `role:readonly` 当默认 |
| R3 | LDAP 组变更只在下次登录生效 | 离职/降权延迟 | 缩短 Token 生命周期 + 定期复核组成员 |
| R4 | Gatekeeper Webhook 故障导致集群写入全挂 | 业务中断 | 设 `failurePolicy: Fail` 但配 PDB + 多副本；先 `Ignore` 观察期再收紧 |
| R5 | ApplicationSet 删除级联删 Application | 业务资源被 prune | 生产环境谨慎使用 `preserveResourcesOnDeletion`；Application 先迁走再删 AppSet |
| R6 | `argocd-server` 副本数与 `ARGOCD_API_SERVER_REPLICAS` 不一致 | 登录被限流误报 | 两者必须同步改，见 [`02-ha.md`](./02-ha.md) §3 |
| R7 | 给单实例 `argocd-redis` 挂 RWO PVC | 滚动更新时挂载冲突 | 不要这么做，HA 走官方 Redis HA 拓扑 |
| R8 | 业务 Redis 从 Deployment 改 StatefulSet | 短时不可用 | 滚动迁移窗口内先 `replicas: 1` 验证，再扩副本 |

---

## 7. 关联文档

| 文档 | 内容 |
|---|---|
| [`01-redis-persistence.md`](./01-redis-persistence.md) | Redis 三分类、当前清单事实、持久化方案 |
| [`02-ha.md`](./02-ha.md) | HA 拓扑、副本约束、备份恢复 |
| [`03-dex-ldap-sso.md`](./03-dex-ldap-sso.md) | SSO 身份打通（OIDC 直连 / Dex+OIDC / Dex+LDAP）、禁用 admin、组映射 |
| [`04-appproject-rbac.md`](./04-appproject-rbac.md) | 三层权限边界 |
| [`05-appset.md`](./05-appset.md) | ApplicationSet 生成器 |
| [`06-opa-gatekeeper-impact.md`](./06-opa-gatekeeper-impact.md) | OPA 三层区分 |
| [`07-repository-githubapp.md`](./07-repository-githubapp.md) | 凭据与分支归属 |
| [`08-implementation-playbook.md`](./08-implementation-playbook.md) | 实施顺序与验收 |
| [`09-troubleshooting.md`](./09-troubleshooting.md) | 排障手册 |
