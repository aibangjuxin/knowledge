#!/bin/bash

# 验证脚本 - 验证迁移结果和资源状态

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
EXPORTS_DIR="${PROJECT_DIR}/exports"

# 参数
NAMESPACE="$1"
DRY_RUN="${2:-false}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$*"
    
    case $level in
        "INFO")
            echo -e "${GREEN}[VALIDATE-INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[VALIDATE-WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[VALIDATE-ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[VALIDATE-DEBUG]${NC} $message"
            ;;
    esac
}

# 检查集群连接
check_cluster_connection() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log "ERROR" "无法连接到集群"
        return 1
    fi
    
    local context=$(kubectl config current-context)
    log "INFO" "当前集群上下文: $context"
    return 0
}

# 检查 namespace 是否存在
check_namespace_exists() {
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "INFO" "干运行模式: 跳过 namespace 存在性检查"
        return 0
    fi
    
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log "ERROR" "Namespace '$NAMESPACE' 不存在"
        return 1
    fi
    
    log "INFO" "Namespace '$NAMESPACE' 存在"
    return 0
}

# 验证 Deployments
validate_deployments() {
    log "INFO" "验证 Deployments..."
    
    local deployments
    deployments=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$deployments" -eq 0 ]]; then
        log "INFO" "没有 Deployments 需要验证"
        return 0
    fi
    
    local ready_deployments=0
    local total_deployments=0
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local name=$(echo "$line" | awk '{print $1}')
            local ready=$(echo "$line" | awk '{print $2}')
            local available=$(echo "$line" | awk '{print $4}')
            
            ((total_deployments++))
            
            if [[ "$available" == "True" ]]; then
                ((ready_deployments++))
                log "INFO" "Deployment $name: ✓ ($ready)"
            else
                log "WARN" "Deployment $name: ⚠️ ($ready, 不可用)"
            fi
        fi
    done < <(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null)
    
    log "INFO" "Deployments 验证: $ready_deployments/$total_deployments 就绪"
    
    if [[ $ready_deployments -eq $total_deployments ]]; then
        return 0
    else
        return 1
    fi
}

# 验证 Services
validate_services() {
    log "INFO" "验证 Services..."
    
    local services
    services=$(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$services" -eq 0 ]]; then
        log "INFO" "没有 Services 需要验证"
        return 0
    fi
    
    local valid_services=0
    local total_services=0
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local name=$(echo "$line" | awk '{print $1}')
            local type=$(echo "$line" | awk '{print $2}')
            local cluster_ip=$(echo "$line" | awk '{print $3}')
            
            ((total_services++))
            
            # 检查 endpoints
            local endpoints
            endpoints=$(kubectl get endpoints "$name" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
            
            if [[ -n "$endpoints" ]]; then
                ((valid_services++))
                log "INFO" "Service $name ($type): ✓ (有端点)"
            else
                log "WARN" "Service $name ($type): ⚠️ (无端点)"
            fi
        fi
    done < <(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null)
    
    log "INFO" "Services 验证: $valid_services/$total_services 有效"
    
    if [[ $valid_services -eq $total_services ]]; then
        return 0
    else
        return 1
    fi
}

# 验证 Pods
validate_pods() {
    log "INFO" "验证 Pods..."
    
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$pods" -eq 0 ]]; then
        log "INFO" "没有 Pods 需要验证"
        return 0
    fi
    
    local running_pods=0
    local total_pods=0
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local name=$(echo "$line" | awk '{print $1}')
            local ready=$(echo "$line" | awk '{print $2}')
            local status=$(echo "$line" | awk '{print $3}')
            local restarts=$(echo "$line" | awk '{print $4}')
            
            ((total_pods++))
            
            if [[ "$status" == "Running" ]]; then
                ((running_pods++))
                log "INFO" "Pod $name: ✓ ($status, $ready, 重启: $restarts)"
            else
                log "WARN" "Pod $name: ⚠️ ($status, $ready, 重启: $restarts)"
            fi
        fi
    done < <(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null)
    
    log "INFO" "Pods 验证: $running_pods/$total_pods 运行中"
    
    if [[ $running_pods -eq $total_pods ]]; then
        return 0
    else
        return 1
    fi
}

# 验证 PVCs
validate_pvcs() {
    log "INFO" "验证 PersistentVolumeClaims..."
    
    local pvcs
    pvcs=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$pvcs" -eq 0 ]]; then
        log "INFO" "没有 PVCs 需要验证"
        return 0
    fi
    
    local bound_pvcs=0
    local total_pvcs=0
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local name=$(echo "$line" | awk '{print $1}')
            local status=$(echo "$line" | awk '{print $2}')
            local volume=$(echo "$line" | awk '{print $3}')
            local capacity=$(echo "$line" | awk '{print $4}')
            
            ((total_pvcs++))
            
            if [[ "$status" == "Bound" ]]; then
                ((bound_pvcs++))
                log "INFO" "PVC $name: ✓ ($status, $capacity)"
            else
                log "WARN" "PVC $name: ⚠️ ($status)"
            fi
        fi
    done < <(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null)
    
    log "INFO" "PVCs 验证: $bound_pvcs/$total_pvcs 已绑定"
    
    if [[ $bound_pvcs -eq $total_pvcs ]]; then
        return 0
    else
        return 1
    fi
}

# 验证 Ingresses
validate_ingresses() {
    log "INFO" "验证 Ingresses..."
    
    local ingresses
    ingresses=$(kubectl get ingresses -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$ingresses" -eq 0 ]]; then
        log "INFO" "没有 Ingresses 需要验证"
        return 0
    fi
    
    local ready_ingresses=0
    local total_ingresses=0
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local name=$(echo "$line" | awk '{print $1}')
            local class=$(echo "$line" | awk '{print $2}')
            local hosts=$(echo "$line" | awk '{print $3}')
            local address=$(echo "$line" | awk '{print $4}')
            
            ((total_ingresses++))
            
            if [[ -n "$address" && "$address" != "<none>" ]]; then
                ((ready_ingresses++))
                log "INFO" "Ingress $name: ✓ ($address)"
            else
                log "WARN" "Ingress $name: ⚠️ (无地址)"
            fi
        fi
    done < <(kubectl get ingresses -n "$NAMESPACE" --no-headers 2>/dev/null)
    
    log "INFO" "Ingresses 验证: $ready_ingresses/$total_ingresses 就绪"
    
    if [[ $ready_ingresses -eq $total_ingresses ]]; then
        return 0
    else
        return 1
    fi
}

# 验证 ConfigMaps 和 Secrets
validate_config_resources() {
    log "INFO" "验证 ConfigMaps 和 Secrets..."
    
    local configmaps
    configmaps=$(kubectl get configmaps -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    local secrets
    secrets=$(kubectl get secrets -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    log "INFO" "ConfigMaps: $configmaps 个"
    log "INFO" "Secrets: $secrets 个"
    
    # 检查是否有系统生成的 secrets
    local system_secrets
    system_secrets=$(kubectl get secrets -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "kubernetes.io/service-account-token" || echo "0")
    
    if [[ "$system_secrets" -gt 0 ]]; then
        log "INFO" "系统生成的 Service Account Tokens: $system_secrets 个"
    fi
    
    return 0
}

# 验证 RBAC 资源
validate_rbac() {
    log "INFO" "验证 RBAC 资源..."
    
    local roles
    roles=$(kubectl get roles -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    local rolebindings
    rolebindings=$(kubectl get rolebindings -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    local serviceaccounts
    serviceaccounts=$(kubectl get serviceaccounts -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    log "INFO" "Roles: $roles 个"
    log "INFO" "RoleBindings: $rolebindings 个"
    log "INFO" "ServiceAccounts: $serviceaccounts 个"
    
    return 0
}

# 检查资源健康状态
check_resource_health() {
    log "INFO" "检查资源健康状态..."
    
    # 检查是否有失败的 Pods
    local failed_pods
    failed_pods=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$failed_pods" -gt 0 ]]; then
        log "WARN" "发现 $failed_pods 个失败的 Pods"
        kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Failed
    fi
    
    # 检查是否有 Pending 的 Pods
    local pending_pods
    pending_pods=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$pending_pods" -gt 0 ]]; then
        log "WARN" "发现 $pending_pods 个 Pending 的 Pods"
        kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending
    fi
    
    # 检查重启次数过多的 Pods
    local high_restart_pods
    high_restart_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '$4 > 5 {print $1}' | wc -l || echo "0")
    
    if [[ "$high_restart_pods" -gt 0 ]]; then
        log "WARN" "发现 $high_restart_pods 个重启次数过多的 Pods (>5次)"
    fi
    
    return 0
}

# 生成验证报告
generate_validation_report() {
    local report_file="${EXPORTS_DIR}/${NAMESPACE}_latest/validation-report.md"
    
    log "INFO" "生成验证报告..."
    
    cat > "$report_file" << EOF
# Namespace 验证报告

**Namespace:** $NAMESPACE  
**验证时间:** $(date)  
**集群上下文:** $(kubectl config current-context)

## 资源概览

EOF
    
    # 获取各种资源的数量
    local resources=(
        "deployments" "statefulsets" "daemonsets" "services" "ingresses"
        "configmaps" "secrets" "persistentvolumeclaims" "serviceaccounts"
        "roles" "rolebindings" "networkpolicies" "horizontalpodautoscalers"
        "poddisruptionbudgets" "jobs" "cronjobs"
    )
    
    echo "| 资源类型 | 数量 |" >> "$report_file"
    echo "|----------|------|" >> "$report_file"
    
    for resource in "${resources[@]}"; do
        local count
        count=$(kubectl get "$resource" -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        echo "| $resource | $count |" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Pod 状态详情

EOF
    
    echo "| Pod 名称 | 状态 | 就绪 | 重启次数 |" >> "$report_file"
    echo "|----------|------|------|----------|" >> "$report_file"
    
    kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local name=$(echo "$line" | awk '{print $1}')
            local ready=$(echo "$line" | awk '{print $2}')
            local status=$(echo "$line" | awk '{print $3}')
            local restarts=$(echo "$line" | awk '{print $4}')
            
            echo "| $name | $status | $ready | $restarts |" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF

## 验证结果

- ✅ 表示验证通过
- ⚠️ 表示需要注意
- ❌ 表示验证失败

## 建议

1. 检查所有 Pod 是否正常运行
2. 验证服务端点是否可访问
3. 检查 Ingress 配置是否正确
4. 验证 PVC 数据是否完整
5. 测试应用功能是否正常

EOF
    
    log "INFO" "验证报告已生成: $report_file"
}

# 主函数
main() {
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "INFO" "开始验证 namespace: $NAMESPACE (干运行模式)"
    else
        log "INFO" "开始验证 namespace: $NAMESPACE"
    fi
    
    # 检查集群连接
    if ! check_cluster_connection; then
        exit 1
    fi
    
    # 检查 namespace 是否存在
    if ! check_namespace_exists; then
        exit 1
    fi
    
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "INFO" "干运行模式: 验证完成"
        exit 0
    fi
    
    # 执行各项验证
    local validation_results=()
    
    if validate_deployments; then
        validation_results+=("Deployments: ✅")
    else
        validation_results+=("Deployments: ⚠️")
    fi
    
    if validate_services; then
        validation_results+=("Services: ✅")
    else
        validation_results+=("Services: ⚠️")
    fi
    
    if validate_pods; then
        validation_results+=("Pods: ✅")
    else
        validation_results+=("Pods: ⚠️")
    fi
    
    if validate_pvcs; then
        validation_results+=("PVCs: ✅")
    else
        validation_results+=("PVCs: ⚠️")
    fi
    
    if validate_ingresses; then
        validation_results+=("Ingresses: ✅")
    else
        validation_results+=("Ingresses: ⚠️")
    fi
    
    validate_config_resources
    validation_results+=("ConfigMaps/Secrets: ✅")
    
    validate_rbac
    validation_results+=("RBAC: ✅")
    
    check_resource_health
    
    # 生成验证报告
    generate_validation_report
    
    # 显示验证结果摘要
    log "INFO" "验证结果摘要:"
    for result in "${validation_results[@]}"; do
        log "INFO" "  $result"
    done
    
    log "INFO" "验证完成"
}

# 执行主函数
main