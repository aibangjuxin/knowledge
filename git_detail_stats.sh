#!/bin/bash

echo "=== 最近20次提交的详细统计 ==="
echo

# 文件改动统计
echo "文件改动频率统计："
git log -20 --name-only --oneline | grep -v "^[0-9a-f]\{7\}" | sort | uniq -c | sort -nr

echo -e "\n各类型文件的改动统计："
git log -20 --name-only --oneline | grep -v "^[0-9a-f]\{7\}" | grep -v "^$" | while read file; do
  extension="${file##*.}"
  if [ "$extension" = "$file" ]; then
    extension="无扩展名"
  fi
  echo "$extension"
done | sort | uniq -c | sort -nr

echo -e "\n每次提交的改动行数："
git log -20 --pretty=format:"%h - %s" --shortstat

git log -20 --pretty=format: --name-only | sort -u | grep -v '^$'

echo "在 Markdown 中以图形化方式展示我的知识点，可以通过 Mermaid 生成一个简单的 MindMap 树形图"
