#!/usr/bin/env bash

# verify-pub-priv-ip-glm.sh
# Purpose: Enhanced DNS verification with IPv6, parallel queries, batch processing,
#          and multiple output formats.
# Enhanced from: verify-pub-priv-ip.sh

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# DNS Servers to query
declare -A DNS_SERVERS=(
  ["8.8.8.8"]="Google Public DNS"
  ["8.8.4.4"]="Google Public DNS 2"
  ["1.1.1.1"]="Cloudflare DNS"
  ["1.0.0.1"]="Cloudflare DNS 2"
  ["9.9.9.9"]="Quad9 DNS"
  ["149.112.112.112"]="Quad9 DNS 2"
  ["208.67.222.222"]="OpenDNS"
  ["208.67.220.220"]="OpenDNS 2"
  ["119.29.29.29"]="Tencent DNSPod"
  ["114.114.114.114"]="114 DNS"
  ["223.5.5.5"]="Ali DNS"
  ["223.6.6.6"]="Ali DNS 2"
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
MAX_PARALLEL=5

# Record types
RECORD_TYPES=("A" "AAAA" "CNAME" "MX")

# ANSI color codes
readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly BLUE='\033[34m'
readonly CYAN='\033[36m'
readonly RED='\033[31m'
readonly MAGENTA='\033[35m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly SEPARATOR="----------------------------------------------------------------"

# Output format flags
OUTPUT_FORMAT="normal"  # normal, json, short, csv, yaml
VERBOSE=false
DEBUG=false
RECORD_TYPE="A"
CUSTOM_DNS_SERVERS=()
DOMAINS_FILE=""
DOMAINS=()

# ============================================================================
# FUNCTIONS
# ============================================================================

# Print usage
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <domain|file>

DNS verification tool with public/private IP detection and IPv6 support.

Arguments:
  <domain>          Domain to query
  -f, --file FILE   Read domains from file (one per line)

Options:
  -t, --type TYPE   Record type: A, AAAA, CNAME, MX, ANY (default: A)
  -o, --output FMT  Output format: normal, json, short, csv, yaml (default: normal)
  -d, --dns IP[:IP] Custom DNS server(s), comma-separated
  -p, --parallel N  Max parallel queries (default: 5)
  --timeout SEC     Query timeout in seconds (default: 2)
  --tries N         Number of tries (default: 2)
  -v, --verbose     Enable verbose output
  --debug           Enable debug output
  -h, --help        Show this help

Examples:
  $(basename "$0") www.baidu.com
  $(basename "$0") www.baidu.com --json
  $(basename "$0") example.com --type AAAA
  $(basename "$0") -f domains.txt --output csv
  $(basename "$0") example.com -d 8.8.8.8,1.1.1.1
  $(basename "$0") example.com --type ANY --verbose

Exit Codes:
  0 - Public IP detected
  1 - Private IP detected
  2 - Unknown/No result
  3 - Error in execution

EOF
}

# Logging functions
log_debug() { [[ "$DEBUG" == true ]] && echo -e "${DIM}[DEBUG]${NC} $*" >&2 || true; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo -e "${CYAN}[VERBOSE]${NC} $*" >&2 || true; }
log_info() { echo -e "${GREEN}[INFO]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        usage
        exit 0
        ;;
      -f|--file)
        DOMAINS_FILE="$2"
        shift 2
        ;;
      -t|--type)
        RECORD_TYPE=$(echo "$2" | tr '[:lower:]' '[:upper:]')
        if [[ ! "$RECORD_TYPE" =~ ^(A|AAAA|CNAME|MX|ANY|NS|TXT)$ ]]; then
          log_error "Invalid record type: $2"
          exit 3
        fi
        shift 2
        ;;
      -o|--output)
        OUTPUT_FORMAT=$(echo "$2" | tr '[:upper:]' '[:lower:]')
        if [[ ! "$OUTPUT_FORMAT" =~ ^(normal|json|short|csv|yaml)$ ]]; then
          log_error "Invalid output format: $2"
          exit 3
        fi
        shift 2
        ;;
      -d|--dns)
        IFS=',' read -ra CUSTOM_DNS_SERVERS <<< "$2"
        # Validate DNS servers
        for dns in "${CUSTOM_DNS_SERVERS[@]}"; do
          if ! [[ "$dns" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && ! [[ "$dns" =~ ^[0-9a-fA-F:]+$ ]]; then
            log_error "Invalid DNS server IP: $dns"
            exit 3
          fi
        done
        shift 2
        ;;
      -p|--parallel)
        MAX_PARALLEL="$2"
        shift 2
        ;;
      --timeout)
        TIMEOUT="$2"
        shift 2
        ;;
      --tries)
        TRIES="$2"
        shift 2
        ;;
      -v|--verbose)
        VERBOSE=true
        shift
        ;;
      --debug)
        DEBUG=true
        shift
        ;;
      --json|--short|--csv|--yaml|--normal)
        OUTPUT_FORMAT="${1#--}"
        shift
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        exit 3
        ;;
      *)
        if [[ -z "${DOMAINS[*]:-}" ]]; then
          DOMAINS=("$1")
        else
          # Check if this is an output format specifier
          case "$1" in
            json|short|csv|yaml|normal)
              OUTPUT_FORMAT="$1"
              ;;
            *)
              DOMAINS+=("$1")
              ;;
          esac
        fi
        shift
        ;;
    esac
  done
}

# Check if domain is in Peering list
check_domain_in_peering() {
  local input_domain="$1"
  for peering_domain in "${DNS_PEERING[@]}"; do
    if [[ "$input_domain" == *"$peering_domain" ]]; then
      return 0
    fi
  done
  return 1
}

# Determine IPv4 type
get_ipv4_type() {
  local ip="$1"
  local a b c d

  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unknown"
    return
  fi

  IFS='.' read -r a b c d <<< "$ip"

  # Validate octets
  if [[ "$a" -gt 255 || "$b" -gt 255 || "$c" -gt 255 || "$d" -gt 255 ]]; then
    echo "Invalid"
    return
  fi

  # RFC1918 Private Ranges
  [[ "$a" -eq 10 ]] && { echo "Private"; return; }
  [[ "$a" -eq 172 && "$b" -ge 16 && "$b" -le 31 ]] && { echo "Private"; return; }
  [[ "$a" -eq 192 && "$b" -eq 168 ]] && { echo "Private"; return; }

  # CGNAT Range (100.64.0.0/10)
  [[ "$a" -eq 100 && "$b" -ge 64 && "$b" -le 127 ]] && { echo "CGNAT"; return; }

  # Loopback
  [[ "$a" -eq 127 ]] && { echo "Local"; return; }

  # Link-local
  [[ "$a" -eq 169 && "$b" -eq 254 ]] && { echo "Local"; return; }

  # Benchmarking (RFC 2544)
  [[ "$a" -eq 198 && "$b" -eq 18 && "$c" -eq 0 ]] && { echo "Reserved"; return; }

  # Documentation (RFC 3849)
  [[ "$a" -eq 192 && "$b" -eq 0 && "$c" -eq 2 ]] && { echo "Reserved"; return; }

  # IETF Protocol Assignments
  [[ "$a" -eq 192 && "$b" -eq 0 && "$c" -eq 0 ]] && { echo "Reserved"; return; }

  # Broadcast
  [[ "$a" -eq 255 && "$b" -eq 255 && "$c" -eq 255 && "$d" -eq 255 ]] && { echo "Broadcast"; return; }

  # Multicast
  [[ "$a" -ge 224 && "$a" -le 239 ]] && { echo "Multicast"; return; }

  echo "Public"
}

# Determine IPv6 type
get_ipv6_type() {
  local ip="$1"
  local compressed

  # Normalize IPv6 for comparison
  compressed=$(echo "$ip" | tr -d '[]')

  # IPv6 loopback (::1)
  if [[ "$compressed" == "::1" ]] || [[ "$compressed" == "0:0:0:0:0:0:0:1" ]]; then
    echo "Local"
    return
  fi

  # Check for IPv6 prefix
  local prefix="${compressed%%:*}"
  local first_block="${prefix%%%*}"  # Remove zone index if present

  # IPv6 private ranges (fc00::/7 - ULA)
  local first_hex=$((0x${first_block:-0}))
  if [[ $first_hex -ge 0xfc00 && $first_hex -le 0xfdff ]]; then
    echo "Private"
    return
  fi

  # Link-local (fe80::/10)
  if [[ $first_hex -ge 0xfe80 && $first_hex -le 0xfebf ]]; then
    echo "Local"
    return
  fi

  # Unique Local (fd00::/8)
  if [[ $first_hex -ge 0xfd00 && $first_hex -le 0xfdff ]]; then
    echo "Private"
    return
  fi

  # Teredo (2001:0::/32)
  if [[ "$compressed" == 2001:0:* ]]; then
    echo "Teredo"
    return
  fi

  # Documentation range (2001:db8::/32) - check after Teredo
  if [[ "$compressed" == 2001:db8:* ]]; then
    echo "Reserved"
    return
  fi

  # 2001::/32 prefix for other 2001 addresses
  if [[ "$compressed" == 2001:* ]]; then
    echo "Public"
    return
  fi

  # 6to4 (2002::/16)
  if [[ "$compressed" == 2002:* ]]; then
    echo "6to4"
    return
  fi

  echo "Public"
}

# Get IP type (auto-detect IPv4/IPv6)
get_ip_type() {
  local ip="$1"

  # Remove any brackets from IPv6
  ip="${ip#\[}"
  ip="${ip%\]}"

  if [[ "$ip" =~ .*:.* ]]; then
    get_ipv6_type "$ip"
  else
    get_ipv4_type "$ip"
  fi
}

# Perform DNS query for a single server
query_dns_server() {
  local dns="$1"
  local desc="$2"
  local domain="$3"
  local record_type="$4"
  local output_file="$5"

  log_debug "Querying $dns ($desc) for $domain $record_type"

  local result

  case "$record_type" in
    "ANY")
      result=$(dig @"$dns" "$domain" +noall +answer +time=${TIMEOUT} +tries=${TRIES} 2>&1)
      ;;
    *)
      result=$(dig @"$dns" "$domain" "$record_type" +noall +answer +time=${TIMEOUT} +tries=${TRIES} 2>&1)
      ;;
  esac

  # Note: dig may return non-zero exit code even with results (e.g., communications error)
  # We ignore the exit code and just check for results below

  if [[ -z "$result" ]]; then
    echo "NO_RECORD|||" > "$output_file"
    return
  fi

  # Extract records based on type
  local records=()
  local types=()

  if [[ "$record_type" == "ANY" ]]; then
    # For ANY queries, include all record types
    while IFS= read -r line; do
      local rec_type=$(echo "$line" | awk '{print $4}')
      local rec_value=$(echo "$line" | awk '{print $NF}')

      if [[ -n "$rec_value" ]]; then
        records+=("$rec_value")
        types+=("$(get_ip_type "$rec_value")")
      fi
    done <<< "$result"
  else
    # For specific queries, only include matching record types
    while IFS= read -r line; do
      local rec_type=$(echo "$line" | awk '{print $4}')
      local rec_value=$(echo "$line" | awk '{print $NF}')

      # Skip CNAME records for A/AAAA queries - the final A/AAAA will be included
      if [[ "$rec_type" == "CNAME" ]]; then
        continue
      fi

      # Only include records that match the requested type (or are IP addresses)
      if [[ -n "$rec_value" ]]; then
        # Check if this is the record type we want or if it looks like an IP
        if [[ "$rec_type" == "$record_type" ]] || [[ "$rec_value" =~ ^[0-9] ]] || [[ "$rec_value" =~ ^[0-9a-f:]*:[0-9a-f:]*$ ]]; then
          records+=("$rec_value")
          types+=("$(get_ip_type "$rec_value")")
        fi
      fi
    done <<< "$result"
  fi

  if [[ ${#records[@]} -eq 0 ]]; then
    echo "NO_${record_type}_RECORD|||" > "$output_file"
    return
  fi

  # Build result string
  local ips_csv=$(IFS=','; echo "${records[*]}")
  local types_csv=$(IFS=','; echo "${types[*]}")
  echo "SUCCESS|${desc}|${ips_csv}|${types_csv}" > "$output_file"
}

# Process results and determine verdict
process_results() {
  local domain="$1"
  declare -n results_ref="$2"
  declare -n ips_ref="$3"
  declare -n types_ref="$4"

  local verdict="UNKNOWN"
  local exit_code=2

  log_debug "Processing results for $domain"

  # Count IP types
  local public_count=0
  local private_count=0
  local local_count=0
  local other_count=0

  for dns in "${!results_ref[@]}"; do
    local result="${results_ref[$dns]}"
    local ips="${ips_ref[$dns]:-}"
    local ip_types="${types_ref[$dns]:-}"

    case "$result" in
      "SUCCESS")
        # Check each IP type
        IFS=',' read -ra TYPE_ARRAY <<< "$ip_types"
        for t in "${TYPE_ARRAY[@]}"; do
          case "$t" in
            "Public") ((public_count++)) ;;
            "Private") ((private_count++)) ;;
            "Local") ((local_count++)) ;;
            *) ((other_count++)) ;;
          esac
        done
        ;;
    esac
  done

  # Determine final verdict
  if [[ $public_count -gt 0 ]]; then
    verdict="PUBLIC"
    exit_code=0
  elif [[ $private_count -gt 0 ]]; then
    verdict="PRIVATE"
    exit_code=1
  elif [[ $local_count -gt 0 ]]; then
    verdict="LOCAL"
    exit_code=2
  fi

  echo "$verdict|$exit_code"
}

# Output in normal format
output_normal() {
  local domain="$1"
  local peering_matched="$2"
  declare -n results_ref="$3"
  declare -n ips_ref="$4"
  declare -n types_ref="$5"
  local verdict="$6"

  echo -e "\n${BOLD}DNS Verification Report for: ${BLUE}${domain}${NC}"
  echo -e "${SEPARATOR}"

  # Peering Check
  if [[ "$peering_matched" == true ]]; then
    echo -e "Peering Status: ${GREEN}Matched (In Peering List)${NC}"
  else
    echo -e "Peering Status: ${YELLOW}Unmatched (Not in Peering List)${NC}"
  fi

  echo -e "Record Type: ${CYAN}${RECORD_TYPE}${NC}"
  echo -e "\n${BOLD}DNS Server Results:${NC}"

  # Iterate over results, not all DNS servers
  for dns in "${!results_ref[@]}"; do
    local result="${results_ref[$dns]}"
    local ips="${ips_ref[$dns]:-}"
    local ip_types="${types_ref[$dns]:-}"
    local desc="${DNS_SERVERS[$dns]:-Custom DNS}"

    echo -e "\n${BLUE}➤ $dns ($desc)${NC}"

    case "$result" in
      "SUCCESS")
        IFS=',' read -ra IP_ARRAY <<< "$ips"
        IFS=',' read -ra TYPE_ARRAY <<< "$ip_types"

        for i in "${!IP_ARRAY[@]}"; do
          local ip="${IP_ARRAY[$i]}"
          local ip_type="${TYPE_ARRAY[$i]}"
          local color="$GREEN"

          case "$ip_type" in
            "Private") color="$YELLOW" ;;
            "Local") color="$BLUE" ;;
            "CGNAT") color="$MAGENTA" ;;
            "Reserved") color="$DIM" ;;
          esac

          echo -e "  ${color}[$ip_type]${NC} $ip"
        done
        ;;
      "FAILED")
        echo -e "  ${RED}✗ Query failed${NC}"
        ;;
      NO_*_RECORD|NO_RECORD)
        echo -e "  ${YELLOW}[!] No record found${NC}"
        ;;
    esac
  done

  # Final verdict
  local verdict_color="$GREEN"
  [[ "$verdict" == "PRIVATE" ]] && verdict_color="$YELLOW"
  [[ "$verdict" == "LOCAL" ]] && verdict_color="$BLUE"
  [[ "$verdict" == "UNKNOWN" ]] && verdict_color="$RED"

  echo -e "\n${SEPARATOR}"
  echo -e "${BOLD}Final Verdict: ${verdict_color}${verdict}${NC}"
  echo -e "${SEPARATOR}\n"
}

# Output in JSON format
output_json() {
  local domain="$1"
  local peering_matched="$2"
  declare -n results_ref="$3"
  declare -n ips_ref="$4"
  declare -n types_ref="$5"
  local verdict="$6"

  local peering_status="UNMATCHED"
  [[ "$peering_matched" == true ]] && peering_status="MATCHED"

  # Start JSON output
  echo "{"
  echo "  \"domain\": \"$domain\","
  echo "  \"record_type\": \"$RECORD_TYPE\","
  echo "  \"peering_status\": \"$peering_status\","
  echo "  \"verdict\": \"$verdict\","
  echo "  \"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
  echo "  \"dns_servers\": ["

  local first=true
  for dns in "${!results_ref[@]}"; do
    local result="${results_ref[$dns]}"
    local ips="${ips_ref[$dns]:-}"
    local ip_types="${types_ref[$dns]:-}"
    local desc="${DNS_SERVERS[$dns]:-Custom DNS}"

    # Output comma separator between entries
    [[ "$first" == true ]] && first=false || echo ","

    # Start server entry
    echo -n "    {"
    echo -n "\"address\": \"$dns\", "
    echo -n "\"description\": \"$desc\", "
    echo -n "\"status\": \"$result\", "

    # Build records array
    echo -n "\"records\": ["
    if [[ "$result" == "SUCCESS" && -n "$ips" ]]; then
      IFS=',' read -ra IP_ARRAY <<< "$ips"
      IFS=',' read -ra TYPE_ARRAY <<< "$ip_types"

      local ip_first=true
      for i in "${!IP_ARRAY[@]}"; do
        [[ "$ip_first" == true ]] && ip_first=false || echo -n ","
        echo -n "{\"ip\": \"${IP_ARRAY[$i]}\", \"type\": \"${TYPE_ARRAY[$i]}\"}"
      done
    fi
    echo "]"
    echo -n "    }"
  done

  # Close JSON
  echo ""
  echo "  ]"
  echo "}"
}

# Output in CSV format
output_csv() {
  local domain="$1"
  local peering_matched="$2"
  declare -n results_ref="$3"
  declare -n ips_ref="$4"
  declare -n types_ref="$5"
  local verdict="$6"

  local peering_status="UNMATCHED"
  [[ "$peering_matched" == true ]] && peering_status="MATCHED"

  echo "domain,record_type,peering_status,verdict,timestamp"
  echo "\"$domain\",\"$RECORD_TYPE\",\"$peering_status\",\"$verdict\",\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\""
  echo ""
  echo "dns_server,description,status,ips,types"

  for dns in "${!results_ref[@]}"; do
    local result="${results_ref[$dns]}"
    local ips="${ips_ref[$dns]:-}"
    local ip_types="${types_ref[$dns]:-}"
    local desc="${DNS_SERVERS[$dns]:-Custom DNS}"

    echo "\"$dns\",\"$desc\",\"$result\",\"$ips\",\"$ip_types\""
  done
}

# Output in short format
output_short() {
  local verdict="$1"
  local exit_code="$2"
  echo "$verdict"
  exit "$exit_code"
}

# Output in YAML format
output_yaml() {
  local domain="$1"
  local peering_matched="$2"
  declare -n results_ref="$3"
  declare -n ips_ref="$4"
  declare -n types_ref="$5"
  local verdict="$6"

  local peering_status="UNMATCHED"
  [[ "$peering_matched" == true ]] && peering_status="MATCHED"

  cat <<EOF
---
domain: "$domain"
record_type: "$RECORD_TYPE"
peering_status: "$peering_status"
verdict: "$verdict"
timestamp: "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
dns_servers:
EOF

  for dns in "${!results_ref[@]}"; do
    local result="${results_ref[$dns]}"
    local ips="${ips_ref[$dns]:-}"
    local ip_types="${types_ref[$dns]:-}"
    local desc="${DNS_SERVERS[$dns]:-Custom DNS}"

    cat <<YAML_EOF
  - address: "$dns"
    description: "$desc"
    status: "$result"
    records:
YAML_EOF

    if [[ "$result" == "SUCCESS" && -n "$ips" ]]; then
      IFS=',' read -ra IP_ARRAY <<< "$ips"
      IFS=',' read -ra TYPE_ARRAY <<< "$ip_types"

      for i in "${!IP_ARRAY[@]}"; do
        echo "      - ip: \"${IP_ARRAY[$i]}\""
        echo "        type: \"${TYPE_ARRAY[$i]}\""
      done
    fi
  done
}

# Main processing function
process_domain() {
  local domain="$1"

  log_verbose "Processing domain: $domain"

  # Check peering status
  local peering_matched=false
  if check_domain_in_peering "$domain"; then
    peering_matched=true
  fi

  # Use custom DNS servers if provided
  local -a DNS_LIST=()
  if [[ ${#CUSTOM_DNS_SERVERS[@]} -gt 0 ]]; then
    for dns in "${CUSTOM_DNS_SERVERS[@]}"; do
      DNS_LIST+=("$dns:Custom DNS")
    done
  else
    # Use default DNS servers
    for dns in "${!DNS_SERVERS[@]}"; do
      DNS_LIST+=("$dns:${DNS_SERVERS[$dns]}")
    done
  fi

  # Result arrays
  declare -A SERVER_RESULTS
  declare -A SERVER_IPS
  declare -A SERVER_TYPES

  # Create temp directory for parallel queries
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" EXIT RETURN

  # Query DNS servers (parallel)
  local pids=()
  for entry in "${DNS_LIST[@]}"; do
    local dns="${entry%%:*}"
    local desc="${entry#*:}"
    # Use DNS IP in filename for reliable mapping
    local safe_dns="${dns//./_}"
    local output_file="$tmpdir/result_$safe_dns"

    query_dns_server "$dns" "$desc" "$domain" "$RECORD_TYPE" "$output_file" &
    pids+=($!)

    # Limit parallel jobs
    if [[ ${#pids[@]} -ge $MAX_PARALLEL ]]; then
      for i in "${!pids[@]}"; do
        wait ${pids[$i]} 2>/dev/null || true
      done
      pids=()
    fi
  done

  # Wait for remaining jobs
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Read results
  for entry in "${DNS_LIST[@]}"; do
    local dns="${entry%%:*}"
    local safe_dns="${dns//./_}"
    local output_file="$tmpdir/result_$safe_dns"
    if [[ -f "$output_file" ]]; then
      IFS='|' read -r result desc ips types < "$output_file"
      SERVER_RESULTS["$dns"]="$result"
      SERVER_IPS["$dns"]="${ips:-}"
      SERVER_TYPES["$dns"]="${types:-}"
    else
      SERVER_RESULTS["$dns"]="FAILED"
    fi
  done

  rm -rf "$tmpdir"

  # Process results
  local verdict_info
  verdict_info=$(process_results "$domain" SERVER_RESULTS SERVER_IPS SERVER_TYPES)
  IFS='|' read -r verdict exit_code <<< "$verdict_info"

  # Output based on format
  case "$OUTPUT_FORMAT" in
    "short")
      output_short "$verdict" "$exit_code"
      ;;
    "json")
      output_json "$domain" "$peering_matched" SERVER_RESULTS SERVER_IPS SERVER_TYPES "$verdict"
      exit "$exit_code"
      ;;
    "csv")
      output_csv "$domain" "$peering_matched" SERVER_RESULTS SERVER_IPS SERVER_TYPES "$verdict"
      exit "$exit_code"
      ;;
    "yaml")
      output_yaml "$domain" "$peering_matched" SERVER_RESULTS SERVER_IPS SERVER_TYPES "$verdict"
      exit "$exit_code"
      ;;
    *)
      output_normal "$domain" "$peering_matched" SERVER_RESULTS SERVER_IPS SERVER_TYPES "$verdict"
      exit "$exit_code"
      ;;
  esac
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  parse_args "$@"

  # Get domains
  local domains=()

  if [[ -n "$DOMAINS_FILE" ]]; then
    if [[ ! -f "$DOMAINS_FILE" ]]; then
      log_error "File not found: $DOMAINS_FILE"
      exit 3
    fi
    mapfile -t domains < <(grep -v '^[[:space:]]*#' "$DOMAINS_FILE" | grep -v '^[[:space:]]*$' | tr -d '\r')
  elif [[ ${#DOMAINS[@]} -gt 0 ]]; then
    domains=("${DOMAINS[@]}")
  else
    log_error "No domain specified"
    usage
    exit 3
  fi

  # Count actual DNS servers to use
  local dns_count=${#CUSTOM_DNS_SERVERS[@]}
  [[ $dns_count -eq 0 ]] && dns_count=${#DNS_SERVERS[@]}
  
  log_info "Processing ${#domains[@]} domain(s) with $dns_count DNS server(s)"

  # Process each domain
  for domain in "${domains[@]}"; do
    process_domain "$domain"
  done
}

main "$@"
