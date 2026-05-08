# Cross-Project Pub/Sub + GKE Workload Identity Debug Guide

---

## Solution Summary (Root Cause)

**The actual issue in this case:**

A single Deployment connected to **multiple Pub/Sub subscriptions** across projects, but only **one subscription** had the GSA (`gke-rt-sa@souce-project.iam.gserviceaccount.com`) authorized. The other subscriptions returned 403 because they had no IAM binding for the GSA.

**Fix:** Add `roles/pubsub.subscriber` to **all** subscriptions the Deployment connects to.

```bash
# Example: binding for multiple subscriptions in target project
gcloud pubsub subscriptions add-iam-policy-binding subscription-a \
  --project=targetproject \
  --member="serviceAccount:gke-rt-sa@souce-project.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"

gcloud pubsub subscriptions add-iam-policy-binding subscription-b \
  --project=targetproject \
  --member="serviceAccount:gke-rt-sa@souce-project.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"

# ... repeat for every subscription the deployment accesses
```

**This is the #1 most overlooked cause** in multi-subscription deployments. The deployment itself starts fine — the 403 only appears when the code actually tries to access each subscription.

---

## Problem Summary

```
Pod in Source Project GKE → Access Pub/Sub Subscription in Target Project
Error: 403 IAM_PERMISSION_DENIED on "pubsub.subscriptions.get"
```

**Setup:**
- Source Project GKE cluster with Deployment using KSA annotated to GSA `gke-rt-sa@souce-project.iam.gserviceaccount.com`
- Target Project has subscription(s) — only some may have GSA bound
- Pod starts normally but API call fails with 403 on one or more subscriptions

---

## Validation: Check All Subscriptions at Once

Before debugging, find every subscription your deployment actually accesses, then check which ones are authorized.

### Step 1: Identify all subscriptions the Deployment references

```bash
# Look in your deployment/config for subscription names
kubectl get deployment YOUR_DEPLOYMENT -n YOUR_NAMESPACE -o yaml | grep -E "subscription|topic"

# Or search in your codebase / config files
grep -r "pubsub.googleapis.com.*projects.*subscriptions\|pubsub.googleapis.com.*projects.*topics" . \
  --include="*.yaml" --include="*.json" --include="*.env" | \
  grep -oE "projects/[^/]+/subscriptions/[^']+" | sort -u
```

### Step 2: Batch-check IAM for all subscriptions

Replace `SOURCE_GSA` and `TARGET_PROJECT`, then run:

```bash
SOURCE_GSA="serviceAccount:gke-rt-sa@souce-project.iam.gserviceaccount.com"
TARGET_PROJECT="targetproject"
SUBSCRIPTIONS=("sub-a" "sub-b" "sub-c")  # Add your subscription names here

echo "=== Batch IAM Check ==="
for SUB in "${SUBSCRIPTIONS[@]}"; do
  echo ""
  echo "Subscription: $SUB"
  POLICY=$(gcloud pubsub subscriptions get-iam-policy "$SUB" --project="$TARGET_PROJECT" 2>/dev/null)
  if echo "$POLICY" | grep -q "$SOURCE_GSA"; then
    echo "  ✓ GSA found"
  else
    echo "  ✗ GSA MISSING — no binding for this subscription"
    echo "  Missing binding:"
    echo "    gcloud pubsub subscriptions add-iam-policy-binding $SUB \\"
    echo "      --project=$TARGET_PROJECT \\"
    echo "      --member=\"$SOURCE_GSA\" \\"
    echo "      --role=\"roles/pubsub.subscriber\""
  fi
done
```

Expected output when one is missing:
```
Subscription: topic-pub-sub
  ✗ GSA MISSING — no binding for this subscription
  Missing binding:
    gcloud pubsub subscriptions add-iam-policy-binding topic-pub-sub \
      --project=targetproject \
      --member="serviceAccount:gke-rt-sa@souce-project.iam.gserviceaccount.com" \
      --role="roles/pubsub.subscriber"
```

### Step 3: Batch-add missing bindings

```bash
SOURCE_GSA="serviceAccount:gke-rt-sa@souce-project.iam.gserviceaccount.com"
TARGET_PROJECT="targetproject"
SUBSCRIPTIONS=("sub-a" "sub-b" "sub-c")

for SUB in "${SUBSCRIPTIONS[@]}"; do
  gcloud pubsub subscriptions add-iam-policy-binding "$SUB" \
    --project="$TARGET_PROJECT" \
    --member="$SOURCE_GSA" \
    --role="roles/pubsub.subscriber" 2>&1 | tee /dev/stderr | grep -v "^$"
done
```

---

## Debug Path (Full)

If batch-check passes and you still get 403, follow through the phases below.

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

Inside the pod:

```bash
# What SA is the token from?
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"
```

- If WI is working → shows `gke-rt-sa@souce-project.iam.gserviceaccount.com`
- If WI is NOT working → shows `PROJECT_NUMBER-compute@developer.gserviceaccount.com` (node's default SA)

#### 1.4 Quick test: verify GSA can access subscription

From a GCE VM or Cloud Shell with the GSA attached:

```bash
gcloud compute instances create test-wi-vm \
  --zone=europe-west2-a \
  --service-account=gke-rt-sa@souce-project.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/pubsub

gcloud compute ssh test-wi-vm --zone=europe-west2-a

# Inside VM:
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://pubsub.googleapis.com/v1/projects/targetproject/subscriptions/topic-pub-sub"
```

If this works, GSA permissions are correct. The problem is in the pod's WI chain.

---

### Phase 2: Verify Pub/Sub Subscription IAM

#### 2.1 Get the actual IAM policy on a subscription

```bash
gcloud pubsub subscriptions get-iam-policy topic-pub-sub --project=targetproject
```

Check for GSA with `roles/pubsub.subscriber`:

```json
{
  "bindings": [
    {
      "role": "roles/pubsub.subscriber",
      "members": [
        "serviceAccount:gke-rt-sa@souce-project.iam.gserviceaccount.com"
      ]
    }
  ]
}
```

**Important**: Pub/Sub subscription IAM is separate from project IAM. Project-level bindings do **not** automatically apply to subscriptions.

#### 2.2 Binding at subscription level

```bash
gcloud pubsub subscriptions add-iam-policy-binding topic-pub-sub \
  --project=targetproject \
  --member="serviceAccount:gke-rt-sa@souce-project.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"
```

#### 2.3 Check API is enabled in both projects

```bash
# Source Project
gcloud services list --project=souce-project | grep pubsub

# Target Project
gcloud services list --project=targetproject | grep pubsub
```

---

### Phase 3: Common Pitfalls

#### Pitfall 1: WI annotation on wrong resource

The annotation must be on the **KSA**, not the Deployment.

```yaml
# WRONG — annotation on Deployment spec.template.metadata
spec:
  template:
    metadata:
      annotations:
        iam.gke.io/gcp-service-account: gke-rt-sa@souce-project.iam.gserviceaccount.com

# CORRECT — annotation on KSA itself
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
      serviceAccountName: your-ksa   # references the annotated KSA
```

#### Pitfall 2: Node pool WI not enabled

Even with correct KSA annotation, if the node pool wasn't created with `--workload-pool`, pods still use the node's default SA token.

**Fix**: Recreate node pool with WI enabled:
```bash
gcloud container node-pools create NEW_POOL \
  --cluster=YOUR_CLUSTER \
  --region=europe-west2 \
  --workload-pool=souce-project.svc.id.goog
```

#### Pitfall 3: Multi-subscription — only some authorized

The deployment connects to multiple subscriptions, but only one has the GSA binding. This is the **most common** cause in complex deployments. Use the batch-check script above.

#### Pitfall 4: Pub/Sub API not enabled in Source Project

```bash
gcloud services enable pubsub.googleapis.com --project=souce-project
```

---

### Phase 4: Full Debug Script (run inside the failing pod)

```bash
#!/bin/bash
set -e

METADATA_URL="http://metadata.google.internal/computeMetadata/v1/instance/service-accounts"

echo "=== KSA Info ==="
echo "KSA: $(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)/$(cat /var/run/secrets/kubernetes.io/serviceaccount/name)"

echo ""
echo "=== Token SA (should be GSA, not node's default SA) ==="
curl -s -H "Metadata-Flavor: Google" "$METADATA_URL/default/email"

echo ""
echo "=== JWT Header & Claims ==="
RAW_TOKEN=$(curl -s -H "Metadata-Flavor: Google" "$METADATA_URL/default/token" | \
  python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
echo "$RAW_TOKEN" | cut -d'.' -f1,2 | base64 -d 2>/dev/null | python3 -m json.tool || echo "decode failed"

echo ""
echo "=== Pub/Sub Access Tests (replace SUBSCRIPTIONS list) ==="
# Add the subscriptions your app actually uses
SUBSCRIPTIONS=(
  "projects/targetproject/subscriptions/sub-a"
  "projects/targetproject/subscriptions/sub-b"
)
TOKEN=$(curl -s -H "Metadata-Flavor: Google" "$METADATA_URL/default/token" | \
  python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

for SUB in "${SUBSCRIPTIONS[@]}"; do
  RESULT=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "https://pubsub.googleapis.com/v1/$SUB" 2>&1)
  if echo "$RESULT" | grep -q '"error"'; then
    echo "✗ $SUB — FAILED"
    echo "  $(echo "$RESULT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["error"]["message"])')"
  else
    echo "✓ $SUB — OK"
  fi
done
```

---

## Solution Checklist

- [ ] Batch-check: all subscriptions the Deployment references have GSA IAM binding
- [ ] KSA has correct annotation: `iam.gke.io/gcp-service-account: gke-rt-sa@souce-project.iam.gserviceaccount.com`
- [ ] Node pool has WI enabled: `workloadMetadataConfig.mode = GKE_METADATA`
- [ ] Pod is using the annotated KSA (not default): `spec.serviceAccountName: your-ksa`
- [ ] Pod actually gets GSA token (not node's default SA token)
- [ ] Pub/Sub API enabled in both Source and Target projects

---

## Quick Fix Commands

### Add binding to all subscriptions at once

```bash
GSA="serviceAccount:gke-rt-sa@souce-project.iam.gserviceaccount.com"
PROJECT="targetproject"

# List all subscriptions — adjust filter as needed
gcloud pubsub subscriptions list --project="$PROJECT" --format="value(name)" | \
  while read SUB; do
    echo "Adding binding to: $SUB"
    gcloud pubsub subscriptions add-iam-policy-binding "$SUB" \
      --project="$PROJECT" \
      --member="$GSA" \
      --role="roles/pubsub.subscriber"
  done
```

### Enable WI on node pool (if needed)

```bash
# Recreate node pool (preferred for prod)
gcloud container node-pools create new-pool-with-wi \
  --cluster=dev-lon-cluster-xxxxxx \
  --region=europe-west2 \
  --workload-pool=souce-project.svc.id.goog \
  --image-type=cos_containerd
```

---

## Further Reference

- [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Pub/Sub IAM](https://cloud.google.com/pubsub/docs/access-control)
- [Troubleshooting WI](https://cloud.google.com/kubernetes-engine/docs/troubleshooting/workload-identity)
