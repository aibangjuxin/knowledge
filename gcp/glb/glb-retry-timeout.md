# GCP GLB 多层架构超时与重试机制设计指南

## 1. 架构概述
- https://docs.cloud.google.com/load-balancing/docs/l7-internal#retries
```text
To configure retries, you can use a retry policy in the URL map. The default number of retries (numRetries) is 1. The maximum configurable perTryTimeout is 24 hours.

Without a retry policy, unsuccessful requests that have no HTTP body (for example, GET requests) that result in HTTP 502, 503, or 504 responses are retried once.

HTTP POST requests aren't retried.

Retried requests only generate one log entry for the final response.

For more information, see Internal Application Load Balancer logging and monitoring.
```


你的平台是典型的多层架构，每一层都可能涉及超时和重试配置：

```
Client
  │
  ▼
┌─────────────────────────┐
│  GCP Global Load        │  ← Layer 1: HTTPS Termination
│  Balancer (GLB)         │    - Timeout: 默认 30s，可配置
│  Target HTTPS Proxy     │    - Health Check
└─────────────────────────┘
  │
  ▼
┌─────────────────────────┐
│  Nginx L7 Proxy         │  ← Layer 2: L7 Load Balancing
│  (Upstream / proxy)     │    - proxy_connect_timeout
│  - Kong Ingress         │    - proxy_read_timeout
│                         │    - proxy_send_timeout
└─────────────────────────┘
  │
  ▼
┌─────────────────────────┐
│  Kong API Gateway       │  ← Layer 3: API Gateway
│  - Route / Service      │    - timeout (server/worker)
│  - Plugins              │    - retry
│  - Upstream             │    - health check
└─────────────────────────┘
  │
  ▼
┌─────────────────────────┐
│  GKE Runtime            │  ← Layer 4: Kubernetes
│  (Kong Dataplane/       │    - Readiness/Liveness Probe
│   Kong for K8s)         │    - Service timeout
│                         │    - Pod disruption
└─────────────────────────┘
  │
  ▼
┌─────────────────────────┐
│  Application /          │
│  Backend Service        │  ← Layer 5: 业务逻辑
│                         │    - Application timeout
│                         │    - Circuit breaker
└─────────────────────────┘
```

**关键问题**：如果各层超时/重试配置不一致，会导致：
- 请求在某些层超时后，另一层还在继续处理（资源浪费）
- 重试导致重复请求（幂等性问题）
- 错误链路复杂，难以排查

---

## 2. 各层超时与重试配置详解

### 2.1 GCP Global Load Balancer (Layer 1)

#### 2.1.1 HTTPS Proxy 超时配置

```bash
# 查看当前 Target HTTPS Proxy 配置
gcloud compute target-https-proxies describe YOUR_PROXY_NAME --global

# 创建时设置 timeout（秒）
gcloud compute target-https-proxies create YOUR_PROXY_NAME \
  --url-map=YOUR_URL_MAP \
  --ssl-certificates=YOUR_CERT \
  --timeout=300s  # 默认 30s，最大 86400s
```

| 参数      | 默认值 | 最大值       | 说明                         |
| --------- | ------ | ------------ | ---------------------------- |
| `timeout` | 30s    | 86400s (24h) | 等待后端响应或保持连接的时间 |

#### 2.1.2 Health Check 超时

```bash
# 创建健康检查
gcloud compute health-checks create https YOUR_HEALTH_CHECK \
  --port=443 \
  --request-path=/healthz \
  --check-interval=10s \
  --timeout=5s \
  --healthy-threshold=2 \
  --unhealthy-threshold=3
```

| 参数                  | 说明                                        |
| --------------------- | ------------------------------------------- |
| `check-interval`      | 两次检查之间的间隔                          |
| `timeout`             | 单次健康检查的超时（应小于 check-interval） |
| `healthy-threshold`   | 连续成功次数才认为健康                      |
| `unhealthy-threshold` | 连续失败次数才认为不健康                    |

#### 2.1.3 GLB 重试机制

**GCP GLB 不会自动重试失败的请求**。重试需要你在后端自行实现。

```bash
# 注意：GLB 不会 retry，但会保持连接池
# 如果需要重试，必须在应用层或 Nginx 层实现
```

#### 2.1.4 GLB 超时配置建议

```bash
# 对于长时间运行的请求（如文件上传/下载）
gcloud compute target-https-proxies update YOUR_PROXY_NAME \
  --timeout=600s \
  --global
```

---

### 2.2 Nginx L7 Proxy (Layer 2)

#### 2.2.1 主要超时参数

```nginx
# /etc/nginx/nginx.conf 或对应的 upstream 块

upstream backend_kong {
    server kong-backend:8000;
    keepalive 64;
}

server {
    listen 8443 ssl;
    
    # 连接超时（与后端建立连接的时间）
    proxy_connect_timeout 60s;
    
    # 读取超时（等待后端发送响应的时间）
    proxy_read_timeout 300s;
    
    # 发送超时（发送请求到后端的时间）
    proxy_send_timeout 300s;
    
    # Buffer 配置
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;
}
```

| 参数                    | 默认值 | 说明           | 推荐值        |
| ----------------------- | ------ | -------------- | ------------- |
| `proxy_connect_timeout` | 60s    | 与后端建立连接 | 5-10s（生产） |
| `proxy_read_timeout`    | 60s    | 等待后端响应   | 依据业务逻辑  |
| `proxy_send_timeout`    | 60s    | 发送请求到后端 | 60s           |

#### 2.2.2 Nginx 重试机制

```nginx
# 当后端返回特定错误码时，Nginx 会自动重试
proxy_next_upstream error timeout http_502 http_503 http_504;
proxy_next_upstream_tries 3;
proxy_next_upstream_timeout 10s;

# 重要：确保操作是幂等的，否则可能产生重复提交
```

#### 2.2.3 Nginx 限流与排队

```nginx
# 限流配置
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/s;

location /api/ {
    # 排队队列（超过 rate 的请求排队）
    limit_req zone=api_limit burst=20 nodelay;
    
    # 超时传递
    proxy_read_timeout 300s;
}
```

---

### 2.3 Kong API Gateway (Layer 3)

#### 2.3.1 Kong Timeout 配置

Kong 的超时配置在 `kong.conf` 或通过 Admin API 设置：

```bash
# 通过 Admin API 查看当前配置
curl -i http://localhost:8001/

# 设置 service/upstream 超时（毫秒）
curl -X PATCH http://localhost:8001/services/SERVICE_NAME \
  --data "connect_timeout=60000" \
  --data "send_timeout=60000" \
  --data "read_timeout=600000"
```

| 参数              | 默认值   | 说明     | 单位 |
| ----------------- | -------- | -------- | ---- |
| `connect_timeout` | 60000ms  | 连接超时 | 毫秒 |
| `send_timeout`    | 60000ms  | 发送超时 | 毫秒 |
| `read_timeout`    | 600000ms | 读取超时 | 毫秒 |

#### 2.3.2 Kong Retry 配置

```bash
# 在 service 或 route 上启用重试
curl -X PATCH http://localhost:8001/services/SERVICE_NAME \
  --data "retries=3"
```

| 参数      | 默认值 | 说明           |
| --------- | ------ | -------------- |
| `retries` | 5      | 失败时重试次数 |

**Kong 重试条件**（默认）：
- Connection timeout
- Read timeout
- HTTP 502 / 503 / 504

**注意**：Kong 不会重试 `POST`、`PUT`、`PATCH` 请求，除非配置 `retries` 且请求未被发送（connection error）。

#### 2.3.3 Kong Health Check

```bash
# 创建 upstream 健康检查
curl -X POST http://localhost:8001/upstreams/backup-backend/targets \
  --data "target=backend:8000" \
  --data "weight=100"

# 配置主动健康检查
curl -X POST http://localhost:8001/upstreams/backup-backend/health-checks \
  --data "type=http" \
  --data "http_path=/healthz" \
  --data "interval=10" \
  --data "timeout=5" \
  --data "consecutive_successes=3" \
  --data "consecutive_failures=3"
```

#### 2.3.4 Kong 插件超时配置

如果使用 Prometheus 或其他监控插件，可能需要调整：

```bash
# 禁用超时用于长时间运行的请求
curl -X POST http://localhost:8001/routes/ROUTE_NAME/plugins \
  --data "name=prometheus" \
  --data "config.timeout=60000"
```

---

### 2.4 GKE Runtime (Layer 4)

#### 2.4.1 Kubernetes Service Timeout

```yaml
# Service spec
apiVersion: v1
kind: Service
metadata:
  name: my-app
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800  # GKE 默认 10800s (3小时)
  ports:
  - port: 80
    targetPort: 8080
```

#### 2.4.2 Readiness vs Liveness Probe

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: my-app
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /live
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
```

| Probe 类型      | 用途                   | 超时建议         |
| --------------- | ---------------------- | ---------------- |
| Readiness Probe | 流量是否应该发送到 Pod | 略短于业务超时   |
| Liveness Probe  | Pod 是否需要重启       | 保守值，避免误杀 |

#### 2.4.3 Pod Disruption Budget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2
  # 或使用 maxUnavailable
```

#### 2.4.4 GKE Ingress 超时

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    kubernetes.io/ingress.global-static-ip-name: "my-ip"
    networking.gke.io/ingress-class: "gce"
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /*
        pathType: ImplementationSpecific
        backend:
          service:
            name: my-app
            port:
              number: 80
```

GKE Ingress 的默认超时是 30s，可通过 annotation 修改：

```yaml
annotations:
  kubernetes.io/ingress.global-static-ip-name: "my-ip"
  networking.gke.io/ingress.class: "gce"
  cloud.google.com/backend-config: '{"default": "my-backend-config"}'
```

```yaml
# BackendConfig for custom timeout
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: my-backend-config
spec:
  timeoutSec: 300
  connectionDraining:
    drainingTimeoutSec: 60
```

---

## 3. 超时与重试的评估框架

### 3.1 是否需要超时机制？

**必须使用超时的场景**：

| 场景          | 原因                   | 风险            |
| ------------- | ---------------------- | --------------- |
| 外部 API 调用 | 对方可能无响应或响应慢 | 线程/连接池耗尽 |
| 数据库查询    | 慢查询可能永远不返回   | 请求堆积        |
| 文件处理      | 大文件上传/下载        | 占用资源        |
| 批量操作      | 可能耗时很长           | 无法预估        |

**可以考虑不设置超时的场景**：

| 场景         | 说明           | 风险       |
| ------------ | -------------- | ---------- |
| 简单同步查询 | 预期毫秒级响应 | 风险低     |
| 内部服务调用 | 网络稳定       | 仍建议设置 |

### 3.2 是否需要重试机制？

**需要重试的场景**：

| 场景             | 重试价值 | 注意事项      |
| ---------------- | -------- | ------------- |
| 瞬时网络抖动     | 高       | 快速失败+重试 |
| 依赖服务偶发故障 | 高       | 指数退避      |
| 读取操作         | 高       | 天然幂等      |
| 健康检查         | 高       | 快速恢复      |

**不应该重试的场景**：

| 场景               | 原因                     | 替代方案          |
| ------------------ | ------------------------ | ----------------- |
| 写操作（无幂等性） | 可能产生重复数据         | 唯一键 + 事后清理 |
| 支付/转账          | 资金风险                 | 人工介入          |
| 删除操作           | 重复删除无害但可能不期望 | 幂等性设计        |
| 已经超时的请求     | 可能已经在处理           | 状态查询          |

### 3.3 风险评估表

| 风险       | 场景           | 影响         | 缓解措施     |
| ---------- | -------------- | ------------ | ------------ |
| 重试风暴   | 多层重试叠加   | 服务雪崩     | 全局重试限制 |
| 重复提交   | 非幂等操作重试 | 数据不一致   | 幂等性设计   |
| 资源泄露   | 超时设置过长   | OOM/连接耗尽 | 合理超时     |
| 链路断裂   | 超时过短       | 误判健康服务 | 渐进式超时   |
| 状态不一致 | 各层超时不一致 | 排查困难     | 统一配置     |

---

## 4. 最佳实践

### 4.1 超时配置原则

#### 4.1.1 超时链路的"大漏斗"原则

```
Client → GLB → Nginx → Kong → GKE → App
  │      │      │      │     │     │
  │      │      │      │     │     └── 应用处理时间 (P99)
  │      │      │      │     └──────── GKE Service timeout
  │      │      │      └────────────── Kong timeout
  │      │      └───────────────────── Nginx proxy_read_timeout
  │      └──────────────────────────── GLB timeout
  └────────────────────────────────── Client timeout (浏览器通常 30-120s)
```

**原则**：每层超时应该**从外到内递增**或**至少相等**，确保请求不会被过早中断。

**计算公式**：
```
Client_timeout >= GLB_timeout >= Nginx_timeout >= Kong_timeout >= GKE_timeout >= App_timeout
```

#### 4.1.2 推荐超时配置组合

| 层级   | 短任务 | 中等任务 | 长任务 |
| ------ | ------ | -------- | ------ |
| Client | 30s    | 60s      | 300s   |
| GLB    | 60s    | 120s     | 600s   |
| Nginx  | 90s    | 180s     | 600s   |
| Kong   | 120s   | 240s     | 600s   |
| GKE    | 150s   | 300s     | 600s   |
| App    | 180s   | 360s     | 600s   |

#### 4.1.3 渐进式超时示例

```nginx
# Nginx 配置
proxy_read_timeout 300s;  # 5 分钟

# Kong Service
# read_timeout = 300000ms

# GKE Service
# timeoutSec = 300
```

### 4.2 重试配置原则

#### 4.2.1 指数退避

```bash
# Kong 重试配置（指数退避）
curl -X PATCH http://localhost:8001/services/SERVICE_NAME \
  --data "retries=3"

# 自定义退避需要在应用层实现
```

```python
# Python 示例：指数退避重试
import time
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

session = requests.Session()
retry_strategy = Retry(
    total=3,
    backoff_factor=1,  # 1s, 2s, 4s (指数退避)
    status_forcelist=[500, 502, 503, 504],
    allowed_methods=["GET", "HEAD"]  # 只重试安全方法
)
adapter = HTTPAdapter(max_retries=retry_strategy)
session.mount("http://", adapter)
```

#### 4.2.2 重试次数限制

| 场景           | 推荐重试次数 | 说明       |
| -------------- | ------------ | ---------- |
| 读取操作       | 2-3          | 幂等       |
| 写操作（幂等） | 1-2          | 需确保幂等 |
| 健康检查       | 1            | 快速感知   |
| 外部支付       | 0            | 禁止重试   |

#### 4.2.3 重试与幂等性

**幂等性设计模式**：

```bash
# 使用 Idempotency Key
curl -X POST https://api.example.com/payments \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{"amount": 100, "currency": "USD"}'
```

```python
# 应用层幂等检查
import hashlib

def make_idempotent_request(request_id, payload):
    # 检查是否已经处理过
    cache_key = f"processed:{request_id}"
    if redis.exists(cache_key):
        return redis.get(cache_key)
    
    # 处理请求
    result = process_payment(payload)
    
    # 标记为已处理
    redis.setex(cache_key, 86400, json.dumps(result))
    return result
```

### 4.3 健康检查最佳实践

#### 4.3.1 分层健康检查

| 层级          | 检查内容    | 检查路径   | 超时 |
| ------------- | ----------- | ---------- | ---- |
| GLB           | 端口 + 路径 | `/healthz` | 5s   |
| Nginx         | 端口        | -          | 2s   |
| Kong          | `/status`   | `/status`  | 1s   |
| GKE Readiness | 业务接口    | `/ready`   | 5s   |
| GKE Liveness  | 存活判断    | `/live`    | 3s   |

#### 4.3.2 健康检查实现

```python
# Python: 健康检查端点
from flask import Flask, jsonify
import requests

app = Flask(__name__)

@app.route('/healthz')
def healthz():
    return jsonify({"status": "ok"})

@app.route('/ready')
def ready():
    try:
        # 检查依赖服务
        requests.get('http://db:5432/healthz', timeout=2)
        return jsonify({"status": "ready"})
    except Exception as e:
        return jsonify({"status": "not_ready", "error": str(e)}), 503

@app.route('/live')
def live():
    return jsonify({"status": "alive"})
```

### 4.4 错误处理与熔断

#### 4.4.1 熔断模式

```python
# Python: 简单熔断实现
class CircuitBreaker:
    def __init__(self, failure_threshold=5, timeout=60):
        self.failure_count = 0
        self.failure_threshold = failure_threshold
        self.timeout = timeout
        self.last_failure_time = None
        self.state = "closed"  # closed, open, half-open
    
    def call(self, func, *args, **kwargs):
        if self.state == "open":
            if time.time() - self.last_failure_time > self.timeout:
                self.state = "half-open"
            else:
                raise CircuitOpenError()
        
        try:
            result = func(*args, **kwargs)
            if self.state == "half-open":
                self.state = "closed"
                self.failure_count = 0
            return result
        except Exception as e:
            self.failure_count += 1
            self.last_failure_time = time.time()
            if self.failure_count >= self.failure_threshold:
                self.state = "open"
            raise
```

#### 4.4.2 错误码处理策略

| 错误码      | 含义       | 处理策略           |
| ----------- | ---------- | ------------------ |
| 400         | 请求错误   | 不重试，修复请求   |
| 401         | 认证失败   | 不重试，刷新 token |
| 403         | 权限不足   | 不重试             |
| 404         | 资源不存在 | 不重试             |
| 429         | 限流       | 退避后重试         |
| 500         | 服务器错误 | 重试               |
| 502/503/504 | 网关错误   | 重试               |
| 599         | 连接超时   | 重试               |

---

## 5. 统一配置模板

### 5.1 超时配置清单

```
┌─────────────────────────────────────────────────────────────┐
│                    超时配置核对表                             │
├─────────────────────────────────────────────────────────────┤
│ GLB (GCP)                                                   │
│   Target HTTPS Proxy timeout: ______s (推荐: 300s)           │
│   Health check timeout: ______s (推荐: 5s)                  │
├─────────────────────────────────────────────────────────────┤
│ Nginx                                                       │
│   proxy_connect_timeout: ______s (推荐: 10s)                │
│   proxy_read_timeout: ______s (推荐: 300s)                  │
│   proxy_send_timeout: ______s (推荐: 60s)                   │
├─────────────────────────────────────────────────────────────┤
│ Kong                                                        │
│   connect_timeout: ______ms (推荐: 60000ms)                 │
│   send_timeout: ______ms (推荐: 60000ms)                    │
│   read_timeout: ______ms (推荐: 300000ms)                   │
│   retries: ______ (推荐: 3)                                 │
├─────────────────────────────────────────────────────────────┤
│ GKE                                                         │
│   Service timeoutSec: ______ (推荐: 300)                    │
│   Readiness probe timeoutSeconds: ______ (推荐: 5)          │
│   Liveness probe timeoutSeconds: ______ (推荐: 3)           │
├─────────────────────────────────────────────────────────────┤
│ Application                                                 │
│   HTTP client timeout: ______s (推荐: 300s)                 │
│   Database query timeout: ______s (推荐: 30s)               │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 配置验证命令

```bash
# 1. 检查 GLB Proxy 超时
gcloud compute target-https-proxies describe YOUR_PROXY --global --format="get(timeout)"

# 2. 检查 Nginx 超时（查看配置文件）
grep -E "proxy_(connect|read|send)_timeout" /etc/nginx/nginx.conf

# 3. 检查 Kong 超时（Admin API）
curl http://localhost:8001/services/SERVICE_NAME | jq '.read_timeout'

# 4. 检查 GKE Service 超时
kubectl get svc my-app -o jsonpath='{.spec.timeoutSeconds}'

# 5. 端到端测试
time curl -I -w "\nTotal: %{time_total}s\n" https://api.example.com/healthz
```

---

## 6. 故障排查指南

### 6.1 常见超时问题

| 症状                | 可能原因          | 排查命令             |
| ------------------- | ----------------- | -------------------- |
| 504 Gateway Timeout | 某层超时设置过短  | 检查各层 timeout     |
| 连接被重置          | 后端无响应        | 检查后端服务状态     |
| 间歇性超时          | 资源不足/GC       | 查看监控             |
| 健康检查失败        | 探针路径/超时问题 | kubectl describe pod |

### 6.2 常见重试问题

| 症状     | 可能原因       | 排查命令     |
| -------- | -------------- | ------------ |
| 重复数据 | 非幂等操作重试 | 检查重试日志 |
| 雪崩效应 | 重试过于激进   | 限流+退避    |
| 资源耗尽 | 大量重试堆积   | 连接池监控   |

### 6.3 排查流程

```
1. 确定超时发生的层级
   - 客户端返回什么错误？
   - GLB/Nginx/Kong 日志在哪？

2. 检查该层的超时配置
   - 是否设置合理？
   - 是否被覆盖？

3. 检查下游服务
   - 是否响应慢？
   - 是否有错误？

4. 验证链路
   - curl 测试各层
   - 逐步定位问题
```

```bash
# 端到端延迟测试
echo "=== Client ===" && time curl -w "\n" https://api.example.com/slow-api

echo "=== GLB → Nginx ===" && time curl -I http://nginx:8443/slow-api

echo "=== Nginx → Kong ===" && time curl -I http://kong:8000/slow-api

echo "=== Kong → Backend ===" && time curl -I http://backend:8080/slow-api
```

---

## 7. 总结

### 7.1 核心原则

1. **超时链路递增**：从外到内，每层超时应相等或递增
2. **重试有限制**：限制重试次数 + 指数退避
3. **幂等性优先**：写操作必须保证幂等才能重试
4. **健康检查分层**：每层都需要独立的健康检查
5. **可观测性**：日志、指标、链路追踪

### 7.2 快速检查清单

- [ ] 各层超时配置已记录
- [ ] 超时链路符合递增原则
- [ ] 重试使用指数退避
- [ ] 非幂等操作已标识，不重试
- [ ] 健康检查已配置并验证
- [ ] 熔断机制已实现
- [ ] 监控告警已设置
- [ ] 文档已更新

### 7.3 推荐阅读

- [GCP Load Balancer Timeout](https://cloud.google.com/load-balancing/docs/https#timeouts_and_retries)
- [Nginx ngx_http_proxy_module](http://nginx.org/en/docs/http/ngx_http_proxy_module.html)
- [Kong Configuration Reference](https://docs.konghq.com/gateway/latest/reference/configuration/)
- [Kubernetes Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)



### 7.4 retries

你说得非常对！GCP **Internal HTTP(S) Load Balancer**（内部负载均衡器）确实有一个我之前文档中遗漏的重要重试机制，而且它的行为与 External GLB 有显著差异。让我为你深入探索这一部分。

---

#### GCP Internal HTTP(S) Load Balancer 重试机制深度解析

##### 一、核心机制概览

GCP Internal HTTP(S) Load Balancer 的重试策略是在 **URL Map 的 Route Rules 层级**配置的，这与 External GLB 的隐式/有限重试行为完全不同 。

```
┌─────────────────────────────────────────────────────────────────────────────┐
│           GCP Internal HTTP(S) LB 重试机制（URL Map Route Rules）            │
└─────────────────────────────────────────────────────────────────────────────┘

【默认行为】（未配置 retryPolicy 时）：
  • numRetries: 1（默认重试1次）
  • 仅对无 HTTP body 的请求 → 即 GET 请求
  • 仅在返回 502、503、504 时触发
  • HTTP POST 请求永远不会被重试
  • 重试请求只生成一条日志（最终响应）

【自定义行为】（通过 retryPolicy 配置）：
  • numRetries: 可配置
  • perTryTimeout: 最大可配置 24 小时（86400 秒）
  • retryConditions: 多种条件可选
  • 可按路径精细控制
```

---

##### 二、与 External GLB 的关键差异

| 特性                | External GLB | Internal HTTP(S) LB        |
| ------------------- | ------------ | -------------------------- |
| **Retry Policy**    | 几乎无/隐式  | 完整的 URL Map retryPolicy |
| **可配置性**        | 不可配置     | 通过 routeRules 完全配置   |
| **默认 numRetries** | 1（隐式）    | 1（显式默认值）            |
| **perTryTimeout**   | 无此概念     | 最大 24 小时               |
| **POST 重试**       | 绝不         | 可配置（但极其危险）       |
| **重试目标**        | 任意健康后端 | **不同 VM**（已验证）      |

---

##### 三、Retry Conditions 详解

Internal LB 支持以下重试条件 ：

| 条件              | 含义               | 安全建议           |
| ----------------- | ------------------ | ------------------ |
| `5xx`             | 任意 5xx 状态码    | ⚠️ 范围太宽，慎用   |
| `gateway-error`   | 502、503、504      | ✅ 最安全的默认选项 |
| `connect-failure` | 无法建立连接       | ✅ 几乎总是安全     |
| `reset`           | 响应头前连接重置   | ✅ 对幂等请求安全   |
| `refused-stream`  | HTTP/2 stream 拒绝 | ✅ gRPC 场景适用    |
| `retriable-4xx`   | 409 Conflict       | ⚠️ 仅应用支持时启用 |

---

##### 四、Timeout 交互模型（Critical!）

这是最容易出错的部分。Internal LB 涉及 **三个不同层级的超时** ：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         超时交互层级                                         │
└─────────────────────────────────────────────────────────────────────────────┘

  Client Request
       │
       ▼
  ┌──────────────────────────────┐
  │  Route Timeout (URL Map)     │  ← 包含所有重试的总超时
  │  例如：35 秒                  │
  │                              │
  │  ┌────────────────────────┐  │
  │  │ Attempt 1              │  │
  │  │ perTryTimeout: 10s     │  │  ← 单次尝试超时
  │  │ ──────► 失败/超时       │  │
  │  └────────────────────────┘  │
  │           │                  │
  │           ▼ 重试             │
  │  ┌────────────────────────┐  │
  │  │ Attempt 2              │  │
  │  │ perTryTimeout: 10s     │  │
  │  │ ──────► 失败/超时       │  │
  │  └────────────────────────┘  │
  │           │                  │
  │           ▼ 重试             │
  │  ┌────────────────────────┐  │
  │  │ Attempt 3 (final)      │  │
  │  │ perTryTimeout: 10s     │  │
  │  │ ──────► 成功/失败       │  │
  │  └────────────────────────┘  │
  │                              │
  └──────────────────────────────┘
       │
       ▼
  ┌──────────────────────────────┐
  │ Backend Service Timeout      │  ← 最终兜底上限
  │ 例如：300 秒                  │
  │ 如果超过 → 504 Gateway Timeout│
  └──────────────────────────────┘
```

**关键公式**：
```
Route Timeout ≥ (numRetries + 1) × perTryTimeout + backoff_buffer

必须满足：
perTryTimeout < Backend Service Timeout
```

---

##### 五、完整架构中的位置与配置

### 5.1 更新后的四层架构

```
    Client
      │
      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ ① GCP Internal HTTP(S) LB                                                   │
│    ┌─────────────────────────────────────────────────────────────────────┐  │
│    │ URL Map Route Rules                                                 │  │
│    │  • retryPolicy:                                                     │  │
│    │    - numRetries: 1~2（保守）                                         │  │
│    │    - perTryTimeout: 10s（读API）                                    │  │
│    │    - retryConditions: ["gateway-error", "connect-failure"]          │  │
│    │  • route timeout: 35s（包含重试）                                    │  │
│    │                                                                     │  │
│    │ 写操作路径：无 retryPolicy（POST 默认不重试）                         │  │
│    │ 长耗时路径：无 retryPolicy，timeout: 290s                           │  │
│    └─────────────────────────────────────────────────────────────────────┘  │
│    Backend Service timeout: 300s                                            │
└─────────────────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ ② Nginx L7 (反向代理)                                                        │
│    • proxy_connect_timeout: 5s                                              │
│    • proxy_read_timeout: 290s  (< Backend Service timeout)                  │
│    • proxy_send_timeout: 60s                                                │
│    • proxy_next_upstream_tries: 2                                           │
│    • 非幂等方法不重试                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ ③ Kong (API Gateway)                                                        │
│    • connect_timeout: 5000ms                                                │
│    • write_timeout: 60000ms                                                 │
│    • read_timeout: 280000ms  (< Nginx read_timeout)                         │
│    • retries: 2                                                             │
│    • 仅幂等方法重试                                                           │
└─────────────────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ ④ GKE Runtime (K8s Pods)                                                    │
│    • Server timeout: 275s                                                   │
│    • Business logic timeout: 270s                                           │
│    • DB query timeout: 30s                                                  │
│    • External API timeout: 20s                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 gcloud 配置示例

```bash
# 导出当前 URL Map
gcloud compute url-maps export my-internal-url-map \
    --region=us-central1 \
    --destination=/tmp/urlmap.yaml

# 编辑后重新导入
gcloud compute url-maps import my-internal-url-map \
    --region=us-central1 \
    --source=/tmp/urlmap.yaml
```

```yaml
# urlmap.yaml
defaultService: projects/my-project/regions/us-central1/backendServices/my-backend

hostRules:
- hosts:
  - "api.internal.example.com"
  pathMatcher: api-matcher

pathMatchers:
- name: api-matcher
  defaultService: projects/my-project/regions/us-central1/backendServices/my-backend
  
  routeRules:
  
  # ═══════════════════════════════════════════════════════
  # 规则1: 读操作 API — 安全重试
  # ═══════════════════════════════════════════════════════
  - priority: 100
    matchRules:
    - prefixMatch: /api/v1/read/
    routeAction:
      retryPolicy:
        retryConditions:
        - "gateway-error"      # 502, 503, 504
        - "connect-failure"    # 连接失败
        - "reset"              # 连接重置
        numRetries: 2           # 最多重试2次（共3次尝试）
        perTryTimeout:
          seconds: 10           # 每次尝试10秒
      timeout:
        seconds: 35             # 总超时35秒（3×10 + 5秒缓冲）
      weightedBackendServices:
      - backendService: projects/my-project/regions/us-central1/backendServices/my-backend
        weight: 100

  # ═══════════════════════════════════════════════════════
  # 规则2: 写操作 API — 显式关闭重试
  # ═══════════════════════════════════════════════════════
  - priority: 200
    matchRules:
    - prefixMatch: /api/v1/write/
    routeAction:
      # 不配置 retryPolicy = 不重试
      # POST 默认也不重试，双重保险
      timeout:
        seconds: 30
      weightedBackendServices:
      - backendService: projects/my-project/regions/us-central1/backendServices/my-backend
        weight: 100

  # ═══════════════════════════════════════════════════════
  # 规则3: 长耗时任务 — 超长超时，无重试
  # ═══════════════════════════════════════════════════════
  - priority: 300
    matchRules:
    - prefixMatch: /api/v1/jobs/
    routeAction:
      timeout:
        seconds: 290            # 接近上限，给Nginx留10秒缓冲
      weightedBackendServices:
      - backendService: projects/my-project/regions/us-central1/backendServices/my-backend
        weight: 100
```

### 5.3 Terraform 配置

```hcl
resource "google_compute_region_url_map" "internal_lb" {
  name            = "my-internal-url-map"
  region          = "us-central1"
  default_service = google_compute_region_backend_service.default.id

  host_rule {
    hosts        = ["api.internal.example.com"]
    path_matcher = "api-matcher"
  }

  path_matcher {
    name            = "api-matcher"
    default_service = google_compute_region_backend_service.default.id

    # 读操作 - 安全重试
    route_rules {
      priority = 100
      match_rules {
        prefix_match = "/api/v1/read/"
      }
      route_action {
        retry_policy {
          retry_conditions = ["gateway-error", "connect-failure", "reset"]
          num_retries      = 2
          per_try_timeout {
            seconds = 10
          }
        }
        timeout {
          seconds = 35
        }
        weighted_backend_services {
          backend_service = google_compute_region_backend_service.default.id
          weight          = 100
        }
      }
    }

    # 写操作 - 不重试
    route_rules {
      priority = 200
      match_rules {
        prefix_match = "/api/v1/write/"
      }
      route_action {
        timeout {
          seconds = 30
        }
        weighted_backend_services {
          backend_service = google_compute_region_backend_service.default.id
          weight          = 100
        }
      }
    }
  }
}

resource "google_compute_region_backend_service" "default" {
  name                  = "my-backend-service"
  region                = "us-central1"
  protocol              = "HTTP"
  timeout_sec           = 300
  connection_draining_timeout_sec = 300

  backend {
    group = google_compute_region_instance_group_manager.default.instance_group
  }

  health_checks = [google_compute_region_health_check.default.id]
}
```

---

##### 六、Critical Warnings（关键警告）

### ⚠️ 1. 重试放大效应（Retry Amplification）

如果每一层都配置重试，会产生**乘法效应**：

```
Internal LB: numRetries=2  → 最多 3 次尝试
     ↓
Nginx: proxy_next_upstream_tries=2  → 最多 3 次尝试
     ↓
Kong: retries=2  → 最多 3 次尝试

最坏情况：3 × 3 × 3 = 27 个后端请求！
```

**建议**：将 Internal LB 的 numRetries 控制在 **1**（最多2次尝试），让 Nginx 和 Kong 主要负责重试。

### ⚠️ 2. POST 请求重试风险

虽然 Internal LB 默认不会重试 POST，但如果你通过 `retryPolicy` 显式配置了包含 POST 路径的规则，**可能导致重复写入**。

**必须**：为写操作路径单独创建 routeRule，**不配置 retryPolicy**。

### ⚠️ 3. 日志追踪陷阱

> "Retried requests only generate one log entry for the final response"

重试的中间请求**不会生成独立日志**！如果最终成功，你只看到一条 200 日志，看不到之前的 503 失败。

**解决方案**：在各层启用分布式追踪（OpenTelemetry/Zipkin），并在 Nginx 注入唯一请求 ID：

```nginx
map $http_x_request_id $req_id {
    default   $http_x_request_id;
    ""        $request_id;  # Nginx 生成的唯一ID
}
proxy_set_header X-Request-ID $req_id;
proxy_set_header X-B3-TraceId $req_id;
```

### ⚠️ 4. 重试目标确认

根据 StackOverflow 验证 ，Internal LB 的重试会路由到**不同的 VM**，而非同一实例。这是好的设计，但需要确保后端实例池足够大：
```
最小实例数 > numRetries + 1
```

---

##### 七、故障排查速查表

| 现象                         | 根因                                       | 排查方法                             |
| ---------------------------- | ------------------------------------------ | ------------------------------------ |
| 间歇性 502，后端日志显示成功 | LB 重试到了健康实例                        | 检查 Cloud Logging `statusDetails`   |
| POST 被重试了                | URL Map 配置了过于宽泛的 retryPolicy       | 检查写操作路径的 routeRule           |
| 重试未触发，直接 504         | `perTryTimeout >= Backend Service Timeout` | 确保 perTryTimeout < Backend Timeout |
| 重试风暴导致雪崩             | 各层重试次数乘积过大                       | 监控重试率，设置 >5% 告警            |
| 无法追踪重试链路             | LB 不生成中间日志                          | 启用 OpenTelemetry 分布式追踪        |

---

##### 八、监控告警

```bash
# 高重试率告警
gcloud alpha monitoring policies create \
  --display-name="Internal LB High Retry Rate" \
  --condition-display-name="Retry rate > 5%" \
  --condition-filter='
    resource.type="internal_http_lb_rule"
    AND metric.type="loadbalancing.googleapis.com/internal/request_count"
    AND metric.labels.response_code_class="5xx"
  ' \
  --condition-comparison=COMPARISON_GT \
  --condition-threshold-value=0.05 \
  --condition-duration=300s
```

---

##### 九、最终检查清单

```
□ perTryTimeout < Backend Service Timeout
□ Route Timeout >= (numRetries + 1) × perTryTimeout + 缓冲
□ POST/PUT/PATCH/DELETE 路径无 retryPolicy
□ numRetries 保守（建议1）
□ 后端实例数 > numRetries + 1
□ 各层超时：LB > Nginx > Kong > App
□ 启用分布式追踪
□ 配置重试率监控告警
□ 压力测试验证重试行为
```

---

##### 十、numRetries 配置必要性评估

**核心问题**：`numRetries` 是否必须配置？不配置有什么坏处？

###### 10.1 不配置 numRetries（使用默认行为）

**默认行为**（未显式配置 retryPolicy 时）：

| 特性 | 行为 |
| ---- | ---- |
| `numRetries` | 默认值 1（自动重试1次） |
| 触发条件 | 仅 GET 请求（无 HTTP body） |
| 错误码 | 仅 502、503、504 |
| POST 重试 | **绝不重试** |
| 日志 | 只生成一条最终响应日志 |

**不配置的坏处**：

| 风险 | 说明 |
| ---- | ---- |
| **重试行为不可预测** | 依赖默认隐式行为，难以追踪 |
| **perTryTimeout 缺失** | 使用后端服务的 timeoutSec，可能不是期望值 |
| **日志追踪困难** | "重试请求只生成一条日志"，无法区分首次成功还是重试成功 |
| **错误处理不精细** | 无法按路径定制重试条件 |

###### 10.2 配置 numRetries（显式配置 retryPolicy）

**显式配置的好处**：

| 收益 | 说明 |
| ---- | ---- |
| **精确控制重试次数** | numRetries=1 表示最多 2 次尝试（1 次重试） |
| **自定义 perTryTimeout** | 每次尝试的超时独立控制（最大 24h） |
| **精细化 retryConditions** | 按场景选择 gateway-error、connect-failure 等 |
| **路径级别控制** | 不同 API 路径可有不同重试策略 |
| **可预测性** | 配置即文档，团队行为一致 |

**显式配置的坏处/风险**：

| 风险 | 说明 |
| ---- | ---- |
| **配置复杂度增加** | 需要维护 URL Map 的 routeRules |
| **重试放大效应** | 如果 Nginx/Kong 也配置重试，可能产生 3×3×3=27 次请求 |
| **POST 意外重试** | 如果配置不当，可能导致非幂等操作重复执行 |
| **超时计算复杂** | Route Timeout = (numRetries + 1) × perTryTimeout，需精确计算 |

###### 10.3 评估决策表

| 场景 | 推荐配置 | 原因 |
| ---- | -------- | ---- |
| **读操作 API**（GET，幂等） | `numRetries: 1-2` + `retryConditions: ["gateway-error", "connect-failure"]` | 提升瞬态故障的可靠性 |
| **写操作 API**（POST/PUT/PATCH） | **不配置 retryPolicy** 或 `numRetries: 0` | 防止重复提交，除非有幂等性保护 |
| **长耗时任务**（批处理、导出） | **不配置 retryPolicy**，使用独立的 `timeout: 290s` | 重试可能导致更大问题 |
| **健康检查/探活** | `numRetries: 0` | 快速感知，无需重试 |
| **高价值交易**（支付、转账） | **不配置 retryPolicy** | 必须人工确认或使用分布式事务 |

###### 10.4 numRetries 配置建议值

| 应用场景 | numRetries | perTryTimeout | retryConditions |
| -------- | ---------- | ------------- | ----------------- |
| **普通读 API** | 1 | 10s | gateway-error, connect-failure |
| **高性能读 API** | 0 | - | 不重试，快速失败 |
| **文件/媒体处理** | 0 | - | 不重试，避免资源浪费 |
| **与下游服务通信** | 1-2 | 5s | connect-failure, reset |
| **gRPC 服务** | 1 | 5s | refused-stream, connect-failure |

**保守建议**：对于大多数场景，`numRetries: 1` 是最安全的选择：
- 提供一次重试机会提升可靠性
- 避免过多重试导致雪崩
- 与 Nginx/Kong 的重试机制叠加后不会过于激进

###### 10.5 不配置 vs 配置 对比

| 维度 | 不配置（默认） | 显式配置 |
| ---- | ------------- | -------- |
| **重试次数** | 隐式 1 次 | 显式控制 (0-10) |
| **超时控制** | 使用 Backend Service timeoutSec | 独立 perTryTimeout，最大 24h |
| **触发条件** | 仅 GET + 502/503/504 | 可完全自定义 |
| **路径控制** | 无（全局影响） | 按 routeRules 精细控制 |
| **运维复杂度** | 低 | 中 |
| **可预测性** | 低（隐式行为） | 高（配置即文档） |

---

如果你使用的是 **Global External Application Load Balancer** 而非 Internal LB，重试策略的行为又会有所不同（Global External 现在也支持通过 URL Map 配置 retryPolicy ）。


# 多层架构超时与重试机制全链路指南

## GCP GLB → Nginx → Kong → GKE Runtime

---

## 一、整体架构与超时/重试链路概览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           客户端请求流向                                      │
└─────────────────────────────────────────────────────────────────────────────┘

    Client
      │
      ▼
┌─────────────┐    timeout: 300s (backend)    ┌─────────────┐
│  GCP GLB    │ ─────────────────────────────▶│  Nginx L7   │
│  (HTTPS)    │    retry: 默认不开启            │  (反向代理)  │
│             │                               │             │
│ • 连接超时   │                               │ • proxy_    │
│ • 响应超时   │                               │   connect_  │
│ • 健康检查   │                               │   timeout   │
│             │                               │ • proxy_    │
│             │                               │   read_     │
│             │                               │   timeout   │
│             │                               │ • proxy_    │
│             │                               │   send_     │
│             │                               │   timeout   │
└─────────────┘                               └──────┬──────┘
                                                     │
                                                     ▼
                                            ┌─────────────┐
                                            │    Kong     │
                                            │ (API Gateway)│
                                            │             │
                                            │ • upstream  │
                                            │   timeout   │
                                            │ • retries   │
                                            │ • connect_  │
                                            │   timeout   │
                                            │ • read_     │
                                            │   timeout   │
                                            │ • send_     │
                                            │   timeout   │
                                            └──────┬──────┘
                                                   │
                                                   ▼
                                          ┌─────────────┐
                                          │  GKE Runtime │
                                          │  (K8s Pods)  │
                                          │             │
                                          │ • 应用层超时  │
                                          │ • 数据库超时  │
                                          │ • HTTP Client│
                                          │   超时       │
                                          └─────────────┘
```

### 超时链路核心原则

> **外层超时 ≥ 内层超时之和 + 缓冲时间**

如果违反此原则，会导致外层已经断开连接，内层仍在处理请求，造成资源浪费和不可预期的错误。

---

## 二、各层配置详解

### 2.1 GCP GLB (Global Load Balancer) - HTTPS Layer 7

GCP GLB 作为入口层，主要控制**连接建立**和**后端响应等待**两个维度。

#### 关键超时参数

| 参数                           | 默认值 | 最大值                   | 说明                   |
| ------------------------------ | ------ | ------------------------ | ---------------------- |
| `timeoutSec` (后端服务超时)    | 30s    | 300s (部分配置可达 600s) | 等待后端响应的完整时间 |
| `connectionDrainingTimeoutSec` | 300s   | 300s                     | 连接排空时间           |
| `healthCheck.timeoutSec`       | 5s     | -                        | 健康检查超时           |
| `healthCheck.checkIntervalSec` | 5s     | -                        | 健康检查间隔           |

#### 配置方式

**gcloud CLI:**
```bash
# 设置后端服务超时为 300 秒
gcloud compute backend-services update my-backend-service \
  --global \
  --timeout=300

# 创建时配置
gcloud compute backend-services create my-backend-service \
  --protocol=HTTPS \
  --global \
  --timeout=300 \
  --health-checks=my-health-check
```

**Terraform:**
```hcl
resource "google_compute_backend_service" "default" {
  name        = "my-backend-service"
  protocol    = "HTTPS"
  timeout_sec = 300  # 关键参数：整个请求响应的超时时间

  backend {
    group = google_compute_instance_group_manager.default.instance_group
  }

  health_checks = [google_compute_health_check.default.id]
}

resource "google_compute_health_check" "default" {
  name = "my-health-check"
  
  https_health_check {
    port         = 443
    request_path = "/health"
    timeout_sec  = 5
  }
  
  check_interval_sec = 5
  healthy_threshold  = 2
  unhealthy_threshold = 3
}
```

#### ⚠️ GCP GLB 重试机制

**GCP GLB 本身不执行应用层重试**。它只在以下场景有隐式行为：
- 后端实例返回 `502`, `503` 时，GLB 可能尝试将请求路由到健康的后端实例（非幂等请求有风险）
- 连接失败时会尝试其他后端

> **建议：不要在 GLB 层依赖重试，应在 Nginx/Kong 层显式配置。**

---

### 2.2 Nginx L7 (反向代理层)

Nginx 是超时配置最精细的一层，分为**连接**、**发送**、**读取**三个独立维度。

#### 关键超时参数

| 指令                          | 上下文               | 默认值          | 说明                                 |
| ----------------------------- | -------------------- | --------------- | ------------------------------------ |
| `proxy_connect_timeout`       | http/server/location | 60s             | 与上游建立连接的超时                 |
| `proxy_read_timeout`          | http/server/location | 60s             | 等待上游响应的超时（两次读操作之间） |
| `proxy_send_timeout`          | http/server/location | 60s             | 向上游发送请求的超时                 |
| `proxy_next_upstream`         | http/server/location | `error timeout` | 什么情况下触发重试                   |
| `proxy_next_upstream_timeout` | http/server/location | 0 (无限制)      | 重试总超时限制                       |
| `proxy_next_upstream_tries`   | http/server/location | 0 (无限制)      | 重试次数限制                         |

#### 配置示例

```nginx
http {
    # 上游 Kong 集群
    upstream kong_backend {
        server kong-1:8000 max_fails=3 fail_timeout=30s;
        server kong-2:8000 max_fails=3 fail_timeout=30s;
        keepalive 100;
    }

    server {
        listen 443 ssl http2;
        server_name api.example.com;

        location / {
            # ========== 超时配置 ==========
            proxy_connect_timeout 5s;        # 连接 Kong 最多等 5s
            proxy_read_timeout 290s;         # 等待 Kong 响应最多 290s
            proxy_send_timeout 60s;          # 发送请求到 Kong 最多 60s
            
            # 必须大于 Kong + GKE 的总处理时间
            # 290s < GLB 300s，留 10s 缓冲

            # ========== 重试配置 ==========
            # 仅在以下错误时重试，排除非幂等方法
            proxy_next_upstream error timeout invalid_header http_502 http_503 http_504;
            
            # 限制重试次数和超时
            proxy_next_upstream_tries 2;     # 最多重试 2 次（含原始共 3 次）
            proxy_next_upstream_timeout 295s; # 重试总时间不超过 295s
            
            # 非幂等请求不重试（关键！）
            if ($request_method ~* "(POST|PATCH|PUT|DELETE)") {
                proxy_next_upstream off;
            }

            # ========== 代理配置 ==========
            proxy_pass http://kong_backend;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # 缓冲配置（影响超时感知）
            proxy_buffering on;
            proxy_buffer_size 4k;
            proxy_buffers 8 4k;
        }
        
        # 长连接/Websocket 路径特殊处理
        location /ws/ {
            proxy_read_timeout 86400s;       # WebSocket 需要超长超时
            proxy_send_timeout 86400s;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_pass http://kong_backend;
        }
    }
}
```

#### Nginx 重试深度解析

```nginx
# 完整的 proxy_next_upstream 配置
proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504 http_403 http_404 http_429 non_idempotent;

# 参数说明：
# error          - 与服务器建立连接、发送请求、读取响应头时出错
# timeout        - 与服务器建立连接、发送请求、读取响应头时超时
# invalid_header - 服务器返回空响应或无效响应头
# http_5xx       - 服务器返回对应状态码
# non_idempotent - 默认不重试非幂等请求(POST/PUT/PATCH/DELETE)，加上此参数会重试（危险！）
```

> **⚠️ 关键警告：** 默认情况下 Nginx **不会**对 `POST/PUT/PATCH/DELETE` 请求重试（即使配置了 `proxy_next_upstream`），这是安全设计。除非你显式添加 `non_idempotent`，否则是安全的。

---

### 2.3 Kong (API Gateway)

Kong 基于 OpenResty/Nginx，但提供了更高级的路由、插件和上游管理能力。

#### 关键超时参数

| 参数              | Kong 传统模式 | Kong Ingress Controller      | 说明         |
| ----------------- | ------------- | ---------------------------- | ------------ |
| `connect_timeout` | upstream 配置 | `konghq.com/connect-timeout` | 连接上游超时 |
| `write_timeout`   | upstream 配置 | `konghq.com/write-timeout`   | 发送请求超时 |
| `read_timeout`    | upstream 配置 | `konghq.com/read-timeout`    | 读取响应超时 |
| `retries`         | upstream 配置 | `konghq.com/retries`         | 重试次数     |

#### 配置方式

**Admin API 配置 Upstream:**
```bash
# 创建 Upstream
curl -X POST http://localhost:8001/upstreams \
  --data name=gke-backend \
  --data algorithm=round-robin

# 添加 Target（GKE Service Endpoint）
curl -X POST http://localhost:8001/upstreams/gke-backend/targets \
  --data target=gke-service.namespace.svc.cluster.local:8080 \
  --data weight=100

# 配置超时和重试
curl -X PATCH http://localhost:8001/upstreams/gke-backend \
  --data connect_timeout=5000 \      # 5s
  --data write_timeout=60000 \       # 60s
  --data read_timeout=280000 \       # 280s (必须 < Nginx 290s)
  --data retries=2

# 创建 Service 关联 Upstream
curl -X POST http://localhost:8001/services \
  --data name=my-api \
  --data host=gke-backend \
  --data protocol=http \
  --data port=80
```

**Kong Ingress Controller (Kubernetes):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-api-ingress
  annotations:
    # Kong 特定注解
    konghq.com/strip-path: "true"
    
    # ========== 超时配置 ==========
    konghq.com/connect-timeout: "5000"     # 5s
    konghq.com/write-timeout: "60000"      # 60s
    konghq.com/read-timeout: "280000"      # 280s
    
    # ========== 重试配置 ==========
    konghq.com/retries: "2"
    
    # ========== 健康检查 ==========
    konghq.com/healthcheck-active-healthy-interval: "5"
    konghq.com/healthcheck-active-unhealthy-interval: "5"
    konghq.com/healthcheck-active-timeout: "3"
    konghq.com/healthcheck-active-http-path: "/health"
    konghq.com/healthcheck-active-healthy-successes: "2"
    konghq.com/healthcheck-active-unhealthy-timeouts: "3"
    
spec:
  ingressClassName: kong
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /v1
        pathType: Prefix
        backend:
          service:
            name: gke-backend-service
            port:
              number: 8080
```

#### Kong 重试机制

```lua
-- Kong 重试逻辑（内部实现）
-- 1. 仅对幂等方法默认重试 (GET, HEAD, OPTIONS, TRACE)
-- 2. 可配置 retries 次数（默认 5，建议改为 2-3）
-- 3. 重试条件：
--    - 连接失败
--    - 连接超时
--    - 500, 502, 503, 504 (可配置)

-- 自定义重试插件示例（Lua）
local RetryHandler = {
  PRIORITY = 1000,
  VERSION = "1.0.0",
}

function RetryHandler:access(conf)
  -- 对特定路径关闭重试
  if kong.request.get_path() == "/payment/webhook" then
    kong.service.request.set_retries(0)
  end
end
```

---

### 2.4 GKE Runtime (Kubernetes Pods)

应用层是超时的最终执行者，必须考虑**业务处理**、**数据库**、**外部依赖**三个维度。

#### K8s 层面的超时配置

```yaml
apiVersion: v1
kind: Service
metadata:
  name: gke-backend-service
spec:
  type: ClusterIP
  selector:
    app: my-app
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
  # Service 本身没有超时概念，但 sessionAffinity 影响连接复用
  sessionAffinity: None
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: app
        image: my-app:latest
        ports:
        - containerPort: 8080
        # ========== 关键：K8s 探针超时 ==========
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5    # 探针超时
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3    # 探针超时
          failureThreshold: 3
        # ========== 资源限制（间接影响超时） ==========
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
```

#### 应用层超时配置示例

**Spring Boot (Java):**
```yaml
# application.yml
server:
  tomcat:
    connection-timeout: 5000        # 连接建立超时 5s
    keep-alive-timeout: 290000      # 保持连接超时 290s
    
spring:
  mvc:
    async:
      request-timeout: 280000       # 异步请求超时 280s
      
  datasource:
    hikari:
      connection-timeout: 3000      # 数据库连接超时 3s
      idle-timeout: 600000
      max-lifetime: 1800000
      
  cloud:
    openfeign:
      client:
        config:
          default:
            connectTimeout: 5000    # Feign 连接超时
            readTimeout: 30000      # Feign 读取超时
```

**Node.js / Express:**
```javascript
const express = require('express');
const app = express();

// 服务器超时设置
const server = app.listen(8080, () => {
  console.log('Server running on port 8080');
});

// 必须小于 Kong read_timeout (280s)
server.timeout = 275000;           // 275s
server.keepAliveTimeout = 275000;  // 275s
server.headersTimeout = 276000;    // 必须 > keepAliveTimeout

// 请求处理超时中间件
const timeout = require('connect-timeout');

app.use('/api/', timeout('270s')); // 业务逻辑超时 270s

app.use((req, res, next) => {
  if (req.timedout) {
    return res.status(504).json({ error: 'Gateway Timeout' });
  }
  next();
});
```

**Python / FastAPI:**
```python
from fastapi import FastAPI
import uvicorn

app = FastAPI()

# Uvicorn 启动参数（超时控制）
# uvicorn main:app --host 0.0.0.0 --port 8080 --timeout-keep-alive 275

@app.get("/api/data")
async def get_data():
    # 业务逻辑超时应 < 275s
    # 使用 asyncio.wait_for 控制具体逻辑
    import asyncio
    try:
        result = await asyncio.wait_for(
            heavy_computation(),
            timeout=270.0
        )
        return result
    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="Request timeout")

if __name__ == "__main__":
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8080,
        timeout_keep_alive=275,  # 必须 < Kong read_timeout
        limit_concurrency=1000
    )
```

---

## 三、如何评估整个平台的需求

### 3.1 超时评估矩阵

```
评估维度：
┌─────────────────┬─────────────────────────────────────────────┐
│   评估项         │              评估方法                        │
├─────────────────┼─────────────────────────────────────────────┤
│ API 类型         │ 同步/异步/流式/Websocket                      │
│ P99 响应时间     │ 从 APM (Datadog/NewRelic/Prometheus) 获取      │
│ 数据库查询时间   │ 慢查询日志分析                                 │
│ 外部依赖耗时     │ 第三方 API 的 SLA 和实际监控                   │
│ 文件上传/下载    │ 文件大小 ÷ 最小带宽                           │
│ 批处理任务       │ 历史执行时间分布                               │
└─────────────────┴─────────────────────────────────────────────┘
```

### 3.2 超时时间计算公式

```
总超时预算 = GLB_timeout

各层分配：
GLB_timeout (300s)
    │
    ├── Nginx proxy_read_timeout (290s) = GLB - 10s 缓冲
    │       │
    │       ├── Kong read_timeout (280s) = Nginx - 10s 缓冲
    │       │       │
    │       │       ├── App Server timeout (275s) = Kong - 5s 缓冲
    │       │       │       │
    │       │       │       ├── Business Logic timeout (270s) = App - 5s
    │       │       │       │       │
    │       │       │       │       └── DB Query timeout (30s)  # 远小于业务超时
    │       │       │       │
    │       │       │       └── External API timeout (20s)  # 独立控制
    │       │       │
    │       │       └── Kong connect_timeout (5s)
    │       │
    │       └── Nginx proxy_connect_timeout (5s)
    │
    └── GLB Health Check timeout (5s)  # 独立

通用公式：
Layer_N_timeout = Layer_(N-1)_timeout - buffer(5~10s)
```

### 3.3 重试需求评估决策树

```
是否需要重试？
        │
        ▼
   请求是否幂等？ ──否──▶ 绝对不重试（除非有去重机制）
        │是
        ▼
   失败率是否 > 0.1%？ ──否──▶ 不需要重试
        │是
        ▼
   失败原因是否瞬态？ ──否──▶ 不重试（业务错误重试无用）
   (网络抖动、临时过载)
        │是
        ▼
   重试是否会加剧问题？ ──是──▶ 限流+熔断，而非重试
   (雪崩风险)
        │否
        ▼
   设置重试次数 = 1~2 次
   使用指数退避 (Exponential Backoff)
   设置重试总超时 < 外层超时
```

### 3.4 重试策略选择

| 场景                     | 重试次数 | 退避策略            | 适用层     |
| ------------------------ | -------- | ------------------- | ---------- |
| 健康实例间的简单故障转移 | 1-2      | 无（立即）          | Nginx/Kong |
| 瞬态网络错误             | 2-3      | 固定间隔 100ms      | Kong       |
| 第三方 API 限流          | 3        | 指数退避 1s, 2s, 4s | App 层     |
| 数据库连接失败           | 2        | 线性退避 50ms       | App 层     |
| 大规模故障（机房级）     | 0        | -                   | 应触发熔断 |

---

## 四、最佳实践

### 4.1 超时配置黄金法则

```
┌────────────────────────────────────────────────────────────────┐
│  1. 外层 > 内层（至少 5-10 秒缓冲）                              │
│  2. 连接超时 << 读取超时（连接通常几秒内建立）                    │
│  3. 健康检查超时 << 业务超时                                     │
│  4. 非幂等请求 = 0 重试                                          │
│  5. 重试总时间 < 当前层读取超时                                   │
│  6. 每一层都配置超时（不要依赖默认值）                            │
│  7. 超时配置需与监控告警联动                                      │
└────────────────────────────────────────────────────────────────┘
```

### 4.2 推荐配置值（基于 300s GLB 上限）

```yaml
# 推荐超时链路配置（单位：毫秒）

gcp_glb:
  timeout_sec: 300
  health_check_timeout: 5

nginx:
  proxy_connect_timeout: 5000      # 5s - 连接 Kong
  proxy_read_timeout: 290000       # 290s - 等待 Kong 响应
  proxy_send_timeout: 60000        # 60s - 发送给 Kong
  proxy_next_upstream_tries: 2
  proxy_next_upstream_timeout: 295000

kong:
  connect_timeout: 5000            # 5s
  write_timeout: 60000             # 60s
  read_timeout: 280000             # 280s
  retries: 2

gke_app:
  server_timeout: 275000           # 275s
  business_logic_timeout: 270000   # 270s
  db_query_timeout: 30000          # 30s
  external_api_timeout: 20000      # 20s
```

### 4.3 重试最佳实践

```nginx
# Nginx 层重试配置（最安全的做法）

# 1. 按方法区分重试
map $request_method $retry_safe {
    default     0;
    GET         1;
    HEAD        1;
    OPTIONS     1;
}

location / {
    proxy_pass http://kong_backend;
    
    # 基础重试条件
    proxy_next_upstream error timeout http_502 http_503 http_504;
    
    # 动态控制重试
    proxy_next_upstream_tries $retry_safe;  # 安全方法重试1次，其他不重试
    
    # 或者使用 if（性能稍差但清晰）
    if ($request_method !~ ^(GET|HEAD|OPTIONS)$) {
        proxy_next_upstream off;
    }
}
```

```yaml
# Kong 层：使用 Circuit Breaker 插件防止重试风暴
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: circuit-breaker
plugin: proxy-cache  # 或使用自定义插件实现熔断
config:
  strategy: memory
```

### 4.4 配置一致性管理

**使用 GitOps + ConfigMap 统一配置：**

```yaml
# configmap-timeouts.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: timeout-configs
  namespace: default
data:
  # 全局超时基准
  GLB_TIMEOUT: "300"
  NGINX_READ_TIMEOUT: "290"
  KONG_READ_TIMEOUT: "280"
  APP_TIMEOUT: "275"
  BUSINESS_TIMEOUT: "270"
  
  # 连接超时
  CONNECT_TIMEOUT: "5"
  
  # 重试配置
  MAX_RETRIES: "2"
  RETRY_TIMEOUT: "295"
---
# 在 CI/CD 中验证：外层 > 内层
# validation.sh
#!/bin/bash
GLB=300
NGINX=290
KONG=280
APP=275

if [ $NGINX -ge $GLB ] || [ $KONG -ge $NGINX ] || [ $APP -ge $KONG ]; then
  echo "ERROR: Timeout hierarchy violated!"
  exit 1
fi
echo "Timeout configuration valid."
```

### 4.5 监控与告警

```yaml
# Prometheus 告警规则
groups:
- name: timeout-alerts
  rules:
  # 1. 检测超时层级不一致
  - alert: TimeoutHierarchyViolation
    expr: |
      nginx_upstream_read_time > kong_upstream_read_time 
      or kong_upstream_read_time > app_server_timeout
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Timeout hierarchy violation detected"

  # 2. 检测高频重试
  - alert: HighRetryRate
    expr: rate(nginx_upstream_retries[5m]) > 0.1
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High retry rate detected: {{ $value }} retries/sec"

  # 3. 检测 504 Gateway Timeout 激增
  - alert: GatewayTimeoutSpike
    expr: rate(nginx_http_requests_total{status="504"}[5m]) > 0.05
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "504 errors spiking, check timeout configuration"

  # 4. 检测连接超时
  - alert: ConnectionTimeoutHigh
    expr: rate(nginx_upstream_connect_time_bucket{le="+Inf"}[5m]) > 0.01
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Connection timeouts increasing"
```

---

## 五、故障排查

### 5.1 常见问题诊断流程

```
用户报告：请求失败/超时
        │
        ▼
   查看 GLB 日志 (Cloud Logging)
        │
        ├── 502 Bad Gateway ──▶ 后端无健康实例
        │                      • 检查 health check
        │                      • 检查 GKE Pod 状态
        │
        ├── 503 Service Unavailable ──▶ 容量不足或维护
        │                                • 检查后端实例数
        │                                • 检查 connection draining
        │
        ├── 504 Gateway Timeout ──▶ 超时层级问题
        │                            • 对比各层 timeout 配置
        │                            • 检查哪一层先触发
        │
        └── 连接重置 ──▶ 安全组/防火墙或 SSL 问题
```

### 5.2 各层日志排查命令

```bash
# ========== GCP GLB 日志 ==========
# 在 Cloud Logging 中查询
resource.type="http_load_balancer"
httpRequest.status>=500
jsonPayload.statusDetails!="response_sent_by_backend"

# 关键字段：
# - jsonPayload.statusDetails: "backend_timeout" (GLB 触发超时)
# - httpRequest.latency: 查看实际耗时

# ========== Nginx 日志 ==========
# 自定义日志格式，包含上游时间
log_format upstream_time '$remote_addr - $remote_user [$time_local] '
                         '"$request" $status $body_bytes_sent '
                         '"$http_referer" "$http_user_agent" '
                         'rt=$request_time uct="$upstream_connect_time" '
                         'uht="$upstream_header_time" urt="$upstream_response_time" '
                         'retry="$upstream_retries"';

# 排查命令
grep "504" /var/log/nginx/access.log | tail -20

# 关键指标：
# - upstream_connect_time: 连接 Kong 耗时（应 < 5s）
# - upstream_header_time: 收到 Kong 响应头耗时
# - upstream_response_time: 完整响应耗时
# - upstream_retries: 重试次数

# 如果 upstream_response_time ≈ proxy_read_timeout → Nginx 触发超时

# ========== Kong 日志 ==========
# 启用 Kong 详细日志
curl -X POST http://localhost:8001/plugins \
  --data name=file-log \
  --data config.path=/var/log/kong/access.log

# 或使用 Prometheus 指标
curl http://localhost:8001/metrics | grep kong_latency

# 关键指标：
# - kong_latency: Kong 处理时间
# - upstream_latency: 上游（GKE）响应时间
# - kong_http_requests_total{code="504"}

# ========== GKE Pod 日志 ==========
kubectl logs -f deployment/my-app --tail=100

# 查看应用超时日志
kubectl logs -f deployment/my-app | grep -i "timeout\|deadline"

# 检查 Pod 资源
kubectl top pod -l app=my-app
```

### 5.3 典型问题速查表

| 现象                       | 根因                                    | 排查层     | 解决方案                                   |
| -------------------------- | --------------------------------------- | ---------- | ------------------------------------------ |
| 504 但后端很快返回         | Nginx proxy_read_timeout < 应用实际耗时 | Nginx      | 增加 proxy_read_timeout，确保 > Kong + App |
| 504 且后端也 504           | Kong read_timeout < 应用耗时            | Kong       | 增加 Kong read_timeout                     |
| 随机 502                   | 后端 Pod 重启/不健康                    | GKE        | 检查 livenessProbe，增加优雅关闭时间       |
| 重试不生效                 | proxy_next_upstream 未配置或方法被排除  | Nginx      | 检查配置，确认非幂等方法处理               |
| 重试导致重复提交           | 非幂等请求被重试                        | Nginx/Kong | 对 POST/PUT/PATCH/DELETE 关闭重试          |
| 连接超时                   | 网络或 Kong 实例不可用                  | Nginx→Kong | 检查 Kong health，增加 connect_timeout     |
| GLB 返回 502 但 Nginx 正常 | GLB health check 失败                   | GLB        | 检查 health check 路径和超时               |
| 超时时间被"截断"           | 某层 timeout < 内层总和                 | 全链路     | 使用公式验证层级关系                       |
| 雪崩效应                   | 重试风暴导致级联故障                    | Kong/App   | 添加熔断器，限制重试次数，使用退避         |

### 5.4 超时链路追踪

```bash
# 使用 OpenTelemetry/Jaeger 追踪全链路超时
# 在每一层注入追踪信息

# 1. Nginx 启用 OpenTelemetry
load_module modules/ngx_http_opentracing_module.so;

opentracing on;
opentracing_tag http.user_agent $http_user_agent;
opentracing_tag upstream_retries $upstream_retries;
opentracing_tag upstream_response_time $upstream_response_time;

# 2. Kong 启用 Zipkin 插件
curl -X POST http://localhost:8001/plugins \
  --data name=zipkin \
  --data config.http_endpoint=http://zipkin:9411/api/v2/spans \
  --data config.sample_ratio=1

# 3. 应用层注入追踪 (OpenTelemetry SDK)

# 追踪结果示例：
# [GLB: 0ms] → [Nginx: 2ms] → [Kong: 5ms] → [App: 150ms] → [DB: 20ms]
#                                     ↑
#                              如果这里突然跳到 290000ms
#                              说明 Kong 触发了超时
```

### 5.5 压力测试验证配置

```bash
# 使用 k6 验证超时配置
# timeout-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },   #  ramp up
    { duration: '5m', target: 100 },   #  steady
    { duration: '2m', target: 0 },     #  ramp down
  ],
  thresholds: {
    http_req_duration: ['p(99)<280000'],  # 99% 请求 < 280s
    http_req_failed: ['rate<0.1'],        # 错误率 < 0.1%
  },
};

export default function() {
  # 测试正常 API
  let res = http.get('https://api.example.com/v1/data');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 270s': (r) => r.timings.duration < 270000,
  });

  # 测试慢 API（验证超时链路）
  let slowRes = http.get('https://api.example.com/v1/slow?delay=285');
  check(slowRes, {
    'timeout returns 504': (r) => r.status === 504,
  });

  sleep(1);
}
```

---

## 六、总结检查清单

```
□ 超时层级验证：GLB(300) > Nginx(290) > Kong(280) > App(275) > Biz(270)
□ 连接超时独立设置：connect_timeout = 5s（远小于 read_timeout）
□ 重试安全：非幂等方法不重试
□ 重试次数限制：≤ 2 次
□ 健康检查超时 < 业务超时
□ 所有超时都有监控告警
□ 压力测试覆盖正常和超时场景
□ 文档化各层配置和变更流程
□ 使用 GitOps 管理配置一致性
□ 故障演练：模拟各层超时，验证行为符合预期
```

