#!/usr/bin/env bash
# k8s-image-replace.sh
# 用于替换 Kubernetes deployment 中的镜像
# 使用方法: ./k8s-image-replace.sh -i <image-name:version> [-n namespace]

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# 显示帮助
show_help() {
    cat << EOF
用法: $0 -i <image> [-n namespace] [-h]

参数:
  -i, --image      目标镜像 (必需) 例如: myapp:v1.2.3
  -n, --namespace  指定命名空间 (可选，默认搜索所有命名空间)
  -h, --help       显示帮助信息

示例:
  $0 -i myapp:v1.2.3
  $0 -i registry.io/myorg/myapp:v2.0.0 -n production
EOF
}

# 解析参数
IMAGE=""
NAMESPACE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--image)
            IMAGE="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 检查必需参数
if [[ -z "$IMAGE" ]]; then
    error "镜像参数是必需的"
    show_help
    exit 1
fi

# 检查 kubectl 是否可用
if ! command -v kubectl &> /dev/null; then
    error "kubectl 未找到，请确保已安装并在 PATH 中"
    exit 1
fi

# 检查 kubectl 连接
if ! kubectl cluster-info &> /dev/null; then
    error "无法连接到 Kubernetes 集群"
    exit 1
fi

# 提取镜像名称（不包含标签）
IMAGE_NAME="${IMAGE%:*}"
IMAGE_TAG="${IMAGE##*:}"

log "目标镜像: $IMAGE"
log "镜像名称: $IMAGE_NAME"
log "镜像标签: $IMAGE_TAG"

# 构建 kubectl 命令参数
if [[ -n "$NAMESPACE" ]]; then
    NS_ARG="-n $NAMESPACE"
    log "搜索命名空间: $NAMESPACE"
else
    NS_ARG="-A"
    log "搜索所有命名空间"
fi

echo
log "正在搜索匹配的 deployments..."

# 获取所有 deployments 及其镜像信息
DEPLOYMENTS=$(kubectl get deployments $NS_ARG -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .spec.template.spec.containers[*]}{.name}{"="}{.image}{";"}{end}{"\n"}{end}' 2>/dev/null)

if [[ -z "$DEPLOYMENTS" ]]; then
    warn "未找到任何 deployments"
    exit 0
fi

# 查找匹配的 deployments
declare -a MATCHED_NS
declare -a MATCHED_DEPLOY
declare -a MATCHED_CONTAINER
declare -a MATCHED_IMAGE

while IFS= read -r line; do
    if [[ -z "$line" ]]; then continue; fi
    
    # 解析行: namespace|deployment|container1=image1;container2=image2;
    ns="${line%%|*}"
    rest="${line#*|}"
    deploy="${rest%%|*}"
    containers="${rest#*|}"
    
    # 解析容器和镜像
    IFS=';' read -ra container_pairs <<< "$containers"
    for pair in "${container_pairs[@]}"; do
        if [[ -z "$pair" ]]; then continue; fi
        
        container="${pair%%=*}"
        image="${pair#*=}"
        current_image_name="${image%:*}"
        
        # 检查镜像名称是否匹配（支持部分匹配）
        if [[ "$current_image_name" == *"$IMAGE_NAME"* ]] || [[ "$IMAGE_NAME" == *"$current_image_name"* ]]; then
            MATCHED_NS+=("$ns")
            MATCHED_DEPLOY+=("$deploy")
            MATCHED_CONTAINER+=("$container")
            MATCHED_IMAGE+=("$image")
        fi
    done
done <<< "$DEPLOYMENTS"

# 显示匹配结果
if [[ ${#MATCHED_NS[@]} -eq 0 ]]; then
    warn "未找到匹配的 deployments"
    exit 0
fi

echo
success "找到 ${#MATCHED_NS[@]} 个匹配的 deployment(s):"
echo
printf "%-4s %-20s %-30s %-20s %-40s\n" "序号" "命名空间" "Deployment" "容器" "当前镜像"
printf "%-4s %-20s %-30s %-20s %-40s\n" "----" "--------" "----------" "----" "--------"

for i in "${!MATCHED_NS[@]}"; do
    printf "%-4d %-20s %-30s %-20s %-40s\n" $((i+1)) "${MATCHED_NS[i]}" "${MATCHED_DEPLOY[i]}" "${MATCHED_CONTAINER[i]}" "${MATCHED_IMAGE[i]}"
done

echo
echo "请选择要更新的 deployment:"
echo "  输入序号 (例如: 1,3,5 或 1-3)"
echo "  输入 'all' 选择全部"
echo "  输入 'q' 退出"
echo

read -p "请选择: " selection

case "$selection" in
    q|Q)
        log "用户取消操作"
        exit 0
        ;;
    all|ALL)
        SELECTED_INDICES=($(seq 0 $((${#MATCHED_NS[@]} - 1))))
        ;;
    *)
        # 解析用户输入的序号
        SELECTED_INDICES=()
        IFS=',' read -ra selections <<< "$selection"
        for sel in "${selections[@]}"; do
            # 处理范围 (例如 1-3)
            if [[ "$sel" == *-* ]]; then
                start="${sel%-*}"
                end="${sel#*-}"
                for ((j=start; j<=end; j++)); do
                    if [[ $j -ge 1 && $j -le ${#MATCHED_NS[@]} ]]; then
                        SELECTED_INDICES+=($((j-1)))
                    fi
                done
            else
                # 单个数字
                if [[ "$sel" =~ ^[0-9]+$ ]] && [[ $sel -ge 1 && $sel -le ${#MATCHED_NS[@]} ]]; then
                    SELECTED_INDICES+=($((sel-1)))
                fi
            fi
        done
        ;;
esac

if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
    warn "未选择任何 deployment"
    exit 0
fi

# 显示将要执行的操作
echo
log "将要执行以下更新操作:"
for idx in "${SELECTED_INDICES[@]}"; do
    echo "  ${MATCHED_NS[idx]}/${MATCHED_DEPLOY[idx]} (${MATCHED_CONTAINER[idx]}): ${MATCHED_IMAGE[idx]} -> $IMAGE"
done

echo
read -p "确认执行? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "用户取消操作"
    exit 0
fi

# 执行更新
echo
log "开始执行镜像更新..."

for idx in "${SELECTED_INDICES[@]}"; do
    ns="${MATCHED_NS[idx]}"
    deploy="${MATCHED_DEPLOY[idx]}"
    container="${MATCHED_CONTAINER[idx]}"
    
    log "更新 $ns/$deploy 中的容器 $container..."
    
    if kubectl set image deployment/"$deploy" "$container"="$IMAGE" -n "$ns" --record; then
        success "✓ $ns/$deploy 更新成功"
        
        # 等待 rollout 完成
        log "等待 $ns/$deploy rollout 完成..."
        if kubectl rollout status deployment/"$deploy" -n "$ns" --timeout=300s; then
            success "✓ $ns/$deploy rollout 完成"
        else
            error "✗ $ns/$deploy rollout 超时或失败"
            warn "如需回滚，请执行: kubectl rollout undo deployment/$deploy -n $ns"
        fi
    else
        error "✗ $ns/$deploy 更新失败"
    fi
    echo
done

success "镜像更新操作完成!"