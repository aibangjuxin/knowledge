# 🍎 Apple Notes CLI 工具

这是一个强大的 Apple Notes 命令行工具，让你可以通过终端操作 macOS 的 Notes 应用。它使用 Node.js 和 AppleScript 来与 Apple Notes 无缝交互。

## 🔍 功能特性

### 核心功能
- **🔍 搜索笔记** - 按标题或内容快速搜索
- **📝 创建笔记** - 新建笔记，支持标题和内容
- **📄 从文件创建** - 直接从文件内容创建笔记
- **✏️ 编辑笔记** - 修改现有笔记内容
- **📋 列出笔记** - 显示笔记列表，支持限制数量
- **👀 查看内容** - 获取特定笔记的完整内容
- **📤 导出笔记** - 将笔记内容保存为文件
- **🗑️ 删除笔记** - 安全删除笔记（带确认）

### 增强特性
- **短命令别名** - 支持 `s`, `c`, `l`, `g`, `e`, `d` 等快捷命令
- **智能显示** - 带表情符号和格式化的清晰输出
- **文件集成** - 与文件系统无缝集成
- **安全操作** - 删除操作需要确认

## 🚀 快速开始

### 1. 环境准备

```bash
# 确保你有 Node.js (本工具使用 Homebrew 安装的 Node.js)
node --version

# 给脚本添加执行权限
chmod +x notes-enhanced

# 测试脚本是否工作
./notes-enhanced
```

### 2. 权限设置

首次运行时，macOS 会要求授权：

1. **系统偏好设置** → **安全性与隐私** → **隐私** → **自动化**
2. 找到 **Terminal** 或你使用的终端应用
3. 确保允许它控制 **Notes** 应用

## 📖 使用指南

### 基本命令格式

```bash
./notes-enhanced <command> [arguments]
```

### 命令详解

#### 🔍 搜索笔记
```bash
# 搜索包含特定关键词的笔记
./notes-enhanced search "关键词"
./notes-enhanced s "GCP"          # 使用短命令

# 示例输出：
# 🔍 Search Results:
# 1. GCP 学习笔记
# 2. VPC 架构设计
# 
# ✨ Found 2 note(s) containing "GCP"
```

#### 📝 创建笔记
```bash
# 创建带内容的笔记
./notes-enhanced create "笔记标题" "笔记内容"
./notes-enhanced c "会议记录" "今天讨论了项目进度"

# 创建空笔记
./notes-enhanced create "待办事项"
```

#### 📄 从文件创建笔记
```bash
# 从 Markdown 文件创建笔记
./notes-enhanced create-from-file "VPC 分析" ../logs/vpc-claude.md
./notes-enhanced cf "代码片段" ./script.js

# 支持的文件类型：.md, .txt, .js, .py, .json 等文本文件
```

#### 📋 列出笔记
```bash
# 列出最近的 20 条笔记（默认）
./notes-enhanced list
./notes-enhanced l

# 指定显示数量
./notes-enhanced list 10
./notes-enhanced l 5

# 示例输出：
# 📝 Recent Notes (showing up to 10):
# 1. 会议记录 | Monday, October 9, 2025 at 2:30:45 PM
#    Modified: Monday, October 9, 2025 at 2:30:45 PM
# 
# 2. VPC 学习笔记 | Sunday, October 8, 2025 at 10:15:22 AM
#    Modified: Sunday, October 8, 2025 at 10:15:22 AM
```

#### 👀 查看笔记内容
```bash
# 查看特定笔记的完整内容
./notes-enhanced get "笔记标题"
./notes-enhanced g "会议记录"

# 示例输出：
# 📄 Content of "会议记录":
# ──────────────────────────────────────────────────────
# 今天讨论了项目进度，主要议题包括：
# 1. VPC 架构优化
# 2. 日志分析工具开发
# ──────────────────────────────────────────────────────
```

#### ✏️ 编辑笔记
```bash
# 替换笔记内容
./notes-enhanced edit "笔记标题" "新的内容"
./notes-enhanced edit "会议记录" "更新：添加了新的讨论要点"
```

#### 📤 导出笔记
```bash
# 导出笔记到文件
./notes-enhanced export "笔记标题" ./output.md
./notes-enhanced e "VPC 分析" ./vpc-analysis.txt

# 成功输出：
# ✅ Note exported to: ./vpc-analysis.txt
```

#### 🗑️ 删除笔记
```bash
# 删除笔记（需要确认）
./notes-enhanced delete "笔记标题"
./notes-enhanced d "旧笔记"

# 会提示确认：
# ⚠️  Delete "旧笔记"? (y/N)
```

## 🎯 实际使用场景

### 开发者工作流

```bash
# 1. 从代码文件创建笔记
./notes-enhanced cf "API 接口设计" ./api-spec.json

# 2. 搜索相关技术笔记
./notes-enhanced s "API"

# 3. 快速记录想法
./notes-enhanced c "Bug 修复思路" "需要检查数据库连接池配置"

# 4. 导出笔记用于文档
./notes-enhanced e "API 接口设计" ./docs/api-design.md
```

### 学习笔记管理

```bash
# 1. 从学习资料创建笔记
./notes-enhanced cf "GCP VPC 概念" ./vpc-learning.md

# 2. 定期查看学习进度
./notes-enhanced l 20

# 3. 搜索特定主题
./notes-enhanced s "Interconnect"

# 4. 更新学习笔记
./notes-enhanced edit "GCP VPC 概念" "新增：Shared VPC 的权限管理"
```

### 会议记录

```bash
# 1. 快速创建会议记录
./notes-enhanced c "$(date '+%Y-%m-%d') 团队会议" "参会人员：张三、李四"

# 2. 会后更新内容
./notes-enhanced edit "2025-10-09 团队会议" "决议：下周完成 VPC 迁移"

# 3. 导出会议纪要
./notes-enhanced e "2025-10-09 团队会议" ./meeting-minutes.txt
```

## 🛠️ 高级用法

### 创建全局命令

```bash
# 创建软链接到系统 PATH
sudo ln -s $(pwd)/notes-enhanced /usr/local/bin/notes

# 现在可以在任何地方使用
notes s "关键词"
notes c "新笔记" "内容"
```

### 添加到 Shell 别名

在 `~/.zshrc` 中添加：

```bash
alias n='/path/to/your/notes-enhanced'
alias ns='n search'
alias nc='n create'
alias nl='n list'
alias ng='n get'
```

重新加载配置：
```bash
source ~/.zshrc
```

使用别名：
```bash
ns "GCP"              # 搜索
nc "新想法" "内容"     # 创建
nl 10                 # 列出
ng "笔记标题"         # 查看
```

## ⚠️ 注意事项

### 权限问题
- 首次运行需要授权终端访问 Notes 应用
- 如果遇到权限错误，检查 **系统偏好设置** → **安全性与隐私** → **隐私** → **自动化**

### 特殊字符处理
- 笔记标题和内容中的引号会被自动转义
- 支持多行内容和特殊字符
- 文件导入时会保持原始格式

### 性能考虑
- 大量笔记时搜索可能较慢
- 建议使用 `list` 命令的限制参数
- 长内容的笔记显示可能需要滚动

## 🔧 故障排除

### 常见问题

1. **"Command not found" 错误**
   ```bash
   # 检查 Node.js 路径
   which node
   # 更新脚本第一行的路径
   ```

2. **AppleScript 权限错误**
   ```bash
   # 重新授权
   # 系统偏好设置 → 安全性与隐私 → 隐私 → 自动化
   ```

3. **笔记未找到**
   ```bash
   # 检查笔记标题是否完全匹配
   ./notes-enhanced list | grep "关键词"
   ```

## 📝 版本信息

- **当前版本**: Enhanced v1.0
- **Node.js 要求**: v12.0+
- **系统要求**: macOS 10.14+
- **依赖**: 无额外依赖，仅使用 Node.js 内置模块

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个工具！

---

*这个工具特别适合开发者、学生、研究人员等需要在命令行环境中快速管理笔记的用户。*

1 change accepted
(
View all
)
