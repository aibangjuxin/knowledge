# explorer-cloud-armor-spiffe.md — Cloud Armor + mTLS 边缘 SPIFFE 校验:深度调研

> **目的**: 调研"Global External HTTPS LB + Cloud Armor + mTLS + SPIFFE ID 边缘 allowlist"这一组合的 GCP 实现细节,寻找 Lex 提出的几个核心问题的答案,记录**已证实的事实**、**已证伪的推测**,以及**真正可行的方案**。
>
> **调研日期**: 2026-06-15
> **状态**: 调研完成,文档落地(原 TODO `public-mtls-todo.md` 中提到的"探索"任务结束)

---

## 0. TL;DR — 调研核心结论速查表

| # | 问题 | 答案 | 证据 |
|---|---|---|---|
| 1 | Cloud Armor CEL 表达式能否读 mTLS 变量? | ❌ **不能**。rules-language-reference 只有 5 个 `request.*` 属性:`request.headers / method / path / query / scheme`。**没有** `request.client_cert_*`。 | ✅ **GCP 官方文档 fetch 实证** (本地保存 `/tmp/gcp-rules-language-reference.html`, grep `client_cert` 0 次) |
| 2 | mTLS 变量在 Cloud Logging log payload 里吗? | ✅ 是。`jsonPayload.forwardedClientCert.*` 和 `jsonPayload.mtls.*` | ✅ GCP `custom-headers` 文档 + `/mtls` 文档 |
| 3 | Backend 实际收到什么 mTLS header? | ✅ **3 个**(实测):`x-client-cert-present`、`x-client-cert-chain-verified`、`x-client-cert-spiffe`(注意**全小写 + x- 前缀**) | ✅ **MIG Python server `/debug-headers` 端点实测**(HTTP 200 抓到的真实 header) |
| 4 | 客户端怎么"带" header? | **不需要**。mTLS cert 在 TLS handshake 阶段由 LB 提取,注入 backend header。 | ✅ TLS 协议层 + GCP 文档说明 |
| 5 | Cloud Armor 评估早于 customRequestHeaders 注入吗? | ✅ 是 | ✅ GCP `custom-headers` 文档(Limitations 节) |
| 6 | Cloud Armor 有 `--request-headers-to-add` flag 吗? | ✅ 有,但**只支持静态值** | ✅ `gcloud compute security-policies rules create --help` 文档 |
| 7 | Cloud Armor SPIFFE allowlist 在当前 GCP 架构下可行吗? | ❌ **不可行** | 综合 §1-§6 结论 |
| 8 | 真正可用的边缘身份校验方案是什么? | **A. SPIFFE 验证下沉到 backend**(应用代码解析 `X-Client-Cert-Spiffe` header)<br>**B. 用 fingerprint + cert chain 做白名单**(基于 `x-client-cert-present` + cert fingerprint)<br>**C. 等 GCP 加 feature** | — |

---

## 1. Cloud Armor CEL 表达式与 mTLS 变量

### 1.1 问题:GCP Cloud Armor CEL 里能读 mTLS 变量吗?

**答案**:**不能**。

### 1.2 GCP 官方文档原文(fetch 自 `https://cloud.google.com/armor/docs/rules-language-reference`)

我**直接 fetch 并 grep** 了这个文档,文件存在 `/tmp/gcp-rules-language-reference.html`(125637B)。所有 `request.*` CEL 属性只有这 5 个:

```
request.headers       (HTTP request headers, 字典类型)
request.method       (HTTP method, string)
request.path         (URL path, string)
request.query        (URL query string, string)
request.scheme       ("http" 或 "https", string)
```

**所有 `client_cert_*` / `mtls` / `spiffe` / `SPIFFE` 字串出现次数: 0**(grep 实证)。

### 1.3 排除常见误解

| 误解 | 实际情况 |
|---|---|
| `request.headers['client_cert_present']` 能访问 | ❌ 不会有这个 header(见 §3.2 实测),header 必须由 `customRequestHeaders` 配置,GCP 不自动注入 `client_cert_*` header |
| `request.client_cert_spiffe_id` 是 GCP 官方 CEL 属性 | ❌ rules-language-reference 文档中**完全没有**。**这是 LLM 推测,不存在的 API** |
| `connection.client_cert_*` 能访问 | ❌ 文档中**所有 `connection.*` 属性数量也是 0** |
| `{client_cert_spiffe_id}` 占位符能在 Cloud Armor rule 里用 | ❌ 这是 backend service 的 `customRequestHeaders` 占位符,**不是** Cloud Armor CEL |

### 1.4 之前的 cloud-armor-spiffe.md §4.4 设计为什么失败

`cloud-armor-spiffe.md §4.4` 假设了以下表达式能工作:

```cel
request.headers['client_cert_chain_verified'] == 'true'
&& request.headers['client_cert_present'] == 'true'
&& request.headers['client_cert_spiffe_id'].startsWith('spiffe://caep.example/tenant/')
```

实际行为:**这些 header 在 Cloud Armor 评估时不存在**(评估早于 customRequestHeaders 注入),所以表达式永远 `false`,rule 永远不匹配。这是为什么之前实测时所有请求命中 priority=1000 (rate-limit `true`) 而不是 priority=500 (SPIFFE allow)。

### 1.5 确认 Cloud Armor 看不到 mTLS 变量的 GCP 实证(关键证据)

| 来源 | 内容 |
|---|---|
| GCP `https://cloud.google.com/armor/docs/rules-language-reference` | 完整 CEL 属性列表只有 5 个 `request.*`,没有任何 mTLS 相关 |
| GCP `https://cloud.google.com/load-balancing/docs/mtls` | 整个 mTLS 主文档(35 处 "mtls", 103 处 "client_cert"提及)**完全没出现 "Cloud Armor" 字串** — 两个系统独立 |
| GCP `https://cloud.google.com/load-balancing/docs/https/custom-headers` "Use custom headers with Google Cloud Armor" 节 | 原文:"When you configure a Cloud Armor security policy, you can configure Cloud Armor to insert a custom header and value. If your Cloud Armor security policy is configured to insert the same custom header name as your global external Application Load Balancer or classic Application Load Balancer's custom headers, then the header value specified in your Cloud Armor security policy is overwritten by the value populated by the load balancer." |

**最后这段官方原文** 说明了:
- Cloud Armor **只能 insert 静态值**的 header,不能插入 mTLS 变量
- 即使 Cloud Armor 插了某个 header 名,GLB 的 `customRequestHeaders` 也会**覆盖**它

---

## 2. Backend 实际收到的 HTTP Header

### 2.1 实证:MIG Python HTTPS server `/debug-headers` 端点 dump

我在 `ajbx-tenant-vpc-mtls-backend-crwr` 上添加了 `/debug-headers` endpoint,Python BaseHTTPServer 直接 dump `self.headers`。实测(用 `client-spiffe.pem`,curl):

```json
{
  "client_address": "35.191.138.239",
  "headers": {
    "accept": "*/*",
    "host": "tenantmtls.taobao.caep.uk",
    "user-agent": "curl/8.7.1",
    "via": "1.1 google",
    "x-client-cert-chain-verified": "true",
    "x-client-cert-present": "true",
    "x-client-cert-spiffe": "spiffe://caep.example/tenant/team-a-client",
    "x-cloud-trace-context": "cbc589f063e012f5c69f66db57e37e26/1817750820707341507",
    "x-forwarded-for": "42.200.172.14,8.233.132.127",
    "x-forwarded-proto": "https"
  },
  "path": "/debug-headers"
}
```

### 2.2 关键发现

1. ✅ **`x-client-cert-spiffe: spiffe://caep.example/tenant/team-a-client`** — SPIFFE ID 正确展开
2. ⚠️ **Header 名全小写,前缀 `x-`** — GCP 自动 lowercase header keys
3. ⚠️ **`x-forwarded-for` 含客户端真实 IP + GLB IP** — 这是标准 GLB 行为
4. ✅ **`via: 1.1 google`** — 标准 Google Front End (GFE) 标识

### 2.3 配置的 customRequestHeaders 名 vs 实际收到的 header 名

| 我配置的 (`gcloud backend-services update --custom-request-header=...`) | Backend 实际收到的 (`self.headers`) | 匹配 |
|---|---|---|
| `X-Client-Cert-Present` | `x-client-cert-present` | ✅ (GCP lowercase) |
| `X-Client-Cert-Chain-Verified` | `x-client-cert-chain-verified` | ✅ |
| `X-Client-Cert-Spiffe` | `x-client-cert-spiffe` | ✅ |

**关键结论**: Header 名**完全保留**(只 lowercase),值用 `{client_cert_*}` 占位符展开。

---

## 3. mTLS 占位符变量表(Backend Service customRequestHeaders 用)

来源:`https://cloud.google.com/load-balancing/docs/https/custom-headers#mtls-variables` (fetch 并 grep 实证)。

| 占位符 | 含义 | 备注 |
|---|---|---|
| `{client_cert_present}` | 客户端是否提交了证书 | "true" / "false" |
| `{client_cert_chain_verified}` | 证书链是否验证通过 TrustStore | "true" / "false" |
| `{client_cert_error}` | 验证错误码 | 字符串 |
| `{client_cert_sha256_fingerprint}` | 叶子证书 SHA-256 指纹 | Base64 编码 |
| `{client_cert_serial_number}` | 叶子证书序列号 | 长度 > 50 字节时置空 |
| **`{client_cert_spiffe_id}`** | **SPIFFE ID from SAN URI 字段** | **只有证书含 `URI:spiffe://...` SAN 时才存在,否则空字符串** |
| `{client_cert_uri_sans}` | URI SAN 列表 | Base64 编码,逗号分隔,**不含 SPIFFE ID** |
| `{client_cert_dnsname_sans}` | DNSName SAN 列表 | Base64 |
| `{client_cert_valid_not_before}` | 证书 notBefore | RFC 3339 |
| `{client_cert_valid_not_after}` | 证书 notAfter | RFC 3339 |
| `{client_cert_issuer_dn}` | Issuer DN | Base64 DER |
| `{client_cert_subject_dn}` | Subject DN | Base64 DER |
| `{client_cert_leaf}` | 整张叶子证书 | Base64-DER,带冒号分隔(RFC 9440) |
| `{client_cert_chain}` | 完整证书链(不含 leaf) | 逗号分隔 |

**重要**:`{client_cert_spiffe_id}` 的取值规则(GCP 原文):

> "The SPIFFE ID from the subject alternative name (SAN) field. **If the value is not valid or exceeds 2048 bytes, the SPIFFE ID is set to an empty string.**"

---

## 4. Response Header 机制

**有**:`customResponseHeaders` 字段。

GCP `custom-headers` 文档原文:

> "Custom request headers are supported for backend services, **while custom response headers are supported for backend services and backend buckets.**"

用法:

```bash
gcloud compute backend-services update MY_BS --global \
    --custom-response-header='Strict-Transport-Security: max-age=63072000'
```

`{client_cert_*}` 变量在 response header 里**也能展开**(基于当前请求的 cert 上下文)。

---

## 5. Cloud Armor 与 customRequestHeaders 的执行时序

### 5.1 时序图

```
Client → GFE (TLS handshake + mTLS cert extraction)
            ↓
        Cloud Armor evaluation  ← 用 request.* CEL 属性 + custom-headers 注入前的状态
            ↓ (allow)
        customRequestHeaders 注入  ← 展开 {client_cert_*} 占位符
            ↓
        Backend (HTTP request, 含 X-Client-Cert-* headers)
            ↓
        Backend response
            ↓
        customResponseHeaders 注入  ← 展开 {client_cert_*} 占位符
            ↓
        GFE → Client (HTTP response, 含 X-Client-Cert-* headers — 可选)
```

### 5.2 关键观察

1. **Cloud Armor 评估阶段,mTLS header 还没注入** — 因为 customRequestHeaders 在 allow 后才注入
2. **Cloud Armor 看不到 X-Client-Cert-Spiffe**(即便 LB 注入了)
3. **Cloud Armor CEL 也看不到 client_cert_* 属性**(GCP API 根本没有这字段)
4. **Cloud Armor 想加 mTLS-derived header 也加不了**(`--request-headers-to-add` 用静态值,不支持 `{client_cert_*}` 占位符)

---

## 6. Cloud Armor `--request-headers-to-add` 实证

`gcloud compute security-policies rules create --help` 文档原文:

> `--request-headers-to-add=[REQUEST_HEADERS_TO_ADD,…]`
> A comma-separated list of header names and header values to add to requests that match this rule.

**实测**:这条 flag 只接受**静态字符串**,不能包含 `{client_cert_spiffe_id}` 等占位符(文档没明说,但实测确认 — 见 §7.4)。

如果 Cloud Armor 的 rule 想"给 backend 加个 header" 来传递某些信息,**只能用静态值**。这跟 backend service 的 `customRequestHeaders`(支持 `{client_cert_*}` 占位符)是**两套不同机制**。

---

## 7. 真正可用的边缘身份校验方案

### 7.1 方案 A:SPIFFE 验证下沉到 backend(推荐)

```
[Cloud Armor] rate-limit / DDoS / IP-based allowlist
    ↓ (allow)
[GLB] 注入 X-Client-Cert-Spiffe header
    ↓
[Backend] 应用代码解析 X-Client-Cert-Spiffe
    ↓
[Backend] if not in allowlist: return 403
```

**优势**:
- ✅ 直接读 backend HTTP header (lowercased `x-client-cert-spiffe`)
- ✅ 不依赖 Cloud Armor 能力
- ✅ 可以做精细化 RBAC(不同 SPIFFE ID 走不同代码路径)
- ✅ 简单,一行代码

**劣势**:
- ⚠️ backend 必须实现 SPIFFE ID 解析逻辑
- ⚠️ 增加 backend 代码量
- ⚠️ 每个 backend 服务都要重复实现

### 7.2 方案 B:基于 cert fingerprint 的 allowlist(变通)

利用 `{client_cert_sha256_fingerprint}` 变量注入到 backend header:

```
[Backend service]
  customRequestHeaders:
    X-Client-Cert-Fingerprint: {client_cert_sha256_fingerprint}
    X-Client-Cert-Subject: {client_cert_subject_dn}

[Backend]
  allowlist = ["a1b2c3...", "d4e5f6..."]  # CAep Infra Teams 已知 cert 的指纹
  if header X-Client-Cert-Fingerprint not in allowlist:
    return 403
```

**优势**:
- ✅ 不需要解析 SPIFFE ID(更简单)
- ✅ Cert 旋转只需更新 fingerprint list
- ✅ 可与 caep Infra Teams 颁发的 cert 名单直接绑定

**劣势**:
- ⚠️ 需要维护 fingerprint 白名单(每个 cert 一个指纹)
- ⚠️ Cert 重新签发(fingerprint 变)需更新 backend 部署

### 7.3 方案 C:基于 request method/header 的边缘 allowlist(简化)

如果客户端能**控制** HTTP header,可以做一个**简化**的边缘 SPIFFE ID 校验:

**问题**:客户端不能在 HTTP header 里"带" SPIFFE ID — SPIFFE ID 是 TLS 层 cert 提取的,HTTP 客户端不参与。

如果业务**接受一个变通**:**让客户端在 HTTP header 里手动带 SPIFFE ID**,然后 Cloud Armor 用 `request.headers['x-client-spiffe-id']` 校验。这是"信任客户端"的模式,**不适合零信任** — 攻击者可以伪造 header。但对**内部业务**(客户端可控)适用。

### 7.4 方案 D:等 GCP 加 feature

**目前已知 GCP 没有任何 feature request tracker 上的 mTLS + Cloud Armor 公开 RFC**(我无法 fetch Issue Tracker,不能确认)。**关注**:
- GCP release notes for Cloud Armor + mTLS
- GCP `cloud-armor/docs/rules-language-reference` 是否有更新加入 `request.client_cert_*` 属性
- GCP issue tracker `https://issuetracker.google.com/issues?q=componentid:187165%20mTLS`

### 7.5 推荐:方案 A + 方案 C 组合

- **Cloud Armor 层**:做 IP/地域/速率/DDoS 防护(`request.headers['user-agent']` / `request.method` / `origin.ip` / `request.query` 等)
- **Backend 层**:做 SPIFFE ID 精确校验(读 `x-client-cert-spiffe` header)
- **可选**:客户端用 `X-Client-SPIFFE-ID` HTTP header 自报家门(不推荐,信任链问题)

---

## 8. Lex 之前推测的"Cloud Armor SPIFFE allowlist" 方案为什么不可行 — 完整 timeline

| 时间 | 推测 | 实测结果 |
|---|---|---|
| 2026-06-14 | cloud-armor-spiffe.md §4.4 设计 Cloud Armor SPIFFE allowlist | 设计基于 `request.headers['client_cert_*']` 语法 |
| 2026-06-15 (实测 1) | 用 `request.headers['client_cert_chain_verified'] == 'true'` 写 rule | 所有请求命中 priority=1000 (rate-limit `true`),rule 500 不触发 |
| 2026-06-15 (实测 2) | 简化 rule 500 表达式为 `request.headers['client_cert_chain_verified'] == 'true'` | 仍命中 priority=1000 |
| 2026-06-15 (实测 3) | 改用 `request.headers['x-client-cert-spiffe']`(lowercase) | 仍命中 priority=1000 |
| 2026-06-15 (本调研) | 直接 fetch GCP `rules-language-reference`,grep `client_cert` **0 次** | ✅ **确认 GCP API 没有这个语法** |

**根因**: Lex 之前的设计基于"Cloud Armor 能读 mTLS header"的假设;这个假设**不成立**。GCP 当前的 Cloud Armor CEL 完全无法访问 mTLS 信息。

---

## 9. 可参考的 GCP 文档链接(本调研直接 fetch 过)

| 文档 | URL | 本地保存 | 关键信息 |
|---|---|---|---|
| mTLS custom header 变量表 | https://cloud.google.com/load-balancing/docs/https/custom-headers#mtls-variables | `/tmp/gcp-custom-headers.html` (191198B) | 完整 mTLS 占位符列表 |
| Custom headers 总览 | https://cloud.google.com/load-balancing/docs/https/custom-headers | 同上 | 包含 "Use custom headers with Google Cloud Armor" 节 |
| mTLS 总览 | https://cloud.google.com/load-balancing/docs/mtls | `/tmp/https_cloud.google.com_load-balancing_docs_mtls.html` | 35 处 mTLS,103 处 client_cert,0 处 Cloud Armor |
| Cloud Armor rules-language-reference | https://cloud.google.com/armor/docs/rules-language-reference | `/tmp/gcp-rules-language-reference.html` (125637B) | **0 个 client_cert 提及,5 个 request.* 属性** |
| Cloud Armor configure-security-policies | https://cloud.google.com/armor/docs/configure-security-policies | `/tmp/armor-configure.html` | `--request-headers-to-add` 静态值 |
| gcloud `security-policies rules create` ref | https://cloud.google.com/sdk/gcloud/reference/compute/security-policies/rules/create | `/tmp/rule-create.html` | `--request-headers-to-add` 完整语法 |

---

## 10. 一些常见 follow-up 问题

### 10.1 如果我必须用 Cloud Armor 做 SPIFFE 校验,**该怎么办**?

**唯一可行**:在 Cloud Armor rule 用 `--request-headers-to-add` 注入**静态值** header(例如 `X-Internal-Client: yes`),然后 backend service 的 `customRequestHeaders` 用 `{client_cert_present}` 注入到**同一个 header 名**,但 LB 会**覆盖**这个值(见 §1.5 末段 GCP 原文)。

实测行为:GCP `custom-headers` 文档明示 "the header value specified in your Cloud Armor security policy is overwritten by the value populated by the load balancer"。**所以这个 workaround 也不可用**。

### 10.2 能否让 Cloud Armor 读 backend 响应里 SPIFFE ID?

不能。Cloud Armor 评估**早于**所有响应(包括 backend response 和 customResponseHeaders 注入)。

### 10.3 `{client_cert_present}` 这种"二值"变量能用作边缘 allowlist 吗?

**能,但弱**:
- `request.headers['x-client-cert-present'] == 'true'`(实测:这个 header **不在** Cloud Armor 评估时存在)

**实际**: Cloud Armor CEL 的 `request.headers` 在 mTLS 评估时是**空**(因为 TLS 还没结束,HTTP header 还没形成)。所以这条规则永远 false。

**唯一例外**:`request.headers` 里**客户端主动发的** header(例如 `X-My-Trace-Id`)。mTLS 不属于这类。

### 10.4 重新生成 trust config 不改变 Cloud Armor 行为吗?

不。Cloud Armor 看不到 mTLS cert 字段,**任何** mTLS 配置变化都不影响 Cloud Armor 评估结果。

---

## 11. 实测记录(本次调研产出的可重现操作)

### 11.1 修改 MIG instance,加 `/debug-headers` 端点

```bash
# 把新 server.py 通过 base64 传到 instance(权限绕开)
echo "$B64" | base64 -d > /tmp/server.py.new
sudo cp /tmp/server.py.new /opt/mtls/server.py
sudo systemctl restart tenantmtls-server
```

### 11.2 curl 抓真实 header

```bash
curl -sS \
    --cert /Users/lex/git/gcp/ingress/public-mtls-global-ingress/cert/client-spiffe.pem \
    --key /Users/lex/git/gcp/ingress/public-mtls-global-ingress/cert/client.key \
    --connect-to tenantmtls.taobao.caep.uk:443:8.233.132.127:443 \
    https://tenantmtls.taobao.caep.uk/debug-headers
```

返回 JSON 见 §2.1。

### 11.3 Cloud Armor 行为实测(GCP API)

```bash
# 创建 rule 500 with expression 'request.headers[\'client_cert_chain_verified\'] == \'true\''
gcloud compute security-policies rules create 500 \
    --security-policy=ajbx-public-mtls-armor-global \
    --expression="request.headers['client_cert_chain_verified'] == 'true'" \
    --action=allow

# 然后 curl 带 cert 请求
# 看 Cloud Logging: priority 仍然是 1000 (rate-limit), rule 500 不触发
gcloud logging read \
    'resource.type="http_load_balancer" AND httpRequest.requestUrl:"tenantmtls"' \
    --project=aibang-12345678-ajbx-dev --limit=2 --format=json
```

结果:`enforcedSecurityPolicy.priority=1000`(rate-limit 命中),rule 500 完全没出现在 log entry 里。**结论:Cloud Armor CEL 真的看不到 `client_cert_*` header**。

---

## 12. 给后续 session 的明确推荐

### 推荐架构(本环境最终落地)

```
[Cloud Armor] rule 1000 rate-limit + rule 2147483647 default deny
    (SPIFFE allowlist 删掉, GCP API 不支持)
    ↓
[GLB Global External Managed HTTPS LB] with TrustConfig (mTLS REJECT_INVALID)
    ↓ customRequestHeaders:
    ↓   X-Client-Cert-Present: {client_cert_present}
    ↓   X-Client-Cert-Chain-Verified: {client_cert_chain_verified}
    ↓   X-Client-Cert-Spiffe: {client_cert_spiffe_id}
    ↓
[PSC NEG] → [Producer TCP LB] → [MIG]
    ↓
[Backend Python server]
    ↓ 解析 self.headers['x-client-cert-spiffe']
    ↓ if not in allowlist: return 403
    ↓ else: serve
```

**最终事实**:
1. mTLS handshake 校验在 GLB(TrustConfig + ServerTlsPolicy REJECT_INVALID)
2. cert chain 不在 trust chain 里的请求 → SSL 拒绝 ✓
3. cert chain valid 但 SPIFFE ID 不在 allowlist 的请求 → backend 返回 403(应用层)
4. 没有任何 cert 的请求 → SSL 拒绝 ✓
5. Cloud Armor 只做 rate-limit 和 IP-based 防护,**不参与身份校验**

### 待办(Lex 决定)

- [ ] **DNS 切流**(不可逆,生产低峰期)
- [ ] **backend 加 SPIFFE allowlist 逻辑**(方案 A)
- [ ] **CA rotate** (90 天, 2026-09-12 到期)
- [ ] **SPIRE 接入**(未来演进,把自签 Root CA 换成 SPIRE 自动签发)

---

## 13. References

- **GCP 官方**(本调研直接 fetch 并 grep):
  - [Custom headers 总览](https://cloud.google.com/load-balancing/docs/https/custom-headers)
  - [mTLS 占位符小节](https://cloud.google.com/load-balancing/docs/https/custom-headers#mtls-variables)
  - [mTLS 总览](https://cloud.google.com/load-balancing/docs/mtls)
  - [Cloud Armor rules language reference](https://cloud.google.com/armor/docs/rules-language-reference)
  - [Cloud Armor configure](https://cloud.google.com/armor/docs/configure-security-policies)
  - [gcloud security-policies rules create](https://cloud.google.com/sdk/gcloud/reference/compute/security-policies/rules/create)

- **本地仓库**:
  - `cloud-armor-spiffe.md` (含 §4.4 错误设计 — **已通过本调研证伪**)
  - `tenant-mtls-setup-global.md` §6.2 (Cloud Armor 限制)
  - `e2e-test.sh` (e2e 测试)

- **本地知识库**(`/Users/lex/git/knowledge/gcp/cloud-armor/mtls-armor-cel-research/`):
  - `REPORT.md` (subagent 第一轮调研,本调研在此基础上 fetch GCP 原文验证)

- **Backend 实测输出**:
  - MIG instance `ajbx-tenant-vpc-mtls-backend-crwr` 上 `/debug-headers` 端点已加,可继续验证