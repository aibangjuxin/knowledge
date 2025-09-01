# Merge Shell Scripts 使用说明

## 功能描述
这个脚本可以将当前目录下的所有 `.sh` 文件合并到一个 Markdown 文件中，方便查看和管理。

## 安装步骤

1. **脚本已创建**: `test-merge.sh` (推荐使用这个版本，兼容性更好)
2. **已添加 alias**: 在 `~/.zshrc` 中添加了 `merge` 命令
3. **重新加载配置**: 在新的 zsh 终端中运行 `source ~/.zshrc`

## 使用方法

### 方法一：直接运行脚本
```bash
cd /path/to/your/scripts
/Users/lex/git/knowledge/test-merge.sh
```

### 方法二：使用 alias (推荐)
```bash
cd /path/to/your/scripts
merge
```

## 交互流程

1. **检查文件**: 脚本会自动检查当前目录下的 `.sh` 文件
2. **显示列表**: 显示找到的所有 `.sh` 文件
3. **输入文件名**: 提示输入输出文件名 (默认: `merged-scripts.md`)
4. **确认操作**: 询问是否继续执行
5. **生成文件**: 创建包含所有脚本内容的 Markdown 文件

## 输出格式

生成的 Markdown 文件包含：
- 标题和生成时间
- 当前目录路径
- 每个脚本文件的内容，格式化为代码块

## 示例输出

```markdown
# Shell Scripts Collection

Generated on: 2025-09-01 14:42:30
Directory: /Users/lex/git/knowledge

## `git.sh`

\`\`\`bash
#!/bin/bash
# Git operations script
...
\`\`\`

## `merge.sh`

\`\`\`bash
#!/bin/bash
# Merge scripts
...
\`\`\`
```

## 注意事项

- 脚本只处理 `.sh` 扩展名的文件
- 如果当前目录没有 `.sh` 文件，脚本会提示并退出
- 输出文件会自动添加 `.md` 扩展名
- 如果输出文件已存在，会被覆盖

## 自定义

你可以修改脚本来支持其他文件类型，只需要更改脚本中的 `*.sh` 为其他模式，比如：
- `*.py` - Python 文件
- `*.js` - JavaScript 文件  
- `*.txt` - 文本文件
```bash
{ for file in \*.sh; do echo "## \`$file\`"; echo; echo '```bash'; cat "$file"; echo; echo '```'; echo; done; } > script.md
```