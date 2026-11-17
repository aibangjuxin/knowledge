# GKE PV 资源创建 → Pod 挂载全链路过程详解

> **范围**:本文档从「真实 GCP 资源在哪儿被创建、谁调什么 API、K8s 对象如何绑定、Pod 如何挂载」四个角度，完整走通一个 500 GiB SSD PD 从生成到 Pod 内可用的全链路。
>
> **立场**:平台工程师视角——"我作为 GCP infra 团队成员，要让业务方在 K8s 里 `kubectl apply` 一下，底层 500 GiB 的 GCP 持久化磁盘就出现在 Pod 上了，并且全过程可控、可追溯"。
>
> **多租户设计**见 [gke-pv-multi-tenant-design.md](./gke-pv-multi-tenant-design.md)；本文专注技术机制本身。

---

## 1. 一句话答案

**500 GiB 的磁盘作为 GCP Persistent Disk（PD）直接存活在 GKE 集群所在的 GCP Project 里**，由 Compute Engine API `compute.disks.create` 在特定 zone 创建，生命周期不依赖 Pod。

| 预配模式 | 谁创建 PD | K8s 哪个对象触发 |
|---------|----------|------------------|
| 静态预配 | 平台工程师手动 / Terraform apply | 无 → 直接 `kubectl apply` PV |
| **动态预配（本文重点）** | GKE control plane（PdCsi driver 调 `compute.disks.create`） | PVC 出现 → provisioner 自动创建 PV → PV 触发创建 PD |

---

## 2. 全链路 5 层栈

```
┌────────────────────────────────────────────────────────────────────┐
│ Layer 5: Pod / Deployment                   ← 业务方视角        │
│   container.volumeMounts → /data                                 │
├────────────────────────────────────────────────────────────────────┤
│ Layer 4: Pod spec.volumes[] → PVC         ← K8s 调度引用        │
│   spec.volumes[].persistentVolumeClaim.claimName: "mysql-data"   │
├────────────────────────────────────────────────────────────────────┤
│ Layer 3: PersistentVolumeClaim (PVC)       ← 业务方写，K8s 接收  │
│   spec.storageClassName: "prod-db-ssd"    ← 这是关键"选 SC"动作 │
├────────────────────────────────────────────────────────────────────┤
│ Layer 2: PersistentVolume (PV) + StorageClass (SC)               │
│   SC 决定 provisioner + 模板参数；PV 在 provision 完成后出现     │
│   spec.csi.volumeHandle 指向 PD 的 selfLink                       │
├────────────────────────────────────────────────────────────────────┤
│ Layer 1: GCP Persistent Disk (compute.disks.create)             │
│   真实资源存活在 GCP Project → Region → Zone 中                  │
└────────────────────────────────────────────────────────────────────┘
```

业务方只接触 Layer 5 和 Layer 3；Layer 1/2 由平台管理。

---

## 3. StorageClass 本质澄清

**SC 是"工厂模板"，不是存储单元。**

| SC 能做的事 | SC 不能做的事 |
|------------|--------------|
| 指定盘类型（pd-ssd / pd-standard） | 限制谁能用（无 tenant 维度） |
| 指定 regional 或 zonal | 计量 quota |
| 指定 KMS key（静态 hardcode） | 跨 tenant 隔离 |
| 指定 reclaimPolicy | 归属归因 |

**每个 SC 只定义"这张盘长什么样"，不定义"这张盘是谁的"。** 归属靠 PD labels 和 namespace 隔离。

常见误解：想用 `client-A-prod-db-ssd` 这种 SC 名来实现"按客户隔离"。这行不通，因为 SC 是 cluster-scoped（所有客户共享同一份），且 SC 数量 = 客户数 × 性能档，规模一大难以维护。正确做法见 [gke-pv-multi-tenant-design.md](./gke-pv-multi-tenant-design.md)。

---

## 4. 集群 namespace 拓扑

K8s 资源分两类：

| Scope | 含义 | 例 |
|-------|------|-----|
| **Cluster-scoped** | 整个集群一份，无 namespace 字段 | `StorageClass` / `PersistentVolume` / `Node` / `CRD` |
| **Namespace-scoped** | 必须属于某个 namespace | `Pod` / `PVC` / `Deployment` / `Service` |

> **注意**：`PersistentVolume` 是 cluster-scoped，`PersistentVolumeClaim` 是 namespace-scoped。`kubectl get pv` 不带 `-n`，`kubectl get pvc` 要带 `-n`。

### 4.1 典型 namespace 布局

```
Cluster
├── (cluster-scoped)  Cluster-wide
│   ├── StorageClass  prod-db-ssd, prod-db-hdd, dev-any, cold-arch
│   ├── PersistentVolume (由 CSI provisioner 自动创建)
│   └── CRD 定义（如 Tenant CRD）
│
├── kube-system/                         # GKE 系统组件
│   ├── gce-pd-csi-driver
│   ├── gatekeeper-system
│   └── istio-system
│
├── platform-control/                    # 平台控制面
│   ├── deployment/tenant-webhook
│   ├── deployment/tenant-provisioner
│   └── serviceaccount/
│
└── {tenant-id}-{env}-{app}/            # 业务 namespace（运行时动态创建）
    ├── pvc/
    ├── deployment/
    └── service/
```

---

## 5. 动态预配 8 步全链路

下面走完一个具体场景：**业务方在 `tnt-001-prod-app` namespace 创建 500 GiB SSD PVC，挂到 Deployment。**

### Step 1 — 平台工程师创建 StorageClass（一次性）

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: prod-db-ssd
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd
  replication-type: regional-pd
volumeBindingMode: WaitForFirstConsumer   # 延迟绑定，等 Pod 调度到节点再创建
allowVolumeExpansion: true
reclaimPolicy: Delete
```

**关键字段解释**：

- `provisioner: pd.csi.storage.gke.io` — GKE 内置 PD CSI driver，告诉 K8s"这个 SC 的盘由 GCE 来创建"
- `volumeBindingMode: WaitForFirstConsumer` — PVC 创建时不立即分配盘，等 Pod 被调度到某个节点 zone 了，才在该 zone 创建盘（regional PD 则等所有 replica 所在 zone 都确定）
- `allowVolumeExpansion: true` — 支持在线扩容（业务方 `kubectl patch pvc` 即可）

### Step 2 — 业务方创建 PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-data
  namespace: tnt-001-prod-app
  labels:
    platform.example.com/tenant-id: tnt-001
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: prod-db-ssd      # ← 引用 Step 1 的 SC
  resources:
    requests:
      storage: 500Gi
```

**此时**：
- K8s apiserver 接收 PVC，写入 etcd
- 由于 `volumeBindingMode: WaitForFirstConsumer`，K8s **不会**立即创建 PV

### Step 3 — Pod 创建，触发 VolumeBinding

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: tnt-001-prod-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-data
        persistentVolumeClaim:
          claimName: mysql-data        # ← 引用 Step 2 的 PVC
```

**此时**：
- Scheduler 发现 Pod 引用了 `mysql-data` PVC，且 PVC 的 SC 设置了 `WaitForFirstConsumer`
- Scheduler 将 Pod 调度到某节点的 zone（如 `asia-southeast1-a`）
- VolumeBinding controller 收到调度结果，在该 zone 创建 **PV** 对象

### Step 4 — CSI External Provisioner 创建 GCP PD

```
K8s control plane（VolumeBinding controller）
    │
    │ 调用 CSI RPC: ControllerCreateVolume
    ▼
GKE PD-CSI Driver（gce-pd-csi-driver, 运行在 kube-system）
    │
    │ 调用 GCP Compute Engine API
    ▼
POST https://compute.googleapis.com/compute/v1/projects/{project}/zones/{zone}/disks
Body: {
  name: "pvc-<uid>",
  sizeGb: 500,
  type: "projects/{project}/zones/{zone}/diskTypes/pd-ssd",
  labels: { "storage.gke.io/created-by": "pd.csi.storage.gke.io" }
}
    │
    ▼
GCP Persistent Disk 出现在 master project 的指定 zone
```

**PD 命名**：`pvc-<uid>`（由 K8s UID 决定，业务方不关心具体名字）。

**GCP labels**：默认只有 K8s system labels；若需 tenant 归属 label，由 Custom Provisioner 注入（见 [gke-pv-multi-tenant-design.md](./gke-pv-multi-tenant-design.md)）。

### Step 5 — PV 对象出现

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pvc-<uid>
spec:
  capacity:
    storage: 500Gi
  accessModes: ["ReadWriteOnce"]
  claimRef:
    namespace: tnt-001-prod-app
    name: mysql-data
  storageClassName: prod-db-ssd
  csi:
    driver: pd.csi.storage.gke.io
    volumeHandle: projects/{project}/zones/{zone}/disks/pvc-<uid>
    # volumeHandle 是 PD 的 GCP selfLink，CSI driver 用它找到物理盘
```

**关键**：`spec.csi.volumeHandle` 是 PV ↔ PD 的绑定锚点，格式为 `projects/{p}/zones/{z}/disks/{disk-name}`。

### Step 6 — Pod 调度到节点，CSI Driver attach 盘

```
Kubelet 收到调度到本节点的 Pod
    │
    │ 调用 CSI RPC: NodeStageVolume → NodePublishVolume
    ▼
PD-CSI Driver 调用 GCP Compute Engine API
    │
    │ POST attach
    ▼
GCP PD (pvc-<uid>) attach 到 GKE Node (VM)
    │
    ▼
Linux kernel: /dev/sdb → /mnt/data
```

**一个 PD 同一时刻只能 attach 到一个节点**（`ReadWriteOnce`）；若 Pod 迁移到另一节点，Kubelet 会先 detach 再 attach。

### Step 7 — 业务方验证

```bash
# 检查 PVC 状态
kubectl get pvc mysql-data -n tnt-001-prod-app
# NAME         STATUS   VOLUME                                     CAPACITY   ACCESS MODES
# mysql-data   Bound    pvc-<uid>                                   500Gi      RWO

# 检查 PV
kubectl get pv pvc-<uid>
# NAME         CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS
# pvc-<uid>    500Gi      RWO            Delete           Bound

# 检查 PD（在 GCP 侧）
gcloud compute disks list --zones=asia-southeast1-a
# NAME        SIZE_GB  TYPE         ZONE
# pvc-<uid>   500      pd-ssd       asia-southeast1-a

# 进入 Pod 验证挂载
kubectl exec -it mysql-xxx -n tnt-001-prod-app -- df -h /var/lib/mysql
# Filesystem                      Size  Used  Avail  Use%  Mounted on
# /dev/sdb                        500G   0    500G    0%   /var/lib/mysql
```

### Step 8 — 扩容（在线）

```bash
# 业务方在线扩容
kubectl patch pvc mysql-data -n tnt-001-prod-app \
  --type merge --patch '{"spec":{"resources":{"requests":{"storage":"1Ti"}}}}'

# K8s 触发 CSI ControllerExpandVolume → GCP PD resize
# 扩容完成后 Pod 内文件系统 resize（若用 xfs/gfs2 等支持 online resize 的文件系统）
```

**注意**：`WaitForFirstConsumer` 模式下，扩容前需 Pod 处于 Running 状态。

---

## 6. 静态预配 vs 动态预配

| 维度 | 静态预配 | 动态预配 |
|------|---------|---------|
| PD 创建者 | 平台工程师手动 `gcloud compute disks create` | CSI provisioner 自动 |
| PV 创建者 | 平台工程师手动 `kubectl apply` | K8s 自动 |
| 适合场景 | 已有盘需复用、特殊初始化 | 新建工作负载（推荐） |
| 平台工作量 | 高（每个盘都要手动管理） | 低（声明式，自动化） |
| KMS / labels 注入 | 手动指定 | Custom Provisioner 注入 |

**平台推荐**：动态预配为默认，业务方只需写 PVC；静态预配仅用于已有 PD 接管场景。

---

## 7. 快速参考

```bash
# 查看集群所有 SC
kubectl get sc

# 查看所有 PV 及绑定状态
kubectl get pv

# 查看某 namespace 的 PVC
kubectl get pvc -n <namespace>

# 查看 PVC 详情（含绑定到的 PV）
kubectl describe pvc mysql-data -n tnt-001-prod-app

# 查看 PV 对应的 GCP PD
kubectl get pv pvc-<uid> -o jsonpath='{.spec.csi.volumeHandle}'

# 在 GCP 侧查盘
gcloud compute disks list --zones=asia-southeast1-a,asia-southeast1-b

# 删除 PVC → 默认删 PD（reclaimPolicy: Delete）
# 删除前确认
kubectl get pvc -n tnt-001-prod-app
# 若 reclaimPolicy 是 Retain，删除 PVC 后 PV 会卡在 Released，PD 不会删
```

---

## 8. 常见问题

**Q: 为什么 PVC 是 Bound 状态但 Pod 启动不了？**
→ 检查 Node 是否在 PVC 所在 zone；Regional PD 需要 Pod 调度到两个 zone；确认 PD 没有 attach 到别的节点。

**Q: PD 能跨 zone 迁移吗？**
→ Regional PD 本身支持两个 zone，但迁移需要手动快照重建；K8s 不做自动迁移。

**Q: SC 的 `reclaimPolicy: Delete` 和 `Retain` 区别？**
→ `Delete`：删除 PVC 时自动删 PD（数据丢失，不可逆）。`Retain`：删除 PVC 后 PV 卡在 Released，PD 保留（数据安全，但需要手动清理）。

**Q: StatefulSet 多个副本各占一张 PD？**
→ 是的。每个 `volumeClaimTemplate` 副本对应独立 PVC → 独立 PV → 独立 PD。副本数 × 单盘容量会累加 quota。
