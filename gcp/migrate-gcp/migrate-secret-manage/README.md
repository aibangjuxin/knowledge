# GCP Secret Manager 跨项目迁移工具

这是一个用于 Google Cloud Platform (GCP) Secret Manager 跨项目迁移的自动化工具集，支持零停机的密钥迁移和完整的验证机制。

## 🎯 功能特性

- 🔍 **自动密钥发现**: 自动发现源项目中的所有密钥和版本
- 📦 **完整数据导出**: 导出密钥值、版本历史、元数据和 IAM 策略
- 🚀 **批量导入**: 高效的批量导入机制，支持大规模密钥迁移
- ✅ **全面验证**: 验证密钥数量、版本、值和 IAM 策略的一致性
- 🔧 **应用配置更新**: 自动更新 Kubernetes 和配置文件中的项目引用
- 📊 **详细报告**: 生成完整的迁移分析和验证报告
- 🔄 **状态跟踪**: 实时跟踪迁移进度和状态
- 🛡️ **安全保障**: 完整的备份和回滚机制

## 📁 目录结构

```
migrate-secret-manage/
├── config.sh                 # 配置文件
├── migrate-secrets.sh        # 主控制脚本
├── 01-setup.sh              # 环境准备脚本
├── 02-discover.sh           # 密钥发现脚本
├── 03-export.sh             # 密钥导出脚本
├── 04-import.sh             # 密钥导入脚本
├── 05-verify.sh             # 迁移验证脚本
├── 06-update-apps.sh        # 应用配置更新脚本
├── README.md                # 本文档
├── backup/                  # 备份目录（自动创建）
└── logs/                    # 日志目录（自动创建）
```

## 🚀 快速开始

### 1. 环境准备

确保已安装以下工具：
```bash
# 安装 gcloud CLI
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# 安装 kubectl
gcloud components install kubectl

# 安装 jq
# macOS
brew install jq
# Ubuntu/Debian
sudo apt-get install jq

# 认证
gcloud auth login
gcloud auth application-default login
```

### 2. 配置参数

编辑 `config.sh` 文件，设置你的项目参数：

```bash
# 基础项目配置
export SOURCE_PROJECT="your-source-project-id"
export TARGET_PROJECT="your-target-project-id"

# 迁移配置
export BATCH_SIZE=10
export VERIFY_SECRET_VALUES=true

# Kubernetes 命名空间
export K8S_NAMESPACES=("default" "production" "staging")
```

### 3. 执行迁移

#### 方式一：完整自动迁移
```bash
# 给脚本执行权限
chmod +x *.sh

# 执行完整迁移流程
./migrate-secrets.sh all
```

#### 方式二：分步骤执行
```bash
# 1. 环境准备
./migrate-secrets.sh setup

# 2. 密钥发现
./migrate-secrets.sh discover

# 3. 密钥导出
./migrate-secrets.sh export

# 4. 密钥导入
./migrate-secrets.sh import

# 5. 迁移验证
./migrate-secrets.sh verify

# 6. 应用配置更新
./migrate-secrets.sh update
```

### 4. 检查状态

```bash
# 查看迁移状态
./migrate-secrets.sh status

# 查看详细日志
tail -f backup/*/migration.log
```

## 📖 详细使用说明

### 主控制脚本

```bash
./migrate-secrets.sh [选项] [阶段]

阶段:
  setup       环境准备和权限检查
  discover    发现和分析源项目中的密钥
  export      导出源项目中的所有密钥
  import      导入密钥到目标项目
  verify      验证迁移结果
  update      更新应用程序配置
  all         执行完整迁移流程
  status      显示当前迁移状态

选项:
  -h, --help              显示帮助信息
  -s, --source PROJECT    源项目ID
  -t, --target PROJECT    目标项目ID
  -d, --dry-run          干运行模式
  -v, --verbose          详细输出模式
  -f, --force            强制执行，跳过确认提示
  --batch-size SIZE      批量处理大小
  --no-verify-values     跳过密钥值验证
```

### 配置说明

#### 基础配置
- `SOURCE_PROJECT`: 源项目ID（当前存储密钥的项目）
- `TARGET_PROJECT`: 目标项目ID（要迁移到的项目）
- `BATCH_SIZE`: 批量处理大小，建议 5-20
- `VERIFY_SECRET_VALUES`: 是否验证密钥值（可能增加迁移时间）

#### Kubernetes 配置
- `K8S_NAMESPACES`: 需要更新的 Kubernetes 命名空间列表
- `CONFIG_FILE_PATTERNS`: 需要扫描的配置文件模式

### 迁移流程详解

#### 阶段 1: 环境准备 (Setup)
- 检查必要工具和权限
- 验证项目访问权限
- 启用 Secret Manager API
- 创建迁移环境

#### 阶段 2: 密钥发现 (Discover)
- 扫描源项目中的所有密钥
- 分析密钥版本、标签、IAM 策略
- 检查目标项目冲突
- 生成迁移分析报告

#### 阶段 3: 密钥导出 (Export)
- 导出所有密钥版本的数据
- 导出密钥元数据和 IAM 策略
- 创建导出清单和验证
- 生成导出报告

#### 阶段 4: 密钥导入 (Import)
- 在目标项目创建密钥
- 导入所有版本数据
- 设置 IAM 策略
- 生成导入报告

#### 阶段 5: 迁移验证 (Verify)
- 比较源项目和目标项目密钥
- 验证版本数量和密钥值
- 检查 IAM 策略一致性
- 生成验证报告

#### 阶段 6: 应用配置更新 (Update)
- 更新 Kubernetes 部署配置
- 扫描和更新配置文件
- 生成环境变量更新指南
- 创建应用切换检查清单

## 🔧 高级用法

### 自定义配置

```bash
# 使用自定义项目ID
./migrate-secrets.sh -s source-proj -t target-proj all

# 干运行模式
./migrate-secrets.sh --dry-run import

# 强制模式（跳过确认）
./migrate-secrets.sh --force verify

# 调整批量大小
./migrate-secrets.sh --batch-size 5 export

# 跳过密钥值验证
./migrate-secrets.sh --no-verify-values verify
```

### 部分迁移

```bash
# 只迁移特定密钥（需要修改发现脚本）
# 在 02-discover.sh 中添加过滤条件

# 只更新特定命名空间
export K8S_NAMESPACES=("production")
./migrate-secrets.sh update
```

### 监控和调试

```bash
# 实时查看日志
tail -f backup/*/migration.log

# 查看详细状态
./migrate-secrets.sh -v status

# 检查特定密钥
gcloud secrets versions access latest --secret="my-secret" --project=$TARGET_PROJECT
```

## 🛡️ 安全考虑

### 权限要求

**源项目权限：**
- `roles/secretmanager.admin` - 管理密钥
- `roles/iam.securityReviewer` - 查看 IAM 策略

**目标项目权限：**
- `roles/secretmanager.admin` - 创建和管理密钥
- `roles/resourcemanager.projectIamAdmin` - 管理 IAM 权限

### 安全最佳实践

1. **最小权限原则**: 只授予必要的权限
2. **临时权限**: 迁移完成后及时回收权限
3. **审计日志**: 启用 Cloud Audit Logs 记录操作
4. **网络安全**: 在安全的网络环境中执行迁移
5. **数据保护**: 妥善保管备份文件

## 📊 监控和报告

### 生成的报告

- **迁移分析报告**: 密钥统计和复杂度评估
- **导出报告**: 导出结果和性能统计
- **导入报告**: 导入结果和版本统计
- **验证报告**: 完整性验证和一致性检查
- **应用更新报告**: 配置更新和备份信息

### 关键指标

- 密钥数量和版本统计
- 迁移成功率和失败率
- 处理时间和性能指标
- IAM 策略迁移状态
- 应用配置更新状态

## 🔄 故障排除

### 常见问题

#### 1. 权限不足
```bash
# 检查当前权限
gcloud projects get-iam-policy $PROJECT_ID

# 添加必要权限
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:your-email@domain.com" \
  --role="roles/secretmanager.admin"
```

#### 2. API 未启用
```bash
# 启用 Secret Manager API
gcloud services enable secretmanager.googleapis.com --project=$PROJECT_ID
```

#### 3. 密钥访问失败
```bash
# 检查密钥是否存在
gcloud secrets describe SECRET_NAME --project=$PROJECT_ID

# 检查版本状态
gcloud secrets versions list SECRET_NAME --project=$PROJECT_ID
```

#### 4. 批量处理超时
```bash
# 减少批量大小
./migrate-secrets.sh --batch-size 5 export

# 增加重试次数
export RETRY_COUNT=5
```

### 回滚操作

```bash
# Kubernetes 回滚
kubectl apply -f backup/*/k8s_backups/

# 配置文件回滚
cp backup/*/config_backups/* /original/location/

# 删除目标项目密钥（如需要）
gcloud secrets delete SECRET_NAME --project=$TARGET_PROJECT
```

## 📈 性能优化

### 迁移时间估算

- **小规模** (< 50 个密钥): 10-30 分钟
- **中等规模** (50-200 个密钥): 30-90 分钟  
- **大规模** (> 200 个密钥): 1-4 小时

### 优化建议

1. **调整批量大小**: 根据网络和 API 限制调整
2. **并行处理**: 在不同区域同时执行
3. **跳过值验证**: 对于大量密钥可跳过值验证
4. **网络优化**: 在同区域执行以减少延迟

## 🤝 贡献指南

### 开发环境设置

```bash
# 克隆仓库
git clone <repository-url>
cd migrate-secret-manage

# 设置开发配置
cp config.sh config-dev.sh
# 编辑 config-dev.sh 设置测试项目

# 运行测试
./migrate-secrets.sh --dry-run all
```

### 代码规范

- 使用 `set -euo pipefail` 确保脚本安全性
- 所有函数都要有错误处理
- 重要操作前要有用户确认
- 详细的日志记录和错误信息

## 📄 许可证

MIT License

## 🆘 支持

如有问题，请：
1. 查看日志文件获取详细错误信息
2. 检查配置和权限设置
3. 参考故障排除部分
4. 提交 Issue 或联系维护团队

---

**注意**: 这是一个强大的迁移工具，请在生产环境使用前充分测试，并确保有完整的备份和回滚计划。