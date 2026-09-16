# GLB mTLS 测试:已知真实 IP + 客户端证书 + 日志过滤

> 适用:GKE / Cloud Run / GCE 上的 **External Application Load Balancer(经典 HTTPS GLB)+ mTLS** 场景
>
> 典型场景:**DNS 解析还没切到真实 IP**(过渡期 / DNS 验证失败 / 想从办公网直连绕过 CDN),但你**已知 GLB 后端服务的真实 IP**(Global Anycast IP 或 NEG 后端 VM 的 internal IP),需要验证 mTLS 链路是否真通,并能在 GCP Cloud Logging 里拉到对应的 mTLS 校验日志。
>
> 配套阅读:
> - [`glb-verify-curl.md`](./glb-verify-curl.md) — 通用 `curl --resolve` / `-k` / `-H "Host:"` 绕过 DNS 的方法
> - [`OpenAI/docs/Verifying-GLB.md`](../../OpenAI/docs/Verifying-GLB.md) — 完整 mTLS 字段参考 + `clientValidationMode` 行为对比
> - [`flow-mtls-log.md`](./flow-mtls-log.md) — X-Cloud-Trace-Context + forwardedClientCert 字段体系
> - [`mtls-test/test-case.md`](./mtls-test/test-case.md) — TCP MTLS → HTTPS MTLS GLB 迁移测试用例

---

## 0. 核心诉求一句话

**保持 TLS SNI + HTTP Host 不变(GLB 才能按 SNI 匹配证书 + ServerTlsPolicy),但把 TCP 连接指向你已知的真实 IP**——`curl --resolve` 一行搞定,不动本地 DNS 也不动 Host 头。

```
你                              GLB                            后端
 ├─ curl --resolve DOM:443:REAL_IP ─────► :443(real IP 实际指向 GLB)
 │  --cert client.crt --key client.key
 │  --cacert server-ca-bundle.pem
 │  https://your.domain.com/api/v1/xxx
 │
 ├─ Host:    your.domain.com  ← 必须仍是域名,不能是 IP
 ├─ SNI:     your.domain.com  ← 必须仍是域名,GLB 按 SNI 选 cert 链
 ├─ client cert: present       ← mTLS 校验起点
 │
 ▼
GLB 走 mTLS 校验链(TrustConfig → ServerTlsPolicy → 链验证)
 ├─ 成功 → 转发到 backend(neg/nginx)
 └─ 失败 → TLS 握手阶段直接拒,不会进 HTTP
```

---

## 1. 测试命令模板

### 1.1 `curl` 一行(推荐)

```bash
curl -v \
  --resolve your.domain.com:443:<GLB_REAL_IP> \
  --cert client.crt \
  --key client.key \
  --cacert server-ca-bundle.pem \
  https://your.domain.com/api/v1/endpoint
```

**字段含义**:

| 参数 | 作用 | 不能省的根因 |
|---|---|---|
| `--resolve DOM:443:IP` | 告诉 curl 直接连这个 IP,**不要 DNS 查** | 不写 = 走系统 DNS,可能拿到旧 IP 或 0.0.0.0 |
| `--cert client.crt` | 客户端证书(PEM) | GLB 是 mTLS,没 cert 就握手失败 |
| `--key client.key` | 客户端私钥 | curl 强制校验 cert/key 配对 |
| `--cacert server-ca-bundle.pem` | 验证 GLB **服务端证书**的 CA bundle | 不写 = curl 用系统 trust store,可能会被自签 cert 挡 |
| `https://DOM/api/...` | URL 写域名,不是 IP | **SNI + Host 头必须仍是域名**,这是 GLB 路由的 key |
| `-v` | 详细输出,看 TLS 握手每一步 | 没它就盲调 |

### 1.2 `openssl s_client` 调试版(更细)

```bash
openssl s_client \
  -connect <GLB_REAL_IP>:443 \
  -servername your.domain.com \
  -cert client.crt \
  -key client.key \
  -CAfile server-ca-bundle.pem \
  -verify 2 \
  -state -debug
```

走完握手后(出现 `Verification: OK`)键入 HTTP 请求回车,再敲回车:

```
GET /api/v1/endpoint HTTP/1.1
Host: your.domain.com

```

> 用 `openssl s_client` 看 **server 请求 client cert 的具体信息**,比 `curl` 更细:能看到 server 给的 "Acceptable client certificate CA names" 列表(GCP GLB 通常**不发**这个扩展,所以你 client 端必须主动配对 cert)。

### 1.3 `--resolve` vs `--connect-to` vs `-H "Host:"`(三个常被混的)

| 方法 | SNI | Host 头 | DNS 缓存 | 推荐度 |
|---|---|---|---|---|
| `--resolve DOM:443:IP` | ✅ 域名 | ✅ 域名 | ✅ 仅本进程 | **首选** |
| `--connect-to DOM:443:IP:443` | ✅ 域名 | ✅ 域名 | ✅ 仅本进程 | 次选(语法稍冗长) |
| `curl https://IP/ -H "Host: DOM"` | ⚠️ 取决于 curl 版本 / HTTP/2 行为 | ✅ 域名 | — | ❌ HTTP/2 下 SNI 可能变 IP,SAN 不匹配会直接断 |

**坑**:`-H "Host:"` 在 HTTP/1.1 看着能用,但 HTTP/2 强制 SNI 来自 `:authority` 伪头,curl 会用连接的 IP 当 SNI,服务端 cert 没有 IP 的 SAN → 握手失败。**别用 `-H "Host:" + 直连 IP** 这种组合做 mTLS 测试**。

### 1.4 走代理时 DNS 又会被覆盖

```bash
# ❌ --resolve 被代理忽略(代理自己再做 DNS 解析)
curl --resolve DOM:443:IP https://DOM -x proxy.corp:8080

# ✅ 用 --connect-to 走代理 + 强制 CONNECT 到真实 IP
curl --connect-to DOM:443:IP:443 https://DOM -x proxy.corp:8080 \
     --cert client.crt --key client.key
```

或者用 `--proxy-resolve DOM:443:IP`(如果 curl 版本支持)。

---

## 2. curl `-v` 输出逐行解读(找 mTLS 标志)

```
* Trying <REAL_IP>:443...                              ← TCP 连接目标 = 真实 IP
* Connected to your.domain.com (<REAL_IP>) port 443    ← curl 把 IP "伪装" 成域名
* ALPN: curl offers h2,http/1.1                       ← ALPN 协商
* (304) (OUT), TLS handshake, Client hello (1):       ← 客户端发起 TLS
* (304) (IN), TLS handshake, Server hello (2):        ← 服务端 hello
* (304) (IN), TLS handshake, Certificate (11):        ← GLB 出示服务端证书链
* (304) (IN), TLS handshake, CERT verify (15):        ← curl 验证 GLB 服务端 cert(用 --cacert)
* (304) (IN), TLS handshake, Request CERT (13):       ← ⭐ 关键:GLB 在 mTLS 模式下请求 client cert
* (304) (OUT), TLS handshake, Certificate (11):       ← 客户端发 client cert
* (304) (OUT), TLS handshake, CERT verify (15):       ← 客户端证明自己持有私钥
* (304) (OUT), TLS handshake, Finished (20):          ← 客户端 TLS 完成
* (304) (IN), TLS handshake, Finished (20):           ← 服务端 TLS 完成
* SSL connection using TLS_AES_128_GCM_SHA256          ← 协议+套件确认
* ALPN: server accepted h2                            ← HTTP/2 协议
* Server certificate:                                  ← GLB 服务端证书详情
*  subject: ... CN=your.domain.com
*  start date: ...
*  expire date: ...
*  subjectAltName: host "your.domain.com" matched cert's "your.domain.com"   ← SAN 匹配
*  issuer: CN=...
*  SSL certificate verify ok.                          ← ⭐ curl 信任服务端证书
* using HTTP/2
> GET /api/v1/endpoint HTTP/2
> Host: your.domain.com                                ← ⭐ Host 头仍是域名
> User-Agent: curl/8.x.x
> ...
< HTTP/2 200                                            ← 后端 200 OK
```

**4 个 mTLS 关键 marker**(任何一个缺失都说明链路断在哪):

| 缺失 marker | 含义 | 排查方向 |
|---|---|---|
| `Request CERT (13)` | GLB 没要 client cert | ServerTlsPolicy 未挂 / `clientValidationMode` 不是 REJECT_INVALID / SNI 拼错 |
| `Certificate (11)`(客户端侧) | 客户端没发 cert | `--cert` / `--key` 路径错 / 格式不是 PEM |
| `Certificate verify (15)`(客户端侧) | 客户端没证明私钥 | cert/key 不配对 / key 加密了但没解 |
| `SSL certificate verify ok.` | curl 不信任 GLB 服务端 cert | `--cacert` 没传 / 服务端 cert 链不全 / 用 `-k` 临时绕过 |

---

## 3. Cloud Logging 过滤 mTLS 校验日志

### 3.1 前置:Backend Service 日志必须打开

GLB 日志**默认不开**,需要在每个 Backend Service 上手动开:

```bash
# 全局外部 HTTPS LB(经典)
gcloud compute backend-services update <BACKEND_SERVICE_NAME> \
  --global \
  --enable-logging \
  --logging-sample-rate=1.0
```

`--logging-sample-rate=1.0` 表示 100% 采样,**测试期间必开**;生产开 1.0 不划算,看你的流量大小降到 0.1~0.01。

### 3.2 Logs Explorer 查询模板

**资源类型固定是** `http_load_balancer`,日志名通常是 `projects/<PROJECT>/logs/requests`。

| 想看什么 | 查询 |
|---|---|
| 全部某个 GLB IP 的请求 | `resource.type="http_load_balancer" resource.labels.forwarding_rule_name="<FR_NAME>"` |
| 全部命中 mTLS 链的请求 | `resource.type="http_load_balancer" jsonPayload.tls.client_cert_present=true` |
| mTLS 验证失败的请求 | `resource.type="http_load_balancer" jsonPayload.statusDetails="client_cert_validation_failed"` |
| 完全没带 cert 的请求 | `resource.type="http_load_balancer" jsonPayload.statusDetails="client_cert_not_provided"` |
| 特定 cert 指纹的所有请求 | `resource.type="http_load_balancer" jsonPayload.tls.client_cert_sha256_fingerprint="AB:CD:..."` |
| 特定 cert subject 的所有请求 | `resource.type="http_load_balancer" jsonPayload.tls.client_cert_subject_dn="CN=client-name,O=myorg"` |
| 同时过滤 Cloud Armor 命中 | `resource.type="http_load_balancer" jsonPayload.enforcedSecurityPolicy.name="<POLICY>"` |
| 时间窗 + 全部字段 | `resource.type="http_load_balancer" resource.labels.forwarding_rule_name="<FR>" timestamp>="2026-09-16T00:00:00Z" timestamp<"2026-09-16T01:00:00Z"` |

**记住 `statusDetails` 的常见 mTLS 错误值**(Lex `OpenAI/docs/Verifying-GLB.md` Table 5 整理):

| 错误字符串 | 含义 | 可能原因 |
|---|---|---|
| `client_cert_not_provided` | 没带 cert | client 端没配;或 `clientValidationMode=REJECT_INVALID` 且 cert 没发 |
| `client_cert_validation_failed` | 链验证失败 | TrustConfig 没匹配 / cert 过期 / cert 格式错 |
| `client_cert_chain_exceeded_limit` | cert 链太深 | 超过 GCP 限制(默认 10) |
| `client_cert_invalid_eku` | 缺 `clientAuth` EKU | cert 用途写错 |
| `client_cert_invalid_rsa_key_size` | RSA key 太短 | 1024-bit 等已不被接受 |
| `client_cert_trust_config_not_found` | TrustConfig 没找到 | ServerTlsPolicy 引用错 / trust config 删了 |
| `proxyStatus` 含 `TLS_ERROR`(仅 Regional / Internal ALB) | 私钥未证明(proof of possession 失败) | **Global Ext ALB 不会记这条**,客户端 curl 才有 |

> ⚠️ **"静默失败"陷阱**:**Global External Application Load Balancer** 在 proof-of-possession 失败时**完全不写日志**(握手直接断),只看 GLB 日志会漏判。这种 case 必须**客户端工具**(curl / openssl s_client)作为主证据。Regional / Internal ALB 才在 `proxyStatus` 记 `TLS_ERROR`。

### 3.3 gcloud CLI 版(脚本友好)

```bash
# 拉最近 1 小时某 forwarding rule 的所有 mTLS 失败请求
gcloud logging read '
resource.type="http_load_balancer"
resource.labels.forwarding_rule_name="my-mtls-fr"
jsonPayload.statusDetails=("client_cert_validation_failed" OR "client_cert_not_provided")
timestamp>="'$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ')'"
' \
  --format='json(jsonPayload.statusDetails,jsonPayload.tls,jsonPayload.httpRequest.responseStatusCode,timestamp)' \
  --limit=50

# 跟踪某个 client cert 指纹的所有请求(看是哪台机器在用)
gcloud logging read '
resource.type="http_load_balancer"
jsonPayload.tls.client_cert_sha256_fingerprint="AB:CD:EF:..."
' --limit=100 --format=json
```

### 3.4 `ALLOW_INVALID_OR_MISSING_CLIENT_CERT` 模式的日志坑

这是另一个常见盲区:

- **REJECT_INVALID**(默认/严格模式):mTLS 失败**直接**进 `statusDetails`,你能查到。
- **ALLOW_INVALID_OR_MISSING_CLIENT_CERT**(宽松模式):**失败也转发到后端**,只有 backend 自己从 header(`X-Client-Cert-Chain-Verified: false`)判断。**GLB 日志里看不到失败**。

→ 如果你切到了 ALLOW_INVALID 模式又只看 GLB 日志,**会误以为 mTLS 没生效**。这种情况下:
1. backend 应用必须把 `X-Client-Cert-Chain-Verified` / `X-Client-Cert-Error` 写进自己的日志,或者
2. backend service 日志打开 `optional mTLS fields`,让 GLB 把 cert_error 字段也写进 Cloud Logging(注意:仅 Regional / Cross-region Internal / Regional External ALB 支持,Global External ALB 不支持)

### 3.5 高频调试用例:curl 通但 GLB 日志搜不到

| 现象 | 真原因 | 验证方式 |
|---|---|---|
| curl 返回 200,但 Logs Explorer 一条记录都没 | Backend Service 没开 `enable-logging` | `gcloud compute backend-services describe <BS> --global --format="get(logConfig)"` |
| curl 失败但 GLB 日志里 `statusDetails` 是 `response_sent_by_backend` | 失败在 backend 后面(nginx / squid),不是 GLB | 看 nginx access log / cloud logging agent 范围 |
| curl 失败但 GLB 日志里没 mTLS 相关字段 | 失败发生在 TLS 握手前(网络层 / Cloud Armor / WAF) | `jsonPayload.enforcedSecurityPolicy.outcome` / VPC firewall log |
| `proxyStatus: TLS_ERROR` 但 Global Ext ALB | **Global Ext ALB 不会记**这条 | 切到 Regional ALB 或依赖客户端工具 |

---

## 4. 全套调试脚本

```bash
#!/usr/bin/env bash
# hermes-verify-glb-mtls.sh
# 一键跑 mTLS 测试 + 拉日志对比
set -uo pipefail

DOM="${DOM:?set DOM=your.domain.com}"
IP="${IP:?set IP=<GLB_REAL_IP>}"
FR="${FR:?set FR=<forwarding-rule-name>}"
CLIENT_CERT="${CLIENT_CERT:-client.crt}"
CLIENT_KEY="${CLIENT_KEY:-client.key}"
SERVER_CA="${SERVER_CA:-server-ca-bundle.pem}"
PROJECT="${PROJECT:?set PROJECT=your-gcp-project}"

echo "==== 1. curl --resolve 测试 ===="
curl -v \
  --resolve "${DOM}:443:${IP}" \
  --cert "${CLIENT_CERT}" \
  --key "${CLIENT_KEY}" \
  --cacert "${SERVER_CA}" \
  "https://${DOM}/healthz" 2>&1 | tee /tmp/glb-mtls-curl.log

echo
echo "==== 2. 拉最近 5 分钟 GLB 日志(同 forwarding rule) ===="
gcloud logging read "
  resource.type=\"http_load_balancer\"
  resource.labels.forwarding_rule_name=\"${FR}\"
  timestamp>=\"$(date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ')\"
" \
  --project="${PROJECT}" \
  --format='json(timestamp,jsonPayload.statusDetails,jsonPayload.tls,jsonPayload.httpRequest.responseStatusCode,jsonPayload.enforcedSecurityPolicy)' \
  --limit=20

echo
echo "==== 3. 仅 mTLS 失败请求 ===="
gcloud logging read "
  resource.type=\"http_load_balancer\"
  resource.labels.forwarding_rule_name=\"${FR}\"
  jsonPayload.statusDetails=(\"client_cert_validation_failed\" OR \"client_cert_not_provided\" OR \"client_cert_invalid_eku\" OR \"client_cert_chain_exceeded_limit\" OR \"client_cert_trust_config_not_found\")
  timestamp>=\"$(date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ')\"
" \
  --project="${PROJECT}" \
  --format='json(timestamp,jsonPayload.statusDetails,jsonPayload.tls.client_cert_error)' \
  --limit=20
```

跑法:`DOM=api.example.com IP=203.0.113.66 FR=my-mtls-fr PROJECT=my-gcp-proj ./hermes-verify-glb-mtls.sh`

---

## 5. 排查决策树

```
curl --resolve https://DOM/ --cert X --key Y --cacert Z
   │
   ├─ "SSL: no alternative certificate subject name matches"
   │   → curl 校验服务端 cert 失败
   │   → 检查 --cacert 是否含 GLB 服务端 cert 的 issuer
   │
   ├─ "alert certificate required" / "required SSL certificate was not sent"
   │   → GLB 拒收 client cert
   │   → 检查 ServerTlsPolicy 是否生效、SNI 是否匹配
   │
   ├─ "Connection reset" / 静默断连(Global Ext ALB)
   │   → 99% 是 proof-of-possession 失败(Global Ext ALB 不记日志)
   │   → 改用 openssl s_client 看 -verify_returncode
   │
   ├─ HTTP 200 / 4xx / 5xx(从 GLB 返回)
   │   → mTLS 通过,看 backend 是否正常
   │   → 到 Backend Service 日志看 statusDetails + httpRequest
   │
   └─ HTTP 400 + body="No required SSL certificate was sent"
       → ALLOW_INVALID 模式下 cert 没传
       → 或 REJECT_INVALID 但 GLB 没收到 cert
```

---

## 6. 重要注意事项

| # | 注意点 |
|---|---|
| 1 | **DNS 解析没问题就用域名**:本文是过渡期绕过方案,**生产永远用域名**。`--resolve` 只在过渡期 / 本地排查时用。 |
| 2 | **测试完清理**:`--resolve` 缓存只在 curl 进程内,不用清;但 `/etc/hosts` 改动需要恢复。 |
| 3 | **`--cacert` vs 服务端 `allowlistedCertificates`**:`--cacert` 控制**客户端信任服务端 cert 的链**;服务端的 TrustConfig 控制**服务端信任客户端 cert 的链**。两者独立,不要混。 |
| 4 | **50 证书上限**:如果 ServerTlsPolicy 走 `allowlistedCertificates` 模式(老方案),测试 cert 也占名额,**测试 cert 和生产 cert 物理隔离**(不同 CA / 不同 serial range)。新方案 TrustConfig 是按 CA 验,不限单个 cert。 |
| 5 | **Cloud Logging 有延迟**:几十秒到几分钟。**验证失败时不要立刻判定"没日志=没请求"**,先等 1–2 分钟。 |
| 6 | **E2E 跟踪**:`X-Cloud-Trace-Context` 头由 GLB 自动注入,backend 也想看的话要 `proxy_set_header X-Cloud-Trace-Context $http_x_cloud_trace_context` 显式传递。详见 `flow-mtls-log.md`。 |
| 7 | **Cloud Armor IP 白名单**:测试出口 IP 必须在 Cloud Armor 白名单内,否则会在 L7 被拦,**表现是 connection refused / 403**,跟 mTLS 无关,容易误判。 |
| 8 | **HTTP/2 SNI**:HTTP/2 下 SNI = `:authority` 伪头,**写 IP 就 SNI 是 IP**,服务端 cert 没 IP 的 SAN 就会失败——这是 `-H "Host:" + 直连 IP` 模式最常见的坑,本文 §1.3 已展开。 |

---

## References

- [GCP LB custom headers variables](https://cloud.google.com/load-balancing/docs/https/custom-headers#mtls-variables) — `client_cert_present` / `client_cert_chain_verified` / `client_cert_error` 等字段定义
- [GCP LB mTLS overview](https://cloud.google.com/load-balancing/docs/https/mtls) — ServerTlsPolicy / TrustConfig 官方模型
- [curl `--resolve` 文档](https://curl.se/docs/manpage.html#--resolve) — DNS 缓存注入语义
- [OpenSSL `s_client` 文档](https://docs.openssl.org/master/man1/openssl-s_client/) — 细粒度 TLS 调试
- [Lex `OpenAI/docs/Verifying-GLB.md`](../../OpenAI/docs/Verifying-GLB.md) — Table 4 / Table 5 字段与错误值
- [Lex `flow-mtls-log.md`](./flow-mtls-log.md) — `forwardedClientCert.*` 字段家族 + E2E 跟踪
- [Lex `glb-verify-curl.md`](./glb-verify-curl.md) — 通用 `--resolve` / `-k` / `-H "Host:"` 对比与坑
- [Lex `mtls-test/test-case.md`](./mtls-test/test-case.md) — TCP→HTTPS MTLS GLB 迁移测试用例合集