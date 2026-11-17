# GKE PV 存储方案:默认 StorageClass vs 自定义 StorageClass 的架构选型

> **范围**:本文讨论的是 GKE(GCP)上,Pod 挂载 PersistentVolume(PV)用于持久化数据的场景。回答的核心问题是:
> - 默认 StorageClass(premium-rwo / standard-rwo 等)够用吗?
> - 业务方是否应该新建自定义 StorageClass?
> - 从平台治理 / 安全 / 成本 / 多租户四个维度,哪种模式更合理?

参考了以下两份资料(向下展开):
- [`/Users/lex/git/gcp/gke/opa-gatekeeper/constraint-explorers/storageclass.md`](../../../gcp/gke/opa-gatekeeper/constraint-explorers/storageclass.md) — Gatekeeper `K8sStorageClass` Constraint 模板与 Rego 逻辑
- [`/Users/lex/git/gcp/skills/gke-basics/references/gke-storage.md`](../../../gcp/skills/gke-basics/references/gke-storage.md) — GKE 黄金路径下的默认 StorageClass 与最佳实践

---

## 1. 一句话结论

**在多租户 / 治理优先的 GKE 集群中,推荐"中心化管控 + 业务不直连默认 SC,而是通过 OPA Gatekeeper allowlist + 几套平台方预定义的命名 SC"模式。**

具体拆开说:
1. **业务方不应当**随意 `kubectl apply` 创建自定义 StorageClass 来"我自己配一套更合适的 PD"。这是治理红线,不是建议。
2. **业务方可以使用**平台管理员(GCP infra 团队 / 平台工程)预创建并通过权限隔离保护的几个 StorageClass(比如 `db-ssd-prod`、`db-ssd-dev`、`shared-nfs`、`cold-hdd`),通过 PVC 的 `storageClassName` 显式选用。
3. **业务方不应该**直接依赖"未指定 SC → 自动用默认 SC"这种隐式行为,因为默认 SC 是谁在哪个 namespace 都一样,而且默认 SC 一旦被改动,所有 PVC 受影响。

这条结论的两条核心理由:
- **统一治理**:StorageClass 决定的是底层 IO 类型、加密、快照策略、回收策略、区域绑定模式 — 这些都是集群级(甚至组织级)决策,不是应用级决策
- **可控变更**:把 StorageClass 创建权收回到 platform team,业务方只能"选",不能"创",这是把"安全相关决策"和"业务逻辑"解耦的标准做法

---

## 2. 三种模式的架构对照

### 2.1 模式 A:业务方直接用默认 StorageClass(不推荐 ❌)

```yaml
# 业务方什么都不指定,让 K8s 自动选 default StorageClass
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 100Gi
  # storageClassName 不写 → 走默认 SC
```

**问题清单**:

| 维度 | 风险 |
|------|------|
| **一致性** | 默认 SC 是集群级全局资源,任何一次 admin 误改 annotation `storageclass.kubernetes.io/is-default-class` 都会全局污染 |
| **可见性** | 业务方不知道自己实际拿到的是哪个 SC,运维审计看不到"这个 PVC 用的什么盘" |
| **治理** | SC 控制的是底层 PD 类型、加密、快照策略 — 这些参数是平台决策,不应当隐式继承 |
| **OPA 兜底** | 参考 storageclass.md §"测试 2",Gatekeeper 在 PVC 没指定 SC 时也会校验最终选中的 SC 是否在 allowlist 内 — 但 allowlist 怎么列依赖模式 A 的可预测性 |

### 2.2 模式 B:业务方自行创建自定义 StorageClass(强烈不推荐 ❌❌)

```yaml
# 业务方自行 apply
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: my-custom-fast-storage
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-extreme
  replication-type: regional-pd
volumeBindingMode: WaitForFirstConsumer
```

**为什么这是"最危险"的模式**:

1. **后端资源无控制**:`pd-extreme`、`pd-ssd`、`replication-type: regional-pd` 都是 GCP 计费项,业务方随手创建一个就等于直接打通了"我在云上花钱"的通道
2. **回收策略不可控**:K8s 默认 reclaim policy 是 `Delete`,但业务方自定义 SC 时如果写错成 `Retain`(或写错成 `Delete` 误以为是 Retain),PV 删除行为完全不同
3. **快照 / 加密策略分散**:不同 SC 可以配不同的 `csi.storage.k8s.io/snapshotter` 和 `encryptionContext`,业务方创建的 SC 会绕过集群级别的统一加密策略
4. **权限模型最反直觉**:很多团队以为业务 namespace 给权限就够 — 但 StorageClass 是**集群范围**(非 namespace)资源,创建权限意味着拥有 *整个集群* 的存储配置能力
5. **跨 namespace 污染**:业务方命名 `my-company-storage`,其他团队发现好用就都用,没人知道它在哪个 namespace 维护,审计追溯困难

### 2.3 模式 C:平台预创建 + 业务方引用(推荐 ✅)

```yaml
# 平台管理员(GCP infra)创建 ↓
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: db-ssd-prod
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd
  replication-type: regional-pd
  disk-encryption-kms-key: projects/<org>/locations/<region>/keyRings/...
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
---
# 业务方在 PVC 里显式引用 ↓
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-data
  namespace: prod-app
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: db-ssd-prod    # 从平台提供的清单里选
  resources:
    requests:
      storage: 500Gi
```

**这是 GCP GKE 黄金路径** — 参考 `gke-basics/references/gke-storage.md` §"StorageClasses",其中 Built-in SC 已经覆盖了大部分场景(`standard-rwo` / `premium-rwo` / `standard-rwx` / `premium-rwx`),但真正的 prod 用法是平台再叠加几套 SC。

---

## 3. 多维度对比表

| 维度 | 模式 A:默认 SC | 模式 B:业务方自定义 | 模式 C:平台预建 + Gatekeeper 兜底 |
|------|------|------|------|
| **创建 SC 的权限在哪** | 平台(GCP infra) | 业务方(全开放) | 平台(GCP infra,RBAC 严格限制) |
| **创建 PVC 的权限在哪** | 业务方 | 业务方 | 业务方 |
| **存储后端选择** | 隐式 / 不可控 | 业务方任意 | 平台 allowlist + Gatekeeper deny |
| **加密 (CMEK)** | 依赖默认 SC 是否配 | 业务方可控(可绕过) | 平台统一管控,不允许绕过 |
| **快照策略** | 依赖默认 SC 是否配 | 业务方可控 | 平台统一 |
| **回收策略** | 全局一致 | 极易出错 | 全局一致 |
| **成本可见性** | 业务方不知道自己在用什么 | 业务方直接产生云费用 | 平台集中账单,可分摊 |
| **OPA 治理** | 难(SC 隐式) | 业务方可绕过(自建不在 inventory 内时) | 简单(allowlist 直接列) |
| **审计追溯** | 难 | 难且复杂 | 容易(SC ↔ PVC ↔ namespace 对应清楚) |
| **故障爆炸半径** | 全局 | 全局 | 命名 SC 范围 |
| **多区域 / HA** | 默认 SC 不一定配 regional | 业务方乱配 | 平台统一配 `regional-pd` |

---

## 4. 为什么 "中心化管控" 模式 C 更安全 — 落到四个具体原理

### 4.1 安全:StorageClass 是集群级资源,创建权 ≠ 命名空间权限

`StorageClass` 没有 namespace,创建它的 RBAC 必然是 cluster-scoped。在 GKE 上等同于把 "在集群里所有命名空间创建存储" 的权限下放给任意 namespace,这是反最小权限原则的。

**对比 StatefulSet**:`StatefulSet` 是 namespace-scoped,业务方在某个 namespace 创建不会污染其他 namespace。但 `StorageClass` 改一处全集群受影响。

### 4.2 可控:StorageClass 控制的是 GCP 计费项入口

SC 关键参数:
- `type: pd-balanced | pd-ssd | pd-standard | pd-extreme` → 单 GB 单价差 10x
- `replication-type: regional-pd` → 翻倍
- `disk-encryption-kms-key` → CMEK 启用会走 KMS 计费

业务方直接拿到 SC 创建权 → 直接拿到 GCP 账单话语权。
参考 gke-storage.md §"Best Practices",这里也只列了平台角度的几个最佳实践,没有 "业务方可自定义 SC" 这种说法。

### 4.3 可治理:StorageClass 是 OPA Gatekeeper 的标准兜底锚点

参考 `constraint-explorers/storageclass.md` 里 Gatekeeper 的 Rego:

```rego
violation[{"msg": msg}] {
  pvc := input.review.object
  is_pvc(pvc)
  storage_class := pvc.spec.storageClassName
  not storageclass_allowed(storage_class)
  msg := sprintf("PVC %v uses disallowed storage class %v", [pvc.metadata.name, storage_class])
}
```

Gatekeeper 的核心是"`allowedStorageClasses` 列表" — **清单本身的可信度决定治理效果**:

- 模式 A(默认 SC):清单很难定,你不知道 SC 在哪
- 模式 B(业务方自建):清单永远滞后,业务创建 SC 速度 > 平台加白速度
- 模式 C(平台预建):清单由平台直接维护 → 等价于 SC 名空间和 allowlist 1:1 对齐,Gatekeeper 一次配置永久生效

`storageclass.md` §"完整 Constraint YAML" 里给的就是模式 C 的标准用法:`allowedStorageClasses: ["premium-ssd", "standard"]`,名字本身就是平台签发的标识符。

### 4.4 可恢复:把"SC 删除 / 改字段"的爆炸半径收回到平台手里

如果 SC 名字在生产 PVC 引用着,删除 SC 会导致新 PVC 无法调度,但**已有 PVC 不受影响**(PV 已经 provision,SC 字段是创建时填入 PV 后才不再依赖的 — 除了 `reclaimPolicy` 这种需要动态读取的字段)。

但业务方创建 SC 有个隐性坑:**如果两个 namespace 都引用 SC `my-team-fast`,业务方可能直接改字段(reclaimPolicy / 类型),影响自己时,其他团队 PVC 不受影响但 SC 行为已变**。模式 C 里 SC 是平台管的,只能走 PR review 才能改,改完发通告所有引用方。

---

## 5. GKE 黄金路径下的 SC 命名建议(平台参考清单)

参考 `gke-basics/references/gke-storage.md` §"Default StorageClasses",GKE 已经预置:

| 默认 SC | 后端 | Access |
|---------|------|--------|
| `standard-rwo` | pd-standard | RWO |
| `premium-rwo` | pd-ssd | RWO |
| `standard-rwx` | Filestore Basic HDD | RWX |
| `premium-rwx` | Filestore Basic SSD | RWX |

这套对 PoC / dev 够用,但生产环境的平台应该再叠一层:

| 平台预建 SC(建议) | 后端 | 用途 | 允许 namespace |
|------------------|------|------|--------------|
| `prod-db-ssd` | pd-ssd + regional-pd | 生产 DB | prod-* |
| `prod-db-extreme` | pd-extreme | 高 IOPS DB | prod-* |
| `prod-shared-nfs` | Filestore Enterprise | 共享文件 | prod-* |
| `dev-any` | pd-balanced | dev / test 通用 | dev-* / non-prod |
| `cold-arch` | pd-standard | 归档 / 日志 | * (全 namespace,低成本) |
| `gcs-archive` | Cloud Storage FUSE | 冷数据 / 数据湖挂载 | * |

注意几个 GKE 默认 SC 的"够用但不够生产"的地方:
- 没有 `replication-type: regional-pd` 的双 zone HA 选项
- 没有 CMEK KMS key 字段
- 没有命名空间隔离的 allowlist 标记

这些"加成项"才是平台方预建的真正价值。

---

## 6. Gatekeeper allowlist 与命名 SC 的双向对应关系

承 §4.3 + §5,平台方直接维护这张表:

```yaml
# constraint-templates/storageclass-allowlist.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sStorageClass
metadata:
  name: prod-storage-allowlist
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["PersistentVolumeClaim"]
    excludedNamespaces:
    - kube-system
    - gatekeeper-system
    - logging
    - monitoring
  parameters:
    allowedStorageClasses:
    - "prod-db-ssd"
    - "prod-db-extreme"
    - "prod-shared-nfs"
    - "gcs-archive"
    includeStorageClassesInMessage: true
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sStorageClass
metadata:
  name: dev-storage-allowlist
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["PersistentVolumeClaim"]
    kinds_namespaceSelector:
      matchExpressions:
      - key: environment
        operator: In
        values: ["dev", "staging"]
  parameters:
    allowedStorageClasses:
    - "dev-any"
    - "cold-arch"
    - "gcs-archive"
    includeStorageClassesInMessage: true
```

这样就有**正反两个方向**都被兜住:
- **正向(平台 → 业务)**:平台预建清单 `prod-db-ssd` 等,业务方在 PVC 里引用
- **反向(业务 → 平台)**:Gatekeeper 校验每个 PVC 的 `storageClassName` 必须在 allowlist 内,任何业务方创建的新 SC 都无法出现在 PVC 引用里(被 deny)

**Reference 链 — 每一个 ID 都可追溯:**
- `prod-db-ssd` 等 SC 定义所在的 repo / directory(GCP infra TF repo 的 `modules/storage/sc/main.tf`)
- `prod-storage-allowlist` constraint 的源文件(`gcp/gke/opa-gatekeeper/constraints/storageclass-allowlist.yaml`)
- `prod-db-ssd` 的 CMEK key ID → `gcp/sa/cmek-keyring/main.tf` 输出

---

## 7. 反向场景:业务方"我就要新 SC"的合理理由 vs 平台方"为什么应该拒绝"

**业务方可能提的理由** 和 **平台方标准回答**:

| 业务方理由 | 平台方标准回答 |
|-----------|--------------|
| "我需要 10000 IOPS,默认 `premium-rwo` 不够" | GKE 的 `pd-extreme` 已经覆盖 120000 IOPS,默认 SC 没用到 ≠ 不支持;平台方可以加 `prod-db-extreme` SC,你引用就行 |
| "我需要跨 region 同步,默认 SC 没有" | GKE 没有"跨 region 同步 PVC"这种原生能力,这个需求要走 Filestore Enterprise 或迁移到 Bigtable / Spanner,不是新建 SC 能解决的 |
| "我需要在 SC 上挂自定义 snapshot schedule" | 平台方通过 VolumeSnapshotClass + Backup for GKE 统一提供,不需要 SC 字段 |
| "我们的 namespace 有特殊合规要求" | 这正是平台方应该提供 named SC 的场景,新建命名 SC(如 `finance-cmek-restricted`),不需要业务方自己创建 |
| "我们想用 pd-balanced,默认都是 pd-ssd 太贵" | 改默认 SC 字段可以加 `prod-economy` SC,不要绕过预建清单 |

唯一**真正合理**的"业务方需要新 SC" 场景是:
- **平台方没有覆盖到的全新 GCP 存储技术出现**(比如未来 GKE 加新 driver)— 这应当由平台方主导纳入清单,业务方提 issue / PR 即可
- **明确的时间窗:平台方快速反应的承诺 + 业务方 SLA 可接受短暂降级到 default SC**

---

## 8. 落地清单 — 平台方从 0 到 1 的操作步骤

按依赖顺序:

1. **冻结默认 SC**:`kubectl patch storageclass standard-rwo ...` 移除 `storageclass.kubernetes.io/is-default-class` annotation,避免业务方依赖默认行为。**注意**:这要确定集群内没有存量 PVC 走默认,否则应渐近迁移
2. **预建命名 SC**:参考 §5 清单,每个 SC 配 `provisioner: pd.csi.storage.gke.io` + `volumeBindingMode: WaitForFirstConsumer` + `allowVolumeExpansion: true`
3. **封装成 TF / Pulumi module**:`modules/gke/sc/<name>/main.tf`,输出 SC name + KMS key 引用 + 计费标签,落到 infra-as-code
4. **配置 RBAC**:`storageclasses create` / `update` / `delete` / `patch` 的动词全部只给 GCP infra 团队 IAM user / Group,不给业务 namespace SA
5. **应用 Gatekeeper allowlist**:参考 §6 的 YAML,先在 audit 模式跑一周(看 violations,不影响业务),再切 deny
6. **更新文档 + README**:列出全部平台预建 SC,每个标用途 + 性能 + 价格档
7. **CI guard(可选)**:`preflight` job 拒绝合并任何引用未平台 SC 的 PVC yaml,作为 Gatekeeper 之上的二次兜底

---

## 9. 反向风险清单 — 模式 C 也会出问题的地方

不能假装模式 C 没成本:

1. **平台反应速度瓶颈**:业务方提诉求 → 平台加 SC → 发版本。如果 SLA 是几小时,业务方可能绕过(自建)
   - **应对**:平台维护"常用 SC 申请表"Slack bot,小时级响应 + 紧急 SC 通道
2. **SC 命名漂移**:`prod-db-ssd` v1 / v2 怎么共存
   - **应对**:SC 不可变(immutable),要变更就新建 SC 名而不是改老 SC
3. **业务方误用低性能 SC**:用 `cold-arch` 当生产 DB 的盘,故障后才发现
   - **应对**:Gatekeeper 加 allowlist-allowlist 二次嵌套,或者用 `mutating webhook` 自动按 namespace 改 PVC 的 SC
4. **多集群(如 GKE fleet)不一致**:cluster A 有 `prod-db-ssd`,cluster B 没有
   - **应对**:SC 定义走 GitOps(FluxCD / Config Sync),所有集群从同一 Git repo 拉取

---

## 10. 完整交付三件套(权威证据 / 最终定型依据)

### 10.1 Google 官方文档

- GKE Storage overview: <https://cloud.google.com/kubernetes-engine/docs/concepts/storage>
- Compute Engine Persistent Disk CSI driver: <https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes-pd>
- Filestore CSI driver: <https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes-filestore>
- GCS FUSE CSI driver: <https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes-gce-csi>
- Backup for GKE + VolumeSnapshotClass: <https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke>

### 10.2 Kubernetes 官方

- StorageClass 概念: <https://kubernetes.io/docs/concepts/storage/storage-classes/>
- PersistentVolume: <https://kubernetes.io/docs/concepts/storage/persistent-volumes/>
- CSI 规范: <https://kubernetes-csi.github.io/docs/>

### 10.3 Gatekeeper / OPA

- K8sStorageClass template source(被 storageclass.md §"模板信息" 引用):<https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general/storageclass>
- Gatekeeper "inventory" 数据同步机制(被 storageclass.md §"关键" 引用,作用于集群已注册 SC 列表同步):<https://open-policy-agent.github.io/gatekeeper/website/docs/sync/>

### 10.4 工程实践 GitHub Issues / PR

- gatekeeper-library 中 K8sStorageClass 模板 v1.1.2 的 release notes(模板字段 `includeStorageClassesInMessage`、`allowedStorageClasses` 的语义定义都在这里)
- GoogleContainerTools(Anthos Config Management) 的 SC allowlist 示例 HCL(`terraform-modules/kubernetes/sc/allowlist`)—

### 10.5 Lex 已沉淀的内部参考

- `gcp/gke/opa-gatekeeper/constraint-explorers/storageclass.md` — 本文 §1 §4.3 §6 都引用
- `gcp/skills/gke-basics/references/gke-storage.md` — 本文 §1 §3 §5 都引用
- `gcp/gke/opa-gatekeeper/constraint-explorers/` 目录下的其他 constraint 文档(用于交叉验证 Gatekeeper 治理范式)
