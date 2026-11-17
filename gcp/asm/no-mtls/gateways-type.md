# Gateway Types Comparison: GKE Gateway vs ASM Gateway vs Istio Classic

This document provides a systematic comparison of the three gateway paradigms in GKE/ASM environments, focusing on resource types, namespace placement, dependency relationships, and multi-tenant patterns.

---

## 1. Overview: Three Gateway Paradigms

| Paradigm | API Group | Provisioned By | Runs On |
|----------|-----------|----------------|---------|
| **GKE Gateway** (K8s Gateway API) | `gateway.networking.k8s.io/v1` | Google Cloud Load Balancer (GCLB) | Google Global Edge (outside cluster) |
| **ASM Managed Gateway** | `gateway.networking.k8s.io/v1` + ASM GatewayClass | Envoy Pods (managed by ASM) | GKE Nodes (inside cluster) |
| **Istio Classic Gateway** | `networking.istio.io/v1beta1` | Existing Envoy proxy deployments | GKE Nodes (inside cluster) |

---

## 2. GKE Gateway (Kubernetes Gateway API)

### 2.1 What It Is

GKE's implementation of the standard Kubernetes Gateway API. Provisions a **Google Cloud Load Balancer (GCLB)** as the underlying infrastructure. The GCLB lives outside the cluster at Google's edge network.

### 2.2 Core Resources

| Resource | Kind | API Version | Namespace | Required |
|----------|------|-------------|-----------|----------|
| GatewayClass | GatewayClass | `gateway.networking.k8s.io/v1` | cluster-scoped | ✅ (pre-provisioned) |
| Gateway | Gateway | `gateway.networking.k8s.io/v1` | user-defined | ✅ |
| HTTPRoute | HTTPRoute | `gateway.networking.k8s.io/v1` | user-defined | ✅ |
| HealthCheckPolicy | HealthCheckPolicy | `networking.gke.io/v1` | same as Backend Service | ⚠️ GKE-specific |
| BackendTLSPolicy | BackendTLSPolicy | `networking.gke.io/v1` | same as Backend Service | ❌ Optional |
| ReferenceGrant | ReferenceGrant | `gateway.networking.k8s.io/v1beta1` | source or target NS | ⚠️ for cross-NS |

### 2.3 Infrastructure Dependencies (GCP Side)

| GCP Resource | Purpose | Notes |
|-------------|---------|-------|
| **NEG (Network Endpoint Group)** | Backend for GCLB | Automatically created by GKE |
| **Backend Service** | GCLB load balancing target | Created by Gateway |
| **Health Check** | GCLB health check | Auto or via HealthCheckPolicy |
| **Forwarding Rule** | Exposes IP:port | Created by Gateway |
| **SSL Certificate** | TLS termination | GCP-managed or self-managed |
| **VPC Subnet (PSC/NEG)** | For internal L7 LB | User must provision |

### 2.4 Namespace Placement Rules

| Resource | Allowed Namespaces | Notes |
|----------|-------------------|-------|
| Gateway | Any namespace | Controls which namespace can reference it via `parentRef` |
| HTTPRoute | Any namespace | Must have ReferenceGrant to attach to cross-NS Gateway |
| HealthCheckPolicy | Same namespace as target Service | GKE-specific CRD |
| ReferenceGrant | Source or target namespace | Grants cross-NS reference permission |
| Backend Service (GCP) | Cluster-wide | Managed by GKE, not a K8s resource |

**Key Insight:** GKE Gateway's `Gateway` resource can be in any namespace. HTTPRoute can reference a Gateway in a different namespace, but requires ReferenceGrant in the HTTPRoute's namespace.

### 2.5 GKE Gateway YAML Example

```yaml
# GatewayClass (pre-provisioned by GKE)
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: gke-l7-global-external  # or gke-l7-rilb for internal
spec:
  controllerName: networking.gke.io/gateway-controller

---
# Gateway
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tenant-a-gw
  namespace: tenant-a-gateway-ns
spec:
  gatewayClassName: gke-l7-global-external
  listeners:
    - name: https
      hostname: "*.tenant-a.example.com"
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: tls-cert
            namespace: tenant-a-gateway-ns
  addresses:
    - type: NamedAddress
      value: tenant-a-gw-ip

---
# HTTPRoute
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
  namespace: tenant-a-runtime-ns
spec:
  parentRefs:
    - name: tenant-a-gw
      namespace: tenant-a-gateway-ns
  hostnames:
    - "app.tenant-a.example.com"
  rules:
    - backendRefs:
        - name: app-svc
          port: 443

---
# ReferenceGrant (needed for cross-NS HTTPRoute → Gateway)
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-route-from-gateway-ns
  namespace: tenant-a-gateway-ns
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: tenant-a-runtime-ns
  to:
    - group: ""
      kind: Secret  # Gateway's TLS cert

---
# HealthCheckPolicy (GKE-specific)
apiVersion: networking.gke.io/v1
kind: HealthCheckPolicy
metadata:
  name: app-hc
  namespace: tenant-a-runtime-ns
spec:
  default:
    config:
      type: HTTP
      httpHealthCheck:
        port: 8080
        requestPath: /healthz
      checkIntervalSec: 5
      timeoutSec: 3
      healthyThreshold: 2
      unhealthyThreshold: 2
  targetRef:
    group: ""
    kind: Service
    name: app-svc
```

---

## 3. ASM Managed Gateway (Kubernetes Gateway API + ASM)

### 3.1 What It Is

ASM's implementation of the Kubernetes Gateway API using **ASM-managed GatewayClass**. ASM automatically provisions and manages Envoy proxy pods and the associated Kubernetes Service. Unlike GKE Gateway (which provisions GCLB), ASM Managed Gateway runs Envoy pods **inside the cluster**.

### 3.2 Core Resources

| Resource | Kind | API Version | Namespace | Required |
|----------|------|-------------|-----------|----------|
| GatewayClass | GatewayClass | `gateway.networking.k8s.io/v1` | cluster-scoped | ✅ (ASM provisions) |
| Gateway | Gateway | `gateway.networking.k8s.io/v1` | user-defined | ✅ |
| HTTPRoute | HTTPRoute | `gateway.networking.k8s.io/v1` | same as Gateway or cross-NS | ✅ |
| ReferenceGrant | ReferenceGrant | `gateway.networking.k8s.io/v1beta1` | source or target NS | ⚠️ for cross-NS |
| **Istio Resources** | DestinationRule, VirtualService | `networking.istio.io/v1beta1` | same as Gateway | ⚠️ for advanced TLS/mTLS |

### 3.3 ASM Managed Gateway YAML Example

```yaml
# GatewayClass (ASM-managed)
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: istio
spec:
  controllerName: asm/ingressgateway

---
# ASM Managed Gateway
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: tenant-a-asm-gw
  namespace: tenant-a-gateway-ns
spec:
  gatewayClassName: istio
  listeners:
    - name: https
      hostname: "*.tenant-a.example.com"
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: tls-cert
  addresses:
    - type: IPAddress
      value: 10.0.0.100  # ILB IP assigned by ASM

---
# HTTPRoute (same namespace as Gateway - no RefGrant needed)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
  namespace: tenant-a-gateway-ns
spec:
  parentRefs:
    - name: tenant-a-asm-gw
  hostnames:
    - "app.tenant-a.example.com"
  rules:
    - backendRefs:
        - name: app-svc
          namespace: tenant-a-runtime-ns
          port: 443

---
# ReferenceGrant (if HTTPRoute is cross-namespace to Service)
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-httproute-to-service
  namespace: tenant-a-runtime-ns
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: tenant-a-gateway-ns
  to:
    - group: ""
      kind: Service
```

### 3.4 Namespace Placement (ASM Managed Gateway)

| Resource | Must Be In | Notes |
|----------|-----------|-------|
| Gateway | Gateway namespace (user choice) | ASM creates Envoy pods in this NS |
| HTTPRoute | Gateway NS or any NS with RefGrant | Can be same as Gateway (no RefGrant needed) |
| DestinationRule | **Gateway namespace** | Istio sidecar processes TLS here |
| VirtualService | Gateway namespace | Controls routing behavior |
| ReferenceGrant | Target Service namespace | When HTTPRoute → cross-NS Service |

**Critical Rule:** DestinationRule and VirtualService **must** be in the same namespace as the Gateway for ASM managed mode, because the Istio control plane (istiod) processes them in that context.

---

## 4. Istio Classic Gateway (Legacy)

### 4.1 What It Is

The original Istio `Gateway` resource (`networking.istio.io/v1beta1`). It **does not provision infrastructure** — it only configures **existing** Envoy proxy deployments (typically the `istio-ingressgateway` Deployment+Service).

### 4.2 Core Resources

| Resource | Kind | API Version | Namespace | Required |
|----------|------|-------------|-----------|----------|
| Gateway | Gateway | `networking.istio.io/v1beta1` | user-defined | ✅ |
| VirtualService | VirtualService | `networking.istio.io/v1beta1` | user-defined | ✅ |
| DestinationRule | DestinationRule | `networking.istio.io/v1beta1` | user-defined | ⚠️ for TLS |
| Sidecar | Sidecar | `networking.istio.io/v1beta1` | per namespace | ❌ Optional |

### 4.3 Namespace Placement (Istio Classic)

| Resource | Must Be In | Notes |
|----------|-----------|-------|
| Gateway | Same NS as istio-ingressgateway pod | Usually `istio-system` or dedicated NS |
| VirtualService | Same NS as Gateway, or cross-NS with `hosts` match | App-developer defined |
| DestinationRule | Same NS as Gateway | For TLS re-encrypt |

### 4.4 Istio Classic Gateway YAML Example

```yaml
# Istio Classic Gateway
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: tenant-a-gateway
  namespace: tenant-a-gateway-ns
spec:
  selector:
    app: istio-ingressgateway  # targets existing ingressgateway pods
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        serverCertificate: /etc/istio/gateway-cert/tls.crt
        privateKey: /etc/istio/gateway-cert/tls.key
      hosts:
        - "*.tenant-a.example.com"

---
# VirtualService
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: app-vs
  namespace: tenant-a-gateway-ns
spec:
  hosts:
    - "app.tenant-a.example.com"
  gateways:
    - tenant-a-gateway  # references the Gateway above
  http:
    - route:
        - destination:
            host: app-svc.tenant-a-runtime-ns.svc.cluster.local
            port:
              number: 443

---
# DestinationRule (TLS re-encrypt)
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: tls-app
  namespace: tenant-a-gateway-ns
spec:
  host: app-svc.tenant-a-runtime-ns.svc.cluster.local
  trafficPolicy:
    portLevelSettings:
      - port:
          number: 443
        tls:
          mode: SIMPLE  # initiates TLS to backend
          insecureSkipVerify: true
```

---

## 5. Side-by-Side Resource Comparison

| Resource | GKE Gateway | ASM Managed Gateway | Istio Classic |
|----------|-------------|---------------------|---------------|
| **Gateway** | `gateway.networking.k8s.io/v1` | `gateway.networking.k8s.io/v1` | `networking.istio.io/v1beta1` |
| **HTTPRoute** | `gateway.networking.k8s.io/v1` | `gateway.networking.k8s.io/v1` | N/A (uses VirtualService) |
| **VirtualService** | N/A | N/A | `networking.istio.io/v1beta1` |
| **DestinationRule** | N/A | `networking.istio.io/v1beta1` | `networking.istio.io/v1beta1` |
| **HealthCheckPolicy** | `networking.gke.io/v1` | N/A | N/A |
| **BackendTLSPolicy** | `networking.gke.io/v1` | N/A | N/A |
| **ReferenceGrant** | `gateway.networking.k8s.io/v1beta1` | `gateway.networking.k8s.io/v1beta1` | N/A |
| **GatewayClass** | `gateway.networking.k8s.io/v1` | `gateway.networking.k8s.io/v1` | N/A |

---

## 6. Infrastructure Dependencies

| Dependency | GKE Gateway | ASM Managed Gateway | Istio Classic |
|------------|-------------|---------------------|---------------|
| **NEG Subnet** | ✅ Required (PSC subnet for internal L7) | ❌ Not needed | ❌ Not needed |
| **GCLB** | ✅ Auto-provisioned | ❌ No | ❌ No |
| **Envoy Pods** | ❌ No | ✅ ASM-managed | ✅ User-managed |
| **istiod** | ❌ No | ✅ Required | ✅ Required |
| **Cloud Armor** | ✅ Via GCLB backend policy | ❌ Not natively | ❌ Not natively |
| **IAP** | ✅ Via GCLB backend policy | ❌ Not natively | ❌ Not natively |
| **mTLS** | ❌ Not supported | ✅ Via DestinationRule | ✅ Via DestinationRule |

---

## 7. Namespace Placement Summary

### 7.1 Strict Rules by Type

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GKE GATEWAY                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│  Gateway         │ Any namespace (controls route attachment)                 │
│  HTTPRoute      │ Any namespace (needs RefGrant for cross-NS Gateway)       │
│  Secret (TLS)   │ Same namespace as Gateway (needs RefGrant if HTTPRoute    │
│                  │ is cross-NS)                                             │
│  HealthCheckPolicy│ Same namespace as target Service (GKE-specific)           │
│  ReferenceGrant │ Source or target namespace                                 │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                     ASM MANAGED GATEWAY                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  Gateway         │ Gateway namespace (ASM creates Envoy pods here)           │
│  HTTPRoute      │ Gateway NS (same = no RefGrant) or cross-NS with RefGrant │
│  DestinationRule│ MUST be in Gateway namespace (Istio processes here)        │
│  VirtualService │ Gateway namespace (Istio processes here)                   │
│  Secret (TLS)   │ Gateway namespace (no RefGrant needed)                    │
│  ReferenceGrant │ Target Service namespace (for cross-NS HTTPRoute→Service) │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        ISTIO CLASSIC                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  Gateway        │ Same namespace as istio-ingressgateway pod                 │
│  VirtualService│ Same namespace as Gateway (or cross-NS with hosts match)   │
│  DestinationRule│ Gateway namespace (for TLS re-encrypt)                    │
│  Secret (TLS)  │ Gateway namespace (mounted in ingressgateway pods)         │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Multi-Tenant Pattern Comparison

**GKE Gateway Multi-Tenant:**

```
tenant-a-gateway-ns/    (Gateway)
tenant-a-runtime-ns/    (HTTPRoute + Service)
  → RefGrant in tenant-a-runtime-ns if HTTPRoute references cross-NS Service
  → HealthCheckPolicy in tenant-a-runtime-ns
```

**ASM Managed Gateway Multi-Tenant (Same Namespace Pattern):**

```
tenant-a-gateway-ns/
  ├── Gateway: tenant-a-asm-gw
  ├── HTTPRoute: app-route
  ├── DestinationRule: tls-app    ← MUST be here
  └── Secret: tls-cert
tenant-a-runtime-ns/
  ├── Service: app
  └── ReferenceGrant (if HTTPRoute → cross-NS Service)
```

**Istio Classic Multi-Tenant:**

```
istio-system/              (istio-ingressgateway pods — shared)
tenant-a-ns/
  ├── Gateway: tenant-a-gw  (selector: app=istio-ingressgateway)
  ├── VirtualService: app-vs
  └── DestinationRule: tls-app
tenant-a-runtime-ns/
  └── Service: app
```

---

## 8. Which Gateway Type to Choose?

| Use Case | Recommended |
|----------|------------|
| Need Cloud Armor / WAF at edge | **GKE Gateway** |
| Need global Anycast IP | **GKE Gateway** |
| Need IAP / Identity-Aware Proxy | **GKE Gateway** |
| Need mTLS between services | **ASM Managed Gateway** or **Istio Classic** |
| Need fine-grained traffic splitting | **ASM Managed Gateway** or **Istio Classic** |
| Want minimal infra dependencies | **ASM Managed Gateway** |
| Already using Istio, want to migrate gradually | **Istio Classic** |
| Kubernetes-native Gateway API standard | **GKE Gateway** or **ASM Managed Gateway** |
| Cross-cluster/multi-cluster service mesh | **ASM Managed Gateway** or **Istio Classic** |

---

## 9. Combining GKE Gateway + ASM Gateway

For production multi-tenant architectures, stacking both is common:

```
Client
  ↓
GKE Gateway (GCLB) — Edge: WAF, TLS Terminate, Cloud Armor
  ↓ HTTPS :443 → :8443 (re-encrypted)
ASM Managed Gateway — Mesh: mTLS, Routing, Observability
  ↓
Runtime Service (no sidecar)
```

In this stacked model:
- **GKE Gateway** handles external boundary (public IP, WAF, TLS termination)
- **ASM Managed Gateway** handles internal mesh (mTLS, traffic policies)
- TLS re-encryption happens between the two layers

---

## 10. Quick Reference Card

| | GKE Gateway | ASM Managed Gateway | Istio Classic |
|---|-------------|-------------------|---------------|
| **API** | K8s Gateway API | K8s Gateway API | Istio API |
| **Infrastructure** | GCLB (Google managed) | Envoy Pods (ASM managed) | Envoy Pods (self-managed) |
| **Runs** | Outside cluster | Inside cluster | Inside cluster |
| **mTLS** | ❌ | ✅ | ✅ |
| **Cloud Armor** | ✅ | ❌ | ❌ |
| **NEG Subnet** | ✅ Required | ❌ | ❌ |
| **Gateway → HTTPRoute DR** | N/A | ✅ Must be Gateway NS | ✅ Gateway NS |
| **Istio Sidecar** | N/A | Required in Gateway NS | Required in Gateway NS |
| **Multi-tenant isolation** | Via namespace + RefGrant | Via namespace + RefGrant | Via namespace |

---

*Document version: 1.0 — Last updated: 2026-01-XX*
