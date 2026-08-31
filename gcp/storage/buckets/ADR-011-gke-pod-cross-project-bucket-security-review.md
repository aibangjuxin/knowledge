# ADR-011: GKE Pod 跨项目访问 Cloud Storage Bucket 安全与架构影响评估

> 👉 **3 协议总览(SMB / NFS / Bucket)对比** 见 [`../STORAGE-3-PROTOCOLS-COMPARISON.md`](../STORAGE-3-PROTOCOLS-COMPARISON.md)
>
> Status: **Proposed** · Date: 2026-08-31 · Author: **architect-gcp** · Reviewers: **infra-gcp** / **devops-gcp** / **qa-gcp**
>
> 用户场景:用户的 API Pod 部署在 master-project(平台项目)的 GKE 集群,需要把用户数据写到位于 **独立项目 user-bucket-project** 的 Cloud Storage Bucket 中。本 ADR 仅做"是否可行 + 风险面 + 加固建议"的架构评估,**不替业务方决定存储位置**。
>
> **ADR 编号说明**:ADR-010 已被 [ADR-009 §10.3 / §10.6](../nas/ADR-009-gke-pod-mount-internal-nas-security-review.md) 预留给 NAS 实施细节,本场景使用 **ADR-011**。

---

## 0. TL;DR(30 秒读完)

| 简化解释 | 严格原话(一手来源) |
|---|---|
| **可行,Workload Identity Federation + 跨 project IAM 是 Google 推荐路径。** | "Workload Identity Federation for GKE lets you use IAM policies to grant Kubernetes workloads in your GKE cluster access to specific Google Cloud APIs without needing manual configuration or less secure methods like service account key files." — [GKE Workload Identity Federation](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity) |
| **拒绝 SA key 方式(凭据泄漏风险大)。** | "[SA key export] can present a security risk if they are not managed correctly. Workload Identity Federation eliminates the maintenance and security burden associated with service account keys." — [IAM Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) |
| **同 "不存用户数据" 原则 — 挂 Bucket 是 "代理档" 灰色地带,需 PM 评估。** | 平台原则:任何持久化到 GCP 服务的用户数据 = 档 1 红线,见 [ADR-009 §6.3](../nas/ADR-009-gke-pod-mount-internal-nas-security-review.md#63-推荐做法扩展版行为判定矩阵--4-条红线--流程图) |
| **跨 project IAM 边界天然隔离,但 audit 链 GKE ↔ Cloud Storage 同样断。** | GKE audit + Cloud Audit Logs 默认不自动拼接,需手工关联(详见 §2.4) |
| **业务方写 Deployment,平台写 Bucket IAM policy + KSA 绑定。** | 与 ADR-009 NAS 场景同分工(详见 §6) |

**一句话总结**:技术上 100% 可行且 Google 推荐;**默认配置下,跨 project Bucket 访问 = 平台变成"Bucket 代理",需业务方 + Manager 评估,且 audit 拼接 + 4 红线自检必备**。

---

## 1. 背景 —— 这到底在说什么

### 1.1 用户的真实需求

```text
项目 A (master-project,平台)
   GKE 集群 → API Pod

项目 B (user-bucket-project,独立)
   Cloud Storage Bucket (用户数据)
```

**关键点**:**API Pod 和 Bucket 不在同一个 GCP project**。

### 1.2 Cloud Storage vs NAS 关键差异(承接 ADR-009)

| 维度 | NAS(ADR-009 主体) | Cloud Storage Bucket(ADR-011 主体) |
|---|---|---|
| **物理位置** | 公司内网 | **GCP 内,跨 project** |
| **协议** | SMB / CIFS(TCP 445) | HTTPS / REST API + gRPC |
| **凭据** | SMB username/password | **GCP IAM**(SA + Workload Identity)|
| **挂载方式** | 文件系统 mount(`/mnt/nas`) | **API 调用**(`storage.Objects.Insert`)|
| **访问粒度** | 文件级 | Object 级(无文件系统抽象)|
| **多租户隔离** | NAS 端共享 ACL(失效)| **GCP IAM policy**(完整覆盖)|
| **加密** | SMB encryption / WireGuard | **GCP-managed CMEK**(强制)|
| **审计** | NAS event log + GKE audit(断链) | **Cloud Audit Logs**(与 GKE audit 同体系)|

### 1.3 必须先澄清的业务语义(交付前阻塞项)

| # | 问题 | 默认假设 | 影响 |
|---|---|---|---|
| Q1 | **读写语义** —— Pod 写 / 读 Bucket? | **默认写**(用户上传数据)| 写 = 持久化到 GCP,**档 1 红线触发,需 PM 评估** |
| Q2 | **挂载范围** —— 整个 namespace 还是单个 Pod? | **单个目标 Pod** | 与 ADR-009 Q2 一致 |
| Q3 | **数据归属** —— Bucket 上的 object 是谁的? | **业务方用户所有** | 决定"是否构成事实上的用户数据代理" |
| Q4 | **读写分离** —— 业务方是否需要分 read / write bucket? | 默认同一 bucket,后续可拆 | 涉及 IAM 分权 |
| Q5 | **数据驻留** —— Bucket 在哪个 region? | 默认与 GKE cluster 同 region | 跨境 / 跨 region 涉及合规 |
| Q6 | **生命周期** —— Object 多久过期 / 是否版本化? | 业务方后续定义 | 涉及 Bucket policy + Lifecycle rule |

---

## 2. Blast Radius —— 5 个冲击维度

### 2.1 维度 ① 跨 project IAM 边界

**核心**:API Pod 在 master-project 的 GKE,要在 user-bucket-project 访问 Bucket,**必须通过 GCP IAM 跨 project 授权**。

```
master-project                    user-bucket-project
┌─────────────────────┐            ┌─────────────────────┐
│  GKE Cluster         │            │  Bucket:user-data  │
│   ↓                  │   IAM?     │                     │
│  KSA:api-bucket-sa   │ ─────────► │  IAM policy:        │
│   (K8s ServiceAccount)│            │  allow KSA principal│
└─────────────────────┘            │  roles/storage.      │
                                     │  objectCreator       │
                                     └─────────────────────┘
```

**3 种跨 project 授权方式**(完整对比见 §3):

| 方式 | 简介 | 推荐度 |
|---|---|---|
| **A. Workload Identity Federation + 跨 project IAM allow policy** | KSA 绑 GSA principal,直接给 IAM role | ⭐ **推荐** |
| **B. SA Impersonation 跨 project** | KSA → 临时 impersonate 跨 project GSA | 备选 |
| **C. SA key 挂 K8s Secret 跨 project** | 下载 JSON key 跨 project | ❌ **不推荐**(凭据风险)|

### 2.2 维度 ② 凭据泄漏风险

| 方式 | 凭据形态 | 风险等级 |
|---|---|---|
| **A. Workload Identity Federation** | **无静态凭据** — KSA 通过 metadata server 拿短期 token | **低** |
| **B. SA Impersonation** | 短期 token,impersonation 链可审计 | 中 |
| **C. SA key** | **JSON key 长期有效**,泄漏后无法追踪 | **高** |

来源:[GKE Workload Identity Federation](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity) — "eliminates the maintenance and security burden associated with service account keys"。

### 2.3 维度 ③ 横向访问面

**关键事实**:**GKE Bucket 访问通过 IAM,不走 NFS / SMB**,因此**没有 NAS 那样的"mount 横向访问面"**。但仍有:

| 横向访问路径 | 是否可能 | 防护 |
|---|---|---|
| 同 namespace 其他 Pod 用同一 KSA | ✅ 是(KSA 是 namespace-scoped) | KSA 最小权限 + 每个应用单独 KSA |
| 跨 namespace Pod 用同一 KSA | ❌ 不可能(KSA 绑 namespace) | K8s RBAC |
| 攻击者拿到 shell 后读 / impersonate | ✅ 是(凭 KSA token) | PodSecurity `restricted` 禁止 shell |
| 任意 Pod 通过 GKE metadata server 拿 token | ✅ 是 | metadata concealment + PodSecurity |

### 2.4 维度 ④ 审计链(覆盖双向纪律)

| 审计来源 | 能看到什么 |
|---|---|
| **GKE audit log** | KSA / Pod / PVC 操作;谁 `kubectl exec` 进 Pod |
| **Cloud Audit Logs(管理员活动)** | IAM policy 变更、Service Account 创建 |
| **Cloud Audit Logs(数据访问)** | **Bucket object 读写** — 这是 GCS 自带 |
| **Cloud Logging 数据流** | Pod 内部 log → Cloud Logging(可与 audit 关联)|

> **优势 vs NAS**:**GCS audit 与 Cloud Audit Logs 同 GCP 体系**,可以靠 `principalEmail` + `resource` 字段自动关联。比 NAS 强很多。

### 2.5 维度 ⑤ "不存用户数据"原则的边界(同 NAS)

**严格意义**:**业务方写数据到 Bucket,等于平台"代理"用户数据持久化到 GCP** = 档 1 红线(详见 ADR-009 §6.3)。

| 行为 | 档位 | 是否违反原则 |
|---|---|---|
| Pod 写 object 到 Bucket | 档 1 ❌ + 档 3 长期代理 | ⚠ **需 PM + Manager 评估 + POC** |
| Pod 读 object 后立刻转发,不持久化 | 档 3 临时代理 | ⚠ 小灰区 |
| Pod 用 Bucket 做配置存储(非用户数据) | 档 1 ✅ | ✅ 不违反 |

> **核心区别**:NAS 是**只读**且数据**始终在公司**,Bucket 是**写且数据落在 GCP**。Bucket 场景的合规压力**远高于 NAS**。

---

## 3. 协议与凭据链路 —— 4 跨项目访问方式详细对比

### 3.1 方式 A:Workload Identity Federation + 跨 project IAM(推荐)

```
┌────────────────────────────────────────────────────────────────┐
│  master-project GKE                                              │
│                                                                  │
│  Pod (api-bucket-writer)                                         │
│    ↓ 使用 KSA                                                    │
│  KSA:api-bucket-writer (api-ns)                                  │
│    ↓ Workload Identity Federation                                │
│  GSA principal:serviceAccount:api-bucket-writer@master-project    │
│    ↓ IAM allow policy 在 user-bucket-project                     │
│  roles/storage.objectCreator (on bucket:user-data)                │
│                                                                  │
│  数据通路(全程 Google 内网):                                    │
│  Pod → KSA → metadata server → STS                              │
│  → user-bucket-project Cloud Storage                              │
└────────────────────────────────────────────────────────────────┘
```

**关键属性**:

| 属性 | 值 |
|---|---|
| 凭据 | **无静态** — 短期 token(默认 1 小时) |
| 设置复杂度 | 中(在 user-bucket-project 加 IAM policy)|
| 审计 | 完整(GKE audit + Cloud Audit Logs 同体系)|
| 多租户隔离 | ✅ KSA → GSA principal 精确绑定,最小权限 |
| 凭据轮换 | 自动(token 过期)|
| 跨 region / 跨 project | ✅ 支持 |

**适用场景**:**本 ADR 主路径,所有 GKE Pod 跨 project GCS 访问的默认方案**。

### 3.2 方式 B:KSA → GSA Impersonation

```
Pod → KSA → (impersonate) → GSA (in user-bucket-project)
       → Bucket
```

**优势**:audit 链更清晰(KSA → "actAs" GSA → 操作)
**劣势**:增加一步 impersonation,延迟 +5-15ms
**适用**:审计要求更高的场景(如金融)

### 3.3 方式 C:SA key 挂 K8s Secret(❌ 不推荐)

**为什么不推荐**(Google 自己的文档原话):

> "These alternatives require you to make certain security compromises."

具体风险:
- SA key 是 **JSON 文件**,长生命周期(默认 10 年,可手动 rotate)
- 泄漏后**任何人**持有 key 都能以 SA 身份操作
- K8s Secret 加密强度有限(multi-tenant 集群有 Secret 跨 ns 风险)
- 审计只能到 SA,**不能**追溯到具体 Pod / KSA

### 3.4 方式 D:Bucket 跨 project IAM policy 直接授权

类似方式 A,但简化:**Bucket IAM policy 直接接收 KSA principal**(无需中间 GSA 绑定)。

```
Pod → KSA principal
            ↓ Bucket IAM policy 直接授权
Bucket (user-bucket-project)
```

**优势**:配置更简单,一层 IAM
**劣势**:与 tenant 隔离机制复杂(每个 tenant 一个 KSA principal)

### 3.5 协议栈对比表

| 维度 | A(WIF)| B(Impersonation)| C(SA key)| D(直接 IAM)|
|---|---|---|---|---|
| 凭据形态 | 短期 token | 短期 token | JSON key(长期)| 短期 token |
| 凭据风险 | 极低 | 低 | **高** | 低 |
| 设置复杂度 | 中 | 中高 | 低 | 中 |
| 审计清晰度 | 中 | 高 | 低 | 中 |
| 跨 region 支持 | ✅ | ✅ | ✅ | ✅ |
| 跨 project 支持 | ✅ | ✅ | ✅ | ✅ |
| Google 推荐 | ⭐ | 备选 | | 场景化 |
| 业务方 YAML 复杂度 | 中(KSA annotation) | 中(KSA + SA annotation)| 简单(+ Secret)| 中 |
| **最终推荐** | ⭐⭐⭐ | ⭐ | ❌ | ⭐⭐ |

---

## 4. 跨 project IAM 设计

### 4.1 IAM allow policy 模板

```json
{
  "bindings": [
    {
      "role": "roles/storage.objectCreator",
      "members": [
        "serviceAccount:master-project.svc.id.goog[api-ns/api-bucket-writer]"
      ],
      "condition": {
        "title": "api-ns-only",
        "expression": "resource.name.startsWith('projects/_/buckets/user-data/objects/api-data/')"
      }
    }
  ]
}
```

**关键点**:
- `serviceAccount:PROJECT.svc.id.goog[NAMESPACE/KSA_NAME]` — Workload Identity Federation 格式
- **绑定 KSA 主体的格式**(不是 GSA)
- **condition 限定前缀** — 即使 IAM 配错,也限定在指定 prefix

### 4.2 最小权限清单

| 角色 | 何时用 | 最小权限 |
|---|---|---|
| **写 Bucket** | API 写用户数据 | `roles/storage.objectCreator` |
| **读 Bucket** | API 读配置 / 数据 | `roles/storage.objectViewer` |
| **删除 Object** | 业务方明确需要 | `roles/storage.objectAdmin` |
| **列出 Object** | API 列出文件 | `roles/storage.objectViewer`(已含 list)|

> **最小权限原则**:能用 object-level 不用 bucket-level。能 prefix-bound 不用全 bucket。

### 4.3 网络层补充

**GCS 走 HTTPS / gRPC over GCP 内网**:
- 同 region:走 GCP 内部网络,不经过公网
- 跨 region:走 GCP 骨干网,**默认走公网**(除非开 Private Google Access + Private Service Connect)
- **本场景**:GKE 与 GCS 同 region 时,无需 VPN / PSC 配置

---

## 5. 跨 namespace / 用户隔离

K8s 层(同 ADR-009 §5):

| 维度 | 行为 |
|---|---|
| KSA namespace-scoped | A ns 的 KSA 看不到 B ns 的 KSA |
| RBAC namespace-scoped | RoleBinding 默认锁在 namespace 内 |
| Bucket IAM policy | 跨 project 显式授权,**不在 K8s RBAC 体系内** |

**风险**:KSA 是 namespace-scoped,但**跨 project IAM policy 是 cluster 级**。如果 1 个 ns 的 KSA 被绑到 1 个 project 的 IAM,其他 ns 想绑同名 KSA 会冲突。

**最佳实践**:**每个 namespace + tenant 一个 KSA + 一个 IAM policy**(详见 gke/ 部署参考集)。

---

## 6. "不存用户数据"原则的边界(深度分析)

### 6.1 4 红线(沿用 ADR-009 §6.3,本场景特别重要)

| 红线 | 本场景具体含义 |
|---|---|
| **R1 不持久化到 GCP 服务** | ⚠ **Bucket 写入是直接触发红线** — 业务方写 user data 到 Bucket = 平台持久化 user data 到 GCP。**任何 Bucket 写操作必须先 PM 评估** |
| **R2 不写 log / metric 暴露** | Pod log 不出现 object name / user data 内容 |
| **R3 不主动观察用户行为** | Cloud Audit Logs 自动记录 object 读写(不可避免),**只记操作类型,不记内容** |
| **R4 Pod lifecycle 与 NAS 解耦** | 同样适用于 Bucket — Pod 删了,object 还在(对象级独立生命周期)|

### 6.2 与 NAS 场景的关键差异

| 维度 | NAS | Bucket |
|---|---|---|
| **红线条数** | 4 条(同 ADR-009)| 4 条(同 ADR-009)|
| **特别敏感的红线** | R4(Pod lifecycle) | **R1(持久化到 GCP)** + R3(audit 必然记录)|
| **业务方想用前的合规门槛** | 默认 ro + 4 红线自检 | **必须 PM 评估 + POC + 走档 1 例外审批** |
| **技术难度** | 低(SMB CSI driver 成熟)| 中(WIF + IAM 跨 project 配置复杂) |

### 6.3 推荐做法(沿用 ADR-009 §6.4)

1. **默认禁止业务方直接写 Bucket**,任何 user data 持久化必须 PM + Manager 评估
2. 若业务方需要写,Pod 写 **GCS bucket + Lifecycle rule 自动过期**,降低持久化风险
3. **写操作必须 prefix-bound**(如 `api-data/xxx`,业务方不能写其他 prefix)
4. **read-only KSA 默认**,write KSA 需审批
5. **BigQuery 不存 user data**(同 ADR-009 §6)

---

## 7. 既有 PV 多租户设计是否被 Bucket 绕过

| 设计要素 | 对 GCP PD 的覆盖 | 对 Bucket 的覆盖 |
|---|---|---|
| Tenant CRD `scAllowlist` | ✅ | ❌(SC 是 PV 概念, Bucket 走 IAM) |
| Per-tenant CMEK | ✅ | ⚠ **可用但要单独配**(GCS 支持 CMEK)|
| GCP labels `tenant=xxx` | ✅ | ⚠ Bucket 支持 labels,但 BigQuery 归因不自动 |
| ValidatingWebhook(PVC admission)| ✅ | ❌( Bucket 不走 PVC admission)|
| Webhook 跨 project IAM | ❌(没考虑)| ✅ **必须新增**:Bucket 操作 admission webhook |

**影响**:
1. **审计归因失效** — BigQuery 不自动归因 Bucket 操作,需手工对账
2. **多租户 CMEK** — GCS CMEK 可用但**没有 per-tenant 自动绑定**,需手维护
3. **配额失效** — GCS quota 是 project-level,**单租户可能影响其他租户**
4. **Webhook 缺位** — 当前 Tenant CRD 不覆盖 Bucket 操作,需扩展

### 7.1 推荐的修补路径

在 [`gcp/storage/gke-pv-multi-tenant-design.md`](../gke-pv-multi-tenant-design.md) 增加"§12 Bucket 跨 project 多租户":

- Bucket IAM policy 必须由 Tenant CRD 派生(不要手写)
- 每个 tenant 1 个 GCS bucket(而不是共享 1 个)
- BigQuery 归因改用 GCS 操作日志(已含 principalEmail)

---

## 8. 决策树与建议方案

### 8.1 主路径 (A) —— Workload Identity Federation

**适用场景**:**所有跨 project GCS 访问的默认方案**(Google 官方推荐)。

**前置条件**:

| # | 问题 | 必须的答案 |
|---|---|---|
| G1 | 业务方确认 Pod 只用 KSA,**不用 SA key** | ✅ |
| G2 | 业务方接受 NetworkPolicy 强制 | ✅ |
| G3 | 跨 project IAM policy 已配(KSA principal + role) | ✅ |
| G4 | 接受"不存用户数据"档 1 红线例外审批 | ✅ |
| G5 | NAS 性能影响可接受(本场景不适用,删)| N/A |
| G6 | 业务方接受 Cloud Audit Logs 自动记录(不可关闭) | ✅ |
| G7 | 路由连通性(本场景默认 GCP 内网) | ✅(默认) |

**实施清单**(交 infra-g):

1. ☐ 在 user-bucket-project 创建 GCS bucket(`user-data`)
2. ☐ 在 user-bucket-project 配置 IAM policy,绑定 master-project KSA principal
3. ☐ 在 master-project 启用 Workload Identity Federation on GKE cluster
4. ☐ 创建 namespace `api-ns` + KSA `api-bucket-writer`(带 WIF annotation)
5. ☐ 部署 application code(使用 GCS SDK,自动用 KSA token)
6. ☐ NetworkPolicy 锁定 KSA 出栈(可选,GCS 走 GCP 内网不严格需要)
7. ☐ PodSecurity:api-ns 标 `restricted`,业务方 Pod 标更严
8. ☐ Audit:Cloud Audit Logs + BigQuery export(归因)
9. ☐ 文档:在 [`gcp/storage/gke-pv-multi-tenant-design.md`](../gke-pv-multi-tenant-design.md) 加 "§12 Bucket 跨 project 多租户"

### 8.2 替代 (B) —— KSA → GSA Impersonation

**适用场景**:审计要求更高(金融 / 医疗)。

**代价**:增加 impersonation 步骤,延迟 +5-15ms。

### 8.3 替代 (C) —— SA key 挂 Secret(❌ 不推荐)

**适用场景**:**无**。Google 自己说不推荐。

### 8.4 替代 (D) —— Bucket 直接 IAM(场景化推荐)

**适用场景**:**只读 / 只写** 简单场景,不需要中间 GSA 绑定。

### 8.5 禁用方案

| 方案 | 禁止原因 |
|---|---|
| SA key 挂 Secret | 凭据泄漏风险 |
| 默认 service account + Editor role | 违反最小权限 |
| Bucket 公共 ACL | 数据泄漏 |
| 关闭 Cloud Audit Logs 数据访问记录 | 审计失效 |

---

## 9. 一手引用与上游文档

| 编号 | 主题 | URL |
|---|---|---|
| R1 | GKE Workload Identity Federation | https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity |
| R2 | IAM Workload Identity Federation | https://cloud.google.com/iam/docs/workload-identity-federation |
| R3 | GCS 跨 project access | https://cloud.google.com/storage/docs/access-control/using-uniform-bucket-level-access |
| R4 | Cloud Audit Logs | https://cloud.google.com/logging/docs/audit |
| R5 | K8s ServiceAccount | https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/ |
| R6 | GCS IAM roles | https://cloud.google.com/storage/docs/access-control/iam-roles |
| R7 | ADR-009 主 ADR(NAS 场景对比) | [gcp/storage/nas/ADR-009-gke-pod-mount-internal-nas-security-review.md](../nas/ADR-009-gke-pod-mount-internal-nas-security-review.md) |
| R8 | 既有 PV 多租户设计 | [gcp/storage/gke-pv-multi-tenant-design.md](../gke-pv-multi-tenant-design.md) |

---

## 10. 下一步

1. **本 ADR 等待 review**:infra-gcp / devops-gcp / qa-gcp 各自 review 自己的 lane
2. **业务方澄清**:§1.3 的 6 个阻塞问题 + §8.1 的 7 治理问题
3. **如决策走 A**:生成 ADR-011 实施细节(独立文档)+ handoff 给 infra-gcp
4. **如决策走 D**:简化 IAM policy 配置,无需 GSA 绑定
5. **配套文档同步**:在 [`gcp/storage/gke-pv-multi-tenant-design.md`](../gke-pv-multi-tenant-design.md) 增加 §12

---

## 11. Review Notes

> 本节预留业务方 review 轮次扩展内容。

### 11.1 Review 时间线(待填)

### 11.2 待澄清(待填)

---

## 12. 概念澄清 —— Pod 跨 project 访问 Bucket 跟 PV 是什么关系

> 本节回应"挂 Bucket 跟 PV 体系"的问题。

### 12.1 核心结论

> **PV/PVC 是 K8s 抽象,用于文件系统和块存储;Bucket 访问是 GCP API 调用,不经 PV 抽象,直接走 IAM**。两者**完全不冲突**,Pod spec 里写 `volumes` 挂 NAS,但写 Bucket 用 `GOOGLE_APPLICATION_CREDENTIALS`(自动) + GCS SDK。

### 12.2 三个层次

```
┌────────────────────────────────────────────────────────────────┐
│  Pod spec                                                     │
│    containers: [api]                                          │
│    volumes: [nas-app-folder](挂 NAS)                        │
│    serviceAccountName: api-bucket-writer(KSA)              │
│                                                                 │
│  application code:                                            │
│    write_to_bucket(object_name, data) —  GCS SDK 自动用 KSA │
└────────────────────────────────────────────────────────────────┘
```

### 12.3 关键事实

- **Pod 不需要 GOOGLE_APPLICATION_CREDENTIALS** — Workload Identity Federation 自动通过 metadata server 注入
- **应用代码只需用 GCS SDK** — 不需要管 IAM、SA、project 边界
- **跨 project 完全透明** — application 只看到 `gs://user-data/...`,不知道是哪个 project

### 12.4 vs ADR-009 NAS 场景

| 维度 | NAS(ADR-009)| Bucket(ADR-011)|
|---|---|---|
| 挂载方式 | 文件系统 mount | **API 调用** |
| 凭据位置 | K8s Secret(SMB user/pass) | **GCP IAM,自动通过 metadata server** |
| 数据物理位置 | 公司内网 | **GCP 内,跨 project** |
| 业务方知道挂载吗 | 知道(`/mnt/nas`)| **完全不知道 IAM** |
| Pod spec 复杂度 | volumes + PVC + NAS 凭据 | serviceAccountName + WIF annotation |

### 12.5 FAQ

| 疑问 | 答复 |
|---|---|
| Pod 怎么知道哪个 project 的 Bucket? | GCS SDK 接受完整路径 `gs://BUCKET_NAME/OBJECT_NAME`,不区分 project |
| 跨 project IAM policy 谁配? | 平台团队(Bucket 所在的 user-bucket-project admin)|
| KSA token 怎么跨 project? | Workload Identity Federation 自动,Pod 无感 |
| audit log 跨 project 怎么查? | Cloud Logging 按 project 隔离,需要 BigQuery export 跨 project 查询 |

---

## 13. Bot 协作纪律(同 ADR-009 §13)

| 实体 | 类型 | 有 GCP 身份? |
|---|---|---|
| 业务方 | 真人 | ✅ wide-scope user OAuth |
| architect-gcp | Hermes agent | ❌(也不该有) |
| infra-gcp | Hermes agent | 应有自己的专属 SA + 最小权限 |
| devops-gcp | Hermes agent | 应有自己的专属 SA |
| qa-gcp | Hermes agent | 应有自己的专属 SA |

**关键规则**:
1. 每个 agent profile 必须有专属 GCP identity(SA + 最小权限)
2. agent 不借真人 OAuth
3. agent 卡的 GCP 阻塞项 push back 给真人,不 push back 给 architect
4. architect 不下场跑 g cloud / kubectl / terraform apply

---

> **作者声明**:本 ADR 仅评估"跨 project 访问 Bucket"的技术可行性与安全风险,**不就业务本身的合规性做结论**。若业务方对"写用户数据到 GCP Bucket"是否触犯其他合规约束有疑问,需走法务/合规审查。