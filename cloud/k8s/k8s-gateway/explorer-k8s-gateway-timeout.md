# K8s Gateway API 超时机制探索文档 (Explorer)

> 本文档基于 **GKE + ASM / Istio Gateway API** 体系，针对多租户 **ListenerSet** 架构下的超时（Timeout）配置与连接池控制进行深度探索。旨在为平台团队及各租户团队（Team1, Team2 等）提供清晰的超时管理视图、避坑指南及标准配置模板。

---

## 1. 架构级超时全景图 (End-to-End Timeout Landscape)

在多租户 ListenerSet 架构下，一个请求从客户端发出到后端 Pod 响应，会依次经过多个流量网关和控制面。超时配置在各层级的设计如下：

```
                                      【 流量入口层 】                  【 服务网格与连接池层 】
 客户端 ──► 负载均衡器 (GCLB) ──► Shared Gateway / ListenerSet ──► HTTPRoute ──► Sidecar/Upstream ──► Backend Service (Pod)
              │                     │                                │             │                    │
              ▼                     ▼                                ▼             ▼                    ▼
       【 平台级/LB 超时 】   【 监听器级/连接超时 】           【 路由级超时 】 【 目标规则超时 】       【 容器应用超时 】
       - BackendConfig        - Envoy Downstream               - timeouts:      - DestinationRule        - Spring Boot
       - 默认: 30s            - idleTimeout / maxDuration      - request        - connectTimeout         - Feign / client
                              - TCP Keepalive                  - backendRequest - HTTP Idle Timeout      - ReadTimeout
```

### 1.1 核心资源超时职责划分

在你的共享架构中：
*   **Infrastructure (单 Namespace 共享)**: 部署共享 `Gateway` (如 `shared-gateway`)。
*   **ListenerSet (各租户 Namespace)**: 部署 `ListenerSet` (如 `team1-listeners`)。控制 TLS/端口。
*   **Tenant Namespace (team1, team2...)**: 部署 `HTTPRoute` 和 `DestinationRule`。控制具体服务的应用层路由、超时重试以及 TCP/HTTP 连接池。

---

## 2. 资源级超时深度剖析 (Resource-by-Resource Deep Dive)

以下针对你明确提到的三类核心资源（以及作为底层数据面的 Envoy）的超时特性进行深度拆解：

### 2.1 ListenerSet 与 Gateway (监听器及入口连接级)

`ListenerSet` 是 GKE/Gateway API 的多租户委托控制扩展，用于动态向共享的 `Gateway` 注册端口与域名。

*   **是否有直接的超时字段？**
    *   **没有**。`ListenerSet` 及其引用的 `Gateway` 资源本身**不包含** HTTP 级别的请求超时字段。
    *   它们的主要职责是声明物理/逻辑监听端口（Port）、协议（Protocol）和 TLS 证书绑定。
*   **底层的超时影响（Envoy Downstream Timeout）：**
    当 `Gateway` 接收到连接时，底层的 Envoy Proxy 会应用下游连接的全局超时策略（通常在网格控制面全局配置或通过 `Telemetry` / `EnvoyFilter` 调整）：
    1.  **Downstream Idle Timeout**（下游空闲超时）：当客户端与网关之间在一定时间内没有数据传输时，网关将主动断开连接。Envoy 默认通常为 **1小时** 或 **5分钟**。
    2.  **Downstream Max Connection Duration**（最大连接存活时间）：对于 gRPC 或 WebSocket 等长连接，防止单个连接永久占用网关资源，Envoy 可以设置连接的最大生命周期。
*   **⚠️ GKE 场景特有大坑：谷歌云负载均衡 (GCLB) 超时**
    如果你的 GKE 集群使用的是内置的 `networking.gke.io` Ingress/Gateway 控制器，共享的 `Gateway` 底层会由 Google Cloud HTTPS Load Balancer (GCLB) 承载：
    *   **GCLB 默认后端保持超时 (Keep-Alive Timeout) 为 30 秒**。
    *   **现象**：即使你在 `HTTPRoute` 或 `DestinationRule` 中配置了 `60s` 的超时，如果后端处理请求超过 30 秒，GCLB 会抢先向客户端返回 **504 Gateway Timeout**。
    *   **解决方案**：平台管理员必须在 `infrastructure` 命名空间下使用 `GCPBackendPolicy`（或旧版的 `BackendConfig`）来调大负载均衡器的超时时间。

---

### 2.2 HTTPRoute (路由与请求应用级)

`HTTPRoute` 是控制 HTTP 路由行为的核心资源。自 Gateway API `v1.1.0` 起，`timeouts` 字段已进入标准通道。

> 💡 **重要纠错：规范你的 YAML 字段**
> 在较旧的文档或草案中，存在 `requestTimeout` 和 `backendTimeout` 的写法。
> **根据 Gateway API 官方标准规范，正确字段名为 `request` 和 `backendRequest`**。编写配置时请以此为准，以防 K8s API Server 拦截报错。

#### 2.2.1 字段定义与优先级关系

```yaml
timeouts:
  request: "30s"          # 客户端请求 -> 接收到响应的完整时间（包含重试、过滤器处理）
  backendRequest: "10s"   # 网关 -> 单个后端服务尝试的超时（单次 Try 超时）
```

*   **`timeouts.request` (请求总超时)**:
    *   定义了从网关收到请求开始，到完整响应返回给客户端的最大时间。
    *   如果超过此时间，网关将向客户端返回 **504 Gateway Timeout**。
    *   **默认值**：如果未指定，默认依赖底层实现（Istio Ingress Envoy 通常默认为 **无限制/disabled**，但依赖网格的默认路由行为，某些老版本会兜底 15s）。
*   **`timeouts.backendRequest` (后端单次请求超时)**:
    *   定义了网关等待单个 upstream 后端实例响应的时间。
    *   **与重试 (Retries) 配合使用效果最佳**：若设置 `request: 30s`，`backendRequest: 5s`，当后端 Pod-A 挂起 5 秒未响应时，网关可以立刻断开并重试 Pod-B，在 30 秒总时限内完成请求。
    *   **约束条件**：`backendRequest` 必须 **小于或等于** `request` 的值。

#### 2.2.2 租户多路超时路由示例 (`team1/httproute.yaml`)

```yaml
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
    # 规则 1：慢速导出 API (例如大文件下载、报表生成)
    - matches:
        - path:
            type: PathPrefix
            value: /api/v1/export
      timeouts:
        request: "300s"         # 允许 5 分钟处理时间
        backendRequest: "120s"  # 单次 upstream 尝试 2 分钟
      backendRefs:
        - name: team1-export-svc
          port: 8080
          
    # 规则 2：标准核心 API (快速响应，防雪崩)
    - matches:
        - path:
            type: PathPrefix
            value: /api
      timeouts:
        request: "5s"
        backendRequest: "2s"    # 快速熔断慢接口，留出重试空间
      backendRefs:
        - name: team1-core-svc
          port: 8080
```

---

### 2.3 DestinationRule (上游服务与连接池级)

`DestinationRule` 是 Istio 的特有资源，直接影响数据面 Sidecar / Gateway Envoy 对特定 upstream 服务建立连接的底层行为。

如果你使用 `istioctl install --set profile=default` 安装了 Istio，你便拥有了完整的 Istio Service Mesh 增强能力。**`DestinationRule` 负责管理 TCP 三次握手超时、连接复用（Keep-Alive）、空闲超时以及连接池的最大容量。**

#### 2.3.1 连接池与超时核心配置项说明 (ConnectionPoolSettings)

根据 Istio DestinationRule 官方规范，超时与连接池控制在两个协议层级实现：

##### A. TCP 级别控制 (`connectionPool.tcp`)
*   **`connectTimeout` (TCP 建连超时)**:
    *   **含义**：Envoy 与目标 Pod 建立 TCP 连接（三次握手）的最大允许时间。
    *   **默认值**：Istio 默认为 `10s`。在云原生集群内部，这显然太长了。
    *   **建议值**：同一集群内部的服务互访建议设置为 `1s` 到 `3s`；跨命名空间或调用集群外服务可放宽至 `5s`。
*   **`tcpKeepalive` (TCP 保活检测)**:
    *   **含义**：在 TCP 连接闲置时发送保活探测包，防止防火墙或 L4 负载均衡器静默断开长连接。
    *   **重要参数**：
        *   `time`: 无数据传输后多久开始发送探测包（例如 `7200s` 或缩短至 `30s`）。
        *   `interval`: 探测包之间的发送间隔（如 `75s` 或 `5s`）。
        *   `probes`: 连续失败几次后判定连接断开。

##### B. HTTP 级别控制 (`connectionPool.http`)
*   **`idleTimeout` (HTTP 连接空闲超时)**:
    *   **含义**：连接池中的 Keep-Alive 闲置连接保持打开的最大时间。如果该连接上在此时限内无任何请求流动，Envoy 将其从连接池中关闭。
    *   **默认值**：Envoy 通常默认为 `1h`（在 Istio 1.2x+ 中通常也为 1 小时）。
    *   **优化建议**：对于高并发微服务，建议设置为 `90s` 或与后端应用的 HTTP Keep-Alive Timeout 保持一致，避免 "五秒神话（5s Silent Close）" 导致的 `Connection reset by peer` 错误。
*   **`maxRetries` (最大重试次数)**:
    *   控制在连接失败或 upstream 异常时自动重试的次数。

#### 2.3.2 深度连接池配置示例 (`team1/destinationrule.yaml`)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team1-core-dr
  namespace: team1
spec:
  host: team1-core-svc.team1.svc.cluster.local
  trafficPolicy:
    # 💡 纠错与澄清：DestinationRule 的 trafficPolicy 下并没有请求级的 timeout 字段！
    # 所有的 L7 请求超时（即等待后端响应的时间）必须在 HTTPRoute / VirtualService 中设置。
    # DestinationRule 仅通过 connectionPool 负责底层连接管理（如 TCP 建连与空闲超时）。
    
    # 底层 TCP & HTTP 连接池配置 (基于 ConnectionPoolSettings)
    connectionPool:
      tcp:
        maxConnections: 1024        # 最大建立的 TCP 连接数
        connectTimeout: 2s          # 2秒建连超时（远低于默认的10秒，快速响应异常）
        tcpKeepalive:
          time: 60s                 # 闲置 60 秒后开始发送保活探测
          interval: 10s             # 探测间隔 10 秒
          probes: 3                 # 失败 3 次断开连接
      http:
        http1MaxPendingRequests: 100 # 等待建连的最大挂起请求数
        http2MaxRequests: 1024      # 最大并发 HTTP/2 请求数
        idleTimeout: 90s            # HTTP 连接空闲超时时间（90秒无请求则释放连接）
        maxRequestsPerConnection: 100 # 单个物理连接最多处理 100 个请求后重建（防内存泄漏）
        
    # 3. 针对特定端口的独立覆盖设置
    portLevelSettings:
      - port:
          number: 8443
        connectionPool:
          tcp:
            connectTimeout: 5s      # TLS 端口建连时间更长，允许 5s
```

---

### 2.4 默认超时与空闲时间一览表 (Default Values when Unspecified)

如果你在 `HTTPRoute` 和 `DestinationRule` 中**不做任何特殊配置**（即缺省所有超时和连接池配置），系统各层级的官方文档规范与默认行为如下：

| 资源层级 | 核心配置项 (附官方规格绝对链接) | 官方/Envoy 默认值 | Istio / GKE 实际生效行为 | 影响及说明 |
| :--- | :--- | :--- | :--- | :--- |
| **HTTPRoute** | [`timeouts.request`](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.HTTPRouteRule) | Envoy 默认为 `15s` | **无限制 / Disabled** | Istio 会在翻译路由时，自动将缺省的路由超时显式重置为 `0s`（无限等待），因此网格层不做请求时间截止。 |
| **HTTPRoute** | [`timeouts.backendRequest`](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.HTTPRouteRule) | Envoy 默认为 `15s` | **无限制 / Disabled** | 缺省时不会执行单次重试超时。 |
| **DestinationRule** | [`connectionPool.tcp.connectTimeout`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-TCPSettings) | 无 | **10 秒 (10s)** | **核心注意点**：TCP 三次握手建连的最长等待时间。同一命名空间或集群内 10s 显然过长，建议显式配置为 `1s` - `2s`。 |
| **DestinationRule** | [`connectionPool.tcp.idleTimeout`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-TCPSettings) | Envoy 默认为 `1h` | **1 小时 (1h)** | TCP 连接上无任何数据流动时的空闲释放时间。 |
| **DestinationRule** | [`connectionPool.http.idleTimeout`](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-HTTPSettings) | Envoy 默认为 `1h` | **无限制 / Disabled** | 依赖底层 TCP idleTimeout 或 gRPC keepalive。高并发场景建议配置为 `90s` 防止静默断连。 |
| **GKE 共享网关** | [`GCPBackendPolicy.timeoutSec`](https://cloud.google.com/kubernetes-engine/docs/how-to/configure-gateway-resources#backend-timeout) | GCP 默认为 `30s` | **30 秒 (30s)** | **终极杀手**：若您的请求未设置超时且处理超过 30s，GCLB 会抢先切断连接并向客户端返回 504。 |

---

## 3. 超时机制优先级与冲突判定

在 ListenerSet 多租户模式下，当多个组件同时配置了超时，它们的生效关系和优先级如下：

| 配置资源 | 控制层级 | 优先级 | 适用场景及冲突表现 |
| :--- | :--- | :---: | :--- |
| **HTTPRoute Rule `timeouts.request`** | 路由级 (Ingress) | **1 (最高)** | 影响网关到客户端的行为。若触发则返回 **504**。会覆盖 `DestinationRule` 的超时。 |
| **DestinationRule `trafficPolicy.timeout`** | 服务级 (Mesh 内部) | **2** | 影响 Sidecar 间调用及网关到 Pod 的底层请求时长。若此处超时先到，网关会收到 504 错误。 |
| **Envoy 默认路由超时 (Router Filter)** | 网关默认 | **3** | **Envoy 默认 HTTP 路由超时通常为 5s 或 15s**。如果以上两者都未显式配置，容易在此处踩坑。 |
| **GCLB Backend Timeout** | 外部负载均衡 | **外部兜底** | 物理入口层。必须 $\ge$ `HTTPRoute.timeouts.request`，否则外部 LB 提前断开返回 **504**（不经过 Envoy）。 |

---

## 4. 完整的租户超时配置最佳实践模板 (Team1 & Team2)

为保障你的多命名空间架构稳定运行，我们为 `team1` 和 `team2` 设定标准的 YAML 示例包。

### 4.1 Team1：高并发、快速熔断类型 (Spring Boot API)

Team1 拥有大量的 Spring Boot 微服务，希望接口响应极快（均在 3s 内），且配置合理的 TCP 连接池防止雪崩。

#### `team1/httproute.yaml`
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: team1-api-route
  namespace: team1
spec:
  parentRefs:
    - name: team1-listeners
      kind: ListenerSet
      group: gateway.networking.k8s.io
      sectionName: https
  hostnames:
    - "api.team1.example.com"
  rules:
    - timeouts:
        request: "3s"               # 整个交易最多 3 秒
        backendRequest: "1.5s"      # 单个 Pod 尝试最多 1.5 秒
      backendRefs:
        - name: team1-api-service
          port: 8080
```

#### `team1/destinationrule.yaml`
- https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings
```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team1-api-dr
  namespace: team1
spec:
  host: team1-api-service.team1.svc.cluster.local
  trafficPolicy:
    # 💡 请求级 L7 超时已在 team1/httproute.yaml 中定义为 3s，此处无 timeout 字段
    connectionPool:
      tcp:
        connectTimeout: 1s          # 1 秒建连超时（同 Namespace 极速建连）
      http:
        idleTimeout: 60s            # 60秒空闲连接断开
        maxRequestsPerConnection: 500
```

---

### 4.2 Team2：大数据导出、慢请求类型 (Report System)

Team2 主要处理后台报表导出业务，执行时间一般长达数分钟，需要极长的超时限制及特制连接池。
- https://gateway-api.sigs.k8s.io/guides/user-guides/http-timeouts/
- https://gateway-api.sigs.k8s.io/reference/api-types/httproute/
  - 1. request is the timeout for the Gateway API implementation to send a response to a client HTTP request. This timeout is intended to cover as close to the whole request-response transaction as possible, although an implementation MAY choose to start the timeout after the entire request stream has been received instead of immediately after the transaction is initiated by the client
  - 2. backendRequest is a timeout for a single request from the Gateway to a backend. This timeout covers the time from when the request first starts being sent from the gateway to when the full response has been received from the backend. This can be particularly helpful if the Gateway retries connections to a backend.
  - Because the request timeout encompasses the backendRequest timeout, the value of backendRequest must not be greater than the value of request timeout.

Timeouts are optional, and their fields are of type Duration. A zero-valued timeout (“0s”) MUST be interpreted as disabling the timeout. A valid non-zero-valued timeout MUST be >= 1ms.
#### `team2/httproute.yaml`
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: team2-report-route
  namespace: team2
spec:
  parentRefs:
    - name: team2-listeners
      kind: ListenerSet
      group: gateway.networking.k8s.io
      sectionName: https
  hostnames:
    - "report.team2.example.com"
  rules:
    - timeouts:
        request: "600s"             # 允许长达 10 分钟
        backendRequest: "300s"      # 单次后端处理允许 5 分钟
      backendRefs:
        - name: team2-report-service
          port: 8080
```

#### `team2/destinationrule.yaml`
```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team2-report-dr
  namespace: team2
spec:
  host: team2-report-service.team2.svc.cluster.local
  trafficPolicy:
    # 💡 慢请求超时已由 team2/httproute.yaml (request: 600s, backendRequest: 300s) 承载，此处仅定义建连和连接空闲
    connectionPool:
      tcp:
        connectTimeout: 5s          # 稍长一些的建连容忍
      http:
        idleTimeout: 300s           # 契合慢长连接场景
```

---

## 5. 超时故障排查与现场诊断 (Troubleshooting Cheat Sheet)

当发生 `504 Gateway Timeout` 或 `Connection reset` 时，使用以下步骤进行诊断：

### 5.1 第一步：查看 Envoy 响应标志 (Response Flags)
响应标志是诊断网卡超时的终极武器。进入 `shared-gateway` 或 Ingress Proxy 日志：
```bash
kubectl logs -l istio=ingressgateway -n istio-system --tail=100 | grep -E "504|UT|UC"
```
**关键响应代码解读：**
*   `UT` (Upstream Timeout): **请求在 upstream 端超时**。说明你的 `HTTPRoute` 规定的超时时间到了，但后端 Pod 仍没有返回数据。
*   `UC` (Upstream Connection Termination): **连接上游失败**。说明 TCP 建连超时（检查 `DestinationRule.connectionPool.tcp.connectTimeout` 是否设得过小）。
*   `UO` (Upstream Overflow): **上游溢出**。说明连接数超出了连接池限制（检查 `connectionPool.tcp.maxConnections`）。

### 5.2 第二步：dump 运行中的 Envoy 路由配置
验证控制面（istiod）是否真的将 `HTTPRoute` 的 `timeouts.request` 下发成了底层 Envoy 路由配置：
```bash
# 获取 Ingress Gateway 的配置快照
istioctl proxy-config routes <shared-gateway-pod-name> -n istio-system -o json > gateway_routes.json
```
在导出的 `gateway_routes.json` 中搜索你的域名（如 `api.team1.example.com`），并确认 `route` 部分的 `timeout` 属性是否正确生效：
```json
"route": {
  "cluster": "outbound|8080||team1-api-service.team1.svc.cluster.local",
  "timeout": "3.000s",
  "retry_policy": {
    "num_retries": 2
  }
}
```

### 5.3 第三步：检查 GCLB 状态（若在 GKE 上运行且由外部 LB 代理）
如果 Envoy 没有产生 504 日志，但客户端收到了 504，多半是前端的 GCLB 连接超时导致的。
```bash
# 确认外部 HTTPRoute 关联的 Loadbalancer 状态
kubectl describe gateway shared-gateway -n infrastructure
```
查看底层 GCLB 监控，若其后端服务（Backend Service）响应耗时刚好停留在 30s 附近并断开，请联系平台管理员使用 `GCPBackendPolicy` 修改共享 Gateway 的 **`timeoutSec`** 属性。

---

## 6. 多租户超时配置终极检查清单 (Verification Checklist)

各 Team 在交付应用上线前，请对照此清单检查：

- [ ] **语法验证**：`HTTPRoute` 中使用的字段是 `timeouts.request` 和 `timeouts.backendRequest`，**没有**误用 `requestTimeout` 等非法词汇。
- [ ] **数值对齐**：`timeouts.backendRequest` 的大小设定必须 $\le$ `timeouts.request` 的大小。
- [ ] **池容量规划**：对流量极高的微服务，`DestinationRule` 已显示配置了 `maxConnections` 和合适（不超过60秒）的 `idleTimeout`。
- [ ] **高频保活**：gRPC 或 WebSocket 等使用 ListenerSet 引流的长期运行连接，在 `DestinationRule` 内配置了 `tcpKeepalive`。
- [ ] **应用配置匹配**：后端容器代码中自带的 HTTP 客户端超时（如 Feign 的 `readTimeout`）必须大于或等于 Envoy 路由网关配置的超时，防止上游连接池静默断开带来负面雪崩。

---

## 7. 官方权威参考规格链接 (Official Specifications Reference)

为了方便您在架构设计中查阅最新的设计文档和 API 规范，以下汇集了文中所有超时配置项对应的官方绝对链接：

*   **Kubernetes Gateway API 官方规范**:
    *   [K8s Gateway API HTTPRoute timeouts 指南](https://gateway-api.sigs.k8s.io/guides/http-timeouts/): 官方关于 `request` 和 `backendRequest` 的核心概念和实践指南。
    *   [K8s Gateway API HTTPRouteRule API 详细参考 specification](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.HTTPRouteRule): 深入查看 API 字段定义与 Duration 规范。
    *   [GEP-1742: HTTPRoute Timeouts 增强提案](https://gateway-api.sigs.k8s.io/geps/gep-1742-httproute-timeouts/): 包含路由超时的设计决策及各类网关控制器的兼容说明。
*   **Istio 官方 API 文档**:
    *   [Istio DestinationRule ConnectionPoolSettings TCP 规范](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-TCPSettings): 包括 `connectTimeout`、`idleTimeout` 及 `tcpKeepalive` 的完整参数参考。
    *   [Istio DestinationRule ConnectionPoolSettings HTTP 规范](https://istio.io/latest/docs/reference/config/networking/destination-rule/#ConnectionPoolSettings-HTTPSettings): 包括 HTTP 层面连接数、等待队列以及并发配置说明。
*   **Google Cloud (GKE) 官方文档**:
    *   [GKE Gateway API 配置自定义参数指南](https://cloud.google.com/kubernetes-engine/docs/how-to/configure-gateway-resources): 包含针对后端服务负载均衡超时的 `GCPBackendPolicy` 详解（`timeoutSec` 以及 `drainingTimeoutSec` 优雅下线配置）。

---
*文档版本: 1.2 | 维护人: 平台架构组 & AI 协同专家*
