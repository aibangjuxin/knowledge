# GKE PV 资源创建 → Pod 挂载

> **文档已拆分**：本文档已拆分为两篇专注文档，建议根据需求直接阅读对应章节。

## 文档导航

| 需求 | 跳转 |
|------|------|
| PVC 是怎么变成 GCP PD 的？Pod 怎么挂上去的？ | → [gke-pv-provisioning-flow.md](./gke-pv-provisioning-flow.md) |
| 多租户场景下怎么隔离、计费、配额？ | → [gke-pv-multi-tenant-design.md](./gke-pv-multi-tenant-design.md) |
| StorageClass 怎么选、Gatekeeper allowlist 怎么配 | → [gke-pv-storageclass-choice.md](./gke-pv-storageclass-choice.md) |

---

## 核心概念速查

### 存储层级

```
Pod (Layer 5) → PVC (Layer 3) → PV (Layer 2) → GCP PD (Layer 1)
```

- **PVC / Pod**：namespace-scoped，业务方操作
- **PV / SC**：cluster-scoped，平台管理
- **GCP PD**：GCP 资源，存活在 master project，不依赖 Pod 生命周期

### StorageClass 本质

SC 是"工厂模板"（盘类型、regional/zonal、reclaimPolicy），**不是存储单元**，**不携带 tenant 归属**。归属靠 PD labels + per-tenant KMS key。

### 多租户隔离机制

| 隔离维度 | 手段 |
|---------|------|
| 谁能用哪些 SC | Tenant CRD.spec.scAllowlist + ValidatingWebhook |
| 谁能看到谁的盘 | namespace RBAC（PVC 天然 namespace-scoped） |
| 数据加密隔离 | Per-tenant KMS CMEK（Custom Provisioner 注入） |
| 容量配额 | Tenant CRD.spec.quota，跨 namespace 聚合 |
| 计费归因 | PD GCP labels → BigQuery billing export |

### 关键设计决策

1. **SC 命名只用性能档**：`prod-db-ssd`，不加 `tnt-001-` 前缀
2. **KMS key 按 tenant 独立**：不在 SC 里 hardcode，由 Custom Provisioner 动态注入
3. **Tenant CRD 是 Single Source of Truth**：webhook / quota / RBAC 都从 CRD 读
4. **Single master project**：不做 per-tenant project，靠 labels + BigQuery 归因

---

## 快速问答

**Q: 3 个用户各申请 500G，资源池里实际有几块盘？**  
A: 3 块真实的 GCP Persistent Disk，各 500Gi，各自独立，**全部落在同一个 master project 里**。

具体来说：

```
同一个 master project 里的磁盘表（gcloud compute disks list）:

  DISK NAME       SIZE_GB   TYPE      ZONE              TAGS/LABELS
  pvc-<uid-A>     500       pd-ssd    asia-southeast1-a  tenant=tnt-001, api=api-prod-app
  pvc-<uid-B>     500       pd-ssd    asia-southeast1-b  tenant=tnt-002, api=api-prod-app
  pvc-<uid-C>     500       pd-ssd    asia-southeast1-a  tenant=tnt-003, api=api-prod-app

  总计: 3 块盘，1500Gi，全部在 master project
```

- **物理上隔离**：每块 PD 有独立的 `selfLink`（`projects/{project}/zones/{zone}/disks/{name}`），互不干扰。用户 A 的 Pod 读写的是 `pvc-<uid-A>`，绝对碰不到 `pvc-<uid-B>` 或 `pvc-<uid-C>`。
- **逻辑上归属**：靠 PD 上的 GCP labels（`tenant`、`api` 等）和 per-tenant KMS key 来区分"谁是这盘的主人"。
- **扩容互不影响**：用户 A 把自己的盘扩到 1Ti，用户 B/C 完全不受影响，各自独立。

如果有第 4 个、第 5 个 API 用户以同样的配置接入，就在这个 master project 里继续追加独立的新磁盘。**不会因为多了用户而"合并"或"共享"已有的盘**，每个用户的存储空间就是他们自己那 N × 500Gi。

**Q: 能不能用一个 SC 实现租户隔离？**  
A: 不能。SC 是 cluster-scoped 模板，不提供 quota / 归属能力。隔离靠 namespace + PD labels + KMS。

**Q: 删 PVC 时 PD 会自动删吗？**  
A: 取决于 SC 的 `reclaimPolicy`：`Delete` = 自动删；`Retain` = 保留（需手动清理）。

---

## 相关文档

- [gke-pv-provisioning-flow.md](./gke-pv-provisioning-flow.md) — 技术链路
- [gke-pv-multi-tenant-design.md](./gke-pv-multi-tenant-design.md) — 多租户设计
- [gke-pv-storageclass-choice.md](./gke-pv-storageclass-choice.md) — SC 选型
- [../cost/gke-cost-allocations.md](../cost/gke-cost-allocations.md) — 计费归因
