# ADR-011 · Pod 跨 project 访问 Bucket 完整链路与顺序概念澄清

> **本文档是 ADR-011 的派生概念文档** —— 专门回答"挂一个跨 project Bucket 到 GKE Pod,从头到尾发生了什么"。
>
> **架构师 lane 边界**:本文档**只做概念澄清 + 流程图**,**不实施任何 provision / apply**,**不创建 Bucket / IAM / KSA**。

---

## 0. TL;DR —— 一句话总结

> **Pod 跨 project 访问 Bucket 不是"挂文件系统",而是经 4 层抽象 + 1 条 IAM 数据通路**:
>
> ```
> Pod 用 GCS SDK 调用
>   → KSA 通过 Workload Identity Federation 自动拿短期 token
>   → metadata server 换 GCP access token
>   → 跨 project IAM policy 验证 KSA principal
>   → Cloud Storage 返回结果
> ```
>
> **业务方完全不用管 IAM,只用 GCS SDK 调 API**。

---

## 1. 为什么需要概念澄清?

业务方常见疑问:

| 疑问 | 在本文档哪节 |
|---|---|
| Pod 跨 project 访问 Bucket 的**完整链路**是什么? | §3 |
| Pod 怎么"知道"自己能用其他 project 的 Bucket? | §3.2(自动 IAM)|
| **Workload Identity Federation** 是什么? | §3.3 |
| 跟 NAS 场景(ADR-009)有什么区别? | §4 |

---

## 2. 为什么 K8s 不直接挂 Bucket?(设计哲学)

### 2.1 K8s 只提供"卷"抽象

K8s 的 `volumes` 抽象只覆盖**块存储 / 文件系统**:

```
Pod spec:
  volumes:
  - name: my-data
    persistentVolumeClaim:
      claimName: pvc-data
  - name: gce-pd
    gcePersistentDisk:
      pdName: my-pd
      fsType: ext4
```

这些是 **节点级 / 文件系统级** 抽象。

### 2.2 Bucket 是对象存储,不是文件系统

**GCS Bucket = 对象存储(Object Store)**:
- 无文件系统抽象
- 通过 HTTPS / gRPC API 访问
- 通过 IAM 控制权限

所以 **Pod 不能 "挂载" Bucket**,只能**调 API**。

### 2.3 K8s 的解决:用 KSA(ServiceAccount)

K8s 提供 **ServiceAccount(KSA)** 作为 Pod 的"身份":
- Pod 用 KSA 标识自己
- KSA 通过 **Workload Identity Federation**(后面解释) 映射到 GCP IAM
- 应用代码用 GCS SDK,**自动用 KSA token**

---

## 3. 完整链路 —— 4 层抽象 + 1 条 IAM 数据通路

### 3.1 4 层抽象(从下到上)

| # | 层 | 角色 | 谁创建 |
|---|---|---|---|
| **L1** | **Pod** | 业务负载 | 业务方 |
| **L2** | **KSA(K8s ServiceAccount)** | Pod 身份 | infra-gcp / 平台 |
| **L3** | **Workload Identity Federation**(GKE metadata server)| KSA → GSA principal 映射 | GKE 自动 |
| **L4** | **Cloud Storage Bucket + IAM** | 真实存储 + 访问控制 | infra-gcp / 平台 |

### 3.2 一条 IAM 数据通路(详细)

```
应用代码                     GKE Node                        GCP IAM                user-bucket-project
   │                            │                              │                            │
   │ upload("api-data/foo")     │                              │                            │
   │ (GCS SDK 自动)             │                              │                            │
   ├──────────────────────────► │                              │                            │
   │                            │                              │                            │
   │                            │ 1. SDK 检查 metadata server │                            │
   │                            │    (169.254.169.254)         │                            │
   │                            │                              │                            │
   │                            │ 2. metadata server 收到请求   │                            │
   │                            │    识别 KSA:                 │                            │
   │                            │    api-ns/api-bucket-writer   │                            │
   │                            │                              │                            │
   │                            │ 3. 换 GCP access token       │                            │
   │                            │    (联邦 token → STS token)  │                            │
   │                            │ ───────────────────────►     │                            │
   │                            │                              │                            │
   │                            │                              │ 4. IAM policy 检查:       │
   │                            │                              │    - KSA principal?       │
   │                            │                              │    - role: objectCreator?  │
   │                            │                              │    - prefix 限定?      │
   │                            │                              │                            │
   │                            │                              │ 5. 转发到 GCS             │
   │                            │                              │ ────────────────────────► │
   │                            │                              │                            │
   │                            │                              │                            │ 6. GCS 执行写
   │                            │                              │                            │
   │                            │ ◄────────── 200 OK ──────────│ ◄──────────────────────── │
   │                            │                              │                            │
   │ ◄─────── "upload OK" ──────│                              │                            │
   │                            │                              │                            │
   ▼                            ▼                              ▼                            ▼
```

**关键观察**:
- 应用代码**完全不用管 IAM、SA、project 边界**
- 应用只看到 `gs://user-data/api-data/foo`,不知道是哪个 project
- **整个过程 0 静态凭据** — metadata server 拿的 token 默认 1 小时过期

### 3.3 Workload Identity Federation 是什么?

> **Workload Identity Federation for GKE** = GKE 让 **K8s ServiceAccount(KSA)** 直接当作 **GCP IAM principal** 用的机制。

**没有 WIF 时**(老做法):

```
Pod → 手动 mount SA key 文件到 /var/secrets/google/key.json
    → GOOGLE_APPLICATION_CREDENTIALS=/var/secrets/google/key.json
    → GCP SDK 自动读 SA key
    → 问题:key 是长期有效,泄漏 = 大事故
```

**有 WIF 时**(Google 推荐):

```
Pod → GKE metadata server 自动注入短期 token
    → GCP SDK 自动用(token 1 小时过期)
    → 凭据安全,审计清晰
```

来源:[GKE Workload Identity Federation 官方文档](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity) — "eliminates the maintenance and security burden associated with service account keys"。

---

## 4. vs NAS 场景(ADR-009)的关键差异

| 维度 | NAS(ADR-009)| Bucket(ADR-011)|
|---|---|---|
| **挂载方式** | 文件系统 mount(`/mnt/nas`)| **API 调用**(`storage.Objects.Insert`)|
| **凭据位置** | K8s Secret(SMB user/pass)| **KSA → metadata server → 短期 token** |
| **数据物理位置** | 公司内网 | **GCP 内,跨 project** |
| **业务方知道挂载吗** | 知道(`/mnt/nas`)| **完全不知道 IAM** |
| **Pod spec 复杂度** | volumes + PVC + NAS 凭据 | serviceAccountName + WIF annotation |
| **协议** | SMB / CIFS(TCP 445) | HTTPS / gRPC over GCP 内网 |
| **审计** | GKE audit + NAS event log(断链)| **Cloud Audit Logs(GKE + GCS 同体系)**|
| **加密** | SMB encryption / WireGuard | **GCP-managed CMEK** |
| **多租户隔离** | NAS 端共享 ACL(失效)| **GCP IAM**(完整覆盖)|

**核心差异**:**Bucket 场景比 NAS 场景更成熟**(GCP 原生支持 IAM + audit + 加密),**但合规压力更大**(数据持久化在 GCP,触发档 1 红线)。

---

## 5. 完整时序图 — Pod 创建 → 写 Bucket 成功

```
时间轴   Pod 业务方           KSA + WIF             metadata server     IAM              Cloud Storage
  │      │                     │                          │                  │                    │
  │  ①   │ 写 Deployment spec   │                          │                  │                    │
  │      │ serviceAccountName:  │                          │                  │                    │
  │      │ api-bucket-writer     │                          │                  │                    │
  │ ───► │ kubectl apply ─────►│                          │                  │                    │
  │      │                     │                          │                  │                    │
  │  ②   │                     KSA 被创建                  │                  │                    │
  │      │                     (infra-gcp)               │                  │                    │
  │      │                     │                          │                  │                    │
  │  ③   │                     绑定 Workload Identity:     │                  │                    │
  │      │                     KSA ↔ IAM principal        │                  │                    │
  │      │                     (annotation)              │                  │                    │
  │      │                     │                          │                  │                    │
  │  ④   │                     Pod 调度到 Node              │                  │                    │
  │      │ ◄──────────────────│                          │                  │                    │
  │      │                     │                          │                  │                    │
  │  ⑤   │ 容器启动              │                          │                  │                    │
  │      │ GCS SDK 初始化        │                          │                  │                    │
  │      │                     │                          │                  │                    │
  │  ⑥   │ upload("foo")        │                          │                  │                    │
  │      │ ──────────────────► │                          │                  │                    │
  │      │                     │                          │                  │                    │
  │      │                     SDK 问 metadata server      │                  │                    │
  │      │                     ─────────────────────────► │                  │                    │
  │      │                     │                          │                  │                    │
  │      │                     │                          │ 换 STS token      │                    │
  │      │                     │                          │ (KSA → GSA       │                    │
  │      │                     │                          │  principal)      │                    │
  │      │                     │                          │                  │                    │
  │      │                     │                          │ 转发 IAM 请求     │                    │
  │      │                     │                          │ ────────────────► │                    │
  │      │                     │                          │                  │                    │
  │      │                     │                          │                  │ IAM 验证:          │
  │      │                     │                          │                  │ - principal 有效?│
  │      │                     │                          │                  │ - role 足够?     │
  │      │                     │                          │                  │ - condition 满足?│
  │      │                     │                          │                  │                    │
  │      │                     │                          │                  │ 转发到 GCS        │
  │      │                     │                          │                  │ ──────────────────►│
  │      │                     │                          │                  │                    │
  │      │                     │                          │                  │                    │ 执行写
  │      │                     │                          │                  │                    │
  │      │                     │                          │ ◄─────── 200 OK ──│ ◄───────────────── │
  │      │                     │                          │                  │                    │
  │      │ ◄─────── upload OK ──│                          │                  │                    │
  │      │                     │                          │                  │                    │
  ▼      ▼                     ▼                          ▼                  ▼                    ▼
```

### 5.1 时序图要点解读

| 步骤 | 谁来做 | 业务方有关吗 |
|---|---|---|
| ① | 业务方 | 写 Deployment spec(只关心 serviceAccountName)|
| ② | infra-gcp | 创建 KSA |
| ③ | infra-gcp | 绑定 WIF annotation |
| ④ | K8s | 调度 |
| ⑤ | 业务方 | 容器启动 + GCS SDK 初始化 |
| ⑥-⑩ | GCS SDK + metadata server + IAM + GCS | **业务方完全无感** |

**业务方只需要关心 ① 和 ⑤** — 中间 5 步全部由平台 + GCP 自动完成。

---

## 6. PSC(Private Service Connect)在哪里?

### 6.1 业务方疑问的来源

跟 NAS 场景类似,"跨 project"听起来像"私有访问",容易跟 **PSC(Private Service Connect)** 混淆。

### 6.2 PSC 在 Bucket 场景的位置

| 场景 | 用 PSC 吗? |
|---|---|
| **同 region 跨 project Bucket 访问** | ❌ **不用**(走 GCP 内网,自动) |
| **跨 region Bucket 访问**(如 GKE 在 asia-northeast1, Bucket 在 us-central1)| ⚠ 可用 PSC 走内网 |
| **从本地 IDC 访问 GCS** | ✅ 用(替代公网) |

**本 ADR 场景默认**:**同 region 跨 project → 走 GCP 内网,无需 PSC**。

### 6.3 何时需要 PSC?

如果 GKE cluster 在 region A, Bucket 在 region B:
- 默认走公网骨干网(Google 自己运营,但仍经公网)
- 用 **Private Service Connect for Google APIs** → 全程 GCP 内网
- 适用:数据驻留 / 合规要求 / 不能经公网

---

## 7. 业务方 FAQ

| 疑问 | 答复 |
|---|---|
| Pod 怎么知道哪个 project 的 Bucket? | GCS SDK 接受完整路径 `gs://BUCKET_NAME/OBJECT_NAME`,**不区分 project** |
| 跨 project IAM policy 谁配? | **平台团队**(Bucket 所在的 user-bucket-project admin)|
| KSA token 怎么跨 project? | **Workload Identity Federation 自动**,Pod 无感 |
| audit log 跨 project 怎么查? | Cloud Logging 按 project 隔离,需要 BigQuery export 跨 project 查询 |
| 业务方需要写 GOOGLE_APPLICATION_CREDENTIALS 环境变量吗? | **不需要**,metadata server 自动注入 |
| Pod 怎么知道 Bucket 在哪个 region? | GCS SDK 自动处理,无需业务方关心 |
| 业务方需要知道 IAM policy 怎么配吗? | **不需要**,平台配好即可 |
| Pod 删了,object 会没吗? | **不会**,GCS object 独立于 Pod 生命周期 |

---

## 8. 跟 ADR-011 章节的映射

| 本文档 | ADR-011 对应章节 | 关系 |
|---|---|---|
| §3 完整链路 | ADR-011 §3.1 方式 A 流程 | 互补(本文档更细) |
| §5 时序图 | ADR-011 §3.1 简化图 | 复用 + 扩展(本文档加 10 步标签) |
| §6 PSC 位置 | ADR-011 §3.5 协议栈对比 | 互补 |
| §7 FAQ | ADR-011 §12.5 FAQ | 互补(本文档更多跨 project FAQ) |

---

## 9. 架构师重申边界

| 能做 | 不做 |
|---|---|
| ✅ 写概念文档 | ❌ 创建 GCS bucket / IAM policy / KSA |
| ✅ 画架构图 | ❌ 配 Workload Identity Federation |
| ✅ 评审回执 | ❌ 跑 gcloud / kubectl |
| ✅ 维护 ADR-011 配套 | ❌ 持有 GCP 凭证 |

---

> **作者声明**:本文档只做概念澄清,**不实施任何 provision / apply**。若业务方基于本文档决定操作模式,实际部署由 infra-gcp 用专属 SA 执行(详见 [ADR-011 主文档 §8.1 实施清单](./ADR-011-gke-pod-cross-project-bucket-security-review.md#81-主路径-a--workload-identity-federation))。