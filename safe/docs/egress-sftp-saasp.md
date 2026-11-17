# Egress SFTP 走 SAASP Proxy 可行性分析

> **本背景**:GKE Pod 里的 Java 应用访问外部 SFTP 资源,沿用现有 `saasp-pod-nginx-squid.md` 拓扑:`GKE Pod → Nginx → Squid (www.def.com:3128) → 外部 SFTP server`
>
> **⚠️ 当前业务方状态**(2026-09-06):`http://www.def.com:3128` 返回 **502 Bad Gateway — Host Not Found or connection failed**(Squid 入口域名解析失败或服务不可达)。**本文档回答的是"如果链路恢复后,走老代理方式 + SFTP 是否可行"**,不是"恢复 def.com"。业务方需先确认 Squid 入口可达性。
>
> **关键问题**:
> 1. Squid 默认**只允许 443 端口**(HTTPS / CONNECT),SFTP 用 SSH 走 **22 端口**,**默认被 Squid 拒绝**
> 2. SFTP 是 SSH 上的文件传输协议(L5,与 HTTP 同层,但**不同 wire format**),Squid "不理解" SSH,但可用 **HTTP CONNECT method** 做 TCP tunnel
> 3. Nginx 默认也**不支持 CONNECT method**(默认 reverse proxy),需要额外模块
>
> **一句话结论**:**✅ 技术上完全可行**(协议层与 HTTPS 一样,都是 HTTP CONNECT 隧道),但需要**同时在 Squid + Nginx + 客户端三处配合配置**——Squid 加 `acl SSL_ports port 22`、Nginx 编译 `ngx_http_proxy_connect_module`(或绕过 Nginx 直接连 Squid)、客户端 SSH config 用 `ProxyCommand nc -X connect -x proxy:3128 %h %p`。
>
> **配套文档**:
> - [`saasp-pod-nginx-squid.md`](./saasp-pod-nginx-squid.md) — 现有 HTTPS 走 Squid 代理链路
> - [`tls-handshake-ascii-flow.md`](./tls-handshake-ascii-flow.md) — TLS 协议层详解
> - [`flow-ssl.md`](./flow-ssl.md) — SSL 流量流转
>
> **架构师 lane**:本文档只做**协议/配置可行性分析 + 审计风险 + 待业务方确认的问题**,**不写具体 nginx.conf / squid.conf**(那是 infra-gcp 的实施 lane)。

---

## TL;DR

| 维度 | 现状 | 需要的改动 | 改动方 |
|---|---|---|---|
| **Squid** | 默认 `acl SSL_ports port 443`(`http_access deny CONNECT !SSL_ports` → 22 端口被拒)| 添加 `acl SSL_ports port 22` + `acl Safe_ports port 22` + 重启 Squid | Squid Admin |
| **Nginx** | 默认 reverse proxy,**不支持 CONNECT method** | 编译 `ngx_http_proxy_connect_module` + 配置 `proxy_connect_allow 443 22` + 加 `proxy_pass` 转发到 Squid | Nginx Admin |
| **客户端(GKE Pod)** | Java 应用 / sftp 客户端**默认直接 TCP,不会**自动用 proxy | SSH config `ProxyCommand` 用 `nc -X connect` 或 `proxytunnel` 工具;Java 应用用 `JSch` 的 `ProxyHTTP` 类 | 业务方 |
| **审计** | Squid access_log 记录所有 CONNECT 请求(含目标 host:port) | **无需改动**,只需确认日志保留 + 监控 | 平台 Admin |
| **授权** | SFTP server 走 SSH key / password,**与现有代理无关** | 业务方确认 SFTP server 是否允许来自 Squid 出口 IP 的连接 | 业务方 + SFTP server owner |
| **性能** | CONNECT method 是 TCP tunnel,**无缓存、无协议解析** | 评估 Squid 单实例吞吐 / 连接数限制 | 平台 Admin |

---

## 1. 协议层澄清(SFTP ≠ 非加密)

**Lex 原话**:"这种协议看起来本身就是非安全的"

**纠正**:SFTP 是 **SSH 上的文件传输协议** — **加密的**。Lex 表达的可能指的是:
- **FTP**(File Transfer Protocol,21 端口)— **明文** + **非加密**
- SFTP(SSH File Transfer Protocol,22 端口)— **加密** + 走 SSH 协议
- FTPS(FTP over SSL/TLS,21 端口 + TLS)— **加密**

**架构师校准**:SFTP **不是"非加密"**,而是**与 HTTP/HTTPS 不同协议层**(都是 L7 应用层,但 SFTP 走 SSH,squid "不解析" SSH 协议,只能做 TCP tunnel)。

| 协议 | 端口 | 加密 | Squid 代理方式 |
|---|---|---|---|
| HTTP | 80 | ❌ 明文 | 完全代理(squid 解析 HTTP)|
| HTTPS | 443 | ✅ TLS | TCP tunnel via CONNECT |
| **SFTP** | **22** | ✅ **SSH** | **TCP tunnel via CONNECT(同 HTTPS)** |
| FTP | 21 | ❌ 明文 | 部分支持(legacy `ftp_port` directive,推荐放弃)|
| FTPS | 21+990 | ✅ TLS | TCP tunnel via CONNECT |

→ **SFTP 走 Squid 在协议层与 HTTPS 一样,都是 HTTP CONNECT 隧道**,只是端口是 22 而非 443。

---

## 2. 完整链路分析(7 层 × SFTP)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  GKE Pod                Nginx (abc.aibang.com)   Squid (www.def.com:3128) │
│  ═══════════════════════════════════════════════════════════════════     │
│                                                                         │
│  ┌─ Client ───────┐ ┌─ Forward Proxy ──┐ ┌─ Forward Proxy ──┐         │
│  │ (Java app /    │ │ (CONNECT method) │ │ (TCP tunnel       │         │
│  │  sftp client)  │ │  module required)│ │  via CONNECT)    │         │
│  └────────┬───────┘ └─────────┬────────┘ └─────────┬────────┘         │
│           │                   │                   │                    │
│  L7:      │ sftp / ssh client│ nginx forward proxy│ squid TCP relay    │
│  L5:      │ SSH client ──────│────── TCP tunnel ──│──── TCP tunnel      │
│  L4:      │ TCP:3128 → :443  │ TCP:443 → :3128   │ TCP:3128 → :22      │
│           │ (tunnel via Nginx │ (Squid sees only   │                    │
│           │  if no direct)   │  HTTP CONNECT)    │                    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                          │
                                          │ SSH tunnel (port 22)
                                          ▼
                              External SFTP Server
                              (sshd listening on :22, requires
                               publickey or password auth)
```

### 关键节点说明

| 节点 | 角色 | 默认是否支持 SFTP? | 需要改什么? |
|---|---|---|---|
| **GKE Pod (客户端)** | SSH/SFTP client | ❌ **默认直接 TCP,不主动走代理** | 客户端用 `ProxyCommand` / `ProxyHTTP` 显式走代理 |
| **Nginx (中间层)** | reverse proxy → forward proxy | ❌ **默认不支持 CONNECT method** | 需编译 `ngx_http_proxy_connect_module` |
| **Squid (出口代理)** | HTTP forward proxy | ⚠️ **支持 CONNECT method,但默认只允许 443 端口** | 添加 `acl SSL_ports port 22` |
| **SFTP Server (目标)** | sshd listening on :22 | ✅ SSH server,正常监听 22 | 业务方需要确认 SFTP server **允许 Squid 出口 IP**(防火墙 / iptables)|

---

## 3. Squid 配置改动(关键步骤)

### 3.1 默认 Squid 行为(阻塞 22 端口)

Squid 默认 ACL(参考 [Squid Wiki - SecurityPitfalls](https://wiki.squid-cache.org/SquidFaq/SecurityPitfalls)):

```squid
# 默认配置示例(squid.conf)
acl SSL_ports port 443
acl Safe_ports port 80        # http
acl Safe_ports port 21        # ftp
acl Safe_ports port 443       # https
acl Safe_ports port 70        # gopher
acl Safe_ports port 210       # wais
acl Safe_ports port 1025-65535 # unregistered ports
acl Safe_ports port 280       # http-mgmt
acl Safe_ports port 488       # gss-http
acl Safe_ports port 591       # filemaker
acl Safe_ports port 777       # multiling http

acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports    # ← 22 端口在此被拒
```

→ **默认 Squid 拒绝 CONNECT 到 22**(因为 22 不在 `SSL_ports` 列表里)。

### 3.2 启用 SFTP 隧道(3 行改动)

来源:[Senior Linux Admin - SSH over Squid](https://www.seniorlinuxadmin.co.uk/ssh-over-proxy.html)

```squid
# /etc/squid/squid.conf(在 ACL 区域添加)
acl SSL_ports port 22          # 加上 SSH/SFTP 端口
acl Safe_ports port 22         # ssh/sftp(同上)

# 不需要改 http_access deny 规则 — 已有的 deny CONNECT !SSL_ports
# 现在 22 在 SSL_ports 列表里,自动放行
```

**关键点**:
- ✅ `acl SSL_ports port 22` — 允许 CONNECT 到 22 端口
- ✅ `acl Safe_ports port 22` — 允许直接访问(虽然 CONNECT 走 SSL_ports)
- ⚠️ **强烈建议加白名单**,不要"完全开放 22",只允许业务方目标 SFTP server IP:

```squid
# 推荐:白名单目标 SFTP server IP
acl sftp_servers dst 203.0.113.10 203.0.113.11    # 业务方 SFTP server IP 列表
acl sftp_ports port 22
http_access allow CONNECT sftp_ports sftp_servers

# 拒绝其他 22 端口(双保险)
acl other_ssh_port port 22
http_access deny CONNECT !SSL_ports     # 已有,兜底
http_access deny other_ssh_port !sftp_servers
```

### 3.3 重启 + 验证

```bash
# 语法检查
squid -k parse

# 重启(无中断 — 平滑重启)
systemctl reload squid
# 或
squid -k reconfigure

# 验证 Squid 接受 CONNECT 到 22
curl -v --proxytunnel -x http://www.def.com:3128 http://www.baidu.com
# 注意 —squid 默认只允许 HTTPS CONNECT,这里只是 smoke test
```

---

## 4. Nginx 配置改动(关键步骤)

### 4.1 默认 Nginx 行为(不支持 CONNECT)

Nginx 是 **reverse proxy**,默认**只接受 HTTP/HTTPS 客户端请求**,**不主动作为 forward proxy 转发 CONNECT method**。

业务方拓扑里 Nginx 在 Pod 和 Squid 中间:
- Pod → Nginx → Squid → 目标
- Pod 想要"过 Nginx 走 CONNECT 到 SFTP server"

→ **默认 Nginx 无法转发 CONNECT 请求**。

### 4.2 启用 CONNECT 转发(编译第三方模块)

来源:[chobits/ngx_http_proxy_connect_module](https://github.com/chobits/ngx_http_proxy_connect_module)(1.9k+ stars,工业成熟)

```nginx
# /etc/nginx/conf.d/saasp-forward-proxy.conf
server {
    listen 3128 ssl;

    # Nginx 服务端证书(如果客户端用 HTTPS 访问 Nginx)
    ssl_certificate     /etc/nginx/certs/nginx-fwd-proxy.crt;
    ssl_certificate_key /etc/nginx/certs/nginx-fwd-proxy.key;

    # DNS resolver 用于 forward proxying
    resolver 8.8.8.8;

    # 启用 CONNECT method 支持
    proxy_connect;
    proxy_connect_allow 443 22;    # 允许 CONNECT 到 443(HTTPS)和 22(SSH/SFTP)
    proxy_connect_connect_timeout 10s;
    proxy_connect_data_timeout 60s;

    # 非 CONNECT 请求(普通 HTTP/HTTPS):转发到 Squid
    location / {
        proxy_pass http://www.def.com:3128;     # 转发到 Squid
        proxy_set_header Host $host;
    }
}
```

### 4.3 编译 ngx_http_proxy_connect_module

⚠️ **这是一个 NDK 模块,需要从源码编译 Nginx**(不能动态加载)。

```bash
# 在 Nginx 源码目录
git clone https://github.com/chobits/ngx_http_proxy_connect_module.git

# 配置 Nginx(根据现版本)
./configure --add-module=./ngx_http_proxy_connect_module \
            --with-http_ssl_module

# 编译
make
make install

# ⚠️ 业务方 nginx 镜像如果是标准的(不是自己编译的),需要重建镜像
```

### 4.4 替代方案:绕过 Nginx,让 Pod 直接连 Squid

如果不想碰 Nginx(避免重建镜像 + 升级风险),**让 GKE Pod 绕过 Nginx,直接连 Squid**:

```
修改前:  Pod → Nginx:3128 → Squid:3128 → SFTP
修改后:  Pod → Squid:3128 → SFTP (绕过 Nginx)
```

客户端配置:
```bash
# sftp 命令
sftp -o ProxyCommand='nc -X connect -x www.def.com:3128 %h %p' user@sftp.example.com

# 或 ~/.ssh/config
Host sftp.example.com
    ProxyCommand    nc -X connect -x www.def.com:3128 %h %p
```

**架构师强观点**:
- ✅ **如果业务方 Pod 不需要 Nginx 做额外的 reverse proxy 能力,推荐绕过 Nginx** — 改动最小
- ❌ 如果业务方必须保留 Nginx(例如 Nginx 还做 path rewrite / 头注入),才用 §4.2 方案

---

## 5. 客户端配置(GKE Pod 内的 Java / sftp)

### 5.1 命令行 sftp 客户端 + nc

```bash
# 依赖:Debian/Ubuntu nc 需支持 -X connect(nc.openbsd 或 ncat)
apt-get install -y netcat-openbsd   # 或 ncat

# 临时测试
sftp -o ProxyCommand='nc -X connect -x www.def.com:3128 %h %p' \
     user@sftp.example.com

# ~/.ssh/config(永久)
Host sftp.example.com
    ProxyCommand    nc -X connect -x www.def.com:3128 %h %p
    ServerAliveInterval 10
```

来源:[Fedora Magazine - SSH proxy with Squid](https://fedoramagazine.org/configure-ssh-proxy-server/) + [Squid Users list 2017](https://ml-archives.squid-cache.org/squid-users/2017-April/014948.html)

### 5.2 Java 应用(常见场景)

```java
// JSch 示例(http://www.jcraft.com/jsch/)
import com.jcraft.jsch.*;

JSch jsch = new JSch();
ProxyHTTP proxy = new ProxyHTTP("www.def.com", 3128);
// 可选认证
// proxy.setUser("proxyuser");
// proxy.setPassword("proxypass");

Session session = jsch.getSession("user", "sftp.example.com", 22);
session.setConfig("StrictHostKeyChecking", "no");    // 生产应改为 yes
session.setProxy(proxy);
session.connect();

ChannelSftp sftp = (ChannelSftp) session.openChannel("sftp");
sftp.connect();
// ... 文件传输逻辑
```

### 5.3 Proxytunnel(替代 nc 的工具)

```bash
# 依赖
apt-get install -y proxytunnel

# 直接 ssh
ssh -o ProxyCommand='proxytunnel -p www.def.com:3128 -d %h:%p' user@sftp.example.com
```

---

## 6. 风险与合规

| # | 风险 | 严重度 | 说明 |
|---|---|---|---|
| R1 | **Squid 单点故障** | 高 | 所有 SFTP 流量经 Squid,Squid 挂 = SFTP 全断;Squid 应配集群 |
| R2 | **Squid 性能瓶颈** | 中 | CONNECT tunnel **不走缓存**,纯 TCP relay,可能比 HTTP proxy 更耗 CPU |
| R3 | **Squid 出口 IP 受限** | 高 | 业务方 SFTP server 可能**只允许特定 IP**;Squid 出口 IP 必须加白 |
| R4 | **审计盲区** | 中 | 业务方 Java 应用对 Squid 是"客户端",**Squid access_log 包含目标 host:port** 是唯一审计入口 |
| R5 | **SSH key / 密码 透明隧道** | 中 | SSH 协议在 TCP tunnel 里**不被代理解析**,Squid/Nginx **看不到** SSH 认证细节;只能看到 "client→sftp.example.com:22" 的连接 |
| R6 | **Nginx 重新编译** | 中 | 如果业务方坚持走 Nginx(§4.2),需要重建 nginx 镜像,运维成本 |
| R7 | **Squid 默认配置被替换风险** | 低 | 如果 Squid Admin 重启或 reload 时用了默认 conf,所有 22 端口被禁 |
| R8 | **业务方 SFTP server 白名单** | 高 | SFTP server 如果只允许特定 IP 段,Squid 出口 IP 必须加白,否则永远连不上 |

---

## 7. 待业务方/平台方确认的问题(Q&A)

| # | 问题 | 责任方 |
|---|---|---|
| Q1 | **Squid Admin** 是否愿意在 `squid.conf` 加 `acl SSL_ports port 22` 并重启? | Squid Admin |
| Q2 | **Squid Admin** 是否允许 SFTP 走**白名单 IP**(推荐),还是允许任意目标 22 端口? | Squid Admin |
| Q3 | **Nginx 维护方** 是否愿意编译 `ngx_http_proxy_connect_module` 并重建镜像?或者**允许绕过 Nginx 直接连 Squid**? | Nginx Admin |
| Q4 | **业务方** GKE Pod 是否能修改为"绕过 Nginx 直接连 Squid"?(`http_proxy` 环境变量或代码层配置)| 业务方 |
| Q5 | **业务方** 的 SFTP server owner 是否允许 **Squid 出口 IP** 连接?(防火墙 / sshd `AllowUsers` / `Match Address`) | SFTP server owner |
| Q6 | **业务方** SFTP 客户端是命令行(sftp / ssh)还是 Java 应用(JSch / Apache Commons VFS)? | 业务方 |
| Q7 | **业务方** 客户端是否需要走 mTLS(双客户端证书)到 SFTP server?如果需要,SSH 协议层走 SSH key,**与 mTLS 不冲突**(SSH 自带 client cert)| 业务方 |
| Q8 | **平台方** Squid 出口 IP 是多少?是否固定?是否在 NAT 之后? | 平台方 |

---

## 8. 架构师最终结论

### 8.1 可行性总判断

✅ **技术上完全可行**(被 Squid 官方文档 + 多家 Linux admin 资源 + Github ngx_http_proxy_connect_module 工业实践证实)。

### 8.2 业务方决策树

```
Q3: 是否愿意重建 Nginx 镜像?
├── 是 → 走 §4.2 方案(Nginx forward proxy + CONNECT module)
│         Pod → Nginx:3128 → Squid:3128 → SFTP
│
└── 否 → 走 §4.4 方案(绕过 Nginx,Pod 直接连 Squid) ← 推荐
          Pod → Squid:3128 → SFTP
```

### 8.3 实施 checklist(给到 infra-gcp)

- [ ] **Squid Admin**:修改 `squid.conf`,加 `acl SSL_ports port 22` + `acl Safe_ports port 22`(推荐加 IP 白名单)
- [ ] **Squid Admin**:`squid -k reconfigure` 平滑重启,确认 `access_log` 开始记录 SFTP CONNECT 请求
- [ ] **业务方**:客户端测试 `sftp -o ProxyCommand='nc -X connect -x www.def.com:3128 %h %p' user@sftp.example.com`
- [ ] **SFTP server owner**:加白 Squid 出口 IP
- [ ] **(可选)Nginx**:若要保留 Nginx 中间,编译 ngx_http_proxy_connect_module,改 nginx.conf
- [ ] **(可选)Java 应用**:用 JSch ProxyHTTP 类设置代理
- [ ] **平台方**:监控 Squid access_log,发现异常 SFTP 连接立即告警(审计要求)

### 8.4 架构师强观点

- ⚠️ **不要"为了一致性"保留 Nginx 中间**——如果业务方只是要"Pod 出去走 SFTP",**直接绕过 Nginx 连 Squid 更简单**。
- ⚠️ **Squid 出口 IP 必须在 SFTP server 白名单**——否则不管配什么都连不上(这是常见踩坑)。
- ⚠️ **审计**:**Squid access_log 是唯一能看到"Pod 在访问哪个 SFTP server"的入口**,日志保留期需符合合规要求。
- ⚠️ **mTLS 与 SFTP 不冲突**——SSH 自带 client cert(public key),如果业务方需要"双客户端证书",用 SSH key 就够了。

---

## 9. 已知未覆盖

| 主题 | 备注 |
|---|---|
| **SSH agent forwarding** | Pod 内的 ssh-agent 通过 CONNECT tunnel 是否需要额外配置 — 未测试 |
| **SSH multiplexing** | `ControlMaster` 多路复用 SSH 连接,可能与 CONNECT tunnel 冲突 — 未验证 |
| **SFTP server 端审计** | SFTP server 是否记录 sshd 连接日志,需业务方另行确认 |
| **Squid access_log 字段** | 需确认日志格式包含 client IP / target host:port / auth 用户 — 字段可能因 Squid 版本不同 |
| **IPv6 路径** | Squid 默认 `acl SSL_ports port 22` 是 IPv4+IPv6 双栈,但 ACL `dst` 需 IPv6 字面量 |

---

**作者备注**:2026-09-06 v1.0。本文档只覆盖"可行性 + 配置 + 风险",**不写具体 conf 文件**(那是 infra-gcp lane)。业务方答复 §7 8 个问题后,可推进实施。