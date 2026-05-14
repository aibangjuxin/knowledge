# GKE Egress 代理流程图集合 (增强版)

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
            D[Squid Service<br/>ClusterIP: 10.68.x.x]
            B --- D
            C --- D
        end
    end
    
    subgraph "Cloud DNS"
        E[Cloud DNS Zone<br/>microsoft.intra.aibang.local<br/>→ 10.68.x.x]
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
    style E fill:#e8f5e8
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
        B1[Cloud DNS<br/>microsoft.intra.aibang.local<br/>→ 10.68.x.x]
    end
    
    subgraph "Layer 3: GKE Proxy"
        C1[Squid Service<br/>10.68.x.x:3128]
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
    style B1 fill:#e8f5e8
    style C1 fill:#f1f8e9
    style D1 fill:#fff8e1
    style E1 fill:#fce4ec
```

## 2. 请求处理时序图

### 2.1 HTTP CONNECT 请求流程

```mermaid
sequenceDiagram
    participant AP as API Pod
    participant CDNS as Cloud DNS
    participant GS as GKE Squid
    participant VS as GCE VM Squid
    participant MS as Microsoft Service
    
    Note over AP,MS: HTTPS 请求处理流程
    
    AP->>CDNS: 1. DNS Query: microsoft.intra.aibang.local
    CDNS->>AP: 2. Response: 10.68.x.x (Service ClusterIP)
    
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

### 2.2 Cloud DNS 解析流程

```mermaid
sequenceDiagram
    participant AP as API Pod
    participant CDNS as Cloud DNS
    participant SVC as Squid Service
    participant POD as Squid Pod
    
    AP->>CDNS: 1. nslookup microsoft.intra.aibang.local
    
    Note over CDNS: Cloud DNS 处理流程:<br/>1. 查询 DNS Zone 配置<br/>2. 匹配 A Record<br/>3. 返回配置的 IP 地址
    
    CDNS->>AP: 2. A Record: 10.68.x.x
    
    AP->>SVC: 3. HTTP Request to 10.68.x.x:3128
    
    Note over SVC: Service 负载均衡:<br/>选择健康的 Pod 实例
    
    SVC->>POD: 4. Forward to selected Pod
    POD->>SVC: 5. Response
    SVC->>AP: 6. Response to API Pod
```

### 2.3 Cloud DNS 配置管理流程

```mermaid
sequenceDiagram
    participant ADMIN as 管理员
    participant GCLOUD as gcloud CLI
    participant CDNS as Cloud DNS
    participant ZONE as DNS Zone
    
    Note over ADMIN,ZONE: Cloud DNS 配置流程
    
    ADMIN->>GCLOUD: 1. 创建 DNS Zone
    GCLOUD->>CDNS: 2. gcloud dns managed-zones create
    CDNS->>ZONE: 3. 创建 aibang.local Zone
    
    ADMIN->>GCLOUD: 4. 添加 A Record
    GCLOUD->>CDNS: 5. gcloud dns record-sets transaction start
    GCLOUD->>CDNS: 6. gcloud dns record-sets transaction add
    Note over GCLOUD: microsoft.intra.aibang.local → 10.68.x.x
    GCLOUD->>CDNS: 7. gcloud dns record-sets transaction execute
    
    CDNS->>ZONE: 8. 更新 DNS 记录
    ZONE->>CDNS: 9. 配置生效确认
    CDNS->>ADMIN: 10. 配置完成通知
```

## 3. 数据流程图

### 3.1 请求数据流

```mermaid
flowchart TD
    A[API Pod 发起请求] --> B{检查环境变量}
    B -->|HTTP_PROXY 已设置| C[使用代理模式]
    B -->|未设置代理| D[直接访问 - 被拒绝]
    
    C --> E[Cloud DNS 解析 microsoft.intra.aibang.local]
    E --> F[连接到 GKE Squid Service 10.68.x.x]
    
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
    style E fill:#e8f5e8
    style G fill:#fff3e0
    style K fill:#ffebee
    style N fill:#e8f5e8
```

### 3.2 错误处理流程

```mermaid
flowchart TD
    A[请求开始] --> B{Cloud DNS 解析}
    B -->|失败| C[DNS 解析错误<br/>检查 Cloud DNS 配置<br/>检查 DNS Zone 记录]
    B -->|成功| D{连接 GKE Squid}
    
    D -->|超时| E[连接超时<br/>检查 Service 和 Pod 状态<br/>检查 10.68.x.x 可达性]
    D -->|成功| F{GKE ACL 检查}
    
    F -->|拒绝| G[403 Forbidden<br/>检查 ACL 规则]
    F -->|通过| H{连接 GCE Squid}
    
    H -->|网络不通| I[网络错误<br/>检查防火墙规则<br/>检查 VM 状态]
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
        SVC[Service: squid-proxy-service<br/>ClusterIP: 10.68.x.x]
        POD1[Pod: squid-proxy-xxx-1]
        POD2[Pod: squid-proxy-xxx-2]
    end
    
    subgraph "Cloud DNS System"
        CDNS[Cloud DNS Service]
        ZONE[DNS Zone: aibang.local]
        RECORD[A Record: microsoft.intra<br/>→ 10.68.x.x]
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
    
    CDNS --> ZONE
    ZONE --> RECORD
    RECORD -.->|resolves to| SVC
    
    POD1 -.->|cache_peer| VM
    POD2 -.->|cache_peer| VM
    
    FW -.->|protects| VM
    
    style NS fill:#e8eaf6
    style SVC fill:#f3e5f5
    style CDNS fill:#e8f5e8
    style VM fill:#fff8e1
    style FW fill:#ffebee
```

### 4.2 Cloud DNS 配置架构

```mermaid
graph TB
    subgraph "Cloud DNS 配置"
        ZONE[DNS Zone: aibang.local]
        RECORD1[A Record: microsoft.intra.aibang.local<br/>→ 10.68.x.x]
        RECORD2[A Record: int-proxy.aibang.com<br/>→ 10.128.2.100]
        NS_RECORD[NS Records: 权威 DNS 服务器]
    end
    
    subgraph "GKE 集群"
        SVC[Squid Service<br/>10.68.x.x:3128]
        POD[Squid Pods]
    end
    
    subgraph "GCE VM"
        VM[int-proxy VM<br/>10.128.2.100:3128]
    end
    
    subgraph "客户端解析"
        CLIENT[API Pod]
        RESOLVER[DNS Resolver]
    end
    
    ZONE --> RECORD1
    ZONE --> RECORD2
    ZONE --> NS_RECORD
    
    RECORD1 -.->|points to| SVC
    RECORD2 -.->|points to| VM
    
    CLIENT --> RESOLVER
    RESOLVER --> ZONE
    
    SVC --> POD
    POD -.->|cache_peer| VM
    
    style ZONE fill:#e8f5e8
    style SVC fill:#f3e5f5
    style VM fill:#fff8e1
```

### 4.3 安全控制流程

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
    
    subgraph "Cloud DNS Metrics"
        C1[DNS 查询次数]
        C2[DNS 响应时间]
        C3[DNS 解析成功率]
    end
    
    subgraph "日志收集"
        D1[GKE Access Logs]
        D2[GCE Access Logs]
        D3[GCE Audit Logs]
        D4[Cloud DNS Query Logs]
    end
    
    subgraph "监控系统"
        E1[Prometheus]
        E2[Grafana Dashboard]
        E3[AlertManager]
    end
    
    subgraph "日志分析"
        F1[ELK Stack]
        F2[SIEM System]
        F3[Security Alerts]
    end
    
    A1 --> E1
    A2 --> E1
    A3 --> E1
    A4 --> E1
    
    B1 --> E1
    B2 --> E1
    B3 --> E1
    B4 --> E1
    
    C1 --> E1
    C2 --> E1
    C3 --> E1
    
    E1 --> E2
    E1 --> E3
    
    D1 --> F1
    D2 --> F1
    D3 --> F1
    D4 --> F1
    
    F1 --> F2
    F2 --> F3
    
    style E1 fill:#e8f5e8
    style F1 fill:#fff3e0
    style F3 fill:#ffebee
    style C1 fill:#e3f2fd
```

### 5.2 告警处理流程

```mermaid
sequenceDiagram
    participant M as Monitoring System
    participant A as AlertManager
    participant O as On-call Engineer
    participant S as Squid Service
    participant DNS as Cloud DNS
    
    Note over M,DNS: 监控告警处理流程
    
    M->>M: 1. 检测异常指标<br/>• 连接数过高<br/>• 错误率上升<br/>• DNS 解析失败<br/>• 响应时间增加
    
    M->>A: 2. 触发告警规则
    
    Note over A: 告警聚合和去重<br/>应用告警策略
    
    A->>O: 3. 发送告警通知<br/>• Email/SMS/Slack<br/>• 包含详细信息
    
    O->>S: 4. 检查 GKE 服务状态<br/>• kubectl get pods<br/>• kubectl logs<br/>• 检查 Service 10.68.x.x
    
    O->>DNS: 5. 检查 Cloud DNS<br/>• gcloud dns record-sets list<br/>• 验证 DNS 解析
    
    Note over O: 根据 Runbook 执行<br/>故障排查步骤
    
    O->>S: 6. 执行修复操作<br/>• 重启 Pod<br/>• 扩容实例<br/>• 修复配置
    
    S->>M: 7. 服务恢复正常
    M->>A: 8. 告警自动解除
    A->>O: 9. 发送恢复通知
```

## 6. 部署流程图

### 6.1 完整部署流程

```mermaid
flowchart TD
    A[开始部署] --> B[检查前置条件]
    B --> C{环境检查}
    C -->|✗ 不满足| D[安装依赖<br/>配置权限]
    C -->|✓ 满足| E[配置 Cloud DNS]
    D --> E
    
    E --> F[创建 DNS Zone]
    F --> G[添加 A Records<br/>microsoft.intra → 10.68.x.x<br/>int-proxy → 10.128.2.100]
    G --> H[创建 GCE VM]
    H --> I[配置防火墙规则]
    
    I --> J[安装配置 VM Squid]
    J --> K[测试 VM Squid]
    K --> L{VM 测试}
    L -->|失败| M[排查 VM 问题]
    L -->|成功| N[创建 GKE 资源]
    M --> J
    
    N --> O[部署 Squid ConfigMap]
    O --> P[部署 Squid Deployment]
    P --> Q[创建 Squid Service<br/>获取 ClusterIP 10.68.x.x]
    Q --> R[更新 Cloud DNS 记录]
    
    R --> S[端到端测试]
    S --> T{测试结果}
    T -->|失败| U[故障排查<br/>检查 DNS/Service/VM]
    T -->|成功| V[配置监控]
    U --> S
    
    V --> W[生产环境验证]
    W --> X[部署完成]
    
    style A fill:#e8f5e8
    style E fill:#e3f2fd
    style X fill:#c8e6c9
    style M fill:#ffcdd2
    style U fill:#ffcdd2
```

### 6.2 Cloud DNS 配置流程

```mermaid
flowchart TD
    A[开始 DNS 配置] --> B[创建 DNS Zone]
    B --> C[gcloud dns managed-zones create aibang-local]
    C --> D[验证 Zone 创建]
    
    D --> E[开始事务]
    E --> F[gcloud dns record-sets transaction start]
    F --> G[添加 microsoft.intra A Record]
    G --> H[gcloud dns record-sets transaction add<br/>--name=microsoft.intra.aibang.local<br/>--type=A --data=10.68.x.x]
    
    H --> I[添加 int-proxy A Record]
    I --> J[gcloud dns record-sets transaction add<br/>--name=int-proxy.aibang.com<br/>--type=A --data=10.128.2.100]
    
    J --> K[执行事务]
    K --> L[gcloud dns record-sets transaction execute]
    L --> M[验证 DNS 记录]
    
    M --> N{DNS 测试}
    N -->|成功| O[DNS 配置完成]
    N -->|失败| P[回滚 DNS 配置]
    P --> Q[重新配置]
    Q --> G
    
    style A fill:#e8f5e8
    style O fill:#c8e6c9
    style P fill:#ffcdd2
```

### 6.3 回滚流程

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
    I --> J[更新 Cloud DNS 记录<br/>移除 microsoft.intra 记录]
    J --> K[验证回滚结果]
    K --> L{回滚成功?}
    L -->|是| M[通知相关人员]
    L -->|否| N[紧急处理]
    
    F --> O[正常运行]
    M --> P[分析问题原因]
    N --> Q[升级处理]
    
    style A fill:#ffebee
    style C fill:#ffcdd2
    style J fill:#fff3e0
    style O fill:#e8f5e8
    style Q fill:#ff5722
```

## 7. 网络拓扑图

### 7.1 完整网络拓扑

```mermaid
graph TB
    subgraph "Internet"
        INT[External Services<br/>login.microsoft.com]
    end
    
    subgraph "GCP Project"
        subgraph "Cloud DNS"
            DNS[DNS Zone: aibang.local<br/>microsoft.intra → 10.68.x.x<br/>int-proxy → 10.128.2.100]
        end
        
        subgraph "GCE VM"
            VM[int-proxy VM<br/>Internal: 10.128.2.100<br/>External: 35.x.x.x]
        end
        
        subgraph "GKE Cluster"
            subgraph "Pod Network: 10.128.0.0/20"
                POD[API Pods<br/>10.128.0.x]
            end
            
            subgraph "Service Network: 10.68.0.0/16"
                SVC[Squid Service<br/>10.68.x.x:3128]
            end
            
            subgraph "intra-proxy Namespace"
                SPOD1[Squid Pod 1]
                SPOD2[Squid Pod 2]
            end
        end
        
        subgraph "Firewall Rules"
            FW1[allow-gke-to-proxy<br/>10.128.0.0/20 → VM:3128]
            FW2[allow-proxy-egress<br/>VM → 0.0.0.0/0:80,443]
        end
    end
    
    POD -->|DNS Query| DNS
    DNS -->|Resolve| POD
    POD -->|HTTP CONNECT| SVC
    SVC --> SPOD1
    SVC --> SPOD2
    SPOD1 -->|cache_peer| VM
    SPOD2 -->|cache_peer| VM
    VM -->|Direct Access| INT
    
    FW1 -.->|Allow| SPOD1
    FW1 -.->|Allow| SPOD2
    FW2 -.->|Allow| VM
    
    style DNS fill:#e8f5e8
    style SVC fill:#f3e5f5
    style VM fill:#fff8e1
    style INT fill:#e3f2fd
```

这个增强版的流程图文档已经完成了以下更新：

1. **将 CoreDNS 替换为 Cloud DNS**：所有相关的流程图都更新为使用 Cloud DNS 服务
2. **IP 地址更新**：将 10.96.x.x 替换为 10.68.x.x
3. **新增 Cloud DNS 相关流程**：包括 DNS 配置管理、部署流程等
4. **增强了监控部分**：添加了 Cloud DNS 的监控指标
5. **完善了网络拓扑图**：展示了完整的网络架构

主要变化体现在 DNS 解析部分，现在使用 Cloud DNS 来管理域名解析，而不是 GKE 集群内的 CoreDNS。这样的架构更适合企业级的 DNS 管理需求。