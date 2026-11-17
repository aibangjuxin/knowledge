# GKE 公网出网发邮件：NHF 三层路由与 Squid 代理可行性分析

> **一句话结论**：在这个环境里，**Squid 帮不上忙**。邮件服务器的 IP 根本不落在 NHF 的 `128.0.0.0/2` 路由里，流量压根到不了 NHF；而且 Squid 是 HTTP 代理，本来就不能代理 SMTP。

---

## 1. 问题拆解

需求是"GKE 环境里要 public egress 到邮件服务（SMTP 25 / 465）"。这个要求里有**两个独立的关卡**，必须都通过才行：

| 关卡 | 问题 | 由什么决定 |
| --- | --- | --- |
| **关卡 A：网络可达** | 流量能不能走出 VPC 到公网？ | GCP 路由表 + 防火墙规则 + NHF |
| **关卡 B：协议代理** | 如果必须走代理，代理能否承载 SMTP？ | Squid 的协议能力 |

**关键判断**：这两个关卡的答案是独立的，代理方案只能解决 B，解决不了 A。

---

## 2. 环境现状：NHF 是什么

参考资料：NHF 出网机制详解文档（位于 `gcp` repo 的 `linux/networking/nhf.md`，本 knowledge repo 内暂无副本）。本文中引用的路由表、防火墙规则、iptables 脚本均出自该文档。

### 2.1 NHF 的路由范围

NHF 通过两条 GCP 路由接管出网：

```
route-xxxxxx-...-ilb-128-0-0-0-2    dest=128.0.0.0/2   next-hop=192.168.0.55 (NHF ILB)  priority=1000
route-xxxxxx-...-scc-10-0-0-0-8     dest=10.0.0.0/8    next-hop=192.168.0.55 (NHF ILB)  priority=1000
```

`128.0.0.0/2` 覆盖 `128.0.0.0` ~ `191.255.255.255`，即**所有首位 bit 为 1 的 IPv4**。

### 2.2 设计意图

NHF 的文档里写得很清楚：

> 内部不再判断"这个域名到底要不要走 NHF"，只要目标落入这两个大网段就丢给 NHF，**具体能不能通，交给办公网出口做精细控制**。

**这是一个 L3-only 的统一出网关**。它解决的是"访问公司内网 DRN/SCC"的问题，不是"访问任意公网服务"的问题。

---

## 3. 关卡 A：邮件服务器的 IP 不在 NHF 路由内

这是最关键的实测结论。

### 3.1 实测：主流邮件服务商 IP 落点

```
smtp.gmail.com                      192.179.26.108    OUT-of-128/2
smtp.office365.com                  40.104.20.34      OUT-of-128/2
smtp.qq.com                         14.22.9.155       OUT-of-128/2
smtp.163.com                        111.124.203.45    OUT-of-128/2
email-smtp.us-east-1.amazonaws.com  3.224.1.122       OUT-of-128/2
```

（用公共 DNS `8.8.8.8` / `1.1.1.1` 解析，**不要用本地 DNS** —— 见 §3.3）

**没有一条落在 `128.0.0.0/2` 内**。

### 3.2 那这些流量去哪了

```
GKE Pod                    GCP 路由表                  结果
┌──────────────┐          ┌────────────────────┐      ┌──────────────────────────────┐
│ 目标         │          │ 128.0.0.0/2 ？     │      │ 该项目没有 0.0.0.0/0        │
│ 142.251.x.x │──查表──► │ 不命中              │─────►│ → default-internet-gateway  │
│ (gmail)     │          │ 10.0.0.0/8 ？ 不命中 │      │   也不存在                    │
└──────────────┘          │ 0.0.0.0/0 ？(不存在)│      │ → 无路由，丢弃                │
                          └────────────────────┘      └──────────────────────────────┘
```

NHF 文档 §4.2.1 第 3 步已经指出这个现象：

> 那 `default-internet-gateway` 呢？……**这条路由在我们的 lex-eg 项目里根本不存在**，所以"走到 Internet Gateway"是从一开始就没有选项。

所以 GKE 出网只有一条路 —— 走 NHF。而 NHF 只接 `128/2` 和 `10/8`。

### 3.3 ⚠️ 排查陷阱：本地 DNS 会骗你

本机 DNS 是 `198.19.0.3`（一个拦截器）。用它解析得到的是：

```
smtp.gmail.com    → 198.0.5.143
smtp.office365.com → 198.0.5.144
```

`198.0.5.143-148` 是**连续递增的假地址**，反查为空，不是真实公网 IP。

**如果用本地 DNS 做排查，会得出"gmail 落在 198.x，在 128/2 之外，所以走不通"的结论 —— 结论方向对，但归因完全错误**（真实原因是它根本不在 128/2 内，而是这个假 IP 恰好也不在）。

排查公网可达性时必须显式指定公共 DNS：

```bash
dig +short @8.8.8.8 smtp.gmail.com
# 或
dig +short @1.1.1.1 smtp.gmail.com
```

### 3.4 结论

**SMTP 25 / 465 / 587 全部走不通 NHF。** 这不是配置没调好，是 NHF 的设计范围不包含公网邮件服务器 —— 邮件服务商的 IP 恰好都不在 `128.0.0.0/2` 这一个粗粒度网段内。

---

## 4. 关卡 B：Squid 也代理不了 SMTP

即使假设网络能通（假设 A 关卡解决了），Squid 这条路也走不通。

### 4.1 Squid 官方默认配置原文

从 squid-cache 源码 `src/cf.data.pre` 抓取的默认配置：

```
acl SSL_ports port 443
acl Safe_ports port 80          # http
acl Safe_ports port 21          # ftp
acl Safe_ports port 443         # https
acl Safe_ports port 70          # gopher
acl Safe_ports port 210         # wais
acl Safe_ports port 1025-65535  # unregistered ports
acl Safe_ports port 280         # http-mgmt
acl Safe_ports port 488         # gss-http
acl Safe_ports port 591         # filemaker
acl Safe_ports port 777         # multiling http

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
```

**两条独立的阻断**：

1. `Safe_ports` 里**没有 25 / 465 / 587** → 默认全被拒
2. `deny CONNECT !SSL_ports` → CONNECT 方法只允许到 **443**

### 4.2 就算改了配置，协议也对不上

假设手工加 `acl SSL_ports port 587`，`CONNECT` 语义仍然不适用：

| 步骤 | HTTP CONNECT 隧道 | SMTP 会话 |
| --- | --- | --- |
| 1 | 客户端发 `CONNECT host:587 HTTP/1.1` | 客户端**不发任何东西，等服务端** |
| 2 | 服务端回 `HTTP/1.1 200 Connection Established` | 服务端回 `220 mail.example.com ESMTP` |
| 3 | 隧道建立，之后裸 TCP 透传 | 客户端回 `EHLO client` |

**协议握手在第一个字节就分叉**。SMTP 客户端不会发 HTTP 请求，它在等 220 greeting。所以哪怕 Squid 放行了端口，SMTP 客户端也无法通过 HTTP 代理建立连接。

**Squid 是 HTTP 代理（RFC 7230），不是通用 TCP 代理。** 它没有 SOCKS 协议实现。

### 4.3 需要 TCP 代理时的正确工具

| 需求 | 正确工具 |
| --- | --- |
| 通用 TCP 代理 | **SOCKS5**（不是 Squid） |
| 临时穿透 | `ssh -D 1080 user@bastion`（动态 SOCKS5 端口转发） |
| 客户端支持 | curl `--socks5-hostname`；Python `smtplib` + PySocks |

SMTP 客户端要走 SOCKS5，客户端本身必须支持 —— 这也是为什么"给个代理地址"通常不够。

---

## 5. 方案对比

假设网络可达性（关卡 A）已经解决，各方案的可行性：

| 方案 | 端口 | Squid 代理可行 | 需改防火墙 | 评价 |
| --- | --- | --- | --- | --- |
| 直连 SMTP 587 | 587 | ❌ | 需要放行 587 | 需先解决关卡 A |
| 直连 SMTPS 465 | 465 | ❌ | 需要放行 465 | 同上 |
| SMTP 25 中继 | 25 | ❌ | 需要放行 25 | ❌ 云上普遍封锁，见下 |
| **走 HTTPS API**（SES 等） | **443** | ✅ **HTTPS 是 Squid 的本职** | 放行 443 | ✅ **推荐** |
| SOCKS5 + `ssh -D` | 任意 | ❌（不是 Squid） | 无 | 临时方案 |

### 5.1 端口 25 的额外问题

即使网络配置全对，25 端口在云上几乎不可用：

- GCP / AWS / Azure 均默认封锁到 25 的出站流量，解封需提交工单说明用途
- Gmail / Outlook 等**永久拒收**来自云 IP 的 25 端口中继（反垃圾策略）

所以 25 端口不是一个"打通就能用"的选项。

---

## 6. 推荐方案

### 方案 A：走 443（推荐）

用邮件服务的 HTTPS API，而不是 SMTP：

```
GKE Pod ──HTTPS 443──► email.<region>.amazonaws.com (AWS SES)
                     或 smtp2go.com / sendgrid.com 等
```

优点：

- 443 端口通常已经放行（NHF 之外可能仍需确认，但至少不在 25/465/587 这三个被封的端口里）
- 不依赖 STARTTLS vs implicit TLS 的差异
- 如果确实需要走代理，HTTPS 是 Squid 唯一原生支持的协议

**注意**：走 443 依然要解决关卡 A —— NHF 不接管公网。所以实际要做的是先确认**有没有任何一条到公网的出网路径**。

### 方案 B：申请公网出网（如果确实需要 SMTP）

如果业务上必须用 SMTP，需要网络团队配合：

1. 在 GCP 加一条到 `default-internet-gateway` 的路由（或专用 Cloud NAT）
2. 防火墙放行对应端口（建议 587 或 465，避开 25）
3. 确认节点有外部 IP 或走 Cloud NAT
4. 邮件服务商侧可能还需要 IP 白名单（尤其是 SES）

**这不是代理能解决的问题**，是网络架构层面的改动。

### 方案 C：如果确实需要一个 TCP 代理

不要用 Squid，用 **SOCKS5**：

```bash
# 在有公网出口的跳板机上
ssh -D 1080 -N user@bastion

# Pod 内测试（curl 支持 --socks5-hostname）
curl --socks5-hostname 127.0.0.1:1080 \
     -v telnet://smtp.gmail.com:587
```

局限：SMTP 客户端（Java `JavaMailSender`、Python `smtplib`）默认**不支持 SOCKS5**，需要额外封装或换客户端库。

---

## 7. 排查清单

如果要在自己的环境里实测，按这个顺序：

```bash
# 1. 用公共 DNS 拿到真实 IP（不要用本地 DNS，见 §3.3）
dig +short @8.8.8.8 smtp.gmail.com

# 2. 检查这个 IP 是否落在 NHF 路由网段
python3 -c "
import ipaddress, subprocess, sys
ip = subprocess.run(['dig','+short','@8.8.8.8',sys.argv[1]],
                    capture_output=True,text=True).stdout.strip().split('\n')[-1]
n = ipaddress.ip_address(ip)
for cidr in ['128.0.0.0/2','10.0.0.0/8']:
    print(f'{ip} in {cidr}: {n in ipaddress.ip_network(cidr)}')
" smtp.gmail.com

# 3. 查 VPC 路由表（需要有 gcloud 权限）
gcloud compute routes list --project=<PROJECT> \
  --format="table(name,destRange,nextHopInstance,nextHopIlb,priority)"

# 4. 直接测 TCP 可达性（不依赖 DNS）
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/<MAIL_IP>/587' && echo "587 open" || echo "587 blocked"

# 5. 测 443 是否可达（作为 HTTPS API 方案的可行性验证）
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/<MAIL_IP>/443' && echo "443 open" || echo "443 blocked"
```

第 4/5 步是最直接的判据 —— 如果 587 和 443 都不通，说明这个 VPC 根本没有公网出网，代理方案无从谈起。

---

## 8. 给用户的一句话回应

> 你这个环境里，NHF 接管的是 `128.0.0.0/2` 和 `10.0.0.0/8` 两个粗粒度网段，主要服务 on-prem DRN/SCC 访问。邮件服务商的 IP（gmail 是 142.251.x.x、office365 是 40.104.x.x）**恰好都不在这个网段内**，而这个 VPC 又没有到 `default-internet-gateway` 的路由，所以流量在路由表这一层就断了，根本走不到 NHF。
>
> Squid 这条路即使网络通了我也不建议：它是 HTTP 代理，默认配置里 `deny CONNECT !SSL_ports` 只放 443，而且 SMTP 客户端跟 HTTP CONNECT 的握手协议在第一个字节就对不上。
>
> **如果目标是"从 GKE 发出邮件"**，最现实的是走 HTTPS API（443）—— AWS SES 之类的，走 HTTPS 是 Squid 的本职工作，端口也不在云厂商封锁名单里。但这仍然需要先确认这个 VPC 有没有公网出网路径。

---

## 9. 参考

**权威标准**

- [RFC 821 — Simple Mail Transfer Protocol](https://www.rfc-editor.org/rfc/rfc821.txt) — 端口 25
- [RFC 5321 — SMTP (2008)](https://www.rfc-editor.org/rfc/rfc5321.txt) — ESMTP 现行标准
- [RFC 6409 — SMTP Submission](https://www.rfc-editor.org/rfc/rfc6409.txt) — 端口 587
- [RFC 8314 — SMTP TLS 重构](https://www.rfc-editor.org/rfc/rfc8314.txt) — 隐式 TLS / 端口 465

**Squid**

- Squid 源码 `src/cf.data.pre` — 默认 `Safe_ports` / `SSL_ports` / `http_access deny CONNECT !SSL_ports`
- [squid-cache.org](http://www.squid-cache.org/) — 官方站（注：`/doc/config.html` 现返回 404，配置事实以源码为准）

**内部资料**

- NHF 出网机制详解 — 位于 `gcp` repo 的 `linux/networking/nhf.md`（含完整路由表、防火墙三段规则、iptables SNAT 脚本、`128/2` 的 LPM 选路推演）

**关联文档**

- [`../mail/smtp-ports-and-proxy.md`](../mail/smtp-ports-and-proxy.md) — SMTP 端口语义速查 + Squid 能力边界
