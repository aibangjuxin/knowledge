# 通用控制平面：Argo CD + Crossplane + GKE

> 面向对象：刚接触云原生 / GKE 平台工程的同学
> 目标：理解"控制平面"是什么、Argo CD 和 Crossplane 各管什么、它们在 GKE 上怎么拼起来

---

## 1. 一句话定义

**通用控制平面（Universal Control Plane）= 一个专门用来"管理其他集群和其他云资源"的 Kubernetes 集群。**

在 GKE 语境里，它通常是这样一副架构：

- **GKE 集群 A（管理集群 / control plane cluster）**：只跑控制面组件，不跑业务
- **GKE 集群 B、C、D（工作负载集群）**：跑业务
- **Argo CD**：把 Git 里的 YAML 同步到工作负载集群
- **Crossplane**：把 Git 里的"意图"同步到 **GCP / AWS / Azure** 等云资源
- 两者都部署在 GKE 集群 A 上

---

## 2. 先搞懂"控制平面"这个概念

这是整篇文档的地基。

| 概念 | 控制平面（Control Plane） | 数据平面（Data Plane） |
|------|------------------------|----------------------|
| 干什么 | **做决定**：要创建什么、状态对不对、要不要纠正 | **干实事**：真正跑业务流量和计算 |
| 谁在做 | 控制器 / Operator / Reconciler | 你的 Pod、Worker、Service |
| 典型组件 | kube-apiserver、Argo CD、Crossplane、Ingress Controller | Deployment 出来的 Pod |
| 状态放哪 | etcd（K8s 集群状态） | 实际运行的进程 / 数据 |
| 特点 | 逻辑集中、要求高可用、要求被保护 | 可以横向扩、可以随时重建 |

**小白类比**：控制平面像"项目经理 + 监理"，数据平面像"施工队"。
项目经理在大楼里（管理集群），盯着施工队（工作负载集群）按图纸（Git）干活。

**为什么在 GKE 上要单独一个控制平面集群？**

1. **隔离**：管理组件（Argo CD、Crossplane）的故障不会影响业务集群
2. **权限**：管理集群持有高权限 Service Account，工作负载集群只拿最小权限
3. **多集群统一**：一套控制面管 N 个集群 + M 个云项目
4. **成本**：控制面节点可以缩容到很低（甚至按需），业务集群独立扩容

---

## 3. 三件套分工

| 组件 | 领域 | 干什么 | 管的对象 |
|------|------|--------|---------|
| **Argo CD** | 应用交付（App / Workload） | GitOps：把 Git 的 K8s YAML 同步到集群，保持一致 | Deployment、Service、Ingress、HPA… |
| **Crossplane** | 基础设施（Infrastructure） | "Kubernetes 化的 Terraform"：用 CRD 声明云资源 | VPC、Cloud SQL、GCS Bucket、IAM… |
| **GKE** | 承载层 | 跑上面两个控制器的集群 | 集群本身、节点池、Ingress、Gateway |

一句话记忆：

> **Argo CD 管"Kubernetes 里跑什么"，Crossplane 管"Kubernetes 外面有什么"。**

---

## 4. Argo CD 核心概念（够用就好）

### 4.1 两个 CRD

| CRD | 作用 | 小白理解 |
|-----|------|---------|
| `Application` | 一个同步单元：一个 Git 仓库 + 一个目录 + 一个目标集群 | "我要把 repoX 的 manifests 目录管到 clusterY" |
| `ApplicationSet` | 批量生成 `Application` 的模板 | "仓库有 20 个微服务、集群有 5 套，帮我自动生成 100 个 Application" |

### 4.2 同步（Sync）的几个动作

| 动作 | 说明 |
|------|------|
| `Auto-sync` | 自动同步（Git 改了自动 apply 到集群） |
| `Self-heal` | 自愈：集群里被人手改歪了，Argo CD 改回去（**Git 是唯一真相源**） |
| `Prune` | Git 里删掉的对象，集群里也要删 |
| `Sync Wave` | 排序：wave 0 先同步，wave 1 后同步（控制部署顺序） |
| `Hook` | 特殊操作，如 `PreSync`（同步前跑迁移 Job）、`PostSync`（同步后跑验证 Job） |
| `Sync Policy` | 手动 / 自动 / 定时 |

### 4.3 最小示例

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: payment-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/my-org/payment-api.git
    targetRevision: main
    path: k8s/overlays/prod
  destination:
    server: https://k8s.prod.example.com   # 或 name: prod-cluster
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

---

## 5. Crossplane 核心概念（够用就好）

Crossplane 的对象分三层，新手最容易混。

### 5.1 三层对象

| 层 | CRD | 说明 | 小白理解 |
|----|-----|------|---------|
| ① 组合资源 | `CompositeResource` (XR) / `CompositeResourceDefinition` (XRD) | 你自己定义的"超级资源"，由 Composition 组合出来 | "我定义一个叫 `XDatabase` 的东西，里面包含实例 + 用户 + 备份" |
| ② 组合实现 | `Composition` / `CompositionRevision` | 定义 XR 内部由哪些 ManagedResource 组成、怎么拼 | "XR 的实现蓝图" |
| ③ 实际云资源 | `ManagedResource` (MR) | 由 Provider 创建出来的、真正存在的云资源 | "一条真实的 Cloud SQL 实例" |

### 5.2 Provider 与配置

| CRD | 说明 |
|-----|------|
| `Provider` | 安装到集群里的 provider 控制器（如 provider-gcp） |
| `ProviderConfig` | 凭据配置（怎么认证 GCP） |
| `Package` / `Configuration` | Provider / XRD / Composition 的打包分发单元（来自 Upbound Marketplace） |

常用 provider：

- `provider-gcp` / `provider-family-gcp` —— 管理 GCP 资源
- `provider-kubernetes` —— 管理**其他 Kubernetes 集群**（多集群场景常用）
- `provider-aws` / `provider-azure` —— 跨云时用

### 5.3 最小示例

```yaml
# 声明一个 Cloud SQL 实例（ManagedResource）
apiVersion: database.gcp.crossplane.io/v1beta1
kind: CloudSQLInstance
metadata:
  name: orders-db
spec:
  forProvider:
    region: asia-southeast1
    databaseVersion: POSTGRES_15
    settings:
      tier: db-custom-1-3840
  providerConfigRef:
    name: gcp-provider
  writeConnectionSecretToRef:
    name: orders-db-conn
```

---

## 6. 在 GKE 上的典型形态

```text
┌─────────────────────────────────────────────────────────────┐
│  Git (单一真相源)                                           │
│  ├── manifests/     → K8s YAML                              │
│  └── infra/         → Crossplane MR / XRD / Composition    │
└───────────────┬─────────────────────────┬───────────────────┘
                │                         │
       Argo CD (pull)              Crossplane (reconcile)
                │                         │
┌───────────────▼─────────────────────────▼───────────────────┐
│  GKE 集群 A —— 管理 / 控制平面集群                          │
│  ├─ argo-cd namespace        (Argo CD server)              │
│  ├─ crossplane-system ns     (Crossplane core + providers) │
│  └─ gitops-sync / fleet 工具                                │
└───────────────┬─────────────────────────────────────────────┘
                │ Argo CD ApplicationSet / fleet API
    ┌───────────┼───────────┬───────────┐
    ▼           ▼           ▼           ▼
 集群B(生产) 集群C(生产) 集群D(测试)  集群E(客户集群)

┌─────────────────────────────────────────────────────────────┐
│  GCP 侧（由 Crossplane 管理）                                │
│  Cloud SQL · GCS Bucket · VPC / Subnet · IAM · Pub/Sub      │
└─────────────────────────────────────────────────────────────┘
```

**关键点**：

1. 管理集群用 **GKE Autopilot 或小规格 Standard + 独立节点池**，并配 **PDB + 多可用区**（控制面挂了 = 整个平台停摆）
2. 管理集群的 Service Account 走 **Workload Identity**，权限按"只管该管的"分配
3. 业务集群**不装** Argo CD / Crossplane 控制器，只被访问（Argo CD 通过 kubeconfig / fleet API；Crossplane 通过 provider-kubernetes）

---

## 7. GCP 原生优先：先看这些方案

按"优先 GCP 原生"的原则，下面这几个方案应该先被评估。

| 方案 | 是什么 | 管什么 | 优势 | 代价 |
|------|--------|--------|------|------|
| **Config Connector (KCC)** | Google 官方的 Kubernetes API for GCP | GCP 资源 | **GCP 原生**、和 Config Sync 一体、权限模型贴合 GCP IAM | 只覆盖 GCP，Provider 由 Google 维护 |
| **Config Sync** | Google 官方的 GitOps 引擎 | K8s + （配合 KCC）GCP 资源 | GCP 原生、集成 GKE Enterprise fleet、审计开箱即用 | 生态/扩展性不如 Argo CD |
| **Terraform** | 传统 IaC 标准 | GCP / 多云 | 生态最成熟、模块最多 | 不跑在 K8s 里，没有 K8s -native 的资源模型和状态展示 |
| **Cloud Deploy** | GCP 的 CD 工具 | 交付到 GKE / Cloud Run | GCP 原生、与 Cloud Build 集成、内置验证 Job | 只管"发布"，不管"全集群 GitOps" |
| **Crossplane** | 社区 K8s-native IaC | 多云 + K8s | 多云统一、Composition 能力强、Provider 生态广 | 复杂度最高，Provider 质量参差，**不是 GCP 原生** |

### 选型建议

| 你的情况 | 建议 |
|---------|------|
| 纯 GCP，团队要简单、要官方支持 | **Config Sync + Config Connector**（Argo CD 都不一定要） |
| 纯 GCP，但需要成熟的 ApplicationSet / 多集群模板能力 | **Argo CD** 管工作负载 + **Config Connector** 管 GCP 资源 |
| 多云（要管 AWS / Azure），或需要把"资源栈"抽象成自己的 CRD | **Argo CD + Crossplane** |
| 已有大量 Terraform 资产 | 保持 Terraform，用 Argo CD 只管 K8s 部分（Terraform 不必强塞进 K8s） |

> **直接的判断**："Universal Control Plane" 这个词本身带着**多云 / 多集群**的诉求。
> 如果你的实际需求只是 GCP + GKE，那么直接上 Crossplane 往往**过度工程**——
> Config Connector + Config Sync 是更短、更官方、权限模型更一致的路径。

---

## 8. 推荐 V1 架构（可落地的最小版本）

**目标：一个管理集群 + 若干工作负载集群 + GCP 资源纳管**

| 组件 | V1 选择 | 说明 |
|------|---------|------|
| 管理集群 | GKE Standard 1 集群 / 3 节点 / 多可用区 + PDB | Autopilot 也可，但控制面组件按需付费需确认配额 |
| 工作负载交付 | **Argo CD**（单集群起步）+ ApplicationSet 扩展多集群 | 成熟、生态好、UI 好用 |
| GCP 资源交付 | **Config Connector**（GCP 原生优先） | 需多云再引入 Crossplane |
| 身份 | Workload Identity 贯穿（GKE SA → GSA） | 不下发 key |
| 密钥 | Secret Manager CSI Driver + External Secrets Operator | 不把 Secret 明文放 Git |
| 可观测 | Cloud Monitoring / Logging 收集控制面指标与审计日志 | 控制面必须有 SLO |

**演进路线（V1 → V2 → V3）**

| 阶段 | 目标 | 关键动作 |
|------|------|---------|
| **V1 立即修** | 单集群能自动部署 | Argo CD 接一个 Git repo，跑通一条流水线 |
| **V2 结构改善** | 多集群统一 + GCP 资源纳管 | ApplicationSet 多集群；引入 Config Connector / Crossplane；Workload Identity 打通 |
| **V3 长期重构** | 平台即产品 | 多租户隔离（namespace + 配额）、自助服务模板、审计与合规、跨区/跨云 |

---

## 9. 风险与常见坑

| 坑 | 表现 | 规避 |
|----|------|------|
| 控制面单点 | 管理集群挂了，所有集群停止同步 | 多可用区 + PDB + 节点池冗余；控制面只放"不会挂"的核心组件 |
| Argo CD 权限过大 | 一个 Application 能删掉整个集群的资源 | 用受管 namespace / `project` 隔离 + 最小权限的 cluster role |
| Crossplane Provider 版本漂移 | Provider 升级导致 XRD 失效 | 锁版本（`Package` digest），先在测试集群验证再升级 |
| Git 里的 Secret | 明文密钥进 Git | Secret Manager + ESO；Git 里只放引用 |
| 同步风暴 | 大量 Application 同时 sync 打爆 API Server | 限速（`ConcurrentSyncs`）、分批 sync wave |
| "什么都往控制面塞" | 管理集群承载业务，隔离失效 | 控制面集群只跑控制组件；业务一律回工作负载集群 |

---

## 10. 小结

| 记住这几点 | 内容 |
|-----------|------|
| 控制平面 = 做决定的层，数据平面 = 干实事的层 | 隔离、权限、统一治理都靠这层 |
| Argo CD 管 K8s 工作负载，Crossplane 管云资源 | 一个 Application，一个 ManagedResource |
| GKE 是承载控制面的最佳位置 | 多可用区 + PDB + Workload Identity |
| GCP 原生优先 | Config Connector / Config Sync / Cloud Deploy 应先评估；Crossplane 用于真·多云场景 |
| V1 别过度设计 | 单管理集群 + Argo CD + Config Connector 已经能覆盖 80% 需求 |

**复杂度评估**：简单（单集群 Argo CD）→ 中等（+ 多集群 ApplicationSet + GCP 资源纳管）→ 高级 / 企业级（+ Crossplane 多云 + 多租户 + 审计合规）

---

## 11. 参考链接

- Argo CD 官方文档：https://argo-cd.readthedocs.io/
- Argo CD 官方安装（Argo CD 官网）：https://argo-cd.readthedocs.io/en/stable/getting_started/
- Crossplane 官方文档：https://docs.crossplane.io/
- Upbound Marketplace（GCP Provider）：https://marketplace.upbound.io/
- Config Connector 概览：https://cloud.google.com/config-connector/docs/overview
- Config Sync 概览：https://cloud.google.com/kubernetes-engine/config-sync/docs/overview
- GKE Enterprise / Fleet 概览：https://cloud.google.com/kubernetes-engine/enterprise
- Cloud Deploy 概览：https://cloud.google.com/deploy/docs
- Kubernetes Controllers 概念：https://kubernetes.io/docs/concepts/architecture/controller/
