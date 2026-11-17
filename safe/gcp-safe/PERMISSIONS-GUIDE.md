# KMS 验证脚本权限指南

## 权限要求总览

### 必需权限

#### 在 KMS 项目中
| 权限 | 用途 | 命令 |
|------|------|------|
| `cloudkms.keyRings.list` | 验证 Keyring 存在性 | `gcloud kms keyrings list` |
| `cloudkms.cryptoKeys.list` | 验证 CryptoKey 存在性 | `gcloud kms keys list` |
| `cloudkms.cryptoKeys.getIamPolicy` | 获取密钥 IAM 策略 | `gcloud kms keys get-iam-policy` |

#### 在业务项目中
| 权限 | 用途 | 命令 |
|------|------|------|
| `resourcemanager.projects.get` | 验证项目可访问性 | `gcloud projects describe` |

### 可选权限（用于功能测试）

| 权限 | 用途 | 参数 |
|------|------|------|
| `cloudkms.cryptoKeyVersions.useToEncrypt` | 执行加密测试 | `--test-encrypt` |
| `cloudkms.cryptoKeyVersions.useToDecrypt` | 执行解密测试 | `--test-decrypt` |

---

## 权限方案对比

### 方案 1: 使用 list 权限（推荐）✅

**脚本版本**: v2.0.2+

**需要的权限:**
```yaml
# KMS 项目
- cloudkms.keyRings.list
- cloudkms.cryptoKeys.list
- cloudkms.cryptoKeys.getIamPolicy

# 业务项目
- resourcemanager.projects.get
```

**优势:**
- ✅ 符合最小权限原则
- ✅ 更容易获得授权
- ✅ 适用于大多数场景
- ✅ 仍能获取密钥状态和用途信息

**劣势:**
- ⚠️ 需要使用 filter 来查找特定资源

### 方案 2: 使用 get/describe 权限

**脚本版本**: v2.0.0 - v2.0.1

**需要的权限:**
```yaml
# KMS 项目
- cloudkms.keyRings.get
- cloudkms.cryptoKeys.get
- cloudkms.cryptoKeys.getIamPolicy

# 业务项目
- resourcemanager.projects.get
```

**优势:**
- ✅ 可以直接 describe 特定资源
- ✅ 获取信息更直接

**劣势:**
- ❌ 需要更高的权限
- ❌ 可能难以获得授权

---

## 预定义角色

### 推荐角色

#### 对于 KMS 项目

**选项 1: Cloud KMS Viewer** (推荐)
```yaml
roles/cloudkms.viewer
```
包含的权限:
- ✅ cloudkms.keyRings.list
- ✅ cloudkms.cryptoKeys.list
- ✅ cloudkms.cryptoKeys.getIamPolicy
- ✅ 以及其他只读权限

**选项 2: 自定义角色** (最小权限)
```yaml
title: "KMS Validator"
description: "用于 KMS 验证脚本的最小权限"
stage: "GA"
includedPermissions:
- cloudkms.keyRings.list
- cloudkms.cryptoKeys.list
- cloudkms.cryptoKeys.getIamPolicy
```

#### 对于业务项目

**选项 1: Project Viewer**
```yaml
roles/viewer
```

**选项 2: 自定义角色** (最小权限)
```yaml
title: "Project Reader"
description: "只读项目信息"
stage: "GA"
includedPermissions:
- resourcemanager.projects.get
```

---

## 权限配置示例

### 使用 gcloud 命令授权

#### 1. 授予 KMS Viewer 角色

```bash
# 在 KMS 项目中授予权限
gcloud projects add-iam-policy-binding KMS_PROJECT_ID \
  --member="user:validator@example.com" \
  --role="roles/cloudkms.viewer"
```

#### 2. 授予自定义角色

```bash
# 创建自定义角色
gcloud iam roles create kmsValidator \
  --project=KMS_PROJECT_ID \
  --title="KMS Validator" \
  --description="用于 KMS 验证脚本" \
  --permissions=cloudkms.keyRings.list,cloudkms.cryptoKeys.list,cloudkms.cryptoKeys.getIamPolicy \
  --stage=GA

# 授予自定义角色
gcloud projects add-iam-policy-binding KMS_PROJECT_ID \
  --member="user:validator@example.com" \
  --role="projects/KMS_PROJECT_ID/roles/kmsValidator"
```

#### 3. 授予业务项目权限

```bash
# 授予 Viewer 角色
gcloud projects add-iam-policy-binding BUSINESS_PROJECT_ID \
  --member="user:validator@example.com" \
  --role="roles/viewer"
```

### 使用 Terraform 配置

```hcl
# KMS 项目权限
resource "google_project_iam_member" "kms_viewer" {
  project = var.kms_project_id
  role    = "roles/cloudkms.viewer"
  member  = "user:validator@example.com"
}

# 业务项目权限
resource "google_project_iam_member" "project_viewer" {
  project = var.business_project_id
  role    = "roles/viewer"
  member  = "user:validator@example.com"
}
```

---

## 权限验证

### 测试当前权限

使用提供的测试脚本：

```bash
./test-permissions.sh \
  KMS_PROJECT \
  LOCATION \
  KEYRING \
  CRYPTO_KEY
```

### 手动测试权限

#### 测试 Keyring list 权限
```bash
gcloud kms keyrings list \
  --project=KMS_PROJECT \
  --location=LOCATION \
  --filter="name:KEYRING"
```

#### 测试 CryptoKey list 权限
```bash
gcloud kms keys list \
  --project=KMS_PROJECT \
  --keyring=KEYRING \
  --location=LOCATION \
  --filter="name:CRYPTO_KEY"
```

#### 测试 IAM 策略权限
```bash
gcloud kms keys get-iam-policy CRYPTO_KEY \
  --project=KMS_PROJECT \
  --keyring=KEYRING \
  --location=LOCATION
```

#### 测试项目访问权限
```bash
gcloud projects describe PROJECT_ID
```

---

## 常见权限问题

### 问题 1: "Permission denied" 错误

**错误信息:**
```
ERROR: (gcloud.kms.keyrings.list) User [user@example.com] does not have permission to access projects instance [project-id]
```

**解决方案:**
1. 确认账号有 `cloudkms.keyRings.list` 权限
2. 确认项目 ID 正确
3. 检查是否有项目级别的访问权限

### 问题 2: "Resource not found" vs "Permission denied"

**区别:**
- **Resource not found**: 有权限但资源不存在
- **Permission denied**: 没有权限访问

**验证方法:**
```bash
# 如果返回空列表 [] - 有权限但资源不存在
# 如果返回 Permission denied - 没有权限
gcloud kms keyrings list --project=PROJECT --location=LOCATION
```

### 问题 3: 有 describe 权限但没有 list 权限

**症状:**
- `gcloud kms keys describe` 成功
- `gcloud kms keys list` 失败

**解决方案:**
使用旧版本脚本 (v2.0.1) 或请求 `list` 权限

---

## 最佳实践

### 1. 使用服务账号

```bash
# 创建服务账号
gcloud iam service-accounts create kms-validator \
  --display-name="KMS Validator Service Account"

# 授予权限
gcloud projects add-iam-policy-binding KMS_PROJECT \
  --member="serviceAccount:kms-validator@PROJECT.iam.gserviceaccount.com" \
  --role="roles/cloudkms.viewer"

# 使用服务账号运行
gcloud auth activate-service-account \
  --key-file=kms-validator-key.json
```

### 2. 定期审查权限

```bash
# 查看当前权限
gcloud projects get-iam-policy KMS_PROJECT \
  --flatten="bindings[].members" \
  --filter="bindings.members:user@example.com"
```

### 3. 使用条件 IAM

```bash
# 添加时间限制的权限
gcloud projects add-iam-policy-binding PROJECT \
  --member="user:validator@example.com" \
  --role="roles/cloudkms.viewer" \
  --condition='expression=request.time < timestamp("2025-12-31T23:59:59Z"),title=temporary-access'
```

### 4. 最小权限原则

- ✅ 只授予必需的权限
- ✅ 使用自定义角色而不是预定义角色
- ✅ 定期审查和撤销不需要的权限
- ✅ 使用服务账号而不是用户账号

---

## 权限故障排查

### 诊断流程

```bash
# 1. 检查当前认证账号
gcloud auth list

# 2. 检查账号权限
gcloud projects get-iam-policy KMS_PROJECT \
  --flatten="bindings[].members" \
  --filter="bindings.members:$(gcloud config get-value account)"

# 3. 测试具体权限
./test-permissions.sh KMS_PROJECT LOCATION KEYRING KEY

# 4. 运行脚本诊断
./debug-test.sh
```

---

## 参考资源

- [Cloud KMS IAM 权限](https://cloud.google.com/kms/docs/reference/permissions-and-roles)
- [IAM 最佳实践](https://cloud.google.com/iam/docs/best-practices)
- [自定义角色](https://cloud.google.com/iam/docs/creating-custom-roles)
- [条件 IAM](https://cloud.google.com/iam/docs/conditions-overview)

---

**版本**: v2.0.2  
**最后更新**: 2025-11-10
