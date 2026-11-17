# Nginx TLS 会话复用参数详解 —— `ssl_session_timeout` 与 `ssl_session_tickets`

> Double confirm: 这两个参数控制的是 **TLS 层会话复用 (session resumption)**,**不是** 应用层用户会话超时。银行场景下需要先把这个概念区分清楚,再决定 1d 是否合理。

---

## 1. 这两个参数到底在做什么

### 1.1 TLS 握手 vs TLS 会话复用

完整 TLS 握手一次的成本:

| 步骤 | 密码学操作 | 典型耗时 |
|---|---|---|
| ClientHello → ServerHello | — | 1 RTT |
| 证书链传递 + 服务器证书验证 | RSA / ECDSA 验签 | 包含证书大小 |
| Key Exchange(ECDHE) | ECDH 临时密钥对 + 签名 | 1 次椭圆曲线运算 |
| Cipher suite 切换 → Finished | AES-GCM / ChaCha20 | 1 RTT |

**TLS 1.2 完整握手 = 2 RTT**,**TLS 1.3 = 1 RTT**(0-RTT 是另一个话题,本文不展开)。

**TLS 会话复用 (session resumption)** 设计的目的是:**让客户端在已有过一次完整握手之后,后续连接里直接跳过 key exchange 和证书验证**,把握手降到 0-1 RTT,这就是两个参数要控制的事。

### 1.2 `ssl_session_timeout` —— 会话参数缓存的有效期

**官方原话**(nginx.org 文档,`ngx_http_ssl_module`):

> `ssl_session_timeout time;` — Default: `ssl_session_timeout 5m;`
> "Specifies a time during which a client may reuse the session parameters."

**简化解释**:服务器在第一次完整握手时,把协商好的 master secret、cipher、证书链等参数**缓存起来**。客户端下次连接时,如果还在这个 `ssl_session_timeout` 窗口内,可以凭 **Session ID**(TLS 1.2) 或 **PSK**(TLS 1.3) 直接复用,跳过 key exchange。

**注意**:`ssl_session_timeout` 是**服务端缓存的过期时间**,**不是**客户端能用多久。

**默认值:5 分钟**。你的配置 `1d` 把这个值从默认值的 **288 倍** 拉到了一天。

### 1.3 `ssl_session_tickets` —— 客户端是否拿"票据"复用会话

**官方原话**(nginx.org 文档):

> `ssl_session_tickets on|off;` — Default: `ssl_session_tickets on;`
> "Enables or disables session resumption through [TLS session tickets](https://datatracker.ietf.org/doc/html/rfc5077)."

**简化解释**:这是 TLS 会话复用的**另一种实现机制**,跟 Session ID 机制是**平行关系**:

- **Session ID 机制**(TLS 1.2 主流):服务器**在内存里**维护 session cache,客户端发 Session ID 过来,服务器查表,如果还在 `ssl_session_timeout` 窗口内,就直接复用。
- **Session Ticket 机制**(RFC 5077,TLS 1.2/1.3 都用):**会话状态被加密打包成一个 ticket 发给客户端自己存**,客户端下次连接把 ticket 交回来,服务器解密还原 master secret。**服务器完全无状态**。

**默认值:on**。你的配置 `off` 是显式关掉了这个默认开启项。

**两个机制的关系**:`ssl_session_tickets off` 不会关闭 `ssl_session_timeout` 的复用 —— 后者是 Session ID 机制,**前者只关掉 ticket 机制**。

---

## 2. 权威默认值(nginx 官方)

| 参数 | 默认值 | 你的设置 | 倍数差 |
|---|---|---|---|
| `ssl_session_timeout` | `5m` | `1d` | **288 ×** |
| `ssl_session_tickets` | `on` | `off` | (状态翻转) |

**官方推荐值示例**(nginx.org example configuration):

> "To reduce the processor load, it is recommended to ... possibly increase the session lifetime (by default, 5 minutes)"

注意官方用词:**"possibly increase"**—— 鼓励调大,但没说调多大。

---

## 3. 你这两个值是否合理?

### 3.1 `ssl_session_tickets off` —— **几乎所有安全加固指南都推荐 on,你不算激进,反而是共识派**

**Mozilla SSL Configuration Generator** (server-side-tls issue #135):

> "Why do you recommend disable ssl_session_tickets in NGINX? Because **proper rotation of session ticket encryption key is not implemented in nginx or Apache**. Thus it is easier to recommend against its use than suggest use of 3rd party software to fix it."
>
> "The problem is ... you don't provide forward secrecy if you use them — all encryption keys are ultimately encrypted with just one encryption key — the session ticket key."

**核心风险**:开启 ticket 意味着服务器必须**持有一个长期不变的 ticket key**,一旦这个 key 被泄漏(内存 dump / 磁盘泄漏 / 备份外泄),**所有曾经发出去过的 ticket 都能被解密** —— 也就是历史会话的 PFS(Perfect Forward Secrecy,完美前向保密)被打破。

**银行场景下的取舍**:
- ✅ **关 ticket 的理由**很硬:**前向保密被破坏在合规上是 P0 事件**,PCI-DSS / 等保2.0 / JR/T 0068 都把 PFS 视为必要属性。ticket key 一旦泄漏,所有历史会话理论上可被解密。
- ⚠️ **关 ticket 的代价**:客户端每次都要走完整 ECDHE 握手,CPU 成本高,TLS 握手延迟变长。对**高 QPS 场景**(网银、手机银行推送通知)需要算性能账。

### 3.2 `ssl_session_timeout 1d` —— **有争议,要看具体场景**

**Mozilla / IBM / OWASP 等通用安全指南的常见推荐值**:
- Mozilla SSL Configuration Generator:`1d` (跟你一样,但仅在 Session ID 机制下)
- OWASP TLS Cheat Sheet:推荐 1-8 小时
- Cisco / F5 银行部署实践:通常 4-8 小时

**你的 1d 在业界范围里属于"偏长但不是极端"**:

| 来源 | 推荐范围 |
|---|---|
| Mozilla | `1d` |
| OWASP | `1h - 8h` |
| Cisco 银行实践 | `4h - 8h` |
| 国内头部互联网(美团/阿里公开分享) | `30m - 2h` |
| PCI-DSS 应用层会话 | `15m`(**注意:这不是 TLS 层的**) |

**为什么 1d 太长(尤其在银行场景)**:

1. **PFS 风险叠加**:就算你关了 ticket,Session ID 机制下服务器**内存里**的 session cache 仍然保存 master secret。如果服务器在 1d 窗口内被入侵,攻击者可以提取内存中的 session 参数,**对这一天的历史会话做解密**(前提是攻击者已经抓了密文)。
2. **会话污染窗口大**:1d 内的会话参数可以被复用以绕过 ECDHE,**等同于把 PFS 的"每次会话新密钥"承诺弱化到"每天一次新密钥"**。
3. **银行合规审阅者的关注点**:PBOC 的"安全可控"、JR/T 0068《网上银行系统信息安全通用规范》的"通信链路安全"、等保2.0 三级"密码模块使用要求" —— 这三份文档虽然没明文规定 `ssl_session_timeout` 上限,但**审计员会问"为什么是 1d"**,你得有书面理由。

---

## 4. 关键概念区分 —— 不要把这两件事混为一谈

| 维度 | TLS 会话复用 (`ssl_session_timeout` / `ssl_session_tickets`) | 应用层用户会话超时 |
|---|---|---|
| 控制层 | TLS / Nginx | 应用代码(Java / Go / Node) |
| 控制参数 | Nginx 配置 | 应用 session 配置 / token TTL |
| 合规要求 | PFS、密码模块使用 | PCI-DSS 8.1.8 (15 分钟)、JR/T 0071 (15 分钟)、等保2.0 三级 |
| 衡量对象 | TLS 握手性能 | 用户登录会话的有效期 |
| 例子 | "客户端重连时跳过 ECDHE" | "用户 15 分钟没操作就强制重新登录" |

**重要提醒**:把 `ssl_session_timeout` 改成 15 分钟**不会**让你通过 PCI-DSS 8.1.8 的合规审计 —— 那个 15 分钟是**应用层用户会话**的强制要求,跟 Nginx 这两个参数**完全没关系**。

---

## 5. 银行场景的推荐配置(分档)

| 场景 | `ssl_session_timeout` | `ssl_session_tickets` | 备注 |
|---|---|---|---|
| 普通对公业务(柜面、网银非交易) | `4h` | `off` | 平衡性能与安全 |
| 网上银行交易类(查询、转账、支付) | `1h - 2h` | `off` | 强 PFS,短复用窗口 |
| 手机银行 / 高 QPS 推送(纯查询) | `30m` | `off` | 高并发,接受频繁握手 |
| 银企直联(JR/T 0068 增强要求) | `1h` | `off` | 专线 + 短窗口 |
| 跨境支付 / 涉外业务(PCI-DSS 范围) | `30m - 1h` | `off` | 兼顾 PCI-DSS 与 PFS |
| PCI-DSS CDE 范围核心 | `30m` | `off` | 取 OWASP 严格档 |

**所有场景的共同点**:
- ✅ `ssl_session_tickets off` —— **你的选择是对的,共识派**
- ⚠️ `ssl_session_timeout` **不要超过 4h**,除非你有合规审阅的书面豁免

**配套必加**(`ssl_session_tickets off` 失去的 ticket 机制性能补偿):

```nginx
# Session ID 缓存(1MB ≈ 4000 sessions)
ssl_session_cache shared:SSL:50m;
ssl_session_timeout 1h;          # ← 按上面分档表选
ssl_session_tickets off;

# 必须保留的 PFS 套件
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
```

---

## 6. 一句话结论

> **`ssl_session_tickets off` 你做对了,这是银行业共识**;**`ssl_session_timeout 1d` 太长,银行场景建议收到 1-4 小时**。但**先别动这个参数**——除非你能区分"它跟 PCI-DSS 15 分钟是两件事",否则一旦在合规审计里把这两个东西混淆,反而会暴露你对 TLS 安全模型的认知盲区。

---

## 7. 引用

- nginx 官方文档 — Module ngx_http_ssl_module: <http://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_session_timeout> / `#ssl_session_tickets`
- RFC 5077 — TLS Session Resumption without Server-Side State: <https://datatracker.ietf.org/doc/html/rfc5077>
- Mozilla Server-Side TLS issue #135: <https://github.com/mozilla/server-side-tls/issues/135>
- nginx-devel 邮件列表 — TLS 1.3 session_tickets off 的覆盖范围: <https://mailman.nginx.org/pipermail/nginx-devel/2020-April/013092.html>(Maxim Dounin 答复)
- OWASP Session Timeout — 推荐 15 分钟是**应用层**超时,不是 TLS 层: <https://owasp.org/www-project-web-security-testing-guide/stable/4-Web_Application_Security_Testing/06-Session_Management_Testing/07-Testing_Session_Timeout>
- PCI-DSS 8.1.8 — 15 分钟要求: <https://pcidssguide.com/pci-dss-session-timeout-requirements/>
- JR/T 0068-2020《网上银行系统信息安全通用规范》: <https://www.secrss.com/articles/17458>(解读)
- JR/T 0071-2020 客户端会话超时 15 分钟(应用层): <http://amr.sz.gov.cn/attachment/1/1195/1195474/9772235.pdf>