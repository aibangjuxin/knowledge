# Istio Context Path 与 Request Path 一致性最佳实践

## 1. 核心概念：Context Path 与 Request Path

### 1.1 定义

| 概念 | 定义 | 示例 |
|------|------|------|
| **Context Path**（上下文路径） | VirtualService 中 `http.match.uri.prefix` 定义的路由前缀 | `prefix: "/v1"` |
| **Request Path**（请求路径） | 客户端实际发送的 HTTP 请求 URI | `GET /v1/health` |
| **Version Tag**（版本标签） | Context Path 中嵌入的版本标识，用于区分服务版本 | `/v1`, `/v2` |

### 1.2 核心原则

**Context Path 必须与 Request Path 保持一致。**

这不是技术约束，而是设计原则。只有当 VirtualService 的 `prefix` 与客户端实际请求的路径前缀匹配时，路由才能正常工作。

```
✅ 正确：Client 请求 /v1/health → VS prefix: /v1 → 路由到 v1 subset
❌ 错误：Client 请求 /v1/health → VS prefix: /api  → 路由失败（404）

```

---

## 2. Context Path 即 Version Tag

### 2.1 为什么 Context Path 像版本标签？

当你设计 API 时，通常会使用路径版本化：

```bash
GET /v1/products/123
GET /v2/products/123
```

这里的 `/v1` 和 `/v2` 就是 **Context Path**，它们本质上是**版本标签**：

- 用户通过选择不同的路径前缀来选择不同的服务版本
- 服务运营商通过设计不同的 VirtualService + DestinationRule subset 来实现版本隔离
- Context Path 成为用户自我控制版本的"开关"

### 2.2 版本标签的价值

| 能力 | 说明 |
|------|------|
| **用户自主版本选择** | 用户根据自己的需求调用 `/v1/` 或 `/v2/`，不依赖服务方强制升级 |
| **灰度发布** | 可以将部分流量引导到新版本，逐步验证 |
| **多版本共存** | 旧版本不删除，直到所有用户迁移完成 |
| **回滚能力** | 出问题时切回旧版本路径，无需重新部署 |

### 2.3 如果没有 Context Path（单一版本限制）

如果一个服务只暴露一个 endpoint，没有版本路径区分：

```yaml
# VirtualService - 无版本区分
http:
  - match:
      - uri:
          prefix: "/"
    route:
      - destination:
          host: my-service
```

**问题**：

- 所有用户共享同一个版本
- 无法对不同用户展示不同版本
- 新版本发布必须全量切换，有风险
- 无法做 A/B 测试或灰度发布

---

## 3. VirtualService 配置模式

### 3.1 基础版本路由

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-service-vs
  namespace: my-namespace
spec:
  hosts:
    - my-service
    - my-service.my-namespace.svc.cluster.local
  http:
    # V1 版本路由
    - match:
        - uri:
            prefix: "/v1"
      route:
        - destination:
            host: my-service
            subset: v1
            port:
              number: 8080

    # V2 版本路由
    - match:
        - uri:
            prefix: "/v2"
      route:
        - destination:
            host: my-service
            subset: v2
            port:
              number: 8080

    # 默认（无版本，或重定向到最新版本）
    - match:
        - uri:
            prefix: "/"
      route:
        - destination:
            host: my-service
            subset: v1
            port:
              number: 8080
```

**要点**：每个 `prefix` 对应一个 `subset`，Context Path 与 Request Path 一致。

### 3.2 路径嵌套与更细粒度的路由

```yaml
http:
  # V2 版本的不同路径组
  - match:
      - uri:
          prefix: "/v2/users"
    route:
      - destination:
          host: user-service
          subset: v2
          port:
            number: 8080

  - match:
      - uri:
          prefix: "/v2/products"
    route:
      - destination:
          host: product-service
          subset: v2
          port:
            number: 8080

  # 共享的 API 路径（所有版本通用）
  - match:
      - uri:
          prefix: "/health"
    route:
      - destination:
          host: my-service
          subset: v1
          port:
            number: 8080
```

### 3.3 正则匹配（Regex Match）

```yaml
http:
  - match:
      - uri:
          regex: "^/v[0-9]+/.*"
    route:
      - destination:
          host: my-service
          subset: latest
```

**注意**：正则匹配性能略低于前缀匹配，建议对性能敏感路径使用 `prefix`。

---

## 4. DestinationRule：Subset 与版本分组

### 4.1 Subset 定义

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-service-dr
  namespace: my-namespace
spec:
  host: my-service
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
        maxRequestsPerConnection: 100
  subsets:
    - name: v1
      labels:
        version: v1
        app: my-service
    - name: v2
      labels:
        version: v2
        app: my-service
    - name: latest
      labels:
        version: v2
        app: my-service
```

### 4.2 版本标签的来源

Subset 的 `labels` 来自 Kubernetes Pod 的标签：

```yaml
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
```

### 4.3 Subset 间的差异策略

不同 subset 可以有不同的流量策略：

```yaml
subsets:
  - name: v1
    labels:
      version: v1
    trafficPolicy:
      connectionPool:
        tcp:
          maxConnections: 50
  - name: v2
    labels:
      version: v2
    trafficPolicy:
      connectionPool:
        tcp:
          maxConnections: 200
      loadBalancer:
        simple: LEAST_REQUEST
```

---

## 5. 多版本部署策略

### 5.1 蓝绿部署（Blue-Green）

两个版本同时运行，通过 weight 切换流量：

```yaml
http:
  - match:
      - uri:
          prefix: "/v1"
    route:
      - destination:
          host: my-service
          subset: v1
          port:
            number: 8080

  - match:
      - uri:
          prefix: "/v2"
    route:
      - destination:
          host: my-service
          subset: v2
          port:
            number: 8080
```

**特点**：

- V1 和 V2 同时运行
- 用户自主选择版本（用户调用 `/v1/` 或 `/v2/`）
- 运营商可以随时调整流量分配

### 5.2 金丝雀发布（Canary）

将部分流量引导到新版本：

```yaml
http:
  - match:
      - uri:
          prefix: "/v2"
    route:
      - destination:
          host: my-service
          subset: v2
          port:
            number: 8080
        weight: 10  # 10% 流量到 v2
      - destination:
          host: my-service
          subset: v1
          port:
            number: 8080
        weight: 90  # 90% 流量到 v1
```

**注意**：`weight` 是在同一个 route 内的多个 destination 之间分配，而不是按 uri prefix 区分。

### 5.3 基于 Header 的灰度

```yaml
http:
  - match:
      - headers:
          x-version:
            exact: "v2"
      uri:
        prefix: "/"
    route:
      - destination:
          host: my-service
          subset: v2
  - match:
      - uri:
          prefix: "/"
    route:
      - destination:
          host: my-service
          subset: v1
```

用户通过设置 `X-Version: v2` header 来选择版本，而不需要改变 URL。

---

## 6. 服务间调用（Service-to-Service）模式

### 6.1 Pod 内部访问同域名服务的路径

当 Pod 内部需要调用 `www.abc.com/api/health` 时：

| 方式 | 说明 | 推荐度 |
|------|------|--------|
| **直接调用外部域名** | `www.abc.com/api/health` → 公网 → 回流 | ❌ 不推荐 |
| **ServiceEntry 内部映射** | `www.abc.com` → ServiceEntry → 内网 IP | ✅ 推荐 |
| **Kubernetes Service DNS** | `my-svc.ns.svc.cluster.local` | ✅✅ 最佳 |
| **Istio Host 路由** | `my-svc`（通过 VS/DR 解析） | ✅✅ 最佳 |

### 6.2 内部服务调用不应使用 Context Path

**错误示范**：

```yaml
# Pod 内部调用
curl http://www.abc.com/v1/health
```

这会走公网 DNS 解析 + 外部路由，效率低。

**正确示范**：

```yaml
# Pod 内部调用 — 直接用 Service DNS
curl http://my-service.my-namespace.svc.cluster.local/health

# 或通过 ServiceEntry 定义内部 host
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: www-abc-internal
spec:
  hosts:
    - www.abc.com
  location: MESH_INTERNAL
  ports:
    - number: 443
      protocol: HTTPS
  endpoints:
    - address: 10.112.1.100
      ports:
        https: 443
```

### 6.3 Context Path 用于内部服务版本控制

如果内部服务也需要版本控制，可以在 VirtualService 中定义：

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: internal-service-vs
  namespace: my-namespace
spec:
  hosts:
    - internal-service
  http:
    - match:
        - uri:
            prefix: "/v1"
      route:
        - destination:
            host: internal-service
            subset: v1
    - match:
        - uri:
            prefix: "/v2"
      route:
        - destination:
            host: internal-service
            subset: v2
```

这样 Pod 内部也可以调用 `/v1/` 或 `/v2/` 路径来选择版本。

---

## 7. 多租户场景下的 Context Path

### 7.1 每租户独立版本

```yaml
# Tenant A 的服务
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: tenant-a-vs
  namespace: tenant-a
spec:
  hosts:
    - "*.tenant-a.example.com"
  http:
    - match:
        - uri:
            prefix: "/v1"
      route:
        - destination:
            host: tenant-a-service
            subset: v1

# Tenant B 的服务（独立的 v1）
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: tenant-b-vs
  namespace: tenant-b
spec:
  hosts:
    - "*.tenant-b.example.com"
  http:
    - match:
        - uri:
            prefix: "/v1"
      route:
        - destination:
            host: tenant-b-service
            subset: v1
```

**特点**：

- 租户间版本隔离
- 租户可以独立升级，不影响其他租户
- 每个租户的 Context Path 可以是 `/v1/`（各自独立）

### 7.2 统一域名 + 租户路径

```yaml
http:
  - match:
      - uri:
          prefix: "/tenant-a/v1"
    route:
      - destination:
          host: tenant-a-service
          subset: v1

  - match:
      - uri:
          prefix: "/tenant-b/v1"
    route:
      - destination:
          host: tenant-b-service
          subset: v1
```

**注意**：这种模式下，Context Path 变成了 `/{tenant}/{version}` 复合结构，需要确保 VirtualService 的 match 顺序正确。

---

## 8. Context Path 迁移策略

### 8.1 从无版本到有版本

**Step 1**：添加 V1 路径，保留原有默认路由

```yaml
http:
  # 新增 V1 路径
  - match:
      - uri:
          prefix: "/v1"
    route:
      - destination:
          host: my-service
          subset: v1

  # 原有默认路由（渐进式迁移）
  - match:
      - uri:
          prefix: "/"
    route:
      - destination:
          host: my-service
          subset: v1  # 默认也指向 v1
```

**Step 2**：用户逐渐迁移到 `/v1/` 路径

**Step 3**：确认所有用户迁移完成后，删除默认路由

```yaml
http:
  - match:
      - uri:
          prefix: "/v1"
    route:
      - destination:
          host: my-service
          subset: v1
```

### 8.2 从 V1 到 V2

**策略**：双写，两个版本同时支持

```yaml
http:
  - match:
      - uri:
          prefix: "/v1"
    route:
      - destination:
          host: my-service
          subset: v1

  - match:
      - uri:
          prefix: "/v2"
    route:
      - destination:
          host: my-service
          subset: v2
```

用户根据自己的节奏从 `/v1/` 迁移到 `/v2/`，运营商可以监控迁移进度。

### 8.3 废弃（Deprecated）路径

```yaml
http:
  # 标记为 deprecated 的 v1
  - match:
      - uri:
          prefix: "/v1"
    route:
      - destination:
          host: my-service
          subset: v1
    headers:
      response:
        add:
          Deprecation: "true"
          Sunset: "Sat, 31 Dec 2025 23:59:59 GMT"

  # 正常 v2
  - match:
      - uri:
          prefix: "/v2"
    route:
      - destination:
          host: my-service
          subset: v2
```

---

## 9. Context Path 一致性检查清单

在部署前，使用 `trace-istio.sh` 脚本验证：

```bash
# 验证 v1 路径
./trace-istio.sh --url https://my-service.example.com/v1/health

# 验证 v2 路径
./trace-istio.sh --url https://my-service.example.com/v2/health
```

### 检查项

| 检查项 | 说明 |
|--------|------|
| ✅ Context Path 与 Request Path 前缀一致 | VS 的 `prefix` 与客户端请求的 URI 前缀匹配 |
| ✅ 每个 Context Path 对应一个 Subset | `/v1` → subset v1，`/v2` → subset v2 |
| ✅ Pod 标签包含 subset 定义的 labels | `version: v1` 标签在 Pod 上存在 |
| ✅ DestinationRule 包含所有 subset 定义 | DR.spec.subsets 包含 v1, v2 |
| ✅ 内部服务调用使用 cluster.local | 不走外部域名，不绕公网 |
| ✅ 迁移路径已规划 | 旧版本保留足够长时间供迁移 |

### 常见错误

**错误 1：Context Path 与 Request Path 不匹配**

```yaml
# Client 请求 /v1/health
# 但 VS 配置的是 /api 前缀
- match:
    - uri:
        prefix: "/api"  # ❌ 错误：应该是 /v1
```

**错误 2：Subset 标签不匹配**

```yaml
# DestinationRule 定义了 subset v1
subsets:
  - name: v1
    labels:
      version: v1  # 需要这个标签

# 但 Pod 上没有这个标签
# ❌ Pod labels 中没有 version: v1
```

**错误 3：路径优先级问题**

```yaml
http:
  - match:
      - uri:
          prefix: "/v1/users"  # 先匹配这个
    route: ...

  - match:
      - uri:
          prefix: "/v1"  # 后匹配这个
    route: ...

  # ❌ 可能导致 /v1/users 被 /v1 规则先匹配
```

---

## 10. 总结：Context Path 最佳实践

### 10.1 设计原则

| 原则 | 说明 |
|------|------|
| **一致性** | Context Path 必须与 Request Path 一致 |
| **版本化** | Context Path 作为版本标签，让用户自主选择版本 |
| **可演进** | 新版本用新 Context Path，不删除旧版本 |
| **内部不用 Context Path** | Pod 间调用用 Service DNS，不走外部域名 |
| **分层治理** | Gateway 层做入口路由，VirtualService 层做版本分发 |

### 10.2 配置模板

```yaml
# 1. Gateway — 接收外部流量
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: my-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: my-tls-cert
      hosts:
        - "*.example.com"

---
# 2. VirtualService — 版本路由
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-service-vs
  namespace: my-namespace
spec:
  hosts:
    - "*.example.com"
  gateways:
    - istio-system/my-gateway
  http:
    - match:
        - uri:
            prefix: "/v1"
      route:
        - destination:
            host: my-service
            subset: v1
            port:
              number: 8080

    - match:
        - uri:
            prefix: "/v2"
      route:
        - destination:
            host: my-service
            subset: v2
            port:
              number: 8080

---
# 3. DestinationRule — 版本定义
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-service-dr
  namespace: my-namespace
spec:
  host: my-service
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
```

### 10.3 调用方式速查

| 场景 | 调用方式 |
|------|----------|
| 外部用户调用 V1 | `https://api.example.com/v1/health` |
| 外部用户调用 V2 | `https://api.example.com/v2/health` |
| Pod 调用内部服务（推荐） | `http://my-service.ns.svc.cluster.local/health` |
| Pod 调用内部服务（带版本） | `http://my-service.ns.svc.cluster.local/v1/health` |
| Pod 调用同域名外部服务 | 通过 ServiceEntry 映射到内网 IP |

---

## 附录：使用 trace-istio.sh 验证 Context Path 路由

```bash
# 检查 v1 路径是否正确路由到 v1 subset
./trace-istio.sh --url https://my-service.example.com/v1/health

# 检查 v2 路径是否正确路由到 v2 subset
./trace-istio.sh --url https://my-service.example.com/v2/health

# 输出示例
# [1] Gateway istio-system/my-gateway selector: istio=ingressgateway
# [2] VirtualService my-namespace/my-service-vs hosts: *.example.com
# [3] Destination host: my-service subset: v1 port: 8080 weight: 100%
#     DestinationRule: my-namespace/my-service-dr
# [4] Service my-namespace/my-service ClusterIP: 10.96.x.x
#     Ports: 8080/TCP -> 8080
#     Endpoints: 192.168.1.2:pod-v1-xxx, 192.168.1.3:pod-v1-yyy
```

检查 `subset` 列是否与 URL 中的版本路径匹配：
- `/v1/health` → `subset: v1` ✅
- `/v2/health` → `subset: v2` ✅