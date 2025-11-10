# GCP KMS 验证工具 - 文件索引

## 📋 快速导航

### 🚀 开始使用
1. **[README.md](README.md)** (6.2K) - 快速开始指南
2. **[VERIFICATION-CHECKLIST.md](VERIFICATION-CHECKLIST.md)** (4.9K) - 部署验证清单

### 🔧 主要脚本
1. **[verify-kms-enhanced.sh](verify-kms-enhanced.sh)** (24K) - 主验证脚本 ⭐
2. **[debug-test.sh](debug-test.sh)** (3.2K) - 环境诊断工具
3. **[quick-test.sh](quick-test.sh)** (2.4K) - 快速功能测试
4. **[test-arithmetic.sh](test-arithmetic.sh)** (1.4K) - 算术运算测试

### 📚 文档
1. **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** (5.3K) - 故障排查指南 ⭐
2. **[BUG-FIX-EXPLANATION.md](BUG-FIX-EXPLANATION.md)** (3.2K) - Bug 修复说明 ⭐
3. **[IMPROVEMENTS.md](IMPROVEMENTS.md)** (7.1K) - 改进说明
4. **[CHANGELOG.md](CHANGELOG.md)** (3.9K) - 更新日志
5. **[example-usage.md](example-usage.md)** (3.0K) - 使用示例

---

## 📖 使用流程

### 第一次使用

```
1. 阅读 README.md
   ↓
2. 按照 VERIFICATION-CHECKLIST.md 检查环境
   ↓
3. 运行 debug-test.sh 诊断环境
   ↓
4. 运行 quick-test.sh 验证功能
   ↓
5. 运行 verify-kms-enhanced.sh 进行实际验证
```

### 遇到问题

```
1. 查看 TROUBLESHOOTING.md
   ↓
2. 如果是"检查前置条件后退出"，查看 BUG-FIX-EXPLANATION.md
   ↓
3. 运行 debug-test.sh 诊断
   ↓
4. 使用 --verbose 模式重新运行
```

---

## 🎯 文件用途说明

### 核心文件

| 文件 | 用途 | 何时使用 |
|------|------|---------|
| **verify-kms-enhanced.sh** | 主验证脚本 | 执行 KMS 权限验证 |
| **README.md** | 快速开始 | 第一次使用时阅读 |
| **TROUBLESHOOTING.md** | 故障排查 | 遇到问题时查阅 |

### 诊断工具

| 文件 | 用途 | 何时使用 |
|------|------|---------|
| **debug-test.sh** | 环境诊断 | 部署前或遇到问题时 |
| **quick-test.sh** | 功能测试 | 验证脚本修复是否生效 |
| **test-arithmetic.sh** | 算术测试 | 理解 Bu