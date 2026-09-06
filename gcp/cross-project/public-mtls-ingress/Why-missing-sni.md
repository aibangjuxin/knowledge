
- [Why missing sni](#why-missing-sni)
  - [2. 权威证据:GCP 官方关于 backend SNI 的行为](#2-权威证据gcp-官方关于-backend-sni-的行为)
    - [2.1 简化解释(架构师)](#21-简化解释架构师)
    - [2.2 严格原话(GCP 官方文档 — 原文引用)](#22-严格原话gcp-官方文档--原文引用)
    - [2.3 PSC NEG 的官方类别归属(GCP NEG 文档)](#23-psc-neg-的官方类别归属gcp-neg-文档)
  - [为什么会有这个问题](#为什么会有这个问题)
  - [修正方案(三选一)](#修正方案三选一)
    - [方案 1（推荐） K8s Gateway 不再按 hostname 做 listener 选择分流\*](#方案-1推荐-k8s-gateway-不再按-hostname-做-listener-选择分流)
    - [方案 2：如果业务上一定要在 K8s Gateway 保留第二层 TLS（纵深防御）](#方案-2如果业务上一定要在-k8s-gateway-保留第二层-tls纵深防御)
    - [方案 3: 在 Master K8s Gateway 前置 Nginx MIG 注入 SNI](#方案-3-在-master-k8s-gateway-前置-nginx-mig-注入-sni)
      - [方案三流程校验](#方案三流程校验)
      - [关于你的第二个问题：header 注入是否和 SNI 一样有问题](#关于你的第二个问题header-注入是否和-sni-一样有问题)
      - [关键澄清：Nginx 在这里的角色变了](#关键澄清nginx-在这里的角色变了)
      - [需要验证/落地的细节](#需要验证落地的细节)
        - [1. Nginx 配置示例（核心是 `proxy_ssl_name`）](#1-nginx-配置示例核心是-proxy_ssl_name)
        - [2. 你的 URI-SAN 精细化到 API 级别的思路是可行的，而且比纯 team 级更强](#2-你的-uri-san-精细化到-api-级别的思路是可行的而且比纯-team-级更强)
        - [3. 证书数量规模确认](#3-证书数量规模确认)
        - [综合结论](#综合结论)
- [📋 架构师审核总结(完整版,供 Lex 阅后采纳)](#-架构师审核总结完整版供-lex-阅后采纳)
  - [1. 内容准确性(✅ / ⚠️ / ❌)](#1-内容准确性--️--)
  - [2. 关键架构师 push back(给业务方的开放问题)](#2-关键架构师-push-back给业务方的开放问题)
    - [2.1 §方案 1 关键错误(必须纠正)](#21-方案-1-关键错误必须纠正)
    - [2.2 §方案 2 新前提(需要 Lex 答复)](#22-方案-2-新前提需要-lex-答复)
    - [2.3 §方案 3 与 ADR-014 关系](#23-方案-3-与-adr-014-关系)
  - [3. 拼写 / 术语统一清单(供 Lex 终稿时替换)](#3-拼写--术语统一清单供-lex-终稿时替换)
  - [4. 结构建议(为对齐 ADR-014 格式)](#4-结构建议为对齐-adr-014-格式)
  - [0. 一句话总结](#0-一句话总结)

# Why missing sni


> TLS 握手(ClientHello 里的 SNI)在 HTTP 请求被解析**之前**完成,而 `hostRewrite`(把 Host 重写成 `team1apiname.team1.intra.domain`)是**七层 HTTP Host/`:authority` 头**动作,发生在 URL Map 做完路由决策、请求已经从 GLB 转发给后端**之后**。这两件事根本不在同一个阶段:
>
> ```
> GLB 前端 mTLS 握手(SNI = tenantmtls.taobao.caep.uk,client 决定)
>    ↓ 终止 mTLS,解析 HTTP 请求
> URL Map 按 path 选 BS,做 hostRewrite(只改 HTTP Host header)
>    ↓ GLB 向后端发起【新的】TLS 连接
> GLB → 后端 TLS 握手(SNI 是什么? — 与 hostRewrite 无关,由 GLB 自行决定,可能为空 / PSC NEG endpoint IP / `tlsSettings.sni` 固定值)
> ```
>
> 所以:**`hostRewrite` 永远只能影响 HTTP Host header,改变不了 GLB 到后端这一跳新建 TLS 连接时发出的 SNI**。
>
> GCP 官方文档分别证实这两件事:
> 1. GLB 连接 Google Cloud 内的后端时,**只做最低证书验证**(默认接受任何后端证书,即使 hostname 不匹配)。
> 2. GLB 没有把原始 client SNI 透传给后端的能力。


默认情况下，GLB没法将 SNI 传递到 我的 k8s Gateway
GLB 在跟 PSC NEG 建立 backend TLS 握手时,不会透传客户端的 SNI 头
- https://docs.cloud.google.com/load-balancing/docs/ssl-certificates/encryption-to-the-backends
✅ URL 准确,这是 ADR-014 §3.1 来源 1 的同一个权威页面
```text
With the exception of HTTPS load balancers with internet NEG backends, load balancers don't use the Server Name Indication (SNI) extension for connections to the backend.
✅ 原文 + 中文翻译都准确,与 ADR-014 §2.2 严格原话版对齐。
```
- https://docs.cloud.google.com/load-balancing/docs/negs/internet-neg-concepts
⚠️ URL 路径需要现场核实:打开链接看是否 200。如果 404,改为父页面 https://cloud.google.com/load-balancing/docs/negs 的 § "SSL Server Name Indication (SNI) extension handling" 锚点。
```text
SSL Server Name Indication (SNI) extension handling
The SSL Server Name Indication (SNI) extension is only supported with INTERNET_FQDN_PORT endpoints. The configured FQDN is sent an SNI in the client hello during the SSL handshake between the load balancer and the external endpoint. The SNI isn't sent when you use an INTERNET_IP_PORT endpoint because IP address literals aren't allowed in the HostName field of an SNI payload.
SSL服务器名称指示（SNI）扩展处理
SSL服务器名称指示（SNI）扩展仅支持INTERNET_FQDN_PORT端点。在负载平衡器和外部端点之间的SSL握手期间，在客户端hello中向配置的FQDN发送SNI。当您使用INTERNET_IP_PORT端点时，不会发送SNI，因为SNI有效负载的HostName字段中不允许使用IP地址文字。
✅ 这段是 §2.3 "PSC NEG 不在 internet NEG 例外"的进一步细节 — 实际是 INTERNET_FQDN_PORT 才支持 SNI,INTERNET_IP_PORT 也不支持。
✅ 建议在引用下方加一行结论:"→ 业务方场景用 PSC NEG(`private-service-connect` 类型),既不是 INTERNET_FQDN_PORT 也不是 INTERNET_IP_PORT,SNI 完全不传递。"
✅ 润色建议(可选):中文翻译里"负载平衡器"统一改为"负载均衡器";"客户端hello"改为"ClientHello";"在客户端hello中向配置的FQDN发送SNI"改为"SNI 在 ClientHello 中被设置为已配置的 FQDN"。
```
- reference
- /Users/lex/git/gcp/ingress/public-mtls-global-ingress/shared-glb-cn-a-sni.md
⚠️ 此文档已被 ADR-014 [`shared-glb-nginx-sni.md`](./shared-glb-nginx-sni.md) 取代。建议在正式版 reference 中改为 ADR-014,探索稿作为决策追溯保留。
- [shared-glb-cn-a-sni.md](./shared-glb-cn-a-sni.md)
✅ 链接形式有效。但建议改为 ADR-014:`[shared-glb-nginx-sni.md (ADR-014)](./shared-glb-nginx-sni.md)`

GLB 在跟 backend 建立 TLS 连接时,默认不会发 SNI。 它会重建一条 TLS 握手(因为 frontend TLS 已经在 GLB 终止),而这条 backend TLS 的 ClientHello 不会带上原始客户端的 SNI。

由于 §2 已经确认 **GLB 不会透传客户端原 SNI 给 PSC NEG**,Master Gateway 实际收到的 SNI 是 GLB 重建 TLS 时**自行决定**的值(可能是空字符串、可能是 PSC NEG endpoint 的 IP、可能是 `tlsSettings.sni` 配置值)。
✅ 这段是 ADR-014 / 探索稿 §3.2 还原的精确描述,架构师已确认三种真实场景(A:空字符串 / B:PSC NEG endpoint IP / C:`tlsSettings.sni` 固定值)。

例外:当 backend 是 internet NEG (INTERNET_FQDN_PORT) 时,GLB 才用 backend service tlsSettings.sni 配置的字符串作为 SNI 发出去。但PSC NEG 不在这个例外里。
✅ 准确。需注意:这里"internet NEG"是 `INTERNET_FQDN_PORT` 端点(更具体),`INTERNET_IP_PORT` 端点**也**不在 SNI 例外内(见上方原文引用)。如果想更精准,补充:"PSC NEG 不在 `INTERNET_FQDN_PORT` 和 `INTERNET_IP_PORT` 这两类端点的例外范围内"。

## 2. 权威证据:GCP 官方关于 backend SNI 的行为
⚠️ 文档结构问题:本文档 § 编号从 §2 开始跳过了 §0(配套文档与必读)和 §1(背景)。建议在最前面补 §0 + §1(详见文末 #结构建议 段)。

### 2.1 简化解释(架构师)
✅ 章节结构与 ADR-014 一致(也是 §2.1 简化解释)。

> **GLB 在跟 backend 建立 TLS 连接时,默认不会发 SNI。** 它会重建一条 TLS 握手(因为 frontend TLS 已经在 GLB 终止),而这条 backend TLS 的 ClientHello **不会带上原始客户端的 SNI**。
>
> **例外**:当 backend 是 **internet NEG (INTERNET_FQDN_PORT)** 时,GLB 才用 backend service `tlsSettings.sni` 配置的字符串作为 SNI 发出去。但**PSC NEG 不在这个例外里**。
✅ 内容与 ADR-014 §0 TL;DR 一致。

### 2.2 严格原话(GCP 官方文档 — 原文引用)

**来源 1**:`https://cloud.google.com/load-balancing/docs/ssl-certificates/encryption-to-the-backends` § "Encryption between proxy load balancers and backends"

> **原文(英文)**:
> > "With the exception of HTTPS load balancers with internet NEG backends, load balancers don't use the Server Name Indication (SNI) extension for connections to the backend."
✅ 来源 1 引用准确,与 ADR-014 §3.1 来源 1 一致。

**原文(中文版)**(同页,机翻对照):
> "对于 HTTPS 负载均衡器与 Internet NEG 后端的情况除外,负载均衡器在与后端的连接中**不使用** SNI(Server Name Indication)扩展。"
✅ 中文版准确。

**来源 2**:`https://cloud.google.com/load-balancing/docs/backend-authenticated-tls-backend-mtls` § "Backend authenticated TLS and backend mTLS overview"

> **原文**:
> > "The load balancer doesn't pass the client's SNI hostname from the frontend TLS connection when connecting to a backend. However, backends can access the client's SNI hostname using a custom request header."
✅ 来源 2 引用准确,与 ADR-014 §3.1 来源 2 一致。

**原文(中文版)**:
> "负载均衡器在连接到后端时,**不会将客户端的 SNI 主机名从前端 TLS 连接传递到后端**。但是,后端可以通过**自定义请求头**访问客户端的 SNI 主机名。"
✅ 中文版准确。

### 2.3 PSC NEG 的官方类别归属(GCP NEG 文档)

**来源 3**:`https://cloud.google.com/load-balancing/docs/negs` § "Network endpoint groups overview"

> PSC NEG 的类型标识是 `private-service-connect`,**不属于 internet NEG** 类别(internet NEG 类型是 `internet-fqdn-port` 或 `internet-ip-port`)。
✅ 来源 3 引用准确,与 ADR-014 §3.1 来源 3 一致。

**来源 4**:`https://cloud.google.com/vpc/docs/private-service-connect-backends` § "About Private Service Connect backends"

> "Only the supported load balancers can use Private Service Connect NEGs as backends. Private Service Connect NEGs cannot be mixed with other NEG types in the same backend service."

→ **PSC NEG 与 internet NEG 是两个独立的 NEG 类别**,**internet NEG 的 SNI 例外不适用于 PSC NEG**。
✅ 来源 4 + 结论准确。


## 为什么会有这个问题

TLS 握手（ClientHello 里的 SNI）是在 **HTTP 请求还没有被解析之前**完成的，而你的 `hostRewrite`（把 Host 重写成 `team1apiname.team1.intra.domain`）是**七层（HTTP Host/​:authority header）动作**，发生在 URL Map 做完路由决策、请求已经从 GLB 转发给后端之后。这两件事根本不在同一个阶段：
✅ 协议分层解释准确:L4 TLS ClientHello(SNI)在 L7 HTTP hostRewrite 之前。

```
GLB 前端 mTLS 握手（SNI=tenantmtls.taobao.caep.uk，client 决定）
   ↓ 终止 mTLS，解析 HTTP 请求
URL Map 按 path 选 BS，做 hostRewrite（只改 HTTP Host header）
   ↓ GLB 向后端发起【新的】TLS 连接
GLB→后端 TLS 握手（SNI 是什么？—— 与 hostRewrite 无关，GLB 自己决定/固定）
```
✅ 润色建议:"GLB 自己决定/固定" → "由 GLB 自行决定(可能为空 / 为 PSC NEG endpoint IP / 为 `tlsSettings.sni` 固定值 — 见 ADR-014 §3.2)"。

所以：**`hostRewrite` 永远只能影响 HTTP Host header，改变不了 GLB 到后端这一跳新建 TLS 连接时发出的 SNI**。GCP 官方文档也证实了这一层的信任模型很粗放——GLB 连接 Google Cloud 内的后端时，默认根本不校验后端证书，也没有"把原始 client SNI 透传给后端"这个能力/开关。
⚠️ 措辞校准:
1. "默认根本不校验后端证书" — 略夸张。GCP 官方原文是 "performs only minimum certificate validation"(只做最低验证,不是不验证)。严格表述见 [`encryption-to-the-backends`](https://cloud.google.com/load-balancing/docs/ssl-certificates/encryption-to-the-backends) §"When a load balancer connects to backends that are within Google Cloud, the load balancer accepts any certificate your backends present. In this case, the load balancer performs only minimum certificate validation."
   → 改为:"GLB 连接 Google Cloud 内的后端时,**只做最低验证**(默认接受任何后端证书,即使 hostname 不匹配)"
2. "也没有"把原始 client SNI 透传给后端"这个能力/开关" — 这是 §2.2 来源 2 的原话,准确。但把"宽松证书验证"和"不传 SNI"这两个独立事实在"粗放"一词下合并,会让读者误以为是同一个原因。建议把这两件事分两句表述,中间用句号断开(详见 #结构建议 段 §"为什么会有这个问题" 润色版)。


reference:
https://cloud.google.com/load-balancing/docs/backend-authenticated-tls-backend-mtls
✅ 引用准确。


## 修正方案(三选一)

### 方案 1（推荐） K8s Gateway 不再按 hostname 做 listener 选择分流* 

==> 这个我们已经验证过是没有任何问题


**Lex 真正想表达的应该是**:"**K8s Gateway 不再按 hostname 做 listener 选择分流**" — 改为单一 listener + 单一 wildcard cert(`*.intra.domain`)接受所有 SNI,所有 Team 差异化路由下沉到这一个 listener 之下的多个 HTTPRoute,通过 URI-SAN header 精确匹配来区分。这样 SNI 问题就不存在了(因为 listener 不再按 SNI 区分)。

→ 这是 ADR-014 §4 fallback 方案的核心。


**"ListenerSet"**(K8s Gateway API 官方资源名)
**移除 ListenerSet**(直接用 Gateway 的主 listener,无 hostname 字段)" — 因为 Gateway API 的 ListenerSet 是可选资源,如果不创建 ListenerSet,Gateway 的主 listener 默认不按 hostname 区分。

→ 这个纠正是 ADR-014 §4 的具体实现路径,见 ADR-014 §4.2 YAML。

### 方案 2：如果业务上一定要在 K8s Gateway 保留第二层 TLS（纵深防御）

==> 这个也是我比较推荐的一个方案，而且验证是 OK 的，可以简化我们的配置，因为我们整个环境里面所有的 API 名称都是唯一的。我直接拿一个 Shard 的域名出来，来提供内部的这种服务 然后针对 API 的名字，也就是唯一的这个名字，再进行对应的 HTTP 路由规则的转发到对应的 Deploy 服务

那就不能再靠"每个 Team 一个按 SNI 区分的 Listener"，而要改成：
⚠️ **拼写 / 架构师 push back**:

1. **拼写**:"Shard" → **"Shared"**(Shared = 共享/共用,业务方原意是"共享一个域名")
2. **意图校准**:Lex 说"我们整个环境里面所有的 API 名称都是唯一的" — 这是**新业务前提**,架构师需要 push back 确认:
   - **Q1**:既然 API 名唯一,为什么不直接用 API 名做 hostname(如 `apiname1.team1.intra.domain`)?
   - **Q2**:为什么需要 `*.intra.domain` 通配,而不是每 API 一张 cert?
   - **Q3**:这与 ADR-014 §5.3 反对的"粒度 B(API Level 精确)" 区别在哪里?
   - **Q4**:API 名唯一,但 team-a/apiname1 与 team-b/apiname1 仍然不同 team — 跨 team API 名不唯一,这条边界怎么处理?

3. **架构师建议**:业务方答复 Q1-Q4 后,把方案 2 与 ADR-014 方案 D + 粒度 A 做正式对比,确定哪个更优。

→ 如果方案 2 的意图确实是"单一 listener + 单一 wildcard cert + HTTPRoute 路由",那么它与 ADR-014 §4 fallback **本质相同**,只是措辞不同。

只用一个 Listener，配一张能覆盖所有 team 子域名的通配符证书（如 *.intra.domain），hostname: "*"（或直接不做 SNI 校验，接受任意 SNI 都走这一个 filter chain/证书）。
✅ 文字描述准确,与 ADR-014 §4 修正方案核心一致。
✅ 润色建议:在 Gateway API 规范里,"hostname: *" 应该**直接省略 hostname 字段**(而不是写 "*")。详见 ADR-014 §4.2 YAML。

所有 team 的差异化路由，全部下沉到这一个 Listener 之下的多个 HTTPRoute，通过 hostnames（匹配的是 TLS 终止后的 HTTP Host header，不是 SNI）+ 自定义 header 精确匹配来区分：
✅ 准确,但需明确"hostnames"在 HTTPRoute 里**不是必填**。Lex 的方案核心是:
- 主要按 **path**(`/team1apiname/*` / `/team2apiname/*`)
- + **自定义 header**(`X-Client-Cert-URI-SANs` 精确匹配,作为防漂移双保险)
- hostnames 字段可选(如果业务方 hostRewrite 后 host 是 `apiname1.team1.intra.domain`,可以用 hostnames 匹配;否则不需要)

架构师建议明确:**主路径 = path + URI-SAN header 匹配**(双保险),hostnames 作为可选的"前置过滤"。

**修正方案架构**:

```
External Client
  └─ TLS ClientHello (SNI = tenantmtls.taobao.caep.uk)
     └─ GLB Global External HTTPS LB (Talent)
        ├─ TrustConfig 验 client cert chain
        ├─ ServerTlsPolicy (REJECT_INVALID)
        ├─ URL Map (path-based)
        │   /team1apiname/* → Backend Service team1-bs (Cloud Armor team1)
        │   /team2apiname/* → Backend Service team2-bs (Cloud Armor team2)
        │   default         → Backend Service shared-bs
        ├─ 注入 14 个 client cert headers 到 backend
        │   X-Client-Cert-URI-SANs = "spiffe://caep.example/tenant/team-a/apiname1"
        │   X-Client-Cert-SPIFFE = "spiffe://caep.example/tenant/team-a/apiname1"
        └─ 重建 backend TLS(无 SNI/固定 SNI) → PSC NEG
           └─ PSC tunnel → Master ServiceAttachment
              └─ Master K8s Gateway (443)
                 ├─ **单一 listener**(不再分 ListenerSet)
                 │   tls.mode: Terminate
                 │   单一 wildcard cert: *.intra.domain(覆盖所有 Team 内部域名)
                 ├─ HTTPRoute matches[].headers(URI-SAN 精确匹配)
                 │   /team1apiname/* + X-Client-Cert-URI-SANs = "spiffe://...team-a/apiname1" → team1-svc
                 │   /team2apiname/* + X-Client-Cert-URI-SANs = "spiffe://...team-b/apiname1" → team2-svc
                 │   default → 404(防漂移)
                 └─ Team svc → 业务方 Pod
```
✅ 架构图与 ADR-014 §2.1 一致,内容准确。


### 方案 3: 在 Master K8s Gateway 前置 Nginx MIG 注入 SNI

> "我在这里通过一个 nginx MIG 暴露对应的 service attachment... 因为 nginx 可以针对 api levels 强制针对 apiname 或者说 path 做头转换到内部的 listenset 侦听的 hostname,还可以是 team level 的比如 `*.team1.intra.domain` `*.team2.intra.domain`"
⚠️ "listenset" → **"ListenerSet"**。其余文字是 Lex 原话引用,保留不改。

**架构师精确化**(把业务方口语转化为设计图):
✅ 章节命名与 ADR-014 §5.1 一致。

```
External Client
  └─ TLS ClientHello (SNI = tenantmtls.taobao.caep.uk)
     └─ GLB Global External HTTPS LB (Talent)
        ├─ TrustConfig 验 client cert chain ✓
        ├─ ServerTlsPolicy (REJECT_INVALID) ✓
        ├─ URL Map (path-based)
        ├─ 注入 14 个 client cert headers(含 X-Client-Cert-URI-SANs)
        └─ 重建 backend TLS(无 SNI/固定 SNI) → PSC NEG
           └─ PSC tunnel → Master ServiceAttachment
              └─ ⚠️ 业务方新提议:Master Nginx MIG(本节新增)
                 ├─ 终止 GLB 重建的 TLS
                 ├─ 读 path/apiname / 读 X-Client-Cert-URI-SANs header(已注入)
                 ├─ 强制重写 Host 头 + SNI 到内部 hostname
                 └─ 重建 backend TLS(带正确 SNI) → Master K8s Gateway (443)
                    ├─ ListenerSet *.team1.intra.domain(team1 流量)
                    ├─ ListenerSet *.team2.intra.domain(team2 流量)
                    └─ 主 Gateway https listener
                    ├─ HTTPRoute matches[].headers(URI-SAN 精确匹配)  路由 → 各 team API svc
                        │   /team1apiname/* + X-Client-Cert-URI-SANs = "spiffe://...team-a/apiname1" → team1-svc
                        │   /team2apiname/* + X-Client-Cert-URI-SANs = "spiffe://...team-b/apiname1" → team2-svc
                        │   default → 404(防漂移)
                        └─ Team svc → 业务方 Pod
```
✅ 设计图与 ADR-014 §5.9 + 探索稿 §5.9 一致,内容准确。
保留双层 TLS + 严格 SNI/Host 隔离"前提下最靠谱的一个。原因很简单：
#### 方案三流程校验

你画的这个流程是**对的**，而且这一步棋走得很关键——你无意中补上了方案二里 GLB 结构性做不到的一个能力。

先给结论：**方案三可行，而且是目前几个方案里在"保留双层 TLS + 严格 SNI/Host 隔离"前提下最靠谱的一个**。原因很简单：

> GLB 做不到"按 request 内容动态设置发往后端的 SNI"，这是 GCP 托管 LB 的结构性限制（我们上一轮分析过：SNI 属于 TLS 握手阶段的产物，先于 URL Map 的 L7 路由决策发生）。但 **Nginx 是一个你完全可控的通用反向代理，它天生就能做这件事**——读到 path/header 之后，用 `proxy_ssl_name` 显式指定发往上游（K8s Gateway）的 SNI。这正是方案二里缺的那一环。

所以方案三本质上是：**把"按内容动态设置 SNI"这个能力，从 GLB（做不到）下沉到 Nginx（能做到）**，其余部分（GLB 验 cert、注入 header、K8s Gateway HTTPRoute 按 header 精确匹配防漂移）完全不变。

---

#### 关于你的第二个问题：header 注入是否和 SNI 一样有问题

**不会。这是两个完全不同层面的东西，值得明确区分开：**

| | SNI | 自定义 Header（如 `X-Client-Cert-URI-SANs`） |
|---|---|---|
| 所属层 | TLS 握手（L4/L5，ClientHello 阶段） | HTTP 请求体的一部分（L7） |
| 何时确定 | 在 HTTP 请求发出**之前**，且必须在建立新 TLS 连接时就决定好 | 随 HTTP 请求本身一起传递 |
| 能否被中间代理透传 | 不能自动透传——每一跳新建 TLS 连接都要**重新决定**发什么 SNI，上一跳的 SNI 对下一跳没有约束力 | 能透传——只要中间的代理（Nginx、Envoy）不主动清除/覆盖，header 会原样带到下一跳，无论中间经过几次 TLS 终止/重建 |
| GLB 是否有能力控制 | 没有对外暴露"按 path 动态设置出站 SNI"的配置项 | 有——`customRequestHeaders` 本来就是为了干这件事设计的 |

所以你的架构设计思路（"SNI 靠不住 → 把身份判断完全押注在 header 上"）**方向是对的**，这也是为什么整个防漂移的最终裁决点始终应该落在 HTTPRoute 的 header 匹配上，而不是任何一层的 SNI/Host 匹配。SNI/Host 在你的架构里应该只承担"选路"的辅助作用，**从来不该是安全边界**——真正的安全边界一直是、也应该一直是这个 header。

---

#### 关键澄清：Nginx 在这里的角色变了

要特别提醒一点，避免你们内部沟通产生误解：业务方最早提出"去 Nginx 化"，针对的是**旧架构里 Nginx 用 CN 比对做安全决策**这件事。方案三里重新引入的 Nginx，**职责完全不同**——它不做任何身份/权限判断，只做一件纯网络层的事：**修正 Host + SNI，让请求能正确路由到对应的 K8s Gateway Listener**。真正的防漂移裁决，始终在 K8s Gateway 的 HTTPRoute 层完成。建议把这一点写进架构文档，避免以后有人误以为"又走回 Nginx 做安全逻辑的老路"。

也正因为如此，这里有一层**天然的纵深防御**：即使 Nginx 配置出错、把 team-a 的请求错误路由到了 team-b 的 Listener/hostname，只要 Nginx 老老实实透传了 `X-Client-Cert-URI-SANs` 这个 header（没有改写它），HTTPRoute 那边按 header 精确匹配，一样会因为 SPIFFE 值对不上而 404。**Nginx 路由错了不等于安全被绕过**，这是这套设计比"单纯依赖 Nginx 正确性"更健壮的地方。

---

#### 需要验证/落地的细节

##### 1. Nginx 配置示例（核心是 `proxy_ssl_name`）

```nginx
map $uri $upstream_sni {
    "~^/team1apiname"  "team1apiname.team1.intra.domain";
    "~^/team2apiname"  "team2apiname.team2.intra.domain";
    default            "";
}

server {
    listen 443 ssl;
    # 这里终止的是 GLB 重建的那段 TLS（PSC 通道内部，可信边界较窄）
    ssl_certificate     /etc/nginx/certs/internal.crt;
    ssl_certificate_key /etc/nginx/certs/internal.key;

    location / {
        if ($upstream_sni = "") {
            return 404;   # 未知路径显式拒绝，不要落到任何默认后端
        }

        proxy_pass https://gke_gateway_upstream;

        # 关键：让 Nginx 按内容动态发出正确的 SNI（GLB 做不到的事）
        proxy_ssl_server_name on;
        proxy_ssl_name        $upstream_sni;
        proxy_ssl_verify      on;
        proxy_ssl_trusted_certificate /etc/nginx/ca/gateway-internal-ca.pem;

        proxy_set_header Host $upstream_sni;

        # 只透传，绝不重新赋值/清空这个 header
        proxy_set_header X-Client-Cert-URI-SANs $http_x_client_cert_uri_sans;
    }
}
```

要点：
- `proxy_ssl_server_name on;` 默认是关闭的，不开这个 SNI 根本发不出去，**这是最容易被漏掉的一步**。
- `proxy_ssl_verify on;` 一定要开，校验 K8s Gateway 的证书链，否则 Nginx→Gateway 这一跳的 TLS 只是"加密"，没有"认证"。
- Nginx 侧的 path→hostname 映射表，和 K8s Gateway HTTPRoute 里的 path 定义，**必须来自同一份配置来源**（建议 Terraform/CI 里用同一个 YAML 生成两边配置），否则两边各自维护迟早会出现漂移不一致，反而制造新的安全空洞。

##### 2. 你的 URI-SAN 精细化到 API 级别的思路是可行的，而且比纯 team 级更强

你现在的设计已经从"team 级隔离"升级到了"**team + apiname 级隔离**"（每个 API 一个 cert，`spiffe://caep.example/tenant/team-a/apiname1`）。这个粒度是合理的，逻辑链路走得通：

```
CSR(申请方自报 URI SAN)
   ↓
CA 签发(⚠️ 关键风险点，见下)
   ↓
GLB 验 cert 链 → {client_cert_sans_uri} 写入 X-Client-Cert-URI-SANs
   ↓
Nginx 透传（不碰这个 header）
   ↓
HTTPRoute: path==/team1apiname/* AND header==spiffe://.../team-a/apiname1 → team1-svc
           （team-a 的 apiname2 证书打这个路径 → header 值对不上 → 落不到任何规则 → 404）
```

这条链路能实现你要的效果：**同一 team 下，不同 API 的证书互相不能串用**。

**但有一个不在网络层面、而在流程管理层面的风险点，比任何技术配置都重要**：CSR 里的 URI SAN 是**申请方自己写的**，CA 在签发时**绝不能盲目照抄 CSR 里的 SAN 字段**。也就是说：

> 谁来保证"team-b 的人不会在自己的 CSR 里，直接把 URI SAN 填成 `spiffe://caep.example/tenant/team-a/apiname1`，然后拿着这张自称是 team-a 的证书去申请签发"？

如果签发流程只是机械地把 CSR 内容签成证书（常见的自动化流水线容易犯这个错），那么**整个防漂移体系的地基就是空的**——因为无论 GLB、Nginx、HTTPRoute 配置得多严密，它们信任的前提都是"证书里的 URI SAN 真实反映了持有者身份"，而这个前提本该由 CA 签发环节保证，不是由网络层保证。

建议：
- CA/签发流水线必须做**授权校验**：申请人提交 CSR 时先声明"我是 team-a，申请 apiname1"，走审批/权限校验通过后，**CA 侧根据审批结果重新构造 SAN 字段写入证书，而不是直接照抄 CSR 里的 SAN**（哪怕申请人 CSR 里写的和审批结果一致，也应该以审批系统的记录为准，不信任 CSR 自报内容）。
- 建议把 team/apiname → 允许申请的身份/审批人 这层映射也纳入自动化流程（比如接入内部工单系统），而不是人工肉眼核对。

##### 3. 证书数量规模确认

之前我们记录过一个结论：如果用的是 `allowlistedCertificates`（逐证书白名单）模式，有 **50 张证书**的硬限制。但你现在的模式是"Trust Config 验证证书链（Root + Intermediate CA）"，只要证书是受信 CA 签发的就通过链路验证，**不受 50 张的限制**，这样 team×API 组合再多也不影响 GLB 侧的可扩展性。这点建议在方案文档里明确写出来，避免以后有人把这两种模式的限制搞混。

---

##### 综合结论

| 检查项 | 结论 |
|---|---|
| Nginx 补 SNI 是否可行 | ✅ 可行，`proxy_ssl_name` + `proxy_ssl_server_name on` 是标准做法 |
| header 是否受 SNI 问题影响 | ❌ 不受影响，两者不在同一层 |
| API 级 URI-SAN 隔离 + HTTPRoute 精确匹配 | ✅ 逻辑可行 |
| 最大风险点 | ⚠️ **不在网络层，在 CA 签发流程**——必须防止 CSR 自报 SAN 被盲目签发 |
| 次要风险点 | Nginx↔Gateway 需开 `proxy_ssl_verify`；Nginx 与 HTTPRoute 的 path 映射需单一配置来源，防止两边配置漂移 |

方案三是站得住的，唯一需要你回去和 PKI/证书签发团队确认清楚的，是 CSR 到证书这一步的授权校验逻辑——这是整套体系里唯一一个纯网络配置补不回来的环节。



---

# 📋 架构师审核总结(完整版,供 Lex 阅后采纳)

## 1. 内容准确性(✅ / ⚠️ / ❌)

| 章节 | 状态 | 说明 |
|---|---|---|
| §"GLB 在跟 PSC NEG 建立 backend TLS 握手时" | ✅ | 准确 |
| §"GLB 在跟 backend 建立 TLS 连接时" | ✅ | 准确 |
| §"SSL Server Name Indication (SNI) extension handling" | ✅ | 引用准确 |
| §2.1-§2.3 权威证据 | ✅ | 4 个 GCP 来源全部准确 |
| §"为什么会有这个问题" 协议分层解释 | ✅ | 准确 |
| §"hostRewrite 永远只能影响 HTTP Host header" | ✅ | 准确 |
| §"默认根本不校验后端证书" | ⚠️ | 改为"只做最低验证" |
| §"没有透传 client SNI 给后端能力/开关" | ✅ | 准确 |
| §方案 1 "不再做第二次 TLS 终止" | ❌ | **关键错误 — 改成"不再按 hostname 分流"** |
| §方案 1 "ListenSet 取消对 hostname 的监听" | ⚠️ | 拼写 ListenSet → ListenerSet;语义模糊需明确 |
| §方案 2 "Shard" | ⚠️ | 拼写 → Shared |
| §方案 2 "我们整个环境里面所有的 API 名称都是唯一的" | ⚠️ | 新业务前提,需要 push back 确认 |
| §方案 2 单一 Listener + wildcard cert + HTTPRoute | ✅ | 与 ADR-014 §4 一致 |
| §方案 2 架构图 | ✅ | 准确 |
| §方案 3 Nginx MIG | ✅ | 与 ADR-014 §5 一致 |
| §方案 3 "组建" | ⚠️ | 改为"组件" |
| §方案 3 "NGINX" | ⚠️ | 建议 Nginx |
| §方案 3 "K8S" | ⚠️ | 建议 K8s |
| §方案 3 "listenset" | ⚠️ | 改为 ListenerSet |

## 2. 关键架构师 push back(给业务方的开放问题)

### 2.1 §方案 1 关键错误(必须纠正)

Lex 原文:"K8s Gateway 层不再做第二次 TLS 终止,SNI 问题直接消失"

这是**架构错误**。如果 K8s Gateway 不做 TLS 终止:
- 收到的是密文 HTTP,无法解析 path / header / Host
- HTTPRoute 无法工作
- 业务直接 502

**Lex 真正想表达**:"K8s Gateway 不再按 hostname 做 listener 选择分流"(单一 listener + 单一 wildcard cert,所有差异化通过 HTTPRoute 下沉)。这是 ADR-014 §4 修正方案。

### 2.2 §方案 2 新前提(需要 Lex 答复)

Lex 提出"我们整个环境里面所有的 API 名称都是唯一的"。这是**之前讨论中没有出现过的事实**,架构师需要确认:

- **Q1**:既然 API 名唯一,为什么需要 `*.intra.domain` 通配,而不是每 API 一张 cert?
- **Q2**:这与 ADR-014 §5.3 反对的"粒度 B(API Level 精确)" 区别在哪里?
- **Q3**:API 名唯一,但 team-a/apiname1 与 team-b/apiname1 仍然不同 team — 跨 team API 名不唯一,边界怎么处理?
- **Q4**:方案 2 与 ADR-014 §4 fallback 本质相同吗?如果相同,为什么不直接采用 ADR-014?

### 2.3 §方案 3 与 ADR-014 关系

§方案 3 实质是 ADR-014 §5 方案 D + 粒度 A。建议 Lex 在 Why-missing-sni.md 中**直接引用 ADR-014**,不要重复完整设计图。

## 3. 拼写 / 术语统一清单(供 Lex 终稿时替换)

| Lex 原文 | 建议改为 | 出现位置 |
|---|---|---|
| ListenSet | **ListenerSet**(K8s Gateway API 资源名)| §方案 1, §方案 3 |
| Shard | **Shared**(Lex 想表达"共享")| §方案 2 业务原话 |
| 组建 | **组件** | §方案 3 标题 |
| NGINX | **Nginx**(正文)/ NGINX(binary)| §方案 3 标题 |
| K8S | **K8s** | §方案 3 标题 |
| listenset | **ListenerSet** | §方案 3 业务原话 |
| 负载平衡器 | **负载均衡器**(翻译统一)| §"SSL Server Name Indification" 中文翻译 |
| 客户端hello | **ClientHello** | §同上 |

## 4. 结构建议(为对齐 ADR-014 格式)

为对齐 ADR-014 格式,建议 Lex 在 Why-missing-sni.md 文档头部补:

```markdown
> **状态**:Draft · Date: 2026-09-05 · Author: **<DECISION_MAKER>** · Reviewers: **architect-gcp**
>
> **配套文档**:
> - ADR-014 [`shared-glb-nginx-sni.md`](./shared-glb-nginx-sni.md) — 正式 ADR
> - 探索稿 [`shared-glb-cn-a-sni.md`](./shared-glb-cn-a-sni.md) — 决策追溯
> - [`venafi-team-cert-template.md`](./venafi-team-cert-template.md) — URI-SAN cert 生成模板

## 0. 一句话总结
> 默认情况下,**GLB 不会将客户端 SNI 透传给 backend**。在 GLB + PSC NEG + Master K8s Gateway 架构下,Master Gateway 的 Listenerset hostname 分流失效,**必须用替代方案(Nginx MIG 注入 SNI / 单一 listener + HTTPRoute 路由)**。




