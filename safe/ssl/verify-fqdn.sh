#!/usr/bin/env bash

# verify-fqdn.sh
# Purpose: One-shot FQDN sanity check — DNS resolution across public resolvers + TLS/SSL analysis.
# Merged from:
#   - verify-dns-fqdn.sh    (DNS multi-resolver probe + Peering list match)
#   - verify-domain-ssl-enhance.sh  (TLS handshake, chain, SAN, expiry, verify)
#
# Usage:   verify-fqdn.sh <domain> [port] [ca-file-path]
# Example: verify-fqdn.sh www.baidu.com
#          verify-fqdn.sh internal.example.com 443 /etc/ssl/certs/ca-certificates.crt

set -u

# ============================================================
# Configuration
# ============================================================

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
HEAVY="=================================================="

# ============================================================
# CLI parsing
# ============================================================

DOMAIN="${1:-}"
PORT="${2:-443}"
CA_FILE="${3:-}"

if [ -z "$DOMAIN" ]; then
  echo -e "${RED}Usage: $0 <domain> [port] [ca-file-path]${NC}"
  echo "Example (system CA): $0 www.baidu.com"
  echo "Example (custom CA): $0 internal.example.com 443 /etc/ssl/certs/ca-certificates.crt"
  exit 1
fi

# ============================================================
# Helpers
# ============================================================

# Check if domain matches any entry in the Peering list (suffix match)
check_domain_in_peering() {
  local input_domain="$1"
  for peering_domain in "${DNS_PEERING[@]}"; do
    if [[ "$input_domain" == *"$peering_domain" ]]; then
      return 0
    fi
  done
  return 1
}

# Classify an IPv4 address: Public / Private (RFC1918) / Local (loopback/link-local) / Unknown
get_ip_type() {
  local ip="$1"
  local a b c d
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unknown"
    return
  fi
  IFS='.' read -r a b c d <<< "$ip"

  # RFC1918: 10.0.0.0/8
  if [[ "$a" -eq 10 ]]; then echo "Private"; return; fi
  # RFC1918: 172.16.0.0/12
  if [[ "$a" -eq 172 && "$b" -ge 16 && "$b" -le 31 ]]; then echo "Private"; return; fi
  # RFC1918: 192.168.0.0/16
  if [[ "$a" -eq 192 && "$b" -eq 168 ]]; then echo "Private"; return; fi
  # 127.0.0.0/8 (Loopback)
  if [[ "$a" -eq 127 ]]; then echo "Local"; return; fi
  # 169.254.0.0/16 (Link-local)
  if [[ "$a" -eq 169 && "$b" -eq 254 ]]; then echo "Local"; return; fi

  echo "Public"
}

print_kv() {
  printf "%-24s %s\n" "$1" "$2"
}

print_section() {
  echo
  echo "$HEAVY"
  echo "$1"
  echo "$HEAVY"
}

# ============================================================
# Header
# ============================================================

echo
echo "$HEAVY"
echo "FQDN verification report for: ${DOMAIN}:${PORT}"
echo "$HEAVY"
echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo "$HEAVY"

# ============================================================
# [1] DNS — Peering check
# ============================================================

print_section "[1] DNS — Peering check"

if check_domain_in_peering "$DOMAIN"; then
  echo -e "Peering Status: ${GREEN}Matched (in Peering list)${NC}"
else
  echo -e "Peering Status: ${YELLOW}Unmatched (not in Peering list)${NC}"
fi

# ============================================================
# [2] DNS — Multi-resolver query
# ============================================================

print_section "[2] DNS — Multi-resolver resolution"

declare -A SERVER_RESULTS
declare -A SERVER_IPS
# Track the first public IP we see, for the optional direct-connect SSL probe later.
FIRST_PUBLIC_IP=""

if ! command -v dig >/dev/null 2>&1; then
  echo -e "${RED}ERROR: 'dig' is required for DNS resolution but not found in PATH.${NC}"
  echo "Install with: brew install bind  (or: apt-get install dnsutils)"
  echo
  echo "Skipping DNS multi-resolver section."
else
  for dns in "${!DNS_SERVERS[@]}"; do
    desc="${DNS_SERVERS[$dns]}"

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

    ips=$(echo "$result" | grep -E "[[:space:]]A[[:space:]]" | awk '{print $NF}')
    if [ -z "$ips" ]; then
      SERVER_RESULTS["$dns"]="NO_A_RECORD"
      continue
    fi

    echo -e "\n${BLUE}-> Querying $dns ($desc)${NC}"

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

      # Stash the first public IP for the optional direct-connect TLS probe
      if [[ -z "$FIRST_PUBLIC_IP" && "$ip_type" == "Public" ]]; then
        FIRST_PUBLIC_IP="$ip"
      fi
    done

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

  # Summary table
  echo -e "\n${BOLD}DNS summary table${NC}"
  echo "$SEPARATOR"
  printf "%-18s | %-15s | %-12s | %s\n" "DNS Server" "Description" "Result" "Resolved IPs"
  echo "$SEPARATOR"

  for dns in "${!DNS_SERVERS[@]}"; do
    desc="${DNS_SERVERS[$dns]}"
    res="${SERVER_RESULTS[$dns]:-N/A}"
    ips="${SERVER_IPS[$dns]:-}"

    res_color=$NC
    case "$res" in
      "PUBLIC") res_color=$GREEN ;;
      "PRIVATE") res_color=$YELLOW ;;
      "FAILED") res_color=$RED ;;
      "NO_RECORD"|"NO_A_RECORD") res_color=$RED ; res="EMPTY" ;;
    esac

    printf "%-18s | %-15s | ${res_color}%-12s${NC} | %s\n" "$dns" "$desc" "$res" "$ips"
  done
  echo "$SEPARATOR"
fi

# ============================================================
# [3] SSL/TLS — Handshake + chain fetch
# ============================================================

print_section "[3] SSL/TLS — Certificate analysis"

if ! command -v openssl >/dev/null 2>&1; then
  echo -e "${RED}ERROR: openssl is required but not found in PATH.${NC}"
  echo
  echo "Skipping SSL/TLS section."
  exit 0
fi

TMP_DIR=$(mktemp -d "/tmp/ssl_probe_${DOMAIN//[^A-Za-z0-9._-]/_}_XXXXXX")
RAW_OUTPUT="$TMP_DIR/s_client.txt"
CHAIN_PEM="$TMP_DIR/chain.pem"
CERT_PREFIX="$TMP_DIR/cert"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

CA_OPT=()
CA_DESC="system default CA store"
if [ -n "$CA_FILE" ]; then
  if [ ! -r "$CA_FILE" ]; then
    echo -e "${RED}ERROR: CA file does not exist or is not readable: $CA_FILE${NC}"
    exit 1
  fi
  CA_OPT=(-CAfile "$CA_FILE")
  CA_DESC="$CA_FILE"
fi

print_kv "CA source:" "$CA_DESC"

echo
echo "--- Fetching TLS handshake and certificate chain ---"
if ! openssl s_client \
  -connect "${DOMAIN}:${PORT}" \
  -servername "$DOMAIN" \
  -showcerts \
  -verify_return_error \
  "${CA_OPT[@]}" \
  </dev/null >"$RAW_OUTPUT" 2>&1; then
  echo "TLS handshake returned a non-zero exit code."
  echo "Continuing with captured output for diagnostics."
fi

if ! awk '
    /-----BEGIN CERTIFICATE-----/, /-----END CERTIFICATE-----/ { print }
' "$RAW_OUTPUT" >"$CHAIN_PEM"; then
  echo -e "${RED}ERROR: Failed to extract certificate chain from openssl output.${NC}"
  exit 1
fi

CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$CHAIN_PEM" || true)
print_kv "Certificates returned:" "$CERT_COUNT"

if [ "$CERT_COUNT" -eq 0 ]; then
  echo -e "${RED}ERROR: No certificate was returned by the remote endpoint.${NC}"
  echo
  echo "Raw handshake tail:"
  tail -n 30 "$RAW_OUTPUT"
  exit 1
elif [ "$CERT_COUNT" -eq 1 ]; then
  echo "Warning: only one certificate returned. Missing intermediate CA is likely."
else
  echo "Chain appears to include multiple certificates."
fi

awk -v prefix="$CERT_PREFIX" '
    /-----BEGIN CERTIFICATE-----/ {
        idx++
        file=sprintf("%s_%02d.pem", prefix, idx)
    }
    idx > 0 { print >> file }
    /-----END CERTIFICATE-----/ {
        close(file)
    }
' "$CHAIN_PEM"

# ============================================================
# [4] SSL/TLS — Connection summary
# ============================================================

print_section "[4] SSL/TLS — Connection summary"

CONNECTED_LINE=$(grep -m1 '^CONNECTED' "$RAW_OUTPUT" || true)
PROTO_LINE=$(grep -m1 '^[[:space:]]*Protocol[[:space:]]*:' "$RAW_OUTPUT" || true)
CIPHER_LINE=$(grep -m1 '^[[:space:]]*Cipher[[:space:]]*:' "$RAW_OUTPUT" || true)
VERIFY_LINE=$(grep -m1 'Verify return code:' "$RAW_OUTPUT" || true)
PEER_LINE=$(grep -m1 '^[[:space:]]*Peer signature type:' "$RAW_OUTPUT" || true)
TEMP_KEY_LINE=$(grep -m1 '^[[:space:]]*Server Temp Key:' "$RAW_OUTPUT" || true)

print_kv "Connected:" "${CONNECTED_LINE:-not available}"
print_kv "Protocol:" "${PROTO_LINE#*: }"
print_kv "Cipher:" "${CIPHER_LINE#*: }"
print_kv "Peer signature:" "${PEER_LINE#*: }"
print_kv "Server temp key:" "${TEMP_KEY_LINE#*: }"
print_kv "Verify result:" "${VERIFY_LINE:-not available}"

# ============================================================
# [5] SSL/TLS — Per-certificate details
# ============================================================

print_section "[5] SSL/TLS — Per-certificate details"

for cert_file in "$CERT_PREFIX"_*.pem; do
  [ -f "$cert_file" ] || continue

  CERT_NAME=$(basename "$cert_file")
  SUBJECT=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/^subject=//')
  ISSUER=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | sed 's/^issuer=//')
  SERIAL=$(openssl x509 -in "$cert_file" -noout -serial 2>/dev/null | sed 's/^serial=//')
  DATES=$(openssl x509 -in "$cert_file" -noout -dates 2>/dev/null)
  NOT_BEFORE=$(printf "%s\n" "$DATES" | sed -n 's/^notBefore=//p')
  NOT_AFTER=$(printf "%s\n" "$DATES" | sed -n 's/^notAfter=//p')
  SAN=$(openssl x509 -in "$cert_file" -noout -ext subjectAltName 2>/dev/null | sed '1d' | sed 's/^[[:space:]]*//')
  IS_CA=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -m1 'CA:' | sed 's/^[[:space:]]*//')

  echo "--- ${CERT_NAME} ---"
  print_kv "Subject:" "${SUBJECT:-not available}"
  print_kv "Issuer:" "${ISSUER:-not available}"
  print_kv "Serial:" "${SERIAL:-not available}"
  print_kv "Not before:" "${NOT_BEFORE:-not available}"
  print_kv "Not after:" "${NOT_AFTER:-not available}"
  print_kv "Basic constraints:" "${IS_CA:-not available}"
  if [ -n "$SAN" ]; then
    print_kv "SAN:" "$SAN"
  else
    print_kv "SAN:" "not present or not readable"
  fi
  echo
done

# ============================================================
# [6] SSL/TLS — Hostname verification
# ============================================================

print_section "[6] SSL/TLS — Hostname verification"

if openssl x509 -in "${CERT_PREFIX}_01.pem" -noout -checkhost "$DOMAIN" >/dev/null 2>&1; then
  print_kv "Leaf cert host match:" "PASS"
else
  print_kv "Leaf cert host match:" "FAIL"
fi

# ============================================================
# [7] SSL/TLS — Chain verification
# ============================================================

print_section "[7] SSL/TLS — Chain verification"

LEAF_CERT="${CERT_PREFIX}_01.pem"
UNTRUSTED_CHAIN="$TMP_DIR/untrusted_chain.pem"

if [ "$CERT_COUNT" -gt 1 ]; then
  cat "$CERT_PREFIX"_0[2-9].pem "$CERT_PREFIX"_[1-9][0-9].pem 2>/dev/null >"$UNTRUSTED_CHAIN" || true
fi

VERIFY_OUTPUT="$TMP_DIR/verify.txt"
if [ -s "$UNTRUSTED_CHAIN" ]; then
  openssl verify "${CA_OPT[@]}" -untrusted "$UNTRUSTED_CHAIN" "$LEAF_CERT" >"$VERIFY_OUTPUT" 2>&1 || true
else
  openssl verify "${CA_OPT[@]}" "$LEAF_CERT" >"$VERIFY_OUTPUT" 2>&1 || true
fi
cat "$VERIFY_OUTPUT"

# ============================================================
# [8] SSL/TLS — SNI vs direct-IP cross-check
# ============================================================

# Bonus: when we have a resolved public IP, probe the same endpoint by IP (still
# with SNI = $DOMAIN). If the certificate returned differs from the SNI-only probe,
# the host is likely behind a CDN/load-balancer presenting different certs per
# edge or path. This catches a common footgun where DNS points one way and TLS
# terminates elsewhere.
print_section "[8] SSL/TLS — SNI vs direct-IP cross-check"

if [ -z "$FIRST_PUBLIC_IP" ]; then
  echo "No public IP resolved from section [2] — skipping direct-IP probe."
else
  print_kv "Probing IP:" "$FIRST_PUBLIC_IP  (with SNI=$DOMAIN)"
  echo
  DIRECT_OUTPUT="$TMP_DIR/s_client_direct.txt"
  if ! openssl s_client \
    -connect "${FIRST_PUBLIC_IP}:${PORT}" \
    -servername "$DOMAIN" \
    "${CA_OPT[@]}" \
    </dev/null >"$DIRECT_OUTPUT" 2>&1; then
    echo "Direct-IP handshake returned a non-zero exit code (likely SNI mismatch or filtered)."
  fi

  # Compare the leaf certificate subject between SNI-only and direct-IP
  DIRECT_LEAF_SUBJECT=$(awk '
      /-----BEGIN CERTIFICATE-----/ { capture=1; subj=""; next }
      capture && /subject=/ { print; capture=0 }
  ' "$DIRECT_OUTPUT" | head -1 | sed 's/^subject=//')

  SNI_LEAF_SUBJECT=$(openssl x509 -in "$LEAF_CERT" -noout -subject 2>/dev/null | sed 's/^subject=//')

  print_kv "SNI probe leaf subject:"    "${SNI_LEAF_SUBJECT:-not available}"
  print_kv "Direct-IP probe leaf subj:" "${DIRECT_LEAF_SUBJECT:-not available}"

  if [ -n "$DIRECT_LEAF_SUBJECT" ] && [ "$SNI_LEAF_SUBJECT" = "$DIRECT_LEAF_SUBJECT" ]; then
    echo -e "Result: ${GREEN}identical${NC} — DNS and TLS path agree."
  elif [ -z "$DIRECT_LEAF_SUBJECT" ]; then
    echo -e "Result: ${YELLOW}could not extract${NC} — endpoint may refuse IP-based connection or SNI mismatch."
  else
    echo -e "Result: ${YELLOW}DIFFERENT${NC} — endpoint is likely behind a CDN/LB presenting per-edge certs. Investigate."
  fi
fi

# ============================================================
# [9] Diagnosis guide
# ============================================================

print_section "[9] Diagnosis guide"
echo "- CERT_COUNT = 0: check DNS, network path, load balancer listener, firewall, SNI, or TLS termination point."
echo "- CERT_COUNT = 1: server likely returns only the leaf certificate; check fullchain configuration on LB / ingress / nginx / kong."
echo "- Verify return code 20: chain was presented but local CA store cannot anchor it to a trusted issuer."
echo "- Verify return code 21: server likely omitted an intermediate certificate, or the presented chain is incomplete."
echo "- Hostname verification FAIL: certificate SAN/CN does not match the requested domain."
echo "- If custom CA passes but system CA fails: the endpoint is probably signed by an internal CA not present in the current trust store."
echo "- Section [8] DIFFERENT: CDN/LB returns different certs depending on edge or connection path. Validate against expected issuer."
echo "- DNS split (public vs private IPs across resolvers): may indicate GeoDNS, hijacking, or split-horizon DNS."

# ============================================================
# [10] Temporary artifacts
# ============================================================

print_section "[10] Temporary artifacts"
echo "Raw openssl output was captured at: $RAW_OUTPUT"
echo "Per-certificate PEM files were created under: $TMP_DIR"
echo "Artifacts will be removed automatically when the script exits."

echo
echo "$HEAVY"
echo -e "FQDN verification completed at $(date '+%Y-%m-%d %H:%M:%S')"
echo "$HEAVY"
