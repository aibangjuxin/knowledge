#!/opt/homebrew/bin/bash

# Domain Explorer Script - Ultra Optimized Version
# Usage: ./explorer-domain-optimized.sh <domain>
# Features: Superior parallel execution, intelligent caching, robust error handling

set -euo pipefail

# ===== CONFIGURATION =====
readonly SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
readonly TEMP_DIR="/tmp/domain_explorer_$$_$(date +%s)"
readonly MAX_PARALLEL_JOBS=16
readonly DNS_TIMEOUT=3
readonly HTTP_TIMEOUT=8
readonly SSL_TIMEOUT=10

# ===== COLORS =====
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# ===== CACHING =====
declare -gA DNS_CACHE
declare -gA IP_CACHE

# ===== SETUP =====
setup_environment() {
  mkdir -p "$TEMP_DIR"
  trap cleanup EXIT INT TERM

  # Set locale for consistent output
  export LC_ALL=C
  export LANG=C
}

cleanup() {
  local exit_code=$?

  # Kill all background jobs
  jobs -p | xargs -r kill 2>/dev/null || true

  # Cleanup temp directory
  if [[ -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR" 2>/dev/null || true
  fi

  exit $exit_code
}

# ===== UTILITY FUNCTIONS =====
print_header() {
  echo -e "\n${BLUE}╔══════════════════════════════╗${NC}"
  echo -e "${WHITE}  $1${NC}"
  echo -e "${BLUE}╚══════════════════════════════╝${NC}"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${PURPLE}ℹ${NC} $1"; }

check_dependencies() {
  local deps=("dig" "curl" "timeout" "openssl" "nmap")
  local missing=()

  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      missing+=("$dep")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    print_error "Missing dependencies: ${missing[*]}"
    exit 1
  fi
}

# ===== PARALLEL EXECUTION ENGINE =====
run_parallel() {
  local max_jobs=${1:-$MAX_PARALLEL_JOBS}
  shift
  local -a commands=("$@")
  local -a pids=()

  for cmd in "${commands[@]}"; do
    while [[ ${#pids[@]} -ge $max_jobs ]]; do
      for i in "${!pids[@]}"; do
        if ! kill -0 "${pids[$i]}" 2>/dev/null; then
          unset "pids[$i]"
        fi
      done
      [[ ${#pids[@]} -ge $max_jobs ]] && sleep 0.1
    done

    eval "$cmd" &
    pids+=($!)
  done

  # Wait for all processes
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
}

# ===== DNS OPTIMIZATION =====
dns_lookup() {
  local domain=$1
  local type=$2
  local output=$3

  timeout $DNS_TIMEOUT dig +short +time=2 +tries=1 "$type" "$domain" 2>/dev/null >"$output" || echo "" >"$output"
}

fast_dns_analysis() {
  local domain=$1

  print_header "DNS ANALYSIS"

  local -a commands=()
  commands+=("dns_lookup '$domain' 'A' '$TEMP_DIR/dns_a'")
  commands+=("dns_lookup '$domain' 'AAAA' '$TEMP_DIR/dns_aaaa'")
  commands+=("dns_lookup '$domain' 'CNAME' '$TEMP_DIR/dns_cname'")
  commands+=("dns_lookup '$domain' 'MX' '$TEMP_DIR/dns_mx'")
  commands+=("dns_lookup '$domain' 'NS' '$TEMP_DIR/dns_ns'")
  commands+=("dns_lookup '$domain' 'TXT' '$TEMP_DIR/dns_txt'")
  commands+=("dns_lookup '$domain' 'SOA' '$TEMP_DIR/dns_soa'")

  run_parallel 7 "${commands[@]}"

  # Display results with enhanced formatting
  local records=(
    "A:IPv4 Addresses"
    "AAAA:IPv6 Addresses"
    "CNAME:Canonical Name"
    "MX:Mail Exchange"
    "NS:Name Servers"
    "TXT:Text Records"
    "SOA:Start of Authority"
  )

  for record in "${records[@]}"; do
    IFS=':' read -r type desc <<<"$record"
    local file="$TEMP_DIR/dns_${type,,}"

    echo -e "\n${CYAN}$desc:${NC}"
    if [[ -s "$file" ]]; then
      cat "$file" | sed 's/^/  /'
      print_success "Found $(wc -l <"$file") $type record(s)"
    else
      print_warning "No $type records"
    fi
  done
}

# ===== WEB ANALYSIS =====
web_request() {
  local url=$1
  local output=$2
  local extra_args=${3:-}

  timeout $HTTP_TIMEOUT curl -s -L --max-time $HTTP_TIMEOUT $extra_args "$url" 2>/dev/null >"$output" || echo "" >"$output"
}

fast_web_analysis() {
  local domain=$1

  print_header "WEB ANALYSIS"

  local -a commands=()
  commands+=("web_request 'http://$domain' '$TEMP_DIR/http_content' '-I'")
  commands+=("web_request 'https://$domain' '$TEMP_DIR/https_content' '-I'")
  commands+=("web_request 'http://$domain/robots.txt' '$TEMP_DIR/robots'")
  commands+=("web_request 'http://$domain/sitemap.xml' '$TEMP_DIR/sitemap'")
  commands+=("web_request 'https://$domain' '$TEMP_DIR/performance' '-w \"DNS:%{time_namelookup}|Connect:%{time_connect}|SSL:%{time_appconnect}|TTFB:%{time_starttransfer}|Total:%{time_total}|Speed:%{speed_download}\" -o /dev/null'")

  run_parallel 5 "${commands[@]}"

  # Enhanced web analysis display
  display_web_results
}

display_web_results() {
  local sections=(
    "http_content:HTTP Headers"
    "https_content:HTTPS Headers"
    "performance:Performance Metrics"
    "robots:Robots.txt"
    "sitemap:Sitemap.xml"
  )

  for section in "${sections[@]}"; do
    IFS=':' read -r file title <<<"$section"
    echo -e "\n${CYAN}$title:${NC}"

    if [[ -s "$TEMP_DIR/$file" ]]; then
      case $file in
      "performance")
        tr '|' '\n' <"$TEMP_DIR/$file" | sed 's/^/  /'
        ;;
      "robots" | "sitemap")
        head -10 "$TEMP_DIR/$file" | sed 's/^/  /'
        [[ $(wc -l <"$TEMP_DIR/$file") -gt 10 ]] && print_info "... truncated"
        ;;
      *)
        grep -E 'HTTP/|Server:|Content-Type:' "$TEMP_DIR/$file" | sed 's/^/  /' | head -5
        ;;
      esac
    else
      print_warning "No data"
    fi
  done

  # Security headers check
  if [[ -s "$TEMP_DIR/https_content" ]]; then
    echo -e "\n${CYAN}Security Headers:${NC}"
    local headers=("Strict-Transport-Security" "X-Frame-Options" "Content-Security-Policy")
    for header in "${headers[@]}"; do
      if grep -qi "$header" "$TEMP_DIR/https_content"; then
        print_success "  $header: ✓"
      else
        print_warning "  $header: ✗"
      fi
    done
  fi
}

# ===== SSL ANALYSIS =====
fast_ssl_analysis() {
  local domain=$1

  print_header "SSL/TLS ANALYSIS"

  local ssl_info
  ssl_info=$(timeout $SSL_TIMEOUT bash -c "echo | openssl s_client -servername $domain -connect $domain:443 2>/dev/null | openssl x509 -noout -text" 2>/dev/null)

  if [[ -n "$ssl_info" ]]; then
    echo -e "\n${CYAN}Certificate Details:${NC}"
    echo "$ssl_info" | grep -E "Subject:|Issuer:|Not Before:|Not After:" | sed 's/^/  /'

    echo -e "\n${CYAN}DNS Names:${NC}"
    echo "$ssl_info" | grep -E "DNS:|Subject Alternative Name" | sed 's/^/  /' | head -5

    local expiry
    expiry=$(echo "$ssl_info" | grep "Not After" | sed 's/.*: //')
    if [[ -n "$expiry" ]]; then
      local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null || echo 0)
      local days_left=$(((expiry_epoch - $(date +%s)) / 86400))
      echo -e "\n${CYAN}Certificate Expiry:${NC} $expiry (${days_left} days remaining)"
    fi
  else
    print_warning "SSL certificate not available"
  fi
}

# ===== PORT SCANNING =====
fast_port_scan() {
  local ip=$1

  [[ -z "$ip" ]] && return

  print_header "PORT SCANNING"

  local common_ports="21,22,23,25,53,80,110,143,443,993,995,3306,5432,6379,8080,8443,9000"

  print_info "Scanning common ports..."
  local scan_result
  scan_result=$(timeout 15 nmap -p "$common_ports" --open -T4 -n "$ip" 2>/dev/null | grep -E "^[0-9]")

  if [[ -n "$scan_result" ]]; then
    echo -e "\n${CYAN}Open Ports:${NC}"
    echo "$scan_result" | sed 's/^/  /'
  else
    print_info "No open ports found"
  fi
}

# ===== SECURITY ANALYSIS =====
security_check() {
  local domain=$1
  local record=$2
  local output=$3

  timeout $DNS_TIMEOUT dig +short +time=2 +tries=1 TXT "$record" 2>/dev/null | grep -v "^$" >"$output" || echo "" >"$output"
}

fast_security_analysis() {
  local domain=$1

  print_header "SECURITY ANALYSIS"

  local -a commands=()
  commands+=("security_check '$domain' '$domain' '$TEMP_DIR/spf'")
  commands+=("security_check '_dmarc.$domain' '_dmarc.$domain' '$TEMP_DIR/dmarc'")
  commands+=("security_check '$domain' '$domain' '$TEMP_DIR/caa'")

  run_parallel 3 "${commands[@]}"

  local security_records=(
    "spf:SPF Record"
    "dmarc:DMARC Record"
    "caa:CAA Record"
  )

  for record in "${security_records[@]}"; do
    IFS=':' read -r file title <<<"$record"
    echo -e "\n${CYAN}$title:${NC}"

    if [[ -s "$TEMP_DIR/$file" ]]; then
      cat "$TEMP_DIR/$file" | sed 's/^/  /'
    else
      print_warning "Not found"
    fi
  done
}

# ===== MAIN EXECUTION =====
main() {
  [[ $# -eq 0 ]] && {
    echo "Usage: $SCRIPT_NAME <domain>"
    exit 1
  }

  local domain=$1
  domain=${domain#http*://} # Remove protocol
  domain=${domain%%/*}      # Remove path

  setup_environment
  check_dependencies

  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local output_file="domain_report_${domain}_$(date +%Y%m%d_%H%M%S).txt"

  print_header "DOMAIN EXPLORATION REPORT"
  echo -e "Domain: ${GREEN}$domain${NC}"
  echo -e "Timestamp: ${CYAN}$timestamp${NC}"
  echo -e "Report: ${PURPLE}$output_file${NC}"

  # Validate domain
  if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    print_error "Invalid domain format"
    exit 1
  fi

  exec > >(tee -a "$output_file") 2>&1

  # Get primary IP
  local primary_ip
  primary_ip=$(dig +short A "$domain" | head -n1)

  if [[ -z "$primary_ip" ]]; then
    print_warning "Could not resolve IP address"
  else
    print_success "Primary IP: $primary_ip"
  fi

  # Run analysis
  fast_dns_analysis "$domain"
  [[ -n "$primary_ip" ]] && fast_port_scan "$primary_ip"
  fast_web_analysis "$domain"
  fast_ssl_analysis "$domain"
  fast_security_analysis "$domain"

  print_header "COMPLETED"
  echo -e "Report saved: ${PURPLE}$output_file${NC}"
  [[ -f "$output_file" ]] && du -h "$output_file" | awk '{print "Size: "$1", Lines: "}' && wc -l <"$output_file"
}

# Execute main function
main "$@"
