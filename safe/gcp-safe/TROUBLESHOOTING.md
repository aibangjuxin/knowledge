# KMS 验证脚本故障排查指南

## 常见问题

### 1. 脚本在"检查前置条件"后立即退出

**已修复的 Bug:** 如果你使用的是旧版本脚本，可能遇到 `((COUNTER++))` 在 `set -e` 模式下导致退出的问题。请使用最新版本的 `verify-kms-enhanced.sh`。详见 `BUG-FIX-EXPLANATION.md`。

**可能原因:**

#### A. gcloud 认证问题
```bash
# 检查当前认证状态
gcloud auth list

# 如果没有活动账号，重新认证
gcloud auth login

# 或使用服务账号
gcloud auth activate-service-account --key-file=path/to/key.json
```

#### B. gcloud 命令输出格式问题
某些旧版本的 gcloud 可能不支持 `--filter` 参数。

**解决方案:**
```bash
# 更新 gcloud
gcloud components update

# 检查版本
gcloud version
```

#### C. 权限不足
当前认证账号可能没有查询项目的权限。

**解决方案:**
```bash
# 测试是否能访问项目
gcloud projects describe YOUR_PROJECT_ID

# 如果失败，检查 IAM 权限
# 需要至少: resourcemanager.projects.get
```

---

### 2. 使用诊断工具

运行诊断脚本快速定位问题：

```bash
./debug-test.sh
```

这会检查:
- Shell 环境
- 必需命令 (gcloud, jq)
- gcloud 认证状态
- 临时目录权限
- jq 解析功能

---

### 3. 启用详细模式

使用 `--verbose` 参数查看详细输出：

```bash
./verify-kms-enhanced.sh \
  --kms-project YOUR_KMS_PROJECT \
  --business-project YOUR_BIZ_PROJECT \
  --keyring YOUR_KEYRING \
  --key YOUR_KEY \
  --location global \
  --service-accounts "sa@project.iam" \
  --verbose
```

---

### 4. 手动测试各个步骤

#### 步骤 1: 测试 gcloud 认证
```bash
# 方法 1
gcloud auth list --filter=status:ACTIVE --format="value(account)"

# 方法 2 (如果方法1失败)
gcloud config get-value account

# 方法 3
gcloud auth list
```

#### 步骤 2: 测试项目访问
```bash
# KMS 项目
gcloud projects describe YOUR_KMS_PROJECT --format=json

# 业务项目
gcloud projects describe YOUR_BIZ_PROJECT --format=json
```

#### 步骤 3: 测试 Keyring 访问
```bash
gcloud kms keyrings describe YOUR_KEYRING \
  --project=YOUR_KMS_PROJECT \
  --location=global \
  --format=json
```

#### 步骤 4: 测试 CryptoKey 访问
```bash
gcloud kms keys describe YOUR_KEY \
  --project=YOUR_KMS_PROJECT \
  --keyring=YOUR_KEYRING \
  --location=global \
  --format=json
```

#### 步骤 5: 测试 IAM 策略获取
```bash
gcloud kms keys get-iam-policy YOUR_KEY \
  --project=YOUR_KMS_PROJECT \
  --keyring=YOUR_KEYRING \
  --location=global \
  --format=json
```

---

### 5. 检查脚本执行权限

```bash
# 确保脚本有执行权限
chmod +x verify-kms-enhanced.sh

# 检查文件权限
ls -la verify-kms-enhanced.sh
```

---

### 6. 检查 Shell 兼容性

脚本需要 Bash 4.0+：

```bash
# 检查 Bash 版本
bash --version

# 如果版本过低，使用新版本 Bash 运行
/usr/local/bin/bash verify-kms-enhanced.sh [参数]
```

---

### 7. 临时目录问题

如果 `/tmp` 目录有问题：

```bash
# 检查 /tmp 权限
ls -ld /tmp

# 检查磁盘空间
df -h /tmp

# 手动清理旧的临时文件
rm -rf /tmp/kms-validator-*
```

---

### 8. jq 解析问题

测试 jq 是否正常工作：

```bash
# 测试 jq
echo '{"test": "value"}' | jq -r '.test'

# 应该输出: value
```

---

## 错误信息对照表

| 错误信息 | 可能原因 | 解决方案 |
|---------|---------|---------|
| `必需命令未找到: gcloud` | gcloud 未安装 | 安装 Google Cloud SDK |
| `必需命令未找到: jq` | jq 未安装 | `apt-get install jq` 或 `yum install jq` |
| `gcloud 未认证` | 没有活动的认证账号 | `gcloud auth login` |
| `无法访问 KMS 项目` | 项目不存在或无权限 | 检查项目 ID 和 IAM 权限 |
| `Keyring 不存在` | Keyring 名称错误或不存在 | 检查 Keyring 名称和位置 |
| `CryptoKey 不存在` | Key 名称错误或不存在 | 检查 Key 名称 |
| `无法获取 IAM 策略` | 无权限查询 IAM | 需要 `cloudkms.cryptoKeys.getIamPolicy` 权限 |

---

## 最小权限要求

执行脚本的账号需要以下权限：

### 在 KMS 项目中:
```yaml
- cloudkms.keyRings.get
- cloudkms.cryptoKeys.get
- cloudkms.cryptoKeys.getIamPolicy
```

### 在业务项目中:
```yaml
- resourcemanager.projects.get
```

### 可选 (用于功能测试):
```yaml
- cloudkms.cryptoKeyVersions.useToEncrypt
- cloudkms.cryptoKeyVersions.useToDecrypt
```

---

## 获取帮助

如果以上方法都无法解决问题：

1. 运行诊断脚本并保存输出:
   ```bash
   ./debug-test.sh > debug-output.txt 2>&1
   ```

2. 使用 verbose 模式运行主脚本:
   ```bash
   ./verify-kms-enhanced.sh --verbose [参数] > output.txt 2>&1
   ```

3. 检查脚本中的错误追踪信息，会显示:
   - 出错的行号
   - 执行的命令
   - 退出码

4. 提供以下信息:
   - 操作系统版本: `uname -a`
   - Bash 版本: `bash --version`
   - gcloud 版本: `gcloud version`
   - jq 版本: `jq --version`
   - 错误输出

---

## 快速测试命令

```bash
# 完整的测试流程
echo "1. 检查环境"
./debug-test.sh

echo "2. 测试脚本帮助"
./verify-kms-enhanced.sh --help

echo "3. 运行实际验证 (替换为你的参数)"
./verify-kms-enhanced.sh \
  --kms-project YOUR_KMS_PROJECT \
  --business-project YOUR_BIZ_PROJECT \
  --keyring YOUR_KEYRING \
  --key YOUR_KEY \
  --location global \
  --service-accounts "sa1@project.iam,sa2@project.iam" \
  --verbose
```
