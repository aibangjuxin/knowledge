# Cloud Service Mesh (ASM) 精细化流量与权限控制指南

本文档旨在解答：**在使用 Google Cloud Service Mesh (ASM / Istio) 暴露 GKE 服务时，如何针对特定 API 或用户场景，实现更精细化的配置与控制（如 API 超时截断、上传文件大小限制、用户上传权限管控等）？**

## 1. 架构选择：控制逻辑应该放在哪一层？

在深入具体配置前，首先需要厘清您的流量入口架构。根据多租户集群环境的典型情况，通常有两种实现这类精细化控制的流派：

1. **API Gateway 层（如 Kong / Apigee）** - **推荐**
   - 极其适合处理“业务形态”的需求，比如针对某个用户 ID 限流、文件大小检测、复杂的路由和协议转换。如果您已经部署了 Kong，上述功能在 Kong 中通过插件（`Rate Limiting`, `Request Size Limiting`, `OIDC`/`JWT`）实现是最简单且性能最好的。
2. **Service Mesh 层（ASM 入口 / Sidecar）** - **本文核心**
   - ASM 本质上是基于 Envoy 代理的。虽然 Envoy 非常强大，但 Service Mesh 定义的配置模型（基于 Istio CRD）偏向于“基础设施网络层”。
   - **如果您决意在 ASM 层（入站的 Ingress Gateway 或目标服务的 Sidecar 上）做拦截，ASM 完全可以实现，需要借助 `VirtualService`、`AuthorizationPolicy` 以及强悍但配置复杂的裸 `EnvoyFilter`。**

---

## 2. 场景化实现方案

以下均假设流量正在通过 ASM 控制平面，到达网关 (`istio-ingressgateway`) 或已注入 Sidecar 的 Pod。

### 场景 A：设置 API 请求的超时时间 (Timeouts)

这是 ASM 的强项，完全不需要修改代码，平台层直接控制。

**实现机制：`VirtualService`**
使用 `VirtualService` 的 `timeout` 字段，不仅可以控制超时，如果您希望遇到特定错误（如 5xx 服务器错误或超时）时自动重试，也可以配置 `retries`。

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: user-api-vs
  namespace: my-tenant
spec:
  hosts:
  - "api.my-domain-fqdn.com"
  http:
  - match:
    - uri:
        prefix: "/api/v1/upload"
    route:
    - destination:
        host: my-upload-service
    # 针对上传 API，放宽超时时间至 60 秒
    timeout: 60s 
  - route:
    - destination:
        host: my-general-service
    # 针对普通 API，严格限制 3 秒超时
    timeout: 3s
```

---

### 场景 B：限制客户端上传的文件大小 (Max Body Size)

原生的 Istio CRD (`VirtualService` / `DestinationRule`) 中 **并没有** 直接控制最大 Body 大小的友好字段。因为这是 HTTP 协议的细节缓冲控制。

**实现机制：`EnvoyFilter`**
我们要越过 Istio，直接给底层的 Envoy 代理下发配置，修改 `envoy.filters.http.buffer` 或 `http_connection_manager` 的最大请求字节数。

如果文件超载，Envoy 会直接在代理层掐断连接并返回 `HTTP 413 Payload Too Large`，根本不会让巨型请求打垮您的后端微服务 Pod。

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: upload-size-limit
  namespace: istio-system  # 若想全局生效放 istio-system，若局部生效放在业务 namespace
spec:
  # 选择器：应用到带有 istio: ingressgateway 标签的网关 Pod 上
  workloadSelector:
    labels:
      istio: ingressgateway
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: GATEWAY
      listener:
        filterChain:
          filter:
            name: "envoy.filters.network.http_connection_manager"
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.buffer
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.buffer.v3.Buffer
          # 限制最大为 10 MB (10485760 bytes)
          max_request_bytes: 10485760
```
*注意：如果不采用 `buffer` filter，高负载情况下的文件上传可能会以流的方式传输，此时应配合应用的流式读取或改用 Nginx/Kong 等专门针对大流量上传场景优化过的入口网关。*

---

### 场景 C：针对特殊端点进行用户权限拦截 (Authorization)

“是否允许某个用户上传文件？”
ASM/Istio 提供了极其强大的零信任访问控制，通过解析请求头中携带的 JWT (JSON Web Token)，直接在网关层完成角色验证。

**实现机制：`RequestAuthentication` + `AuthorizationPolicy`**

**步骤 1：让 ASM 解析并信任您的 JWT**
```yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: jwt-auth
  namespace: my-tenant
spec:
  selector:
    matchLabels:
      app: my-upload-service
  jwtRules:
  - issuer: "https://my-identity-provider.com" # 颁发 JWT 的 OIDC 提供商
    jwksUri: "https://my-identity-provider.com/.well-known/jwks.json"
    forwardOriginalToken: true
```

**步骤 2：校验 JWT 内部的 Claims (如 Role 或 Groups)**
当 JWT 解析通过后，我们可以检查用户是否有 `admin` 或者 `uploader` 的角色，如果没有，直接返回 `HTTP 403 Forbidden`。

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: require-upload-permission
  namespace: my-tenant
spec:
  selector:
    matchLabels:
      app: my-upload-service
  action: ALLOW
  rules:
  - to:
    - operation:
        methods: ["POST", "PUT"]
        paths: ["/api/v1/upload"]
    when:
    # 提取 JWT payload 中的 roles 字段，检查是否包含 uploader
    - key: request.auth.claims[roles]
      values: ["uploader", "admin"]
```

---

### 场景 D：对高并发请求进行 API 速率限制 (Rate Limiting)

如果您担心 GKE 环境里的某些 API 被恶意用户高频请求刷爆，可以在 ASM 层面采取局部的限流。

**实现机制：本地 `EnvoyFilter` 限流 (Local Rate Limiting)**
（注：全局限流需要独立部署 Redis 和 ratelimit 外部服务，在 ASM 中配置极为复杂。大多数场景下可以用 Token Bucket 的本地限流代替）

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: filter-local-ratelimit
  namespace: my-tenant
spec:
  workloadSelector:
    labels:
      app: my-upload-service
  configPatches:
  - applyTo: HTTP_FILTER
    match:
      context: SIDECAR_INBOUND
      listener:
        filterChain:
          filter:
            name: "envoy.filters.network.http_connection_manager"
    patch:
      operation: INSERT_BEFORE
      value:
        name: envoy.filters.http.local_ratelimit
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
          stat_prefix: http_local_rate_limiter
          token_bucket:
            max_tokens: 100 # 这个 Pod 最多容忍 100 个并发请求
            tokens_per_fill: 10 # 补充令牌的速度
            fill_interval: 1s # 每秒补充 10 个令牌
          filter_enabled:
            runtime_key: local_rate_limit_enabled
            default_value:
              numerator: 100
              denominator: HUNDRED
          filter_enforced:
            runtime_key: local_rate_limit_enforced
            default_value:
              numerator: 100
              denominator: HUNDRED
```

---

## 3. 运维与落地总结

| 需求 | ASM 中的实现手段 | 是否推荐在 ASM 中做？ | 替代方案（如果不用 ASM）|
|---|---|---|---|
| **API 超时 / 重试** | `VirtualService` 路由属性 | ✅ **强烈推荐**，这是服务网格的内建强项 | 代码逻辑实现，或 Nginx/Kong 配置 |
| **细粒度权限 (JWT)** | `AuthorizationPolicy` | ✅ **推荐**，提供服务间及入向的零信任防护 | 应用中间件 (Spring Auth 等) |
| **最大上传文件限制** | `EnvoyFilter` (buffer) | ⚠️ **勉强推荐**，维护晦涩的 EnvoyFilter 不直观 | 建议放在最外层 GLB/WAF 或 Kong 中拦截 |
| **API QPS 限流** | `EnvoyFilter` (local ratelimit)| ⚠️ **勉强推荐**，需操作底层 Envoy 配置 | 强烈建议使用专门的 API Gateway (如 Kong) |
| **防抖、Header 改写**| `VirtualService` 或 `EnvoyFilter`| 🆗 **视情况而定** | API Gateway 层处理 |

### 针对您当前的基础设施建议：
鉴于您的环境是一个带有北向 Global Load Balancer，且即将拥抱 Kong 和 GKE 的综合性平台：
- **强烈保留** 将 `Timeout` 和 `JWT Authorization` 规则下沉到 ASM/GKE 的 Sidecar 层进行配置。这有助于您的微服务之间也能互相信任并获得自我保护。
- **重新考虑** 像“上传大小限制”、“高频并发防刷限制” 这种极度偏离后端业务、偏向边缘防护的需求，最好放在 **GCP Cloud Armor (利用 WAF Size limits 拦截)** 或者 **Kong API Gateway 插件** 层面完成，从而使得整个流量在落到 GKE Node 之前就已经被健康过滤。
