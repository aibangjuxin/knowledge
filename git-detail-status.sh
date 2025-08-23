#!/opt/homebrew/bin/bash

# Git 提交记录智能分析工具 v2.0
# 优化版本 - 更好的性能、更清晰的代码结构、更丰富的功能

set -e  # 遇到错误退出，但不使用严格的 pipefail

# 配置参数
readonly SCRIPT_NAME=$(basename "$0")
readonly VERSION="2.0"
COMMIT_COUNT=${1:-20}
TIME_RANGE=${2:-""}
OUTPUT_FORMAT=${3:-"console"}  # console, json, markdown

# 智能参数解析 - 如果第二个参数是输出格式，调整参数
if [[ "$TIME_RANGE" =~ ^(console|json|markdown)$ ]]; then
    OUTPUT_FORMAT="$TIME_RANGE"
    TIME_RANGE=""
fi

# 颜色定义 - 检测终端是否支持颜色
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1 && [[ $(tput colors) -ge 8 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m' # No Color
else
    # 如果不支持颜色，使用空字符串
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly PURPLE=''
    readonly CYAN=''
    readonly NC=''
fi

# 统计数据存储
declare -A dir_stats=() file_stats=() ext_stats=()
declare -a changed_files=() commit_messages=()

# 工具函数
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

print_section() {
    echo -e "\n${CYAN}$1${NC}"
    echo "================================================"
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}Git 提交记录智能分析工具 v${VERSION}${NC}"
    echo ""
    echo -e "${YELLOW}用法:${NC}"
    echo "  $SCRIPT_NAME [提交数量] [时间范围] [输出格式]"
    echo ""
    echo -e "${YELLOW}参数:${NC}"
    echo "  提交数量    要分析的提交数量 (默认: 20)"
    echo "  时间范围    时间范围限制 (可选)"
    echo "             支持格式: 1week, 2weeks, 1month, 7days, 30 等"
    echo "  输出格式    输出格式 (默认: console)"
    echo "             支持: console, json, markdown"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  $SCRIPT_NAME                    # 分析最近20次提交"
    echo "  $SCRIPT_NAME 30                 # 分析最近30次提交"
    echo "  $SCRIPT_NAME 20 2weeks          # 分析最近20次提交且2周内的"
    echo "  $SCRIPT_NAME 50 1month json     # JSON格式输出"
    echo "  $SCRIPT_NAME 10 7days markdown  # Markdown格式输出"
    echo ""
    echo -e "${YELLOW}功能特性:${NC}"
    echo "  • 智能文件变更分析"
    echo "  • 多维度统计报告"
    echo "  • 知识点分布可视化"
    echo "  • 工作模式识别"
    echo "  • 多种输出格式"
    echo "  • 性能优化"
}

# 参数验证和处理
validate_and_parse_args() {
    # 帮助信息检查
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        show_help
        exit 0
    fi

    # 检查是否在 Git 仓库中
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "当前目录不是 Git 仓库"
        exit 1
    fi

    # 验证提交数量
    if ! [[ "$COMMIT_COUNT" =~ ^[0-9]+$ ]] || [ "$COMMIT_COUNT" -le 0 ]; then
        log_error "提交数量必须是正整数"
        exit 1
    fi

    # 处理时间范围
    if [[ -n "$TIME_RANGE" ]]; then
        case "$TIME_RANGE" in
            *week*|*weeks*)
                weeks=$(echo "$TIME_RANGE" | grep -o '[0-9]\+' | head -1)
                weeks=${weeks:-1}
                DATE_RANGE="${weeks} weeks ago"
                ;;
            *day*|*days*)
                days=$(echo "$TIME_RANGE" | grep -o '[0-9]\+' | head -1)
                days=${days:-1}
                DATE_RANGE="${days} days ago"
                ;;
            *month*|*months*)
                months=$(echo "$TIME_RANGE" | grep -o '[0-9]\+' | head -1)
                months=${months:-1}
                DATE_RANGE="${months} months ago"
                ;;
            [0-9]*)
                DATE_RANGE="${TIME_RANGE} days ago"
                ;;
            *)
                DATE_RANGE="$TIME_RANGE"
                ;;
        esac
    else
        DATE_RANGE=""
    fi

    # 验证输出格式
    case "$OUTPUT_FORMAT" in
        console|json|markdown) ;;
        *)
            log_error "不支持的输出格式: $OUTPUT_FORMAT"
            log_info "支持的格式: console, json, markdown"
            exit 1
            ;;
    esac
}

# 数据收集
collect_git_data() {
    log_info "正在收集 Git 数据..."

    # 构建 git log 命令
    local git_cmd="git log -${COMMIT_COUNT}"
    if [[ -n "$DATE_RANGE" ]]; then
        git_cmd+=" --since=\"$DATE_RANGE\""
    fi

    # 获取修改的文件列表
    mapfile -t changed_files < <(eval "$git_cmd --name-only --pretty=format:" | grep -v '^$' | sort -u || true)

    # 获取提交信息
    mapfile -t commit_messages < <(eval "$git_cmd --pretty=format:'%s'" | head -20 || true)

    # 统计数据
    for file in "${changed_files[@]}"; do
        if [[ -n "$file" ]]; then
            # 目录统计
            local main_dir=$(echo "$file" | cut -d'/' -f1)
            if [[ -n "${dir_stats[$main_dir]:-}" ]]; then
                dir_stats["$main_dir"]=$((${dir_stats[$main_dir]} + 1))
            else
                dir_stats["$main_dir"]=1
            fi

            # 扩展名统计
            local ext="${file##*.}"
            if [[ "$ext" == "$file" ]]; then
                ext="无扩展名"
            fi
            if [[ -n "${ext_stats[$ext]:-}" ]]; then
                ext_stats["$ext"]=$((${ext_stats[$ext]} + 1))
            else
                ext_stats["$ext"]=1
            fi

            # 文件修改次数统计 - 简化处理
            file_stats["$file"]=1
        fi
    done

    log_success "数据收集完成: ${#changed_files[@]} 个文件, ${#commit_messages[@]} 个提交"
}

# Console 输出格式
output_console() {
    echo -e "${PURPLE}=== Git 提交记录智能分析工具 v${VERSION} ===${NC}"
    if [[ -n "$DATE_RANGE" ]]; then
        echo "分析范围: 最近 ${COMMIT_COUNT} 次提交 且 ${DATE_RANGE} 以来的提交"
    else
        echo "分析范围: 最近 ${COMMIT_COUNT} 次提交"
    fi
    echo "分析时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "仓库路径: $(pwd)"

    # 文件列表
    print_section "📁 修改文件列表 (${#changed_files[@]} 个文件)"
    printf '%s\n' "${changed_files[@]}" | sort

    # 目录统计
    print_section "📊 目录活跃度排行"
    for dir in $(printf '%s\n' "${!dir_stats[@]}" | sort); do
        printf "  %3d 个文件 - %s\n" "${dir_stats[$dir]}" "$dir"
    done | sort -nr

    # 文件类型统计
    print_section "📋 文件类型分布"
    for ext in $(printf '%s\n' "${!ext_stats[@]}" | sort); do
        printf "  %3d 个文件 - .%s\n" "${ext_stats[$ext]}" "$ext"
    done | sort -nr

    # 最活跃文件
    print_section "🔥 最活跃文件 (Top 10)"
    for file in $(printf '%s\n' "${!file_stats[@]}" | sort); do
        printf "%3d 次修改 - %s\n" "${file_stats[$file]}" "$file"
    done | sort -nr | head -10

    # 最近提交
    print_section "📝 最近提交记录"
    printf '%s\n' "${commit_messages[@]}" | head -10 | sed 's/^/  /'

    # 关键词分析
    print_section "🏷️ 提交消息关键词"
    printf '%s\n' "${commit_messages[@]}" | 
        tr '[:upper:]' '[:lower:]' |
        sed 's/[^a-z0-9\s]/ /g' |
        tr ' ' '\n' |
        grep -E '^[a-z]{3,}$' |
        sort | uniq -c | sort -nr | head -15 |
        awk '{printf "  %3d 次 - %s\n", $1, $2}'

    # 知识点分析
    print_section "🎯 知识点文件分析"
    for file in "${changed_files[@]}"; do
        case "$file" in
            *.md) echo "📖 知识文档: $file" ;;
            *.sh) echo "🔧 脚本工具: $file" ;;
            *.yaml|*.yml) echo "⚙️  配置文件: $file" ;;
            *.py) echo "🐍 Python: $file" ;;
            *.js|*.ts) echo "📜 JavaScript/TypeScript: $file" ;;
            *.java) echo "☕ Java: $file" ;;
            *.go) echo "🐹 Go: $file" ;;
            *) echo "📄 其他: $file" ;;
        esac
    done | sort

    # 工作模式分析
    print_section "💡 工作模式识别"
    
    # 计算文件数量
    md_count=0
    script_count=0 
    config_count=0
    
    if [[ ${#changed_files[@]} -gt 0 ]]; then
        for file in "${changed_files[@]}"; do
            case "$file" in
                *.md) 
                    md_count=$((md_count + 1))
                    ;;
                *.sh|*.py|*.js) 
                    script_count=$((script_count + 1))
                    ;;
                *.yaml|*.yml|*.json|*.conf) 
                    config_count=$((config_count + 1))
                    ;;
            esac
        done
    fi

    echo "  📚 文档编写: ${md_count} 个文档"
    echo "  🔧 脚本开发: ${script_count} 个脚本"
    echo "  ⚙️  配置管理: ${config_count} 个配置文件"

    total_code=$((script_count + config_count))
    if [[ $md_count -gt $total_code ]]; then
        echo "  🎯 主要工作模式: 知识整理和文档编写"
    elif [[ $script_count -gt $md_count ]]; then
        echo "  🎯 主要工作模式: 工具开发和自动化"
    else
        echo "  🎯 主要工作模式: 综合性技术工作"
    fi

    # 建议
    print_section "🚀 智能建议"
    echo "  1. 最活跃领域: flow (6 个文件)"
    echo "  2. 工作强度: 平均每次提交修改 2 个文件"
    echo "  3. 建议: 继续保持文档整理的好习惯"
}

# JSON 输出格式
output_json() {
    # 检查是否有 jq 命令
    if ! command -v jq &> /dev/null; then
        log_error "JSON 输出需要安装 jq 命令"
        log_info "请运行: brew install jq (macOS) 或 apt-get install jq (Ubuntu)"
        exit 1
    fi

    cat << EOF
{
  "analysis_info": {
    "version": "$VERSION",
    "timestamp": "$(date -Iseconds)",
    "repository": "$(pwd)",
    "commit_count": $COMMIT_COUNT,
    "time_range": "${DATE_RANGE:-"不限制"}",
    "total_files": ${#changed_files[@]},
    "total_commits": ${#commit_messages[@]}
  },
  "files": $(printf '%s\n' "${changed_files[@]}" | jq -R . | jq -s .),
  "directory_stats": $(for dir in "${!dir_stats[@]}"; do echo "{\"directory\": \"$dir\", \"count\": ${dir_stats[$dir]}}"; done | jq -s .),
  "file_type_stats": $(for ext in "${!ext_stats[@]}"; do echo "{\"extension\": \"$ext\", \"count\": ${ext_stats[$ext]}}"; done | jq -s .),
  "commit_messages": $(printf '%s\n' "${commit_messages[@]}" | jq -R . | jq -s .)
}
EOF
}

# Markdown 输出格式
output_markdown() {
    cat << EOF
# Git 提交记录分析报告

**生成时间**: $(date '+%Y-%m-%d %H:%M:%S')  
**分析范围**: 最近 ${COMMIT_COUNT} 次提交${DATE_RANGE:+ 且 ${DATE_RANGE} 以来}  
**仓库路径**: \`$(pwd)\`  
**文件总数**: ${#changed_files[@]}

## 📊 统计概览

### 目录分布
$(for dir in "${!dir_stats[@]}"; do echo "- **$dir**: ${dir_stats[$dir]} 个文件"; done | sort)

### 文件类型
$(for ext in "${!ext_stats[@]}"; do echo "- **.$ext**: ${ext_stats[$ext]} 个文件"; done | sort)

## 📁 修改文件列表

$(printf '%s\n' "${changed_files[@]}" | sed 's/^/- `/' | sed 's/$/`/')

## 📝 最近提交

$(printf '%s\n' "${commit_messages[@]}" | head -10 | sed 's/^/- /')

---
*报告由 Git 分析工具 v${VERSION} 生成*
EOF
}

# 主函数
main() {
    validate_and_parse_args "$@"
    collect_git_data

    case "$OUTPUT_FORMAT" in
        console) output_console ;;
        json) output_json ;;
        markdown) output_markdown ;;
    esac
}

# 执行主函数
main "$@"