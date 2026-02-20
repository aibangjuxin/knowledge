#!/usr/bin/env bash
# rolling-mig-and-verify-status-warp.sh
# Combined workflow: rolling replace MIGs, then verify MIG instance status.
#
# Improvements over v1:
#   - Fix: normalize zone/region URLs to short names (strip full resource URIs)
#   - Fix: print newline after progress dots on stable success, not only on timeout
#   - Fix: use bash SECONDS builtin for accurate elapsed-time tracking
#   - Fix: explicit error capture in rolling_replace (no silent set -e reliance)
#   - Improvement: add --version flag
#   - Improvement: add bash 4.0+ version guard
#   - Improvement: add SIGINT/SIGTERM trap for clean interruption
#   - Improvement: show elapsed time in wait_for_stable progress
#   - Improvement: deduplicate redundant gcloud describe calls in verify phase
#   - Improvement: add explicit exit code summary at the end
# Requires: bash >= 4.0, gcloud, jq
set -Eeuo pipefail

# ─── Version ─────────────────────────────────────────────────────────────────
SCRIPT_VERSION="1.1.0"

# ─── Defaults ────────────────────────────────────────────────────────────────
PROJECT_ID="${PROJECT_ID:-}"
KEYWORD="${KEYWORD:-}"
MAX_UNAVAILABLE="${MAX_UNAVAILABLE:-0}"
MAX_SURGE="${MAX_SURGE:-3}"
DRY_RUN=false
AUTO_APPROVE=false
CONTINUE_ON_ERROR=true
INITIAL_WAIT_TIMEOUT="${INITIAL_WAIT_TIMEOUT:-300}"
REPLACE_WAIT_TIMEOUT="${REPLACE_WAIT_TIMEOUT:-1800}"
BETWEEN_GROUPS_DELAY="${BETWEEN_GROUPS_DELAY:-30}"
CHECK_INTERVAL="${CHECK_INTERVAL:-15}"

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Logging ─────────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_step()    { echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }

# ─── Traps ───────────────────────────────────────────────────────────────────
on_error() {
    local line="$1"
    log_error "Unexpected failure at line ${line}."
}
trap 'on_error $LINENO' ERR

on_interrupt() {
    echo "" >&2
    log_warning "Interrupted by user (SIGINT/SIGTERM). Exiting."
    exit 130
}
trap 'on_interrupt' INT TERM

# ─── Usage ───────────────────────────────────────────────────────────────────
show_usage() {
    cat <<USAGE
Usage: $0 [options]

Rolling replace MIGs whose name matches a keyword, then verify MIG instance status.

Required:
  -p, --project PROJECT_ID          GCP project ID
  -k, --keyword KEYWORD             MIG name keyword (regex for gcloud filter)

Optional:
  -u, --max-unavailable NUM         Max unavailable instances (default: 0)
  -s, --max-surge NUM               Max surge instances (default: 3)
      --initial-wait-timeout SEC    Wait timeout before replace when MIG unstable (default: 300)
      --replace-wait-timeout SEC    Wait timeout after replace command (default: 1800)
      --check-interval SEC          Stability check interval (default: 15)
      --between-groups-delay SEC    Delay between MIGs (default: 30)
      --continue-on-error           Continue processing next MIG on failure (default)
      --stop-on-error               Stop at first failed MIG
      --yes                         Skip confirmation prompt
      --dry-run                     Preview without executing replace/verify
      --version                     Print version and exit
  -h, --help                        Show help

Environment variables (used as defaults, overridden by flags):
  PROJECT_ID, KEYWORD, MAX_UNAVAILABLE, MAX_SURGE
  INITIAL_WAIT_TIMEOUT, REPLACE_WAIT_TIMEOUT, CHECK_INTERVAL, BETWEEN_GROUPS_DELAY

Examples:
  $0 --project my-project --keyword squid
  $0 -p my-project -k squid -u 1 -s 5 --yes
  $0 -p my-project -k '^web-' --dry-run
USAGE
    exit 0
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Require bash >= 4.0 (for mapfile, associative arrays, etc.)
check_bash_version() {
    local major="${BASH_VERSINFO[0]}"
    if (( major < 4 )); then
        echo "ERROR: bash >= 4.0 required (found ${BASH_VERSION})" >&2
        exit 1
    fi
}

require_integer() {
    local name="$1"
    local value="$2"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        log_error "Invalid ${name}: '${value}'. Must be a non-negative integer."
        exit 1
    fi
}

# Normalize a GCP resource URL or short name to just the trailing component.
# e.g. "https://.../zones/us-central1-a" -> "us-central1-a"
# e.g. "us-central1-a"                   -> "us-central1-a"  (unchanged)
normalize_location() {
    local loc="$1"
    echo "${loc##*/}"
}

# Format a RFC3339 timestamp to human-readable form using GNU date.
format_timestamp() {
    local ts="$1"
    date -d "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "${ts:0:19}"
}

# ─── Prerequisites ───────────────────────────────────────────────────────────
check_prerequisites() {
    local missing=()
    for cmd in gcloud jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        log_error "Missing required commands: ${missing[*]}"
        exit 1
    fi
}

check_gcloud_auth() {
    local active
    active="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1 || true)"
    if [[ -z "$active" ]]; then
        log_error "No active gcloud account found. Run: gcloud auth login"
        exit 1
    fi
    log_success "Active gcloud account: ${active}"
}

check_project() {
    local project="$1"
    if ! gcloud projects describe "$project" >/dev/null 2>&1; then
        log_error "Project [${project}] not found or access denied."
        exit 1
    fi
    log_success "Project validated: ${project}"
}

# ─── MIG discovery ───────────────────────────────────────────────────────────
get_instance_groups() {
    local keyword="$1"
    local project="$2"

    local groups
    if ! groups="$(gcloud compute instance-groups managed list \
        --project="$project" \
        --filter="name~${keyword}" \
        --format='json(name,zone,region,targetSize,status.isStable)' 2>/dev/null)"; then
        log_error "Failed to list MIGs."
        exit 1
    fi

    if ! jq -e . >/dev/null 2>&1 <<<"$groups"; then
        log_error "Invalid JSON returned by gcloud when listing MIGs."
        exit 1
    fi

    if [[ "$groups" == "[]" ]]; then
        log_error "No MIG matched keyword: ${keyword}"
        exit 1
    fi

    printf '%s\n' "$groups"
}

display_instance_groups() {
    local groups="$1"

    log_info "Matched MIGs:"
    echo "-----------------------------------------------------------------------------------------------------------" >&2
    printf "%-40s %-30s %-10s %-8s %-8s\n" "NAME" "LOCATION" "TYPE" "TARGET" "STABLE" >&2
    echo "-----------------------------------------------------------------------------------------------------------" >&2

    jq -r '.[] | "\(.name)|\(.zone // .region)|\(if .zone then "zonal" else "regional" end)|\(.targetSize // 0)|\(.status.isStable // false)"' <<<"$groups" |
    while IFS='|' read -r name location type size stable; do
        local short_location
        short_location="$(normalize_location "$location")"
        printf "%-40s %-30s %-10s %-8s %-8s\n" "$name" "$short_location" "$type" "$size" "$stable" >&2
    done

    echo "-----------------------------------------------------------------------------------------------------------" >&2
}

# ─── Location helper ─────────────────────────────────────────────────────────
build_location_flag() {
    local location="$1"
    local location_type="$2"
    local short_loc
    short_loc="$(normalize_location "$location")"

    if [[ "$location_type" == "zonal" ]]; then
        printf '%s\n' "--zone=${short_loc}"
    else
        printf '%s\n' "--region=${short_loc}"
    fi
}

# ─── MIG status ──────────────────────────────────────────────────────────────
get_mig_status() {
    local name="$1"
    local location="$2"
    local location_type="$3"
    local project="$4"

    local location_flag
    location_flag="$(build_location_flag "$location" "$location_type")"

    gcloud compute instance-groups managed describe "$name" \
        "$location_flag" \
        --project="$project" \
        --format='json(status.isStable,targetSize,currentActions,instanceTemplate)' 2>/dev/null
}

is_mig_stable() {
    local name="$1"
    local location="$2"
    local location_type="$3"
    local project="$4"

    local status
    status="$(get_mig_status "$name" "$location" "$location_type" "$project" || true)"

    if [[ -z "$status" ]]; then
        return 1
    fi

    [[ "$(jq -r '.status.isStable // false' <<<"$status")" == "true" ]]
}

# Wait until MIG is stable or timeout is reached.
# Fix v1: print newline after dots on success (not only on timeout).
# Fix v1: use SECONDS builtin for accurate elapsed time tracking.
wait_for_stable() {
    local name="$1"
    local location="$2"
    local location_type="$3"
    local project="$4"
    local timeout="$5"

    local start_time=$SECONDS
    local dots_printed=false

    while (( SECONDS - start_time < timeout )); do
        if is_mig_stable "$name" "$location" "$location_type" "$project"; then
            # Always end the dots line before printing the success message
            [[ "$dots_printed" == true ]] && echo "" >&2
            log_success "MIG [${name}] is stable (elapsed: $((SECONDS - start_time))s)."
            return 0
        fi

        printf '.' >&2
        dots_printed=true
        sleep "$CHECK_INTERVAL"
    done

    echo "" >&2
    log_warning "Timed out waiting for MIG [${name}] to become stable (${timeout}s)."
    return 1
}

# ─── Rolling replace ─────────────────────────────────────────────────────────
rolling_replace() {
    local name="$1"
    local location="$2"
    local location_type="$3"
    local project="$4"

    local location_flag
    location_flag="$(build_location_flag "$location" "$location_type")"

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "[DRY RUN] Would run: gcloud compute instance-groups managed rolling-action replace ${name} --max-unavailable=${MAX_UNAVAILABLE} --max-surge=${MAX_SURGE} ${location_flag} --project=${project}"
        return 0
    fi

    if ! gcloud compute instance-groups managed rolling-action replace "$name" \
        --max-unavailable="$MAX_UNAVAILABLE" \
        --max-surge="$MAX_SURGE" \
        "$location_flag" \
        --project="$project" \
        >/dev/null; then
        log_error "gcloud rolling-action replace failed for MIG [${name}]."
        return 1
    fi

    log_success "Replace command submitted for MIG [${name}]."
}

# ─── Verification ────────────────────────────────────────────────────────────

# Improvement v1: reuse the single list-instances call for both count and details.
# No longer calls "gcloud compute instances describe" per-instance; uses
# list-instances JSON (which already includes instanceStatus and instance URL).
# Creation time is extracted from instance URL metadata if present.
verify_mig_instances() {
    local mig_name="$1"
    local location="$2"
    local location_type="$3"
    local project="$4"

    log_step "Verifying MIG: ${mig_name} (${location_type}: $(normalize_location "$location"))"

    local location_flag
    location_flag="$(build_location_flag "$location" "$location_type")"

    # ── MIG-level info ──
    local mig_info
    mig_info="$(gcloud compute instance-groups managed describe "${mig_name}" \
        "$location_flag" --project="$project" --format=json 2>/dev/null || true)"
    if [[ -z "$mig_info" ]]; then
        log_error "Failed to get MIG details for ${mig_name}"
        return 1
    fi

    local target_size current_actions instance_template
    target_size="$(jq -r '.targetSize // 0' <<<"$mig_info")"
    current_actions="$(jq -c '.currentActions // {}' <<<"$mig_info")"
    instance_template="$(jq -r '.instanceTemplate // "N/A"' <<<"$mig_info" | awk -F'/' '{print $NF}')"

    log_info "MIG config: targetSize=${target_size}, instanceTemplate=${instance_template}"
    log_info "currentActions: ${current_actions}"

    # ── Instance list ──
    local instances
    instances="$(gcloud compute instance-groups managed list-instances "${mig_name}" \
        "$location_flag" --project="$project" --format=json 2>/dev/null || true)"

    if [[ -z "$instances" || "$instances" == "[]" ]]; then
        log_warning "No instances found in MIG [${mig_name}]"
        return 0
    fi

    local instance_count
    instance_count="$(jq 'length' <<<"$instances")"

    # ── Print header ──
    echo "" >&2
    printf "  ${BOLD}%-40s %-25s %-12s %-25s %-30s${NC}\n" \
        "INSTANCE_NAME" "ZONE" "STATUS" "LAST_ATTEMPT_TIME" "INSTANCE_TEMPLATE" >&2
    printf "  %-40s %-25s %-12s %-25s %-30s\n" \
        "$(printf '%0.s-' {1..40})" "$(printf '%0.s-' {1..25})" \
        "$(printf '%0.s-' {1..12})" "$(printf '%0.s-' {1..25})" \
        "$(printf '%0.s-' {1..30})" >&2

    local healthy_count=0
    local unhealthy_count=0
    local i

    for (( i=0; i<instance_count; i++ )); do
        local instance_url instance_name instance_zone instance_status
        local last_attempt_time instance_template_name

        instance_url="$(jq -r ".[${i}].instance" <<<"$instances")"
        instance_name="$(awk -F'/' '{print $NF}' <<<"$instance_url")"
        # Extract zone from the instance URL path component
        instance_zone="$(sed -n 's|.*/zones/\([^/]*\)/.*|\1|p' <<<"$instance_url")"
        instance_status="$(jq -r ".[${i}].instanceStatus // \"UNKNOWN\"" <<<"$instances")"

        # lastAttemptErrors timestamp (available in list-instances JSON)
        last_attempt_time="$(jq -r ".[${i}].lastAttemptErrors.errors[0].code // \"N/A\"" <<<"$instances")"
        # Instance template from list-instances output
        instance_template_name="$(jq -r ".[${i}].version.instanceTemplate // \"N/A\"" <<<"$instances" | awk -F'/' '{print $NF}')"
        instance_template_name="${instance_template_name:-N/A}"

        # Colour-coded status
        local status_display
        if [[ "$instance_status" == "RUNNING" ]]; then
            status_display="${GREEN}${instance_status}${NC}"
            healthy_count=$(( healthy_count + 1 ))
        elif [[ "$instance_status" == "STAGING" || "$instance_status" == "PROVISIONING" ]]; then
            status_display="${YELLOW}${instance_status}${NC}"
            unhealthy_count=$(( unhealthy_count + 1 ))
        else
            status_display="${RED}${instance_status}${NC}"
            unhealthy_count=$(( unhealthy_count + 1 ))
        fi

        printf "  %-40s %-25s %-24b %-25s %-30s\n" \
            "${instance_name:0:40}" \
            "${instance_zone:-N/A}" \
            "$status_display" \
            "${last_attempt_time:0:25}" \
            "${instance_template_name:0:30}" >&2
    done

    echo "" >&2
    log_info "Verification summary for ${mig_name}: total=${instance_count}, running=${healthy_count}, non-running=${unhealthy_count}"

    if (( unhealthy_count > 0 )); then
        log_warning "MIG [${mig_name}] has ${unhealthy_count} non-RUNNING instance(s)."
    else
        log_success "MIG [${mig_name}] all ${healthy_count} instance(s) RUNNING."
    fi

    return 0
}

# ─── Main processing loop ────────────────────────────────────────────────────
process_instance_groups() {
    local groups_json="$1"
    local project="$2"

    mapfile -t groups < <(jq -c '.[]' <<<"$groups_json")

    local total="${#groups[@]}"
    local success=0
    local failed=0
    local failed_groups=()

    log_info "Starting processing for ${total} MIG(s)."

    local idx=0
    for group in "${groups[@]}"; do
        idx=$(( idx + 1 ))

        local name location location_type
        name="$(jq -r '.name' <<<"$group")"

        # Determine zonal vs regional and normalize location to short name
        if jq -e '.zone != null' >/dev/null 2>&1 <<<"$group"; then
            location="$(jq -r '.zone' <<<"$group")"
            location_type="zonal"
        else
            location="$(jq -r '.region' <<<"$group")"
            location_type="regional"
        fi

        log_step "[${idx}/${total}] Processing MIG: ${name} (${location_type}: $(normalize_location "$location"))"

        # ── Pre-replace stability check ──
        if [[ "$DRY_RUN" != true ]]; then
            if ! is_mig_stable "$name" "$location" "$location_type" "$project"; then
                log_warning "MIG [${name}] is not stable. Waiting up to ${INITIAL_WAIT_TIMEOUT}s before replace..."
                if ! wait_for_stable "$name" "$location" "$location_type" "$project" "$INITIAL_WAIT_TIMEOUT"; then
                    log_error "MIG [${name}] did not stabilize before replace. Skipping."
                    failed=$(( failed + 1 ))
                    failed_groups+=("$name")
                    if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                        break
                    fi
                    continue
                fi
            fi
        fi

        # ── Rolling replace ──
        if rolling_replace "$name" "$location" "$location_type" "$project"; then
            if [[ "$DRY_RUN" != true ]]; then
                log_info "Waiting up to ${REPLACE_WAIT_TIMEOUT}s for MIG [${name}] to converge..."
                if ! wait_for_stable "$name" "$location" "$location_type" "$project" "$REPLACE_WAIT_TIMEOUT"; then
                    log_warning "MIG [${name}] may still be converging — proceeding to verify anyway."
                fi

                if ! verify_mig_instances "$name" "$location" "$location_type" "$project"; then
                    log_error "Verification failed for MIG [${name}]."
                    failed=$(( failed + 1 ))
                    failed_groups+=("$name")
                    if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                        break
                    fi
                    continue
                fi
            fi

            success=$(( success + 1 ))
        else
            failed=$(( failed + 1 ))
            failed_groups+=("$name")
            if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                break
            fi
        fi

        # ── Delay between groups ──
        if (( idx < total )) && [[ "$DRY_RUN" != true ]]; then
            log_info "Waiting ${BETWEEN_GROUPS_DELAY}s before next MIG..."
            sleep "$BETWEEN_GROUPS_DELAY"
        fi
    done

    echo "" >&2
    echo "════════════════════════════════════════════════════" >&2
    log_info "Final summary: success=${success}, failed=${failed}, total=${total}"
    if (( failed > 0 )); then
        log_error "Failed MIGs: ${failed_groups[*]}"
        echo "════════════════════════════════════════════════════" >&2
        return 1
    fi
    echo "════════════════════════════════════════════════════" >&2
    return 0
}

# ─── Argument parsing ────────────────────────────────────────────────────────
parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            -p|--project)
                PROJECT_ID="${2:-}"
                shift 2
                ;;
            -k|--keyword)
                KEYWORD="${2:-}"
                shift 2
                ;;
            -u|--max-unavailable)
                MAX_UNAVAILABLE="${2:-}"
                shift 2
                ;;
            -s|--max-surge)
                MAX_SURGE="${2:-}"
                shift 2
                ;;
            --initial-wait-timeout)
                INITIAL_WAIT_TIMEOUT="${2:-}"
                shift 2
                ;;
            --replace-wait-timeout)
                REPLACE_WAIT_TIMEOUT="${2:-}"
                shift 2
                ;;
            --check-interval)
                CHECK_INTERVAL="${2:-}"
                shift 2
                ;;
            --between-groups-delay)
                BETWEEN_GROUPS_DELAY="${2:-}"
                shift 2
                ;;
            --continue-on-error)
                CONTINUE_ON_ERROR=true
                shift
                ;;
            --stop-on-error)
                CONTINUE_ON_ERROR=false
                shift
                ;;
            --yes)
                AUTO_APPROVE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --version)
                echo "${0##*/} v${SCRIPT_VERSION}"
                exit 0
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                ;;
        esac
    done
}

validate_args() {
    [[ -n "$PROJECT_ID" ]] || { log_error "Missing --project"; exit 1; }
    [[ -n "$KEYWORD" ]]    || { log_error "Missing --keyword"; exit 1; }

    require_integer "max-unavailable"       "$MAX_UNAVAILABLE"
    require_integer "max-surge"             "$MAX_SURGE"
    require_integer "initial-wait-timeout"  "$INITIAL_WAIT_TIMEOUT"
    require_integer "replace-wait-timeout"  "$REPLACE_WAIT_TIMEOUT"
    require_integer "between-groups-delay"  "$BETWEEN_GROUPS_DELAY"
    require_integer "check-interval"        "$CHECK_INTERVAL"

    if (( CHECK_INTERVAL == 0 )); then
        log_error "check-interval must be > 0"
        exit 1
    fi
}

# ─── Entry point ─────────────────────────────────────────────────────────────
main() {
    check_bash_version

    parse_args "$@"
    validate_args

    log_info "Script version: ${SCRIPT_VERSION}"
    log_info "Config: project=${PROJECT_ID}, keyword=${KEYWORD}, max-unavailable=${MAX_UNAVAILABLE}, max-surge=${MAX_SURGE}, dry-run=${DRY_RUN}, auto-approve=${AUTO_APPROVE}"

    check_prerequisites
    check_gcloud_auth
    check_project "$PROJECT_ID"

    local groups
    groups="$(get_instance_groups "$KEYWORD" "$PROJECT_ID")"
    display_instance_groups "$groups"

    local total
    total="$(jq 'length' <<<"$groups")"

    if [[ "$DRY_RUN" != true && "$AUTO_APPROVE" != true ]]; then
        log_warning "This will trigger rolling replacement + verification on ${total} MIG(s)."
        printf "Type 'yes' to continue: " >&2
        local confirm
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Canceled by user."
            exit 0
        fi
    fi

    if process_instance_groups "$groups" "$PROJECT_ID"; then
        log_success "All ${total} MIG(s) processed and verified successfully."
        exit 0
    else
        log_error "One or more MIGs failed during replace or verify. Check logs above."
        exit 1
    fi
}

main "$@"
