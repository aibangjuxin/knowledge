# GCP Secret Manager 审计脚本集合

## 📚 概述

本目录包含三个版本的 GCP Secret Manager 权限审计脚本，以及完整的文档和工具。

## 🚀 快速开始

### 选择合适的版本

```bash
# 小规模项目 (< 50 个 Secret)
bash list-all-secrets-permissions.sh my-project

# 中等规模项目 (50-300 个 Secret)
bash list-all-secrets-permissions-parallel.sh my-project 20

# 大规模项目 (> 300 个 Secret) - 推荐
bash list-all-secrets-optimized.sh my-project
```

## 📦 脚本版本

### 1. 串行版本 (原版)
**文件:** `list-all-secrets-permissions.sh`

- ✅ 简单可靠
- ✅ 实时输出
- ✅ 无额外依赖
- ⏱️ 速度: 基准 (1x)

**适用:** Secret < 50

### 2. 并行版本
**文件:** `list-all-secrets-permissions-parallel.sh`

- ✅ 速度快 (10x)
- ✅ 可配置并行数
- ✅ 进度条显示
- ⏱️ 速度: 10x

**适用:** Secret 50-500

### 3. 最优化版本 (推荐)
**文件:** `list-all-secrets-optimized.sh`

- ✅ 最快速度 (15-20x)
- ✅ 批量 API 调用
- ✅ 智能数据合并
- ⏱️ 速度: 15-20x

**适用:** 任意数量

## 📊 性能对比

| Secret 数量 | 串行版 | 并行版 | 最优版 |
|------------|--------|--------|--------|
| 50 | 5 分钟 | 30 秒 | 20 秒 |
| 100 | 10 分钟 | 1 分钟 | 40 秒 |
| 350 | 35 分钟 | 3.5 分钟 | 2.5 分钟 |
| 500 | 50 分钟 | 5 分钟 | 3.5 分钟 |

## 📖 文档

### 使用指南
- [README-audit-scripts.md](../README-audit-scripts.md) - 完整使用文档
- [README-PARALLEL.md](./README-PARALLEL.md) - 并行版本指南
- [QUICK-REFERENCE.md](../QUICK-REFERENCE.md) - 快速参考

### 性能优化
- [PERFORMANCE-OPTIMIZATION.md](./PERFORMANCE-OPTIMIZATION.md) - 性能优化指南
- [VERSION-COMPARISON.md](./VERSION-COMPARISON.md) - 版本对比
- [benchmark-comparison.sh](./benchmark-comparison.sh) - 性能测试脚本

### 问题修复
- [BUGFIX-NOTES.md](./BUGFIX-NOTES.md) - Bug 修复说明
- [CHANGELOG.md](./CHANGELOG.md) - 更新日志
- [test-increment-fix.sh](./test-increment-fix.sh) - 测试脚本

## 🛠️ 辅助工具

### 单个应用验证
```bash
bash verify-gcp-secretmanage.sh <deployment> <namespace>
```

### 快速查询 Groups 和 SA
```bash
bash list-secrets-groups-sa.sh my-project
```

### 性能基准测试
```bash
bash benchmark-comparison.sh my-project 10
```

## 💡 使用示例

### 示例 1: 首次审计

```bash
# 使用串行版了解情况
bash list-all-secrets-permissions.sh my-project

# 查看结果
cat secret-audit-*/summary.txt
```

### 示例 2: 定期审计

```bash
# 使用最优版快速完成
bash list-all-secrets-optimized.sh my-project

# 在浏览器中查看报告
open secret-audit-optimized-*/report.html
```

### 示例 3: 查询特定 Group

```bash
# 生成审计报告
bash list-secrets-groups-sa.sh my-project

# 查询特定 Group
grep "dev-team@company.com" secrets-groups-sa-*.csv
```

### 示例 4: 自动化审计

```bash
# 添加到 crontab
# 每周一早上 9 点运行
0 9 * * 1 /path/to/list-all-secrets-optimized.sh my-project
```

## 📋 输出文件

所有版本生成相同格式的文件：

```
secret-audit-*/
├── summary.txt                    # 📄 汇总报告
├── secrets-permissions.csv        # 📊 CSV 数据
├── secrets-permissions.json       # 📦 JSON 数据
├── report.md                      # 📝 Markdown 报告
└── report.html                    # 🌐 HTML 可视化报告
```

## 🔧 依赖要求

### 必需
- `gcloud` CLI
- `bash` 4.0+

### 可选
- `jq` (并行版和最优版需要)
- `GNU parallel` (提供进度条)

### 安装依赖

```bash
# macOS
brew install jq parallel

# Ubuntu/Debian
sudo apt-get install jq parallel

# CentOS/RHEL
sudo yum install jq parallel
```

## 🎯 选择指南

### 决策表

| 场景 | 推荐版本 | 命令 |
|------|---------|------|
| 学习代码 | 串行版 | `bash list-all-secrets-permissions.sh` |
| Secret < 50 | 串行版 | `bash list-all-secrets-permissions.sh` |
| Secret 50-300 | 并行版 | `bash list-all-secrets-permissions-parallel.sh my-project 20` |
| Secret > 300 | 最优版 | `bash list-all-secrets-optimized.sh` |
| 生产环境 | 最优版 | `bash list-all-secrets-optimized.sh` |
| 网络不稳定 | 串行版 | `bash list-all-secrets-permissions.sh` |

### 快速决策

```
Secret 数量 < 50   → 串行版
Secret 数量 50-300 → 并行版
Secret 数量 > 300  → 最优版（推荐）
```

## ⚡ 性能优化技巧

### 1. 选择合适的版本
```bash
# 根据 Secret 数量选择
SECRET_COUNT=$(gcloud secrets list --project=my-project --format="value(name)" | wc -l)

if [ "$SECRET_COUNT" -lt 50 ]; then
    bash list-all-secrets-permissions.sh my-project
elif [ "$SECRET_COUNT" -lt 300 ]; then
    bash list-all-secrets-permissions-parallel.sh my-project 20
else
    bash list-all-secrets-optimized.sh my-project
fi
```

### 2. 调整并行任务数
```bash
# 并行版可以调整任务数
bash list-all-secrets-permissions-parallel.sh my-project 30
```

### 3. 启用 HTTP/2
```bash
export CLOUDSDK_CORE_USE_HTTP2=true
bash list-all-secrets-optimized.sh my-project
```

## 🐛 故障排查

### 问题 1: jq 未安装

```bash
# 错误: jq: command not found
# 解决:
brew install jq  # macOS
sudo apt-get install jq  # Ubuntu
```

### 问题 2: API 限流

```bash
# 错误: RESOURCE_EXHAUSTED: Quota exceeded
# 解决: 减少并行任务数
bash list-all-secrets-permissions-parallel.sh my-project 10
```

### 问题 3: 脚本提前退出

```bash
# 已修复: 参见 BUGFIX-NOTES.md
# 确保使用最新版本
```

## 📈 数据分析

### 使用 CSV 文件

```bash
# 在 Excel 中打开
open secrets-permissions.csv

# 查询特定 Group
grep "dev-team@company.com" secrets-permissions.csv

# 统计每个 Secret 的权限数量
cut -d',' -f1 secrets-permissions.csv | sort | uniq -c | sort -rn
```

### 使用 JSON 文件

```bash
# 查找有 Groups 的 Secret
jq '.[] | select(.summary.groups > 0)' secrets-permissions.json

# 列出所有 Groups
jq -r '.[] | .bindings[]?.members[]? | select(.type == "Group") | .id' secrets-permissions.json | sort -u

# 统计总数
jq '[.[] | .summary.groups] | add' secrets-permissions.json
```

## 🔐 安全最佳实践

1. **定期审计** - 每周或每月运行一次
2. **权限最小化** - 移除不必要的权限
3. **文档化** - 记录每个 Secret 的用途
4. **版本控制** - 保存历史审计报告
5. **自动化** - 集成到 CI/CD Pipeline

## 📞 支持

### 相关文档
- [完整使用文档](../README-audit-scripts.md)
- [快速参考](../QUICK-REFERENCE.md)
- [性能优化](./PERFORMANCE-OPTIMIZATION.md)
- [版本对比](./VERSION-COMPARISON.md)

### 常见问题
- [BUGFIX-NOTES.md](./BUGFIX-NOTES.md)
- [CHANGELOG.md](./CHANGELOG.md)

## 📝 更新日志

### v1.1.0 (2024-11-14)
- ✨ 新增最优化版本
- ✨ 新增性能基准测试
- 🐛 修复计数器 Bug
- 📚 完善文档

### v1.0.0 (2024-11-14)
- ✨ 初始版本发布
- ✨ 串行版本
- ✨ 并行版本
- 📚 完整文档

## 🤝 贡献

欢迎提出改进建议！

## 📄 许可证

内部使用

---

**最后更新:** 2024-11-14  
**维护者:** Platform Team
