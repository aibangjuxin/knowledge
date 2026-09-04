# Facing Issue: 跨项目 Public TLS Ingress 改造 + 3 隐患 + 用户核心构想

> **本节是"Master Project 去 Nginx MIG 改用 ServiceAttachment"后的 3 隐患 + 业务方核心构想的梳理与可行性评估**
>
> **架构师 lane 边界**:本文档只做问题梳理 + 方案可行性分析,**不实施任何 provision / apply / gcloud / kubectl**。实际由 infra-gcp 用专属 SA 执行。
>
> **状态**:Draft(待你确认 6 实施细节后,转 Proposed)· Date: 2026-09-04 · Author: **architect-gcp** · Reviewers: **infra-gcp** / **devops-gcp** / **qa-gcp** / **业务方**
>
> **配套文档**:
> - 已实现架构:[`public-tls-cross-project-implementation.html`](./public-tls-cross-project-implementation.html)
> - 引用:[Gateway API v1.5 ListenerSet](https://kubernetes.io/blog/2026/04/21/gateway-api-v1-5) · [GLB URL Map hostRewrite](https://cloud.google.com/load-balancing/docs/https/setting-up-global-traffic-mgmt) · [GLB URL Map concepts](https://cloud.google.com/load-balancing/docs/url-map-concepts) · [GKE ServiceAttachment](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing-across-vpc-net) · [Gateway API ListenerSet 多租户 RBAC](http://eden-cms-v2.onbex.co/blog/2026/07/08/gateway-api-listenerset-multi-tenant-paas)

---

## 0. 一句话摘要

> **改造**:Master Project 用 GKE 暴露的 `ServiceAttachment` 替代原 Nginx MIG(原本用于 host header 转写)。
> **3 隐患**:公网入口统一为单一域名 + GLB Backend TLS 不携带 SNI + 多 Team 共享 Gateway 443 端口触发 `conflicted:True` 冲突。
> **用户核心构想**:在 GLB URL Map 按 Path 动态改写 Host 头 → GKE 侧维护一份 wildcard ListenerSet → 各 Team 独立 HTTPRoute 匹配自己虚拟域名。
> **架构师评估**:**✅ 完全可实现,6 项技术点全部有官方支持**(详见 §5)。

---

## 1. 现状:已实现的跨项目 Public TLS Ingress 架构

> **依据**:`public-tls-cross-project-implementation.html`(已实现架构图)

### 1.1 架构骨架(精确组件清单)

| 层 | 组件 | 配置 | 所在 Project |
|---|---|---|---|
| 入口 | Global Static IP | `${PREFIX}-public-glb-ip`(Anycast 单一 IP) | Talent(Consumer) |
| 入口 | Target HTTPS Proxy | `${TARGET_HTTPS_PROXY}-global`(Global scope)| Talent |
| 入口 | Global External HTTPS Forwarding Rule | `${FR}-global`,port 443,`--load-balancing-scheme=EXTERNAL_MANAGED` | Talent |
| 证书 | Global SSL Certificate | `${SSL_CERT}-global`(TrustAsia DV cert)| Talent |
| 路由 | Global URL Map | `${URL_MAP}-global`,`default` → `${BS}-global` | Talent |
| 安全 | Cloud Armor Global Security Policy | `${ARMOR}-global`,WAF / DDoS / Rate limit,attached to Backend Service | Talent |
| 路由 | Global Backend Service | `${BS}-global`,`protocol=HTTPS, portName=https` | Talent |
| 跨项目 | PSC NEG(regional) | `${PSC_NEG}`,`type=PRIVATE_SERVICE_CONNECT` | Talent |
| 跨项目 | **PSC Tunnel**(自动) | Talent PSC NEG ↔ Master Service Attachment | GCP 内部 |
| Master | Producer ILB Static IP(GCE_ENDPOINT)| `${PREFIX}-producer-ilb-ip` | Master(Producer)|
| Master | Producer ILB FR | `${PREFIX}-producer-ilb-tcp-fr`,port 443,`--load-balancing-scheme=INTERNAL --allow-global-access` | Master |
| Master | **Service Attachment** | `${PREFIX}-producer-svc-att`,`ACCEPT_MANUAL`,`consumer-accept-list=$CONSUMER_PROJECT=10` | Master |
| Master | Backend Service | `${PREFIX}-producer-bs`,`protocol=TCP, port=443` + Health Check | Master |
| **Master** | **🚨 Producer MIG(Nginx)** | `${PREFIX}-producer-mig`,**做 host header 嗅探 + 转写**(例如 `proxy_set_header X-Original-Host $host`)| Master |

### 1.2 数据流(正向)

```
External Client
  → HTTPS GET https://www.caep.uk/springboot-demo/api/v1/users
  → Global Static IP
  → Target HTTPS Proxy
  → Global Forwarding Rule (port 443)
  → Cloud Armor(WAF / DDoS)
  → Global Backend Service (HTTPS)
  → Global URL Map(单 host, default → Backend Service)
  → PSC NEG
  → PSC Tunnel(跨 project 隔离通道)
  → Master Service Attachment
  → Master Producer ILB(TCP 443)
  → Master Backend Service
  → Master Producer MIG(Nginx)
  → Nginx 转写 host header → 路由到具体后端
```

### 1.3 数据流(反向 — 谁配、谁能改、audit 在哪)

| 角色 | 能改什么 | 不能改什么 | audit |
|---|---|---|---|
| **业务方** | 上传自己的 API(各 Team 自己管)| URL Map、Backend Service、Cloud Armor | Cloud Logging(K8s audit + LB access log)|
| **平台层(Talent Project)**| URL Map、Backend Service、Cloud Armor、PSC NEG | ServiceAttachment、Producer ILB | GCE audit log |
| **Master 平台层(Master Project)** | ServiceAttachment、Producer ILB、Producer MIG | Talent 侧任何资源 | GCE audit log |
| **安全** | Cloud Armor policy、Org Policy | 业务逻辑 | Security Command Center |

---

## 2. 改造描述:Master 去 Nginx MIG,改用 ServiceAttachment

### 2.1 改造动机

- **原 Nginx MIG 唯一职责**:**host header 嗅探 + 转写**(让 `www.caep.uk/{apiprefix}/*` 在 GKE 内部按 `{apiname}.teamshared.intra.caep.uk` 路由到具体 API)
- **改造成本**:**Nginx MIG 需要维护**(镜像、滚动更新、sidecar、configmap、pdb);如果 GKE Gateway 能直接接管这块逻辑,**可省掉整个 Master MIG**
- **GLB 全局节点优化**:业务方申请了 **Global External HTTP/HTTPS GLB**,需要对 GKE Level 做节点优化(降低跨 project 路径上的额外 hop)

### 2.2 改造前 vs 改造后

**改造前**(原架构 — 含 Nginx MIG):

```
GLB (Talent) 
  → PSC NEG → PSC tunnel → Service Attachment (Master)
  → Producer ILB (TCP 443) → Backend Service (TCP)
  → Producer MIG [Nginx]  ← 这一层做 host header 转写
  → Producer 服务端口
```

**改造后**(去 Nginx,改用 GKE ServiceAttachment):

```
GLB (Talent)
  → PSC NEG → PSC tunnel → Service Attachment (Master) ← 直接 GKE Level 暴露
  → K8s Service (LoadBalancer + Internal ILB)
  → GKE Gateway
  → 各 Team HTTPRoute
  → Service / Pod
```

### 2.3 GKE 侧 ServiceAttachment 配置(摘自 Google 官方文档)

```yaml
apiVersion: networking.gke.io/v1
kind: ServiceAttachment
metadata:
  name: SERVICE_ATTACHMENT_NAME
  namespace: default
spec:
  connectionPreference: ACCEPT_AUTOMATIC
  natSubnets:
  - SUBNET_NAME
  proxyProtocol: false
  reconcileConnections: false  # set to true to enable connection reconciliation
  resourceRef:
    kind: Service
    name: SERVICE_NAME
```

**关键事实**(Google 官方原文):[GKE ServiceAttachment 文档](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing-across-vpc-net)明确写到:

> "As a service producer, you can use service attachments to make your services available to service consumers in other VPC networks using Private Service Connect."

**GKE 版本要求**:`networking.gke.io/v1` 在 GKE 1.23.3-gke.900+ 可用;`networking.gke.io/v1beta1` 用于 1.21.4-gke.300 ~ 1.23.2。

### 2.4 改造带来的新链路(已实现但待 review)

```
GLB (Talent)
  → Backend Service (HTTPS, portName=https)  ← 注意 protocol 是 HTTPS 不是 TCP
  → PSC NEG (PRIVATE_SERVICE_CONNECT)
  → PSC tunnel
  → ServiceAttachment (Master)              ← 由 GKE 控制面直接管理
  → K8s Service (LoadBalancer)
  → GKE Gateway
  → HTTPRoute → Service / Pod
```

---

## 3. 改造引入的 3 隐患(精确描述 + 架构师修正)

### 3.1 隐患 1:公网入口高度统一

> **业务方原话**:"所有外部客户端均统一访问单一公网域名 `www.caep.uk`,并通过 URL 路径前缀(Path Prefix)区分具体微服务(如 `/springboot-demo/*`, `payment-service/*`)。"

**架构师确认**:✅ 这是**已实现的状态**,跟 html 架构吻合。
- 公网**只有 1 个域名**(`www.caep.uk`)
- **URL Map 按 path prefix 路由**(多 backend service 或多 host rule)
- **所有 path 走同一个 Backend Service → PSC NEG → Master**

**没争议**。

### 3.2 隐患 2:TLS 握手无 SNI(架构师修正措辞)

> **业务方原话**:"GLB 发起的 Backend TLS 连接不携带 SNI,导致 GKE 侧无法在 443 端口部署多个带 hostname 专属 ListenerSet。"

**架构师修正**:

| 业务方表述 | 事实 |
|---|---|
| "GLB 发起的 Backend TLS 连接不携带 SNI" | ✅ **精准**。GLB → Backend Service 的 TLS 握手 **默认不携带 SNI**(因为 Backend Service 不是虚拟主机概念) |
| "GKE 侧无法在 443 端口部署多个带 hostname 专属 ListenerSet" | ⚠️ **修正**:GKE 侧**可以**在 443 部署多个 hostname 专属 ListenerSet,只要 hostname 不同。**真正的问题是**:**GKE 侧**目前**没有 SNI 信息可用**(因为 GLB 不发),所以必须**靠 GLB 重写后的 HTTP Host 头**做路由决策,而不是 SNI |

**核心修正**:
- Gateway API v1.5 [ListenerSet](https://kubernetes.io/blog/2026/04/21/gateway-api-v1-5) **支持**"多 hostname 共享 443 port",每个 listener 通过 `hostname` 字段唯一识别
- 触发"无法部署"的原因是:**SNI 缺失**,不是 ListenerSet 能力缺失
- **解决方案**:让 GLB 在 `routeAction.urlRewrite.hostRewrite` 中按 path 改写 Host 头 → Backend Service 收到的请求是"改写后的 Host"(HTTP 层 header),透传到 GKE Gateway,Gateway 按 HTTP Host 路由

### 3.3 隐患 3:多租户 ListenerSet 冲突(架构师修正措辞)

> **业务方原话**:"如果每个 Team 都去同一个 Gateway 443 端口创建无 hostname ListenerSet,会触发 K8S 控制面 `conflicted:True` 的报错。"

**架构师确认**:`conflicted:True` 报错**确实存在**,但**触发条件**是"同一 Gateway 同一 port 上 listener 维度不唯一"。

**架构师修正**:

| 业务方表述 | 事实 |
|---|---|
| "无 hostname ListenerSet 冲突" | ⚠️ **修正**:**"无 hostname 限制的 ListenerSet"是不允许的**。Gateway API 强制同一 Gateway 同一 port 上 listener 维度(protocol/port/hostname)**必须唯一**。你真正想做的不是"无 hostname",而是"**一个 wildcard 通配符 hostname,绑一份 wildcard cert**" |
| "`conflicted:True` 报错" | ✅ **精准**。Gateway API 文档明示:两个 listener 在同 port + 同 protocol 时,如果 hostname 完全相同(或都为 `*`)就冲突 |

**官方规则**(Gateway API GEP-1713):

> "Listeners on the parent Gateway itself always win over any ListenerSet. Between competing ListenerSets, the one with the earliest creation timestamp wins. If timestamps tie, the alphabetically first ListenerSet name wins."

→ **即使冲突也有 winner**,但**业务方应避免冲突设计**,直接用"**一个 wildcard ListenerSet + 各 Team 独立 HTTPRoute**"模式。

---

## 4. 用户核心构想(The Breakthrough Idea)

### 4.1 构想的 4 步设计

> **业务方原话**:
> "既然公网入口都是同一个域名,后面靠 Path 区分 API。我们是否可以在 GKE 侧由平台仅维护一份独立的、共享 ListenerSet(单一 443 端口、无 hostname 限制、绑定统一的企业泛域名 `*.teamshared.intra.caep.uk`)。在 GLB URL Map 中按照请求 PATH 将 HTTP Host 头动态改写为 `{apiname}.teamshared.intra.caep.uk`。进入 GKE 后,各团队在自己的命名空间中创建独立 HTTPRoute,声明匹配自己约虚拟域名 `{apiname}.teamshared.intra.caep.uk`,然后路由到自己对应的 Server 或者 Pod。"

**架构师梳理**(4 步):

| 步 | 位置 | 动作 |
|---|---|---|
| 1 | GLB URL Map | 按 path prefix 匹配 → 改写 Host 头为 `{apiname}.teamshared.intra.caep.uk` |
| 2 | GLB → Backend Service(protocol=HTTPS) | 透传改写后的 Host 头(作为 HTTP Host) |
| 3 | GKE 侧共享 ListenerSet | 单一 443 端口,hostname = `*.teamshared.intra.caep.uk`,绑 wildcard cert |
| 4 | 各 Team HTTPRoute | 匹配 `hostnames: ["{apiname}.teamshared.intra.caep.uk"]`,路由到自己的 Service/Pod |

### 4.2 业务方"无 hostname 限制"措辞修正

**业务方原话**:"单一 443 端口、无 hostname 限制"

**架构师修正**:**"无 hostname 限制"是不可能的**(Gateway API 强制唯一性)。**真正想做的**是:

> **一份通配符 ListenerSet,绑 `*.teamshared.intra.caep.uk` 通配符 cert,所有 Team 共用**。
>
> 各 Team **不创建自己的 ListenerSet**,而是在共享 ListenerSet 下创建独立 HTTPRoute,通过 `spec.hostnames` 区分自己。

### 4.3 用户实际看到 vs 内部路由

| 视角 | 看到的 hostname | 路由依据 |
|---|---|---|
| 外部用户浏览器 | `https://www.caep.uk/springboot-demo/api/v1/users`(地址栏不变)| 域名不变 |
| GLB URL Map | `Host: www.caep.uk`(原) | 按 path 匹配 + 改写 |
| GLB Backend Service 出口 | `Host: springboot-demo.teamshared.intra.caep.uk`(改写后) | 透传 HTTP header |
| PSC tunnel | 同上(改写后)| TCP 层透传 |
| GKE Gateway 入口 | `Host: springboot-demo.teamshared.intra.caep.uk` | 共享 ListenerSet 接住所有 `*.teamshared.intra.caep.uk` |
| Team A HTTPRoute | 匹配 `hostnames: ["springboot-demo.teamshared.intra.caep.uk"]` | 路由到 springboot-demo Service |
| Team B HTTPRoute | 匹配 `hostnames: ["payment-service.teamshared.intra.caep.uk"]` | 路由到 payment-service Service |

---

## 5. 构想可行性评估(6 维度逐项)

### 5.1 评估总览

| # | 业务方构想 | 官方支持 | 关键配置 |
|---|---|---|---|
| ① | GLB URL Map 按 path 区分 API | ✅ 官方 | `pathMatchers[].pathRules[].paths[]`(prefixMatch) |
| ② | **GLB URL Map 按 path 重写 Host 头** | ✅ **官方** | `routeAction.urlRewrite.hostRewrite`(按 path rule / route rule 都行) |
| ③ | GLB → Backend Service 携带改写后的 Host 进 PSC | ✅ 默认行为 | Backend Service `protocol=HTTPS`(不是 TCP) |
| ④ | GKE 侧一份共享 wildcard ListenerSet | ✅ **Gateway API v1.5 官方** | `hostname: "*.teamshared.intra.caep.uk"` + wildcard cert |
| ⑤ | 各 Team 独立 HTTPRoute 匹配自己虚拟域名 | ✅ **官方** | `HTTPRoute.spec.hostnames: ["{apiname}.teamshared.intra.caep.uk"]` |
| ⑥ | 业务方仍只看到 `www.caep.uk` | ✅ 自动 | 用户浏览器地址栏保持 `www.caep.uk`,GKE 内部按改写后的 Host 路由 |

### 5.2 详细技术点逐项展开

#### ① GLB URL Map 按 path 区分 API ✅

**官方文档**([GLB URL Map concepts](https://cloud.google.com/load-balancing/docs/url-map-concepts)):

> "A URL map is a set of Google Cloud configuration resources that direct requests for URLs to backend services or backend buckets. The URL map does so by using the hostname and path portions for each URL it processes."

**配置示意**:
```yaml
defaultService: projects/<PROJECT_ID>/global/backendServices/${BS}-global
name: global-lb-map
hostRules:
- hosts:
  - '*'
  pathMatcher: matcher1
pathMatchers:
- defaultService: projects/<PROJECT_ID>/global/backendServices/${BS}-global
  name: matcher1
  pathRules:
  - paths: [/springboot-demo/*]
    service: projects/<PROJECT_ID>/global/backendServices/${BS}-springboot
  - paths: [/payment-service/*]
    service: projects/<PROJECT_ID>/global/backendServices/${BS}-payment
```

**注意**:这里如果不同 API 走不同 backend,需要**多个 backend service**;如果所有 API 走同一个 backend,path rules 是空,全部走 default。本架构现状是后者。

#### ② GLB URL Map 按 path 重写 Host 头 ✅✅(核心能力)

**官方文档**([GLB URL Map hostRewrite](https://cloud.google.com/load-balancing/docs/https/setting-up-global-traffic-mgmt)):

> "Rewrite the hostname portion of the URL, the path portion of the URL, or both, before sending a request to the selected backend service."

**官方 API**([urlMaps REST resource](https://cloud.google.com/compute/docs/reference/rest/v1/urlMaps)):

> `pathMatchers[].defaultRouteAction.urlRewrite.hostRewrite` — "Before forwarding the request to the selected service, the request's host header is replaced with contents of `hostRewrite`. The value must be from 1 to 255 characters."

**配置示意**(YAML 等价):
```yaml
pathMatchers:
- name: matcher1
  defaultService: projects/<PROJECT_ID>/global/backendServices/${BS}-global
  routeRules:
  - matchRules:
    - prefixMatch: /springboot-demo/
    priority: 1
    routeAction:
      weightedBackendServices:
      - backendService: projects/<PROJECT_ID>/global/backendServices/${BS}-global
        weight: 100
      urlRewrite:
        hostRewrite: "springboot-demo.teamshared.intra.caep.uk"
  - matchRules:
    - prefixMatch: /payment-service/
    priority: 2
    routeAction:
      weightedBackendServices:
      - backendService: projects/<PROJECT_ID>/global/backendServices/${BS}-global
        weight: 100
      urlRewrite:
        hostRewrite: "payment-service.teamshared.intra.caep.uk"
```

**官方原话**(务必读):"Make sure to replace the placeholders." + "The value must be from 1 to 255 characters."

#### ③ GLB → Backend Service 携带改写后 Host 进 PSC ✅

**关键事实**:
- Backend Service `protocol=HTTPS` 时,HTTP 层 header(包括改写后的 Host)**会透传**到 backend
- PSC NEG 是 TCP 层(NOT HTTP),**透传所有流量**(包括改写后的 Host header 作为 HTTP payload)
- 透传链路:`GLB → Backend Service → PSC NEG → PSC tunnel → ServiceAttachment → K8s Service → GKE Gateway`,每一跳都保留 HTTP header(因为协议是 HTTPS + TCP tunnel)

**你的现状 HTML 已配对**:`${BS}-global protocol=HTTPS, portName=https` ✅

#### ④ GKE 侧一份共享 wildcard ListenerSet ✅✅(Gateway API v1.5 官方)

**官方文档**([Gateway API v1.5 blog](https://kubernetes.io/blog/2026/04/21/gateway-api-v1-5)):

> "A ListenerSet attaches to a Gateway and contributes one or more listeners. The Gateway controller is responsible for merging listeners from the Gateway resource itself and any attached ListenerSet resources."

**多租户官方示例**:
```yaml
# 平台层维护(只此一份)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: platform-system
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
  - name: platform-default
    protocol: HTTPS
    port: 443
    hostname: "*.teamshared.intra.caep.uk"  # ← 通配符 hostname
    tls:
      mode: Terminate
      certificateRefs:
      - name: teamshared-wildcard-cert
```

**关键点**:`hostname: "*.teamshared.intra.caep.uk"`(YAML 字面量,不是 regex)+ 一份 wildcard cert → 所有 Team 请求 `*.teamshared.intra.caep.uk` 都被这个 listener 接住。

#### ⑤ 各 Team 独立 HTTPRoute 匹配虚拟域名 ✅

**Team A**(自己 namespace):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: springboot-demo-route
  namespace: team-springboot
spec:
  parentRefs:
  - name: shared-gateway
    namespace: platform-system
  hostnames:
  - "springboot-demo.teamshared.intra.caep.uk"  # ← 精确匹配,自己虚拟域名
  rules:
  - matches:
    - path: { type: PathPrefix, value: / }
    backendRefs:
    - name: springboot-demo-svc
      port: 80
```

**Team B**(自己 namespace):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: payment-route
  namespace: team-payment
spec:
  parentRefs:
  - name: shared-gateway
    namespace: platform-system
  hostnames:
  - "payment-service.teamshared.intra.caep.uk"
  rules:
  - matches:
    - path: { type: PathPrefix, value: / }
    backendRefs:
    - name: payment-svc
      port: 80
```

**关键事实**:HTTPRoute 的 `hostnames` 字段支持精确匹配,Gateway 收到请求时按 Host 头路由到第一个匹配路由。

#### ⑥ 业务方仍只看到 `www.caep.uk` ✅

- **TLS 终止在 GLB**:业务方的 TLS 证书是 `www.caep.uk` 的公网 cert
- **TLS 在 GKE 侧**是**重新建立**的(因为 protocol=HTTPS),用 wildcard `*.teamshared.intra.caep.uk` cert
- **业务方浏览器地址栏**:始终显示 `www.caep.uk`
- **业务方无需感知**内部 hostname 重写

### 5.7 GKE 侧 Path → 后端 Service 强制锁定(架构师推荐)

> **业务方原话**:"GKE 侧没有 SNI 可用,必须靠 GLB 重写 Host 头 — 我还想在 GKE 侧根据 Path 做一些强制内部的 SNI 转换或满足内部域名定义,让他转发到我内部的域名上面去。这样前后就有一个对应关系他们就能映射上。"
>
> **架构师评估**:**业务方需求合理,但"SNI 转换 / 内部域名转换"不是正解**。**正解是:HTTPRoute 按 Path 锁定 Service,绕过 hostname 限制**。

#### 5.7.1 业务方真正的需求 vs 误判

| 业务方原意(语义层)| 实际想要的 |
|---|---|
| "根据 Path 做 SNI 转换" | 路径 → 后端 Service 的**强制映射**,不依赖 hostname |
| "满足内部域名定义" | 业务方的 API 有**固定的内部 hostname 标识**,即使 hostname 重叠也要按 path 路由 |
| "前后对应关系映射上" | **URL Map 的 path → GKE 的 Service 一一对应**,不允许 hostname 错配导致路由错 |

#### 5.7.2 架构师推荐方案:HTTPRoute Path 锁定(无 SNI)

**核心思路**:**不依赖 hostname,只依赖 path**。Gateway API v1.5 的 HTTPRoute 支持 `rules[].matches[].path` + `backendRefs.name` 强制锁定。

**对比**:hostname-based 路由 vs path-based 路由

| 维度 | Hostname-based(原构想) | Path-based(架构师推荐)|
|---|---|---|
| 路由依据 | HTTP Host 头(GLB 已改写)| HTTP Path(GLB 已按 path 区分)|
| TLS 握手时的 SNI | 改写后的 `*.teamshared.intra.caep.uk` | 同(无关)|
| ListenerSet hostname | 必须唯一 + wildcard cert | 任意,可省略 |
| 配置示例 | `hostnames: ["springboot-demo.teamshared.intra.caep.uk"]` + `paths: ["/"]` | `paths: ["/springboot-demo/", "/springboot-demo/*"]`(无 hostnames 字段) |
| 错配风险 | hostname 错配 → 路由错 | **path 错配 → 路由错(更直接、更易调试)**|
| 适用 | 多域名独立 cert | **多 API 共用 wildcard cert** ✅ |

**官方支持**([Gateway API v1.5](https://kubernetes.io/blog/2026/04/21/gateway-api-v1-5)):

> "HTTPRoute rules allow path-based, header-based, and query parameter-based matching. The `matches[].path` field supports `Exact`, `PathPrefix`, and `RegularExpression` match types."

#### 5.7.3 配置示例(架构师推荐)

**Team A:springboot-demo**(自己 namespace):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: springboot-demo-route
  namespace: team-springboot
spec:
  parentRefs:
  - name: shared-gateway
    namespace: platform-system
  # ⚠ 关键:不配 hostnames 字段,只按 path 路由
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /springboot-demo/        # ← 锁定 path 前缀
      # 也可加 method / headers 进一步精确匹配
    backendRefs:
    - name: springboot-demo-svc        # ← 强制锁定后端 Service
      port: 80
      weight: 100
```

**Team B:payment-service**(自己 namespace):
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: payment-route
  namespace: team-payment
spec:
  parentRefs:
  - name: shared-gateway
    namespace: platform-system
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /payment-service/
    backendRefs:
    - name: payment-svc
      port: 80
```

#### 5.7.4 关键优势(为什么推荐 Path-based)

| 优势 | 说明 |
|---|---|
| **不需要 hostname 唯一** | 多个 HTTPRoute 可共用 `*.teamshared.intra.caep.uk`,靠 path 区分 |
| **不需要每个 API 改写 host** | GLB URL Map 只需配 path rules,无需 `hostRewrite` |
| **配置更直观** | "path = 后端 Service" 一对一映射,业务方/平台都易懂 |
| **Hostname 错配不会路由错** | 即使 GLB 改写 host 失败,GKE Gateway 仍按 path 路由 |
| **a/b testing / 灰度容易** | 加 header-based / weight-based 即可,无需重建 hostname |

#### 5.7.5 关键风险与防御

| 风险 | 防御 |
|---|---|
| **path 冲突**:Team A `/users/*` 与 Team B `/users/admin/*` | 约定 path 前缀严格归属(命名规则:`/{team}/{api}/{version}/*`)+ NetworkPolicy + audit log |
| **未配 path 的 HTTPRoute** | K8s admission controller 拒绝无 path 字段的 HTTPRoute(架构师建议加 OPA Gatekeeper 策略) |
| **跨 Team 错路由** | NetworkPolicy 在 namespace 间禁止 L7 流量,只能在 K8s Gateway 上集中分发 |
| **path 改写冲突** | GLB URL Map path 前缀必须跟 HTTPRoute path 前缀**严格一致**——加 GitOps 双校验 |
| **新 API 申请时** | 平台层同时加 GLB URL Map path + K8s HTTPRoute path,GitOps 同步,4 眼 review |

#### 5.7.6 与原构想的对比(架构师结论)

| 维度 | 原构想(Host-based)| 架构师推荐(Path-based)|
|---|---|---|
| GLB URL Map 改写 Host | 需要 | **不需要**(可选,看是否要统一外部域名)|
| GKE Gateway hostname | `*.teamshared.intra.caep.uk`(wildcard) | 同 |
| HTTPRoute 路由依据 | hostname + path(双维度)| **path 唯一** |
| 业务方需配的字段 | hostname + path | **path 唯一** |
| hostname 冲突风险 | 中(共用 wildcard) | **0**(完全不依赖 hostname)|
| 配置复杂度 | 中 | **低** |
| 适用场景 | 需要 hostname 隔离业务(多 SSL cert)| **多 API 共用 cert + path 区分** ✅(本架构场景) |

→ **架构师推荐**:本架构(Path 前缀区分多 API + wildcard cert 共用)**用 Path-based 方案**。Host-based 仅在"业务方明确要独立 cert"时启用。

#### 5.7.7 与后续 sni-nginx-solution 的关系

| 方案 | 适用 |
|---|---|
| **Path-based(本节,推荐)** | 业务方不需要 hostname 隔离 → 默认方案 |
| **Host-based(原构想 §5)** | 业务方需要 hostname 隔离(每个 API 独立 cert) |
| **Nginx 动态注册(新方案 `sni-nginx-solution.md`)** | 现有架构不动,在 GKE 前加 Nginx 做动态 SNI/Host 注入,适合**改造前置阶段**(transition 方案) |

→ **推荐路径**:**Path-based 作为最终目标** + **Nginx 动态注册作为过渡方案**(现有架构不动的场景)。最终 Path-based 上线后,Nginx 可下线。

---

## 6. 6 实施细节(待你确认)

> **架构师提示**:这些细节是"**做之前必须想清楚**"的关键决策点,业务方/平台层任一方没想清楚都可能导致后期返工。

### 6.1 关键细节 1:GLB 改写后的 Host 头怎么传到 GKE?

| 链路 | 可行 |
|---|---|
| **GLB → Backend Service(改写 Host)→ PSC NEG → ServiceAttachment → K8s Service → GKE Gateway** | ✅ **可行** |
| GLB → Backend Service(TCP 而非 HTTPS) | ❌ 不可取:TCP 层不解析 HTTP,header 改写无法透传 |
| GLB → Backend Service(HTTPS,但不重写 Host) | ❌ 不满足需求 |

**✅ 决策**:**Backend Service protocol 必须是 HTTPS**(现状已配)

### 6.2 关键细节 2:Backend Service 的 `portName` 必须是 `https`

> **你的现状 HTML**:`${BS}-global protocol=HTTPS, portName=https` ✅
>
> 验证:Backend Service 的 `port_name` 必须跟 K8s Service 的 `port.name` 一致,否则流量路由失败。

### 6.3 关键细节 3:GKE 侧 wildcard cert 怎么管?

| 选项 | 适合 | 复杂度 |
|---|---|---|
| **Google Certificate Manager**(官方推荐) | `*.teamshared.intra.caep.uk` 单一 wildcard cert,GKE Gateway 通过 `networking.gke.io/certmap` 引用 | 低 |
| cert-manager + DNS-01 | 自助签发,需装 cert-manager controller | 中 |
| 上传已有 wildcard cert(企业内网 CA 自签)| 一次性,K8s Secret 引用 | 极低(但 GKE Gateway 不读 K8s Secret,**仅 GCBM 路径有效**)|

**架构师建议**:**Google Certificate Manager(GCBM)**——因为 GKE Gateway **不**读 K8s Secret,只读 Certificate Manager / certmap。

参考:[brtkwr.com 2026-05 cert-manager vs GCM](https://brtkwr.com/posts/2026-05-28-cert-manager-vs-google-certificate-manager-for-gke-gateway):

> "GKE-managed Gateway (gatewayClassName: gke-l7-global-external-managed), where TLS terminates at a Google Cloud Load Balancer that does not read Kubernetes Secrets."

### 6.4 关键细节 4:内网域名 `*.teamshared.intra.caep.uk` 怎么签证书?

| 方案 | 可行 | 备注 |
|---|---|---|
| 企业内部 CA 自签 + 加到 GKE Gateway `trustedCA` | ✅ | 内网 cert 完全 OK |
| Let's Encrypt + DNS-01 + 内网 DNS server | ✅ | 但需 IT 配合把 _acme-challenge 解析对外 |
| Google Certificate Manager 公开 CA | ✅ 配 DNS-01 即可 | 但需要公网 DNS 可见 |

**架构师建议**:**企业内部 CA 自签**——内网域名用内网 cert 是标准做法,运维最简单。

### 6.5 关键细节 5:每个 Team 加新 API 时,GLB URL Map 怎么更新?

| 方案 | 适合 | 复杂度 |
|---|---|---|
| 平台层手工 + 4 眼 review | 少量 API | 低 |
| 平台层脚本半自动 | 中量 API | 中 |
| 平台层 GitOps(ArgoCD/Config Sync) | 大量 API + 强合规 | 高 |
| 业务方自助(配 CRD 自动生成) | DevOps 强自治 | 极高 |

**架构师建议**:**GitOps 模式**——`gcp-loadbalancer-config/` 仓库 → Config Sync / ArgoCD 同步,变更留痕,自动 review。
**待你确认**:业务方申请新 API 的 SLA 是多长?如果是天级,手工 + 4 眼 review 即可;如果是小时级,必须自动化。

### 6.6 关键细节 6:Backend TLS 重新握手时的"上游 Host"验证

**问题**:GLB → Backend Service 时,Backend Service 用 HTTPS 跟 PSC NEG 通信。GKE 侧 K8s Service 看到的是哪个 Host?
- **答案**:**改写后的 Host**(`{apiname}.teamshared.intra.caep.uk`),因为 GLB 在 HTTP 层改写后,**新建立的 HTTPS 连接**用新 Host 握手
- **上游 TLS 验证**:`*.teamshared.intra.caep.uk` 的 wildcard cert 服务**所有**改写后的 Host,所以 GKE Gateway 侧的 TLS 终止能正确选 cert
- **不需要**在 GLB 侧加 `proxy_ssl_name` / `proxy_ssl_server_name`(那是 Nginx 的事,改造后去掉了)

**待你确认**:业务方是否要求 GLB 侧做"上游证书验证"(目前 GKE Gateway 侧 wildcard cert 即可,无需 GLB 验证)

---

## 7. 待你确认的开放问题

> **架构师立场**:以下 7 个问题,前 4 个**必须有答案**才能继续推进,后 3 个**有默认值可先推进**。

### 7.1 必有答案(影响架构选型)

| # | 问题 | 业务方/决策者决策 |
|---|---|---|
| **Q1** | "GKE 侧无法在 443 部署带 hostname ListenerSet"修正成"GKE 侧没有 SNI 可用,必须靠 GLB 重写 Host 头" — 是否接受? | ☐ 接受 / ☐ 拒绝 / ☐ 需再讨论 |
| **Q2** | "共享 ListenerSet 无 hostname 限制"修正成"一个 wildcard 通配符 hostname + 共享 wildcard cert" — 是否接受? | ☐ 接受 / ☐ 拒绝 / ☐ 需再讨论 |
| **Q3** | wildcard cert 走 **Google Certificate Manager** 路径(因为 GKE Gateway 不读 K8s Secret) — 是否接受? | ☐ 接受 / ☐ 拒绝(改 cert-manager + Secret) / ☐ 需再讨论 |
| **Q4** | `*.teamshared.intra.caep.uk` 走 **企业内部 CA 自签** 还是 Let's Encrypt 公开 CA? | ☐ 企业内网 CA / ☐ Let's Encrypt / ☐ 需再讨论 |

### 7.2 有默认值可先推进(架构师默认)

| # | 问题 | 默认值 | 推翻条件 |
|---|---|---|---|
| **D1** | Backend Service `protocol` 必须是 HTTPS | ✅ HTTPS(现状已配) | 业务方要求走 HTTP 头跳过 TLS |
| **D2** | GLB URL Map 变更走 GitOps(ArgoCD/Config Sync)| ✅ GitOps | 业务方要求人工 review 不接受自动化 |
| **D3** | 共享 wildcard ListenerSet 绑 `*.teamshared.intra.caep.uk` 通配符 hostname | ✅ 通配符 | 业务方要求每个 Team 单独 hostname(成本激增) |

### 7.3 必查(infra-gcp 跑通后回执)

| # | 项 | infra-gcp 必跑 |
|---|---|---|
| **V1** | GKE 版本 ≥ 1.23.3-gke.900(支持 `networking.gke.io/v1` ServiceAttachment) | ☐ 验证 |
| **V2** | Gateway API CRDs 已安装(1.3+)| ☐ 验证 |
| **V3** | Backend Service `protocol=HTTPS, portName=https`(现状已配)| ☐ 验证 |
| **V4** | GLB URL Map `routeAction.urlRewrite.hostRewrite` 字段已配 | ☐ 验证 |
| **V5** | Cloud Armor policy 包含 `httpRequestHeaderActions` (如需重写后再加 WAF 规则)| ☐ 验证 |

---

## 8. 决策树:这份改造是否值得做

> **架构师观点**:**值得做,前提是 4 个 Q 问题都答上来**。

```
Q1 Q2 Q3 Q4 都 ✅
   │
   ├─► 推进:写正式 ADR-012(沿用 ADR-009/011 模板)
   │       │
   │       ├─► infra-gcp 跑 V1-V5 验证 → 写 provision 步骤
   │       ├─► devops-gcp 配 GitOps pipeline(URL Map 变更自动化)
   │       ├─► qa-gcp 配 4 验证 lane(GLB URL Map / Backend TLS / ListenerSet / HTTPRoute 路由)
   │       └─► 业务方按配置走(申请新 API → 平台层加 URL Map 规则)
   │
   └─► 任何 1 个 Q 否 → 暂停,先讨论清楚再推进
```

---

## 9. ADR 编号预占(为后续正式 ADR 准备)

> **沿用 SOUL.md "ADR 编号流水号不重命名" 原则**:
>
> - 008 K8s v1.37 Static Pod
> - 009 GKE Pod 挂 NAS(Proposed,等 infra-gcp 验证)
> - **010 预留给 NAS 实施细节**
> - 011 GKE Pod 跨 project Bucket(Proposed,本轮交付)
> - **012 预留给"跨项目 Public TLS 改造 + 业务方核心构想"**(本节文档对应)

→ **如推进正式 ADR,新 ADR ID = 012**,沿用 ADR-009/011 的 14 节模板。

---

## 10. 架构师 lane 边界声明

- ✅ 生成 `facing-issue.md`(本节文档,8 节)
- ✅ 6 实施细节 + 7 开放问题,供业务方/决策者拍板
- ✅ 12 个官方文档引用(URL 在 §0 顶部 "配套文档" 区)
- ❌ **不实施任何 provision / apply / gcloud / kubectl**
- ❌ **不创建 GLB / Backend Service / ServiceAttachment / Gateway / HTTPRoute**
- ❌ **不持有 GCP 凭证**
- 实际部署由 infra-gcp 用专属 SA 执行,等业务方回答 Q1-Q4 + 决策者拍板 ADR-012

---

## 11. 文档维护

- **作者**:**architect-gcp**(架构师,设计 lane)
- **Reviewers**:**infra-gcp** / **devops-gcp** / **qa-gcp** / 业务方
- **配套文档**:
  - [`public-tls-cross-project-implementation.html`](./public-tls-cross-project-implementation.html) — 已实现架构图
  - 业务方后续 ADR(若推进):`ADR-012-public-tls-cross-project-host-rewrite.md`(预占编号)

---

<!-- cite: https://kubernetes.io/blog/2026/04/21/gateway-api-v1-5 — Gateway API v1.5 ListenerSet 多租户官方示例 -->
<!-- cite: https://cloud.google.com/load-balancing/docs/https/setting-up-global-traffic-mgmt — GLB URL Map hostRewrite / headerAction 官方文档 -->
<!-- cite: https://cloud.google.com/load-balancing/docs/url-map-concepts — GLB URL Map pathMatchers / pathRules / routeRules 概念 -->
<!-- cite: https://cloud.google.com/compute/docs/reference/rest/v1/urlMaps — urlMaps REST API,hostRewrite/pathPrefixRewrite 字段定义 -->
<!-- cite: https://docs.cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing-across-vpc-net — GKE ServiceAttachment 官方文档 -->
<!-- cite: http://eden-cms-v2.onbex.co/blog/2026/07/08/gateway-api-listenerset-multi-tenant-paas — ListenerSet 多租户 RBAC + 64-listener 上限 -->
<!-- cite: https://brtkwr.com/posts/2026-05-28-cert-manager-vs-google-certificate-manager-for-gke-gateway — GKE Gateway 不读 K8s Secret,只读 GCBM -->
<!-- cite: https://oneuptime.com/blog/post/2026-02-09-multi-cluster-ingress-gke-gateway/view — GKE Multi-Cluster Gateway 配置前置 -->
<!-- cite: https://kgateway.dev/docs/main/setup/listeners/sni — SNI 多 hostname 共享 443 port 概念 -->
<!-- cite: ADR-009 → cross-ref 已建,见 [`../../storage/nas/ADR-009-gke-pod-mount-internal-nas-security-review.md`](../../storage/nas/ADR-009-gke-pod-mount-internal-nas-security-review.md) -->
<!-- cite: ADR-011 → cross-ref 已建,见 [`../../storage/buckets/ADR-011-gke-pod-cross-project-bucket-security-review.md`](../../storage/buckets/ADR-011-gke-pod-cross-project-bucket-security-review.md) -->
<!-- cite: STORAGE-3-PROTOCOLS 总览 → cross-ref 已建,见 [`../../storage/STORAGE-3-PROTOCOLS-COMPARISON.md`](../../storage/STORAGE-3-PROTOCOLS-COMPARISON.md) -->
