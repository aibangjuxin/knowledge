# Kubernetes Gateway API 深度分析报告

## Multi-Tenant Security via Cross-Namespace Attachment

**分析对象：** Kubernetes Gateway API 核心安全机制  
**编写时间：** 2025-01-XX  
**状态：** Draft

---

## 1. 摘要

Kubernetes Gateway API 是 SIG-NETWORK 社区提出的新一代 Ingress 标准，旨在解决传统 Ingress 对象和自定义 Mesh Ingress Gateway 在多租户场景下的根本性缺陷。其核心理念是通过**角色分离**（Role-Oriented Separation）和**显式路由绑定**（Explicit Route Attachment）实现安全的多租户网络隔离。

---

## 2. Gateway API 三层角色模型

### 2.1 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                    Gateway API Role Model                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐                                           │
│  │  GatewayClass     │  ← Infrastructure Provider Role          │
│  │  (kgateway)       │     Platform Team 专属                    │
│  └────────┬─────────┘                                           │
│           │ defines + implements                                │
│           ▼                                                     │
│  ┌──────────────────┐                                           │
│  │  Gateway         │  ← Cluster Operator Role                  │
│  │  (kgateway-system│     Platform/Network Team                 │
│  │   namespace)     │     控制 IP/TLS/allowedRoutes            │
│  └────────┬─────────┘                                           │
│           │ permits binding                                     │
│           ▼                                                     │
│  ┌──────────────────┐                                           │
│  │  HTTPRoute       │  ← Application Developer Role            │
│  │  (tenant namespace│     Tenant Teams                         │
│  │   e.g., team-a)  │     定义路由规则/路径/Header/Upstream     │
│  └──────────────────┘                                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 各层职责详解

#### Layer 1: GatewayClass（基础设施提供商角色）

| 属性 | 说明 |
|------|------|
| **管理者** | Platform Team |
| **定义内容** | 负载均衡器的模板和控制器实现（如 `kgateway`） |
| **Scope** | Cluster-scoped，但定义的是控制器行为 |
| **数量** | 通常每个集群 1-N 个（如生产级 GKE 可能需要 2 个：internal + external） |

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: kgateway
spec:
  controllerName: "example.com/gateway-controller"
  # 参数引用可选，指向 Infrastructure Provider 的配置
  parametersRef:
    group: example.com
    kind: GatewayParameters
    name: production-config
```

**关键洞察：** GatewayClass 本质上是**对控制器实现的引用**，而非直接配置基础设施。它解决了 "Ingress Class" 语义模糊的问题（传统 Ingress 的 `ingress.class` annotation 仅仅是约定，缺乏约束力）。

---

#### Layer 2: Gateway（集群运营商角色）

| 属性 | 说明 |
|------|------|
| **管理者** | Platform/Network Team |
| **定义内容** | 流量接收位置（公网 IP、TLS 证书）、允许绑定的命名空间 |
| **Scope** | Namespace-scoped，但通常放在 `kgateway-system` 或 `istio-gateways` |
| **核心机制** | `allowedRoutes` 参数控制哪些命名空间的路由可以绑定 |

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: central-gateway
  namespace: kgateway-system
spec:
  gatewayClassName: kgateway
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: wildcard-cert
        allowedRoutes:
          # 关键：显式声明允许绑定路由的命名空间
          namespaces:
            from: Selector
            selector:
              matchLabels:
                tenant: team-a
              matchLabels:
                tenant: team-b
              # 或者用 from: All / from: Same / from: Selector
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchExpressions:
              - key: tenant
                operator: Exists
```

**关键洞察：** Gateway 的 `allowedRoutes` 是**声明式安全边界**——它不是在运行时检查，而是在路由绑定阶段就由网关控制器拒绝非法绑定。

---

#### Layer 3: HTTPRoute / GRPCRoute / TCPRoute（应用开发者角色）

| 属性 | 说明 |
|------|------|
| **管理者** | Tenant Teams（在各自隔离的命名空间内） |
| **定义内容** | 路由规则、路径匹配、Header 匹配、上游 BackendService |
| **Scope** | Namespace-scoped（自身所在命名空间） |
| **绑定方式** | 通过 `parentRefs` 指向上游 Gateway |

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: team-a-routes
  namespace: team-a
  labels:
    tenant: team-a
spec:
  parentRefs:
    # 关键：显式引用目标 Gateway
    - kind: Gateway
      name: central-gateway
      namespace: kgateway-system
      sectionName: https  # 指定 listener
  hostnames:
    - "api.team-a.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /users
        - headers:
            values:
              X-Tenant-ID: team-a
      backendRefs:
        - kind: Service
          name: users-service
          port: 8080
          weight: 100
    - matches:
        - path:
            type: PathPrefix
            value: /orders
      backendRefs:
        - kind: Service
          name: orders-service
          port: 8080
```

---

## 3. 核心安全机制：Cross-Namespace Attachment（跨命名空间绑定）

### 3.1 什么是 Cross-Namespace Attachment？

传统 Ingress 模型的安全缺陷：

```
传统 Ingress 问题：
┌────────────────────────────────────────────────────────────┐
│  传统 Ingress: 每个租户创建自己的 Ingress 对象             │
│  问题 1: 所有租户的路由规则汇聚到同一个 Ingress Controller │
│  问题 2: 没有机制阻止租户 A 定义 host/path 冲突          │
│  问题 3: Annotation 方式定义策略，缺乏类型安全             │
│  问题 4: Namespace 隔离形同虚设（都在同一个 apiserver）   │
└────────────────────────────────────────────────────────────┘
```

Gateway API 的解决方案：

```
Gateway API Cross-Namespace Attachment:
┌────────────────────────────────────────────────────────────────┐
│  Gateway (kgateway-system)                                     │
│  allowedRoutes.namespaces.from = Selector(tenant: team-a, team-b)│
│                                                                │
│  双向握手：                                                     │
│  1. Gateway 显式声明"我允许哪些命名空间绑定路由"              │
│  2. HTTPRoute 显式声明"我引用哪个 Gateway/Listener"           │
│  3. 只有双向都匹配时，绑定才生效                               │
└────────────────────────────────────────────────────────────────┘
```

### 3.2 双向握手机制详解

#### 握手第一步：Gateway 声明允许列表

```yaml
# Gateway 端：kgateway-system/central-gateway
allowedRoutes:
  namespaces:
    from: Selector
    selector:
      matchLabels:
        tenant: team-a
      matchLabels:
        tenant: team-b
```

含义：**"只有 labels 包含 `tenant: team-a` 或 `tenant: team-b` 的命名空间中的 HTTPRoute，才有可能绑定到我的 443 端口"**

#### 握手第二步：HTTPRoute 声明 parentRefs

```yaml
# HTTPRoute 端：team-a/team-a-routes
parentRefs:
  - kind: Gateway
    name: central-gateway
    namespace: kgateway-system
    sectionName: https
```

含义：**"我想绑定到 `kgateway-system/central-gateway` 的 `https` listener"**

#### 握手第三步：Gateway Controller 验证

```
验证逻辑伪代码：
function canAttach(route, gateway, listener):
    # 1. 检查 route 所在 namespace 是否在 gateway.listener.allowedRoutes.namespaces 允许列表中
    if not isNamespaceAllowed(route.namespace, listener.allowedRoutes.namespaces):
        return REJECT("namespace not in allowedRoutes")
    
    # 2. 检查 route 声明的 hostname 是否与 listener.hostname 兼容
    if not isHostnameCompatible(route.hostname, listener.hostname):
        return REJECT("hostname mismatch")
    
    # 3. 检查 route 类型是否为 listener.protocol 支持的类型
    if not isProtocolSupported(route.kind, listener.protocol):
        return REJECT("protocol mismatch")
    
    return ACCEPT
```

### 3.3 攻击场景分析

#### 场景 1：租户 A 尝试劫持租户 B 的路由

```
攻击者：team-a namespace 中的恶意/错误配置的 HTTPRoute
目标：定义 host: "api.team-b.example.com" 拦截 team-b 的流量

结果：
┌────────────────────────────────────────────────────────────────┐
│ Gateway Controller 拒绝理由：                                    │
│ "HTTPRoute team-a/evil-route specifies hostname               │
│  api.team-b.example.com which does not match any allowed       │
│  hostname in parentRefs Gateway kgateway-system/central-gateway"│
│                                                                │
│ 或更早的拒绝：                                                  │
│ "namespace team-a is not in allowedRoutes for listener :443"  │
└────────────────────────────────────────────────────────────────┘
```

#### 场景 2：跨命名空间污染

```
攻击者：team-x namespace（不在 allowedRoutes 中）
目标：创建 HTTPRoute 绑定到 central-gateway

结果：
┌────────────────────────────────────────────────────────────────┐
│ Gateway Controller 拒绝理由：                                   │
│ "Namespace team-x is not in allowedRoutes.namespaces for       │
│  gateway kgateway-system/central-gateway listener :443"        │
└────────────────────────────────────────────────────────────────┘
```

#### 场景 3：协议混淆攻击

```
攻击者：在 HTTPS listener 上尝试绑定 TCPRoute
目标：绕过 TLS 终止，直接代理原始 TCP 流量

结果：
┌────────────────────────────────────────────────────────────────┐
│ Gateway Controller 拒绝理由：                                   │
│ "TCPRoute is not supported for protocol HTTPS"                 │
└────────────────────────────────────────────────────────────────┘
```

### 3.4 与 Istio Sidecar 模式的对比

| 维度 | Gateway API | Istio Sidecar (Ambient/Ztunnel) |
|------|-------------|----------------------------------|
| **安全边界** | Namespace + Route binding | mTLS + AuthorizationPolicy |
| **配置位置** | Gateway (centralized) | Envoy sidecar (per-pod) |
| **策略执行点** | Control plane (Gateway Controller) | Data plane (Envoy) |
| **拒绝时机** | 绑定阶段（早） | 流量阶段（晚） |
| **噪声邻居隔离** | Route-level namespace selector | mTLS authz |
| **复杂度** | 较低（声明式 CRD） | 较高（多组件） |
| **租户可见性** | Gateway 可以查询所有绑定路由 | AuthorizationPolicy 分散 |

**关键区别：**

- **Gateway API**：在控制平面拒绝非法绑定，污染永远不会到达数据平面
- **Istio**：在数据平面拒绝非法流量，如果 AuthorizationPolicy 配置错误，流量可能到达 pod

---

## 4. 多租户安全隔离的深度理解

### 4.1 安全的三个层次

```
┌─────────────────────────────────────────────────────────────────┐
│                    多租户安全层次                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Layer 1: Network Isolation（网络层）                            │
│  ├─ VPC/CNR 网络隔离                                            │
│  ├─ NetworkPolicy（pod 级别）                                   │
│  └─ GKE 的 Workload Identity / Bastion 访问                    │
│                                                                  │
│  Layer 2: Control Plane Security（控制层）                      │
│  ├─ RBAC（谁可以创建 HTTPRoute）                                 │
│  ├─ Gateway allowedRoutes（谁可以绑定到哪个 Gateway）            │
│  └─ GatewayClass controller 验证                                │
│                                                                  │
│  Layer 3: Data Plane Security（数据层）                          │
│  ├─ mTLS（服务间通信加密）                                       │
│  ├─ AuthorizationPolicy（谁可以访问谁）                          │
│  └─ RateLimiting / AuthN plugins                                 │
│                                                                  │
│  Gateway API 主要解决 Layer 2，在 Layer 1 的基础上提供           │
│  细粒度的路由绑定控制                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 为什么 allowedRoutes 比 RBAC 更安全？

```
RBAC 的问题：
┌────────────────────────────────────────────────────────────────┐
│ RBAC: 允许 user/SA 在 namespace X 创建 HTTPRoute               │
│                                                                │
│ 但是：namespace X 中的 HTTPRoute 可能会绑定到错误的 Gateway     │
│ 导致：route 规则被意外附加到错误的入口点                         │
│                                                                │
│ allowedRoutes 的优势：                                         │
│ ├─ Gateway 所有者显式控制"谁可以绑定到我"                       │
│ ├─ 即使 RBAC 被破坏，allowedRoutes 仍然提供保护                │
│ └─ 零信任原则：默认拒绝，按需显式授权                            │
└────────────────────────────────────────────────────────────────┘
```

**结论：** RBAC 控制"谁可以创建资源"，allowedRoutes 控制"创建的资源可以绑定到哪里"。两者正交，共同构成安全体系。

---

## 5. 实际部署拓扑建议

### 5.1 推荐的多租户 Gateway 部署模式

```
生产环境推荐架构：
┌─────────────────────────────────────────────────────────────────┐
│                    production 集群                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │ GatewayClass    │     │ GatewayClass    │                   │
│  │ external-lb     │     │ internal-lb     │                   │
│  │ (公网入口)       │     │ (内网入口)       │                   │
│  └────────┬────────┘     └────────┬────────┘                   │
│           │                        │                             │
│           ▼                        ▼                             │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │ Gateway         │     │ Gateway         │                   │
│  │ public-gw       │     │ internal-gw     │                   │
│  │ (kgateway-sys) │     │ (istio-gateways)│                   │
│  │ allowedRoutes:  │     │ allowedRoutes:  │                   │
│  │  team-a, team-b │     │  team-a, team-b │                   │
│  └────────┬────────┘     └────────┬────────┘                   │
│           │                        │                             │
│           ▼                        ▼                             │
│  ┌─────────────────────────────────────────────────────┐         │
│  │         Tenant Namespaces                           │         │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐        │         │
│  │  │ team-a   │  │ team-b   │  │ team-c   │        │         │
│  │  │ (prod)   │  │ (staging)│  │ (dev)    │        │         │
│  │  └──────────┘  └──────────┘  └──────────┘        │         │
│  └─────────────────────────────────────────────────────┘         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 命名空间标签策略

```yaml
# namespace team-a.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
  labels:
    # 必需：用于 Gateway allowedRoutes 筛选
    tenant: team-a
    # 可选：用于 RBAC / 成本分摊
    cost-center: cc-12345
    environment: production
    # 可选：用于网络策略
    network-isolation: "true"
```

---

## 6. 已知限制与最佳实践

### 6.1 限制

| 限制 | 说明 | 缓解方案 |
|------|------|----------|
| **hostname 冲突** | 如果两个 HTTPRoute 声明相同的 hostname 但属于不同的 Gateway，可能冲突 | 在 Gateway 层统一管理 hostname 分配 |
| **Controller 实现差异** | 不同的 Gateway Controller (Istio, Kong, NGINX) 对 allowedRoutes 的实现可能有细微差别 | 使用 Gateway API conformance 测试验证 |
| **规模限制** | 当 Gateway 上绑定了数千条路由时，controller 性能可能下降 | 考虑按租户分 Gateway 或使用 RouteTable |
| **向后兼容** | 传统 Ingress 资源仍然可用，需要迁移 | 使用 Ingress->HTTPRoute 转换工具 |

### 6.2 最佳实践

```yaml
# 1. Gateway 命名规范
name: {env}-{region}-{purpose}-gateway
# 例：prod-us-central1-external-gateway

# 2. 严格限制 allowedRoutes
allowedRoutes:
  namespaces:
    from: Selector
    selector:
      matchLabels:
        gateway-allowed: "true"
      # 避免使用 from: Same（隐式耦合）

# 3. 每个 listener 使用独立的 allowedRoutes
listeners:
  - name: https-public
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            visibility: public
  - name: https-internal
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            visibility: internal

# 4. HTTPRoute parentRefs 显式指定 sectionName
parentRefs:
  - kind: Gateway
    name: public-gateway
    sectionName: https-public  # 显式指定 listener

# 5. 使用 hostname 约束防止子域名劫持
# Gateway 定义：
hostnames:
  - "*.example.com"  # 通配符域名

# HTTPRoute 定义（租户只能用自己的子域）：
hostnames:
  - "team-a.example.com"  # 必须是 example.com 的子域
```

---

## 7. 总结

### 7.1 核心要点

1. **Gateway API 通过三层角色模型实现了关注点分离**：
   - GatewayClass 由平台团队管理，定义控制器实现
   - Gateway 由网络团队管理，定义入口点和安全边界
   - HTTPRoute 由租户团队管理，定义应用路由

2. **Cross-Namespace Attachment 是核心安全机制**：
   - Gateway 通过 `allowedRoutes` 显式声明允许绑定路由的命名空间
   - HTTPRoute 通过 `parentRefs` 显式声明要绑定的 Gateway
   - 双向握手确保只有授权的路由才能绑定到对应的入口点

3. **安全优势**：
   - 绑定阶段拒绝，比运行时拒绝更早（省资源）
   - 声明式配置，易于审计和版本控制
   - 消除噪声邻居冲突（noisy-neighbor collisions）
   - 消除配置劫持（configuration hijacking）

4. **与 Istio 的关系**：
   - Gateway API 可以作为 Istio 的 Ingress，补充 Ambient/Ztunnel 模式
   - 两者在 Layer 2/3 提供互补的安全能力
   - 推荐：Gateway API 做入口路由，Istio 做服务间 mTLS

### 7.2 适用场景

| 场景 | 推荐方案 |
|------|----------|
| 新建 GKE 集群，多租户 | Gateway API + Istio Ambient |
| 已有 Istio 集群，升级 Ingress | Gateway API 作为 Istio Gateway |
| 单一团队，简单路由 | 传统 Ingress（逐渐迁移） |
| 混合云 / 多集群 | Gateway API（跨集群路由） |

---

## 8. 参考资料

- [Kubernetes Gateway API Official](https://gateway-api.sigs.k8s.io/)
- [GKE Gateway API Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api)
- [Gateway API Security Model](https://gateway-api.sigs.k8s.io/concepts/security-model/)
- [Istio Ambient Mode and Gateway API](https://istio.io/latest/blog/2022/introducing-istio-agent/)
- [Kubernetes Gateway API Conformance Tests](https://gateway-api.sigs.k8s.io/concepts/conformance/)

---

*报告生成工具：Hermes Agent + Claude*  
*文档版本：v1.0*
