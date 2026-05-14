#!/bin/bash

# 获取操作系统类型
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

echo "操作系统: $os_type"

# 检查并进入工作目录
dir=$(pwd)
if [ ! -d "$dir" ]; then
  echo "目录不存在: $dir"
  exit 1
fi

# 检查是否有改动
if [ -z "$(git status --porcelain)" ]; then
  echo "没有需要提交的改动"
  exit 0
fi

# 获取并处理改动的文件
changed_files=$(git diff --name-only HEAD)
echo "改动的文件列表:"
echo "==============="
git diff --stat HEAD
echo "==============="

# 处理每个改动的文件
for filename in $changed_files; do
  full_path="$dir/$filename"
  echo "处理文件: $filename"
  /Users/lex/shell/replace.sh "$full_path"
  if [ $? -ne 0 ]; then
    echo "处理文件失败: $filename"
    exit 1
  fi
done

# 添加改动
git add .
if [ $? -ne 0 ]; then
  echo "添加改动失败"
  exit 1
fi

# 获取当前分支和最后改动的文件
current_branch=$(git rev-parse --abbrev-ref HEAD)
last_file=$(git diff --name-only HEAD | tail -n 1)

# 构建提交信息
commit_message="[$os_type][$current_branch] 自动提交

最后改动: $last_file
改动时间: $(date '+%Y-%m-%d %H:%M:%S')"

# 提交改动
git commit -m "$commit_message"
if [ $? -ne 0 ]; then
  echo "提交失败"
  exit 1
fi

# 推送改动
git push
if [ $? -ne 0 ]; then
  echo "推送失败"
  exit 1
fi

echo "成功提交并推送所有改动"