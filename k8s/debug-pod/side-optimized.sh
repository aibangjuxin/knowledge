#!/bin/bash

# 优化版本的 GKE Ephemeral Container Debug 脚本
# 保持原有功能的同时增加了更多优化和错误处理

set -euo pipefail  # 严格模式

# 颜色定义
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# 全局变量
DEPLOYMENT_NAME=""
GAR_IMAGE_PATH=""
NAMESPACE=""
SELECTED_POD=""
TARGET_CONTAINER=""
VERBOSE=false
AUTO_CONFIRM=false

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { [[ "$VERBOSE" == true ]] && echo -e "${CYAN}[DEBUG]${NC} $1"; }

# 显示使用方法
show_usage() {
    cat << EOF
Usage: $0 <deployment-name> <gar-image-path> -n <namespace> [OPTIONS]

Parameters:
  deployment-name    Name of the deployment to debug
  gar-image-path     Full GAR image path (e.g., region-docker.pkg.dev/project/repo/image:tag)
  -n namespace       Kubernetes namespace

Options:
  -v, --verbose      Enable verbose output
  -y, --yes          Auto-confirm without prompting
  -h, --help         Show this help message

Examples:
  $0 my-app europe-west2-docker.pkg.dev/project/repo/debug:latest -n default
  $0 user-service asia.gcr.io/project/curlimages/curl:latest -n production -v
  $0 api-service gcr.io/project/debug:latest -n staging --yes

Supported debug images:
  - curlimages/curl:latest
  - nicolaka/netshoot:latest
  - busybox:latest
  - alpine:latest
EOF
    exit 1
}

# 检查依赖
check_dependencies() {
    local deps=("kubectl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Required dependency '$dep' not found"
            exit 1
        fi
    done
    log_debug "All dependencies checked"
}

# 解析参数
parse_arguments() {
    # 首先检查是否是帮助请求
    for arg in "$@"; do
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            show_usage
        fi
    done
    
    if [[ $# -lt 4 ]]; then
        log_error "Invalid number of arguments"
        show_usage
    fi

    # 解析位置参数
    DEPLOYMENT_NAME="$1"
    GAR_IMAGE_PATH="$2"
    
    # 解析选项
    shift 2
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -y|--yes)
                AUTO_CONFIRM=true
                shift
                ;;
            -h|--help)
                show_usage
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                ;;
        esac
    done

    # 验证必需参数
    if [[ -z "$NAMESPACE" ]]; then
        log_error "Namespace is required"
        show_usage
    fi

    log_debug "Parsed arguments: deployment=$DEPLOYMENT_NAME, image=$GAR_IMAGE_PATH, namespace=$NAMESPACE"
}

# 验证 Kubernetes 连接
validate_k8s_connection() {
    log_debug "Validating Kubernetes connection..."
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    log_debug "Kubernetes connection validated"
}

# 检查 deployment 是否存在
check_deployment_exists() {
    log_info "Checking if deployment '$DEPLOYMENT_NAME' exists in namespace '$NAMESPACE'..."
    
    if ! kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" &> /dev/null; then
        log_error "Deployment '$DEPLOYMENT_NAME' not found in namespace '$NAMESPACE'"
        log_info "Available deployments in namespace '$NAMESPACE':"
        kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print "  - " $1}' || echo "  No deployments found"
        exit 1
    fi
    log_debug "Deployment exists"
}

# 获取 deployment 对应的 pods (优化版本)
get_deployment_pods() {
    log_info "Getting pods for deployment '$DEPLOYMENT_NAME'..."
    
    # 方法1: 直接通过 deployment 的 selector 获取 pods
    local selector
    selector=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null)
    
    if [[ -n "$selector" ]]; then
        # 解析 selector 并构建标签查询
        local label_selector=""
        while IFS= read -r line; do
            if [[ "$line" =~ \"([^\"]+)\":\"([^\"]+)\" ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                if [[ -n "$label_selector" ]]; then
                    label_selector="$label_selector,$key=$value"
                else
                    label_selector="$key=$value"
                fi
            fi
        done <<< "$selector"
        
        if [[ -n "$label_selector" ]]; then
            PODS=$(kubectl get pods -n "$NAMESPACE" -l "$label_selector" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
            log_debug "Found pods using deployment selector: $label_selector"
        fi
    fi
    
    # 方法2: 回退到原有的标签查找逻辑
    if [[ -z "$PODS" ]]; then
        log_debug "Falling back to legacy label matching..."
        local app_label="$DEPLOYMENT_NAME"
        
        # 处理 -deployment 后缀
        if [[ "$DEPLOYMENT_NAME" == *-deployment ]]; then
            app_label="${DEPLOYMENT_NAME%-deployment}"
        fi
        
        # 尝试多种标签选择器
        local selectors=("app=$app_label" "app.kubernetes.io/name=$app_label" "app=$DEPLOYMENT_NAME")
        
        for selector in "${selectors[@]}"; do
            PODS=$(kubectl get pods -n "$NAMESPACE" -l "$selector" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
            if [[ -n "$PODS" ]]; then
                log_debug "Found pods using selector: $selector"
                break
            fi
        done
    fi
    
    if [[ -z "$PODS" ]]; then
        log_error "No pods found for deployment '$DEPLOYMENT_NAME'"
        log_info "Available pods in namespace '$NAMESPACE':"
        kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print "  - " $1}' || echo "  No pods found"
        exit 1
    fi
    
    log_debug "Found pods: $PODS"
}

# 选择 pod
select_pod() {
    local pod_array=($PODS)
    
    log_info "Available pods:"
    for i in "${!pod_array[@]}"; do
        local pod_status
        pod_status=$(kubectl get pod "${pod_array[i]}" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "  $((i+1)). ${pod_array[i]} (status: $pod_status)"
    done
    
    if [[ ${#pod_array[@]} -eq 1 ]]; then
        SELECTED_POD="${pod_array[0]}"
        log_info "Auto-selected pod: $SELECTED_POD"
    else
        echo ""
        read -p "Select pod number (1-${#pod_array[@]}): " pod_choice
        
        if ! [[ "$pod_choice" =~ ^[0-9]+$ ]] || [[ "$pod_choice" -lt 1 ]] || [[ "$pod_choice" -gt ${#pod_array[@]} ]]; then
            log_error "Invalid pod selection"
            exit 1
        fi
        
        SELECTED_POD="${pod_array[$((pod_choice-1))]}"
        log_info "Selected pod: $SELECTED_POD"
    fi
    
    # 检查 pod 状态
    local pod_status
    pod_status=$(kubectl get pod "$SELECTED_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$pod_status" != "Running" ]]; then
        log_warn "Pod '$SELECTED_POD' is not in Running state (current: $pod_status)"
        if [[ "$AUTO_CONFIRM" != true ]]; then
            read -p "Continue anyway? (y/N): " continue_choice
            if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
                log_info "Operation cancelled"
                exit 0
            fi
        fi
    fi
}

# 选择容器
select_container() {
    log_info "Getting containers in pod '$SELECTED_POD'..."
    
    local containers
    containers=$(kubectl get pod "$SELECTED_POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
    
    if [[ -z "$containers" ]]; then
        log_error "No containers found in pod '$SELECTED_POD'"
        exit 1
    fi
    
    local container_array=($containers)
    
    log_info "Available containers:"
    for i in "${!container_array[@]}"; do
        local container_image
        container_image=$(kubectl get pod "$SELECTED_POD" -n "$NAMESPACE" -o jsonpath="{.spec.containers[$i].image}" 2>/dev/null)
        echo "  $((i+1)). ${container_array[i]} (image: $container_image)"
    done
    
    if [[ ${#container_array[@]} -eq 1 ]]; then
        TARGET_CONTAINER="${container_array[0]}"
        log_info "Auto-selected container: $TARGET_CONTAINER"
    else
        echo ""
        read -p "Select target container number (1-${#container_array[@]}): " container_choice
        
        if ! [[ "$container_choice" =~ ^[0-9]+$ ]] || [[ "$container_choice" -lt 1 ]] || [[ "$container_choice" -gt ${#container_array[@]} ]]; then
            log_error "Invalid container selection"
            exit 1
        fi
        
        TARGET_CONTAINER="${container_array[$((container_choice-1))]}"
        log_info "Selected target container: $TARGET_CONTAINER"
    fi
}

# 验证镜像
validate_image() {
    log_info "Validating debug image..."
    
    if kubectl run temp-image-check --image="$GAR_IMAGE_PATH" --dry-run=client -o yaml &> /dev/null; then
        log_debug "Image format validation passed"
    else
        log_warn "Image format validation failed, but continuing..."
    fi
}

# 确认执行
confirm_execution() {
    if [[ "$AUTO_CONFIRM" == true ]]; then
        log_info "Auto-confirming execution..."
        return 0
    fi
    
    echo ""
    log_info "Ready to inject ephemeral container:"
    echo -e "  Pod: ${GREEN}$SELECTED_POD${NC}"
    echo -e "  Target Container: ${GREEN}$TARGET_CONTAINER${NC}"
    echo -e "  Debug Image: ${GREEN}$GAR_IMAGE_PATH${NC}"
    echo -e "  Namespace: ${GREEN}$NAMESPACE${NC}"
    echo ""
    
    read -p "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        exit 0
    fi
}

# 执行 debug 命令 (修复版本)
execute_debug() {
    local debug_cmd="kubectl debug $SELECTED_POD -n $NAMESPACE -it --image=$GAR_IMAGE_PATH --target=$TARGET_CONTAINER"
    
    echo ""
    log_info "Injecting ephemeral container..."
    log_debug "Command: $debug_cmd"
    echo ""
    
    log_info "Starting ephemeral container session..."
    echo -e "${YELLOW}Tip: You can now run commands like:${NC}"
    echo -e "  ${CYAN}curl -H \"Metadata-Flavor: Google\" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token${NC}"
    echo -e "  ${CYAN}curl http://localhost:8080/health${NC}"
    echo -e "  ${CYAN}wget http://localhost:3000${NC}"
    echo -e "  ${CYAN}ps aux${NC}"
    echo -e "  ${CYAN}netstat -tulpn${NC}"
    echo ""
    
    # 实际执行命令 (修复了原脚本的问题)
    if ! $debug_cmd -- bash; then
        log_warn "Debug session ended with non-zero exit code"
    fi
    
    echo ""
    log_info "Ephemeral container session ended"
}

# 主函数
main() {
    echo -e "${BLUE}=== GKE Ephemeral Container Debug Script (Optimized) ===${NC}"
    echo -e "${GREEN}Deployment:${NC} $DEPLOYMENT_NAME"
    echo -e "${GREEN}Image:${NC} $GAR_IMAGE_PATH"
    echo -e "${GREEN}Namespace:${NC} $NAMESPACE"
    echo ""
    
    check_dependencies
    validate_k8s_connection
    check_deployment_exists
    get_deployment_pods
    select_pod
    select_container
    validate_image
    confirm_execution
    execute_debug
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    main
fi