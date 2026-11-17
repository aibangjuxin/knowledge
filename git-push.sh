#!/bin/bash

# 函数：获取操作系统类型
get_os_type() {
  case $(uname -s) in
    Linux) echo "Linux" ;;
    Darwin) echo "macOS" ;;
    *) echo "Unknown" ;;
  esac
}

# 函数：调用替换脚本并检查执行结果
run_replace_script() {
  local file="$1"
  /Users/lex/shell/replace.sh "$file"
  local exit_code=$?
  if [ $exit_code -eq 0 ]; then
    echo "Replace script executed successfully for $file."
  else
    echo "Failed to execute replace script for $file."
    exit 1
  fi
}

# 函数：提交并推送更改
commit_and_push_changes() {
  local os_type="$1"
  local riqi=$(date)
  local filename=$(git diff --name-only HEAD | tail -n 1)
  local commit_message="This is for my ${os_type} git push or pull at $riqi. Last changed file: $filename"

  git add .
  if [ $? -ne 0 ]; then
    echo "Failed to add changes."
    exit 1
  fi

  git commit -m "$commit_message"
  if [ $? -ne 0 ]; then
    echo "Failed to commit changes."
    exit 1
  fi

  git push
  if [ $? -ne 0 ]; then
    echo "Failed to push changes."
    exit 1
  fi

  echo "Changes added, committed, and pushed successfully."
}

# 主脚本逻辑
main() {
  local os_type=$(get_os_type)
  echo "OS Type: $os_type"

  local changed_files=$(git diff --name-only HEAD)

  if [ -n "$changed_files" ]; then
    for file in $changed_files; do
      local full_path=$(pwd)/$file
      run_replace_script "$full_path"
    done
  else
    echo "No changes to commit."
    exit 0
  fi

  commit_and_push_changes "$os_type"
}

# 执行主脚本逻辑
main

