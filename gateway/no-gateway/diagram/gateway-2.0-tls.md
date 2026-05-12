# Gateway 2.0 TLS/证书配置方案

## 1. 整体请求流程

```
Client
  │
  │ HTTPS (*.appdev.abjx)
  ▼
PSC Attachment (Cross-Project)
  │
  ▼
IIP (Nginx) ◄── SSL Termination here (*.appdev.abjx cert)
  │
  │ proxy_pass https://10.100.0.100/
  ▼
Gateway 2.0 (Internal ILB)
  │
  ├── /iip/kong/*   ──► Kong Gateway 2.0 ──► GKE Runtime (iip ns)
  │
  └── /iip/direct/* ──► GKE Runtime Direct (SVC + Pods)
```

## 2. 证书配置位置分析

### 方案对比

| 终止点 | 位置 | 证书类型 | 优点 | 缺点 |
|--------|------|----------|------|------|
| **方案A** | IIP (Nginx) 单点终止 | `*.appdev.abjx` 通配符证书 | 统一管理，配置简单 | 后端服务无法验证客户端证书 |
| **方案B** | IIP + Gateway 2.0 双终止 | Nginx 用 `*.appdev.abjx`，Gateway 用内部证书 | 层次化安全 | 需要两套证书管理 |
| **方案C** | Gateway 2.0 终止 (mTLS) | Gateway 用 `*.appdev.abjx`，IIP 用内部证书 | 后端可验证来源，可做 mTLS | 配置复杂 |

**推荐：方案A（简化）或 方案C（高安全）**

---

## 3. 推荐方案：IIP (Nginx) 单点终止

### 3.1 IIP (Nginx) 证书配置

```nginx
# /etc/nginx/conf.d/iip-appdev.conf

# Upstream: Gateway 2.0
upstream gateway2_backend {
    server 10.100.0.100:443;
    keepalive 32;
}

# SSL Server Block for *.appdev.abjx
server {
    listen 443 ssl;
    server_name ~^(?<subdomain>.+)\.appdev\.abjx$;

    # Wildcard Certificate for *.appdev.abjx
    ssl_certificate /etc/nginx/ssl/wildcard.appdev.abjx.crt;
    ssl_certificate_key /etc/nginx/ssl/wildcard.appdev.abjx.key;

    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security Headers
    add_header X-SSL-Terminated "true" always;
    add_header X-Frontend-Domain $subdomain.appdev.abjx always;

    # Proxy to Gateway 2.0
    location / {
        proxy_pass https://gateway2_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Original-Host $subdomain.appdev.abjx;
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/nginx/ssl/internal-ca.crt;
    }
}
```

### 3.2 Gateway 2.0 证书配置（内部 TLS）

由于 IIP 已经终止 SSL，Gateway 2.0 使用内部证书进行 Pod 间通信：

```yaml
# gateway-2.0-tls-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: gateway-2-internal-tls
  namespace: gateway-system
type: kubernetes.io/tls
data:
  # Base64 encoded: openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/CN=gateway-2.gke.internal"
  tls.crt: <base64-encoded-cert>
  tls.key: <base64-encoded-key>
---
# gateway-2.0.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway-2-internal
  namespace: gateway-system
  annotations:
    networking.gke.io/internal-load-balancer: "true"
spec:
  gatewayClassName: gke-l7-rilb
  listeners:
  - name: https-internal
    protocol: HTTPS
    port: 443
    hostname: "*"  # 由于 IIP 已做 SSL 终止，Gateway 使用通配符
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: gateway-2-internal-tls
        namespace: gateway-system
    allowedRoutes:
      namespaces:
        from: All
```

---

## 4. 路径路由配置

### 4.1 HTTPRoute 配置（基于路径分流）

```yaml
# httproute-gateway-2.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gateway-2-routes
  namespace: gateway-system
spec:
  parentRefs:
  - name: gateway-2-internal
    namespace: gateway-system
    sectionName: https-internal
  hostnames:
  - "*.appdev.abjx"
  rules:
  # Rule 1: /iip/kong/* → Kong Gateway 2.0
  - matches:
    - path:
        type: PathPrefix
        value: /iip/kong
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
          X-Gateway-Mode: "kong-gw-2"
          X-Original-Host: "*.appdev.abjx"
    backendRefs:
    - name: kong-gateway-2-svc
      namespace: iip
      port: 443

  # Rule 2: /iip/direct/* → Direct Backend SVC
  - matches:
    - path:
        type: PathPrefix
        value: /iip/direct
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
          X-Gateway-Mode: "direct"
          X-Original-Host: "*.appdev.abjx"
    backendRefs:
    - name: iip-direct-svc
      namespace: iip
      port: 8443

  # Rule 3: Default /iip/* → Default Backend
  - matches:
    - path:
        type: PathPrefix
        value: /iip
    backendRefs:
    - name: iip-default-svc
      namespace: iip
      port: 8080
```

### 4.2 多域名证书配置（可选）

如果需要不同域名走不同后端，在 IIP 层按域名分流：

```nginx
# /etc/nginx/conf.d/iip-multi-domain.conf

# Upstreams
upstream gateway2_backend {
    server 10.100.0.100:443;
}

upstream kong_gw2_backend {
    server 10.100.0.101:443;
}

# Domain A: *.appdev.abjx → Gateway 2.0
server {
    listen 443 ssl;
    server_name ~^(?<subdomain>.+)\.appdev\.abjx$;

    ssl_certificate /etc/nginx/ssl/wildcard.appdev.abjx.crt;
    ssl_certificate_key /etc/nginx/ssl/wildcard.appdev.abjx.key;

    location / {
        proxy_pass https://gateway2_backend;
        # ... proxy_set_headers ...
    }
}

# Domain B: *.api.appdev.abjx → Kong Gateway 2.0 (特殊域名)
server {
    listen 443 ssl;
    server_name ~^(?<subdomain>.+)\.api\.appdev\.abjx$;

    ssl_certificate /etc/nginx/ssl/wildcard.api.appdev.abjx.crt;
    ssl_certificate_key /etc/nginx/ssl/wildcard.api.appdev.abjx.key;

    location / {
        proxy_pass https://kong_gw2_backend;
        proxy_set_header X-Kong-UpstreamName "api-gateway";
        # ... proxy_set_headers ...
    }
}
```

---

## 5. 证书管理方案

### 5.1 证书类型总结

| 层级 | 组件 | 证书用途 | 证书类型 |
|------|------|----------|----------|
| **入口层** | IIP (Nginx) | 对外 SSL 终止 | `*.appdev.abjx` 公网通配符证书 |
| **内部层** | Gateway 2.0 | 内部 mTLS 通信 | 内部 CA 签发证书 |
| **应用层** | Kong Gateway 2.0 | 内部 API 管理 | 内部 CA 签发证书 |
| **Pod 层** | Runtime Pods | Service Mesh / mTLS | SPIRE 或 istio 给的 Workload Identity 证书 |

### 5.2 证书存储（Kubernetes Secret）

```yaml
# 证书清单
apiVersion: v1
kind: Secret
metadata:
  name: iip-external-cert
  namespace: iip
type: kubernetes.io/tls
data:
  tls.crt: <公网证书>
  tls.key: <私钥>

---
apiVersion: v1
kind: Secret
metadata:
  name: gateway-2-internal-cert
  namespace: gateway-system
type: kubernetes.io/tls
data:
  tls.crt: <内部 CA 证书>
  tls.key: <内部 CA 私钥>

---
apiVersion: v1
kind: Secret
metadata:
  name: kong-gw2-internal-cert
  namespace: iip
type: kubernetes.io/tls
data:
  tls.crt: <Kong 内部证书>
  tls.key: <Kong 内部私钥>
```

---

## 6. 完整配置示例

### 6.1 IIP (Nginx) 完整配置

```nginx
# /etc/nginx/nginx.conf
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers on;

    # Upstreams
    upstream gateway2_backend {
        server 10.100.0.100:443;
        keepalive 32;
    }

    upstream kong_gw2_backend {
        server 10.100.0.101:443;
        keepalive 32;
    }

    # Server Blocks
    include /etc/nginx/conf.d/*.conf;
}
```

```nginx
# /etc/nginx/conf.d/iip-gateway-2.conf

# ========== *.appdev.abjx ==========
server {
    listen 443 ssl;
    server_name ~^(?<subdomain>.+)\.appdev\.abjx$;

    # SSL Certificate
    ssl_certificate /etc/nginx/ssl/wildcard.appdev.abjx.crt;
    ssl_certificate_key /etc/nginx/ssl/wildcard.appdev.abjx.key;
    ssl_session_tickets on;
    ssl_session_ticket_key /etc/nginx/ssl/ticket.key;

    # Path-based Routing
    location ~ ^/iip/kong(/|$) {
        proxy_pass https://gateway2_backend;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Original-Host $subdomain.appdev.abjx;
        proxy_set_header X-Entry-Point "kong-gw2";

        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/nginx/ssl/internal-ca.crt;
        proxy_ssl_server_name on;
        proxy_ssl_name gateway-2.gke.internal;
    }

    location ~ ^/iip/direct(/|$) {
        proxy_pass https://gateway2_backend;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Original-Host $subdomain.appdev.abjx;
        proxy_set_header X-Entry-Point "direct";

        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/nginx/ssl/internal-ca.crt;
        proxy_ssl_server_name on;
        proxy_ssl_name gateway-2.gke.internal;
    }

    location / {
        return 404;
    }
}
```

### 6.2 Gateway 2.0 配置

```yaml
# gateway-2.0-full.yaml
---
# Gateway Listener Config
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway-2-internal
  namespace: gateway-system
  annotations:
    networking.gke.io/internal-load-balancer: "true"
    networking.gke.io/static-ip: "gateway-2-internal-ip"
spec:
  gatewayClassName: gke-l7-rilb
  listeners:
  - name: https-all
    protocol: HTTPS
    port: 443
    hostname: "*"
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: gateway-2-internal-cert
        namespace: gateway-system
    allowedRoutes:
      namespaces:
        from: All

---
# HTTPRoute: Path-based Routing
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gateway-2-httproute
  namespace: gateway-system
spec:
  parentRefs:
  - name: gateway-2-internal
    namespace: gateway-system
    sectionName: https-all
  hostnames:
  - "*.appdev.abjx"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /iip/kong
    - path:
        type: Exact
        value: /iip/kong
    headerMatches:
    - name: X-Entry-Point
      value: kong-gw2
    backendRefs:
    - name: kong-gateway-2-svc
      namespace: iip
      port: 443
      weight: 100

  - matches:
    - path:
        type: PathPrefix
        value: /iip/direct
    - path:
        type: Exact
        value: /iip/direct
    headerMatches:
    - name: X-Entry-Point
      value: direct
    backendRefs:
    - name: iip-direct-svc
      namespace: iip
      port: 8443
      weight: 100

  - matches:
    - path:
        type: PathPrefix
        value: /iip
    backendRefs:
    - name: iip-default-backend
      namespace: iip
      port: 8080
      weight: 100

---
# Internal TLS Certificate
apiVersion: v1
kind: Secret
metadata:
  name: gateway-2-internal-cert
  namespace: gateway-system
  labels:
    app: gateway-2
    tier: internal
type: kubernetes.io/tls
data:
  # Generate: openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/CN=gateway-2.gke.internal/O=Gateway2"
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURYVENDQWtXZ0F3SUJBZ0lVRXh...
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCnWxYS5yb290LmV4cGlyZWQ0NTYh

---
# Reserved Internal IP
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeAddress
metadata:
  name: gateway-2-internal-ip
  namespace: gateway-system
spec:
  location: europe-west2
  purpose: SHARED_LOADBALANCER_VIP
  ipVersion: IPV4
  address: 10.100.0.100
```

---

## 7. 路由决策流程

```
请求进入 Gateway 2.0 后的处理流程：

┌─────────────────────────────────────────────────────────────┐
│                    Gateway 2.0 Listener                      │
│                         Port 443                             │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
              ┌────────────────────────┐
              │   TLS Termination      │
              │  (Internal Cert)      │
              └──────────┬─────────────┘
                         │
                         ▼
              ┌────────────────────────┐
              │     HTTPRoute          │
              │  *.appdev.abjx         │
              └──────────┬─────────────┘
                         │
                         ▼
              ┌────────────────────────┐
              │   Match Rules by       │
              │   Path + Header        │
              └──────────┬─────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
   /iip/kong/*    /iip/direct/*      /iip/*
        │                │                │
        ▼                ▼                ▼
 ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
 │   Kong GW   │  │   Direct    │  │   Default   │
 │   2.0 SVC   │  │   SVC       │  │   Backend   │
 │  (iip ns)   │  │  (iip ns)   │  │  (iip ns)  │
 └─────────────┘  └─────────────┘  └─────────────┘
       │                │                │
       ▼                ▼                ▼
 ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
 │  Upstream   │  │    Pods     │  │    Pods     │
 │  + Plugins  │  │ (api impl)  │  │ (default)   │
 └─────────────┘  └─────────────┘  └─────────────┘
```

---

## 8. 证书配置总结

### 8.1 配置位置

| 组件 | 证书类型 | 配置位置 | 说明 |
|------|----------|----------|------|
| **IIP (Nginx)** | `*.appdev.abjx` 公网证书 | `ssl_certificate` | **主 SSL 终止点** |
| **Gateway 2.0** | 内部 CA 证书 | Gateway Listener | 内部 mTLS |
| **Kong GW 2.0** | 内部 CA 证书 | Kong 配置 | 内部 API 管理 |
| **Runtime Pods** | SPIRE/istiod 签发 | 自动注入 | Workload Identity |

### 8.2 关键配置项

**IIP (Nginx):**
```nginx
ssl_certificate /etc/nginx/ssl/wildcard.appdev.abjx.crt;
ssl_certificate_key /etc/nginx/ssl/wildcard.appdev.abjx.key;
proxy_ssl_trusted_certificate /etc/nginx/ssl/internal-ca.crt;  # 验证后端证书
```

**Gateway 2.0:**
```yaml
tls:
  mode: Terminate
  certificateRefs:
  - kind: Secret
    name: gateway-2-internal-cert
```

**HTTPRoute:**
```yaml
rules:
- matches:
  - path:
      type: PathPrefix
      value: /iip/kong
  backendRefs:
  - name: kong-gateway-2-svc
```

### 8.3 路由分发依据

| 依据 | 方式 | 示例 |
|------|------|------|
| **路径前缀** | HTTPRoute `pathPrefix` | `/iip/kong/*` → Kong GW 2.0 |
| **Header** | HTTPRoute `headerMatches` | `X-Entry-Point: kong-gw2` |
| **Host** | HTTPRoute `hostnames` | `*.appdev.abjx` |

---

## 9. 常见问题

### Q1: 为什么 IIP 和 Gateway 2.0 都需要证书？

- **IIP**: 对外终止 SSL，客户请求需要加密
- **Gateway 2.0**: Pod 间通信加密，防止内部流量被嗅探

### Q2: 能否只在 Gateway 2.0 终止 SSL？

可以，但需要：
1. IIP 使用 `proxy_ssl_verify off`（不验证证书）
2. IIP 不持有公网证书（不安全）
3. 客户端证书无法传递给后端验证来源

### Q3: 如何管理多域名证书？

方案：
1. **IAP 层（Nginx）**：使用 `server_name` 匹配不同域名，每个域名独立证书
2. **Gateway 层**：使用 HTTPRoute `hostnames` 匹配，内部统一证书

### Q4: 证书轮换策略？

| 证书位置 | 轮换方式 | 建议频率 |
|----------|----------|----------|
| IIP (公网) | cert-manager + ACME | 90 天自动 |
| Gateway 2.0 (内部) | cert-manager + 内部 CA | 365 天 |
| Pod (Workload) | SPIRE 自动轮换 | 24 小时自动 |

---

## 10. 下一步建议

1. **实施 cert-manager**：自动化证书管理
2. **配置内部 CA**：使用 Vault 或 GCP Certificate Authority Service
3. **开启 mTLS**：使用 Istio 或 SPIRE 做 Pod 间双向认证
4. **监控证书过期**：配置证书到期告警
