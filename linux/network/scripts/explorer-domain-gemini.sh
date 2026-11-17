#!/bin/bash

# Domain Explorer Script - Gemini Enhanced
# Description: An advanced script for comprehensive domain analysis, including DNS, IP, web, SSL, and vulnerability scanning.
# Usage: ./explorer-domain-gemini.sh <domain>
# Example: ./explorer-domain-gemini.sh www.baidu.com

set -euo pipefail

# --- Configuration ---
# Timeout for most commands
DEFAULT_TIMEOUT=30
# Timeout for longer commands like nmap scans
LONG_TIMEOUT=120
# Common ports for quick scan
COMMON_PORTS="21,22,23,25,53,80,110,143,443,3306,3389,5900,8080,8443"
# Extended list of subdomains for enumeration
SUBDOMAIN_LIST="www,mail,ftp,admin,blog,shop,api,cdn,m,mobile,dev,test,staging,uat,prod,db,sql,mysql,mongo,api-docs,docs,support,help,status,old,new,vpn,gateway,remote,portal,sso,auth,assets,static,files,images,video,app,dashboard,cloud,lab,labs,internal,external,corp,corporate,office"

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# --- Helper Functions ---
print_header() {
    echo -e "\n${BLUE}======================================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}======================================================================${NC}"
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to run a command with a description, timeout, and error handling
run_command() {
    local cmd="$1"
    local description="$2"
    local timeout_duration="${3:-$DEFAULT_TIMEOUT}"
    
    echo -e "${YELLOW}Running: $description...${NC}"
    # Using eval to handle complex commands with pipes and redirects correctly
    if timeout "$timeout_duration" bash -c "$cmd"; then
        print_success "$description completed."
    else
        print_warning "$description failed or timed out after ${timeout_duration}s."
    fi
    echo
}

# --- Pre-flight Checks ---
# Check for root user for certain commands
if [[ $EUID -eq 0 ]]; then
    print_warning "Running as root. Nmap scans will be more powerful but also more detectable."
fi

# Check if domain is provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <domain>"
    echo -e "${YELLOW}Example: $0 baidu.com${NC}"
    exit 1
fi

# Check for required tools
REQUIRED_TOOLS="dig curl nmap openssl whois traceroute"
for tool in $REQUIRED_TOOLS; do
    if ! command_exists "$tool"; then
        print_error "Required tool '$tool' is not installed. Please install it to continue."
        MISSING_TOOL=true
    fi
done
if [ -n "${MISSING_TOOL-}" ]; then
    exit 1
fi
print_success "All required tools are available."

# --- Initialization ---
DOMAIN="$1"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
# Remove protocol and trailing slashes for a clean filename
CLEAN_DOMAIN="$(echo "$DOMAIN" | sed -e 's|^https?://||' -e 's|/.*$||')"
OUTPUT_FILE="domain_report_${CLEAN_DOMAIN}_$(date +%Y%m%d_%H%M%S).txt"

# Start logging to file
exec > >(tee -a "$OUTPUT_FILE") 2>&1

print_header "GEMINI DOMAIN EXPLORATION REPORT"
echo -e "Domain: ${GREEN}$CLEAN_DOMAIN${NC}"
echo -e "Timestamp: ${CYAN}$TIMESTAMP${NC}"
echo -e "Report File: ${PURPLE}$OUTPUT_FILE${NC}"

# --- Main Logic ---

# 1. DNS ANALYSIS
print_header "1. DNS ANALYSIS"
print_subheader "A Records (IPv4)"
IPV4_ADDRESSES="$(dig +short A "$CLEAN_DOMAIN")"
echo "${IPV4_ADDRESSES:-No A records found.}"

print_subheader "AAAA Records (IPv6)"
IPV6_ADDRESSES="$(dig +short AAAA "$CLEAN_DOMAIN")"
echo "${IPV6_ADDRESSES:-No AAAA records found.}"

ALL_IPS="$(echo "$IPV4_ADDRESSES $IPV6_ADDRESSES" | tr ' ' '\n' | sort -u)"

print_subheader "CNAME Record"
run_command "dig +short CNAME $CLEAN_DOMAIN" "CNAME resolution"

print_subheader "MX Records (Mail Exchange)"
run_command "dig +short MX $CLEAN_DOMAIN | sort -n" "MX records"

print_subheader "NS Records (Name Servers)"
run_command "dig +short NS $CLEAN_DOMAIN" "Name servers"

print_subheader "TXT Records"
run_command "dig +short TXT $CLEAN_DOMAIN" "TXT records"

print_subheader "SOA Record (Start of Authority)"
run_command "dig +short SOA $CLEAN_DOMAIN" "SOA record"

print_subheader "SPF Records (Sender Policy Framework)"
run_command "dig +short TXT $CLEAN_DOMAIN | grep 'v=spf1'" "SPF record check"

print_subheader "DMARC Records (Domain-based Message Authentication, Reporting & Conformance)"
run_command "dig +short TXT _dmarc.$CLEAN_DOMAIN" "DMARC record check"

print_subheader "DNSSEC Records (DNS Security Extensions)"
run_command "dig +dnssec $CLEAN_DOMAIN | grep RRSIG" "DNSSEC check"

print_subheader "CAA Records (Certificate Authority Authorization)"
run_command "dig +short CAA $CLEAN_DOMAIN" "CAA records"

print_subheader "DNS Query Trace"
run_command "dig +trace $CLEAN_DOMAIN" "Full DNS query trace" $LONG_TIMEOUT

# 2. IP ADDRESS ANALYSIS
print_header "2. IP ADDRESS ANALYSIS"
if [ -z "$ALL_IPS" ]; then
    print_error "No IP addresses found for domain. Skipping IP analysis."
else
    for IP in $ALL_IPS; do
        print_subheader "Analysis for IP: ${GREEN}$IP${NC}"
        run_command "dig +short -x $IP" "Reverse DNS (PTR)"
        run_command "whois $IP | grep -i 'netname|orgname|country'" "WHOIS Info (Netname, Org, Country)"
        run_command "curl -s ipinfo.io/$IP" "IP Geolocation & ASN"
        run_command "traceroute -m 20 $IP" "Traceroute" $LONG_TIMEOUT
    done
fi

# 3. PORT SCANNING & SERVICE DETECTION
print_header "3. PORT SCANNING & SERVICE DETECTION"
if [ -z "$ALL_IPS" ]; then
    print_warning "Skipping port scans - no IP addresses available."
else
    for IP in $ALL_IPS; do
        print_subheader "Scanning IP: ${GREEN}$IP${NC}"
        run_command "nmap -p $COMMON_PORTS --open $IP" "Common ports scan" $LONG_TIMEOUT
        run_command "nmap -sV -p $COMMON_PORTS --open $IP" "Service version detection" $LONG_TIMEOUT
        if [[ $EUID -eq 0 ]]; then
            run_command "nmap -O $IP" "OS Detection (Requires Root)" $LONG_TIMEOUT
        else
            print_warning "OS Detection requires root privileges. Skipping."
        fi
    done
fi

# 4. WEB SERVER ANALYSIS
print_header "4. WEB SERVER ANALYSIS"
print_subheader "HTTP/HTTPS Headers & Tech Stack"
run_command "curl -A 'Gemini-Explorer-Bot' -I -L --max-time $DEFAULT_TIMEOUT https://$CLEAN_DOMAIN" "HTTPS headers"
HEADERS="$(curl -I -L -s --max-time $DEFAULT_TIMEOUT https://$CLEAN_DOMAIN)"
SERVER_INFO="$(echo "$HEADERS" | grep -i 'server:')"
POWERED_BY="$(echo "$HEADERS" | grep -i 'x-powered-by:')"
echo "Technology Stack:"
[ -n "$SERVER_INFO" ] && echo "  - $SERVER_INFO" || echo "  - Server header not found."
[ -n "$POWERED_BY" ] && echo "  - $POWERED_BY" || echo "  - X-Powered-By header not found."

print_subheader "Cookie Analysis"
COOKIE_INFO="$(echo "$HEADERS" | grep -i 'set-cookie')"
if [ -n "$COOKIE_INFO" ]; then
    echo "$COOKIE_INFO" | while read -r line; do
        echo "Found Cookie: $line"
        [[ "$line" =~ "HttpOnly" ]] && print_success "  HttpOnly flag is set." || print_warning "  HttpOnly flag is MISSING."
        [[ "$line" =~ "Secure" ]] && print_success "  Secure flag is set." || print_warning "  Secure flag is MISSING."
    done
else
    echo "No cookies found in headers."
fi

print_subheader "Security Headers Check"
echo "$HEADERS" | grep -i "strict-transport-security" && print_success "HSTS enabled" || print_warning "HSTS not found"
echo "$HEADERS" | grep -i "x-frame-options" && print_success "X-Frame-Options set" || print_warning "X-Frame-Options not found"
echo "$HEADERS" | grep -i "x-content-type-options" && print_success "X-Content-Type-Options set" || print_warning "X-Content-Type-Options not found"
echo "$HEADERS" | grep -i "content-security-policy" && print_success "CSP enabled" || print_warning "CSP not found"

print_subheader "Common Sensitive Files Check"
run_command "curl -s -o /dev/null -w '%{http_code}' http://$CLEAN_DOMAIN/robots.txt | grep 200 && echo 'robots.txt found' || echo 'robots.txt not found'" "Robots.txt"
run_command "curl -s -o /dev/null -w '%{http_code}' http://$CLEAN_DOMAIN/sitemap.xml | grep 200 && echo 'sitemap.xml found' || echo 'sitemap.xml not found'" "Sitemap.xml"
run_command "curl -s -o /dev/null -w '%{http_code}' http://$CLEAN_DOMAIN/.git/config | grep 200 && print_error '.git/config is accessible' || echo '.git/config not found'" ".git/config"
run_command "curl -s -o /dev/null -w '%{http_code}' http://$CLEAN_DOMAIN/.env | grep 200 && print_error '.env is accessible' || echo '.env not found'" ".env file"

# 5. SSL/TLS ANALYSIS
print_header "5. SSL/TLS ANALYSIS"
print_subheader "Certificate Details"
run_command "echo | openssl s_client -servername $CLEAN_DOMAIN -connect $CLEAN_DOMAIN:443 2>/dev/null | openssl x509 -noout -text" "SSL certificate details"
print_subheader "Certificate Expiry"
run_command "echo | openssl s_client -servername $CLEAN_DOMAIN -connect $CLEAN_DOMAIN:443 2>/dev/null | openssl x509 -noout -dates" "SSL certificate expiry"
print_subheader "Cipher Suite Enumeration"
run_command "nmap --script ssl-enum-ciphers -p 443 $CLEAN_DOMAIN" "SSL cipher analysis" $LONG_TIMEOUT
print_subheader "SSL Vulnerability Check (POODLE)"
run_command "nmap --script ssl-poodle -p 443 $CLEAN_DOMAIN" "SSL POODLE check" $LONG_TIMEOUT

# 6. VULNERABILITY SCANNING (ACTIVE)
print_header "6. VULNERABILITY SCANNING (ACTIVE)"
print_warning "This section performs active scans and may be detected by security systems."
if [ -z "$ALL_IPS" ]; then
    print_warning "Skipping vulnerability scans - no IP addresses available."
else
    for IP in $ALL_IPS; do
        print_subheader "Running Nmap vuln scan on: ${GREEN}$IP${NC}"
        run_command "nmap --script vuln -p $COMMON_PORTS $IP" "Nmap vulnerability scan" 300
    done
fi

# 7. SUBDOMAIN ENUMERATION
print_header "7. SUBDOMAIN ENUMERATION"
print_subheader "Checking common subdomains..."
for sub in $SUBDOMAIN_LIST; do
    TARGET_SUBDOMAIN="$sub.$CLEAN_DOMAIN"
    if host "$TARGET_SUBDOMAIN" &>/dev/null; then
        SUB_IP="$(host "$TARGET_SUBDOMAIN" | grep 'has address' | awk '{print $4}' | head -n1)"
        print_success "Found: $TARGET_SUBDOMAIN -> $SUB_IP"
    fi
done

# 8. SUMMARY
print_header "8. SUMMARY"
echo -e "${WHITE}Domain Exploration Complete!${NC}"
echo -e "Domain: ${GREEN}$CLEAN_DOMAIN${NC}"
echo -e "Primary IPv4: ${GREEN}$(echo "$IPV4_ADDRESSES" | head -n1)${NC}"
echo -e "All IPs Found: ${GREEN}$(echo "$ALL_IPS" | tr '\n' ' ')${NC}"
echo -e "Report saved to: ${PURPLE}$OUTPUT_FILE${NC}"
echo -e "Timestamp: ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE="$(du -h "$OUTPUT_FILE" | cut -f1)"
    LINE_COUNT="$(wc -l < "$OUTPUT_FILE")"
    echo -e "Report size: ${YELLOW}$FILE_SIZE${NC} (${YELLOW}$LINE_COUNT${NC} lines)"
fi

print_success "Domain exploration completed successfully!"

echo -e "\n${BLUE}----------------------------------------------------------------------${NC}"
echo -e "${WHITE}Recommended Next Steps:${NC}"
echo -e "${BLUE}----------------------------------------------------------------------${NC}"
echo "1. Review the full report file ($OUTPUT_FILE) for details."
echo "2. Investigate any findings from the 'VULNERABILITY SCANNING' section."
echo "3. Check for missing security headers (HSTS, CSP) and insecure cookie flags."
echo "4. Verify that no sensitive files (.git, .env) are publicly accessible."
echo "5. For deeper subdomain discovery, consider tools like Amass or Sublist3r."
echo "6. For more in-depth web application scanning, use tools like Nikto or OWASP ZAP."

exit 0
