# GKE PV 多租户平台设计

> **范围**:本文档承接 [gke-pv-provisioning-flow.md](./gke-pv-provisioning-flow.md)，聚焦平台侧多租户设计：从"一个 master project + 共享 PD"出发，解决"谁的盘是谁的"这个核心问题。
>
> **前置条件**:master project 共享架构（GCP 资源不按 tenant 拆 project），仅在 labels / KMS / namespace 层做逻辑隔离。

---

## 1. 设计目标

在 single master project 下，平台必须回答三个问题：

| 问题 | 答案 |
|------|------|
| **这张盘是谁的？** | GCP labels: `tenant=<tnt-id>` |
| **谁能解密这张盘？** | Per-tenant KMS key |
| **这个租户还能再申请多少？** | Quota ledger |

---

## 2. 四层映射：Customer → Tenant → SC → PD

```
Customer Account / API Key
       │
       │  API Gateway / IAM 验证
       ▼
Tenant (平台账套, 如 tnt-001)
       │  Tenant CRD 维护在 tenant-registry namespace
       │  含: customerId、quota、SC allowlist、KMS key
       ▼
StorageClass (性能档, 平台公共)
       │  SC 是"工厂模板"，多个 tenant 共享同一个 SC
       │  SC 只定义: 盘类型(pd-ssd)、regional/zonal、reclaimPolicy
       ▼
PVC (per workload, 带 tenant label)
       │  metadata.labels.platform.example.com/tenant-id: tnt-001
       ▼
PD (单 tenant 单盘, 落在 master project)
       │  GCP labels: tenant=tnt-001
       │  CMEK: tenant 专属的 KMS key
       ▼
BigQuery billing export
       │  GROUP BY labels.tenant → 月度 invoice 归因
```

**关键设计原则**：SC 不携带 tenant 信息（不用 `tnt-001-prod-db-ssd` 这种名字）；归属差异通过 webhook + Custom Provisioner 在 PVC admission 时动态注入。

---

## 3. Tenant CRD 设计

### 3.1 CRD 定义

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: tenants.platform.example.com
spec:
  group: platform.example.com
  names:
    kind: Tenant
    plural: tenants
  scope: Cluster          # Cluster-scoped CRD
---
apiVersion: platform.example.com/v1
kind: Tenant
metadata:
  name: tnt-001
  namespace: tenant-registry
spec:
  customerId: CUST-2025-0001
  displayName: "ACME Corp"
  kmsKeyResource: "projects/master-project/locations/global/keyRings/tenant-tnt-001/cryptoKeys/pd-key"
  quota:
    totalStorageGiB: 2000
    maxPdCount: 20
    maxIopsTotal: 100000
  scAllowlist:
    - prod-db-ssd
    - prod-db-hdd
  namespaces:
    - tnt-001-prod-app
    - tnt-001-dev-app
status:
  usedStorageGiB: 500
  usedPdCount: 1
  namespaces:
    - tnt-001-prod-app
    - tnt-001-dev-app
```

### 3.2 关键字段说明

| 字段 | 作用 |
|------|------|
| `spec.kmsKeyResource` | 该 tenant 所有 PD 的 CMEK |
| `spec.quota` | 聚合 quota，跨 namespace 累加 |
| `spec.scAllowlist` | 该 tenant 允许使用的 SC 白名单 |
| `status.usedStorageGiB` | 当前已用容量（由 provisioner 更新） |
| `spec.namespaces` | 该 tenant 拥有的 namespace 列表 |

**Single Source of Truth**：webhook、RBAC、quota check、provisioner **全部从 Tenant CRD 读取**，不允许手写 namespace label 反推 tenant 归属。

---

## 4. KMS 设计：Per-tenant CMEK

### 4.1 Terraform 创建 Per-tenant KMS Key

```hcl
# modules/tenant-kms/main.tf
variable "tenant_id" {}
variable "project_id" {}

resource "google_kms_key_ring" "tenant" {
  name     = "tenant-${var.tenant_id}"
  project  = var.project_id
  location = "global"
}

resource "google_kms_crypto_key" "pd" {
  name            = "pd-key"
  key_ring        = google_kms_key_ring.tenant.id
  rotation_period = "7776000s"  # 90 天轮换
}

# 授权 GKE Node SA 解密
resource "google_kms_crypto_key_iam_member" "pd_csi" {
  crypto_key_id = google_kms_crypto_key.pd.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${var.gke_node_sa_email}"
}
```

### 4.2 两种方案对比

| 维度 | 方案 A: Per-tenant KMS key ✅ | 方案 B: Shared master key |
|------|-------------------|--------------------------|
| 物理安全 | 强 — 各 tenant key 独立 | 弱 — 拿到 master key 解全部 |
| KMS 配额 | 需管理 tenant 数 × 1 把 key | 1 把，无配额压力 |
| 审计粒度 | Cloud Audit Log 精确到 tenant | 只能看 master project 全局 |
| key 误轮换影响 | 仅影响该 tenant | 所有 tenant 业务中断 |
| **推荐场景** | **生产多租户 SaaS** | 仅 PoC / 内测 |

---

## 5. Webhook + Custom Provisioner 链路

SC 的 `parameters` 是 K8s 静态字段，无法引用 CRD。因此平台在 PVC admission 链路中注入 tenant 元信息。

### 5.1 ValidatingWebhook: 4 项校验

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: validate-pvc-tenant
spec:
  enforcementAction: Deny
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["persistentvolumeclaims"]
  validations:
  # 1. PVC 必须有 tenant-id label
  - expression: "object.metadata.labels['platform.example.com/tenant-id'] != null"
    message: "PVC 必须包含 platform.example.com/tenant-id label"
  # 2. PVC 所在 namespace 必须在 Tenant CRD.spec.namespaces 中
  - expression: |
      object.metadata.namespace != null &&
      object.metadata.namespace.startsWith('tnt-')
    message: "PVC 必须在业务 namespace 中创建"
  # 3. PVC tenant-id 与 namespace tenant-id 一致（防止冒名）
  - expression: |
      object.metadata.labels['platform.example.com/tenant-id'] ==
      object.namespace.metadata.labels['platform.example.com/tenant-id']
    message: "PVC tenant-id 必须与 namespace tenant-id 一致"
  # 4. SC 必须在 Tenant CRD.spec.scAllowlist 中
  - expression: |
      object.spec.storageClassName in ['prod-db-ssd', 'prod-db-hdd']
    message: "SC 不在 Tenant 允许列表中"
```

### 5.2 Custom Provisioner: 创建 PD 时注入 tenant 信息

```go
// 自研 provisioner 伪码（替换 CSI external-provisioner sidecar）
func (p *TenantProvisioner) CreateVolume(ctx context.Context, req *csi.CreateVolumeRequest) (*csi.CreateVolumeResponse, error) {
    tenantID := req.PVC.Labels["platform.example.com/tenant-id"]
    if tenantID == "" {
        return nil, status.Error(codes.InvalidArgument, "missing tenant-id label")
    }

    tenant, err := p.registry.Get(tenantID)
    if err != nil {
        return nil, status.Error(codes.NotFound, "tenant not found")
    }

    // Quota check
    if tenant.Status.UsedStorageGiB+gi(req.CapacityRange.RequiredBytes) > tenant.Spec.Quota.TotalStorageGiB {
        return nil, status.Error(codes.ResourceExhausted, "tenant quota exceeded")
    }

    // 创建 GCP PD，带 tenant labels + CMEK
    disk, err := p.gcp.Disks.Create(ctx, &compute.Disk{
        Name: req.Name,
        SizeGb: gi(req.CapacityRange.RequiredBytes),
        Type:   "projects/master-project/zones/" + req.AllocatedZone + "/diskTypes/pd-ssd",
        Labels: map[string]string{
            "tenant":      tenantID,
            "managed-by":  "platform",
        },
        DiskEncryptionKey: &compute.CustomerEncryptionKey{
            KmsKeyName: tenant.Spec.KMSKeyResource,  // ← per-tenant CMEK
        },
    })

    // 更新 Tenant CRD status
    tenant.Status.UsedStorageGiB += gi(req.CapacityRange.RequiredBytes)
    tenant.Status.UsedPdCount++
    p.registry.Update(tenant)

    return &csi.CreateVolumeResponse{
        Volume: &csi.Volume{
            VolumeId: disk.SelfLink,
        },
    }, nil
}
```

---

## 6. Quota 管理

Tenant quota 在 **Tenant CRD** 中定义，**跨 namespace 聚合**。

```
tnt-001-prod-app    PVC: 500Gi  ─┐
tnt-001-dev-app    PVC: 300Gi  ─┼── tnt-001 totalUsed = 800Gi ≤ quota 2000Gi ✓
tnt-001-jobs-app   PVC: 0Gi    ─┘
```

| 操作 | quota 影响 |
|------|-----------|
| PVC 创建 | ✅ 预扣（provisioner 在 CreateVolume 时检查） |
| PVC 删除 | ✅ 释放（provisioner 在 DeleteVolume 后更新 CRD status） |
| PVC 扩容 | ✅ 增量检查（扩容后 ≤ quota） |
| StatefulSet 副本扩缩 | ✅ replicas × pvcSize 一起算 |

---

## 7. 计费归因

**目标**：Bill 收到 "$X 存储费用" → 一键回答 "tnt-001 $Y，tnt-002 $Z"。

### 7.1 链路

```
PD 创建时 labels: { tenant: tnt-001 }
    ↓
GCP Compute Engine 将 labels 写入 usage record
    ↓
BigQuery billing export (master project, 一次性开启)
    ↓
SQL 聚合
```

```sql
SELECT
  labels.value AS tenant_id,
  SUM(cost) AS monthly_storage_cost,
  SUM(usage.amount) AS total_gib_months
FROM `master-project.billing.gcp_billing_export_*`
WHERE service.description = "Compute Engine"
  AND sku.description LIKE "%PD%"
  AND labels.key = "tenant"
GROUP BY tenant_id
ORDER BY monthly_storage_cost DESC
```

### 7.2 必备配置

- master project 开启 **Detailed Billing Data Export to BigQuery**（一次性配置）
- Custom Provisioner 在 `compute.disks.insert` 时传 labels
- `labels.key = "tenant"`（平台统一约定，不可改）

---

## 8. 失败模式与缓解

| # | 失效模式 | 现象 | 缓解 |
|---|---------|------|------|
| 1 | **CMEK 误共享** | 平台误用 master key 给所有 tenant → 客户间加密隔离失效 | SC parameters 的 KMS 字段由 provisioner 动态注入，不允许为空 |
| 2 | **Quota 漏算** | 恶意用户跑满 project 磁盘限额 | Custom Provisioner 在 CreateVolume 前强制 quota check |
| 3 | **租户冒名** | tnt-002 ns 上 PVC 标了 `tenant: tnt-001` | ValidatingWebhook 强制 ns label = PVC label |
| 4 | **删 tenant 漏 PD** | 平台删 ns 后 regional PD 仍存在 | 删除前 `kubectl get pv -l tenant=tnt-001` 扫描；Tenant CRD finalizer 阻止删除 |
| 5 | **Quota 在高并发下超发** | 两个 PVC 并发创建都在 quota 内，但总和超了 | Provisioner 使用 Tenant CRD 的 `resourceVersion` 做乐观锁 CAS |
| 6 | **计费标签缺失** | PD 创建时 label 未注入，BigQuery 归因失败 | PD-CSI driver 必须使用 custom provisioner；上线前跑 E2E 验证脚本 |

---

## 9. 平台 Onboarding 流程

```
客户合同签订完毕
    ↓
Step 1: Platform eng 在 tenant-registry ns 创建 Tenant CRD
        - metadata.name: tnt-001
        - spec.quota, spec.scAllowlist
        ↓
Step 2: Terraform 创建 per-tenant KMS key
        - keyRing: tenant-tnt-001
        - cryptoKey: pd-key
        - IAM: GKE Node SA ← cloudkms.cryptoKeyEncrypterDecrypter
        ↓
Step 3: 更新 Tenant CRD.spec.kmsKeyResource
        ↓
Step 4: 平台 tooling 通知客户 admin（建 namespace、分配 RBAC）
        ↓
Step 5: 客户 admin 在 tnt-001-prod-app namespace 创建 PVC
        ↓
Step 6: 平台验证
        - kubectl get pvc -n tnt-001-prod-app → Bound ✓
        - gcloud compute disks describe pvc-xxx → labels.tenant=tnt-001 ✓
        - BigQuery 验证标签落地 ✓
```

---

## 10. StatefulSet 特殊处理

StatefulSet 使用 `volumeClaimTemplates`，每个副本自动生成独立 PVC。

**Quota 计算**：`replicas × pvcSize` 一起算。

```yaml
spec:
  replicas: 3
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      storageClassName: prod-db-ssd
      resources:
        requests:
          storage: 500Gi
```

→ 3 副本 × 500Gi = **1500Gi**，占 Tenant quota。

**校验点**：MutatingWebhook 应在 StatefulSet 创建时做 replicas × pvcSize 的 quota 预检，而不是等每个 PVC 逐个创建（否则可能出现前两个成功、第三个因 quota 不够而失败）。

---

## 11. 相关文档

| 文档 | 内容 |
|------|------|
| [gke-pv-provisioning-flow.md](./gke-pv-provisioning-flow.md) | 从 PVC 到 PD 的技术链路，CSI 机制，namespace 拓扑 |
| [gke-pv-storageclass-choice.md](./gke-pv-storageclass-choice.md) | StorageClass 选型，Gatekeeper allowlist |
| [../cost/gke-cost-allocations.md](../cost/gke-cost-allocations.md) | GKE 计费归因进阶 |
| [../cross-project/cross-project-bigquery.md](../cross-project/cross-project-bigquery.md) | 另一种隔离思路：per-tenant project（不走此路径，但可对比） |
