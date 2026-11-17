#!/bin/bash

# Domain Explorer Script
# Usage: ./explorer-domain.sh <domain>
# Example: ./explorer-domain.sh www.baidu.com

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

# Check if domain is provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Usage: $0 <domain>${NC}"
    echo -e "${YELLOW}Example: $0 www.baidu.com${NC}"
    exit 1
fi

DOMAIN="$1"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
OUTPUT_FILE="domain_report_${DOMAIN}_$(date +%Y%m%d_%H%M%S).txt"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to run command with timeout and error handling
run_command() {
    local cmd="$1"
    local description="$2"
    local timeout_duration="${3:-30}"
    
    echo -e "${YELLOW}Running: $description${NC}"
    if timeout "$timeout_duration" bash -c "$cmd" 2>/dev/null; then
        print_success "$description completed"
    else
        print_warning "$description failed or timed out"
    fi
    echo
}

# Start the exploration
print_header "DOMAIN EXPLORATION REPORT"
echo -e "Domain: ${GREEN}$DOMAIN${NC}"
echo -e "Timestamp: ${CYAN}$TIMESTAMP${NC}"
echo -e "Report file: ${PURPLE}$OUTPUT_FILE${NC}"

# Redirect all output to both console and file
exec > >(tee -a "$OUTPUT_FILE") 2>&1

print_header "1. BASIC DOMAIN INFORMATION"

# Domain validation
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    print_error "Invalid domain format"
    exit 1
fi

print_success "Domain format is valid"

# Remove protocol if present
CLEAN_DOMAIN=$(echo "$DOMAIN" | sed 's|^https\?://||' | sed 's|/.*||')
echo -e "Clean domain: ${GREEN}$CLEAN_DOMAIN${NC}"

print_header "2. DNS RESOLUTION"

print_subheader "A Records (IPv4)"
run_command "dig +short A $CLEAN_DOMAIN" "IPv4 resolution"

print_subheader "AAAA Records (IPv6)"
run_command "dig +short AAAA $CLEAN_DOMAIN" "IPv6 resolution"

print_subheader "CNAME Records"
run_command "dig +short CNAME $CLEAN_DOMAIN" "CNAME resolution"

print_subheader "MX Records (Mail Exchange)"
run_command "dig +short MX $CLEAN_DOMAIN" "MX records"

print_subheader "NS Records (Name Servers)"
run_command "dig +short NS $CLEAN_DOMAIN" "Name servers"

print_subheader "TXT Records"
run_command "dig +short TXT $CLEAN_DOMAIN" "TXT records"

print_subheader "SOA Record (Start of Authority)"
run_command "dig +short SOA $CLEAN_DOMAIN" "SOA record"

print_subheader "Complete DNS Information"
run_command "dig ANY $CLEAN_DOMAIN" "Complete DNS query"

print_header "3. IP ADDRESS ANALYSIS"

# Get primary IP
PRIMARY_IP=$(dig +short A "$CLEAN_DOMAIN" | head -n1)
if [ -n "$PRIMARY_IP" ]; then
    echo -e "Primary IP: ${GREEN}$PRIMARY_IP${NC}"
    
    print_subheader "Reverse DNS Lookup"
    run_command "dig +short -x $PRIMARY_IP" "Reverse DNS for $PRIMARY_IP"
    
    print_subheader "IP Geolocation (using ipinfo.io)"
    if command_exists curl; then
        run_command "curl -s ipinfo.io/$PRIMARY_IP" "IP geolocation"
    else
        print_warning "curl not available for geolocation lookup"
    fi
    
    print_subheader "Traceroute to Domain"
    if command_exists traceroute; then
        run_command "traceroute -m 15 $PRIMARY_IP" "Traceroute" 45
    elif command_exists tracert; then
        run_command "tracert -h 15 $PRIMARY_IP" "Traceroute (Windows)" 45
    else
        print_warning "Traceroute command not available"
    fi
else
    print_error "No IPv4 address found for domain"
fi

print_header "4. PORT SCANNING"

if [ -n "$PRIMARY_IP" ]; then
    print_subheader "Common Ports Scan"
    COMMON_PORTS="21,22,23,25,53,80,110,143,443,993,995,8080,8443"
    
    if command_exists nmap; then
        run_command "nmap -p $COMMON_PORTS --open $PRIMARY_IP" "Nmap port scan" 60
        
        print_subheader "Service Detection"
        run_command "nmap -sV -p $COMMON_PORTS $PRIMARY_IP" "Service version detection" 90
        
        print_subheader "OS Detection"
        run_command "nmap -O $PRIMARY_IP" "OS detection" 60
    elif command_exists nc; then
        print_subheader "Basic Port Check (using netcat)"
        for port in 21 22 23 25 53 80 110 143 443 993 995 8080 8443; do
            if timeout 3 nc -z "$PRIMARY_IP" "$port" 2>/dev/null; then
                print_success "Port $port is open"
            fi
        done
    else
        print_warning "Neither nmap nor netcat available for port scanning"
    fi
else
    print_warning "Skipping port scan - no IP address available"
fi

print_header "5. WEB SERVER ANALYSIS"

print_subheader "HTTP Response Headers"
if command_exists curl; then
    run_command "curl -I -L --max-time 15 http://$CLEAN_DOMAIN" "HTTP headers"
    
    print_subheader "HTTPS Response Headers"
    run_command "curl -I -L --max-time 15 https://$CLEAN_DOMAIN" "HTTPS headers"
    
    print_subheader "HTTP Status and Redirects"
    run_command "curl -L -w 'HTTP Status: %{http_code}\nTotal Time: %{time_total}s\nRedirect Count: %{num_redirects}\nFinal URL: %{url_effective}\n' -o /dev/null -s --max-time 15 http://$CLEAN_DOMAIN" "HTTP analysis"
else
    print_warning "curl not available for web server analysis"
fi

print_subheader "Robots.txt"
if command_exists curl; then
    run_command "curl -s --max-time 10 http://$CLEAN_DOMAIN/robots.txt" "Robots.txt check"
fi

print_subheader "Sitemap.xml"
if command_exists curl; then
    run_command "curl -s --max-time 10 http://$CLEAN_DOMAIN/sitemap.xml | head -20" "Sitemap check"
fi

print_header "6. SSL/TLS CERTIFICATE ANALYSIS"

if command_exists openssl; then
    print_subheader "SSL Certificate Information"
    run_command "echo | openssl s_client -servername $CLEAN_DOMAIN -connect $CLEAN_DOMAIN:443 2>/dev/null | openssl x509 -noout -text" "SSL certificate details" 30
    
    print_subheader "SSL Certificate Chain"
    run_command "echo | openssl s_client -servername $CLEAN_DOMAIN -connect $CLEAN_DOMAIN:443 -showcerts 2>/dev/null" "SSL certificate chain" 30
    
    print_subheader "SSL Certificate Expiry"
    run_command "echo | openssl s_client -servername $CLEAN_DOMAIN -connect $CLEAN_DOMAIN:443 2>/dev/null | openssl x509 -noout -dates" "SSL certificate expiry" 20
    
    print_subheader "SSL Cipher Suites"
    run_command "nmap --script ssl-enum-ciphers -p 443 $CLEAN_DOMAIN" "SSL cipher analysis" 45
else
    print_warning "OpenSSL not available for certificate analysis"
fi

print_header "7. DOMAIN REPUTATION & SECURITY"

print_subheader "WHOIS Information"
if command_exists whois; then
    run_command "whois $CLEAN_DOMAIN" "WHOIS lookup" 30
else
    print_warning "whois command not available"
fi

print_subheader "DNS Security Extensions (DNSSEC)"
run_command "dig +dnssec $CLEAN_DOMAIN" "DNSSEC check"

print_subheader "CAA Records (Certificate Authority Authorization)"
run_command "dig +short CAA $CLEAN_DOMAIN" "CAA records"

print_subheader "Security Headers Check"
if command_exists curl; then
    echo "Checking security headers..."
    HEADERS=$(curl -I -s --max-time 10 https://$CLEAN_DOMAIN 2>/dev/null || echo "Failed to fetch headers")
    
    echo "Security Headers Analysis:"
    echo "$HEADERS" | grep -i "strict-transport-security" && print_success "HSTS enabled" || print_warning "HSTS not found"
    echo "$HEADERS" | grep -i "x-frame-options" && print_success "X-Frame-Options set" || print_warning "X-Frame-Options not found"
    echo "$HEADERS" | grep -i "x-content-type-options" && print_success "X-Content-Type-Options set" || print_warning "X-Content-Type-Options not found"
    echo "$HEADERS" | grep -i "content-security-policy" && print_success "CSP enabled" || print_warning "CSP not found"
    echo "$HEADERS" | grep -i "x-xss-protection" && print_success "XSS Protection enabled" || print_warning "XSS Protection not found"
fi

print_header "8. PERFORMANCE ANALYSIS"

print_subheader "Ping Test"
if command_exists ping; then
    run_command "ping -c 4 $CLEAN_DOMAIN" "Ping test" 20
else
    print_warning "ping command not available"
fi

print_subheader "Page Load Time"
if command_exists curl; then
    run_command "curl -w 'DNS Lookup: %{time_namelookup}s\nTCP Connect: %{time_connect}s\nSSL Handshake: %{time_appconnect}s\nTime to First Byte: %{time_starttransfer}s\nTotal Time: %{time_total}s\nDownload Speed: %{speed_download} bytes/sec\n' -o /dev/null -s --max-time 30 https://$CLEAN_DOMAIN" "Performance metrics"
fi

print_header "9. SUBDOMAIN ENUMERATION"

print_subheader "Common Subdomains Check"
COMMON_SUBDOMAINS="www mail ftp admin blog shop api cdn m mobile dev test staging"

for sub in $COMMON_SUBDOMAINS; do
    if dig +short A "$sub.$CLEAN_DOMAIN" >/dev/null 2>&1; then
        SUB_IP=$(dig +short A "$sub.$CLEAN_DOMAIN" | head -n1)
        if [ -n "$SUB_IP" ]; then
            print_success "Found: $sub.$CLEAN_DOMAIN -> $SUB_IP"
        fi
    fi
done

print_header "10. ADDITIONAL NETWORK INFORMATION"

print_subheader "Network Route Information"
if command_exists ip; then
    run_command "ip route get $PRIMARY_IP" "Route information"
elif command_exists route; then
    run_command "route -n" "Routing table"
fi

print_subheader "DNS Propagation Check"
DNS_SERVERS="8.8.8.8 1.1.1.1 208.67.222.222"
echo "Checking DNS propagation across different servers:"
for dns in $DNS_SERVERS; do
    echo -n "DNS Server $dns: "
    RESULT=$(dig @$dns +short A $CLEAN_DOMAIN 2>/dev/null | head -n1)
    if [ -n "$RESULT" ]; then
        echo -e "${GREEN}$RESULT${NC}"
    else
        echo -e "${RED}No response${NC}"
    fi
done

print_header "11. SUMMARY"

echo -e "${WHITE}Domain Exploration Complete!${NC}"
echo -e "Domain: ${GREEN}$CLEAN_DOMAIN${NC}"
echo -e "Primary IP: ${GREEN}${PRIMARY_IP:-'Not found'}${NC}"
echo -e "Report saved to: ${PURPLE}$OUTPUT_FILE${NC}"
echo -e "Timestamp: ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"

# File size and line count
if [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    LINE_COUNT=$(wc -l < "$OUTPUT_FILE")
    echo -e "Report size: ${YELLOW}$FILE_SIZE${NC} (${YELLOW}$LINE_COUNT${NC} lines)"
fi

print_success "Domain exploration completed successfully!"

echo -e "\n${BLUE}================================${NC}"
echo -e "${WHITE}Recommended Next Steps:${NC}"
echo -e "${BLUE}================================${NC}"
echo "1. Review the generated report file for detailed analysis"
echo "2. Check any security warnings or missing headers"
echo "3. Verify SSL certificate expiry dates"
echo "4. Monitor open ports for security implications"
echo "5. Consider running additional security scans if needed"

exit 0