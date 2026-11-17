# Kubernetes Pod 日志查看工具

## 背景

通常我们使用 `kubectl logs -l app=nginx-ingress -n <namespace>` 来查看某个 Deployment 下所有 Pod 的日志。但每次都需要手动获取 Pod 的 label，比较繁琐。

## 解决方案

使用以下脚本可以直接通过 Deployment 名称查看所有 Pod 的日志。

---

## 脚本：k-logs.sh

```bash
#!/usr/bin/env bash

# k-logs.sh - Kubernetes Deployment Logs Viewer
# 快速查看指定 Deployment 下所有 Pod 的日志

set -euo pipefail

# 颜色定义
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly CYAN=$'\033[0;36m'
readonly NC=$'\033[0m' # No Color

# 默认值
NAMESPACE="default"
DEPLOYMENT=""
FOLLOW=false
TAIL_LINES=""
CONTAINER=""
PREVIOUS=false
TIMESTAMPS=false
SINCE=""
ALL_CONTAINERS=false

# 使用说明
usage() {
    cat <<EOF
${CYAN}Kubernetes Deployment Logs Viewer${NC}

${GREEN}用法:${NC}
  $(basename "$0") -d <deployment> [选项]

${GREEN}必需参数:${NC}
  -d, --deployment NAME    Deployment 名称

${GREEN}可选参数:${NC}
  -n, --namespace NS       命名空间 (默认: default)
  -f, --follow             持续输出日志 (类似 tail -f)
  -c, --container NAME     指定容器名称 (多容器 Pod 时使用)
  -p, --previous           查看上一个终止容器的日志
  --tail N                 显示最后 N 行日志 (默认: 全部)
  --since DURATION         显示指定时间之后的日志 (如: 5s, 2m, 3h)
  --timestamps             显示时间戳
  --all-containers         显示所有容器的日志
  -h, --help               显示此帮助信息

${GREEN}示例:${NC}
  # 查看 nginx deployment 的日志
  $(basename "$0") -d nginx

  # 查看指定命名空间的 deployment 日志
  $(basename "$0") -d nginx -n production

  # 持续跟踪日志输出
  $(basename "$0") -d nginx -n production -f

  # 查看最后 100 行日志
  $(basename "$0") -d nginx --tail 100

  # 查看最近 5 分钟的日志
  $(basename "$0") -d nginx --since 5m

  # 查看指定容器的日志
  $(basename "$0") -d nginx -c nginx-container

  # 查看所有容器的日志（带时间戳）
  $(basename "$0") -d nginx --all-containers --timestamps

EOF
}

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# 检查 kubectl 是否可用
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 命令未找到，请先安装 kubectl"
        exit 1
    fi
}

# 检查 deployment 是否存在
check_deployment() {
    local deploy="$1"
    local ns="$2"
    
    if ! kubectl get deployment "$deploy" -n "$ns" &> /dev/null; then
        log_error "Deployment '$deploy' 在命名空间 '$ns' 中不存在"
        log_info "可用的 Deployments:"
        kubectl get deployments -n "$ns" --no-headers 2>/dev/null | awk '{print "  - " $1}' || echo "  (无)"
        exit 1
    fi
}

# 获取 deployment 的 label selector
get_label_selector() {
    local deploy="$1"
    local ns="$2"
    
    local selector
    selector=$(kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null)
    
    if [[ -z "$selector" ]]; then
        log_error "无法获取 Deployment '$deploy' 的 label selector"
        exit 1
    fi
    
    # 将 JSON 格式的 labels 转换为 kubectl 的 -l 格式
    # 例如: {"app":"nginx","version":"v1"} -> app=nginx,version=v1
    echo "$selector" | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")' 2>/dev/null || {
        # 如果 jq 不可用，使用简单的文本处理
        echo "$selector" | sed 's/[{}"]//g' | sed 's/:/=/g' | tr ' ' ','
    }
}

# 获取 pod 列表
get_pods() {
    local selector="$1"
    local ns="$2"
    
    kubectl get pods -l "$selector" -n "$ns" --no-headers 2>/dev/null | awk '{print $1}'
}

# 构建 kubectl logs 命令参数
build_logs_args() {
    local args=()
    
    [[ "$FOLLOW" == true ]] && args+=("--follow")
    [[ -n "$TAIL_LINES" ]] && args+=("--tail=$TAIL_LINES")
    [[ -n "$CONTAINER" ]] && args+=("--container=$CONTAINER")
    [[ "$PREVIOUS" == true ]] && args+=("--previous")
    [[ "$TIMESTAMPS" == true ]] && args+=("--timestamps")
    [[ -n "$SINCE" ]] && args+=("--since=$SINCE")
    [[ "$ALL_CONTAINERS" == true ]] && args+=("--all-containers=true")
    
    echo "${args[@]}"
}

# 查看日志
view_logs() {
    local deploy="$1"
    local ns="$2"
    
    log_info "正在查询 Deployment: ${CYAN}$deploy${NC} (命名空间: ${CYAN}$ns${NC})"
    
    # 获取 label selector
    local selector
    selector=$(get_label_selector "$deploy" "$ns")
    log_info "Label Selector: ${BLUE}$selector${NC}"
    
    # 获取 pod 列表
    local pods
    pods=$(get_pods "$selector" "$ns")
    
    if [[ -z "$pods" ]]; then
        log_warn "未找到任何 Pod"
        log_info "检查 Deployment 状态:"
        kubectl get deployment "$deploy" -n "$ns"
        exit 0
    fi
    
    local pod_count
    pod_count=$(echo "$pods" | wc -l | tr -d ' ')
    log_info "找到 ${GREEN}$pod_count${NC} 个 Pod"
    
    # 构建日志命令参数
    local logs_args
    logs_args=$(build_logs_args)
    
    # 如果只有一个 pod，直接查看
    if [[ "$pod_count" -eq 1 ]]; then
        local pod_name="$pods"
        log_info "查看 Pod: ${CYAN}$pod_name${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # shellcheck disable=SC2086
        kubectl logs "$pod_name" -n "$ns" $logs_args
    else
        # 多个 pod，使用 label selector
        log_info "使用 label selector 查看所有 Pod 日志"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # shellcheck disable=SC2086
        kubectl logs -l "$selector" -n "$ns" $logs_args --prefix=true
    fi
}

# 解析命令行参数
parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--deployment)
                DEPLOYMENT="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -f|--follow)
                FOLLOW=true
                shift
                ;;
            -c|--container)
                CONTAINER="$2"
                shift 2
                ;;
            -p|--previous)
                PREVIOUS=true
                shift
                ;;
            --tail)
                TAIL_LINES="$2"
                shift 2
                ;;
            --since)
                SINCE="$2"
                shift 2
                ;;
            --timestamps)
                TIMESTAMPS=true
                shift
                ;;
            --all-containers)
                ALL_CONTAINERS=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # 验证必需参数
    if [[ -z "$DEPLOYMENT" ]]; then
        log_error "必须指定 Deployment 名称 (-d)"
        usage
        exit 1
    fi
}

# 主函数
main() {
    parse_args "$@"
    check_kubectl
    check_deployment "$DEPLOYMENT" "$NAMESPACE"
    view_logs "$DEPLOYMENT" "$NAMESPACE"
}

main "$@"
```

---

## 安装和使用

### 1. 安装脚本

```bash
# 下载脚本
curl -o k-logs.sh https://raw.githubusercontent.com/your-repo/k-logs.sh

# 或直接创建文件并复制上面的脚本内容
vim k-logs.sh

# 添加执行权限
chmod +x k-logs.sh

# 移动到 PATH 目录（可选）
sudo mv k-logs.sh /usr/local/bin/k-logs

# 或者添加到用户目录
mkdir -p ~/bin
mv k-logs.sh ~/bin/k-logs
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 2. 使用示例

```bash
# 基础用法：查看 deployment 日志
k-logs -d nginx

# 指定命名空间
k-logs -d nginx -n production

# 持续跟踪日志（类似 tail -f）
k-logs -d nginx -n production -f

# 查看最后 100 行
k-logs -d nginx --tail 100

# 查看最近 5 分钟的日志
k-logs -d nginx --since 5m

# 查看最近 1 小时的日志，带时间戳
k-logs -d nginx --since 1h --timestamps

# 多容器 Pod：查看指定容器
k-logs -d nginx -c sidecar-container

# 查看所有容器的日志
k-logs -d nginx --all-containers

# 查看上一个终止容器的日志（排查崩溃问题）
k-logs -d nginx -p

# 组合使用
k-logs -d nginx -n production -f --tail 50 --timestamps
```

### 3. 常见场景

#### 场景 1：快速查看应用日志
```bash
k-logs -d my-app -n default
```

#### 场景 2：实时监控生产环境
```bash
k-logs -d api-server -n production -f --timestamps
```

#### 场景 3：排查最近的错误
```bash
k-logs -d backend -n staging --since 10m | grep -i error
```

#### 场景 4：查看崩溃的容器日志
```bash
k-logs -d worker -n production -p
```

#### 场景 5：多容器 Pod 调试
```bash
# 先查看有哪些容器
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].name}'

# 查看特定容器
k-logs -d my-app -c init-container
```

---

## 功能特性

- ✅ 自动获取 Deployment 的 label selector
- ✅ 支持单个或多个 Pod 的日志查看
- ✅ 支持持续跟踪日志输出（-f）
- ✅ 支持查看指定行数（--tail）
- ✅ 支持时间范围过滤（--since）
- ✅ 支持多容器 Pod（-c 或 --all-containers）
- ✅ 支持查看崩溃容器日志（-p）
- ✅ 彩色输出，易于阅读
- ✅ 错误提示和帮助信息

---

## 参数说明

| 参数 | 简写 | 说明 | 示例 |
|------|------|------|------|
| `--deployment` | `-d` | Deployment 名称（必需） | `-d nginx` |
| `--namespace` | `-n` | 命名空间 | `-n production` |
| `--follow` | `-f` | 持续输出日志 | `-f` |
| `--container` | `-c` | 指定容器名称 | `-c sidecar` |
| `--previous` | `-p` | 查看上一个容器日志 | `-p` |
| `--tail` | - | 显示最后 N 行 | `--tail 100` |
| `--since` | - | 时间范围 | `--since 5m` |
| `--timestamps` | - | 显示时间戳 | `--timestamps` |
| `--all-containers` | - | 所有容器日志 | `--all-containers` |
| `--help` | `-h` | 帮助信息 | `-h` |

---

## 依赖项

- `kubectl` - Kubernetes 命令行工具
- `jq` - JSON 处理工具（可选，用于更好的 label 解析）

安装依赖：
```bash
# macOS
brew install kubectl jq

# Ubuntu/Debian
sudo apt-get install kubectl jq

# CentOS/RHEL
sudo yum install kubectl jq
```

---

## 故障排查

### 问题 1：找不到 Deployment
```bash
# 检查 Deployment 是否存在
kubectl get deployments -n <namespace>

# 检查当前 context
kubectl config current-context

# 切换 namespace
kubectl config set-context --current --namespace=<namespace>
```

### 问题 2：没有 Pod
```bash
# 检查 Deployment 状态
kubectl get deployment <name> -n <namespace>

# 查看 Deployment 详情
kubectl describe deployment <name> -n <namespace>

# 检查 ReplicaSet
kubectl get rs -n <namespace>
```

### 问题 3：权限不足
```bash
# 检查当前用户权限
kubectl auth can-i get pods -n <namespace>
kubectl auth can-i get deployments -n <namespace>

# 查看当前用户
kubectl config view --minify
```

---

## 高级技巧

### 1. 结合 grep 过滤日志
```bash
k-logs -d api-server -n production | grep -i "error\|warn"
```

### 2. 保存日志到文件
```bash
k-logs -d backend --since 1h > backend-logs.txt
```

### 3. 实时过滤关键字
```bash
k-logs -d worker -f | grep --line-buffered "processing"
```

### 4. 多窗口监控
```bash
# 终端 1：监控应用日志
k-logs -d app -f

# 终端 2：监控 nginx 日志
k-logs -d nginx -f

# 终端 3：监控数据库日志
k-logs -d postgres -f
```

### 5. 创建别名
```bash
# 添加到 ~/.bashrc 或 ~/.zshrc
alias kl='k-logs'
alias klf='k-logs -f'
alias klt='k-logs --tail 100'

# 使用
kl -d nginx
klf -d api-server -n prod
klt -d worker
```

---

## 与原生命令对比

| 操作 | 原生命令 | k-logs 脚本 |
|------|----------|-------------|
| 查看日志 | `kubectl logs -l app=nginx -n prod` | `k-logs -d nginx -n prod` |
| 持续跟踪 | `kubectl logs -l app=nginx -n prod -f` | `k-logs -d nginx -n prod -f` |
| 最后 100 行 | `kubectl logs -l app=nginx --tail 100` | `k-logs -d nginx --tail 100` |
| 多容器 | `kubectl logs pod-name -c container` | `k-logs -d nginx -c container` |

**优势：**
- 无需手动查找和输入 label selector
- 自动处理单个或多个 Pod 的情况
- 更友好的错误提示
- 彩色输出，易于阅读