# GKE 跨 Namespace 网络访问完整流程图
our model ==> Routes-based

## 完整的网络流量和策略验证流程

### 1. 整体架构和流量路径

```mermaid
graph TB
    subgraph "Namespace A - 100.68.1.0/24"
        A1[Pod A<br/>100.68.1.10<br/>app: client]
    end
    
    subgraph "Kubernetes Service Layer"
        B1[Service B<br/>100.64.5.20:443<br/>namespace-b.svc.cluster.local]
        B2[kube-proxy<br/>iptables/IPVS Rules]
    end
    
    subgraph "Namespace B - 100.68.2.0/24"
        C1[Pod B1<br/>100.68.2.30:8443<br/>app: server]
        C2[Pod B2<br/>100.68.2.31:8443<br/>app: server]
    end
    
    subgraph "GKE Nodes - 192.168.65.0/24"
        D1[Node 1<br/>192.168.65.10]
        D2[Node 2<br/>192.168.65.11]
    end
    
    A1 -->|1 发起请求<br/>dst: 100.64.5.20:443| B1
    B1 -->|2 Service解析| B2
    B2 -->|3 DNAT转换<br/>dst: 100.68.2.30:8443| C1
    B2 -.->|负载均衡| C2
    
    A1 -.-|可能经过| D1
    C1 -.-|可能经过| D2
    
    style A1 fill:#e1f5ff
    style C1 fill:#ffe1e1
    style C2 fill:#ffe1e1
    style B1 fill:#fff4e1
    style B2 fill:#fff4e1
```

### 2. NetworkPolicy 匹配和验证流程

```mermaid
graph TD
    Start[Pod A 发起请求<br/>curl https://svc-b.namespace-b:443] --> DNS[DNS 查询]
    
    DNS --> CheckDNS{Namespace A<br/>Egress Policy<br/>允许 DNS?}
    CheckDNS -->|❌ 拒绝| Fail1[连接失败:<br/>DNS Resolution Error]
    CheckDNS -->|✅ 允许<br/>UDP 53 to kube-dns| Resolve[解析为 Service IP<br/>100.64.5.20]
    
    Resolve --> SendReq[发送请求到<br/>100.64.5.20:443]
    
    SendReq --> KubeProxy[kube-proxy 处理]
    KubeProxy --> DNAT[DNAT 转换:<br/>src: 100.68.1.10<br/>dst: 100.68.2.30:8443]
    
    DNAT --> CheckEgress{Namespace A<br/>Egress Policy<br/>允许访问?}
    
    CheckEgress -->|检查条件| EgressCheck1{目标 Namespace<br/>= namespace-b?}
    EgressCheck1 -->|❌ 否| Fail2[Egress 阻止]
    EgressCheck1 -->|✅ 是| EgressCheck2{目标端口<br/>= 8443?}
    EgressCheck2 -->|❌ 否| Fail2
    EgressCheck2 -->|✅ 是| EgressPass[Egress 允许]
    
    EgressPass --> Route{流量路由}
    
    Route -->|同节点| SameNode[本地转发]
    Route -->|跨节点| DiffNode[通过 Node 网络]
    
    SameNode --> CheckIngress{Namespace B<br/>Ingress Policy<br/>允许访问?}
    DiffNode --> CheckIngress
    
    CheckIngress -->|检查条件| IngressCheck1{源 Namespace<br/>= namespace-a?}
    IngressCheck1 -->|❌ 否| Fail3[Ingress 阻止]
    IngressCheck1 -->|✅ 是| IngressCheck2{目标端口<br/>= 8443?}
    IngressCheck2 -->|❌ 否| Fail3
    IngressCheck2 -->|✅ 是| IngressCheck3{Pod 标签匹配?}
    IngressCheck3 -->|❌ 否| Fail3
    IngressCheck3 -->|✅ 是| IngressPass[Ingress 允许]
    
    IngressPass --> PodB[请求到达 Pod B<br/>处理业务逻辑]
    PodB --> Response[返回响应]
    
    Response --> CheckEgressB{Namespace B<br/>Egress Policy<br/>允许响应?}
    CheckEgressB -->|✅ 允许| ReturnPath[响应返回 Pod A]
    CheckEgressB -->|❌ 拒绝| Fail4[响应被阻止]
    
    ReturnPath --> Success[✅ 连接成功]
    
    Fail1 --> End[连接失败]
    Fail2 --> End
    Fail3 --> End
    Fail4 --> End
    Success --> End
    
    style Start fill:#e1f5ff
    style Success fill:#90EE90
    style Fail1 fill:#FFB6C6
    style Fail2 fill:#FFB6C6
    style Fail3 fill:#FFB6C6
    style Fail4 fill:#FFB6C6
    style CheckDNS fill:#FFF4E1
    style CheckEgress fill:#FFF4E1
    style CheckIngress fill:#FFF4E1
    style CheckEgressB fill:#FFF4E1
```

### 3. 不同 GKE 网络模式下的流量差异

```mermaid
graph TD
    subgraph "VPC-Native 模式 [推荐]"
        VPC1[Pod A<br/>100.68.1.10] -->|直接路由<br/>保持源IP| VPC2[Pod B<br/>100.68.2.30]
        VPC2 -->|看到的源IP:<br/>100.68.1.10| VPC3[✅ NetworkPolicy<br/>匹配 Namespace A]
    end
    
    subgraph "Routes-Based 模式"
        RB1[Pod A<br/>100.68.1.10] -->|经过 Node 1<br/>192.168.65.10| RB2[可能 SNAT]
        RB2 -->|源IP可能变为:<br/>192.168.65.10| RB3[Pod B<br/>100.68.2.30]
        RB3 -->|看到的源IP:<br/>192.168.65.10| RB4[⚠️ NetworkPolicy<br/>可能不匹配]
    end
    
    subgraph "GKE Dataplane V2 [eBPF]"
        DP1[Pod A<br/>100.68.1.10] -->|eBPF 处理<br/>完全保持源IP| DP2[Pod B<br/>100.68.2.30]
        DP2 -->|看到的源IP:<br/>100.68.1.10| DP3[✅ NetworkPolicy<br/>完美匹配]
    end
    
    style VPC3 fill:#90EE90
    style RB4 fill:#FFB6C6
    style DP3 fill:#90EE90
```

### 4. NetworkPolicy 规则匹配详细流程

```mermaid
graph LR
    subgraph "Egress Policy - Namespace A"
        E1[Pod 发起连接] --> E2{目标是<br/>Pod IP?}
        E2 -->|是| E3{Namespace<br/>匹配?}
        E2 -->|是 Service IP| E4[kube-proxy<br/>转换为 Pod IP]
        E4 --> E3
        
        E3 -->|namespace-b| E5{Pod Label<br/>匹配?}
        E3 -->|其他| E6[❌ 拒绝]
        
        E5 -->|app=server| E7{端口<br/>匹配?}
        E5 -->|不匹配| E6
        
        E7 -->|8443| E8[✅ 允许出站]
        E7 -->|其他| E6
    end
    
    subgraph "Ingress Policy - Namespace B"
        I1[收到连接请求] --> I2{源 Pod<br/>Namespace?}
        
        I2 -->|namespace-a| I3{目标 Pod<br/>Label 匹配?}
        I2 -->|其他| I4[❌ 拒绝]
        
        I3 -->|app=server| I5{端口<br/>匹配?}
        I3 -->|不匹配| I4
        
        I5 -->|8443| I6[✅ 允许入站]
        I5 -->|其他| I4
    end
    
    E8 -.->|流量传输| I1
    
    style E8 fill:#90EE90
    style I6 fill:#90EE90
    style E6 fill:#FFB6C6
    style I4 fill:#FFB6C6
```

### 5. 故障排查决策树

```mermaid
graph TD
    Problem[连接失败] --> Check1{能解析<br/>Service 名称?}
    
    Check1 -->|❌ 否| Fix1[检查 Namespace A<br/>Egress DNS 规则<br/>允许 UDP/TCP 53]
    Check1 -->|✅ 是| Check2{ping Pod IP<br/>可达?}
    
    Check2 -->|❌ 否| Check3{同一节点?}
    Check3 -->|是| Fix2[检查本地路由<br/>CNI 配置]
    Check3 -->|否| Fix3[检查跨节点路由<br/>VPC 防火墙规则]
    
    Check2 -->|✅ 是| Check4{telnet Pod IP:8443<br/>可连接?}
    
    Check4 -->|❌ 否| Check5{Namespace A<br/>Egress 配置正确?}
    Check5 -->|否| Fix4[修正 Egress:<br/>- namespaceSelector<br/>- port: 8443]
    Check5 -->|是| Check6{Namespace B<br/>Ingress 配置正确?}
    Check6 -->|否| Fix5[修正 Ingress:<br/>- namespaceSelector<br/>- port: 8443<br/>- podSelector]
    Check6 -->|是| Fix6[抓包验证源IP:<br/>tcpdump -i any port 8443]
    
    Check4 -->|✅ 是| Check7{curl Service:443<br/>成功?}
    Check7 -->|❌ 否| Fix7[检查 Service 配置:<br/>- targetPort: 8443<br/>- selector 匹配]
    Check7 -->|✅ 是| Success[✅ 问题解决]
    
    Fix1 --> Retest[重新测试]
    Fix2 --> Retest
    Fix3 --> Retest
    Fix4 --> Retest
    Fix5 --> Retest
    Fix6 --> Retest
    Fix7 --> Retest
    Retest --> Check1
    
    style Problem fill:#FFB6C6
    style Success fill:#90EE90
    style Fix1 fill:#FFF4E1
    style Fix2 fill:#FFF4E1
    style Fix3 fill:#FFF4E1
    style Fix4 fill:#FFF4E1
    style Fix5 fill:#FFF4E1
    style Fix6 fill:#FFF4E1
    style Fix7 fill:#FFF4E1
```

### 6. 端口映射和流量转换流程

```mermaid
sequenceDiagram
    participant PodA as Pod A<br/>100.68.1.10
    participant DNS as kube-dns
    participant SvcIP as Service VIP<br/>100.64.5.20:443
    participant IPTables as kube-proxy<br/>iptables/IPVS
    participant PodB as Pod B<br/>100.68.2.30:8443
    
    Note over PodA: 应用层请求
    PodA->>DNS: DNS Query: svc-b.namespace-b
    Note over DNS: Egress Policy 检查<br/>允许 UDP 53?
    DNS-->>PodA: Response: 100.64.5.20
    
    Note over PodA: 建立连接
    PodA->>SvcIP: SYN [src:100.68.1.10:random]<br/>[dst:100.64.5.20:443]
    
    Note over SvcIP,IPTables: Service 不是真实 endpoint
    SvcIP->>IPTables: 查询 iptables 规则
    
    Note over IPTables: DNAT 转换<br/>Service Port → Pod Port
    IPTables->>IPTables: 转换规则:<br/>dst: 100.64.5.20:443<br/>→ 100.68.2.30:8443
    
    Note over PodA,PodB: 实际网络包
    IPTables->>PodB: SYN [src:100.68.1.10:random]<br/>[dst:100.68.2.30:8443]
    
    Note over PodB: Egress Policy 检查<br/>目标: namespace-b<br/>端口: 8443 ✅
    
    Note over PodB: Ingress Policy 检查<br/>源: namespace-a<br/>端口: 8443 ✅
    
    PodB-->>IPTables: SYN-ACK
    
    Note over IPTables: SNAT 反向转换<br/>Pod Port → Service Port
    IPTables-->>PodA: SYN-ACK [src:100.64.5.20:443]<br/>[dst:100.68.1.10:random]
    
    Note over PodA: 建立连接成功
    PodA->>PodB: Application Data
    PodB-->>PodA: Response Data
    
    rect rgb(200, 255, 200)
        Note right of PodB: NetworkPolicy 关键点:<br/>1. 检查的是 Pod IP (100.68.x.x)<br/>2. 检查的是 Pod Port (8443)<br/>3. Service IP 只在 DNS 和 iptables 中存在
    end
```

### 7. 配置应用和验证完整流程

```mermaid
graph TD
    Start[开始配置] --> Step1[1. 标记 Namespace]
    
    Step1 --> Cmd1["kubectl label namespace namespace-a<br/>kubernetes.io/metadata.name=namespace-a"]
    Cmd1 --> Cmd2["kubectl label namespace namespace-b<br/>kubernetes.io/metadata.name=namespace-b"]
    
    Cmd2 --> Step2[2. 部署 Namespace A Egress]
    Step2 --> Apply1["kubectl apply -f namespace-a-egress.yaml"]
    
    Apply1 --> Step3[3. 部署 Namespace B Ingress]
    Step3 --> Apply2["kubectl apply -f namespace-b-ingress.yaml"]
    
    Apply2 --> Step4[4. 验证策略生效]
    Step4 --> Verify1{kubectl get netpol -A<br/>显示策略?}
    
    Verify1 -->|❌ 否| Fix1[检查 YAML 格式<br/>查看 kubectl logs]
    Verify1 -->|✅ 是| Verify2[kubectl describe netpol]
    
    Fix1 --> Apply1
    
    Verify2 --> Step5[5. 测试 DNS 解析]
    Step5 --> Test1["kubectl exec pod-a -- nslookup<br/>svc-b.namespace-b"]
    
    Test1 --> Check1{DNS 解析<br/>成功?}
    Check1 -->|❌ 否| Fix2[检查 Egress DNS 规则:<br/>- kube-system namespace<br/>- port 53 UDP/TCP]
    Check1 -->|✅ 是| Step6[6. 测试直接 Pod 连接]
    
    Fix2 --> Apply1
    
    Step6 --> Test2["kubectl exec pod-a --<br/>curl -v -k https://POD_B_IP:8443"]
    
    Test2 --> Check2{连接<br/>成功?}
    Check2 -->|❌ 否| Debug1[启动调试]
    Check2 -->|✅ 是| Step7[7. 测试 Service 连接]
    
    Debug1 --> Debug2["tcpdump -i any -nn port 8443"]
    Debug2 --> Debug3[检查源IP和端口]
    Debug3 --> Fix3[根据抓包结果调整策略]
    Fix3 --> Apply1
    
    Step7 --> Test3["kubectl exec pod-a --<br/>curl -v -k https://svc-b.namespace-b:443"]
    
    Test3 --> Check3{连接<br/>成功?}
    Check3 -->|❌ 否| Fix4[检查 Service 配置:<br/>targetPort: 8443]
    Check3 -->|✅ 是| Step8[8. 生产环境测试]
    
    Fix4 --> Test3
    
    Step8 --> Final[✅ 配置完成]
    
    style Start fill:#e1f5ff
    style Final fill:#90EE90
    style Fix1 fill:#FFB6C6
    style Fix2 fill:#FFB6C6
    style Fix3 fill:#FFB6C6
    style Fix4 fill:#FFB6C6
    style Debug1 fill:#FFF4E1
```

## 关键检查点对照表

|检查项|位置|检查内容|期望值|
|---|---|---|---|
|**DNS 解析**|Namespace A Egress|允许访问 kube-system:53|✅ UDP/TCP 53 开放|
|**目标地址**|Namespace A Egress|namespaceSelector|✅ namespace-b|
|**目标端口**|Namespace A Egress|port|⚠️ **8443** (Pod 端口)|
|**源地址**|Namespace B Ingress|namespaceSelector|✅ namespace-a|
|**目标端口**|Namespace B Ingress|port|⚠️ **8443** (Pod 端口)|
|**Pod 标签**|Namespace B Ingress|podSelector|✅ app: server|
|**Service 配置**|Service YAML|targetPort|⚠️ **8443** (指向 Pod)|
|**Service 配置**|Service YAML|port|✅ 443 (外部访问)|

## 快速验证命令集

```bash
# 1. 验证网络模式
gcloud container clusters describe YOUR_CLUSTER \
  --zone YOUR_ZONE \
  --format="value(ipAllocationPolicy.useIpAliases)"
# 输出: true = VPC-native (推荐)

# 2. 验证 IP 范围
kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}' | tr ' ' '\n'
kubectl get svc -A -o wide | grep ClusterIP

# 3. 验证 NetworkPolicy
kubectl get networkpolicies -A
kubectl describe networkpolicy -n namespace-a
kubectl describe networkpolicy -n namespace-b

# 4. 实时抓包验证
kubectl exec -it POD_B -n namespace-b -- \
  tcpdump -i any -nn 'port 8443' -A

# 5. 完整连接测试
kubectl exec -it POD_A -n namespace-a -- sh -c '
  echo "=== DNS 测试 ==="
  nslookup svc-b.namespace-b.svc.cluster.local
  
  echo "=== 直接 Pod IP 测试 ==="
  curl -v -k --connect-timeout 5 https://POD_B_IP:8443
  
  echo "=== Service 测试 ==="
  curl -v -k --connect-timeout 5 https://svc-b.namespace-b.svc.cluster.local:443
'
```

通过以上流程图和表格，您可以清晰地理解整个网络访问的每一个环节，以及 NetworkPolicy 在哪个阶段生效。关键要记住：**NetworkPolicy 看到的永远是 Pod IP 和 Pod Port，而不是 Service IP 和 Service Port**。