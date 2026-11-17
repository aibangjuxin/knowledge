#!/bin/bash

echo "📁 当前目录: $(pwd)"
echo "🔍 查找 .sh 文件..."

# 检查是否有 .sh 文件
if ls *.sh 1> /dev/null 2>&1; then
    echo "找到以下 .sh 文件 (按时间由新到旧排序):"
    ls -1t *.sh
else
    echo "❌ 当前目录没有找到 .sh 文件"
    exit 1
fi

# 询问输出文件名
echo
read -p "📝 请输入输出文件名 (默认: merged-scripts.md): " output_file

# 使用默认值
if [ -z "$output_file" ]; then
    output_file="merged-scripts.md"
fi

# 确保 .md 扩展名
if [[ "$output_file" != *.md ]]; then
    output_file="${output_file}.md"
fi

echo "📄 将合并到文件: $output_file"

# 询问确认
read -p "🤔 确认继续? (y/N): " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "❌ 操作已取消"
    exit 0
fi

# 生成合并文件
echo "🚀 开始合并文件..."

{
    echo "# Shell Scripts Collection"
    echo
    echo "Generated on: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Directory: $(pwd)"
    echo
    
    # 获取按修改时间排序的文件列表 (最晚修改的在前面)
    files=$(ls -t *.sh)
    
    for file in $files; do
        if [ -f "$file" ]; then
            echo "## \`$file\`"
            echo
            echo '```bash'
            cat "$file"
            echo
            echo '```'
            echo
        fi
    done
} > "$output_file"

echo "✅ 合并完成！"
echo "📄 输出文件: $output_file"
echo "📊 合并了 $(ls -1 *.sh 2>/dev/null | wc -l | tr -d ' ') 个脚本文件"

# 转换行尾为 LF
echo "🔄 正在检查并转换行尾格式..."
if command -v dos2unix >/dev/null 2>&1; then
    dos2unix "$output_file"
    echo "✅ 已使用 dos2unix 转换为 LF 格式"
else
    # Mac/BSD sed syntax
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' 's/\r$//' "$output_file"
    else
        # GNU sed syntax
        sed -i 's/\r$//' "$output_file"
    fi
    echo "✅ 已使用 sed 转换为 LF 格式"
fi