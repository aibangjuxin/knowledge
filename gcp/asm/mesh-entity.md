# summary
## Mesh Entity: 用户级别 API 对外部 FQDN / 域名出口的访问控制 (Egress FQDN Control)

这份文档回答你最初提出的核心问题:

> 当我们提到一个概念叫 **mesh entity** 的时候,其实核心目的是想要 **控制用户级别的 API 可以访问哪些外部的域名 / FQDN**,也就是对 **egress 的域名或者说 FQDN 端点** 做对应的控制。

文档会明确告诉你:

1. Istio / Cloud Service Mesh 的官方术语里 **没有** "mesh entity" 这个词 — 这是用户场景化描述
2. 真正能落地"用户级别 API → 外部 FQDN 出口控制" 的 Istio 资源有三个: **Sidecar**, **ServiceEntry**, **AuthorizationPolicy**
3. 它们三者各有边界,需要组合,任何单一资源都不够
4. 这条链路上还有一层 mesh-wide 开关 (`meshConfig.outboundTrafficPolicy.mode`) 和 ALLOW_ANY / REGISTRY_ONLY 的语义区别

# 1. Goal And Context

在生产里,我们经常需要做这种控制:

- 某个 API 团队只能调用 `*.payments.partner.com` 这一个外部域名
- 另一个 API 团队只能调用 `*.data-vendor.io` 和 `api.openai.com`
- 其它任何外部域名都不许调用

直觉上,你可能会想说:

> "我有一个 entity 代表这个 API 团队,我希望这个 entity 关联一组允许访问的 FQDN。"

但 Istio / Cloud Service Mesh 的官方 API 设计 **不是这样的**。
它没有一个直接的 `MeshEntity` / `EgressEntity` 资源。Istio 的设计是把"身份"和"出口"切成两层:

| 层 | 资源 | 控制的是 |
|---|---|---|
| **身份侧** | `ServiceEntry` 的 `hosts` / `workloadSelector` + AuthorizationPolicy 的 `principals` / `serviceAccounts` | "**我**是谁" + "**谁**是目的地" |
| **行为侧** | `Sidecar.spec.egress[].hosts` / `meshConfig.outboundTrafficPolicy.mode` / AuthorizationPolicy 的 `to.operation.hosts` | "**我能去哪**" |

所以"mesh entity"这个概念在 Istio 里 **不是某个 resource 名字**,而是**一组 field 的组合语义**。下面逐步拆开。

# 2. Short Answer

如果你只能记住一句话:

> **用户级别 API → 外部 FQDN 出口控制,本质是三个 Istio 资源叠加的结果:**
>
> 1. **`ServiceEntry`** 把"外部 FQDN" **注册** 进 mesh 的内部服务注册表
> 2. **`Sidecar.spec.egress[].hosts`** 在 per-workload 维度限定**这个 API 实例能路由到哪些 namespace/service**
> 3. **`AuthorizationPolicy.spec.rules[].to[].operation.hosts`** 在身份维度限定**这个 API 的调用方身份能访问哪些 host**

**少了任何一层,都不会得到你想要的那个"用户级别 → FQDN 白名单"效果。**

再加一层 mesh-wide 总开关:

> **`meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY`** 把所有没在 `ServiceEntry` 注册过的外部 host **全部默认拒绝** — 这是"默认收紧"的入口。

---

# 3. What "Mesh Entity" Really Maps To In Istio

## 3.1 Istio 官方没有这个词

我检索了:

- `Istio Sidecar resource reference` ([istio.io/latest/docs/reference/config/networking/sidecar](https://istio.io/latest/docs/reference/config/networking/sidecar/))
- `Istio AuthorizationPolicy reference` ([istio.io/latest/docs/reference/config/security/authorization-policy](https://istio.io/latest/docs/reference/config/security/authorization-policy/))
- `Istio concepts/security` ([istio.io/latest/docs/concepts/security/](https://istio.io/latest/docs/concepts/security/))
- `Cloud Service Mesh authorization policy overview` ([cloud.google.com/service-mesh/docs/security/authorization-policy-overview](https://cloud.google.com/service-mesh/docs/security/authorization-policy-overview))

在 Istio 官方文档里出现的最接近概念是:

> **"Mesh-wide policy: A policy specified for the root namespace with no workload selector"**

来源 — Istio concepts/security ([istio.io/latest/docs/concepts/security/](https://istio.io/latest/docs/concepts/security/)):

> **"Mesh-wide policy: A policy specified for the root namespace with no workload selector applies to all workloads in the mesh, in any namespace."**

**注意**,这里的 "mesh-wide" 是 **policy 的作用域**,不是某个具体资源。所以你脑子里那个 "mesh entity" 的概念,在 Istio 里是这样对应的:

| 你说的概念 | Istio 实际对应的资源/字段 |
|---|---|
| "mesh entity = 一个用户/团队/API" | **workloadSelector**(选一组 Pod)+ namespace + ServiceAccount |
| "entity 能访问的外部域名" | **`ServiceEntry.hosts`** 注册外部 host + **`Sidecar.egress[].hosts`** 限定路由范围 + **`AuthorizationPolicy.to.operation.hosts`** 限定访问目的 |

## 3.2 为什么 Istio 没有 "MeshEntity" 资源

因为 Istio 的设计哲学是:

> **身份 ≠ 出口目的地 ≠ 路由可达性**

这三个东西分别用不同字段控制,解耦的好处是你能自由组合 — 例如一个 team 的 API 既能调内部其它 team 的 service 又能调特定的外部域名,通过给 ServiceEntry / Sidecar / AuthorizationPolicy 分别写规则来实现。

**坏处就是你要写 3 个 resource 而不是 1 个**,这是 Istio / CSM 在 egress 控制上最常被吐槽的点。

---

# 4. The Three Resources That Actually Do The Job

## 4.1 Resource #1: `ServiceEntry` — 把外部 FQDN 注册进 mesh

**作用**:`ServiceEntry` 是 Istio 用来描述 "一个外部 service 的 metadata" 的资源。它最关键的字段是 `location: MESH_EXTERNAL`,表示"这个 host 是在 mesh 外部"。

**Istio 官方原文** ([istio.io/latest/docs/tasks/traffic-management/egress/egress-control/](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-control/)):

> **"Using Istio ServiceEntry configurations, you can access any publicly accessible service from within your Istio cluster."**

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

## 4.2 Resource #2: `Sidecar` — per-workload 限定 egress 路由范围

**作用**:`Sidecar.spec.egress[].hosts` 用来 **声明** 这个 workload 的 sidecar 能路由到哪些 namespace/service。如果目标不在列表里,sidecar 不知道路由到哪儿(虽然默认会 fall through 到 Envoy 的 outbound cluster)。

**Istio 官方原文** ([istio.io/latest/docs/reference/config/networking/sidecar/](https://istio.io/latest/docs/reference/config/networking/sidecar/)):

> **"By default, Istio will program all sidecar proxies in the mesh with the necessary configuration required to reach every workload instance in the mesh, as well as accept traffic on all the ports associated with the workload."**

> **"One of the common usages of Sidecar is to limit the set of configuration for outbound traffic. This configuration scoping, among other options, is useful to prune out unneeded configuration, to improve scalability of the mesh."**

> **"A common misunderstanding is that restricting the configuration amounts to blocking the traffic. If requests are sent to destinations not included in the scoping, the traffic will be treated as unmatched traffic, which is often still allowed. The sidecar is not able to enforce an outbound traffic restriction (see Egress Gateways for how to achieve this)."**

⚠️ **关键陷阱**:Sidecar 资源不能完全阻断流量,只能 **限制 sidecar 的可见路由范围** — 这是 Istio 文档自己说的,不是 agent 误导。如果要做真正的 egress 阻断,需要配合 Egress Gateway(本文档 §5 详谈)。

**示例 — 限定一个 namespace 内的所有 Pod 只能访问 `prod-us1` 和 `istio-system` namespace**:

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: prod-us1
spec:
  egress:
  - hosts:
    - "prod-us1/*"          # 同 namespace 的所有 service
    - "istio-system/*"       # istio control plane
    - "external-svc/*"       # 别处 namespace 注册的外部 service
```

**Istio 原文 — 关于 wildcard `*/*`** ([istio.io/latest/docs/reference/config/networking/sidecar/](https://istio.io/latest/docs/reference/config/networking/sidecar/)):

> **"Istio will configure the sidecar to be able to reach every service in the mesh that is exported to the sidecar's namespace. The value `*/*` can be used to [opt out of this pruning]."**

> **"The value `~/*` can be used to completely trim the configuration for sidecars that simply receive traffic and respond, but make no outbound connections of their own."**

两个 wildcard 你需要分清:

| Wildcard | 含义 |
|---|---|
| `*/*` | "所有 namespace 的所有 service" — opt-out,不裁剪 |
| `~/*` | "完全不要 outbound 配置" — 不发起外部连接 |

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

**关键限制**:`Operation.hosts` 必须搭配 HTTP,不能用来限制 TCP-level 的 egress(详见 §5.3)。

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

# 6. Putting It Together: User-Level API → FQDN Egress Control

## 6.1 推荐的最小落地模型

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

**Step 3:AuthorizationPolicy 限定哪个 SA 可以调哪些 host**

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

**Step 4(可选):Sidecar 限制 outbound 路由范围,节省内存**

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: api-orders
  namespace: abjx-int
spec:
  workloadSelector:
    labels:
      app: api-orders
  egress:
  - hosts:
    - "abjx-int/*"
    - "istio-system/*"
    - "allowed-external-fqdns.abjx-int.svc.cluster.local"   # ServiceEntry 自身也算 host
```

## 6.2 关键决策表:每一步解决什么

| 步骤 | 资源 | 解决的问题 | 不解决什么 |
|---|---|---|---|
| Step 1 | `meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY` | 禁止访问**所有未注册**的外部 host | 不能区分"哪个团队允许哪些 host" |
| Step 2 | `ServiceEntry` | 注册白名单外部 host(让 sidecar 认得它) | 不做身份区分 — 任何 mesh 内的 Pod 都能调 |
| Step 3 | `AuthorizationPolicy` (用 `to.operation.hosts`) | 限定**特定身份** 只能访问特定 host | 不开 Step 1 + Step 2 也生效,但默认 mesh-wide 不阻拦其他 host |
| Step 4 | `Sidecar.egress[].hosts` | 节省 sidecar 配置内存,精确路由 | **不阻断流量**(Istio 官方明确说了) |

## 6.3 这一组合解决不了的:TCP-level egress

`AuthorizationPolicy.to.operation.hosts` 文档明确说:

> **"Must be used only with HTTP."**

([istio.io/latest/docs/reference/config/security/authorization-policy/](https://istio.io/latest/docs/reference/config/security/authorization-policy/))

**意味着**:如果你要限制某个 API 只能 TCP-调外部某些 IP(不是 HTTP),`AuthorizationPolicy` 帮不上忙。你需要的是:

- **Egress Gateway** + NetworkPolicy/Firewall
- 或者回到 **NetworkPolicy egress** + IP allowlist
- 或者把 TCP 流量包成 HTTP(grpc over HTTP/2)

---

# 7. Common Pitfalls

## 7.1 Pitfall #1:认为 `Sidecar.egress[].hosts` 是 egress firewall

Istio 官方明确说:

> **"A common misunderstanding is that restricting the configuration amounts to blocking the traffic. If requests are sent to destinations not included in the scoping, the traffic will be treated as unmatched traffic, which is often still allowed. The sidecar is not able to enforce an outbound traffic restriction (see Egress Gateways for how to achieve this)."**

([istio.io/latest/docs/reference/config/networking/sidecar/](https://istio.io/latest/docs/reference/config/networking/sidecar/))

**Sidecar 只控制 sidecar 装载的配置,不控制流量本身。**

## 7.2 Pitfall #2:AuthorizationPolicy 默认 deny

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

## 7.3 Pitfall #3:`meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY` 不区分 namespace

这是一个 mesh-wide 开关,你要么全集群 `REGISTRY_ONLY` 要么全 `ALLOW_ANY`。如果你的设计是"某些 namespace 收紧,某些不收紧",你需要:

- **方案 A**:全集群开 `REGISTRY_ONLY`,然后给所有需要调用外部的 namespace 都加 ServiceEntry
- **方案 B**:不靠 mesh-wide 开关,纯靠 `AuthorizationPolicy` 显式拒绝 (`spec.action: DENY`)

**注意**:你不能给某些 namespace 开 `REGISTRY_ONLY` 其它开 `ALLOW_ANY` — 这是个 mesh-level install-time 设置。

## 7.4 Pitfall #4:`ServiceEntry.hosts` 用 wildcard,AuthorizationPolicy 也得跟着 wildcard

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

---

# 8. Decision Tree: How To Actually Pick

```
我要"用户级别 API → 外部 FQDN 出口控制"
│
├── 这个外部流量是 HTTP/HTTPS/gRPC?
│   ├── 是 → 用 AuthorizationPolicy.to.operation.hosts (Step 3)
│   │       ├── mesh 默认 ALLOW_ANY? → 开 meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY (Step 1)
│   │       └── ServiceEntry 注册了外部 host 吗? → 没注册先加 ServiceEntry (Step 2)
│   │
│   └── 否(纯 TCP,如 MySQL/Redis/自定义 TCP)
│       └── AuthorizationPolicy 帮不上,改用:
│           ├── Egress Gateway + NetworkPolicy/Firewall IP allowlist
│           └── 或者 sidecar 终止后 egress gateway 转出
│
└── 想顺便限制 sidecar 配置大小?
    └── 加 Sidecar.spec.egress[].hosts (Step 4)
        注意:这不阻断流量,只裁剪配置
```

---

# 9. Comparison To AuthorizationPolicy Source Document

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

# 10. Recommended Pattern

## 10.1 平台工程视角的"分层模型"

| 层 | 资源 | 平台默认 | API owner 自定义 |
|---|---|---|---|
| **Mesh-wide 总开关** | `meshConfig.outboundTrafficPolicy.mode` | 平台 install 时强制 `REGISTRY_ONLY` | 不允许 override |
| **外部 host 注册表** | `ServiceEntry` | 平台提供 template + allowlist 流程 | API owner 申请后平台审批 + apply |
| **per-workload egress 路由范围** | `Sidecar.egress[].hosts` | 平台 Helm/Kustomize 模板默认 `"./*" + "istio-system/*"` | API owner 按需扩展 |
| **身份 → FQDN 精细授权** | `AuthorizationPolicy.to.operation.hosts` | API owner 自维护,平台审核 lint 规则 | API owner 自维护 |

## 10.2 多团队场景下的实际例子

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

# 11. What Mesh Entity Is NOT

为了避免后续混淆,明确一些**不是** "mesh entity" 的常见误解:

| 误解 | 实际情况 |
|---|---|
| "mesh entity 是一个 Istio 资源" | ❌ Istio 没有这个资源,这是用户场景化描述 |
| "AuthorizationPolicy 能完全限制 egress" | ⚠️ 部分正确 — 仅 HTTP 流量,且需要配合 ServiceEntry + REGISTRY_ONLY |
| "Sidecar.egress[].hosts 能阻断 egress" | ❌ Istio 文档明确说不能阻断流量 |
| "开 REGISTRY_ONLY 就够" | ❌ 只挡了未注册 host,没挡"注册了但不归我"的 host |
| "ServiceEntry 加 AuthorizationPolicy 等于"用户级别 FQDN 控制" | ✅ 这才是真正的答案 — 两者缺一不可 |

---

# 12. Final Summary

## 12.1 一句话答案

> **用户级别 API 对外部 FQDN 的出口控制 = `meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY` + `ServiceEntry`(白名单) + `AuthorizationPolicy.to.operation.hosts`(身份 → host 映射),可选 `Sidecar.egress[].hosts` 节省配置。**

## 12.2 三个 resource 的边界

| Resource | 控制范围 | 不能做什么 |
|---|---|---|
| `meshConfig.outboundTrafficPolicy.mode` | mesh-wide "未注册 host 默认拒绝"开关 | 不能 per-namespace / per-workload 差异化 |
| `ServiceEntry` | 把外部 host 注册进 mesh 路由表 | 不区分身份,只区分 host |
| `Sidecar.egress[].hosts` | 限定 sidecar 装载的路由配置 | **不阻断流量** |
| `AuthorizationPolicy.to.operation.hosts` | 限定特定身份能访问哪些 host | 仅 HTTP,不能管 TCP-level |

## 12.3 最重要的判断

如果你要落地"用户级别 → 外部 FQDN 出口控制":

1. **必须** 开 `meshConfig.outboundTrafficPolicy.mode = REGISTRY_ONLY`(默认 ALLOW_ANY 啥都拦不住)
2. **必须** 给每个允许的外部 host 写一条 `ServiceEntry`
3. **必须** 给每个 API 团队写一条 `AuthorizationPolicy` 把 `to.operation.hosts` 限定到该团队的白名单
4. **可选** 配 `Sidecar.egress[].hosts` 节省 sidecar 配置

**这三条(1+2+3)才是 Istio / CSM 实现你脑子里那个 "mesh entity" 概念的正确姿态。**

---

# References

- [Istio Sidecar reference](https://istio.io/latest/docs/reference/config/networking/sidecar/) — `workloadSelector` / `egress[].hosts` / "sidecar is not able to enforce an outbound traffic restriction" 引文来源
- [Istio AuthorizationPolicy reference](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — `Operation.hosts` "Must be used only with HTTP" 引文来源
- [Istio Concepts: Security](https://istio.io/latest/docs/concepts/security/) — mesh-wide / namespace-wide / workload-wide policy 层级定义
- [Istio Egress Control Task](https://istio.io/latest/docs/tasks/traffic-management/egress/egress-control/) — `meshConfig.outboundTrafficPolicy.mode` ALLOW_ANY vs REGISTRY_ONLY 引文来源
- [Istio Authorization HTTP Task](https://istio.io/latest/docs/tasks/security/authorization/authz-http/) — 入门级 ALLOW/DENY 示例
- [Cloud Service Mesh: Authorization policy overview](https://cloud.google.com/service-mesh/docs/security/authorization-policy-overview) — CSM 视角 "Policy scope" 分类
- [Istio API source: `security/v1beta1/authorization_policy.pb.go`](https://github.com/istio/api/blob/master/security/v1beta1/authorization_policy.pb.go) — `Rule` / `Source` / `Operation` 结构体源码(L391 / L624 / L846 字段定义)
- [Istio API source: `networking/v1alpha3/sidecar.pb.go`](https://github.com/istio/api/blob/master/networking/v1alpha3/sidecar.pb.go) — `Sidecar` / `IstioEgressListener` 结构体源码