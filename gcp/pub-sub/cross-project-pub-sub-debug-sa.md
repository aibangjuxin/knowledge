# Cross-Project Pub/Sub + GKE Workload Identity Debug Guide

## Problem Summary

```
Pod in Source Project GKE → Access Pub/Sub Subscription in Target Project
Error: 403 IAM_PERMISSION_DENIED on "pubsub.subscriptions.get"
```

**Setup:**
- Source Project GKE cluster with Deployment using KSA annotated to GSA `gke-rt-sa@souce-project.iam.gserviceaccount.com`
- Target Project has subscription `topic-pub-sub` with GSA bound to `roles/pubsub.subscriber`
- Pod starts normally but API call fails with 403

---

## Debug Path

### Phase 1: Verify Workload Identity is Actually Working

Workload Identity requires **two** things:
1. KSA annotation (`iam.gke.io/gcp-service-account`)
2. Node pool WI enabled (`--workload-pool=SOURCE_PROJECT.svc.id.goog`)

#### 1.1 Check KSA annotation in your Deployment

```bash
kubectl get deployment YOUR_DEPLOYMENT -n YOUR_NAMESPACE -o yaml | grep -A2 "iam.gke.io"
```

Expected output:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    iam.gke.io/gcp-service-account: gke-rt-sa@souce-project.iam.gserviceaccount.com
```

If the annotation is missing or on the wrong KSA, WI won't work.

#### 1.2 Check Node Pool WI is enabled

```bash
# In Source Project
gcloud container node-pools list --cluster=YOUR_CLUSTER --region=europe-west2

# Get node pool details
gcloud container node-pools describe YOUR_NODE_POOL \
  --cluster=YOUR_CLUSTER \
  --region=europe-west2 \
  --project=souce-project
```

Look for:
```yaml
workloadMetadataConfig:
  mode: GKE_METADATA (not GCE_METADATA or MODE_UNSPECIFIED)
```

**CRITICAL**: If you see `mode: GCE_METADATA` or if the field is absent, WI is NOT enabled. The node pool needs recreation with `--workload-pool=souce-project.svc.id.goog`.

#### 1.3 Verify what token your pod is actually getting

Inside the pod, compare:

```bash
# Token from metadata server (what your curl uses)
TOKEN1=$(curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email")
echo "Service Account: $TOKEN1"

# Get the actual access token
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('Token expires:', d.get('expires_in'), 'seconds')"
```

If WI is working → the token should be for `gke-rt-sa@souce-project.iam.gserviceaccount.com`
If WI is NOT working → the token will be for the **Node's default SA** (something like `PROJECT_NUMBER-compute@developer.gserviceaccount.com`)

**This is the #1 most likely cause.** If the node's default SA token is being used, it won't have permission on the target project.

#### 1.4 Quick test: verify GSA can access subscription

From a GCE VM in Source Project (or Cloud Shell), attach the GSA:

```bash
# Create a temporary test VM with the GSA attached
gcloud compute instances create test-wi-vm \
  --zone=europe-west2-a \
  --service-account=gke-rt-sa@souce-project.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/pubsub

# SSH and test
gcloud compute ssh test-wi-vm --zone=europe-west2-a

# Inside VM:
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://pubsub.googleapis.com/v1/projects/targetproject/subscriptions/topic-pub-sub"
```

If this works, GSA permissions are correct. The problem is in the pod's WI chain.

---

### Phase 2: Verify Pub/Sub Subscription IAM

#### 2.1 Get the actual IAM policy on the subscription

```bash
gcloud pubsub subscriptions get-iam-policy topic-pub-sub --project=targetproject
```

Check that the GSA appears with `roles/pubsub.subscriber`:

```json
{
  "bindings": [
    {
      "role": "roles/pubsub.subscriber",
      "members": [
        "serviceAccount:gke-rt-sa@souce-project.iam.gserviceaccount.com"
      ]
    }
  ],
  "etag": "..."
}
```

**Important**: If you only see bindings at the **project** level (not subscription level), that's not enough. Pub/Sub subscription IAM is separate from project IAM.

#### 2.2 Binding at subscription level (if not already)

```bash
gcloud pubsub subscriptions add-iam-policy-binding topic-pub-sub \
  --project=targetproject \
  --member="serviceAccount:gke-rt-sa@souce-project.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"
```

#### 2.3 Also check if Target Project needs the API enabled

```bash
gcloud services list --project=targetproject | grep pubsub
```

If `pubsub.googleapis.com` is not enabled:
```bash
gcloud services enable pubsub.googleapis.com --project=targetproject
```

---

### Phase 3: Common Pitfalls

#### Pitfall 1: WI annotation on wrong resource

The annotation must be on the **KSA**, not the Deployment. Kubernetes applies it from KSA → Pod.

```yaml
# WRONG - annotation on Deployment
spec:
  template:
    metadata:
      annotations:
        iam.gke.io/gcp-service-account: gke-rt-sa@souce-project.iam.gserviceaccount.com

# CORRECT - annotation on KSA (referenced by Deployment)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: your-ksa
  namespace: your-namespace
  annotations:
    iam.gke.io/gcp-service-account: gke-rt-sa@souce-project.iam.gserviceaccount.com
---
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      serviceAccountName: your-ksa   # <-- references the KSA
```

#### Pitfall 2: Node pool WI not enabled

Even with correct KSA annotation, if the node pool wasn't created with `--workload-pool`, pods still use the node's default SA token.

**Solution**: Recreate the node pool with WI enabled:
```bash
gcloud container node-pools create NEW_POOL \
  --cluster=YOUR_CLUSTER \
  --region=europe-west2 \
  --workload-pool=souce-project.svc.id.goog \
  # ... other flags same as existing pool
```

Then migrate workloads to the new pool.

#### Pitfall 3: Wrong token endpoint

The user used the legacy endpoint:
```
/computeMetadata/v1/instance/service-accounts/default/token
```

This still works but prefer the newer one:
```
/computeMetadata/v1/instance/service-accounts/default/identity?audience=pubsub.googleapis.com
```

For a proper OIDC token for Pub/Sub:
```bash
# Get OIDC token for Pub/Sub
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=pubsub.googleapis.com"
```

#### Pitfall 4: Pub/Sub API not enabled in Source Project

Even with WI working, the Source Project needs the Pub/Sub API enabled to make API calls:
```bash
gcloud services enable pubsub.googleapis.com --project=souce-project
```

---

### Phase 4: Full Debug Script

Run this inside the failing pod:

```bash
#!/bin/bash
set -e

echo "=== Workload Identity Debug ==="

# 1. Who is the KSA?
echo "KSA: $(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)/$(cat /var/run/secrets/kubernetes.io/serviceaccount/name)"

# 2. What token are we getting?
echo ""
echo "=== Token Info ==="
METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance/service-accounts"
EMAIL=$(curl -s -H "Metadata-Flavor: Google" "$METADATA_URL/default/email")
echo "Service Account Email: $EMAIL"

# 3. Test Pub/Sub access
echo ""
echo "=== Testing Pub/Sub Access ==="
TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  -H "Authorization: Bearer $(curl -s -H 'Metadata-Flavor: Google' '$METADATA_URL/default/token' | python3 -c 'import sys,json;print(json.load(sys.stdin)[\"access_token\"])')" \
  "https://pubsub.googleapis.com/v1/projects/targetproject/subscriptions/topic-pub-sub" 2>&1)

echo "$TOKEN"

# 4. Decode JWT to verify issuer
echo ""
echo "=== JWT Decoded (header.claims) ==="
RAW_TOKEN=$(curl -s -H "Metadata-Flavor: Google" "$METADATA_URL/default/token" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
echo "$RAW_TOKEN" | cut -d'.' -f1,2 | base64 -d 2>/dev/null | python3 -m json.tool || echo "Could not decode"
```

---

## Solution Checklist

After fixing, verify in order:

- [ ] KSA has correct annotation: `iam.gke.io/gcp-service-account: gke-rt-sa@souce-project.iam.gserviceaccount.com`
- [ ] Node pool has WI enabled: `workloadMetadataConfig.mode = GKE_METADATA`
- [ ] Pod is using the KSA (not default): `spec.serviceAccountName: your-ksa`
- [ ] GSA has `roles/pubsub.subscriber` on the **subscription** (not just project)
- [ ] Pub/Sub API enabled in both Source and Target projects
- [ ] Pod actually gets GSA token (not node's default SA token)

---

## Quick Fix Commands

### If WI not enabled on node pool:

```bash
# Option A: Recreate node pool (preferred for prod)
gcloud container node-pools create new-pool-with-wi \
  --cluster=dev-lon-cluster-xxxxxx \
  --region=europe-west2 \
  --workload-pool=souce-project.svc.id.goog \
  --image-type=cos_containerd \
  --num-nodes=1

# Option B: For testing only - enable on existing pool (may cause restarts)
gcloud container clusters update dev-lon-cluster-xxxxxx \
  --region=europe-west2 \
  --workload-pool=souce-project.svc.id.goog
```

### If GSA not bound to subscription:

```bash
gcloud pubsub subscriptions add-iam-policy-binding topic-pub-sub \
  --project=targetproject \
  --member="serviceAccount:gke-rt-sa@souce-project.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"
```

### Verify fix inside pod:

```bash
# Should show gke-rt-sa@souce-project.iam.gserviceaccount.com
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"

# Should return subscription details (not 403)
curl -s -H "Metadata-Flavor: Google" \
  -H "Authorization: Bearer $(curl -s -H 'Metadata-Flavor: Google' 'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token' | python3 -c 'import sys,json;print(json.load(sys.stdin)[\"access_token\"])'))" \
  "https://pubsub.googleapis.com/v1/projects/targetproject/subscriptions/topic-pub-sub"
```

---

## Your Case: Most Likely Cause

Based on your description (Pod works but Pub/Sub fails), the **most likely issue** is:

**Node pool doesn't have Workload Identity enabled.**

Even though the KSA annotation exists, if the node pool wasn't created with `--workload-pool`, pods still get tokens from the node's default service account, which doesn't have cross-project Pub/Sub permissions.

**Fix**: Recreate the node pool with WI enabled, then test again.

---

## Further Reference

- [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Pub/Sub IAM](https://cloud.google.com/pubsub/docs/access-control)
- [Troubleshooting WI](https://cloud.google.com/kubernetes-engine/docs/troubleshooting/workload-identity)
