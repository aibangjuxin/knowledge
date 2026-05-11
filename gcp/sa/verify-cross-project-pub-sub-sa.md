# verify-cross-project-pub-sub-sa.sh

## Overview

**Script:** `verify-cross-project-pub-sub-sa.sh`
**Purpose:** Verifies what permissions a GCP Service Account — resolved from a GKE Deployment's Kubernetes Service Account (KSA) via Workload Identity — has on a Pub/Sub topic or subscription in a cross-project.

**Location:** `knowledge/GCP/sa/`

---

## When to Use

- You have a GKE Deployment using Workload Identity to bind a KSA to a GCP SA from another project.
- You want to audit what Pub/Sub permissions that SA has in a target cross-project.
- You need to troubleshoot "permission denied" errors when a workload tries to publish/subscribe to a Pub/Sub in another project.

---

## Usage

```bash
./verify-cross-project-pub-sub-sa.sh <deployment-name> <namespace>
```

### Examples

```bash
# Basic usage
./verify-cross-project-pub-sub-sa.sh my-deployment default

# Production namespace
./verify-cross-project-pub-sub-sa.sh api-server production
```

---

## Workflow

The script executes these steps in order:

| Step | Description |
|------|-------------|
| **1** | Resolve the KSA from the Deployment's `serviceAccountName` field |
| **2** | Extract the bound GCP SA from the KSA annotation `iam.gke.io/gcp-service-account` |
| **3** | Prompt interactively for the cross-project ID and Pub/Sub resource info |
| **4** | Check project-level IAM roles granted to the SA in its **home** project |
| **5** | Check project-level IAM roles granted to the SA in the **GKE** project (if different) |
| **6** | Expand all roles and filter for `pubsub.*` permissions |
| **7** | Query IAM policy directly on the target Pub/Sub topic/subscription in the cross-project |

---

## Interactive Inputs

The script will prompt for:

| Prompt | Description | Validation |
|--------|-------------|------------|
| Cross-project ID | Project ID where the Pub/Sub resource lives | Cannot be empty |
| Pub/Sub resource type | `topic` or `subscription` | Must be exact |
| Pub/Sub resource name | Name of the topic or subscription | Cannot be empty |

---

## Key Outputs

- **KSA → GCP SA resolution** — confirms which GCP SA the workload is using
- **IAM roles** granted to the SA in both its home project and the GKE project
- **pubsub.\* permissions** extracted and highlighted from all granted roles
- **Direct Pub/Sub IAM bindings** — shows if the SA has any direct `roles/pubsub.publisher`, `roles/pubsub.subscriber`, etc. on the target resource
- **Full IAM policy** of the target Pub/Sub resource for reference

---

## Example Output

```
==============================================================
   Cross-Project Pub/Sub SA Permission Verification Tool
==============================================================
GKE Project:   my-gke-project
Deployment:    api-server
Namespace:     production

[1/6] Resolving KSA from Deployment 'api-server' ...
  ✅ KSA found: api-server-ksa

[2/6] Fetching GCP SA bound to KSA ...
  ✅ Bound GCP SA: my-sa@sa-project.iam.gserviceaccount.com
  SA Home Project: sa-project

  Enter cross-project ID (Project B, where Pub/Sub lives): data-project
  Enter Pub/Sub resource type (topic OR subscription): topic
  Enter Pub/Sub resource name: my-topic

[4/6] Checking project-level IAM roles in home project 'sa-project' ...
  ✅ 2 role(s) granted:
     - roles/pubsub.publisher

[6/6] Expanding roles to identify Pub/Sub permissions ...
  📦 Role: roles/pubsub.publisher
     - pubsub.topics.publish
     - pubsub.topics.update

[7/6] Checking IAM policy on Pub/Sub topic 'my-topic' in project 'data-project' ...
  ✅ Pub/Sub topic 'my-topic' exists.
  ✅ Direct IAM bindings for SA on this topic:
     - roles/pubsub.publisher
```

---

## Common Issues

### "No GCP SA found bound to KSA"

The KSA lacks the `iam.gke.io/gcp-service-account` annotation. Ensure Workload Identity is properly configured:

```bash
kubectl annotate serviceaccount <ksa-name> \
  -n <namespace> \
  iam.gke.io/gcp-service-account=<gcp-sa-email>
```

### "No Pub/Sub permissions found"

The SA may not have any Pub/Sub roles granted. Check:

```bash
# In the SA's home project
gcloud projects get-iam-policy <sa-home-project> \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:<gcp-sa-email>"
```

### "Pub/Sub resource not found"

Verify the resource exists in the target project:

```bash
gcloud pubsub topics list --project=<cross-project>
gcloud pubsub subscriptions list --project=<cross-project>
```

---

## Relationship to Other Scripts

| Script | Purpose |
|--------|---------|
| `verify-another-proj-sa.sh` | Checks what roles a foreign SA has in **your** current project |
| `verify-gke-ksa-iam-authentication.sh` | Resolves KSA → GCP SA and checks Workload Identity config |
| `verify-cross-project-pub-sub-sa.sh` | **This script** — resolves KSA → GCP SA, then audits Pub/Sub permissions in a cross-project |

---

## Prerequisites

- `gcloud` CLI authenticated and configured
- `kubectl` configured with access to the target GKE cluster
- Sufficient IAM permissions to read IAM policies in both the SA home project and the cross-project
