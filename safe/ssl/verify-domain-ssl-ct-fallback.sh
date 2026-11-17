#!/usr/bin/env bash

# verify-domain-ssl-ct-fallback.sh
#
# Look up public Certificate Transparency (CT) issuance history for a DNS name,
# without requiring its DNS record or TLS endpoint to exist.
#
# Data source: Cert Spotter (api.certspotter.com, operated by SSLMate).
# CT shows publicly issued certificates, not the certificate currently configured
# on a server. A currently-valid CT record is therefore not proof of deployment.
#
# Usage:
#   ./verify-domain-ssl-ct-fallback.sh <fqdn>             # show all matching issuances
#   ./verify-domain-ssl-ct-fallback.sh <fqdn> --active    # currently valid, non-revoked
#   ./verify-domain-ssl-ct-fallback.sh <fqdn> --expired   # expired or revoked
#
# Reference: USER.md §Ephemeral GCP / infra-gcp MEMORY §Cert + key 操作的方法论.
# This script answers "未部署域名也能看证书" by querying CT, not by TCP/TLS.

set -euo pipefail

DOMAIN="${1:-}"
MODE="${2:-all}"

if [ -z "$DOMAIN" ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <fqdn> [--active|--expired]"
  echo "  all      -- every issuance found (default)"
  echo "  active   -- currently valid (not_before <= now <= not_after) AND not revoked"
  echo "  expired  -- not_after < now (or revoked)"
  exit 1
fi

case "$MODE" in
  all|--all) MODE="all" ;;
  active|--active) MODE="active" ;;
  expired|--expired) MODE="expired" ;;
  *)
    echo "ERROR: unknown mode '${MODE}'. Use --active or --expired."
    exit 1
    ;;
esac

# CT APIs take a DNS name, not a URL or host:port. Normalising a trailing dot
# avoids a false negative when users pass the fully-qualified DNS representation.
DOMAIN="${DOMAIN%.}"
DOMAIN="${DOMAIN,,}"
if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required but not found in PATH."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required (used for JSON parsing + date math)."
  exit 1
fi

if ! python3 - "$DOMAIN" <<'PYEOF'
import re
import sys

name = sys.argv[1]
valid = (
    len(name) <= 253
    and bool(re.fullmatch(r"(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}", name))
)
sys.exit(0 if valid else 1)
PYEOF
then
  echo "ERROR: '${DOMAIN}' is not an ASCII FQDN. Pass a DNS name only (use punycode for IDNs)."
  exit 1
fi

# ------------------------------------------------------------------------------
# Fetch + parse Cert Spotter response. We request SAN and issuer expansions so
# the local filter can prove the requested FQDN is actually covered.
# ------------------------------------------------------------------------------

API_BASE="https://api.certspotter.com/v1/issuances"
RAW_DIR=$(mktemp -d "/tmp/ct_fallback_${DOMAIN//[^A-Za-z0-9._-]/_}_XXXXXX")
trap 'rm -rf "$RAW_DIR"' EXIT

echo "=================================================="
echo "CT fallback probe for: ${DOMAIN}"
echo "Source: api.certspotter.com (Cert Spotter / SSLMate)"
echo "Mode:   ${MODE}"
echo "=================================================="

FETCHED="$RAW_DIR/all_records.json"
> "$FETCHED"

cursor=""
MAX_PAGES=10   # Safety cap; prevents an unexpectedly broad query from running indefinitely.
page=0
fetch_ok=1

while [ "$page" -lt "$MAX_PAGES" ]; do
  page=$((page + 1))
  body="$RAW_DIR/page_${page}.json"
  curl_args=(
    --silent --show-error --location --max-time 30
    --retry 2 --retry-delay 1
    --get --data-urlencode "domain=${DOMAIN}"
    --data-urlencode "expand=dns_names"
    --data-urlencode "expand=issuer"
    --output "$body" --write-out '%{http_code}' "$API_BASE"
  )
  if [ -n "$cursor" ]; then
    curl_args+=(--data-urlencode "after=${cursor}")
  fi
  http_code=$(curl "${curl_args[@]}" 2>/dev/null) || fetch_ok=0

  if [ "$fetch_ok" = "0" ]; then
    echo
    echo "ERROR: curl could not reach api.certspotter.com."
    echo "Hint:  this network path may be blocked. crt.sh (Cloudflare-backed) is"
    echo "       usually a fallback, but if both fail, no public CT data is reachable."
    exit 2
  fi

  if [ "$http_code" != "200" ]; then
    echo
    echo "ERROR: certspotter returned HTTP ${http_code} on page ${page}."
    echo "Body:"
    head -c 500 "$body"
    echo
    exit 2
  fi

  # Validate it is actually JSON (certspotter sometimes returns HTML error pages on rate limit).
  if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$body" 2>/dev/null; then
    echo
    echo "ERROR: certspotter returned a non-JSON body on page ${page}."
    echo "Body:"
    head -c 500 "$body"
    echo
    exit 2
  fi

  # Cert Spotter signals "no more" by returning an empty array.
  count=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$body")
  if [ "$count" = "0" ]; then
    break
  fi

  # Append this page's records (strip surrounding array brackets).
  python3 -c '
import json, sys
src = sys.argv[1]
dst = sys.argv[2]
data = json.load(open(src))
with open(dst, "a") as f:
    for rec in data:
        f.write(json.dumps(rec) + "\n")
' "$body" "$FETCHED"

  # Use the last record's id as the cursor for the next page.
  cursor=$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(data[-1]["id"])' "$body")

  # If we got less than 100, that's the last page.
  if [ "$count" -lt "100" ]; then
    break
  fi
done

if [ "$page" -eq "$MAX_PAGES" ] && [ "$count" -eq 100 ]; then
  echo "WARNING: stopped at MAX_PAGES=${MAX_PAGES}; output may be incomplete." >&2
fi

TOTAL=$(wc -l < "$FETCHED" | tr -d ' ')
echo
echo "Total issuances pulled: ${TOTAL}"
echo

if [ "$TOTAL" = "0" ]; then
  echo "No CT records found for '${DOMAIN}'."
  echo "This means either:"
  echo "  - the domain never had a public-CA certificate (private CA / self-signed only)"
  echo "  - the certificate was issued very recently and has not been logged yet"
  echo "  - the domain spelling differs from what is in the certificate's SAN"
  echo
  echo "No public-CA issuance currently visible in this CT source."
  exit 0
fi

# ------------------------------------------------------------------------------
# Python pipeline: dedup, parse dates, classify by mode, pretty-print.
# Pure python3 (no extra deps) so the script stays portable like its sibling.
# ------------------------------------------------------------------------------

python3 - "$FETCHED" "$DOMAIN" "$MODE" <<'PYEOF'
import json
import datetime as dt
import sys
from collections import OrderedDict

path, domain, mode = sys.argv[1], sys.argv[2], sys.argv[3]

raw = []
with open(path) as f:
    for line in f:
        line = line.strip()
        if line:
            raw.append(json.loads(line))

# Dedup by cert_sha256 (certspotter logs precert + final cert as two entries).
seen = OrderedDict()
for rec in raw:
    seen.setdefault(rec.get("cert_sha256", ""), rec)
records = list(seen.values())

def covers_requested_name(dns_name, requested):
    """RFC 6125-style DNS wildcard match: one left-most label only."""
    dns_name = (dns_name or "").lower().rstrip(".")
    requested = requested.lower().rstrip(".")
    if dns_name == requested:
        return True
    if not dns_name.startswith("*."):
        return False
    suffix = dns_name[2:]
    return requested.endswith("." + suffix) and requested.count(".") == suffix.count(".") + 1

def parse_iso(s):
    if not s:
        return None
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return dt.datetime.fromisoformat(s)

now = dt.datetime.now(dt.timezone.utc)
classified = []
for r in records:
    dns_names = r.get("dns_names") or []
    matching_names = [n for n in dns_names if covers_requested_name(n, domain)]
    # Do not trust a broad API search alone: certificate records that merely
    # mention a parent/child name must not be reported as covering this FQDN.
    if not matching_names:
        continue
    nb = parse_iso(r.get("not_before"))
    na = parse_iso(r.get("not_after"))
    revoked = bool(r.get("revoked"))
    is_active = (nb is not None and na is not None
                 and nb <= now <= na
                 and not revoked)
    is_expired = (na is not None and na < now) or revoked
    classified.append({
        "id":            r.get("id", ""),
        "cert_sha256":   r.get("cert_sha256", ""),
        "matching_names": matching_names,
        "issuer":        (r.get("issuer") or {}).get("friendly_name", "?"),
        "not_before":    nb,
        "not_after":     na,
        "revoked":       revoked,
        "is_active":     is_active,
        "is_expired":    is_expired,
    })

if mode == "active":
    shown = [c for c in classified if c["is_active"]]
    header = "Currently active (not expired, not revoked)"
elif mode == "expired":
    shown = [c for c in classified if c["is_expired"]]
    header = "Expired or revoked"
else:
    shown = classified
    header = "All issuances"

print("==================================================")
print(header)
print("==================================================")

if not shown:
    print("(none match this filter)")
    sys.exit(0)

# Sort: active first by not_after ascending (soonest-to-expire wins).
#        expired: most recently expired first.
#        all:     newest not_before first.
if mode == "active":
    shown.sort(key=lambda c: (c["not_after"] or dt.datetime.min.replace(tzinfo=dt.timezone.utc)))
elif mode == "expired":
    shown.sort(key=lambda c: -(c["not_after"].timestamp() if c["not_after"] else 0))
else:
    shown.sort(key=lambda c: -(c["not_before"].timestamp() if c["not_before"] else 0))

for i, c in enumerate(shown, 1):
    nb = c["not_before"].strftime("%Y-%m-%d %H:%M:%S UTC") if c["not_before"] else "?"
    na = c["not_after"].strftime("%Y-%m-%d %H:%M:%S UTC") if c["not_after"] else "?"
    sha = c["cert_sha256"]
    sha_short = sha[:16] + "..." + sha[-8:] if len(sha) >= 32 else sha

    days_left = ""
    if c["not_after"]:
        delta = c["not_after"] - now
        days_left = f"  (expires in {delta.days}d)" if delta.total_seconds() > 0 \
                   else f"  (expired {-delta.days}d ago)"
    revoked_tag = "  [REVOKED]" if c["revoked"] else ""

    print()
    print(f"--- #{i}  certspotter id {c['id']}{revoked_tag} ---")
    print(f"  not_before:    {nb}")
    print(f"  not_after:     {na}{days_left}")
    print(f"  matching SAN:  {', '.join(c['matching_names'])}")
    print(f"  issuer:        {c['issuer']}")
    print(f"  cert_sha256:   {sha_short}")

print()
print("==================================================")
print("Notes")
print("==================================================")
print("- CT data answers 'was a public certificate issued and when does it expire?'")
print("  It does NOT identify the certificate currently served by any endpoint.")
print("- For the deployed certificate, run verify-domain-ssl-enhance.sh once a live")
print("  TLS endpoint is reachable.")
print("- If you only see precerts (not_before == not_after ~ a few minutes apart),")
print("  those are SCT-only pre-issuance entries; the final cert is also listed.")
print("- Results are limited by this source and the script's page cap; absence from")
print("  output is not proof that no certificate was ever issued.")
PYEOF
