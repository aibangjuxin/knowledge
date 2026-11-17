# End-to-End Gloo Gateway Installation on GKE

> **Document Purpose**: Complete step-by-step guide for installing Gloo Gateway on Google Kubernetes Engine (GKE), from cluster preparation to deploying an accessible API service.
>
> **Target Audience**: Platform engineers, SREs, and DevOps teams replacing Google Cloud Service Mesh (ASM) with Gloo Gateway.
>
> **Background**: This guide focuses on Gloo Gateway as a standalone API Gateway solution, ideal for organizations that need ingress/gateway capabilities without the full service mesh management plane. It provides a simpler alternative to Gloo Mesh Enterprise while still offering enterprise-grade features.
>
> **Version**: Gloo Gateway 1.17.x / Gloo Platform 2.x

---

## Table of Contents

1. [Overview and Concepts](#1-overview-and-concepts)
2. [Prerequisites](#2-prerequisites)
3. [Step 1: GKE Cluster Setup](#3-step-1-gke-cluster-setup)
4. [Step 2: Install Required Tools](#4-step-2-install-required-tools)
5. [Step 3: Install Gloo Gateway](#5-step-3-install-gloo-gateway)
6. [Step 4: Verify Gateway Installation](#6-step-4-verify-gateway-installation)
7. [Step 5: Deploy Sample Backend Application](#7-step-5-deploy-sample-backend-application)
8. [Step 6: Configure Routing](#8-step-6-configure-routing)
9. [Step 7: Test External Access](#9-step-7-test-external-access)
10. [Step 8: Validation and Troubleshooting](#10-step-8-validation-and-troubleshooting)
11. [Appendix: YAML Files Reference](#appendix-yaml-files-reference)

---

## 1. Overview and Concepts

### 1.1 Why Gloo Gateway?

Gloo Gateway is an Envoy-based API Gateway that provides:

- **Native Kubernetes Integration**: Built on Kubernetes Gateway API
- **Advanced Routing**: Content-based routing, transformations, and middleware
- **Traffic Management**: Canary deployments, rate limiting, circuit breaking
- **Security**: mTLS, OAuth, JWT validation, WAF support
- **Observability**: Distributed tracing, metrics, access logs

### 1.2 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        GCP GKE Cluster                          │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                   gloo-gateway Namespace                   │ │
│  │  ┌─────────────────────┐  ┌─────────────────────────────┐  │ │
│  │  │   gloo-gateway      │  │         istiod             │  │ │
│  │  │   (Envoy Proxy)     │  │   (Istio Control Plane)   │  │ │
│  │  │   LoadBalancer      │  │                            │  │ │
│  │  │   :8080, :8443      │  │   :15010, :15012          │  │ │
│  │  └─────────────────────┘  └─────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                minimax-runtime Namespace                  │ │
│  │  ┌─────────────────────┐  ┌─────────────────────────────┐  │ │
│  │  │    minimax-api      │  │       istio-proxy         │  │ │
│  │  │    (nginx)          │  │       (sidecar)           │  │ │
│  │  │    Pod              │  │                            │  │ │
│  │  └─────────────────────┘  └─────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  External Traffic → GCLB → Gloo Gateway → minimax-api          │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 Key Concepts

| Concept | Description |
|---------|-------------|
| **VirtualGateway** | Defines the ingress listener configuration (ports, TLS, etc.) |
| **RouteTable** | Defines routing rules (URI matching, destination selection) |
| **Gateway Proxy** | Envoy-based data plane that handles traffic |
| **Istiod** | Istio control plane that manages the service mesh |
| **Sidecar Proxy** | Envoy sidecar injected into workload pods |

### 1.4 What This Guide Covers

This guide provides a simplified installation focusing on:
- Gloo Gateway as the API Gateway (without full Gloo Mesh management plane)
- Using Istio for the data plane (optional, for mTLS support)
- Basic routing configuration
- End-to-end accessibility testing

---

## 2. Prerequisites

### 2.1 GCP Permissions

Ensure your GCP account has the following roles:

```bash
# Required IAM roles
roles/container.admin        # Kubernetes Engine Admin
roles/iam.serviceAccountAdmin # Service Account Admin (if using Workload Identity)
```

### 2.2 Required Tools

| Tool | Minimum Version | Purpose |
|------|-----------------|---------|
| `gcloud` | 400.0.0+ | GCP CLI |
| `kubectl` | 1.28+ | Kubernetes CLI |
| `helm` | 3.12+ | Helm Package Manager |

### 2.3 Environment Variables

Set the following environment variables for your session:

```bash
# GCP Configuration
export GCP_PROJECT_ID="your-gcp-project-id"
export GCP_REGION="us-central1"
export GKE_CLUSTER_NAME="gloo-minimax-cluster"

# Gloo Configuration
export GLOO_VERSION="1.17.5"  # Check latest at https://docs.solo.io/gloo-gateway/
export GATEWAY_NAMESPACE="gloo-gateway"
export WORKLOAD_NAMESPACE="minimax-runtime"

# Gateway IP (will be set later)
export GATEWAY_IP=""
```

---

## 3. Step 1: GKE Cluster Setup

### 3.1 Create GKE Cluster

Create a GKE cluster with recommended settings for Gloo Gateway:

```bash
gcloud container clusters create ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION} \
  --cluster-version=1.28 \
  --machine-type=e2-standard-4 \
  --num-nodes=3 \
  --enable-autoscaling \
  --min-nodes=3 \
  --max-nodes=5 \
  --enable-autoupgrade \
  --enable-autorepair \
  --disk-size=50 \
  --disk-type=pd-balanced \
  --enable-ip-alias \
  --enable-intra-node-visibility \
  --labels="env=prod,app=gloo-gateway"
```

**Parameter Explanations**:
- `e2-standard-4`: 4 vCPU, 16GB RAM - adequate for gateway + workloads
- `--enable-autoscaling`: Automatically adjust node count based on load
- `--enable-ip-alias`: VPC-native cluster networking (recommended)
- `--enable-intra-node-visibility`: Allow pods to communicate directly

### 3.2 Configure kubectl Context

```bash
# Get credentials for the cluster
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION}

# Verify connection
kubectl cluster-info

# Verify node access
kubectl get nodes
```

**Expected Output**:
```
Kubernetes control plane is running at https://XXX.XXX.XXX.XXX
GKE control plane is running at https://XXX.XXX.XXX.XXX

NAME                              STATUS   ROLES    AGE   VERSION
gke-gloo-minimax-cluster-xxx      Ready    <none>   5m    v1.28.X
gke-gloo-minimax-cluster-xxx      Ready    <none>   5m    v1.28.X
gke-gloo-minimax-cluster-xxx      Ready    <none>   5m    v1.28.X
```

### 3.3 Create Namespaces

```bash
# Create namespace for Gloo Gateway
kubectl create namespace ${GATEWAY_NAMESPACE}

# Create namespace for workloads
kubectl create namespace ${WORKLOAD_NAMESPACE}

# Create namespace for Istio (required for mTLS)
kubectl create namespace istio-system

# Enable automatic sidecar injection
kubectl label namespace ${GATEWAY_NAMESPACE} istio-injection=enabled --overwrite
kubectl label namespace ${WORKLOAD_NAMESPACE} istio-injection=enabled --overwrite

# Verify namespaces
kubectl get namespaces
```

---

## 4. Step 2: Install Required Tools

### 4.1 Install Helm

```bash
# macOS (using Homebrew)
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version

# Expected output:
# version.BuildInfo{Version:"v3.14.0", ...}
```

### 4.2 Add Gloo Gateway Helm Repository

```bash
# Add Gloo Platform Helm repository
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts

# Update repository
helm repo update

# Search for available charts
helm search repo gloo-platform

# Expected output (partial):
# NAME                            CHART VERSION   APP VERSION
# gloo-platform/gloo-platform     2.1.0           2.1.0
# gloo-platform/gloo-gateway       1.17.5          1.17.5
```

### 4.3 Install glooctl (Optional - for diagnostics)

```bash
# Download and install glooctl
curl -sL https://run.solo.io/gloo/install | sh

# Move to PATH
export PATH=$HOME/.gloo/bin:$PATH

# Verify installation
glooctl version

# Expected output:
# {"glooctl":"1.17.5","gloo":"1.17.5"}
```

---

## 5. Step 3: Install Gloo Gateway

### 5.1 Install Gloo Gateway using Helm

```bash
# Install Gloo Gateway with custom values
helm install gloo-gateway gloo-platform/gloo-gateway \
  --namespace ${GATEWAY_NAMESPACE} \
  --create-namespace \
  --version ${GLOO_VERSION} \
  -f yamls/minimax/gateway-values.yaml \
  --wait \
  --timeout 5m

# Alternative: Install with inline values
helm install gloo-gateway gloo-platform/gloo-gateway \
  --namespace ${GATEWAY_NAMESPACE} \
  --create-namespace \
  --version ${GLOO_VERSION} \
  --set glooGateway.gatewayProxies.gatewayProxy.service.type=LoadBalancer \
  --set glooGateway.gatewayProxies.gatewayProxy.service.annotations.service.beta.kubernetes.io/gcp-load-balancer-type=External \
  --wait \
  --timeout 5m
```

**Key Configuration Parameters**:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `glooGateway.enabled` | Enable Gloo Gateway | true |
| `gatewayProxies.gatewayProxy.service.type` | Service type | LoadBalancer |
| `gatewayProxies.gatewayProxy.deployment.replicas` | Number of replicas | 2 |
| `istio.enabled` | Enable Istio integration | true |

### 5.2 Verify Installation

```bash
# Wait for pods to be ready
kubectl wait --for=condition=Ready pods --all -n ${GATEWAY_NAMESPACE} --timeout=300s

# Check pod status
kubectl get pods -n ${GATEWAY_NAMESPACE}

# Expected output:
# NAME                             READY   STATUS    RESTARTS   AGE
# gloo-gateway-xxxxx               1/1     Running   0          2m
# gloo-gateway-xxxxx               1/1     Running   0          2m
# istiod-xxxxx                     1/1     Running   0          3m
```

### 5.3 Get Gateway External IP

```bash
# Get the external IP of the LoadBalancer
kubectl get svc -n ${GATEWAY_NAMESPACE}

# Expected output:
# NAME                 TYPE           CLUSTER-IP    EXTERNAL-IP    PORT(S)                      AGE
# gloo-gateway-proxy   LoadBalancer   10.0.XXX.XXX  34.XXX.XXX.XXX  8080:31234/TCP,8443:31235/TCP  3m

# Save the IP for later use
export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Gateway External IP: ${GATEWAY_IP}"

# If IP is pending, wait and retry
while [ -z "${GATEWAY_IP}" ]; do
  echo "Waiting for LoadBalancer IP..."
  sleep 10
  export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
done
```

---

## 6. Step 4: Verify Gateway Installation

### 6.1 Check Gateway Health

```bash
# Check all Gloo Gateway resources
kubectl get all -n ${GATEWAY_NAMESPACE}

# Check Gateway CRDs are installed
kubectl get crds | grep gloo

# Expected output (partial):
# gateways.networking.gloo.solo.io
# virtualgateways.networking.gloo.solo.io
# routetables.networking.gloo.solo.io
# proxies.gloo.solo.io
```

### 6.2 Verify Envoy Configuration

```bash
# Get the gateway pod name
GATEWAY_POD=$(kubectl get pods -n ${GATEWAY_NAMESPACE} -l app=gloo-gateway -o jsonpath='{.items[0].metadata.name}')

# Check Envoy configuration
kubectl exec -n ${GATEWAY_NAMESPACE} ${GATEWAY_POD} -c gloo-gateway-proxy -- cat /etc/envoy/envoy.yaml | head -50

# Alternatively, check the Envoy admin interface
kubectl port-forward -n ${GATEWAY_NAMESPACE} ${GATEWAY_POD} 15000:15000 &
sleep 2
curl http://localhost:15000/server_info
```

### 6.3 Test Internal Connectivity

```bash
# Create a test pod
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- sh

# From the test pod, check gateway health
kubectl exec -it curl-test -- curl -s http://gloo-gateway.${GATEWAY_NAMESPACE}.svc.cluster.local:8080/

# Test from gateway to backend (internal)
kubectl run -n ${GATEWAY_NAMESPACE} -it curl-test --image=curlimages/curl --rm -- \
  curl -s http://minimax-api.${WORKLOAD_NAMESPACE}.svc.cluster.local:8080/healthz

# Expected output: OK
```

---

## 7. Step 5: Deploy Sample Backend Application

### 5.1 Apply Backend Deployment and Service

```bash
# Apply the backend deployment
kubectl apply -f yamls/minimax/02-backend-deployment.yaml

# Apply the service
kubectl apply -f yamls/minimax/03-backend-service.yaml

# Verify deployment
kubectl get deployment -n ${WORKLOAD_NAMESPACE}

# Expected output:
# NAME         READY   UP-TO-DATE   AVAILABLE
# minimax-api  2/2     2            2

# Verify pods (should show 2/2 = app + istio-proxy)
kubectl get pods -n ${WORKLOAD_NAMESPACE}

# Expected output:
# NAME                          READY   STATUS    RESTARTS   AGE
# minimax-api-xxxxx-xxxxx       2/2     Running   0          1m
# minimax-api-xxxxx-xxxxx       2/2     Running   0          1m

# Verify service
kubectl get svc -n ${WORKLOAD_NAMESPACE}

# Expected output:
# NAME         TYPE        CLUSTER-IP    PORT(S)    AGE
# minimax-api  ClusterIP   10.0.XXX.XXX  8080/TCP   1m
```

### 5.2 Verify Sidecar Injection

```bash
# Check that istio-proxy sidecar is injected
kubectl get pod -n ${WORKLOAD_NAMESPACE} -l app=minimax-api -o jsonpath='{.items[0].spec.containers[*].name}'

# Expected output: nginx istio-proxy

# Verify istio-proxy configuration
kubectl get pod -n ${WORKLOAD_NAMESPACE} -l app=minimax-api -o yaml | grep -A 20 'istio-proxy'
```

### 5.3 Test Backend Internal Access

```bash
# Test from a debug container
kubectl run -n ${WORKLOAD_NAMESPACE} -it debug-pod --image=busybox:1.36 --rm -- sh

# Inside the pod, test connectivity
wget -qO- http://minimax-api.minimax-runtime.svc.cluster.local:8080/healthz
# Expected: OK

wget -qO- http://minimax-api.minimax-runtime.svc.cluster.local:8080/
# Expected: HTML page

exit
```

---

## 8. Step 6: Configure Routing

### 6.1 Create VirtualGateway

```bash
# Apply VirtualGateway configuration
kubectl apply -f yamls/minimax/04-virtual-gateway.yaml

# Verify VirtualGateway
kubectl get virtualgateway -n gloo-gateway

# Expected output:
# NAME             AGE
# minimax-gateway  10s

# Check VirtualGateway details
kubectl get virtualgateway -n gloo-gateway minimax-gateway -o yaml
```

**VirtualGateway Explanation**:
- `workloads`: Specifies which Gateway proxy pods to use (gloo-gateway)
- `listeners`: Defines ports 8080 (HTTP) and 8443 (HTTPS)
- `allowedRouteTables`: Specifies which RouteTables can bind to this gateway

### 6.2 Create RouteTable

```bash
# Apply RouteTable configuration
kubectl apply -f yamls/minimax/05-route-table.yaml

# Verify RouteTable
kubectl get routetable -n ${WORKLOAD_NAMESPACE}

# Expected output:
# NAME            AGE
# minimax-routes  5s

# Check RouteTable details
kubectl get routetable -n ${WORKLOAD_NAMESPACE} minimax-routes -o yaml
```

**RouteTable Explanation**:
- `hosts`: Defines which Host headers to match ("*" for any)
- `virtualGateways`: Binds to the VirtualGateway
- `http`: Defines routing rules with matchers and destinations

### 6.3 Verify Route Translation

```bash
# Check if Gloo translated RouteTable to Istio VirtualService
kubectl get virtualservice -n ${WORKLOAD_NAMESPACE}

# Check if Istio Gateway was created
kubectl get gateway -n ${WORKLOAD_NAMESPACE}

# Verify the gateway is linked to the VirtualGateway
kubectl get gateway -n ${WORKLOAD_NAMESPACE} -o yaml
```

---

## 9. Step 7: Test External Access

### 7.1 Get Gateway External IP

```bash
# Get the current Gateway IP
export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Testing against Gateway IP: ${GATEWAY_IP}"

# If IP is still pending
if [ -z "${GATEWAY_IP}" ]; then
  echo "Gateway IP not assigned yet. Waiting..."
  kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -w
fi
```

### 7.2 Test HTTP Access

```bash
# Test 1: Root path (default route)
curl -s http://${GATEWAY_IP}:8080/

# Test 2: Health check endpoint
curl -s http://${GATEWAY_IP}:8080/healthz

# Test 3: API endpoint
curl -s http://${GATEWAY_IP}:8080/api/minimax

# Test 4: Verbose output for debugging
curl -v http://${GATEWAY_IP}:8080/api/minimax 2>&1 | head -30
```

**Expected Results**:
```
# Test 1 - Root path:
<!DOCTYPE html>
<html>
<head><title>MiniMax API Service</title>...
</head>
<body>...
</body>
</html>

# Test 2 - Health check:
OK

# Test 3 - API endpoint:
{"service":"minimax-api","version":"v1","pod":"minimax-api-xxxxx","namespace":"minimax-runtime"}
```

### 7.3 Test with Custom Host Header

```bash
# Test with Host header (simulates DNS-based routing)
curl -s -H "Host: api.example.com" http://${GATEWAY_IP}:8080/api/minimax

# Test with different paths
curl -s http://${GATEWAY_IP}:8080/api/minimax/info
```

---

## 10. Step 8: Validation and Troubleshooting

### 8.1 End-to-End Validation Script

```bash
#!/bin/bash
# e2e-validation.sh - Complete E2E validation script

set -e

# Configuration
export GATEWAY_NAMESPACE="gloo-gateway"
export WORKLOAD_NAMESPACE="minimax-runtime"

echo "========================================"
echo "Gloo Gateway E2E Validation"
echo "========================================"

# Get Gateway IP
echo ""
echo "[1/6] Getting Gateway IP..."
export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || echo "")
if [ -z "${GATEWAY_IP}" ]; then
  echo "ERROR: Gateway IP not assigned"
  exit 1
fi
echo "Gateway IP: ${GATEWAY_IP}"

# Check Gateway Pods
echo ""
echo "[2/6] Checking Gateway Pods..."
kubectl get pods -n ${GATEWAY_NAMESPACE} -l app=gloo-gateway
GATEWAY_PODS=$(kubectl get pods -n ${GATEWAY_NAMESPACE} -l app=gloo-gateway --no-headers | grep Running | wc -l)
if [ "${GATEWAY_PODS}" -lt 1 ]; then
  echo "ERROR: Gateway pods not running"
  exit 1
fi
echo "Gateway pods: OK"

# Check Backend Pods
echo ""
echo "[3/6] Checking Backend Pods..."
kubectl get pods -n ${WORKLOAD_NAMESPACE} -l app=minimax-api
BACKEND_PODS=$(kubectl get pods -n ${WORKLOAD_NAMESPACE} -l app=minimax-api --no-headers | grep Running | wc -l)
if [ "${BACKEND_PODS}" -lt 1 ]; then
  echo "ERROR: Backend pods not running"
  exit 1
fi
echo "Backend pods: OK"

# Test External Access
echo ""
echo "[4/6] Testing External Access..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://${GATEWAY_IP}:8080/api/minimax || echo "000")
echo "HTTP Response Code: ${HTTP_CODE}"
if [ "${HTTP_CODE}" != "200" ]; then
  echo "ERROR: External access failed"
  exit 1
fi
echo "External access: OK"

# Test Health Endpoint
echo ""
echo "[5/6] Testing Health Endpoint..."
HEALTH=$(curl -s http://${GATEWAY_IP}:8080/healthz)
echo "Health Response: ${HEALTH}"
if [ "${HEALTH}" != "OK" ]; then
  echo "ERROR: Health check failed"
  exit 1
fi
echo "Health check: OK"

# Test API Response
echo ""
echo "[6/6] Testing API Response..."
API_RESPONSE=$(curl -s http://${GATEWAY_IP}:8080/api/minimax)
echo "API Response: ${API_RESPONSE}"
echo "${API_RESPONSE}" | grep -q "minimax-api" || { echo "ERROR: Invalid API response"; exit 1; }
echo "API response: OK"

echo ""
echo "========================================"
echo "All E2E Tests Passed!"
echo "========================================"
echo ""
echo "Access your service at: http://${GATEWAY_IP}:8080/"
echo "API endpoint: http://${GATEWAY_IP}:8080/api/minimax"
```

Run the validation script:
```bash
chmod +x yamls/minimax/e2e-validation.sh
bash yamls/minimax/e2e-validation.sh
```

### 8.2 Manual Validation Commands

```bash
# ─── Check All Resources ────────────────────

# List all Gloo resources
kubectl get virtualgateway,routetable -A

# Check VirtualGateway status
kubectl get virtualgateway -n ${GATEWAY_NAMESPACE} -o wide

# Check RouteTable status
kubectl get routetable -n ${WORKLOAD_NAMESPACE} -o wide

# ─── Check Pod Health ────────────────────────

# Gateway pods
kubectl get pods -n ${GATEWAY_NAMESPACE}

# Backend pods
kubectl get pods -n ${WORKLOAD_NAMESPACE}

# ─── Check Service Endpoints ─────────────────

# Gateway service
kubectl get svc -n ${GATEWAY_NAMESPACE}

# Backend service and endpoints
kubectl get svc,endpoints -n ${WORKLOAD_NAMESPACE}

# ─── Debug Routing ────────────────────────────

# Check VirtualService translation
kubectl get virtualservice -n ${WORKLOAD_NAMESPACE} -o yaml

# Check Gateway translation
kubectl get gateway -n ${WORKLOAD_NAMESPACE} -o yaml

# ─── View Logs ────────────────────────────────

# Gateway logs
kubectl logs -n ${GATEWAY_NAMESPACE} -l app=gloo-gateway --tail=50

# Backend logs
kubectl logs -n ${WORKLOAD_NAMESPACE} -l app=minimax-api --tail=50

# Istio-proxy logs (if using Istio)
kubectl logs -n ${WORKLOAD_NAMESPACE} -l app=minimax-api -c istio-proxy --tail=50
```

### 8.3 Common Issues and Solutions

#### Issue 1: Gateway LoadBalancer IP Not Assigned

**Symptoms**: `EXTERNAL-IP` shows `<pending>`

**Solutions**:
```bash
# Check service status
kubectl describe svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy

# Check GCP Load Balancer creation
gcloud compute forwarding-rules list --project=${GCP_PROJECT_ID}
gcloud compute target-pools list --project=${GCP_PROJECT_ID}

# Check firewall rules (required for GCLB)
gcloud compute firewall-rules list --project=${GCP_PROJECT_ID} | grep gke
```

#### Issue 2: 503 Service Unavailable

**Symptoms**: HTTP 503 when accessing through gateway

**Solutions**:
```bash
# Check backend pods are running
kubectl get pods -n ${WORKLOAD_NAMESPACE}

# Check endpoints exist
kubectl get endpoints -n ${WORKLOAD_NAMESPACE} minimax-api

# Verify RouteTable is correctly configured
kubectl get routetable -n ${WORKLOAD_NAMESPACE} minimax-routes -o yaml

# Check if VirtualService was created
kubectl get virtualservice -n ${WORKLOAD_NAMESPACE}
```

#### Issue 3: RouteTable Not Binding to VirtualGateway

**Symptoms**: Routes not working, no errors visible

**Solutions**:
```bash
# Check VirtualGateway configuration
kubectl get virtualgateway -n ${GATEWAY_NAMESPACE} minimax-gateway -o yaml

# Verify allowedRouteTables in VirtualGateway
# Should include the namespace where RouteTable is defined

# Check RouteTable virtualGateways reference
kubectl get routetable -n ${WORKLOAD_NAMESPACE} minimax-routes -o yaml | grep -A 5 virtualGateways
```

#### Issue 4: TLS/SSL Errors (HTTPS)

**Symptoms**: SSL certificate errors when using port 8443

**Solutions**:
```bash
# Check if TLS secret exists
kubectl get secrets -n ${GATEWAY_NAMESPACE}

# Create TLS secret (if using custom certificate)
kubectl create secret tls gateway-tls-secret \
  --cert=path/to/certificate.crt \
  --key=path/to/private.key \
  -n ${GATEWAY_NAMESPACE}

# For testing with HTTP only, remove TLS listener from VirtualGateway
```

---

## Appendix: YAML Files Reference

### A.1 Namespace Configuration (yamls/minimax/01-namespace.yaml)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: gloo-gateway
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: Namespace
metadata:
  name: minimax-runtime
  labels:
    istio-injection: enabled
```

### A.2 Backend Deployment (yamls/minimax/02-backend-deployment.yaml)

See the full file at [`yamls/minimax/02-backend-deployment.yaml`](yamls/minimax/02-backend-deployment.yaml).

Key components:
- ConfigMap with nginx configuration
- Deployment with 2 replicas
- Readiness and liveness probes
- Volume mounts for configuration

### A.3 Backend Service (yamls/minimax/03-backend-service.yaml)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: minimax-api
  namespace: minimax-runtime
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: minimax-api
```

### A.4 VirtualGateway (yamls/minimax/04-virtual-gateway.yaml)

```yaml
apiVersion: networking.gloo.solo.io/v2
kind: VirtualGateway
metadata:
  name: minimax-gateway
  namespace: gloo-gateway
spec:
  workloads:
  - selector:
      labels:
        app: gloo-gateway
      namespace: gloo-gateway
  listeners:
  - http: {}
    port:
      number: 8080
    allowedRouteTables:
    - host: "*"
```

### A.5 RouteTable (yamls/minimax/05-route-table.yaml)

```yaml
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: minimax-routes
  namespace: minimax-runtime
spec:
  hosts:
  - "*"
  virtualGateways:
  - name: minimax-gateway
    namespace: gloo-gateway
  http:
  - name: minimax-api-route
    matchers:
    - uri:
        prefix: /api/minimax
    forwardTo:
      destinations:
      - ref:
          name: minimax-api
          namespace: minimax-runtime
        port:
          number: 8080
```

### A.6 Gateway Values (yamls/minimax/gateway-values.yaml)

```yaml
glooGateway:
  enabled: true
  gatewayProxies:
    gatewayProxy:
      service:
        type: LoadBalancer
        annotations:
          service.beta.kubernetes.io/gcp-load-balancer-type: "External"
      deployment:
        replicas: 2

istio:
  enabled: true
  istiod:
    enabled: true
```

---

## Quick Reference Cheatsheet

### Installation Commands

```bash
# 1. Create cluster
gcloud container clusters create gloo-minimax-cluster --project=YOUR_PROJECT --location=us-central1 --machine-type=e2-standard-4 --num-nodes=3

# 2. Add Helm repo
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts
helm repo update

# 3. Install Gloo Gateway
helm install gloo-gateway gloo-platform/gloo-gateway --namespace gloo-gateway --create-namespace --version 1.17.5 --set glooGateway.gatewayProxies.gatewayProxy.service.type=LoadBalancer

# 4. Deploy backend
kubectl apply -f yamls/minimax/02-backend-deployment.yaml
kubectl apply -f yamls/minimax/03-backend-service.yaml

# 5. Configure routing
kubectl apply -f yamls/minimax/04-virtual-gateway.yaml
kubectl apply -f yamls/minimax/05-route-table.yaml
```

### Diagnostic Commands

```bash
# Check Gateway IP
kubectl get svc -n gloo-gateway gloo-gateway-proxy

# Check pods
kubectl get pods -n gloo-gateway
kubectl get pods -n minimax-runtime

# Check resources
kubectl get virtualgateway,routetable -A

# View logs
kubectl logs -n gloo-gateway -l app=gloo-gateway --tail=50
```

### Key Ports

| Service | Port | Protocol |
|---------|------|----------|
| Gloo Gateway HTTP | 8080 | HTTP |
| Gloo Gateway HTTPS | 8443 | HTTPS |
| Istiod | 15010 | HTTP |
| Istiod | 15012 | HTTPS |
| Envoy Admin | 15000 | HTTP |

---

## References

- [Gloo Gateway Documentation](https://docs.solo.io/gloo-gateway/)
- [Gloo Gateway GitHub](https://github.com/solo-io/gloo)
- [GCP GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Istio Documentation](https://istio.io/latest/docs/)

---

*Document Version: 1.0*
*Created: 2026-04-17*
*Last Updated: 2026-04-17*
*Status: Production-Ready*
