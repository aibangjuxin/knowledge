# Compare and Migrate: Reverse Proxy vs. Forward Proxy

## 1. 核心概念对比：真相代理 (Truth Proxy) vs. 反向代理 (Reverse Proxy)

在网络架构中，"代理"的角色决定了谁拥有连接的"控制权"和"知情权"。我们用 **"真相" (Truth)** 来比喻**目的地地址**的可见性。

### 1.1 反向代理 (Reverse Proxy) - 模式 A (Hidden Truth)
**"客户端无需知道真相，服务器替你完成一切。"**

*   **定义**：客户端将代理服务器视为**最终目的地**。客户端不知道真实的服务端在哪里，甚至不知道背后有代理的存在。
*   **机制**: 业务代码向内部 Nginx 发起普通的 HTTPS 请求。Nginx 负责 URL 重写 (`rewrite`) 和 转发 (`proxy_pass`) 到 Squid，最后由 Squid 出网。
*   **代码视角**:
    ```python
    # 伪代码：反向代理模式 - 只有 url 是特殊的，behavior 就像访问普通网站
    requests.post("https://dev-microsoft.gcp.cloud.env.aibang/login/...") 
    ```

### 1.2 正向代理 (Forward Proxy) - 模式 B (Explicit Truth)
**"客户端知道真相，并主动寻求代理的帮助。"**

*   **定义**：客户端明确知道**最终目的地**是谁，但无法直接到达，于是主动连接代理服务器，请它帮忙中转。
*   **机制**: 业务代码利用 HTTP 协议的 `CONNECT` 方法，告诉 Squid："我想去 Microsoft，请帮我建立隧道"。
*   **代码视角**:
    ```python
    # 伪代码：正向代理模式 - URL 是真实的 Microsoft 地址，但配置了 proxy
    requests.post(
        "https://login.microsoftonline.com/...",
        proxies={"https": "http://microsoft.intra.aibang.local:3128"}
    )
    ```

---

## 2. 深度流程分析与可视化

### 2.1 Mode A: 现有反向代理链路 (Legacy Flow)
这个模式是对遗留代码最友好的，因为代码不需要改动，但架构最复杂（双跳）。

```mermaid
sequenceDiagram
    participant App as GKE App Pod
    participant Nginx as Internal Nginx (Reverse Proxy)
    participant SquidGKE as Squid Service (GKE)
    participant Microsoft as Microsoft Online

    Note over App, Nginx: Phase 1: Client Request (Reflects Internal Truth)
    App->>Nginx: GET https://dev-microsoft.gcp.../token
    activate Nginx
    
    Note over Nginx: Review & Rewrite:<br/>1. Rewrite Host -> login.microsoftonline.com<br/>2. Prepare Proxy Request
    
    Note over Nginx, SquidGKE: Phase 2: Nginx as Proxy Client
    Nginx->>SquidGKE: CONNECT login.microsoftonline.com:443
    activate SquidGKE
    
    Note over SquidGKE, Microsoft: Phase 3: Tunnel Establishment
    SquidGKE->>Microsoft: TCP Connection
    activate Microsoft
    Microsoft-->>SquidGKE: OK
    deactivate Microsoft
    
    SquidGKE-->>Nginx: HTTP/1.1 200 Connection Established
    deactivate SquidGKE
    
    Note over Nginx, Microsoft: Phase 4: Data Transmission (Proxied)
    Nginx->>Microsoft: [Encrypted Payload Via Tunnel]
    activate Microsoft
    Microsoft-->>Nginx: [Response Payload]
    deactivate Microsoft
    
    Nginx-->>App: HTTP 200 OK (Clean Response)
    deactivate Nginx
```

### 2.2 Mode B: 目标正向代理链路 (Target Flow)
这个模式是云原生推荐的，符合 "Smart Endpoint, Dumb Pipes" 原则。

```mermaid
sequenceDiagram
    participant App as GKE App Pod
    participant DNS as Cloud DNS
    participant SquidGKE as Squid Service (GKE)
    participant Microsoft as Microsoft Online

    Note over App: Phase 1: Env & DNS Definition
    Note over App: Check HTTP_PROXY=<br/>microsoft.intra.aibang.local:3128
    
    App->>DNS: Resolve microsoft.intra.aibang.local
    activate DNS
    DNS-->>App: Return 10.68.x.x (ClusterIP)
    deactivate DNS

    Note over App, SquidGKE: Phase 2: Direct Tunnel Request
    App->>SquidGKE: CONNECT login.microsoftonline.com:443
    activate SquidGKE
    
    Note over SquidGKE: ACL Check:<br/>Allowed Domain?<br/>Allowed Source?

    Note over SquidGKE, Microsoft: Phase 3: Tunnel Establishment
    SquidGKE->>Microsoft: TCP Connection
    activate Microsoft
    Microsoft-->>SquidGKE: OK
    deactivate Microsoft

    SquidGKE-->>App: HTTP/1.1 200 Connection Established
    deactivate SquidGKE

    Note over App, Microsoft: Phase 4: Direct Secure Transmission
    App->>Microsoft: [Encrypted Payload Direct]
    activate Microsoft
    Microsoft-->>App: [Response Payload]
    deactivate Microsoft
```

### 2.3 架构对比 (Topology View)

```mermaid
graph TB
    subgraph "Legacy Mode A: Reverse Proxy Path"
        A1[App Pod]
        N1["Nginx Reverse Proxy<br/>(Termination Point)"]
        S1[Squid Proxy]
        
        A1 -->|1. Internal HTTPS| N1
        N1 -->|2. Proxy Request| S1
        
        style A1 fill:#e1f5fe
        style N1 fill:#fff9c4,stroke:#fbc02d
        style S1 fill:#f3e5f5
    end

    subgraph "Target Mode B: Forward Proxy Path"
        A2[App Pod]
        S2[Squid Proxy]
        
        A2 -->|1. Proxy Tunnel Request| S2
        
        style A2 fill:#e1f5fe
        style S2 fill:#f3e5f5
    end
    
    subgraph "Internet Destination"
        Target[Microsoft Online<br/>login.microsoftonline.com]
    end

    S1 -->|3. Egress| Target
    S2 -->|2. Egress| Target
    
    style Target fill:#e8f5e8
```

---

## 3. 迁移决策流程图 (Decision Flow)

这个流程图展示了代码或配置应该如何根据环境自动选择模式。

```mermaid
flowchart TD
    Start[应用启动 / 发起请求] --> CheckEnv{检查环境变量<br/>HTTP_PROXY / HTTPS_PROXY?}
    
    CheckEnv -->|存在| ModeB[Mode B: 正向代理模式]
    CheckEnv -->|不存在| CheckConfig{检查配置文件<br/>是否强制指定 Proxy?}
    
    CheckConfig -->|是| ModeB
    CheckConfig -->|否| ModeA["Mode A: 反向代理模式<br/>(Legacy Fallback)"]
    
    subgraph "Mode B Execution"
        ModeB --> ResolveProxy[解析代理地址<br/>microsoft.intra.aibang.local]
        ResolveProxy --> ConnectProxy[CONNECT 目标域名<br/>login.microsoftonline.com]
        ConnectProxy --> SuccessB[建立隧道通信]
    end
    
    subgraph "Mode A Execution"
        ModeA --> UseInternalUrl[使用内部 URL<br/>dev-microsoft.gcp...]
        UseInternalUrl --> ConnectNginx[连接 Nginx]
        ConnectNginx --> SuccessA[接收透传响应]
    end
    
    style ModeB fill:#c8e6c9,stroke:#2e7d32
    style ModeA fill:#ffccbc,stroke:#d84315
    style Start fill:#e3f2fd
```

---

## 4. 迁移策略 (Migration Strategy)

### 4.1 基础设施层
*   **Done**: 你已经部署了 Squid 并且验证了 `curl -x` (Mode B) 是通的。
*   **To Do**: 确保 Squid 的 ACL 规则覆盖了所有 `cache_peer` 的场景，因为 Mode A 中 Nginx 可能隐藏了一些 header 或 path 逻辑，Mode B 中这些由客户端直接发起，必须确保 Squid 允许这些流量。

### 4.2 代码层适配 (关键)
这是迁移的核心。由于我们不能强迫所有业务代码立刻重写，我们需要设计一个**兼容层**。

**设计理念**：
1.  **优先正向代理**: 如果检测到 `HTTP_PROXY` 或 `HTTPS_PROXY` 环境变量，则认为应用具备出网能力，直接使用真实 URL + 代理配置。
2.  **回退反向代理**: 如果没有这些变量，或者显式配置了 `FORCE_REVERSE_PROXY`，则使用为了兼容保留的 Nginx 内部域名。
3.  **配置模板化**: 将 "目标地址" 从硬编码字符串提取为配置项。

### 4.3 环境变量注入 (Kubernetes)
GKE `ConfigMap` 示例:

```yaml
# 推荐的 Pod 环境变量配置
env:
  - name: MICROSOFT_AUTH_URL
    # 迁移后，这个值应该是真实的 URL
    value: "https://login.microsoftonline.com/<tenant_id>/oauth2/v2.0/token"
  - name: HTTPS_PROXY
    # 你的正向代理地址
    value: "http://microsoft.intra.aibang.local:3128"
  - name: NO_PROXY
    # 确保内部服务不走代理
    value: ".cluster.local,.svc,.internal,10.0.0.0/8,127.0.0.1,localhost"
```

如果代码还未改造（必须用 Mode A），则环境变量设为：
```yaml
env:
  - name: MICROSOFT_AUTH_URL
    value: "https://dev-microsoft.gcp.cloud.env.aibang/login/<tenant_id>/oauth2/v2.0/token"
  # 不设置 HTTPS_PROXY
```

---

## 5. Python 代码模拟与适配示例

为了演示这种"双模"兼容性，我们将编写一个 Python 脚本 (`proxy_simulator.py`)。它展示了如何编写一段既能适应旧环境（反向代理），又能无缝迁移到新环境（正向代理）的代码。

*(请参考同目录下的 proxy_simulator.py)*
