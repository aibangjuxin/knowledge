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
