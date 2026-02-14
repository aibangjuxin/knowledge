#!/usr/bin/env bash
# rolling-replace-mig-enhance.sh
# Enhanced rolling replace script for GCE Managed Instance Groups (MIGs).

set -Eeuo pipefail

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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }
log_step() { echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2; }

on_error() {
    local line="$1"
    log_error "Unexpected failure at line ${line}."
}
trap 'on_error $LINENO' ERR

show_usage() {
    cat <<USAGE
Usage: $0 [options]

Rolling replace MIGs whose name matches a keyword.

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
      --dry-run                     Preview without executing replace
  -h, --help                        Show help

Examples:
  $0 --project my-project --keyword squid
  $0 -p my-project -k squid -u 1 -s 5 --yes
  $0 -p my-project -k '^web-' --dry-run
USAGE
    exit 0
}

require_integer() {
    local name="$1"
    local value="$2"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        log_error "Invalid ${name}: ${value}. Must be a non-negative integer."
        exit 1
    fi
}

check_prerequisites() {
    local missing=()
    for cmd in gcloud jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if ((${#missing[@]} > 0)); then
        log_error "Missing commands: ${missing[*]}"
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
    log_success "Active account: ${active}"
}

check_project() {
    local project="$1"
    gcloud projects describe "$project" >/dev/null 2>&1 || {
        log_error "Project [${project}] not found or access denied."
        exit 1
    }
    log_success "Project validated: ${project}"
}

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
    printf "%-40s %-20s %-10s %-10s %-10s\n" "NAME" "LOCATION" "TYPE" "TARGET" "STABLE" >&2
    echo "-----------------------------------------------------------------------------------------------------------" >&2

    jq -r '.[] | "\(.name)|\(.zone // .region)|\(if .zone then "zonal" else "regional" end)|\(.targetSize // 0)|\(.status.isStable // false)"' <<<"$groups" |
    while IFS='|' read -r name location type size stable; do
        printf "%-40s %-20s %-10s %-10s %-10s\n" "$name" "$location" "$type" "$size" "$stable" >&2
    done

    echo "-----------------------------------------------------------------------------------------------------------" >&2
}

build_location_flag() {
    local location="$1"
    local location_type="$2"

    if [[ "$location_type" == "zonal" ]]; then
        printf '%s\n' "--zone=${location}"
    else
        printf '%s\n' "--region=${location}"
    fi
}

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
        --format='json(status.isStable,targetSize,currentActions)' 2>/dev/null
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

wait_for_stable() {
    local name="$1"
    local location="$2"
    local location_type="$3"
    local project="$4"
    local timeout="$5"

    local elapsed=0
    while (( elapsed < timeout )); do
        if is_mig_stable "$name" "$location" "$location_type" "$project"; then
            log_success "MIG [${name}] is stable."
            return 0
        fi

        printf '.' >&2
        sleep "$CHECK_INTERVAL"
        elapsed=$((elapsed + CHECK_INTERVAL))
    done

    echo "" >&2
    log_warning "Timed out waiting for MIG [${name}] to become stable (${timeout}s)."
    return 1
}

rolling_replace() {
    local name="$1"
    local location="$2"
    local location_type="$3"
    local project="$4"

    local location_flag
    location_flag="$(build_location_flag "$location" "$location_type")"

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "[DRY RUN] gcloud compute instance-groups managed rolling-action replace ${name} --max-unavailable=${MAX_UNAVAILABLE} --max-surge=${MAX_SURGE} ${location_flag} --project=${project}"
        return 0
    fi

    gcloud compute instance-groups managed rolling-action replace "$name" \
        --max-unavailable="$MAX_UNAVAILABLE" \
        --max-surge="$MAX_SURGE" \
        "$location_flag" \
        --project="$project" \
        >/dev/null

    log_success "Replace command submitted for MIG [${name}]."
}

process_instance_groups() {
    local groups_json="$1"
    local project="$2"

    mapfile -t groups < <(jq -c '.[]' <<<"$groups_json")
    local total="${#groups[@]}"

    local success=0
    local failed=0
    local -a failed_groups=()

    log_info "Starting processing for ${total} MIG(s)."

    local idx=0
    for group in "${groups[@]}"; do
        idx=$((idx + 1))

        local name
        local location
        local location_type

        name="$(jq -r '.name' <<<"$group")"
        if jq -e '.zone != null' >/dev/null 2>&1 <<<"$group"; then
            location="$(jq -r '.zone' <<<"$group")"
            location_type="zonal"
        else
            location="$(jq -r '.region' <<<"$group")"
            location_type="regional"
        fi

        log_step "[${idx}/${total}] Processing MIG: ${name} (${location_type}: ${location})"

        if [[ "$DRY_RUN" != true ]]; then
            if ! is_mig_stable "$name" "$location" "$location_type" "$project"; then
                log_warning "MIG [${name}] is not stable. Waiting before replace..."
                if ! wait_for_stable "$name" "$location" "$location_type" "$project" "$INITIAL_WAIT_TIMEOUT"; then
                    log_error "MIG [${name}] did not stabilize before replace."
                    failed=$((failed + 1))
                    failed_groups+=("$name")
                    if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                        break
                    fi
                    continue
                fi
            fi
        fi

        if rolling_replace "$name" "$location" "$location_type" "$project"; then
            if [[ "$DRY_RUN" != true ]]; then
                log_info "Waiting for replace to complete on MIG [${name}]..."
                if ! wait_for_stable "$name" "$location" "$location_type" "$project" "$REPLACE_WAIT_TIMEOUT"; then
                    log_warning "MIG [${name}] may still be converging. Verify manually."
                fi
            fi
            success=$((success + 1))
        else
            failed=$((failed + 1))
            failed_groups+=("$name")
            if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                break
            fi
        fi

        if (( idx < total )) && [[ "$DRY_RUN" != true ]]; then
            sleep "$BETWEEN_GROUPS_DELAY"
        fi
    done

    log_info "Summary: success=${success}, failed=${failed}, total=${total}"
    if (( failed > 0 )); then
        log_error "Failed MIGs: ${failed_groups[*]}"
        return 1
    fi
    return 0
}

parse_args() {
    while (($# > 0)); do
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
    [[ -n "$KEYWORD" ]] || { log_error "Missing --keyword"; exit 1; }

    require_integer "max-unavailable" "$MAX_UNAVAILABLE"
    require_integer "max-surge" "$MAX_SURGE"
    require_integer "initial-wait-timeout" "$INITIAL_WAIT_TIMEOUT"
    require_integer "replace-wait-timeout" "$REPLACE_WAIT_TIMEOUT"
    require_integer "between-groups-delay" "$BETWEEN_GROUPS_DELAY"
    require_integer "check-interval" "$CHECK_INTERVAL"

    if (( CHECK_INTERVAL == 0 )); then
        log_error "check-interval must be > 0"
        exit 1
    fi
}

main() {
    parse_args "$@"
    validate_args

    log_info "Config: project=${PROJECT_ID}, keyword=${KEYWORD}, max-unavailable=${MAX_UNAVAILABLE}, max-surge=${MAX_SURGE}, dry-run=${DRY_RUN}"

    check_prerequisites
    check_gcloud_auth
    check_project "$PROJECT_ID"

    local groups
    groups="$(get_instance_groups "$KEYWORD" "$PROJECT_ID")"
    display_instance_groups "$groups"

    local total
    total="$(jq 'length' <<<"$groups")"

    if [[ "$DRY_RUN" != true && "$AUTO_APPROVE" != true ]]; then
        log_warning "This will trigger rolling replacement on ${total} MIG(s)."
        printf "Type 'yes' to continue: " >&2
        local confirm
        read -r confirm
        [[ "$confirm" == "yes" ]] || {
            log_info "Canceled by user."
            exit 0
        }
    fi

    if process_instance_groups "$groups" "$PROJECT_ID"; then
        log_success "All requested MIGs processed."
    else
        log_error "Some MIGs failed. Check logs above."
        exit 1
    fi
}

main "$@"
