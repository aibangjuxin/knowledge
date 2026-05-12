# GKE Gateway Header 转写详解：Host Header 透传到 Kong

## 1. 场景描述

### 1.1 核心问题

```
客户端请求：
  Host: api2.appdev.abjx
  Path: /api-path/e2e

Kong DP 配置：
  监听域名: www.intrakong.com
  路由路径: /api2/*

问题：如何让 Gateway 2.0 把请求转发给 Kong，同时让 Kong 认为是它的本域名？
```

### 1.2 架构图

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           Host Header 转写场景                                        │
│                                                                                     │
│   Client                                                                           │
│     │                                                                            │
│     │ api2.appdev.abjx/api-path/e2e                                              │
│     ▼                                                                            │
│   Gateway 2.0                                                                     │
│     │ *.appdev.abjx 证书                                                         │
│     │                                                                            │
│     │ Header 转写:                                                                │
│     │   Host: api2.appdev.abjx  ──► Host: www.intrakong.com                     │
│     │   (原始域名保留)               (Kong 认知的域名)                              │
│     │                                                                            │
│     ▼                                                                            │
│   Kong DP (www.intrakong.com)                                                    │
│     │                                                                            │
│     └──► /api2/* ──► Upstream Backend                                            │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 需求矩阵

| API | 域名 | 路径 | 目标 | Host Header 处理 |
|-----|------|------|------|-----------------|
| API1 | `api1.appdev.abjx` | `/api1/*` | GKE Runtime Direct | Host 保持原样 |
| API2 | `api2.appdev.abjx` | `/api-path/e2e/*` | Kong DP (www.intrakong.com) | Host 转写为 `www.intrakong.com` |

---

## 2. Host Header 转写原理

### 2.1 为什么需要 Host Header 转写？

Kong (和其他 API Gateway) 依赖 Host Header 来：
1. **路由决策**：匹配 Server Block / Route
2. **虚拟主机**：区分同一 IP 上的多个域名
3. **Upstream 请求**：构造回源请求的 Host

如果 Kong 监听的是 `www.intrakong.com`，但请求带着 `api2.appdev.abjx`，Kong 无法匹配到正确的 Route。

### 2.2 转写策略

**策略 A：完全替换**
```
原始:  Host: api2.appdev.abjx
转发:  Host: www.intrakong.com
结果:  Kong 按 www.intrakong.com 路由
```

**策略 B：保留原始 + 添加 X-Forwarded-Host**
```
原始:  Host: api2.appdev.abjx
转发:  Host: www.intrakong.com
       X-Forwarded-Host: api2.appdev.abjx
结果:  Kong 按 www.intrakong.com 路由，但保留原始域名信息
```

---

## 3. Gateway 2.0 HTTPRoute 配置

### 3.1 方案一：基于 Hostname 分流 + Host Header 转写

```yaml
# gateway-2.0-host-rewrite.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: gateway-2-external-cert
  namespace: gateway-system
type: kubernetes.io/tls
data:
  tls.crt: <base64>
  tls.key: <base64>
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway-2-external
  namespace: gateway-system
spec:
  gatewayClassName: gke-l7-rilb
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*.appdev.abjx"  # 匹配所有 *.appdev.abjx 域名
    tls:
      mode: Terminate
      certificateRefs:
      - name: gateway-2-external-cert
        namespace: gateway-system
    allowedRoutes:
      namespaces:
        from: All
---
# HTTPRoute: 基于 hostname + path 分流
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gateway-2-host-routes
  namespace: gateway-system
spec:
  parentRefs:
  - name: gateway-2-external
    namespace: gateway-system
    sectionName: https
  hostnames:
  # Gateway 匹配这些 hostname
  - "api1.appdev.abjx"
  - "api2.appdev.abjx"
  - "*.appdev.abjx"
  rules:
  # ========== API1: api1.appdev.abjx → Direct Backend ==========
  - matches:
    - path:
        type: PathPrefix
        value: /api1
    hostname:
    - "api1.appdev.abjx"
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        # Host 保持原样，直接透传到 Direct Backend
        set:
          X-Original-Host: "%{request.host}%"
          X-Upstream-Service: direct-backend
          X-Entry-Point: api1
        add:
          X-SSL-Terminated: gateway-2
    backendRefs:
    - name: api1-direct-svc
      namespace: iip
      port: 8443

  # ========== API2: api2.appdev.abjx → Kong DP (Host 转写) ==========
  - matches:
    - path:
        type: PathPrefix
        value: /api-path/e2e
    hostname:
    - "api2.appdev.abjx"
    filters:
    # 核心：Host Header 转写
    - type: RequestHeaderModifier
      requestHeaderModifier:
        # 覆盖 Host 为 Kong 监听的域名
        set:
          # ★★★ 关键配置：Host 头转写 ★★★
          Host: www.intrakong.com

          # 保留原始信息
          X-Original-Host: "%{request.host}%"

          # 标识上游服务
          X-Upstream-Service: kong-dp
          X-Kong-Route: api2-route
          X-Entry-Point: api2
        add:
          # 标识 SSL 终止
          X-SSL-Terminated: gateway-2

          # Kong 根据此 header 做额外路由（可选）
          X-Kong-Downstream-Host: www.intrakong.com
        remove:
          # 移除可能干扰的 headers
          - X-Forwarded-Host
    backendRefs:
    - name: kong-dp-svc
      namespace: kong-system
      port: 443

  # ========== API2 其他路径 (兜底) ==========
  - matches:
    - path:
        type: PathPrefix
        value: /api2
    hostname:
    - "api2.appdev.abjx"
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
          Host: www.intrakong.com
          X-Original-Host: "%{request.host}%"
          X-Upstream-Service: kong-dp
          X-Entry-Point: api2
    backendRefs:
    - name: kong-dp-svc
      namespace: kong-system
      port: 443
```

### 3.2 方案二：纯 Path 分流（Host 统一处理）

如果不想用 hostname 区分，可以在同一 hostname 下按 path 分流：

```yaml
# gateway-2.0-path-only-routes.yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gateway-2-path-routes
  namespace: gateway-system
spec:
  parentRefs:
  - name: gateway-2-external
    namespace: gateway-system
    sectionName: https
  hostnames:
  - "*.appdev.abjx"  # 匹配所有 *.appdev.abjx
  rules:
  # ========== /api1/* → Direct Backend (Host 透传) ==========
  - matches:
    - path:
        type: PathPrefix
        value: /api1
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
          X-Upstream-Service: direct-backend
          X-Entry-Point: api1
        add:
          X-Original-Host: "%{request.host}%"
          X-SSL-Terminated: gateway-2
    backendRefs:
    - name: api1-direct-svc
      namespace: iip
      port: 8443

  # ========== /api-path/e2e/* → Kong DP (Host 转写) ==========
  - matches:
    - path:
        type: PathPrefix
        value: /api-path/e2e
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
          # ★★★ Host 头转写为 Kong 域名 ★★★
          Host: www.intrakong.com

          # 保留原始信息
          X-Original-Host: "%{request.host}%"

          # 上游标识
          X-Upstream-Service: kong-dp
          X-Kong-Route: api2-e2e-route
          X-Entry-Point: api2-e2e
        add:
          X-SSL-Terminated: gateway-2
    backendRefs:
    - name: kong-dp-svc
      namespace: kong-system
      port: 443

  # ========== /api2/* → Kong DP (兜底) ==========
  - matches:
    - path:
        type: PathPrefix
        value: /api2
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
          Host: www.intrakong.com
          X-Original-Host: "%{request.host}%"
          X-Upstream-Service: kong-dp
          X-Entry-Point: api2
    backendRefs:
    - name: kong-dp-svc
      namespace: kong-system
      port: 443
```

---

## 4. Kong DP 配置

### 4.1 Kong DP 需要监听 www.intrakong.com

```yaml
# kong-dp-config.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: kong-system
---
# Kong TLS Secret (for www.intrakong.com)
apiVersion: v1
kind: Secret
metadata:
  name: kong-dp-tls-cert
  namespace: kong-system
type: kubernetes.io/tls
data:
  # 证书 CN 必须包含 www.intrakong.com
  tls.crt: <base64-cert-with-www.intrakong.com>
  tls.key: <base64-key>
---
# Kong Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kong-dp
  namespace: kong-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: kong-dp
  template:
    metadata:
      labels:
        app: kong-dp
    spec:
      containers:
      - name: kong
        image: kong:3.5
        env:
        - name: KONG_MODE
          value: "proxy"
        # Kong 监听 www.intrakong.com
        - name: KONG_PROXY_LISTEN
          value: |
            0.0.0.0:443 ssl
            0.0.0.0:80
        # SSL 配置
        - name: KONG_SSL_CERT
          value: /etc/kong/ssl/tls.crt
        - name: KONG_SSL_CERT_KEY
          value: /etc/kong/ssl/tls.key
        - name: KONG_ADMIN_LISTEN
          value: "0.0.0.0:8444"
        ports:
        - containerPort: 443
        - containerPort: 80
        volumeMounts:
        - name: kong-certs
          mountPath: /etc/kong/ssl
        - name: kong-config
          mountPath: /usr/local/kong/declarative.yml
          subPath: declarative.yml
      volumes:
      - name: kong-certs
        secret:
          secretName: kong-dp-tls-cert
      - name: kong-config
        configMap:
          name: kong-dp-config
---
# Kong Service
apiVersion: v1
kind: Service
metadata:
  name: kong-dp-svc
  namespace: kong-system
spec:
  type: ClusterIP
  ports:
  - name: proxy
    port: 443
    targetPort: 443
  selector:
    app: kong-dp
```

### 4.2 Kong 路由配置 (dec.yml)

```yaml
# kong-dp-declarative.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kong-dp-config
  namespace: kong-system
data:
  declarative.yml: |
    _format_version: "3.0"

    # ============================================================
    # Services
    # ============================================================

    # Service: API2 E2E Backend (来自 Gateway 转发的 /api-path/e2e/*)
    services:
    - name: api2-e2e-backend
      url: http://api2-backend.iip.svc.cluster.local:8080
      routes:
      # Kong 路由：按 path 匹配
      - name: api2-e2e-route
        strip_path: false  # 保留完整路径 /api-path/e2e/*
        paths:
        - /api-path/e2e
        - /api2
      plugins:
      # 请求转换：添加 upstream 标识
      - name: request-transformer
        config:
          add:
            headers:
            - X-Kong-Upstream:api2-e2e
            - X-Kong-Downstream-Host:www.intrakong.com

    # ============================================================
    # 全局插件
    # ============================================================
    plugins:
    # 读取 Gateway 转发的 Header
    - name: access-log
      config:
        log_level: info

    # 读取 X-Original-Host 做审计
    - name: correlation-id
      config:
        header_name: X-Request-ID

    # 基于 X-Upstream-Service 做流量控制
    - name: rate-limiting
      config:
        minute: 1000
        policy: local
```

---

## 5. 完整请求流程

### 5.1 API2 请求流程（api2.appdev.abjx → Kong DP）

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                            API2 请求完整流程                                          │
│                                                                                     │
│  1. Client 发起请求                                                                  │
│     GET /api-path/e2e/service HTTP/1.1                                             │
│     Host: api2.appdev.abjx                                                          │
│                                                                                     │
│                          ▼                                                          │
│                                                                                     │
│  2. PSC → IIP (HTTPS passthrough)                                                   │
│     Host 保持: api2.appdev.abjx                                                     │
│                                                                                     │
│                          ▼                                                          │
│                                                                                     │
│  3. Gateway 2.0 (SSL 终止)                                                          │
│     Host: api2.appdev.abjx ──────────────────────────► Host: www.intrakong.com      │
│     (原始)                                                  (转写)                    │
│                                                                                     │
│     添加 Header:                                                                    │
│       X-Original-Host: api2.appdev.abjx                                             │
│       X-Upstream-Service: kong-dp                                                  │
│       X-Kong-Route: api2-e2e-route                                                 │
│       X-Entry-Point: api2-e2e                                                       │
│       X-SSL-Terminated: gateway-2                                                   │
│                                                                                     │
│                          ▼                                                          │
│                                                                                     │
│  4. Kong DP (www.intrakong.com)                                                    │
│     • 收到 Host: www.intrakong.com                                                  │
│     • 匹配 Route: api2-e2e-route                                                    │
│     • 匹配 paths: /api-path/e2e                                                     │
│     • X-Original-Host: api2.appdev.abjx (用于审计/日志)                              │
│                                                                                     │
│                          ▼                                                          │
│                                                                                     │
│  5. Kong → Upstream Backend                                                         │
│     GET /api-path/e2e/service HTTP/1.1                                             │
│     Host: api2-backend.iip.svc.cluster.local                                        │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Header 变化对比

| 位置 | Host | X-Original-Host | X-Upstream-Service |
|------|------|-----------------|-------------------|
| Client | `api2.appdev.abjx` | - | - |
| IIP | `api2.appdev.abjx` | - | - |
| Gateway (出站) | `www.intrakong.com` | `api2.appdev.abjx` | `kong-dp` |
| Kong (入站) | `www.intrakong.com` | `api2.appdev.abjx` | `kong-dp` |
| Kong (转发) | `api2-backend...` | `api2.appdev.abjx` | - |

---

## 6. 高级 Header 转写场景

### 6.1 场景：Path 也需要转写

如果 Kong 的路由不是 `/api-path/e2e`，而是 Kong 自己的路径：

```
原始: api2.appdev.abjx/api-path/e2e
Kong:  www.intrakong.com/kong-api/e2e
```

```yaml
filters:
- type: RequestHeaderModifier
  requestHeaderModifier:
    set:
      # Host 转写
      Host: www.intrakong.com
      # ★★★ Path 转写 ★★★
      # 使用 URLRewrite 过滤器 (GKE Gateway 支持)
      # 注意：GKE Gateway API 标准不支持 URLRewrite
      # 解决方案：在 Kong 层做 path 转换，或使用 Nginx ingress
```

### 6.2 场景：Kong 需要多个 Header

```yaml
filters:
- type: RequestHeaderModifier
  requestHeaderModifier:
    set:
      # 主要 Host
      Host: www.intrakong.com

      # Kong 需要的额外 Header
      X-Kong-Requested-Host: www.intrakong.com
      X-Real-IP: "%{request.x-forwarded-for}%"
      X-Forwarded-Host: "%{request.host}%"
      X-Forwarded-Proto: https
    add:
      # 保留原始信息
      X-Original-Host: "%{request.host}%"

      # Gateway 信息
      X-SSL-Terminated: gateway-2
      X-Gateway-Name: gateway-2-external
      X-Entry-Point: api2-e2e
      X-Upstream-Service: kong-dp
```

### 6.3 场景：条件 Header 转写

根据不同路径转写到不同 Kong 服务：

```yaml
rules:
# 路径 A → Kong Service A
- matches:
  - path:
      type: PathPrefix
      value: /api-path/e2e
  filters:
  - type: RequestHeaderModifier
    requestHeaderModifier:
      set:
        Host: www.intrakong.com
        X-Kong-Service: service-a
        X-Kong-Route: route-a
      add:
        X-Original-Host: "%{request.host}%"
      remove:
        - X-Kong-Service
        - X-Kong-Route
  backendRefs:
  - name: kong-dp-svc
    namespace: kong-system
    port: 443

# 路径 B → Kong Service B
- matches:
  - path:
      type: PathPrefix
      value: /api-path/e3e
  filters:
  - type: RequestHeaderModifier
    requestHeaderModifier:
      set:
        Host: www.intrakong.com
        X-Kong-Service: service-b
        X-Kong-Route: route-b
      add:
        X-Original-Host: "%{request.host}%"
    backendRefs:
  - name: kong-dp-svc
    namespace: kong-system
    port: 443
```

---

## 7. Kong DP 路由匹配详解

### 7.1 Kong Route 匹配优先级

```
1. Route.host     - 匹配的域名
2. Route.paths   - 匹配的前缀/精确路径
3. Route.methods  - 匹配的 HTTP 方法
4. Route.snis     - 匹配的 SNI (TLS)
```

### 7.2 为什么 Host 必须是 www.intrakong.com？

Kong 的 Route 配置中：

```yaml
routes:
- name: api2-route
  # 如果设置了 hosts，Kong 会验证请求的 Host header
  hosts:
  - www.intrakong.com
  paths:
  - /api-path/e2e
  - /api2
```

如果 Gateway 转发的请求 Host 是 `api2.appdev.abjx`，但 Kong Route 要求 Host 是 `www.intrakong.com`，则 404。

### 7.3 Kong 层保留原始域名

在 Kong 中，可以通过 `X-Forwarded-Host` 或自定义 header 保留原始域名：

```yaml
plugins:
- name: request-transformer
  config:
    add:
      headers:
      # Kong 读取 Gateway 转发的 X-Original-Host
      X-Downstream-Host: "%headers.X-Original-Host%"
```

---

## 8. 完整配置示例

### 8.1 Gateway 2.0 HTTPRoute (最终版)

```yaml
# gateway-2.0-httproute-complete.yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gateway-2-complete-routes
  namespace: gateway-system
spec:
  parentRefs:
  - name: gateway-2-external
    namespace: gateway-system
    sectionName: https
  hostnames:
  - "*.appdev.abjx"
  rules:

  # ============================================================
  # API1: api1.appdev.abjx → Direct Backend
  # ============================================================
  - matches:
    - path:
        type: PathPrefix
        value: /api1
    hostname:
    - "api1.appdev.abjx"
    - "*.api1.appdev.abjx"
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
          X-Upstream-Service: api1-direct
          X-Entry-Point: api1
        add:
          X-Original-Host: "%{request.host}%"
          X-SSL-Terminated: gateway-2
        remove:
          - X-Kong-Route
          - X-Kong-Service
    backendRefs:
    - name: api1-direct-svc
      namespace: iip
      port: 8443

  # ============================================================
  # API2: api2.appdev.abjx → Kong DP (Host 转写)
  # ============================================================
  - matches:
    - path:
        type: PathPrefix
        value: /api-path/e2e
    hostname:
    - "api2.appdev.abjx"
    - "*.api2.appdev.abjx"
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        # ★★★ 核心：Host 头转写 ★★★
        set:
          # Kong DP 监听的域名
          Host: www.intrakong.com

          # Kong 路由标识
          X-Kong-Route: api2-e2e-route
          X-Kong-Service: api2-e2e-backend

          # 上游标识
          X-Upstream-Service: kong-dp
          X-Entry-Point: api2-e2e

          # 保留原始域名（用于审计/日志）
          X-Original-Host: "%{request.host}%"

          # SSL 信息
          X-Forwarded-Proto: https
          X-Forwarded-Port: "443"
        add:
          X-SSL-Terminated: gateway-2
        remove:
          # 清理可能干扰的 headers
          - X-Forwarded-Host
    backendRefs:
    - name: kong-dp-svc
      namespace: kong-system
      port: 443

  # ============================================================
  # API2 兜底: /api2/* → Kong DP
  # ============================================================
  - matches:
    - path:
        type: PathPrefix
        value: /api2
    hostname:
    - "api2.appdev.abjx"
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
          Host: www.intrakong.com
          X-Kong-Route: api2-default-route
          X-Kong-Service: api2-backend
          X-Upstream-Service: kong-dp
          X-Entry-Point: api2
          X-Original-Host: "%{request.host}%"
          X-Forwarded-Proto: https
          X-Forwarded-Port: "443"
        add:
          X-SSL-Terminated: gateway-2
    backendRefs:
    - name: kong-dp-svc
      namespace: kong-system
      port: 443

  # ============================================================
  # Default: 未知路径 → 404
  # ============================================================
  - matches:
    - path:
        type: PathPrefix
        value: /
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
          X-Upstream-Service: unknown
          X-Entry-Point: unknown
    backendRefs:
    - name: gateway-2-404-backend
      namespace: gateway-system
      port: 8080
```

---

## 9. 验证与调试

### 9.1 检查 Header 转写

```bash
# 在 IIP 层抓包验证
tcpdump -i any -A 'tcp[((tcp[12:1] & 0xf0) >> 2):4]' | grep Host

# 在 Kong 层检查 Header
curl -v -H "Host: api2.appdev.abjx" https://kong-dp/api-path/e2e
```

### 9.2 Kong 日志分析

```bash
# Kong Access Log 显示原始 vs 转写后的 Host
# 格式: $remote_addr - $host - [$timestamp] "$method $uri" $status

# 期望看到:
# 203.0.113.1 - www.intrakong.com - [2024-01-01...] "GET /api-path/e2e HTTP/1.1" 200
```

### 9.3 GKE Gateway 日志

```bash
# 查看 HTTPRoute 匹配情况
kubectl logs -n gateway-system -l app=gateway-2

# 检查 HTTPRoute status
kubectl get httproute gateway-2-complete-routes -n gateway-system -o yaml
```

---

## 10. 总结

### 10.1 Host Header 转写配置

```yaml
filters:
- type: RequestHeaderModifier
  requestHeaderModifier:
    set:
      # ★★★ 核心：Kong 监听的域名 ★★★
      Host: www.intrakong.com

      # 保留原始域名
      X-Original-Host: "%{request.host}%"

      # Kong 路由标识
      X-Kong-Route: api2-e2e-route
      X-Kong-Service: api2-e2e-backend
```

### 10.2 关键点

| 要点 | 说明 |
|------|------|
| **为什么 Host 要转写？** | Kong 按 Route.hosts 匹配，请求 Host 必须和 Kong 配置的域名一致 |
| **Kong 监听什么域名？** | `www.intrakong.com` (由 Kong DP 证书决定) |
| **原始域名如何保留？** | `X-Original-Host` header |
| **路径需要转写吗？** | 不需要，Kong 按 paths 匹配 |
| **转写在哪儿做？** | Gateway 2.0 HTTPRoute Filter |

### 10.3 完整链路

```
Client: api2.appdev.abjx/api-path/e2e
    ↓
Gateway 2.0:
    Host: api2.appdev.abjx → www.intrakong.com
    + X-Original-Host: api2.appdev.abjx
    ↓
Kong DP: www.intrakong.com
    Route matches: paths: [/api-path/e2e]
    ↓
Upstream: /api-path/e2e (完整路径保留)
```
