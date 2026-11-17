# GKE Pod 通过 PSC 连接 Cloud SQL 演示

完美！我已经为你创建了一个完整的 PSC 演示项目，专门展示 GKE Pod 如何通过 Private Service Connect 连接到 Cloud SQL。

## 项目概述

这个演示展示了如何在 Google Kubernetes Engine (GKE) 中部署应用程序，通过 Private Service Connect (PSC) 安全地连接到另一个项目的 Cloud SQL 实例。

## 架构概述

```
Producer Project (数据库项目)
├── Cloud SQL Instance (启用 PSC)
└── Service Attachment

Consumer Project (应用项目)  
├── GKE Cluster
├── PSC Endpoint
├── Kubernetes Deployment
├── Service Account & IAM
└── ConfigMap/Secret
```

## 项目结构

```
psc-demo/
├── README.md                    # 项目概述
├── Flow.md                      # 流程图和架构说明
├── setup/                       # 基础设施配置
│   ├── env-vars.sh             # 环境变量配置
│   ├── setup-producer.sh       # Producer 项目设置 (Cloud SQL)
│   └── setup-consumer.sh       # Consumer 项目设置 (GKE)
├── k8s/                        # Kubernetes 资源配置
│   ├── namespace.yaml          # 命名空间
│   ├── service-account.yaml    # Service Account (Workload Identity)
│   ├── configmap.yaml          # 应用配置
│   ├── secret.yaml             # 数据库密码
│   ├── deployment.yaml         # 应用部署配置
│   ├── service.yaml            # Kubernetes 服务
│   ├── hpa.yaml               # 自动扩缩容
│   └── network-policy.yaml     # 网络策略
├── app/                        # 示例应用程序
│   ├── main.go                 # Go 应用程序
│   ├── go.mod                  # Go 模块
│   └── Dockerfile              # Docker 镜像
├── scripts/                    # 部署和管理脚本
│   ├── deploy-app.sh           # 应用部署脚本
│   ├── test-connection.sh      # 连接测试脚本
│   ├── monitor.sh              # 监控脚本
│   └── cleanup.sh              # 资源清理脚本
└── docs/                       # 文档
    ├── DEPLOYMENT_GUIDE.md     # 部署指南
    └── TROUBLESHOOTING.md      # 故障排除指南
```

## 核心特性

### 🔐 安全性
- **Workload Identity**: GKE Pod 使用 Google Service Account 身份，无需 Service Account Key
- **Network Policy**: 限制 Pod 间网络通信
- **Private Service Connect**: 数据库流量完全在 Google Cloud 内部
- **Secret 管理**: 数据库密码安全存储

### 🚀 生产就绪
- **健康检查**: Liveness、Readiness 和 Startup 探针
- **自动扩缩容**: 基于 CPU/内存的 HPA
- **资源限制**: 防止资源耗尽
- **Pod 反亲和性**: 确保高可用性

### 📊 可观测性
- **监控面板**: 实时监控 Pod、服务状态
- **数据库统计**: 连接池使用情况
- **日志聚合**: 结构化日志输出
- **健康检查端点**: 详细的健康状态信息

## 快速开始

1. **配置环境变量**
```bash
cd psc-demo
vim setup/env-vars.sh  # 修改项目 ID 等配置
source setup/env-vars.sh
```

2. **设置 Producer 项目** (创建 Cloud SQL)
```bash
./setup/setup-producer.sh
```

3. **设置 Consumer 项目** (创建 GKE 和 PSC)
```bash
./setup/setup-consumer.sh
```

4. **部署应用**
```bash
./scripts/deploy-app.sh
```

5. **测试连接**
```bash
./scripts/test-connection.sh
```

## 应用程序特点

这个 Go 应用程序提供了完整的 REST API，包括：

- **健康检查端点**: `/health`, `/ready`
- **用户管理 API**: CRUD 操作
- **数据库统计**: 连接池监控
- **Pod 信息**: 显示 Pod 名称、IP 等信息

### Deployment 配置亮点

```yaml
# Workload Identity 集成
serviceAccountName: db-app-sa

# 环境变量从 ConfigMap 和 Secret 加载
env:
- name: DB_HOST
  valueFrom:
    configMapKeyRef:
      name: db-config
      key: DB_HOST
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: db-credentials
      key: DB_PASSWORD

# 完整的健康检查配置
livenessProbe:
  httpGet:
    path: /health
    port: 8080
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
startupProbe:
  httpGet:
    path: /health
    port: 8080

# 安全上下文
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
```

## 监控和故障排除

项目包含了完整的监控和故障排除工具：

```bash
# 交互式监控面板
./scripts/monitor.sh

# 端口转发进行本地测试
kubectl port-forward svc/db-app-service 8080:80 -n psc-demo
curl http://localhost:8080/health
```

## 文档

- [Flow.md](Flow.md) - 详细的流程图和架构说明
- [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) - 完整的部署指南
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - 故障排除指南

这个演示完美展示了在生产环境中如何安全、可靠地连接 GKE 应用到 Cloud SQL，包含了所有必要的安全配置、监控和故障排除工具。你可以直接使用这些配置作为你实际项目的模板！