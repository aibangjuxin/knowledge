#!/bin/bash

# Basic Domain Explorer Script
# Usage: ./basic-domain-explorer.sh <domain>
# Example: ./basic-domain-explorer.sh example.com
# Uses only basic commands available on most systems

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Function to print colored headers
print_header() {
    echo -e "\n${BLUE}================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_subheader() {
    echo -e "\n${CYAN}--- $1 ---${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${PURPLE}i $1${NC}"
}

# Check if domain is provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Usage: $0 <domain>${NC}"
    echo -e "${YELLOW}Example: $0 example.com${NC}"
    exit 1
fi

DOMAIN="$1"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
OUTPUT_FILE="basic_domain_report_${DOMAIN}_$(date +%Y%m%d_%H%M%S).txt"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to run command with basic error handling
run_basic_command() {
    local cmd="$1"
    local description="$2"
    
    echo -e "${YELLOW}Running: $description${NC}"
    
    if eval "$cmd" 2>/dev/null; then
        print_success "$description completed"
    else
        print_warning "$description failed or not available"
    fi
    echo
}

print_header "BASIC DOMAIN EXPLORATION REPORT"
echo -e "Domain: ${GREEN}$DOMAIN${NC}"
echo -e "Timestamp: ${CYAN}$TIMESTAMP${NC}"
echo -e "Report file: ${PURPLE}$OUTPUT_FILE${NC}"

# Redirect all output to both console and file
exec > >(tee -a "$OUTPUT_FILE") 2>&1

# Clean domain (remove protocol if present)
CLEAN_DOMAIN=$(echo "$DOMAIN" | sed 's|^https\?://||' | sed 's|/.*||')
echo -e "Clean domain: ${GREEN}$CLEAN_DOMAIN${NC}"

# 1. WHOIS Information
print_header "1. WHOIS INFORMATION"
if command_exists whois; then
    run_basic_command "whois $CLEAN_DOMAIN | head -30" "WHOIS lookup"
else
    print_warning "whois command not available"
fi

# 2. Basic DNS Analysis
print_header "2. DNS ANALYSIS"

print_subheader "A Records (IPv4)"
if command_exists dig; then
    run_basic_command "dig +short A $CLEAN_DOMAIN" "A record lookup"
elif command_exists nslookup; then
    run_basic_command "nslookup $CLEAN_DOMAIN | grep -A2 'Name:'" "A record lookup (nslookup)"
else
    print_warning "No DNS lookup tools available"
fi

print_subheader "MX Records (Mail Exchange)"
if command_exists dig; then
    run_basic_command "dig +short MX $CLEAN_DOMAIN" "MX record lookup"
else
    print_warning "dig command not available for MX lookup"
fi

print_subheader "NS Records (Name Servers)"
if command_exists dig; then
    run_basic_command "dig +short NS $CLEAN_DOMAIN" "NS record lookup"
else
    print_warning "dig command not available for NS lookup"
fi

print_subheader "TXT Records"
if command_exists dig; then
    run_basic_command "dig +short TXT $CLEAN_DOMAIN" "TXT record lookup"
else
    print_warning "dig command not available for TXT lookup"
fi

# 3. Basic Web Analysis
print_header "3. WEB SERVER ANALYSIS"

print_subheader "HTTP Response Headers"
if command_exists curl; then
    run_basic_command "curl -I -s --max-time 10 http://$CLEAN_DOMAIN | head -10" "HTTP headers"
else
    print_warning "curl command not available"
fi

print_subheader "HTTPS Response Headers"
if command_exists curl; then
    run_basic_command "curl -I -s --max-time 10 https://$CLEAN_DOMAIN | head -10" "HTTPS headers"
else
    print_warning "curl command not available"
fi

print_subheader "Robots.txt"
if command_exists curl; then
    run_basic_command "curl -s --max-time 5 http://$CLEAN_DOMAIN/robots.txt | head -10" "robots.txt check"
else
    print_warning "curl command not available"
fi

# 4. Basic Port Scanning (using netcat if available)
print_header "4. BASIC PORT SCANNING"

# Get IP address first
PRIMARY_IP=""
if command_exists dig; then
    PRIMARY_IP=$(dig +short A "$CLEAN_DOMAIN" | head -n1)
elif command_exists nslookup; then
    PRIMARY_IP=$(nslookup "$CLEAN_DOMAIN" 2>/dev/null | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -n1)
fi

if [ -n "$PRIMARY_IP" ]; then
    echo -e "Primary IP: ${GREEN}$PRIMARY_IP${NC}"
    
    if command_exists nc; then
        print_subheader "Common Ports Check (using netcat)"
        common_ports="21 22 23 25 53 80 110 143 443 993 995 3306 5432 8080 8443"
        
        for port in $common_ports; do
            if nc -z -w3 "$PRIMARY_IP" "$port" 2>/dev/null; then
                print_success "Port $port is open"
            fi
        done
    elif command_exists telnet; then
        print_subheader "Basic Port Check (using telnet)"
        print_info "Checking common ports with telnet (this may take a moment)..."
        
        for port in 22 80 443; do
            if timeout 3 telnet "$PRIMARY_IP" "$port" 2>/dev/null | grep -q "Connected"; then
                print_success "Port $port appears to be open"
            fi
        done
    else
        print_warning "No port scanning tools available (nc or telnet)"
    fi
else
    print_warning "Could not resolve IP address for port scanning"
fi

# 5. Basic Security Analysis
print_header "5. BASIC SECURITY ANALYSIS"

print_subheader "SPF Record Check"
if command_exists dig; then
    run_basic_command "dig +short TXT $CLEAN_DOMAIN | grep -i 'v=spf1'" "SPF record check"
else
    print_warning "dig command not available for SPF check"
fi

print_subheader "DMARC Record Check"
if command_exists dig; then
    run_basic_command "dig +short TXT _dmarc.$CLEAN_DOMAIN" "DMARC record check"
else
    print_warning "dig command not available for DMARC check"
fi

# 6. Basic SSL Certificate Check
print_header "6. SSL CERTIFICATE ANALYSIS"

if command_exists openssl; then
    print_subheader "SSL Certificate Information"
    run_basic_command "echo | openssl s_client -servername $CLEAN_DOMAIN -connect $CLEAN_DOMAIN:443 2>/dev/null | openssl x509 -noout -text | grep -E '(Subject:|Issuer:|Not Before|Not After)' | head -5" "SSL certificate check"
else
    print_warning "openssl command not available"
fi

# 7. Basic Subdomain Discovery
print_header "7. BASIC SUBDOMAIN DISCOVERY"

print_subheader "Common Subdomains Check"
common_subs="www mail ftp admin blog shop api cdn m mobile dev test staging"

for sub in $common_subs; do
    if command_exists dig; then
        result=$(dig +short A "$sub.$CLEAN_DOMAIN" 2>/dev/null | head -n1)
        if [ -n "$result" ]; then
            print_success "Found: $sub.$CLEAN_DOMAIN -> $result"
        fi
    elif command_exists nslookup; then
        if nslookup "$sub.$CLEAN_DOMAIN" >/dev/null 2>&1; then
            print_success "Found: $sub.$CLEAN_DOMAIN"
        fi
    fi
done

# 8. Basic Network Information
print_header "8. NETWORK INFORMATION"

print_subheader "DNS Propagation Check"
if command_exists dig; then
    dns_servers="8.8.8.8 1.1.1.1"
    
    for dns in $dns_servers; do
        result=$(dig @"$dns" +short A "$CLEAN_DOMAIN" 2>/dev/null | head -n1)
        if [ -n "$result" ]; then
            echo -e "DNS Server $dns: ${GREEN}$result${NC}"
        else
            echo -e "DNS Server $dns: ${RED}No response${NC}"
        fi
    done
else
    print_warning "dig command not available for DNS propagation check"
fi

# Summary
print_header "SUMMARY"

echo -e "${WHITE}Basic Domain Exploration Complete!${NC}"
echo -e "Domain: ${GREEN}$CLEAN_DOMAIN${NC}"
echo -e "Primary IP: ${GREEN}${PRIMARY_IP:-'Not found'}${NC}"
echo -e "Report saved to: ${PURPLE}$OUTPUT_FILE${NC}"
echo -e "Timestamp: ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"

# File size and line count
if [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(du -h "$OUTPUT_FILE" 2>/dev/null | cut -f1 || echo "Unknown")
    LINE_COUNT=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "Unknown")
    echo -e "Report size: ${YELLOW}$FILE_SIZE${NC} (${YELLOW}$LINE_COUNT${NC} lines)"
fi

print_success "Basic domain exploration completed successfully!"

echo -e "\n${BLUE}================================${NC}"
echo -e "${WHITE}Tools Used (Basic Commands):${NC}"
echo -e "${BLUE}================================${NC}"
echo "✓ whois - Domain registration information"
echo "✓ dig/nslookup - DNS record queries"
echo "✓ curl - HTTP/HTTPS requests and headers"
echo "✓ nc/telnet - Basic port connectivity checks"
echo "✓ openssl - SSL certificate analysis"
echo "✓ Basic shell utilities (grep, head, sed, etc.)"

exit 0