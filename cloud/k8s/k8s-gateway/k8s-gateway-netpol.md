# K8s Gateway NetworkPolicy — Multi-Tenant Isolation Guide

> 本文档定义 K8s Gateway API 模式下，Gateway Namespace (`abjx-gw-int`) 与 Tenant Namespace (`teamname-int`) 之间的网络隔离规则。
>
> 流量模型：
> ```
> External Client
>     │
>     ▼
> ┌─────────────────────────┐
> │   abjx-gw-int           │  ← Gateway Namespace (Kong + K8s Gateway)
> │   Kong Gateway          │
> └───────────┬─────────────┘
>             │ HTTPRoute → Service
>             ▼
> ┌─────────────────────────┐
> │   teamname-int          │  ← Tenant Namespace (tenant workloads)
> │   Tenant Workloads     │
> └─────────────────────────┘
> ```

---

## 命名总览

### Gateway Namespace (`abjx-gw-int`) — 4 条策略

| 规则名称 | 用途 |
|---|---|
| `default-deny-all` | 零信任底座：拒绝所有未显式放行的流量 |
| `default-allow-ingress-gw` | 允许内网/Node CIDR 入站到网关（SNAT 兼容） |
| `default-allow-kong-gw-rt-intra-ns` | 允许网关访问 Kong Runtime（命名空间级别） |
| `default-allow-none-gw-rt-intra-ns` | 允许网关访问 Non-Gateway 运行时（直连容器） |

### Tenant Namespace (`teamname-int`) — 10 条策略

| 规则名称 | 用途 |
|---|---|
| `default-deny-all` | 零信任底座：拒绝所有未显式放行的流量 |
| `default-allow-egress-dns` | 放行 DNS 解析（UDP/TCP 53 → kube-dns） |
| `default-allow-egress-drn` | 放行 DRN/内网 CIDR 出站 |
| `default-allow-egress-restricted-api` | 放行 GCP Restricted API 端点（199.36.153.4/30） |
| `default-allow-egress-workload-identity` | 放行 Workload Identity 元数据服务（988 端口） |
| `default-allow-ingress-gw` | 允许 Gateway NS 入站 → NONE 容器（直连 API） |
| `default-allow-ingress-int-kdp` | 允许 Kong KDP NS 入站 → KONG 容器（Kong 保护 API） |
| `default-allow-kong-gw-rt-intra-ns` | 允许 KONG 容器同命名空间内互通 |
| `default-allow-intra-ns-ms` | 允许 ms（微服务）容器同命名空间内互通 |
| `default-allow-none-gw-rt-intra-ns` | 允许 NONE 容器同命名空间内互通（只能访问 NONE，禁止访问 KONG） |

---

## 1. Gateway Namespace (`abjx-gw-int`) NetworkPolicies

Gateway 命名空间运行真实的 Envoy 代理，是全集群外部流量的唯一入口。由于 `externalTrafficPolicy: Cluster` 会将下游流量 SNAT 成 Node IP，入站规则必须显式放行 `10.0.0.0/8` 和 GKE Node CIDR `192.168.64.0/19`。

### 1.1 `default-deny-all`

兜底策略。拦截一切未显式放行的入站和出站流量。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: abjx-gw-int
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### 1.2 `default-allow-ingress-gw`

允许内网及 GKE Node CIDR 入站到网关。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-ingress-gw
  namespace: abjx-gw-int
spec:
  podSelector: {}
  ingress:
    - from:
        - ipBlock:
            cidr: 10.0.0.0/8
        - ipBlock:
            cidr: 192.168.64.0/19   # GKE Node CIDR — required for SNAT under externalTrafficPolicy: Cluster
  policyTypes:
    - Ingress
```

### 1.3 `default-allow-kong-gw-rt-intra-ns`

允许网关命名空间访问 Kong Runtime（`kong-apw-kong-int` 命名空间），保障需要 Kong 鉴权的 API 请求能被正常处理。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-kong-gw-rt-intra-ns
  namespace: abjx-gw-int
spec:
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kong-apw-kong-int
      ports:
        - port: 80
          protocol: TCP
        - port: 443
          protocol: TCP
        - port: 8443
          protocol: TCP
  policyTypes:
    - Egress
```

### 1.4 `default-allow-none-gw-rt-intra-ns`

允许网关命名空间访问 Non-Gateway 运行时（`ingress: int` 标签的命名空间），即直连容器的租户命名空间。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-none-gw-rt-intra-ns
  namespace: abjx-gw-int
spec:
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              ingress: int
      ports:
        - port: 443
          protocol: TCP
        - port: 80
          protocol: TCP
  policyTypes:
    - Egress
```

---

## 2. Tenant Namespace (`teamname-int`) NetworkPolicies

### 2.1 `default-deny-all`

兜底策略。一刀切拒绝所有 Pod 的入站和出站流量，任何合法通信必须由下面策略显式放行。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: teamname-int
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### 2.2 `default-allow-egress-dns`

允许 Pod 访问 kube-dns（UDP/TCP 53）。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-egress-dns
  namespace: teamname-int
spec:
  egress:
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
      to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
  policyTypes:
    - Egress
```

### 2.3 `default-allow-egress-drn`

允许访问 Disaster Recovery Network（DRN）及内网 RFC 1918 地址段。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-egress-drn
  namespace: teamname-int
spec:
  egress:
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8
        - ipBlock:
            cidr: 128.0.0.0/2
  policyTypes:
    - Egress
```

### 2.4 `default-allow-egress-restricted-api`

允许访问 GCP Restricted API 服务端点（`199.36.153.4/30`）。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-egress-restricted-api
  namespace: teamname-int
spec:
  egress:
    - ports:
        - port: 443
          protocol: TCP
      to:
        - ipBlock:
            cidr: 199.36.153.4/30
  policyTypes:
    - Egress
```

### 2.5 `default-allow-egress-workload-identity`

允许访问本地元数据服务器（`127.0.0.1`）和 GCP 元数据服务器（`169.254.169.252`）的 988 端口，以支持 GCP Workload Identity 认证。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-egress-workload-identity
  namespace: teamname-int
spec:
  egress:
    - ports:
        - port: 988
          protocol: TCP
      to:
        - ipBlock:
            cidr: 127.0.0.1/32
        - ipBlock:
            cidr: 169.254.169.252/32
  policyTypes:
    - Egress
```

### 2.6 `default-allow-ingress-gw`

允许 Gateway 命名空间（`abjx-gw-int`）的网关 Pod 流量进入本命名空间，并只作用于 `apigateway: NONE` 的直连容器 Pod。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-ingress-gw
  namespace: teamname-int
spec:
  podSelector:
    matchLabels:
      apigateway: NONE
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: abjx-gw-int
  policyTypes:
    - Ingress
```

### 2.7 `default-allow-ingress-int-kdp`

允许 Kong Data Plane 命名空间（`kong-apw-kong-int`）的流量进入本命名空间，并只作用于 `apigateway: KONG` 的 Kong 保护 API Pod（8080/8443 端口）。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-ingress-int-kdp
  namespace: teamname-int
spec:
  podSelector:
    matchLabels:
      apigateway: KONG
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kong-apw-kong-int
      ports:
        - port: 8080
          protocol: TCP
        - port: 8443
          protocol: TCP
  policyTypes:
    - Ingress
```

### 2.8 `default-allow-kong-gw-rt-intra-ns`

允许 `apigateway: KONG` 的 Kong API 容器在同命名空间内互通（接收来自 KONG 和 NONE 容器的请求，发起出站到 KONG 和 NONE 容器）。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-kong-gw-rt-intra-ns
  namespace: teamname-int
spec:
  podSelector:
    matchLabels:
      apigateway: KONG
  ingress:
    - from:
        - podSelector:
            matchLabels:
              apigateway: KONG
  egress:
    - to:
        - podSelector:
            matchLabels:
              apigateway: KONG
    - to:
        - podSelector:
            matchLabels:
              apigateway: NONE
  policyTypes:
    - Ingress
    - Egress
```

### 2.9 `default-allow-intra-ns-ms`

允许 `type: ms` 的微服务容器在同命名空间内与 ms、KONG、NONE 容器互通。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-intra-ns-ms
  namespace: teamname-int
spec:
  podSelector:
    matchLabels:
      type: ms
  ingress:
    - from:
        - podSelector:
            matchLabels:
              type: ms
    - from:
        - podSelector:
            matchLabels:
              apigateway: KONG
    - from:
        - podSelector:
            matchLabels:
              apigateway: NONE
  egress:
    - to:
        - podSelector:
            matchLabels:
              type: ms
    - to:
        - podSelector:
            matchLabels:
              apigateway: KONG
    - to:
        - podSelector:
            matchLabels:
              apigateway: NONE
  policyTypes:
    - Ingress
    - Egress
```

### 2.10 `default-allow-none-gw-rt-intra-ns`

允许 `apigateway: NONE` 的直连 API 容器在同命名空间内互通（接收来自 KONG 和 NONE 容器的请求，出站只能访问 NONE 容器）。禁止 NONE 反向访问 KONG，防止横向越权。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-none-gw-rt-intra-ns
  namespace: teamname-int
spec:
  podSelector:
    matchLabels:
      apigateway: NONE
  ingress:
    - from:
        - podSelector:
            matchLabels:
              apigateway: KONG
    - from:
        - podSelector:
            matchLabels:
              apigateway: NONE
  egress:
    - to:
        - podSelector:
            matchLabels:
              apigateway: NONE
  policyTypes:
    - Ingress
    - Egress
```

---

## 3. 命名空间标签参考

| 命名空间 | 关键标签 | 用途 |
|---------|---------|------|
| `abjx-gw-int` | `kubernetes.io/metadata.name: abjx-gw-int` | Gateway 命名空间 |
| `teamname-int` | `tenant.com/name: teamname` | 租户命名空间 |
| `kong-apw-kong-int` | `kubernetes.io/metadata.name: kong-apw-kong-int` | Kong DP 命名空间 |
| `istio-system` | `kubernetes.io/metadata.name: istio-system` | Istiod 命名空间 |
| `kube-system` | `kubernetes.io/metadata.name: kube-system` | K8s 系统命名空间 |
| `no-gw-rt` | `kubernetes.io/metadata.name: no-gw-rt` | Non-Gateway 运行时 |

---

## 4. 验证命令

```bash
# 查看所有 NetworkPolicy
kubectl get netpol -n abjx-gw-int
kubectl get netpol -n teamname-int

# 查看特定策略的完整 YAML
kubectl get netpol <name> -n <namespace> -o yaml

# 测试网络连通性（从 tenant 命名空间 Pod）
kubectl exec -n teamname-int deploy/<pod> -- curl -v --connect-timeout 5 kube-dns.kube-system:53

# 测试 DNS 解析
kubectl exec -n teamname-int deploy/<pod> -- nslookup kubernetes.default.svc.cluster.local
```

---

## 5. 微隔离标签体系

| 标签 | 值 | 含义 |
|---|---|---|
| `apigateway` | `KONG` | Kong 保护API（需要 Kong DP 鉴权） |
| `apigateway` | `NONE` | 直连 API（无需 Kong，直接由 Gateway 路由） |
| `type` | `ms` | 微服务（允许同命名空间内互通） |
| `ingress` | `int` | Non-Gateway 运行时命名空间标签 |

---

*文档版本: 1.2 — 2026-05-28*