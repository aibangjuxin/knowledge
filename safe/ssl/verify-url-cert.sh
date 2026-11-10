#!/usr/bin/env bash

# verify-url-cert.sh
# Purpose: One-shot TLS/certificate inspection for a URL, focused on CWE-326
#          (Inadequate Encryption Strength) of the key material the endpoint
#          actually presents, plus the protocol/cipher posture around it.
#
# Usage:   verify-url-cert.sh <url> [port] [ca-file-path]
# Example: verify-url-cert.sh https://time.caep.uk/html
#          verify-url-cert.sh internal.example.com 8443 /etc/ssl/certs/ca-certificates.crt
#
# Baseline: safe/cwe/cwe-326.md §6.1 (NIST SP 800-57 / SP 800-131A / OWASP)
#
# Exit codes: 0 = clean or advisory only, 1 = usage/tool error, 2 = CRITICAL findings

set -u

# ============================================================
# Configuration
# ============================================================

TIMEOUT=10                      # per-probe timeout (seconds)
CONNECT_TIMEOUT=8

# ANSI color codes — $'...' so the bytes are real ESC sequences and survive
# printf "%s" (a plain '\033[32m' string would print literally).
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
RED=$'\033[31m'
CYAN=$'\033[36m'
NC=$'\033[0m'
BOLD=$'\033[1m'
SEPARATOR="----------------------------------------------------------------"
HEAVY="=================================================="

# ============================================================
# CLI parsing
# ============================================================

RAW_TARGET="${1:-}"
PORT_OVERRIDE="${2:-}"
CA_FILE="${3:-}"

if [ -z "$RAW_TARGET" ] || [ "$RAW_TARGET" = "-h" ] || [ "$RAW_TARGET" = "--help" ]; then
  echo -e "${GREEN}verify-url-cert.sh${NC} — TLS certificate & encryption-strength check (CWE-326)"
  echo
  echo "Usage: $0 <url> [port] [ca-file-path]"
  echo "Example: $0 https://time.caep.uk/html"
  echo "         $0 internal.example.com 8443 /etc/ssl/certs/ca-certificates.crt"
  echo
  echo "The URL may carry a scheme and a path; both are stripped to reach the host:"
  echo "  https://time.caep.uk/html  ->  time.caep.uk:443"
  exit 1
fi

# ============================================================
# URL parsing
# ============================================================

URL_SCHEME="https"
URL_HOST=""
URL_PORT=""
URL_PATH="/"
URL_QUERY=""

parse_target() {
  local raw="$1" authority rest port_part

  # --- scheme ---
  if [[ "$raw" =~ ^([A-Za-z][A-Za-z0-9+.\-]*)://(.*)$ ]]; then
    URL_SCHEME="${BASH_REMATCH[1],,}"
    raw="${BASH_REMATCH[2]}"
  fi

  # --- authority vs path ---
  if [[ "$raw" == */* ]]; then
    authority="${raw%%/*}"
    rest="${raw#*/}"
    if [[ "$rest" == *\?* ]]; then
      URL_PATH="/${rest%%\?*}"
      URL_QUERY="${rest#*\?}"
    else
      URL_PATH="/$rest"
    fi
  else
    authority="$raw"
  fi

  # --- host vs port (handle [::1]:443) ---
  port_part=""
  if [[ "$authority" == \[*\]* ]]; then
    URL_HOST="${authority%%\]*}]"
    port_part="${authority#*\]}"
    port_part="${port_part#:}"
  elif [[ "$authority" == *:* ]]; then
    URL_HOST="${authority%%:*}"
    port_part="${authority##*:}"
  else
    URL_HOST="$authority"
  fi

  if [[ "$port_part" =~ ^[0-9]+$ ]]; then
    URL_PORT="$port_part"
  fi

  # --- default port by scheme ---
  if [ -z "$URL_PORT" ]; then
    case "$URL_SCHEME" in
      http)  URL_PORT=80 ;;
      https) URL_PORT=443 ;;
      *)     URL_PORT=443 ;;
    esac
  fi
}

parse_target "$RAW_TARGET"

if [ -z "$PORT_OVERRIDE" ]; then
  PORT="$URL_PORT"
else
  PORT="$PORT_OVERRIDE"
fi

if [ -z "$URL_HOST" ]; then
  echo -e "${RED}ERROR: could not determine a host from '${RAW_TARGET}'.${NC}"
  exit 1
fi

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo -e "${RED}ERROR: invalid port: ${PORT}${NC}"
  exit 1
fi

# SNI is only sent for real DNS names, never for IP literals.
IS_IP=0
if [[ "$URL_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$URL_HOST" == *:* ]]; then
  IS_IP=1
fi

SNI_OPT=()
if [ "$IS_IP" -eq 0 ]; then
  SNI_OPT=(-servername "$URL_HOST")
fi

if [ "$URL_SCHEME" = "http" ]; then
  echo -e "${RED}ERROR: target scheme is 'http' — there is no TLS layer to inspect.${NC}"
  echo "       That is a cleartext-transport finding (CWE-319), not a CWE-326 one."
  exit 1
fi

# ============================================================
# Helpers
# ============================================================

print_kv() {
  printf "%-26s %s\n" "$1" "$2"
}

# Extract the value from a "<label>: <value>" handshake line.
#
# An absent line must render as an explicit "not available" rather than as an
# empty string, which would look like a missing value for a field that is
# genuinely not reported (e.g. "Temp Key:" does not exist under TLS 1.3).
kv_from_line() {
  local line="$1"
  if [ -z "$line" ]; then
    printf "not available"
  else
    printf "%s" "${line#*: }"
  fi
}

print_section() {
  echo
  echo "$HEAVY"
  echo "$1"
  echo "$HEAVY"
}

# Findings ledger — "SEVERITY|AREA|DETAIL"
declare -a FINDINGS=()
CRIT_COUNT=0
WARN_COUNT=0

add_finding() {
  FINDINGS+=("$1|$2|$3")
  case "$1" in
    CRITICAL) CRIT_COUNT=$((CRIT_COUNT + 1)) ;;
    WARNING)  WARN_COUNT=$((WARN_COUNT + 1)) ;;
  esac
}

sev_color() {
  case "$1" in
    CRITICAL) printf "%s" "$RED" ;;
    WARNING)  printf "%s" "$YELLOW" ;;
    PASS)     printf "%s" "$GREEN" ;;
    *)        printf "%s" "$NC" ;;
  esac
}

# ============================================================
# OpenSSL engine discovery
# ============================================================

if ! command -v openssl >/dev/null 2>&1; then
  echo -e "${RED}ERROR: openssl is required but not found in PATH.${NC}"
  exit 1
fi

# Detect the engine flavour (OpenSSL vs LibreSSL). They differ in cipher-list
# syntax (@SECLEVEL support) and, more importantly, in which algorithms they can
# even express — OpenSSL >= 3.5 dropped TLS 1.0/1.1 and RC4/3DES entirely,
# while LibreSSL still ships them. This drives the fallback logic below.
openssl_flavour() {
  local ver
  ver="$("$1" version 2>/dev/null)"
  case "$ver" in
    *LibreSSL*) printf "libressl" ;;
    *OpenSSL*)  printf "openssl" ;;
    *)          printf "unknown" ;;
  esac
}

# Build the -cipher spec for an engine.
#   OpenSSL : "<cipher>:@SECLEVEL=0"  — SECLEVEL=0 is required even to *offer*
#             the legacy algorithms for a negative (test) handshake.
#   LibreSSL: "<cipher>"              — no @SECLEVEL support.
cipher_spec() {
  local flavour="$1" cipher="$2"
  if [ "$flavour" = "openssl" ]; then
    printf "%s:@SECLEVEL=0" "$cipher"
  else
    printf "%s" "$cipher"
  fi
}

# List the cipher names an engine can express.
#
# For OpenSSL the legacy provider is not loaded by default, and it is where
# RC4/3DES live on many Linux builds. Union both lists so the gate in the
# cipher probe reflects what the engine can really offer, not just what the
# default provider happens to expose.
list_ciphers() {
  local bin="$1" flavour="$2"
  if [ "$flavour" = "openssl" ]; then
    {
      "$bin" ciphers -v 'ALL:@SECLEVEL=0' 2>/dev/null | awk '{print $1}'
      OPENSSL_CONF="$LEGACY_CONF" "$bin" ciphers -v -provider legacy -provider default 'ALL:@SECLEVEL=0' 2>/dev/null | awk '{print $1}'
    } | grep -v '^$' | sort -u
  else
    "$bin" ciphers 'ALL' 2>/dev/null | tr ':' '\n' | grep -v '^$' | sort -u
  fi
}

# Ordered list of candidate engines. The first is the default; the rest are
# fallbacks used when the default cannot express a legacy algorithm.
ENGINES=()
add_engine() {
  local candidate="$1" resolved existing
  [ -n "$candidate" ] || return 0
  resolved="$(command -v "$candidate" 2>/dev/null)" || return 0
  [ -x "$resolved" ] || return 0
  for existing in "${ENGINES[@]:-}"; do
    [ "$existing" = "$resolved" ] && return 0
  done
  ENGINES+=("$resolved")
}

add_engine "openssl"
add_engine "/usr/bin/openssl"     # LibreSSL on macOS — still ships RC4/3DES
add_engine "openssl@1.1"
add_engine "openssl@3"
add_engine "openssl@1.0"

if [ "${#ENGINES[@]}" -eq 0 ]; then
  echo -e "${RED}ERROR: no usable openssl binary found.${NC}"
  exit 1
fi

PRIMARY_ENGINE="${ENGINES[0]}"
PRIMARY_FLAVOUR="$(openssl_flavour "$PRIMARY_ENGINE")"

# ============================================================
# Handshake analysis — engine-agnostic
# ============================================================
#
# Two output dialects exist in the wild:
#   OpenSSL >= 3.x/4.x : "New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384"
#                         "Protocol: TLSv1.3"
#   OpenSSL 1.x/LibreSSL: an indented session block
#                         "    Protocol  : TLSv1.2"
#                         "    Cipher    : ECDHE-ECDSA-CHACHA20-POLY1305"
#
# On failure BOTH dialects print "New, (NONE), Cipher is (NONE)". That marker
# is the only reliable failure signal — note that the "Protocol:" line still
# shows the *default* protocol on a failed handshake, so it must never be used
# to infer success.
#
# hs_cipher <output>   -> negotiated cipher, or empty
# hs_protocol <output> -> negotiated protocol, or empty
hs_cipher() {
  local out="$1" v
  # OpenSSL 3.x/4.x flat form
  v=$(printf "%s\n" "$out" | grep -m1 -E '^New, .*, Cipher is ' | sed 's/^.*Cipher is //')
  if [ -z "$v" ] || [ "$v" = "(NONE)" ]; then
    # LibreSSL / OpenSSL 1.x session block
    v=$(printf "%s\n" "$out" | grep -m1 -E '^[[:space:]]*Cipher[[:space:]]*:' | sed 's/^[^:]*:[[:space:]]*//')
    if [ "$v" = "0000" ] || [ "$v" = "(NONE)" ]; then
      v=""
    fi
  fi
  printf "%s" "$v"
}

hs_protocol() {
  local out="$1" v
  # Session block form first (more precise than the flat "Protocol:" line)
  v=$(printf "%s\n" "$out" | grep -m1 -E '^[[:space:]]*Protocol[[:space:]]*:' | sed 's/^[^:]*:[[:space:]]*//')
  if [ -z "$v" ]; then
    v=$(printf "%s\n" "$out" | grep -m1 -E '^Protocol: ' | sed 's/^Protocol:[[:space:]]*//')
  fi
  [ "$v" = "(NONE)" ] && v=""
  printf "%s" "$v"
}

# Extract the finite-field DH group size from handshake output, in bits.
#
# The label differs between dialects: OpenSSL prints "Peer Temp Key: DH, N
# bits" while LibreSSL prints "Server Temp Key: DH, N bits". Both must match.
#
# Do NOT confuse this with "Server public key is N bit", which reports the
# certificate key size, not the DH group size.
dh_group_bits() {
  local out="$1" v
  v=$(printf "%s\n" "$out" | grep -m1 -E '(Peer|Server) Temp Key:[[:space:]]*DH,' | sed 's/.*DH,[[:space:]]*//')
  printf "%s" "$v" | grep -oE '[0-9]+' | head -1
}

# --- Temporary artifacts ---------------------------------------------------
#
# Defined before the legacy-compat config below, which lives in the same
# directory. `set -u` means an unset TMP_DIR would abort the script outright.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/urlcert_XXXXXX")"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

RAW_OUTPUT="$TMP_DIR/s_client.txt"
CHAIN_PEM="$TMP_DIR/chain.pem"
CERT_PREFIX="$TMP_DIR/cert"

# --- Legacy-compat probe profile -------------------------------------------
#
# OpenSSL >= 3.5 (and 4.x) refuses TLS 1.0/1.1 out of the box, so the probe
# fails locally with "no protocols available" and never reaches the server.
# Feeding an OPENSSL_CONF that lowers MinProtocol and the security level
# restores the ability to actually ask the server. Verified: OpenSSL 3.5.9
# with this config returns "tlsv1 alert protocol version" (a real server
# answer) where it previously returned "no protocols available".
#
# s_client has no -config flag in 3.x, so the config must be supplied through
# the OPENSSL_CONF environment variable.
LEGACY_CONF="$TMP_DIR/legacy_compat.cnf"
cat >"$LEGACY_CONF" <<'LEGCFG'
openssl_conf = default_conf

[default_conf]
ssl_conf = ssl_sect

[ssl_sect]
system_default = system_default_sect

[system_default_sect]
MinProtocol = TLSv1
CipherString = DEFAULT:@SECLEVEL=0
LEGCFG

# Probe one protocol version with one engine.
# Returns: SUPPORTED | REFUSED | CLIENT_UNSUPPORTED | UNREACHABLE | UNKNOWN
#
# The distinction that matters: a modern OpenSSL refuses TLS 1.0/1.1 locally
# with "no protocols available" before a single packet reaches the server. That
# is a client limitation, NOT evidence the server refuses the protocol. The two
# must never be conflated, or the report lies about the server.
#
# Note on the matching: the phrase "Secure Renegotiation IS NOT supported"
# appears in normal LibreSSL output, so a loose "not supported" pattern would
# misclassify a real server refusal as a client limitation. The patterns below
# are anchored to unambiguous OpenSSL error strings instead.
probe_protocol() {
  local engine="$1" flag="$2" out cipher
  out="$(timeout "$TIMEOUT" "$engine" s_client \
      -connect "${URL_HOST}:${PORT}" "${SNI_OPT[@]+"${SNI_OPT[@]}"}" "$flag" \
      </dev/null 2>&1)"

  cipher="$(hs_cipher "$out")"
  if [ -n "$cipher" ]; then
    printf "SUPPORTED"
    return
  fi

  # Client-side refusal to even try. Anchored on the OpenSSL error codes:
  #   no protocols available        -> protocol compiled out / disabled
  #   unsupported protocol          -> protocol disabled by policy
  if printf "%s" "$out" | grep -qiE 'no protocols available|unsupported protocol|no suitable protocol'; then
    printf "CLIENT_UNSUPPORTED"
    return
  fi
  # Server-side TLS alert.
  if printf "%s" "$out" | grep -qiE 'alert protocol version|alert handshake failure|wrong version number|alert illegal parameter|alert insufficient security|alert internal error'; then
    printf "REFUSED"
    return
  fi
  if printf "%s" "$out" | grep -qiE 'connection refused|operation timed out|no route to host|network is unreachable'; then
    printf "UNREACHABLE"
    return
  fi
  printf "UNKNOWN"
}

# Same as probe_protocol, but runs the engine under the legacy-compat config
# so it can actually offer TLS 1.0/1.1. Only meaningful for OpenSSL (LibreSSL
# has no openssl_conf support in this form).
probe_protocol_legacy() {
  local engine="$1" flag="$2" out cipher
  out="$(OPENSSL_CONF="$LEGACY_CONF" timeout "$TIMEOUT" "$engine" s_client \
      -connect "${URL_HOST}:${PORT}" "${SNI_OPT[@]+"${SNI_OPT[@]}"}" "$flag" \
      </dev/null 2>&1)"

  cipher="$(hs_cipher "$out")"
  if [ -n "$cipher" ]; then
    printf "SUPPORTED"
    return
  fi
  if printf "%s" "$out" | grep -qiE 'no protocols available|unsupported protocol|no suitable protocol'; then
    printf "CLIENT_UNSUPPORTED"
    return
  fi
  if printf "%s" "$out" | grep -qiE 'alert protocol version|alert handshake failure|wrong version number|alert illegal parameter|alert insufficient security|alert internal error'; then
    printf "REFUSED"
    return
  fi
  if printf "%s" "$out" | grep -qiE 'connection refused|operation timed out|no route to host|network is unreachable'; then
    printf "UNREACHABLE"
    return
  fi
  printf "UNKNOWN"
}

# ============================================================
# Temporary artifacts
# ============================================================

# (Temporary artifacts — TMP_DIR and the legacy-compat config — are created
#  above, before the handshake helpers that consume them.)

# ============================================================
# Header
# ============================================================

echo
echo "$HEAVY"
echo "TLS / certificate report for: ${URL_HOST}:${PORT}"
echo "$HEAVY"
echo "Target URL:      ${RAW_TARGET}"
echo "Parsed host:     ${URL_HOST}"
echo "Parsed port:     ${PORT}"
echo "Parsed path:     ${URL_PATH}${URL_QUERY:+?$URL_QUERY}"
echo "SNI sent:        $([ "$IS_IP" -eq 0 ] && echo "${URL_HOST}" || echo "(none - IP literal)")"
echo "Primary engine:  $PRIMARY_ENGINE (${PRIMARY_FLAVOUR})"
echo "Generated:       $(date '+%Y-%m-%d %H:%M:%S')"
echo "$HEAVY"

# ============================================================
# [1] DNS resolution
# ============================================================

print_section "[1] DNS — name resolution"

if command -v dig >/dev/null 2>&1; then
  DNS_OUT=$(dig +short "$URL_HOST" A 2>/dev/null)
  DNS_OUT6=$(dig +short "$URL_HOST" AAAA 2>/dev/null)
else
  DNS_OUT=""
  DNS_OUT6=""
  echo -e "${YELLOW}'dig' not available — skipping explicit DNS resolution.${NC}"
fi

if [ -n "$DNS_OUT" ] || [ -n "$DNS_OUT6" ]; then
  [ -n "$DNS_OUT" ] && echo -e "A     records: ${GREEN}${DNS_OUT//$'\n'/, }${NC}"
  [ -n "$DNS_OUT6" ] && echo -e "AAAA  records: ${GREEN}${DNS_OUT6//$'\n'/, }${NC}"
else
  echo "No A/AAAA records returned (host may be an IP literal, or resolved via a local resolver)."
fi

# ============================================================
# [2] TLS handshake and certificate chain
# ============================================================

print_section "[2] TLS — handshake and certificate chain"

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
if ! timeout "$CONNECT_TIMEOUT" "$PRIMARY_ENGINE" s_client \
  -connect "${URL_HOST}:${PORT}" \
  "${SNI_OPT[@]+"${SNI_OPT[@]}"}" \
  -showcerts \
  -verify_return_error \
  "${CA_OPT[@]+"${CA_OPT[@]}"}" \
  </dev/null >"$RAW_OUTPUT" 2>&1; then
  echo "TLS handshake returned a non-zero exit code."
  echo "Continuing with captured output for diagnostics."
fi

awk '
  /-----BEGIN CERTIFICATE-----/, /-----END CERTIFICATE-----/ { print }
' "$RAW_OUTPUT" >"$CHAIN_PEM"

# Count certificates with awk, not `grep -c`: grep prints "0" AND exits 1 when
# there is no match, so the common `grep -c ... || echo 0` idiom yields a
# two-line value ("0\n0") that breaks the integer comparison below.
CERT_COUNT=$(awk '/BEGIN CERTIFICATE/{n++} END{print n+0}' "$CHAIN_PEM")
print_kv "Certificates returned:" "$CERT_COUNT"

if [ "$CERT_COUNT" -eq 0 ]; then
  echo -e "${RED}ERROR: no certificate was returned by the remote endpoint.${NC}"
  if grep -qiE 'name or service not known|could not resolve|nodename nor servname' "$RAW_OUTPUT"; then
    echo "The hostname could not be resolved."
  elif grep -qiE 'connection refused|network is unreachable|no route to host' "$RAW_OUTPUT"; then
    echo "The host was reachable by name but refused the connection on port ${PORT}."
  elif grep -qiE 'operation timed out|i/o timeout' "$RAW_OUTPUT"; then
    echo "The connection to ${URL_HOST}:${PORT} timed out after ${CONNECT_TIMEOUT}s."
  fi
  echo
  echo "Raw handshake tail:"
  tail -n 25 "$RAW_OUTPUT"
  exit 1
elif [ "$CERT_COUNT" -eq 1 ]; then
  echo -e "${YELLOW}Warning: only one certificate returned — a missing intermediate CA is likely.${NC}"
  add_finding "WARNING" "Chain" "Server presented only the leaf certificate (intermediate CA likely missing)"
fi

awk -v prefix="$CERT_PREFIX" '
  /-----BEGIN CERTIFICATE-----/ { idx++; file=sprintf("%s_%02d.pem", prefix, idx) }
  idx > 0 { print >> file }
  /-----END CERTIFICATE-----/ { close(file) }
' "$CHAIN_PEM"

# ============================================================
# [3] Connection summary
# ============================================================

print_section "[3] TLS — connection summary"

# hs_* take the captured output as *content*, not a path.
RAW_CONTENT="$(<"$RAW_OUTPUT")"
PROTO="$(hs_protocol "$RAW_CONTENT")"
CIPHER="$(hs_cipher "$RAW_CONTENT")"

VERIFY_LINE=$(grep -m1 'Verify return code:' "$RAW_OUTPUT" || true)
PEER_LINE=$(grep -m1 -E '^[[:space:]]*Peer signature type:' "$RAW_OUTPUT" || true)
DIGEST_LINE=$(grep -m1 -E '^[[:space:]]*Peer signing digest:' "$RAW_OUTPUT" || true)
HASH_LINE=$(grep -m1 -E '^[[:space:]]*Hash used:' "$RAW_OUTPUT" || true)
TEMP_KEY_LINE=$(grep -m1 -E '(Peer|Server) Temp Key:' "$RAW_OUTPUT" || true)
GROUP_LINE=$(grep -m1 -E '^[[:space:]]*Negotiated TLS1.3 group:' "$RAW_OUTPUT" || true)

print_kv "Negotiated protocol:" "${PROTO:-not available}"
print_kv "Negotiated cipher:" "${CIPHER:-not available}"
print_kv "Peer signature type:" "$(kv_from_line "$PEER_LINE")"
print_kv "Peer signing digest:" "$(kv_from_line "$DIGEST_LINE")"
print_kv "Handshake hash:" "$(kv_from_line "$HASH_LINE")"
print_kv "Key-exchange group:" "$(kv_from_line "$GROUP_LINE")"
print_kv "Server temp key:" "$(kv_from_line "$TEMP_KEY_LINE")"
print_kv "Verify result:" "${VERIFY_LINE:-not available}"

# --- DH / key-exchange parameter strength -----------------------------------
# The baseline (safe/cwe/cwe-326.md §6.1) puts DSA/DH 512/1024 in the
# "unacceptable" column and 2048 as the minimum.
#
# Careful: "Server public key is N bit" reports the CERTIFICATE key size, not
# the DH group size (verified against a 2048-bit cert with 1024-bit DH, which
# printed 2048). The ephemeral DH size lives in "Server Temp Key: DH, N bits".
DH_BITS="$(dh_group_bits "$RAW_CONTENT")"

if [ -n "$DH_BITS" ]; then
  if [ "$DH_BITS" -lt 2048 ]; then
    print_kv "DH param size:" "${RED}CRITICAL — ${DH_BITS}-bit DH group is below the 2048-bit baseline${NC}"
    add_finding "CRITICAL" "DH params" "Negotiated DH group is ${DH_BITS} bits; the baseline requires 2048"
  else
    print_kv "DH param size:" "${GREEN}PASS — ${DH_BITS}-bit DH group meets the baseline${NC}"
  fi
else
  print_kv "DH param size:" "not applicable (no finite-field DH key exchange negotiated)"
fi

case "$PROTO" in
  *TLSv1.3*) print_kv "Protocol verdict:" "${GREEN}PASS — TLS 1.3 is the recommended floor${NC}" ;;
  *TLSv1.2*) print_kv "Protocol verdict:" "${YELLOW}WARN — TLS 1.2 is acceptable, TLS 1.3 preferred${NC}" ;;
  *TLSv1.1*|*TLSv1*) print_kv "Protocol verdict:" "${RED}CRITICAL — TLS 1.0/1.1 are below the CWE-326 baseline${NC}" ;;
esac

# ============================================================
# [4] Per-certificate details
# ============================================================

print_section "[4] Certificates — per-certificate detail and key-strength assessment"

# Map an EC curve to its NIST security strength in bits.
ec_security_bits() {
  case "$1" in
    secp192r1|prime192v1|P-192)  printf "96"  ;;
    secp224r1|P-224)             printf "112" ;;
    prime256v1|secp256r1|P-256)  printf "128" ;;
    secp384r1|P-384)             printf "192" ;;
    secp521r1|P-521)             printf "256" ;;
    X25519|x25519)               printf "128" ;;
    X448)                        printf "224" ;;
    *)                           printf ""   ;;
  esac
}

# Map a signature algorithm to its hash strength.
sig_hash_of() {
  case "$1" in
    *md5*|*MD5*)     printf "MD5"     ;;
    *sha1*|*SHA1*)   printf "SHA-1"   ;;
    *sha224*|*SHA224*) printf "SHA-224" ;;
    *sha256*|*SHA256*) printf "SHA-256" ;;
    *sha384*|*SHA384*) printf "SHA-384" ;;
    *sha512*|*SHA512*) printf "SHA-512" ;;
    *ED25519*|*Ed25519*) printf "Ed25519" ;;
    *ED448*|*Ed448*)     printf "Ed448"   ;;
    *)               printf ""       ;;
  esac
}

CERT_INDEX=0
for cert_file in "$CERT_PREFIX"_*.pem; do
  [ -f "$cert_file" ] || continue
  CERT_INDEX=$((CERT_INDEX + 1))

  CERT_TEXT=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null)

  SUBJECT=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/^subject=//')
  ISSUER=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | sed 's/^issuer=//')
  SERIAL=$(openssl x509 -in "$cert_file" -noout -serial 2>/dev/null | sed 's/^serial=//')
  NOT_BEFORE=$(openssl x509 -in "$cert_file" -noout -startdate 2>/dev/null | sed 's/^notBefore=//')
  NOT_AFTER=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')
  SAN=$(openssl x509 -in "$cert_file" -noout -ext subjectAltName 2>/dev/null | sed '1d' | sed 's/^[[:space:]]*//')
  IS_CA=$(printf "%s\n" "$CERT_TEXT" | grep -m1 'CA:' | sed 's/^[[:space:]]*//')
  # "No extensions in certificate" means the extension is absent, which is
  # different from a parse failure — report it as "not present".
  KEY_USAGE=$(openssl x509 -in "$cert_file" -noout -ext keyUsage 2>/dev/null | tail -n +2 | tr '\n' ',' | sed 's/,$//;s/^[[:space:]]*//')
  EKU=$(openssl x509 -in "$cert_file" -noout -ext extendedKeyUsage 2>/dev/null | tail -n +2 | tr '\n' ',' | sed 's/,$//;s/^[[:space:]]*//')
  [ "$KEY_USAGE" = "No extensions in certificate" ] && KEY_USAGE=""
  [ "$EKU" = "No extensions in certificate" ] && EKU=""

  PUB_ALGO=$(printf "%s\n" "$CERT_TEXT" | grep -m1 'Public Key Algorithm:' | sed 's/.*Public Key Algorithm:[[:space:]]*//')
  PUB_BITS=$(printf "%s\n" "$CERT_TEXT" | grep -m1 -E 'Public-Key: \([0-9]+ bit' | sed -E 's/.*Public-Key: \(([0-9]+) bit.*/\1/')
  CURVE_OID=$(printf "%s\n" "$CERT_TEXT" | grep -m1 'ASN1 OID:' | sed 's/.*ASN1 OID:[[:space:]]*//')
  CURVE_NAME=$(printf "%s\n" "$CERT_TEXT" | grep -m1 'NIST CURVE:' | sed 's/.*NIST CURVE:[[:space:]]*//')

  SIG_ALGO=$(printf "%s\n" "$CERT_TEXT" | grep -m1 'Signature Algorithm:' | sed 's/.*Signature Algorithm:[[:space:]]*//')
  SIG_HASH=$(sig_hash_of "$SIG_ALGO")
  # RSA-PSS names the hash separately; recover it from the algorithm parameters.
  if [ -z "$SIG_HASH" ] || [ "$SIG_HASH" = "PSS" ]; then
    PSS_HASH=$(printf "%s\n" "$CERT_TEXT" | grep -m1 -iE 'Hash Algorithm:' | sed 's/.*Hash Algorithm:[[:space:]]*//' | tr 'A-Z' 'a-z')
    if [ -n "$PSS_HASH" ]; then
      case "$PSS_HASH" in
        sha256) SIG_HASH="SHA-256" ;;
        sha384) SIG_HASH="SHA-384" ;;
        sha512) SIG_HASH="SHA-512" ;;
        sha1)   SIG_HASH="SHA-1" ;;
        md5)    SIG_HASH="MD5" ;;
        *)      SIG_HASH="${PSS_HASH}" ;;
      esac
    fi
  fi

  # Role: leaf is always first. The last cert is only a root if it is
  # self-signed (subject == issuer) — otherwise it is a cross-signed
  # intermediate, which is a common and easy-to-misread case.
  ROLE="intermediate / issuer"
  if [ "$CERT_INDEX" -eq 1 ]; then
    ROLE="leaf (end-entity)"
  elif [ "$SUBJECT" = "$ISSUER" ]; then
    ROLE="root (self-signed)"
  elif [ "$CERT_INDEX" -eq "$CERT_COUNT" ]; then
    ROLE="intermediate (cross-signed — subject != issuer)"
  fi

  echo "--- cert_$(printf '%02d' "$CERT_INDEX")  [$ROLE] ---"
  print_kv "Subject:" "${SUBJECT:-not available}"
  print_kv "Issuer:" "${ISSUER:-not available}"
  print_kv "Serial:" "${SERIAL:-not available}"
  print_kv "Valid from:" "${NOT_BEFORE:-not available}"
  print_kv "Valid until:" "${NOT_AFTER:-not available}"
  print_kv "Public key algo:" "${PUB_ALGO:-not available}"
  if [ -n "$CURVE_NAME" ]; then
    print_kv "Curve:" "$CURVE_NAME (OID $CURVE_OID)"
  elif [ -n "$CURVE_OID" ]; then
    print_kv "Curve OID:" "$CURVE_OID"
  fi
  print_kv "Public key size:" "${PUB_BITS:-n/a} bit"
  print_kv "Signature algo:" "${SIG_ALGO:-not available}"
  print_kv "Signature hash:" "${SIG_HASH:-not available}"
  print_kv "Basic constraints:" "${IS_CA:-not available}"
  print_kv "Key usage:" "${KEY_USAGE:-not present}"
  print_kv "Extended key usage:" "${EKU:-not present}"
  if [ -n "$SAN" ]; then
    print_kv "SAN:" "$SAN"
  else
    print_kv "SAN:" "not present"
  fi

  # --- CWE-326 key strength verdict ---
  KEY_VERDICT="PASS"
  KEY_REASON=""

  case "$PUB_ALGO" in
    rsaEncryption)
      if [ -n "$PUB_BITS" ] && [ "$PUB_BITS" -lt 2048 ]; then
        KEY_VERDICT="CRITICAL"
        KEY_REASON="RSA ${PUB_BITS}-bit public key is below the 2048-bit baseline"
      elif [ -n "$PUB_BITS" ] && [ "$PUB_BITS" -lt 3072 ]; then
        KEY_REASON="RSA ${PUB_BITS}-bit meets the 2048-bit baseline (3072 recommended for long-term data)"
      elif [ -n "$PUB_BITS" ]; then
        KEY_REASON="RSA ${PUB_BITS}-bit exceeds the baseline"
      else
        KEY_REASON="RSA key size could not be parsed"
      fi
      ;;
    dsaEncryption|id-dsa)
      if [ -n "$PUB_BITS" ] && [ "$PUB_BITS" -lt 2048 ]; then
        KEY_VERDICT="CRITICAL"
        KEY_REASON="DSA ${PUB_BITS}-bit public key is below the 2048-bit baseline"
      else
        KEY_REASON="DSA ${PUB_BITS:-?} bit meets the baseline"
      fi
      ;;
    id-ecPublicKey|ecPublicKey)
      SEC_BITS=$(ec_security_bits "${CURVE_OID:-$CURVE_NAME}")
      if [ -n "$PUB_BITS" ] && [ "$PUB_BITS" -lt 256 ]; then
        KEY_VERDICT="CRITICAL"
        KEY_REASON="EC curve ${CURVE_NAME:-$CURVE_OID} (${PUB_BITS} bit, ${SEC_BITS:-?} bit security) is below the P-256 baseline"
      elif [ -n "$PUB_BITS" ] && [ "$PUB_BITS" -ge 384 ]; then
        KEY_REASON="EC curve ${CURVE_NAME:-$CURVE_OID} (${PUB_BITS} bit, ${SEC_BITS:-?} bit security) exceeds the baseline"
      else
        KEY_REASON="EC curve ${CURVE_NAME:-$CURVE_OID} (${PUB_BITS} bit, ${SEC_BITS:-?} bit security) meets the P-256 baseline"
      fi
      ;;
    ED25519|id-Ed25519)
      KEY_REASON="Ed25519 (128-bit security) — modern, exceeds the baseline"
      ;;
    ED448|id-Ed448)
      KEY_REASON="Ed448 (224-bit security) — modern, exceeds the baseline"
      ;;
    "")
      KEY_VERDICT="WARNING"
      KEY_REASON="public key algorithm could not be parsed"
      ;;
    *)
      KEY_REASON="${PUB_ALGO} — not evaluated against the CWE-326 baseline"
      ;;
  esac

  # --- CWE-326 signature hash verdict ---
  SIG_VERDICT="PASS"
  case "$SIG_HASH" in
    MD5)
      SIG_VERDICT="CRITICAL"
      SIG_REASON="MD5 signature — broken hash (CWE-327), must be replaced"
      ;;
    SHA-1)
      SIG_VERDICT="CRITICAL"
      SIG_REASON="SHA-1 signature — deprecated for certificate signing since 2017"
      ;;
    SHA-224)
      SIG_VERDICT="WARNING"
      SIG_REASON="SHA-224 signature — below the SHA-256 baseline"
      ;;
    "")
      SIG_VERDICT="WARNING"
      SIG_REASON="signature algorithm could not be parsed"
      ;;
    *)
      SIG_REASON="${SIG_HASH} signature — meets the SHA-256 baseline"
      ;;
  esac

  print_kv "Key strength verdict:" "$(sev_color "$KEY_VERDICT")${KEY_VERDICT}${NC} — ${KEY_REASON}"
  print_kv "Signature verdict:" "$(sev_color "$SIG_VERDICT")${SIG_VERDICT}${NC} — ${SIG_REASON}"

  if [ "$CERT_INDEX" -eq 1 ]; then
    if [ "$KEY_VERDICT" = "CRITICAL" ]; then
      add_finding "CRITICAL" "Public key" "Leaf certificate: $KEY_REASON"
    fi
    if [ "$SIG_VERDICT" = "CRITICAL" ]; then
      add_finding "CRITICAL" "Signature" "Leaf certificate: $SIG_REASON"
    elif [ "$SIG_VERDICT" = "WARNING" ]; then
      add_finding "WARNING" "Signature" "Leaf certificate: $SIG_REASON"
    fi
  fi

  echo
done

# ============================================================
# [5] Protocol version support
# ============================================================

print_section "[5] TLS — protocol version support"

printf "%-10s | %-19s | %-34s | %s\n" "Version" "Result" "Client engine" "Verdict"
echo "$SEPARATOR"

probe_version() {
  local label="$1" flag="$2"
  local result="UNKNOWN" engine_used="-" flavour engine

  for engine in "${ENGINES[@]}"; do
    flavour="$(openssl_flavour "$engine")"
    result="$(probe_protocol "$engine" "$flag")"
    engine_used="$engine ($flavour)"
    if [ "$result" != "CLIENT_UNSUPPORTED" ]; then
      break
    fi
  done

  # The default engine could not offer this protocol at all. Retry under the
  # legacy-compat config, which restores TLS 1.0/1.1 support on OpenSSL 3.x/4.x
  # and turns an unanswered question into a real server response.
  if [ "$result" = "CLIENT_UNSUPPORTED" ]; then
    for engine in "${ENGINES[@]}"; do
      flavour="$(openssl_flavour "$engine")"
      [ "$flavour" = "openssl" ] || continue
      legacy_result="$(probe_protocol_legacy "$engine" "$flag")"
      if [ "$legacy_result" != "CLIENT_UNSUPPORTED" ]; then
        result="$legacy_result"
        engine_used="$engine ($flavour, legacy-compat config)"
        break
      fi
    done
  fi

  local verdict
  case "$result" in
    SUPPORTED)
      if [ "$label" = "TLS 1.0" ] || [ "$label" = "TLS 1.1" ]; then
        verdict="${RED}CRITICAL${NC} — accepted by server; below the TLS 1.2 baseline"
        add_finding "CRITICAL" "Protocol" "Server accepts $label, which is below the CWE-326 baseline (TLS 1.2 minimum)"
      elif [ "$label" = "TLS 1.2" ]; then
        verdict="${GREEN}PASS${NC} — meets the minimum baseline"
      else
        verdict="${GREEN}PASS${NC} — recommended"
      fi
      ;;
    REFUSED)
      verdict="${GREEN}PASS${NC} — server refused"
      ;;
    CLIENT_UNSUPPORTED)
      verdict="${YELLOW}UNKNOWN${NC} — no local engine can offer $label; not a server finding"
      ;;
    UNREACHABLE)
      verdict="${YELLOW}UNKNOWN${NC} — host unreachable from here"
      ;;
    *)
      verdict="${YELLOW}UNKNOWN${NC} — probe inconclusive"
      ;;
  esac

  printf "%-10s | %-19s | %-34s | %b\n" "$label" "$result" "$engine_used" "$verdict"
}

probe_version "TLS 1.0" "-tls1"
probe_version "TLS 1.1" "-tls1_1"
probe_version "TLS 1.2" "-tls1_2"
probe_version "TLS 1.3" "-tls1_3"

echo "$SEPARATOR"

# ============================================================
# [6] Cipher suite exposure
# ============================================================

print_section "[6] TLS — cipher suite exposure"

# Does the server negotiate TLS 1.2 at all? Legacy suites live in TLS 1.0/1.1/1.2;
# without TLS 1.2 the TLS 1.2-class probes below are meaningless.
TLS12_BASE=$(probe_protocol "$PRIMARY_ENGINE" "-tls1_2")

if [ "$TLS12_BASE" != "SUPPORTED" ]; then
  echo -e "${YELLOW}Server does not negotiate TLS 1.2 — TLS 1.2-class cipher probes are skipped.${NC}"
  echo "Legacy suites exist only in TLS 1.0/1.1 and below; see section [5] for those results."
  echo
else
  echo "Forced TLS 1.2 probes. A cipher is only reported as exposed when a handshake"
  echo "with it actually completed, or explicitly refused by the server."
  echo

  printf "%-26s | %-19s | %-30s | %s\n" "Cipher" "Server" "Probing engine" "Verdict"
  echo "$SEPARATOR"
  # cipher|label|severity
  # Severity is graded by actual cryptographic weakness, not just by the
  # cipher appearing in the §6.1 "unacceptable" column:
  #   broken     — the cipher itself is broken (RC4, 3DES, single DES, NULL,
  #                EXPORT). CRITICAL.
  #   cbc-sha1   — CBC with a SHA-1 MAC. Both the mode and the MAC are
  #                deprecated. CRITICAL.
  #   cbc        — CBC with an HMAC-SHA-256 MAC. Not practically broken, but
  #                the doc recommends AEAD-only, and CBC invites downgrade
  #                attacks. WARNING — it still meets the TLS 1.2 minimum.
  CANDIDATE_CIPHERS="DES-CBC-SHA|single DES (56-bit)|broken
DES-CBC3-SHA|3DES|broken
RC4-SHA|RC4|broken
NULL-SHA|NULL cipher (no encryption)|broken
EXP-RC4-MD5|EXPORT-grade|broken
AES128-SHA|AES-CBC + SHA-1 MAC|cbc-sha1
AES256-SHA|AES-CBC + SHA-1 MAC|cbc-sha1
AES128-SHA256|AES-CBC + SHA-256 MAC|cbc
ECDHE-RSA-AES128-GCM-SHA256|AEAD (reference)|reference"

  while IFS='|' read -r cipher label severity; do
    [ -z "$cipher" ] && continue

    result="UNKNOWN"
    engine_used="-"

    for engine in "${ENGINES[@]}"; do
      flavour="$(openssl_flavour "$engine")"

      # Can this engine even express the cipher? If not, any handshake result
      # would say nothing about the server.
      if ! list_ciphers "$engine" "$flavour" | grep -qx "$cipher"; then
        continue
      fi

      spec="$(cipher_spec "$flavour" "$cipher")"
      out="$(timeout "$TIMEOUT" "$engine" s_client \
          -connect "${URL_HOST}:${PORT}" "${SNI_OPT[@]+"${SNI_OPT[@]}"}" \
          -tls1_2 -cipher "$spec" \
          </dev/null 2>&1)"

      engine_used="$engine ($flavour)"

      # OpenSSL >= 3.0 ships RC4/3DES in the "legacy" provider, which is not
      # loaded by default. If the cipher is simply absent from the list, retry
      # with the legacy provider loaded so the test is meaningful.
      if printf "%s" "$out" | grep -qiE 'no cipher match|error setting cipher list|no suitable cipher'; then
        if [ "$flavour" = "openssl" ]; then
          out="$(OPENSSL_CONF="$LEGACY_CONF" timeout "$TIMEOUT" "$engine" s_client \
              -connect "${URL_HOST}:${PORT}" "${SNI_OPT[@]+"${SNI_OPT[@]}"}" \
              -provider legacy -provider default \
              -tls1_2 -cipher "$spec" \
              </dev/null 2>&1)"
        fi
        if printf "%s" "$out" | grep -qiE 'no cipher match|error setting cipher list|no suitable cipher'; then
          result="CLIENT_UNSUPPORTED"
          continue
        fi
      fi

      negotiated="$(hs_cipher "$out")"
      if [ -n "$negotiated" ]; then
        result="SUPPORTED"
      elif printf "%s" "$out" | grep -qiE 'alert handshake failure|alert protocol version|alert insufficient security|handshake failure'; then
        result="REFUSED"
      elif printf "%s" "$out" | grep -qiE 'connection refused|operation timed out|no route to host|network is unreachable'; then
        result="UNREACHABLE"
      else
        result="UNKNOWN"
      fi
      break
    done

    if [ "$result" = "UNKNOWN" ] && [ "$engine_used" = "-" ]; then
      result="CLIENT_UNSUPPORTED"
      engine_used="(none can express it)"
    fi

    verdict=""
    case "$result" in
      SUPPORTED)
        case "$severity" in
          reference)
            verdict="${GREEN}PASS${NC} — AEAD suite offered (expected)"
            ;;
          broken)
            verdict="${RED}CRITICAL${NC} — broken cipher accepted by the server"
            add_finding "CRITICAL" "Cipher" "Server accepts ${cipher} (${label})"
            ;;
          cbc-sha1)
            verdict="${RED}CRITICAL${NC} — CBC with a SHA-1 MAC accepted by the server"
            add_finding "CRITICAL" "Cipher" "Server accepts ${cipher} (${label})"
            ;;
          cbc)
            verdict="${YELLOW}WARNING${NC} — CBC accepted; baseline recommends AEAD-only"
            add_finding "WARNING" "Cipher" "Server accepts ${cipher} (${label}); §6.1 recommends AEAD-only"
            ;;
          *)
            verdict="${YELLOW}WARNING${NC} — accepted by the server"
            add_finding "WARNING" "Cipher" "Server accepts ${cipher} (${label})"
            ;;
        esac
        ;;
      REFUSED)
        verdict="${GREEN}PASS${NC} — server refused"
        ;;
      CLIENT_UNSUPPORTED)
        verdict="${YELLOW}UNKNOWN${NC} — no local engine can offer this cipher"
        ;;
      UNREACHABLE)
        verdict="${YELLOW}UNKNOWN${NC} — host unreachable from here"
        ;;
      *)
        verdict="${YELLOW}UNKNOWN${NC} — probe inconclusive"
        ;;
    esac

    printf "%-26s | %-19s | %-30s | %b\n" "$cipher" "$result" "$engine_used" "$verdict"
  done <<< "$CANDIDATE_CIPHERS"

  echo "$SEPARATOR"

  # --- DH key-exchange parameter strength ---
  # The default handshake may negotiate ECDHE, which has no finite-field DH
  # group to judge. Force a DHE handshake to measure the server's actual DH
  # group size and compare it against the 2048-bit baseline.
  echo
  echo "DH key-exchange group size (forced DHE probe):"
  dh_probe_out=""
  for engine in "${ENGINES[@]}"; do
    flavour="$(openssl_flavour "$engine")"
    spec="$(cipher_spec "$flavour" 'DHE-RSA-AES256-GCM-SHA384')"
    dh_probe_out="$(OPENSSL_CONF="$LEGACY_CONF" timeout "$TIMEOUT" "$engine" s_client \
        -connect "${URL_HOST}:${PORT}" "${SNI_OPT[@]+"${SNI_OPT[@]}"}" \
        -tls1_2 -cipher "$spec" \
        </dev/null 2>&1)"
    if [ -n "$(hs_cipher "$dh_probe_out")" ]; then
      break
    fi
    dh_probe_out=""
  done

  if [ -n "$dh_probe_out" ]; then
    dh_group="$(dh_group_bits "$dh_probe_out")"
    if [ -n "$dh_group" ]; then
      if [ "$dh_group" -lt 2048 ]; then
        echo -e "  ${RED}CRITICAL${NC} — server offers a ${dh_group}-bit DH group; the baseline requires 2048"
        add_finding "CRITICAL" "DH params" "Server offers a ${dh_group}-bit DH group; the baseline requires 2048"
      else
        echo -e "  ${GREEN}PASS${NC} — server offers a ${dh_group}-bit DH group"
      fi
    else
      echo -e "  ${YELLOW}UNKNOWN${NC} — DHE handshake succeeded but the group size could not be read"
    fi
  else
    echo -e "  ${GREEN}PASS${NC} — no finite-field DHE key exchange offered"
  fi

  # --- TLS 1.3 ciphersuites ---
  # TLS 1.3 suites are selected via -ciphersuites, not -cipher. All of them are
  # AEAD, so this section is informational rather than a weakness hunt.
  echo
  echo "TLS 1.3 ciphersuites (probed via -ciphersuites):"
  for suite in TLS_AES_256_GCM_SHA384 TLS_AES_128_GCM_SHA256 TLS_CHACHA20_POLY1305_SHA256; do
    suite_result="UNKNOWN"
    for engine in "${ENGINES[@]}"; do
      flavour="$(openssl_flavour "$engine")"
      [ "$flavour" = "openssl" ] || continue
      out="$(timeout "$TIMEOUT" "$engine" s_client \
          -connect "${URL_HOST}:${PORT}" "${SNI_OPT[@]+"${SNI_OPT[@]}"}" \
          -tls1_3 -ciphersuites "$suite" \
          </dev/null 2>&1)"
      negotiated="$(hs_cipher "$out")"
      if [ -n "$negotiated" ]; then
        suite_result="SUPPORTED"
      elif printf "%s" "$out" | grep -qiE 'alert|no cipher|no suites'; then
        suite_result="REFUSED"
      fi
      break
    done
    case "$suite_result" in
      SUPPORTED) echo -e "  ${GREEN}${suite_result}${NC}  — all TLS 1.3 suites are AEAD; none are weak" ;;
      REFUSED)   echo -e "  ${GREEN}${suite_result}${NC}  — server refused this suite" ;;
      *)         echo -e "  ${YELLOW}${suite_result}${NC}  — inconclusive" ;;
    esac
  done
fi

# ============================================================
# [7] Hostname, expiry and chain verification
# ============================================================

print_section "[7] Verification — hostname, expiry and chain"

LEAF_CERT="${CERT_PREFIX}_01.pem"

if [ -f "$LEAF_CERT" ]; then
  if openssl x509 -in "$LEAF_CERT" -noout -checkhost "$URL_HOST" >/dev/null 2>&1; then
    print_kv "Hostname match:" "${GREEN}PASS${NC}"
  else
    print_kv "Hostname match:" "${RED}FAIL${NC}"
    add_finding "CRITICAL" "Hostname" "Leaf certificate does not match ${URL_HOST}"
  fi

  if openssl x509 -in "$LEAF_CERT" -noout -checkend 0 >/dev/null 2>&1; then
    print_kv "Not expired:" "${GREEN}PASS${NC}"
  else
    print_kv "Not expired:" "${RED}FAIL — certificate has expired${NC}"
    add_finding "CRITICAL" "Expiry" "Leaf certificate has expired"
  fi

  for window in 2592000 604800 86400; do
    case "$window" in
      2592000) label="Expires within 30 days" ;;
      604800)  label="Expires within 7 days" ;;
      86400)   label="Expires within 24 hours" ;;
    esac
    if openssl x509 -in "$LEAF_CERT" -noout -checkend "$window" >/dev/null 2>&1; then
      print_kv "$label:" "${GREEN}PASS${NC}"
    else
      print_kv "$label:" "${YELLOW}WARN${NC}"
      add_finding "WARNING" "Expiry" "Leaf certificate $label"
    fi
  done
fi

# Build the untrusted chain from every cert except the leaf, in order.
UNTRUSTED_CHAIN="$TMP_DIR/untrusted_chain.pem"
: >"$UNTRUSTED_CHAIN"
for f in "$CERT_PREFIX"_*.pem; do
  [ -f "$f" ] || continue
  base=$(basename "$f" .pem)
  idx=${base##*_}
  if [ "$idx" != "01" ]; then
    cat "$f" >>"$UNTRUSTED_CHAIN"
  fi
done

VERIFY_OUTPUT="$TMP_DIR/verify.txt"
if [ -s "$UNTRUSTED_CHAIN" ]; then
  openssl verify "${CA_OPT[@]+"${CA_OPT[@]}"}" -untrusted "$UNTRUSTED_CHAIN" "$LEAF_CERT" >"$VERIFY_OUTPUT" 2>&1
  VERIFY_RC=$?
else
  openssl verify "${CA_OPT[@]+"${CA_OPT[@]}"}" "$LEAF_CERT" >"$VERIFY_OUTPUT" 2>&1
  VERIFY_RC=$?
fi

echo
echo "Chain verification output:"
sed 's/^/  /' "$VERIFY_OUTPUT"

if [ "$VERIFY_RC" -eq 0 ]; then
  print_kv "Chain verification:" "${GREEN}PASS${NC}"
else
  print_kv "Chain verification:" "${YELLOW}WARN — chain did not verify against the selected CA store${NC}"
  add_finding "WARNING" "Chain" "Presented chain did not verify against ${CA_DESC}"
fi

# ============================================================
# [8] Verdict
# ============================================================

print_section "[8] Verdict — CWE-326 findings"

if [ "${#FINDINGS[@]}" -eq 0 ]; then
  echo -e "${GREEN}No CWE-326 (Inadequate Encryption Strength) findings.${NC}"
  echo "Key lengths, signature hashes, protocol floor and cipher exposure all met the baseline."
else
  printf "%-10s | %-14s | %s\n" "Severity" "Area" "Detail"
  echo "$SEPARATOR"
  for finding in "${FINDINGS[@]+"${FINDINGS[@]}"}"; do
    sev="${finding%%|*}"
    rest="${finding#*|}"
    area="${rest%%|*}"
    detail="${rest#*|}"
    printf "%-10s | %-14s | %s\n" "$(sev_color "$sev")${sev}${NC}" "$area" "$detail"
  done
  echo "$SEPARATOR"
  echo
  echo "CRITICAL findings: $CRIT_COUNT   WARNING findings: $WARN_COUNT"
  echo
  if [ "$CRIT_COUNT" -gt 0 ]; then
    echo -e "${RED}${BOLD}Verdict: NOT compliant with the CWE-326 baseline.${NC}"
    echo "Remediation — see safe/cwe/cwe-326.md §6.1 (baseline) and §6.2 (fix list):"
    echo "  - Re-issue certificates with RSA >= 2048 (3072 recommended) or EC P-256+."
    echo "  - Re-sign with SHA-256 or stronger; SHA-1/MD5 certificates must be replaced."
    echo "  - Remove legacy protocol versions (TLS 1.0/1.1) and weak suites (3DES/RC4/CBC)."
    echo "  - On GCP: tighten the SSL policy and the LB frontend, then re-run this check."
  else
    echo -e "${YELLOW}${BOLD}Verdict: compliant, with advisory findings.${NC}"
    echo "No critical strength gaps were found; review the warnings above."
  fi
fi

# ============================================================
# [9] Diagnosis guide
# ============================================================

print_section "[9] Diagnosis guide"
echo "- CLIENT_UNSUPPORTED in sections [5]/[6] means your local OpenSSL cannot express the"
echo "  algorithm at all (OpenSSL >= 3.5 dropped TLS 1.0/1.1 and RC4/3DES). It is NOT evidence"
echo "  that the server is safe — it means the question was never asked. Close those gaps with"
echo "  testssl.sh / sslyze, or by running this script on a host with LibreSSL or OpenSSL 1.1.1."
echo "- CRITICAL on a cipher means the server completed a handshake using a weak suite."
echo "- CRITICAL on 'Public key' means the certificate key is below the NIST SP 800-57 floor."
echo "- CRITICAL on 'Signature' means the certificate is signed with MD5 or SHA-1."
echo "- 'Chain verification' WARN with a passing handshake usually means an internal/private CA."
echo "- A single-certificate chain (Certificates returned: 1) breaks clients that do not fetch"
echo "  intermediates themselves — check the fullchain file on the LB / ingress / nginx."
echo "- If the path in the URL matters (different certs per path), probe each path separately."
echo "- 'intermediate (cross-signed)' in section [4] is normal for a CDN chain — the last"
echo "  certificate presented is not always the trust anchor."

echo
echo "$HEAVY"
echo "Report completed at $(date '+%Y-%m-%d %H:%M:%S')"
echo "$HEAVY"

if [ "$CRIT_COUNT" -gt 0 ]; then
  exit 2
fi
exit 0
