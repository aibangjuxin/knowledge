# GCP 日志成本优化工具包

本工具包提供了一套完整的 GCP 日志成本优化解决方案，帮助您在保持测试环境和生产环境日志内容一致性的前提下，通过精细化的保留策略和过滤规则来控制成本。

## 📁 文件结构

```
cost/
├── README.md                           # 本文件
├── gcp-logging-cost-optimization-guide.md  # 详细优化指南
├── gcp-logging-audit-script.sh        # 日志配置审计脚本
├── gcp-logging-terraform-module.tf    # Terraform 基础设施代码
├── gcp-logging-cost-analysis.py       # Python 成本分析脚本
└── examples/                           # 使用示例（自动生成）

gcp-logging-cost-optimization-guide.md - 详细的优化指南文档
gcp-logging-audit-script.sh - 日志配置审计脚本
gcp-logging-terraform-module.tf - Terraform 基础设施代码
gcp-logging-cost-analysis.py - Python 成本分析脚本
gcp-logging-quick-setup.sh - 交互式快速设置脚本
terraform.tfvars.example - Terraform 配置示例
README.md - 使用说明和快速开始指南

```

## 🚀 快速开始

### 1. 审计当前配置

首先使用审计脚本检查您当前的日志配置：

```bash
# 给脚本执行权限
chmod +x gcp-logging-audit-script.sh

# 审计指定项目
./gcp-logging-audit-script.sh YOUR_PROJECT_ID

# 或审计当前活动项目
./gcp-logging-audit-script.sh
```

脚本将生成：
- 详细的配置审计报告
- 成本优化建议
- 可执行的配置脚本（在 `./gcp-logging-optimization/` 目录）

### 2. 使用 Terraform 部署优化配置

```bash
# 初始化 Terraform
terraform init

# 为开发环境部署优化配置
terraform plan -var="project_id=your-dev-project" -var="environment=dev"
terraform apply -var="project_id=your-dev-project" -var="environment=dev"

# 为生产环境部署（保守策略）
terraform plan -var="project_id=your-prod-project" -var="environment=prod"
terraform apply -var="project_id=your-prod-project" -var="environment=prod"
```

### 3. 成本分析和监控

```bash
# 安装 Python 依赖
pip install google-cloud-logging google-cloud-monitoring pandas matplotlib

# 运行成本分析
python3 gcp-logging-cost-analysis.py YOUR_PROJECT_ID --days 30

# 生成详细报告和可视化图表
python3 gcp-logging-cost-analysis.py YOUR_PROJECT_ID --days 30 --output-dir ./reports/
```

## 📊 预期成本节省

根据环境类型，预期的成本节省效果：

| 环境类型 | 保留期优化 | 过滤器优化 | 总体节省 |
|----------|------------|------------|----------|
| 开发环境 | 30-40% | 40-50% | 70-80% |
| 测试环境 | 20-30% | 40-50% | 60-70% |
| 预生产环境 | 10-20% | 20-30% | 30-40% |
| 生产环境 | 5-10% | 15-25% | 20-30% |

## 🎯 核心优化策略

### 1. 分环境保留策略
- **开发环境**: 3-7天保留，ERROR+ 级别
- **测试环境**: 7-14天保留，WARNING+ 级别  
- **预生产环境**: 30-60天保留，INFO+ 级别
- **生产环境**: 90-365天保留，INFO+ 级别

### 2. 智能过滤规则
- 健康检查日志过滤
- 低严重性日志过滤（非生产环境）
- 系统组件噪音过滤
- Istio/服务网格代理日志过滤

### 3. 成本监控告警
- 日志量异常监控
- 成本阈值告警
- 按资源类型的成本分析

## 🛠️ 工具详细说明

### 审计脚本 (`gcp-logging-audit-script.sh`)

**功能**:
- 检查日志桶配置和保留策略
- 审计日志接收器和排除项
- 分析 GKE 集群日志设置
- 检查审计日志配置
- 生成优化建议和配置脚本

**输出**:
- 详细的审计报告
- 自动生成的优化脚本
- 成本节省建议

### Terraform 模块 (`gcp-logging-terraform-module.tf`)

**功能**:
- 创建环境特定的日志桶
- 配置差异化保留策略
- 部署成本优化过滤器
- 设置 GCS 归档
- 创建监控指标和告警

**变量**:
- `project_id`: GCP 项目 ID
- `environment`: 环境类型 (dev/test/staging/prod)
- `enable_gcs_archive`: 是否启用 GCS 归档
- `enable_cost_optimization_filters`: 是否启用成本优化过滤器

### 成本分析脚本 (`gcp-logging-cost-analysis.py`)

**功能**:
- 分析日志使用量和成本
- 按资源类型分解成本
- 生成优化建议
- 创建可视化图表
- 输出详细的 JSON 报告

**依赖**:
```bash
pip install google-cloud-logging google-cloud-monitoring pandas matplotlib
```

## 📋 实施检查清单

### 项目级检查
- [ ] 运行审计脚本检查当前配置
- [ ] 审查并禁用非必要的数据访问审计日志
- [ ] 为不同环境创建自定义日志桶
- [ ] 配置环境特定的保留策略
- [ ] 实施日志排除过滤器

### GKE 集群级检查
- [ ] 配置集群日志收集范围（SYSTEM vs WORKLOAD）
- [ ] 实施容器级日志过滤
- [ ] 优化应用日志级别配置
- [ ] 配置日志轮转策略

### 监控和维护
- [ ] 设置成本监控指标
- [ ] 配置成本异常告警
- [ ] 建立定期审查流程
- [ ] 文档化所有配置变更

## 🔧 故障排除

### 常见问题

1. **日志突然消失**
   - 检查排除过滤器配置
   - 验证日志桶保留策略
   - 确认接收器路由规则

2. **成本未如预期下降**
   - 验证过滤器是否生效
   - 检查是否有遗漏的高成本日志源
   - 确认保留策略已应用

3. **合规性问题**
   - 确保关键审计日志未被过度过滤
   - 检查生产环境的保留策略
   - 验证归档配置

### 回滚策略

1. 保留原始配置的备份
2. 分阶段实施，便于快速回滚
3. 监控关键业务指标
4. 使用 Terraform 状态管理变更

## 📞 支持和贡献

如果您在使用过程中遇到问题或有改进建议，请：

1. 检查本 README 和详细指南
2. 查看生成的审计报告中的建议
3. 运行成本分析脚本获取详细信息

## 📄 许可证

本工具包遵循 MIT 许可证，可自由使用和修改。

---

**注意**: 在生产环境中应用任何配置变更之前，请务必在开发或测试环境中进行充分测试，并确保符合您的合规性要求。