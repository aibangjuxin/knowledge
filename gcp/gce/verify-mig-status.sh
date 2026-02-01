#!/bin/bash

# verify-mig-status.sh - Verify MIG instances status after refresh/replace
# Author: Infrastructure Team
# Version: 1.1 (Optimized)

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Function: Usage ---
show_usage() {
    echo -e "${BLUE}Usage:${NC} $0 <mig-keyword>"
    echo -e "${BLUE}Example:${NC} $0 'web-server'"
    echo ""
    echo -e "${BLUE}Description:${NC}"
    echo "  Verify MIG instances status including creation time, health status, etc."
    exit 1
}

# --- Function: Check prerequisites ---
check_prerequisites() {
    local missing_deps=0
    
    if ! command -v gcloud &> /dev/null; then
        echo -e "${RED}Error: gcloud CLI not found. Please install Google Cloud SDK.${NC}"
        missing_deps=1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq not found. Please install jq (e.g., brew install jq, apt-get install jq).${NC}"
        missing_deps=1
    fi

    if [ $missing_deps -ne 0 ]; then
        exit 1
    fi
}

# --- Function: Get MIG list by keyword ---
get_mig_list() {
    local keyword=$1
    echo -e "${BLUE}Searching for MIGs matching keyword: ${keyword}${NC}"
    echo ""
    
    # Search in all zones
    local migs=$(gcloud compute instance-groups managed list \
        --format=\"table[no-heading](name,zone,baseInstanceName,targetSize,INSTANCE_TEMPLATE)\" \
        --filter=\"name:${keyword}\" 2>/dev/null)
    
    # Search in all regions (regional MIGs)
    local regional_migs=$(gcloud compute instance-groups managed list \
        --format=\"table[no-heading](name,region,baseInstanceName,targetSize,INSTANCE_TEMPLATE)\" \
        --filter=\"name:${keyword}\" 2>/dev/null)
    
    if [ -z "$migs" ] && [ -z "$regional_migs" ]; then
        echo -e "${RED}Error: No MIG found matching keyword '${keyword}'${NC}"
        exit 1
    fi
    
    # Output zonal MIGs if found
    if [ -n "$migs" ]; then
        echo "$migs"
    fi
    
    # Output regional MIGs if found
    if [ -n "$regional_migs" ]; then
        echo "$regional_migs"
    fi
}

# --- Function: Get instance details safely ---
get_instance_details() {
    local instance_name=$1
    local zone=$2
    
    if [ -z "$zone" ] || [ -z "$instance_name" ]; then
        echo "ERROR: Missing zone or instance name"
        return 1
    fi

    # Execute command and handle errors
    local cmd="gcloud compute instances describe ${instance_name} --zone=${zone} --format=json"
    local result=$(eval $cmd 2>&1)
    
    if [ $? -ne 0 ]; then
        # Check if it's a 404 (instance might be terminating)
        if [[ "$result" == *"was not found"* ]]; then
             echo "NOT_FOUND"
        else
             echo "ERROR: Failed to describe instance ${instance_name} in zone ${zone}"
        fi
        return 1
    fi
    
    echo "$result"
}

# --- Function: Verify MIG instances ---
verify_mig_instances() {
    local mig_name=$1
    local location=$2
    local location_type=$3
    
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}Verifying MIG: ${mig_name}${NC}"
    echo -e "${GREEN}Location: ${location} (${location_type})${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    
    # Get MIG details
    local mig_cmd=""
    if [ "$location_type" == "zone" ]; then
        mig_cmd="gcloud compute instance-groups managed describe ${mig_name} --zone=${location} --format=json"
    else
        mig_cmd="gcloud compute instance-groups managed describe ${mig_name} --region=${location} --format=json"
    fi
    
    local mig_info=$(eval $mig_cmd 2>&1)
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to get MIG details${NC}"
        return 1
    fi
    
    local target_size=$(echo "$mig_info" | jq -r '.targetSize // 0')
    local current_actions=$(echo "$mig_info" | jq -r '.currentActions // {}')
    local instance_template=$(echo "$mig_info" | jq -r '.instanceTemplate' | awk -F'/' '{print $NF}')
    
    echo -e "${BLUE}MIG Configuration:${NC}"
    echo "  Target Size: ${target_size}"
    echo "  Instance Template: ${instance_template}"
    echo "  Current Actions:"
    echo "$current_actions" | jq '.'
    echo ""
    
    # Get instances list
    local instances_cmd=""
    if [ "$location_type" == "zone" ]; then
        instances_cmd="gcloud compute instance-groups managed list-instances ${mig_name} --zone=${location} --format=json"
    else
        instances_cmd="gcloud compute instance-groups managed list-instances ${mig_name} --region=${location} --format=json"
    fi
    
    local instances=$(eval $instances_cmd 2>/dev/null)
    if [ -z "$instances" ] || [ "$instances" == "[]" ]; then
        echo -e "${YELLOW}Warning: No instances found in this MIG${NC}"
        return 0
    fi
    
    local instance_count=$(echo "$instances" | jq '. | length')
    echo -e "${BLUE}Found ${instance_count} instances:${NC}"
    echo ""
    
    # Create summary table header
    printf "% -35s % -15s % -15s % -25s % -30s\n" "INSTANCE_NAME" "ZONE" "STATUS" "CREATION_TIME" "INSTANCE_TEMPLATE"
    printf "% -35s % -15s % -15s % -25s % -30s\n" "-----------------------------------" "--------------- " "--------------- " "-------------------------" "------------------------------"
    
    # Iterate through instances
    local healthy_count=0
    local unhealthy_count=0
    
    for i in $(seq 0 $((instance_count - 1))); do
        local instance_url=$(echo "$instances" | jq -r ".[${i}].instance")
        local instance_name=$(echo "$instance_url" | awk -F'/' '{print $NF}')
        
        # Extract zone from URL: .../zones/us-central1-a/instances/...
        local instance_zone=$(echo "$instance_url" | sed -n 's/.*\/zones\/\([^\/]*\)\/instances\/.*/\1/p')
        
        local instance_status=$(echo "$instances" | jq -r ".[${i}].instanceStatus")
        local current_action=$(echo "$instances" | jq -r ".[${i}].currentAction // \"NONE\"")
        
        # Optimization: Pass extracted zone directly
        local instance_details=$(get_instance_details "$instance_name" "$instance_zone")
        
        if [[ "$instance_details" == ERROR* ]] || [[ "$instance_details" == "NOT_FOUND" ]]; then
            printf "% -35s % -15s % -15s % -25s % -30s\n" "$instance_name" "${instance_zone}" "UNKNOWN" "N/A" "N/A"
            ((unhealthy_count++))
            continue
        fi
        
        local creation_time=$(echo "$instance_details" | jq -r '.creationTimestamp // "N/A"')
        local instance_template_from_metadata=$(echo "$instance_details" | jq -r '.metadata.items[] | select(.key=="instance-template") | .value' 2>/dev/null | awk -F'/' '{print $NF}')
        
        # Status color coding
        local status_display="$instance_status"
        if [ "$instance_status" == "RUNNING" ]; then
            status_display="${GREEN}${instance_status}${NC}"
            ((healthy_count++))
        else
            status_display="${RED}${instance_status}${NC}"
            ((unhealthy_count++))
        fi
        
        printf "% -35s % -15s % -24b % -25s % -30s\n" \
            "${instance_name:0:35}" \
            "${instance_zone}" \
            "$status_display" \
            "${creation_time:0:19}" \
            "${instance_template_from_metadata:-N/A}"
        
        # Show current action if any
        if [ "$current_action" != "NONE" ]; then
            echo -e "  ${YELLOW}→ Current Action: ${current_action}${NC}"
        fi
    done
    
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${BLUE}Summary:${NC}"
    echo "  Total Instances: ${instance_count}"
    echo -e "  Healthy (RUNNING): ${GREEN}${healthy_count}${NC}"
    echo -e "  Unhealthy/Other: ${RED}${unhealthy_count}${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
}

# --- Main Execution ---
main() {
    # Check arguments
    if [ "$#" -ne 1 ]; then
        echo -e "${RED}Error: Missing MIG keyword argument.${NC}"
        show_usage
    fi
    
    local keyword=$1
    
    # Check prerequisites
    check_prerequisites
    
    # Get MIG list
    local mig_data=$(get_mig_list "$keyword")
    
    # Process each MIG
    # Use while loop with input redirection to handle multiple lines correctly
    while IFS= read -r line; do
        if [ -z "$line" ]; then
            continue
        fi
        
        local mig_name=$(echo "$line" | awk '{print $1}')
        local location=$(echo "$line" | awk '{print $2}')
        
        # Determine if it's zonal or regional
        local location_type="zone"
        if [[ "$location" =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
            location_type="region"
        fi
        
        verify_mig_instances "$mig_name" "$location" "$location_type"
    done <<< "$mig_data"
    
    echo -e "${GREEN}Verification completed!${NC}"
}

# Run main function
main "$@"
