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
