# 使用指南

## 概述

本文档详细介绍如何使用 GKE 跨项目 Namespace 迁移工具进行资源迁移。

## 前置条件

### 1. 工具依赖

**必需工具：**
```bash
# 检查 kubectl
kubectl version --client

# 检查 gcloud
gcloud version
```

**可选工具（用于更好的 YAML 处理）：**
```bash
# 选项 1: 安装 yq (推荐)
# macOS
brew install yq

# Linux
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# 选项 2: 确保有 Python3 (大多数系统默认安装)
python3 --version

# 选项 3: 如果都没有，工具会使用 grep/awk 备用方案
```

**说明：**
- 如果安装了 `yq`，工具会使用它进行精确的 YAML 处理
- 如果没有 `yq` 但有 `python3`，会使用 Python 的 yaml 库
- 如果都没有，会使用 `grep/awk` 备用方案（功能稍有限制但基本可用）

### 2. GCP 权限

确保你有以下权限：

**源项目权限：**
- `container.clusters.get`
- `container.clusters.list` 
- `container.*.get` (读取所有 Kubernetes 资源)

**目标项目权限：**
- `container.clusters.get`
- `container.clusters.list`
- `container.*.create` (创建 Kubernetes 资源)
- `container.*.update` (更新 Kubernetes 资源)

### 3. 集群访问

确保可以访问源集群和目标集群：

```bash
# 获取源集群凭据
gcloud container clusters get-credentials SOURCE_CLUSTER \
    --zone SOURCE_ZONE \
    --project SOURCE_PROJECT

# 获取目标集群凭据  
gcloud container clusters get-credentials TARGET_CLUSTER \
    --zone TARGET_ZONE \
    --project TARGET_PROJECT
```

## 配置设置

### 1. 编辑配置文件

编辑 `config/config.yaml` 文件：

```yaml
# 源项目配置
source:
  project: "your-source-project-id"
  cluster: "your-source-cluster"
  zone: "asia-east1-a"

# 目标项目配置
target:
  project: "your-target-project-id"
  cluster: "your-target-cluster"
  zone: "asia-east1-a"

# 迁移配置
migration:
  backup_enabled: true
  dry_run: false
  skip_existing: true
  timeout: 300
```

### 2. 自定义资源类型

如需自定义要迁移的资源类型，编辑 `config/resource-types.yaml`。

## 基本使用

### 1. 迁移单个 Namespace

```bash
# 迁移指定 namespace
./migrate.sh -n my-app

# 查看详细输出
./migrate.sh -n my-app -v
```

### 2. 迁移多个 Namespace

```bash
# 迁移多个 namespace
./migrate.sh -n app1,app2,app3
```

### 3. 干运行模式

在实际执行前，建议先使用干运行模式检查：

```bash
# 干运行模式
./migrate.sh -n my-app --dry-run
```

### 4. 选择性迁移

```bash
# 只迁移指定资源类型
./migrate.sh -n my-app --resources deployments,services,configmaps

# 排除特定资源类型
./migrate.sh -n my-app --exclude secrets,persistentvolumeclaims
```

## 高级用法

### 1. 强制覆盖

如果目标集群中已存在同名资源：

```bash
# 强制覆盖已存在的资源
./migrate.sh -n my-app --force
```

### 2. 自定义超时

```bash
# 设置超时时间为 10 分钟
./migrate.sh -n my-app --timeout 600
```

### 3. 跳过备份

```bash
# 跳过备份步骤
./migrate.sh -n my-app --no-backup
```

## 迁移流程详解

### 阶段 1: 导出资源

工具会连接到源集群并导出指定 namespace 的所有资源：

1. 验证 namespace 存在性
2. 检查是否为系统 namespace
3. 按资源类型导出 YAML 文件
4. 清理不需要的字段（如 uid、resourceVersion 等）
5. 生成导出清单和统计报告

导出的文件存储在 `exports/NAMESPACE_TIMESTAMP/` 目录中。

### 阶段 2: 处理资源

工具会对导出的资源进行预处理：

1. 移除集群特定的字段
2. 添加迁移标签
3. 处理敏感资源（如 Secrets）
4. 验证资源依赖关系

### 阶段 3: 导入资源

工具会连接到目标集群并按依赖顺序创建资源：

1. 创建 namespace
2. 按优先级顺序创建资源
3. 等待资源就绪
4. 验证创建结果

### 阶段 4: 验证结果

工具会验证迁移结果：

1. 检查资源数量是否匹配
2. 验证 Pod 状态
3. 检查服务端点
4. 生成验证报告

## 文件结构说明

迁移完成后，会生成以下文件结构：

```
exports/
└── my-app_20240830_143022/
    ├── namespace.yaml              # Namespace 定义
    ├── deployments.yaml           # Deployment 资源
    ├── services.yaml              # Service 资源
    ├── configmaps.yaml            # ConfigMap 资源
    ├── secrets.yaml               # Secret 资源
    ├── manifest.yaml              # 资源清单
    ├── export-stats.md            # 导出统计报告
    ├── import-report.md           # 导入报告
    └── validation-report.md       # 验证报告
```

## 监控和日志

### 1. 查看日志

所有操作都会记录到日志文件：

```bash
# 查看最新日志
tail -f logs/migration-*.log

# 查看特定时间的日志
ls logs/
cat logs/migration-20240830_143022.log
```

### 2. 查看报告

迁移完成后会生成多个报告：

```bash
# 查看导出统计
cat exports/my-app_latest/export-stats.md

# 查看导入报告
cat exports/my-app_latest/import-report.md

# 查看验证报告
cat exports/my-app_latest/validation-report.md
```

## 故障排除

### 1. 常见错误

**权限不足：**
```bash
Error: User "user@company.com" cannot get resource "deployments" in API group "apps"
```
解决方案：确保有足够的 RBAC 权限。

**集群连接失败：**
```bash
Error: Unable to connect to the server
```
解决方案：检查集群凭据和网络连接。

**资源已存在：**
```bash
Error: deployments.apps "my-app" already exists
```
解决方案：使用 `--force` 参数或手动删除冲突资源。

### 2. 调试技巧

```bash
# 启用详细输出
./migrate.sh -n my-app -v

# 使用干运行模式检查
./migrate.sh -n my-app --dry-run

# 检查导出的 YAML 文件
cat exports/my-app_latest/deployments.yaml

# 手动验证资源
kubectl get all -n my-app
```

### 3. 手动修复

如果自动迁移失败，可以手动处理：

```bash
# 手动应用单个资源文件
kubectl apply -f exports/my-app_latest/deployments.yaml -n my-app

# 手动删除有问题的资源
kubectl delete deployment problematic-app -n my-app

# 重新运行迁移
./migrate.sh -n my-app --force
```

## 最佳实践

### 1. 迁移前准备

- 在测试环境先验证迁移流程
- 备份重要数据
- 通知相关团队
- 选择低峰期执行

### 2. 迁移过程中

- 使用干运行模式预检查
- 监控日志输出
- 准备回滚计划
- 保持与团队沟通

### 3. 迁移后验证

- 检查所有 Pod 状态
- 验证服务可访问性
- 测试应用功能
- 更新监控和告警

### 4. 清理工作

- 清理旧的导出文件
- 更新文档
- 总结经验教训
- 优化迁移流程

## 性能优化

### 1. 大规模迁移

对于包含大量资源的 namespace：

```bash
# 分批迁移资源类型
./migrate.sh -n large-app --resources deployments,services
./migrate.sh -n large-app --resources configmaps,secrets
./migrate.sh -n large-app --resources persistentvolumeclaims

# 增加超时时间
./migrate.sh -n large-app --timeout 1800
```

### 2. 网络优化

- 确保源集群和目标集群网络连接良好
- 使用相同区域的集群减少延迟
- 考虑使用 VPC 对等连接

### 3. 资源优化

- 清理不需要的资源
- 压缩大型 ConfigMap
- 优化镜像大小

## 安全考虑

### 1. 敏感数据

- Secrets 会被迁移，确保目标集群安全
- 考虑重新生成敏感凭据
- 使用 Secret 管理工具

### 2. 网络安全

- 验证 NetworkPolicy 配置
- 检查服务暴露范围
- 更新防火墙规则

### 3. 访问控制

- 验证 RBAC 配置
- 更新 ServiceAccount 权限
- 检查 Pod 安全策略

## 扩展功能

### 1. 自定义钩子

可以在配置文件中定义自定义钩子：

```yaml
advanced:
  hooks:
    pre_migration: "/path/to/pre-script.sh"
    post_migration: "/path/to/post-script.sh"
```

### 2. 资源转换

可以定义资源转换规则：

```yaml
advanced:
  transformations:
    enabled: true
    rules_file: "transformations.yaml"
```

### 3. 通知集成

可以配置 Slack 或邮件通知：

```yaml
notifications:
  slack:
    enabled: true
    webhook_url: "https://hooks.slack.com/..."
    channel: "#migrations"
```

## 支持和反馈

如果遇到问题或有改进建议：

1. 查看 `docs/TROUBLESHOOTING.md`
2. 检查日志文件
3. 提交 Issue 或联系维护团队
4. 参与社区讨论