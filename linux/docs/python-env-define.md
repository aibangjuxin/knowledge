# Python Gunicorn 环境变量覆盖问题排查指南

## 问题背景

### 症状描述

在生产环境中遇到 Python 应用超时问题，经过完整的链路排查（A → B → C → D 组件），发现：

- A 组件（L7 Nginx）：超时配置 300s ✅
- B 组件（L4 Nginx）：超时配置 300s ✅  
- C 组件（Kong DP）：超时配置 300s ✅
- D 组件（GKE Runtime）：**实际超时远小于预期** ❌

**关键发现：**
- 平台默认配置文件 `/opt/conf/gunicorn.conf.py` 设置了 `timeout = 0`（无限超时）和 `workers = 4`
- 但实际运行时，应用仍然在 30 秒左右超时
- 检查 Pod 发现实际 worker 数量是 3+1（而非预期的 4+1）

### 根本原因

**用户在构建镜像时设置了环境变量：**

```bash
GUNICORN_CMD_ARGS="--bind=0.0.0.0:8443 --workers=3 --keyfile=... --certfile=..."
```

**问题：**
1. 环境变量 `GUNICORN_CMD_ARGS` 的优先级高于配置文件
2. 环境变量中只指定了部分参数（bind、workers、SSL），**缺少 timeout 参数**
3. 导致 Gunicorn 使用默认的 `timeout = 30` 秒，而非配置文件中的 `timeout = 0`

---

## Gunicorn 配置优先级

### 配置加载顺序（从低到高）

```
1. Gunicorn 内置默认值
   ↓
2. 配置文件 (gunicorn.conf.py)
   ↓
3. 命令行参数 (--timeout, --workers, etc.)
   ↓
4. 环境变量 (GUNICORN_CMD_ARGS)  ← 最高优先级
```


**关键点：**
- `GUNICORN_CMD_ARGS` 环境变量会**完全覆盖**配置文件中的对应参数
- 如果环境变量中缺少某个参数，Gunicorn 会使用**内置默认值**，而非配置文件中的值
- 这是一个常见的配置陷阱

### Gunicorn 内置默认值

```python
# Gunicorn 默认配置
bind = "127.0.0.1:8000"
workers = 1
worker_class = "sync"
timeout = 30          # ← 默认 30 秒超时
keepalive = 2
max_requests = 0
max_requests_jitter = 0
```

**重要：** 当使用 `GUNICORN_CMD_ARGS` 时，未指定的参数会回退到这些默认值，而不是配置文件中的值。

---

## 完整排查步骤

### 步骤 1：检查环境变量

#### 方法 A：登录 Pod 检查

```bash
# 列出所有 Pod
kubectl get pods -n your-namespace

# 登录到 Pod
kubectl exec -it -n your-namespace <pod-name> -- bash

# 检查所有环境变量
env | sort

# 检查 Gunicorn 相关环境变量
env | grep -i gunicorn

# 预期输出示例：
# GUNICORN_CMD_ARGS=--bind=0.0.0.0:8443 --workers=3 --keyfile=/path/to/key --certfile=/path/to/cert
```

#### 方法 B：通过 kubectl 检查

```bash
# 查看 Pod 的环境变量
kubectl get pod -n your-namespace <pod-name> -o json | jq '.spec.containers[].env'

# 或使用 describe
kubectl describe pod -n your-namespace <pod-name> | grep -A 20 "Environment:"
```

#### 方法 C：检查 Deployment/StatefulSet 配置

```bash
# 检查 Deployment
kubectl get deployment -n your-namespace <deployment-name> -o yaml | grep -A 10 "env:"

# 检查 ConfigMap（如果环境变量来自 ConfigMap）
kubectl get configmap -n your-namespace -o yaml

# 检查 Secret（如果环境变量来自 Secret）
kubectl get secret -n your-namespace <secret-name> -o yaml
```

---

### 步骤 2：验证实际运行的 Worker 数量

#### 检查 Gunicorn 进程

```bash
# 登录 Pod
kubectl exec -it -n your-namespace <pod-name> -- bash

# 查看所有 Gunicorn 进程
ps aux | grep gunicorn

# 预期输出：
# root         1  0.0  0.1  Master process
# root        10  0.0  0.2  Worker process 1
# root        11  0.0  0.2  Worker process 2
# root        12  0.0  0.2  Worker process 3
```

**分析：**
- Master 进程：1 个
- Worker 进程：3 个（而非配置文件中的 4 个）
- **总进程数：4 个（3 workers + 1 master）**

#### 通过 Gunicorn 日志确认

```bash
# 查看 Pod 启动日志
kubectl logs -n your-namespace <pod-name> | head -20

# 预期输出：
# [2026-02-25 10:00:00 +0000] [1] [INFO] Starting gunicorn 20.1.0
# [2026-02-25 10:00:00 +0000] [1] [INFO] Listening at: https://0.0.0.0:8443 (1)
# [2026-02-25 10:00:00 +0000] [1] [INFO] Using worker: sync
# [2026-02-25 10:00:00 +0000] [10] [INFO] Booting worker with pid: 10
# [2026-02-25 10:00:00 +0000] [11] [INFO] Booting worker with pid: 11
# [2026-02-25 10:00:00 +0000] [12] [INFO] Booting worker with pid: 12
```

**关键信息：**
- Worker 数量：3 个（pid 10, 11, 12）
- 绑定地址：`https://0.0.0.0:8443`（来自环境变量）
- **没有显示 timeout 配置**（使用默认值 30s）

---

### 步骤 3：使用 gcrane 分析镜像配置

#### 安装 gcrane

```bash
# macOS
brew install gcrane

# Linux
go install github.com/google/go-containerregistry/cmd/gcrane@latest

# 或使用 Docker
docker run --rm gcr.io/go-containerregistry/gcrane:latest
```

#### 分析 GCR 镜像

```bash
# 获取镜像完整配置
gcrane config gcr.io/your-project/your-image:tag | jq

# 查看环境变量
gcrane config gcr.io/your-project/your-image:tag | jq '.config.Env'

# 预期输出：
# [
#   "PATH=/usr/local/bin:/usr/bin:/bin",
#   "GUNICORN_CMD_ARGS=--bind=0.0.0.0:8443 --workers=3 --keyfile=/certs/key.pem --certfile=/certs/cert.pem",
#   "PYTHONUNBUFFERED=1"
# ]
```

#### 查看镜像构建历史

```bash
# 查看镜像层历史
gcrane manifest gcr.io/your-project/your-image:tag | jq

# 查看 Dockerfile 指令（如果可用）
docker history gcr.io/your-project/your-image:tag --no-trunc
```

---

### 步骤 4：检查配置文件内容

#### 查看平台默认配置

```bash
# 登录 Pod
kubectl exec -it -n your-namespace <pod-name> -- bash

# 查看 Gunicorn 配置文件
cat /opt/conf/gunicorn.conf.py

# 预期内容：
# bind = "0.0.0.0:8080"
# workers = 4
# worker_class = "sync"
# timeout = 0          # 无限超时
# keepalive = 5
# accesslog = "-"
# errorlog = "-"
# loglevel = "info"
```

#### 验证配置文件是否被使用

```bash
# 检查 Gunicorn 启动命令
ps aux | grep gunicorn | head -1

# 预期输出（如果使用配置文件）：
# gunicorn -c /opt/conf/gunicorn.conf.py app:application

# 实际输出（如果被环境变量覆盖）：
# gunicorn --bind=0.0.0.0:8443 --workers=3 --keyfile=... app:application
```

---

## 问题验证方法

### 验证 1：测试超时行为

```bash
# 创建测试端点（在应用代码中）
@app.route('/test/timeout/<int:seconds>')
def test_timeout(seconds):
    import time
    time.sleep(seconds)
    return {"status": "success", "slept": seconds}

# 测试 30 秒（应该成功，如果 timeout > 30）
time curl -X GET "https://your-app/test/timeout/30"

# 测试 35 秒（应该超时，如果 timeout = 30）
time curl -X GET "https://your-app/test/timeout/35"

# 测试 60 秒（应该超时，如果 timeout = 30）
time curl -X GET "https://your-app/test/timeout/60"
```

**预期结果：**
- 如果 timeout = 30（默认值）：35 秒和 60 秒请求会超时
- 如果 timeout = 0（配置文件）：所有请求都应该成功

---

### 验证 2：动态修改环境变量测试

```bash
# 登录 Pod
kubectl exec -it -n your-namespace <pod-name> -- bash

# 临时修改环境变量（添加 timeout 参数）
export GUNICORN_CMD_ARGS="--bind=0.0.0.0:8443 --workers=3 --timeout=300 --keyfile=/certs/key.pem --certfile=/certs/cert.pem"

# 重启 Gunicorn（如果可以）
pkill -HUP gunicorn

# 或重启 Pod
kubectl delete pod -n your-namespace <pod-name>
```

---

## 解决方案

### 方案 1：修改环境变量（推荐）

#### 选项 A：在环境变量中添加 timeout 参数

```bash
# 修改 Deployment/StatefulSet
kubectl edit deployment -n your-namespace <deployment-name>

# 修改 env 部分：
env:
  - name: GUNICORN_CMD_ARGS
    value: "--bind=0.0.0.0:8443 --workers=3 --timeout=0 --keyfile=/certs/key.pem --certfile=/certs/cert.pem"
    #                                         ^^^^^^^^^^^^ 添加 timeout 参数
```

**完整示例：**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: python-app
  namespace: your-namespace
spec:
  template:
    spec:
      containers:
      - name: app
        image: gcr.io/your-project/your-image:tag
        env:
        - name: GUNICORN_CMD_ARGS
          value: >-
            --bind=0.0.0.0:8443
            --workers=4
            --timeout=0
            --worker-class=sync
            --keyfile=/certs/key.pem
            --certfile=/certs/cert.pem
            --access-logfile=-
            --error-logfile=-
            --log-level=info
```

#### 选项 B：使用 ConfigMap 管理环境变量

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gunicorn-config
  namespace: your-namespace
data:
  GUNICORN_CMD_ARGS: |
    --bind=0.0.0.0:8443
    --workers=4
    --timeout=0
    --worker-class=sync
    --keyfile=/certs/key.pem
    --certfile=/certs/cert.pem

---
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: python-app
spec:
  template:
    spec:
      containers:
      - name: app
        envFrom:
        - configMapRef:
            name: gunicorn-config
```

---

### 方案 2：移除环境变量，使用配置文件

#### 选项 A：完全移除 GUNICORN_CMD_ARGS

```bash
# 编辑 Deployment
kubectl edit deployment -n your-namespace <deployment-name>

# 删除 GUNICORN_CMD_ARGS 环境变量
# 确保启动命令使用配置文件：
# gunicorn -c /opt/conf/gunicorn.conf.py app:application
```

#### 选项 B：修改镜像构建过程

```dockerfile
# Dockerfile（修改前）
FROM python:3.9-slim

# 设置环境变量（问题所在）
ENV GUNICORN_CMD_ARGS="--bind=0.0.0.0:8443 --workers=3 --keyfile=/certs/key.pem --certfile=/certs/cert.pem"

COPY app /app
WORKDIR /app

CMD ["gunicorn", "app:application"]
```

```dockerfile
# Dockerfile（修改后）
FROM python:3.9-slim

# 移除环境变量，使用配置文件
COPY gunicorn.conf.py /opt/conf/gunicorn.conf.py
COPY app /app
WORKDIR /app

# 显式指定配置文件
CMD ["gunicorn", "-c", "/opt/conf/gunicorn.conf.py", "app:application"]
```

---

### 方案 3：混合方案（部分参数用环境变量）

**策略：** 只在环境变量中设置必须动态变化的参数（如 bind、SSL 证书路径），其他参数使用配置文件。

```bash
# 环境变量（只设置动态参数）
GUNICORN_CMD_ARGS="--bind=0.0.0.0:8443 --keyfile=/certs/key.pem --certfile=/certs/cert.pem"

# 配置文件（设置稳定参数）
# /opt/conf/gunicorn.conf.py
workers = 4
timeout = 0
worker_class = "sync"
keepalive = 5
```

**注意：** 这种方案仍然存在风险，因为环境变量中未指定的参数会使用默认值，而非配置文件值。

---

## 最佳实践

### 1. 配置管理原则

**推荐优先级：**

```
1. 配置文件（gunicorn.conf.py）
   - 用于所有稳定的、通用的配置
   - 版本控制，易于审查
   
2. 环境变量（GUNICORN_CMD_ARGS）
   - 仅用于环境特定的配置（如 bind 地址、证书路径）
   - 避免覆盖核心参数（timeout、workers）
   
3. 命令行参数
   - 仅用于临时测试和调试
```

---

### 2. 配置文件模板

```python
# /opt/conf/gunicorn.conf.py
import os
import multiprocessing

# 绑定地址（可从环境变量覆盖）
bind = os.getenv("GUNICORN_BIND", "0.0.0.0:8080")

# Worker 配置
workers = int(os.getenv("GUNICORN_WORKERS", multiprocessing.cpu_count() * 2 + 1))
worker_class = os.getenv("GUNICORN_WORKER_CLASS", "sync")
worker_connections = int(os.getenv("GUNICORN_WORKER_CONNECTIONS", 1000))
max_requests = int(os.getenv("GUNICORN_MAX_REQUESTS", 1000))
max_requests_jitter = int(os.getenv("GUNICORN_MAX_REQUESTS_JITTER", 50))

# 超时配置（关键）
timeout = int(os.getenv("GUNICORN_TIMEOUT", 0))  # 0 = 无限超时
graceful_timeout = int(os.getenv("GUNICORN_GRACEFUL_TIMEOUT", 30))
keepalive = int(os.getenv("GUNICORN_KEEPALIVE", 5))

# SSL 配置（可从环境变量覆盖）
keyfile = os.getenv("GUNICORN_KEYFILE", None)
certfile = os.getenv("GUNICORN_CERTFILE", None)

# 日志配置
accesslog = os.getenv("GUNICORN_ACCESS_LOG", "-")  # stdout
errorlog = os.getenv("GUNICORN_ERROR_LOG", "-")    # stderr
loglevel = os.getenv("GUNICORN_LOG_LEVEL", "info")
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# 进程命名
proc_name = os.getenv("GUNICORN_PROC_NAME", "gunicorn-app")

# 安全配置
limit_request_line = int(os.getenv("GUNICORN_LIMIT_REQUEST_LINE", 4096))
limit_request_fields = int(os.getenv("GUNICORN_LIMIT_REQUEST_FIELDS", 100))
limit_request_field_size = int(os.getenv("GUNICORN_LIMIT_REQUEST_FIELD_SIZE", 8190))

# 钩子函数（可选）
def on_starting(server):
    server.log.info("Gunicorn server is starting")

def on_reload(server):
    server.log.info("Gunicorn server is reloading")

def when_ready(server):
    server.log.info("Gunicorn server is ready. Spawning workers")

def pre_fork(server, worker):
    server.log.info(f"Worker {worker.pid} is being forked")

def post_fork(server, worker):
    server.log.info(f"Worker {worker.pid} has been forked")

def worker_exit(server, worker):
    server.log.info(f"Worker {worker.pid} is exiting")
```

**使用方式：**

```bash
# 只需要设置环境特定的变量
export GUNICORN_BIND="0.0.0.0:8443"
export GUNICORN_KEYFILE="/certs/key.pem"
export GUNICORN_CERTFILE="/certs/cert.pem"
export GUNICORN_TIMEOUT="0"  # 明确设置

# 启动（使用配置文件）
gunicorn -c /opt/conf/gunicorn.conf.py app:application
```

---

### 3. Kubernetes 部署最佳实践

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: python-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: python-app
  template:
    metadata:
      labels:
        app: python-app
    spec:
      containers:
      - name: app
        image: gcr.io/your-project/your-image:v1.0.0
        
        # 环境变量（只设置必要的）
        env:
        - name: GUNICORN_BIND
          value: "0.0.0.0:8443"
        - name: GUNICORN_WORKERS
          value: "4"
        - name: GUNICORN_TIMEOUT
          value: "0"  # 明确设置，避免使用默认值
        - name: GUNICORN_KEYFILE
          value: "/certs/tls.key"
        - name: GUNICORN_CERTFILE
          value: "/certs/tls.crt"
        
        # 不要使用 GUNICORN_CMD_ARGS
        # - name: GUNICORN_CMD_ARGS
        #   value: "..."  # ❌ 避免使用
        
        # 资源限制
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2000m"
            memory: "2Gi"
        
        # 健康检查
        livenessProbe:
          httpGet:
            path: /health
            port: 8443
            scheme: HTTPS
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
        
        readinessProbe:
          httpGet:
            path: /ready
            port: 8443
            scheme: HTTPS
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
        
        # 挂载证书
        volumeMounts:
        - name: tls-certs
          mountPath: /certs
          readOnly: true
      
      volumes:
      - name: tls-certs
        secret:
          secretName: app-tls-secret
```

---

### 4. 配置验证清单

部署前验证：

- [ ] 检查镜像中是否设置了 `GUNICORN_CMD_ARGS` 环境变量
- [ ] 如果使用环境变量，确保包含所有关键参数（特别是 `timeout`）
- [ ] 验证配置文件存在且内容正确
- [ ] 确认启动命令使用了配置文件（`-c /path/to/gunicorn.conf.py`）
- [ ] 测试超时行为（使用延迟端点）
- [ ] 验证 worker 数量符合预期
- [ ] 检查日志中的启动信息

**验证脚本：**

```bash
#!/bin/bash
# validate-gunicorn-config.sh

set -euo pipefail

NAMESPACE="your-namespace"
POD_LABEL="app=python-app"

echo "=== Gunicorn 配置验证 ==="

# 1. 获取 Pod 名称
POD_NAME=$(kubectl get pods -n $NAMESPACE -l $POD_LABEL -o jsonpath='{.items[0].metadata.name}')
echo "检查 Pod: $POD_NAME"
echo ""

# 2. 检查环境变量
echo "1. 检查环境变量..."
kubectl exec -n $NAMESPACE $POD_NAME -- env | grep -i gunicorn || echo "未找到 GUNICORN 相关环境变量"
echo ""

# 3. 检查进程
echo "2. 检查 Gunicorn 进程..."
kubectl exec -n $NAMESPACE $POD_NAME -- ps aux | grep gunicorn | grep -v grep
echo ""

# 4. 统计 worker 数量
echo "3. 统计 Worker 数量..."
WORKER_COUNT=$(kubectl exec -n $NAMESPACE $POD_NAME -- ps aux | grep "gunicorn.*worker" | grep -v grep | wc -l)
echo "Worker 数量: $WORKER_COUNT"
echo ""

# 5. 检查配置文件
echo "4. 检查配置文件..."
kubectl exec -n $NAMESPACE $POD_NAME -- cat /opt/conf/gunicorn.conf.py | grep -E "timeout|workers|bind"
echo ""

# 6. 测试超时（如果有测试端点）
echo "5. 测试超时行为..."
SERVICE_URL=$(kubectl get svc -n $NAMESPACE -l $POD_LABEL -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
if [ -n "$SERVICE_URL" ]; then
    echo "测试 35 秒延迟..."
    time curl -s -o /dev/null -w "%{http_code}\n" --max-time 40 "https://$SERVICE_URL/test/timeout/35" || echo "超时或失败"
else
    echo "未找到 Service 外部 IP，跳过超时测试"
fi

echo ""
echo "=== 验证完成 ==="
```

---

## 监控和告警

### Prometheus 指标

```yaml
# prometheus-rules.yaml
groups:
  - name: gunicorn_alerts
    rules:
      - alert: GunicornWorkerTimeout
        expr: rate(gunicorn_worker_timeout_total[5m]) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Gunicorn workers are timing out"
          description: "{{ $value }} workers timed out in the last 5 minutes"
      
      - alert: GunicornWorkerCountMismatch
        expr: gunicorn_workers != 4
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Gunicorn worker count mismatch"
          description: "Expected 4 workers, but found {{ $value }}"
      
      - alert: GunicornHighRequestDuration
        expr: histogram_quantile(0.95, rate(gunicorn_request_duration_seconds_bucket[5m])) > 30
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "95th percentile request duration > 30s"
          description: "Requests are taking {{ $value }}s at 95th percentile"
```

### 日志监控

```bash
# 实时监控超时日志
kubectl logs -n your-namespace -l app=python-app -f | grep -i "timeout\|worker"

# 统计超时频率
kubectl logs -n your-namespace -l app=python-app --tail=10000 | \
    grep "Worker timeout" | wc -l
```

---

## 故障恢复

### 快速回滚

```bash
# 回滚到上一个版本
kubectl rollout undo deployment/python-app -n your-namespace

# 回滚到特定版本
kubectl rollout undo deployment/python-app -n your-namespace --to-revision=2

# 查看回滚历史
kubectl rollout history deployment/python-app -n your-namespace
```

### 紧急修复

```bash
# 临时修改环境变量（不推荐，仅用于紧急情况）
kubectl set env deployment/python-app -n your-namespace \
    GUNICORN_CMD_ARGS="--bind=0.0.0.0:8443 --workers=4 --timeout=0 --keyfile=/certs/key.pem --certfile=/certs/cert.pem"

# 或直接编辑
kubectl edit deployment/python-app -n your-namespace
```

---

## 总结

### 关键要点

1. **环境变量优先级最高**：`GUNICORN_CMD_ARGS` 会覆盖配置文件
2. **缺少参数会使用默认值**：环境变量中未指定的参数不会从配置文件读取
3. **默认 timeout = 30 秒**：这是最常见的超时问题根因
4. **验证实际配置**：不要假设配置文件生效，要验证实际运行参数

### 推荐方案

**生产环境：**
- 使用配置文件管理所有参数
- 通过环境变量覆盖配置文件中的特定值（而非使用 `GUNICORN_CMD_ARGS`）
- 明确设置 `timeout` 参数，避免使用默认值

**开发环境：**
- 可以使用 `GUNICORN_CMD_ARGS` 快速测试
- 但要确保包含所有关键参数

### 预防措施

1. **镜像构建时**：避免在 Dockerfile 中设置 `GUNICORN_CMD_ARGS`
2. **部署时**：使用 ConfigMap 管理配置，而非环境变量
3. **验证时**：部署后立即验证 worker 数量和超时设置
4. **监控时**：设置告警监控超时和 worker 异常

---

## 参考资料

- [Gunicorn Configuration](https://docs.gunicorn.org/en/stable/configure.html)
- [Gunicorn Settings](https://docs.gunicorn.org/en/stable/settings.html)
- [Kubernetes Environment Variables](https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/)
- [gcrane Documentation](https://github.com/google/go-containerregistry/blob/main/cmd/gcrane/README.md)
