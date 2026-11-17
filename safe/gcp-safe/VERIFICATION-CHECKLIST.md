# 验证清单

在 Linux 服务器上部署和运行脚本前，请按此清单逐项检查。

## ✅ 部署前检查

### 1. 环境准备

- [ ] 已安装 Google Cloud SDK
  ```bash
  gcloud version
  ```

- [ ] 已安装 jq
  ```bash
  jq --version
  ```

- [ ] Bash 版本 >= 4.0
  ```bash
  bash --version
  ```

### 2. 认证配置

- [ ] gcloud 已认证
  ```bash
  gcloud auth list
  ```

- [ ] 当前账号有必需权限
  - KMS 项目: `cloudkms.keyRings.get`, `cloudkms.cryptoKeys.get`, `cloudkms.cryptoKeys.getIamPolicy`
  - 业务项目: `resourcemanager.projects.get`

### 3. 文件准备

- [ ] 脚本文件已上传
  ```bash
  ls -la verify-kms-enhanced.sh
  ```

- [ ] 脚本有执行权限
  ```bash
  chmod +x verify-kms-enhanced.sh
  ```

- [ ] 脚本文件完整性
  ```bash
  wc -l verify-kms-enhanced.sh
  # 应该显示约 800+ 行
  ```

## ✅ 功能验证

### 4. 运行诊断工具

- [ ] 环境诊断通过
  ```bash
  ./debug-test.sh
  ```
  
  预期输出：
  - ✓ gcloud 已安装
  - ✓ jq 已安装
  - ✓ gcloud 已认证
  - ✓ 可以创建临时目录
  - ✓ jq 解析正常

### 5. 运行快速测试

- [ ] 计数器测试通过
  ```bash
  ./quick-test.sh
  ```
  
  预期输出：
  - ✅ 所有测试通过！

### 6. 测试帮助信息

- [ ] 帮助信息正常显示
  ```bash
  ./verify-kms-enhanced.sh --help
  ```

### 7. 测试实际运行

- [ ] 基础验证成功
  ```bash
  ./verify-kms-enhanced.sh \
    --kms-project YOUR_KMS_PROJECT \
    --business-project YOUR_BIZ_PROJECT \
    --keyring YOUR_KEYRING \
    --key YOUR_KEY \
    --location global \
    --service-accounts "sa1@project.iam,sa2@project.iam"
  ```
  
  预期行为：
  - 不会在"检查前置条件"后立即退出
  - 能够完成所有检查步骤
  - 生成验证报告

### 8. 测试详细模式

- [ ] verbose 模式正常工作
  ```bash
  ./verify-kms-enhanced.sh \
    --kms-project YOUR_KMS_PROJECT \
    --business-project YOUR_BIZ_PROJECT \
    --keyring YOUR_KEYRING \
    --key YOUR_KEY \
    --location global \
    --service-accounts "sa1@project.iam" \
    --verbose
  ```

### 9. 测试 JSON 输出

- [ ] JSON 报告生成成功
  ```bash
  ./verify-kms-enhanced.sh \
    --kms-project YOUR_KMS_PROJECT \
    --business-project YOUR_BIZ_PROJECT \
    --keyring YOUR_KEYRING \
    --key YOUR_KEY \
    --location global \
    --service-accounts "sa1@project.iam" \
    --output-format json
  ```
  
  验证：
  ```bash
  cat kms-validation-report-*.json | jq .
  ```

## ✅ 问题排查

### 如果脚本在"检查前置条件"后退出

- [ ] 确认使用的是最新版本 (v2.0.1+)
  ```bash
  head -10 verify-kms-enhanced.sh | grep "版本"
  # 应该显示: 版本: 2.0.0 或更高
  ```

- [ ] 检查是否有 `((COUNTER++))` 语法
  ```bash
  grep -n "((.*++))" verify-kms-enhanced.sh
  # 应该没有任何匹配
  ```

- [ ] 运行算术测试
  ```bash
  ./test-arithmetic.sh
  ```

### 如果 gcloud 认证失败

- [ ] 重新认证
  ```bash
  gcloud auth login
  # 或
  gcloud auth activate-service-account --key-file=key.json
  ```

- [ ] 测试项目访问
  ```bash
  gcloud projects describe YOUR_PROJECT_ID
  ```

### 如果 IAM 策略获取失败

- [ ] 检查权限
  ```bash
  gcloud projects get-iam-policy YOUR_KMS_PROJECT \
    --flatten="bindings[].members" \
    --filter="bindings.members:$(gcloud config get-value account)"
  ```

- [ ] 手动测试 KMS 访问
  ```bash
  gcloud kms keys get-iam-policy YOUR_KEY \
    --project=YOUR_KMS_PROJECT \
    --keyring=YOUR_KEYRING \
    --location=global
  ```

## ✅ 生产部署

### 10. 集成到 CI/CD

- [ ] 添加到 GitLab CI / Jenkins / GitHub Actions
- [ ] 配置定期执行（建议每周）
- [ ] 设置失败告警
- [ ] 配置报告归档

### 11. 文档和培训

- [ ] 团队成员了解如何使用脚本
- [ ] 文档已更新到内部 Wiki
- [ ] 故障排查流程已建立

### 12. 监控和维护

- [ ] 设置执行日志收集
- [ ] 配置失败告警通知
- [ ] 定期审查验证报告
- [ ] 跟踪权限变更

## ✅ 最终确认

- [ ] 所有检查项都已完成
- [ ] 脚本在测试环境运行正常
- [ ] 团队已了解使用方法
- [ ] 故障排查文档已准备
- [ ] 可以开始在生产环境使用

---

## 快速命令参考

```bash
# 1. 完整的验证流程
./debug-test.sh                    # 环境诊断
./quick-test.sh                    # 功能测试
./verify-kms-enhanced.sh --help    # 查看帮助

# 2. 实际运行
./verify-kms-enhanced.sh \
  --kms-project PROJECT \
  --business-project PROJECT \
  --keyring KEYRING \
  --key KEY \
  --location global \
  --service-accounts "sa1,sa2" \
  --verbose

# 3. 查看报告
cat kms-validation-report-*.md
cat kms-validation-report-*.json | jq .

# 4. 故障排查
cat TROUBLESHOOTING.md
cat BUG-FIX-EXPLANATION.md
```

---

## 支持

遇到问题？
1. 查看 `TROUBLESHOOTING.md`
2. 查看 `BUG-FIX-EXPLANATION.md`
3. 运行 `./debug-test.sh`
4. 联系团队支持

---

**版本**: v2.0.1  
**最后更新**: 2025-11-10
