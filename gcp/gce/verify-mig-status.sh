#!/bin/bash

# ==============================================================================
# Script Name: verify-mig-status.sh
# Description: Verifies the status of Managed Instance Groups (MIG) and their instances.
# Usage: ./verify-mig-status.sh <mig-keyword>
# ==============================================================================

# --- Color Definitions ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Function: Usage ---
show_usage() {
    echo -e "${BLUE}Usage:${NC} $0 <mig-keyword>"
    echo -e "${BLUE}Example:${NC} $0 'web-server'"
    exit 1
}

# --- Check Arguments ---
if [ "$#" -ne 1 ]; then
    echo -e "${RED}Error: Missing MIG keyword argument.${NC}"
    show_usage
fi

KEYWORD=$1
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}   GCP MIG Status Verification Tool                 ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Project:${NC} $PROJECT_ID"
echo -e "${GREEN}Keyword:${NC} $KEYWORD"
echo -e ""

# --- 1. Discover MIGs ---
echo -e "${YELLOW}[1/3] Searching for MIGs matching '$KEYWORD'...${NC}"
MIGS=$(gcloud compute instance-groups managed list --filter="name ~ $KEYWORD" --format="table(name,zone,region,targetSize,status.isStable)")

if [ -z "$(echo "$MIGS" | tail -n +2)" ]; then
    echo -e "${RED}❌ No Managed Instance Groups found matching keyword '$KEYWORD'.${NC}"
    exit 1
fi

echo -e "${GREEN}Found following MIGs:${NC}"
echo "$MIGS"

# --- 2. Iterate through found MIGs ---
while read -r name location type; do
    # Skip header
    if [ "$name" == "NAME" ] || [ -z "$name" ]; then continue; fi

    # Determine if it's regional or zonal
    LOCATION_FLAG="--zone=$location"
    if [[ "$location" == *[a-z] ]]; then 
        LOCATION_FLAG="--zone=$location"
    else
        LOCATION_FLAG="--region=$location"
    fi

    echo -e "\n${BLUE}>>> Analyzing MIG: ${GREEN}$name${BLUE} (Location: $location)${NC}"

    # Get MIG details
    MIG_DESC=$(gcloud compute instance-groups managed describe "$name" $LOCATION_FLAG --format="json")
    TARGET_TEMPLATE=$(echo "$MIG_DESC" | jq -r '.instanceTemplate' | awk -F'/' '{print $NF}')
    IS_STABLE=$(echo "$MIG_DESC" | jq -r '.status.isStable')
    UPDATE_POLICY=$(echo "$MIG_DESC" | jq -r '.updatePolicy.type')
    
    echo -e "${BLUE}Target Template:${NC} $TARGET_TEMPLATE"
    echo -e "${BLUE}Status Stable:  ${NC} $([ "$IS_STABLE" == "true" ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO (Updating...)${NC}")"
    echo -e "${BLUE}Update Policy:  ${NC} $UPDATE_POLICY"

    # --- 3. Instance Level Details ---
    echo -e "${YELLOW}[2/3] Fetching instance details...${NC}"
    # We use list-instances and then describe individual instances for creation time
    INSTANCE_LIST=$(gcloud compute instance-groups managed list-instances "$name" $LOCATION_FLAG \
        --format="table[no-headers](instance.basename(),status,currentAction,instanceTemplate.basename())")

    echo -e "${BLUE}%-30s %-15s %-15s %-30s %-25s${NC}" "NAME" "STATUS" "ACTION" "TEMPLATE" "CREATION_TIME"
    
    while read -r inst_name inst_status inst_action inst_template; do
        if [ -z "$inst_name" ]; then continue; fi
        
        # Get creation time (requires separate call or complex filter, here we optimize with one describe per instance or a bulk command)
        # To avoid too many calls, we can try to get creation time for all VMs in one go if possible, 
        # but for accuracy per MIG we do it here.
        CREATE_TIME=$(gcloud compute instances describe "$inst_name" $LOCATION_FLAG --format="value(creationTimestamp)" 2>/dev/null)
        
        # Formatting action/template for highlighting
        DISP_ACTION=$inst_action
        if [ "$inst_action" != "NONE" ]; then DISP_ACTION="${YELLOW}$inst_action${NC}"; fi
        
        DISP_TEMPLATE=$inst_template
        if [ "$inst_template" != "$TARGET_TEMPLATE" ]; then DISP_TEMPLATE="${RED}$inst_template (Old)${NC}"; else DISP_TEMPLATE="${GREEN}$inst_template${NC}"; fi

        printf "%-30s %-15s %b %b %-25s\n" "$inst_name" "$inst_status" "$DISP_ACTION" "$DISP_TEMPLATE" "$CREATE_TIME"
    done <<< "$INSTANCE_LIST"

    # --- 4. Health Check Status ---
    echo -e "\n${YELLOW}[3/3] Checking health states...${NC}"
    HEALTH=$(gcloud compute instance-groups managed list-instances "$name" $LOCATION_FLAG --format="table(instance.basename(),healthStatus[0].healthState)")
    if [ -n "$(echo "$HEALTH" | tail -n +2)" ]; then
        echo "$HEALTH"
    else
        echo -e "${YELLOW}No health check information available for this MIG.${NC}"
    fi

done <<< "$(gcloud compute instance-groups managed list --filter="name ~ $KEYWORD" --format="value(name,zone,region)")"

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${BLUE}   Verification Complete!                           ${NC}"
echo -e "${BLUE}====================================================${NC}"
