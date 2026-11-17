#!/usr/bin/env bash
# =============================================================================
# fetch-gcp-pricing.sh — Pull current GCP SKU pricing from Cloud Billing Catalog
# Companion to: gcp/cost/cross-project-public-tls-mtls-billing.md §8
# =============================================================================
# Why this exists:
#   GCP pricing changes frequently. All `[std]` numbers in the cost doc are
#   baseline figures; the ONLY authoritative real-time source is the Cloud
#   Billing Catalog API. This script pulls relevant SKUs in one shot and
#   filters to LB / PSC / Logging / Armor / egress.
#
# Output:
#   /tmp/gcp-services.json         — all GCP services list (filtered)
#   /tmp/gcp-network-skus.json     — relevant SKUs with rate+unit
#   stdout human-readable summary  — forwarding rules / LB / PSC / egress
#
# Requirements:
#   - gcloud CLI authenticated (gcloud auth login or ADC)
#   - jq installed
#   - cloudbilling API enabled (script auto-enables)
#
# Usage:
#   ./fetch-gcp-pricing.sh                       # default — all relevant SKUs
#   ./fetch-gcp-pricing.sh --region=europe-west2 # filter by region
#   ./fetch-gcp-pricing.sh --json-only          # just dump JSON, no pretty print
# =============================================================================

set -euo pipefail

REGION_FILTER=".*"
JSON_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --region=*) REGION_FILTER="${arg#*=}" ;;
    --json-only) JSON_ONLY=true ;;
    --help|-h)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "[err] unknown flag: $arg" >&2; exit 1 ;;
  esac
done

TOKEN=$(gcloud auth print-access-token 2>/dev/null || true)

if [[ -z "${TOKEN:-}" || "$TOKEN" == "None" ]]; then
  echo "[err] gcloud auth not initialized. Run: gcloud auth login" >&2
  exit 1
fi

echo "[step] enabling cloudbilling API..."
gcloud services enable cloudbilling.googleapis.com --quiet 2>/dev/null || true

# Step 1: list services, filter to networking / compute / logging / security
echo "[step] fetching GCP services list..."
curl -sL \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://cloudbilling.googleapis.com/v1/services?pageSize=200" \
  > /tmp/gcp-services-raw.json

# Use jq file-based filtering to avoid quoting hell
cat > /tmp/_filter_services.jq <<'EOF'
[.services[] | select(
    (.displayName | test("Compute Engine|Networking|Cloud Logging|Cloud Armor|Cloud DNS"; "i"))
  ) | {id: .serviceId, name: .displayName}]
EOF
jq -f /tmp/_filter_services.jq /tmp/gcp-services-raw.json > /tmp/gcp-services.json

if $JSON_ONLY; then
  cat /tmp/gcp-services.json
  exit 0
fi

echo "[ok] services:"
jq -r '.[] | "  " + .name + " → " + .id' /tmp/gcp-services.json

# Step 2: pull SKUs for each service (paginated)
ALL_SKUS=/tmp/gcp-all-skus.json
echo "[]" > "$ALL_SKUS"

SVC_IDS=$(jq -r '.[].id' /tmp/gcp-services.json)
for SVC_ID in $SVC_IDS; do
  echo "[step] pulling SKUs for service $SVC_ID..."
  NEXT=""
  while true; do
    URL="https://cloudbilling.googleapis.com/v1/services/${SVC_ID}/skus?pageSize=5000"
    if [[ -n "$NEXT" ]]; then
      URL="${URL}&pageToken=${NEXT}"
    fi
    curl -sL \
      -H "Authorization: Bearer ${TOKEN}" \
      "$URL" > /tmp/_sku_page.json

    # Append .skus to $ALL_SKUS
    jq -s '.[0] + (.[1].skus // [])' "$ALL_SKUS" /tmp/_sku_page.json > /tmp/_sku_new.json
    mv /tmp/_sku_new.json "$ALL_SKUS"

    NEXT=$(jq -r '.nextPageToken // ""' /tmp/_sku_page.json)
    [[ -z "$NEXT" ]] && break
  done
done

TOTAL_SKUS=$(jq 'length' "$ALL_SKUS")
echo "[ok] total SKUs pulled: ${TOTAL_SKUS}"

# Step 3: filter to relevant SKUs (forwarding rules / LB / proxy / egress / PSC / armor / logging)
echo "[step] filtering to relevant SKUs..."

cat > /tmp/_filter_skus.jq <<'EOF'
[.[] | select(
    (.description | test("Forwarding Rule|Load Balancing|Envoy|Proxy|Egress|Service Connect|Armor|Internet"; "i"))
    and (.category.resourceFamily == "Compute" or .category.resourceFamily == "Network")
  ) | {
    sku: .skuId,
    desc: .description,
    service_regions: .serviceRegions,
    unit: .pricingInfo[0].pricingExpression.usageUnit,
    rate_units: (.pricingInfo[0].pricingExpression.tieredRates[0].unitPrice.units // 0),
    rate_nanos: (.pricingInfo[0].pricingExpression.tieredRates[0].unitPrice.nanos // 0),
    rate_usd: ((.pricingInfo[0].pricingExpression.tieredRates[0].unitPrice.units // 0) +
               ((.pricingInfo[0].pricingExpression.tieredRates[0].unitPrice.nanos // 0) / 1000000000))
  }]
EOF
jq -f /tmp/_filter_skus.jq "$ALL_SKUS" > /tmp/gcp-network-skus.json

FILTERED=$(jq 'length' /tmp/gcp-network-skus.json)
echo "[ok] filtered SKUs: ${FILTERED}"

# Step 4: pretty-print summary by category — use jq files to avoid quoting
section() {
  local title="$1"
  local filter_jq="$2"
  printf '%s\n' ""
  printf '================================================================\n'
  printf '  %s\n' "$title"
  printf '================================================================\n'
  jq -r "$filter_jq" /tmp/gcp-network-skus.json | sort -u | head -25
}

section "Forwarding Rules (per hour)" \
  '.[] | select(.desc | test("Forwarding Rule"; "i")) | "  $" + (.rate_usd|tostring) + " / " + .unit + "  -- " + .desc'

section "Load Balancing -- Data Processing (per GB)" \
  '.[] | select(.desc | test("Load Balancing"; "i") and (.unit | test("BYT|GB"; "i"))) | "  $" + (.rate_usd|tostring) + " / " + .unit + "  -- " + .desc'

section "Proxy / Envoy instances" \
  '.[] | select(.desc | test("Envoy|Proxy|Hour"; "i")) | "  $" + (.rate_usd|tostring) + " / " + .unit + "  -- " + .desc'

section "Internet / Premium Egress" \
  '.[] | select(.desc | test("Egress|Internet"; "i")) | "  $" + (.rate_usd|tostring) + " / " + .unit + "  -- " + .desc + " [" + (if (.service_regions | length) > 0 then .service_regions[0] else "global" end) + "]"'

section "Private Service Connect" \
  '.[] | select(.desc | test("Service Connect|PSC"; "i")) | "  $" + (.rate_usd|tostring) + " / " + .unit + "  -- " + .desc'

section "Cloud Armor" \
  '.[] | select(.desc | test("Armor"; "i")) | "  $" + (.rate_usd|tostring) + " / " + .unit + "  -- " + .desc'

printf '%s\n' ""
printf '================================================================\n'
printf 'DONE. Full data: /tmp/gcp-network-skus.json\n'
printf 'Use this file to update $/hour / $/GB in your cost model.\n'
printf '================================================================\n'

rm -f /tmp/_filter_services.jq /tmp/_filter_skus.jq /tmp/_sku_page.json