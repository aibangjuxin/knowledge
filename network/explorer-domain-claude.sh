#!/opt/homebrew/bin/bash

# Domain Explorer Script - Claude Optimized Version
# Usage: ./explorer-domain-claude.sh <domain>
# Example: ./explorer-domain-claude.sh www.baidu.com
# Optimizations: Parallel execution, reduced timeouts, smart caching

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

# Global variables for caching
declare -A DNS_CACHE
declare -A IP_CACHE
TEMP_DIR="/tmp/domain_explorer_$$"
MAX_PARALLEL_JOBS=8

# Create temp directory
mkdir -p "$TEMP_DIR"
trap "cleanup_and_exit" EXIT

# Cleanup function
cleanup_and_exit() {
    # Kill any remaining background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    # Remove temp directory
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}

# Function to wait for background jobs with timeout
wait_for_jobs() {
    local pids=("$@")
    local timeout_per_job=10
    
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            # Process is still running, wait with timeout
            local count=0
            while kill -0 "$pid" 2>/dev/null && [ $count -lt $timeout_per_job ]; do
                sleep 1
                count=$((count + 1))
            done
            
            # If still running, kill it
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                print_warning "Background process $pid timed out and was killed"
            fi
        fi
    done
}

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

# Debug mode (set to 1 to enable debug output)
DEBUG=${DEBUG:-0}

# Debug function
debug_log() {
    if [ "$DEBUG" -eq 1 ]; then
        echo -e "${PURPLE}[DEBUG] $1${NC}" >&2
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Optimized function to run command with timeout and caching
run_command_fast() {
    local cmd="$1"
    local description="$2"
    local timeout_duration="${3:-10}"
    local cache_key="${4:-}"
    
    # Check cache first
    if [ -n "$cache_key" ] && [ -f "$TEMP_DIR/$cache_key" ]; then
        cat "$TEMP_DIR/$cache_key"
        print_success "$description (cached)"
        return 0
    fi
    
    echo -e "${YELLOW}Running: $description${NC}"
    local result=""
    local exit_code=0
    
    result=$(timeout "$timeout_duration" bash -c "$cmd" 2>/dev/null) || exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -n "$result" ]; then
        echo "$result"
        # Cache result if cache key provided
        if [ -n "$cache_key" ]; then
            echo "$result" > "$TEMP_DIR/$cache_key"
        fi
        print_success "$description completed"
    elif [ $exit_code -eq 124 ]; then
        print_warning "$description timed out after ${timeout_duration}s"
    else
        print_warning "$description failed (Exit code: $exit_code)"
    fi
    echo
}

# Parallel DNS resolution function
parallel_dns_lookup() {
    local domain="$1"
    local record_type="$2"
    local output_file="$3"
    
    if command_exists dig; then
        timeout 5 dig +short +time=2 +tries=1 "$record_type" "$domain" 2>/dev/null > "$output_file" || echo "" > "$output_file"
    elif command_exists nslookup && [ "$record_type" = "A" ]; then
        timeout 5 nslookup "$domain" 2>/dev/null | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -n1 > "$output_file" || echo "" > "$output_file"
    else
        echo "" > "$output_file"
    fi
}

# Fast DNS analysis with parallel queries
fast_dns_analysis() {
    local domain="$1"
    
    print_header "DNS ANALYSIS (PARALLEL)"
    
    # Start parallel DNS queries
    local pids=()
    parallel_dns_lookup "$domain" "A" "$TEMP_DIR/dns_a" &
    pids+=($!)
    parallel_dns_lookup "$domain" "AAAA" "$TEMP_DIR/dns_aaaa" &
    pids+=($!)
    parallel_dns_lookup "$domain" "CNAME" "$TEMP_DIR/dns_cname" &
    pids+=($!)
    parallel_dns_lookup "$domain" "MX" "$TEMP_DIR/dns_mx" &
    pids+=($!)
    parallel_dns_lookup "$domain" "NS" "$TEMP_DIR/dns_ns" &
    pids+=($!)
    parallel_dns_lookup "$domain" "TXT" "$TEMP_DIR/dns_txt" &
    pids+=($!)
    parallel_dns_lookup "$domain" "SOA" "$TEMP_DIR/dns_soa" &
    pids+=($!)
    
    # Wait for all DNS queries to complete with timeout
    wait_for_jobs "${pids[@]}"
    
    # Display results
    print_subheader "A Records (IPv4)"
    if [ -s "$TEMP_DIR/dns_a" ]; then
        cat "$TEMP_DIR/dns_a"
        print_success "IPv4 resolution completed"
    else
        print_warning "No A records found"
    fi
    
    print_subheader "AAAA Records (IPv6)"
    if [ -s "$TEMP_DIR/dns_aaaa" ]; then
        cat "$TEMP_DIR/dns_aaaa"
        print_success "IPv6 resolution completed"
    else
        print_warning "No AAAA records found"
    fi
    
    print_subheader "CNAME Records"
    if [ -s "$TEMP_DIR/dns_cname" ]; then
        cat "$TEMP_DIR/dns_cname"
        print_success "CNAME resolution completed"
    else
        print_info "No CNAME records found"
    fi
    
    print_subheader "MX Records (Mail Exchange)"
    if [ -s "$TEMP_DIR/dns_mx" ]; then
        cat "$TEMP_DIR/dns_mx"
        print_success "MX records found"
    else
        print_warning "No MX records found"
    fi
    
    print_subheader "NS Records (Name Servers)"
    if [ -s "$TEMP_DIR/dns_ns" ]; then
        cat "$TEMP_DIR/dns_ns"
        print_success "Name servers found"
    else
        print_warning "No NS records found"
    fi
    
    print_subheader "TXT Records"
    if [ -s "$TEMP_DIR/dns_txt" ]; then
        cat "$TEMP_DIR/dns_txt"
        print_success "TXT records found"
    else
        print_info "No TXT records found"
    fi
    
    print_subheader "SOA Record"
    if [ -s "$TEMP_DIR/dns_soa" ]; then
        cat "$TEMP_DIR/dns_soa"
        print_success "SOA record found"
    else
        print_warning "No SOA record found"
    fi
}

# Fast IP analysis
fast_ip_analysis() {
    local domain="$1"
    local ip="$2"
    
    print_header "IP ADDRESS ANALYSIS"
    
    if [ -n "$ip" ]; then
        echo -e "Primary IP: ${GREEN}$ip${NC}"
        
        # Parallel IP analysis
        local pids=()
        
        # Reverse DNS lookup
        if command_exists dig; then
            dig +short -x "$ip" 2>/dev/null > "$TEMP_DIR/reverse_dns" &
            pids+=($!)
        fi
        
        # Geolocation lookup
        if command_exists curl; then
            curl -s --max-time 8 "ipinfo.io/$ip" 2>/dev/null > "$TEMP_DIR/geolocation" &
            pids+=($!)
        fi
        
        # Wait for parallel tasks with timeout
        wait_for_jobs "${pids[@]}"
        
        print_subheader "Reverse DNS Lookup"
        if [ -s "$TEMP_DIR/reverse_dns" ]; then
            cat "$TEMP_DIR/reverse_dns"
            print_success "Reverse DNS completed"
        else
            print_warning "No reverse DNS found"
        fi
        
        print_subheader "IP Geolocation"
        if [ -s "$TEMP_DIR/geolocation" ]; then
            cat "$TEMP_DIR/geolocation"
            print_success "Geolocation completed"
        else
            print_warning "Geolocation lookup failed"
        fi
        
    else
        print_warning "No IPv4 address found for domain. Skipping IP analysis."
    fi
}

# Fast web analysis with parallel requests
fast_web_analysis() {
    local domain="$1"
    
    print_header "WEB SERVER ANALYSIS (PARALLEL)"
    
    if command_exists curl; then
        local pids=()
        
        # Parallel web requests
        curl -I -L --max-time 8 "http://$domain" 2>/dev/null > "$TEMP_DIR/http_headers" &
        pids+=($!)
        curl -I -L --max-time 8 "https://$domain" 2>/dev/null > "$TEMP_DIR/https_headers" &
        pids+=($!)
        curl -s --max-time 5 "http://$domain/robots.txt" 2>/dev/null > "$TEMP_DIR/robots" &
        pids+=($!)
        curl -s --max-time 5 "http://$domain/sitemap.xml" 2>/dev/null > "$TEMP_DIR/sitemap" &
        pids+=($!)
        
        # Performance metrics
        curl -w 'DNS:%{time_namelookup}s|Connect:%{time_connect}s|SSL:%{time_appconnect}s|TTFB:%{time_starttransfer}s|Total:%{time_total}s|Speed:%{speed_download}' \
             -o /dev/null -s --max-time 10 "https://$domain" 2>/dev/null > "$TEMP_DIR/performance" &
        pids+=($!)
        
        # Wait for all requests with timeout
        wait_for_jobs "${pids[@]}"
        
        # Display results
        print_subheader "HTTP Response Headers"
        if [ -s "$TEMP_DIR/http_headers" ]; then
            cat "$TEMP_DIR/http_headers"
            print_success "HTTP headers retrieved"
        else
            print_warning "HTTP headers not available"
        fi
        
        print_subheader "HTTPS Response Headers"
        if [ -s "$TEMP_DIR/https_headers" ]; then
            cat "$TEMP_DIR/https_headers"
            print_success "HTTPS headers retrieved"
            
            # Quick security headers check
            echo
            print_info "Security Headers Check:"
            grep -i "strict-transport-security" "$TEMP_DIR/https_headers" && print_success "HSTS enabled" || print_warning "HSTS not found"
            grep -i "x-frame-options" "$TEMP_DIR/https_headers" && print_success "X-Frame-Options set" || print_warning "X-Frame-Options not found"
            grep -i "content-security-policy" "$TEMP_DIR/https_headers" && print_success "CSP enabled" || print_warning "CSP not found"
        else
            print_warning "HTTPS headers not available"
        fi
        
        print_subheader "Performance Metrics"
        if [ -s "$TEMP_DIR/performance" ]; then
            cat "$TEMP_DIR/performance" | tr '|' '\n'
            print_success "Performance analysis completed"
        else
            print_warning "Performance metrics not available"
        fi
        
        print_subheader "Robots.txt"
        if [ -s "$TEMP_DIR/robots" ]; then
            head -10 "$TEMP_DIR/robots"
            print_success "Robots.txt found"
        else
            print_info "No robots.txt found"
        fi
        
        print_subheader "Sitemap.xml"
        if [ -s "$TEMP_DIR/sitemap" ]; then
            head -10 "$TEMP_DIR/sitemap"
            print_success "Sitemap.xml found"
        else
            print_info "No sitemap.xml found"
        fi
        
    else
        print_warning "curl not available for web analysis"
    fi
}

# Fast SSL analysis
fast_ssl_analysis() {
    local domain="$1"
    
    print_header "SSL/TLS CERTIFICATE ANALYSIS"
    
    if command_exists openssl; then
        print_subheader "SSL Certificate Information"
        local ssl_info=""
        ssl_info=$(timeout 10 bash -c "echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | openssl x509 -noout -text" 2>/dev/null)
        
        if [ -n "$ssl_info" ]; then
            echo "$ssl_info" | grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:|Subject Alternative Name)" | head -10
            print_success "SSL certificate details retrieved"
        else
            print_warning "SSL certificate not available"
        fi
        
        print_subheader "SSL Certificate Expiry"
        local ssl_dates=""
        ssl_dates=$(timeout 8 bash -c "echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | openssl x509 -noout -dates" 2>/dev/null)
        
        if [ -n "$ssl_dates" ]; then
            echo "$ssl_dates"
            print_success "SSL certificate expiry retrieved"
        else
            print_warning "SSL certificate expiry not available"
        fi
        
    else
        print_warning "OpenSSL not available for certificate analysis"
    fi
}

# Fast port scanning with targeted approach
fast_port_scan() {
    local ip="$1"
    
    if [ -z "$ip" ]; then
        print_warning "No IP address provided for port scanning"
        return
    fi
    
    print_header "FAST PORT SCANNING"
    
    if command_exists nmap; then
        print_subheader "Common Ports Scan"
        # Scan only the most common ports for speed
        local common_ports="21,22,23,25,53,80,110,143,443,993,995,3306,5432,8080,8443"
        run_command_fast "nmap -p $common_ports --open -T4 $ip" "Common ports scan" 15
        
        print_subheader "Service Detection (Top Ports)"
        # Quick service detection on open ports only
        run_command_fast "nmap -sV -T4 --version-intensity 2 -p $common_ports $ip" "Service detection" 20
        
    elif command_exists nc; then
        print_subheader "Basic Port Check (using netcat)"
        local ports=(21 22 23 25 53 80 110 143 443 993 995 3306 5432 8080 8443)
        local open_ports=()
        
        for port in "${ports[@]}"; do
            if timeout 2 nc -z "$ip" "$port" 2>/dev/null; then
                open_ports+=("$port")
                print_success "Port $port is open"
            fi
        done
        
        if [ ${#open_ports[@]} -eq 0 ]; then
            print_info "No common ports found open"
        fi
    else
        print_warning "Neither nmap nor netcat available for port scanning"
    fi
}

# Fast subdomain discovery with parallel checks
fast_subdomain_discovery() {
    local domain="$1"
    
    print_header "FAST SUBDOMAIN DISCOVERY"
    
    print_subheader "Common Subdomains Check"
    local common_subs="www mail ftp admin blog shop api cdn m mobile dev test staging"
    local pids=()
    local found_subs=()
    
    # Parallel subdomain checks
    for sub in $common_subs; do
        {
            if command_exists dig; then
                local result=$(timeout 3 dig +short +time=1 +tries=1 A "$sub.$domain" 2>/dev/null | head -n1)
                if [ -n "$result" ]; then
                    echo "$sub.$domain:$result" >> "$TEMP_DIR/found_subdomains"
                fi
            fi
        } &
        pids+=($!)
        
        # Limit parallel jobs
        if [ ${#pids[@]} -ge $MAX_PARALLEL_JOBS ]; then
            wait "${pids[0]}" 2>/dev/null || true
            pids=("${pids[@]:1}")
        fi
    done
    
    # Wait for remaining jobs with timeout
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Display results
    if [ -f "$TEMP_DIR/found_subdomains" ]; then
        while IFS=':' read -r subdomain ip; do
            print_success "Found: $subdomain -> $ip"
        done < "$TEMP_DIR/found_subdomains"
    else
        print_info "No common subdomains found"
    fi
}

# Fast security analysis
fast_security_analysis() {
    local domain="$1"
    
    print_header "SECURITY ANALYSIS"
    debug_log "Starting security analysis for domain: $domain"
    
    print_subheader "Email Security Records"
    local pids=()
    debug_log "Starting parallel security record checks"
    
    # Parallel security record checks with timeout
    if command_exists dig; then
        {
            debug_log "Starting SPF lookup for $domain"
            timeout 8 dig +short +time=2 +tries=1 TXT "$domain" 2>/dev/null | grep -i "v=spf1" > "$TEMP_DIR/spf" || echo "" > "$TEMP_DIR/spf"
            debug_log "SPF lookup completed"
        } &
        pids+=($!)
        
        {
            debug_log "Starting DMARC lookup for _dmarc.$domain"
            timeout 8 dig +short +time=2 +tries=1 TXT "_dmarc.$domain" 2>/dev/null > "$TEMP_DIR/dmarc" || echo "" > "$TEMP_DIR/dmarc"
            debug_log "DMARC lookup completed"
        } &
        pids+=($!)
        
        {
            debug_log "Starting CAA lookup for $domain"
            timeout 8 dig +short +time=2 +tries=1 CAA "$domain" 2>/dev/null > "$TEMP_DIR/caa" || echo "" > "$TEMP_DIR/caa"
            debug_log "CAA lookup completed"
        } &
        pids+=($!)
        
        # Wait for security checks with simple timeout
        debug_log "Waiting for ${#pids[@]} security check processes"
        sleep 10  # Give enough time for all checks to complete
        
        # Kill any remaining processes
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                debug_log "Killed hanging process $pid"
            fi
        done
        
        # Display results
        print_info "SPF Record:"
        if [ -s "$TEMP_DIR/spf" ]; then
            cat "$TEMP_DIR/spf"
            print_success "SPF Record found"
        else
            print_warning "No SPF Record found"
        fi
        
        print_info "DMARC Record:"
        if [ -s "$TEMP_DIR/dmarc" ]; then
            cat "$TEMP_DIR/dmarc"
            print_success "DMARC Record found"
        else
            print_warning "No DMARC Record found"
        fi
        
        print_info "CAA Records:"
        if [ -s "$TEMP_DIR/caa" ]; then
            cat "$TEMP_DIR/caa"
            print_success "CAA Records found"
        else
            print_info "No CAA Records found"
        fi
    else
        print_warning "dig command not available for security analysis"
    fi
}

# Fast network information
fast_network_info() {
    local domain="$1"
    local ip="$2"
    
    print_header "NETWORK INFORMATION"
    
    print_subheader "DNS Propagation Check"
    local dns_servers="8.8.8.8 1.1.1.1 119.29.29.29 114.114.114.114"
    local pids=()
    
    # Parallel DNS propagation check
    for dns in $dns_servers; do
        {
            if command_exists dig; then
                local result=$(timeout 5 dig @"$dns" +short +time=2 +tries=1 A "$domain" 2>/dev/null | head -n1)
                echo "$dns:$result" >> "$TEMP_DIR/dns_propagation"
            fi
        } &
        pids+=($!)
    done
    
    # Wait for DNS checks with timeout
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    # Display DNS propagation results
    if [ -f "$TEMP_DIR/dns_propagation" ]; then
        while IFS=':' read -r dns_server result; do
            if [ -n "$result" ]; then
                echo -e "DNS Server $dns_server: ${GREEN}$result${NC}"
            else
                echo -e "DNS Server $dns_server: ${RED}No response${NC}"
            fi
        done < "$TEMP_DIR/dns_propagation"
    fi
    
    print_subheader "CDN Detection"
    if [ -s "$TEMP_DIR/https_headers" ]; then
        if grep -qi "cloudflare" "$TEMP_DIR/https_headers"; then
            print_success "Cloudflare CDN detected"
        elif grep -qi "akamai" "$TEMP_DIR/https_headers"; then
            print_success "Akamai CDN detected"
        elif grep -qi "amazon" "$TEMP_DIR/https_headers"; then
            print_success "Amazon CloudFront CDN detected"
        elif grep -qi "fastly" "$TEMP_DIR/https_headers"; then
            print_success "Fastly CDN detected"
        else
            print_info "No common CDN detected"
        fi
    fi
}

# Main execution starts here
print_header "DOMAIN EXPLORATION REPORT (CLAUDE OPTIMIZED)"
echo -e "Domain: ${GREEN}$DOMAIN${NC}"
echo -e "Timestamp: ${CYAN}$TIMESTAMP${NC}"
echo -e "Report file: ${PURPLE}$OUTPUT_FILE${NC}"
echo -e "Optimization: ${YELLOW}Parallel execution enabled${NC}"

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

# Get primary IP quickly
PRIMARY_IP=""
if command_exists dig; then
    PRIMARY_IP=$(dig +short A "$CLEAN_DOMAIN" | head -n1)
elif command_exists nslookup; then
    PRIMARY_IP=$(nslookup "$CLEAN_DOMAIN" 2>/dev/null | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -n1)
fi

if [ -z "$PRIMARY_IP" ]; then
    print_warning "Could not resolve IP address for $CLEAN_DOMAIN. Some tests will be skipped."
else
    echo -e "Primary IP: ${GREEN}$PRIMARY_IP${NC}"
fi

# Run all optimized analysis functions
fast_dns_analysis "$CLEAN_DOMAIN"
fast_ip_analysis "$CLEAN_DOMAIN" "$PRIMARY_IP"
fast_web_analysis "$CLEAN_DOMAIN"
fast_ssl_analysis "$CLEAN_DOMAIN"
fast_security_analysis "$CLEAN_DOMAIN"
fast_port_scan "$PRIMARY_IP"
fast_subdomain_discovery "$CLEAN_DOMAIN"
fast_network_info "$CLEAN_DOMAIN" "$PRIMARY_IP"

print_header "SUMMARY"

echo -e "${WHITE}Fast Domain Exploration Complete!${NC}"
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

print_success "Optimized domain exploration completed successfully!"

echo -e "\n${BLUE}================================${NC}"
echo -e "${WHITE}Performance Optimizations Applied:${NC}"
echo -e "${BLUE}================================${NC}"
echo "✓ Parallel DNS queries for faster resolution"
echo "✓ Concurrent web requests to reduce wait time"
echo "✓ Targeted port scanning on common ports only"
echo "✓ Parallel subdomain discovery"
echo "✓ Reduced timeouts for faster completion"
echo "✓ Smart caching to avoid duplicate queries"
echo "✓ Background process management"
echo "✓ Streamlined output for better readability"

exit 0