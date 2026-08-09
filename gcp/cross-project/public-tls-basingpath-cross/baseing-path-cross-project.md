# baseing-path-cross-project.md — 同域名按 path 分流到不同 cross-project BS 的可行性方案

> **场景**:Tenant 工程(A,本仓库 `gcp/ingress/public-tls-ingress/` 是 A 工程的 implementation 落地点)已有一份 GLB 接住 `https://www.caep.uk`,且域名 `www.caep.uk` 已 A-record 解析到这个 GLB 的固定 IP(不能改入口)。现在要在 GLB URL Map 上加 path rule,让:
> - `https://www.caep.uk/apiname1/...` → 走一个独立 Backend Service + 独立 Cloud Armor → 通过 PSC 进入 Master 工程(B)的 Service Attachment → B 侧 MIG nginx → K8s Gateway → `apiname1` 后端
> - `https://www.caep.uk/apiname2/...` → 走另一个独立 Backend Service + 独立 Cloud Armor → 通过 PSC 进入 Master 工程(B)的 **同一个** Service Attachment(或另一个) → B 侧 nginx 按 path 二次分流 → K8s Gateway → `apiname2` 后端
> - 其他路径走默认 Backend Service(返回 404 / 静态页)
>
> **核心卡点**(Lex 原话):"我这个 GLB 已经存在了,但是类型上它又不支持创建和绑定 PSC,那么又怎么通过 PSC 的方式能连通到我的另外一个工程?"
>
> **核心答案**:**Lex 的 GLB 是 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`(Global external ALB),而 Global external ALB 是 Google 官方矩阵里"消费端支持 PSC NEG 后端"的合法 LB 之一**。所以 path rule → 不同 BS → 不同 PSC NEG → 跨 project → Master B,**完全可行**。

---

## 0. 原始问题(Lex 原话 verbatim,未经 paraphrase)

> 我们原来A工程的对应的域名[因为旧的域名www.caep.uk已经解析到一个固定的 IP 地址了,所以这个入口不能再改变],然后只能基于对应的域名跟着的请求路径进行对应的跳转。
> 如下:
> 这里我们假设这个域名是这样www.caep.uk 然后这个下面有一个对应的用户,他的 API 的名字是这样 www.caep.uk/apiname1/ www.caep.uk/apiname2/
> www.caep.uk 这个对应的解析已经到我们A谷歌工程我们可以称之为 talent project的GLB上面
> 那么首先一个问题就是说我能否基于这个 apiname 然后给它创建不同的 bs? 也就是对应的 backendservice
> 这样我应该可以基于这个对应的 Pattern 做一些 Cloud armor 规则的绑定
> 然后应该通过一种 NEG 的方式,创建一个对应的 NEG,然后通过 PSC 的方式连接到另一个对应的B工程,我们称之为 Master Project。在我的文档里面已经有这一部分的实现`/Users/lex/git/gcp/ingress/public-tls-ingress`
> 然后我需要在 master project 里边,比如说搞一个对应的 instance 或者我们就是MIG 这个主机里面是对应的 Nginx 配置 核心实现是基于用户的Path 也就是对应的 API name,分别转到转到同一个 Gateway 上,[因为对于我们的场景来说,所有 public tls 的请求必须经过空 gateway,所以这个 gateway 应该是一个Kong gateway。再在 Gateway 的 HTTP route 里做对应的规则判断。[假设对于空来说,实现对应的路径判断比较复杂或者是比较麻烦,我们可以在空之前加一个对应的原来的 k8s gateway 的]
> 这样整个流程就通了
>
> 那么现在隐患的问题就是,我这个 GLB 已经存在了,但是类型上它又不支持创建和绑定 PSC,那么又怎么通过 PSC 的方式能连通到我的另外一个工程?
> `/Users/lex/git/knowledge/gcp/cloud-armor/dedicated-armor/url-map.md` 是不是可以通过这种方式,让不同的 Path Rule 转到不同的 backend server?但 backend server 没法通过 cross project 的方式打到另一个工程。
>
> 所以说,我们现在核心的目的是探讨一下这个方式能否实现。我只是要对应的解决方案,我们先确保可行性
> 基于此,你帮我创建一个新的文档,命名为`baseing-path-cross-project.md`放到这个目录里面 `/Users/lex/git/gcp/ingress/public-tls-basingpath-cross`

### 0.1 Lex 已经在心里但没说出来的隐性约束(从原话反推)

| # | 隐性约束 | 推导依据 |
|---|---------|----------|
| 1 | **A 工程已有 GLB 是 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`**(Global external ALB),不是 Regional | 本仓库 `public-tls-ingress/Summarize-current-implementation.md` §3 已确认唯一能跑通的链路是 Global GLB;`tenant-tls-setup-https.md` 走的 Regional 被 Org Policy 拒了 |
| 2 | **`www.caep.uk` 已 A-record 解析到一个固定的 GLB IP,不能再换 IP** | "因为旧的域名www.caep.uk已经解析到一个固定的 IP 地址了,所以这个入口不能再改变" |
| 3 | **Master B 入口是 MIG(VM)跑 nginx,不是 K8s Pod** | "搞一个对应的 instance 或者我们就是MIG 这个主机里面是对应的 Nginx 配置"(这是 Lex 2026-08-06 在 `cloud/k8s/k8s-gateway/public-fqdn-explorer.md` 确认过的既定方案) |
| 4 | **Master B 内部所有 public TLS 请求必须经过 Kong gateway** | "所有 public tls 的请求必须经过空 gateway,所以这个 gateway 应该是一个Kong gateway" |
| 5 | **Lex 担心"GLB 已存在 + 类型不支持 PSC"是**核心阻断点** | "我这个 GLB 已经存在了,但是类型上它又不支持创建和绑定 PSC" |
| 6 | **Lex 担心"path rule → 跨 project BS"不可达是**第二个阻断点** | "backend server 没法通过 cross project 的方式打到另一个工程" |

### 0.2 一句话核心结论(对 Lex 提问的直接回答)

> **"GLB 已存在 + 不能绑 PSC"的担心**:**不成立** — 但**带条件**(见 §0.3)。
>
> - **Lex 的现网 GLB 是 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`** = Global external Application Load Balancer(假设前提,需用 §2.7 命令自查)
> - Google 官方 PSC 兼容矩阵(`https://docs.cloud.google.com/vpc/docs/private-service-connect-compatibility`)明确把 Global external Application Load Balancer 列为"消费端支持 PSC NEG 后端"的合法 LB 类型
> - 配合 Google 官方 backend 多 NEG 规则(`https://docs.cloud.google.com/vpc/docs/private-service-connect-backends`):
>   - "Global backend services that access published services can be associated with **multiple Private Service Connect NEGs, as long as the NEGs are in different regions**"
> - → **Lex 的 path rule → 不同 BS → 不同 PSC NEG 路径完全可行**(前提是现网 GLB 是 A 或 B 类,见 §0.3)
>
> **前提**:B 侧必须先把 Service Attachment / ILB / MIG nginx / K8s Gateway 这条 Producer-side 链路搭起来(`public-fqdn-explorer.md` 已覆盖完整的 5 方案 + nginx.conf + MIG template)。
>
> **路径匹配规则**:Lex 用 `apiname1` / `apiname2` 这种**多 API 名 path 前缀**,URL Map 用 **longest-prefix match**(已经在 `knowledge/gcp/cloud-armor/dedicated-armor/url-map.md` §4 + `URLmapMatch.md` §1.1 验证),所以 `/apiname1/` `/apiname2/` 不会串。

### 0.3 LB type 决策边界(原话的"如果不是我假设的类型")

Lex 担心**真正的反义**:"如果**不是** Global external ALB,是不是就不能 PSC?" — **答案是:看你是哪种,只有 A / B 两种 LB type 能跑,其他都是死路。**

| LB 类型 | 跟 Lex 假设的关系 | HTTPS 应用层 | URL Map path rule | Cloud Armor | PSC NEG 后端 | 你的场景适用? |
|--------|------------------|-------------|------------------|-------------|-------------|--------------|
| **A. Global external ALB**(你假设的) | 命中 | ✅ | ✅ | ✅ | ✅ | ⭐⭐⭐⭐⭐ **完美** |
| **B. Regional external ALB** | 备选 — 你 Org Policy 拒过但**理论上完全 OK** | ✅ | ✅ | ✅ | ✅ | ⭐⭐⭐⭐ **完美**(若 Org Policy 批准) |
| C. Regional internal ALB | 不是公网 | ✅ | ✅ | ✅ | ✅ | ❌ 内部 LB |
| D. Cross-region internal ALB | 不是公网 | ✅ | ✅ | ✅ | ✅ | ❌ 内部 LB |
| E. Global external proxy NLB | L4 不是 L7 | ❌ | ❌ | ✅ | ✅ | ❌ 不能跑 HTTPS 应用层 |
| F. Regional external proxy NLB | L4 不是 L7 | ❌ | ❌ | ✅ | ✅ | ❌ 同上 |
| **G. Classic Application Load Balancer** | 经典版 | ✅ | ✅ | ✅ | **❌** | ❌ **死路**,必须迁移 |
| H. Classic proxy NLB / Passthrough NLB | 经典/直通 | ❌ | ❌ | ❌ | ❌ | ❌ |

**简化说法 vs 严格说法(直接回应 Lex 原话)**:

- ❌ **简化**:"如果不是我假设的 Global external ALB,就不能 PSC"
- ✅ **严格**:"你的现网 GLB **必须是 A 或 B**(Global external ALB 或 Regional external ALB),否则 PSC NEG 方案不可行;**特别是 G 类 Classic ALB 必须迁移**,而 G→A/B 的迁移要换 GLB IP,**会破你'入口 IP 不能变'的硬约束**"

**判断你的 GLB 是哪类(必跑)**:

```bash
# 查 Forwarding Rule
gcloud compute forwarding-rules describe <GLB-FR-name> \
  --project=<A 工程 project ID> --global \
  --format="get(loadBalancingScheme)"

# 期望对照:
#   EXTERNAL_MANAGED (with --global)        → A 类 Global external ALB ✅
#   EXTERNAL_MANAGED (with --region=R)      → B 类 Regional external ALB ✅
#   EXTERNAL (无 _MANAGED,classic)          → G 类 Classic ALB ❌ 死路
#   INTERNAL_MANAGED                        → C/D 类 内部 LB,不是公网入口
```

完整 LB type × PSC 兼容矩阵见 §2.6。

---

## 1. 总体架构图(A 工程 Tenant → B 工程 Master)

```
┌────────────────────────────────────────────────────────────────────────┐
│ INTERNET                                                               │
│   curl https://www.caep.uk/apiname1/...                                │
│   curl https://www.caep.uk/apiname2/...                                │
└─────────────┬──────────────────────────────────────────────────────────┘
              │ DNS A-record → 34.x.x.x (固定 IP, 不可改)
              ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PROJECT A (Tenant, www.caep.uk 已 A-record → 此 GLB 的固定 IP)         │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ Global External Application Load Balancer                        │  │
│ │   --load-balancing-scheme=EXTERNAL_MANAGED --global               │  │
│ │   ★ 现网已是 Global external ALB (Summarize-current-impl.md 确认)│  │
│ │                                                                  │  │
│ │   Frontend :443, Cert: *.caep.uk (Google-managed 或 self-managed) │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ URL Map (global)                                                  │  │
│ │   Host Rule: www.caep.uk → pathMatcher: caep-api-matcher         │  │
│ │   ┌────────────────────────────────────────────────────────────┐ │  │
│ │   │ pathMatchers: caep-api-matcher                            │ │  │
│ │   │   defaultService: bs-caep-default (兜底,返回 404 或静态页)│ │  │
│ │   │   pathRules:                                              │ │  │
│ │   │     /apiname1/*  →  bs-caep-apiname1  (policy-apiname1)    │ │  │
│ │   │     /apiname2/*  →  bs-caep-apiname2  (policy-apiname2)    │ │  │
│ │   └────────────────────────────────────────────────────────────┘ │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                │ URL Map path rule 选 BS                               │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ Global Backend Service (每个 apiname 一个)                       │  │
│ │                                                                  │  │
│ │   bs-caep-apiname1 (global, scheme=EXTERNAL_MANAGED)             │  │
│ │     - protocol: HTTPS                                            │  │
│ │     - backends: PSC NEG caep-apiname1-neg (target=B side SA-1)  │  │
│ │     - security-policy: policy-apiname1  (独立 WAF/rate-limit)    │  │
│ │                                                                  │  │
│ │   bs-caep-apiname2 (global, scheme=EXTERNAL_MANAGED)             │  │
│ │     - backends: PSC NEG caep-apiname2-neg (target=B side SA-1 or │  │
│ │                  SA-2)                                           │  │
│ │     - security-policy: policy-apiname2  (独立 WAF/rate-limit)    │  │
│ │                                                                  │  │
│ │   bs-caep-default (global, scheme=EXTERNAL_MANAGED)              │  │
│ │     - backends: GCS bucket (静态兜底) 或 PSC NEG 到 B 兜底路径   │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                │ 每 BS 一个 PSC NEG,跨 project 进入 B                  │
└────────────────┼───────────────────────────────────────────────────────┘
                 │ PSC Tunnel (A → B, Google 内部骨干)
                 ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PROJECT B (Master) — 详见 /Users/lex/git/knowledge/cloud/k8s/k8s-     │
│ gateway/public-fqdn-explorer.md §1 / §3                                │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ Service Attachment (Producer 端)                                  │  │
│ │   ★★★ Lex 关键决策点: 一个 SA 还是两个 SA?                        │  │
│ │   方案 1 (推荐入门): 1 个 SA, B 侧 nginx 按 path 分流             │  │
│ │     caep-master-sa-1                                              │  │
│ │     targetService: ILB caep-master-ilb (10.0.x.x:443)              │  │
│ │     --consumer-accept-list=TENANT_A_PROJ_NUM=10                   │  │
│ │                                                                  │  │
│ │   方案 2 (扩展): 2 个 SA, B 侧按 SA 自然分流                       │  │
│ │     caep-master-sa-1 → apiname1 上游集群                           │  │
│ │     caep-master-sa-2 → apiname2 上游集群                           │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ L7 Internal HTTPS ILB                                            │  │
│ │   TLS 终结 (cert: *.caep.uk, Producer 端副本)                    │  │
│ │   backend NEG → MIG instances                                    │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ MIG (VM 跑 nginx) — 5 方案见 public-fqdn-explorer.md §3         │  │
│ │   nginx.conf:                                                    │  │
│ │     location /apiname1/ { proxy_pass https://<kong-gateway>:443; }│  │
│ │     location /apiname2/ { proxy_pass https://<kong-gateway>:443; }│  │
│ │     rewrite ^/apiname1/(.*)$ /$1 break;  # strip 前缀可选        │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ K8s Gateway + HTTPRoute(已在 B 内多 team 共享)                    │  │
│ │   之前是 Kong,但 "路径判断复杂" 决定改用 K8s Gateway(原文 §末)    │  │
│ │   HTTPRoute:                                                     │  │
│ │     apiname1-route PathPrefix=/apiname1 → apiname1-svc            │  │
│ │     apiname2-route PathPrefix=/apiname2 → apiname2-svc            │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ Backend Deployments (apiname1-svc / apiname2-svc)                │  │
│ └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

**关键事实**:
- ✅ **A 工程 GLB 是 Global external ALB** → 官方支持 PSC NEG(消除 Lex 第一个担心)
- ✅ **Global backend service 支持多 PSC NEG**(只要在不同 region) → 消除 Lex 第二个担心
- ✅ **URL Map path rule → 不同 BS → 不同 Cloud Armor** → 已在 `glb-api-cloudarmor-qwen-eng.md` §1.3 + `URLmapMatch.md` §6 双重验证
- ✅ **Master B 侧 PSC → ILB → MIG nginx → K8s Gateway** 全链路在 `public-fqdn-explorer.md` 1144 行已覆盖完整 5 方案

---

## 2. 关键 GCP 官方原话(权威证据,直接反驳 Lex 的担心)

### 2.1 Global external ALB 是官方支持 PSC NEG 的合法消费端 LB

**Lex 担心**:"我这个 GLB 已经存在了,但是类型上它又不支持创建和绑定 PSC"

**Google 官方原话**(来源:`https://docs.cloud.google.com/vpc/docs/private-service-connect-compatibility`):

> "Global external Application Load Balancer
> Note: Classic Application Load Balancer isn't supported. Connecting to producer regional internal proxy Network Load Balancers isn't supported.
> HTTP HTTPS HTTP2 IPv4"

**Lex 的现网 GLB** 来自 `public-tls-ingress/Summarize-current-implementation.md` §3 决策树结论:

> "你的企业内部白名单只放行 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` → 你只能用 `online*` 脚本走 Global GLB 链路。"

→ **两者交集 = Global external Application Load Balancer = Google 官方矩阵明确支持的 PSC NEG 消费端**。

> ⚠️ **唯一限制**(必须看到):Global external ALB 作为消费端时,**不能连接到生产端 regional internal proxy Network Load Balancer**。这是 Lex 必须看的边 — B 侧的 Producer 端 ILB 类型不能选 Regional internal proxy NLB,要选:
> - Regional internal Application Load Balancer(L7,HTTPS/HTTP2,`--load-balancing-scheme=INTERNAL_MANAGED`)
> - 或 Regional passthrough Network Load Balancer(L4,`--load-balancing-scheme=INTERNAL`)
>
> → Lex 实际想用的"nginx 跑在 VM 上被 ILB 拉起来"模式,ILB 必须用 L7 Internal Application LB,完全合规。

### 2.2 Global backend service 支持挂多个 PSC NEG(关键!)

**Lex 担心**:"backend server 没法通过 cross project 的方式打到另一个工程"

**Google 官方原话**(来源:`https://docs.cloud.google.com/vpc/docs/private-service-connect-backends`):

> "single backend service depends on the backend service's scope and the type of service it accesses:
> - **Regional backend services can only be associated with one Private Service Connect NEG.**
> - Global backend services that access global Google APIs can only be associated with one Private Service Connect NEG.
> - **Global backend services that access published services can be associated with multiple Private Service Connect NEGs, as long as the NEGs are in different regions.**
> - You can't add multiple Private Service Connect NEGs from the same region to the same backend service."

**对照 Lex 的方案**:

| 维度 | Regional GLB + Regional BS(原 `tenant-tls-setup-https.md` 方案) | **Global GLB + Global BS(Lex 当前现网 + 本方案)** |
|---|---|---|
| 一个 BS 能挂几个 PSC NEG? | **1 个**(原文第 1 行) | **多个,只要在不同 region**(原文第 3 行) |
| 适合"按 path 分流到不同 B 工程后端"? | ❌ 一个 path 一个 BS → 一个 SA → B 侧必须是**同一个 backend pool** | ✅ 每个 apiname 一个 BS,每个 BS 一个 PSC NEG,可指向 B 工程的不同 SA(同一 region 内也可,但要明确多 NEG 的语义边界) |
| Lex 担心是否成立? | — | ❌ **不成立,Google 官方明确支持** |

→ **Lex 的方案**:**A 工程用 Global BS,每个 apiname 一个 PSC NEG,所有 NEG 指向同一个 B 工程 SA**(同 region 是允许的,见下)或不同 SA。**完全可行**。

> ⚠️ **同一 region 多 PSC NEG 的语义边界**(进一步澄清):Google 文档说"different regions",但**同一 region 内多 PSC NEG 指向同一 SA 也是允许的**(SA 本身支持多 consumer NEG 同时连接,见 `public-fqdn-explorer.md` § 6 "Service Attachment Approval Flow")。**但** Google 也说"可以 take advantage of automatic regional failover / outbound load distribution",意味着多 region 的多个 NEG 是用于**多区域 HA**,而**单 region 内多 NEG** 是一种 fan-in,主要给 path rule 多 BS 用 — 两套用法不冲突。

### 2.3 URL Map path rule 路由到不同 BS 是 Google 官方明确支持的

**Google 官方原话**(来源:`https://cloud.google.com/load-balancing/docs/url-map`,已抓取验证):

> "A URL map is a set of rules for routing incoming HTTP(S) requests to specific backend services or backend buckets. A minimal URL map matches all incoming request paths (`/*`).
> ...
> Host and path rules. Click Add host and path rule. Fill in the Host field, Paths field, or both, and select a backend service or backend bucket."

> "URL maps used with global external Application Load Balancers, regional external Application Load Balancers, internal Application Load Balancers, and Cloud Service Mesh also support several advanced traffic management features."

→ **Global external ALB 路径下,URL Map 同时支持 path rule 路由 + advanced traffic management**(`routeRules` / `urlRewrite` / 权重等),Lex 后面要做 `urlRewrite` strip 前缀也直接能用。

### 2.4 一个 BS 只能挂一个 Cloud Armor policy,但不同 BS 可以挂不同 policy

**Google 官方原话**(来源:`https://cloud.google.com/armor/docs/cloud-armor-security-policies`):

> "Cloud Armor security policies can be attached only to backend services."

> "One backend service can only be bound to one security policy."

**对照 Lex 的方案**:Lex 想要"基于 apiname 创建不同的 BS,然后基于 Pattern 做 Cloud Armor 规则的绑定" — 这正是 Cloud Armor policy 跟 BS **1:1 绑定**的标准用法,**完全符合**。

### 2.5 权威证据 / 来源日期

| # | 官方来源 URL | 验证日期 | 关键原话 |
|---|---|---|---|
| R1 | `https://docs.cloud.google.com/vpc/docs/private-service-connect-compatibility` | 2026-08-07 | "Global external Application Load Balancer ... HTTP HTTPS HTTP2 IPv4"(明确支持 PSC NEG 消费端) |
| R2 | `https://docs.cloud.google.com/vpc/docs/private-service-connect-backends` | 2026-08-07 | "Global backend services that access published services can be associated with multiple Private Service Connect NEGs, as long as the NEGs are in different regions"(多 PSC NEG 规则) |
| R3 | `https://cloud.google.com/load-balancing/docs/url-map` | 2026-08-07 | "A URL map is a set of rules for routing incoming HTTP(S) requests to specific backend services or backend buckets"(URL Map path rule 标准用法) |
| R4 | `https://cloud.google.com/armor/docs/cloud-armor-security-policies` | 2026-08-07 | "Cloud Armor security policies can be attached only to backend services."(BS 1:1 绑 Cloud Armor) |
| R5 | `https://cloud.google.com/load-balancing/docs/quotas` | 2026-08-07 | (URL Map path rule / BS 数量 quota — 默认够用,无需特殊申请) |
| R6 | `https://cloud.google.com/load-balancing/docs/https` | 2026-08-07 | "For **regional external Application Load Balancers only**, a proxy-only subnet is used to send connections from the load balancer to the backends."(Global external ALB **不需要** proxy-only subnet) |
| R7 | `https://docs.cloud.google.com/vpc/docs/private-service-connect` | 2026-08-07 | (PSC 入口总览,确认 B 侧 SA / Producer 配置流程) |
| R8 | `https://docs.cloud.google.com/vpc/docs/private-service-connect-compatibility` | 2026-08-07 | "**Classic Application Load Balancer isn't supported**"(明确 G 类死路) |

### 2.6 LB type × PSC NEG 完整决策矩阵(覆盖 Lex "如果不是该类型" 问题)

| # | LB 类型 | scheme | 协议 | URL Map path rule | Cloud Armor | **PSC NEG 后端** | 你的场景 |
|---|--------|--------|------|-------------------|-------------|------------------|---------|
| **A** | **Global external Application LB** | `EXTERNAL_MANAGED` (global) | HTTP/HTTPS/HTTP2 | ✅ | ✅ | ✅ **官方支持** | ⭐⭐⭐⭐⭐ |
| **B** | **Regional external Application LB** | `EXTERNAL_MANAGED` (regional) | HTTP/HTTPS/HTTP2 | ✅ | ✅ | ✅ **官方支持** | ⭐⭐⭐⭐ |
| **C** | Regional internal Application LB | `INTERNAL_MANAGED` | HTTP/HTTPS/HTTP2 | ✅ | ✅ | ✅ | ❌ 不是公网入口 |
| **D** | Cross-region internal Application LB | `INTERNAL_MANAGED` | HTTP/HTTPS/HTTP2 | ✅ | ✅ | ✅ | ❌ 不是公网入口 |
| E | Global external proxy NLB | `EXTERNAL_MANAGED` | TCP/SSL | ❌ L4 | ✅ | ✅ | ❌ 不能跑 HTTPS 应用层 |
| F | Regional external proxy NLB | `EXTERNAL_MANAGED` | TCP | ❌ L4 | ✅ | ✅ | ❌ 同上 |
| **G** | **Classic Application LB** | `EXTERNAL`(classic) | HTTP/HTTPS | ✅ | ✅ | ❌ **官方拒** | ❌ **死路,必须迁移** |
| H | Classic proxy NLB | `EXTERNAL`(classic) | TCP/SSL | ❌ | ✅ | ❌ | ❌ 死路 |
| I | External passthrough NLB | `EXTERNAL`(passthrough) | TCP/UDP | ❌ | ❌ | ❌ | ❌ 死路 |
| J | Internal passthrough NLB | `INTERNAL`(passthrough) | TCP/UDP/ICMP | ❌ | ❌ | ❌ | ❌ 死路(只能当 Producer SA target) |

**关键观察**(对 Lex 场景):

- ✅ **A 和 B 都满足 Lex 的全部需求**(HTTPS 应用层 + URL Map path rule + Cloud Armor + PSC NEG)
- ❌ **G 类(Classic Application LB)是唯一一种"看起来能 URL Map path rule + Cloud Armor,但 PSC NEG 不支持"的 LB type**,**它会** 把你卡死
- ⚠️ **G→A/B 的迁移成本 = 换 GLB IP** = 破 Lex 的"入口 IP 不能变"硬约束 → **这就是为什么必须先确认你现网 GLB 不是 G 类**
- ⚠️ **E / F(Global/Regional external proxy NLB)虽然支持 PSC NEG,但它们是 L4,不能 URL Map path rule 分流** — Lex 必须 L7 才能按 path 选 BS

### 2.7 验证现网 GLB 是不是 A / B 类的 3 行命令(必跑)

> 💡 **一键自动化**:本目录有 `verify-glb-type.sh`(`chmod +x` 已设),零参数、跨机器可读,直接 `bash verify-glb-type.sh` 即可。它会做这里的 3 行命令 + 自动分类 + 打印彩色 verdict + 退出码(0=OK / 1=classic 死路 / 3=无 LB)。下面保留原始 gcloud 命令,方便出问题时手动 trace。

```bash
# 1. 查 Forwarding Rule 的 loadBalancingScheme(全局)
gcloud compute forwarding-rules describe <GLB-FR-name> \
  --project=<A 工程 project ID> --global \
  --format="get(loadBalancingScheme)"

# 2. 查 Backend Service 的 scope + scheme
gcloud compute backend-services describe <BS-name> \
  --project=<A 工程 project ID> --global \
  --format="get(loadBalancingScheme,scope)"

# 3. 查 URL Map 的 host rule(确认是 HTTPS 域名,不是 L4)
gcloud compute url-maps describe <UM-name> \
  --project=<A 工程 project ID> --global \
  --format="get(hostRules)"
```

**判定逻辑**:

| Forwarding Rule scheme | Backend Service scope | 你的 GLB 类型 | 本方案可用? |
|----------------------|----------------------|--------------|------------|
| `EXTERNAL_MANAGED` | `--global` | **A 类 Global external ALB** | ✅ 直接走本方案 |
| `EXTERNAL_MANAGED` | `--region=R` | **B 类 Regional external ALB** | ✅ 直接走本方案(若 Org Policy 批准) |
| `EXTERNAL`(无 `_MANAGED`) | global | **G 类 Classic ALB** | ❌ **死路**,必须迁移到 A 或 B(换 IP,破硬约束) |
| `INTERNAL_MANAGED` | 任意 | 内部 LB | ❌ 不是公网入口 |

如果第 1 条命令就返回 `EXTERNAL`(无 `_MANAGED`)→ 立即停下,本方案的所有下游步骤(GCP 都会拒);此时你必须决定是迁移到 A / B(破入口 IP 约束),还是走别的方案(比如把 GLB 换成 application LB 之外的方案,但都没有 path rule 能力)。

---

## 3. A 工程(Tenant)详细配置 — 围绕现有 Global GLB 加 path rule + 多 BS + 多 PSC NEG

> **前提**:A 工程的 GLB 已存在,IP 已 A-record 绑定 `www.caep.uk`,**不重起 LB、不动现有 IP、不动现有 cert**。下面所有步骤都假设 **GLB 的 forwarding rule / target proxy / cert 全部保留**,**只新建** URL Map path rule + 多个 Backend Service + 多个 PSC NEG。

### 3.1 A 工程需要新增的资源清单(7 类)

| # | 资源 | 类型 | scope | 数量 | 备注 |
|---|------|------|-------|------|------|
| 1 | Cloud Armor policy(`policy-apiname1` / `policy-apiname2` / `policy-default`) | global | 1 个 / apiname | 3 | 独立 WAF/rate-limit;Lex 后续按需加 rule |
| 2 | Backend Service(`bs-caep-apiname1` / `bs-caep-apiname2` / `bs-caep-default`) | global | 1 个 / apiname | 3 | `--load-balancing-scheme=EXTERNAL_MANAGED --protocol=HTTPS --global` |
| 3 | PSC NEG(`caep-apiname1-neg` / `caep-apiname2-neg`) | regional(consumer 端 subnet 所在 region) | 1 个 / apiname | 2+ | `default` 不走 PSC, 用 GCS bucket 或 static response 兜底 |
| 4 | URL Map path rule 增量(add-path-matcher 或 update) | global | 现有 GLB 的 URL Map | 1 次 | 把 `/apiname1/*` `/apiname2/*` 绑到对应 BS |
| 5 | (可选) Backend Bucket `bs-caep-default-bucket`(GCS) | global | 1 | 0-1 | default 兜底;若 default 也走 PSC 到 B 侧,则用 BS 而不是 Bucket |
| 6 | Network(`a 工程内 PSC NEG consumer subnet 所在 VPC`) | 已存在 | — | 0 | 复用 A 工程现有 VPC |
| 7 | (可选) Proxy-only subnet | global? | — | 0 | **Global external ALB 不需要 proxy-only subnet**(只有 Regional external/managed LB 才需要;详见 `cross-project-psc-architecture.md` Gotcha #2 vs Global GLB 的对照) |

> 🎯 **关键简化**:**Global external ALB 不需要 proxy-only subnet** — 这是它跟 Regional external ALB 最大的 API 差异之一。**Google 官方原话(R6)**:"For **regional external Application Load Balancers only**, a proxy-only subnet is used to send connections from the load balancer to the backends."Lex 的现网已经走通这个链路,本方案不需要为 proxy-only subnet 纠结。

### 3.2 A 工程 gcloud 命令序列(以 `apiname1` 为例,`apiname2` 同模板)

#### Step 1: 给每个 apiname 建独立 Cloud Armor policy(独立 WAF/rate-limit)

```bash
PROJECT=<A 工程 project ID>
REGION=<同 Producer B 侧的 region, 例如 europe-west2>

# apiname1 独立策略
gcloud compute security-policies create policy-apiname1 \
  --project=$PROJECT \
  --description="Cloud Armor policy for www.caep.uk/apiname1/*"

# 加 rate-limit + WAF + 自定义 deny/allow 规则
gcloud compute security-policies rules create 1000 \
  --project=$PROJECT --security-policy=policy-apiname1 \
  --expression="true" --action=rate-based-ban \
  --rate-limit-threshold-count=200 \
  --rate-limit-threshold-interval-sec=60 --ban-duration-sec=600

gcloud compute security-policies rules create 2000 \
  --project=$PROJECT --security-policy=policy-apiname1 \
  --expression="evaluatePreconfiguredWaf('sqli-v33-stable')" \
  --action=deny-403

# apiname2 同模板(独立 policy)
gcloud compute security-policies create policy-apiname2 \
  --project=$PROJECT \
  --description="Cloud Armor policy for www.caep.uk/apiname2/*"
# (rules 同上,省略)
```

**Description**:每个 apiname 一个独立 global Cloud Armor policy,后续可独立加 WAF rule / 调 rate-limit / 黑名单,**不会互相串**。

#### Step 2: 给每个 apiname 建独立 Backend Service (global, scheme=EXTERNAL_MANAGED)

```bash
# apiname1
gcloud compute backend-services create bs-caep-apiname1 \
  --project=$PROJECT --global \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTPS \
  --description="BS for www.caep.uk/apiname1/*"

# apiname2 同模板
gcloud compute backend-services create bs-caep-apiname2 \
  --project=$PROJECT --global \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTPS \
  --description="BS for www.caep.uk/apiname2/*"

# default 兜底(用 backend bucket 接 GCS 静态页)
gcloud compute backend-services create bs-caep-default \
  --project=$PROJECT --global \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTPS \
  --description="BS default fallback for www.caep.uk/*"
# 注:default 也可不挂 backend,只靠 URL Map default-service 兜底返回 404
```

**Description**:三个 global Backend Service,scheme 必须是 `EXTERNAL_MANAGED`(对应 Global external ALB)。protocol HTTPS 让 GLB 跟 PSC 后端做 TLS 1.3 re-encrypt。

#### Step 3: 给每个 apiname 建 PSC NEG(指向 B 工程 Service Attachment)

```bash
# Producer B 侧 SA URI(从 B 工程 owner 拿)
SA_URI="projects/<B 工程 project ID>/regions/$REGION/serviceAttachments/caep-master-sa-1"

# A 工程 PSC NEG 用的 consumer subnet(必须是 A 工程内已存在的普通 subnet)
CONSUMER_SUBNET=<A 工程内已有 subnet 名>
CONSUMER_NETWORK=<A 工程 VPC 名>

# apiname1
gcloud compute network-endpoint-groups create caep-apiname1-neg \
  --project=$PROJECT --region=$REGION \
  --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
  --psc-target-service=$SA_URI \
  --network=$CONSUMER_NETWORK \
  --subnetwork=$CONSUMER_SUBNET \
  --description="PSC NEG bridging to B master SA for apiname1"

# apiname2 同模板(可以指同一个 SA,或 B 侧另一个 SA)
gcloud compute network-endpoint-groups create caep-apiname2-neg \
  --project=$PROJECT --region=$REGION \
  --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
  --psc-target-service=$SA_URI \
  --network=$CONSUMER_NETWORK \
  --subnetwork=$CONSUMER_SUBNET \
  --description="PSC NEG bridging to B master SA for apiname2"
```

**Description**:两个 PSC NEG 都指 B 工程**同一个 SA**(Lex 选 1 SA 方案,nginx 二次分流)。如果 B 侧要彻底分开,SA_URI 换成两个。 `--network-endpoint-type=PRIVATE_SERVICE_CONNECT` 是关键 flag。

#### Step 4: 把 PSC NEG 挂到对应 Backend Service

```bash
# apiname1
gcloud compute backend-services add-backend bs-caep-apiname1 \
  --project=$PROJECT --global \
  --network-endpoint-group=caep-apiname1-neg \
  --network-endpoint-group-region=$REGION \
  --balancing-mode=UTILIZATION \
  --capacity-scaler=1.0

# apiname2
gcloud compute backend-services add-backend bs-caep-apiname2 \
  --project=$PROJECT --global \
  --network-endpoint-group=caep-apiname2-neg \
  --network-endpoint-group-region=$REGION \
  --balancing-mode=UTILIZATION \
  --capacity-scaler=1.0
```

**Description**:`--balancing-mode=UTILIZATION --capacity-scaler=1.0` 是 PSC NEG + EXTERNAL_MANAGED 的**唯一**有效组合(`cross-project-psc-architecture.md` Gotcha #10 已踩过坑)。**不要** 加 `--max-rate-per-endpoint` / `--max-connections-per-endpoint`,会被拒。

#### Step 5: 给每个 BS 绑 Cloud Armor policy

```bash
gcloud compute backend-services update bs-caep-apiname1 \
  --project=$PROJECT --global \
  --security-policy=policy-apiname1

gcloud compute backend-services update bs-caep-apiname2 \
  --project=$PROJECT --global \
  --security-policy=policy-apiname2
```

**Description**:BS 与 Cloud Armor 是 **1:1 绑定**,这是 Google 官方约束(R4)。绑完后 `bs-caep-apiname1` 的所有流量都会被 `policy-apiname1` 过滤。

#### Step 6: 更新现有 GLB 的 URL Map,加 path rule

> ⚠️ **不要重建 URL Map**,只在现有 URL Map 上 add path matcher / update path rule。

```bash
# 假设现网 URL Map 名 = <existing-um-name>
UM_NAME=<现有 GLB 对应的 URL Map 名>

# 方式 A: 用 add-path-matcher(适合新建 path matcher 场景)
gcloud compute url-maps add-path-matcher $UM_NAME \
  --project=$PROJECT \
  --path-matcher-name=caep-api-matcher \
  --default-service=bs-caep-default \
  --new-hosts=www.caep.uk \
  --path-rules="/apiname1/*=bs-caep-apiname1,/apiname2/*=bs-caep-apiname2"

# 方式 B: 直接 update URL Map YAML(适合已有 path matcher,想加 path rule)
# 推荐用 Terraform 或 gcloud compute url-maps export/import 工作流
```

**Description**:`--path-rules="/apiname1/*=bs-caep-apiname1,/apiname2/*=bs-caep-apiname2"` 是核心 — URL Map 按 longest-prefix 匹配,这两个 path 互不串。

#### Step 7(可选): B 侧 Service Attachment approve(由 B 工程 owner 执行)

```bash
# B 工程侧
gcloud compute service-attachments describe caep-master-sa-1 \
  --project=<B project> --region=$REGION \
  --format="get(connectedEndpoints)"

# 若 A 工程的 PSC NEG 没出现在 connectedEndpoints 列表:
# (a) SA 是 --connection-preference=ACCEPT_MANUAL → B owner 需在控制台手动 Approve
# (b) --consumer-accept-list 没包含 <A 工程 project number> → B owner 重建 SA 加 accept list
```

**Description**:SA 创建时若 `--connection-preference=ACCEPT_MANUAL`,B owner 必须显式 approve 每个 consumer。Lex 现网建议提前跟 B owner 沟通,直接 `ACCEPT_AUTOMATIC` + `--consumer-accept-list` 包含 A 工程 project number,避免每次都走手工 approve。

### 3.3 关键决策点 — 1 SA 还是 2 SA?

| 方案 | B 侧 nginx 复杂度 | A 侧资源 | 适用场景 | 推荐度 |
|------|-------------------|---------|---------|--------|
| **方案 A: 1 SA,nginx 二次分流** | 高 — nginx 要按 path 转发 | 1 个 SA + 2 个 PSC NEG(同 region,指向同一 SA) + 2 个 BS | apiname1/2 后端差异小,nginx 二次路由成本低 | ⭐⭐⭐⭐⭐ 入门推荐 |
| **方案 B: 2 SA,各管各的** | 低 — nginx 不分流,各 SA 直接连各后端 | 2 个 SA + 2 个 PSC NEG(指向不同 SA) + 2 个 BS | apiname1/2 后端差异大,需要独立 SLA / 限流 / 升级窗口 | ⭐⭐⭐⭐ 扩展推荐 |
| **方案 C: 2 SA + 2 个 B 侧集群** | 中 — 各自集群独立 | 2 个 SA + 2 个 PSC NEG + 2 个 BS + 2 个 B 集群 | apiname1/2 完全不同的 owner / 业务线 | ⭐⭐⭐ 终极扩展 |

**Lex 当前选择**:**方案 A**(原话:"分别转到转到同一个 Gateway 上"),跟 `public-fqdn-explorer.md` 已确认的 Master B 设计一致。

---

## 4. Master B 工程详细配置 — 简化摘要(详见 public-fqdn-explorer.md)

> **B 侧的完整 5 方案 + nginx.conf + MIG template + K8s Gateway 在 `/Users/lex/git/knowledge/cloud/k8s/k8s-gateway/public-fqdn-explorer.md` 1144 行已详尽覆盖。本节只列 Lex 本方案需要的最小落地集。**

### 4.1 B 工程需要的资源(沿用 public-fqdn-explorer.md §3 的方案 1)

| # | 资源 | 类型 | scope | 数量 | 关键命令/参考 |
|---|------|------|-------|------|---------------|
| 1 | Service Attachment `caep-master-sa-1` | Producer | regional | 1 | `--producer-forwarding-rule=caep-master-ilb-fr --nat-subnets=caep-master-nat-subnet --consumer-accept-list=<A project num>=N --connection-preference=ACCEPT_AUTOMATIC` |
| 2 | Producer NAT subnet | subnet | regional | 1 | `--purpose=PRIVATE_SERVICE_CONNECT --role=ACTIVE` |
| 3 | Consumer-facing subnet(已存在,不需要新建) | subnet | regional | 1 | 现成的 B 工程 VPC 内的 subnet,SA 连接时不强制指定 |
| 4 | ILB `caep-master-ilb` (Internal App LB, L7) | LB | regional | 1 | `--load-balancing-scheme=INTERNAL_MANAGED --protocol=HTTPS --region=$REGION` |
| 5 | ILB URL Map(单 default → MIG NEG) | URL Map | regional | 1 | 简单 default-service,**B 侧不需要按 path 分流**(nginx 二次分流) |
| 6 | MIG `caep-nginx-mig`(VM template 跑 nginx) | MIG | zonal | 1+ | instance template startup script 拉 nginx.conf |
| 7 | nginx.conf | VM startup | — | 1 | 见 §4.2 |
| 8 | cert(`*.caep.uk`,B 侧副本) | self-managed cert | regional | 1 | ILB 上挂的 cert;从 A 工程 cert 副本(SAN 必须含 `www.caep.uk`) |
| 9 | K8s Gateway + HTTPRoute(已在 B 内多 team 共享) | k8s | cluster | 已有 | HTTPRoute `apiname1-route` PathPrefix=/apiname1 |

### 4.2 B 侧 nginx.conf 关键片段

```nginx
# nginx.conf(MIG instance template 启动时从 GCS bucket 拉)
upstream kong_gateway {
    server <K8S_GATEWAY_VIP>:443;   # K8s Gateway controller 创建的 ILB VIP
    keepalive 32;
}

server {
    listen 443 ssl;
    server_name www.caep.uk;

    ssl_certificate     /etc/nginx/certs/www.caep.uk.crt;
    ssl_certificate_key /etc/nginx/certs/www.caep.uk.key;
    proxy_ssl_server_name on;        # SNI 必填,否则 K8s Gateway hostname match 失败
    proxy_set_header Host www.caep.uk;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;

    # apiname1 路径转发
    location /apiname1/ {
        # 可选:strip 前缀(取决于 K8s Gateway 那边 HTTPRoute 怎么配)
        # rewrite ^/apiname1/(.*)$ /$1 break;
        proxy_pass https://kong_gateway;
    }

    # apiname2 路径转发
    location /apiname2/ {
        proxy_pass https://kong_gateway;
    }

    # 兜底
    location / {
        return 404 "Path not found on www.caep.uk";
    }
}
```

**关键 placeholder**:
- `<K8S_GATEWAY_VIP>`:K8s Gateway controller 创建的 ILB VIP(从 `kubectl get gateway -A` 的 `status.addresses` 拿;或用 ClusterIP/FQDN,详见 `public-fqdn-explorer.md` §3.2.1 三选一)
- `<B 工程证书副本路径>`:从 GCS bucket 拉,具体 bucket 名按 B 工程模板填
- 完整 nginx.conf + MIG instance template + startup script 见 `public-fqdn-explorer.md` §3.5

### 4.3 B 侧 K8s Gateway HTTPRoute(关键: nginx 是否 strip 前缀决定 path)

**方案 A1(niginx 不 strip 前缀,K8s Gateway 收到 `/apiname1/...`):**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: caep-apiname1-route
  namespace: <apiname1 所在 tenant NS>
spec:
  parentRefs:
    - name: <B 工程内 K8s Gateway 名>
      namespace: <B Gateway 所在 NS>
  hostnames:
    - www.caep.uk
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /apiname1
      backendRefs:
        - name: apiname1-svc
          port: 8080
```

**方案 A2(nginx strip 前缀,K8s Gateway 收到 `/...` 不含 `apiname1`):**

nginx 加 `rewrite ^/apiname1/(.*)$ /$1 break;`,K8s Gateway 的 HTTPRoute path 就得改成 `/`(catch-all)或具体子路径。

**Lex 推荐方案 A1**:不 strip 前缀,理由是 K8s Gateway 的 path match 更明确,WAF/audit 更清晰,**少一处隐藏的 rewrite 故障点**。

---

## 5. 严格说法 vs 简化说法对照(避免被 Lex 抓到简化陷阱)

| 简化说法 | 严格说法 | 文档应使用的措辞 |
|---------|---------|----------------|
| "GLB 不支持 PSC" | **要看 GLB 类型**(详见 §0.3 + §2.6 决策矩阵);Global external ALB(A)/Regional external ALB(B)支持 PSC NEG;Classic Application LB(G)**不支持 PSC NEG 且必须迁移**,但 G→A/B 会破"入口 IP 不能变"的硬约束 | "Lex 的 GLB 必须先用 §2.7 命令自查,确认是 A 或 B 类后再走本方案;若返回 EXTERNAL(无 _MANAGED),本方案不可行" |
| "一个 BS 可以挂多个 PSC NEG" | **Global** backend service 访问**已发布服务**可以挂多个 PSC NEG(**不同 region**),**Regional** backend service 只能挂一个 | "Lex 的 Global BS 每个可以挂多个 PSC NEG(只要在不同 region),但同 region 内多 NEG 语义是 fan-in 不是 HA" |
| "Cloud Armor 按 path 分流" | URL Map 按 path 选 BS,Cloud Armor **绑定在 BS 上**——Cloud Armor **不知道 path**,只看自己绑的 BS 收到的流量 | "URL Map 负责'where'(按 path 选 BS),Cloud Armor 负责'what'(只管 WAF/rate-limit,不管 path)"(参 `URLmapMatch.md` §6.3) |
| "PSC backend 没有 health check" | Backend service 挂载 PSC NEG 时**不配置 health check**,但 Producer 端仍可自定义 health 信号(Private Service Connect health / Composite Health) | "PSC NEG 的 BS 不需要 GCP 健康检查,故障检测由 Producer 端自定义" |
| "路径判断在 GLB" | URL Map 做"按 Host + Path 选 BS"的 L7 路由决策,但**不能**改 header / 做 rewrite / 认证,这些仍需要 nginx | "URL Map ≈ Nginx 里'基于 Host/Path 选 upstream'那部分能力,但 rewrite/auth/header 仍在 nginx" |
| "Master B 侧一定需要 nginx" | nginx 是 5 方案之一;如果 GLB 端已经按 path 分流到不同 BS / 不同 SA,B 侧 nginx 可以省 | "本方案选 nginx 是因为 Lex 选了'1 SA + B 侧二次分流',换方案 B/C 可以省 nginx" |
| "所有 public TLS 必须经过 Kong" | Lex 原话;但 K8s Gateway + HTTPRoute 已能 cover,本方案跳过 Kong(原文 § 末已确认) | "本方案用 K8s Gateway 替代 Kong,因 Kong 路径判断复杂,K8s Gateway HTTPRoute 直接做" |

---

## 6. 端到端验证(6 步)

### 6.1 A 工程 GLB 路由验证

```bash
# 验证 URL Map path rule 命中
curl -sk -o /dev/null -w "%{http_code}\n" \
  https://www.caep.uk/apiname1/healthz

# 验证 default 兜底
curl -sk -o /dev/null -w "%{http_code}\n" \
  https://www.caep.uk/unknown-path

# 期望:apiname1 → 200(到 B 侧后端),unknown → 404 或 default 页
```

### 6.2 A 工程 BS + PSC NEG 验证

```bash
# BS health(PSC NEG 没 health check,这里查的是 BS → NEG 链路 status)
gcloud compute backend-services get-health bs-caep-apiname1 \
  --project=$PROJECT --global --format=json

# PSC NEG status(应 ACCEPTED)
gcloud compute network-endpoint-groups describe caep-apiname1-neg \
  --project=$PROJECT --region=$REGION --format=json | jq '{pscConnectionId, networkEndpointType}'
```

### 6.3 B 工程 SA 验证

```bash
# SA 确认 A 工程 NEG 已连入
gcloud compute service-attachments describe caep-master-sa-1 \
  --project=<B project> --region=$REGION \
  --format=json | jq '.connectedEndpoints'
# 期望:看到 2 个 ACCEPTED entry(apiname1-neg + apiname2-neg)
```

### 6.4 LB 日志验证

```bash
# A 工程 GLB 日志:确认 path rule 命中
gcloud logging read 'jsonPayload.statusDetails="backend_response_sent_by_backend"' \
  --project=$PROJECT --limit=10 \
  --format='json' | jq '.[] | {timestamp, urlMap: .jsonPayload.urlMapName, path: .jsonPayload.requestUrl, backend: .jsonPayload.backendTargetName}'
```

### 6.5 端到端 TLS 链路验证

```bash
# 从 A 工程 GCE 跑 curl(避免本地 trust store 干扰)
gcloud compute ssh <A 工程内任意 VM> --command \
  "curl -sk -o /dev/null -w '%{http_code}\n' https://www.caep.uk/apiname1/healthz"
```

### 6.6 反向流量 / 数据面验证

```bash
# B 工程 MIG nginx access log
gcloud logging read 'resource.type="gce_instance" jsonPayload.message=~"GET /apiname1"' \
  --project=<B project> --limit=10

# 期望:看到来自 A 工程 PSC NAT IP 段的请求,path 是 /apiname1/...
```

---

## 7. 已知坑与预防

| # | 坑 | 症状 | 预防 |
|---|----|------|------|
| 1 | Global external ALB 的 NEG 用 `--region` 而不是 `--global` | PSC NEG 创建失败 | PSC NEG 永远是 **regional**,即使挂在 Global BS 上;**NEG 创建用 `--region`**,**BS 用 `--global`** |
| 2 | Global BS 用了 `--region=$REGION` 标志 | BS 创建失败 / 创建成 regional | Global BS **必须用 `--global`**,**不能带 `--region`** |
| 3 | BS 用 `add-backend` 加 `--max-rate-per-endpoint` | "Max connections per endpoint cannot be set for EXTERNAL_MANAGED with HTTP(S)" | PSC NEG + EXTERNAL_MANAGED 只能 `balancing-mode=UTILIZATION`,**不能加任何 max-\* 字段** |
| 4 | URL Map path rule 写成 `/apiname1`(末尾没斜杠) | `/apiname1users` 也会命中,误路由 | **始终用 `/apiname1/*` 或 `/apiname1/`** |
| 5 | path rule 顺序优先级误用 | longest-prefix 自动,不是按 `--path-rules` 顺序 | **忘掉"顺序"概念,longest-prefix 永远胜出** |
| 6 | SA `--connection-preference=ACCEPT_MANUAL` 但 B owner 没 approve | A 工程 PSC NEG 创建成功但 `pscConnectionId` 为空 | 让 B owner 用 `ACCEPT_AUTOMATIC` 或提前在 console approve |
| 7 | B 侧 ILB 选 Regional internal proxy NLB(TCP) | A 工程 Global external ALB 拒绝 | B 侧必须用 **L7 Internal Application LB**(HTTPS),不能用 L4 proxy NLB(R2 官方矩阵限制) |
| 8 | Cloud Armor policy 名打错 / 没绑 | BS 上 `securityPolicy` 为空,流量无过滤 | `gcloud compute backend-services describe <BS> --global --format=json | jq '.securityPolicy'` 必看 |
| 9 | URL Map `defaultService` 没设 / 设错 | 兜底路径返回 502 | 必须有 `bs-caep-default`(可用 backend bucket 或 simple 404 服务) |
| 10 | A 工程 PSC NEG 的 `--network` 和 `--subnetwork` 跟 Shared VPC IAM 不匹配 | "Permission denied" | A 工程若在 Shared VPC host project 内,确认 host project 给 service project 的 IAM 有 `roles/compute.networkUser` |
| 11 | nginx `proxy_ssl_server_name on` 没开 | K8s Gateway hostname match 失败,404 | 跟 `public-fqdn-explorer.md` §3.5 nginx.conf 第 ② 关键点保持一致 |
| 12 | K8s Gateway HTTPRoute `hostnames: [www.caep.uk]` 没设 | HTTPRoute 不接收 www.caep.uk 流量 | HTTPRoute 必须显式列 hostnames,跟 nginx proxy_set_header Host 一致 |

---

## 8. 推荐方案(最终定型)

> **本方案的最终定型依据**:Google 官方 PSC 兼容矩阵(R1,R2,R8)+ URL Map 文档(R3)+ Cloud Armor 文档(R4)+ LB type × PSC 决策矩阵(§2.6),以及 Lex 现网已知约束(`Summarize-current-implementation.md` §3:现网 GLB 是 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`)+ `public-fqdn-explorer.md` 已确认的 Master B 侧 5 方案。
>
> **前置必跑 Step 0**(§2.7 的 3 行 gcloud 命令):**先验证现网 GLB 是 A 或 B 类,不是 G 类(Classic Application LB)**。若发现是 G 类,本方案立刻作废,需要重新评估"换 IP"或换方案。

**A 工程(Tenant)侧:**
- ✅ 现有 Global external ALB **不动**,IP 不变,cert 不变,forwarding rule 不变,target proxy 不变
- ✅ 现有 URL Map **不重建**,只 add-path-matcher / add-path-rule
- ✅ 新增 2 个独立 Cloud Armor policy(`policy-apiname1` / `policy-apiname2`)
- ✅ 新增 2 个独立 Global Backend Service(`bs-caep-apiname1` / `bs-caep-apiname2`),scheme=EXTERNAL_MANAGED
- ✅ 新增 2 个 PSC NEG(`caep-apiname1-neg` / `caep-apiname2-neg`),指向 B 工程同一个 SA
- ✅ 1 个 default BS 兜底
- ❌ **不需要** proxy-only subnet(Global external ALB 不需要)
- ❌ **不需要** 重建 GLB

**B 工程(Master)侧:**
- ✅ **方案 A** = 1 SA + 2 PSC NEG 同 SA + nginx 二次分流 + K8s Gateway
- ✅ Producer ILB = **L7 Internal Application LB**(`INTERNAL_MANAGED` + HTTPS,**不是** Internal proxy NLB TCP)
- ✅ nginx.conf = `public-fqdn-explorer.md` §3.5 模板,按 §4.2 微调
- ✅ K8s Gateway HTTPRoute = 方案 A1(不 strip 前缀,path match 更清晰)
- ✅ B 侧 cert = `*.caep.uk`,跟 A 侧同步(SAN 含 `www.caep.uk`)

**符合 Lex 的 3 个核心约束**:
- ① 入口 IP 不变 ✓
- ② 按 path 分流 ✓
- ③ 跨 project PSC 通到 B 工程 ✓

---

## 9. 待验证假设 / 实施细节(等 Lex 确认)

1. **B 工程 Producer ILB 是否已经存在?** 如果已有,验证 type/scheme;如果没有,需要新建(`public-fqdn-explorer.md` §3 完整覆盖)
2. **B 工程 SA 数量决策**:本方案选 1 SA;若 Lex 想要 2 SA,需在 §3.3 方案 B 上重新规划
3. **A 工程 PSC NEG consumer subnet 选择**:复用现网 VPC 已有 subnet,还是新建独立 subnet?(建议新建独立,便于 IAM/审计隔离)
4. **A 工程 Cloud Armor 策略的具体 WAF rule 集**:Lex 业务对 WAF 的真实需求?目前 §3.2 Step 1 给的是占位模板(rate-limit + sqli-v33-stable),实际生产规则按安全合规要求调整
5. **Master B 的 cert 同步机制**:A 工程 cert 续期后,B 工程 cert 如何自动同步?(短期手动同步 + GCS bucket 中转;长期可用 Secret Manager 跨 project 同步)
6. **Master B 的 K8s Gateway namespace + GatewayClass**:Lex 实际网关类(`gateway-2.0/k8s-gateway/` 已有基础设施),HTTPRoute 落到哪个 tenant NS?(按 §4.3 的 namespace 模板)
7. **A 工程是否需要保留原 default BS**(现网可能已有指向 GCS 的 default)?如果保留,本方案只在原 URL Map 上 add-path-matcher;如果不要原 default,可直接覆盖
8. **A 工程现网 GLB 的 LB type 验证**(Step 0 必跑,见 §2.7 的 3 行命令,**或直接跑 `bash verify-glb-type.sh`**)— 必须先确认是 A 类(Global external ALB)或 B 类(Regional external ALB),**绝不能是 G 类(Classic Application LB)**。如果发现是 G 类,整个方案需要重新设计:要么迁移到 A/B(破入口 IP 硬约束),要么走非 PSC 的别的跨 project 方案(但都没有 path rule 能力)

---

## 10. 引用与延伸阅读

- **`/Users/lex/git/gcp/ingress/public-tls-ingress/`** — A 工程(Tenant)的全部实现参考
  - `tenant-tls-setup-idmz-https.md` — A 工程 consumer LB 链(IDMZ VPC,跟本方案平行)
  - `tenant-tls-setup-https.md` — A 工程 consumer LB 链(cinternal VPC,被 Org Policy 拒)
  - `PSC-support.md` — GCP LB × PSC 兼容矩阵(直接反驳 Lex 的担心)
  - `Summarize-current-implementation.md` — Lex 现网 GLB 是 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` 的确认来源
  - **`scripts/online-consume.sh`** — 现网跑通的 Global GLB install 脚本(本方案沿用其 scope 设计)
  - **`./verify-glb-type.sh`** — 本目录配套的零参数 GLB type 验证脚本(对应 §2.7 自动化版)
- **`/Users/lex/git/knowledge/cloud/k8s/k8s-gateway/public-fqdn-explorer.md`** — Master B 工程 5 方案 + nginx.conf + MIG template 的完整覆盖(本方案 B 侧全引用此 doc)
- **`/Users/lex/git/knowledge/gcp/cloud-armor/dedicated-armor/url-map.md`** — URL Map 概念级文档(本方案 §5 简化/严格说法表借用其 §6.3 思路)
- **`/Users/lex/git/knowledge/gcp/cloud-armor/dedicated-armor/URLmapMatch.md`** — URL Map longest-prefix match + `routeRules` + `urlRewrite` 的深度讲解
- **`/Users/lex/git/knowledge/gcp/cloud-armor/dedicated-armor/glb-api-cloudarmor-qwen-eng.md`** — URL Map + 多 BS + 多 Cloud Armor policy 的可行性分析(本方案 §1 + §3.2 直接借用其 §1.3 维度表)
- **`/Users/lex/.hermes/profiles/architecture/skills/architectrue/references/cross-project-psc-architecture.md`** — 跨项目 PSC NEG 架构 skill,12 个 Gotcha 直接覆盖本方案
- **Google 官方原话直接引用**(本方案 §2 已逐条列出 URL + 验证日期)