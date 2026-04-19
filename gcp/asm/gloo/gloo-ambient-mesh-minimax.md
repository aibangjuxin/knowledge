# Gloo Mesh Enterprise Ambient Mode Installation Guide on GKE

> **Document Purpose**: Complete step-by-step guide for installing Gloo Mesh Enterprise with Ambient Mesh (sidecarless) architecture on Google Kubernetes Engine (GKE). This document covers the installation process, configuration, and verification of the Ambient mode deployment.
>
> **Target Audience**: Platform engineers, SREs, and DevOps teams deploying Gloo Mesh Enterprise in Ambient mode on GKE.
>
> **Prerequisites**: GCP account with appropriate permissions, basic Kubernetes knowledge, Gloo Mesh Enterprise license key.
>
> **Version**: Gloo Mesh Enterprise 2.x with Istio Ambient Mesh (see [Version Selection Guide](#15-version-selection-guide) for recommendations)
>
> **Key Feature**: This guide covers the Ambient (sidecarless) architecture where business pods do NOT have sidecar containers, reducing resource overhead and simplifying operations.

---

## Table of Contents

1. [Overview and Architecture](#1-overview-and-architecture)
2. [Prerequisites](#2-prerequisites)
3. [Step 1: GKE Cluster Setup](#3-step-1-gke-cluster-setup)
4. [Step 2: Install Required Tools](#4-step-2-install-required-tools)
5. [Step 3: Install Gloo Mesh Enterprise with Ambient Mode](#5-step-3-install-gloo-mesh-enterprise-with-ambient-mode)
6. [Step 4: Deploy Gloo Gateway](#6-step-4-deploy-gloo-gateway)
7. [Step 5: Configure Workspace and Isolation](#7-step-5-configure-workspace-and-isolation)
8. [Step 6: Deploy Sample Backend Service (No Sidecar)](#8-step-6-deploy-sample-backend-service-no-sidecar)
9. [Step 7: Configure VirtualGateway and RouteTable](#9-step-7-configure-virtualgateway-and-routetable)
10. [Step 8: Configure Traffic Policies](#10-step-8-configure-traffic-policies)
11. [Step 9: Expose Service via LoadBalancer](#11-step-9-expose-service-via-loadbalancer)
12. [Step 10: Validate End-to-End Connectivity](#12-step-10-validate-end-to-end-connectivity)
13. [Troubleshooting Guide](#13-troubleshooting-guide)
14. [Appendix: Complete YAML Files](#14-appendix-complete-yaml-files)
15. [References](#references)
16. [Version Selection Guide](#16-version-selection-guide)

---

## 1. Overview and Architecture

### 1.1 What is Ambient Mesh?

Ambient Mesh represents a fundamental evolution in service mesh architecture. Unlike traditional sidecar-based service mesh (where each pod has an injected Envoy proxy container), Ambient Mesh moves the proxy functionality out of individual pods and into a dedicated, shared infrastructure layer.

**Key Characteristics of Ambient Mode:**

- **No Sidecar Injection**: Business pods run with only their application containers (1/1 readiness), not 2/2 (app + sidecar)
- **Node-Level Traffic Interception**: Traffic is intercepted at the node level using `ztunnel` (a DaemonSet)
- **Waypoint Proxy**: L7 processing is handled by dedicated Waypoint Proxy pods that can be scaled independently
- **Resource Efficiency**: Significantly reduced CPU and memory overhead compared to sidecar mode

### 1.2 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         GCP GKE Cluster                              │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │                    Management Plane (gloo-mesh)              │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐        │   │
│  │  │ mgmt-server  │  │  gloo-agent  │  │  gloo-ui  │        │   │
│  │  └──────────────┘  └──────────────┘  └───────────┘        │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │              Data Plane - Ambient Mode                         │   │
│  │                                                               │   │
│  │  ┌─────────────────────────────────────────────────────┐     │   │
│  │  │        istio-system namespace                        │     │   │
│  │  │  ┌──────────────┐  ┌──────────────┐                │     │   │
│  │  │  │    istiod    │  │  ztunnel    │                │     │   │
│  │  │  │  (control)   │  │ (node-level)│                │     │   │
│  │  │  └──────────────┘  └──────────────┘                │     │   │
│  │  └─────────────────────────────────────────────────────┘     │   │
│  │                                                               │   │
│  │  ┌─────────────────────────────────────────────────────┐     │   │
│  │  │        gloo-gateway namespace                        │     │   │
│  │  │  ┌──────────────┐  ┌──────────────┐                │     │   │
│  │  │  │ gloo-gateway │  │ waypoint     │                │     │   │
│  │  │  │   (ingress)  │  │  (L7 proxy)  │                │     │   │
│  │  │  └──────────────┘  └──────────────┘                │     │   │
│  │  └─────────────────────────────────────────────────────┘     │   │
│  │                                                               │   │
│  │  ┌─────────────────────────────────────────────────────┐     │   │
│  │  │        team-a-runtime namespace (NO SIDECAR)         │     │   │
│  │  │  ┌──────────────┐                                    │     │   │
│  │  │  │ api1-backend │  ← Pure application container     │     │   │
│  │  │  │     (Pod)    │    (NO istio-proxy sidecar)       │     │   │
│  │  │  └──────────────┘                                    │     │   │
│  │  └─────────────────────────────────────────────────────┘     │   │
│  │                                                               │   │
│  │  External Traffic → GCLB → Gloo Gateway → api1-backend       │
│  └───────────────────────────────────────────────────────────────┘   │
```

### 1.3 Component Roles in Ambient Mode

| Component               | Namespace      | Purpose                                                         |
| ----------------------- | -------------- | --------------------------------------------------------------- |
| `gloo-mesh-mgmt-server` | `gloo-mesh`    | Management plane, translates high-level CRDs to Istio resources |
| `gloo-mesh-agent`       | `gloo-mesh`    | Reports cluster state to management plane                       |
| `gloo-mesh-ui`          | `gloo-mesh`    | Enterprise dashboard (web UI)                                   |
| `gloo-gateway`          | `gloo-gateway` | Envoy-based ingress gateway                                     |
| `istiod`                | `istio-system` | Istio control plane (xDS server)                                |
| `ztunnel`               | `istio-system` | Node-level traffic interception (Ambient mode)                 |
| `waypoint`              | `istio-system` | L7 proxy for service-to-service traffic (Ambient mode)         |

### 1.4 Sidecar vs Ambient Mode Comparison

| Feature                  | Sidecar Mode              | Ambient Mode                            |
| ------------------------ | ------------------------ | --------------------------------------- |
| Pod Container Count      | 2/2 (app + sidecar)     | 1/1 (app only)                         |
| Traffic Interception     | Per-pod sidecar         | Node-level ztunnel (DaemonSet)         |
| L7 Processing           | Sidecar Envoy           | Dedicated Waypoint Proxy                |
| Memory Overhead          | ~50MB per pod           | Shared node-level ~100MB per node      |
| Upgrade Impact          | Requires pod restart    | No pod restart required                |
| Resource Efficiency      | Lower                   | Higher (up to 90% reduction)           |

---

## 2. Prerequisites

### 2.1 GCP Permissions

Ensure your service account or user has the following IAM roles:

- `roles/container.admin` (Kubernetes Engine Admin)
- `roles/iam.serviceAccountAdmin` (Service Account Admin)
- `roles/compute.networkAdmin` (Compute Network Admin)

### 2.2 Required Tools

| Tool       | Minimum Version | Purpose                      |
| ---------- | --------------- | ---------------------------- |
| `gcloud`   | 400.0.0+        | GCP CLI                      |
| `kubectl`  | 1.28+           | Kubernetes CLI               |
| `helm`     | 3.12+           | Package manager              |
| `meshctl`  | 2.x             | Gloo Mesh Enterprise CLI     |
| `istioctl` | 1.22+           | Istio diagnostics (for Ambient) |

### 2.3 Environment Variables

Set the following environment variables for your session:

```bash
# GCP Configuration
export GCP_PROJECT_ID="your-gcp-project-id"
export GCP_REGION="us-central1"
export GKE_CLUSTER_NAME="gloo-ambient-cluster"

# Gloo Configuration
export GLOO_VERSION="2.5.5"  # Check latest at https://docs.solo.io/gloo-mesh-enterprise/
export LICENSE_KEY="your-solo-enterprise-license-key"  # Required for Enterprise

# Namespace Configuration
export MGMT_NAMESPACE="gloo-mesh"
export GATEWAY_NAMESPACE="gloo-gateway"
export WORKLOAD_NAMESPACE="team-a-runtime"
```

---

## 3. Step 1: GKE Cluster Setup

### 3.1 Create GKE Cluster

Create a GKE cluster with sufficient resources for Gloo Mesh Enterprise in Ambient mode:

```bash
gcloud container clusters create ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION} \
  --cluster-version=1.29 \
  --machine-type=e4-standard-4 \
  --num-nodes=3 \
  --min-nodes=3 \
  --max-nodes=6 \
  --enable-autoscaling \
  --enable-autoupgrade \
  --enable-autorepair \
  --disk-size=100 \
  --disk-type=pd-balanced \
  --network=default \
  --subnetwork=default \
  --enable-ip-alias \
  --enable-intra-node-visibility \
  --enable-shielded-nodes \
  --shielded-secure-boot \
  --shielded-integrity-monitoring \
  --workload-pool=${GCP_PROJECT_ID}.svc.id.goog \
  --labels="env=prod,team=platform,mesh=gloo-ambient"
```

**Key Notes for Ambient Mode:**

- `e4-standard-4`: 4 vCPU, 16GB RAM per node (sufficient for management plane + ztunnel + workloads)
- `--enable-autoscaling`: Automatically scale nodes based on demand
- `--enable-ip-alias`: Required for VPC-native clusters
- `--workload-pool`: Enables Workload Identity (optional but recommended for production)

### 3.2 Configure kubectl Context

```bash
# Get credentials for the cluster
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION}

# Verify connection
kubectl cluster-info
```

### 3.3 Create Required Namespaces

```bash
# Create namespaces for Gloo components
kubectl create namespace ${MGMT_NAMESPACE}
kubectl create namespace ${GATEWAY_NAMESPACE}
kubectl create namespace ${WORKLOAD_NAMESPACE}
kubectl create namespace istio-system

# Verify namespaces
kubectl get namespaces
```

---

## 4. Step 2: Install Required Tools

### 4.1 Install meshctl (Gloo Mesh Enterprise CLI)

```bash
# Download and install meshctl
curl -sL https://run.solo.io/meshctl/install | sh

# Move to PATH (optional)
sudo mv $HOME/.gloo-mesh/bin/meshctl /usr/local/bin/

# Verify installation
meshctl version

# Expected output (Enterprise version):
# {
#   "meshctl": "2.5.5",
#   "gloo-mesh-enterprise": "2.5.5"
# }
```

### 4.2 Install Helm

```bash
# For macOS (Homebrew)
brew install helm

# For Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

### 4.3 Add Gloo Platform Helm Repository

```bash
# Add Gloo Platform Helm repo
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts
helm repo update

# Verify repo
helm search repo gloo-platform
```

### 4.4 Install istioctl (Required for Ambient Mode Debugging)

```bash
# Install istioctl (version 1.22+ required for Ambient)
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.22.0 sh -

# Move to PATH
sudo mv $HOME/istio-1.22.0/bin/istioctl /usr/local/bin/

# Verify installation
istioctl version

# Install the istioctl bash completion (optional)
# istioctl admin collateral
```

---

## 5. Step 3: Install Gloo Mesh Enterprise with Ambient Mode

### 5.1 Install CRDs

```bash
# Install Gloo Platform CRDs
helm install gloo-platform-crds gloo-platform/gloo-platform-crds \
  --namespace ${MGMT_NAMESPACE} \
  --create-namespace \
  --version ${GLOO_VERSION} \
  --wait

# Verify CRDs are installed
kubectl get crds | grep gloo
```

### 5.2 Install Management Plane with Ambient Mode

The key difference in Ambient mode is the Istio configuration. We need to enable Ambient mode in the Istio settings:

```bash
# Install Gloo Mesh Enterprise management plane with Ambient mode enabled
helm install gloo-platform gloo-platform/gloo-platform \
  --namespace ${MGMT_NAMESPACE} \
  --version ${GLOO_VERSION} \
  --values - <<EOF
licensing:
  glooMeshLicenseKey: ${LICENSE_KEY}

glooMgmtServer:
  enabled: true
  replicaCount: 1
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi

glooAgent:
  enabled: true
  relay:
    serverAddress: gloo-mesh-mgmt-server.${MGMT_NAMESPACE}.svc.cluster.local:9900
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

telemetryCollector:
  enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

glooUi:
  enabled: true
  replicaCount: 1
  service:
    type: ClusterIP
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Istio Configuration - Enable Ambient Mode
istiod:
  enabled: true
  global:
    # This enables Ambient mode
    meshConfig:
      enableAmbient: true
    proxy:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
  # Enable ztunnel (required for Ambient mode)
  ztunnel:
    enabled: true
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
EOF
```

**Key Ambient Mode Configuration:**

- `istiod.global.meshConfig.enableAmbient: true`: Enables Istio Ambient Mesh
- `istiod.ztunnel.enabled: true`: Deploys ztunnel DaemonSet for node-level traffic interception

### 5.3 Verify Management Plane Installation

```bash
# Wait for all pods to be ready
kubectl wait --for=condition=Ready pods --all -n ${MGMT_NAMESPACE} --timeout=300s

# Check pod status
kubectl get pods -n ${MGMT_NAMESPACE}

# Expected output:
# NAME                                      READY   STATUS    RESTARTS   AGE
# gloo-mesh-agent-xxxxx                     1/1     Running   0          2m
# gloo-mesh-mgmt-server-xxxxx               1/1     Running   0          2m
# gloo-mesh-ui-xxxxx                        1/1     Running   0          2m
# gloo-telemetry-collector-xxxxx            1/1     Running   0          2m
# istiod-xxxxx                              1/1     Running   0          2m
```

### 5.4 Verify ztunnel Installation (Ambient Mode Indicator)

```bash
# Check ztunnel DaemonSet (Ambient mode specific)
kubectl get pods -n istio-system -l app=ztunnel

# Expected output (one pod per node):
# NAME                READY   STATUS    RESTARTS   AGE
# ztunnel-xxxxx       1/1     Running   0          2m
# ztunnel-xxxxx       1/1     Running   0          2m
# ztunnel-xxxxx       1/1     Running   0          2m
```

### 5.5 Run Health Check

```bash
# Run Gloo Mesh health check
meshctl check

# Expected output:
# ✓ Gloo Mesh management plane is healthy
# ✓ Gloo Mesh agent is connected
# ✓ Istiod is running
# ✓ License is valid
# ✓ Ambient mode is enabled
```

---

## 6. Step 4: Deploy Gloo Gateway

### 6.1 Install Gloo Gateway

```bash
# Install Gloo Gateway
helm install gloo-gateway gloo-platform/gloo-platform \
  --namespace ${GATEWAY_NAMESPACE} \
  --version ${GLOO_VERSION} \
  --values - <<EOF
glooGateway:
  enabled: true
  gatewayProxies:
    gatewayProxy:
      service:
        type: LoadBalancer  # Expose via GCP Load Balancer
        annotations:
          service.beta.kubernetes.io/gcp-load-balancer-type: "External"
      deployment:
        replicas: 2
      resources:
        requests:
          cpu: 250m
          memory: 256Mi
        limits:
          cpu: 1000m
          memory: 1Gi
      podTemplate:
        terminationGracePeriodSeconds: 30
        affinity:
          podAntiAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app: gloo-gateway
                topologyKey: kubernetes.io/hostname

glooPortalServer:
  enabled: false  # Developer portal (optional, not needed for basic setup)
EOF
```

### 6.2 Verify Gateway Installation

```bash
# Wait for gateway pods to be ready
kubectl wait --for=condition=Ready pods -l app=gloo-gateway -n ${GATEWAY_NAMESPACE} --timeout=300s

# Check pod status
kubectl get pods -n ${GATEWAY_NAMESPACE}

# Expected output:
# NAME                            READY   STATUS    RESTARTS   AGE
# gloo-gateway-xxxxx              1/1     Running   0          2m
# gloo-gateway-xxxxx              1/1     Running   0          2m
```

### 6.3 Get Gateway Load Balancer IP

```bash
# Get the external IP of the gateway service
export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Gateway Load Balancer IP: ${GATEWAY_IP}"

# Wait until IP is assigned (may take 2-5 minutes)
# If empty, wait and run again:
# kubectl get svc -n ${GATEWAY_NAMESPACE}
```

---

## 7. Step 5: Configure Workspace and Isolation

### 7.1 Create Workspace for Team Isolation

```bash
# Create Workspace YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/01-workspace.yaml
apiVersion: admin.gloo.solo.io/v2
kind: Workspace
metadata:
  name: team-a-workspace
  namespace: ${MGMT_NAMESPACE}
spec:
  workloadClusters:
  - name: gke-cluster-1  # Cluster name (auto-discovered in single-cluster)
    namespaces:
    - name: ${WORKLOAD_NAMESPACE}
    - name: ${GATEWAY_NAMESPACE}
EOF

# Apply Workspace
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/01-workspace.yaml
```

### 7.2 Configure Workspace Settings

```bash
# Create WorkspaceSettings YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/02-workspace-settings.yaml
apiVersion: admin.gloo.solo.io/v2
kind: WorkspaceSettings
metadata:
  name: team-a-settings
  namespace: ${WORKLOAD_NAMESPACE}
spec:
  importFrom:
  - workspaces:
    - name: team-a-workspace
  exportTo:
  - workspaces:
    - name: team-a-workspace
  options:
    # Ambient mode doesn't require service isolation to be enabled
    # since there's no sidecar to manage
    serviceIsolation:
      enabled: false
    # Use waypoint proxies for L7 processing in Ambient mode
    waypointProxy:
      enabled: true
EOF

# Apply WorkspaceSettings
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/02-workspace-settings.yaml
```

### 7.3 Verify Workspace Configuration

```bash
# Check Workspace status
kubectl get workspace -n ${MGMT_NAMESPACE} team-a-workspace -o yaml

# Check WorkspaceSettings status
kubectl get workspacesettings -n ${WORKLOAD_NAMESPACE} team-a-settings -o yaml
```

---

## 8. Step 6: Deploy Sample Backend Service (No Sidecar)

### 8.1 Key Difference: No Sidecar Injection

In Ambient mode, you do NOT need to label the namespace for sidecar injection. The traffic interception happens at the node level via ztunnel, not via per-pod sidecars.

**Important**: Do NOT run the following command in Ambient mode:
```bash
# DO NOT DO THIS IN AMBIENT MODE
# kubectl label namespace ${WORKLOAD_NAMESPACE} istio-injection=enabled
```

Instead, simply deploy your application without any Istio injection labels.

### 8.2 Create Sample Application Deployment

```bash
# Create backend deployment YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/03-backend-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api1-backend
  namespace: ${WORKLOAD_NAMESPACE}
  labels:
    app: api1-backend
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api1-backend
  template:
    metadata:
      labels:
        app: api1-backend
        version: v1
      annotations:
        # In Ambient mode, we can use waypoint for L7 processing
        # But the pod itself has NO sidecar container
    spec:
      serviceAccountName: default
      containers:
      - name: api1
        image: nginx:1.25-alpine
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
        volumeMounts:
        - name: config
          mountPath: /usr/share/nginx/html
      volumes:
      - name: config
        configMap:
          name: api1-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: api1-config
  namespace: ${WORKLOAD_NAMESPACE}
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
        <title>API1 Backend</title>
    </head>
    <body>
        <h1>API1 Backend Service</h1>
        <p>Service: api1-backend</p>
        <p>Namespace: team-a-runtime</p>
        <p>Mesh: Gloo Mesh Enterprise (Ambient Mode)</p>
        <p>Architecture: Sidecarless</p>
    </body>
    </html>
  healthz: "OK"
EOF

# Apply deployment
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/03-backend-deployment.yaml
```

### 8.3 Create Kubernetes Service

```bash
# Create service YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/04-backend-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: api1-backend
  namespace: ${WORKLOAD_NAMESPACE}
  labels:
    app: api1-backend
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: api1-backend
EOF

# Apply service
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/04-backend-service.yaml
```

### 8.4 Verify Backend Deployment (NO SIDECAR)

```bash
# Wait for deployment to be ready
kubectl wait --for=condition=Ready pods -l app=api1-backend -n ${WORKLOAD_NAMESPACE} --timeout=300s

# Check pod status - should show 1/1 containers (NO sidecar!)
kubectl get pods -n ${WORKLOAD_NAMESPACE}

# Expected output:
# NAME                            READY   STATUS    RESTARTS   AGE
# api1-backend-xxxxx              1/1     Running   0          2m  ← Only 1 container!
# api1-backend-xxxxx              1/1     Running   0          2m  ← Only 1 container!

# Verify there is NO istio-proxy container
kubectl get pod -n ${WORKLOAD_NAMESPACE} -l app=api1-backend -o jsonpath='{.items[0].spec.containers[*].name}'
echo ""
# Expected output: api1-backend  ← Only the app container, NO istio-proxy!
```

This is the key difference from sidecar mode! The pod should show 1/1 containers, not 2/2.

### 8.5 Test Backend Connectivity (Internal)

```bash
# Get a backend pod name
BACKEND_POD=$(kubectl get pods -n ${WORKLOAD_NAMESPACE} -l app=api1-backend -o jsonpath='{.items[0].metadata.name}')

# Test from within the cluster
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -n ${GATEWAY_NAMESPACE} -- \
  curl -s http://api1-backend.${WORKLOAD_NAMESPACE}.svc.cluster.local:8080/healthz

# Expected output: OK
```

---

## 9. Step 7: Configure VirtualGateway and RouteTable

### 9.1 Create VirtualGateway

```bash
# Create VirtualGateway YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/05-virtual-gateway.yaml
apiVersion: networking.gloo.solo.io/v2
kind: VirtualGateway
metadata:
  name: team-a-gateway
  namespace: ${WORKLOAD_NAMESPACE}
spec:
  workloads:
  - selector:
      labels:
        app: gloo-gateway
      namespace: ${GATEWAY_NAMESPACE}
  listeners:
  - http: {}
    port:
      number: 8080
    allowedRouteTables:
    - host: "*"
EOF

# Apply VirtualGateway
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/05-virtual-gateway.yaml
```

### 9.2 Create RouteTable

```bash
# Create RouteTable YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/06-route-table.yaml
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: api1-route
  namespace: ${WORKLOAD_NAMESPACE}
spec:
  hosts:
  - "*"
  virtualGateways:
  - name: team-a-gateway
    namespace: ${WORKLOAD_NAMESPACE}
  http:
  - name: route-to-api1
    matchers:
    - uri:
        prefix: /api1
    forwardTo:
      destinations:
      - ref:
          name: api1-backend
          namespace: ${WORKLOAD_NAMESPACE}
        port:
          number: 8080
    labels:
      route: api1
  - name: default-route
    matchers:
    - uri:
        prefix: /
    forwardTo:
      destinations:
      - ref:
          name: api1-backend
          namespace: ${WORKLOAD_NAMESPACE}
        port:
          number: 8080
EOF

# Apply RouteTable
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/06-route-table.yaml
```

### 9.3 Verify Gateway and Route Configuration

```bash
# Check VirtualGateway status
kubectl get virtualgateway -n ${WORKLOAD_NAMESPACE} team-a-gateway -o yaml

# Check RouteTable status
kubectl get routetable -n ${WORKLOAD_NAMESPACE} api1-route -o yaml

# Verify translated Istio resources
kubectl get virtualservice -n ${WORKLOAD_NAMESPACE}
kubectl get gateway -n ${WORKLOAD_NAMESPACE}
```

---

## 10. Step 8: Configure Traffic Policies

### 10.1 Enable mTLS in Ambient Mode

In Ambient mode, mTLS configuration is different from sidecar mode. We use `AuthorizationPolicy` instead of `PeerAuthentication`:

```bash
# Create AuthorizationPolicy for STRICT mTLS
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/07-authorization-policy.yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: default-strict
  namespace: ${WORKLOAD_NAMESPACE}
spec:
  {}  # Empty spec = STRICT mTLS for the namespace
EOF

# Apply AuthorizationPolicy
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/07-authorization-policy.yaml
```

### 10.2 Create TrafficPolicy for Backend

```bash
# Create TrafficPolicy YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/08-traffic-policy.yaml
apiVersion: trafficcontrol.policy.gloo.solo.io/v2
kind: TrafficPolicy
metadata:
  name: api1-backend-policy
  namespace: ${WORKLOAD_NAMESPACE}
spec:
  applyToDestinations:
  - selector:
      name: api1-backend
      namespace: ${WORKLOAD_NAMESPACE}
  policy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
    loadBalancer:
      roundRobin: {}
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
EOF

# Apply TrafficPolicy
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/08-traffic-policy.yaml
```

### 10.3 Verify Traffic Policy Configuration

```bash
# Check TrafficPolicy status
kubectl get trafficpolicy -n ${WORKLOAD_NAMESPACE} api1-backend-policy -o yaml

# In Ambient mode, verify waypoint proxy is being used
# Waypoint proxies are automatically created for services that need L7 processing
kubectl get pods -n ${WORKLOAD_NAMESPACE} -l "app.kubernetes.io/waypoint"
```

---

## 11. Step 9: Expose Service via LoadBalancer

### 11.1 Get Gateway External IP

```bash
# Get the external IP (if not already set)
export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Wait if IP is not yet assigned
if [ -z "${GATEWAY_IP}" ]; then
  echo "Waiting for LoadBalancer IP assignment..."
  kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -w
fi

echo "Gateway External IP: ${GATEWAY_IP}"
```

### 11.2 Test External Access

```bash
# Test access to the API via gateway
curl -v http://${GATEWAY_IP}:8080/api1

# Expected output:
# < HTTP/1.1 200 OK
# < server: envoy
# ...
# API1 Backend Service
# Service: api1-backend
# Namespace: team-a-runtime
# Mesh: Gloo Mesh Enterprise (Ambient Mode)
```

---

## 12. Step 10: Validate End-to-End Connectivity

### 12.1 End-to-End Test Script

```bash
#!/bin/bash
# ambient-e2e-validation.sh

set -e

GATEWAY_IP=$(kubectl get svc -n gloo-gateway gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
WORKLOAD_NS="team-a-runtime"

echo "=== Gloo Mesh Ambient Mode E2E Validation ==="
echo "Gateway IP: ${GATEWAY_IP}"
echo ""

# Test 1: Gateway Pod Health
echo "Test 1: Gateway Pod Health"
kubectl get pods -n gloo-gateway -l app=gloo-gateway
echo ""

# Test 2: ztunnel Pod Health (Ambient mode specific)
echo "Test 2: ztunnel Pod Health (Ambient Mode)"
kubectl get pods -n istio-system -l app=ztunnel
echo ""

# Test 3: Backend Pod Health (NO sidecar!)
echo "Test 3: Backend Pod Health (NO Sidecar)"
kubectl get pods -n ${WORKLOAD_NS} -l app=api1-backend
echo ""

# Test 4: Verify pod container count (should be 1/1)
echo "Test 4: Verify No Sidecar"
CONTAINER_COUNT=$(kubectl get pod -n ${WORKLOAD_NS} -l app=api1-backend -o jsonpath='{.items[0].spec.containers | length}')
if [ "${CONTAINER_COUNT}" == "1" ]; then
  echo "✓ No sidecar detected (Ambient mode working correctly)"
else
  echo "✗ Sidecar detected (unexpected in Ambient mode)"
  exit 1
fi
echo ""

# Test 5: External Access via Gateway
echo "Test 5: External Access via Gateway"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://${GATEWAY_IP}:8080/api1)
if [ "${RESPONSE}" == "200" ]; then
  echo "✓ External access successful (HTTP ${RESPONSE})"
else
  echo "✗ External access failed (HTTP ${RESPONSE})"
  exit 1
fi
echo ""

# Test 6: Waypoint Proxy Check
echo "Test 6: Waypoint Proxy"
WAYPOINT_COUNT=$(kubectl get pods -n ${WORKLOAD_NS} -l "app.kubernetes.io/waypoint" --no-headers 2>/dev/null | wc -l)
echo "Waypoint proxies found: ${WAYPOINT_COUNT}"
echo ""

echo "=== All Tests Completed ==="
```

Save and run:

```bash
chmod +x /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/e2e-validation.sh
bash /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/e2e-validation.sh
```

### 12.2 Expected Test Results

```
=== Gloo Mesh Ambient Mode E2E Validation ===
Gateway IP: 34.0.0.1

Test 1: Gateway Pod Health
NAME                            READY   STATUS    RESTARTS   AGE
gloo-gateway-xxxxx              1/1     Running   0          10m
gloo-gateway-xxxxx              1/1     Running   0          10m

Test 2: ztunnel Pod Health (Ambient Mode)
NAME                READY   STATUS    RESTARTS   AGE
ztunnel-xxxxx       1/1     Running   0          10m
ztunnel-xxxxx       1/1     Running   0          10m
ztunnel-xxxxx       1/1     Running   0          10m

Test 3: Backend Pod Health (NO Sidecar)
NAME                            READY   STATUS    RESTARTS   AGE
api1-backend-xxxxx              1/1     Running   0          8m   ← Only 1 container!
api1-backend-xxxxx              1/1     Running   0          8m   ← Only 1 container!

Test 4: Verify No Sidecar
✓ No sidecar detected (Ambient mode working correctly)

Test 5: External Access via Gateway
✓ External access successful (HTTP 200)

Test 6: Waypoint Proxy
Waypoint proxies found: 0 (or more if configured)

=== All Tests Completed ===
```

---

## 13. Troubleshooting Guide

### 13.1 Common Issues and Solutions

#### Issue 1: ztunnel Not Running

**Symptoms**: Pods not receiving traffic in Ambient mode

**Solutions**:
```bash
# Check ztunnel pods
kubectl get pods -n istio-system -l app=ztunnel

# Check ztunnel logs
kubectl logs -n istio-system -l app=ztunnel --tail=50

# Verify Ambient mode is enabled in mesh config
kubectl get configmap istio -n istio-system -o yaml | grep -i ambient
```

#### Issue 2: Waypoint Proxy Not Created

**Symptoms**: L7 features not working

**Solutions**:
```bash
# Check waypoint proxy status
kubectl get waypoints -A

# Manually create a waypoint for a service
istioctl x waypoint generate --service api1-backend.team-a-runtime

# Check workspace settings for waypoint configuration
kubectl get workspacesettings -A -o yaml
```

#### Issue 3: mTLS Not Working in Ambient Mode

**Symptoms**: Connection errors, authorization failures

**Solutions**:
```bash
# Check AuthorizationPolicy (not PeerAuthentication in Ambient mode)
kubectl get authorizationpolicy -A

# Verify ztunnel has the correct certs
kubectl exec -n istio-system -it deploy/ztunnel -- \
  curl -s localhost:15000/certs
```

#### Issue 4: Traffic Not Reaching Pods

**Symptoms**: 503 Service Unavailable

**Solutions**:
```bash
# Check if ztunnel is intercepting traffic
kubectl get pods -n istio-system -l app=ztunnel

# Verify service endpoints
kubectl get endpoints -n ${WORKLOAD_NAMESPACE}

# Check ztunnel routing table
kubectl exec -n istio-system -it deploy/ztunnel -- \
  ztunnel-cli show routes
```

### 13.2 Debug Commands Reference

```bash
# ─── Ambient Mode Diagnostics ───────────────────────

# Check ztunnel status
kubectl get pods -n istio-system -l app=ztunnel -o wide

# Check ztunnel logs
kubectl logs -n istio-system -l app=ztunnel --tail=100

# Check waypoint proxies
kubectl get waypoints -A

# Check AuthorizationPolicy (Ambient mode mTLS)
kubectl get authorizationpolicy -A

# ─── Gloo Mesh Diagnostics ───────────────────────

# Global health check
meshctl check

# List registered clusters
meshctl cluster list

# Generate diagnostic report
meshctl debug report

# ─── Kubernetes Resource Inspection ───────────────

# View all Gloo CRDs
kubectl api-resources | grep solo.io

# View Gloo resources with status
kubectl get virtualgateway,routetable,trafficpolicy -n ${WORKLOAD_NAMESPACE} -o wide

# View translated Istio resources
kubectl get vs,dr,gw -n ${WORKLOAD_NAMESPACE} -l "reconciler.mesh.gloo.solo.io/name"

# ─── Pod Verification (Ambient Mode) ──────────────

# Verify NO sidecar in pod
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].name}'

# Count containers in pod (should be 1 in Ambient mode)
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers | length}'
```

---

## 14. Appendix: Complete YAML Files

### 14.1 All-in-One Installation Script

```bash
#!/bin/bash
# install-gloo-ambient.sh

set -e

# Configuration
export GCP_PROJECT_ID="your-gcp-project-id"
export GCP_REGION="us-central1"
export GKE_CLUSTER_NAME="gloo-ambient-cluster"
export GLOO_VERSION="2.5.5"
export LICENSE_KEY="your-solo-enterprise-license-key"
export MGMT_NAMESPACE="gloo-mesh"
export GATEWAY_NAMESPACE="gloo-gateway"
export WORKLOAD_NAMESPACE="team-a-runtime"

echo "=== Starting Gloo Mesh Enterprise Ambient Mode Installation ==="

# Step 1: Create GKE cluster (if not exists)
echo "Step 1: Creating GKE cluster..."
gcloud container clusters create ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION} \
  --cluster-version=1.29 \
  --machine-type=e4-standard-4 \
  --num-nodes=3 \
  --enable-autoscaling \
  --enable-autoupgrade \
  --enable-autorepair \
  --disk-size=100 \
  --enable-ip-alias \
  --labels="env=prod,team=platform,mesh=gloo-ambient"

# Step 2: Get credentials
echo "Step 2: Configuring kubectl..."
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION}

# Step 3: Create namespaces
echo "Step 3: Creating namespaces..."
kubectl create namespace ${MGMT_NAMESPACE}
kubectl create namespace ${GATEWAY_NAMESPACE}
kubectl create namespace ${WORKLOAD_NAMESPACE}
kubectl create namespace istio-system

# Step 4: Install CRDs
echo "Step 4: Installing CRDs..."
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts
helm repo update

helm install gloo-platform-crds gloo-platform/gloo-platform-crds \
  --namespace ${MGMT_NAMESPACE} \
  --create-namespace \
  --version ${GLOO_VERSION} \
  --wait

# Step 5: Install management plane with Ambient mode
echo "Step 5: Installing management plane with Ambient mode..."
helm install gloo-platform gloo-platform/gloo-platform \
  --namespace ${MGMT_NAMESPACE} \
  --version ${GLOO_VERSION} \
  --values - <<EOF
licensing:
  glooMeshLicenseKey: ${LICENSE_KEY}
glooMgmtServer:
  enabled: true
glooAgent:
  enabled: true
  relay:
    serverAddress: gloo-mesh-mgmt-server.${MGMT_NAMESPACE}.svc.cluster.local:9900
telemetryCollector:
  enabled: true
glooUi:
  enabled: true
istiod:
  enabled: true
  global:
    meshConfig:
      enableAmbient: true
  ztunnel:
    enabled: true
EOF

# Step 6: Install Gloo Gateway
echo "Step 6: Installing Gloo Gateway..."
helm install gloo-gateway gloo-platform/gloo-platform \
  --namespace ${GATEWAY_NAMESPACE} \
  --version ${GLOO_VERSION} \
  --values - <<EOF
glooGateway:
  enabled: true
  gatewayProxies:
    gatewayProxy:
      service:
        type: LoadBalancer
glooPortalServer:
  enabled: false
EOF

# Step 7: Wait for all components
echo "Step 7: Waiting for components to be ready..."
kubectl wait --for=condition=Ready pods --all -n ${MGMT_NAMESPACE} --timeout=300s
kubectl wait --for=condition=Ready pods -l app=gloo-gateway -n ${GATEWAY_NAMESPACE} --timeout=300s

# Step 8: Verify ztunnel (Ambient mode indicator)
echo "Step 8: Verifying ztunnel..."
kubectl get pods -n istio-system -l app=ztunnel

# Step 9: Deploy sample application (NO sidecar injection)
echo "Step 9: Deploying sample application..."
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/03-backend-deployment.yaml
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/04-backend-service.yaml

# Step 10: Configure Gloo resources
echo "Step 10: Configuring Gloo resources..."
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/01-workspace.yaml
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/02-workspace-settings.yaml
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/05-virtual-gateway.yaml
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/06-route-table.yaml
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/ambient/08-traffic-policy.yaml

# Step 11: Validate installation
echo "Step 11: Validating installation..."
meshctl check

echo ""
echo "=== Installation Complete ==="
echo "Gateway IP: $(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "Test access: curl http://<GATEWAY_IP>:8080/api1"
echo ""
echo "=== Ambient Mode Verification ==="
echo "Pod container count (should be 1): $(kubectl get pod -n ${WORKLOAD_NAMESPACE} -l app=api1-backend -o jsonpath='{.items[0].spec.containers | length}')"
```

---

## 15. References

- [Gloo Mesh Enterprise Documentation](https://docs.solo.io/gloo-mesh-enterprise/)
- [Gloo Mesh Ambient Mode Documentation](https://docs.solo.io/gloo-mesh-enterprise/latest/setup/ambient/)
- [Istio Ambient Mesh Documentation](https://istio.io/latest/docs/ops/ambient/)
- [Gloo Gateway Documentation](https://docs.solo.io/gloo-mesh-gateway/)
- [Solo.io GitHub](https://github.com/solo-io/gloo-mesh)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)

---

## 16. Version Selection Guide

### 16.1 Gloo Mesh Enterprise Version Overview

Gloo Mesh Enterprise versions follow a 2.x numbering scheme. The version you choose depends on your production requirements, feature needs, and compatibility requirements.

#### Current Recommended Versions (2026)

| Version Series | Status | Ambient Mode Support | Istio Version | Recommended For |
|---------------|--------|---------------------|---------------|----------------|
| **2.6.x** | Latest Stable | ✅ Full Support | Istio 1.24+ | New deployments |
| **2.5.x** | Stable | ✅ Full Support | Istio 1.22+ | Production use |
| **2.4.x** | Stable | ✅ Support (Initial) | Istio 1.21+ | Legacy compatibility |
| **2.3.x** | Maintenance | ⚠️ Limited | Istio 1.20+ | Migration only |
| **2.0-2.2.x** | End of Life | ❌ Not Supported | Istio 1.19- | Upgrade required |

### 16.2 Version Selection Recommendations

#### For New Deployments (Recommended: 2.6.x)

If you are starting a new Gloo Mesh Enterprise deployment in 2026, use the latest stable version:

```bash
export GLOO_VERSION="2.6.0"  # Check for latest at https://docs.solo.io/gloo-mesh-enterprise/
```

**Benefits of 2.6.x:**
- Full Ambient mode support with all latest features
- Improved Waypoint Proxy performance
- Enhanced security patches and CVE fixes
- Better compatibility with newer Kubernetes versions (1.29+)
- Enterprise support for latest Istio Ambient features

#### For Production Workloads (Recommended: 2.5.x)

If you need maximum stability for production workloads:

```bash
export GLOO_VERSION="2.5.5"  # Latest patch in 2.5 series
```

**Benefits of 2.5.x:**
- Well-tested in production environments
- Mature Ambient mode implementation
- Comprehensive enterprise support
- Stable API surface
- Known compatibility with GKE 1.28-1.29

### 16.3 Ambient Mode Version Requirements

#### Minimum Requirements for Ambient Mode

| Component | Minimum Version | Notes |
|-----------|---------------|-------|
| Gloo Mesh Enterprise | 2.4.0+ | Initial Ambient support |
| Istio | 1.21.0+ | Required for Ambient |
| Kubernetes | 1.28.0+ | Required for ztunnel |
| GKE | 1.28+ | Recommended |

#### Recommended Version Combinations

| Gloo Mesh Version | Istio Version | GKE Version | Status |
|-------------------|---------------|-------------|--------|
| 2.6.0 | 1.24.0 | 1.29+ | ✅ Recommended |
| 2.5.5 | 1.22.0 | 1.28+ | ✅ Stable |
| 2.5.0 | 1.22.0 | 1.28+ | ✅ Stable |
| 2.4.0 | 1.21.0 | 1.28+ | ✅ Supported |

### 16.4 How to Check Available Versions

```bash
# Search for available Gloo Platform Helm chart versions
helm search repo gloo-platform/gloo-platform --versions | head -20

# Check meshctl for version info
meshctl version

# Check latest version from Solo.io
curl -s https://storage.googleapis.com/gloo-platform/helm-charts/index.yaml | grep -A5 "gloo-platform:"
```

### 16.5 Version Upgrade Path

If you are upgrading from an older version to use Ambient mode:

#### From Gloo Mesh 2.3.x or Earlier → 2.5.x+

1. **Backup current configuration**
   ```bash
   # Export all Gloo resources
   kubectl get virtualgateway,routetable,trafficpolicy,workspace,workspacesettings -A -o yaml > gloo-backup.yaml
   ```

2. **Upgrade to 2.4.x first (if on older version)**
   ```bash
   helm upgrade gloo-platform gloo-platform/gloo-platform \
     --namespace gloo-mesh \
     --version 2.4.x
   ```

3. **Enable Ambient mode**
   ```bash
   # Update Istio configuration to enable Ambient
   helm upgrade gloo-platform gloo-platform/gloo-platform \
     --namespace gloo-mesh \
     --version 2.5.5 \
     --set istiod.global.meshConfig.enableAmbient=true \
     --set istiod.ztunnel.enabled=true
   ```

4. **Verify upgrade**
   ```bash
   meshctl check
   kubectl get pods -n istio-system -l app=ztunnel
   ```

### 16.6 Compatibility Matrix

#### GKE Compatibility

| GKE Version | Gloo Mesh 2.4.x | Gloo Mesh 2.5.x | Gloo Mesh 2.6.x |
|-------------|-----------------|-----------------|-----------------|
| 1.27 | ✅ | ✅ | ✅ |
| 1.28 | ✅ | ✅ | ✅ |
| 1.29 | ✅ | ✅ | ✅ |
| 1.30 | ⚠️ | ✅ | ✅ |

#### Istio Ambient Mode Compatibility

| Gloo Mesh Version | Istio Sidecar Mode | Istio Ambient Mode | Waypoint Proxy |
|-------------------|-------------------|-------------------|----------------|
| 2.4.x | ✅ | ✅ (Initial) | ✅ |
| 2.5.x | ✅ | ✅ (GA) | ✅ (Enhanced) |
| 2.6.x | ✅ | ✅ (GA) | ✅ (Production) |

### 16.7 Enterprise License Considerations

**Important**: Gloo Mesh Enterprise requires a valid license key from Solo.io. License types include:

| License Type | Features | Ambient Mode Support |
|-------------|----------|---------------------|
| **Enterprise** | Full features, SLA support | ✅ All versions |
| **Enterprise Trial** | 30-day trial | ✅ All versions |
| **Enterprise Premium** | Extended features, premium support | ✅ All versions |

**To obtain a license:**
1. Contact Solo.io sales (https://www.solo.io/contact/)
2. Request a trial at https://www.solo.io/free-trial/
3. Your license key will be provided as a string similar to: `gms_xxxxxxxxxxxxx`

### 16.8 Version Selection Decision Tree

```
Start
  │
  ├─ Are you deploying NEW infrastructure?
  │   └─ YES → Use Gloo Mesh 2.6.x (latest stable)
  │
  ├─ Are you upgrading existing deployment?
  │   └─ YES → Use Gloo Mesh 2.5.x (most stable)
  │
  ├─ Do you need specific Istio features?
  │   └─ YES → Check compatibility matrix above
  │
  └─ What is your GKE version?
      ├─ 1.27 → Use Gloo Mesh 2.5.x
      ├─ 1.28 → Use Gloo Mesh 2.5.x or 2.6.x
      └─ 1.29+ → Use Gloo Mesh 2.6.x (recommended)
```

### 16.9 Current Version Recommendations Summary

| Scenario | Recommended Version | Istio Version | Rationale |
|----------|-------------------|---------------|-----------|
| **New Production** | 2.5.5 | 1.22.0 | Maximum stability |
| **New PoC/Dev** | 2.6.0 | 1.24.0 | Latest features |
| **Migration from ASM** | 2.5.5 | 1.22.0 | Proven compatibility |
| **Multi-cluster** | 2.5.5 | 1.22.0 | Stable federation |
| **Maximum Performance** | 2.6.0 | 1.24.0 | Optimized Waypoint |

---

## Quick Reference Cheatsheet

### Ambient Mode Specific Commands

```bash
# Check if Ambient mode is enabled
kubectl get configmap istio -n istio-system -o yaml | grep enableAmbient

# Check ztunnel pods (one per node)
kubectl get pods -n istio-system -l app=ztunnel

# Verify NO sidecar in pod (should return only 1 container)
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].name}'

# Create waypoint proxy manually
istioctl x waypoint generate --service <service>.<namespace>

# Check waypoint proxies
kubectl get waypoints -A
```

### Installation Commands

```bash
# Install meshctl
curl -sL https://run.solo.io/meshctl/install | sh

# Add Helm repo
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts

# Install CRDs
helm install gloo-platform-crds gloo-platform/gloo-platform-crds -n gloo-mesh --create-namespace

# Install management plane with Ambient mode
helm install gloo-platform gloo-platform/gloo-platform -n gloo-mesh --values values.yaml
```

### Key Differences: Sidecar vs Ambient

| Aspect | Sidecar Mode | Ambient Mode |
|--------|--------------|--------------|
| Namespace label | `istio-injection=enabled` | Not needed |
| Pod containers | 2/2 (app + sidecar) | 1/1 (app only) |
| Traffic interception | Per-pod sidecar | Node-level ztunnel |
| mTLS config | PeerAuthentication | AuthorizationPolicy |
| L7 proxy | Sidecar Envoy | Waypoint Proxy |
| Upgrade impact | Pod restart required | No pod restart |

---

*Document Version: 1.0*
*Created: 2026-04-19*
*Last Updated: 2026-04-19*
*Status: Production-Ready*
*Mode: Gloo Mesh Enterprise with Istio Ambient Mesh*
