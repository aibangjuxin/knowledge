#!/usr/bin/env bash
#
# dns-debug.sh — GKE DNS Resolution Debug Tool
#
# Traces a DNS query from Pod to public internet, layer by layer.
# Works from inside a GKE Pod, a VM in the same VPC, or your Mac.
#
# Usage:
#   ./dns-debug.sh abc.def.hi.com                    # trace a domain
#   ./dns-debug.sh abc.def.hi.com @169.254.254.254   # use specific resolver
#   ./dns-debug.sh abc.def.hi.com --all               # full debug (zones + VPC + forwarding)
#
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Color codes
# ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color
DIVIDER="════════════════════════════════════════════════════"

# ─────────────────────────────────────────────────────────────
# Default values
# ─────────────────────────────────────────────────────────────
DOMAIN="${1:-}"
RESOLVER="${2:-169.254.254.254}"
MODE="${3:-trace}"   # trace | full | quick
VPC_DNS="169.254.254.254"
GCLOUD_PROJECT="${GCLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo '')}"

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[PASS]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; }
section() { echo -e "\n${BOLD}${DIVIDER}${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${DIVIDER}"; }
header()  { echo -e "\n${BOLD}▶ $*${NC}"; }

# Run dig and capture result
dig_result() {
    dig @"${RESOLVER}" "${DOMAIN}" "$@" +noall+answer +authority +additional 2>/dev/null
}

dig_short() {
    dig @"${RESOLVER}" "${DOMAIN}" "$@" +short 2>/dev/null
}

dig_ns() {
    dig @"${RESOLVER}" "$@" NS +short 2>/dev/null
}

# Extract parent domains from a given domain
# e.g. extract_parents "abc.def.hi.com" → ["hi.com.", "def.hi.com.", "abc.def.hi.com."]
extract_parents() {
    local domain="$1"
    local result=()
    local current="$domain"

    # Strip trailing dot if present
    current="${current%.}"

    while [[ "$current" == *.* ]]; do
        result+=("${current}.")
        current="${current#*.}"
    done

    # Always add the TLD
    result+=("${current}.")

    printf '%s\n' "${result[@]}"
}

# Check if gcloud is available
has_gcloud() {
    command -v gcloud &>/dev/null && [[ -n "${GCLOUD_PROJECT}" ]]
}

# ─────────────────────────────────────────────────────────────
# Usage
# ─────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}DNS Debug Tool — Layer-by-Layer GKE DNS Troubleshooting${NC}

${BOLD}Usage:${NC}
  $0 <domain> [resolver] [mode]

${BOLD}Arguments:${NC}
  domain     Full domain to trace (e.g. abc.def.hi.com)
  resolver   DNS resolver to use (default: 169.254.254.254)
  mode       'trace' (default) | 'full' (all zones) | 'quick' (no NS tracing)

${BOLD}Examples:${NC}
  $0 abc.def.hi.com
  $0 abc.def.hi.com @8.8.8.8
  $0 abc.def.hi.com 169.254.254.254 full
  $0 api.internal.aibang @169.254.254.254 trace

${BOLD}Modes:${NC}
  trace   Trace each domain level from TLD → parent → full domain (default)
  full    trace + list all Cloud DNS zones + VPC config + forwarding targets
  quick   Just resolve the domain, no NS tracing

${BOLD}Prerequisites:${NC}
  - dig (included in macOS, install with 'brew install dig' on older macOS)
  - gcloud (optional, for GCP zone listing)
  - Set GCLOUD_PROJECT env var or run 'gcloud config set project YOUR_PROJECT'

EOF
    exit 1
}

# ─────────────────────────────────────────────────────────────
# Main logic
# ─────────────────────────────────────────────────────────────
main() {
    if [[ -z "${DOMAIN}" ]] || [[ "$DOMAIN" == "--help" ]] || [[ "$DOMAIN" == "-h" ]]; then
        usage
    fi

    # Strip trailing dot
    DOMAIN="${DOMAIN%.}"

    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║       DNS Debug — GKE DNS Resolution Tracer        ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Domain:    ${CYAN}${DOMAIN}${NC}"
    echo -e "  Resolver:  ${CYAN}${RESOLVER}${NC}"
    echo -e "  Mode:      ${CYAN}${MODE}${NC}"
    echo -e "  Project:   ${CYAN}${GCLOUD_PROJECT:-<not set>}${NC}"

    # ── L0: Basic reachability ──────────────────────────────
    section "L0 — Resolver Reachability"
    header "Pinging DNS resolver ${RESOLVER}..."

    if command -v nc &>/dev/null; then
        if nc -wz1 -t "${RESOLVER}" 53 2>/dev/null; then
            ok "Resolver ${RESOLVER}:53 is reachable (TCP)"
        else
            if nc -w3 -u -z "${RESOLVER}" 53 2>/dev/null; then
                ok "Resolver ${RESOLVER}:53 is reachable (UDP)"
            else
                fail "Cannot reach ${RESOLVER}:53 — check VPC firewall rules"
            fi
        fi
    else
        info "nc not available — skipping reachability check"
    fi

    # ── L1: Direct domain resolution ────────────────────────
    section "L1 — Direct Query (${DOMAIN})"
    header "Querying ${DOMAIN} at ${RESOLVER}..."

    local direct_result
    direct_result=$(dig_short)
    if [[ -n "${direct_result}" ]]; then
        ok "Resolved: ${direct_result}"
    else
        warn "No A record returned — might be NXDOMAIN or CNAME chain"
        # Try to get any answer
        dig_result | head -20
    fi

    # Show full answer section
    echo ""
    info "Full answer:"
    dig_result 2>/dev/null | grep -v "^$" | head -30 || true

    # ── L2: NS records for each level ──────────────────────
    if [[ "${MODE}" != "quick" ]]; then
        section "L2 — NS Record Tracing (right → left)"
        header "Tracing NS for each domain level from TLD..."

        local parents
        mapfile -t parents < <(extract_parents "${DOMAIN}")

        echo ""
        printf "  %-30s %s\n" "Domain Level" "NS Records"
        printf "  %-30s %s\n" "------------" "----------"

        local all_ok=true
        for parent in "${parents[@]}"; do
            local ns
            ns=$(dig_ns "${parent}" 2>/dev/null || echo "FAILED")
            if [[ "$ns" == "FAILED" ]] || [[ -z "$ns" ]]; then
                printf "  ${RED}%-30s${NC} %s\n" "${parent}" "❌ No NS found"
                all_ok=false
            else
                printf "  ${GREEN}%-30s${NC} %s\n" "${parent}" "${ns}"
            fi
        done

        if $all_ok; then
            ok "All NS levels resolved correctly"
        else
            warn "Some NS lookups failed — check which level is broken"
        fi
    fi

    # ── L3: GCP Cloud DNS zones (if gcloud available) ───────
    if [[ "${MODE}" == "full" ]] && has_gcloud; then
        section "L3 — GCP Cloud DNS Zones"
        header "Checking Cloud DNS managed zones in project ${GCLOUD_PROJECT}..."

        # Find matching zones
        local matching_zones
        matching_zones=$(gcloud dns managed-zones list \
            --filter="dnsName:~${DOMAIN##*.}." \
            --format="value(name,dnsName,visibility)" 2>/dev/null || echo "")

        if [[ -n "${matching_zones}" ]]; then
            ok "Matching zone(s) found:"
            echo "${matching_zones}" | while IFS=$'\t' read -r name dns visibility; do
                echo "  ───────────────────────────────────────"
                echo "  Zone:       ${name}"
                echo "  DNS Name:   ${dns}"
                echo "  Visibility: ${visibility}"
                echo ""
                echo "  Forwarding config:"
                gcloud dns managed-zones describe "${name}" \
                    --format="yaml(forwardingConfig)" 2>/dev/null | grep -v "^$" | sed 's/^/    /'
                echo "  Peering config:"
                gcloud dns managed-zones describe "${name}" \
                    --format="yaml(peeringConfig)" 2>/dev/null | grep -v "^$" | sed 's/^/    /'
            done
        else
            warn "No Cloud DNS zone found for ${DOMAIN}"
        fi

        # List all private zones
        echo ""
        info "All private zones in this project:"
        gcloud dns managed-zones list \
            --filter="visibility=private" \
            --format="table(name,dnsName)" 2>/dev/null || warn "Failed to list zones"

        # ── L4: Response Policies ──────────────────────────
        section "L4 — Response Policy Rules"
        header "Checking Response Policies..."

        local rp_result
        rp_result=$(gcloud dns response-policies list \
            --format="yaml(responsePolicyRules)" 2>/dev/null || echo "")
        if [[ -n "${rp_result}" ]]; then
            ok "Response Policy found (see above)"
        else
            info "No Response Policy rules configured"
        fi

        # ── L5: VPC DNS config ──────────────────────────────
        section "L5 — VPC DNS Configuration"
        header "Checking VPC DNS config..."

        info "Run this to see VPC DNS settings:"
        echo "  gcloud compute networks describe YOUR_VPC_NAME \\\\"
        echo "    --format=\"yaml(dnsConfiguration)\""

        # Try to get default VPC
        local default_vpc
        default_vpc=$(gcloud compute networks list \
            --filter="name:mynetwork" \
            --format="value(name)" 2>/dev/null | head -1 || echo "")
        if [[ -n "${default_vpc}" ]]; then
            echo ""
            info "Default VPC (mynetwork) DNS config:"
            gcloud compute networks describe "${default_vpc}" \
                --format="yaml(dnsConfiguration)" 2>/dev/null | sed 's/^/  /' || true
        fi
    fi

    # ── L6: SMTP / Email DNS checks ────────────────────────
    if [[ "${MODE}" == "full" ]]; then
        section "L6 — DNS Record Types (MX / TXT / CNAME)"
        header "Checking additional record types..."

        for rtype in MX TXT CNAME AAAA; do
            local result
            result=$(dig @"${RESOLVER}" "${DOMAIN}" ${rtype} +short 2>/dev/null || echo "")
            if [[ -n "${result}" ]]; then
                ok "${rtype} record: ${result}"
            else
                info "${rtype} record: (not found)"
            fi
        done
    fi

    # ── L7: CNAME chain ────────────────────────────────────
    section "L7 — CNAME Chain (if any)"
    header "Following CNAME chain..."

    dig_result 2>/dev/null | grep "CNAME" | while read -r line; do
        echo "  ${line}"
    done

    # ── Final summary ──────────────────────────────────────
    section "Summary"
    echo ""
    echo -e "  ${BOLD}Domain:${NC}      ${DOMAIN}"
    echo -e "  ${BOLD}Resolver:${NC}     ${RESOLVER}"
    echo -e "  ${BOLD}Result:${NC}       ${direct_result:-NO A RECORD}"
    echo ""
    echo -e "  ${BOLD}Next steps if failed:${NC}"
    echo "  1. Verify NS records for each level (see L2 above)"
    echo "  2. Check VPC firewall: allow UDP/TCP 53 from 169.254.0.0/16"
    echo "  3. Check if Cloud DNS zone is bound to VPC (see L3 above)"
    echo "  4. Test forwarding target: dig @10.x.x.x ${DOMAIN}"
    echo "  5. Check Cloud DNS logs: gcloud logging read 'dns_query'"
    echo ""
    echo -e "${BOLD}Debug complete.${NC}"
}

main "$@"
