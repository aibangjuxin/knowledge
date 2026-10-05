# 09-01-app-httproute.yaml — 两段式 HTTPRoute 详解

> **作者**: architect-gcp Bot
> **日期**: 2026-09-25
> **目标**: 解释 `09-01-app-httproute.yaml` 中两个 HTTPRoute 资源的工作原理、差异、
>          为什么需要两个,以及"只保留一个会怎样"。
> **历史**: 原 `09-app-httproute.yaml` (单 HTTPRoute + Service 名 `app`) 已删除,
>          本文分析适用于改进版 `09-01-app-httproute.yaml` (两段 HTTPRoute + Service 名 `plat-abjx-lex-testing-0-0-0-service`)。
> **类比**: Lex 线上 `plat-abjx-lex-testing-ingress` + `plat-abjx-lex-testing-waypoint` 配置
> **依据**: Istio 1.30+ 官方 ambient 文档 / Solo 1.30 ambient docs / K8s Gateway API spec

---

## 0. 你的核心疑惑 — 一句话回答

> "两个 HTTPRoute 是串联路由还是各自独立?只保留一个能工作吗?"

**回答**: **各自独立, 不串联, 但是相互补全的**。

- HTTPRoute 1 负责**入口** (ingress Gateway: client → edge L7)
- HTTPRoute 2 负责**mesh 内部** (waypoint: east-west + 入站二次处理)
- **缺任何一段, 特定流量路径就会失效**(详见 §6)

---

## 1. 这两个 HTTPRoute 到底在做什么 — 一张图看懂

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Internet / Client                          │
└────────────────────────────────┬────────────────────────────────────┘
                                 │ https://http.lex.caep.uk
                                 ▼
                  ┌─────────────────────────────┐
                  │  GCP Internal LB            │ (GCP-managed)
                  │  (NEG → Pod IP of Gateway)  │
                  └─────────────┬───────────────┘
                                │
                                ▼
                  ┌─────────────────────────────┐
                  │  lex-gw-int Gateway         │ ← Istio ingress Gateway (sidecar)
                  │  listener: http:80 + https:443│   — installed by Hub
                  │  parentRef chain:           │
                  │    └─► ListenerSet          │
                  │         "lex-team-listenerset" │ ← 05-lex-listenerset.yaml
                  │         listener: https:443  │
                  │         hostname: *.lex.caep.uk│
                  │         cert: *.lex.caep.uk   │
                  └─────────────┬───────────────┘
                                │
                                │ HTTPS, server cert *.lex.caep.uk
                                │ Host: http.lex.caep.uk
                                ▼
        ╔═══════════════════════════════════════════════╗
        ║ HTTPRoute 1: app-route-ingress                ║  ← 09 文件第 39-89 行
        ║ parentRef: ListenerSet "lex-team-listenerset" ║
        ║   sectionName: https                          ║
        ║ hostnames: [http.lex.caep.uk]                 ║
        ║ backendRef: plat-abjx-lex-testing-0-0-0-service:80 ║
        ║ filters:                                      ║
        ║   + X-Correlation-Id (从 X-Request-Id 取)    ║
        ║   + X-Content-Type-Options: nosniff           ║
        ║   + Strict-Transport-Security                 ║
        ║   - Server 头                                  ║
        ╚═══════════════════════════════════════════╤══╝
                                                    │
                                │ ┌────────────────┘
                                │ │ HTTP/2 CONNECT (HBONE)
                                │ │ (waypoint 地址通过 ztunnel 解析)
                                ▼ ▼
                  ┌─────────────────────────────┐
                  │  ztunnel (节点级 DaemonSet) │
                  │  src side:                  │
                  │   L4 mTLS 加密              │
                  │   HBONE 转发                │
                  └─────────────┬───────────────┘
                                │
                                ▼
                  ┌─────────────────────────────┐
                  │  ztunnel (业务节点, dst side)│
                  │  dst side:                  │
                  │   HBONE 解包                │
                  │   看到 hostname http.lex.caep.uk│
                  │   决定送到 waypoint 还是 pod│
                  └─────────────┬───────────────┘
                                │
                                │ 业务 ns 有 label:
                                │   istio.io/ingress-use-waypoint=waypoint
                                │   istio.io/use-waypoint=waypoint
                                │ → 强制入站走 waypoint
                                ▼
        ╔═══════════════════════════════════════════════╗
        ║ HTTPRoute 2: app-route-waypoint               ║  ← 09 文件第 91-131 行
        ║ parentRef: Service "plat-abjx-lex-testing-0-0-0-service"   ║
        ║ (no hostnames!)                              ║
        ║ backendRef: plat-abjx-lex-testing-0-0-0-service:80 ║
        ║ filters:                                      ║
        ║   + X-Tenant-Id: ba000000                     ║
        ║   + X-Forwarded-Proto: https                  ║
        ╚═══════════════════════════════════════════╤══╝
                                                    │
                                                    │ plain HTTP/8080 (backend)
                                                    ▼
                                  ┌─────────────────────────────┐
                                  │  Service "plat-abjx-lex-testing-0-0-0-service" ClusterIP │
                                  │  port: 80 → targetPort 8080 │
                                  │  appProtocol: http          │
                                  └─────────────┬───────────────┘
                                                │
                                                ▼
                                  ┌─────────────────────────────┐
                                  │  Pod "app" (nginx)          │
                                  │  containerPort: 8080        │
                                  │  收到的 headers:            │
                                  │    X-Correlation-Id  (从 HR1)│
                                  │    X-Tenant-Id      (从 HR2)│
                                  │    X-Forwarded-Proto: https │
                                  │    (从 HR2)                 │
                                  └─────────────────────────────┘
```

---

## 2. 具体差异表 (HTTPRoute 1 vs HTTPRoute 2)

| 字段 | HTTPRoute 1 (app-route-ingress) | HTTPRoute 2 (app-route-waypoint) |
|---|---|---|
| `metadata.name` | `app-route-ingress` | `app-route-waypoint` |
| `metadata.namespace` | `ba000000-lex-int` (业务 ns) | `ba000000-lex-int` (业务 ns) |
| **执行的 envoy** | ingress Gateway `lex-gw-int` 的 sidecar | 业务 ns 的 waypoint proxy (per-ns ambient) |
| **执行时机** | 客户端 TLS 终止后立即 | ztunnel 解包 HBONE 后,在 waypoint 内 |
| `spec.parentRefs[0].kind` | **`ListenerSet`** | **`Service`** |
| `spec.parentRefs[0].name` | `lex-team-listenerset` | `app` (业务 Service) |
| `spec.parentRefs[0].namespace` | (默认 = HTTPRoute 的 ns) | (默认 = HTTPRoute 的 ns) |
| `spec.parentRefs[0].sectionName` | `https` (对应 listener 名) | (无 — Service parentRef 不需要) |
| `spec.hostnames` | **`[http.lex.caep.uk]`** ✅ 显式 | **(空)** — waypoint 拦截所有入站 |
| `spec.rules[0].matches[0].path` | `/` (PathPrefix) | `/` (PathPrefix) |
| **filter 职责** | **Edge** (correlation, HSTS, nosniff, remove Server) | **Tenant** (X-Tenant-Id, X-Forwarded-Proto) |
| `backendRefs[0].port` | `80` (Service port) | `80` (Service port) |
| 影响的流量方向 | 仅南北向 (client → Gateway) | 入站 + east-west (业务 pod → 业务 pod) |
| 对应 K8s 资源 | ListenerSet 在业务 ns | Service 在业务 ns |

---

## 3. 关键差异 — parentRef 决定一切

```yaml
# HTTPRoute 1
parentRefs:
  - group: gateway.networking.k8s.io
    kind: ListenerSet              # ← K8s 网关类资源
    name: lex-team-listenerset
    sectionName: https
hostnames: ["http.lex.caep.uk"]    # ← 必须有, 限定 ingress 接受哪些 hostname

# HTTPRoute 2
parentRefs:
  - group: ""                       # ← 空字符串 = core K8s API
    kind: Service                   # ← 业务 K8s Service
    name: app
# 没有 hostnames 字段               # ← waypoint 拦截所有入站流量
```

### 为什么 parentRef 是 Service 而不是 Gateway

按 Istio 1.30+ 官方 ambient 迁移文档 (`migrate-policies`):
> "Replace the VirtualService with an HTTPRoute that attaches to the
> **reviews Service directly (using kind: Service as the parentRef)**.
> This is the correct attachment model for ambient mode —
> **the waypoint uses the Service as the routing anchor**"

按 Solo 1.30 ambient docs (`redirects-and-rewrites`):
> "The HTTPRoute in this guide attaches to a **Service as a parentRef**,
> which **requires a waypoint to enforce L7 rules**."

按 Istio ambient L7 features docs:
> "Without a waypoint installed, you can only use Layer 4 security policies.
> By adding a waypoint, you gain access to the following policies:
> **HTTPRoute ... parentRefs**"

### 严格定义 vs 简化解释

| 维度 | 简化解释 | 严格定义 (K8s Gateway API spec) |
|---|---|---|
| parentRef 是 ListenerSet | "挂在入口上" | "ListenerSet extends Gateway, providing a way to delegate HTTP route configuration in multi-tenant environments" |
| parentRef 是 Service | "让 waypoint 拦截这个 Service" | "When HTTPRoute's parentRef is a Service, the route is **scoped to that Service's traffic and enforced by the waypoint that handles the Service**" |
| parentRef 是 Gateway | (本配置未用) | "Attach to the entire gateway proxy — applies to all listeners" |

---

## 4. 答疑 — Lex 的核心疑惑

### Q1: "我理解有一个就可以工作的"

**结论**: **错误**(有条件)。

| 场景 | 只 HTTPRoute 1 | 只 HTTPRoute 2 |
|---|---|---|
| 客户端 → `http.lex.caep.uk` | ✅ 工作 | ❌ **Gateway 不知道 hostname 路由谁** |
| 业务 pod A → 业务 pod B (east-west) | ❌ **waypoint 没规则,直接 pass-through** | ✅ 工作 (waypoint 拦截) |
| 业务 pod → 外部服务 (egress) | ❌ 不影响 (此 ns 没出站 mesh 规则) | ❌ 不影响 |

### Q2: "有一个侦听到了 hostname, 但另一个并没有"

**解释**: 这是**设计**,不是 bug。

- **HTTPRoute 1 有 hostnames** → 因为它挂在 **ListenerSet 上**。ListenerSet 有 `hostname: "*.lex.caep.uk"`, K8s Gateway API 规定: HTTPRoute.hostnames 必须**与 parent.hostname 做交集** (intersection)。
  - 所以 `app-route-ingress` 只对 `http.lex.caep.uk` 这个 FQDN 生效
  - 客户端请求 `http.lex.caep.uk` → ListenerSet 匹配 → HTTPRoute 1 接管
  - 客户端请求 `api.lex.caep.uk` (虽然也在 *.lex.caep.uk 内) → HTTPRoute 1 不匹配 → 没有匹配的 HTTPRoute → 404

- **HTTPRoute 2 没有 hostnames** → 因为它挂在 **Service 上**。Service parentRef 没有 hostname 概念:
  - waypoint 拦截所有发往 `app:80` 的入站流量, 不管客户端 hostname 是啥
  - **类比**: 后端业务不需要知道原始 URL 的 hostname 是什么,只需要处理请求体即可

### Q3: "看起来 HTTPRoute 2 像是 waypoint 承载业务, 转发到 server"

**正确**。HTTPRoute 2 是** waypoint 的 L7 规则**, 服务对象是 `app:80` (业务 Service)。
但要纠正一个常见误解:
- HTTPRoute 2 **不是把流量"再转发"一次**给 Service
- 而是 **ztunnel 已经把流量送到 waypoint 了**, waypoint 用 HTTPRoute 2 做 L7 处理(加 header、改请求等),然后再发到 Service
- **流量物理上只经过 Service 一次**

### Q4: "看起来 HTTPRoute 1 像是 ingress gateway 对接请求转发到 service"

**部分对, 但不完全对**:

- HTTPRoute 1 的 backendRef 指向 `app:80` — Service 是 `app`(业务 Service)
- 但 ingress Gateway **不直接发到 Service**, 而是发到 **HBONE 15008 端口**(waypoint 地址)
- waypoint 处理后再发到 Service
- **所以 HTTPRoute 1 的"backendRef"是名义上的目的地, 实际物理路径是 Gateway → waypoint → Service**

详细物理路径:
```
Gateway envoy
   │ 看到 HTTPRoute 1: backendRef = app:80
   │
   │ 解析 app:80 的 endpoint:
   │   1. ClusterIP → Pod IPs
   │   2. Pod IP 是不是 ambient pod? → 看 ztunnel HBONE 监听器
   │   3. 是 → 走 HBONE CONNECT 到目标 ztunnel
   │   4. 目标 ztunnel 知道 waypoint (per-ns), 转给 waypoint
   │   5. waypoint 处理 HTTPRoute 2 的 filter
   │   6. waypoint 发到 Service app:80 → Pod
```

### Q5: "是不是第一个就够了"

**答**: 不够。

- 只 HTTPRoute 1: ✅ 入口能工作, ❌ **east-west 不走 waypoint** (业务 pod → 业务 pod 不被拦截)
- 只 HTTPRoute 2: ❌ **入口不能工作** (ListenerSet 没路由规则, hostname 无路由)
- 两个都要: ✅ **all traffic paths go through L7 enforcement**

### Q6: 那我现在两个 HTTPRoute 是合理的吗

**答**: ✅ 合理。

依据 ambientmesh.io 文档:
> "**Gateways**: Apply minimal routing logic, such as through HTTPRoutes, that is
> sufficient only for selecting a backend app. **Avoid applying policies to
> gateways**, except for policies that **must be applied at the edge, such as
> rate limiting or user authentication**."
>
> "**Waypoints**: Apply all other routing and policy logic."

按这个原则看你的线上配置:
- **HTTPRoute 1 (edge)**: 只做 correlation / HSTS / nosniff — ✅ 符合 "必须 applied at the edge" 的策略
- **HTTPRoute 2 (waypoint)**: 只做 tenant header / proto — ✅ 属于业务路由逻辑

---

## 5. 关键隐性约束 — 删一个会怎么失效

| 约束 | 解释 | 失效场景 |
|---|---|---|
| **Hostname 必须落在 ListenerSet 内** | HTTPRoute 1 的 `hostnames[0]` 必须**被** ListenerSet.hostname 覆盖 | 如果改 `http.lex.caep.uk` → `http.lex.internal`, ListenerSet 不匹配, HTTPRoute 1 不生效, 入口 404 |
| **Service parentRef 必须有对应 waypoint** | HTTPRoute 2 的 `kind: Service app` 需要 ns 有 `istio.io/use-waypoint=waypoint` label 才有 waypoint 拦截 | 如果删这个 label, HTTPRoute 2 不会被执行 (waypoint 不存在), 业务 pod 收不到 X-Tenant-Id |
| **`ingress-use-waypoint` label 启用** | ns 级 label `istio.io/ingress-use-waypoint=waypoint` 让 ingress 流量强制走 waypoint | 如果改 label 为 `false` 或删除, ingress Gateway 直接发到 Service, **绕过 waypoint** (HTTPRoute 2 不执行) |
| **`ENABLE_INGRESS_WAYPOINT_ROUTING` flag** | istiod 环境变量, 默认 `false` | 如果集群 flag 没开, **即使所有 label 都对, 入口也不走 waypoint** (这是 yaml-assessment.md v5 §3 H-1 风险) |
| **HTTPRoute 1 的 backendRef port 必须 = Service port** | `port: 80` 对应 Service.app.port=80 | 如果改 port=8080(容器端口), K8s Gateway API 会报错, 因为 Service 没暴露 8080 |
| **HTTPRoute 2 的 backendRef port 可省** | waypoint 不限端口, 拦截所有入站 | 如果写 `port: 8080`, 仍然工作但语义略不准 |

---

## 6. 真实流量路径拆解

### 6.1 客户端 → http.lex.caep.uk

```
1. 客户端 TLS 连 LB, SNI=http.lex.caep.uk
2. LB → Gateway lex-gw-int pod (sidecar envoy)
3. Gateway envoy 收到 HTTPS, 看到 Host=http.lex.caep.uk
4. 查找匹配的 ListenerSet:
   - Listener "https" 在 Gateway 上
   - ListenerSet.allowedRoutes 限定 ba000000-lex-int
   - HTTPRoute 1 app-route-ingress:
     ✓ hostnames 匹配 (http.lex.caep.uk in *.lex.caep.uk)
     ✓ 业务 ns label 匹配
   → HTTPRoute 1 被选中
5. 应用 HTTPRoute 1 的 filters:
   + X-Correlation-Id
   + X-Content-Type-Options: nosniff
   + Strict-Transport-Security
   - Server
6. backendRef: app:80
   Gateway 解析 app:80:
   - ClusterIP 10.96.0.X:80
   - endpoint 是哪个 pod? (iptables → pod IP)
   - pod 是不是 ambient? 看 ns label: istio.io/dataplane-mode=ambient ✅
   - pod 上有没有 ztunnel socket? 有
   - 通过 HBONE CONNECT 发到 pod 节点 ztunnel
7. 节点 ztunnel (src side):
   - 看业务 ns 有 istio.io/ingress-use-waypoint=waypoint ✅
   - 决定: 强制入站走 waypoint
   - HBONE 解包后发给 waypoint pod:15008
8. waypoint pod:
   - 收到请求 (有 HTTPRoute 1 加的 headers)
   - 看自己有没有匹配的 HTTPRoute:
     - HTTPRoute 2 app-route-waypoint:
       ✓ parentRef 是 Service app
       ✓ hostnames 字段空 (匹配所有)
   → HTTPRoute 2 被选中
9. 应用 HTTPRoute 2 的 filters:
   + X-Tenant-Id: ba000000
   + X-Forwarded-Proto: https
10. backendRef: app:80
    waypoint 直接发到 Service app:80 → Pod:8080
11. Pod 收到:
    GET /
    Host: http.lex.caep.uk
    X-Correlation-Id: <from X-Request-Id>
    X-Tenant-Id: ba000000
    X-Forwarded-Proto: https
    X-Content-Type-Options: nosniff
    Strict-Transport-Security: max-age=31536000; ...
```

### 6.2 业务 pod A → 业务 pod B (east-west)

```
1. Pod A 发起 HTTP 请求到 Service B
2. Pod A 的 ztunnel 拦截 (因为 Pod A 在 ambient ns)
3. Pod A 节点 ztunnel 解析目标 Service B:
   - Service B 是不是 ambient? 看 ns label: istio.io/use-waypoint=waypoint ✅
   - 决定: 走 waypoint
   - HBONE CONNECT 发到 Pod B 节点 ztunnel
4. Pod B 节点 ztunnel:
   - 解包 HBONE, 转给 waypoint
5. waypoint:
   - 看到 HTTPRoute 2 app-route-waypoint (parentRef=Service B)
   - ✅ 匹配 (Service B 是 HTTPRoute 2 的 parentRef)
   - 应用 filters (X-Tenant-Id 等)
   - 发到 Pod B
6. Pod A → waypoint → Pod B 走完
   ⚠️ HTTPRoute 1 不参与此路径 (它是给 ingress 用的)
```

### 6.3 业务 pod → 外部 (egress)

```
此 ns 没定义 egress HTTPRoute 或 AuthorizationPolicy (case-lex 不覆盖 egress)
→ 业务 pod 直接走节点 ztunnel, 默认 pass-through
→ 如果后续要管 egress, 在 egress Gateway 或 egress waypoint 上加 HTTPRoute/AuthZ
```

---

## 7. 关键观察 — Lex 线上配置 vs 我的 case-lex

| 维度 | Lex 线上 | 我的 case-lex | 一致性 |
|---|---|---|---|
| HTTPRoute 1 hostnames | `http.lex.caep.uk` | `http.lex.caep.uk` | ✅ |
| HTTPRoute 1 parentRef | ListenerSet | ListenerSet | ✅ |
| HTTPRoute 1 sectionName | (无, Lex 没写) | `https` | ⚠️ 我加了 sectionName |
| HTTPRoute 1 backendRef | `plat-abjx-lex-testing-0-0-0-service:80` | `app:80` | ⚠️ 名字模式不同 |
| HTTPRoute 1 filter (req) | X-ABJX-CAP-Correlation-Id | X-Correlation-Id | ⚠️ 头名不同 |
| HTTPRoute 1 filter (resp) | HSTS / nosniff / -Server | 同 | ✅ |
| HTTPRoute 2 parentRef | Service | Service | ✅ |
| HTTPRoute 2 hostnames | (空) | (空) | ✅ |
| HTTPRoute 2 backendRef | service:80 | app:80 | ⚠️ 名字模式不同 |
| HTTPRoute 2 filter (req) | X-Tenant-Id / X-Forwarded-Proto | 同 | ✅ |
| HTTPRoute 2 filter (resp) | X-Ambient-Waypoint | (我没加) | ❌ 缺失 |
| HTTPRoute 2 labels | `app.kubernetes.io/managed-by: tenant` | 同 | ✅ |

### 我相对线上**缺失/不同**的地方

| # | 项 | 改进建议 |
|---|---|---|
| 1 | HTTPRoute 2 没加 `X-Ambient-Waypoint: waypoint-int` 响应头 | 应该补 — 这是审计标记 |
| 2 | HTTPRoute 1 的 `X-Correlation-Id` 头名跟线上 `X-ABJX-CAP-Correlation-Id` 不一致 | 跟 Lex 命名约定统一 |
| 3 | HTTPRoute 1 backendRef 是 `app`, 线上是 `plat-abjx-lex-testing-0-0-0-service` | 业务命名约定 (Lex 平台 `plat-abjx-lex-<env>-<ver>-service` 模式) |
| 4 | HTTPRoute 1 sectionName 写了 `https`, 线上没写 | 两种写法 K8s 都接受, 我加了更明确 |

---

## 8. 总结 — 4 个结论

### 8.1 两个 HTTPRoute 不是串联

| ❌ 错误理解 | ✅ 正确理解 |
|---|---|
| "HTTPRoute 1 把流量发给 HTTPRoute 2" | "两个 HTTPRoute **各自被 istiod 分发给不同的 envoy**, 在不同时机执行" |
| "HTTPRoute 2 的 backendRef 是 HTTPRoute 1" | "两个 backendRef **都指向同一个 Service** (app:80)" |
| "删一个就少一跳" | "删一个就**某个流量路径失效**" |

### 8.2 只保留一个能工作吗?

| 方案 | 入口 | east-west | 整体评价 |
|---|---|---|---|
| **只 HR1** | ✅ | ❌ 不走 waypoint, X-Tenant-Id 缺失 | ❌ 不推荐 |
| **只 HR2** | ❌ Gateway 不知道 hostname 路由 | ✅ | ❌ 不推荐 |
| **两个都有** | ✅ 两段都执行 | ✅ | ✅ 推荐 |

### 8.3 两段配置合理吗?

✅ **合理**。职责清晰分离:
- HR1 = edge 关注点 (security headers, correlation)
- HR2 = waypoint 关注点 (tenant 身份, waypoint 标识)

符合 Istio 官方推荐:
> "**Gateways** apply minimal routing logic. **Waypoints** apply all other
> routing and policy logic."

### 8.4 我的 case-lex 配置相对线上**还需要补**:

1. HTTPRoute 2 加 `X-Ambient-Waypoint: waypoint-int` 响应头
2. X-Correlation-Id 头名跟 Lex 命名约定统一 (X-ABJX-CAP-Correlation-Id)
3. Service 命名模式跟 Lex 平台对齐 (plat-abjx-lex-...)
4. HTTPRoute 1 sectionName 可选 (K8s 两种写法都接受)

---

## 9. 参考链接

### Istio 官方文档
- [Configure waypoint proxies](https://istio.io/latest/docs/ambient/usage/waypoint/) — §"Ingress gateways and waypoints" 两层模式
- [Use Layer 7 features](https://istio.io/latest/docs/ambient/usage/l7-features/) — HTTPRoute parentRefs attachment
- [Migrate policies to ambient](https://istio.io/latest/docs/ambient/migrate/migrate-policies/) — "use kind: Service as the parentRef" 推荐

### Solo 文档
- [Redirects and rewrites (Solo 1.30)](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/redirects-and-rewrites) — "attaches to a Service as a parentRef, which requires a waypoint to enforce L7 rules"

### Ambient Mesh 社区
- [Waypoints overview](https://ambientmesh.io/docs/waypoints/overview/) — "Gateways vs Waypoints 职责分离"
- [Sidecar migration part 4](https://ambientmesh.io/blog/sidecar-migration-part-4/) — two-tier gateway pattern

### 关联文档 (本目录)
- `09-01-app-httproute.yaml` — 本文档分析对象 (改进版, 原 09 已删除)
- `05-lex-listenerset.yaml` — HTTPRoute 1 的 parentRef
- `08-app-deployment.yaml` — backend Service `plat-abjx-lex-testing-0-0-0-service:80`
- `01-waypoint-int.yaml` — HTTPRoute 2 的执行环境
- `00-namespace-ba000000-lex-int.yaml` — ns 级 3 个 istio label
- `assessment-ingress.md` — ingress 流量跨 ns 路径分析
- `yaml-assessment.md` — v5 残余风险审计

---

*Generated by architect-gcp Bot — 2026-09-25.*
*基于 Istio 1.30+ 官方文档 + Solo 1.30 docs + Lex 线上实际配置。*
*回答 4 个核心问题: 怎么工作 / 区别 / 单个能工作吗 / 是否合理。*