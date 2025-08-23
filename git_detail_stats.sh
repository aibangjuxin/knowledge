#!/opt/homebrew/bin/bash

# 配置参数
COMMIT_COUNT=${1:-20}
TIME_RANGE=${2:-""}

# 处理时间范围参数
if [[ -n "$TIME_RANGE" ]]; then
    case "$TIME_RANGE" in
        *week*|*weeks*)
            # 提取数字，如果没有数字默认为1
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
            # 如果是纯数字，当作天数处理
            DATE_RANGE="${TIME_RANGE} days ago"
            ;;
        *)
            # 如果是其他格式，直接使用
            DATE_RANGE="$TIME_RANGE"
            ;;
    esac
else
    # 如果没有指定时间范围，使用提交数量限制
    DATE_RANGE=""
fi

echo "=== Git 提交记录知识点分析工具 ==="
if [[ -n "$DATE_RANGE" ]]; then
    echo "分析范围: 最近 ${COMMIT_COUNT} 次提交 且 ${DATE_RANGE} 以来的提交"
else
    echo "分析范围: 最近 ${COMMIT_COUNT} 次提交"
fi
echo "分析时间: $(date)"
echo

# 获取所有修改的文件
get_changed_files() {
    if [[ -n "$DATE_RANGE" ]]; then
        # 如果指定了时间范围，同时考虑提交数量和时间
        git log -${COMMIT_COUNT} --since="$DATE_RANGE" --name-only --pretty=format: | grep -v '^$' | sort -u
    else
        # 只按提交数量限制
        git log -${COMMIT_COUNT} --name-only --pretty=format: | grep -v '^$' | sort -u
    fi
}

# 1. 直接展示所有修改的文件（按目录结构）
echo "📁 所有修改的文件（按目录结构）："
echo "================================================"
get_changed_files | sort | while read file; do
  if [[ -n "$file" ]]; then
    echo "  $file"
  fi
done

echo -e "\n📊 目录层级统计："
echo "================================================"
get_changed_files | while read file; do
  if [[ -n "$file" ]]; then
    # 提取第一级目录
    first_dir=$(echo "$file" | cut -d'/' -f1)
    echo "$first_dir"
  fi
done | sort | uniq -c | sort -nr

echo -e "\n📋 文件类型统计："
echo "================================================"
get_changed_files | while read file; do
  if [[ -n "$file" ]]; then
    extension="${file##*.}"
    if [ "$extension" = "$file" ]; then
      extension="无扩展名"
    fi
    echo "$extension"
  fi
done | sort | uniq -c | sort -nr

echo -e "\n🔥 最活跃的文件 (按修改次数排序)："
echo "================================================"
git log -${COMMIT_COUNT} --name-only --oneline | grep -v "^[0-9a-f]\{7\}" | grep -v '^$' | sort | uniq -c | sort -nr | head -15

echo -e "\n📝 最近的提交记录（文件 + 提交信息）："
echo "================================================"
if [[ -n "$DATE_RANGE" ]]; then
    git log -${COMMIT_COUNT} --since="$DATE_RANGE" --oneline --name-status | head -30
else
    git log -${COMMIT_COUNT} --oneline --name-status | head -30
fi

echo -e "\n🏷️ 提交消息关键词分析："
echo "================================================"
if [[ -n "$DATE_RANGE" ]]; then
    git log -${COMMIT_COUNT} --since="$DATE_RANGE" --pretty=format:"%s"
else
    git log -${COMMIT_COUNT} --pretty=format:"%s"
fi | \
  tr '[:upper:]' '[:lower:]' | \
  sed 's/[^a-z0-9\s]/ /g' | \
  tr ' ' '\n' | \
  grep -E '^[a-z]{3,}$' | \
  sort | uniq -c | sort -nr | head -20

echo -e "\n🎯 知识点文件分析（基于文件名和路径）："
echo "================================================"
get_changed_files | while read file; do
  if [[ -n "$file" ]]; then
    # 提取文件名（不含扩展名）作为潜在知识点
    filename=$(basename "$file")
    filename_no_ext="${filename%.*}"
    dir_path=$(dirname "$file")

    # 如果是markdown文件，更可能是知识点文档
    if [[ "$file" == *.md ]]; then
      echo "📖 知识文档: $file"
    elif [[ "$file" == *.sh ]]; then
      echo "🔧 脚本工具: $file"
    elif [[ "$file" == *.yaml ]] || [[ "$file" == *.yml ]]; then
      echo "⚙️  配置文件: $file"
    else
      echo "📄 其他文件: $file"
    fi
  fi
done | sort

echo -e "\n🌳 目录结构知识点分布："
echo "================================================"
# 生成树状结构显示
get_changed_files | sort | while read file; do
  if [[ -n "$file" ]]; then
    # 计算目录深度
    depth=$(echo "$file" | tr -cd '/' | wc -c)
    indent=""
    for ((i = 0; i < depth; i++)); do
      indent+="  "
    done

    # 只显示文件名
    filename=$(basename "$file")
    echo "${indent}├── $filename"
  fi
done | head -50 # 限制显示数量

echo -e "\n📈 工作重点分析（基于实际目录结构）："
echo "================================================"
declare -A dir_stats
get_changed_files | while read file; do
  if [[ -n "$file" ]]; then
    # 提取第一级目录作为主要工作领域
    main_dir=$(echo "$file" | cut -d'/' -f1)
    echo "$main_dir"
  fi
done | sort | uniq -c | sort -nr | while read count dir; do
  echo "  $count 个文件 - $dir 相关"
done

echo -e "\n🎨 动态生成MindMap结构："
echo "================================================"
echo "基于你的实际目录结构生成："
echo ""
echo '```mermaid'
echo 'mindmap'
echo '  root((我的知识库))'

# 动态生成mindmap，基于实际目录结构
declare -A mindmap_dirs
get_changed_files | while read file; do
  if [[ -n "$file" && "$file" == *.md ]]; then
    main_dir=$(echo "$file" | cut -d'/' -f1)
    filename=$(basename "$file" .md)
    echo "$main_dir|$filename|$file"
  fi
done | sort | while IFS='|' read main_dir filename filepath; do
  if [[ -n "$main_dir" ]]; then
    echo "    $main_dir"
    echo "      $filename"
  fi
done | sort -u

echo '```'

echo -e "\n💡 智能建议："
echo "================================================"
echo "基于分析结果的建议："

# 分析文件数量最多的目录
top_dir=$(get_changed_files | while read file; do
  echo "$file" | cut -d'/' -f1
done | sort | uniq -c | sort -nr | head -1 | awk '{print $2}')

if [[ -n "$top_dir" ]]; then
  echo "1. 你最活跃的工作领域是: $top_dir"
fi

md_count=$(get_changed_files | grep -c '\.md$')
echo "2. 你创建/修改了 $md_count 个知识文档"

script_count=$(get_changed_files | grep -c '\.sh$')
if [[ $script_count -gt 0 ]]; then
  echo "3. 你开发了 $script_count 个脚本工具"
fi

echo -e "\n📖 使用方法："
echo "================================================"
echo "  $0                    # 分析最近20次提交"
echo "  $0 30                 # 分析最近30次提交"
echo "  $0 20 2weeks          # 分析最近20次提交且2周内的"
echo "  $0 50 1month          # 分析最近50次提交且1个月内的"
echo "  $0 10 7days           # 分析最近10次提交且7天内的"
echo "  $0 15 14              # 分析最近15次提交且14天内的"
echo ""
echo "时间范围支持格式："
echo "  - 数字 (当作天数): 7, 14, 30"
echo "  - 带单位: 1week, 2weeks, 1month, 3months, 7days"
echo "  - Git格式: '1 week ago', '2 months ago'"
