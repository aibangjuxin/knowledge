```bash
#!/bin/bash

# GKE Namespace Information Extraction Script
# Usage: ./get-ns-information.sh -n <namespace> [-o output_dir]

set -e

# Default values
NAMESPACE=""
OUTPUT_DIR="./migration-info"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    echo "Usage: $0 -n <namespace> [-o output_directory]"
    echo "  -n: Kubernetes namespace to analyze"
    echo "  -o: Output directory (default: ./migration-info)"
    echo "  -h: Show this help message"
    exit 1
}

# Parse command line arguments
while getopts "n:o:h" opt; do
    case $opt in
        n)
            NAMESPACE="$OPTARG"
            ;;
        o)
            OUTPUT_DIR="$OPTARG"
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Check if namespace is provided
if [ -z "$NAMESPACE" ]; then
    print_error "Namespace is required!"
    usage
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
REPORT_FILE="$OUTPUT_DIR/namespace-${NAMESPACE}-report-${TIMESTAMP}.md"

print_info "Starting analysis for namespace: $NAMESPACE"
print_info "Output directory: $OUTPUT_DIR"

# Function to check if namespace exists
check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_error "Namespace '$NAMESPACE' does not exist!"
        exit 1
    fi
}

# Function to get deployment information
get_deployment_info() {
    print_info "Extracting Deployment information..."
    
    echo "# Deployment Information" >> "$REPORT_FILE"
    echo "Generated at: $(date)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o name 2>/dev/null)
    
    if [ -z "$deployments" ]; then
        echo "No deployments found in namespace $NAMESPACE" >> "$REPORT_FILE"
        return
    fi
    
    for deployment in $deployments; do
        local dep_name=$(echo $deployment | cut -d'/' -f2)
        echo "## Deployment: $dep_name" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Basic deployment info
        echo "### Basic Information" >> "$REPORT_FILE"
        kubectl get deployment "$dep_name" -n "$NAMESPACE" -o wide >> "$REPORT_FILE" 2>/dev/null
        echo "" >> "$REPORT_FILE"
        
        # Images
        echo "### Container Images" >> "$REPORT_FILE"
        kubectl get deployment "$dep_name" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[*].image}' | tr ' ' '\n' >> "$REPORT_FILE" 2>/dev/null
        echo "" >> "$REPORT_FILE"
        
        # Service Account
        echo "### Service Account" >> "$REPORT_FILE"
        local sa=$(kubectl get deployment "$dep_name" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null)
        echo "Service Account: ${sa:-default}" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Probes
        echo "### Health Probes" >> "$REPORT_FILE"
        kubectl get deployment "$dep_name" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[*].livenessProbe}' > /tmp/liveness_probe 2>/dev/null
        kubectl get deployment "$dep_name" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[*].readinessProbe}' > /tmp/readiness_probe 2>/dev/null
        kubectl get deployment "$dep_name" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[*].startupProbe}' > /tmp/startup_probe 2>/dev/null
        
        if [ -s /tmp/liveness_probe ]; then
            echo "**Liveness Probe:**" >> "$REPORT_FILE"
            cat /tmp/liveness_probe >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
        
        if [ -s /tmp/readiness_probe ]; then
            echo "**Readiness Probe:**" >> "$REPORT_FILE"
            cat /tmp/readiness_probe >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
        
        if [ -s /tmp/startup_probe ]; then
            echo "**Startup Probe:**" >> "$REPORT_FILE"
            cat /tmp/startup_probe >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
        
        # Container Ports
        echo "### Container Ports" >> "$REPORT_FILE"
        kubectl get deployment "$dep_name" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[*].ports[*]}' >> "$REPORT_FILE" 2>/dev/null
        echo "" >> "$REPORT_FILE"
        
        # Resource Requests/Limits
        echo "### Resource Configuration" >> "$REPORT_FILE"
        kubectl get deployment "$dep_name" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[*].resources}' >> "$REPORT_FILE" 2>/dev/null
        echo "" >> "$REPORT_FILE"
        
        # Environment Variables
        echo "### Environment Variables" >> "$REPORT_FILE"
        kubectl get deployment "$dep_name" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[*].env[*]}' >> "$REPORT_FILE" 2>/dev/null
        echo "" >> "$REPORT_FILE"
        
        # Volume Mounts
        echo "### Volume Mounts" >> "$REPORT_FILE"
        kubectl get deployment "$dep_name" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[*].volumeMounts[*]}' >> "$REPORT_FILE" 2>/dev/null
        echo "" >> "$REPORT_FILE"
        
        echo "---" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
}

# Function to get service information
get_service_info() {
    print_info "Extracting Service information..."
    
    echo "# Service Information" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local services=$(kubectl get services -n "$NAMESPACE" -o name 2>/dev/null)
    
    if [ -z "$services" ]; then
        echo "No services found in namespace $NAMESPACE" >> "$REPORT_FILE"
        return
    fi
    
    for service in $services; do
        local svc_name=$(echo $service | cut -d'/' -f2)
        echo "## Service: $svc_name" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Service details
        kubectl get service "$svc_name" -n "$NAMESPACE" -o wide >> "$REPORT_FILE" 2>/dev/null
        echo "" >> "$REPORT_FILE"
        
        # Service endpoints
        echo "### Endpoints" >> "$REPORT_FILE"
        kubectl get endpoints "$svc_name" -n "$NAMESPACE" >> "$REPORT_FILE" 2>/dev/null
        echo "" >> "$REPORT_FILE"
        
        # Service YAML (key parts)
        echo "### Service Configuration" >> "$REPORT_FILE"
        echo '```yaml' >> "$REPORT_FILE"
        kubectl get service "$svc_name" -n "$NAMESPACE" -o yaml | grep -A 20 "spec:" >> "$REPORT_FILE" 2>/dev/null
        echo '```' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "---" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
}

# Function to get HPA information
get_hpa_info() {
    print_info "Extracting HPA information..."
    
    echo "# HPA (Horizontal Pod Autoscaler) Information" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local hpas=$(kubectl get hpa -n "$NAMESPACE" -o name 2>/dev/null)
    
    if [ -z "$hpas" ]; then
        echo "No HPAs found in namespace $NAMESPACE" >> "$REPORT_FILE"
        return
    fi
    
    for hpa in $hpas; do
        local hpa_name=$(echo $hpa | cut -d'/' -f2)
        echo "## HPA: $hpa_name" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o wide >> "$REPORT_FILE" 2>/dev/null
        echo "" >> "$REPORT_FILE"
        
        echo "### HPA Configuration" >> "$REPORT_FILE"
        echo '```yaml' >> "$REPORT_FILE"
        kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o yaml >> "$REPORT_FILE" 2>/dev/null
        echo '```' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "---" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
}

# Function to get ConfigMap and Secret information
get_config_info() {
    print_info "Extracting ConfigMap and Secret information..."
    
    echo "# ConfigMaps and Secrets" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # ConfigMaps
    echo "## ConfigMaps" >> "$REPORT_FILE"
    local configmaps=$(kubectl get configmaps -n "$NAMESPACE" -o name 2>/dev/null)
    if [ -n "$configmaps" ]; then
        for cm in $configmaps; do
            local cm_name=$(echo $cm | cut -d'/' -f2)
            echo "### ConfigMap: $cm_name" >> "$REPORT_FILE"
            kubectl describe configmap "$cm_name" -n "$NAMESPACE" >> "$REPORT_FILE" 2>/dev/null
            echo "" >> "$REPORT_FILE"
        done
    else
        echo "No ConfigMaps found" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # Secrets (without sensitive data)
    echo "## Secrets" >> "$REPORT_FILE"
    local secrets=$(kubectl get secrets -n "$NAMESPACE" -o name 2>/dev/null)
    if [ -n "$secrets" ]; then
        for secret in $secrets; do
            local secret_name=$(echo $secret | cut -d'/' -f2)
            echo "### Secret: $secret_name" >> "$REPORT_FILE"
            kubectl get secret "$secret_name" -n "$NAMESPACE" -o wide >> "$REPORT_FILE" 2>/dev/null
            echo "" >> "$REPORT_FILE"
        done
    else
        echo "No Secrets found" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# Function to get Ingress information
get_ingress_info() {
    print_info "Extracting Ingress information..."
    
    echo "# Ingress Information" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    local ingresses=$(kubectl get ingress -n "$NAMESPACE" -o name 2>/dev/null)
    
    if [ -z "$ingresses" ]; then
        echo "No Ingresses found in namespace $NAMESPACE" >> "$REPORT_FILE"
        return
    fi
    
    for ingress in $ingresses; do
        local ing_name=$(echo $ingress | cut -d'/' -f2)
        echo "## Ingress: $ing_name" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        kubectl get ingress "$ing_name" -n "$NAMESPACE" -o wide >> "$REPORT_FILE" 2>/dev/null
        echo "" >> "$REPORT_FILE"
        
        echo "### Ingress Configuration" >> "$REPORT_FILE"
        echo '```yaml' >> "$REPORT_FILE"
        kubectl get ingress "$ing_name" -n "$NAMESPACE" -o yaml >> "$REPORT_FILE" 2>/dev/null
        echo '```' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "---" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
}

# Function to get Pod information
get_pod_info() {
    print_info "Extracting Pod information..."
    
    echo "# Pod Information" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "## Pod Status Overview" >> "$REPORT_FILE"
    kubectl get pods -n "$NAMESPACE" -o wide >> "$REPORT_FILE" 2>/dev/null
    echo "" >> "$REPORT_FILE"
    
    echo "## Pod Resource Usage" >> "$REPORT_FILE"
    kubectl top pods -n "$NAMESPACE" >> "$REPORT_FILE" 2>/dev/null || echo "Metrics not available" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Function to export YAML manifests
export_manifests() {
    print_info "Exporting YAML manifests..."
    
    local manifest_dir="$OUTPUT_DIR/manifests-${NAMESPACE}-${TIMESTAMP}"
    mkdir -p "$manifest_dir"
    
    # Export all resources
    local resources=("deployments" "services" "configmaps" "secrets" "hpa" "ingress" "serviceaccounts" "persistentvolumeclaims")
    
    for resource in "${resources[@]}"; do
        local resource_list=$(kubectl get "$resource" -n "$NAMESPACE" -o name 2>/dev/null)
        if [ -n "$resource_list" ]; then
            mkdir -p "$manifest_dir/$resource"
            for item in $resource_list; do
                local item_name=$(echo $item | cut -d'/' -f2)
                kubectl get "$item" -n "$NAMESPACE" -o yaml > "$manifest_dir/$resource/${item_name}.yaml" 2>/dev/null
            done
            print_success "Exported $resource manifests"
        fi
    done
    
    echo "" >> "$REPORT_FILE"
    echo "# Exported Manifests" >> "$REPORT_FILE"
    echo "YAML manifests have been exported to: $manifest_dir" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Function to generate migration checklist
generate_checklist() {
    print_info "Generating migration checklist..."
    
    echo "# Migration Checklist" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "## Pre-Migration Tasks" >> "$REPORT_FILE"
    echo "- [ ] Review all container images and update registry paths" >> "$REPORT_FILE"
    echo "- [ ] Verify service accounts exist in target project" >> "$REPORT_FILE"
    echo "- [ ] Check IAM permissions for service accounts" >> "$REPORT_FILE"
    echo "- [ ] Validate ConfigMaps and Secrets content" >> "$REPORT_FILE"
    echo "- [ ] Review resource requests/limits" >> "$REPORT_FILE"
    echo "- [ ] Check persistent volume requirements" >> "$REPORT_FILE"
    echo "- [ ] Verify network policies and firewall rules" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "## During Migration" >> "$REPORT_FILE"
    echo "- [ ] Apply manifests in correct order (ConfigMaps/Secrets first)" >> "$REPORT_FILE"
    echo "- [ ] Monitor pod startup and health probes" >> "$REPORT_FILE"
    echo "- [ ] Verify service endpoints are healthy" >> "$REPORT_FILE"
    echo "- [ ] Test ingress connectivity" >> "$REPORT_FILE"
    echo "- [ ] Validate HPA functionality" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "## Post-Migration" >> "$REPORT_FILE"
    echo "- [ ] Update DNS records" >> "$REPORT_FILE"
    echo "- [ ] Monitor application logs" >> "$REPORT_FILE"
    echo "- [ ] Verify all integrations work correctly" >> "$REPORT_FILE"
    echo "- [ ] Update monitoring and alerting" >> "$REPORT_FILE"
    echo "- [ ] Clean up old resources" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Main execution
main() {
    print_info "Kubernetes Migration Information Extractor"
    print_info "=========================================="
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if connected to cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Not connected to a Kubernetes cluster"
        exit 1
    fi
    
    # Check namespace exists
    check_namespace
    
    print_info "Current cluster: $(kubectl config current-context)"
    print_info "Analyzing namespace: $NAMESPACE"
    
    # Initialize report file
    echo "# Kubernetes Migration Report" > "$REPORT_FILE"
    echo "**Namespace:** $NAMESPACE" >> "$REPORT_FILE"
    echo "**Cluster:** $(kubectl config current-context)" >> "$REPORT_FILE"
    echo "**Generated:** $(date)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Extract information
    get_deployment_info
    get_service_info
    get_hpa_info
    get_config_info
    get_ingress_info
    get_pod_info
    export_manifests
    generate_checklist
    
    print_success "Analysis complete!"
    print_info "Report saved to: $REPORT_FILE"
    print_info "Manifests exported to: $OUTPUT_DIR/manifests-${NAMESPACE}-${TIMESTAMP}/"
    
    # Clean up temp files
    rm -f /tmp/liveness_probe /tmp/readiness_probe /tmp/startup_probe
}

# Run main function
main "$@"
```