# Gateway 2.0 SSL 终止方案 (强制每跳 HTTPS)

## 1. 核心约束

| 约束 | 说明 |
|------|------|
| **每跳 HTTPS** | IIP → Gateway 2.0 → Kong/Direct 必须全程 HTTPS |
| **Header 转写位置** | 在 Gateway 2.0 上做（HTTPRoute Filter） |
| **内部证书用途** | IIP 和 Gateway 2.0 之间、Gateway 2.0 和后端之间 |
| **公网证书** | 仅在 PSC 入口处（由跨项目提供） |

## 2. 架构图

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              每跳 HTTPS 流程                                         │
│                                                                                     │
│   Client                                                                        │
│      │                                                                          │
│      │ HTTPS (*.appdev.abjx)  ◄── 公网证书 (PSC Producer 提供)                      │
│      ▼                                                                          │
│   PSC Attachment (Cross-Project)                                                   │
│      │                                                                          │
│      │ HTTPS (passthrough)                                                         │
│      ▼                                                                          │
│   IIP (Nginx) ◄── 内部证书 (*.internal.gke.local)                                  │
│      │                                                                          │
│      │ HTTPS (proxy_pass)    ◄── 内部证书 + SNI 转发                               │
│      ▼                                                                          │
│   Gateway 2.0 ◄───────────────────────────────────────────────────────────────── │
│      │                                                                         │   │
│      │ HTTPS 终止 + Header 转写                                                 │   │
│      │                                                                         │   │
│      ├─── /iip/kong/* ─────────────────────────────► Kong GW 2.0 (HTTPS) ──► Runtime │
│      │                                                     │                      │
│      │                                                     ▼                      │
│      │                                               Internal mTLS                │
│      │                                                                         │
│      └─── /iip/direct/* ───────────────────────────► GKE Runtime (HTTPS) ◄─────────┘
│                                                                │
│                                                                ▼
│                                                          Pod-to-Pod mTLS
│                                                         (SPIRE / Istio)
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## 3. 各跳详细配置

### 第1跳：PSC → IIP

**证书**：PSC Producer 提供的公网证书（`*.appdev.abjx`）
**IIP 配置**：接收来自 PSC 的 HTTPS，IIP 持有内部证书用于下一跳

```nginx
# /etc/nginx/conf.d/iip-listen.conf

# IIP 监听来自 PSC 的 HTTPS 请求
# 证书：内部 CA 签发的 *.internal.iip.local
server {
    listen 443 ssl;
    server_name ~^(?<subdomain>.+)\.internal\.iip\.local$;

    # IIP 的入站证书（内部 CA）
    ssl_certificate /etc/nginx/ssl/iip-internal.crt;
    ssl_certificate_key /etc/nginx/ssl/iip-internal.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_verify_client off;  # PSC 到 IIP 不需要双向认证

    # 记录原始请求信息
    log_format iip_access '$remote_addr - $host - $request_uri - $ssl_client_s_dn';

    # 向上游 Gateway 2.0 转发
    location / {
        # 转发到 Gateway 2.0（下一跳 HTTPS）
        proxy_pass https://10.100.0.100:443;

        proxy_http_version 1.1;

        # 透传原始 Host（客户端请求的域名）
        proxy_set_header Host $http_host;

        # 透传 SSL 信息
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Port 443;

        # 保留原始客户端信息
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;

        # 新增：标识请求来源（经过 IIP）
        proxy_set_header X-Forwarded-TLS-Connection "through-iip";

        # 连接配置
        proxy_set_header Connection "";
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/nginx/ssl/internal-ca.crt;
        proxy_ssl_server_name on;
        proxy_ssl_name $host;
    }

    location /health {
        return 200 'IIP OK';
    }
}
```

### 第2跳：IIP → Gateway 2.0

**Gateway 2.0 配置**：持有公网证书 `*.appdev.abjx`，终止 HTTPS，转写 Headers

```yaml
# gateway-2.0-ssl-terminate.yaml
---
# Secret: *.appdev.abjx 公网证书
apiVersion: v1
kind: Secret
metadata:
  name: gateway-2-external-cert
  namespace: gateway-system
  labels:
    app: gateway-2
type: kubernetes.io/tls
data:
  # 生成 CSR 并由外部 CA 签发
  # openssl req -new -key key.pem -out csr.pem -subj "/CN=*.appdev.abjx/O=AibangDev"
  tls.crt: <base64-encoded-cert>
  tls.key: <base64-encoded-key>
---
# Secret: Gateway 2.0 内部证书（用于后端验证）
apiVersion: v1
kind: Secret
metadata:
  name: gateway-2-internal-cert
  namespace: gateway-system
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-internal-cert>
  tls.key: <base64-encoded-internal-key>
---
# Gateway: SSL 终止 + Header 转写
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway-2-external
  namespace: gateway-system
  annotations:
    networking.gke.io/internal-load-balancer: "true"
    networking.gke.io/static-ip: "gateway-2-ip"
spec:
  gatewayClassName: gke-l7-rilb
  listeners:
  - name: https-external
    protocol: HTTPS
    port: 443
    hostname: "*"
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: gateway-2-external-cert
        namespace: gateway-system
    allowedRoutes:
      namespaces:
        from: All
  addresses:
  - type: IPAddress
    value: 10.100.0.100
---
# HTTPRoute: Header 转写 + 路由分发
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gateway-2-routes
  namespace: gateway-system
spec:
  parentRefs:
  - name: gateway-2-external
    namespace: gateway-system
    sectionName: https-external
  hostnames:
  - "*.appdev.abjx"
  rules:
  # ========== /iip/kong/* ==========
  - matches:
    - path:
        type: PathPrefix
        value: /iip/kong
    filters:
    # Header 转写（关键配置）
    - type: RequestHeaderModifier
      requestHeaderModifier:
        # 设置上游标识（Kong GW 2.0 根据此 header 做路由）
        set:
          X-Upstream-Service: kong-gateway-2
          X-Entry-Point: kong
        # 保留原始域名信息
        add:
          X-Original-Host: "%{request.host}%"
          X-SSL-Terminated: "gateway-2"
          X-Request-Path: "/iip/kong"
        # 移除敏感信息
        remove:
          - X-Forwarded-TLS-Connection
    backendRefs:
    - name: kong-gateway-2-svc
      namespace: iip
      port: 443

  # ========== /iip/direct/* ==========
  - matches:
    - path:
        type: PathPrefix
        value: /iip/direct
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
          X-Upstream-Service: iip-direct
          X-Entry-Point: direct
        add:
          X-Original-Host: "%{request.host}%"
          X-SSL-Terminated: "gateway-2"
          X-Request-Path: "/iip/direct"
    backendRefs:
    - name: iip-direct-svc
      namespace: iip
      port: 8443

  # ========== Default (兜底) ==========
  - matches:
    - path:
        type: PathPrefix
        value: /iip
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
          X-Upstream-Service: iip-default
          X-Entry-Point: default
        add:
          X-Original-Host: "%{request.host}%"
          X-SSL-Terminated: "gateway-2"
    backendRefs:
    - name: iip-default-svc
      namespace: iip
      port: 8080
```

### 第3跳：Gateway 2.0 → Kong GW 2.0 / Direct Backend

#### 3.1 Kong GW 2.0 配置（接收 HTTPS）

```yaml
# kong-gw2-deployment.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: iip
  labels:
    app: kong-gw-2
---
# Kong TLS Secret
apiVersion: v1
kind: Secret
metadata:
  name: kong-gw2-internal-cert
  namespace: iip
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-kong-cert>
  tls.key: <base64-encoded-kong-key>
---
# Kong Gateway 2.0 Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kong-gateway-2
  namespace: iip
spec:
  replicas: 2
  selector:
    matchLabels:
      app: kong-gateway-2
  template:
    metadata:
      labels:
        app: kong-gateway-2
      annotations:
        # Istio 注入配置（如使用 mTLS）
        inject.istio.io/inject: "true"
    spec:
      containers:
      - name: kong-gateway
        image: kong:3.5
        env:
        - name: KONG_MODE
          value: "proxy"
        # Kong 监听 HTTPS
        - name: KONG_PROXY_LISTEN
          value: "0.0.0.0:443 ssl"
        # 证书路径
        - name: KONG_SSL_CERT
          value: /etc/kong/ssl/tls.crt
        - name: KONG_SSL_CERT_KEY
          value: /etc/kong/ssl/tls.key
        # Admin API
        - name: KONG_ADMIN_LISTEN
          value: "0.0.0.0:8444"
        # Upstream 配置
        - name: KONG_UPSTREAM_KEEPALIVE_POOL_SIZE
          value: "32"
        ports:
        - name: proxy
          containerPort: 443
        - name: admin
          containerPort: 8444
        volumeMounts:
        - name: kong-ssl-certs
          mountPath: /etc/kong/ssl
          readOnly: true
        - name: kong-config
          mountPath: /usr/local/kong/declarative.yml
          subPath: declarative.yml
        readinessProbe:
          httpGet:
            path: /health
            port: 443
          initialDelaySeconds: 10
      volumes:
      - name: kong-ssl-certs
        secret:
          secretName: kong-gw2-internal-cert
      - name: kong-config
        configMap:
          name: kong-gw2-config

---
# Kong Gateway 2.0 Service
apiVersion: v1
kind: Service
metadata:
  name: kong-gateway-2-svc
  namespace: iip
  annotations:
    cloud.google.com/backend-config: '{"default": "kong-gw2-backend"}'
spec:
  type: ClusterIP
  ports:
  - name: proxy
    port: 443
    targetPort: 443
  selector:
    app: kong-gateway-2

---
# Kong Declarative Config
apiVersion: v1
kind: ConfigMap
metadata:
  name: kong-gw2-config
  namespace: iip
data:
  declarative.yml: |
    _format_version: "3.0"

    # 读取 Gateway 2.0 转写的 Header
    services:
    - name: api-backend
      url: https://iip-direct-svc.iip.svc.cluster.local:8443
      routes:
      - name: api-route
        strip_path: true
        paths:
        - /iip/direct
      plugins:
      - name: proxy-cache
        config:
          response_code: 200
          request_method: GET
          content_type: application/json

    # 基于 X-Upstream-Service header 路由（Gateway 注入）
    plugins:
    - name: request-transformer
      config:
        add:
          headers:
          - X-Kong-Downstream:gateway-2
```

#### 3.2 Direct Backend 配置

```yaml
# iip-direct-backend.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: iip
---
# Direct Backend TLS Secret
apiVersion: v1
kind: Secret
metadata:
  name: iip-direct-cert
  namespace: iip
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-direct-cert>
  tls.key: <base64-encoded-direct-key>
---
# Direct Backend Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: iip-direct
  namespace: iip
spec:
  replicas: 2
  selector:
    matchLabels:
      app: iip-direct
  template:
    metadata:
      labels:
        app: iip-direct
    spec:
      containers:
      - name: app
        image: your-app:latest
        ports:
        - name: https
          containerPort: 8443
        volumeMounts:
        - name: app-certs
          mountPath: /etc/certs
          readOnly: true
        env:
        - name: TLS_CERT_PATH
          value: /etc/certs/tls.crt
        - name: TLS_KEY_PATH
          value: /etc/certs/tls.key
      volumes:
      - name: app-certs
        secret:
          secretName: iip-direct-cert

---
# Direct Backend Service
apiVersion: v1
kind: Service
metadata:
  name: iip-direct-svc
  namespace: iip
spec:
  type: ClusterIP
  ports:
  - name: https
    port: 8443
    targetPort: 8443
  selector:
    app: iip-direct
```

---

## 4. Header 转写详解

### 4.1 Gateway 2.0 HTTPRoute Header 转写规则

```yaml
# 完整 Header 转写配置
filters:
- type: RequestHeaderModifier
  requestHeaderModifier:
    # ===== set: 覆盖已有值或设置新值 =====
    set:
      # 标识上游服务（Kong/Direct 根据此路由）
      X-Upstream-Service: kong-gateway-2

      # 标识入口点
      X-Entry-Point: kong

    # ===== add: 添加新 header（不存在时） =====
    add:
      # 保留原始请求域名
      X-Original-Host: "%{request.host}%"

      # 标识 SSL 终止位置
      X-SSL-Terminated: gateway-2

      # 标识请求路径
      X-Request-Path: "/iip/kong"

      # 时间戳
      X-Request-Timestamp: "%{current_time_iso}%"

    # ===== remove: 移除敏感/冗余 header =====
    remove:
      - X-Forwarded-TLS-Connection
      - X-Via-IIP
```

### 4.2 Header 流向

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ Header 流转                                                                 │
│                                                                               │
│ Client Request                                                                │
│   Host: api.appdev.abjx                                                      │
│   X-Real-IP: 203.0.113.1                                                     │
│   X-Forwarded-Proto: https                                                   │
│                                                                               │
│        │                                                                      │
│        ▼ PSC (passthrough)                                                    │
│                                                                               │
│        │                                                                      │
│        ▼ IIP (透传，可能添加 X-Forwarded-TLS-Connection)                      │
│                                                                               │
│        │                                                                      │
│        ▼ Gateway 2.0 (SSL 终止 + Header 转写)                                │
│           ─ X-Upstream-Service: kong-gateway-2                                │
│           ─ X-Entry-Point: kong                                               │
│           ─ X-Original-Host: api.appdev.abjx                                 │
│           ─ X-SSL-Terminated: gateway-2                                        │
│           ─ X-Request-Path: /iip/kong/...                                    │
│           ─ X-Real-IP: 203.0.113.1 (保留)                                    │
│                                                                               │
│        │                                                                      │
│        ▼ Kong GW 2.0 / Direct Backend                                        │
│                                                                               │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. 证书清单

### 5.1 证书用途总览

| 证书 | 持有者 | 用途 | 证书类型 |
|------|--------|------|----------|
| `*.appdev.abjx` | PSC Producer | 公网入口 | 公网 CA |
| `*.internal.iip.local` | IIP | IIP 入站 | 内部 CA |
| `gateway-2-external` | Gateway 2.0 | SSL 终止 | 公网 CA (`*.appdev.abjx`) |
| `gateway-2-internal` | Gateway 2.0 | 后端验证 | 内部 CA |
| `kong-gw2-internal` | Kong GW 2.0 | HTTPS 入站 | 内部 CA |
| `iip-direct-cert` | Direct Pods | HTTPS 入站 | 内部 CA |

### 5.2 证书存储

```yaml
# certificates.yaml
---
# 1. Gateway 2.0 公网证书 (*.appdev.abjx)
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
# 2. Gateway 2.0 内部证书（后端验证用）
apiVersion: v1
kind: Secret
metadata:
  name: gateway-2-internal-cert
  namespace: gateway-system
type: kubernetes.io/tls
data:
  tls.crt: <base64>
  tls.key: <base64>
---
# 3. IIP 内部证书
apiVersion: v1
kind: Secret
metadata:
  name: iip-internal-cert
  namespace: iip
type: kubernetes.io/tls
data:
  tls.crt: <base64>
  tls.key: <base64>
---
# 4. Kong GW 2.0 内部证书
apiVersion: v1
kind: Secret
metadata:
  name: kong-gw2-internal-cert
  namespace: iip
type: kubernetes.io/tls
data:
  tls.crt: <base64>
  tls.key: <base64>
---
# 5. Direct Backend 证书
apiVersion: v1
kind: Secret
metadata:
  name: iip-direct-cert
  namespace: iip
type: kubernetes.io/tls
data:
  tls.crt: <base64>
  tls.key: <base64>
```

---

## 6. 完整配置示例

### 6.1 IIP 配置

```nginx
# /etc/nginx/conf.d/iip-upstream.conf

# 上游：Gateway 2.0
upstream gateway2_upstream {
    server 10.100.0.100:443;
    keepalive 32;
}

# IIP 入站配置
server {
    listen 443 ssl;
    server_name _;

    # 入站证书（内部 CA 签发）
    ssl_certificate /etc/nginx/ssl/iip-internal.crt;
    ssl_certificate_key /etc/nginx/ssl/iip-internal.key;
    ssl_ca_file /etc/nginx/ssl/internal-ca.crt;
    ssl_verify_client optional_no_ca;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL;

    access_log /var/log/nginx/iip.access.log main;

    location / {
        # 出站到 Gateway 2.0（HTTPS）
        proxy_pass https://gateway2_upstream;

        proxy_http_version 1.1;

        # Host 头保持原始
        proxy_set_header Host $http_host;

        # SSL 相关头
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Port 443;

        # 客户端信息
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $http_x_forwarded_for;

        # 标识经过 IIP
        proxy_set_header X-Via-IIP: "true";

        # 出站 HTTPS 配置
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/nginx/ssl/internal-ca.crt;
        proxy_ssl_server_name on;
        proxy_ssl_name $host;

        proxy_set_header Connection "";

        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /health {
        return 200 'IIP: OK';
        add_header Content-Type text/plain;
    }
}
```

### 6.2 Gateway 2.0 完整配置

```yaml
# gateway-2.0-complete.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: gateway-system
---
# Secret: *.appdev.abjx 公网证书
apiVersion: v1
kind: Secret
metadata:
  name: gateway-2-external-cert
  namespace: gateway-system
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0t...
---
# Secret: Gateway 内部证书
apiVersion: v1
kind: Secret
metadata:
  name: gateway-2-internal-cert
  namespace: gateway-system
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...
  tls.key: LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0t...
---
# ComputeAddress: 预留 IP
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeAddress
metadata:
  name: gateway-2-ip
  namespace: gateway-system
spec:
  location: europe-west2
  purpose: SHARED_LOADBALANCER_VIP
  address: 10.100.0.100
---
# Gateway
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway-2-external
  namespace: gateway-system
  annotations:
    networking.gke.io/internal-load-balancer: "true"
    networking.gke.io/static-ip: "gateway-2-ip"
spec:
  gatewayClassName: gke-l7-rilb
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*"
    tls:
      mode: Terminate
      certificateRefs:
      - name: gateway-2-external-cert
        namespace: gateway-system
    allowedRoutes:
      namespaces:
        from: All
  addresses:
  - type: IPAddress
    value: 10.100.0.100
---
# HTTPRoute
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gateway-2-routes
  namespace: gateway-system
spec:
  parentRefs:
  - name: gateway-2-external
    namespace: gateway-system
    sectionName: https
  hostnames:
  - "*.appdev.abjx"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /iip/kong
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
          X-Upstream-Service: kong-gateway-2
          X-Entry-Point: kong
        add:
          X-Original-Host: "%{request.host}%"
          X-SSL-Terminated: gateway-2
          X-Request-Path: /iip/kong
    backendRefs:
    - name: kong-gateway-2-svc
      namespace: iip
      port: 443
  - matches:
    - path:
        type: PathPrefix
        value: /iip/direct
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set:
          X-Upstream-Service: iip-direct
          X-Entry-Point: direct
        add:
          X-Original-Host: "%{request.host}%"
          X-SSL-Terminated: gateway-2
          X-Request-Path: /iip/direct
    backendRefs:
    - name: iip-direct-svc
      namespace: iip
      port: 8443
```

---

## 7. Pod 间 mTLS 配置（SPIRE）

```yaml
# spire-mtls.yaml
---
# SPIRE Registration Entry for Kong GW 2.0
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: kong-gw2
spec:
  spiffeIDTemplate: "spiffe://cluster.local/ns/{{.PodMeta.Namespace}}/sa/{{.PodSpec.ServiceAccountName}}"
  podSelector:
    matchLabels:
      app: kong-gateway-2
---
# SPIRE Registration Entry for Direct Backend
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: iip-direct
spec:
  spiffeIDTemplate: "spiffe://cluster.local/ns/{{.PodMeta.Namespace}}/sa/{{.PodSpec.ServiceAccountName}}"
  podSelector:
    matchLabels:
      app: iip-direct
---
# PeerAuthentication (mTLS STRICT mode)
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: iip
spec:
  mtls:
    mode: STRICT
```

---

## 8. 总结

### 每跳 HTTPS 配置

| 跳 | 组件 | 入站证书 | 出站证书 |
|----|------|----------|----------|
| 1 | PSC → IIP | PSC Producer (`*.appdev.abjx`) | IIP 内部 (`*.internal.iip.local`) |
| 2 | IIP → Gateway 2.0 | IIP 内部 | Gateway 2.0 (`*.appdev.abjx`) |
| 3 | Gateway 2.0 → Kong/Direct | Gateway 2.0 公网证书 | Kong/Direct 内部证书 |
| 4 | Pod → Pod | SPIRE mTLS | SPIRE mTLS |

### Header 转写位置

**Gateway 2.0** 是唯一的 Header 转写点：
- `X-Upstream-Service`: 标识目标服务
- `X-Entry-Point`: 标识入口类型
- `X-Original-Host`: 保留原始域名
- `X-SSL-Terminated`: 标识 SSL 终止位置
- `X-Request-Path`: 标识原始请求路径
