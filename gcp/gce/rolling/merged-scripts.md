# Shell Scripts Collection

Generated on: 2026-02-14 18:57:42
Directory: /Users/lex/git/knowledge/gcp/gce/rolling

## `rooling-mig-and-verify-status.sh`

```bash
#!/usr/bin/env bash
# rooling-mig-and-verify-status.sh
# Combined workflow: rolling replace MIGs, then verify MIG instance status.

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

get_instance_details() {
    local instance_name="$1"
    local zone="$2"
    local project="$3"

    if [[ -z "$zone" || -z "$instance_name" ]]; then
        return 1
    fi

    local result
    result="$(gcloud compute instances describe "${instance_name}" --zone="${zone}" --project="${project}" --format=json 2>/dev/null || true)"

    if [[ -z "$result" ]]; then
        return 1
    fi

    printf '%s\n' "$result"
}

verify_mig_instances() {
    local mig_name="$1"
    local location="$2"
    local location_type="$3"
    local project="$4"

    log_step "Verifying MIG: ${mig_name} (${location_type}: ${location})"

    local location_flag
    location_flag="$(build_location_flag "$location" "$location_type")"

    local mig_info
    mig_info="$(gcloud compute instance-groups managed describe "${mig_name}" "$location_flag" --project="$project" --format=json 2>/dev/null || true)"
    if [[ -z "$mig_info" ]]; then
        log_error "Failed to get MIG details for ${mig_name}"
        return 1
    fi

    local target_size
    target_size="$(jq -r '.targetSize // 0' <<<"$mig_info")"
    local current_actions
    current_actions="$(jq -c '.currentActions // {}' <<<"$mig_info")"
    local instance_template
    instance_template="$(jq -r '.instanceTemplate // "N/A"' <<<"$mig_info" | awk -F'/' '{print $NF}')"

    log_info "MIG config: targetSize=${target_size}, instanceTemplate=${instance_template}, currentActions=${current_actions}"

    local instances
    instances="$(gcloud compute instance-groups managed list-instances "${mig_name}" "$location_flag" --project="$project" --format=json 2>/dev/null || true)"

    if [[ -z "$instances" || "$instances" == "[]" ]]; then
        log_warning "No instances found in MIG [${mig_name}]"
        return 0
    fi

    local instance_count
    instance_count="$(jq 'length' <<<"$instances")"

    printf "%-35s %-15s %-15s %-25s %-30s\n" "INSTANCE_NAME" "ZONE" "STATUS" "CREATION_TIME" "INSTANCE_TEMPLATE" >&2
    printf "%-35s %-15s %-15s %-25s %-30s\n" "-----------------------------------" "---------------" "---------------" "-------------------------" "------------------------------" >&2

    local healthy_count=0
    local unhealthy_count=0
    local i

    for ((i=0; i<instance_count; i++)); do
        local instance_url
        instance_url="$(jq -r ".[${i}].instance" <<<"$instances")"
        local instance_name
        instance_name="$(awk -F'/' '{print $NF}' <<<"$instance_url")"

        local instance_zone
        instance_zone="$(sed -n 's/.*\/zones\/\([^\/]*\)\/instances\/.*/\1/p' <<<"$instance_url")"

        local instance_status
        instance_status="$(jq -r ".[${i}].instanceStatus // \"UNKNOWN\"" <<<"$instances")"

        local instance_details
        instance_details="$(get_instance_details "$instance_name" "$instance_zone" "$project" || true)"

        local creation_time_fmt="N/A"
        local instance_template_from_metadata="N/A"

        if [[ -n "$instance_details" ]]; then
            local creation_time
            creation_time="$(jq -r '.creationTimestamp // "N/A"' <<<"$instance_details")"
            if [[ "$creation_time" != "N/A" ]]; then
                creation_time_fmt="$(date -d "${creation_time}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "${creation_time:0:19}")"
            fi

            instance_template_from_metadata="$(jq -r '.metadata.items[]? | select(.key=="instance-template") | .value' <<<"$instance_details" 2>/dev/null | awk -F'/' '{print $NF}')"
            instance_template_from_metadata="${instance_template_from_metadata:-N/A}"
        fi

        local status_display="$instance_status"
        if [[ "$instance_status" == "RUNNING" ]]; then
            status_display="${GREEN}${instance_status}${NC}"
            healthy_count=$((healthy_count + 1))
        else
            status_display="${RED}${instance_status}${NC}"
            unhealthy_count=$((unhealthy_count + 1))
        fi

        printf "%-35s %-15s %-24b %-25s %-30s\n" \
            "${instance_name:0:35}" \
            "${instance_zone}" \
            "$status_display" \
            "${creation_time_fmt}" \
            "${instance_template_from_metadata}" >&2
    done

    log_info "Verification summary for ${mig_name}: total=${instance_count}, healthy=${healthy_count}, unhealthy=${unhealthy_count}"

    if (( unhealthy_count > 0 )); then
        log_warning "MIG [${mig_name}] has ${unhealthy_count} non-RUNNING instance(s)."
    else
        log_success "MIG [${mig_name}] verification passed (all RUNNING)."
    fi

    return 0
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
                    log_warning "MIG [${name}] may still be converging before verify."
                fi

                if ! verify_mig_instances "$name" "$location" "$location_type" "$project"; then
                    log_error "Verification failed for MIG [${name}]."
                    failed=$((failed + 1))
                    failed_groups+=("$name")
                    if [[ "$CONTINUE_ON_ERROR" != true ]]; then
                        break
                    fi
                    continue
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
        log_warning "This will trigger rolling replacement + verification on ${total} MIG(s)."
        printf "Type 'yes' to continue: " >&2
        local confirm
        read -r confirm
        [[ "$confirm" == "yes" ]] || {
            log_info "Canceled by user."
            exit 0
        }
    fi

    if process_instance_groups "$groups" "$PROJECT_ID"; then
        log_success "All requested MIGs processed and verified."
    else
        log_error "Some MIGs failed during replace or verify. Check logs above."
        exit 1
    fi
}

main "$@"

```

## `rolling-replace-mig-enhance-minimax.sh`

```bash
#!/usr/bin/env bash
# rolling-replace-mig-enhance-minimax.sh
# Enhanced rolling replace script for GCE Managed Instance Groups (MIGs).
# Version: 2.0.0 (MiniMax Enhanced)
# Enhanced with: verbose mode, health checks, zone filtering, retry logic, notifications, template backup

set -Eeuo pipefail

PROJECT_ID="${PROJECT_ID:-}"
KEYWORD="${KEYWORD:-}"
ZONE_FILTER="${ZONE_FILTER:-}"
REGION_FILTER="${REGION_FILTER:-}"
MAX_UNAVAILABLE="${MAX_UNAVAILABLE:-0}"
MAX_SURGE="${MAX_SURGE:-3}"
DRY_RUN=false
AUTO_APPROVE=false
CONTINUE_ON_ERROR=true
INITIAL_WAIT_TIMEOUT="${INITIAL_WAIT_TIMEOUT:-300}"
REPLACE_WAIT_TIMEOUT="${REPLACE_WAIT_TIMEOUT:-1800}"
BETWEEN_GROUPS_DELAY="${BETWEEN_GROUPS_DELAY:-30}"
CHECK_INTERVAL="${CHECK_INTERVAL:-15}"
VERBOSE=false
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_DELAY="${RETRY_DELAY:-60}"
HEALTH_CHECK_ENABLED=false
HEALTH_CHECK_URL="${HEALTH_CHECK_URL:-}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
BACKUP_TEMPLATES=true
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
LOG_FILE="${LOG_FILE:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { 
    local msg="${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo -e "$msg" >> "$LOG_FILE"
}
log_success() { 
    local msg="${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo -e "$msg" >> "$LOG_FILE"
}
log_warning() { 
    local msg="${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo -e "$msg" >> "$LOG_FILE"
}
log_error() { 
    local msg="${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo -e "$msg" >> "$LOG_FILE"
}
log_step() { 
    local msg="${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo -e "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo -e "$msg" >> "$LOG_FILE"
}
log_debug() { 
    if [[ "$VERBOSE" == true ]]; then
        local msg="${MAGENTA}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
        echo -e "$msg" >&2
        [[ -n "$LOG_FILE" ]] && echo -e "$msg" >> "$LOG_FILE"
    fi
}

on_error() {
    local line="$1"
    log_error "Unexpected failure at line ${line}."
    send_notification "ERROR" "Script failed at line ${line}"
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
  -z, --zone-filter ZONE            Filter by zone (e.g., us-central1-a)
  -r, --region-filter REGION        Filter by region (e.g., us-central1)
  -u, --max-unavailable NUM         Max unavailable instances (default: 0)
  -s, --max-surge NUM               Max surge instances (default: 3)
      --initial-wait-timeout SEC    Wait timeout before replace when MIG unstable (default: 300)
      --replace-wait-timeout SEC    Wait timeout after replace command (default: 1800)
      --check-interval SEC           Stability check interval (default: 15)
      --between-groups-delay SEC     Delay between MIGs (default: 30)
      --retry-count NUM              Number of retries on failure (default: 3)
      --retry-delay SEC              Delay between retries (default: 60)
      --health-check-url URL         HTTP health check URL for instances
      --health-check-timeout SEC     Health check timeout (default: 30)
      --no-backup-templates          Skip backing up instance templates
      --slack-webhook URL            Send notifications to Slack
      --log-file PATH                Log output to file
      --verbose                      Enable verbose output
      --continue-on-error            Continue processing next MIG on failure (default)
      --stop-on-error                Stop at first failed MIG
      --yes                          Skip confirmation prompt
      --dry-run                      Preview without executing replace
  -h, --help                        Show help

Examples:
  $0 --project my-project --keyword squid
  $0 -p my-project -k squid -u 1 -s 5 --yes
  $0 -p my-project -k '^web-' --dry-run
  $0 -p my-project -k 'app-' -z us-central1-a --verbose
  $0 -p my-project -k 'api-' --health-check-url http://localhost:8080/health
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

require_non_empty() {
    local name="$1"
    local value="$2"
    if [[ -z "$value" ]]; then
        log_error "Invalid ${name}: value cannot be empty."
        exit 1
    fi
}

check_prerequisites() {
    local missing=()
    for cmd in gcloud jq curl; do
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
    log_debug "Using gcloud authentication"
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
    local zone_filter="$3"
    local region_filter="$4"

    local filter="name~${keyword}"
    [[ -n "$zone_filter" ]] && filter="${filter} AND zone:${zone_filter}"
    [[ -n "$region_filter" ]] && filter="${filter} AND region:${region_filter}"

    log_debug "MIG filter: ${filter}"

    local groups
    if ! groups="$(gcloud compute instance-groups managed list \
        --project="$project" \
        --filter="$filter" \
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

get_instance_template() {
    local name="$1"
    local location="$2"
    local location_type="$3"
    local project="$4"

    local location_flag
    location_flag="$(build_location_flag "$location" "$location_type")"

    gcloud compute instance-groups managed describe "$name" \
        "$location_flag" \
        --project="$project" \
        --format='value(instanceTemplate)' 2>/dev/null
}

backup_instance_template() {
    local template_name="$1"
    local project="$2"
    local backup_suffix="backup-$(date +%Y%m%d-%H%M%S)"

    if [[ "$BACKUP_TEMPLATES" != true ]]; then
        log_debug "Template backup disabled, skipping"
        return 0
    fi

    log_info "Backing up instance template: ${template_name}"

    local template_json
    template_json="$(gcloud compute instance-templates describe "$template_name" --project="$project" --format=json 2>/dev/null)" || {
        log_warning "Failed to describe template ${template_name}"
        return 1
    }

    local backup_name="${template_name}-${backup_suffix}"
    
    echo "$template_json" | gcloud compute instance-templates create "$backup_name" \
        --project="$project" \
        --source-instance-template=- 2>/dev/null || {
        log_warning "Failed to create backup template ${backup_name}"
        return 1
    }

    log_success "Backup template created: ${backup_name}"
    return 0
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

check_instance_health() {
    local mig_name="$1"
    local location="$2"
    local location_type="$3"
    local project="$4"

    if [[ "$HEALTH_CHECK_ENABLED" != true ]] || [[ -z "$HEALTH_CHECK_URL" ]]; then
        log_debug "Health check disabled, skipping"
        return 0
    fi

    log_info "Checking health for MIG [${mig_name}] instances..."

    local instances
    instances="$(gcloud compute instance-groups managed list-instances "$mig_name" \
        --"${location_type}"="$location" \
        --project="$project" \
        --format='json(instances[].instance)' 2>/dev/null)" || {
        log_warning "Failed to list instances for MIG [${mig_name}]"
        return 1
    }

    local instance_ips
    instance_ips="$(echo "$instances" | jq -r '.[].instance | split("/") | last' 2>/dev/null | head -n1)" || {
        log_warning "Failed to parse instance names"
        return 1
    }

    if [[ -z "$instance_ips" ]]; then
        log_warning "No instances found for MIG [${mig_name}]"
        return 1
    fi

    local ip
    for ip in $instance_ips; do
        local health_url="http://${ip}${HEALTH_CHECK_URL#/}"
        log_debug "Checking health: ${health_url}"
        
        if curl -sf --connect-timeout 5 --max-time "$HEALTH_CHECK_TIMEOUT" "$health_url" >/dev/null 2>&1; then
            log_debug "Instance ${ip} is healthy"
        else
            log_warning "Instance ${ip} failed health check"
        fi
    done

    return 0
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

    local retry=0
    while (( retry < RETRY_COUNT )); do
        if gcloud compute instance-groups managed rolling-action replace "$name" \
            --max-unavailable="$MAX_UNAVAILABLE" \
            --max-surge="$MAX_SURGE" \
            "$location_flag" \
            --project="$project" \
            >/dev/null 2>&1; then
            log_success "Replace command submitted for MIG [${name}]."
            return 0
        fi

        retry=$((retry + 1))
        if (( retry < RETRY_COUNT )); then
            log_warning "Replace command failed for MIG [${name}], retrying in ${RETRY_DELAY}s (attempt ${retry}/${RETRY_COUNT})..."
            sleep "$RETRY_DELAY"
        fi
    done

    log_error "Failed to submit replace command for MIG [${name}] after ${RETRY_COUNT} attempts"
    return 1
}

send_notification() {
    local status="$1"
    local message="$2"

    if [[ -z "$SLACK_WEBHOOK" ]]; then
        log_debug "Slack webhook not configured, skipping notification"
        return 0
    fi

    local color
    case "$status" in
        SUCCESS) color="#36a64f" ;;
        ERROR) color="#ff0000" ;;
        WARNING) color="#ff9900" ;;
        *) color="#cccccc" ;;
    esac

    local payload
    payload="$(cat <<EOF
{
  "attachments": [{
    "color": "$color",
    "title": "GCE MIG Rolling Replace",
    "text": "$message",
    "footer": "Project: $PROJECT_ID",
    "ts": $(date +%s)
  }]
}
EOF
)"

    curl -s -X POST -H 'Content-Type: application/json' \
        -d "$payload" \
        "$SLACK_WEBHOOK" >/dev/null 2>&1 || {
        log_warning "Failed to send Slack notification"
    }
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
    send_notification "INFO" "Starting rolling replace for ${total} MIG(s) in project ${project}"

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

        # Backup instance template
        if [[ "$BACKUP_TEMPLATES" == true ]]; then
            local template
            template="$(get_instance_template "$name" "$location" "$location_type" "$project")"
            if [[ -n "$template" ]]; then
                backup_instance_template "$template" "$project" || {
                    log_warning "Failed to backup template for MIG [${name}], continuing..."
                }
            fi
        fi

        if [[ "$DRY_RUN" != true ]]; then
            if ! is_mig_stable "$name" "$location" "$location_type" "$project"; then
                log_warning "MIG [${name}] is not stable. Waiting before replace..."
                if ! wait_for_stable "$name" "$location" "$location_type" "$project" "$INITIAL_WAIT_TIMEOUT"; then
                    log_error "MIG [${name}] did not stabilize before replace."
                    failed=$((failed + 1))
                    failed_groups+=("$name")
                    send_notification "ERROR" "MIG [${name}] failed to stabilize"
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
                
                # Check instance health if enabled
                check_instance_health "$name" "$location" "$location_type" "$project"
            fi
            success=$((success + 1))
            send_notification "SUCCESS" "MIG [${name}] replaced successfully"
        else
            failed=$((failed + 1))
            failed_groups+=("$name")
            send_notification "ERROR" "MIG [${name}] replace failed"
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
            -z|--zone-filter)
                ZONE_FILTER="${2:-}"
                shift 2
                ;;
            -r|--region-filter)
                REGION_FILTER="${2:-}"
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
            --retry-count)
                RETRY_COUNT="${2:-}"
                shift 2
                ;;
            --retry-delay)
                RETRY_DELAY="${2:-}"
                shift 2
                ;;
            --health-check-url)
                HEALTH_CHECK_URL="${2:-}"
                HEALTH_CHECK_ENABLED=true
                shift 2
                ;;
            --health-check-timeout)
                HEALTH_CHECK_TIMEOUT="${2:-}"
                shift 2
                ;;
            --no-backup-templates)
                BACKUP_TEMPLATES=false
                shift
                ;;
            --slack-webhook)
                SLACK_WEBHOOK="${2:-}"
                shift 2
                ;;
            --log-file)
                LOG_FILE="${2:-}"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
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
    require_integer "retry-count" "$RETRY_COUNT"
    require_integer "retry-delay" "$RETRY_DELAY"
    require_integer "health-check-timeout" "$HEALTH_CHECK_TIMEOUT"

    if (( CHECK_INTERVAL == 0 )); then
        log_error "check-interval must be > 0"
        exit 1
    fi

    if [[ "$HEALTH_CHECK_ENABLED" == true ]] && [[ -z "$HEALTH_CHECK_URL" ]]; then
        log_error "health-check-url is required when health check is enabled"
        exit 1
    fi

    # Create log file if specified
    if [[ -n "$LOG_FILE" ]]; then
        touch "$LOG_FILE" || {
            log_error "Cannot create log file: ${LOG_FILE}"
            exit 1
        }
        log_info "Logging to file: ${LOG_FILE}"
    fi
}

main() {
    parse_args "$@"
    validate_args

    log_info "=============================================="
    log_info "GCE MIG Rolling Replace - Enhanced Edition"
    log_info "=============================================="
    log_info "Config: project=${PROJECT_ID}, keyword=${KEYWORD}"
    log_info "Config: max-unavailable=${MAX_UNAVAILABLE}, max-surge=${MAX_SURGE}"
    log_info "Config: dry-run=${DRY_RUN}, verbose=${VERBOSE}"
    [[ -n "$ZONE_FILTER" ]] && log_info "Config: zone-filter=${ZONE_FILTER}"
    [[ -n "$REGION_FILTER" ]] && log_info "Config: region-filter=${REGION_FILTER}"
    log_info "=============================================="

    check_prerequisites
    check_gcloud_auth
    check_project "$PROJECT_ID"

    local groups
    groups="$(get_instance_groups "$KEYWORD" "$PROJECT_ID" "$ZONE_FILTER" "$REGION_FILTER")"
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
        send_notification "SUCCESS" "All MIGs processed successfully"
    else
        log_error "Some MIGs failed. Check logs above."
        send_notification "ERROR" "Some MIGs failed to process"
        exit 1
    fi
}

main "$@"

```

## `rolling-replace-mig-enhance.sh`

```bash
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

```

## `rolling-replace-instance-groups-eng.sh`

```bash
#!/bin/bash
# rolling-replace-instance-groups.sh
# Rolling replacement script for MIG instance groups matching keywords
# this script running success the core command eg
#    gcloud compute instance-groups managed rolling-action replace "$name" \
#        --max-unavailable=0 \
#        --max-surge=3 \
#        --region=https://www.googleapis.com/compute/v1/projct/projectid/region/europe-west2 \
#        --project="$project"

set -e

# ============================================
# Configuration Section
# ============================================
PROJECT_ID="${PROJECT_ID:-}"
KEYWORD="${KEYWORD:-}"

# Rolling replacement configuration
MAX_UNAVAILABLE="${MAX_UNAVAILABLE:-0}"    # Do not allow unavailable instances
MAX_SURGE="${MAX_SURGE:-3}"                # Maximum number of instances exceeding target count

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# Helper Functions
# ============================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

# Display usage instructions
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Rolling replacement of MIG instance groups matching keywords

Options:
    -p, --project PROJECT_ID        GCP Project ID (Required)
    -k, --keyword KEYWORD           Instance group name keyword (Required)
    -u, --max-unavailable NUM       Maximum unavailable instances (Default: 0)
    -s, --max-surge NUM             Maximum surge instances (Default: 3)
    --dry-run                       Simulate run without actual execution
    -h, --help                      Show this help message

Examples:
    # Replace all instance groups containing "squid" in name
    $0 --project my-project --keyword squid

    # Customize rolling replacement parameters
    $0 -p my-project -k squid -u 1 -s 5

    # Simulate run
    $0 --project my-project --keyword squid --dry-run

Description:
    --max-unavailable: Maximum number of unavailable instances allowed during rolling replacement
                       Set to 0 to ensure high availability

    --max-surge:       Maximum number of instances exceeding target count during rolling replacement
                       Set to 3 means 3 additional instances can be temporarily added

EOF
    exit 0
}

# Check required commands
check_prerequisites() {
    log_info "Checking required commands..."

    local missing_commands=()

    for cmd in gcloud jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_error "Please install missing commands and retry"
        exit 1
    fi

    log_success "All required commands are installed"
}

# Verify gcloud authentication
check_gcloud_auth() {
    log_info "Verifying gcloud authentication status..."

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "No active gcloud authentication detected"
        log_error "Please run: gcloud auth login"
        exit 1
    fi

    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)
    log_success "Authenticated account: $active_account"
}

# Verify project exists
check_project() {
    local project=$1
    log_info "Verifying project [$project] exists..."

    if ! gcloud projects describe "$project" &> /dev/null; then
        log_error "Project [$project] does not exist or access denied"
        exit 1
    fi

    log_success "Project [$project] validation passed"
}

# Get list of instance groups matching keyword
get_instance_groups() {
    local keyword=$1
    local project=$2

    log_info "Finding instance groups containing [$keyword]..."

    local instance_groups
    instance_groups=$(gcloud compute instance-groups managed list \
        --project="$project" \
        --filter="name~$keyword" \
        --format="json" 2>&1)

    # Check if command executed successfully
    if [ $? -ne 0 ]; then
        log_error "Failed to get instance group list"
        log_error "$instance_groups"
        exit 1
    fi

    # Verify returned data is valid JSON
    if ! echo "$instance_groups" | jq empty 2>/dev/null; then
        log_error "Returned data is not valid JSON format"
        log_error "Original output: $instance_groups"
        exit 1
    fi

    if [ -z "$instance_groups" ] || [ "$instance_groups" = "[]" ]; then
        log_error "No instance groups found matching keyword [$keyword]"
        exit 1
    fi

    echo "$instance_groups"
}

# Display instance group information
display_instance_groups() {
    local instance_groups=$1

    # Verify JSON format again
    if ! echo "$instance_groups" | jq empty 2>/dev/null; then
        log_error "display_instance_groups: Received data is not valid JSON"
        return 1
    fi

    log_info "Found the following instance groups:"
    echo "" >&2
    echo "--------------------------------------------------------------------------------------------------------" >&2
    printf "%-40s %-20s %-15s %-10s\n" "Name" "Location" "Type" "Instance Count" >&2
    echo "--------------------------------------------------------------------------------------------------------" >&2

    echo "$instance_groups" | jq -r '.[] | "\(.name)|\(.zone // .region)|\(if .zone then "zonal" else "regional" end)|\(.targetSize)"' | \
    while IFS='|' read -r name location type size; do
        printf "%-40s %-20s %-15s %-10s\n" "$name" "$location" "$type" "$size" >&2
    done

    echo "--------------------------------------------------------------------------------------------------------" >&2
    echo "" >&2
}

# Get current status of instance group
get_instance_group_status() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4

    local location_flag
    if [ "$location_type" = "zonal" ]; then
        location_flag="--zone=$location"
    else
        location_flag="--region=$location"
    fi

    gcloud compute instance-groups managed describe "$name" \
        $location_flag \
        --project="$project" \
        --format="json" 2>/dev/null
}

# Check if instance group is stable
check_instance_group_stable() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4

    local status
    status=$(get_instance_group_status "$name" "$location" "$location_type" "$project")

    local is_stable
    is_stable=$(echo "$status" | jq -r '.status.isStable // false')

    if [ "$is_stable" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# Wait for instance group to become stable
wait_for_stable() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4
    local max_wait=${5:-600}  # Default maximum wait 10 minutes

    log_info "Waiting for instance group [$name] to stabilize..."

    local elapsed=0
    local check_interval=15

    while [ $elapsed -lt $max_wait ]; do
        if check_instance_group_stable "$name" "$location" "$location_type" "$project"; then
            log_success "Instance group [$name] is stable"
            return 0
        fi

        echo -n "."
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    echo ""
    log_warning "Instance group [$name] stability check timed out (${max_wait}s)"
    return 1
}

# Perform rolling replacement
rolling_replace() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4
    local max_unavailable=$5
    local max_surge=$6
    local dry_run=$7

    log_step "Starting rolling replacement for instance group: $name"

    local location_flag
    if [ "$location_type" = "zonal" ]; then
        location_flag="--zone=$location"
    else
        location_flag="--region=$location"
    fi

    if [ "$dry_run" = "true" ]; then
        log_warning "[DRY RUN] Simulating rolling replacement:"
        log_warning "  Instance group: $name"
        log_warning "  Location: $location ($location_type)"
        log_warning "  max-unavailable: $max_unavailable"
        log_warning "  max-surge: $max_surge"
        return 0
    fi

    # Execute rolling replacement
    log_info "Executing command: gcloud compute instance-groups managed rolling-action replace $name"
    log_info "  Parameters: --max-unavailable=$max_unavailable --max-surge=$max_surge"

    if gcloud compute instance-groups managed rolling-action replace "$name" \
        --max-unavailable="$max_unavailable" \
        --max-surge="$max_surge" \
        $location_flag \
        --project="$project" 2>&1 >&2; then

        log_success "Instance group [$name] rolling replacement command submitted"
        return 0
    else
        log_error "Instance group [$name] rolling replacement failed"
        return 1
    fi
}

# Process all instance groups
process_instance_groups() {
    local instance_groups=$1
    local project=$2
    local max_unavailable=$3
    local max_surge=$4
    local dry_run=$5

    local total
    total=$(echo "$instance_groups" | jq '. | length')
    local current=0
    local success=0
    local failed=0
    local failed_groups=()

    log_info "========================================="
    log_info "Starting processing of $total instance groups"
    log_info "========================================="

    echo "$instance_groups" | jq -c '.[]' | while read -r group; do
        current=$((current + 1))

        local name
        local location
        local location_type

        name=$(echo "$group" | jq -r '.name')

        # Determine if zonal or regional
        if echo "$group" | jq -e '.zone' > /dev/null 2>&1; then
            location=$(echo "$group" | jq -r '.zone')
            location_type="zonal"
        else
            location=$(echo "$group" | jq -r '.region')
            location_type="regional"
        fi

        log_info ""
        log_info "========================================="
        log_info "[$current/$total] Processing instance group: $name"
        log_info "Location: $location ($location_type)"
        log_info "========================================="

        # Check initial status
        if [ "$dry_run" != "true" ]; then
            if ! check_instance_group_stable "$name" "$location" "$location_type" "$project"; then
                log_warning "Instance group [$name] is currently unstable, waiting for stability before proceeding..."
                if ! wait_for_stable "$name" "$location" "$location_type" "$project" 300; then
                    log_error "Instance group [$name] initial status is unstable, skipping"
                    failed=$((failed + 1))
                    failed_groups+=("$name")
                    continue
                fi
            fi
        fi

        # Execute rolling replacement
        if rolling_replace "$name" "$location" "$location_type" "$project" \
            "$max_unavailable" "$max_surge" "$dry_run"; then

            # Wait for operation to complete
            if [ "$dry_run" != "true" ]; then
                log_info "Waiting for rolling replacement to complete..."
                if wait_for_stable "$name" "$location" "$location_type" "$project" 1800; then
                    success=$((success + 1))
                    log_success "Instance group [$name] rolling replacement completed"
                else
                    log_warning "Instance group [$name] rolling replacement may still be in progress"
                    log_warning "Please check status manually"
                    success=$((success + 1))
                fi
            else
                success=$((success + 1))
            fi
        else
            failed=$((failed + 1))
            failed_groups+=("$name")
        fi

        # Wait before processing next instance group
        if [ $current -lt $total ] && [ "$dry_run" != "true" ]; then
            log_info "Waiting 30 seconds before processing next instance group..."
            sleep 30
        fi
    done

    # Output summary
    log_info ""
    log_info "========================================="
    log_info "Processing completed"
    log_info "========================================="
    log_success "Success: $success instance groups"

    if [ $failed -gt 0 ]; then
        log_error "Failed: $failed instance groups"
        log_error "Failed list: ${failed_groups[*]}"
        return 1
    fi

    return 0
}

# ============================================
# Main Program
# ============================================

main() {
    local DRY_RUN=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -k|--keyword)
                KEYWORD="$2"
                shift 2
                ;;
            -u|--max-unavailable)
                MAX_UNAVAILABLE="$2"
                shift 2
                ;;
            -s|--max-surge)
                MAX_SURGE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                log_error "Unknown parameter: $1"
                show_usage
                ;;
        esac
    done

    # Validate required parameters
    if [ -z "$PROJECT_ID" ]; then
        log_error "Missing required parameter: --project"
        show_usage
    fi

    if [ -z "$KEYWORD" ]; then
        log_error "Missing required parameter: --keyword"
        show_usage
    fi

    # Display configuration
    log_info "========================================="
    log_info "Configuration Information"
    log_info "========================================="
    log_info "Project ID: $PROJECT_ID"
    log_info "Keyword: $KEYWORD"
    log_info "Max Unavailable: $MAX_UNAVAILABLE"
    log_info "Max Surge: $MAX_SURGE"
    [ "$DRY_RUN" = "true" ] && log_warning "Mode: DRY RUN (Simulated run)"
    log_info "========================================="
    echo "" >&2

    # Check prerequisites
    check_prerequisites
    check_gcloud_auth
    check_project "$PROJECT_ID"

    # Get instance group list
    local instance_groups
    instance_groups=$(get_instance_groups "$KEYWORD" "$PROJECT_ID")

    # Display instance group information
    display_instance_groups "$instance_groups"

    # Confirm operation
    if [ "$DRY_RUN" != "true" ]; then
        local total
        total=$(echo "$instance_groups" | jq '. | length')

        log_warning ""
        log_warning "⚠️  Warning: This operation will perform rolling replacement on $total instance groups"
        log_warning "⚠️  All instances will be gradually replaced with new instances"
        log_warning ""
        echo -n "Confirm to continue? (Enter 'yes' to confirm): " >&2
        read CONFIRM

        if [ "$CONFIRM" != "yes" ]; then
            log_info "Operation cancelled"
            exit 0
        fi
    fi

    # Process all instance groups
    if process_instance_groups "$instance_groups" "$PROJECT_ID" \
        "$MAX_UNAVAILABLE" "$MAX_SURGE" "$DRY_RUN"; then

        log_success ""
        log_success "========================================="
        log_success "All instance groups processed!"
        log_success "========================================="
        exit 0
    else
        log_error ""
        log_error "========================================="
        log_error "Some instance groups processing failed, please check logs"
        log_error "========================================="
        exit 1
    fi
}

# Execute main program
main "$@"
```

## `rolling-replace-instance-groups.sh`

```bash
#!/bin/bash
# rolling-replace-instance-groups.sh
# 滚动替换匹配关键字的 MIG 实例组脚本
# this script running success the core command eg
#    gcloud compute instance-groups managed rolling-action replace "$name" \
#        --max-unavailable=0 \
#        --max-surge=3 \
#        --region=https://www.googleapis.com/compute/v1/projct/projectid/region/europe-west2 \
#        --project="$project"
         
set -e

# ============================================
# 配置区域
# ============================================
PROJECT_ID="${PROJECT_ID:-}"
KEYWORD="${KEYWORD:-}"

# 滚动替换配置
MAX_UNAVAILABLE="${MAX_UNAVAILABLE:-0}"    # 不允许不可用的实例
MAX_SURGE="${MAX_SURGE:-3}"                # 允许超出目标数的实例数

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# 辅助函数
# ============================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

# 显示使用说明
show_usage() {
    cat << EOF
用法: $0 [选项]

滚动替换匹配关键字的 MIG 实例组

选项:
    -p, --project PROJECT_ID        GCP 项目 ID (必需)
    -k, --keyword KEYWORD           实例组名称关键字 (必需)
    -u, --max-unavailable NUM       最大不可用实例数 (默认: 0)
    -s, --max-surge NUM             最大超出实例数 (默认: 3)
    --dry-run                       模拟运行，不实际执行
    -h, --help                      显示此帮助信息

示例:
    # 替换名称包含 "squid" 的所有实例组
    $0 --project my-project --keyword squid

    # 自定义滚动替换参数
    $0 -p my-project -k squid -u 1 -s 5

    # 模拟运行
    $0 --project my-project --keyword squid --dry-run

说明:
    --max-unavailable: 滚动替换期间允许不可用的最大实例数
                       设置为 0 确保高可用性
    
    --max-surge:       滚动替换期间允许超出目标数的最大实例数
                       设置为 3 表示可以临时增加 3 个实例

EOF
    exit 0
}

# 检查必要的命令
check_prerequisites() {
    log_info "检查必要的命令..."
    
    local missing_commands=()
    
    for cmd in gcloud jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "缺少必要的命令: ${missing_commands[*]}"
        log_error "请安装缺失的命令后重试"
        exit 1
    fi
    
    log_success "所有必要命令已安装"
}

# 验证 gcloud 认证
check_gcloud_auth() {
    log_info "验证 gcloud 认证状态..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "未检测到活动的 gcloud 认证"
        log_error "请运行: gcloud auth login"
        exit 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)
    log_success "已认证账户: $active_account"
}

# 验证项目存在
check_project() {
    local project=$1
    log_info "验证项目 [$project] 是否存在..."
    
    if ! gcloud projects describe "$project" &> /dev/null; then
        log_error "项目 [$project] 不存在或无权访问"
        exit 1
    fi
    
    log_success "项目 [$project] 验证通过"
}

# 获取匹配关键字的实例组列表
get_instance_groups() {
    local keyword=$1
    local project=$2
    
    log_info "查找名称包含 [$keyword] 的实例组..."
    
    local instance_groups
    instance_groups=$(gcloud compute instance-groups managed list \
        --project="$project" \
        --filter="name~$keyword" \
        --format="json" 2>&1)
    
    # 检查命令是否执行成功
    if [ $? -ne 0 ]; then
        log_error "获取实例组列表失败"
        log_error "$instance_groups"
        exit 1
    fi
    
    # 验证返回的是有效的 JSON
    if ! echo "$instance_groups" | jq empty 2>/dev/null; then
        log_error "返回的数据不是有效的 JSON 格式"
        log_error "原始输出: $instance_groups"
        exit 1
    fi
    
    if [ -z "$instance_groups" ] || [ "$instance_groups" = "[]" ]; then
        log_error "未找到匹配关键字 [$keyword] 的实例组"
        exit 1
    fi
    
    echo "$instance_groups"
}

# 显示实例组信息
display_instance_groups() {
    local instance_groups=$1
    
    # 再次验证 JSON 格式
    if ! echo "$instance_groups" | jq empty 2>/dev/null; then
        log_error "display_instance_groups: 接收到的数据不是有效的 JSON"
        return 1
    fi
    
    log_info "找到以下实例组:"
    echo "" >&2
    echo "--------------------------------------------------------------------------------------------------------" >&2
    printf "%-40s %-20s %-15s %-10s\n" "名称" "位置" "类型" "实例数" >&2
    echo "--------------------------------------------------------------------------------------------------------" >&2
    
    echo "$instance_groups" | jq -r '.[] | "\(.name)|\(.zone // .region)|\(if .zone then "zonal" else "regional" end)|\(.targetSize)"' | \
    while IFS='|' read -r name location type size; do
        printf "%-40s %-20s %-15s %-10s\n" "$name" "$location" "$type" "$size" >&2
    done
    
    echo "--------------------------------------------------------------------------------------------------------" >&2
    echo "" >&2
}

# 获取实例组当前状态
get_instance_group_status() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4
    
    local location_flag
    if [ "$location_type" = "zonal" ]; then
        location_flag="--zone=$location"
    else
        location_flag="--region=$location"
    fi
    
    gcloud compute instance-groups managed describe "$name" \
        $location_flag \
        --project="$project" \
        --format="json" 2>/dev/null
}

# 检查实例组是否稳定
check_instance_group_stable() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4
    
    local status
    status=$(get_instance_group_status "$name" "$location" "$location_type" "$project")
    
    local is_stable
    is_stable=$(echo "$status" | jq -r '.status.isStable // false')
    
    if [ "$is_stable" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# 等待实例组稳定
wait_for_stable() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4
    local max_wait=${5:-600}  # 默认最多等待 10 分钟
    
    log_info "等待实例组 [$name] 稳定..."
    
    local elapsed=0
    local check_interval=15
    
    while [ $elapsed -lt $max_wait ]; do
        if check_instance_group_stable "$name" "$location" "$location_type" "$project"; then
            log_success "实例组 [$name] 已稳定"
            return 0
        fi
        
        echo -n "."
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    echo ""
    log_warning "实例组 [$name] 稳定检查超时 (${max_wait}s)"
    return 1
}

# 执行滚动替换
rolling_replace() {
    local name=$1
    local location=$2
    local location_type=$3
    local project=$4
    local max_unavailable=$5
    local max_surge=$6
    local dry_run=$7
    
    log_step "开始滚动替换实例组: $name"
    
    local location_flag
    if [ "$location_type" = "zonal" ]; then
        location_flag="--zone=$location"
    else
        location_flag="--region=$location"
    fi
    
    if [ "$dry_run" = "true" ]; then
        log_warning "[DRY RUN] 模拟执行滚动替换:"
        log_warning "  实例组: $name"
        log_warning "  位置: $location ($location_type)"
        log_warning "  max-unavailable: $max_unavailable"
        log_warning "  max-surge: $max_surge"
        return 0
    fi
    
    # 执行滚动替换
    log_info "执行命令: gcloud compute instance-groups managed rolling-action replace $name"
    log_info "  参数: --max-unavailable=$max_unavailable --max-surge=$max_surge"
    
    if gcloud compute instance-groups managed rolling-action replace "$name" \
        --max-unavailable="$max_unavailable" \
        --max-surge="$max_surge" \
        $location_flag \
        --project="$project" 2>&1 >&2; then
        
        log_success "实例组 [$name] 滚动替换命令已提交"
        return 0
    else
        log_error "实例组 [$name] 滚动替换失败"
        return 1
    fi
}

# 处理所有实例组
process_instance_groups() {
    local instance_groups=$1
    local project=$2
    local max_unavailable=$3
    local max_surge=$4
    local dry_run=$5
    
    local total
    total=$(echo "$instance_groups" | jq '. | length')
    local current=0
    local success=0
    local failed=0
    local failed_groups=()
    
    log_info "========================================="
    log_info "开始处理 $total 个实例组"
    log_info "========================================="
    
    echo "$instance_groups" | jq -c '.[]' | while read -r group; do
        current=$((current + 1))
        
        local name
        local location
        local location_type
        
        name=$(echo "$group" | jq -r '.name')
        
        # 判断是 zonal 还是 regional
        if echo "$group" | jq -e '.zone' > /dev/null 2>&1; then
            location=$(echo "$group" | jq -r '.zone')
            location_type="zonal"
        else
            location=$(echo "$group" | jq -r '.region')
            location_type="regional"
        fi
        
        log_info ""
        log_info "========================================="
        log_info "[$current/$total] 处理实例组: $name"
        log_info "位置: $location ($location_type)"
        log_info "========================================="
        
        # 检查初始状态
        if [ "$dry_run" != "true" ]; then
            if ! check_instance_group_stable "$name" "$location" "$location_type" "$project"; then
                log_warning "实例组 [$name] 当前不稳定，等待稳定后再操作..."
                if ! wait_for_stable "$name" "$location" "$location_type" "$project" 300; then
                    log_error "实例组 [$name] 初始状态不稳定，跳过"
                    failed=$((failed + 1))
                    failed_groups+=("$name")
                    continue
                fi
            fi
        fi
        
        # 执行滚动替换
        if rolling_replace "$name" "$location" "$location_type" "$project" \
            "$max_unavailable" "$max_surge" "$dry_run"; then
            
            # 等待操作完成
            if [ "$dry_run" != "true" ]; then
                log_info "等待滚动替换完成..."
                if wait_for_stable "$name" "$location" "$location_type" "$project" 1800; then
                    success=$((success + 1))
                    log_success "实例组 [$name] 滚动替换完成"
                else
                    log_warning "实例组 [$name] 滚动替换可能仍在进行中"
                    log_warning "请手动检查状态"
                    success=$((success + 1))
                fi
            else
                success=$((success + 1))
            fi
        else
            failed=$((failed + 1))
            failed_groups+=("$name")
        fi
        
        # 在处理下一个实例组前稍作等待
        if [ $current -lt $total ] && [ "$dry_run" != "true" ]; then
            log_info "等待 30 秒后处理下一个实例组..."
            sleep 30
        fi
    done
    
    # 输出总结
    log_info ""
    log_info "========================================="
    log_info "处理完成"
    log_info "========================================="
    log_success "成功: $success 个实例组"
    
    if [ $failed -gt 0 ]; then
        log_error "失败: $failed 个实例组"
        log_error "失败列表: ${failed_groups[*]}"
        return 1
    fi
    
    return 0
}

# ============================================
# 主程序
# ============================================

main() {
    local DRY_RUN=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -k|--keyword)
                KEYWORD="$2"
                shift 2
                ;;
            -u|--max-unavailable)
                MAX_UNAVAILABLE="$2"
                shift 2
                ;;
            -s|--max-surge)
                MAX_SURGE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                ;;
        esac
    done
    
    # 验证必需参数
    if [ -z "$PROJECT_ID" ]; then
        log_error "缺少必需参数: --project"
        show_usage
    fi
    
    if [ -z "$KEYWORD" ]; then
        log_error "缺少必需参数: --keyword"
        show_usage
    fi
    
    # 显示配置
    log_info "========================================="
    log_info "配置信息"
    log_info "========================================="
    log_info "项目 ID: $PROJECT_ID"
    log_info "关键字: $KEYWORD"
    log_info "最大不可用: $MAX_UNAVAILABLE"
    log_info "最大超出: $MAX_SURGE"
    [ "$DRY_RUN" = "true" ] && log_warning "模式: DRY RUN (模拟运行)"
    log_info "========================================="
    echo "" >&2
    
    # 检查前置条件
    check_prerequisites
    check_gcloud_auth
    check_project "$PROJECT_ID"
    
    # 获取实例组列表
    local instance_groups
    instance_groups=$(get_instance_groups "$KEYWORD" "$PROJECT_ID")
    
    # 显示实例组信息
    display_instance_groups "$instance_groups"
    
    # 确认操作
    if [ "$DRY_RUN" != "true" ]; then
        local total
        total=$(echo "$instance_groups" | jq '. | length')
        
        log_warning ""
        log_warning "⚠️  警告: 此操作将对 $total 个实例组执行滚动替换"
        log_warning "⚠️  所有实例将被逐步替换为新实例"
        log_warning ""
        echo -n "确认继续? (输入 'yes' 确认): " >&2
        read CONFIRM
        
        if [ "$CONFIRM" != "yes" ]; then
            log_info "操作已取消"
            exit 0
        fi
    fi
    
    # 处理所有实例组
    if process_instance_groups "$instance_groups" "$PROJECT_ID" \
        "$MAX_UNAVAILABLE" "$MAX_SURGE" "$DRY_RUN"; then
        
        log_success ""
        log_success "========================================="
        log_success "所有实例组处理完成！"
        log_success "========================================="
        exit 0
    else
        log_error ""
        log_error "========================================="
        log_error "部分实例组处理失败，请检查日志"
        log_error "========================================="
        exit 1
    fi
}

# 执行主程序
main "$@"

```

## `verify-mig-status.sh`

```bash
#!/bin/bash

# verify-mig-status.sh - Verify MIG instances status after refresh/replace
# Author: Infrastructure Team
# Version: 1.2 (Linux Hardened - Fixed JQ Parse Error)

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Function: Usage ---
show_usage() {
    echo -e "${BLUE}Usage:${NC} $0 <mig-keyword>"
    echo -e "${BLUE}Example:${NC} $0 'web-server'"
    echo ""
    echo -e "${BLUE}Description:${NC}"
    echo "  Verify MIG instances status including creation time, health status, etc."
    exit 1
}

# --- Function: Check prerequisites ---
check_prerequisites() {
    local missing_deps=0
    
    if ! command -v gcloud &> /dev/null; then
        echo -e "${RED}Error: gcloud CLI not found. Please install Google Cloud SDK.${NC}"
        missing_deps=1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq not found. Please install jq (e.g., sudo apt-get install jq).${NC}"
        missing_deps=1
    fi

    if [ $missing_deps -ne 0 ]; then
        exit 1
    fi
}

# --- Function: Get MIG list by keyword ---
get_mig_list() {
    local keyword=$1
    # CRITICAL: Send status messages to stderr so they don't pollute the data stream (stdout)
    echo -e "${BLUE}Searching for MIGs matching keyword: ${keyword}${NC}" >&2
    echo "" >&2
    
    local json_data
    # Unified call for both zonal and regional MIGs
    json_data=$(gcloud compute instance-groups managed list --filter="name:${keyword}" --format=json 2>/dev/null)
    
    if [ -z "$json_data" ] || [ "$json_data" == "[]" ]; then
        echo -e "${RED}Error: No MIG found matching keyword '${keyword}'${NC}" >&2
        exit 1
    fi
    
    # Extract name and location (handles both .zone and .region fields)
    echo "$json_data" | jq -r '.[] | .name + " " + (.zone // .region | split("/") | last)'
}

# --- Function: Get instance details safely ---
# ... (rest of the functions remain the same)

# --- Function: Get instance details safely ---
get_instance_details() {
    local instance_name=$1
    local zone=$2
    
    if [ -z "$zone" ] || [ -z "$instance_name" ]; then
        return 1
    fi

    local result
    # CRITICAL: Separate assignment from local to catch exit code.
    # CRITICAL: Do NOT redirect 2>&1 into JSON variable because warnings/errors break jq.
    result=$(gcloud compute instances describe "${instance_name}" --zone="${zone}" --format=json 2>/dev/null)
    local exit_val=$?
    
    if [ $exit_val -ne 0 ] || [ -z "$result" ]; then
        # If it failed, check why (let stderr flow for info if wanted, or just return 1)
        return 1
    fi
    
    echo "$result"
}

# --- Function: Verify MIG instances ---
verify_mig_instances() {
    local mig_name=$1
    local location=$2
    local location_type=$3
    
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}Verifying MIG: ${mig_name}${NC}"
    echo -e "${GREEN}Location: ${location} (${location_type})${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    
    local mig_info
    if [ "$location_type" == "zone" ]; then
        mig_info=$(gcloud compute instance-groups managed describe "${mig_name}" --zone="${location}" --format=json 2>/dev/null)
    else
        mig_info=$(gcloud compute instance-groups managed describe "${mig_name}" --region="${location}" --format=json 2>/dev/null)
    fi
    
    if [ $? -ne 0 ] || [ -z "$mig_info" ]; then
        echo -e "${RED}Error: Failed to get MIG details for ${mig_name}${NC}"
        return 1
    fi
    
    local target_size
    target_size=$(echo "$mig_info" | jq -r '.targetSize // 0')
    local current_actions
    current_actions=$(echo "$mig_info" | jq -r '.currentActions // {}')
    local instance_template
    instance_template=$(echo "$mig_info" | jq -r '.instanceTemplate' | awk -F'/' '{print $NF}')
    
    echo -e "${BLUE}MIG Configuration:${NC}"
    echo "  Target Size: ${target_size}"
    echo "  Instance Template: ${instance_template}"
    echo "  Current Actions:"
    echo "$current_actions" | jq '.'
    echo ""
    
    local instances
    if [ "$location_type" == "zone" ]; then
        instances=$(gcloud compute instance-groups managed list-instances "${mig_name}" --zone="${location}" --format=json 2>/dev/null)
    else
        instances=$(gcloud compute instance-groups managed list-instances "${mig_name}" --region="${location}" --format=json 2>/dev/null)
    fi
    
    if [ -z "$instances" ] || [ "$instances" == "[]" ]; then
        echo -e "${YELLOW}Warning: No instances found in this MIG${NC}"
        return 0
    fi
    
    local instance_count
    instance_count=$(echo "$instances" | jq '. | length')
    echo -e "${BLUE}Found ${instance_count} instances:${NC}"
    echo ""
    
    printf "%-35s %-15s %-15s %-25s %-30s\n" "INSTANCE_NAME" "ZONE" "STATUS" "CREATION_TIME" "INSTANCE_TEMPLATE"
    printf "%-35s %-15s %-15s %-25s %-30s\n" "-----------------------------------" "---------------" "---------------" "-------------------------" "------------------------------"
    
    local healthy_count=0
    local unhealthy_count=0
    
    for i in $(seq 0 $((instance_count - 1))); do
        local instance_url
        instance_url=$(echo "$instances" | jq -r ".[${i}].instance")
        local instance_name
        instance_name=$(echo "$instance_url" | awk -F'/' '{print $NF}')
        
        local instance_zone
        instance_zone=$(echo "$instance_url" | sed -n 's/.*\/zones\/\([^\/]*\)\/instances\/.*/\1/p')
        
        local instance_status
        instance_status=$(echo "$instances" | jq -r ".[${i}].instanceStatus")
        local current_action
        current_action=$(echo "$instances" | jq -r ".[${i}].currentAction // \"NONE\"")
        
        local instance_details
        instance_details=$(get_instance_details "$instance_name" "$instance_zone")
        
        if [ -z "$instance_details" ]; then
            printf "%-35s %-15s %-15s %-25s %-30s\n" "$instance_name" "${instance_zone}" "UNKNOWN" "N/A" "N/A"
            ((unhealthy_count++))
            continue
        fi
        
        local creation_time
        creation_time=$(echo "$instance_details" | jq -r '.creationTimestamp // "N/A"')
        
        # GNU date compatibility for Linux
        local creation_time_fmt
        if [[ "$creation_time" != "N/A" ]]; then
            creation_time_fmt=$(date -d "${creation_time}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "${creation_time:0:19}")
        else
            creation_time_fmt="N/A"
        fi

        local instance_template_from_metadata
        instance_template_from_metadata=$(echo "$instance_details" | jq -r '.metadata.items[]? | select(.key=="instance-template") | .value' 2>/dev/null | awk -F'/' '{print $NF}')
        
        local status_display="$instance_status"
        if [ "$instance_status" == "RUNNING" ]; then
            status_display="${GREEN}${instance_status}${NC}"
            ((healthy_count++))
        else
            status_display="${RED}${instance_status}${NC}"
            ((unhealthy_count++))
        fi
        
        printf "%-35s %-15s %-24b %-25s %-30s\n" \
            "${instance_name:0:35}" \
            "${instance_zone}" \
            "$status_display" \
            "${creation_time_fmt}" \
            "${instance_template_from_metadata:-N/A}"
        
        if [ "$current_action" != "NONE" ]; then
            echo -e "  ${YELLOW}→ Current Action: ${current_action}${NC}"
        fi
    done
    
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${BLUE}Summary:${NC}"
    echo "  Total Instances: ${instance_count}"
    echo -e "  Healthy (RUNNING): ${GREEN}${healthy_count}${NC}"
    echo -e "  Unhealthy/Other: ${RED}${unhealthy_count}${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
}

# --- Main Execution ---
main() {
    if [ "$#" -ne 1 ]; then
        echo -e "${RED}Error: Missing MIG keyword argument.${NC}"
        show_usage
    fi
    
    local keyword=$1
    check_prerequisites
    
    local mig_data
    mig_data=$(get_mig_list "$keyword")
    # Process each MIG
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        
        local mig_name
        mig_name=$(echo "$line" | awk '{print $1}')
        local location
        location=$(echo "$line" | awk '{print $2}')
        
        # Skip header lines if they somehow leaked (e.g., if keyword is 'Searching')
        if [ "$mig_name" == "Searching" ] || [ "$mig_name" == "INSTANCE_NAME" ]; then
            continue
        fi
        
        # Determine if it's zonal or regional
        local location_type="zone"
        if [[ "$location" =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
            location_type="region"
        fi
        
        verify_mig_instances "$mig_name" "$location" "$location_type"
    done <<< "$mig_data"
    
    echo -e "${GREEN}Verification completed!${NC}"
}

main "$@"

```

