#!/bin/bash

echo "最近20次提交的文件改动统计："
echo "----------------------------------------"

# 获取最近20次提交的哈希值
commits=$(git log -20 --pretty=format:"%h")

for commit in $commits; do
    echo "提交: $(git log -1 --pretty=format:"%h - %s (%cr)" $commit)"
    echo "修改的文件:"
    git show --stat --oneline $commit | tail -n +2
    echo "----------------------------------------"
done