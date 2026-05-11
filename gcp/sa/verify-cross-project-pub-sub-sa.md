# verify-cross-project-pub-sub-sa.sh

> **Script:** `verify-cross-project-pub-sub-sa.sh`
> **Directory:** `knowledge/GCP/sa/`

## Overview

This script verifies what permissions a GCP Service Account (derived from a KSA binding in the deploy project) has on a Pub/Sub topic or subscription in a **cross-project** context.

## Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  1. Get KSA Info (Interactive)                              │
│     - KSA name                                              │
│     - Namespace (default: default)                          │
│     - GKE cluster name                                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  2. Resolve GCP SA from KSA                                 │
│     - Reads annotation: iam.gke.io/gcp-service-account      │
│     - Or manually input if annotation not found             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Query Cross-Project Pub/Sub Permissions (Interactive)   │
│     - Cross-project ID                                      │
│     - Resource type (topic / subscription)                  │
│     - Resource name                                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Verification Steps                                      │
│     [1/5] Verify GCP SA exists in its home project          │
│     [2/5] Check project-level IAM in cross-project          │
│     [3/5] Check Pub/Sub resource-level IAM bindings         │
│     [4/5] Check conditional IAM bindings                    │
│     [5/5] Test actual Pub/Sub permissions (publish/pull/ack)│
└─────────────────────────────────────────────────────────────┘
```

## Usage

```bash
cd ~/git/knowledge/GCP/sa/
chmod +x verify-cross-project-pub-sub-sa.sh
./verify-cross-project-pub-sub-sa.sh
```

> **Note:** This script runs in **interactive mode** — all inputs are prompted.

## Interactive Inputs

| Step | Input | Default | Description |
|------|-------|---------|-------------|
| 1 | KSA name | — | Kubernetes Service Account name |
| 1 | KSA namespace | `default` | Namespace where KSA resides |
| 1 | GKE cluster name | — | Cluster where KSA exists (optional, leave empty to skip) |
| 2 | GCP SA email | auto-detected | GCP SA bound to KSA via Workload Identity |
| 3 | Cross-project ID | — | GCP project where Pub/Sub resides |
| 3 | Resource type | — | `1` = Topic, `2` = Subscription |
| 3 | Pub/Sub name | — | Name of the topic or subscription |

## Verification Checks

### Step [1/5] — SA Existence Check
Verifies the GCP SA exists in its home project using:
```bash
gcloud iam service-accounts describe "$GCP_SA_EMAIL" --project="$GCP_SA_PROJECT"
```

### Step [2/5] — Project-Level IAM
Lists all project-level IAM roles granted to the SA in the cross-project:
```bash
gcloud projects get-iam-policy "$CROSS_PROJECT" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${GCP_SA_EMAIL}" \
    --format="table(bindings.role)"
```

### Step [3/5] — Resource-Level IAM
Checks Pub/Sub topic or subscription IAM bindings:
```bash
# For topics:
gcloud pubsub topics get-iam-policy "$PUBSUB_NAME" --project="$CROSS_PROJECT"

# For subscriptions:
gcloud pubsub subscriptions get-iam-policy "$PUBSUB_NAME" --project="$CROSS_PROJECT"
```

### Step [4/5] — Conditional IAM
Detects any IAM conditions attached to the bindings (e.g., date-based expiration, resource name filters).

### Step [5/5] — Permission Testing
Tests actual Pub/Sub permissions:

| Permission | Command | Description |
|-----------|---------|-------------|
| `pubsub.topics.publish` | `gcloud pubsub topics test-iam-permissions` | Publish messages to topic |
| `pubsub.subscriptions.pull` | `gcloud pubsub subscriptions test-iam-permissions` | Pull messages from subscription |
| `pubsub.subscriptions.acknowledge` | `gcloud pubsub subscriptions test-iam-permissions` | Acknowledge processed messages |

## Prerequisites

1. **gcloud CLI** — authenticated and configured
2. **kubectl** — configured to access the target GKE cluster
3. **IAM Permissions:**
   - `iam.serviceAccounts.getIamPolicy` — to read SA bindings
   - `pubusb.topics.getIamPolicy` / `pubsub.subscriptions.getIamPolicy` — to read Pub/Sub IAM
   - `pubsub.topics.testIamPermissions` / `pubsub.subscriptions.testIamPermissions` — to test permissions

## Common Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Cannot auto-detect GCP SA | Workload Identity not configured | Manually enter the GCP SA email |
| Permission denied on Pub/Sub IAM | Missing `pubsub.*.getIamPolicy` permission | Ask cross-project admin to grant permission |
| No roles found | SA not granted access in cross-project | Verify IAM bindings in cross-project |
| KSA annotation is empty | Annotations not set on KSA | Check Workload Identity binding configuration |

## Related Scripts

- `Verify-another-proj-sa.sh` — verifies cross-project SA roles (general purpose, no KSA)
- `verify-gce-sa.sh` — verifies GCE instance service account permissions
