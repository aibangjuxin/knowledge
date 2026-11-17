# Shell Scripts Collection

Generated on: 2026-04-23 15:51:42
Directory: /Users/lex/git/knowledge/nginx/ingress-control

## `check-tls-secret-ns.sh`

```bash
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
```

## `check-tls-secret2.sh`

```bash
#!/bin/bash

# TLS Secret Validation Script
# Usage: ./check-tls-secret.sh <secret-name> <namespace>

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if required tools are installed
check_dependencies() {
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
}

# Function to validate input parameters
validate_input() {
    if [ $# -ne 2 ]; then
        echo "Usage: $0 <secret-name> <namespace>"
        echo "Example: $0 my-tls-secret default"
        exit 1
    fi
    
    SECRET_NAME="$1"
    NAMESPACE="$2"
    
    if [ -z "$SECRET_NAME" ] || [ -z "$NAMESPACE" ]; then
        print_error "Secret name and namespace cannot be empty"
        exit 1
    fi
}

# Function to check if secret exists and get its type
check_secret_exists() {
    print_header "Checking Secret Existence and Type"
    
    if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
        print_error "Secret '$SECRET_NAME' not found in namespace '$NAMESPACE'"
        exit 1
    fi
    
    print_success "Secret '$SECRET_NAME' exists in namespace '$NAMESPACE'"
    
    # Get secret type
    SECRET_TYPE=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.type}')
    
    if [ "$SECRET_TYPE" = "kubernetes.io/tls" ]; then
        print_success "Secret type is correct: $SECRET_TYPE"
    else
        print_error "Invalid secret type: $SECRET_TYPE (expected: kubernetes.io/tls)"
        exit 1
    fi
}

# Function to export certificate and key from secret
export_tls_files() {
    print_header "Exporting TLS Files"
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    TLS_CRT_FILE="$TEMP_DIR/tls.crt"
    TLS_KEY_FILE="$TEMP_DIR/tls.key"
    
    # Export certificate
    if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TLS_CRT_FILE" 2>/dev/null; then
        print_success "Certificate exported to: $TLS_CRT_FILE"
    else
        print_error "Failed to export tls.crt from secret"
        cleanup_and_exit 1
    fi
    
    # Export private key
    if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.key}' | base64 -d > "$TLS_KEY_FILE" 2>/dev/null; then
        print_success "Private key exported to: $TLS_KEY_FILE"
    else
        print_error "Failed to export tls.key from secret"
        cleanup_and_exit 1
    fi
    
    # Check if files are not empty
    if [ ! -s "$TLS_CRT_FILE" ]; then
        print_error "Certificate file is empty"
        cleanup_and_exit 1
    fi
    
    if [ ! -s "$TLS_KEY_FILE" ]; then
        print_error "Private key file is empty"
        cleanup_and_exit 1
    fi
}

# Function to validate certificate and key consistency
validate_cert_key_match() {
    print_header "Validating Certificate and Key Consistency"
    
    # Get certificate modulus
    CERT_MODULUS=$(openssl x509 -noout -modulus -in "$TLS_CRT_FILE" 2>/dev/null | openssl md5)
    if [ $? -ne 0 ]; then
        print_error "Failed to extract certificate modulus"
        cleanup_and_exit 1
    fi
    
    # Get private key modulus
    KEY_MODULUS=$(openssl rsa -noout -modulus -in "$TLS_KEY_FILE" 2>/dev/null | openssl md5)
    if [ $? -ne 0 ]; then
        print_error "Failed to extract private key modulus"
        cleanup_and_exit 1
    fi
    
    # Compare moduli
    if [ "$CERT_MODULUS" = "$KEY_MODULUS" ]; then
        print_success "Certificate and private key match"
    else
        print_error "Certificate and private key do not match"
        print_info "Certificate modulus: $CERT_MODULUS"
        print_info "Private key modulus: $KEY_MODULUS"
        cleanup_and_exit 1
    fi
}

# Function to display certificate information
display_cert_info() {
    print_header "Certificate Information"
    
    # Basic certificate info
    print_info "Certificate Details:"
    openssl x509 -in "$TLS_CRT_FILE" -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:|IP Address:)" | while read line; do
        echo "  $line"
    done
    
    # Subject and Issuer
    SUBJECT=$(openssl x509 -noout -subject -in "$TLS_CRT_FILE" | sed 's/subject=//')
    ISSUER=$(openssl x509 -noout -issuer -in "$TLS_CRT_FILE" | sed 's/issuer=//')
    
    echo ""
    print_info "Subject: $SUBJECT"
    print_info "Issuer: $ISSUER"
    
    # Validity period
    NOT_BEFORE=$(openssl x509 -noout -startdate -in "$TLS_CRT_FILE" | cut -d= -f2)
    NOT_AFTER=$(openssl x509 -noout -enddate -in "$TLS_CRT_FILE" | cut -d= -f2)
    
    echo ""
    print_info "Valid From: $NOT_BEFORE"
    print_info "Valid Until: $NOT_AFTER"
    
    # Check if certificate is expired
    if openssl x509 -checkend 0 -noout -in "$TLS_CRT_FILE" > /dev/null; then
        print_success "Certificate is currently valid"
    else
        print_error "Certificate has expired"
    fi
    
    # Check if certificate expires soon (30 days)
    if openssl x509 -checkend 2592000 -noout -in "$TLS_CRT_FILE" > /dev/null; then
        print_success "Certificate is not expiring within 30 days"
    else
        print_warning "Certificate expires within 30 days"
    fi
    
    # Extract Subject Alternative Names
    echo ""
    print_info "Subject Alternative Names:"
    SAN=$(openssl x509 -noout -text -in "$TLS_CRT_FILE" | grep -A 1 "Subject Alternative Name" | tail -n 1 | sed 's/^ *//')
    if [ -n "$SAN" ]; then
        echo "  $SAN"
    else
        print_warning "No Subject Alternative Names found"
    fi
}

# Function to check certificate chain
check_cert_chain() {
    print_header "Certificate Chain Analysis"
    
    # Count certificates in the file
    CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$TLS_CRT_FILE")
    
    print_info "Number of certificates in chain: $CERT_COUNT"
    
    if [ "$CERT_COUNT" -eq 1 ]; then
        print_warning "Only one certificate found (no intermediate certificates)"
    else
        print_success "Certificate chain contains $CERT_COUNT certificates"
        
        # Extract and display each certificate in the chain
        awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$TLS_CRT_FILE" | \
        awk -v RS="-----END CERTIFICATE-----" -v ORS="-----END CERTIFICATE-----\n" '{
            if (NF) {
                print $0
                print ""
            }
        }' | while IFS= read -r cert_block; do
            if [ -n "$cert_block" ]; then
                echo "$cert_block" | openssl x509 -noout -subject -issuer 2>/dev/null | while read line; do
                    echo "  $line"
                done
                echo ""
            fi
        done
    fi
    
    # Verify certificate chain
    if openssl verify -CAfile "$TLS_CRT_FILE" "$TLS_CRT_FILE" &> /dev/null; then
        print_success "Certificate chain verification passed"
    else
        print_warning "Certificate chain verification failed (this might be normal if intermediate CAs are not included)"
    fi
}

# Function to generate summary table
generate_summary() {
    print_header "Validation Summary"
    
    echo "| Check | Status | Details |"
    echo "|-------|--------|---------|"
    echo "| Secret Exists | ✓ Pass | Found in namespace $NAMESPACE |"
    echo "| Secret Type | ✓ Pass | kubernetes.io/tls |"
    echo "| Cert/Key Match | ✓ Pass | Modulus validation successful |"
    echo "| Certificate Validity | $(if openssl x509 -checkend 0 -noout -in "$TLS_CRT_FILE" > /dev/null; then echo "✓ Pass"; else echo "✗ Fail"; fi) | $(if openssl x509 -checkend 0 -noout -in "$TLS_CRT_FILE" > /dev/null; then echo "Currently valid"; else echo "Expired"; fi) |"
    echo "| Certificate Chain | $(if [ "$CERT_COUNT" -gt 1 ]; then echo "✓ Pass"; else echo "⚠ Warning"; fi) | $CERT_COUNT certificate(s) in chain |"
}

# Cleanup function
cleanup_and_exit() {
    local exit_code=${1:-0}
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_info "Temporary files cleaned up"
    fi
    exit $exit_code
}

# Trap to ensure cleanup on script exit
trap 'cleanup_and_exit' EXIT INT TERM

# Main execution
main() {
    print_header "TLS Secret Validation Tool"
    print_info "Checking TLS secret: $SECRET_NAME in namespace: $NAMESPACE"
    
    check_dependencies
    check_secret_exists
    export_tls_files
    validate_cert_key_match
    display_cert_info
    check_cert_chain
    generate_summary
    
    print_success "TLS secret validation completed successfully"
}

# Script entry point
validate_input "$@"
main
```

## `check-tls-secret.sh`

```bash
#!/bin/bash
# 用法: ./check-tls-secret.sh <secret-name> <namespace>

set -e

SECRET_NAME=$1
NAMESPACE=$2

if [ -z "$SECRET_NAME" ] || [ -z "$NAMESPACE" ]; then
  echo "用法: $0 <secret-name> <namespace>"
  exit 1
fi

echo "🔍 检查 Secret: $SECRET_NAME (namespace: $NAMESPACE)"
echo "------------------------------------------------------"

# 1. 确认 Secret 类型
SECRET_TYPE=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.type}')
if [ "$SECRET_TYPE" != "kubernetes.io/tls" ]; then
  echo "❌ Secret 类型错误: $SECRET_TYPE (必须是 kubernetes.io/tls)"
  exit 1
else
  echo "✅ Secret 类型正确: $SECRET_TYPE"
fi

# 2. 导出证书和私钥
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/tls.crt
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/tls.key

# 3. 校验证书和私钥是否匹配
CRT_MD5=$(openssl x509 -in /tmp/tls.crt -noout -modulus | openssl md5)
KEY_MD5=$(openssl rsa -in /tmp/tls.key -noout -modulus | openssl md5)

if [ "$CRT_MD5" != "$KEY_MD5" ]; then
  echo "❌ 证书和私钥不匹配"
  echo "CRT: $CRT_MD5"
  echo "KEY: $KEY_MD5"
  exit 1
else
  echo "✅ 证书和私钥匹配"
fi

# 4. 显示证书基本信息
echo "------------------------------------------------------"
echo "📜 证书信息:"
openssl x509 -in /tmp/tls.crt -noout -subject -issuer -dates -ext subjectAltName || true

# 5. 检查是否包含中间证书
CHAIN_COUNT=$(grep -c "END CERTIFICATE" /tmp/tls.crt)
if [ "$CHAIN_COUNT" -gt 1 ]; then
  echo "✅ 证书链完整, 包含 $CHAIN_COUNT 个证书"
else
  echo "⚠️ 证书链可能不完整, 仅检测到 1 个证书"
  echo "   如果使用的是 CA 签发的证书, 请确认已包含中间证书"
fi

echo "------------------------------------------------------"
echo "🔎 检查完成"
```

