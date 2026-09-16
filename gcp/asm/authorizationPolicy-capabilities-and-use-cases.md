# Istio AuthorizationPolicy 能力矩阵与实战场景

> 适用环境:GKE / Google Cloud Service Mesh(ASM)/ Upstream Istio · sidecar 模式 · `security.istio.io/v1`
>
> 与 `authorizationPolicy-and-Peerauthentication.md` 配套 — 那篇讲概念、与 `PeerAuthentication` 的分工和模板化;**这篇专门回答「它到底能控制什么、能用在哪」**。

---

## 0. 一句话定位

`AuthorizationPolicy` 解决的是「**流量到了 sidecar 之后,放不放行 / 让谁放行 / 在什么条件下放行**」。

它能控制的维度,本质只有四类:

| 维度 | 字段 | 类比防火墙 |
|---|---|---|
| **谁**(caller) | `source.principals` / `source.namespaces` / `source.serviceAccounts` / `source.ipBlocks` / `source.remoteIpBlocks` / `requestPrincipals` / `notXxx` 系列 | Source IP / Caller Identity |
| **做什么**(operation) | `operation.hosts` / `methods` / `paths` / `ports` | L7 协议字段 |
| **附加条件** | `when:[{key, values/notValues}]` | L7 attribute 匹配 |
| **动作** | `action: ALLOW / DENY / AUDIT / CUSTOM` | Accept / Drop / Log / 委托外部 |

**所有用例,都是这四类的组合。**

---

## 1. 资源结构骨架

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: <rule-name>
  namespace: <ns>                     # 作用命名空间;root namespace = mesh-wide
  annotations:
    "istio.io/dry-run": "true"        # 可选:演练模式,不真拦截
spec:
  selector:                            # 可选:限定到具体 workload
    matchLabels:
      app: api-a
  # ── 关键四元组 ──
  action: ALLOW                        # ALLOW | DENY | AUDIT | CUSTOM
  rules:
    - from:                            # 1. 谁
        - source:
            principals: [...]
      to:                              # 2. 做什么
        - operation:
            hosts: [...]
            methods: [...]
            paths: [...]
            ports: [...]
      when:                            # 3. 附加条件(AND)
        - key: request.auth.claims[team]
          values: ["team-a"]
  provider:                            # 仅 action=CUSTOM 时
    name: ext-authz
```

**匹配语义**:
- `rules` 之间是 **OR**(任一 rule 命中即触发该 rule 的 action)
- 单个 rule 内 `from` / `to` / `when` 之间是 **AND**(每个都至少一条命中)
- 单个 rule 的 `from[*]` 之间是 **OR**(任一 source 命中)
- `when[*]` 之间是 **AND**(全部条件命中)

**`spec: {}`(空 spec)= 默认 deny all** · **`rules: [{}]` = 默认 allow all**

---

## 2. 四种 action:什么时候用哪个

```
┌──────────┬────────────────────────────────────────────────────────────────────┐
│ ALLOW    │ 默认动作;没匹配的请求 → ALLOW 失败 → deny                        │
│          │ 用法:白名单模型;namespace / API 基线                              │
├──────────┼────────────────────────────────────────────────────────────────────┤
│ DENY     │ 命中规则的请求被拒绝;其余仍按 ALLOW 评估                          │
│          │ 用法:快速打补丁 / 黑名单 / 临时封禁某 IP / SA                     │
│          │ 注意:TCP 协议上 DENY 的属性缺失会被当匹配,务必 scope 到具体 port   │
├──────────┼────────────────────────────────────────────────────────────────────┤
│ AUDIT    │ 不影响放行;只把"被命中"的请求标记为"需要审计"                    │
│          │ 用法:合规留痕 / 等保审计;实际审计需要配套 envoy plugin            │
│          │ 实战:从「完全没审计」→「先 AUDIT 影子观察」→「改 ALLOW 真生效」   │
├──────────┼────────────────────────────────────────────────────────────────────┤
│ CUSTOM   │ 调用外部 authorization provider(envoy ext_authz / OPA 等)       │
│          │ CUSTOM 先评估;即使返回 allow,仍需 ALLOW 规则通过                  │
│          │ 用法:把复杂业务授权(角色 / 字段级 / 动态策略)委外                  │
└──────────┴────────────────────────────────────────────────────────────────────┘
```

**评估顺序(同一 workload 同时存在多种 action 时)**:
```
CUSTOM → DENY → ALLOW
```
任一阶段拒绝即终止;只有所有允许阶段都通过才真正放行。

---

## 3. 能力矩阵(字段全表)

### 3.1 source — 控制"谁可以访问我"

| 字段 | 取值 | 含义 | 依赖 |
|---|---|---|---|
| `principals` | SPIFFE 列表 | peer 证书里的服务身份 | **mTLS 必需** |
| `notPrincipals` | SPIFFE 列表 | 反向排除 peer 身份 | mTLS |
| `namespaces` | namespace 列表 | 来源命名空间(peer cert) | mTLS |
| `notNamespaces` | namespace 列表 | 反向排除 | mTLS |
| `serviceAccounts` | `<ns>/<sa>` | K8s SA 简写形式 | mTLS |
| `notServiceAccounts` | 同上 | 反向排除 | mTLS |
| `ipBlocks` | CIDR / IP | **source.ip**(直连客户端 IP) | 任意 |
| `notIpBlocks` | CIDR / IP | 反向排除 | 任意 |
| `remoteIpBlocks` | CIDR / IP | **remote.ip**(`X-Forwarded-For`/proxy protocol) | 网关 `topology.numTrustedProxies` |
| `notRemoteIpBlocks` | CIDR / IP | 反向排除 | 同上 |
| `trustDomains` | trust domain | SPIFFE trust domain | mTLS |
| `requestPrincipals` | `<iss>/<sub>` | JWT 主体身份 | RequestAuthentication |
| `notRequestPrincipals` | 同上 | 反向排除 | 同上 |

**容易混的两对**:

| 字段 | 谁是谁 |
|---|---|
| `ipBlocks` ↔ `source.ip` | **直连客户端** 的 IP(经过 LB / gateway 转发后会被改写) |
| `remoteIpBlocks` ↔ `remote.ip` | **原始客户端** 的 IP(从 `X-Forwarded-For` 取回) |

→ 网关后面挂的真实业务,**基本都要用 `remoteIpBlocks`**,否则你拿到的是 sidecar 的同节点 IP。

### 3.2 operation — 控制"可以访问我做什么"

| 字段 | 协议 | 含义 |
|---|---|---|
| `hosts` | HTTP | HTTP Host header(大小写不敏感) |
| `methods` | HTTP | GET / POST / PUT / DELETE(grpc 总是 POST) |
| `paths` | HTTP | URL path;支持 `*` 前/后缀、`{*}` / `{**}` Envoy URI template |
| `ports` | TCP+HTTP | 目标端口(注意是 sidecar 看到的端口,不是 service port) |
| `notHosts` / `notMethods` / `notPaths` / `notPorts` | 同上 | 反向排除 |

**path 通配语法**(`{*}` 单段、`{**}` 多段、必须在末尾):

```yaml
paths:
  - "/foo/{*}"          # 匹配 /foo/bar,不匹配 /foo/bar/baz
  - "/foo/{**}/"        # 匹配 /foo/bar/、/foo/bar/baz.txt、/foo//,不匹配 /foo/bar
  - "/foo/{*}/bar/{**}" # 匹配 /foo/buzz/bar/、/foo/buzz/bar/baz
```

### 3.3 when — 控制"还有什么附加条件必须满足"

`when` 是 AuthorizationPolicy 最容易被低估的能力。每条 `when` 是一个 `{key, values, notValues}`,key 是 Istio attribute 名。

完整 attribute 列表(直接来自 Istio 官方):

| Key | 协议 | 典型值 | 用途 |
|---|---|---|---|
| `request.headers[<name>]` | HTTP | `["Mozilla/*", "*"]` | **任意 HTTP header** |
| `source.ip` | 任意 | CIDR / IP | 来源 IP(等于 `source.ipBlocks`) |
| `source.namespace` | 任意 | namespace 名 | 来源命名空间 |
| `source.principal` | 任意 | SPIFFE | 来源身份 |
| `source.serviceAccount` | 任意 | `<ns>/<sa>` | 来源 SA |
| `remote.ip` | 任意 | CIDR / IP | 原始客户端 IP |
| `destination.ip` | 任意 | CIDR / IP | 目标 Pod IP(注意不是 service IP) |
| `destination.port` | 任意 | `"8080"` | 目标端口 |
| `connection.sni` | TLS | `"api.example.com"` | TLS SNI |
| `request.auth.principal` | HTTP | `<iss>/<sub>` | JWT 主体(同 `requestPrincipals`) |
| `request.auth.audiences` | HTTP | audience 列表 | JWT aud 校验 |
| `request.auth.presenter` | HTTP | azp claim | JWT authorized party |
| `request.auth.claims[<name>]` | HTTP | claim 值 | **JWT 自定义 claim**;支持 `[nested1][nested2]` |
| `experimental.envoy.filters.<filter-name>[<key>]` | 任意 | filter metadata | Envoy filter 自定义 attribute |

**关键洞察**:`request.headers[<X>]` 配合 `when` = **你可以在 Istio 层读任意 HTTP header 决定放行**。这是 file upload、API key 验证、租户隔离、白名单流量分发等所有"基于 header 决策"场景的底层能力。

---

## 4. 实战场景:它到底能做哪些事

下面每个场景都对应"用户说想做 X"的可能解读 + 配套 AuthorizationPolicy 模板。所有 namespace / workload / SPIFFE 都用 `<PLACEHOLDER>` 形式,可直接替换。

### 4.1 文件上传限制

> **能不能限制:① 只有特定服务能调用上传接口 ② 上传接口 path 必须匹配 ③ 大小限制**?

**① ② 走 AuthorizationPolicy**,**③ 走 EnvoyFilter(Buffer filter / Local Rate Limit)**——AuthorizationPolicy 没有 body size 字段。

```yaml
# 只允许 frontend-sa 通过 POST + multipart 上传到 /upload/*
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-upload-allow-frontend
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-upload
  action: ALLOW
  rules:
    - from:
        - source:
            serviceAccounts: ["<NAMESPACE>/frontend-sa"]
      to:
        - operation:
            methods: ["POST"]
            paths: ["/upload/*"]
            hosts: ["api.example.com"]
      when:
        # 强制要求上传接口必须是 multipart/form-data
        - key: request.headers[content-type]
          values: ["multipart/form-data*"]
```

```yaml
# 配合 EnvoyFilter 限制 50MB(因为 AuthorizationPolicy 不管 body size)
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: api-upload-body-limit
  namespace: istio-system
spec:
  workloadSelector:
    labels:
      app: api-upload
  configPatches:
    - applyTo: HTTP_FILTER
      match:
        context: SIDECAR_INBOUND
        listener:
          filterChain:
            filter:
              name: "envoy.filters.network.http_connection_manager"
              subFilter:
                name: "envoy.filters.http.router"
      patch:
        operation: INSERT_BEFORE
        value:
          name: envoy.filters.http.buffer
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.filters.http.buffer.v3.Buffer
            max_request_bytes: 52428800  # 50 MB
```

**进阶**:
- 想做 MIME 白名单(`image/png` / `application/pdf`):用 `request.headers[content-type]` 的 `values: ["image/*", "application/pdf"]`,但只在请求小到能读完 header 时生效——大文件只能靠后端业务校验。
- 想限制每秒上传次数:`EnvoyFilter` + `local_ratelimit` filter(不是 AuthorizationPolicy 的范畴)。
- 想"任何人都能调 / 但只有 SA-A 调得到":用 `when` 限定 caller + 公开 `paths`,其余 default deny。

### 4.2 用户认证(JWT / OIDC)

> **能不能强制所有外部请求必须带 JWT?并按 JWT 里的 team / role 字段决定放行?**

可以,且这是 AuthorizationPolicy + RequestAuthentication 的标准组合。

**Step 1 — RequestAuthentication 验证 JWT 真伪**(不是 AuthorizationPolicy 的职责,放这里一起讲清楚):

```yaml
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: api-jwt-verify
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  jwtRules:
    - issuer: "https://auth.example.com"
      jwksUri: "https://auth.example.com/.well-known/jwks.json"
      audiences: ["api-a"]
      forwardOriginalToken: true
```

**Step 2 — AuthorizationPolicy 强制必须有有效 JWT**:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-a-require-jwt
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  action: DENY
  rules:
    # 如果没带有效 JWT 就拒(principal 为空表示未认证)
    - from:
        - source:
            requestPrincipals: ["*"]   # 此写法本身 = 跳过,看下面
```

> ⚠️ 反直觉坑:`requestPrincipals: ["*"]` 在 Istio 里 = "任意 principal 都被匹配",**不是 "必须有 principal"**。要表达"必须带 JWT",正确做法是:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-a-require-jwt
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  # 空 spec = 拒绝所有(此时 RequestAuthentication 已保证带 JWT 的请求有 principal)
  # 但 RequestAuthentication 失败本身也会拒,所以"必须有 JWT"由它 + ALLOW 组合实现:
---
# 显式 ALLOW:只放行带有效 JWT 的请求
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-a-allow-authenticated
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  action: ALLOW
  rules:
    - from:
        - source:
            # 必须带来自某个 issuer 的有效 JWT(* = "存在"判定,见下方说明)
            requestPrincipals: ["*"]
```

**Step 3 — 基于 JWT claim 字段放行(team / role / scope)**:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-a-only-team-platform
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  action: ALLOW
  rules:
    - from:
        - source:
            requestPrincipals: ["https://auth.example.com/*"]
      when:
        - key: request.auth.claims[team]
          values: ["platform"]
        - key: request.auth.claims[role]
          values: ["admin", "editor"]
        # 支持 nested claim
        # - key: request.auth.claims[address][city]
        #   values: ["Shanghai"]
```

**关键 4 个 JWT attribute**(都在 `when` 用):
- `request.auth.principal` = `<iss>/<sub>`(用 `requestPrincipals` 等价)
- `request.auth.audiences` = aud claim
- `request.auth.presenter` = azp claim
- `request.auth.claims[<name>]` = 任意 claim,支持 nested

### 4.3 API key / 自定义 header 鉴权

> **能不能基于自定义 header(比如 `X-API-Key: xxx` 或 `X-Tenant-ID: t1`)做放行?**

可以,但 AuthorizationPolicy **只能看 header 是否存在 / 匹配固定值**,不能解密或调外部服务验证真伪。真伪校验需要:
- (a) RequestAuthentication 把 key 当作 JWT 处理,或
- (b) `action: CUSTOM` 委派 ext_authz 服务

```yaml
# 简单场景 —— 只看 header 在不在、值对不对
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-a-require-api-key
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  action: ALLOW
  rules:
    - when:
        - key: request.headers[x-api-key]
          values: ["abc123*"]   # 支持前缀匹配
```

```yaml
# 多租户 —— 按 X-Tenant-ID 路由到不同 service(配合 VirtualService)
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-a-allow-tenant-t1
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  action: ALLOW
  rules:
    - when:
        - key: request.headers[x-tenant-id]
          values: ["t1", "t2"]   # 只允许这两个租户
```

**真要做"动态 key 校验"(查 DB / 调 OAuth server)**:走 `action: CUSTOM` 委托 ext_authz,见 §4.10。

### 4.4 多租户 / namespace 隔离

> **能不能强制"team-a 命名空间的服务只能被 team-a 内部调用"?**

```yaml
# team-a namespace 级别 baseline:只允许 team-a 内部 + 指定外部 SA
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: team-a-internal-only
  namespace: team-a
spec:
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces: ["team-a"]
    - from:
        - source:
            # 也允许 team-shared 命名空间的某些服务调用
            principals: ["cluster.local/ns/team-shared/sa/api-aggregator"]
```

**配合** `targetRefs`(API ≥ 1.22):把策略绑定到 Service / Gateway 而不是 selector,更精细。

### 4.5 Egress 出口管控

> **能不能控制"哪些服务能调外部 SaaS / API"?**

可以,**但前提**是要先 `ServiceEntry` 把外部域名注册进来,否则 sidecar 根本不知道路由。

```yaml
# 已有 ServiceEntry 把 api.saas1.com 注册后:
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: egress-allow-saas1
  namespace: istio-system      # 挂在 egressgateway 上
spec:
  selector:
    matchLabels:
      istio: egressgateway
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/apps/sa/api1"]
      to:
        - operation:
            hosts: ["api.saas1.com"]
            ports: ["443"]
```

**配 `connection.sni` 防止"假装访问 saas1 实际访问 saas2"**:

```yaml
when:
  - key: connection.sni
    values: ["api.saas1.com"]
```

完整实战例子见 `gcp/asm/istio-egress/05-authorizationpolicy.yaml`(同目录)。

### 4.6 健康检查 / 探针豁免

> **能不能让 K8s readiness / liveness 探针绕过 AuthorizationPolicy?**

```yaml
# 探针来自 kubelet(同节点,非 mTLS),source.ip 是节点 IP
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-node-probe
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  action: ALLOW
  rules:
    - to:
        - operation:
            paths: ["/healthz", "/readyz", "/livez"]
            ports: ["15020"]   # istio-agent healthcheck port
      when:
        - key: source.ip
          values: ["<KUBELET_CIDR>"]
```

⚠️ **避免在 deny 规则里用 `notPaths`**——很多实际故障都是"探针被挡"导致 Pod 一直 not ready。详见 §6.2。

### 4.7 黑名单 / 临时封禁(快速打补丁)

```yaml
# 紧急封禁某个外部 IP / SA(无需重新生成白名单)
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: block-bad-ip
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  action: DENY
  rules:
    - from:
        - source:
            ipBlocks: ["203.0.113.66"]
            remoteIpBlocks: ["198.51.100.0/24"]
```

DENY 规则**优先于** ALLOW——所以不需要改原有白名单,加一条 DENY 即可。

### 4.8 gRPC 路由级授权

```yaml
# gRPC method = /package.Service/Method(path 形式)
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: grpc-ratelimit
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: grpc-api
  action: ALLOW
  rules:
    - to:
        - operation:
            hosts: ["grpc-api.example.com"]
            paths:
              - "/grpc.health.v1.Health/Check"        # 只允许 health check
              - "/order.v1.OrderService/CreateOrder"  # 和下单接口
    - to:
        - operation:
            # 其他方法限流 —— 这条改用 EnvoyFilter
            paths: ["/payment.v1.*"]
```

gRPC 的 `methods` 字段总是 `POST`(HTTP/2);真正区分方法的是 `paths`。

### 4.9 灰度 / 金丝雀(基于 header)

AuthorizationPolicy 自己不能做流量分割(那是 VirtualService 的事),但可以**控制灰度流量是否有权限**——常见模式:

```yaml
# 允许 canary 调用生产 API(只有带 x-canary header 的才能进)
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-prod-allow-canary
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-prod
      version: stable
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/<NAMESPACE>/sa/canary-client"]
      when:
        - key: request.headers[x-canary-token]
          values: ["secret-2026*"]
```

这样灰度 client 必须带 SA + token 才能调生产——比 VirtualService 的 weight 切流更安全。

### 4.10 委托外部授权(OPA / custom authz)

> **能不能让 OPA、OPA Gatekeeper、自研 authz 服务来决策?**

`action: CUSTOM` + Envoy ext_authz protocol:

```yaml
# MeshConfig 里声明 provider(假设已配置 ext_authz server)
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: ext-authz-for-admin
  namespace: istio-system
spec:
  selector:
    matchLabels:
      app: istio-ingressgateway
  action: CUSTOM
  provider:
    name: "my-custom-authz"
  rules:
    - to:
        - operation:
            paths: ["/admin/*"]
```

CUSTOM 即使返回 allow,也**必须同时通过 ALLOW**——所以 ext_authz 失败仍兜底有 Istio 原生策略。

### 4.11 审计影子(等保 / 合规)

```yaml
# AUDIT 不影响放行,只把匹配请求标记为"需审计"
# 配合 envoy tap / otel 才能产出审计日志
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: audit-admin-access
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  action: AUDIT
  rules:
    - to:
        - operation:
            paths: ["/admin/*", "/internal/admin/*"]
            methods: ["POST", "PUT", "DELETE"]
```

**实战推荐路径**:`完全没审计 → AUDIT 影子观察(记录哪些请求会被拦)→ 改 ALLOW 真生效`。

### 4.12 演练模式 / dry-run

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: dry-run-check
  namespace: <NAMESPACE>
  annotations:
    "istio.io/dry-run": "true"   # 不真生效,但 envoy 会汇报"如果生效会拦哪些"
spec:
  action: DENY
  rules:
    - to:
        - operation:
            paths: ["/legacy/*"]
```

查看 dry-run 命中的请求:`istioctl experimental authz check <pod>` 或 envoy access log 标记。

---

## 5. 作用域:能在哪生效

| 作用域 | 写法 | 适用场景 |
|---|---|---|
| **mesh-wide** | `namespace: istio-system` (root) + selector | 不推荐,粒度太粗 |
| **namespace-wide** | `namespace: <ns>` + 无 selector | namespace baseline |
| **workload-specific** | `namespace: <ns>` + `selector.matchLabels` | 单个 service 的精细规则 |
| **绑定到 Gateway / Service**(API ≥ 1.22) | `targetRefs` 代替 `selector` | waypoint / 显式 K8s Gateway API |

`selector` 和 `targetRefs` **互斥**,同一策略二选一。

---

## 6. 常见坑(实战验证)

### 6.1 `requestPrincipals: ["*"]` 不等于"必须有 JWT"

Istio 中 `*` = **存在即匹配**,不是"存在性断言"。要"必须有 JWT"通常用 RequestAuthentication 验证失败自动拒绝 + AuthorizationPolicy ALLOW 组合(§4.2 Step 3)。

### 6.2 TCP 协议上 DENY 规则的属性缺失 = 全部匹配

> "missing attributes are treated as matches"

```yaml
# ❌ 错:这条会拒掉所有 TCP 流量(因为 method 是 HTTP-only,缺失即命中)
- to:
  - operation:
      methods: ["POST"]
```

TCP 上的 DENY 务必显式 `ports` scope:

```yaml
# ✅ 对:限定到具体端口
- to:
  - operation:
      methods: ["POST"]
      ports: ["8080"]
```

### 6.3 `mTLS = PERMISSIVE` 时所有 mTLS-依赖字段都不可信

`principals` / `namespaces` 在 PERMISSIVE 下会被明文流量绕过(sidecar 看到没身份 = 当 * 匹配)。**生产环境任何用 AuthorizationPolicy 的 namespace 必须 `PeerAuthentication STRICT`**——这是 Istio 安全公告 [istio-security-2021-004](https://istio.io/latest/news/security/istio-security-2021-004/) 的结论。

### 6.4 `when: request.headers[X]` 读取大小写敏感

header 名是 **case-sensitive**;`request.headers[content-type]` ≠ `request.headers[Content-Type]`。HTTP/2 header 必须小写,HTTP/1.1 客户端会按原样发,所以**最佳实践是匹配 lowercase**。

### 6.5 没有 selector 的策略会作用到整个 namespace

包括 namespace 里**所有** workload(不只是你预期的那一个)。新增 AuthorizationPolicy 前确认 scope。

### 6.6 DENY 优先于 ALLOW,但要小心"零规则 ≠ deny all"

```yaml
spec:
  rules: []   # 没有任何规则 = 永远不匹配 = 等价于 deny all
```
```yaml
spec:
  rules:
    - {}      # 空 rule = 任何请求都匹配 = 等价于 allow all
```
两个看着像,行为完全相反。

### 6.7 多 ALLOW 规则是 OR,不是 AND

同一 workload 上:
```yaml
rules:
  - from: [{source: {principals: ["A"]}}]
  - from: [{source: {principals: ["B"]}}]
```
A 和 B **都能进**,不是"必须同时是 A 和 B"。

### 6.8 `targetRefs` 只在 ≥ 1.22 才支持

旧版本用 `selector`;多版本集群里 targetRefs 策略要打 `istio.io/rev` label 防止被旧控制面误读。

---

## 7. 决策树:新需求来了该用哪条

```
新需求 X
  │
  ├─ X 是 "控制谁能访问/怎么访问"?
  │   ├─ X 是 "谁能进/允许谁进" → ALLOW + 白名单
  │   ├─ X 是 "拒绝某 IP/SA"    → DENY
  │   ├─ X 是 "只记录不拦截"   → AUDIT
  │   └─ X 是 "调外部决策"     → CUSTOM + ext_authz
  │
  ├─ X 的判断依据是什么?
  │   ├─ 身份 (K8s SA / mTLS SPIFFE)  → source.principals / serviceAccounts
  │   ├─ 来源 IP (本机 / 真实客户端) → source.ipBlocks / remoteIpBlocks
  │   ├─ JWT claim                   → requestPrincipals / request.auth.claims
  │   ├─ HTTP 字段 (method/path/host)→ operation.methods / paths / hosts
  │   └─ 自定义 header / SNI / metadata → when: [...]
  │
  └─ X 的作用范围?
      ├─ 整个 mesh        → root namespace
      ├─ 整个 namespace   → 无 selector
      ├─ 单个 workload    → selector.matchLabels
      └─ 绑定 Gateway     → targetRefs
```

---

## 8. 一句话总结

AuthorizationPolicy 的四元组 `action × source × to × when` 涵盖了:

- **白名单 / 黑名单 / 影子审计 / 委托授权**(`action`)
- **服务身份 / IP / JWT / namespace**(`source`)
- **HTTP method/path/host/port**(`to`)
- **任意 HTTP header / JWT claim / SNI / Envoy metadata**(`when`)

**能做的**:访问控制、租户隔离、灰度白名单、egress 出口管控、API key 校验、JWT claim 路由、gRPC method 授权、审计影子、健康检查豁免、外部授权委派。

**做不了的**:body size 限制(body 字段级限制)、rate limit(频次 / 速率)、dynamic 解密验证(需要外部 ext_authz)、TLS 终止(那是 Gateway 的事)、路由分流(那是 VirtualService 的事)——这些要配合 EnvoyFilter、Envoy ext_authz、Gateway、VirtualService 一起。

## References

- [Istio AuthorizationPolicy reference](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — action / Rule / Source / Operation / Condition 权威字段表
- [Istio Authorization Policy Conditions](https://istio.io/latest/docs/reference/config/security/conditions/) — `when` 全部 key 的官方清单
- [Istio Security concepts](https://istio.io/latest/docs/concepts/security/) — AAA / mTLS / RequestAuthentication 全景
- [Istio Authorization tasks](https://istio.io/latest/docs/tasks/security/authorization/) — 官方示例
- [Istio security best practices](https://istio.io/latest/docs/ops/best-practices/security/) — host-match / 多 mesh 等坑
- [Istio security advisory 2021-004](https://istio.io/latest/news/security/istio-security-2021-004/) — PERMISSIVE mTLS 下身份字段可绕过的硬约束
- [Google Cloud Service Mesh: Authorization policy](https://cloud.google.com/service-mesh/docs/security/authorization-policy-overview) — ASM 视角下的字段差异
- [Envoy URI template match](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/path/match/uri_template/v3/uri_template_match.proto) — `paths` 的 `{*}` / `{**}` 语法权威定义
- 同目录 `authorizationPolicy-and-Peerauthentication.md` — 与 `PeerAuthentication` 分工、模板化、三层安全模型
- 同目录 `istio-egress/05-authorizationpolicy.yaml` — Egress 实操 YAML