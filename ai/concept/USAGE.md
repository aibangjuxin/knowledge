# 知识库检索工具使用指南

## 快速开始

### 1. 安装依赖（首次使用）

```bash
cd /Users/lex/git/knowledge/ai/concept
conda install -y requests  # 如果使用 conda
# 或
pip3 install --user requests  # 如果使用系统 Python
```

### 2. 设置别名（推荐）

编辑 `~/.zshrc` 或 `~/.bashrc`，添加：

```bash
# 知识库检索工具
alias kbq='/Users/lex/git/knowledge/ai/concept/kbq'
alias kbs='/Users/lex/git/knowledge/ai/concept/kbs'
```

然后运行：

```bash
source ~/.zshrc  # 或 source ~/.bashrc
```

### 3. 开始使用

```bash
# 快速检索（推荐，速度快）
kbq nginx proxy_pass

# AI 智能检索（需要等待 AI 响应）
kbs "GKE architecture" --model qwen3.5:0.8b
```

## 工具对比

| 工具 | 速度 | AI 总结 | 适用场景 |
|------|------|---------|----------|
| `kbq` (kb_quick.py) | ⚡️ 快 | ❌ 无 | 日常快速查找，查看文件列表 |
| `kbs` (kb_search.py) | 🐌 慢 | ✅ 有 | 需要概念性总结和深度分析 |
| `kb_search.sh` | ⚡️ 快 | ❌ 无 | 简单搜索，查看原始结果 |

## 使用示例

### 场景 1: 快速查找相关文件

```bash
# 我想找关于 nginx proxy_pass 的文档
kbq "nginx proxy_pass"

# 输出会显示：
# - 找到多少条匹配
# - 哪些文件包含这个关键词
# - 每个文件的匹配内容预览
# - 主题分类
# - 推荐阅读的文件
# - 相关搜索建议
```

### 场景 2: 深入理解某个概念

```bash
# 我想深入理解 GKE ingress 的概念
kbs "GKE ingress" --model qwen3.5:0.8b

# AI 会分析搜索结果并提供：
# - 核心概念总结
# - 关键知识点
# - 推荐阅读文件
# - 相关主题建议
```

### 场景 3: 搜索特定主题

```bash
# 搜索 Kong Gateway 相关内容
kbq kong gateway --max 20

# 搜索 Istio 配置
kbq istio virtualservice

# 搜索 SSL 证书相关
kbq "SSL certificate"
```

### 场景 4: 探索新领域

```bash
# 第一步：快速了解有哪些相关文档
kbq "cloud armor"

# 第二步：根据推荐的文件，深入阅读
# 比如输出推荐了 gcp/cloud-armor/docs/setup.md
cat /Users/lex/git/knowledge/gcp/cloud-armor/docs/setup.md

# 第三步：如果需要概念性总结
kbs "cloud armor" --model qwen3.5:0.8b
```

## 高级用法

### 1. 限制搜索结果数量

```bash
# 只显示前 10 条匹配
kbq kubernetes --max 10

# 显示更多结果
kbq nginx --max 50
```

### 2. 选择不同的 AI 模型

```bash
# 列出可用模型
kbs --list-models

# 使用最快的模型（推荐）
kbs "topic" --model qwen3.5:0.8b

# 使用更强大的模型（较慢）
kbs "topic" --model gemma4:e4b

# 使用默认模型
kbs "topic"
```

### 3. 只搜索不使用 AI

```bash
# 使用 kb_search.py 但不调用 AI
kbs "nginx" --no-ai
```

### 4. 组合使用

```bash
# 先快速查找
kbq "GKE networking"

# 如果需要更深入的理解，再使用 AI
kbs "GKE networking" --model qwen3.5:0.8b

# 打开推荐的文件阅读
code /Users/lex/git/knowledge/gcp/network/vpc-peering.md
```

## 工作流建议

### 日常查找工作流

```
1. 使用 kbq 快速搜索
   ↓
2. 查看文件列表和分类
   ↓
3. 打开推荐的文件深入阅读
   ↓
4. 如果需要，使用相关搜索建议继续探索
```

### 学习新概念工作流

```
1. 使用 kbq 快速了解有哪些相关文档
   ↓
2. 使用 kbs 获取 AI 概念性总结
   ↓
3. 根据推荐文件深入学习
   ↓
4. 使用相关主题建议扩展知识面
```

### 解决问题工作流

```
1. 使用 kbq 搜索问题关键词
   ↓
2. 查看匹配内容预览，快速定位相关文档
   ↓
3. 打开相关文件查找解决方案
   ↓
4. 如果需要，搜索相关主题获取更多信息
```

## 常见问题

### Q: AI 响应太慢怎么办？

A: 
1. 使用 `kbq` 代替 `kbs`，不使用 AI
2. 使用更快的模型：`--model qwen3.5:0.8b`
3. 使用 `--no-ai` 选项：`kbs "topic" --no-ai`

### Q: 搜索结果太多怎么办？

A:
1. 使用更具体的关键词
2. 限制结果数量：`--max 10`
3. 使用引号搜索精确短语：`kbq "exact phrase"`

### Q: 找不到想要的内容？

A:
1. 尝试不同的关键词
2. 使用更宽泛的搜索词
3. 查看"相关搜索"建议
4. 检查主题分类，可能在其他目录

### Q: Ollama 连接失败？

A:
```bash
# 检查 Ollama 是否运行
curl http://localhost:11434/api/tags

# 如果没有运行，启动 Ollama
ollama serve

# 或者使用 --no-ai 选项
kbs "topic" --no-ai
```

### Q: 如何搜索多个关键词？

A:
```bash
# 搜索包含所有关键词的内容
kbq "nginx AND proxy_pass"

# 或者直接用空格分隔
kbq nginx proxy_pass

# 搜索精确短语
kbq "GKE ingress controller"
```

## 性能优化建议

1. **日常使用优先 kbq**: 速度快，结果清晰
2. **AI 总结按需使用**: 只在需要概念性理解时使用
3. **选择合适的模型**: 
   - 快速查询：qwen3.5:0.8b
   - 平衡选择：qwen3.5:4b (默认)
   - 深度分析：gemma4:e4b
4. **限制结果数量**: 使用 `--max` 参数控制输出

## 扩展阅读

- [README.md](README.md) - 完整文档
- [kb_search.py](kb_search.py) - Python 源码
- [kb_quick.py](kb_quick.py) - 快速检索源码

## 反馈和改进

如果你有任何建议或发现问题，可以：
1. 修改脚本源码
2. 调整配置参数
3. 添加新功能

祝你使用愉快！🚀
