#!/usr/bin/env bash

# verify-pub-priv-ip-glm-ipv6-fixed.sh
# Purpose: Enhanced DNS verification with IPv6, parallel queries, batch processing,
#          and multiple output formats. Hardened version based on the
#          shell-review audit (audit-verify-pub-priv-ip-glm-ipv6.md).
#
# Enhanced from: verify-pub-priv-ip.sh
#
# Changes from original (see ../shell-review/audit-verify-pub-priv-ip-glm-ipv6.md):
#   - IPv6 hex range checks now use (( )) arithmetic context (was [[ -ge ]])
#   - trap 'rm -rf "$tmpdir"' EXIT only (was EXIT RETURN, with double-quoted
#     expansion-time bug + multiple-cleanup race)
#   - `local x=$(...)` patterns split into declare-then-assign (6 places)
#   - Added --dry-run flag for safe L4 testing
#   - Glob-based prefix matching replaced with case statements (no over-match)
#   - Removed dead-code arrays (RECORD_TYPES, SERVER_IPS, SERVER_TYPES)
#   - Added --version, --help is now in main case statement

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
DRY_RUN=false
RECORD_TYPE="A"
CUSTOM_DNS_SERVERS=()
DOMAINS_FILE=""
DOMAINS=()

SCRIPT_VERSION="1.1.0-fixed"

# Internal CSV stream separators (FIX #6)
# IPv6 contains ':' and domains/records may contain ',', so plain delimiters are
# unsafe. RS/US are ASCII control chars that never appear in DNS responses.
readonly CSV_RS=$'\x1e'  # Record Separator — between dns key and value
readonly CSV_US=$'\x1f'  # Unit Separator — between server entries

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
  --dry-run         Print planned queries, do not contact DNS servers
  -V, --version     Print version and exit
  -h, --help        Show this help

Examples:
  $(basename "$0") www.baidu.com
  $(basename "$0") www.baidu.com --json
  $(basename "$0") example.com --type AAAA
  $(basename "$0") -f domains.txt --output csv
  $(basename "$0") example.com -d 8.8.8.8,1.1.1.1
  $(basename "$0") example.com --type ANY --verbose
  $(basename "$0") example.com --dry-run --verbose

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
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -V|--version)
        echo "$(basename "$0") version $SCRIPT_VERSION"
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
      --dry-run)
        DRY_RUN=true
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
# Fixed: hex range comparisons use (( )) arithmetic context, not [[ ]] string compare
get_ipv6_type() {
  local ip="$1"
  local compressed

  # Normalize IPv6 for comparison (strip brackets)
  compressed=${ip//[\[\]]/}

  # IPv6 loopback (::1)
  if [[ "$compressed" == "::1" || "$compressed" == "0:0:0:0:0:0:0:1" ]]; then
    echo "Local"
    return
  fi

  # Extract first 16-bit block (4 hex chars) before the first colon
  local prefix="${compressed%%:*}"
  local first_block="${prefix%%%*}"  # Remove zone index if present

  # Convert hex block to decimal once (FIX #1: arithmetic context)
  local first_hex
  first_hex=$((0x${first_block:-0}))

  # IPv6 ULA fc00::/7 — uses (( )) arithmetic, NOT [[ ]] string compare
  if (( first_hex >= 0xfc00 && first_hex <= 0xfdff )); then
    echo "Private"
    return
  fi

  # Link-local fe80::/10
  if (( first_hex >= 0xfe80 && first_hex <= 0xfebf )); then
    echo "Local"
    return
  fi

  # Unique Local fd00::/8 (subset of fc00::/7 but distinct semantics in some contexts)
  if (( first_hex >= 0xfd00 && first_hex <= 0xfdff )); then
    echo "Private"
    return
  fi

  # 2001::/32 prefix space — case-based matching (FIX #5: no glob over-match)
  case "$compressed" in
    2001:0000:*|2001:0:*)
      # Teredo (2001:0::/32) — exact 2001:0000::/32
      echo "Teredo"
      return
      ;;
    2001:0db8:*|2001:db8:*)
      # Documentation (2001:db8::/32)
      echo "Reserved"
      return
      ;;
    2002:*)
      # 6to4 (2002::/16)
      echo "6to4"
      return
      ;;
  esac

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

# Extract a field by index from a tab/whitespace-separated dig line
# Refactored from inline `echo "$line" | awk '{print $4}'` pattern (FIX #3).
# Args: line, field_index (integer or "NF" for last field)
get_dig_field() {
  local line="$1"
  local idx="$2"
  if [[ "$idx" == "NF" ]]; then
    awk '{print $NF}' <<< "$line"
  else
    awk -v i="$idx" '{print $i}' <<< "$line"
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

  # FIX #7: --dry-run short-circuits before any network call
  if [[ "$DRY_RUN" == true ]]; then
    log_verbose "[dry-run] would query $dns for $domain $record_type"
    echo "DRY_RUN|${desc}||||" > "$output_file"
    return
  fi

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
  local -a records=()
  local -a types=()

  if [[ "$record_type" == "ANY" ]]; then
    # For ANY queries, include all record types
    while IFS= read -r line; do
      local rec_type rec_value
      rec_type=$(get_dig_field "$line" 4)
      rec_value=$(get_dig_field "$line" NF)

      # FIX #3: declare-then-assign, explicit empty check surfaces awk failures
      if [[ -n "$rec_value" ]]; then
        records+=("$rec_value")
        types+=("$(get_ip_type "$rec_value")")
      fi
    done <<< "$result"
  else
    # For specific queries, only include matching record types
    while IFS= read -r line; do
      local rec_type rec_value
      rec_type=$(get_dig_field "$line" 4)
      rec_value=$(get_dig_field "$line" NF)

      # Skip CNAME records for A/AAAA queries - the final A/AAAA will be included
      if [[ "$rec_type" == "CNAME" ]]; then
        continue
      fi

      # Only include records that match the requested type (or are IP addresses)
      if [[ -n "$rec_value" ]]; then
        # Check if this is the record type we want or if it looks like an IP
        if [[ "$rec_type" == "$record_type" || "$rec_value" =~ ^[0-9] || "$rec_value" =~ ^[0-9a-f:]*:[0-9a-f:]*$ ]]; then
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

  # Build result string (FIX #3: declare-then-assign, avoid SC2155 mask)
  local ips_csv types_csv
  ips_csv=$(IFS=','; echo "${records[*]}")
  types_csv=$(IFS=','; echo "${types[*]}")
  echo "SUCCESS|${desc}|${ips_csv}|${types_csv}" > "$output_file"
}

# Process results and determine verdict
# FIX #6: simplified to take CSV strings directly; removes dead-code SERVER_*
# arrays that were never read.
process_results() {
  local domain="$1"
  local results_csv="$2"  # format: dns1:result1|dns2:result2|...
  local types_csv="$3"    # format: dns1:type1,type2|dns2:type3|...

  local verdict="UNKNOWN"
  local exit_code=2

  log_debug "Processing results for $domain"

  # Count IP types across all servers
  local public_count=0
  local private_count=0
  local local_count=0
  local other_count=0

  IFS="$CSV_US" read -ra server_entries <<< "$types_csv"
  for entry in "${server_entries[@]}"; do
    [[ -z "$entry" ]] && continue
    IFS=',' read -ra TYPE_ARRAY <<< "$entry"
    for t in "${TYPE_ARRAY[@]}"; do
      case "$t" in
        "Public") ((public_count++)) ;;
        "Private") ((private_count++)) ;;
        "Local") ((local_count++)) ;;
        *) ((other_count++)) ;;
      esac
    done
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
  local results_csv="$3"
  local ips_csv="$4"
  local types_csv="$5"
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

  # Build per-server parallel arrays from CSV
  IFS="$CSV_US" read -ra RESULT_ENTRIES <<< "$results_csv"
  IFS="$CSV_US" read -ra IP_ENTRIES <<< "$ips_csv"
  IFS="$CSV_US" read -ra TYPE_ENTRIES <<< "$types_csv"

  for i in "${!RESULT_ENTRIES[@]}"; do
    local entry="${RESULT_ENTRIES[$i]}"
    local dns="${entry%%"$CSV_RS"*}"
    local result="${entry#*"$CSV_RS"}"
    local ips ip_types
    ips="${IP_ENTRIES[$i]:-}"
    ips="${ips#*"$CSV_RS"}"
    ip_types="${TYPE_ENTRIES[$i]:-}"
    ip_types="${ip_types#*"$CSV_RS"}"
    local desc="${DNS_SERVERS[$dns]:-Custom DNS}"

    echo -e "\n${BLUE}➤ $dns ($desc)${NC}"

    case "$result" in
      "SUCCESS")
        IFS=',' read -ra IP_ARRAY <<< "$ips"
        IFS=',' read -ra TYPE_ARRAY <<< "$ip_types"

        for j in "${!IP_ARRAY[@]}"; do
          local ip="${IP_ARRAY[$j]}"
          local ip_type="${TYPE_ARRAY[$j]}"
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
      DRY_RUN)
        echo -e "  ${CYAN}[dry-run] would query${NC}"
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
  local results_csv="$3"
  local ips_csv="$4"
  local types_csv="$5"
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

  IFS="$CSV_US" read -ra RESULT_ENTRIES <<< "$results_csv"
  IFS="$CSV_US" read -ra IP_ENTRIES <<< "$ips_csv"
  IFS="$CSV_US" read -ra TYPE_ENTRIES <<< "$types_csv"

  local first=true
  for i in "${!RESULT_ENTRIES[@]}"; do
    local entry="${RESULT_ENTRIES[$i]}"
    local dns="${entry%%"$CSV_RS"*}"
    local result="${entry#*"$CSV_RS"}"
    local ips ip_types
    ips="${IP_ENTRIES[$i]:-}"
    ips="${ips#*"$CSV_RS"}"
    ip_types="${TYPE_ENTRIES[$i]:-}"
    ip_types="${ip_types#*"$CSV_RS"}"
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
      for j in "${!IP_ARRAY[@]}"; do
        [[ "$ip_first" == true ]] && ip_first=false || echo -n ","
        echo -n "{\"ip\": \"${IP_ARRAY[$j]}\", \"type\": \"${TYPE_ARRAY[$j]}\"}"
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
  local results_csv="$3"
  local ips_csv="$4"
  local types_csv="$5"
  local verdict="$6"

  local peering_status="UNMATCHED"
  [[ "$peering_matched" == true ]] && peering_status="MATCHED"

  echo "domain,record_type,peering_status,verdict,timestamp"
  echo "\"$domain\",\"$RECORD_TYPE\",\"$peering_status\",\"$verdict\",\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\""
  echo ""
  echo "dns_server,description,status,ips,types"

  IFS="$CSV_US" read -ra RESULT_ENTRIES <<< "$results_csv"
  IFS="$CSV_US" read -ra IP_ENTRIES <<< "$ips_csv"
  IFS="$CSV_US" read -ra TYPE_ENTRIES <<< "$types_csv"

  for i in "${!RESULT_ENTRIES[@]}"; do
    local entry="${RESULT_ENTRIES[$i]}"
    local dns="${entry%%"$CSV_RS"*}"
    local result="${entry#*"$CSV_RS"}"
    local ips ip_types
    ips="${IP_ENTRIES[$i]:-}"
    ips="${ips#*"$CSV_RS"}"
    ip_types="${TYPE_ENTRIES[$i]:-}"
    ip_types="${ip_types#*"$CSV_RS"}"
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
  local results_csv="$3"
  local ips_csv="$4"
  local types_csv="$5"
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

  IFS="$CSV_US" read -ra RESULT_ENTRIES <<< "$results_csv"
  IFS="$CSV_US" read -ra IP_ENTRIES <<< "$ips_csv"
  IFS="$CSV_US" read -ra TYPE_ENTRIES <<< "$types_csv"

  for i in "${!RESULT_ENTRIES[@]}"; do
    local entry="${RESULT_ENTRIES[$i]}"
    local dns="${entry%%"$CSV_RS"*}"
    local result="${entry#*"$CSV_RS"}"
    local ips ip_types
    ips="${IP_ENTRIES[$i]:-}"
    ips="${ips#*"$CSV_RS"}"
    ip_types="${TYPE_ENTRIES[$i]:-}"
    ip_types="${ip_types#*"$CSV_RS"}"
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

      for j in "${!IP_ARRAY[@]}"; do
        echo "      - ip: \"${IP_ARRAY[$j]}\""
        echo "        type: \"${TYPE_ARRAY[$j]}\""
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

  # Create temp directory for parallel queries
  local tmpdir
  tmpdir=$(mktemp -d)
  # FIX #2: single-quoted trap, only EXIT (no RETURN race), no double-cleanup
  # (removed the explicit `rm -rf "$tmpdir"` later; the trap handles it)
  trap 'rm -rf "$tmpdir"' EXIT

  # Query DNS servers (parallel)
  local -a pids=()
  local -a pid_to_dns=()  # Map PID index → DNS server (for safe wait+cleanup)
  for entry in "${DNS_LIST[@]}"; do
    local dns="${entry%%:*}"
    local desc="${entry#*:}"
    # Use DNS IP in filename for reliable mapping
    local safe_dns="${dns//./_}"
    local output_file="$tmpdir/result_$safe_dns"

    query_dns_server "$dns" "$desc" "$domain" "$RECORD_TYPE" "$output_file" &
    pids+=($!)
    pid_to_dns+=("$dns")

    # Limit parallel jobs
    if [[ ${#pids[@]} -ge $MAX_PARALLEL ]]; then
      for i in "${!pids[@]}"; do
        wait "${pids[$i]}" 2>/dev/null || true
      done
      pids=()
      pid_to_dns=()
    fi
  done

  # Wait for remaining jobs
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Aggregate results into three parallel CSV streams.
  # (FIX #6: replaces dead-code SERVER_RESULTS / SERVER_IPS / SERVER_TYPES arrays.)
  # Uses global CSV_RS (Record Separator) between dns and value, CSV_US (Unit
  # Separator) between entries. Safe for IPv6 ':' because ASCII control chars
  # never appear in DNS responses.
  local results_csv=""
  local ips_csv=""
  local types_csv=""

  for entry in "${DNS_LIST[@]}"; do
    local dns="${entry%%:*}"
    local safe_dns="${dns//./_}"
    local output_file="$tmpdir/result_$safe_dns"
    local result ips types

    if [[ -f "$output_file" ]]; then
      IFS='|' read -r result desc ips types < "$output_file"
    else
      result="FAILED"
      ips=""
      types=""
    fi

    # Append to CSV streams
    [[ -n "$results_csv" ]] && results_csv+="$CSV_US"
    results_csv+="${dns}${CSV_RS}${result}"

    [[ -n "$ips_csv" ]] && ips_csv+="$CSV_US"
    ips_csv+="${dns}${CSV_RS}${ips:-}"

    [[ -n "$types_csv" ]] && types_csv+="$CSV_US"
    types_csv+="${dns}${CSV_RS}${types:-}"
  done

  # FIX #2: explicit rm -rf removed; EXIT trap handles cleanup
  # (no more triple-cleanup race between EXIT trap, RETURN trap, and line 763)

  # Process results (now takes CSV strings directly)
  local verdict_info
  verdict_info=$(process_results "$domain" "$results_csv" "$types_csv")
  IFS='|' read -r verdict exit_code <<< "$verdict_info"

  # Output based on format
  case "$OUTPUT_FORMAT" in
    "short")
      output_short "$verdict" "$exit_code"
      ;;
    "json")
      output_json "$domain" "$peering_matched" "$results_csv" "$ips_csv" "$types_csv" "$verdict"
      exit "$exit_code"
      ;;
    "csv")
      output_csv "$domain" "$peering_matched" "$results_csv" "$ips_csv" "$types_csv" "$verdict"
      exit "$exit_code"
      ;;
    "yaml")
      output_yaml "$domain" "$peering_matched" "$results_csv" "$ips_csv" "$types_csv" "$verdict"
      exit "$exit_code"
      ;;
    *)
      output_normal "$domain" "$peering_matched" "$results_csv" "$ips_csv" "$types_csv" "$verdict"
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
  local -a domains=()

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
  [[ "$DRY_RUN" == true ]] && log_warn "DRY-RUN mode: no DNS queries will be issued"

  # Process each domain
  for domain in "${domains[@]}"; do
    process_domain "$domain"
  done
}

main "$@"