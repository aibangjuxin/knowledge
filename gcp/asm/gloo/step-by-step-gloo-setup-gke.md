- [End-to-End Gloo Mesh Enterprise Installation on GKE](#end-to-end-gloo-mesh-enterprise-installation-on-gke)
  - [Table of Contents](#table-of-contents)
  - [1. Overview and Architecture](#1-overview-and-architecture)
    - [1.1 Why Gloo Mesh Enterprise?](#11-why-gloo-mesh-enterprise)
    - [1.2 Architecture Diagram](#12-architecture-diagram)
    - [1.3 Component Roles](#13-component-roles)
  - [2. Prerequisites](#2-prerequisites)
    - [2.1 GCP Permissions](#21-gcp-permissions)
    - [2.2 Required Tools](#22-required-tools)
    - [2.3 Environment Variables](#23-environment-variables)
  - [3. Step 1: GKE Cluster Setup](#3-step-1-gke-cluster-setup)
    - [3.1 Create GKE Cluster](#31-create-gke-cluster)
    - [3.2 Configure kubectl Context](#32-configure-kubectl-context)
    - [3.3 Create Required Namespaces](#33-create-required-namespaces)
    - [3.4 Enable Required GCP APIs](#34-enable-required-gcp-apis)
  - [4. Step 2: Install Required Tools](#4-step-2-install-required-tools)
    - [4.1 Install meshctl (Gloo Mesh Enterprise CLI)](#41-install-meshctl-gloo-mesh-enterprise-cli)
    - [4.2 Install Helm](#42-install-helm)
    - [4.3 Add Gloo Platform Helm Repository](#43-add-gloo-platform-helm-repository)
    - [4.4 Install istioctl (Optional, for Debugging)](#44-install-istioctl-optional-for-debugging)
  - [5. Step 3: Install Gloo Mesh Enterprise](#5-step-3-install-gloo-mesh-enterprise)
    - [5.1 Install CRDs](#51-install-crds)
    - [5.2 Install Management Plane (Single-Cluster Mode)](#52-install-management-plane-single-cluster-mode)
    - [5.3 Verify Management Plane Installation](#53-verify-management-plane-installation)
    - [5.4 Run Health Check](#54-run-health-check)
    - [5.5 Access Gloo Mesh UI (Optional)](#55-access-gloo-mesh-ui-optional)
  - [6. Step 4: Deploy Gloo Gateway](#6-step-4-deploy-gloo-gateway)
    - [6.1 Install Gloo Gateway](#61-install-gloo-gateway)
    - [6.2 Verify Gateway Installation](#62-verify-gateway-installation)
    - [6.3 Get Gateway Load Balancer IP](#63-get-gateway-load-balancer-ip)
    - [6.4 Configure Health Check Port](#64-configure-health-check-port)
  - [7. Step 5: Configure Workspace and Isolation](#7-step-5-configure-workspace-and-isolation)
    - [7.1 Create Workspace for Team Isolation](#71-create-workspace-for-team-isolation)
    - [7.2 Configure Workspace Settings](#72-configure-workspace-settings)
    - [7.3 Verify Workspace Configuration](#73-verify-workspace-configuration)
  - [8. Step 6: Deploy Sample Backend Service](#8-step-6-deploy-sample-backend-service)
    - [8.1 Create Sample Application Deployment](#81-create-sample-application-deployment)
    - [8.2 Create Kubernetes Service](#82-create-kubernetes-service)
    - [8.3 Enable Automatic Sidecar Injection](#83-enable-automatic-sidecar-injection)
    - [8.4 Verify Backend Deployment](#84-verify-backend-deployment)
    - [8.5 Test Backend Connectivity (Internal)](#85-test-backend-connectivity-internal)
  - [9. Step 7: Configure VirtualGateway and RouteTable](#9-step-7-configure-virtualgateway-and-routetable)
    - [9.1 Create VirtualGateway](#91-create-virtualgateway)
    - [9.2 Create RouteTable](#92-create-routetable)
    - [9.3 Verify Gateway and Route Configuration](#93-verify-gateway-and-route-configuration)
  - [10. Step 8: Configure mTLS and Traffic Policies](#10-step-8-configure-mtls-and-traffic-policies)
    - [10.1 Enable Mesh-Wide STRICT mTLS](#101-enable-mesh-wide-strict-mtls)
    - [10.2 Create TrafficPolicy for Backend](#102-create-trafficpolicy-for-backend)
    - [10.3 Create AccessPolicy (Optional L7 Authorization)](#103-create-accesspolicy-optional-l7-authorization)
    - [10.4 Verify mTLS Configuration](#104-verify-mtls-configuration)
  - [11. Step 9: Expose Service via LoadBalancer](#11-step-9-expose-service-via-loadbalancer)
    - [11.1 Get Gateway External IP](#111-get-gateway-external-ip)
    - [11.2 Configure DNS (Optional)](#112-configure-dns-optional)
    - [11.3 Test External Access](#113-test-external-access)
    - [11.4 Configure HTTPS (Optional, requires TLS certificate)](#114-configure-https-optional-requires-tls-certificate)
  - [12. Step 10: Validate End-to-End Connectivity](#12-step-10-validate-end-to-end-connectivity)
    - [12.1 End-to-End Test Script](#121-end-to-end-test-script)
    - [12.2 Manual Validation Commands](#122-manual-validation-commands)
    - [12.3 Expected Test Results](#123-expected-test-results)
  - [13. Troubleshooting Guide](#13-troubleshooting-guide)
    - [13.1 Common Issues and Solutions](#131-common-issues-and-solutions)
      - [Issue 1: Gateway LoadBalancer IP Not Assigned](#issue-1-gateway-loadbalancer-ip-not-assigned)
      - [Issue 2: 503 Service Unavailable](#issue-2-503-service-unavailable)
      - [Issue 3: mTLS Handshake Failure](#issue-3-mtls-handshake-failure)
      - [Issue 4: Gloo Mesh Translation Failures](#issue-4-gloo-mesh-translation-failures)
    - [13.2 Debug Commands Reference](#132-debug-commands-reference)
  - [14. Appendix: Complete YAML Files](#14-appendix-complete-yaml-files)
    - [14.1 All-in-One Installation Script](#141-all-in-one-installation-script)
    - [14.2 HTTPS Configuration Example](#142-https-configuration-example)
    - [14.3 RouteTable Delegation Example](#143-routetable-delegation-example)
    - [14.4 Production-Ready Gateway Configuration](#144-production-ready-gateway-configuration)
  - [Quick Reference Cheatsheet](#quick-reference-cheatsheet)
    - [Installation Commands](#installation-commands)
    - [Diagnostic Commands](#diagnostic-commands)
    - [Key Ports](#key-ports)
  - [References](#references)

# End-to-End Gloo Mesh Enterprise Installation on GKE

> **Document Purpose**: Complete step-by-step guide for installing Gloo Mesh Enterprise on Google Kubernetes Engine (GKE), from cluster preparation to deploying a production-ready API service accessible via Gloo Gateway.
>
> **Target Audience**: Platform engineers, SREs, and DevOps teams replacing Google Cloud Service Mesh (ASM) with Gloo Mesh Enterprise.
>
> **Prerequisites**: GCP account with appropriate permissions, basic Kubernetes knowledge.
>
> **Version**: Gloo Mesh Enterprise 2.x (latest stable)

---

## Table of Contents

1. [Overview and Architecture](#1-overview-and-architecture)
2. [Prerequisites](#2-prerequisites)
3. [Step 1: GKE Cluster Setup](#3-step-1-gke-cluster-setup)
4. [Step 2: Install Required Tools](#4-step-2-install-required-tools)
5. [Step 3: Install Gloo Mesh Enterprise](#5-step-3-install-gloo-mesh-enterprise)
6. [Step 4: Deploy Gloo Gateway](#6-step-4-deploy-gloo-gateway)
7. [Step 5: Configure Workspace and Isolation](#7-step-5-configure-workspace-and-isolation)
8. [Step 6: Deploy Sample Backend Service](#8-step-6-deploy-sample-backend-service)
9. [Step 7: Configure VirtualGateway and RouteTable](#9-step-7-configure-virtualgateway-and-routetable)
10. [Step 8: Configure mTLS and Traffic Policies](#10-step-8-configure-mtls-and-traffic-policies)
11. [Step 9: Expose Service via LoadBalancer](#11-step-9-expose-service-via-loadbalancer)
12. [Step 10: Validate End-to-End Connectivity](#12-step-10-validate-end-to-end-connectivity)
13. [Troubleshooting Guide](#13-troubleshooting-guide)
14. [Appendix: Complete YAML Files](#14-appendix-complete-yaml-files)

---

## 1. Overview and Architecture

### 1.1 Why Gloo Mesh Enterprise?

Gloo Mesh Enterprise replaces Google Cloud Service Mesh (ASM) with:

- **Unified Management Plane**: Centralized control for multi-cluster Istio deployments
- **Enterprise UI**: Visual dashboard for topology, policies, and health monitoring
- **Advanced RBAC**: Multi-tenant isolation with Workspace abstraction
- **Gateway API Native**: Modern Kubernetes Gateway API for ingress/egress
- **Commercial Support**: SLA-backed support from Solo.io

### 1.2 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    GCP GKE Cluster                          │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Management Plane (gloo-mesh)           │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │   │
│  │  │ mgmt-server  │  │  gloo-agent  │  │  gloo-ui  │ │   │
│  │  └──────────────┘  └──────────────┘  └───────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Data Plane (gloo-gateway)              │   │
│  │  ┌──────────────┐  ┌──────────────┐                 │   │
│  │  │ gloo-gateway │  │  istiod      │                 │   │
│  │  └──────────────┘  └──────────────┘                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Workload Namespace (team-a)            │   │
│  │  ┌──────────────┐  ┌──────────────┐                 │   │
│  │  │ api1-backend │  │  sidecar     │                 │   │
│  │  │   (Pod)      │  │  (Envoy)     │                 │   │
│  │  └──────────────┘  └──────────────┘                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  External Traffic → GCLB → Gloo Gateway → api1-backend     │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 Component Roles

| Component               | Namespace      | Purpose                                                         |
| ----------------------- | -------------- | --------------------------------------------------------------- |
| `gloo-mesh-mgmt-server` | `gloo-mesh`    | Management plane, translates high-level CRDs to Istio resources |
| `gloo-mesh-agent`       | `gloo-mesh`    | Reports cluster state to management plane                       |
| `gloo-mesh-ui`          | `gloo-mesh`    | Enterprise dashboard (web UI)                                   |
| `gloo-gateway`          | `gloo-gateway` | Envoy-based ingress gateway                                     |
| `istiod`                | `istio-system` | Istio control plane (xDS server)                                |
| `sidecar-proxy`         | Workload pods  | Envoy sidecar for traffic interception                          |

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
| `istioctl` | 1.19+           | Istio diagnostics (optional) |

### 2.3 Environment Variables

Set the following environment variables for your session:

```bash
# GCP Configuration
export GCP_PROJECT_ID="your-gcp-project-id"
export GCP_REGION="us-central1"
export GKE_CLUSTER_NAME="gloo-gke-cluster"

# Gloo Configuration
export GLOO_VERSION="2.0.0"  # Check latest at https://docs.solo.io/gloo-mesh-enterprise/
export LICENSE_KEY="your-solo-enterprise-license-key"  # Required for Enterprise

# Namespace Configuration
export MGMT_NAMESPACE="gloo-mesh"
export GATEWAY_NAMESPACE="gloo-gateway"
export WORKLOAD_NAMESPACE="team-a-runtime"
```

---

## 3. Step 1: GKE Cluster Setup

### 3.1 Create GKE Cluster

Create a GKE cluster with sufficient resources for Gloo Mesh Enterprise:

```bash
gcloud container clusters create ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION} \
  --cluster-version=1.28 \
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
  --labels="env=prod,team=platform,mesh=gloo"
```

**Explanation**:
- `e4-standard-4`: 4 vCPU, 16GB RAM per node (sufficient for management plane + workloads)
- `--enable-autoscaling`: Automatically scale nodes based on demand
- `--enable-ip-alias`: Required for VPC-native clusters (recommended for Gloo)
- `--workload-pool`: Enables Workload Identity (optional but recommended for production)

### 3.2 Configure kubectl Context

```bash
# Get credentials for the cluster
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION}

# Verify connection
kubectl cluster-info

# Expected output:
# Kubernetes control plane is running at https://<IP>
# GKE control plane is running at https://<IP>
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

### 3.4 Enable Required GCP APIs

```bash
# Enable GKE and Container APIs
gcloud services enable container.googleapis.com \
  --project=${GCP_PROJECT_ID}

# Enable Cloud Monitoring (optional, for observability)
gcloud services enable monitoring.googleapis.com \
  --project=${GCP_PROJECT_ID}
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
#   "meshctl": "2.0.0",
#   "gloo-mesh-enterprise": "2.0.0"
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

# Expected output:
# version.BuildInfo{Version:"v3.12.0", ...}
```

### 4.3 Add Gloo Platform Helm Repository

```bash
# Add Gloo Platform Helm repo
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts
helm repo update

# Verify repo
helm search repo gloo-platform

# Expected output:
# NAME                            CHART VERSION   APP VERSION     DESCRIPTION
# gloo-platform/gloo-platform     2.0.0           2.0.0           Gloo Platform Helm Chart
```

### 4.4 Install istioctl (Optional, for Debugging)

```bash
# Install istioctl
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.19.0 sh -

# Move to PATH
sudo mv $HOME/istio-1.19.0/bin/istioctl /usr/local/bin/

# Verify installation
istioctl version
```

---

## 5. Step 3: Install Gloo Mesh Enterprise

### 5.1 Install CRDs

Gloo Mesh Enterprise uses Custom Resource Definitions (CRDs) to extend Kubernetes API:

```bash
# Install Gloo Platform CRDs
helm install gloo-platform-crds gloo-platform/gloo-platform-crds \
  --namespace ${MGMT_NAMESPACE} \
  --create-namespace \
  --version ${GLOO_VERSION} \
  --wait

# Verify CRDs are installed
kubectl get crds | grep gloo

# Expected output (partial list):
# virtualgateways.networking.gloo.solo.io
# routetables.networking.gloo.solo.io
# trafficpolicies.trafficcontrol.policy.gloo.solo.io
# workspaces.admin.gloo.solo.io
```

### 5.2 Install Management Plane (Single-Cluster Mode)

```bash
# Install Gloo Mesh Enterprise management plane
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

istiod:
  enabled: true
  global:
    proxy:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
EOF
```

**Explanation**:
- `licensing.glooMeshLicenseKey`: **Required** for Enterprise edition
- `glooMgmtServer`: Translates Gloo CRDs to Istio resources
- `glooAgent`: Reports cluster state to management plane
- `glooUi`: Enterprise dashboard (web UI)
- `istiod`: Istio control plane (manages Envoy sidecars)

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

### 5.4 Run Health Check

```bash
# Run Gloo Mesh health check
meshctl check

# Expected output:
# ✓ Gloo Mesh management plane is healthy
# ✓ Gloo Mesh agent is connected
# ✓ Istiod is running
# ✓ License is valid
```

### 5.5 Access Gloo Mesh UI (Optional)

```bash
# Port-forward to access Gloo Mesh UI
kubectl port-forward -n ${MGMT_NAMESPACE} svc/gloo-mesh-ui 8080:8080 &

# Open browser to http://localhost:8080
# Default credentials: No authentication by default (configure RBAC in production)
```

---

## 6. Step 4: Deploy Gloo Gateway

### 6.1 Install Gloo Gateway

Gloo Gateway is an Envoy-based ingress gateway that replaces Istio Ingress Gateway:

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

**Explanation**:
- `type: LoadBalancer`: Creates a GCP External Load Balancer
- `replicas: 2`: High availability (minimum for production)
- `podAntiAffinity`: Spreads gateway pods across nodes for HA

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
kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
echo ""

# Save the IP for later use
export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Gateway Load Balancer IP: ${GATEWAY_IP}"

# Wait until IP is assigned (may take 2-5 minutes)
# If empty, wait and run again:
# kubectl get svc -n ${GATEWAY_NAMESPACE}
```

### 6.4 Configure Health Check Port

```bash
# Gloo Gateway uses port 8080 for HTTP and 8443 for HTTPS by default
# Verify the service ports
kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy

# Expected output:
# NAME                 TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
# gloo-gateway-proxy   LoadBalancer   10.0.0.123     34.0.0.1      8080:30XXX/TCP,8443:30XXX/TCP   2m
```

---

## 7. Step 5: Configure Workspace and Isolation

### 7.1 Create Workspace for Team Isolation

Workspace is Gloo Mesh's abstraction for multi-tenant isolation:

```bash
# Create Workspace YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/01-workspace.yaml
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
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/01-workspace.yaml
```

**Explanation**:
- Workspace defines which namespaces belong to a team/tenant
- Policies and routes are scoped to the Workspace
- Prevents cross-team interference

### 7.2 Configure Workspace Settings

```bash
# Create WorkspaceSettings YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/02-workspace-settings.yaml
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
    serviceIsolation:
      enabled: false  # Enable in multi-tenant environments
    trimProxyConfig:
      enabled: true   # Reduce sidecar memory footprint
EOF

# Apply WorkspaceSettings
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/02-workspace-settings.yaml
```

**Explanation**:
- `importFrom`: Which Workspaces can import services from
- `exportTo`: Which Workspaces can see services from this Workspace
- `serviceIsolation`: Enforces namespace-level isolation
- `trimProxyConfig`: Optimizes Envoy configuration (reduces memory usage)

### 7.3 Verify Workspace Configuration

```bash
# Check Workspace status
kubectl get workspace -n ${MGMT_NAMESPACE} team-a-workspace -o yaml

# Check WorkspaceSettings status
kubectl get workspacesettings -n ${WORKLOAD_NAMESPACE} team-a-settings -o yaml
```

---

## 8. Step 6: Deploy Sample Backend Service

### 8.1 Create Sample Application Deployment

```bash
# Create backend deployment YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/03-backend-deployment.yaml
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
        <p>Mesh: Gloo Mesh Enterprise</p>
    </body>
    </html>
  healthz: "OK"
EOF

# Apply deployment
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/03-backend-deployment.yaml
```

### 8.2 Create Kubernetes Service

```bash
# Create service YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/04-backend-service.yaml
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
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/04-backend-service.yaml
```

### 8.3 Enable Automatic Sidecar Injection

```bash
# Label namespace for automatic sidecar injection
kubectl label namespace ${WORKLOAD_NAMESPACE} istio-injection=enabled

# Verify label
kubectl get namespace ${WORKLOAD_NAMESPACE} --show-labels

# Expected output:
# NAME               STATUS   AGE     LABELS
# team-a-runtime     Active   5m      istio-injection=enabled
```

### 8.4 Verify Backend Deployment

```bash
# Wait for deployment to be ready
kubectl wait --for=condition=Ready pods -l app=api1-backend -n ${WORKLOAD_NAMESPACE} --timeout=300s

# Check pod status (should show 2/2 containers = app + sidecar)
kubectl get pods -n ${WORKLOAD_NAMESPACE}

# Expected output:
# NAME                            READY   STATUS    RESTARTS   AGE
# api1-backend-xxxxx              2/2     Running   0          2m
# api1-backend-xxxxx              2/2     Running   0          2m

# Verify sidecar injection
kubectl get pod -n ${WORKLOAD_NAMESPACE} -l app=api1-backend -o jsonpath='{.items[0].spec.containers[*].name}'
echo ""
# Expected output: api1-backend istio-proxy
```

### 8.5 Test Backend Connectivity (Internal)

```bash
# Get a backend pod name
BACKEND_POD=$(kubectl get pods -n ${WORKLOAD_NAMESPACE} -l app=api1-backend -o jsonpath='{.items[0].metadata.name}')

# Test from within the mesh (from gateway namespace)
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -n ${GATEWAY_NAMESPACE} -- \
  curl -s http://api1-backend.${WORKLOAD_NAMESPACE}.svc.cluster.local:8080/healthz

# Expected output: OK
```

---

## 9. Step 7: Configure VirtualGateway and RouteTable

### 9.1 Create VirtualGateway

VirtualGateway defines the ingress gateway listener configuration:

```bash
# Create VirtualGateway YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/05-virtual-gateway.yaml
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
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/05-virtual-gateway.yaml
```

**Explanation**:
- `workloads.selector`: Targets Gloo Gateway pods
- `listeners[0].port`: Listens on port 8080 (HTTP)
- `allowedRouteTables`: Which RouteTables can bind to this gateway

### 9.2 Create RouteTable

RouteTable defines HTTP routing rules (replaces Istio VirtualService):

```bash
# Create RouteTable YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/06-route-table.yaml
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
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/06-route-table.yaml
```

**Explanation**:
- `hosts`: Matches incoming Host header (use specific domains in production)
- `virtualGateways`: Binds to the VirtualGateway created earlier
- `http.matchers`: URI prefix matching
- `forwardTo.destinations`: Routes to backend service

### 9.3 Verify Gateway and Route Configuration

```bash
# Check VirtualGateway status
kubectl get virtualgateway -n ${WORKLOAD_NAMESPACE} team-a-gateway -o yaml

# Check RouteTable status
kubectl get routetable -n ${WORKLOAD_NAMESPACE} api1-route -o yaml

# Verify translated Istio resources (Gloo auto-generates these)
kubectl get virtualservice -n ${WORKLOAD_NAMESPACE}
kubectl get gateway -n ${WORKLOAD_NAMESPACE}
```

---

## 10. Step 8: Configure mTLS and Traffic Policies

### 10.1 Enable Mesh-Wide STRICT mTLS

```bash
# Create PeerAuthentication for STRICT mTLS
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/07-peer-authentication.yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default-strict
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF

# Apply PeerAuthentication
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/07-peer-authentication.yaml
```

**Explanation**:
- `STRICT` mode: All traffic must be mTLS encrypted
- Applied mesh-wide (istio-system namespace)
- Rejects plaintext traffic between sidecars

### 10.2 Create TrafficPolicy for Backend

TrafficPolicy controls traffic behavior to specific destinations:

```bash
# Create TrafficPolicy YAML
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/08-traffic-policy.yaml
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
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/08-traffic-policy.yaml
```

**Explanation**:
- `connectionPool`: Limits concurrent connections
- `loadBalancer`: Round-robin distribution
- `outlierDetection`: Ejects unhealthy endpoints (circuit breaker)

### 10.3 Create AccessPolicy (Optional L7 Authorization)

```bash
# Create AccessPolicy YAML (restrict access to gateway only)
cat <<EOF > /Users/lex/git/knowledge/gcp/asm/gloo/yamls/09-access-policy.yaml
apiVersion: security.policy.gloo.solo.io/v2
kind: AccessPolicy
metadata:
  name: allow-gateway-to-api1
  namespace: ${WORKLOAD_NAMESPACE}
spec:
  applyToWorkloads:
  - selector:
      labels:
        app: api1-backend
  config:
    authn:
      tlsMode: STRICT
    authz:
      allowedClients:
      - serviceAccountSelector:
          name: gloo-gateway-sa
          namespace: ${GATEWAY_NAMESPACE}
EOF

# Apply AccessPolicy (optional, uncomment if needed)
# kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/09-access-policy.yaml
```

**Note**: AccessPolicy is optional. Enable it in production for strict L7 authorization.

### 10.4 Verify mTLS Configuration

```bash
# Check PeerAuthentication
kubectl get peerauthentication -n istio-system default-strict -o yaml

# Check TrafficPolicy status
kubectl get trafficpolicy -n ${WORKLOAD_NAMESPACE} api1-backend-policy -o yaml

# Verify mTLS status using istioctl
istioctl proxy-status | grep ${WORKLOAD_NAMESPACE}

# Expected output:
# NAME                            CLUSTER        CDS        LDS        EDS        RDS        ECDS                         ISTIOD                     VERSION
# api1-backend-xxxxx              KUBERNETES     SYNCED     SYNCED     SYNCED     SYNCED     SYNCED  2024-04-17T10:00:00Z istiod-xxxxx  1.19.0
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

### 11.2 Configure DNS (Optional)

For production, configure DNS to point to the gateway IP:

```bash
# Example: Create a DNS A record (using gcloud DNS)
# Replace with your actual DNS zone and domain
# gcloud dns record-sets create api1.example.com \
#   --type=A \
#   --ttl=300 \
#   --rrdatas=${GATEWAY_IP} \
#   --zone=your-dns-zone
```

### 11.3 Test External Access

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
```

```bash
# Test with Host header (if using custom domain)
curl -v -H "Host: api1.example.com" http://${GATEWAY_IP}:8080/api1
```

### 11.4 Configure HTTPS (Optional, requires TLS certificate)

```bash
# Create TLS secret (requires certificate)
# kubectl create secret tls gateway-tls-secret \
#   --cert=path/to/cert.pem \
#   --key=path/to/key.pem \
#   -n ${GATEWAY_NAMESPACE}

# Update VirtualGateway to use TLS
# See Appendix for HTTPS configuration example
```

---

## 12. Step 10: Validate End-to-End Connectivity

### 12.1 End-to-End Test Script

```bash
#!/bin/bash
# e2e-validation.sh

set -e

GATEWAY_IP=$(kubectl get svc -n gloo-gateway gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
WORKLOAD_NS="team-a-runtime"

echo "=== Gloo Mesh E2E Validation ==="
echo "Gateway IP: ${GATEWAY_IP}"
echo ""

# Test 1: Gateway Pod Health
echo "Test 1: Gateway Pod Health"
kubectl get pods -n gloo-gateway -l app=gloo-gateway
echo ""

# Test 2: Backend Pod Health
echo "Test 2: Backend Pod Health"
kubectl get pods -n ${WORKLOAD_NS} -l app=api1-backend
echo ""

# Test 3: External Access via Gateway
echo "Test 3: External Access via Gateway"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://${GATEWAY_IP}:8080/api1)
if [ "${RESPONSE}" == "200" ]; then
  echo "✓ External access successful (HTTP ${RESPONSE})"
else
  echo "✗ External access failed (HTTP ${RESPONSE})"
  exit 1
fi
echo ""

# Test 4: mTLS Verification
echo "Test 4: mTLS Verification"
mTLS_STATUS=$(kubectl exec -n ${WORKLOAD_NS} $(kubectl get pods -n ${WORKLOAD_NS} -l app=api1-backend -o jsonpath='{.items[0].metadata.name}') -c istio-proxy -- \
  curl -s localhost:15000/clusters | grep -c "api1-backend" || true)
if [ "${mTLS_STATUS}" -gt 0 ]; then
  echo "✓ mTLS configured correctly"
else
  echo "⚠ mTLS status unclear (may need manual verification)"
fi
echo ""

# Test 5: RouteTable Translation
echo "Test 5: RouteTable Translation"
kubectl get virtualservice -n ${WORKLOAD_NS} -l "reconciler.mesh.gloo.solo.io/name"
echo ""

echo "=== All Tests Completed ==="
```

Save and run:

```bash
chmod +x /Users/lex/git/knowledge/gcp/asm/gloo/yamls/e2e-validation.sh
bash /Users/lex/git/knowledge/gcp/asm/gloo/yamls/e2e-validation.sh
```

### 12.2 Manual Validation Commands

```bash
# 1. Check all Gloo resources
kubectl get virtualgateway,routetable,trafficpolicy -n ${WORKLOAD_NAMESPACE}

# 2. Check translated Istio resources
kubectl get gateway,virtualservice,destinationrule -n ${WORKLOAD_NAMESPACE}

# 3. Check Envoy proxy configuration
GATEWAY_POD=$(kubectl get pods -n ${GATEWAY_NAMESPACE} -l app=gloo-gateway -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config route ${GATEWAY_POD} -n ${GATEWAY_NAMESPACE}

# 4. Check endpoint connectivity
istioctl proxy-config endpoint ${GATEWAY_POD} -n ${GATEWAY_NAMESPACE} | grep api1-backend

# 5. Check access logs
kubectl logs -n ${GATEWAY_NAMESPACE} ${GATEWAY_POD} -c gloo-gateway-proxy | tail -20
```

### 12.3 Expected Test Results

```
=== Gloo Mesh E2E Validation ===
Gateway IP: 34.0.0.1

Test 1: Gateway Pod Health
NAME                            READY   STATUS    RESTARTS   AGE
gloo-gateway-xxxxx              1/1     Running   0          10m
gloo-gateway-xxxxx              1/1     Running   0          10m

Test 2: Backend Pod Health
NAME                            READY   STATUS    RESTARTS   AGE
api1-backend-xxxxx              2/2     Running   0          8m
api1-backend-xxxxx              2/2     Running   0          8m

Test 3: External Access via Gateway
✓ External access successful (HTTP 200)

Test 4: mTLS Verification
✓ mTLS configured correctly

Test 5: RouteTable Translation
NAME               STATUS   AGE
api1-route         Active   5m

=== All Tests Completed ===
```

---

## 13. Troubleshooting Guide

### 13.1 Common Issues and Solutions

#### Issue 1: Gateway LoadBalancer IP Not Assigned

**Symptoms**: `EXTERNAL-IP` shows `<pending>`

**Solutions**:
```bash
# Check if GCP Load Balancer is being created
gcloud compute forwarding-rules list --project=${GCP_PROJECT_ID}

# Check service events
kubectl describe svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy

# Verify GCP quotas
gcloud compute project-info describe --project=${GCP_PROJECT_ID}
```

#### Issue 2: 503 Service Unavailable

**Symptoms**: `curl` returns HTTP 503

**Solutions**:
```bash
# Check if backend pods are ready
kubectl get pods -n ${WORKLOAD_NAMESPACE}

# Check endpoint exists
istioctl proxy-config endpoint ${GATEWAY_POD} -n ${GATEWAY_NAMESPACE} | grep api1-backend

# Check RouteTable status
kubectl describe routetable -n ${WORKLOAD_NAMESPACE} api1-route

# Check translated VirtualService
kubectl get virtualservice -n ${WORKLOAD_NAMESPACE} -o yaml
```

#### Issue 3: mTLS Handshake Failure

**Symptoms**: Connection errors, TLS handshake failures

**Solutions**:
```bash
# Check PeerAuthentication mode
kubectl get peerauthentication -A

# Verify sidecar certificates
istioctl proxy-config secret ${BACKEND_POD} -n ${WORKLOAD_NAMESPACE}

# Check AccessPolicy (if enabled)
kubectl get accesspolicy -n ${WORKLOAD_NAMESPACE} -o yaml

# Review Envoy logs for RBAC denials
kubectl logs ${BACKEND_POD} -n ${WORKLOAD_NAMESPACE} -c istio-proxy | grep -i "rbac\|403"
```

#### Issue 4: Gloo Mesh Translation Failures

**Symptoms**: RouteTable not translated to VirtualService

**Solutions**:
```bash
# Check management plane logs
kubectl logs -n ${MGMT_NAMESPACE} deployment/gloo-mesh-mgmt-server | grep -i error

# Check resource status
kubectl get routetable -n ${WORKLOAD_NAMESPACE} api1-route -o jsonpath='{.status}'

# Verify Workspace configuration
kubectl get workspace -n ${MGMT_NAMESPACE} -o yaml | grep -A10 namespaces

# Run health check
meshctl check
```

### 13.2 Debug Commands Reference

```bash
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

# ─── Envoy Proxy Diagnostics ─────────────────────

# Proxy status
istioctl proxy-status

# Listener configuration
istioctl proxy-config listener ${GATEWAY_POD} -n ${GATEWAY_NAMESPACE}

# Route configuration
istioctl proxy-config route ${GATEWAY_POD} -n ${GATEWAY_NAMESPACE}

# Cluster (upstream) configuration
istioctl proxy-config cluster ${GATEWAY_POD} -n ${GATEWAY_NAMESPACE}

# Endpoint configuration
istioctl proxy-config endpoint ${GATEWAY_POD} -n ${GATEWAY_NAMESPACE}

# ─── Log Analysis ────────────────────────────────

# Gateway logs
kubectl logs -n ${GATEWAY_NAMESPACE} -l app=gloo-gateway --tail=100

# Management plane logs
kubectl logs -n ${MGMT_NAMESPACE} -l app=gloo-mesh-mgmt-server --tail=100

# Sidecar logs (backend)
kubectl logs -n ${WORKLOAD_NAMESPACE} -l app=api1-backend -c istio-proxy --tail=50
```

---

## 14. Appendix: Complete YAML Files

### 14.1 All-in-One Installation Script

```bash
#!/bin/bash
# install-gloo-e2e.sh

set -e

# Configuration
export GCP_PROJECT_ID="your-gcp-project-id"
export GCP_REGION="us-central1"
export GKE_CLUSTER_NAME="gloo-gke-cluster"
export GLOO_VERSION="2.0.0"
export LICENSE_KEY="your-solo-enterprise-license-key"
export MGMT_NAMESPACE="gloo-mesh"
export GATEWAY_NAMESPACE="gloo-gateway"
export WORKLOAD_NAMESPACE="team-a-runtime"

echo "=== Starting Gloo Mesh Enterprise Installation ==="

# Step 1: Create GKE cluster (if not exists)
echo "Step 1: Creating GKE cluster..."
gcloud container clusters create ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION} \
  --cluster-version=1.28 \
  --machine-type=e4-standard-4 \
  --num-nodes=3 \
  --enable-autoscaling \
  --enable-autoupgrade \
  --enable-autorepair \
  --disk-size=100 \
  --enable-ip-alias \
  --labels="env=prod,team=platform,mesh=gloo"

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

# Step 5: Install management plane
echo "Step 5: Installing management plane..."
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

# Step 8: Deploy sample application
echo "Step 8: Deploying sample application..."
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/03-backend-deployment.yaml
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/04-backend-service.yaml
kubectl label namespace ${WORKLOAD_NAMESPACE} istio-injection=enabled --overwrite

# Step 9: Configure Gloo resources
echo "Step 9: Configuring Gloo resources..."
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/01-workspace.yaml
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/02-workspace-settings.yaml
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/05-virtual-gateway.yaml
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/06-route-table.yaml
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/07-peer-authentication.yaml
kubectl apply -f /Users/lex/git/knowledge/gcp/asm/gloo/yamls/08-traffic-policy.yaml

# Step 10: Validate installation
echo "Step 10: Validating installation..."
meshctl check

echo ""
echo "=== Installation Complete ==="
echo "Gateway IP: $(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "Test access: curl http://<GATEWAY_IP>:8080/api1"
```

### 14.2 HTTPS Configuration Example

```yaml
# 05-virtual-gateway-https.yaml
apiVersion: networking.gloo.solo.io/v2
kind: VirtualGateway
metadata:
  name: team-a-gateway
  namespace: team-a-runtime
spec:
  workloads:
  - selector:
      labels:
        app: gloo-gateway
      namespace: gloo-gateway
  listeners:
  - port:
      number: 8443
    tls:
      mode: SIMPLE
      secretName: gateway-tls-secret  # Kubernetes TLS secret name
    allowedRouteTables:
    - host: "*.example.com"
```

```bash
# Create TLS secret
kubectl create secret tls gateway-tls-secret \
  --cert=path/to/tls.crt \
  --key=path/to/tls.key \
  -n gloo-gateway
```

### 14.3 RouteTable Delegation Example

```yaml
# Root RouteTable (Platform Team)
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: root-route
  namespace: team-a-runtime
spec:
  hosts:
  - "*.example.com"
  virtualGateways:
  - name: team-a-gateway
    namespace: team-a-runtime
  http:
  - name: delegate-to-teams
    delegate:
      routeTables:
      - labels:
          team: backend
      sortMethod: ROUTE_SPECIFICITY

---
# Child RouteTable (Backend Team)
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: api1-route
  namespace: team-a-runtime
  labels:
    team: backend
spec:
  http:
  - name: api1-route
    matchers:
    - uri:
        prefix: /api1
    forwardTo:
      destinations:
      - ref:
          name: api1-backend
          namespace: team-a-runtime
        port:
          number: 8080
```

### 14.4 Production-Ready Gateway Configuration

```yaml
# production-gateway-values.yaml
glooGateway:
  enabled: true
  gatewayProxies:
    gatewayProxy:
      service:
        type: LoadBalancer
        annotations:
          service.beta.kubernetes.io/gcp-load-balancer-type: "External"
          service.beta.kubernetes.io/gcp-global-access: "true"
      deployment:
        replicas: 3
        strategy:
          type: RollingUpdate
          rollingUpdate:
            maxSurge: 1
            maxUnavailable: 0
      resources:
        requests:
          cpu: 500m
          memory: 512Mi
        limits:
          cpu: 2000m
          memory: 2Gi
      podTemplate:
        terminationGracePeriodSeconds: 60
        affinity:
          podAntiAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: gloo-gateway
              topologyKey: kubernetes.io/hostname
        nodeSelector:
          node-pool: gateway-pool
        tolerations:
        - key: "gateway"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"
      hpa:
        enabled: true
        minReplicas: 3
        maxReplicas: 10
        metrics:
        - type: Resource
          resource:
            name: cpu
            target:
              type: Utilization
              averageUtilization: 70
      pdb:
        enabled: true
        minAvailable: 2
```

---

## Quick Reference Cheatsheet

### Installation Commands

```bash
# Install meshctl
curl -sL https://run.solo.io/meshctl/install | sh

# Add Helm repo
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts

# Install CRDs
helm install gloo-platform-crds gloo-platform/gloo-platform-crds -n gloo-mesh --create-namespace

# Install management plane
helm install gloo-platform gloo-platform/gloo-platform -n gloo-mesh --values values.yaml

# Install gateway
helm install gloo-gateway gloo-platform/gloo-platform -n gloo-gateway --values gateway-values.yaml
```

### Diagnostic Commands

```bash
# Health check
meshctl check

# View resources
kubectl get virtualgateway,routetable,trafficpolicy -A

# View translated Istio resources
kubectl get vs,dr,gw -A -l "reconciler.mesh.gloo.solo.io/name"

# Proxy diagnostics
istioctl proxy-status
istioctl proxy-config route <pod> -n <namespace>
```

### Key Ports

| Component            | Port  | Protocol    |
| -------------------- | ----- | ----------- |
| Gloo Gateway (HTTP)  | 8080  | HTTP        |
| Gloo Gateway (HTTPS) | 8443  | HTTPS       |
| Istiod               | 15010 | HTTP (xDS)  |
| Istiod               | 15012 | HTTPS (xDS) |
| Envoy Admin          | 15000 | HTTP        |

---

## References

- [Gloo Mesh Enterprise Documentation](https://docs.solo.io/gloo-mesh-enterprise/)
- [Gloo Gateway Documentation](https://docs.solo.io/gloo-mesh-gateway/)
- [Solo.io GitHub](https://github.com/solo-io/gloo-mesh)
- [Istio Documentation](https://istio.io/latest/docs/)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)

---

*Document Version: 1.0*
*Created: 2026-04-17*
*Last Updated: 2026-04-17*
*Status: Production-Ready*
