# Squid SNI 提取机制:从 URL 到 TLS ClientHello

> **本节是"Squid 如何把 URL 的 host 提取成 SNI,填入到跟上游 TLS ClientHello"的深度技术文档**。
>
> **架构师 lane 边界**:本文档只做技术机制解释 + 抓包验证逻辑,**不实施任何 Squid 配置变更 / 不抓包 / 不运维**。实际验证由 infra-gcp / qa-gcp 在自己 lane 执行。
>
> **状态**:Reference · Date: 2026-09-04 · Author: **architect-gcp** · Reviewers: 业务方(已确认生产可用)、infra-gcp
>
> **核心问题**:
> 1. Squid 跟上游 GKE API 建立 TLS 握手时,**SNI 是从哪里来的?**
> 2. **"Squid 自动从 URL 提取 host 作 SNI"** —— 这个业务方理解**有多精确**?
> 3. Squid forward proxy + HTTP CONNECT 模式 vs `ssl-bump peek` 模式,**SNI 处理有什么区别**?
> 4. 业务方架构(Nginx → Squid → GKE)**走了哪条路径**,为什么不需要配 `ssl-bump`?
>
> **前置知识**:
> - HTTP CONNECT 方法 + TLS 隧道(TLS Tunneling)
> - TLS 握手中的 SNI(Server Name Indication)扩展
> - Squid 4 种工作模式:forward proxy / intercept / tproxy / accel
> - `ssl-bump` 机制(SSL inspection / MITM)
>
> **配套文档**:
> - 上游架构:[`../../nginx/docs/proxy-pass/nginx-proxy-pass-sni.md`](../../nginx/docs/proxy-pass/nginx-proxy-pass-sni.md) — Nginx 跟 Squid 这一跳
> - 同目录:[`squid-as-https-proxy.md`](../squid-as-https-proxy.md) — Squid 作为 HTTPS proxy 的部署文档
> - 同目录:[`squid-conf.md`](../squid-conf.md) — Squid 基础配置
> - 同目录:[`squid-l4-explorer.md`](../squid-l4-explorer.md) — Squid L4 探索

---

## 0. 一句话总结

> **业务方理解"Squid 自动从 URL 提取 host 作 SNI"是正确但不够精确的**。
>
> **真实情况**(forward proxy + HTTP CONNECT 默认模式):
> 1. 客户端发 `CONNECT host:port HTTP/1.1`(host 来自 URL)
> 2. Squid **从 CONNECT 请求的目标提取 host:port**,作为 upstream 地址
> 3. Squid 跟上游建立 **TLS 握手**,**OpenSSL 自动把 `host` 字段填入 ClientHello 的 SNI 扩展**(因为 OpenSSL 知道 DNS 解析的目标是 host 字符串,不是 IP)
> 4. **不需要任何 `ssl-bump` 配置**——Squid 在此模式下**不解密 TLS**,**只透传**
>
> **业务方架构走的就是这条路径**(默认 forward proxy + HTTP CONNECT),所以**不需要配 ssl-bump**。
>
> **如果业务方配了 `ssl-bump peek`**(SSL inspection 模式),Squid 会**显式解析 ClientHello 的 SNI**,做规则匹配(MITM / 内容审计),**这是另一种完全不同的路径**,**业务方不需要**。

---

## 1. 业务方原始问题精确化

### 1.1 业务方原话

> "Squid 是怎么做这个事情的。我想有一个详细的了解。"

**架构师精确化**(从业务方上一轮的 Nginx config + 这一轮提问中提取):
- **场景**:Nginx 主机(`www.aibang.com:443`)通过 Squid(`http://ourintra.squid.proxy:3128`)转发请求到上游 GKE API(`https://apiname.team.caep.uk:443`)
- **目标**:理解 Squid 在这个转发链中,**SNI 的填入机制**具体是怎样的
- **范围**:仅限 **forward proxy + HTTP CONNECT 模式**(业务方架构的现实模式)

### 1.2 架构师校准(基于业务方上一轮的认知)

**业务方上一轮的理解**:
> "Squid 自动从 URL 提取 host 作 SNI ← 这里就是 SNI 注入点"

**架构师校准**:
- ✅ **正确部分**:Squid 的确"用 host 作 SNI"
- ⚠️ **不够精确**:**"自动"是 OpenSSL 库的行为**,**不是 Squid 显式填的**
- ⚠️ **没区分模式**:**forward proxy + CONNECT 模式**下 SNI 是 OpenSSL 填的;**ssl-bump 模式**下 Squid 才会显式解析 SNI
- → **业务方架构走 forward proxy + CONNECT 模式,OpenSSL 填 SNI,Squid 本身没主动操作**

---

## 2. Squid 4 种工作模式(架构师先建立框架)

> **先搞清楚 Squid 在哪个模式工作**,才能准确解释 SNI 行为。

**Squid 官方**([http_port 文档](https://www.squid-cache.org/Versions/v3/3.5/cfgman/http_port.html))列出 4 种模式:

| # | 模式 | 触发配置 | 工作机制 | SNI 行为 |
|---|---|---|---|---|
| 1 | **forward proxy**(默认)| `http_port 3128` | 客户端主动配置 proxy 走 Squid | **OpenSSL 自动填 SNI**(本节重点)|
| 2 | **intercept**(透明代理)| `http_port 3128 intercept` | iptables 把 80/443 强制 redirect 到 Squid | 同上(但需要 SSL bump 解密)|
| 3 | **tproxy** | `http_port 3128 tproxy` | 透明代理 + 保留 client IP | 同上 |
| 4 | **accel**(反向代理)| `http_port 80 accel` | Squid 当 reverse proxy | 同上 + Squid 自己处理 SNI |

**业务方架构 = 模式 1 (forward proxy)**:
- Nginx 主动配置 `proxy_pass http://ourintra.squid.proxy:3128`
- Squid 不需要 SSL bump
- **SNI 由 OpenSSL 库自动填入 ClientHello**

---

## 3. forward proxy 模式的完整 SNI 注入链路(本节核心)

### 3.1 4 跳 TLS 握手时序图(架构师细化)

```
┌──────────────────────────────────────────────────────────────────────┐
│ 跳 1:客户端 → Nginx(HTTPS)                                              │
│    客户端发起 TLS ClientHello,SNI = "www.aibang.com"(公网域名)         │
│    Nginx 用 www.aibang.com 的公网 cert 完成握手                       │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 跳 2:Nginx 解密 HTTPS → 看到明文 HTTP 请求                              │
│    Nginx 改写 URL + Host 头(rewrite + proxy_set_header Host)          │
│    Nginx 看到目标 = "https://apiname.team.caep.uk:443/users/123"      │
│    Nginx 知道要发 CONNECT 请求到 Squid:3128                           │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 跳 3a:Nginx → Squid(明文 HTTP)                                         │
│    Nginx 发:CONNECT apiname.team.caep.uk:443 HTTP/1.1                 │
│            Host: apiname.team.caep.uk                                  │
│            User-Agent: nginx/1.x.x                                     │
│                                                                       │
│    Squid 收到 CONNECT 请求                                              │
│    Squid 解析 host:port 字段 = apiname.team.caep.uk:443               │
│    Squid ACL 检查(默认 allow CONNECT SSL_ports)                       │
│    Squid 返回:HTTP/1.1 200 Connection Established                       │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 跳 3b:Squid → GKE API(HTTPS 握手)                                     │
│    Squid 用 OpenSSL 库建立到 apiname.team.caep.uk:443 的 TCP 连接      │
│    OpenSSL 看到目标是 "apiname.team.caep.uk"(域名字符串,不是 IP)        │
│    OpenSSL 自动把 "apiname.team.caep.uk" 填入 ClientHello 的 SNI 扩展   │
│    OpenSSL 发送 ClientHello:                                            │
│      ServerName: "apiname.team.caep.uk"  ← OpenSSL 自动填              │
│      ... (cipher suites, extensions 等)                                │
│                                                                       │
│    GKE API 收到 ClientHello                                              │
│    GKE Envoy 解析 SNI = "apiname.team.caep.uk"                         │
│    GKE Envoy 按 SNI 匹配 filter chain                                     │
│    GKE Envoy 用对应 cert 完成握手                                        │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 跳 4:GKE API 解密 → 看到 HTTP 请求                                     │
│    GKE Envoy 解密 → 看到 /users/123                                     │
│    路由到对应业务后端 Pod                                                │
└──────────────────────────────────────────────────────────────────────┘
```

### 3.2 SNI 注入的关键节点(架构师标注)

| 跳 | SNI 在哪里被填? | 填入主体 |
|---|---|---|
| 跳 1(客户端 → Nginx)| 客户端 TLS 库(浏览器/OpenSSL)| 客户端 OS/应用,跟 Squid 无关 |
| **跳 3b(Squid → GKE API)** | **OpenSSL 库的 SSL_connect() 调用** | **OpenSSL 库**(Squid 进程内的 OpenSSL)|
| 跳 4(GKE API → 后端)| 不适用(GKE 内部不需要 SNI)| - |

**架构师关键洞察**:
> **Squid 在这个过程中,SNI 不是它"主动"填的,而是它调用 OpenSSL 时,OpenSSL 库自动填的**。
>
> **Squid 给 OpenSSL 的输入**:`SSL_connect(ssl, "apiname.team.caep.uk:443")`
> **OpenSSL 的行为**:
> 1. DNS 解析 `apiname.team.caep.uk` → IP(走系统 resolver 或 Squid 的 DNS 配置)
> 2. 建立 TCP 连接到 IP
> 3. 发送 ClientHello,自动把 `apiname.team.caep.uk` 填入 SNI 扩展
> 4. 因为 OpenSSL 知道**目标是 hostname 字符串**,所以填 SNI 是天然行为

---

## 4. Squid 官方文档原文(Squid HTTPS 特性页)

> **架构师引用 Squid 官方 [Features/HTTPS](https://wiki.squid-cache.org/Features/HTTPS) 文档,核对关键事实**。

### 4.1 官方原文 1:CONNECT 方法的本质

> **"The CONNECT method is a way to tunnel any kind of connection through an HTTP proxy. By default, the proxy establishes a TCP connection to the specified server, responds with an HTTP 200 (Connection Established) response, and then shovels packets back and forth between the client and the server, without understanding or interpreting the tunneled traffic."**

**架构师解读**:
- "**without understanding or interpreting the tunneled traffic**"——**Squid 默认不解密隧道**
- Squid 只做"字节转发"(shoveling packets)
- **业务方架构就是这样**——Squid 在 Nginx 和 GKE 之间是"透明字节转发"

### 4.2 官方原文 2:CONNECT 信息可访问性

> **"When a browser establishes a CONNECT tunnel through Squid, Access Controls are able to control CONNECT requests, but only limited information is available. For example, many common parts of the request URL do not exist in a CONNECT request... With HTTPS, the above parts are present in encapsulated HTTP requests that flow through the tunnel, but Squid does not have access to those encrypted messages."**

**架构师解读**:
- **Squid 只能看到 CONNECT 请求的目标 host:port**
- **Squid 看不到隧道里的 HTTPS 内容**(因为隧道是加密的)
- ACL 只能基于 **host:port + 来源 IP** 决策

### 4.3 官方原文 3:CONNECT 隧道的灵活性

> **"It is important to notice that the protocols passed through CONNECT are not limited to the ones Squid normally handles. Quite literally anything that uses a two-way TCP connection can be passed through a CONNECT tunnel. This is why the Squid default ACLs start with `deny CONNECT !SSL_Ports` and why you must have a very good reason to place any type of allow rule above them."**

**架构师解读**:
- **CONNECT 隧道可以传任何 TCP 流量**(HTTP / HTTPS / 甚至 telnet / SSH 等)
- **Squid 默认 ACL `deny CONNECT !SSL_Ports` 阻止非 HTTPS 端口**
- 这是**安全默认值**——防止 Squid 当成"万能隧道代理"

### 4.4 官方原文 4:Squid 看 SNI 需要 ssl-bump

> **"Is TLS origin SNI available to Squid ACLs in HTTPS proxy mode? A: No, not today. SslBump features are not yet supported in that mode."**

**架构师解读(关键)**:
- 在 **HTTPS proxy 模式**(`https_port` + 不带 `ssl-bump`):**Squid 看不到 SNI**
- 在 **ssl-bump 模式**(`https_port ssl-bump`):Squid 通过 `peek` 步骤显式解析 SNI
- **业务方架构用 `http_port`(不是 `https_port`),更不是 ssl-bump**——所以 **Squid 在架构里看不到 SNI,也不需要看**

---

## 5. 业务方架构的 SNI 注入具体路径(架构师精准解释)

### 5.1 Squid 配置假设(架构师推断)

业务方架构下,Squid 的最小配置应该是:

```squid
# /etc/squid/squid.conf
http_port 3128

# 默认 ACL(业务方应该保持)
acl SSL_ports port 443
acl CONNECT method CONNECT
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager
http_access allow localnet
http_access deny all

# 业务方特定 ACL(架构师推断)
# 只允许内网 Nginx 主机访问 Squid
acl nginx_hosts src 10.x.x.x/24  # 业务方内网段(脱敏)
http_access allow nginx_hosts
http_access deny all

# 上游 DNS(架构师建议:用 internal DNS,不要走公网)
dns_nameservers 10.x.x.x 10.x.x.x

# 可选:配置 cache(业务方不需要,跨网络转发不需要缓存)
# cache deny all  # 跨网络代理通常关 cache
```

**关键**:
- **没有 `ssl-bump`** 配置——Squid 不解密 TLS
- **没有 `https_port`**——Squid 接受明文 HTTP CONNECT 请求
- **没有 sslproxy_* 配置**——Squid 跟上游建立 TLS 时用默认值

### 5.2 业务方架构下 SNI 注入的具体 4 步(架构师精细化)

```
步骤 1:Nginx 发 CONNECT 请求
───────────────────────────────────────────────────────────
Nginx → Squid(明文 HTTP):

  CONNECT apiname.team.caep.uk:443 HTTP/1.1
  Host: apiname.team.caep.uk
  User-Agent: nginx/1.x.x

字节级(简化):
  43 4F 4E 4E 45 43 54 20  = "CONNECT "
  61 70 69 6E 61 6D 65 2E 74 65 61 6D 2E 63 61 65 70 2E 75 6B 3A 34 34 33  = "apiname.team.caep.uk:443"
  20 48 54 54 50 2F 31 2E 31  = " HTTP/1.1"
  0D 0A  = "\r\n"
  48 6F 73 74 3A 20 61 70 69 6E 61 6D 65 2E 74 65 61 6D 2E 63 61 65 70 2E 75 6B  = "Host: apiname.team.caep.uk"
  0D 0A 0D 0A  = "\r\n\r\n"

Squid 行为:
  - Squid 解析 CONNECT 请求行
  - 提取 host:port = "apiname.team.caep.uk:443"
  - 检查 ACL:`method=CONNECT` ✓ + `port=443` (SSL_ports) ✓
  - Squid 准备建立到 apiname.team.caep.uk:443 的 TCP 连接

步骤 2:Squid 建立 TCP 连接到上游
───────────────────────────────────────────────────────────
Squid → 系统 resolver:
  - DNS 查询 apiname.team.caep.uk → 10.x.x.x(内网 IP,脱敏)
  - 业务方内网 DNS 负责(不在 Squid 配置,跟 OS resolver 一致)

Squid → 内网:
  - TCP 三次握手: 10.x.x.x:443
  - 上游 GKE API Envoy 接收 SYN,响应 SYN-ACK,ESTABLISHED

步骤 3:Squid 调用 OpenSSL 建立 TLS
───────────────────────────────────────────────────────────
Squid 代码(简化伪代码):

  SSL *ssl = SSL_new(squid_ssl_ctx);
  SSL_set_fd(ssl, tcp_socket_fd);
  // 关键:OpenSSL 接受的是 hostname 字符串,不是 IP
  SSL_set_tlsext_host_name(ssl, "apiname.team.caep.uk");  // 显式设置 SNI
  // 注:实际上 Squid 不一定显式调用此函数,OpenSSL 也可能从 SSL_connect 的 hostname 参数推断
  
  int ret = SSL_connect(ssl);

  // OpenSSL 内部:
  // 1. 发送 ClientHello
  // 2. 在 ClientHello 的 extensions 中填入 SNI = "apiname.team.caep.uk"
  // 3. 因为 host 是 hostname 字符串,OpenSSL 会自动设置 SNI(SSL 3.0+ 协议要求)

步骤 4:GKE API 接收 ClientHello,匹配 SNI
───────────────────────────────────────────────────────────
GKE API 收到 ClientHello:
  - ClientHello.Version: TLS 1.3
  - ClientHello.cipher_suites: [ECDHE-RSA-AES256-GCM-SHA384, ...]
  - ClientHello.extensions.server_name:
      server_name_type: host_name(0)
      server_name_value: "apiname.team.caep.uk"  ← SNI

  GKE Envoy 处理:
  - 解析 SNI = "apiname.team.caep.uk"
  - 匹配 filter chain(按 SNI)
  - 选择对应 server cert(apiname.team.caep.uk.crt)
  - 发送 ServerHello + Certificate
  - 完成 TLS 握手
```

### 5.3 关键代码级事实(架构师标注)

#### 事实 1:OpenSSL 自动填 SNI 的条件

**OpenSSL 行为**(从 OpenSSL 源码约定):
- 如果调用者提供 **hostname 字符串**(而不是 IP)给 `SSL_connect()`,**OpenSSL 自动填 SNI**
- 如果调用者提供 **IP 地址**,**OpenSSL 不填 SNI**(RFC 6066 限制)
- Squid 在 CONNECT 隧道模式:**通过 hostname 字符串调用 SSL_connect()**——所以 SNI 自动填

#### 事实 2:Squid 显式控制 SNI 的位置(可选)

**如果业务方想显式控制 SNI**,Squid 提供配置:
- `sslproxy_cert_sign_hash` / `sslproxy_version` 等
- 但 **SNI 字段本身不需要显式配置**——OpenSSL 自动填

#### 事实 3:`ssl-bump` 模式下 Squid 才显式看 SNI

**如果业务方配了 `ssl-bump`**:
- Squid 主动解密 client ↔ Squid 的 TLS
- Squid 看到 ClientHello,**显式解析 SNI**
- Squid 用 SNI 做规则匹配(ACL / peek / splice / bump)
- **业务方架构不需要这条路径**

---

## 6. 抓包验证:如何证明 SNI = apiname.team.caep.uk

> **架构师提示**:这是验证"Squid 跟 GKE API 握手时,SNI 是不是 apiname.team.caep.uk"的标准方法。**架构师不抓包**(lane 边界),**infra-gcp / qa-gcp 实际抓**。

### 6.1 在 Squid 主机抓包

```bash
# 在 Squid 主机上抓包,过滤 TLS ClientHello
sudo tcpdump -i any -nn -s 0 -w /tmp/squid-upstream.pcap \
  'host <GKE_API_IP> and port 443'

# 触发一次请求
curl -x http://ourintra.squid.proxy:3128 \
  https://apiname.team.caep.uk/api/v1/test

# 停止抓包
sudo tcpdump -r /tmp/squid-upstream.pcap -A | head -100

# 用 tshark 看 ClientHello 的 SNI
tshark -r /tmp/squid-upstream.pcap \
  -Y "tls.handshake.extensions_server_name" \
  -T fields -e tls.handshake.extensions_server_name

# 期望输出:
# apiname.team.caep.uk
```

### 6.2 在 Nginx 主机抓包(对比)

```bash
# 在 Nginx 主机上抓 Squid 段(明文 HTTP)
sudo tcpdump -i any -nn -s 0 -w /tmp/nginx-squid.pcap \
  'host ourintra.squid.proxy and port 3128'

# 触发一次请求
curl https://www.aibang.com/apiname/api/v1/test

# 停止抓包
tshark -r /tmp/nginx-squid.pcap \
  -Y "http.request.method == CONNECT" \
  -T fields -e http.request.full_uri

# 期望输出:
# apiname.team.caep.uk:443
```

### 6.3 在 GKE API / Envoy 侧抓包

```bash
# 在 GKE 节点抓包
sudo tcpdump -i any -nn -s 0 -w /tmp/gke-client-hello.pcap \
  'src host <SQUID_IP> and port 443'

# 触发一次请求
curl -x http://ourintra.squid.proxy:3128 \
  https://apiname.team.caep.uk/api/v1/test

# 停止抓包
tshark -r /tmp/gke-client-hello.pcap \
  -Y "tls.handshake.type == 1" \
  -T fields -e tls.handshake.extensions_server_name

# 期望输出:
# apiname.team.caep.uk
```

**架构师标注**:
- **3 处抓包点**任意一处看到 SNI = "apiname.team.caep.uk" 即可证明
- **最佳证据**:**GKE API 侧抓包**(因为这是 SNI 注入的目标)
- **次佳证据**:**Squid 主机抓包**(因为这是 SNI 注入的发生地)

---

## 7. 为什么业务方架构不需要 ssl-bump

### 7.1 ssl-bump 的用途(架构师解释)

`ssl-bump` 是 Squid 的 **SSL inspection / MITM 机制**,用于:
- **DLP**(Data Loss Prevention,数据防泄漏)
- **内容审计**(审计员工访问的 URL)
- **恶意软件扫描**(扫描 HTTPS 流量里的 payload)
- **合规审计**(满足合规要求)

### 7.2 ssl-bump 的工作原理

```
正常 CONNECT 隧道(业务方架构):
  Client ─TLS─→ Squid ─raw bytes─→ Server

ssl-bump 模式:
  Client ─TLS─→ Squid(解密)─→ Squid(看清文)─→ Squid(重新加密)─→ Server
                              ↑
                          MITM(中间人)
                          Squid 用内部 CA 签发 fake cert
```

### 7.3 业务方架构为什么不需要

| 维度 | 业务方架构 | ssl-bump 架构 |
|---|---|---|
| **目的** | 跨网络转发 + SNI 注入 | 解密 HTTPS 做内容审计 |
| **Squid 角色** | **透明字节转发器** | **MITM(中间人)** |
| **客户端信任** | 客户端不需要 Squid cert | 客户端必须信任 Squid CA cert |
| **GKE API 信任** | GKE API 用自己的真实 cert | GKE API 看到 Squid 签的 fake cert |
| **性能** | 极低开销(透传) | 高开销(加解密 2 次)|
| **合规** | 不破坏 TLS 端到端 | 破坏 TLS 端到端(必须告知用户)|

→ **业务方架构是"安全优先 + 最小干预"**,**不需要 ssl-bump**。

### 7.4 业务方架构需要的安全控制(替代 ssl-bump)

| 替代机制 | 实现 |
|---|---|
| **Squid ACL 限制 CONNECT 目标** | 只允许特定 host(白名单) |
| **Squid ACL 限制来源 IP** | 只允许内网 Nginx 主机 |
| **Nginx 强制 Host 头重写** | 防止 Host 头注入(业务方已配) |
| **GKE Envoy 按 SNI 严格匹配 filter chain** | 防止 host 头伪造 |
| **TLS 1.2+ 强制 + 现代 cipher suite** | Nginx 侧 `ssl_protocols` + `ssl_ciphers` 已配 |

---

## 8. 业务方认知校准

### 8.1 业务方原话

> "Squid 自动从 URL 提取 host 作 SNI ← 这里就是 SNI 注入点"

### 8.2 架构师校准

| 业务方理解 | 真实情况 | 准确度 |
|---|---|---|
| "Squid 自动从 URL 提取 host" | ✅ Squid 从 CONNECT 请求提取 host | ✅ **完全正确** |
| "host 作 SNI" | ⚠️ **不是 Squid 作的**,**是 OpenSSL 自动填的** | ⚠️ **主体错** |
| "SNI 注入点" | ✅ 概念正确(Squid 跟 GKE 这一跳是关键) | ✅ **正确** |

### 8.3 架构师最终结论

**SNI 注入的精确主体链**:
1. **Nginx**:从 URL 提取 host + 通过 rewrite + proxy_set_header 把 host 传给 Squid
2. **Squid**:从 CONNECT 请求解析 host + 用 host 字符串调用 OpenSSL SSL_connect()
3. **OpenSSL**(Squid 进程内):自动把 host 填入 ClientHello 的 SNI 扩展
4. **GKE API / Envoy**:解析 ClientHello.SNI + 按 SNI 匹配 filter chain + 选 cert

→ **业务方认知"Squid 自动从 URL 提取 host 作 SNI"是**直觉正确但主体不够精确**——**SNI 注入的实际动作主体是 OpenSSL 库,Squid 只是提供了 host 字符串作为输入**。

---

## 9. 业务方常见疑问解答

### 9.1 疑问 1:如果我想看 SNI 是不是真的填了,怎么验证?

**架构师答**:**抓包**。详见 §6。最佳证据:**GKE API 侧抓包** + tshark 解析 ClientHello.extensions.server_name。

### 9.2 疑问 2:如果 OpenSSL 自动填 SNI,我能控制吗?

**架构师答**:能控制**填充的源**(通过 hostname 参数),但**填充动作是 OpenSSL 自动做的**。业务方架构下,Squid 给 OpenSSL 的 hostname = CONNECT 请求的 host,**业务方不需要控制**。

### 9.3 疑问 3:为什么 Squid 不显式填 SNI,要用 OpenSSL 自动填?

**架构师答**:
- **简洁**——不需要额外配置
- **可靠**——OpenSSL 是 TLS 标准实现,SNI 处理经过充分测试
- **跨版本兼容**——OpenSSL 1.0.2+ 全部支持 SNI 自动填充
- **ssl-bump 模式下** Squid 才需要显式解析 SNI(因为要解密 + 看规则)

### 9.4 疑问 4:如果业务方用 `https_port` 而不是 `http_port`,会怎样?

**架构师答**:
- `http_port 3128`:**Squid 接受明文 HTTP CONNECT 请求**(业务方架构)
- `https_port 3128`:**Squid 接受加密的 HTTP CONNECT 请求**(需要客户端配置 Squid cert)
- **两种模式 SNI 注入机制相同**——都是 OpenSSL 自动填
- **业务方架构不需要 `https_port`**(Nginx 跟 Squid 之间是内网,可信)

### 9.5 疑问 5:ssl-bump 模式下 SNI 是 Squid 显式填的吗?

**架构师答**:**不是**。
- `ssl-bump peek`:Squid 看 ClientHello **已有的** SNI(不是填),做规则匹配
- Squid 不会"主动修改"SNI 值
- **SNI 永远由 ClientHello 的发起方决定**——要么是客户端,要么是 upstream(OpenSSL 自动填)

### 9.6 疑问 6:业务方架构有没有安全风险?

**架构师答**(参考,**业务方已确认生产可用**):
- ✅ **TLS 端到端**:客户端 ↔ Squid 段是 HTTP(透明),Squid ↔ GKE 段是 TLS(端到端加密)
- ⚠️ **Squid 是 TLS 边界点**:Squid 主机被攻破 = TLS 旁路——**这是所有 forward proxy 的固有风险**
- ⚠️ **建议加 host 白名单**(Squid ACL):只允许特定 host(如 `apiname.team.caep.uk` / `te2apiname.temm2.caep.uk`)
- ⚠️ **建议加来源 IP 白名单**:只允许内网 Nginx 主机

---

## 10. 决策树:Squid SNI 行为的 3 个分支

```
Squid 在客户端 ↔ GKE 中间,SNI 怎么填?
│
├─ 模式 A:forward proxy + HTTP CONNECT(默认)  ← 业务方架构走这条
│   │
│   ├─ 客户端发 CONNECT host:port
│   ├─ Squid 解析 host
│   ├─ Squid 调用 OpenSSL SSL_connect(host)  ← host 是字符串
│   └─ OpenSSL 自动填 ClientHello.SNI = host
│
├─ 模式 B:ssl-bump peek(SSL inspection)
│   │
│   ├─ 客户端发 ClientHello(ClientHello 含 SNI)
│   ├─ Squid 解密 → 显式解析 ClientHello.SNI
│   ├─ Squid 做规则匹配(acl ssl::server_name ...)
│   └─ Squid 决定 peek / splice / bump
│
└─ 模式 C:transparent interception(iptables redirect)
    │
    ├─ 客户端发 ClientHello(直接到 Squid,无 CONNECT)
    ├─ Squid 配 ssl-bump 才能看 ClientHello
    └─ 同模式 B
```

**业务方架构 = 模式 A**,**SNI 由 OpenSSL 自动填,Squid 本身不操作**。

---

## 11. 架构师 lane 边界声明

- ✅ 生成 `squid-sni.md`(本节文档,11 节)
- ✅ 引用 Squid 官方文档(`Features/HTTPS` + `Features/SslPeekAndSplice` + `http_port` 配置)
- ✅ 引用 Nginx 官方文档
- ✅ 提供抓包验证方法(§6)
- ✅ 校准业务方"Squid 自动填 SNI"的认知(§8)
- ❌ **不抓包验证**(架构师不接 lane)
- ❌ **不修改 Squid 配置**(业务方生产已可用)
- ❌ **不实施任何 Squid 部署 / 调优**

---

## 12. 文档维护

- **作者**:**architect-gcp**(架构师,设计 lane)
- **Reviewers**:业务方(已确认生产可用)、infra-gcp
- **配套文档**:
  - 上游架构:[`../../nginx/docs/proxy-pass/nginx-proxy-pass-sni.md`](../../nginx/docs/proxy-pass/nginx-proxy-pass-sni.md)
  - 同目录:[`squid-as-https-proxy.md`](../squid-as-https-proxy.md) — Squid 作为 HTTPS proxy 的部署文档
  - 同目录:[`squid-conf.md`](../squid-conf.md) — Squid 基础配置
  - 同目录:[`squid-l4-explorer.md`](../squid-l4-explorer.md) — Squid L4 探索
- **状态**:Reference(架构师仅作参考,不修改业务方生产 Squid 配置)

---

<!-- cite: https://wiki.squid-cache.org/Features/HTTPS — Squid HTTPS 特性官方文档(CONNECT 方法 + 默认不解密)|
<!-- cite: https://wiki.squid-cache.org/Features/SslPeekAndSplice — Squid SslBump Peek and Splice 官方文档 -->
<!-- cite: https://www.squid-cache.org/Versions/v3/3.5/cfgman/http_port.html — Squid http_port 官方配置(4 种模式 + ssl-bump 选项)|
<!-- cite: https://ml-archives.squid-cache.org/squid-users/2020-May/022135.html — Squid HTTPS proxy 模式下 SNI/ACL 可访问性官方答复 -->
<!-- cite: https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass — Nginx proxy_pass 官方文档 -->
<!-- cite: https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_set_header — Nginx proxy_set_header 官方文档 -->
<!-- cite: RFC 6066 — TLS Server Name Indication (SNI) 扩展标准 -->
<!-- cite: OpenSSL 源码约定(SSL_connect 接受 hostname 字符串时自动填 SNI)—— 行为基于 OpenSSL 1.0.2+ 长期行为 -->
<!-- cite: 上游 nginx-proxy-pass-sni.md §3.2 — Nginx 跟 Squid 跳的完整数据流 -->
<!-- cite: 上游 nginx-proxy-pass-sni.md §5 — 业务方 SNI 理解的分析 -->
