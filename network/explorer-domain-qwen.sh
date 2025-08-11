#!/bin/bash

# Domain Explorer Script - Enhanced Version
# Usage: ./explorer-domain-qwen.sh <domain>
# Example: ./explorer-domain-qwen.sh www.baidu.com

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
    local result=""
    local exit_code=0
    # We capture the exit code directly from the command substitution.
    # The '|| exit_code=$?' part ensures that 'set -e' is not triggered if the command fails.
    result=$(timeout "$timeout_duration" bash -c "$cmd" 2>/dev/null) || exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -n "$result" ]; then
        echo "$result"
        print_success "$description completed"
    elif [ $exit_code -eq 124 ]; then
        print_warning "$description timed out after ${timeout_duration}s"
    else
        # For other errors, we can mention the exit code for debugging.
        print_warning "$description failed or returned no results (Exit code: $exit_code)"
    fi
    echo
}

# Enhanced function for web analysis
analyze_web_security() {
    local domain="$1"
    local protocol="$2"
    local url="${protocol}://${domain}"
    
    # Convert protocol to uppercase for display
    local proto_upper=$(echo "$protocol" | tr '[:lower:]' '[:upper:]')
    
    print_subheader "${proto_upper} Security Headers Analysis"
    if command_exists curl; then
        local headers=""
        headers=$(curl -I -s --max-time 15 "$url" 2>/dev/null || echo "Failed to fetch headers")
        
        if [ "$headers" != "Failed to fetch headers" ] && [ -n "$headers" ]; then
            echo "Security Headers Analysis:"
            echo "$headers" | grep -i "strict-transport-security" && print_success "HSTS enabled" || print_warning "HSTS not found"
            echo "$headers" | grep -i "x-frame-options" && print_success "X-Frame-Options set" || print_warning "X-Frame-Options not found"
            echo "$headers" | grep -i "x-content-type-options" && print_success "X-Content-Type-Options set" || print_warning "X-Content-Type-Options not found"
            echo "$headers" | grep -i "content-security-policy" && print_success "CSP enabled" || print_warning "CSP not found"
            echo "$headers" | grep -i "x-xss-protection" && print_success "XSS Protection enabled" || print_warning "XSS Protection not found"
            echo "$headers" | grep -i "referrer-policy" && print_success "Referrer Policy set" || print_warning "Referrer Policy not found"
            echo "$headers" | grep -i "permissions-policy" && print_success "Permissions Policy set" || print_warning "Permissions Policy not found"
        else
            print_warning "Failed to fetch headers for $url"
        fi
    else
        print_warning "curl not available for security headers analysis"
    fi
}

# Enhanced subdomain discovery function
enhanced_subdomain_discovery() {
    local domain="$1"
    local wordlist="/usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt"
    
    print_subheader "Enhanced Subdomain Discovery"
    
    # Common subdomains check (existing functionality)
    print_info "Checking common subdomains..."
    COMMON_SUBDOMAINS="www mail ftp admin blog shop api cdn m mobile dev test staging forum cpanel webmail"
    
    for sub in $COMMON_SUBDOMAINS; do
        if command_exists dig; then
            if dig +short A "$sub.$domain" >/dev/null 2>&1; then
                SUB_IP=$(dig +short A "$sub.$domain" | head -n1)
                if [ -n "$SUB_IP" ]; then
                    print_success "Found: $sub.$domain -> $SUB_IP"
                fi
            fi
        elif command_exists nslookup; then
            local result=""
            result=$(nslookup "$sub.$domain" 2>/dev/null | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -n1)
            if [ -n "$result" ]; then
                print_success "Found: $sub.$domain -> $result"
            fi
        fi
    done
    
    # Using wordlist if available
    if [ -f "$wordlist" ] && command_exists dig; then
        print_info "Performing dictionary-based subdomain discovery..."
        local found_count=0
        while IFS= read -r subdomain; do
            if [ -n "$subdomain" ] && [ "$subdomain" != "#" ]; then
                if dig +short A "${subdomain}.${domain}" >/dev/null 2>&1; then
                    SUB_IP=$(dig +short A "${subdomain}.${domain}" | head -n1)
                    if [ -n "$SUB_IP" ]; then
                        print_success "Found: ${subdomain}.${domain} -> $SUB_IP"
                        found_count=$((found_count + 1))
                        # Limit output to prevent overwhelming the report
                        if [ $found_count -gt 20 ]; then
                            print_info "Found 20+ subdomains. Stopping to prevent report bloat."
                            break
                        fi
                    fi
                fi
            fi
        done < "$wordlist"
    elif command_exists amass; then
        print_info "Using Amass for subdomain discovery..."
        run_command "amass enum -d $domain" "Amass subdomain enumeration" 120
    else
        print_warning "No subdomain wordlist found and Amass not installed. Skipping dictionary-based discovery."
    fi
}

# Enhanced port scanning function
enhanced_port_scan() {
    local ip="$1"
    
    if [ -z "$ip" ]; then
        print_warning "No IP address provided for port scanning"
        return
    fi
    
    print_subheader "Enhanced Port Scanning"
    
    if command_exists nmap; then
        # Top 1000 ports scan
        run_command "nmap -F --open $ip" "Fast scan (top 1000 ports)" 90
        
        # Service version detection
        echo "if we don't wait 120s . we can adjust the timeout setting"
        #run_command "nmap -sV $ip" "Service version detection" 120
        run_command "nmap -sV $ip" "Service version detection" 12
        
        # OS detection
        # run_command "nmap -O $ip" "OS detection" 120
        run_command "nmap -O $ip" "OS detection" 12
        
        # Vulnerability scan with default scripts
        # setting Vulnerability scan timeout 18s
        # run_command "nmap --script default,vuln -p 80,443,21,22,23,25,110,143,993,995 $ip" "Vulnerability scan" 180
        run_command "nmap --script default,vuln -p 80,443,21,22,23,25,110,143,993,995 $ip" "Vulnerability scan" 10
        
        # Aggressive scan for more info
        # run_command "nmap -A $ip" "Aggressive scan (OS, version, script, traceroute)" 180
        run_command "nmap -A $ip" "Aggressive scan (OS, version, script, traceroute)" 12
    elif command_exists nc; then
        print_subheader "Basic Port Check (using netcat)"
        for port in 21 22 23 25 53 80 110 143 443 993 995 3306 5432 8080 8443; do
            if timeout 3 nc -z "$ip" "$port" 2>/dev/null; then
                print_success "Port $port is open"
            fi
        done
    else
        print_warning "Neither nmap nor netcat available for port scanning"
    fi
}

# DNS Analysis function
dns_analysis() {
    local domain="$1"
    
    print_header "DNS ANALYSIS"
    
    print_subheader "A Records (IPv4)"
    if command_exists dig; then
        run_command "dig +short A $domain" "IPv4 resolution"
    elif command_exists nslookup; then
        run_command "nslookup -type=A $domain" "IPv4 resolution (nslookup)"
    elif command_exists host; then
        run_command "host -t A $domain" "IPv4 resolution (host)"
    else
        print_warning "No DNS query tool available"
    fi
    
    print_subheader "AAAA Records (IPv6)"
    if command_exists dig; then
        run_command "dig +short AAAA $domain" "IPv6 resolution"
    elif command_exists host; then
        run_command "host -t AAAA $domain" "IPv6 resolution (host)"
    else
        print_warning "No IPv6 DNS query tool available"
    fi
    
    print_subheader "CNAME Records"
    if command_exists dig; then
        run_command "dig +short CNAME $domain" "CNAME resolution"
    elif command_exists nslookup; then
        run_command "nslookup -type=CNAME $domain" "CNAME resolution (nslookup)"
    else
        print_warning "No CNAME query tool available"
    fi
    
    print_subheader "MX Records (Mail Exchange)"
    if command_exists dig; then
        run_command "dig +short MX $domain" "MX records"
    elif command_exists nslookup; then
        run_command "nslookup -type=MX $domain" "MX records (nslookup)"
    else
        print_warning "No MX query tool available"
    fi
    
    print_subheader "NS Records (Name Servers)"
    if command_exists dig; then
        run_command "dig +short NS $domain" "Name servers"
    elif command_exists nslookup; then
        run_command "nslookup -type=NS $domain" "Name servers (nslookup)"
    else
        print_warning "No NS query tool available"
    fi
    
    print_subheader "TXT Records"
    if command_exists dig; then
        run_command "dig +short TXT $domain" "TXT records"
    elif command_exists nslookup; then
        run_command "nslookup -type=TXT $domain" "TXT records (nslookup)"
    else
        print_warning "No TXT query tool available"
    fi
    
    print_subheader "SOA Record (Start of Authority)"
    if command_exists dig; then
        run_command "dig +short SOA $domain" "SOA record"
    elif command_exists nslookup; then
        run_command "nslookup -type=SOA $domain" "SOA record (nslookup)"
    else
        print_warning "No SOA query tool available"
    fi
    
    print_subheader "CAA Records (Certificate Authority Authorization)"
    if command_exists dig; then
        run_command "dig +short CAA $domain" "CAA records"
    else
        print_warning "CAA query requires dig command"
    fi
    
    print_subheader "DNS Security Extensions (DNSSEC)"
    if command_exists dig; then
        run_command "dig +dnssec $domain DNSKEY" "DNSKEY records"
        run_command "dig +dnssec $domain DS" "DS records"
    else
        print_warning "DNSSEC analysis requires dig command"
    fi
    
    print_subheader "Zone Transfer Attempt"
    local nameservers=""
    if command_exists dig; then
        # For a CNAME or subdomain, find NS records of the root domain.
        local root_domain=$(echo "$domain" | awk -F. '{if (NF>1) print $(NF-1)"."$NF; else print $0}')
        nameservers=$(dig +short NS "$root_domain" 2>/dev/null | grep -v "^$" | head -5)
        # If that fails, fall back to the provided domain
        if [ -z "$nameservers" ]; then
            nameservers=$(dig +short NS "$domain" 2>/dev/null | grep -v "^$" | head -5)
        fi
    elif command_exists nslookup; then
        # This nslookup logic can be fragile, dig is preferred.
        nameservers=$(nslookup -type=NS "$domain" 2>/dev/null | grep 'nameserver =' | awk '{print $NF}' | sed 's/\.$//' | head -5)
    fi
    
    if [ -n "$nameservers" ]; then
        echo "Attempting zone transfer on each nameserver:"
        local ns_count=0
        while IFS= read -r ns; do
            if [ -n "$ns" ] && [ "$ns_count" -lt 5 ]; then
                ns=$(echo "$ns" | tr -d '\r\n' | sed 's/\.$//')
                
                if [[ "$ns" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$ns" =~ \. ]]; then
                    print_warning "Skipping invalid nameserver: $ns"
                    continue
                fi
                
                echo -n "Nameserver $ns: "
                local axfr_result=""
                # The 'dig' command for AXFR will return a non-zero exit code on failure.
                # With 'set -e', this would terminate the script. Adding '|| true' prevents this.
                if command_exists dig; then
                    axfr_result=$(timeout 5 dig +time=2 +tries=1 +short axfr "$domain" "@$ns" 2>/dev/null) || true
                fi

                # Check if the result is non-empty and doesn't contain common failure messages.
                if [ -n "$axfr_result" ] && ! [[ "$axfr_result" =~ "connection timed out" || "$axfr_result" =~ "Transfer failed" || "$axfr_result" =~ "communications error" || "$axfr_result" =~ "refused" ]]; then
                    echo -e "${GREEN}Zone transfer successful${NC}"
                    echo "$axfr_result" | head -10
                    if [ "$(echo "$axfr_result" | wc -l)" -gt 10 ]; then
                        echo "... (truncated, showing first 10 lines)"
                    fi
                else
                    echo -e "${RED}Zone transfer failed or not allowed${NC}"
                fi
                ns_count=$((ns_count + 1))
            fi
        done <<< "$nameservers"
    else
        print_warning "No nameservers found for zone transfer attempt"
    fi
    
    print_subheader "Complete DNS Information"
    if command_exists dig; then
        run_command "dig ANY $domain" "Complete DNS query" 10
    else
        print_warning "Complete DNS query requires dig command"
    fi
}

# IP Analysis function
ip_analysis() {
    local domain="$1"
    local ip="$2"
    
    print_header "IP ADDRESS ANALYSIS"
    
    if [ -n "$ip" ]; then
        echo -e "Primary IP: ${GREEN}$ip${NC}"
        
        print_subheader "Reverse DNS Lookup"
        if command_exists dig; then
            run_command "dig +short -x $ip" "Reverse DNS for $ip"
        elif command_exists nslookup; then
            run_command "nslookup $ip" "Reverse DNS for $ip (nslookup)"
        else
            print_warning "No reverse DNS lookup tool available"
        fi
        
        print_subheader "IP Geolocation (using ipinfo.io)"
        if command_exists curl; then
            run_command "curl -s ipinfo.io/$ip" "IP geolocation"
        else
            print_warning "curl not available for geolocation lookup"
        fi
        
        print_subheader "Traceroute to Domain"
        if command_exists traceroute; then
            run_command "timeout 20 traceroute -m 10 -w 1 $ip" "Traceroute" 25
        elif command_exists tracert; then
            run_command "timeout 20 tracert -h 10 $ip" "Traceroute (Windows)" 25
        elif command_exists tcptraceroute; then
            run_command "timeout 20 tcptraceroute -m 10 -w 1 $ip" "TCP Traceroute" 25
        else
            print_warning "Traceroute command not available"
        fi
        
        print_subheader "ASN and Network Information"
        if command_exists curl; then
            run_command "curl -s ipinfo.io/$ip/org" "Organization"
            run_command "curl -s ipinfo.io/$ip/asn" "ASN Information"
        fi
    else
        print_warning "No IPv4 address found for domain. Skipping IP analysis."
    fi
}

# Web Analysis function
web_analysis() {
    local domain="$1"
    
    print_header "WEB SERVER ANALYSIS"
    
    print_subheader "HTTP Response Headers"
    if command_exists curl; then
        run_command "curl -I -L --max-time 15 http://$domain" "HTTP headers"
        
        print_subheader "HTTPS Response Headers"
        run_command "curl -I -L --max-time 15 https://$domain" "HTTPS headers"
        
        print_subheader "HTTP Status and Redirects"
        run_command "curl -L -w 'HTTP Status: %{http_code}\nTotal Time: %{time_total}s\nRedirect Count: %{num_redirects}\nFinal URL: %{url_effective}\n' -o /dev/null -s --max-time 15 http://$domain" "HTTP analysis"
        
        # Security headers analysis
        analyze_web_security "$domain" "http"
        analyze_web_security "$domain" "https"
        
        # Check for common web vulnerabilities
        print_subheader "Web Vulnerability Checks"
        
        # Check for HTTP methods
        print_info "Checking HTTP methods..."
        local methods=""
        if command_exists curl; then
            # The pipe can fail if the 'Allow' header isn't found. '|| true' prevents 'set -e' from exiting.
            methods=$(curl -s -L -X OPTIONS --max-time 10 "http://$domain" -I 2>/dev/null | grep -i "allow" | cut -d" " -f2- || true)
        fi
        if [ -n "$methods" ]; then
            echo "Allowed HTTP methods: $methods"
        else
            print_warning "Could not determine allowed HTTP methods"
        fi
        
        # Check for TRACE method (XST vulnerability)
        print_info "Checking for TRACE method..."
        local trace_result=""
        if command_exists curl; then
            # This command can also fail. Add '|| true' for safety.
            trace_result=$(curl -s -L -X TRACE --max-time 10 "http://$domain" 2>/dev/null || true)
        fi
        # A successful TRACE request usually reflects the request line in the response.
        if [ -n "$trace_result" ] && echo "$trace_result" | grep -qE "(TRACE|TRACK) /"; then
            print_warning "TRACE/TRACK method may be enabled (potential Cross-Site Tracing vulnerability)"
        else
            print_success "TRACE/TRACK method appears disabled"
        fi
        
    else
        print_warning "curl not available for web server analysis"
    fi
    
    print_subheader "Robots.txt"
    if command_exists curl; then
        local robots=""
        robots=$(curl -s --max-time 10 "http://$domain/robots.txt" 2>/dev/null)
        if [ -n "$robots" ]; then
            echo "$robots" | head -20
            if echo "$robots" | grep -i "disallow:" >/dev/null; then
                print_info "Interesting paths found in robots.txt"
            fi
        else
            print_warning "No robots.txt file found"
        fi
    fi
    
    print_subheader "Sitemap.xml"
    if command_exists curl; then
        local sitemap=""
        sitemap=$(curl -s --max-time 10 "http://$domain/sitemap.xml" 2>/dev/null)
        if [ -n "$sitemap" ]; then
            echo "$sitemap" | head -20
        else
            print_warning "No sitemap.xml found"
        fi
    fi
    
    print_subheader "Directory Discovery"
    if command_exists curl; then
        print_info "Checking for common directories..."
        COMMON_DIRS="admin login wp-admin phpmyadmin .git .env"
        for dir in $COMMON_DIRS; do
            local status=""
            status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://$domain/$dir/" 2>/dev/null)
            case $status in
                200) print_success "Directory found: /$dir (Status: $status)" ;;
                301|302) print_warning "Directory redirect: /$dir (Status: $status)" ;;
                403) print_warning "Directory forbidden: /$dir (Status: $status)" ;;
                401) print_warning "Directory requires auth: /$dir (Status: $status)" ;;
                *) if [ -n "$status" ] && [ "$status" != "000" ]; then
                     print_info "Directory $dir returned status: $status"
                   fi ;;
            esac
        done
    fi
}

# SSL/TLS Analysis function
ssl_analysis() {
    local domain="$1"
    
    print_header "SSL/TLS CERTIFICATE ANALYSIS"
    
    if command_exists openssl; then
        print_subheader "SSL Certificate Information"
        run_command "echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | openssl x509 -noout -text" "SSL certificate details" 30
        
        print_subheader "SSL Certificate Chain"
        run_command "echo | openssl s_client -servername $domain -connect $domain:443 -showcerts 2>/dev/null" "SSL certificate chain" 30
        
        print_subheader "SSL Certificate Expiry"
        run_command "echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | openssl x509 -noout -dates" "SSL certificate expiry" 20
        
        print_subheader "SSL Cipher Suites"
        if command_exists nmap; then
            run_command "nmap --script ssl-enum-ciphers -p 443 $domain" "SSL cipher analysis" 45
        else
            run_command "openssl ciphers -v 'ALL:COMPLEMENTOFALL' | grep $domain" "SSL cipher check" 30
        fi
        
        print_subheader "TLS Version Support"
        for tls in tls1 tls1_1 tls1_2 tls1_3; do
            if echo | openssl s_client -servername "$domain" -connect "$domain:443" -"$tls" 2>/dev/null | grep -q "Protocol.*$tls"; then
                print_success "$tls supported"
            else
                print_warning "$tls not supported"
            fi
        done
        
        print_subheader "Certificate Transparency Logs"
        local cert_serial=""
        cert_serial=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -serial 2>/dev/null | cut -d'=' -f2)
        if [ -n "$cert_serial" ]; then
            print_info "Certificate serial: $cert_serial"
        fi
    else
        print_warning "OpenSSL not available for certificate analysis"
    fi
}

# Security Analysis function
security_analysis() {
    local domain="$1"
    
    print_header "SECURITY ANALYSIS"
    
    print_subheader "WHOIS Information"
    if command_exists whois; then
        run_command "whois $domain" "WHOIS lookup" 30
    else
        print_warning "whois command not available"
    fi
    
    print_subheader "DNS Security Extensions (DNSSEC)"
    if command_exists dig; then
        run_command "dig +dnssec $domain" "DNSSEC check"
    else
        print_warning "DNSSEC check requires dig command"
    fi
    
    print_subheader "Email Security Records"
    print_info "Checking SPF Record..."
    local spf=""
    if command_exists dig; then
        # Add '|| true' to prevent pipefail from exiting the script if no SPF record is found.
        spf=$(dig +short TXT "$domain" 2>/dev/null | grep -i "v=spf1" || true)
    fi
    if [ -n "$spf" ]; then
        print_success "SPF Record found: $spf"
    else
        print_warning "No SPF Record found"
    fi
    
    print_info "Checking DKIM Records..."
    # This is a basic check - DKIM selectors vary
    local selectors="default google yahoo"
    local dkim_found=false
    for selector in $selectors; do
        local dkim=""
        if command_exists dig; then
            # Add '|| true' to prevent dig failure from exiting the script.
            dkim=$(dig +short TXT "${selector}._domainkey.$domain" 2>/dev/null || true)
        fi
        if [ -n "$dkim" ]; then
            print_success "DKIM Record found for selector '$selector': $dkim"
            dkim_found=true
        fi
    done
    if [ "$dkim_found" = false ]; then
        print_warning "No common DKIM Records found"
    fi
    
    print_info "Checking DMARC Record..."
    local dmarc=""
    if command_exists dig; then
        # Add '|| true' to prevent dig failure from exiting the script.
        dmarc=$(dig +short TXT "_dmarc.$domain" 2>/dev/null || true)
    fi
    if [ -n "$dmarc" ]; then
        print_success "DMARC Record found: $dmarc"
    else
        print_warning "No DMARC Record found"
    fi
    
    print_subheader "CAA Records (Certificate Authority Authorization)"
    if command_exists dig; then
        run_command "dig +short CAA $domain" "CAA records"
    else
        print_warning "CAA records check requires dig command"
    fi
    
    print_subheader "Subdomain Takeover Checks"
    print_info "Checking for potential subdomain takeover vulnerabilities..."
    # This is a simplified check - real checks would be more comprehensive
    print_warning "Note: Full subdomain takeover checks require manual verification"
}

# Performance Analysis function
performance_analysis() {
    local domain="$1"
    local ip="$2"
    
    print_header "PERFORMANCE ANALYSIS"
    
    print_subheader "Ping Test"
    if command_exists ping; then
        run_command "ping -c 4 $domain" "Ping test" 20
    else
        print_warning "ping command not available"
    fi
    
    print_subheader "Page Load Time"
    if command_exists curl; then
        run_command "curl -w 'DNS Lookup: %{time_namelookup}s\nTCP Connect: %{time_connect}s\nSSL Handshake: %{time_appconnect}s\nTime to First Byte: %{time_starttransfer}s\nTotal Time: %{time_total}s\nDownload Speed: %{speed_download} bytes/sec\n' -o /dev/null -s --max-time 30 https://$domain" "Performance metrics"
    fi
    
    print_subheader "DNS Resolution Performance"
    local dns_servers="8.8.8.8 1.1.1.1 208.67.222.222"
    for dns in $dns_servers; do
        local resolve_time=""
        if command_exists dig; then
            resolve_time=$(dig @"$dns" "$domain" 2>/dev/null | grep "Query time" | awk '{print $4}')
        fi
        echo "DNS Server $dns: ${resolve_time:-N/A} ms"
    done
}

# Network Information function
network_info() {
    local domain="$1"
    local ip="$2"
    
    print_header "NETWORK INFORMATION"
    
    print_subheader "Network Route Information"
    if command_exists ip; then
        run_command "ip route get $ip" "Route information"
    elif command_exists route; then
        run_command "route -n" "Routing table"
    fi
    
    print_subheader "DNS Propagation Check"
    #local dns_servers="8.8.8.8 1.1.1.1 208.67.222.222 9.9.9.9"
    local dns_servers="119.29.29.29 114.114.114.114"
    echo "Checking DNS propagation across different servers:"
    for dns in $dns_servers; do
        echo -n "DNS Server $dns: "
        local result=""
        if command_exists dig; then
            result=$(dig @"$dns" +short A "$domain" 2>/dev/null | head -n1)
        fi
        if [ -n "$result" ]; then
            echo -e "${GREEN}$result${NC}"
        else
            echo -e "${RED}No response${NC}"
        fi
    done
    
    print_subheader "CDN Detection"
    if command_exists curl; then
        local headers=""
        headers=$(curl -I -s --max-time 10 "http://$domain" 2>/dev/null)
        if echo "$headers" | grep -i "cloudflare" >/dev/null; then
            print_success "Cloudflare CDN detected"
        elif echo "$headers" | grep -i "akamai" >/dev/null; then
            print_success "Akamai CDN detected"
        elif echo "$headers" | grep -i "amazon" >/dev/null; then
            print_success "Amazon CloudFront CDN detected"
        elif echo "$headers" | grep -i "fastly" >/dev/null; then
            print_success "Fastly CDN detected"
        else
            print_info "No common CDN detected"
        fi
    fi
}

# Start the exploration
print_header "DOMAIN EXPLORATION REPORT (ENHANCED)"
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

# Get primary IP
PRIMARY_IP=""
if command_exists dig; then
    PRIMARY_IP=$(dig +short A "$CLEAN_DOMAIN" | head -n1)
elif command_exists nslookup; then
    PRIMARY_IP=$(nslookup "$CLEAN_DOMAIN" 2>/dev/null | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -n1)
elif command_exists host; then
    PRIMARY_IP=$(host -t A "$CLEAN_DOMAIN" 2>/dev/null | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -n1)
fi

if [ -z "$PRIMARY_IP" ]; then
    print_warning "Could not resolve IP address for $CLEAN_DOMAIN. Some tests will be skipped."
else
    echo -e "Primary IP: ${GREEN}$PRIMARY_IP${NC}"
fi

# Run all analysis functions
dns_analysis "$CLEAN_DOMAIN"
ip_analysis "$CLEAN_DOMAIN" "$PRIMARY_IP"
web_analysis "$CLEAN_DOMAIN"
ssl_analysis "$CLEAN_DOMAIN"
security_analysis "$CLEAN_DOMAIN"
enhanced_port_scan "$PRIMARY_IP"
performance_analysis "$CLEAN_DOMAIN" "$PRIMARY_IP"
enhanced_subdomain_discovery "$CLEAN_DOMAIN"
network_info "$CLEAN_DOMAIN" "$PRIMARY_IP"

print_header "12. SUMMARY"

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

print_success "Enhanced domain exploration completed successfully!"

echo -e "\n${BLUE}================================${NC}"
echo -e "${WHITE}Recommended Next Steps:${NC}"
echo -e "${BLUE}================================${NC}"
echo "1. Review the generated report file for detailed analysis"
echo "2. Check any security warnings or missing headers"
echo "3. Verify SSL certificate expiry dates"
echo "4. Monitor open ports for security implications"
echo "5. Verify subdomain takeover vulnerabilities"
echo "6. Consider running additional security scans with specialized tools"
echo "7. Check email security records (SPF, DKIM, DMARC) for proper configuration"

exit 0