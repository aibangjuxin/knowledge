# End-to-End Guide: Installing Gloo Mesh Enterprise on GKE

This guide provides a step-by-step process to install **Gloo Mesh Enterprise** on Google Kubernetes Engine (GKE), replacing existing managed Istio (ASM) installations. We will cover the installation of the management plane, cluster registration, gateway deployment, and exposing a sample API.

---

## 1. Architecture Overview

Gloo Mesh Enterprise is a management plane that sits on top of Istio. It abstracts complex Istio configurations into higher-level, multi-cluster friendly Custom Resource Definitions (CRDs).

### Key Concepts
- **Management Plane**: The central controller (`gloo-mesh-mgmt-server`) that translates Gloo CRDs into Istio resources.
- **Agent**: A lightweight component (`gloo-mesh-agent`) running in each workload cluster to report status and receive configurations.
- **Workspace**: A logical boundary for services and policies, enabling multi-tenancy and isolation.
- **VirtualGateway**: Defines entry points (listeners, TLS) for your ingress traffic.
- **RouteTable**: Defines how traffic is routed to specific services (equivalent to Istio VirtualService but more powerful).

---

## 2. Prerequisites

Before starting, ensure you have:
1.  **A GKE Cluster**: Recommended version 1.28+.
2.  **Solo.io License Key**: An Enterprise License Key for Gloo Mesh.
3.  **Helm**: Version 3.12+.
4.  **kubectl**: Configured to your GKE cluster.

---

## 3. Step 1: Install CLIs and Add Helm Repos

First, install the `meshctl` CLI, which is the specialized tool for Gloo Mesh.

```bash
# Install meshctl
curl -sL https://run.solo.io/meshctl/install | sh
export PATH=$HOME/.gloo-mesh/bin:$PATH

# Verify installation
meshctl version

# Add the Solo.io Helm repository
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts
helm repo update
```

---

## 4. Step 2: Install Gloo Platform CRDs

Install the required CRDs for the Gloo Platform.

```bash
export GLOO_VERSION=2.5.5 # Replace with your target version

helm install gloo-platform-crds gloo-platform/gloo-platform-crds \
  --namespace gloo-mesh \
  --create-namespace \
  --version ${GLOO_VERSION}
```

---

## 5. Step 3: Install Gloo Management Plane & Agent

In a single-cluster setup, the Management Plane and the Agent reside in the same cluster. We will use a `values.yaml` file for configuration.

```bash
# Set your license key
export GLOO_GATEWAY_LICENSE_KEY="your-license-key-here"

# Install Gloo Platform
helm install gloo-platform gloo-platform/gloo-platform \
  --namespace gloo-mesh \
  --version ${GLOO_VERSION} \
  --values yamls/gloo-setup/gloo-platform-values.yaml \
  --set licensing.glooMeshLicenseKey=${GLOO_GATEWAY_LICENSE_KEY}
```

> **Note**: In production, you would typically have a dedicated Management Cluster and multiple Workload Clusters.

---

## 6. Step 4: Register the Cluster

Gloo Mesh needs to "know" about the cluster it is managing. For a single-cluster setup, you must register it with itself.

```bash
meshctl cluster register \
  --cluster-name=gke-cluster-1 \
  --mgmt-context=$(kubectl config current-context)
```

Verify the registration status:
```bash
meshctl check
```

---

## 7. Step 5: Deploy Gloo Gateway (Ingress)

Deploy the Envoy-based Ingress Gateway. This replaces the standard Istio Ingress Gateway.

```bash
# Create the namespace for the gateway
kubectl create namespace gloo-gateway

# Install the Gateway component
helm install gloo-gateway gloo-platform/gloo-platform \
  --namespace gloo-gateway \
  --version ${GLOO_VERSION} \
  --values yamls/gloo-setup/gloo-gateway-values.yaml
```

---

## 8. Step 6: Configure Workspace

Workspaces are the foundation of Gloo Mesh. Even for a single cluster, you should define a Workspace to scope your services and policies.

```bash
# Apply the Workspace and WorkspaceSettings
kubectl apply -f yamls/gloo-setup/workspace-setup.yaml
```

---

## 9. Step 7: Deploy Sample Application

We will deploy a simple `httpbin` application into the `sample-app` namespace. Note the `istio-injection: enabled` label, as Gloo Mesh utilizes the underlying Istio sidecar.

```bash
# Deploy the sample app
kubectl apply -f yamls/gloo-setup/sample-app.yaml
```

Wait for the pods to be ready:
```bash
kubectl get pods -n sample-app -w
```

---

## 10. Step 8: Expose the API via Gloo Gateway

Now, we define a `VirtualGateway` to listen for traffic and a `RouteTable` to route that traffic to our `httpbin` service.

```bash
# Apply the routing configuration
kubectl apply -f yamls/gloo-setup/routing-setup.yaml
```

---

## 11. Step 9: Verification

### 1. Find the External IP of the Gateway
```bash
kubectl get svc -n gloo-gateway
```
Wait until the `EXTERNAL-IP` is assigned to the `gloo-gateway-proxy` service.

### 2. Test the API
```bash
# Replace <GATEWAY_IP> with the actual External IP
export GATEWAY_IP=$(kubectl get svc -n gloo-gateway gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -i http://${GATEWAY_IP}/get
```

You should receive a `200 OK` response with the JSON output from `httpbin`.

---

## 12. Troubleshooting

If things aren't working as expected, use these commands:

- **Check Gloo Mesh Health**: `meshctl check`
- **Inspect Management Server Logs**: `kubectl logs -n gloo-mesh deployment/gloo-mesh-mgmt-server`
- **Inspect Agent Logs**: `kubectl logs -n gloo-mesh deployment/gloo-mesh-agent`
- **Debug Envoy Config**: 
  ```bash
  istioctl proxy-config routes -n gloo-gateway deployment/gloo-gateway-proxy
  ```

---

## Summary of Files Created

| File Path | Description |
|---|---|
| `yamls/gloo-setup/gloo-platform-values.yaml` | Helm values for Management Plane and Agent. |
| `yamls/gloo-setup/gloo-gateway-values.yaml` | Helm values for the Ingress Gateway. |
| `yamls/gloo-setup/workspace-setup.yaml` | Definition of the Workspace and Settings. |
| `yamls/gloo-setup/sample-app.yaml` | Sample backend app (httpbin). |
| `yamls/gloo-setup/routing-setup.yaml` | VirtualGateway and RouteTable configuration. |
