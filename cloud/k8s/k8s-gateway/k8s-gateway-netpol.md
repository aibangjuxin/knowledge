- [requirement](#requirement)
  - [flow1: Direct Container Routing](#flow1-direct-container-routing)
  - [Target Traffic Flows](#target-traffic-flows)
- [K8s Gateway NetworkPolicy — Multi-Tenant Isolation Guide](#k8s-gateway-networkpolicy--multi-tenant-isolation-guide)
  - [1. Gateway Namespace (`abjx-gw-int`) NetworkPolicies](#1-gateway-namespace-abjx-gw-int-networkpolicies)
    - [1.1 `default-deny-all`](#11-default-deny-all)
    - [1.2 `default-allow-dns`](#12-default-allow-dns)
    - [1.3 `default-allow-gcp-hc-ingress`](#13-default-allow-gcp-hc-ingress)
    - [1.4 `default-allow-gw-egress-to-kong`](#14-default-allow-gw-egress-to-kong)
    - [1.5 `default-allow-gw-to-no-gw-rt`](#15-default-allow-gw-to-no-gw-rt)
    - [1.6 `default-allow-nginx-ingress-to-gw`](#16-default-allow-nginx-ingress-to-gw)
    - [1.7 `default-allow-istiod`](#17-default-allow-istiod)
  - [2. Tenant Namespace (`teamname-int`) NetworkPolicies](#2-tenant-namespace-teamname-int-networkpolicies)
    - [2.1 `default-deny-all`](#21-default-deny-all)
    - [2.2 `default-allow-egress-dns`](#22-default-allow-egress-dns)
    - [2.3 `default-allow-kong-gw-rt-intra-ns`](#23-default-allow-kong-gw-rt-intra-ns)
    - [2.4 `default-allow-intra-ns-ms`](#24-default-allow-intra-ns-ms)
    - [2.5 `default-allow-none-gw-rt-intra-ns`](#25-default-allow-none-gw-rt-intra-ns)
    - [2.6 `default-allow-egress-drn`](#26-default-allow-egress-drn)
    - [2.7 `default-allow-egress-workload-identity`](#27-default-allow-egress-workload-identity)
    - [2.8 `default-allow-ingress-gw`](#28-default-allow-ingress-gw)
    - [2.9 `default-allow-ingress-int-kdp`](#29-default-allow-ingress-int-kdp)
    - [2.10 `default-allow-egress-restricted-api`](#210-default-allow-egress-restricted-api)
  - [3. 命名空间标签参考](#3-命名空间标签参考)
  - [4. 验证命令](#4-验证命令)
# requirement 
## flow1: Direct Container Routing

Client (ILB) -> abjx-gw-int (Gateway Pod) -> abjx-listenerset-int (无 Pod，仅做配置绑定) -> teamname-int 等 (Tenant Runtime Pod)

## Target Traffic Flows

Flow 1: Direct Container Routing
Client -> Gateway (abjx-gw-int) -> HTTPRoute (teamname-int) -> Direct Container Pod (teamname-int)
• Source: Platform Gateway (abjx-gw-int)
• Destination: Pods labeled as Direct Containers.

Flow 2: Kong DP Routing
Client -> Gateway (abjx-gw-int) -> HTTPRoute (teamname-int) -> Kong DP (abjx-int-kdp) -> Kong API Pod (teamname-int)
• Source: Kong DP (abjx-int-kdp)
• Destination: Pods labeled as Kong APIs.

Flow 3: 我们的用户流量应该是这样的。

Clients -> Gateway (abjx-gw-int) -> ajbx-listenerset-int (无 Pod，仅做配置绑定) -> teamname-int 等 (Tenant Runtime Pod)

对于teamname-int 命名空间，里面存在两种情况，一种就是直接访问容器，一种就是访问kong的api。如果是访问空DP的API的话，那么它最终还是要回到这个
teamname-int Namespace里面运行的Pod 但是这个Pod 是KongAPI的





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

## 1. Gateway Namespace (`abjx-gw-int`) NetworkPolicies

以下是网关命名空间 (abjx-gw-int) 下所有 7 条 NetworkPolicy 的功能总结。
该命名空间运行着真实的 Envoy 代理，它是全集群所有外部流量的唯一入口。
1. 零信任基线底座 (Zero-Trust Baseline)
• default-deny-all: 兜底策略。拦截一切未显式放行的出站和入站流量，防止网关被攻破后成为跳板。
• default-allow-iip-ingress-to-gw: 允许爱帮内部网段 (IIP) 请求进入网关。[已修复隐藏 Bug] 之前该规则遗漏了 GKE Node CIDR (192.168.64.0/19)。由于网关 ILB使用了 externalTrafficPolicy: Cluster，所有来自下游 Nginx 的流量在达到网关 Pod 时都会被 SNAT（源地址转换）成 Node IP。必须放行 Node CIDR 才能防止流量被底层的 Default Deny 默默丢弃（导致 504 Gateway Timeout）。
• default-allow-gcp-hc-ingress: 【必不可少】专门放行 GCP 内部负载均衡器 (ILB) 的健康检查探针网段 (130.211.0.0/22, 35.191.0.0/16) 访问 Envoy 的 15021 及 443 端口。如果不放行，GCP 会将所有 Envoy 节点标记为宕机并切断外部流量。
• default-allow-dns: 【必不可少】允许 Envoy 访问 kube-system 进行 DNS 解析 (53 端口)。网关在启动和计算路由时高度依赖 DNS，不放行会导致 Envoy 容器直接崩溃。
• default-allow-istiod: 【必不可少】


• default-allow-istiod: [必不可少]允许 Envoy 访问 istio-system 的15012 端口。网关作为数据面，必须实时连接到控制面 (istiod) 才能拉取租户下发的路由规则 (xDS 协议)。
• default-allow-gw-egress-to-kong: [核心隔离] 精准允许网关将流量发送到 Kong 数据面(kubernetes.io/metadata.name:cap-int-kdp)，保障那些需要鉴权的 API 请求能够正常交由 Kong处理。
• default-allow-gw-to-no-gw-rt:【核心隔离】精准允许网关直接将流量发送给带有 ingress: int 标签的内部租户空间（普通直连 API 请求），从而实现了网关的最小化出站放行



### 1.1 `default-deny-all`

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

### 1.2 `default-allow-dns`

允许 DNS 解析 (UDP/TCP 53)。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-dns
  namespace: abjx-gw-int
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

### 1.3 `default-allow-gcp-hc-ingress`

允许 GCP LoadBalancer 健康检查 (GCP IP 段)。

> **注意**：GCP HTTP(S)/TCP/SSL LB 健康检查探针来自以下两个固定 IP 段：
> - `35.191.0.0/16`
> - `130.211.0.0/22`
>
> `199.36.153.4/30` 是 GCP **Restricted API** 端点地址，不是健康检查 IP，应写在 `default-allow-restricted-api` 策略里（见第 2.10 节）。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-gcp-hc-ingress
  namespace: abjx-gw-int
spec:
  podSelector: {}
  ingress:
    - from:
        - ipBlock:
            cidr: 35.191.0.0/16
        - ipBlock:
            cidr: 130.211.0.0/22
      ports:
        - port: 15021
          protocol: TCP
        - port: 443
          protocol: TCP
  policyTypes:
    - Ingress
```

### 1.4 `default-allow-gw-egress-to-kong`

允许 Gateway 命名空间访问 Kong DP (Kong Data Plane) 命名空间。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-gw-egress-to-kong
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

### 1.5 `default-allow-gw-to-no-gw-rt`

允许 Gateway 命名空间访问非 Gateway 运行时命名空间 (`no-gw-rt`)。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-gw-to-no-gw-rt
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

### 1.6 `default-allow-nginx-ingress-to-gw`

允许内部 IP (nginx) 段进入 Gateway 命名空间。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-nginx-ingress-to-gw
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

### 1.7 `default-allow-istiod`

允许 Gateway 命名空间访问 Istiod (istio-system)。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-istiod
  namespace: abjx-gw-int
spec:
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
          podSelector:
            matchLabels:
              app: istiod
      ports:
        - port: 15012
          protocol: TCP
        - port: 15010
          protocol: TCP
  policyTypes:
    - Egress
```

---

## 2. Tenant Namespace (`teamname-int`) NetworkPolicies

1. 零信任基线底座 (Zero-Trust Baseline)
• default-deny-all: 兜底策略。一刀切拒绝该命名空间内所有 Pod 的一切入站 (Ingress) 和出站 (Egress) 流量。任何合法的通信都必须由下面的策略显式放行。

2. 核心基础设施放行 (Infrastructure Egress)
• default-allow-egress-dns: 允许 Pod 发送 UDP/TCP 53 端口流量到 kube-system 的 kube-dns，以保障域名解析正常工作。
• default-allow-egress-workload-identity: 允许访问本地和 GCP 元数据服务器的 988 端口，以支持 GCP 的 Workload Identity 原生身份认证。
• default-allow-egress-restricted-api: 允许访问 Google Restricted API 的专用 IP 块。
• default-allow-egress-drn: 允许访问特定的内网及爱帮内部网络 (DRN) 的大段 CIDR。

3. 跨命名空间入口白名单 (Cross-Namespace Ingress)
• default-allow-ingress-gw: 专门允许来自 abjx-gw-int 命名空间中 abjx-gw-int 网关 Pod 的流量，直接访问本命名空间里不需要 Kong 保护的普通容器 (apigateway: NONE)。
• default-allow-ingress-int-kdp: 专门允许来自 Kong 数据面 (kdp: cap-int-kdp 标签的 Pod) 的流量，打入本命名空间里受 Kong 保护的 API 容器 (apigateway: KONG)。
4. 命名空间内部微隔离与防越权 (Intra-NS Micro-segmentation)
• default-allow-kong-gw-rt-intra-ns: 作用于 Kong API 容器 (apigateway: KONG)。允许它接收同类容器的请求；并允许它发起出站请求，调用同类的 Kong 容器以及普通的 Container 容器 (apigateway: NONE)。
• default-allow-none-gw-rt-intra-ns: 作用于 普通 API 容器 (apigateway: NONE)。允许它接收 Kong API 容器发来的请求；但它的出站规则被严格限制为只能访问其他普通容器，绝对物理隔离、无法反向去访问高权限的 Kong 容器。这完美阻断了潜在的横向越权攻击。
• default-allow-intra-ns-ms: 【新增】作用于 微服务容器 (type: ms)。允许它接收来自同类 ms、KONG 以及 NONE 容器的请求；出站方向也允许访问这三类容器，实现了租户内微服务逻辑层的受控互通。

### 2.1 `default-deny-all`

| 名称 | 说明 |
|------|------|
| `default-deny-all` | 兜底策略。一刀切拒绝该命名空间内所有 Pod 的一切入站 (Ingress) 和出站 (Egress) 流量。任何合法的通信都必须由下面的策略显式放行。 |
| `default-allow-egress-dns` | 允许 Pod 发送 UDP/TCP 53 端口流量到 kube-system 的 kube-dns，以保障域名解析正常工作。 |
| `default-allow-kong-gw-rt-intra-ns` | 作用于 Kong API 容器 (apigateway: KONG)。允许它接收同类容器的请求；并允许它发起出站请求，调用同类的 Kong 容器以及普通的 Container 容器 (apigateway: NONE)。 |
| `default-allow-intra-ns-ms` | 作用于 微服务容器 (type: ms)。允许它接收来自同类 ms、KONG 以及 NONE 容器的请求；出站方向也允许访问这三类容器，实现了租户内微服务逻辑层的受控互通。 |
| `default-allow-none-gw-rt-intra-ns` | 作用于 普通 API 容器 (apigateway: NONE)。允许它接收 Kong API 容器发来的请求；但它的出站规则被严格限制为只能访问其他普通容器，绝对物理隔离、无法反向去访问高权限的 Kong 容器。这完美阻断了潜在的横向越权攻击。 |
| `default-allow-egress-drn` | 允许访问 Disaster Recovery Network (DRN) 或外部网络 (RFC 1918 + DRN IP 段)。 |
| `default-allow-egress-workload-identity` | 允许访问本地和 GCP 元数据服务器的 988 端口，以支持 GCP 的 Workload Identity 原生身份认证。 |
| `default-allow-ingress-gw` | 专门允许来自 abjx-gw-int 命名空间中 abjx-gw-int 网关 Pod 的流量，直接访问本命名空间里不需要 Kong 保护的普通容器 (apigateway: NONE)。 |
| `default-allow-ingress-int-kdp` | 专门允许来自 Kong 数据面 (kdp: cap-int-kdp 标签的 Pod) 的流量，打入本命名空间里受 Kong 保护的 API 容器 (apigateway: KONG)。 |
| `default-allow-egress-restricted-api` | 允许访问 Google Restricted API 的专用 IP 块 (199.36.153.4/30)。 |

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

允许 DNS 解析 (UDP/TCP 53)。

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

### 2.3 `default-allow-kong-gw-rt-intra-ns`

允许 Kong 相关 Pod 在同一命名空间内通信。

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

### 2.4 `default-allow-intra-ns-ms`

允许微服务 (type: ms) Pod 与同命名空间内的 ms、KONG、NONE 容器互通。

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

### 2.5 `default-allow-none-gw-rt-intra-ns`

允许普通 API (NoGateway) Pod 在同一命名空间内通信，并接收来自 Kong 容器的请求，但禁止反向访问 Kong 容器（防横向越权）。

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

### 2.6 `default-allow-egress-drn`

允许访问 Disaster Recovery Network (DRN) 或外部网络 (RFC 1918 + DRN IP 段)。

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

### 2.7 `default-allow-egress-workload-identity`

允许 Workload Identity (GKE 元数据服务) 访问。

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

### 2.8 `default-allow-ingress-gw`

允许 Gateway 命名空间通过 K8s Gateway 路由到 NoGateway 运行时 (`no-gw-rt`)。

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

### 2.9 `default-allow-ingress-int-kdp`

允许 KDP (Kong Data Plane) 命名空间访问 Kong Runtime。

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

### 2.10 `default-allow-egress-restricted-api`

允许访问 GCP Restricted API (受限 API 服务端点)。

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

---

## 3. 命名空间标签参考

| 命名空间 | 关键标签 | 用途 |
|---------|---------|------|
| `abjx-gw-int` | `kubernetes.io/metadata.name: abjx-gw-int` | Gateway 命名空间 |
| `teamname-int` | `tenant.com/name: teamname` | 租户命名空间 |
| `kong-apw-kong-int` | `kubernetes.io/metadata.name: kong-apw-kong-int` | Kong DP 命名空间 |
| `istio-system` | `kubernetes.io/metadata.name: istio-system` | Istiod 命名空间 |
| `kube-system` | `kubernetes.io/metadata.name: kube-system` | K8s 系统命名空间 |
| `no-gw-rt` | `kubernetes.io/metadata.name: no-gw-rt` | 非 Gateway 运行时 |

---

## 4. 验证命令

```bash
# 查看所有 NetworkPolicy
kubectl get netpol -n abjx-gw-int
kubectl get netpol -n teamname-int

# 查看特定策略的完整 YAML
kubectl get netpol <name> -n <namespace> -o yaml

# 测试网络连通性 (从 tenant 命名空间 Pod)
kubectl exec -n teamname-int deploy/<pod> -- curl -v --connect-timeout 5 kube-dns.kube-system:53

# 查看 istiod 访问日志
kubectl logs -n istio-system istiod-* --tail=20 | grep -i networkpolicy
```

---

*文档版本: 1.1 — 2026-05-25*