# 02 · 跨 project Bucket IAM Policy 设置指南(infra-gcp 视角)

> **本节是 infra-gcp 视角的"怎么在 user-bucket-project 配置 IAM policy,让 master-project 的 KSA 能写"**

---

## 1. 核心原则

| 原则 | 说明 |
|---|---|
| **最小权限** | `roles/storage.objectCreator`,不要用 `objectAdmin` |
| **Prefix-bound** | IAM `condition` 限定 object key prefix |
| **KSA principal 格式** | `serviceAccount:PROJECT.svc.id.goog[NAMESPACE/KSA_NAME]` |
| **不要给 GSA** | 走 WIF 链路,KSA → principal,不需要中间 GSA |

---

## 2. IAM policy JSON 模板

### 2.1 写权限(KSA → objectCreator)

```json
{
  "bindings": [
    {
      "role": "roles/storage.objectCreator",
      "members": [
        "serviceAccount:master-project.svc.id.goog[api-ns/api-bucket-writer]"
      ],
      "condition": {
        "title": "api-ns-prefix-only",
        "description": "只允许写 api-data/ 前缀",
        "expression": "resource.name.startsWith('projects/_/buckets/user-data/objects/api-data/')"
      }
    }
  ]
}
```

**关键**:
- `serviceAccount:master-project.svc.id.goog[api-ns/api-bucket-writer]` — **WIF 格式**,不是 GSA email
- `condition.expression` — **必须**限定 prefix,即使 IAM 配错也只影响指定 prefix

### 2.2 读权限(只读场景)

```json
{
  "bindings": [
    {
      "role": "roles/storage.objectViewer",
      "members": [
        "serviceAccount:master-project.svc.id.goog[api-ns/api-bucket-reader]"
      ]
    }
  ]
}
```

**注**:读权限一般不需要 `condition`,因为读是 idempotent(不会写)。

### 2.3 不要的权限模式

| ❌ 模式 | 原因 |
|---|---|
| `roles/owner` | 权限爆炸,违反最小权限 |
| `roles/editor` | 同上 |
| `roles/storage.objectAdmin` | 包含 delete,业务方应单独评估 delete 需求 |
| `allUsers` / `allAuthenticatedUsers` | **数据泄漏** |
| 不带 `condition` 的 objectCreator | 一旦 KSA 泄漏,整个 bucket 可写 |

---

## 3. gcloud 命令(infra-gcp 执行)

### 3.1 创建 Bucket(在 user-bucket-project)

```bash
# 用 infra-gcp 的 SA 鉴权(详见 ADR-009 §13)
gcloud config set project user-bucket-project

# 创建 bucket
gsutil mb -p user-bucket-project -c STANDARD -l asia-northeast1 \
  -b on gs://user-data

# 开启 uniform bucket-level access(强制 IAM,禁用 ACL)
gsutil iam ch allUsers:legacyObjectReader gs://user-data 2>/dev/null || true  # 移除可能存在的旧 ACL
gsutil uniformbucketlevelaccess set on gs://user-data
```

### 3.2 配置 IAM policy(允许 master-project KSA 写)

```bash
# 准备 IAM policy 文件(参考 §2.1 模板)
cat > /tmp/bucket-iam-policy.json <<'EOF'
{
  "bindings": [
    {
      "role": "roles/storage.objectCreator",
      "members": [
        "serviceAccount:master-project.svc.id.goog[api-ns/api-bucket-writer]"
      ],
      "condition": {
        "title": "api-ns-prefix-only",
        "description": "只允许写 api-data/ 前缀",
        "expression": "resource.name.startsWith('projects/_/buckets/user-data/objects/api-data/')"
      }
    }
  ]
}
EOF

# 应用到 bucket
gcloud storage buckets set-iam-policy gs://user-data /tmp/bucket-iam-policy.json
```

### 3.3 验证

```bash
# 验证 IAM policy 已应用
gcloud storage buckets get-iam-policy gs://user-data

# 应该看到:
#   - role: roles/storage.objectCreator
#   - members: serviceAccount:master-project.svc.id.goog[api-ns/api-bucket-writer]
#   - condition: prefix-only
```

---

## 4. CMEK 加密(强烈推荐)

如果业务方要求 user data 加密(默认 GCP-managed 也够,强需求才用 CMEK):

```bash
# 1. 在 user-bucket-project 创建 CMEK key ring + key
gcloud kms keyrings create tenant-tnt-001 --location global --project user-bucket-project
gcloud kms keys create pd-key \
  --location global --keyring tenant-tnt-001 \
  --purpose encryption --project user-bucket-project

# 2. 给 GCS service account 访问 CMEK 的权限
# (GCS 服务账户是 google-managed,需要 grant)

# 3. 创建 bucket 时指定 CMEK
gsutil mb -p user-bucket-project -c STANDARD -l asia-northeast1 \
  -k projects/user-bucket-project/locations/global/keyRings/tenant-tnt-001/cryptoKeys/pd-key \
  -b on gs://user-data
```

**注意**:CMEK 涉及跨 project KMS 权限,需要 Security + infra-gcp 联合配置。

---

## 5. 常见错误

### ❌ 错误 1:用 GSA email 而不是 KSA principal

```json
// ❌ 不要这么写
{
  "role": "roles/storage.objectCreator",
  "members": [
    "serviceAccount:bucket-writer-sa@user-bucket-project.iam.gserviceaccount.com"
    // ← 这是 GSA,WIF 链路下不会生效
  ]
}
```

**修正**:用 KSA principal 格式:
```json
{
  "members": [
    "serviceAccount:master-project.svc.id.goog[api-ns/api-bucket-writer]"
  ]
}
```

### ❌ 错误 2:不带 condition

```json
// ❌ 不要这么写(一旦 KSA 泄漏,整个 bucket 可写)
{
  "role": "roles/storage.objectCreator",
  "members": ["serviceAccount:..."]
  // ← 没有 condition,无法限制 prefix
}
```

**修正**:加 `condition.expression` 限定 prefix。

### ❌ 错误 3:用 `objectAdmin` 而不是 `objectCreator`

```json
// ❌ 包含 delete 权限,业务方不需要
{
  "role": "roles/storage.objectAdmin"
}
```

**修正**:写用 `objectCreator`,删用单独 `objectAdmin` 且业务方需额外审批。

---

## 6. 验证清单

- [ ] Bucket IAM policy 已应用
- [ ] KSA principal 格式正确(`PROJECT.svc.id.goog[NS/KSA]`)
- [ ] `condition.expression` 限定 prefix
- [ ] role 是 `objectCreator` 而不是 `objectAdmin`
- [ ] 验证 `gcloud storage buckets get-iam-policy` 输出符合预期
- [ ] CMEK 已配(如果业务方要求)

---

## 7. 跨 project 流程总览

```
master-project (infra-gcp 操 作)        user-bucket-project (infra-gcp 操作)
┌─────────────────────┐              ┌─────────────────────┐
│ 1. 启用 WIF on cluster│              │                     │
│ 2. 创建 namespace    │              │                     │
│ 3. 创建 KSA          │              │                     │
│ 4. 绑 WIF annotation │              │                     │
│    (KSA principal)   │              │                     │
└─────────────────────┘              │ 5. 创建 Bucket       │
                                       │ 6. 配 IAM policy     │
                                       │    (KSA principal)   │
                                       │ 7. 配 CMEK (可选)   │
                                       └─────────────────────┘
```

业务方**完全不需要碰 user-bucket-project**。

---

## 8. 下一步

- 业务方澄清 §1.3 的 6 个阻塞问题
- infra-gcp 评审 + 按本指南 §3 执行
- devops-gcp 配 Cloud Audit Logs → BigQuery export(归因)
- qa-gcp 端到端验证