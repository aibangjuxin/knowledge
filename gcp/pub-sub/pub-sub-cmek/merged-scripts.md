# Shell Scripts Collection

Generated on: 2026-01-26 09:35:00
Directory: /Users/lex/git/knowledge/gcp/pub-sub/pub-sub-cmek

## `pubsub-cmek-manager.sh`

```bash
#!/usr/bin/env bash

# ============================================================================
# GCP Pub/Sub CMEK & Cloud Scheduler Management Script
# ============================================================================
# Purpose: Manage Pub/Sub topics with CMEK encryption and Cloud Scheduler jobs
# Author: Generated for GCP CMEK workflow automation
# Version: 1.0
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Project and Resource Configuration
PROJECT_ID="${PROJECT_ID:-aibang-projectid-abjx01-dev}"
LOCATION="${LOCATION:-europe-west2}"
KEY_RING="${KEY_RING:-your-key-ring}"
KEY_NAME="${KEY_NAME:-your-key-name}"
TOPIC_NAME="${TOPIC_NAME:-test-cmek-topic}"
JOB_NAME="${JOB_NAME:-scheduler-job-001}"

# Construct full KMS key resource ID
KEY_RESOURCE_ID="projects/${PROJECT_ID}/locations/${LOCATION}/keyRings/${KEY_RING}/cryptoKeys/${KEY_NAME}"

# Get project number (needed for service agents)
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null || echo "")

# Service Agent email patterns
SCHEDULER_SA="service-${PROJECT_NUMBER}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
PUBSUB_SA="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"

# Color codes for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓ SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗ ERROR]${NC} $*"
}

log_section() {
    echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN} $*${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}\n"
}

# Validate prerequisites
validate_prerequisites() {
    log_section "Validating Prerequisites"
    
    local missing_tools=()
    
    # Check required tools
    for tool in gcloud jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    # Validate project ID
    if [ -z "$PROJECT_NUMBER" ]; then
        log_error "Failed to get project number for PROJECT_ID: $PROJECT_ID"
        log_info "Please verify the project ID and your authentication"
        return 1
    fi
    
    log_success "All prerequisites validated"
    log_info "Project ID: $PROJECT_ID"
    log_info "Project Number: $PROJECT_NUMBER"
    log_info "Location: $LOCATION"
    
    return 0
}

# ============================================================================
# SERVICE AGENT FUNCTIONS
# ============================================================================

# Get and display service agent emails
get_service_agents() {
    log_section "Service Agent Information"
    
    log_info "Retrieving service agent emails..."
    
    # Get Pub/Sub service agent (create if not exists)
    local pubsub_sa_retrieved
    pubsub_sa_retrieved=$(gcloud beta services identity create \
        --service=pubsub.googleapis.com \
        --project="${PROJECT_ID}" \
        --format="value(email)" 2>/dev/null || echo "")
    
    if [ -n "$pubsub_sa_retrieved" ]; then
        PUBSUB_SA="$pubsub_sa_retrieved"
        log_success "Pub/Sub Service Agent: ${CYAN}${PUBSUB_SA}${NC}"
    else
        log_warn "Using default Pub/Sub SA pattern: ${PUBSUB_SA}"
    fi
    
    log_info "Scheduler Service Agent: ${CYAN}${SCHEDULER_SA}${NC}"
    
    echo ""
    echo "PUBSUB_SA=${PUBSUB_SA}"
    echo "SCHEDULER_SA=${SCHEDULER_SA}"
}

# ============================================================================
# TOPIC MANAGEMENT FUNCTIONS
# ============================================================================

# Create Pub/Sub topic with CMEK encryption
create_topic_with_cmek() {
    local topic_name="${1:-$TOPIC_NAME}"
    
    log_section "Creating Pub/Sub Topic with CMEK"
    
    log_info "Topic Name: ${topic_name}"
    log_info "Encryption Key: ${KEY_RESOURCE_ID}"
    
    if gcloud pubsub topics describe "${topic_name}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_warn "Topic '${topic_name}' already exists"
        describe_topic "${topic_name}"
        return 0
    fi
    
    log_info "Creating topic..."
    
    if gcloud pubsub topics create "${topic_name}" \
        --topic-encryption-key="${KEY_RESOURCE_ID}" \
        --project="${PROJECT_ID}"; then
        log_success "Topic '${topic_name}' created successfully with CMEK"
        describe_topic "${topic_name}"
    else
        log_error "Failed to create topic '${topic_name}'"
        return 1
    fi
}

# Describe Pub/Sub topic
describe_topic() {
    local topic_name="${1:-$TOPIC_NAME}"
    
    log_section "Topic Details: ${topic_name}"
    
    if ! gcloud pubsub topics describe "${topic_name}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_error "Topic '${topic_name}' does not exist"
        return 1
    fi
    
    # Get full topic details
    local topic_details
    topic_details=$(gcloud pubsub topics describe "${topic_name}" \
        --project="${PROJECT_ID}" \
        --format=json)
    
    # Extract key information
    local kms_key
    kms_key=$(echo "$topic_details" | jq -r '.kmsKeyName // "NOT_ENCRYPTED"')
    
    echo -e "${BOLD}Topic Information:${NC}"
    echo -e "  Name:           ${CYAN}${topic_name}${NC}"
    echo -e "  Project:        ${PROJECT_ID}"
    echo -e "  Encryption Key: ${GREEN}${kms_key}${NC}"
    
    if [ "$kms_key" = "NOT_ENCRYPTED" ]; then
        log_warn "Topic is NOT encrypted with CMEK!"
        log_warn "This may cause issues with restrictNonCmekServices policy"
    else
        log_success "Topic is properly encrypted with CMEK"
    fi
    
    echo ""
    echo "Full topic details:"
    echo "$topic_details" | jq '.'
}

# Delete Pub/Sub topic
delete_topic() {
    local topic_name="${1:-$TOPIC_NAME}"
    
    log_section "Deleting Topic: ${topic_name}"
    
    if ! gcloud pubsub topics describe "${topic_name}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_warn "Topic '${topic_name}' does not exist"
        return 0
    fi
    
    log_info "Deleting topic..."
    
    if gcloud pubsub topics delete "${topic_name}" \
        --project="${PROJECT_ID}" \
        --quiet; then
        log_success "Topic '${topic_name}' deleted successfully"
    else
        log_error "Failed to delete topic '${topic_name}'"
        return 1
    fi
}

# ============================================================================
# PERMISSION MANAGEMENT FUNCTIONS
# ============================================================================

# Check KMS permissions for service agents
check_kms_permissions() {
    log_section "Checking KMS Permissions"
    
    log_info "Checking permissions on key: ${KEY_NAME}"
    
    # Get current IAM policy
    local policy
    policy=$(gcloud kms keys get-iam-policy "${KEY_NAME}" \
        --keyring="${KEY_RING}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" \
        --format=json 2>/dev/null || echo "{}")
    
    echo -e "\n${BOLD}Current IAM Policy:${NC}"
    echo "$policy" | jq '.'
    
    # Check for Scheduler SA
    echo -e "\n${BOLD}Checking Scheduler Service Agent:${NC}"
    if echo "$policy" | jq -e --arg sa "$SCHEDULER_SA" \
        '.bindings[]? | select(.role=="roles/cloudkms.cryptoKeyEncrypterDecrypter") | .members[] | select(. == "serviceAccount:\($sa)")' \
        &>/dev/null; then
        log_success "Scheduler SA has cryptoKeyEncrypterDecrypter role"
    else
        log_warn "Scheduler SA MISSING cryptoKeyEncrypterDecrypter role"
        echo "  Required for: Creating/resuming Scheduler jobs with CMEK topics"
    fi
    
    # Check for Pub/Sub SA
    echo -e "\n${BOLD}Checking Pub/Sub Service Agent:${NC}"
    if echo "$policy" | jq -e --arg sa "$PUBSUB_SA" \
        '.bindings[]? | select(.role=="roles/cloudkms.cryptoKeyEncrypterDecrypter") | .members[] | select(. == "serviceAccount:\($sa)")' \
        &>/dev/null; then
        log_success "Pub/Sub SA has cryptoKeyEncrypterDecrypter role"
    else
        log_warn "Pub/Sub SA MISSING cryptoKeyEncrypterDecrypter role"
        echo "  Required for: Message encryption/decryption in CMEK topics"
    fi
}

# Grant KMS permissions to service agents
grant_kms_permissions() {
    log_section "Granting KMS Permissions"
    
    local grant_scheduler="${1:-true}"
    local grant_pubsub="${2:-true}"
    
    # Grant to Scheduler SA
    if [ "$grant_scheduler" = "true" ]; then
        log_info "Granting permissions to Scheduler Service Agent..."
        
        if gcloud kms keys add-iam-policy-binding "${KEY_NAME}" \
            --keyring="${KEY_RING}" \
            --location="${LOCATION}" \
            --project="${PROJECT_ID}" \
            --member="serviceAccount:${SCHEDULER_SA}" \
            --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
            --condition=None; then
            log_success "Granted cryptoKeyEncrypterDecrypter to Scheduler SA"
        else
            log_error "Failed to grant permissions to Scheduler SA"
        fi
    fi
    
    # Grant to Pub/Sub SA
    if [ "$grant_pubsub" = "true" ]; then
        log_info "Granting permissions to Pub/Sub Service Agent..."
        
        if gcloud kms keys add-iam-policy-binding "${KEY_NAME}" \
            --keyring="${KEY_RING}" \
            --location="${LOCATION}" \
            --project="${PROJECT_ID}" \
            --member="serviceAccount:${PUBSUB_SA}" \
            --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
            --condition=None; then
            log_success "Granted cryptoKeyEncrypterDecrypter to Pub/Sub SA"
        else
            log_error "Failed to grant permissions to Pub/Sub SA"
        fi
    fi
    
    # Verify permissions were granted
    echo ""
    check_kms_permissions
}

# Verify all permissions are correctly set
verify_all_permissions() {
    log_section "Complete Permission Verification"
    
    local all_ok=true
    
    # Check KMS permissions
    check_kms_permissions
    
    # Summary
    echo -e "\n${BOLD}Verification Summary:${NC}"
    
    local policy
    policy=$(gcloud kms keys get-iam-policy "${KEY_NAME}" \
        --keyring="${KEY_RING}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" \
        --format=json 2>/dev/null || echo "{}")
    
    if echo "$policy" | jq -e --arg sa "$SCHEDULER_SA" \
        '.bindings[]? | select(.role=="roles/cloudkms.cryptoKeyEncrypterDecrypter") | .members[] | select(. == "serviceAccount:\($sa)")' \
        &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Scheduler SA permissions: OK"
    else
        echo -e "  ${RED}✗${NC} Scheduler SA permissions: MISSING"
        all_ok=false
    fi
    
    if echo "$policy" | jq -e --arg sa "$PUBSUB_SA" \
        '.bindings[]? | select(.role=="roles/cloudkms.cryptoKeyEncrypterDecrypter") | .members[] | select(. == "serviceAccount:\($sa)")' \
        &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Pub/Sub SA permissions: OK"
    else
        echo -e "  ${RED}✗${NC} Pub/Sub SA permissions: MISSING"
        all_ok=false
    fi
    
    if [ "$all_ok" = "true" ]; then
        log_success "All permissions are correctly configured"
        return 0
    else
        log_warn "Some permissions are missing. Run 'grant_kms_permissions' to fix."
        return 1
    fi
}

# ============================================================================
# SCHEDULER JOB MANAGEMENT FUNCTIONS
# ============================================================================

# Create Cloud Scheduler job
create_scheduler_job() {
    local job_name="${1:-$JOB_NAME}"
    local topic_name="${2:-$TOPIC_NAME}"
    local schedule="${3:-*/5 * * * *}"  # Every 5 minutes by default
    
    log_section "Creating Cloud Scheduler Job"
    
    log_info "Job Name: ${job_name}"
    log_info "Target Topic: ${topic_name}"
    log_info "Schedule: ${schedule}"
    
    # Check if job already exists
    if gcloud scheduler jobs describe "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_warn "Job '${job_name}' already exists"
        describe_scheduler_job "${job_name}"
        return 0
    fi
    
    # Verify topic exists
    if ! gcloud pubsub topics describe "${topic_name}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_error "Topic '${topic_name}' does not exist. Create it first."
        return 1
    fi
    
    log_info "Creating scheduler job..."
    
    if gcloud scheduler jobs create pubsub "${job_name}" \
        --schedule="${schedule}" \
        --topic="${topic_name}" \
        --message-body='{"status":"scheduled","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}"; then
        log_success "Scheduler job '${job_name}' created successfully"
        describe_scheduler_job "${job_name}"
    else
        log_error "Failed to create scheduler job '${job_name}'"
        log_info "This may be due to missing KMS permissions. Check with 'check_kms_permissions'"
        return 1
    fi
}

# Describe Cloud Scheduler job
describe_scheduler_job() {
    local job_name="${1:-$JOB_NAME}"
    
    log_section "Scheduler Job Details: ${job_name}"
    
    if ! gcloud scheduler jobs describe "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_error "Job '${job_name}' does not exist"
        return 1
    fi
    
    local job_details
    job_details=$(gcloud scheduler jobs describe "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" \
        --format=json)
    
    # Extract key information
    local state
    local schedule
    local topic
    
    state=$(echo "$job_details" | jq -r '.state // "UNKNOWN"')
    schedule=$(echo "$job_details" | jq -r '.schedule // "N/A"')
    topic=$(echo "$job_details" | jq -r '.pubsubTarget.topicName // "N/A"')
    
    echo -e "${BOLD}Job Information:${NC}"
    echo -e "  Name:     ${CYAN}${job_name}${NC}"
    echo -e "  State:    ${GREEN}${state}${NC}"
    echo -e "  Schedule: ${schedule}"
    echo -e "  Topic:    ${topic}"
    
    echo ""
    echo "Full job details:"
    echo "$job_details" | jq '.'
}

# Delete Cloud Scheduler job
delete_scheduler_job() {
    local job_name="${1:-$JOB_NAME}"
    
    log_section "Deleting Scheduler Job: ${job_name}"
    
    if ! gcloud scheduler jobs describe "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_warn "Job '${job_name}' does not exist"
        return 0
    fi
    
    log_info "Deleting job..."
    
    if gcloud scheduler jobs delete "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" \
        --quiet; then
        log_success "Job '${job_name}' deleted successfully"
    else
        log_error "Failed to delete job '${job_name}'"
        return 1
    fi
}

# Resume Cloud Scheduler job
resume_scheduler_job() {
    local job_name="${1:-$JOB_NAME}"
    
    log_section "Resuming Scheduler Job: ${job_name}"
    
    if ! gcloud scheduler jobs describe "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_error "Job '${job_name}' does not exist"
        return 1
    fi
    
    log_info "Attempting to resume job..."
    
    if gcloud scheduler jobs resume "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}"; then
        log_success "Job '${job_name}' resumed successfully"
        describe_scheduler_job "${job_name}"
    else
        log_error "Failed to resume job '${job_name}'"
        log_warn "This may indicate a broken internal stream (NOT_FOUND error)"
        log_info "Solution: Delete and recreate the job using 'recreate_broken_job'"
        return 1
    fi
}

# Pause Cloud Scheduler job
pause_scheduler_job() {
    local job_name="${1:-$JOB_NAME}"
    
    log_section "Pausing Scheduler Job: ${job_name}"
    
    if ! gcloud scheduler jobs describe "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_error "Job '${job_name}' does not exist"
        return 1
    fi
    
    log_info "Pausing job..."
    
    if gcloud scheduler jobs pause "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}"; then
        log_success "Job '${job_name}' paused successfully"
        describe_scheduler_job "${job_name}"
    else
        log_error "Failed to pause job '${job_name}'"
        return 1
    fi
}

# ============================================================================
# JOB STATUS SIMULATION FUNCTIONS
# ============================================================================

# Simulate different job statuses
simulate_job_status() {
    local status="${1:-PAUSED}"
    local job_name="${2:-$JOB_NAME}"
    
    log_section "Simulating Job Status: ${status}"
    
    case "$status" in
        ENABLED)
            log_info "Creating job in ENABLED state..."
            create_scheduler_job "$job_name"
            ;;
        PAUSED)
            log_info "Creating job and pausing it..."
            create_scheduler_job "$job_name"
            sleep 2
            pause_scheduler_job "$job_name"
            ;;
        FAILED)
            log_info "Simulating FAILED state by creating without permissions..."
            log_warn "This will intentionally fail to demonstrate the error"
            # Temporarily note: actual failure requires removing permissions
            log_info "To truly simulate FAILED state:"
            echo "  1. Remove KMS permissions from service agents"
            echo "  2. Try to create the job"
            echo "  3. Job will be created but in broken state"
            ;;
        *)
            log_error "Unknown status: $status"
            log_info "Valid statuses: ENABLED, PAUSED, FAILED"
            return 1
            ;;
    esac
}

# Test resume scenarios
test_resume_scenarios() {
    log_section "Testing Resume Scenarios"
    
    local test_job="test-resume-job"
    
    # Scenario 1: Resume a healthy paused job
    echo -e "\n${BOLD}Scenario 1: Resume healthy paused job${NC}"
    create_scheduler_job "$test_job"
    pause_scheduler_job "$test_job"
    sleep 2
    resume_scheduler_job "$test_job"
    
    # Cleanup
    delete_scheduler_job "$test_job"
    
    log_success "Resume scenario testing completed"
}

# ============================================================================
# WORKFLOW FUNCTIONS
# ============================================================================

# Complete setup workflow
full_setup_workflow() {
    log_section "Complete Setup Workflow"
    
    echo "This workflow will:"
    echo "  1. Validate prerequisites"
    echo "  2. Get service agent emails"
    echo "  3. Create CMEK-encrypted topic"
    echo "  4. Grant KMS permissions"
    echo "  5. Create scheduler job"
    echo "  6. Verify everything is working"
    echo ""
    
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Workflow cancelled"
        return 0
    fi
    
    # Step 1: Validate
    validate_prerequisites || return 1
    
    # Step 2: Get service agents
    get_service_agents
    
    # Step 3: Create topic
    create_topic_with_cmek || return 1
    
    # Step 4: Grant permissions
    grant_kms_permissions || return 1
    
    # Step 5: Create scheduler job
    create_scheduler_job || return 1
    
    # Step 6: Verify
    verify_all_permissions
    
    log_success "Complete setup workflow finished successfully!"
}

# Troubleshoot resume failure
troubleshoot_resume_failure() {
    local job_name="${1:-$JOB_NAME}"
    
    log_section "Troubleshooting Resume Failure for: ${job_name}"
    
    echo "Running diagnostic checks..."
    echo ""
    
    # Check 1: Job exists
    echo -e "${BOLD}Check 1: Job Existence${NC}"
    if gcloud scheduler jobs describe "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_success "Job exists"
    else
        log_error "Job does not exist"
        return 1
    fi
    
    # Check 2: Topic exists and is CMEK encrypted
    echo -e "\n${BOLD}Check 2: Topic Configuration${NC}"
    local job_details
    job_details=$(gcloud scheduler jobs describe "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" \
        --format=json)
    
    local topic_name
    topic_name=$(echo "$job_details" | jq -r '.pubsubTarget.topicName' | awk -F'/' '{print $NF}')
    
    if [ -n "$topic_name" ] && [ "$topic_name" != "null" ]; then
        log_info "Target topic: $topic_name"
        describe_topic "$topic_name"
    else
        log_error "Cannot determine target topic"
    fi
    
    # Check 3: KMS Permissions
    echo -e "\n${BOLD}Check 3: KMS Permissions${NC}"
    check_kms_permissions
    
    # Recommendation
    echo -e "\n${BOLD}${YELLOW}Recommendation:${NC}"
    echo "If the job has a NOT_FOUND error on resume, the internal stream is broken."
    echo "Solution: Delete and recreate the job using:"
    echo "  recreate_broken_job \"${job_name}\""
}

# Recreate a broken scheduler job
recreate_broken_job() {
    local job_name="${1:-$JOB_NAME}"
    
    log_section "Recreating Broken Job: ${job_name}"
    
    # Get current job configuration
    if ! gcloud scheduler jobs describe "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_error "Job '${job_name}' does not exist"
        return 1
    fi
    
    local job_details
    job_details=$(gcloud scheduler jobs describe "${job_name}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" \
        --format=json)
    
    local schedule
    local topic_name
    
    schedule=$(echo "$job_details" | jq -r '.schedule')
    topic_name=$(echo "$job_details" | jq -r '.pubsubTarget.topicName' | awk -F'/' '{print $NF}')
    
    log_info "Current configuration:"
    echo "  Schedule: $schedule"
    echo "  Topic: $topic_name"
    echo ""
    
    read -p "Delete and recreate this job? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        return 0
    fi
    
    # Delete old job
    delete_scheduler_job "${job_name}" || return 1
    
    # Wait a moment
    sleep 2
    
    # Recreate job
    create_scheduler_job "${job_name}" "${topic_name}" "${schedule}"
    
    log_success "Job recreated successfully!"
}

# Cleanup all test resources
cleanup_resources() {
    log_section "Cleanup Resources"
    
    echo "This will delete:"
    echo "  - Scheduler job: $JOB_NAME"
    echo "  - Pub/Sub topic: $TOPIC_NAME"
    echo ""
    echo "KMS permissions will NOT be removed (manual cleanup required)"
    echo ""
    
    read -p "Continue with cleanup? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled"
        return 0
    fi
    
    # Delete scheduler job
    delete_scheduler_job "$JOB_NAME" 2>/dev/null || true
    
    # Delete topic
    delete_topic "$TOPIC_NAME" 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# ============================================================================
# MAIN MENU
# ============================================================================

show_menu() {
    cat <<EOF

${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}
${BOLD}${CYAN}  GCP Pub/Sub CMEK & Scheduler Management${NC}
${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}

${BOLD}Configuration:${NC}
  PROJECT_ID:  ${PROJECT_ID}
  LOCATION:    ${LOCATION}
  TOPIC_NAME:  ${TOPIC_NAME}
  JOB_NAME:    ${JOB_NAME}

${BOLD}Topic Management:${NC}
  1) Create topic with CMEK
  2) Describe topic
  3) Delete topic

${BOLD}Scheduler Job Management:${NC}
  4) Create scheduler job
  5) Describe scheduler job
  6) Delete scheduler job
  7) Resume scheduler job
  8) Pause scheduler job

${BOLD}Permission Management:${NC}
  9) Get service agents
  10) Check KMS permissions
  11) Grant KMS permissions
  12) Verify all permissions

${BOLD}Testing \u0026 Troubleshooting:${NC}
  13) Simulate job status
  14) Test resume scenarios
  15) Troubleshoot resume failure
  16) Recreate broken job

${BOLD}Workflows:${NC}
  17) Full setup workflow
  18) Cleanup resources

${BOLD}Other:${NC}
  19) Validate prerequisites
  0) Exit

EOF
}

# Main function
main() {
    # If function name provided as argument, execute it
    if [ $# -gt 0 ]; then
        "$@"
        return $?
    fi
    
    # Otherwise show interactive menu
    while true; do
        show_menu
        read -p "Select an option: " choice
        echo ""
        
        case $choice in
            1) create_topic_with_cmek ;;
            2) describe_topic ;;
            3) delete_topic ;;
            4) create_scheduler_job ;;
            5) describe_scheduler_job ;;
            6) delete_scheduler_job ;;
            7) resume_scheduler_job ;;
            8) pause_scheduler_job ;;
            9) get_service_agents ;;
            10) check_kms_permissions ;;
            11) grant_kms_permissions ;;
            12) verify_all_permissions ;;
            13) 
                read -p "Enter status (ENABLED/PAUSED/FAILED): " status
                simulate_job_status "$status"
                ;;
            14) test_resume_scenarios ;;
            15) troubleshoot_resume_failure ;;
            16) recreate_broken_job ;;
            17) full_setup_workflow ;;
            18) cleanup_resources ;;
            19) validate_prerequisites ;;
            0) 
                log_info "Exiting..."
                exit 0
                ;;
            *) 
                log_error "Invalid option: $choice"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"

```

