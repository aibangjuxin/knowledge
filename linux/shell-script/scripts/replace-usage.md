# 批量替换脚本使用说明

## 脚本位置
- 脚本文件: `/Users/lex/git/knowledge/shell-script/scripts/replace.sh`
- 示例规则文件: `/Users/lex/replace.txt`

## 添加到 .zshrc

在你的 `~/.zshrc` 文件中添加以下行:

```bash
alias rp="/Users/lex/git/knowledge/shell-script/scripts/replace.sh"
```

然后执行 `source ~/.zshrc` 使别名生效。

## 功能特性

✅ **支持多种分隔符**: 制表符或空格分隔  
✅ **预览模式**: 使用 `-p` 参数预览将要执行的替换  
✅ **自动排除**: 自动排除 `.git`, `node_modules`, `__pycache__` 等目录  
✅ **跨平台**: 自动检测 macOS/Linux 并使用正确的 sed 命令  
✅ **彩色输出**: 使用颜色区分不同类型的信息  
✅ **错误处理**: 完善的参数检查和错误提示

## 使用方法

### 基本用法

```bash
# 使用规则文件替换当前目录
rp -f /Users/lex/replace.txt

# 指定目标目录
rp -f /Users/lex/replace.txt -d /path/to/project

# 预览模式(不实际执行替换)
rp -f /Users/lex/replace.txt -p

# 显示帮助信息
rp -h
```

## 替换规则文件格式

规则文件每行包含两列,用**空格**或**制表符**分隔:

```
原始内容	替换内容
```

### 示例规则文件

```bash
# 批量替换规则文件
# 以 # 开头的行为注释

# 域名替换
old-domain.com	new-domain.com
example.com	mysite.com

# 协议升级
http://	https://

# API 版本升级
/api/v1/	/api/v2/

# 变量名重命名
oldVariableName	newVariableName
OLD_CONSTANT	NEW_CONSTANT
```

## 使用示例

### 示例 1: 替换当前目录

```bash
cd /path/to/your/project
rp -f /Users/lex/replace.txt
```

### 示例 2: 先预览再执行

```bash
# 1. 先预览
rp -f /Users/lex/replace.txt -p

# 2. 确认无误后执行
rp -f /Users/lex/replace.txt
```

### 示例 3: 替换指定目录

```bash
rp -f /Users/lex/replace.txt -d /Users/lex/git/knowledge
```

## 输出示例

```
========================================
批量替换
========================================
替换规则文件: /Users/lex/replace.txt
目标目录: /Users/lex/git/knowledge
----------------------------------------

规则 1: 'old_text' -> 'new_text'
  找到 3 个文件包含 'old_text':
    - ./file1.md
    - ./file2.sh
    - ./docs/readme.md

规则 2: 'example.com' -> 'newdomain.com'
  找到 1 个文件包含 'example.com':
    - ./config.yaml

========================================
替换完成!
总共处理规则: 2
总共处理文件: 4
修改的文件: 4
========================================
```

## 注意事项

⚠️ **备份重要文件**: 执行替换前建议先备份或使用版本控制  
⚠️ **使用预览模式**: 首次使用建议先用 `-p` 参数预览  
⚠️ **特殊字符**: 如果替换内容包含特殊字符,可能需要转义  
⚠️ **大小写敏感**: 替换是大小写敏感的

## 排除的文件和目录

脚本会自动排除以下目录和文件:
- `.git/`
- `node_modules/`
- `__pycache__/`
- `.venv/`, `venv/`
- `dist/`, `build/`
- `*.pyc`, `*.pyo`, `*.so`, `*.o`

## 故障排除

### 问题: 提示 "Permission denied"
**解决**: 确保脚本有执行权限
```bash
chmod +x /Users/lex/git/knowledge/shell-script/scripts/replace.sh
```

### 问题: 替换规则文件格式错误
**解决**: 确保每行有两列,用空格或制表符分隔

### 问题: 某些文件没有被替换
**解决**: 检查文件是否在排除列表中,或者文件权限是否正确
