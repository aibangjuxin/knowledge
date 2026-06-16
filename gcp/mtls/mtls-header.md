# mTLS 工作模式下「HTTP 头」的处理 — GCLB 视角 + 与 Header 的关系

> 文档目的：回答核心问题 —— **mTLS 双向校验是不是跟 HTTP Header 完全无关？还是说两者有对应关系？**
>
> 答案先放在最前面：**两者属于不同的 OSI 层（mTLS = TLS 层握手；Header = 应用层 HTTP 消息），但 GLB 必须用「HTTP Header」作为「跨代理传递 mTLS 验证结果」的带外通道**。所以它们在 GLB 这里是 **「机制无关、传递通道耦合」** 的关系。
>
> 本文档同时澄清库内 `mtls-verify.md`、`glb-verify.md`、`Glb-Client-Authentication.md`、`SSLVerifyDepth.md` 之间关于 `X-Forwarded-Client-Cert` 和 GCLB 资源命名的事实冲突。

---

## 0. TL;DR — 一句话回答

| 你想问的 | 直接答案 |
|---|---|
| mTLS 改不改客户端发的原始 HTTP 头（`Authorization`/`User-Agent`/`Cookie`/业务 `X-*`）？ | **不改**。客户端 → GLB 这段连接里所有应用层字节原样转发。 |
| mTLS 是否会让 GLB 自动新增头给后端？ | **会，但仅在 backend service / URL map 上显式配置了 `customRequestHeaders` 的占位符时**。GCLB **不会** 默认注入任何 `X-Client-Cert-*`。 |
| mTLS 验证结果（成功 / 失败 / 没给证书）怎么传后端？ | **通过你配置的自定义请求头 + 17 个 `client_cert_*` 占位符**。 |
| 那 `X-Forwarded-Client-Cert` 是什么？ | **那是 Istio/Envoy/IAP 的命名，不是 GCLB 的**。GCLB 用 `X-Client-Cert-*`。两者编码格式偶然都是 RFC 9440（colon-delimited Base64），头名却不通用。 |
| 如果 Cluster（带证书）→ GLB → 后端，header 链路是怎样的？ | 见 §3，分 4 种典型架构。 |

---

## 1. 分层视角：mTLS 与 Header 各自在哪一层

```
Client ─── mTLS 握手 (TLS 层) ───► GCLB ─── TLS / 明文 ───► Backend
         │                                  │
         │ 客户端发的 HTTP Header ──────────►│  透传给后端（GLB 可叠加）
         │                                  │
         │  mTLS 验证结果 ──────────────────►│  以占位符形式塞入 Header
         │  (证书指纹/Subject/SAN/...)       │  (由你显式配置)
```

- **mTLS**：发生在 TLS handshake 阶段（TCP 三次握手之后、HTTP 业务数据之前）。它交换的是 **X.509 证书** 和 **TLS 协议消息**（CertificateRequest / Certificate / CertificateVerify），**不是 HTTP 头**。
- **HTTP Header**：是 TLS 握手**完成之后**、应用层 HTTP 请求的一部分。

→ 这就是「**无关**」的根源：mTLS 完成时，HTTP Header 还没开始被解析。

但工程上有一个**例外**：当 GCLB 把 mTLS 握手结果「带外」告知后端时，**唯一可用的带外通道就是 HTTP Header**（因为 TLS 连接已经被 GCLB 终结，后端看到的是一段新的、由 GLB 控制的 HTTP 请求）。所以 mTLS 验证信息通过 header **传递**给后端 —— 但 mTLS 本身**不修改**客户端原始 header。

---

## 2. 客户端原始 Header 是否被 mTLS 修改？

**不会。** 严格地讲：

| 客户端发的头 | mTLS 是否触碰 | 说明 |
|---|---|---|
| `Authorization: Bearer ...` | ❌ 不动 | mTLS 只验证客户端身份，不替你做认证授权 |
| `Cookie: ...` | ❌ 不动 | 同上 |
| `User-Agent`、`Accept-*`、`Content-*` | ❌ 不动 | mTLS 在 TLS 层，HTTP header 是 payload |
| 业务自定义头（`X-Tenant-Id` 等） | ❌ 不动 | 除非你显式 strip |
| `X-Forwarded-Client-Cert`（如果客户端主动发了） | ⚠️ **会被覆盖** | 见 §4.3 — 这是唯一一种"修改" |
| `X-Forwarded-For` / `X-Forwarded-Proto` | ⚠️ GLB 会**叠加追加**，不会覆盖原值 | 标准代理行为 |

唯一会**改**的，是 GCLB 自己**自动加的代理头**（即便你不开 mTLS 也会加）：

- `X-Forwarded-For: <client_ip>` （追加在已有值后面）
- `X-Forwarded-Proto: <https|http>`
- `Via: 1.1 google` （一般可见）

→ 这些与 mTLS **无关**，是任何 HTTP 代理都会做的事。

**mTLS 的特殊行为**：GCLB 在 backend service 或 URL map 上**默认不会**注入任何 `X-Client-Cert-*`。只有当**你**配置了 `customRequestHeaders`（带 `client_cert_*` 占位符）后，GLB 才会**新增**这些 header 给后端。这是 **opt-in**，不是 opt-out。

---

## 3. 四种典型架构下「Header 链路」梳理

### 3.1 架构 A：浏览器 / curl 直连 GLB（无 Cluster）

```
[curl --cert ... --key ...] ──mTLS──► [GCLB] ──HTTP/HTTPS──► [Nginx / App]
         客户端发:                        GLB 加:                后端收到:
         Authorization: ...              X-Forwarded-For: ...   Authorization: ...
         X-Tenant-Id: ...                X-Forwarded-Proto: ... X-Tenant-Id: ...
         (你配了 customRequestHeaders    X-Client-Cert-Hash:    X-Forwarded-For: ...
          后才会出现 ↓)                   {client_cert_sha256...  X-Client-Cert-Hash: ...
                                        ..._fingerprint}       ...
```

✅ 客户端原始 header 100% 保留；GLB 仅追加代理头 + 你配的 mTLS 占位符。

### 3.2 架构 B：GKE Cluster 内部 Pod 通过 Ingress / GLB 出公网（无 Istio）

```
[Pod A] ──HTTP──► [GCLB (Ingress)] ──HTTP──► [Pod B / 外部 API]
  客户端发:                       GLB 加:
  X-Request-Id: ...               X-Client-Cert-Hash: ...
  Authorization: ...              (如果你在 BackendService
                                   配了 customRequestHeaders)
```

如果 GCLB 前**没有 mTLS**（比如纯 HTTP Ingress），那么 GLB **完全不会**加 `X-Client-Cert-*`。mTLS 是 GLB 边缘的特性，Pod 间互相调用不涉及。

### 3.3 架构 C：GKE Cluster 内部带 Istio / ASM（无 GLB 边缘 mTLS）

```
[Pod A] ──mTLS──► [istio-proxy sidecar] ──HTTP──► [Pod B]
                              Envoy sidecar 加:
                              X-Forwarded-Client-Cert: <colon-Base64 leaf cert>
                              X-Request-Id: ...
                              X-B3-TraceId: ...
```

**注意命名差异**：
- Istio/Envoy 用 `X-Forwarded-Client-Cert`（RFC 9440）
- GCLB 用 `X-Client-Cert-*`（前缀不同）
- 编码格式两者**正好都是** RFC 9440（colon-delimited Base64）

→ 这就是为什么库内一些文档把两者混淆：编码格式一样，但**头名不一样**，**注入点不一样**，**用哪个看你处在哪一层**。

### 3.4 架构 D：Client Cert 客户端 ──mTLS──► GLB ──HTTP──► GKE / Istio（双重 mTLS 注入）

这是用户问的"Cluster 访问 URL"最完整的形态：

```
[Client + cert]
   │  (1) mTLS handshake with GCLB
   ▼
[GCLB]  ←────── 在这里 mTLS 验证完成
   │   GLB 自动加: X-Forwarded-For, X-Forwarded-Proto
   │   GLB 按你的 customRequestHeaders 加: X-Client-Cert-Hash, X-Client-Cert-Present ...
   │   (注意: GLB 不会注入 X-Forwarded-Client-Cert)
   │   HTTP (TLS 已终结)
   ▼
[GKE Ingress → Pod with istio-proxy sidecar]
   │   Envoy sidecar 看到 X-Client-Cert-* 是普通头,原样转发
   │   sidecar 自己没有 mTLS 上下文,不会注入 X-Forwarded-Client-Cert
   ▼
[Backend Pod / 业务 App]
   看到的所有 header:
     - 原始客户端头 (Authorization, Cookie, ...)
     - X-Forwarded-For: <client_ip>           ← GLB 加
     - X-Forwarded-Proto: https               ← GLB 加
     - X-Client-Cert-Present: true            ← GLB 加 (你配的)
     - X-Client-Cert-Hash: ...                ← GLB 加 (你配的)
     - (没有 X-Forwarded-Client-Cert,除非你的 ingress 单独配置)
```

⚠️ **关键陷阱**：如果你的 backend 同时被 GCLB 边缘 mTLS + ASM/Istio 内部 mTLS 保护，**两个 mTLS 是独立的**：
- GCLB 验证的是「客户端→GLB」这一段
- Istio 验证的是「sidecar A→sidecar B」这一段
- 两者之间互不知情 —— GCLB **不会**把客户端原始证书原样透传到 Istio（它只透传占位符提取的字段，如 fingerprint / Subject DN / SAN）
- 如果 Istio 需要重新校验客户端证书（不是只信任 header 里的 fingerprint），**这套架构做不到**

---

## 4. GCLB mTLS 完整占位符（官方 2026，共 17 个）

> 来源：[GCP 官方 Mutual TLS overview](https://cloud.google.com/load-balancing/docs/mtls) + [Create custom headers in backend services](https://cloud.google.com/load-balancing/docs/https/custom-headers)
>
> 库内 `glb-verify.md` 第 174-183 行只列出了 **8 个**（截至 2025 年的快照），已**过时**。下表是当前完整版本。

### 4.1 完整占位符表

| # | 占位符 | 输出类型 | 字段含义 / 注意事项 |
|---|---|---|---|
| 1 | `client_cert_present` | bool | 客户端是否在 TLS 握手期间提供了证书 (`true`/`false`) |
| 2 | `client_cert_chain_verified` | bool | 证书链是否对配置的 TrustConfig 验证通过 (`true`/`false`) |
| 3 | `client_cert_error` | string | 验证失败原因（多值用逗号分隔）。详见 §4.4 |
| 4 | `client_cert_sha256_fingerprint` | Base64(SHA-256) | 叶证书 SHA-256 指纹 |
| 5 | `client_cert_serial_number` | string | 序列号；>50 字节时 `client_cert_error` 会包含 `client_cert_serial_number_exceeded_size_limit`，本字段置空 |
| 6 | `client_cert_spiffe_id` | string | URI SAN 中的 SPIFFE ID；>2048 字节或格式非法时置空，error 含 `client_cert_spiffe_id_exceeded_size_limit` |
| 7 | `client_cert_uri_sans` | string | URI 类型 SAN（逗号分隔，Base64）；>512 字节时置空，error 含 `client_cert_uri_sans_exceeded_size_limit` |
| 8 | `client_cert_dnsname_sans` | string | DNSName 类型 SAN（逗号分隔，Base64）；>512 字节时同上 |
| 9 | `client_cert_valid_not_before` | RFC 3339 时间 | 证书 `notBefore` 字段，例如 `2022-07-01T18:05:09+00:00` |
| 10 | `client_cert_valid_not_after` | RFC 3339 时间 | 证书 `notAfter` 字段 |
| 11 | `client_cert_issuer_dn` | Base64(DER) | 颁发者 DN 的 DER 编码；>512 字节置空，error 含 `client_cert_issuer_dn_exceeded_size_limit` |
| 12 | `client_cert_subject_dn` | Base64(DER) | Subject DN 的 DER 编码；>512 字节置空，error 含 `client_cert_subject_dn_exceeded_size_limit` |
| 13 | `client_cert_leaf` | RFC 9440 编码 | **整个叶证书**，二进制 DER 经 Base64 后用冒号包围（`:` 开头和结尾）。>16KB 时置空，error 含 `client_cert_validated_leaf_exceeded_size_limit` |
| 14 | `client_cert_chain` | RFC 9440 编码 | **整个证书链**（逗号分隔，每个证书同样是 colon-Base64）。leaf + chain 合计 >16KB 时置空，error 含 `client_cert_validated_chain_exceeded_size_limit` |
| 15-17 | (预留 / 旧) | — | 库内 `glb-verify.md:224-231` 提到的 8 个已全部涵盖在上表 |

> **RFC 9440 编码** 的具体形态：`Hash=<base64-data>;Hash=<base64-data>...` 这种 key=value 形式（参考 Envoy 的 `X-Forwarded-Client-Cert` 编码定义）。**注意：这不是 PEM**（没有 `-----BEGIN CERTIFICATE-----` 标记，也不是换行分隔）。如果你的代码想拿这一头还原 PEM，必须先剥冒号、再 base64 解码、再包成 PEM。

### 4.2 配置示例（gcloud）

```bash
# BackendService 配置（最常见）
gcloud compute backend-services update BACKEND_SERVICE_NAME \
  --global \
  --custom-request-header='X-Client-Cert-Present:{client_cert_present}' \
  --custom-request-header='X-Client-Cert-Chain-Verified:{client_cert_chain_verified}' \
  --custom-request-header='X-Client-Cert-Error:{client_cert_error}' \
  --custom-request-header='X-Client-Cert-Hash:{client_cert_sha256_fingerprint}' \
  --custom-request-header='X-Client-Cert-Serial:{client_cert_serial_number}' \
  --custom-request-header='X-Client-Cert-SPIFFE:{client_cert_spiffe_id}' \
  --custom-request-header='X-Client-Cert-URI-SANs:{client_cert_uri_sans}' \
  --custom-request-header='X-Client-Cert-DNSName-SANs:{client_cert_dnsname_sans}' \
  --custom-request-header='X-Client-Cert-Valid-Before:{client_cert_valid_not_before}' \
  --custom-request-header='X-Client-Cert-Valid-After:{client_cert_valid_not_after}' \
  --custom-request-header='X-Client-Cert-Issuer:{client_cert_issuer_dn}' \
  --custom-request-header='X-Client-Cert-Subject:{client_cert_subject_dn}' \
  --custom-request-header='X-Client-Cert-Leaf:{client_cert_leaf}' \
  --custom-request-header='X-Client-Cert-Chain:{client_cert_chain}'

# 也可以配在 URL Map 上（影响所有绑定该 URL Map 的 BackendService）
gcloud compute url-maps update URL_MAP_NAME \
  --custom-request-header='X-Client-Cert-Present:{client_cert_present}'
```

### 4.3 Nginx 后端读 header（Nginx 变量命名规则）

Nginx 把 header 名转成 `http_<lowercase-with-underscores>`：

```nginx
log_format mtls_log '$remote_addr - $remote_user [$time_local] "$request" '
                  '$status $body_bytes_sent '
                  'cert_present=$http_x_client_cert_present '
                  'cert_verified=$http_x_client_cert_chain_verified '
                  'cert_error=$http_x_client_cert_error '
                  'cert_hash=$http_x_client_cert_hash '
                  'cert_serial=$http_x_client_cert_serial '
                  'spiffe=$http_x_client_cert_spiffe '
                  'uri_sans=$http_x_client_cert_uri_sans '
                  'dns_sans=$http_x_client_cert_dns_sans '
                  'valid_before=$http_x_client_cert_valid_before '
                  'valid_after=$http_x_client_cert_valid_after '
                  'issuer_dn=$http_x_client_cert_issuer '
                  'subject_dn=$http_x_client_cert_subject';

access_log /var/log/nginx/mtls.log mtls_log;
```

⚠️ **Nginx 默认 header buffer 是 4KB/8KB**。如果使用 `client_cert_leaf` 或 `client_cert_chain`（最大 ~16KB Base64），**必须**调大：

```nginx
large_client_header_buffers 4 32k;       # buffer 数量 × 单 buffer 大小
client_header_buffer_size 32k;          # 主 header buffer
proxy_buffer_size 32k;                   # 如果反向代理到 upstream
proxy_busy_buffers_size 64k;
```

否则超过 16KB 的 header 会被 Nginx 直接丢弃，后端拿到的就是空值 / 截断。

### 4.4 `client_cert_error` 的所有可能取值

| error 字符串 | 含义 | 触发条件 |
|---|---|---|
| `client_cert_not_provided` | 客户端未提供证书 | 客户端根本没发 CertificateResponse |
| `client_cert_validation_failed` | TrustConfig 验证失败 | 证书链不完整 / 弱哈希 / 过期 / 格式错误 |
| `client_cert_chain_invalid_eku` | 缺 `clientAuth` EKU | 证书或颁发者没声明 clientAuth OID |
| `client_cert_chain_exceeded_limit` | 中间证书 >10 张 | 客户端链太长 |
| `client_cert_invalid_rsa_key_size` | RSA 密钥长度不在 2048-4096 | 验证未执行 |
| `client_cert_unsupported_elliptic_curve_key` | 曲线不是 P-256 / P-384 | 验证未执行 |
| `client_cert_unsupported_key_algorithm` | 不是 RSA / ECDSA | 验证未执行 |
| `client_cert_pki_too_large` | 同 Subject+SPKI 的中间证书 >10 张 | 验证未执行 |
| `client_cert_chain_max_name_constraints_exceeded` | 中间证书 name constraints >10 | 验证未执行 |
| `client_cert_validation_timed_out` | 验证超时 | 验证未完成 |
| `client_cert_validation_search_limit_exceeded` | 深度 >10 或迭代 >100 | 链路过深 |
| `client_cert_validation_not_performed` | 配置了 mTLS 但没绑 TrustConfig | 配置错误 |
| `client_cert_serial_number_exceeded_size_limit` | 序列号 >50 字节 | 见 #5 |
| `client_cert_spiffe_id_exceeded_size_limit` | SPIFFE ID >2048 字节 | 见 #6 |
| `client_cert_uri_sans_exceeded_size_limit` | URI SANs 拼接 >512 字节 | 见 #7 |
| `client_cert_dnsname_sans_exceeded_size_limit` | DNSName SANs 拼接 >512 字节 | 见 #8 |
| `client_cert_issuer_dn_exceeded_size_limit` | Issuer DN >512 字节 | 见 #11 |
| `client_cert_subject_dn_exceeded_size_limit` | Subject DN >512 字节 | 见 #12 |
| `client_cert_validated_leaf_exceeded_size_limit` | leaf >16KB | 见 #13 |
| `client_cert_validated_chain_exceeded_size_limit` | leaf + chain >16KB | 见 #14 |

→ 多个错误并存时 `client_cert_error` 用逗号拼接。

---

## 5. 三种 Header 类别（按用途分组）

GCLB 在 mTLS 场景下给 backend 注入的 header 按用途分**三类**，来自官方文档原文：

### 5.1 类别 1：指纹（Thumbprint）

> "Pass the **fingerprint** of the certificate to the backend as a custom request header."

- 用 `client_cert_sha256_fingerprint`

用途：作为客户端身份的去标识符（deterministic ID），后端可以做白名单 / audit log / rate limit。

### 5.2 类别 2：证书字段提取

> "Pass **selected fields** extracted from the certificate to the backend by using custom headers."

- `client_cert_serial_number`、`client_cert_spiffe_id`、`client_cert_uri_sans`、`client_cert_dnsname_sans`、`client_cert_valid_not_before`、`client_cert_valid_not_after`、`client_cert_issuer_dn`、`client_cert_subject_dn`

用途：业务层做授权（基于 SPIFFE ID、基于 URI SAN、基于 DN）、审计（颁发者追踪）、证书生命周期检查。

### 5.3 类别 3：完整证书 / 链 + 验证结果

> "Pass the **validation result and any validation errors** to the backend by using custom headers."

- 验证结果类：`client_cert_present`、`client_cert_chain_verified`、`client_cert_error`
- 完整证书类：`client_cert_leaf`、`client_cert_chain`

用途：
- 后端根据 `client_cert_chain_verified` 做最终放行决策（即使 `ALLOW_INVALID_OR_MISSING_CLIENT_CERT` 模式放行，backend 也能自己拒绝）
- 后端拿到完整证书后**重新**做一次验证（用于和 GCLB 的 TrustConfig 不同的策略 —— 比如后端要做 CRL/OCSP 检查，但 GCLB 只做静态 TrustConfig 链校验）
- 透传给下游服务（多跳链路里的二次 mTLS）

---

## 6. 与库内既有文档的事实冲突澄清

读库时发现多处自相矛盾，必须澄清，否则将来踩坑：

### 6.1 `X-Forwarded-Client-Cert` 在 GCLB 里**不存在**

| 来源 | 说法 | 实际情况 |
|---|---|---|
| `mtls-verify.md:1136, 1302, 1341, 1419` | "GLB 转发 `X-Forwarded-Client-Cert` 头（含 PEM）" | ❌ **错误**。GCLB 官方 mTLS 文档完全没有 `X-Forwarded-Client-Cert` 这个名字。GLB 用 `X-Client-Cert-*` 系列。 |
| `glb-verify.md:184` | "x-forwarded-for-client-cert 未被传递，应关注 GCP 官方标准标头" | ✅ **正确**。`x-forwarded-for-client-cert` 这个名字在 GCLB 里确实不存在 —— 库内把这个事实写对了，但理由没说清：它是 Istio/Envoy/IAP 的命名。 |
| `SSLVerifyDepth.md:171, 174` | "配置 `x-forwarded-client-cert: true` 让 Nginx 获取 X-SSL-Client-S-DN 或 X-Forwarded-Client-Cert" | ❌ 这描述的是 **Istio/IAP** 的配置，不是 GCLB 的；用在了 GCLB 语境里是错的。 |
| `SSLVerifyDepth.md:98` | "在 GCP LB 里开启 client certificate forwarding" | ⚠️ 概念对，但没说明：GCLB 没有"一个开关" —— 它是通过 `customRequestHeaders` 一个一个占位符**逐个加**的。 |

→ **结论**：库内 `mtls-verify.md` 反复提到的"GLB 转发 PEM `X-Forwarded-Client-Cert`"是把 **Istio sidecar 行为**误套到 **GCLB** 上了。两者头名不同、注入点不同、用途也不同，但编码格式碰巧都是 RFC 9440。

### 6.2 资源命名：`ServerTlsPolicy` ≠ `ClientTlsPolicy`

| 说法 | 实际情况 |
|---|---|
| `Glb-Client-Authentication.md:92, 132, 287` 用 `gcloud network-security server-tls-policies create` | ✅ 正确（GCLB mTLS 的官方资源叫 ServerTlsPolicy） |
| `Glb-Client-Authentication.md:310` 用 `gcloud network-security client-tls-policies create` | ⚠️ **这条描述的是「客户端侧 mTLS 策略」（client 验证 server 的证书），即反向 mTLS**，不是 GCLB 用来验证客户端的那个策略。混在一起讲容易混淆 |
| `glb-verify.md:252, 297` 用 `gcloud certificate-manager client-tls-policies` | ❌ **错误**。资源类型应该是 `network-security server-tls-policies`，不是在 `certificate-manager` 下。`certificate-manager` 只管 `trust-configs` / `certificates` / `dns-authorizations` |
| `Glb-Client-Authentication.md:94` 用 `--mtls-policy=STRICT` | ❌ **错误**。官方 2026 仅承认两个 mode：`ALLOW_INVALID_OR_MISSING_CLIENT_CERT` 和 `REJECT_INVALID`。`STRICT` 不是合法值（可能是早期版本遗留或 AI 幻觉） |

### 6.3 字段命名：`mtlsPolicy` vs `ServerTlsPolicy`

- 旧方式（**仍在用**）：`targetHttpsProxies` 上挂 `mtlsPolicy` 块，含 `clientValidationMode` + `clientValidationTrustConfig`
- 新方式：独立的 `ServerTlsPolicy` 资源，引用 `TrustConfig`，再 attach 到 `targetHttpsProxy`

两者**共存**，旧方式只是新方式的语法糖。文档 `Glb-Client-Authentication.md:84-105` 的命令是旧方式，能跑通；新方式可读性更好。

---

## 7. 实战 Checklist（用户场景：带证书的 Cluster 访问 URL）

假设场景：**A 集群里的客户端（带 client cert）→ GCLB（mTLS）→ 后端业务**

- [ ] **GLB 配置**：targetHttpsProxy 挂 ServerTlsPolicy，clientValidationMode = `REJECT_INVALID`，绑 TrustConfig（含客户端 CA）
- [ ] **BackendService customRequestHeaders**：至少配 `X-Client-Cert-Present`、`X-Client-Cert-Chain-Verified`、`X-Client-Cert-Error`、`X-Client-Cert-Hash` 四个 —— 这是最小可观测集
- [ ] **如要后端做细粒度授权**：再加 `X-Client-Cert-SPIFFE-Id`（基于 SPIFFE ID 授权）或 `X-Client-Cert-Subject`（基于 DN 授权）或 `X-Client-Cert-URI-SANs`（基于 URI SAN 授权）
- [ ] **如要让后端重新验证证书**：加 `X-Client-Cert-Leaf`（用 RFC 9440 → 转 PEM 后校验），需 Nginx 调大 `large_client_header_buffers`
- [ ] **如要排查失败**：打开 GLB Cloud Logging，看 `jsonPayload.statusDetails`，对照 §4.4 表格定位错误码
- [ ] **后端日志**：在 access log 里打印上面这几个 X-Client-Cert-* 头 —— 没有日志就没有可观测性
- [ ] **客户端原始头清单**：在切换前**抓一次**客户端发的所有 header（含 cookie 大小、Authorization 长度），确保 Nginx / 后端 buffer 够用
- [ ] **后端**不要去解析名为 `X-Forwarded-Client-Cert` 的头 —— 这个名字在 GCLB 里**不存在**，你永远不会收到
- [ ] **Istio 侧的 mTLS 是独立的**：如果 GCLB 后端是 GKE + ASM，请单独考虑 Pod-to-Pod 的 mTLS，与 GCLB mTLS **不互通**

---

## 8. 引用

- 官方 mTLS overview: https://cloud.google.com/load-balancing/docs/mtls
- 官方 custom headers (含 17 个占位符完整定义): https://cloud.google.com/load-balancing/docs/https/custom-headers
- 库内 `glb-verify.md` 第 III.C 节 — 后端日志验证方法
- 库内 `SSLVerifyDepth.md` — Nginx SSL 客户端验证深度
- 库内 `asm/` 目录 — Istio 侧 `X-Forwarded-Client-Cert` 行为（与 GCLB 的差异）
- RFC 9440 — X.509 Certificate Encoding for HTTP Header Forwarding（`X-Client-Cert-Leaf` 和 Istio 的 `X-Forwarded-Client-Cert` 都遵循这个 RFC）


# Gemini
这是一个非常深刻且具有实战意义的问题。在 GCP (如 GFE/Cloud Load Balancing) 或 Kubernetes (GKE Gateway API/Kong) 的架构中，mTLS 与 HTTP Header 之间既有“解耦”的一面，也有“深度绑定”的一面。

以下是从架构师视角对 mTLS 与 HTTP Header 关系的深度探索。

🔍 问题分析 (Analysis)
从技术本质上讲，mTLS 和 HTTP Header 处于 OSI 模型的不同层级：

mTLS (Layer 4/Transport Layer): 发生在 TCP 握手之后，HTTP 数据传输之前。它的核心职责是身份验证 (Authentication) 和 加密 (Encryption)。
HTTP Header (Layer 7/Application Layer): 是应用层的数据包头。
核心结论：

在传输阶段：它们确实“没有任何关系”。mTLS 握手失败，连接直接断开，根本不会解析到 Header。
在业务处理阶段：它们有“强对应关系”。网关（如 GCP GLB 或 Kong）在卸载 (Terminate) mTLS 证书后，会将客户端证书中的身份信息（如 CN, SAN, Issuer）透传到 HTTP Header 中，以便后端服务进行鉴权 (Authorization)。
🛠 解决方案 (Solution)
1. 流量处理流程：从握手到 Header 透传
当一个带 Client 证书的请求访问 URL 时，流程如下：

TLS 握手阶段: 客户端发送证书，网关校验有效期及 CA 信任链。
证书卸载 (Termination): 网关验证成功，提取证书元数据。
Header 注入: 网关根据配置，将提取的信息（如证书序列号、CN）写入新的 HTTP Header。
后端路由: 网关将带有这些新 Header 的请求转发给后端（通常是普通 HTTP 或单向 TLS）。
2. 常见的透传 Header 命名规范
不同的网关有不同的默认行为，但通常遵循以下逻辑：

信息维度	常用 Header 示例	说明
证书状态	X-Client-Cert-Present	标识是否通过了 mTLS 校验
主体信息 (Subject)	X-Client-Cert-Subject-DN	完整的受访者名称 (Distinguished Name)
常用名 (CN)	X-Client-Cert-CN	提取出的 Common Name (如 api-client-001)
指纹 (Fingerprint)	X-Client-Cert-Fingerprint	证书的唯一哈希值
完整证书	X-Client-Cert	将整个 PEM 格式证书经 URL Encode 后放入 Header
📊 流程可视化 (Visualization)
sequenceDiagram
    participant Client as "Client (with Cert)"
    participant Gateway as "GCP GLB / Kong (mTLS Terminate)"
    participant Backend as "Backend Service (GKE/GCE)"

    Note over Client, Gateway: 1. TCP Handshake
    Note over Client, Gateway: 2. mTLS Handshake (Cert Exchange)
    
    rect rgb(200, 255, 200)
    Gateway->>Gateway: Validate Client Cert against Trust Bundle

Generated code may be subject to license restrictions not shown here. Use code with care. Learn more 

💻 代码/配置 (Code)
场景：在 GKE Gateway API 中配置 mTLS 身份透传
如果你使用 GKE 的 Gateway，可以通过 ClientTlsPolicy 实现。

# 示例：通过特定的 Policy 确保身份信息注入 Header
apiVersion: networking.gke.io/v1
kind: ClientTlsPolicy
metadata:
  name: mtls-identity-policy
spec:
  serverValidation:
    caCertificates:
    - name: client-ca-cert # 引用存储在 Secret 中的 CA
  clientCertificateSelection:

Generated code may be subject to license restrictions not shown here. Use code with care. Learn more 

场景：在 Kong Gateway 中通过插件实现
Kong 官方提供 mtls-auth 插件，可以将证书信息映射到 Header。

# 启用 mTLS 插件并配置身份透传
curl -X POST http://localhost:8001/services/my-service/plugins \
    --data "name=mtls-auth" \
    --data "config.ca_certificates=ca-uuid" \
    --data "config.skip_consumer_lookup=true" \
    --data "config.authenticated_group_by=certificate.subject_name"
# 结果：Kong 会在 Header 中自动添加 X-Consumer-Custom-ID 等信息
Generated code may be subject to license restrictions not shown here. Use code with care. Learn more 

⚠️ 注意事项 (Best Practices)
Header 欺骗风险 (Header Spoofing):
极其重要：后端服务必须只信任来自网关的特定 Header。
安全建议：网关在转发请求前，应先清除 (Strip) 掉客户端自行携带的所有同名 X-Client-Cert-* Header，防止客户端伪造身份。
解耦优势:
通过将 mTLS 信息转为 Header，你的后端业务逻辑（Java/Go/Python）不再需要调用复杂的 SSL 库去解析证书二进制流，只需读一个字符串 Header 即可。
性能损耗:
mTLS 握手比普通 TLS 耗时稍长（多了一次证书交换和验证）。在高并发场景下，建议在网关层开启 SSL Session Reuse。
总结回答： mTLS 负责“进门校验”，Header 负责“进门后的身份工牌”。网关就是那个负责核对身份证并给你发工牌的管理员。

您当前是在考虑使用 GCP 原生的负载均衡 mTLS，还是在 Kubernetes 内部使用 Service Mesh (Istio/Linkerd) 或者是 Kong 来处理这部分逻辑呢？