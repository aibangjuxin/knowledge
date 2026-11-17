#!/bin/bash
# 安装依赖和设置别名

echo "🔧 安装 Python 依赖..."
pip3 install requests

echo ""
echo "✅ 依赖安装完成！"
echo ""
echo "📝 建议添加以下别名到你的 shell 配置文件 (~/.bashrc 或 ~/.zshrc):"
echo ""
echo "alias kbs='python3 /Users/lex/git/knowledge/ai/concept/kb_search.py'"
echo "alias kbq='/Users/lex/git/knowledge/ai/concept/kb_search.sh'"
echo ""
echo "然后运行: source ~/.bashrc  或  source ~/.zshrc"
echo ""
echo "🚀 快速测试:"
echo "  python3 /Users/lex/git/knowledge/ai/concept/kb_search.py ollama --max 5"
