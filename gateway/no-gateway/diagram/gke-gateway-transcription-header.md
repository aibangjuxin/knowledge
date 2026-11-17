# GKE Gateway 2.0 TLS 终止与 Host Header 转写方案

## 1. 结论先行

这个场景可以实现，但原文档里的实现方式不够可靠，需要修正：

| 判断项 | 结论 |
|---|---|
| Gateway 2.0 在 `*.appdev.abjx` 上终止 HTTPS | 可行 |
| 根据 `api1.appdev.abjx` / `api2.appdev.abjx` 分流到不同后端 | 可行 |
| 把转发给 Kong DP 的 `Host` 改成 `www.intrakong.com` | 可行，推荐用 `URLRewrite.hostname` |
| 用 `RequestHeaderModifier.set.Host` 改写 Host | 不推荐作为主方案，且原文档 YAML 写法不符合 Gateway API |
| 用 `%{request.host}%` 这类变量保留原始 Host | 不可靠，GKE Gateway 自定义 header 支持的是 Google Cloud 变量格式，例如 `{client_region}`，不是 Envoy/Nginx 风格模板 |
| `rules.matches.hostname` | 无效字段，HTTPRoute 的域名匹配应放在 `spec.hostnames`，或拆成多个 HTTPRoute |
| `api2.appdev.ajbx` | 注意拼写：如果是 `ajbx`，不被 `*.appdev.abjx` 证书覆盖 |

推荐做法：

```text
Client
  Host: api2.appdev.abjx
  TLS SNI: api2.appdev.abjx
      |
      v
GKE Gateway
  使用 *.appdev.abjx 证书终止 HTTPS
  HTTPRoute 按 host/path 分流
  URLRewrite.hostname: www.intrakong.com
      |
      v
Kong DP Service
  收到 HTTP Host: www.intrakong.com
  按 Kong Route 的 hosts/path 匹配
```

如果核心目标只是让 Kong 按 `www.intrakong.com` 的 Route 命中，应该使用 `URLRewrite.hostname`。如果还需要审计原始域名，建议在每个 HTTPRoute 里静态设置 `X-Original-Host`，例如 API2 Route 固定设置为 `api2.appdev.abjx`；不要依赖 Gateway 动态复制原始 `Host` 到自定义 header，除非已经在你的 GKE 版本中验证了对应变量可用。

---

## 2. 场景澄清

### 2.1 入口域名

你描述里出现了两个域名：

- `api1.appdev.abjx`
- `api2.appdev.ajbx` / `api2.appdev.abjx`

如果 Gateway 持有的证书是 `*.appdev.abjx`，那么它只覆盖：

- `api1.appdev.abjx`
- `api2.appdev.abjx`
- `xxx.appdev.abjx`

它不覆盖：

- `api2.appdev.ajbx`

因此本文后续统一按 `api2.appdev.abjx` 说明。如果实际是 `ajbx`，需要单独准备 `*.appdev.ajbx` 证书，或者把 listener / HTTPRoute hostname 改成对应域名。

### 2.2 目标流量

| API | Client 访问域名 | Client 路径 | Gateway 后端 | 后端期望 Host |
|---|---|---|---|---|
| API1 | `api1.appdev.abjx` | `/api1/*` | GKE runtime service | 保持 `api1.appdev.abjx` |
| API2 / common API | `api2.appdev.abjx` | `/api-path/e2e/*` | Kong DP service | 改成 `www.intrakong.com` |

### 2.3 关键边界

这里有两个不同的 TLS/HTTP 边界：

| 边界 | 说明 |
|---|---|
| Client -> Gateway | Gateway 使用 `*.appdev.abjx` 证书终止 HTTPS |
| Gateway -> Kong DP | 可以是 HTTP，也可以是 HTTPS；如果用 HTTPS，需要在 Service port 上设置 `appProtocol: HTTPS` |

GKE Gateway 到 Pod 的 HTTPS 连接默认不校验后端证书的 SAN/CN。因此 Kong DP 没有 `*.appdev.abjx` 证书不是问题；真正影响 Kong 路由命中的是 HTTP `Host` header 是否被改成 Kong 认识的 `www.intrakong.com`。

---

## 3. 推荐架构 V1

复杂度：`Moderate`

```text
                           *.appdev.abjx
Client ── HTTPS ──> GKE Gateway / Google Cloud Application Load Balancer
                          |
                          | HTTPRoute: api1.appdev.abjx
                          v
                    api1-runtime-svc

                          |
                          | HTTPRoute: api2.appdev.abjx + /api-path/e2e
                          | URLRewrite.hostname = www.intrakong.com
                          v
                    kong-dp-svc
                          |
                          | Kong Route:
                          | hosts: www.intrakong.com
                          | paths: /api-path/e2e
                          v
                    existing upstream APIs
```

设计原则：

- 在 GKE Gateway 做公网 TLS 终止和第一层 host/path 分流。
- 到 Kong DP 的 API2 流量只改写转发时的 `Host`，不改变用户访问域名。
- Kong DP 继续使用现有 Route 模型，按 `hosts + paths` 或仅 `paths` 做分发。
- API2 的路径要在 Kong 现有路径空间中单独规划，避免和已有 API 冲突。

---

## 4. 可部署配置

### 4.1 Gateway

根据实际入口选择 GatewayClass：

| 场景 | GatewayClass |
|---|---|
| 公网全局入口 | `gke-l7-global-external-managed` |
| 公网区域入口 | `gke-l7-regional-external-managed` |
| 内网区域入口 | `gke-l7-rilb` |

如果你说的“公网证书”表示外部用户直接访问，通常优先选 `gke-l7-global-external-managed` 或 `gke-l7-regional-external-managed`，不要误用 `gke-l7-rilb`。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway-2-external
  namespace: gateway-system
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*.appdev.abjx"
    tls:
      mode: Terminate
      certificateRefs:
      - name: gateway-2-external-cert
    allowedRoutes:
      namespaces:
        from: All
```

### 4.2 API1：直接转发到 GKE runtime

建议 API1 单独一个 HTTPRoute，避免在同一个 Route 里混多个 hostname 后难以排障。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api1-runtime-route
  namespace: iip
spec:
  parentRefs:
  - name: gateway-2-external
    namespace: gateway-system
    sectionName: https
  hostnames:
  - api1.appdev.abjx
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api1
    backendRefs:
    - name: api1-runtime-svc
      port: 8080
```

### 4.3 API2：转发到 Kong DP 并改写 Host

这是本需求的核心配置。使用 `URLRewrite.hostname`，不是用普通 header modifier 硬改 `Host`。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api2-kong-route
  namespace: kong-system
spec:
  parentRefs:
  - name: gateway-2-external
    namespace: gateway-system
    sectionName: https
  hostnames:
  - api2.appdev.abjx
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api-path/e2e
    filters:
    - type: URLRewrite
      urlRewrite:
        hostname: www.intrakong.com
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
        - name: X-Original-Host
          value: api2.appdev.abjx
        - name: X-Entry-Point
          value: api2
        - name: X-Upstream-Gateway
          value: gke-gateway-2
        - name: X-Forwarded-Proto
          value: https
    backendRefs:
    - name: kong-dp-svc
      port: 8000
```

转发效果：

```text
Client -> Gateway:
  Host: api2.appdev.abjx
  Path: /api-path/e2e

Gateway -> Kong:
  Host: www.intrakong.com
  Path: /api-path/e2e
  X-Original-Host: api2.appdev.abjx
  X-Entry-Point: api2
  X-Upstream-Gateway: gke-gateway-2
```

### 4.4 如果 Gateway 到 Kong 必须使用 HTTPS

在 Kong Service 的端口上声明 `appProtocol: HTTPS`：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kong-dp-svc
  namespace: kong-system
spec:
  selector:
    app: kong-dp
  ports:
  - name: proxy-https
    port: 8443
    targetPort: 8443
    appProtocol: HTTPS
```

对应 HTTPRoute：

```yaml
backendRefs:
- name: kong-dp-svc
  port: 8443
```

注意：

- GKE Gateway 到 GKE Pod 的 HTTPS 后端连接默认不校验后端证书。
- 传统 Application Load Balancer 到 GKE 后端通常不会把前端 Client SNI 原样传给后端。
- 如果 Kong DP 的 TLS 配置强依赖特定 SNI 才能完成握手，需要单独验证；更稳妥的 V1 是 Gateway -> Kong 使用集群内 HTTP，或让 Kong 的 HTTPS listener 有默认服务证书。

---

## 5. Kong DP 配置要点

Kong Route 需要和 Gateway 转发后的请求保持一致。

### 5.1 推荐 Route

```yaml
_format_version: "3.0"

services:
- name: api2-e2e-backend
  url: http://api2-backend.iip.svc.cluster.local:8080
  routes:
  - name: api2-e2e-route
    hosts:
    - www.intrakong.com
    paths:
    - /api-path/e2e
    strip_path: false
```

### 5.2 路径冲突控制

你关心的 “`api2.appdev.abjx/api-path/e2e` 不和现存 API 冲突” 应该在 Kong 侧明确治理：

| 检查项 | 建议 |
|---|---|
| Kong Route paths | 使用明确前缀，例如 `/api-path/e2e`，避免 `/api` 这种过宽前缀 |
| hosts | 如果 Kong 现有 Route 支持 host 匹配，给 common API 固定 `www.intrakong.com` |
| strip_path | 默认建议 `false`，除非后端明确要求去掉前缀 |
| priority | 如果有正则或多路径 Route，检查 Kong 实际匹配优先级 |
| 变更发布 | 先发布 Kong Route，再发布 Gateway HTTPRoute |

---

## 6. 不推荐继续使用的原文配置

### 6.1 `rules.matches.hostname`

原文类似：

```yaml
rules:
- matches:
  - path:
      type: PathPrefix
      value: /api-path/e2e
  hostname:
  - api2.appdev.abjx
```

这不是标准 HTTPRoute 结构。域名匹配应放在：

```yaml
spec:
  hostnames:
  - api2.appdev.abjx
```

如果需要同一个 Gateway 下多个域名，推荐拆成多个 HTTPRoute。

### 6.2 `RequestHeaderModifier.set` 写成 map

原文类似：

```yaml
requestHeaderModifier:
  set:
    Host: www.intrakong.com
    X-Upstream-Service: kong-dp
```

标准写法是数组：

```yaml
requestHeaderModifier:
  set:
  - name: X-Upstream-Service
    value: kong-dp
```

### 6.3 `%{request.host}%`

原文类似：

```yaml
X-Original-Host: "%{request.host}%"
```

这个变量风格不是 GKE Gateway 文档里的自定义 header 变量格式。GKE Gateway 依赖 Google Cloud Load Balancing 的变量格式，例如：

```yaml
- name: X-Client-Geo-Location
  value: "{client_region},{client_city}"
```

截至本文验证，不应把 `%{request.host}%` 当作可靠配置。

### 6.4 用普通 header modifier 改 Host

GKE Gateway 官方示例里，改写 Host 的明确方式是：

```yaml
filters:
- type: URLRewrite
  urlRewrite:
    hostname: store.example.com
```

它的语义是：转发到后端时把请求里的 `Host` 改成目标 hostname。

---

## 7. 验证步骤

### 7.1 验证 Gateway 和 HTTPRoute 被接受

```bash
kubectl get gateway -n gateway-system gateway-2-external
kubectl describe gateway -n gateway-system gateway-2-external

kubectl get httproute -A
kubectl describe httproute -n kong-system api2-kong-route
```

重点看：

- `Accepted=True`
- `Reconciled=True`
- 没有 `UnsupportedValue`
- 没有 `Invalid`

### 7.2 验证 API1

```bash
GATEWAY_IP=<gateway-ip>

curl -vk \
  --resolve api1.appdev.abjx:443:${GATEWAY_IP} \
  https://api1.appdev.abjx/api1/health
```

期望：

- TLS 证书匹配 `*.appdev.abjx`
- 请求命中 `api1-runtime-svc`
- 后端看到 `Host: api1.appdev.abjx`

### 7.3 验证 API2 到 Kong

```bash
GATEWAY_IP=<gateway-ip>

curl -vk \
  --resolve api2.appdev.abjx:443:${GATEWAY_IP} \
  https://api2.appdev.abjx/api-path/e2e/health
```

期望：

- Client 仍然访问 `api2.appdev.abjx`
- Kong access log 里看到 `Host: www.intrakong.com`
- Kong access log 或 request header 里看到 `X-Original-Host: api2.appdev.abjx`
- Kong Route 命中 `api2-e2e-route`
- 上游收到路径 `/api-path/e2e/health`

### 7.4 验证 URL map 是否生成 Host rewrite

```bash
gcloud compute url-maps list
gcloud compute url-maps describe <url-map-name> --global
```

如果是区域 Gateway：

```bash
gcloud compute url-maps describe <url-map-name> --region <region>
```

重点查是否出现类似：

```yaml
hostRewrite: www.intrakong.com
```

实际字段位置可能因 GatewayClass 和负载均衡器类型不同而不同，验证目标是确认 GKE Gateway 已把 `URLRewrite.hostname` 下发到了 Cloud Load Balancing URL map。

---

## 8. 回滚策略

### 8.1 最小回滚

删除 API2 的 HTTPRoute：

```bash
kubectl delete httproute -n kong-system api2-kong-route
```

影响范围：

- 只影响 `api2.appdev.abjx`
- 不影响 `api1.appdev.abjx`
- 不影响 Gateway listener 和证书

### 8.2 灰度发布

如果已有旧入口，建议先用一个临时域名验证：

```text
api2-canary.appdev.abjx -> Gateway -> Kong DP
```

验证完成后再把正式 DNS 或正式 HTTPRoute 切过去。

---

## 9. 替代方案

| 方案 | 说明 | 适用场景 | 不足 |
|---|---|---|---|
| 推荐：GKE Gateway `URLRewrite.hostname` | Gateway 终止 TLS、分流、改写 Host | 当前需求最匹配 | 需要确认 GKE GatewayClass 支持 `urlRewrite` |
| 让 Kong 同时接收 `api2.appdev.abjx` | Kong Route 增加 `hosts: [api2.appdev.abjx]` | 可以修改 Kong Route 时更简单 | Kong 侧暴露了入口域名概念 |
| Gateway 不改 Host，只按 Path 转发 | Kong Route 不使用 host，仅使用 path | Kong Route 空间非常清晰时 | 容易和现存 API 路径冲突 |
| 在 Kong 前再加 Nginx/Envoy | 专门做 header/path 转换 | 复杂兼容场景 | 增加一层运维复杂度，不建议 V1 |

如果能改 Kong Route，最简单的结构其实是让 Kong 同时接受：

```yaml
hosts:
- www.intrakong.com
- api2.appdev.abjx
```

这样 Gateway 不需要改写 Host，只做 TLS 终止和路由。但如果组织边界要求 Kong 只认 `www.intrakong.com`，就采用本文推荐的 `URLRewrite.hostname`。

---

## 10. 官方依据

- [GKE Deploying Gateways](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)：示例中使用 `URLRewrite.hostname`，并说明转发到后端时会把 `Host` 改成 rewrite 后的 hostname；同时说明 custom headers、redirect、URL rewrite 需要 GKE 1.27+。
- [GKE GatewayClass capabilities](https://cloud.google.com/kubernetes-engine/docs/how-to/gatewayclass-capabilities)：列出 GKE Gateway 支持的 filter 类型，包括 `requestHeaderModifier`、`responseHeaderModifier`、`requestMirror`、`requestRedirect`、`urlRewrite`，并列出 `urlRewrite.hostname` 和 `urlRewrite.path.replacePrefixMatch`。
- [Gateway API HTTPRoute spec](https://gateway-api.sigs.k8s.io/reference/spec/)：`RequestHeaderModifier` 的 `add/set` 使用 `name/value` header 数组，不是 map。
- GKE Gateway 到后端 HTTPS 使用 Service `ports[].appProtocol: HTTPS`；旧的 `networking.gke.io/app-protocol` annotation 不适用于 GKE Gateway。
- Google Cloud Load Balancing 到 GKE 后端的 TLS 默认接受后端提供的证书，不要求后端证书 SAN/CN 匹配前端 Host。

---

## 11. 最终建议

当前需求不要把它理解成“普通 header 转写”，而应该理解成：

```text
GKE Gateway 做入口 TLS 终止和 L7 分流；
HTTPRoute 对转发到 Kong 的 API2 流量做 URLRewrite.hostname；
Kong 继续按它已有的 www.intrakong.com + path 规则路由。
```

V1 推荐：

1. `api1.appdev.abjx` 和 `api2.appdev.abjx` 拆成两个 HTTPRoute。
2. API2 的 HTTPRoute 使用 `URLRewrite.hostname: www.intrakong.com`。
3. Kong Route 显式配置 `hosts: [www.intrakong.com]` 和 `paths: [/api-path/e2e]`。
4. Gateway -> Kong 优先用集群内 HTTP；如果必须 HTTPS，再用 `appProtocol: HTTPS` 并验证 Kong TLS 握手。
5. 发布前用 `kubectl describe httproute`、`curl --resolve`、Kong access log、Cloud URL map 四个点验证。

---

## 12. `*.appdev.abjx` 与具体 API 域名的匹配理解

这里容易混淆的是：`*.appdev.abjx` 主要解决的是 Gateway listener 的 TLS 证书覆盖范围，而 `api1.appdev.abjx` / `api2.appdev.abjx` 解决的是 HTTPRoute 的 L7 路由匹配。它们发生在同一条请求链路里，但不是同一个匹配动作。

### 12.1 请求进入 Gateway 的两个阶段

```text
Client 访问:
  https://api1.appdev.abjx/api1/health

阶段 1: TLS 握手
  SNI = api1.appdev.abjx
  Gateway listener hostname = *.appdev.abjx
  Gateway 证书 = *.appdev.abjx
  结果: api1.appdev.abjx 被 wildcard 覆盖，HTTPS 在 Gateway 终止成功

阶段 2: HTTP 路由
  Host = api1.appdev.abjx
  HTTPRoute hostnames = api1.appdev.abjx
  Path = /api1/health
  结果: 命中 API1 独立 HTTPRoute，转发到 api1-runtime-svc
```

所以，你的理解是对的：

- Gateway 在 `*.appdev.abjx` 上终止 HTTPS，表示这个 listener 可以接收 `api1.appdev.abjx`、`api2.appdev.abjx` 这类子域名。
- `api1.appdev.abjx` 是更具体的业务域名，可以独立配置一个 HTTPRoute。
- 请求解密之后，Gateway 根据 HTTP `Host` 和 `Path` 做 L7 匹配，命中 `api1.appdev.abjx` 对应的路由。
- API1 的独立配置可以生效，不会因为 listener 使用了 wildcard 证书而失效。

### 12.2 推荐的配置模型

```text
Gateway listener:
  hostname: "*.appdev.abjx"
  tls certificate: *.appdev.abjx

HTTPRoute for API1:
  hostnames:
  - api1.appdev.abjx
  rules:
  - /api1 -> api1-runtime-svc

HTTPRoute for API2:
  hostnames:
  - api2.appdev.abjx
  rules:
  - /api-path/e2e -> URLRewrite.hostname=www.intrakong.com -> kong-dp-svc
```

这个模型里，Gateway listener 是“入口证书和端口”，HTTPRoute 是“具体业务域名和路径路由”。生产上建议把 API1、API2 拆成独立 HTTPRoute，这样匹配关系清晰，回滚时也能只影响单个 API。

### 12.3 匹配优先级的表达方式

可以这样表达给团队：

```text
Gateway 的 wildcard hostname/certificate 负责接入范围；
HTTPRoute 的具体 hostnames 负责业务路由归属；
当具体 HTTPRoute 存在时，api1.appdev.abjx 会命中自己的 Route；
只有没有更具体业务 Route 时，才考虑是否需要兜底 Route。
```

注意不要把它描述成“证书的 `*.appdev.abjx` 和 HTTPRoute 的 `api1.appdev.abjx` 互相竞争”。更准确的说法是：

```text
先用 wildcard 证书完成 TLS 终止；
再用具体 Host 完成 HTTPRoute 匹配。
```
