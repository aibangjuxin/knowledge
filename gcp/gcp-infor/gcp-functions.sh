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
  # Check if kubectl is available
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "0"
    return
  fi
  
  # Save current kubectl context
  local original_context
  original_context="$(kubectl config current-context 2>/dev/null || true)"
  
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
  
  # Restore original kubectl context
  if [[ -n "$original_context" ]]; then
    kubectl config use-context "$original_context" >/dev/null 2>&1 || true
  fi
  
  echo "$total_deployments"
}

# 获取指定集群的 Deployment 数量
gcp_count_cluster_deployments() {
  local cluster="$1"
  local location="$2"
  [[ -z "$cluster" ]] && { echo "Usage: gcp_count_cluster_deployments CLUSTER_NAME LOCATION" >&2; return 1; }
  [[ -z "$location" ]] && { echo "Usage: gcp_count_cluster_deployments CLUSTER_NAME LOCATION" >&2; return 1; }
  
  # Check if kubectl is available
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "0"
    return 1
  fi
  
  # Save current kubectl context
  local original_context
  original_context="$(kubectl config current-context 2>/dev/null || true)"
  
  gcloud container clusters get-credentials "$cluster" --location="$location" --quiet 2>/dev/null || return 1
  local count
  count=$(kubectl get deployments --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
  
  # Restore original kubectl context
  if [[ -n "$original_context" ]]; then
    kubectl config use-context "$original_context" >/dev/null 2>&1 || true
  fi
  
  echo "$count"
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
