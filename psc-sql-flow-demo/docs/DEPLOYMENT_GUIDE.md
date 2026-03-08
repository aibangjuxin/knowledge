# GKE Pod 通过 PSC 连接 Cloud SQL 部署指南

## 概述

这个演示展示了如何在 Google Kubernetes Engine (GKE) 中部署应用程序，通过 Private Service Connect (PSC) 安全地连接到另一个项目的 Cloud SQL 实例。

## 架构说明

### Producer 项目 (数据库项目)
- Cloud SQL 实例 (MySQL)
- 启用 Private Service Connect
- 配置授权的 Consumer 项目

### Consumer 项目 (应用项目)
- GKE 集群
- PSC 端点连接到 Cloud SQL
- Go 应用程序 (REST API)
- Workload Identity 集成
- 自动扩缩容 (HPA)

## 核心特性

### 安全性
- **Workload Identity**: GKE Pod 使用 Google Service Account 身份
- **Network Policy**: 限制 Pod 间网络通信
- **Private Service Connect**: 数据库流量不经过公网
- **Secret 管理**: 数据库密码存储在 Kubernetes Secret 中

### 可靠性
- **健康检查**: Liveness、Readiness 和 Startup 探针
- **资源限制**: CPU 和内存限制防止资源耗尽
- **Pod 反亲和性**: 确保 Pod 分布在不同节点
- **自动重启**: 失败的 Pod 自动重启

### 可扩展性
- **Horizontal Pod Autoscaler**: 基于 CPU/内存自动扩缩容
- **连接池**: 数据库连接池优化性能
- **多副本**: 默认运行 2 个 Pod 副本

## 部署步骤

### 1. 环境准备

```bash
# 克隆或下载项目文件
cd psc-demo

# 配置环境变量
vim setup/env-vars.sh
# 修改以下变量:
# - PRODUCER_PROJECT_ID: 数据库项目 ID
# - CONSUMER_PROJECT_ID: 应用项目 ID
# - 其他配置根据需要调整

# 加载环境变量
source setup/env-vars.sh
```

### 2. 设置 Producer 项目

```bash
# 创建 Cloud SQL 实例并启用 PSC
./setup/setup-producer.sh
```

这个脚本会：
- 启用必要的 API
- 创建 VPC 网络
- 配置私有 IP 范围
- 创建 Cloud SQL 实例
- 启用 Private Service Connect
- 创建应用数据库和用户

### 3. 设置 Consumer 项目

```bash
# 创建 GKE 集群和 PSC 端点
./setup/setup-consumer.sh
```

这个脚本会：
- 启用必要的 API
- 创建 VPC 网络和子网
- 创建 PSC 端点
- 配置防火墙规则
- 创建 GKE 集群
- 配置 Workload Identity

### 4. 部署应用

```bash
# 构建镜像并部署到 GKE
./scripts/deploy-app.sh
```

这个脚本会：
- 构建 Docker 镜像
- 推送到 Container Registry
- 配置 Workload Identity
- 部署 Kubernetes 资源
- 等待 Pod 启动完成

### 5. 测试连接

```bash
# 测试 PSC 连接和应用功能
./scripts/test-connection.sh
```

## 应用程序说明

### API 端点

- `GET /` - 服务信息
- `GET /health` - 健康检查 (包含数据库状态)
- `GET /ready` - 就绪检查
- `GET /api/v1/users` - 获取用户列表
- `POST /api/v1/users` - 创建用户
- `GET /api/v1/users/{id}` - 获取特定用户
- `GET /api/v1/db-stats` - 数据库连接池统计

### 环境变量配置

应用程序通过以下环境变量配置：

```yaml
# 数据库配置
DB_HOST: PSC 端点 IP 地址
DB_PORT: 数据库端口 (3306)
DB_NAME: 数据库名称
DB_USER: 数据库用户名
DB_PASSWORD: 数据库密码 (来自 Secret)

# 连接池配置
DB_MAX_CONNECTIONS: 最大连接数
DB_MAX_IDLE_CONNECTIONS: 最大空闲连接数
DB_CONNECTION_MAX_LIFETIME: 连接最大生命周期
DB_CONNECTION_TIMEOUT: 连接超时时间

# 应用配置
APP_PORT: 应用端口 (8080)
LOG_LEVEL: 日志级别
ENVIRONMENT: 运行环境
```

## 监控和故障排除

### 使用监控脚本

```bash
# 启动交互式监控面板
./scripts/monitor.sh
```

监控功能包括：
- 实时 Pod 状态
- 服务状态
- 自动扩缩容状态
- 应用日志
- 数据库连接统计
- 端口转发测试

### 常用调试命令

```bash
# 查看 Pod 状态
kubectl get pods -n psc-demo

# 查看 Pod 日志
kubectl logs -f deployment/db-app -n psc-demo

# 进入 Pod 调试
kubectl exec -it deployment/db-app -n psc-demo -- /bin/sh

# 端口转发到本地测试
kubectl port-forward svc/db-app-service 8080:80 -n psc-demo

# 查看事件
kubectl get events -n psc-demo --sort-by='.lastTimestamp'

# 查看 HPA 状态
kubectl get hpa -n psc-demo

# 测试数据库连接
kubectl exec deployment/db-app -n psc-demo -- nc -zv <PSC_IP> 3306
```

### 本地测试

启动端口转发后，可以在本地测试：

```bash
# 健康检查
curl http://localhost:8080/health

# 获取用户列表
curl http://localhost:8080/api/v1/users

# 创建用户
curl -X POST http://localhost:8080/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"name":"John Doe","email":"john@example.com"}'

# 数据库统计
curl http://localhost:8080/api/v1/db-stats
```

## 常见问题

### 1. Pod 无法启动

**症状**: Pod 处于 `CrashLoopBackOff` 状态

**排查步骤**:
```bash
# 查看 Pod 事件
kubectl describe pod <pod-name> -n psc-demo

# 查看应用日志
kubectl logs <pod-name> -n psc-demo

# 检查配置
kubectl get configmap db-config -n psc-demo -o yaml
kubectl get secret db-credentials -n psc-demo -o yaml
```

**常见原因**:
- 数据库连接配置错误
- PSC 端点 IP 不正确
- 数据库密码错误
- 网络策略阻止连接

### 2. 数据库连接失败

**症状**: 应用日志显示数据库连接错误

**排查步骤**:
```bash
# 测试网络连通性
kubectl exec deployment/db-app -n psc-demo -- ping <PSC_IP>
kubectl exec deployment/db-app -n psc-demo -- nc -zv <PSC_IP> 3306

# 检查 PSC 端点状态
gcloud compute forwarding-rules describe sql-psc-endpoint \
  --region=asia-east2 --project=<consumer-project>

# 检查防火墙规则
gcloud compute firewall-rules list --project=<consumer-project>
```

### 3. Workload Identity 问题

**症状**: Pod 无法访问 Google Cloud 服务

**排查步骤**:
```bash
# 检查 Service Account 绑定
kubectl describe sa db-app-sa -n psc-demo

# 检查 IAM 绑定
gcloud iam service-accounts get-iam-policy \
  db-app-gsa@<consumer-project>.iam.gserviceaccount.com
```

## 清理资源

```bash
# 清理所有创建的资源
./scripts/cleanup.sh
```

这个脚本会删除：
- Kubernetes 命名空间和所有资源
- GKE 集群
- PSC 端点和静态 IP
- 防火墙规则
- VPC 网络
- Service Account
- 可选：Cloud SQL 实例

## 最佳实践

### 安全性
- 使用 Workload Identity 而不是 Service Account Key
- 启用网络策略限制 Pod 间通信
- 使用 Secret 存储敏感信息
- 定期轮换数据库密码

### 性能
- 配置合适的连接池大小
- 设置适当的资源请求和限制
- 使用 HPA 自动扩缩容
- 监控数据库连接使用情况

### 可靠性
- 配置健康检查探针
- 使用 Pod 反亲和性
- 设置适当的容忍度
- 实施监控和告警

### 成本优化
- 使用合适的机器类型
- 配置 HPA 避免过度配置
- 监控资源使用情况
- 定期审查和优化配置