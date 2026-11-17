# Cross-Nginx Header Rewrite — Internal Domain Isolation

> **文档版本**: 1.0.0  
> **更新日期**: 2026-05-07  
> **场景**: 外部域名入口 → Nginx → 内部 Kong DP（仅监听内部域名）

---

## 1. 背景与问题

### 1.1 业务拓扑

```
Client
  │
  │  www.abjx.com/apiname1/endpoint
  │  www.abjx.com/apiname2/endpoint
  ▼
Nginx (公网入口)
  │  server_name: www.abjx.com
  │  SSL termination
  │  ⚠ Host header rewrite (www.abjx.com → www.aibang.com)
  ▼
GKE Kong Data Plane (内部)
  │  仅监听: www.aibang.com
  │  路由: /apiname1/* → Runtime-1
  │  路由: /apiname2/* → Runtime-2
  ▼
GKE Runtime (Service A / Service B)
```

### 1.2 核心矛盾

| 要素 | 外部（公网） | 内部（Kong DP） |
|------|------------|----------------|
| **域名** | `www.abjx.com` | `www.aibang.com` |
| **证书** | *.abjx.com（公网 CA） | 内部 CA 或相同证书 |
| **监听端口** | 80 / 443 | 8000 / 8443 |
| **Host 头部** | `Host: www.abjx.com` | 期望 `Host: www.aibang.com` |

**问题**: Kong DP 只认 `www.aibang.com`，但客户端请求的 Host 是 `www.abjx.com`。需要在 Nginx 层做 Host 头部改写。

---

## 2. 解决方案

### 2.1 核心思路

Nginx 作为**反向代理 + TLS termination**，在转发给 Kong DP 之前，将请求头中的 `Host` 从 `www.abjx.com` 改写为 `www.aibang.com`，同时保留原始 Host 供排查使用。

### 2.2 Nginx 配置

```nginx
# ============================================================
# upstream: GKE Kong Data Plane internal service
# ============================================================
upstream kong_dp_backend {
    server kong-dp.gke-namespace.svc.cluster.local:8000;
    keepalive 32;
}

# ============================================================
# HTTP → HTTPS 重定向（可选，根据业务需求启用）
# ============================================================
server {
    listen 80;
    server_name www.abjx.com;

    # 强制跳转到 HTTPS
    return 301 https://$host$request_uri;
}

# ============================================================
# HTTPS 入口：处理公网域名 www.abjx.com
# ============================================================
server {
    listen 443 ssl http2;
    server_name www.abjx.com;

    # ----- SSL 配置（公网证书 *.abjx.com）-----
    ssl_certificate     /etc/nginx/ssl/abjx.com.crt;
    ssl_certificate_key /etc/nginx/ssl/abjx.com.key;

    # 现代 TLS 配置
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

    # ----- 日志格式：记录原始域名和目标域名 -----
    log_format main '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    'original_host=$http_host upstream_host=$http_x_original_host';

    access_log /var/log/nginx/access.log main;
    error_log  /var/log/nginx/error.log warn;

    # ----- 默认location：转发所有请求到 Kong DP -----
    location / {
        # ---------- 关键：Host 头部改写 ----------
        # 将外部域名改写为内部 Kong DP 监听的域名
        proxy_set_header Host www.aibang.com;

        # 保留原始 Host 到自定义头部，供后端日志和排障使用
        proxy_set_header X-Original-Host $host;

        # 标准代理头部
        proxy_set_header X-Real-IP       $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 保留原始请求 URI（包含路径和查询字符串）
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # 超时配置（根据实际业务调整）
        proxy_connect_timeout 5s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;

        # ---------- 转发到 Kong DP ----------
        proxy_pass http://kong_dp_backend;
    }

    # ----- 健康检查端点（Nginx 自身）-----
    location /health {
        access_log off;
        return 200 "nginx healthy\n";
        add_header Content-Type text/plain;
    }
}
```

### 2.3 配置要点解析

| 配置项 | 作用 | 注意事项 |
|--------|------|---------|
| `proxy_set_header Host www.aibang.com` | **核心**：将 Host 改写为 Kong DP 监听的内部域名 | 必须是 Kong DP 配置中声明的 server_name |
| `proxy_set_header X-Original-Host $host` | 保留原始域名到自定义头部 | Kong 侧可据此记录真实来源 |
| `$host` vs `$http_host` | `$host` 不含端口，`$http_host` 含端口 | 通常用 `$host` 更干净 |
| `keepalive 32` | upstream 保持长连接 | 降低 Kong DP 的连接建立开销 |
| `proxy_pass http://kong_dp_backend` | 反向代理到 upstream | 注意不是 `https://`，内部通信通常用 http |

---

## 3. Kong DP 侧配置（参考）

Kong DP 需要声明对 `www.aibang.com` 的监听，通常通过 `KongIngress` 或 Annotation 实现：

```yaml
# Kong DP Service / Ingress 注解示例
metadata:
  annotations:
    kubernetes.io/ingress.class: kong
    konghq.com/protocol: "http"          # 内部通信用 http
    konghq.com/preserve-host: "false"    # 关键：Kong 使用 route 的 host 而非请求 Host
```

**关键点**: `preserve-host: "false"` 告诉 Kong 不要把请求的 Host 头用于路由匹配，而是使用 Route 定义的 `hosts` 规则。

---

## 4. 请求流程详解

```
┌──────────────────────────────────────────────────────────────┐
│  Step 1: Client                                              │
│  GET /apiname1/endpoint HTTP/1.1                             │
│  Host: www.abjx.com                                          │
│  User-Agent: curl/7.88.1                                     │
└────────────────────────┬─────────────────────────────────────┘
                         │ 公网请求 (TLS)
                         ▼
┌──────────────────────────────────────────────────────────────┐
│  Step 2: Nginx (www.abjx.com)                                │
│  - TLS termination (使用 *.abjx.com 公网证书)               │
│  - 日志记录 original_host = www.abjx.com                     │
│  - proxy_set_header Host www.aibang.com    ← 改写           │
│  - proxy_set_header X-Original-Host www.abjx.com  ← 保留   │
│  - proxy_pass http://kong_dp_backend/                       │
└────────────────────────┬─────────────────────────────────────┘
                         │ 内部请求 (HTTP, Host = www.aibang.com)
                         ▼
┌──────────────────────────────────────────────────────────────┐
│  Step 3: Kong DP (listens: www.aibang.com)                  │
│  - 根据 Route: www.aibang.com + /apiname1/*                 │
│  - 匹配到对应的 Service/Runtime                              │
│  - X-Original-Host: www.abjx.com（用于日志追踪）            │
│  - 路由到对应的 upstream (Runtime-1)                        │
└────────────────────────┬─────────────────────────────────────┘
                         │ 内部 gRPC/HTTP
                         ▼
┌──────────────────────────────────────────────────────────────┐
│  Step 4: GKE Runtime (Service A)                             │
│  收到请求: Host = www.aibang.com (Kong 传入)                │
│  路径: /apiname1/endpoint                                    │
│  Header: X-Original-Host = www.abjx.com（可选）             │
└──────────────────────────────────────────────────────────────┘
```

---

## 5. 验证步骤

### 5.1 本地 curl 测试（模拟 Nginx 行为）

```bash
# 直接测试 Kong DP（Host 头部 = www.aibang.com）
curl -v -H "Host: www.aibang.com" \
     http://<kong-dp-internal-ip>/apiname1/endpoint

# 测试原始域名（www.abjx.com）通过 Nginx
curl -v --resolve www.abjx.com:443:<nginx-external-ip> \
     https://www.abjx.com/apiname1/endpoint \
     --cacert /path/to/abjx.com.crt
```

### 5.2 Nginx 配置语法检查

```bash
# 检查配置语法
nginx -t

# 重新加载配置（不中断连接）
nginx -s reload
```

### 5.3 日志排查

```bash
# 查看原始域名访问情况
grep "X-Original-Host=www.abjx.com" /var/log/nginx/access.log | head -20

# 查看 Kong DP 日志（确认收到的是哪个 Host）
kubectl logs -n kong deploy/kong-dp -f | grep "www.aibang.com"
```

---

## 6. 风险与注意事项

### 6.1 风险

| 风险 | 等级 | 缓解措施 |
|------|------|---------|
| Host 头部改写错误导致 Kong 路由失败 | **高** | 上线前用 curl 模拟测试；配置 `preserve-host: "false"` |
| SSL 证书域名不匹配 | **中** | 确保 Nginx 用 *.abjx.com 证书，Kong 用 *.aibang.com 或相同证书 |
| Nginx 成为单点故障 | **高** | 至少部署 2 个 Nginx 实例，使用 GKE NodePool 保障 HA |
| X-Original-Host 泄露内部架构 | **低** | 仅在需要排障时使用，生产可移除 |

### 6.2 注意事项

1. **Kong preserve-host**: 确保 Kong 侧设置了 `preserve-host: "false"`，否则 Kong 会把 `www.abjx.com` 当作路由依据。
2. **内部 DNS**: `kong-dp.gke-namespace.svc.cluster.local` 需在 Nginx 的 DNS 解析范围内，建议使用 ClusterIP Service + CoreDNS。
3. **健康检查**: Nginx 需对 upstream 做主动健康检查，防止流量打到已停止的 Kong Pod。
4. **超时对齐**: Nginx 的 `proxy_read_timeout` 应大于等于 Kong 的超时配置，避免过早断开。

---

## 7. 多域名扩展

如果未来有更多外部域名需要路由到同一个 Kong DP：

```nginx
# 使用 map 指令做域名映射
map $http_host $upstream_host {
    default                    "kong-dp.gke-namespace.svc.cluster.local:8000";
    "www.abjx.com"             "kong-dp.gke-namespace.svc.cluster.local:8000";
    "api.abjx.com"             "kong-dp.gke-namespace.svc.cluster.local:8000";
    "m.abjx.com"               "kong-dp-mobile.gke-namespace.svc.cluster.local:8000";
}

server {
    server_name www.abjx.com api.abjx.com m.abjx.com;
    
    location / {
        proxy_set_header Host $upstream_host;
        # 这个用法不对，Host 头不能这样动态...
        # 正确的做法是分开 server {} 块
    }
}
```

> **推荐做法**：每个外部域名使用独立的 `server {}` 块，保持配置清晰，便于独立维护和排查。

---

## 8. 配置清单

| 文件 | 路径 | 说明 |
|------|------|------|
| Nginx 主配置 | `/etc/nginx/nginx.conf` | 包含 upstream、server 块 |
| SSL 证书 | `/etc/nginx/ssl/abjx.com.crt` | *.abjx.com 公网证书 |
| SSL 私钥 | `/etc/nginx/ssl/abjx.com.key` | 私钥文件 |
| 访问日志 | `/var/log/nginx/access.log` | 含 original_host 字段 |
| 错误日志 | `/var/log/nginx/error.log` | warn 级别 |
| 健康检查 | `/health` | Nginx 自身健康端点 |

---

*文档基于 GKE + Kong DP 内部域名隔离场景生成*
