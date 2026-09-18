# `parametersRef` vs `targetRefs` — 概念澄清(都是 "Refs" 但完全不同的东西)

> **TL;DR**:
> - **两者都是 K8s Gateway API / Istio 里的"引用机制"**,**但语义完全不同**,不是同一资源
> - **`parametersRef`** = **"实现特定配置"**(implementation-specific config)**指向** — "我要哪份 ConfigMap / CRD 来给我个性化配置"
> - **`targetRefs`** = **"策略作用目标"**(policy attachment target)**反向指向** — "我这个策略要作用到哪些 Service / Gateway 上"
> - **域归属**:**两者都是 K8s Gateway API 标准**,不是某个 ingress gateway 专属;但 `targetRefs` 在 Istio mesh policy 里被扩展支持
> - **本场景现状**:`k8s-gateway/` 里用 `parentRefs` + `backendRefs`,还没用 `parametersRef` / `targetRefs`(后者将在 ambient AuthZ 引入时使用)

---

## 0. 这篇文档要解决什么

> Lex 通读 `k8s-gateway-ambient/` 14 篇文档后,在 `PERSONAL-FOCUS-LIST.md` 关注 1.2 提到:
> "AuthorizationPolicy / PeerAuthentication ==> ambient 下推荐 targetRefs 代替 selector"
>
> 但同时在 `06-policy-capabilities.md` 和 `12-revision-canary-mtls-compat.md` 里又出现 `parametersRef` 字段(BackendTLSPolicy / Mesh / Gateway 等资源)。
>
> 两个字段**名字相似、英文都是 "Refs"、都跟 "引用"有关** — **容易混淆**。

**本文档的目标**:
1. 澄清 `parametersRef` 与 `targetRefs` **不是同一种东西**(虽然长得像)
2. 给出**完整出现位置矩阵**(它们在哪些 K8s / Gateway API / Istio 资源里出现)
3. 给出**对比表 + 真实 YAML 示例**,让概念看得见摸得着
4. 标注**本场景当前用法**与**未来引入路径**

---

## 1. 一句话定位(简化版)

| 字段 | 一句话定位 | 比喻 |
|---|---|---|
| **`parametersRef`** | "实现特定配置" 的引用 | **配置模板** — "我要用哪个 ConfigMap / CRD 来配置我" |
| **`targetRefs`** | "策略作用目标" 的引用 | **目标清单** — "我这个策略要作用到哪些 Service / Gateway 上" |

> **严格定义出处**:
> - `parametersRef`: "ParametersRef is an optional reference to a resource that contains implementation-specific configuration for this resource." — [K8s Gateway API spec](https://gateway-api.sigs.k8s.io/reference/api-spec/)
> - `targetRefs`: "targetRefs identifies API object(s) to apply this policy to." — [K8s Gateway API spec](https://gateway-api.sigs.k8s.io/reference/api-spec/)

---

## 2. 严格定义 vs 简化解释(双栏)

### 2.1 `parametersRef`

| 简化解释 | 严格原话(一手来源) |
|---|---|
| **"我想引用一份 ConfigMap / CRD 当我的配置"** | "`ParametersRef` is an optional reference to a resource that contains implementation-specific configuration for this resource. ParametersRef can reference a standard Kubernetes resource, i.e. ConfigMap, or an implementation-specific custom resource. The resource can be cluster-scoped or namespace-scoped." — [K8s Gateway API spec](https://gateway-api.sigs.k8s.io/reference/api-spec/) |
| **"GEP-1867 引入,Gateway 也支持了"** | "A new `parametersRef` field has been added to `Gateway.spec.infrastructure`. This allows configuration of arbitrary implementation-specific parameters. This field previously existed only on `GatewayClass`." — [PR #2924](https://github.com/kubernetes-sigs/gateway-api/pull/2924) |
| **"如果指向的资源不存在/格式错,该资源会被 reject"** | "If the referent cannot be found, refers to an unsupported kind, or when the data within that resource is malformed, the [resource] MUST be rejected with the 'Accepted' status condition set to 'False' and an 'InvalidParameters' reason." — K8s Gateway API spec |
| **"Istio 常用 ConfigMap 加 label `gateway.istio.io/defaults-for-class` 兜底"** | "Istio's current Gateway API integration configures defaults for all Gateways in a class with a ConfigMap labeled `gateway.istio.io/defaults-for-class: <gateway class name>` in the root namespace." — [Istio docs](https://istio.io/latest/docs/) |

### 2.2 `targetRefs`

| 简化解释 | 严格原话(一手来源) |
|---|---|
| **"我这个策略要绑哪些 Service / Gateway / GatewayClass"** | "`targetRefs` identifies API object(s) to apply this policy to. Currently, Backends (a grouping of like endpoints such as Service, ServiceImport, or any implementation-specific backendRef) are the only valid API target references." — [K8s Gateway API spec](https://gateway-api.sigs.k8s.io/reference/api-spec/) |
| **"Istio AuthorizationPolicy 用 `targetRefs` 绑 waypoint / Service / GatewayClass"** | "Currently, the following resource attachment types are supported: `kind: Gateway` with `group: gateway.networking.k8s.io` in the same namespace; `kind: GatewayClass` with `group: gateway.networking.k8s.io` in the root namespace; `kind: Service` with `group: ""` or `group: "core"` in the same namespace. This type is only supported for waypoints; `kind: ServiceEntry` with `group: networking.istio.io` in the same namespace." — [Istio AuthorizationPolicy](https://istio.io/latest/docs/reference/config/security/authorization-policy/) |
| **"targetRefs 与 selector 互斥,同一 spec 二选一"** | "At most one of `selector` and `targetRefs` can be set." — [Istio AuthorizationPolicy](https://istio.io/latest/docs/reference/config/security/authorization-policy/) |
| **"用 targetRefs 时必须打 `istio.io/rev` label 防止老控制面误读"** | "If you are using the `targetRefs` field in a multi-revision environment with Istio versions prior to 1.22, it is highly recommended that you pin the policy to a revision running 1.22+ via the `istio.io/rev` label." — [Istio AuthorizationPolicy](https://istio.io/latest/docs/reference/config/security/authorization-policy/) |

---

## 3. 完整出现位置矩阵

> 这是本节核心 — 让"两个 Refs 出现在哪些资源里"一目了然。

### 3.1 `parametersRef` 出现在哪些资源

| 资源类型 | 路径 | 资源作用域 | 指向对象 | 状态 |
|---|---|---|---|---|
| **K8s Gateway API `GatewayClass`** | `spec.parametersRef` | cluster-scoped | 任意 ConfigMap / CRD | Stable(已有)|
| **K8s Gateway API `Gateway`** | `spec.infrastructure.parametersRef` | namespace-scoped | 任意 ConfigMap / CRD | **Stable(1.3+ / PR #2924 引入)** |
| **K8s Gateway API `Mesh`** | `spec.parametersRef` | namespace-scoped | 任意 ConfigMap / CRD | Experimental(GEP-1867)|
| **K8s Gateway API `BackendTLSPolicy`** | 无(此资源没有 parametersRef) | - | - | - |
| **Istio CRD** | 部分 Istio 自定义 CRD 也用 parametersRef | varies | varies | Implementation-specific |

> 来源:[K8s Gateway API reference](https://gateway-api.sigs.k8s.io/reference/api-spec/) + [PR #2924](https://github.com/kubernetes-sigs/gateway-api/pull/2924)

### 3.2 `targetRefs` 出现在哪些资源

| 资源类型 | 路径 | 作用目标 | 状态 |
|---|---|---|---|
| **K8s Gateway API `BackendTLSPolicy`** | `spec.targetRefs` | Service / Gateway(Implementation-specific) | Standard(1.5+) |
| **K8s Gateway API 其他 Policy** | `spec.targetRefs` | Service / Gateway | Stable(1.5+) |
| **Istio `AuthorizationPolicy`** | `spec.targetRefs` | Gateway / GatewayClass / Service / ServiceEntry | Istio 自定义扩展,1.22+ 推荐用法 |
| **Istio `PeerAuthentication`** | 不支持 targetRefs(只用 selector)| - | sidecar only |
| **Istio `Telemetry`** | 部分版本支持 targetRefs | 资源 | Implementation-specific |
| **K8s Gateway API `ReferenceGrant`** | **完全不同的含义**(ReferenceGrant 用 `from` + `to` 字段,不叫 targetRefs) | - | 见 §5 |

> 来源:[Istio AuthorizationPolicy reference](https://istio.io/latest/docs/reference/config/security/authorization-policy/) + [K8s Gateway API reference](https://gateway-api.sigs.k8s.io/reference/api-spec/)

### 3.3 容易混淆的"邻居字段"

| 字段 | 域 | 是什么 | 与本文两个 Refs 的关系 |
|---|---|---|---|
| **`parentRefs`** | K8s Gateway API `HTTPRoute / GRPCRoute / TLSRoute / TCPRoute / UDPRoute` | "我这个路由要附到哪些 Gateway / ListenerSet 上" | **完全不同** — `parentRefs` 是"我的父资源" |
| **`backendRefs`** | K8s Gateway API `HTTPRoute.rules[].backendRefs` | "我这个路由规则把流量转到哪些后端 Service" | **完全不同** — `backendRefs` 是"我的目标服务" |
| **`refs`**(ReferenceGrant) | K8s Gateway API `ReferenceGrant.spec.from` + `.to` | "哪个 ns 的哪个资源可以引用哪个 ns 的哪个资源" | **完全不同** — ReferenceGrant 用 `from/to`,不是 targetRefs |
| **`selector`** | Istio `AuthorizationPolicy.spec.selector` | "匹配哪些 workload pod"(sidecar 时代主流) | **与 targetRefs 互斥** — 同 spec 只能二选一 |

> ⚠️ 你 `k8s-gateway/` 里已经在用的就是 **`parentRefs` + `backendRefs`**(都是 HTTPRoute 上的字段)。这两个与 `parametersRef` / `targetRefs` 完全无关。

---

## 4. 真实 YAML 示例对比(让概念看得见)

### 4.1 `parametersRef` 示例 — GatewayClass 用 EnvoyProxy CRD 自定义配置

```yaml
# Envoy Gateway 的 GatewayClass 用 parametersRef 指向 EnvoyProxy CRD
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:                    # ← parametersRef
    group: gateway.envoyproxy.io
    kind: EnvoyProxy                # ← 指向另一个 CRD
    name: default-proxy-config
    namespace: envoy-gateway-system
---
# 被引用的 EnvoyProxy CRD(实现特定)
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: default-proxy-config
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
```

**含义解读**:
- `GatewayClass` 是**模板** — "我是哪种 Gateway 类"
- `parametersRef` 指向一份**实现特定配置**(`EnvoyProxy` CRD)
- `EnvoyProxy` CRD 是 Envoy Gateway 自定义的,**不是 K8s 标准** — 这就是"implementation-specific config"的含义

### 4.2 `parametersRef` 示例 — Gateway 用 ConfigMap 兜底

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
  namespace: default
spec:
  gatewayClassName: istio
  infrastructure:
    parametersRef:                  # ← Gateway 上的 parametersRef(PR #2924 引入)
      group: ""
      kind: ConfigMap
      name: my-gateway-config       # ← 指向同一 ns 的 ConfigMap
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-gateway-config
  namespace: default
data:
  service-type: "LoadBalancer"
  replicas: "2"
```

**含义解读**:
- 每个 `Gateway` 实例可挂自己的 `ConfigMap` 个性化配置(不必通过 `GatewayClass` 全局模板)
- 这就是 PR #2924 的核心动机 — **"我想要每个 Gateway 单独 config"**

### 4.3 `targetRefs` 示例 — Istio AuthorizationPolicy 绑 waypoint

```yaml
# ambient 模式下,AuthZ 用 targetRefs 绑 waypoint(per-namespace L7 拦截)
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: team-a-allow-internal
  namespace: team-a-runtime
  labels:
    istio.io/rev: 1-30            # ← 双 revision 时 pin 到目标 istiod(防老版本误读)
spec:
  targetRefs:                      # ← targetRefs:绑 waypoint Gateway
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: waypoint
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces: ["team-a-runtime"]
```

**含义解读**:
- `AuthorizationPolicy` 是**策略**(policy)
- `targetRefs` 指向**作用对象**(`waypoint` Gateway)
- **方向相反于 parametersRef** — `parametersRef` 是"我指向我的配置",`targetRefs` 是"策略指向目标"

### 4.4 `targetRefs` 示例 — K8s Gateway API BackendTLSPolicy 绑 Service

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: BackendTLSPolicy
metadata:
  name: require-tls-to-upstream
spec:
  targetRefs:                      # ← targetRefs:绑 Service
    - kind: Service
      name: my-api-service
      group: ""
  validation:
    caCertificateRefs:
      - kind: ConfigMap
        name: upstream-ca
```

**含义解读**:
- 这是 **K8s Gateway API 标准资源**(不是 Istio 专属)
- `targetRefs` 绑 Service,要求所有进 my-api-service 的流量都验 TLS

### 4.5 `parentRefs` + `backendRefs` 示例 — 你已有的 HTTPRoute(对比用)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-route
  namespace: team1-appdev-aibang
spec:
  parentRefs:                      # ← parentRefs:绑 ListenerSet
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listenerset
      sectionName: https
  rules:
    - matches:
        - path: {type: PathPrefix, value: /api}
      backendRefs:                 # ← backendRefs:绑 Service
        - group: ""
          kind: Service
          name: my-api
          port: 443
```

> `parentRefs` 与 `backendRefs` 都是 **HTTPRoute 上的字段**,与 `parametersRef` / `targetRefs` 完全独立。

---

## 5. ReferenceGrant 是另一个常见混淆点

> 你可能会问:"targetRefs 不就是 ReferenceGrant 吗?"

**不是**。

| 字段 | 域 | 是什么 |
|---|---|---|
| **`ReferenceGrant`** | K8s Gateway API 资源(整资源,不是字段) | "授权跨 ns 引用"的工具 |
| **`ReferenceGrant.spec.from` / `.to`** | ReferenceGrant 的字段 | "哪个 ns 的哪个 kind 可引用哪个 ns 的哪个 kind" |
| **`targetRefs`** | K8s Gateway API 多种 Policy 资源的字段 | "策略作用到哪些资源" |

```yaml
# ReferenceGrant 示例:HTTPRoute 跨 ns 引用 Service
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: allow-team1-to-team2-service
  namespace: team2-ns         # ← 必须放在**被引用方**所在 ns
spec:
  from:                       # ← 哪些资源可以引用
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: team1-ns     # ← 在哪个 ns 的 HTTPRoute 可以引用
  to:                         # ← 哪些资源可以被引用
    - group: ""               # ← 引用哪个 kind
      kind: Service
      # namespace 不写 = 必须在 ReferenceGrant 所在 ns(本例 team2-ns)
```

**关系**:
- 当你用 `targetRefs` 引用**跨 ns 的 Service** — 需要先在**目标 ns** 建 ReferenceGrant
- 当你用 `parentRefs` 引用**跨 ns 的 Gateway / ListenerSet** — Gateway listener 配置内置握手(不需 ReferenceGrant)
- 当你用 `backendRefs` 引用**跨 ns 的 Service** — 同 targetRefs,需 ReferenceGrant

---

## 6. 完整对比表(横向)

| 维度 | `parametersRef` | `targetRefs` |
|---|---|---|
| **方向** | 我 → 我的配置 | 策略 → 目标资源 |
| **谁持有** | GatewayClass / Gateway / Mesh / Istio CRD | AuthorizationPolicy / BackendTLSPolicy / 其他 Policy |
| **被指向** | ConfigMap / CRD(实现特定)| Service / Gateway / GatewayClass / ServiceEntry |
| **典型场景** | 给 GatewayClass 配 EnvoyProxy / 给 Gateway 单独 ConfigMap | 给 AuthorizationPolicy 选作用 Service / 给 BackendTLSPolicy 绑 Service |
| **是否必须** | 否(可选)| 视资源而定 — AuthorizationPolicy 是 optional,BackendTLSPolicy 是 required |
| **scope** | cluster-scoped 或 namespace-scoped(看持有者)| 跟随持有者 namespace |
| **状态** | Stable(1.3+) | Stable(1.5+)|
| **Istio 扩展?** | 部分 Istio CRD 用 | **Istio 把它扩展到 AuthorizationPolicy** |
| **与 selector 关系** | 无关 | **与 selector 互斥**(AuthorizationPolicy)|
| **ReferenceGrant 需求** | 不需要(同 ns ConfigMap 即可)| 跨 ns 引用 Service 时需要 |
| **本场景现状** | **没用过** | **没用过**(AuthZ 引入时才用)|
| **本场景未来** | Istio 默认 `ConfigMap gateway.istio.io/defaults-for-class` 自动 | ambient AuthZ 引入时必用 |

---

## 7. 命名学 — 为什么名字这么像?

两个 Refs 名字相似是 **K8s Gateway API 的命名历史** 造成的:

| 时间 | 字段 | 含义 |
|---|---|---|
| 早期 | `parametersRef` | GatewayClass 用,指向实现特定 config |
| 2024 年 PR #2924 | `parametersRef` 扩展到 `Gateway.infrastructure` | Gateway 实例级 config |
| 2023+ | `targetRefs` | K8s Policy 标准化("此 policy 作用于哪些目标") |
| Istio 1.22+ | AuthorizationPolicy 加 `targetRefs` | 取代 `selector` |

**两个 Refs 本质上对应两个不同的抽象**:
- "我需要 config" → `parametersRef`(consumer 视角)
- "我需要目标" → `targetRefs`(policy producer 视角)

**这只是命名巧合**,没有更深层的语义关联。

---

## 8. 本场景当前用法与未来引入

### 8.1 当前用法(2026-09-17)

| Refs 类型 | 用在哪 | 文件 |
|---|---|---|
| **`parentRefs`** | ✅ **HTTPRoute → ListenerSet** | `k8s-gateway/03-gateway/abjx-gw-int.yaml` 等 |
| **`backendRefs`** | ✅ **HTTPRoute → Service** | `k8s-gateway/06-runtime/httproute.yaml` |
| **`parametersRef`** | ❌ **未用** | - |
| **`targetRefs`** | ❌ **未用**(AuthZ 引入时才用) | - |

### 8.2 未来引入路径

| 阶段 | 会引入什么 | 来源 |
|---|---|---|
| **Phase 1**(装 ambient) | 仍是 HTTPRoute + parentRefs/backendRefs | - |
| **Phase 2**(业务 ns 迁 ambient) | 仍是 HTTPRoute + parentRefs/backendRefs | - |
| **Phase 4**(引入 L7 AuthZ) | **首次用 `targetRefs`** — AuthorizationPolicy 绑 Service / waypoint | 06 文 §4 + 11 文 |
| **Phase 4**(引 BackendTLSPolicy) | **首次用 `targetRefs`(K8s 标准版)** — 绑 Service 验 TLS | K8s Gateway API 1.5+ |
| **可选**(企业版 / Solo 分发)| **首次用 `parametersRef`** — 给 waypoint / Gateway 挂 EnvoyProxy CRD | Solo / kgateway |

### 8.3 本场景未来最容易踩的混淆

| 场景 | 容易写错的 |
|---|---|
| 写 AuthorizationPolicy 想绑 waypoint | 写成 `parentRefs: [waypoint]` ❌ — 应该是 `targetRefs: [Gateway waypoint]` |
| 写 HTTPRoute 想绑 ListenerSet | 写成 `targetRefs: [ListenerSet]` ❌ — 应该是 `parentRefs: [ListenerSet ...]` |
| 想给 Gateway 单独 ConfigMap 配置 | 写成 `targetRefs` ❌ — 应该是 `infrastructure.parametersRef` |
| 想跨 ns 引用 Service | 只写 `targetRefs` 不写 ReferenceGrant ❌ — 需要 ReferenceGrant 兜底 |

---

## 9. 反向:什么时候这两个都不需要

| 场景 | 理由 |
|---|---|
| 纯 HTTPRoute 路由(无 L7 策略)| `parentRefs` + `backendRefs` 已够 |
| 简单业务 ns(纯 mTLS)| 只需 `PeerAuthentication`(用 selector,不是 targetRefs)|
| 集群级 default GatewayClass | `GatewayClass` 由 Istio 自动注册,无需 parametersRef 自定义 |

---

## 10. 决策树 — 写 YAML 时怎么选字段

```
你想写什么?
  │
  ├─ 我要给某个 Gateway 选特定的 controller / 配实现特定 config
  │   └─ 用 parametersRef(指向 ConfigMap / CRD)
  │
  ├─ 我要给某个 Gateway 单独 config(不是全局)
  │   └─ 用 spec.infrastructure.parametersRef
  │
  ├─ 我要写一个 Policy(AuthZ / TLS / RateLimit)绑到 Service / Gateway
  │   └─ 用 targetRefs
  │
  ├─ 我要写 HTTPRoute 绑 Gateway / ListenerSet
  │   └─ 用 parentRefs(不是 targetRefs!)
  │
  ├─ 我要写 HTTPRoute 绑后端 Service
  │   └─ 用 backendRefs(不是 targetRefs!)
  │
  └─ 我要跨 ns 引用 Service
      ├─ HTTPRoute → Service(backendRefs):需 ReferenceGrant
      ├─ AuthZ targetRefs → Service:需 ReferenceGrant
      └─ HTTPRoute → Gateway(parentRefs):Gateway listener 内置握手,无需
```

---

## 11. References

### 11.1 权威来源

- [K8s Gateway API API Reference](https://gateway-api.sigs.k8s.io/reference/api-spec/) — 所有字段权威定义
- [K8s Gateway API ReferenceGrant](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/) — ReferenceGrant 文档
- [K8s Gateway API Security Concepts](https://gateway-api.sigs.k8s.io/docs/concepts/security/) — ReferenceGrant 与 parentRefs 跨 ns 模式
- [Gateway API PR #2924: Add parametersRef to Gateway.spec.infrastructure](https://github.com/kubernetes-sigs/gateway-api/pull/2924) — parametersRef 扩展到 Gateway
- [GEP-1867: GatewayClass parametersRef 扩展](https://gateway-api.sigs.k8s.io/geps/gep-1867/) — parametersRef 设计动机
- [Istio AuthorizationPolicy reference](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — Istio targetRefs 扩展
- [Istio Security Best Practices](https://istio.io/latest/docs/ops/best-practices/security) — `targetRefs` 绑 GatewayClass `istio-waypoint` 用法
- [Istio GitHub Issue #59328: Support HTTPRoute in AuthorizationPolicy targetRefs](https://github.com/istio/istio/issues/59328) — 未来 targetRefs 支持扩展

### 11.2 本目录关联文档

- `01-ambient-vs-sidecar.md` — 整体对比
- `06-policy-capabilities.md` — AuthorizationPolicy 能力矩阵(含 targetRefs 用法)
- `08-ambient-networkpolicy.md` — NetworkPolicy 与 ambient 协同
- `10-waypoint-gateway-coexistence.md` — Gateway + waypoint 共存
- `11-l7-zero-downtime-constraint.md` — targetRefs vs selector 迁移约束
- `12-revision-canary-mtls-compat.md` — targetRefs 与 `istio.io/rev` label 配合
- `ADR-LOCAL-001-migrate-minimal-to-ambient.md` — 决策记录
- `PERSONAL-FOCUS-LIST.md` — Lex 个人关注清单

### 11.3 你已有 HTTPRoute 用法

- `k8s-gateway/03-gateway/abjx-gw-int.yaml` — Gateway(本场景 GatewayClass: istio)
- `k8s-gateway/06-runtime/httproute.yaml` — HTTPRoute(用 parentRefs + backendRefs)
- `k8s-gateway/05-listenerset/team1-listenerset.yaml` — ListenerSet

---

## 12. 关键认知 checklist(自测)

读完本文后,你能回答下列问题吗?

| # | 问题 | 答案要点 |
|---|---|---|
| 1 | `parametersRef` 在哪些资源出现? | GatewayClass / Gateway / Mesh / 部分 Istio CRD |
| 2 | `targetRefs` 在哪些资源出现? | K8s Gateway API Policy(BackendTLSPolicy 等)+ Istio AuthorizationPolicy |
| 3 | `targetRefs` 与 `parentRefs` 区别? | `targetRefs` 是"策略绑目标";`parentRefs` 是"路由绑父 Gateway" |
| 4 | `targetRefs` 与 `selector` 关系? | AuthorizationPolicy 里**互斥** |
| 5 | `parametersRef` 通常指向什么? | ConfigMap / 实现特定 CRD(如 EnvoyProxy)|
| 6 | ReferenceGrant 与 `targetRefs` 关系? | **ReferenceGrant 不是字段,是个独立资源**;跨 ns 引用 Service 时需要 |
| 7 | 本场景当前用了哪个 Refs? | **只用 parentRefs + backendRefs**(HTTPRoute)|
| 8 | 本场景未来会首次用哪个? | **targetRefs**(AuthZ 引入时)|

> 自测 8/8 = 已掌握;5-7 = 大部分懂;≤ 4 = 重读 §2 / §3 / §6