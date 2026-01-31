#!/bin/bash

# ==============================================================================
# Script Name: verify-gce-sa.sh
# Description: Verifies the existence, keys, and IAM roles of a GCP Service Account.
# Usage: ./verify-gce-sa.sh {sa-email}
# ==============================================================================

# --- Color Definitions ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Function: Usage ---
show_usage() {
    echo -e "${BLUE}Usage:${NC} $0 <sa-email>"
    echo -e "${BLUE}Example:${NC} $0 dev-us-west1-app-sa@prod-project-123.iam.gserviceaccount.com"
    exit 1
}

# --- Check Arguments ---
if [ "$#" -ne 1 ]; then
    echo -e "${RED}Error: Missing Service Account email argument.${NC}"
    show_usage
fi

SA_EMAIL=$1

# --- Basic Validation ---
if [[ ! "$SA_EMAIL" =~ ^[^@]+@[^.]+\.iam\.gserviceaccount\.com$ ]]; then
    echo -e "${RED}Error: Invalid Service Account email format.${NC}"
    show_usage
fi

# --- Extract Info ---
SA_NAME=$(echo "$SA_EMAIL" | cut -d'@' -f1)
SA_PROJECT_ID=$(echo "$SA_EMAIL" | cut -d'@' -f2 | cut -d'.' -f1)
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   GCP Service Account Verification Tool            ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Target SA:${NC} $SA_EMAIL"
echo -e "${GREEN}Project ID:${NC} $SA_PROJECT_ID"
echo -e ""

# --- 1. Check if the SA exists ---
echo -e "${YELLOW}[1/4] Checking if Service Account exists...${NC}"
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$SA_PROJECT_ID" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Service Account '$SA_EMAIL' not found in project '$SA_PROJECT_ID'.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Service Account exists.${NC}"

# --- 2. Check if the SA has any user-managed keys ---
echo -e "\n${YELLOW}[2/4] Checking for user-managed keys...${NC}"
KEYS=$(gcloud iam service-accounts keys list --iam-account="$SA_EMAIL" --project="$SA_PROJECT_ID" --filter="keyType=USER_MANAGED" --format="table(name.basename(),validAfterTime,validBeforeTime)")

if [ -z "$(echo "$KEYS" | tail -n +2)" ]; then
    echo -e "${GREEN}✅ No user-managed keys found (Safe).${NC}"
else
    echo -e "${RED}⚠️  User-managed keys detected! (Security Risk)${NC}"
    echo "$KEYS"
fi

# --- 3. Check project-level IAM roles ---
echo -e "\n${YELLOW}[3/4] Checking project-level IAM roles...${NC}"
# Using the command provided by the user
ROLES=$(gcloud projects get-iam-policy "$SA_PROJECT_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.members:$SA_EMAIL" \
    --format="table(bindings.role)" | tail -n +2)

if [ -z "$ROLES" ]; then
    echo -e "${YELLOW}⚠️  No direct project-level roles found for this SA.${NC}"
else
    echo -e "${GREEN}✅ Found roles in project '$SA_PROJECT_ID':${NC}"
    echo "$ROLES" | sed 's/^/  - /'
fi

# --- 4. Check Service Account level IAM policy (Permissions on the SA) ---
echo -e "\n${YELLOW}[4/4] Checking permissions ON this Service Account...${NC}"
SA_IAM=$(gcloud iam service-accounts get-iam-policy "$SA_EMAIL" --project="$SA_PROJECT_ID" --format="table(bindings.role, bindings.members)" | tail -n +2)

if [ -z "$SA_IAM" ]; then
    echo -e "${GREEN}✅ No special IAM bindings on this SA resource itself.${NC}"
else
    echo -e "${GREEN}✅ Found the following entities with access to this SA:${NC}"
    echo "$SA_IAM"
fi

# --- Cross-Project Warning ---
if [ "$SA_PROJECT_ID" != "$CURRENT_PROJECT" ]; then
    echo -e "\n${RED}Note:${NC} This SA is in project ${RED}$SA_PROJECT_ID${NC}, but your current gcloud context is ${RED}$CURRENT_PROJECT${NC}."
fi

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${BLUE}   Verification Complete!                           ${NC}"
echo -e "${BLUE}====================================================${NC}"