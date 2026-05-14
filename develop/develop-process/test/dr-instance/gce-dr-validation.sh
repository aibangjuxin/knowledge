#!/bin/bash

# GCE DR Validation Script
# This script validates disaster recovery capabilities for GCE instances
# by testing auto-scaling across zones and regions

set -e

# Configuration variables - Update these with your values
MIG_NAME="${MIG_NAME:-your-mig-name}"
REGION="${REGION:-europe-west2}"
PROJECT_ID="${PROJECT_ID:-your-project-id}"

# DR Test Configuration
INITIAL_SIZE=2
SCALE_UP_SIZE=4
TARGET_CPU_UTIL=0.9
COOL_DOWN_PERIOD="180s"

# Zone configuration for testing
ZONES=("${REGION}-a" "${REGION}-b" "${REGION}-c")
ZONE_TO_SIMULATE_FAILURE="${REGION}-a"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display zone distribution
show_zone_distribution() {
    local title="$1"
    echo
    log_info "$title"
    echo "=================================================="
    
    gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --region="$REGION" \
        --format="table(instance.basename(), zone.basename(), status)" \
        --project="$PROJECT_ID"
    
    echo
    log_info "Zone distribution summary:"
    for zone in "${ZONES[@]}"; do
        local count=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
            --region="$REGION" \
            --filter="zone:($zone)" \
            --format="value(instance)" \
            --project="$PROJECT_ID" | wc -l)
        echo "  $zone: $count instances"
    done
    echo
}

# Function to get current autoscaler settings
get_autoscaler_settings() {
    log_info "Checking current autoscaler settings..."
    
    local autoscaler_exists=$(gcloud compute instance-groups managed describe "$MIG_NAME" \
        --region="$REGION" \
        --format="value(autoscaler)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$autoscaler_exists" ]]; then
        log_info "Autoscaler is currently enabled"
        gcloud compute instance-groups managed describe "$MIG_NAME" \
            --region="$REGION" \
            --format="yaml(autoscaler)" \
            --project="$PROJECT_ID"
        return 0
    else
        log_warning "No autoscaler currently configured"
        return 1
    fi
}

# Function to disable autoscaler
disable_autoscaler() {
    log_info "Disabling autoscaler for manual testing..."
    
    if get_autoscaler_settings >/dev/null 2>&1; then
        gcloud compute instance-groups managed set-autoscaling "$MIG_NAME" \
            --region="$REGION" \
            --mode=off \
            --project="$PROJECT_ID"
        log_success "Autoscaler disabled"
    else
        log_info "No autoscaler to disable"
    fi
}

# Function to enable autoscaler
enable_autoscaler() {
    local min_replicas=${1:-$INITIAL_SIZE}
    local max_replicas=${2:-$SCALE_UP_SIZE}
    
    log_info "Enabling autoscaler (min: $min_replicas, max: $max_replicas)..."
    
    gcloud compute instance-groups managed set-autoscaling "$MIG_NAME" \
        --region="$REGION" \
        --min-num-replicas="$min_replicas" \
        --max-num-replicas="$max_replicas" \
        --target-cpu-utilization="$TARGET_CPU_UTIL" \
        --cool-down-period="$COOL_DOWN_PERIOD" \
        --project="$PROJECT_ID"
    
    log_success "Autoscaler enabled"
}

# Function to resize MIG
resize_mig() {
    local new_size=$1
    local wait_time=${2:-90}
    
    log_info "Resizing MIG to $new_size instances..."
    
    gcloud compute instance-groups managed resize "$MIG_NAME" \
        --region="$REGION" \
        --size="$new_size" \
        --project="$PROJECT_ID"
    
    log_info "Waiting ${wait_time}s for instances to be created/deleted..."
    sleep "$wait_time"
}

# Function to simulate zone failure by deleting instances
simulate_zone_failure() {
    local zone_to_fail="$1"
    
    log_warning "Simulating zone failure for: $zone_to_fail"
    
    # Get instances in the target zone
    local instances=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --region="$REGION" \
        --filter="zone:($zone_to_fail)" \
        --format="value(instance.basename())" \
        --project="$PROJECT_ID")
    
    if [[ -z "$instances" ]]; then
        log_info "No instances found in zone $zone_to_fail"
        return 0
    fi
    
    log_info "Deleting instances in zone $zone_to_fail:"
    for instance in $instances; do
        log_info "  - Deleting: $instance"
        gcloud compute instance-groups managed delete-instances "$MIG_NAME" \
            --region="$REGION" \
            --instances="$instance" \
            --project="$PROJECT_ID" \
            --quiet
    done
    
    log_info "Waiting 120s for MIG to recreate instances in other zones..."
    sleep 120
}

# Function to validate zone distribution
validate_zone_distribution() {
    local expected_zones=("$@")
    local validation_passed=true
    
    log_info "Validating zone distribution..."
    
    for zone in "${expected_zones[@]}"; do
        local count=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
            --region="$REGION" \
            --filter="zone:($zone)" \
            --format="value(instance)" \
            --project="$PROJECT_ID" | wc -l)
        
        if [[ $count -gt 0 ]]; then
            log_success "✓ Zone $zone has $count instance(s)"
        else
            log_warning "✗ Zone $zone has no instances"
        fi
    done
    
    # Check if instances exist in the failed zone
    local failed_zone_count=$(gcloud compute instance-groups managed list-instances "$MIG_NAME" \
        --region="$REGION" \
        --filter="zone:($ZONE_TO_SIMULATE_FAILURE)" \
        --format="value(instance)" \
        --project="$PROJECT_ID" | wc -l)
    
    if [[ $failed_zone_count -eq 0 ]]; then
        log_success "✓ No instances in simulated failed zone ($ZONE_TO_SIMULATE_FAILURE)"
    else
        log_warning "✗ Found $failed_zone_count instance(s) in simulated failed zone"
        validation_passed=false
    fi
    
    return $validation_passed
}

# Main DR validation workflow
main() {
    echo "========================================"
    echo "GCE Disaster Recovery Validation Script"
    echo "========================================"
    echo
    
    log_info "Configuration:"
    echo "  MIG Name: $MIG_NAME"
    echo "  Region: $REGION"
    echo "  Project: $PROJECT_ID"
    echo "  Zones: ${ZONES[*]}"
    echo "  Zone to simulate failure: $ZONE_TO_SIMULATE_FAILURE"
    echo
    
    # Verify MIG exists
    if ! gcloud compute instance-groups managed describe "$MIG_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_error "MIG '$MIG_NAME' not found in region '$REGION'"
        exit 1
    fi
    
    # Step 1: Show initial state
    show_zone_distribution "Initial MIG State"
    
    # Step 2: Disable autoscaler for manual testing
    disable_autoscaler
    
    # Step 3: Scale up to test zone distribution
    log_info "=== Testing Scale-Up Zone Distribution ==="
    resize_mig "$SCALE_UP_SIZE" 90
    show_zone_distribution "After Scale-Up"
    
    # Step 4: Simulate zone failure
    log_info "=== Testing Zone Failure Recovery ==="
    simulate_zone_failure "$ZONE_TO_SIMULATE_FAILURE"
    show_zone_distribution "After Zone Failure Simulation"
    
    # Step 5: Validate DR capabilities
    log_info "=== Validating DR Capabilities ==="
    remaining_zones=()
    for zone in "${ZONES[@]}"; do
        if [[ "$zone" != "$ZONE_TO_SIMULATE_FAILURE" ]]; then
            remaining_zones+=("$zone")
        fi
    done
    
    if validate_zone_distribution "${remaining_zones[@]}"; then
        log_success "DR validation PASSED: Instances successfully redistributed to available zones"
    else
        log_error "DR validation FAILED: Issues found with zone distribution"
    fi
    
    # Step 6: Ask about restoration
    echo
    read -p "Do you want to restore the original configuration? (y/n): " restore_confirm
    
    if [[ "$restore_confirm" == "y" || "$restore_confirm" == "Y" ]]; then
        log_info "=== Restoring Original Configuration ==="
        
        # Resize back to original size
        resize_mig "$INITIAL_SIZE" 60
        
        # Re-enable autoscaler
        read -p "Re-enable autoscaler? (y/n): " autoscaler_confirm
        if [[ "$autoscaler_confirm" == "y" || "$autoscaler_confirm" == "Y" ]]; then
            enable_autoscaler "$INITIAL_SIZE" "$SCALE_UP_SIZE"
        fi
        
        show_zone_distribution "Final State After Restoration"
        log_success "Configuration restored"
    else
        log_info "Configuration left as-is for further testing"
    fi
    
    echo
    log_success "DR validation script completed!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi