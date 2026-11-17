#!/opt/homebrew/bin/bash

# GKE Namespace Statistics Script - Focus on counts and unique values
# Usage: ./get-ns-stats.sh -n <namespace> [-o output_dir]

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
REPORT_FILE="$OUTPUT_DIR/namespace-${NAMESPACE}-stats-${TIMESTAMP}.md"

print_info "Starting statistics analysis for namespace: $NAMESPACE"

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
    kubectl get daemonsets -n "$NAMESPACE" -o json > /tmp/daemonsets.json 2>/dev/null &
    kubectl get statefulsets -n "$NAMESPACE" -o json > /tmp/statefulsets.json 2>/dev/null &
    kubectl get jobs -n "$NAMESPACE" -o json > /tmp/jobs.json 2>/dev/null &
    kubectl get cronjobs -n "$NAMESPACE" -o json > /tmp/cronjobs.json 2>/dev/null &
    
    # Wait for all background jobs to complete
    wait
    
    print_success "All resources fetched successfully"
}

# Function to count and analyze container images
analyze_images() {
    print_info "Analyzing container images..."
    
    echo "# Container Images Statistics" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Collect all images from different workload types
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[].image' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[].image' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[].image' /tmp/statefulsets.json 2>/dev/null
        [ -s /tmp/jobs.json ] && jq -r '.items[].spec.template.spec.containers[].image' /tmp/jobs.json 2>/dev/null
        [ -s /tmp/cronjobs.json ] && jq -r '.items[].spec.jobTemplate.spec.template.spec.containers[].image' /tmp/cronjobs.json 2>/dev/null
    } | sort | uniq -c | sort -nr > /tmp/image_stats.txt
    
    echo "## Image Usage Count" >> "$REPORT_FILE"
    echo "| Count | Image |" >> "$REPORT_FILE"
    echo "|-------|-------|" >> "$REPORT_FILE"
    
    while read -r count image; do
        echo "| $count | $image |" >> "$REPORT_FILE"
    done < /tmp/image_stats.txt
    echo "" >> "$REPORT_FILE"
    
    # Registry analysis
    echo "## Registry Distribution" >> "$REPORT_FILE"
    echo "| Count | Registry |" >> "$REPORT_FILE"
    echo "|-------|----------|" >> "$REPORT_FILE"
    
    awk '{print $2}' /tmp/image_stats.txt | sed 's|/.*||' | sort | uniq -c | sort -nr | while read -r count registry; do
        echo "| $count | $registry |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Total unique images
    local total_images=$(wc -l < /tmp/image_stats.txt)
    echo "**Total unique images:** $total_images" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Function to analyze health probes
analyze_probes() {
    print_info "Analyzing health probes..."
    
    echo "# Health Probes Statistics" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Liveness Probes
    echo "## Liveness Probe Types" >> "$REPORT_FILE"
    echo "| Count | Probe Type |" >> "$REPORT_FILE"
    echo "|-------|------------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.livenessProbe) | 
            if .livenessProbe.httpGet then "httpGet"
            elif .livenessProbe.tcpSocket then "tcpSocket"
            elif .livenessProbe.exec then "exec"
            else "unknown" end' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.livenessProbe) | 
            if .livenessProbe.httpGet then "httpGet"
            elif .livenessProbe.tcpSocket then "tcpSocket"
            elif .livenessProbe.exec then "exec"
            else "unknown" end' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.livenessProbe) | 
            if .livenessProbe.httpGet then "httpGet"
            elif .livenessProbe.tcpSocket then "tcpSocket"
            elif .livenessProbe.exec then "exec"
            else "unknown" end' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count probe_type; do
        echo "| $count | $probe_type |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Readiness Probes
    echo "## Readiness Probe Types" >> "$REPORT_FILE"
    echo "| Count | Probe Type |" >> "$REPORT_FILE"
    echo "|-------|------------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.readinessProbe) | 
            if .readinessProbe.httpGet then "httpGet"
            elif .readinessProbe.tcpSocket then "tcpSocket"
            elif .readinessProbe.exec then "exec"
            else "unknown" end' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.readinessProbe) | 
            if .readinessProbe.httpGet then "httpGet"
            elif .readinessProbe.tcpSocket then "tcpSocket"
            elif .readinessProbe.exec then "exec"
            else "unknown" end' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.readinessProbe) | 
            if .readinessProbe.httpGet then "httpGet"
            elif .readinessProbe.tcpSocket then "tcpSocket"
            elif .readinessProbe.exec then "exec"
            else "unknown" end' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count probe_type; do
        echo "| $count | $probe_type |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Startup Probes
    echo "## Startup Probe Types" >> "$REPORT_FILE"
    echo "| Count | Probe Type |" >> "$REPORT_FILE"
    echo "|-------|------------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.startupProbe) | 
            if .startupProbe.httpGet then "httpGet"
            elif .startupProbe.tcpSocket then "tcpSocket"
            elif .startupProbe.exec then "exec"
            else "unknown" end' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.startupProbe) | 
            if .startupProbe.httpGet then "httpGet"
            elif .startupProbe.tcpSocket then "tcpSocket"
            elif .startupProbe.exec then "exec"
            else "unknown" end' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.startupProbe) | 
            if .startupProbe.httpGet then "httpGet"
            elif .startupProbe.tcpSocket then "tcpSocket"
            elif .startupProbe.exec then "exec"
            else "unknown" end' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count probe_type; do
        echo "| $count | $probe_type |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# Function to analyze service accounts
analyze_service_accounts() {
    print_info "Analyzing service accounts..."
    
    echo "# Service Account Statistics" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "## Service Account Usage" >> "$REPORT_FILE"
    echo "| Count | Service Account |" >> "$REPORT_FILE"
    echo "|-------|-----------------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.serviceAccountName // "default"' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.serviceAccountName // "default"' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.serviceAccountName // "default"' /tmp/statefulsets.json 2>/dev/null
        [ -s /tmp/jobs.json ] && jq -r '.items[].spec.template.spec.serviceAccountName // "default"' /tmp/jobs.json 2>/dev/null
        [ -s /tmp/cronjobs.json ] && jq -r '.items[].spec.jobTemplate.spec.template.spec.serviceAccountName // "default"' /tmp/cronjobs.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count sa; do
        echo "| $count | $sa |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# Function to analyze ports
analyze_ports() {
    print_info "Analyzing container ports..."
    
    echo "# Container Ports Statistics" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "## Port Usage" >> "$REPORT_FILE"
    echo "| Count | Port | Protocol |" >> "$REPORT_FILE"
    echo "|-------|------|----------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.ports) | .ports[] | (.containerPort | tostring) + "/" + (.protocol // "TCP")' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.ports) | .ports[] | (.containerPort | tostring) + "/" + (.protocol // "TCP")' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.ports) | .ports[] | (.containerPort | tostring) + "/" + (.protocol // "TCP")' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count port_proto; do
        local port=$(echo "$port_proto" | cut -d'/' -f1)
        local proto=$(echo "$port_proto" | cut -d'/' -f2)
        echo "| $count | $port | $proto |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# Function to analyze service types
analyze_service_types() {
    print_info "Analyzing service types..."
    
    echo "# Service Types Statistics" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [ -s /tmp/services.json ] && [ "$(jq '.items | length' /tmp/services.json)" -gt 0 ]; then
        echo "## Service Type Distribution" >> "$REPORT_FILE"
        echo "| Count | Service Type |" >> "$REPORT_FILE"
        echo "|-------|--------------|" >> "$REPORT_FILE"
        
        jq -r '.items[].spec.type' /tmp/services.json | sort | uniq -c | sort -nr | while read -r count svc_type; do
            echo "| $count | $svc_type |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
        
        echo "## Service Port Distribution" >> "$REPORT_FILE"
        echo "| Count | Port |" >> "$REPORT_FILE"
        echo "|-------|------|" >> "$REPORT_FILE"
        
        jq -r '.items[].spec.ports[].port' /tmp/services.json | sort -n | uniq -c | sort -nr | while read -r count port; do
            echo "| $count | $port |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    else
        echo "No services found" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
}

# Function to analyze resource requests and limits
analyze_resources() {
    print_info "Analyzing resource requirements..."
    
    echo "# Resource Requirements Statistics" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # CPU Requests
    echo "## CPU Requests Distribution" >> "$REPORT_FILE"
    echo "| Count | CPU Request |" >> "$REPORT_FILE"
    echo "|-------|-------------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.requests.cpu) | .resources.requests.cpu' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.requests.cpu) | .resources.requests.cpu' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.requests.cpu) | .resources.requests.cpu' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count cpu; do
        echo "| $count | $cpu |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Memory Requests
    echo "## Memory Requests Distribution" >> "$REPORT_FILE"
    echo "| Count | Memory Request |" >> "$REPORT_FILE"
    echo "|-------|----------------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.requests.memory) | .resources.requests.memory' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.requests.memory) | .resources.requests.memory' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.requests.memory) | .resources.requests.memory' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count memory; do
        echo "| $count | $memory |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# Function to analyze volume types
analyze_volumes() {
    print_info "Analyzing volume types..."
    
    echo "# Volume Types Statistics" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "## Volume Type Distribution" >> "$REPORT_FILE"
    echo "| Count | Volume Type |" >> "$REPORT_FILE"
    echo "|-------|-------------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.volumes[]? | keys[]' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.volumes[]? | keys[]' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.volumes[]? | keys[]' /tmp/statefulsets.json 2>/dev/null
    } | grep -v "name" | sort | uniq -c | sort -nr | while read -r count vol_type; do
        echo "| $count | $vol_type |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# Function to generate overall statistics
generate_overall_stats() {
    print_info "Generating overall statistics..."
    
    echo "# Overall Resource Statistics" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Count all resource types
    local dep_count=$(jq '.items | length' /tmp/deployments.json 2>/dev/null || echo 0)
    local ds_count=$(jq '.items | length' /tmp/daemonsets.json 2>/dev/null || echo 0)
    local sts_count=$(jq '.items | length' /tmp/statefulsets.json 2>/dev/null || echo 0)
    local job_count=$(jq '.items | length' /tmp/jobs.json 2>/dev/null || echo 0)
    local cj_count=$(jq '.items | length' /tmp/cronjobs.json 2>/dev/null || echo 0)
    local svc_count=$(jq '.items | length' /tmp/services.json 2>/dev/null || echo 0)
    local hpa_count=$(jq '.items | length' /tmp/hpa.json 2>/dev/null || echo 0)
    local cm_count=$(jq '.items | length' /tmp/configmaps.json 2>/dev/null || echo 0)
    local secret_count=$(jq '.items | length' /tmp/secrets.json 2>/dev/null || echo 0)
    local ing_count=$(jq '.items | length' /tmp/ingress.json 2>/dev/null || echo 0)
    local pod_count=$(jq '.items | length' /tmp/pods.json 2>/dev/null || echo 0)
    local pvc_count=$(jq '.items | length' /tmp/pvc.json 2>/dev/null || echo 0)
    local sa_count=$(jq '.items | length' /tmp/serviceaccounts.json 2>/dev/null || echo 0)
    
    echo "## Resource Count Summary" >> "$REPORT_FILE"
    echo "| Resource Type | Count |" >> "$REPORT_FILE"
    echo "|---------------|-------|" >> "$REPORT_FILE"
    echo "| Deployments | $dep_count |" >> "$REPORT_FILE"
    echo "| DaemonSets | $ds_count |" >> "$REPORT_FILE"
    echo "| StatefulSets | $sts_count |" >> "$REPORT_FILE"
    echo "| Jobs | $job_count |" >> "$REPORT_FILE"
    echo "| CronJobs | $cj_count |" >> "$REPORT_FILE"
    echo "| Services | $svc_count |" >> "$REPORT_FILE"
    echo "| HPAs | $hpa_count |" >> "$REPORT_FILE"
    echo "| ConfigMaps | $cm_count |" >> "$REPORT_FILE"
    echo "| Secrets | $secret_count |" >> "$REPORT_FILE"
    echo "| Ingresses | $ing_count |" >> "$REPORT_FILE"
    echo "| Pods | $pod_count |" >> "$REPORT_FILE"
    echo "| PVCs | $pvc_count |" >> "$REPORT_FILE"
    echo "| ServiceAccounts | $sa_count |" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Calculate totals
    local total_workloads=$((dep_count + ds_count + sts_count + job_count + cj_count))
    local total_resources=$((dep_count + ds_count + sts_count + job_count + cj_count + svc_count + hpa_count + cm_count + secret_count + ing_count + pvc_count + sa_count))
    
    echo "**Total Workloads:** $total_workloads" >> "$REPORT_FILE"
    echo "**Total Resources:** $total_resources" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Main execution
main() {
    print_info "Kubernetes Namespace Statistics Analyzer"
    print_info "========================================"
    
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
    echo "# Kubernetes Namespace Statistics Report" > "$REPORT_FILE"
    echo "**Namespace:** $NAMESPACE" >> "$REPORT_FILE"
    echo "**Cluster:** $(kubectl config current-context)" >> "$REPORT_FILE"
    echo "**Generated:** $(date)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Fetch all resources in parallel
    fetch_all_resources
    
    # Generate statistics
    generate_overall_stats
    analyze_images
    analyze_probes
    analyze_service_accounts
    analyze_ports
    analyze_service_types
    analyze_resources
    analyze_volumes
    
    print_success "Statistics analysis complete!"
    print_info "Report saved to: $REPORT_FILE"
    
    # Clean up temp files
    rm -f /tmp/deployments.json /tmp/services.json /tmp/hpa.json /tmp/configmaps.json /tmp/secrets.json /tmp/ingress.json /tmp/pods.json /tmp/serviceaccounts.json /tmp/pvc.json /tmp/daemonsets.json /tmp/statefulsets.json /tmp/jobs.json /tmp/cronjobs.json /tmp/image_stats.txt
}

# Run main function
main "$@"