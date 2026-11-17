# ListenerSet 多租户配置指南

> 基于 [Gateway API ListenerSet 官方文档](https://gateway-api.sigs.k8s.io/guides/user-guides/listener-set/) 深度探索

---

## 1. 背景与动机

### 1.1 传统 Gateway 的局限性

Kubernetes Gateway API 标准中，`Gateway` 资源的 `listeners` 字段**最多支持 64 个 listener**。在多租户场景下，这很快会成为瓶颈：

| 场景 | 问题 |
|------|------|
| 每个租户需要独立端口/TLS 证书 | 64 个租户上限 |
| 不同租户不同域名 | listener 数量爆炸 |
| 租户需要动态添加 | 需要改 Gateway 资源，引发冲突 |

### 1.2 ListenerSet 如何解决

ListenerSet 是 Gateway API 的**扩展支持功能**，它允许：

- 将端口、主机名、TLS 证书的定义**从 Gateway 分离**到独立资源
- **突破 64 listener 限制**
- 实现**委托管理模式**：各团队管理自己的 ListenerSet，共享同一个 Gateway

---

## 2. 核心概念

### 2.1 资源层次

```
Gateway (shared namespace)
    │
    ├── ListenerSet (team1 namespace)
    │       └── HTTPRoute (team1 namespace)
    │               └── Service (team1 namespace)
    │
    ├── ListenerSet (team2 namespace)
    │       └── HTTPRoute (team2 namespace)
    │               └── Service (team2 namespace)
    │
    └── ListenerSet (teamN namespace)
            └── HTTPRoute (teamN namespace)
                    └── Service (teamN namespace)
```

### 2.2 关键字段说明

| 字段 | Gateway | ListenerSet | 说明 |
|------|---------|-------------|------|
| `spec.listeners` | ✅ 直接定义 | ❌ 通过 parentRef 引用 | ListenerSet 本身不直接定义 listeners |
| `spec.allowedListeners` | ✅ 控制哪些 ListenerSet 可以绑定 | N/A | 命名空间级别控制 |
| `spec.parentRef` | N/A | ✅ 指向 Gateway | ListenerSet 绑定到哪个 Gateway |
| `parentRefs` in HTTPRoute | ✅ 直接引用 | ✅ 引用 ListenerSet | HTTPRoute 引用 ListenerSet 而非 Gateway |

### 2.3 ListenerSet vs Gateway listeners

| 特性 | Gateway listeners | ListenerSet |
|------|------------------|-------------|
| 数量限制 | 64 | **无限制** |
| 命名空间 | 与 Gateway 同命名空间 | **任意命名空间**（受 allowedListeners 控制） |
| 管理权限 | 平台团队 | **各租户团队** |
| TLS 证书 | Gateway 统一管理 | **租户自己管理** |
| 冲突解决 | 固定优先级 | 按创建时间 + 字母序 |

---

## 3. 架构设计

### 3.1 多租户命名空间规划

```
┌─────────────────────────────────────────────────────────────────┐
│  infrastructure namespace (平台团队管理)                          │
│  └── gateway/shared-gateway                                      │
│      ├── allowedListeners: 允许 team1, team2, team3... 命名空间   │
│      └── 绑定到 istio-ingressgateway 或 ASM Managed Gateway      │
└─────────────────────────────────────────────────────────────────┘
           ▲
           │ parentRef
    ┌──────┴──────┬─────────────────┬─────────────────┐
    │            │                 │                 │
    ▼            ▼                 ▼                 ▼
┌─────────┐  ┌─────────┐     ┌─────────┐       ┌─────────┐
│ team1   │  │ team2   │     │ team3   │       │ teamN   │
│namespace│  │namespace│     │namespace│       │namespace│
│         │  │         │     │         │       │         │
│ListenerSet│ │ListenerSet│   │ListenerSet│     │ListenerSet│
│HTTPRoute │  │HTTPRoute │   │HTTPRoute │     │HTTPRoute │
│Service   │  │Service   │   │Service   │       │Service   │
└─────────┘  └─────────┘     └─────────┘       └─────────┘
```

### 3.2 流量模型

```
Client HTTPS 请求
    │
    │  *.tenant1.example.com
    │  *.tenant2.example.com
    │  ...
    ▼
┌─────────────────────────────────────────┐
│         Shared Gateway                  │
│  (infrastructure namespace)             │
│  istio-ingressgateway / ASM Gateway     │
│                                         │
│  - 共享端口 443                         │
│  - TLS termination (per ListenerSet)   │
│  - SNI-based routing → ListenerSet      │
└──────────────────┬──────────────────────┘
                   │ HTTPRoute → ListenerSet
                   ▼
         ┌─────────────────┐
         │  Tenant Service  │
         │  (各团队命名空间) │
         └─────────────────┘
```

---

## 4. 完整配置示例

### 4.1 环境信息

| 项目 | 值 |
|------|-----|
| Istio 版本 | 1.29.2 |
| GatewayClass | istio |
| 共享 Gateway 命名空间 | `infrastructure` |
| 租户命名空间 | `team1`, `team2`, `team3` |
| 入口域名 | `*.tenant{1,2,3}.example.com` |

### 4.2 目录结构

```
infrastructure/
└── gateway.yaml          # 共享 Gateway 配置

team1/
├── listenerset.yaml      # Team1 的 ListenerSet
├── httproute.yaml        # Team1 的 HTTPRoute
└── destinationrule.yaml  # Team1 的 DestinationRule (可选)

team2/
├── listenerset.yaml      # Team2 的 ListenerSet
├── httproute.yaml        # Team2 的 HTTPRoute
└── destinationrule.yaml  # Team2 的 DestinationRule (可选)

team3/
└── ... (同上)
```

---

## 5. 配置清单

### 5.1 前提条件：部署 Istio Ingress Gateway

> **注意**：你的环境中只有 istiod，没有 ingressgateway。ListenerSet 需要有数据面处理流量。

```bash
# 方式 A: 使用 istioctl 安装默认 profile (包含 ingressgateway)
istioctl install --set profile=default

# 方式 B: 单独安装 ingressgateway (Helm)
helm install istio-ingressgateway istio/gateway -n istio-system

# 方式 C: 使用 ASM/ambient 模式
istioctl install --set profile=ambient
```

### 5.2 GatewayClass 检查

```bash
kubectl get gatewayclass
```

期望输出：
```
NAME    CONTROLLER              AGE
istio   asm/ingressgateway      10d
```

### 5.3 共享 Gateway 配置 (infrastructure namespace)

```yaml
# infrastructure/gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: infrastructure
  annotations:
    # 说明：这是共享 Gateway，由平台团队管理
    gateway.beta.mesh.com/managed-by: platform-team
spec:
  gatewayClassName: istio
  # 允许以下命名空间的 ListenerSet 绑定到此 Gateway
  allowedListeners:
    - namespaces:
        from: Selector
        selector:
          matchLabels:
            gateway.tenant.com/allowed: "true"
  # 注意：这里不直接定义任何 listener！
  # 所有 listener 由 ListenerSet 提供
  listeners:
    # 可以预定义一个默认 listener 用于 ACME HTTP-01 验证等
    - name: http-redirect
      port: 80
      protocol: HTTP
      hostname: "*"
      allowedRoutes:
        namespaces:
          from: Same
```

### 5.4 Team1 配置

#### 4.4.1 租户命名空间 (带标签)

```yaml
# team1/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team1
  labels:
    gateway.tenant.com/allowed: "true"    # 与 Gateway allowedListeners selector 匹配
    tenant.com/name: team1
```

#### 4.4.2 ListenerSet

```yaml
# team1/listenerset.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ListenerSet
metadata:
  name: team1-listeners
  namespace: team1
  labels:
    tenant.com/name: team1
spec:
  # 引用共享 Gateway
  parentRef:
    name: shared-gateway
    namespace: infrastructure
    kind: Gateway
    group: gateway.networking.k8s.io
  # 定义 Team1 专用的 listeners
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "*.team1.example.com"
      tls:
        mode: Terminate
        certificateRefs:
          - name: team1-tls-cert
            namespace: team1
      # 允许 team1 内的 HTTPRoute 绑定
      allowedRoutes:
        namespaces:
          from: Same
    - name: grpc
      port: 8443
      protocol: HTTPS
      hostname: "*.team1.example.com"
      tls:
        mode: Terminate
        certificateRefs:
          - name: team1-tls-cert
            namespace: team1
      allowedRoutes:
        namespaces:
          from: Same
```

#### 4.4.3 HTTPRoute

```yaml
# team1/httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: team1-app-route
  namespace: team1
spec:
  # 引用 ListenerSet，不是直接引用 Gateway
  parentRefs:
    - name: team1-listeners
      kind: ListenerSet
      group: gateway.networking.k8s.io
      sectionName: https
  hostnames:
    - "app.team1.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: X-Tenant
                value: team1
      backendRefs:
        - name: team1-app-service
          port: 8080
    - backendRefs:
        - name: team1-app-service
          port: 8080
```

#### 4.4.4 DestinationRule (可选，用于 mTLS)

```yaml
# team1/destinationrule.yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team1-app-dr
  namespace: team1
spec:
  host: team1-app-service.team1.svc.cluster.local
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 8080
        tls:
          mode: SIMPLE
          # 如果后端服务启用 mTLS，改为 MUTUAL
```

### 5.5 Team2 配置

#### 4.5.1 命名空间

```yaml
# team2/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team2
  labels:
    gateway.tenant.com/allowed: "true"
    tenant.com/name: team2
```

#### 4.5.2 ListenerSet

```yaml
# team2/listenerset.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ListenerSet
metadata:
  name: team2-listeners
  namespace: team2
  labels:
    tenant.com/name: team2
spec:
  parentRef:
    name: shared-gateway
    namespace: infrastructure
    kind: Gateway
    group: gateway.networking.k8s.io
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "*.team2.example.com"
      tls:
        mode: Terminate
        certificateRefs:
          - name: team2-tls-cert
            namespace: team2
      allowedRoutes:
        namespaces:
          from: Same
```

#### 4.5.3 HTTPRoute

```yaml
# team2/httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: team2-app-route
  namespace: team2
spec:
  parentRefs:
    - name: team2-listeners
      kind: ListenerSet
      group: gateway.networking.k8s.io
      sectionName: https
  hostnames:
    - "api.team2.example.com"
  rules:
    - backendRefs:
        - name: team2-api-service
          port: 8080
```

---

## 6. 部署步骤

### 6.1 部署顺序

```bash
# 1. 创建平台侧资源
kubectl apply -f infrastructure/gateway.yaml

# 2. 创建所有租户命名空间
kubectl apply -f team1/namespace.yaml
kubectl apply -f team2/namespace.yaml

# 3. 创建租户 TLS Secret (需要先创建证书)
kubectl create secret tls team1-tls-cert \
  --cert=tls.crt --key=tls.key -n team1
kubectl create secret tls team2-tls-cert \
  --cert=tls.crt --key=tls.key -n team2

# 4. 创建 ListenerSet
kubectl apply -f team1/listenerset.yaml
kubectl apply -f team2/listenerset.yaml

# 5. 创建 HTTPRoute
kubectl apply -f team1/httproute.yaml
kubectl apply -f team2/httproute.yaml

# 6. 创建 DestinationRule (可选)
kubectl apply -f team1/destinationrule.yaml
kubectl apply -f team2/destinationrule.yaml
```

### 6.2 验证

```bash
# 检查 Gateway 状态
kubectl get gateway -n infrastructure

# 检查 ListenerSet 绑定状态
kubectl get listenerset -A

# 检查 HTTPRoute 状态
kubectl get httproute -A

# 查看 istiod 日志确认配置下发
kubectl logs -n istio-system istiod-* --tail=50 | grep -i listener
```

### 6.3 预期输出

```bash
$ kubectl get gateway,listenerset,httproute -A

NAMESPACE       NAME                                 CLASS   ADDRESS         PROGRAMMED   AGE
infrastructure  gateway.gateway.networking.k8s.io/shared-gateway   istio   10.0.0.100    True         30d

NAMESPACE       NAME                                 PARENT           STATUS     ACCEPTED   AGE
team1          listenerset.gateway.networking.k8s.io/team1-listeners   shared-gateway   Bound     True       7d
team2          listenerset.gateway.networking.k8s.io/team2-listeners   shared-gateway   Bound     True       7d

NAMESPACE       NAME                                       HOSTNAMES                      STATUS     AGE
team1          httproute.gateway.networking.k8s.io/team1-app-route   [app.team1.example.com]      Accepted   7d
team2          httproute.gateway.networking.k8s.io/team2-app-route   [api.team2.example.com]      Accepted   7d
```

---

## 7. 冲突解决规则

当多个 ListenerSet 定义了相同的 (Port, Protocol, Hostname) 组合时：

| 优先级 | 规则 |
|--------|------|
| 1 | Gateway 直接定义的 listener 优先于所有 ListenerSet |
| 2 | ListenerSet 创建时间更早的优先 |
| 3 | ListenerSet 名字字母序更早的优先 |

**示例**：

```yaml
# ListenerSet A (创建于 2026-01-01)
# ListenerSet B (创建于 2026-01-02)
# 如果两者都定义了 port=443, hostname="app.example.com"
# → ListenerSet A 生效，B 被标记为 Conflicted: true
```

```bash
# 检查冲突
kubectl get listenerset -n team2 -o yaml | grep -A5 status
```

---

## 8. 规模估算

### 8.1 资源消耗预估

| Gateway 数量 | ListenerSet 数量 | istiod 内存增幅 | Envoy 配置增幅 |
|-------------|-----------------|----------------|----------------|
| 1 | 50 | ~50MB | ~2MB |
| 1 | 200 | ~200MB | ~8MB |
| 1 | 500 | ~500MB | ~20MB |
| 5 | 200 each | ~1GB | ~40MB |

### 8.2 你的场景 (200 个目标)

| 资源 | 建议 |
|------|------|
| istiod 内存 | 建议 4GB+ (当前 2 cores CPU，内存未确认) |
| ingressgateway | 建议 HPA 或 VPA，根据流量自动扩缩容 |
| 每个 ListenerSet 的 listeners 数量 | 建议 1-3 个，避免单个 ListenerSet 过于庞大 |

---

## 9. 注意事项

### 9.1 Istio 版本兼容性

ListenerSet 是 Gateway API 的 **Extended Support** 功能，不是所有实现都支持：

```bash
# 检查你的 GatewayClass 支持的功能
kubectl get gatewayclass istio -o yaml | grep -i features
```

### 9.2 数据面缺失问题

你的环境目前**只有 istiod，没有 ingressgateway**。在使用 ListenerSet 之前，必须先部署数据面：

```bash
# 检查是否存在任何 ingressgateway
kubectl get pods -A | grep -E 'ingress|ztunnel'

# 如果没有，需要安装
istioctl install --set profile=default
```

### 9.3 TLS 证书管理

每个 ListenerSet 引用的证书 Secret 必须在 **ListenerSet 同一命名空间**内：

```yaml
spec:
  listeners:
    - tls:
        certificateRefs:
          - name: my-cert
            namespace: team1  # ← 必须与 ListenerSet 同命名空间
```

---

## 10. 快速参考

### 10.1 核心命令

```bash
# 查看 Gateway 及其允许的 ListenerSet
kubectl get gateway -n infrastructure -o wide

# 查看所有 ListenerSet
kubectl get listenerset -A

# 查看 HTTPRoute 与 ListenerSet 的绑定关系
kubectl get httproute -A -o custom-columns='NAME:.metadata.name,NS:.metadata.namespace,PARENT_REF:.spec.parentRefs[0].name'

# 触发 istiod 重新推送配置
kubectl rollout restart deployment istiod -n istio-system

# 查看 Envoy 配置
istioctl proxy-config listener <ingressgateway-pod> -n istio-system
```

### 10.2 ListenerSet 模板 (可直接使用)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ListenerSet
metadata:
  name: <TENANT>-listeners
  namespace: <TENANT>
spec:
  parentRef:
    name: shared-gateway
    namespace: infrastructure
    kind: Gateway
    group: gateway.networking.k8s.io
  listeners:
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "*.${TENANT}.example.com"
      tls:
        mode: Terminate
        certificateRefs:
          - name: ${TENANT}-tls-cert
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${TENANT}-default-route
  namespace: ${TENANT}
spec:
  parentRefs:
    - name: ${TENANT}-listeners
      kind: ListenerSet
      group: gateway.networking.k8s.io
      sectionName: https
  hostnames:
    - "*.${TENANT}.example.com"
  rules:
    - backendRefs:
        - name: ${TENANT}-service
          port: 8080
```

---

## 11. 参考链接

- [Gateway API ListenerSet 官方文档](https://gateway-api.sigs.k8s.io/guides/user-guides/listener-set/)
- [Gateway API 跨命名空间路由](https://gateway-api.sigs.k8s.io/guides/user-guides/multiple-ns/)
- [Istio Gateway API 支持](https://istio.io/latest/docs/setup/additional-setup/gateway/)

---

*文档版本: 1.0 — 2026-01-19*
