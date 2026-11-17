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
