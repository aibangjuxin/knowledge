#!/bin/bash

# GCP Cloud DNS Record Batch Addition Script
# Purpose: Automatically resolve domains and add CNAME and A records to the specified Cloud DNS Zone

# ============================================
# Configuration Section
# ============================================

# GCP Project ID
PROJECT_ID="your-project-id"

# Default DNS Zone Name
DEFAULT_ZONE_NAME="private-access"

# Domain list to be added
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
  -h               Show this help information

Examples:
  $(basename $0)                                    # Use default configuration
  $(basename $0) -p my-project -z my-zone          # Specify project and Zone
  $(basename $0) -z custom-zone                    # Specify Zone only

Description:
  The script automatically resolves all domains in the domain list, extracts CNAME and A records,
  and adds them to the specified Cloud DNS Zone.

EOF
}

# Parse command-line arguments
parse_args() {
    while getopts "p:z:h" opt; do
        case $opt in
            p)
                PROJECT_ID="$OPTARG"
                ;;
            z)
                ZONE_NAME="$OPTARG"
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

    for cmd in gcloud host; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done

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
verify_records() {
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
# Main Program
# ============================================

main() {
    # Parse arguments
    parse_args "$@"

    # Use default Zone if not specified
    ZONE_NAME="${ZONE_NAME:-$DEFAULT_ZONE_NAME}"

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}GCP Cloud DNS Record Batch Addition Tool${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Project ID: ${BLUE}$PROJECT_ID${NC}"
    echo -e "DNS Zone: ${BLUE}$ZONE_NAME${NC}"
    echo -e "Domain Count: ${BLUE}${#DOMAINS[@]}${NC}"
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
                verify_records "$ZONE_NAME" "$domain"
            else
                ((fail_count++))
            fi
        else
            ((fail_count++))
        fi
    done

    # Display summary
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Processing Complete${NC}"
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

# Run main program
main "$@"