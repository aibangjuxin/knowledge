#!/bin/bash

# 导出脚本 - 从源集群导出指定 namespace 的资源

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
EXPORTS_DIR="${PROJECT_DIR}/exports"
CONFIG_DIR="${PROJECT_DIR}/config"

# 参数
NAMESPACE="$1"
RESOURCES="${2:-}"
EXCLUDE="${3:-}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$*"
    
    case $level in
        "INFO")
            echo -e "${GREEN}[EXPORT-INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[EXPORT-WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[EXPORT-ERROR]${NC} $message"
            ;;
    esac
}

# 检查 namespace 是否存在
check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log "ERROR" "Namespace '$NAMESPACE' 不存在于源集群"
        return 1
    fi
    
    # 检查是否为系统 namespace
    local system_namespaces=("kube-system" "kube-public" "kube-node-lease" "default" "gke-system")
    for sys_ns in "${system_namespaces[@]}"; do
        if [[ "$NAMESPACE" == "$sys_ns" ]]; then
            log "ERROR" "不允许迁移系统 namespace: $NAMESPACE"
            return 1
        fi
    done
    
    log "INFO" "Namespace '$NAMESPACE' 验证通过"
    return 0
}

# 获取资源类型列表
get_resource_types() {
    local include_resources=()
    local exclude_resources=()
    
    # 解析包含的资源类型
    if [[ -n "$RESOURCES" ]]; then
        IFS=',' read -ra include_resources <<< "$RESOURCES"
    else
        # 默认资源类型
        include_resources=(
            "deployments" "services" "configmaps" "secrets" "ingresses"
            "persistentvolumeclaims" "serviceaccounts" "roles" "rolebindings"
            "networkpolicies" "horizontalpodautoscalers" "poddisruptionbudgets"
            "cronjobs" "jobs" "daemonsets" "statefulsets" "limitranges" "resourcequotas"
        )
    fi
    
    # 解析排除的资源类型
    if [[ -n "$EXCLUDE" ]]; then
        IFS=',' read -ra exclude_resources <<< "$EXCLUDE"
    fi
    
    # 过滤排除的资源
    local filtered_resources=()
    for resource in "${include_resources[@]}"; do
        local should_exclude=false
        for exclude in "${exclude_resources[@]}"; do
            if [[ "$resource" == "$exclude" ]]; then
                should_exclude=true
                break
            fi
        done
        
        if [[ "$should_exclude" == "false" ]]; then
            filtered_resources+=("$resource")
        fi
    done
    
    echo "${filtered_resources[@]}"
}

# 清理资源 YAML
clean_resource_yaml() {
    local input_file="$1"
    local output_file="$2"
    
    # 使用 yq 或 jq+yq 清理不需要的字段
    if command -v yq >/dev/null 2>&1; then
        log "DEBUG" "使用 yq 清理资源文件"
        yq eval '
            del(.metadata.uid) |
            del(.metadata.resourceVersion) |
            del(.metadata.generation) |
            del(.metadata.creationTimestamp) |
            del(.metadata.deletionTimestamp) |
            del(.metadata.deletionGracePeriodSeconds) |
            del(.metadata.selfLink) |
            del(.status) |
            del(.metadata.annotations."deployment.kubernetes.io/revision") |
            del(.metadata.annotations."kubectl.kubernetes.io/last-applied-configuration")
        ' "$input_file" > "$output_file"
    elif command -v jq >/dev/null 2>&1; then
        log "DEBUG" "使用 jq 清理资源文件 (先转换为 JSON)"
        # 将 YAML 转换为 JSON，清理后再转回 YAML
        if command -v python3 >/dev/null 2>&1; then
            python3 -c "
import yaml, json, sys
try:
    with open('$input_file', 'r') as f:
        docs = list(yaml.safe_load_all(f))
    
    cleaned_docs = []
    for doc in docs:
        if doc is None:
            continue
        # 清理不需要的字段
        if 'metadata' in doc:
            for field in ['uid', 'resourceVersion', 'generation', 'creationTimestamp', 
                         'deletionTimestamp', 'deletionGracePeriodSeconds', 'selfLink']:
                doc['metadata'].pop(field, None)
            
            # 清理注解
            if 'annotations' in doc['metadata']:
                doc['metadata']['annotations'].pop('deployment.kubernetes.io/revision', None)
                doc['metadata']['annotations'].pop('kubectl.kubernetes.io/last-applied-configuration', None)
        
        # 删除 status 字段
        doc.pop('status', None)
        cleaned_docs.append(doc)
    
    with open('$output_file', 'w') as f:
        yaml.dump_all(cleaned_docs, f, default_flow_style=False)
except Exception as e:
    print(f'Python YAML processing failed: {e}', file=sys.stderr)
    sys.exit(1)
"
        else
            log "WARN" "Python3 不可用，使用简化的 grep 清理方式"
            # 简化的清理方式
            grep -v -E "(uid:|resourceVersion:|generation:|creationTimestamp:|deletionTimestamp:|selfLink:|status:)" "$input_file" > "$output_file"
        fi
    else
        log "WARN" "yq 和 jq 都不可用，使用简化的 grep 清理方式"
        # 简化的清理方式
        grep -v -E "(uid:|resourceVersion:|generation:|creationTimestamp:|deletionTimestamp:|selfLink:|status:)" "$input_file" > "$output_file"
    fi
}

# 导出单个资源类型
export_resource_type() {
    local resource_type="$1"
    local export_dir="$2"
    
    log "INFO" "导出 $resource_type..."
    
    # 检查资源是否存在
    local resource_count
    resource_count=$(kubectl get "$resource_type" -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ "$resource_count" -eq 0 ]]; then
        log "WARN" "Namespace '$NAMESPACE' 中没有 $resource_type 资源"
        return 0
    fi
    
    local raw_file="${export_dir}/${resource_type}-raw.yaml"
    local clean_file="${export_dir}/${resource_type}.yaml"
    
    # 导出资源
    if kubectl get "$resource_type" -n "$NAMESPACE" -o yaml > "$raw_file" 2>/dev/null; then
        # 清理资源文件
        clean_resource_yaml "$raw_file" "$clean_file"
        rm -f "$raw_file"
        
        log "INFO" "成功导出 $resource_count 个 $resource_type 资源"
        return 0
    else
        log "ERROR" "导出 $resource_type 失败"
        return 1
    fi
}

# 导出 namespace 定义
export_namespace_definition() {
    local export_dir="$1"
    local ns_file="${export_dir}/namespace.yaml"
    
    log "INFO" "导出 namespace 定义..."
    
    if kubectl get namespace "$NAMESPACE" -o yaml > "${ns_file}.tmp" 2>/dev/null; then
        clean_resource_yaml "${ns_file}.tmp" "$ns_file"
        rm -f "${ns_file}.tmp"
        log "INFO" "成功导出 namespace 定义"
    else
        log "ERROR" "导出 namespace 定义失败"
        return 1
    fi
}

# 生成资源清单
generate_manifest() {
    local export_dir="$1"
    local manifest_file="${export_dir}/manifest.yaml"
    
    log "INFO" "生成资源清单..."
    
    cat > "$manifest_file" << EOF
# 资源迁移清单
# 生成时间: $(date)
# 源 namespace: $NAMESPACE
# 导出目录: $export_dir

apiVersion: v1
kind: ConfigMap
metadata:
  name: migration-manifest
  namespace: $NAMESPACE
data:
  timestamp: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  source_namespace: "$NAMESPACE"
  export_directory: "$export_dir"
  resource_types: |
$(find "$export_dir" -name "*.yaml" -not -name "manifest.yaml" -not -name "namespace.yaml" | sed 's|.*/||' | sed 's|\.yaml$||' | sort | sed 's/^/    /')
EOF
}

# 生成统计报告
generate_stats() {
    local export_dir="$1"
    local stats_file="${export_dir}/export-stats.md"
    
    log "INFO" "生成导出统计报告..."
    
    cat > "$stats_file" << EOF
# Namespace 导出统计报告

**Namespace:** $NAMESPACE  
**导出时间:** $(date)  
**导出目录:** $export_dir

## 资源统计

| 资源类型 | 数量 | 文件 |
|----------|------|------|
EOF
    
    for yaml_file in "$export_dir"/*.yaml; do
        if [[ -f "$yaml_file" && "$(basename "$yaml_file")" != "manifest.yaml" && "$(basename "$yaml_file")" != "namespace.yaml" ]]; then
            local resource_type=$(basename "$yaml_file" .yaml)
            local count=0
            
            if [[ -f "$yaml_file" ]]; then
                count=$(grep -c "^kind:" "$yaml_file" 2>/dev/null || echo "0")
            fi
            
            echo "| $resource_type | $count | $(basename "$yaml_file") |" >> "$stats_file"
        fi
    done
    
    cat >> "$stats_file" << EOF

## 导出的文件

EOF
    
    find "$export_dir" -name "*.yaml" | sort | while read -r file; do
        echo "- $(basename "$file")" >> "$stats_file"
    done
    
    cat >> "$stats_file" << EOF

## 注意事项

- 所有敏感信息（如 secrets）已导出，请妥善保管
- PVC 数据需要单独迁移
- 某些资源可能需要在目标集群中调整配置
- 建议在导入前检查目标集群的资源配额和限制

EOF
}

# 主函数
main() {
    log "INFO" "开始导出 namespace: $NAMESPACE"
    
    # 检查 namespace
    if ! check_namespace; then
        exit 1
    fi
    
    # 创建导出目录
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local export_dir="${EXPORTS_DIR}/${NAMESPACE}_${timestamp}"
    mkdir -p "$export_dir"
    
    log "INFO" "导出目录: $export_dir"
    
    # 导出 namespace 定义
    export_namespace_definition "$export_dir"
    
    # 获取要导出的资源类型
    local resource_types
    read -ra resource_types <<< "$(get_resource_types)"
    
    log "INFO" "将导出以下资源类型: ${resource_types[*]}"
    
    # 导出各种资源
    local success_count=0
    local total_count=${#resource_types[@]}
    
    for resource_type in "${resource_types[@]}"; do
        if export_resource_type "$resource_type" "$export_dir"; then
            ((success_count++))
        fi
    done
    
    # 生成清单和统计
    generate_manifest "$export_dir"
    generate_stats "$export_dir"
    
    log "INFO" "导出完成: $success_count/$total_count 个资源类型成功"
    log "INFO" "导出文件位于: $export_dir"
    
    # 创建最新导出的符号链接
    local latest_link="${EXPORTS_DIR}/${NAMESPACE}_latest"
    rm -f "$latest_link"
    ln -s "$(basename "$export_dir")" "$latest_link"
    
    if [[ $success_count -eq $total_count ]]; then
        log "INFO" "所有资源导出成功"
        exit 0
    else
        log "WARN" "部分资源导出失败"
        exit 1
    fi
}

# 执行主函数
main