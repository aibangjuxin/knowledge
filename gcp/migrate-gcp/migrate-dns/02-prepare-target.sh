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