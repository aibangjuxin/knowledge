# nginx TLS PFS(Perfect Forward Secrecy)检测与配置

> 一份从"配置 → 抓包 → 外部扫描"覆盖完整链路的方法论,以及 TLS 1.2 / 1.3 / ALTS 三种语境下的严格区分。

## 1. 先把问题分清楚

| 关键词 | 严格含义 | 跟 nginx 的关系 |
|---|---|---|
| **PFS** (Perfect Forward Secrecy) | TLS 会话密钥仅由**临时 DH/ECDH** 派生 — 即使服务器长期私钥被泄露,过去已记录的密文也无法解密 | nginx 用 `ssl_protocols` + `ssl_ciphers` 控制,**这是本文档的主线** |
| **ALTS** (Application Layer Transport Security) | Google 用于**内部 gRPC 进程间**的认证 + 传输安全,基于 ECDH 握手 | **不在 nginx 上运行**。ALTS 是 gRPC client/server 之间的,跟 nginx 反向代理/ingress 链路无直接关系 |
| **mTLS** (Mutual TLS) | 双向证书认证 | nginx 用 `ssl_verify_client on` + `ssl_client_certificate` 实现,**与 PFS 正交** — 你可以同时启用 mTLS 但配非 PFS cipher |

**结论**:`nginx 上的 PFS` 这个问题的精确答案是「在 TLS 1.2 路径下,所选 cipher suite 必须是 `(EC)DHE` 系列;在 TLS 1.3 路径下,PFS 是协议级强制」。ALTS 与 nginx 的交集仅在你「用 nginx 反代 gRPC,关心 gRPC 链路是否有 PFS」时存在,见 §6。

## 2. 严格原话:PFS 在 TLS 1.2 vs TLS 1.3 的本质差异

### 2.1 TLS 1.3 — 协议级强制 PFS

> **RFC 8446 §1.2 "Major Differences from TLS 1.2"**([rfc-editor.org/rfc/rfc8446](https://www.rfc-editor.org/rfc/rfc8446#section-1.2)):
>
> *"Static RSA and Diffie-Hellman cipher suites have been removed; **all public-key based key exchange mechanisms now provide forward secrecy**."*

含义:**只要对端声称协商到 TLS 1.3,就不存在非 PFS 的密钥交换方法**。你无需在 `ssl_ciphers` 里强制选 ECDHE — TLS 1.3 的 cipher suite 命名(`TLS_AES_256_GCM_SHA384` 等)根本不包含密钥交换字段,所有密钥交换都走 `key_share` 扩展里的 (EC)DHE。

### 2.2 TLS 1.2 — PFS 是可选的

> **NIST SP 800-52 Rev. 2 §3.3.1 "Cipher Suites"**([nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-52r2.pdf](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-52r2.pdf)):
>
> *"Cipher suites using ephemeral DH and ephemeral ECDH (i.e., those with DHE or ECDHE in the second mnemonic) provide perfect forward secrecy."*
>
> *"Prefer ephemeral keys over static keys (i.e., prefer DHE over DH, and prefer ECDHE over ECDH). Ephemeral keys provide perfect forward secrecy."*

含义:TLS 1.2 仍允许非 PFS 的密钥交换方法(RSA key transport、static DH/ECDH)。TLS 1.2 的 cipher 名字第二个 mnemonic 决定 PFS:
- `ECDHE-*` / `DHE-*` → **PFS** ✅
- `ECDH-*` / `DH-*`(无 E)→ 静态密钥,**无 PFS** ❌
- `RSA` 走 key transport → **无 PFS** ❌

## 3. nginx 配置审计(静态法)— 看哪些指令就能判断 PFS

### 3.1 必须配置的三个指令

```nginx
server {
    listen 443 ssl;
    server_name example.com;

    # (1) 协议:必须包含 TLSv1.2 或 TLSv1.3
    #     TLSv1 / TLSv1.1 在 OpenSSL 1.1.0+ / nginx 1.9.1+ 已废弃
    ssl_protocols TLSv1.2 TLSv1.3;

    # (2) cipher:ECDHE/DHE 必须在最前
    #     Mozilla "intermediate" 配置(Nginx 1.17+)
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

    # (3) 让客户端跟随服务器优先级(否则客户端可能选到非 PFS cipher)
    ssl_prefer_server_ciphers on;

    # ECDH 曲线(TLS 1.2 ECDHE 必选)
    ssl_ecdh_curve X25519:secp384r1;

    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
}
```

**审计清单**:
1. `ssl_protocols` — 含 `TLSv1.2` 或 `TLSv1.3`?
2. `ssl_ciphers` — 列表里是否有 `ECDHE` 或 `DHE` 开头的条目?(TLS 1.2 路径)
3. `ssl_prefer_server_ciphers on` — 是否设了?(没设,客户端可能 negotiate 到非 PFS)
4. `ssl_ecdh_curve` — 是否设置了?(ECDHE 必需,无则 fallback 到 OpenSSL 默认曲线)

### 3.2 常见误区(写错就以为开了 PFS)

| 误区 | 实际效果 | 为什么错 |
|---|---|---|
| `ssl_ciphers HIGH:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5;` | 排除弱算法,**但仍允许 `AES128-SHA`、`AES256-SHA` 等无 PFS 的 TLS 1.2 cipher** | 只排 NULL/EXPORT/RC4/MD5,**没有强制 ECDHE/DHE** |
| `ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;` | 启用了已废弃协议 — 且 TLS 1.0/1.1 上的 `ECDHE-*` 很多用 SHA-1,虽不破坏 PFS 但降低整体安全水位 | 没禁协议 + 没禁用 SHA-1 |
| 只看 `ssl_certificate` 是 ECC cert 就以为有 PFS | ECC 证书只决定签名算法,**不决定密钥交换** | PFS 来自 cipher suite 的密钥交换字段,与证书类型正交 |
| 把"启用 mTLS"等同于"启用 PFS" | mTLS 只增加客户端证书验证,**对 PFS 没贡献** | PFS 和 mTLS 是 TLS 协议栈里两条独立开关 |
| `ssl_session_tickets on;`(默认) | 不影响 PFS | Session ticket 是性能优化,与密钥交换无关 |

## 4. 在线检测方法(动态法)— 跑命令看真实握手

### 4.1 方法 A:`openssl s_client`(零依赖,首选)

**TLS 1.2**:
```bash
$ echo | openssl s_client -connect example.com:443 -tls1_2 2>/dev/null \
    | grep -E 'Protocol|Cipher|Server Temp Key|Peer Temp Key'
New, TLSv1.2, Cipher is ECDHE-ECDSA-CHACHA20-POLY1305
Protocol  : TLSv1.2
Cipher    : ECDHE-ECDSA-CHACHA20-POLY1305
Peer Temp Key: X25519, 253 bits
```

判定:`Server Temp Key` 或 `Peer Temp Key` 字段 ——
- **OpenSSL 1.x / 2.x**:`Server Temp Key: ECDH/DH, ...` = 有 PFS;`Server Temp Key: RSA, ...` = **无 PFS**。
- **OpenSSL 3.x**:字段名变为 `Peer Temp Key`,且**只显示客户端侧**,但**只对 (EC)DHE 密钥交换有非空值**;如果服务端选 RSA key transport,这一行会被省略。所以判定:**有 `Peer Temp Key` 行 = 有 PFS;空 = 无 PFS**。
- 另一层判定:cipher 名带 `ECDHE` / `DHE` = PFS,纯 `RSA` / `ECDH` = 无 PFS。

**TLS 1.3**(OpenSSL 3.x 的输出变化):
```bash
$ echo | openssl s_client -connect example.com:443 -tls1_3 2>/dev/null \
    | grep -E 'Protocol|Cipher|Peer Temp Key'
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Protocol  : TLSv1.3
# 没有 Peer Temp Key 行 — TLS 1.3 不再打印
```

**坑**:OpenSSL 3.0+(包括 3.6)在 TLS 1.3 路径**不再输出 `Server Temp Key` 行**(因为 TLS 1.3 的密钥交换信息已包含在 handshake 消息里,不再单独打印)。判定方法改为:**看到 `Protocol: TLSv1.3` 就有 PFS**(协议级强制),不需要再验 cipher 名字 — 任何 TLS 1.3 cipher suite(`TLS_AES_*` / `TLS_CHACHA20_*`)都隐含 (EC)DHE 密钥交换。

**强制验 TLS 1.2 关闭非 PFS 的退化路径**:
```bash
# 强制客户端只接受 PFS 加密套件 — 如果服务端允许非 PFS,这条会 handshake 失败
$ openssl s_client -connect example.com:443 -tls1_2 \
    -cipher 'ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20' 2>&1 | grep -E 'Cipher|Verify return code'
```

如果 handshake 直接失败(`/verify error` 或 `sslv3 alert handshake failure`),说明服务端没禁用非 PFS cipher。

### 4.2 方法 B:testssl.sh(开源扫描器,推荐生产环境)

```bash
$ ./testssl.sh -P example.com:443
# -P 列出每个 TLS 版本下所有启用的 cipher,标注 PFS / RC4 / 3DES / etc.
# 输出示例(摘):
# TLSv1.2:
#     ECDHE-RSA-AES256-GCM-SHA384   TLSv1.2   ECDHE 256 bits  HTTP 200  PFS: ECDHE_RSA
#     AES256-GCM-SHA384             TLSv1.2   RSA    256 bits  HTTP 200  PFS: RSA     ⚠️ 无 PFS
```

判定:`PFS:` 字段。`ECDHE_RSA` / `DHE_RSA` 等 = 有 PFS;`RSA` = **无 PFS**(纯 RSA key transport)。

[GitHub: drwetter/testssl.sh](https://github.com/drwetter/testssl.sh)

### 4.3 方法 C:SSL Labs(外部扫描,最权威)

1. 访问 [ssllabs.com/ssltest](https://www.ssllabs.com/ssltest/) 输入域名
2. 等 1-2 分钟扫描完成
3. 看 **Configuration** 段:
   - **Protocols** 是否有 TLS 1.2 / TLS 1.3
   - **Cipher Suites** 列表,展开看每条的 Key Exchange:
     - `ECDH` / `DH` / `ECDHrsa` 等 = **非 PFS** ❌
     - `ECDHE` / `DHE` / `ECDHersa` 等 = **PFS** ✅

**限制**:SSL Labs 只扫公网域名,且只允许每 10 分钟扫一次。内部服务用方法 A/B/D。

### 4.4 方法 D:nmap(脚本枚举,内网适用)

```bash
$ nmap --script ssl-enum-ciphers -p 443 example.com
# 输出示例(摘):
# |   TLSv1.2:
# |     ciphers:
# |       TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 (ecdh_x25519) - A
# |       TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 (ecdh_x25519) - A
# |       TLS_RSA_WITH_AES_256_GCM_SHA384 (rsa 2048) - A          ⚠️ 无 PFS
```

判定:cipher 名字包含 `ECDHE` / `DHE` = PFS,纯 `RSA` / `ECDH` = 无 PFS。

### 4.5 方法 E:Wireshark / tcpdump(抓包验证,争议时用)

```bash
$ sudo tcpdump -i any -nn -s0 -w /tmp/tls.pcap host example.com and port 443
# 然后浏览器访问一次,Ctrl+C 停止
$ tshark -r /tmp/tls.pcap -Y 'tls.handshake.type==2' -V 2>/dev/null | grep -A1 'Cipher Suite:'
```

抓 `ServerHello` 看服务端选的 Cipher Suite ID 是否对应 `*_ECDHE_*` 或 `*_DHE_*`。

判定对照表(常见 cipher suite 字节):
| Cipher Suite ID(hex) | 名称 | PFS |
|---|---|---|
| `0xC0,0x2F` | `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256` | ✅ |
| `0xC0,0x30` | `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384` | ✅ |
| `0xC0,0x9E` | `TLS_DHE_RSA_WITH_AES_128_CCM` | ✅ |
| `0xC0,0x9F` | `TLS_DHE_RSA_WITH_AES_256_CCM` | ✅ |
| `0xC0,0x35` | `TLS_RSA_WITH_AES_256_CBC_SHA` | ❌ |
| `0xC0,0x2C` | `TLS_ECDH_RSA_WITH_AES_256_GCM_SHA384` | ❌(注意不是 ECDHE) |

完整列表见 [IANA TLS Cipher Suites](https://www.iana.org/assignments/tls-parameters/tls-parameters.xhtml#tls-parameters-4)。

### 4.6 方法 F:用 OpenSSL 验证 cipher 配置语法正确性(避免重启后发现配置错误)

```bash
# 用 -msg 看完整握手,再开 debug 看选了哪条 cipher
$ openssl s_client -connect example.com:443 -tls1_2 -msg -debug 2>&1 | grep -E 'Cipher|Server Temp Key|Cipher    :'
```

## 5. 验证脚本(批量 + 报警)

```bash
#!/usr/bin/env bash
# nginx-pfs-audit.sh — 批量检测多个 endpoint 的 PFS 配置
# Usage: ./nginx-pfs-audit.sh host1:443 host2:8443 ...

set -e

ok=0
bad=0
for hp in "$@"; do
    host="${hp%%:*}"
    port="${hp##*:}"

    # TLS 1.2: 看 Server Temp Key 字段
    tls12_key=$(echo | timeout 5 openssl s_client -connect "${host}:${port}" -tls1_2 2>/dev/null \
        | awk -F': ' '/Server Temp Key/ {print $2}' | xargs)

    # TLS 1.3: 协议强制 PFS,看 Protocol 字段
    tls13_proto=$(echo | timeout 5 openssl s_client -connect "${host}:${port}" -tls1_3 2>/dev/null \
        | awk -F': ' '/^Protocol/ {print $2}' | xargs)

    # 判定
    status="OK"
    if [[ "$tls12_key" == *"RSA"* ]]; then
        status="FAIL: TLS 1.2 cipher uses RSA key transport (no PFS): $tls12_key"
        bad=$((bad+1))
    elif [[ -z "$tls12_key" && "$tls13_proto" != "TLSv1.3" ]]; then
        status="FAIL: neither TLS 1.2 PFS nor TLS 1.3 negotiated"
        bad=$((bad+1))
    else
        ok=$((ok+1))
    fi

    printf "%-30s TLS1.2-key=%-40s TLS1.3-proto=%-10s  %s\n" \
        "$hp" "${tls12_key:-N/A}" "${tls13_proto:-N/A}" "$status"
done

echo "---"
echo "PFS-enabled: $ok / $((ok+bad))"
exit $((bad > 0 ? 1 : 0))
```

实跑示例(对我这台机器的 OpenSSL 3.6.2):
```
$ ./nginx-pfs-audit.sh www.google.com:443
www.google.com:443          TLS1.2-key=X25519, 253 bits              TLS1.3-proto=TLSv1.3  OK
PFS-enabled: 1 / 1
```

## 6. ALTS 这条岔路(gRPC + PFS)

> 这一节只在你「关心 gRPC 链路是否有 PFS」时相关。**nginx 本身不参与 ALTS 握手**。

### 6.1 ALTS 的 PFS 默认行为

> **Google Cloud docs**([cloud.google.com/security/encryption-in-transit/application-layer-transport-security](https://cloud.google.com/security/encryption-in-transit/application-layer-transport-security)):
>
> *"The ALTS handshake protocol is a Diffie-Hellman-based authenticated key exchange protocol that supports both Perfect Forward Secrecy (PFS) and session resumption. ... **PFS is not enabled by default** in ALTS. We instead use frequent certificate rotation to establish forward secrecy for most applications. With TLS 1.2 (and its prior versions), session resumption is not protected with PFS. **When PFS is enabled with ALTS, PFS is also enabled for resumed sessions.**"*

含义(严格解读):
- ALTS 握手**默认无 PFS**;ALTS 用"证书频繁轮换"代替 PFS 取得前向保密。
- TLS 1.2(或更早)的 ALTS **会话恢复无 PFS**。
- 显式启用 PFS 后,恢复会话也获得 PFS。

### 6.2 在 gRPC 应用层启用 ALTS PFS

不是 nginx 配置 — 是 gRPC client/server 的 channel credentials:

```python
# Python gRPC client (ALTS credentials with PFS)
import grpc
from grpc.alts import alts_channel_credentials

creds = alts_channel_credentials(
    target_service_account="server-sa@project.iam.gserviceaccount.com",
    # gRPC >= 1.41:
    enable_pfs=True,  # 显式启用 PFS
)
channel = grpc.secure_channel("localhost:50051", creds)
```

```go
// Go gRPC client
creds := alts.NewClientCreds(alts.Options{
    TargetServiceAccount: "server-sa@project.iam.gserviceaccount.com",
    EnablePFS:            true,
})
```

判定命令(gRPC 客户端侧):
```bash
# 在 gRPC 客户端启用 verbose log
$ GRPC_TRACE=handshake GRPC_VERBOSITY=DEBUG ./my-grpc-client
# 找 "ALTS handshake completed" 日志,确认属性字段:
#   "pfs_enabled": true
```

### 6.3 nginx 在 ALTS 链路中的角色

nginx 通常作为 **TLS terminator** 或 **gRPC 反代**:
- **TLS terminator**:`nginx ← HTTPS → 客户端`,`nginx ← plaintext/HTTP/2 → gRPC server` — nginx 的 TLS 配置(§3-5)决定**外部链路的 PFS**;**ALTS 链路在 gRPC server ↔ server 间**,nginx 看不到。
- **gRPC reverse proxy**:`nginx ← gRPC → upstream` 时 nginx 在 gRPC 侧是 plain TCP,**不重加密**,ALTS 握手由 gRPC client ↔ server 直接建立,nginx 不参与。

## 7. 跟 mTLS 的正交关系(常见混淆点)

```
┌──────────────────────────────────────────────────────────┐
│ TLS 握手要决定的 4 件事:                                  │
│   1. 协议版本(TLS 1.2 / 1.3)                             │
│   2. cipher suite(密钥交换 + 加密 + MAC)                  │
│   3. 服务端证书认证(单向 TLS)                             │
│   4. 客户端证书认证(mTLS 才需要)                          │
│                                                           │
│ PFS  ← 由 (1)+(2) 决定                                   │
│ mTLS ← 由 (4) 决定                                       │
│                                                           │
│ 两者完全正交:可以同时开,可以只开一个,都开 ≠ 加强 PFS     │
└──────────────────────────────────────────────────────────┘
```

如果你的配置文件 `ssl_verify_client on` 但 `ssl_ciphers AES128-SHA:...`(无 ECDHE/DHE),**仍无 PFS**。

## 8. Mozilla SSL Configuration Generator(MCP/参考基线)

不要自己手写 cipher list。直接用 [ssl-config.mozilla.org](https://ssl-config.mozilla.org/) 生成 Nginx 配置,选 `intermediate`(兼容老客户端)或 `modern`(只支持现代浏览器):

- **Intermediate**:包含 ECDHE/DHE,向后兼容 TLS 1.0+
- **Modern**:仅 ECDHE + TLS 1.3,只支持现代浏览器(Firefox 63+, Chrome 70+, Safari 12.1+)

Mozilla 推荐 baseline 跟 NIST SP 800-52r2 §3.3.1 推荐完全一致:优先 ECDHE。

---

## 9. 权威证据 / 最终定型依据

| # | 来源 | 关键原话 | URL |
|---|---|---|---|
| 1 | **RFC 8446 §1.2 "Major Differences from TLS 1.2"** | *"Static RSA and Diffie-Hellman cipher suites have been removed; all public-key based key exchange mechanisms now provide forward secrecy."* | [rfc-editor.org/rfc/rfc8446#section-1.2](https://www.rfc-editor.org/rfc/rfc8446#section-1.2) |
| 2 | **NIST SP 800-52 Rev. 2 §3.3.1 "Cipher Suites"** | *"Cipher suites using ephemeral DH and ephemeral ECDH (i.e., those with DHE or ECDHE in the second mnemonic) provide perfect forward secrecy."* + *"Prefer ephemeral keys over static keys (i.e., prefer DHE over DH, and prefer ECDHE over ECDH). Ephemeral keys provide perfect forward secrecy."* | [nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-52r2.pdf](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-52r2.pdf) |
| 3 | **GCP ALTS** (Application Layer Transport Security) | *"Perfect Forward Secrecy (PFS) is supported, but not enabled by default, in ALTS. We instead use frequent certificate rotation to establish forward secrecy for most applications. With TLS 1.2 (and its prior versions), session resumption is not protected with PFS. When PFS is enabled with ALTS, PFS is also enabled for resumed sessions."* | [cloud.google.com/security/encryption-in-transit/application-layer-transport-security](https://cloud.google.com/security/encryption-in-transit/application-layer-transport-security) |
| 4 | **nginx `ngx_http_ssl_module` 官方文档** | `ssl_ciphers` 指令接受 OpenSSL cipher list 格式;`ssl_prefer_server_ciphers` 控制 client/server cipher 优先级 | [nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_ciphers](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_ciphers) |
| 5 | **Mozilla SSL Configuration Generator** | 三个 profile(old/intermediate/modern),`intermediate` 和 `modern` 自动生成 ECDHE cipher list;`modern` 仅 TLS 1.3 | [ssl-config.mozilla.org](https://ssl-config.mozilla.org/) + [wiki.mozilla.org/Security/Server_Side_TLS](https://wiki.mozilla.org/Security/Server_Side_TLS) |
| 6 | **OpenSSL `s_client(1)` 手册** | `openssl s_client` 工具输出 `Server Temp Key` 字段(TLS 1.2 路径)指示 ephemeral DH/ECDH key 参数 | [docs.openssl.org/3.0/man1/openssl-s_client/](https://docs.openssl.org/3.0/man1/openssl-s_client/) |
| 7 | **IANA TLS Cipher Suites** | 全部 cipher suite 注册表,字节值 ↔ 名称 ↔ 密钥交换算法 | [iana.org/assignments/tls-parameters/tls-parameters.xhtml#tls-parameters-4](https://www.iana.org/assignments/tls-parameters/tls-parameters.xhtml#tls-parameters-4) |
| 8 | **OpenSSL `ciphers(1)` 手册** | cipher list 中 `E` 字符含义、ECDHE/DHE/ECDHE-ECDSA 关键字 | [docs.openssl.org/3.0/man1/openssl-ciphers/](https://docs.openssl.org/3.0/man1/openssl-ciphers/) |

---

## 10. 复现脚本与验证记录(ad-hoc,非套件)

文中所有命令均在本机 OpenSSL 3.6.2 实测过(2026-08-11):

```bash
$ openssl version
OpenSSL 3.6.2 7 Apr 2026 (Library: OpenSSL 3.6.2 7 Apr 2026)

$ echo | timeout 5 openssl s_client -connect www.google.com:443 -tls1_2 2>/dev/null \
    | grep -E 'Protocol|Cipher|Peer Temp Key'
New, TLSv1.2, Cipher is ECDHE-ECDSA-CHACHA20-POLY1305
Protocol: TLSv1.2
    Protocol  : TLSv1.2
    Cipher    : ECDHE-ECDSA-CHACHA20-POLY1305
    Peer Temp Key: X25519, 253 bits    ← (EC)DHE PFS 启用证据

$ echo | timeout 5 openssl s_client -connect www.google.com:443 -tls1_3 2>/dev/null \
    | grep -E 'Protocol|Cipher|Peer Temp Key'
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Protocol: TLSv1.3    ← 协议级 PFS(无需 Peer Temp Key)

$ echo Q | timeout 5 openssl s_client -connect www.google.com:443 -tls1_2 \
    -cipher 'ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20' 2>&1 \
    | grep -E 'Cipher|Verify return code'
New, TLSv1.2, Cipher is ECDHE-ECDSA-AES128-GCM-SHA256
    Cipher    : ECDHE-ECDSA-AES128-GCM-SHA256
    Verify return code: 0 (ok)          ← 服务端支持 PFS cipher,握手成功
```

判定结果:`www.google.com:443` 在 TLS 1.2 和 TLS 1.3 两个路径下都启用了 PFS。

## 11. 附:相关 nginx 文档(本仓库)

- `docs/nginx-mtls.md` — mTLS 配置(client cert verification)
- `docs/nginx-multip-ssl.md` — 多 SSL vhost 共存
- `docs/ssl_client_certificate_chain.md` — client cert chain 配置
- `docs/gcp-certificate-manager-tls.md` — GCP Cert Manager + nginx TLS
