# PV vs PVC —— 集群范围 vs namespace 范围 · 概念澄清

> **本文档回应业务方在 review 中提出的核心疑问**: "PV 是集群范围,谁都能引用;PVC 是 namespace 范围,只有同 ns 的 Pod 能引用" 这句话背后的多租户隔离机制。
>
> **本文档定位**:
> - **配套阅读**:[ADR-009 §12 概念澄清](./nas/ADR-009-gke-pod-mount-internal-nas-security-review.md#12-概念澄清--pod-挂-nas-跟-pvpvc-到底是什么关系)(讲 PV/PVC/CSI 的关系)
> - **配套阅读**:[gke-pv-multi-tenant-design.md](./gke-pv-multi-tenant-design.md)(讲 master project + tenant labels 多租户体系)
> - **小白版本**:见同目录 `pv-with-pvc-eli5.html`(≤1500 字 5 岁版解释)
>
> **架构师 lane 边界**:本文档**只做概念澄清**,**不实施任何 provision**,**不创建 PV / PVC**。

---

## 0. TL;DR —— 一句话总结

> **PV 是"货架",cluster-scoped(集群范围);PVC 是"申请单",namespace-scoped(命名空间范围)。Pod 不直接拿 PV,通过 PVC 引用,自动获得 namespace 隔离。**
>
> 这是 K8s 多租户隔离的**第一道闸门** —— 也是为什么"业务方写 PVC、平台写 PV"成为合理分工的根本原因。

---

## 1. 为什么要拆 PV 和 PVC?(K8s 设计哲学)

### 1.1 如果只有一个对象会怎样?

如果 K8s 只用一个对象(比如"卷"),会变成:

```yaml
# 假想的"直接绑"模式(实际不存在)
apiVersion: v1
kind: Pod
metadata:
  name: api-app
  namespace: api-ns
spec:
  volumes:
  - name: my-data
    storage:
      #: ← 假想字段,Pod 直接描述存储细节
      type: pd-ssd
      size: 100Gi
      region: asia-northeast1
      encryptedWith: kms-key-1
      tenant: tnt-001
```

**问题**:

- Pod spec 跟**存储系统强耦合** —— 换 GCP PD / Filestore / NAS 都要改 Pod
- Pod 里有 **KMS key 引用** —— **凭据泄漏**
- 没有命名空间隔离 —— A 用户的 Pod 直接看到 B 用户的存储细节
- 平台无法统一管控(谁都能创建任意存储)

### 1.2 K8s 的解法:拆成 2 个对象

```
PV (PersistentVolume)        ← 集群范围的"货架"
PVC (PersistentVolumeClaim)  ← 命名空间范围的"申请单"
Pod 拿 PVC                    ← 自动得到命名空间隔离
```

**好处**:

- Pod 只描述"我要一块存储"(不知道是谁的、用什么类型)
- 存储细节(KMS key / tenant label / SC 等)都在 PV / PVC 层,平台可控
- 命名空间隔离**内置** —— Pod 看不到别 ns 的 PVC
- 业务方写 PVC(不关心底层),平台写 PV(治理层)

---

## 2. PV 详解(cluster-scoped)

### 2.1 是什么?

> **PV(PersistentVolume)**:集群范围的"真实存储的代理",代表"仓库里的一台货架"。

**关键属性**:

| 属性 | 值 | 为什么 |
|---|---|---|
| **作用域** | cluster-scoped(集群范围) | 不属于任何 namespace,所有 namespace 都能引用 |
| **谁创建** | 平台 / 集群管理员 | 业务方不应该直接创建 PV |
| **关键字段** | `spec.csi.driver` / `volumeAttributes` / `nodePublishSecretRef` | 决定底层是什么存储、怎么连、凭据在哪 |
| **绑定方式** | 1:1 绑定到 PVC(`spec.volumeName`) | 绑定后**不可改**,改了 K8s 直接拒绝 |
| **删除策略** | `persistentVolumeReclaimPolicy`(Retain/Recycle/Delete) | 删 PVC 时 PV 怎么处理(NAS 场景用 Retain) |

### 2.2 PV 示例(摘自 ADR-009 gke/ 部署参考集)

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-nas-app           # ← 集群内唯一,所有 ns 都能看到这个名字
  labels:
    tenant: tnt-001         # ← 业务方不知道,但 BigQuery 归因用
spec:
  capacity: { storage: 100Gi }
  accessModes: [ReadOnlyMany]
  persistentVolumeReclaimPolicy: Retain
  csi:
    driver: smb.csi.k8s.io  # ← 决定挂什么(NAS SMB)
    volumeAttributes:
      source: "//nas.address.aibang/hk/gsd/application"
    nodePublishSecretRef:
      name: smb-secret
      namespace: api-ns      # ← Secret 在哪个 ns,挂载就用哪个 ns 的凭据
```

**业务方看不到这些字段** —— PV 在 cluster scope,业务方只通过 PVC 引用。

---

## 3. PVC 详解(namespace-scoped)

### 3.1 是什么?

> **PVC(PersistentVolumeClaim)**:namespace 范围的"申请单",代表"我要一块什么样的存储"。

**关键属性**:

| 属性 | 值 | 为什么 |
|---|---|---|
| **作用域** | namespace-scoped(命名空间范围) | 只有同 ns 的 Pod 能引用,A ns 的 Pod 看不到 B ns 的 PVC |
| **谁创建** | 业务方 / 应用 owner | 业务方知道自己的应用需要多少存储 |
| **关键字段** | `volumeName`(绑到 PV)/ `accessModes` / `resources.requests.storage` / `storageClassName` | 描述存储需求,不关心底层 |
| **绑定方式** | 1:1 绑到 PV(显式 `volumeName` 或动态 SC 匹配) | 绑定后**不可改** |
| **生命周期** | namespace 生命周期 | 删 namespace = 自动删 PVC |

### 3.2 PVC 示例

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-nas-app          # ← 在 api-ns 里唯一
  namespace: api-ns          # ← namespace-scoped
spec:
  volumeName: pv-nas-app     # ← 显式绑到哪个 PV
  accessModes: [ReadOnlyMany]
  resources:
    requests:
      storage: 10Gi          # ← 业务方只关心"我要 10G"
  storageClassName: ""       # ← 静态 PV,不用 SC
```

**关键观察**:
- 业务方写 PVC,**不用写** NAS 地址 / CSI driver / Secret 名字
- 这些细节在 PV 里(平台控制)
- 业务方只声明"我需要 10Gi 只读存储"

---

## 4. Pod 怎么拿到存储

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-with-nas
  namespace: api-ns          # ← Pod 也在 api-ns
spec:
  template:
    spec:
      containers:
      - name: api
        volumeMounts:
        - name: nas-app-folder
          mountPath: /mnt/nas
          readOnly: true
      volumes:
      - name: nas-app-folder
        persistentVolumeClaim:
          claimName: pvc-nas-app    # ← Pod 通过 PVC 名字引用
          # ↑ Pod 不知道 PV,不知道 NAS 地址,不知道 CSI driver
```

**链路**:
1. Pod 写 `claimName: pvc-nas-app`
2. K8s 在 **同 ns**(api-ns)找 PVC
3. 找到 PVC → PVC 已 bind 到 PV
4. PV 触发 CSI driver → 挂载到 Pod

**关键事实**:
- Pod **不知道 PV** 的存在
- Pod **不知道底层存储**
- Pod 只能引用 **同 ns 的 PVC**
- A ns 的 Pod 想用 B ns 的 PVC?→ **不允许**,自动拒绝

---

## 5. 多租户隔离是怎么发生的?

```
ns: api-ns (tnt-001)                ns: other-ns (tnt-002)
┌──────────────────────────┐        ┌──────────────────────────┐
│  Pod A (tnt-001)         │        │  Pod B (tnt-002)         │
│    ↓ claimName: pvc-1   │        │    ↓ claimName: pvc-2   │
│  PVC pvc-1 (tnt-001)     │        │  PVC pvc-2 (tnt-002)     │
│    ↓ volumeName          │        │    ↓ volumeName          │
└──────────────────────────┘        └──────────────────────────┘
            ↓                                     ↓
        ┌────────────────────────────────────────────┐
        │  PV pv-001 (cluster-scoped,所有人可见)     │
        │  PV pv-002 (cluster-scoped,所有人可见)     │
        └────────────────────────────────────────────┘
            ↑
        K8s 自动隔离:Pod A 只能看到 pvc-1,看不到 pvc-2
                       Pod B 只能看到 pvc-2,看不到 pvc-1
                       即使两个 PVC 都绑到同一个 PV,Pod 也只能引用自己 ns 的 PVC
```

**5 层隔离机制**:

1. **PVC 在 namespace 内** — A ns 看不到 B ns 的 PVC
2. **Pod 在 namespace 内** — A ns 看不到 B ns 的 Pod
3. **Pod 引用 PVC 时,自动限定到 Pod 自己的 ns** — 跨 ns 引用 K8s 直接拒绝
4. **PV 是 cluster 范围,但通过 PVC 间接访问** — 业务方不直接拿 PV
5. **RBAC 在 namespace 层** — RoleBinding / ClusterRoleBinding 控制谁能 create PVC

**结果**: 即使 PV 在 cluster 全可见,业务方也只能用自己 ns 的 PVC,看不到别人 ns 的 PVC → **第一道隔离闸门**。

---

## 6. "业务方写 PVC,平台写 PV" 的分工原因

| 维度 | 业务方写 PVC | 平台写 PV |
|---|---|---|
| **作用域** | namespace-scoped | cluster-scoped |
| **影响范围** | 限于自己的应用 | 影响整个集群 |
| **需要的权限** | K8s: `create pvc`(namespaced) | K8s: `create pv`(cluster-wide) |
| **需要的信息** | "我需要 10Gi 只读" | "底层是什么 / 凭据在哪 / KMS 用哪个" |
| **凭据暴露** | ❌ PVC 里没有凭据字段 | ⚠ PV 里有 Secret 引用,平台必须严管 |
| **审计粒度** | namespace 级 audit log | cluster 级 audit log |

**结论**:
- 业务方只声明需求,不暴露底层细节 → 凭据泄漏风险低
- 平台控制 PV + KMS + IAM → 多租户隔离可控
- 平台维护 tenant label → BigQuery 归因可追溯
- 业务方 review 自己的 PVC,平台 review 所有的 PV → **职责清晰**

---

## 7. 命名空间隔离的边界情况(必须知道)

| 场景 | 行为 | 原因 |
|---|---|---|
| Pod 想引用别 ns 的 PVC | ❌ K8s 自动拒绝 | 命名空间边界 |
| 同 ns 的 2 个 Pod 引用同一个 PVC | ✅ 允许(取决于 accessModes) | PV 共享,Pod 都在 ns 内 |
| PV 已被 PVC bind,新 PVC 想绑同一 PV | ❌ 1:1 绑定,绑完不变 | 避免冲突 |
| 删 PVC 后 PV 还在 | ✅ Retain 策略保护 PV | 防数据丢失 |
| PV 已 bind 但 PVC 删了,新 PVC 想绑 | ✅ 允许(PV 状态 Available 后) | PV 被释放,可重新绑定 |
| Pod 跨 cluster 想访问 PV | ❌ 不可能(PV 不跨 cluster) | K8s 集群边界 |

---

## 8. 常见误解澄清

### ❌ 误解 1:"业务方不应该看 PV"

**对**:业务方应该**理解** PV 是什么(读 ADR / review 时用),但不应该**写 PV**(写会绕过平台管控)。

### ❌ 误解 2:"PVC 必须显式 bind 到 PV"

**半对**:静态 PV 需要显式 `volumeName`;**动态 PV 通过 StorageClass 自动匹配**,不需要显式 volumeName。

### ❌ 误解 3:"PV 一旦创建,所有人都能用"

**半对**:PV 在 cluster scope,所有人**看得到**,但**用不到**(因为 PVC 是 namespace-scoped,Pod 必须引用自己 ns 的 PVC)。

### ❌ 误解 4:"Pod 删除后,数据没了"

**错**:PV 绑定的存储(GCP PD / Filestore / 远端 NAS)数据**独立于 Pod 生命周期**。Pod 删除重建,数据还在。

---

## 9. 跟 ADR-009 NAS 场景的关系

| 概念 | NAS 场景里的体现 |
|---|---|
| PV 是 cluster-scoped | 多个 namespace 都能引用同一个 PV-nas-app |
| PVC 是 namespace-scoped | api-ns 里的 PVC-nas-app 看不到 other-ns 的 PVC |
| Pod 引用 PVC → PVC 引用 PV | api Pod → pvc-nas-app(在 api-ns)→ pv-nas-app(集群范围)|
| 业务方写 PVC | 业务方提供 PVC YAML,平台提供 PV YAML |
| 平台写 PV | infra-gcp 创建 PV,绑定 SMB CSI driver |
| 隔离闸门 | 即使 2 个 namespace 都挂同一个 NAS,通过不同 PVC 隔离 |

**挂 NAS 场景下的最佳实践**(本 ADR 推 荐):
- 1 个 PV(集群共享 NAS 真实存储)
- N 个 PVC(每个 namespace 一个)
- 1 个 PVC 只被 1 个 Pod 引用(避免共享访问面)
- NetworkPolicy 锁定 Pod 出栈(第二道闸门)

---

## 10. 关键引用

| 引用 | 用途 |
|---|---|
| [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) | K8s 官方 PV 文档 |
| [Kubernetes Persistent Volume Claims](https://kubernetes.io/docs/concepts/storage/persistent-volume-claims/) | K8s 官方 PVC 文档 |
| [Kubernetes Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/) | 动态 PV 匹配机制 |
| [ADR-009 §12 概念澄清](./nas/ADR-009-gke-pod-mount-internal-nas-security-review.md#12-概念澄清--pod-挂-nas-跟-pvpvc-到底是什么关系) | PV/PVC/CSI driver 的关系(本 ADR 上下文) |
| [gke-pv-multi-tenant-design.md](./gke-pv-multi-tenant-design.md) | master project + tenant labels 多租户体系 |
| [pv-with-pvc-eli5.html](./pv-with-pvc-eli5.html) | 小白版 ELI5 解释(同目录)|

---

## 11. 架构师重申边界

| 能做 | 不能做 |
|---|---|
| ✅ 评审 PV / PVC YAML 设计 | ❌ 创建 PV / PVC |
| ✅ 评审 namespace / RBAC 设计 | ❌ 创建 namespace / RoleBinding |
| ✅ 评审多租户隔离方案 | ❌ 跑 gcloud / kubectl |
| ✅ 维护本文档 + 配套 eli5 版本 | ❌ 持有 GCP / K8s 凭证 |

---

> **作者声明**:本文档只做概念澄清,**不实施任何 provision / apply**。如果业务方基于本文档决定操作模式,实际部署由 infra-gcp 用专属 SA 执行(详见 [gke/README.md](./nas/gke/README.md))。