#!/bin/bash

# DNS 迁移 - 第一步：服务发现和映射关系建立
# 功能：自动发现源项目和目标项目的服务，建立DNS映射关系

set -euo pipefail

# 加载配置
source "$(dirname "$0")/config.sh"

# 初始化
setup_directories
check_prerequisites

log_info "开始服务发现和映射关系建立..."

# 函数：获取 GKE Ingress 的外部IP
get_ingress_ip() {
    local project=$1
    local cluster=$2
    local region=$3
    local namespace=${4:-default}
    
    log_info "获取项目 $project 集群 $cluster 的 Ingress IP..."
    
    # 设置 kubectl 上下文
    gcloud container clusters get-credentials "$cluster" --region="$region" --project="$project"
    
    # 获取 Ingress 资源
    local ingress_ips=()
    while IFS= read -r line; do
        if [[ -n "$line" && "$line" != "<none>" ]]; then
            ingress_ips+=("$line")
        fi
    done < <(kubectl get ingress -n "$namespace" -o jsonpath='{.items[*].status.loadBalancer.ingress[*].ip}' 2>/dev/null || echo "")
    
    if [[ ${#ingress_ips[@]} -gt 0 ]]; then
        echo "${ingress_ips[0]}"  # 返回第一个IP
    else
        echo ""
    fi
}

# 函数：获取 LoadBalancer Service 的外部IP
get_service_ip() {
    local project=$1
    local cluster=$2
    local region=$3
    local service_name=$4
    local namespace=${5:-default}
    
    log_info "获取项目 $project 服务 $service_name 的外部IP..."
    
    # 设置 kubectl 上下文
    gcloud container clusters get-credentials "$cluster" --region="$region" --project="$project"
    
    # 获取 Service 的外部IP
    local service_ip
    service_ip=$(kubectl get service "$service_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    echo "$service_ip"
}

# 函数：获取 ILB (Internal Load Balancer) 的IP
get_ilb_ip() {
    local project=$1
    local ilb_name_pattern=$2
    
    log_info "获取项目 $project 的 ILB IP (模式: $ilb_name_pattern)..."
    
    # 查找匹配的负载均衡器
    local ilb_ip
    ilb_ip=$(gcloud compute forwarding-rules list --project="$project" --filter="name~'$ilb_name_pattern'" --format="value(IPAddress)" --limit=1 2>/dev/null || echo "")
    
    echo "$ilb_ip"
}

# 函数：根据 Deployment 名称推断服务类型和获取IP
discover_service_mapping() {
    local project=$1
    local cluster=$2
    local region=$3
    local deployment_name=$4
    
    log_info "发现部署 $deployment_name 的服务映射..."
    
    # 设置 kubectl 上下文
    gcloud container clusters get-credentials "$cluster" --region="$region" --project="$project"
    
    # 获取与 Deployment 关联的 Service
    local service_info
    service_info=$(kubectl get services -o json | jq -r --arg dep "$deployment_name" '
        .items[] | 
        select(.spec.selector and (.spec.selector | to_entries[] | .value == $dep)) |
        "\(.metadata.name):\(.spec.type):\(.status.loadBalancer.ingress[0].ip // "")"
    ' 2>/dev/null || echo "")
    
    if [[ -n "$service_info" ]]; then
        echo "$service_info"
    else
        # 如果没有直接关联，尝试通过标签匹配
        service_info=$(kubectl get services -o json | jq -r --arg dep "$deployment_name" '
            .items[] | 
            select(.spec.selector and (.spec.selector.app == $dep or .spec.selector."app.kubernetes.io/name" == $dep)) |
            "\(.metadata.name):\(.spec.type):\(.status.loadBalancer.ingress[0].ip // "")"
        ' 2>/dev/null || echo "")
        echo "$service_info"
    fi
}

# 函数：获取当前DNS记录
get_current_dns_records() {
    local project=$1
    local zone=$2
    
    log_info "获取项目 $project DNS Zone $zone 的当前记录..."
    
    local dns_records_file="$BACKUP_DIR/${project}_dns_records.json"
    gcloud dns record-sets list --zone="$zone" --project="$project" --format=json > "$dns_records_file"
    
    echo "$dns_records_file"
}

# 函数：分析DNS记录并提取映射关系
analyze_dns_mappings() {
    local dns_records_file=$1
    local project=$2
    
    log_info "分析DNS记录文件: $dns_records_file"
    
    local mappings_file="$BACKUP_DIR/${project}_dns_mappings.txt"
    
    # 提取CNAME和A记录
    jq -r '.[] | select(.type == "CNAME" or .type == "A") | "\(.name):\(.type):\(.rrdatas[0])"' "$dns_records_file" > "$mappings_file"
    
    echo "$mappings_file"
}

# 函数：发现目标项目的服务端点
discover_target_endpoints() {
    local project=$1
    local cluster=$2
    local region=$3
    
    log_info "发现目标项目 $project 的服务端点..."
    
    local endpoints_file="$BACKUP_DIR/${project}_endpoints.txt"
    
    # 设置 kubectl 上下文
    gcloud container clusters get-credentials "$cluster" --region="$region" --project="$project"
    
    # 获取所有 Deployments
    local deployments
    deployments=$(kubectl get deployments -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    echo "# 目标项目服务端点发现结果" > "$endpoints_file"
    echo "# 格式: deployment_name:service_name:service_type:external_ip" >> "$endpoints_file"
    echo "# 生成时间: $(date)" >> "$endpoints_file"
    echo "" >> "$endpoints_file"
    
    for deployment in $deployments; do
        local service_mapping
        service_mapping=$(discover_service_mapping "$project" "$cluster" "$region" "$deployment")
        
        if [[ -n "$service_mapping" ]]; then
            echo "${deployment}:${service_mapping}" >> "$endpoints_file"
            log_success "发现服务映射: $deployment -> $service_mapping"
        else
            log_warning "未找到 Deployment $deployment 的服务映射"
        fi
    done
    
    # 获取 Ingress 信息
    local ingress_ip
    ingress_ip=$(get_ingress_ip "$project" "$cluster" "$region")
    if [[ -n "$ingress_ip" ]]; then
        echo "ingress:ingress-controller:Ingress:$ingress_ip" >> "$endpoints_file"
        log_success "发现 Ingress IP: $ingress_ip"
    fi
    
    echo "$endpoints_file"
}

# 函数：生成DNS迁移计划
generate_migration_plan() {
    local source_mappings_file=$1
    local target_endpoints_file=$2
    
    log_info "生成DNS迁移计划..."
    
    local migration_plan_file="$BACKUP_DIR/migration_plan.txt"
    
    echo "# DNS 迁移计划" > "$migration_plan_file"
    echo "# 生成时间: $(date)" >> "$migration_plan_file"
    echo "# 源项目: $SOURCE_PROJECT" >> "$migration_plan_file"
    echo "# 目标项目: $TARGET_PROJECT" >> "$migration_plan_file"
    echo "" >> "$migration_plan_file"
    
    # 读取配置的域名映射
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}"
        local target_domain="${subdomain}.${TARGET_PROJECT}.${PARENT_DOMAIN}"
        
        # 从源项目DNS记录中查找当前配置
        local current_record
        current_record=$(grep "^${source_domain}\\." "$source_mappings_file" 2>/dev/null || echo "")
        
        # 从目标项目端点中查找对应的服务
        local target_endpoint=""
        case "$service_type" in
            "ingress")
                target_endpoint=$(grep ":ingress-controller:Ingress:" "$target_endpoints_file" 2>/dev/null | head -1 || echo "")
                ;;
            "ilb")
                # 查找ILB相关的服务
                target_endpoint=$(grep ":LoadBalancer:" "$target_endpoints_file" 2>/dev/null | head -1 || echo "")
                ;;
            "service")
                # 查找特定服务名称
                target_endpoint=$(grep "^${subdomain}:" "$target_endpoints_file" 2>/dev/null | head -1 || echo "")
                ;;
        esac
        
        echo "## 域名: $source_domain" >> "$migration_plan_file"
        echo "当前记录: $current_record" >> "$migration_plan_file"
        echo "目标端点: $target_endpoint" >> "$migration_plan_file"
        echo "迁移动作: CNAME $source_domain -> $target_domain" >> "$migration_plan_file"
        echo "" >> "$migration_plan_file"
        
        log_info "计划迁移: $source_domain -> $target_domain"
    done
    
    echo "$migration_plan_file"
}

# 主执行流程
main() {
    log_info "=== DNS 迁移发现阶段开始 ==="
    
    # 验证项目访问权限
    verify_project_access "$SOURCE_PROJECT"
    verify_project_access "$TARGET_PROJECT"
    
    # 1. 获取源项目DNS记录
    log_info "步骤 1: 获取源项目DNS记录"
    local source_dns_file
    source_dns_file=$(get_current_dns_records "$SOURCE_PROJECT" "$SOURCE_ZONE")
    
    # 2. 分析源项目DNS映射
    log_info "步骤 2: 分析源项目DNS映射"
    local source_mappings_file
    source_mappings_file=$(analyze_dns_mappings "$source_dns_file" "$SOURCE_PROJECT")
    
    # 3. 获取目标项目DNS记录
    log_info "步骤 3: 获取目标项目DNS记录"
    local target_dns_file
    target_dns_file=$(get_current_dns_records "$TARGET_PROJECT" "$TARGET_ZONE")
    
    # 4. 发现目标项目服务端点
    log_info "步骤 4: 发现目标项目服务端点"
    local target_endpoints_file
    target_endpoints_file=$(discover_target_endpoints "$TARGET_PROJECT" "$TARGET_CLUSTER" "$CLUSTER_REGION")
    
    # 5. 生成迁移计划
    log_info "步骤 5: 生成迁移计划"
    local migration_plan_file
    migration_plan_file=$(generate_migration_plan "$source_mappings_file" "$target_endpoints_file")
    
    log_success "=== DNS 迁移发现阶段完成 ==="
    log_info "备份目录: $BACKUP_DIR"
    log_info "迁移计划: $migration_plan_file"
    log_info "源项目映射: $source_mappings_file"
    log_info "目标项目端点: $target_endpoints_file"
    
    echo ""
    echo "下一步："
    echo "1. 检查迁移计划: cat $migration_plan_file"
    echo "2. 运行目标项目DNS准备: ./02-prepare-target.sh"
}

# 执行主函数
main "$@"