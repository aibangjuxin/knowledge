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
