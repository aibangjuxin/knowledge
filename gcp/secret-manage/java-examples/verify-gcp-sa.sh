#!/bin/bash

# Enhanced GCP Secret Manager Service Account Verification Script
# This script provides comprehensive debugging for GCP Secret Manager integration with GKE Workload Identity

# Color output settings
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_NAME=$(basename "$0")
DEBUG_MODE=false
VERBOSE_MODE=false
CHECK_SECRETS=true
FIX_MODE=false

# Usage function
usage() {
    echo "Usage: $SCRIPT_NAME [OPTIONS] <deployment-name> <namespace>"
    echo ""
    echo "OPTIONS:"
    echo "  -d, --debug         Enable debug mode with detailed output"
    echo "  -v, --verbose       Enable verbose mode"
    echo "  -s, --skip-secrets  Skip secret verification checks"
    echo "  -f, --fix          Attempt to fix common issues (experimental)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $SCRIPT_NAME my-app default"
    echo "  $SCRIPT_NAME --debug --verbose my-app my-namespace"
    echo "  $SCRIPT_NAME -d -f secret-manager-demo secret-manager-demo"
    echo ""
    exit 1
}

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

log_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

log_step() {
    echo -e "\n${CYAN}=== $1 ===${NC}"
}

# Check if required tools are installed
check_prerequisites() {
    log_step "Checking Prerequisites"
    
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v gcloud &> /dev/null; then
        missing_tools+=("gcloud")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again"
        exit 1
    fi
    
    log_success "All required tools are available"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--debug)
                DEBUG_MODE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE_MODE=true
                shift
                ;;
            -s|--skip-secrets)
                CHECK_SECRETS=false
                shift
                ;;
            -f|--fix)
                FIX_MODE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            -*)
                log_error "Unknown option $1"
                usage
                ;;
            *)
                if [ -z "$DEPLOYMENT_NAME" ]; then
                    DEPLOYMENT_NAME="$1"
                elif [ -z "$NAMESPACE" ]; then
                    NAMESPACE="$1"
                else
                    log_error "Too many arguments"
                    usage
                fi
                shift
                ;;
        esac
    done
    
    if [ -z "$DEPLOYMENT_NAME" ] || [ -z "$NAMESPACE" ]; then
        log_error "Missing required arguments"
        usage
    fi
}

# Get project ID and validate GCP authentication
validate_gcp_auth() {
    log_step "Validating GCP Authentication"
    
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        log_error "No GCP project configured. Run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    log_info "Using GCP Project: $PROJECT_ID"
    
    # Test GCP authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        log_error "GCP authentication failed. Run: gcloud auth login"
        exit 1
    fi
    
    log_success "GCP authentication validated"
}

# Check if deployment exists
check_deployment() {
    log_step "Checking Deployment"
    
    if ! kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" &>/dev/null; then
        log_error "Deployment '$DEPLOYMENT_NAME' not found in namespace '$NAMESPACE'"
        
        log_info "Available deployments in namespace '$NAMESPACE':"
        kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print "  - " $1}' || log_warning "No deployments found"
        exit 1
    fi
    
    log_success "Deployment '$DEPLOYMENT_NAME' found"
    
    if [ "$VERBOSE_MODE" = true ]; then
        kubectl describe deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"
    fi
}

# Get Kubernetes Service Account
get_kubernetes_sa() {
    log_step "Getting Kubernetes Service Account"
    
    KSA=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null)
    
    if [ -z "$KSA" ]; then
        KSA="default"
        log_warning "No explicit ServiceAccount found, using 'default'"
    else
        log_info "Found ServiceAccount: $KSA"
    fi
    
    # Check if KSA exists
    if ! kubectl get serviceaccount "$KSA" -n "$NAMESPACE" &>/dev/null; then
        log_error "ServiceAccount '$KSA' not found in namespace '$NAMESPACE'"
        exit 1
    fi
    
    log_success "Kubernetes ServiceAccount: $KSA"
    
    if [ "$DEBUG_MODE" = true ]; then
        log_debug "ServiceAccount details:"
        kubectl describe serviceaccount "$KSA" -n "$NAMESPACE"
    fi
}

# Get GCP Service Account from KSA annotation
get_gcp_sa() {
    log_step "Getting GCP Service Account Binding"
    
    GCP_SA=$(kubectl get serviceaccount "$KSA" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null)
    
    if [ -z "$GCP_SA" ]; then
        log_error "No GCP ServiceAccount annotation found on KSA '$KSA'"
        log_info "Expected annotation: iam.gke.io/gcp-service-account"
        
        if [ "$FIX_MODE" = true ]; then
            log_info "Fix mode: Would add annotation (not implemented yet)"
        fi
        
        exit 1
    fi
    
    log_success "GCP ServiceAccount: $GCP_SA"
    
    # Verify GCP SA exists
    if ! gcloud iam service-accounts describe "$GCP_SA" --project="$PROJECT_ID" &>/dev/null; then
        log_error "GCP ServiceAccount '$GCP_SA' does not exist in project '$PROJECT_ID'"
        exit 1
    fi
    
    log_success "GCP ServiceAccount exists and is accessible"
}

# Check GCP SA IAM roles at project level
check_gcp_sa_roles() {
    log_step "Checking GCP ServiceAccount IAM Roles"
    
    log_info "Project-level roles for $GCP_SA:"
    
    local roles=$(gcloud projects get-iam-policy "$PROJECT_ID" \
        --flatten="bindings[].members" \
        --format='value(bindings.role)' \
        --filter="bindings.members:$GCP_SA" 2>/dev/null)
    
    if [ -z "$roles" ]; then
        log_warning "No project-level IAM roles found for $GCP_SA"
    else
        echo "$roles" | while read -r role; do
            if [ -n "$role" ]; then
                log_info "  - $role"
            fi
        done
        
        # Check for Secret Manager accessor role
        if echo "$roles" | grep -q "roles/secretmanager.secretAccessor"; then
            log_success "Found secretmanager.secretAccessor role"
        else
            log_warning "Missing roles/secretmanager.secretAccessor role"
            
            if [ "$FIX_MODE" = true ]; then
                log_info "Fix mode: Adding secretmanager.secretAccessor role..."
                gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                    --member="serviceAccount:$GCP_SA" \
                    --role="roles/secretmanager.secretAccessor"
            fi
        fi
    fi
}

# Check Workload Identity binding
check_workload_identity() {
    log_step "Checking Workload Identity Binding"
    
    log_info "Checking workloadIdentityUser binding for $GCP_SA..."
    
    local wi_members=$(gcloud iam service-accounts get-iam-policy "$GCP_SA" \
        --project="$PROJECT_ID" \
        --format=json 2>/dev/null | \
        jq -r '.bindings[]? | select(.role=="roles/iam.workloadIdentityUser") | .members[]?' 2>/dev/null)
    
    local expected_member="serviceAccount:$PROJECT_ID.svc.id.goog[$NAMESPACE/$KSA]"
    
    if [ -z "$wi_members" ]; then
        log_error "No workloadIdentityUser bindings found for $GCP_SA"
        log_info "Expected binding: $expected_member"
        
        if [ "$FIX_MODE" = true ]; then
            log_info "Fix mode: Adding Workload Identity binding..."
            gcloud iam service-accounts add-iam-policy-binding "$GCP_SA" \
                --role="roles/iam.workloadIdentityUser" \
                --member="$expected_member" \
                --project="$PROJECT_ID"
        fi
        
        exit 1
    fi
    
    log_info "Found workloadIdentityUser bindings:"
    echo "$wi_members" | while read -r member; do
        if [ -n "$member" ]; then
            log_info "  - $member"
            if [ "$member" = "$expected_member" ]; then
                log_success "✓ Correct binding found: $member"
            fi
        fi
    done
    
    if echo "$wi_members" | grep -q "$expected_member"; then
        log_success "Workload Identity binding is correct"
    else
        log_error "Expected binding not found: $expected_member"
        exit 1
    fi
}

# Get API name and find related secrets
find_related_secrets() {
    if [ "$CHECK_SECRETS" = false ]; then
        log_info "Skipping secret checks (--skip-secrets flag used)"
        return
    fi
    
    log_step "Finding Related Secrets"
    
    # Get API name from deployment labels
    API_NAME_WITH_VERSION=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.app}' 2>/dev/null)
    
    if [ -z "$API_NAME_WITH_VERSION" ]; then
        API_NAME_WITH_VERSION="$DEPLOYMENT_NAME"
        log_warning "No app label found, using deployment name: $API_NAME_WITH_VERSION"
    else
        log_info "Found app label: $API_NAME_WITH_VERSION"
    fi
    
    # Remove version suffix (pattern: -X-Y-Z)
    API_NAME=$(echo "$API_NAME_WITH_VERSION" | sed -E 's/-[0-9]+-[0-9]+-[0-9]+$//')
    log_info "API name without version: $API_NAME"
    
    # Find secrets containing the API name
    log_info "Searching for secrets containing '$API_NAME'..."
    
    local secrets=$(gcloud secrets list --filter="name~$API_NAME" --format="value(name)" --project="$PROJECT_ID" 2>/dev/null)
    
    if [ -z "$secrets" ]; then
        log_warning "No secrets found containing '$API_NAME'"
        
        # Try broader search
        log_info "Trying broader search with deployment name..."
        secrets=$(gcloud secrets list --filter="name~$DEPLOYMENT_NAME" --format="value(name)" --project="$PROJECT_ID" 2>/dev/null)
        
        if [ -z "$secrets" ]; then
            log_warning "No secrets found for deployment '$DEPLOYMENT_NAME'"
            return
        fi
    fi
    
    log_success "Found related secrets:"
    echo "$secrets" | while read -r secret; do
        if [ -n "$secret" ]; then
            log_info "  - $secret"
        fi
    done
    
    # Check permissions for each secret
    echo "$secrets" | while read -r secret; do
        if [ -n "$secret" ]; then
            check_secret_permissions "$secret"
        fi
    done
}

# Check secret-level permissions
check_secret_permissions() {
    local secret_name="$1"
    
    log_step "Checking Permissions for Secret: $secret_name"
    
    # Check if secret exists
    if ! gcloud secrets describe "$secret_name" --project="$PROJECT_ID" &>/dev/null; then
        log_error "Secret '$secret_name' does not exist"
        return
    fi
    
    # Get secret IAM policy
    local secret_policy=$(gcloud secrets get-iam-policy "$secret_name" --project="$PROJECT_ID" --format=json 2>/dev/null)
    
    if [ -z "$secret_policy" ] || [ "$secret_policy" = "{}" ]; then
        log_warning "No IAM policy found for secret '$secret_name'"
        
        if [ "$FIX_MODE" = true ]; then
            log_info "Fix mode: Adding secretAccessor permission to secret..."
            gcloud secrets add-iam-policy-binding "$secret_name" \
                --member="serviceAccount:$GCP_SA" \
                --role="roles/secretmanager.secretAccessor" \
                --project="$PROJECT_ID"
        fi
        
        return
    fi
    
    # Check if GSA has access to this secret
    local has_access=$(echo "$secret_policy" | jq -r --arg gsa "$GCP_SA" \
        '.bindings[]? | select(.role=="roles/secretmanager.secretAccessor") | .members[]? | select(. == ("serviceAccount:" + $gsa))' 2>/dev/null)
    
    if [ -n "$has_access" ]; then
        log_success "✓ $GCP_SA has secretAccessor permission for '$secret_name'"
    else
        log_error "✗ $GCP_SA does NOT have secretAccessor permission for '$secret_name'"
        
        if [ "$FIX_MODE" = true ]; then
            log_info "Fix mode: Adding secretAccessor permission..."
            gcloud secrets add-iam-policy-binding "$secret_name" \
                --member="serviceAccount:$GCP_SA" \
                --role="roles/secretmanager.secretAccessor" \
                --project="$PROJECT_ID"
        fi
    fi
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_debug "Full IAM policy for secret '$secret_name':"
        echo "$secret_policy" | jq '.'
    fi
}

# Test secret access from pod
test_secret_access() {
    log_step "Testing Secret Access from Pod"
    
    # Get a running pod from the deployment
    local pod=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$pod" ]; then
        log_warning "No running pods found for deployment '$DEPLOYMENT_NAME'"
        return
    fi
    
    log_info "Testing from pod: $pod"
    
    # Test metadata server access
    log_info "Testing metadata server access..."
    local token_test=$(kubectl exec "$pod" -n "$NAMESPACE" -- \
        curl -s -H "Metadata-Flavor: Google" \
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" 2>/dev/null)
    
    if echo "$token_test" | grep -q "access_token"; then
        log_success "✓ Metadata server access working"
    else
        log_error "✗ Metadata server access failed"
        log_debug "Response: $token_test"
    fi
    
    # Test gcloud auth
    log_info "Testing gcloud authentication in pod..."
    local auth_test=$(kubectl exec "$pod" -n "$NAMESPACE" -- \
        gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
    
    if [ -n "$auth_test" ]; then
        log_success "✓ gcloud authentication working: $auth_test"
    else
        log_warning "gcloud not available or authentication failed in pod"
    fi
}

# Generate summary report
generate_summary() {
    log_step "Verification Summary"
    
    echo -e "\n${CYAN}Configuration Summary:${NC}"
    echo "  Project ID: $PROJECT_ID"
    echo "  Deployment: $DEPLOYMENT_NAME"
    echo "  Namespace: $NAMESPACE"
    echo "  Kubernetes SA: $KSA"
    echo "  GCP SA: $GCP_SA"
    
    echo -e "\n${CYAN}Next Steps:${NC}"
    if [ "$FIX_MODE" = true ]; then
        log_info "Fix mode was enabled - check above for any fixes applied"
    else
        log_info "Run with --fix flag to attempt automatic fixes for common issues"
    fi
    
    log_info "For detailed debugging, run with --debug --verbose flags"
    log_info "To test the application, try accessing the Secret Manager API from within a pod"
}

# Main execution
main() {
    echo -e "${BLUE}GCP Secret Manager Service Account Verification Tool${NC}\n"
    
    parse_arguments "$@"
    
    check_prerequisites
    validate_gcp_auth
    check_deployment
    get_kubernetes_sa
    get_gcp_sa
    check_gcp_sa_roles
    check_workload_identity
    find_related_secrets
    test_secret_access
    generate_summary
    
    log_success "Verification completed successfully!"
}

# Execute main function with all arguments
main "$@"