# How to Setup Istio Ingress Gateway (No Sidecar) on GKE with ASM Managed Control Plane

A complete step-by-step guide to deploying an Istio Ingress Gateway with TLS termination, without injecting sidecar proxies into backend pods, using Google Cloud Service Mesh (ASM) managed control plane.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Prerequisites](#prerequisites)
3. [Step 1: Enable Required APIs](#step-1-enable-required-apis)
4. [Step 2: Register Cluster to Fleet](#step-2-register-cluster-to-fleet)
5. [Step 3: Enable Managed Service Mesh](#step-3-enable-managed-service-mesh)
6. [Step 4: Enable Gateway API on GKE Cluster](#step-4-enable-gateway-api-on-gke-cluster)
7. [Step 5: Verify ASM Control Plane Status](#step-5-verify-asm-control-plane-status)
8. [Step 6: Generate TLS Certificates](#step-6-generate-tls-certificates)
9. [Step 7: Deploy YAML Resources](#step-7-deploy-yaml-resources)
10. [Step 8: Verify Deployment](#step-8-verify-deployment)
11. [Troubleshooting Guide](#troubleshooting-guide)
12. [YAML Resource Files Reference](#yaml-resource-files-reference)
13. [Accessing the Service](#accessing-the-service)

---

## Architecture Overview

```yaml
Internet
   |
   v
GCP LoadBalancer (88.88.243.168:443)
   |
   v
Istio Ingress Gateway (istio-ingressgateway-int namespace)
  Pod with ASM managed sidecar (image:auto)
  TLS termination at port 443 (Envoy terminates TLS using mounted certs)
   |
   |  VirtualService routes *.team-a.appdev.aibang
   |  DestinationRule (TLS SIMPLE mode, originates TLS to backend)
   v
Runtime Pod (teama-nosidecare-rt-ns-int namespace)
  Plain nginx (no sidecar)
  HTTPS on port 8443 (self-signed cert)
  Returns: "env0-region-runtimepod response"
```

Key design decisions:
- **Gateway namespace** (`istio-ingressgateway-int`): Uses ASM managed control plane (`istio.io/rev=asm-managed` label). Pod uses `image:auto` to trigger ASM managed sidecar injection via `inject.istio.io/templates: gateway`.
- **Runtime namespace** (`teama-nosidecare-rt-ns-int`): Sidecar injection **explicitly disabled** (`istio-injection: disabled`). Backend pod is plain nginx.
- **TLS termination at Gateway**: Gateway terminates HTTPS using file-mounted certificates (not SDS). The ASM managed control plane pushes TLS config via xDS but certs are read from mounted files.
- **TLS origination to backend**: DestinationRule uses `tls.mode: SIMPLE` so Envoy originates TLS to the backend runtime pod on port 8443.
- **No mTLS**: Because the runtime namespace has no sidecar, this is NOT mesh mTLS. It is plain HTTPS TLS origination.

---

## Prerequisites

- GKE cluster running on GCP (europe-west2 region)
- Project ID: `aibang-12345678-ajbx-dev`
- Cluster name: `dev-lon-cluster-xxxxxx`
- A bastion host with IAP tunneling access: `dev-lon-bastion-public` in zone `europe-west2-a`
- kubectl configured to access the cluster via the bastion
- Project owner or editor permissions

### Connect to Cluster via Bastion

```bash
gcloud compute ssh dev-lon-bastion-public \
    --zone=europe-west2-a \
    --tunnel-through-iap \
    --command="kubectl get nodes"
```

Or set up kubectl context:

```bash
gcloud compute ssh dev-lon-bastion-public \
    --zone=europe-west2-a \
    --tunnel-through-iap \
    --command="gcloud container clusters get-credentials dev-lon-cluster-xxxxxx --region=europe-west2"
```

---

## Step 1: Enable Required APIs

Enable all necessary GCP APIs for ASM:

```bash
gcloud services enable \
    mesh.googleapis.com \
    gkehub.googleapis.com \
    anthos.googleapis.com \
    multiclustermesh.googleapis.com \
    --project=aibang-12345678-ajbx-dev
```

Expected output:
```bash
Operation "operations/acat.p2-487126826743-7a81ae37-af71-4ebe-88b1-ec234bde785c" finished successfully.
```

---

## Step 2: Register Cluster to Fleet

### 2.1 Verify Fleet Status

```bash
gcloud container fleet list
```

If cloudresourcemanager API is not enabled:
```bash
API [cloudresourcemanager.googleapis.com] not enabled on project [aibang-12345678-ajbx-dev]. Would you
like to enable and retry (this will take a few minutes)? (y/N)?
# Answer: y
```

### 2.2 Register the Cluster

```bash
gcloud container fleet memberships register aibang-master \
    --gke-cluster=europe-west2/dev-lon-cluster-xxxxxx \
    --enable-workload-identity
```

Expected output:
```bash
Membership [projects/aibang-12345678-ajbx-dev/locations/europe-west2/memberships/aibang-master] already registered with the cluster
Finished registering to the Fleet.
```

### 2.3 List Memberships

```bash
gcloud container fleet memberships list
```

Expected output:
```bash
NAME           UNIQUE_ID                             LOCATION
aibang-master  b70501ce-2ebb-406d-995f-d3fda89ca7d6  europe-west2
```

---

## Step 3: Enable Managed Service Mesh

### 3.1 Enable Fleet Mesh

```bash
gcloud container fleet mesh enable --project=aibang-12345678-ajbx-dev
```

Expected output:
```bash
Waiting for Feature Service Mesh to be created...done.
```

### 3.2 Set Management to Automatic

```bash
gcloud container fleet mesh update \
    --management automatic \
    --memberships aibang-master \
    --project=aibang-12345678-ajbx-dev
```

Expected output:
```bash
Waiting for MembershipFeature projects/aibang-12345678-ajbx-dev/locations/europe-west2/memberships/aibang-master/features/servicemesh to be updated...done.
```

---

## Step 4: Enable Gateway API on GKE Cluster

GKE may not have all Gateway API features enabled by default. Enable them:

```bash
gcloud container clusters update dev-lon-cluster-xxxxxx \
    --region=europe-west2 \
    --gateway-api=standard
```

Verify the Gateway API channel:

```bash
gcloud container clusters describe dev-lon-cluster-xxxxxx \
    --region=europe-west2 \
    --format="value(gatewayApiConfig.channel)"
```

Expected output:
```bash
CHANNEL_STANDARD
```

### 4.1 Verify GatewayClass Exists

```bash
kubectl get gatewayclass
```

Expected output:
```bash
NAME                               CONTROLLER                    ACCEPTED   AGE
gke-l7-global-external-managed     networking.gke.io/gateway     True       11m
gke-l7-gxlb                        networking.gke.io/gateway     True       11m
gke-l7-regional-external-managed   networking.gke.io/gateway     True       11m
gke-l7-rilb                        networking.gke.io/gateway     True       11m
istio                              istio.io/gateway-controller   True       14m
istio-remote                       istio.io/unmanaged-gateway    True       14m
```

All classes should show `ACCEPTED: True`.

---

## Step 5: Verify ASM Control Plane Status

### 5.1 Check Fleet Mesh Describe

```bash
gcloud container fleet mesh describe
```

Expected healthy output:
```yaml
createTime: '2026-05-16T03:45:04.984842608Z'
membershipSpecs:
  projects/487126826743/locations/europe-west2/memberships/aibang-master:
    mesh:
      management: MANAGEMENT_AUTOMATIC
membershipStates:
  projects/487126826743/locations/europe-west2/memberships/aibang-master:
    servicemesh:
      controlPlaneManagement:
        details:
        - code: REVISION_READY
          details: 'Ready: asm-managed'
        implementation: ISTIOD
        state: ACTIVE
      dataPlaneManagement:
        details:
        - code: OK
          details: Service is running.
        state: ACTIVE
    state:
      code: OK
      description: 'Revision ready for use: asm-managed.'
resourceState:
  state: ACTIVE
```

Key fields to verify:
- `controlPlaneManagement.state` should be `ACTIVE` with `REVISION_READY`
- `dataPlaneManagement.state` should be `ACTIVE`
- `resourceState.state` should be `ACTIVE`

### 5.2 Check ControlPlaneRevision

```bash
kubectl get controlplanerevision -n istio-system
```

Expected output:
```bash
NAME          RECONCILED   STALLED   AGE
asm-managed   True         False     52m
```

### 5.3 Check Namespace Labels

The gateway namespace must have the correct label for ASM managed control plane to manage it:

```bash
kubectl get ns istio-ingressgateway-int --show-labels
```

Expected output:
```bash
NAME                       STATUS   AGE   LABELS
istio-ingressgateway-int   Active   56m   ingress=int,istio.io/rev=asm-managed,kubernetes.io/metadata.name=istio-ingressgateway-int
```

The label `istio.io/rev=asm-managed` is required for ASM managed control plane to inject the gateway sidecar.

### 5.4 Verify No istiod Pod in Cluster

With ASM managed control plane, there is **no** `istiod` pod in the cluster. The control plane runs on Google infrastructure. This is by design.

```bash
kubectl get pods -n kube-system -l app=istiod
# Expected: No resources found in kube-system namespace.
```

---

## Step 6: Generate TLS Certificates

### 6.1 Certificate for Gateway (Ingress TLS Termination)

Domain: `*.team-a.appdev.aibang`
Purpose: Terminate HTTPS at the Istio Ingress Gateway

```bash
# Create a working directory
mkdir -p /tmp/tls && cd /tmp/tls

# Generate private key and certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout gateway-tls.key \
  -out gateway-tls.crt \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=Aibang/CN=*.team-a.appdev.aibang" \
  -addext "subjectAltName = DNS:*.team-a.appdev.aibang, DNS:team-a.appdev.aibang"
```

### 6.2 Certificate for Runtime Pod (Backend HTTPS)

Domain: `*.env0-region-runtimepod.aliyun.cloud.region.aibang` (or any FQDN matching the backend service)
Purpose: Backend pod serves HTTPS on port 8443 with this self-signed cert

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout runtime-tls.key \
  -out runtime-tls.crt \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=Aibang/CN=*.env0-region-runtimepod.aliyun.cloud.region.aibang" \
  -addext "subjectAltName = DNS:*.env0-region-runtimepod.aliyun.cloud.region.aibang, DNS:env0-region-runtimepod.aliyun.cloud.region.aibang"
```

### 6.3 Verify Certificates
- need notice . when I using 
- [./dp/02-gateway.yaml](./dp/02-gateway.yaml) ==> using deployment mount this key /etc/istio/gateway-cert/tls.key ==> attempt put the secret to istio-system 
```bash
# Istio Gateway CRD
# Terminates HTTPS for *.team-a.appdev.aibang
# TLS certificate is in Secret: team-a-gateway-tls
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: team-a-gateway
  namespace: istio-ingressgateway-int
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

# Check Gateway cert
openssl x509 -in gateway-tls.crt -noout -dates -subject
kubectl get secret team-a-gateway-tls -n istio-ingressgateway-int -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text|grep CN
        Issuer: C = CN, ST = Beijing, L = Beijing, O = Aibang, CN = *.team-a.appdev.aibang
        Subject: C = CN, ST = Beijing, L = Beijing, O = Aibang, CN = *.team-a.appdev.aibang

kubectl get secret team-a-gateway-tls -n istio-system -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text|grep CN
        Issuer: C = CN, ST = Beijing, L = Beijing, O = Aibang, CN = *.team-a.appdev.aibang
        Subject: C = CN, ST = Beijing, L = Beijing, O = Aibang, CN = *.team-a.appdev.aibang

 kubectl get secret env0-region-runtimepod-tls -n teama-nosidecare-rt-ns-int -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text|grep CN
        Issuer: C = CN, ST = Beijing, L = Beijing, O = Aibang, CN = *.env0-region-runtimepod.aliyun.cloud.region.aibang
        Subject: C = CN, ST = Beijing, L = Beijing, O = Aibang, CN = *.env0-region-runtimepod.aliyun.cloud.region.aibang

# Check Runtime cert
openssl x509 -in runtime-tls.crt -noout -dates -subject
```

---

### 6.4 Simple Gateway can't success 
```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: team-a-gateway
  namespace: istio-ingressgateway-int
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
      credentialName: team-a-gateway-tls
    hosts:
    - "*.team-a.appdev.aibang"
```bash
### 6.5 deploy need deleted mount 

```yaml
        volumeMounts:
        - name: gateway-cert
          mountPath: /etc/istio/gateway-cert
          readOnly: true
      volumes:
      - name: gateway-cert
        secret:
          secretName: team-a-gateway-tls
```bash
### 6.6 Using 02-gateway.yaml and add volumeMounts
- the using 02-gateway.yaml deploy and add volumeMounts 
```bash
kubectl apply -f 02-gateway.yaml
 k apply -f 02-gateway.yaml
serviceaccount/istio-ingressgateway-int-sa unchanged
role.rbac.authorization.k8s.io/istio-ingressgateway-int-role unchanged
rolebinding.rbac.authorization.k8s.io/istio-ingressgateway-int-rolebinding unchanged
deployment.apps/istio-ingressgateway-int configured
service/istio-ingressgateway-int unchanged
gateway.networking.istio.io/team-a-gateway configured

kubectl logs -l app=istio-ingressgateway-int -n istio-ingressgateway-int -c istio-proxy | grep -iE "ssl|tls|error"
2026-05-16T09:10:13.131859Z     info    cache   adding watcher for file certificate /etc/istio/gateway-cert/tls.crt
2026-05-16T09:10:13.131909Z     info    cache   read certificate from file      resource=file-cert:/etc/istio/gateway-cert/tls.crt~/etc/istio/gateway-cert/tls.key
2026-05-16T09:10:13.132027Z     info    ads     SDS: PUSH request for node:istio-ingressgateway-int-5f57955f9c-xj5xr.istio-ingressgateway-int resources:1 size:3.2kB resource:file-cert:/etc/istio/gateway-cert/tls.crt~/etc/istio/gateway-cert/tls.key
```

## Step 7: Deploy YAML Resources

All resources are organized in the `dp/` directory. Apply them in order:

### 7.1 Copy YAML Files to Bastion

```bash
gcloud compute scp --recurse --zone=europe-west2-a --tunnel-through-iap \
    /Users/lex/git/gcp/asm/dp \
    dev-lon-bastion-public:/tmp/asm-dp
```

### 7.2 Apply Resources

Apply all resources in sequence:

```bash
# Login to bastion and apply
gcloud compute ssh dev-lon-bastion-public \
    --zone=europe-west2-a \
    --tunnel-through-iap \
    --command="kubectl apply -f /tmp/asm-dp/"
```

Order of application:
1. `00-namespaces.yaml` - Create namespaces
2. `01-gateway-tls-secret.yaml` - Create TLS secret for Gateway
3. `02-gateway.yaml` - SA, Role, RoleBinding, Deployment, Service, Gateway CRD
4. `03-runtime-app.yaml` - TLS secret, ConfigMap, Deployment, Service for runtime
5. `04-istio-routing.yaml` - VirtualService and DestinationRule
6. `05-networkpolicy.yaml` - NetworkPolicy rules for runtime namespace

### 7.3 Wait for Gateway Pod to Be Ready

```bash
kubectl get pod -n istio-ingressgateway-int -w
```

Expected:
```bash
NAME                                        READY   STATUS    RESTARTS   AGE
istio-ingressgateway-int-xxxxxxxx-xxxxx       1/1     Running   0          2m
```

### 7.4 Resource Limits Note

The default deployment requests `cpu: 100m` and limits of `cpu: 2000m`. If your nodes have high CPU pressure (>90% allocated), the pod may get stuck in `Pending` state with `OutOfcpu` or `ContainerStatusUnknown`.

If that happens, patch the deployment to reduce CPU limits:

```bash
kubectl patch deployment istio-ingressgateway-int \
  -n istio-ingressgateway-int \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"istio-proxy","resources":{"requests":{"cpu":"50m","memory":"64Mi"},"limits":{"cpu":"500m","memory":"512Mi"}}}]}}}}'
```

---

## Step 8: Verify Deployment

### 8.1 Check All Resources

```bash
# Namespaces
kubectl get ns istio-ingressgateway-int teama-nosidecare-rt-ns-int

# Gateway pod
kubectl get pod -n istio-ingressgateway-int

# Gateway service (should show LoadBalancer with external IP)
kubectl get svc -n istio-ingressgateway-int

# Gateway CRD
kubectl get gateways.networking.istio.io -A

# VirtualService
kubectl get virtualservices.networking.istio.io -A

# DestinationRule
kubectl get destinationrules.networking.istio.io -A

# Runtime deployment and service
kubectl get deploy,svc -n teama-nosidecare-rt-ns-int

# NetworkPolicies
kubectl get networkpolicy -n teama-nosidecare-rt-ns-int
```

### 8.2 Check Envoy Listeners

The gateway pod must be running. Get the pod name and check listeners:

```bash
GW_POD=$(kubectl get pod -n istio-ingressgateway-int \
  -l app=istio-ingressgateway-int \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec $GW_POD -n istio-ingressgateway-int -c istio-proxy -- \
  curl -s localhost:15000/listeners
```

Expected output should include:
- `0.0.0.0_8443::0.0.0.0:8443` (HTTPS port for backend connection)
- Port 443 **is NOT directly exposed** in the pod. The Gateway Service exposes port 443 on the LoadBalancer, which forwards to port 8443 on the pod.

### 8.3 Check Mounted Certificates in Pod

```bash
GW_POD=$(kubectl get pod -n istio-ingressgateway-int \
  -l app=istio-ingressgateway-int \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec $GW_POD -n istio-ingressgateway-int -c istio-proxy -- \
  ls -la /etc/istio/gateway-cert/

  ls -la /etc/istio/gateway-cert/
total 4
drwxrwxrwt 3 root root  120 May 16 09:10 .
drwxr-xr-x 5 root root 4096 May 16 09:10 ..
drwxr-xr-x 2 root root   80 May 16 09:10 ..2026_05_16_09_10_10.1731598578
lrwxrwxrwx 1 root root   32 May 16 09:10 ..data -> ..2026_05_16_09_10_10.1731598578
lrwxrwxrwx 1 root root   14 May 16 09:10 tls.crt -> ..data/tls.crt
lrwxrwxrwx 1 root root   14 May 16 09:10 tls.key -> ..data/tls.key
```

Expected:
```bash
total 4
drwxr-xr-x 3 root root  120 May 16 07:10 .
drwxrwt 3 root root 4096 May 16 07:10 ..
lrwxrwxrwx 14 root root 14 May 16 07:10 tls.crt -> ..data/tls.crt
lrwxrwxrwx 14 root root 14 May 16 07:10 tls.key -> ..data/tls.key
```

### 8.4 Test Access via IAP Bastion

```bash
# Test HTTPS access with SNI (use --resolve to set SNI correctly)
curl -kv --resolve 'test.team-a.appdev.aibang:443:88.88.243.168' \
  'https://test.team-a.appdev.aibang/'
```

Expected response:
```bash
< HTTP/2 200
< server: istio-envoy
< content-type: application/octet-stream,text/plain
< content-length: 31

env0-region-runtimepod response
```

### 8.5 Important: Why `-H "Host:"` Alone Does Not Work

If you use:
```bash
curl -kv -H "Host: test.team-a.appdev.aibang" https://88.88.243.168/
# Result: curl: (35) Recv failure: Connection reset by peer
```

This happens because when you access `https://88.88.243.168/` directly by IP, curl sets the TLS SNI to the IP address, not to the hostname in the Host header. The server certificate is for `*.team-a.appdev.aibang`, so TLS verification fails during the handshake — before the HTTP Host header is even sent.

**The correct approach** is to use `--resolve` to bind the hostname to the IP, which sets the SNI correctly:
```bash
curl -kv --resolve 'test.team-a.appdev.aibang:443:88.88.243.168' \
  'https://test.team-a.appdev.aibang/'
```

Alternatively, add an entry to `/etc/hosts`:
```bash
88.88.243.168 test.team-a.appdev.aibang
```bash
Then:
```bash
curl -kv -H "Host: test.team-a.appdev.aibang" https://test.team-a.appdev.aibang/
```

---

## Troubleshooting Guide

### Issue 1: Gateway Pod Stuck in Pending (OutOfcpu)

**Symptom**: `kubectl get pod -n istio-ingressgateway-int` shows pods in `OutOfcpu` or `ContainerStatusUnknown` status.

**Cause**: Node CPU overcommitted. Original deployment requests `cpu: 100m` but limits `cpu: 2000m`. Nodes may have 90-99% CPU already allocated.

**Fix**: Reduce CPU limits as described in Step 7.4.

**Verification**:
```bash
kubectl top node  # Check actual CPU usage (should be low, e.g., 12-16%)
kubectl describe node | grep -A5 'Allocated resources'  # Check allocated requests
```

### Issue 2: HTTPS Connection Reset by Peer (TLS Handshake Failure)

**Symptom**:
```bash
curl -kv -H "Host: test.team-a.appdev.aibang" https://88.88.243.168/
* Recv failure: Connection reset by peer
curl: (35) Recv failure: Connection reset by peer
```

**Possible causes**:

#### Cause A: TLS SNI Mismatch (Most Common)
When accessing by IP address directly, SNI is set to IP, not hostname.
**Fix**: Use `--resolve` flag as shown in Step 8.4.

#### Cause B: Envoy Not Listening on Expected Port
Check listeners inside the gateway pod:
```bash
GW_POD=$(kubectl get pod -n istio-ingressgateway-int \
  -l app=istio-ingressgateway-int \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec $GW_POD -n istio-ingressgateway-int -c istio-proxy -- \
  curl -s localhost:15000/listeners
```bash
If you see `0.0.0.0_8443::0.0.0.0:8443`, the HTTPS listener is active.

#### Cause C: SDS Timeout from ASM Managed Control Plane
**Symptom**: Envoy log shows `gRPC config: initial fetch timed out for type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.Secret`
```bash
kubectl logs -l app=istio-ingressgateway-int -n istio-ingressgateway-int -c istio-proxy | grep -iE "ssl|tls|error"
2026-05-16T08:59:21.809438Z     warning envoy config external/envoy/source/extensions/config_subscription/grpc/grpc_subscription_impl.cc:130    gRPC config: initial fetch timed out for type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.Secret  thread=15
```

**Cause**: The ASM managed control plane's SDS (Secret Discovery Service) is timing out when pushing TLS secret configuration to Envoy.

**Fix**: The solution used in this setup is to use **file-mounted certificates** instead of SDS. In the `Gateway` CRD, specify:
```yaml
tls:
  mode: SIMPLE
  privateKey: /etc/istio/gateway-cert/tls.key
  serverCertificate: /etc/istio/gateway-cert/tls.crt
```bash
And mount the TLS secret as a volume in the deployment:
```yaml
volumes:
- name: gateway-cert
  secret:
    secretName: team-a-gateway-tls
volumeMounts:
- name: gateway-cert
  mountPath: /etc/istio/gateway-cert
  readOnly: true
```

### Issue 3: Gateway Service Shows No External IP

**Symptom**: `kubectl get svc -n istio-ingressgateway-int` shows `EXTERNAL-IP: <pending>`.

**Cause**: GCP LoadBalancer provisioning takes time, or there are配额 issues.

**Fix**: Wait a few minutes. If still pending:
```bash
kubectl describe svc istio-ingressgateway-int -n istio-ingressgateway-int
# Look for events showing LoadBalancer provisioning status
```

### Issue 4: VirtualService Returns 404

**Symptom**: HTTP request returns `404 Not Found` with `server: istio-envoy` header.

**Cause**: VirtualService destination host or port doesn't match the actual backend service.

**Fix**: Verify the VirtualService destination:
```bash
kubectl get vs team-a-vs -n teama-nosidecare-rt-ns-int -o yaml
# Check that destination host matches the runtime service FQDN
# e.g., env0-region-runtimepod.teama-nosidecare-rt-ns-int.svc.cluster.local
```

### Issue 5: ASM Control Plane Not Ready (REVISION_PROVISIONING)

**Symptom**: `gcloud container fleet mesh describe` shows `state: PROVISIONING` and `code: REVISION_PROVISIONING` for a long time.

**Cause**: ASM managed control plane provisioning is stuck.

**Fix**:
1. Check IAM permissions for the ASM service agent:
```bash
gcloud projects add-iam-policy-binding aibang-12345678-ajbx-dev \
    --member="serviceAccount:service-487126826743@gcp-sa-servicemesh.iam.gserviceaccount.com" \
    --role="roles/anthosservicemesh.serviceAgent"
```

2. Force re-sync by toggling management:
```bash
gcloud container fleet mesh update \
    --management automatic \
    --memberships aibang-master \
    --project=aibang-12345678-ajbx-dev
```

3. Wait 5-10 minutes and re-check.

### Issue 6: Pod Not Reaching Ready State

**Symptom**: Gateway pod shows `READY 0/1` even after several minutes.

**Diagnosis**:
```bash
# Check pod events
kubectl describe pod <pod-name> -n istio-ingressgateway-int

# Check readiness probe
# The readiness probe hits port 15021 (not 8080 or 8443)
kubectl logs <pod-name> -n istio-ingressgateway-int -c istio-proxy | grep -i 'healthz\|ready\|probe'
```

The readiness probe should be:
```yaml
readinessProbe:
  httpGet:
    path: /healthz/ready
    port: 15021
```

### Issue 7: NetworkPolicy Blocking Traffic

**Symptom**: Traffic reaches the gateway but is not forwarded to backend pods.

If you have strict NetworkPolicies in the runtime namespace, ensure the gateway's namespace is allowed:

The `default-allow-ingress-istio-int` NetworkPolicy allows ingress from `istio-ingressgateway-int` namespace pods on port 8443:
```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: istio-ingressgateway-int
        podSelector:
          matchLabels:
            app: istio-ingressgateway-int
    ports:
      - port: 8443
        protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"networking.k8s.io/v1","kind":"NetworkPolicy","metadata":{"annotations":{},"name":"default-allow-ingress-istio-int","namespace":"teama-nosidecare-rt-ns-int"},"spec":{"ingress":[{"from":[{"namespaceSelector":{"matchLabels":{"kubernetes.io/metadata.name":"istio-ingressgateway-int"}},"podSelector":{"matchLabels":{"app":"istio-ingressgateway-int"}}}],"ports":[{"port":8443,"protocol":"TCP"}]}],"policyTypes":["Ingress"]}}
  creationTimestamp: "2026-05-16T04:31:07Z"
  generation: 1
  name: default-allow-ingress-istio-int
  namespace: teama-nosidecare-rt-ns-int
  resourceVersion: "1778905867089551019"
  uid: 3d13926b-06bb-47cc-8d72-343af241c3a4
spec:
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: istio-ingressgateway-int
      podSelector:
        matchLabels:
          app: istio-ingressgateway-int
    ports:
    - port: 8443
      protocol: TCP
  podSelector: {}
  policyTypes:
  - Ingress
```

---

## YAML Resource Files Reference

All files are located at `/Users/lex/git/gcp/asm/dp/`.

### File 00-namespaces.yaml
Creates two namespaces:
- `istio-ingressgateway-int` — Gateway namespace with `istio.io/rev=asm-managed` label for ASM managed control plane
- `teama-nosidecare-rt-ns-int` — Runtime namespace with `istio-injection: disabled` to prevent sidecar injection

### File 01-gateway-tls-secret.yaml
TLS Secret `team-a-gateway-tls` in `istio-ingressgateway-int` namespace. Certificate is for `*.team-a.appdev.aibang`. Used by the Gateway for HTTPS termination.

### File 02-gateway.yaml
Contains:
- **ServiceAccount**: `istio-ingressgateway-int-sa`
- **Role**: Permission to `get`, `list`, `watch` gateways in the namespace
- **RoleBinding**: Binds the Role to the ServiceAccount
- **Deployment**: Single replica with `image:auto` for ASM managed sidecar, `inject.istio.io/templates: gateway` annotation, resource limits (50m CPU request, 500m limit), TLS secret mounted at `/etc/istio/gateway-cert/`
- **Service**: `LoadBalancer` type exposing ports 80→8080 and 443→8443
- **Gateway CRD**: Configures HTTPS on port 443 with TLS mode SIMPLE, using file-based certificate paths

### File 03-runtime-app.yaml
Contains:
- **Secret**: `env0-region-runtimepod-tls` with self-signed cert for backend HTTPS
- **ConfigMap**: `nginx-https-config` — nginx config to serve HTTPS on 8443
- **Deployment**: `env0-region-runtimepod` with 2 replicas, `sidecar.istio.io/inject: "false"` annotation, nginx with mounted TLS certs
- **Service**: `ClusterIP` on port 8443

### File 04-istio-routing.yaml
Contains:
- **VirtualService**: Routes `*.team-a.appdev.aibang` through `team-a-gateway` to `env0-region-runtimepod` on port 8443
- **DestinationRule**: Configures Envoy to originate TLS (`mode: SIMPLE`) to the backend service

### File 05-networkpolicy.yaml
Contains 8 NetworkPolicy rules for the runtime namespace:
1. `default-allow-dns` — Allow DNS (port 53)
2. `default-allow-egress-int-rt` — Allow egress to namespaces with `ingress: int` label
3. `default-allow-egress-to-drn` — Allow egress to DRN network ranges
4. `default-allow-egress-workload-identity` — Allow egress to workload identity endpoints
5. `default-allow-ingress-int-rt` — Allow ingress from namespaces with `ingress: int` label
6. `default-allow-ingress-istio-int` — Allow ingress from gateway namespace pods on port 8443
7. `default-allow-restricted-api` — Allow egress to Google restricted API (199.36.153.4/30)
8. `default-deny-all` — Deny all other ingress and egress

---

## Accessing the Service

After successful deployment, the service is accessible at:

```bash
# From any machine with network access to the GCP LoadBalancer
curl -kv --resolve 'test.team-a.appdev.aibang:443:88.88.243.168' \
  'https://test.team-a.appdev.aibang/'
```

Response:
```bash
HTTP/2 200
server: istio-envoy
content-type: application/octet-stream,text/plain
content-length: 31

env0-region-runtimepod response
```

The LoadBalancer external IP is: `88.88.243.168`

---

## Quick Reference: All Critical Commands

```bash
# Connect to bastion
gcloud compute ssh dev-lon-bastion-public \
    --zone=europe-west2-a \
    --tunnel-through-iap

# Check ASM fleet status
gcloud container fleet mesh describe

# Check gateway pods
kubectl get pod -n istio-ingressgateway-int

# Check gateway listeners
GW_POD=$(kubectl get pod -n istio-ingressgateway-int \
  -l app=istio-ingressgateway-int \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec $GW_POD -n istio-ingressgateway-int -c istio-proxy -- \
  curl -s localhost:15000/listeners

 kubectl exec -n istio-ingressgateway-int deploy/istio-ingressgateway-int -c istio-proxy -- curl -s http://localhost:15000/listeners
6e94fdaf-6d94-4dc8-ab39-6014f6eaadcc::0.0.0.0:15090
d5e4fa42-668f-4428-b991-f49f4deea186::0.0.0.0:15021
0.0.0.0_8443::0.0.0.0:8443


kubectl logs -l app=istio-ingressgateway-int -n istio-ingressgateway-int -c istio-proxy | grep -iE "ssl|tls|error" | tail -n 20
kubectl logs -l app=istio-ingressgateway-int -n istio-ingressgateway-int -c istio-proxy | grep -iE "ssl|tls|error"
2026-05-16T08:59:21.809438Z     warning envoy config external/envoy/source/extensions/config_subscription/grpc/grpc_subscription_impl.cc:130    gRPC config: initial fetch timed out for type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.Secret  thread=15


# Check gateway cert mount
kubectl exec $GW_POD -n istio-ingressgateway-int -c istio-proxy -- \
  ls -la /etc/istio/gateway-cert/

# Test HTTPS
curl -kv --resolve 'test.team-a.appdev.aibang:443:88.88.243.168' \
  'https://test.team-a.appdev.aibang/'

```json
{
  "textPayload": "100.64.2.17 - - [16/May/2026:09:19:06 +0000] \"GET / HTTP/1.1\" 200 31 \"-\" \"curl/8.7.1\" \"192.168.64.30\"",
  "insertId": "8xx2feh526aavfpy",
  "resource": {
    "type": "k8s_container",
    "labels": {
      "location": "europe-west2",
      "cluster_name": "dev-lon-cluster-xxxxxx",
      "container_name": "nginx",
      "namespace_name": "teama-nosidecare-rt-ns-int",
      "pod_name": "env0-region-runtimepod-78d74975d7-txhsc",
      "project_id": "aibang-12345678-ajbx-dev"
    }
  },
  "timestamp": "2026-05-16T09:19:06.315692671Z",
  "severity": "INFO",
  "labels": {
    "k8s-pod/app": "env0-region-runtimepod",
    "k8s-pod/topology_kubernetes_io/zone": "europe-west2-b",
    "k8s-pod/topology_kubernetes_io/region": "europe-west2",
    "logging.gke.io/top_level_controller_type": "Deployment",
    "compute.googleapis.com/resource_name": "gke-dev-lon-cluster-xxxx-default-pool-1a16d7c8-fg57",
    "logging.gke.io/top_level_controller_name": "env0-region-runtimepod",
    "k8s-pod/pod-template-hash": "78d74975d7"
  },
  "logName": "projects/aibang-12345678-ajbx-dev/logs/stdout",
  "receiveTimestamp": "2026-05-16T09:19:10.766368223Z"
}
```

# Check all Istio resources
kubectl get gateways.networking.istio.io -A
kubectl get virtualservices.networking.istio.io -A
kubectl get destinationrules.networking.istio.io -A

# Check pod logs
kubectl logs $GW_POD -n istio-ingressgateway-int -c istio-proxy --tail=30

# Restart gateway deployment
kubectl rollout restart deployment istio-ingressgateway-int -n istio-ingressgateway-int
kubectl rollout status deployment istio-ingressgateway-int -n istio-ingressgateway-int --timeout=120s

# Apply updated YAML
kubectl apply -f /tmp/asm-dp/

# Check service external IP
kubectl get svc istio-ingressgateway-int -n istio-ingressgateway-int

# verify pod logs 
kubectl logs -l app=env0-region-runtimepod -n teama-nosidecare-rt-ns-int  --tail=100
kubectl logs -l app=env0-region-runtimepod -n teama-nosidecare-rt-ns-int --tail=20 -f 


100.64.2.17 - - [16/May/2026:09:19:06 +0000] "GET / HTTP/1.1" 200 31 "-" "curl/8.7.1" "192.168.64.30"
```

---

## Appendix: IAM Permissions Check

If encountering control plane provisioning issues, verify the ASM service agent has the correct role:

```bash
gcloud projects get-iam-policy aibang-12345678-ajbx-dev \
  --flatten="bindings[].members" \
  --filter="bindings.role:anthosservicemesh.serviceAgent"
```

Expected member:
```bash
serviceAccount:service-487126826743@gcp-sa-servicemesh.iam.gserviceaccount.com
```

If missing, add it:
```bash
gcloud projects add-iam-policy-binding aibang-12345678-ajbx-dev \
    --member="serviceAccount:service-487126826743@gcp-sa-servicemesh.iam.gserviceaccount.com" \
    --role="roles/anthosservicemesh.serviceAgent"
```