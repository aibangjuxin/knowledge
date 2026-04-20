https://claude.ai/public/artifacts/03952fd0-9f57-41ed-848f-b73c59f0bc9f

外部客户端HTTPS 请求 *.team-a.appdev.aibang

1 HTTPS / TLS(外部证书)namespace: istio-ingressgateway-intIstio Gateway PodTLS SIMPLE 终止 · 持有域名证书Envoy SidecarSPIFFE 身份 · 持有 istiod 颁发证书明文istiod CA(SDS)→ 自动签发 SPIFFE 证书,每 24h 轮转,存于 Sidecar 内存,不落盘,不可见

2 mTLS(自动加密)SPIFFE 双向证书验证NetworkPolicyL3/L4 仅放行 :8443namespace: team-a-runtimePeerAuthenticationSTRICT — 强制 mTLS,无证书即拒绝AuthorizationPolicydefault-deny-all + allow gateway SABusiness PodEnvoy Sidecar接收 mTLS 流量验证 SPIFFE 证书

3 明文localhost业务容器 AppHTTP :8443(明文)完全感知不到 mTLSiptables 规则由 istio-init 注入,自动拦截所有出入站流量至 Sidecar(App 无感知)安全层说明1 外部 TLS(SIMPLE)客户端 → Gateway 终止。使用业务域名证书(team-a 独立证书)。Gateway 之后无外部 TLS。

2 网格内 mTLS(自动)Sidecar ↔ Sidecar 自动加密。istiod 颁发 SPIFFE 证书,无需手动配置。PeerAuthentication STRICT 强制。

3 Pod 内明文(localhost)Sidecar → App 容器,走 localhost,不经过网络,安全边界由 Sidecar 保障。双层防护NetworkPolicy(L3/L4)+ AuthorizationPolicy(L7 SPIFFE)同时生效,互为补充。



我需要你现在读这个flow,这个其实是我的一个在GKE里面用Istio service mesh的一个flow流,也就是我关心的它一些流向和加密的一个方式。那么如果我是在GKE里边安装了不是Gloo,而且是Gloo的企业版本的话,那么它这个对应的follow应该是什么样的呢?我比较关心。你可以先帮我生成对应的Markdown的follow流,然后也可以生成SVG。


无法直接访问这个 artifact 链接。能否把那个 flow 的内容贴到对话里？或者描述一下它的主要流程节点？

同时，为了让我生成的 Gloo Enterprise 对应 flow 更准确，帮我确认几点：我先基于你描述的场景（GKE + Istio service mesh，关注流向和加密方式）以及 Gloo Enterprise 的架构特性，给你生成对应的完整 flow。我会覆盖 **标准 Istio flow** 和 **Gloo Enterprise 替换后的 flow** 的对比，方便你直接理解差异。现在我基于 Istio service mesh 的标准架构和 Gloo Enterprise 的特性，为你生成完整的对比 Flow。先输出 Markdown，再渲染 SVG。

---

## Istio vs Gloo Enterprise：GKE 流量 & 加密 Flow 对比

### 架构对比概览

| 层级         | Istio（原生）                        | Gloo Enterprise（替换后）                |
| ------------ | ------------------------------------ | ---------------------------------------- |
| 入口控制器   | Istio Ingress Gateway（Envoy）       | Gloo Gateway（基于 Envoy，扩展企业能力） |
| mTLS         | PeerAuthentication + DestinationRule | GlooMesh mTLS（跨集群，证书统一管理）    |
| 流量策略     | VirtualService / DestinationRule     | RouteTable / VirtualGateway              |
| 观测性       | Prometheus + Jaeger + Kiali          | Gloo Dashboard + 内置 OpenTelemetry      |
| OIDC/JWT/WAF | 需自行集成 AuthorizationPolicy       | 原生 ExtAuthPolicy（OIDC/LDAP/OPA/WAF）  |
| 证书管理     | istiod CA 或外部 cert-manager        | Gloo Mesh 内置 CA 或 Vault 集成          |
| 多集群       | 手动配置 east-west gateway           | GlooMesh 原生多集群服务发现              |

---

### Markdown Flow 文档

#### Flow 1：Istio 原生（标准三层架构）

```mermaid
graph TD
    subgraph External
        Client["外部客户端 / Internet"]
    end

    subgraph GKE-LB [GKE - Cloud Load Balancer]
        GLB["Google Cloud LB (L4/L7)\nTLS Termination"]
    end

    subgraph istio-system [Namespace: istio-system]
        IGW["Istio Ingress Gateway\n(Envoy Proxy)\nTLS/mTLS 终结"]
        ISTIOD["istiod\n(CA + xDS Control Plane)"]
    end

    subgraph app-ns [Namespace: team-a-runtime]
        SVC["Kubernetes Service"]
        POD["App Pod\n+ Envoy Sidecar\nmTLS 加密通信"]
    end

    Client -->|"HTTPS TLS"| GLB
    GLB -->|"HTTPS 或透传"| IGW
    IGW -->|"mTLS (PeerAuth)  "| POD
    ISTIOD -.->|"证书下发 xDS"| IGW
    ISTIOD -.->|"证书下发 xDS"| POD
    IGW --> SVC
    SVC --> POD
```
- ![istio_mtls_full_flow.svg](../istio_mtls_full_flow.svg)

**加密链路说明：**

```
Client → GLB: TLS 1.3（公网证书）
GLB → Istio GW: HTTPS 或 TLS 透传（取决于 GLB 配置）
Istio GW → Pod Sidecar: mTLS（istiod 签发的 SPIFFE 证书）
Pod Sidecar → App Container: 127.0.0.1 明文（进程间）
```

---

#### Flow 2：Gloo Enterprise（替换 Istio 控制面 + 增强入口）

```mermaid
graph TD
    subgraph External
        Client["外部客户端 / Internet"]
    end

    subgraph GKE-LB [GKE - Cloud Load Balancer]
        GLB["Google Cloud LB\nTLS Termination"]
    end

    subgraph gloo-system [Namespace: gloo-system]
        GGW["Gloo Gateway\n(Envoy-based)\nOIDC / WAF / JWT 校验"]
        GM["Gloo Mesh Control Plane\n证书统一管理 + xDS"]
        EXTAUTH["ExtAuthServer\nOIDC / LDAP / OPA"]
    end

    subgraph app-ns [Namespace: team-a-runtime]
        SVC["Kubernetes Service"]
        POD["App Pod\n+ Envoy Sidecar\nmTLS 加密通信"]
    end

    Client -->|"HTTPS TLS"| GLB
    GLB -->|"HTTPS 或透传"| GGW
    GGW -->|"ExtAuthPolicy 校验"| EXTAUTH
    EXTAUTH -->|"认证通过"| GGW
    GGW -->|"mTLS (GlooMesh 证书)"| POD
    GM -.->|"xDS + 证书下发"| GGW
    GM -.->|"xDS + 证书下发"| POD
    GGW --> SVC
    SVC --> POD
```

**加密链路说明：**

```
Client → GLB:       TLS 1.3（公网证书）
GLB → Gloo GW:      HTTPS 或 TLS 透传
Gloo GW:            OIDC/JWT 校验（ExtAuthPolicy）+ WAF 过滤
Gloo GW → Pod:      mTLS（Gloo Mesh 签发的 SPIFFE/SVID 证书）
Pod Sidecar → App:  127.0.0.1 明文
```

---

#### 关键差异：资源对象对比

| Istio 资源            | Gloo Enterprise 对应资源                              |
| --------------------- | ----------------------------------------------------- |
| `Gateway`             | `VirtualGateway`                                      |
| `VirtualService`      | `RouteTable`                                          |
| `DestinationRule`     | `TrafficPolicy`                                       |
| `PeerAuthentication`  | `PeerAuthentication`（兼容）或 `GlooMesh mTLS Policy` |
| `AuthorizationPolicy` | `AccessPolicy` + `ExtAuthPolicy`                      |
| `EnvoyFilter`         | `ListenerOption` / `RouteOption`                      |

---

现在渲染 SVG 可视化对比图：
- ![istio_vs_gloo_enterprise_flow.svg](./istio_vs_gloo_enterprise_flow.svg)

---

## Gloo Mesh Enterprise 完整加密 Flow（三层架构详解）

> 以下是将 Istio Service Mesh 完整替换为 **Gloo Mesh Enterprise** 后，
> 对应原始 `istio_mtls_full_flow.svg` 的等价加密流程。
> **用户请求路径不变**，仅替换网格控制面和入口网关组件。

### 整体流量路径总览

```
外部客户端
  │
  │ HTTPS 请求 *.team-a.appdev.aibang
  │
  ▼
┌─────────────────────────────────────────────────────────┐
│ ① HTTPS / TLS（外部证书）                                │
│                                                         │
│ namespace: gloo-gateway                                 │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Gloo Gateway Pod（Envoy-based，本身持有 SPIFFE 身份）│ │
│ │ VirtualGateway TLS SIMPLE 终止                      │ │
│ │ 持有域名证书 wildcard-team-a-cert                   │ │
│ │ 🆔 SPIFFE: spiffe://cluster.local/ns/gloo-gateway  │ │
│ │ 🔐 Gloo Mesh CA 签发证书（通过 istiod SDS 下发）   │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Control Plane 证书下发路径：                             │
│ mgmt-server ↔ gloo-mesh-agent（gRPC relay）            │
│ → agent 同步配置到 istiod（ns: istio-system）           │
│ → istiod 通过 SDS 自动签发 SPIFFE 证书                  │
│ → 每 24h 轮转，存于 Envoy 内存，不落盘                  │
└─────────────────────────────────────────────────────────┘
  │
  │ ② mTLS（自动加密）
  │ SPIFFE 双向证书验证（Gloo Mesh CA 签发）
  │ Gateway Pod 直接发起 mTLS（Gateway 本身即 Envoy）
  │
  ▼
┌─────────────────────────────────────────────────────────┐
│ namespace: team-a-runtime                               │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ NetworkPolicy: L3/L4 仅放行 :8443                   │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ ┌────────────────────┐  ┌────────────────────────────┐  │
│ │ PeerAuthentication │  │ AccessPolicy               │  │
│ │ STRICT             │  │ (Gloo Mesh Enterprise)     │  │
│ │ 强制 mTLS          │  │ default-deny +             │  │
│ │ 无证书即拒绝       │  │ allow gloo-gateway SA      │  │
│ └────────────────────┘  └────────────────────────────┘  │
│                                                         │
│ ┌─── Business Pod ────────────────────────────────────┐ │
│ │ ┌─────────────────┐    ③ 明文     ┌──────────────┐ │ │
│ │ │ Envoy Sidecar   │──localhost──→│ 业务容器 App │ │ │
│ │ │ 接收 mTLS 流量  │              │ HTTP :8443   │ │ │
│ │ │ 验证 SPIFFE 证书│              │ 无感知 mTLS  │ │ │
│ │ └─────────────────┘              └──────────────┘ │ │
│ │                                                     │ │
│ │ iptables 规则由 istio-init 注入（Gloo Mesh 复用）    │ │
│ │ 自动拦截所有出入站流量至 Sidecar（App 无感知）       │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Mermaid 流程图

```mermaid
graph TD
    subgraph External["外部"]
        Client["外部客户端\nHTTPS *.team-a.appdev.aibang"]
    end

    subgraph gloo-gw-ns["namespace: gloo-gateway"]
        GGW["Gloo Gateway Pod（Envoy-based）\nVirtualGateway TLS SIMPLE 终止\n持有域名证书 wildcard-team-a-cert\n🆔 SPIFFE 身份 · Gloo Mesh CA 签发"]
    end

    subgraph ctrl["Control Plane"]
        MGMT["mgmt-server\n（Management Cluster · ns: gloo-mesh）\nRootTrustPolicy 统一 CA"]
        AGENT["gloo-mesh-agent\n（Workload Cluster · ns: gloo-mesh）"]
        ISTIOD["istiod\n（ns: istio-system）"]
    end

    subgraph team-a-ns["namespace: team-a-runtime"]
        NP["NetworkPolicy\nL3/L4 仅放行 :8443"]
        PA["PeerAuthentication\nSTRICT mTLS"]
        AP["AccessPolicy\nallow gloo-gateway SA"]
        subgraph pod["Business Pod"]
            RT_SC["Envoy Sidecar\n接收 mTLS\n验证 SPIFFE"]
            APP["业务容器 App\nHTTP :8443 明文\n完全无感知 mTLS"]
        end
    end

    Client -->|"①\nHTTPS / TLS\n外部证书"| GGW
    GGW -->|"②\nmTLS 自动加密\nSPIFFE 双向验证"| RT_SC
    RT_SC -->|"③\n明文 localhost"| APP

    MGMT <-->|"gRPC relay"| AGENT
    AGENT -->|"配置同步"| ISTIOD
    ISTIOD -.->|"xDS + SDS\n证书下发 24h 轮转"| GGW
    ISTIOD -.->|"xDS + SDS\n证书下发"| RT_SC

    NP -.->|"L3/L4 过滤"| pod
    PA -.->|"强制 mTLS"| pod
    AP -.->|"L7 SPIFFE 验证"| pod
```
- ![gloo-flow-optimized.svg](./gloo-flow-optimized.svg)

### Sequence Diagram — 完整请求生命周期

```mermaid
sequenceDiagram
    participant C as 外部客户端
    participant GGW as Gloo Gateway Pod（Envoy-based）
    participant MGMT as mgmt-server
    participant AGENT as gloo-mesh-agent
    participant ISTIOD as istiod
    participant RT_SC as Runtime Envoy Sidecar
    participant APP as 业务容器 App

    Note over MGMT: 启动阶段：RootTrustPolicy 初始化 CA
    MGMT->>AGENT: gRPC relay 推送 CA 配置
    AGENT->>ISTIOD: 同步证书策略
    ISTIOD->>GGW: SDS 下发 SPIFFE 证书
    ISTIOD->>RT_SC: SDS 下发 SPIFFE 证书
    Note over GGW,RT_SC: 证书每 24h 自动轮转，内存存储

    C->>GGW: ① HTTPS 请求 *.team-a.appdev.aibang
    Note over GGW: VirtualGateway TLS SIMPLE 终止<br/>使用 wildcard-team-a-cert 证书

    Note over GGW,RT_SC: ② mTLS 自动加密<br/>SPIFFE 双向证书验证
    GGW->>RT_SC: mTLS 加密传输（Gateway 直接发起）

    Note over RT_SC: PeerAuthentication STRICT 验证<br/>AccessPolicy 检查 gloo-gateway SA
    RT_SC->>APP: ③ 明文 localhost（HTTP :8443）
    Note over APP: 完全感知不到 mTLS<br/>iptables 规则自动拦截

    APP-->>RT_SC: HTTP Response
    RT_SC-->>GGW: mTLS Response
    GGW-->>C: HTTPS Response
```

### 三层安全说明（Gloo Enterprise 版）

| 安全层                        | 说明                                                                                                                                                                   | Gloo Enterprise 配置                                           |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| **① 外部 TLS（SIMPLE）**      | 客户端 → Gloo Gateway 终止。使用业务域名证书（team-a 独立 wildcard 证书）。Gateway 之后无外部 TLS。                                                                    | `VirtualGateway` + `tls.mode: SIMPLE` + `secretName`           |
| **② 网格内 mTLS（自动）**     | Sidecar ↔ Sidecar 自动加密。**Gloo Mesh Control Plane** 通过 `RootTrustPolicy` 统一管理 CA，SDS 自动签发 SPIFFE 证书，无需手动配置。`PeerAuthentication STRICT` 强制。 | `PeerAuthentication` + `RootTrustPolicy` + Gloo Mesh CA        |
| **③ Pod 内明文（localhost）** | Sidecar → App 容器，走 localhost，不经过网络，安全边界由 Sidecar 保障。iptables 规则由 istio-init 注入（Gloo Mesh 复用 Istio 数据面机制）。                            | 自动（与 Istio 完全一致）                                      |
| **双层防护**                  | NetworkPolicy（L3/L4）+ **AccessPolicy**（L7 SPIFFE）同时生效，互为补充。                                                                                              | `NetworkPolicy` + `AccessPolicy`（替代 `AuthorizationPolicy`） |

### Istio → Gloo Enterprise 资源配置迁移对照

| 安全层      | Istio 配置                                        | Gloo Enterprise 配置                                  | 变化点                                               |
| ----------- | ------------------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------- |
| ① TLS 终止  | `Gateway` + `tls.mode: SIMPLE` + `credentialName` | `VirtualGateway` + `tls.mode: SIMPLE` + `secretName`  | CRD 名称和字段名变化，语义一致                       |
| ② mTLS 证书 | `istiod` CA 内置签发                              | `Gloo Mesh Control Plane` + `RootTrustPolicy` 统一 CA | **Enterprise 优势**：跨集群统一 CA，支持外部 CA 集成 |
| ② PeerAuth  | `PeerAuthentication` STRICT                       | `PeerAuthentication` STRICT（**兼容，不变**）         | 直接复用，无需修改                                   |
| ② 访问控制  | `AuthorizationPolicy` default-deny + allow SA     | `AccessPolicy` default-deny + allow SA                | CRD 替换，SPIFFE principals 语义一致                 |
| ② 路由规则  | `VirtualService` host/path 匹配                   | `RouteTable` host/path 匹配 + delegation              | **Enterprise 优势**：支持路由委托                    |
| ③ localhost | iptables（istio-init 注入）                       | iptables（istio-init 注入，**完全一致**）             | 不变                                                 |
| 防护叠加    | `NetworkPolicy` + `AuthorizationPolicy`           | `NetworkPolicy` + `AccessPolicy`                      | L3/L4 不变，L7 CRD 名称变化                          |

### Gloo Enterprise 关键 YAML 参考

#### VirtualGateway（替代 Istio Gateway）

```yaml
apiVersion: networking.gloo.solo.io/v2
kind: VirtualGateway
metadata:
  name: team-a-gateway
  namespace: gloo-gateway
spec:
  workloads:
  - selector:
      labels:
        app: gloo-gateway
      namespace: gloo-gateway
  listeners:
  - http: {}
    port:
      number: 443
    tls:
      mode: SIMPLE                                # ① TLS 终止（与 Istio 完全一致）
      secretName: wildcard-team-a-appdev-aibang-cert
    allowedRouteTables:
    - host: "*.team-a.appdev.aibang"
```

#### AccessPolicy（替代 AuthorizationPolicy）

```yaml
apiVersion: security.policy.gloo.solo.io/v2
kind: AccessPolicy
metadata:
  name: allow-gateway-only
  namespace: team-a-runtime
spec:
  applyToWorkloads:
  - selector:
      labels:
        app: api1-backend
  config:
    authn:
      tlsMode: STRICT                             # ② 强制 mTLS
    authz:
      allowedClients:
      - serviceAccountSelector:
          name: gloo-gateway-sa                    # 仅允许 Gateway SA
          namespace: gloo-gateway
```

#### RootTrustPolicy（Enterprise 专属：统一 CA 管理）

```yaml
apiVersion: admin.gloo.solo.io/v2
kind: RootTrustPolicy
metadata:
  name: unified-ca
  namespace: gloo-mesh
spec:
  config:
    intermediateCertOptions:
      secretType: Opaque
    mgmtServerCa:
      generated:
        ttlDays: 365                               # CA 有效期
    autoRestartPods: true                           # CA 轮换时自动重启 Pod
```

### 核心结论

> [!IMPORTANT]
> **Gloo Mesh Enterprise 替换 Istio 后，三层加密架构完全保持不变**：
> - ① 外部 TLS SIMPLE 终止 → `VirtualGateway`（等价替换 `Gateway`）
> - ② 网格内 mTLS 自动加密 → `Gloo Mesh CA` + `PeerAuthentication STRICT`（证书管理升级，PeerAuth 直接兼容）
> - ③ Pod 内 localhost 明文 → 完全不变
>
> **唯一的本质区别**：证书签发从 `istiod 内置 CA` 升级为 `Gloo Mesh Control Plane + RootTrustPolicy`，
> 支持跨集群统一 CA、外部 CA 集成（Vault/cert-manager）、集中式证书轮换管理。
> 数据面（Envoy Sidecar + iptables 拦截）**完全不变**。

---

## Gloo Mesh Enterprise 可视化 Flow 图集

### 🔷 图 1：North-South 完整流量路径（带加密标注）

```mermaid
graph TD
    Client["🌐 外部客户端\nHTTPS *.team-a.appdev.aibang"]

    subgraph TLS_Zone["🟠 Zone 1 — 外部 TLS 加密区"]
        direction TB
        GLB["☁️ Google Cloud LB\nTLS 1.3 终止 或 透传"]
    end

    subgraph GW_Zone["🔵 Zone 2 — Gloo Gateway（ns: gloo-gateway）"]
        direction TB
        GGW["🚪 Gloo Gateway Pod（Envoy-based）\n📜 VirtualGateway TLS SIMPLE 终止\n🔑 wildcard-team-a-cert\n🆔 SPIFFE: spiffe://cluster.local/ns/gloo-gateway/sa/gloo-gw-sa\n🔐 Gloo Mesh CA 签发"]
    end

    subgraph MESH_Zone["🟢 Zone 3 — Mesh mTLS 加密区（ns: team-a-runtime）"]
        direction TB
        NP["🧱 NetworkPolicy\nL3/L4: 仅放行 TCP :8443"]
        PA["🔒 PeerAuthentication\nSTRICT — 无证书即拒绝"]
        AP["🎫 AccessPolicy\n仅允许 gloo-gateway SA"]
        RT_SC["🛡️ Runtime Envoy Sidecar\n🆔 SPIFFE: spiffe://cluster.local/ns/team-a-runtime/sa/default\n🔐 验证对端 SPIFFE 身份"]
    end

    subgraph APP_Zone["🟡 Zone 4 — Pod 内明文区"]
        direction TB
        APP["📦 业务容器 App\nHTTP :8443 明文\n✨ 完全无感知加密"]
    end

    subgraph CTRL["⚙️ Control Plane"]
        MGMT["🧠 mgmt-server\n（Management Cluster）"]
        AGENT["📡 gloo-mesh-agent\n（Workload Cluster）"]
        ISTIOD["🎛️ istiod\n（ns: istio-system）"]
    end

    Client -->|"🔸 HTTPS TLS 1.3\n公网证书"| GLB
    GLB -->|"🔸 HTTPS / 透传"| GGW
    GGW -->|"🔹 mTLS\nSPIFFE 双向验证\nAES-256-GCM"| RT_SC
    NP -.->|"L3/L4"| RT_SC
    PA -.->|"mTLS 强制"| RT_SC
    AP -.->|"L7 SA 验证"| RT_SC
    RT_SC -->|"🔸 明文\n127.0.0.1"| APP

    MGMT <-->|"gRPC relay"| AGENT
    AGENT -->|"配置同步"| ISTIOD
    ISTIOD -.->|"xDS + SDS"| GGW
    ISTIOD -.->|"xDS + SDS"| RT_SC

    style Client fill:#2d2d2d,stroke:#e0e0e0,color:#fff
    style GLB fill:#4a90d9,stroke:#2a5fa8,color:#fff
    style GGW fill:#6c5ce7,stroke:#5341d6,color:#fff
    style NP fill:#636e72,stroke:#4a5459,color:#fff
    style PA fill:#00cec9,stroke:#00b3ad,color:#fff
    style AP fill:#e17055,stroke:#c0553e,color:#fff
    style RT_SC fill:#00b894,stroke:#009a7d,color:#fff
    style APP fill:#fdcb6e,stroke:#d4a84e,color:#333
    style MGMT fill:#6c5ce7,stroke:#5341d6,color:#fff
    style AGENT fill:#a29bfe,stroke:#8a82e5,color:#fff
    style ISTIOD fill:#ffeaa7,stroke:#dcc47a,color:#333
```

### 🔷 图 2：Gloo Mesh 证书生命周期

```mermaid
graph LR
    subgraph Control["🧠 Gloo Mesh Control Plane"]
        RTP["📋 RootTrustPolicy\nCA 根证书 TTL=365d"]
        MGMT["⚙️ gloo-mesh-mgmt-server\n统一 CA 管理"]
    end

    subgraph SDS["🔄 SDS 证书分发"]
        direction TB
        SDS_GW["📤 SDS → Gateway Sidecar"]
        SDS_RT["📤 SDS → Runtime Sidecar"]
    end

    subgraph Certs["🔐 SPIFFE 证书"]
        CERT_GW["🆔 Gateway 证书\nspiffe://cluster.local\n/ns/gloo-gateway\n/sa/gloo-gw-sa\nTTL: 24h"]
        CERT_RT["🆔 Runtime 证书\nspiffe://cluster.local\n/ns/team-a-runtime\n/sa/default\nTTL: 24h"]
    end

    subgraph Storage["💾 存储方式"]
        MEM["🧠 内存存储\n不落盘 · 不可见\nSidecar 重启即更新"]
    end

    RTP --> MGMT
    MGMT --> SDS_GW
    MGMT --> SDS_RT
    SDS_GW --> CERT_GW
    SDS_RT --> CERT_RT
    CERT_GW --> MEM
    CERT_RT --> MEM

    style RTP fill:#6c5ce7,stroke:#5341d6,color:#fff
    style MGMT fill:#a29bfe,stroke:#8a82e5,color:#fff
    style SDS_GW fill:#74b9ff,stroke:#5ca4e5,color:#fff
    style SDS_RT fill:#74b9ff,stroke:#5ca4e5,color:#fff
    style CERT_GW fill:#00b894,stroke:#009a7d,color:#fff
    style CERT_RT fill:#00b894,stroke:#009a7d,color:#fff
    style MEM fill:#ffeaa7,stroke:#dcc47a,color:#333
```

### 🔷 图 3：安全防护层级纵深

```mermaid
graph TB
    subgraph L1["🟠 Layer 1 — 网络边界"]
        FW["🔥 GCP Firewall Rules\n仅允许 GLB IP 范围"]
        CA_WAF["🛡️ Cloud Armor / WAF\nDDoS 防护 · IP 黑白名单"]
    end

    subgraph L2["🔵 Layer 2 — TLS 加密"]
        TLS_EXT["🔐 外部 TLS 1.3\n公网证书 · 客户端验证"]
        TLS_GW["🔐 Gateway TLS SIMPLE\n域名 wildcard 证书终止"]
    end

    subgraph L3["🟢 Layer 3 — Mesh mTLS"]
        MTLS["🔒 mTLS 双向认证\nSPIFFE 证书 · AES-256-GCM\nGloo Mesh CA 签发"]
        PEER["✅ PeerAuthentication STRICT\n无证书流量 → 拒绝"]
    end

    subgraph L4["🟣 Layer 4 — Kubernetes 策略"]
        NETPOL["🧱 NetworkPolicy\nL3/L4 端口白名单 :8443"]
        ACCPOL["🎫 AccessPolicy\nL7 SPIFFE 身份验证\n仅允许指定 SA"]
    end

    subgraph L5["🟡 Layer 5 — Pod 隔离"]
        NS["📁 Namespace 隔离\nWorkspace 租户边界"]
        SIDECAR["🛡️ Sidecar iptables\n所有流量强制经过 Envoy"]
    end

    L1 --> L2
    L2 --> L3
    L3 --> L4
    L4 --> L5

    style FW fill:#d63031,stroke:#b52727,color:#fff
    style CA_WAF fill:#e17055,stroke:#c0553e,color:#fff
    style TLS_EXT fill:#0984e3,stroke:#0972c7,color:#fff
    style TLS_GW fill:#6c5ce7,stroke:#5341d6,color:#fff
    style MTLS fill:#00b894,stroke:#009a7d,color:#fff
    style PEER fill:#00cec9,stroke:#00b3ad,color:#fff
    style NETPOL fill:#636e72,stroke:#4a5459,color:#fff
    style ACCPOL fill:#e17055,stroke:#c0553e,color:#fff
    style NS fill:#fdcb6e,stroke:#d4a84e,color:#333
    style SIDECAR fill:#ffeaa7,stroke:#dcc47a,color:#333
```

### 🔷 图 4：East-West Mesh 内部流量加密

```mermaid
graph LR
    subgraph NS_A["namespace: team-a-runtime"]
        POD_A["📦 Pod A\n+ Envoy Sidecar"]
    end

    subgraph NS_B["namespace: team-b-runtime"]
        POD_B["📦 Pod B\n+ Envoy Sidecar"]
    end

    subgraph gloo-mesh["namespace: gloo-mesh"]
        GMCP["🧠 Gloo Mesh CP\n统一 CA\nRootTrustPolicy"]
    end

    subgraph Workspace_A["Workspace: team-a"]
        WS_A["📋 WorkspaceSettings\nexportTo: team-b"]
    end

    subgraph Workspace_B["Workspace: team-b"]
        WS_B["📋 WorkspaceSettings\nimportFrom: team-a"]
    end

    POD_A <-->|"🔒 mTLS\nSPIFFE 双向验证\n自动加密"| POD_B
    GMCP -.->|"证书签发"| POD_A
    GMCP -.->|"证书签发"| POD_B
    WS_A -.->|"服务导出"| WS_B

    style POD_A fill:#00b894,stroke:#009a7d,color:#fff
    style POD_B fill:#0984e3,stroke:#0972c7,color:#fff
    style GMCP fill:#6c5ce7,stroke:#5341d6,color:#fff
    style WS_A fill:#fdcb6e,stroke:#d4a84e,color:#333
    style WS_B fill:#74b9ff,stroke:#5ca4e5,color:#fff
```

### 🔷 图 5：完整请求加密区域标注图

```mermaid
graph TD
    Client["🌐 Client"]

    subgraph RED["🔴 公网 — TLS 1.3 加密"]
        GLB["☁️ GCP LB"]
    end

    subgraph PURPLE["🟣 Gateway — TLS SIMPLE 终止"]
        GGW["🚪 Gloo Gateway\nVirtualGateway\n（Envoy-based）"]
    end

    subgraph GREEN["🟢 Mesh — mTLS SPIFFE 自动加密"]
        GGW2["🛡️ Gateway Envoy"] --> RTSC["🛡️ RT Sidecar"]
    end

    subgraph YELLOW["🟡 Pod — 明文 localhost"]
        APP["📦 App :8443"]
    end

    subgraph CONTROL["⚙️ Control Plane"]
        MGMT["🧠 mgmt-server"]
        AGENT["📡 agent"]
        ISTIOD["🎛️ istiod"]
    end

    Client -->|"TLS 1.3"| GLB
    GLB -->|"TLS"| GGW
    GGW -->|"mTLS"| GGW2
    RTSC -->|"localhost"| APP
    MGMT <-->|"relay"| AGENT
    AGENT -->|"sync"| ISTIOD
    ISTIOD -.->|"xDS + SDS"| GGW2
    ISTIOD -.->|"xDS + SDS"| RTSC

    style Client fill:#2d3436,stroke:#636e72,color:#fff
    style GLB fill:#d63031,stroke:#b52727,color:#fff
    style GGW fill:#6c5ce7,stroke:#5341d6,color:#fff
    style GGW2 fill:#00b894,stroke:#009a7d,color:#fff
    style RTSC fill:#00b894,stroke:#009a7d,color:#fff
    style APP fill:#fdcb6e,stroke:#d4a84e,color:#333
    style MGMT fill:#a29bfe,stroke:#8a82e5,color:#fff
    style AGENT fill:#00cec9,stroke:#00b3ad,color:#fff
    style ISTIOD fill:#ffeaa7,stroke:#dcc47a,color:#333
```

### 🔷 图 6：Gloo Gateway 请求处理管线

```mermaid
graph LR
    REQ["📨 入站请求"] --> TLS_T["🔐 TLS 终止\nVirtualGateway\nSIMPLE mode"]
    TLS_T --> RT_M["📋 路由匹配\nRouteTable\nhost + path"]
    RT_M --> EXTAUTH{"🔑 ExtAuth?\nEnterprise"}
    EXTAUTH -->|"启用"| AUTH["🎫 ExtAuthPolicy\nOIDC / JWT / OPA"]
    EXTAUTH -->|"未启用"| TP
    AUTH -->|"✅ 通过"| TP
    AUTH -->|"❌ 拒绝"| DENY["🚫 403 Forbidden"]
    TP["⚡ 流量策略\nTrafficPolicy\n重试 · 超时 · 熔断"]
    TP --> MTLS_O["🔒 mTLS 发起\nGateway Envoy 加密\nSPIFFE 证书"]
    MTLS_O --> BACKEND["📦 Backend Pod"]

    style REQ fill:#2d3436,stroke:#636e72,color:#fff
    style TLS_T fill:#6c5ce7,stroke:#5341d6,color:#fff
    style RT_M fill:#0984e3,stroke:#0972c7,color:#fff
    style EXTAUTH fill:#e17055,stroke:#c0553e,color:#fff
    style AUTH fill:#fdcb6e,stroke:#d4a84e,color:#333
    style DENY fill:#d63031,stroke:#b52727,color:#fff
    style TP fill:#00cec9,stroke:#00b3ad,color:#fff
    style MTLS_O fill:#00b894,stroke:#009a7d,color:#fff
    style BACKEND fill:#55efc4,stroke:#3dd4a5,color:#333
```

### 🔷 图 7：Gloo Mesh Enterprise 组件全景

```mermaid
graph TB
    subgraph MgmtCluster["🧠 Management Cluster"]
        subgraph gloo_mesh_ns["ns: gloo-mesh"]
            MGMT["⚙️ mgmt-server\nCRD 翻译引擎"]
            UI["📊 Gloo Mesh UI\nEnterprise Dashboard"]
            RBAC_E["🔐 Enterprise RBAC\n多租户策略"]
            RTP_E["📜 RootTrustPolicy\n统一 CA"]
            TEL["📡 Telemetry Collector\nOpenTelemetry"]
        end
    end

    subgraph WkldCluster["⚡ Workload Cluster"]
        subgraph agent_ns["ns: gloo-mesh（Agent）"]
            AGENT["📡 gloo-mesh-agent\nRelay 双向同步"]
        end

        subgraph istio_ns["ns: istio-system"]
            ISTIOD_E["🎛️ istiod\nxDS + SDS Server"]
        end

        subgraph gw_ns["ns: gloo-gateway"]
            GW["🚪 Gloo Gateway\nEnvoy-based"]
        end

        subgraph Workloads["📦 Workload Namespaces"]
            W1["🟢 team-a-runtime\nPod + Sidecar"]
            W2["🔵 team-b-runtime\nPod + Sidecar"]
            W3["🟠 team-c-runtime\nPod + Sidecar"]
        end
    end

    MGMT <-->|"gRPC relay"| AGENT
    UI --> MGMT
    RBAC_E --> MGMT
    RTP_E --> MGMT
    TEL --> MGMT
    AGENT --> ISTIOD_E
    ISTIOD_E -->|"xDS"| GW
    ISTIOD_E -->|"xDS + SDS"| W1
    ISTIOD_E -->|"xDS + SDS"| W2
    ISTIOD_E -->|"xDS + SDS"| W3
    GW -->|"mTLS"| W1
    GW -->|"mTLS"| W2
    GW -->|"mTLS"| W3

    style MGMT fill:#6c5ce7,stroke:#5341d6,color:#fff
    style UI fill:#a29bfe,stroke:#8a82e5,color:#fff
    style RBAC_E fill:#fd79a8,stroke:#e06090,color:#fff
    style RTP_E fill:#e17055,stroke:#c0553e,color:#fff
    style TEL fill:#74b9ff,stroke:#5ca4e5,color:#fff
    style GW fill:#00b894,stroke:#009a7d,color:#fff
    style AGENT fill:#00cec9,stroke:#00b3ad,color:#fff
    style ISTIOD_E fill:#ffeaa7,stroke:#dcc47a,color:#333
    style W1 fill:#55efc4,stroke:#3dd4a5,color:#333
    style W2 fill:#74b9ff,stroke:#5ca4e5,color:#fff
    style W3 fill:#fab1a0,stroke:#e08e7e,color:#333
```

---

## 🏗️ Maitreya Premium Visualization

### 🔷 图 8：Gloo Mesh Enterprise 全景 (Maitreya Premium Style)

> [!TIP]
> **Maitreya 视角**：本图通过色彩分层与 `classDef` 强化了管理面（Zone 1）、网关层（Zone 2）、网格基础设施（Zone 3）与业务负载（Zone 4）的逻辑边界。
> 
> ![Gloo Mesh Enterprise Architecture Overview (Maitreya Style)](./gloo-enterprise-architecture.svg)

```mermaid
graph TB
    %% [Maitreya Style Definitions]
    classDef default font-family:Inter,font-size:13px;
    classDef mgmt fill:#2d3436,stroke:#000,color:#fff,stroke-width:2px,rx:10,ry:10;
    classDef gateway fill:#6c5ce7,stroke:#5341d6,color:#fff,stroke-width:2px,rx:10,ry:10;
    classDef mesh fill:#00b894,stroke:#009a7d,color:#fff,stroke-width:2px,rx:10,ry:10;
    classDef app fill:#fdcb6e,stroke:#d4a84e,color:#333,stroke-width:2px;
    classDef storage fill:#fab1a0,stroke:#e17055,color:#333;

    subgraph MgmtCluster ["🧠 Management Cluster (Zone 1)"]
        direction TB
        subgraph gloo_mesh_ns ["ns: gloo-mesh"]
            MGMT["⚙️ mgmt-server\n(CRD Translation)"]:::mgmt
            UI["📊 Gloo Mesh UI\n(Dashboard)"]:::mgmt
            RTP_E["📜 RootTrustPolicy\n(Unified CA)"]:::mgmt
            TEL["📡 Telemetry Collector\n(OpenTelemetry)"]:::mgmt
        end
    end

    subgraph WkldCluster ["⚡ Workload Cluster"]
        subgraph mesh_infra ["Mesh Infrastructure (Zone 3)"]
            AGENT["📡 gloo-mesh-agent\n(Relay Agent)"]:::mesh
            ISTIOD_E["🎛️ istiod\n(xDS + SDS Server)"]:::mesh
        end

        subgraph entry_points ["Entry Points (Zone 2)"]
            GW["🚪 Gloo Gateway\n(Envoy-based)"]:::gateway
        end

        subgraph workloads ["Workload Domains (Zone 4)"]
            W1["🟢 team-a-runtime\n(Pod + Sidecar)"]:::app
            W2["🔵 team-b-runtime\n(Pod + Sidecar)"]:::app
            W3["🟠 team-c-runtime\n(Pod + Sidecar)"]:::app
        end
    end

    %% [Control Plane & Relay Flow]
    MGMT <-->|"gRPC Relay\n(Bi-directional)"| AGENT
    AGENT -->|"Config Sync"| ISTIOD_E
    UI --- MGMT
    RTP_E --- MGMT

    %% [Data Plane Distribution]
    ISTIOD_E -.->|"xDS / SDS"| GW
    ISTIOD_E -.->|"xDS / SDS"| W1
    ISTIOD_E -.->|"xDS / SDS"| W2
    ISTIOD_E -.->|"xDS / SDS"| W3

    %% [North-South Traffic]
    GW ==>|"mTLS"| W1
    GW ==>|"mTLS"| W2
    GW ==>|"mTLS"| W3

    %% [Technical Insight Note]
    Note_Maitreya[Maitreya 架构见解：'浓缩铀'级别核心]
    Note_Maitreya --- K1{统一信任根: RootTrustPolicy 跨集群分发}
    Note_Maitreya --- K2{Relay 架构: 屏蔽 API Server 跨集群暴露风险}
    Note_Maitreya --- K3{无感加密: 业务 0 感知 mTLS 自动注入}

    style MgmtCluster fill:#f1f2f6,stroke:#dfe4ea,stroke-width:2px
    style WkldCluster fill:#f1f2f6,stroke:#dfe4ea,stroke-width:2px
    style Note_Maitreya fill:#fff,stroke:#e17055,stroke-width:3px
```
