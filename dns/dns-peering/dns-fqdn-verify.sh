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
