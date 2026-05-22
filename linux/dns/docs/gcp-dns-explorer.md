# GCP DNS Explorer — GKE DNS 深度探索与故障排查

> **目标：** 从 GKE Pod 的视角出发，逐层深入理解 DNS 解析的完整路径，解释 DNS Peering 的工作机制，排查 `aibang.cluster.local` 异常查询和 DNS 超时问题，并提供 Java 应用频繁 DNS 请求的完整优化方案。
>
> **你的环境概要：**
> - VPC1 (Shared VPC)：连接公司内部网络，配置了 Forwarding Zone，将 `aibang.` 等域名转发到公司内部 DNS 服务器
> - VPC2 (Private VPC)：运行 GKE 环境，Pod 使用 VPC DNS 解析器 `169.254.254.254`
> - GKE 使用 Cloud DNS (169.254.254.254)，未使用 kube-dns/CoreDNS 作为主要解析器

---

## 1. GKE DNS 架构深度解析

### 1.1 现代 GKE DNS 整体架构（GKE 1.36+）

从 GKE 1.36 开始，GKE 全面使用 CoreDNS 作为 `kube-dns` 的底层实现，并默认启用 NodeLocal DNSCache。完整架构如下：

```
                        ┌───────────────────────────────┐
                        │          Pod (Java App)        │
                        │  /etc/resolv.conf:             │
                        │    nameserver 169.254.20.10    │
                        │    (NodeLocal DNSCache IP)      │
                        │    search ns.svc.cluster.local  │
                        │           svc.cluster.local     │
                        │           cluster.local         │
                        │    options ndots:5              │
                        └──────────────┬────────────────┘
                                       │ DNS Query
                                       ▼
                        ┌───────────────────────────────┐
                        │   NodeLocal DNSCache (DaemonSet)│
                        │   每个节点运行一个 Pod           │
                        │   端口: 53 (UDP/TCP)            │
                        │   监听 IP: 169.254.20.10        │
                        │   缓存: 成功≤30s, 失败 5s       │
                        │                                 │
                        │   cluster.local 查询 → kube-dns │
                        │   其他所有查询   → 元数据服务器 │
                        └──────┬────────────────┬───────┘
                               │                │
                    cluster.local          外部域名
                               │                │
                               ▼                ▼
              ┌──────────────────┐   ┌──────────────────┐
              │  kube-dns (CoreDNS)│   │ 元数据服务器       │
              │  kube-system ns    │   │ 169.254.169.254   │
              │  ClusterIP: 10.x   │   └────────┬─────────┘
              │                    │            │
              │  无法解析 → 转发   │            ▼
              └─────────┬──────────┘   ┌──────────────────┐
                        │              │  Cloud DNS /      │
                        │              │  VPC DNS          │
                        │              │  169.254.254.254  │
                        │              └────────┬─────────┘
                        │                       │
                        └───────────┬───────────┘
                                    ▼
                        ┌───────────────────────────────┐
                        │   VPC DNS Decision Engine      │
                        │   1. Response Policy           │
                        │   2. DNS Peering               │
                        │   3. Forwarding Zone           │
                        │   4. 公网递归                  │
                        └───────────────────────────────┘
```

### 1.2 NodeLocal DNSCache 详解

NodeLocal DNSCache 是 GKE 中最重要的 DNS 性能优化组件，GKE 1.34.1+ Standard 集群默认启用。

**核心价值：**
- latency：平均 DNS 查找延迟降低 50-80%
- conntrack：Pod 到本地缓存不经过 conntrack 表，消除 conntrack 竞态条件
- offload：外部域名查询绕过 kube-dns，直接到元数据服务器，减少 kube-dns 80-90% 负载
- cache：成功记录缓存上限 30 秒，NXDOMAIN 缓存 5 秒

**数据流详解：**
```
Pod 发起 DNS 查询
  │
  ├─ 目标域名属于 cluster.local？
  │   YES → NodeLocal DNSCache → kube-dns-upstream Service → CoreDNS Pod
  │
  ├─ 目标域名匹配 stubDomains？
  │   YES → NodeLocal DNSCache 直接转发到自定义 DNS 服务器
  │
  └─ 其他所有域名
      → NodeLocal DNSCache → 节点本地元数据服务器 (169.254.169.254) → Cloud DNS
```

### 1.3 CoreDNS 插件管道与配置

GKE 1.36+ CoreDNS 的请求处理是按插件链顺序执行的：

```
DNS Query → errors → health → ready → kubernetes → prometheus → forward → cache → loop → reload → loadbalance → Response
```

**Corefile 完整解析：**
```
.:53 {
    errors           # 错误日志
    health { lameduck 5s }  # 健康检查，优雅关闭 5s
    ready            # 就绪检查
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30       # K8s Service 记录 TTL = 30s
    }
    prometheus :9153 # 指标暴露端口
    forward . /etc/resolv.conf {
        max_concurrent 1000  # 最大并发上游查询
    }
    cache 30 {
        success 9984 30     # 成功缓存 9984 条，TTL 30s
        denial 5000 5       # 否定缓存 5000 条，TTL 5s
    }
    loop             # 循环检测
    reload           # 热重载配置
    loadbalance      # 轮询上游
}
```

### 1.4 四层 DNS 缓存架构总结

在 GKE 中，一次 DNS 查询可能经过四层缓存：

| 层级 | 位置 | 范围 | 默认 TTL | 可配置 |
|------|------|------|----------|--------|
| L1: JVM DNS Cache | Pod 内 JVM 进程 | 单个应用 | **永久 (-1)** | `networkaddress.cache.ttl` |
| L2: OS DNS Cache (nscd/systemd) | Pod 内 OS | 单个 Pod | 取决于 OS | 通常不改 |
| L3: NodeLocal DNSCache | 节点 | 同节点所有 Pod | 30s (上限) | 否 |
| L4: CoreDNS Cache | 集群 | 整个集群 | 30s | Corefile |

**对 Java 应用的影响：** L1（JVM）默认永久缓存会完全屏蔽 L2-L4 的缓存，导致 DNS 变更无法感知。这是 Java 应用在 K8s 中最常见的 DNS 问题根源。

---

## 2. Java 应用频繁 DNS 请求 — 完整优化方案

### 2.1 问题场景建模

假设你的 Java 应用在 GKE Pod 中运行，业务特征如下：
- 每秒处理 1000 个 HTTP 请求
- 每个请求需要调用 3 个外部微服务（通过域名）
- 域名示例：`service-a.internal.aibang.`, `service-b.internal.aibang.`, `db-proxy.internal.aibang.`

**原始 JVM 配置（默认永久缓存）：**
```
DNS QPS = 3 次（整个 JVM 生命周期只查一次）
```
问题：DNS 变更（IP 漂移/故障切换）后，应用仍然连接旧 IP，直到重启 JVM。

**优化后（TTL=10s）：**
```
DNS QPS = (1000 × 3) / 10 = 300 QPS
```
挑战：300 QPS 如果直接打到 CoreDNS，在大规模集群中会造成压力。

### 2.2 JVM DNS 缓存机制深究

Java DNS 缓存由 `InetAddress` 类控制，有两套属性体系：

| 属性 | 类型 | 优先级 | 配置方式 |
|------|------|--------|----------|
| `networkaddress.cache.ttl` | Security Property | **高** | `$JAVA_HOME/conf/security/java.security` 或代码 `Security.setProperty()` |
| `networkaddress.cache.negative.ttl` | Security Property | **高** | 同上 |
| `sun.net.inetaddr.ttl` | System Property | 低（fallback） | `-D` 启动参数 |
| `sun.net.inetaddr.negative.ttl` | System Property | 低（fallback） | `-D` 启动参数 |

**关键规则：** Security Property 优先于 System Property。`-D` 参数只是 fallback！

### 2.3 优化方案选择指南

```
你的场景需求
  │
  ├─ DNS 变更频繁（IP 漂移 < 30s）？
  │   ├─ 是 → TTL 设为 5-10s
  │   └─ 否 → TTL 设为 30-60s
  │
  ├─ DNS QPS 预估？
  │   ├─ < 1000 → JVM 参数 + NodeLocal DNSCache（默认已启用）即可
  │   ├─ 1000-5000 → 额外优化 CoreDNS Cache 配置
  │   └─ > 5000 → 应用层连接池 + 域名预热 + 多级缓存
  │
  └─ 能否改代码？
      ├─ 能 → 使用 FQDN（尾部加点）、连接池复用、DNS 预热
      └─ 不能 → 侧重基础设施层优化
```

### 2.4 方案 A：JVM 参数优化（必选，最小改动）

**生产环境推荐配置：**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: java-microservice
spec:
  template:
    spec:
      containers:
      - name: app
        image: your-java-app:latest
        env:
        - name: JAVA_TOOL_OPTIONS
          value: >-
            -Dnetworkaddress.cache.ttl=10
            -Dnetworkaddress.cache.negative.ttl=5
            -Dsun.net.inetaddr.ttl=10
            -Dsun.net.inetaddr.negative.ttl=5
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
```

**或通过 `java.security` 文件（推荐，优先级更高）：**

```dockerfile
# Dockerfile
FROM openjdk:17-slim
RUN echo "networkaddress.cache.ttl=10" >> $JAVA_HOME/conf/security/java.security && \
    echo "networkaddress.cache.negative.ttl=5" >> $JAVA_HOME/conf/security/java.security
COPY target/app.jar /app.jar
ENTRYPOINT ["java", "-jar", "/app.jar"]
```

### 2.5 方案 B：NodeLocal DNSCache（推荐，零代码改动）

**验证是否已启用：**
```bash
kubectl get pods -n kube-system -l k8s-app=node-local-dns -o wide
# 每个节点应该有一个 Running 的 node-local-dns Pod
```

**检查 Pod 是否使用 NodeLocal DNSCache：**
```bash
kubectl exec -it <pod> -- cat /etc/resolv.conf
# nameserver 应该是 169.254.20.10（NodeLocal DNSCache IP）
# 而不是 kube-dns 的 ClusterIP
```

**启用（如未启用）：**
```bash
gcloud container clusters update CLUSTER_NAME \
    --location=COMPUTE_LOCATION \
    --update-addons=NodeLocalDNS=ENABLED
```

### 2.6 方案 C：CoreDNS 缓存优化（大规模集群推荐）

```bash
kubectl edit configmap kube-dns -n kube-system
```

优化后的 Corefile：
```
.:53 {
    errors
    health { lameduck 5s }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
        max_concurrent 1000
        policy sequential
        health_check 0.5s
    }
    cache {
        success 20000 60       # 扩容到 20000 条，TTL 60s
        denial 10000 30        # 否定缓存扩容
        prefetch 10 30% 5s     # 预取：剩余 30% TTL 时触发
        serve_stale 10s        # 过期后继续服务 10s
    }
    loop
    reload
    loadbalance round_robin
}
```

**参数详解：**
- `success CAPACITY TTL`：成功响应缓存容量和 TTL
- `prefetch AMOUNT DURATION PERCENTAGE`：预取机制，在缓存过期前主动刷新
- `serve_stale DURATION`：缓存过期后仍继续返回旧值，同时异步更新（防止缓存击穿）

### 2.7 方案 D：应用层代码优化（根本性解决）

**1. 始终使用 FQDN（尾部加点）：**
```java
// 错误（触发 ndots search 路径追加）
String host = "service-a.internal.aibang";

// 正确（绝对 FQDN，不触发 search）
String host = "service-a.internal.aibang.";
```

**2. HTTP 客户端连接池复用：**
```java
// OkHttp 示例
OkHttpClient client = new OkHttpClient.Builder()
    .connectionPool(new ConnectionPool(50, 5, TimeUnit.MINUTES))
    .dns(new Dns() {
        @Override
        public List<InetAddress> lookup(String hostname) {
            // 自定义 DNS 解析 + 应用层缓存
            return CachingDnsResolver.resolve(hostname);
        }
    })
    .build();
```

**3. DNS 预热（启动时预解析）：**
```java
@Component
public class DnsWarmup implements ApplicationRunner {
    private static final List<String> HOSTS = List.of(
        "service-a.internal.aibang.",
        "service-b.internal.aibang.",
        "db-proxy.internal.aibang."
    );

    @Override
    public void run(ApplicationArguments args) {
        HOSTS.parallelStream().forEach(host -> {
            try {
                InetAddress.getAllByName(host);
                log.info("DNS warmed up: {}", host);
            } catch (UnknownHostException e) {
                log.warn("DNS warmup failed: {}", host, e);
            }
        });
    }
}
```

**4. Micrometer 指标监控 DNS 解析：**
```java
@Configuration
public class DnsMetricsConfig {
    @Bean
    public DnsMetrics dnsMetrics(MeterRegistry registry) {
        return new DnsMetrics(registry);
    }
}

class DnsMetrics {
    private final Timer dnsTimer;
    private final Counter dnsErrors;

    DnsMetrics(MeterRegistry registry) {
        this.dnsTimer = Timer.builder("dns.resolution")
            .description("DNS resolution time")
            .register(registry);
        this.dnsErrors = Counter.builder("dns.errors")
            .description("DNS resolution failures")
            .register(registry);
    }
}
```

### 2.8 方案效果对比矩阵

```
                              默认     方案A     方案A+B   方案A+B+C  全部
                              (永久)   (JVM)    (+Node)   (+CoreDNS) (+代码)
─────────────────────────────────────────────────────────────────────────
DNS 变更感知延迟              永久      10s       10s       10s       实时
平均 DNS 解析延迟 (P50)       <1ms     10ms      2ms       1ms       <1ms
CoreDNS 负载 (相对)           0%        100%      15%       10%       8%
conntrack 表压力              0%        中        无        无        无
缓存击穿风险                  无        有        低        极低      无
实施难度                      无        低        低        中        高

注：负载百分比以方案A的 CoreDNS QPS 为基准 (100%)
```

---

## 3. 从 Pod 出发 — DNS 解析的真实起点

### 3.1 Pod 内的 /etc/resolv.conf

有 NodeLocal DNSCache 时：
```
nameserver 169.254.20.10       ← NodeLocal DNSCache 本地 IP
search <ns>.svc.cluster.local svc.cluster.local cluster.local \
       c.<project-id>.internal google.internal
options ndots:5
```

无 NodeLocal DNSCache 时：
```
nameserver 10.x.x.x            ← kube-dns ClusterIP
search <ns>.svc.cluster.local svc.cluster.local cluster.local \
       c.<project-id>.internal google.internal
options ndots:5
```

### 3.2 ndots 搜索路径完整行为

```
若 FQDN 中 dots（.）数量 < ndots → 依次追加所有 search 域再查询
若 FQDN 中 dots（.）数量 >= ndots → 直接查原始 FQDN
```

| ndots | api.aliyun.cloud.region.aibang (5 dots) 行为 |
|-------|----------------------------------------------|
| 5 | 直接查询原始 FQDN (5 >= 5) |
| 4 | 先追加 4 次 search 路径再查原始 FQDN |
| 6 | 直接查询原始 FQDN (5 < 6? 不对，5 < 6，会追加 search! → 实际上如果 ndots=6，5 < 6，则会追加 search) |

**注意：** ndots 值变大对短域名不利，会减少 search 追加；ndots 值变小会增加 search 追加。

### 3.3 aibang 域名 ndots 行为表

对于 `api.aliyun.cloud.region.aibang`（5 个 dots）：

| ndots 配置 | dots 数 vs ndots | 行为 |
|-----------|-----------------|------|
| ndots:3 | 5 >= 3 | 直接查询 FQDN，不追加 search |
| ndots:4 | 5 >= 4 | 直接查询 FQDN，不追加 search |
| ndots:5 | 5 >= 5 | 直接查询 FQDN，不追加 search |
| ndots:6 | 5 < 6 | **先追加 search 路径**，会导致 `.cluster.local` 查询 |

如果你看到 `aibang.cluster.local` 查询，最可能的原因就是 **ndots 配置为 6 或更高**，导致 search 路径被追加。

---

## 4. 完整 DNS 解析流程 — aibang 域名示例

```
Pod (Java App) 查询 api.aliyun.cloud.region.aibang
    │
    │ ndots=5, 5 dots >= 5 → 直接查询 FQDN
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: NodeLocal DNSCache (169.254.20.10)                      │
│                                                                 │
│ 检查缓存？→ 未命中                                              │
│ 属于 cluster.local？→ 否                                        │
│ 匹配 stubDomains？→ 否                                          │
│ → 转发到节点本地元数据服务器 (169.254.169.254)                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: 元数据服务器 → Cloud DNS / VPC DNS (169.254.254.254)   │
│                                                                 │
│ 检查匹配顺序：                                                  │
│   1. Response Policy？        → 无                              │
│   2. DNS Peering Zone？      → 有！匹配 aibang. → VPC1         │
│   3. Forwarding Zone？        → 在 VPC1 上检查                  │
│   4. 默认递归？               → 不执行                          │
└────────────────────────────┬────────────────────────────────────┘
                             │ VPC Network Peering
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: VPC1 Cloud DNS (Shared VPC)                             │
│                                                                 │
│ 检查：                                                          │
│   1. Response Policy？→ 无                                      │
│   2. DNS Peering？   → 无（这里是 Peering 的接收端）           │
│   3. Forwarding Zone？→ 有！aibang. → 公司内部 DNS              │
│   4. 默认递归？      → 不执行                                   │
└────────────────────────────┬────────────────────────────────────┘
                             │ Forwarding
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 4: 公司内部 DNS 服务器                                      │
│                                                                 │
│ 解析 api.aliyun.cloud.region.aibang                                │
│ → 返回 IP: 10.x.x.x                                             │
└────────────────────────────┬────────────────────────────────────┘
                             │
         结果沿原路径返回：
         VPC1 Cloud DNS → VPC2 Cloud DNS → NodeLocal DNSCache
                             │
         缓存 30s（NodeLocal DNSCache）
         返回 IP 给 Pod
```

---

## 5. DNS 超时问题 — 诊断与扩容

### 5.1 超时定位决策树

```
Pod 内 nslookup 超时
    │
    ├─ dig @169.254.20.10 (NodeLocal DNSCache) 超时？
    │   ├─ 否 → 问题在 Pod → NodeLocal 网络
    │   └─ 是 ↓
    │
    ├─ dig @10.x.x.x (CoreDNS ClusterIP) 超时？
    │   ├─ 否 → 问题在 NodeLocal DNSCache
    │   └─ 是 ↓
    │
    ├─ kubectl top pods -n kube-system -l k8s-app=kube-dns
    │   ├─ CPU > 80% → 扩容 CoreDNS
    │   └─ 正常 ↓
    │
    └─ dig @169.254.254.254 (VPC DNS) 超时？
        ├─ 是 → 检查 Forwarding Target、VPC Firewall
        └─ 否 → 检查 CoreDNS 到 VPC DNS 的网络路径
```

### 5.2 CoreDNS 扩容策略

```bash
# 查看当前 autoscaler 配置
kubectl get configmap kube-dns-autoscaler -n kube-system -o yaml

# 调整扩容策略
kubectl edit configmap kube-dns-autoscaler -n kube-system
```

```
# 激进扩容（每 4 节点一个 CoreDNS，最多 20）
linear: '{"coresPerReplica":128, "nodesPerReplica":4, "min": 3, "max": 20, "preventSinglePointFailure":true}'

# 标准扩容（每 8 节点一个 CoreDNS，最多 15）
linear: '{"coresPerReplica":256, "nodesPerReplica":8, "min": 2, "max": 15, "preventSinglePointFailure":true}'
```

### 5.3 常见 DNS 超时根因速查

| 现象 | 根因 | 修复 |
|------|------|------|
| `getaddrinfo EAI_AGAIN` | CoreDNS 过载 | 扩容 CoreDNS + 启用 NodeLocal |
| conntrack 表满 | 大量短连接 DNS | 启用 NodeLocal DNSCache |
| Spot VM 上的 CoreDNS 被回收 | 调度策略问题 | 添加标准节点池 + 污点容忍 |
| 偶发 5s 超时 | Linux conntrack race | 启用 NodeLocal DNSCache |
| Forwarding Target 不可达 | 内部 DNS 故障 | 检查 Forwarding Zone 目标健康 |

---

## 6. DNS Peering vs Forwarding Zone

### 6.1 Cloud DNS 决策优先级

```
同一 VPC 内，Cloud DNS 的处理顺序：

Response Policy（最高优先级，覆盖一切）
    ↓
DNS Peering（拉取模式：VPC2 主动 Peering 到 VPC1）
    ↓
Forwarding Zone（转发模式：将特定域名转发到指定 DNS 服务器）
    ↓
Private Zone（VPC 内部私有 DNS 记录）
    ↓
默认递归（公网查询）
```

### 6.2 你的 aibang 场景配置验证

```bash
# 检查 VPC2 的 DNS Peering
gcloud dns managed-zones list --filter="visibility:private AND peeringConfig.targetNetwork:*"

# 检查 VPC1 的 Forwarding Zone
gcloud dns managed-zones list --filter="visibility:private AND forwardingConfig.targetNameServers:*"

# 直接测试 VPC DNS
dig @169.254.254.254 api.aliyun.cloud.region.aibang. +short
```

---

## 7. 排查命令速查表

### 7.1 Java 应用层排查

```bash
# 进入 Pod
kubectl exec -it <pod> -- /bin/bash

# 检查 JVM DNS 缓存配置
java -XshowSettings:all -version 2>&1 | grep -i dns

# 检查 resolv.conf
cat /etc/resolv.conf

# DNS 查询测试
nslookup api.aliyun.cloud.region.aibang.
dig api.aliyun.cloud.region.aibang. +short

# 查询耗时
time nslookup api.aliyun.cloud.region.aibang.

# 抓包
tcpdump -i any -n port 53 -c 50
```

### 7.2 CoreDNS 层排查

```bash
# CoreDNS Pod 状态
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# CoreDNS 日志
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=200

# CoreDNS 指标
kubectl port-forward -n kube-system svc/kube-dns 9153:9153 &
curl http://localhost:9153/metrics | grep -E "(cache_hits|cache_misses|requests_total|request_duration)"

# 检查 ConfigMap
kubectl get configmap kube-dns -n kube-system -o yaml
```

### 7.3 NodeLocal DNSCache 排查

```bash
# NodeLocal Pod 状态
kubectl get pods -n kube-system -l k8s-app=node-local-dns -o wide

# NodeLocal 日志
kubectl logs -n kube-system -l k8s-app=node-local-dns --tail=100

# 直接测试 NodeLocal
kubectl exec -it <pod> -- dig @169.254.20.10 api.aliyun.cloud.region.aibang.
```

### 7.4 VPC DNS 层排查

```bash
# 直接查询 VPC DNS
dig @169.254.254.254 api.aliyun.cloud.region.aibang. +trace

# Cloud DNS 查询日志
gcloud logging read \
  'resource.type="dns_query" AND query_name:"aibang"' \
  --limit=20 --order=desc

# 检查 DNS Peering 配置
gcloud dns managed-zones list --filter="peeringConfig:*"
```

---

## 8. 关键结论

1. **aibang.cluster.local 异常查询根因：** ndots 配置值偏高（>=6）导致 search 路径被追加。ndots=5 时，5 个 dots 的域名刚好满足直接查询条件。

2. **Java 应用频繁 DNS 优化最佳实践（按优先级）：**
   - 第一优先：`networkaddress.cache.ttl=10`，避免 JVM 永久缓存
   - 第二优先：确认 NodeLocal DNSCache 已启用（GKE 1.34.1+ 默认）
   - 第三优先：应用代码使用 FQDN（尾部加点），消除 ndots search 开销
   - 第四优先：CoreDNS cache 扩容 + prefetch，提升集群级缓存命中率

3. **DNS 超时扩容决策：**
   - 先确认超时发生在哪一层（Pod → NodeLocal → CoreDNS → VPC DNS → 内部 DNS）
   - CoreDNS 过载：扩容副本 + 启用 NodeLocal DNSCache
   - VPC DNS 层慢：检查 Forwarding Target + 启用 NodeLocal DNSCache

4. **效果量化预估：**
   - JVM TTL=10s：DNS 变更感知 10s，300 QPS 打到 CoreDNS
   - +NodeLocal DNSCache：300 QPS → ~45 QPS（85% 卸载）
   - +CoreDNS cache prefetch：消除缓存击穿风险，P99 < 5ms

---

*Document version: 2.0.0 — 2026-05-22*
