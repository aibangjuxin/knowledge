#!/bin/bash

# Kubernetes Namespace Status Check Script
# Usage: ./namespace-status.sh -n <namespace-name>
# 检查指定namespace中Ingress、Deployment和Pod的对应关系和状态

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的状态信息
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 显示使用说明
show_usage() {
    echo "Usage: $0 -n <namespace-name>"
    echo "  -n: Kubernetes namespace name"
    echo ""
    echo "Example:"
    echo "  $0 -n default"
    echo "  $0 -n my-app-namespace"
    exit 1
}

# 检查kubectl是否可用
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_status $RED "Error: kubectl command not found. Please install kubectl first."
        exit 1
    fi
}

# 检查namespace是否存在
check_namespace() {
    local namespace=$1
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        print_status $RED "Error: Namespace '$namespace' not found."
        exit 1
    fi
}

# 获取Ingress信息
get_ingress_info() {
    local namespace=$1
    kubectl get ingress -n "$namespace" -o custom-columns="NAME:.metadata.name,HOSTS:.spec.rules[*].host" --no-headers 2>/dev/null
}

# 获取Deployment信息
get_deployment_info() {
    local namespace=$1
    kubectl get deployment -n "$namespace" -o custom-columns="NAME:.metadata.name,READY:.status.readyReplicas,REPLICAS:.status.replicas,AVAILABLE:.status.availableReplicas" --no-headers 2>/dev/null
}

# 获取Pod信息
get_pod_info() {
    local namespace=$1
    local deployment_name=$2
    kubectl get pods -n "$namespace" -l app="$deployment_name" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[*].ready" --no-headers 2>/dev/null
}

# 获取Pod信息（通过deployment selector）
get_pods_by_deployment() {
    local namespace=$1
    local deployment_name=$2
    
    # 获取deployment的selector
    local selector=$(kubectl get deployment "$deployment_name" -n "$namespace" -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null)
    
    if [ -n "$selector" ]; then
        # 解析selector并构建label selector字符串
        local label_selector=$(echo "$selector" | sed 's/[{}"]//g' | sed 's/:/=/g' | sed 's/,/,/g')
        kubectl get pods -n "$namespace" -l "$label_selector" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount" --no-headers 2>/dev/null
    else
        # fallback: 尝试使用app label
        kubectl get pods -n "$namespace" -l app="$deployment_name" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount" --no-headers 2>/dev/null
    fi
}

# 分析Pod状态
analyze_pod_status() {
    local pod_line=$1
    local pod_name=$(echo "$pod_line" | awk '{print $1}')
    local pod_status=$(echo "$pod_line" | awk '{print $2}')
    local pod_ready=$(echo "$pod_line" | awk '{print $3}')
    local pod_restarts=$(echo "$pod_line" | awk '{print $4}')
    
    # 判断Pod是否健康
    if [[ "$pod_status" == "Running" && "$pod_ready" == "true" ]]; then
        echo "✓ $pod_name (Running, Ready, Restarts: ${pod_restarts:-0})"
        return 0  # 健康
    else
        echo "✗ $pod_name ($pod_status, Ready: $pod_ready, Restarts: ${pod_restarts:-0})"
        return 1  # 不健康
    fi
}

# 主要处理函数
process_namespace_status() {
    local namespace=$1
    
    print_status $BLUE "=== Namespace: $namespace Status Report ==="
    echo
    
    # 获取Ingress信息
    print_status $YELLOW "📋 Getting Ingress resources..."
    local ingress_data=$(get_ingress_info "$namespace")
    
    if [ -z "$ingress_data" ]; then
        print_status $YELLOW "No Ingress resources found in namespace '$namespace'"
        echo
    fi
    
    # 获取Deployment信息
    print_status $YELLOW "📋 Getting Deployment resources..."
    local deployment_data=$(get_deployment_info "$namespace")
    
    if [ -z "$deployment_data" ]; then
        print_status $YELLOW "No Deployment resources found in namespace '$namespace'"
        echo
        return
    fi
    
    # 输出表头
    printf "%-30s %-40s %-15s %s\n" "NAME" "HOSTS" "DEPLOY_STATUS" "POD_STATUS"
    printf "%-30s %-40s %-15s %s\n" "----" "-----" "-------------" "----------"
    
    # 处理每个Ingress
    if [ -n "$ingress_data" ]; then
        while IFS= read -r ingress_line; do
            if [ -n "$ingress_line" ]; then
                local ingress_name=$(echo "$ingress_line" | awk '{print $1}')
                local ingress_hosts=$(echo "$ingress_line" | awk '{print $2}')
                
                # 查找对应的Deployment
                local matching_deployment=$(echo "$deployment_data" | grep "^$ingress_name ")
                
                if [ -n "$matching_deployment" ]; then
                    local deploy_ready=$(echo "$matching_deployment" | awk '{print $2}')
                    local deploy_replicas=$(echo "$matching_deployment" | awk '{print $3}')
                    local deploy_available=$(echo "$matching_deployment" | awk '{print $4}')
                    
                    # Deployment状态
                    local deploy_status
                    if [[ "$deploy_ready" == "$deploy_replicas" && "$deploy_available" == "$deploy_replicas" ]]; then
                        deploy_status="✓ ${deploy_ready}/${deploy_replicas}"
                    else
                        deploy_status="✗ ${deploy_ready:-0}/${deploy_replicas:-0}"
                    fi
                    
                    # 获取Pod信息
                    local pod_data=$(get_pods_by_deployment "$namespace" "$ingress_name")
                    
                    if [ -n "$pod_data" ]; then
                        local healthy_pods=0
                        local total_pods=0
                        local pod_status_summary=""
                        
                        while IFS= read -r pod_line; do
                            if [ -n "$pod_line" ]; then
                                total_pods=$((total_pods + 1))
                                if analyze_pod_status "$pod_line" >/dev/null; then
                                    healthy_pods=$((healthy_pods + 1))
                                fi
                            fi
                        done <<< "$pod_data"
                        
                        if [ $healthy_pods -eq $total_pods ]; then
                            pod_status_summary="✓ ${healthy_pods}/${total_pods} healthy"
                        else
                            pod_status_summary="✗ ${healthy_pods}/${total_pods} healthy"
                        fi
                    else
                        pod_status_summary="No pods found"
                    fi
                    
                    # 输出汇总行
                    printf "%-30s %-40s %-15s %s\n" "$ingress_name" "$ingress_hosts" "$deploy_status" "$pod_status_summary"
                    
                else
                    printf "%-30s %-40s %-15s %s\n" "$ingress_name" "$ingress_hosts" "No deployment" "N/A"
                fi
            fi
        done <<< "$ingress_data"
    fi
    
    # 处理没有对应Ingress的Deployment
    echo
    print_status $YELLOW "📋 Deployments without matching Ingress:"
    while IFS= read -r deploy_line; do
        if [ -n "$deploy_line" ]; then
            local deploy_name=$(echo "$deploy_line" | awk '{print $1}')
            
            # 检查是否有对应的Ingress
            local has_ingress=$(echo "$ingress_data" | grep "^$deploy_name ")
            
            if [ -z "$has_ingress" ]; then
                local deploy_ready=$(echo "$deploy_line" | awk '{print $2}')
                local deploy_replicas=$(echo "$deploy_line" | awk '{print $3}')
                local deploy_available=$(echo "$deploy_line" | awk '{print $4}')
                
                local deploy_status
                if [[ "$deploy_ready" == "$deploy_replicas" && "$deploy_available" == "$deploy_replicas" ]]; then
                    deploy_status="✓ ${deploy_ready}/${deploy_replicas}"
                else
                    deploy_status="✗ ${deploy_ready:-0}/${deploy_replicas:-0}"
                fi
                
                # 获取Pod信息
                local pod_data=$(get_pods_by_deployment "$namespace" "$deploy_name")
                local pod_status_summary="No pods found"
                
                if [ -n "$pod_data" ]; then
                    local healthy_pods=0
                    local total_pods=0
                    
                    while IFS= read -r pod_line; do
                        if [ -n "$pod_line" ]; then
                            total_pods=$((total_pods + 1))
                            if analyze_pod_status "$pod_line" >/dev/null; then
                                healthy_pods=$((healthy_pods + 1))
                            fi
                        fi
                    done <<< "$pod_data"
                    
                    if [ $healthy_pods -eq $total_pods ]; then
                        pod_status_summary="✓ ${healthy_pods}/${total_pods} healthy"
                    else
                        pod_status_summary="✗ ${healthy_pods}/${total_pods} healthy"
                    fi
                fi
                
                printf "%-30s %-40s %-15s %s\n" "$deploy_name" "No ingress" "$deploy_status" "$pod_status_summary"
            fi
        fi
    done <<< "$deployment_data"
    
    echo
    print_status $BLUE "=== Detailed Pod Status ==="
    
    # 详细的Pod状态信息
    while IFS= read -r deploy_line; do
        if [ -n "$deploy_line" ]; then
            local deploy_name=$(echo "$deploy_line" | awk '{print $1}')
            
            print_status $YELLOW "Deployment: $deploy_name"
            local pod_data=$(get_pods_by_deployment "$namespace" "$deploy_name")
            
            if [ -n "$pod_data" ]; then
                local healthy_pods=()
                local unhealthy_pods=()
                
                while IFS= read -r pod_line; do
                    if [ -n "$pod_line" ]; then
                        local pod_analysis=$(analyze_pod_status "$pod_line")
                        if analyze_pod_status "$pod_line" >/dev/null; then
                            healthy_pods+=("  $pod_analysis")
                        else
                            unhealthy_pods+=("  $pod_analysis")
                        fi
                    fi
                done <<< "$pod_data"
                
                if [ ${#healthy_pods[@]} -gt 0 ]; then
                    print_status $GREEN "  Healthy Pods:"
                    printf '%s\n' "${healthy_pods[@]}"
                fi
                
                if [ ${#unhealthy_pods[@]} -gt 0 ]; then
                    print_status $RED "  Unhealthy Pods:"
                    printf '%s\n' "${unhealthy_pods[@]}"
                fi
            else
                print_status $YELLOW "  No pods found"
            fi
            echo
        fi
    done <<< "$deployment_data"
}

# 主函数
main() {
    local namespace=""
    
    # 解析命令行参数
    while getopts "n:h" opt; do
        case $opt in
            n)
                namespace="$OPTARG"
                ;;
            h)
                show_usage
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                show_usage
                ;;
        esac
    done
    
    # 检查必需参数
    if [ -z "$namespace" ]; then
        print_status $RED "Error: Namespace is required"
        show_usage
    fi
    
    # 检查依赖
    check_kubectl
    check_namespace "$namespace"
    
    # 执行主要逻辑
    process_namespace_status "$namespace"
}

# 运行脚本
main "$@"