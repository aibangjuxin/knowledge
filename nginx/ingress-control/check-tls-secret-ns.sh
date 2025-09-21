#!/bin/bash

# TLS Secrets Namespace Validation Script
# Usage: ./check-tls-secret-ns.sh -n <namespace> [options]

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
NAMESPACE=""
VERBOSE=false
EXPORT_DETAILS=false
OUTPUT_FORMAT="table"

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_success() {
    print_status "$GREEN" "✓ $1"
}

print_error() {
    print_status "$RED" "✗ $1"
}

print_warning() {
    print_status "$YELLOW" "⚠ $1"
}

print_info() {
    print_status "$BLUE" "ℹ $1"
}

print_section() {
    print_status "$CYAN" "▶ $1"
}

# Function to show usage
show_usage() {
    cat << EOF
TLS Secrets Namespace Validation Tool

Usage: $0 -n <namespace> [options]

Options:
    -n, --namespace <name>    Target namespace (required)
    -v, --verbose            Show detailed information for each certificate
    -e, --export-details     Export certificate details to files
    -f, --format <format>    Output format: table, json, csv (default: table)
    -h, --help              Show this help message

Examples:
    $0 -n default
    $0 -n kube-system --verbose
    $0 -n ingress-nginx --export-details --format json
EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -e|--export-details)
                EXPORT_DETAILS=true
                shift
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    if [ -z "$NAMESPACE" ]; then
        print_error "Namespace is required"
        show_usage
        exit 1
    fi
}

# Check if required tools are installed
check_dependencies() {
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    
    if ! command -v jq &> /dev/null && [ "$OUTPUT_FORMAT" = "json" ]; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
}

# Function to check if namespace exists
check_namespace_exists() {
    print_header "Checking Namespace"
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_error "Namespace '$NAMESPACE' not found"
        exit 1
    fi
    
    print_success "Namespace '$NAMESPACE' exists"
}

# Function to get all TLS secrets in namespace
get_tls_secrets() {
    print_header "Discovering TLS Secrets"
    
    # Get all secrets of type kubernetes.io/tls
    TLS_SECRETS=$(kubectl get secrets -n "$NAMESPACE" --field-selector type=kubernetes.io/tls -o jsonpath='{.items[*].metadata.name}')
    
    if [ -z "$TLS_SECRETS" ]; then
        print_warning "No TLS secrets found in namespace '$NAMESPACE'"
        exit 0
    fi
    
    # Convert to array
    read -ra SECRET_ARRAY <<< "$TLS_SECRETS"
    SECRET_COUNT=${#SECRET_ARRAY[@]}
    
    print_success "Found $SECRET_COUNT TLS secret(s): ${SECRET_ARRAY[*]}"
}

# Function to validate a single certificate
validate_single_cert() {
    local secret_name=$1
    local temp_dir=$2
    local tls_crt_file="$temp_dir/${secret_name}_tls.crt"
    local tls_key_file="$temp_dir/${secret_name}_tls.key"
    
    # Initialize result variables
    local cert_key_match="Unknown"
    local cert_valid="Unknown"
    local cert_expires_soon="Unknown"
    local cert_count="0"
    local subject=""
    local issuer=""
    local not_after=""
    local san=""
    
    # Export certificate and key
    if kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$tls_crt_file" 2>/dev/null && \
       kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data.tls\.key}' | base64 -d > "$tls_key_file" 2>/dev/null; then
        
        # Check if files are not empty
        if [ -s "$tls_crt_file" ] && [ -s "$tls_key_file" ]; then
            
            # Validate certificate and key match
            local cert_modulus=$(openssl x509 -noout -modulus -in "$tls_crt_file" 2>/dev/null | openssl md5 2>/dev/null)
            local key_modulus=$(openssl rsa -noout -modulus -in "$tls_key_file" 2>/dev/null | openssl md5 2>/dev/null)
            
            if [ "$cert_modulus" = "$key_modulus" ] && [ -n "$cert_modulus" ]; then
                cert_key_match="✓ Match"
            else
                cert_key_match="✗ Mismatch"
            fi
            
            # Check certificate validity
            if openssl x509 -checkend 0 -noout -in "$tls_crt_file" > /dev/null 2>&1; then
                cert_valid="✓ Valid"
            else
                cert_valid="✗ Expired"
            fi
            
            # Check if certificate expires within 30 days
            if openssl x509 -checkend 2592000 -noout -in "$tls_crt_file" > /dev/null 2>&1; then
                cert_expires_soon="✓ OK"
            else
                cert_expires_soon="⚠ <30 days"
            fi
            
            # Get certificate details
            cert_count=$(grep -c "BEGIN CERTIFICATE" "$tls_crt_file" 2>/dev/null || echo "0")
            subject=$(openssl x509 -noout -subject -in "$tls_crt_file" 2>/dev/null | sed 's/subject=//' || echo "Unknown")
            issuer=$(openssl x509 -noout -issuer -in "$tls_crt_file" 2>/dev/null | sed 's/issuer=//' || echo "Unknown")
            not_after=$(openssl x509 -noout -enddate -in "$tls_crt_file" 2>/dev/null | cut -d= -f2 || echo "Unknown")
            san=$(openssl x509 -noout -text -in "$tls_crt_file" 2>/dev/null | grep -A 1 "Subject Alternative Name" | tail -n 1 | sed 's/^ *//' || echo "None")
            
        else
            cert_key_match="✗ Empty files"
        fi
    else
        cert_key_match="✗ Export failed"
    fi
    
    # Store results in associative arrays (simulated with variables)
    eval "CERT_KEY_MATCH_${secret_name//[-.]/_}='$cert_key_match'"
    eval "CERT_VALID_${secret_name//[-.]/_}='$cert_valid'"
    eval "CERT_EXPIRES_SOON_${secret_name//[-.]/_}='$cert_expires_soon'"
    eval "CERT_COUNT_${secret_name//[-.]/_}='$cert_count'"
    eval "SUBJECT_${secret_name//[-.]/_}='$subject'"
    eval "ISSUER_${secret_name//[-.]/_}='$issuer'"
    eval "NOT_AFTER_${secret_name//[-.]/_}='$not_after'"
    eval "SAN_${secret_name//[-.]/_}='$san'"
}

# Function to display detailed information for a secret
display_detailed_info() {
    local secret_name=$1
    local safe_name=${secret_name//[-.]/_}
    
    print_section "Detailed Information for: $secret_name"
    
    local cert_key_match_var="CERT_KEY_MATCH_${safe_name}"
    local cert_valid_var="CERT_VALID_${safe_name}"
    local cert_expires_soon_var="CERT_EXPIRES_SOON_${safe_name}"
    local cert_count_var="CERT_COUNT_${safe_name}"
    local subject_var="SUBJECT_${safe_name}"
    local issuer_var="ISSUER_${safe_name}"
    local not_after_var="NOT_AFTER_${safe_name}"
    local san_var="SAN_${safe_name}"
    
    echo "  Certificate/Key Match: ${!cert_key_match_var}"
    echo "  Certificate Valid: ${!cert_valid_var}"
    echo "  Expires Soon: ${!cert_expires_soon_var}"
    echo "  Certificate Count: ${!cert_count_var}"
    echo "  Subject: ${!subject_var}"
    echo "  Issuer: ${!issuer_var}"
    echo "  Valid Until: ${!not_after_var}"
    echo "  SAN: ${!san_var}"
    echo ""
}

# Function to generate table output
generate_table_output() {
    print_header "TLS Secrets Validation Summary"
    
    printf "%-25s %-15s %-15s %-15s %-10s\n" "Secret Name" "Cert/Key Match" "Valid" "Expires Soon" "Cert Count"
    printf "%-25s %-15s %-15s %-15s %-10s\n" "$(printf '%*s' 25 | tr ' ' '-')" "$(printf '%*s' 15 | tr ' ' '-')" "$(printf '%*s' 15 | tr ' ' '-')" "$(printf '%*s' 15 | tr ' ' '-')" "$(printf '%*s' 10 | tr ' ' '-')"
    
    for secret in "${SECRET_ARRAY[@]}"; do
        local safe_name=${secret//[-.]/_}
        local cert_key_match_var="CERT_KEY_MATCH_${safe_name}"
        local cert_valid_var="CERT_VALID_${safe_name}"
        local cert_expires_soon_var="CERT_EXPIRES_SOON_${safe_name}"
        local cert_count_var="CERT_COUNT_${safe_name}"
        
        printf "%-25s %-15s %-15s %-15s %-10s\n" \
            "$secret" \
            "${!cert_key_match_var}" \
            "${!cert_valid_var}" \
            "${!cert_expires_soon_var}" \
            "${!cert_count_var}"
    done
}

# Function to generate JSON output
generate_json_output() {
    print_header "TLS Secrets Validation Summary (JSON)"
    
    echo "{"
    echo "  \"namespace\": \"$NAMESPACE\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"total_secrets\": $SECRET_COUNT,"
    echo "  \"secrets\": ["
    
    for i in "${!SECRET_ARRAY[@]}"; do
        local secret="${SECRET_ARRAY[$i]}"
        local safe_name=${secret//[-.]/_}
        local cert_key_match_var="CERT_KEY_MATCH_${safe_name}"
        local cert_valid_var="CERT_VALID_${safe_name}"
        local cert_expires_soon_var="CERT_EXPIRES_SOON_${safe_name}"
        local cert_count_var="CERT_COUNT_${safe_name}"
        local subject_var="SUBJECT_${safe_name}"
        local issuer_var="ISSUER_${safe_name}"
        local not_after_var="NOT_AFTER_${safe_name}"
        local san_var="SAN_${safe_name}"
        
        echo "    {"
        echo "      \"name\": \"$secret\","
        echo "      \"cert_key_match\": \"${!cert_key_match_var}\","
        echo "      \"cert_valid\": \"${!cert_valid_var}\","
        echo "      \"expires_soon\": \"${!cert_expires_soon_var}\","
        echo "      \"cert_count\": \"${!cert_count_var}\","
        echo "      \"subject\": \"${!subject_var}\","
        echo "      \"issuer\": \"${!issuer_var}\","
        echo "      \"valid_until\": \"${!not_after_var}\","
        echo "      \"san\": \"${!san_var}\""
        
        if [ $i -eq $((SECRET_COUNT - 1)) ]; then
            echo "    }"
        else
            echo "    },"
        fi
    done
    
    echo "  ]"
    echo "}"
}

# Function to generate CSV output
generate_csv_output() {
    print_header "TLS Secrets Validation Summary (CSV)"
    
    echo "Secret Name,Cert/Key Match,Valid,Expires Soon,Cert Count,Subject,Issuer,Valid Until,SAN"
    
    for secret in "${SECRET_ARRAY[@]}"; do
        local safe_name=${secret//[-.]/_}
        local cert_key_match_var="CERT_KEY_MATCH_${safe_name}"
        local cert_valid_var="CERT_VALID_${safe_name}"
        local cert_expires_soon_var="CERT_EXPIRES_SOON_${safe_name}"
        local cert_count_var="CERT_COUNT_${safe_name}"
        local subject_var="SUBJECT_${safe_name}"
        local issuer_var="ISSUER_${safe_name}"
        local not_after_var="NOT_AFTER_${safe_name}"
        local san_var="SAN_${safe_name}"
        
        echo "\"$secret\",\"${!cert_key_match_var}\",\"${!cert_valid_var}\",\"${!cert_expires_soon_var}\",\"${!cert_count_var}\",\"${!subject_var}\",\"${!issuer_var}\",\"${!not_after_var}\",\"${!san_var}\""
    done
}

# Function to export certificate details to files
export_certificate_details() {
    if [ "$EXPORT_DETAILS" = true ]; then
        print_header "Exporting Certificate Details"
        
        local export_dir="tls-certs-export-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$export_dir"
        
        for secret in "${SECRET_ARRAY[@]}"; do
            local secret_dir="$export_dir/$secret"
            mkdir -p "$secret_dir"
            
            # Export certificate and key
            kubectl get secret "$secret" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$secret_dir/tls.crt" 2>/dev/null || true
            kubectl get secret "$secret" -n "$NAMESPACE" -o jsonpath='{.data.tls\.key}' | base64 -d > "$secret_dir/tls.key" 2>/dev/null || true
            
            # Generate certificate info
            if [ -s "$secret_dir/tls.crt" ]; then
                openssl x509 -in "$secret_dir/tls.crt" -text -noout > "$secret_dir/cert-info.txt" 2>/dev/null || true
            fi
        done
        
        print_success "Certificate details exported to: $export_dir"
    fi
}

# Function to generate statistics
generate_statistics() {
    print_header "Statistics"
    
    local valid_count=0
    local expired_count=0
    local expires_soon_count=0
    local mismatch_count=0
    
    for secret in "${SECRET_ARRAY[@]}"; do
        local safe_name=${secret//[-.]/_}
        local cert_valid_var="CERT_VALID_${safe_name}"
        local cert_expires_soon_var="CERT_EXPIRES_SOON_${safe_name}"
        local cert_key_match_var="CERT_KEY_MATCH_${safe_name}"
        
        if [[ "${!cert_valid_var}" == *"Valid"* ]]; then
            ((valid_count++))
        elif [[ "${!cert_valid_var}" == *"Expired"* ]]; then
            ((expired_count++))
        fi
        
        if [[ "${!cert_expires_soon_var}" == *"<30 days"* ]]; then
            ((expires_soon_count++))
        fi
        
        if [[ "${!cert_key_match_var}" == *"Mismatch"* ]] || [[ "${!cert_key_match_var}" == *"failed"* ]]; then
            ((mismatch_count++))
        fi
    done
    
    echo "Total TLS Secrets: $SECRET_COUNT"
    echo "Valid Certificates: $valid_count"
    echo "Expired Certificates: $expired_count"
    echo "Expiring Soon (<30 days): $expires_soon_count"
    echo "Certificate/Key Mismatches: $mismatch_count"
    
    if [ $expired_count -gt 0 ] || [ $mismatch_count -gt 0 ]; then
        print_warning "Issues found! Please review the certificates above."
    else
        print_success "All certificates are valid and properly configured."
    fi
}

# Cleanup function
cleanup_and_exit() {
    local exit_code=${1:-0}
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    exit $exit_code
}

# Trap to ensure cleanup on script exit
trap 'cleanup_and_exit' EXIT INT TERM

# Main execution
main() {
    print_header "TLS Secrets Namespace Validation Tool"
    print_info "Checking namespace: $NAMESPACE"
    print_info "Output format: $OUTPUT_FORMAT"
    
    check_dependencies
    check_namespace_exists
    get_tls_secrets
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    
    # Validate each certificate
    print_header "Validating Certificates"
    for secret in "${SECRET_ARRAY[@]}"; do
        print_info "Processing: $secret"
        validate_single_cert "$secret" "$TEMP_DIR"
    done
    
    # Generate output based on format
    case $OUTPUT_FORMAT in
        "table")
            generate_table_output
            ;;
        "json")
            generate_json_output
            ;;
        "csv")
            generate_csv_output
            ;;
        *)
            print_error "Unknown output format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
    
    # Show detailed information if verbose mode is enabled
    if [ "$VERBOSE" = true ]; then
        print_header "Detailed Certificate Information"
        for secret in "${SECRET_ARRAY[@]}"; do
            display_detailed_info "$secret"
        done
    fi
    
    # Export certificate details if requested
    export_certificate_details
    
    # Generate statistics
    generate_statistics
    
    print_success "TLS secrets validation completed for namespace: $NAMESPACE"
}

# Script entry point
parse_arguments "$@"
main