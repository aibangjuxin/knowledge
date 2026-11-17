# 邮件协议与端口速查

## SMTP 端口语义（权威来源见文末）

| 端口 | 服务名 | 协议 | 加密时机 | RFC | 用途 |
| --- | --- | --- | --- | --- | --- |
| 25 | smtp | 明文 SMTP | STARTTLS 可选 | RFC 5321 | 服务器间中继 (MTA→MTA) |
| 465 | submissions | SMTPS | **隐式 TLS，TCP 建连即握手** | RFC 8314 | 用户提交 |
| 587 | submission | 明文 SMTP | STARTTLS 强制 | RFC 6409 | 用户提交（替代 465）|
| 2525 | — | 明文 SMTP | STARTTLS 可选 | 非标 | AWS / 阿里云备用端口 |

**关键区别：465 与 587 的加密时机不同**

```
端口 587 (submission) — STARTTLS：
  客户端 ──TCP──► 服务器        (明文)
         ──EHLO──►
         ◄──250 STARTTLS──      (明文协商)
         ──STARTTLS──►           (此刻开始 TLS 握手)

端口 465 (submissions) — Implicit TLS：
  客户端 ──TCP+TLS──► 服务器    (握手发生在第一个应用字节之前)
         ──EHLO──►               (全程密文)
```

RFC 8314 §3.3 原文：
> When a TCP connection is established for the "submissions" service (default port 465), a TLS handshake begins immediately.

**这意味着：如果中间有 L7 代理，只支持 STARTTLS 的代理能处理 587，但无法处理 465** —— 因为 465 的 TLS 握手在 TCP 层就开始了，代理必须先透传字节流而不能自己解析协议。

## 端口 25 的现实封锁

端口 25 在公有云上几乎全被封：

- GCP / AWS / Azure 均默认封锁发往 25 的出站流量，且**申请解封通常需提交工单 + 说明用途**
- Gmail / Outlook 等消费级邮箱**永久拒收**来自云 IP 的 25 端口中继（防垃圾邮件）
- 实际可用的提交路径是 587 / 465 / 2525，不是 25

## Squid 能否代理 SMTP

**结论：不能。** Squid 是 HTTP/HTTPS 代理（RFC 7230），不是通用 TCP/SOCKS 代理。

### Squid 官方默认配置原文

```
acl SSL_ports port 443
acl Safe_ports port 80      # http
acl Safe_ports port 21      # ftp
acl Safe_ports port 443     # https
acl Safe_ports port 70      # gopher
acl Safe_ports port 210     # wais
acl Safe_ports port 1025-65535  # unregistered ports
...
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
```

两条规则说明：

1. `Safe_ports` 里**没有 25 / 465 / 587** → 默认全被拒
2. `deny CONNECT !SSL_ports` → CONNECT 方法只允许到 443

即使手工加 `acl SSL_ports port 587`，`CONNECT` 语义本身也不是为 SMTP 设计的：HTTP CONNECT 隧道要求客户端先发 `CONNECT host:port HTTP/1.1`，而 SMTP 客户端不会这么做 —— 它直接等服务器的 `220 greeting`。协议握手根本对不上。

### 要代理 TCP 用 SOCKS5

```
# Squid 支持 SOCKS 模式（编译时需 --enable-ssl + SOCKS 支持）
squid -N -p 3129   # HTTP 代理

# 真正的 TCP 代理应该用 SOCKS5：
ssh -D 1080 user@bastion        # SOCKS5 动态端口转发
curl --socks5-hostname 127.0.0.1:1080 smtp://smtp.gmail.com:587
```

SMTP 客户端若要走 SOCKS5，需要客户端本身支持（如 Python `smtplib` + PySocks，或 curl 的 `--socks5-hostname`）。

## AWS SES 风格的替代方案

如果目的是「从 GKE 发出邮件」，比打通 25 更现实的是走 HTTP API：

| 服务 | 协议 | 出网端口 |
| --- | --- | --- |
| AWS SES | HTTPS API (`https://email.<region>.amazonaws.com`) | 443 |
| GCP Pub/Sub + 第三方 | HTTPS | 443 |
| 自建 relay (Postfix) 监听 587 | SMTP | 587 |

走 443 的最大好处：不需要动防火墙的 25 端口规则，也不依赖 STARTTLS/implicit TLS 的端口差异。

## 参考

- [RFC 821 — Simple Mail Transfer Protocol](https://www.rfc-editor.org/rfc/rfc821.txt) — 端口 25
- [RFC 5321 — SMTP (2008)](https://www.rfc-editor.org/rfc/rfc5321.txt) — ESMTP 现行标准
- [RFC 6409 — SMTP Submission](https://www.rfc-editor.org/rfc/rfc6409.txt) — 端口 587
- [RFC 8314 — SMTP TLS 重构](https://www.rfc-editor.org/rfc/rfc8314.txt) — 隐式 TLS / 端口 465
- Squid 官方默认配置 `src/cf.data.pre` — `Safe_ports` / `SSL_ports` / `deny CONNECT !SSL_ports`
