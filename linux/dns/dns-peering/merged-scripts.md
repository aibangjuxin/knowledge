# Shell Scripts Collection

Generated on: 2026-01-01 19:10:59
Directory: /Users/lex/git/knowledge/dns/dns-peering

## `verify-pub-priv-ip.sh`

```bash
#!/usr/bin/env bash

# verify-pub-priv-ip.sh
# Purpose: Verify domain resolution across multiple DNS servers and determine if IP is public/private.
# Enhanced from: verify-dns-fqdn.sh with output flags for programmatic use.

# --- Configuration ---

# DNS Servers to query
declare -A DNS_SERVERS=(
  ["8.8.8.8"]="Google Public DNS"
  ["119.29.29.29"]="Tencent DNSPod"
  ["114.114.114.114"]="114 DNS"
  ["223.5.5.5"]="Ali DNS"
)

# DNS Peering list
DNS_PEERING=(
  "baidu.com"
  "sohu.com"
  "internal.lan"
)

# Query Parameters
TIMEOUT=2
TRIES=2

# ANSI color codes
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RED='\033[31m'
NC='\033[0m'
BOLD='\033[1m'
SEPARATOR="----------------------------------------------------------------"

# Output format flags
OUTPUT_FORMAT="normal"  # normal, json, short

# --- Functions ---

# Function to check if domain is in Peering list
check_domain_in_peering() {
  local input_domain="$1"
  for peering_domain in "${DNS_PEERING[@]}"; do
    if [[ "$input_domain" == *"$peering_domain" ]]; then
      return 0 # Match found
    fi
  done
  return 1 # No match found
}

# Function to determine IP type (RFC1918)
get_ip_type() {
  local ip="$1"
  local a b c d
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unknown"
    return
  fi
  IFS='.' read -r a b c d <<< "$ip"
  
  # RFC1918 Ranges
  # 10.0.0.0/8
  if [[ "$a" -eq 10 ]]; then
    echo "Private"
    return
  fi
  # 172.16.0.0/12
  if [[ "$a" -eq 172 && "$b" -ge 16 && "$b" -le 31 ]]; then
    echo "Private"
    return
  fi
  # 192.168.0.0/16
  if [[ "$a" -eq 192 && "$b" -eq 168 ]]; then
    echo "Private"
    return
  fi
  # 127.0.0.0/8 (Loopback)
  if [[ "$a" -eq 127 ]]; then
    echo "Local"
    return
  fi
  # 169.254.0.0/16 (Link-local)
  if [[ "$a" -eq 169 && "$b" -eq 254 ]]; then
    echo "Local"
    return
  fi
  
  echo "Public"
}

# --- Execution ---

# Parse command line arguments
if [ $# -lt 1 ]; then
  echo -e "${RED}Usage: $0 <domain> [--json|--short]${NC}" >&2
  echo "Example: $0 www.baidu.com" >&2
  echo "Example: $0 www.baidu.com --short" >&2
  echo "Example: $0 www.baidu.com --json" >&2
  exit 1
fi

DOMAIN="$1"
[[ "$2" == "--json" ]] && OUTPUT_FORMAT="json"
[[ "$2" == "--short" ]] && OUTPUT_FORMAT="short"

# If normal output format, show the full report
if [[ "$OUTPUT_FORMAT" == "normal" ]]; then
  echo -e "\n${BOLD}DNS Verification Report for: ${BLUE}${DOMAIN}${NC}"
  echo -e "${SEPARATOR}"
  
  # Step 1: Peering Check
  if check_domain_in_peering "$DOMAIN"; then
    echo -e "Peering Status: ${GREEN}✅ Matched (In Peering List)${NC}"
    peering_matched=true
  else
    echo -e "Peering Status: ${YELLOW}ℹ️  Unmatched (Not in Peering List)${NC}"
    peering_matched=false
  fi
fi

# Arrays to store results for summary
declare -A SERVER_RESULTS
declare -A SERVER_IPS
declare -a RESULT_ARRAY

# Step 2: Query Each DNS Server
for dns in "${!DNS_SERVERS[@]}"; do
  desc="${DNS_SERVERS[$dns]}"
  
  # Execute dig
  result=$(dig @"$dns" "$DOMAIN" +noall +answer +time=${TIMEOUT} +tries=${TRIES} 2>/dev/null)
  exit_code=$?

  if [ $exit_code -ne 0 ]; then
    SERVER_RESULTS["$dns"]="FAILED"
    continue
  fi

  if [ -z "$result" ]; then
    SERVER_RESULTS["$dns"]="NO_RECORD"
    continue
  fi

  # Extract IPs and determine types
  ips=$(echo "$result" | grep -E "[[:space:]]A[[:space:]]" | awk '{print $NF}')
  if [ -z "$ips" ]; then
    SERVER_RESULTS["$dns"]="NO_A_RECORD"
    continue
  fi

  # Detailed logging during execution (only for normal output)
  if [[ "$OUTPUT_FORMAT" == "normal" ]]; then
    echo -e "\n${BLUE}➤ Querying $dns ($desc)${NC}"
  fi
  
  types=()
  ip_list=()
  for ip in $ips; do
    ip_type=$(get_ip_type "$ip")
    ip_list+=("$ip")
    types+=("$ip_type")
    
    if [[ "$OUTPUT_FORMAT" == "normal" ]]; then
      color=$GREEN
      [[ "$ip_type" == "Private" ]] && color=$YELLOW
      [[ "$ip_type" == "Local" ]] && color=$BLUE
      echo -e "  - $ip ${color}[$ip_type]${NC}"
    fi
  done
  
  # Summarize results for this server
  # If any IP is public, mark as PUBLIC, else if any is private, mark as PRIVATE
  has_public=false
  has_private=false
  for t in "${types[@]}"; do
    [[ "$t" == "Public" ]] && has_public=true
    [[ "$t" == "Private" ]] && has_private=true
  done

  if $has_public; then
    SERVER_RESULTS["$dns"]="PUBLIC"
  elif $has_private; then
    SERVER_RESULTS["$dns"]="PRIVATE"
  else
    SERVER_RESULTS["$dns"]="OTHER"
  fi
  
  SERVER_IPS["$dns"]=$(echo "${ip_list[@]}" | tr ' ' ',')
  RESULT_ARRAY+=("${SERVER_RESULTS[$dns]}")
done

# Step 3: Determine Final Verdict
# Count results
public_count=0
private_count=0
for result in "${RESULT_ARRAY[@]}"; do
  [[ "$result" == "PUBLIC" ]] && ((public_count++))
  [[ "$result" == "PRIVATE" ]] && ((private_count++))
done

# Final decision logic: if any server returns PUBLIC, verdict is PUBLIC
if [[ $public_count -gt 0 ]]; then
  FINAL_VERDICT="PUBLIC"
  exit_code=0
elif [[ $private_count -gt 0 ]]; then
  FINAL_VERDICT="PRIVATE"
  exit_code=1
else
  FINAL_VERDICT="UNKNOWN"
  exit_code=2
fi

# Step 4: Output based on format
case "$OUTPUT_FORMAT" in
  "short")
    echo "$FINAL_VERDICT"
    exit $exit_code
    ;;
  "json")
    # Build JSON results object
    json_results="{"
    first=true
    for dns in "${!DNS_SERVERS[@]}"; do
      [[ $first == true ]] && first=false || json_results="${json_results},"
      json_results="${json_results}\"${dns}\": {\"description\": \"${DNS_SERVERS[$dns]}\", \"result\": \"${SERVER_RESULTS[$dns]}\", \"ips\": \"${SERVER_IPS[$dns]}\"}"
    done
    json_results="${json_results}}"
    
    # Determine peering status
    if check_domain_in_peering "$DOMAIN"; then
      peering_status="MATCHED"
    else
      peering_status="UNMATCHED"
    fi
    
    # Output as JSON
    cat <<EOF
{
  "domain": "$DOMAIN",
  "peering_status": "$peering_status",
  "verdict": "$FINAL_VERDICT",
  "results": $json_results,
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF
    exit $exit_code
    ;;
  *)
    # Normal formatted output
    # Step 3: Final Summary Table
    echo -e "\n\n${BOLD}SUMMARY TABLE${NC}"
    echo -e "${SEPARATOR}"
    printf "%-18s | %-15s | %-12s | %s\n" "DNS Server" "Description" "Result" "Resolved IPs"
    echo -e "${SEPARATOR}"
    
    for dns in "${!DNS_SERVERS[@]}"; do
      desc="${DNS_SERVERS[$dns]}"
      res="${SERVER_RESULTS[$dns]}"
      ips="${SERVER_IPS[$dns]}"
      
      res_color=$NC
      case "$res" in
        "PUBLIC") res_color=$GREEN ;;
        "PRIVATE") res_color=$YELLOW ;;
        "FAILED") res_color=$RED ;;
        "NO_RECORD"|"NO_A_RECORD") res_color=$RED ; res="EMPTY" ;;
      esac
      
      printf "%-18s | %-15s | ${res_color}%-12s${NC} | %s\n" "$dns" "$desc" "$res" "$ips"
    done
    
    echo -e "${SEPARATOR}"
    echo -e "${BOLD}Final Verdict: ${FINAL_VERDICT}${NC}"
    echo -e "✅ Check completed at $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${SEPARATOR}\n"
    exit $exit_code
    ;;
esac

```

## `verify-dns-fqdn.sh`

```bash
#!/usr/bin/env bash

# verify-dns-fqdn.sh
# Purpose: Verify domain resolution across multiple DNS servers and check against Peering list.
# Merged from: dns-peering-eng.sh and dns-fqdn-verify.sh

# --- Configuration ---

# DNS Servers to query
declare -A DNS_SERVERS=(
  ["8.8.8.8"]="Google Public DNS"
  ["119.29.29.29"]="Tencent DNSPod"
  ["114.114.114.114"]="114 DNS"
  ["223.5.5.5"]="Ali DNS"
)

# DNS Peering list
DNS_PEERING=(
  "baidu.com"
  "sohu.com"
  "internal.lan"
)

# Query Parameters
TIMEOUT=2
TRIES=2

# ANSI color codes
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RED='\033[31m'
NC='\033[0m'
BOLD='\033[1m'
SEPARATOR="----------------------------------------------------------------"

# --- Functions ---

# Function to check if domain is in Peering list
check_domain_in_peering() {
  local input_domain="$1"
  for peering_domain in "${DNS_PEERING[@]}"; do
    if [[ "$input_domain" == *"$peering_domain" ]]; then
      return 0 # Match found
    fi
  done
  return 1 # No match found
}

# Function to determine IP type (RFC1918)
get_ip_type() {
  local ip="$1"
  local a b c d
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unknown"
    return
  fi
  IFS='.' read -r a b c d <<< "$ip"
  
  # RFC1918 Ranges
  # 10.0.0.0/8
  if [[ "$a" -eq 10 ]]; then
    echo "Private"
    return
  fi
  # 172.16.0.0/12
  if [[ "$a" -eq 172 && "$b" -ge 16 && "$b" -le 31 ]]; then
    echo "Private"
    return
  fi
  # 192.168.0.0/16
  if [[ "$a" -eq 192 && "$b" -eq 168 ]]; then
    echo "Private"
    return
  fi
  # 127.0.0.0/8 (Loopback)
  if [[ "$a" -eq 127 ]]; then
    echo "Local"
    return
  fi
  # 169.254.0.0/16 (Link-local)
  if [[ "$a" -eq 169 && "$b" -eq 254 ]]; then
    echo "Local"
    return
  fi
  
  echo "Public"
}

# --- Execution ---

# Check if domain parameter is provided
if [ $# -ne 1 ]; then
  echo -e "${RED}Usage: $0 <domain>${NC}"
  echo "Example: $0 www.baidu.com"
  exit 1
fi

DOMAIN=$1

echo -e "\n${BOLD}DNS Verification Report for: ${BLUE}${DOMAIN}${NC}"
echo -e "${SEPARATOR}"

# Step 1: Peering Check
if check_domain_in_peering "$DOMAIN"; then
  echo -e "Peering Status: ${GREEN}✅ Matched (In Peering List)${NC}"
else
  echo -e "Peering Status: ${YELLOW}ℹ️  Unmatched (Not in Peering List)${NC}"
fi

# Arrays to store results for summary
declare -A SERVER_RESULTS
declare -A SERVER_IPS

# Step 2: Query Each DNS Server
for dns in "${!DNS_SERVERS[@]}"; do
  desc="${DNS_SERVERS[$dns]}"
  
  # Execute dig
  result=$(dig @"$dns" "$DOMAIN" +noall +answer +time=${TIMEOUT} +tries=${TRIES} 2>/dev/null)
  exit_code=$?

  if [ $exit_code -ne 0 ]; then
    SERVER_RESULTS["$dns"]="FAILED"
    continue
  fi

  if [ -z "$result" ]; then
    SERVER_RESULTS["$dns"]="NO_RECORD"
    continue
  fi

  # Extract IPs and determine types
  ips=$(echo "$result" | grep -E "[[:space:]]A[[:space:]]" | awk '{print $NF}')
  if [ -z "$ips" ]; then
    SERVER_RESULTS["$dns"]="NO_A_RECORD"
    continue
  fi

  # Detailed logging during execution
  echo -e "\n${BLUE}➤ Querying $dns ($desc)${NC}"
  
  types=()
  ip_list=()
  for ip in $ips; do
    ip_type=$(get_ip_type "$ip")
    ip_list+=("$ip")
    types+=("$ip_type")
    
    color=$GREEN
    [[ "$ip_type" == "Private" ]] && color=$YELLOW
    [[ "$ip_type" == "Local" ]] && color=$BLUE
    
    echo -e "  - $ip ${color}[$ip_type]${NC}"
  done
  
  # Summarize results for this server
  # If any IP is public, mark as PUBLIC, else if any is private, mark as PRIVATE
  has_public=false
  has_private=false
  for t in "${types[@]}"; do
    [[ "$t" == "Public" ]] && has_public=true
    [[ "$t" == "Private" ]] && has_private=true
  done

  if $has_public; then
    SERVER_RESULTS["$dns"]="PUBLIC"
  elif $has_private; then
    SERVER_RESULTS["$dns"]="PRIVATE"
  else
    SERVER_RESULTS["$dns"]="OTHER"
  fi
  
  SERVER_IPS["$dns"]=$(echo "${ip_list[@]}" | tr ' ' ',')
done

# Step 3: Final Summary Table
echo -e "\n\n${BOLD}SUMMARY TABLE${NC}"
echo -e "${SEPARATOR}"
printf "%-18s | %-15s | %-12s | %s\n" "DNS Server" "Description" "Result" "Resolved IPs"
echo -e "${SEPARATOR}"

for dns in "${!DNS_SERVERS[@]}"; do
  desc="${DNS_SERVERS[$dns]}"
  res="${SERVER_RESULTS[$dns]}"
  ips="${SERVER_IPS[$dns]}"
  
  res_color=$NC
  case "$res" in
    "PUBLIC") res_color=$GREEN ;;
    "PRIVATE") res_color=$YELLOW ;;
    "FAILED") res_color=$RED ;;
    "NO_RECORD"|"NO_A_RECORD") res_color=$RED ; res="EMPTY" ;;
  esac
  
  printf "%-18s | %-15s | ${res_color}%-12s${NC} | %s\n" "$dns" "$desc" "$res" "$ips"
done

echo -e "${SEPARATOR}"
echo -e "✅ Check completed at $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${SEPARATOR}\n"

```

## `dns-fqdn-verify.sh`

```bash
#!/opt/homebrew/bin/bash

# DNS FQDN Verification Script
# Purpose: Verify domain ownership by determining if the resolved IP is private or public
# Returns: 0 for public IP (internet-accessible), 1 for private IP (internal), 2 for query failure

set -o pipefail

# Check if domain parameter is provided
if [ $# -lt 1 ]; then
  echo "Usage: $0 <domain> [dns_server]" >&2
  echo "Example: $0 www.baidu.com 8.8.8.8" >&2
  exit 2
fi

DOMAIN=$1
DNS_SERVER=${2:-"8.8.8.8"}  # Default to Google DNS

# Query Parameters
TIMEOUT=2
TRIES=2

# ANSI color codes
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m'

# Function to determine IP type (RFC1918)
# Returns: "Private" or "Public"
get_ip_type() {
  local ip="$1"
  local a b c d
  
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unknown"
    return 1
  fi
  
  IFS='.' read -r a b c d <<< "$ip"
  
  # RFC1918 Private Ranges
  # 10.0.0.0/8
  if [[ "$a" -eq 10 ]]; then
    echo "Private"
    return 0
  fi
  
  # 172.16.0.0/12
  if [[ "$a" -eq 172 && "$b" -ge 16 && "$b" -le 31 ]]; then
    echo "Private"
    return 0
  fi
  
  # 192.168.0.0/16
  if [[ "$a" -eq 192 && "$b" -eq 168 ]]; then
    echo "Private"
    return 0
  fi
  
  # 127.0.0.0/8 (Loopback)
  if [[ "$a" -eq 127 ]]; then
    echo "Private"
    return 0
  fi
  
  # 169.254.0.0/16 (Link-local)
  if [[ "$a" -eq 169 && "$b" -eq 254 ]]; then
    echo "Private"
    return 0
  fi
  
  echo "Public"
  return 0
}

# Function to query DNS and extract A records
# Returns: space-separated list of IPs, or empty string if query fails
query_dns() {
  local domain="$1"
  local server="$2"
  
  result=$(dig @"$server" "$domain" +noall +answer +time=${TIMEOUT} +tries=${TRIES} 2>/dev/null)
  exit_code=$?
  
  if [ $exit_code -ne 0 ]; then
    return 1
  fi
  
  # Extract A record IPs
  echo "$result" | grep -E "[[:space:]]A[[:space:]]" | awk '{print $NF}' | tr '\n' ' '
}

# Main verification logic
verify_domain() {
  local domain="$1"
  local server="$2"
  
  # Query DNS
  ips=$(query_dns "$domain" "$server")
  
  if [ $? -ne 0 ] || [ -z "$ips" ]; then
    echo -e "${RED}[ERROR]${NC} Failed to resolve domain: $domain using $server" >&2
    return 2
  fi
  
  echo -e "${GREEN}[INFO]${NC} Domain: $domain" >&2
  echo -e "${GREEN}[INFO]${NC} Resolved IPs: $ips" >&2
  
  # Check IP types
  local has_public=0
  local has_private=0
  
  for ip in $ips; do
    ip_type=$(get_ip_type "$ip")
    
    if [ "$ip_type" = "Private" ]; then
      has_private=1
      echo -e "${YELLOW}[PRIVATE]${NC} $ip" >&2
    elif [ "$ip_type" = "Public" ]; then
      has_public=1
      echo -e "${GREEN}[PUBLIC]${NC} $ip" >&2
    else
      echo -e "${RED}[UNKNOWN]${NC} $ip" >&2
    fi
  done
  
  # Determine ownership based on IP type
  # Return 0: domain is publicly accessible (has public IP)
  # Return 1: domain is internally hosted (only private IPs)
  # Return 2: query failed
  if [ $has_public -eq 1 ]; then
    echo -e "${GREEN}[VERDICT]${NC} Domain is publicly accessible" >&2
    return 0
  elif [ $has_private -eq 1 ]; then
    echo -e "${YELLOW}[VERDICT]${NC} Domain is internally hosted (private IP)" >&2
    return 1
  else
    echo -e "${RED}[ERROR]${NC} Unable to determine IP type" >&2
    return 2
  fi
}

# Execute verification
verify_domain "$DOMAIN" "$DNS_SERVER"
result=$?

# Output for conditional logic
case $result in
  0)
    echo "PUBLIC"
    exit 0
    ;;
  1)
    echo "PRIVATE"
    exit 1
    ;;
  *)
    echo "FAILED"
    exit 2
    ;;
esac

```

## `dns-query-eng.sh`

```bash
#!/opt/homebrew/bin/bash

# Check if domain parameter is provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <domain>"
  echo "Example: $0 www.baidu.com"
  exit 1
fi

# Define domain and DNS server list (using associative array)
DOMAIN=$1
declare -A DNS_SERVERS=(
  ["8.8.8.8"]="Google Public DNS"
  ["119.29.29.29"]="Tencent DNSPod"
  ["114.114.114.114"]="114 DNS"
)

# Define DNS Peering list (using array)
DNS_PEERING=(
  "baidu.com"
  "sohu.com"
)

# Function to check if domain is in Peering list
check_domain_in_peering() {
  local input_domain="$1"
  for peering_domain in "${DNS_PEERING[@]}"; do
    if [[ "$input_domain" == *"$peering_domain" ]]; then
      return 0 # Match found
    fi
  done
  return 1 # No match found
}

# Check if input domain is in Peering list
if check_domain_in_peering "$DOMAIN"; then
  echo -e "✅ Domain $DOMAIN is in DNS Peering list"
else
  echo -e "❌ Domain $DOMAIN is not in DNS Peering list"
fi

# Query Parameters
TIMEOUT=2
TRIES=2

# ANSI color codes
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RED='\033[31m'
NC='\033[0m'
SEPARATOR="================================================================"

# Function to determine IP type (RFC1918)
get_ip_type() {
  local ip="$1"
  local a b c d
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unknown"
    return
  fi
  IFS='.' read -r a b c d <<< "$ip"
  
  # RFC1918 Ranges
  # 10.0.0.0/8
  if [[ "$a" -eq 10 ]]; then
    echo "Private"
    return
  fi
  # 172.16.0.0/12
  if [[ "$a" -eq 172 && "$b" -ge 16 && "$b" -le 31 ]]; then
    echo "Private"
    return
  fi
  # 192.168.0.0/16
  if [[ "$a" -eq 192 && "$b" -eq 168 ]]; then
    echo "Private"
    return
  fi
  
  echo "Public"
}

# Query each DNS server
for dns in "${!DNS_SERVERS[@]}"; do
  echo -e "\n${SEPARATOR}"
  echo -e "🔍 Using DNS Server: ${BLUE}${dns}${NC} (${DNS_SERVERS[$dns]})"
  echo "${SEPARATOR}"

  # Execute dig command with timeout and retries
  result=$(dig @"$dns" "$DOMAIN" +noall +answer +authority +additional +time=${TIMEOUT} +tries=${TRIES})
  exit_code=$?

  if [ $exit_code -ne 0 ]; then
    echo -e "${RED}❌ Query failed (Exit Code: $exit_code). Server may be unreachable or timed out.${NC}"
    continue
  fi

  if [ -n "$result" ]; then
    echo -e "${GREEN}DNS records found:${NC}"
    # Process each line of the answer
    echo "$result" | while read -r line; do
      # Ignore comment lines
      [[ "$line" =~ ^\; ]] && continue
      [[ -z "$line" ]] && continue

      if [[ "$line" =~ [[:space:]]A[[:space:]]+([0-9.]+)$ ]]; then
        ip="${BASH_REMATCH[1]}"
        ip_type=$(get_ip_type "$ip")
        
        # Colorize type
        type_color=$GREEN
        [[ "$ip_type" == "Private" ]] && type_color=$YELLOW
        
        echo -e "${line}  -> ${type_color}[${ip_type}]${NC}"
      else
        echo "$line"
      fi
    done
  else
    echo "❌ Query failed or no results returned"
  fi
done

echo -e "\n${SEPARATOR}"
echo "✅ Query completed"

```

## `dns-peering-eng.sh`

```bash
#!/opt/homebrew/bin/bash

# Check if domain parameter is provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <domain>"
  echo "Example: $0 www.baidu.com"
  exit 1
fi

# Define domain and DNS server list (using associative array)
DOMAIN=$1
declare -A DNS_SERVERS=(
  ["8.8.8.8"]="Google Public DNS"
  ["119.29.29.29"]="Tencent DNSPod"
  ["114.114.114.114"]="114 DNS"
)

# Define DNS Peering list (using array)
DNS_PEERING=(
  "baidu.com"
  "sohu.com"
)

# Function to check if domain is in Peering list
check_domain_in_peering() {
  local input_domain="$1"
  for peering_domain in "${DNS_PEERING[@]}"; do
    if [[ "$input_domain" == *"$peering_domain" ]]; then
      return 0 # Match found
    fi
  done
  return 1 # No match found
}

# Check if input domain is in Peering list
if check_domain_in_peering "$DOMAIN"; then
  echo -e "✅ Domain $DOMAIN is in DNS Peering list"
else
  echo -e "❌ Domain $DOMAIN is not in DNS Peering list"
fi

# Query Parameters
TIMEOUT=2
TRIES=2

# ANSI color codes
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RED='\033[31m'
NC='\033[0m'
SEPARATOR="================================================================"

# Function to determine IP type (RFC1918)
get_ip_type() {
  local ip="$1"
  local a b c d
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unknown"
    return
  fi
  IFS='.' read -r a b c d <<< "$ip"
  
  # RFC1918 Ranges
  # 10.0.0.0/8
  if [[ "$a" -eq 10 ]]; then
    echo "Private"
    return
  fi
  # 172.16.0.0/12
  if [[ "$a" -eq 172 && "$b" -ge 16 && "$b" -le 31 ]]; then
    echo "Private"
    return
  fi
  # 192.168.0.0/16
  if [[ "$a" -eq 192 && "$b" -eq 168 ]]; then
    echo "Private"
    return
  fi
  
  echo "Public"
}

# Query each DNS server
for dns in "${!DNS_SERVERS[@]}"; do
  echo -e "\n${SEPARATOR}"
  echo -e "🔍 Using DNS Server: ${BLUE}${dns}${NC} (${DNS_SERVERS[$dns]})"
  echo "${SEPARATOR}"

  # Execute dig command with timeout and retries
  result=$(dig @"$dns" "$DOMAIN" +noall +answer +authority +additional +time=${TIMEOUT} +tries=${TRIES})
  exit_code=$?

  if [ $exit_code -ne 0 ]; then
    echo -e "${RED}❌ Query failed (Exit Code: $exit_code). Server may be unreachable or timed out.${NC}"
    continue
  fi

  if [ -n "$result" ]; then
    echo -e "${GREEN}DNS records found:${NC}"
    # Process each line of the answer
    echo "$result" | while read -r line; do
      # Ignore comment lines
      [[ "$line" =~ ^\; ]] && continue
      [[ -z "$line" ]] && continue

      if [[ "$line" =~ [[:space:]]A[[:space:]]+([0-9.]+)$ ]]; then
        ip="${BASH_REMATCH[1]}"
        ip_type=$(get_ip_type "$ip")
        
        # Colorize type
        type_color=$GREEN
        [[ "$ip_type" == "Private" ]] && type_color=$YELLOW
        
        echo -e "${line}  -> ${type_color}[${ip_type}]${NC}"
      else
        echo "$line"
      fi
    done
  else
    echo "❌ Query failed or no results returned"
  fi
done

echo -e "\n${SEPARATOR}"
echo "✅ Query completed"

```

## `dns-peering-claude.sh`

```bash
#!/opt/homebrew/bin/bash

# Check if domain parameter is provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <domain>"
  echo "Example: $0 www.baidu.com"
  exit 1
fi

# Define domain and DNS server list (using associative array)
DOMAIN=$1
declare -A DNS_SERVERS=(
  ["8.8.8.8"]="Google Public DNS"
  ["119.29.29.29"]="Tencent DNSPod"
  ["114.114.114.114"]="114 DNS"
)

# Define DNS Peering list (using array)
DNS_PEERING=(
  "baidu.com"
  "sohu.com"
)

# ANSI color codes
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLUE='\033[34m'
NC='\033[0m'
SEPARATOR="================================================================"

# Function to convert IP to decimal
ip_to_decimal() {
  local ip=$1
  local a b c d
  IFS=. read -r a b c d <<< "$ip"
  echo "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
}

# Function to check if IP is in CIDR range
ip_in_cidr() {
  local ip=$1
  local cidr=$2
  local network mask ip_decimal network_decimal
  
  network="${cidr%/*}"
  mask="${cidr#*/}"
  
  ip_decimal=$(ip_to_decimal "$ip")
  network_decimal=$(ip_to_decimal "$network")
  
  # Calculate network mask
  local mask_decimal=$(( (0xFFFFFFFF << (32 - mask)) & 0xFFFFFFFF ))
  
  # Check if IP is in range
  if [ $(( ip_decimal & mask_decimal )) -eq $(( network_decimal & mask_decimal )) ]; then
    return 0
  else
    return 1
  fi
}

# Function to determine IP address type
get_ip_type() {
  local ip=$1
  
  # RFC1918 Private IP ranges
  if ip_in_cidr "$ip" "10.0.0.0/8"; then
    echo "${RED}[Private - RFC1918: 10.0.0.0/8]${NC}"
    return
  fi
  
  if ip_in_cidr "$ip" "172.16.0.0/12"; then
    echo "${RED}[Private - RFC1918: 172.16.0.0/12]${NC}"
    return
  fi
  
  if ip_in_cidr "$ip" "192.168.0.0/16"; then
    echo "${RED}[Private - RFC1918: 192.168.0.0/16]${NC}"
    return
  fi
  
  # Loopback
  if ip_in_cidr "$ip" "127.0.0.0/8"; then
    echo "${YELLOW}[Loopback - RFC1122]${NC}"
    return
  fi
  
  # Link-local
  if ip_in_cidr "$ip" "169.254.0.0/16"; then
    echo "${YELLOW}[Link-Local - RFC3927]${NC}"
    return
  fi
  
  # Carrier-grade NAT (CGNAT)
  if ip_in_cidr "$ip" "100.64.0.0/10"; then
    echo "${YELLOW}[Shared Address Space - RFC6598 CGNAT]${NC}"
    return
  fi
  
  # Multicast
  if ip_in_cidr "$ip" "224.0.0.0/4"; then
    echo "${YELLOW}[Multicast - RFC5771]${NC}"
    return
  fi
  
  # Reserved
  if ip_in_cidr "$ip" "240.0.0.0/4"; then
    echo "${YELLOW}[Reserved - RFC1112]${NC}"
    return
  fi
  
  # Public IP
  echo "${GREEN}[Public IP]${NC}"
}

# Function to extract and classify IP addresses from DNS result
process_dns_result() {
  local result=$1
  
  # Extract A records (IPv4)
  local ips=$(echo "$result" | grep -E "^[^;].*\sA\s" | awk '{print $NF}')
  
  if [ -n "$ips" ]; then
    echo -e "${GREEN}DNS A records found:${NC}"
    while IFS= read -r line; do
      # Extract complete DNS record line
      local full_record=$(echo "$result" | grep -E "\s$line\s*$" | head -1)
      if [ -n "$full_record" ]; then
        local ip_type=$(get_ip_type "$line")
        echo -e "${GREEN}${full_record}${NC} ${ip_type}"
      fi
    done <<< "$ips"
    return 0
  else
    # If no A records, show other record types
    if [ -n "$result" ]; then
      echo -e "${BLUE}Other DNS records found:${NC}"
      echo -e "${BLUE}${result}${NC}"
      return 0
    fi
  fi
  
  return 1
}

# Function to check if domain is in Peering list
check_domain_in_peering() {
  local input_domain="$1"
  for peering_domain in "${DNS_PEERING[@]}"; do
    if [[ "$input_domain" == *"$peering_domain" ]]; then
      return 0
    fi
  done
  return 1
}

# Check if input domain is in Peering list
if check_domain_in_peering "$DOMAIN"; then
  echo -e "✅ Domain $DOMAIN is in DNS Peering list"
else
  echo -e "❌ Domain $DOMAIN is not in DNS Peering list"
fi

# Query each DNS server
for dns in "${!DNS_SERVERS[@]}"; do
  echo -e "\n${SEPARATOR}"
  echo -e "🔍 Using DNS Server: ${GREEN}${dns}${NC} (${DNS_SERVERS[$dns]})"
  echo "${SEPARATOR}"
  
  # Execute dig command and process output
  result=$(dig @"$dns" "$DOMAIN" +noall +answer +authority +additional)
  
  # Check if result exists
  if [ -n "$result" ]; then
    if ! process_dns_result "$result"; then
      echo "❌ No DNS records found"
    fi
  else
    echo "❌ Query failed or no results returned"
  fi
done

echo -e "\n${SEPARATOR}"
echo "✅ Query completed"

```

## `dns-query.sh`

```bash
#!/opt/homebrew/bin/bash

# 检查是否提供了域名参数
if [ $# -ne 1 ]; then
    echo "Usage: $0 <domain>"
    echo "Example: $0 www.baidu.com"
    exit 1
fi

# 定义域名和 DNS 服务器列表（使用关联数组）
DOMAIN=$1
declare -A DNS_SERVERS=(
    ["8.8.8.8"]="Google Public DNS"
    ["119.29.29.29"]="腾讯 DNSPod"
    ["114.114.114.114"]="114 DNS"
)

# 定义 DNS Peering 列表（使用普通数组）
DNS_PEERING=(
    "baidu.com"
    "sohu.com"
)

# 检查域名是否在 Peering 列表中的函数
check_domain_in_peering() {
    local input_domain="$1"
    for peering_domain in "${DNS_PEERING[@]}"; do
        if [[ "$input_domain" == *"$peering_domain" ]]; then
            return 0  # 找到匹配
        fi
    done
    return 1  # 未找到匹配
}

# 检查输入域名是否在 Peering 列表中
if check_domain_in_peering "$DOMAIN"; then
    echo -e "✅ 域名 $DOMAIN 属于 DNS Peering 列表"
else
    echo -e "❌ 域名 $DOMAIN 不属于 DNS Peering 列表"
fi


# ANSI 颜色代码
GREEN='\033[32m'
NC='\033[0m'
SEPARATOR="================================================================"

# 对每个 DNS 服务器执行查询
for dns in "${!DNS_SERVERS[@]}"; do
    echo -e "\n${SEPARATOR}"
    echo -e "🔍 使用 DNS 服务器: ${GREEN}${dns}${NC} (${DNS_SERVERS[$dns]})"
    echo "${SEPARATOR}"
    
    # 执行 dig 命令并处理输出
    result=$(dig @"$dns" "$DOMAIN" +noall +answer +authority +additional)
    
    # 检查是否有 ANSWER SECTION
    if [ -n "$result" ]; then
        # 提取并高亮显示 ANSWER SECTION
        answer_section=$(echo "$result" | grep -A 10 "^$DOMAIN")
        if [ -n "$answer_section" ]; then
            echo -e "${GREEN}找到解析记录:${NC}"
            echo -e "${GREEN}${answer_section}${NC}"
        else
            echo "❌ 未找到解析记录"
        fi
    else
        echo "❌ 查询失败或未返回结果"
    fi
done

echo -e "\n${SEPARATOR}"
echo "✅ 查询完成"
```

