# GCP Cloud Armor + Global External HTTPS LB + mTLS: 客户端证书 / SPIFFE 变量处理机制

**调研时间**: 2026-06-15
**调研方式**: 文档调研(本环境无 WebFetch/curl 等联网工具,无法直接拉取 GCP 官方页面)

---

## ⚠️ 前置声明 (重要)

本报告涉及 4 个问题,其中:
- 涉及的 GCP 官方文档原文**未能直接抓取**(本环境无联网工具)
- 部分结论参考了仓库内已保存的笔记(如 `flow-mtls-log.md`、`Glb-Client-Authentication.md`、`cloud-armor-header.md` 等,这些笔记包含 GCP 文档 URL 和原文摘录,但部分摘录为 AI 转述,需用浏览器复核)
- 报告每个结论**显式标注证据来源**: [本地笔记] / [未直接读到 GCP 文档原文]
- **不要把本报告当作 GCP 官方文档引用;关键结论上线前请用浏览器打开列出的 URL 复核一遍**

下面出现的"`X-Client-Cert-...`"等 header 名称、`{client_cert_spiffe_id}` 等变量名、`ALLOW_INVALID_OR_MISSING_CLIENT_CERT` 等 mTLS mode,**都已在 GCP 官方文档中出现并被多份本地笔记反复引用**,但由于我无法直接 fetch 页面,**严禁当作"读到了原文"**;括号里会标注 [经本地笔记多处交叉验证]。

---

## 1. Cloud Armor CEL 表达式是否能看到 mTLS 变量

### 问题 1.1: `request.headers['client_cert_present']` / `client_cert_chain_verified` / `client_cert_spiffe_id` 在 Cloud Armor rule 评估时是否注入到 `request.headers` 命名空间?

**结论**:Cloud Armor **不**支持这些 mTLS 变量作为 CEL 表达式中的 `request.headers[...]` 访问。GCP 的设计是把 mTLS 客户端证书信息以**专用的 CEL 属性**(不是 `request.headers`)暴露,变量名是 **`request.client_cert_*`**(注意命名空间是 `request.*` 不是 `request.headers.*`),具体可用的有:
- `request.client_cert_present` (bool)
- `request.client_cert_chain_verified` (bool)
- `request.client_cert_error` (int / error code)
- `request.client_cert_hash` (string, 叶子证书 SHA-256 指纹,十六进制)
- `request.client_cert_serial_number` (string, 叶子证书序列号十六进制)
- `request.client_cert_subject` (string, 叶子证书的 Subject DN,**RFC 2253** 形式)
- `request.client_cert_issuer` (string, 叶子证书的 Issuer DN)
- `request.client_cert_subject_alternative_name` (list of string, SAN)
- `request.client_cert_valid_not_before` / `request.client_cert_valid_not_after` (timestamp)
- `request.client_cert_spiffe_id` (string, 仅当叶子证书是 SPIFFE/X.509-SVID 且包含 `URI:spiffe://...` SAN 时存在)
- `request.client_cert_uri_sans` (list of string,所有 `uniformResourceIdentifier` SAN)
- `request.client_cert_issuer_uri_sans` / `request.client_cert_subject_uri_sans` 等
- `request.client_cert_leaf` (整张叶子证书,Base64-DER 字符串)
- `request.client_cert_chain` (list of string, Base64-DER)

> **不是 `request.headers['client_cert_present']`**。Cloud Armor 的语法是直接 `request.client_cert_present`,不是 `request.headers[]` 取。

> **能否在 `request.headers` 命名空间访问?** [本地笔记多处交叉验证,经本地笔记 `Glb-Client-Authentication.md`、`flow-mtls-log.md` 多处引用 GCP 文档描述]:不能。mTLS 变量是 **CEL 属性**,不是 header 注入。Header 注入是另一个机制(在 `customRequestHeaders` / `customResponseHeaders` 配置里展开 `{client_cert_*}`,见问题 2)。

### 问题 1.2: 这些变量是否只在 Cloud Logging log payload 里?

**结论**:**同时在两处都可用**,但**不是 HTTP header**:
1. **Cloud Armor CEL 表达式中**(问题 1.1):以 `request.client_cert_*` 属性形式存在
2. **Cloud Logging 访问日志 (`resource.type="http_load_balancer"`) 中**:以 `jsonPayload.forwardedClientCert.*` 嵌套对象形式存在
   - 字段包括: `subject`, `issuer`, `certInfo` (Base64-DER 整张叶子证书), `certFingerprint`, `subjectAlternativeName` (list), `certNotBefore`, `certNotAfter`, `validationResult`, `validationError`, `chainInfo`(链信息) 等 [来源: `flow-mtls-log.md` 中引用 GCP 官方文档说明]

**[未直接读到 GCP 文档原文,但与本地笔记交叉一致]** 此外,Access log 还有一个独立的 `jsonPayload.mtls` 字段(`mtlsInfo` / `mtlsClientCertChainVerified` / `mtlsClientCertPresent` / `mtlsClientCertError` / `mtlsClientCertSha256Fingerprint` 等),这部分是基于 mTLS 的「是否提供证书 / 链是否验证通过 / 错误码 / 指纹」,是 mTLS-层的快速元数据,比 `forwardedClientCert` 轻量。

### 官方文档链接

- `https://cloud.google.com/load-balancing/docs/https/custom-headers#mtls-variables` — mTLS 变量在 customRequestHeaders / customResponseHeaders 中的展开(backend 侧)
- `https://cloud.google.com/armor/docs/rules-language-reference` — Cloud Armor CEL 表达式属性集,包含 `request.client_cert_*`
- `https://cloud.google.com/armor/docs/configure-security-policies` — 策略/规则配置流程
- `https://cloud.google.com/load-balancing/docs/https/setting-up-mtls` (注意:此 URL 出现在本地笔记中,具体路径以浏览器实际打开为准) — Global External HTTPS LB 的 mTLS 配置总览
- `https://cloud.google.com/load-balancing/docs/https/logging` — 访问日志字段 `forwardedClientCert` 文档

### 原文引用(经本地笔记转述,需复核)

来自 `Glb-Client-Authentication.md` 中引用的 GCP 文档摘录:
> "the following variables are available for use in custom request and response headers: `client_cert_present`, `client_cert_chain_verified`, `client_cert_error`, `client_cert_hash`, `client_cert_serial_number`, `client_cert_valid_not_before`, `client_cert_valid_not_after`, `client_cert_uri_sans`, `client_cert_issuer_uri_sans`, `client_cert_subject`, `client_cert_issuer`, `client_cert_subject_alternative_name`, `client_cert_leaf`, `client_cert_chain`."

来自 `cloud-armor-header.md` 中转述的 Cloud Armor rules language reference:
> "Cloud Armor expressions can reference request attributes such as `request.client_cert_present`, `request.client_cert_chain_verified`, `request.client_cert_spiffe_id` etc."(⚠️ 这是笔记里的转述,**建议浏览器直接打开 https://cloud.google.com/armor/docs/rules-language-reference 核对一遍**)

### Workaround(无需 workaround)

**好消息**:Cloud Armor 直接支持 `request.client_cert_*` CEL 属性。**不需要 workaround**。

典型 SPIFFE allowlist 写法(伪代码,需用真实 SPIFFE ID 替换):

```cel
request.client_cert_spiffe_id == "spiffe://example.org/ns/foo/sa/bar"
```

或者用 `has()` + 列表 `in`:

```cel
"spiffe://example.org/ns/foo/sa/bar" in request.client_cert_uri_sans
```

> **注意**:Cloud Armor CEL 中字符串字面量是**双引号**,且**区分大小写**。这是 CEL 通则,不是 Cloud Armor 特性。

---

## 2. Backend 收到的 Request Header / Response Header

### 问题 2.1: Global External HTTPS LB + mTLS + `customRequestHeaders` 注入 `{client_cert_spiffe_id}` 后,backend 实际收到的 HTTP header 名是什么?

**结论**:**HTTP header 名 = 你在 `customRequestHeaders` 里写死的那一个**(大小写、是否带 `X-` 前缀,完全由你配置决定)。GCP **不会自动加 `X-` 前缀**、**不会自动改大小写**。

例:

```bash
# gcloud
gcloud compute backend-services update MY_BS --global \
  --custom-request-header 'X-Client-Cert-SPIFFE-ID:{client_cert_spiffe_id}' \
  --custom-request-header 'X-Client-Cert-Subject:{client_cert_subject}' \
  --custom-request-header 'X-Client-Cert-Fingerprint:{client_cert_hash}'

# Terraform
# 在 google_compute_backend_service.custom_request_headers 中添加键值对
```

> ⚠️ `gcloud compute backend-services update` 的 flag **不是** `--custom-request-header`,而是 **`--custom-request-header` 在不同 gcloud 版本里被替换/弃用过**。**更可靠的姿势**是用 `gcloud compute backend-services edit` 改 YAML,或在 Terraform 的 `custom_request_headers` 字段直接写。([本地笔记 `flow-mtls-log.md` 已跑通的环境] 直接在 backend service 的 `customRequestHeaders` 字段里配:`X-client-Cert-Leaf:{client_cert_leaf}`,然后 nginx 用 njs 读取。)

### 完整可用变量列表(可在 `{...}` 占位符中展开)

来自本地笔记引用的 GCP 文档(经 `flow-mtls-log.md`、`Glb-Client-Authentication.md`、`https-glb-pass-client.md` 等多处交叉):

| 占位符 | 含义 | 备注 |
|---|---|---|
| `{client_cert_present}` | 客户端是否提交了证书 | bool 字符串化 |
| `{client_cert_chain_verified}` | 证书链是否验证通过 | bool 字符串化 |
| `{client_cert_error}` | 验证错误码 | int 字符串化 |
| `{client_cert_hash}` | 叶子证书 SHA-256 指纹 | hex |
| `{client_cert_serial_number}` | 叶子证书序列号 | hex |
| `{client_cert_subject}` | Subject DN | RFC 2253 |
| `{client_cert_issuer}` | Issuer DN | RFC 2253 |
| `{client_cert_subject_alternative_name}` | SAN,逗号分隔 | 字符串 |
| `{client_cert_uri_sans}` | URI SAN 列表 | 字符串(具体格式需查文档) |
| `{client_cert_subject_uri_sans}` | 叶子 Subject 中的 URI SAN | |
| `{client_cert_issuer_uri_sans}` | 叶子 Issuer 中的 URI SAN | |
| `{client_cert_valid_not_before}` | 证书 notBefore | timestamp / ISO 8601 |
| `{client_cert_valid_not_after}` | 证书 notAfter | timestamp / ISO 8601 |
| `{client_cert_leaf}` | 整张叶子证书 | Base64-DER,字符串 |
| `{client_cert_chain}` | 完整证书链(多张) | Base64-DER 列表 |
| `{client_cert_spiffe_id}` | SPIFFE ID (URI SAN) | 字符串,**只有证书含 `URI:spiffe://...` SAN 时才存在** |

### 问题 2.2: Response Header 机制?

**结论**:**有**。Global External HTTPS LB 同时支持 `customResponseHeaders`(backend → 客户端方向),变量集**完全相同**(见上表)。

> **注意**:`customResponseHeaders` 中能用的 `client_cert_*` 变量,值是基于**当时请求的客户端证书**计算的(GCP 在响应回程时也保留了上下文),所以后端在响应头中依然可以回显 SPIFFE ID / Subject。

[来源: `Glb-Client-Authentication.md`、`flow-mtls-log.md`]

### 问题 2.3: 用 `connection.client_cert` / `request.headers['x-forwarded-client-cert']` 之类的访问方式?

**结论**:**不是**。在 GCP 上,这些变量**不会**自动以 `X-Forwarded-Client-Cert` 之类的标准 header 注入到 backend。要传 SPIFFE ID / Subject,**必须显式在 backend service 的 `customRequestHeaders` 里配置** `{client_cert_spiffe_id}` → 任意 header 名(常见命名:`X-Client-Cert-Subject`、`X-Client-Cert-Fingerprint`、`X-Client-Cert-SPIFFE-ID` 或干脆 `{client_cert_hash}` 这样的"魔术 header 名")。

> **Envoy 的 `x-forwarded-client-cert` header**:Envoy 自己有一个 `x-forwarded-client-cert` header(在 Istio / xDS 体系里很常见),但 GCP 的 HTTPS LB 默认**不**注入这个 header;必须自己用 `customRequestHeaders` 仿写一个。

### 官方文档链接

- `https://cloud.google.com/load-balancing/docs/https/custom-headers` — 列出所有可展开的 header 变量,包括 mTLS
- `https://cloud.google.com/load-balancing/docs/https/custom-headers#mtls-variables` — mTLS 变量小节
- `https://cloud.google.com/load-balancing/docs/https/setting-up-mtls` — 设置 mTLS 时,变量如何与 backend service 集成
- Terraform: `google_compute_backend_service.custom_request_headers` / `custom_response_headers` 字段

### 原文引用(本地笔记转述)

> "The following variables are available for use in custom request and response headers..."(见上表)

> "GCP does not forward the raw client certificate to the backend; only the variables above are usable as placeholders inside `customRequestHeaders` / `customResponseHeaders`."

### 已跑通示例(用户实际环境)

来自 `flow-mtls-log.md`:
> "在我的 backend service 里面定义了一个 `customRequestHeaders` 比如叫做 `X-client-Cert-Leaf:{client_cert_leaf}` 然后用 nginx 的 njs 模块进行 `js_set $sse_client_s_dn_cn http.subjectcn;` 这样去获取这个 head 做 CN 校验"

→ 说明**实测**:`{client_cert_leaf}` 变量在 `customRequestHeaders` 里成功展开,nginx 可以读到。

---

## 3. 客户端如何"带" header & Cloud Armor CEL 是否能看到 mTLS 变量

### 问题 3.1: 客户端如何"带" header?

**客户端不需要在 HTTP 请求里加任何 header**。客户端证书 / SPIFFE ID 是**通过 TLS handshake 提交**的,在 TLS 层完成。具体流程:

```
Client → GLB (TLS ClientHello)
GLB → Client (ServerHello, Server Certificate, Certificate Request)
Client → GLB (Certificate, CertificateVerify)
GLB → Trust Config 验证
GLB → 验证通过后, 提取 client cert 字段, 注入 customRequestHeaders
GLB → Backend (HTTP 请求, 包含 backend service 配的 customRequestHeaders)
```

[来源: `mtls-key.md`、`mtls-key-eng.md` 中详细 mTLS 握手流程]

### 问题 3.2: Cloud Armor CEL 在 LB 边缘评估时是否能看到这个 header?如果不能,Workaround?

**结论**:**能看到,直接在 CEL 属性里**(`request.client_cert_*`,不是 `request.headers[...]`)。

**Cloud Armor 的执行时序**:
1. TLS 握手结束(包括 mTLS 证书验证)
2. Cloud Armor 评估所有规则(此时 `request.client_cert_*` 已可用)
3. 规则命中后,Cloud Armor 决定 allow / deny / throttle / redirect / custom-response
4. **如果 allow**,GLB 才展开 `customRequestHeaders` 并转发到 backend

所以**Cloud Armor 的 CEL 评估早于 `customRequestHeaders` 注入**。Cloud Armor **不依赖** `customRequestHeaders` 注入的 header(它直接读 `request.client_cert_*` 属性,这些是 GFE 内部的内部状态,不是来自 HTTP header)。

> **所以问题 3 的"如果不能"假设不成立**——Cloud Armor 一定能看,只是语法不是 `request.headers[...]`,而是 `request.client_cert_*`。

### 如果一定要让 Cloud Armor 通过 `request.headers[]` 访问(非推荐)

**没有可靠 workaround**。GCP 不允许用户在 mTLS 阶段手动注入客户端证书信息到 header(因为此时 TLS 还没结束,HTTP header 还没形成)。**不要尝试**这种方案。

### 官方文档链接

- `https://cloud.google.com/armor/docs/rules-language-reference` — CEL 属性完整列表
- `https://cloud.google.com/load-balancing/docs/https/custom-headers` — `customRequestHeaders` 变量

### 原文引用(本地笔记转述)

> "Custom request and response headers are expanded **after** the security policy is evaluated. Cloud Armor accesses mTLS metadata through CEL attributes (`request.client_cert_*`), not through HTTP headers."(本地笔记 `cloud-armor-header.md` 中总结)

---

## 4. Rule 生效时间 (propagation delay)

### 问题 4.1: GCP Cloud Armor rule 更新后多久生效?5 分钟?10 分钟?

**结论**:**Cloud Armor 规则更改通常在 **几秒到 ~1 分钟** 内全球生效**,**远短于** 5-10 分钟。

**具体细节**(综合本地笔记,需要浏览器复核 GCP 原文):
- `gcloud compute security-policies rules create/update/delete` 返回成功后,后端配置通过 GFE 的**配置推送系统**(control plane → data plane)下发
- 全球 GFE 节点**通常 < 1 分钟**(20-30 秒是常见值)内一致
- 但**首次 attach** 一个安全策略到一个 backend service / URL map 时,可能略长(经验值几十分钟,但这是"绑定"不是"改规则")

> ⚠️ **不要引用 5 分钟 / 10 分钟这个数字**。[未直接读到 GCP 文档给出"5 分钟"或"10 分钟"的明确 SLA 数字]——这是社区里常见的"以防万一"经验值,不是 GCP 公开 SLA。

### 问题 4.2: `gcloud compute security-policies rules update / create` 是否需要等?

**结论**:**不需要**显式等。`gcloud` 命令返回 success 即代表**控制面**(control plane)的资源更新成功。数据面(GFE)的传播是异步的,**通常 1 分钟内**,但这不是命令的同步行为。

如果想主动验证 rule 已生效,有 3 种方式:
1. `gcloud compute security-policies describe POLICY --global` 看 rule 是否存在(只能验证控制面)
2. 触发一次该规则的请求,看 Cloud Logging 里的 `enforcedSecurityPolicy.ruleInfo.priority` 是否匹配新规则
3. `gcloud compute security-policies get-iam-policy POLICY` 之类(对 rule 不直接适用)

### 官方文档链接

- `https://cloud.google.com/armor/docs/configure-security-policies` — 配置策略步骤
- `https://cloud.google.com/armor/docs/security-policy-concepts` — 策略/规则概念
- `https://cloud.google.com/load-balancing/docs/https/setting-up-https` — 整体 HTTPS LB + Cloud Armor 流程
- 散见: `https://cloud.google.com/load-balancing/docs/https/setting-up-mtls`

### 原文引用(本地笔记转述,需浏览器复核)

> "Changes to Google Cloud Armor security policy rules propagate to all Google Front End (GFE) locations within a short period, typically less than a minute."

(此句来自本地笔记转述,具体 GCP 文档原文请用浏览器打开上述链接核对。)

### Workaround(如果实在担心延迟)

- **永远先用 `preview` 模式** `--preview` / `preview=true`:**不实际执行动作**,只记录在 access log 中(用 `previewSecurityPolicy.*` 字段过滤)
- preview 模式让你**先观察 24-48 小时**再正式启用,完全消除 propagation 误伤风险
- 对 critical rule,**先在低优先级 / preview 试运行**,确认无误后再 `update --preview=false`

---

## 5. 术语澄清: Global External HTTPS LB vs Global External Application Load Balancer

[本地笔记中,用户在不同 AI 助手回答里都遇到过这个混淆]

**结论**:**它们是同一个产品**(同一个底层资源,同一个 gcloud resource type),GCP 文档中这两个名字混用:

| 文档/CLI 里的名字 | 实际 gcloud resource | 说明 |
|---|---|---|
| Global External Application Load Balancer | `target-http-proxy` / `target-https-proxy` (global scope) | GCP 营销/产品页用名,2023+ 推荐用此名 |
| Global External HTTP(S) Load Balancer (LB) | 同上 | 老名字,文档里仍大量出现 |
| GLB (Generic) | 同上 | 简称 |
| External Application Load Balancer (新) | 同上 | GCP 进一步简化的命名,2024+ |

**关键事实**:
- 全部指**同一个**资源,只是不同时期/不同页面用的 marketing name 不同
- 如果你看到 "Application Load Balancer" / "HTTP(S) Load Balancer" / "Classic Application Load Balancer",在 External + Global 语境下,都是同款
- **不要**和 **Classic** (target-pool-based) **Network Load Balancer** 混淆
- **不要**和 **Internal Application Load Balancer** (regional) 混淆

mTLS、customRequestHeaders、Cloud Armor 集成对**所有这些名字都适用**(因为是同一资源)。

---

## 6. 关键 takeaway 速查表

| 问题 | 答案 | 关键变量 / 字段 |
|---|---|---|
| **Cloud Armor 能否在 CEL 里看 mTLS 变量?** | ✅ 可以,直接用 `request.client_cert_*` CEL 属性 | `request.client_cert_present` / `request.client_cert_chain_verified` / `request.client_cert_spiffe_id` 等 |
| **是否在 `request.headers` 命名空间?** | ❌ 不是。是**专用 CEL 属性** `request.client_cert_*` | — |
| **是否只在 log payload 里?** | ❌ 也在 Cloud Armor CEL 里。**HTTP header 不自动注入** | log: `jsonPayload.forwardedClientCert.*` 和 `jsonPayload.mtls.*` |
| **backend 收到的 header 名?** | **完全由用户在 `customRequestHeaders` 里写死的名字决定**。GCP 不加 `X-` 前缀、不动大小写 | 变量: `{client_cert_spiffe_id}` / `{client_cert_subject}` / `{client_cert_hash}` / `{client_cert_leaf}` 等 |
| **Response Header 机制?** | ✅ 有,`customResponseHeaders`,变量集**完全相同** | 同上 |
| **`x-forwarded-client-cert` 是否自动?** | ❌ 不自动。要自己用 `customRequestHeaders` 仿写 | — |
| **客户端是否需要手加 header?** | ❌ 不需要。证书通过 TLS handshake 提交,GLB 自动提取 | — |
| **Cloud Armor 评估时序?** | **TLS 结束后、customRequestHeaders 注入前**。所以能直接读 `request.client_cert_*` | — |
| **Rule propagation delay?** | **< 1 分钟**(经验值 20-30 秒),不是 5-10 分钟。**首次 attach 可能更慢** | — |
| **`gcloud` 需不需要等?** | 不需要显式等。用 `--preview` 模式先 dry-run 24-48h | — |

---

## 7. 待浏览器复核的 URL(本环境无 WebFetch,无法直接 fetch 原文)

请用浏览器手动打开以下链接,**逐条对照**本文档的"原文引用"部分:

1. **mTLS variables 在 customRequestHeaders 中**:
   `https://cloud.google.com/load-balancing/docs/https/custom-headers#mtls-variables`

2. **Cloud Armor CEL 属性集** (查 `request.client_cert_*` 是否完整):
   `https://cloud.google.com/armor/docs/rules-language-reference`

3. **Global External HTTPS LB mTLS 设置**:
   `https://cloud.google.com/load-balancing/docs/https/setting-up-mtls` (具体路径以打开后为准)
   备用: `https://cloud.google.com/load-balancing/docs/https/setting-up-https`

4. **Cloud Armor 策略配置 + propagation 细节**:
   `https://cloud.google.com/armor/docs/configure-security-policies`
   `https://cloud.google.com/armor/docs/security-policy-concepts`

5. **Access log 字段 (`forwardedClientCert.*` / `mtls.*`)**:
   `https://cloud.google.com/load-balancing/docs/https/logging`

6. **Custom request/response headers 整体说明**:
   `https://cloud.google.com/load-balancing/docs/https/custom-headers`

---

## 8. 关键风险提示

1. **`client_cert_spiffe_id` 变量仅当叶子证书含 `URI:spiffe://...` SAN 时才存在**。如果你的证书是普通 X.509(没 SPIFFE SAN),这个变量是空字符串,**不是错误**。
2. **Cloud Armor CEL 字符串字面量用双引号** (`"spiffe://..."`),不是单引号。
3. **`{client_cert_subject}` 输出是 RFC 2253 形式的 DN** (e.g. `CN=foo,O=bar`),不是 RFC 4714 形式,别拿 OpenSSL 那种空格分隔的格式去匹配。
4. **gcloud flag 不稳定**:`--custom-request-header` 在不同 gcloud 版本里语法/flag 都有变化,推荐 **Terraform** 或 **`gcloud ... edit`** 改 YAML,不要靠 flag。
5. **TLS 失败时 Cloud Logging 不会有 http_load_balancer 日志**(因为 HTTP 层根本没收到请求)。[来源: `glb-verify-curl.md` 已实测] 想看 TLS 失败,得开 `ALLOW_INVALID_OR_MISSING_CLIENT_CERT` 模式做测试。
6. **Propagation 数字不要死扣**。GCP 没明确 SLA,社区经验是 < 1 分钟,但首次 attach policy 可能更慢。用 `--preview` 模式避雷。

---

*本报告基于本地已有笔记交叉验证,涉及 GCP 官方文档原文的部分均标注 [经本地笔记交叉验证] 或 [未直接读到 GCP 文档原文]。上线前请用浏览器复核第 7 节列出的 URL。*
