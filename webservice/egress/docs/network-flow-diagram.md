# 网络流量图和架构详解

## 1. 详细网络流量图

### 1.1 完整流量路径图

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    GKE Cluster                                         │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                              API Namespace                                          │ │
│  │                                                                                     │ │
│  │  ┌─────────────────┐                                                               │ │
│  │  │   API Pod       │  1. HTTP Request                                              │ │
│  │  │                 │  ──────────────────────────────────────────────────────────┐ │ │
│  │  │ ENV:            │                                                             │ │ │
│  │  │ HTTP_PROXY=     │                                                             │ │ │
│  │  │ microsoft.intra │                                                             │ │ │
│  │  │ .aibang.local   │                                                             │ │ │
│  │  │ :3128           │                                                             │ │ │
│  │  └─────────────────┘                                                             │ │ │
│  └─────────────────────────────────────────────────────────────────────────────────┼─┘ │
│                                                                                      │   │
│  ┌─────────────────────────────────────────────────────────────────────────────────┼─┐ │
│  │                           intra-proxy Namespace                                  │ │ │
│  │                                                                                  │ │ │
│  │  2. DNS Resolution: microsoft.intra.aibang.local                                │ │ │
│  │     → squid-proxy-service.intra-proxy.svc.cluster.local                         │ │ │
│  │                                                                                  ▼ │ │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐              │ │ │
│  │  │   Squid Pod 1   │    │   Squid Pod 2   │    │   Squid Pod N   │              │ │ │
│  │  │                 │    │                 │    │                 │              │ │ │
│  │  │ Port: 3128      │    │ Port: 3128      │    │ Port: 3128      │              │ │ │
│  │  │                 │    │                 │    │                 │              │ │ │
│  │  │ cache_peer:     │    │ cache_peer:     │    │ cache_peer:     │              │ │ │
│  │  │ int-proxy       │    │ int-proxy       │    │ int-proxy       │              │ │ │
│  │  │ .aibang.com     │    │ .aibang.com     │    │ .aibang.com     │              │ │ │
│  │  │ :3128           │    │ :3128           │    │ :3128           │              │ │ │
│  │  └─────────────────┘    └─────────────────┘    └─────────────────┘              │ │ │
│  │           │                       │                       │                      │ │ │
│  │           └───────────────────────┼───────────────────────┘                      │ │ │
│  │                                   │                                              │ │ │
│  │  ┌─────────────────────────────────┼─────────────────────────────────────────────┐ │ │ │
│  │  │              Service Load Balancer                                          │ │ │ │
│  │  │         squid-proxy-service (ClusterIP)                                     │ │ │ │
│  │  └─────────────────────────────────┼─────────────────────────────────────────────┘ │ │ │
│  └─────────────────────────────────────┼─────────────────────────────────────────────┘ │ │
└─────────────────────────────────────────┼─────────────────────────────────────────────────┘
                                          │
                                          │ 3. Forward to cache_peer
                                          │    (GKE → GCE internal network)
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                  GCE VM Instance                                        │
│                              int-proxy.aibang.com                                      │
│                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                              Squid Proxy (二级代理)                                  │ │
│  │                                                                                     │ │
│  │  ┌─────────────────┐                                                               │ │
│  │  │  Squid Process  │  4. ACL Check & Forward                                       │ │
│  │  │                 │  ──────────────────────────────────────────────────────────┐ │ │
│  │  │ Port: 3128      │                                                             │ │ │
│  │  │                 │  • Source IP validation                                     │ │ │
│  │  │ ACL Rules:      │  • Domain whitelist check                                  │ │ │
│  │  │ - gke_cluster   │  • Audit logging                                           │ │ │
│  │  │ - microsoft_*   │                                                             │ │ │
│  │  │                 │                                                             │ │ │
│  │  └─────────────────┘                                                             │ │ │
│  └─────────────────────────────────────────────────────────────────────────────────┼─┘ │
└─────────────────────────────────────────────────────────────────────────────────────┼───┘
                                                                                        │
                                                                                        │ 5. Direct Internet Access
                                                                                        │    (VM → External)
                                                                                        ▼
                                  ┌─────────────────────────────────────┐
                                  │            Internet                 │
                                  │                                     │
                                  │  ┌─────────────────────────────────┐ │
                                  │  │     login.microsoft.com         │ │
                                  │  │     graph.microsoft.com         │ │
                                  │  │     *.microsoftonline.com       │ │
                                  │  └─────────────────────────────────┘ │
                                  └─────────────────────────────────────┘
```

### 1.2 网络层次详解

#### Layer 1: API Pod 层
```
┌─────────────────────────────────────────────────────────────────┐
│                        API Pod                                  │
│                                                                 │
│  Application Code:                                              │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ import requests                                             │ │
│  │                                                             │ │
│  │ # 自动使用环境变量中的代理                                      │ │
│  │ response = requests.get(                                    │ │
│  │     'https://login.microsoft.com/oauth2/token'              │ │
│  │ )                                                           │ │
│  │                                                             │ │
│  │ # 或者显式指定代理                                            │ │
│  │ proxies = {                                                 │ │
│  │     'http': 'http://microsoft.intra.aibang.local:3128',     │ │
│  │     'https': 'http://microsoft.intra.aibang.local:3128'     │ │
│  │ }                                                           │ │
│  │ response = requests.get(url, proxies=proxies)               │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Environment Variables:                                         │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ HTTP_PROXY=http://microsoft.intra.aibang.local:3128         │ │
│  │ HTTPS_PROXY=http://microsoft.intra.aibang.local:3128        │ │
│  │ NO_PROXY=localhost,127.0.0.1,.cluster.local,.svc           │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

#### Layer 2: DNS 解析层
```
┌─────────────────────────────────────────────────────────────────┐
│                      CoreDNS Resolution                        │
│                                                                 │
│  Query: microsoft.intra.aibang.local                           │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                                                             │ │
│  │  1. Pod queries CoreDNS                                     │ │
│  │     microsoft.intra.aibang.local → ?                       │ │
│  │                                                             │ │
│  │  2. CoreDNS custom config matches                           │ │
│  │     Rewrite rule applies                                    │ │
│  │                                                             │ │
│  │  3. Returns ClusterIP                                       │ │
│  │     squid-proxy-service.intra-proxy.svc.cluster.local      │ │
│  │     → 10.96.x.x (ClusterIP)                                │ │
│  │                                                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

#### Layer 3: GKE Squid 层
```
┌─────────────────────────────────────────────────────────────────┐
│                    GKE Squid Proxy Layer                       │
│                                                                 │
│  Request Processing Flow:                                       │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                                                             │ │
│  │  1. Receive HTTP CONNECT/GET request                        │ │
│  │     Source: 10.128.x.x (Pod IP)                            │ │
│  │     Target: login.microsoft.com:443                        │ │
│  │                                                             │ │
│  │  2. ACL Validation                                          │ │
│  │     ✓ Source IP in localnet ACL                            │ │
│  │     ✓ Target domain in allowed_domains ACL                 │ │
│  │     ✓ Port 443 in Safe_ports ACL                           │ │
│  │                                                             │ │
│  │  3. Cache Peer Forwarding                                   │ │
│  │     Forward to: int-proxy.aibang.com:3128                  │ │
│  │     Method: Parent proxy (never_direct)                    │ │
│  │                                                             │ │
│  │  4. Logging                                                 │ │
│  │     Log format: timestamp source target status             │ │
│  │                                                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

#### Layer 4: GCE VM Squid 层
```
┌─────────────────────────────────────────────────────────────────┐
│                    GCE VM Squid Proxy Layer                    │
│                                                                 │
│  Request Processing Flow:                                       │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                                                             │ │
│  │  1. Receive forwarded request                               │ │
│  │     Source: 10.128.x.x (GKE Squid IP)                      │ │
│  │     Target: login.microsoft.com:443                        │ │
│  │                                                             │ │
│  │  2. Secondary ACL Validation                                │ │
│  │     ✓ Source IP in gke_cluster ACL                         │ │
│  │     ✓ Target domain in microsoft_domains ACL               │ │
│  │     ✓ Business hours check (optional)                      │ │
│  │                                                             │ │
│  │  3. Direct Internet Access                                  │ │
│  │     Establish connection to login.microsoft.com:443        │ │
│  │     Use VM's external IP as source                         │ │
│  │                                                             │ │
│  │  4. Enhanced Logging & Auditing                            │ │
│  │     Detailed request/response logging                      │ │
│  │     Security event correlation                             │ │
│  │                                                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## 2. 网络配置详解

### 2.1 IP 地址规划

```
┌─────────────────────────────────────────────────────────────────┐
│                      IP Address Planning                        │
│                                                                 │
│  GKE Cluster Network:                                           │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ Pod CIDR:        10.128.0.0/20   (Pod IPs)                 │ │
│  │ Service CIDR:    10.96.0.0/12    (Service ClusterIPs)      │ │
│  │ Node CIDR:       10.128.16.0/20  (Node IPs)                │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  GCE VM Network:                                                │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ Internal IP:     10.128.2.100    (VM internal)             │ │
│  │ External IP:     35.x.x.x        (VM external, optional)   │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  DNS Mappings:                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ microsoft.intra.aibang.local → 10.96.x.x (Service IP)      │ │
│  │ int-proxy.aibang.com → 10.128.2.100 (VM internal IP)       │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 防火墙规则详解

```yaml
# 防火墙规则配置
firewall_rules:
  
  # 规则 1: 允许 GKE 访问 GCE VM 代理
  - name: allow-gke-to-proxy
    direction: INGRESS
    action: ALLOW
    sources:
      - 10.128.0.0/20    # GKE Pod CIDR
      - 10.128.16.0/20   # GKE Node CIDR
    targets:
      - proxy-server     # VM 标签
    ports:
      - tcp:3128
    
  # 规则 2: 允许 VM 访问外网
  - name: allow-proxy-egress
    direction: EGRESS
    action: ALLOW
    sources:
      - proxy-server     # VM 标签
    destinations:
      - 0.0.0.0/0       # 所有外网
    ports:
      - tcp:80
      - tcp:443
      
  # 规则 3: 拒绝 Pod 直接访问外网 (可选)
  - name: deny-pod-direct-egress
    direction: EGRESS
    action: DENY
    sources:
      - 10.128.0.0/20   # GKE Pod CIDR
    destinations:
      - 0.0.0.0/0       # 所有外网
    exceptions:
      - 10.128.2.100/32 # 允许访问代理 VM
```

## 3. 数据流分析

### 3.1 HTTP 请求流程

```
时序图:
API Pod          GKE Squid       GCE Squid       Microsoft
   │                 │               │               │
   │ 1. HTTP CONNECT │               │               │
   │ ──────────────→ │               │               │
   │                 │ 2. Forward    │               │
   │                 │ ──────────────→ │               │
   │                 │               │ 3. CONNECT    │
   │                 │               │ ──────────────→ │
   │                 │               │ 4. 200 OK     │
   │                 │               │ ←────────────── │
   │                 │ 5. 200 OK     │               │
   │                 │ ←────────────── │               │
   │ 6. 200 OK       │               │               │
   │ ←────────────── │               │               │
   │                 │               │               │
   │ 7. HTTPS Data   │               │               │
   │ ──────────────→ │ ──────────────→ │ ──────────────→ │
   │                 │               │               │
```

### 3.2 HTTPS 处理机制

```
HTTPS 流量处理:

┌─────────────────────────────────────────────────────────────────┐
│                    HTTPS CONNECT Method                         │
│                                                                 │
│  1. Client → Proxy: CONNECT login.microsoft.com:443 HTTP/1.1   │
│                                                                 │
│  2. Proxy → Server: CONNECT login.microsoft.com:443 HTTP/1.1   │
│                                                                 │
│  3. Server → Proxy: HTTP/1.1 200 Connection established        │
│                                                                 │
│  4. Proxy → Client: HTTP/1.1 200 Connection established        │
│                                                                 │
│  5. 建立 TCP 隧道，代理透明转发加密数据                            │
│     Client ←→ Proxy ←→ Server (encrypted data)                 │
│                                                                 │
│  注意: 代理无法解密 HTTPS 内容，只能看到:                          │
│  - 源 IP 和目标 IP                                              │
│  - 连接时间和数据量                                              │
│  - 无法看到具体的 URL 路径和请求内容                              │
└─────────────────────────────────────────────────────────────────┘
```

## 4. 监控和可观测性

### 4.1 监控指标流程图

```
┌─────────────────────────────────────────────────────────────────┐
│                      Monitoring Flow                            │
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │   GKE Squid     │    │   GCE Squid     │    │   External      │ │
│  │   Metrics       │    │   Metrics       │    │   Monitoring    │ │
│  │                 │    │                 │    │                 │ │
│  │ • Connections   │    │ • Connections   │    │ • Prometheus    │ │
│  │ • Requests/sec  │    │ • Requests/sec  │    │ • Grafana       │ │
│  │ • Cache hits    │    │ • Cache hits    │    │ • AlertManager  │ │
│  │ • Error rate    │    │ • Error rate    │    │                 │ │
│  │                 │    │                 │    │                 │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│           │                       │                       │        │
│           └───────────────────────┼───────────────────────┘        │
│                                   │                                │
│  ┌─────────────────────────────────┼─────────────────────────────────┐ │
│  │                    Log Aggregation                              │ │
│  │                                                                 │ │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │ │
│  │  │ GKE Squid Logs  │    │ GCE Squid Logs  │    │   SIEM/ELK      │ │ │
│  │  │                 │    │                 │    │                 │ │ │
│  │  │ • Access logs   │    │ • Access logs   │    │ • Log analysis  │ │ │
│  │  │ • Error logs    │    │ • Error logs    │    │ • Security      │ │ │
│  │  │ • Debug logs    │    │ • Audit logs    │    │   alerts        │ │ │
│  │  │                 │    │                 │    │ • Compliance    │ │ │
│  │  └─────────────────┘    └─────────────────┘    └─────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

这个详细的网络流量图和架构分析应该能帮助你更好地理解整个代理方案的工作原理和实施细节。每一层都有明确的职责和配置要求，确保了方案的可行性和安全性。