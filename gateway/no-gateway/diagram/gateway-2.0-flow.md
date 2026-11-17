# Gateway 2.0 Architecture Flow

## 修正后的架构：双入口设计

```mermaid
graph TD
    %% === Client Layer ===
    A["Client (User / API Consumer)"]:::client -->|HTTPS Request| B["Google Cloud Load Balancer (GLB)"]:::glb

    %% === Security Layer ===
    B -->|TLS Termination / Cloud Armor| B1["GLB Security Layer"]:::security

    %% === Two Independent Entry Points ===
    B -->|Path = /teamA/*, /teamB/*| C["Nginx L7 (Reverse Proxy + Path Routing)"]:::nginx
    C -->|Path = /teamA/*| D["Kong Gateway"]:::kong
    C -->|Path = /teamB/*| E["GKE Gateway (Listener 443)"]:::gke

    %% === Cross-Project PSC Entry (NEW - Independent Entry Point B) ===
    PSC["PSC Attachment<br/>Cross-Project Producer"]:::psc
    PSC -->|Traffic In| IIP["IIP (Internal Ingress Proxy)<br/>This Project as Entry"]:::iip
    IIP -->|proxy_pass| G2["Gateway 2.0 (Internal ILB)"]:::gateway2

    %% === Gateway 2.0 Branches ===
    G2 -->|Path = /iip/kong/*| K2["Kong Gateway 2.0"]:::kong2
    G2 -->|Path = /iip/direct/*| R2["GKE Runtime Direct"]:::runtime2

    %% === Kong Path (Original teamA) ===
    D --> D1["Kong Upstream Service(s)"]:::kong
    D1 --> D2["GKE Runtime (Pods / Services)"]:::runtime
    D -.-> D3["Kong Policy Layer (Auth / Rate Limit / Logging / Plugin)"]:::policy

    %% === GKE Gateway Path (Original teamB) ===
    E -->|/api-healthcheck1| F["HTTPRoute Tenant A"]:::httproute
    E -->|/api2-healthcheck2| G["HTTPRoute Tenant B"]:::httproute

    F --> H["Service api-healthcheck1 (tenant-a)"]:::service
    H --> I["Runtime Pods (tenant-a ns)"]:::runtime

    G --> J["Service api2-healthcheck2 (tenant-b)"]:::service
    J --> K["Runtime Pods (tenant-b ns)"]:::runtime

    %% === Kong Gateway 2.0 Path ===
    K2 --> K2_1["Kong Gateway 2.0 Upstream"]:::kong2
    K2_1 --> K2_2["GKE Runtime (iip namespace)"]:::runtime2

    %% === GKE Runtime Direct Path ===
    R2 --> R2_1["Service iip-direct-svc (ClusterIP)"]:::service2
    R2_1 --> R2_2["Runtime Pods (iip ns)"]:::runtime2

    %% === Security Layers ===
    C -.-> S1["Nginx Security Layer (Strict Host/Path Check + Header Injection)"]:::security
    IIP -.-> S2["IIP Security Layer (Header Validation / Path Rewrite)"]:::security
    E -.-> S3["GKE Gateway Control Layer (HTTPRoute / Path Routing / Canary / Cert)"]:::control
    G2 -.-> S4["Gateway 2.0 Control Layer (Listener / TLS / Route Binding)"]:::control

    %% === Style Definitions ===
    classDef client fill:#b3d9ff,stroke:#004c99,color:#000
    classDef glb fill:#e6b3ff,stroke:#660066,color:#000
    classDef nginx fill:#ffd699,stroke:#cc7a00,color:#000
    classDef iip fill:#ffe4b5,stroke:#8b4513,color:#000
    classDef psc fill:#e6e6fa,stroke:#9370db,color:#000
    classDef kong fill:#b3ffb3,stroke:#006600,color:#000
    classDef kong2 fill:#98fb98,stroke:#006400,color:#000
    classDef gke fill:#b3e0ff,stroke:#005c99,color:#000
    classDef gateway2 fill:#87ceeb,stroke:#4682b4,color:#000
    classDef httproute fill:#99ccff,stroke:#004c99,color:#000
    classDef service fill:#99b3ff,stroke:#003366,color:#000
    classDef service2 fill:#add8e6,stroke:#4682b4,color:#000
    classDef runtime fill:#99b3ff,stroke:#003366,color:#000
    classDef runtime2 fill:#add8e6,stroke:#4682b4,color:#000
    classDef policy fill:#ccffcc,stroke:#006600,color:#000,stroke-dasharray: 3 3
    classDef security fill:#ffe6e6,stroke:#990000,color:#000,stroke-dasharray: 3 3
    classDef control fill:#cce5ff,stroke:#004c99,color:#000,stroke-dasharray: 3 3
```

## Flow Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DUAL ENTRY POINTS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Entry Point A: GLB Ingress (Original)          Entry Point B: PSC (NEW)   │
│  ═══════════════════════════════════            ════════════════════════   │
│                                                                             │
│  Client ──HTTPS──> GLB ──/teamA/*, /teamB/* ──> Nginx L7                   │
│                          │                               │                   │
│                          │                    PSC (Cross-Project)          │
│                          │                         │                        │
│                          │                    PSC Attachment               │
│                          │                         │                        │
│                          │                    IIP (This Project Entry)     │
│                          │                         │                        │
│                    ┌─────┴─────┐                    │                       │
│                    │           │                    ▼                       │
│               /teamA/*    /teamB/*           Gateway 2.0                   │
│                    │           │           ┌──────┴──────┐                  │
│                    ▼           ▼           │             │                  │
│             Kong Gateway  GKE Gateway    /iip/kong/*  /iip/direct/*         │
│                    │           │           │             │                  │
│                    ▼           ▼           ▼             ▼                  │
│             GKE Runtime  HTTPRoutes   Kong GW 2.0  GKE Runtime Direct      │
│                                    │             │                         │
│                                    ▼             ▼                         │
│                               GKE Runtime    Pods (iip ns)                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

| Entry Point | Source | Path | Destination |
|-------------|--------|------|-------------|
| **A (Original)** | GLB → Nginx L7 | /teamA/* | Kong Gateway → GKE Runtime |
| **A (Original)** | GLB → Nginx L7 | /teamB/* | GKE Gateway → HTTPRoutes |
| **B (NEW)** | PSC Attachment (Cross-Project) | /iip/* | IIP → Gateway 2.0 → Kong GW 2.0 / Direct |

```mermaid
flowchart TD
    Client["Client\nHTTPS 请求 / TLS SNI"]

    subgraph Phase1["① TLS 握手阶段"]
        GWL["GKE Gateway Listener\nhostname: *.appdev.abjx | port: 443\ncertificate: *.appdev.abjx | TLS mode: Terminate"]
    end

    subgraph Phase2["② HTTP 路由阶段 - L7 分流 Host + Path"]
        R1["HTTPRoute: api1-runtime-route\nhostnames: api1.appdev.abjx\npath: /api1/*\nfilter: 无，Host 保持不变"]
        R2["HTTPRoute: api2-kong-route\nhostnames: api2.appdev.abjx\npath: /api-path/e2e/*\nfilter: URLRewrite.hostname"]
        RW["URLRewrite 效果\nClient Host: api2.appdev.abjx\n转发 Host: www.intrakong.com\nX-Original-Host: api2.appdev.abjx"]
    end

    subgraph Phase3["③ 后端服务层"]
        SVC1["api1-runtime-svc\nGKE runtime Pod | port: 8080"]
        KONG["kong-dp-svc\nKong DP Pod | port: 8000"]
        KR["Kong Route 匹配\nhosts: www.intrakong.com\npaths: /api-path/e2e\nstrip_path: false"]
    end

    subgraph Phase4["④ Upstream"]
        UP1["API1 upstream service"]
        UP2["existing upstream APIs"]
    end

    subgraph Forbidden["❌ 禁止用法 - 原文档错误项"]
        F1["RequestHeaderModifier 修改 Host\nHost 是 forbidden header\n规范明确禁止"]
        F2["%{request.host}% 变量模板\nGKE Gateway 不支持 Envoy/Nginx 风格\n改用静态写入 X-Original-Host"]
        F3["rules.matches.hostname 无效字段\n应放在 spec.hostnames"]
        F4["RequestHeaderModifier.set 写成 map\n必须用 name/value 数组格式"]
    end

    Client -->|"HTTPS"| GWL
    GWL -->|"TLS 终止 → HTTP"| R1
    GWL -->|"TLS 终止 → HTTP"| R2
    R2 --> RW
    R1 -->|"Host: api1.appdev.abjx"| SVC1
    RW -->|"Host: www.intrakong.com"| KONG
    KONG --> KR
    SVC1 --> UP1
    KR --> UP2

    style Forbidden fill:#fff0f0,stroke:#e24b4a,stroke-dasharray:5 3
    style F1 fill:#fff0f0,stroke:#e24b4a
    style F2 fill:#fff0f0,stroke:#e24b4a
    style F3 fill:#fff0f0,stroke:#e24b4a
    style F4 fill:#fff0f0,stroke:#e24b4a
    style RW fill:#f0f0ff,stroke:#534ab7
```
