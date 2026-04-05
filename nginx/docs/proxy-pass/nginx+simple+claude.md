# Nginx + Runtime Gateway + Pod 端到端 TLS 方案（Claude 整理版）

> 基于 `nginx+simple+chatgpt.md` 中的 Requirements 与 Target，整理结论并补充详细的 VirtualService 配置参考。

---

## 0. 需求回顾

### 硬约束（不可妥协）

| 约束                 | 说明                                                                    |
| -------------------- | ----------------------------------------------------------------------- |
| 统一外部域名         | 访问域名始终为 `{apiname}.{team}.appdev.aibang`，不做任何 Host 改写     |
| 全链路 TLS           | Client → Nginx → Gateway → Pod 每一跳都必须加密                         |
| Pod 终止业务 TLS     | Pod 自己挂载 team wildcard 证书并监听 HTTPS，Gateway → Pod 不能降级明文 |
| Pod-to-Pod 也要加密  | east-west 流量也必须 TLS                                                |
| 证书统一             | 尽量复用同一套 `*.{team}.appdev.aibang` wildcard 证书                   |
| Gateway 作为标准模板 | runtime Gateway 由平台维护，用户只关注 runtime 侧资源                   |

### 核心前提（必须接受）

如果坚持 Pod-to-Pod 复用同一套 wildcard 证书，那么内部调用**不能**依赖：

```
service.namespace.svc.cluster.local
```

必须改为：

```
https://apiX.{team}.appdev.aibang
```

因为证书 SAN 校验是和主机名绑定的，`cluster.local` 不在 wildcard `*.{team}.appdev.aibang` 的覆盖范围内。

---

## 1. 架构结论

### 1.1 推荐方案：Gateway SIMPLE + DestinationRule TLS

**为什么不选 PASSTHROUGH？**

原始文档已经分析了两条路：

| 方案                                                 | Gateway 是否解密 | VS 路由类型       | Pod 是否加密 | 是否保留 HTTP 七层能力 |
| ---------------------------------------------------- | ---------------- | ----------------- | ------------ | ---------------------- |
| `PASSTHROUGH + VirtualService.tls + sniHosts`        | ❌ 否             | `tls:` + sniHosts | ✅ 是         | ❌ 否                   |
| `SIMPLE + VirtualService.http + DestinationRule.tls` | ✅ 是             | `http:`           | ✅ 是         | ✅ 是                   |

**结论：优先选 `SIMPLE + http + DestinationRule.tls`。**

原因：

1. 你的域名模型是 `{apiname}.{team}.appdev.aibang`，一个 API 一个子域名，虽然 SNI 路由理论上够用，但保留 HTTP 七层能力（path 路由、header 注入、HTTP 重试、JWT 鉴权）成本几乎为零，放弃它没有收益。
2. `PASSTHROUGH` 的唯一真正优点是"避免 Gateway 持有私钥"，但你已经要求 Nginx 和 Pod 都持有，Gateway 多持一份不是瓶颈问题。
3. `SIMPLE` 模式下，后端 Pod 仍然可以继续终止 TLS（通过 DestinationRule 控制），满足"Pod 自己持有业务 TLS"的目标。

> **唯一应该切换到 PASSTHROUGH 的场景**：你明确不需要任何 HTTP 七层路由，且强调 TLS 会话不在 Gateway 层解密（例如监管合规要求）。

### 1.2 三层 TLS 职责分工

```
Client                     Nginx                    Runtime Gateway              Pod
  |                          |                            |                        |
  |---TLS(*.team.appdev)---> |                            |                        |
  |                   terminate TLS                       |                        |
  |                          |---TLS(*.team.appdev)-----> |                        |
  |                          |                      terminate TLS                  |
  |                          |                            |---TLS(DestinationRule)->|
  |                          |                            |                  terminate TLS
  |                          |                            |                        |
```

| 层              | 对象                                          | TLS 作用                 |
| --------------- | --------------------------------------------- | ------------------------ |
| Nginx           | `ssl_certificate`                             | 终止外部 Client TLS      |
| Nginx → Gateway | `proxy_ssl_server_name` + `proxy_ssl_name`    | re-encrypt，保持原始 SNI |
| Gateway         | `Gateway.tls.mode: SIMPLE` + `credentialName` | 终止 Nginx → Gateway TLS |
| Gateway → Pod   | `DestinationRule.trafficPolicy.tls`           | 发起新 TLS 到后端 Pod    |
| Pod             | 应用自身监听 HTTPS 端口                       | 终止最终业务 TLS         |

### 1.3 最重要的架构判断

整个方案真正的难点不在 Nginx，不在 Gateway，而在：

> **`apiX.{team}.appdev.aibang` 如何在集群内部稳定解析到目标工作负载？**

East-West 解析的三种选择：

| 方式                         | 优点                | 缺点                               | 推荐度 |
| ---------------------------- | ------------------- | ---------------------------------- | ------ |
| 内部 DNS 直接指向 Service IP | 最直接，路径最短    | 需要内部 DNS 管理                  | ⭐⭐⭐    |
| ServiceEntry + mesh 注册     | mesh-native，更统一 | 需要额外资源设计，DNS 解析仍有问题 | ⭐⭐⭐    |
| 内部回到 Gateway 再转发      | 最容易统一          | 路径较长，非最短                   | ⭐⭐     |
| 只用 `cluster.local`         | 最简单（运维侧）    | ❌ 证书 SAN 不匹配                  | ❌      |

**推荐优先验证**：ServiceEntry `MESH_INTERNAL` + DNS 解析指向 Service ClusterIP，让 mesh 内部的 `api1.{team}.appdev.aibang` 直接命中后端 Service，不回流到 Gateway。

---

## 2. 完整配置示例

> 以下以 `abjx` team、`api1.abjx.appdev.aibang` 为例。

### 2.1 Nginx（平台侧 - 不做 Host 改写）

```nginx
server {
    listen 443 ssl http2;
    server_name *.abjx.appdev.aibang;

    ssl_certificate     /etc/pki/tls/certs/wildcard-abjx-appdev-aibang.crt;
    ssl_certificate_key /etc/pki/tls/private/wildcard-abjx-appdev-aibang.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_timeout 5m;

    # 关键：不改写 Host，保持原始 SNI
    proxy_set_header Host             $host;
    proxy_set_header X-Original-Host  $host;
    proxy_set_header X-Forwarded-For  $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-aibang-CAP-Correlation-Id $request_id;

    proxy_http_version 1.1;
    proxy_set_header   Connection "";
    client_max_body_size 50m;
    underscores_in_headers on;

    location / {
        proxy_pass https://runtime-istio-ingressgateway.abjx-int.svc.cluster.local:443;

        # 关键：透传原始 SNI 到 Gateway
        proxy_ssl_server_name on;
        proxy_ssl_name        $host;

        # 生产环境建议替换成内部 CA 校验
        proxy_ssl_verify off;
    }
}
```

### 2.2 Gateway（平台侧标准模板）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: runtime-team-gateway
  namespace: abjx-int
spec:
  selector:
    app: runtime-istio-ingressgateway
  servers:
  - port:
      number: 443
      name: https-team
      protocol: HTTPS
    hosts:
    - "*.abjx.appdev.aibang"
    tls:
      mode: SIMPLE
      credentialName: wildcard-abjx-appdev-aibang-cert   # 引用同一套 team wildcard 证书
      minProtocolVersion: TLSV1_2
```

### 2.3 VirtualService（用户侧 - 每个 API 一份）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api1-abjx-vs
  namespace: abjx-int
spec:
  gateways:
  - runtime-team-gateway
  hosts:
  - api1.abjx.appdev.aibang
  http:
  - name: route-api1
    match:
    - uri:
        prefix: /
    route:
    - destination:
        host: api1-backend.abjx-int.svc.cluster.local
        port:
          number: 8443
    timeout: 60s
    retries:
      attempts: 2
      perTryTimeout: 20s
      retryOn: gateway-error,connect-failure,reset
```

### 2.4 DestinationRule（用户侧 - 控制 Gateway → Pod TLS）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: api1-backend-dr
  namespace: abjx-int
spec:
  host: api1-backend.abjx-int.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: api1.abjx.appdev.aibang          # SNI 保持业务域名
      # 生产建议补充 CA 校验：
      # caCertificates: /etc/ssl/certs/ca-bundle.crt
```

### 2.5 ServiceEntry（用于 east-west 解析）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: api1-abjx-se
  namespace: abjx-int
spec:
  hosts:
  - api1.abjx.appdev.aibang
  location: MESH_INTERNAL
  ports:
  - number: 443
    name: https
    protocol: TLS
  resolution: DNS
```

### 2.6 East-West DestinationRule

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: api1-abjx-eastwest-dr
  namespace: abjx-int
spec:
  host: api1.abjx.appdev.aibang
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: api1.abjx.appdev.aibang
```

### 2.7 Secret（team wildcard 证书）

```yaml
# Gateway 引用的证书 Secret（放在 istio-system 或 Gateway 所在 ns）
apiVersion: v1
kind: Secret
metadata:
  name: wildcard-abjx-appdev-aibang-cert
  namespace: istio-system          # credentialName 引用时从这里找
type: kubernetes.io/tls
data:
  tls.crt: <BASE64_CERT>
  tls.key: <BASE64_KEY>
---
# Pod 挂载的证书 Secret
apiVersion: v1
kind: Secret
metadata:
  name: wildcard-abjx-appdev-aibang-pod-cert
  namespace: abjx-int
type: kubernetes.io/tls
data:
  tls.crt: <BASE64_CERT>
  tls.key: <BASE64_KEY>
```

### 2.8 Deployment（用户侧 - Pod 监听 HTTPS）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api1
  namespace: abjx-int
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api1
  template:
    metadata:
      labels:
        app: api1
    spec:
      containers:
      - name: api1
        image: your-registry/api1:latest
        ports:
        - containerPort: 8443
          name: https
        volumeMounts:
        - name: tls-cert
          mountPath: /etc/tls
          readOnly: true
        env:
        - name: TLS_CERT_FILE
          value: /etc/tls/tls.crt
        - name: TLS_KEY_FILE
          value: /etc/tls/tls.key
      volumes:
      - name: tls-cert
        secret:
          secretName: wildcard-abjx-appdev-aibang-pod-cert
```

### 2.9 Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api1-backend
  namespace: abjx-int
spec:
  selector:
    app: api1
  ports:
  - name: https
    port: 8443
    targetPort: 8443
    protocol: TCP
```

---

## 3. VirtualService 详解（重点学习参考）

> 这一节专门梳理 `VirtualService` 的语法、字段含义和常用规则，帮助理解如何配置路由。

### 3.1 VirtualService 是什么

`VirtualService` 定义了流量从 Gateway（或 mesh 内部）到后端的路由规则，相当于 Nginx 里的 `location` 块，但能力更强。

- 它不决定是否加密（那是 DestinationRule 的职责）。
- 它不持有证书（那是 Gateway 的职责）。
- 它只负责：**匹配 → 选路 → 转发策略**。

### 3.2 顶层字段结构

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: <name>
  namespace: <namespace>
spec:
  hosts:       # 该 VS 生效的目标主机名（必填）
  gateways:    # 生效的 Gateway，不填则只在 mesh 内生效
  http:        # HTTP/HTTPS 路由规则（Gateway 已解密时使用）
  tls:         # TLS/HTTPS 路由规则（Gateway PASSTHROUGH 时使用）
  tcp:         # TCP 路由规则（4 层）
  exportTo:    # 控制 VS 对哪些命名空间可见，默认 * (全局)
```

### 3.3 `hosts` 字段

```yaml
hosts:
- api1.abjx.appdev.aibang           # 精确域名
# 或
- "*.abjx.appdev.aibang"            # wildcard（仅 mesh 内部 VS 支持）
```

**注意**：
- `hosts` 里的域名决定这个 VS 拦截哪些目标流量。
- 如果 VS 绑定了 Gateway，`hosts` 必须和 Gateway 的 `hosts` 有交集，否则不生效。
- `hosts` 可以是多个，但通常一个 VS 只管一个 API 域名最清晰。

### 3.4 `gateways` 字段

```yaml
gateways:
- runtime-team-gateway                    # 同 namespace 内的 Gateway 名
- abjx-int/runtime-team-gateway           # 跨 namespace 写法
- mesh                                    # 特殊值：只在 mesh 内部生效（east-west）
```

**同时绑定 Gateway 和 mesh**（north-south + east-west 共用同一份 VS）：

```yaml
gateways:
- runtime-team-gateway
- mesh
```

这样外部流量和内部 Pod-to-Pod 流量都会走这份 VS 的路由规则。

### 3.5 `http` 路由规则详解

`http` 规则是 Gateway `SIMPLE` 模式下最常用的路由块，支持最丰富的七层能力。

#### 基本路由

```yaml
http:
- name: route-default
  route:
  - destination:
      host: api1-backend.abjx-int.svc.cluster.local
      port:
        number: 8443
```

#### 按 URI 前缀匹配

```yaml
http:
- name: route-v2
  match:
  - uri:
      prefix: /v2          # 前缀匹配
  route:
  - destination:
      host: api1-v2.abjx-int.svc.cluster.local
      port:
        number: 8443
- name: route-default
  route:
  - destination:
      host: api1-v1.abjx-int.svc.cluster.local
      port:
        number: 8443
```

#### URI 匹配方式（三选一）

```yaml
match:
- uri:
    exact: /api/health     # 精确匹配
# 或
- uri:
    prefix: /api           # 前缀匹配
# 或
- uri:
    regex: /api/v[0-9]+/.*  # 正则匹配
```

#### Header 匹配

```yaml
match:
- headers:
    x-canary:
      exact: "true"        # Header 值精确匹配
# 或
- headers:
    x-version:
      prefix: "v2"
# 或
- headers:
    x-debug:
      regex: ".+"          # Header 存在即匹配
```

#### 多条件 AND 匹配

同一个 `match` 块内的条件是 **AND** 关系：

```yaml
match:
- uri:
    prefix: /api
  headers:
    x-canary:
      exact: "true"
  method:
    exact: POST
```

#### 多条件 OR 匹配

多个 `match` 块之间是 **OR** 关系：

```yaml
match:
- uri:
    prefix: /api/v1
- uri:
    prefix: /api/v2
```

### 3.6 `route` 字段详解

#### 单后端

```yaml
route:
- destination:
    host: api1-backend.abjx-int.svc.cluster.local
    port:
      number: 8443
```

#### 加权流量分割（灰度/金丝雀）

```yaml
route:
- destination:
    host: api1-backend-v2.abjx-int.svc.cluster.local
    port:
      number: 8443
  weight: 10              # 10% 流量到新版本
- destination:
    host: api1-backend-v1.abjx-int.svc.cluster.local
    port:
      number: 8443
  weight: 90              # 90% 流量到老版本
```

#### 指定子集（配合 DestinationRule subset 使用）

```yaml
route:
- destination:
    host: api1-backend.abjx-int.svc.cluster.local
    subset: v2            # 对应 DestinationRule 中定义的 subset
    port:
      number: 8443
```

### 3.7 超时与重试

```yaml
http:
- name: route-api1
  route:
  - destination:
      host: api1-backend.abjx-int.svc.cluster.local
      port:
        number: 8443
  timeout: 30s            # 整体超时
  retries:
    attempts: 3           # 最多重试 3 次
    perTryTimeout: 10s    # 每次重试超时
    retryOn: >            # 触发重试的条件（逗号分隔）
      gateway-error,connect-failure,reset,retriable-4xx
```

常用 `retryOn` 值：

| 值                | 含义                   |
| ----------------- | ---------------------- |
| `gateway-error`   | 502/503/504 等网关错误 |
| `connect-failure` | 连接失败               |
| `reset`           | 连接被重置             |
| `retriable-4xx`   | 可重试的 4xx（409 等） |
| `refused-stream`  | HTTP/2 stream 被拒绝   |
| `5xx`             | 任意 5xx（谨慎使用）   |

### 3.8 URI Rewrite

```yaml
http:
- match:
  - uri:
      prefix: /old-api
  rewrite:
    uri: /new-api         # 重写路径前缀
  route:
  - destination:
      host: api1-backend.abjx-int.svc.cluster.local
      port:
        number: 8443
```

也可以重写 Authority（Host）：

```yaml
rewrite:
  authority: api1-internal.abjx-int.svc.cluster.local
```

### 3.9 Header 操作

```yaml
http:
- name: route-with-headers
  route:
  - destination:
      host: api1-backend.abjx-int.svc.cluster.local
      port:
        number: 8443
  headers:
    request:
      add:
        x-injected-by: istio-gateway          # 注入请求 header
        x-team: abjx
      remove:
      - x-internal-debug                       # 删除请求 header
      set:
        x-env: production                      # 覆盖/设置请求 header
    response:
      add:
        x-served-by: api1                      # 注入响应 header
      remove:
      - x-powered-by
```

### 3.10 故障注入（测试用）

```yaml
http:
- name: fault-inject-test
  match:
  - headers:
      x-test-fault:
        exact: "true"
  fault:
    delay:
      percentage:
        value: 50         # 50% 的请求延迟 3s
      fixedDelay: 3s
    abort:
      percentage:
        value: 10         # 10% 的请求直接返回 503
      httpStatus: 503
  route:
  - destination:
      host: api1-backend.abjx-int.svc.cluster.local
      port:
        number: 8443
```

### 3.11 `tls` 路由规则（Gateway PASSTHROUGH 模式专用）

当 Gateway 使用 `PASSTHROUGH` 时，VS 改用 `tls:` 路由块，基于 SNI 而非 HTTP 内容做路由：

```yaml
tls:
- match:
  - port: 443
    sniHosts:
    - api1.abjx.appdev.aibang
  route:
  - destination:
      host: api1-backend.abjx-int.svc.cluster.local
      port:
        number: 8443
```

**`tls:` 路由的限制**：

| 能力                | `http:` 路由 | `tls:` 路由 |
| ------------------- | ------------ | ----------- |
| URI/path 匹配       | ✅            | ❌           |
| Header 匹配         | ✅            | ❌           |
| Header 注入/改写    | ✅            | ❌           |
| URI rewrite         | ✅            | ❌           |
| 加权流量分割        | ✅            | ✅           |
| 按 SNI Host 路由    | ❌            | ✅           |
| 超时/重试（HTTP级） | ✅            | ❌           |

### 3.12 `tcp` 路由规则（四层 TCP 透传）

```yaml
tcp:
- match:
  - port: 9000
  route:
  - destination:
      host: api1-tcp.abjx-int.svc.cluster.local
      port:
        number: 9000
```

适用场景：数据库连接、消息队列等非 HTTP 协议。

### 3.13 `exportTo` 字段（命名空间可见性）

```yaml
exportTo:
- "."          # 只在当前 namespace 可见
- "*"          # 对所有 namespace 可见（默认）
- "abjx-int"   # 只对指定 namespace 可见
```

建议：平台侧 VS 通常设置 `"."` 做隔离，用户侧 VS 默认即可。

### 3.14 金丝雀发布完整示例

结合 Header 匹配实现灰度：

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api1-canary-vs
  namespace: abjx-int
spec:
  gateways:
  - runtime-team-gateway
  hosts:
  - api1.abjx.appdev.aibang
  http:
  # 规则 1：Header 标记的内测用户走新版本
  - name: canary-route
    match:
    - headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: api1-backend.abjx-int.svc.cluster.local
        subset: v2
        port:
          number: 8443
  # 规则 2：其余流量 10% 飞越新版本，90% 走老版本
  - name: stable-route
    route:
    - destination:
        host: api1-backend.abjx-int.svc.cluster.local
        subset: v2
        port:
          number: 8443
      weight: 10
    - destination:
        host: api1-backend.abjx-int.svc.cluster.local
        subset: v1
        port:
          number: 8443
      weight: 90
    timeout: 60s
    retries:
      attempts: 2
      perTryTimeout: 20s
      retryOn: gateway-error,connect-failure,reset
```

配套 DestinationRule（定义 subset + TLS origination）：

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: api1-backend-dr
  namespace: abjx-int
spec:
  host: api1-backend.abjx-int.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: api1.abjx.appdev.aibang
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

---

## 4. 职责边界总结

### 4.1 平台团队负责

| 资源                       | 说明                              |
| -------------------------- | --------------------------------- |
| Nginx 配置模板             | re-encrypt，保持原始 SNI          |
| `Gateway`                  | team 级标准 HTTPS 入口            |
| `Secret`（Gateway 用）     | wildcard 证书下发到 Gateway       |
| `ServiceEntry` 模板        | 支持 east-west 业务域名解析       |
| 证书签发、分发、轮换、审计 | 保障三层（Nginx/Gateway/Pod）同步 |

### 4.2 API Owner 负责

| 资源                     | 说明                               |
| ------------------------ | ---------------------------------- |
| `VirtualService`         | 按业务域名定义路由规则             |
| `DestinationRule`        | 控制 Gateway → Pod 的 TLS 策略     |
| `Deployment/StatefulSet` | Pod 监听 HTTPS，挂载 wildcard 证书 |
| `Service`                | 暴露 HTTPS 端口                    |
| `Secret`（Pod 用）       | 挂载到 Pod 的 wildcard 证书        |

---

## 5. 验证清单

### 5.1 North-South 验证

```bash
# 从外部验证全链路 TLS
curl --resolve api1.abjx.appdev.aibang:443:<NGINX_IP> \
     https://api1.abjx.appdev.aibang/healthz -v

# 检查 Nginx 是否保留了原始 Host
# 看 Gateway 日志确认 Host = api1.abjx.appdev.aibang

# 检查 Gateway 是否匹配到了正确的 VirtualService
istioctl proxy-config routes <gateway-pod> -n abjx-int

# 检查 DestinationRule 是否生效（Gateway → Pod TLS）
istioctl proxy-config cluster <gateway-pod> -n abjx-int | grep api1-backend
```

### 5.2 East-West 验证

```bash
# 从 api2 Pod 内部调用 api1（使用业务域名，不能用 cluster.local）
kubectl exec -n abjx-int -it <api2-pod> -- \
  curl https://api1.abjx.appdev.aibang/healthz -v

# 确认 api1 返回的证书 SAN 覆盖 api1.abjx.appdev.aibang
kubectl exec -n abjx-int -it <api2-pod> -- \
  openssl s_client -connect api1.abjx.appdev.aibang:443 -servername api1.abjx.appdev.aibang
```

### 5.3 证书 SAN 验证

```bash
# 检查 Pod 证书的 SAN 是否包含 *.abjx.appdev.aibang
openssl x509 -in wildcard.crt -text -noout | grep -A1 "Subject Alternative Name"
```

---

## 6. 关键风险与应对

| 风险                   | 影响                       | 应对措施                                 |
| ---------------------- | -------------------------- | ---------------------------------------- |
| 证书分发面扩大         | Nginx / Gateway / Pod 三层 | 统一证书管理平台（cert-manager / Vault） |
| 证书轮换不同步         | 任一层过期即中断           | 自动轮换 + 提前告警，`not-after` 监控    |
| East-West 域名解析失败 | Pod-to-Pod 不通            | 提前验证 ServiceEntry DNS 解析           |
| Pod 应用不支持 HTTPS   | 无法接收 TLS 流量          | 应用接入规范强制要求 HTTPS               |
| 私钥暴露面增加         | 三层都持有私钥             | Secret 最小权限，审计 + 轮换 SLA         |
| DestinationRule 缺失   | Gateway → Pod 降级为明文   | 平台侧 Linting 检查，要求 VS 必须配套 DR |

---

## 7. 两方案最终对比

| 维度                  | 方案 A：`SIMPLE + http + DR.tls`（推荐）  | 方案 B：`PASSTHROUGH + tls + sniHosts` |
| --------------------- | ----------------------------------------- | -------------------------------------- |
| Gateway 是否持有私钥  | ✅ 需要                                    | ❌ 不需要                               |
| Pod 是否终止 TLS      | ✅ 是                                      | ✅ 是                                   |
| HTTP 七层路由能力     | ✅ 完整                                    | ❌ 仅 SNI 路由                          |
| path 路由             | ✅ 支持                                    | ❌ 不支持                               |
| header 注入/改写      | ✅ 支持                                    | ❌ 不支持                               |
| 金丝雀发布（HTTP 级） | ✅ 支持                                    | ❌ 不支持                               |
| 配置复杂度            | 中（需要 Gateway + VS + DR）              | 低（Gateway + VS，无 DR）              |
| Pod-to-Pod 证书复用   | ✅ 通过 ServiceEntry + DR 实现             | ✅ 通过 ServiceEntry + DR 实现          |
| 推荐场景              | 需要 HTTP 治理能力，并且 Pod 也要终止 TLS | 只需 SNI 路由，不需要 HTTP 七层能力    |

---

## References

- [Istio Gateway reference](https://preliminary.istio.io/latest/docs/reference/config/networking/gateway/)
- [Istio VirtualService reference](https://istio.io/latest/docs/reference/config/networking/virtual-service/)
- [Istio DestinationRule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/)
- [Istio ServiceEntry reference](https://preliminary.istio.io/latest/docs/reference/config/networking/service-entry/)
- [Istio TLS origination](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-tls-origination/)
- [Kubernetes TLS Secret](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Set up TLS termination in ingress gateway](https://cloud.google.com/service-mesh/docs/operate-and-maintain/gateway-tls-termination)
