# DestinationRule 深度探索

> 适用环境：GKE + Google Cloud Service Mesh / ASM，Istio sidecar 数据面
> 目标：彻底理解 DestinationRule 的本质、使用场景、TLS 模式、以及与 Istio 其他 CRD 的关系
> 前置知识：已理解 VirtualService、Istio Gateway、Sidecar 注入概念

---

## 1. 先纠正一个关键误解

**DestinationRule 不是 no-sidecar 场景独有的。**

DestinationRule 是 Istio 中最基础、最常用的 CRD 之一，它的核心作用是：**定义"调用方" Envoy proxy 如何连接到一个目标服务**。

换句话说，DestinationRule 是"出口流量策略"——它告诉你的 Sidecar/Envoy **出去的时候** 怎么连接对方。它和对方有没有 Sidecar 无关。

所有 DestinationRule 生效的位置都是**调用方的 Sidecar**，即：

```
你的 Pod (有 Sidecar)
  -> 读取 DestinationRule
  -> 决定如何连接目标服务
  -> 发出流量
```

---

## 2. DestinationRule 的本质

### 2.1 谁读取 DestinationRule？

**是调用方的 Sidecar/Envoy，不是被调用方的 Sidecar。**

| 场景 | 读取 DR 的 Envoy | DR 作用对象 |
|------|----------------|-------------|
| Gateway → Runtime | Gateway Pod 的 Sidecar | Gateway 如何发出调用 |
| Sidecar A → Sidecar B | Sidecar A | Sidecar A 如何连接 B |
| Sidecar → 外部服务 | Sidecar | Sidecar 如何连接外部 |

### 2.2 DestinationRule 在 Istio CRD 链中的位置

```
VirtualService    → 路由规则（去哪个 host/path/subset）
DestinationRule   → 流量策略（连接方式、TLS 模式、负载均衡）
Gateway          → 入口流量（外部如何进入 mesh）
```

VirtualService 决定"流量去哪"，DestinationRule 决定"怎么连过去"。

### 2.3 DestinationRule 的 host 字段

```yaml
spec:
  host: my-service        # 简短名字（相对于 namespace）
  # 或
  host: my-service.default.svc.cluster.local  # FQDN
```

`host` 匹配 Kubernetes Service 名称。如果 VirtualService 和 DestinationRule 在同一 namespace，可以只写 Service 名。

---

## 3. TLS 模式详解（全场景覆盖）

`trafficPolicy.tls.mode` 是 DestinationRule 最核心的配置。Istio 支持四种模式：

### 3.1 ISTIO_MUTUAL（最常用，自动 mTLS）

**场景：** mesh 内服务互调，双方都有 Istio Sidecar。

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-service-dr
  namespace: ns-a
spec:
  host: my-service.ns-b.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL   # 使用 Istio 自动签发的 SPIFFE 证书做 mTLS
```

**发生了什么：**
- 调用方 Sidecar 从 istiod 获取 SPIFFE 证书
- 连接目标时，Sidecar 自动完成 mTLS 握手
- 双方身份由 SPIFFE ID 标识，例如 `cluster.local/ns-b/sa/my-service-account`
- 证书自动轮转，无需人工干预

**这是 mesh 的默认推荐模式。** 在完全迁移到 mesh mTLS 后，所有内部服务调用都应该使用 ISTIO_MUTUAL。

### 3.2 SIMPLE（发起 HTTPS，无需客户端证书）

**场景：** 调用没有 Istio Sidecar 的服务，或调用外部 HTTPS 服务。

```yaml
# 场景 A：从 Gateway 调用没有 Sidecar 的 Runtime App（no-mtls-sidecar 方案）
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team-a-service-tls
  namespace: team-a-runtime
spec:
  host: team-a-service.team-a-runtime.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: team-a-service.team-a-runtime.svc.cluster.local
```

**场景 B：从 Sidecar 调用外部 HTTPS API：**

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: external-api-dr
  namespace: istio-system
spec:
  host: api.external.com
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: api.external.com
```

**发生了什么：**
- 调用方 Envoy 作为 TLS 客户端，发起 HTTPS 连接
- 只验证服务端证书（如果使用系统 CA 或指定 caCertificates）
- 不需要客户端证书
- `sni` 字段告诉 TLS 客户端在 SNI 扩展中发送什么主机名

**你的 no-sidecar 方案中，Gateway Envoy 就是用这个模式连接到 Runtime App 的 8443。**

### 3.3 MUTUAL（双向 HTTPS，客户端必须提供证书）

**场景：** 调用外部服务时需要客户端证书（mTLS 客户端认证）。

```yaml
# 从 mesh 内部调用需要客户端证书的外部 SaaS API
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: saas-api-mtls
  namespace: istio-system
spec:
  host: proxy-saas2.mesh.local
  trafficPolicy:
    portLevelSettings:
    - port:
        number: 3128
      tls:
        mode: MUTUAL
        credentialName: saas2-client-credential   # 引用 Kubernetes Secret
        sni: api.saas2.com
        subjectAltNames:
        - api.saas2.com
```

**发生了什么：**
- Envoy 作为 TLS 客户端，发起双向 HTTPS 握手
- `credentialName` 指向一个 Kubernetes Secret，里面包含 client.crt + client.key
- `subjectAltNames` 指定服务端期望的客户端证书身份
- 同时验证服务端证书

**credentialName Secret 格式：**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: saas2-client-credential
  namespace: istio-system
type: kubernetes.io/tls
data:
  cert: <base64 encoded client cert>
  key: <base64 encoded client key>
```

### 3.4 DISABLE（明文，不加密）

**场景：** 告诉 Sidecar 不要对目标使用任何 TLS，直接 TCP 明文。

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: plaintext-dr
  namespace: default
spec:
  host: my-service
  trafficPolicy:
    tls:
      mode: DISABLE
```

**常见用途：**
- 调用明确不使用 TLS 的内部 HTTP 服务
- 调试时临时禁用 TLS
- 配合 `PERMISSIVE` mTLS 模式做迁移过渡

**警告：** 不要对公网流量使用 DISABLE。

---

## 4. TLS 模式选择决策树

```
发起调用前，先问三个问题：
│
├─ 目标服务在 mesh 内，且双方都有 Sidecar？
│   └─ YES → ISTIO_MUTUAL ✓
│
├─ 目标服务需要客户端证书（外部 mTLS）？
│   └─ YES → MUTUAL + credentialName
│
├─ 目标服务是 HTTPS，但没有 Sidecar（你的 no-sidecar 场景）？
│   └─ YES → SIMPLE + sni
│
└─ 目标服务是明文 HTTP，不需要加密？
    └─ YES → DISABLE（仅内网）
```

---

## 5. Subsets（版本分组）

### 5.1 什么是 Subset？

Subset 是对同一个 Service 的不同版本的分组定义，配合 VirtualService 做金丝雀/蓝绿发布。

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-service-dr
  namespace: my-namespace
spec:
  host: my-service
  trafficPolicy:           # 全局策略，所有 subset 继承
    tls:
      mode: ISTIO_MUTUAL
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
    - name: canary
      labels:
        version: canary
```

**`labels` 匹配 Kubernetes Pod 标签：**

```yaml
# v1 Pod
apiVersion: v1
kind: Pod
metadata:
  name: my-service-v1-abc123
  labels:
    version: v1
    app: my-service
spec:
  containers:
    - name: app
      image: my-service:v1
---
# v2 Pod
apiVersion: v1
kind: Pod
metadata:
  name: my-service-v2-xyz789
  labels:
    version: v2
    app: my-service
spec:
  containers:
    - name: app
      image: my-service:v2
```

### 5.2 不同 Subset 可以有不同的流量策略

```yaml
subsets:
  - name: v1
    labels:
      version: v1
    trafficPolicy:          # v1 特殊策略
      connectionPool:
        tcp:
          maxConnections: 50
  - name: v2
    labels:
      version: v2
    trafficPolicy:          # v2 可以用更激进的策略
      connectionPool:
        tcp:
          maxConnections: 200
      loadBalancer:
        simple: LEAST_REQUEST
```

---

## 6. 流量策略详解（trafficPolicy）

### 6.1 TLS 配置

最常用，直接决定如何加密出站流量。详见第 3 节。

```yaml
trafficPolicy:
  tls:
    mode: ISTIO_MUTUAL | SIMPLE | MUTUAL | DISABLE
    sni: ...
    caCertificates: ...     # 可选，用于验证服务端
    credentialName: ...     # MUTUAL 模式必需
```

### 6.2 Load Balancer

```yaml
trafficPolicy:
  loadBalancer:
    simple: ROUND_ROBIN | LEAST_REQUEST | RANDOM | PASSTHROUGH
    consistentHash:
      httpHeaderName: x-user-id
```

### 6.3 Connection Pool

```yaml
trafficPolicy:
  connectionPool:
    tcp:
      maxConnections: 100      # 最大 HTTP/1.1 连接数
    http:
      h2UpgradePolicy: UPGRADE # HTTP/1 → HTTP/2 升级
      maxRequestsPerConnection: 100
      maxPendingRequests: 100
```

### 6.4 Outlier Detection（熔断）

```yaml
trafficPolicy:
  outlierDetection:
    consecutive5xxErrors: 5   # 连续 5 次 5xx，弹出实例
    interval: 30s              # 检测间隔
    baseEjectionTime: 30s      # 最小弹出时间
    maxEjectionPercent: 50     # 最多弹出 50% 实例
```

### 6.5 Port Level Settings（端口级策略）

对同一 `host` 的不同端口使用不同策略：

```yaml
trafficPolicy:
  portLevelSettings:
    - port:
        number: 8443
      tls:
        mode: SIMPLE
    - port:
        number: 8080
      tls:
        mode: ISTIO_MUTUAL
```

---

## 7. 在你的 No-Sidecar 方案中的角色

### 7.1 为什么需要 DestinationRule？

在你的 no-sidecar 方案中：

```
Gateway Pod (有 Sidecar)
  │
  │  Gateway Envoy 需要调用 Runtime App
  │  Runtime App 在端口 8443 上监听 HTTPS
  │  Runtime App 没有 Sidecar，所以不能走 ISTIO_MUTUAL
  │
  └─ 需要 DestinationRule 告诉 Gateway Envoy：
       "用 SIMPLE TLS 模式连接到 team-a-service:8443"
```

**没有 DestinationRule 会发生什么：**
- Gateway Envoy 默认会用 mesh mTLS
- 但 Runtime App 没有 Sidecar，不会响应 mTLS 握手
- 连接失败

### 7.2 你的 DestinationRule 配置

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team-a-service-tls
  namespace: team-a-runtime
spec:
  host: team-a-service.team-a-runtime.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: team-a-service.team-a-runtime.svc.cluster.local
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 100
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
```

### 7.3 namespace 放哪里？

放在 `team-a-runtime`（和被调用方同 namespace）是最常见做法，也可以放在 Gateway namespace 或 `istio-system`。关键原则：

- DR 的 `host` 必须是**被调用方**的 Service FQDN
- 调用方（Gateway）能读到 DR 即可（通过 ServiceAccount 跨 namespace 读取）

---

## 8. DestinationRule vs PeerAuthentication

这两个经常被混淆，但作用完全不同：

| 维度 | DestinationRule | PeerAuthentication |
|------|----------------|-------------------|
| **作用方向** | 我怎么连别人（出站） | 别人怎么连我（入站） |
| **生效位置** | 调用方的 Sidecar | 被调用方的 Sidecar |
| **TLS 方向** | TLS 发起（origination） | TLS 终止（termination） |
| **典型场景** | "我用 SIMPLE TLS 访问外部 HTTPS" | "我只接受 mTLS 连接" |
| **no-sidecar 场景** | **需要**（Gateway → Runtime） | 不需要（Runtime 无 Sidecar） |
| **mesh mTLS 场景** | 可选（默认 ISTIO_MUTUAL） | 需要（STRICT/PERMISSIVE） |

**在你的 no-sidecar 方案中：**
- Runtime namespace **不需要** PeerAuthentication（没有 Sidecar）
- Gateway namespace 需要 **DestinationRule** 告诉 Gateway Envoy 怎么连 Runtime

---

## 9. 常见错误和避坑

### 9.1 DISABLE 不是"禁用 TLS 终止"

`tls.mode: DISABLE` 是告诉**调用方** Sidecar 不要用 TLS 发出。如果后端服务是 HTTPS，这不会让它变成 HTTPS —— 它会变成明文 HTTP。用了 DISABLE 再访问 HTTPS 后端会失败。

### 9.2 ISTIO_MUTUAL 不需要指定证书

ISTIO_MUTUAL 使用 Istio 自动管理的 SPIFFE 证书，不需要也不应该指定 `credentialName`。如果写了，Istio 会忽略 SPIFFE 转而用你指定的证书。

### 9.3 DestinationRule 不会覆盖 Server 的 TLS 配置

DestinationRule 控制**客户端**的 TLS 行为。Server 端（被调用方）的 TLS 配置由 Gateway 或 Server 本身的配置决定。两者需要匹配：
- Server 要求 mTLS → Client 用 ISTIO_MUTUAL 或 MUTUAL
- Server 要求 HTTPS (SIMPLE) → Client 用 SIMPLE
- Server 要求明文 → Client 用 DISABLE

### 9.4 MUTUAL 模式的 Secret 类型

必须使用 `type: kubernetes.io/tls` 的 Secret，不能是 generic Secret：

```bash
kubectl create secret tls my-client-certs \
  --cert=client.crt \
  --key=client.key \
  -n istio-system
```

### 9.5 DR 不影响入站流量

DestinationRule 是**出站**策略。如果你想要控制"谁可以访问我的服务"，那是 AuthorizationPolicy 和 NetworkPolicy 的工作，不是 DestinationRule。

---

## 10. 参考：在不同场景中的 DestinationRule 配置

| 场景 | DR host | TLS mode | 说明 |
|------|---------|----------|------|
| Gateway → Runtime (no-sidecar) | `team-a-service.team-a-runtime...` | SIMPLE | Gateway Envoy 发起 HTTPS |
| Sidecar → Sidecar (mesh mTLS) | `other-svc.other-ns...` | ISTIO_MUTUAL | 自动 SPIFFE mTLS |
| Sidecar → 外部 HTTPS API | `api.external.com` | SIMPLE | 只需要服务端证书验证 |
| Sidecar → 外部 mTLS API | `proxy-saas2.mesh.local` | MUTUAL | 需要客户端证书 |
| Sidecar → 明文 HTTP | `legacy-service` | DISABLE | 仅内网，调试用 |

---

## 11. 验证 DestinationRule 是否生效

### 11.1 查看所有 DestinationRule

```bash
kubectl get destinationrule --all-namespaces
```

### 11.2 查看特定 Service 的 DestinationRule

```bash
kubectl get destinationrule -n team-a-runtime team-a-service-tls -o yaml
```

### 11.3 从 Gateway Pod 验证对后端的 TLS 连接

```bash
GW_POD="$(kubectl get pod -n istio-ingressgateway-int -l app=istio-ingressgateway-int -o jsonpath='{.items[0].metadata.name}')"

# 检查 TLS 版本和证书
kubectl exec -n istio-ingressgateway-int "$GW_POD" -c istio-proxy -- \
  openssl s_client -connect team-a-service.team-a-runtime.svc.cluster.local:8443 -servername team-a-service.team-a-runtime.svc.cluster.local

# 查看 Envoy 配置中是否包含 DR
kubectl exec -n istio-ingressgateway-int "$GW_POD" -c istio-proxy -- \
  curl localhost:15000/config_dump?resource=dynamic_listeners | jq '.configs[].filter_chains[].filters'
```

### 11.4 检查 istio-proxy 日志中的 TLS 握手

```bash
kubectl logs -n istio-ingressgateway-int "$GW_POD" -c istio-proxy -- | grep -i "tls\|certificate\|TLS"
```
