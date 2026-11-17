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
