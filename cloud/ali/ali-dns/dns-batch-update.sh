#!/bin/bash

# DNS Batch Update Script
# Usage: ./dns-batch-update.sh <dns_list_file> [mode] [environment]
# Format of dns_list_file: record_name record_values (one per line)

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/dns-config.sh"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    API_BASE_URL="$DNS_API_BASE_URL"
    TOKEN="$DNS_TOKEN"
    DOMAIN_NAME="$DNS_DOMAIN_NAME"
else
    # Fallback configuration
    API_BASE_URL="https://domain/api/v1"
    TOKEN="abcdef"
    DOMAIN_NAME="aliyun.cloud.cn.aibang"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to add DNS record
add_dns_record() {
    local record_name=$1
    local record_value=$2
    
    print_status $YELLOW "Adding DNS record: ${record_name} -> ${record_value}"
    
    response=$(curl -s -X POST \
        "${API_BASE_URL}/add-global-zone-record" \
        -H "accept: application/json" \
        -H "token: ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_name\": \"${DOMAIN_NAME}\",
            \"record_name\": \"${record_name}\",
            \"record_values\": \"${record_value}\"
        }")
    
    if [ $? -eq 0 ]; then
        print_status $GREEN "✓ Successfully added: ${record_name}.${DOMAIN_NAME} -> ${record_value}"
    else
        print_status $RED "✗ Failed to add: ${record_name}"
        echo "Response: $response"
    fi
}

# Function to update DNS record
update_dns_record() {
    local record_name=$1
    local record_value=$2
    
    print_status $YELLOW "Updating DNS record: ${record_name} -> ${record_value}"
    
    response=$(curl -s -X POST \
        "${API_BASE_URL}/update-global-zone-record" \
        -H "accept: application/json" \
        -H "token: ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_name\": \"${DOMAIN_NAME}\",
            \"record_name\": \"${record_name}\",
            \"record_values\": \"${record_value}\"
        }")
    
    if [ $? -eq 0 ]; then
        print_status $GREEN "✓ Successfully updated: ${record_name}.${DOMAIN_NAME} -> ${record_value}"
    else
        print_status $RED "✗ Failed to update: ${record_name}"
        echo "Response: $response"
    fi
}

# Function to process DNS list
process_dns_list() {
    local file=$1
    local mode=$2
    
    if [ ! -f "$file" ]; then
        print_status $RED "Error: File '$file' not found!"
        exit 1
    fi
    
    print_status $YELLOW "Processing DNS records from: $file"
    print_status $YELLOW "Mode: $mode"
    echo
    
    while IFS=' ' read -r record_name record_value || [ -n "$record_name" ]; do
        # Skip empty lines and comments
        if [[ -z "$record_name" || "$record_name" =~ ^#.* ]]; then
            continue
        fi
        
        if [ -z "$record_value" ]; then
            print_status $RED "Warning: Missing record value for '$record_name', skipping..."
            continue
        fi
        
        if [ "$mode" = "add" ]; then
            add_dns_record "$record_name" "$record_value"
        elif [ "$mode" = "update" ]; then
            update_dns_record "$record_name" "$record_value"
        fi
        
        # Small delay to avoid overwhelming the API
        sleep 0.5
    done < "$file"
}

# Main script
main() {
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <dns_list_file> [mode] [environment]"
        echo "  dns_list_file: File containing DNS records (format: record_name record_value)"
        echo "  mode: 'add' or 'update' (default: add)"
        echo "  environment: Set DNS_ENV before running (development, staging, production)"
        echo
        echo "Examples:"
        echo "  $0 dns_records.txt add"
        echo "  $0 dns_records.txt update"
        echo "  DNS_ENV=development $0 dns_records.txt add"
        exit 1
    fi
    
    local dns_file=$1
    local mode=${2:-add}
    
    if [[ "$mode" != "add" && "$mode" != "update" ]]; then
        print_status $RED "Error: Mode must be 'add' or 'update'"
        exit 1
    fi
    
    print_status $GREEN "=== DNS Batch Update Script ==="
    print_status $YELLOW "Domain: $DOMAIN_NAME"
    print_status $YELLOW "API Base URL: $API_BASE_URL"
    echo
    
    process_dns_list "$dns_file" "$mode"
    
    print_status $GREEN "=== Processing Complete ==="
}

# Run the script
main "$@"