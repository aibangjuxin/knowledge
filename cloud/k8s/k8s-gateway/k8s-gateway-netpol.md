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
    - [2.2 `default-allow-dns`](#22-default-allow-dns)
    - [2.3 `allow-intra-ns-kong-teamname-int`](#23-allow-intra-ns-kong-teamname-int)
    - [2.4 `allow-intra-ns-ms-teamname-int`](#24-allow-intra-ns-ms-teamname-int)
    - [2.5 `allow-intra-ns-nogateway-teamname`](#25-allow-intra-ns-nogateway-teamname)
    - [2.6 `default-allow-egress-to-drn`](#26-default-allow-egress-to-drn)
    - [2.7 `default-allow-egress-workload-identity`](#27-default-allow-egress-workload-identity)
    - [2.8 `default-allow-gw-ingress-to-no-gw-rt`](#28-default-allow-gw-ingress-to-no-gw-rt)
    - [2.9 `default-allow-kdp-ingress-to-kong-rt`](#29-default-allow-kdp-ingress-to-kong-rt)
    - [2.10 `default-allow-restricted-api`](#210-default-allow-restricted-api)
  - [3. 命名空间标签参考](#3-命名空间标签参考)
  - [4. 验证命令](#4-验证命令)

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
    - to:
        - ipBlock:
            cidr: [IP_ADDRESS]
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
  ingress:
    - from:
        - ipBlock:
            cidr: 35.191.0.0/16
        - ipBlock:
            cidr: 130.211.0.0/22
        - ports:
            - port: 15021
              protocol: TCP
            - port: 443
              protocol: TCP
    podSelector: {}
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
  - ports:
      - port: 443
        protocol: TCP
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: no-gw-rt
    podSelector: {}
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
  ingress:
    - from:
        - ipBlock:
            cidr: 10.0.0.0/8
        - ipBlock:
            cidr: [IP_ADDRESS] # this is our gke node IP range
    podSelector: {}
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

### 2.1 `default-deny-all`

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

### 2.2 `default-allow-dns`

允许 DNS 解析 (UDP/TCP 53)。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-dns
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

### 2.3 `allow-intra-ns-kong-teamname-int`

允许 Kong 相关 Pod 在同一命名空间内通信。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-intra-ns-kong-teamname-int
  namespace: teamname-int
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: kong
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/part-of: kong
  egress:
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/part-of: kong
  policyTypes:
    - Ingress
    - Egress
```

### 2.4 `allow-intra-ns-ms-teamname-int`

允许微服务 (microservice) Pod 在同一命名空间内通信。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-intra-ns-ms-teamname-int
  namespace: teamname-int
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: microservice
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/part-of: microservice
  egress:
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/part-of: microservice
  policyTypes:
    - Ingress
    - Egress
```

### 2.5 `allow-intra-ns-nogateway-teamname`

允许 `teamname` 部署 (NoGateway) Pod 在同一命名空间内通信。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-intra-ns-nogateway-teamname
  namespace: teamname-int
spec:
  podSelector:
    matchLabels:
      app: teamname
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: teamname
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: teamname
  policyTypes:
    - Ingress
    - Egress
```

### 2.6 `default-allow-egress-to-drn`

允许访问 Disaster Recovery Network (DRN) 或外部网络 (RFC 1918 + DRN IP 段)。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-egress-to-drn
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

### 2.8 `default-allow-gw-ingress-to-no-gw-rt`

允许 Gateway 命名空间通过 K8s Gateway 路由到 NoGateway 运行时 (`no-gw-rt`)。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-gw-ingress-to-no-gw-rt
  namespace: teamname-int
spec:
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: abjx-gw-int
  policyTypes:
    - Ingress
```

### 2.9 `default-allow-kdp-ingress-to-kong-rt`

允许 KDP (Kong Data Plane) 命名空间访问 Kong Runtime。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-kdp-ingress-to-kong-rt
  namespace: teamname-int
spec:
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

### 2.10 `default-allow-restricted-api`

允许访问 GCP Restricted API (受限 API 服务端点)。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-allow-restricted-api
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