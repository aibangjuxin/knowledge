# K8s集群迁移代理 (K8s Cluster Migration Proxy)

## 概述 (Overview)

本项目实现了Kubernetes集群间的灰度迁移功能，通过在旧集群部署代理服务，实现流量的智能分配和平滑迁移。

This project implements grayscale migration functionality between Kubernetes clusters by deploying a proxy service in the old cluster to achieve intelligent traffic allocation and smooth migration.

## 功能特性 (Features)

### ✅ 已实现功能 (Implemented Features)

- **配置管理 (Configuration Management)**
  - ConfigMap热更新支持
  - 配置验证和错误处理
  - 本地文件和K8s ConfigMap双模式支持

- **流量分配 (Traffic Allocation)**
  - 基于权重的流量分配
  - 基于请求头的路由规则
  - 基于IP地址的路由规则
  - 基于用户ID哈希的路由规则

- **故障处理 (Failure Handling)**
  - 自动降级机制
  - 失败计数和恢复时间控制
  - 健康检查集成

- **Nginx配置生成 (Nginx Configuration Generation)**
  - 动态Nginx配置生成
  - 配置语法验证
  - 热重载支持

## 架构设计 (Architecture)

```
客户端请求 → 旧集群Ingress → 迁移代理 → 新集群/旧集群服务
Client Request → Old Cluster Ingress → Migration Proxy → New/Old Cluster Services
```

### 核心组件 (Core Components)

1. **ConfigManager**: 配置管理器，支持ConfigMap和本地文件的热更新
2. **TrafficAllocator**: 流量分配器，实现多种路由策略
3. **NginxConfigGenerator**: Nginx配置生成器，动态生成代理配置
4. **MigrationController**: 迁移控制器，协调所有组件

## 快速开始 (Quick Start)

### 1. 部署ConfigMap

```bash
kubectl apply -f config/migration-configmap.yaml
```

### 2. 构建Docker镜像

```bash
docker build -t migration-proxy:latest .
```

### 3. 部署到K8s集群

```bash
kubectl apply -f k8s/deployment.yaml
```

### 4. 验证部署

```bash
kubectl get pods -n aibang-1111111111-bbdm -l app=migration-proxy
kubectl logs -n aibang-1111111111-bbdm -l app=migration-proxy
```

## 配置说明 (Configuration)

### ConfigMap配置示例

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: migration-config
data:
  migration.yaml: |
    global:
      default_timeout: 30s
      retry_attempts: 3
    
    services:
      - name: "api-name01"
        old_host: "api-name01.teamname.dev.aliyun.intracloud.cn.aibang"
        old_backend: "bbdm-api.aibang-1111111111-bbdm.svc.cluster.local:8078"
        new_host: "api-name01.kong.dev.aliyun.intracloud.cn.aibang"
        new_backend: "api-name01.kong.dev.aliyun.intracloud.cn.aibang:443"
        migration:
          enabled: true
          strategy: "weight"
          percentage: 20  # 20%流量到新集群
        canary:
          header_rules:
            - header: "X-Migration-Target"
              value: "new"
              target: "new_cluster"
        fallback:
          enabled: true
          max_failures: 5
          failure_window: 60
          recovery_time: 300
```

### 路由策略 (Routing Strategies)

1. **权重路由 (Weight-based)**
   ```yaml
   migration:
     strategy: "weight"
     percentage: 50  # 50%流量到新集群
   ```

2. **请求头路由 (Header-based)**
   ```yaml
   canary:
     header_rules:
       - header: "X-Migration-Target"
         value: "new"
         target: "new_cluster"
   ```

3. **IP路由 (IP-based)**
   ```yaml
   canary:
     ip_rules:
       - cidr: "10.0.0.0/8"
         target: "new_cluster"
   ```

## 使用方法 (Usage)

### 命令行工具

```bash
# 运行迁移控制器
python src/migration_controller.py run

# 查看状态
python src/migration_controller.py status

# 更新服务迁移百分比
python src/migration_controller.py update api-name01 50
```

### API接口

迁移控制器提供HTTP API接口：

```bash
# 健康检查
curl http://localhost:8080/health

# 获取指标
curl http://localhost:8080/metrics

# 获取状态
curl http://localhost:8080/status
```

## 开发环境 (Development)

### 安装依赖

```bash
pip install -r requirements.txt
```

### 运行测试

```bash
pytest tests/ -v
```

### 代码格式化

```bash
black src/
flake8 src/
```

### 本地开发

使用本地配置文件进行开发：

```bash
python src/migration_controller.py run --local-config ./config/migration.yaml
```

## 监控和日志 (Monitoring & Logging)

### 日志格式

```
2024-01-01 12:00:00 - migration_controller - INFO - Configuration changed, updating components...
```

### 关键指标

- 新旧集群流量分布
- 响应时间和错误率
- 配置更新频率
- 降级事件统计

### Nginx访问日志

```
192.168.1.1 - - [01/Jan/2024:12:00:00 +0000] "GET /api/test HTTP/1.1" 200 1234 backend="new_backend" upstream_response_time=0.123 request_time=0.125
```

## 故障排查 (Troubleshooting)

### 常见问题

1. **配置更新不生效**
   - 检查ConfigMap是否正确更新
   - 查看控制器日志确认配置加载
   - 验证Nginx配置语法

2. **流量分配不均匀**
   - 检查权重配置是否正确
   - 确认路由规则优先级
   - 查看流量分配日志

3. **新集群连接失败**
   - 验证网络连通性
   - 检查DNS解析
   - 确认证书配置

### 日志查看

```bash
# 查看控制器日志
kubectl logs -n aibang-1111111111-bbdm -l app=migration-proxy -c migration-proxy

# 查看Nginx日志
kubectl exec -n aibang-1111111111-bbdm deployment/migration-proxy -- tail -f /var/log/nginx/migration_access.log
```

## 安全考虑 (Security)

- 使用非root用户运行容器
- 最小权限RBAC配置
- TLS证书管理
- 网络策略限制

## 性能优化 (Performance)

- Nginx连接池配置
- 上游服务器健康检查
- 缓存和压缩设置
- 资源限制配置

## 贡献指南 (Contributing)

1. Fork项目
2. 创建功能分支
3. 提交代码变更
4. 运行测试
5. 提交Pull Request

## 许可证 (License)

MIT License

## 联系方式 (Contact)

如有问题或建议，请提交Issue或联系维护团队。