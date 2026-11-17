#!/usr/bin/env bash
# get-forwarding-rule.sh (v2 — bash + jq only)
# Usage: get-forwarding-rule.sh -k <keyword> [-r <region>] [-g] [-p <project>]

set -euo pipefail

# ─── Color definitions ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── Help message ─────────────────────────────────────────────────────────────────
usage() {
cat <<EOF
Usage: $(basename "$0") -k <keyword> [-r <region>] [-g] [-p <project>]

Options:
-k keyword Forwarding Rule filter keyword (required)
-r region GCP region (default: gcloud config)
-g Use Global Forwarding Rule (mutually exclusive with -r)
-p project GCP project (default: gcloud config)
-h Show help

Example:
$(basename "$0") -k my-api -r asia-east1
$(basename "$0") -k my-api -g
EOF
exit 0
}

# ─── Argument parsing ─────────────────────────────────────────────────────────────────
KEYWORD=""; REGION=""; PROJECT=""; GLOBAL=false

while getopts "k:r:gp:h" opt; do
case $opt in
k) KEYWORD="$OPTARG" ;;
r) REGION="$OPTARG" ;;
g) GLOBAL=true ;;
p) PROJECT="$OPTARG" ;;
h) usage ;;
*) usage ;;
esac
done

[[ -z "$KEYWORD" ]] && { echo -e "${RED}[ERROR] -k keyword is required${RESET}"; usage; }

PROJECT="${PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
[[ -z "$PROJECT" ]] && { echo -e "${RED}[ERROR] Cannot determine project, use -p to specify${RESET}"; exit 1; }

if [[ "$GLOBAL" == false ]]; then
REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null)}"
[[ -z "$REGION" ]] && { echo -e "${RED}[ERROR] Cannot determine region, use -r to specify, or use -g for Global${RESET}"; exit 1; }
fi

# ─── Dependency check ─────────────────────────────────────────────────────────────────
command -v jq &>/dev/null || { echo -e "${RED}[ERROR] Missing dependency: jq${RESET}"; exit 1; }
command -v gcloud &>/dev/null || { echo -e "${RED}[ERROR] Missing dependency: gcloud${RESET}"; exit 1; }

# ─── Days until expiry calculation (compatible with macOS/Linux) ──────────────────────────
days_until_expiry() {
local expire_str="$1"
# Strip milliseconds for consistency, macOS date compatible
local clean="${expire_str%%.*}"
clean="${clean%Z}Z"
# macOS: date -j -f, Linux: date -d
local expire_epoch
if date --version &>/dev/null 2>&1; then
# GNU date (Linux)
expire_epoch=$(date -d "${clean}" +%s 2>/dev/null || date -d "${expire_str}" +%s 2>/dev/null || echo 0)
else
# BSD date (macOS)
expire_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${clean}" +%s 2>/dev/null || echo 0)
fi
local now_epoch; now_epoch=$(date +%s)
echo $(( (expire_epoch - now_epoch) / 86400 ))
}

# ─── Expiry warning label ─────────────────────────────────────────────────────────────
expiry_label() {
local days="$1"
if [[ "$days" -lt 0 ]]; then echo " EXPIRED!"
elif [[ "$days" -lt 30 ]]; then echo " EXPIRING SOON!"
elif [[ "$days" -lt 90 ]]; then echo " EXPIRES WITHIN 90 DAYS"
else echo ""
fi
}

# ─── Print separator row ───────────────────────────────────────────────────────────────
row() { printf " ${CYAN}%-22s${RESET} %s\n" "$1" "$2"; }

echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD} GCP Forwarding Rule -> SSL Certificate Inspector (v2)${RESET}"
echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════${RESET}"
row "Project" "$PROJECT"
[[ "$GLOBAL" == true ]] && row "Scope" "Global" || row "Region" "$REGION"
row "Keyword" "$KEYWORD"
echo ""

# ─── STEP 1: Get Forwarding Rules ───────────────────────────────────────────────────
echo -e "${BOLD}[STEP 1] Searching Forwarding Rules (keyword: ${KEYWORD})${RESET}"

if [[ "$GLOBAL" == true ]]; then
FR_JSON=$(gcloud compute forwarding-rules list \
--project="${PROJECT}" \
--global \
--format="json" \
--filter="name~${KEYWORD}" 2>/dev/null || echo '[]')
else
FR_JSON=$(gcloud compute forwarding-rules list \
--project="${PROJECT}" \
--regions="${REGION}" \
--format="json" \
--filter="name~${KEYWORD}" 2>/dev/null || echo '[]')
fi

FR_COUNT=$(echo "$FR_JSON" | jq 'length')

if [[ "$FR_COUNT" -eq 0 ]]; then
echo -e "${YELLOW}[WARN] No Forwarding Rule matching '${KEYWORD}' found${RESET}"
exit 0
fi
echo -e "${GREEN} Found ${FR_COUNT} Forwarding Rule(s)${RESET}\n"

# ─── STEP 2: Filter targetHttpsProxies, build name|proxy list ─────────────────────────
echo -e "${BOLD}[STEP 2] Filtering targetHttpsProxies${RESET}\n"

FR_LIST=$(echo "$FR_JSON" | jq -r '
.[] |
select(.target // "" | contains("targetHttpsProxies")) |
.name + "|" + (.target | split("/") | last)
')

if [[ -z "$FR_LIST" ]]; then
echo -e "${YELLOW}[WARN] No Forwarding Rule associated with targetHttpsProxies found${RESET}"
exit 0
fi

# ─── Main loop ─────────────────────────────────────────────────────────────────────
while IFS='|' read -r FR_NAME PROXY_NAME; do
echo -e "${BOLD}${BLUE}┌─────────────────────────────────────────────────────┐${RESET}"
echo -e "${BOLD}${BLUE}│ Forwarding Rule : ${CYAN}${FR_NAME}${RESET}"
echo -e "${BOLD}${BLUE}│ targetHttpsProxy: ${CYAN}${PROXY_NAME}${RESET}"
echo -e "${BOLD}${BLUE}└─────────────────────────────────────────────────────┘${RESET}"

# ── STEP 3: Describe targetHttpsProxy ──────────────────────────────────────────────
echo -e "\n${BOLD} [STEP 3] gcloud compute target-https-proxies describe${RESET}"

if [[ "$GLOBAL" == true ]]; then
PROXY_JSON=$(gcloud compute target-https-proxies describe "${PROXY_NAME}" \
--project="${PROJECT}" --global --format="json" 2>/dev/null) || {
echo -e "${RED} [ERROR] Cannot get proxy: ${PROXY_NAME}${RESET}\n"; continue; }
else
PROXY_JSON=$(gcloud compute target-https-proxies describe "${PROXY_NAME}" \
--project="${PROJECT}" --region="${REGION}" --format="json" 2>/dev/null) || {
echo -e "${RED} [ERROR] Cannot get proxy: ${PROXY_NAME}${RESET}\n"; continue; }
fi

PROXY_URL_MAP=$(echo "$PROXY_JSON" | jq -r '.urlMap // "" | split("/") | last')
PROXY_FP=$(echo "$PROXY_JSON" | jq -r '.fingerprint // "N/A"')
CERT_URLS=$(echo "$PROXY_JSON" | jq -r '.sslCertificates // [] | .[]')
CERT_COUNT=$(echo "$PROXY_JSON" | jq '.sslCertificates // [] | length')

row " urlMap" "$PROXY_URL_MAP"
row " fingerprint" "$PROXY_FP"
row " Certificate Count" "$CERT_COUNT"
echo "$PROXY_JSON" | jq -r '.sslCertificates // [] | to_entries[] | " [\(.key+1)] \(.value | split("/") | last)"'

# ── STEP 4: SSL Certificate details ─────────────────────────────────────────────────
echo -e "\n${BOLD} [STEP 4] SSL Certificate Details${RESET}"

if [[ -z "$CERT_URLS" ]]; then
echo -e "${YELLOW} [WARN] This proxy has no associated SSL certificates${RESET}\n"
continue
fi

CERT_INDEX=0
while IFS= read -r CERT_URL; do
CERT_NAME="${CERT_URL##*/}"
CERT_INDEX=$((CERT_INDEX + 1))
echo -e "\n${BOLD} -- Certificate [${CERT_INDEX}]: ${CYAN}${CERT_NAME}${RESET}"

if [[ "$GLOBAL" == true ]]; then
CERT_JSON=$(gcloud compute ssl-certificates describe "${CERT_NAME}" \
--project="${PROJECT}" --global --format="json" 2>/dev/null) || {
echo -e "${RED} [ERROR] Cannot get certificate: ${CERT_NAME}${RESET}"; continue; }
else
CERT_JSON=$(gcloud compute ssl-certificates describe "${CERT_NAME}" \
--project="${PROJECT}" --region="${REGION}" --format="json" 2>/dev/null) || {
echo -e "${RED} [ERROR] Cannot get certificate: ${CERT_NAME}${RESET}"; continue; }
fi

# Basic fields
CERT_TYPE=$(echo "$CERT_JSON" | jq -r '.type // "N/A"')
CERT_STATUS=$(echo "$CERT_JSON" | jq -r '
if .managed.status then .managed.status
elif .selfManaged.status then .selfManaged.status
else "N/A" end')
CERT_CREATED=$(echo "$CERT_JSON" | jq -r '.creationTimestamp // "N/A"')
CERT_EXPIRE=$(echo "$CERT_JSON" | jq -r '.expireTime // ""')

row " Type" "$CERT_TYPE"
row " Status" "$CERT_STATUS"
row " Created" "$CERT_CREATED"

# FQDN / SAN domains
DOMAINS=$(echo "$CERT_JSON" | jq -r '
(.managed.domains // []) + (.subjectAlternativeNames // []) |
unique | .[]')
if [[ -n "$DOMAINS" ]]; then
echo -e " ${CYAN}FQDN / SANs :${RESET}"
while IFS= read -r d; do echo " - $d"; done <<< "$DOMAINS"
else
row " FQDN / SANs" "N/A"
fi

# Expiry time + remaining days
if [[ -n "$CERT_EXPIRE" ]]; then
DAYS=$(days_until_expiry "$CERT_EXPIRE")
LABEL=$(expiry_label "$DAYS")
row " Expires" "${CERT_EXPIRE}${LABEL}"
row " Days Remaining" "${DAYS} days"
else
row " Expires" "N/A"
fi

# Managed certificate domain status
DOMAIN_STATUS=$(echo "$CERT_JSON" | jq -r '
.managed.domainStatus // {} |
to_entries[] |
(if .value == "ACTIVE" then "[OK]" else "[FAIL]" end) + " " + .key + ": " + .value')
if [[ -n "$DOMAIN_STATUS" ]]; then
echo -e " ${CYAN}Domain Status :${RESET}"
while IFS= read -r line; do echo " $line"; done <<< "$DOMAIN_STATUS"
fi

done <<< "$CERT_URLS"

echo -e "\n${BLUE}───────────────────────────────────────────────────────${RESET}\n"

done <<< "$FR_LIST"

echo -e "${GREEN}${BOLD}[DONE] Inspection complete${RESET}"