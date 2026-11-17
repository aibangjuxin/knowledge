# Google Cloud Service Mesh Setup Guide for Multi-Tenant GKE Platform

> Document Version: 1.0  
> Last Updated: 2026-02-27  
> Target Audience: Platform Engineers, SRE, Infrastructure Team  
> Prerequisites: GKE clusters running in Master/Tenant project structure

---

## Executive Summary

This document provides a comprehensive guide for implementing **Google Cloud Service Mesh (GCSM)** in your multi-tenant GKE platform. Based on your current architecture:

- **Master Project**: Shared platform capabilities (GKE, Redis, Proxy, AI Models)
- **Tenant Projects**: Isolated tenant workloads with dedicated resources
- **Entry Point**: Global HTTPS Load Balancer for north-south traffic
- **Network Model**: Cross-project VPC peering (IDMZ ↔ EDMZ)

**Key Recommendation**: Use GCSM for **east-west service governance** within clusters, NOT as your primary north-south entry point. Your existing Global HTTPS LB + URL Map architecture remains the correct choice for external traffic management.

---

## Table of Contents

1. [Understanding Google Cloud Service Mesh](#1-understanding-google-cloud-service-mesh)
2. [Architecture Fit Analysis](#2-architecture-fit-analysis)
3. [Deployment Models](#3-deployment-models)
4. [Implementation Guide](#4-implementation-guide)
5. [Service Export and Exposure Patterns](#5-service-export-and-exposure-patterns)
6. [Multi-GKE Cluster Scenarios](#6-multi-gke-cluster-scenarios)
7. [Integration with Existing Architecture](#7-integration-with-existing-architecture)
8. [Operational Considerations](#8-operational-considerations)
9. [Migration Path](#9-migration-path)
10. [Appendix](#10-appendix)

---

## 1. Understanding Google Cloud Service Mesh

### 1.1 What is Google Cloud Service Mesh?

Google Cloud Service Mesh (GCSM) is a managed Istio-based service mesh that provides:

| Capability | Description |
|------------|-------------|
| **Traffic Management** | Fine-grained control over service-to-service communication |
| **Security** | Automatic mTLS between services, policy enforcement |
| **Observability** | Unified metrics, logs, and traces across services |
| **Reliability** | Retries, timeouts, circuit breaking, fault injection |
| **Canary Deployments** | Traffic splitting for gradual rollouts |

### 1.2 What GCSM is NOT

❌ **NOT an API Gateway** - Does not replace your Global HTTPS LB  
❌ **NOT for north-south traffic** - Designed for east-west (service-to-service)  
❌ **NOT a replacement for Kong/Apigee** - Lacks API lifecycle management  
❌ **NOT multi-project by default** - Each mesh typically lives within a project boundary

### 1.3 GCSM vs. Your Current Architecture

| Layer | Current Solution | GCSM Role |
|-------|-----------------|-----------|
| **North-South Entry** | Global HTTPS LB + URL Map | ✅ Keep as-is |
| **API Management** | Kong (optional) / Cloud Armor | ✅ Keep as-is |
| **Service-to-Service** | Direct Kubernetes Services | ⚠️ **GCSM adds value here** |
| **Security** | Network Policies, IAM | ✅ GCSM adds mTLS |
| **Observability** | Cloud Monitoring per project | ✅ GCSM unifies service view |

---

## 2. Architecture Fit Analysis

### 2.1 Your Current Multi-Tenant Model

```
┌─────────────────────────────────────────────────────────┐
│ Master Project (Platform)                               │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ GKE Shared Clusters                                 │ │
│ │ - t1-*.gke-ns (Tenant 1 workloads)                  │ │
│ │ - t2-*.gke-ns (Tenant 2 workloads)                  │ │
│ │ - common-rt-gke-ns (Shared services)                │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Tenant Project A                                        │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ GKE Tenant Cluster                                  │ │
│ │ - API / UI / Microservices                          │ │
│ │ - Kong Gateway / GKE Gateway                        │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Where Does Service Mesh Fit?

**Recommended Deployment Model for Your Platform:**

```
┌──────────────────────────────────────────────────────────────┐
│ External Traffic Flow (North-South)                          │
│ Client → Global HTTPS LB → R-PROXY → GKE Ingress → Service   │
│ ✅ No change needed - keep existing architecture             │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ Internal Traffic Flow (East-West) - GCSM Value Add           │
│ Service A → Sidecar Proxy → mTLS → Sidecar Proxy → Service B │
│                 ↑                                    ↑       │
│                 └──── Service Mesh Control Plane ────┘       │
│ ✅ GCSM provides: security, observability, resilience        │
└──────────────────────────────────────────────────────────────┘
```

### 2.3 Decision Matrix: Do You Need GCSM?

| Scenario | Recommendation |
|----------|----------------|
| Single service per tenant | ❌ Not needed |
| Multiple microservices per tenant | ✅ Consider GCSM |
| Need mTLS between services | ✅ Strong candidate |
| Need canary deployments at service level | ✅ Strong candidate |
| Need unified observability across services | ✅ Strong candidate |
| Only need external API gateway | ❌ Use Kong/Apigee instead |
| Tenant-to-tenant communication required | ⚠️ Complex - see Section 6 |

---

## 3. Deployment Models

### 3.1 Model A: Per-Tenant Mesh (Recommended for Multi-Tenancy)

**Architecture:**
```
┌─────────────────────────────────────────────────────────┐
│ Tenant Project A                                        │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ GKE Cluster A                                       │ │
│ │ ┌─────────────────────────────────────────────────┐ │ │
│ │ │ Service Mesh A (Istio)                          │ │ │
│ │ │ - Control Plane (managed)                       │ │ │
│ │ │ - Data Plane (sidecars)                         │ │ │
│ │ │ - Services: t1-api, t1-ui, t1-ms                │ │ │
│ │ └─────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Tenant Project B                                        │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ GKE Cluster B                                       │ │
│ │ ┌─────────────────────────────────────────────────┐ │ │
│ │ │ Service Mesh B (Istio)                          │ │ │
│ │ │ - Independent from Tenant A                     │ │ │
│ │ │ - Services: t2-api, t2-ui, t2-ms                │ │ │
│ │ └─────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ Clear blast radius isolation
- ✅ Tenant-specific policies
- ✅ Independent upgrade cycles
- ✅ Aligns with your 1 Team = 1 Project model

**Cons:**
- ❌ No unified cross-tenant service discovery
- ❌ More operational overhead per mesh
- ❌ Platform must provide templates/guardrails

**Best For:** Your multi-tenant platform with strong isolation requirements

---

### 3.2 Model B: Platform-Wide Mesh (Not Recommended for Multi-Tenancy)

**Architecture:**
```
┌─────────────────────────────────────────────────────────┐
│ Master Project                                          │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ GKE Shared Clusters                                 │ │
│ │ ┌─────────────────────────────────────────────────┐ │ │
│ │ │ Unified Service Mesh                            │ │ │
│ │ │ - All tenants share same control plane          │ │ │
│ │ │ - Namespace isolation only                      │ │ │
│ │ │ - t1-ns, t2-ns, common-ns                       │ │ │
│ │ └─────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ Unified policy enforcement
- ✅ Easier cross-service communication
- ✅ Single observability plane

**Cons:**
- ❌ Large blast radius
- ❌ Complex multi-project networking
- ❌ Tenant workloads share control plane
- ❌ Harder to meet isolation requirements

**Best For:** Single-organization internal microservices (NOT multi-tenant SaaS)

---

### 3.3 Model C: Hybrid (Platform Services + Tenant Services)

**Architecture:**
```
┌─────────────────────────────────────────────────────────┐
│ Master Project - Platform Services Mesh                 │
│ - Shared infrastructure services                        │
│ - Redis, Common APIs, Platform Services                 │
└─────────────────────────────────────────────────────────┘
                          ↕ (controlled gateway)
┌─────────────────────────────────────────────────────────┐
│ Tenant Project - Tenant Service Mesh                    │
│ - Tenant-specific microservices                         │
│ - Isolated from other tenants                           │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ Platform services get mesh benefits
- ✅ Tenant isolation maintained
- ✅ Controlled cross-mesh communication

**Cons:**
- ❌ Most complex to implement
- ❌ Requires multi-mesh gateway pattern
- ❌ Advanced operational knowledge needed

**Best For:** Mature platforms with clear platform/tenant service boundaries

---

## 4. Implementation Guide

### 4.1 Prerequisites

Before deploying GCSM, ensure:

1. **GKE Version**: 1.26 or later recommended
2. **Project Permissions**: `roles/container.admin`, `roles/meshconfig.admin`
3. **APIs Enabled**:
   ```bash
   gcloud services enable mesh.googleapis.com \
     container.googleapis.com \
     monitoring.googleapis.com \
     logging.googleapis.com \
     --project=${PROJECT_ID}
   ```

4. **Network Requirements**:
   - Workload Identity enabled
   - Private cluster recommended
   - Sufficient IP ranges for sidecars

---

### 4.2 Step-by-Step: Deploy GCSM on Tenant GKE

#### Step 1: Enable Required APIs

```bash
PROJECT_ID="your-tenant-project-id"
CLUSTER_NAME="tenant-gke-cluster"
LOCATION="asia-southeast1"

gcloud services enable mesh.googleapis.com \
  container.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  --project=${PROJECT_ID}
```

#### Step 2: Create GKE Cluster with Mesh Support

```bash
gcloud container clusters create ${CLUSTER_NAME} \
  --location=${LOCATION} \
  --workload-pool=${PROJECT_ID}.svc.id.goog \
  --mesh-certificates=enable=true \
  --enable-ip-alias \
  --enable-intra-node-visibility \
  --num-nodes=3 \
  --machine-type=e2-standard-4 \
  --network=edmz-vpc \
  --subnetwork=edmz-subnet
```

#### Step 3: Register Cluster with GCSM

```bash
gcloud container memberships register ${CLUSTER_NAME}-membership \
  --gke-cluster=${LOCATION}/${CLUSTER_NAME} \
  --enable-workload-identity
```

#### Step 4: Create Service Mesh Deployment

```bash
gcloud container mesh create \
  --location=${LOCATION} \
  --cluster=${CLUSTER_NAME} \
  --cluster-membership=${CLUSTER_NAME}-membership
```

#### Step 5: Verify Mesh Status

```bash
gcloud container mesh describe \
  --location=${LOCATION} \
  --cluster=${CLUSTER_NAME}
```

---

### 4.3 Step-by-Step: Inject Sidecar Proxies

#### Option A: Automatic Injection (Recommended)

```yaml
# Enable sidecar injection for namespace
apiVersion: v1
kind: Namespace
metadata:
  name: t1-api
  labels:
    istio-injection: enabled
```

#### Option B: Manual Injection

```bash
# Inject sidecar into existing deployment
kubectl get deployment my-service -n t1-api -o yaml | \
  istioctl kube-inject -f - | \
  kubectl apply -f -
```

---

### 4.4 Step-by-Step: Configure mTLS

```yaml
# Mesh-wide mTLS policy (strict mode)
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: t1-api
spec:
  mtls:
    mode: STRICT
```

```yaml
# Allow only mTLS traffic to this service
apiVersion: security.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-service-mtls
  namespace: t1-api
spec:
  host: my-service.t1-api.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
```

---

### 4.5 Step-by-Step: Traffic Management

#### Canary Deployment Example

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-service-vs
  namespace: t1-api
spec:
  hosts:
  - my-service
  http:
  - match:
    - headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: my-service
        subset: canary
  - route:
    - destination:
        host: my-service
        subset: stable
      weight: 90
    - destination:
        host: my-service
        subset: canary
      weight: 10
```

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-service-dr
  namespace: t1-api
spec:
  host: my-service
  subsets:
  - name: stable
    labels:
      version: stable
  - name: canary
    labels:
      version: canary
```

---

## 5. Service Export and Exposure Patterns

### 5.1 Internal Service Exposure (Within Mesh)

Services within the mesh are automatically discoverable via Kubernetes DNS:

```
# Service A calls Service B
http://service-b.t1-api.svc.cluster.local:8080
```

**No additional configuration needed** - sidecars handle service discovery and mTLS.

---

### 5.2 External Service Exposure (North-South)

**Important**: GCSM is NOT your external entry point. Use your existing architecture:

```
External Client
    ↓
Global HTTPS LB (Entry Project)
    ↓
R-PROXY (IDMZ)
    ↓
GKE Ingress / Gateway API
    ↓
Service (with sidecar)
```

#### Option A: GKE Ingress (Recommended)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-service-ingress
  namespace: t1-api
  annotations:
    kubernetes.io/ingress.class: "gce"
    networking.gke.io/managed-certificates: "my-service-cert"
spec:
  rules:
  - host: my-service.aibang.com
    http:
      paths:
      - path: /*
        pathType: ImplementationSpecific
        backend:
          service:
            name: my-service
            port:
              number: 8080
```

#### Option B: Istio Ingress Gateway (Advanced)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: my-service-gateway
  namespace: t1-api
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
      credentialName: my-service-tls
    hosts:
    - my-service.aibang.com
```

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-service-vs
  namespace: t1-api
spec:
  hosts:
  - my-service.aibang.com
  gateways:
  - my-service-gateway
  http:
  - route:
    - destination:
        host: my-service
        port:
          number: 8080
```

⚠️ **Warning**: Istio Ingress Gateway adds complexity. Only use if you need advanced L7 routing not supported by GKE Ingress.

---

### 5.3 Cross-Project Service Exposure

For exposing services across projects (Master ↔ Tenant):

#### Pattern 1: Backend Service + NEG (Recommended)

```
Tenant Project Service
    ↓
NEG (Network Endpoint Group)
    ↓
Cross-Project Backend Service (Entry Project)
    ↓
Global HTTPS LB
```

**Configuration:**

```bash
# In Tenant Project - Create NEG
gcloud compute network-endpoint-groups create my-service-neg \
  --network-endpoint-type=gce-vm-ip-port \
  --zone=${ZONE} \
  --project=${TENANT_PROJECT}

# In Entry Project - Reference cross-project NEG
gcloud compute backend-services create my-service-backend \
  --global \
  --project=${ENTRY_PROJECT}

gcloud compute backend-services add-backend my-service-backend \
  --network-endpoint-group=my-service-neg \
  --network-endpoint-group-zone=${ZONE} \
  --project=${ENTRY_PROJECT}
```

#### Pattern 2: Private Service Connect (PSC)

For service-as-a-product model:

```
Service Producer (Master/Tenant)
    ↓
PSC Endpoint
    ↓
VPC Peering / Network
    ↓
Service Consumer (Other Tenants)
```

---

## 6. Multi-GKE Cluster Scenarios

### 6.1 Do You Need Multiple GKE Clusters?

**Question**: "If our GCP master project needs multiple GKE?"

**Answer**: It depends on your isolation requirements:

| Scenario | Recommendation |
|----------|----------------|
| Multiple tenants, shared infrastructure | ✅ Single cluster with namespace isolation |
| Multiple tenants, strong isolation | ✅ Multiple clusters (one per tenant) |
| Production + Non-production | ✅ Separate clusters |
| Different regions | ✅ Regional clusters or multi-cluster |
| Different compliance requirements | ✅ Separate clusters |
| Scale > 1000 pods per cluster | ✅ Consider multiple clusters |

---

### 6.2 Multi-Cluster Mesh Patterns

#### Pattern A: Independent Meshes (Recommended)

Each cluster has its own service mesh:

```
Cluster A (Tenant 1)          Cluster B (Tenant 2)
┌─────────────────┐           ┌─────────────────┐
│ Mesh A          │           │ Mesh B          │
│ - Control Plane │           │ - Control Plane │
│ - Services      │           │ - Services      │
└─────────────────┘           └─────────────────┘
       ↓                             ↓
  No direct mesh communication (isolated)
```

**Pros:**
- Maximum isolation
- Independent upgrades
- Clear blast radius

**Cons:**
- No cross-cluster service discovery
- Requires gateway for inter-cluster communication

---

#### Pattern B: Multi-Cluster Mesh (Advanced)

Connect multiple clusters into a single mesh:

```
Cluster A                      Cluster B
┌─────────────────────────────────────────┐
│         Unified Service Mesh            │
│  ┌────────────┐    ┌────────────┐      │
│  │ Control    │◄──►│ Control    │      │
│  │ Plane A    │    │ Plane B    │      │
│  └────────────┘    └────────────┘      │
│         ▲                   ▲           │
│         └───────┬───────────┘           │
│                 ▼                       │
│         Shared Service Discovery        │
└─────────────────────────────────────────┘
```

**Requirements:**
- All clusters registered to same GCSM control plane
- Network connectivity between clusters (VPC Peering)
- Trust domain alignment
- Advanced operational expertise

**⚠️ Not recommended for multi-tenant isolation** - increases blast radius

---

### 6.3 Cross-Cluster Communication

If you need Cluster A → Cluster B communication:

#### Option 1: Gateway Pattern (Recommended)

```yaml
# Expose service via Gateway in Cluster B
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: cross-cluster-gateway
  namespace: t2-api
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - t2-service.internal.aibang.com
```

```yaml
# Cluster A calls Cluster B via gateway
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: t2-service-external
  namespace: t1-api
spec:
  hosts:
  - t2-service.internal.aibang.com
  ports:
  - number: 443
    name: https
    protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: DNS
```

#### Option 2: Multi-Cluster Service Entry

For unified mesh scenarios:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: remote-service
  namespace: t1-api
spec:
  hosts:
  - my-service.t2-api.global
  location: MESH_INTERNAL
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  resolution: NONE
```

---

## 7. Integration with Existing Architecture

### 7.1 Current Architecture Integration Points

Based on your existing documents:

```
┌─────────────────────────────────────────────────────────────┐
│ Internet                                                    │
│   ↓                                                         │
│ Global HTTPS LB (Entry Project) ← Keep as-is               │
│   ↓                                                         │
│ Cloud Armor / WAF / Cert Manager ← Keep as-is              │
│   ↓                                                         │
│ R-PROXY (TLS/mTLS) ← Keep as-is                            │
│   ↓                                                         │
│ Bridge Proxy (L4) ← Keep as-is                             │
│   ↓                                                         │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ GKE Cluster (Master or Tenant)                          │ │
│ │   ↓                                                     │ │
│ │ GKE Ingress / Gateway API ← Keep as-is                 │ │
│ │   ↓                                                     │ │
│ │ ┌─────────────────────────────────────────────────────┐ │ │
│ │ │ Service Mesh Sidecar (NEW)                          │ │ │
│ │ │   ↓                                                 │ │ │
│ │ │ Application Container                               │ │ │
│ │ └─────────────────────────────────────────────────────┘ │ │
│ │   ↕ (east-west traffic via mesh)                        │ │
│ │ ┌─────────────────────────────────────────────────────┐ │ │
│ │ │ Other Services with Sidecars                        │ │ │
│ │ └─────────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

### 7.2 Integration with Kong Gateway

If you're using Kong as API Gateway:

```
External Client
    ↓
Global HTTPS LB
    ↓
Kong Gateway (on GKE)
    ↓
┌─────────────────────────────┐
│ Service Mesh Sidecar        │
│   ↓                         │
│ Microservice A              │
│   ↕ (mesh-managed traffic)  │
│ Microservice B              │
└─────────────────────────────┘
```

**Kong handles:**
- API authentication
- Rate limiting
- Request/response transformation
- Developer portal

**Service Mesh handles:**
- Service-to-service mTLS
- Traffic splitting
- Retries and timeouts
- Observability

---

### 7.3 Integration with VPC Peering

Your existing IDMZ ↔ EDMZ VPC peering:

```
Master Project (IDMZ VPC)
    ↓
VPC Peering
    ↓
Tenant Project (EDMZ VPC)
    ↓
GKE Cluster with Service Mesh
```

**Key Considerations:**

1. **Sidecar Traffic**: Ensure VPC firewall rules allow sidecar communication
2. **Service Discovery**: Kubernetes DNS works within cluster; use Gateway for cross-cluster
3. **mTLS**: Works within mesh; terminates at gateway for external traffic

**Firewall Rules Needed:**

```bash
# Allow Istio sidecar communication
gcloud compute firewall-rules create allow-mesh-communication \
  --project=${TENANT_PROJECT} \
  --network=edmz-vpc \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:15001,tcp:15006,tcp:15011,tcp:15012,tcp:15014,tcp:15017 \
  --source-ranges=${GKE_POD_CIDR}
```

---

### 7.4 Integration with Cross-Project Logging

Your existing centralized logging:

```
GKE with Service Mesh
    ↓
Cloud Logging (automatic)
    ↓
Log Router Sink
    ↓
Central Log Bucket (logging-hub-project)
```

**Service Mesh adds these log types:**

- `istio-access-log`: Request/response logs
- `istio-audit-log`: Policy enforcement logs
- `istio-error-log`: Sidecar and control plane errors

**Ensure these are included in your sink filters:**

```text
logName:"istio"
OR logName:"mesh"
OR resource.type="k8s_container" AND labels.k8s-istio-mesh="*"
```

---

## 8. Operational Considerations

### 8.1 Monitoring and Observability

GCSM integrates with Cloud Monitoring:

```bash
# View mesh metrics in Cloud Monitoring
gcloud monitoring dashboards create --config-from-file=mesh-dashboard.json
```

**Key Metrics to Monitor:**

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `istio_requests_total` | Total requests | Error rate > 1% |
| `istio_request_duration_milliseconds` | Request latency | p99 > 500ms |
| `istio_tcp_connections_opened_total` | TCP connections | Sudden drop |
| `pilot_k8s_endpoints` | Endpoint discovery | Count = 0 |
| `istio_build` | Component version | Mismatch detected |

---

### 8.2 Upgrade Strategy

**GCSM Upgrade Path:**

1. **Test in non-production first**
2. **Follow Google's upgrade sequence:**
   - Control plane first
   - Data plane (sidecars) second
3. **Use canary deployment for sidecar upgrades**

```bash
# Check current mesh version
gcloud container mesh describe --location=${LOCATION}

# Upgrade mesh
gcloud container mesh update --location=${LOCATION}
```

---

### 8.3 Backup and Disaster Recovery

**What to Backup:**

- Istio configuration (VirtualServices, DestinationRules, etc.)
- Namespace labels (istio-injection=enabled)
- Gateway configurations
- Custom certificates

**Backup Script Example:**

```bash
#!/bin/bash
# Backup Istio configurations

BACKUP_DIR="istio-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p ${BACKUP_DIR}

kubectl get virtualservices --all-namespaces -o yaml > ${BACKUP_DIR}/virtualservices.yaml
kubectl get destinationrules --all-namespaces -o yaml > ${BACKUP_DIR}/destinationrules.yaml
kubectl get gateways --all-namespaces -o yaml > ${BACKUP_DIR}/gateways.yaml
kubectl get serviceentries --all-namespaces -o yaml > ${BACKUP_DIR}/serviceentries.yaml
```

---

### 8.4 Security Best Practices

1. **Enable strict mTLS:**
   ```yaml
   apiVersion: security.istio.io/v1beta1
   kind: MeshConfig
   spec:
     mtlsMode: STRICT
   ```

2. **Implement authorization policies:**
   ```yaml
   apiVersion: security.istio.io/v1beta1
   kind: AuthorizationPolicy
   metadata:
     name: require-jwt
     namespace: t1-api
   spec:
     rules:
     - from:
       - source:
           requestPrincipals: ["*"]
   ```

3. **Rotate certificates regularly:**
   - GCSM auto-rotates workload certificates
   - Manually rotate gateway certificates every 90 days

4. **Audit mesh configurations:**
   - Use GitOps for all Istio resources
   - Require PR review for mesh changes
   - Enable audit logging for mesh control plane

---

### 8.5 Cost Considerations

**GCSM Pricing Components:**

1. **Managed Control Plane**: ~$50/month per cluster
2. **Data Plane (Sidecars)**: No additional cost
3. **Cloud Monitoring**: Standard pricing applies

**Cost Optimization:**

- Don't inject sidecars into services that don't need mesh features
- Use namespace-level injection control
- Consider shared clusters for non-critical workloads

---

## 9. Migration Path

### 9.1 Phase 1: Foundation (Month 1-2)

**Goals:**
- Deploy GCSM on one non-production cluster
- Enable sidecar injection for 1-2 services
- Validate mTLS and observability

**Tasks:**
1. Enable GCSM APIs
2. Deploy test cluster
3. Deploy sample microservices
4. Configure basic traffic policies
5. Validate Cloud Monitoring integration

---

### 9.2 Phase 2: Pilot (Month 3-4)

**Goals:**
- Deploy GCSM on one tenant production cluster
- Migrate 2-3 critical services
- Implement canary deployments

**Tasks:**
1. Production cluster setup
2. Service migration (one at a time)
3. Implement traffic management policies
4. Set up alerting and dashboards
5. Document operational runbooks

---

### 9.3 Phase 3: Scale (Month 5-6)

**Goals:**
- Roll out to all tenant clusters
- Implement platform guardrails
- Automate mesh provisioning

**Tasks:**
1. Create Terraform modules for GCSM
2. Define platform baseline policies
3. Implement automated onboarding
4. Train tenant teams on mesh features
5. Establish upgrade procedures

---

### 9.4 Phase 4: Optimize (Month 7+)

**Goals:**
- Advanced traffic management
- Cross-cluster communication (if needed)
- Continuous optimization

**Tasks:**
1. Implement advanced canary patterns
2. Optimize resource allocation
3. Review and refine policies
4. Measure and report ROI

---

## 10. Appendix

### 10.1 Common Troubleshooting Commands

```bash
# Check sidecar injection status
kubectl get pods -n t1-api -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.istio-injection}{"\n"}{end}'

# Verify mTLS status
istioctl analyze --all-namespaces

# Check proxy configuration
istioctl proxy-config listeners <pod-name>.<namespace>

# View access logs
istioctl proxy-config log <pod-name>.<namespace> --level access:debug

# Test connectivity
istioctl proxy-config route <pod-name>.<namespace> --name http.8080
```

---

### 10.2 Terraform Module Example

```hcl
# GCSM-enabled GKE Cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.location
  project  = var.project_id

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  mesh_certificates {
    enable_certificates = true
  }

  # ... other configurations
}

# Register cluster with GCSM
resource "google_gke_hub_membership" "membership" {
  membership_id = "${var.cluster_name}-membership"
  project       = var.project_id
  location      = var.location

  endpoint {
    gke_cluster {
      resource_link = google_container_cluster.primary.id
    }
  }

  authority {
    issuer = "https://container.googleapis.com/${google_container_cluster.primary.id}"
  }
}
```

---

### 10.3 Decision Checklist

Before deploying GCSM, confirm:

- [ ] Do you have multiple microservices per tenant?
- [ ] Do you need service-to-service mTLS?
- [ ] Do you need advanced traffic management (canary, retries, timeouts)?
- [ ] Do you have operational capacity to manage mesh configurations?
- [ ] Is your GKE version compatible (1.26+)?
- [ ] Have you enabled Workload Identity?
- [ ] Do you have sufficient IP ranges for sidecars?
- [ ] Have you defined mesh governance policies?
- [ ] Is your team trained on Istio concepts?
- [ ] Do you have a rollback plan?

---

### 10.4 References

- [Google Cloud Service Mesh Documentation](https://cloud.google.com/service-mesh/docs)
- [Istio Documentation](https://istio.io/latest/docs/)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [Multi-Cluster Service Mesh](https://cloud.google.com/service-mesh/docs/multi-cluster-setup-overview)
- [Service Mesh vs API Gateway](https://cloud.google.com/architecture/service-meshes)

---

### 10.5 Glossary

| Term | Definition |
|------|------------|
| **GCSM** | Google Cloud Service Mesh (managed Istio) |
| **Sidecar** | Envoy proxy deployed alongside each service container |
| **Control Plane** | Manages and configures all sidecar proxies |
| **Data Plane** | Network of sidecar proxies handling service traffic |
| **mTLS** | Mutual TLS authentication between services |
| **VirtualService** | Istio resource for traffic routing rules |
| **DestinationRule** | Istio resource for traffic policies to a service |
| **Gateway** | Istio resource for managing ingress traffic |
| **NEG** | Network Endpoint Group (GCP load balancing backend) |
| **PSC** | Private Service Connect (GCP service exposure) |

---

## Summary and Recommendations

### For Your Multi-Tenant Platform:

1. **✅ Adopt GCSM for east-west service governance** within tenant clusters
2. **✅ Keep Global HTTPS LB for north-south traffic** (don't replace with mesh ingress)
3. **✅ Use per-tenant mesh model** for isolation (Model A)
4. **✅ Start with non-production pilot** before production rollout
5. **✅ Integrate with existing logging/monitoring** (logging-hub-project)
6. **❌ Don't use mesh for cross-project routing** (use Backend Service + NEG)
7. **❌ Don't deploy multi-cluster mesh** unless absolutely necessary

### Next Steps:

1. **Week 1-2**: Enable GCSM APIs, deploy test cluster
2. **Week 3-4**: Deploy sample microservices, validate mTLS
3. **Month 2**: Pilot with one tenant workload
4. **Month 3**: Create Terraform modules, define guardrails
5. **Month 4+**: Gradual rollout to all tenants

---

**Document Owner**: Infrastructure Team  
**Review Cycle**: Quarterly  
**Feedback**: Contact platform-architecture@aibang.com
