#!/opt/homebrew/bin/bash

# Gemini Enhanced GKE Namespace Statistics Script - Comprehensive migration analysis
#
# This script provides a comprehensive analysis of a Kubernetes namespace, generating
# a detailed Markdown report to aid in migration planning. It expands on the original
# by adding deeper analysis of Ingresses, Secret types, GKE Workload Identity, and
# how configurations and secrets are consumed by applications.
#
# Usage: ./get-ns-stats-gemini.sh -n <namespace> [-o output_dir]
#
set -eo pipefail

# --- Default values and Configuration ---
NAMESPACE=""
OUTPUT_DIR="./migration-info"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# --- Colors for output ---
RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
BLUE='[0;34m'
NC='[0m' # No Color

# --- Script Functions ---

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to show usage
usage() {
    echo "Usage: $0 -n <namespace> [-o output_directory]"
    echo "  -n: Kubernetes namespace to analyze"
    echo "  -o: Output directory (default: ./migration-info)"
    echo "  -h: Show this help message"
    exit 1
}

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
    
    if ! kubectl get "$resource_type" -n "$namespace" -o json > "$output_file" 2>/dev/null; then
        # If the resource type is not found or no resources exist, create an empty list.
        echo '{"items":[]}' > "$output_file"
    fi
}

# Function to get all resources in one go
fetch_all_resources() {
    local namespace="$1"
    local temp_dir="$2"
    print_info "Fetching all resources from namespace..."
    
    # List of all resources to fetch
    local resources=(
        deployments daemonsets statefulsets jobs cronjobs services endpoints hpa vpa
        configmaps secrets ingress networkpolicies pods serviceaccounts
        persistentvolumeclaims rolebindings roles poddisruptionbudgets
        resourcequotas limitranges
    )
    
    # Fetch all resources in parallel
    for res in "${resources[@]}"; do
        safe_kubectl_get "$res" "$namespace" "$temp_dir/$res.json" &
    done
    
    # Wait for all background jobs to complete
    wait
    print_success "All resources fetched successfully"
}

# Helper function to query standard workloads (Deployments, DaemonSets, StatefulSets)
query_workloads() {
    local jq_filter="$1"
    local temp_dir="$2"
    for file in "$temp_dir/deployments.json" "$temp_dir/daemonsets.json" "$temp_dir/statefulsets.json"; do
        [ -s "$file" ] && jq -r "$jq_filter" "$file" 2>/dev/null
    done
}

# --- Analysis Functions ---

generate_overall_stats() {
    local temp_dir="$1"
    local report_file="$2"
    print_info "Generating overall statistics..."
    
    echo "# Overall Resource Statistics" >> "$report_file"
    echo "" >> "$report_file"
    
    echo "## Resource Count Summary" >> "$report_file"
    echo "| Resource Type | Count |" >> "$report_file"
    echo "|---------------|-------|" >> "$report_file"
    
    local total_resources=0
    for file in "$temp_dir"/*.json; do
        local resource_type=$(basename "$file" .json)
        local count=$(jq '.items | length' "$file")
        printf "| %s | %s |
" "${resource_type^}" "$count" >> "$report_file"
        total_resources=$((total_resources + count))
    done
    
    echo "" >> "$report_file"
    echo "**Total Resources Found:** $total_resources" >> "$report_file"
    echo "" >> "$report_file"
}

analyze_images() {
    local temp_dir="$1"
    local report_file="$2"
    print_info "Analyzing container images..."
    
    echo "# Container Images Statistics" >> "$report_file"
    echo "" >> "$report_file"
    
    local image_stats_file="$temp_dir/image_stats.txt"
    {
        query_workloads '.items[].spec.template.spec.containers[].image' "$temp_dir"
        [ -s "$temp_dir/jobs.json" ] && jq -r '.items[].spec.template.spec.containers[].image' "$temp_dir/jobs.json"
        [ -s "$temp_dir/cronjobs.json" ] && jq -r '.items[].spec.jobTemplate.spec.template.spec.containers[].image' "$temp_dir/cronjobs.json"
    } | sort | uniq -c | sort -nr > "$image_stats_file"
    
    echo "## Image Usage Count" >> "$report_file"
    echo "| Count | Image |" >> "$report_file"
    echo "|-------|-------|" >> "$report_file"
    while read -r count image; do printf '| %s | `%s` |
' "$count" "$image" >> "$report_file"; done < "$image_stats_file"
    echo "" >> "$report_file"
    
    echo "## Registry Distribution" >> "$report_file"
    echo "| Count | Registry | Type |" >> "$report_file"
    echo "|-------|----------|------|" >> "$report_file"
    awk '{print $2}' "$image_stats_file" | while read -r image; do
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
    done | sort | uniq -c | sort -nr | while read -r count registry registry_type;
    do
        printf '| %s | `%s` | %s |
' "$count" "$registry" "$registry_type" >> "$report_file"
    done
    echo "" >> "$report_file"
}

analyze_probes() {
    local temp_dir="$1"
    local report_file="$2"
    print_info "Analyzing health probes..."
    echo "# Health Probes Statistics" >> "$report_file"; echo "" >> "$report_file"

    for probe in livenessProbe readinessProbe startupProbe;
    do
        echo "## ${probe^} Analysis" >> "$report_file"; echo "" >> "$report_file"
        echo "### ${probe^} Types" >> "$report_file"
        echo "| Count | Probe Type |" >> "$report_file"; echo "|-------|------------|" >> "$report_file"
        query_workloads ".items[].spec.template.spec.containers[] | select(.$probe) | if .$probe.httpGet then \"httpGet\" elif .$probe.tcpSocket then \"tcpSocket\" elif .$probe.exec then \"exec\" else \"unknown\" end" "$temp_dir" |
        sort | uniq -c | sort -nr | while read -r count type;
        do
            printf '| %s | %s |
' "$count" "$type" >> "$report_file"
        done
        echo "" >> "$report_file"

        echo "### HTTP ${probe^} Paths" >> "$report_file"
        echo "| Count | Path | Port |" >> "$report_file"; echo "|-------|------|------|" >> "$report_file"
        query_workloads ".items[].spec.template.spec.containers[] | select(.$probe.httpGet) | (.$probe.httpGet.path // \"/\") + \"|\" + (.$probe.httpGet.port | tostring)" "$temp_dir" |
        sort | uniq -c | sort -nr | while read -r count path_port;
        do
            local path=$(echo "$path_port" | cut -d'|' -f1)
            local port=$(echo "$path_port" | cut -d'|' -f2)
            printf '| %s | `%s` | %s |
' "$count" "$path" "$port" >> "$report_file"
        done
        echo "" >> "$report_file"
    done
}

analyze_network_policies() {
    local temp_dir="$1"
    local report_file="$2"
    print_info "Analyzing network policies..."
    echo "# Network Policies Analysis" >> "$report_file"; echo "" >> "$report_file"

    if [ "$(jq '.items | length' "$temp_dir/networkpolicies.json")" -gt 0 ]; then
        echo "## Network Policy Summary" >> "$report_file"
        echo "| Name | Pod Selector | Ingress Rules | Egress Rules |" >> "$report_file"
        echo "|------|--------------|---------------|--------------|" >> "$report_file"
        jq -r '.items[] | [.metadata.name, ((.spec.podSelector.matchLabels // {}) | to_entries | map(.key + "=" + .value) | join(", ") | if . == "" then "All Pods" else . end), ((.spec.ingress // []) | length), ((.spec.egress // []) | length)] | @tsv' "$temp_dir/networkpolicies.json" |
        while IFS=$'\t' read -r name selector ingress egress;
        do
            printf '| %s | `%s` | %s | %s |
' "$name" "$selector" "$ingress" "$egress" >> "$report_file"
        done
    else
        echo "No Network Policies found." >> "$report_file"
    fi
    echo "" >> "$report_file"
}

analyze_rbac_and_identity() {
    local temp_dir="$1"
    local report_file="$2"
    print_info "Analyzing RBAC and Workload Identity..."
    echo "# RBAC and Workload Identity Analysis" >> "$report_file"; echo "" >> "$report_file"

    # Service Accounts & Workload Identity
    if [ "$(jq '.items | length' "$temp_dir/serviceaccounts.json")" -gt 0 ]; then
        echo "## Service Accounts & GKE Workload Identity" >> "$report_file"
        echo "| Name | GKE Workload Identity SA |" >> "$report_file"
        echo "|------|--------------------------|" >> "$report_file"
        jq -r '.items[] | [.metadata.name, (.metadata.annotations["iam.gke.io/gcp-service-account"] // "Not Configured")] | @tsv' "$temp_dir/serviceaccounts.json" |
        while IFS=$'\t' read -r name wi_sa;
        do
            printf '| %s | `%s` |
' "$name" "$wi_sa" >> "$report_file"
        done
    fi
    echo "" >> "$report_file"

    # Role Bindings
    if [ "$(jq '.items | length' "$temp_dir/rolebindings.json")" -gt 0 ]; then
        echo "## Role Bindings" >> "$report_file"
        echo "| Name | Role | Subject Type | Subject Name |" >> "$report_file"
        echo "|------|------|--------------|--------------|" >> "$report_file"
        jq -r '.items[] | (.subjects // [])[] as $subject | [.metadata.name, .roleRef.name, $subject.kind, $subject.name] | @tsv' "$temp_dir/rolebindings.json" |
        while IFS=$'\t' read -r name role type sub_name;
        do
            printf '| %s | %s | %s | %s |
' "$name" "$role" "$type" "$sub_name" >> "$report_file"
        done
    fi
    echo "" >> "$report_file"
}

analyze_service_types() {
    local temp_dir="$1"
    local report_file="$2"
    print_info "Analyzing service types..."
    echo "# Service Types Statistics" >> "$report_file"; echo "" >> "$report_file"

    if [ "$(jq '.items | length' "$temp_dir/services.json")" -gt 0 ]; then
        echo "## Service Type Distribution" >> "$report_file"
        echo "| Count | Service Type |" >> "$report_file"; echo "|-------|--------------|" >> "$report_file"
        jq -r '.items[].spec.type // "ClusterIP"' "$temp_dir/services.json" | sort | uniq -c | sort -nr |
        while read -r count type; do printf '| %s | %s |
' "$count" "$type" >> "$report_file"; done
        echo "" >> "$report_file"

        echo "## Session Affinity" >> "$report_file"
        echo "| Count | Session Affinity |" >> "$report_file"; echo "|-------|------------------|" >> "$report_file"
        jq -r '.items[].spec.sessionAffinity // "None"' "$temp_dir/services.json" | sort | uniq -c | sort -nr |
        while read -r count affinity; do printf '| %s | %s |
' "$count" "$affinity" >> "$report_file"; done
    else
        echo "No services found." >> "$report_file"
    fi
    echo "" >> "$report_file"
}

analyze_ingresses() {
    local temp_dir="$1"
    local report_file="$2"
    print_info "Analyzing Ingress resources..."
    echo "# Ingress Analysis" >> "$report_file"; echo "" >> "$report_file"

    if [ "$(jq '.items | length' "$temp_dir/ingress.json")" -gt 0 ]; then
        echo "## Ingress Summary" >> "$report_file"
        echo "| Name | Class | Hosts | TLS Enabled |" >> "$report_file"
        echo "|------|-------|-------|-------------|" >> "$report_file"
        jq -r '.items[] | [.metadata.name, (.spec.ingressClassName // "default"), (.spec.rules[].host // "N/A"), (if .spec.tls then "Yes" else "No" end)] | @tsv' "$temp_dir/ingress.json" |
        while IFS=$'\t' read -r name class host tls;
        do
            printf '| %s | `%s` | `%s` | %s |
' "$name" "$class" "$host" "$tls" >> "$report_file"
        done
        echo "" >> "$report_file"

        echo "## Ingress Class Distribution" >> "$report_file"
        echo "| Count | Ingress Class |" >> "$report_file"; echo "|-------|---------------|" >> "$report_file"
        jq -r '.items[].spec.ingressClassName // "default"' "$temp_dir/ingress.json" | sort | uniq -c | sort -nr |
        while read -r count class; do printf '| %s | `%s` |
' "$count" "$class" >> "$report_file"; done
    else
        echo "No Ingress resources found." >> "$report_file"
    fi
    echo "" >> "$report_file"
}

analyze_secrets() {
    local temp_dir="$1"
    local report_file="$2"
    print_info "Analyzing Secret resources..."
    echo "# Secret Analysis" >> "$report_file"; echo "" >> "$report_file"

    if [ "$(jq '.items | length' "$temp_dir/secrets.json")" -gt 0 ]; then
        echo "## Secret Type Distribution" >> "$report_file"
        echo "| Count | Secret Type |" >> "$report_file"; echo "|-------|-------------|" >> "$report_file"
        jq -r '.items[].type // "Opaque"' "$temp_dir/secrets.json" | sort | uniq -c | sort -nr |
        while read -r count type; do printf '| %s | `%s` |
' "$count" "$type" >> "$report_file"; done
    else
        echo "No Secret resources found." >> "$report_file"
    fi
    echo "" >> "$report_file"
}

analyze_config_usage() {
    local temp_dir="$1"
    local report_file="$2"
    print_info "Analyzing ConfigMap and Secret usage..."
    echo "# ConfigMap & Secret Usage Analysis" >> "$report_file"; echo "" >> "$report_file"

    echo "## ConfigMap Volume Mounts" >> "$report_file"
    echo "| Count | ConfigMap Name |" >> "$report_file"; echo "|-------|----------------|" >> "$report_file"
    query_workloads '.items[].spec.template.spec.volumes[] | select(.configMap) | .configMap.name' "$temp_dir" |
    sort | uniq -c | sort -nr | while read -r count name; do printf '| %s | `%s` |
' "$count" "$name" >> "$report_file"; done
    echo "" >> "$report_file"

    echo "## Secret Volume Mounts" >> "$report_file"
    echo "| Count | Secret Name |" >> "$report_file"; echo "|-------|-------------|" >> "$report_file"
    query_workloads '.items[].spec.template.spec.volumes[] | select(.secret) | .secret.secretName' "$temp_dir" |
    sort | uniq -c | sort -nr | while read -r count name; do printf '| %s | `%s` |
' "$count" "$name" >> "$report_file"; done
    echo "" >> "$report_file"

    echo "## ConfigMap Environment Variables" >> "$report_file"
    echo "| Count | ConfigMap Name |" >> "$report_file"; echo "|-------|----------------|" >> "$report_file"
    query_workloads '.items[].spec.template.spec.containers[].envFrom[] | select(.configMapRef) | .configMapRef.name' "$temp_dir" |
    sort | uniq -c | sort -nr | while read -r count name; do printf '| %s | `%s` |
' "$count" "$name" >> "$report_file"; done
    echo "" >> "$report_file"

    echo "## Secret Environment Variables" >> "$report_file"
    echo "| Count | Secret Name |" >> "$report_file"; echo "|-------|-------------|" >> "$report_file"
    query_workloads '.items[].spec.template.spec.containers[].envFrom[] | select(.secretRef) | .secretRef.name' "$temp_dir" |
    sort | uniq -c | sort -nr | while read -r count name; do printf '| %s | `%s` |
' "$count" "$name" >> "$report_file"; done
    echo "" >> "$report_file"
}

generate_migration_checklist() {
    local report_file="$1"
    print_info "Generating migration checklist..."
    echo "# Migration Checklist" >> "$report_file"; echo "" >> "$report_file"
    
    echo "### Critical Items to Verify:" >> "$report_file"
    cat <<EOF >> "$report_file"
- [ ] **Container Registries**: Ensure target cluster can pull all images from detected registries (GCR, GAR, Docker Hub, etc.).
- [ ] **Storage Classes**: Verify all `PersistentVolumeClaim` storage classes exist in the target cluster and plan data migration.
- [ ] **Network Policies**: Review and adapt network security policies. The target CNI must support them.
- [ ] **RBAC & Workload Identity**: Ensure Service Accounts, Roles, and especially GKE Workload Identity bindings are correctly configured in the new environment.
- [ ] **Ingresses**: Check for Ingress Class compatibility (e.g., `gce`, `nginx`) and ensure TLS certificates (from cert-manager or secrets) are migrated.
- [ ] **Secrets**: Plan migration for all secret types, especially `kubernetes.io/tls` and `kubernetes.io/dockerconfigjson`.
- [ ] **Node Selectors & Affinity**: Verify node labels and taints in the target cluster match workload scheduling requirements.
- [ ] **External Dependencies**: Check connectivity to external services, databases, or APIs referenced in ConfigMaps or application code.
- [ ] **Resource Quotas & Limits**: Adjust `ResourceQuotas` and `LimitRanges` for the target cluster.
EOF
}

# --- Main Execution ---
main() {
    # --- Argument Parsing ---
    while getopts "n:o:h" opt;
    do
        case $opt in
            n) NAMESPACE="$OPTARG" ;;
            o) OUTPUT_DIR="$OPTARG" ;;
            h) usage ;;
            \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
        esac
    done

    if [ -z "$NAMESPACE" ]; then
        print_error "Namespace is required!"
        usage
    fi

    # --- Initial Checks ---
    print_info "Gemini Enhanced Kubernetes Namespace Analyzer"
    print_info "============================================"
    if ! command -v kubectl &> /dev/null; then print_error "kubectl is not installed or not in PATH"; exit 1; fi
    if ! command -v jq &> /dev/null; then print_error "jq is required but not installed. Please install jq."; exit 1; fi
    if ! kubectl cluster-info &> /dev/null; then print_error "Not connected to a Kubernetes cluster"; exit 1; fi
    
    check_namespace

    # Get context once and store it to prevent repeated calls
    print_info "Fetching cluster context..."
    local current_context
    current_context=$(kubectl config current-context)
    if [ -z "$current_context" ]; then
        print_error "Failed to get current cluster context. 'kubectl config current-context' may be hanging."
        exit 1
    fi

    print_info "Current cluster: $current_context"
    print_info "Analyzing namespace: $NAMESPACE"

    # --- Setup ---
    mkdir -p "$OUTPUT_DIR"
    local report_file="$OUTPUT_DIR/namespace-${NAMESPACE}-gemini-stats-${TIMESTAMP}.md"
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf -- '$temp_dir'" EXIT

    # --- Report Generation ---
    echo "# Gemini Kubernetes Namespace Report" > "$report_file"
    echo "**Namespace:** 
$NAMESPACE
" >> "$report_file"
    echo "**Cluster:** 
$current_context
" >> "$report_file"
    echo "**Generated:** $(date)" >> "$report_file"
    echo "" >> "$report_file"
    
    fetch_all_resources "$NAMESPACE" "$temp_dir"
    
    # --- Run Analysis ---
    generate_overall_stats "$temp_dir" "$report_file"
    analyze_images "$temp_dir" "$report_file"
    analyze_ingresses "$temp_dir" "$report_file"
    analyze_secrets "$temp_dir" "$report_file"
    analyze_config_usage "$temp_dir" "$report_file"
    analyze_service_types "$temp_dir" "$report_file"
    analyze_probes "$temp_dir" "$report_file"
    analyze_network_policies "$temp_dir" "$report_file"
    analyze_rbac_and_identity "$temp_dir" "$report_file"
    # (Add other analysis functions from original script if needed e.g. resources, volumes, scaling)
    generate_migration_checklist "$report_file"
    
    print_success "Analysis complete!"
    print_info "Report saved to: $report_file"
}

# Run main function
main "$@"
