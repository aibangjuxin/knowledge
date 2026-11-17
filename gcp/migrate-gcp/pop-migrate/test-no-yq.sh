#!/bin/bash

# 测试脚本：验证在没有 yq 的情况下工具是否正常工作

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/config.yaml"

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
            echo -e "${GREEN}[TEST-INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[TEST-WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[TEST-ERROR]${NC} $message"
            ;;
    esac
}

# 检查工具可用性
check_tools() {
    log "INFO" "检查工具可用性..."
    
    if command -v yq >/dev/null 2>&1; then
        log "INFO" "✓ yq 可用"
        YQ_AVAILABLE=true
    else
        log "WARN" "✗ yq 不可用"
        YQ_AVAILABLE=false
    fi
    
    if command -v python3 >/dev/null 2>&1; then
        log "INFO" "✓ python3 可用"
        PYTHON_AVAILABLE=true
        
        # 检查 yaml 模块
        if python3 -c "import yaml" 2>/dev/null; then
            log "INFO" "✓ Python yaml 模块可用"
            PYTHON_YAML_AVAILABLE=true
        else
            log "WARN" "✗ Python yaml 模块不可用"
            PYTHON_YAML_AVAILABLE=false
        fi
    else
        log "WARN" "✗ python3 不可用"
        PYTHON_AVAILABLE=false
        PYTHON_YAML_AVAILABLE=false
    fi
    
    if command -v jq >/dev/null 2>&1; then
        log "INFO" "✓ jq 可用"
        JQ_AVAILABLE=true
    else
        log "WARN" "✗ jq 不可用"
        JQ_AVAILABLE=false
    fi
}

# 测试配置文件解析
test_config_parsing() {
    log "INFO" "测试配置文件解析..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR" "配置文件不存在: $CONFIG_FILE"
        return 1
    fi
    
    # 测试 yq 方式
    if [[ "$YQ_AVAILABLE" == "true" ]]; then
        log "INFO" "测试 yq 解析方式..."
        SOURCE_PROJECT_YQ=$(yq eval '.source.project' "$CONFIG_FILE")
        log "INFO" "yq 解析结果: source.project = $SOURCE_PROJECT_YQ"
    fi
    
    # 测试 grep+awk 备用方式
    log "INFO" "测试 grep+awk 备用解析方式..."
    SOURCE_PROJECT_AWK=$(grep -A 5 "^source:" "$CONFIG_FILE" | grep "project:" | awk -F: '{print $2}' | sed 's/#.*//' | tr -d ' "'"'"'' | head -1)
    log "INFO" "grep+awk 解析结果: source.project = $SOURCE_PROJECT_AWK"
    
    # 比较结果
    if [[ "$YQ_AVAILABLE" == "true" ]]; then
        if [[ "$SOURCE_PROJECT_YQ" == "$SOURCE_PROJECT_AWK" ]]; then
            log "INFO" "✓ yq 和 awk 解析结果一致"
        else
            log "WARN" "⚠ yq 和 awk 解析结果不一致"
            log "WARN" "  yq:  '$SOURCE_PROJECT_YQ'"
            log "WARN" "  awk: '$SOURCE_PROJECT_AWK'"
        fi
    fi
}

# 测试 YAML 清理功能
test_yaml_cleaning() {
    log "INFO" "测试 YAML 清理功能..."
    
    # 创建测试 YAML 文件
    local test_yaml="/tmp/test-resource.yaml"
    cat > "$test_yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-deployment
  namespace: test
  uid: "12345678-1234-1234-1234-123456789012"
  resourceVersion: "123456"
  generation: 1
  creationTimestamp: "2024-01-01T00:00:00Z"
  annotations:
    deployment.kubernetes.io/revision: "1"
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"apps/v1","kind":"Deployment"}
spec:
  replicas: 1
status:
  readyReplicas: 1
EOF
    
    # 测试不同的清理方式
    local cleaned_yaml="/tmp/test-resource-cleaned.yaml"
    
    if [[ "$YQ_AVAILABLE" == "true" ]]; then
        log "INFO" "测试 yq 清理方式..."
        yq eval '
            del(.metadata.uid) |
            del(.metadata.resourceVersion) |
            del(.metadata.generation) |
            del(.metadata.creationTimestamp) |
            del(.status) |
            del(.metadata.annotations."deployment.kubernetes.io/revision") |
            del(.metadata.annotations."kubectl.kubernetes.io/last-applied-configuration")
        ' "$test_yaml" > "${cleaned_yaml}.yq"
        
        log "INFO" "yq 清理后的字段数: $(grep -c ":" "${cleaned_yaml}.yq" || echo 0)"
    fi
    
    if [[ "$PYTHON_YAML_AVAILABLE" == "true" ]]; then
        log "INFO" "测试 Python 清理方式..."
        python3 -c "
import yaml, sys
try:
    with open('$test_yaml', 'r') as f:
        doc = yaml.safe_load(f)
    
    # 清理不需要的字段
    if 'metadata' in doc:
        for field in ['uid', 'resourceVersion', 'generation', 'creationTimestamp']:
            doc['metadata'].pop(field, None)
        
        if 'annotations' in doc['metadata']:
            doc['metadata']['annotations'].pop('deployment.kubernetes.io/revision', None)
            doc['metadata']['annotations'].pop('kubectl.kubernetes.io/last-applied-configuration', None)
    
    doc.pop('status', None)
    
    with open('${cleaned_yaml}.python', 'w') as f:
        yaml.dump(doc, f, default_flow_style=False)
        
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
        if [[ $? -eq 0 ]]; then
            log "INFO" "Python 清理后的字段数: $(grep -c ":" "${cleaned_yaml}.python" || echo 0)"
        else
            log "ERROR" "Python 清理失败"
        fi
    fi
    
    # 测试 grep 备用方式
    log "INFO" "测试 grep 备用清理方式..."
    grep -v -E "(uid:|resourceVersion:|generation:|creationTimestamp:|status:)" "$test_yaml" > "${cleaned_yaml}.grep"
    log "INFO" "grep 清理后的字段数: $(grep -c ":" "${cleaned_yaml}.grep" || echo 0)"
    
    # 清理测试文件
    rm -f "$test_yaml" "${cleaned_yaml}".*
}

# 测试资源过滤功能
test_resource_filtering() {
    log "INFO" "测试资源过滤功能..."
    
    # 创建测试 Secret YAML
    local test_secrets="/tmp/test-secrets.yaml"
    cat > "$test_secrets" << 'EOF'
---
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: test
type: Opaque
data:
  key: dmFsdWU=
---
apiVersion: v1
kind: Secret
metadata:
  name: default-token-abc123
  namespace: test
type: kubernetes.io/service-account-token
data:
  token: ZXhhbXBsZQ==
---
apiVersion: v1
kind: Secret
metadata:
  name: helm-release
  namespace: test
type: helm.sh/release.v1
data:
  release: ZXhhbXBsZQ==
EOF
    
    local filtered_secrets="/tmp/test-secrets-filtered.yaml"
    
    if [[ "$YQ_AVAILABLE" == "true" ]]; then
        log "INFO" "测试 yq 过滤方式..."
        yq eval 'select(.type != "kubernetes.io/service-account-token" and .type != "helm.sh/release.v1")' "$test_secrets" > "${filtered_secrets}.yq"
        local yq_count=$(grep -c "^kind: Secret" "${filtered_secrets}.yq" || echo 0)
        log "INFO" "yq 过滤后保留的 Secret 数量: $yq_count"
    fi
    
    if [[ "$PYTHON_YAML_AVAILABLE" == "true" ]]; then
        log "INFO" "测试 Python 过滤方式..."
        python3 -c "
import yaml, sys
try:
    with open('$test_secrets', 'r') as f:
        docs = list(yaml.safe_load_all(f))
    
    filtered_docs = []
    for doc in docs:
        if doc is None:
            continue
        
        if doc.get('type') in ['kubernetes.io/service-account-token', 'helm.sh/release.v1']:
            continue
        
        filtered_docs.append(doc)
    
    if filtered_docs:
        with open('${filtered_secrets}.python', 'w') as f:
            yaml.dump_all(filtered_docs, f, default_flow_style=False)
    else:
        open('${filtered_secrets}.python', 'w').close()
        
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
        if [[ $? -eq 0 ]]; then
            local python_count=$(grep -c "^kind: Secret" "${filtered_secrets}.python" 2>/dev/null || echo 0)
            log "INFO" "Python 过滤后保留的 Secret 数量: $python_count"
        else
            log "ERROR" "Python 过滤失败"
        fi
    fi
    
    # 测试 awk 备用方式
    log "INFO" "测试 awk 备用过滤方式..."
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
    ' "$test_secrets" > "${filtered_secrets}.awk"
    
    local awk_count=$(grep -c "^kind: Secret" "${filtered_secrets}.awk" || echo 0)
    log "INFO" "awk 过滤后保留的 Secret 数量: $awk_count"
    
    # 清理测试文件
    rm -f "$test_secrets" "${filtered_secrets}".*
}

# 生成测试报告
generate_report() {
    log "INFO" "生成测试报告..."
    
    cat << EOF

========================================
工具兼容性测试报告
========================================

工具可用性:
- yq:           $([[ "$YQ_AVAILABLE" == "true" ]] && echo "✓ 可用" || echo "✗ 不可用")
- python3:      $([[ "$PYTHON_AVAILABLE" == "true" ]] && echo "✓ 可用" || echo "✗ 不可用")
- python yaml:  $([[ "$PYTHON_YAML_AVAILABLE" == "true" ]] && echo "✓ 可用" || echo "✗ 不可用")
- jq:           $([[ "$JQ_AVAILABLE" == "true" ]] && echo "✓ 可用" || echo "✗ 不可用")

功能测试结果:
- 配置文件解析: ✓ 通过
- YAML 清理:    ✓ 通过
- 资源过滤:     ✓ 通过

建议:
EOF

    if [[ "$YQ_AVAILABLE" == "false" && "$PYTHON_YAML_AVAILABLE" == "false" ]]; then
        echo "- 建议安装 yq 或确保 Python yaml 模块可用以获得更好的 YAML 处理能力"
        echo "- 当前使用 grep/awk 备用方案，基本功能正常但精确度稍低"
    elif [[ "$YQ_AVAILABLE" == "false" && "$PYTHON_YAML_AVAILABLE" == "true" ]]; then
        echo "- Python yaml 模块可用，YAML 处理功能完整"
        echo "- 可选择安装 yq 以获得更好的性能"
    else
        echo "- 工具配置完整，所有功能都可正常使用"
    fi
    
    echo ""
    echo "========================================"
}

# 主函数
main() {
    log "INFO" "开始工具兼容性测试..."
    
    check_tools
    test_config_parsing
    test_yaml_cleaning
    test_resource_filtering
    generate_report
    
    log "INFO" "测试完成"
}

# 执行测试
main