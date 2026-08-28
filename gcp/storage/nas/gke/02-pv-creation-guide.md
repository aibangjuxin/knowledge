# 02 · PV 创建指南 + 与 PVC 的关系 + 绑 PVC 流程

> **本节是 infra-gcp 视角的"怎么创建 PV"+ 业务方需要理解的"PV/PVC 关系"**
>
> **架构师 lane 边界**:本文档**只描述创建步骤和 YAML 模板**,**不执行 apply**。实际 `kubectl apply` 由 infra-gcp 用专属 SA 执行。

---

## 1. PV / PVC 关系速懂(给业务方看的 30 秒版)

```
┌──────────────────────────────────────────────────────────────────────┐
│  PV (PersistentVolume)            — 集群范围的"货架"                   │
│    spec.csi.driver: smb.csi.k8s.io   ← 关键:决定挂什么                  │
│    spec.csi.volumeAttributes:        ← 关键:挂哪里                     │
│      source: "//nas.address.aibang/hk/gsd/application"                │
│    spec.csi.nodePublishSecretRef:    ← 凭据来源                       │
│      name: smb-secret                                                    │
│                                                                       │
│  ↓ binding(自动 or 手动)                                              │
│                                                                       │
│  PVC (PersistentVolumeClaim)       — 命名空间范围的"申请单"            │
│    metadata.namespace: api-ns                                         │
│    spec.volumeName: pv-nas-app      ← 指向 PV                        │
│    spec.resources.requests.storage: 10Gi                             │
│    spec.accessModes: [ReadOnlyMany]                                   │
│                                                                       │
│  ↓ pod reference                                                       │
│                                                                       │
│  Pod 写 volumes:                                                       │
│    volumes:                                                            │
│    - name: nas-app-folder                                             │
│      persistentVolumeClaim:                                            │
│        claimName: pvc-nas-app      ← 指向 PVC                        │
└──────────────────────────────────────────────────────────────────────┘
```

**关键事实**:
- PV 是**集群范围**(谁都能引用)
- PVC 是**namespace 范围**(只有同 ns 的 Pod 能引用)
- **业务方写 PVC,平台写 PV**(虽然 PV YAML 业务方也可以写,但建议 infra-gcp 写)
- PV 和 PVC 通过 `spec.volumeName` 绑(1:1)

---

## 2. PV 的两种创建方式

### 方式 A:静态 PV(infra-gcp 提前建好,业务方后引用)

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-nas-app                # ← 集群内唯一名字
  labels:
    tenant: tnt-001               # ← BigQuery 归因
    storage-type: nas-smb
spec:
  capacity:
    storage: 100Gi               # ← 标称容量(NAS 实际可能更大)
  accessModes:
  - ReadOnlyMany                  # ← 多个 Pod 可读,NAS 上同时打开多个 handle
  persistentVolumeReclaimPolicy: Retain   # ← 删 PVC 时不删 NAS 文件(保护数据)
  storageClassName: ""            # ← 不用 StorageClass,手动绑
  csi:
    driver: smb.csi.k8s.io        # ← 关键:CSI driver 名字
    volumeHandle: "nas-app-folder#//nas.address.aibang/hk/gsd/application#"
                               # ← 格式: <name>#<share>#   CSI driver 要求
    volumeAttributes:
      source: "//nas.address.aibang/hk/gsd/application"   # ← 关键:挂载路径
    nodePublishSecretRef:
      name: smb-secret            # ← SMB 凭据 Secret(infra-gcp 创建)
      namespace: api-ns           # ← Secret 必须在 Pod 所在 ns
    # 注:SMB CSI driver 不需要 fsType 字段
```

**适用场景**:本 ADR-009 场景(挂公司 NAS,数据固定)

### 方式 B:动态 PV(StorageClass + dynamic provisioner)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nas-smb
provisioner: smb.csi.k8s.io
parameters:
  source: "//nas.address.aibang"
reclaimPolicy: Retain
volumeBindingMode: Immediate
allowVolumeExpansion: false   # SMB CSI driver 不支持扩容
mountOptions:
  - dir_mode=0755
  - file_mode=0644
```

**适用场景**:动态创建多份 SMB 共享子目录(超出 ADR-009 范围,本节不展开)

**本 ADR 用方式 A**(更可控、可审计)。

---

## 3. PVC 创建方式

业务方提供 PVC,infra-gcp 套 namespace:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-nas-app                 # ← 业务方命名
  namespace: api-ns                 # ← 业务方指定 namespace
  labels:
    tenant: tnt-001                 # ← 与 PV 对齐
spec:
  volumeName: pv-nas-app            # ← 绑到哪个 PV(关键)
  accessModes:
  - ReadOnlyMany
  resources:
    requests:
      storage: 10Gi                # ← 不超 PV capacity
  storageClassName: ""             # ← 静态 PV,不用 SC
```

---

## 4. PV 创建 + 绑 PVC 的端到端流程

```
┌────────────────────────────────────────────────────────────────┐
│  Step 1: 业务方提供 PVC manifest                                │
│          (infra-gcp 提供 PVC YAML 模板,业务方填字段)           │
└─────────────────┬──────────────────────────────────────────────┘
                  │
                  ▼
┌────────────────────────────────────────────────────────────────┐
│  Step 2: infra-gcp 评审                                         │
│          • 4 红线自检(grep deployment.yaml)                      │
│          • tenant label 一致性                                  │
│          • readOnly 默认值                                       │
│          • namespace / RBAC 合规                                 │
└─────────────────┬──────────────────────────────────────────────┘
                  │ ✅ 通过
                  ▼
┌────────────────────────────────────────────────────────────────┐
│  Step 3: infra-gcp 创建 namespace + SA + Secret(凭据)             │
│          kubectl create namespace api-ns                        │
│          kubectl create sa api-nas-consumer-sa -n api-ns       │
│          kubectl create secret generic smb-secret -n api-ns     │
│            --from-literal=username=...                           │
│            --from-literal=password=...                           │
└─────────────────┬──────────────────────────────────────────────┘
                  │
                  ▼
┌────────────────────────────────────────────────────────────────┐
│  Step 4: infra-gcp 创建 PV                                      │
│          kubectl apply -f pv-nas-template.yaml                  │
│          验证:kubectl get pv pv-nas-app -o yaml | grep csi     │
└─────────────────┬──────────────────────────────────────────────┘
                  │
                  ▼
┌────────────────────────────────────────────────────────────────┐
│  Step 5: infra-gcp 创建 PVC + 验证绑定                          │
│          kubectl apply -f pvc-nas-template.yaml -n api-ns       │
│          验证:kubectl get pvc pvc-nas-app -n api-ns            │
│          期望:STATUS = Bound                                    │
└─────────────────┬──────────────────────────────────────────────┘
                  │
                  ▼
┌────────────────────────────────────────────────────────────────┐
│  Step 6: infra-gcp 创建 NetworkPolicy(必配)                     │
│          kubectl apply -f network-policy-nas.yaml               │
└─────────────────┬──────────────────────────────────────────────┘
                  │
                  ▼
┌────────────────────────────────────────────────────────────────┐
│  Step 7: 业务方 apply Deployment(实际由 infra-gcp 走 CI/CD)      │
│          kubectl apply -f deployment-with-nas.yaml -n api-ns   │
└─────────────────┬──────────────────────────────────────────────┘
                  │
                  ▼
┌────────────────────────────────────────────────────────────────┐
│  Step 8: qa-gcp 端到端验证                                       │
│          • kubectl exec -it <pod> -n api-ns -- ls /mnt/nas     │
│            期望:看到 NAS 文件                                    │
│          • NetworkPolicy 测试                                    │
│          • 红线自检(应用 log 不能含 NAS 路径)                     │
└────────────────────────────────────────────────────────────────┘
```

---

## 5. 关键 YAML 模板位置

| 资源 | 文件 |
|---|---|
| Deployment | [`examples/deployment-with-nas.yaml`](./examples/deployment-with-nas.yaml) |
| PV(本 ADR 主用)| [`examples/pv-nas-template.yaml`](./examples/pv-nas-template.yaml) |
| PVC | [`examples/pvc-nas-template.yaml`](./examples/pvc-nas-template.yaml) |
| NetworkPolicy(必配) | [`examples/network-policy-nas.yaml`](./examples/network-policy-nas.yaml) |
| SMB Secret | [`examples/smb-secret-template.yaml`](./examples/smb-secret-template.yaml) |
| Namespace + labels | [`examples/namespace-with-labels.yaml`](./examples/namespace-with-labels.yaml) |

---

## 6. infra-gcp 必跑的自检命令

```bash
# PV 创建后
kubectl get pv pv-nas-app -o yaml | grep -E "driver|volumeAttributes|nodePublishSecretRef"
# 期望:csi.driver = smb.csi.k8s.io

# PVC 绑定后
kubectl get pvc pvc-nas-app -n api-ns -o jsonpath='{.status.phase}'
# 期望:Bound

# Pod 启动后
kubectl exec -it <pod-name> -n api-ns -- mount | grep cifs
# 期望:看到 //nas.address.aibang/hk/gsd/application on /mnt/nas type cifs

# 4 红线自检(grep Deployment)
grep -E "gcs|firestore|bigquery|cloudsql" deployment.yaml            # R1
grep -E "nas.*path|/mnt/nas" deployment.yaml                         # R2
grep -E "audit_log.*file_path|audit_log.*file_content" deployment.yaml  # R3
grep -E "configMapRef.*nas|secretRef.*nas" deployment.yaml            # R4
# 期望:全部无输出
```

---

## 7. 错误排查 quick reference

| 现象 | 可能原因 | 修复 |
|---|---|---|
| `kubectl get pvc` STATUS = Pending | PV `volumeName` 写错 / capacity 不够 / accessModes 不匹配 | 检查 PV 的 `volumeName` 和 `accessModes` |
| Pod 启动后 `ls /mnt/nas` 空 | SMB 路径错 / 凭据错 / NAS 防火墙挡住 GKE Node IP | 见 ADR-009 §11.4(G6 NAS 信任网络验证) |
| `kubectl describe pod` 报 `FailedMount` | Secret 引用错 / CSI driver 未装 | `kubectl get csinodes` 应能看到 smb.csi.k8s.io |
| Pod 内 `mount` 看不到 cifs | CSI driver 没装 / DaemonSet 没跑 | `kubectl get pods -n csi-system -l app=csi-smb` |

---

> **作者声明**:本文档只描述创建流程,**不执行 apply**。实际部署由 infra-gcp 用专属 SA 执行。