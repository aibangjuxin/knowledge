# 本地知识库智能检索系统

## 概述

这是一个本地知识库检索工具，结合了 ripgrep 的快速搜索能力和 Ollama AI 的智能总结功能。

## 快速开始

```bash
# 推荐：快速检索（无 AI，速度快）
./kbq "nginx proxy_pass"

# 完整版：带 AI 总结（需要等待）
./kbs "GKE architecture" --model qwen3.5:0.8b
```

## 工具说明

### 1. kb_quick.py (推荐) - 快速检索工具

快速搜索工具，不使用 AI，提供智能化的结果展示。

**特性:**
- 使用 ripgrep 快速搜索
- 按文件分组显示结果
- 自动分类和推荐相关文件
- 建议相关搜索关键词
- 无需等待 AI 响应

**使用方法:**

```bash
# 基本搜索
./kbq nginx proxy_pass

# 或使用 Python 直接调用
python kb_quick.py "GKE ingress"

# 指定最大结果数
./kbq kubernetes --max 50
```

### 2. kb_search.py - AI 智能检索工具

功能完整的检索工具，包含 AI 总结功能（响应较慢）。

**特性:**
- 使用 ripgrep 快速搜索 Markdown 文件
- 调用本地 Ollama AI 生成概念性总结
- 提供关键知识点和进一步探索方向
- 支持多种 Ollama 模型

**使用方法:**

```bash
# 基本搜索
python3 kb_search.py nginx proxy_pass

# 指定最大结果数
python3 kb_search.py "GKE ingress" --max 30

# 使用不同的 AI 模型
python3 kb_search.py ollama --model gemma3:4b

# 只搜索，不使用 AI 总结
python3 kb_search.py kubernetes --no-ai

# 列出可用的 Ollama 模型
python3 kb_search.py --list-models
```

### 2. kb_search.sh - Shell 快速检索工具

轻量级搜索脚本，不使用 AI，适合快速查找。

**使用方法:**

```bash
# 基本搜索
./kb_search.sh nginx

# 带上下文搜索
./kb_search.sh "GKE ingress" -A 2 -B 2

# 搜索特定类型文件
./kb_search.sh ollama --type-add 'yaml:*.yaml' --type yaml
```

## 安装依赖

### Python 依赖

```bash
pip3 install requests
```

### 系统依赖

- ripgrep: 已安装在 `/opt/homebrew/bin/rg`
- Ollama: 运行在 `http://localhost:11434`

## 配置

编辑脚本顶部的配置变量：

```python
KNOWLEDGE_BASE = "/Users/lex/git/knowledge"  # 知识库路径
RG_PATH = "/opt/homebrew/bin/rg"             # ripgrep 路径
OLLAMA_API = "http://localhost:11434/api/generate"  # Ollama API
DEFAULT_MODEL = "qwen3.5:4b"                 # 默认 AI 模型
```

## 推荐的 Ollama 模型

根据你的本地模型，推荐使用：

- **qwen3.5:4b** - 平衡速度和质量（默认）
- **gemma3:4b** - Google 模型，效果好
- **gemma4:e4b** - 最新版本，更强大
- **qwen3.5:0.8b** - 最快，适合快速查询

## 工作流程

1. **搜索阶段**: 使用 ripgrep 在知识库中搜索关键词
2. **结果整理**: 按文件分组，提取相关内容
3. **AI 分析**: 调用 Ollama 生成概念性总结
4. **输出结果**: 
   - 核心概念总结
   - 关键知识点列表
   - 相关文件推荐
   - 进一步探索方向

## 示例输出

### kb_quick.py 输出示例（推荐）

```
======================================================================
🔍 搜索: nginx proxy_pass
📊 找到 20 条匹配，分布在 11 个文件中
======================================================================

📁 相关文件:

 1. linux/docs/curl-and-nginx-proxy.md (4 条匹配)
 2. nginx/docs/proxy-pass/nginx-proxy-pass-usersgent.md (1 条匹配)
 3. ssl/docs/claude/routeaction/ssl-terminal-2.md (2 条匹配)
 ...

======================================================================
📝 匹配内容预览:

▶ linux/docs/curl-and-nginx-proxy.md
----------------------------------------------------------------------
  行    1: # nginx proxy_pass 和curl 直接proxy 的区别是什么？
  行   60: ## Nginx proxy_pass和http proxy Tunnel有什么区别?
  ...

======================================================================
💡 建议:

  主题分类:
    • nginx: 3 个文件
    • ssl: 4 个文件
    • linux: 2 个文件

  推荐深入阅读:
    • linux/docs/curl-and-nginx-proxy.md (4 条匹配)
    • nginx/docs/proxy-pass/nginx-proxy-pass-usersgent.md (1 条匹配)

  相关搜索:
    • upstream
    • location
    • server

======================================================================
```

### kb_search.py 输出示例（带 AI）

```
🔍 搜索关键词: nginx proxy_pass
📁 知识库路径: /Users/lex/git/knowledge
🤖 AI 模型: qwen3.5:0.8b

找到 15 条匹配，分布在 5 个文件中
...

============================================================
🤖 AI 正在分析搜索结果...
============================================================

1. 核心概念
nginx proxy_pass 是反向代理的核心指令，用于将请求转发到后端服务...

2. 关键点
- proxy_pass 语法和配置方式
- 与 upstream 的配合使用
- User-Agent 头信息处理

3. 推荐文件
- linux/docs/curl-and-nginx-proxy.md
- nginx/docs/proxy-pass/nginx-proxy-pass-usersgent.md

4. 相关主题
- nginx upstream
- nginx load balancing

============================================================
✅ 完成！共找到 15 条匹配
============================================================
```

## 高级用法

### 创建别名

在 `~/.bashrc` 或 `~/.zshrc` 中添加：

```bash
# 快速检索（推荐）
alias kbq='/Users/lex/git/knowledge/ai/concept/kbq'

# AI 智能检索
alias kbs='/Users/lex/git/knowledge/ai/concept/kbs'

# Shell 快速检索
alias kbsh='/Users/lex/git/knowledge/ai/concept/kb_search.sh'
```

然后运行 `source ~/.zshrc` 或 `source ~/.bashrc`，就可以直接使用：

```bash
# 日常使用推荐
kbq nginx proxy_pass

# 需要 AI 总结时
kbs "GKE architecture" --model qwen3.5:0.8b

# 简单搜索
kbsh kubernetes
```

### 集成到工作流

```bash
# 搜索并保存结果
kbs "GKE architecture" > gke_research.md

# 批量搜索
for topic in nginx kong istio; do
    echo "=== $topic ===" >> research.md
    kbs "$topic" --no-ai >> research.md
done
```

## 故障排查

### Ollama 连接失败

```bash
# 检查 Ollama 是否运行
curl http://localhost:11434/api/tags

# 启动 Ollama
ollama serve
```

### ripgrep 未找到

```bash
# 检查路径
which rg

# 如果路径不同，更新脚本中的 RG_PATH
```

### 搜索结果为空

- 确认知识库路径正确
- 检查是否有 .md 文件
- 尝试更宽泛的关键词

## 扩展建议

1. **添加更多文件类型**: 修改 `--type` 参数支持 yaml, json 等
2. **语义搜索**: 集成向量数据库实现语义检索
3. **Web 界面**: 使用 Flask/FastAPI 创建 Web UI
4. **缓存机制**: 缓存常见查询的 AI 总结
5. **多语言支持**: 支持英文知识库和双语输出

## 许可

MIT License
