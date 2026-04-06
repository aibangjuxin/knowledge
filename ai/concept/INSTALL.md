# 安装指南

## 系统要求

- macOS (已测试)
- Python 3.x (conda 或系统 Python)
- ripgrep (已安装在 `/opt/homebrew/bin/rg`)
- Ollama (可选，用于 AI 功能)

## 快速安装

### 1. 安装 Python 依赖

```bash
# 如果使用 conda (推荐)
conda install -y requests

# 如果使用系统 Python
pip3 install --user requests
```

### 2. 设置别名

编辑 `~/.zshrc` (如果使用 zsh) 或 `~/.bashrc` (如果使用 bash):

```bash
# 添加以下行
alias kbq='/Users/lex/git/knowledge/ai/concept/kbq'
alias kbs='/Users/lex/git/knowledge/ai/concept/kbs'
```

保存后运行：

```bash
source ~/.zshrc  # 或 source ~/.bashrc
```

### 3. 验证安装

```bash
# 测试快速检索
kbq ollama --max 5

# 测试 AI 检索（可选）
kbs --list-models
```

## 详细安装步骤

### 步骤 1: 检查依赖

```bash
# 检查 Python
python --version
# 或
python3 --version

# 检查 ripgrep
/opt/homebrew/bin/rg --version

# 检查 Ollama (可选)
curl http://localhost:11434/api/tags
```

### 步骤 2: 安装 Python 包

#### 方法 A: 使用 conda (推荐)

```bash
conda install -y requests
```

#### 方法 B: 使用 pip

```bash
pip3 install --user requests
```

#### 方法 C: 使用虚拟环境

```bash
cd /Users/lex/git/knowledge/ai/concept
python3 -m venv venv
source venv/bin/activate
pip install requests
```

### 步骤 3: 配置工具

所有配置都在脚本顶部，可以根据需要修改：

#### kb_search.py 配置

```python
KNOWLEDGE_BASE = "/Users/lex/git/knowledge"  # 知识库路径
RG_PATH = "/opt/homebrew/bin/rg"             # ripgrep 路径
OLLAMA_API = "http://localhost:11434/api/generate"  # Ollama API
DEFAULT_MODEL = "qwen3.5:4b"                 # 默认 AI 模型
```

#### kb_quick.py 配置

```python
KNOWLEDGE_BASE = "/Users/lex/git/knowledge"  # 知识库路径
RG_PATH = "/opt/homebrew/bin/rg"             # ripgrep 路径
```

### 步骤 4: 设置别名

#### 临时别名（当前会话）

```bash
alias kbq='/Users/lex/git/knowledge/ai/concept/kbq'
alias kbs='/Users/lex/git/knowledge/ai/concept/kbs'
```

#### 永久别名（推荐）

编辑 shell 配置文件：

```bash
# 对于 zsh (macOS 默认)
nano ~/.zshrc

# 对于 bash
nano ~/.bashrc
```

添加以下内容：

```bash
# 知识库检索工具
alias kbq='/Users/lex/git/knowledge/ai/concept/kbq'
alias kbs='/Users/lex/git/knowledge/ai/concept/kbs'
```

保存并重新加载：

```bash
source ~/.zshrc  # 或 source ~/.bashrc
```

### 步骤 5: 测试安装

```bash
# 测试快速检索
kbq nginx --max 5

# 测试 AI 功能（如果安装了 Ollama）
kbs --list-models

# 测试 AI 搜索
kbs ollama --max 5 --model qwen3.5:0.8b
```

## 可选：安装 Ollama

如果你想使用 AI 总结功能，需要安装 Ollama：

### 1. 下载安装 Ollama

访问 https://ollama.ai 下载 macOS 版本

### 2. 安装模型

```bash
# 安装推荐的快速模型
ollama pull qwen3.5:0.8b

# 安装默认模型
ollama pull qwen3.5:4b

# 安装更强大的模型
ollama pull gemma4:e4b
```

### 3. 启动 Ollama

```bash
# Ollama 通常会自动启动
# 如果没有，手动启动：
ollama serve
```

### 4. 验证 Ollama

```bash
# 检查 Ollama 是否运行
curl http://localhost:11434/api/tags

# 列出已安装的模型
ollama list
```

## 故障排查

### 问题 1: Python 找不到 requests 模块

```bash
# 检查 Python 路径
which python
which python3

# 确保使用正确的 Python 安装 requests
# 如果使用 conda:
conda install -y requests

# 如果使用系统 Python:
pip3 install --user requests
```

### 问题 2: 权限错误

```bash
# 确保脚本有执行权限
chmod +x /Users/lex/git/knowledge/ai/concept/kbq
chmod +x /Users/lex/git/knowledge/ai/concept/kbs
chmod +x /Users/lex/git/knowledge/ai/concept/kb_quick.py
chmod +x /Users/lex/git/knowledge/ai/concept/kb_search.py
```

### 问题 3: ripgrep 未找到

```bash
# 检查 ripgrep 路径
which rg

# 如果路径不同，更新脚本中的 RG_PATH
# 或者安装 ripgrep:
brew install ripgrep
```

### 问题 4: Ollama 连接失败

```bash
# 检查 Ollama 是否运行
ps aux | grep ollama

# 启动 Ollama
ollama serve

# 或者使用 --no-ai 选项
kbs "topic" --no-ai
```

### 问题 5: 别名不生效

```bash
# 检查别名是否设置
alias | grep kb

# 重新加载配置
source ~/.zshrc  # 或 source ~/.bashrc

# 或者直接使用完整路径
/Users/lex/git/knowledge/ai/concept/kbq nginx
```

## 卸载

如果需要卸载：

```bash
# 1. 删除别名（从 ~/.zshrc 或 ~/.bashrc 中移除）

# 2. 删除文件
rm -rf /Users/lex/git/knowledge/ai/concept

# 3. 卸载 Python 包（可选）
pip3 uninstall requests
```

## 更新

```bash
# 如果脚本有更新，只需替换文件即可
# 别名和配置会自动生效
```

## 下一步

安装完成后，查看：
- [USAGE.md](USAGE.md) - 使用指南
- [README.md](README.md) - 完整文档

开始使用：

```bash
kbq nginx proxy_pass
```

祝你使用愉快！🎉
