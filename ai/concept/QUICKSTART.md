# 快速开始指南

## 5 分钟上手

### 1. 安装依赖（30 秒）

```bash
conda install -y requests
```

### 2. 设置别名（1 分钟）

```bash
# 编辑配置文件
nano ~/.zshrc

# 添加这两行
alias kbq='/Users/lex/git/knowledge/ai/concept/kbq'
alias kbs='/Users/lex/git/knowledge/ai/concept/kbs'

# 保存后重新加载
source ~/.zshrc
```

### 3. 开始使用（3 分钟）

```bash
# 搜索 nginx 相关内容
kbq nginx

# 搜索 GKE ingress
kbq "GKE ingress"

# 搜索 Kong Gateway
kbq kong gateway
```

## 核心命令

```bash
# 快速检索（推荐，日常使用）
kbq <关键词>

# AI 智能检索（需要概念性总结时）
kbs <关键词> --model qwen3.5:0.8b
```

## 实际例子

### 例子 1: 查找 nginx proxy_pass 配置

```bash
$ kbq "nginx proxy_pass"

# 输出会显示：
# ✓ 找到 20 条匹配，分布在 11 个文件中
# ✓ 相关文件列表
# ✓ 匹配内容预览
# ✓ 推荐阅读的文件
# ✓ 相关搜索建议
```

### 例子 2: 了解 GKE ingress

```bash
$ kbq "GKE ingress" --max 10

# 快速查看有哪些相关文档
# 然后打开推荐的文件深入阅读
```

### 例子 3: 探索新主题

```bash
# 第一步：快速搜索
$ kbq "cloud armor"

# 第二步：查看推荐文件
# 比如: gcp/cloud-armor/docs/setup.md

# 第三步：打开文件阅读
$ cat /Users/lex/git/knowledge/gcp/cloud-armor/docs/setup.md
```

## 常用选项

```bash
# 限制结果数量
kbq nginx --max 10

# 列出可用的 AI 模型
kbs --list-models

# 使用 AI 总结（较慢）
kbs "topic" --model qwen3.5:0.8b

# 只搜索不用 AI
kbs "topic" --no-ai
```

## 工作流建议

### 日常查找

```
kbq <关键词> → 查看文件列表 → 打开推荐文件阅读
```

### 学习新概念

```
kbq <概念> → 了解相关文档 → kbs <概念> 获取 AI 总结 → 深入阅读
```

### 解决问题

```
kbq <问题关键词> → 查看匹配内容 → 找到解决方案
```

## 下一步

- 查看 [USAGE.md](USAGE.md) 了解更多使用技巧
- 查看 [README.md](README.md) 了解完整功能
- 查看 [INSTALL.md](INSTALL.md) 了解详细安装步骤

## 需要帮助？

```bash
# 查看帮助
kbq --help
kbs --help

# 测试是否正常工作
kbq ollama --max 5
```

开始探索你的知识库吧！🚀
