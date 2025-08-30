#!/bin/bash

# 导入脚本 - 将导出的资源导入到目标集群

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
EXPORTS_DIR="${PROJECT_DIR}/exports"
CONFIG_DIR="${PROJECT_DIR}/config"

# 参数
NAMESPACE="$1"
FORCE="${2:-false}"
TIMEOUT="${3:-300}"

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
            echo -e "${GREEN}[IMPORT-INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[IMPORT-WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[IMPORT-ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[IMPORT-DEBUG]${NC} $message"
            ;;
    esac
}

# 查找最新的导出目录
find_export_dir() {
    local latest_link="${EXPORTS_DIR}/${NAMESPACE}_latest"
    
    if [[ -L "$latest_link" ]]; then
        local export_dir="${EXPORTS_DIR}/$(readlink "$latest_link")"
        if [[ -d "$export_dir" ]]; then
            echo "$export_dir"
            return 0
        fi
    fi
    
    # 查找最新的导出目录
    local latest_dir
    latest_dir=$(find "$EXPORTS_DIR" -maxdepth 1 -type d -name "${NAMESPACE}_*" | sort -r | head -n1)
    
    if [[ -n "$latest_dir" && -d "$latest_dir" ]]; then
        echo "$latest_dir"
        return 0
    fi
    
    log "ERROR" "找不到 namespace '$NAMESPACE' 的导出目录"
    return 1
}

# 检查目标集群连接
check_target_cluster() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log "ERROR" "无法连接到目标集群"
        return 1
    fi
    
    log "INFO" "目标集群连接正常"
    return 0
}

# 创建 namespace
create_namespace() {
    local export_dir="$1"
    local ns_file="${export_dir}/namespace.yaml"
    
    if [[ ! -f "$ns_file" ]]; then
        log "WARN" "未找到 namespace 定义文件，使用默认配置创建"
        kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
        return 0
    fi
    
    log "INFO" "创建 namespace: $NAMESPACE"
    
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        if [[ "$FORCE" == "true" ]]; then
            log "WARN" "Namespace 已存在，强制更新"
            kubectl apply -f "$ns_file"
        else
            log "INFO" "Namespace 已存在，跳过创建"
        fi
    else
        kubectl apply -f "$ns_file"
    fi
    
    log "INFO" "Namespace 创建完成"
}

# 获取资源导入顺序
get_import_order() {
    # 定义导入优先级
    local priority_order=(
        "namespace"
        "serviceaccounts"
        "secrets"
        "configmaps"
        "persistentvolumeclaims"
        "roles"
        "rolebindings"
        "services"
        "networkpolicies"
        "deployments"
        "statefulsets"
        "daemonsets"
        "jobs"
        "cronjobs"
        "horizontalpodautoscalers"
        "poddisruptionbudgets"
        "limitranges"
        "resourcequotas"
        "ingresses"
    )
    
    echo "${priority_order[@]}"
}

# 预处理资源文件
preprocess_resource() {
    local resource_file="$1"
    local temp_file="${resource_file}.tmp"
    
    # 添加迁移标签
    if command -v yq >/dev/null 2>&1; then
        log "DEBUG" "使用 yq 添加迁移标签"
        yq eval '
            .metadata.labels."migration.tool" = "pop-migrate" |
            .metadata.labels."migration.timestamp" = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'" |
            .metadata.labels."migration.target" = "'$(kubectl config current-context)'"
        ' "$resource_file" > "$temp_file"
        mv "$temp_file" "$resource_file"
    elif command -v python3 >/dev/null 2>&1; then
        log "DEBUG" "使用 Python 添加迁移标签"
        python3 -c "
import yaml, sys
try:
    with open('$resource_file', 'r') as f:
        docs = list(yaml.safe_load_all(f))
    
    for doc in docs:
        if doc is None or 'metadata' not in doc:
            continue
        
        if 'labels' not in doc['metadata']:
            doc['metadata']['labels'] = {}
        
        doc['metadata']['labels']['migration.tool'] = 'pop-migrate'
        doc['metadata']['labels']['migration.timestamp'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
        doc['metadata']['labels']['migration.target'] = '$(kubectl config current-context)'
    
    with open('$temp_file', 'w') as f:
        yaml.dump_all(docs, f, default_flow_style=False)
    
except Exception as e:
    print(f'Python YAML processing failed: {e}', file=sys.stderr)
    sys.exit(1)
"
        if [ $? -eq 0 ]; then
            mv "$temp_file" "$resource_file"
        else
            log "WARN" "Python 处理失败，跳过添加迁移标签"
        fi
    else
        log "DEBUG" "yq 和 Python 都不可用，跳过添加迁移标签"
    fi
}

# 导入单个资源文件
import_resource_file() {
    local resource_file="$1"
    local resource_type="$2"
    
    if [[ ! -f "$resource_file" ]]; then
        log "DEBUG" "资源文件不存在: $resource_file"
        return 0
    fi
    
    log "INFO" "导入 $resource_type 资源..."
    
    # 检查文件是否为空
    if [[ ! -s "$resource_file" ]]; then
        log "WARN" "$resource_type 资源文件为空，跳过"
        return 0
    fi
    
    # 预处理资源文件
    preprocess_resource "$resource_file"
    
    # 特殊处理某些资源类型
    case "$resource_type" in
        "secrets")
            import_secrets "$resource_file"
            ;;
        "persistentvolumeclaims")
            import_pvcs "$resource_file"
            ;;
        "serviceaccounts")
            import_serviceaccounts "$resource_file"
            ;;
        *)
            import_generic_resource "$resource_file" "$resource_type"
            ;;
    esac
}

# 导入 Secrets (特殊处理)
import_secrets() {
    local resource_file="$1"
    
    log "INFO" "导入 Secrets (跳过系统生成的 token)..."
    
    # 过滤掉系统生成的 secrets
    local temp_file="${resource_file}.filtered"
    
    if command -v yq >/dev/null 2>&1; then
        log "DEBUG" "使用 yq 过滤 Secrets"
        yq eval 'select(.type != "kubernetes.io/service-account-token" and .type != "helm.sh/release.v1")' "$resource_file" > "$temp_file"
    elif command -v python3 >/dev/null 2>&1; then
        log "DEBUG" "使用 Python 过滤 Secrets"
        python3 -c "
import yaml, sys
try:
    with open('$resource_file', 'r') as f:
        docs = list(yaml.safe_load_all(f))
    
    filtered_docs = []
    for doc in docs:
        if doc is None:
            continue
        
        # 跳过系统生成的 secrets
        if doc.get('type') in ['kubernetes.io/service-account-token', 'helm.sh/release.v1']:
            continue
        
        filtered_docs.append(doc)
    
    if filtered_docs:
        with open('$temp_file', 'w') as f:
            yaml.dump_all(filtered_docs, f, default_flow_style=False)
    else:
        open('$temp_file', 'w').close()  # 创建空文件
        
except Exception as e:
    print(f'Python YAML processing failed: {e}', file=sys.stderr)
    sys.exit(1)
"
    else
        log "DEBUG" "使用 grep 过滤 Secrets"
        # 简化过滤 - 更精确的方式
        awk '
        BEGIN { skip = 0; doc = ""; }
        /^---/ { 
            if (doc != "" && skip == 0) print doc;
            doc = $0 "\n"; skip = 0; next;
        }
        /^apiVersion:/ { doc = doc $0 "\n"; next; }
        /^kind:/ { doc = doc $0 "\n"; next; }
        /^type: kubernetes\.io\/service-account-token/ { skip = 1; }
        /^type: helm\.sh\/release\.v1/ { skip = 1; }
        { doc = doc $0 "\n"; }
        END { if (doc != "" && skip == 0) print doc; }
        ' "$resource_file" > "$temp_file"
    fi
    
    if [[ -s "$temp_file" ]]; then
        kubectl apply -f "$temp_file" -n "$NAMESPACE"
        rm -f "$temp_file"
    else
        log "INFO" "没有需要导入的 Secrets"
    fi
}

# 导入 PVCs (特殊处理)
import_pvcs() {
    local resource_file="$1"
    
    log "INFO" "导入 PersistentVolumeClaims..."
    log "WARN" "注意: PVC 数据需要单独迁移"
    
    # 检查 StorageClass 是否存在
    if command -v yq >/dev/null 2>&1; then
        log "DEBUG" "使用 yq 检查 StorageClass"
        local storage_classes
        storage_classes=$(yq eval '.spec.storageClassName' "$resource_file" | sort -u | grep -v "null")
        
        for sc in $storage_classes; do
            if ! kubectl get storageclass "$sc" >/dev/null 2>&1; then
                log "WARN" "StorageClass '$sc' 在目标集群中不存在"
            fi
        done
    elif command -v python3 >/dev/null 2>&1; then
        log "DEBUG" "使用 Python 检查 StorageClass"
        python3 -c "
import yaml, sys
try:
    with open('$resource_file', 'r') as f:
        docs = list(yaml.safe_load_all(f))
    
    storage_classes = set()
    for doc in docs:
        if doc is None:
            continue
        
        sc = doc.get('spec', {}).get('storageClassName')
        if sc and sc != 'null':
            storage_classes.add(sc)
    
    for sc in storage_classes:
        print(sc)
        
except Exception as e:
    print(f'Python YAML processing failed: {e}', file=sys.stderr)
" | while read -r sc; do
            if [[ -n "$sc" ]] && ! kubectl get storageclass "$sc" >/dev/null 2>&1; then
                log "WARN" "StorageClass '$sc' 在目标集群中不存在"
            fi
        done
    else
        log "DEBUG" "yq 和 Python 都不可用，跳过 StorageClass 检查"
    fi
    
    kubectl apply -f "$resource_file" -n "$NAMESPACE"
}

# 导入 ServiceAccounts (特殊处理)
import_serviceaccounts() {
    local resource_file="$1"
    
    log "INFO" "导入 ServiceAccounts (跳过 default)..."
    
    # 过滤掉 default service account
    local temp_file="${resource_file}.filtered"
    
    if command -v yq >/dev/null 2>&1; then
        log "DEBUG" "使用 yq 过滤 ServiceAccounts"
        yq eval 'select(.metadata.name != "default")' "$resource_file" > "$temp_file"
    elif command -v python3 >/dev/null 2>&1; then
        log "DEBUG" "使用 Python 过滤 ServiceAccounts"
        python3 -c "
import yaml, sys
try:
    with open('$resource_file', 'r') as f:
        docs = list(yaml.safe_load_all(f))
    
    filtered_docs = []
    for doc in docs:
        if doc is None:
            continue
        
        # 跳过 default service account
        if doc.get('metadata', {}).get('name') == 'default':
            continue
        
        filtered_docs.append(doc)
    
    if filtered_docs:
        with open('$temp_file', 'w') as f:
            yaml.dump_all(filtered_docs, f, default_flow_style=False)
    else:
        open('$temp_file', 'w').close()  # 创建空文件
        
except Exception as e:
    print(f'Python YAML processing failed: {e}', file=sys.stderr)
    sys.exit(1)
"
    else
        log "DEBUG" "使用 grep 过滤 ServiceAccounts"
        # 使用 awk 更精确地过滤
        awk '
        BEGIN { skip = 0; doc = ""; }
        /^---/ { 
            if (doc != "" && skip == 0) print doc;
            doc = $0 "\n"; skip = 0; next;
        }
        /^apiVersion:/ { doc = doc $0 "\n"; next; }
        /^kind:/ { doc = doc $0 "\n"; next; }
        /^  name: default$/ { skip = 1; }
        { doc = doc $0 "\n"; }
        END { if (doc != "" && skip == 0) print doc; }
        ' "$resource_file" > "$temp_file"
    fi
    
    if [[ -s "$temp_file" ]]; then
        kubectl apply -f "$temp_file" -n "$NAMESPACE"
        rm -f "$temp_file"
    else
        log "INFO" "没有需要导入的 ServiceAccounts"
    fi
}

# 导入通用资源
import_generic_resource() {
    local resource_file="$1"
    local resource_type="$2"
    
    local apply_args="-f $resource_file -n $NAMESPACE"
    
    if [[ "$FORCE" == "true" ]]; then
        apply_args="$apply_args --force"
    fi
    
    # 执行导入
    if kubectl apply $apply_args; then
        log "INFO" "$resource_type 导入成功"
        
        # 等待资源就绪
        wait_for_resource_ready "$resource_type"
    else
        log "ERROR" "$resource_type 导入失败"
        return 1
    fi
}

# 等待资源就绪
wait_for_resource_ready() {
    local resource_type="$1"
    local wait_time=30
    
    case "$resource_type" in
        "deployments"|"statefulsets"|"daemonsets")
            log "INFO" "等待 $resource_type 就绪..."
            kubectl wait --for=condition=available "$resource_type" --all -n "$NAMESPACE" --timeout="${wait_time}s" || true
            ;;
        "jobs")
            log "INFO" "等待 Jobs 完成..."
            kubectl wait --for=condition=complete jobs --all -n "$NAMESPACE" --timeout="${wait_time}s" || true
            ;;
        "persistentvolumeclaims")
            log "INFO" "等待 PVCs 绑定..."
            sleep 10  # PVC 绑定需要时间
            ;;
        "ingresses")
            log "INFO" "等待 Ingresses 配置..."
            sleep 30  # Ingress 配置需要时间
            ;;
    esac
}

# 验证导入结果
validate_import() {
    local export_dir="$1"
    
    log "INFO" "验证导入结果..."
    
    # 检查 namespace 是否存在
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log "ERROR" "Namespace '$NAMESPACE' 不存在"
        return 1
    fi
    
    # 检查各种资源
    local validation_passed=true
    
    for yaml_file in "$export_dir"/*.yaml; do
        if [[ -f "$yaml_file" ]]; then
            local resource_type=$(basename "$yaml_file" .yaml)
            
            if [[ "$resource_type" == "namespace" || "$resource_type" == "manifest" || "$resource_type" == "export-stats" ]]; then
                continue
            fi
            
            local expected_count
            expected_count=$(grep -c "^kind:" "$yaml_file" 2>/dev/null || echo "0")
            
            if [[ "$expected_count" -gt 0 ]]; then
                local actual_count
                actual_count=$(kubectl get "$resource_type" -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
                
                if [[ "$actual_count" -eq "$expected_count" ]]; then
                    log "INFO" "$resource_type: $actual_count/$expected_count ✓"
                else
                    log "WARN" "$resource_type: $actual_count/$expected_count (数量不匹配)"
                    validation_passed=false
                fi
            fi
        fi
    done
    
    if [[ "$validation_passed" == "true" ]]; then
        log "INFO" "导入验证通过"
        return 0
    else
        log "WARN" "导入验证发现问题，请检查"
        return 1
    fi
}

# 生成导入报告
generate_import_report() {
    local export_dir="$1"
    local report_file="${export_dir}/import-report.md"
    
    log "INFO" "生成导入报告..."
    
    cat > "$report_file" << EOF
# Namespace 导入报告

**Namespace:** $NAMESPACE  
**导入时间:** $(date)  
**目标集群:** $(kubectl config current-context)

## 导入结果

| 资源类型 | 预期数量 | 实际数量 | 状态 |
|----------|----------|----------|------|
EOF
    
    for yaml_file in "$export_dir"/*.yaml; do
        if [[ -f "$yaml_file" ]]; then
            local resource_type=$(basename "$yaml_file" .yaml)
            
            if [[ "$resource_type" == "namespace" || "$resource_type" == "manifest" || "$resource_type" == "export-stats" ]]; then
                continue
            fi
            
            local expected_count
            expected_count=$(grep -c "^kind:" "$yaml_file" 2>/dev/null || echo "0")
            
            if [[ "$expected_count" -gt 0 ]]; then
                local actual_count
                actual_count=$(kubectl get "$resource_type" -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
                
                local status="✓"
                if [[ "$actual_count" -ne "$expected_count" ]]; then
                    status="⚠️"
                fi
                
                echo "| $resource_type | $expected_count | $actual_count | $status |" >> "$report_file"
            fi
        fi
    done
    
    cat >> "$report_file" << EOF

## 后续步骤

1. 检查所有 Pod 是否正常运行
2. 验证服务端点是否可访问
3. 检查 Ingress 配置是否正确
4. 验证 PVC 数据是否需要迁移
5. 更新监控和告警配置

## 注意事项

- 某些资源可能需要手动调整配置
- PVC 数据需要单独迁移
- 检查外部依赖是否正常工作

EOF
    
    log "INFO" "导入报告已生成: $report_file"
}

# 主函数
main() {
    log "INFO" "开始导入 namespace: $NAMESPACE"
    
    # 检查目标集群连接
    if ! check_target_cluster; then
        exit 1
    fi
    
    # 查找导出目录
    local export_dir
    if ! export_dir=$(find_export_dir); then
        exit 1
    fi
    
    log "INFO" "使用导出目录: $export_dir"
    
    # 创建 namespace
    create_namespace "$export_dir"
    
    # 获取导入顺序
    local import_order
    read -ra import_order <<< "$(get_import_order)"
    
    log "INFO" "按以下顺序导入资源: ${import_order[*]}"
    
    # 按顺序导入资源
    local success_count=0
    local total_count=0
    
    for resource_type in "${import_order[@]}"; do
        local resource_file="${export_dir}/${resource_type}.yaml"
        
        if [[ -f "$resource_file" && -s "$resource_file" ]]; then
            ((total_count++))
            if import_resource_file "$resource_file" "$resource_type"; then
                ((success_count++))
            fi
        fi
    done
    
    # 验证导入结果
    validate_import "$export_dir"
    
    # 生成导入报告
    generate_import_report "$export_dir"
    
    log "INFO" "导入完成: $success_count/$total_count 个资源类型成功"
    
    if [[ $success_count -eq $total_count ]]; then
        log "INFO" "所有资源导入成功"
        exit 0
    else
        log "WARN" "部分资源导入失败"
        exit 1
    fi
}

# 执行主函数
main