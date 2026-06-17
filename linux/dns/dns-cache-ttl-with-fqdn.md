# GKE Java Pod 外部域名 DNS 解析出错 — Cache + FQDN 最佳实践

> **场景聚焦**:Java Pod 请求**集群外的真实外部域名**(如 `api.partner.com.`、`s3.amazonaws.com.`、`payments.stripe.com.`),不是 `*.svc.cluster.local`。
> **目标**:从应用代码、JVM 调参、CoreDNS 转发链、客户端重试四个层面,系统性降低"外部域名 DNS 解析出错/超时"的概率和影响面。

---

## 0. 写在前面 — 重新框定问题

> 你的真实诉求:**"Java Pod 请求外部域名,怎么降低 DNS 查询出错的概率?"**

**先把"出错"拆清楚**(只保留与**外部域名**相关的根因):

| 编号 | 根因 | 现象 |
|------|------|------|
| **E1** | ndots 触发 search path 拼接,先 4 次 NXDOMAIN 才查对的名字 | 首次解析 100ms+ 尖刺、CoreDNS 日志同一名字被打 4 次 |
| **E2** | 外部域名解析走 `forward . 10.60.0.2` → Cloud DNS,**多一跳** | 跨节点查询延迟 5-20ms、Cloud DNS 配额 / rate limit 风险 |
| **E3** | Java `networkaddress.cache.negative.ttl=10s` 吞掉 NXDOMAIN | 外部域名恢复后,Java 端**最长 10s 持续失败** |
| **E4** | Java `networkaddress.cache.ttl=30s` 与外部域名短 TTL(60s)不匹配 | 缓存陈旧指向已切换的 IP 池、CDN 调度失效 |
| **E5** | Java `InetAddress.getAllByName0` 默认重试 + 串行 | 单次失败就 5s+、超时雪崩 |
| **E6** | HTTP client 连接池**预热失败**导致首请求雪崩 | 服务冷启动 / Region failover 时第一次请求 100% 失败 |
| **E7** | CoreDNS forward plugin 没有健康检查,上游 Cloud DNS 故障时**全集群失败** | 一过 35.199.192.0/19 网段故障,所有外部域名解析挂 |

> **核心结论**:**FQDN 解决 E1**,**Cache TTL 调参解决 E3 + E4**,**客户端重试/超时解决 E5 + E6**,**forward 调优 + 上游选型解决 E2 + E7**。**单点都不够**。

---

## 1. 外部域名查询在 GKE 上的完整路径

```
Java 应用
  → InetAddress.getAllByName0("api.partner.com.")         ← JVM cache (L1)
  → glibc resolver (nss_resolve)                          ← 无 nscd (L2)
  → /etc/resolv.conf 第一跳: 169.254.20.10                ← NodeLocal DNSCache (L3)
  → /etc/resolv.conf 备选:  kube-dns Service ClusterIP    ← CoreDNS (L4)
  → CoreDNS `forward . 10.60.0.2`                          ← Cloud DNS 内部网关
  → Cloud DNS (35.199.192.0/19 源)
  → 上游 authoritative DNS (e.g. Route53 / Cloudflare)
```

**关键观察**:
- 外部域名查询**至少 4 跳**(JVM miss 时),每多一跳 = 多一份失败风险
- 任何一层**没缓存**或**缓存错** = 整条链炸
- CoreDNS `forward .` 是**单点依赖**,没有 health check

---

## 2. 应用代码层 — 强制尾部点 FQDN(E1 的根治)

### 2.1 反例(踩过)

```java
// 错 1:把外部域名当短名传,ndots 触发 4 次 search path NXDOMAIN
URI uri = new URI("http://api.partner.com/orders");
HttpRequest req = HttpRequest.newBuilder(uri).build();

// 错 2:从配置中心读到名字直接拼 URL,没意识到 resolver 看不到尾部点
String host = config.get("partner.host");  // "api.partner.com"
String url = "http://" + host + "/orders";
```

**为什么错**(参考 `dns-resolution-ndots.md` §2 §3):
- 名字普通分隔点 = 2 个,< ndots:5
- resolver 会先做 4 次 search path 拼接(`.namespace.svc.cluster.local` / `.svc.cluster.local` / `.cluster.local` / `.internal`),**全部 NXDOMAIN**
- 第 5 次才查原始名 → 走 CoreDNS forward → Cloud DNS
- 单次解析多 4 次 NXDOMAIN,在 CoreDNS 日志里看**同一名字被打 5 次**

### 2.2 正例 — 集中管理 + 强制尾部点

```yaml
# application.yml
external-services:
  partner-api:
    base-url: "http://api.partner.com."    # ← 强制尾部点
  s3-bucket:
    base-url: "https://s3.amazonaws.com."
  payments:
    base-url: "https://api.stripe.com."
```

**Lint 规则(关键防线)**:禁止非 Service 名 + 不带尾部点的外部 URL:
```java
// ArchUnit 示例
@ArchTest
static final ArchRule external_domains_must_be_fqdn =
    methods().that().areDeclaredInClassesThat().resideInAPackage("..external..")
        .and().haveNameMatching(".*[Uu]rl.*")
        .should(callMethod(URL.class, "of", String.class))
        .orShould(callMethod(URI.class, "create", String.class));
```
外加 Checkstyle regex:`^https?://(?![\w-]+\.svc\.cluster\.local\.)[^/]+$` 匹配外部 URL,**构建期 fail**。

### 2.3 Java 客户端对尾部点的处理(必须验证)

| 客户端 | 尾部点处理 | 备注 |
|--------|-----------|------|
| `java.net.URI` | **保留** | 传给底层 client,不会自动剥 |
| `java.net.URL` | **保留** | 同上 |
| `InetAddress.getByName("host.")` | **支持** | 解析为绝对名字,不走 search |
| Apache HttpClient 5 | **保留** Host header 尾部点 | ⚠️ 服务端 NGINX 可能 400 |
| OkHttp 4.x | **保留** Host header 尾部点 | ⚠️ 同上 |
| Spring RestTemplate | **保留** | 同上 |
| Java HttpClient (JDK 11+) | **保留** | 同上 |

**核心坑**:**Host header 不要带尾部点**(违反 HTTP/1.1 RFC 7230 §5.4,NGINX/HAProxy 报 400/421)。尾部点**只用在解析层**:
```java
// 推荐:用 URI 解析 + 自定义 Host header
URI uri = URI.create("http://api.partner.com./orders");  // 解析用
HttpRequest req = HttpRequest.newBuilder(uri)
    .header("Host", "api.partner.com")                    // 发送剥掉
    .build();
```
或 Apache HttpClient:
```java
HttpGet get = new HttpGet("http://api.partner.com./orders");
get.setHeader("Host", "api.partner.com");  // 显式覆盖
```

---

## 3. JVM DNS Cache 调参(解决 E3 + E4,关键)

> 容器编排里 **JVM 的 InetAddress cache 默认值(30s/10s)与外部域名短 TTL 严重不匹配**。

### 3.1 关键参数

| 参数 | 默认 | 推荐 | 解决 |
|------|------|------|------|
| `networkaddress.cache.ttl` | 30s | **10s** | E4 — 与外部域名常见 TTL 60s+ 配比适中,滚动时不会陈旧太久 |
| `networkaddress.cache.negative.ttl` | **10s** | **5s** | E3 — 外部域名 NXDOMAIN 恢复后 5s 内重试 |
| `sun.net.inetaddr.ttl` | 30s | **10s** | 部分老框架读这个参数,同步改 |

> ⚠️ **注意区分场景**:
> - **K8s Service 内部调用**:`ttl` 短一些更好(滚动发布快感知)
> - **外部域名**:`ttl` 短一些 = CoreDNS 压力↑,**平衡点 10s**
> - **有 CDN 调度的外部域名**(如 S3 / CloudFront):`ttl` 5s 也能接受,因 CDN 边缘有缓存

### 3.2 注入方式(三种)

**方式 A:JVM args(推荐,零侵入)**
```yaml
# Deployment spec
spec:
  containers:
  - name: app
    env:
    - name: JAVA_TOOL_OPTIONS
      value: >-
        -Dnetworkaddress.cache.ttl=10
        -Dnetworkaddress.cache.negative.ttl=5
        -Dsun.net.inetaddr.ttl=10
```

**方式 B:PodPreset / Kustomize 统一注入(集群级)**
```yaml
# kustomization.yaml
patches:
- target:
    group: apps
    version: v1
    kind: Deployment
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/env/-
      value:
        name: JAVA_TOOL_OPTIONS
        value: "-Dnetworkaddress.cache.ttl=10 -Dnetworkaddress.cache.negative.ttl=5"
```

**方式 C:`$JAVA_HOME/jre/lib/security/java.security`(镜像层)**
```dockerfile
# Dockerfile
RUN echo "networkaddress.cache.ttl=10" >> $JAVA_HOME/conf/security/java.security && \
    echo "networkaddress.cache.negative.ttl=5" >> $JAVA_HOME/conf/security/java.security
```
**好处**:不改业务 deployment,**所有** JVM 进程都生效。

### 3.3 验证(必做)

```bash
# 1. 启动后看实际生效值
kubectl exec -it $POD -- jcmd 1 VM.system_properties | grep -E "networkaddress|inetaddr"

# 2. 代码里强制打点(Micrometer)
Counter.builder("dns.lookup")
    .tag("name", hostname)
    .tag("result", "hit|miss|negative")
    .register(meterRegistry)
    .increment();
```

---

## 4. CoreDNS 转发链调优(解决 E2 + E7)

### 4.1 默认 Corefile 的问题

```yaml
# GKE 默认
forward . 10.60.0.2
```
- **单上游**:Cloud DNS 网关故障 = 全部外部域名挂
- **无健康检查**:上游挂时不切换
- **无并行**:一个 upstream 串行查询,延迟叠加

### 4.2 推荐 Corefile

```yaml
# kubectl edit cm coredns -n kube-system
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        }

        # 关键:外部域名缓存调优
        cache 30 {
          success  1000      # 命中缓存 TTL 上限
          denial   30        # NXDOMAIN 缓存
          prefetch 10 1m     # 命中 >10 次提前 1m 续期
        }

        # 关键:多上游 + 健康检查
        forward . 10.60.0.2 10.0.0.2 {
          prefer_healthy
          max_fails 3
          expire 10s
          timeout 5s
          force_tcp
        }

        loop
        reload
        loadbalance
        serve_stale 1h
    }
```

### 4.3 上游选型策略

| 上游 | 适用 | 备选 |
|------|------|------|
| `10.60.0.2` | GKE Cloud DNS(默认,快,内网) | 第一选 |
| `10.0.0.2` | 自建 unbound/coredns(可定制转发) | 备选 |
| `8.8.8.8` / `1.1.1.1` | 公网 DNS 兜底 | **慎用** — 走公网 NAT,延迟高,可能出站受限 |
| VPC 内的其他 DNS | 跨 VPC 解析 | Hybrid DNS 场景 |

**`force_tcp`**:GKE 节点上 UDP 53 出站可能被防火墙/Security Policy 截断,**强制 TCP 减少 ERR**。

### 4.4 自定义 Stub 域名(企业内网)

如果外部域名其实在**企业内网 DNS**(非公网),需要 stub 域:
```yaml
# Corefile
.:53 {
    # ... 前面配置 ...
    
    # 企业内网域名走内网 DNS
    partner.internal:53 {
        forward partner.internal 10.100.0.53 {
          force_tcp
        }
        cache 30
    }
    
    # 其余走 GCP
    .:53 {
        forward . 10.60.0.2 {
          force_tcp
        }
    }
}
```
**坑**:`partner.internal` 这种带 `internal` 后缀的域名在 GKE 节点上**本身合法**,但要确保 Corefile server block 顺序对,**先匹配 stub 再匹配通配**。

---

## 5. NodeLocal DNSCache(解决 E2 的性能面)

### 5.1 作用

在每个 GKE 节点跑 DaemonSet,Pod 第一跳 DNS 变成 `169.254.20.10`:

- 节点级缓存,命中直接返回不查 CoreDNS
- UDP→TCP 转换,规避 512 字节 UDP 截断
- 跳过 kube-dns Service 的 iptables 跳转

### 5.2 开启

```bash
# Standard GKE
gcloud container clusters update $CLUSTER \
  --cluster-dns=clouddns \
  --cluster-dns-scope=cluster \
  --enable-dns-cache

# Autopilot 默认开启,验证即可
```

### 5.3 验证

```bash
kubectl exec -it $POD -- cat /etc/resolv.conf
# 期望: nameserver 169.254.20.10
```

### 5.4 对外部域名的影响

- **JVM 缓存 miss 时**,NodeLocal 命中 = 跳过 CoreDNS,**减少 1 跳**
- **NodeLocal miss 时**,CoreDNS forward 仍要走 `10.60.0.2` → Cloud DNS
- 所以 NodeLocal **优化延迟**,**不解决** Cloud DNS 上游故障(E7)

---

## 6. Java 客户端重试/超时(解决 E5 + E6)

> 即便前面三层全部正确,Java 第一次解析某外部域名时仍可能失败。**客户端重试是最后一道防线**。

### 6.1 InetAddress 层面

Java 解析外部域名的默认行为:
- `InetAddress.getAllByName0` 默认**不重试**,但会**串行尝试**所有 nameserver
- 每次查询默认 timeout 5s(可改 `sun.net.client.defaultConnectTimeout`)
- 失败时抛 `UnknownHostException`

**调参**:
```java
// JVM args
-Dsun.net.client.defaultConnectTimeout=3000   // TCP 连接超时
-Dsun.net.client.defaultReadTimeout=3000      // TCP 读超时
-Dsun.net.inetaddr.ttl=10                    // (已讨论)
```

### 6.2 HTTP client 重试(关键)

**OkHttp 4.x**:
```java
OkHttpClient client = new OkHttpClient.Builder()
    .connectTimeout(3, TimeUnit.SECONDS)
    .readTimeout(10, TimeUnit.SECONDS)
    .callTimeout(15, TimeUnit.SECONDS)         // 总超时
    .retryOnConnectionFailure(true)            // ← 默认开,但只对 Socket 错误
    .dns(new Dns() {
        @Override
        public List<InetAddress> lookup(String hostname) throws UnknownHostException {
            try {
                return InetAddress.getAllByName(hostname);
            } catch (UnknownHostException e) {
                // 外部域名首次失败,等 200ms 重试一次
                try { Thread.sleep(200); } catch (InterruptedException ie) {}
                return InetAddress.getAllByName(hostname);
            }
        }
    })
    .build();
```

**Apache HttpClient 5**:
```java
RequestConfig config = RequestConfig.custom()
    .setConnectTimeout(3, TimeUnit.SECONDS)
    .setResponseTimeout(10, TimeUnit.SECONDS)
    .build();

CloseableHttpClient client = HttpClients.custom()
    .setDefaultRequestConfig(config)
    .setRetryStrategy(new DefaultHttpRequestRetryStrategy(2, 500))  // 重试 2 次,间隔 500ms
    .build();
```

**Spring RestTemplate / WebClient**:
```yaml
# application.yml
spring:
  http:
    client:
      connect-timeout: 3s
      read-timeout: 10s
  webflux:
    client:
      connect-timeout: 3s
      read-timeout: 10s

# Resilience4j 重试
resilience4j:
  retry:
    instances:
      externalApi:
        max-attempts: 3
        wait-duration: 500ms
        retry-exceptions:
          - java.net.UnknownHostException
          - java.net.SocketTimeoutException
          - org.apache.http.NoHttpResponseException
```

### 6.3 连接池预热(E6 解决)

服务冷启动时,所有连接池都是空的。Region failover / 上游 DNS 切换时,**第一次请求 100% 失败**。

**预热方式**:
```java
@Component
public class ExternalClientWarmer {
    @Autowired RestTemplate restTemplate;
    
    @EventListener(ApplicationReadyEvent.class)
    public void warmUp() {
        // 启动后预热外部域名解析
        for (String host : externalHosts) {
            executor.submit(() -> {
                try {
                    InetAddress.getAllByName(host);
                } catch (UnknownHostException e) {
                    log.warn("DNS warmup failed for {}", host);
                }
            });
        }
    }
}
```

**K8s 探针**:
```yaml
startupProbe:
  httpGet:
    path: /health/dns
    port: 8080
  failureThreshold: 30
  periodSeconds: 5
livenessProbe:
  httpGet:
    path: /health/full
    port: 8080
```
`/health/dns` 检查所有外部域名解析成功才让流量进。

---

## 7. 完整组合方案 — "四件套"

> GKE Java Pod 外部域名解析出错,**4 件套同时启用**,不是任选其一。

### 7.1 应用代码(必做)

```yaml
# 配置文件 — 外部域名一律带尾部点
external-services:
  partner-api:
    base-url: "http://api.partner.com."    # 关键:尾部点
  payments:
    base-url: "https://api.stripe.com."
  storage:
    base-url: "https://s3.amazonaws.com."
```
+ Lint 规则强制外部域名带尾部点
+ HTTP client 显式设 Host header(剥掉尾部点)

### 7.2 JVM 调参(必做)

```yaml
env:
- name: JAVA_TOOL_OPTIONS
  value: >-
    -Dnetworkaddress.cache.ttl=10
    -Dnetworkaddress.cache.negative.ttl=5
    -Dsun.net.inetaddr.ttl=10
    -Dsun.net.client.defaultConnectTimeout=3000
    -Dsun.net.client.defaultReadTimeout=3000
```

### 7.3 GKE 集群(必做)

```bash
gcloud container clusters update $CLUSTER --enable-dns-cache
```

### 7.4 CoreDNS(必做)

按 §4.2 的 Corefile 调优:多上游 + force_tcp + cache prefetch + serve_stale。

### 7.5 HTTP client(必做)

按 §6 配置:connect/read timeout、retry、warmup。

---

## 8. 监控与验证

### 8.1 必看指标

```promql
# 外部域名解析延迟 P99(应该 < 50ms,CoreDNS 缓存命中时 < 1ms)
histogram_quantile(0.99,
  rate(coredns_dns_request_duration_seconds_bucket{server="dns://:53"}[5m]))

# NXDOMAIN 占比(外部域名应该 < 5%,高了 = 配错或上游故障)
rate(coredns_dns_responses_total{rcode="NXDOMAIN"}[5m])
  / rate(coredns_dns_responses_total[5m])

# SERVFAIL 占比(应该 ≈ 0,升高 = 上游 Cloud DNS 故障)
rate(coredns_dns_responses_total{rcode="SERVFAIL"}[5m])
  / rate(coredns_dns_responses_total[5m])

# NodeLocal 命中率
rate(node_local_dnscache_cache_hits_total[5m])
  / (rate(node_local_dnscache_cache_hits_total[5m])
     + rate(node_local_dnscache_cache_misses_total[5m]))

# forward 插件健康(如果有多个上游)
coredns_forward_healthcheck_failures_total
```

### 8.2 应用层拨测

```yaml
# dns-probe-external.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: dns-probe-external
spec:
  schedule: "*/1 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: probe
            image: drill/drill
            args:
            - "@169.254.20.10"                                  # NodeLocal
            - "api.partner.com."                                 # 带尾部点(测正解)
            - "api.partner.com"                                  # 不带尾部点(测 search path 行为)
            - "nonexistent.partner.com."                         # 测 NXDOMAIN 缓存时长
            - "s3.amazonaws.com."                                # 公网域名
          restartPolicy: OnFailure
```

### 8.3 JVM 层打点

```java
@Aspect
@Component
public class DnsMetricsAspect {
    private final MeterRegistry registry;
    
    @Around("execution(* java.net.InetAddress.getAllByName0(..))")
    public Object trace(ProceedingJoinPoint pjp) throws Throwable {
        long start = System.nanoTime();
        try {
            Object result = pjp.proceed();
            registry.counter("dns.lookup", "result", "success").increment();
            return result;
        } catch (UnknownHostException e) {
            registry.counter("dns.lookup", "result", "negative").increment();
            throw e;
        } finally {
            registry.timer("dns.lookup.duration")
                .record(System.nanoTime() - start, TimeUnit.NANOSECONDS);
        }
    }
}
```

---

## 9. 踩坑实录(外部域名专属)

### 9.1 外部域名加尾部点,Host header 报 400

**症状**:NGINX 报 `400 Bad Request - Invalid Host`。
**根因**:HTTP Host header 不允许带尾部点。
**修法**:解析层用尾部点,发送层显式剥掉:
```java
HttpRequest req = HttpRequest.newBuilder(URI.create("http://api.partner.com./orders"))
    .header("Host", "api.partner.com")  // ← 关键
    .build();
```

### 9.2 公网 DNS 兜底导致所有外部域名走公网 NAT

**症状**:CoreDNS `forward . 8.8.8.8` 后,所有外部域名延迟 50ms+,部分被 GFW 干扰。
**根因**:GKE 节点出站 UDP 53 到公网可能受 VPC firewall / Cloud NAT 限制。
**修法**:CoreDNS `forward` 只用 GCP 内部 DNS(`10.60.0.2`),**不要**加公网 DNS 兜底。

### 9.3 外部域名短 TTL + JVM 长 cache = CDN 调度失效

**症状**:CDN 切换 region 后,Java 端**最长 30s** 仍连旧 region。
**根因**:`networkaddress.cache.ttl=30` > CDN TTL 5s。
**修法**:`networkaddress.cache.ttl=10` 或更短。

### 9.4 Java 负缓存放大外部域名故障

**症状**:外部域名挂 5s 恢复,Java 端**持续 10s 失败**。
**根因**:`networkaddress.cache.negative.ttl=10`。
**修法**:`=5` 或更短。

### 9.5 上游 Cloud DNS 网关故障,全集群外部域名挂

**症状**:CoreDNS 大量 SERVFAIL,`35.199.192.0/19` 网段异常。
**根因**:CoreDNS `forward .` 单上游无健康检查。
**修法**:加备选上游 + `prefer_healthy` + `max_fails 3` + `expire 10s`。

### 9.6 防火墙截断 UDP 53 出站

**症状**:部分外部域名解析直接 timeout。
**根因**:VPC firewall / GKE Sandbox / Calico NetworkPolicy 阻止 UDP 53 出站。
**修法**:CoreDNS `forward` 加 `force_tcp`,同时在 NetworkPolicy 放行 TCP 53。

### 9.7 TTL 调到 5s 后 CoreDNS QPS 暴增

**症状**:CoreDNS 内存涨、CPU 高、节点出口带宽涨。
**根因**:`networkaddress.cache.ttl=5` + 大量短 TTL 外部域名 + NodeLocal 没开。
**修法**:
- 优先**开 NodeLocal** 顶住节点级 QPS
- JVM cache 留 10s,平衡
- CoreDNS `cache` plugin `success 1000` 顶住 Pod 级重复

---

## 10. 决策表 — 症状 → 根因 → 修法

| 症状 | 怀疑根因 | 验证方法 | 修法 |
|------|----------|----------|------|
| 外部域名首次解析 500ms+,后续 50ms | ndots search path 风暴(E1) | `nslookup api.partner.com` vs `nslookup api.partner.com.` | URL 加尾部点 |
| 外部域名解析 P99 > 50ms 持续 | CoreDNS forward 路径长(E2) | CoreDNS 日志看是否每次都走 forward | 开 NodeLocal + CoreDNS cache |
| 外部域名挂 5s 恢复后 Java 端 10s 内持续失败 | Java 负缓存(E3) | jstack 看错误一致 | `networkaddress.cache.negative.ttl=5` |
| CDN 切换 region 后 Java 端仍连旧 region | JVM cache TTL 过长(E4) | `tcpdump` 看 SYN 目的 IP | `networkaddress.cache.ttl=10` |
| 外部域名首次解析 5s+ | Java 默认重试 / 串行(E5) | 看 stack 是 `getAllByName0` 阻塞 | 调 connectTimeout + HTTP client retry |
| 冷启动时第一次请求 100% 失败 | 连接池未预热(E6) | 看启动日志 | 启动时 warmup + startupProbe |
| 35.199.192.0/19 故障时全集群挂 | CoreDNS forward 单上游(E7) | CoreDNS 日志 SERVFAIL | 多上游 + prefer_healthy |

---

## 11. 一句话总结

> **外部域名 DNS 解析出错,不是单点问题**。
> - **FQDN(尾部点)解 E1** — 让 resolver 跳过 4 次 NXDOMAIN
> - **JVM cache TTL 调短解 E3 + E4** — 平衡陈旧与压力
> - **HTTP client 重试 + 超时解 E5 + E6** — 最后一道防线
> - **CoreDNS 多上游 + force_tcp 解 E2 + E7** — 转发链健壮性
> - **NodeLocal DNSCache 解 E2 性能面** — 减一跳
> **4 件套组合 = 必做**;HTTP client 调优 = 生产环境必做。

---

## 12. 参考文档

- `dns-resolution-ndots.md` — ndots 行为、绝对 FQDN、CoreDNS 转发链
- `/Users/lex/git/knowledge/linux/dns/docs/external-internal-dns-separation.md` — 内外网 DNS 分离
- `/Users/lex/git/knowledge/linux/dns/docs/gcp-dns-explorer-gpt5-6.md` — 探索基准
- GKE 官方 — NodeLocal DNSCache:https://cloud.google.com/kubernetes-engine/docs/how-to/dns-cache
- CoreDNS forward plugin:https://coredns.io/plugins/forward/
- CoreDNS cache plugin:https://coredns.io/plugins/cache/
- Java `InetAddress` cache 调参:https://docs.oracle.com/javase/8/docs/technotes/guides/net/properties.html
- OkHttp DNS:https://square.github.io/okhttp/4.x/okhttp/okhttp3/-dns/
