#!/bin/bash

# GCP Cloud DNS Record Batch Management Script
# Purpose: Automatically add or delete DNS records in Cloud DNS Zone
# Supported modes: add (add) / del (delete)

# ============================================
# Configuration Section
# ============================================

# GCP Project ID
PROJECT_ID="your-project-id"

# Default DNS Zone Name
DEFAULT_ZONE_NAME="private-access"

# Domain list to be processed
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
Usage: $(basename $0) <command> [options]

Commands:
  add              Add DNS records to Cloud DNS Zone
  del              Delete DNS records from Cloud DNS Zone
  list             List all DNS records in specified Zone

Options:
  -p PROJECT_ID    Specify GCP Project ID (default: $PROJECT_ID)
  -z ZONE_NAME     Specify DNS Zone Name (default: $DEFAULT_ZONE_NAME)
  -n               Preview mode (only effective in delete mode), only show records to be deleted
  -h               Show this help information

Examples:
  # Add mode
  $(basename $0) add                              # Add records using default configuration
  $(basename $0) add -p my-project -z my-zone     # Specify project and Zone to add

  # Delete mode
  $(basename $0) del                              # Delete records using default configuration
  $(basename $0) del -p my-project -z my-zone     # Specify project and Zone to delete
  $(basename $0) del -n                           # Preview mode (don't actually delete)
  $(basename $0) del -z custom-zone -n            # Preview deletion for specified Zone

  # List records
  $(basename $0) list                             # List all records in default Zone
  $(basename $0) list -z my-zone                  # List all records in specified Zone

Description:
  Add mode: The script resolves domains in the domain list, gets CNAME chains and A records,
           and adds them to the specified Cloud DNS Zone.

  Delete mode: The script queries all records related to the domain list in Cloud DNS Zone,
           including CNAME chains and A records, and deletes them.

EOF
}

# Parse command-line arguments
parse_args() {
    # First parameter must be command
    COMMAND="${1:-}"
    shift 2>/dev/null || true

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

    # Use default Zone if not specified
    ZONE_NAME="${ZONE_NAME:-$DEFAULT_ZONE_NAME}"
}

# Display current configuration
show_config() {
    local mode_desc=""
    case "$COMMAND" in
        add)
            mode_desc="${GREEN}Add Mode${NC}"
            ;;
        del)
            if [ "$DRY_RUN" = true ]; then
                mode_desc="${YELLOW}Delete Mode [Preview]${NC}"
            else
                mode_desc="${RED}Delete Mode${NC}"
            fi
            ;;
        list)
            mode_desc="${BLUE}List Mode${NC}"
            ;;
    esac

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}GCP Cloud DNS Record Management Tool${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Operation Mode: $mode_desc"
    echo -e "Project ID: ${BLUE}$PROJECT_ID${NC}"
    echo -e "DNS Zone: ${BLUE}$ZONE_NAME${NC}"
    echo -e "Domain Count: ${BLUE}${#DOMAINS[@]}${NC}"
    echo ""
}

# Check if required commands exist
check_dependencies() {
    local missing_deps=()

    if ! command -v gcloud &> /dev/null; then
        missing_deps+=(gcloud)
    fi

    case "$COMMAND" in
        add)
            for cmd in host; do
                if ! command -v $cmd &> /dev/null; then
                    missing_deps+=($cmd)
                fi
            done
            ;;
    esac

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

# ============================================
# Add Mode Related Functions
# ============================================

# Resolve domain to get all records
resolve_domain() {
    local domain=$1
    local -n cnames_ref=$2
    local -n a_record_ref=$3

    echo -e "${BLUE}Resolving domain: $domain${NC}"

    # Use host command to resolve
    local host_output=$(host "$domain" 2>&1)

    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}  Warning: Cannot resolve $domain${NC}"
        return 1
    fi

    # Extract CNAME records
    local cname_chain=()
    local current_domain="$domain"

    while true; do
        local cname=$(echo "$host_output" | grep "is an alias for" | awk '{print $NF}' | sed 's/\.$//')

        if [ -z "$cname" ]; then
            break
        fi

        cname_chain+=("$current_domain -> $cname")
        echo -e "  ${GREEN}CNAME:${NC} $current_domain -> $cname"

        current_domain="$cname"
        host_output=$(host "$cname" 2>&1)
    done

    # Extract A record
    local ip_address=$(echo "$host_output" | grep "has address" | awk '{print $NF}' | head -1)

    if [ -n "$ip_address" ]; then
        echo -e "  ${GREEN}A Record:${NC} $current_domain -> $ip_address"
        a_record_ref="$current_domain $ip_address"
    else
        echo -e "${YELLOW}  Warning: No A record found${NC}"
        return 1
    fi

    # Return CNAME chain
    cnames_ref=("${cname_chain[@]}")

    return 0
}

# Add DNS records
add_dns_records() {
    local zone=$1
    local domain=$2
    local -n cnames_array=$3
    local a_record=$4

    echo -e "\n${BLUE}Adding DNS records for $domain to Zone: $zone${NC}" >&2

    local success=true

    # Add CNAME records
    for cname_entry in "${cnames_array[@]}"; do
        local source=$(echo "$cname_entry" | awk '{print $1}')
        local target=$(echo "$cname_entry" | awk '{print $3}')

        # Ensure ends with .
        [[ "$source" != *. ]] && source="${source}."
        [[ "$target" != *. ]] && target="${target}."

        echo -e "  ${BLUE}Adding CNAME:${NC} $source -> $target" >&2

        # Check if record already exists
        if gcloud dns record-sets describe "$source" --type=CNAME --zone="$zone" &>/dev/null; then
            echo -e "  ${YELLOW}Record already exists, skipping${NC}" >&2
        else
            if gcloud dns record-sets create "$source" \
                --rrdatas="$target" \
                --type=CNAME \
                --ttl=300 \
                --zone="$zone" &>/dev/null; then
                echo -e "  ${GREEN}✓ Successfully added CNAME${NC}" >&2
            else
                echo -e "  ${RED}✗ Failed to add CNAME${NC}" >&2
                success=false
            fi
        fi
    done

    # Add A record
    if [ -n "$a_record" ]; then
        local a_domain=$(echo "$a_record" | awk '{print $1}')
        local a_ip=$(echo "$a_record" | awk '{print $2}')

        [[ "$a_domain" != *. ]] && a_domain="${a_domain}."

        echo -e "  ${BLUE}Adding A Record:${NC} $a_domain -> $a_ip" >&2

        # Check if record already exists
        if gcloud dns record-sets describe "$a_domain" --type=A --zone="$zone" &>/dev/null; then
            echo -e "  ${YELLOW}Record already exists, skipping${NC}" >&2
        else
            if gcloud dns record-sets create "$a_domain" \
                --rrdatas="$a_ip" \
                --type=A \
                --ttl=300 \
                --zone="$zone" &>/dev/null; then
                echo -e "  ${GREEN}✓ Successfully added A Record${NC}" >&2
            else
                echo -e "  ${RED}✗ Failed to add A Record${NC}" >&2
                success=false
            fi
        fi
    fi

    if [ "$success" = true ]; then
        return 0
    else
        return 1
    fi
}

# Verify if records were added successfully
verify_add_records() {
    local zone=$1
    local domain=$2

    echo -e "\n${BLUE}Verifying DNS records for $domain...${NC}"

    # Query all records related to this domain
    gcloud dns record-sets list \
        --zone="$zone" \
        --filter="name:$domain" \
        --format="table[box](name, type, ttl, rrdatas)"

    echo ""
}

# ============================================
# Delete Mode Related Functions
# ============================================

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
# List Mode Functions
# ============================================

# List all records in Zone
list_all_records() {
    local zone=$1

    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}All records in Zone '$zone':${NC}"
    echo -e "${GREEN}========================================${NC}"

    gcloud dns record-sets list \
        --zone="$zone" \
        --format="table[box](name, type, ttl, rrdatas)"
}

# ============================================
# Main Program - Add Mode
# ============================================

run_add_mode() {
    # Statistics variables
    local total_domains=${#DOMAINS[@]}
    local success_count=0
    local fail_count=0

    # Process each domain
    for domain in "${DOMAINS[@]}"; do
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${GREEN}Processing domain: $domain${NC}"
        echo -e "${GREEN}========================================${NC}"

        # Resolve domain
        local domain_cnames=()
        local domain_a_record=""

        if resolve_domain "$domain" domain_cnames domain_a_record; then
            # Add DNS records
            if add_dns_records "$ZONE_NAME" "$domain" domain_cnames "$domain_a_record"; then
                ((success_count++))

                # Verify records
                verify_add_records "$ZONE_NAME" "$domain"
            else
                ((fail_count++))
            fi
        else
            ((fail_count++))
        fi
    done

    # Display summary
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Add Complete${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Total Domains: ${BLUE}$total_domains${NC}"
    echo -e "Success: ${GREEN}$success_count${NC}"
    echo -e "Failed: ${RED}$fail_count${NC}"
    echo -e "${GREEN}========================================${NC}"

    # Display all records in the end
    echo -e "\n${BLUE}All records in Zone '$ZONE_NAME':${NC}"
    gcloud dns record-sets list \
        --zone="$ZONE_NAME" \
        --format="table[box](name, type, ttl, rrdatas)"
}

# ============================================
# Main Program - Delete Mode
# ============================================

run_del_mode() {
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

# ============================================
# Main Program - List Mode
# ============================================

run_list_mode() {
    # List all Zones
    list_zones

    # Check if Zone exists
    check_zone_exists "$ZONE_NAME"

    # List all records
    list_all_records "$ZONE_NAME"
}

# ============================================
# Main Program Entry
# ============================================

main() {
    # Parse arguments
    parse_args "$@"

    # Validate command
    case "$COMMAND" in
        add|del|list)
            ;;
        "")
            echo -e "${RED}Error: Missing command parameter${NC}"
            show_help
            exit 1
            ;;
        *)
            echo -e "${RED}Error: Invalid command '$COMMAND'${NC}"
            show_help
            exit 1
            ;;
    esac

    # Display configuration
    show_config

    # Check dependencies
    check_dependencies

    # Set project
    set_project

    # List all Zones
    list_zones

    # Check if Zone exists (list mode also checks, but is handled separately in run_list_mode)
    if [ "$COMMAND" != "list" ]; then
        check_zone_exists "$ZONE_NAME"
    fi

    # Execute corresponding operation based on command
    case "$COMMAND" in
        add)
            run_add_mode
            ;;
        del)
            run_del_mode
            ;;
        list)
            run_list_mode
            ;;
    esac
}

# Run main program
main "$@"