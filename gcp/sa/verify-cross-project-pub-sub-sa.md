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

---

## Full Script

```bash
#!/bin/bash

# ==============================================================================
# Script Name: verify-cross-project-pub-sub-sa.sh
# Description: Verifies what permissions a GCP Service Account (obtained via a
#              GKE Deployment's KSA Workload Identity binding) has on a
#              Pub/Sub topic/subscription in a cross-project.
#
# Usage:       ./verify-cross-project-pub-sub-sa.sh <deployment-name> <namespace>
#
# Examples:
#   ./verify-cross-project-pub-sub-sa.sh my-deployment default
#   ./verify-cross-project-pub-sub-sa.sh api-server production
#
# Workflow:
#   1. Resolve KSA from the given Deployment in the current GKE project.
#   2. Extract the bound GCP SA from the KSA annotation.
#   3. Collect all IAM roles granted to that GCP SA (home project + current project).
#   4. Check Pub/Sub permissions in the cross-project interactively.
# ==============================================================================

set -euo pipefail

# --- Color Definitions ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Function: Usage ---
show_usage() {
    echo -e "${BLUE}Usage:${NC} $0 <deployment-name> <namespace>"
    echo -e "${BLUE}Example:${NC} $0 my-deployment default"
    echo -e "${BLUE}Example:${NC} $0 api-server production"
    exit 1
}

# --- Parse Arguments ---
if [[ $# -ne 2 ]]; then
    show_usage
fi

DEPLOYMENT_NAME="$1"
NAMESPACE="$2"

# --- Resolve Project Context ---
GKE_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$GKE_PROJECT" ]]; then
    echo -e "${RED}Error: No gcloud project set. Run 'gcloud config set project <project-id>'.${NC}"
    exit 1
fi

echo -e "${BLUE}==============================================================${NC}"
echo -e "${BLUE}   Cross-Project Pub/Sub SA Permission Verification Tool     ${NC}"
echo -e "${BLUE}==============================================================${NC}"
echo -e "${GREEN}GKE Project:${NC}   $GKE_PROJECT"
echo -e "${GREEN}Deployment:${NC}    $DEPLOYMENT_NAME"
echo -e "${GREEN}Namespace:${NC}     $NAMESPACE"
echo ""

# --- 1. Get KSA from Deployment ---
echo -e "${YELLOW}[1/6] Resolving KSA from Deployment '$DEPLOYMENT_NAME' in namespace '$NAMESPACE'...${NC}"
KSA=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null || true)

if [[ -z "$KSA" ]]; then
    KSA="default"
    echo -e "${YELLOW}  No explicit serviceAccountName found, assuming 'default'.${NC}"
else
    echo -e "${GREEN}  ✅ KSA found: ${KSA}${NC}"
fi

# --- 2. Get bound GCP SA from KSA annotation ---
echo -e "\n${YELLOW}[2/6] Fetching GCP SA bound to KSA '${KSA}' via Workload Identity annotation...${NC}"
GCP_SA=$(kubectl get serviceaccount "${KSA}" -n "${NAMESPACE}" \
    -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null || true)

if [[ -z "$GCP_SA" ]]; then
    echo -e "${RED}❌ No GCP SA found bound to KSA '${KSA}'.${NC}"
    echo -e "${YELLOW}  Ensure Workload Identity is configured: iam.gke.io/gcp-service-account annotation required.${NC}"
    exit 1
fi

SA_HOME_PROJECT=$(echo "$GCP_SA" | cut -d'@' -f2 | cut -d'.' -f1)
SA_NAME=$(echo "$GCP_SA" | cut -d'@' -f1)

echo -e "${GREEN}  ✅ Bound GCP SA: ${GCP_SA}${NC}"
echo -e "${GREEN}  SA Home Project: ${SA_HOME_PROJECT}${NC}"
echo -e "${GREEN}  SA Name: ${SA_NAME}${NC}"

if [[ "$SA_HOME_PROJECT" == "$GKE_PROJECT" ]]; then
    echo -e "${YELLOW}  ⚠️  SA is in the SAME project as the GKE cluster (not cross-project IAM).${NC}"
fi

# --- 3. Interactive: Cross-project and Pub/Sub resource ---
echo -e "\n${YELLOW}[3/6] Gathering cross-project Pub/Sub target...${NC}"

read -rp "  Enter cross-project ID (Project B, where Pub/Sub lives): " CROSS_PROJECT
while [[ -z "$CROSS_PROJECT" ]]; do
    echo -e "${RED}  Cross-project ID cannot be empty.${NC}"
    read -rp "  Enter cross-project ID: " CROSS_PROJECT
done

read -rp "  Enter Pub/Sub resource type (topic OR subscription): " PUBSUB_KIND
while [[ "$PUBSUB_KIND" != "topic" && "$PUBSUB_KIND" != "subscription" ]]; do
    echo -e "${RED}  Must be 'topic' or 'subscription'.${NC}"
    read -rp "  Enter Pub/Sub resource type (topic OR subscription): " PUBSUB_KIND
done

read -rp "  Enter Pub/Sub resource name: " PUBSUB_NAME
while [[ -z "$PUBSUB_NAME" ]]; do
    echo -e "${RED}  Pub/Sub resource name cannot be empty.${NC}"
    read -rp "  Enter Pub/Sub resource name: " PUBSUB_NAME
done

echo ""
echo -e "${CYAN}  Cross-project: ${CROSS_PROJECT}${NC}"
echo -e "${CYAN}  Pub/Sub kind:   ${PUBSUB_KIND}${NC}"
echo -e "${CYAN}  Pub/Sub name:   ${PUBSUB_NAME}${NC}"

# --- 4. Check IAM roles granted to this SA in its home project ---
echo -e "\n${YELLOW}[4/6] Checking project-level IAM roles for '${GCP_SA}' in its home project '${SA_HOME_PROJECT}'...${NC}"

ROLES_HOME=$(gcloud projects get-iam-policy "${SA_HOME_PROJECT}" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${GCP_SA}" \
    --format="table(bindings.role)" 2>/dev/null | tail -n +2 || true)

if [[ -z "$ROLES_HOME" ]]; then
    echo -e "${YELLOW}  ⚠️  No project-level roles found for this SA in '${SA_HOME_PROJECT}'.${NC}"
else
    ROLE_COUNT=$(echo "$ROLES_HOME" | grep -c . || echo 0)
    echo -e "${GREEN}  ✅ ${ROLE_COUNT} role(s) granted in home project:${NC}"
    echo "$ROLES_HOME" | sed 's/^/     - /'
fi

# --- 5. Check IAM roles granted to this SA in the current (GKE) project ---
if [[ "$SA_HOME_PROJECT" != "$GKE_PROJECT" ]]; then
    echo -e "\n${YELLOW}[5/6] Checking project-level IAM roles for '${GCP_SA}' in GKE project '${GKE_PROJECT}'...${NC}"

    ROLES_GKE=$(gcloud projects get-iam-policy "${GKE_PROJECT}" \
        --flatten="bindings[].members" \
        --filter="bindings.members:serviceAccount:${GCP_SA}" \
        --format="table(bindings.role)" 2>/dev/null | tail -n +2 || true)

    if [[ -z "$ROLES_GKE" ]]; then
        echo -e "${YELLOW}  ⚠️  No project-level roles found for this SA in '${GKE_PROJECT}'.${NC}"
    else
        ROLE_COUNT=$(echo "$ROLES_GKE" | grep -c . || echo 0)
        echo -e "${GREEN}  ✅ ${ROLE_COUNT} role(s) granted in GKE project:${NC}"
        echo "$ROLES_GKE" | sed 's/^/     - /'
    fi
else
    echo -e "\n${YELLOW}[5/6] Skipping cross-project check — SA home === GKE project (same project).${NC}"
fi

# --- 6. Expand roles and identify Pub/Sub permissions ---
echo -e "\n${YELLOW}[6/6] Expanding roles to identify Pub/Sub permissions...${NC}"

# Collect all roles from both projects
ALL_ROLES=$(echo -e "${ROLES_HOME:-}\n${ROLES_GKE:-}" | grep -v '^$' | sort -u)

if [[ -z "$ALL_ROLES" ]]; then
    echo -e "${YELLOW}  ⚠️  No roles found — cannot expand permissions. Is the SA properly granted access?${NC}"
else
    PUBSUB_PERMS_FOUND=false

    while IFS= read -r role; do
        [[ -z "$role" ]] && continue
        PERMS=$(gcloud iam roles describe "${role}" \
            --project="${SA_HOME_PROJECT}" \
            --format="value(includedPermissions)" 2>/dev/null | tr ';' '\n' || true)

        if [[ -z "$PERMS" ]]; then
            continue
        fi

        MATCHING=$(echo "$PERMS" | grep '^pubsub\.' || true)
        if [[ -n "$MATCHING" ]]; then
            PUBSUB_PERMS_FOUND=true
            echo -e "\n  ${CYAN}📦 Role: ${role}${NC}"
            echo "$MATCHING" | sed 's/^/     - /'
        fi
    done <<< "$ALL_ROLES"

    if [[ "$PUBSUB_PERMS_FOUND" == "false" ]]; then
        echo -e "${YELLOW}  ⚠️  No Pub/Sub permissions found in any granted roles.${NC}"
        echo -e "${YELLOW}     The SA may not have access to the target Pub/Sub resource.${NC}"
    fi
fi

# --- 7. Check Pub/Sub resource IAM (who can access it) ---
echo -e "\n${YELLOW}[7/6] Checking IAM policy on Pub/Sub resource '${PUBSUB_NAME}' in project '${CROSS_PROJECT}'...${NC}"

if [[ "$PUBSUB_KIND" == "topic" ]]; then
    PUBSUB_CMD="gcloud pubsub topics get-iam-policy ${PUBSUB_NAME} --project=${CROSS_PROJECT}"
    PUBSUB_DESCRIBE_CMD="gcloud pubsub topics describe ${PUBSUB_NAME} --project=${CROSS_PROJECT}"
else
    PUBSUB_CMD="gcloud pubsub subscriptions get-iam-policy ${PUBSUB_NAME} --project=${CROSS_PROJECT}"
    PUBSUB_DESCRIBE_CMD="gcloud pubsub subscriptions describe ${PUBSUB_NAME} --project=${CROSS_PROJECT}"
fi

# Check if resource exists
if $PUBSUB_DESCRIBE_CMD >/dev/null 2>&1; then
    echo -e "${GREEN}  ✅ Pub/Sub ${PUBSUB_KIND} '${PUBSUB_NAME}' exists in project '${CROSS_PROJECT}'.${NC}"
else
    echo -e "${RED}  ❌ Pub/Sub ${PUBSUB_KIND} '${PUBSUB_NAME}' not found in project '${CROSS_PROJECT}'.${NC}"
    echo -e "${YELLOW}     Please verify the resource name and project ID.${NC}"
fi

# Get IAM policy on the resource
IAM_POLICY=$($PUBSUB_CMD --format='json' 2>/dev/null || echo "{}")

SA_BINDINGS=$(echo "$IAM_POLICY" | \
    jq -r ".bindings[] | select(.members[] | contains(\"serviceAccount:${GCP_SA}\")) | .role" 2>/dev/null || true)

if [[ -n "$SA_BINDINGS" ]]; then
    echo -e "${GREEN}  ✅ Direct IAM bindings for '${GCP_SA}' on this Pub/Sub ${PUBSUB_KIND}:${NC}"
    echo "$SA_BINDINGS" | sed 's/^/     - /'
else
    echo -e "${YELLOW}  ⚠️  No direct IAM bindings found for '${GCP_SA}' on this Pub/Sub ${PUBSUB_KIND}.${NC}"
    echo -e "${YELLOW}     Access may be granted via a Google Group or workloadIdentityUser binding.${NC}"
fi

# Full bindings for reference
echo -e "\n${CYAN}  Full IAM bindings on this Pub/Sub ${PUBSUB_KIND}:${NC}"
echo "$IAM_POLICY" | jq -r '.bindings[] | "\(.role): \(.members[])"' 2>/dev/null | sed 's/^/     /' || \
    echo "     (unable to parse IAM policy)"

# --- Summary ---
echo -e "\n${BLUE}==============================================================${NC}"
echo -e "${BLUE}   Summary                                                       ${NC}"
echo -e "${BLUE}==============================================================${NC}"
echo -e "${GREEN}Deployment:${NC}    $DEPLOYMENT_NAME"
echo -e "${GREEN}Namespace:${NC}     $NAMESPACE"
echo -e "${GREEN}KSA:${NC}          $KSA"
echo -e "${GREEN}GCP SA:${NC}       $GCP_SA"
echo -e "${GREEN}SA Home:${NC}      $SA_HOME_PROJECT"
echo -e "${GREEN}GKE Project:${NC}  $GKE_PROJECT"
echo -e "${CYAN}Cross Project:${NC} $CROSS_PROJECT"
echo -e "${CYAN}Pub/Sub Kind:${NC} $PUBSUB_KIND"
echo -e "${CYAN}Pub/Sub Name:${NC} $PUBSUB_NAME"
echo ""
echo -e "${BLUE}==============================================================${NC}"
echo -e "${BLUE}   Verification Complete!                                         ${NC}"
echo -e "${BLUE}==============================================================${NC}"
```
