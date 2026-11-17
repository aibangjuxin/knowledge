#!/bin/bash

# ==============================================================================
# Script Name: verify-cross-project-pub-sub-sa.sh
# Description: Queries a GCP Service Account (from KSA binding in deploy project)
#              and checks its permissions on a Pub/Sub topic/subscription in a
#              cross-project context.
#
# Usage:       ./verify-cross-project-pub-sub-sa.sh
#              (Interactive mode — will prompt for all required inputs)
#
# Examples:
#   - KSA:     deploy-app-ksa
#   - Namespace: default
#   - Cluster:  my-gke-cluster
#   - Target Cross Project: target-gcp-project
#   - Pub/Sub Resource: my-topic OR my-subscription
#
# Scenario:
#   You have a KSA (Kubernetes Service Account) bound to a GCP SA in your deploy
#   project. You want to verify what permissions that GCP SA has on a specific
#   Pub/Sub topic or subscription in a CROSS-PROJECT.
# ==============================================================================

set -euo pipefail

# --- Color Definitions ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Function: Print Header ---
print_header() {
    echo -e "${BLUE}==============================================================${NC}"
    echo -e "${BLUE}   Cross-Project Pub/Sub SA Permission Verification Tool      ${NC}"
    echo -e "${BLUE}==============================================================${NC}"
}

# --- Function: Prompt for input ---
prompt() {
    local prompt_text="$1"
    local var_name="$2"
    local default_value="${3:-}"
    local result

    if [[ -n "$default_value" ]]; then
        read -p "$(echo -e "${CYAN}${prompt_text} [${default_value}]: ${NC}")" result
        result="${result:-$default_value}"
    else
        read -p "$(echo -e "${CYAN}${prompt_text}: ${NC}")" result
    fi

    # shellcheck disable=SC2086
    printf -v $var_name '%s' "$result"
}

# --- Function: Validate non-empty ---
validate_not_empty() {
    local value="$1"
    local name="$2"
    if [[ -z "$value" ]]; then
        echo -e "${RED}Error: ${name} cannot be empty.${NC}"
        exit 1
    fi
}

# --- Function: Prompt yes/no ---
prompt_yes_no() {
    local prompt_text="$1"
    local result
    while true; do
        read -p "$(echo -e "${CYAN}${prompt_text} (y/n): ${NC}")" result
        case "$result" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

print_header

echo -e "${YELLOW}This script helps you verify GCP SA permissions on cross-project Pub/Sub.${NC}"
echo ""

# --- Step 1: Get local project from gcloud config ---
LOCAL_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$LOCAL_PROJECT" ]]; then
    echo -e "${RED}Error: No gcloud project set. Run 'gcloud config set project YOUR_PROJECT' first.${NC}"
    exit 1
fi
echo -e "${GREEN}Local Project (from gcloud):${NC} ${LOCAL_PROJECT}"
echo ""

# --- Step 2: KSA Info ---
echo -e "${YELLOW}--- Kubernetes Service Account (KSA) Info ---${NC}"

prompt "  Enter KSA name" KSA_NAME ""
validate_not_empty "$KSA_NAME" "KSA name"

prompt "  Enter KSA namespace" KSA_NAMESPACE "default"
validate_not_empty "$KSA_NAMESPACE" "KSA namespace"

prompt "  Enter GKE cluster name (leave empty to list clusters)" CLUSTER_NAME ""
CLUSTER_ARG=""
if [[ -n "$CLUSTER_NAME" ]]; then
    CLUSTER_ARG="--cluster=$CLUSTER_NAME"
fi

# --- Step 3: Get GCP SA bound to KSA via Workload Identity ---
echo ""
echo -e "${YELLOW}--- Resolving GCP SA from KSA binding ---${NC}"

# Get GCP SA email bound to this KSA via Workload Identity
# Format: system:serviceaccount:<namespace>:<ksa-name>
KSA_FULL_NAME="system:serviceaccount:${KSA_NAMESPACE}:${KSA_NAME}"

# Query the KSA's annotated email (if Workload Identity is configured)
GCP_SA_EMAIL=$(kubectl get sa "$KSA_NAME" \
    -n "$KSA_NAMESPACE" \
    ${CLUSTER_ARG:+"$CLUSTER_ARG"} \
    -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null || echo "")

if [[ -z "$GCP_SA_EMAIL" ]]; then
    echo -e "${YELLOW}⚠️  Cannot auto-detect GCP SA from KSA annotation.${NC}"
    echo -e "${YELLOW}   annotation key: iam.gke.io/gcp-service-account${NC}"
    echo ""
    prompt "  Enter GCP SA email manually (e.g., deploy-sa@${LOCAL_PROJECT}.iam.gserviceaccount.com)" GCP_SA_EMAIL ""
    validate_not_empty "$GCP_SA_EMAIL" "GCP SA email"
else
    echo -e "${GREEN}✅ Detected GCP SA from KSA annotation:${NC} ${GCP_SA_EMAIL}"
fi

if [[ ! "$GCP_SA_EMAIL" =~ ^[^@]+@[^.]+\.iam\.gserviceaccount\.com$ ]]; then
    echo -e "${RED}Error: Invalid GCP Service Account email format.${NC}"
    exit 1
fi

GCP_SA_PROJECT=$(echo "$GCP_SA_EMAIL" | cut -d'@' -f2 | cut -d'.' -f1)
echo -e "${GREEN}GCP SA Home Project:${NC} ${GCP_SA_PROJECT}"

# --- Step 4: Cross-Project Info ---
echo ""
echo -e "${YELLOW}--- Cross-Project Pub/Sub Target ---${NC}"

prompt "  Enter cross-project ID (target project where Pub/Sub resides)" CROSS_PROJECT ""
validate_not_empty "$CROSS_PROJECT" "Cross-project ID"

echo ""
echo -e "${CYAN}Pub/Sub resource type:${NC}"
echo "  1) Topic"
echo "  2) Subscription"
while true; do
    read -p "  Select [1/2]: " PUBSUB_TYPE_CHOICE
    case "$PUBSUB_TYPE_CHOICE" in
        1) PUBSUB_TYPE="topic"; break ;;
        2) PUBSUB_TYPE="subscription"; break ;;
        *) echo "Please select 1 or 2." ;;
    esac
done

prompt "  Enter Pub/Sub ${PUBSUB_TYPE} name" PUBSUB_NAME ""
validate_not_empty "$PUBSUB_NAME" "Pub/Sub ${PUBSUB_TYPE} name"

# Build the full resource name
if [[ "$PUBSUB_TYPE" == "topic" ]]; then
    PUBSUB_RESOURCE="projects/${CROSS_PROJECT}/topics/${PUBSUB_NAME}"
else
    PUBSUB_RESOURCE="projects/${CROSS_PROJECT}/subscriptions/${PUBSUB_NAME}"
fi

echo ""
echo -e "${BLUE}==============================================================${NC}"
echo -e "${BLUE}   Configuration Summary                                      ${NC}"
echo -e "${BLUE}==============================================================${NC}"
echo -e "${GREEN}KSA:${NC}               ${KSA_FULL_NAME}"
echo -e "${GREEN}GCP SA:${NC}           ${GCP_SA_EMAIL}"
echo -e "${GREEN}GCP SA Project:${NC}   ${GCP_SA_PROJECT}"
echo -e "${CYAN}Cross Project:${NC}    ${CROSS_PROJECT}"
echo -e "${CYAN}Pub/Sub Type:${NC}      ${PUBSUB_TYPE}"
echo -e "${CYAN}Pub/Sub Resource:${NC}  ${PUBSUB_RESOURCE}"
echo ""

if ! prompt_yes_no "Proceed with verification?"; then
    echo "Aborted."
    exit 0
fi

# ============================================================================
# VERIFICATION STEPS
# ============================================================================

echo ""
echo -e "${YELLOW}[1/5] Verifying GCP SA exists in its home project '${GCP_SA_PROJECT}'...${NC}"
if gcloud iam service-accounts describe "$GCP_SA_EMAIL" --project="$GCP_SA_PROJECT" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Service Account '${GCP_SA_EMAIL}' exists.${NC}"
else
    echo -e "${RED}❌ Cannot verify SA in project '${GCP_SA_PROJECT}' (no access or SA does not exist).${NC}"
fi

# --- Step 2: Check project-level IAM in CROSS PROJECT ---
echo ""
echo -e "${YELLOW}[2/5] Checking project-level IAM roles in cross-project '${CROSS_PROJECT}'...${NC}"

ROLES=$(gcloud projects get-iam-policy "$CROSS_PROJECT" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${GCP_SA_EMAIL}" \
    --format="table(bindings.role)" 2>/dev/null | tail -n +2 || true)

if [[ -z "$ROLES" ]]; then
    echo -e "${YELLOW}⚠️  No direct project-level roles found for this SA in '${CROSS_PROJECT}'.${NC}"
else
    echo -e "${GREEN}✅ Project-level roles granted to '${GCP_SA_EMAIL}' in '${CROSS_PROJECT}':${NC}"
    echo "$ROLES" | sed 's/^/   - /'
fi

# --- Step 3: Check resource-level (Pub/Sub) IAM bindings ---
echo ""
echo -e "${YELLOW}[3/5] Checking Pub/Sub ${PUBSUB_TYPE} IAM bindings in '${CROSS_PROJECT}'...${NC}"

if [[ "$PUBSUB_TYPE" == "topic" ]]; then
    RESOURCE_ROLES=$(gcloud pubsub topics get-iam-policy "$PUBSUB_NAME" \
        --project="$CROSS_PROJECT" \
        --flatten="bindings[].members" \
        --filter="bindings.members:serviceAccount:${GCP_SA_EMAIL}" \
        --format="table(bindings.role)" 2>/dev/null | tail -n +2 || true)
else
    RESOURCE_ROLES=$(gcloud pubsub subscriptions get-iam-policy "$PUBSUB_NAME" \
        --project="$CROSS_PROJECT" \
        --flatten="bindings[].members" \
        --filter="bindings.members:serviceAccount:${GCP_SA_EMAIL}" \
        --format="table(bindings.role)" 2>/dev/null | tail -n +2 || true)
fi

if [[ -z "$RESOURCE_ROLES" ]]; then
    echo -e "${YELLOW}⚠️  No ${PUBSUB_TYPE}-level IAM bindings found for this SA.${NC}"
else
    echo -e "${GREEN}✅ Pub/Sub ${PUBSUB_TYPE}-level roles:${NC}"
    echo "$RESOURCE_ROLES" | sed 's/^/   - /'
fi

# --- Step 4: Check IAM conditions ---
echo ""
echo -e "${YELLOW}[4/5] Checking for conditional IAM bindings on Pub/Sub...${NC}"

if [[ "$PUBSUB_TYPE" == "topic" ]]; then
    COND_BINDINGS=$(gcloud pubsub topics get-iam-policy "$PUBSUB_NAME" \
        --project="$CROSS_PROJECT" \
        --flatten="bindings[].members" \
        --filter="bindings.members:serviceAccount:${GCP_SA_EMAIL} AND bindings.condition:*" \
        --format="table(bindings.role, bindings.condition.title, bindings.condition.expression)" 2>/dev/null | tail -n +2 || true)
else
    COND_BINDINGS=$(gcloud pubsub subscriptions get-iam-policy "$PUBSUB_NAME" \
        --project="$CROSS_PROJECT" \
        --flatten="bindings[].members" \
        --filter="bindings.members:serviceAccount:${GCP_SA_EMAIL} AND bindings.condition:*" \
        --format="table(bindings.role, bindings.condition.title, bindings.condition.expression)" 2>/dev/null | tail -n +2 || true)
fi

if [[ -z "$COND_BINDINGS" ]]; then
    echo -e "${GREEN}✅ No conditional bindings found.${NC}"
else
    echo -e "${CYAN}📋 Conditional IAM bindings:${NC}"
    echo "$COND_BINDINGS"
fi

# --- Step 5: Test permissions with gcloud ---
echo ""
echo -e "${YELLOW}[5/5] Testing actual Pub/Sub permissions...${NC}"

echo -e "  ${CYAN}Testing topic permissions (publish)...${NC}"
PUBLISH_RESULT=$(gcloud pubsub topics test-iam-permissions "$PUBSUB_NAME" \
    --project="$CROSS_PROJECT" \
    --permissions="pubsub.topics.publish" 2>/dev/null | grep -c "pubsub.topics.publish" || echo "0")
if [[ "$PUBLISH_RESULT" -gt 0 ]]; then
    echo -e "  ${GREEN}✅ Can publish to topic${NC}"
else
    echo -e "  ${RED}❌ Cannot publish to topic${NC}"
fi

echo -e "  ${CYAN}Testing subscription permissions (pull)...${NC}"
PULL_RESULT=$(gcloud pubsub subscriptions test-iam-permissions "$PUBSUB_NAME" \
    --project="$CROSS_PROJECT" \
    --permissions="pubsub.subscriptions.pull" 2>/dev/null | grep -c "pubsub.subscriptions.pull" || echo "0")
if [[ "$PULL_RESULT" -gt 0 ]]; then
    echo -e "  ${GREEN}✅ Can pull from subscription${NC}"
else
    echo -e "  ${RED}❌ Cannot pull from subscription${NC}"
fi

echo -e "  ${CYAN}Testing subscription permissions (ack)...${NC}"
ACK_RESULT=$(gcloud pubsub subscriptions test-iam-permissions "$PUBSUB_NAME" \
    --project="$CROSS_PROJECT" \
    --permissions="pubsub.subscriptions.acknowledge" 2>/dev/null | grep -c "pubsub.subscriptions.acknowledge" || echo "0")
if [[ "$ACK_RESULT" -gt 0 ]]; then
    echo -e "  ${GREEN}✅ Can acknowledge messages${NC}"
else
    echo -e "  ${RED}❌ Cannot acknowledge messages${NC}"
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo -e "${BLUE}==============================================================${NC}"
echo -e "${BLUE}   Summary                                                  ${NC}"
echo -e "${BLUE}==============================================================${NC}"
echo -e "${GREEN}KSA:${NC}               ${KSA_FULL_NAME}"
echo -e "${GREEN}GCP SA:${NC}           ${GCP_SA_EMAIL}"
echo -e "${CYAN}Cross Project:${NC}    ${CROSS_PROJECT}"
echo -e "${CYAN}Pub/Sub Resource:${NC}  ${PUBSUB_RESOURCE}"

echo ""
if [[ -n "$ROLES" ]]; then
    echo -e "${GREEN}Project-level roles in ${CROSS_PROJECT}:${NC}"
    echo "$ROLES" | sed 's/^/   - /'
fi

if [[ -n "$RESOURCE_ROLES" ]]; then
    echo ""
    echo -e "${GREEN}Pub/Sub ${PUBSUB_TYPE}-level roles:${NC}"
    echo "$RESOURCE_ROLES" | sed 's/^/   - /'
fi

echo ""
echo -e "${BLUE}==============================================================${NC}"
echo -e "${BLUE}   Verification Complete!                                     ${NC}"
echo -e "${BLUE}==============================================================${NC}"
