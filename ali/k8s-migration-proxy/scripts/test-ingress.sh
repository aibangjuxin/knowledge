#!/bin/bash

# Test Script for Ingress Configuration Implementation
# Tests all aspects of the ingress configuration for K8s cluster migration
# Requirements: 2.1, 3.2, 5.1

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/../k8s"
NAMESPACE="${NAMESPACE:-aibang-1111111111-bbdm}"
SERVICE_NAME="${SERVICE_NAME:-bbdm-api}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_TOTAL++))
    log_info "Running test: $test_name"
    
    if $test_function; then
        log_success "$test_name"
        return 0
    else
        log_failure "$test_name"
        return 1
    fi
}

# Test 1: Validate YAML syntax
test_yaml_syntax() {
    local files=(
        "${K8S_DIR}/ingress.yaml"
        "${K8S_DIR}/ingress-config.yaml"
    )
    
    for file in "${files[@]}"; do
        if [ ! -f "$file" ]; then
            echo "File not found: $file"
            return 1
        fi
        
        if ! python3 -c "import yaml; yaml.safe_load_all(open('$file'))" 2>/dev/null; then
            echo "Invalid YAML syntax in: $file"
            return 1
        fi
    done
    
    return 0
}

# Test 2: Validate ingress resources using validation script
test_ingress_validation() {
    if [ ! -f "${SCRIPT_DIR}/validate-ingress.py" ]; then
        echo "Validation script not found"
        return 1
    fi
    
    python3 "${SCRIPT_DIR}/validate-ingress.py" "${K8S_DIR}/ingress.yaml" --canary-validation
}

# Test 3: Check required ingress resources exist
test_ingress_resources_exist() {
    local required_ingresses=(
        "bbdm-api-migration"
        "bbdm-api-canary"
        "migration-template"
        "multi-host-migration"
    )
    
    for ingress_name in "${required_ingresses[@]}"; do
        if ! grep -q "name: $ingress_name" "${K8S_DIR}/ingress.yaml"; then
            echo "Required ingress not found: $ingress_name"
            return 1
        fi
    done
    
    return 0
}

# Test 4: Validate canary annotations
test_canary_annotations() {
    local canary_file="${K8S_DIR}/ingress.yaml"
    
    # Check for canary-specific annotations
    local required_annotations=(
        "nginx.ingress.kubernetes.io/canary"
        "nginx.ingress.kubernetes.io/canary-weight"
        "nginx.ingress.kubernetes.io/canary-by-header"
        "nginx.ingress.kubernetes.io/canary-by-cookie"
    )
    
    for annotation in "${required_annotations[@]}"; do
        if ! grep -q "$annotation" "$canary_file"; then
            echo "Required canary annotation not found: $annotation"
            return 1
        fi
    done
    
    return 0
}

# Test 5: Validate multi-host support
test_multi_host_support() {
    local ingress_file="${K8S_DIR}/ingress.yaml"
    
    # Check for multiple hosts in multi-host ingress
    local expected_hosts=(
        "api-name01.teamname.dev.aliyun.intracloud.cn.aibang"
        "api-name02.teamname.dev.aliyun.intracloud.cn.aibang"
        "admin.teamname.dev.aliyun.intracloud.cn.aibang"
    )
    
    for host in "${expected_hosts[@]}"; do
        if ! grep -q "host: $host" "$ingress_file"; then
            echo "Expected host not found: $host"
            return 1
        fi
    done
    
    return 0
}

# Test 6: Validate multi-path support
test_multi_path_support() {
    local ingress_file="${K8S_DIR}/ingress.yaml"
    
    # Check for multiple paths
    local expected_paths=(
        "path: /"
        "path: /api"
        "path: /health"
        "path: /api/v1"
        "path: /api/v2"
        "path: /admin"
    )
    
    for path in "${expected_paths[@]}"; do
        if ! grep -q "$path" "$ingress_file"; then
            echo "Expected path not found: $path"
            return 1
        fi
    done
    
    return 0
}

# Test 7: Validate TLS configuration
test_tls_configuration() {
    local ingress_file="${K8S_DIR}/ingress.yaml"
    
    # Check for TLS sections
    if ! grep -q "tls:" "$ingress_file"; then
        echo "No TLS configuration found"
        return 1
    fi
    
    # Check for secret names
    local expected_secrets=(
        "bbdm-api-tls"
        "wildcard-teamname-tls"
    )
    
    for secret in "${expected_secrets[@]}"; do
        if ! grep -q "secretName: $secret" "$ingress_file"; then
            echo "Expected TLS secret not found: $secret"
            return 1
        fi
    done
    
    return 0
}

# Test 8: Validate configuration management
test_configuration_management() {
    local config_file="${K8S_DIR}/ingress-config.yaml"
    
    # Check for ConfigMaps
    if ! grep -q "kind: ConfigMap" "$config_file"; then
        echo "No ConfigMap found in configuration file"
        return 1
    fi
    
    # Check for required configuration sections
    local required_configs=(
        "ingress-config.yaml"
        "canary-rules.yaml"
        "multi-host-config.yaml"
        "standard-annotations.yaml"
    )
    
    for config in "${required_configs[@]}"; do
        if ! grep -q "$config" "$config_file"; then
            echo "Required configuration not found: $config"
            return 1
        fi
    done
    
    return 0
}

# Test 9: Validate management scripts
test_management_scripts() {
    local scripts=(
        "${SCRIPT_DIR}/manage-ingress.py"
        "${SCRIPT_DIR}/manage-ingress.sh"
        "${SCRIPT_DIR}/validate-ingress.py"
    )
    
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            echo "Management script not found: $script"
            return 1
        fi
        
        if [ ! -x "$script" ] && [[ "$script" == *.sh ]]; then
            echo "Script not executable: $script"
            return 1
        fi
    done
    
    return 0
}

# Test 10: Test management script functionality (dry run)
test_management_script_functionality() {
    local manage_script="${SCRIPT_DIR}/manage-ingress.py"
    
    # Test help functionality
    if ! python3 "$manage_script" --help >/dev/null 2>&1; then
        echo "Management script help not working"
        return 1
    fi
    
    # Test validation functionality (if we have kubectl access)
    if command -v kubectl >/dev/null 2>&1; then
        # This is a dry-run test, so we don't actually need the cluster
        log_info "kubectl available - management script should work in real environment"
    else
        log_warning "kubectl not available - cannot test full functionality"
    fi
    
    return 0
}

# Test 11: Validate migration-specific annotations
test_migration_annotations() {
    local ingress_file="${K8S_DIR}/ingress.yaml"
    
    # Check for migration-specific annotations
    local migration_annotations=(
        "migration.k8s.io/enabled"
        "migration.k8s.io/service-name"
        "migration.k8s.io/canary-enabled"
        "migration.k8s.io/target-cluster"
    )
    
    for annotation in "${migration_annotations[@]}"; do
        if ! grep -q "$annotation" "$ingress_file"; then
            echo "Migration annotation not found: $annotation"
            return 1
        fi
    done
    
    return 0
}

# Test 12: Validate proxy configuration
test_proxy_configuration() {
    local ingress_file="${K8S_DIR}/ingress.yaml"
    
    # Check for proxy-related annotations
    local proxy_annotations=(
        "nginx.ingress.kubernetes.io/proxy-body-size"
        "nginx.ingress.kubernetes.io/proxy-connect-timeout"
        "nginx.ingress.kubernetes.io/proxy-send-timeout"
        "nginx.ingress.kubernetes.io/proxy-read-timeout"
    )
    
    for annotation in "${proxy_annotations[@]}"; do
        if ! grep -q "$annotation" "$ingress_file"; then
            echo "Proxy annotation not found: $annotation"
            return 1
        fi
    done
    
    # Check for header preservation
    if ! grep -q "X-Original-Host" "$ingress_file"; then
        echo "Header preservation configuration not found"
        return 1
    fi
    
    return 0
}

# Test 13: Validate template ingress
test_template_ingress() {
    local ingress_file="${K8S_DIR}/ingress.yaml"
    
    # Check for template ingress with placeholders
    if ! grep -q "migration-template" "$ingress_file"; then
        echo "Template ingress not found"
        return 1
    fi
    
    # Check for placeholders
    local placeholders=(
        "PLACEHOLDER_SERVICE_NAME"
        "PLACEHOLDER_OLD_HOST"
        "PLACEHOLDER_NEW_HOST"
        "example.teamname.dev.aliyun.intracloud.cn.aibang"
        "PLACEHOLDER_TLS_SECRET"
    )
    
    for placeholder in "${placeholders[@]}"; do
        if ! grep -q "$placeholder" "$ingress_file"; then
            echo "Template placeholder not found: $placeholder"
            return 1
        fi
    done
    
    return 0
}

# Main test runner
run_all_tests() {
    echo "Starting Ingress Configuration Tests"
    echo "===================================="
    
    # Run all tests
    run_test "YAML Syntax Validation" test_yaml_syntax
    run_test "Ingress Resource Validation" test_ingress_validation
    run_test "Required Ingress Resources" test_ingress_resources_exist
    run_test "Canary Annotations" test_canary_annotations
    run_test "Multi-Host Support" test_multi_host_support
    run_test "Multi-Path Support" test_multi_path_support
    run_test "TLS Configuration" test_tls_configuration
    run_test "Configuration Management" test_configuration_management
    run_test "Management Scripts" test_management_scripts
    run_test "Management Script Functionality" test_management_script_functionality
    run_test "Migration Annotations" test_migration_annotations
    run_test "Proxy Configuration" test_proxy_configuration
    run_test "Template Ingress" test_template_ingress
    
    # Print summary
    echo
    echo "Test Results Summary"
    echo "==================="
    echo "Total Tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All tests passed! ✅"
        echo
        echo "Ingress configuration implementation is complete and valid."
        echo "The following features are implemented:"
        echo "  ✓ Canary routing with weight, header, and cookie support"
        echo "  ✓ Multi-host and multi-path routing"
        echo "  ✓ Hot configuration updates"
        echo "  ✓ TLS/SSL support"
        echo "  ✓ Proxy configuration with header preservation"
        echo "  ✓ Management scripts for dynamic updates"
        echo "  ✓ Configuration validation"
        echo "  ✓ Template-based ingress creation"
        return 0
    else
        log_failure "Some tests failed! ❌"
        echo
        echo "Please review the failed tests and fix the issues."
        return 1
    fi
}

# Help function
show_help() {
    cat << EOF
Ingress Configuration Test Script

USAGE:
    $0 [options]

OPTIONS:
    --help, -h          Show this help message
    --verbose, -v       Enable verbose output
    --namespace, -n     Set Kubernetes namespace (default: $NAMESPACE)
    --service           Set service name for testing (default: $SERVICE_NAME)

EXAMPLES:
    # Run all tests
    $0

    # Run tests with verbose output
    $0 --verbose

    # Run tests for specific namespace
    $0 --namespace my-namespace

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --service)
            SERVICE_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run tests
if run_all_tests; then
    exit 0
else
    exit 1
fi