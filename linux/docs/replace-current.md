# Shell 脚本：批量文件内容关键字替换

## 问题分析

需要开发一个 Shell 脚本，实现以下核心功能：
- 读取指定配置文件（包含原始关键字和替换关键字的映射）
- 遍历当前目录及子目录下所有文件
- 批量替换文件内容中的关键字
- 支持通过命令行参数指定配置文件路径

## 解决方案

### 脚本实现

```bash
#!/bin/bash

# 脚本名称: replace_keywords.sh
# 功能: 根据配置文件批量替换当前目录下所有文件的关键字
# 使用方法: ./replace_keywords.sh -f /path/to/replace.txt

set -e

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 默认变量
CONFIG_FILE=""
CURRENT_DIR=$(pwd)
BACKUP_DIR="${CURRENT_DIR}/.backup_$(date +%Y%m%d_%H%M%S)"
DRY_RUN=false
VERBOSE=false

# 显示使用帮助
show_usage() {
    cat << EOF
使用方法: $0 -f <配置文件路径> [选项]

必需参数:
    -f <file>    指定关键字替换配置文件路径

可选参数:
    -d           试运行模式（不实际修改文件）
    -v           详细输出模式
    -b           创建备份（默认不备份）
    -h           显示此帮助信息

配置文件格式:
    每行两列，使用空格或制表符分隔
    第一列: 原始关键字
    第二列: 替换后的关键字
    
示例:
    old_value    new_value
    prod_server  test_server
    api.old.com  api.new.com

EOF
    exit 1
}

# 日志输出函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 创建备份
create_backup() {
    if [[ "$CREATE_BACKUP" == "true" ]]; then
        log_info "创建备份目录: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
        cp -r "$CURRENT_DIR"/* "$BACKUP_DIR"/ 2>/dev/null || true
        log_info "备份完成"
    fi
}

# 验证配置文件
validate_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
    
    if [[ ! -r "$CONFIG_FILE" ]]; then
        log_error "配置文件无读取权限: $CONFIG_FILE"
        exit 1
    fi
    
    local line_count=$(wc -l < "$CONFIG_FILE")
    if [[ $line_count -eq 0 ]]; then
        log_error "配置文件为空"
        exit 1
    fi
    
    log_info "配置文件验证通过: $CONFIG_FILE (共 $line_count 行规则)"
}

# 检查文件是否为二进制文件
is_binary_file() {
    local file="$1"
    if file "$file" | grep -q "text"; then
        return 1  # 文本文件
    else
        return 0  # 二进制文件
    fi
}

# 执行文件内容替换
perform_replace() {
    local file="$1"
    local old_keyword="$2"
    local new_keyword="$3"
    
    # 跳过二进制文件
    if is_binary_file "$file"; then
        [[ "$VERBOSE" == "true" ]] && log_warn "跳过二进制文件: $file"
        return
    fi
    
    # 检查文件是否包含关键字
    if ! grep -q "$old_keyword" "$file" 2>/dev/null; then
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] 将替换 '$old_keyword' -> '$new_keyword' in $file"
    else
        # 使用 sed 进行替换（兼容 Linux 和 macOS）
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|$old_keyword|$new_keyword|g" "$file"
        else
            sed -i "s|$old_keyword|$new_keyword|g" "$file"
        fi
        [[ "$VERBOSE" == "true" ]] && log_info "已替换: $file"
    fi
}

# 处理所有文件
process_files() {
    local total_files=0
    local processed_files=0
    local skipped_files=0
    
    log_info "开始处理文件..."
    
    # 读取配置文件并执行替换
    while IFS=$'\t ' read -r old_keyword new_keyword; do
        # 跳过空行和注释行
        [[ -z "$old_keyword" || "$old_keyword" =~ ^# ]] && continue
        
        log_info "处理替换规则: '$old_keyword' -> '$new_keyword'"
        
        # 查找所有文件（排除隐藏目录和脚本自身）
        while IFS= read -r -d '' file; do
            ((total_files++))
            
            # 跳过脚本自身和备份目录
            if [[ "$file" == "$0" || "$file" == *"/.backup_"* ]]; then
                ((skipped_files++))
                continue
            fi
            
            perform_replace "$file" "$old_keyword" "$new_keyword"
            ((processed_files++))
            
        done < <(find "$CURRENT_DIR" -type f -not -path '*/\.*' -print0)
        
    done < "$CONFIG_FILE"
    
    log_info "处理完成！"
    log_info "总文件数: $total_files, 处理: $processed_files, 跳过: $skipped_files"
}

# 主函数
main() {
    # 解析命令行参数
    while getopts "f:dvbh" opt; do
        case $opt in
            f)
                CONFIG_FILE="$OPTARG"
                ;;
            d)
                DRY_RUN=true
                log_warn "运行在试运行模式（不会实际修改文件）"
                ;;
            v)
                VERBOSE=true
                ;;
            b)
                CREATE_BACKUP=true
                ;;
            h)
                show_usage
                ;;
            \?)
                log_error "无效选项: -$OPTARG"
                show_usage
                ;;
        esac
    done
    
    # 检查必需参数
    if [[ -z "$CONFIG_FILE" ]]; then
        log_error "必须指定配置文件"
        show_usage
    fi
    
    # 验证配置文件
    validate_config
    
    # 创建备份（如果需要）
    create_backup
    
    # 执行替换
    process_files
    
    log_info "所有操作完成！"
}

# 执行主函数
main "$@"
```

## 配置文件示例

创建 `replace.txt` 配置文件：

```text
# 关键字替换配置文件
# 格式: 原始关键字    替换关键字

old_api_url             new_api_url
production              development
192.168.1.100           192.168.2.100
old-service-name        new-service-name
v1.0.0                  v2.0.0
```

## 使用说明

### 基本使用

```bash
# 赋予执行权限
chmod +x replace_keywords.sh

# 基本执行
./replace_keywords.sh -f /tmp/replace.txt

# 试运行模式（不实际修改文件）
./replace_keywords.sh -f /tmp/replace.txt -d

# 详细输出模式
./replace_keywords.sh -f /tmp/replace.txt -v

# 创建备份
./replace_keywords.sh -f /tmp/replace.txt -b

# 组合使用
./replace_keywords.sh -f /tmp/replace.txt -d -v -b
```

### 执行流程

```mermaid
graph TD
    A[开始执行脚本] --> B[解析命令行参数]
    B --> C{验证配置文件}
    C -->|失败| D[输出错误信息并退出]
    C -->|成功| E{是否需要备份?}
    E -->|是| F[创建备份目录]
    E -->|否| G[读取配置文件]
    F --> G
    G --> H[逐行解析替换规则]
    H --> I[遍历当前目录所有文件]
    I --> J{是否为二进制文件?}
    J -->|是| K[跳过该文件]
    J -->|否| L{是否包含关键字?}
    L -->|否| K
    L -->|是| M{是否试运行模式?}
    M -->|是| N[仅输出替换信息]
    M -->|否| O[执行实际替换]
    N --> P{还有更多文件?}
    O --> P
    K --> P
    P -->|是| I
    P -->|否| Q[输出统计信息]
    Q --> R[结束]
```

## 注意事项

### 使用前检查

1. **备份重要数据**
   - 首次使用建议使用 `-d` 参数试运行
   - 使用 `-b` 参数自动创建备份
   - 手动备份关键文件

2. **配置文件格式**
   - 确保使用空格或制表符分隔两列
   - 避免关键字中包含特殊字符（如 `/`）
   - 可以使用 `#` 添加注释行

3. **权限检查**
   ```bash
   # 检查当前目录权限
   ls -la
   
   # 确保脚本有执行权限
   chmod +x replace_keywords.sh
   ```

### 性能优化建议

1. **大规模文件处理**
   - 考虑使用 GNU parallel 并行处理
   - 限制处理的文件类型（添加文件扩展名过滤）

2. **排除特定目录**
   ```bash
   # 修改 find 命令，排除 node_modules 等目录
   find "$CURRENT_DIR" -type f -not -path '*/node_modules/*' -not -path '*/\.*' -print0
   ```

### 常见问题处理

1. **特殊字符转义**
   - 如果关键字包含特殊字符，需要在配置文件中转义
   - 或修改脚本使用 `perl` 替代 `sed`

2. **macOS 兼容性**
   - 脚本已处理 macOS 的 `sed -i` 差异
   - 需要安装 GNU coreutils 以获得更好兼容性

3. **大文件处理**
   - 对于超大文件，考虑使用流式处理
   - 添加文件大小限制检查

## 扩展功能建议

```bash
# 添加文件类型过滤
INCLUDE_EXTENSIONS=("*.txt" "*.conf" "*.yaml" "*.yml")

# 添加排除目录列表
EXCLUDE_DIRS=("node_modules" ".git" "vendor" "dist")

# 添加替换计数统计
echo "共替换 $count 处关键字"
```