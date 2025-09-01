# Shell Scripts Collection

Generated on: 2025-09-01 16:25:20
Directory: /Users/lex/git/knowledge/gcp/migrate-gcp/migrate-dns

## `01-discovery.sh`

```bash
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
```

## `02-prepare-target.sh`

```bash
#!/bin/bash

# DNS 迁移 - 第二步：准备目标项目DNS记录
# 功能：在目标项目中创建新的DNS记录，为迁移做准备

set -euo pipefail

# 加载配置
source "$(dirname "$0")/config.sh"

log_info "开始准备目标项目DNS记录..."

# 函数：检查DNS Zone是否存在
check_dns_zone() {
    local project=$1
    local zone=$2
    
    if gcloud dns managed-zones describe "$zone" --project="$project" &>/dev/null; then
        log_success "DNS Zone $zone 在项目 $project 中存在"
        return 0
    else
        log_error "DNS Zone $zone 在项目 $project 中不存在"
        return 1
    fi
}

# 函数：创建DNS Zone（如果不存在）
create_dns_zone_if_not_exists() {
    local project=$1
    local zone=$2
    local dns_name=$3
    
    if ! check_dns_zone "$project" "$zone"; then
        log_info "创建DNS Zone: $zone"
        gcloud dns managed-zones create "$zone" \
            --dns-name="$dns_name" \
            --description="DNS zone for $project migration" \
            --project="$project"
        log_success "DNS Zone $zone 创建成功"
    fi
}

# 函数：获取服务的实际IP地址
get_service_actual_ip() {
    local project=$1
    local cluster=$2
    local region=$3
    local service_type=$4
    local service_name=${5:-""}
    
    case "$service_type" in
        "ingress")
            get_ingress_ip "$project" "$cluster" "$region"
            ;;
        "ilb")
            # 查找ILB的IP地址
            local ilb_pattern="internal.*${project}.*ilb"
            get_ilb_ip "$project" "$ilb_pattern"
            ;;
        "service")
            if [[ -n "$service_name" ]]; then
                get_service_ip "$project" "$cluster" "$region" "$service_name"
            else
                echo ""
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

# 函数：创建A记录
create_a_record() {
    local project=$1
    local zone=$2
    local name=$3
    local ip=$4
    local ttl=${5:-$DEFAULT_TTL}
    
    log_info "创建A记录: $name -> $ip (TTL: $ttl)"
    
    # 检查记录是否已存在
    if gcloud dns record-sets list --zone="$zone" --project="$project" --name="$name" --type=A &>/dev/null; then
        log_warning "A记录 $name 已存在，跳过创建"
        return 0
    fi
    
    # 创建A记录
    gcloud dns record-sets transaction start --zone="$zone" --project="$project"
    gcloud dns record-sets transaction add "$ip" \
        --name="$name" \
        --ttl="$ttl" \
        --type=A \
        --zone="$zone" \
        --project="$project"
    
    if gcloud dns record-sets transaction execute --zone="$zone" --project="$project"; then
        log_success "A记录创建成功: $name -> $ip"
        return 0
    else
        log_error "A记录创建失败: $name"
        gcloud dns record-sets transaction abort --zone="$zone" --project="$project" 2>/dev/null || true
        return 1
    fi
}

# 函数：创建CNAME记录
create_cname_record() {
    local project=$1
    local zone=$2
    local name=$3
    local target=$4
    local ttl=${5:-$DEFAULT_TTL}
    
    log_info "创建CNAME记录: $name -> $target (TTL: $ttl)"
    
    # 检查记录是否已存在
    if gcloud dns record-sets list --zone="$zone" --project="$project" --name="$name" --type=CNAME &>/dev/null; then
        log_warning "CNAME记录 $name 已存在，跳过创建"
        return 0
    fi
    
    # 创建CNAME记录
    gcloud dns record-sets transaction start --zone="$zone" --project="$project"
    gcloud dns record-sets transaction add "$target" \
        --name="$name" \
        --ttl="$ttl" \
        --type=CNAME \
        --zone="$zone" \
        --project="$project"
    
    if gcloud dns record-sets transaction execute --zone="$zone" --project="$project"; then
        log_success "CNAME记录创建成功: $name -> $target"
        return 0
    else
        log_error "CNAME记录创建失败: $name"
        gcloud dns record-sets transaction abort --zone="$zone" --project="$project" 2>/dev/null || true
        return 1
    fi
}

# 函数：根据服务类型创建相应的DNS记录
create_service_dns_record() {
    local project=$1
    local zone=$2
    local subdomain=$3
    local service_type=$4
    local cluster=$5
    local region=$6
    
    local domain_name="${subdomain}.${project}.${PARENT_DOMAIN}."
    
    case "$service_type" in
        "ingress")
            # 对于Ingress，创建CNAME指向ingress控制器的域名
            local ingress_target="ingress-nginx.gke-01.${project}.${PARENT_DOMAIN}."
            create_cname_record "$project" "$zone" "$domain_name" "$ingress_target"
            
            # 同时创建ingress控制器的A记录
            local ingress_ip
            ingress_ip=$(get_service_actual_ip "$project" "$cluster" "$region" "ingress")
            if [[ -n "$ingress_ip" ]]; then
                create_a_record "$project" "$zone" "$ingress_target" "$ingress_ip"
            else
                log_warning "无法获取Ingress IP地址"
            fi
            ;;
        "ilb")
            # 对于ILB，创建CNAME指向ILB的域名
            local ilb_target="cinternal-vpc1-ingress-proxy-europe-west2-l4-ilb.${project}.${PARENT_DOMAIN}."
            create_cname_record "$project" "$zone" "$domain_name" "$ilb_target"
            
            # 同时创建ILB的A记录
            local ilb_ip
            ilb_ip=$(get_service_actual_ip "$project" "$cluster" "$region" "ilb")
            if [[ -n "$ilb_ip" ]]; then
                create_a_record "$project" "$zone" "$ilb_target" "$ilb_ip"
            else
                log_warning "无法获取ILB IP地址"
            fi
            ;;
        "service")
            # 对于Service，直接创建A记录
            local service_ip
            service_ip=$(get_service_actual_ip "$project" "$cluster" "$region" "service" "$subdomain")
            if [[ -n "$service_ip" ]]; then
                create_a_record "$project" "$zone" "$domain_name" "$service_ip"
            else
                log_warning "无法获取Service $subdomain 的IP地址"
            fi
            ;;
        *)
            log_error "不支持的服务类型: $service_type"
            return 1
            ;;
    esac
}

# 函数：验证DNS记录创建结果
verify_dns_records() {
    local project=$1
    local zone=$2
    
    log_info "验证目标项目DNS记录..."
    
    local verification_file="$BACKUP_DIR/${project}_dns_verification.txt"
    echo "# DNS记录验证结果" > "$verification_file"
    echo "# 项目: $project" >> "$verification_file"
    echo "# Zone: $zone" >> "$verification_file"
    echo "# 验证时间: $(date)" >> "$verification_file"
    echo "" >> "$verification_file"
    
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local domain_name="${subdomain}.${project}.${PARENT_DOMAIN}."
        
        log_info "验证域名: $domain_name"
        
        # 检查DNS记录是否存在
        local record_info
        record_info=$(gcloud dns record-sets list --zone="$zone" --project="$project" --name="$domain_name" --format="value(type,rrdatas)" 2>/dev/null || echo "")
        
        if [[ -n "$record_info" ]]; then
            echo "✓ $domain_name: $record_info" >> "$verification_file"
            log_success "域名 $domain_name 记录存在: $record_info"
            
            # 测试DNS解析
            local resolved_ip
            resolved_ip=$(dig +short "$domain_name" @8.8.8.8 2>/dev/null | tail -1 || echo "")
            if [[ -n "$resolved_ip" && "$resolved_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "  解析结果: $resolved_ip" >> "$verification_file"
                log_success "域名 $domain_name 解析成功: $resolved_ip"
            else
                echo "  解析失败或未传播" >> "$verification_file"
                log_warning "域名 $domain_name 解析失败或DNS未传播"
            fi
        else
            echo "✗ $domain_name: 记录不存在" >> "$verification_file"
            log_error "域名 $domain_name 记录不存在"
        fi
        
        echo "" >> "$verification_file"
    done
    
    echo "$verification_file"
}

# 函数：创建SSL证书配置
create_ssl_certificate_config() {
    local project=$1
    
    log_info "生成SSL证书配置..."
    
    local cert_config_file="$BACKUP_DIR/${project}_ssl_certificate.yaml"
    
    cat > "$cert_config_file" << EOF
# Google Managed Certificate 配置
# 项目: $project
# 生成时间: $(date)

apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: migration-cert-$(date +%s)
  namespace: default
spec:
  domains:
EOF
    
    # 添加新域名
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local new_domain="${subdomain}.${project}.${PARENT_DOMAIN}"
        echo "    - $new_domain" >> "$cert_config_file"
    done
    
    # 添加旧域名（用于迁移期间的兼容性）
    echo "    # 旧域名（迁移兼容性）" >> "$cert_config_file"
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local old_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}"
        echo "    - $old_domain" >> "$cert_config_file"
    done
    
    log_success "SSL证书配置生成完成: $cert_config_file"
    echo "$cert_config_file"
}

# 主执行流程
main() {
    log_info "=== DNS 迁移目标准备阶段开始 ==="
    
    # 验证项目访问权限
    verify_project_access "$TARGET_PROJECT"
    
    # 1. 检查并创建DNS Zone
    log_info "步骤 1: 检查并创建DNS Zone"
    local target_dns_name="${TARGET_PROJECT}.${PARENT_DOMAIN}."
    create_dns_zone_if_not_exists "$TARGET_PROJECT" "$TARGET_ZONE" "$target_dns_name"
    
    # 2. 为每个配置的域名创建DNS记录
    log_info "步骤 2: 创建目标项目DNS记录"
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        log_info "处理域名映射: $subdomain ($service_type)"
        
        create_service_dns_record "$TARGET_PROJECT" "$TARGET_ZONE" "$subdomain" "$service_type" "$TARGET_CLUSTER" "$CLUSTER_REGION"
    done
    
    # 3. 验证DNS记录
    log_info "步骤 3: 验证DNS记录创建结果"
    local verification_file
    verification_file=$(verify_dns_records "$TARGET_PROJECT" "$TARGET_ZONE")
    
    # 4. 生成SSL证书配置
    log_info "步骤 4: 生成SSL证书配置"
    local cert_config_file
    cert_config_file=$(create_ssl_certificate_config "$TARGET_PROJECT")
    
    log_success "=== DNS 迁移目标准备阶段完成 ==="
    log_info "验证结果: $verification_file"
    log_info "SSL证书配置: $cert_config_file"
    
    echo ""
    echo "下一步："
    echo "1. 检查验证结果: cat $verification_file"
    echo "2. 应用SSL证书配置: kubectl apply -f $cert_config_file"
    echo "3. 等待DNS传播（建议等待5-10分钟）"
    echo "4. 运行DNS切换脚本: ./03-execute-migration.sh"
}

# 执行主函数
main "$@"
```

## `03-execute-migration.sh`

```bash
#!/bin/bash

# DNS 迁移 - 第三步：执行DNS切换
# 功能：将源项目的DNS记录切换为CNAME指向目标项目

set -euo pipefail

# 加载配置
source "$(dirname "$0")/config.sh"

log_info "开始执行DNS迁移切换..."

# 函数：降低DNS记录的TTL
reduce_dns_ttl() {
    local project=$1
    local zone=$2
    local domain_name=$3
    local new_ttl=$4
    
    log_info "降低域名 $domain_name 的TTL至 $new_ttl 秒"
    
    # 获取当前记录信息
    local current_record
    current_record=$(gcloud dns record-sets list --zone="$zone" --project="$project" --name="$domain_name" --format="value(type,ttl,rrdatas)" 2>/dev/null || echo "")
    
    if [[ -z "$current_record" ]]; then
        log_error "域名 $domain_name 的记录不存在"
        return 1
    fi
    
    IFS=$'\t' read -r record_type current_ttl record_data <<< "$current_record"
    
    if [[ "$current_ttl" -le "$new_ttl" ]]; then
        log_info "域名 $domain_name 的TTL已经是 $current_ttl 秒，无需降低"
        return 0
    fi
    
    # 开始事务
    gcloud dns record-sets transaction start --zone="$zone" --project="$project"
    
    # 删除旧记录
    gcloud dns record-sets transaction remove "$record_data" \
        --name="$domain_name" \
        --ttl="$current_ttl" \
        --type="$record_type" \
        --zone="$zone" \
        --project="$project"
    
    # 添加新记录（相同数据，但TTL更低）
    gcloud dns record-sets transaction add "$record_data" \
        --name="$domain_name" \
        --ttl="$new_ttl" \
        --type="$record_type" \
        --zone="$zone" \
        --project="$project"
    
    # 执行事务
    if gcloud dns record-sets transaction execute --zone="$zone" --project="$project"; then
        log_success "域名 $domain_name TTL降低成功: $current_ttl -> $new_ttl"
        return 0
    else
        log_error "域名 $domain_name TTL降低失败"
        gcloud dns record-sets transaction abort --zone="$zone" --project="$project" 2>/dev/null || true
        return 1
    fi
}

# 函数：备份当前DNS记录
backup_current_dns_records() {
    local project=$1
    local zone=$2
    
    log_info "备份项目 $project 的当前DNS记录"
    
    local backup_file="$BACKUP_DIR/${project}_dns_backup_$(date +%Y%m%d_%H%M%S).json"
    gcloud dns record-sets list --zone="$zone" --project="$project" --format=json > "$backup_file"
    
    log_success "DNS记录备份完成: $backup_file"
    echo "$backup_file"
}

# 函数：将DNS记录从A/CNAME切换为CNAME指向目标项目
switch_dns_to_cname() {
    local project=$1
    local zone=$2
    local domain_name=$3
    local target_domain=$4
    local ttl=${5:-$MIGRATION_TTL}
    
    log_info "切换域名 $domain_name -> $target_domain"
    
    # 获取当前记录信息
    local current_record
    current_record=$(gcloud dns record-sets list --zone="$zone" --project="$project" --name="$domain_name" --format="value(type,ttl,rrdatas)" 2>/dev/null || echo "")
    
    if [[ -z "$current_record" ]]; then
        log_error "域名 $domain_name 的记录不存在"
        return 1
    fi
    
    IFS=$'\t' read -r record_type current_ttl record_data <<< "$current_record"
    
    log_info "当前记录: $domain_name ($record_type) -> $record_data (TTL: $current_ttl)"
    
    # 开始事务
    gcloud dns record-sets transaction start --zone="$zone" --project="$project"
    
    # 删除当前记录
    gcloud dns record-sets transaction remove "$record_data" \
        --name="$domain_name" \
        --ttl="$current_ttl" \
        --type="$record_type" \
        --zone="$zone" \
        --project="$project"
    
    # 添加新的CNAME记录
    gcloud dns record-sets transaction add "$target_domain" \
        --name="$domain_name" \
        --ttl="$ttl" \
        --type=CNAME \
        --zone="$zone" \
        --project="$project"
    
    # 执行事务
    if gcloud dns record-sets transaction execute --zone="$zone" --project="$project"; then
        log_success "DNS切换成功: $domain_name -> $target_domain"
        return 0
    else
        log_error "DNS切换失败: $domain_name"
        gcloud dns record-sets transaction abort --zone="$zone" --project="$project" 2>/dev/null || true
        return 1
    fi
}

# 函数：验证DNS切换结果
verify_dns_migration() {
    local domain_name=$1
    local expected_target=$2
    local timeout=${3:-$VALIDATION_TIMEOUT}
    
    log_info "验证域名 $domain_name 的DNS切换结果"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        # 使用多个DNS服务器进行验证
        local dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222")
        local success_count=0
        
        for dns_server in "${dns_servers[@]}"; do
            local resolved_cname
            resolved_cname=$(dig +short CNAME "$domain_name" "@$dns_server" 2>/dev/null | sed 's/\.$//' || echo "")
            
            if [[ "$resolved_cname" == "${expected_target%.*}" ]]; then
                ((success_count++))
            fi
        done
        
        # 如果大多数DNS服务器都返回正确结果，认为验证成功
        if [[ $success_count -ge 2 ]]; then
            log_success "域名 $domain_name DNS切换验证成功"
            return 0
        fi
        
        log_info "等待DNS传播... (${success_count}/${#dns_servers[@]} 服务器已更新)"
        sleep 10
    done
    
    log_warning "域名 $domain_name DNS切换验证超时，但这可能是正常的DNS传播延迟"
    return 1
}

# 函数：测试目标服务的可用性
test_target_service_availability() {
    local domain_name=$1
    local timeout=${2:-30}
    
    log_info "测试目标服务可用性: $domain_name"
    
    # 移除域名末尾的点
    local clean_domain="${domain_name%.*}"
    
    for endpoint in "${HEALTH_CHECK_ENDPOINTS[@]}"; do
        local url="https://${clean_domain}${endpoint}"
        log_info "测试端点: $url"
        
        if curl -s --max-time "$timeout" --fail "$url" >/dev/null 2>&1; then
            log_success "端点 $url 可访问"
            return 0
        else
            log_warning "端点 $url 不可访问或响应异常"
        fi
    done
    
    # 如果健康检查端点都不可用，尝试基本的连通性测试
    local url="https://${clean_domain}/"
    if curl -s --max-time "$timeout" -I "$url" 2>/dev/null | grep -q "HTTP"; then
        log_success "基本连通性测试通过: $url"
        return 0
    else
        log_error "目标服务不可访问: $clean_domain"
        return 1
    fi
}

# 函数：生成迁移报告
generate_migration_report() {
    local migration_results=("$@")
    
    log_info "生成迁移报告..."
    
    local report_file="$BACKUP_DIR/migration_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
# DNS 迁移执行报告
# 执行时间: $(date)
# 源项目: $SOURCE_PROJECT
# 目标项目: $TARGET_PROJECT

## 迁移结果摘要
EOF
    
    local success_count=0
    local total_count=${#DOMAIN_MAPPINGS[@]}
    
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        local target_domain="${subdomain}.${TARGET_PROJECT}.${PARENT_DOMAIN}."
        local result="${migration_results[$i]:-UNKNOWN}"
        
        echo "- $source_domain -> $target_domain: $result" >> "$report_file"
        
        if [[ "$result" == "SUCCESS" ]]; then
            ((success_count++))
        fi
    done
    
    cat >> "$report_file" << EOF

## 统计信息
- 总计域名: $total_count
- 成功迁移: $success_count
- 失败数量: $((total_count - success_count))
- 成功率: $(( success_count * 100 / total_count ))%

## 后续步骤
1. 监控目标服务的流量和性能指标
2. 验证所有应用功能正常
3. 在确认稳定后，考虑清理源项目资源
4. 更新内部文档和配置

## 回滚信息
如需回滚，请执行: ./04-rollback.sh
备份文件位置: $BACKUP_DIR
EOF
    
    log_success "迁移报告生成完成: $report_file"
    echo "$report_file"
}

# 函数：交互式确认
confirm_migration() {
    echo ""
    echo "=== DNS 迁移确认 ==="
    echo "源项目: $SOURCE_PROJECT"
    echo "目标项目: $TARGET_PROJECT"
    echo "将要迁移的域名:"
    
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}"
        local target_domain="${subdomain}.${TARGET_PROJECT}.${PARENT_DOMAIN}"
        echo "  $source_domain -> $target_domain"
    done
    
    echo ""
    read -p "确认执行DNS迁移？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "用户取消迁移操作"
        exit 0
    fi
}

# 主执行流程
main() {
    log_info "=== DNS 迁移执行阶段开始 ==="
    
    # 交互式确认
    confirm_migration
    
    # 验证项目访问权限
    verify_project_access "$SOURCE_PROJECT"
    verify_project_access "$TARGET_PROJECT"
    
    # 1. 备份当前DNS记录
    log_info "步骤 1: 备份当前DNS记录"
    local backup_file
    backup_file=$(backup_current_dns_records "$SOURCE_PROJECT" "$SOURCE_ZONE")
    
    # 2. 降低TTL（如果需要）
    log_info "步骤 2: 降低DNS记录TTL"
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        
        reduce_dns_ttl "$SOURCE_PROJECT" "$SOURCE_ZONE" "$source_domain" "$MIGRATION_TTL"
    done
    
    # 等待TTL生效
    log_info "等待TTL更新生效 (60秒)..."
    sleep 60
    
    # 3. 执行DNS切换
    log_info "步骤 3: 执行DNS切换"
    local migration_results=()
    
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        local target_domain="${subdomain}.${TARGET_PROJECT}.${PARENT_DOMAIN}."
        
        if switch_dns_to_cname "$SOURCE_PROJECT" "$SOURCE_ZONE" "$source_domain" "$target_domain"; then
            migration_results+=("SUCCESS")
        else
            migration_results+=("FAILED")
        fi
    done
    
    # 4. 验证DNS切换结果
    log_info "步骤 4: 验证DNS切换结果"
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        local target_domain="${subdomain}.${TARGET_PROJECT}.${PARENT_DOMAIN}."
        
        if [[ "${migration_results[$i]}" == "SUCCESS" ]]; then
            verify_dns_migration "$source_domain" "$target_domain"
        fi
    done
    
    # 5. 测试目标服务可用性
    log_info "步骤 5: 测试目标服务可用性"
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        
        if [[ "${migration_results[$i]}" == "SUCCESS" ]]; then
            test_target_service_availability "$source_domain"
        fi
    done
    
    # 6. 生成迁移报告
    log_info "步骤 6: 生成迁移报告"
    local report_file
    report_file=$(generate_migration_report "${migration_results[@]}")
    
    log_success "=== DNS 迁移执行阶段完成 ==="
    log_info "备份文件: $backup_file"
    log_info "迁移报告: $report_file"
    
    # 统计结果
    local success_count=0
    for result in "${migration_results[@]}"; do
        if [[ "$result" == "SUCCESS" ]]; then
            ((success_count++))
        fi
    done
    
    echo ""
    echo "迁移结果: $success_count/${#DOMAIN_MAPPINGS[@]} 个域名迁移成功"
    
    if [[ $success_count -eq ${#DOMAIN_MAPPINGS[@]} ]]; then
        log_success "所有域名迁移成功！"
        echo "建议："
        echo "1. 监控目标服务24-48小时"
        echo "2. 验证所有应用功能"
        echo "3. 考虑运行清理脚本: ./05-cleanup.sh"
    else
        log_warning "部分域名迁移失败，请检查日志并考虑回滚"
        echo "回滚命令: ./04-rollback.sh"
    fi
}

# 执行主函数
main "$@"
```

## `04-rollback.sh`

```bash
#!/bin/bash

# DNS 迁移 - 第四步：回滚操作
# 功能：将DNS记录回滚到迁移前的状态

set -euo pipefail

# 加载配置
source "$(dirname "$0")/config.sh"

log_info "开始DNS迁移回滚操作..."

# 函数：列出可用的备份文件
list_backup_files() {
    log_info "查找可用的备份文件..."
    
    local backup_files=()
    while IFS= read -r -d '' file; do
        backup_files+=("$file")
    done < <(find "$BACKUP_DIR" -name "*_dns_backup_*.json" -print0 2>/dev/null || true)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log_error "未找到DNS备份文件"
        return 1
    fi
    
    echo "可用的备份文件:"
    for i in "${!backup_files[@]}"; do
        local file="${backup_files[$i]}"
        local timestamp=$(basename "$file" | sed 's/.*_dns_backup_\(.*\)\.json/\1/')
        echo "$((i+1)). $file (时间: $timestamp)"
    done
    
    echo ""
    read -p "请选择要回滚的备份文件编号 (1-${#backup_files[@]}): " -r backup_choice
    
    if [[ "$backup_choice" =~ ^[0-9]+$ ]] && [[ "$backup_choice" -ge 1 ]] && [[ "$backup_choice" -le ${#backup_files[@]} ]]; then
        echo "${backup_files[$((backup_choice-1))]}"
    else
        log_error "无效的选择"
        return 1
    fi
}

# 函数：解析备份文件中的DNS记录
parse_backup_records() {
    local backup_file=$1
    local domain_filter=$2
    
    log_info "解析备份文件中的DNS记录: $backup_file"
    
    # 提取指定域名的记录
    jq -r --arg domain "$domain_filter" '
        .[] | 
        select(.name == $domain) | 
        "\(.name):\(.type):\(.ttl):\(.rrdatas | join(","))"
    ' "$backup_file"
}

# 函数：恢复单个DNS记录
restore_dns_record() {
    local project=$1
    local zone=$2
    local domain_name=$3
    local record_type=$4
    local ttl=$5
    local record_data=$6
    
    log_info "恢复DNS记录: $domain_name ($record_type)"
    
    # 获取当前记录（如果存在）
    local current_record
    current_record=$(gcloud dns record-sets list --zone="$zone" --project="$project" --name="$domain_name" --format="value(type,ttl,rrdatas)" 2>/dev/null || echo "")
    
    # 开始事务
    gcloud dns record-sets transaction start --zone="$zone" --project="$project"
    
    # 如果当前存在记录，先删除
    if [[ -n "$current_record" ]]; then
        IFS=$'\t' read -r current_type current_ttl current_data <<< "$current_record"
        log_info "删除当前记录: $domain_name ($current_type) -> $current_data"
        
        gcloud dns record-sets transaction remove "$current_data" \
            --name="$domain_name" \
            --ttl="$current_ttl" \
            --type="$current_type" \
            --zone="$zone" \
            --project="$project"
    fi
    
    # 添加备份的记录
    log_info "恢复记录: $domain_name ($record_type) -> $record_data (TTL: $ttl)"
    gcloud dns record-sets transaction add "$record_data" \
        --name="$domain_name" \
        --ttl="$ttl" \
        --type="$record_type" \
        --zone="$zone" \
        --project="$project"
    
    # 执行事务
    if gcloud dns record-sets transaction execute --zone="$zone" --project="$project"; then
        log_success "DNS记录恢复成功: $domain_name"
        return 0
    else
        log_error "DNS记录恢复失败: $domain_name"
        gcloud dns record-sets transaction abort --zone="$zone" --project="$project" 2>/dev/null || true
        return 1
    fi
}

# 函数：验证回滚结果
verify_rollback() {
    local domain_name=$1
    local expected_type=$2
    local expected_data=$3
    local timeout=${4:-$VALIDATION_TIMEOUT}
    
    log_info "验证回滚结果: $domain_name"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        local current_record
        current_record=$(gcloud dns record-sets list --zone="$SOURCE_ZONE" --project="$SOURCE_PROJECT" --name="$domain_name" --format="value(type,rrdatas)" 2>/dev/null || echo "")
        
        if [[ -n "$current_record" ]]; then
            IFS=$'\t' read -r record_type record_data <<< "$current_record"
            
            if [[ "$record_type" == "$expected_type" && "$record_data" == "$expected_data" ]]; then
                log_success "回滚验证成功: $domain_name"
                return 0
            fi
        fi
        
        log_info "等待DNS记录更新..."
        sleep 10
    done
    
    log_warning "回滚验证超时: $domain_name"
    return 1
}

# 函数：测试回滚后的服务可用性
test_rollback_service() {
    local domain_name=$1
    local timeout=${2:-30}
    
    log_info "测试回滚后服务可用性: $domain_name"
    
    # 移除域名末尾的点
    local clean_domain="${domain_name%.*}"
    
    # 等待DNS传播
    log_info "等待DNS传播 (60秒)..."
    sleep 60
    
    for endpoint in "${HEALTH_CHECK_ENDPOINTS[@]}"; do
        local url="https://${clean_domain}${endpoint}"
        log_info "测试端点: $url"
        
        if curl -s --max-time "$timeout" --fail "$url" >/dev/null 2>&1; then
            log_success "回滚后端点可访问: $url"
            return 0
        else
            log_warning "回滚后端点不可访问: $url"
        fi
    done
    
    # 基本连通性测试
    local url="https://${clean_domain}/"
    if curl -s --max-time "$timeout" -I "$url" 2>/dev/null | grep -q "HTTP"; then
        log_success "回滚后基本连通性正常: $url"
        return 0
    else
        log_error "回滚后服务不可访问: $clean_domain"
        return 1
    fi
}

# 函数：生成回滚报告
generate_rollback_report() {
    local rollback_results=("$@")
    
    log_info "生成回滚报告..."
    
    local report_file="$BACKUP_DIR/rollback_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
# DNS 迁移回滚报告
# 执行时间: $(date)
# 源项目: $SOURCE_PROJECT
# 目标项目: $TARGET_PROJECT

## 回滚结果摘要
EOF
    
    local success_count=0
    local total_count=${#DOMAIN_MAPPINGS[@]}
    
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        local result="${rollback_results[$i]:-UNKNOWN}"
        
        echo "- $source_domain: $result" >> "$report_file"
        
        if [[ "$result" == "SUCCESS" ]]; then
            ((success_count++))
        fi
    done
    
    cat >> "$report_file" << EOF

## 统计信息
- 总计域名: $total_count
- 成功回滚: $success_count
- 失败数量: $((total_count - success_count))
- 成功率: $(( success_count * 100 / total_count ))%

## 回滚后状态
所有域名已恢复到迁移前的状态。

## 后续步骤
1. 验证所有服务功能正常
2. 分析迁移失败的原因
3. 修复问题后重新规划迁移
4. 更新迁移计划和文档

## 注意事项
- 目标项目的资源仍然存在，可以保留用于下次迁移
- 建议保留此次的日志和报告用于问题分析
EOF
    
    log_success "回滚报告生成完成: $report_file"
    echo "$report_file"
}

# 函数：交互式确认回滚
confirm_rollback() {
    echo ""
    echo "=== DNS 迁移回滚确认 ==="
    echo "警告: 此操作将把以下域名回滚到迁移前的状态:"
    
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}"
        echo "  $source_domain"
    done
    
    echo ""
    echo "回滚后，流量将重新指向源项目 ($SOURCE_PROJECT)"
    echo ""
    read -p "确认执行回滚操作？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "用户取消回滚操作"
        exit 0
    fi
}

# 主执行流程
main() {
    log_info "=== DNS 迁移回滚阶段开始 ==="
    
    # 交互式确认
    confirm_rollback
    
    # 验证项目访问权限
    verify_project_access "$SOURCE_PROJECT"
    
    # 1. 选择备份文件
    log_info "步骤 1: 选择备份文件"
    local backup_file
    backup_file=$(list_backup_files)
    
    if [[ -z "$backup_file" ]]; then
        log_error "未选择有效的备份文件"
        exit 1
    fi
    
    log_info "使用备份文件: $backup_file"
    
    # 2. 执行回滚操作
    log_info "步骤 2: 执行DNS记录回滚"
    local rollback_results=()
    
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        
        # 从备份文件中获取原始记录
        local backup_record
        backup_record=$(parse_backup_records "$backup_file" "$source_domain")
        
        if [[ -n "$backup_record" ]]; then
            IFS=':' read -r domain_name record_type ttl record_data <<< "$backup_record"
            
            if restore_dns_record "$SOURCE_PROJECT" "$SOURCE_ZONE" "$domain_name" "$record_type" "$ttl" "$record_data"; then
                rollback_results+=("SUCCESS")
            else
                rollback_results+=("FAILED")
            fi
        else
            log_error "在备份文件中未找到域名 $source_domain 的记录"
            rollback_results+=("NOT_FOUND")
        fi
    done
    
    # 3. 验证回滚结果
    log_info "步骤 3: 验证回滚结果"
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        
        if [[ "${rollback_results[$i]}" == "SUCCESS" ]]; then
            # 从备份文件获取预期的记录信息用于验证
            local backup_record
            backup_record=$(parse_backup_records "$backup_file" "$source_domain")
            
            if [[ -n "$backup_record" ]]; then
                IFS=':' read -r domain_name record_type ttl record_data <<< "$backup_record"
                verify_rollback "$domain_name" "$record_type" "$record_data"
            fi
        fi
    done
    
    # 4. 测试服务可用性
    log_info "步骤 4: 测试回滚后服务可用性"
    for i in "${!DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "${DOMAIN_MAPPINGS[$i]}"
        local source_domain="${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN}."
        
        if [[ "${rollback_results[$i]}" == "SUCCESS" ]]; then
            test_rollback_service "$source_domain"
        fi
    done
    
    # 5. 生成回滚报告
    log_info "步骤 5: 生成回滚报告"
    local report_file
    report_file=$(generate_rollback_report "${rollback_results[@]}")
    
    log_success "=== DNS 迁移回滚阶段完成 ==="
    log_info "使用的备份: $backup_file"
    log_info "回滚报告: $report_file"
    
    # 统计结果
    local success_count=0
    for result in "${rollback_results[@]}"; do
        if [[ "$result" == "SUCCESS" ]]; then
            ((success_count++))
        fi
    done
    
    echo ""
    echo "回滚结果: $success_count/${#DOMAIN_MAPPINGS[@]} 个域名回滚成功"
    
    if [[ $success_count -eq ${#DOMAIN_MAPPINGS[@]} ]]; then
        log_success "所有域名回滚成功！"
        echo "建议："
        echo "1. 验证所有服务功能正常"
        echo "2. 分析迁移失败原因"
        echo "3. 修复问题后重新规划迁移"
    else
        log_error "部分域名回滚失败，请手动检查和修复"
    fi
}

# 执行主函数
main "$@"
```

## `05-cleanup.sh`

```bash
#!/bin/bash

# DNS 迁移 - 第五步：清理操作
# 功能：清理迁移过程中的临时资源和旧资源

set -euo pipefail

# 加载配置
source "$(dirname "$0")/config.sh"

log_info "开始DNS迁移清理操作..."

# 函数：列出源项目中可以清理的资源
list_cleanup_candidates() {
    local project=$1
    
    log_info "扫描项目 $project 中可清理的资源..."
    
    local cleanup_file="$BACKUP_DIR/${project}_cleanup_candidates.txt"
    
    echo "# 项目 $project 清理候选资源" > "$cleanup_file"
    echo "# 扫描时间: $(date)" >> "$cleanup_file"
    echo "" >> "$cleanup_file"
    
    # 1. 扫描GKE集群
    echo "## GKE 集群" >> "$cleanup_file"
    local clusters
    clusters=$(gcloud container clusters list --project="$project" --format="value(name,location)" 2>/dev/null || echo "")
    
    if [[ -n "$clusters" ]]; then
        while IFS=$'\t' read -r cluster_name location; do
            echo "- 集群: $cluster_name (位置: $location)" >> "$cleanup_file"
            
            # 获取集群详细信息
            local node_count
            node_count=$(gcloud container clusters describe "$cluster_name" --location="$location" --project="$project" --format="value(currentNodeCount)" 2>/dev/null || echo "0")
            echo "  节点数: $node_count" >> "$cleanup_file"
            
            # 检查集群是否有流量
            gcloud container clusters get-credentials "$cluster_name" --location="$location" --project="$project" 2>/dev/null || true
            local ingress_count
            ingress_count=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
            echo "  Ingress数量: $ingress_count" >> "$cleanup_file"
            
        done <<< "$clusters"
    else
        echo "- 无GKE集群" >> "$cleanup_file"
    fi
    echo "" >> "$cleanup_file"
    
    # 2. 扫描负载均衡器
    echo "## 负载均衡器" >> "$cleanup_file"
    local forwarding_rules
    forwarding_rules=$(gcloud compute forwarding-rules list --project="$project" --format="value(name,IPAddress,target)" 2>/dev/null || echo "")
    
    if [[ -n "$forwarding_rules" ]]; then
        while IFS=$'\t' read -r rule_name ip_address target; do
            echo "- 转发规则: $rule_name (IP: $ip_address, 目标: $target)" >> "$cleanup_file"
        done <<< "$forwarding_rules"
    else
        echo "- 无负载均衡器" >> "$cleanup_file"
    fi
    echo "" >> "$cleanup_file"
    
    # 3. 扫描静态IP地址
    echo "## 静态IP地址" >> "$cleanup_file"
    local static_ips
    static_ips=$(gcloud compute addresses list --project="$project" --format="value(name,address,status,users)" 2>/dev/null || echo "")
    
    if [[ -n "$static_ips" ]]; then
        while IFS=$'\t' read -r ip_name ip_address status users; do
            echo "- IP地址: $ip_name ($ip_address) - 状态: $status" >> "$cleanup_file"
            if [[ -n "$users" ]]; then
                echo "  使用者: $users" >> "$cleanup_file"
            else
                echo "  使用者: 无 (可安全删除)" >> "$cleanup_file"
            fi
        done <<< "$static_ips"
    else
        echo "- 无静态IP地址" >> "$cleanup_file"
    fi
    echo "" >> "$cleanup_file"
    
    # 4. 扫描持久磁盘
    echo "## 持久磁盘" >> "$cleanup_file"
    local disks
    disks=$(gcloud compute disks list --project="$project" --format="value(name,sizeGb,status,users)" 2>/dev/null || echo "")
    
    if [[ -n "$disks" ]]; then
        while IFS=$'\t' read -r disk_name size_gb status users; do
            echo "- 磁盘: $disk_name (${size_gb}GB) - 状态: $status" >> "$cleanup_file"
            if [[ -n "$users" ]]; then
                echo "  使用者: $users" >> "$cleanup_file"
            else
                echo "  使用者: 无 (可安全删除)" >> "$cleanup_file"
            fi
        done <<< "$disks"
    else
        echo "- 无持久磁盘" >> "$cleanup_file"
    fi
    echo "" >> "$cleanup_file"
    
    # 5. 扫描防火墙规则
    echo "## 防火墙规则" >> "$cleanup_file"
    local firewall_rules
    firewall_rules=$(gcloud compute firewall-rules list --project="$project" --format="value(name,direction,priority,sourceRanges,allowed)" 2>/dev/null || echo "")
    
    if [[ -n "$firewall_rules" ]]; then
        while IFS=$'\t' read -r rule_name direction priority source_ranges allowed; do
            echo "- 防火墙规则: $rule_name ($direction, 优先级: $priority)" >> "$cleanup_file"
        done <<< "$firewall_rules"
    else
        echo "- 无自定义防火墙规则" >> "$cleanup_file"
    fi
    
    log_success "资源扫描完成: $cleanup_file"
    echo "$cleanup_file"
}

# 函数：检查资源使用情况
check_resource_usage() {
    local project=$1
    local resource_type=$2
    local resource_name=$3
    
    case "$resource_type" in
        "cluster")
            # 检查集群是否有活跃的工作负载
            gcloud container clusters get-credentials "$resource_name" --region="$CLUSTER_REGION" --project="$project" 2>/dev/null || return 1
            
            local pod_count
            pod_count=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
            
            if [[ "$pod_count" -gt 0 ]]; then
                log_warning "集群 $resource_name 仍有 $pod_count 个Pod运行"
                return 1
            fi
            ;;
        "forwarding-rule")
            # 检查转发规则是否有流量
            # 这里可以添加更复杂的流量检查逻辑
            log_info "检查转发规则 $resource_name 的使用情况"
            ;;
        "address")
            # 检查IP地址是否被使用
            local users
            users=$(gcloud compute addresses describe "$resource_name" --project="$project" --format="value(users)" 2>/dev/null || echo "")
            
            if [[ -n "$users" ]]; then
                log_warning "IP地址 $resource_name 仍被使用: $users"
                return 1
            fi
            ;;
        "disk")
            # 检查磁盘是否被挂载
            local users
            users=$(gcloud compute disks describe "$resource_name" --zone="$CLUSTER_REGION-a" --project="$project" --format="value(users)" 2>/dev/null || echo "")
            
            if [[ -n "$users" ]]; then
                log_warning "磁盘 $resource_name 仍被使用: $users"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# 函数：安全删除GKE集群
safe_delete_cluster() {
    local project=$1
    local cluster_name=$2
    local location=$3
    
    log_info "准备删除集群: $cluster_name"
    
    # 检查集群状态
    if ! check_resource_usage "$project" "cluster" "$cluster_name"; then
        log_error "集群 $cluster_name 仍在使用中，跳过删除"
        return 1
    fi
    
    # 确认删除
    read -p "确认删除集群 $cluster_name？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "跳过删除集群 $cluster_name"
        return 0
    fi
    
    # 执行删除
    log_info "删除集群 $cluster_name..."
    if gcloud container clusters delete "$cluster_name" --location="$location" --project="$project" --quiet; then
        log_success "集群 $cluster_name 删除成功"
        return 0
    else
        log_error "集群 $cluster_name 删除失败"
        return 1
    fi
}

# 函数：安全删除负载均衡器
safe_delete_load_balancer() {
    local project=$1
    local rule_name=$2
    
    log_info "准备删除转发规则: $rule_name"
    
    # 确认删除
    read -p "确认删除转发规则 $rule_name？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "跳过删除转发规则 $rule_name"
        return 0
    fi
    
    # 执行删除
    log_info "删除转发规则 $rule_name..."
    if gcloud compute forwarding-rules delete "$rule_name" --project="$project" --quiet; then
        log_success "转发规则 $rule_name 删除成功"
        return 0
    else
        log_error "转发规则 $rule_name 删除失败"
        return 1
    fi
}

# 函数：安全删除静态IP
safe_delete_static_ip() {
    local project=$1
    local ip_name=$2
    
    log_info "准备删除静态IP: $ip_name"
    
    # 检查IP使用情况
    if ! check_resource_usage "$project" "address" "$ip_name"; then
        log_error "静态IP $ip_name 仍在使用中，跳过删除"
        return 1
    fi
    
    # 确认删除
    read -p "确认删除静态IP $ip_name？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "跳过删除静态IP $ip_name"
        return 0
    fi
    
    # 执行删除
    log_info "删除静态IP $ip_name..."
    if gcloud compute addresses delete "$ip_name" --project="$project" --quiet; then
        log_success "静态IP $ip_name 删除成功"
        return 0
    else
        log_error "静态IP $ip_name 删除失败"
        return 1
    fi
}

# 函数：清理DNS记录中的过渡CNAME
cleanup_transition_cnames() {
    local project=$1
    local zone=$2
    
    log_info "清理项目 $project 中的过渡CNAME记录"
    
    # 检查是否存在指向目标项目的CNAME记录
    local cname_records
    cname_records=$(gcloud dns record-sets list --zone="$zone" --project="$project" --filter="type=CNAME" --format="value(name,rrdatas)" 2>/dev/null || echo "")
    
    if [[ -z "$cname_records" ]]; then
        log_info "未找到CNAME记录"
        return 0
    fi
    
    local cleanup_count=0
    while IFS=$'\t' read -r record_name record_data; do
        # 检查是否是指向目标项目的CNAME
        if [[ "$record_data" == *"${TARGET_PROJECT}.${PARENT_DOMAIN}"* ]]; then
            log_info "发现过渡CNAME记录: $record_name -> $record_data"
            
            read -p "删除过渡CNAME记录 $record_name？(yes/no): " -r
            if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                # 获取记录的TTL
                local ttl
                ttl=$(gcloud dns record-sets list --zone="$zone" --project="$project" --name="$record_name" --type=CNAME --format="value(ttl)" 2>/dev/null || echo "300")
                
                # 删除CNAME记录
                gcloud dns record-sets transaction start --zone="$zone" --project="$project"
                gcloud dns record-sets transaction remove "$record_data" \
                    --name="$record_name" \
                    --ttl="$ttl" \
                    --type=CNAME \
                    --zone="$zone" \
                    --project="$project"
                
                if gcloud dns record-sets transaction execute --zone="$zone" --project="$project"; then
                    log_success "过渡CNAME记录删除成功: $record_name"
                    ((cleanup_count++))
                else
                    log_error "过渡CNAME记录删除失败: $record_name"
                    gcloud dns record-sets transaction abort --zone="$zone" --project="$project" 2>/dev/null || true
                fi
            fi
        fi
    done <<< "$cname_records"
    
    log_info "清理了 $cleanup_count 个过渡CNAME记录"
}

# 函数：生成清理报告
generate_cleanup_report() {
    local cleanup_results=("$@")
    
    log_info "生成清理报告..."
    
    local report_file="$BACKUP_DIR/cleanup_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
# DNS 迁移清理报告
# 执行时间: $(date)
# 源项目: $SOURCE_PROJECT
# 目标项目: $TARGET_PROJECT

## 清理操作摘要
EOF
    
    local success_count=0
    local total_operations=${#cleanup_results[@]}
    
    for result in "${cleanup_results[@]}"; do
        echo "- $result" >> "$report_file"
        
        if [[ "$result" == *"SUCCESS"* ]]; then
            ((success_count++))
        fi
    done
    
    cat >> "$report_file" << EOF

## 统计信息
- 总计操作: $total_operations
- 成功清理: $success_count
- 跳过/失败: $((total_operations - success_count))

## 清理后状态
- 源项目中的旧资源已按选择进行清理
- 目标项目继续正常运行
- DNS记录已优化，移除了不必要的过渡记录

## 后续建议
1. 定期检查和清理未使用的资源
2. 更新监控和告警配置
3. 更新文档和运维手册
4. 考虑设置资源使用监控和自动清理策略

## 注意事项
- 保留此报告用于审计和问题追踪
- 如发现误删除，可参考备份文件进行恢复
EOF
    
    log_success "清理报告生成完成: $report_file"
    echo "$report_file"
}

# 函数：交互式清理确认
confirm_cleanup() {
    echo ""
    echo "=== DNS 迁移清理确认 ==="
    echo "此操作将清理源项目 ($SOURCE_PROJECT) 中的以下类型资源:"
    echo "1. 不再使用的GKE集群"
    echo "2. 不再使用的负载均衡器"
    echo "3. 未使用的静态IP地址"
    echo "4. 过渡期的CNAME记录"
    echo ""
    echo "警告: 清理操作不可逆，请确保已完成迁移验证"
    echo ""
    read -p "确认开始清理操作？(yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "用户取消清理操作"
        exit 0
    fi
}

# 主执行流程
main() {
    log_info "=== DNS 迁移清理阶段开始 ==="
    
    # 交互式确认
    confirm_cleanup
    
    # 验证项目访问权限
    verify_project_access "$SOURCE_PROJECT"
    
    # 1. 扫描可清理的资源
    log_info "步骤 1: 扫描可清理的资源"
    local cleanup_candidates_file
    cleanup_candidates_file=$(list_cleanup_candidates "$SOURCE_PROJECT")
    
    echo ""
    echo "请查看清理候选资源:"
    echo "cat $cleanup_candidates_file"
    echo ""
    read -p "按回车键继续清理操作..." -r
    
    # 2. 清理GKE集群
    log_info "步骤 2: 清理GKE集群"
    local cleanup_results=()
    
    local clusters
    clusters=$(gcloud container clusters list --project="$SOURCE_PROJECT" --format="value(name,location)" 2>/dev/null || echo "")
    
    if [[ -n "$clusters" ]]; then
        while IFS=$'\t' read -r cluster_name location; do
            if safe_delete_cluster "$SOURCE_PROJECT" "$cluster_name" "$location"; then
                cleanup_results+=("集群 $cluster_name: SUCCESS")
            else
                cleanup_results+=("集群 $cluster_name: SKIPPED/FAILED")
            fi
        done <<< "$clusters"
    fi
    
    # 3. 清理负载均衡器
    log_info "步骤 3: 清理负载均衡器"
    local forwarding_rules
    forwarding_rules=$(gcloud compute forwarding-rules list --project="$SOURCE_PROJECT" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$forwarding_rules" ]]; then
        while read -r rule_name; do
            if [[ -n "$rule_name" ]]; then
                if safe_delete_load_balancer "$SOURCE_PROJECT" "$rule_name"; then
                    cleanup_results+=("转发规则 $rule_name: SUCCESS")
                else
                    cleanup_results+=("转发规则 $rule_name: SKIPPED/FAILED")
                fi
            fi
        done <<< "$forwarding_rules"
    fi
    
    # 4. 清理静态IP地址
    log_info "步骤 4: 清理静态IP地址"
    local static_ips
    static_ips=$(gcloud compute addresses list --project="$SOURCE_PROJECT" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$static_ips" ]]; then
        while read -r ip_name; do
            if [[ -n "$ip_name" ]]; then
                if safe_delete_static_ip "$SOURCE_PROJECT" "$ip_name"; then
                    cleanup_results+=("静态IP $ip_name: SUCCESS")
                else
                    cleanup_results+=("静态IP $ip_name: SKIPPED/FAILED")
                fi
            fi
        done <<< "$static_ips"
    fi
    
    # 5. 清理过渡CNAME记录
    log_info "步骤 5: 清理过渡CNAME记录"
    cleanup_transition_cnames "$SOURCE_PROJECT" "$SOURCE_ZONE"
    cleanup_results+=("过渡CNAME记录清理: COMPLETED")
    
    # 6. 生成清理报告
    log_info "步骤 6: 生成清理报告"
    local report_file
    report_file=$(generate_cleanup_report "${cleanup_results[@]}")
    
    log_success "=== DNS 迁移清理阶段完成 ==="
    log_info "清理候选资源: $cleanup_candidates_file"
    log_info "清理报告: $report_file"
    
    echo ""
    echo "清理操作完成！"
    echo "建议："
    echo "1. 检查清理报告确认所有操作"
    echo "2. 验证目标项目服务正常运行"
    echo "3. 更新相关文档和监控配置"
    echo "4. 定期检查和清理未使用的资源"
}

# 执行主函数
main "$@"
```

## `config.sh`

```bash
#!/bin/bash

# GCP DNS 迁移配置文件
# 请根据实际环境修改以下配置

# 项目配置
export SOURCE_PROJECT="project-id"
export TARGET_PROJECT="project-id2"
export PARENT_DOMAIN="dev.aliyun.cloud.uk.aibang"

# DNS Zone 配置
export SOURCE_ZONE="${SOURCE_PROJECT}-${PARENT_DOMAIN//./-}"
export TARGET_ZONE="${TARGET_PROJECT}-${PARENT_DOMAIN//./-}"

# 集群配置
export SOURCE_CLUSTER="gke-01"
export TARGET_CLUSTER="gke-01"
export CLUSTER_REGION="europe-west2"

# 域名映射配置 (格式: "subdomain:service_type")
# service_type: ingress|ilb|service
export DOMAIN_MAPPINGS=(
    "events:ilb"
    "events-proxy:ingress"
    "api:ingress"
    "admin:ingress"
)

# DNS TTL 配置
export DEFAULT_TTL=300
export MIGRATION_TTL=60

# 备份目录
export BACKUP_DIR="./backup/$(date +%Y%m%d_%H%M%S)"

# 日志配置
export LOG_FILE="./logs/migration_$(date +%Y%m%d_%H%M%S).log"
export DEBUG=true

# 验证配置
export VALIDATION_TIMEOUT=300  # 5分钟
export HEALTH_CHECK_ENDPOINTS=(
    "/health"
    "/api/health"
    "/status"
)

# 颜色输出配置
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# 函数：打印带颜色的日志
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# 函数：检查必要的工具
check_prerequisites() {
    local tools=("gcloud" "kubectl" "dig" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool 未安装或不在 PATH 中"
            return 1
        fi
    done
    
    # 检查 gcloud 认证
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud 未认证，请运行 'gcloud auth login'"
        return 1
    fi
    
    log_success "所有必要工具检查通过"
    return 0
}

# 函数：创建必要的目录
setup_directories() {
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$BACKUP_DIR"
    log_info "创建目录: $BACKUP_DIR"
}

# 函数：验证项目访问权限
verify_project_access() {
    local project=$1
    if ! gcloud projects describe "$project" &>/dev/null; then
        log_error "无法访问项目: $project"
        return 1
    fi
    log_success "项目访问验证通过: $project"
    return 0
}
```

## `migrate-dns.sh`

```bash
#!/bin/bash

# DNS 迁移主控制脚本
# 功能：统一管理整个DNS迁移流程

set -euo pipefail

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置
source "$SCRIPT_DIR/config.sh"

# 函数：显示帮助信息
show_help() {
    cat << EOF
DNS 迁移工具 - GCP 跨项目DNS迁移自动化脚本

用法: $0 [选项] [阶段]

阶段:
  discovery     发现和分析源项目与目标项目的服务映射关系
  prepare       在目标项目中准备DNS记录和SSL证书
  migrate       执行DNS切换，将流量从源项目切换到目标项目
  rollback      回滚DNS记录到迁移前状态
  cleanup       清理源项目中不再使用的资源
  all           执行完整的迁移流程 (discovery -> prepare -> migrate)

选项:
  -h, --help              显示此帮助信息
  -c, --config FILE       指定配置文件 (默认: config.sh)
  -d, --dry-run          干运行模式，只显示将要执行的操作
  -v, --verbose          详细输出模式
  -f, --force            强制执行，跳过确认提示
  --source-project ID    源项目ID (覆盖配置文件)
  --target-project ID    目标项目ID (覆盖配置文件)

示例:
  $0 discovery                    # 发现服务映射关系
  $0 prepare                      # 准备目标项目
  $0 migrate                      # 执行迁移
  $0 all                          # 执行完整迁移流程
  $0 rollback                     # 回滚迁移
  $0 cleanup                      # 清理资源
  
  $0 --dry-run migrate           # 干运行迁移
  $0 --force cleanup             # 强制清理，跳过确认
  $0 --source-project proj1 --target-project proj2 all

配置:
  在执行前，请确保已正确配置 config.sh 文件中的以下参数:
  - SOURCE_PROJECT: 源项目ID
  - TARGET_PROJECT: 目标项目ID
  - PARENT_DOMAIN: 父域名
  - DOMAIN_MAPPINGS: 域名映射配置
  - 其他相关配置参数

注意事项:
  1. 确保已安装并配置 gcloud、kubectl 工具
  2. 确保对源项目和目标项目有足够的权限
  3. 建议先在测试环境验证整个流程
  4. 迁移前请做好备份和回滚准备
EOF
}

# 函数：显示当前配置
show_config() {
    echo "=== 当前配置 ==="
    echo "源项目: $SOURCE_PROJECT"
    echo "目标项目: $TARGET_PROJECT"
    echo "父域名: $PARENT_DOMAIN"
    echo "集群区域: $CLUSTER_REGION"
    echo "备份目录: $BACKUP_DIR"
    echo "日志文件: $LOG_FILE"
    echo ""
    echo "域名映射:"
    for mapping in "${DOMAIN_MAPPINGS[@]}"; do
        IFS=':' read -r subdomain service_type <<< "$mapping"
        echo "  ${subdomain}.${SOURCE_PROJECT}.${PARENT_DOMAIN} -> ${subdomain}.${TARGET_PROJECT}.${PARENT_DOMAIN} ($service_type)"
    done
    echo ""
}

# 函数：检查阶段依赖
check_stage_dependencies() {
    local stage=$1
    
    case "$stage" in
        "prepare")
            if [[ ! -f "$BACKUP_DIR"/*_endpoints.txt ]]; then
                log_warning "未找到服务发现结果，建议先运行 discovery 阶段"
                read -p "是否继续？(yes/no): " -r
                if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                    exit 0
                fi
            fi
            ;;
        "migrate")
            if [[ ! -f "$BACKUP_DIR"/*_dns_verification.txt ]]; then
                log_warning "未找到目标项目DNS验证结果，建议先运行 prepare 阶段"
                read -p "是否继续？(yes/no): " -r
                if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                    exit 0
                fi
            fi
            ;;
        "rollback")
            if [[ ! -f "$BACKUP_DIR"/*_dns_backup_*.json ]]; then
                log_error "未找到DNS备份文件，无法执行回滚"
                exit 1
            fi
            ;;
        "cleanup")
            if [[ ! -f "$BACKUP_DIR"/migration_report_*.txt ]]; then
                log_warning "未找到迁移报告，建议先完成迁移"
                read -p "是否继续清理？(yes/no): " -r
                if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                    exit 0
                fi
            fi
            ;;
    esac
}

# 函数：执行单个阶段
execute_stage() {
    local stage=$1
    local script_file=""
    
    case "$stage" in
        "discovery")
            script_file="$SCRIPT_DIR/01-discovery.sh"
            ;;
        "prepare")
            script_file="$SCRIPT_DIR/02-prepare-target.sh"
            ;;
        "migrate")
            script_file="$SCRIPT_DIR/03-execute-migration.sh"
            ;;
        "rollback")
            script_file="$SCRIPT_DIR/04-rollback.sh"
            ;;
        "cleanup")
            script_file="$SCRIPT_DIR/05-cleanup.sh"
            ;;
        *)
            log_error "未知阶段: $stage"
            return 1
            ;;
    esac
    
    if [[ ! -f "$script_file" ]]; then
        log_error "脚本文件不存在: $script_file"
        return 1
    fi
    
    log_info "执行阶段: $stage"
    log_info "脚本文件: $script_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] 将要执行: $script_file"
        return 0
    fi
    
    # 检查阶段依赖
    if [[ "$FORCE_MODE" != "true" ]]; then
        check_stage_dependencies "$stage"
    fi
    
    # 执行脚本
    if bash "$script_file"; then
        log_success "阶段 $stage 执行成功"
        return 0
    else
        log_error "阶段 $stage 执行失败"
        return 1
    fi
}

# 函数：执行完整迁移流程
execute_full_migration() {
    log_info "开始执行完整DNS迁移流程..."
    
    local stages=("discovery" "prepare" "migrate")
    
    for stage in "${stages[@]}"; do
        log_info "=== 执行阶段: $stage ==="
        
        if ! execute_stage "$stage"; then
            log_error "阶段 $stage 失败，停止执行"
            echo ""
            echo "建议："
            echo "1. 检查错误日志: $LOG_FILE"
            echo "2. 修复问题后重新运行失败的阶段"
            echo "3. 如需回滚，运行: $0 rollback"
            return 1
        fi
        
        # 在阶段之间添加暂停，让用户有机会检查结果
        if [[ "$FORCE_MODE" != "true" && "$stage" != "migrate" ]]; then
            echo ""
            read -p "阶段 $stage 完成，按回车键继续下一阶段..." -r
        fi
    done
    
    log_success "完整DNS迁移流程执行成功！"
    echo ""
    echo "后续步骤："
    echo "1. 监控目标服务24-48小时"
    echo "2. 验证所有应用功能正常"
    echo "3. 运行清理脚本: $0 cleanup"
}

# 函数：显示迁移状态
show_migration_status() {
    log_info "检查迁移状态..."
    
    echo "=== 迁移状态检查 ==="
    
    # 检查各阶段的输出文件
    local discovery_done=false
    local prepare_done=false
    local migrate_done=false
    local rollback_done=false
    local cleanup_done=false
    
    if [[ -f "$BACKUP_DIR"/*_endpoints.txt ]]; then
        discovery_done=true
        echo "✓ Discovery 阶段已完成"
    else
        echo "✗ Discovery 阶段未完成"
    fi
    
    if [[ -f "$BACKUP_DIR"/*_dns_verification.txt ]]; then
        prepare_done=true
        echo "✓ Prepare 阶段已完成"
    else
        echo "✗ Prepare 阶段未完成"
    fi
    
    if [[ -f "$BACKUP_DIR"/migration_report_*.txt ]]; then
        migrate_done=true
        echo "✓ Migrate 阶段已完成"
        
        # 显示迁移结果摘要
        local latest_report
        latest_report=$(ls -t "$BACKUP_DIR"/migration_report_*.txt 2>/dev/null | head -1 || echo "")
        if [[ -n "$latest_report" ]]; then
            echo "  最新迁移报告: $latest_report"
            local success_count
            success_count=$(grep "成功迁移:" "$latest_report" | cut -d: -f2 | tr -d ' ' || echo "0")
            echo "  迁移结果: $success_count"
        fi
    else
        echo "✗ Migrate 阶段未完成"
    fi
    
    if [[ -f "$BACKUP_DIR"/rollback_report_*.txt ]]; then
        rollback_done=true
        echo "✓ Rollback 已执行"
    fi
    
    if [[ -f "$BACKUP_DIR"/cleanup_report_*.txt ]]; then
        cleanup_done=true
        echo "✓ Cleanup 已完成"
    else
        echo "✗ Cleanup 未完成"
    fi
    
    echo ""
    echo "建议的下一步操作:"
    if [[ "$discovery_done" == false ]]; then
        echo "  $0 discovery"
    elif [[ "$prepare_done" == false ]]; then
        echo "  $0 prepare"
    elif [[ "$migrate_done" == false ]]; then
        echo "  $0 migrate"
    elif [[ "$cleanup_done" == false && "$rollback_done" == false ]]; then
        echo "  $0 cleanup  # 清理源项目资源"
    else
        echo "  迁移流程已完成"
    fi
}

# 解析命令行参数
DRY_RUN=false
VERBOSE=false
FORCE_MODE=false
CUSTOM_CONFIG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--config)
            CUSTOM_CONFIG="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            DEBUG=true
            shift
            ;;
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        --source-project)
            SOURCE_PROJECT="$2"
            shift 2
            ;;
        --target-project)
            TARGET_PROJECT="$2"
            shift 2
            ;;
        discovery|prepare|migrate|rollback|cleanup|all|status)
            STAGE="$1"
            shift
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 重新加载自定义配置（如果指定）
if [[ -n "$CUSTOM_CONFIG" ]]; then
    if [[ -f "$CUSTOM_CONFIG" ]]; then
        source "$CUSTOM_CONFIG"
        log_info "使用自定义配置文件: $CUSTOM_CONFIG"
    else
        log_error "配置文件不存在: $CUSTOM_CONFIG"
        exit 1
    fi
fi

# 初始化
setup_directories
check_prerequisites

# 显示配置信息
if [[ "$VERBOSE" == "true" ]]; then
    show_config
fi

# 检查必要参数
if [[ -z "${STAGE:-}" ]]; then
    echo "错误: 请指定要执行的阶段"
    echo ""
    show_help
    exit 1
fi

# 主执行逻辑
case "$STAGE" in
    "all")
        execute_full_migration
        ;;
    "status")
        show_migration_status
        ;;
    *)
        execute_stage "$STAGE"
        ;;
esac
```

