- enhance version
```bash
#!/opt/homebrew/bin/bash

# Enhanced GKE Namespace Statistics Script - Comprehensive migration analysis
# Usage: ./get-ns-stats-kiro-enhance.sh -n <namespace> [-o output_dir]
# NetworkPolicies, Endpoints, RoleBindings, Roles, PodDisruptionBudgets, ResourceQuotas, LimitRanges, VPA
# 
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
REPORT_FILE="$OUTPUT_DIR/namespace-${NAMESPACE}-enhanced-stats-${TIMESTAMP}.md"

print_info "Starting enhanced analysis for namespace: $NAMESPACE"

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

# Function to safely get resources with error handling
safe_kubectl_get() {
    local resource_type="$1"
    local namespace="$2"
    local output_file="$3"
    
    if kubectl get "$resource_type" -n "$namespace" -o json > "$output_file" 2>/dev/null; then
        return 0
    else
        echo '{"items":[]}' > "$output_file"
        return 1
    fi
}

# Function to get all resources in one go
fetch_all_resources() {
    print_info "Fetching all resources from namespace..."
    
    # Fetch all resources in parallel with enhanced coverage
    safe_kubectl_get "deployments" "$NAMESPACE" "/tmp/deployments.json" &
    safe_kubectl_get "daemonsets" "$NAMESPACE" "/tmp/daemonsets.json" &
    safe_kubectl_get "statefulsets" "$NAMESPACE" "/tmp/statefulsets.json" &
    safe_kubectl_get "jobs" "$NAMESPACE" "/tmp/jobs.json" &
    safe_kubectl_get "cronjobs" "$NAMESPACE" "/tmp/cronjobs.json" &
    safe_kubectl_get "services" "$NAMESPACE" "/tmp/services.json" &
    safe_kubectl_get "endpoints" "$NAMESPACE" "/tmp/endpoints.json" &
    safe_kubectl_get "hpa" "$NAMESPACE" "/tmp/hpa.json" &
    safe_kubectl_get "vpa" "$NAMESPACE" "/tmp/vpa.json" &
    safe_kubectl_get "configmaps" "$NAMESPACE" "/tmp/configmaps.json" &
    safe_kubectl_get "secrets" "$NAMESPACE" "/tmp/secrets.json" &
    safe_kubectl_get "ingress" "$NAMESPACE" "/tmp/ingress.json" &
    safe_kubectl_get "networkpolicies" "$NAMESPACE" "/tmp/networkpolicies.json" &
    safe_kubectl_get "pods" "$NAMESPACE" "/tmp/pods.json" &
    safe_kubectl_get "serviceaccounts" "$NAMESPACE" "/tmp/serviceaccounts.json" &
    safe_kubectl_get "persistentvolumeclaims" "$NAMESPACE" "/tmp/pvc.json" &
    safe_kubectl_get "rolebindings" "$NAMESPACE" "/tmp/rolebindings.json" &
    safe_kubectl_get "roles" "$NAMESPACE" "/tmp/roles.json" &
    safe_kubectl_get "poddisruptionbudgets" "$NAMESPACE" "/tmp/pdb.json" &
    safe_kubectl_get "resourcequotas" "$NAMESPACE" "/tmp/resourcequotas.json" &
    safe_kubectl_get "limitranges" "$NAMESPACE" "/tmp/limitranges.json" &
    
    # Wait for all background jobs to complete
    wait
    
    print_success "All resources fetched successfully"
}

# Function to count and analyze container images with registry details
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
    
    # Registry analysis with more details
    echo "## Registry Distribution" >> "$REPORT_FILE"
    echo "| Count | Registry | Type |" >> "$REPORT_FILE"
    echo "|-------|----------|------|" >> "$REPORT_FILE"
    
    awk '{print $2}' /tmp/image_stats.txt | while read -r image; do
        local registry=$(echo "$image" | sed 's|/.*||')
        local registry_type="Unknown"
        
        case "$registry" in
            gcr.io|*.gcr.io) registry_type="Google Container Registry" ;;
            *.pkg.dev) registry_type="Google Artifact Registry" ;;
            docker.io|registry-1.docker.io) registry_type="Docker Hub" ;;
            quay.io) registry_type="Red Hat Quay" ;;
            *.amazonaws.com) registry_type="AWS ECR" ;;
            *.azurecr.io) registry_type="Azure Container Registry" ;;
            localhost*|127.0.0.1*) registry_type="Local Registry" ;;
            *) registry_type="Private/Custom" ;;
        esac
        
        echo "$registry $registry_type"
    done | sort | uniq -c | sort -nr | while read -r count registry registry_type; do
        echo "| $count | $registry | $registry_type |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Image pull policy analysis
    echo "## Image Pull Policy Distribution" >> "$REPORT_FILE"
    echo "| Count | Pull Policy |" >> "$REPORT_FILE"
    echo "|-------|-------------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[].imagePullPolicy // "IfNotPresent"' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[].imagePullPolicy // "IfNotPresent"' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[].imagePullPolicy // "IfNotPresent"' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count policy; do
        echo "| $count | $policy |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Total unique images
    local total_images=$(wc -l < /tmp/image_stats.txt)
    echo "**Total unique images:** $total_images" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Enhanced function to analyze health probes with detailed paths and configurations
analyze_probes() {
    print_info "Analyzing health probes..."
    
    echo "# Health Probes Statistics" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Liveness Probes with detailed analysis
    echo "## Liveness Probe Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "### Liveness Probe Types" >> "$REPORT_FILE"
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
    
    # HTTP Probe Paths Analysis
    echo "### HTTP Liveness Probe Paths" >> "$REPORT_FILE"
    echo "| Count | Path | Port |" >> "$REPORT_FILE"
    echo "|-------|------|------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.livenessProbe.httpGet) | 
            (.livenessProbe.httpGet.path // "/") + "|" + (.livenessProbe.httpGet.port | tostring)' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.livenessProbe.httpGet) | 
            (.livenessProbe.httpGet.path // "/") + "|" + (.livenessProbe.httpGet.port | tostring)' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.livenessProbe.httpGet) | 
            (.livenessProbe.httpGet.path // "/") + "|" + (.livenessProbe.httpGet.port | tostring)' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count path_port; do
        local path=$(echo "$path_port" | cut -d'|' -f1)
        local port=$(echo "$path_port" | cut -d'|' -f2)
        echo "| $count | $path | $port |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Readiness Probes with detailed analysis
    echo "## Readiness Probe Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "### Readiness Probe Types" >> "$REPORT_FILE"
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
    
    # HTTP Readiness Probe Paths
    echo "### HTTP Readiness Probe Paths" >> "$REPORT_FILE"
    echo "| Count | Path | Port |" >> "$REPORT_FILE"
    echo "|-------|------|------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.readinessProbe.httpGet) | 
            (.readinessProbe.httpGet.path // "/") + "|" + (.readinessProbe.httpGet.port | tostring)' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.readinessProbe.httpGet) | 
            (.readinessProbe.httpGet.path // "/") + "|" + (.readinessProbe.httpGet.port | tostring)' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.readinessProbe.httpGet) | 
            (.readinessProbe.httpGet.path // "/") + "|" + (.readinessProbe.httpGet.port | tostring)' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count path_port; do
        local path=$(echo "$path_port" | cut -d'|' -f1)
        local port=$(echo "$path_port" | cut -d'|' -f2)
        echo "| $count | $path | $port |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Startup Probes
    echo "## Startup Probe Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "### Startup Probe Types" >> "$REPORT_FILE"
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
    
    # Probe timing configuration analysis
    echo "## Probe Timing Configuration" >> "$REPORT_FILE"
    echo "| Probe Type | Common Initial Delay | Common Period | Common Timeout |" >> "$REPORT_FILE"
    echo "|------------|---------------------|---------------|----------------|" >> "$REPORT_FILE"
    
    for probe_type in "livenessProbe" "readinessProbe" "startupProbe"; do
        local initial_delay=$(
            {
                [ -s /tmp/deployments.json ] && jq -r ".items[].spec.template.spec.containers[] | select(.$probe_type) | .$probe_type.initialDelaySeconds // 0" /tmp/deployments.json 2>/dev/null
                [ -s /tmp/daemonsets.json ] && jq -r ".items[].spec.template.spec.containers[] | select(.$probe_type) | .$probe_type.initialDelaySeconds // 0" /tmp/daemonsets.json 2>/dev/null
                [ -s /tmp/statefulsets.json ] && jq -r ".items[].spec.template.spec.containers[] | select(.$probe_type) | .$probe_type.initialDelaySeconds // 0" /tmp/statefulsets.json 2>/dev/null
            } | sort -n | uniq -c | sort -nr | head -1 | awk '{print $2}'
        )
        
        local period=$(
            {
                [ -s /tmp/deployments.json ] && jq -r ".items[].spec.template.spec.containers[] | select(.$probe_type) | .$probe_type.periodSeconds // 10" /tmp/deployments.json 2>/dev/null
                [ -s /tmp/daemonsets.json ] && jq -r ".items[].spec.template.spec.containers[] | select(.$probe_type) | .$probe_type.periodSeconds // 10" /tmp/daemonsets.json 2>/dev/null
                [ -s /tmp/statefulsets.json ] && jq -r ".items[].spec.template.spec.containers[] | select(.$probe_type) | .$probe_type.periodSeconds // 10" /tmp/statefulsets.json 2>/dev/null
            } | sort -n | uniq -c | sort -nr | head -1 | awk '{print $2}'
        )
        
        local timeout=$(
            {
                [ -s /tmp/deployments.json ] && jq -r ".items[].spec.template.spec.containers[] | select(.$probe_type) | .$probe_type.timeoutSeconds // 1" /tmp/deployments.json 2>/dev/null
                [ -s /tmp/daemonsets.json ] && jq -r ".items[].spec.template.spec.containers[] | select(.$probe_type) | .$probe_type.timeoutSeconds // 1" /tmp/daemonsets.json 2>/dev/null
                [ -s /tmp/statefulsets.json ] && jq -r ".items[].spec.template.spec.containers[] | select(.$probe_type) | .$probe_type.timeoutSeconds // 1" /tmp/statefulsets.json 2>/dev/null
            } | sort -n | uniq -c | sort -nr | head -1 | awk '{print $2}'
        )
        
        echo "| $probe_type | ${initial_delay:-0}s | ${period:-10}s | ${timeout:-1}s |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# Function to analyze network policies
analyze_network_policies() {
    print_info "Analyzing network policies..."
    
    echo "# Network Policies Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if [ -s /tmp/networkpolicies.json ] && [ "$(jq '.items | length' /tmp/networkpolicies.json)" -gt 0 ]; then
        echo "## Network Policy Summary" >> "$REPORT_FILE"
        echo "| Name | Pod Selector | Ingress Rules | Egress Rules |" >> "$REPORT_FILE"
        echo "|------|--------------|---------------|--------------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            [.metadata.name,
             ((.spec.podSelector.matchLabels // {}) | to_entries | map(.key + "=" + .value) | join(",") | if . == "" then "All Pods" else . end),
             ((.spec.ingress // []) | length),
             ((.spec.egress // []) | length)] |
            @tsv' /tmp/networkpolicies.json | while IFS=$'\t' read -r name selector ingress egress; do
            echo "| $name | $selector | $ingress | $egress |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
        
        # Policy types analysis
        echo "## Policy Types Distribution" >> "$REPORT_FILE"
        echo "| Count | Policy Types |" >> "$REPORT_FILE"
        echo "|-------|--------------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | (.spec.policyTypes // []) | join(",") | if . == "" then "None" else . end' /tmp/networkpolicies.json | sort | uniq -c | sort -nr | while read -r count policy_types; do
            echo "| $count | $policy_types |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    else
        echo "No Network Policies found in namespace $NAMESPACE" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
}

# Function to analyze RBAC
analyze_rbac() {
    print_info "Analyzing RBAC..."
    
    echo "# RBAC Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Service Accounts
    if [ -s /tmp/serviceaccounts.json ] && [ "$(jq '.items | length' /tmp/serviceaccounts.json)" -gt 0 ]; then
        echo "## Service Accounts" >> "$REPORT_FILE"
        echo "| Name | Secrets | Image Pull Secrets |" >> "$REPORT_FILE"
        echo "|------|---------|-------------------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            [.metadata.name,
             (.secrets | length),
             (.imagePullSecrets | length)] |
            @tsv' /tmp/serviceaccounts.json | while IFS=$'\t' read -r name secrets image_secrets; do
            echo "| $name | $secrets | $image_secrets |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
    
    # Role Bindings
    if [ -s /tmp/rolebindings.json ] && [ "$(jq '.items | length' /tmp/rolebindings.json)" -gt 0 ]; then
        echo "## Role Bindings" >> "$REPORT_FILE"
        echo "| Name | Role | Subject Type | Subject Name |" >> "$REPORT_FILE"
        echo "|------|------|--------------|--------------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            (.subjects // [])[] as $subject |
            [.metadata.name, (.roleRef.name // "N/A"), ($subject.kind // "N/A"), ($subject.name // "N/A")] |
            @tsv' /tmp/rolebindings.json 2>/dev/null | while IFS=$'\t' read -r name role subject_type subject_name; do
            echo "| $name | $role | $subject_type | $subject_name |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
    
    # Roles
    if [ -s /tmp/roles.json ] && [ "$(jq '.items | length' /tmp/roles.json)" -gt 0 ]; then
        echo "## Roles" >> "$REPORT_FILE"
        echo "| Name | Rules Count | Resources |" >> "$REPORT_FILE"
        echo "|------|-------------|-----------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            [.metadata.name,
             ((.rules // []) | length),
             ((.rules // []) | map(.resources // []) | flatten | unique | join(",") | if . == "" then "N/A" else . end)] |
            @tsv' /tmp/roles.json | while IFS=$'\t' read -r name rules_count resources; do
            echo "| $name | $rules_count | $resources |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
}

# Function to analyze service accounts usage
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

# Function to analyze ports with enhanced details
analyze_ports() {
    print_info "Analyzing container ports..."
    
    echo "# Container Ports Statistics" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "## Port Usage" >> "$REPORT_FILE"
    echo "| Count | Port | Protocol | Name |" >> "$REPORT_FILE"
    echo "|-------|------|----------|------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.ports) | .ports[] | 
            (.containerPort | tostring) + "/" + (.protocol // "TCP") + "/" + (.name // "unnamed")' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.ports) | .ports[] | 
            (.containerPort | tostring) + "/" + (.protocol // "TCP") + "/" + (.name // "unnamed")' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.ports) | .ports[] | 
            (.containerPort | tostring) + "/" + (.protocol // "TCP") + "/" + (.name // "unnamed")' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count port_info; do
        local port=$(echo "$port_info" | cut -d'/' -f1)
        local proto=$(echo "$port_info" | cut -d'/' -f2)
        local name=$(echo "$port_info" | cut -d'/' -f3)
        echo "| $count | $port | $proto | $name |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# Function to analyze service types with enhanced details
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
        echo "| Count | Port | Target Port | Protocol |" >> "$REPORT_FILE"
        echo "|-------|------|-------------|----------|" >> "$REPORT_FILE"
        
        jq -r '.items[].spec.ports[] | 
            (.port | tostring) + "/" + (.targetPort | tostring) + "/" + (.protocol // "TCP")' /tmp/services.json | 
            sort | uniq -c | sort -nr | while read -r count port_info; do
            local port=$(echo "$port_info" | cut -d'/' -f1)
            local target_port=$(echo "$port_info" | cut -d'/' -f2)
            local protocol=$(echo "$port_info" | cut -d'/' -f3)
            echo "| $count | $port | $target_port | $protocol |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
        
        # Service session affinity
        echo "## Session Affinity Distribution" >> "$REPORT_FILE"
        echo "| Count | Session Affinity |" >> "$REPORT_FILE"
        echo "|-------|------------------|" >> "$REPORT_FILE"
        
        jq -r '.items[].spec.sessionAffinity // "None"' /tmp/services.json | sort | uniq -c | sort -nr | while read -r count affinity; do
            echo "| $count | $affinity |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    else
        echo "No services found" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
}

# Function to analyze resource requests and limits with enhanced details
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
    
    # CPU Limits
    echo "## CPU Limits Distribution" >> "$REPORT_FILE"
    echo "| Count | CPU Limit |" >> "$REPORT_FILE"
    echo "|-------|-----------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.limits.cpu) | .resources.limits.cpu' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.limits.cpu) | .resources.limits.cpu' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.limits.cpu) | .resources.limits.cpu' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count cpu; do
        echo "| $count | $cpu |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Memory Limits
    echo "## Memory Limits Distribution" >> "$REPORT_FILE"
    echo "| Count | Memory Limit |" >> "$REPORT_FILE"
    echo "|-------|--------------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.limits.memory) | .resources.limits.memory' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.limits.memory) | .resources.limits.memory' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | select(.resources.limits.memory) | .resources.limits.memory' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count memory; do
        echo "| $count | $memory |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
}

# Function to analyze volume types with enhanced details
analyze_volumes() {
    print_info "Analyzing volume types..."
    
    echo "# Volume Types Statistics" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "## Volume Type Distribution" >> "$REPORT_FILE"
    echo "| Count | Volume Type |" >> "$REPORT_FILE"
    echo "|-------|-------------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.volumes[]? | keys[] | select(. != "name")' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.volumes[]? | keys[] | select(. != "name")' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.volumes[]? | keys[] | select(. != "name")' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count vol_type; do
        echo "| $count | $vol_type |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # PVC Analysis
    if [ -s /tmp/pvc.json ] && [ "$(jq '.items | length' /tmp/pvc.json)" -gt 0 ]; then
        echo "## Persistent Volume Claims" >> "$REPORT_FILE"
        echo "| Name | Storage Class | Access Mode | Size | Status |" >> "$REPORT_FILE"
        echo "|------|---------------|-------------|------|--------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            [.metadata.name,
             (.spec.storageClassName // "default"),
             (.spec.accessModes | join(",")),
             .spec.resources.requests.storage,
             .status.phase] |
            @tsv' /tmp/pvc.json | while IFS=$'\t' read -r name sc access_mode size status; do
            echo "| $name | $sc | $access_mode | $size | $status |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
}

# Function to analyze scaling configurations
analyze_scaling() {
    print_info "Analyzing scaling configurations..."
    
    echo "# Scaling Configuration Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # HPA Analysis
    if [ -s /tmp/hpa.json ] && [ "$(jq '.items | length' /tmp/hpa.json)" -gt 0 ]; then
        echo "## Horizontal Pod Autoscaler (HPA)" >> "$REPORT_FILE"
        echo "| Name | Target | Min Replicas | Max Replicas | Metrics |" >> "$REPORT_FILE"
        echo "|------|--------|--------------|--------------|---------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            [.metadata.name,
             .spec.scaleTargetRef.name,
             .spec.minReplicas,
             .spec.maxReplicas,
             ((.spec.metrics // []) | length)] |
            @tsv' /tmp/hpa.json | while IFS=$'\t' read -r name target min_replicas max_replicas metrics_count; do
            echo "| $name | $target | $min_replicas | $max_replicas | $metrics_count |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
        
        # HPA Metrics Analysis
        echo "### HPA Metrics Types" >> "$REPORT_FILE"
        echo "| Count | Metric Type |" >> "$REPORT_FILE"
        echo "|-------|-------------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | select(.spec.metrics) | .spec.metrics[]? | select(.type) | .type' /tmp/hpa.json 2>/dev/null | sort | uniq -c | sort -nr | while read -r count metric_type; do
            echo "| $count | $metric_type |" >> "$REPORT_FILE"
        done
        
        # If no metrics found, add a note
        if ! jq -e '.items[] | select(.spec.metrics) | .spec.metrics[]? | select(.type)' /tmp/hpa.json >/dev/null 2>&1; then
            echo "| 0 | No metrics configured |" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
    fi
    
    # VPA Analysis (if available)
    if [ -s /tmp/vpa.json ] && [ "$(jq '.items | length' /tmp/vpa.json)" -gt 0 ]; then
        echo "## Vertical Pod Autoscaler (VPA)" >> "$REPORT_FILE"
        echo "| Name | Target | Update Mode |" >> "$REPORT_FILE"
        echo "|------|--------|-------------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            [.metadata.name,
             (.spec.targetRef.name // "N/A"),
             (.spec.updatePolicy.updateMode // "N/A")] |
            @tsv' /tmp/vpa.json | while IFS=$'\t' read -r name target update_mode; do
            echo "| $name | $target | $update_mode |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
    
    # Pod Disruption Budgets
    if [ -s /tmp/pdb.json ] && [ "$(jq '.items | length' /tmp/pdb.json)" -gt 0 ]; then
        echo "## Pod Disruption Budgets" >> "$REPORT_FILE"
        echo "| Name | Min Available | Max Unavailable | Selector |" >> "$REPORT_FILE"
        echo "|------|---------------|-----------------|----------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            [.metadata.name,
             (.spec.minAvailable // "N/A"),
             (.spec.maxUnavailable // "N/A"),
             ((.spec.selector.matchLabels // {}) | to_entries | map(.key + "=" + .value) | join(",") | if . == "" then "N/A" else . end)] |
            @tsv' /tmp/pdb.json | while IFS=$'\t' read -r name min_available max_unavailable selector; do
            echo "| $name | $min_available | $max_unavailable | $selector |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
}

# Function to analyze resource quotas and limits
analyze_quotas_limits() {
    print_info "Analyzing resource quotas and limits..."
    
    echo "# Resource Quotas and Limits Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Resource Quotas
    if [ -s /tmp/resourcequotas.json ] && [ "$(jq '.items | length' /tmp/resourcequotas.json)" -gt 0 ]; then
        echo "## Resource Quotas" >> "$REPORT_FILE"
        echo "| Name | CPU Limit | Memory Limit | Pods Limit |" >> "$REPORT_FILE"
        echo "|------|-----------|--------------|------------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            [.metadata.name,
             (.spec.hard."limits.cpu" // "N/A"),
             (.spec.hard."limits.memory" // "N/A"),
             (.spec.hard.pods // "N/A")] |
            @tsv' /tmp/resourcequotas.json | while IFS=$'\t' read -r name cpu_limit memory_limit pods_limit; do
            echo "| $name | $cpu_limit | $memory_limit | $pods_limit |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
    
    # Limit Ranges
    if [ -s /tmp/limitranges.json ] && [ "$(jq '.items | length' /tmp/limitranges.json)" -gt 0 ]; then
        echo "## Limit Ranges" >> "$REPORT_FILE"
        echo "| Name | Type | Default CPU | Default Memory | Max CPU | Max Memory |" >> "$REPORT_FILE"
        echo "|------|------|-------------|----------------|---------|------------|" >> "$REPORT_FILE"
        
        jq -r '.items[] | 
            .spec.limits[] as $limit |
            [.metadata.name,
             $limit.type,
             ($limit.default.cpu // "N/A"),
             ($limit.default.memory // "N/A"),
             ($limit.max.cpu // "N/A"),
             ($limit.max.memory // "N/A")] |
            @tsv' /tmp/limitranges.json | while IFS=$'\t' read -r name type default_cpu default_memory max_cpu max_memory; do
            echo "| $name | $type | $default_cpu | $default_memory | $max_cpu | $max_memory |" >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
    fi
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
    local ep_count=$(jq '.items | length' /tmp/endpoints.json 2>/dev/null || echo 0)
    local hpa_count=$(jq '.items | length' /tmp/hpa.json 2>/dev/null || echo 0)
    local vpa_count=$(jq '.items | length' /tmp/vpa.json 2>/dev/null || echo 0)
    local cm_count=$(jq '.items | length' /tmp/configmaps.json 2>/dev/null || echo 0)
    local secret_count=$(jq '.items | length' /tmp/secrets.json 2>/dev/null || echo 0)
    local ing_count=$(jq '.items | length' /tmp/ingress.json 2>/dev/null || echo 0)
    local np_count=$(jq '.items | length' /tmp/networkpolicies.json 2>/dev/null || echo 0)
    local pod_count=$(jq '.items | length' /tmp/pods.json 2>/dev/null || echo 0)
    local pvc_count=$(jq '.items | length' /tmp/pvc.json 2>/dev/null || echo 0)
    local sa_count=$(jq '.items | length' /tmp/serviceaccounts.json 2>/dev/null || echo 0)
    local rb_count=$(jq '.items | length' /tmp/rolebindings.json 2>/dev/null || echo 0)
    local role_count=$(jq '.items | length' /tmp/roles.json 2>/dev/null || echo 0)
    local pdb_count=$(jq '.items | length' /tmp/pdb.json 2>/dev/null || echo 0)
    local rq_count=$(jq '.items | length' /tmp/resourcequotas.json 2>/dev/null || echo 0)
    local lr_count=$(jq '.items | length' /tmp/limitranges.json 2>/dev/null || echo 0)
    
    echo "## Resource Count Summary" >> "$REPORT_FILE"
    echo "| Resource Type | Count |" >> "$REPORT_FILE"
    echo "|---------------|-------|" >> "$REPORT_FILE"
    echo "| Deployments | $dep_count |" >> "$REPORT_FILE"
    echo "| DaemonSets | $ds_count |" >> "$REPORT_FILE"
    echo "| StatefulSets | $sts_count |" >> "$REPORT_FILE"
    echo "| Jobs | $job_count |" >> "$REPORT_FILE"
    echo "| CronJobs | $cj_count |" >> "$REPORT_FILE"
    echo "| Services | $svc_count |" >> "$REPORT_FILE"
    echo "| Endpoints | $ep_count |" >> "$REPORT_FILE"
    echo "| HPAs | $hpa_count |" >> "$REPORT_FILE"
    echo "| VPAs | $vpa_count |" >> "$REPORT_FILE"
    echo "| ConfigMaps | $cm_count |" >> "$REPORT_FILE"
    echo "| Secrets | $secret_count |" >> "$REPORT_FILE"
    echo "| Ingresses | $ing_count |" >> "$REPORT_FILE"
    echo "| NetworkPolicies | $np_count |" >> "$REPORT_FILE"
    echo "| Pods | $pod_count |" >> "$REPORT_FILE"
    echo "| PVCs | $pvc_count |" >> "$REPORT_FILE"
    echo "| ServiceAccounts | $sa_count |" >> "$REPORT_FILE"
    echo "| RoleBindings | $rb_count |" >> "$REPORT_FILE"
    echo "| Roles | $role_count |" >> "$REPORT_FILE"
    echo "| PodDisruptionBudgets | $pdb_count |" >> "$REPORT_FILE"
    echo "| ResourceQuotas | $rq_count |" >> "$REPORT_FILE"
    echo "| LimitRanges | $lr_count |" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Calculate totals
    local total_workloads=$((dep_count + ds_count + sts_count + job_count + cj_count))
    local total_resources=$((dep_count + ds_count + sts_count + job_count + cj_count + svc_count + hpa_count + vpa_count + cm_count + secret_count + ing_count + np_count + pvc_count + sa_count + rb_count + role_count + pdb_count + rq_count + lr_count))
    
    echo "**Total Workloads:** $total_workloads" >> "$REPORT_FILE"
    echo "**Total Resources:** $total_resources" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Function to generate migration-specific analysis
generate_migration_analysis() {
    print_info "Generating migration analysis..."
    
    echo "# Migration-Specific Analysis" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Security contexts analysis
    echo "## Security Context Analysis" >> "$REPORT_FILE"
    echo "| Count | Run As Non Root | Privileged | Read Only Root FS |" >> "$REPORT_FILE"
    echo "|-------|-----------------|------------|-------------------|" >> "$REPORT_FILE"
    
    {
        [ -s /tmp/deployments.json ] && jq -r '.items[].spec.template.spec.containers[] | 
            [(.securityContext.runAsNonRoot // false),
             (.securityContext.privileged // false),
             (.securityContext.readOnlyRootFilesystem // false)] | 
            join("|")' /tmp/deployments.json 2>/dev/null
        [ -s /tmp/daemonsets.json ] && jq -r '.items[].spec.template.spec.containers[] | 
            [(.securityContext.runAsNonRoot // false),
             (.securityContext.privileged // false),
             (.securityContext.readOnlyRootFilesystem // false)] | 
            join("|")' /tmp/daemonsets.json 2>/dev/null
        [ -s /tmp/statefulsets.json ] && jq -r '.items[].spec.template.spec.containers[] | 
            [(.securityContext.runAsNonRoot // false),
             (.securityContext.privileged // false),
             (.securityContext.readOnlyRootFilesystem // false)] | 
            join("|")' /tmp/statefulsets.json 2>/dev/null
    } | sort | uniq -c | sort -nr | while read -r count security_config; do
        local run_as_non_root=$(echo "$security_config" | cut -d'|' -f1)
        local privileged=$(echo "$security_config" | cut -d'|' -f2)
        local read_only_root=$(echo "$security_config" | cut -d'|' -f3)
        echo "| $count | $run_as_non_root | $privileged | $read_only_root |" >> "$REPORT_FILE"
    done
    echo "" >> "$REPORT_FILE"
    
    # Node selector and affinity analysis
    echo "## Node Placement Analysis" >> "$REPORT_FILE"
    echo "| Workload | Node Selector | Affinity | Tolerations |" >> "$REPORT_FILE"
    echo "|----------|---------------|----------|-------------|" >> "$REPORT_FILE"
    
    for workload_file in "/tmp/deployments.json" "/tmp/daemonsets.json" "/tmp/statefulsets.json"; do
        if [ -s "$workload_file" ]; then
            jq -r '.items[] | 
                [(.kind + "/" + .metadata.name),
                 (if .spec.template.spec.nodeSelector then "Yes" else "No" end),
                 (if .spec.template.spec.affinity then "Yes" else "No" end),
                 (.spec.template.spec.tolerations | length)] |
                @tsv' "$workload_file" 2>/dev/null | while IFS=$'\t' read -r workload node_selector affinity tolerations; do
                echo "| $workload | $node_selector | $affinity | $tolerations |" >> "$REPORT_FILE"
            done
        fi
    done
    echo "" >> "$REPORT_FILE"
    
    # Generate migration checklist
    echo "## Migration Checklist" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "### Critical Items to Verify:" >> "$REPORT_FILE"
    echo "- [ ] **Container Registry Access** - Ensure target cluster can pull all images" >> "$REPORT_FILE"
    echo "- [ ] **Storage Classes** - Verify storage classes exist in target cluster" >> "$REPORT_FILE"
    echo "- [ ] **Network Policies** - Review and adapt network security policies" >> "$REPORT_FILE"
    echo "- [ ] **RBAC Configuration** - Ensure service accounts and roles are properly configured" >> "$REPORT_FILE"
    echo "- [ ] **Resource Quotas** - Check if resource quotas need adjustment" >> "$REPORT_FILE"
    echo "- [ ] **Node Selectors** - Verify node labels and selectors compatibility" >> "$REPORT_FILE"
    echo "- [ ] **Persistent Volumes** - Plan data migration strategy for PVCs" >> "$REPORT_FILE"
    echo "- [ ] **Health Check Paths** - Verify probe endpoints are accessible" >> "$REPORT_FILE"
    echo "- [ ] **Security Contexts** - Review security policies and constraints" >> "$REPORT_FILE"
    echo "- [ ] **External Dependencies** - Check external service connectivity" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# Main execution
main() {
    print_info "Enhanced Kubernetes Namespace Statistics Analyzer"
    print_info "================================================"
    
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
    echo "# Enhanced Kubernetes Namespace Statistics Report" > "$REPORT_FILE"
    echo "**Namespace:** $NAMESPACE" >> "$REPORT_FILE"
    echo "**Cluster:** $(kubectl config current-context)" >> "$REPORT_FILE"
    echo "**Generated:** $(date)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Fetch all resources in parallel
    fetch_all_resources
    
    # Generate comprehensive statistics
    generate_overall_stats
    analyze_images
    analyze_probes
    analyze_service_accounts
    analyze_ports
    analyze_service_types
    analyze_resources
    analyze_volumes
    analyze_scaling
    analyze_network_policies
    analyze_rbac
    analyze_quotas_limits
    generate_migration_analysis
    
    print_success "Enhanced analysis complete!"
    print_info "Report saved to: $REPORT_FILE"
    
    # Clean up temp files
    rm -f /tmp/deployments.json /tmp/services.json /tmp/hpa.json /tmp/vpa.json /tmp/configmaps.json /tmp/secrets.json /tmp/ingress.json /tmp/networkpolicies.json /tmp/pods.json /tmp/serviceaccounts.json /tmp/pvc.json /tmp/daemonsets.json /tmp/statefulsets.json /tmp/jobs.json /tmp/cronjobs.json /tmp/image_stats.txt /tmp/endpoints.json /tmp/rolebindings.json /tmp/roles.json /tmp/pdb.json /tmp/resourcequotas.json /tmp/limitranges.json
}

# Run main function
main "$@"
```