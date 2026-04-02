文档无法直接访问（GitHub 私有仓库或网络限制），但基于你描述的需求已经足够完整，我直接进行方案分析。

---

## 问题分析

核心矛盾点：**在哪一层做 Host 改写，决定了后续每一层的复杂度分布**。

| 决策点 | Nginx 改写 Host | Nginx 不改写 Host |
|--------|-----------------|-------------------|
| Nginx 配置复杂度 | 中（需维护改写规则） | 低（纯透传） |
| 内部证书 | 只需一套内部证书 | 证书数量随 team 增长 |
| Gateway/VS 配置 | 统一 host 匹配，简单 | 需匹配外部域名，复杂 |
| Onboarding 负担 | Nginx 层需介入 | CICD 团队维护 Gateway+VS |
| API 级特例（大小/超时） | Nginx location 块 | Nginx location 块（相同） |

---

## 最佳实践方案：推荐 **方案 A —— Nginx 做 Team 级 Host 改写 + Istio 做 API 级路由**

### 核心思路

```
外部请求 (*.team.app.aibang / *.team2.app.aibang)
    │
    ▼
Nginx (7层入口)
    ├── 泛证书终止 TLS
    ├── Team 级通配符 server_name 匹配
    ├── API 级特例 location（超时/body size）
    ├── Host 改写: *.team.app.aibang → internal.team.mesh / *.team2.app.aibang → internal.team2.mesh
    └── proxy_pass → ASM LB (统一入口)
            │
            ▼
    Istio Gateway（监听 internal.*.mesh 内部域名）
            │
            ▼
    VirtualService（按 host 精确匹配路由到对应 Service）
```

---

## 解决方案

### 第一层：Nginx 配置

#### Team 级通配符块（默认策略）

```nginx
# *.team.app.aibang 默认 server 块
server {
    listen 443 ssl;
    server_name *.team.app.aibang;

    ssl_certificate     /etc/ssl/team/wildcard.team.app.aibang.crt;
    ssl_certificate_key /etc/ssl/team/wildcard.team.app.aibang.key;

    # 默认限制
    client_max_body_size 30M;
    proxy_read_timeout   60s;
    proxy_send_timeout   60s;

    # 改写 Host：把外部 team 域名统一改为内部标识
    # api1.team.app.aibang → api1.team.internal.mesh
    set $internal_host "";
    if ($host ~* "^(.+)\.team\.app\.aibang$") {
        set $internal_host "$1.team.internal.mesh";
    }

    location / {
        proxy_set_header Host $internal_host;
        proxy_set_header X-Original-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass https://asm-loadbalancer-ip;
    }
}
```

#### API 级特例（独立 server 块，优先级更高）

```nginx
# components.team.app.aibang 特例 server 块
server {
    listen 443 ssl;
    server_name components.team.app.aibang;

    ssl_certificate     /etc/ssl/team/wildcard.team.app.aibang.crt;
    ssl_certificate_key /etc/ssl/team/wildcard.team.app.aibang.key;

    # API 级特例限制
    client_max_body_size 50M;
    proxy_read_timeout   300s;
    proxy_send_timeout   300s;

    location / {
        proxy_set_header Host components.team.internal.mesh;
        proxy_set_header X-Original-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass https://asm-loadbalancer-ip;
    }
}
```

#### team2 的通配符块

```nginx
server {
    listen 443 ssl;
    server_name *.team2.app.aibang;

    ssl_certificate     /etc/ssl/team2/wildcard.team2.app.aibang.crt;
    ssl_certificate_key /etc/ssl/team2/wildcard.team2.app.aibang.key;

    client_max_body_size 30M;
    proxy_read_timeout   60s;

    set $internal_host "";
    if ($host ~* "^(.+)\.team2\.app\.aibang$") {
        set $internal_host "$1.team2.internal.mesh";
    }

    location / {
        proxy_set_header Host $internal_host;
        proxy_set_header X-Original-Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass https://asm-loadbalancer-ip;
    }
}
```

---

### 第二层：Istio Gateway 配置

内部只需维护 `.internal.mesh` 泛域名证书，Gateway 监听这些内部 host。

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: team-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: team-internal-mesh-cert   # 内部通配符证书
      hosts:
        - "*.team.internal.mesh"
    - port:
        number: 443
        name: https-team2
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: team2-internal-mesh-cert
      hosts:
        - "*.team2.internal.mesh"
```

---

### 第三层：VirtualService 配置（CICD 团队负责）

每个 API 对应一个 VirtualService，按内部 host 精确路由。

```yaml
# api1.team 的 VirtualService
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api1-team-vs
  namespace: team-ns
spec:
  hosts:
    - api1.team.internal.mesh
  gateways:
    - istio-system/team-gateway
  http:
    - route:
        - destination:
            host: api1-service.team-ns.svc.cluster.local
            port:
              number: 8080
```

```yaml
# components.team 的 VirtualService（无需特殊配置超时，已在 Nginx 处理）
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: components-team-vs
  namespace: team-ns
spec:
  hosts:
    - components.team.internal.mesh
  gateways:
    - istio-system/team-gateway
  http:
    - route:
        - destination:
            host: components-service.team-ns.svc.cluster.local
            port:
              number: 8080
```

---

## 流程图

```mermaid
graph TD
    A[外部客户端] -->|HTTPS api1.team.app.aibang| B[Nginx 入口]
    A -->|HTTPS components.team.app.aibang| C[Nginx 特例 server块]
    A -->|HTTPS api1.team2.app.aibang| D[Nginx team2 server块]

    B -->|Host改写 api1.team.internal.mesh\n默认 30M/60s| E[ASM LB]
    C -->|Host改写 components.team.internal.mesh\n特例 50M/300s| E
    D -->|Host改写 api1.team2.internal.mesh\n默认 30M/60s| E

    E --> F[Istio Gateway\n*.team.internal.mesh\n*.team2.internal.mesh]

    F -->|host匹配| G[VirtualService api1-team]
    F -->|host匹配| H[VirtualService components-team]
    F -->|host匹配| I[VirtualService api1-team2]

    G --> J[api1-service Pod]
    H --> K[components-service Pod]
    I --> L[api1-team2-service Pod]

    style C fill:#f9a,stroke:#c00
    style H fill:#f9a,stroke:#c00
```

---

## Onboarding 职责划分

```mermaid
graph LR
    subgraph Nginx团队[Nginx Onboarding 团队]
        N1[新 Team: 添加 server_name 通配符块]
        N2[特殊 API: 添加独立 server 块+超时/size]
    end

    subgraph CICD团队[CICD 团队]
        C1[新 API: 添加 VirtualService]
        C2[无需关心证书和超时]
    end

    subgraph 证书团队[证书维护]
        T1[外部: 每个Team一张泛证书]
        T2[内部: 每个Team一张*.internal.mesh泛证书]
    end
```

| 角色 | 职责 | 触发时机 |
|------|------|----------|
| Nginx/Onboarding | 新增 Team 通配符 server 块 | 新 Team 接入 |
| Nginx/Onboarding | 新增 API 级特例 server 块 | API 有特殊超时/size 需求 |
| CICD 团队 | 新增 VirtualService | 每个新 API 上线 |
| 证书团队 | 申请外部泛证书 | 新 Team 接入 |
| 证书团队 | 签发内部泛证书 | 新 Team 接入（内部 .mesh 域名） |

---

## 注意事项

1. **Nginx `if` 使用限制**：Nginx 中 `if` 有副作用，建议用 `map` 替代正则 `if` 做 host 映射：

```nginx
# nginx.conf http 块中定义
map $host $internal_host {
    ~^(?<sub>.+)\.team\.app\.aibang$   $sub.team.internal.mesh;
    ~^(?<sub>.+)\.team2\.app\.aibang$  $sub.team2.internal.mesh;
    default                             $host;
}
```

2. **ASM LB 的 TLS 处理**：Nginx `proxy_pass` 到 ASM LB 时，需确认是 TLS passthrough 还是 re-encrypt，建议配置 `proxy_ssl_verify off`（内网信任）或挂载内部 CA。

3. **X-Original-Host 透传**：后端服务若需要知道原始外部域名，通过 `X-Original-Host` header 获取，不依赖 `Host`。

4. **内部证书规模**：每新增一个 Team，增加一张外部泛证书 + 一张内部泛证书，总量 = `2 × Team数`，可控。

5. **特例 server 块优先级**：Nginx 精确域名 server 块优先级高于通配符，`components.team.app.aibang` 的精确块会自动覆盖 `*.team.app.aibang` 的通配符块，无需额外配置。





# Nginx 7层代理 - Team级别配置最佳实践分析

## 目标分析

```mermaid
graph TD
    A[Client HTTPS Request] --> B[Nginx 7层代理]
    B --> C{Team路由匹配}
    C -->|*.team1.app.aibang| D[Team1配置<br/>默认: 30M/60s]
    C -->|*.team2.app.aibang| E[Team2配置<br/>特殊: 50M/300s]
    C -->|*.teamN.app.aibang| F[TeamN配置]
    D --> G[Host重写为内部统一Host]
    E --> G
    F --> G
    G --> H[ASM LoadBalancer IP<br/>统一入口]
    H --> I[Istio Gateway 共享]
    I --> J[Team1 Namespace<br/>Gateway + VirtualService]
    I --> K[Team2 Namespace<br/>Gateway + VirtualService]
    I --> L[TeamN Namespace<br/>Gateway + VirtualService]
```

## 架构设计原则

| 维度 | 设计决策 |
|------|----------|
| 路由粒度 | Team级别（非API级别） |
| 证书管理 | 每Team独立泛域名证书 |
| 上游 | 单一ASM LB IP，靠Host头区分流量 |
| 配置覆盖 | 默认值 + Team级别覆盖 |
| Host重写 | Nginx统一重写为ASM内部Host |

---

## Nginx 配置结构规划

```
/etc/nginx/
├── nginx.conf                    # 主配置，全局默认值
├── conf.d/
│   ├── upstream.conf             # ASM上游定义
│   ├── default_params.conf       # 默认proxy参数片段
│   └── ssl_common.conf           # 公共SSL参数
└── sites-enabled/
    ├── team1.conf                # team1 默认配置
    └── team2.conf                # team2 特殊配置(50M/300s)
```

---

## 核心配置文件

### 1. `nginx.conf` - 全局默认

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # 日志格式
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'host=$host upstream=$upstream_addr '
                    'rt=$request_time uct=$upstream_connect_time '
                    'uht=$upstream_header_time urt=$upstream_response_time';

    access_log /var/log/nginx/access.log main;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout 65;

    # ========================================
    # 全局默认值 (Team级别可覆盖)
    # ========================================
    client_max_body_size     30m;       # 默认上传限制
    client_body_timeout      60s;
    proxy_connect_timeout    10s;
    proxy_send_timeout       60s;       # 默认超时
    proxy_read_timeout       60s;       # 默认超时

    # Gzip
    gzip on;
    gzip_types text/plain application/json application/xml;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*.conf;
}
```

### 2. `conf.d/upstream.conf` - ASM上游

```nginx
upstream asm_gateway {
    # ASM暴露的统一LB IP
    server 10.x.x.x:443;          # ASM LB IP

    keepalive 32;
    keepalive_requests 1000;
    keepalive_timeout 60s;
}
```

### 3. `conf.d/default_params.conf` - 可复用Proxy参数片段

```nginx
# 这个文件作为公共片段被各team include

# 注意：此文件不能独立使用，需在server/location块中include

# Proxy 基础头
proxy_http_version  1.1;
proxy_set_header    Connection        "";
proxy_set_header    X-Real-IP         $remote_addr;
proxy_set_header    X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header    X-Forwarded-Proto $scheme;

# 关键：重写Host为ASM内部统一入口Host
# ASM Istio Gateway通过Host头路由到对应Team的VirtualService
proxy_set_header    Host              $host;

# 透传原始请求信息给上游
proxy_set_header    X-Original-Host   $host;
proxy_set_header    X-Original-URI    $request_uri;
```

---

## Team配置文件

### 4. `sites-enabled/team1.conf` - 标准Team（默认配置）

```nginx
# ============================================================
# Team1: *.team1.app.aibang
# 配置级别: 默认 (30M / 60s)
# ============================================================

server {
    listen 443 ssl;
    http2  on;

    # 泛域名匹配
    server_name *.team1.app.aibang;

    # Team1 独立泛证书
    ssl_certificate     /etc/nginx/ssl/team1/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/team1/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL_team1:10m;
    ssl_session_timeout 10m;

    # Team级别日志
    access_log /var/log/nginx/team1_access.log main;
    error_log  /var/log/nginx/team1_error.log warn;

    # 使用全局默认值 (30M / 60s) 无需重复声明

    location / {
        proxy_pass https://asm_gateway;

        # 引入公共proxy头配置
        include /etc/nginx/conf.d/default_params.conf;

        # ★ 核心：Host重写为Team1对应的ASM内部路由Host
        # Istio VirtualService 通过此Host匹配路由规则
        proxy_set_header Host team1.internal.app.aibang;

        # 保留原始域名供上游业务识别
        proxy_set_header X-Original-Host $host;

        # 上游使用HTTPS，忽略内部自签证书校验（内网信任）
        proxy_ssl_verify  off;
        proxy_ssl_name    team1.internal.app.aibang;
    }
}

# HTTP -> HTTPS 重定向
server {
    listen 80;
    server_name *.team1.app.aibang;
    return 301 https://$host$request_uri;
}
```

### 5. `sites-enabled/team2.conf` - 特殊Team（上传50M/超时300s）

```nginx
# ============================================================
# Team2: *.team2.app.aibang
# 配置级别: 特殊覆盖 (50M / 300s)
# 场景: 需要大文件上传和长超时
# ============================================================

server {
    listen 443 ssl;
    http2  on;

    server_name *.team2.app.aibang;

    # Team2 独立泛证书
    ssl_certificate     /etc/nginx/ssl/team2/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/team2/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL_team2:10m;
    ssl_session_timeout 10m;

    access_log /var/log/nginx/team2_access.log main;
    error_log  /var/log/nginx/team2_error.log warn;

    # ★ Team级别覆盖全局默认值
    client_max_body_size  50m;     # 覆盖: 30m -> 50m
    client_body_timeout   300s;    # 覆盖: 60s -> 300s
    proxy_send_timeout    300s;    # 覆盖: 60s -> 300s
    proxy_read_timeout    300s;    # 覆盖: 60s -> 300s

    location / {
        proxy_pass https://asm_gateway;

        include /etc/nginx/conf.d/default_params.conf;

        # ★ 重写为Team2的ASM内部Host
        proxy_set_header Host team2.internal.app.aibang;
        proxy_set_header X-Original-Host $host;

        proxy_ssl_verify  off;
        proxy_ssl_name    team2.internal.app.aibang;

        # 大文件上传优化
        proxy_request_buffering off;    # 流式转发，不在nginx缓冲请求体
        proxy_buffering         off;    # 流式响应
    }
}

server {
    listen 80;
    server_name *.team2.app.aibang;
    return 301 https://$host$request_uri;
}
```

---

## Host重写流量路由全链路

```mermaid
sequenceDiagram
    participant C as Client
    participant N as Nginx
    participant A as ASM LB
    participant I as Istio Gateway
    participant VS as Team VirtualService
    participant S as Team Service

    C->>N: HTTPS请求<br/>Host: api.team2.app.aibang
    Note over N: 匹配 *.team2.app.aibang<br/>加载team2证书
    N->>A: proxy_pass to ASM LB<br/>Host: team2.internal.app.aibang<br/>X-Original-Host: api.team2.app.aibang
    A->>I: 转发到Istio Gateway
    Note over I: Gateway监听<br/>team2.internal.app.aibang
    I->>VS: 匹配Team2 VirtualService
    VS->>S: 路由到Team2 Service
    S-->>C: 响应返回
```

---

## ASM侧对应配置参考

```yaml
# Team2 Istio Gateway
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: team2-gateway
  namespace: team2
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      hosts:
        - "team2.internal.app.aibang"   # 对应Nginx重写的Host
      tls:
        mode: SIMPLE
        credentialName: team2-internal-cert
---
# Team2 VirtualService
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: team2-vs
  namespace: team2
spec:
  hosts:
    - "team2.internal.app.aibang"
  gateways:
    - team2/team2-gateway
  http:
    - match:
        - uri:
            prefix: "/"
      route:
        - destination:
            host: team2-service
            port:
              number: 8080
```

---

## 最佳实践总结

| 实践项 | 建议 | 原因 |
|--------|------|------|
| 配置分层 | 全局默认 + Team覆盖 | 减少重复，便于维护 |
| Host重写 | `proxy_set_header Host team.internal.*` | ASM靠Host路由，必须统一 |
| 保留原始Host | `X-Original-Host: $host` | 上游业务可能需要识别原始域名 |
| 大文件上传 | `proxy_request_buffering off` | 避免nginx内存/磁盘压力 |
| 证书隔离 | 每Team独立泛证书目录 | 证书轮换互不影响 |
| upstream keepalive | `keepalive 32` | 复用TCP连接，减少延迟 |
| 内部TLS | `proxy_ssl_verify off` + `proxy_ssl_name` | 内网信任但保持SNI正确 |
| 日志分离 | 每Team独立access/error log | 便于排障和审计 |

> **注意事项**
> - `client_max_body_size` 必须在 `server` 块声明才能覆盖全局，放在 `location` 块对已读取的请求头无效
> - `proxy_request_buffering off` 时，上游必须支持chunked transfer，否则可能出现兼容性问题
> - ASM侧的 Gateway `hosts` 必须与Nginx `proxy_set_header Host` 完全一致，否则流量无法匹配VirtualService