# GCP DNS 迁移工具

这是一个用于 GCP 跨项目 DNS 迁移的自动化工具集，支持零停机的 DNS 切换和完整的回滚机制。

## 功能特性

- 🔍 **自动服务发现**: 自动发现源项目和目标项目的服务映射关系
- 🎯 **智能DNS准备**: 在目标项目中自动创建对应的DNS记录
- 🔄 **零停机切换**: 通过CNAME重定向实现平滑的DNS切换
- 📊 **完整验证**: 全面验证DNS解析和服务可用性
- 🔙 **快速回滚**: 5分钟内完成DNS回滚操作
- 🧹 **资源清理**: 安全清理源项目中不再使用的资源
- 📝 **详细报告**: 生成完整的迁移和验证报告

## 架构支持

支持以下 GCP 架构的迁移：
- Nginx Proxy L4 + GKE Ingress Controller
- Internal Load Balancer (ILB) + GKE
- LoadBalancer Service + GKE
- 混合架构

## 目录结构

```
migrate-dns/
├── config.sh                 # 配置文件
├── migrate-dns.sh            # 主控制脚本
├── 01-discovery.sh           # 服务发现脚本
├── 02-prepare-target.sh      # 目标项目准备脚本
├── 03-execute-migration.sh   # DNS迁移执行脚本
├── 04-rollback.sh           # 回滚脚本
├── 05-cleanup.sh            # 清理脚本
├── README.md                # 本文档
├── backup/                  # 备份目录（自动创建）
└── logs/                    # 日志目录（自动创建）
```

## 快速开始

### 1. 环境准备

确保已安装以下工具：
```bash
# 安装 gcloud CLI
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# 安装 kubectl
gcloud components install kubectl

# 认证
gcloud auth login
gcloud auth application-default login
```

### 2. 配置参数

编辑 `config.sh` 文件，设置你的项目参数：

```bash
# 项目配置
export SOURCE_PROJECT="your-source-project"
export TARGET_PROJECT="your-target-project"
export PARENT_DOMAIN="dev.aliyun.cloud.uk.aibang"

# 集群配置
export SOURCE_CLUSTER="gke-01"
export TARGET_CLUSTER="gke-01"
export CLUSTER_REGION="europe-west2"

# 域名映射配置
export DOMAIN_MAPPINGS=(
    "events:ilb"
    "events-proxy:ingress"
    "api:ingress"
    "admin:ingress"
)
```

### 3. 执行迁移

#### 方式一：完整自动迁移
```bash
# 给脚本执行权限
chmod +x *.sh

# 执行完整迁移流程
./migrate-dns.sh all
```

#### 方式二：分步骤执行
```bash
# 1. 服务发现
./migrate-dns.sh discovery

# 2. 准备目标项目
./migrate-dns.sh prepare

# 3. 执行DNS切换
./migrate-dns.sh migrate

# 4. 清理资源（可选）
./migrate-dns.sh cleanup
```

### 4. 检查状态

```bash
# 查看迁移状态
./migrate-dns.sh status

# 查看详细日志
tail -f logs/migration_*.log
```

## 详细使用说明

### 配置说明

#### 域名映射类型

- `ingress`: GKE Ingress Controller 服务
- `ilb`: Internal Load Balancer 服务  
- `service`: LoadBalancer 类型的 Service

#### 示例配置

```bash
# 域名映射示例
export DOMAIN_MAPPINGS=(
    "api:ingress"           # api.project-id.domain -> Ingress
    "events:ilb"            # events.project-id.domain -> ILB
    "admin:service"         # admin.project-id.domain -> Service
)
```

### 迁移流程详解

#### 阶段 1: 服务发现 (Discovery)
- 扫描源项目和目标项目的 GKE 集群
- 发现 Deployment、Service、Ingress 的映射关系
- 获取当前 DNS 记录配置
- 生成迁移计划

#### 阶段 2: 目标准备 (Prepare)
- 在目标项目创建 DNS Zone（如果不存在）
- 创建新的 DNS 记录指向目标项目服务
- 生成 SSL 证书配置
- 验证目标项目服务可用性

#### 阶段 3: DNS 切换 (Migrate)
- 降低源项目 DNS 记录的 TTL
- 将源项目 DNS 记录切换为 CNAME 指向目标项目
- 验证 DNS 传播和服务可用性
- 生成迁移报告

#### 阶段 4: 回滚 (Rollback)
- 从备份文件恢复原始 DNS 记录
- 验证回滚结果
- 测试服务可用性

#### 阶段 5: 清理 (Cleanup)
- 扫描源项目中可清理的资源
- 安全删除不再使用的 GKE 集群、负载均衡器等
- 清理过渡期的 CNAME 记录

### 高级用法

#### 干运行模式
```bash
# 查看将要执行的操作，不实际执行
./migrate-dns.sh --dry-run migrate
```

#### 强制模式
```bash
# 跳过确认提示，自动执行
./migrate-dns.sh --force cleanup
```

#### 自定义配置
```bash
# 使用自定义配置文件
./migrate-dns.sh --config my-config.sh migrate
```

#### 覆盖项目参数
```bash
# 临时覆盖项目配置
./migrate-dns.sh --source-project proj1 --target-project proj2 all
```

## 安全考虑

### 权限要求

确保执行用户具有以下权限：

**源项目权限：**
- `roles/viewer` - 读取资源配置
- `roles/dns.admin` - 管理 DNS 记录
- `roles/container.viewer` - 查看 GKE 集群

**目标项目权限：**
- `roles/dns.admin` - 管理 DNS 记录
- `roles/container.admin` - 管理 GKE 集群
- `roles/compute.admin` - 管理负载均衡器

### 备份策略

工具会自动创建以下备份：
- DNS 记录备份（JSON 格式）
- 服务映射关系备份
- 迁移计划和报告

备份文件位置：`backup/YYYYMMDD_HHMMSS/`

### 回滚保障

- 所有 DNS 操作都有对应的回滚脚本
- 支持从任意备份点恢复
- 5 分钟内完成紧急回滚

## 故障排除

### 常见问题

#### 1. DNS 解析失败
```bash
# 检查 DNS 传播状态
dig +short your-domain.com @8.8.8.8
dig +short your-domain.com @1.1.1.1

# 检查 TTL 设置
dig your-domain.com
```

#### 2. 服务不可访问
```bash
# 检查目标项目服务状态
kubectl get pods,svc,ingress -n default

# 检查负载均衡器状态
gcloud compute forwarding-rules list --project=target-project
```

#### 3. 权限问题
```bash
# 检查当前认证状态
gcloud auth list

# 检查项目权限
gcloud projects get-iam-policy source-project
gcloud projects get-iam-policy target-project
```

### 日志分析

```bash
# 查看详细日志
tail -f logs/migration_*.log

# 搜索错误信息
grep -i error logs/migration_*.log

# 查看特定阶段的日志
grep "步骤" logs/migration_*.log
```

### 紧急回滚

如果迁移过程中出现问题，立即执行：

```bash
# 紧急回滚
./migrate-dns.sh rollback

# 或者手动回滚单个域名
gcloud dns record-sets transaction start --zone=source-zone
gcloud dns record-sets transaction remove "target.domain.com." \
  --name="source.domain.com." --type=CNAME --zone=source-zone
gcloud dns record-sets transaction add "original-ip" \
  --name="source.domain.com." --type=A --ttl=60 --zone=source-zone
gcloud dns record-sets transaction execute --zone=source-zone
```

## 最佳实践

### 迁移前准备

1. **测试环境验证**：先在测试环境完整验证迁移流程
2. **备份检查**：确保所有重要数据已备份
3. **监控准备**：设置迁移期间的监控和告警
4. **团队协调**：通知相关团队迁移时间窗口

### 迁移执行

1. **低峰期执行**：选择业务低峰期进行迁移
2. **分批迁移**：对于大量域名，建议分批次迁移
3. **实时监控**：密切监控服务可用性和性能指标
4. **快速响应**：准备好快速回滚方案

### 迁移后验证

1. **功能测试**：全面测试所有业务功能
2. **性能监控**：监控服务性能是否符合预期
3. **日志检查**：检查应用日志是否有异常
4. **用户反馈**：收集用户使用反馈

## 贡献指南

欢迎提交 Issue 和 Pull Request 来改进这个工具。

### 开发环境设置

```bash
# 克隆仓库
git clone <repository-url>
cd migrate-dns

# 设置开发环境
cp config.sh config-dev.sh
# 编辑 config-dev.sh 设置测试项目

# 运行测试
./migrate-dns.sh --config config-dev.sh --dry-run all
```

### 代码规范

- 使用 `set -euo pipefail` 确保脚本安全性
- 所有函数都要有错误处理
- 重要操作前要有用户确认
- 详细的日志记录和错误信息

## 许可证

MIT License

## 支持

如有问题，请提交 Issue 或联系维护团队。