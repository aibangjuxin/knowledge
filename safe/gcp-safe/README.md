# GCP KMS 跨项目权限校验工具

自动化验证 KMS 跨项目加解密架构的完整性和权限配置。

## 快速开始

### 1. 安装依赖

```bash
# 安装 Google Cloud SDK
# https://cloud.google.com/sdk/docs/install

# 安装 jq
# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq

# macOS
brew install jq
```

### 2. 认证

```bash
# 使用用户账号
gcloud auth login

# 或使用服务账号
gcloud auth activate-service-account --key-file=path/to/key.json
```

### 3. 运行验证

```bash
./verify-kms-enhanced.sh \
  --kms-project aibang-project-id-kms-env \
  --business-project aibang-1234567-ajx01-env \
  --keyring aibang-1234567-ajx01-env \
  --key env01-uk-core-ajx \
  --location global \
  --service-accounts "sa1@project.iam,sa2@project.iam"
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `verify-kms-enhanced.sh` | 主验证脚本 (增强版) |
| `debug-test.sh` | 环境诊断工具 |
| `example-usage.sh` | 使用示例 |
| `TROUBLESHOOTING.md` | 故障排查指南 |
| `IMPROVEMENTS.md` | 改进说明 |
| `README.md` | 本文件 |

## 主要功能

- ✅ 资源存在性验证 (项目、Keyring、CryptoKey)
- ✅ IAM 权限分析 (加密/解密权限)
- ✅ 服务账号权限检查
- ✅ 未授权账号检测
- ✅ 密钥轮换策略验证
- ✅ 可选的加密/解密功能测试
- ✅ 支持 Markdown 和 JSON 报告输出
- ✅ 详细的错误追踪和调试模式

## 使用场景

### 场景 1: 日常权限检查
```bash
./verify-kms-enhanced.sh \
  --kms-project PROJECT \
  --business-project PROJECT \
  --keyring KEYRING \
  --key KEY \
  --location global \
  --service-accounts "sa1,sa2"
```

### 场景 2: 故障排查 (详细模式)
```bash
./verify-kms-enhanced.sh \
  --kms-project PROJECT \
  --business-project PROJECT \
  --keyring KEYRING \
  --key KEY \
  --location global \
  --service-accounts "sa1,sa2" \
  --verbose
```

### 场景 3: CI/CD 集成 (JSON 输出)
```bash
./verify-kms-enhanced.sh \
  --kms-project PROJECT \
  --business-project PROJECT \
  --keyring KEYRING \
  --key KEY \
  --location global \
  --service-accounts "sa1,sa2" \
  --output-format json
```

### 场景 4: 完整功能测试 (仅测试环境)
```bash
./verify-kms-enhanced.sh \
  --kms-project PROJECT \
  --business-project PROJECT \
  --keyring KEYRING \
  --key KEY \
  --location global \
  --service-accounts "sa1,sa2" \
  --test-encrypt \
  --test-decrypt
```

## 参数说明

### 必需参数
- `--kms-project` - KMS 项目 ID
- `--business-project` - 业务项目 ID
- `--keyring` - Keyring 名称
- `--key` - CryptoKey 名称
- `--location` - 密钥位置 (如: global, us-central1)
- `--service-accounts` - 服务账号列表 (逗号分隔)

### 可选参数
- `--test-encrypt` - 执行加密功能测试
- `--test-decrypt` - 执行解密功能测试
- `--output-format` - 输出格式: text|json|markdown (默认: text)
- `--skip-rotation-check` - 跳过密钥轮换策略检查
- `--verbose` - 详细输出模式
- `--help` - 显示帮助信息

## 权限要求

### 在 KMS 项目中
- `cloudkms.keyRings.get`
- `cloudkms.cryptoKeys.get`
- `cloudkms.cryptoKeys.getIamPolicy`

### 在业务项目中
- `resourcemanager.projects.get`

### 可选 (用于功能测试)
- `cloudkms.cryptoKeyVersions.useToEncrypt`
- `cloudkms.cryptoKeyVersions.useToDecrypt`

## 故障排查

### 脚本在"检查前置条件"后退出？

1. **运行诊断工具:**
   ```bash
   ./debug-test.sh
   ```

2. **检查 gcloud 认证:**
   ```bash
   gcloud auth list
   ```

3. **使用详细模式:**
   ```bash
   ./verify-kms-enhanced.sh --verbose [其他参数]
   ```

4. **查看完整排查指南:**
   ```bash
   cat TROUBLESHOOTING.md
   ```

## 输出示例

### 终端输出
```
╔════════════════════════════════════════════════════════════════╗
║           GCP KMS 跨项目权限校验工具 v2.0.0                    ║
║                      (Enhanced Edition)                        ║
╚════════════════════════════════════════════════════════════════╝

========================================================================
[INFO] 检查前置条件...
[✓] 前置条件检查通过 (gcloud, jq) - 当前账号: user@example.com
========================================================================
[INFO] 验证 KMS 项目: aibang-project-id-kms-env
[✓] KMS 项目可访问且状态为 ACTIVE
...
```

### Markdown 报告
生成的报告包含:
- 检查统计
- 资源验证结果
- 权限配置详情
- 建议和改进方向

### JSON 报告
```json
{
  "metadata": {
    "timestamp": "2025-11-10T12:00:00Z",
    "kms_project": "...",
    "business_project": "..."
  },
  "summary": {
    "status": "passed",
    "total_checks": 10,
    "passed": 9,
    "warnings": 1,
    "failed": 0
  },
  "checks": [...]
}
```

## CI/CD 集成示例

### GitLab CI
```yaml
validate_kms:
  stage: validate
  script:
    - gcloud auth activate-service-account --key-file=${SA_KEY_FILE}
    - |
      ./verify-kms-enhanced.sh \
        --kms-project ${KMS_PROJECT} \
        --business-project ${BUSINESS_PROJECT} \
        --keyring ${KEYRING} \
        --key ${CRYPTO_KEY} \
        --location ${LOCATION} \
        --service-accounts ${SERVICE_ACCOUNTS} \
        --output-format json
  artifacts:
    reports:
      - kms-validation-report-*.json
    expire_in: 30 days
```

## 最佳实践

1. **定期执行** - 建议每周或配置变更后执行
2. **避免生产测试** - `--test-encrypt/decrypt` 仅在测试环境使用
3. **保留报告** - 用于审计和合规检查
4. **监控告警** - 将验证失败接入告警系统
5. **版本控制** - 将脚本和配置纳入版本控制

## 版本历史

- **v2.0.0** - 增强版
  - 更健壮的 IAM 解析 (使用 jq)
  - 完善的错误处理和追踪
  - 支持 JSON 输出
  - 未授权账号检测
  - 详细的调试模式

- **v1.0.0** - 初始版本
  - 基础验证功能

## 许可证

内部使用

## 支持

遇到问题？
1. 查看 `TROUBLESHOOTING.md`
2. 运行 `./debug-test.sh`
3. 使用 `--verbose` 模式
4. 联系团队支持
