# 更新日志

## [1.1.0] - 2024-11-14

### 🐛 Bug 修复

#### 修复 `set -e` 环境下计数器导致脚本退出的问题

**问题描述：**
- 脚本在遇到第一个 Group 时自动退出
- 退出位置：`((GROUP_COUNT++))`
- 根本原因：`set -e` 与 `((var++))` 的组合问题

**影响范围：**
- `list-all-secrets-permissions.sh`
- `list-secrets-groups-sa.sh`

**修复内容：**

1. **list-all-secrets-permissions.sh**
   ```bash
   # 修复前
   ((GROUP_COUNT++))
   ((SA_COUNT++))
   ((USER_COUNT++))
   ((OTHER_COUNT++))
   
   # 修复后
   GROUP_COUNT=$((GROUP_COUNT + 1))
   SA_COUNT=$((SA_COUNT + 1))
   USER_COUNT=$((USER_COUNT + 1))
   OTHER_COUNT=$((OTHER_COUNT + 1))
   ```

2. **list-secrets-groups-sa.sh**
   ```bash
   # 修复前
   ((TOTAL_GROUPS++))
   ((TOTAL_SAS++))
   ((SECRETS_WITH_GROUPS++))
   ((SECRETS_WITH_SAS++))
   
   # 修复后
   TOTAL_GROUPS=$((TOTAL_GROUPS + 1))
   TOTAL_SAS=$((TOTAL_SAS + 1))
   SECRETS_WITH_GROUPS=$((SECRETS_WITH_GROUPS + 1))
   SECRETS_WITH_SAS=$((SECRETS_WITH_SAS + 1))
   ```

**技术细节：**

当变量值为 0 时，`((var++))` 返回 0（false），在 `set -e` 环境下会导致脚本退出。

```bash
# 问题演示
set -e
COUNT=0
((COUNT++))  # 返回 0，脚本退出
echo "这行不会执行"

# 修复后
set -e
COUNT=0
COUNT=$((COUNT + 1))  # 总是成功
echo "这行会执行"
```

**验证方法：**
```bash
# 运行测试脚本
bash test-increment-fix.sh

# 或手动测试
bash -c 'set -e; COUNT=0; ((COUNT++)); echo "Success"' || echo "Failed"
bash -c 'set -e; COUNT=0; COUNT=$((COUNT + 1)); echo "Success"' || echo "Failed"
```

**相关文档：**
- [BUGFIX-NOTES.md](./BUGFIX-NOTES.md) - 详细的问题分析和解决方案
- [test-increment-fix.sh](./test-increment-fix.sh) - 测试脚本

---

## [1.0.0] - 2024-11-14

### ✨ 新功能

#### 初始版本发布

**新增脚本：**

1. **list-all-secrets-permissions.sh**
   - 完整的 Secret Manager 权限审计
   - 支持所有成员类型（Groups、ServiceAccounts、Users、Domains）
   - 生成多种格式报告（TXT、CSV、JSON、Markdown、HTML）
   - 彩色终端输出
   - 详细的统计信息

2. **list-secrets-groups-sa.sh**
   - 快速查询 Groups 和 ServiceAccounts
   - 简洁的输出格式
   - CSV 数据导出
   - 唯一成员列表

3. **verify-gcp-secretmanage.sh**
   - 验证单个 Deployment 的权限链路
   - 检查 KSA → GSA 绑定
   - 验证 Workload Identity
   - 检查 Secret Manager 权限

**文档：**
- README-audit-scripts.md - 完整使用文档
- QUICK-REFERENCE.md - 快速参考
- 使用示例和最佳实践

**输出格式：**
- 文本报告（TXT）
- CSV 数据文件
- JSON 数据文件
- Markdown 报告
- HTML 可视化报告

**主要特性：**
- 🎨 彩色终端输出
- 📊 详细的统计信息
- 📋 多种输出格式
- 🔍 完整的权限审计
- 📈 可视化 HTML 报告
- 🚀 快速查询模式

---

## 计划中的功能

### [1.2.0] - 待定

- [ ] 添加过滤功能（按 Secret 名称、角色等）
- [ ] 支持导出到 Google Sheets
- [ ] 添加权限变更检测
- [ ] 支持多项目批量审计
- [ ] 添加告警功能（异常权限检测）

### [1.3.0] - 待定

- [ ] 集成到 CI/CD Pipeline
- [ ] 添加 Web UI
- [ ] 支持权限推荐
- [ ] 添加合规性检查
- [ ] 生成审计报告模板

---

## 升级指南

### 从 1.0.0 升级到 1.1.0

**无需任何操作**，修复是向后兼容的。

如果你之前遇到脚本提前退出的问题，现在应该已经解决。

**验证升级：**
```bash
# 运行脚本应该不再提前退出
bash list-all-secrets-permissions.sh
bash list-secrets-groups-sa.sh
```

---

## 已知问题

### 1.1.0

- 无已知问题

### 1.0.0

- ✅ **已修复** - 脚本在遇到第一个 Group 时退出（修复于 1.1.0）

---

## 贡献者

- 初始开发和 Bug 修复

---

## 许可证

内部使用

---

## 支持

如有问题或建议，请：
1. 查看 [README-audit-scripts.md](../README-audit-scripts.md)
2. 查看 [QUICK-REFERENCE.md](../QUICK-REFERENCE.md)
3. 查看 [BUGFIX-NOTES.md](./BUGFIX-NOTES.md)
