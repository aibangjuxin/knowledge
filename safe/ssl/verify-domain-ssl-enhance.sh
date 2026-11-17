#!/opt/homebrew/bin/bash

set -u

DOMAIN="${1:-}"
PORT="${2:-443}"
CA_FILE="${3:-}"

if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <domain-fqdn> [port] [ca-file-path]"
  echo "Example (system CA): $0 my-domain-fqdn.com 443 /etc/ssl/certs/ca-certificates.crt"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required but not found in PATH."
  exit 1
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
    echo "ERROR: CA file does not exist or is not readable: $CA_FILE"
    exit 1
  fi
  CA_OPT=(-CAfile "$CA_FILE")
  CA_DESC="$CA_FILE"
fi

print_section() {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

print_kv() {
  printf "%-24s %s\n" "$1" "$2"
}

echo "=================================================="
echo "SSL probe for ${DOMAIN}:${PORT}"
print_kv "CA source:" "$CA_DESC"
echo "=================================================="

print_section "[1] Fetching TLS handshake and certificate chain"
if ! openssl s_client \
  -connect "${DOMAIN}:${PORT}" \
  -servername "$DOMAIN" \
  -showcerts \
  -verify_return_error \
  "${CA_OPT[@]}" \
  </dev/null >"$RAW_OUTPUT" 2>&1; then
  echo "TLS handshake returned a non-zero exit code."
  echo "Continuing with abjtured output for diagnostics."
fi

if ! awk '
    /-----BEGIN CERTIFICATE-----/, /-----END CERTIFICATE-----/ { print }
' "$RAW_OUTPUT" >"$CHAIN_PEM"; then
  echo "ERROR: Failed to extract certificate chain from openssl output."
  exit 1
fi

CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "$CHAIN_PEM" || true)
print_kv "Certificates returned:" "$CERT_COUNT"

if [ "$CERT_COUNT" -eq 0 ]; then
  echo "ERROR: No certificate was returned by the remote endpoint."
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

print_section "[2] Connection summary"
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

print_section "[3] Per-certificate details"
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

print_section "[4] Hostname verification"
if openssl x509 -in "${CERT_PREFIX}_01.pem" -noout -checkhost "$DOMAIN" >/dev/null 2>&1; then
  print_kv "Leaf cert host match:" "PASS"
else
  print_kv "Leaf cert host match:" "FAIL"
fi

print_section "[5] Chain verification"
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

print_section "[6] Diagnosis guide"
echo "- CERT_COUNT = 0: check DNS, network path, load balancer listener, firewall, SNI, or TLS termination point."
echo "- CERT_COUNT = 1: server likely returns only the leaf certificate; check fullchain configuration on LB / ingress / nginx / kong."
echo "- Verify return code 20: chain was presented but local CA store cannot anchor it to a trusted issuer."
echo "- Verify return code 21: server likely omitted an intermediate certificate, or the presented chain is incomplete."
echo "- Hostname verification FAIL: certificate SAN/CN does not match the requested domain."
echo "- If custom CA passes but system CA fails: the endpoint is probably signed by an internal CA not present in the current trust store."

print_section "[7] Temporary artifacts"
echo "Raw openssl output was abjtured at: $RAW_OUTPUT"
echo "Per-certificate PEM files were created under: $TMP_DIR"
echo "Artifacts will be removed automatically when the script exits."
