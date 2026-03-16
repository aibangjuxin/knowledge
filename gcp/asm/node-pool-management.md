# Master Project: GKE Node Pool Management（架构视角）

> Document Version: 1.0  
> Last Updated: 2026-03-16  
> Target Audience: Platform Engineers / SRE / Infra Team  
> Related: [`master-project-setup-mesh.md`](master-project-setup-mesh.md), [`3.md`](3.md)

本文聚焦 **Master Project 的 GKE 集群**如何做可落地、可验证、可持续演进的 **Node Pool（节点池）管理**。默认你的 Master 集群承载平台核心能力（例如 CSM/ASM、PSC/ILB Gateway、平台服务），且需要在升级、扩缩、隔离、成本之间取得平衡。

---

## 1. Goal and Constraints

### 目标（你做 Node Pool Management 要“解决什么”）

1. **可控升级**：控制 GKE 节点版本/镜像升级节奏，尽量做到无感或低风险变更。
2. **故障域隔离**：把系统组件、网关、平台服务、批处理/弹性负载分离，缩小 blast radius。
3. **容量与成本可预测**：稳定负载用稳定池，弹性负载用弹性池（甚至 Spot），避免“一个池养所有”。
4. **多租户边界强化**：为“边界组件”（例如 PSC/ILB Gateway）提供更强隔离与可观测性。

### Node Pool Management 的范围（建议明确到 Runbook）

- **创建/变更**：机型、磁盘、节点 SA、labels/taints、metadata 配置、升级策略。
- **扩缩**：手动扩缩、Cluster Autoscaler、（可选）HPA 与节点扩缩联动。
- **升级**：发布渠道、维护窗、surge 参数、blue/green pool 迁移。
- **退役**：节点 drain、旧池删除、账单与配额回收。

### 约束（生产环境默认）

- 建议 **Regional cluster + multi-zone node pool**（跨 zone），避免单 zone 故障放大。
- 需要兼容你现有的 **跨 Project 访问架构**（参见 `3.md` 的 PSC 方向），Master 集群里常见会有内部网关与平台服务。
- 假设你希望 **最小化人为操作**：用 GKE 原生能力（release channel、auto-upgrade/repair、surge upgrade、autoscaler）而不是自建复杂控制器。

### 复杂度评估

- 推荐 V1：`Moderate`（2~4 个 Node Pool，清晰职责 + 标准化升级流程）
- 如果做到“按租户独立池 + 强隔离 + 自助交付”：`Advanced / Enterprise`

---

## 2. Recommended Architecture (V1)

### V1 设计原则（架构侧的“底线”）

1. **职责分离**：至少拆分 System / Gateway / Workload。
2. **升级可迁移**：默认采用“建新池迁移（blue/green pool）”来做大版本/关键变更，而不是在同一个池上硬滚。
3. **可观测可对账**：每个池必须能从监控与账单维度被识别（labels / nodepool 名称 / 资源配额）。
4. **默认开启自愈**：`auto-repair` 开启；`auto-upgrade` 根据你的发布节奏选择开启或用 release channel+维护窗控制。

### V1 Node Pool 划分（建议最小集合）

| Node Pool | 主要承载 | 关键手段 | 备注 |
|---|---|---|---|
| `np-system` | `kube-system`、mesh/system 组件（如 istio/asm 组件的集群内控制器、DNS、监控 agent） | taint 隔离 + 为系统 Pod 加 toleration | 减少系统被业务抢占资源 |
| `np-gateway` | Internal Gateway / East-West Gateway / PSC 入口网关（承接 tenant->master 或 east-west） | taint + HPA + 多 zone | 建议与平台服务隔离，便于独立扩缩/升级 |
| `np-workload` | 平台服务（你的业务/平台 API） | autoscaling + 合理机型 | 绝大多数工作负载在这里 |
| `np-batch-spot`（可选） | 离线/批处理/可中断任务 | Spot/Preemptible + taint | 生产里非常省钱，但必须能容忍中断 |
| `np-ci`（可选） | 构建/Runner/重 IO 工具类任务 | 隔离 + 配额 | 避免 CI 抖动影响线上 |

> 不建议在 V1 里“每个租户一个 Node Pool”当作默认策略：成本高、复杂度高、碎片化严重。更合理的硬隔离通常是 **按租户拆集群**，或至少按租户拆命名空间 + 网络策略 + 边界网关。

### V1 策略矩阵（把“约定”固化，减少口头规则）

| 维度 | `np-system` | `np-gateway` | `np-workload` | `np-batch-spot` |
|---|---|---|---|---|
| autoscaling | 通常小范围 | 必须 | 必须 | 必须 |
| upgrade 策略 | `maxUnavailable=0` 优先 | `maxUnavailable=0` + `maxSurge>=1` | 视业务容忍度 | 允许更激进 |
| 节点 SA | 最小权限 | 最小权限（可与 workload 分离） | 按需 | 最小权限 |
| taint | 必须 | 必须 | 通常不打（便于默认调度） | 必须 |
| Spot | 否 | 否 | 否 | 是 |
| 典型风险 | 被业务抢资源 | 入口抖动影响全局 | 资源碎片/容量不足 | 中断/驱逐 |

---

## 3. Trade-offs and Alternatives

### 方案 A：少量标准池（推荐 V1）

- 优点：运维简单、升级路径清晰、成本可控。
- 缺点：隔离强度有限（仍是同一集群共享内核/调度面）。

### 方案 B：Node Auto-Provisioning（NAP）/ 自动建池

- 优点：弹性更强，能自动按需求创建节点池。
- 风险：池数量不可控、成本与升级策略更难治理；多租户场景容易出现“意外池”和策略漂移。
- 建议：除非你已经有完善的配额/策略与可观测性治理，否则 **V1 不建议依赖 NAP**。

### 方案 C：按租户 Node Pool（仅在有强需求时）

适用：租户需要不同的节点 SA / 不同的硬件（GPU/高内存）/ 不同的成本模型（Spot/On-demand）/ 需要在“同一集群内”做更强隔离。

代价：更多池意味着更多升级面、更多碎片、更多调度边界；建议配套准入策略（OPA/Gatekeeper）和明确的交付规范。

---

## 4. Implementation Steps

### 4.1 盘点现状（必须先做）

```bash
PROJECT_ID="master-prj"
CLUSTER_NAME="master-gke"
LOCATION="asia-east1"   # region or zone

gcloud container clusters describe "${CLUSTER_NAME}" \
  --project "${PROJECT_ID}" --location "${LOCATION}" \
  --format="yaml(releaseChannel,currentMasterVersion,workloadIdentityConfig,privateClusterConfig,autoscaling)"

gcloud container node-pools list \
  --project "${PROJECT_ID}" --location "${LOCATION}" --cluster "${CLUSTER_NAME}"

gcloud container node-pools describe "NODEPOOL_NAME" \
  --project "${PROJECT_ID}" --location "${LOCATION}" --cluster "${CLUSTER_NAME}" \
  --format="yaml(version,autoscaling,management,config.machineType,config.diskType,config.diskSizeGb,config.workloadMetadataConfig,config.oauthScopes,config.serviceAccount,upgradeSettings,networkConfig)"

kubectl get nodes -L cloud.google.com/gke-nodepool,topology.kubernetes.io/zone
kubectl get pods -A -o wide | head
```

你要输出并确认这些结论：

- 当前是否已经有 **System/Gateway/Workload** 的职责分离？
- 现有池是否 **跨 zone**（regional cluster 时尤为关键）？
- 节点池是否启用 **auto-repair**？升级策略是 **surge 还是不可用滚动**？
- Gateway/关键平台服务是否已经具备 **PDB + HPA + topology spread**？
- 集群是否在 **Release Channel**（Rapid/Regular/Stable）内？维护窗是否已设置？

### 4.2 统一命名、labels、taints（建议标准）

建议把 “池职责” 明确写到 node labels / taints，后续部署都能复用：

- Labels（用于 nodeSelector/affinity、成本对账、可观测）
  - `platform.gke/pool-role: system|gateway|workload|batch|ci`
- Taints（用于强制隔离）
  - `platform.gke/pool-role=system:NoSchedule`
  - `platform.gke/pool-role=gateway:NoSchedule`
  - `platform.gke/pool-role=batch:NoSchedule`（Spot 池常用）

### 4.3 创建 Node Pool（示例：Gateway 池）

下面示例强调：跨 zone、自动修复、可控升级、Workload Identity 元数据配置、基础安全能力。

```bash
NODEPOOL="np-gateway"

gcloud container node-pools create "${NODEPOOL}" \
  --project "${PROJECT_ID}" --location "${LOCATION}" --cluster "${CLUSTER_NAME}" \
  --machine-type "e2-standard-4" \
  --disk-type "pd-balanced" --disk-size "100" \
  --image-type "COS_CONTAINERD" \
  --num-nodes "1" \
  --enable-autoscaling --min-nodes "1" --max-nodes "10" \
  --enable-autorepair \
  --workload-metadata "GKE_METADATA" \
  --node-labels "platform.gke/pool-role=gateway" \
  --node-taints "platform.gke/pool-role=gateway:NoSchedule" \
  --max-surge-upgrade "1" --max-unavailable-upgrade "0"
```

> 机型/磁盘只是示例：网关通常更吃 **CPU/网络**，平台服务可能更吃 **内存**。建议把机型选择作为一条明确的容量设计工作（见第 6 节）。

### 4.4（可选但强建议）按职责拆分 Node Service Account

GKE 节点 SA 是“节点上所有 Pod 访问 GCP API 的底座能力”（即使你启用了 Workload Identity，也常见会有节点级组件需要访问 GCP）。为降低 blast radius，建议至少把 `np-gateway` 与 `np-workload` 的节点 SA 分开，并保证：

- 节点 SA 只拥有“节点必须的最小权限”（比如拉镜像、写日志/指标等），其余权限交给 Workload Identity 的 KSA->GSA 绑定。
- 网关池节点 SA 不要继承业务侧广泛权限，避免入口面被利用后横向扩大。

### 4.5 让关键组件“落到正确的池”

对 Gateway / System 组件，建议使用 `nodeSelector + tolerations`（或 affinity）绑定：

```yaml
spec:
  template:
    spec:
      nodeSelector:
        platform.gke/pool-role: gateway
      tolerations:
      - key: "platform.gke/pool-role"
        operator: "Equal"
        value: "gateway"
        effect: "NoSchedule"
```

你可以先从最关键的入口开始（例如承接 PSC/ILB 的 gateway deployment），逐步把 system / gateway / workload 分开，避免一次性大迁移。

### 4.6 升级与迁移（推荐生产流程）

把“节点池升级”分成两类：

1. **In-place 小升级**（风险较低）：同一池上滚动升级（配合 surge、PDB、HPA）。
2. **Blue/Green Pool 升级**（推荐用于大版本/关键变更）：新建一个目标版本/新配置的池，把 workload 迁移过去，然后删除旧池。

#### 什么时候必须用 Blue/Green pool

- GKE 小版本跨越较大、或你希望在升级前做更严格的回归验证。
- 机型/磁盘/节点 SA/关键安全参数变更（这些变更通常“原地改”风险大且不易回退）。
- 网关与系统池（入口面/控制面）——优先选择可回退的升级路径。

#### Release Channel 与升级节奏（建议）

- Master 生产集群建议 `Regular` 或 `Stable`（选哪个取决于你对新特性的需求 vs 稳定性偏好）。
- 建一个 **canary pool**（或 canary cluster）先吃升级，再扩大范围到 gateway/workload/system。
- 推荐顺序：**控制平面先升级**（GKE 托管）→ 节点池逐个升级（先 canary，再 workload，再 gateway/system，按你的风险评估调整）。

常用迁移动作：

```bash
# 迁移前：确保 PDB/HPA 就绪，并观察容量是否足够
kubectl get pdb -A
kubectl get hpa -A

# 逐步迁移：先 cordon/drain 旧池节点（按节点池分批）
kubectl get nodes -l cloud.google.com/gke-nodepool=OLD_POOL
kubectl cordon NODE_NAME
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data --grace-period=60 --timeout=20m
```

---

## 5. Validation and Rollback

### 验证清单（最少要过的关）

- **调度验证**：Gateway/System Pod 是否只落在目标池？
  - `kubectl get pods -A -o wide | rg -n "gateway|istio|asm|kube-system"`
- **可用性验证**：升级/迁移期间，入口链路是否稳定（PSC/ILB/网关健康、错误率、P99 延迟）？
- **容量验证**：节点利用率是否健康（CPU/内存/Pod density），是否出现频繁 scale up/down 抖动？
- **故障演练**（建议）：任意一个 zone 的节点不可用时，网关/平台服务是否仍可对外提供服务？

### 回滚策略（务实、可执行）

- **Blue/Green 场景**：保留旧池不删，先把新池缩容/解除 selector，再把 selector/toleration 切回旧池；验证通过后再推进。
- **In-place 升级场景**：如果出现异常，优先 **暂停进一步 drain**，保持存量节点；必要时新建回退池承接。

---

## 6. Reliability and Cost Optimizations

### 6.1 关键可靠性点（与 Node Pool 强相关）

- **PDB**：所有关键服务必须有 PDB，否则任何 drain 都可能造成不可控中断。
- **Topology Spread / Anti-Affinity**：网关和关键平台服务要求跨 zone 分布，避免集中在单 zone。
- **升级参数**：关键池建议 `maxUnavailable=0` + 合理 `maxSurge`（但注意配额与成本瞬时上升）。
- **系统资源保留**：为 system/gateway/workload 设置 requests/limits，避免节点饥饿导致级联故障。

### 6.2 安全基线（Node Pool 维度最容易被忽略但很关键）

- **Workload Identity**：默认启用，并把业务访问 GCP 的权限从“节点 SA”迁移到 “KSA->GSA”。
- **节点元数据访问**：使用 `--workload-metadata=GKE_METADATA`（避免旧式 metadata 模式带来的风险与不一致）。
- **镜像与节点 OS**：保持一致的 `image-type`（例如 `COS_CONTAINERD`），并把镜像升级纳入升级流程（不要“混跑”太久）。
- **最小权限节点 SA**：至少把入口网关（`np-gateway`）从业务池权限中隔离出来。

### 6.3 成本优化抓手（优先 GCP 原生）

- **稳定池（system/gateway/workload）**：结合承诺折扣（CUD）或 Reservation 做成本可预测。
- **弹性池（batch/ci）**：优先用 Spot，并配合容忍中断的作业策略（重试/幂等/队列）。
- **优化 Pod density**：不要为了“少节点”把 Pod 密到极限；通常需要在密度与可靠性之间做约束（尤其是网关类服务）。

---

## 7. Handoff Checklist（交付给团队的落地清单）

1. Node Pool 划分完成：`np-system` / `np-gateway` / `np-workload`（可选 `np-batch-spot` / `np-ci`）。
2. 所有关键 Deployment/DaemonSet：
   - 有 PDB（关键服务）
   - 有 HPA（入口与核心服务建议）
   - 有 topology spread / anti-affinity（跨 zone）
   - 有明确的 nodeSelector/affinity + tolerations（system/gateway）
3. 升级策略文档化：
   - 哪些变更走 in-place
   - 哪些变更必须 blue/green pool
   - 维护窗与变更窗口（Change window）
4. 监控与告警就绪：
   - 节点池 CPU/内存利用率、节点 NotReady、升级事件
   - 网关 QPS、错误率、P99、后端健康
5. 回滚预案可执行：保留旧池、明确切回步骤、明确验证指标。
