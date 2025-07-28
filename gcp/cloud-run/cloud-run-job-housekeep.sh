#!/bin/bash

# =============================================================================
# Cloud Run Job Housekeeping Script (Enhanced Version)
# =============================================================================
#
# Features:
# - Delete failed executions
# - Delete older executions
# - Support batch processing of multiple jobs
# - Support dry-run mode
# - Detailed logging
# - Error handling and retry mechanism
# - Statistical report
#
# Author: Lex
# Version: 1.0
# Last Updated: $(date +"%Y-%m-%d")
#
# =============================================================================

set -euo pipefail

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Global Variables ---
SCRIPT_NAME=$(basename "$0")
LOG_FILE="/tmp/cloud-run-housekeep-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
VERBOSE=false
BATCH_MODE=false
CONFIG_FILE=""
DELETED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# --- Logging Function ---
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            if [ "$VERBOSE" = true ]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# --- Help Information ---
show_help() {
    cat << EOF
$SCRIPT_NAME - Cloud Run Job Housekeeping Script

Usage:
    $SCRIPT_NAME [Options] <JOB_NAME> <REGION>
    $SCRIPT_NAME [Options] --batch --config <CONFIG_FILE>

Options:
    -h, --help              Show this help message
    -d, --dry-run           Dry-run mode, does not actually delete
    -v, --verbose           Verbose output
    -f, --delete-failed     Delete failed executions
    -o, --older-than DAYS   Delete executions older than specified days
    -b, --batch             Batch mode
    -c, --config FILE       Configuration file path
    -l, --log-file FILE     Specify log file path
    -r, --retry COUNT       Number of retries (default: 3)

Examples:
    # Delete failed executions
    $SCRIPT_NAME -f my-job europe-west2

    # Delete executions older than 30 days (dry-run)
    $SCRIPT_NAME -d -o 30 my-job europe-west2

    # Batch processing
    $SCRIPT_NAME -b -c jobs.conf

    # Full cleanup
    $SCRIPT_NAME -f -o 7 -v my-job europe-west2

Configuration file format (jobs.conf):
    # Format: JOB_NAME,REGION,DELETE_FAILED,OLDER_THAN_DAYS
    my-job-1,europe-west2,true,30
    my-job-2,us-central1,false,7
    my-job-3,asia-northeast1,true,14

EOF
}

# --- Argument Parsing ---
parse_arguments() {
    local delete_failed=false
    local older_than_days=""
    local retry_count=3

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--delete-failed)
                delete_failed=true
                shift
                ;;
            -o|--older-than)
                older_than_days="$2"
                shift 2
                ;;
            -b|--batch)
                BATCH_MODE=true
                shift
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -l|--log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            -r|--retry)
                retry_count="$2"
                shift 2
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [ "$BATCH_MODE" = false ]; then
                    if [ -z "${JOB_NAME:-}" ]; then
                        JOB_NAME="$1"
                    elif [ -z "${REGION:-}" ]; then
                        REGION="$1"
                    else
                        log "ERROR" "Too many arguments: $1"
                        exit 1
                    fi
                fi
                shift
                ;;
        esac
    done

    # Export variables for other functions to use
    export DELETE_FAILED="$delete_failed"
    export OLDER_THAN_DAYS="$older_than_days"
    export RETRY_COUNT="$retry_count"
}

# --- Dependency Validation ---
check_dependencies() {
    local deps=("gcloud" "jq" "date")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "ERROR" "Dependency '$dep' not found, please install it first"
            exit 1
        fi
    done

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log "ERROR" "gcloud is not authenticated, please run 'gcloud auth login' first"
        exit 1
    fi

    log "DEBUG" "All dependency checks passed"
}

# --- Retry Mechanism ---
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local command=("$@")

    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log "DEBUG" "Attempting to execute command (Attempt $attempt): ${command[*]}"

        if "${command[@]}"; then
            return 0
        else
            local exit_code=$?
            log "WARN" "Command failed (Attempt $attempt) with exit code: $exit_code"

            if [ $attempt -lt $max_attempts ]; then
                log "INFO" "Retrying after $delay seconds..."
                sleep "$delay"
            fi

            ((attempt++))
        fi
    done

    log "ERROR" "Command still failed after $max_attempts attempts"
    return 1
}

# --- Get Executions List ---
get_executions() {
    local job_name="$1"
    local region="$2"

    log "DEBUG" "Getting executions for job '$job_name' in region '$region'"

    local executions_json
    if ! executions_json=$(retry_command "$RETRY_COUNT" 2 gcloud run jobs executions list \
        --job="$job_name" \
        --region="$region" \
        --format="json" 2>/dev/null); then
        log "ERROR" "Failed to get executions for job '$job_name'"
        return 1
    fi

    if [ "$executions_json" = "[]" ] || [ -z "$executions_json" ]; then
        log "INFO" "No executions found for job '$job_name'"
        echo "[]"
        return 0
    fi

    echo "$executions_json"
}

# --- Delete Failed Executions ---
delete_failed_executions() {
    local job_name="$1"
    local region="$2"
    local executions_json="$3"

    log "INFO" "Finding failed executions for job '$job_name'..."

    local failed_executions
    failed_executions=$(echo "$executions_json" | jq -r '
        .[] |
        select(
            (.status.conditions[]? | select(.type == "Completed" and .status == "False")) or
            (.status.failedCount? and .status.failedCount > 0)
        ) |
        .metadata.name
    ')

    if [ -z "$failed_executions" ]; then
        log "INFO" "No failed executions found"
        return 0
    fi

    local count=0
    while IFS= read -r execution_name; do
        [ -z "$execution_name" ] && continue

        log "INFO" "Processing failed execution: $execution_name"

        if [ "$DRY_RUN" = true ]; then
            log "INFO" "[DRY RUN] Would delete failed execution: $execution_name"
            ((SKIPPED_COUNT++))
        else
            if retry_command "$RETRY_COUNT" 2 gcloud run jobs executions delete \
                "$execution_name" --region="$region" --quiet; then
                log "INFO" "Successfully deleted failed execution: $execution_name"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete failed execution: $execution_name"
                ((FAILED_COUNT++))
            fi
        fi
        ((count++))
    done <<< "$failed_executions"

    log "INFO" "Processed $count failed executions"
}

# --- Delete Older Executions ---
delete_older_executions() {
    local job_name="$1"
    local region="$2"
    local executions_json="$3"
    local days="$4"

    log "INFO" "Finding executions older than $days days for job '$job_name'..."

    # Calculate cutoff date
    local cutoff_date
    if command -v gdate &> /dev/null; then
        # macOS with GNU date
        cutoff_date=$(gdate -d "$days days ago" -u +"%Y-%m-%dT%H:%M:%SZ")
    else
        # Linux date
        cutoff_date=$(date -d "$days days ago" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                     date -v-"$days"d -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    fi

    if [ -z "$cutoff_date" ]; then
        log "ERROR" "Could not calculate cutoff date"
        return 1
    fi

    log "DEBUG" "Cutoff date: $cutoff_date"

    local older_executions
    older_executions=$(echo "$executions_json" | jq -r --arg CUTOFF_DATE "$cutoff_date" '
        .[] |
        select(
            .status.completionTime and
            .status.completionTime < $CUTOFF_DATE and
            (.status.conditions[]? | select(.type == "Completed" and .status == "True"))
        ) |
        .metadata.name
    ')

    if [ -z "$older_executions" ]; then
        log "INFO" "No executions found older than $days days"
        return 0
    fi

    local count=0
    while IFS= read -r execution_name; do
        [ -z "$execution_name" ] && continue

        log "INFO" "Processing older execution: $execution_name"

        if [ "$DRY_RUN" = true ]; then
            log "INFO" "[DRY RUN] Would delete older execution: $execution_name"
            ((SKIPPED_COUNT++))
        else
            if retry_command "$RETRY_COUNT" 2 gcloud run jobs executions delete \
                "$execution_name" --region="$region" --quiet; then
                log "INFO" "Successfully deleted older execution: $execution_name"
                ((DELETED_COUNT++))
            else
                log "ERROR" "Failed to delete older execution: $execution_name"
                ((FAILED_COUNT++))
            fi
        fi
        ((count++))
    done <<< "$older_executions"

    log "INFO" "Processed $count older executions"
}

# --- Process Single Job ---
process_job() {
    local job_name="$1"
    local region="$2"
    local delete_failed="$3"
    local older_than_days="$4"

    log "INFO" "Starting to process job: $job_name (Region: $region)"

    # Verifying if job exists
    if ! gcloud run jobs describe "$job_name" --region="$region" &>/dev/null; then
        log "ERROR" "Job '$job_name' does not exist in region '$region'"
        ((FAILED_COUNT++))
        return 1
    fi

    # Get executions list
    local executions_json
    if ! executions_json=$(get_executions "$job_name" "$region"); then
        log "ERROR" "Failed to get executions for job '$job_name'"
        ((FAILED_COUNT++))
        return 1
    fi

    # Checking for execution records
    if [ "$executions_json" = "[]" ]; then
        log "INFO" "Job '$job_name' has no executions, skipping"
        ((SKIPPED_COUNT++))
        return 0
    fi

    # Delete failed executions
    if [ "$delete_failed" = true ]; then
        delete_failed_executions "$job_name" "$region" "$executions_json"
    fi

    # Delete older executions
    if [ -n "$older_than_days" ]; then
        delete_older_executions "$job_name" "$region" "$executions_json" "$older_than_days"
    fi

    log "INFO" "Finished processing job: $job_name"

    # If no executions were deleted and there were no failures, provide a friendly message
    local job_deleted=0
    local job_skipped=0

    if [ "$delete_failed" = true ] && [ -n "$older_than_days" ]; then
        log "INFO" "Job '$job_name' processing complete - checked for failed and executions older than $older_than_days days"
    elif [ "$delete_failed" = true ]; then
        log "INFO" "Job '$job_name' processing complete - checked for failed executions"
    elif [ -n "$older_than_days" ]; then
        log "INFO" "Job '$job_name' processing complete - checked for executions older than $older_than_days days"
    fi
}

# --- Batch Processing ---
process_batch() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        log "ERROR" "Configuration file not found: $config_file"
        exit 1
    fi

    log "INFO" "Starting batch processing with config file: $config_file"

    local line_number=0
    while IFS=',' read -r job_name region delete_failed older_than_days || [ -n "$job_name" ]; do
        ((line_number++))

        # Skipping empty lines and comments
        if [[ -z "$job_name" || "$job_name" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Trimming whitespace
        job_name=$(echo "$job_name" | xargs)
        region=$(echo "$region" | xargs)
        delete_failed=$(echo "$delete_failed" | xargs)
        older_than_days=$(echo "$older_than_days" | xargs)

        log "INFO" "Processing config line $line_number: $job_name,$region,$delete_failed,$older_than_days"

        # Validating parameters
        if [ -z "$job_name" ] || [ -z "$region" ]; then
            log "ERROR" "Incorrect format in config file on line $line_number"
            ((FAILED_COUNT++))
            continue
        fi

        # Processing job
        process_job "$job_name" "$region" "$delete_failed" "$older_than_days"

    done < "$config_file"
}

# --- Generate Report ---
generate_report() {
    log "INFO" "==================== Cleanup Report ===================="
    log "INFO" "Execution Time: $(date)"
    log "INFO" "Log File: $LOG_FILE"
    log "INFO" "Dry Run Mode: $DRY_RUN"
    log "INFO" ""
    log "INFO" "Statistics:"
    log "INFO" "  - Successfully Deleted: $DELETED_COUNT"
    log "INFO" "  - Skipped: $SKIPPED_COUNT"
    log "INFO" "  - Failed: $FAILED_COUNT"
    log "INFO" "=================================================="

    # Return error code only on actual failures, not if no items were found to delete
    if [ $FAILED_COUNT -gt 0 ]; then
        log "WARN" "Some items failed to process, please check the log file: $LOG_FILE"
    fi

    # Always return success, let the main function decide the final exit code
    return 0
}

# --- Cleanup Function ---
cleanup() {
    #local exit_code=$?

    # Generate report
    generate_report

    if [ "$VERBOSE" = true ]; then
        log "INFO" "Verbose log saved to: $LOG_FILE"
    fi

    # Determine exit code based on actual failures
    if [ $FAILED_COUNT -gt 0 ]; then
        log "ERROR" "Script execution had failures, exiting with code: 1"
        exit 1
    else
        log "INFO" "Script finished successfully"
        exit 0
    fi
}

# --- Main Function ---
main() {
    # Set up signal trap
    trap cleanup EXIT INT TERM

    log "INFO" "Starting Cloud Run Job Housekeeping"
    log "INFO" "Script Version: 2.0"
    log "INFO" "Log File: $LOG_FILE"

    # Check dependencies
    check_dependencies

    # Parse arguments
    parse_arguments "$@"

    # Validate arguments
    if [ "$BATCH_MODE" = true ]; then
        if [ -z "$CONFIG_FILE" ]; then
            log "ERROR" "Batch mode requires a config file"
            show_help
            exit 1
        fi
        process_batch "$CONFIG_FILE"
    else
        if [ -z "${JOB_NAME:-}" ] || [ -z "${REGION:-}" ]; then
            log "ERROR" "JOB_NAME and REGION must be provided"
            show_help
            exit 1
        fi

        if [ "$DELETE_FAILED" = false ] && [ -z "$OLDER_THAN_DAYS" ]; then
            log "ERROR" "Must specify at least one cleanup option (-f or -o)"
            show_help
            exit 1
        fi

        process_job "$JOB_NAME" "$REGION" "$DELETE_FAILED" "$OLDER_THAN_DAYS"
    fi

    log "INFO" "Housekeeping complete"
}

# --- Script Entrypoint ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
