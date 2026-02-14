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