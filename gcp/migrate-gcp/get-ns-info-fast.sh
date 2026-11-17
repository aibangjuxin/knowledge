#!/bin/bash

# Fast GKE Namespace Information Extraction Script using JSON parsing
# Usage: ./get-ns-info-fast.sh -n <namespace> [-o output_dir]

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
REPORT_FILE="$OUTPUT_DIR/namespace-${NAMESPACE}-fast-report-${TIMESTAMP}.md"

print_info "Starting fast analysis for namespace: $NAMESPACE"

# Check if jq is available
if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed. Please install jq first."
    exit 1
fi

# Function to check if namespace exists
check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_error "Namespace '$NAMESPACE' does not exist!"
        exit 1
    fi
}

# Function to get all resources in one go
fetch_all_resources() {
    print_info "Fetching all resources from namespace..."
    
    # Fetch all resources in parallel
    kubectl get deployments -n "$NAMESPACE" -o json > /tmp/deployments.json 2>/dev/null &
    kubectl get services -n "$NAMESPACE" -o json > /tmp/services.json 2>/dev/null &
    kubectl get hpa -n "$NAMESPACE" -o json > /tmp/hpa.json 2>/dev/null &
    kubectl get configmaps -n "$NAMESPACE" -o json > /tmp/configmaps.json 2>/dev/null &
    kubectl get secrets -n "$NAMESPACE" -o json > /tmp/secrets.json 2>/dev/null &
    kubectl get ingress -n "$NAMESPACE" -o json > /tmp/ingress.json 2>/dev/null &
    kubectl get pods -n "$NAMESPACE" -o json > /tmp/pods.json 2>/dev/null &
    kubectl get serviceaccounts -n "$NAMESPACE" -o json > /tmp/serviceaccounts.json 2>/dev/null &
    kubectl get persistentvolumeclaims -n "$NAMESPACE" -o json > /tmp/pvc.json 2>/dev/null &
    
    # Wait for all background jobs to complete
    wait
    
    print_success "All resources fetched successfully"
}

# Function to analyze deployments using jq
analyze_deployments() {
    print_info "Analyzing Deployments..."
    
    echo "# Deployment Analysis" >> "$REPORT_FILE"
    echo "Generated at: $(date)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [ ! -s /tmp/deployments.json ] || [ "$(jq '.items | length' /tmp/deployments.json)" -eq 0 ]; then
        echo "No deployments found in namespace $NAMESPACE" >> "$REPORT_FILE"
        return
    fi
    
    # Create deployment summary table
    echo "## Deployment Summary" >> "$REPORT_FILE"
    echo "| Name | Replicas | Ready | Images | Service Account |" >> "$REPORT_FILE"
    echo "|------|----------|-------|--------|-----------------|" >> "$REPORT_FILE"
    
    jq -r '.items[] | 
        [.metadata.name, 
         .spec.replicas, 
         .status.readyReplicas // 0,
         (.spec.template.spec.containers[].image),
         (.spec.template.spec.serviceAccountName // "default")] | 
        @tsv' /tmp/deployments.json | while IFS=$'\t' read -r name replicas ready images sa; do
        echo "| $name | $replicas | $ready | $images | $sa |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Detailed deployment analysis
    echo "## Detailed Deployment Configuration" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    jq -c '.items[]' /tmp/deployments.json | while read -r deployment; do
        local dep_name=$(echo "$deployment" | jq -r '.metadata.name')
        echo "### Deployment: $dep_name" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Container information
        echo "**Container Images:**" >> "$REPORT_FILE"
        echo "$deployment" | jq -r '.spec.template.spec.containers[] | "- " + .image' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Service Account
        local sa=$(echo "$deployment" | jq -r '.spec.template.spec.serviceAccountName // "default"')
        echo "**Service Account:** $sa" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Container Ports
        echo "**Container Ports:**" >> "$REPORT_FILE"
        echo "$deployment" | jq -r '.spec.template.spec.containers[] | 
            select(.ports) | 
            .ports[] | 
            "- " + (.name // "unnamed") + ": " + (.containerPort | tostring) + "/" + (.protocol // "TCP")' >> "$REPORT_FILE" 2>/dev/null || echo "No ports defined" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Health Probes
        echo "**Health Probes:**" >> "$REPORT_FILE"
        echo "$deployment" | jq -r '.spec.template.spec.containers[] | 
            if .livenessProbe then "- Liveness: " + (.livenessProbe | tostring) else empty end,
            if .readinessProbe then "- Readiness: " + (.readinessProbe | tostring) else empty end,
            if .startupProbe then "- Startup: " + (.startupProbe | tostring) else empty end' >> "$REPORT_FILE" 2>/dev/null || echo "No probes configured" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Resource Requirements
        echo "**Resource Requirements:**" >> "$REPORT_FILE"
        echo "$deployment" | jq -r '.spec.template.spec.containers[] | 
            if .resources then 
                "- Requests: " + (.resources.requests // {} | tostring) + "\n" +
                "- Limits: " + (.resources.limits // {} | tostring)
            else "No resource requirements specified" end' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Environment Variables
        echo "**Environment Variables:**" >> "$REPORT_FILE"
        echo "$deployment" | jq -r '.spec.template.spec.containers[] | 
            if .env then 
                .env[] | "- " + .name + ": " + (.value // .valueFrom | tostring)
            else "No environment variables" end' >> "$REPORT_FILE" 2>/dev/null || echo "No environment variables" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Volume Mounts
        echo "**Volume Mounts:**" >> "$REPORT_FILE"
        echo "$deployment" | jq -r '.spec.template.spec.containers[] | 
            if .volumeMounts then 
                .volumeMounts[] | "- " + .name + " -> " + .mountPath
            else "No volume mounts" end' >> "$REPORT_FILE" 2>/dev/null || echo "No volume mounts" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "---" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
}

# Function to analyze services
analyze_services() {
    print_info "Analyzing Services..."
    
    echo "# Service Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [ ! -s /tmp/services.json ] || [ "$(jq '.items | length' /tmp/services.json)" -eq 0 ]; then
        echo "No services found in namespace $NAMESPACE" >> "$REPORT_FILE"
        return
    fi
    
    # Service summary table
    echo "## Service Summary" >> "$REPORT_FILE"
    echo "| Name | Type | Cluster IP | External IP | Ports |" >> "$REPORT_FILE"
    echo "|------|------|------------|-------------|-------|" >> "$REPORT_FILE"
    
    jq -r '.items[] | 
        [.metadata.name,
         .spec.type,
         .spec.clusterIP,
         (.status.loadBalancer.ingress[0].ip // "None"),
         (.spec.ports | map(.port | tostring) | join(","))] |
        @tsv' /tmp/services.json | while IFS=$'\t' read -r name type cluster_ip external_ip ports; do
        echo "| $name | $type | $cluster_ip | $external_ip | $ports |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Detailed service analysis
    echo "## Detailed Service Configuration" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    jq -c '.items[]' /tmp/services.json | while read -r service; do
        local svc_name=$(echo "$service" | jq -r '.metadata.name')
        echo "### Service: $svc_name" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "**Port Configuration:**" >> "$REPORT_FILE"
        echo "$service" | jq -r '.spec.ports[] | 
            "- " + (.name // "unnamed") + ": " + (.port | tostring) + " -> " + (.targetPort | tostring) + "/" + (.protocol // "TCP")' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "**Selector:**" >> "$REPORT_FILE"
        echo "$service" | jq -r '.spec.selector | to_entries[] | "- " + .key + ": " + .value' >> "$REPORT_FILE" 2>/dev/null || echo "No selector" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "---" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
}

# Function to analyze HPA
analyze_hpa() {
    print_info "Analyzing HPA..."
    
    echo "# HPA Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [ ! -s /tmp/hpa.json ] || [ "$(jq '.items | length' /tmp/hpa.json)" -eq 0 ]; then
        echo "No HPAs found in namespace $NAMESPACE" >> "$REPORT_FILE"
        return
    fi
    
    echo "## HPA Summary" >> "$REPORT_FILE"
    echo "| Name | Target | Min Replicas | Max Replicas | Current Replicas |" >> "$REPORT_FILE"
    echo "|------|--------|--------------|--------------|------------------|" >> "$REPORT_FILE"
    
    jq -r '.items[] | 
        [.metadata.name,
         .spec.scaleTargetRef.name,
         .spec.minReplicas,
         .spec.maxReplicas,
         (.status.currentReplicas // 0)] |
        @tsv' /tmp/hpa.json | while IFS=$'\t' read -r name target min_replicas max_replicas current_replicas; do
        echo "| $name | $target | $min_replicas | $max_replicas | $current_replicas |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Detailed HPA configuration
    jq -c '.items[]' /tmp/hpa.json | while read -r hpa; do
        local hpa_name=$(echo "$hpa" | jq -r '.metadata.name')
        echo "### HPA: $hpa_name" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "**Metrics:**" >> "$REPORT_FILE"
        echo "$hpa" | jq -r '.spec.metrics[]? | 
            "- Type: " + .type + 
            (if .resource then " (Resource: " + .resource.name + ", Target: " + (.resource.target.averageUtilization // .resource.target.averageValue | tostring) + ")" else "" end)' >> "$REPORT_FILE" 2>/dev/null || echo "No metrics configured" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "---" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
}

# Function to analyze ConfigMaps and Secrets
analyze_config() {
    print_info "Analyzing ConfigMaps and Secrets..."
    
    echo "# ConfigMaps and Secrets Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # ConfigMaps
    echo "## ConfigMaps" >> "$REPORT_FILE"
    if [ -s /tmp/configmaps.json ] && [ "$(jq '.items | length' /tmp/configmaps.json)" -gt 0 ]; then
        echo "| Name | Keys | Size |" >> "$REPORT_FILE"
        echo "|------|------|------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            [.metadata.name,
             (.data // {} | keys | join(", ")),
             (.data // {} | to_entries | map(.value | length) | add // 0)] |
            @tsv' /tmp/configmaps.json | while IFS=$'\t' read -r name keys size; do
            echo "| $name | $keys | ${size} bytes |" >> "$REPORT_FILE"
        done
    else
        echo "No ConfigMaps found" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
    
    # Secrets
    echo "## Secrets" >> "$REPORT_FILE"
    if [ -s /tmp/secrets.json ] && [ "$(jq '.items | length' /tmp/secrets.json)" -gt 0 ]; then
        echo "| Name | Type | Keys |" >> "$REPORT_FILE"
        echo "|------|------|------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            [.metadata.name,
             .type,
             (.data // {} | keys | join(", "))] |
            @tsv' /tmp/secrets.json | while IFS=$'\t' read -r name type keys; do
            echo "| $name | $type | $keys |" >> "$REPORT_FILE"
        done
    else
        echo "No Secrets found" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# Function to analyze Ingress
analyze_ingress() {
    print_info "Analyzing Ingress..."
    
    echo "# Ingress Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [ ! -s /tmp/ingress.json ] || [ "$(jq '.items | length' /tmp/ingress.json)" -eq 0 ]; then
        echo "No Ingresses found in namespace $NAMESPACE" >> "$REPORT_FILE"
        return
    fi
    
    echo "## Ingress Summary" >> "$REPORT_FILE"
    echo "| Name | Hosts | TLS | Backend Services |" >> "$REPORT_FILE"
    echo "|------|-------|-----|------------------|" >> "$REPORT_FILE"
    
    jq -r '.items[] | 
        [.metadata.name,
         (.spec.rules[]?.host // "None" | tostring),
         (if .spec.tls then "Yes" else "No" end),
         (.spec.rules[]?.http.paths[]?.backend.service.name // "None" | tostring)] |
        @tsv' /tmp/ingress.json | while IFS=$'\t' read -r name hosts tls backends; do
        echo "| $name | $hosts | $tls | $backends |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# Function to analyze Pods
analyze_pods() {
    print_info "Analyzing Pods..."
    
    echo "# Pod Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [ ! -s /tmp/pods.json ] || [ "$(jq '.items | length' /tmp/pods.json)" -eq 0 ]; then
        echo "No Pods found in namespace $NAMESPACE" >> "$REPORT_FILE"
        return
    fi
    
    echo "## Pod Status Summary" >> "$REPORT_FILE"
    echo "| Name | Status | Ready | Restarts | Node |" >> "$REPORT_FILE"
    echo "|------|--------|-------|----------|------|" >> "$REPORT_FILE"
    
    jq -r '.items[] | 
        [.metadata.name,
         .status.phase,
         (.status.containerStatuses[]?.ready // false | tostring),
         (.status.containerStatuses[]?.restartCount // 0),
         (.spec.nodeName // "Unknown")] |
        @tsv' /tmp/pods.json | while IFS=$'\t' read -r name status ready restarts node; do
        echo "| $name | $status | $ready | $restarts | $node |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# Function to generate migration summary
generate_migration_summary() {
    print_info "Generating migration summary..."
    
    echo "# Migration Summary" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Count resources
    local dep_count=$(jq '.items | length' /tmp/deployments.json 2>/dev/null || echo 0)
    local svc_count=$(jq '.items | length' /tmp/services.json 2>/dev/null || echo 0)
    local hpa_count=$(jq '.items | length' /tmp/hpa.json 2>/dev/null || echo 0)
    local cm_count=$(jq '.items | length' /tmp/configmaps.json 2>/dev/null || echo 0)
    local secret_count=$(jq '.items | length' /tmp/secrets.json 2>/dev/null || echo 0)
    local ing_count=$(jq '.items | length' /tmp/ingress.json 2>/dev/null || echo 0)
    local pod_count=$(jq '.items | length' /tmp/pods.json 2>/dev/null || echo 0)
    
    echo "## Resource Count" >> "$REPORT_FILE"
    echo "- Deployments: $dep_count" >> "$REPORT_FILE"
    echo "- Services: $svc_count" >> "$REPORT_FILE"
    echo "- HPAs: $hpa_count" >> "$REPORT_FILE"
    echo "- ConfigMaps: $cm_count" >> "$REPORT_FILE"
    echo "- Secrets: $secret_count" >> "$REPORT_FILE"
    echo "- Ingresses: $ing_count" >> "$REPORT_FILE"
    echo "- Pods: $pod_count" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Extract unique images
    echo "## Container Images to Migrate" >> "$REPORT_FILE"
    if [ -s /tmp/deployments.json ]; then
        jq -r '.items[].spec.template.spec.containers[].image' /tmp/deployments.json | sort -u | while read -r image; do
            echo "- $image" >> "$REPORT_FILE"
        done
    fi
    echo "" >> "$REPORT_FILE"
    
    # Extract unique service accounts
    echo "## Service Accounts to Verify" >> "$REPORT_FILE"
    if [ -s /tmp/deployments.json ]; then
        jq -r '.items[].spec.template.spec.serviceAccountName // "default"' /tmp/deployments.json | sort -u | while read -r sa; do
            echo "- $sa" >> "$REPORT_FILE"
        done
    fi
    echo "" >> "$REPORT_FILE"
    
    echo "## Quick Migration Checklist" >> "$REPORT_FILE"
    echo "- [ ] Update container image registry paths" >> "$REPORT_FILE"
    echo "- [ ] Verify service accounts exist in target project" >> "$REPORT_FILE"
    echo "- [ ] Migrate ConfigMaps and Secrets" >> "$REPORT_FILE"
    echo "- [ ] Update Ingress configurations if needed" >> "$REPORT_FILE"
    echo "- [ ] Verify HPA metrics server availability" >> "$REPORT_FILE"
    echo "- [ ] Test service connectivity" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Main execution
main() {
    print_info "Fast Kubernetes Migration Information Extractor"
    print_info "=============================================="
    
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
    echo "# Fast Kubernetes Migration Report" > "$REPORT_FILE"
    echo "**Namespace:** $NAMESPACE" >> "$REPORT_FILE"
    echo "**Cluster:** $(kubectl config current-context)" >> "$REPORT_FILE"
    echo "**Generated:** $(date)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Fetch all resources in parallel
    fetch_all_resources
    
    # Analyze resources using JSON parsing
    analyze_deployments
    analyze_services
    analyze_hpa
    analyze_config
    analyze_ingress
    analyze_pods
    generate_migration_summary
    
    print_success "Fast analysis complete!"
    print_info "Report saved to: $REPORT_FILE"
    
    # Clean up temp files
    rm -f /tmp/deployments.json /tmp/services.json /tmp/hpa.json /tmp/configmaps.json /tmp/secrets.json /tmp/ingress.json /tmp/pods.json /tmp/serviceaccounts.json /tmp/pvc.json
}

# Run main function
main "$@"