# K8sStorageClass 限制 PersistentVolumeClaim 存储类

## 概述

`K8sStorageClass` 限制 PersistentVolumeClaim (PVC) 只能使用**指定的存储类**，防止应用滥用不合适的存储类型。

在多云环境中，不同的 StorageClass 代表不同的存储后端（SSD/HDD/网络存储），不同性能/成本/持久性。强制 PVC 使用合适的 StorageClass 是存储治理的基础。

---

## 核心概念

### 这个 Constraint 做什么

```
检查每个 PVC:
  └── 使用的 storageClassName 必须在 allowedStorageClasses 列表中

PVC.spec.storageClassName: "premium-ssd"
  ✓ 通过 if allowedStorageClasses 包含 "premium-ssd"
  ✗ 拒绝 if 不在列表中
```

### 模板信息

| 属性 | 值 |
|------|-----|
| **ConstraintTemplate Name** | `k8sstorageclass` |
| **Kind** | `K8sStorageClass` |
| **版本** | 1.1.2 |
| **来源** | [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general/storageclass) |

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `allowedStorageClasses` | array[string] | 允许的 StorageClass 名称列表 |
| `includeStorageClassesInMessage` | boolean | violation 消息中是否包含允许列表，默认 `true` |

---

## Rego 核心逻辑

```rego
package k8sstorageclass

is_pvc(obj) {
  obj.apiVersion == "v1"
  obj.kind == "PersistentVolumeClaim"
}

violation[{"msg": msg}] {
  not data.inventory.cluster["storage.k8s.io/v1"]["StorageClass"]
  msg := "StorageClasses not synced. Gatekeeper may be misconfigured."
}

violation[{"msg": msg}] {
  pvc := input.review.object
  is_pvc(pvc)
  storage_class := pvc.spec.storageClassName
  not storageclass_allowed(storage_class)
  msg := sprintf("PVC %v uses disallowed storage class %v", [pvc.metadata.name, storage_class])
}
```

关键：`data.inventory.cluster` 是 Gatekeeper 的特殊数据源，包含集群中所有已注册的 CRD 资源。这使得 Constraint 可以查询集群中实际存在的 StorageClass。

---

## 完整 Constraint YAML

### 允许特定存储类

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sStorageClass
metadata:
  name: allow-only-premium-storage
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["PersistentVolumeClaim"]
    excludedNamespaces:
    - kube-system
  parameters:
    allowedStorageClasses:
    - "premium-ssd"       # GCP: pd-ssd
    - "standard"           # GCP: pd-standard
    includeStorageClassesInMessage: true
```

### 生产环境：仅允许 SSD

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sStorageClass
metadata:
  name: prod-storage-classes
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["PersistentVolumeClaim"]
    excludedNamespaces:
    - kube-system
    - logging
  parameters:
    allowedStorageClasses:
    - "premium-rwo"        # ReadWriteOnce SSD
    includeStorageClassesInMessage: true
```

### 阿里云 ACK 环境

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sStorageClass
metadata:
  name: ack-storage-classes
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["PersistentVolumeClaim"]
  parameters:
    allowedStorageClasses:
    - "alicloud-disk-efficiency"   # 高效云盘
    - "alicloud-disk-ssd"          # SSD 云盘
    - "alicloud-disk-essd"         # ESSD 超高 IO 云盘
    - "nas"                         # NAS 文件存储
    includeStorageClassesInMessage: true
```

---

## 应用命令

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sStorageClass
metadata:
  name: allow-only-premium-storage
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["PersistentVolumeClaim"]
  parameters:
    allowedStorageClasses:
    - "premium-ssd"
    - "standard"
EOF

# 查看
kubectl get k8sstorageclass

# 查看 violations
kubectl get k8sstorageclass allow-only-premium-storage \
  -o jsonpath='{.status.violations}' | jq '.'

# 查看集群中可用的 StorageClass
kubectl get storageclass
```

---

## 测试：触发违规

### 测试 1：使用不允许的存储类

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bad-storage-pvc
  namespace: default
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: "cheap-hdd"    # 不在允许列表 → 触发 violation

# 预期拒绝:
# PVC bad-storage-pvc uses disallowed storage class cheap-hdd
```

### 测试 2：使用默认 StorageClass（动态选择）

如果集群设置了默认 StorageClass（annotation `storageclass.kubernetes.io/is-default-class: "true"`），PVC 可以不指定 `storageClassName`。但 Gatekeeper 仍会检查，因为最终会选择一个实际的 StorageClass。

```yaml
# 不指定 storageClassName → 使用集群默认
spec:
  resources:
    requests:
      storage: 10Gi
# Gatekeeper 会检查这个 PVC 最终使用的默认 SC 是否在允许列表
```

### 测试 3：使用允许的存储类

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: good-storage-pvc
  namespace: default
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: "premium-ssd"   # ✓ 在允许列表中 → 通过
```

---

## 实际应用场景

### 场景 1：成本控制

```yaml
# 只有研发 namespace 可以用标准存储
namespace: development
  allowedStorageClasses: ["standard", "premium-ssd"]

# 生产 namespace 必须用高性能存储
namespace: production
  allowedStorageClasses: ["premium-ssd", "ultra-disk"]
```

### 场景 2：GKE 多存储后端

GKE 支持多种 StorageClass：

```bash
kubectl get storageclass
# NAME                    PROVISIONER            RECLAIMPOLICY
# premium-rwo             pd.csi.storage.gke.io  Delete
# standard                pd.csi.storage.gke.io  Delete
# standard-rwo            pd.csi.storage.gke.io  Delete
# ultra                   pd.csi.storage.gke.io  Delete
# regional-pd             pd.csi.storage.gke.io  Delete
```

```yaml
# 允许 GKE 所有存储类型（通过命名区分）
allowedStorageClasses:
- "premium-rwo"      # Local SSD
- "standard-rwo"     # Regional PD
- "standard"         # Standard
```

### 场景 3：多云环境差异化

GKE 和 ACK 的 StorageClass 名称完全不同，需要分别配置：

```
GKE:
  - premium-rwo
  - standard

ACK (Alibaba Cloud):
  - alicloud-disk-ssd
  - alicloud-disk-efficiency
  - nas
```

---

## StatefulSet 配合检查

`K8sStorageClass` 同样会检查 StatefulSet 中内嵌的 PVC 模板：

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: "mysql"
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    spec:
      containers:
      - name: mysql
        image: mysql:8
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: "premium-ssd"   # ← 检查这个
      resources:
        requests:
          storage: 100Gi
```

---

## 常见问题

### Q1: 什么是 `data.inventory.cluster`？

`data.inventory.cluster` 是 Gatekeeper 的同步数据机制，它将集群中所有 CRD 资源同步为 OPA 数据，提供给 Rego 查询。`K8sStorageClass` 使用它来获取集群中实际存在的 StorageClass 列表。

### Q2: PVC 没有指定 storageClassName 会被阻止吗？

会。如果 PVC 使用集群默认 StorageClass（通过 `storageClassName: ""` 或省略），Gatekeeper 会检查实际选择的 SC 是否在允许列表中。

### Q3: 如何允许所有存储类？

```yaml
parameters:
  allowedStorageClasses: []    # 空列表 = 不限制
```

### Q4: 哪些 namespace 需要排除？

通常排除系统 namespace：
- `kube-system`（集群组件 PVC）
- `gatekeeper-system`
- `istio-system`
- `monitoring`
- `logging`

---

## 快速命令参考

```bash
# 查看集群中所有 StorageClass
kubectl get storageclass

# 查看某个 StorageClass 是否是默认
kubectl get storageclass <name> -o jsonpath='{.metadata.annotations}'

# 应用
kubectl apply -f k8sstorageclass.yaml

# 查看
kubectl get k8sstorageclass

# 查看 violations
kubectl get k8sstorageclass <name> \
  -o jsonpath='{.status.violations}' | jq

# 更新允许列表
kubectl patch k8sstorageclass allow-only-premium-storage \
  --type=merge \
  -p '{"spec":{"parameters":{"allowedStorageClasses":["premium-ssd","standard","nas"]}}}'

# 删除
kubectl delete k8sstorageclass <name>
```

---

## 源文件路径

- ConstraintTemplate: `library/general/storageclass/template.yaml`
- Samples: `library/general/storageclass/samples/`
