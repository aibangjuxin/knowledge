# K8s Gateway API 超时配置参考

> 基于 ListenerSet 多租户架构探索：infrastructure/Gateway + team*/ListenerSet + HTTPRoute + DestinationRule
>
> 生成日期：2026-05-30

---

## 1. 架构与超时配置层级

涉及超时的三个资源：

| 资源 | 命名空间 | 超时相关字段 |
|------|----------|-------------|
| `ListenerSet` | team* | **无超时字段**（仅定义端口/TLS/域名） |
| `HTTPRoute` | team* | `spec.rules[].timeouts.request`、`timeouts.backendTimeout` |
| `DestinationRule` | team* | `spec.trafficPolicy.{timeout, connectTimeout, connectionPool}` |

### 1.1 目录结构（对齐用户实际环境）

```
infrastructure/
└── gateway.yaml              # 共享 Gateway (infrastructure ns)

team1/
├── listenerset.yaml          # ListenerSet (team1 ns)
├── httproute.yaml           # HTTPRoute (team1 ns)
└── destinationrule.yaml     # DestinationRule (team1 ns)

team2/ ... team3/ ... (同上)
```

---

## 2. HTTPRoute 超时

### 2.1 字段定义

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
        # 整个 HTTP 请求总超时
        request: "10s"
        # upstream 后端响应超时
        backendTimeout: "5s"
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `timeouts.request` | Duration | HTTP 请求总超时（RFC 3339 格式） |
| `timeouts.backendTimeout` | Duration | 仅后端 upstream 响应超时 |

> ⚠️ **注意**：这是 **Extended Support** 特性（非 GA 标准通道），Istio 的 Gateway API 实现可能不完全转换此字段到 Envoy 配置。实际超时控制以 DestinationRule 为准。

### 2.2 示例

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
```

---

## 3. DestinationRule 超时配置

### 3.1 核心字段

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `trafficPolicy.timeout` | `5s` | HTTP 请求级超时（**Envoy 默认 5s**，覆盖它） |
| `trafficPolicy.connectTimeout` | `10s` | TCP 连接建立超时 |

### 3.2 ConnectionPoolSettings（HTTP 和 TCP）

#### HTTP 设置

```yaml
trafficPolicy:
  connectionPool:
    http:
      http2: true
      maxRequestsPerConnection: 0
      h2UpgradePolicy: UPGRADE
  timeout: 60s
  connectTimeout: 10s
```

#### TCP 设置

```yaml
trafficPolicy:
  connectionPool:
    tcp:
      maxConnections: 100
      connectTimeout: 30ms
      tcpKeepalive:
        time: 7200s
        interval: 75s
```

### 3.3 完整示例

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team1-app-dr
  namespace: team1
spec:
  host: team1-app-service.team1.svc.cluster.local
  trafficPolicy:
    timeout: 60s
    connectTimeout: 10s
    loadBalancer:
      simple: LEAST_REQUEST
    connectionPool:
      http:
        http2: true
        maxRequestsPerConnection: 0
      tcp:
        maxConnections: 100
    portLevelSettings:
      - port:
          number: 8080
        timeout: 30s
        loadBalancer:
          simple: ROUND_ROBIN
```

---

## 4. 超时优先级

```
HTTPRoute rules[].timeouts.backendTimeout   ← 最细粒度（upstream 等待）
HTTPRoute rules[].timeouts.request         ← HTTP 总超时 (Extended Support)
DestinationRule trafficPolicy.timeout     ← 服务级覆盖 Envoy 默认 5s
DestinationRule trafficPolicy.connectTimeout ← TCP 连接超时
Envoy cluster 默认                          ← 兜底（5s）
```

---

## 5. 各场景配置方案

### 场景一：同命名空间（team1 HTTPRoute → team1 Service）

```
Client → Gateway (infrastructure)
       → ListenerSet (team1)
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

### 场景二：跨命名空间（team1 HTTPRoute → team2 Service）

```
team1 HTTPRoute → team2 Service
（需要 ReferenceGrant 授权）
```

**DestinationRule**（写在 team1 命名空间）：
```yaml
# team1/destinationrule.yaml
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

---

## 6. 调试与验证

### 检查 Envoy 实际生效的超时

```bash
kubectl exec -it <pod-name> -n team1 -c istio-proxy -- /bin/bash
curl -s http://localhost:15000/config_dump | grep -E '"timeout"|"connect_timeout"'
```

### 识别超时日志

| 标志 | 含义 |
|------|------|
| `UT` | Upstream Timeout（后端超时） |
| `UC` | Upstream Connection Failure（连接失败） |

```bash
kubectl logs <pod-name> -n team1 -c istio-proxy --tail=100 | grep -E "UT|UC|504"
```

### 端到端测试

```bash
curl -v --max-time 60 https://app.team1.example.com/api/health
```

---

## 7. 超时配置检查清单

```
□ HTTPRoute spec.rules[].timeouts.request          ← HTTP 总超时 (Extended Support)
□ HTTPRoute spec.rules[].timeouts.backendTimeout   ← upstream 超时 (Extended Support)
□ DestinationRule trafficPolicy.timeout           ← 覆盖 Envoy 默认 5s
□ DestinationRule trafficPolicy.connectTimeout    ← TCP 连接超时
□ DestinationRule trafficPolicy.connectionPool.http  ← HTTP 连接池
□ DestinationRule trafficPolicy.connectionPool.tcp  ← TCP 连接池
□ Envoy access log response_flags (UT/UC)        ← 超时验证
□ 后端应用 HTTP 客户端显式超时                    ← Feign/RestTemplate
□ ReferenceGrant（如跨命名空间调用）              ← 授权
```

---

## 8. 参考资料

- [Gateway API HTTP Timeouts (官方指南)](https://gateway-api.sigs.k8s.io/guides/user-guides/http-timeouts/)
- [Istio DestinationRule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/)
- [Istio ConnectionPoolSettings — HTTP](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-HTTPSettings)
- [Istio ConnectionPoolSettings — TCP](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-TCPSettings)
- [Istio Request Timeouts Task](https://istio.io/latest/docs/tasks/traffic-management/request-timeouts/)
- [Envoy HTTP Connection Manager Timeouts](https://www.envoyproxy.io/docs/envoy/v1.29.0/configuration/http/http_conn_man/timeouts)