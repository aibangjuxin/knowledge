# Shell Scripts Collection

Generated on: 2025-12-31 17:05:54
Directory: /Users/lex/git/knowledge/dns

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

