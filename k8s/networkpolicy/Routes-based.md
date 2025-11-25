# Routes-based 模式下的网络流量详解

## 问题核心分析

为什么在 Routes-based 模式下**不需要** Egress 到 Service IP Range 的规则。
- 1 在 Routes-based 模式下，您**不需要**配置 Egress 到 Service IP Range 的规则，因为 NetworkPolicy 在检查时，Service IP 已经被 kube-proxy DNAT 转换成了 Pod IP。NetworkPolicy 从头到尾都看不到 Service IP！
- 2 **最终答案**：不需要 Service IP 规则不代表不需要 Pod IP 规则，恰恰相反，**Pod IP 规则是唯一有效且必须的规则**，因为 NetworkPolicy 只能看到经过 DNAT 转换后的 Pod IP！但是一定要注意这个是可以通过namespaceSelector来配置而不是推荐使用IP Range来配置### **NetworkPolicy 不推荐直接写 Pod IP CIDR（容易失效）；应该通过 namespaceSelector / podSelector 让 K8s 自动管理 Pod IP 变化**
	-  ❌ **不需要**配置 `ipBlock: 100.64.0.0/14`
	- ✅ **只需要**配置 `namespaceSelector: namespace-b`
	- ✅ NetworkPolicy 会自动通过 K8s API 找到该 Namespace 的所有 Pod IP
- 3 [另外不用单独配置类似这样一个namespace level的比如ingress from 192.168.64.0/19 8443这样的规则](./network-node-ip.md)
	- 有基于A- B的 egress
	- B ==> ingress A 
	- 有上面对应的规则就可以了。 
```yaml
# ============================================
# Namespace A Egress - 完全正确的配置
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-a-egress
  namespace: namespace-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  
  # ✅ 规则 1：访问 namespace-b（您的配置）
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: namespace-b
    ports:
    - protocol: TCP
      port: 8443
  
  # ✅ 规则 2：DNS 解析
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    - podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53

---
# ============================================
# Namespace B Ingress - 完全正确的配置
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-b-ingress
  namespace: namespace-b
spec:
  podSelector:
    matchLabels:
      app: your-app-b  # 根据实际标签修改
  policyTypes:
  - Ingress
  ingress:
  
  # ✅ 规则：允许来自 namespace-a
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: namespace-a
    ports:
    - protocol: TCP
      port: 8443
	```

## 关键概念：NetworkPolicy 的工作层级

```mermaid
graph TB
    subgraph "应用层视角"
        App[应用代码] -->|看到| AppView["目标: svc-b.namespace-b:443<br/>Service IP: 100.64.5.20:443"]
    end
    
    subgraph "NetworkPolicy 工作层"
        NP[NetworkPolicy] -->|实际检查| NPView["❌ 看不到 Service IP<br/>✅ 只看到 Pod IP: 100.68.2.30:8443"]
    end
    
    subgraph "Packet 实际内容"
        Packet[网络包] -->|Headers| Headers["src: 100.68.1.10:random<br/>dst: 100.68.2.30:8443"]
    end
    
    subgraph "kube-proxy 转换层"
        KP[kube-proxy<br/>iptables/IPVS] -->|DNAT 发生在| Layer["PREROUTING 链<br/>在 NetworkPolicy 之前!"]
    end
    
    AppView -.->|DNS 解析| KP
    KP -.->|转换| Headers
    Headers -->|实际检查| NPView
    
    style NPView fill:#90EE90
    style AppView fill:#e1f5ff
    style Layer fill:#FFE4B5
```

## 深入理解：DNAT 转换时机

### iptables 处理顺序（关键！）

```mermaid
graph LR
    A[网络包到达] --> B[PREROUTING]
    B --> C[**kube-proxy DNAT**<br/>Service IP → Pod IP]
    C --> D[FORWARD]
    D --> E[**NetworkPolicy 检查**<br/>此时已经是 Pod IP]
    E --> F[POSTROUTING]
    F --> G[发送到目标]
    
    style C fill:#FFB6C6
    style E fill:#90EE90
    
    Note1[关键：DNAT 在 NetworkPolicy 之前!]
    C -.-> Note1
```

### 详细的包处理流程

```mermaid
sequenceDiagram
    participant App as Pod A 应用
    participant Socket as Socket Layer
    participant PreRoute as PREROUTING<br/>[iptables]
    participant DNAT as kube-proxy DNAT
    participant NetPol as NetworkPolicy<br/>[CNI Plugin]
    participant Forward as FORWARD Chain
    participant Node as Node 网络
    participant PodB as Pod B
    
    App->>Socket: connect(100.64.5.20:443)
    Note over App,Socket: 应用层看到的是 Service IP
    
    Socket->>PreRoute: 发送 SYN 包<br/>dst: 100.64.5.20:443
    
    rect rgb(255, 200, 200)
        Note over PreRoute,DNAT: 第一阶段：DNAT 转换
        PreRoute->>DNAT: 匹配 Service 规则
        DNAT->>DNAT: 查找 Endpoints<br/>选择 Pod B
        DNAT->>DNAT: **DNAT 转换**<br/>100.64.5.20:443<br/>→ 100.68.2.30:8443
    end
    
    DNAT->>NetPol: 转发包<br/>dst: 100.68.2.30:8443
    
    rect rgb(200, 255, 200)
        Note over NetPol: 第二阶段：NetworkPolicy 检查
        NetPol->>NetPol: 检查 Egress 规则<br/>目标: 100.68.2.30 ✅<br/>端口: 8443 ✅<br/>Namespace: B ✅
        Note over NetPol: Service IP (100.64.5.20)<br/>已经不存在了！
    end
    
    NetPol->>Forward: 允许通过
    Forward->>Node: 路由到目标节点
    Node->>PodB: 交付到 Pod B:8443
    
    Note over App,PodB: 整个过程中 NetworkPolicy<br/>只看到 Pod IP，从未看到 Service IP
```

## Routes-based 模式的完整流量路径

### 同节点场景

```mermaid
graph TD
    subgraph "Node 1 - 192.168.65.10"
        subgraph "Network Namespace: Pod A"
            A1[Pod A<br/>100.68.1.10]
        end
        
        subgraph "Network Namespace: Pod B"
            B1[Pod B<br/>100.68.2.30:8443]
        end
        
        subgraph "Host Network Namespace"
            H1[iptables PREROUTING]
            H2[kube-proxy rules]
            H3[NetworkPolicy<br/>eBPF/iptables]
            H4[Linux Bridge/veth]
        end
    end
    
    A1 -->|1 dst: 100.64.5.20:443| H1
    H1 -->|2 查询规则| H2
    H2 -->|3 DNAT 转换<br/>dst: 100.68.2.30:8443| H3
    H3 -->|4 Egress 检查<br/>看到: 100.68.2.30:8443| H4
    H4 -->|5 路由| B1
    B1 -->|6 Ingress 检查<br/>看到源: 100.68.1.10| B1
    
    style H2 fill:#FFB6C6
    style H3 fill:#90EE90
```

### 跨节点场景（Routes-based 关键）

```mermaid
graph TD
    subgraph "Node 1 - 192.168.65.10"
        subgraph "Pod A Namespace"
            A1[Pod A<br/>100.68.1.10]
        end
        
        subgraph "Host Namespace"
            H1[iptables PREROUTING]
            H2[kube-proxy DNAT]
            H3[NetworkPolicy Egress]
            H4[POSTROUTING]
            H5[eth0: 192.168.65.10]
        end
    end
    
    subgraph "VPC Network"
        VPC[GCP VPC 路由表<br/>100.68.2.0/24 → Node 2]
    end
    
    subgraph "Node 2 - 192.168.65.11"
        subgraph "Host Namespace 2"
            H6[eth0: 192.168.65.11<br/>接收端口 8443]
            H7[PREROUTING]
            H8[NetworkPolicy Ingress]
            H9[veth / Bridge]
        end
        
        subgraph "Pod B Namespace"
            B1[Pod B<br/>100.68.2.30:8443]
        end
    end
    
    A1 -->|dst: 100.64.5.20:443| H1
    H1 -->|DNAT| H2
    H2 -->|dst: 100.68.2.30:8443| H3
    H3 -->|Egress 检查<br/>目标: Pod IP 100.68.2.30<br/>端口: 8443| H4
    
    H4 -->|查路由表:<br/>100.68.2.30 在 Node 2| H5
    H5 -->|物理网络<br/>src: 100.68.1.10<br/>dst: 100.68.2.30:8443| VPC
    
    VPC -->|路由到 Node 2| H6
    H6 -->|接收 8443 端口| H7
    H7 --> H8
    H8 -->|Ingress 检查<br/>源: 100.68.1.10<br/>端口: 8443| H9
    H9 --> B1
    
    style H2 fill:#FFB6C6
    style H3 fill:#90EE90
    style H6 fill:#FFF4E1
    style H8 fill:#90EE90
    
    Note1[关键：DNAT 在 Node 1 完成<br/>跨节点时已经是 Pod IP]
    H2 -.-> Note1
    
    Note2[Node 2 必须开放 8443<br/>因为包的 dst port = 8443]
    H6 -.-> Note2
```

## 为什么不需要 Egress 到 Service IP Range？

### 核心原因对比表

|检查点|Service IP (100.64.x.x)|Pod IP (100.68.x.x)|
|---|---|---|
|**应用层看到**|✅ 100.64.5.20:443|❌ 不知道|
|**DNS 返回**|✅ 100.64.5.20|❌ 不返回|
|**iptables PREROUTING 看到**|✅ 100.64.5.20:443|❌ 还未转换|
|**kube-proxy DNAT 后**|❌ 已被替换|✅ 100.68.2.30:8443|
|**NetworkPolicy 看到**|❌ **根本看不到**|✅ **只看到这个**|
|**物理网络包**|❌ 不存在|✅ 100.68.2.30:8443|

### 包头内容对比

```mermaid
graph LR
    subgraph "应用发送时"
        P1["IP Header:<br/>src: 100.68.1.10<br/>dst: 100.64.5.20<br/>TCP: sport:random dport:443"]
    end
    
    subgraph "kube-proxy DNAT 后"
        P2["IP Header:<br/>src: 100.68.1.10<br/>dst: 100.68.2.30<br/>TCP: sport:random dport:8443"]
    end
    
    subgraph "NetworkPolicy 检查时"
        P3["检查的包:<br/>src: 100.68.1.10<br/>dst: 100.68.2.30<br/>port: 8443"]
    end
    
    P1 -->|DNAT| P2
    P2 -->|传递给| P3
    
    style P1 fill:#FFB6C6
    style P2 fill:#90EE90
    style P3 fill:#90EE90
    
    Note1["Service IP 在这里消失!"]
    P1 -.-> Note1
```

## Routes-based 模式的正确配置

### Namespace A - Egress 配置

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-a-egress
  namespace: namespace-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
  
  egress:
  # ✅ 规则1：允许访问 Namespace B 的 Pod（必需）
  # NetworkPolicy 只看到 Pod IP，所以只需要这个规则
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: namespace-b
    ports:
    - protocol: TCP
      port: 8443  # Pod 端口
  
  # ❌ 不需要：允许访问 Service IP Range
  # 因为 NetworkPolicy 检查时 Service IP 已经被 DNAT 转换了
  # - to:
  #   - ipBlock:
  #       cidr: 100.64.0.0/16
  #   ports:
  #   - protocol: TCP
  #     port: 443
  
  # ✅ 规则2：允许 DNS（必需）
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    - podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

### Namespace B - Ingress 配置

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-b-ingress
  namespace: namespace-b
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
  - Ingress
  
  ingress:
  # ✅ 规则：允许来自 Namespace A 的 Pod（必需）
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: namespace-a
    ports:
    - protocol: TCP
      port: 8443  # Pod 监听的端口
```

### GCP 防火墙规则（Routes-based 必需）

```bash
# 创建防火墙规则允许 Node 间的 Pod 通信
gcloud compute firewall-rules create allow-gke-pod-to-pod \
  --network=YOUR_VPC_NETWORK \
  --action=ALLOW \
  --rules=tcp:8443 \
  --source-ranges=100.64.0.0/14 \
  --target-tags=gke-node \
  --description="Allow pod-to-pod communication on port 8443"

# 或者如果使用 Node IP 范围
gcloud compute firewall-rules create allow-gke-node-to-node \
  --network=YOUR_VPC_NETWORK \
  --action=ALLOW \
  --rules=tcp:8443 \
  --source-ranges=192.168.64.0/19 \
  --target-tags=gke-node \
  --description="Allow node-to-node communication on port 8443"
```

## 完整的 Routes-based 模式流程图

```mermaid
graph TB
    Start[Pod A 发起请求<br/>curl https://svc-b.namespace-b:443]
    
    Start --> DNS[DNS 查询]
    DNS --> DNSResp[返回: 100.64.5.20]
    
    DNSResp --> Send[发送 TCP SYN<br/>dst: 100.64.5.20:443]
    
    Send --> PreRoute[Node 1: PREROUTING]
    
    PreRoute --> Match{匹配 kube-proxy<br/>Service 规则?}
    Match -->|是| DNAT[执行 DNAT<br/>dst: 100.64.5.20:443<br/>→ 100.68.2.30:8443]
    Match -->|否| Drop1[丢弃]
    
    DNAT --> EgressCheck[NetworkPolicy<br/>Egress 检查]
    
    EgressCheck --> EgressRule{检查规则}
    EgressRule -->|目标 Namespace: B ✅<br/>目标端口: 8443 ✅| EgressPass[Egress 通过]
    EgressRule -->|不匹配| Drop2[Egress 拒绝]
    
    EgressPass --> Route{路由判断}
    
    Route -->|同节点| Local[本地转发<br/>通过 veth pair]
    Route -->|跨节点| Remote[发送到 Node 2<br/>通过物理网络]
    
    Local --> IngressCheck[NetworkPolicy<br/>Ingress 检查]
    
    Remote --> Node2[Node 2 eth0<br/>接收 8443 端口]
    Node2 --> GCPFirewall{GCP 防火墙<br/>允许 8443?}
    GCPFirewall -->|✅ 允许| IngressCheck
    GCPFirewall -->|❌ 拒绝| Drop3[防火墙拒绝]
    
    IngressCheck --> IngressRule{检查规则}
    IngressRule -->|源 Namespace: A ✅<br/>目标端口: 8443 ✅| IngressPass[Ingress 通过]
    IngressRule -->|不匹配| Drop4[Ingress 拒绝]
    
    IngressPass --> PodB[Pod B 接收请求]
    PodB --> Response[处理并响应]
    
    Response --> Success[✅ 连接成功]
    
    Drop1 --> Fail[❌ 连接失败]
    Drop2 --> Fail
    Drop3 --> Fail
    Drop4 --> Fail
    
    style DNAT fill:#FFB6C6
    style EgressCheck fill:#90EE90
    style IngressCheck fill:#90EE90
    style GCPFirewall fill:#FFF4E1
    style Success fill:#90EE90
    style Fail fill:#FFB6C6
    
    Note1["关键点 1:<br/>DNAT 在 NetworkPolicy 之前<br/>所以 NetworkPolicy 看不到 Service IP"]
    DNAT -.-> Note1
    
    Note2["关键点 2:<br/>Routes-based 需要 GCP 防火墙<br/>允许 Node 间的 Pod 端口"]
    GCPFirewall -.-> Note2
    
    Note3["关键点 3:<br/>NetworkPolicy 检查的是<br/>Pod IP:8443<br/>不是 Service IP:443"]
    EgressCheck -.-> Note3
```

## 实际验证方法

### 1. 抓包验证 DNAT 转换

```bash
# 在 Node 1 上抓包（Pod A 所在节点）
# 观察 PREROUTING 之前
sudo tcpdump -i any -nn 'host 100.64.5.20 and port 443'
# 预期：能看到目标是 Service IP:443

# 观察 POSTROUTING 之后
sudo tcpdump -i any -nn 'host 100.68.2.30 and port 8443'
# 预期：能看到目标已经是 Pod IP:8443
```

### 2. 查看 iptables 规则

```bash
# 查看 kube-proxy 创建的 DNAT 规则
sudo iptables -t nat -L KUBE-SERVICES -n | grep "100.64.5.20"
# 输出示例：
# KUBE-SVC-XXX  tcp  --  0.0.0.0/0  100.64.5.20  tcp dpt:443

sudo iptables -t nat -L KUBE-SVC-XXX -n
# 输出示例：
# DNAT  tcp  --  0.0.0.0/0  0.0.0.0/0  to:100.68.2.30:8443
```

### 3. 测试 NetworkPolicy 实际行为

```bash
# 测试1：临时添加 Service IP Range 规则（不应该有影响）
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-service-ip-egress
  namespace: namespace-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 100.64.0.0/16
    ports:
    - protocol: TCP
      port: 443
EOF

# 测试连接（预期：仍然失败，因为 NetworkPolicy 看不到 Service IP）
kubectl exec -it pod-a -n namespace-a -- \
  curl -v https://svc-b.namespace-b:443

# 删除测试规则
kubectl delete networkpolicy test-service-ip-egress -n namespace-a
```

## 总结：为什么不需要 Service IP Range 规则

### 三个核心事实

1. **时序问题**：
    
    ```
    包到达 → PREROUTING → kube-proxy DNAT → NetworkPolicy 检查
                         ↑
                     Service IP 在这里消失
    ```
    
2. **NetworkPolicy 的视角**：
    
    - NetworkPolicy 是一个 **L3/L4 过滤器**
    - 它工作在 **iptables FORWARD 链**
    - 在它看到包时，**DNAT 已经完成**
3. **实际网络包内容**：
    
    ```
    应用发送：dst=100.64.5.20:443
    ↓ DNAT
    NetworkPolicy 看到：dst=100.68.2.30:8443
    ```
    

### 配置清单（Routes-based 模式）

|组件|配置项|目标|端口|必需？|
|---|---|---|---|---|
|Namespace A Egress|namespaceSelector|namespace-b|8443|✅ 必需|
|Namespace A Egress|ipBlock|~~100.64.0.0/16~~|~~443~~|❌ **不需要**|
|Namespace A Egress|kube-system DNS|kube-dns|53|✅ 必需|
|Namespace B Ingress|namespaceSelector|namespace-a|8443|✅ 必需|
|GCP 防火墙|source-ranges|100.64.0.0/14|8443|✅ 必需|
|GCP 防火墙|source-ranges|192.168.64.0/19|8443|⚠️ 推荐|

**最终答案**：在 Routes-based 模式下，您**不需要**配置 Egress 到 Service IP Range 的规则，因为 NetworkPolicy 在检查时，Service IP 已经被 kube-proxy DNAT 转换成了 Pod IP。NetworkPolicy 从头到尾都看不到 Service IP！


# Why need pod ip 
# 关键纠正：必须配置 Pod IP Range！

您的理解有一个**重要的误区**，让我详细解释为什么**必须**配置针对 Pod IP 的规则。

## 核心误解澄清

```mermaid
graph LR
    subgraph "❌ 错误理解"
        E1[不需要 Service IP 规则] --> E2[所以也不需要 Pod IP 规则?]
        E2 --> E3[❌ 错误推论]
    end
    
    subgraph "✅ 正确理解"
        C1[不需要 Service IP 规则] --> C2[因为 NetworkPolicy 看不到]
        C3[必须配置 Pod IP 规则] --> C4[因为 NetworkPolicy 只看到这个!]
    end
    
    style E3 fill:#FFB6C6
    style C4 fill:#90EE90
```

## 关键区别对比

|对象|Service IP|Pod IP|
|---|---|---|
|**是否存在于网络包中**|❌ 仅在 DNAT 前存在<br/>DNAT 后被替换|✅ DNAT 后一直存在<br/>直到到达目标|
|**NetworkPolicy 能否看到**|❌ 完全看不到|✅ **这是唯一能看到的**|
|**是否需要配置规则**|❌ 不需要<br/>(配了也没用)|✅ **必须配置**<br/>(不配就被拒绝)|
|**在包头中的位置**|临时存在于应用层|实际的 IP 包目标地址|

## 详细的包内容对比

```mermaid
sequenceDiagram
    participant App as 应用层
    participant Socket as Socket/DNS
    participant PreDNAT as DNAT 之前
    participant PostDNAT as DNAT 之后
    participant NetPol as NetworkPolicy
    participant Wire as 物理网络
    
    App->>Socket: 请求 svc-b.namespace-b:443
    Socket->>PreDNAT: DNS 解析<br/>得到 Service IP
    
    rect rgb(255, 240, 240)
        Note over PreDNAT: 这个阶段的包头
        PreDNAT->>PreDNAT: IP dst: 100.64.5.20<br/>TCP dport: 443
        Note over PreDNAT: Service IP 存在<br/>但 NetworkPolicy 还没检查
    end
    
    PreDNAT->>PostDNAT: kube-proxy DNAT
    
    rect rgb(255, 200, 200)
        Note over PostDNAT: DNAT 转换
        PostDNAT->>PostDNAT: IP dst: 100.64.5.20 ❌<br/>→ 100.68.2.30 ✅<br/>TCP dport: 443 ❌<br/>→ 8443 ✅
        Note over PostDNAT: Service IP 消失!<br/>变成 Pod IP
    end
    
    PostDNAT->>NetPol: 传递网络包
    
    rect rgb(200, 255, 200)
        Note over NetPol: NetworkPolicy 检查
        NetPol->>NetPol: 看到的包头:<br/>IP dst: 100.68.2.30 ✅<br/>TCP dport: 8443 ✅
        Note over NetPol: 只能看到 Pod IP!<br/>Service IP 已经不存在
        
        NetPol->>NetPol: 检查 Egress 规则:<br/>是否允许访问<br/>100.68.2.30:8443?
        
        alt 有 Pod IP 规则
            NetPol->>NetPol: ✅ 匹配规则<br/>允许通过
        else 没有 Pod IP 规则
            NetPol->>NetPol: ❌ 不匹配任何规则<br/>默认拒绝
        end
    end
    
    NetPol->>Wire: 发送到网络
    Wire->>Wire: 包头内容:<br/>IP dst: 100.68.2.30<br/>TCP dport: 8443
    
    Note over App,Wire: 从 DNAT 之后到目标 Pod<br/>一直都是 Pod IP: 100.68.2.30
```

## 为什么必须配置 Pod IP 规则

### 原因 1：NetworkPolicy 的检查点

```mermaid
graph TD
    Packet[网络包] --> Q1{经过了<br/>DNAT 吗?}
    
    Q1 -->|否| Before[包头内容:<br/>dst: Service IP]
    Q1 -->|是| After[包头内容:<br/>dst: Pod IP]
    
    Before --> Q2{NetworkPolicy<br/>在哪里检查?}
    After --> Q2
    
    Q2 --> Answer[❗在 DNAT 之后]
    
    Answer --> Result[所以 NetworkPolicy<br/>只能看到 Pod IP]
    
    Result --> Conclusion[✅ 必须配置<br/>Pod IP 规则]
    
    style Before fill:#FFB6C6
    style After fill:#90EE90
    style Conclusion fill:#90EE90
```

### 原因 2：默认拒绝策略的工作原理

```yaml
# 您的配置：默认 deny all
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: namespace-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress: []  # 空数组 = 拒绝所有
```

**工作逻辑**：

```mermaid
graph TD
    Start[Pod A 发出包] --> Check[NetworkPolicy 检查]
    
    Check --> Loop{遍历所有<br/>Egress 规则}
    
    Loop --> Rule1{规则 1 匹配?}
    Rule1 -->|匹配| Allow[✅ 允许]
    Rule1 -->|不匹配| Rule2{规则 2 匹配?}
    Rule2 -->|匹配| Allow
    Rule2 -->|不匹配| RuleN{更多规则?}
    RuleN -->|是| Loop
    RuleN -->|否| Deny[❌ 默认拒绝]
    
    Check -.->|看到的包| PacketInfo["dst: 100.68.2.30:8443<br/>(Pod IP，不是 Service IP)"]
    
    style Deny fill:#FFB6C6
    style Allow fill:#90EE90
    style PacketInfo fill:#FFF4E1
```

**关键点**：

- NetworkPolicy 检查时，包头中的目标 IP 是 `100.68.2.30`（Pod IP）
- 如果没有规则匹配 `100.68.2.30`，就会被拒绝
- 即使有 Service IP 的规则（`100.64.5.20`），也不会匹配，因为包头中没有这个 IP

## 实际验证：没有 Pod IP 规则会发生什么

### 实验 1：只配置 Service IP 规则（错误）

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: wrong-config
  namespace: namespace-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  # ❌ 错误：只允许 Service IP
  - to:
    - ipBlock:
        cidr: 100.64.0.0/16  # Service IP Range
    ports:
    - protocol: TCP
      port: 443
  # DNS 规则省略
```

**测试结果**：

```bash
# 测试连接
kubectl exec -it pod-a -n namespace-a -- \
  curl -v --connect-timeout 5 https://svc-b.namespace-b:443

# 结果：
# * connect to 100.64.5.20 port 443 failed: Connection timed out
# ❌ 连接失败
```

**失败原因分析**：

```mermaid
graph LR
    A[发送包<br/>dst: 100.64.5.20:443] --> B[DNAT 转换]
    B --> C[包变为<br/>dst: 100.68.2.30:8443]
    C --> D[NetworkPolicy 检查]
    D --> E{匹配规则?}
    
    E --> F[规则: 100.64.0.0/16]
    F --> G[包的 dst: 100.68.2.30]
    G --> H{100.68.2.30<br/>在 100.64.0.0/16 中?}
    H -->|❌ 不在| I[拒绝]
    
    style I fill:#FFB6C6
```

### 实验 2：只配置 Pod IP 规则（正确）

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: correct-config
  namespace: namespace-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  # ✅ 正确：允许访问目标 Namespace 的 Pod
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: namespace-b
    ports:
    - protocol: TCP
      port: 8443  # Pod 端口
```

**测试结果**：

```bash
# 测试连接
kubectl exec -it pod-a -n namespace-a -- \
  curl -v --connect-timeout 5 https://svc-b.namespace-b:443

# 结果：
# * Connected to svc-b.namespace-b (100.64.5.20) port 443
# ✅ 连接成功
```

**成功原因分析**：

```mermaid
graph LR
    A[发送包<br/>dst: 100.64.5.20:443] --> B[DNAT 转换]
    B --> C[包变为<br/>dst: 100.68.2.30:8443]
    C --> D[NetworkPolicy 检查]
    D --> E{匹配规则?}
    
    E --> F[规则: namespace-b<br/>port: 8443]
    F --> G[包的 dst: 100.68.2.30<br/>在 namespace-b]
    G --> H{匹配?}
    H -->|✅ 是| I[允许]
    
    style I fill:#90EE90
```


#### Using select

## 核心理解

```mermaid
graph TD
    Question[您的疑惑]
    
    Question --> Q1["为什么不需要配置<br/>ipBlock: 100.64.0.0/14?"]
    Question --> Q2["只用 namespaceSelector<br/>就够了吗?"]
    
    Q1 --> A1[✅ 是的!<br/>namespaceSelector 已经足够]
    Q2 --> A2[✅ 完全正确!<br/>不需要 ipBlock]
    
    A1 --> Reason[原因]
    A2 --> Reason
    
    Reason --> R1["namespaceSelector 会:<br/>1. 通过 K8s API 查询<br/>2. 自动匹配该 Namespace 的所有 Pod IP<br/>3. 动态更新"]
    
    style A1 fill:#90EE90
    style A2 fill:#90EE90
```

## 两种配置方式对比

### 方式 1：namespaceSelector（您使用的，推荐）

```yaml
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: namespace-b
  ports:
  - protocol: TCP
    port: 8443
```

**工作原理**：

```mermaid
graph LR
    Packet[收到网络包<br/>dst: 100.68.2.30:8443] --> Step1[NetworkPolicy 处理]
    
    Step1 --> Step2[通过 K8s API 查询:<br/>100.68.2.30 属于哪个 Pod?]
    
    Step2 --> Step3[找到 Pod:<br/>name: pod-b<br/>namespace: namespace-b<br/>labels: app=server]
    
    Step3 --> Step4{检查 namespace-b<br/>是否匹配规则?}
    
    Step4 -->|✅ 匹配| Allow[允许]
    Step4 -->|❌ 不匹配| Deny[拒绝]
    
    style Allow fill:#90EE90
    style Deny fill:#FFB6C6
```

**特点**：

- ✅ **不需要知道具体 IP 范围**
- ✅ 动态适配 Pod IP 变化
- ✅ 语义化：匹配 Namespace，不关心 IP
- ✅ 更符合 Kubernetes 声明式理念

### 方式 2：ipBlock（也可以，但不推荐）

```yaml
egress:
- to:
  - ipBlock:
      cidr: 100.64.0.0/14  # 整个 Pod IP Range
  ports:
  - protocol: TCP
    port: 8443
```

**工作原理**：

```mermaid
graph LR
    Packet[收到网络包<br/>dst: 100.68.2.30:8443] --> Step1[NetworkPolicy 处理]
    
    Step1 --> Step2{100.68.2.30<br/>在 100.64.0.0/14 范围内?}
    
    Step2 -->|✅ 在范围内| Allow[允许]
    Step2 -->|❌ 不在范围内| Deny[拒绝]
    
    style Allow fill:#90EE90
    style Deny fill:#FFB6C6
```

**特点**：

- ⚠️ 需要知道 Pod IP 范围
- ⚠️ 权限过大（允许整个 CIDR）
- ⚠️ 不区分 Namespace
- ✅ 性能略好（无需 API 查询）

## 完整对比表

|特性|namespaceSelector|ipBlock (Pod CIDR)|ipBlock (Service CIDR)|
|---|---|---|---|
|**需要配置 IP 范围**|❌ 不需要|✅ 需要|✅ 需要|
|**能否工作**|✅ 完美工作|✅ 可以工作|❌ **完全无效**|
|**原因**|K8s API 查询|直接匹配 IP|Service IP 已被 DNAT|
|**动态适配 Pod 变化**|✅ 自动适配|✅ 自动适配|N/A|
|**精确控制**|✅ 到 Namespace 级别|⚠️ 到 CIDR 级别|N/A|
|**可读性**|✅ 语义清晰|⚠️ 需要理解 IP 规划|N/A|
|**推荐程度**|⭐⭐⭐⭐⭐|⭐⭐⭐|❌ 无效|

## 为什么 namespaceSelector 不需要 IP Range？

### 详细工作流程

```mermaid
sequenceDiagram
    participant Packet as 网络包<br/>dst: 100.68.2.30:8443
    participant CNI as CNI Plugin<br/>(NetworkPolicy 执行者)
    participant API as Kubernetes API
    participant Cache as 本地缓存
    
    Packet->>CNI: 检查 Egress 规则
    
    Note over CNI: 看到规则:<br/>namespaceSelector:<br/>  namespace-b
    
    CNI->>Cache: 查询缓存:<br/>100.68.2.30 的元数据
    
    alt 缓存命中
        Cache-->>CNI: Pod: pod-b<br/>Namespace: namespace-b
    else 缓存未命中
        CNI->>API: GET /api/v1/pods?fieldSelector=status.podIP=100.68.2.30
        API-->>CNI: Pod: pod-b<br/>Namespace: namespace-b<br/>Labels: {...}
        CNI->>Cache: 更新缓存
    end
    
    CNI->>CNI: 检查: namespace-b<br/>匹配规则? ✅
    
    CNI->>Packet: 允许通过
    
    Note over CNI,API: 整个过程不需要知道<br/>100.64.0.0/14 这个 IP 范围
```

### 关键点

```yaml
# 这个配置的含义是：
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: namespace-b
  ports:
  - protocol: TCP
    port: 8443
```

**解读**：

```
允许 Egress 到：
  - 目标：任何属于 namespace-b 的 Pod（不管 IP 是什么）
  - 端口：8443
```

**不是**：

```
允许 Egress 到：
  - 目标：IP 范围 100.68.x.x 的 Pod
  - 端口：8443
```

## 实际验证

### 验证 1：namespaceSelector 自动匹配所有 Pod IP

```bash
# 假设 namespace-b 有多个 Pod，IP 各不相同
kubectl get pods -n namespace-b -o wide

# 输出示例：
# NAME      IP            NODE
# pod-b-1   100.68.2.30   node-1
# pod-b-2   100.68.2.31   node-2
# pod-b-3   100.68.3.50   node-3

# 测试：都能访问
kubectl exec -it pod-a -n namespace-a -- curl -k https://100.68.2.30:8443
# ✅ 成功

kubectl exec -it pod-a -n namespace-a -- curl -k https://100.68.2.31:8443
# ✅ 成功

kubectl exec -it pod-a -n namespace-a -- curl -k https://100.68.3.50:8443
# ✅ 成功（注意：这个 IP 在不同的子网）
```

**原因**：namespaceSelector 不关心 IP 地址，只关心 Namespace

### 验证 2：ipBlock 的局限性

```yaml
# 如果使用 ipBlock
egress:
- to:
  - ipBlock:
      cidr: 100.68.2.0/24  # 只允许这个子网
  ports:
  - protocol: TCP
    port: 8443
```

```bash
kubectl exec -it pod-a -n namespace-a -- curl -k https://100.68.2.30:8443
# ✅ 成功（在 100.68.2.0/24 范围内）

kubectl exec -it pod-a -n namespace-a -- curl -k https://100.68.3.50:8443
# ❌ 失败（不在 100.68.2.0/24 范围内）
```

## 您的配置完全正确！

### 基于您的需求，正确的配置

```yaml
# ============================================
# Namespace A Egress - 完全正确的配置
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-a-egress
  namespace: namespace-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  
  # ✅ 规则 1：访问 namespace-b（您的配置）
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: namespace-b
    ports:
    - protocol: TCP
      port: 8443
  
  # ✅ 规则 2：DNS 解析
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    - podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53

---
# ============================================
# Namespace B Ingress - 完全正确的配置
# ============================================
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-b-ingress
  namespace: namespace-b
spec:
  podSelector:
    matchLabels:
      app: your-app-b  # 根据实际标签修改
  policyTypes:
  - Ingress
  ingress:
  
  # ✅ 规则：允许来自 namespace-a
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: namespace-a
    ports:
    - protocol: TCP
      port: 8443
```

## 总结：您的理解完全正确

```mermaid
graph TD
    Your[您的理解]
    
    Your --> U1["不需要配置<br/>ipBlock: 100.64.0.0/14"]
    Your --> U2["只需要<br/>namespaceSelector"]
    Your --> U3["不需要关心<br/>具体的 Pod IP"]
    
    U1 --> C1[✅ 完全正确]
    U2 --> C2[✅ 完全正确]
    U3 --> C3[✅ 完全正确]
    
    C1 --> Reason[原因：]
    C2 --> Reason
    C3 --> Reason
    
    Reason --> R1["namespaceSelector 通过<br/>Kubernetes API 自动识别<br/>该 Namespace 的所有 Pod"]
    Reason --> R2["无需手动指定 IP 范围"]
    Reason --> R3["更灵活、更语义化"]
    
    style C1 fill:#90EE90
    style C2 fill:#90EE90
    style C3 fill:#90EE90
```

### 关键要点

|您的疑惑|答案|
|---|---|
|**需要配置 Pod IP Range 吗？**|❌ **不需要**|
|**只用 namespaceSelector 够吗？**|✅ **完全够**|
|**为什么不需要 IP Range？**|namespaceSelector 通过 K8s API 自动匹配|
|**这样配置正确吗？**|✅ **完全正确，推荐方式**|

之前我的解释可能让您误解了。您的理解是对的：

- ❌ **不需要**配置 `ipBlock: 100.64.0.0/14`
- ✅ **只需要**配置 `namespaceSelector: namespace-b`
- ✅ NetworkPolicy 会自动通过 K8s API 找到该 Namespace 的所有 Pod IP

这就是 Kubernetes NetworkPolicy 的优雅之处！

## namespaceSelector 的工作原理

您可能疑惑：为什么 `namespaceSelector` 能匹配到 Pod IP？

```mermaid
graph TD
    subgraph "NetworkPolicy 匹配逻辑"
        Check[收到包<br/>dst: 100.68.2.30:8443]
        
        Check --> Step1[1. 查询 K8s API]
        Step1 --> Step2[2. 找到 100.68.2.30<br/>对应的 Pod]
        Step2 --> Step3[3. 获取 Pod 的<br/>Namespace: namespace-b]
        Step3 --> Step4[4. 检查 namespace-b<br/>是否匹配规则]
        Step4 --> Step5{匹配<br/>namespace-b?}
        Step5 -->|✅ 是| Allow[允许]
        Step5 -->|❌ 否| Deny[拒绝]
    end
    
    subgraph "Kubernetes 元数据"
        Meta["Pod: pod-b<br/>IP: 100.68.2.30<br/>Namespace: namespace-b<br/>Labels: app=server"]
    end
    
    Step2 -.->|查询| Meta
    
    style Allow fill:#90EE90
    style Deny fill:#FFB6C6
```

**关键点**：

- `namespaceSelector` 不是直接匹配 IP 地址
- 而是先通过 IP 找到 Pod 对象
- 然后检查 Pod 所在的 Namespace
- 这就是为什么它能工作！

## 完整的规则配置逻辑

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-a-egress
  namespace: namespace-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  
  # ✅ 方式 1：使用 namespaceSelector（推荐）
  # 匹配机制：IP → Pod → Namespace → 检查 Label
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: namespace-b
    ports:
    - protocol: TCP
      port: 8443
  
  # ✅ 方式 2：直接指定 Pod IP Range（也可以）
  # 匹配机制：直接检查 IP 是否在 CIDR 范围内
  # - to:
  #   - ipBlock:
  #       cidr: 100.64.0.0/14  # Pod IP Range
  #   ports:
  #   - protocol: TCP
  #     port: 8443
  
  # ❌ 方式 3：指定 Service IP Range（无效！）
  # 匹配失败原因：NetworkPolicy 检查时包中没有 Service IP
  # - to:
  #   - ipBlock:
  #       cidr: 100.64.0.0/16  # Service IP Range
  #   ports:
  #   - protocol: TCP
  #     port: 443
```

## 两种有效配置方式对比

### 方式 1：namespaceSelector（推荐）

```yaml
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: namespace-b
  ports:
  - protocol: TCP
    port: 8443
```

**优点**：

- ✅ 不需要知道具体的 Pod IP
- ✅ Pod IP 变化时无需修改规则
- ✅ 更符合 Kubernetes 的声明式理念
- ✅ 支持动态 Pod 伸缩

**缺点**：

- ⚠️ 依赖 Kubernetes API 查询
- ⚠️ 轻微性能开销（通常可忽略）

### 方式 2：ipBlock with Pod CIDR

```yaml
egress:
- to:
  - ipBlock:
      cidr: 100.64.0.0/14  # 整个 Pod IP Range
      # 或者更精确：
      # cidr: 100.68.2.0/24  # namespace-b 的 Pod 子网
  ports:
  - protocol: TCP
    port: 8443
```

**优点**：

- ✅ 性能最优（直接 IP 匹配）
- ✅ 不依赖 API 查询

**缺点**：

- ❌ 需要知道 Pod IP 范围
- ❌ 权限范围可能过大（允许整个 CIDR）
- ❌ 如果 Pod CIDR 变化需要更新规则

## 完整验证流程

```bash
# 1. 部署错误配置（只有 Service IP 规则）
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-wrong
  namespace: namespace-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 100.64.0.0/16
    ports:
    - protocol: TCP
      port: 443
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

# 2. 测试连接（预期失败）
kubectl exec -it pod-a -n namespace-a -- \
  timeout 10 curl -v https://svc-b.namespace-b:443
# 结果：Connection timed out ❌

# 3. 在目标 Pod 上抓包验证
kubectl exec -it pod-b -n namespace-b -- \
  timeout 20 tcpdump -i any -nn port 8443 &

# 4. 再次发起连接
kubectl exec -it pod-a -n namespace-a -- \
  timeout 10 curl -v https://svc-b.namespace-b:443

# 抓包结果：没有任何包到达！证明被 Egress 阻止

# 5. 修改为正确配置（Pod IP 规则）
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-correct
  namespace: namespace-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: namespace-b
    ports:
    - protocol: TCP
      port: 8443
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

# 6. 再次测试（预期成功）
kubectl exec -it pod-a -n namespace-a -- \
  curl -v https://svc-b.namespace-b:443
# 结果：连接成功 ✅

# 7. 抓包验证
kubectl exec -it pod-b -n namespace-b -- \
  tcpdump -i any -nn port 8443 -c 5
# 抓包结果：能看到来自 100.68.1.10 的包
```

## 总结：必须配置的原因

```mermaid
graph TD
    Q[为什么必须配置 Pod IP 规则?]
    
    Q --> R1[原因 1:<br/>NetworkPolicy 在 DNAT 之后检查]
    Q --> R2[原因 2:<br/>包头中只有 Pod IP]
    Q --> R3[原因 3:<br/>Service IP 已经被替换]
    Q --> R4[原因 4:<br/>默认 deny 策略需要明确允许]
    
    R1 --> C[结论:<br/>NetworkPolicy 只能看到 Pod IP]
    R2 --> C
    R3 --> C
    R4 --> C
    
    C --> A[✅ 必须配置匹配 Pod IP 的规则<br/>❌ 配置 Service IP 规则无效]
    
    style Q fill:#e1f5ff
    style A fill:#90EE90
```

### 关键要点

|问题|答案|
|---|---|
|**需要配置 Service IP 规则吗？**|❌ 不需要（NetworkPolicy 看不到）|
|**需要配置 Pod IP 规则吗？**|✅ **必须**（这是 NetworkPolicy 唯一能看到的）|
|**为什么不需要 Service IP？**|因为 DNAT 在 NetworkPolicy 之前完成|
|**为什么必须配置 Pod IP？**|因为 NetworkPolicy 检查时，包中只有 Pod IP|
|**如何配置 Pod IP 规则？**|使用 `namespaceSelector` 或 `ipBlock: 100.64.0.0/14`|
|**Service IP 去哪了？**|被 kube-proxy 的 DNAT 规则替换成 Pod IP|

**最终答案**：不需要 Service IP 规则不代表不需要 Pod IP 规则，恰恰相反，**Pod IP 规则是唯一有效且必须的规则**，因为 NetworkPolicy 只能看到经过 DNAT 转换后的 Pod IP！