# GKE 跨项目 Namespace 迁移工具

## 概述

这个工具用于在 GCP 项目之间迁移 GKE 集群的 namespace 资源。支持导出源项目的资源，然后在目标项目中重新创建。

## 功能特性

- 🚀 **简单易用**: 一条命令完成 namespace 迁移
- 📦 **完整导出**: 导出 namespace 中的所有 Kubernetes 资源
- 🔄 **智能处理**: 自动处理资源依赖关系和创建顺序
- 🛡️ **安全可靠**: 支持备份和回滚操作
- 📊 **详细报告**: 生成迁移前后的资源统计报告
- 🎯 **选择性迁移**: 支持指定资源类型进行迁移

## 目录结构

```
pop-migrate/
├── README.md                 # 本文档
├── migrate.sh               # 主迁移脚本
├── config/
│   ├── config.yaml         # 配置文件
│   └── resource-types.yaml # 资源类型定义
├── scripts/
│   ├── export.sh           # 导出脚本
│   ├── import.sh           # 导入脚本
│   ├── validate.sh         # 验证脚本
│   └── cleanup.sh          # 清理脚本
├── templates/
│   └── namespace-template.yaml # Namespace 模板
├── exports/                # 导出的资源文件存储目录
├── backups/               # 备份文件存储目录
├── logs/                  # 日志文件存储目录
└── docs/                  # 详细文档
    ├── USAGE.md           # 使用指南
    ├── TROUBLESHOOTING.md # 故障排除
    └── EXAMPLES.md        # 使用示例
```

## 快速开始

### 1. 环境准备

```bash
# 确保已安装必要工具
kubectl version --client
gcloud version

# 设置执行权限
chmod +x migrate.sh scripts/*.sh

# 可选：安装 yq 以获得更好的 YAML 处理能力
# (如果没有 yq，工具会自动使用 Python 或 grep/awk 备用方案)
brew install yq  # macOS
# 或者确保 Python3 可用
python3 --version
```

### 2. 配置文件

编辑 `config/config.yaml`:

```yaml
source:
  project: "source-project-id"
  cluster: "source-cluster-name"
  zone: "asia-east1-a"
  
target:
  project: "target-project-id"
  cluster: "target-cluster-name"
  zone: "asia-east1-a"

migration:
  backup_enabled: true
  dry_run: false
  skip_existing: true
  timeout: 300
```

### 3. 执行迁移

```bash
# 迁移指定 namespace
./migrate.sh -n namespace-name

# 迁移多个 namespace
./migrate.sh -n namespace1,namespace2,namespace3

# 干运行模式（仅检查，不实际执行）
./migrate.sh -n namespace-name --dry-run

# 指定资源类型迁移
./migrate.sh -n namespace-name --resources deployments,services,configmaps

# 查看帮助
./migrate.sh --help
```

## 主要命令选项

| 选项 | 描述 | 示例 |
|------|------|------|
| `-n, --namespace` | 指定要迁移的 namespace | `-n my-app` |
| `--dry-run` | 干运行模式，不实际执行 | `--dry-run` |
| `--resources` | 指定要迁移的资源类型 | `--resources deployments,services` |
| `--exclude` | 排除特定资源类型 | `--exclude secrets,configmaps` |
| `--backup` | 强制创建备份 | `--backup` |
| `--no-backup` | 跳过备份 | `--no-backup` |
| `--force` | 强制覆盖已存在的资源 | `--force` |
| `--timeout` | 设置超时时间（秒） | `--timeout 600` |

## 迁移流程

1. **连接源集群** - 获取源项目的集群凭据
2. **导出资源** - 导出指定 namespace 的所有资源
3. **资源处理** - 清理和转换资源定义
4. **连接目标集群** - 获取目标项目的集群凭据
5. **创建 Namespace** - 在目标集群创建 namespace
6. **导入资源** - 按依赖顺序创建资源
7. **验证结果** - 检查迁移结果和资源状态
8. **生成报告** - 创建迁移报告

## 注意事项

### 不会迁移的资源
- `kube-system` 等系统 namespace
- Node、PersistentVolume 等集群级资源
- 包含敏感信息的 Secret（需手动处理）

### 需要手动处理的情况
- 跨项目的 IAM 权限
- 外部负载均衡器配置
- 持久卷数据迁移
- 自定义 RBAC 策略

### 最佳实践
- 迁移前先在测试环境验证
- 确保目标集群有足够资源
- 备份重要数据
- 在低峰期执行迁移

## 故障排除

如果遇到问题，请查看：
1. `logs/` 目录下的日志文件
2. `docs/TROUBLESHOOTING.md` 故障排除指南
3. 使用 `--dry-run` 模式预检查

## 支持的资源类型

- Deployments
- Services
- ConfigMaps
- Secrets
- Ingresses
- PersistentVolumeClaims
- ServiceAccounts
- Roles & RoleBindings
- NetworkPolicies
- HorizontalPodAutoscalers
- 更多...

详细列表请查看 `config/resource-types.yaml`