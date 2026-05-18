# API Versioning and Gateway Comparison: GKE, Istio, and Cloud Service Mesh

This document explores the differences between the various Gateway API versions and implementations available in Google Kubernetes Engine (GKE) and Cloud Service Mesh (ASM).

## 1. Overview of Cloud Service Mesh (CSM/ASM) APIs

Cloud Service Mesh uses open-source Istio APIs for GKE workloads. 
- **Documentation:** [Cloud Service Mesh Overview](https://docs.cloud.google.com/service-mesh/docs/overview)
- **Control Plane:** Uses xDS v3 (xDS v2 is deprecated).
- **Supported API Versions:** Primarily `networking.istio.io/v1` and `v1beta1`.

---

## 2. The Three "Gateways" in GKE/ASM

When working with GKE and Cloud Service Mesh, you will encounter three distinct ways to define and manage Gateways.

### A. Kubernetes Gateway API (The New Standard)
*   **API Group:** `gateway.networking.k8s.io/v1`
*   **Implementation (GKE):** Provisions a **Google Cloud Load Balancer (GCLB)** outside the cluster.
*   **Implementation (Istio/ASM):** Provisions **Envoy-based Gateway Pods** inside the cluster.
*   **Focus:** Role-oriented (Infrastructure vs. App Developer), vendor-neutral, and expressive.

### B. Istio Classic Gateway API (Legacy/Custom)
*   **API Group:** `networking.istio.io/v1beta1` or `v1`
*   **Implementation:** Configures **existing** Envoy proxy deployments. It does *not* automatically provision infrastructure.

### C. ASM Managed Gateway (The Hybrid)
*   **API Group:** `gateway.networking.k8s.io` using ASM-specific `GatewayClasses`.
*   **Implementation:** ASM automatically deploys the Envoy proxy pods and Service.

---

## 3. Deep Dive: GKE Gateway (GCLB) vs. ASM Gateway (Envoy)

To better understand the technical boundary, we compare the GKE-managed Load Balancer and the Mesh-managed Envoy Proxy.

### 运行位置与基础设施 (Infrastructure & Location)
*   **GKE Gateway (GCLB):** 集群外基础设施 (Infrastructure outside the cluster).
    *   Provisions managed **Google Cloud Load Balancing (GCLB)** resources at the **Edge of Google's network**. It does not consume cluster CPU/RAM.
*   **Istio/ASM Gateway (Envoy):** 集群内工作负载 (Workload inside the cluster).
    *   Provisions **Envoy Proxy pods** running directly on your GKE nodes. It acts as the **Ingress Point** for the mesh.

### 功能侧重点 (Feature Focus & Roles)
*   **GKE Gateway: 边缘防护与全球接入 (Edge Protection & Global Reach)**
    *   Handles **Public-facing Edge** concerns: Global Anycast IP, **Cloud Armor (WAF)** for DDoS/SQL injection protection, and **IAP (Identity-Aware Proxy)** for zero-trust access.
*   **Istio/ASM Gateway: 细粒度治理与安全加密 (Fine-grained Governance & mTLS)**
    *   Handles **Service Mesh Entrance** concerns: **mTLS (Mutual TLS)** for end-to-end encryption, **Advanced Routing** (based on headers/subsets), and deep **Telemetry/Observability**.

### “内外”协作模式 (The Collaborative Model: "Better Together")

| 步骤 (Step) | 负责组件 (Owner) | 动作 (Action) | 意义 (Meaning) |
| :--- | :--- | :--- | :--- |
| **Outer Layer** | **GKE Gateway** | HTTPS Termination, WAF (Cloud Armor) | **External Boundary (集群外边界)** |
| **Inner Layer** | **ASM Gateway** | Traffic Splitting, mTLS, Mesh Policy | **Internal Governance (集群内治理)** |

---

## 4. Comparative Feature Table

| 特性 (Feature) | GKE Gateway API (GCLB) | Istio/ASM Gateway (Envoy) |
| :--- | :--- | :--- |
| **本质 (Nature)** | **云基础设施 (Cloud Infra)** | **集群 Pod (Cluster Workload)** |
| **运行位置 (Runs on)** | Google Global Edge (边缘节点) | GKE Node (集群节点) |
| **暴露方式 (Exposure)** | 直接提供外部公网 IP | 作为 Pod，通常后端于 L4 LB |
| **安全能力 (Security)** | **WAF / DDoS / IAP** (防流氓) | **mTLS / AuthPolicy** (防内贼) |
| **资源占用 (Resource)** | 无 (由 Google 托管) | 占用 Pod 资源 (CPU/Memory) |

---

## 5. API Syntax Examples

### Istio Managed Gateway (Classic API)
```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: team-a-gateway
spec:
  selector:
    app: istio-ingressgateway-int
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      privateKey: /etc/istio/gateway-cert/tls.key
      serverCertificate: /etc/istio/gateway-cert/tls.crt
    hosts:
    - "*.team-a.appdev.aibang"
```

### Kubernetes Gateway API (GKE GCLB)
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
   name: internal-http
spec:
  gatewayClassName: gke-l7-rilb 
  listeners:
  - name: http
    protocol: HTTP
    port: 80
```

---

## 6. Key Takeaways for Gateway Selection

*   **Choose GKE Gateway API (GCLB)** when your priority is global acceleration, managed SSL, and edge security (Cloud Armor/WAF). It is the **"Front Door"** to Google Cloud.
*   **Choose ASM/Istio Gateway (Envoy)** when your priority is internal security (mTLS), fine-grained traffic management, and observability. It is the **"Internal Hallway"** of your Mesh.
*   **Recommendation:** Stack them together for the most robust architecture.
