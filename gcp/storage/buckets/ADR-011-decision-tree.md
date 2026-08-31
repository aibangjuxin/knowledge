# ADR-011 · 决策树清单(GKE 跨 project 访问 Bucket)

> **A 是主路径**(Workload Identity Federation + 跨 project IAM,Google 推荐)。B/C 是替代方案。本决策树由 architect-gcp 设计,**不替业务方拍板**。
>
> 详细分析见 [ADR-011-gke-pod-cross-project-bucket-security-review.md](./ADR-011-gke-pod-cross-project-bucket-security-review.md)。

---

## 路线总览

| 路线 | 凭据 | 设置复杂度 | 安全 | Google 推荐 | 评级 |
|---|---|---|---|---|---|
| **A · WIF + 跨 project IAM** | 短期 token | 中 | 高 | ⭐⭐⭐ | ✅ **主路径** |
| **B · KSA → GSA Impersonation** | 短期 token | 中高 | 高 | 备选 | ⚠ 审计严格场景 |
| **C · SA key 挂 Secret** | JSON key(长期) | 低(配置) | **低** | ❌ 不推荐 | ❌ 禁用 |
| **D · Bucket 直接 IAM** | 短期 token | 中 | 高 | 场景化推荐 | ✅ 简单场景 |

---

## 主路径 (A) 详表

### A 的 7 个治理问题(必须全部 ✅)

**本节经业务方 review 后扩展**(对应 ADR-011 §8.1):

| # | 问题 | 必须的答案 | 影响 |
|---|---|---|---|
| G1 | 业务方确认 Pod 只用 KSA,**不用 SA key** | ✅ | 用 SA key = 触发红线 C,必须驳回 |
| G2 | 业务方接受 NetworkPolicy 强制 | ✅ | 不接受 = 不上线 |
| G3 | 跨 project IAM policy 已配(KSA principal + role) | ✅ | 没配 = Pod 启动后报错 |
| G4 | 接受"不存用户数据"档 1 红线例外审批 | ✅ | Bucket 写 = 档 1 红线,需 PM 走档 1 例外流程 |
| G5 | N/A(本场景不适用,删)| — | — |
| G6 | 业务方接受 Cloud Audit Logs 自动记录(不可关闭) | ✅ | 关不掉,业务方需知情同意 |
| G7 | 路由连通性(本场景默认 GCP 内网) | ✅ | 默认 OK,跨 region 才需 Private Service Connect |

### A 的实施清单(交 infra-gcp)

1. ☐ 在 user-bucket-project 创建 GCS bucket(`user-data`,region 与 GKE 同)
2. ☐ 跨 project IAM policy 绑定 KSA principal(对象级 IAM,不是 bucket 级)
3. ☐ 在 master-project GKE cluster 启用 Workload Identity Federation
4. ☐ 创建 namespace `api-ns` + KSA `api-bucket-writer`(带 WIF annotation)
5. ☐ Deployment `serviceAccountName: api-bucket-writer`(业务方 Pod spec)
6. ☐ 应用代码用 GCS SDK(自动用 KSA token,**不传 GOOGLE_APPLICATION_CREDENTIALS**)
7. ☐ PodSecurity:api-ns 标 `restricted`,业务方 Pod 标更严
8. ☐ Audit:Cloud Audit Logs 数据访问事件 export 到 BigQuery 跨 project 查询
9. ☐ 文档:在 `gcp/storage/gke-pv-multi-tenant-design.md` 加 "§12 Bucket 跨 project 多租户"
10. ☐ 4 红线 CI 检查(同 ADR-009 §6.3)

### A 的 IAM policy 模板(JSON)

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

**关键**:
- `serviceAccount:PROJECT.svc.id.goog[NAMESPACE/KSA_NAME]` — **Workload Identity Federation 格式**(不是 GSA)
- IAM role 用 `objectCreator` 而不是 `objectAdmin`(**不能删**)
- condition 限定 prefix(`api-data/`),即使 IAM 配错也只影响指定 prefix

### A 的代价

| 维度 | 代价 |
|---|---|
| **安全** | KSA 通过 metadata server 拿短期 token,凭据风险极低 |
| **审计** | Cloud Audit Logs 自动记录(操作类型,不记录内容),BigQuery export 可归因 |
| **多租户** | 每个 tenant 一个 KSA + IAM policy,BigQuery 归因需手工配置 |
| **成本** | GCS 存储 + Cloud Audit Logs 数据事件存储 |
| **运维** | GCS object 生命周期 / IAM policy 更新 / KSA 轮换(自动)|

---

## 替代 (B) — Impersonation 详表

**适用场景**:审计要求更严(金融 / 医疗),需要明确 KSA → GSA "actAs" 链。

**与 A 的关键差异**:

| 维度 | A(WIF 直接)| B(Impersonation)|
|---|---|---|
| 配置复杂度 | 低(KSA 绑 IAM role)| 中(KSA + GSA + Impersonation binding)|
| 延迟 | ~ | +5-15ms(impersonation 调用)|
| Audit 链路 | `principalEmail=KSA` | `principalEmail=KSA, actAs=GSA` |
| 配置位置 | IAM policy 在 user-bucket-project | KSA → `roles/iam.workloadIdentityUser` 在 master-project |

**实施(简版)**:
```bash
# 1. 在 user-bucket-project 创建 GSA bucket-writer-sa
gcloud iam service-accounts create bucket-writer-sa --project=user-bucket-project

# 2. 授予 GSA storage.objectCreator on bucket
gcloud storage buckets add-iam-policy-binding gs://user-data \
  --member="serviceAccount:bucket-writer-sa@user-bucket-project.iam.gserviceaccount.com" \
  --role="roles/storage.objectCreator"

# 3. 授予 KSA impersonate GSA
gcloud iam service-accounts add-iam-policy-binding \
  bucket-writer-sa@user-bucket-project.iam.gserviceaccount.com \
  --member="serviceAccount:master-project.svc.id.goog[api-ns/api-bucket-writer]" \
  --role="roles/iam.workloadIdentityUser"
```

---

## 替代 (C) — SA key 挂 Secret(❌ 不推荐)

**为什么不推荐**:

1. Google 自己的文档:"These alternatives require you to make certain security compromises."
2. SA key 是 JSON 文件,长期有效(默认 10 年)
3. 泄漏后无法追溯到具体 Pod / KSA
4. K8s Secret 多租户集群风险(详见 ADR-009 §7)
5. 违反 ADR-009 §6.3 红线 1(持久化到 GCP 服务)+ 引入新的凭据风险

**唯一适用场景**:**无**。如果业务方说"没时间做 IAM",请改回路线 A。

---

## 替代 (D) — Bucket 直接 IAM(简单场景推荐)

**适用场景**:只读或只写,**不需要 GSA 中间层**。

**实施**:直接在 bucket IAM policy 写 KSA principal,不用 impersonation。

```bash
# 跨 project IAM,bucket 直接绑 KSA
gcloud storage buckets add-iam-policy-binding gs://user-data \
  --member="serviceAccount:master-project.svc.id.goog[api-ns/api-bucket-writer]" \
  --role="roles/storage.objectViewer"
```

**与 A 的差异**:A 用 GSA 中间层,D 直接绑 KSA principal。**安全等价**,但 D 更简单。

**何时选 D 不选 A**:1 个 bucket 1 个 KSA,**不需要 GSA 共享**。

---

## 禁用方案

| 方案 | 禁止原因 |
|---|---|
| SA key 挂 Secret | 凭据泄漏风险 |
| 默认 service account + Editor role | 违反最小权限 |
| Bucket 公共 ACL(`allUsers` / `allAuthenticatedUsers`)| 数据泄漏 |
| 关闭 Cloud Audit Logs 数据访问事件 | 审计失效 |
| KSA 直接绑 `roles/owner` | 权限爆炸 |

---

## 决策流程

```
                ┌────────────────────────────────┐
                │  业务方需要跨 project 写 Bucket  │
                └─────────────┬──────────────────┘
                              │
                              ▼
              ┌──────────────────────────────────┐
              │  是否能用 Workload Identity?      │
              │  (GKE ≥ 1.20 都支持)             │
              └───────────┬─────────────┬───────┘
                       YES │          │ NO
                          ▼          ▼
            ┌─────────────────┐  ┌──────────────────────┐
            │  A 主路径       │  │  业务方需确认 K8s 版本│
            │  WIF + 跨 IAM  │  │  或考虑 GKE 升级      │
            └────────┬────────┘  └──────────────────────┘
                     │
                     ▼
        ┌─────────────────────────────────────┐
        │  需要更严格的审计链?                │
        │  (金融 / 医疗 / 等保)             │
        └──────────┬────────────────┬──────┘
                YES│                │NO
                  ▼                ▼
            ┌─────────────┐  ┌──────────────────┐
            │ B 替代      │  │ A 主路径 / D 替代│
            │ Impersonation│  │ (简单选 D)       │
            └─────────────┘  └──────────────────┘
```

---

## 推荐结论

> **如果业务方能接受 Workload Identity Federation(几乎所有现代 GKE 都支持),走 A 主路径**。
>
> 简单场景(只读或只写 bucket,无中间 GSA 需求)走 D 替代,**比 A 更简单**。
>
> 严格审计场景(金融 / 医疗)走 B Impersonation。
>
> **C SA key 任何时候都不要走**。

---

## 下一步

- 业务方澄清 §1.3 的 6 个阻塞问题(Q1 读写 / Q3 数据归属 / G1 / G4 等)
- infra-gcp 评审并按 §A 实施清单执行
- 完成后生成 ADR-011 实施细节(独立文档)
- 在 [`gcp/storage/gke-pv-multi-tenant-design.md`](../gke-pv-multi-tenant-design.md) 加 §12 Bucket 跨 project 多租户章节