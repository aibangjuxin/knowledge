#!/bin/bash

################################################################################
# Script: verify-trust-configs.sh
# Description: Verify GCP Certificate Manager Trust Configs and extract
#              detailed certificate information including expiration dates
# Usage: ./verify-trust-configs.sh [--project PROJECT_ID] [--location LOCATION]
# Author: Auto-generated
# Created: 2026-01-23
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configurations
DEFAULT_LOCATION="global"
PROJECT_ID=""
LOCATION=""

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "\n${CYAN}================================${NC}" >&2
    echo -e "${CYAN}$1${NC}" >&2
    echo -e "${CYAN}================================${NC}\n" >&2
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Verify GCP Certificate Manager Trust Configs and extract detailed certificate information.

OPTIONS:
    --project PROJECT_ID    GCP Project ID (optional, uses default if not specified)
    --location LOCATION     Location of trust configs (default: global)
    -h, --help             Show this help message

EXAMPLES:
    # Use default project and global location
    $0

    # Specify project and location
    $0 --project my-project --location global

    # Get help
    $0 --help

EOF
    exit 0
}

# Parse certificate details from PEM content
parse_certificate_info() {
    local cert_pem="$1"
    local cert_name="$2"
    
    echo -e "\n${YELLOW}  Certificate: ${cert_name}${NC}" >&2
    echo "  -------------------------------------------" >&2
    
    # Create temporary file for certificate
    local temp_cert=$(mktemp)
    echo "$cert_pem" > "$temp_cert"
    
    # Extract Subject
    local subject=$(openssl x509 -in "$temp_cert" -noout -subject 2>/dev/null | sed 's/subject=//')
    echo "  Subject: $subject" >&2
    
    # Extract Issuer
    local issuer=$(openssl x509 -in "$temp_cert" -noout -issuer 2>/dev/null | sed 's/issuer=//')
    echo "  Issuer: $issuer" >&2
    
    # Extract Serial Number
    local serial=$(openssl x509 -in "$temp_cert" -noout -serial 2>/dev/null | sed 's/serial=//')
    echo "  Serial: $serial" >&2
    
    # Extract validity dates
    local not_before=$(openssl x509 -in "$temp_cert" -noout -startdate 2>/dev/null | sed 's/notBefore=//')
    local not_after=$(openssl x509 -in "$temp_cert" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    
    echo "  Valid From: $not_before" >&2
    echo "  Valid Until: $not_after" >&2
    
    # Calculate days until expiration
    # Try GNU date first (Linux/GCP Cloud Shell), then BSD date (macOS)
    local expiry_epoch=0
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        expiry_epoch=$(date -d "$not_after" "+%s" 2>/dev/null || echo "0")
    else
        # BSD date (macOS)
        expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$not_after" "+%s" 2>/dev/null || echo "0")
    fi
    
    local current_epoch=$(date "+%s")
    local days_remaining=$(( ($expiry_epoch - $current_epoch) / 86400 ))
    
    if [ "$expiry_epoch" -eq 0 ]; then
        echo -e "  ${YELLOW}Days Remaining: Unable to calculate (date parsing failed)${NC}" >&2
    elif [ "$days_remaining" -gt 0 ]; then
        if [ "$days_remaining" -lt 30 ]; then
            echo -e "  ${RED}Days Remaining: $days_remaining (EXPIRING SOON!)${NC}" >&2
        elif [ "$days_remaining" -lt 90 ]; then
            echo -e "  ${YELLOW}Days Remaining: $days_remaining (WARNING)${NC}" >&2
        else
            echo -e "  ${GREEN}Days Remaining: $days_remaining${NC}" >&2
        fi
    else
        echo -e "  ${RED}Days Remaining: $days_remaining (EXPIRED!)${NC}" >&2
    fi
    
    # Extract fingerprints
    local fingerprint_sha256=$(openssl x509 -in "$temp_cert" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//')
    local fingerprint_sha1=$(openssl x509 -in "$temp_cert" -noout -fingerprint -sha1 2>/dev/null | sed 's/.*=//')
    
    echo "  SHA256 Fingerprint: $fingerprint_sha256" >&2
    echo "  SHA1 Fingerprint: $fingerprint_sha1" >&2
    
    # Extract key information
    local key_algo=$(openssl x509 -in "$temp_cert" -noout -text 2>/dev/null | grep "Public Key Algorithm" | sed 's/.*: //')
    echo "  Public Key Algorithm: $key_algo" >&2
    
    # Extract SAN (Subject Alternative Names) if present
    local san=$(openssl x509 -in "$temp_cert" -noout -ext subjectAltName 2>/dev/null | grep -v "X509v3")
    if [ -n "$san" ]; then
        echo "  Subject Alternative Names: $san" >&2
    fi
    
    # Cleanup
    rm -f "$temp_cert"
    echo "  -------------------------------------------" >&2
}

################################################################################
# Main Functions
################################################################################

# Get project ID
get_project_id() {
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            print_error "No project ID specified and no default project configured"
            exit 1
        fi
    fi
    print_info "Using Project: $PROJECT_ID"
}

# List all trust configs
list_trust_configs() {
    print_header "Listing Trust Configs in ${LOCATION}"
    
    local trust_configs=$(gcloud certificate-manager trust-configs list \
        --location="$LOCATION" \
        --project="$PROJECT_ID" \
        --format="value(name)" 2>/dev/null)
    
    if [ -z "$trust_configs" ]; then
        print_warning "No trust configs found in location: $LOCATION"
        return 1
    fi
    
    # Extract short names from full resource paths
    # Format: projects/PROJECT/locations/LOCATION/trustConfigs/NAME -> NAME
    echo "$trust_configs" | while read -r full_name; do
        basename "$full_name"
    done
    
    return 0
}

# Get detailed information about a trust config
describe_trust_config() {
    local trust_config_name="$1"
    
    print_header "Trust Config: ${trust_config_name}"
    
    # Get full details in YAML format
    local config_details=$(gcloud certificate-manager trust-configs describe "$trust_config_name" \
        --location="$LOCATION" \
        --project="$PROJECT_ID" \
        --format=yaml 2>/dev/null)
    
    if [ -z "$config_details" ]; then
        print_error "Failed to get details for trust config: $trust_config_name"
        return 1
    fi
    
    # Display basic information
    echo "$config_details" | grep -E "^(name|createTime|updateTime|description):" >&2 || true
    
    # Get JSON format for easier parsing
    local config_json=$(gcloud certificate-manager trust-configs describe "$trust_config_name" \
        --location="$LOCATION" \
        --project="$PROJECT_ID" \
        --format=json 2>/dev/null)
    
    # Extract and parse trust anchors
    echo -e "\n${GREEN}Trust Anchors (Root CAs):${NC}" >&2
    local trust_anchors=$(echo "$config_json" | jq -r '.trustStores[0].trustAnchors[]? | @base64' 2>/dev/null)
    
    if [ -n "$trust_anchors" ]; then
        local anchor_count=0
        while IFS= read -r anchor_b64; do
            if [ -n "$anchor_b64" ]; then
                anchor_count=$((anchor_count + 1))
                local anchor=$(echo "$anchor_b64" | base64 -d 2>/dev/null)
                local pem_cert=$(echo "$anchor" | jq -r '.pemCertificate' 2>/dev/null)
                
                if [ -n "$pem_cert" ] && [ "$pem_cert" != "null" ]; then
                    parse_certificate_info "$pem_cert" "Trust Anchor #${anchor_count}"
                fi
            fi
        done <<< "$trust_anchors"
        
        if [ "$anchor_count" -eq 0 ]; then
            print_warning "  No trust anchors found"
        fi
    else
        print_warning "  No trust anchors configured"
    fi
    
    # Extract and parse intermediate CAs
    echo -e "\n${GREEN}Intermediate CAs:${NC}" >&2
    local intermediate_cas=$(echo "$config_json" | jq -r '.trustStores[0].intermediateCas[]? | @base64' 2>/dev/null)
    
    if [ -n "$intermediate_cas" ]; then
        local intermediate_count=0
        while IFS= read -r intermediate_b64; do
            if [ -n "$intermediate_b64" ]; then
                intermediate_count=$((intermediate_count + 1))
                local intermediate=$(echo "$intermediate_b64" | base64 -d 2>/dev/null)
                local pem_cert=$(echo "$intermediate" | jq -r '.pemCertificate' 2>/dev/null)
                
                if [ -n "$pem_cert" ] && [ "$pem_cert" != "null" ]; then
                    parse_certificate_info "$pem_cert" "Intermediate CA #${intermediate_count}"
                fi
            fi
        done <<< "$intermediate_cas"
        
        if [ "$intermediate_count" -eq 0 ]; then
            print_warning "  No intermediate CAs found"
        fi
    else
        print_info "  No intermediate CAs configured"
    fi
    
    # Extract allowlisted certificates if any
    echo -e "\n${GREEN}Allowlisted Certificates:${NC}" >&2
    local allowlisted=$(echo "$config_json" | jq -r '.allowlistedCertificates[]? | @base64' 2>/dev/null)
    
    if [ -n "$allowlisted" ]; then
        local allowlist_count=0
        while IFS= read -r allowlist_b64; do
            if [ -n "$allowlist_b64" ]; then
                allowlist_count=$((allowlist_count + 1))
                local allowlist=$(echo "$allowlist_b64" | base64 -d 2>/dev/null)
                local pem_cert=$(echo "$allowlist" | jq -r '.pemCertificate' 2>/dev/null)
                
                if [ -n "$pem_cert" ] && [ "$pem_cert" != "null" ]; then
                    parse_certificate_info "$pem_cert" "Allowlisted Certificate #${allowlist_count}"
                fi
            fi
        done <<< "$allowlisted"
        
        if [ "$allowlist_count" -eq 0 ]; then
            print_info "  No allowlisted certificates"
        fi
    else
        print_info "  No allowlisted certificates configured"
    fi
    
    echo "" >&2
}

# Generate summary report
generate_summary() {
    local trust_configs="$1"
    local total_count=$(echo "$trust_configs" | wc -l | tr -d ' ')
    
    print_header "Summary Report"
    echo "Project: $PROJECT_ID" >&2
    echo "Location: $LOCATION" >&2
    echo "Total Trust Configs: $total_count" >&2
    echo "" >&2
    
    print_info "Trust Config Names:"
    echo "$trust_configs" | while read -r tc_name; do
        echo "  - $tc_name" >&2
    done
}

# Export trust config to file
export_trust_config() {
    local trust_config_name="$1"
    local output_dir="./trust-configs-export"
    
    mkdir -p "$output_dir"
    
    local output_file="${output_dir}/${trust_config_name}-$(date +%Y%m%d-%H%M%S).yaml"
    
    gcloud certificate-manager trust-configs describe "$trust_config_name" \
        --location="$LOCATION" \
        --project="$PROJECT_ID" \
        --format=yaml > "$output_file" 2>/dev/null
    
    print_success "Exported to: $output_file"
}

################################################################################
# Main Execution
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project)
                PROJECT_ID="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Set default location if not specified
    if [ -z "$LOCATION" ]; then
        LOCATION="$DEFAULT_LOCATION"
    fi
    
    # Get project ID
    get_project_id
    
    # Check required commands
    for cmd in gcloud jq openssl; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
    
    # List all trust configs
    print_info "Fetching trust configs..."
    local trust_configs=$(list_trust_configs)
    
    if [ $? -ne 0 ]; then
        exit 0
    fi
    
    # Process each trust config
    while IFS= read -r trust_config_name; do
        if [ -n "$trust_config_name" ]; then
            describe_trust_config "$trust_config_name"
            
            # Export configuration
            export_trust_config "$trust_config_name"
        fi
    done <<< "$trust_configs"
    
    # Generate summary
    generate_summary "$trust_configs"
    
    print_success "Verification completed!"
}

# Run main function
main "$@"
