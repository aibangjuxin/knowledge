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

# ANSI color codes
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
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

  # Execute dig command
  result=$(dig @"$dns" "$DOMAIN" +noall +answer +authority +additional)

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
