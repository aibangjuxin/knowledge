#!/opt/homebrew/bin/bash
# IP地址处理调试脚本
# 用于快速诊断问题

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# 检查文件和环境
debug_check() {
    local input_file="${1:-api_list.yaml}"
    
    log_info "=== 环境检查 ==="
    
    # 检查文件存在性
    if [[ -f "$input_file" ]]; then
        log_success "文件存在: $input_file"
    else
        log_error "文件不存在: $input_file"
        return 1
    fi
    
    # 检查文件权限
    if [[ -r "$input_file" ]]; then
        log_success "文件可读"
    else
        log_error "文件不可读"
        return 1
    fi
    
    # 检查文件大小
    local file_size=$(wc -c < "$input_file")
    local line_count=$(wc -l < "$input_file")
    log_info "文件大小: $file_size 字节"
    log_info "行数: $line_count"
    
    if [[ $file_size -eq 0 ]]; then
        log_error "文件为空"
        return 1
    fi
    
    # 检查依赖命令
    log_info "=== 依赖检查 ==="
    local deps=("ipcalc" "sort" "uniq" "grep" "awk" "sed")
    for dep in "${deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            log_success "$dep: $(which "$dep")"
        else
            log_error "$dep: 未找到"
        fi
    done
    
    # 显示文件内容
    log_info "=== 文件内容分析 ==="
    log_info "前10行内容:"
    head -10 "$input_file" | nl -ba
    
    log_info "=== 文件编码检查 ==="
    if command -v file &> /dev/null; then
        file "$input_file"
    fi
    
    # 检查特殊字符
    log_info "=== 特殊字符检查 ==="
    if grep -P '[^\x00-\x7F]' "$input_file" > /dev/null; then
        log_error "发现非ASCII字符"
        grep -P '[^\x00-\x7F]' "$input_file" | head -5
    else
        log_success "没有发现非ASCII字符"
    fi
    
    # 行尾字符检查
    log_info "=== 行尾格式检查 ==="
    if grep -c $'\r' "$input_file" > /dev/null 2>&1; then
        log_error "发现Windows行尾符(\\r\\n)"
        log_info "建议执行: dos2unix $input_file"
    else
        log_success "Unix行尾格式正常"
    fi
    
    return 0
}

# 简单的IP处理测试
simple_test() {
    local input_file="${1:-api_list.yaml}"
    
    log_info "=== 简单处理测试 ==="
    
    local line_num=0
    local processed=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        
        # 原始行
        log_info "第${line_num}行原始: '$line'"
        
        # 检查是否为空行
        if [[ -z "$line" ]]; then
            log_info "  -> 空行，跳过"
            continue
        fi
        
        # 检查是否为注释
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            log_info "  -> 注释行，跳过"
            continue
        fi
        
        # 清理空格
        local cleaned=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        log_info "  -> 清理后: '$cleaned'"
        
        if [[ -z "$cleaned" ]]; then
            log_info "  -> 清理后为空，跳过"
            continue
        fi
        
        # 验证IP格式
        if command -v ipcalc &> /dev/null; then
            if ipcalc "$cleaned" > /dev/null 2>&1; then
                log_success "  -> 有效CIDR: $cleaned"
                ((processed++))
            else
                log_error "  -> 无效CIDR: $cleaned"
                log_info "  -> ipcalc错误: $(ipcalc "$cleaned" 2>&1 || true)"
            fi
        else
            log_error "ipcalc命令不可用"
        fi
        
        # 限制显示行数
        if [[ $line_num -ge 20 ]]; then
            log_info "... (超过20行，截断显示)"
            break
        fi
        
    done < "$input_file"
    
    log_info "=== 处理结果 ==="
    log_info "总行数: $line_num"
    log_info "处理成功: $processed"
}

# 创建示例文件
create_sample() {
    local sample_file="sample_api_list.yaml"
    
    log_info "创建示例文件: $sample_file"
    
    cat > "$sample_file" << 'EOF'
# 示例IP列表
205.188.54.82/32
205.188.54.81/32
205.188.54.83/32
192.168.1.0/24
10.0.0.0/8
8.8.8.8/32
1.1.1.1/32
# 这是注释行
172.16.0.0/12

# 空行测试

203.0.113.0/24
EOF
    
    log_success "示例文件已创建: $sample_file"
    log_info "使用示例: $0 debug $sample_file"
}

# 主函数
main() {
    local command="${1:-debug}"
    local input_file="${2:-api_list.yaml}"
    
    case "$command" in
        "debug")
            log_info "开始调试检查..."
            if debug_check "$input_file"; then
                simple_test "$input_file"
            fi
            ;;
        "sample")
            create_sample
            ;;
        "test")
            if [[ -f "sample_api_list.yaml" ]]; then
                debug_check "sample_api_list.yaml"
                simple_test "sample_api_list.yaml"
            else
                log_error "示例文件不存在，请先运行: $0 sample"
            fi
            ;;
        *)
            echo "用法: $0 [debug|sample|test] [文件名]"
            echo "  debug  - 调试指定文件 (默认)"
            echo "  sample - 创建示例文件"
            echo "  test   - 测试示例文件"
            echo ""
            echo "示例:"
            echo "  $0 debug api_list.yaml"
            echo "  $0 sample"
            echo "  $0 test"
            ;;
    esac
}

main "$@"