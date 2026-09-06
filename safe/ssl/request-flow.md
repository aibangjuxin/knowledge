# HTTPS 完整请求流程 — 从 URL 到像素(OSI 7 层视角)

> **这份文档画一张完整的 HTTPS 请求链路**:从浏览器地址栏输入 URL,到服务器返回 HTTP 响应,再到 TCP 连接关闭 — 把 DNS / TCP / TLS / HTTP / 应用层全部串起来。
>
> **怎么读这张图**:
> - 顶层是 4 大阶段(URL 解析 → DNS → TCP + TLS → HTTP),每阶段用 `═══════` 分隔
> - 左侧是客户端(client),右侧是服务端(server);中间的箭头是该阶段的协议包
> - 每个阶段下方的 `╔═══╗` 框是该阶段**可能触发的 fatal / 常见报错**
> - 带 `★` 的报错 = 跟我们 `tls-handshake-ascii-flow.md` / `debug-ssl.md` 等系列文档直接相关
> - **mTLS**(双向证书)本图**不展开**(只放一行过渡),完整版见后续专门文档
>
> **配套文档**(同目录):
> - [`docs/tls-handshake-ascii-flow.md`](./docs/tls-handshake-ascii-flow.md) — TLS 1.2/1.3 握手细节
> - [`docs/tls-handshake-explained.md`](./docs/tls-handshake-explained.md) — 协议层解释 + RFC 引用
> - [`compare-san-sni.md`](./compare-san-sni.md) — SNI vs SAN 关系
> - [`sni.md`](./sni.md) — SNI 详解

---

## TL;DR

> 用户在浏览器输入 `https://example.com/path` 按回车后,大致 8 个阶段:
>
> 1. **URL 解析** (应用层 L7) — 拆分 scheme/host/path
> 2. **DNS 解析** (L7 → L5/L4) — 浏览器缓存 → OS 缓存 → resolver → 根 → TLD → 权威,UDP 53(大响应走 TCP)
> 3. **TCP 三次握手** (L4) — SYN → SYN-ACK → ACK,1 RTT
> 4. **TLS 握手** (L5-L6) — 1.3 一次 RTT(0-RTT 可选),1.2 两次 RTT;含 SNI / ALPN / cert 校验 / key exchange
> 5. **HTTP 请求** (L7) — 加密通道里发 `GET /path HTTP/1.1` 或 HTTP/2 frame
> 6. **服务器处理** (L7) — LB → 后端服务 → DB(可能)
> 7. **HTTP 响应** (L7) — 返回 HTML/JSON
> 8. **TCP 四次挥手** (L4) — FIN/ACK 各两次,主动关方进入 TIME_WAIT
>
> **mTLS 唯一区别**:第 4 阶段 TLS 握手时,ServerHelloDone 后**多一轮** CertificateRequest ↔ Certificate(客户端证书) ↔ CertificateVerify(client 用 private key 签名一段 handshake 摘要)— 业务方场景见本目录 mTLS 专题文档。

---

## 完整链路 ASCII 流程图

```
                       ┌──────────────────────────────────────────────────────────────┐
   Client              │                       Network / Server                         │
   (浏览器 / curl)     │                                                              │
   ════════════════════════════════════════════════════════════════════════════════
                       │
                       │         ╔═══ 阶段 ①: URL 解析 (Application L7) ═══╗
   输入 "https://example.com/path"                                              │
   按下 Enter                                                                   │
                       │
   ↓ 浏览器解析:                                                                │
     scheme=https                                                               │
     host=example.com                                                          │
     port=443 (默认)                                                            │
     path=/path                                                                │
                       │
   ↓ 检查 HSTS preload list                                                    │
     if example.com on list → 即使输入 http 也强制 https                       │
                       │
                       │         ╔═══ 可能的报错 ═══╗
                       │         ║ • 无 scheme → 走搜索框                          ║
                       │         ║ • HSTS 强制 https 但 TLS 失败 → 无法降级       ║
                       │         ╚════════════════════════════════════════════════╝
                       │
   ════════════════════════════════════════════════════════════════════════════════
                       │
                       │         ╔═══ 阶段 ②: DNS 解析 (Application → L7 → L4) ═══╗
                       │
   ↓ 浏览器先查本机缓存(Chrome 60s,NSLookup cache,...)                        │
   ↓ miss → OS 缓存(/etc/hosts,/etc/resolver.conf)                              │
   ↓ miss → 本地 resolver(通常 ISP 给的,或 8.8.8.8 / 1.1.1.1)                 │
   ↓ 走 DNS 协议 — UDP 53(port 53,大响应自动 fallback TCP 53)                 │
                       │
       ┌────────────────────────────────────────────┐
       │ DNS 解析层次 (从 client 视角)               │
       │                                            │
       │  client                                    │
       │    ↓ query "example.com" A/AAAA           │
       │  Local Resolver (递归)                    │
       │    ↓                                      │
       │  Root NS (.)                               │
       │    ↓ 告知 .com NS                          │
       │  TLD NS (.com)                             │
       │    ↓ 告知 example.com NS                   │
       │  Authoritative NS (example.com)            │
       │    ↓ 返回 A/AAAA record + TTL              │
       │  Local Resolver                            │
       │    ↓                                      │
       │  client 拿到 IP                            │
       └────────────────────────────────────────────┘
                       │
   client 拿到 IP: 93.184.216.34                                                │
                       │
                       │         ╔═══ 可能的报错 ═══╗
                       │         ║ • NXDOMAIN        → "无法访问此网站"            ║
                       │         ║ • SERVFAIL        → resolver 上游故障           ║
                       │         ║ • timeout         → 网络/防火墙拦截 UDP 53       ║ ★ debug-ssl.md
                       │         ║ • CDN/WAF 把 DNS query 当攻击 → 临时封 IP    ║
                       │         ╚════════════════════════════════════════════════╝
                       │
   ════════════════════════════════════════════════════════════════════════════════
                       │
                       │         ╔═══ 阶段 ③: TCP 三次握手 (Transport L4) ═══╗
                       │
   ┌─ Client ──────────────────────────── Server ─┐
   |                                          |
   |-------- SYN (seq=x) ------------------>|    ① 客户端 → 服务端:请求建连
   |                                          |
   |<------ SYN-ACK (seq=y, ack=x+1) -------|    ② 服务端 → 客户端:同意 + 同步
   |                                          |
   |-------- ACK (seq=x+1, ack=y+1) ------->|    ③ 客户端 → 服务端:确认
   |                                          |
   |  (connection established)             |    ✓ 连接建立 — 进入 ESTABLISHED
   └──────────────────────────────────────────┘
                       │
                       │  端口:443 (HTTPS 默认)
                       │  MSS 协商 / Window Scale / Timestamps (SYN 阶段一并)
                       │  TLS 1.3 时,这个握手 + TLS handshake 合并 ≈ 1 RTT
                       │
                       │         ╔═══ 可能的报错 ═══╗
                       │         ║ • SYN 无响应       → 防火墙丢包 / 端口未开         ║
                       │         ║ • SYN-ACK 重传     → 链路上有丢包                   ║
                       │         ║ • RST 立即回       → 端口存在但应用拒绝           ║
                       │         ║ • TIME_WAIT 堆积   → 短连接高并发场景             ║
                       │         ╚════════════════════════════════════════════════╝
                       │
   ════════════════════════════════════════════════════════════════════════════════
                       │
                       │         ╔═══ 阶段 ④: TLS 握手 (Presentation L6 + Session L5) ═══╗
                       │         ║ 详见 docs/tls-handshake-ascii-flow.md              ║
                       │         ║ 这里只列 TLS 1.3 主路径(默认)                       ║
                       │
   ┌─ Client ──────────────────────────── Server ─┐
   |                                          |
   |--- ClientHello ------------------------>|  ① SNI=example.com
   |      cipher suites                       |     + key share (ECDHE)
   |      + supported_versions (1.3)          |     + ALPN (h2, http/1.1)
   |      + random                            |
   |                                          |
   |                              [服务器计算:]
   |                              1. 选 cipher (AES-256-GCM / ChaCha20)
   |                              2. 选 cert chain (含 leaf + intermediates)
   |                              3. 验证: 域名匹配 SNI / cert chain 信任
   |                                          |
   |<-- ServerHello --------------------------|  ② 选定 cipher + key share
   |<-- Certificate (X.509 chain) ------------|  ③ server cert (CN/SAN=example.com)
   |<-- CertificateVerify (ECDHE sig) --------|  ④ server 用 private key 签名 handshake 摘要
   |<-- Finished (encrypted) -----------------|  ⑤ server:握手摘要 MAC
   |                                          |
   |--- Finished (encrypted) ---------------->|  ⑥ client:握手摘要 MAC
   |                                          |
   |  (Application Data 加密通道建立)        |  ✓ TLS 1.3:1 RTT 完成握手
   |  (0-RTT 模式: client Finished 可带       |     (TLS 1.2:还需 ClientKeyExchange 等)
   |   早期数据,但有重放风险)                  |
   └──────────────────────────────────────────┘
                       │
                       │         ╔═══ 可能的报错(fatal,关 TCP) ═══╗
                       │         ║ • handshake_failure (40)                         ║ ★ handshake-ascii
                       │         ║   → cipher 交集 = ∅                              ║
                       │         ║ • protocol_version (70)                          ║
                       │         ║   → 仅 TLS 1.0/1.1 client 连 1.3-only server       ║
                       │         ║ • certificate_expired (45) / unknown_ca (48)     ║ ★ openssl x509
                       │         ║ • bad_certificate (42) — 签名错误                  ║
                       │         ║ • SAN/SNI mismatch                                ║ ★ CVE-2026-50010
                       │         ║   → SAN 无 example.com  / cert 给 *.other.com   ║
                       │         ║ • unsupported_extension                            ║
                       │         ║ • decrypt_error (51) — Finished MAC 不匹配       ║
                       │         ║   → 经常是中间人 / 系统时间错乱 / MTU 问题       ║
                       │         ╚════════════════════════════════════════════════╝
                       │
   ─────── mTLS 区别(简述,不展开) ───────
   │  TLS 单向认证(上图):client 验 server cert
   │  mTLS 双向认证:server HelloDone 后**多一轮**
   │    ServerHelloDone → CertificateRequest
   │    → Certificate (client 证书链)
   │    → CertificateVerify (client 用 private key 签 handshake hash)
   │    → Finished (client 加密)
   │  → server 验 client 证书链(TrustConfig / CA bundle)
   │  业务方 GLB + PSC NEG + Master K8s Gateway 场景见 ADR-014 系列
   ──────────────────────────────────────
                       │
   ════════════════════════════════════════════════════════════════════════════════
                       │
                       │         ╔═══ 阶段 ⑤: HTTP 请求 (Application L7) ═══╗
                       │         ║ TLS 加密通道里传输                                ║
                       │
   ┌─ Client ──────────────────────────── Server ─┐
   |                                          |
   |  (TLS record: type=application_data     |
   |   fragment=<encrypted HTTP request>)    |
   |                                          |
   |--- GET /path HTTP/1.1 ------------------>|  (HTTP/1.1 文本)
   |    Host: example.com                     |  (HTTP/2 二进制 frame)
   |    User-Agent: Mozilla/5.0               |
   |    Accept: text/html                     |
   |    Accept-Encoding: gzip, br             |
   |    Connection: keep-alive                |  (HTTP/1.1 默认 keep-alive,
   |    Cookie: session=...                   |   HTTP/2 多路复用无需)
   |                                          |
   └──────────────────────────────────────────┘
                       │
                       │         ╔═══ 可能的报错(应用层,不解 TLS) ═══╗
                       │         ║ • HTTP/2 SETTINGS frame 不被服务端接受 → 降级 1.1 ║
                       │         ║ • 大 body 超 Max-FRAMESIZE → GOAWAY frame       ║
                       │         ║ • Cookie 过大 / Header 字段缺失 (Host 必须)    ║
                       │         ╚════════════════════════════════════════════════╝
                       │
   ════════════════════════════════════════════════════════════════════════════════
                       │
                       │         ╔═══ 阶段 ⑥: 服务器处理 (Application L7) ═══╗
                       │         ║ 这一层在 client 视角是黑盒                        ║
                       │
   ┌─ Server ───────────────────────────────────────────────────────────────────┐
   | (LB / CDN / WAF 链)                                                          |
   |   ↓                                                                          |
   | Nginx / Envoy / ALB — 解析 path / header                                    |
   |   ↓                                                                          |
   | 应用框架 — 路由到 handler (Java Spring / Go net/http / Node express / ...)  |
   |   ↓                                                                          |
   | 业务逻辑 — 查 DB / 调下游微服务 / 算缓存                                    |
   |   ↓                                                                          |
   | 拼装 Response: status + headers + body (HTML / JSON / 二进制)               |
   └─────────────────────────────────────────────────────────────────────────────┘
                       │
                       │  (如果有 LB / CDN,这一段会被分发到多个节点;
                       │   GCP GLB + Cloud Armor + PSC NEG + K8s Gateway 场景见
                       │   safe/ssl/ ../public-mtls-global-ingress 系列文档)
                       │
   ════════════════════════════════════════════════════════════════════════════════
                       │
                       │         ╔═══ 阶段 ⑦: HTTP 响应 (Application L7) ═══╗
                       │
   ┌─ Client ──────────────────────────── Server ─┐
   |                                          |
   |<-- HTTP/1.1 200 OK ----------------------|  示例响应:
   |    Content-Type: text/html; charset=UTF-8 |
   |    Content-Encoding: br                  |  (HTTP/2 HEADERS + DATA frames)
   |    Cache-Control: max-age=3600            |
   |    ETag: "abc123"                        |
   |    Strict-Transport-Security: max-age=... |  (HSTS — 浏览器记录,以后强制 https)
   |    Set-Cookie: session=...; Secure; HttpOnly
   |    <html>...encrypted body...</html>      |  body 通常 br/gzip 压缩
   |                                          |
   └──────────────────────────────────────────┘
                       │
                       │         ╔═══ 常见的响应码 ═══╗
                       │         ║ • 2xx — 成功 (200 OK / 204 No Content / 206 Partial)║
                       │         ║ • 3xx — 重定向 (301 Moved / 304 Not Modified)     ║
                       │         ║ • 4xx — client 错 (400 / 401 / 403 / 404 / 429)   ║
                       │         ║ • 5xx — server 错 (500 / 502 / 503 / 504)          ║
                       │         ╚════════════════════════════════════════════════╝
                       │
                       │         ╔═══ 服务端错误排查 ═══╗
                       │         ║ • 502 Bad Gateway — 上游 LB → 后端 timeout       ║
                       │         ║ • 503 Service Unavailable — 后端过载 / 健康检查失败║
                       │         ║ • 504 Gateway Timeout — 后端响应超时              ║
                       │         ╚════════════════════════════════════════════════╝
                       │
   ════════════════════════════════════════════════════════════════════════════════
                       │
                       │         ╔═══ 阶段 ⑧: TCP 四次挥手 (Transport L4) ═══╗
                       │         ║ 若 Connection: keep-alive,这一阶段会延后           ║
                       │         ║ 直到浏览器标签页关闭 / idle timeout               ║
                       │
   ┌─ Client ──────────────────────────── Server ─┐
   |                                          |
   |--- FIN (seq=u) ------------------------>|  ① 主动关方 (可能是 client 或 server)
   |                                          |
   |<-- ACK (ack=u+1) ------------------------|  ② 对端确认 FIN
   |                                          |
   |<-- FIN (seq=v) -------------------------|  ③ 对端也准备关
   |                                          |
   |--- ACK (ack=v+1) ---------------------->|  ④ 主动关方确认
   |                                          |
   |  (主动关方进入 TIME_WAIT 状态            |  ✓ Linux 默认 TIME_WAIT = 60s
   |   防止延迟的旧包污染新连接 —             |     防止后续同 4-tuple 的新连接
   |   因为同源 IP/port 可能被复用)            |     收到旧的 FIN/数据
   └──────────────────────────────────────────┘
                       │
                       │         ╔═══ 关键调优点 ═══╗
                       │         ║ • 高并发短连接 → TIME_WAIT 堆积                   ║
                       │         ║   解决: tcp_tw_reuse / 连接池 / HTTP/2 多路复用    ║
                       │         ║ • RST 提前关 (异常断连)                            ║
                       │         ║   应用崩溃 / idle timeout / proxy 强制清           ║
                       │         ╚════════════════════════════════════════════════╝
                       │
   ════════════════════════════════════════════════════════════════════════════════
                       │
                       │  ✓ 完整请求结束。
                       │  从 URL 输入到 TCP TIME_WAIT,通常 < 1s (本地网络)
                       │  或 < 几百 ms (跨大洲)
                       │
```

---

## OSI 7 层映射总览

| 阶段 | OSI 层 | 协议 | 包 / 报文关键字段 | 典型 debug 工具 |
|---|---|---|---|---|
| **① URL 解析** | L7 Application | (本地处理) | scheme / host / path / query | `curl -v` |
| **② DNS 解析** | L7 → L4 (UDP/TCP) | DNS (RFC 1035), DoH (RFC 8484) | A/AAAA/CNAME records + TTL | `dig`, `nslookup`, `host` |
| **③ TCP 握手** | L4 Transport | TCP (RFC 9293) | SYN / SYN-ACK / ACK + seq + window | `tcpdump`, `ss -s` |
| **④ TLS 握手** | L5 Session + L6 Presentation | TLS 1.2 (RFC 5246) / 1.3 (RFC 8446) | ClientHello(SNI+ALPN+cipher+keyshare) → ServerHello+Cert+Finished | `openssl s_client`, `wireshark` |
| **⑤ HTTP 请求** | L7 Application | HTTP/1.1 (RFC 9110) / HTTP/2 (RFC 9113) / HTTP/3 (RFC 9114) | method + path + headers + body (or HTTP/2 frames) | `curl -v`, Chrome DevTools |
| **⑥ 服务器处理** | L7 Application | (应用内部) | 路由 / 业务逻辑 / DB 查询 | 服务端 logs |
| **⑦ HTTP 响应** | L7 Application | 同 ⑤ | status + headers + body | 同 ⑤ |
| **⑧ TCP 关闭** | L4 Transport | TCP | FIN / ACK + 主动方 TIME_WAIT | `ss -tan state time-wait` |

**注意层号的常见误读**:
- TLS 在 OSI 严格定义里跨 L5(会话) + L6(表示) — **不是 L7**
- DNS 查询本身是 L7 应用协议,但**用 UDP/TCP**(L4)承载 — 这是"应用层协议跑在传输层"的典型例子
- HTTP/3 (QUIC) 把 TLS 1.3 嵌进 QUIC,真正做到 L4 — 这是一个新趋势

---

## 时间线总结(TLS 1.3 + HTTP/2,典型延迟)

```
t=0ms       ┌── URL 解析 (浏览器, <1ms)
t=10ms      ├── DNS 解析 (缓存命中: <5ms; 未命中: 20-100ms 跨网)
t=30ms      ├── TCP 握手 SYN → SYN-ACK → ACK (≈1 RTT ≈ 10-50ms 跨大洲)
t=60ms      ├── TLS 1.3 握手 (1 RTT: ClientHello → ServerHello+Finished) (≈10-50ms)
            │   ← 此时 encrypted channel 已建好
t=80ms      ├── HTTP/2 HEADERS + DATA frames (≈10-50ms 跨大洲)
t=130ms     ├── 服务器处理 (LB + 后端服务,通常 50-500ms;含 DB query)
t=180ms     ├── HTTP/2 响应 frames (≈10-50ms)
            ├── 浏览器开始 render (DOM → CSSOM → layout → paint → composite)
t=250ms     └── 用户看到内容
```

**对比 TLS 1.2**(更老,默认场景):TLS 握手要 **2 RTT**(ClientHello → ServerHello+Cert → ClientKeyExchange+Finished → ServerFinished),所以总时长多 1 RTT ≈ 30ms。

---

## 常见问题速查

| 现象 | 大概率阶段 | 排查起点 |
|---|---|---|
| 浏览器报 "无法访问此网站" | ② DNS | `dig example.com` / `nslookup example.com` |
| 浏览器转圈很久,最后 timeout | ③ TCP 或 ④ TLS | `curl -v https://example.com` 看卡在哪一步 |
| 报 "您的连接不是私密连接" | ④ TLS 证书 | 浏览器点证书查看详情;或 `openssl s_client -connect example.com:443` |
| 报 "此网站无法提供安全连接" | ④ TLS 协议 | client / server TLS 版本不兼容 |
| 报 "ERR_CONNECTION_RESET" | ③ TCP RST 或 ④ TLS alert | 抓包看是否 TCP RST 或 TLS fatal alert |
| 报 "504 Gateway Timeout" | ⑥ 服务器处理 | LB → 后端 timeout,检查后端 health check |
| 报 "502 Bad Gateway" | ⑥ 服务器处理 | 后端无响应或 5xx,检查后端服务日志 |
| 报 "403 Forbidden" | ⑥ 服务器处理 | WAF / Cloud Armor / 应用层拒绝 |
| 报 "429 Too Many Requests" | ⑥ 服务器处理 | rate-limit 触发 |
| 网页空白但 curl -I 返回 200 | ⑦ 响应后渲染 | 浏览器 console / JS error |
| 短连接高并发 TIME_WAIT 堆积 | ⑧ TCP | `ss -s`, 考虑连接池 / HTTP/2 多路复用 |

---

## 关键交互

### TLS 1.2 vs 1.3 差异(影响 ④ 阶段)

| 维度 | TLS 1.2 | TLS 1.3 |
|---|---|---|
| **RTT** | 2 RTT(完整握手)/ 1 RTT(resume) | **1 RTT**(完整握手)/ **0 RTT**(resumption) |
| **Cipher suites** | 大量(包含 CBC / RC4 等弱密码)| 仅 AEAD (AES-GCM / ChaCha20-Poly1305) |
| **Key exchange** | RSA / (EC)DHE | 仅 (EC)DHE — 前向保密 (PFS) **强制** |
| **证书链** | server-only | server-only (mTLS 时 client 也发) |
| **握手消息数** | 2-RTT 路径: 4 个明文消息 + 2 个密文消息 | **1-RTT 路径: 1+3 个明文消息 + 0 个密文消息**(0-RTT 时) |
| **当前默认** | 仍广泛支持(老服务器) | **新部署默认应选 1.3** |

### HTTP/1.1 vs HTTP/2 vs HTTP/3 差异(影响 ⑤⑦ 阶段)

| 维度 | HTTP/1.1 | HTTP/2 | HTTP/3 |
|---|---|---|---|
| **传输** | TCP + TLS | TCP + TLS | **QUIC (UDP) + TLS 1.3** |
| **多路复用** | ❌ 一连接一请求(队列)| ✅ 一连接多 stream(并行)| ✅ 同 HTTP/2,但无 TCP HOL blocking |
| **头部压缩** | ❌ | ✅ HPACK | ✅ QPACK |
| **优先级** | ❌ | ✅ stream priority | ✅ 同 HTTP/2 |
| **当前默认** | fallback / 老 client | **现代推荐** | 渐进采用,需 UDP 443 不被封 |

---

## 相关文档

- **TLS 握手细节** — [`docs/tls-handshake-ascii-flow.md`](./docs/tls-handshake-ascii-flow.md) (★ 同目录必读)
- **TLS 协议解释** — [`docs/tls-handshake-explained.md`](./docs/tls-handshake-explained.md)
- **cipher suites** — [`docs/cipher-suites-explained.md`](./docs/cipher-suites-explained.md)
- **SNI vs SAN** — [`compare-san-sni.md`](./compare-san-sni.md)
- **SNI 详解** — [`sni.md`](./sni.md)
- **debug SSL 实战** — [`debug-ssl.md`](./debug-ssl.md), [`debug-ssl-chatgpt.md`](./debug-ssl-chatgpt.md)
- **mTLS 业务方场景** — `../public-mtls-global-ingress/ADR-014` (跨项目 mTLS 跨项目 TLS)

---

**作者备注**:第一版(2026-09-06),用 ASCII 流程图串起 OSI 7 层与 8 个请求阶段。mTLS 与 HTTP/3 仅简述,如需展开独立成专题文档。

