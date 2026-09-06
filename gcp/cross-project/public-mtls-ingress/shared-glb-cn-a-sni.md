# 共享 GLB → PSC NEG → Master Gateway — SNI 传递性分析 — shared-glb-cn-a-sni

> **本节是业务方提出的"SNI 是否能从外部 client 一路传到 Master Project 的 K8s Gateway listener 选择"问题的精确分析文档**。
>
> **架构师 lane 边界**:本文档只做协议行为分析 + GCP 权威文档引用 + 修正方案,**不实施任何 provision / apply / gcloud / terraform**。infra-gcp 按本文档的修正方案落地。
>
> **状态**:Draft(待业务方 + 决策者确认修正方案)· Date: 2026-09-05 · Author: **architect-gcp** · Reviewers: **infra-gcp** / 业务方 / **qa-gcp**
>
> **业务方核心问题**(原文提炼):
> > "对于这种 GLB 的形式,通过 PSC NEG 的暴露方式做 Cross Project 的时候,**SNI 的头好像没法传递到我的 Master Gateway 上面**... 在我这个架构模式下面,它能不能传递到 Master Gateway 的位置?"
>
> **一句话答案**(架构师结论):
> > **❌ 不能**。**GLB 在跟 PSC NEG 建立 backend TLS 握手时,不会透传客户端的 SNI 头**(GCP 官方明确文档:`encryption-to-the-backends`)。
> > 因此 [`shared-glb-cn-a.md` §3.2.1](./shared-glb-cn-a.md) 里"每个 Team 一个 ListenerSet + hostname `*.team-a.intra.domain`"的写法**在当前架构下不会触发** — ListenerSet 的 hostname 字段**变成无效配置**。
> > 但**好消息是:合并方案(A+B)的防漂移能力不依赖 SNI** — 它依赖 GLB 已经透传的 `X-Client-Cert-URI-SANs` HTTP header。修正方案见 §4。

---

## 0. 配套文档与必读

| 文档 | 用途 |
|---|---|
| [`shared-glb-cn-a.md`](./shared-glb-cn-a.md) | 业务方合并方案(A+B)— 本文要修正的版本 |
| [`shared-glb-cn.md`](./shared-glb-cn.md) | 上游 3 候选方案对比 |
| [`tenant-mtls-cn.md` §0.3](./tenant-mtls-cn.md) | 已实现 GLB mTLS 架构(无 PSC NEG 版,ServerTlsPolicy 验 cert) |
| [`explorer-mtls-cn.md`](./explorer-mtls-cn.md) | mTLS 字段能力边界 |
| [`venafi-team-cert-template.md`](./venafi-team-cert-template.md) | URI-SAN cert 生成模板 |

**前置知识**:GCP External Application Load Balancer backend 协议、TLS ClientHello / SNI、K8s Gateway API ListenerSet、Envoy `filter_chain_match.server_names`。

---

## 1. 业务方问题的协议层分解

### 1.1 业务方问题精确化

业务方的怀疑聚焦于一条**完整的数据链路**,从外部 client 到 Master K8s Gateway listener 选择:

```
External Client
  └─ TLS ClientHello (SNI = tenantmtls.taobao.caep.uk)        ← 业务方原 SNI
     └─ GLB Global External HTTPS LB (Talent)
        └─ TLS 终止 + TrustConfig 验 client cert chain
           └─ URL Map 路由 → Backend Service
              └─ Backend Service → PSC NEG (单一 IP)
                 └─ ⚠️ GLB 重建 backend TLS ClientHello            ← 这里 SNI 是什么?
                    └─ PSC tunnel → Master ServiceAttachment
                       └─ Master K8s Gateway (443)
                          └─ Envoy filter_chain_match.server_names  ← 业务方期望这里用 SNI 选 ListenerSet
                             └─ *.team-a.intra.domain / *.team-b.intra.domain
```

**业务方核心疑问**:从 External Client 到 Master K8s Gateway listener 选择,**SNI 是否完整传递**?

### 1.2 架构师分解(4 段链路)

| 段 | 链路 | SNI 行为 |
|---|---|---|
| **L1** | External Client → GLB GFE | ✅ 完整传递(`tenantmtls.taobao.caep.uk`) |
| **L2** | GLB GFE → Backend Service(经 PSC NEG) | ❌ **不传递**(GCP 重建 backend TLS,见 §2) |
| **L3** | PSC NEG → Master ServiceAttachment | ❌ 不适用(内部 IP 路由,无 SNI 概念) |
| **L4** | Master ServiceAttachment → K8s Gateway Envoy | ❌ 收到的 SNI 是 **GLB 重建的**,不是客户端原 SNI |

→ **L2 是关键断点**。SNI 在 L1 是原值,L2 之后是 GLB 重建 TLS 时**自行决定**的新值(可能为空,可能是 GLB 默认 dummy,见 §2 原文)。

---

## 2. 权威证据:GCP 官方关于 backend SNI 的行为

### 2.1 简化解释(架构师)

> **GLB 在跟 backend 建立 TLS 连接时,默认不会发 SNI。** 它会重建一条 TLS 握手(因为 frontend TLS 已经在 GLB 终止),而这条 backend TLS 的 ClientHello **不会带上原始客户端的 SNI**。
>
> **例外**:当 backend 是 **internet NEG (INTERNET_FQDN_PORT)** 时,GLB 才用 backend service `tlsSettings.sni` 配置的字符串作为 SNI 发出去。但**PSC NEG 不在这个例外里**。

### 2.2 严格原话(GCP 官方文档 — 原文引用)

**来源 1**:`https://cloud.google.com/load-balancing/docs/ssl-certificates/encryption-to-the-backends` § "Encryption between proxy load balancers and backends"

> **原文(英文)**:
> > "With the exception of HTTPS load balancers with internet NEG backends, load balancers don't use the Server Name Indication (SNI) extension for connections to the backend."

**原文(中文版)**(同页,机翻对照):
> "对于 HTTPS 负载均衡器与 Internet NEG 后端的情况除外,负载均衡器在与后端的连接中**不使用** SNI(Server Name Indication)扩展。"

**来源 2**:`https://cloud.google.com/load-balancing/docs/backend-authenticated-tls-backend-mtls` § "Backend authenticated TLS and backend mTLS overview"

> **原文**:
> > "The load balancer doesn't pass the client's SNI hostname from the frontend TLS connection when connecting to a backend. However, backends can access the client's SNI hostname using a custom request header."

**原文(中文版)**:
> "负载均衡器在连接到后端时,**不会将客户端的 SNI 主机名从前端 TLS 连接传递到后端**。但是,后端可以通过**自定义请求头**访问客户端的 SNI 主机名。"

### 2.3 PSC NEG 的官方类别归属(GCP NEG 文档)

**来源 3**:`https://cloud.google.com/load-balancing/docs/negs` § "Network endpoint groups overview"

> PSC NEG 的类型标识是 `private-service-connect`,**不属于 internet NEG** 类别(internet NEG 类型是 `internet-fqdn-port` 或 `internet-ip-port`)。

**来源 4**:`https://cloud.google.com/vpc/docs/private-service-connect-backends` § "About Private Service Connect backends"

> "Only the supported load balancers can use Private Service Connect NEGs as backends. Private Service Connect NEGs cannot be mixed with other NEG types in the same backend service."

→ **PSC NEG 与 internet NEG 是两个独立的 NEG 类别**,**internet NEG 的 SNI 例外不适用于 PSC NEG**。

### 2.4 架构师结论

| 维度 | 严格事实 |
|---|---|
| GLB frontend 收到的 SNI(`tenantmtls.taobao.caep.uk`) | ✅ 收到,但只用于 frontend cert 选择 |
| GLB → PSC NEG 的 backend TLS SNI 字段 | ❌ **默认不传**(GCP 官方原文) |
| GLB → PSC NEG 的 backend TLS ClientHello 内容 | 由 GLB 内部决定,可能为空 / 可能为 PSC NEG endpoint hostname / 可能为 `tlsSettings.sni` 显式配置值 |
| PSC NEG 收到的 backend TLS 是否能透传到 Master Gateway | ❌ 不适用(PSC 是 IP 层 tunnel,不处理 TLS) |
| Master Gateway Envoy 实际看到的 SNI | 是 **GLB 重建的 SNI**(非业务方原 SNI),可能是空或非业务域名 |

**业务方原话"通过 PSC NEG 的暴露方式做 Cross Project 的时候,SNI 的头好像没法传递到我的 Master Gateway 上面"** → **业务方判断完全正确**。

---

## 3. 业务方合并方案(a+b)里 SNI 原本的设计意图

### 3.1 [`shared-glb-cn-a.md` §3.2.1](./shared-glb-cn-a.md) 中 SNI 的设计意图

原方案期望利用 SNI 在 K8s Gateway listener 选择阶段做分流:

```yaml
# shared-glb-cn-a.md §3.2.1(原文摘录)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tenantmtls-gateway
  namespace: gateway-system
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
      - name: tenantmtls-internal-cert  # *.taobao.caep.uk 内网 wildcard
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ListenerSet
metadata:
  name: team-a-listenerset
spec:
  parentRef:
    name: tenantmtls-gateway
  listeners:
  - name: https-team-a
    protocol: HTTPS
    port: 443
    hostname: "*.team-a.intra.domain"
    tls:
      mode: Terminate
      certificateRefs:
      - name: team-a-internal-cert  # *.team-a.intra.domain wildcard
```

**原方案假设的链路**:

```
External Client → GLB 终止 → 重建 TLS 到 PSC NEG
  → SNI 字段 = tenantmtls.taobao.caep.uk(原客户端)
  → Master Gateway 用 SNI 选 listener
  → team-a-listenerset(hostname *.team-a.intra.domain) 不匹配 → fallback ?
  → team-b-listenerset(hostname *.team-b.intra.domain) 不匹配 → fallback ?
```

### 3.2 架构师还原问题 — 真实情况

由于 §2 已经确认 **GLB 不会透传客户端原 SNI 给 PSC NEG**,Master Gateway 实际收到的 SNI 是 GLB 重建 TLS 时**自行决定**的值(可能是空字符串、可能是 PSC NEG endpoint 的 IP、可能是 `tlsSettings.sni` 配置值)。

**3 个可能的真实链路**:

#### 场景 A:GLB 重建 TLS 时 SNI 字段为空

```
Master Gateway Envoy 收到 ClientHello SNI = (空)
  → 没有 filter_chain_match.server_names 命中 hostname `*.team-a.intra.domain`
  → 没有 filter_chain_match.server_names 命中 hostname `*.team-b.intra.domain`
  → 也没法命中主 Gateway 的 `https` listener(它也没设置 hostname,默认是空 hostname)
  → Envoy 行为:落到 default filter_chain,但此时 frontend mTLS 已经验完,只能 421/404
  → 实际效果:ListenerSet 配置**完全失效**,team-a 和 team-b 都被路由到主 Gateway 的 https listener
```

#### 场景 B:GLB 重建 TLS 时 SNI 字段 = PSC NEG endpoint hostname / IP

```
Master Gateway Envoy 收到 ClientHello SNI = "<PSC endpoint IP>" 或其他非业务域名
  → 不会命中任何 team-a/team-b 业务 hostname
  → 同场景 A 的结果
```

#### 场景 C:业务方在 Backend Service 配置了 `tlsSettings.sni`

> 业务方可以**显式**给 backend service 设置 `tlsSettings.sni`(参考 [`backend-authenticated-tls-setup`](https://cloud.google.com/load-balancing/docs/backend-authenticated-tls-setup)):
>
> ```yaml
> tlsSettings:
>   sni: "tenantmtls-internal.intra.domain"  # 任意固定字符串
> ```
>
> 此时 GLB 重建 backend TLS 时会用这个固定 SNI 发出去。**但这不会因不同 client 而变化** — 它是个**全局固定值**。
>
> → **场景 C 的价值**:让 Master Gateway 能选到一个 listener(比如 hostname = 这个固定值的 listener),但**不能按 Team 区分**(所有 Team 共用同一个 SNI)。
- ![backend-authenticated-tls-setup](./setup_backend_authenticated_TLS.svg)
### 3.3 架构师判断 — ListenerSet 的 hostname 在当前架构下**没有作用**

| ListenerSet 配置 | 实际作用 | 业务方影响 |
|---|---|---|
| `hostname: "*.team-a.intra.domain"` | ❌ 不会触发(GLB 不传客户端原 SNI) | listener 选择无法按 Team 分流 |
| `hostname: "*.team-b.intra.domain"` | ❌ 不会触发(同上) | 同上 |
| `certificateRefs: team-a-internal-cert` | ⚠️ 部分触发 — Envoy 会在 SNI 匹配 hostname 时用对应的 cert;但 SNI 不匹配时 fallback 到主 Gateway cert | cert 选择无法按 Team 分流 |
| `tls.mode: Terminate` | ✅ 触发 — TLS 终止在 Envoy | 无变化(仍由 Envoy 终止) |

→ **3 个 ListenerSet + 3 个 wildcard cert 的设计在当前架构下等价于 1 个 listener + 1 个 wildcard cert**。

---

## 4. 修正方案 — 共享 GLB + 共享 listener + URI-SAN 防漂移

### 4.1 修正核心思路

既然 SNI 在当前架构(GLB + PSC NEG + Master K8s Gateway)下**不能按 Team 分流**,**防漂移能力必须完全依赖**:

1. **GLB 注入 URI-SAN header**(已经验证,见 [`tenant-mtls-cn.md` §0.3](./tenant-mtls-cn.md))
2. **K8s Gateway HTTPRoute `matches[].headers` 按 URI-SAN 路由**(独立于 SNI)

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

### 4.2 Master K8s Gateway 修正后的 YAML(架构师建议版)

```yaml
# =============================================================
# Master K8s Gateway — 修正版(共享 listener + URI-SAN 防漂移)
# 重要变化:
#   1. 不再需要 ListenerSet(消除 hostname 不生效的伪配置)
#   2. 单一 listener,单一 wildcard cert
#   3. 防漂移 100% 依赖 HTTPRoute matches[].headers(URI-SAN)
# =============================================================
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tenantmtls-gateway
  namespace: gateway-system
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    # hostname 字段不设置 → 接受任何 SNI(GLB 重建的 SNI)
    tls:
      mode: Terminate
      certificateRefs:
      - name: tenantmtls-internal-wildcard-cert
        # 单一 wildcard cert:*.intra.domain
        # (由 CertManager 签发,内网 CA,覆盖所有 team-*.intra.domain)
        # 不需要为每个 Team 单独维护 cert
---
# HTTPRoute — URI-SAN 防漂移
# 关键:防漂移点不在 listener 选择,而在 HTTPRoute matches
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: tenant-routing
  namespace: gateway-system
spec:
  parentRefs:
  - name: tenantmtls-gateway
  rules:
  # ────────────────────────────────────────────────────────────
  # Team 1 规则:URI-SAN 精确匹配 + 路径前缀
  # ────────────────────────────────────────────────────────────
  - matches:
    - path:
        type: PathPrefix
        value: /team1apiname/
      headers:
      - name: x-client-cert-uri-sans
        type: Exact
        value: "spiffe://caep.example/tenant/team-a/apiname1-client"
    backendRefs:
    - name: team1-svc
      port: 80
  # ────────────────────────────────────────────────────────────
  # Team 2 规则:URI-SAN 精确匹配 + 路径前缀
  # ────────────────────────────────────────────────────────────
  - matches:
    - path:
        type: PathPrefix
        value: /team2apiname/
      headers:
      - name: x-client-cert-uri-sans
        type: Exact
        value: "spiffe://caep.example/tenant/team-b/apiname1-client"
    backendRefs:
    - name: team2-svc
      port: 80
  # ────────────────────────────────────────────────────────────
  # 不匹配任何规则 → K8s Gateway 默认 404(防漂移内置)
  # ────────────────────────────────────────────────────────────
```

### 4.3 与原方案对比

| 维度 | 原方案([§3.2.1](./shared-glb-cn-a.md)) | 修正方案(本文 §4.2) |
|---|---|---|
| **Gateway listener** | 1 个 listener + 2 个 ListenerSet | 1 个 listener(**移除 ListenerSet**) |
| **listener hostname** | `*.team-a.intra.domain` / `*.team-b.intra.domain`(无效) | 不设置(hostname 字段去掉) |
| **TLS cert 数量** | 3 个 wildcard cert(主 + 2 个 ListenerSet)| 1 个 wildcard cert(`*.intra.domain`) |
| **listener 选择依据** | ❌ 试图用 SNI,但 SNI 来不了 | ✅ 不依赖 SNI(单一 listener 接受所有) |
| **防漂移点** | ListenerSet hostname(失效) | HTTPRoute `matches[].headers`(URI-SAN) |
| **K8s Gateway 控制面冲突** | ⚠️ 多 ListenerSet 共享同一 port 443 → `conflicted:True` 风险 | ✅ 单一 listener,无冲突 |
| **运维复杂度** | 高(3 cert,3 listener 维护)| 低(1 cert,1 listener) |

---

## 5. 业务方新提议 — 方案 D:在 PSC NEG 与 Master Gateway 之间插入 Nginx MIG 注入 SNI

> **本节是业务方在阅读 §2-§4 后的反向提议** — 如果业务方**坚持**要用 ListenerSet hostname 分流(而不是 §4 的 HTTPRoute header 分流),那么业务方提议**在 PSC tunnel 出口处插入一层 Nginx MIG**,由 Nginx 根据 path/apiname **强制重写 SNI** 再转发到 Master K8s Gateway。
>
> **架构师 lane 边界**:本节只做**可行性分析 + 粒度对比 + 风险评估 + 决策建议**,**不实施任何 provision**。infra-gcp 等待业务方决策后再行动。

### 5.1 业务方原话精确化

> "我在这里通过一个 nginx MIG 暴露对应的 service attachment... 因为 nginx 可以针对 api levels 强制针对 apiname 或者说 path 做头转换到内部的 listenset 侦听的 hostname,还可以是 team level 的比如 `*.team1.intra.domain` `*.team2.intra.domain`"

**架构师精确化**(把业务方口语转化为设计图):

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
                 ├─ 强制重写 Host 头 + SNI 到内部 hostname(规则见 §5.3)
                 └─ 重建 backend TLS(带正确 SNI) → Master K8s Gateway (443)
                    ├─ ListenerSet *.team1.intra.domain(team1 流量)
                    ├─ ListenerSet *.team2.intra.domain(team2 流量)
                    └─ 主 Gateway https listener
                       └─ HTTPRoute 按 path/header 路由 → 各 team svc
```

### 5.2 可行性 — 技术层面

**结论**:**技术上完全可行**。Nginx 注入 SNI 是标准能力,配置如下:

```nginx
# /etc/nginx/nginx.conf(最小 demo,仅用于 §5.2 展示可行性)
# ⚠️ 这是早期 demo,完整最终版见 §5.10.2(粒度 A,按 location 分别加载 Team cert)
#
# =============================================================
# Master Nginx MIG — SNI 注入示例
# 关键指令:
#   proxy_ssl_server_name on  → 启用 SNI 注入(默认 off)
#   proxy_ssl_name <hostname> → 强制使用这个 hostname 作为 SNI
#   proxy_pass https://upstream  → 触发 TLS 重建
# =============================================================
server {
    listen 443 ssl;
    # Nginx 自己需要一张服务端 cert(接收 GLB 重建的 TLS)
    ssl_certificate     /etc/nginx/certs/master-nginx.crt;
    ssl_certificate_key /etc/nginx/certs/master-nginx.key;

    # ↓ 业务方原架构里这部分由 GLB 决定;现在 Nginx 接管
    location /team1apiname/ {
        # 强制 SNI = *.team1.intra.domain 的具体某值
        proxy_ssl_server_name on;
        proxy_ssl_name "team1apiname.team1.intra.domain";  # 或 *.team1.intra.domain 通配
        proxy_ssl_verify off;  # ⚠️ 内部网络,关闭 cert 验证;生产应开启
        proxy_pass https://master-k8s-gateway.intra.domain:443;
    }

    location /team2apiname/ {
        proxy_ssl_server_name on;
        proxy_ssl_name "team2apiname.team2.intra.domain";
        proxy_ssl_verify off;
        proxy_pass https://master-k8s-gateway.intra.domain:443;
    }
}
```

**权威证据**(Nginx 官方文档):
- [`ngx_http_proxy_module.html` § `proxy_ssl_name`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ssl_name) — "By default, the name of the proxied server is used... overridden by `proxy_ssl_name`"
- [`ngx_http_proxy_module.html` § `proxy_ssl_server_name`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ssl_server_name) — "Enables or disables passing of the server name through TLS Server Name Indication extension when establishing a connection with the proxied server"

**架构师技术判断**:
| 子能力 | Nginx 支持 | 备注 |
|---|---|---|
| 强制注入 SNI | ✅ `proxy_ssl_name` | 静态值,运行期不变 |
| 按 path 分流注入不同 SNI | ✅ `location` + `proxy_ssl_name` | 每个 location 一份规则 |
| 读 URI-SAN header 动态注入 SNI | ⚠️ 需 Nginx Lua 模块或变量映射 | 默认模块不直接支持 SPIFFE URI 解析 |
| TLS 终止 + 重建 | ✅ 标准能力 | 需服务端 cert |
| 健康检查 / 高可用 | ✅ Nginx upstream + health check | 需自管 MIG |

→ **静态 path → SNI 映射可行**;**动态 URI-SAN → SNI 映射需要扩展(不推荐)**。

### 5.3 业务方粒度决策 — 业务方已确认选粒度 A

业务方原话:> "其实我们的 API 都是 Team Level,我只需要给 Team Level 上线一次比如域名是 `*.team1.intra.domain` `*.team2.intra.domain` 类似这样的部署,他只能将对应的请求转发到不同 team 的 listenset... 其实每一个 team 有一个对应的配置就可以了"

**业务方决策**:**粒度 A(Team Level)** — **每 Team 一条 Nginx location**,**不是每 API 一条**。这恰好排除了架构师之前反对的"粒度 B 每 API 改 Nginx"风险。

| 粒度 | SNI 注入值 | Nginx 规则数 | wildcard cert | 维护负担 | 架构师评价 |
|---|---|---|---|---|---|
| **A. Team Level** ⭐ | `*.team1.intra.domain` / `*.team2.intra.domain` | **每 Team 一条 location**(Team 上线时改一次)| 2-3 个 wildcard cert | **低**(Team 数量稳定,几乎不变)| ✅ **业务方已选,架构师认可** |
| ~~B. API Level(精确)~~ | ~~`apiname1.team1.intra.domain` ...~~ | ~~每 API 一条 location~~ | — | — | ❌ **业务方已明确排除**(原话:"API 都是 Team Level") |
| C. API Level(通配) | `*.team1.intra.domain` / `*.team2.intra.domain` 但 path 不同 | Nginx 只按 Team 分,SNI 同 A | 2-3 个 wildcard cert | **低** | ✅ 与 A 等价,但 path 区分由 Gateway HTTPRoute 完成 |

**架构师关键观察**:
- **粒度 A 的运维负担很低** — Team 数量在业务方语境下是**有限且稳定**的(几个 Team),不会频繁变化
- **新增 Team 时**:增加 1 条 Nginx location + 1 个 wildcard cert + 1 个 ListenerSet(在 K8s Gateway) — **3 处协调修改,可接受**
- **新增 API 时**:**0 处修改**(由 K8s Gateway HTTPRoute 自动按 path 路由) — 这正是业务方原话想要的"API 不需要碰 Nginx"
- **业务方原话已确认排除粒度 B**(每 API 改 Nginx),所以架构师之前对 B 的反对**已被业务方化解**

### 5.4 与 §4 修正方案的对比

| 维度 | §4 修正方案(单一 listener + HTTPRoute header) | §5 方案 D(Nginx MIG 注入 SNI + 多 ListenerSet) |
|---|---|---|
| **K8s Gateway 拓扑** | 1 listener + 多 HTTPRoute | 1 listener + **N 个 ListenerSet** + 多 HTTPRoute |
| **TLS 终止点** | Master K8s Gateway 一处终止 | GLB → **Nginx MIG** → Master K8s Gateway(两处终止)|
| **防漂移依据** | HTTPRoute `matches[].headers`(URI-SAN) | ListenerSet hostname(SNI)+ HTTPRoute header(双保险) |
| **Nginx 维护成本** | **零** | 每次新增 Team / API 改 Nginx 规则 |
| **TLS 终止次数** | 1 次(GLB→Master Gateway)| 2 次(GLB→Nginx→Master Gateway)— 多一跳 RTT |
| **Nginx 服务端 cert** | 不需要 | 需要(内网 cert,Venafi 签发)|
| **Nginx 高可用 / 监控** | 不需要 | 需要(MIG + health check + Prometheus)|
| **架构复杂度** | 低 | **中-高** |
| **运维责任边界** | Master 平台管理员只管 K8s Gateway | Master 平台管理员同时管 Nginx MIG + K8s Gateway |
| **故障面** | 小(GLB + PSC + Gateway)| **大**(多一跳 Nginx 故障点)|
| **性能开销** | 低 | 中(Nginx 多一跳 TLS 终止 + 重建)|

### 5.5 架构师风险评估

| # | 风险 | 严重度 | 说明 |
|---|---|---|---|
| R5 | Nginx MIG 故障 → 所有内部流量中断(单点) | 中 | 已通过 MIG 多 VM 池缓解;需配 Prometheus + Alertmanager + health check 告警 |
| R6 | Nginx `proxy_ssl_verify off` 关闭后端 cert 验证 | 中 | 内部网络可接受,但应改为 `verify on` + 配 CA(见 §5.10 Nginx config) |
| R7 | Nginx 规则变更需 reload,期间新 Team 路径不可达 | 低 | reload 影响既有连接(优雅退出可缓解);**每 Team 才改一次,频次极低** |
| R8 | Nginx 注入的 SNI 字符串与 K8s Gateway 实际 ListenerSet hostname 必须**精确一致** | 中 | 任何拼写错误 → ListenerSet 不匹配 → 故障;需 CI 校验 + GitOps 单一源 |
| R9 | Nginx 与 GLB 之间的 TLS 终止 — Nginx 需要服务端 cert | 中 | Venafi 模板里新增一种 cert 类型(见 §5.10 cert 段) |
| R10 | 业务方 Nginx 自身可能成为新的攻击面(配置漏洞、SSL 中间人) | 中 | Config drift / cert 过期 / 漏洞修补需纳入日常运维 |
| R11 | §4 方案不需要 Nginx,**新增 Nginx 违背原"去 Nginx 化"架构目标** | 架构 | **业务方已明确选择** — 利用 ListenerSet hostname + Team wildcard cert 强绑定实现租户隔离 |

### 5.6 业务方决策 — 已确认采纳方案 D + 粒度 A,采纳理由

**业务方决策**:**采纳方案 D + 粒度 A**,在 PSC NEG 与 Master Gateway 之间插入 Nginx MIG,按 Team Level 注入 SNI 到对应 ListenerSet hostname。

**业务方采纳理由(架构师整理)**:

| # | 理由 | 对应 §5.6 原硬性需求 |
|---|---|---|
| 1 | **希望保留 ListenerSet hostname 分流** — 利用 Envoy 在 SNI 匹配时**用对应 Team 的 wildcard cert**(而非 default cert),实现**每 Team cert 与 hostname 强绑定** | 对应 #2(合规要求 cert 与 hostname 强绑定)|
| 2 | **业务方 API 都在 Team Level**(业务方原话),不需要 API Level 精细化 — 这恰好与 §4 方案形成对比 | 业务方架构直觉,与 §4 复杂度差异的依据 |
| 3 | **不希望改变 §5 之前的架构**,仅在 Master Project 内追加一层 — 业务方接受新增运维负担(R5-R11)换取 ListenerSet hostname 的天然隔离能力 | 对应 #1(下游系统只接受特定 hostname)|
| 4 | **架构师 §4 仍为参考方案** — 如果后续业务方发现方案 D 维护成本高于预期,可以平滑迁移回 §4(只需删除 Nginx MIG + 把 SNI 注入改为 URI-SAN header) | 架构可逆性 |

**架构师立场更新**:
- ✅ **架构师认可方案 D + 粒度 A 的业务方采纳理由** — 理由 1 命中 §5.6 #2 硬性需求,理由 2 排除了 §5.3 粒度 B 的扩展性问题
- ✅ **粒度 A 的运维负担可接受** — Team 数量稳定,几乎不会变
- ⚠️ **架构师仍提醒 R5-R11** — 这是新增组件的固有代价,业务方需要在交付前明确监控/告警/cert 轮换策略

**架构师明确反对的场景(本节更新后)**:
- ❌ 业务方后续想改成"每 API 一条 Nginx location"(粒度 B)— 立即 push back
- ❌ 业务方想用单 VM 而非 MIG 部署 Nginx — 单点故障,R5 严重度从"中"升级到"高"
- ❌ Nginx 不配 Prometheus 监控就上线 — 不可观测,故障无法告警

### 5.7 方案 D 决策流程图(已确认)

```
业务方决策:"已采纳方案 D + 粒度 A,按 Team Level 注入 SNI"
    │
    ├─ 业务方满足 §5.6 硬性需求 #2(cert 与 hostname 强绑定)✅
    ├─ 业务方已明确排除 §5.3 粒度 B(API Level 精确)✅
    │
    └─ 进入实施方案
        ├─ §5.9 完整 Master Project 拓扑(含 Nginx MIG)
        ├─ §5.10 Nginx MIG 完整 manifest(MIG 模板 / ServiceAttachment / CertManager / Nginx config)
        └─ §5.11 方案 D 完整请求流(覆盖双向)
```

### 5.8 业务方确认请求(交付前 — 多数已通过,等 Q11 澄清)

| # | 问题 | 业务方回答 |
|---|---|---|
| ~~Q5~~ | ~~Nginx MIG 注入 SNI 是否有硬性合规需求?~~ | ✅ 已通过(理由 1 命中 §5.6 #2)|
| Q6 | Master K8s Gateway 下游是否有**第 3 层系统**只接受特定 hostname?(§5.6 #1)| ✅ **已答复**:下游就是 Listenerset 的 hostname(`*.team-a.intra.domain`),由 Listenerset + Team wildcard cert 实现 Team 级别访问 — **这强化了方案 D 的必要性** |
| Q7 | 业务方是否**已有 Nginx 资产**可以复用?(§5.6 #3)| ✅ **已答复**:"组件现成,没有障碍" |
| ~~Q8~~ | ~~业务方下游服务是否期待特定 Host header?~~ | ✅ 已通过(理由 3)|
| Q9 | **粒度 A** 每 Team 一条 Nginx location — **业务方已确认** ✅ | ✅ 已确认 |
| Q10 | **Nginx 高可用方案** — 单 MIG 多 VM 池 / 多 region 互备 / 其他? | ✅ **已答复**:"这些都已经具备" — 架构师采用 **3 VM pool + health check + autoscaling + Prometheus exporter** |
| **Q11** | Nginx 服务端 cert 类型 — 用现有 `*.intra.domain` 通配(简化)还是新增 `nginx-mig.intra.domain` 独立 cert? | ✅ **业务方答复**:"本身就是多张证书,针对不同的 team 有不同的证书,*.team-a.intra.domain *.team-b.intra.domain"。**架构师确认**:每 Team 一张 Nginx 服务端 cert(`team-X-wildcard.crt/key`)= 该 Team Listenerset cert 同一张。Nginx 按 location 分别加载(§5.10.2)。原澄清文件 [`q11-nginx-cert-clarification.md`](./q11-nginx-cert-clarification.md) 已归档,业务方选**选项 B**。 |
| Q12 | Nginx MIG **VM 镜像** — Debian + nginx package / GCP Click-to-Deploy Nginx / 自定义 image? | ✅ **已答复**:"镜像标准,没有 violation,有内部管理机制;**配置文件上传到 8K 就有 Agent 同步** — 架构师确认:用 8K Agent 同步 nginx.conf + cert(替代 §5.10.3 中的 Secret Manager / CSI 方案) |
| Q13 | 是否要保留 §4 方案作为 **fallback / rollback 路径**?(架构师建议保留 — 见 §5.6 理由 4) | ✅ **业务方答复:保留 §4 作为 fallback** — 架构师确认 |

**架构师立场更新(Q11 已澄清后定稿)**:
- ✅ **6 个问题已通过**(Q6/Q7/Q9/Q10/Q11/Q12/Q13)
- ✅ 业务方对方案 D + 粒度 A 的决策**完全确认**,所有 13 个技术细节均已澄清
- ✅ Nginx 服务端 cert 与 Listenerset cert 严格对齐(每 Team 一张,Q11 选项 B)
- ✅ Nginx config + cert 同步走 8K Agent(Q12)

**架构师默认推荐(等 Q11 答复后更新)**:**§5 方案 D(业务方已确认)+ 粒度 A + Nginx MIG 3 VM 池 + 8K Agent 同步 nginx.conf/cert + Prometheus exporter + Venafi 签 cert + §4 作为 rollback**。

---

### 5.9 方案 D — Master Project 完整拓扑

```
                          ┌─────────────────────────────────────────────────────┐
                          │              Master Project                          │
                          │                                                     │
   ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │   ┌─────────────────────────────────────────────┐    │
  │  GLB 重建 TLS  │ ─ ─ ┼─► │       ServiceAttachment (Master)             │    │
   ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │   │       ┌─────────────────────────────────┐    │    │
        (Talent PSC       │   │       │   Regional Internal HTTPS LB    │    │    │
         NEG → tunnel)    │   │       │   (由 ServiceAttachment 自动生成) │    │    │
                          │   │       │   NEG: gce-l7-ilb-regional-mig  │    │    │
                          │   │       │        pointing at Nginx MIG      │    │    │
                          │   │       └────────────┬────────────────────┘    │    │
                          │   └────────────────────│─────────────────────────┘    │
                          │                        │                              │
                          │                        ▼                              │
                          │   ┌────────────────────────────────────────────┐      │
                          │   │  Master Nginx MIG (3 VM pool, regional)   │      │
                          │   │  ┌──────────────────────────────────────┐  │      │
                          │   │  │ Server:                              │  │      │
                          │   │  │   listen 443 ssl                     │  │      │
                          │   │  │   ssl_certificate nginx-mig.crt      │  │      │
                          │   │  │                                      │  │      │
                          │   │  │ location /team1apiname/ {            │  │      │
                          │   │  │   proxy_ssl_server_name on           │  │      │
                          │   │  │   proxy_ssl_name "*.team1.intra..." │  │      │
                          │   │  │   proxy_pass → Master K8s Gateway    │  │      │
                          │   │  │ }                                     │  │      │
                          │   │  │ location /team2apiname/ {            │  │      │
                          │   │  │   proxy_ssl_name "*.team2.intra..." │  │      │
                          │   │  │   proxy_pass → Master K8s Gateway    │  │      │
                          │   │  │ }                                     │  │      │
                          │   │  │                                       │  │      │
                          │   │  │ Prometheus exporter :9113             │  │      │
                          │   │  │ Health check :80/nginx_status        │  │      │
                          │   │  └──────────────────────────────────────┘  │      │
                          │   └─────────────────┬──────────────────────────┘      │
                          │                     │                                  │
                          │                     │ HTTPS (含正确 SNI)              │
                          │                     ▼                                  │
                          │   ┌────────────────────────────────────────────┐      │
                          │   │  Master K8s Gateway (gke-l7-rilb)          │      │
                          │   │  ├─ 主 Listener: https (default cert)      │      │
                          │   │  ├─ ListenerSet: *.team1.intra.domain       │      │
                          │   │  │   cert: wildcard-team1.crt (SNI 匹配)   │      │
                          │   │  ├─ ListenerSet: *.team2.intra.domain       │      │
                          │   │  │   cert: wildcard-team2.crt (SNI 匹配)   │      │
                          │   │  └─ HTTPRoute (path + URI-SAN header)       │      │
                          │   │     ├─ /team1apiname/* + URI-SAN team1 → team1-svc │
                          │   │     ├─ /team2apiname/* + URI-SAN team2 → team2-svc │
                          │   │     └─ default → 404 (防漂移)              │      │
                          │   └────────────────────────────────────────────┘      │
                          │                                                     │
                          └─────────────────────────────────────────────────────┘
```

**架构师新增元素清单**(从零开始,业务方之前未提供):
| 元素 | 数量 | 角色 |
|---|---|---|
| Master ServiceAttachment | 1 | 接收 PSC NEG 流量(由 Master 平台管理员创建) |
| Regional Internal HTTPS LB | 1 | 由 ServiceAttachment 自动生成,GFE 类型,ILB |
| Nginx MIG | 3 VM | 接受 ILB 流量,做 SNI 注入 |
| Master K8s Gateway | 1 | 接收 Nginx 转发的 HTTPS,用 SNI 选 ListenerSet |
| ListenerSet | N(每 Team 一个)| hostname `*.teamX.intra.domain` + Team wildcard cert |
| CertManager / Venafi | 1 套 | 签 Nginx 服务端 cert + 每 Team wildcard cert |

### 5.10 Nginx MIG 完整 manifest(架构师提供,infra-gcp 实施)

#### 5.10.1 组件清单

| 组件 | 类型 | 来源 | 关键配置 |
|---|---|---|---|
| Master Nginx MIG | GCP Managed Instance Group | infra-gcp 创建 | 3 VM × e2-medium,health check,autoscaling |
| ServiceAttachment | PSC ServiceAttachment(Master)| infra-gcp 创建 | ACCEPT_AUTOMATIC + NAT subnet + accept list |
| CertManager(issuer) | cert-manager + Venafi | 已存在(参考 [`venafi-team-cert-template.md`](./venafi-team-cert-template.md))| 2 类 cert:每 Team 一张 wildcard cert(`*.team-a.intra.domain` / `*.team-b.intra.domain`),**该 cert 既用于 K8s Gateway Listenerset,也用于 Nginx 服务端** |
| ILB(自动)| Regional Internal HTTPS LB | GCP 自动生成(ServiceAttachment 触发)| NEG → MIG |
| Prometheus 监控 | Prometheus exporter | infra-gcp | nginx-prometheus-exporter on :9113 |
| Cert 轮换 | cert-manager | 已存在 | 90 天自动续 |

#### 5.10.2 Nginx config(完整版,含 `proxy_ssl_name` 注入)

```nginx
# /etc/nginx/nginx.conf(架构师最终版,粒度 A — Team Level)
# 业务方已确认选粒度 A,每个 Team 一条 location
#
# ✅ 关于 Nginx 服务端 cert:业务方 Q11 已澄清,选"选项 B — 每 Team 一张 Nginx 服务端 cert
# 与该 Team ListenerSet cert 共享"(业务方原话:"本身就是多张证书,针对不同的 team 有不同的证书")。
# Nginx 按 location 分别加载与 Listenerset 同一张 wildcard cert,替换 cert 时一张替换一张。

# ↓↓↓ 全局性能 / TLS 优化(标准做法,本节不展开) ↓↓↓
worker_processes auto;
worker_rlimit_nofile 65535;
events { worker_connections 4096; }

http {
    # ↓↓↓ TLS server 配置(接收 GLB 重建的 backend TLS) ↓↓↓
    # 注意:Nginx 服务端 cert 与 Listenerset cert 同一张
    # (例如 team-a-listenerset 用 *.team-a.intra.domain,这里也用 *.team-a.intra.domain)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # ↓↓↓ 上游 — Master K8s Gateway ILB(由 ServiceAttachment 自动生成) ↓↓↓
    upstream master-k8s-gateway {
        # 内部 ILB 的 DNS 名(由 GCP 自动注册)
        server master-tenantmtls-ilb.ilb.region.master.project.internal:443;
        keepalive 32;
    }

    # ↓↓↓ Prometheus metrics 输出(nginx-prometheus-exporter) ↓↓↓
    log_format prometheus '$remote_addr - $remote_user [$time_local] '
                          '"$request" $status $body_bytes_sent '
                          '"$http_referer" "$http_user_agent" '
                          'rt=$request_time uct=$upstream_connect_time '
                          'uht=$upstream_header_time urt=$upstream_response_time '
                          'usni="$upstream_ssl_server_name"';  # ⚠️ 记录注入的 SNI(可观测性)
    access_log /var/log/nginx/access.log prometheus;

    # ↓↓↓ server_name 强制为业务方域名(让 GLB 重建的 TLS SNI 落到 default server) ↓↓↓
    server {
        listen 443 ssl default_server;
        server_name tenantmtls.taobao.caep.uk;  # ⚠️ 强制 SNI(让 client cert chain hostname 校验通过)
        # 注意:此处不声明 ssl_certificate — 由 location 内按 Team 分别加载

        # 健康检查端点(GCP MIG health check 探测)
        location /nginx_status {
            stub_status;
            access_log off;
            allow 127.0.0.1;     # 只允许 localhost
            allow 10.0.0.0/8;    # GCP health check 来源 IP
            deny all;
        }

        # ↓↓↓ 核心:Team Level SNI 注入 + 每 Team 服务端 cert 加载 ↓↓↓

        # Team 1 — *.team-a.intra.domain cert
        location /team1apiname/ {
            # Nginx 服务端 cert — 与 Listenerset team-a-listenerset **同一张**
            ssl_certificate     /etc/nginx/certs/team-a-wildcard.crt;
            ssl_certificate_key /etc/nginx/certs/team-a-wildcard.key;

            # SNI 注入到上游(Master K8s Gateway)
            proxy_ssl_server_name on;
            proxy_ssl_name "team-a.intra.domain";  # 匹配 Listenerset *.team-a.intra.domain
            proxy_ssl_protocols TLSv1.2 TLSv1.3;
            proxy_ssl_verify on;                   # 验证 Gateway cert
            proxy_ssl_trusted_certificate /etc/nginx/certs/master-gateway-ca.crt;

            # 转发 HTTP 头
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass https://master-k8s-gateway;
        }

        # Team 2 — *.team-b.intra.domain cert
        location /team2apiname/ {
            # Nginx 服务端 cert — 与 Listenerset team-b-listenerset **同一张**
            ssl_certificate     /etc/nginx/certs/team-b-wildcard.crt;
            ssl_certificate_key /etc/nginx/certs/team-b-wildcard.key;

            # SNI 注入到上游
            proxy_ssl_server_name on;
            proxy_ssl_name "team-b.intra.domain";
            proxy_ssl_protocols TLSv1.2 TLSv1.3;
            proxy_ssl_verify on;
            proxy_ssl_trusted_certificate /etc/nginx/certs/master-gateway-ca.crt;

            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_pass https://master-k8s-gateway;
        }

        # 默认 — 不匹配任何 /teamXapiname/ 时返回 404
        location / {
            return 404;
        }
    }
}
```

**关键配置要点**(架构师校准):
| 指令 | 值 | 原因 |
|---|---|---|
| `proxy_ssl_server_name` | `on` | **关键** — 默认 off,SNI 不会发出去 |
| `proxy_ssl_name` | `"teamX.intra.domain"` | 注入的 SNI 字符串,必须与 Gateway ListenerSet hostname **完全一致** |
| `proxy_ssl_verify` | `on` | 必须验证 Gateway cert;off 的话 SSL 中间人攻击无法防护(R6 缓解)|
| `proxy_ssl_trusted_certificate` | Master Gateway CA bundle | 让 Nginx 信任 Gateway 颁发的 wildcard cert |
| `upstream` keepalive | `32` | 减少 TLS 握手次数,提升性能 |
| `access_log` prometheus format | 自定义 | 记录 `usni`(upstream_ssl_server_name)— **可观测注入的 SNI**,便于故障排查 |

#### 5.10.3 Startup script(MIG 模板)— Nginx config 注入 + 多 Team cert 加载

```bash
# /var/lib/google/startup-script.sh(架构师最终版)
# 业务方 Q12 已确认:配置文件上传到 8K,Agent 定期同步到本机
# 因此不需要 Secret Manager / CSI Driver / gsutil,直接由 8K Agent 拉到 /etc/nginx/

#!/bin/bash
set -euo pipefail

# ↓ 1. 安装 nginx + nginx-prometheus-exporter
apt-get update -y
apt-get install -y nginx prometheus-nginx-exporter

# ↓ 2. 创建 cert 挂载目录(每 Team 一张 wildcard cert)
mkdir -p /etc/nginx/certs

# ↓ 3. 8K Agent 同步 cert(业务方 Q12 已确认机制)
# 8K 是业务方内部配置管理平台,Agent 定期把 /etc/nginx/ 下的文件从 8K 拉到本机
# 这里依赖 8K Agent 已安装并配置 /etc/nginx/ 同步规则
# 典型 cert 文件(由 8K 同步):
#   /etc/nginx/certs/team-a-wildcard.crt  (与 Listenerset team-a-listenerset 同一张)
#   /etc/nginx/certs/team-a-wildcard.key
#   /etc/nginx/certs/team-b-wildcard.crt
#   /etc/nginx/certs/team-b-wildcard.key
#   /etc/nginx/certs/master-gateway-ca.crt (Master Gateway 的 CA bundle,用于 proxy_ssl_verify)
chmod 600 /etc/nginx/certs/*.key 2>/dev/null || true

# ↓ 4. 验证 cert 已同步(8K Agent 通常每 30s-2min 同步)
# 如果 cert 还没到,nginx 启动会失败 — 让 8K Agent 先跑一段时间
echo "Waiting for 8K Agent to sync certs..."
for i in {1..30}; do
    if [[ -f /etc/nginx/certs/team-a-wildcard.crt && \
          -f /etc/nginx/certs/team-a-wildcard.key && \
          -f /etc/nginx/certs/team-b-wildcard.crt && \
          -f /etc/nginx/certs/team-b-wildcard.key ]]; then
        echo "✅ All certs synced from 8K"
        break
    fi
    sleep 2
done

# ↓ 5. 测试 Nginx config(语法检查,失败则不启动)
nginx -t
if [[ $? -ne 0 ]]; then
    echo "❌ Nginx config test failed — refusing to start"
    exit 1
fi

# ↓ 6. 启动 nginx + Prometheus exporter
systemctl enable nginx
systemctl restart nginx
prometheus-nginx-exporter -nginx.scrape-uri=http://127.0.0.1/nginx_status &

echo "✅ Nginx MIG startup complete at $(date)"
```

**架构师关键校准**(基于业务方 Q12 答复):
- **不走 Secret Manager / CSI / gsutil** — 业务方已有 8K 配置同步机制,直接用
- **8K Agent 同步 nginx.conf + cert** — 更新 config 时不需要重建 MIG,只需 8K 上传新文件 + Agent 自动同步 + `nginx -s reload`(可由 8K Agent 或 systemd timer 触发)
- **`nginx -t` 语法检查** — 防止坏 config 让 nginx 启动失败,影响 health check
- **Cert 文件命名与 §5.10.2 Nginx config 严格对应**:
  - `team-a-wildcard.crt/key` — 与 ListenerSet `team1-wildcard-cert` 同一张(`*.team-a.intra.domain`)
  - `team-b-wildcard.crt/key` — 与 ListenerSet `team2-wildcard-cert` 同一张(`*.team-b.intra.domain`)

#### 5.10.4 ServiceAttachment + ILB 配置要点

业务方 ServiceAttachment 由 Master 平台管理员创建,**YAML 参考**官方文档(原文参考 [`kubernetes-engine/docs/how-to/internal-load-balancing-across-vpc-net`](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing-across-vpc-net)):

```yaml
apiVersion: networking.gke.io/v1
kind: ServiceAttachment
metadata:
  name: master-tenantmtls-svc-attach
  namespace: master-system
spec:
  connectionPreference: ACCEPT_AUTOMATIC
  natSubnets:
  - master-psc-nat-subnet       # NAT subnet,Master Project 内
  proxyProtocol: false
  reconcileConnections: false
  resourceRef:
    kind: Service
    name: master-nginx-mig-service  # Nginx MIG 暴露的 Service
```

**架构师校准**:
| 字段 | 值 | 原因 |
|---|---|---|
| `connectionPreference` | `ACCEPT_AUTOMATIC` | 默认接受所有 PSC NEG(需配合 project allowlist)|
| `natSubnets` | Master 内 NAT subnet | PSC 必备,不能省略 |
| `proxyProtocol` | `false` | Nginx 直接处理 TLS,不需要 proxy protocol 头 |
| `resourceRef.kind` | `Service` | 指向 Nginx MIG 的 K8s Service(由 MIG 创建后自动暴露)|

#### 5.10.5 K8s Gateway + ListenerSet(粒度 A)

```yaml
# Master K8s Gateway — 主 Gateway
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tenantmtls-gateway
  namespace: gateway-system
spec:
  gatewayClassName: gke-l7-rilb  # ⚠️ 注意:这里是 internal ILB(不是 global external)
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    tls:
      mode: Terminate
      certificateRefs:
      - name: tenantmtls-default-cert  # default cert(SNI 不匹配时用)

---
# ListenerSet Team 1
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ListenerSet
metadata:
  name: team-a-listenerset
  namespace: gateway-system
spec:
  parentRef:
    name: tenantmtls-gateway
  listeners:
  - name: https-team-a
    protocol: HTTPS
    port: 443
    hostname: "*.team-a.intra.domain"  # ⚠️ Nginx 注入的 SNI 必须匹配这里
    tls:
      mode: Terminate
      certificateRefs:
      - name: team-a-wildcard-cert  # *.team-a.intra.domain wildcard cert(与 Nginx team-a-wildcard.crt 同一张)

---
# ListenerSet Team 2(同结构)
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ListenerSet
metadata:
  name: team-b-listenerset
  namespace: gateway-system
spec:
  parentRef:
    name: tenantmtls-gateway
  listeners:
  - name: https-team-b
    protocol: HTTPS
    port: 443
    hostname: "*.team-b.intra.domain"
    tls:
      mode: Terminate
      certificateRefs:
      - name: team-b-wildcard-cert  # *.team-b.intra.domain wildcard cert(与 Nginx team-b-wildcard.crt 同一张)

---
# HTTPRoute — 防漂移(与 §4 修正方案相同)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: tenant-routing
  namespace: gateway-system
spec:
  parentRefs:
  - name: tenantmtls-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /team1apiname/
      headers:
      - name: x-client-cert-uri-sans
        type: Exact
        value: "spiffe://caep.example/tenant/team-a/apiname1-client"
    backendRefs:
    - name: team1-svc
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: /team2apiname/
      headers:
      - name: x-client-cert-uri-sans
        type: Exact
        value: "spiffe://caep.example/tenant/team-b/apiname1-client"
    backendRefs:
    - name: team2-svc
      port: 80
```

**关键校准**:
- `gatewayClassName: gke-l7-rilb` — 因为 Nginx 在 Master Project 内,Gateway 也是 Master 内 → 内部 LB
- ListenerSet hostname **必须与 Nginx `proxy_ssl_name` 完全一致**(R8 风险缓解)
- **保留 HTTPRoute URI-SAN header 匹配** — 即使 SNI 已分流,**保留 header 匹配作为双保险**(防漂移)

### 5.11 方案 D 完整请求流(覆盖双向)

#### 5.11.1 Forward(正常路径 Team 1)

```
[1] External Client (Team 1)
    TLS ClientHello
      SNI = "tenantmtls.taobao.caep.uk"
      client cert = CN=apiname1, URI-SAN=spiffe://.../team-a/apiname1-client

[2] GLB Global External HTTPS LB (Talent)
    ├─ frontend TLS 终止,TrustConfig 验 client cert chain ✓
    ├─ URL Map path rule: /team1apiname/* → Backend Service team1-bs
    ├─ 注入 14 个 client cert headers(含 X-Client-Cert-URI-SANs)
    └─ 重建 backend TLS(SNI 空/固定)→ PSC NEG

[3] PSC tunnel → Master ServiceAttachment

[4] Regional Internal HTTPS LB(由 ServiceAttachment 自动生成)
    └─ NEG 指向 Master Nginx MIG

[5] Master Nginx MIG(3 VM pool)
    ├─ 接受 TLS,使用 *.intra.domain 通配 cert
    ├─ 解密 HTTP,匹配 location /team1apiname/
    ├─ 重建 backend TLS 到 Master K8s Gateway:
    │   ⚠️ 关键:proxy_ssl_name = "team1.intra.domain"(SNI 注入)
    │   ⚠️ ClientHello SNI = "team1.intra.domain"
    └─ proxy_pass → master-k8s-gateway (Master ILB)

[6] Master K8s Gateway Envoy
    ├─ 收到 TLS ClientHello SNI = "team1.intra.domain"
    ├─ filter_chain_match.server_names 匹配:
    │   ListenerSet team1-listenerset hostname "*.team1.intra.domain" ✓
    ├─ 终止 TLS,使用 team1-wildcard-cert(*.team1.intra.domain)
    ├─ 解密 HTTP,匹配 HTTPRoute:
    │   /team1apiname/* + X-Client-Cert-URI-SANs=spiffe://.../team-a/apiname1 ✓
    └─ 转发 → team1-svc

[7] team1-svc → 业务方 Pod(无 TLS,K8s Gateway 已终止)
    处理业务逻辑
```

#### 5.11.2 Reverse(治理)— 方案 D 新增的责任点

| 维度 | 角色 | 资源 / 操作 |
|---|---|---|
| **Nginx MIG 部署** | Master 平台管理员 | MIG 模板、startup script、Secret Manager config、Prometheus exporter |
| **Nginx config 维护** | Master 平台管理员 | 新增 Team 时:1) Nginx location 1) Team wildcard cert 1) Gateway ListenerSet 1) HTTPRoute — **4 处协调修改** |
| **Nginx config 版本控制** | Master 平台管理员 | Git repo + Secret Manager 同步 + CI 校验 R8 风险(SNI 字符串与 ListenerSet hostname 一致)|
| **Nginx 服务端 cert 签发/轮换** | Venafi Admin + Master 平台管理员 | Venafi policy + cert-manager 同步到 Secret Manager,90 天自动续 |
| **每 Team wildcard cert** | Venafi Admin + Master 平台管理员 | 每 Team 一张 `*.teamX.intra.domain` cert(Venafi policy 模板) |
| **Master Gateway ListenerSet** | Master 平台管理员 | 每个 Team 一个,hostname 与 Nginx `proxy_ssl_name` 严格一致 |
| **HTTPRoute(双保险)** | Master 平台管理员 | URI-SAN header 匹配,即使 SNI 不对也会 reject |
| **Master K8s Gateway cert(默认)** | Master 平台管理员 | tenantmtls-default-cert(SNI 不匹配时 fallback) |
| **Prometheus 监控** | Master 平台管理员 | nginx-prometheus-exporter on :9113 + Alertmanager(连接错误率 > 1% 告警) |
| **故障响应(单跳)** | Master 平台管理员 | Nginx 健康 → MIG 自动重建 VM;Nginx 全挂 → ServiceAttachment 报错 → Talent 侧 GLB 收到 5xx |
| **业务方 cert 签发/吊销** | Venafi Admin + Team 用户 | 见 [`venafi-team-cert-template.md`](./venafi-team-cert-template.md) |
| **审计日志** | 所有平台管理员 | GLB:Cloud Logging;Nginx:access log to Cloud Logging;Gateway:envoy access log;ServiceAttachment:VPC Flow Logs |
| **漂移事件响应** | 业务方 + Master 平台管理员 | 任何 team-X cert 访问 /teamYapiname → Nginx 注入 teamY SNI → ListenerSet teamY 选中 → HTTPRoute URI-SAN 头**不匹配** → 404(双保险)|

#### 5.11.3 关键反向问题(架构师纪律)

> **Q**:Nginx 注入的 SNI 必须是精确的固定字符串,业务方有 Team 新增时怎么办?
>
> **A**:每新增一个 Team,**3 处协调修改**:
> 1. Master Nginx config — 加 1 条 `location /teamXapiname/` + 注入 `proxy_ssl_name "teamX.intra.domain"`
> 2. K8s Gateway — 加 1 个 ListenerSet,hostname `*.teamX.intra.domain` + 引用 Team wildcard cert
> 3. CertManager — 签 `*.teamX.intra.domain` wildcard cert(由 Venafi policy 自动)
> 4. HTTPRoute — 加 URI-SAN 头匹配规则(每 API 一条)
>
> **4 处协调修改是已知代价** — 业务方用 GitOps(参见 §5.10.3 Secret Manager 同步)可以**一次 PR 完成**。

> **Q**:Nginx MIG 故障时,Talent GLB 会收到什么错误?
>
> **A**:
> - 单 VM 故障 → MIG 自动重建,无影响(R5 缓解)
> - 整个 MIG 故障 → ILB 健康检查失败 → ServiceAttachment 返回 5xx → Talent GLB 收到 backend error → 用户看到 502
> - 此时 Talent GLB **无 fallback 路径**(§4 方案同样无 fallback) — 这是架构可逆性的另一个理由(§5.6 理由 4)

> **Q**:为什么方案 D 还要保留 HTTPRoute URI-SAN 头匹配(双保险)?
>
> **A**:
> - SNI 是**第一道防线** — ListenerSet 选错就直接 421/404
> - URI-SAN 头是**第二道防线** — 即使 SNI 注入对了(比如 Nginx 配置错误把 team1 注入成 team2),ListenerSet 选了 team2,但 HTTPRoute 检查 URI-SAN 是 team1 的 → 不匹配 → 404
> - **双保险**避免"单一错误导致完全绕过防漂移"

> **Q**:Nginx 服务端 cert 必须用 `*.intra.domain` 通配吗?还是每 Team 一张?
>
> **A**:
> - Nginx 服务端 cert 只需覆盖**所有 Team wildcard hostname 的父域** — 一张 `*.intra.domain` 通配即可
> - 这是 Nginx 接受的 cert,与业务方 client cert、Gateway Team wildcard cert **完全独立**
> - **不要每 Team 一张 Nginx cert** — 增加管理负担,无安全收益(内部 cert,只需信任链正确)|

---

## 6. 修正方案的完整请求流(覆盖双向)

### 6.1 Forward(请求数据流)— 正常路径 Team 1 访问

```
[1] External Client (Team 1 用户)
    TLS ClientHello
      SNI = "tenantmtls.taobao.caep.uk"
      client cert = CN=apiname1, URI-SAN=spiffe://caep.example/tenant/team-a/apiname1-client

[2] GLB Global External HTTPS LB(Talent Project)
    ├─ frontend TLS 终止,TrustConfig 验 client cert chain
    │   ✓ cert 链 → Maplequad Internal CA → Root CA,chain_verified=true
    ├─ ServerTlsPolicy (REJECT_INVALID) ✓
    ├─ URL Map path rule: /team1apiname/* → Backend Service team1-bs
    │   (Cloud Armor team1-policy 应用:rate-limit, OWASP 规则)
    ├─ Backend Service 注入 14 个 client cert headers:
    │   X-Client-Cert-URI-SANs: spiffe://caep.example/tenant/team-a/apiname1-client
    │   X-Client-Cert-Chain-Verified: true
    │   X-Client-Cert-SPIFFE: spiffe://caep.example/tenant/team-a/apiname1-client
    │   X-Client-Cert-Subject-DN: CN=apiname1,...
    │   ... (其他 10 个)
    └─ 重建 backend TLS 到 PSC NEG:
        ⚠️ ClientHello SNI 字段 = (空) 或 GLB 内部 dummy
        ⚠️ client cert = GLB 自己的 client cert(用于 backend mTLS 验证)
        ⚠️ 与 [1] 的 client cert 无关

[3] PSC NEG (Talent) → PSC tunnel → Master ServiceAttachment

[4] Master K8s Gateway (Master Project)
    ├─ Envoy 收到 TLS ClientHello
    │   SNI = (空) — 不影响 listener 选择(单一 listener)
    ├─ 终止 TLS,使用 *.intra.domain wildcard cert
    ├─ 解密 HTTP 请求,检查 headers
    │   X-Client-Cert-URI-SANs: spiffe://caep.example/tenant/team-a/apiname1-client
    ├─ HTTPRoute team-routing 评估 matches:
    │   match #1: path /team1apiname/ + header X-Client-Cert-URI-SANs=spiffe://...team-a/apiname1 ✓
    │   → backendRef: team1-svc
    └─ 转发 HTTP 请求(无 TLS,因为 K8s Gateway 已终止)→ team1-svc (ClusterIP)

[5] Team 1 svc (cluster IP) → 业务方 Pod
    处理业务逻辑,不感知 cert / 防漂移(K8s Gateway 已做)
```

### 6.2 Reverse(治理)— 谁配置 / 谁监控 / 谁审计

| 维度 | 角色 | 资源 / 操作 |
|---|---|---|
| **frontend mTLS 验证** | **Talent 平台管理员** | TrustConfig(企业 CA Root/Intermediate)+ ServerTlsPolicy(REJECT_INVALID)+ 14 个 custom request headers 配置 |
| **path 路由 + Cloud Armor** | **Talent 平台管理员** | URL Map path rules + 每 Team 独立 Cloud Armor policy |
| **backend cert 验证**(如果 Backend Service 配了 backend mTLS)| **Talent 平台管理员** | BackendAuthenticationConfig(reference TrustConfig) |
| **PSC tunnel 接入** | **Talent 平台管理员 + Master 平台管理员** 协作 | PSC NEG(Talent)+ ServiceAttachment(Master)+ accept list / project allowlist |
| **K8s Gateway 终止 TLS** | **Master 平台管理员** | 单一 wildcard cert(*.intra.domain)、单一 listener |
| **HTTPRoute 防漂移** | **Master 平台管理员** | URI-SAN → backendRef 映射,定期 review 新增 API 的 cert 与 route 是否对齐 |
| **client cert 签发/吊销** | **Venafi Admin + Team 用户** | Venafi policy + cert 申请流程(见 [`venafi-team-cert-template.md`](./venafi-team-cert-template.md)) |
| **审计日志** | 所有平台管理员 | GLB:Cloud Logging 启用 `--enable-logging --logging-sample-rate=1.0`;K8s Gateway:envoy access log;Venafi:cert 签发/吊销事件 |
| **漂移事件响应** | **业务方 + Master 平台管理员** | 任何 team-X 的 cert 访问 /teamYapiname → HTTPRoute 不匹配 → Gateway 返回 404(内置);同时 Cloud Logging 记录请求,管理员可基于 URI-SAN + path 检索异常访问尝试 |

### 6.3 关键反向问题(架构师纪律:覆盖双向)

> **Q**:GLB 重建 backend TLS 时 SNI 是空,Master Gateway 用什么 cert 回应?
>
> **A**:单一 wildcard cert (`*.intra.domain`)。SNI 为空时 Envoy fallback 到该 listener 的 default cert,**不需要 per-team cert**。这就是 §4 修正方案大幅简化的根本原因。
>
> **Q**:如果业务方内部有跨 region 多套 Master Gateway,各自需要不同 wildcard cert 吗?
>
> **A**:不需要。每套 Master Gateway(每 region)用**自己**的 wildcard cert 即可,但 cert 的覆盖范围**只需要是内部域名通配**(`*.intra.domain`),**不必与 Team 挂钩**。
>
> **Q**:这个 cert 由谁签发?是否要企业 CA?
>
> **A**:必须由业务方企业 CA(或 Venafi 管理的企业 CA)签发,因为 Master Gateway 在内网 VPC,不能依赖公网 CA。详细流程见 [`venafi-team-cert-template.md`](./venafi-team-cert-template.md)。

---

## 7. 风险与遗留问题

### 7.1 已识别风险

| # | 风险 | 严重度 | 缓解 |
|---|---|---|---|
| R1 | ListenerSet 删除后,某些 team 用其他方式依赖 listener hostname(例如 WAF / NetworkPolicy)| 中 | 修正方案 §4.2 提供单一 listener + 多 HTTPRoute,业务方如有其他依赖需业务方核对 |
| R2 | wildcard cert `*.intra.domain` 签发需要内网 CA,且每个 Master region 各一份 | 中 | Venafi 模板已支持内网 cert 签发,新增 region 需额外流程 |
| R3 | HTTPRoute `matches[].headers` 精确匹配 — 如果 URI-SAN 拼写错误(YAML 字符串),route 不命中 → 业务方 Pod 收不到流量 | 中 | 在 Venafi 模板里**强约束** URI-SAN 命名(已写入 [`venafi-team-cert-template.md` §1.2](./venafi-team-cert-template.md));业务方 cert 申请后强制 pre-flight 校验 |
| R4 | 如果未来 GLB 升级支持透传 frontend SNI 给 PSC NEG(目前不支持,见 §2),`tlsSettings.sni` 显式配置仍然更稳 | 低 | 监控 GCP 官方文档更新 |

### 7.2 遗留问题(待业务方确认)

| # | 问题 | 建议 |
|---|---|---|
| Q1 | 原方案里 ListenerSet 写法是否已在生产部署?**如果是,需要按 §4 修正** | 业务方核对 |
| Q2 | Master K8s Gateway 当前有没有 wildcard cert `*.intra.domain` 已签发? | infra-gcp 核对 |
| Q3 | HTTPRoute header 匹配是否在 GKE Gateway GA 范围?(应 GA,但需核对当前集群版本) | infra-gcp 核对 |
| Q4 | 业务方是否希望保留每 Team 独立的 wildcard cert(出于运维习惯)?如果保留,可以用 `tlsSettings.sni` 显式配置 + ListenerSet 按 SNI 选 listener,但运维成本不降反升 — 架构师**不推荐** | 业务方决策 |

---

## 8. 架构师最终结论与交付建议

### 8.1 一句话结论

> **业务方怀疑完全正确**:**SNI 不能从 External Client 一路传到 Master K8s Gateway**,因为 GLB 在 backend TLS 握手时**不会透传 frontend SNI**(GCP 官方明确),且 PSC NEG 不属于 internet NEG 的 SNI 例外范围。
>
> **好消息是合并方案(A+B)的防漂移能力不依赖 SNI** — 它依赖 GLB 注入的 `X-Client-Cert-URI-SANs` HTTP header,**完全独立于 SNI**。
>
> **修正方案 §4**(单一 listener + HTTPRoute header 路由)— 架构师首推,**作为 fallback / rollback 路径保留**(业务方 Q13 已确认)。
>
> **业务方决策 — 方案 D + 粒度 A**(§5):**在 PSC NEG 与 Master Gateway 之间插入 Nginx MIG,按 Team Level 注入 SNI(`*.team-a.intra.domain` / `*.team-b.intra.domain`)**以激活 ListenerSet hostname 分流。
> - **业务方采纳理由**(§5.6):1) ListenerSet + Team wildcard cert 强绑定 2) API 都在 Team Level 3) 不改变 §5 之前的架构 4) §4 fallback 提供架构可逆性
> - **所有 13 个技术细节已澄清**(Q1-Q13):Nginx 服务端 cert 与 Listenerset cert 同一张(每 Team 一张,Q11 选项 B);8K Agent 同步 nginx.conf + cert(Q12);3 VM MIG + health check + autoscaling + Prometheus(Q10)
> - **架构师认可**:§5 方案 D + 粒度 A 为业务方最终选择;理由 4 排除粒度 B 扩展性问题;理由 1 命中 §5.6 #2 硬性需求
> - **架构师仍提醒**:R5-R11 是新增组件的固有代价,业务方需在交付前明确监控告警 + cert 轮换策略
> - **架构师反对**任何后续想把方案 D 改成"每 API 一条 Nginx location"(粒度 B)的提议 — 立即 push back

### 8.2 交付建议(已对齐业务方决策)

1. **更新 [`shared-glb-cn-a.md` §3.2.1](./shared-glb-cn-a.md)**:把 3 个 ListenerSet 写法替换为 §5.10.5 的 Gateway + ListenerSet + HTTPRoute 组合(架构师**不擅自动手**,等业务方拍板)
2. **infra-gcp**:按 §5.10 完整 manifest 创建 Master Nginx MIG、ServiceAttachment、CertManager issuer;按 §5.11.1 验证 7 段链路(GLB → Nginx → Gateway → svc)
3. **qa-gcp**:按 §5.11.1 流程,验证:
   - Team 1 cert + Team 1 path → 200(正常)
   - Team 1 cert + Team 2 path → 404(SNI 分流 + URI-SAN 头**双保险**)
   - Nginx MIG 单 VM 故障 → MIG 自动重建,无影响
   - Nginx MIG 全挂 → 502 + 告警
   - 8K Agent 同步新 cert → Nginx 自动 reload,无流量中断
4. **业务方**:所有 13 个技术细节已澄清,✅ 无未决问题
5. **架构师后续**:~~正式发布 ADR-014~~ → **已发布**,见 [`shared-glb-nginx-sni.md`](./shared-glb-nginx-sni.md)。待办:更新 [`shared-glb-cn-a.md` §3.2.1`](./shared-glb-cn-a.md) 为方案 D + 粒度 A 实现版本

### 8.3 严格原话引用列表(供维护者参考)

| # | 文档 | 关键原话 |
|---|---|---|
| C1 | [encryption-to-the-backends](https://cloud.google.com/load-balancing/docs/ssl-certificates/encryption-to-the-backends) | "load balancers don't use the Server Name Indication (SNI) extension for connections to the backend."(例外:internet NEG) |
| C2 | [backend-authenticated-tls-backend-mtls](https://cloud.google.com/load-balancing/docs/backend-authenticated-tls-backend-mtls) | "The load balancer doesn't pass the client's SNI hostname from the frontend TLS connection when connecting to a backend. However, backends can access the client's SNI hostname using a custom request header." |
| C3 | [negs 文档](https://cloud.google.com/load-balancing/docs/negs) | PSC NEG 类型是 `private-service-connect`,与 internet NEG 独立分类 |
| C4 | [private-service-connect-backends](https://cloud.google.com/vpc/docs/private-service-connect-backends) | "Only the supported load balancers can use Private Service Connect NEGs as backends." |
| C5 | [backend-authenticated-tls-setup](https://cloud.google.com/load-balancing/docs/backend-authenticated-tls-setup) | 提供 `tlsSettings.sni` 显式配置 backend SNI(但全局固定值,不能按 client 分流)|

---

## 9. ADR 编号 — ADR-014 已发布

> **本文档**:`shared-glb-cn-a-sni`(探索稿 — 已被取代,保留决策追溯)
>
> **ADR 编号**:**ADR-014 已发布**(`Accepted`,2026-09-05)— 见 [`shared-glb-nginx-sni.md`](./shared-glb-nginx-sni.md)
>
> **关联 ADR**:
> - ADR-009(GKE Pod mount internal NAS — 跨项目安全评审)
> - ADR-011(GKE Pod cross-project Bucket — 跨项目安全评审)
> - ADR-012 / 013(mTLS 跨项目 TLS 改造 / SNI 注入)
>
> **被引用**:本文档全部内容已并入 ADR-014 正式版。本节作为 ADR 编号追溯保留。

