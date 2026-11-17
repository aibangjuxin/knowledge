#!/bin/bash
# 快速知识库搜索脚本 (不使用 AI)

KNOWLEDGE_BASE="/Users/lex/git/knowledge"
RG_PATH="/opt/homebrew/bin/rg"

if [ $# -eq 0 ]; then
    echo "用法: $0 <关键词> [选项]"
    echo ""
    echo "示例:"
    echo "  $0 nginx"
    echo "  $0 'GKE ingress'"
    echo "  $0 ollama -A 2 -B 2  # 显示上下文"
    exit 1
fi

KEYWORD="$1"
shift  # 移除第一个参数，剩余的作为 rg 选项

echo "🔍 搜索关键词: $KEYWORD"
echo "📁 知识库: $KNOWLEDGE_BASE"
echo ""

# 使用 ripgrep 搜索
$RG_PATH \
    --ignore-case \
    --type md \
    --heading \
    --line-number \
    --color always \
    --max-count 10 \
    "$@" \
    "$KEYWORD" \
    "$KNOWLEDGE_BASE" | less -R

echo ""
echo "提示: 使用 kb_search.py 获取 AI 总结"
