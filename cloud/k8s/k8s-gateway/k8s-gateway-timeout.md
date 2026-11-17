# K8s Gateway API 超时配置指南

> ListenerSet 多租户架构下的超时配置
>
> 参考：[Gateway API HTTP Timeouts](https://gateway-api.sigs.k8s.io/guides/user-guides/http-timeouts/) · [Istio DestinationRule](https://istio.io/latest/docs/reference/config/networking/destination-rule/)

---

## 1. 架构与资源映射

```
infrastructure/                    # infrastructure 命名空间
└── gateway.yaml                   # 共享 Gateway

listenersets/                      # listenersets 命名空间（所有 ListenerSet 汇聚）
├── team1-listenerset.yaml         # Team1 ListenerSet
├── team2-listenerset.yaml         # Team2 ListenerSet
└── team3-listenerset.yaml         # Team3 ListenerSet

team1/                             # team1 命名空间
├── httproute.yaml                 # HTTPRoute
└── destinationrule.yaml          # DestinationRule

team2/ ... team3/ ... (同上)
```

| 命名空间 | 资源 | 超时相关字段 |
|----------|------|-------------|
| `infrastructure` | `Gateway` | 无 |
| `listenersets` | `ListenerSet` | 无（仅定义端口/TLS/域名） |
| `team*` | `HTTPRoute` | `spec.rules[].timeouts` |
| `team*` | `DestinationRule` | `spec.trafficPolicy.{timeout, connectTimeout, connectionPool}` |

---

## 2. HTTPRoute 超时配置

### 2.1 官方字段（Extended Support）

Gateway API `v1` 在 `HTTPRouteRule` 级别定义了 [`timeouts`](https://gateway-api.sigs.k8s.io/references/spec/gateway.networking.k8s.io/v1/#gateway.networking.k8s.io/v1.HTTPRouteRule)：

```yaml
spec:
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /delay
      backendRefs:
        - name: infra-backend-v1
          port: 8080
      timeouts:
        # 整个 HTTP 请求超时（含后端处理、重试等）
        request: "10s"
        # 仅后端 upstream 响应超时
        backendTimeout: "5s"
```

| 字段 | 类型 | 说明 |
|------|------|------|
| [`timeouts.request`](https://gateway-api.sigs.k8s.io/references/spec/gateway.networking.k8s.io/v1/#gateway.networking.k8s.io/v1.HTTPRouteTimeout) | `Duration` | HTTP 请求总超时（RFC 3339 格式，如 `"10s"`） |
| [`timeouts.backendTimeout`](https://gateway-api.sigs.k8s.io/references/spec/gateway.networking.k8s.io/v1/#gateway.networking.k8s.io/v1.HTTPRouteTimeout) | `Duration` | 等待后端响应超时 |

> ⚠️ **注意**：这是 **Extended Support** 特性（非 GA 标准通道），Istio 的 Gateway API 实现可能不完全转换此字段到 Envoy 配置。

### 2.2 HTTPRoute 超时示例

```yaml
# team1/httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: team1-app-route
  namespace: team1
spec:
  parentRefs:
    - name: team1-listeners
      kind: ListenerSet
      group: gateway.networking.k8s.io
      sectionName: https
  hostnames:
    - "app.team1.example.com"
  rules:
    # 规则一：/api 路径，超时较短
    - matches:
        - path:
            type: PathPrefix
            value: /api
      timeouts:
        request: "30s"
        backendTimeout: "15s"
      backendRefs:
        - name: team1-app-service
          port: 8080
    # 规则二：默认路由，超时较长
    - timeouts:
        request: "120s"
        backendTimeout: "60s"
      backendRefs:
        - name: team1-app-service
          port: 8080
```

---

## 3. DestinationRule 超时配置

### 3.1 核心字段

| 字段 | 默认值 | 说明 | 参考 |
|------|--------|------|------|
| [`trafficPolicy.timeout`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#TrafficPolicy) | `5s` | **HTTP 请求级超时**（[Istio 文档](https://istio.io/latest/docs/tasks/traffic-management/request-timeouts/)） |
| [`trafficPolicy.connectTimeout`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings) | `10s` | TCP 连接建立超时 |

### 3.2 ConnectionPoolSettings

Istio DestinationRule 提供 [`connectionPool`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings) 子字段用于连接控制：

#### HTTP 连接池

| 字段 | 默认值 | 说明 | 参考 |
|------|--------|------|------|
| [`http.maxRequestsPerConnection`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-HTTPSettings) | `0` (无限制) | 单连接最大请求数 |
| [`http.h2UpgradePolicy`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-HTTPSettings) | `UPGRADE` | HTTP/2 升级策略 |
| [`http.useClientProtocol`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-HTTPSettings) | `false` | 保持客户端协议 |

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team1-app-dr
  namespace: team1
spec:
  host: team1-app-service.team1.svc.cluster.local
  trafficPolicy:
    connectionPool:
      http:
        http2: true
        maxRequestsPerConnection: 0
        h2UpgradePolicy: UPGRADE
    timeout: 60s
    connectTimeout: 10s
```

#### TCP 连接池

| 字段 | 默认值 | 说明 | 参考 |
|------|--------|------|------|
| [`tcp.maxConnections`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-TCPSettings) | `1024` | 最大连接数 |
| [`tcp.connectTimeout`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-TCPSettings) | `10s` | TCP 连接超时 |
| [`tcp.tcpKeepalive`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-TCPSettings) | 无默认值 | TCP Keepalive 配置 |

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team1-tcp-dr
  namespace: team1
spec:
  host: team1-tcp-service.team1.svc.cluster.local
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
        connectTimeout: 30ms
        tcpKeepalive:
          time: 7200s
          interval: 75s
```

#### 完整示例

```yaml
# team1/destinationrule.yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team1-app-dr
  namespace: team1
spec:
  host: team1-app-service.team1.svc.cluster.local
  trafficPolicy:
    # HTTP 请求超时（覆盖 Envoy 默认 5s）
    timeout: 60s
    # TCP 连接超时
    connectTimeout: 10s
    # 负载均衡策略
    loadBalancer:
      simple: LEAST_REQUEST
    # 连接池 - HTTP
    connectionPool:
      http:
        http2: true
        maxRequestsPerConnection: 0
    # 连接池 - TCP
    connectionPool:
      tcp:
        maxConnections: 100
    # 端口级超时覆盖
    portLevelSettings:
      - port:
          number: 8080
        timeout: 30s
        loadBalancer:
          simple: ROUND_ROBIN
```

---

## 4. ListenerSet 说明

ListenerSet **本身不包含超时字段**，它仅负责：

- 端口绑定（port）
- 协议定义（protocol: HTTPS/HTTP）
- TLS 终止配置（tls.mode: Terminate）
- 域名绑定（hostname）
- 路由授权（allowedRoutes）

超时由 **HTTPRoute** 和 **DestinationRule** 控制。

---

## 5. 超时优先级

```
HTTPRoute rules[].timeouts.backendTimeout   ← 最细粒度（upstream 等待）
HTTPRoute rules[].timeouts.request         ← HTTP 总超时
DestinationRule trafficPolicy.timeout      ← 服务级覆盖 Envoy 默认 5s
DestinationRule trafficPolicy.connectTimeout ← TCP 连接超时
Envoy cluster 默认                           ← 兜底（5s）
```

---

## 6. 各场景配置方案

### 6.1 同命名空间跳转（team1 HTTPRoute → team1 Service）

```
Client → Gateway (infrastructure)
       → ListenerSet (listenersets)
       → HTTPRoute (team1) → team1-app-service (team1)
```

**HTTPRoute**：
```yaml
spec:
  rules:
    - timeouts:
        request: "60s"
        backendTimeout: "30s"
      backendRefs:
        - name: team1-app-service
          port: 8080
```

**DestinationRule**：
```yaml
spec:
  trafficPolicy:
    timeout: 30s
    connectTimeout: 10s
```

### 6.2 跨命名空间跳转（team1 HTTPRoute → team2 Service）

```
team1 HTTPRoute (team1) → team2-service (team2)
（需要 ReferenceGrant 授权）
```

**DestinationRule**（写在 team1 命名空间）：
```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: cross-ns-dr
  namespace: team1
spec:
  host: team2-service.team2.svc.cluster.local
  trafficPolicy:
    timeout: 45s
    connectTimeout: 10s
```

### 6.3 长耗时任务（如文件处理、ML 推理）

| 场景 | `timeout` | `backendTimeout` |
|------|-----------|-----------------|
| 快速 API (< 5s) | `15s` | `10s` |
| 标准 API | `60s` | `30s` |
| 长耗时任务 | `300s` | `180s` |

---

## 7. 调试与验证

### 7.1 检查 HTTPRoute 超时配置

```bash
kubectl get httproute team1-app-route -n team1 -o yaml
```

### 7.2 检查 DestinationRule 超时配置

```bash
kubectl get destinationrule team1-app-dr -n team1 -o yaml | grep -E 'timeout|connectTimeout'
```

### 7.3 检查 Envoy 实际生效的超时

```bash
kubectl exec -it <pod-name> -n team1 -c istio-proxy -- /bin/bash
curl -s http://localhost:15000/config_dump | grep -E '"timeout"|"connect_timeout"'
```

### 7.4 识别超时日志

Envoy access log 响应标志：

| 标志 | 含义 |
|------|------|
| `UT` | Upstream Timeout（后端超时） |
| `UC` | Upstream Connection Failure（连接失败） |
| `UF` | Upstream Failure（上游失败） |

```bash
kubectl logs <pod-name> -n team1 -c istio-proxy --tail=100 | grep -E "UT|UC|timeout|504"
```

### 7.5 端到端测试

```bash
curl -v --max-time 60 https://app.team1.example.com/api/health
```

---

## 8. 参考资料

### 官方文档直链

| 字段 | 官方文档 |
|------|---------|
| HTTPRoute `timeouts` | [Gateway API HTTP Timeouts Guide](https://gateway-api.sigs.k8s.io/guides/user-guides/http-timeouts/) |
| HTTPRoute `timeouts` (spec) | [HTTPRoute API Reference](https://gateway-api.sigs.k8s.io/references/spec/gateway.networking.k8s.io/v1/#gateway.networking.k8s.io/v1.HTTPRouteRule) |
| HTTPRouteTimeout 类型 | [HTTPRouteTimeout Definition](https://gateway-api.sigs.k8s.io/references/spec/gateway.networking.k8s.io/v1/#gateway.networking.k8s.io/v1.HTTPRouteTimeout) |
| `trafficPolicy.timeout` | [Istio DestinationRule — TrafficPolicy](https://istio.io/latest/docs/reference/config/networking/destination-rule/#TrafficPolicy) |
| `connectTimeout` | [Istio ConnectionPoolSettings — TCP](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-TCPSettings) |
| `connectionPool.http` | [Istio ConnectionPoolSettings — HTTP](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-HTTPSettings) |
| `connectionPool.tcp` | [Istio ConnectionPoolSettings — TCP](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-TCPSettings) |
| Istio 超时任务 | [Istio Request Timeouts Task](https://istio.io/latest/docs/tasks/traffic-management/request-timeouts/) |

### 超时默认值速查

| 字段 | 默认值 | 来源 |
|------|--------|------|
| `trafficPolicy.timeout` | `5s` | [Istio 官方文档](https://istio.io/latest/docs/tasks/traffic-management/request-timeouts/) |
| `trafficPolicy.connectTimeout` | `10s` | [Istio DestinationRule](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings) |
| `connectionPool.tcp.maxConnections` | `1024` | [Istio DestinationRule](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-TCPSettings) |
| `connectionPool.http.maxRequestsPerConnection` | `0` (无限制) | [Istio DestinationRule](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-HTTPSettings) |

---

## 9. 超时配置检查清单

```
□ HTTPRoute spec.rules[].timeouts.request          ← HTTP 总超时 (Extended Support)
□ HTTPRoute spec.rules[].timeouts.backendTimeout   ← upstream 超时 (Extended Support)
□ DestinationRule trafficPolicy.timeout           ← 覆盖 Envoy 默认 5s
□ DestinationRule trafficPolicy.connectTimeout    ← TCP 连接超时
□ DestinationRule trafficPolicy.connectionPool.http  ← HTTP 连接池
□ DestinationRule trafficPolicy.connectionPool.tcp    ← TCP 连接池
□ Envoy access log response_flags (UT/UC/UF)      ← 超时验证
□ 后端应用 HTTP 客户端显式超时                    ← Feign/RestTemplate
□ ReferenceGrant（如跨命名空间调用）              ← 授权
```

**对你的场景**，最核心配置是 `DestinationRule trafficPolicy.timeout`（覆盖 Envoy 默认 5s）—— 配合 HTTPRoute `backendTimeout` 做细粒度控制。