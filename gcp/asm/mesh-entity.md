# summary
## Mesh Entity: 用户级别 API 对外部 FQDN / 域名出口的访问控制 (Egress FQDN Control)

这份文档回答你最初提出的核心问题,并融合你提供的**背景信息**:

> 当我们提到一个概念叫 **mesh entity** 的时候,其实核心目的是想要 **控制用户级别的 API 可以访问哪些外部的域名 / FQDN**,也就是对 **egress 的域名或者说 FQDN 端点** 做对应的控制。

**文档会明确告诉你:**

1. Istio / Cloud Service Mesh 的官方术语里 **没有** "mesh entity" 这个词 — 这是场景化描述
2. 真正能落地"用户级别 API → 外部 FQDN 出口控制" 的 Istio 资源是 **三个资源的叠加**:**`ServiceEntry` + `DestinationRule` + `AuthorizationPolicy`**(三件套)
3. 这条链路在生产里通常 **不是只有 mesh 内部** — 应用 → sidecar → 平台 egress → Blue Coat → 外部 FQDN,**多 proxy 收敛** 是实际治理课题
4. **Waypoint proxy**(Envoy-based 开源)+ **HTTP CONNECT 协议** 可以替代商业网关做 Enterprise Engine Gateway 的 egress 隧道,避免 vendor lock-in
5. **Follow-Up Work Plan**(3 项):Vivian tenant template 对齐 / US 内部 POC / SHB wildcard cert 收敛

# 1. Goal And Context

在生产里,我们经常需要做这种控制:

- 某个 API 团队只能调用 `*.payments.partner.com` 这一个外部域名
- 另一个 API 团队只能调用 `*.data-vendor.io` 和 `api.openai.com`
- 其它任何外部域名都不许调用

直觉上,你可能会想说:

> "我有一个 entity 代表这个 API 团队,我希望这个 entity 关联一组允许访问的 FQDN。"

但 Istio / Cloud Service Mesh 的官方 API 设计 **不是这样的**。
它没有一个直接的 `MeshEntity` / `EgressEntity` 资源。Istio 的设计是把"身份"和"出口"切成多层:

| 层 | 资源 | 控制的是 |
|---|---|---|
| **身份侧** | `ServiceEntry` 的 `hosts` / `workloadSelector` + AuthorizationPolicy 的 `principals` / `serviceAccounts` | "**我**是谁" + "**谁**是目的地" |
| **路由行为侧** | `Sidecar.spec.egress[].hosts` / `meshConfig.outboundTrafficPolicy.mode` | "**我能去哪**(路由范围)" |
| **TLS / 连接策略侧** | `DestinationRule.spec.trafficPolicy.tls` / `connectionPool` / `outlierDetection` | "**怎么去**(mTLS / plaintext / TCP tunnel)" |
| **细粒度访问控制** | `AuthorizationPolicy.spec.rules[].to[].operation.hosts` | "**谁的身份** 允许访问 **哪些 host**" |

所以"mesh entity"这个概念在 Istio 里 **不是某个 resource 名字**,而是**一组 field 的组合语义**。下面逐步拆开。

# 2. Short Answer

如果你只能记住一句话:

> **用户级别 API → 外部 FQDN 出口控制,本质是三个 Istio 资源叠加的结果(三件套):**
>
> 1. **`ServiceEntry`** 把"外部 FQDN" **注册** 进 mesh 的内部服务注册表(白名单的载体)
> 2. **`DestinationRule`** 配置**去这个 FQDN 的客户端策略**(TLS / connection pool / TCP tunnel 等)
> 3. **`AuthorizationPolicy.spec.rules[].to[].operation.hosts`** 在身份维度限定**这个 API 的调用方身份能访问哪些 host**

再加一个 mesh-wide 总开关:

> **`meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY`** 把所有没在 `ServiceEntry` 注册过的外部 host **全部默认拒绝** — 这是"默认收紧"的入口。

**而生产实际链路不只有 mesh 这一段 — 平台 egress + Blue Coat + 外部 FQDN 才是完整路径。**

---

# 3. What "Mesh Entity" Really Maps To In Istio

## 3.1 Istio 官方没有这个词

我检索了:

- `Istio Sidecar resource reference` ([istio.io/latest/docs/reference/config/networking/sidecar](https://istio.io/latest/docs/reference/config/networking/sidecar/))
- `Istio AuthorizationPolicy reference` ([istio.io/latest/docs/reference/config/security/authorization-policy](https://istio.io/latest/docs/reference/config/security/authorization-policy/))
- `Istio ServiceEntry reference` ([istio.io/latest/docs/reference/config/networking/service-entry](https://istio.io/latest/docs/reference/config/networking/service-entry/))
- `Istio DestinationRule reference` ([istio.io/latest/docs/reference/config/networking/destination-rule](https://istio.io/latest/docs/reference/config/networking/destination-rule/))
- `Istio concepts/security` ([istio.io/latest/docs/concepts/security/](https://istio.io/latest/docs/concepts/security/))
- `Istio ambient overview` ([istio.io/latest/docs/ambient/overview/](https://istio.io/latest/docs/ambient/overview/))
- `Cloud Service Mesh authorization policy overview` ([cloud.google.com/service-mesh/docs/security/authorization-policy-overview](https://cloud.google.com/service-mesh/docs/security/authorization-policy-overview))

在 Istio 官方文档里出现的最接近概念是:

> **"Mesh-wide policy: A policy specified for the root namespace with no workload selector"**

来源 — Istio concepts/security ([istio.io/latest/docs/concepts/security/](https://istio.io/latest/docs/concepts/security/)):

> **"Mesh-wide policy: A policy specified for the root namespace with no workload selector applies to all workloads in the mesh, in any namespace."**

**注意**,这里的 "mesh-wide" 是 **policy 的作用域**,不是某个具体资源。所以你脑子里那个 "mesh entity" 的概念,在 Istio 里是这样对应的:

| 你说的概念 | Istio 实际对应的资源/字段 |
|---|---|
| "mesh entity = 一个用户/团队/API" | **workloadSelector**(选一组 Pod)+ namespace + ServiceAccount |
| "entity 能访问的外部域名" | **`ServiceEntry.hosts`** 注册外部 host + **`AuthorizationPolicy.to.operation.hosts`** 限定访问目的 + **`DestinationRule.trafficPolicy.tls`** 配置客户端 TLS |

## 3.2 为什么 Istio 没有 "MeshEntity" 资源

因为 Istio 的设计哲学是:

> **身份 ≠ 出口目的地 ≠ 路由可达性 ≠ 客户端 TLS 策略**

这四个东西分别用不同字段控制,解耦的好处是你能自由组合 — 例如一个 team 的 API 既能调内部其它 team 的 service 又能调特定的外部域名,通过给 ServiceEntry / DestinationRule / AuthorizationPolicy 分别写规则来实现。

**坏处就是你要写 3 个 resource 而不是 1 个**,这是 Istio / CSM 在 egress 控制上最常被吐槽的点。

---

# 4. The Three Resources That Actually Do The Job (The "Three-Piece Set")

## 4.1 Resource #1: `ServiceEntry` — 把外部 FQDN 注册进 mesh

**作用**:`ServiceEntry` 是 Istio 用来描述 "一个外部 service 的 metadata" 的资源。它最关键的字段是:

| 字段 | 角色 |
|---|---|
| `hosts` | 注册的外部 host 名(支持 wildcard 如 `*.bar.com`) |
| `location: MESH_EXTERNAL` | 告诉 mesh 这个 host 在 mesh 外部 |
| `resolution` | DNS / STATIC / NONE — 决定怎么解析这个 host |
| `endpoints` | 可选,显式声明 IP(可绕开 DNS) |

**Istio 官方原文 — wildcard hosts + resolution NONE** ([istio.io/latest/docs/reference/config/networking/service-entry/](https://istio.io/latest/docs/reference/config/networking/service-entry/)):

> **"The following example demonstrates the use of wildcards in the hosts for external services. If the connection has to be routed to the IP address requested by the application (i.e. application resolves DNS and attempts to connect to a specific IP), the resolution mode must be set to NONE."**

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: httpbin-ext
spec:
  hosts:
  - httpbin.org
  ports:
  - number: 80
    name: http
    protocol: HTTP
  resolution: DNS
  location: MESH_EXTERNAL   # 关键: 表示这个 host 在 mesh 外部
```

**为什么需要它?** 因为如果 `meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY`,sidecar 默认会 **拒绝所有没注册的外部 host**。你想允许 `api.openai.com` 出站,你必须先把它用 ServiceEntry 注册进来。

**来源 — Istio 源码** ([github.com/istio/api/blob/master/networking/v1alpha3/service_entry.pb.go](https://github.com/istio/api/blob/master/networking/v1alpha3/service_entry.pb.go)),`MESH_EXTERNAL` 是个枚举值(`Location` enum),与 `MESH_INTERNAL` 相对。

## 4.2 Resource #2: `DestinationRule` — 客户端策略(去这个 FQDN 怎么连)

**作用**:`DestinationRule.spec.trafficPolicy` 用来配置 **客户端** 到某个 destination 的策略。它在 egress FQDN 控制链上的角色是:

| 子字段 | 角色 |
|---|---|
| `tls.mode` | DISABLE / SIMPLE / ISTIO_MUTUAL / MUTUAL_ISTIO — 决定连接用哪种 TLS |
| `tls.certificates` | SIMPLE 模式下挂 client cert(对接外部服务的 mTLS) |
| `tls.sni` | 显式 SNI 覆盖 |
| `connectionPool` | TCP / HTTP 连接池大小 |
| `outlierDetection` | 不健康实例剔除 |
| `tunnel` | TCP over HTTP CONNECT tunnel — **这就是 Enterprise Engine Gateway 用的机制** |

**Istio 官方原文 — TrafficPolicy 字段定义** ([istio.io/latest/docs/reference/config/networking/destination-rule/](https://istio.io/latest/docs/reference/config/networking/destination-rule/)):

> **"Traffic policies to apply for a specific destination, across all destination ports."**

> **"tls: ClientTLSSettings — TLS related settings for connections to the upstream service."**

> **"tunnel: TunnelSettings — Configuration of tunneling TCP over other transport or application layers for the host configured in the DestinationRule."**

**示例 — DR 给外部 host 配置 mTLS client + TCP tunnel**:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: external-payments-mtls
spec:
  host: api.payments.partner.com   # 必须跟某个 ServiceEntry.hosts 对应
  trafficPolicy:
    tls:
      mode: MUTUAL                  # mTLS 客户端模式
      clientCertificate: /etc/certs/client.pem
      privateKey: /etc/certs/client.key
      caCertificates: /etc/certs/ca.pem
      sni: api.payments.partner.com
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 50
        maxRequestsPerConnection: 10
```

**为什么需要它?** 因为:

1. 外部服务经常要求 **客户端 mTLS**(比如 SHB / SHB Enterprise Engine 接入就需要客户端证书)
2. 经过中间 egress proxy(Blue Coat)的 TCP 流量可能需要 **HTTP CONNECT tunnel**
3. connection pool / outlier detection 是 QoS 治理

## 4.3 Resource #3: `AuthorizationPolicy` — 身份 → host 维度的访问控制

**作用**:`AuthorizationPolicy.spec.rules[].to[].operation.hosts` 用来在 **请求的目的 host** 维度收紧授权。这是 **唯一** 一个 Istio 资源让你可以写"哪些 SA 可以调这些 host"。

**Istio 官方原文** ([istio.io/latest/docs/reference/config/security/authorization-policy/](https://istio.io/latest/docs/reference/config/security/authorization-policy/)):

> **`Operation.hosts: "A list of hosts as specified in the HTTP request. The match is case-insensitive. See the security best practices for recommended usage of this field. If not set, any host is allowed. Must be used only with HTTP."**

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: api-orders-allow-external
  namespace: abjx-int
spec:
  selector:
    matchLabels:
      app: api-orders
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - "cluster.local/ns/abjx-int/sa/orders-sa"
    to:
    - operation:
        hosts:
        - "api.payments.partner.com"     # 关键: FQDN 白名单
        - "*.data-vendor.io"
        methods: ["GET", "POST"]
```

**关键限制**:`Operation.hosts` 必须搭配 HTTP,不能用来限制 TCP-level 的 egress(详见 §5.4)。

**Istio 源码证据** ([github.com/istio/api/blob/master/security/v1beta1/authorization_policy.pb.go](https://github.com/istio/api/blob/master/security/v1beta1/authorization_policy.pb.go)):

| 字段 | PB 字段 | 行号 |
|---|---|---|
| `selector` | `*v1beta1.WorkloadSelector` | L391 |
| `rules[].from[].source.principals` | `Principals []string` | L624 |
| `rules[].to[].operation.hosts` | `Hosts []string` | L846 |

---

# 5. The Mesh-Wide Switch: `meshConfig.outboundTrafficPolicy.mode`

如果你不显式打开下面的开关,所有上面的精细配置 **白做** — 因为默认情况下 sidecar 是 `ALLOW_ANY`。

**Istio 官方原文** ([istio.io/latest/docs/tasks/traffic-management/egress/egress-control/](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-control/)):

> **"Istio has an installation option, `meshConfig.outboundTrafficPolicy.mode`, that configures the sidecar handling of external services, that is, those services that are not defined in Istio's internal service registry. If this option is set to `ALLOW_ANY`, the Istio proxy lets calls to unknown services pass through. If the option is set to `REGISTRY_ONLY`, then the Istio proxy blocks any host without an HTTP service or service entry defined within the mesh. `ALLOW_ANY` is the default value."**

| Mode | 行为 | 适用场景 |
|---|---|---|
| `ALLOW_ANY`(默认) | sidecar 放过所有未知 host | dev / PoC / 快速评估 |
| `REGISTRY_ONLY` | sidecar 拒绝所有未注册的 host | 生产 / 多租户隔离 |

```bash
# 验证当前 meshConfig
kubectl get configmap istio -n istio-system -o yaml | grep outboundTrafficPolicy

# 安装时设置
istioctl install --set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY
```

**升级路径**:

| 你的需求 | MeshConfig mode | 必须的资源组合 |
|---|---|---|
| "随便调,先跑起来" | `ALLOW_ANY`(默认) | 无 |
| "禁止调所有外部 host" | `REGISTRY_ONLY` + **不放任何外部 ServiceEntry** | ServiceEntry |
| "允许调指定的几个外部 host" | `REGISTRY_ONLY` + ServiceEntry(白名单) | ServiceEntry |

---

# 6. Tenant Egress Cross-Platform Flow (Lex 团队实际生产链路)

## 6.1 真实拓扑

你提供的背景信息里,生产环境的 egress 链路实际是 **多层 proxy 串联**:

```
┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐    ┌──────────────┐    ┌──────────────────┐
│  Application │ ──→│ Istio sidecar /  │ ──→│  Aliyun 平台      │ ──→│ Blue Coat     │ ──→│ External FQDN    │
│  Pod         │    │  ambient ztunnel │    │  egress 节点      │    │ forward proxy │    │ (api.openai.com) │
│  (mesh 内部) │    │  (mesh 出口)     │    │  (平台强制)       │    │ (DLP / 审计)  │    │                  │
└──────────────┘    └──────────────────┘    └──────────────────┘    └──────────────┘    └──────────────────┘
                       [Layer 1]              [Layer 2]              [Layer 3]            [Layer 4]
                       Istio 控制             平台控制               第三方控制            目标服务
                       FQDN 白名单            IP / 域名 收敛         FQDN / 域名白名单
```

**每一层做的"事情不同,管的事情不同":**

| 层 | 节点 | 控制什么 | 不控制什么 |
|---|---|---|---|
| Layer 1 | Istio sidecar / ztunnel | FQDN 白名单(AuthorizationPolicy.to.operation.hosts) + 客户端 TLS(DestinationRule) + mTLS / mesh identity | 不做 DLP / 不做最终审计 |
| Layer 2 | Aliyun 平台 egress | **平台强制的网络收敛点**,做 IP / 域名 收敛(具体能力和 Aliyun 平台对齐) | 不一定能做 FQDN 级别精细白名单(需平台确认) |
| Layer 3 | Blue Coat forward proxy | **企业级 DLP / 审计 / FQDN 黑名单**(企业安全策略) | 不理解 mesh identity(只能看到 IP / SNI) |
| Layer 4 | External service | 决定 mTLS / auth 校验 | 无 |

## 6.2 关键问题:多 Proxy 收敛(Multi-Proxy Stacking)

**你背景信息里明确提出**:"The current multi-proxy stacking architecture will be gradually converged; the Aliyun platform egress link to directly connect to Blue Coat proxy needs clarification to reduce intermediate nodes."

**问题分析:**

每加一层 proxy 都有代价:

| 代价 | Layer 1 (sidecar) | Layer 2 (Aliyun) | Layer 3 (Blue Coat) |
|---|---|---|---|
| **连接额外延迟** | ~1-3ms | ~5-10ms | ~10-30ms |
| **TLS 终止次数** | 1 次 (TLS origination) | 0-1 次 (TCP 透传 / 重新 TLS) | 1 次 (TLS interception + re-encrypt) |
| **配置耦合** | mesh CRD | 平台配置 | 企业策略 |
| **故障域** | mesh 内部 | 平台 SLO | 企业 SLO |

**收敛思路**:

| 收敛方向 | 做法 | 风险 |
|---|---|---|
| **去掉 Layer 2**(让 sidecar 直连 Blue Coat) | Istio sidecar → Blue Coat → 外部 | 平台失去 egress 收敛点;需要 Blue Coat 配合 mesh identity |
| **去掉 Layer 1**(平台 egress 当 egress gateway) | 应用 → Aliyun egress → Blue Coat → 外部 | 失去 mesh 内部 FQDN 控制和 mTLS identity |
| **保留 Layer 1 + Layer 3,改造 Layer 2 为可选项** | sidecar → Blue Coat(经 Aliyun 平台"按需"收敛) | 需要 Aliyun 平台支持 egress 直通模式 |

**当前建议**(未验证,需跟平台 + Blue Coat 对齐):**保留 Layer 1(Istio)+ Layer 3(Blue Coat),让 Layer 2(Aliyun)成为透明转发层** — 因为前两层都有 mesh identity 概念,Layer 2 是纯网络层。

## 6.3 各层"管什么"的对比表

| 控制项 | Layer 1 (Istio) | Layer 2 (Aliyun) | Layer 3 (Blue Coat) |
|---|---|---|---|
| **FQDN 白名单(用户/团队)** | ✅ AuthorizationPolicy + ServiceEntry | ⚠️ 看平台能力(待确认) | ✅ 平台级策略 |
| **客户端 mTLS** | ✅ DestinationRule.tls | ❌ | ⚠️ 取决于 Blue Coat 模式(forward proxy vs MITM) |
| **mTLS / mesh identity** | ✅ SPIFFE identity | ❌ | ❌(只看到 IP / SNI) |
| **DLP / 内容审计** | ❌ | ⚠️ 看平台 | ✅ Blue Coat 强项 |
| **TLS interception(中间人解密)** | ❌ | ⚠️ 看平台 | ✅(蓝盾 / DLP 需要) |
| **Audit log** | ✅ Envoy access log | ⚠️ 看平台 | ✅ |

---

# 7. Waypoint Proxy + CONNECT Protocol(替代商业网关)

## 7.1 背景:SHB Enterprise Engine Gateway 的需求

你提供的背景信息里提到:

> "Third-Party Gateway Evaluation: For SHB's Enterprise Engine Gateway request, verification confirms the open-source Waypoint proxy supports required Connect protocol tunnel capability, eliminating the need for paid commercial tools to avoid vendor lock-in and extra cost."

**这里的核心命题是:**

- SHB Enterprise Engine Gateway(第三方网关)需要一个 **HTTP CONNECT 隧道能力**(让内网应用通过 CONNECT 把 HTTPS 流量转到外部)
- 商业方案可能是某种付费的 HTTPS forward proxy appliance
- **Istio 生态里有一个原生概念可以替代 — Waypoint proxy**

## 7.2 What is Waypoint Proxy

**Istio 官方原文** ([istio.io/latest/docs/ambient/overview/](https://istio.io/latest/docs/ambient/overview/)):

> **"The waypoint proxy is a deployment of the Envoy proxy; the same engine that Istio uses for its sidecar data plane mode."**

> **"Waypoint proxies run outside of application pods. They are installed, upgraded, and scale independently from applications."**

**关键属性**:

| 属性 | 含义 |
|---|---|
| **运行位置** | 装在 pod 外(不像 sidecar 必须 inject 到每个 pod) |
| **数据面** | Envoy(和 sidecar 同引擎) |
| **升级 / 扩缩容** | 独立于应用 |
| **可观测性** | 享受 Istio 全套遥测(trace / metric / log) |

## 7.3 HTTP CONNECT Protocol Tunneling(Istio 的"HBONE")

**Istio 官方原文** ([istio.io/latest/docs/ambient/overview/](https://istio.io/latest/docs/ambient/overview/)):

> **"At the transport layer, this is implemented via an HTTP CONNECT-based traffic tunneling protocol called HBONE."**

| 协议层 | 实现机制 |
|---|---|
| **L4 安全 overlay** | HTTP CONNECT-based traffic tunneling protocol = **HBONE** |
| **L7 出口代理** | Waypoint proxy(Envoy-based) |

**应用场景 — Enterprise Engine Gateway**:

```
Enterprise App ──HTTP CONNECT (CONNECT host:port)──→ Waypoint proxy ──TCP/TLS──→ External FQDN
                  (CONNECT 隧道发起)                    (Envoy 终止 CONNECT)         (实际目标)
```

**为什么用开源 Waypoint 而不是商业方案**:

| 维度 | 开源 Waypoint (Envoy) | 商业 HTTPS Forward Proxy Appliance |
|---|---|---|
| **CONNECT 协议支持** | ✅ 原生支持 | ✅ |
| **mTLS / mesh identity** | ✅ SPIFFE 透传 | ❌(通常只看到 IP / SNI) |
| **Audit / 审计** | ✅ Envoy access log | ✅ |
| **DLP / 内容审查** | ⚠️ 需配合外部 L7 inspection | ✅ 通常集成 |
| **Vendor lock-in** | ❌(CNI / Envoy 标准) | ✅(专有协议 / 专有配置) |
| **成本** | ✅ 仅基础设施 | ❌ License + 维护费 |
| **可观测性** | ✅ Prometheus / Jaeger / Zipkin | ⚠️ 私有 API |

**结论**:对 SHB Enterprise Engine Gateway 来说,CONNECT 协议能力是核心 — Waypoint (Envoy) 100% 覆盖,且带来 mesh identity 优势,无需付费。

## 7.4 DR.tunnel 字段 — CONNECT tunnel 的另一处体现

`DestinationRule.spec.trafficPolicy.tunnel` 也是 CONNECT-style tunneling 的另一种用法(per-host 配置,不是 per-gateway 配置)。

**Istio 官方原文** ([istio.io/latest/docs/reference/config/networking/destination-rule/](https://istio.io/latest/docs/reference/config/networking/destination-rule/)):

> **"tunnel: TunnelSettings — Configuration of tunneling TCP over other transport or application layers for the host configured in the DestinationRule."**

这个用法适合"某个特定外部 host 必须经过 HTTP CONNECT tunnel 出去"的场景(比如绕开企业防火墙)。

---

# 8. Putting It Together: User-Level API → FQDN Egress Control (完整 4 步)

## 8.1 推荐最小落地模型

假设你有 `api-orders` 这个 API,只允许调用 `api.payments.partner.com` 和 `*.data-vendor.io`,其它外部 host 全部拒绝。

**Step 1:开 mesh-wide 收紧**

```bash
istioctl install --set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY
```

**Step 2:ServiceEntry 注册允许的外部 FQDN**

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: allowed-external-fqdns
  namespace: abjx-int
spec:
  hosts:
  - api.payments.partner.com
  - api.data-vendor.io
  - report.data-vendor.io
  ports:
  - number: 443
    name: https
    protocol: HTTPS
  resolution: DNS
  location: MESH_EXTERNAL
```

**Step 3:DestinationRule 配置客户端 TLS / connection pool**

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: external-payments-dr
  namespace: abjx-int
spec:
  host: api.payments.partner.com     # 必须跟 ServiceEntry.hosts 对应
  trafficPolicy:
    tls:
      mode: SIMPLE                   # 到外部 host 用 SIMPLE TLS(单向)
      sni: api.payments.partner.com
    connectionPool:
      tcp:
        maxConnections: 100
```

**Step 4:AuthorizationPolicy 限定哪个 SA 可以调哪些 host**

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: api-orders-allow-external
  namespace: abjx-int
spec:
  selector:
    matchLabels:
      app: api-orders
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - "cluster.local/ns/abjx-int/sa/orders-sa"
    to:
    - operation:
        hosts:
        - "api.payments.partner.com"
        - "*.data-vendor.io"
        methods: ["GET", "POST"]
```

## 8.2 关键决策表:每一步解决什么

| 步骤 | 资源 | 解决的问题 | 不解决什么 |
|---|---|---|---|
| Step 1 | `meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY` | 禁止访问**所有未注册**的外部 host | 不能区分"哪个团队允许哪些 host" |
| Step 2 | `ServiceEntry` | 注册白名单外部 host(让 sidecar 认得它) | 不做身份区分 — 任何 mesh 内的 Pod 都能调 |
| Step 3 | `DestinationRule` (用 `trafficPolicy.tls` / `connectionPool`) | 客户端 TLS 模式 / 连接池 / TCP tunnel | **不做身份维度的 host 限制** — 所有 mesh 身份都同样策略 |
| Step 4 | `AuthorizationPolicy` (用 `to.operation.hosts`) | 限定**特定身份** 只能访问特定 host | 不开 Step 1 + Step 2 也生效,但默认 mesh-wide 不阻拦其他 host |
| Step 5(可选) | `Sidecar.egress[].hosts` | 节省 sidecar 配置内存,精确路由 | **不阻断流量**(Istio 官方明确说了) |

## 8.3 这一组合解决不了的:TCP-level egress

`AuthorizationPolicy.to.operation.hosts` 文档明确说:

> **"Must be used only with HTTP."**

([istio.io/latest/docs/reference/config/security/authorization-policy/](https://istio.io/latest/docs/reference/config/security/authorization-policy/))

**意味着**:如果你要限制某个 API 只能 TCP-调外部某些 IP(不是 HTTP),`AuthorizationPolicy` 帮不上忙。你需要的是:

- **Egress Gateway / Waypoint proxy** + NetworkPolicy/Firewall
- 或者回到 **NetworkPolicy egress** + IP allowlist
- 或者把 TCP 流量包成 HTTP(grpc over HTTP/2)

---

# 9. Common Pitfalls

## 9.1 Pitfall #1:认为 `Sidecar.egress[].hosts` 是 egress firewall

Istio 官方明确说:

> **"A common misunderstanding is that restricting the configuration amounts to blocking the traffic. If requests are sent to destinations not included in the scoping, the traffic will be treated as unmatched traffic, which is often still allowed. The sidecar is not able to enforce an outbound traffic restriction (see Egress Gateways for how to achieve this)."**

([istio.io/latest/docs/reference/config/networking/sidecar/](https://istio.io/latest/docs/reference/config/networking/sidecar/))

**Sidecar 只控制 sidecar 装载的配置,不控制流量本身。**

## 9.2 Pitfall #2:AuthorizationPolicy 默认 deny

Istio 的 AuthorizationPolicy 有个反直觉的默认行为:

> **没有 AuthorizationPolicy = allow all**
> **有 ALLOW rule 但不带 DENY = 默认还是 allow all,因为 ALLOW 是白名单叠加在 implicit allow 上**

要真正做到 "默认拒绝",必须显式写一条:

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: abjx-int
spec: {}   # 空 spec + 没 action = 默认 DENY(必须放在 root namespace 或用 selector 选目标)
```

(具体语义参考 [istio.io/latest/docs/concepts/security/](https://istio.io/latest/docs/concepts/security/) — `Authorization` 部分)

## 9.3 Pitfall #3:`meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY` 不区分 namespace

这是一个 mesh-wide 开关,你要么全集群 `REGISTRY_ONLY` 要么全 `ALLOW_ANY`。如果你的设计是"某些 namespace 收紧,某些不收紧",你需要:

- **方案 A**:全集群开 `REGISTRY_ONLY`,然后给所有需要调用外部的 namespace 都加 ServiceEntry
- **方案 B**:不靠 mesh-wide 开关,纯靠 `AuthorizationPolicy` 显式拒绝 (`spec.action: DENY`)

**注意**:你不能给某些 namespace 开 `REGISTRY_ONLY` 其它开 `ALLOW_ANY` — 这是个 mesh-level install-time 设置。

## 9.4 Pitfall #4:`ServiceEntry.hosts` 用 wildcard,AuthorizationPolicy 也得跟着 wildcard

如果你这样写:

```yaml
# ServiceEntry
spec:
  hosts:
  - "*.data-vendor.io"   # 允许所有子域名
```

那么 AuthorizationPolicy 的 `to.operation.hosts` 也要同步:

```yaml
to:
- operation:
    hosts:
    - "*.data-vendor.io"   # 必须一致
```

**两边任何一边 wildcard 不一致就会出现 "ServiceEntry 允许但 AuthorizationPolicy 拒绝" 的死循环**。

## 9.5 Pitfall #5:DestinationRule.host 必须跟 ServiceEntry.hosts 对应

**Istio 官方原文** ([istio.io/latest/docs/reference/config/networking/service-entry/](https://istio.io/latest/docs/reference/config/networking/service-entry/)):

> **"The associated DestinationRule is used to initiate mTLS connections to the database instances."**

也就是说:

```yaml
# ServiceEntry.hosts: ["api.payments.partner.com"]
# DestinationRule.host: "api.payments.partner.com"     # 必须完全匹配,DR 才能作用
```

如果 DR.host 是 `api.payments.partner.com:443` 或者带前缀 `*`,DR 都不会匹配到这个 SE。

## 9.6 Pitfall #6:在多 proxy 拓扑里,只配一层是不够的

**你提供的背景信息里描述的真实生产环境**有 4 层 proxy,如果只配 Istio 这一层:

- 应用 → sidecar(✅ FQDN 白名单生效)
- sidecar → Aliyun 平台 egress(⚠️ 平台可能有独立策略)
- Aliyun → Blue Coat(⚠️ Blue Coat 可能有独立 FQDN 黑名单)
- Blue Coat → 外部 FQDN(✅ 真正到达目标)

**任何一层缺配置,流量都会出问题**。必须 4 层都做对应的配置 / 对齐。

---

# 10. Decision Tree: How To Actually Pick

```
我要"用户级别 API → 外部 FQDN 出口控制"
│
├── 这个外部流量是 HTTP/HTTPS/gRPC?
│   ├── 是 → 用 AuthorizationPolicy.to.operation.hosts (Step 4)
│   │       ├── mesh 默认 ALLOW_ANY? → 开 meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY (Step 1)
│   │       ├── ServiceEntry 注册了外部 host 吗? → 没注册先加 ServiceEntry (Step 2)
│   │       └── 需要客户端 mTLS / 连接池 / TCP tunnel? → 加 DestinationRule (Step 3)
│   │
│   └── 否(纯 TCP,如 MySQL/Redis/自定义 TCP)
│       └── AuthorizationPolicy 帮不上,改用:
│           ├── Egress Gateway / Waypoint proxy + NetworkPolicy/Firewall IP allowlist
│           └── 或者 sidecar 终止后 egress gateway 转出
│
├── 需要经过中间 proxy(Blue Coat / 企业 forward proxy)?
│   └── 用 Waypoint proxy(Envoy-based)+ HTTP CONNECT tunnel
│       - 替代商业 HTTPS forward proxy appliance
│       - 享受 mesh identity / mTLS 透传
│
└── 想顺便限制 sidecar 配置大小?
    └── 加 Sidecar.spec.egress[].hosts (Step 5)
        注意:这不阻断流量,只裁剪配置
```

---

# 11. Comparison To AuthorizationPolicy Source Document

回顾你在 `authorizationPolicy-and-Peerauthentication.md` 里熟悉的概念,这篇文档讲的"mesh entity"是 **另一条独立维度**:

| 文档 | 控制范围 |
|---|---|
| `authorizationPolicy-and-Peerauthentication.md` | 入口(inbound)流量 — 谁可以调这个 API |
| `mesh-entity.md`(本篇) | 出口(outbound)流量 — 这个 API 能调哪些外部 FQDN |

它们的 AuthorizationPolicy schema 是 **同一份**,但应用方向相反:

| 字段 | 入口控制(原文 doc) | 出口控制(本篇) |
|---|---|---|
| `rules[].from[].source.principals` | 调用方 SA 身份 | 通常不用(我们关心"我能去哪"不是"谁能调我") |
| `rules[].to[].operation.hosts` | 通常不用(不需要限定入口 host) | ✅ 限定允许访问的外部 FQDN |
| `rules[].to[].operation.methods` | 通常不用 | ✅ 限定允许的 HTTP method |

---

# 12. Recommended Pattern

## 12.1 平台工程视角的"分层模型"

| 层 | 资源 | 平台默认 | API owner 自定义 |
|---|---|---|---|
| **Mesh-wide 总开关** | `meshConfig.outboundTrafficPolicy.mode` | 平台 install 时强制 `REGISTRY_ONLY` | 不允许 override |
| **外部 host 注册表** | `ServiceEntry` | 平台提供 template + allowlist 流程 | API owner 申请后平台审批 + apply |
| **客户端 TLS 策略** | `DestinationRule.trafficPolicy.tls` | 平台提供默认 SIMPLE + SNI 模板 | API owner 按外部服务要求覆盖 |
| **per-workload egress 路由范围** | `Sidecar.egress[].hosts` | 平台 Helm/Kustomize 模板默认 `"./*" + "istio-system/*"` | API owner 按需扩展 |
| **身份 → FQDN 精细授权** | `AuthorizationPolicy.to.operation.hosts` | API owner 自维护,平台审核 lint 规则 | API owner 自维护 |

## 12.2 多团队场景下的实际例子

假设平台上有 `frontend-team`、`orders-team`、`billing-team` 三个团队:

```yaml
# 平台 baseline(平台统一下发)
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio-mesh-baseline
  namespace: istio-system
data:
  mesh: |-
    outboundTrafficPolicy:
      mode: REGISTRY_ONLY     # 平台强制
---
# 每个 runtime namespace 一条 namespace-level AuthorizationPolicy baseline
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: namespace-baseline
  namespace: abjx-int
spec:
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["*"]    # 接受任意 mesh 内带身份请求
# (deny-by-default 还需要在 root namespace 或各 ns 显式配置)
```

```yaml
# orders-team 的外部 host 白名单(团队维护)
---
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: orders-allowed-externals
  namespace: abjx-int
spec:
  hosts:
  - api.payments.partner.com
  - *.data-vendor.io
  ports:
  - number: 443
    name: https
    protocol: HTTPS
  resolution: DNS
  location: MESH_EXTERNAL
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: orders-payments-dr
  namespace: abjx-int
spec:
  host: api.payments.partner.com     # 对应 SE
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: api.payments.partner.com
    connectionPool:
      tcp:
        maxConnections: 100
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: orders-api-egress
  namespace: abjx-int
spec:
  selector:
    matchLabels:
      app: api-orders
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - "cluster.local/ns/abjx-int/sa/orders-sa"
    to:
    - operation:
        hosts:
        - api.payments.partner.com
        - "*.data-vendor.io"
        methods: ["GET", "POST"]
```

**这个组合就让"orders-team 这个用户级别 API" 只能调用上述两个外部域名,其它一律拒绝。**

---

# 13. Follow-Up Work Plan

下面这些事项来自你提供的背景信息,文档层面的探索只是第一步 — **这些是真正要落地的工作**:

## 13.1 Tenant Template Alignment(Vivian)

**事项**:Hold a dedicated call with Vivian to review tenant service mesh templates and clarify specific onboarding and migration requirements.

**这是 tenant 上线流程里的一个具体动作**:

- **目的**:跟 Vivian(tenant 服务网格模板 owner)对齐 tenant onboarding 时的 mesh 资源模板
- **关键问题**:
  - 现有 tenant template 是否已经包含 `meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY` ?
  - 现有 template 是否包含 namespace-level `AuthorizationPolicy` baseline ?
  - 现有 template 是否包含 default `Sidecar` ?
  - 每个 tenant 申请 ServiceEntry 的流程是怎样的(平台审批 / 自助)?
- **行动项**:
  1. 拉 Vivian 一起开 30-45min 对齐会议
  2. 共享本文档 §12 的"分层模型"作为讨论基线
  3. 输出"Migration delta":现有 template 缺什么、要加什么、按什么顺序加

## 13.2 Pilot Verification(US Side POC)

**事项**:Complete internal POC on the US side to confirm workload port and traffic compatibility before rolling out to external users.

**这是任何 mesh 改动前的标准 SRE 流程**:

- **范围**:仅 US 区域(可能是某个特定 GKE 集群)的 internal POC
- **目的**:**实际跑通** §8 推荐的"三件套 + mesh-wide switch",验证:
  - workload 端口兼容性(Envoy 15090 / 15021 / 15020 等管理端口不冲突)
  - 业务流量兼容性(mTLS 对客户端 lib 的要求、HTTP/2 vs HTTP/1.1 等)
  - **真实 FQDN 调用是否被正确允许 / 拒绝**(用 `tcpdump` / Envoy access log 验证)
  - 性能开销(每加一层 policy 都有 1-3ms 延迟)
- **不要做的事**:
  - ❌ 在 POC 没跑通前推到 external users
  - ❌ 跳过 Envoy access log 验证(只看"流量没断"是不够的)
- **行动项**:
  1. 选一个非关键 namespace 做 POC(避免影响生产 tenant)
  2. 应用 §8 的 4-step 模板
  3. 用 Envoy access log / Kiali 验证 FQDN 命中规则
  4. 记录性能 baseline,作为推广决策依据

## 13.3 Gateway Requirement Alignment(SHB Wildcard Cert)

**事项**:Follow up with SHB on their wildcard certificate requirement for edge gateways to finalize egress configuration rules.

**这是 SHB 接入的关键技术对齐**:

- **SHB 需求**:SHB 边缘网关需要 **wildcard certificate**(通配符证书)— 例如 `*.shb-internal.example.com` 一张证书覆盖多个子域名
- **为什么这影响 egress 配置规则**:
  - wildcard cert 意味着 SHB 多子域名共享同一张证书(同一 CA chain)
  - DestinationRule.tls.certificates / caCertificates 的配置粒度需要支持 wildcard(可能需要按 `*.shb-internal.example.com` 配)
  - AuthorizationPolicy.to.operation.hosts 的 wildcard 匹配要覆盖到所有 SHB 子域名
- **行动项**:
  1. 跟 SHB 对齐 wildcard cert 的具体格式(SAN / CN / CA chain)
  2. 跟 SHB 对齐他们 Enterprise Engine Gateway 的 SNI 要求(必须用哪个 host 名作为 SNI)
  3. 根据对齐结果更新:
     - `ServiceEntry.hosts`(注册所有 SHB 子域名)
     - `DestinationRule.tls.certificates / caCertificates / sni`(对接 SHB 证书链)
     - `AuthorizationPolicy.to.operation.hosts`(白名单规则)
     - 可能需要 `Waypoint proxy + HTTP CONNECT tunnel` 让 mesh 内部应用通过 CONNECT 走 SHB Enterprise Engine Gateway

---

# 14. What Mesh Entity Is NOT

为了避免后续混淆,明确一些**不是** "mesh entity" 的常见误解:

| 误解 | 实际情况 |
|---|---|
| "mesh entity 是一个 Istio 资源" | ❌ Istio 没有这个资源,这是用户场景化描述 |
| "AuthorizationPolicy 能完全限制 egress" | ⚠️ 部分正确 — 仅 HTTP 流量,且需要配合 ServiceEntry + REGISTRY_ONLY |
| "Sidecar.egress[].hosts 能阻断 egress" | ❌ Istio 文档明确说不能阻断流量 |
| "开 REGISTRY_ONLY 就够" | ❌ 只挡了未注册 host,没挡"注册了但不归我"的 host |
| "ServiceEntry + AuthorizationPolicy 等于"用户级别 FQDN 控制" | ⚠️ 不完整 — 还差 DestinationRule 配置客户端 TLS,且多 proxy 拓扑里 platform egress + Blue Coat 也要单独配 |
| "Waypoint proxy 是 ambient mesh 专有" | ⚠️ 技术上 yes,但 waypoint proxy 本质就是 Envoy 部署,**任何需要 HTTP CONNECT 隧道的场景都能复用**(包括 SHB Enterprise Engine Gateway 接入) |

---

# 15. Final Summary

## 15.1 一句话答案

> **用户级别 API 对外部 FQDN 的出口控制 = `meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY` + `ServiceEntry`(白名单) + `DestinationRule`(客户端 TLS / 连接池) + `AuthorizationPolicy.to.operation.hosts`(身份 → host 映射),可选 `Sidecar.egress[].hosts` 节省配置。**

## 15.2 四个 resource 的边界

| Resource | 控制范围 | 不能做什么 |
|---|---|---|
| `meshConfig.outboundTrafficPolicy.mode` | mesh-wide "未注册 host 默认拒绝"开关 | 不能 per-namespace / per-workload 差异化 |
| `ServiceEntry` | 把外部 host 注册进 mesh 路由表 | 不区分身份,只区分 host |
| `DestinationRule` | 客户端 TLS / 连接池 / outlier detection / TCP tunnel | 不做"哪个 SA 能调哪个 host" |
| `Sidecar.egress[].hosts` | 限定 sidecar 装载的路由配置 | **不阻断流量** |
| `AuthorizationPolicy.to.operation.hosts` | 限定特定身份能访问哪些 host | 仅 HTTP,不能管 TCP-level |

## 15.3 最重要的判断

如果你要落地"用户级别 → 外部 FQDN 出口控制":

1. **必须** 开 `meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY`(默认 ALLOW_ANY 啥都拦不住)
2. **必须** 给每个允许的外部 host 写一条 `ServiceEntry`
3. **必须** 给每个 API 团队写一条 `AuthorizationPolicy` 把 `to.operation.hosts` 限定到该团队的白名单
4. **强烈建议** 给外部 host 配 `DestinationRule`,尤其是外部服务要求客户端 mTLS 的场景
5. **多 proxy 拓扑里**(mesh + 平台 egress + Blue Coat)**任何一层缺配置都会出问题**,必须 4 层都做配置 / 对齐
6. **Waypoint proxy**(Envoy-based 开源)+ HTTP CONNECT tunnel 是替代商业 HTTPS forward proxy 的可行路径,无需 vendor lock-in

**这三条(1+2+3)+ 一条(4)+ 一组(5)+ 一条(6)才是 Istio / CSM 实现你脑子里那个 "mesh entity" 概念的正确姿态。**

---

# References

- [Istio Sidecar reference](https://istio.io/latest/docs/reference/config/networking/sidecar/) — `workloadSelector` / `egress[].hosts` / "sidecar is not able to enforce an outbound traffic restriction" 引文来源
- [Istio AuthorizationPolicy reference](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — `Operation.hosts` "Must be used only with HTTP" 引文来源
- [Istio Concepts: Security](https://istio.io/latest/docs/concepts/security/) — mesh-wide / namespace-wide / workload-wide policy 层级定义
- [Istio Egress Control Task](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-control/) — `meshConfig.outboundTrafficPolicy.mode` ALLOW_ANY vs REGISTRY_ONLY 引文来源
- [Istio Authorization HTTP Task](https://istio.io/latest/docs/tasks/security/authorization/authz-http/) — 入门级 ALLOW/DENY 示例
- [Istio ServiceEntry reference](https://istio.io/latest/docs/reference/config/networking/service-entry/) — `MESH_EXTERNAL` / wildcard hosts / resolution NONE / DestinationRule 配套
- [Istio DestinationRule reference](https://istio.io/latest/docs/reference/config/networking/destination-rule/) — `TrafficPolicy.tls` / `connectionPool` / `tunnel` 字段定义
- [Istio Ambient Overview](https://istio.io/latest/docs/ambient/overview/) — "waypoint proxy is a deployment of the Envoy proxy" / "HTTP CONNECT-based traffic tunneling protocol called HBONE" 引文来源
- [Cloud Service Mesh: Authorization policy overview](https://cloud.google.com/service-mesh/docs/security/authorization-policy-overview) — CSM 视角 "Policy scope" 分类
- [Istio API source: `security/v1beta1/authorization_policy.pb.go`](https://github.com/istio/api/blob/master/security/v1beta1/authorization_policy.pb.go) — `Rule` / `Source` / `Operation` 结构体源码(L391 / L624 / L846 字段定义)
- [Istio API source: `networking/v1alpha3/sidecar.pb.go`](https://github.com/istio/api/blob/master/networking/v1alpha3/sidecar.pb.go) — `Sidecar` / `IstioEgressListener` 结构体源码
- [Istio API source: `networking/v1alpha3/destination_rule.pb.go`](https://github.com/istio/api/blob/master/networking/v1alpha3/destination_rule.pb.go) — `DestinationRule` / `TrafficPolicy` / `TunnelSettings` 结构体源码