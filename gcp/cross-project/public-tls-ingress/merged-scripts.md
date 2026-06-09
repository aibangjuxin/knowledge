# Shell Scripts Collection

Generated on: 2026-06-08 18:16:01
Directory: /Users/lex/git/gcp/ingress/public-tls-ingress/scripts

## `lex-poc-housekeep-consumer-resource.sh`

```bash
#!/usr/bin/env bash
# =============================================================================
# lex-poc-housekeep-consumer-resource.sh
# -----------------------------------------------------------------------------
# Housekeeping: delete Consumer VPC resources created by lex-poc-create-consumer-resource.sh
# (Reverse dependency order — start from External Static IP §5 onward, KEEP subnet §4.)
#
# Per user requirement:
# - Subnet-Proxy (item #4) is NOT deleted (network infra, leave intact)
# - All other resources from item #5 onward are deleted
# - Idempotent: skip-if-not-exists for each step (safe to re-run)
#
# Reference: tenant-tls-setup-https.md §5.2 "Consumer VPC" cleanup section
#
# Usage:
# ./lex-poc-housekeep-consumer-resource.sh # default PREFIX=lex-poc
# PREFIX=lex-poc-test ./lex-poc-housekeep-consumer-resource.sh
# ./lex-poc-housekeep-consumer-resource.sh --help
#
# Exit codes:
#0 all deletions completed (or resources not present)
#1 arg parse / pre-flight failure
#2 a delete step failed unexpectedly
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Section0. Colors / helpers
# -----------------------------------------------------------------------------
if [[ -t1 ]]; then
 BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
 RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
 BLUE=$'\033[34m'; CYAN=$'\033[36m'
else
 BOLD=''; DIM=''; RESET=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''
fi

step() { printf '\n%s%s[step] %s%s\n' "$BOLD" "$CYAN" "$1" "$RESET"; }
ok() { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$1"; }
err() { printf '%s[err]%s %s\n' "$RED" "$RESET" "$1" >&2; }
info() { printf '%s[info]%s %s\n' "$BLUE" "$RESET" "$1"; }
skip() { printf '%s[skip]%s %s (not present)\n' "$DIM" "$RESET" "$1"; }

usage() {
 echo -e "$(cat <<EOF
${BOLD}Usage:${RESET} $0 [options]

${BOLD}Options:${RESET}
 --prefix=NAME override resource name prefix (default: lex-poc)
 --project=ID override GCP project (default: aibang-12345678-ajbx-dev)
 --region=REGION override GCP region (default: europe-west2)
 --network=NAME override consumer VPC network (default: aibang-12345678-ajbx-dev-cinternal-vpc1)
 --dry-run print what would be deleted, do not actually delete
 --force skip the interactive confirm prompt
 --help, -h show this help

${BOLD}Resources DELETED (reverse dependency order, §5 onward):${RESET}
16. Detach Cloud Armor from BS (must happen before deleting BS)
15. Remove NEG from BS (must happen before deleting BS)
14. PSC NEG
13. Backend Service (HTTPS)
10. Cloud Armor (security policy) + its rate limit rules
9. Forwarding Rule
7. Target HTTPS Proxy
8. URL Map
6. SSL Certificate
5. External Static IP

${BOLD}Resources KEPT (NOT deleted):${RESET}
4. Subnet-Proxy (\${PREFIX}-proxy) — network infra, leave intact
1-3. VPC + core subnet + GKE subnet — pre-existing, not in our scope

EOF
)"
}

# -----------------------------------------------------------------------------
# Section1. Parse args
# -----------------------------------------------------------------------------
DRY_RUN=false
FORCE=false
for arg in "$@"; do
 case "$arg" in
 --help|-h) usage; exit 0 ;;
 --prefix=*) PREFIX="${arg#*=}" ;;
 --project=*) PROJECT="${arg#*=}" ;;
 --region=*) REGION="${arg#*=}" ;;
 --network=*) NETWORK="${arg#*=}" ;;
 --dry-run) DRY_RUN=true ;;
 --force|-f) FORCE=true ;;
 *) err "unknown flag: $arg"; usage; exit 1 ;;
 esac
done

# -----------------------------------------------------------------------------
# Section2. Defaults
# -----------------------------------------------------------------------------
: "${PREFIX:=lex-poc}"
: "${PROJECT:=aibang-12345678-ajbx-dev}"
: "${REGION:=europe-west2}"
: "${NETWORK:=aibang-12345678-ajbx-dev-cinternal-vpc1}"

# Derived resource names
SUBNET_PROXY="${PREFIX}-${REGION}-abjx-proxy"
GLB_IP="${PREFIX}-public-glb-ip"
SSL_CERT="${PREFIX}-public-cert"
TARGET_HTTPS_PROXY="${PREFIX}-public-proxy"
URL_MAP="${PREFIX}-public-um"
FR="${PREFIX}-public-fr"
ARMOR="${PREFIX}-public-armor"
BS="${PREFIX}-public-bs"
PSC_NEG="${PREFIX}-public-neg"

# Generic delete helper (idempotent, --quiet, capture errors)
do_delete() {
 local resource_type="$1" resource_name="$2"; shift 2
 local exists_check_cmd=("$@")
 if "${exists_check_cmd[@]}" >/dev/null2>&1; then
 if [[ "$DRY_RUN" == true ]]; then
 info "[dry-run] would delete: $resource_type $resource_name"
 return 0
 fi
 info "deleting: $resource_type $resource_name"
 if gcloud "$resource_type" delete "$resource_name" --project="$PROJECT" --region="$REGION" --quiet 2>&1; then
 ok "deleted: $resource_name"
 else
 err "FAILED to delete: $resource_name (might be already deleting, or has dependent refs)"
 return 1
 fi
 else
 skip "$resource_type $resource_name"
 fi
}

# Detach armor helper (no-op if not attached)
do_detach_armor() {
 if gcloud compute backend-services describe "$BS" \
 --project="$PROJECT" --region="$REGION" \
 --format="get(securityPolicy.basename())"2>/dev/null | grep -q "$ARMOR"; then
 if [[ "$DRY_RUN" == true ]]; then
 info "[dry-run] would detach $ARMOR from $BS"
 return 0
 fi
 info "detaching $ARMOR from $BS"
 # detach by setting security-policy to none
 gcloud compute backend-services update "$BS" \
 --project="$PROJECT" --region="$REGION" \
 --security-policy="" --quiet 2>&1 \
 || gcloud compute backend-services update "$BS" \
 --project="$PROJECT" --region="$REGION" \
 --clear-security-policy --quiet 2>&1 \
 || warn "detach failed (may already be detached)"
 ok "armor detached"
 else
 skip "armor not attached to $BS"
 fi
}

# Remove NEG from BS helper (no-op if not present)
do_remove_neg_from_bs() {
 local has_neg
 has_neg=$(gcloud compute backend-services describe "$BS" \
 --project="$PROJECT" --region="$REGION" \
 --format="get(backends)"2>/dev/null || true)
 if [[ "$has_neg" == *"$PSC_NEG"* ]]; then
 if [[ "$DRY_RUN" == true ]]; then
 info "[dry-run] would remove $PSC_NEG from $BS"
 return 0
 fi
 info "removing $PSC_NEG from $BS"
 gcloud compute backend-services remove-backend "$BS" \
 --project="$PROJECT" --region="$REGION" \
 --network-endpoint-group="$PSC_NEG" \
 --network-endpoint-group-region="$REGION" --quiet 2>&1 \
 || warn "remove-backend failed (NEG may already be gone)"
 ok "NEG removed from BS"
 else
 skip "$PSC_NEG not attached to $BS"
 fi
}

# -----------------------------------------------------------------------------
# Section3. Banner
# -----------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}"
echo "========================================================================"
echo " Consumer Resources Housekeep - POC"
echo "========================================================================"
echo -e "${RESET}"
printf ' %-22s %s\n' "PREFIX" "$PREFIX"
printf ' %-22s %s\n' "PROJECT" "$PROJECT"
printf ' %-22s %s\n' "REGION" "$REGION"
printf ' %-22s %s\n' "NETWORK" "$NETWORK"
printf ' %-22s %s\n' "DRY_RUN" "$DRY_RUN"

# -----------------------------------------------------------------------------
# Section4. Pre-flight
# -----------------------------------------------------------------------------
step "0. Pre-flight checks"

#4.1 gcloud auth
if ! gcloud auth list --filter=status:ACTIVE --format='value(account)'2>/dev/null | grep -q '@'; then
 err "gcloud has no active auth - run gcloud auth login first"
 exit 1
fi
ok "gcloud authenticated"

#4.2 project exists
if ! gcloud projects describe "$PROJECT" >/dev/null2>&1; then
 err "project does not exist or no access: $PROJECT"
 exit 1
fi
gcloud config set project "$PROJECT" >/dev/null
ok "project = $PROJECT (active)"

#4.3 confirm unless --force
if [[ "$FORCE" != true && "$DRY_RUN" != true ]]; then
 printf '\n%sAbout to DELETE all PREFIX=%s resources from project=%s region=%s.%s\n' \
 "$YELLOW" "$PREFIX" "$PROJECT" "$REGION" "$RESET"
 printf 'Subnet-Proxy (%s) is KEPT. Dry-run available with --dry-run.\n' "$SUBNET_PROXY"
 read -p "Continue? (y/N): " confirm
 if [[ "$confirm" != [yY] ]]; then
 err "aborted by user"
 exit 1
 fi
fi

# -----------------------------------------------------------------------------
# Section5. Cleanup steps (reverse dependency order)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Step16 (cleanup) - Detach Cloud Armor from BS (do BEFORE deleting BS)
# -----------------------------------------------------------------------------
step "Detach Cloud Armor from Backend Service"

if gcloud compute backend-services describe "$BS" \
 --project="$PROJECT" --region="$REGION" >/dev/null2>&1; then
 do_detach_armor
else
 skip "Backend Service $BS not present, nothing to detach"
fi

# -----------------------------------------------------------------------------
# Step15 (cleanup) - Remove NEG from BS (do BEFORE deleting BS or NEG)
# -----------------------------------------------------------------------------
step "Remove PSC NEG from Backend Service"

if gcloud compute backend-services describe "$BS" \
 --project="$PROJECT" --region="$REGION" >/dev/null2>&1; then
 do_remove_neg_from_bs
else
 skip "Backend Service $BS not present, nothing to remove"
fi

# -----------------------------------------------------------------------------
# Step14 (cleanup) - PSC NEG
# -----------------------------------------------------------------------------
step "Delete PSC NEG ($PSC_NEG)"

do_delete network-endpoint-groups "$PSC_NEG" \
 gcloud compute network-endpoint-groups describe "$PSC_NEG" \
 --project="$PROJECT" --region="$REGION"

# -----------------------------------------------------------------------------
# Step13 (cleanup) - Backend Service
# -----------------------------------------------------------------------------
step "Delete Backend Service ($BS)"

do_delete backend-services "$BS" \
 gcloud compute backend-services describe "$BS" \
 --project="$PROJECT" --region="$REGION"

# -----------------------------------------------------------------------------
# Step10 (cleanup) - Cloud Armor security policy
# -----------------------------------------------------------------------------
step "Delete Cloud Armor ($ARMOR)"

# Cloud Armor has rules too — delete them first (in reverse priority order)
if gcloud compute security-policies describe "$ARMOR" \
 --project="$PROJECT" --region="$REGION" >/dev/null2>&1; then
 info "deleting all rules under $ARMOR"
 # list rules and delete by priority (reverse order — highest priority first)
 RULE_PRIORITIES=$(gcloud compute security-policies rules list \
 --project="$PROJECT" --region="$REGION" \
 --security-policy="$ARMOR" --format="value(priority)"2>/dev/null || true)
 if [[ -n "$RULE_PRIORITIES" ]]; then
 for prio in $RULE_PRIORITIES; do
 if [[ "$DRY_RUN" == true ]]; then
 info "[dry-run] would delete rule priority=$prio on $ARMOR"
 else
 gcloud compute security-policies rules delete "$prio" \
 --project="$PROJECT" --region="$REGION" \
 --security-policy="$ARMOR" --quiet 2>&1 \
 || warn "rule delete failed for priority=$prio"
 fi
 done
 ok "rules removed"
 else
 skip "no rules to delete"
 fi
 do_delete security-policies "$ARMOR" \
 gcloud compute security-policies describe "$ARMOR" \
 --project="$PROJECT" --region="$REGION"
else
 skip "Cloud Armor $ARMOR not present"
fi

# -----------------------------------------------------------------------------
# Step9 (cleanup) - Forwarding Rule
# -----------------------------------------------------------------------------
step "Delete Forwarding Rule ($FR)"

do_delete forwarding-rules "$FR" \
 gcloud compute forwarding-rules describe "$FR" \
 --project="$PROJECT" --region="$REGION"

# -----------------------------------------------------------------------------
# Step7 (cleanup) - Target HTTPS Proxy
# -----------------------------------------------------------------------------
step "Delete Target HTTPS Proxy ($TARGET_HTTPS_PROXY)"

do_delete target-https-proxies "$TARGET_HTTPS_PROXY" \
 gcloud compute target-https-proxies describe "$TARGET_HTTPS_PROXY" \
 --project="$PROJECT" --region="$REGION"

# -----------------------------------------------------------------------------
# Step8 (cleanup) - URL Map
# -----------------------------------------------------------------------------
step "Delete URL Map ($URL_MAP)"

do_delete url-maps "$URL_MAP" \
 gcloud compute url-maps describe "$URL_MAP" \
 --project="$PROJECT" --region="$REGION"

# -----------------------------------------------------------------------------
# Step6 (cleanup) - SSL Certificate
# -----------------------------------------------------------------------------
step "Delete SSL Certificate ($SSL_CERT)"

do_delete ssl-certificates "$SSL_CERT" \
 gcloud compute ssl-certificates describe "$SSL_CERT" \
 --project="$PROJECT" --region="$REGION"

# -----------------------------------------------------------------------------
# Step5 (cleanup) - External Static IP
# -----------------------------------------------------------------------------
step "Delete External Static IP ($GLB_IP)"

do_delete addresses "$GLB_IP" \
 gcloud compute addresses describe "$GLB_IP" \
 --project="$PROJECT" --region="$REGION"

# -----------------------------------------------------------------------------
# Section6. Verify remaining state
# -----------------------------------------------------------------------------
step "Verify - remaining PREFIX=$PREFIX resources (should be EMPTY)"

REMAINING=0
for cmd_label in \
 "forwarding-rules:forwarding-rules list --filter=name~$PREFIX --format=value(name)" \
 "backend-services:backend-services list --filter=name~$PREFIX --format=value(name)" \
 "target-https-proxies:target-https-proxies list --filter=name~$PREFIX --format=value(name)" \
 "url-maps:url-maps list --filter=name~$PREFIX --format=value(name)" \
 "ssl-certificates:ssl-certificates list --filter=name~$PREFIX --format=value(name)" \
 "network-endpoint-groups:network-endpoint-groups list --filter=name~$PREFIX --format=value(name)" \
 "security-policies:security-policies list --filter=name~$PREFIX --format=value(name)" \
 "addresses:addresses list --filter=name~$PREFIX --format=value(address)"; do
 label="${cmd_label%%:*}"
 cmd="${cmd_label#*:}"
 out=$(gcloud compute $cmd --project="$PROJECT" --region="$REGION"2>/dev/null || true)
 if [[ -n "$out" ]]; then
 warn "$label: $out"
 REMAINING=$((REMAINING + $(echo "$out" | wc -l | tr -d ' ')))
 fi
done

# Subnet-Proxy should STILL exist (we kept it)
if gcloud compute networks subnets describe "$SUBNET_PROXY" \
 --project="$PROJECT" --region="$REGION" >/dev/null2>&1; then
 ok "subnet-Proxy $SUBNET_PROXY KEPT (as expected, per user requirement)"
else
 warn "subnet-Proxy $SUBNET_PROXY not found — was it never created or already deleted?"
fi

echo
if [[ "$REMAINING" -eq 0 ]]; then
 echo -e "${BOLD}${GREEN}"
 echo "========================================================================"
 echo " Housekeep complete - all PREFIX=$PREFIX resources deleted"
 echo "========================================================================"
 echo -e "${RESET}"
else
 echo -e "${BOLD}${YELLOW}"
 echo "========================================================================"
 echo " Housekeep complete with $REMAINING remaining items — review above"
 echo "========================================================================"
 echo -e "${RESET}"
fi

echo
echo " Notes:"
echo " - Subnet-Proxy $SUBNET_PROXY kept (network infra)"
echo " - Pre-existing VPC + core subnet + GKE subnet untouched"
echo " - Cert files in $CERT_DIR NOT touched (file-system)"
echo

```

## `lex-poc-create-consumer-resource.sh`

```bash
#!/usr/bin/env bash
# =============================================================================
# lex-poc-create-consumer-resource.sh
# -----------------------------------------------------------------------------
# Create Consumer VPC (`cinternal-vpc1`-side) resources for the
# External HTTPS GLB -> PSC NEG -> Producer ILB -> MIG path.
#
# References:
# - tenant-tls-setup-https.md section5.2 "Consumer VPC - cinternal-vpc1"
# (resources4-16, since1-3 are pre-existing VPC + core + GKE subnets)
# - pitfall section6.2 (gcloud CLI MANAGED parsing bug -> use YAML import)
# - pitfall section6.3 (backend-services --port=443 not recognized -> use --port-name=https)
#
# Pre-requisites (must exist before running):
# - VPC + core subnet + GKE subnet (doc section5.2 items1-3)
# - cert/key files in CERT_DIR (filename has underscore, see doc section6.1)
# - Producer-side (ajbx-tenant-vpc) Service Attachment must exist or be created after
#
# Usage:
# ./lex-poc-create-consumer-resource.sh # default PREFIX=lex-poc
# PREFIX=lex-demo ./lex-poc-create-consumer-resource.sh
# ./lex-poc-create-consumer-resource.sh --help
#
# Exit codes:
#0 success (all13 create +2 association steps done)
#1 pre-flight check failed (missing cert, missing VPC, etc.)
#2 a gcloud create step failed
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Section0. Colors / helpers
# -----------------------------------------------------------------------------
if [[ -t1 ]]; then
 BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
 RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
 BLUE=$'\033[34m'; CYAN=$'\033[36m'
else
 BOLD=''; DIM=''; RESET=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''
fi

step() { printf '\n%s%s[step] %s%s\n' "$BOLD" "$CYAN" "$1" "$RESET"; }
ok() { printf '%s[ok]%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$1"; }
err() { printf '%s[err]%s %s\n' "$RED" "$RESET" "$1" >&2; }
info() { printf '%s[info]%s %s\n' "$BLUE" "$RESET" "$1"; }

usage() {
 echo -e "$(cat <<EOF
${BOLD}Usage:${RESET} $0 [options]

${BOLD}Options:${RESET}
 --prefix=NAME override resource name prefix (default: lex-poc)
 --project=ID override GCP project (default: aibang-12345678-ajbx-dev)
 --region=REGION override GCP region (default: europe-west2)
 --network=NAME override consumer VPC network (default: aibang-12345678-ajbx-dev-cinternal-vpc1)
 --core-subnet=NAME override PSC-NEG core subnet (default: <network>-europe-west2-abjx-core)
 --proxy-cidr=CIDR override proxy-only subnet CIDR (default:192.168.96.0/24)
 --cert-dir=PATH override cert/key directory (default: ~/tmp/lex-poc-certs)
 --help, -h show this help

${BOLD}Resources created (13 +2 association, doc section5.2 items4-16):${RESET}
4. Subnet - Proxy (\${PREFIX}-proxy)
5. External Static IP (\${PREFIX}-public-glb-ip)
6. SSL Certificate (\${PREFIX}-public-cert)
7. Target HTTPS Proxy (\${PREFIX}-public-proxy)
8. URL Map (\${PREFIX}-public-um)
9. Forwarding Rule (:443) (\${PREFIX}-public-fr)
10. Cloud Armor (regional) (\${PREFIX}-public-armor)
13. Backend Service (HTTPS) (\${PREFIX}-public-bs) [YAML import]
14. PSC NEG (\${PREFIX}-public-neg)
15. Add NEG -> BS (association)
16. Attach Cloud Armor -> BS (association)

EOF
)"
}

# -----------------------------------------------------------------------------
# Section1. Parse args
# -----------------------------------------------------------------------------
for arg in "$@"; do
 case "$arg" in
 --help|-h) usage; exit 0 ;;
 --prefix=*) PREFIX="${arg#*=}" ;;
 --project=*) PROJECT="${arg#*=}" ;;
 --region=*) REGION="${arg#*=}" ;;
 --network=*) NETWORK="${arg#*=}" ;;
 --core-subnet=*) CORE_SUBNET="${arg#*=}" ;;
 --proxy-cidr=*) PROXY_SUBNET_CIDR="${arg#*=}" ;;
 --cert-dir=*) CERT_DIR="${arg#*=}" ;;
 *) err "unknown flag: $arg"; usage; exit 1 ;;
 esac
done

# -----------------------------------------------------------------------------
# Section2. Defaults (single source of truth at top)
# -----------------------------------------------------------------------------
: "${PREFIX:=lex-poc}"
: "${PROJECT:=aibang-12345678-ajbx-dev}"
: "${REGION:=europe-west2}"
: "${NETWORK:=aibang-12345678-ajbx-dev-cinternal-vpc1}"
: "${CORE_SUBNET:=${NETWORK}-europe-west2-abjx-core}"
: "${PROXY_SUBNET_CIDR:=192.168.96.0/24}"
: "${CERT_DIR:=$HOME/tmp/lex-poc-certs}"

# Note: actual filename has underscore tenant.taobao.caep.uk_bundle.crt
# doc section6.1 pitfall: hex decode shows underscore between uk and bundle
CERT_FILE="$CERT_DIR/tenant.taobao.caep.uk_bundle.crt"
KEY_FILE="$CERT_DIR/tenant.taobao.caep.uk.key"

# Derived resource names (PREFIX assembly)
SUBNET_PROXY="${PREFIX}-${REGION}-abjx-proxy"
GLB_IP="${PREFIX}-public-glb-ip"
SSL_CERT="${PREFIX}-public-cert"
TARGET_HTTPS_PROXY="${PREFIX}-public-proxy"
URL_MAP="${PREFIX}-public-um"
FR="${PREFIX}-public-fr"
ARMOR="${PREFIX}-public-armor"
BS="${PREFIX}-public-bs"
PSC_NEG="${PREFIX}-public-neg"

# Temp YAML directory (cleaned up on exit)
YAML_DIR="$(mktemp -d -t lex-poc-yaml.XXXXXX)"
cleanup_yaml() { rm -rf "$YAML_DIR"; }
trap cleanup_yaml EXIT

# -----------------------------------------------------------------------------
# Section3. Banner
# -----------------------------------------------------------------------------
echo -e "${BOLD}${CYAN}"
echo "========================================================================"
echo " Consumer Resources Create - POC"
echo "========================================================================"
echo -e "${RESET}"
printf ' %-22s %s\n' "PREFIX" "$PREFIX"
printf ' %-22s %s\n' "PROJECT" "$PROJECT"
printf ' %-22s %s\n' "REGION" "$REGION"
printf ' %-22s %s\n' "NETWORK" "$NETWORK"
printf ' %-22s %s\n' "CORE_SUBNET" "$CORE_SUBNET"
printf ' %-22s %s\n' "PROXY_SUBNET_CIDR" "$PROXY_SUBNET_CIDR"
printf ' %-22s %s\n' "CERT_DIR" "$CERT_DIR"
printf ' %-22s %s\n' "CERT_FILE" "$CERT_FILE"
printf ' %-22s %s\n' "KEY_FILE" "$KEY_FILE"

# -----------------------------------------------------------------------------
# Section4. Pre-flight checks
# -----------------------------------------------------------------------------
step "0. Pre-flight checks"

#4.1 cert/key files exist
if [[ ! -f "$CERT_FILE" ]]; then
 err "cert file not found: $CERT_FILE"
 echo " expected: in $CERT_DIR, filename has underscore (doc section6.1)"
 exit 1
fi
if [[ ! -f "$KEY_FILE" ]]; then
 err "key file not found: $KEY_FILE"
 exit 1
fi
ok "cert + key files present"

#4.2 cert/key match (modulus check)
LEAF_MOD=$(openssl x509 -in "$CERT_FILE" -noout -modulus 2>/dev/null | sed 's/Modulus=//')
KEY_MOD=$(openssl rsa -in "$KEY_FILE" -noout -modulus 2>/dev/null | sed 's/Modulus=//')
if [[ "$LEAF_MOD" != "$KEY_MOD" ]]; then
 err "cert and key do not match (modulus mismatch)"
 exit 1
fi
ok "cert and key modulus match"

#4.3 gcloud auth
if ! gcloud auth list --filter=status:ACTIVE --format='value(account)'2>/dev/null | grep -q '@'; then
 err "gcloud has no active auth - run gcloud auth login first"
 exit 1
fi
ok "gcloud authenticated"

#4.4 project exists and is set
if ! gcloud projects describe "$PROJECT" >/dev/null2>&1; then
 err "project does not exist or no access: $PROJECT"
 exit 1
fi
gcloud config set project "$PROJECT" >/dev/null
ok "project = $PROJECT (active)"

#4.5 assume VPC + core subnet exist (doc section5.2 items1-2)
if ! gcloud compute networks describe "$NETWORK" --project="$PROJECT" >/dev/null2>&1; then
 err "VPC does not exist: $NETWORK"
 echo " This is a pre-requisite for the POC - create the VPC first"
 exit 1
fi
ok "VPC = $NETWORK (exists)"

if ! gcloud compute networks subnets describe "$CORE_SUBNET" \
 --project="$PROJECT" --region="$REGION" >/dev/null2>&1; then
 err "core subnet does not exist: $CORE_SUBNET"
 echo " PSC NEG attachment requires this subnet"
 exit 1
fi
ok "core subnet = $CORE_SUBNET (exists)"

echo
info "Pre-flight OK - starting13 +2 creation steps"
info "Order (doc section5.2): Subnet-Proxy -> Static-IP -> Cert -> Proxy -> UM -> FR -> Armor -> BS -> NEG -> assoc"

# -----------------------------------------------------------------------------
# Section5. Step4 - Subnet - Proxy (REGIONAL_MANAGED_PROXY)
# -----------------------------------------------------------------------------
step "4. Subnet - Proxy ($SUBNET_PROXY)"

info "purpose=REGIONAL_MANAGED_PROXY role=ACTIVE for External GLB proxy"
gcloud compute networks subnets create "$SUBNET_PROXY" \
 --project="$PROJECT" \
 --network="$NETWORK" \
 --region="$REGION" \
 --range="$PROXY_SUBNET_CIDR" \
 --purpose=REGIONAL_MANAGED_PROXY \
 --role=ACTIVE \
 --description="External GLB proxy-only subnet for ${PREFIX} POC"

echo " verify:"
gcloud compute networks subnets describe "$SUBNET_PROXY" \
 --project="$PROJECT" --region="$REGION" \
 --format="table(name,region.basename(),ipCidrRange,purpose,role,network.basename())"
ok "subnet created"

# -----------------------------------------------------------------------------
# Section6. Step5 - External Static IP (PREMIUM tier)
# -----------------------------------------------------------------------------
step "5. External Static IP ($GLB_IP)"

info "PREMIUM tier EXTERNAL IP, GLB entry address"
gcloud compute addresses create "$GLB_IP" \
 --project="$PROJECT" \
 --region="$REGION" \
 --network-tier=PREMIUM \
 --ip-version=IPV4 \
 --description="External GLB public IP for ${PREFIX} POC"

echo " verify:"
GLB_IP_ADDR=$(gcloud compute addresses describe "$GLB_IP" \
 --project="$PROJECT" --region="$REGION" --format="value(address)")
gcloud compute addresses describe "$GLB_IP" \
 --project="$PROJECT" --region="$REGION" \
 --format="table(name,address,region.basename(),networkTier,status)"
ok "static IP created = $GLB_IP_ADDR"

# -----------------------------------------------------------------------------
# Section7. Step6 - SSL Certificate (regional)
# -----------------------------------------------------------------------------
step "6. SSL Certificate ($SSL_CERT)"

info "regional SSL cert (SELF_MANAGED), file uploaded to GCP"
gcloud compute ssl-certificates create "$SSL_CERT" \
 --project="$PROJECT" \
 --region="$REGION" \
 --certificate="$CERT_FILE" \
 --private-key="$KEY_FILE" \
 --description="TrustAsia DV cert for ${PREFIX} POC (regional)"

echo " verify:"
gcloud compute ssl-certificates describe "$SSL_CERT" \
 --project="$PROJECT" --region="$REGION" \
 --format="table(name,type,region.basename(),expireTime,creationTimestamp)"
ok "SSL cert created"

# -----------------------------------------------------------------------------
# Section8. Step8 - URL Map (created BEFORE HTTPS proxy because proxy refs it)
# -----------------------------------------------------------------------------
step "8. URL Map ($URL_MAP) [created first - HTTPS proxy references it]"

info "default service = $BS (BS not yet built, but UM does not require BS to exist)"
gcloud compute url-maps create "$URL_MAP" \
 --project="$PROJECT" \
 --region="$REGION" \
 --default-service="$BS" \
 --description="External GLB URL map for ${PREFIX} POC"

echo " verify:"
gcloud compute url-maps describe "$URL_MAP" \
 --project="$PROJECT" --region="$REGION" \
 --format="table(name,defaultService.basename(),region.basename())"
ok "URL map created"

# -----------------------------------------------------------------------------
# Section9. Step7 - Target HTTPS Proxy (references cert + UM)
# -----------------------------------------------------------------------------
step "7. Target HTTPS Proxy ($TARGET_HTTPS_PROXY)"

info "cert + UM already created in previous steps"
gcloud compute target-https-proxies create "$TARGET_HTTPS_PROXY" \
 --project="$PROJECT" \
 --region="$REGION" \
 --url-map="$URL_MAP" \
 --url-map-region="$REGION" \
 --ssl-certificates="$SSL_CERT" \
 --ssl-certificates-region="$REGION" \
 --description="External GLB HTTPS proxy for ${PREFIX} POC"

echo " verify:"
gcloud compute target-https-proxies describe "$TARGET_HTTPS_PROXY" \
 --project="$PROJECT" --region="$REGION" \
 --format="table(name,urlMap.basename(),sslCertificates.basename(),region.basename())"
ok "target HTTPS proxy created"

# -----------------------------------------------------------------------------
# Section10. Step9 - Forwarding Rule (port443, EXTERNAL_MANAGED)
# -----------------------------------------------------------------------------
step "9. Forwarding Rule ($FR) port443"

info "EXTERNAL_MANAGED scheme, PREMIUM tier, attached to $NETWORK"
# Note: --load-balancing-scheme=EXTERNAL_MANAGED uses underscore single-token form.
# `create` command accepts this. (Space form "EXTERNAL MANAGED" hits the gcloud CLI
# parsing bug documented in section6.2 - use YAML import in that case.)
gcloud compute forwarding-rules create "$FR" \
 --project="$PROJECT" \
 --region="$REGION" \
 --load-balancing-scheme=EXTERNAL_MANAGED \
 --target-https-proxy="$TARGET_HTTPS_PROXY" \
 --target-https-proxy-region="$REGION" \
 --address="$GLB_IP" \
 --address-region="$REGION" \
 --ports=443 \
 --network-tier=PREMIUM \
 --network="$NETWORK" \
 --description="External GLB FR for ${PREFIX} POC (port443)"

echo " verify:"
gcloud compute forwarding-rules describe "$FR" \
 --project="$PROJECT" --region="$REGION" \
 --format="table(name,IPAddress,portRange,loadBalancingScheme,target.basename(),networkTier)"
ok "forwarding rule created"

# -----------------------------------------------------------------------------
# Section11. Step10 - Cloud Armor (regional, security policy)
# -----------------------------------------------------------------------------
step "10. Cloud Armor ($ARMOR) - regional security policy"

info "rate limit + DDoS (regional, must pair with regional BS, see doc section5.2 item10)"
gcloud compute security-policies create "$ARMOR" \
 --project="$PROJECT" \
 --region="$REGION" \
 --description="Public GLB DDoS + rate limit for ${PREFIX} POC"

echo " add rate limit rule (threshold200/min, ban600s):"
gcloud compute security-policies rules create1000 \
 --project="$PROJECT" \
 --region="$REGION" \
 --security-policy="$ARMOR" \
 --expression="true" \
 --action=rate-based-ban \
 --rate-limit-threshold-count=200 \
 --rate-limit-threshold-interval-sec=60 \
 --ban-duration-sec=600 \
 --conform-action=allow \
 --exceed-action=deny-403 \
 --enforce-on-app=disabled \
 --description="Rate limit200 req/min, ban600s"

echo " verify:"
gcloud compute security-policies describe "$ARMOR" \
 --project="$PROJECT" --region="$REGION" \
 --format="table(name,region.basename(),type)"
gcloud compute security-policies rules list \
 --project="$PROJECT" --region="$REGION" \
 --security-policy="$ARMOR" \
 --format="table(priority,expression,action,rateLimitThreshold.count)"
ok "Cloud Armor policy + rate limit rule created"

# -----------------------------------------------------------------------------
# Section12. Step13 - Backend Service (HTTPS) - YAML import (section6.2 pitfall)
# -----------------------------------------------------------------------------
step "13. Backend Service ($BS) HTTPS [YAML import - doc section6.2 pitfall]"

info "protocol=HTTPS + port-name=https, NO --port flag (doc section6.3 pitfall)"
info "loadBalancingScheme uses space 'EXTERNAL MANAGED' in YAML, REST API bypasses CLI bug"
BS_SPEC="$YAML_DIR/bs-spec.yaml"
cat > "$BS_SPEC" <<EOF
name: $BS
loadBalancingScheme: EXTERNAL MANAGED
protocol: HTTPS
portName: https
timeoutSec:30
backends:
- group: 'https://www.googleapis.com/compute/v1/projects/$PROJECT/regions/$REGION/networkEndpointGroups/$PSC_NEG'
logConfig:
 enable: true
 sampleRate:1.0
description: 'External GLB -> PSC NEG -> ILB (HTTPS backend) for ${PREFIX} POC'
EOF
echo " YAML spec written to $BS_SPEC"

# NEG not yet created, but BS backend field allows referencing a non-existent
# group URL (immutable field is validated at create time but NEG is created next)
gcloud compute backend-services import "$BS" \
 --project="$PROJECT" \
 --region="$REGION" \
 --source="$BS_SPEC" \
 --quiet

echo " verify:"
gcloud compute backend-services describe "$BS" \
 --project="$PROJECT" --region="$REGION" \
 --format="table(name,protocol,portName,loadBalancingScheme,timeoutSec)"
ok "backend service created (protocol=HTTPS, port-name=https)"

# -----------------------------------------------------------------------------
# Section13. Step14 - PSC NEG (cross-project bridge to producer SA)
# -----------------------------------------------------------------------------
step "14. PSC NEG ($PSC_NEG)"

# Producer SA name = "ajbx-tenant-vpc-internal-sa" (doc section5.1 item19)
# Default: same project, same region
PRODUCER_SA="projects/$PROJECT/regions/$REGION/serviceAttachments/ajbx-tenant-vpc-internal-sa"
info "PSC target = $PRODUCER_SA"
info "subnet = $CORE_SUBNET (used by PSC NEG for attachment IP)"
gcloud compute network-endpoint-groups create "$PSC_NEG" \
 --project="$PROJECT" \
 --region="$REGION" \
 --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
 --psc-target-service="$PRODUCER_SA" \
 --subnet="$CORE_SUBNET" \
 --network="$NETWORK" \
 --description="PSC NEG cross-project bridge for ${PREFIX} POC"

echo " verify:"
gcloud compute network-endpoint-groups describe "$PSC_NEG" \
 --project="$PROJECT" --region="$REGION" \
 --format="table(name,networkEndpointType,pscTargetService,subnet.basename(),network.basename())"
ok "PSC NEG created"

# -----------------------------------------------------------------------------
# Section14. Step15 - Add NEG to BS (association)
# -----------------------------------------------------------------------------
step "15. Add NEG -> BS (association)"

info "attach PSC NEG to BS as backend"
gcloud compute backend-services add-backend "$BS" \
 --project="$PROJECT" \
 --region="$REGION" \
 --network-endpoint-group="$PSC_NEG" \
 --network-endpoint-group-region="$REGION" \
 --balancing-mode=UTILIZATION \
 --capacity-scaler=1.0

echo " verify:"
gcloud compute backend-services describe "$BS" \
 --project="$PROJECT" --region="$REGION" \
 --format="get(backends)"
ok "NEG added to BS"

# -----------------------------------------------------------------------------
# Section15. Step16 - Attach Cloud Armor to BS (association)
# -----------------------------------------------------------------------------
step "16. Attach Cloud Armor -> BS (association)"

info "attach Cloud Armor to new BS (rate limit200/min)"
gcloud compute backend-services update "$BS" \
 --project="$PROJECT" \
 --region="$REGION" \
 --security-policy="$ARMOR"

echo " verify:"
gcloud compute backend-services describe "$BS" \
 --project="$PROJECT" --region="$REGION" \
 --format="get(name,securityPolicy.basename())"
ok "Cloud Armor attached to BS"

# -----------------------------------------------------------------------------
# Section16. Final self-check
# -----------------------------------------------------------------------------
step "Final self-check - status of all13 created resources"

echo
echo " forwarding rules:"
gcloud compute forwarding-rules list --project="$PROJECT" \
 --filter="name~$PREFIX" \
 --format="table(name.basename(),IPAddress,portRange,loadBalancingScheme,target.basename())"
echo
echo " backend services:"
gcloud compute backend-services list --project="$PROJECT" \
 --filter="name~$PREFIX" \
 --format="table(name.basename(),protocol,portName,loadBalancingScheme,region.basename())"
echo
echo " target https proxies:"
gcloud compute target-https-proxies list --project="$PROJECT" \
 --filter="name~$PREFIX" \
 --format="table(name.basename(),region.basename())"
echo
echo " url maps:"
gcloud compute url-maps list --project="$PROJECT" \
 --filter="name~$PREFIX" \
 --format="table(name.basename(),defaultService.basename())"
echo
echo " ssl certificates:"
gcloud compute ssl-certificates list --project="$PROJECT" \
 --filter="name~$PREFIX" \
 --format="table(name,type,region.basename(),expireTime)"
echo
echo " NEGs (PSC):"
gcloud compute network-endpoint-groups list --project="$PROJECT" \
 --filter="name~$PREFIX" \
 --format="table(name.basename(),networkEndpointType,pscTargetService,pscConnectionId)"
echo
echo " cloud armor (security policies):"
gcloud compute security-policies list --project="$PROJECT" \
 --filter="name~$PREFIX" \
 --format="table(name.basename(),region.basename(),type)"
echo
echo " proxy subnets:"
gcloud compute networks subnets list --project="$PROJECT" \
 --filter="name~$SUBNET_PROXY" \
 --format="table(name.basename(),region.basename(),ipCidrRange,purpose,role)"
echo
echo " static IPs:"
gcloud compute addresses list --project="$PROJECT" \
 --filter="name~$PREFIX" \
 --format="table(name.basename(),address,region.basename(),networkTier,status)"

echo
echo -e "${BOLD}${GREEN}"
echo "========================================================================"
echo " Consumer Resources Create - POC complete"
echo "========================================================================"
echo -e "${RESET}"
echo
echo " GLB IP: $GLB_IP_ADDR"
echo
echo " Next steps (e2e test, requires Producer-side ready):"
echo " curl --resolve <your-domain>:443:$GLB_IP_ADDR https://<your-domain>/"
echo " curl --resolve <your-domain>:443:$GLB_IP_ADDR https://<your-domain>/healthz"
echo
echo " Cleanup:"
echo " ./lex-poc-housekeep-consumer-resource.sh # default PREFIX=lex-poc"
echo " PREFIX=$PREFIX ./lex-poc-housekeep-consumer-resource.sh"

```

## `startup-nginx.sh`

```bash
#!/bin/bash
set -e
exec > /var/log/startup.log 2>&1
echo "[startup] starting at $(date -u)"

mkdir -p /opt/tenant
base64 -d > /opt/tenant/server.crt <<'CERT_EOF'
LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUczVENDQk1XZ0F3SUJBZ0lRRDJ4Zk5iWVZwbG1rNGM5djltR0taakFOQmdrcWhraUc5dzBCQVFzRkFEQmIKTVFzd0NRWURWUVFHRXdKRFRqRWxNQ01HQTFVRUNoTWNWSEoxYzNSQmMybGhJRlJsWTJodWIyeHZaMmxsY3l3ZwpTVzVqTGpFbE1DTUdBMVVFQXhNY1ZISjFjM1JCYzJsaElFUldJRlJNVXlCU1UwRWdRMEVnTWpBeU5UQWVGdzB5Ck5qQTJNRFV3TURBd01EQmFGdzB5TmpBNU1ESXlNelU1TlRsYU1DQXhIakFjQmdOVkJBTVRGWFJsYm1GdWRDNTAKWVc5aVlXOHVZMkZsY0M1MWF6Q0NBU0l3RFFZSktvWklodmNOQVFFQkJRQURnZ0VQQURDQ0FRb0NnZ0VCQU44TgpycVpkVXFOVmZ1Y1ZVZE92Nlg3dWdrVVgyYURPamMyaWpoU0QrZG5zNXBTMmU2VjJNMmdETG5waVZqV05GRi9YCjlDZWlSem5aeXFIeXNnb213WjA0bmd1bUFyTVdza1VYRU5pMWhyVUUvQ3VuNWpTR243WEpzUi9aaGV3N3lhZGcKQjNOUkV6bW1BY3BZcDI4akVMdC9tZW1wRVhwTUFTdklXay9VcWM2cnpBdEx5Q2VBeCt6USthODN3eU5NUkEzNwoxUnR4a0MyNDhFRmJMSEVkZnFsL1lxR0syS3FIMTF2byt6cTI3OWlKOFhXWVJrS3FoNVNYZUtBRDN4dld1Z21uCjl4aG95dm01cDZySkdrSm9Db1c2bThGdjRyYTA0S0p3TEQ0ZThOQWRDcEZ0ODVvT0Y2TmtHeFBoRE1uTTAyaVAKRWhDc1NoZXQ1djAyb3BLS3pXY0NBd0VBQWFPQ0F0WXdnZ0xTTUI4R0ExVWRJd1FZTUJhQUZMUVNLS1cwd0IyZgpLWEZwUE5rUmxrcDFhVkRBTUIwR0ExVWREZ1FXQkJTdGpOdHB0R3RGUldCaXRsdmFEZFlONjhUbit6QWdCZ05WCkhSRUVHVEFYZ2hWMFpXNWhiblF1ZEdGdlltRnZMbU5oWlhBdWRXc3dQZ1lEVlIwZ0JEY3dOVEF6QmdabmdRd0IKQWdFd0tUQW5CZ2dyQmdFRkJRY0NBUlliYUhSMGNEb3ZMM2QzZHk1a2FXZHBZMlZ5ZEM1amIyMHZRMUJUTUE0RwpBMVVkRHdFQi93UUVBd0lGb0RBVEJnTlZIU1VFRERBS0JnZ3JCZ0VGQlFjREFUQjVCZ2dyQmdFRkJRY0JBUVJ0Ck1Hc3dKQVlJS3dZQkJRVUhNQUdHR0doMGRIQTZMeTl2WTNOd0xtUnBaMmxqWlhKMExtTnZiVEJEQmdnckJnRUYKQlFjd0FvWTNhSFIwY0RvdkwyTmhZMlZ5ZEhNdVpHbG5hV05sY25RdVkyOXRMMVJ5ZFhOMFFYTnBZVVJXVkV4VApVbE5CUTBFeU1ESTFMbU55ZERBTUJnTlZIUk1CQWY4RUFqQUFNSUlCZmdZS0t3WUJCQUhXZVFJRUFnU0NBVzRFCmdnRnFBV2dBZFFEQ01YNVhSUm1qUmU1L09ONnlrRUhyeDhJaFdpSy9mOVcxclhhYTJRNVN6UUFBQVo2VnFSdVYKQUFBRUF3QkdNRVFDSUc2T0huaWNRMm1DUTJpNXg5Z2ExeEJSQU9JWWFoQUpFQlA5czVLNTBwTlRBaUJLbjN2SgpMK2VkMVhXU1J5elhTMk5jRnhML1BhR1RwaTdxYmIwMlFmWmJCQUIyQU5kdGZSRFJwL1Yzd3NmcFg5Y0F2L21DCnlUTmFaZUhRc3dGekY4REl4V2wzQUFBQm5wV3BHMklBQUFRREFFY3dSUUlnQ01lRWYvNFlqck5NNXdNNHhSN3AKQjg4ODd1WER3UGF3MEtNVUNXNkl6UEFDSVFDVisxU21TbmZEWmcrOERvRGdGcm0zUTB6cVNOWUhXSEpBemNMLwp3OEprSXdCM0FKUk9RNGY2N01IdmdmTVpKQ2FvR0dVQng5TmZPQUlCUDNKbmZWVTNMaG5ZQUFBQm5wV3BHNmdBCkFBUURBRWd3UmdJaEFOODg4TzE2Z2hCeUFmL3lFT2tXTHVHRTYrZllxVy9XZjhGUWI1ZE1XUTVnQWlFQWxET0gKWnI0ZnhhUFhSMUg4ZW5HM3VNbVE5alZ5VG1jV1UrY1gvUnJCUFdzd0RRWUpLb1pJaHZjTkFRRUxCUUFEZ2dJQgpBRUs0OVk2ckZidWVkcmd2OWdPZklRZDMzdjdXbzBrWndLbVgvMnhOcUhMUTRJc0l2T085UkdqbHErTExLcEJvCk5jcFF4VTl4aTBUcXVhWGhJK3pyZTlXYUlKZmdkSitXMXF1T2JabGFTRkpZUnliK0szSjNadnhqSXhhYTBLRXgKbSttYkhhUUFsYkZ2eHF1QW5Ca2F0ZTJwb2dlNU9NczJDSjZ2a0lndkpOd0paSVU5UzlNT0s4K29WdWhUM1B5UApqdHB2M2p3RlhTcDk2NWp6U0pwOGFWcnhOTmdLUy9FVk5ZQ09laGd6NmJHdFVtVlp0dXZ5eGE5WnpIckgreFVLCmNEWDAwaFBsdVVUL0NFc1dLeHpoOUpqTi8wVDBCTW9RMCtmYUhhUVgyU1RJYzFrMDE5T3kvWENWZ01XUE9qUUYKUEVwbFplcWczMTJLcitpRk40SDVELzFEd2JJVDlFQU8xRGViNWppT1IvMnRweWZFZVkzeUVFcXBLaXRaSlZXUgpWV3A3SzVFLzk4TlUwOXl2T2gyOS9vcG41NWhFdlBqWng4WEl4NlFsUFE2d042dU5wNTdDaUV5NlVhYnlydUcvCmdydGd5Smw1YXZVUkJvemg3UDFqSmJXOXArSElCb1grNXdjUUg1eTE3Z3I0cTRCZ1dyQllWT0ZyS2VVSlBMQWcKS3JvV0JycjV0dXVPWHdKeUVVL2JqSlJSS29FM0NuYVNST0d4cUc2Qmg4YmNNRnA4K0pJMWF3MkhtaWRsVUZjdwp4b0VRaXkwVURxSzlBeXd2UTcxY1dHZHFoSFRxVlNMYXdiZ2M0cFQ3RFdiazB6WXZCUW9aaWpUelJMejJvaWFtCnNhaTFTTDlZc0pzMG9iSzQ0SWRnclFFREN0cmZUZ0dXeURjSFdMbDhubDZGCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0KLS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUZuakNDQklhZ0F3SUJBZ0lRQ1NZeU8wbGs0MmhHRlJMZThhWFZMREFOQmdrcWhraUc5dzBCQVFzRkFEQmgKTVFzd0NRWURWUVFHRXdKVlV6RVZNQk1HQTFVRUNoTU1SR2xuYVVObGNuUWdTVzVqTVJrd0Z3WURWUVFMRXhCMwpkM2N1WkdsbmFXTmxjblF1WTI5dE1TQXdIZ1lEVlFRREV4ZEVhV2RwUTJWeWRDQkhiRzlpWVd3Z1VtOXZkQ0JICk1qQWVGdzB5TlRBeE1EZ3dNREF3TURCYUZ3MHpOVEF4TURjeU16VTVOVGxhTUZzeEN6QUpCZ05WQkFZVEFrTk8KTVNVd0l3WURWUVFLRXh4VWNuVnpkRUZ6YVdFZ1ZHVmphRzV2Ykc5bmFXVnpMQ0JKYm1NdU1TVXdJd1lEVlFRRApFeHhVY25WemRFRnphV0VnUkZZZ1ZFeFRJRkpUUVNCRFFTQXlNREkxTUlJQ0lqQU5CZ2txaGtpRzl3MEJBUUVGCkFBT0NBZzhBTUlJQ0NnS0NBZ0VBMGZ1RW11QklzTjZaWlZxK2dSb2JNb3JPR0lpbFRDSWZRcnhOcFI4RlVaOVIKL0dmYmlla2JpSUtwaFFYRVo3TjF1Qm5uNnRYVXVaMzJ6bDZqUGtacEh6Ti9CbWdrMUJXU0l6VmMwbnBNenJXcQovaHJiazUrS2RkWEpkc05wZUcxK1E4bGM4dVZNQnJ6dG54YVBiN1JoN3lRQ3NNcmNPNGhnVmFxTEpXa1Z2RWZXClVMdG9DSFFuTmFqNElyb0c2VnhRZjFvQXJROGJQYndwSTAybGllU2FoUmE3OEZRdVhkb0dWZVFjcmtodFZqWnMKT045OHZxNWZQV1pYMkxGdjdlNUo2UDlJSGJ6dk9sOHl5UWp2KzIvSU93aE5Ta2FYWDNiSSsvL2JxRjlYVy9wNworZ3NVbUhpSzVZc3ZMam1YY3ZEbW9ERUdyWE16Z1gzMVpsMm5KK3VtcFJiTGp3UDhyeFlJVXNLb0V3RWRGb3RvCkFpZDU5VUVCSnl3L0dpYndYUTV4VHlLRC9ONkM4U0ZrcjErbXlPbzRvZTFVQitZZ3ZSdTZxU3hJQUJvNWtZZFgKRm9kTFA0SWdvVkpkZVVGczFVc2E2YnhZRU82RWdNZjVsQ1d0OWhHWnN6dlhZWnd2eVpHcTNvZ05YTTdlS3lpMgoyMFd6SlhZTW1pOVRZRnEyRmE5NWFaZTR3a2k2WWhEaGhPTzFnMHNqSVRHVmFCNzNHK0pPQ0k5eUpodjYrUkVOCkQ0MFpwYm9VSEU4Sk5nTVZXYkcxaXNBTVZDWHFpQURnWHR1Qyt0bUpXUEVIOWNSNk91SkxFcHdPelBmZ0Fibm4KMk1SdTdUc2RyOGpQalRQYkQwRnhibFgxeWRXM1JHMzB2d0xGNWxrVFRSa0hHOWVwTWdwUE1kWVA3blkvMDhNQwpBd0VBQWFPQ0FWWXdnZ0ZTTUJJR0ExVWRFd0VCL3dRSU1BWUJBZjhDQVFBd0hRWURWUjBPQkJZRUZMUVNLS1cwCndCMmZLWEZwUE5rUmxrcDFhVkRBTUI4R0ExVWRJd1FZTUJhQUZFNGlWQ0FZbGViamJ1WVArdnE1RXUwR0Y0ODUKTUE0R0ExVWREd0VCL3dRRUF3SUJoakFkQmdOVkhTVUVGakFVQmdnckJnRUZCUWNEQVFZSUt3WUJCUVVIQXdJdwpkZ1lJS3dZQkJRVUhBUUVFYWpCb01DUUdDQ3NHQVFVRkJ6QUJoaGhvZEhSd09pOHZiMk56Y0M1a2FXZHBZMlZ5CmRDNWpiMjB3UUFZSUt3WUJCUVVITUFLR05HaDBkSEE2THk5allXTmxjblJ6TG1ScFoybGpaWEowTG1OdmJTOUUKYVdkcFEyVnlkRWRzYjJKaGJGSnZiM1JITWk1amNuUXdRZ1lEVlIwZkJEc3dPVEEzb0RXZ000WXhhSFIwY0RvdgpMMk55YkRNdVpHbG5hV05sY25RdVkyOXRMMFJwWjJsRFpYSjBSMnh2WW1Gc1VtOXZkRWN5TG1OeWJEQVJCZ05WCkhTQUVDakFJTUFZR0JGVWRJQUF3RFFZSktvWklodmNOQVFFTEJRQURnZ0VCQUo0YTNzdmgzMTZHWTIrWjdFWXgKbUJJc093akpTbnlvRWZ6eDJUNjk5Y3RMTHJ2dXpTNzlNZzNwUGp4U0xsVWd5TThVenJGYzV0Z1ZVM2RaMXNGUQpJNFJNK3lzSmR2SUFYLzdZeDFRYm9vVmRLaGtkaTlYN1FON3lWa2pxd00zZlkzV2ZRa1JUemhJa003bVlJUWJSCnIreTJWa2p1NjFCTHFoN09DUnBQTWl1ZGpFcFAxa0V0UnlHczJnMGFRcEVJcUtCenhnaXRDWFNheU8xaG9PNi8KNzF0czgwMU96WWxxWVc5T1FRUTJHQ0p5RmJENlhIRGpkcG4rYldVeFRLV2FNWTBxZWRTQ2JIRTNLbDJRRUYwQwp5blo3U2JDMDN5UitnS1pRRGVUWHJOUDFrazVRaGU3alNYZ3crbmhic3BlMHEvTTFaY05DeitzUHhlT3dkQ2NDCmdKRT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQ==
CERT_EOF
base64 -d > /opt/tenant/server.key <<'KEY_EOF'
LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQ0KTUlJRW93SUJBQUtDQVFFQTN3MnVwbDFTbzFWKzV4VlIwNi9wZnU2Q1JSZlpvTTZOemFLT0ZJUDUyZXptbExaNw0KcFhZemFBTXVlbUpXTlkwVVg5ZjBKNkpIT2RuS29mS3lDaWJCblRpZUM2WUNzeGF5UlJjUTJMV0d0UVQ4SzZmbQ0KTklhZnRjbXhIOW1GN0R2SnAyQUhjMUVUT2FZQnlsaW5ieU1RdTMrWjZha1Jla3dCSzhoYVQ5U3B6cXZNQzB2SQ0KSjRESDdORDVyemZESTB4RURmdlZHM0dRTGJqd1FWc3NjUjErcVg5aW9Zcllxb2ZYVytqN09yYnYySW54ZFpoRw0KUXFxSGxKZDRvQVBmRzlhNkNhZjNHR2pLK2JtbnFza2FRbWdLaGJxYndXL2l0clRnb25Bc1BoN3cwQjBLa1czeg0KbWc0WG8yUWJFK0VNeWN6VGFJOFNFS3hLRjYzbS9UYWlrb3JOWndJREFRQUJBb0lCQVFES0xUR3dGQWpTaWEwaw0KTWh2Z1A2UHFiSy9oaHJPNVlXQUJFeVdyak5DTWFvRzZMQW01T1lGdzl1bEsveFZiSnN4ZjczT2I5U2lRVkV1cQ0KTFR5Wm5QV0QxNHpSekNESVNYcyt5cUIzZlZwamUraENmY1pZdCtuTnNjcDlyd0lIMVUxOEM3dlZGNWpRZVJ0SQ0KV01FektGcURTUzZ1TDVQckFUZFNneUR4R1RidFh2SzVTSS94V3JsbHNVMUJXTkpqS1BPWGw5RlNNUkNrc0RjMQ0KM0FzbmhOM0loUFJRcXNOWmIzb1AwRU5scHNlRE9Tb1hROEhwOHdweUg3SlRWNlNzWDFiNnBhVStKQTExUW9JYQ0KcnBOZXIyUnVxaDVzS0lGUTVUQllCQkpia3FDdlMvMlJqUVVKcVlBTGVxU3BjRDc3bjdJV2pKNFQwd1ZUc2o1VA0KSGtlMEdsQlpBb0dCQU44MHo3QVNlZkw0V01RaURnZ1Bac3dYbktxMTIwU05FWmU4WXN6MGQwekZyVENQMkkxZw0KSklxK2tnVTFzOUhFYVVEL2I2QU1hbE9WUnh4L0FMQVBXM1IzWmZmVnQrQUFROU00T0VlVlZKdldqVEFQcTF6dw0KZUdzNzVldlBoVXFIK3ZiNlR5TS9PVGpZSGxzZlFxZHQyK0dKTGNXbEhYTTRSNzV2VjFySFpIRjFBb0dCQVAvVA0KSHorTGhmNmw1Umdyb2lITTFzNy8vU2RxSWNxMmZJa0JmQjY5L3FqeXQwdk5sVy96ZHcrSzh3OTlSeWJQVEFpSw0KNDJ1QkZQc2d1YWN4UmNIeG95YWFYSUtKOGFDZjgzMkpQRDFBQXN3SWUxWS91RnJMSkg4WnQxM2hkVkxCSkd2bg0KVFI4cU5HQWJPNjZmU0ErYnZKNmFPdmlVa0JqYVlELzd6M2d3S0N2ckFvR0FHc2VrVDNTNEN1Mi9BTEV4UzhoRg0KUmlGakc1dzhGWXB6WE9ndVZuYlNSWFRHSmJoc2UvSFlFSWx5ellzMjZ1a00wODZSM3ZyK1dzN2pQRWtFbFJzUw0KbHZPb1dVYmNDOVVjVGlCRnFGa0RVTHM2TDFVQjgyR3FvUHNMeC9JYkJPa3h0Q1l1RG9XTVlRU1ZCOHZGWEg4eQ0KeldsL0EyS2ZHTzdjdEwxNUZwd3JzZTBDZ1lBMmJ6eng3NFZHaHhRMVRXdUZWNm5KaUF6YzZ5ZGZrKzd4MUNBTw0KQm8xK2M0N3ZFVUtmL0tVejZIUUpzcldHRzR2cE1XeHN2cDJ4UmVoYkhBL2swYjdPZ3YvMlF0WG9RTUMxMEpMQg0KMGJJR3FqTmNTZGkzY1F4R0F6blNQeHdRek1vc0w1NW9hRG1XelpTb2Rub0Y0RFNGWnZudlZPVklkSWNRZGt0Uw0KSHFVZG13S0JnSDB3TGdKNHJGMDFzakpQWElqa0FFQ1h0Yng5cHU3SEtGOUtWbUJZTjBlQ2dBSFZ3TnA0WU42Tg0KTjhteHdQaisyUmRiZXVOUXJ6YjY2S0l0Qm5lZTlZSlVqWkZFaENNOW1BWm1MODk0dytsdCtneXlpaFA2YzdFNA0KR1V1Y3A2eUd3aVpsVGQrYnFWcTQweTVnQkJBVTdqaTZFWEdKOG1KV1dzSGswTjY1SnJsYg0KLS0tLS1FTkQgUlNBIFBSSVZBVEUgS0VZLS0tLS0=
KEY_EOF
chmod 600 /opt/tenant/server.key

LEAF_MOD=$(openssl x509 -in /opt/tenant/server.crt -noout -modulus 2>/dev/null | sed 's/Modulus=//')
KEY_MOD=$(openssl rsa -in /opt/tenant/server.key -noout -modulus 2>/dev/null | sed 's/Modulus=//')
[[ "$LEAF_MOD" == "$KEY_MOD" ]] && echo "[startup] ✓ cert+key matched" || { echo "[startup] ✗ cert+key NOT matched"; exit 1; }

cat > /opt/tenant/server.py <<'PYTHON_EOF'
import http.server, ssl, os, sys, time, threading, socketserver

INDEX_HTML = '''<!DOCTYPE html>
<html><head><title>tenant.taobao.caep.uk</title></head>
<body>
<h1>OK</h1>
<p>Hello from PSC NEG end-to-end test (HTTPS)</p>
<p>VM: {}</p>
<p>Time: {}</p>
</body></html>
'''
CERT = '/opt/tenant/server.crt'
KEY = '/opt/tenant/server.key'

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))
    def do_GET(self):
        if self.path == '/healthz':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'ok')
        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            body = INDEX_HTML.format(os.uname().nodename, time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())).encode()
            self.wfile.write(body)

class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

def serve_http():
    srv = ThreadedHTTPServer(('0.0.0.0', 80), H)
    sys.stderr.write("[http] listening on :80\n")
    srv.serve_forever()

def serve_https():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT, KEY)
    srv = ThreadedHTTPServer(('0.0.0.0', 443), H)
    srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
    sys.stderr.write("[https] listening on :443\n")
    srv.serve_forever()

threading.Thread(target=serve_http, daemon=True).start()
serve_https()
PYTHON_EOF

cat > /etc/systemd/system/tenant-server.service <<'SYSTEMD_EOF'
[Unit]
Description=Tenant Hello World HTTP+HTTPS server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -u /opt/tenant/server.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

systemctl daemon-reload
systemctl enable tenant-server
systemctl restart tenant-server
sleep 3
systemctl status tenant-server --no-pager | head -5
ss -tlnp 2>/dev/null | grep -E ':(80|443) '
echo "[startup] complete"

```

