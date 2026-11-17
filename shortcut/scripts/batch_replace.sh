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

# 检查目标目录是否存在
if [ ! -d "$TARGET_DIR" ]; then
    echo "错误: 目标目录不存在 $TARGET_DIR"
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
while read -r line || [ -n "$line" ]; do
    # 跳过空行和注释行
    if [[ -z "$line" || "$line" =~ ^#.* || "$line" =~ ^[[:space:]]*$ ]]; then
        continue
    fi
    
    # 解析源字符串和目标字符串（用第一个空格分隔）
    source=$(echo "$line" | cut -d' ' -f1)
    target=$(echo "$line" | cut -d' ' -f2-)
    
    # 跳过无效行
    if [[ -z "$source" || -z "$target" ]]; then
        continue
    fi
    
    echo "替换规则: '$source' -> '$target'"
    
    # 查找包含源字符串的文件
    files_with_source=$(grep -rl "$source" "$TARGET_DIR" 2>/dev/null | grep -v ".git" | grep -v "__pycache__" | grep -v "node_modules" | grep -v ".DS_Store")
    
    if [ -n "$files_with_source" ]; then
        echo "  找到包含 '$source' 的文件:"
        file_count=0
        while IFS= read -r file; do
            echo "    - $file"
            # 执行替换
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS 使用 BSD sed，转义特殊字符
                escaped_source=$(printf '%s\n' "$source" | sed 's/[[\.*^$()+?{|]/\\&/g')
                escaped_target=$(printf '%s\n' "$target" | sed 's/[[\.*^$()+?{|]/\\&/g')
                sed -i '' "s|$escaped_source|$escaped_target|g" "$file"
            else
                # Linux 使用 GNU sed，转义特殊字符
                escaped_source=$(printf '%s\n' "$source" | sed 's/[[\.*^$()+?{|]/\\&/g')
                escaped_target=$(printf '%s\n' "$target" | sed 's/[[\.*^$()+?{|]/\\&/g')
                sed -i "s|$escaped_source|$escaped_target|g" "$file"
            fi
            ((file_count++))
        done <<< "$files_with_source"
        ((total_files += file_count))
        ((modified_files += file_count))
    else
        echo "  未找到包含 '$source' 的文件"
    fi
    echo ""
done < "$REPLACE_FILE"

echo "----------------------------------------"
echo "替换完成!"
echo "总共处理文件: $total_files"
echo "修改的文件: $modified_files"