# GKE Egress 代理流程图集合

## 1. 整体架构流程图

### 1.1 系统架构概览

```mermaid
graph TB
    subgraph "GKE Cluster"
        subgraph "API Namespace"
            A[API Pod<br/>HTTP_PROXY=microsoft.intra.aibang.local:3128]
        end
        
        subgraph "intra-proxy Namespace"
            B[Squid Proxy Pod 1]
            C[Squid Proxy Pod 2]
            D[Squid Service<br/>ClusterIP: 10.96.x.x]
            B --- D
            C --- D
        end
        
        subgraph "kube-system"
            E[CoreDNS<br/>microsoft.intra.aibang.local<br/>→ squid-proxy-service]
        end
    end
    
    subgraph "GCE VM"
        F[Squid Proxy<br/>int-proxy.aibang.com:3128]
    end
    
    subgraph "Internet"
        G[login.microsoft.com<br/>External Services]
    end
    
    A -->|1 DNS Query| E
    E -->|2 Resolve to Service IP| A
    A -->|3 HTTP CONNECT| D
    D -->|4 Load Balance| B
    B -->|5 cache_peer forward| F
    F -->|6 Direct Access| G
    
    style A fill:#e1f5fe
    style D fill:#f3e5f5
    style F fill:#fff3e0
    style G fill:#e8f5e8
```

### 1.2 网络层次架构

```mermaid
graph LR
    subgraph "Layer 1: Application"
        A1[API Pod<br/>10.128.0.x]
    end
    
    subgraph "Layer 2: DNS Resolution"
        B1[CoreDNS<br/>microsoft.intra.aibang.local<br/>→ 10.96.x.x]
    end
    
    subgraph "Layer 3: GKE Proxy"
        C1[Squid Service<br/>10.96.x.x:3128]
        C2[Squid Pods<br/>ACL + cache_peer]
    end
    
    subgraph "Layer 4: GCE Proxy"
        D1[VM Squid<br/>10.128.2.100:3128]
        D2[Secondary ACL<br/>Audit Logging]
    end
    
    subgraph "Layer 5: Internet"
        E1[External Services<br/>login.microsoft.com]
    end
    
    A1 --> B1
    B1 --> C1
    C1 --> C2
    C2 --> D1
    D1 --> D2
    D2 --> E1
    
    style A1 fill:#e3f2fd
    style C1 fill:#f1f8e9
    style D1 fill:#fff8e1
    style E1 fill:#fce4ec
```

## 2. 请求处理时序图

### 2.1 HTTP CONNECT 请求流程

```mermaid
sequenceDiagram
    participant AP as API Pod
    participant DNS as CoreDNS
    participant GS as GKE Squid
    participant VS as GCE VM Squid
    participant MS as Microsoft Service
    
    Note over AP,MS: HTTPS 请求处理流程
    
    AP->>DNS: 1. DNS Query: microsoft.intra.aibang.local
    DNS->>AP: 2. Response: 10.96.x.x (Service ClusterIP)
    
    AP->>GS: 3. CONNECT login.microsoft.com:443 HTTP/1.1
    Note over GS: ACL 检查:<br/>✓ Source IP in localnet<br/>✓ Domain in allowed_domains<br/>✓ Port 443 in Safe_ports
    
    GS->>VS: 4. CONNECT login.microsoft.com:443 HTTP/1.1
    Note over VS: 二级 ACL 检查:<br/>✓ Source IP in gke_cluster<br/>✓ Domain in microsoft_domains<br/>✓ Business hours (optional)
    
    VS->>MS: 5. TCP Connect to login.microsoft.com:443
    MS->>VS: 6. TCP Connection Established
    VS->>GS: 7. HTTP/1.1 200 Connection established
    GS->>AP: 8. HTTP/1.1 200 Connection established
    
    Note over AP,MS: TCP 隧道建立，开始传输加密数据
    
    AP->>GS: 9. Encrypted HTTPS Data
    GS->>VS: 10. Forward Encrypted Data
    VS->>MS: 11. Forward to Microsoft
    MS->>VS: 12. Response Data
    VS->>GS: 13. Forward Response
    GS->>AP: 14. Forward to API Pod
    
    Note over GS,VS: 记录访问日志和审计信息
```

### 2.2 DNS 解析流程

```mermaid
sequenceDiagram
    participant AP as API Pod
    participant DNS as CoreDNS
    participant SVC as Squid Service
    participant POD as Squid Pod
    
    AP->>DNS: 1. nslookup microsoft.intra.aibang.local
    
    Note over DNS: CoreDNS 处理流程:<br/>1. 检查自定义 hosts 配置<br/>2. 匹配重写规则<br/>3. 返回 Service ClusterIP
    
    DNS->>AP: 2. A Record: 10.96.x.x
    
    AP->>SVC: 3. HTTP Request to 10.96.x.x:3128
    
    Note over SVC: Service 负载均衡:<br/>选择健康的 Pod 实例
    
    SVC->>POD: 4. Forward to selected Pod
    POD->>SVC: 5. Response
    SVC->>AP: 6. Response to API Pod
```

## 3. 数据流程图

### 3.1 请求数据流

```mermaid
flowchart TD
    A[API Pod 发起请求] --> B{检查环境变量}
    B -->|HTTP_PROXY 已设置| C[使用代理模式]
    B -->|未设置代理| D[直接访问 - 被拒绝]
    
    C --> E[DNS 解析 microsoft.intra.aibang.local]
    E --> F[连接到 GKE Squid Service]
    
    F --> G{GKE Squid ACL 检查}
    G -->|通过| H[转发到 cache_peer]
    G -->|拒绝| I[返回 403 Forbidden]
    
    H --> J[GCE VM Squid 接收请求]
    J --> K{GCE Squid ACL 检查}
    K -->|通过| L[建立到目标服务的连接]
    K -->|拒绝| M[返回 403 Forbidden]
    
    L --> N[Microsoft 服务响应]
    N --> O[数据原路返回]
    
    style A fill:#e1f5fe
    style G fill:#fff3e0
    style K fill:#ffebee
    style N fill:#e8f5e8
```

### 3.2 错误处理流程

```mermaid
flowchart TD
    A[请求开始] --> B{DNS 解析}
    B -->|失败| C[DNS 解析错误<br/>检查 CoreDNS 配置]
    B -->|成功| D{连接 GKE Squid}
    
    D -->|超时| E[连接超时<br/>检查 Service 和 Pod 状态]
    D -->|成功| F{GKE ACL 检查}
    
    F -->|拒绝| G[403 Forbidden<br/>检查 ACL 规则]
    F -->|通过| H{连接 GCE Squid}
    
    H -->|网络不通| I[网络错误<br/>检查防火墙规则]
    H -->|成功| J{GCE ACL 检查}
    
    J -->|拒绝| K[403 Forbidden<br/>检查二级 ACL]
    J -->|通过| L{连接目标服务}
    
    L -->|失败| M[目标服务不可达<br/>检查外网连接]
    L -->|成功| N[请求成功]
    
    style C fill:#ffcdd2
    style E fill:#ffcdd2
    style G fill:#ffcdd2
    style I fill:#ffcdd2
    style K fill:#ffcdd2
    style M fill:#ffcdd2
    style N fill:#c8e6c9
```

## 4. 组件交互图

### 4.1 Kubernetes 资源交互

```mermaid
graph TB
    subgraph "Kubernetes Resources"
        NS[Namespace: intra-proxy]
        CM[ConfigMap: squid-config]
        DEP[Deployment: squid-proxy]
        SVC[Service: squid-proxy-service]
        POD1[Pod: squid-proxy-xxx-1]
        POD2[Pod: squid-proxy-xxx-2]
    end
    
    subgraph "DNS System"
        COREDNS[CoreDNS ConfigMap]
        DNSRULE[DNS Rewrite Rule]
    end
    
    subgraph "External Resources"
        VM[GCE VM: int-proxy]
        FW[Firewall Rules]
    end
    
    NS --> DEP
    NS --> SVC
    NS --> CM
    
    DEP --> POD1
    DEP --> POD2
    DEP -.->|uses config| CM
    
    SVC --> POD1
    SVC --> POD2
    
    COREDNS --> DNSRULE
    DNSRULE -.->|resolves to| SVC
    
    POD1 -.->|cache_peer| VM
    POD2 -.->|cache_peer| VM
    
    FW -.->|protects| VM
    
    style NS fill:#e8eaf6
    style SVC fill:#f3e5f5
    style VM fill:#fff8e1
    style FW fill:#ffebee
```

### 4.2 安全控制流程

```mermaid
flowchart TD
    A[请求到达] --> B[第一层安全检查]
    
    subgraph "GKE Squid 安全控制"
        B --> C{源 IP 检查}
        C -->|✓ localnet| D{目标域名检查}
        C -->|✗ 非法 IP| E[拒绝访问]
        
        D -->|✓ allowed_domains| F{端口检查}
        D -->|✗ 非法域名| G[拒绝访问]
        
        F -->|✓ Safe_ports| H[记录访问日志]
        F -->|✗ 非法端口| I[拒绝访问]
    end
    
    H --> J[转发到二级代理]
    
    subgraph "GCE Squid 安全控制"
        J --> K{源 IP 二次检查}
        K -->|✓ gke_cluster| L{域名白名单检查}
        K -->|✗ 非法来源| M[拒绝访问]
        
        L -->|✓ microsoft_domains| N{时间窗口检查}
        L -->|✗ 域名不在白名单| O[拒绝访问]
        
        N -->|✓ business_hours| P[记录审计日志]
        N -->|✗ 非工作时间| Q[拒绝访问]
    end
    
    P --> R[允许访问外网]
    
    style B fill:#e3f2fd
    style J fill:#fff3e0
    style R fill:#e8f5e8
    style E fill:#ffcdd2
    style G fill:#ffcdd2
    style I fill:#ffcdd2
    style M fill:#ffcdd2
    style O fill:#ffcdd2
    style Q fill:#ffcdd2
```

## 5. 监控和日志流程

### 5.1 监控数据流

```mermaid
graph TB
    subgraph "GKE Squid Metrics"
        A1[连接数统计]
        A2[请求成功率]
        A3[响应时间]
        A4[缓存命中率]
    end
    
    subgraph "GCE Squid Metrics"
        B1[连接数统计]
        B2[请求成功率]
        B3[响应时间]
        B4[带宽使用率]
    end
    
    subgraph "日志收集"
        C1[GKE Access Logs]
        C2[GCE Access Logs]
        C3[GCE Audit Logs]
    end
    
    subgraph "监控系统"
        D1[Prometheus]
        D2[Grafana Dashboard]
        D3[AlertManager]
    end
    
    subgraph "日志分析"
        E1[ELK Stack]
        E2[SIEM System]
        E3[Security Alerts]
    end
    
    A1 --> D1
    A2 --> D1
    A3 --> D1
    A4 --> D1
    
    B1 --> D1
    B2 --> D1
    B3 --> D1
    B4 --> D1
    
    D1 --> D2
    D1 --> D3
    
    C1 --> E1
    C2 --> E1
    C3 --> E1
    
    E1 --> E2
    E2 --> E3
    
    style D1 fill:#e8f5e8
    style E1 fill:#fff3e0
    style E3 fill:#ffebee
```

### 5.2 告警处理流程

```mermaid
sequenceDiagram
    participant M as Monitoring System
    participant A as AlertManager
    participant O as On-call Engineer
    participant S as Squid Service
    
    Note over M,S: 监控告警处理流程
    
    M->>M: 1. 检测异常指标<br/>• 连接数过高<br/>• 错误率上升<br/>• 响应时间增加
    
    M->>A: 2. 触发告警规则
    
    Note over A: 告警聚合和去重<br/>应用告警策略
    
    A->>O: 3. 发送告警通知<br/>• Email/SMS/Slack<br/>• 包含详细信息
    
    O->>S: 4. 检查服务状态<br/>• kubectl get pods<br/>• kubectl logs<br/>• 检查 VM 状态
    
    Note over O: 根据 Runbook 执行<br/>故障排查步骤
    
    O->>S: 5. 执行修复操作<br/>• 重启 Pod<br/>• 扩容实例<br/>• 修复配置
    
    S->>M: 6. 服务恢复正常
    M->>A: 7. 告警自动解除
    A->>O: 8. 发送恢复通知
```

## 6. 部署流程图

### 6.1 完整部署流程

```mermaid
flowchart TD
    A[开始部署] --> B[检查前置条件]
    B --> C{环境检查}
    C -->|✗ 不满足| D[安装依赖<br/>配置权限]
    C -->|✓ 满足| E[创建 GCE VM]
    D --> E
    
    E --> F[配置防火墙规则]
    F --> G[安装配置 VM Squid]
    G --> H[测试 VM Squid]
    H --> I{VM 测试}
    I -->|失败| J[排查 VM 问题]
    I -->|成功| K[创建 GKE 资源]
    J --> G
    
    K --> L[部署 Squid ConfigMap]
    L --> M[部署 Squid Deployment]
    M --> N[创建 Squid Service]
    N --> O[配置 DNS 解析]
    
    O --> P[端到端测试]
    P --> Q{测试结果}
    Q -->|失败| R[故障排查]
    Q -->|成功| S[配置监控]
    R --> P
    
    S --> T[生产环境验证]
    T --> U[部署完成]
    
    style A fill:#e8f5e8
    style U fill:#c8e6c9
    style J fill:#ffcdd2
    style R fill:#ffcdd2
```

### 6.2 回滚流程

```mermaid
flowchart TD
    A[检测到问题] --> B{问题严重程度}
    B -->|严重| C[立即回滚]
    B -->|一般| D[尝试快速修复]
    
    D --> E{修复成功?}
    E -->|是| F[继续监控]
    E -->|否| C
    
    C --> G[停止新流量]
    G --> H[恢复原有配置]
    H --> I[删除 GKE 资源]
    I --> J[恢复 DNS 配置]
    J --> K[验证回滚结果]
    K --> L{回滚成功?}
    L -->|是| M[通知相关人员]
    L -->|否| N[紧急处理]
    
    F --> O[正常运行]
    M --> P[分析问题原因]
    N --> Q[升级处理]
    
    style A fill:#ffebee
    style C fill:#ffcdd2
    style O fill:#e8f5e8
    style Q fill:#ff5722
```

这个文档包含了完整的 Mermaid 流程图，涵盖了架构、时序、数据流、监控、部署等各个方面的流程图，应该能够很好地展示整个 Egress 代理方案的工作流程。