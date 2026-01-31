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
while read -r name zone region; do
    # Skip header or empty lines
    if [ "$name" == "NAME" ] || [ -z "$name" ]; then continue; fi

    # Determine if it's regional or zonal
    # Both zone and region might be URLs or simple names
    if [ -n "$zone" ]; then
        # Zonal MIG
        # Extract zone name from URL if needed
        if [[ "$zone" == *"zones/"* ]]; then
            ZONE_NAME=$(echo "$zone" | sed -n 's|.*/zones/\([^/]*\).*|\1|p')
        else
            ZONE_NAME="$zone"
        fi
        LOCATION_FLAG="--zone=$ZONE_NAME"
        LOCATION_TYPE="zonal"
        LOCATION="$ZONE_NAME"
    else
        # Regional MIG
        # Extract region name from URL if needed
        if [[ "$region" == *"regions/"* ]]; then
            REGION_NAME=$(echo "$region" | sed -n 's|.*/regions/\([^/]*\).*|\1|p')
        else
            REGION_NAME="$region"
        fi
        LOCATION_FLAG="--region=$REGION_NAME"
        LOCATION_TYPE="regional"
        LOCATION="$REGION_NAME"
    fi

    echo -e "\n${BLUE}>>> Analyzing MIG: ${GREEN}$name${BLUE} (Location: $LOCATION, Type: $LOCATION_TYPE)${NC}"

    # Get MIG details
    MIG_DESC=$(gcloud compute instance-groups managed describe "$name" $LOCATION_FLAG --format="json")
    TARGET_TEMPLATE=$(echo "$MIG_DESC" | jq -r '.instanceTemplate' | awk -F'/' '{print $NF}')
    IS_STABLE=$(echo "$MIG_DESC" | jq -r '.status.isStable')
    UPDATE_POLICY=$(echo "$MIG_DESC" | jq -r '.updatePolicy.type')
    
    echo -e "${BLUE}Target Template:${NC} $TARGET_TEMPLATE"
    echo -e "${BLUE}Status Stable:  ${NC} $([ "$IS_STABLE" == "true" ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO (Updating...)${NC}")"
    echo -e "${BLUE}Update Policy:  ${NC} $UPDATE_POLICY"

    # --- 3. Instance Level Details ---
    echo -e "\n${YELLOW}[2/3] Fetching instance details...${NC}"
    
    # 获取实例列表和健康状态
    INSTANCE_DATA=$(gcloud compute instance-groups managed list-instances "$name" $LOCATION_FLAG --format="json")
    
    # 打印表头
    printf "${BLUE}%-35s %-12s %-12s %-15s %-30s %-20s${NC}\n" \
        "INSTANCE_NAME" "STATUS" "ACTION" "HEALTH" "TEMPLATE" "UPTIME"
    echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    
    # 遍历每个实例
    echo "$INSTANCE_DATA" | jq -c '.[]' | while read -r instance; do
        inst_name=$(echo "$instance" | jq -r '.instance' | awk -F'/' '{print $NF}')
        inst_status=$(echo "$instance" | jq -r '.instanceStatus // "UNKNOWN"')
        inst_action=$(echo "$instance" | jq -r '.currentAction // "NONE"')
        inst_template=$(echo "$instance" | jq -r '.instanceTemplate' | awk -F'/' '{print $NF}')
        
        # 获取健康状态
        inst_health=$(echo "$instance" | jq -r '.instanceHealth[0].detailedHealthState // "N/A"')
        
        # 对于 regional MIG，需要从实例 URL 中提取 zone
        # URL 格式: https://www.googleapis.com/compute/v1/projects/PROJECT/zones/ZONE/instances/INSTANCE
        if [ "$LOCATION_TYPE" == "regional" ]; then
            inst_url=$(echo "$instance" | jq -r '.instance')
            # 使用 sed 提取 zones/ 后面的部分
            inst_zone=$(echo "$inst_url" | sed -n 's|.*/zones/\([^/]*\)/.*|\1|p')
            INST_LOCATION_FLAG="--zone=$inst_zone"
        else
            INST_LOCATION_FLAG="$LOCATION_FLAG"
        fi
        
        # 获取创建时间并计算运行时长
        CREATE_TIME=$(gcloud compute instances describe "$inst_name" $INST_LOCATION_FLAG --format="value(creationTimestamp)")
        
        # 计算运行时长（参考 get_instance_uptime.sh）
        if [ -n "$CREATE_TIME" ]; then
            START_TIME_UTC=$(TZ=UTC date -d"$CREATE_TIME" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
            CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            SECONDS1=$(date -u -d "$CURRENT_TIME" +"%s")
            SECONDS2=$(date -u -d "$START_TIME_UTC" +"%s")
            DIFF_SECONDS=$((SECONDS1 - SECONDS2))
            
            # 计算天、小时、分钟
            DAYS=$((DIFF_SECONDS / 86400))
            HOURS=$(((DIFF_SECONDS % 86400) / 3600))
            MINUTES=$(((DIFF_SECONDS % 3600) / 60))
            
            if [ $DAYS -gt 0 ]; then
                UPTIME="${DAYS}d ${HOURS}h ${MINUTES}m"
            else
                UPTIME="${HOURS}h ${MINUTES}m"
            fi
        else
            UPTIME="N/A"
        fi
        
        # 格式化显示
        # Action 高亮
        if [ "$inst_action" != "NONE" ]; then
            DISP_ACTION="${YELLOW}${inst_action}${NC}"
        else
            DISP_ACTION="${inst_action}"
        fi
        
        # Template 对比
        if [ "$inst_template" != "$TARGET_TEMPLATE" ]; then
            DISP_TEMPLATE="${RED}${inst_template}*${NC}"
        else
            DISP_TEMPLATE="${GREEN}${inst_template}${NC}"
        fi
        
        # Health 状态颜色
        case "$inst_health" in
            "HEALTHY")
                DISP_HEALTH="${GREEN}${inst_health}${NC}"
                ;;
            "UNHEALTHY")
                DISP_HEALTH="${RED}${inst_health}${NC}"
                ;;
            "N/A")
                DISP_HEALTH="${YELLOW}${inst_health}${NC}"
                ;;
            *)
                DISP_HEALTH="${inst_health}"
                ;;
        esac
        
        printf "%-35s %-12s %b %-15s %b %-20s\n" \
            "$inst_name" "$inst_status" "$DISP_ACTION" "$DISP_HEALTH" "$DISP_TEMPLATE" "$UPTIME"
    done
    
    echo ""

done <<< "$(gcloud compute instance-groups managed list --filter="name ~ $KEYWORD" --format="value(name,zone,region)")"

echo -e "\n${BLUE}====================================================${NC}"
echo -e "${BLUE}   Verification Complete!                           ${NC}"
echo -e "${BLUE}====================================================${NC}"
