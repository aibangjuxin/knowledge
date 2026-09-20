- [summary](#summary)
  - [📄 文档总结：`20-solo-ambient-kong.md`](#-文档总结20-solo-ambient-kongmd)
    - [这篇文档干了什么](#这篇文档干了什么)
    - [文档结构(4 个递进章节)](#文档结构4-个递进章节)
    - [三个核心 takeaway](#三个核心-takeaway)
    - [文档性质](#文档性质)
- [Istio Gateway old Work mode](#istio-gateway-old-work-mode)
    - [1. ListenerSet 配置示例](#1-listenerset-配置示例)
    - [2. HTTPRoute 配置示例](#2-httproute-配置示例)
      - [场景 A：API 经过 KongDP 治理 (`api1`)](#场景-aapi-经过-kongdp-治理-api1)
      - [场景 B：API 绕过 Kong，直连 Runtime (`api2`)](#场景-bapi-绕过-kong直连-runtime-api2)
    - [3. DestinationRule 配置示例（旧模式关键）](#3-destinationrule-配置示例旧模式关键)
    - [1. 架构与控制面维度：多租户网关与责任分离模式 (Multi-Tenant Gateway with Separation of Concerns)](#1-架构与控制面维度多租户网关与责任分离模式-multi-tenant-gateway-with-separation-of-concerns)
    - [2. 流量路由与数据面维度：两级/分层网关路由模式 (Two-Tier / Layered Gateway Routing Pattern)](#2-流量路由与数据面维度两级分层网关路由模式-two-tier--layered-gateway-routing-pattern)
    - [3. 服务间安全与传输维度：南北向-东西向 mTLS 桥接模式 (Tier-1-to-Tier-2 mTLS Direct Bridging)](#3-服务间安全与传输维度南北向-东西向-mtls-桥接模式-tier-1-to-tier-2-mtls-direct-bridging)
    - [总结归纳](#总结归纳)
- [istio Gateway + KongDP](#istio-gateway--kongdp)
    - [1. 整体流量图谱与端口协议转换](#1-整体流量图谱与端口协议转换)
    - [2. KongDP 与 Ambient 结合的核心机制](#2-kongdp-与-ambient-结合的核心机制)
      - [方案 A：KongDP 位于 Ambient Mesh **外部**（推荐，架构最清晰）](#方案-akongdp-位于-ambient-mesh-外部推荐架构最清晰)
      - [方案 B：KongDP 也加入 Ambient Mesh](#方案-bkongdp-也加入-ambient-mesh)
    - [3. 配置适配调整对比](#3-配置适配调整对比)
      - [① HTTPRoute 资源调整](#-httproute-资源调整)
      - [② DestinationRule 资源调整（非常关键）](#-destinationrule-资源调整非常关键)
      - [③ Kong Upstream Target 调整](#-kong-upstream-target-调整)
    - [4. 关键优势与注意事项](#4-关键优势与注意事项)
- [In-depth exploration of Plan A](#in-depth-exploration-of-plan-a)
    - [一、 疑问一：第 3 步 ztunnel 接管需要手动配置吗？](#一-疑问一第-3-步-ztunnel-接管需要手动配置吗)
    - [二、 疑问二：从 Kong 到 ztunnel 是明文，安全吗？如何看待这一段？](#二-疑问二从-kong-到-ztunnel-是明文安全吗如何看待这一段)
      - [1. 流量链路的安全风险分析](#1-流量链路的安全风险分析)
      - [2. 如果要求“全链路零信任加密”，如何强化方案 A？](#2-如果要求全链路零信任加密如何强化方案-a)
    - [三、 方案 A 细化落地架构与配置全貌](#三-方案-a-细化落地架构与配置全貌)
      - [1. 架构拓扑细化](#1-架构拓扑细化)
      - [2. 各组件 YAML 配置细节](#2-各组件-yaml-配置细节)
        - [① Istio Ingress Gateway 层的 HTTPRoute (无需变更逻辑，仅改后端端口)](#-istio-ingress-gateway-层的-httproute-无需变更逻辑仅改后端端口)
        - [② KongDP Upstream 配置 (Declarative Config / KongIngress)](#-kongdp-upstream-配置-declarative-config--kongingress)
        - [③ Runtime Namespace 命名空间准备](#-runtime-namespace-命名空间准备)
        - [④ Runtime Deployment \& Service](#-runtime-deployment--service)
    - [四、 落地落地建议与总结](#四-落地落地建议与总结)
- [ambient 网关接管之后的配置](#ambient-网关接管之后的配置)
    - [一、 变更前后配置拆解对比](#一-变更前后配置拆解对比)
    - [二、 基础设施与 Namespace 准备](#二-基础设施与-namespace-准备)
      - [1. Namespace 启用 Ambient](#1-namespace-启用-ambient)
      - [2. ListenerSet 配置（位于 `abjx-listenerset-int`）](#2-listenerset-配置位于-abjx-listenerset-int)
    - [三、 Ambient 模式下的 HTTPRoute 配置](#三-ambient-模式下的-httproute-配置)
      - [1. 场景一：API 经过 KongDP (`api1`)](#1-场景一api-经过-kongdp-api1)
      - [2. 场景二：API 绕过 Kong，直连 Runtime (`api2`)](#2-场景二api-绕过-kong直连-runtime-api2)
    - [四、 KongDP 端 Upstream 映射配置 (Declarative / DB-less 示例)](#四-kongdp-端-upstream-映射配置-declarative--db-less-示例)
    - [五、 业务层 Runtime Deployment \& Service YAML](#五-业务层-runtime-deployment--service-yaml)
    - [六、 总结与注意事项](#六-总结与注意事项)
    - [networkpolicy](#networkpolicy)
    - [1. 特殊 Network Policy 配置汇总表](#1-特殊-network-policy-配置汇总表)
    - [2. 核心 Network Policy YAML 配置示例](#2-核心-network-policy-yaml-配置示例)
      - [特别注意：Ambient 模式下的网络策略踩坑点](#特别注意ambient-模式下的网络策略踩坑点)
      - [策略一：Runtime Namespace - 许可源头流量与 Ambient ztunnel 隧道](#策略一runtime-namespace---许可源头流量与-ambient-ztunnel-隧道)
      - [策略二：KongDP Namespace - 许可来自 Istio Gateway 的流量](#策略二kongdp-namespace---许可来自-istio-gateway-的流量)
    - [总结建议](#总结建议)


# summary 

## 📄 文档总结：`20-solo-ambient-kong.md`

**路径**:`gcp/gateway-2.0/k8s-gateway-ambient/20-solo-ambient-kong.md`(1012 行,~46KB)

### 这篇文档干了什么

回答一个核心问题:**Istio Ambient Mesh 已经接管 Runtime Pod 的 mTLS 之后,旧的 "Istio Gateway + KongDP + Runtime" 两级网关架构怎么迁,运行时 Runtime 已经不能 / 不需要走 HTTPS 端口,KongDP 该怎么对接?**

### 文档结构(4 个递进章节)

| § | 章节 | 干的事 |
|---|---|---|
| 1 | **Istio Gateway old Work mode** | 描绘旧模式:**多租户声明式应用网关**模式。`ListenerSet`(在 `abjx-listenerset-int`)挂到共享 `gke-shared-gateway` 上,各 Team 通过 `parentRefs` 声明自己的 `HTTPRoute`。两条路径: ① `/api1` → KongDP 8443;② `/api2` → 直连 Runtime 8443。旧模式 Runtime Pod 必须自建 TLS,`DestinationRule` 必须显式声明 `tls.mode: SIMPLE/MUTUAL`。给出 3 个完整 YAML(ListenerSet / HTTPRoute×2 / DestinationRule×2)。 |
| 2 | **istio Gateway + KongDP** | 提出核心矛盾:Ambient 模式下 Pod 间已被 ztunnel 自动 HBONE 加密,KongDP 与 Ambient Runtime 该如何拼装?给出**方案 A(KongDP 在 Mesh 外,推荐)** vs **方案 B(KongDP 也加 Ambient)**。方案 A 流量:Kong → 明文 HTTP 跨节点 → Runtime 节点的 ztunnel → Runtime Pod 的明文 80/8443。 |
| 3 | **In-depth exploration of Plan A** | 深挖方案 A 两个疑问:① ztunnel 接管**无需手动配置**,Namespace 打 `istio.io/dataplane-mode=ambient` 标签即可(CNI + eBPF/iptables 自动劫持);② Kong→ztunnel 是明文,VPC 内风险可接受,但如要"全链路零信任"应升级方案 B。给出细化落地:HTTPRoute(后端端口 8443→8000,删 DestinationRule)+ Kong declarative config(`http://...:80`)+ Runtime Deployment(Service 监听明文 80)。 |
| 4 | **ambient 网关接管之后的配置** | 落地方案全貌。重新汇总 ListenerSet + 两个 HTTPRoute(api1 过 Kong 8000、api2 直连 Runtime 80)+ Kong upstream + Runtime Deployment/Service。**核心变化表**:DestinationRule 彻底废弃 / HTTPRoute 端口 443→80 / Kong upstream https→http / Runtime Pod 不再管证书。 |
| 5 | **networkpolicy** | Ambient 模式下 NetworkPolicy 的特殊性:ztunnel 在**节点网络层**(CNI + eBPF/iptables)拦截流量,NetworkPolicy 看到的是原始发送方 IP + 真实业务端口 80,不是 HBONE 端口。给出**5 条策略**(汇总表)+ 2 段 YAML(Runtime Namespace 放行 ztunnel 15008/15006 + Kong 源 IP + Istio Gateway 源 IP;Kong Namespace 放行 Istio Gateway 源 IP 到 8000)。强调必须放行 ztunnel 的 15008(HBONE)/ 15006(健康检查)端口。 |

### 三个核心 takeaway

1. **架构判定**:Ambient 模式让 `DestinationRule` 彻底消失,集群内加密被 ztunnel 透明接管,业务代码/镜像彻底解耦 TLS。
2. **演进路径**:先方案 A(Kong 在 Mesh 外,迁移最小)平滑迁移,安全审计不达标再升级到方案 B(Kong Namespace 也打 `ambient` 标签,无需改 Kong 任何配置即可获得端到端 mTLS)。
3. **NetPol 适配**:在 GKE/Cilium/GKE Dataplane V2 上,业务 Pod 的 NetworkPolicy 写法不变(按真实源 IP + 真实端口 80),唯一特殊点是必须额外放行 ztunnel 的 **15008/15006**。

### 文档性质

这是一份**架构调研 + 落地配方**混合文档,围绕"KongDP 与 Ambient Mesh 的三种结合可能性"做了从旧模式 → 新方案 → 安全分析 → 落地 YAML → NetPol 适配的完整闭环,适合直接照着迁。

# Istio Gateway old Work mode
原来的这套 **Istio Gateway + ListenerSet + HTTPRoute** 模式，在现代 Cloud Native / Gateway API 的体系下，属于**标准的“多租户声明式应用网关”模式（Multi-Tenant Declarative Application Gateway Model）**，具体可以从以下几个维度来精确定义和总结：


| 镜像 | 对应组件 | Helm Chart | Ambient 中的角色 |
|------|---------|-----------|-----------------|
| `soloio-img/pilot:1.30.3-distroless` | istiod | `istiod` | 控制面，下发 xDS / ztunnel WDS，签发 SPIFFE 证书 |
| `soloio-img/install-cni:1.30.3-distroless` | istio-cni + ambient node agent | `cni` | DaemonSet，做 pod netns 重定向（Ambient 的**前置必需**） |
| `soloio-img/ztunnel:1.30.3-distroless` | ztunnel | `ztunnel` | DaemonSet，节点级 L4 代理，HBONE + mTLS |
| `soloio-img/proxyv2:1.30.3-distroless` | Envoy | `gateway` / waypoint 自动拉起 | ① Ingress Gateway ② `istio-waypoint` 的数据面 ③ east-west gateway |


基于架构背景，在旧模式（传统 Istio Gateway API + HTTPS 传输 + 业务自建/Sidecar TLS）下的完整 YAML 配置示例。

在这套模式中：

1. **`ListenerSet`**：由业务团队（如 Team 1）在共享入口网关下声明属于自己的域名（如 `*.team1.caep.uk`）。
2. **`HTTPRoute 1` (经过 KongDP)**：基于 API 名称匹配（如 `/api1`），路由至 KongDP 的 HTTPS/TLS 端口。
3. **`HTTPRoute 2` (直连 Runtime)**：绕过 KongDP，直接路由至业务 Runtime Pod 的 HTTPS/TLS 端口（`443` 或 `8443`）。
4. **`DestinationRule`**：指引 Istio Gateway 在向后端（Kong 或 Runtime）发起连接时使用 TLS 模式。

---

### 1. ListenerSet 配置示例

此资源部署在 ListenerSet 所在的 Namespace（如 `abjx-listenerset-int`），定义了属于 Team 1 的 HTTPS 域名监听配置。

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha2 # 注：部分版本中使用 gateway.networking.k8s.io/v1
kind: ListenerSet
metadata:
  name: team1-listenerset
  namespace: abjx-listenerset-int
spec:
  # 绑定到集群管理员部署的共享 Istio Gateway
  parentRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: gke-shared-gateway
    namespace: istio-system
  listeners:
    - name: https
      hostname: "*.team1.caep.uk"
      port: 443
      protocol: HTTPS
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              tenant: team1
      tls:
        mode: Terminate
        certificateRefs:
          - group: ""
            kind: Secret
            name: team1-wildcard-cert
            namespace: abjx-listenerset-int

```

---

### 2. HTTPRoute 配置示例

#### 场景 A：API 经过 KongDP 治理 (`api1`)

请求在 Istio Gateway 解密 TLS 后，匹配 `/api1` 路径，被转发到 KongDP 的 HTTPS 端口。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api1-via-kong-route
  namespace: 110139-int # 租户/业务团队 Namespace
  labels:
    app: api1
    tenant: team1
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listenerset
      namespace: abjx-listenerset-int
      sectionName: https
  hostnames:
    - "api1.team1.caep.uk"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api1
      backendRefs:
        - name: kong-dp-service # 指向 KongDP 的 Kubernetes Service
          namespace: kong-system # 若 Kong 部署在独立 Namespace
          port: 8443            # KongDP 的 HTTPS 端口
          weight: 1
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: X-Tenant
                value: team1
              - name: X-Gateway-Source
                value: team1-listenerset

```

#### 场景 B：API 绕过 Kong，直连 Runtime (`api2`)

对于不需要 Kong 治理的 API，HTTPRoute 直接指向 Runtime 的 HTTPS 端口。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api2-direct-runtime-route
  namespace: 110139-int
  labels:
    app: api2
    tenant: team1
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listenerset
      namespace: abjx-listenerset-int
      sectionName: https
  hostnames:
    - "api2.team1.caep.uk"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api2
      backendRefs:
        - name: app2-runtime-service # 直接指向业务 Pod 的 Service
          port: 8443                 # Runtime 自建 TLS / Envoy Sidecar 的 HTTPS 端口
          weight: 1
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: X-Tenant
                value: team1
              - name: X-Gateway-Source
                value: team1-listenerset

```

---

### 3. DestinationRule 配置示例（旧模式关键）

在旧模式下，因为下游（KongDP 或 Runtime Pod）监听的是 TLS 端口，Istio Ingress Gateway 转发流量时需要显式配置出站 TLS 发起逻辑。

```yaml
# 指引 Gateway 向 KongDP 发起 TLS 连接
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: kong-dp-tls-dr
  namespace: 110139-int
spec:
  host: kong-dp-service.kong-system.svc.cluster.local
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 8443
        tls:
          mode: SIMPLE # 告诉 Istio Gateway 出站使用 HTTPS/TLS 发起请求
---
# 指引 Gateway 向直连 Runtime Pod 发起 TLS 连接
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: app2-runtime-tls-dr
  namespace: 110139-int
spec:
  host: app2-runtime-service.110139-int.svc.cluster.local
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 8443
        tls:
          mode: SIMPLE # 若 Runtime 要求客户端验证，可设为 MUTUAL

```


---

### 1. 架构与控制面维度：多租户网关与责任分离模式 (Multi-Tenant Gateway with Separation of Concerns)

这是基于 **Kubernetes Gateway API** 标准构建的高级多租户架构：

* **基础设施层 (Infra Team)**：负责部署管理 `Gateway` 资源及底层控制器（Istio Pilot），定义全局的入口基础设施（如 IP、TLS 证书、全局网络等）。
* **业务团队/租户层 (Tenant Teams)**：通过 `ListenerSet`（或 Gateway API 的跨 Namespace 挂载能力）在各自的逻辑/应用隔离区内声明属于该 Team 的入口规则（域名通配符、端口、TLS 终止点等）。
* **API / 服务开发者 (Service Owners)**：在自己的租户 Namespace 中编写 `HTTPRoute`，通过 `parentRefs` 将路由精准绑定到团队的 `ListenerSet` 上。

这种架构打破了传统“单块集中式网关配置”的瓶颈，实现了**控制面的声明式自治与多租户隔离**。

---

### 2. 流量路由与数据面维度：两级/分层网关路由模式 (Two-Tier / Layered Gateway Routing Pattern)

在业务流量的具体走向中，您采用的是标准的**两级代理/路由拓扑**：

```text
[ Client Request ]
       │
       ▼
┌─────────────────────────────────────────────────────────┐
│ Istio Ingress Gateway (Tier 1: Global/Tenant Router)    │
│  - 匹配域名 (e.g. api1.team1.caep.uk)                   │
│  - 执行全局/租户级 HTTPRoute L7 匹配                      │
│  - 注入租户/来源 Header (X-Tenant, X-Gateway-Source)     │
└────────────────────────────┬────────────────────────────┘
                             │
            ┌────────────────┴────────────────┐
            │ Path-based Dynamic Routing      │
            ▼                                 ▼
┌─────────────────────────┐       ┌─────────────────────────┐
│  KongDP (Tier 2 Gateway)│       │  Direct Runtime Pod     │
│  (经过 API 平台/插件治理) │       │  (直连业务/ bypassing)   │
└───────────┬─────────────┘       └─────────────────────────┘
            │                                 ▲
            └─────────────── Direct ──────────┘

```

这种两级模式在企业级微服务中非常典型，其核心特点为：

1. **Tier 1 (Istio Gateway)**：作为**统一流量入口与租户分流层**。负责域名解包、TLS 终止、租户身份 Header 注入，以及根据全局唯一的 Path（API 名称）做 **流量分叉 (Bypass or Ingress-to-Kong)**。
2. **Tier 2 (KongDP)**：作为**共享 API 平台/业务网关层 (Shared Sharded API Gateway)**。承接需要高级 API 治理能力（如限流、鉴权、Plugin 扩展、API 计费等）的流量，基于路径（如 `/api1`）路由回具体的业务 Runtime。
3. **Bypass 机制 (直连能力)**：对于不需要 Kong 治理的简单 API，HTTPRoute 直接将后端 (`backendRefs`) 指向业务 Runtime 的 ClusterIP，跳过 KongDP。

---

### 3. 服务间安全与传输维度：南北向-东西向 mTLS 桥接模式 (Tier-1-to-Tier-2 mTLS Direct Bridging)

由于您的 Runtime Pod 本身内部实现了 TLS 加密，且在启用 Ambient 模式之前使用传统 Istio：

* **全链路 TLS/mTLS 覆盖**：从最外层的 HTTPS (TLS Termination @ Istio Gateway) 到下游（无论是 KongDP 还是 Runtime），均在 Mesh / 自建 TLS 的作用下维持内部加密传输。
* **基于请求头的上下文传递 (Context Propagation)**：通过 Istio `HTTPRoute` 过滤器的 `RequestHeaderModifier` 手动注入 `X-Tenant` 与 `X-Gateway-Source`，将南北向入口处提取的租户身份信息穿透传递给下游的 KongDP 或业务服务，实现了**边缘网关向内部 API 网关/服务的租户上下文透传**。

---

### 总结归纳

简单来说，原有的架构可以概括为：

> **基于 Kubernetes Gateway API (ListenerSet + HTTPRoute) 实现的“多租户边缘网关 + 可选择性 Kong API 网关”的两级（Two-Tier）南北向流量分发与 API 治理模式。**

* **优点**：不同 Team 域名隔离、API Path 全局唯一、配置解耦度高；能够非常灵活地按 API 粒度选择“开启 Kong 治理”或“直连 Runtime 绕过 Kong”。



* **引入 Ambient 模式后的潜在变革点**：如果未来引入 Ambient，Istio Gateway 作为南北向入口的角色不会改变，但 Tier 1 到 Tier 2 (KongDP) 以及 Tier 2 到 Runtime 之间的内部加密与身份认证，可以从原来的 Sidecar 注入或应用自建 TLS，透明地下沉给 **ztunnel (HBONE / L4 mTLS)** 与 **waypoint (L7 治理)**，从而大幅降低每一个业务 Pod 和 KongDP 的 Sidecar 资源开销。


# istio Gateway + KongDP 
```text
那么现在针对我的这个旧模式，如果我们现在要在环境里引入 Ambient 模式后 就是 Pod之间我们肯定是不要 HTTPS 因为这个默认它自带了 mTLS 的加密， 那么我现在想帮探索一下，在这种模式下面我们的 API 还要到达 Kong，然后 Kong DP 应该本身又不受 ambient 的接管 那么 如何能实现我们原来的需求，比如也可以支持让 API 可以经过 Kong ，Kong 之后 upstream 到 runtime 。但是这里有个前提条件，就是 runtime肯定已经 ambient 接管下的比如 80 端口了 或者自定义的非 https 端口了比如也可能是 8443 那么在这种模式下呢，我们和 Kong的结合如何来工作呢？
```



在 Ambient 模式下，Pod 间传输已被 **ztunnel 自动加密 (HBONE / mTLS)**，原本应用层（如应用自建 TLS 或 Envoy TLS Sidecar）的 HTTPS 需求被彻底解耦。
针对您的架构（KongDP 未开启 Ambient / 属于 Mesh 外或未打标 Pod，而 Runtime Pod 位于 Ambient 纳管的 Namespace 下，监听明文端口如 `80` 或 `8443`），
实现 **“Istio Gateway ➔ KongDP ➔ Ambient Runtime”** 链路的落地方案总结如下：

---

### 1. 整体流量图谱与端口协议转换

在这套方案中，端口解耦与协议转换在各阶段的职责分工如下：

```text
[ External User ]
       │ HTTPS (Port 443 / TLS Termination)
       ▼
┌────────────────────────────────────────────────────────┐
│ Tier 1: Istio Ingress Gateway                          │
└───────────┬────────────────────────────────────────────┘
            │
            ├─────────────────────────────────────────┐
            │ Path: /api2 (Bypass Kong)               │ Path: /api1 (Need Kong)
            │ Standard HTTP/mTLS                      │ Standard HTTP / Cleartext
            ▼                                         ▼
┌─────────────────────────┐               ┌─────────────────────────┐
│ Ambient Runtime Pod     │               │ Tier 2: KongDP          │
│ (Port 80/8443 HTTP)     │               │ (Pod/Deployment Outside)│
└─────────────────────────┘               └────────────┬────────────┘
            ▲                                          │
            │          HTTP (Port 80/8443)             │
            └──────────────────────────────────────────┘
             (Traverses ztunnel for HBONE / mTLS)

```

---

### 2. KongDP 与 Ambient 结合的核心机制

当 Runtime 卸载了应用层 HTTPS 改用明文端口（例如 `80` 或 `8443`）后，Kong 与 Ambient 的对接关键在于**将 Kong 视作网关边界提供者（Client-to-Mesh Edge）**：

#### 方案 A：KongDP 位于 Ambient Mesh **外部**（推荐，架构最清晰）

* **KongDP 的配置**：Kong 保持部署在未标记 `istio.io/dataplane-mode=ambient` 的 Namespace 中。
* **Upstream 目标**：KongDP 的 upstream 直接填 Runtime 的 Kubernetes Service 域名与明文端口（例如 `[http://app-service.110139-int.svc:80](http://app-service.110139-int.svc:80)`）。
* **流量穿透路径**：
1. Kong 发出普通的明文 HTTP 请求到 `app-service:80`。
2. 流量离开 Kong 节点或进入 Runtime 宿主机时，Runtime 所在节点的 **ztunnel 劫持入站流量**。
3. ztunnel 在入口自动将明文 HTTP 包打上 **HBONE (mTLS)** 隧道包，解密后投递给 Runtime 的 `80` 或 `8443` 端口。
4. **结果**：Kong 自身完全无需关注任何 TLS/mTLS 逻辑，由 ztunnel 在节点侧静默完成加密与身份校验。



#### 方案 B：KongDP 也加入 Ambient Mesh

* 如果将 KongDP 所在 Namespace 也打上 `istio.io/dataplane-mode=ambient` 标签：
* Kong 节点侧的 ztunnel 会建立 **Kong ztunnel ➔ Runtime ztunnel** 的直接 L4 HBONE 隧道。
* Kong 内部上游同样只需配置 `http://app-service:80`，所有节点间的传输将获得全透明的零信任 mTLS 保护。

---

### 3. 配置适配调整对比

在切换到 Ambient 模式后，原有的各级 K8s 资源配置调整如下：

#### ① HTTPRoute 资源调整

对于经过 Kong 与不经过 Kong 的路由，直接把 upstream 改为明文端口：

* **直连 Runtime (api2，不经过 Kong)**：
```yaml
backendRefs:
  - name: app-runtime-svc
    port: 80 # 原来是 443，现在使用 Ambient 纳管的明文端口

```


* **经过 KongDP (api1)**：
```yaml
backendRefs:
  - name: kong-dp-svc
    port: 8000 # KongDP 的 HTTP 入口端口

```



#### ② DestinationRule 资源调整（非常关键）

* **旧模式**：必须配置 `TLS mode: SIMPLE` 或 `MUTUAL` 来指引 Istio Gateway/Sidecar 向下游 Pod 发起 TLS 请求。
* **Ambient 模式**：
* **删除针对 Runtime 端口的 TLS 设置**（或将其设为 `DISABLE`）。因为底层 ztunnel 会接管 L4 加密，应用层只需发送标准 HTTP。
* 如果应用了 Ambient，Istio 控制面 (Pilot) 会通过 WDS 自动通知 Gateway 使用 HBONE 协议连接到 Ambient 节点。



#### ③ Kong Upstream Target 调整

在 Kong 的 Admin API / Declarative Config 中：

* **旧配置**：`target: app-service.110139-int.svc:443` (HTTPs)
* **新配置**：`target: app-service.110139-int.svc:80` (HTTP)

---

### 4. 关键优势与注意事项

* **应用无感知剥离 TLS**：Runtime 代码与 Pod 彻底解耦了证书加载与 HTTPS 维护，性能消耗转移至节点级 Rust 编写的高性能 ztunnel 代理。
* **L7 策略拓展（Waypoint Proxy）**：如果在 Runtime 端后续需要做 Header 级别的访问控制或 Istio 侧的 L7 流量切分（例如灰度发布），只需在 Runtime Namespace 下部署一个 `Waypoint Proxy`。流量会自动变成：`KongDP ➔ ztunnel ➔ Waypoint ➔ ztunnel ➔ Runtime`，完全无需动 Kong 或 Gateway 的任何逻辑。
* **租户 Context 保持**：HTTPRoute 中注入的 `X-Tenant` 及 `X-Gateway-Source` 仍会在 HTTP Header 中完好无损地通过 Kong 透传给 downstream Runtime。



# In-depth exploration of Plan A

这里对**方案 A**的核心疑问（是否需要额外工作、明文安全性分析、细化落地步骤）进行详细的拆解与细化。

---

### 一、 疑问一：第 3 步 ztunnel 接管需要手动配置吗？

**不需要任何手动配置，全过程 100% 自动完成。**

在 Istio Ambient 模式下，流量的劫持与加密是**声明式且对应用无感的**：

1. **如何生效**：只要您将 Runtime 所在的 Namespace 打上标签：
```bash
kubectl label namespace 110139-int istio.io/dataplane-mode=ambient

```


2. **底层机制**：
* 节点的 `istio-cni` 会自动在节点网络层（`eBPF` 或 `iptables`）配置规则。
* 当 KongDP 吐出 HTTP 请求（目标地址为 `app-service.110139-int.svc:80`），数据包一到达 **Runtime Pod 所在的宿主机节点**，该节点的 **ztunnel** 就会在内核层捕获入站流量。
* ztunnel 校验其为 Mesh 内部流量，在节点侧完成 **HBONE 解密/mTLS 验证**（如果是 Mesh 内发出的流量）或**入站 mTLS 终止**（对于非 Mesh 源），并将解密后的明文 HTTP 直接投递给 Pod 的 `80`/`8443` 端口。


3. **应用要求**：Runtime 只需要监听普通的 HTTP 明文端口（如 `80`），应用代码和 K8s 资源都不需要感知 ztunnel 或 HBONE 的存在。

---

### 二、 疑问二：从 Kong 到 ztunnel 是明文，安全吗？如何看待这一段？

**是的，在方案 A 下，KongDP 吐出的原始数据包在离开 Kong Pod 到到达 Runtime 节点 ztunnel 之前是明文 HTTP。**

需要从网络拓扑的两个层面来评估安全风险：

#### 1. 流量链路的安全风险分析

```text
[ KongDP Pod ] 
      │ 
      │ ① 明文 HTTP (跨 K8s Overlay 网络 / 节点间)
      ▼
[ Runtime 宿主机 Node ] ──▶ [ ztunnel (节点级) ] ──② 明文 HTTP (Node 本地 loopback)──▶ [ Runtime Pod ]

```

* **跨节点传输 (链路 ①)**：KongDP 到 Runtime 节点的 Pod 网络 overlay（如 Calico, Cilium 等）传输的是明文 HTTP。如果在同一个云厂商 VPC 内（如 GKE VPC），云厂商底层网络天然具备隔离性；但如果防范“集群内部横向攻击/抓包（Pod-to-Pod Eavesdropping）”，**这确实是一个安全的盲区**。
* **节点本地传输 (链路 ②)**：ztunnel 解密后在宿主机内部把流量交给 Runtime Pod，该过程不出节点物理网卡，安全风险极低。

#### 2. 如果要求“全链路零信任加密”，如何强化方案 A？

如果您对安全性有极高要求，不允许集群内部网络出现任何明文链路，有以下两种演进路线：

* **优化路线 1：提升至【方案 B】（KongDP Namespace 也加入 Ambient，最推荐）**
* **操作**：直接给 Kong 所在的 Namespace 也打上 `istio.io/dataplane-mode=ambient` 标签。
* **效果**：
Kong 节点上的 ztunnel 也会生效。Kong 发出明文 HTTP ➔ **Kong 节点的 ztunnel (自动打上 HBONE/mTLS)** ➔ 跨节点加密传输 ➔ **Runtime 节点的 ztunnel (解密)** ➔ Runtime Pod。
* **优点**：KongDP 的代码和配置**完全不需要改动**（依然配置 `http://app-service:80`），但网络链路实现了真正的**端到端节点级 mTLS 加密**。


* **优化路线 2：保持方案 A，但 Kong 到 Runtime 使用 HTTPS（Kong 单边 TLS 探针）**
* 如果 Runtime 前面挂载了 Istio 的 **Waypoint Proxy**（Ambient 的 L7 代理）：
* Kong 配置 upstream 为 HTTPS 指向 Waypoint，由 Waypoint 终止 TLS，再由 Waypoint/ztunnel 转发给 Runtime。



---

### 三、 方案 A 细化落地架构与配置全貌

为了让您能够直接落地，将 **方案 A（Kong 处于 Ambient 外，Runtime 处于 Ambient 内）** 的完整配置和链路梳理如下：

#### 1. 架构拓扑细化

```text
  [ External Client ]
         │ HTTPS (Port 443)
         ▼
┌─────────────────────────────────────────────────────────┐
│ Tier 1: Istio Ingress Gateway                           │
│ (Terminates HTTPS, injects X-Tenant / X-Gateway-Source) │
└────────────────────────────┬────────────────────────────┘
                             │
                             │ HTTP (Over K8s Pod Network)
                             ▼
┌─────────────────────────────────────────────────────────┐
│ Tier 2: KongDP (Namespace: kong-system, NOT Ambient)    │
│  - Match Path: /api1                                    │
│  - Upstream Target: http://app1-svc.110139-int.svc:80   │
└────────────────────────────┬────────────────────────────┘
                             │
                             │ HTTP (Cleartext request)
                             ▼
 ═════════════════════ Node Network Boundary ═════════════════════
                             │ (Intercepted by eBPF/iptables)
                             ▼
┌─────────────────────────────────────────────────────────┐
│ Runtime Node Level: ztunnel (DaemonSet)                 │
│  - Receives inbound HTTP on 80                          │
│  - Handles Node-level identity & traffic proxying       │
└────────────────────────────┬────────────────────────────┘
                             │
                             │ Local Cleartext HTTP
                             ▼
┌─────────────────────────────────────────────────────────┐
│ Runtime Pod (Namespace: 110139-int, Ambient Enabled)   │
│  - App Listening on Port 80 / 8443 (Cleartext)          │
└─────────────────────────────────────────────────────────┘

```

#### 2. 各组件 YAML 配置细节

##### ① Istio Ingress Gateway 层的 HTTPRoute (无需变更逻辑，仅改后端端口)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api1-to-kong
  namespace: 110139-int
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listenerset
      namespace: abjx-listenerset-int
      sectionName: https
  hostnames:
    - "api1.team1.caep.uk"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api1
      backendRefs:
        - name: kong-dp-svc
          namespace: kong-system
          port: 8000 # Kong 的明文/HTTP 接收端口（旧模式下通常是 8443 HTTPS）
          weight: 1
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: X-Tenant
                value: team1
              - name: X-Gateway-Source
                value: team1-listenerset

```

##### ② KongDP Upstream 配置 (Declarative Config / KongIngress)

在 Kong 的配置中，指向 Runtime 的 Service，协议直接使用 `http`：

```yaml
_format_version: "3.0"
services:
  - name: app1-service
    url: http://app1-svc.110139-int.svc.cluster.local:80 # 填 Runtime Service 的明文端口
    routes:
      - name: app1-route
        paths:
          - /api1

```

##### ③ Runtime Namespace 命名空间准备

这是唯一需要执行的操作命令：

```bash
# 1. 给业务租户 Namespace 开启 Ambient 模式
kubectl label namespace 110139-int istio.io/dataplane-mode=ambient

# 2. 移除原有的 Sidecar 自动注入标签（如果有的话）
kubectl label namespace 110139-int istio.io/rev- istio-injection-

```

##### ④ Runtime Deployment & Service

Runtime 应用镜像完全剥离自建 TLS 逻辑，直接提供 HTTP 服务：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app1-runtime
  namespace: 110139-int
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: app
          image: your-company/api1-runtime:v1.0
          ports:
            - containerPort: 80 # 或 8443，纯明文 HTTP 服务
---
apiVersion: v1
kind: Service
metadata:
  name: app1-svc
  namespace: 110139-int
spec:
  ports:
    - port: 80
      targetPort: 80
      name: http
  selector:
    app: app1-runtime

```

---

### 四、 落地落地建议与总结

1. **工作量层面**：选择方案 A，您在 Runtime 端**完全不需要写任何额外的 Istio / Envoy CRD 配置**（连旧模式下的 `DestinationRule` 都可以删掉）。只需要给 Namespace 打标签，Runtime 换成明文端口即可。
2. **安全演进建议**：
* **第一阶段（平滑迁移）**：采用方案 A。KongDP 保持在 Mesh 外，仅将 Runtime 迁入 Ambient Namespace，验证 HTTP 路径透传与 Kong 插件功能。
* **第二阶段（零信任补全）**：如果安全审计要求集群内 Pod-to-Pod 100% 加密，直接将 Kong 所在的 Namespace 也打上 `istio.io/dataplane-mode=ambient` 标签（即升级为方案 B）。无需修改 Kong 的任何配置，即可实现 **Kong ztunnel ➔ Runtime ztunnel** 的透明双向 mTLS 加密。

#  ambient 网关接管之后的配置

在方案 A（**KongDP 位于 Ambient 外部**）下，Runtime 业务剥离了应用层/Sidecar TLS，全面拥抱 **Ambient 自动化 mTLS（HBONE）**。

旧模式中的 `DestinationRule`（用于出站 TLS 加起）被彻底废弃，集群内网络配置简化为标准的 Gateway API YAML。


通过 Istio Gateway + ListenerSet 实现统一的多租户南北向入口与按 API Path 灵活分流（直连或经过 KongDP），同时由节点级的 ztunnel 将内部传输加密透明下沉为自动化 HBONE (mTLS)，让应用彻底解耦 HTTPS 与证书管理。

---

### 一、 变更前后配置拆解对比

| 资源配置层级 | 旧模式 (Traditional Istio Sidecar) | 迁移到 Ambient 模式 (方案 A) |
| --- | --- | --- |
| **Namespace 标签** | `istio-injection=enabled` | `istio.io/dataplane-mode=ambient` |
| **Istio Ingress Gateway** | 挂载证书解密 HTTPS，出口发 TLS 到 Backend | 终止外部 HTTPS，向后端发送**标准 HTTP**（流量经由 ztunnel 加密） |
| **HTTPRoute** | 后端端口为 `443`/`8443` (HTTPS) | 后端端口修改为 `80`/`8000` (标准 HTTP) |
| **DestinationRule** | **必需** (显式声明 `tls.mode: SIMPLE`) | **彻底删除/废弃**（由 ztunnel 自动完成 mTLS） |
| **KongDP Upstream** | `https://app-svc.110139-int:8443` | `http://app-svc.110139-int:80` |
| **Runtime Pod** | 需配置证书/Sidecar 监听 `8443` | 仅需监听明文端口（如 `80`），代码/镜像无需关心 TLS |

---

### 二、 基础设施与 Namespace 准备

#### 1. Namespace 启用 Ambient

```bash
# 1. 为 Runtime Namespace 开启 Ambient 模式
kubectl label namespace 110139-int istio.io/dataplane-mode=ambient

# 2. 清理旧模式的 Sidecar 自动注入标签
kubectl label namespace 110139-int istio-injection- istio.io/rev-

```

#### 2. ListenerSet 配置（位于 `abjx-listenerset-int`）

保持标准 Gateway API 声明不变，用于定义外网入口域名 `*.team1.caep.uk`。

```yaml
apiVersion: gateway.networking.k8s.io/v1alpha2
kind: ListenerSet
metadata:
  name: team1-listenerset
  namespace: abjx-listenerset-int
spec:
  parentRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: gke-shared-gateway
    namespace: istio-system
  listeners:
    - name: https
      hostname: "*.team1.caep.uk"
      port: 443
      protocol: HTTPS
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              tenant: team1
      tls:
        mode: Terminate
        certificateRefs:
          - group: ""
            kind: Secret
            name: team1-wildcard-cert
            namespace: abjx-listenerset-int

```

---

### 三、 Ambient 模式下的 HTTPRoute 配置

#### 1. 场景一：API 经过 KongDP (`api1`)

流量在 Istio Ingress Gateway 解密后，转发到 KongDP 的 **HTTP 明文端口** (`8000`)。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api1-via-kong-route
  namespace: 110139-int
  labels:
    app: api1
    tenant: team1
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listenerset
      namespace: abjx-listenerset-int
      sectionName: https
  hostnames:
    - "api1.team1.caep.uk"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api1
      backendRefs:
        - name: kong-dp-svc
          namespace: kong-system  # Kong 部署在 Mesh 外部 Namespace
          port: 8000              # 由 8443(HTTPS) 切换为 8000(HTTP 明文)
          weight: 1
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: X-Tenant
                value: team1
              - name: X-Gateway-Source
                value: team1-listenerset

```

#### 2. 场景二：API 绕过 Kong，直连 Runtime (`api2`)

流量直接指向 Runtime Pod 的 **HTTP 明文端口** (`80`)。当流量从 Istio Gateway 发出并进入 Runtime 节点时，由 **ztunnel 自动接管并打上 HBONE (mTLS)** 隧道包。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api2-direct-runtime-route
  namespace: 110139-int
  labels:
    app: api2
    tenant: team1
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listenerset
      namespace: abjx-listenerset-int
      sectionName: https
  hostnames:
    - "api2.team1.caep.uk"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api2
      backendRefs:
        - name: app2-runtime-service  # 直连 Ambient 纳管下的业务服务
          port: 80                    # 由 8443/443(HTTPS) 切换为 80(HTTP 明文)
          weight: 1
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: X-Tenant
                value: team1
              - name: X-Gateway-Source
                value: team1-listenerset

```

---

### 四、 KongDP 端 Upstream 映射配置 (Declarative / DB-less 示例)

在方案 A 中，Kong 作为外部 Gateway，向 Ambient 纳管的 `app1-runtime-service` 发起请求时，也统一改用 **HTTP 明文** 端口。

```yaml
_format_version: "3.0"
services:
  - name: api1-upstream-service
    # 指向 Ambient 环境中的 Runtime 服务，改为明文 http:// 协议及 80 端口
    url: http://app1-runtime-service.110139-int.svc.cluster.local:80
    routes:
      - name: api1-kong-route
        paths:
          - /api1
        strip_path: false

```

---

### 五、 业务层 Runtime Deployment & Service YAML

业务 Pod 完全解耦 HTTPS/TLS，直接暴露明文 HTTP 端口。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app1-runtime
  namespace: 110139-int
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app1-runtime
  template:
    metadata:
      labels:
        app: app1-runtime
    spec:
      containers:
        - name: app
          image: your-registry/api1-runtime:v1.0
          ports:
            - containerPort: 80 # 仅监听明文 HTTP 端口
---
apiVersion: v1
kind: Service
metadata:
  name: app1-runtime-service
  namespace: 110139-int
spec:
  ports:
    - port: 80
      targetPort: 80
      name: http
  selector:
    app: app1-runtime

```

---

### 六、 总结与注意事项

1. **全面废弃 `DestinationRule**`：在旧模式中写在 `DestinationRule` 里的 `tls.mode: SIMPLE` 或 `MUTUAL` **无需再保留**，直接删掉对应资源即可。
2. **端口一致性**：所有内部网络组件（Istio Gateway 出口、Kong Upstream、Runtime Service）的后端通信端口统一下调为明文 HTTP 端口（如 `80`/`8000`）。
3. **安全闭环**：虽然 Kong 到 Runtime 节点间发送的是明文 HTTP，但只要数据包触达 Runtime 宿主机的网络层，即被节点级 **ztunnel 透明拦截**并在内部完成隔离传输，代码无感知。


### networkpolicy 
在 Kubernetes 集群中，一旦实施了默认的 `Default Deny All` 网络策略（Network Policy），所有 Pod 的入站（Ingress）和出站（Egress）流量默认都会被阻断。

在 **Istio Ambient 模式**下，网络层发生了重大变化：**节点级代理 `ztunnel` 会拦截并使用 HBONE 协议（默认端口 `15008`）在 Pod/节点之间传输流量**。如果 Network Policy 过于严格，可能会直接阻断 `ztunnel` 的工作，或者阻断 KongDP 到业务 Pod 的连接。

针对您的架构（**Istio Gateway ➔ KongDP ➔ Ambient Runtime / 直连 Runtime**），为了在保持“零信任（Zero-Trust）/ Deny All”原则的同时让业务正常通畅，以下是需要特殊配置或放行的 Network Policy 清单：

---

### 1. 特殊 Network Policy 配置汇总表

| 策略名称 / 作用对象 | 流量方向 | 源 / 目的 (Source / Destination) | 开放端口 / 协议 | 配置目的与说明 |
| --- | --- | --- | --- | --- |
| **① ztunnel 容器层通信放行**<br>*(应用在 Ambient Namespace)* | **Ingress** | **源**：同节点/跨节点的 `ztunnel` Pods / Nodes | **15008/TCP** (HBONE)<br>**15006/TCP** (Inbound Plaintext/mTLS) | **【Ambient 特有】** 放行 ztunnel 投递给 Pod 的 HBONE 加密隧道流量及底层健康检查流量。 |
| **② Istio Gateway ➔ KongDP**<br>*(应用在 KongDP Namespace)* | **Ingress** | **源**：Istio Ingress Gateway (`istio-system`) | **8000/TCP** (Kong HTTP 端口) | 放行经过 `/api1` 匹配后，从 Istio 网关路由到 KongDP 的流量。 |
| **③ KongDP ➔ Ambient Runtime**<br>*(应用在 Runtime Namespace)* | **Ingress** | **源**：KongDP Pods (`kong-system`) | **80/TCP** (Runtime 明文端口) | **【方案 A 核心】** Kong 位于 Mesh 外，向 Ambient 内部 Pod 发起 HTTP 请求，需显式放行 Kong 的 IP/Pod 标签。 |
| **④ Istio Gateway ➔ Ambient Runtime**<br>*(应用在 Runtime Namespace)* | **Ingress** | **源**：Istio Ingress Gateway (`istio-system`) | **80/TCP** (Runtime 明文端口) | **【直连场景】** 放行绕过 KongDP (`/api2`) 直接指向 Runtime Pod 的入口流量。 |
| **⑤ Runtime ➔ DNS / K8s API**<br>*(应用在 Runtime Namespace)* | **Egress** | **目的**：`kube-dns` (`kube-system`) | **53/UDP & TCP** | 放行所有业务 Pod 和网关的基础域名解析需求（如果默认限制了 Egress）。 |

---

### 2. 核心 Network Policy YAML 配置示例

#### 特别注意：Ambient 模式下的网络策略踩坑点

传统 Envoy Sidecar 模式下，流量经过 Sidecar 注入，Network Policy 看到的是 Envoy 容器的流量。
在 **Ambient 模式**下，网络拦截发生在**节点网络层（CNI + eBPF/iptables）**：

* 流量进入 Pod 之前，`ztunnel` 会先在宿主机侧将其解包（解密 HBONE）。
* 当流量进入 Runtime Pod 时，网络策略引擎（如 Calico / Cilium / GKE Dataplane V2）**看到的是原始发送方（如 KongDP 或 Gateway）的源 IP，以及目标 Pod 的真实端口（80）**。
* 因此，Network Policy 依然按照**业务真实端口（如 80）**以及**真实源 Pod 标签/Namespace** 来写即可，同时必须额外放行 `ztunnel` 的控制/隧道端口（`15008`）。

---

#### 策略一：Runtime Namespace - 许可源头流量与 Ambient ztunnel 隧道

部署在业务租户 Namespace（`110139-int`）：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ambient-and-gateways-to-runtime
  namespace: 110139-int
spec:
  podSelector:
    matchLabels:
      app: app1-runtime # 选择您的业务 Pod
  policyTypes:
    - Ingress
  ingress:
    # 1. 放行 ztunnel 节点的 HBONE 机制隧道端口（Ambient 内部通信必需）
    - ports:
        - protocol: TCP
          port: 15008
        - protocol: TCP
          port: 15006
    # 2. 允许来自 KongDP (Mesh 外) 的流量访问业务 80 端口
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kong-system
          podSelector:
            matchLabels:
              app: kong-dp
      ports:
        - protocol: TCP
          port: 80
    # 3. 允许来自 Istio Ingress Gateway (直连 bypassing 场景) 的流量访问业务 80 端口
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
          podSelector:
            matchLabels:
              app: istio-ingressgateway
      ports:
        - protocol: TCP
          port: 80

```

---

#### 策略二：KongDP Namespace - 许可来自 Istio Gateway 的流量

部署在 Kong 所在 Namespace（`kong-system`）：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-istio-gateway-to-kong
  namespace: kong-system
spec:
  podSelector:
    matchLabels:
      app: kong-dp
  policyTypes:
    - Ingress
  ingress:
    # 允许来自 Tier 1 Istio Gateway 的访问
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
          podSelector:
            matchLabels:
              app: istio-ingressgateway
      ports:
        - protocol: TCP
          port: 8000 # KongDP 的明文 HTTP 监听端口

```

---

### 总结建议

1. **不用改变编写习惯**：在 GKE / CNI 环境下，由于 ztunnel 在节点侧已经把 HBONE 解包还原为明文 IP 包，您针对业务 Pod 配置 Network Policy 时，**直接按照真实的来源（如 Kong/Gateway）和目标端口（如 80）编写即可**。
2. **唯一特殊点**：一定要确保集群没有阻断 `ztunnel` 所在的 DaemonSet 与业务 Pod 之间的 `15008` (HBONE) 和 `15006` 端口通信，否则 Ambient 的数据面隧道建立会失败。