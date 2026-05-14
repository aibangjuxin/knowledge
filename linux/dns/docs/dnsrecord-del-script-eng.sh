#!/bin/bash

# GCP Cloud DNS Record Batch Deletion Script
# Purpose: Delete all related records (CNAME and A records) for specified domains in Cloud DNS Zone

# ============================================
# Configuration Section
# ============================================

# GCP Project ID
PROJECT_ID="your-project-id"

# Default DNS Zone Name
DEFAULT_ZONE_NAME="private-access"

# Domain list to be deleted (just provide the original domains)
DOMAINS=(
    "www.example.com"
    "api.example.com"
    "login.microsoft.com"
    "graph.microsoft.com"
)

# ============================================
# Color Definitions
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# Function Definitions
# ============================================

# Display help information
show_help() {
    cat << EOF
Usage: $(basename $0) [options]

Options:
  -p PROJECT_ID    Specify GCP Project ID (default: $PROJECT_ID)
  -z ZONE_NAME     Specify DNS Zone Name (default: $DEFAULT_ZONE_NAME)
  -n               Preview mode, only show records to be deleted, don't actually delete
  -h               Show this help information

Examples:
  $(basename $0)                                    # Use default configuration
  $(basename $0) -p my-project -z my-zone          # Specify project and Zone
  $(basename $0) -n                                # Preview mode
  $(basename $0) -z custom-zone -n                 # Preview deletion for specified Zone

Description:
  The script queries all records related to the domain list in the Cloud DNS Zone,
  including CNAME chains and A records, and deletes them.
  The deletion logic is based on actual records in the Zone, not on current DNS resolution results.

EOF
}

# Parse command-line arguments
parse_args() {
    DRY_RUN=false

    while getopts "p:z:nh" opt; do
        case $opt in
            p)
                PROJECT_ID="$OPTARG"
                ;;
            z)
                ZONE_NAME="$OPTARG"
                ;;
            n)
                DRY_RUN=true
                ;;
            h)
                show_help
                exit 0
                ;;
            \?)
                echo -e "${RED}Error: Invalid option -$OPTARG${NC}" >&2
                show_help
                exit 1
                ;;
        esac
    done
}

# Check if required commands exist
check_dependencies() {
    local missing_deps=()

    if ! command -v gcloud &> /dev/null; then
        missing_deps+=(gcloud)
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required commands: ${missing_deps[*]}${NC}"
        echo "Please install the missing tools and try again"
        exit 1
    fi
}

# Set GCP Project
set_project() {
    echo -e "${BLUE}Setting GCP Project: $PROJECT_ID${NC}"
    gcloud config set project "$PROJECT_ID" --quiet

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Cannot set project $PROJECT_ID${NC}"
        exit 1
    fi
}

# List all DNS Zones
list_zones() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}DNS Zones in Current Project:${NC}"
    echo -e "${GREEN}========================================${NC}"

    gcloud dns managed-zones list \
        --format='table[box](dnsName, creationTime:sort=1, name, privateVisibilityConfig.networks.networkUrl.basename(), description)'

    echo ""
}

# Check if Zone exists
check_zone_exists() {
    local zone=$1

    if ! gcloud dns managed-zones describe "$zone" &> /dev/null; then
        echo -e "${RED}Error: DNS Zone '$zone' does not exist${NC}"
        echo "Available Zones:"
        gcloud dns managed-zones list --format="value(name)"
        exit 1
    fi
}

# Find all records related to domain
find_related_records() {
    local zone=$1
    local domain=$2
    local -n records_ref=$3

    echo -e "${BLUE}Finding domain related records: $domain${NC}" >&2

    # Ensure domain ends with .
    local search_domain="$domain"
    [[ "$search_domain" != *. ]] && search_domain="${search_domain}."

    # Query all records
    local all_records=$(gcloud dns record-sets list \
        --zone="$zone" \
        --format="csv[no-heading](name,type,ttl,rrdatas)" 2>/dev/null)

    if [ -z "$all_records" ]; then
        echo -e "${YELLOW}  No records found${NC}" >&2
        return 1
    fi

    # Store found records
    local found_records=()
    local processed_domains=()

    # Recursively find CNAME chain
    local current_domain="$search_domain"
    local max_depth=10
    local depth=0

    while [ $depth -lt $max_depth ]; do
        # Check if already processed this domain (to avoid loops)
        if [[ " ${processed_domains[@]} " =~ " ${current_domain} " ]]; then
            break
        fi

        processed_domains+=("$current_domain")

        # Find records for current domain
        local record=$(echo "$all_records" | grep "^${current_domain}," | head -1)

        if [ -z "$record" ]; then
            break
        fi

        local record_type=$(echo "$record" | cut -d',' -f2)
        local record_ttl=$(echo "$record" | cut -d',' -f3)
        local record_data=$(echo "$record" | cut -d',' -f4-)

        # Remove quotes
        record_data=$(echo "$record_data" | sed 's/"//g')

        echo -e "  ${GREEN}Found $record_type record:${NC} $current_domain -> $record_data" >&2

        # Save record information
        found_records+=("$current_domain|$record_type|$record_ttl|$record_data")

        # If CNAME, continue tracking
        if [ "$record_type" = "CNAME" ]; then
            current_domain="$record_data"
            [[ "$current_domain" != *. ]] && current_domain="${current_domain}."
        elif [ "$record_type" = "A" ]; then
            # Reached A record, end
            break
        else
            break
        fi

        ((depth++))
    done

    if [ ${#found_records[@]} -eq 0 ]; then
        echo -e "${YELLOW}  No related records found${NC}" >&2
        return 1
    fi

    # Return found records
    records_ref=("${found_records[@]}")
    return 0
}

# Delete DNS records
delete_dns_records() {
    local zone=$1
    local domain=$2
    local -n records_array=$3
    local dry_run=$4

    if [ "$dry_run" = true ]; then
        echo -e "\n${YELLOW}[Preview Mode] Will delete the following records:${NC}" >&2
    else
        echo -e "\n${BLUE}Deleting DNS records for $domain...${NC}" >&2
    fi

    local success=true
    local deleted_count=0

    # Delete in reverse order (first delete A records, then CNAME)
    for ((i=${#records_array[@]}-1; i>=0; i--)); do
        local record="${records_array[$i]}"

        local record_name=$(echo "$record" | cut -d'|' -f1)
        local record_type=$(echo "$record" | cut -d'|' -f2)
        local record_ttl=$(echo "$record" | cut -d'|' -f3)
        local record_data=$(echo "$record" | cut -d'|' -f4)

        echo -e "  ${BLUE}$record_type record:${NC} $record_name (TTL: $record_ttl) -> $record_data" >&2

        if [ "$dry_run" = true ]; then
            echo -e "    ${YELLOW}[Preview] Will delete this record${NC}" >&2
            ((deleted_count++))
        else
            # Actually delete
            if gcloud dns record-sets delete "$record_name" \
                --type="$record_type" \
                --zone="$zone" \
                --quiet &>/dev/null; then
                echo -e "    ${GREEN}✓ Successfully deleted${NC}" >&2
                ((deleted_count++))
            else
                echo -e "    ${RED}✗ Deletion failed${NC}" >&2
                success=false
            fi
        fi
    done

    echo -e "  ${GREEN}Processed $deleted_count records${NC}" >&2

    if [ "$success" = true ]; then
        return 0
    else
        return 1
    fi
}

# Verify if records have been deleted
verify_deletion() {
    local zone=$1
    local domain=$2

    echo -e "\n${BLUE}Verifying deletion result...${NC}" >&2

    local search_domain="$domain"
    [[ "$search_domain" != *. ]] && search_domain="${search_domain}."

    local remaining=$(gcloud dns record-sets list \
        --zone="$zone" \
        --filter="name:$search_domain" \
        --format="value(name)" 2>/dev/null)

    if [ -z "$remaining" ]; then
        echo -e "${GREEN}✓ Confirmed all related records have been deleted${NC}" >&2
    else
        echo -e "${YELLOW}⚠ Still related records exist:${NC}" >&2
        echo "$remaining" | while read -r name; do
            echo -e "  - $name" >&2
        done
    fi
}

# ============================================
# Main Program
# ============================================

main() {
    # Parse arguments
    parse_args "$@"

    # Use default Zone if not specified
    ZONE_NAME="${ZONE_NAME:-$DEFAULT_ZONE_NAME}"

    echo -e "${GREEN}========================================${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}GCP Cloud DNS Record Batch Deletion Tool [Preview Mode]${NC}"
    else
        echo -e "${GREEN}GCP Cloud DNS Record Batch Deletion Tool${NC}"
    fi
    echo -e "${GREEN}========================================${NC}"
    echo -e "Project ID: ${BLUE}$PROJECT_ID${NC}"
    echo -e "DNS Zone: ${BLUE}$ZONE_NAME${NC}"
    echo -e "Domain Count: ${BLUE}${#DOMAINS[@]}${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "Mode: ${YELLOW}Preview Mode (will not actually delete)${NC}"
    fi
    echo ""

    # Check dependencies
    check_dependencies

    # Set project
    set_project

    # List all Zones
    list_zones

    # Check if Zone exists
    check_zone_exists "$ZONE_NAME"

    # Statistics variables
    local total_domains=${#DOMAINS[@]}
    local success_count=0
    local fail_count=0
    local total_records_deleted=0

    # Process each domain
    for domain in "${DOMAINS[@]}"; do
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${GREEN}Processing domain: $domain${NC}"
        echo -e "${GREEN}========================================${NC}"

        # Find related records
        local domain_records=()

        if find_related_records "$ZONE_NAME" "$domain" domain_records; then
            # Delete records
            if delete_dns_records "$ZONE_NAME" "$domain" domain_records "$DRY_RUN"; then
                ((success_count++))
                total_records_deleted=$((total_records_deleted + ${#domain_records[@]}))

                # Verify deletion (only in non-preview mode)
                if [ "$DRY_RUN" = false ]; then
                    verify_deletion "$ZONE_NAME" "$domain"
                fi
            else
                ((fail_count++))
            fi
        else
            echo -e "${YELLOW}Domain $domain has no related records in Zone, skipping${NC}"
            ((success_count++))
        fi
    done

    # Display summary
    echo -e "\n${GREEN}========================================${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}Preview Complete${NC}"
    else
        echo -e "${GREEN}Deletion Complete${NC}"
    fi
    echo -e "${GREEN}========================================${NC}"
    echo -e "Total Domains: ${BLUE}$total_domains${NC}"
    echo -e "Successfully Processed: ${GREEN}$success_count${NC}"
    echo -e "Failed: ${RED}$fail_count${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "Records to be deleted: ${YELLOW}$total_records_deleted${NC}"
    else
        echo -e "Records deleted: ${GREEN}$total_records_deleted${NC}"
    fi
    echo -e "${GREEN}========================================${NC}"

    if [ "$DRY_RUN" = true ]; then
        echo -e "\n${YELLOW}This is preview mode, no records were actually deleted${NC}"
        echo -e "${YELLOW}To actually delete, remove the -n parameter and run again${NC}"
    fi
}

# Run main program
main "$@"