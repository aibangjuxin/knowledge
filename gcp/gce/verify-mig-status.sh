#!/bin/bash

# verify-mig-status.sh - Verify MIG instances status after refresh/replace
# Author: Infrastructure Team
# Version: 1.2 (Linux Hardened - Fixed JQ Parse Error)

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
        echo -e "${RED}Error: jq not found. Please install jq (e.g., sudo apt-get install jq).${NC}"
        missing_deps=1
    fi

    if [ $missing_deps -ne 0 ]; then
        exit 1
    fi
}

# --- Function: Get MIG list by keyword ---
get_mig_list() {
    local keyword=$1
    # CRITICAL: Send status messages to stderr so they don't pollute the data stream (stdout)
    echo -e "${BLUE}Searching for MIGs matching keyword: ${keyword}${NC}" >&2
    echo "" >&2
    
    local json_data
    # Unified call for both zonal and regional MIGs
    json_data=$(gcloud compute instance-groups managed list --filter="name:${keyword}" --format=json 2>/dev/null)
    
    if [ -z "$json_data" ] || [ "$json_data" == "[]" ]; then
        echo -e "${RED}Error: No MIG found matching keyword '${keyword}'${NC}" >&2
        exit 1
    fi
    
    # Extract name and location (handles both .zone and .region fields)
    echo "$json_data" | jq -r '.[] | .name + " " + (.zone // .region | split("/") | last)'
}

# --- Function: Get instance details safely ---
# ... (rest of the functions remain the same)

# --- Function: Get instance details safely ---
get_instance_details() {
    local instance_name=$1
    local zone=$2
    
    if [ -z "$zone" ] || [ -z "$instance_name" ]; then
        return 1
    fi

    local result
    # CRITICAL: Separate assignment from local to catch exit code.
    # CRITICAL: Do NOT redirect 2>&1 into JSON variable because warnings/errors break jq.
    result=$(gcloud compute instances describe "${instance_name}" --zone="${zone}" --format=json 2>/dev/null)
    local exit_val=$?
    
    if [ $exit_val -ne 0 ] || [ -z "$result" ]; then
        # If it failed, check why (let stderr flow for info if wanted, or just return 1)
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
    
    local mig_info
    if [ "$location_type" == "zone" ]; then
        mig_info=$(gcloud compute instance-groups managed describe "${mig_name}" --zone="${location}" --format=json 2>/dev/null)
    else
        mig_info=$(gcloud compute instance-groups managed describe "${mig_name}" --region="${location}" --format=json 2>/dev/null)
    fi
    
    if [ $? -ne 0 ] || [ -z "$mig_info" ]; then
        echo -e "${RED}Error: Failed to get MIG details for ${mig_name}${NC}"
        return 1
    fi
    
    local target_size
    target_size=$(echo "$mig_info" | jq -r '.targetSize // 0')
    local current_actions
    current_actions=$(echo "$mig_info" | jq -r '.currentActions // {}')
    local instance_template
    instance_template=$(echo "$mig_info" | jq -r '.instanceTemplate' | awk -F'/' '{print $NF}')
    
    echo -e "${BLUE}MIG Configuration:${NC}"
    echo "  Target Size: ${target_size}"
    echo "  Instance Template: ${instance_template}"
    echo "  Current Actions:"
    echo "$current_actions" | jq '.'
    echo ""
    
    local instances
    if [ "$location_type" == "zone" ]; then
        instances=$(gcloud compute instance-groups managed list-instances "${mig_name}" --zone="${location}" --format=json 2>/dev/null)
    else
        instances=$(gcloud compute instance-groups managed list-instances "${mig_name}" --region="${location}" --format=json 2>/dev/null)
    fi
    
    if [ -z "$instances" ] || [ "$instances" == "[]" ]; then
        echo -e "${YELLOW}Warning: No instances found in this MIG${NC}"
        return 0
    fi
    
    local instance_count
    instance_count=$(echo "$instances" | jq '. | length')
    echo -e "${BLUE}Found ${instance_count} instances:${NC}"
    echo ""
    
    printf "%-35s %-15s %-15s %-25s %-30s\n" "INSTANCE_NAME" "ZONE" "STATUS" "CREATION_TIME" "INSTANCE_TEMPLATE"
    printf "%-35s %-15s %-15s %-25s %-30s\n" "-----------------------------------" "---------------" "---------------" "-------------------------" "------------------------------"
    
    local healthy_count=0
    local unhealthy_count=0
    
    for i in $(seq 0 $((instance_count - 1))); do
        local instance_url
        instance_url=$(echo "$instances" | jq -r ".[${i}].instance")
        local instance_name
        instance_name=$(echo "$instance_url" | awk -F'/' '{print $NF}')
        
        local instance_zone
        instance_zone=$(echo "$instance_url" | sed -n 's/.*\/zones\/\([^\/]*\)\/instances\/.*/\1/p')
        
        local instance_status
        instance_status=$(echo "$instances" | jq -r ".[${i}].instanceStatus")
        local current_action
        current_action=$(echo "$instances" | jq -r ".[${i}].currentAction // \"NONE\"")
        
        local instance_details
        instance_details=$(get_instance_details "$instance_name" "$instance_zone")
        
        if [ -z "$instance_details" ]; then
            printf "%-35s %-15s %-15s %-25s %-30s\n" "$instance_name" "${instance_zone}" "UNKNOWN" "N/A" "N/A"
            ((unhealthy_count++))
            continue
        fi
        
        local creation_time
        creation_time=$(echo "$instance_details" | jq -r '.creationTimestamp // "N/A"')
        
        # GNU date compatibility for Linux
        local creation_time_fmt
        if [[ "$creation_time" != "N/A" ]]; then
            creation_time_fmt=$(date -d "${creation_time}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "${creation_time:0:19}")
        else
            creation_time_fmt="N/A"
        fi

        local instance_template_from_metadata
        instance_template_from_metadata=$(echo "$instance_details" | jq -r '.metadata.items[]? | select(.key=="instance-template") | .value' 2>/dev/null | awk -F'/' '{print $NF}')
        
        local status_display="$instance_status"
        if [ "$instance_status" == "RUNNING" ]; then
            status_display="${GREEN}${instance_status}${NC}"
            ((healthy_count++))
        else
            status_display="${RED}${instance_status}${NC}"
            ((unhealthy_count++))
        fi
        
        printf "%-35s %-15s %-24b %-25s %-30s\n" \
            "${instance_name:0:35}" \
            "${instance_zone}" \
            "$status_display" \
            "${creation_time_fmt}" \
            "${instance_template_from_metadata:-N/A}"
        
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
    if [ "$#" -ne 1 ]; then
        echo -e "${RED}Error: Missing MIG keyword argument.${NC}"
        show_usage
    fi
    
    local keyword=$1
    check_prerequisites
    
    local mig_data
    mig_data=$(get_mig_list "$keyword")
    # Process each MIG
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        
        local mig_name
        mig_name=$(echo "$line" | awk '{print $1}')
        local location
        location=$(echo "$line" | awk '{print $2}')
        
        # Skip header lines if they somehow leaked (e.g., if keyword is 'Searching')
        if [ "$mig_name" == "Searching" ] || [ "$mig_name" == "INSTANCE_NAME" ]; then
            continue
        fi
        
        # Determine if it's zonal or regional
        local location_type="zone"
        if [[ "$location" =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
            location_type="region"
        fi
        
        verify_mig_instances "$mig_name" "$location" "$location_type"
    done <<< "$mig_data"
    
    echo -e "${GREEN}Verification completed!${NC}"
}

main "$@"
