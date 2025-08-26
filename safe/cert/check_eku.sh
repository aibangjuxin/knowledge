#!/bin/bash

# check_eku.sh - Check Extended Key Usage (EKU) in certificates
# Usage:
#   ./check_eku.sh server.crt
#   ./check_eku.sh your.domain.com:443
#   ./check_eku.sh certs/*.crt
# Note: openssl s_client gets raw certificate data (PEM format), which is Base64-encoded binary data.
# To read specific certificate information (like EKU), you must first parse it with openssl x509 -text into human-readable format.

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Help information
show_help() {
    echo "Usage: $0 [options] <certificate_file_or_domain:port>"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --verbose  Verbose output"
    echo "  -d, --debug    Debug mode (show raw openssl output)"
    echo ""
    echo "Examples:"
    echo "  $0 server.crt                    # Check local certificate file"
    echo "  $0 example.com:443               # Check online certificate"
    echo "  $0 certs/*.crt                   # Batch check certificate files"
    echo ""
}

# Check dependencies
check_dependencies() {
    if ! command -v openssl &> /dev/null; then
        echo -e "${RED}Error: openssl is required but not installed${NC}"
        exit 1
    fi
}

# Parse EKU
parse_eku() {
    local eku_line="$1"
    local verbose="$2"
    
    echo -e "${BLUE}Extended Key Usage:${NC}"
    
    # Check common EKU types
    local has_server_auth=false
    local has_client_auth=false
    local has_code_signing=false
    local has_email_protection=false
    
    if echo "$eku_line" | grep -q "TLS Web Server Authentication\|serverAuth"; then
        echo -e "  ${GREEN}✓ Server Authentication (TLS Web Server)${NC}"
        has_server_auth=true
    fi
    
    if echo "$eku_line" | grep -q "TLS Web Client Authentication\|clientAuth"; then
        echo -e "  ${GREEN}✓ Client Authentication (TLS Web Client)${NC}"
        has_client_auth=true
    fi
    
    if echo "$eku_line" | grep -q "Code Signing\|codeSigning"; then
        echo -e "  ${GREEN}✓ Code Signing${NC}"
        has_code_signing=true
    fi
    
    if echo "$eku_line" | grep -q "E-mail Protection\|emailProtection"; then
        echo -e "  ${GREEN}✓ Email Protection${NC}"
        has_email_protection=true
    fi
    
    # Show raw EKU information (if verbose mode)
    if [ "$verbose" = true ]; then
        echo -e "${YELLOW}Raw EKU Information:${NC}"
        echo "$eku_line" | sed 's/^/  /'
    fi
    
    # Digicert change warning
    if [ "$has_client_auth" = true ]; then
        echo -e "${YELLOW}⚠️  Warning: This certificate contains Client Authentication EKU${NC}"
        echo -e "${YELLOW}   From October 1st, 2025, Digicert new certificates will no longer include this EKU${NC}"
    fi
    
    return 0
}

# Check certificate file
check_cert_file() {
    local cert_file="$1"
    local verbose="$2"
    
    if [ ! -f "$cert_file" ]; then
        echo -e "${RED}Error: File '$cert_file' does not exist${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Checking certificate file: $cert_file${NC}"
    echo "----------------------------------------"
    
    # Get basic certificate information
    local subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//')
    local issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | sed 's/issuer=//')
    local not_after=$(openssl x509 -in "$cert_file" -noout -dates 2>/dev/null | grep notAfter | sed 's/notAfter=//')
    
    echo -e "${BLUE}Subject:${NC} $subject"
    echo -e "${BLUE}Issuer:${NC} $issuer"
    echo -e "${BLUE}Expires:${NC} $not_after"
    echo ""
    
    # Get EKU information
    local eku_info=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A 10 "X509v3 Extended Key Usage" | grep -v "X509v3 Extended Key Usage" | head -1 | xargs)
    
    if [ -n "$eku_info" ]; then
        parse_eku "$eku_info" "$verbose"
    else
        echo -e "${RED}Extended Key Usage information not found${NC}"
    fi
    
    echo ""
}

# Check online certificate
check_online_cert() {
    local target="$1"
    local verbose="$2"
    local debug="$3"
    
    # Parse hostname and port
    local host=$(echo "$target" | cut -d: -f1)
    local port=$(echo "$target" | cut -d: -f2)
    
    if [ "$port" = "$host" ]; then
        port=443
    fi
    
    echo -e "${BLUE}Checking online certificate: $host:$port${NC}"
    echo "----------------------------------------"
    
    # Test connection
    if ! echo | openssl s_client -connect "$host:$port" -servername "$host" >/dev/null 2>&1; then
        echo -e "${RED}Error: Cannot connect to $host:$port${NC}"
        return 1
    fi
    
    # Get certificate information - using more reliable method
    local subject=$(echo | openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//')
    local issuer=$(echo | openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//')
    local not_after=$(echo | openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | grep notAfter | sed 's/notAfter=//')
    
    echo -e "${BLUE}Subject:${NC} $subject"
    echo -e "${BLUE}Issuer:${NC} $issuer"
    echo -e "${BLUE}Expires:${NC} $not_after"
    echo ""
    
    # Get EKU information - using more precise method
    local eku_raw=$(echo | openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -text -noout 2>/dev/null | grep -A 3 "X509v3 Extended Key Usage")
    local eku_info=$(echo "$eku_raw" | grep -v "X509v3 Extended Key Usage" | grep -v "X509v3" | head -1 | xargs)
    
    # Debug mode shows raw output
    if [ "$debug" = true ]; then
        echo -e "${YELLOW}Debug Info - Raw EKU Output:${NC}"
        echo "$eku_raw"
        echo -e "${YELLOW}Debug Info - Full Certificate Text (first 50 lines):${NC}"
        echo | openssl s_client -connect "$host:$port" -servername "$host" 2>/dev/null | openssl x509 -text -noout 2>/dev/null | head -50
        echo ""
    fi
    
    if [ -n "$eku_info" ]; then
        parse_eku "$eku_info" "$verbose"
    else
        echo -e "${RED}Extended Key Usage information not found${NC}"
        if [ "$debug" != true ]; then
            echo -e "${YELLOW}Tip: Use -d option to see debug information${NC}"
        fi
    fi
    
    echo ""
}

# Main function
main() {
    local verbose=false
    local debug=false
    local targets=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -d|--debug)
                debug=true
                shift
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
            *)
                targets+=("$1")
                shift
                ;;
        esac
    done
    
    # Check dependencies
    check_dependencies
    
    # Check if targets are provided
    if [ ${#targets[@]} -eq 0 ]; then
        echo -e "${RED}Error: Please specify certificate file or domain name${NC}"
        show_help
        exit 1
    fi
    
    # Process each target
    for target in "${targets[@]}"; do
        if [[ "$target" == *":"* ]] || [[ "$target" =~ ^[a-zA-Z0-9.-]+$ ]]; then
            # Looks like a domain name
            check_online_cert "$target" "$verbose" "$debug"
        else
            # Looks like a file
            check_cert_file "$target" "$verbose"
        fi
    done
}

# Run main function
main "$@"