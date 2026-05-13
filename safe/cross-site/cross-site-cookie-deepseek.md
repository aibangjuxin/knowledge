# Cross-Site Cookie 深度分析 — 同一域名多路径路由方案

> **文档版本**: 1.0.0  
> **更新日期**: 2026-05-07  
> **状态**: 深度技术分析  
> **分类**: Internal — Safe to Share  
> **前置文档**: `cross-analysis.md`（基础分析）、`cross-nginx-header.md`（Header 重写）

---

## 1. 问题背景与新场景

### 1.1 已知问题回顾

`cross-analysis.md` 中已明确：

- 前端页面 `www.abjx.com` 与 API 域名为不同域名时，浏览器将 Cookie 视为 **Third-Party Cookie**
- Firefox / Safari 默认阻止第三方 Cookie，导致用户认证失败（`"We were unable to authenticate you"`）
- **根本解决方案**：使用同一域名作为所有请求的入口，使浏览器将所有 Cookie 视为 **First-Party Cookie**

### 1.2 新场景：GKE API Platform + 多 GCP 项目后端

**当前架构流程：**

```
Client (Browser)
  │
  │  https://www.abjx.com/apiname1/endpoint
  │  https://www.abjx.com/apiname2/endpoint
  │  （同一域名，同一入口）
  ▼
Nginx (公网入口)
  │  统一域名: www.abjx.com
  │  TLS Termination
  │  根据路径分发 → Kong DP
  ▼
GKE Kong Data Plane
  │  路由: /apiname1/* → Runtime-1 (同集群)
  │  路由: /apiname2/* → Runtime-2 (同集群)
  │  路由: /apiname3/* → External Backend (其他 GCP 项目)
  ▼
GKE Runtime / External Service
```

**新增需求点：**

| 需求 | 说明 |
|------|------|
| 统一入口 | 所有请求从 `www.abjx.com` 进入 |
| 按路径分发 | `/apiname1/*` → Kong Runtime A，`/apiname2/*` → Kong Runtime B |
| 跨 GCP 项目 | `/apiname3/*` → 其他 GCP 工程的 Backend Service（需 HTTPS proxy） |
| Cookie 同源 | 浏览器只看到 `www.abjx.com`，所有 Cookie 为 First-Party |
| 内部域名隔离 | Kong DP 仅监听内部域名（如 `www.aibang.com`），通过 Header 改写实现 |

---

## 2. 核心机制：同一域名多路径路由

### 2.1 为什么同一域名能解决 Cross-Site Cookie

**浏览器 Same-Site 判断逻辑：**

```
浏览器判断 Cookie 是否为 "same-site"：
1. 读取请求的 URL 的 origin (scheme + domain + port)
2. 读取 Set-Cookie 头部的 Domain 属性
3. 如果 Domain 匹配当前 URL 的 domain → First-Party Cookie
4. 如果不匹配 → Third-Party Cookie → 可能被阻止
```

**关键洞察：** 当所有请求（前端页面 + API 调用）都来自 `www.abjx.com` 时，浏览器认为所有 `Set-Cookie` 都来自同一个 Site，Cookie 不会被阻止。

### 2.2 路径路由 vs 域名路由

| 路由方式 | 外部视角（浏览器） | 内部实现 | Cookie 状态 |
|---------|-----------------|---------|------------|
| **路径路由**（本方案）| 所有请求 → `www.abjx.com` | Nginx 按 path 分发到不同 backend | ✅ First-Party |
| 域名路由（旧方案） | 不同域名 | 浏览器天然视为 cross-site | ❌ Third-Party |

### 2.3 路径设计

```
www.abjx.com/
├── /                    → 前端静态页面（或重定向到 UI）
├── /apiname1/           → Kong DP → Runtime-1 (GKE 同集群)
├── /apiname2/           → Kong DP → Runtime-2 (GKE 同集群)
├── /apiname3/           → Kong DP → Runtime-3 (GKE 同集群)
├── /ext-crm/            → Nginx 直接 proxy_pass HTTPS → 其他 GCP 项目 CRM Service
├── /ext-erp/            → Nginx 直接 proxy_pass HTTPS → 其他 GCP 项目 ERP Service
└── /health              → Nginx 健康检查
```

**命名空间隔离**：每个 `apiname` 对应一个独立的 Kong Route + Service + Runtime，路径前缀即隔离边界。

---

## 3. Nginx 完整配置

### 3.1 整体架构

```nginx
# ============================================================
# upstream 定义
# ============================================================

# GKE Kong DP（内部通信用 HTTP）
upstream kong_dp {
    server kong-dp.gke-namespace.svc.cluster.local:8000;
    keepalive 32;
}

# 其他 GCP 项目的后端服务（外部 HTTPS）
upstream ext_crm_backend {
    server crm.internal.other-project.example.com:443;
}

upstream ext_erp_backend {
    server erp.internal.other-project.example.com:443;
}

# 前端静态资源（可选，如有独立前端服务）
upstream frontend_static {
    server frontend-svc.gke-namespace.svc.cluster.local:8080;
}

# ============================================================
# HTTP → HTTPS 重定向
# ============================================================
server {
    listen 80;
    server_name www.abjx.com;
    return 301 https://$host$request_uri;
}

# ============================================================
# HTTPS 入口 (统一域名 www.abjx.com)
# ============================================================
server {
    listen 443 ssl http2;
    server_name www.abjx.com;

    # ----- SSL 配置（*.abjx.com 公网证书）-----
    ssl_certificate     /etc/nginx/ssl/abjx.com.crt;
    ssl_certificate_key /etc/nginx/ssl/abjx.com.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

    # ----- 日志格式 -----
    log_format main '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    'upstream=$upstream_addr '
                    'upstream_status=$upstream_status';

    access_log /var/log/nginx/access.log main;
    error_log  /var/log/nginx/error.log warn;

    # ============================================================
    # 路径路由：APIName1 → Kong DP
    # ============================================================
    location /apiname1/ {
        # Header 改写：Host 改为 Kong DP 内部监听域名
        proxy_set_header Host www.aibang.com;
        proxy_set_header X-Original-Host $host;
        proxy_set_header X-Original-URI $request_uri;

        proxy_set_header X-Real-IP       $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 5s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;

        proxy_pass http://kong_dp/apiname1/;
    }

    # ============================================================
    # 路径路由：APIName2 → Kong DP
    # ============================================================
    location /apiname2/ {
        proxy_set_header Host www.aibang.com;
        proxy_set_header X-Original-Host $host;
        proxy_set_header X-Original-URI $request_uri;

        proxy_set_header X-Real-IP       $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 5s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;

        proxy_pass http://kong_dp/apiname2/;
    }

    # ============================================================
    # 路径路由：跨 GCP 项目 CRM（直接 HTTPS proxy_pass）
    # ============================================================
    location /ext-crm/ {
        # 保留原始 Host（外部服务可能需要）
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP       $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 关键：向上游服务传递原始路径
        proxy_set_header X-Original-URI $request_uri;

        # HTTPS 向上游（使用 CA 证书验证，或允许自签名）
        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/nginx/ssl/ca-certs.pem;
        proxy_ssl_server_name on;         # SNI 支持
        proxy_ssl_name $host;             # SNI 名称

        proxy_connect_timeout 10s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;

        proxy_pass https://ext_crm_backend/ext-crm/;
    }

    # ============================================================
    # 路径路由：跨 GCP 项目 ERP（直接 HTTPS proxy_pass）
    # ============================================================
    location /ext-erp/ {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP       $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Original-URI $request_uri;

        proxy_ssl_verify on;
        proxy_ssl_trusted_certificate /etc/nginx/ssl/ca-certs.pem;
        proxy_ssl_server_name on;
        proxy_ssl_name $host;

        proxy_connect_timeout 10s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;

        proxy_pass https://ext_erp_backend/ext-erp/;
    }

    # ============================================================
    # 前端静态资源（可选）
    # ============================================================
    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ /index.html;

        # 静态资源缓存
        location ~* \.(css|js|images?|fonts?|ico|svg|woff2?)$ {
            expires 1d;
            add_header Cache-Control "public, immutable";
        }
    }

    # ============================================================
    # 健康检查
    # ============================================================
    location /health {
        access_log off;
        return 200 "nginx healthy\n";
        add_header Content-Type text/plain;
    }
}
```

### 3.2 配置要点解析

| 配置块 | 关键指令 | 作用 |
|--------|---------|------|
| **Kong DP 路由** | `proxy_set_header Host www.aibang.com` | 将 Host 改写为 Kong 内部监听域名（见 `cross-nginx-header.md`） |
| **Kong DP 路由** | `proxy_pass http://kong_dp/apiname1/` | 保留路径前缀，Kong 按 Route 匹配 |
| **跨 GCP 项目** | `proxy_ssl_verify on` + `proxy_ssl_server_name on` | 启用 HTTPS 双向验证 + SNI |
| **跨 GCP 项目** | `proxy_set_header X-Original-URI` | 保留原始路径供上游服务日志追踪 |
| **所有路由** | `X-Forwarded-*` headers | 传递原始客户端信息 |
| **所有路由** | `proxy_buffering` (默认 on) | API 响应建议开启；流式响应关闭 |

---

## 4. Kong DP 侧配置

### 4.1 Kong Route 定义（apiname1 为例）

每个 `apiname` 在 Kong 中对应独立的 Service + Route：

```yaml
# apiname1-service.yaml
apiVersion: configuration.konghq.com/v1
kind: KongIngress
metadata:
  name: apiname1-service
  namespace: kong
spec:
  proxy:
    protocol: http
    host: runtime1-svc.runtime-ns.svc.cluster.local
    port: 8080
    path: /
---
# apiname1-route.yaml
apiVersion: configuration.konghq.com/v1
kind: KongIngress
metadata:
  name: apiname1-route
  namespace: runtime-ns   # 实际业务 NS
  annotations:
    konghq.com/protocol: http
    konghq.com/preserve-host: "false"   # 关键：不使用请求的 Host 做路由
spec:
  route:
    - name: apiname1-route
      methods:
        - GET
        - POST
        - PUT
        - DELETE
        - PATCH
      paths:
        - /apiname1/
      strip_path: false   # 保留 /apiname1/ 前缀传递给上游
```

### 4.2 preserve-host: "false" 的关键作用

```
Nginx 传入:  Host: www.aibang.com, URI: /apiname1/endpoint
                    ↓
Kong Route 匹配:  hosts=www.aibang.com + path=/apiname1/*
                    ↓
preserve-host: false  → Kong 使用 Route 定义的上游地址，不传递请求 Host
                    ↓
Runtime 收到:  Host=runtime1-svc.runtime-ns (上游定义)
              X-Original-Host=www.abjx.com (Nginx 传入)
              X-Original-URI=/apiname1/endpoint (Nginx 传入)
```

---

## 5. Cross-Site Cookie 解决机制

### 5.1 Cookie 流转全过程

```
┌─────────────────────────────────────────────────────────────┐
│  Browser                                                    │
│  URL: https://www.abjx.com/apiname1/endpoint               │
│  Cookie jar: (empty initially)                             │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTPS Request
                         │ GET /apiname1/endpoint
                         │ Host: www.abjx.com
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Nginx (www.abjx.com)                                       │
│  proxy_set_header Host www.aibang.com   ← Header 改写      │
│  proxy_pass http://kong_dp/apiname1/                        │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTP (internal)
                         │ GET /apiname1/endpoint
                         │ Host: www.aibang.com
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Kong DP                                                    │
│  Route: /apiname1/* → Runtime-1                            │
│  Runtime 返回:                                              │
│    HTTP/1.1 200 OK                                          │
│    Set-Cookie: abjx_session=xyz; SameSite=Lax; Secure;     │
│                HttpOnly; Path=/                              │
└────────────────────────┬────────────────────────────────────┘
                         │ Response (Cookie: Domain=www.abjx.com)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Nginx (透传 Response)                                      │
│  透传 Set-Cookie 到浏览器                                    │
│  浏览器解析 Cookie:                                          │
│    Domain = www.abjx.com  ← 匹配当前 URL origin             │
│    → First-Party Cookie ✅                                  │
│    → Cookie 保存到 jar                                       │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 为什么这是 First-Party Cookie

**浏览器判断标准（简化版）：**

```
请求 URL:  https://www.abjx.com/apiname1/endpoint
Cookie:    Domain=www.abjx.com

判断：
  - Cookie Domain (www.abjx.com) 是否是请求 URL Domain (www.abjx.com) 的同源或父域？
  - 是 → Same-Site (First-Party)
```

**浏览器实际判断：**

```
URL origin:     https://www.abjx.com
Cookie Domain: www.abjx.com

→ 精确匹配 → 浏览器将 Cookie 视为 First-Party
→ Cookie 不会被 Firefox/Safari 的追踪保护阻止
```

### 5.3 Cookie 属性配置（必需）

无论 Kong Runtime 还是外部服务，所有 Set-Cookie 必须包含以下属性：

```nginx
# Nginx 层统一加固（兜底）
proxy_cookie_path / "/; SameSite=Lax; Secure; HttpOnly; Path=/";
```

```bash
# 推荐在后端服务层设置（更根本）
Set-Cookie: abjx_session=abc123; SameSite=Lax; Secure; HttpOnly; Path=/; Domain=www.abjx.com
```

| 属性 | 推荐值 | 原因 |
|------|-------|------|
| `SameSite` | `Lax` | 允许同站 + 安全跨站 GET；比 `None` 更安全，比 `Strict` 更宽松 |
| `Secure` | `必需` | 确保 Cookie 仅在 HTTPS 下传输 |
| `HttpOnly` | `必需` | 防止 JavaScript 读取（防 XSS 盗取） |
| `Path` | `/` | 全局共享 |
| `Domain` | `www.abjx.com` | 显式指定（可选，隐含同源） |

---

## 6. 跨 GCP 项目 HTTPS 代理详解

### 6.1 需求场景

```
www.abjx.com/ext-crm/orders
                    │
                    ▼
              Nginx (www.abjx.com)
                    │ HTTPS upstream (SNI = $host)
                    ▼
              CRM Service (other-gcp-project)
              Internal domain: crm.internal.other-project.example.com
              内部 mTLS 要求: YES
```

### 6.2 HTTPS Upstream 关键配置

```nginx
# upstream 定义
upstream ext_crm_backend {
    server crm.internal.other-project.example.com:443;
}

location /ext-crm/ {
    # SNI — 向上游传递请求的 Host
    proxy_ssl_server_name on;
    proxy_ssl_name $host;          # 使用 $host (= www.abjx.com) 或指定域名

    # 证书验证
    proxy_ssl_verify on;
    proxy_ssl_trusted_certificate /etc/nginx/ssl/internal-ca.pem;

    # 双向认证（如果上游要求）
    proxy_ssl_certificate /etc/nginx/ssl/nginx-client.crt;
    proxy_ssl_certificate_key /etc/nginx/ssl/nginx-client.key;

    proxy_pass https://ext_crm_backend/ext-crm/;
}
```

### 6.3 证书管理策略

| 场景 | 证书配置 |
|------|---------|
| Nginx → Kong DP (同集群) | HTTP，无需证书 |
| Nginx → 内部 HTTPS 服务（同一 GCP 项目） | GCP 内部 CA (`certificate-manager` 或 `KIAM`) |
| Nginx → 其他 GCP 项目服务 | 内部 CA 证书，或 GCP 全局根 CA |
| 跨公司/外部服务 | 公网 CA 或 mutual TLS |

---

## 7. 请求流程完整图

```
Client (Browser)
│  URL: https://www.abjx.com/apiname1/endpoint
│  Cookie: (自动携带同站 cookie)
│  Host: www.abjx.com
│
▼ HTTPS
┌──────────────────────────────────────────────────────────┐
│ Nginx (www.abjx.com)                                     │
│                                                          │
│  location /apiname1/                                      │
│    proxy_set_header Host www.aibang.com  ← Header 改写   │
│    proxy_pass http://kong_dp/apiname1/                   │
│                                                          │
│  location /ext-crm/                                       │
│    proxy_ssl_server_name on                              │
│    proxy_pass https://ext_crm_backend/ext-crm/            │
│                                                          │
│  location /ext-erp/                                       │
│    proxy_ssl_server_name on                              │
│    proxy_pass https://ext_erp_backend/ext-erp/           │
└────────────────────────┬─────────────────────────────────┘
                         │
          ┌──────────────┴──────────────┐
          │ HTTP internal               │ HTTPS + SNI
          ▼                             ▼
┌──────────────────────┐    ┌──────────────────────────────┐
│ Kong DP              │    │ External GCP Project         │
│ (www.aibang.com)     │    │ (crm.internal.example.com)   │
│                      │    │                              │
│ Route: /apiname1/* ──┼──► │  /ext-crm/*                  │
│  → Runtime-1 (GKE)   │    │    ↑ proxy_ssl_server_name   │
│                      │    │    ↑ proxy_ssl_verify on      │
│ Route: /apiname2/* ──┼───►│                              │
│  → Runtime-2 (GKE)   │    └──────────────────────────────┘
│                      │
│ preserve-host: false │
└────────────────────────┬─────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ GKE Runtime-1        │
              │                      │
              │ X-Original-Host:     │
              │   www.abjx.com       │
              │                      │
              │ Set-Cookie:          │
              │ Domain=www.abjx.com  │
              │   SameSite=Lax       │
              │   Secure; HttpOnly   │
              └──────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ Browser              │
              │ Cookie Domain 匹配   │
              │ www.abjx.com ✅      │
              │                      │
              │ First-Party Cookie ✅│
              │ 不会被阻止           │
              └──────────────────────┘
```

---

## 8. 安全考量

### 8.1 CSRF 防护

Same-Site Cookie (`Lax`) 本身提供 CSRF 保护：

| SameSite 模式 | GET 请求 | POST/PUT/DELETE |
|-------------|---------|----------------|
| `Strict` | ✅ 受保护 | ✅ 受保护 |
| `Lax` | ✅ 受保护 | ⚠️ 不受保护（来自外部网站的 POST） |
| `None` | ❌ 不保护 | ❌ 不保护 |

**建议**：除 GET 外的所有操作，使用 `SameSite=Lax` + **CSRF Token** 双保险：

```html
<!-- 前端页面中嵌入 CSRF Token -->
<meta name="csrf-token" content="{{ csrf_token }}">
```

```javascript
// AJAX 请求中附加 CSRF Token
fetch('/apiname1/api/orders', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
  },
  body: JSON.stringify(data)
});
```

### 8.2 XSS 防护

`HttpOnly` Cookie 属性防止 JavaScript 读取：

```bash
# 有 HttpOnly：document.cookie 不可读取
# 无 HttpOnly：XSS 脚本可读取 session cookie
```

### 8.3 HTTPS 强制

```nginx
# 强制所有内部 HTTPS 通信
proxy_set_header X-Forwarded-Proto https;
```

### 8.4 内部架构隐藏

```
浏览器仅知: www.abjx.com
内部域名 (www.aibang.com, crm.internal.example.com) 对浏览器不可见
X-Original-Host 仅在内部流转，不暴露给浏览器
```

---

## 9. 性能考量

### 9.1 Nginx 静态缓存

```nginx
location ~* \.(css|js|images?|fonts?|ico|svg|woff2?)$ {
    proxy_cache static_cache;
    proxy_cache_valid 200 1d;
    add_header X-Cache-Status $upstream_cache_status;
    expires 1d;
    add_header Cache-Control "public, no-transform";
}
```

### 9.2 Kong DP 长连接优化

```nginx
upstream kong_dp {
    server kong-dp.gke-namespace.svc.cluster.local:8000;
    keepalive 32;      # 保持 32 个空闲长连接
}
```

### 9.3 跨 GCP 项目超时配置

```nginx
# 外部服务延迟更高，适当延长超时
location /ext-crm/ {
    proxy_connect_timeout 10s;   # 外部网络可能慢
    proxy_send_timeout    120s;
    proxy_read_timeout    120s;
}
```

---

## 10. 与 cross-analysis.md Option 2 的关系

| 对比项 | cross-analysis.md (Option 2) | 本文档 (路径路由方案) |
|--------|------------------------------|---------------------|
| **入口** | 单一 origin | 单一 origin (`www.abjx.com`) |
| **路由粒度** | `/` (前端) vs `/api/` (API) | `/apiname1/`, `/apiname2/`, `/ext-crm/` |
| **内部实现** | 单 upstream | Kong DP (GKE) + 跨 GCP 项目 |
| **Cookie 效果** | ✅ First-Party | ✅ First-Party（机制相同） |
| **Header 改写** | 未涉及 | 核心机制（`www.abjx.com` → `www.aibang.com`） |
| **HTTPS Upstream** | 基础 `proxy_pass https://` | 完整 SNI + 证书验证 + mTLS |

**结论**：本文档是 `cross-analysis.md` Option 2 在 GKE Kong 平台场景下的**具体工程实现**，核心机制（单一域名消除 Third-Party Cookie）完全一致。

---

## 11. 决策清单

- [ ] Nginx 部署完成，统一入口 `www.abjx.com`
- [ ] Kong DP 配置 `preserve-host: "false"` + `Host www.aibang.com` Header 改写
- [ ] 所有 Kong Route 的 `strip_path: false`（保留路径前缀）
- [ ] 跨 GCP 项目 upstream 配置 `proxy_ssl_server_name on` + CA 证书
- [ ] 所有后端服务设置 `SameSite=Lax; Secure; HttpOnly`
- [ ] Nginx 层 `proxy_cookie_path` 兜底加固
- [ ] CSRF Token 集成（POST/PUT/DELETE 请求）
- [ ] 静态资源 Nginx 缓存配置
- [ ] Kong DP upstream `keepalive` 配置
- [ ] 跨 GCP 项目超时配置调整
- [ ] 浏览器 DevTools 验证 Cookie Domain = `www.abjx.com`，类型 = First-Party
- [ ] Firefox（默认 ETP 开启）认证流程测试

---

## 12. 参考文档

- [SameSite Cookies Explained — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie/SameSite)
- [SameSite=None: Required Secure — Chrome Developers](https://www.chromium.org/updates/privacy-sandbox)
- [proxy_ssl_server_name — Nginx docs](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ssl_server_name)
- [Kong preserve-host annotation](https://docs.konghq.com/kubernetes-ingress-controller/latest/references/annotations/#konghqcompreserve-host)
- `cross-analysis.md` — Cross-Site Cookie 基础分析
- `cross-nginx-header.md` — Nginx Host Header 重写详解

---

*本文档为 GKE API Platform 场景下的 Cross-Site Cookie 深度技术分析，与 cross-analysis.md 配套使用*
