#!/bin/bash
# 知识库检索系统演示脚本

echo "======================================================================"
echo "  本地知识库智能检索系统 - 演示"
echo "======================================================================"
echo ""

# 检查依赖
echo "1️⃣  检查依赖..."
echo ""

echo "检查 Python..."
python --version || python3 --version

echo ""
echo "检查 ripgrep..."
/opt/homebrew/bin/rg --version | head -1

echo ""
echo "检查 Ollama (可选)..."
curl -s http://localhost:11434/api/tags > /dev/null && echo "✓ Ollama 运行中" || echo "✗ Ollama 未运行（AI 功能不可用）"

echo ""
echo "======================================================================"
echo ""

# 演示快速检索
echo "2️⃣  演示快速检索 (kbq)"
echo ""
echo "命令: ./kbq ollama --max 3"
echo ""
./kbq ollama --max 3

echo ""
echo "======================================================================"
echo ""

# 演示搜索不同主题
echo "3️⃣  演示搜索不同主题"
echo ""
echo "命令: ./kbq nginx --max 5"
echo ""
./kbq nginx --max 5

echo ""
echo "======================================================================"
echo ""

# 显示帮助
echo "4️⃣  可用命令"
echo ""
echo "快速检索（推荐）:"
echo "  ./kbq <关键词>"
echo "  ./kbq <关键词> --max 10"
echo ""
echo "AI 智能检索:"
echo "  ./kbs <关键词> --model qwen3.5:0.8b"
echo "  ./kbs --list-models"
echo "  ./kbs <关键词> --no-ai"
echo ""
echo "Shell 快速检索:"
echo "  ./kb_search.sh <关键词>"
echo ""

echo "======================================================================"
echo ""

# 显示文档
echo "5️⃣  文档"
echo ""
echo "  QUICKSTART.md  - 5 分钟快速开始"
echo "  USAGE.md       - 详细使用指南"
echo "  INSTALL.md     - 安装步骤"
echo "  README.md      - 完整文档"
echo ""

echo "======================================================================"
echo ""

# 显示别名设置
echo "6️⃣  设置别名（推荐）"
echo ""
echo "在 ~/.zshrc 或 ~/.bashrc 中添加:"
echo ""
echo "  alias kbq='/Users/lex/git/knowledge/ai/concept/kbq'"
echo "  alias kbs='/Users/lex/git/knowledge/ai/concept/kbs'"
echo ""
echo "然后运行: source ~/.zshrc"
echo ""

echo "======================================================================"
echo ""
echo "演示完成！开始使用: ./kbq <关键词>"
echo ""
echo "======================================================================"
