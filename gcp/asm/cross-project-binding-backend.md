# Cross-Project Internal HTTPS LB Backend Binding Exploration

> Document Version: 1.0  
> Last Updated: 2026-02-27  
> Author: Infrastructure Team  
> Architecture Context: Master Project (IDMZ) → Tenant Project (EDMZ)  
> Prerequisites: VPC Peering established, GKE clusters deployed

---

## Executive Summary

This document explores the feasibility and implementation of **cross-project Internal HTTPS Load Balancer (ILB) binding** in your multi-tenant GCP architecture.

**Your Current Architecture:**
```
Internet
    ↓
Global HTTPS LB (Entry Project)
    ↓
Cloud Armor + WAF + Cert Manager
    ↓
R-PROXY (Master Project - IDMZ)
    ↓
Nginx L7 Proxy (Master Project)
    ↓
GKE Backend (Tenant Project - EDMZ)
```

**Core Question:** Can Internal HTTPS LB in Master Project directly bind to Backend Services in Tenant Projects?

**Short Answer:** ✅ **Yes, this is supported** via cross-project Backend Service references, but requires specific IAM permissions and network configuration.

---

## Table of Contents

1. [Architecture Context](#1-architecture-context)
2. [Feasibility Analysis](#2-feasibility-analysis)
3. [Implementation Models](#3-implementation-models)
4. [Step-by-Step Implementation](#4-step-by-step-implementation)
5. [Network and IAM Requirements](#5-network-and-iam-requirements)
6. [Security Considerations](#6-security-considerations)
7. [Traffic Flow Analysis](#7-traffic-flow-analysis)
8. [Limitations and Quotas](#8-limitations-and-quotas)
9. [Troubleshooting Guide](#9-troubleshooting-guide)
10. [Comparison Matrix](#10-comparison-matrix)
11. [Recommendations](#11-recommendations)
12. [Appendix](#12-appendix)

---

## 1. Architecture Context

### 1.1 Your Current Multi-Tenant Model

Based on your existing architecture documents:

```
┌─────────────────────────────────────────────────────────────┐
│ Master Project (Platform)                                   │
│ VPC: idmz-vpc                                               │
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Internal HTTPS LB                                       │ │
│ │ (Cloud Armor + WAF + Cert Manager)                      │ │
│ └───────────────────┬─────────────────────────────────────┘ │
│                     │                                       │
│ ┌───────────────────▼─────────────────────────────────────┐ │
│ │ Nginx L7 Proxy                                          │ │
│ │ (Multi-NIC Compute Engine)                              │ │
│ └───────────────────┬─────────────────────────────────────┘ │
│                     │                                       │
│ ┌───────────────────▼─────────────────────────────────────┐ │
│ │ VPC Peering (idmz-vpc ↔ edmz-vpc)                       │ │
│ └───────────────────┬─────────────────────────────────────┘ │
└─────────────────────┼───────────────────────────────────────┘
                      │
┌─────────────────────┼───────────────────────────────────────┐
│ Tenant Project A    │                                       │
│ VPC: edmz-vpc-a     │                                       │
│                     │                                       │
│ ┌───────────────────▼─────────────────────────────────────┐ │
│ │ GKE Cluster A                                           │ │
│ │ - NEG (Network Endpoint Group)                          │ │
│ │ - Services: t1-api, t1-ui, t1-ms                        │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────┼───────────────────────────────────────┐
│ Tenant Project B    │                                       │
│ VPC: edmz-vpc-b     │                                       │
│                     │                                       │
│ ┌───────────────────▼─────────────────────────────────────┐ │
│ │ GKE Cluster B                                           │ │
│ │ - NEG (Network Endpoint Group)                          │ │
│ │ - Services: t2-api, t2-ui, t2-ms                        │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Current Traffic Flow

**North-South (External):**
```
Client → Global HTTPS LB → R-PROXY → Nginx L7 → GKE (Tenant)
```

**Internal (Within Master):**
```
Internal Client → Internal HTTPS LB → Nginx L7 → GKE (Master)
```

**Target State (Cross-Project):**
```
Internal Client → Internal HTTPS LB (Master) → GKE (Tenant Project)
```

---

## 2. Feasibility Analysis

### 2.1 GCP Capability Assessment

| Capability | Supported | Notes |
|------------|-----------|-------|
| Cross-project Backend Service | ✅ Yes | Via IAM delegation |
| Cross-project NEG reference | ✅ Yes | `compute.networkUser` role |
| Internal HTTPS LB cross-project | ✅ Yes | Same as global, but regional |
| VPC Peering required | ⚠️ Depends | Required for private IP access |
| Shared VPC alternative | ✅ Yes | Simpler but less isolation |

### 2.2 Technical Requirements

**Must Have:**
1. ✅ VPC Peering between Master (IDMZ) and Tenant (EDMZ) VPCs
2. ✅ IAM permissions: `compute.networkUser` granted to Master Project
3. ✅ NEG enabled on Tenant GKE clusters
4. ✅ Firewall rules allowing traffic from Master to Tenant subnet
5. ✅ Non-overlapping CIDR ranges

**Should Have:**
1. ✅ Private Google Access enabled
2. ✅ Cloud NAT for egress
3. ✅ VPC Flow Logs for troubleshooting
4. ✅ Monitoring and alerting configured

### 2.3 Architecture Decision Points

| Decision | Option A (Recommended) | Option B |
|----------|------------------------|----------|
| **Load Balancer Type** | Regional Internal HTTPS LB | Global Internal HTTPS LB |
| **Backend Reference** | Cross-project NEG | Cross-project Instance Group |
| **Network Model** | VPC Peering | Shared VPC |
| **Certificate Management** | Private CA per project | Shared Certificate Manager |
| **IAM Model** | Per-project service accounts | Centralized service accounts |

---

## 3. Implementation Models

### 3.1 Model A: Direct Cross-Project Backend Service (Recommended)

**Architecture:**
```
┌─────────────────────────────────────────────────────────┐
│ Master Project (idmz-vpc)                               │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Internal HTTPS LB                                   │ │
│ │ - Regional                                          │ │
│ │ - Cloud Armor (internal rules)                      │ │
│ │ - Private Certificate                               │ │
│ └───────────────────┬─────────────────────────────────┘ │
│                     │                                   │
│ ┌───────────────────▼─────────────────────────────────┐ │
│ │ Backend Service (cross-project reference)           │ │
│ │ - Points to Tenant Project NEG                      │ │
│ │ - IAM: compute.networkUser                          │ │
│ └───────────────────┬─────────────────────────────────┘ │
└─────────────────────┼───────────────────────────────────┘
                      │
                      │ VPC Peering
                      │
┌─────────────────────┼───────────────────────────────────┐
│ Tenant Project (edmz-vpc)           │                   │
│                                     │                   │
│ ┌─────────────────▼───────────────────────────────────┐ │
│ │ NEG (Network Endpoint Group)                        │ │
│ │ - GKE Serverless NEG                                │ │
│ │ - Points to Kubernetes Service                      │ │
│ └─────────────────┬───────────────────────────────────┘ │
│                   │                                     │
│ ┌─────────────────▼───────────────────────────────────┐ │
│ │ GKE Cluster                                         │ │
│ │ - Service: my-api                                   │ │
│ │ - Pods: API workloads                               │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ Clean separation of concerns
- ✅ Tenant controls their own NEG
- ✅ Master controls routing and security
- ✅ Aligns with your 1 Team = 1 Project model

**Cons:**
- ⚠️ Requires cross-project IAM setup
- ⚠️ More complex initial configuration
- ⚠️ Troubleshooting spans multiple projects

**Best For:** Your multi-tenant platform with strong isolation requirements

---

### 3.2 Model B: Shared VPC Host Project

**Architecture:**
```
┌─────────────────────────────────────────────────────────┐
│ Host Project (idmz-vpc)                                 │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Internal HTTPS LB                                   │ │
│ │ - All subnets shared                                │ │
│ │ - Centralized management                            │ │
│ └───────────────────┬─────────────────────────────────┘ │
│                     │                                   │
│ ┌───────────────────▼─────────────────────────────────┐ │
│ │ Backend Service (same VPC)                          │ │
│ │ - No cross-project IAM needed                       │ │
│ │ - Simpler networking                                │ │
│ └───────────────────┬─────────────────────────────────┘ │
└─────────────────────┼───────────────────────────────────┘
                      │
┌─────────────────────┼───────────────────────────────────┐
│ Service Project A   │   Service Project B               │
│ (GKE Cluster A)     │   (GKE Cluster B)                 │
│                     │                                   │
│ ┌─────────────────▼─┴─────────────────────────────────┐ │
│ │ NEG (attached to shared VPC)                        │ │
│ │ GKE clusters use shared subnets                     │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ Simpler networking (single VPC)
- ✅ No cross-project IAM complexity
- ✅ Easier troubleshooting

**Cons:**
- ⚠️ Less isolation between tenants
- ⚠️ Network policies shared across projects
- ⚠️ Harder to enforce tenant boundaries

**Best For:** Organizations with strong central network team

---

### 3.3 Model C: Nginx L7 Proxy as Cross-Project Gateway

**Architecture (Your Current Baseline):**
```
┌─────────────────────────────────────────────────────────┐
│ Master Project (idmz-vpc)                               │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Internal HTTPS LB                                   │ │
│ └───────────────────┬─────────────────────────────────┘ │
│                     │                                   │
│ ┌───────────────────▼─────────────────────────────────┐ │
│ │ Nginx L7 Proxy (Multi-NIC CE)                       │ │
│ │ - Acts as application gateway                       │ │
│ │ - Cross-project routing logic                       │ │
│ └───────────────────┬─────────────────────────────────┘ │
│                     │                                   │
│                     │ VPC Peering                       │
│                     │                                   │
│ ┌───────────────────▼─────────────────────────────────┐ │
│ │ Tenant Project Backend                              │ │
│ │ (via private IP or ILB)                             │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ Maximum flexibility (custom routing logic)
- ✅ Can implement tenant-specific policies
- ✅ Works with existing architecture

**Cons:**
- ⚠️ Additional hop (latency)
- ⚠️ Nginx management overhead
- ⚠️ Not cloud-native

**Best For:** Complex routing requirements not supported by ILB

---

## 4. Step-by-Step Implementation

### 4.1 Prerequisites Checklist

Before starting, ensure:

- [ ] VPC Peering established between `idmz-vpc` and `edmz-vpc`
- [ ] Both VPCs have non-overlapping CIDR ranges
- [ ] Firewall rules allow traffic between VPCs
- [ ] GKE clusters have NEG enabled
- [ ] Required APIs enabled in both projects
- [ ] IAM permissions configured (see Section 5)

---

### 4.2 Phase 1: Enable Required APIs

**In Master Project:**
```bash
MASTER_PROJECT="master-project-id"

gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  servicenetworking.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project=${MASTER_PROJECT}
```

**In Tenant Project:**
```bash
TENANT_PROJECT="tenant-project-id"

gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  servicenetworking.googleapis.com \
  --project=${TENANT_PROJECT}
```

---

### 4.3 Phase 2: Configure VPC Peering

**Step 2.1: Create Peering from Master to Tenant**
```bash
gcloud compute networks peerings create idmz-to-edmz \
  --project=${MASTER_PROJECT} \
  --network=idmz-vpc \
  --peer-project=${TENANT_PROJECT} \
  --peer-network=edmz-vpc \
  --import-custom-routes \
  --export-custom-routes \
  --import-subnet-routes-with-public-ip \
  --export-subnet-routes-with-public-ip
```

**Step 2.2: Create Peering from Tenant to Master**
```bash
gcloud compute networks peerings create edmz-to-idmz \
  --project=${TENANT_PROJECT} \
  --network=edmz-vpc \
  --peer-project=${MASTER_PROJECT} \
  --peer-network=idmz-vpc \
  --import-custom-routes \
  --export-custom-routes \
  --import-subnet-routes-with-public-ip \
  --export-subnet-routes-with-public-ip
```

**Step 2.3: Verify Peering Status**
```bash
gcloud compute networks peerings list \
  --project=${MASTER_PROJECT} \
  --filter="network=idmz-vpc"

gcloud compute networks peerings list \
  --project=${TENANT_PROJECT} \
  --filter="network=edmz-vpc"
```

Expected output: `state: ACTIVE`

---

### 4.4 Phase 3: Configure IAM Permissions

**Step 3.1: Get Master Project Number**
```bash
MASTER_PROJECT_NUMBER=$(gcloud projects describe ${MASTER_PROJECT} \
  --format="value(projectNumber)")
```

**Step 3.2: Grant compute.networkUser to Master Project**
```bash
gcloud projects add-iam-policy-binding ${TENANT_PROJECT} \
  --member="serviceAccount:service-${MASTER_PROJECT_NUMBER}@compute-system.iam.gserviceaccount.com" \
  --role="roles/compute.networkUser"
```

**Step 3.3: Grant additional roles for NEG management**
```bash
# For GKE service account
GKE_SA_EMAIL="$(gcloud services identity create \
  --service=container.googleapis.com \
  --project=${TENANT_PROJECT} \
  --format='get(email)')"

gcloud projects add-iam-policy-binding ${TENANT_PROJECT} \
  --member="serviceAccount:${GKE_SA_EMAIL}" \
  --role="roles/compute.networkUser"

gcloud projects add-iam-policy-binding ${TENANT_PROJECT} \
  --member="serviceAccount:${GKE_SA_EMAIL}" \
  --role="roles/compute.loadBalancerServiceUser"
```

---

### 4.5 Phase 4: Create GKE NEG in Tenant Project

**Step 4.1: Deploy Sample Service**
```yaml
# tenant-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: my-api-service
  namespace: t1-api
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
    cloud.google.com/backend-config: '{"default": "my-backend-config"}'
spec:
  type: ClusterIP
  selector:
    app: my-api
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
---
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: my-backend-config
  namespace: t1-api
spec:
  healthCheck:
    checkIntervalSec: 30
    timeoutSec: 5
    healthyThreshold: 1
    unhealthyThreshold: 2
    type: HTTP
    requestPath: /health
    port: 8080
```

**Step 4.2: Apply Configuration**
```bash
kubectl apply -f tenant-service.yaml --context=${TENANT_CLUSTER_CONTEXT}
```

**Step 4.3: Get NEG Name**
```bash
NEG_NAME=$(kubectl get service my-api-service -n t1-api \
  -o jsonpath='{.metadata.annotations.cloud\.google\.com/neg-status}' | \
  jq -r '.network_endpoint_groups["asia-southeast1-a"]' | \
  cut -d'/' -f11)

echo "NEG Name: ${NEG_NAME}"
```

---

### 4.6 Phase 5: Create Cross-Project Backend Service

**Step 5.1: Create Backend Service in Master Project**
```bash
ZONE="asia-southeast1-a"

gcloud compute backend-services create my-api-backend \
  --project=${MASTER_PROJECT} \
  --global \
  --protocol=HTTPS \
  --port-name=https \
  --health-checks=my-api-health-check \
  --enable-cdn \
  --connection-draining-timeout=300
```

**Step 5.2: Add Cross-Project NEG as Backend**
```bash
gcloud compute backend-services add-backend my-api-backend \
  --project=${MASTER_PROJECT} \
  --global \
  --network-endpoint-group=${NEG_NAME} \
  --network-endpoint-group-zone=${ZONE} \
  --balancing-mode=RATE \
  --max-rate-per-endpoint=100
```

**Step 5.3: Verify Backend Service**
```bash
gcloud compute backend-services describe my-api-backend \
  --project=${MASTER_PROJECT} \
  --global
```

Expected output should show the NEG from tenant project.

---

### 4.7 Phase 6: Create Internal HTTPS Load Balancer

**Step 6.1: Reserve Internal IP Address**
```bash
gcloud compute addresses create my-api-ilb-ip \
  --project=${MASTER_PROJECT} \
  --region=asia-southeast1 \
  --subnet=idmz-subnet \
  --address-type=INTERNAL
```

**Step 6.2: Create Health Check**
```bash
gcloud compute health-checks create https my-api-health-check \
  --project=${MASTER_PROJECT} \
  --port=8080 \
  --request-path=/health \
  --check-interval=30s \
  --timeout=5s \
  --healthy-threshold=1 \
  --unhealthy-threshold=2
```

**Step 6.3: Create SSL Certificate (Private)**
```bash
# Option A: Self-signed for testing
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout my-api.key \
  -out my-api.crt \
  -subj "/CN=my-api.internal.aibang.com"

gcloud compute ssl-certificates create my-api-cert \
  --project=${MASTER_PROJECT} \
  --certificate=my-api.crt \
  --private-key=my-api.key
```

```bash
# Option B: Private CA (recommended for production)
gcloud compute ssl-certificates create my-api-cert \
  --project=${MASTER_PROJECT} \
  --certificate=cert-from-private-ca.crt \
  --private-key=private-key.key
```

**Step 6.4: Create URL Map**
```bash
gcloud compute url-maps create my-api-url-map \
  --project=${MASTER_PROJECT} \
  --default-service=my-api-backend
```

**Step 6.5: Create Target HTTPS Proxy**
```bash
gcloud compute target-https-proxies create my-api-proxy \
  --project=${MASTER_PROJECT} \
  --url-map=my-api-url-map \
  --ssl-certificates=my-api-cert
```

**Step 6.6: Create Forwarding Rule**
```bash
ILB_IP=$(gcloud compute addresses describe my-api-ilb-ip \
  --project=${MASTER_PROJECT} \
  --region=asia-southeast1 \
  --format="value(address)")

gcloud compute forwarding-rules create my-api-forwarding-rule \
  --project=${MASTER_PROJECT} \
  --region=asia-southeast1 \
  --load-balancing-scheme=INTERNAL \
  --network=idmz-vpc \
  --subnet=idmz-subnet \
  --ip-protocol=TCP \
  --ports=443 \
  --address=${ILB_IP} \
  --target-https-proxy=my-api-proxy
```

---

### 4.8 Phase 7: Configure Firewall Rules

**In Master Project (allow ILB to reach Tenant):**
```bash
TENANT_CIDR="10.2.0.0/16"  # Replace with actual Tenant VPC CIDR

gcloud compute firewall-rules create allow-ilb-to-tenant \
  --project=${MASTER_PROJECT} \
  --network=idmz-vpc \
  --direction=EGRESS \
  --action=ALLOW \
  --rules=tcp:443,tcp:8080 \
  --destination-ranges=${TENANT_CIDR}
```

**In Tenant Project (allow Master VPC to reach NEG):**
```bash
MASTER_CIDR="10.1.0.0/16"  # Replace with actual Master VPC CIDR

gcloud compute firewall-rules create allow-master-to-neg \
  --project=${TENANT_PROJECT} \
  --network=edmz-vpc \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:8080,tcp:443 \
  --source-ranges=${MASTER_CIDR}
```

---

### 4.9 Phase 8: Testing and Validation

**Step 8.1: Test from Master Project VM**
```bash
# SSH to a VM in Master Project
gcloud compute ssh test-vm \
  --project=${MASTER_PROJECT} \
  --zone=asia-southeast1-a

# Test connectivity
curl -k https://${ILB_IP}/health
curl -k https://my-api.internal.aibang.com/health \
  --resolve my-api.internal.aibang.com:443:${ILB_IP}
```

**Step 8.2: Verify End-to-End Flow**
```bash
# Check load balancer logs
gcloud logging read \
  "resource.type=\"http_load_balancer\" AND \
   jsonPayload.targetDetails.target=\"${ILB_IP}\"" \
  --project=${MASTER_PROJECT} \
  --limit=10

# Check NEG health
gcloud compute network-endpoint-groups get-health ${NEG_NAME} \
  --project=${TENANT_PROJECT} \
  --zone=${ZONE}
```

**Step 8.3: Validate Traffic Distribution**
```bash
# Send multiple requests and check backend distribution
for i in {1..10}; do
  curl -k -s https://${ILB_IP}/health | jq '.pod_name'
done
```

---

## 5. Network and IAM Requirements

### 5.1 Network Requirements Summary

| Requirement | Master Project | Tenant Project |
|-------------|----------------|----------------|
| **VPC** | idmz-vpc | edmz-vpc |
| **Subnet CIDR** | 10.1.0.0/16 (example) | 10.2.0.0/16 (example) |
| **VPC Peering** | idmz-to-edmz | edmz-to-idmz |
| **Private Google Access** | Enabled | Enabled |
| **Cloud NAT** | Recommended | Recommended |
| **Firewall (Ingress)** | Allow from internal clients | Allow from Master CIDR |
| **Firewall (Egress)** | Allow to Tenant CIDR | Allow to Master CIDR |

---

### 5.2 IAM Permissions Matrix

| Role | Granted To | Purpose |
|------|------------|---------|
| `roles/compute.networkUser` | Master Project SA | Reference Tenant NEG |
| `roles/compute.loadBalancerServiceUser` | Master Project SA | Create LB resources |
| `roles/container.hostServiceAgentUser` | Master Project SA | Access GKE resources |
| `roles/compute.admin` | Platform Team | Manage LB and networking |
| `roles/container.admin` | Platform Team | Manage GKE and NEG |

**Service Accounts Involved:**

```bash
# Master Project Compute Service Account
service-${MASTER_PROJECT_NUMBER}@compute-system.iam.gserviceaccount.com

# Master Project GKE Service Account
service-${MASTER_PROJECT_NUMBER}@container-engine-robot.iam.gserviceaccount.com

# Tenant Project GKE Service Account
service-${TENANT_PROJECT_NUMBER}@container-engine-robot.iam.gserviceaccount.com
```

---

### 5.3 Required APIs

**Master Project:**
```yaml
- compute.googleapis.com
- container.googleapis.com
- servicenetworking.googleapis.com
- cloudresourcemanager.googleapis.com
- logging.googleapis.com
- monitoring.googleapis.com
```

**Tenant Project:**
```yaml
- compute.googleapis.com
- container.googleapis.com
- servicenetworking.googleapis.com
- logging.googleapis.com
- monitoring.googleapis.com
```

---

## 6. Security Considerations

### 6.1 TLS/Certificate Strategy

**Option A: Private CA (Recommended for Production)**

```
Master Project
├── Private CA (Certificate Authority)
├── SSL Certificate (issued by Private CA)
└── Trust Config (shared with Tenant)
```

**Implementation:**
```bash
# Create Private CA
gcloud privateca pools create my-pool \
  --project=${MASTER_PROJECT} \
  --location=asia-southeast1 \
  --tier=ENTERPRISE

# Issue certificate
gcloud privateca certificates create my-api-cert \
  --project=${MASTER_PROJECT} \
  --location=asia-southeast1 \
  --pool=my-pool \
  --common-name=my-api.internal.aibang.com \
  --subject-alternative-names="my-api.internal.aibang.com"
```

**Option B: Certificate Manager with DNS Validation**

```bash
gcloud certificate-manager certificates create my-api-cert \
  --project=${MASTER_PROJECT} \
  --domains="my-api.internal.aibang.com"
```

---

### 6.2 Network Security Best Practices

1. **Minimize Firewall Rules:**
   ```bash
   # ❌ Too permissive
   --source-ranges=0.0.0.0/0
   
   # ✅ Specific to Master VPC
   --source-ranges=10.1.0.0/16
   ```

2. **Enable VPC Flow Logs:**
   ```bash
   gcloud compute networks subnets update idmz-subnet \
     --project=${MASTER_PROJECT} \
     --region=asia-southeast1 \
     --enable-flow-logs
   
   gcloud compute networks subnets update edmz-subnet \
     --project=${TENANT_PROJECT} \
     --region=asia-southeast1 \
     --enable-flow-logs
   ```

3. **Implement Cloud Armor Policies:**
   ```bash
   gcloud compute security-policies create my-api-policy \
     --project=${MASTER_PROJECT}
   
   gcloud compute security-policies rules create 1000 \
     --project=${MASTER_PROJECT} \
     --security-policy=my-api-policy \
     --description="Allow internal only" \
     --src-ip-ranges="10.0.0.0/8" \
     --action="allow"
   ```

---

### 6.3 IAM Security Best Practices

1. **Principle of Least Privilege:**
   - Grant roles at project level, not org level
   - Use service accounts, not user accounts
   - Review permissions quarterly

2. **Audit Logging:**
   ```bash
   gcloud logging sinks create iam-audit-sink \
     logging.googleapis.com/projects/${MASTER_PROJECT}/locations/global/buckets/central-logs \
     --log-filter='protoPayload.methodName:"compute.*.insert"' \
     --project=${MASTER_PROJECT}
   ```

3. **Service Account Key Rotation:**
   - Avoid long-lived keys
   - Use workload identity where possible
   - Rotate keys every 90 days

---

## 7. Traffic Flow Analysis

### 7.1 Request Flow (Client to Backend)

```
┌──────────────┐
│ Client VM    │
│ (Master VPC) │
└──────┬───────┘
       │ 1. HTTPS Request to ILB IP
       ▼
┌──────────────────────────────┐
│ Internal HTTPS LB            │
│ - Terminates TLS             │
│ - Applies Cloud Armor rules  │
│ - Selects backend            │
└──────┬───────────────────────┘
       │ 2. Forward to Backend Service
       ▼
┌──────────────────────────────┐
│ Backend Service              │
│ - Load balancing algorithm   │
│ - Health check validation    │
└──────┬───────────────────────┘
       │ 3. Route to NEG
       ▼
┌──────────────────────────────┐
│ NEG (Tenant Project)         │
│ - Serverless NEG             │
│ - Points to GKE Service      │
└──────┬───────────────────────┘
       │ 4. VPC Peering
       ▼
┌──────────────────────────────┐
│ GKE Cluster (Tenant)         │
│ - Kubernetes Service         │
│ - Pod endpoints              │
└──────────────────────────────┘
```

---

### 7.2 Response Flow (Backend to Client)

```
┌──────────────────────────────┐
│ Pod (GKE Cluster)            │
│ - Processes request          │
│ - Returns response           │
└──────┬───────────────────────┘
       │ 1. Response to NEG
       ▼
┌──────────────────────────────┐
│ NEG (Tenant Project)         │
│ - Aggregates pod responses   │
└──────┬───────────────────────┘
       │ 2. VPC Peering
       ▼
┌──────────────────────────────┐
│ Backend Service              │
│ - Collects from all NEGs     │
└──────┬───────────────────────┘
       │ 3. Forward to Target Proxy
       ▼
┌──────────────────────────────┐
│ Target HTTPS Proxy           │
│ - Re-encrypts if needed      │
└──────┬───────────────────────┘
       │ 4. Forward to Forwarding Rule
       ▼
┌──────────────────────────────┐
│ Forwarding Rule              │
│ - Routes to client           │
└──────┬───────────────────────┘
       │ 5. HTTPS Response
       ▼
┌──────────────┐
│ Client VM    │
│ (Master VPC) │
└──────────────┘
```

---

### 7.3 Health Check Flow

```
┌──────────────────────────────┐
│ Health Check Service         │
│ (Master Project)             │
└──────┬───────────────────────┘
       │ 1. HTTP GET /health (every 30s)
       ▼
┌──────────────────────────────┐
│ VPC Peering                  │
└──────┬───────────────────────┘
       │ 2. Route to Tenant VPC
       ▼
┌──────────────────────────────┐
│ NEG Endpoints                │
│ (Tenant Project)             │
└──────┬───────────────────────┘
       │ 3. Forward to Pod
       ▼
┌──────────────────────────────┐
│ Pod (GKE)                    │
│ - Returns 200 OK             │
│ - Returns 500 if unhealthy   │
└──────────────────────────────┘
```

**Health Check Configuration:**
```yaml
checkIntervalSec: 30
timeoutSec: 5
healthyThreshold: 1
unhealthyThreshold: 2
requestPath: /health
port: 8080
```

---

## 8. Limitations and Quotas

### 8.1 GCP Quotas (Default)

| Resource | Default Limit | Can Increase | Notes |
|----------|---------------|--------------|-------|
| Backend Services per project | 500 | ✅ Yes | Request via support |
| NEGs per project | 1000 | ✅ Yes | Per zone |
| Cross-project NEG references | 100 | ✅ Yes | Per backend service |
| Internal LBs per region | 50 | ✅ Yes | Per project |
| Firewall rules per VPC | 200 | ✅ Yes | Consider using policies |
| VPC Peering connections | 25 | ✅ Yes | Per VPC |
| IAM policy bindings | 1500 | ✅ Yes | Per project |

**Check Your Quotas:**
```bash
gcloud compute project-info describe --project=${MASTER_PROJECT} \
  --format="table(quotas.metric,quotas.limit,quotas.usage)"
```

---

### 8.2 Performance Considerations

| Metric | Expected Value | Notes |
|--------|----------------|-------|
| **Latency (cross-project)** | +1-3ms | VPC peering overhead |
| **Throughput** | Up to 60 Gbps | Per LB |
| **Connections per second** | 1M+ | Depends on backend |
| **Health check delay** | 30-60s | To mark unhealthy |
| **NEG endpoint limit** | 1000 per NEG | Per zone |

---

### 8.3 Known Limitations

1. **Regional Scope:**
   - Internal HTTPS LB is regional
   - NEG must be in same region as LB
   - Cross-region requires Global LB

2. **NEG Types:**
   - Serverless NEG (GKE) supported ✅
   - VM-based NEG supported ✅
   - App Engine NEG supported ⚠️ (same region only)

3. **VPC Peering:**
   - Non-transitive routing
   - No overlapping CIDRs
   - Limited to 25 peerings per VPC (default)

4. **Cross-Project:**
   - Requires explicit IAM grants
   - Troubleshooting spans multiple projects
   - Audit logs in separate projects

---

## 9. Troubleshooting Guide

### 9.1 Common Issues and Solutions

#### Issue 1: Backend Shows "Unhealthy"

**Symptoms:**
```bash
gcloud compute backend-services get-health my-api-backend --global
# Output: healthStatus: UNHEALTHY
```

**Troubleshooting Steps:**

1. **Check NEG Health:**
   ```bash
   gcloud compute network-endpoint-groups get-health ${NEG_NAME} \
     --project=${TENANT_PROJECT} \
     --zone=${ZONE}
   ```

2. **Verify Pod Health:**
   ```bash
   kubectl get pods -n t1-api -l app=my-api
   kubectl logs -n t1-api -l app=my-api
   ```

3. **Test Health Endpoint:**
   ```bash
   kubectl exec -n t1-api <pod-name> -- curl -s http://localhost:8080/health
   ```

4. **Check Firewall Rules:**
   ```bash
   gcloud compute firewall-rules list \
     --project=${TENANT_PROJECT} \
     --filter="network=edmz-vpc"
   ```

5. **Verify VPC Peering:**
   ```bash
   gcloud compute networks peerings list \
     --project=${MASTER_PROJECT} \
     --filter="state!=ACTIVE"
   ```

---

#### Issue 2: 403 Permission Denied

**Symptoms:**
```bash
ERROR: (gcloud.compute.backend-services.add-backend) Could not fetch resource:
- Required 'compute.networks.use' permission for resource
```

**Solution:**

1. **Verify IAM Permissions:**
   ```bash
   gcloud projects get-iam-policy ${TENANT_PROJECT} \
     --flatten="bindings[].members" \
     --format="table(bindings.role)" \
     --filter="bindings.members:service-${MASTER_PROJECT_NUMBER}@compute-system"
   ```

2. **Grant Missing Permissions:**
   ```bash
   gcloud projects add-iam-policy-binding ${TENANT_PROJECT} \
     --member="serviceAccount:service-${MASTER_PROJECT_NUMBER}@compute-system.iam.gserviceaccount.com" \
     --role="roles/compute.networkUser"
   ```

---

#### Issue 3: Traffic Not Reaching Backend

**Symptoms:**
```bash
curl https://${ILB_IP}/health
# Connection timeout or 502 Bad Gateway
```

**Troubleshooting Steps:**

1. **Check Forwarding Rule:**
   ```bash
   gcloud compute forwarding-rules describe my-api-forwarding-rule \
     --project=${MASTER_PROJECT} \
     --region=asia-southeast1
   ```

2. **Verify Backend Service:**
   ```bash
   gcloud compute backend-services describe my-api-backend \
     --project=${MASTER_PROJECT} \
     --global
   ```

3. **Check Load Balancer Logs:**
   ```bash
   gcloud logging read \
     "resource.type=\"http_load_balancer\" AND \
      severity>=ERROR" \
     --project=${MASTER_PROJECT} \
     --limit=20
   ```

4. **Test from VM in Master VPC:**
   ```bash
   gcloud compute ssh test-vm \
     --project=${MASTER_PROJECT} \
     --zone=asia-southeast1-a \
     --command="curl -k https://${ILB_IP}/health"
   ```

5. **Check VPC Flow Logs:**
   ```bash
   gcloud logging read \
     "resource.type=\"gce_subnetwork\" AND \
      jsonPayload.connection.src_ip=\"${ILB_IP}\"" \
     --project=${MASTER_PROJECT} \
     --limit=10
   ```

---

#### Issue 4: Certificate Validation Failed

**Symptoms:**
```bash
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

**Solution:**

1. **Verify Certificate Chain:**
   ```bash
   openssl x509 -in my-api.crt -text -noout
   ```

2. **Check Certificate Expiry:**
   ```bash
   gcloud compute ssl-certificates describe my-api-cert \
     --project=${MASTER_PROJECT}
   ```

3. **Use CA Bundle:**
   ```bash
   curl --cacert ca-bundle.crt https://${ILB_IP}/health
   ```

---

### 9.2 Diagnostic Commands Reference

```bash
# Check all LB components
gcloud compute target-https-proxies describe my-api-proxy --project=${MASTER_PROJECT}
gcloud compute url-maps describe my-api-url-map --project=${MASTER_PROJECT}
gcloud compute backend-services describe my-api-backend --project=${MASTER_PROJECT}
gcloud compute forwarding-rules describe my-api-forwarding-rule --project=${MASTER_PROJECT} --region=asia-southeast1

# Check NEG status
gcloud compute network-endpoint-groups list --project=${TENANT_PROJECT}
gcloud compute network-endpoint-groups get-health ${NEG_NAME} --project=${TENANT_PROJECT} --zone=${ZONE}

# Check VPC connectivity
gcloud compute networks peerings list --project=${MASTER_PROJECT}
gcloud compute routes list --project=${MASTER_PROJECT}

# Check firewall rules
gcloud compute firewall-rules list --project=${MASTER_PROJECT} --format="table(name,direction,sourceRanges,targetTags)"
gcloud compute firewall-rules list --project=${TENANT_PROJECT} --format="table(name,direction,sourceRanges,targetTags)"

# Check IAM permissions
gcloud projects get-iam-policy ${MASTER_PROJECT}
gcloud projects get-iam-policy ${TENANT_PROJECT}

# Real-time monitoring
gcloud logging tail --filter="resource.type=\"http_load_balancer\""
```

---

## 10. Comparison Matrix

### 10.1 Solution Comparison

| Criteria | Direct Cross-Project | Shared VPC | Nginx L7 Proxy |
|----------|---------------------|------------|---------------|
| **Complexity** | Medium | Low | High |
| **Isolation** | High | Medium | High |
| **Performance** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Flexibility** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Cloud Native** | ✅ Yes | ✅ Yes | ⚠️ Partial |
| **Maintenance** | Medium | Low | High |
| **Cost** | $ | $ | $$ (VM costs) |
| **Recommended** | ✅ **Yes** | ⚠️ Maybe | ❌ No |

---

### 10.2 Feature Comparison

| Feature | Direct Cross-Project | Shared VPC | Nginx L7 Proxy |
|---------|---------------------|------------|----------------|
| Cross-project IAM | Required | Not required | Required |
| VPC Peering | Required | Not required | Required |
| Cloud Armor | ✅ Supported | ✅ Supported | ⚠️ Manual |
| Cloud CDN | ✅ Supported | ✅ Supported | ❌ Not supported |
| Auto-scaling | ✅ Automatic | ✅ Automatic | ⚠️ Manual |
| Health Checks | ✅ Managed | ✅ Managed | ⚠️ Self-managed |
| TLS Termination | ✅ Managed | ✅ Managed | ⚠️ Self-managed |
| Monitoring | ✅ Cloud Monitoring | ✅ Cloud Monitoring | ⚠️ Custom |
| Logging | ✅ Cloud Logging | ✅ Cloud Logging | ⚠️ Custom |

---

## 11. Recommendations

### 11.1 Architecture Recommendation

**For Your Multi-Tenant Platform:**

✅ **Recommended: Model A (Direct Cross-Project Backend Service)**

**Rationale:**
1. Aligns with your 1 Team = 1 Project model
2. Maintains strong tenant isolation
3. Cloud-native and fully managed
4. Integrates with existing Cloud Armor and Cert Manager
5. Minimal operational overhead

**Implementation Priority:**
1. Start with non-production POC (1 tenant)
2. Validate end-to-end connectivity
3. Implement monitoring and alerting
4. Create Terraform modules
5. Roll out to production tenants

---

### 11.2 Security Recommendations

1. **Use Private CA for certificates**
   - Don't use self-signed in production
   - Implement automatic certificate rotation

2. **Implement Cloud Armor policies**
   - Restrict to internal IP ranges
   - Add rate limiting and DDoS protection

3. **Enable VPC Flow Logs**
   - Critical for troubleshooting
   - Required for compliance

4. **Audit IAM permissions quarterly**
   - Remove unused service account grants
   - Implement least privilege

---

### 11.3 Operational Recommendations

1. **Infrastructure as Code:**
   - Use Terraform for all LB resources
   - Version control all configurations
   - Implement CI/CD for infrastructure changes

2. **Monitoring and Alerting:**
   ```yaml
   Alerts to implement:
   - Backend unhealthy (>50% endpoints)
   - High error rate (>5% 5xx responses)
   - High latency (p99 > 500ms)
   - Certificate expiry (<30 days)
   - VPC peering state changes
   ```

3. **Documentation:**
   - Document network topology
   - Maintain runbook for troubleshooting
   - Create escalation procedures

4. **Testing:**
   - Regular failover tests
   - Load testing before production rollout
   - Security penetration testing

---

### 11.4 Migration Path

**Phase 1: Foundation (Week 1-2)**
- Set up VPC peering
- Configure IAM permissions
- Deploy test GKE service

**Phase 2: POC (Week 3-4)**
- Create cross-project backend service
- Deploy Internal HTTPS LB
- Test end-to-end connectivity

**Phase 3: Production (Week 5-8)**
- Implement monitoring and alerting
- Create Terraform modules
- Roll out to first production tenant

**Phase 4: Scale (Week 9+)**
- Automate tenant onboarding
- Implement guardrails
- Optimize performance

---

## 12. Appendix

### 12.1 Terraform Module Example

```hcl
# Cross-Project Internal HTTPS LB

variable "master_project" {
  type = string
}

variable "tenant_project" {
  type = string
}

variable "region" {
  type = string
}

variable "neg_name" {
  type = string
}

variable "neg_zone" {
  type = string
}

# Backend Service
resource "google_compute_backend_service" "cross_project" {
  name                  = "my-api-backend"
  project               = var.master_project
  protocol              = "HTTPS"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_health_check.default.id]

  backend {
    group          = "https://www.googleapis.com/compute/v1/projects/${var.tenant_project}/zones/${var.neg_zone}/networkEndpointGroups/${var.neg_name}"
    balancing_mode = "RATE"
    max_rate_per_endpoint = 100
  }
}

# Health Check
resource "google_compute_health_check" "default" {
  name    = "my-api-health-check"
  project = var.master_project

  https_health_check {
    port     = 8080
    request_path = "/health"
  }
}

# Internal HTTPS LB
resource "google_compute_forwarding_rule" "ilb" {
  name                  = "my-api-ilb"
  project               = var.master_project
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  network               = "idmz-vpc"
  subnetwork            = "idmz-subnet"
  ip_protocol           = "TCP"
  ports                 = [443]
  target                = google_compute_target_https_proxy.default.id
}

resource "google_compute_target_https_proxy" "default" {
  name    = "my-api-proxy"
  project = var.master_project
  url_map = google_compute_url_map.default.id
  ssl_certificates = [google_compute_ssl_certificate.default.id]
}

resource "google_compute_url_map" "default" {
  name    = "my-api-url-map"
  project = var.master_project
  default_service = google_compute_backend_service.cross_project.id
}

resource "google_compute_ssl_certificate" "default" {
  name    = "my-api-cert"
  project = var.master_project
  certificate = file("certs/my-api.crt")
  private_key = file("certs/my-api.key")
}
```

---

### 12.2 Checklist for Production Deployment

**Pre-Deployment:**
- [ ] VPC peering established and ACTIVE
- [ ] IAM permissions granted
- [ ] Firewall rules configured
- [ ] Health check endpoint validated
- [ ] Certificate issued and uploaded
- [ ] NEG created and healthy

**Deployment:**
- [ ] Backend service created
- [ ] NEG added as backend
- [ ] Health check passing
- [ ] LB components created
- [ ] Forwarding rule active

**Post-Deployment:**
- [ ] End-to-end connectivity tested
- [ ] Monitoring dashboards created
- [ ] Alerts configured
- [ ] Runbook documented
- [ ] Team trained on troubleshooting

---

### 12.3 References

- [Cross-Project Load Balancing](https://cloud.google.com/load-balancing/docs/cross-project-load-balancing)
- [Serverless NEG](https://cloud.google.com/load-balancing/docs/negs/serverless-neg-concepts)
- [Internal HTTPS LB](https://cloud.google.com/load-balancing/docs/l7-internal)
- [VPC Peering](https://cloud.google.com/vpc/docs/vpc-peering)
- [IAM for Cross-Project](https://cloud.google.com/iam/docs/cross-project-access)

---

### 12.4 Glossary

| Term | Definition |
|------|------------|
| **ILB** | Internal Load Balancer |
| **NEG** | Network Endpoint Group |
| **VPC** | Virtual Private Cloud |
| **IDMZ** | Internal Demilitarized Zone (Master Project) |
| **EDMZ** | External Demilitarized Zone (Tenant Project) |
| **L7** | Layer 7 (Application Layer) |
| **Cloud Armor** | GCP WAF and DDoS protection |

---

## Summary

### Key Takeaways:

1. ✅ **Cross-project Internal HTTPS LB is feasible** and supported by GCP
2. ✅ **Direct Backend Service reference** is the recommended approach
3. ✅ **VPC Peering + IAM** are the two critical prerequisites
4. ✅ **Cloud-native and fully managed** - no need for Nginx L7 proxy
5. ⚠️ **Requires careful IAM and network configuration**
6. ⚠️ **Troubleshooting spans multiple projects**

### Next Steps:

1. **Week 1**: Set up VPC peering and IAM
2. **Week 2**: Deploy POC with test service
3. **Week 3**: Validate and test end-to-end
4. **Week 4**: Create Terraform modules
5. **Week 5+**: Production rollout

---

**Document Owner**: Infrastructure Team  
**Review Cycle**: Quarterly  
**Feedback**: Contact platform-architecture@aibang.com
