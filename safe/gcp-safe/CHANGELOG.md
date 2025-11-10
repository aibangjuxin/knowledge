# 更新日志

## v2.0.1 (2025-11-10) - 关键 Bug 修复

### 🐛 Bug 修复

**关键修复：修复 `((COUNTER++))` 导致脚本在 `set -e` 模式下退出的问题**

#### 问题描述
- 脚本在"检查前置条件"后立即退出
- 即使所有命令都成功执行，脚本仍然异常退出
- 根本原因：`((COUNTER++))` 后置递增返回 0，在算术上下文中为假，退出码为 1

#### 修复内容
将所有的 `((COUNTER++))` 改为 `COUNTER=$((COUNTER + 1))`：
- `TOTAL_CHECKS=$((TOTAL_CHECKS + 1))`
- `PASSED_CHECKS=$((PASSED_CHECKS + 1))`
- `WARNING_CHECKS=$((WARNING_CHECKS + 1))`
- `FAILED_CHECKS=$((FAILED_CHECKS + 1))`

#### 影响范围
- `check_prerequisites()`
- `check_kms_project()`
- `check_business_project()`
- `check_keyring()`
- `check_crypto_key()`
- `check_service_account_permissions()`
- `check_rotation_policy()`
- `test_encryption()`
- `test_decryption()`
- `log_success()`
- `log_warning()`
- `log_error()`

#### 验证
运行 `./quick-test.sh` 验证修复是否生效。

### 📚 新增文档
- `BUG-FIX-EXPLANATION.md` - 详细解释问题原因和解决方案
- `test-arithmetic.sh` - 演示 Bash 算术运算在 `set -e` 下的行为
- `quick-test.sh` - 快速验证修复是否生效
- `CHANGELOG.md` - 本文件

---

## v2.0.0 (2025-11-10) - 增强版发布

### ✨ 新功能

1. **更健壮的 IAM 解析**
   - 使用 jq 精确解析 JSON
   - 替代了容易出错的 grep/read 组合

2. **完善的错误处理**
   - 添加错误追踪 (trap ERR)
   - 显示出错的行号和命令
   - 支持 verbose 模式

3. **真正的 JSON 输出**
   - 实现了机器可读的 JSON 报告
   - 包含结构化的检查结果

4. **检查结果追踪**
   - 记录每个检查的详细结果
   - 包含时间戳便于审计

5. **未授权服务账号检测**
   - 自动发现不在检查列表中的服务账号
   - 提高安全审计能力

6. **更详细的资源信息**
   - 显示密钥用途、状态
   - 显示项目生命周期状态

7. **新增参数**
   - `--verbose` - 详细输出模式
   - `--skip-rotation-check` - 跳过轮换策略检查
   - `--output-format json` - JSON 输出支持

### 🔧 改进

1. **临时文件管理**
   - 统一的临时目录
   - 自动清理机制 (trap EXIT)

2. **命令检查**
   - 提供安装提示
   - 更友好的错误信息

3. **认证检查**
   - 更可靠的 gcloud 认证验证
   - 支持多种认证方式

4. **测试验证**
   - 验证文件存在且非空
   - 显示密文大小

### 📚 文档

- `README.md` - 快速开始指南
- `IMPROVEMENTS.md` - 详细改进说明
- `TROUBLESHOOTING.md` - 故障排查指南
- `example-usage.sh` - 使用示例
- `debug-test.sh` - 环境诊断工具

### 🔄 向后兼容

完全向后兼容 v1.0.0 的所有参数和功能。

---

## v1.0.0 (2025-11-09) - 初始版本

### ✨ 功能

- 资源存在性验证
- IAM 权限分析
- 服务账号权限检查
- 密钥轮换策略验证
- 可选的加密/解密测试
- Markdown 报告生成

---

## 升级指南

### 从 v1.0.0 升级到 v2.0.1

1. **安装 jq**（如果尚未安装）
   ```bash
   # Ubuntu/Debian
   sudo apt-get install jq
   
   # CentOS/RHEL
   sudo yum install jq
   ```

2. **替换脚本文件**
   ```bash
   cp verify-kms-enhanced.sh /path/to/your/scripts/
   chmod +x /path/to/your/scripts/verify-kms-enhanced.sh
   ```

3. **验证修复**
   ```bash
   ./quick-test.sh
   ```

4. **测试运行**
   ```bash
   ./verify-kms-enhanced.sh --help
   ```

5. **使用相同参数运行**
   - 所有 v1.0.0 的参数在 v2.0.1 中都能正常工作
   - 可选：添加 `--verbose` 查看详细输出

### 破坏性变更

无。完全向后兼容。

---

## 已知问题

无。

---

## 计划功能

- [ ] 多密钥批量验证
- [ ] 历史对比功能
- [ ] 自动修复选项
- [ ] 审计日志分析
- [ ] 性能测试
- [ ] 支持更多输出格式 (HTML, CSV)

---

## 贡献

欢迎提交 Issue 和 Pull Request。

---

## 许可证

内部使用
