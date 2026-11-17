# Shell Scripts Collection

Generated on: 2026-02-23 11:50:32
Directory: /Users/lex/git/knowledge/gcp/gcp-infor

## `gcpfetch.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
gcpfetch: neofetch-like system info for GCP (bash)

Usage:
  gcpfetch [--full] [--no-logo] [--color|--no-color] [--help]

Options:
  --full      Include extra fields (all resources, detailed info).
  --no-logo   Do not print the ASCII logo.
  --color     Force ANSI colors (even if stdout isn't a TTY).
  --no-color  Disable ANSI colors.
  --help      Show this help.
EOF
}

want_full=false
want_logo=true
want_color=auto

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) want_full=true ;;
    --no-logo) want_logo=false ;;
    --color) want_color=always ;;
    --no-color) want_color=never ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

supports_color() {
  [[ "${want_color}" == "never" ]] && return 1
  [[ "${TERM:-}" == "dumb" ]] && return 1
  [[ "${want_color}" == "always" ]] && return 0
  [[ -t 1 ]] || return 1
  return 0
}

if supports_color; then
  c_reset=$'\033[0m'
  c_dim=$'\033[2m'
  c_key=$'\033[1;33m'
  c_value=$'\033[0;36m'
else
  c_reset=""
  c_dim=""
  c_key=""
  c_value=""
fi

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# Check if gcloud is installed
if ! cmd_exists gcloud; then
  echo "Error: gcloud command not found. Please install Google Cloud SDK." >&2
  exit 1
fi

get_project() {
  gcloud config get-value project 2>/dev/null || echo "N/A"
}

get_account() {
  gcloud config get-value account 2>/dev/null || echo "N/A"
}

get_region() {
  gcloud config get-value compute/region 2>/dev/null || echo "N/A"
}

get_zone() {
  gcloud config get-value compute/zone 2>/dev/null || echo "N/A"
}

get_gce_instances() {
  local count names
  count="$(gcloud compute instances list --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$count" == "0" ]]; then
    echo "0"
  else
    names="$(gcloud compute instances list --format='value(name)' 2>/dev/null | head -n 5 | paste -sd, - | sed 's/,/, /g')"
    if [[ "$count" -gt 5 ]]; then
      echo "$count ($names, ...)"
    else
      echo "$count ($names)"
    fi
  fi
}

get_secrets() {
  local count names
  count="$(gcloud secrets list --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$count" == "0" ]]; then
    echo "0"
  else
    names="$(gcloud secrets list --format='value(name)' 2>/dev/null | head -n 10 | paste -sd, - | sed 's/,/, /g')"
    if [[ "$count" -gt 10 ]]; then
      echo "$count (first 10: $names, ...)"
    else
      echo "$count ($names)"
    fi
  fi
}

get_gke_clusters() {
  local count names
  count="$(gcloud container clusters list --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$count" == "0" ]]; then
    echo "0"
  else
    names="$(gcloud container clusters list --format='value(name)' 2>/dev/null | paste -sd, - | sed 's/,/, /g')"
    echo "$count ($names)"
  fi
}

get_gke_nodes() {
  local project cluster_count total_nodes
  project="$(get_project)"
  if [[ "$project" == "N/A" ]]; then
    echo "N/A"
    return
  fi
  
  cluster_count="$(gcloud container clusters list --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$cluster_count" == "0" ]]; then
    echo "0 (no clusters)"
    return
  fi
  
  total_nodes=0
  while IFS= read -r cluster; do
    [[ -z "$cluster" ]] && continue
    local zone location
    zone="$(gcloud container clusters list --filter="name=$cluster" --format='value(location)' 2>/dev/null | head -n1)"
    if [[ -n "$zone" ]]; then
      local nodes
      nodes="$(gcloud container clusters describe "$cluster" --location="$zone" --format='value(currentNodeCount)' 2>/dev/null || echo 0)"
      total_nodes=$((total_nodes + nodes))
    fi
  done < <(gcloud container clusters list --format='value(name)' 2>/dev/null)
  
  echo "$total_nodes"
}

get_gke_deployments() {
  local project cluster_count total_deployments
  project="$(get_project)"
  if [[ "$project" == "N/A" ]]; then
    echo "N/A"
    return
  fi
  
  cluster_count="$(gcloud container clusters list --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$cluster_count" == "0" ]]; then
    echo "0 (no clusters)"
    return
  fi
  
  total_deployments=0
  while IFS= read -r cluster; do
    [[ -z "$cluster" ]] && continue
    local zone
    zone="$(gcloud container clusters list --filter="name=$cluster" --format='value(location)' 2>/dev/null | head -n1)"
    if [[ -n "$zone" ]]; then
      # Get credentials for the cluster
      gcloud container clusters get-credentials "$cluster" --location="$zone" --quiet 2>/dev/null || continue
      local deployments
      deployments="$(kubectl get deployments --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')"
      total_deployments=$((total_deployments + deployments))
    fi
  done < <(gcloud container clusters list --format='value(name)' 2>/dev/null)
  
  echo "$total_deployments"
}

get_buckets() {
  local count
  count="$(gsutil ls 2>/dev/null | wc -l | tr -d ' ')"
  echo "$count"
}

get_vpcs() {
  local count names
  count="$(gcloud compute networks list --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$count" == "0" ]]; then
    echo "0"
  else
    names="$(gcloud compute networks list --format='value(name)' 2>/dev/null | paste -sd, - | sed 's/,/, /g')"
    echo "$count ($names)"
  fi
}

get_subnets() {
  local count
  count="$(gcloud compute networks subnets list --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  echo "$count"
}

get_firewall_rules() {
  local count
  count="$(gcloud compute firewall-rules list --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  echo "$count"
}

get_load_balancers() {
  local count
  count="$(gcloud compute forwarding-rules list --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  echo "$count"
}

get_service_accounts() {
  local count
  count="$(gcloud iam service-accounts list --format='value(email)' 2>/dev/null | wc -l | tr -d ' ')"
  echo "$count"
}

get_cloud_sql() {
  local count names
  count="$(gcloud sql instances list --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$count" == "0" ]]; then
    echo "0"
  else
    names="$(gcloud sql instances list --format='value(name)' 2>/dev/null | paste -sd, - | sed 's/,/, /g')"
    echo "$count ($names)"
  fi
}

get_cloud_run() {
  local count
  count="$(gcloud run services list --format='value(metadata.name)' 2>/dev/null | wc -l | tr -d ' ')"
  echo "$count"
}

get_cloud_functions() {
  local count
  count="$(gcloud functions list --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
  echo "$count"
}

# Gather basic info
project="$(get_project)"
account="$(get_account)"
region="$(get_region)"
zone="$(get_zone)"
gce_instances="$(get_gce_instances)"
secrets="$(get_secrets)"
gke_clusters="$(get_gke_clusters)"
gke_nodes="$(get_gke_nodes)"
gke_deployments="$(get_gke_deployments)"
buckets="$(get_buckets)"
vpcs="$(get_vpcs)"
subnets="$(get_subnets)"

declare -a info_lines
info_lines+=("${c_value}GCP Platform Info${c_reset}")
info_lines+=("${c_dim}------------------${c_reset}")
info_lines+=("${c_key}Project:${c_reset} ${project}")
info_lines+=("${c_key}Account:${c_reset} ${account}")
info_lines+=("${c_key}Region:${c_reset} ${region}")
info_lines+=("${c_key}Zone:${c_reset} ${zone}")
info_lines+=("")
info_lines+=("${c_key}GCE Instances:${c_reset} ${gce_instances}")
info_lines+=("${c_key}Secrets:${c_reset} ${secrets}")
info_lines+=("${c_key}GKE Clusters:${c_reset} ${gke_clusters}")
info_lines+=("${c_key}GKE Nodes:${c_reset} ${gke_nodes}")
info_lines+=("${c_key}GKE Deployments:${c_reset} ${gke_deployments}")
info_lines+=("${c_key}Storage Buckets:${c_reset} ${buckets}")
info_lines+=("${c_key}VPCs:${c_reset} ${vpcs}")
info_lines+=("${c_key}Subnets:${c_reset} ${subnets}")

if $want_full; then
  firewall_rules="$(get_firewall_rules)"
  load_balancers="$(get_load_balancers)"
  service_accounts="$(get_service_accounts)"
  cloud_sql="$(get_cloud_sql)"
  cloud_run="$(get_cloud_run)"
  cloud_functions="$(get_cloud_functions)"
  
  info_lines+=("")
  info_lines+=("${c_key}Firewall Rules:${c_reset} ${firewall_rules}")
  info_lines+=("${c_key}Load Balancers:${c_reset} ${load_balancers}")
  info_lines+=("${c_key}Service Accounts:${c_reset} ${service_accounts}")
  info_lines+=("${c_key}Cloud SQL:${c_reset} ${cloud_sql}")
  info_lines+=("${c_key}Cloud Run:${c_reset} ${cloud_run}")
  info_lines+=("${c_key}Cloud Functions:${c_reset} ${cloud_functions}")
fi

declare -a logo_lines_plain
declare -a logo_lines
if $want_logo; then
  logo_lines_plain+=("        ___           ___      ")
  logo_lines_plain+=("       /  /\         /  /\     ")
  logo_lines_plain+=("      /  /:/_       /  /:/     ")
  logo_lines_plain+=("     /  /:/ /\     /  /:/      ")
  logo_lines_plain+=("    /  /:/_/::\   /  /:/  ___  ")
  logo_lines_plain+=("   /__/:/__\/\:\ /__/:/  /  /\ ")
  logo_lines_plain+=("   \  \:\ /~~/:/ \  \:\ /  /:/ ")
  logo_lines_plain+=("    \  \:\  /:/   \  \:\  /:/  ")
  logo_lines_plain+=("     \  \:\/:/     \  \:\/:/   ")
  logo_lines_plain+=("      \  \::/       \  \::/    ")
  logo_lines_plain+=("       \__\/         \__\/     ")
  logo_lines_plain+=("                               ")
  logo_lines_plain+=("   Google Cloud Platform       ")

  if supports_color; then
    declare -a logo_colors
    logo_colors+=($'\033[38;5;33m')   # Blue
    logo_colors+=($'\033[38;5;33m')
    logo_colors+=($'\033[38;5;39m')
    logo_colors+=($'\033[38;5;39m')
    logo_colors+=($'\033[38;5;45m')
    logo_colors+=($'\033[38;5;45m')
    logo_colors+=($'\033[38;5;51m')
    logo_colors+=($'\033[38;5;51m')
    logo_colors+=($'\033[38;5;87m')
    logo_colors+=($'\033[38;5;87m')
    logo_colors+=($'\033[38;5;123m')
    logo_colors+=($'\033[38;5;123m')
    logo_colors+=($'\033[1;37m')      # White for text

    for ((i=0; i<${#logo_lines_plain[@]}; i++)); do
      logo_lines+=("${logo_colors[$i]}${logo_lines_plain[$i]}${c_reset}")
    done
  else
    logo_lines=("${logo_lines_plain[@]}")
  fi
fi

max_left=0
if $want_logo; then
  for line in "${logo_lines_plain[@]}"; do
    ((${#line} > max_left)) && max_left=${#line}
  done
fi

rows=${#info_lines[@]}
if $want_logo && ((${#logo_lines[@]} > rows)); then rows=${#logo_lines[@]}; fi

for ((i=0; i<rows; i++)); do
  left=""
  left_plain=""
  right=""

  if $want_logo && (( i < ${#logo_lines[@]} )); then
    left="${logo_lines[$i]}"
    left_plain="${logo_lines_plain[$i]}"
  fi
  if (( i < ${#info_lines[@]} )); then right="${info_lines[$i]}"; fi

  if $want_logo; then
    pad=$((max_left - ${#left_plain}))
    ((pad < 0)) && pad=0
    printf "%s%*s  %s\n" "$left" "$pad" "" "$right"
  else
    printf "%s\n" "$right"
  fi
done

```

## `gcp-functions.sh`

```bash
#!/usr/bin/env bash
# GCP Functions Library
# 可以被其他脚本 source 使用的函数库

# 检查 gcloud 是否可用
check_gcloud() {
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "Error: gcloud not found. Please install Google Cloud SDK." >&2
    return 1
  fi
  return 0
}

# 检查是否有活动项目
check_project() {
  local project
  project=$(gcloud config get-value project 2>/dev/null || echo "")
  if [[ -z "$project" ]]; then
    echo "Error: No active project. Run: gcloud config set project PROJECT_ID" >&2
    return 1
  fi
  echo "$project"
  return 0
}

# ============================================
# 基础配置信息
# ============================================

# 获取当前项目
gcp_get_project() {
  gcloud config get-value project 2>/dev/null || echo "N/A"
}

# 获取当前账号
gcp_get_account() {
  gcloud config get-value account 2>/dev/null || echo "N/A"
}

# 获取默认区域
gcp_get_region() {
  gcloud config get-value compute/region 2>/dev/null || echo "N/A"
}

# 获取默认可用区
gcp_get_zone() {
  gcloud config get-value compute/zone 2>/dev/null || echo "N/A"
}

# 获取项目编号
gcp_get_project_number() {
  local project
  project=$(gcp_get_project)
  [[ "$project" == "N/A" ]] && { echo "N/A"; return; }
  gcloud projects describe "$project" --format='value(projectNumber)' 2>/dev/null || echo "N/A"
}

# ============================================
# Compute Engine
# ============================================

# 获取 GCE 实例数量
gcp_count_instances() {
  gcloud compute instances list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取 GCE 实例列表
gcp_list_instances() {
  gcloud compute instances list --format='table(name,zone,machineType,status,networkInterfaces[0].networkIP)' 2>/dev/null
}

# 获取指定实例的详细信息
gcp_describe_instance() {
  local instance="$1"
  local zone="$2"
  [[ -z "$instance" ]] && { echo "Usage: gcp_describe_instance INSTANCE_NAME ZONE" >&2; return 1; }
  [[ -z "$zone" ]] && { echo "Usage: gcp_describe_instance INSTANCE_NAME ZONE" >&2; return 1; }
  gcloud compute instances describe "$instance" --zone="$zone" 2>/dev/null
}

# 获取实例组数量
gcp_count_instance_groups() {
  gcloud compute instance-groups list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取磁盘数量
gcp_count_disks() {
  gcloud compute disks list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# ============================================
# GKE (Google Kubernetes Engine)
# ============================================

# 获取 GKE 集群数量
gcp_count_gke_clusters() {
  gcloud container clusters list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取 GKE 集群列表
gcp_list_gke_clusters() {
  gcloud container clusters list --format='table(name,location,currentMasterVersion,currentNodeCount,status)' 2>/dev/null
}

# 获取所有 GKE 集群的节点总数
gcp_count_gke_nodes() {
  local total_nodes=0
  while IFS= read -r cluster; do
    [[ -z "$cluster" ]] && continue
    local zone
    zone="$(gcloud container clusters list --filter="name=$cluster" --format='value(location)' 2>/dev/null | head -n1)"
    if [[ -n "$zone" ]]; then
      local nodes
      nodes="$(gcloud container clusters describe "$cluster" --location="$zone" --format='value(currentNodeCount)' 2>/dev/null || echo 0)"
      total_nodes=$((total_nodes + nodes))
    fi
  done < <(gcloud container clusters list --format='value(name)' 2>/dev/null)
  echo "$total_nodes"
}

# 获取指定集群的节点数
gcp_get_cluster_nodes() {
  local cluster="$1"
  local location="$2"
  [[ -z "$cluster" ]] && { echo "Usage: gcp_get_cluster_nodes CLUSTER_NAME LOCATION" >&2; return 1; }
  [[ -z "$location" ]] && { echo "Usage: gcp_get_cluster_nodes CLUSTER_NAME LOCATION" >&2; return 1; }
  gcloud container clusters describe "$cluster" --location="$location" --format='value(currentNodeCount)' 2>/dev/null || echo "0"
}

# 获取所有 GKE 集群的 Deployment 总数（需要 kubectl）
gcp_count_gke_deployments() {
  local total_deployments=0
  while IFS= read -r cluster; do
    [[ -z "$cluster" ]] && continue
    local zone
    zone="$(gcloud container clusters list --filter="name=$cluster" --format='value(location)' 2>/dev/null | head -n1)"
    if [[ -n "$zone" ]]; then
      gcloud container clusters get-credentials "$cluster" --location="$zone" --quiet 2>/dev/null || continue
      local deployments
      deployments="$(kubectl get deployments --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')"
      total_deployments=$((total_deployments + deployments))
    fi
  done < <(gcloud container clusters list --format='value(name)' 2>/dev/null)
  echo "$total_deployments"
}

# 获取指定集群的 Deployment 数量
gcp_count_cluster_deployments() {
  local cluster="$1"
  local location="$2"
  [[ -z "$cluster" ]] && { echo "Usage: gcp_count_cluster_deployments CLUSTER_NAME LOCATION" >&2; return 1; }
  [[ -z "$location" ]] && { echo "Usage: gcp_count_cluster_deployments CLUSTER_NAME LOCATION" >&2; return 1; }
  gcloud container clusters get-credentials "$cluster" --location="$location" --quiet 2>/dev/null || return 1
  kubectl get deployments --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' '
}

# ============================================
# Networking
# ============================================

# 获取 VPC 数量
gcp_count_vpcs() {
  gcloud compute networks list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取 VPC 列表
gcp_list_vpcs() {
  gcloud compute networks list --format='table(name,subnet_mode,bgpRoutingMode)' 2>/dev/null
}

# 获取子网数量
gcp_count_subnets() {
  gcloud compute networks subnets list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取子网列表
gcp_list_subnets() {
  gcloud compute networks subnets list --format='table(name,region,network,ipCidrRange)' 2>/dev/null
}

# 获取防火墙规则数量
gcp_count_firewall_rules() {
  gcloud compute firewall-rules list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取防火墙规则列表
gcp_list_firewall_rules() {
  gcloud compute firewall-rules list --format='table(name,network,direction,priority,allowed[].map().firewall_rule().list():label=ALLOW)' 2>/dev/null
}

# 获取路由数量
gcp_count_routes() {
  gcloud compute routes list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取 VPC Peering 列表
gcp_list_vpc_peerings() {
  gcloud compute networks peerings list --format='table(name,network,peerNetwork,state)' 2>/dev/null
}

# ============================================
# Load Balancing
# ============================================

# 获取转发规则（负载均衡器）数量
gcp_count_forwarding_rules() {
  gcloud compute forwarding-rules list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取转发规则列表
gcp_list_forwarding_rules() {
  gcloud compute forwarding-rules list --format='table(name,region,IPAddress,target)' 2>/dev/null
}

# 获取后端服务数量
gcp_count_backend_services() {
  gcloud compute backend-services list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取健康检查数量
gcp_count_health_checks() {
  gcloud compute health-checks list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# ============================================
# Cloud Armor
# ============================================

# 获取安全策略数量
gcp_count_security_policies() {
  gcloud compute security-policies list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取安全策略列表
gcp_list_security_policies() {
  gcloud compute security-policies list --format='table(name,description,ruleTupleCount)' 2>/dev/null
}

# ============================================
# Storage
# ============================================

# 获取存储桶数量
gcp_count_buckets() {
  gsutil ls 2>/dev/null | wc -l | tr -d ' '
}

# 获取存储桶列表
gcp_list_buckets() {
  gsutil ls -L 2>/dev/null
}

# ============================================
# Cloud SQL
# ============================================

# 获取 Cloud SQL 实例数量
gcp_count_sql_instances() {
  gcloud sql instances list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取 Cloud SQL 实例列表
gcp_list_sql_instances() {
  gcloud sql instances list --format='table(name,databaseVersion,region,tier,state)' 2>/dev/null
}

# ============================================
# Secret Manager
# ============================================

# 获取密钥数量
gcp_count_secrets() {
  gcloud secrets list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取密钥列表
gcp_list_secrets() {
  gcloud secrets list --format='table(name,created)' 2>/dev/null
}

# ============================================
# IAM
# ============================================

# 获取服务账号数量
gcp_count_service_accounts() {
  gcloud iam service-accounts list --format='value(email)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取服务账号列表
gcp_list_service_accounts() {
  gcloud iam service-accounts list --format='table(email,displayName,disabled)' 2>/dev/null
}

# ============================================
# Cloud Run
# ============================================

# 获取 Cloud Run 服务数量
gcp_count_cloud_run_services() {
  gcloud run services list --format='value(metadata.name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取 Cloud Run 服务列表
gcp_list_cloud_run_services() {
  gcloud run services list --format='table(metadata.name,status.url,status.latestReadyRevisionName)' 2>/dev/null
}

# ============================================
# Cloud Functions
# ============================================

# 获取 Cloud Functions 数量
gcp_count_cloud_functions() {
  gcloud functions list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取 Cloud Functions 列表
gcp_list_cloud_functions() {
  gcloud functions list --format='table(name,status,trigger,runtime)' 2>/dev/null
}

# ============================================
# Pub/Sub
# ============================================

# 获取 Pub/Sub 主题数量
gcp_count_pubsub_topics() {
  gcloud pubsub topics list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取 Pub/Sub 订阅数量
gcp_count_pubsub_subscriptions() {
  gcloud pubsub subscriptions list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# ============================================
# Cloud DNS
# ============================================

# 获取 DNS 托管区域数量
gcp_count_dns_zones() {
  gcloud dns managed-zones list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取 DNS 托管区域列表
gcp_list_dns_zones() {
  gcloud dns managed-zones list --format='table(name,dnsName,visibility)' 2>/dev/null
}

# ============================================
# SSL Certificates
# ============================================

# 获取 SSL 证书数量
gcp_count_ssl_certificates() {
  gcloud compute ssl-certificates list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取 SSL 证书列表
gcp_list_ssl_certificates() {
  gcloud compute ssl-certificates list --format='table(name,type,creationTimestamp,expireTime)' 2>/dev/null
}

# ============================================
# Monitoring & Logging
# ============================================

# 获取日志接收器数量
gcp_count_log_sinks() {
  gcloud logging sinks list --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取日志接收器列表
gcp_list_log_sinks() {
  gcloud logging sinks list --format='table(name,destination)' 2>/dev/null
}

# ============================================
# APIs
# ============================================

# 获取已启用的 API 数量
gcp_count_enabled_apis() {
  gcloud services list --enabled --format='value(config.name)' 2>/dev/null | wc -l | tr -d ' '
}

# 获取已启用的 API 列表
gcp_list_enabled_apis() {
  gcloud services list --enabled --format='table(config.name,config.title)' 2>/dev/null
}

# ============================================
# 工具函数
# ============================================

# 打印带颜色的输出
print_color() {
  local color="$1"
  shift
  local message="$*"
  case "$color" in
    red) echo -e "\033[0;31m${message}\033[0m" ;;
    green) echo -e "\033[0;32m${message}\033[0m" ;;
    yellow) echo -e "\033[0;33m${message}\033[0m" ;;
    blue) echo -e "\033[0;34m${message}\033[0m" ;;
    cyan) echo -e "\033[0;36m${message}\033[0m" ;;
    *) echo "$message" ;;
  esac
}

# 打印分隔线
print_separator() {
  echo "----------------------------------------"
}

# 打印标题
print_header() {
  local title="$1"
  echo ""
  print_color cyan "=== $title ==="
  print_separator
}

```

## `gcp-explore.sh`

```bash
#!/usr/bin/env bash
# GCP Platform Exploration Script
# 探索 GCP 平台中可以获取的各种信息

set -euo pipefail

echo "=== GCP Platform Exploration ==="
echo ""

# 检查 gcloud 是否安装
if ! command -v gcloud >/dev/null 2>&1; then
  echo "Error: gcloud not found. Please install Google Cloud SDK."
  exit 1
fi

PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [[ -z "$PROJECT" ]]; then
  echo "Error: No active project. Run: gcloud config set project PROJECT_ID"
  exit 1
fi

echo "Current Project: $PROJECT"
echo ""

# 1. Compute Engine
echo "--- Compute Engine ---"
echo "Instances:"
gcloud compute instances list --format="table(name,zone,machineType,status,networkInterfaces[0].networkIP:label=INTERNAL_IP)" 2>/dev/null || echo "  No instances or permission denied"
echo ""

echo "Instance Groups:"
gcloud compute instance-groups list --format="table(name,location,size)" 2>/dev/null || echo "  No instance groups"
echo ""

echo "Disks:"
gcloud compute disks list --format="table(name,zone,sizeGb,type,status)" 2>/dev/null | head -n 10 || echo "  No disks"
echo ""

# 2. GKE
echo "--- Google Kubernetes Engine ---"
echo "Clusters:"
gcloud container clusters list --format="table(name,location,currentMasterVersion,currentNodeCount,status)" 2>/dev/null || echo "  No clusters"
echo ""

# 3. Networking
echo "--- Networking ---"
echo "VPCs:"
gcloud compute networks list --format="table(name,subnet_mode,bgpRoutingMode)" 2>/dev/null || echo "  No VPCs"
echo ""

echo "Subnets (first 10):"
gcloud compute networks subnets list --format="table(name,region,network,ipCidrRange)" 2>/dev/null | head -n 10 || echo "  No subnets"
echo ""

echo "Firewall Rules (first 10):"
gcloud compute firewall-rules list --format="table(name,network,direction,priority,sourceRanges.list():label=SRC_RANGES)" 2>/dev/null | head -n 10 || echo "  No firewall rules"
echo ""

echo "Routes (first 10):"
gcloud compute routes list --format="table(name,network,destRange,nextHopGateway,priority)" 2>/dev/null | head -n 10 || echo "  No routes"
echo ""

echo "VPC Peerings:"
gcloud compute networks peerings list --format="table(name,network,peerNetwork,state)" 2>/dev/null || echo "  No peerings"
echo ""

# 4. Load Balancing
echo "--- Load Balancing ---"
echo "Forwarding Rules:"
gcloud compute forwarding-rules list --format="table(name,region,IPAddress,target)" 2>/dev/null || echo "  No forwarding rules"
echo ""

echo "Backend Services:"
gcloud compute backend-services list --format="table(name,backends[].group.basename():label=BACKENDS,protocol)" 2>/dev/null || echo "  No backend services"
echo ""

echo "Health Checks:"
gcloud compute health-checks list --format="table(name,type,healthyThreshold,unhealthyThreshold)" 2>/dev/null || echo "  No health checks"
echo ""

# 5. Cloud Armor
echo "--- Cloud Armor ---"
echo "Security Policies:"
gcloud compute security-policies list --format="table(name,description,ruleTupleCount)" 2>/dev/null || echo "  No security policies"
echo ""

# 6. Storage
echo "--- Storage ---"
echo "Buckets (first 10):"
gsutil ls 2>/dev/null | head -n 10 || echo "  No buckets or permission denied"
echo ""

# 7. Cloud SQL
echo "--- Cloud SQL ---"
echo "Instances:"
gcloud sql instances list --format="table(name,databaseVersion,region,tier,ipAddresses[0].ipAddress:label=IP,state)" 2>/dev/null || echo "  No SQL instances"
echo ""

# 8. Secret Manager
echo "--- Secret Manager ---"
echo "Secrets (first 10):"
gcloud secrets list --format="table(name,created,replication.automatic:label=AUTO_REPLICATION)" 2>/dev/null | head -n 10 || echo "  No secrets"
echo ""

# 9. IAM
echo "--- IAM ---"
echo "Service Accounts:"
gcloud iam service-accounts list --format="table(email,displayName,disabled)" 2>/dev/null || echo "  No service accounts"
echo ""

# 10. Cloud Run
echo "--- Cloud Run ---"
echo "Services:"
gcloud run services list --format="table(metadata.name,status.url,status.latestReadyRevisionName)" 2>/dev/null || echo "  No Cloud Run services"
echo ""

# 11. Cloud Functions
echo "--- Cloud Functions ---"
echo "Functions (Gen 1):"
gcloud functions list --format="table(name,status,trigger,runtime)" 2>/dev/null || echo "  No functions"
echo ""

# 12. Pub/Sub
echo "--- Pub/Sub ---"
echo "Topics (first 10):"
gcloud pubsub topics list --format="table(name)" 2>/dev/null | head -n 10 || echo "  No topics"
echo ""

echo "Subscriptions (first 10):"
gcloud pubsub subscriptions list --format="table(name,topic.basename():label=TOPIC,ackDeadlineSeconds)" 2>/dev/null | head -n 10 || echo "  No subscriptions"
echo ""

# 13. Cloud DNS
echo "--- Cloud DNS ---"
echo "Managed Zones:"
gcloud dns managed-zones list --format="table(name,dnsName,visibility)" 2>/dev/null || echo "  No DNS zones"
echo ""

# 14. BigQuery
echo "--- BigQuery ---"
echo "Datasets:"
bq ls --format=pretty 2>/dev/null || echo "  No datasets or bq not configured"
echo ""

# 15. APIs
echo "--- Enabled APIs (first 15) ---"
gcloud services list --enabled --format="table(config.name,config.title)" 2>/dev/null | head -n 15 || echo "  Cannot list APIs"
echo ""

# 16. Billing
echo "--- Billing ---"
echo "Billing Accounts:"
gcloud billing accounts list --format="table(name,displayName,open)" 2>/dev/null || echo "  No billing access"
echo ""

# 17. Organization
echo "--- Organization ---"
echo "Projects:"
gcloud projects list --format="table(projectId,name,projectNumber)" 2>/dev/null | head -n 10 || echo "  Cannot list projects"
echo ""

# 18. Monitoring
echo "--- Monitoring ---"
echo "Uptime Checks:"
gcloud monitoring uptime list --format="table(name,displayName,monitoredResource.type)" 2>/dev/null || echo "  No uptime checks"
echo ""

# 19. Logging
echo "--- Logging ---"
echo "Log Sinks:"
gcloud logging sinks list --format="table(name,destination,filter)" 2>/dev/null || echo "  No log sinks"
echo ""

# 20. Certificates
echo "--- SSL Certificates ---"
echo "SSL Certificates:"
gcloud compute ssl-certificates list --format="table(name,type,creationTimestamp,expireTime)" 2>/dev/null || echo "  No SSL certificates"
echo ""

# 21. Quotas (sample)
echo "--- Quotas (Sample) ---"
echo "Compute Engine Quotas (CPUs):"
gcloud compute project-info describe --format="value(quotas.filter(metric:CPUS))" 2>/dev/null || echo "  Cannot retrieve quotas"
echo ""

echo "=== Exploration Complete ==="

```

