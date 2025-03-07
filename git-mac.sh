#!/bin/bash
os_type=""
os_name=$(uname -s)

case $os_name in
Linux)
  os_type="Linux"
  ;;
Darwin)
  os_type="macOS"
  ;;
*)
  os_type="iPhone"
  ;;
esac

# 检查目录
dir=$(pwd)
if [ ! -d "$dir" ]; then
  echo "Directory $dir does not exist."
  exit 1
fi

# 检查是否有改动
if [ -z "$(git status --porcelain)" ]; then
  echo "No changes to commit."
  exit 0
fi

# 显示改动摘要
echo "Changes Summary:"
echo "==============="
git diff --stat HEAD
echo "==============="

# 获取所有改变的文件列表
changed_files=$(git diff --name-only HEAD)

# 处理每个改动的文件
for filename in $changed_files; do
  full_path="$dir/$filename"
  /Users/lex/shell/replace.sh "$full_path"
  if [ $? -ne 0 ]; then
    echo "Failed to execute replace script for $filename"
    exit 1
  fi
done

# 添加所有改动
git add .

# 获取改动统计
files_changed=$(git diff --cached --numstat | wc -l | tr -d '[:space:]')
insertions=$(git diff --cached --stat | tail -n1 | cut -d' ' -f5)
deletions=$(git diff --cached --stat | tail -n1 | cut -d' ' -f7)

# 提示用户输入自定义提交信息（可选）
echo -n "Enter custom commit message (press Enter to skip): "
read custom_message

# 构建提交信息
timestamp=$(date "+%Y-%m-%d %H:%M:%S")
if [ -n "$custom_message" ]; then
  commit_message="[$os_type] $custom_message

Changes: $files_changed files modified ($insertions insertions, $deletions deletions)
Time: $timestamp"
else
  commit_message="[$os_type] Auto commit

Changes: $files_changed files modified ($insertions insertions, $deletions deletions)
Time: $timestamp"
fi

# 提交改动
git commit -m "$commit_message"
if [ $? -ne 0 ]; then
  echo "Failed to commit changes."
  exit 1
fi

# 推送改动
git push
if [ $? -ne 0 ]; then
  echo "Failed to push changes."
  exit 1
fi

echo "Successfully committed and pushed changes."