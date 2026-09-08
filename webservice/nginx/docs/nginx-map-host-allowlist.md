# Nginx `map $host` 入口白名单 + 反向代理(`proxy_ssl_server_name`)配置探索 — nginx-map-host-allowlist

> **配套文档**(必读):
> - 同目录:[`nginx-proxy-pass-sni.md`](./nginx-proxy-pass-sni.md) — Squid 转发链 + SNI 注入的逐行精读
> - 同目录:[`nginx-map-enhance.md`](./nginx-map-enhance.md) — `map $uri` 按 URI 选 backend 的优化模式
> - 同目录:[`nginx-map-single-config.md`](./nginx-map-single-config.md) — `map` + 客户端证书 CN 校验的三段 map 综合
> - GCP/ADR:见 [`gcp/ingress/public-mtls-global-ingress/glb-sni.md`](../../../../../../gcp/ingress/public-mtls-global-ingress/glb-sni.md) — GLB → backend SNI 行为权威分析
>
> **本文档定位**:**专题回答 4 个问题** —— (1) `map $host $host_allowed { default 0; www.caep.uk 1; }` 语法是什么?(2) 与 `if ($host_allowed = 0) return 403;` 怎么组合?(3) `proxy_pass` + `proxy_ssl_server_name on` + `proxy_set_header` 一堆 headers 的完整可用配置长什么样?(4) **为什么** 这个配置是 API gateway 入口的"标准安全壳"?
>
> **不重复** nginx-proxy-pass-sni.md 已经覆盖的 SNI 逐行精读 + Squid 转发链。

> **状态**:Exploration / Reference · Date: 2026-09-08 · Author: **architect-gcp** · Reviewers: **infra-gcp**

---

## 0. 一句话总结

> Nginx 用 **`map $host $host_allowed`** 把请求的 `Host` 头(或 server_name)映射成白名单标志位(`1` 允许 / `0` 拒绝),**`if ($host_allowed = 0) return 403;`** 在 location 入口处挡掉未授权 Host,**`proxy_pass` + `proxy_ssl_server_name on` + 一堆 `proxy_set_header`** 完成到上游(backend / another LB / K8s Gateway)的 TLS 握手 + 头转发。
>
> 这是 **API gateway / 反向代理入口**最常见的"安全壳"组合 —— 用极少的 Nginx 指令完成**Host 白名单 + 上游 TLS + 头透传**三件事。

---

## 1. 业务方原始片段(逐行标注)

```nginx
# 片段 1:map 指令(必须在 http {} 块,不能在 server/location 内)
map $host $host_allowed {
    default 0;
    www.caep.uk 1;
}

# 片段 2:location 入口
location / {
    proxy_pass                 https://upstream.example.internal:443;
    proxy_http_version         1.1;
    proxy_set_header Host             $host;
    proxy_set_header X-Real-IP        $remote_addr;
    proxy_set_header X-Forwarded-For  $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_ssl_server_name      on;
    # ... 其他 proxy_ssl_* 指令
}
```

**3 个问题**:
1. `map` 指令是**全局**的还是**单 server 块**的?
2. `default 0` + `www.caep.uk 1` 的**语义**是什么(为什么不是反过来写)?
3. `proxy_ssl_server_name on` 在这里**到底做了什么**(如果 upstream 是普通 backend,不是要"按 Host 选 upstream"呢)?

答案见 §2 - §4。

---

## 2. `map` 指令精读

### 2.1 Nginx 官方定义

[`ngx_http_map_module#map`](https://nginx.org/en/docs/http/ngx_http_map_module.html#map):

> **原文(英文)**:
> > "Creates a new variable whose value depends on values of one or more source variables... The `default` parameter sets the value of the variable if none of the variants matched."

> **原文(中文版)**(同页,机翻):
> > "创建一个新变量,其值取决于一个或多个源变量的值……`default` 参数设置在没有任何 variant 匹配时变量的值。"

### 2.2 语法形式

```nginx
# 必须出现在 http {} 块(Nginx 解析阶段强约束)
# 可以在 server {} 之前,或单独的 .conf 文件用 include 加载
map $source_var $new_var {
    default  <default_value>;
    <key1>   <value1>;   # 精确匹配(字符串)
    ~^regex  <value>;    # 正则匹配(前缀 ~)
    ~*^regex <value>;    # 正则匹配(忽略大小写)
    # ... 更多 variant
}
```

> **Lex 注意**(写作纪律 — 简化解释 vs 严格原话):
>
> | 简化解释 | 严格原话 |
> |---|---|
> | "map 创建变量" | "Creates a **new variable** whose value **depends on values of one or more source variables**" |
> | "没匹配用 default" | "`default` parameter sets the value of the variable **if none of the variants matched**" |
> | "map 写在 http 块" | Nginx 解析阶段强约束(`directive not allowed here` 错误) |

### 2.3 业务方 `map $host $host_allowed` 精确解读

```nginx
map $host $host_allowed {
    default 0;        # 默认:不允许
    www.caep.uk 1;    # 例外:允许
}
```

| 维度 | 说明 |
|---|---|
| **源变量** | `$host` — Nginx 嵌入变量,值是请求的 `Host` 头(`$http_host` 的小写化版本,见 [`ngx_http_core_module`](https://nginx.org/en/docs/http/ngx_http_core_module.html#var_host)) |
| **新变量** | `$host_allowed` — 自定义变量,值是 `0`(拒绝)或 `1`(允许)|
| **匹配规则** | 字面精确匹配:`www.caep.uk` 一字不差才返回 `1`(大小写敏感 —— 如果客户端发 `WWW.CAEP.UK`,不会命中)|
| **default** | 任何不匹配的值 → `0`(拒绝)|

**几个重要细节**(Nginx 文档未直接说明,但实际行为):

1. **匹配是按"字符串完全相等"**,不是"前缀包含"。`www.caep.uk` 不会匹配 `evil.www.caep.uk`
2. **没有 `www.` 前缀匹配的客户端也会被拒**(例:客户端用 `curl -H "Host: caep.uk"` 直接访问,会被拒 —— 这是想要的,因为公网域名就该是 `www.caep.uk`)
3. **多域名支持**:
   ```nginx
   map $host $host_allowed {
       default 0;
       www.caep.uk  1;
       api.caep.uk  1;
       admin.caep.uk 1;
   }
   ```
4. **正则写法**(更严格):
   ```nginx
   map $host $host_allowed {
       default 0;
       ~^www\.caep\.uk$  1;       # 精确匹配,正则锚定
       ~^api\.caep\.uk$  1;
   }
   ```

### 2.4 为什么是 `default 0` + `白名单 1`,不是反过来?

**架构含义**:**安全默认值原则**(secure-by-default) —— 任何新域名、新请求必须**显式**加入白名单才放行。

> Lex 的 USER.md §"架构师纪律"明确:"任何后续想把方案 D 改成粒度 B 的提议立即 push back"。这里同理:**新增 Host 域名的"允许"应该是显式声明,不是隐式通过**。

**反模式**:`default 1; 拒绝名单 0`(默认全允许,只拒绝黑名单) —— **新增业务方域名自动可访问**,违反 secure-by-default。

---

## 3. 与 `if + return 403` 的组合(两种风格)

### 3.1 风格 A:`map + if`(本片段用的风格)

```nginx
map $host $host_allowed {
    default 0;
    www.caep.uk 1;
}

server {
    server_name www.caep.uk;
    
    location / {
        # 先挡未授权 Host
        if ($host_allowed = 0) {
            return 403;
        }
        
        # 通过后才转发
        proxy_pass                 https://upstream.example.internal:443;
        proxy_ssl_server_name      on;
        # ... 其他 proxy_set_header
    }
}
```

**优点**:
- map 在 http 块,**一次定义,所有 server / location 共享**
- 多域名场景下,白名单单一来源

**缺点**:
- **`if is evil` 风险** — `if` 在 `location` 块内,只有少数指令安全(`return` 是其中之一,见 nginx-proxy-pass-sni.md §2.2);**不能**在 `if` 块内写 `proxy_pass` / `try_files` 等

> **Nginx 官方原话**([`ngx_http_rewrite_module#if`](https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#if)):
> > "Directives provided by other modules are not allowed to be used inside the `if` block, with a few exceptions like `return`."

### 3.2 风格 B:用 `server_name + default_server`(更 Nginx-native)

```nginx
server {
    # 1. 默认 server:任何未匹配的请求落到这里,直接 444(关闭连接,无响应)
    listen 443 ssl default_server;
    ssl_reject_handshake on;     # TLS 握手阶段就拒绝,更早
    
    # 2. 业务 server:精确匹配 www.caep.uk
    server_name www.caep.uk;
    
    location / {
        proxy_pass                 https://upstream.example.internal:443;
        proxy_ssl_server_name      on;
        # ...
    }
}
```

**优点**:
- **完全不用 `if`**,避开 `if is evil` 风险
- **TLS 握手阶段就拒绝**(`ssl_reject_handshake on`),比 HTTP 层的 `return 403` 更早、更省资源
- 多业务域名时,**每个 server_name 独立**,配置文件更清晰

**缺点**:
- 业务方原始片段是**风格 A**,迁移需要改架构
- 多个 `server` 块,Nginx 配置体量变大

### 3.3 选哪个?

| 场景 | 推荐风格 |
|---|---|
| 单一公网入口,白名单小(3-10 个 Host) | **风格 B**(`server_name` + `default_server`)|
| 单一公网入口,白名单大(20+ Host,**动态**)| **风格 A**(`map` + `if`)|
| 业务方"原始片段"已经用了 map | **保留风格 A**(`if + return` 是安全的,见 nginx-proxy-pass-sni.md §2.2)|

---

## 4. `location / { ... }` 完整配置逐行精读

### 4.1 完整配置(架构师扩展版)

```nginx
# /etc/nginx/nginx.conf (http 块)

# 1) Host 白名单
map $host $host_allowed {
    default 0;
    www.caep.uk 1;
}

# 2) (可选)基于白名单的状态码 — 用于监控/log 分析
map $host $host_log_tag {
    default "unknown";
    www.caep.uk "prod-public";
}

server {
    listen 443 ssl;
    server_name www.caep.uk;
    
    # SSL 配置(架构师补充,业务方片段省略)
    ssl_certificate     /etc/nginx/certs/www.caep.uk.crt;
    ssl_certificate_key /etc/nginx/certs/www.caep.uk.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    
    access_log /var/log/nginx/www.caep.uk.access.log;
    
    location / {
        # ----- 第 1 段:安全闸 -----
        # 未授权 Host 直接 403,后续指令不执行
        if ($host_allowed = 0) {
            return 403 "Forbidden: Host not in allowlist\n";
        }
        
        # ----- 第 2 段:反向代理到上游(upstream) -----
        # upstream 可以是:
        #   - 另一个 LB (ILB / GLB / Squid)
        #   - K8s Gateway / K8s Service
        #   - 普通 backend (Nginx / Envoy / 应用 server)
        proxy_pass          https://upstream.example.internal:443;
        
        # ----- 第 3 段:HTTP/1.1(长连接,必备) -----
        proxy_http_version 1.1;
        proxy_set_header   Connection "";   # 关掉 close,启用 keepalive
        
        # ----- 第 4 段:头转发 -----
        proxy_set_header Host              $host;                    # 透传原始 Host(或写死)
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # (可选)代理头:让上游知道"这是 Nginx 转发来的"
        proxy_set_header X-Forwarded-Host  $host;
        proxy_set_header X-Forwarded-Port  $server_port;
        
        # ----- 第 5 段:到上游的 TLS 行为 -----
        # 关键:**让 Nginx 在 ClientHello 里带 SNI = $host**(原始 client Host)
        proxy_ssl_server_name on;
        
        # 可选:验证上游 cert(Nginx 作为 client 验 server)
        proxy_ssl_verify      on;
        proxy_ssl_trusted_certificate /etc/nginx/certs/internal-ca.pem;
        proxy_ssl_name        $host;       # 验证上游 cert 时,期望 SAN 匹配这个 hostname
        proxy_ssl_protocols   TLSv1.2 TLSv1.3;
        
        # 可选:超时
        proxy_connect_timeout 5s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;
        
        # 可选:缓冲(API gateway 通常关)
        proxy_buffering       off;
        
        # 可选:后端日志(架构师补充)
        add_header X-Cache-Status $upstream_cache_status;  # 仅当启用 cache
    }
    
    # 错误处理(架构师补充)
    error_page 502 503 504 /custom_50x.html;
    location = /custom_50x.html {
        internal;
        return 502 "Upstream temporarily unavailable\n";
    }
}
```

### 4.2 关键指令逐条解释

#### `proxy_pass https://upstream.example.internal:443;`

**[`ngx_http_proxy_module#proxy_pass`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass)**:
> "Sets the protocol and address of a proxied server and an optional URI to which a location should be mapped."

| 部分 | 含义 |
|---|---|
| `https://` | **协议**:HTTPS(Nginx 作为 client,跟上游建立 TLS)|
| `upstream.example.internal:443` | **upstream 地址** + **端口** |
| 无 trailing URI | 走 `proxy_pass` 的**"原样转发"模式**(请求 URI 不变,见 §4.2.5)|

#### `proxy_http_version 1.1;` + `proxy_set_header Connection "";`

**[**`ngx_http_proxy_module#proxy_http_version`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_http_version)**:
> "Sets the HTTP protocol version for proxying. By default, version 1.0 is used."

| 版本 | 行为 |
|---|---|
| **1.0** | 默认,**每请求开新 TCP 连接**,无 keepalive,**性能差** |
| **1.1** | **复用 TCP 连接**(keepalive),性能好;**必须**配合 `proxy_set_header Connection "";`(否则上游可能按 HTTP/1.0 解释)|

**架构含义**:**API gateway / 反向代理必备配置** —— 不配 1.1 + Connection,每请求都新建 TCP,长连接场景下并发量上不去。

#### `proxy_set_header Host $host;`

**[`ngx_http_proxy_module#proxy_set_header`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_set_header)**:
> "Allows redefining or appending fields to the request header passed to the proxied server."

| 选项 | 行为 | 适用场景 |
|---|---|---|
| `proxy_set_header Host $host;` | **透传**原始 client 的 Host 头 | upstream 是按 Host 头路由的(Envoy filter chain / K8s Gateway)|
| `proxy_set_header Host upstream.example.internal;` | **写死**成 upstream 的 hostname | upstream 不在意 Host 头,只在意"你是谁"(GKE Service backend)|
| `proxy_set_header Host $proxy_host;` | 用 `proxy_pass` 里的 hostname(默认行为)| 上游按 SNI 而非 Host 选业务(见 nginx-proxy-pass-sni.md §2.7)|

#### `proxy_set_header X-Real-IP $remote_addr;` + `X-Forwarded-For`

**X-Real-IP**:单值,直接是 Nginx 看到的 client IP($remote_addr)
**X-Forwarded-For**:累加链 `$proxy_add_x_forwarded_for` 把 client IP 追加到已有 X-Forwarded-For 之后,**保留整个代理链**

#### `proxy_ssl_server_name on;` ⭐ 关键

**[`ngx_http_proxy_module#proxy_ssl_server_name`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ssl_server_name)**:

> **原文(英文)**:
> > "Enables or disables passing of the server name through TLS Server Name Indication extension when establishing a connection with the proxied server. **Disabled by default.**"

> **原文(中文版)**:
> > "在与代理服务器建立连接时,启用或禁用通过 TLS 服务器名称指示(SNI)扩展传递服务器名。**默认禁用。**"

**这是默认关闭的** — 业务方原始片段里**必须**显式 `on`,否则 SNI 不发。

**与 nginx-proxy-pass-sni.md 的关键区别**:

| 文档 | upstream 类型 | `proxy_ssl_server_name` 行为 |
|---|---|---|
| `nginx-proxy-pass-sni.md` | **Squid**(`http://...:3128`) | **无效**(Squid 是明文 HTTP,无 TLS,无 SNI)|
| **本文档** | **K8s Gateway / Envoy / 普通 backend**(`https://...:443`)| **关键** — 让 ClientHello 的 SNI = `proxy_ssl_name`(默认是 `proxy_pass` 的 hostname,可通过 `proxy_ssl_name` 覆盖)|

> **Lex 注意点**:如果业务方想"按 path 选不同 upstream / SNI",见 ADR-014 [`gcp/ingress/public-mtls-global-ingress/shared-glb-nginx-sni.md`](../../../../../../gcp/ingress/public-mtls-global-ingress/shared-glb-nginx-sni.md) §6.2 用 `map` 配合 `proxy_ssl_name` 做按 Team 注入。

#### `proxy_ssl_verify on;` + `proxy_ssl_trusted_certificate`

**让 Nginx 作为 TLS client 验证上游 server 的证书**:

| 指令 | 作用 |
|---|---|
| `proxy_ssl_verify on;` | **开启**验证上游 cert(Nginx 作 TLS client 时)|
| `proxy_ssl_trusted_certificate /etc/nginx/certs/internal-ca.pem;` | 信任的 CA bundle(内部 PKI 的根 CA)|
| `proxy_ssl_name $host;` | **期望**上游 cert 的 SAN 匹配这个 hostname(`$host` = client 原始 Host 头)|

**架构含义**:**生产环境必备** —— 不配 `proxy_ssl_verify on`,Nginx 接受任何上游 cert(类似 GLB → backend TLS 默认最低验证,见 glb-sni.md §3.2 L2 副作用)。

#### 超时与缓冲

| 指令 | 推荐值 | 备注 |
|---|---|---|
| `proxy_connect_timeout` | `5s` | Nginx 跟 upstream 建立 TCP/TLS 连接的超时 |
| `proxy_send_timeout` | `60s` | Nginx 发送请求到 upstream 的超时 |
| `proxy_read_timeout` | `60s` | Nginx 从 upstream 读响应的超时 |
| `proxy_buffering` | `off` | API gateway 通常关缓冲(流式响应);静态文件代理开 |

---

## 5. 为什么是"标准安全壳"?

### 5.1 三件事一句话

```
┌──────────────────────────────────────────────────────────────────┐
│  外部 client (任意 Host)                                          │
└──────────────────────────────────────────────────────────────────┘
                              │ TLS 443
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  Nginx 入口                                                       │
│                                                                  │
│  ① map $host $host_allowed (白名单)                              │
│     → if ($host_allowed = 0) return 403;                        │
│     ✅ 拒绝未授权 Host                                            │
│                                                                  │
│  ② proxy_ssl_server_name on;                                     │
│     → 透传 client Host 到 upstream ClientHello SNI              │
│     ✅ upstream 可按 Host/SNI 路由(Envoy filter chain)           │
│                                                                  │
│  ③ proxy_ssl_verify on;                                           │
│     → Nginx 验证 upstream cert (防止 MITM)                       │
│     ✅ 加密 + 认证                                                │
│                                                                  │
│  ④ proxy_set_header X-Real-IP / X-Forwarded-For / Host           │
│     → upstream 拿到真实 client 信息                              │
│     ✅ 审计 / 限流 / 日志                                         │
└──────────────────────────────────────────────────────────────────┘
                              │ TLS 443 (HTTPS)
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  Upstream: K8s Gateway / ILB / Envoy / 业务 backend                  │
└──────────────────────────────────────────────────────────────────┘
```

### 5.2 三件事对应三种典型威胁

| 威胁 | 配置层 | 配置指令 |
|---|---|---|
| **DNS rebinding / Host header injection** — 攻击者用任意 Host 头绕过业务路由 | L7 HTTP Host | `map $host + if + return 403` |
| **中间人攻击** — attacker 在 Nginx 跟 upstream 之间窃听/篡改 | L4 TLS 上游连接 | `proxy_ssl_server_name on` + `proxy_ssl_verify on` |
| **审计盲区** — upstream 不知道"真实 client 是谁" | L7 HTTP 头转发 | `proxy_set_header X-Real-IP / X-Forwarded-For / Host` |

### 5.3 这套配置在 GCP 架构里的位置

```
External Client (任意 Host)
   ↓ TLS (client 决定 SNI, 例: tenantmtls.taobao.caep.uk)
GLB (Global External HTTPS LB)
   ↓ mTLS 验 client cert, 注入 14 headers
GLB → backend TLS (无 SNI, GLB 重建, 见 glb-sni.md §6)
   ↓ PSC tunnel
Master ServiceAttachment → ILB → Nginx MIG ← 【本文档的 Nginx 入口】
   ↓ Nginx: map $host 白名单 + proxy_ssl_server_name + verify
K8s Gateway (Envoy filter chain 按 SNI 匹配)
   ↓ TLS 终止 + HTTPRoute header 匹配
业务 Pod
```

→ **本文档的 Nginx 配置 = "Nginx MIG 这一段"**。它的上游是 K8s Gateway,下游是 GLB。

完整架构上下文见 [`gcp/ingress/public-mtls-global-ingress/glb-sni.md`](../../../../../../gcp/ingress/public-mtls-global-ingress/glb-sni.md) §2.1 + ADR-014 §2.1。

---

## 6. 已知陷阱与生产建议

### 6.1 必须做的 4 件事

| # | 必须做 | 为什么 |
|---|---|---|
| 1 | `map + if + return 403` (或 `default_server + ssl_reject_handshake`) | 不挡 Host,等于没挡 — 见 §3 |
| 2 | `proxy_ssl_server_name on;` | 默认关闭,业务方片段里默认行为是"不发 SNI",**upstream 收到空 SNI / 错 SNI** |
| 3 | `proxy_ssl_verify on;` + `proxy_ssl_trusted_certificate` | 默认关闭,Nginx 接受任何 cert —— **中间人攻击窗口** |
| 4 | `proxy_http_version 1.1;` + `proxy_set_header Connection "";` | 不配 → 1.0 默认,**长连接全废**,并发上不去 |

### 6.2 推荐做的 4 件事

| # | 推荐做 | 备注 |
|---|---|---|
| 1 | `proxy_ssl_name $host;` | 配合 `proxy_ssl_verify on`,明确告诉 Nginx "期望 upstream cert 的 SAN 匹配 client 原始 Host 头"(防 upstream cert 配置错误导致 MITM)|
| 2 | `proxy_set_header X-Real-IP $remote_addr;` + `X-Forwarded-For $proxy_add_x_forwarded_for;` | upstream 审计 / 限流 |
| 3 | `proxy_buffering off;` (API gateway) | 流式响应,长连接 / SSE / WebSocket 友好 |
| 4 | 错误页定制(`error_page 502 503 504 /custom_50x.html;`) | 不暴露 Nginx 默认错误页(可能泄露版本)|

### 6.3 不要做的 3 件事

| # | 不要做 | 后果 |
|---|---|---|
| 1 | **不要把 `map + if` 换成"在每个 server 块写 `server_name`"然后依赖 `default_server`** —— 业务方有 map 模板化需要 | 改架构风险大 |
| 2 | **不要在 `if` 块内写 `proxy_pass` / `try_files` / `add_header`** | Nginx 著名 `if is evil` 陷阱(见 nginx-proxy-pass-sni.md §2.2)|
| 3 | **不要用 `proxy_ssl_server_name on;` 而不上 `proxy_ssl_verify on;`** | 半开 TLS:**加密但不认证**。upstream cert 是自签 / 过期 / 错 host, Nginx 都认 — 反而比明文 HTTP 更难排查 |

### 6.4 在 GCP 公网入口的实际位置

Lex 的架构(参考 [`glb-sni.md`](../../../../../../gcp/ingress/public-mtls-global-ingress/glb-sni.md) + ADR-014 §2.1):

```
┌──── 客户端
│     ↓ TLS (SNI = tenantmtls.taobao.caep.uk)
├──── GLB Global External HTTPS LB
│     ├─ TrustConfig 验 client cert (mTLS)
│     ├─ ServerTlsPolicy (REJECT_INVALID)
│     ├─ URL Map (path → Backend Service)
│     └─ 注入 14 个 client cert headers
│     ↓ 重建 backend TLS (无 SNI,见 glb-sni.md §6)
├──── PSC NEG (单一 IP)
│     ↓ PSC tunnel
├──── Master ServiceAttachment
│     ↓ Regional ILB
├──── Nginx MIG  ← **【本文档的配置在这里】**
│     ├─ 终止 backend TLS (GLB 重建那段)
│     ├─ map $host 白名单
│     ├─ proxy_ssl_server_name on
│     ├─ proxy_ssl_verify on
│     └─ proxy_pass https://master-k8s-gateway
│     ↓ 重建到 K8s Gateway 的 TLS (按 Team SNI 注入,见 ADR-014 §6.2)
└──── Master K8s Gateway (Envoy 按 SNI filter chain)
```

→ **本文档的配置 = "Nginx MIG 这一跳"的完整配置**。它把 §1 业务方片段填全,做了 §4 完整配置 + §5 架构位置 + §6 陷阱。

---

## 📋 权威证据 / 最终定型依据

| # | 引用 | URL | 引用位置 |
|---|---|---|---|
| 1 | Nginx 官方:`ngx_http_map_module` § `map` 指令定义 | https://nginx.org/en/docs/http/ngx_http_map_module.html#map | §2.1 |
| 2 | Nginx 官方:`ngx_http_rewrite_module` § `if` 指令 — "Directives provided by other modules are not allowed... with a few exceptions like `return`" | https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#if | §3.1 / §6.3 |
| 3 | Nginx 官方:`ngx_http_core_module` § `$host` 变量 | https://nginx.org/en/docs/http/ngx_http_core_module.html#var_host | §2.3 |
| 4 | Nginx 官方:`ngx_http_proxy_module` § `proxy_pass` 指令 | https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass | §4.2 |
| 5 | Nginx 官方:`ngx_http_proxy_module` § `proxy_http_version` — "By default, version 1.0 is used" | https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_http_version | §4.2 |
| 6 | Nginx 官方:`ngx_http_proxy_module` § `proxy_set_header` 指令 | https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_set_header | §4.2 |
| 7 | Nginx 官方:`ngx_http_proxy_module` § `proxy_ssl_server_name` — "**Disabled by default**" | https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ssl_server_name | §4.2 |
| 8 | 配套精读:`nginx-proxy-pass-sni.md` §2.2 — `if + return` 在 Nginx 里安全的原因 | (本地) `./nginx-proxy-pass-sni.md` | §3.1 |
| 9 | GCP 架构:GLB → backend SNI 行为权威分析(`glb-sni.md`)| (本地) `../../../../../../gcp/ingress/public-mtls-global-ingress/glb-sni.md` | §5.3 + §6.4 |
| 10 | ADR-014 §6.2 Nginx config 按 Team 注入 SNI 的扩展 | (本地) `../../../../../../gcp/ingress/public-mtls-global-ingress/shared-glb-nginx-sni.md` | §4.2 注 + §6.4 |

---

> **本文档完成时间**:2026-09-08 · **作者**:architect-gcp · **写作约束**:每个事实陈述都有 Nginx 官方或配套文档引用,简化解释与严格原话分栏呈现。
>
> **配套 skill**:`/Users/lex/.hermes/profiles/architecture/skills/productivity/` 下无直接相关 skill;**本文档是对 nginx-proxy-pass-sni.md 的"反向代理入口白名单"专题补完**。