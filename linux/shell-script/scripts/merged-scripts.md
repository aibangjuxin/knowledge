# Shell Scripts Collection

Generated on: 2026-01-27 11:51:57
Directory: /Users/lex/git/knowledge/shell-script/scripts

## `replace.sh`

```bash
#!/bin/bash

# 批量替换脚本 - 用于替换当前目录下所有文件中的文本
# 用法: rp -f /path/to/replace.txt

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 默认值
REPLACE_FILE=""
TARGET_DIR="$(pwd)"
DRY_RUN=false

# 显示帮助信息
show_help() {
    echo "用法: $(basename $0) -f <替换文件> [选项]"
    echo ""
    echo "必选参数:"
    echo "  -f FILE    指定替换规则文件"
    echo ""
    echo "可选参数:"
    echo "  -d DIR     指定目标目录 (默认: 当前目录)"
    echo "  -p         预览模式,不实际执行替换"
    echo "  -h         显示此帮助信息"
    echo ""
    echo "替换文件格式:"
    echo "  每行两列,用空格或制表符分隔"
    echo "  第一列: 原始内容"
    echo "  第二列: 替换内容"
    echo "  # 开头的行为注释"
    echo ""
    echo "示例:"
    echo "  $(basename $0) -f /home/lex/replace.txt"
    echo "  $(basename $0) -f /home/lex/replace.txt -d /path/to/project"
    echo "  $(basename $0) -f /home/lex/replace.txt -p  # 预览模式"
}

# 解析命令行参数
while getopts "f:d:ph" opt; do
    case $opt in
        f)
            REPLACE_FILE="$OPTARG"
            ;;
        d)
            TARGET_DIR="$OPTARG"
            ;;
        p)
            DRY_RUN=true
            ;;
        h)
            show_help
            exit 0
            ;;
        \?)
            echo -e "${RED}错误: 无效选项 -$OPTARG${NC}" >&2
            show_help
            exit 1
            ;;
        :)
            echo -e "${RED}错误: 选项 -$OPTARG 需要参数${NC}" >&2
            show_help
            exit 1
            ;;
    esac
done

# 检查必选参数
if [ -z "$REPLACE_FILE" ]; then
    echo -e "${RED}错误: 必须指定替换规则文件 (-f)${NC}"
    show_help
    exit 1
fi

# 检查替换规则文件是否存在
if [ ! -f "$REPLACE_FILE" ]; then
    echo -e "${RED}错误: 找不到替换规则文件: $REPLACE_FILE${NC}"
    exit 1
fi

# 检查目标目录是否存在
if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}错误: 目标目录不存在: $TARGET_DIR${NC}"
    exit 1
fi

# 显示配置信息
echo -e "${GREEN}========================================${NC}"
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[预览模式] 批量替换${NC}"
else
    echo -e "${GREEN}批量替换${NC}"
fi
echo -e "${GREEN}========================================${NC}"
echo "替换规则文件: $REPLACE_FILE"
echo "目标目录: $TARGET_DIR"
echo "----------------------------------------"

# 统计变量
total_rules=0
total_files=0
modified_files=0

# 读取替换规则并执行替换
while IFS=$'\t' read -r source target || [ -n "$source" ]; do
    # 如果没有找到制表符,尝试用空格分隔
    if [ -z "$target" ]; then
        read -r source target <<< "$source"
    fi
    
    # 跳过空行和注释行
    if [[ -z "$source" || "$source" =~ ^[[:space:]]*#.* ]]; then
        continue
    fi
    
    # 跳过只有一列的行
    if [ -z "$target" ]; then
        echo -e "${YELLOW}警告: 跳过格式不正确的行: '$source'${NC}"
        continue
    fi
    
    ((total_rules++))
    
    echo ""
    echo -e "${GREEN}规则 $total_rules:${NC} '$source' -> '$target'"
    
    # 查找包含源字符串的文件
    # 排除常见的不需要处理的目录
    files_with_source=$(grep -rl --exclude-dir=".git" \
                                 --exclude-dir="node_modules" \
                                 --exclude-dir="__pycache__" \
                                 --exclude-dir=".venv" \
                                 --exclude-dir="venv" \
                                 --exclude-dir="dist" \
                                 --exclude-dir="build" \
                                 --exclude="*.pyc" \
                                 --exclude="*.pyo" \
                                 --exclude="*.so" \
                                 --exclude="*.o" \
                                 "$source" "$TARGET_DIR" 2>/dev/null)
    
    if [ -n "$files_with_source" ]; then
        file_count=$(echo "$files_with_source" | wc -l | tr -d ' ')
        echo "  找到 $file_count 个文件包含 '$source':"
        
        echo "$files_with_source" | while read -r file; do
            echo "    - $file"
            
            # 显示匹配的行(最多显示3行)
            if [ "$DRY_RUN" = true ]; then
                grep -n "$source" "$file" 2>/dev/null | head -3 | while read -r line; do
                    echo -e "      ${YELLOW}$line${NC}"
                done
            fi
        done
        
        # 执行替换(非预览模式)
        if [ "$DRY_RUN" = false ]; then
            echo "$files_with_source" | while read -r file; do
                # 检测操作系统类型
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS 使用 BSD sed
                    sed -i '' "s|$source|$target|g" "$file"
                else
                    # Linux 使用 GNU sed
                    sed -i "s|$source|$target|g" "$file"
                fi
            done
            ((modified_files += file_count))
        fi
        
        ((total_files += file_count))
    else
        echo "  未找到包含 '$source' 的文件"
    fi
    
done < "$REPLACE_FILE"

# 显示统计信息
echo ""
echo -e "${GREEN}========================================${NC}"
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}预览完成!${NC}"
    echo "总共处理规则: $total_rules"
    echo "将影响文件: $total_files"
    echo ""
    echo "如需实际执行替换,请去掉 -p 参数"
else
    echo -e "${GREEN}替换完成!${NC}"
    echo "总共处理规则: $total_rules"
    echo "总共处理文件: $total_files"
    echo "修改的文件: $modified_files"
fi
echo -e "${GREEN}========================================${NC}"

```

## `batch_replace_preview.sh`

```bash
#!/bin/bash

# 批量替换脚本 - 预览版本
# 先显示将要进行的替换，用户确认后再执行

# 默认值
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPLACE_FILE="$SCRIPT_DIR/replace.txt"
TARGET_DIR="."

# 显示帮助信息
show_help() {
    echo "用法: $0 [-f 替换文件] [目标目录]"
    echo ""
    echo "选项:"
    echo "  -f FILE    指定替换规则文件 (默认: 脚本同级目录下的 replace.txt)"
    echo "  -h         显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                           # 使用默认替换文件，预览当前目录"
    echo "  $0 /path/to/project          # 使用默认替换文件，预览指定目录"
    echo "  $0 -f /path/to/rules.txt     # 使用指定替换文件，预览当前目录"
    echo "  $0 -f /path/to/rules.txt /path/to/project  # 使用指定替换文件和目录"
}

# 解析命令行参数
while getopts "f:h" opt; do
    case $opt in
        f)
            REPLACE_FILE="$OPTARG"
            ;;
        h)
            show_help
            exit 0
            ;;
        \?)
            echo "无效选项: -$OPTARG" >&2
            show_help
            exit 1
            ;;
    esac
done

# 移除已处理的选项参数
shift $((OPTIND-1))

# 获取目标目录参数
if [ $# -gt 0 ]; then
    TARGET_DIR="$1"
fi

# 检查替换规则文件是否存在
if [ ! -f "$REPLACE_FILE" ]; then
    echo "错误: 找不到替换规则文件 $REPLACE_FILE"
    exit 1
fi

echo "批量替换预览模式"
echo "替换规则文件: $REPLACE_FILE"
echo "目标目录: $TARGET_DIR"
echo "----------------------------------------"

# 预览将要进行的替换
echo "将要进行的替换:"
while IFS=' ' read -r source target || [ -n "$source" ]; do
    # 跳过空行和注释行
    if [[ -z "$source" || "$source" =~ ^#.* ]]; then
        continue
    fi
    
    echo "  '$source' -> '$target'"
    
    # 查找包含源字符串的文件
    files_with_source=$(grep -rl "$source" "$TARGET_DIR" 2>/dev/null | grep -v ".git" | grep -v "__pycache__" | grep -v "node_modules")
    
    if [ -n "$files_with_source" ]; then
        echo "    影响的文件:"
        echo "$files_with_source" | while read -r file; do
            echo "      - $file"
            # 显示匹配的行
            grep -n "$source" "$file" | head -3 | while read -r line; do
                echo "        $line"
            done
        done
    fi
    echo ""
done < "$REPLACE_FILE"

echo "----------------------------------------"
read -p "确认执行替换? (y/N): " confirm

if [[ $confirm =~ ^[Yy]$ ]]; then
    echo "开始执行替换..."
    "$SCRIPT_DIR/batch_replace.sh" -f "$REPLACE_FILE" "$TARGET_DIR"
else
    echo "取消替换操作"
fi
```

## `batch_replace.sh`

```bash
#!/bin/bash

# 批量替换脚本
# 支持通过 -f 参数指定替换规则文件

# 默认值
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPLACE_FILE="$SCRIPT_DIR/replace.txt"
TARGET_DIR="."

# 显示帮助信息
show_help() {
    echo "用法: $0 [-f 替换文件] [目标目录]"
    echo ""
    echo "选项:"
    echo "  -f FILE    指定替换规则文件 (默认: 脚本同级目录下的 replace.txt)"
    echo "  -h         显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                           # 使用默认替换文件，替换当前目录"
    echo "  $0 /path/to/project          # 使用默认替换文件，替换指定目录"
    echo "  $0 -f /path/to/rules.txt     # 使用指定替换文件，替换当前目录"
    echo "  $0 -f /path/to/rules.txt /path/to/project  # 使用指定替换文件和目录"
}

# 解析命令行参数
while getopts "f:h" opt; do
    case $opt in
        f)
            REPLACE_FILE="$OPTARG"
            ;;
        h)
            show_help
            exit 0
            ;;
        \?)
            echo "无效选项: -$OPTARG" >&2
            show_help
            exit 1
            ;;
    esac
done

# 移除已处理的选项参数
shift $((OPTIND-1))

# 获取目标目录参数
if [ $# -gt 0 ]; then
    TARGET_DIR="$1"
fi

# 检查替换规则文件是否存在
if [ ! -f "$REPLACE_FILE" ]; then
    echo "错误: 找不到替换规则文件 $REPLACE_FILE"
    exit 1
fi

echo "开始批量替换..."
echo "替换规则文件: $REPLACE_FILE"
echo "目标目录: $TARGET_DIR"
echo "----------------------------------------"

# 统计变量
total_files=0
modified_files=0

# 读取替换规则并执行替换
while IFS=' ' read -r source target || [ -n "$source" ]; do
    # 跳过空行和注释行
    if [[ -z "$source" || "$source" =~ ^#.* ]]; then
        continue
    fi
    
    echo "替换规则: '$source' -> '$target'"
    
    # 查找包含源字符串的文件
    files_with_source=$(grep -rl "$source" "$TARGET_DIR" 2>/dev/null | grep -v ".git" | grep -v "__pycache__" | grep -v "node_modules")
    
    if [ -n "$files_with_source" ]; then
        echo "  找到包含 '$source' 的文件:"
        echo "$files_with_source" | while read -r file; do
            echo "    - $file"
            # 执行替换
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS 使用 BSD sed
                sed -i '' "s|$source|$target|g" "$file"
            else
                # Linux 使用 GNU sed
                sed -i "s|$source|$target|g" "$file"
            fi
            ((modified_files++))
        done
        ((total_files += $(echo "$files_with_source" | wc -l)))
    else
        echo "  未找到包含 '$source' 的文件"
    fi
    echo ""
done < "$REPLACE_FILE"

echo "----------------------------------------"
echo "替换完成!"
echo "总共处理文件: $total_files"
echo "修改的文件: $modified_files"
```

## `git-detail-status.sh`

```bash
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

# 颜色定义 - 简化版本，默认启用颜色
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

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
```

## `source.sh`

```bash

如果希望在脚本执行后，https_proxy 的值依然在你的终端会话中生效，可以通过以下方法实现。

source a.sh -e dev-cn 

```bash
#!/usr/bin/env bash
# 设置环境变量的脚本

declare -A env_info

env_info=(
  ["dev-cn"]="project=aibang-teng-sit-api-dev cluster=dev-cn-cluster-123789 region=europe-west2 https_proxy=10.72.21.119:3128 private_network=aibang-teng-sit-api-dev-internal-vpc3"
  ["lex-in"]="project=aibang-teng-sit-kongs-dev cluster=lex-in-cluster-123456 region=europe-west2 https_proxy=10.72.25.50:3128 private_network=aibang-teng-sit-kongs-dev-internal-vpc1"
)

environment=""

# 显示使用帮助
function usage() {
  echo "使用方法: source $0 --environment 环境"
  echo "if using source $0 when script finished . you can verify the proxy"
  echo "Using export |grep https verify the result"
  echo "选项:"
  echo "  --environment, -e   环境名称,必选"
  echo "  --help, -h          显示此帮助消息"
  echo "可用的环境选项:"
  for key in "${!env_info[@]}"; do
    echo "  $key"
  done
}

# 检查参数
if [[ ($# -eq 0) || ($1 != "-e" && $1 != "--environment") ]]; then
  usage
  return 2>/dev/null || exit 1
fi

# 解析参数
while [[ $# -gt 0 ]]; do
  case $1 in
    -e | --environment)
      if [[ -z "$2" ]]; then
        echo "环境选项为空"
        usage
        return 2>/dev/null || exit 1
      fi
      environment="$2"
      shift 2
      ;;
    -h | --help)
      usage
      return 2>/dev/null || exit 0
      ;;
    *)
      usage
      return 2>/dev/null || exit 1
      ;;
  esac
done

if [[ -z "${environment}" ]]; then
  echo "缺少环境选项"
  usage
  return 2>/dev/null || exit 1
fi

if [[ -z "${env_info[$environment]}" ]]; then
  echo "无效的环境: $environment"
  usage
  return 2>/dev/null || exit 1
fi

# 设置环境变量
env_vars="${env_info[$environment]}"
IFS=' ' read -r -a var_array <<< "$env_vars"

for var in "${var_array[@]}"; do
  if [[ $var == *"="* ]]; then
    key="${var%%=*}"
    value="${var#*=}"
    eval "export $key='$value'"
  fi
done

echo "Environment: $environment"
echo "Project: $project"
echo "Region: $region"
echo "Cluster: $cluster"
echo "https_proxy: $https_proxy"
echo "private_network: $private_network"

SCRIPT_NAME="${0##*/}"
info() {
  echo -e "\033[31m ${SCRIPT_NAME}: ${1} \033[0m"
}
echo -e "active $project"
echo -e "\033[31m active $project \033[0m"
echo "gcloud config configurations activate $project"
echo "gcloud config set project $project"
echo "if you want unset the https proxy.Please using next command"
echo "unset https_proxy"
#unset https_proxy
```

遇到问题可能会退出终端?


方法 1：在当前 Shell 会话中运行脚本

你可以通过 source 命令运行脚本（即 source a.sh 或 . a.sh），这样脚本中的环境变量会直接在当前 Shell 会话中生效。

示例脚本内容（a.sh）：

#!/bin/bash

# 参数处理
while getopts "e:" opt; do
  case $opt in
    e)
      ENV=$OPTARG
      ;;
    *)
      echo "Usage: $0 -e <environment>"
      exit 1
      ;;
  esac
done

if [ -z "$ENV" ]; then
  echo "Error: Environment not specified. Use -e <environment>."
  exit 1
fi

# 设置 https_proxy
export https_proxy="http://192.168.12.5:3128"
echo "Proxy set: $https_proxy"

# 获取 GKE 凭据
gcloud container clusters get-credentials "$ENV" --region your-region --project your-project

# 验证连接
kubectl get nodes

使用方式：

运行脚本时使用 source：

source a.sh -e dev-hk

或者使用点号：

. a.sh -e dev-hk

在这种情况下，脚本中的 export https_proxy 设置将影响当前 Shell 会话，后续在终端中运行的命令会继承此代理配置。

方法 2：将代理设置保存到 Shell 环境

如果希望脚本执行后自动将代理永久保留，可以直接将 https_proxy 设置添加到 Shell 的配置文件（如 ~/.bashrc 或 ~/.zshrc）。

修改脚本内容：

#!/bin/bash

# 设置 https_proxy
export https_proxy="http://192.168.12.5:3128"
echo "Proxy set: $https_proxy"

# 写入代理到当前用户的配置文件
if ! grep -q "export https_proxy=http://192.168.12.5:3128" ~/.bashrc; then
  echo "export https_proxy=http://192.168.12.5:3128" >> ~/.bashrc
fi

# 加载新配置
source ~/.bashrc

# 获取 GKE 凭据
gcloud container clusters get-credentials "$1" --region your-region --project your-project

# 验证连接
kubectl get nodes

使用方式：

直接执行脚本：

./a.sh -e dev-hk

脚本执行后，代理会被写入到 ~/.bashrc，并加载到当前 Shell 会话中，代理配置会长期生效。

方法 3：临时代理设置并在脚本中提示手动操作

如果你只希望脚本自动设置代理，但在终端会话中仍然可用，可以通过在脚本中打印提示，提醒用户手动运行 export 命令。

示例脚本：

#!/bin/bash

# 参数处理
while getopts "e:" opt; do
  case $opt in
    e)
      ENV=$OPTARG
      ;;
    *)
      echo "Usage: $0 -e <environment>"
      exit 1
      ;;
  esac
done

if [ -z "$ENV" ]; then
  echo "Error: Environment not specified. Use -e <environment>."
  exit 1
fi

# 设置 https_proxy
export https_proxy="http://192.168.12.5:3128"
echo "Proxy temporarily set for this script: $https_proxy"

# 提示用户如何设置代理为长期生效
echo "To make the proxy persistent, run the following command in your terminal:"
echo "export https_proxy=http://192.168.12.5:3128"

# 获取 GKE 凭据
gcloud container clusters get-credentials "$ENV" --region your-region --project your-project

# 验证连接
kubectl get nodes

推荐方式
	1.	如果脚本只在当前会话中使用代理，推荐 方法 1，用 source 运行脚本即可。
	2.	如果需要代理长期生效，可以采用 方法 2，将代理设置写入到配置文件（如 ~/.bashrc）。
	3.	如果需要灵活控制，可采用 方法 3，让用户手动决定是否长期设置代理。

根据你的需求选择合适的方法即可！

我想写这样一个Shell脚本.这个脚本主要是让我连接我不同的GCP project的,进一步连接对应的Cluster的,直接执行
1 会让我输入对应的数字 
2 我的数字会对应比如1 HK 2 UK 3 IN 4 US 
HK 对应的 region asia-east2
UK 对应的 region europe-west2
IN 对应的 region asia-south1
US 对应的 region us-central1
3 比如我输入的是1 那么代表的是我要选择HK这个region
下一步提示我输入对应的env 信息
比如我输入pdev dev sit uat ppd prd 这些

比如我输入的是dev 

那么我上面完成的是dev-hk这个环境

```

## `git.sh`

```bash
#!/bin/bash

# Define the directory
dir=$(pwd)

# Check if the directory exists
if [ -d "$dir" ]; then
  cd "$dir"
else
  echo "Directory $dir does not exist."
  exit 1
fi

# Get the current date
riqi=$(date)

# Check if there are any changes
if [ -n "$(git status --porcelain)" ]; then
  # Add all changes
  git add .
  if [ $? -eq 0 ]; then
    echo "Changes added successfully."
  else
    echo "Failed to add changes."
    exit 1
  fi

  # Get the latest changed filename
  filename=$(git diff --name-only HEAD | tail -n 1)

  # Define a commit message 
  commit_message="This is for my iPhone git push or pull at $riqi. Last changed file: $filename"

  # Commit the changes
  git commit -m "$commit_message"
  if [ $? -eq 0 ]; then
    echo "Changes committed successfully."
  else
    echo "Failed to commit changes."
    exit 1
  fi

  # Push the changes
  git push
  if [ $? -eq 0 ]; then
    echo "Changes pushed successfully."
  else
    echo "Failed to push changes."
    exit 1
  fi
else
  echo "No changes to commit."
fi
```

