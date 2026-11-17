# Istio 网格内 DNS 解析与服务发现机制

## 1. 问题背景

### 场景描述

Gateway 暴露的域名为 `www.abc.com`，Pod 内部也需要访问 `www.abc.com/api1/health` 或 `www.abc.com/api2/health`。此时 Pod 是否需要"绕出去"走公网访问？

### 核心问题

- Pod 通过什么 DNS 解析 `www.abc.com`？
- 解析结果是公网 IP 还是内网 IP？
- 流量是否必须经过外部 Gateway 才能访问集群内服务？

---

## 2. Istio 环境下的 DNS 解析链路

### 2.1 链路流程图

![DNS Flow Diagram](dns-flow.html)

### 2.2 默认行为（无特殊配置）

当 Pod 访问 `www.abc.com` 时：

```
Pod
  │
  │ 1. 查询 /etc/resolv.conf 中的 nameserver（默认 kube-dns）
  │
  ▼
kube-dns (CoreDNS in kube-system)
  │
  │ 2. kube-dns 没有 www.abc.com 的记录
  │
  ▼
  │
  │ 3. 递归查询公网 DNS（Cloud DNS 或外部 DNS）
  │
  ▼
公网 DNS 返回公网 IP（例如 1.2.3.4）
  │
  ▼
Pod 用公网 IP 访问 → 走 NAT/网关 → 外部入口
```

**结论**：Pod 会走公网，绕一大圈才能回来，效率低下且增加延迟。

### 2.2 为什么不能直接解析到内网 IP？

因为 `www.abc.com` 的 DNS 记录通常只包含公网 IP，而公网 IP 无法直接从 VPC 内部路由到集群入口（除非配置了内部 LB）。

---

## 3. GCP Istio / GKE 环境下的 DNS 控制机制

### 3.1 Cloud DNS 私有托管区域（Private DNS Zone）

GCP Cloud DNS 可以创建私有托管区域，仅在 VPC 内部生效：

```yaml
apiVersion: dns.cnrm.cloud.google.com/v1beta1
kind: DNSManagedZone
metadata:
  name: abc-internal-zone
  namespace: my-namespace
spec:
  description: "Internal DNS for abc.com"
  dnsName: "abc.com."
  visibility: private
  privateVisibilityConfig:
    networkRefs:
      - name: my-vpc
        namespace: my-namespace
```

配合 DNS Peering 或 Cloud DNS in-cluster resolver，可以让集群内的 kube-dns 解析 `abc.com` 时返回内网 IP。

### 3.2 Istio 的 DNS 代理（ Envoy DNS 代理）

Istio 1.8+ 引入了 `istio-cni` 的 DNS 代理功能，Envoy 可以拦截 DNS 请求并进行智能解析：

```
Pod
  │
  │ DNS 请求被 Envoy 拦截
  │
  ▼
Envoy Sidecar Proxy
  │
  ├── 如果是网格内部服务 → 直接解析为 Endpoint IP（绕过 kube-dns）
  │
  └── 如果是外部域名   → 转发给 kube-dns → 公网查询
```

**关键配置**：`istio.yaml` 中的 `dnsCapture` 和 `dnsAutoPassthrough`：

```yaml
meshConfig:
  enableDnsCapture: true
  dnsAutoPassthrough: false
```

### 3.3 Istio 的 ServiceEntry 内部解析

通过定义 ServiceEntry，可以将外部服务声明为网格内可解析的服务：

```yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: www-abc-com-internal
  namespace: my-namespace
spec:
  hosts:
    - www.abc.com
  location: MESH_INTERNAL
  ports:
    - number: 443
      name: https
      protocol: HTTPS
  endpoints:
    - address: 10.112.1.100   # 内部 IP（Internal GCLB/NEEDED）
      ports:
        https: 443
```

**工作原理**：

1. Pod 访问 `www.abc.com`
2. Envoy 拦截 DNS 查询
3. 发现存在 MESH_INTERNAL 的 ServiceEntry，返回内部 IP `10.112.1.100`
4. 流量直接路由到内网 IP，不再走公网

### 3.4 DestinationRule 定义后端策略

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: www-abc-com
  namespace: my-namespace
spec:
  host: www.abc.com
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 100
    tls:
      mode: ISTIO_MUTUAL
    loadBalancer:
      simple: LEAST_REQUEST
    subsets:
      - name: v1
        labels:
          version: v1
      - name: v2
        labels:
          version: v2
```

---

## 4. 企业最佳实践：同域名内外分流

### 场景划分

| 场景 | 调用方式 | 路由目标 |
|------|----------|----------|
| 外部用户 | 浏览器/客户端 | `www.abc.com` → 公网 GCLB → Gateway |
| Pod 内部调用服务 A | 内部服务名 | `http://service-a.namespace.svc.cluster.local` |
| Pod 访问同域名的外部 API | 内部服务 + VirtualService | `www.abc.com` → 内网 IP → 路由到真实后端 |

### 推荐做法

#### 做法 1：ServiceEntry 指向内部 IP

用 ServiceEntry 声明 `www.abc.com` 的内网解析和路由：

```yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: www-abc-com-internal
  namespace: my-namespace
spec:
  hosts:
    - www.abc.com
  location: MESH_INTERNAL
  ports:
    - number: 443
      name: https
      protocol: HTTPS
    - number: 80
      name: http
      protocol: HTTP
  resolution: STATIC
  endpoints:
    - address: 10.112.1.100   # 内部 IP（Internal GCLB）
      ports:
        https: 443
        http: 80
```

配合 DestinationRule 定义 mTLS 和负载均衡策略。

#### 做法 2：Pod 内部直接用 Kubernetes Service DNS

**最佳实践原则**：Pod 访问内部服务时，用集群内部 DNS，不走外部域名。

```
# 不推荐（绕公网，效率低）
www.abc.com/api1/health

# 推荐（直接内网路由）
http://my-service.my-namespace.svc.cluster.local/api1/health

# 或用 Istio 内部 host（通过 VirtualService/DestinationRule 路由）
http://my-service/api1/health
```

#### 做法 3：Istio VirtualService 定义内部路由规则

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-service-internal
  namespace: my-namespace
spec:
  hosts:
    - my-service
    - my-service.my-namespace
    - my-service.my-namespace.svc.cluster.local
  http:
    - match:
        - uri:
            prefix: /api1/
      route:
        - destination:
            host: my-service
            subset: v1
            port:
              number: 8080
    - match:
        - uri:
            prefix: /api2/
      route:
        - destination:
            host: my-service
            subset: v2
            port:
              number: 8080
  tls:
    - match:
        - port: 443
          sniHosts:
            - my-service
      route:
        - destination:
            host: my-service
            subset: v1
            port:
              number: 443
```

---

## 5. VirtualService 和 DestinationRule 的职责划分

### VirtualService

定义"请求怎么转发"——匹配 host、path、header、subset 等条件：

```yaml
spec:
  hosts:        # 匹配的请求 host
    - www.abc.com
  gateways:     # 关联的 Gateway（控制外部入口）
    - istio-system/public-gateway
  http:
    - match:
        - headers:
            x-version:
              exact: v2
      route:
        - destination:
            host: my-service
            subset: v2
    - route:
        - destination:
            host: my-service
            subset: v1
```

### DestinationRule

定义"转发到目标 host 时，后端实例怎么分组和连接"：

```yaml
spec:
  host: www.abc.com   # 与 VirtualService 的 destination 对应
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
    connectionPool:
      tcp:
        maxConnections: 100
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 60s
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
```

### 配合工作的例子

外部请求（通过 Gateway）：

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: www-abc-gateway
  namespace: istio-system
spec:
  hosts:
    - www.abc.com
  gateways:
    - istio-system/public-gateway
  http:
    - match:
        - uri:
            prefix: /api1/
      route:
        - destination:
            host: my-service.my-namespace.svc.cluster.local
            subset: v1
```

内部 Pod 访问 `www.abc.com` 时，ServiceEntry 拦截后直接路由到内部 IP。

---

## 6. 为什么这样更优

### 延迟对比

| 方式 | DNS 解析 | 路由跳数 | 典型延迟 |
|------|----------|----------|----------|
| Pod 直接访问公网域名 | 公网 DNS | 4-6 跳（公网 → LB → Gateway） | 50-200ms |
| ServiceEntry 内部解析 | kube-dns / Envoy | 1-2 跳（内部网络） | 1-5ms |

### 策略隔离

- 内部调用和对外入口分离，互不影响
- 改 Gateway / LB / 域名解析时，不影响 Pod 内部服务调用
- 内部服务不会被外部域名和路径绑定

### 安全优势

- 内部流量完全在 VPC 内部，不暴露公网
- 可通过 AuthorizationPolicy 精确控制服务间访问权限
- mTLS 自动加密，无需手动配置

---

## 7. 网络 Policy 修复

### 原始问题 YAML

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-dns
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: kube-system
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

### 错误说明

1. `protoco` → `protocol`（拼写错误）
2. `to:` 下面的 `namespaceSelector` 和 `podSelector` 缩进多了一层，与 `to` 同级应该是 `- to:` 中的第二个 `-`，缩进应为 6 空格
3. `ports` 应与 `to` 同级，是 egress 规则的一部分

### 修复后 YAML

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-dns
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

### 修复说明

| 位置 | 修复内容 |
|------|----------|
| `protoco` | 改为 `protocol` |
| `to:` 块 | 缩进调整为正确层级，`namespaceSelector` 和 `podSelector` 与 `to` 同级 |

---

## 9. GKE DNS 安全与加固

### 9.1 DNS 是否加密？

在 GKE 环境中，Pod 默认使用 standard DNS 协议（UDP/TCP 53），这些流量**在传输过程中通常是明文（Unencrypted）的**。

- **是否允许？**：在 Google Cloud VPC 内部，这是默认且允许的行为。由于流量在 Google 的受保护内网中传输，通常认为其面临的被动监听风险较低。
- **潜在风险**：恶意 Pod 可能通过 ARP 欺骗或网络嗅探尝试捕获同一节点上的 DNS 查询（尽管 VPC-native 架构极大地限制了这种风险）。

### 9.2 加固建议（Hardening）

1.  **Cloud DNS for GKE**：
    *   将 `kube-dns` 替换为托管的 Cloud DNS。
    *   **优势**：100% SLA，由于是托管服务，其解析请求直接发往 Google API，不再需要在集群内运行 DNS Pod，减少了攻击面。
2.  **NodeLocal DNSCache**：
    *   在每个节点运行缓存 Agent。
    *   **优势**：减少 CoreDNS 负载，提高解析稳定性，同时 DNS 流量主要在本地 Loopback 接口处理。
3.  **DNS-based Endpoints (Control Plane)**：
    *   使用 GKE 提供的 FQDN 访问 API Server。
    *   **优势**：可以配合 IAM 鉴权，实现更细粒度的控制面访问保护。

### 9.3 跨命名空间隔离与安全性

**问题**：如果 A Team 和 B Team 都在同一集群但不同 Namespace，他们都用同一个 `kube-dns` 解析，是否安全？

**结论**：DNS 本身主要负责 "地址解析" 而不是 "访问控制"。
1.  **解析可见性**：默认情况下，CoreDNS 是全集群共享的。Team A 的 Pod **可以解析**到 Team B 的服务地址（例如 `service-b.team-b.svc`）。仅通过 DNS 无法实现 "逻辑上看不见"。
2.  **访问控制（核心）**：解析到 IP 并不代表能访问。
    *   **NetworkPolicy**：这是最直接的手段。通过定义 Egress/Ingress Policy，即便 Team A 知道了 Team B 的 IP，其网络包也会在 Pod 边界或 Pod 接收端被丢弃。
    *   **Istio Sidecar 隔离**：在 Istio/ASM 中，你可以使用 `Sidecar` 资源来限制哪些服务的配置（Endpoints）被推送到特定命名空间的 Sidecar。这样 Team A 的 Envoy 甚至不知道 Team B 的服务存在，解析请求会在 Sidecar 层面被拒绝/路由失败。

### 9.4 理解图：多租户隔离架构

![DNS Security Diagram](dns-security.html)

---

## 10. 总结

**Pod 访问 `www.abc.com` 是否需要绕出去？**

- 默认情况下：**是**。DNS 解析返回公网 IP，流量走公网再回来，效率低。
- 配置 ServiceEntry + 内部 IP 后：**否**。DNS 解析返回内网 IP，流量直接在内网路由。

**最佳实践**：
1. 服务间调用用 Kubernetes Service DNS（`svc.cluster.local`）
2. 外部可访问的服务用 ServiceEntry 声明内部解析，Pod 不直接依赖外部域名
3. 用 VirtualService 和 DestinationRule 分离路由策略和连接策略
4. 内外分流，内部流量不走公网