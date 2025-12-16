# Pod 健康检查通用函数库

## 📖 概述

本文档提供了一套通用的 Pod 健康检查函数库，可以在 Kubernetes 环境中对 Pod 内部的 HTTP/HTTPS 端点进行健康检查。这些函数可以被其他脚本引用和调用，提供了灵活且可复用的健康检查能力。

## 🎯 核心价值

### 为什么需要这个函数库？

1. **绕过 Service/Ingress** - 直接在 Pod 内部检查，不受网络策略影响
2. **支持 HTTPS** - 使用 `openssl s_client` 处理 TLS 连接
3. **无需额外工具** - 只依赖 Pod 内已有的 `openssl` 和 `nc`
4. **可复用** - 一次编写，多处使用
5. **灵活配置** - 支持自定义超时、重试、协议等

### 适用场景

- ✅ 测量 Pod 启动时间
- ✅ 验证探针配置是否合理
- ✅ 调试健康检查端点问题
- ✅ 自动化测试和监控脚本
- ✅ CI/CD 流水线中的健康检查
- ✅ 故障排查和诊断

## 🔧 技术原理

### HTTP vs HTTPS 检查方式

#### HTTP 检查 (使用 nc)
```bash
printf "GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | \
  kubectl exec -i pod-name -n namespace -- timeout 2 nc localhost 8080
```

#### HTTPS 检查 (使用 openssl)
```bash
printf "GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | \
  kubectl exec -i pod-name -n namespace -- openssl s_client -connect localhost:8443 -quiet
```

### 为什么选择这种方式？

| 方法 | 优点 | 缺点 |
|------|------|------|
| `curl` | 简单易用 | Pod 内可能没有安装 |
| `wget` | 功能丰富 | Pod 内可能没有安装 |
| `nc` + `openssl` | ✅ 通常预装 | 需要手动构造 HTTP 请求 |


## 📦 函数库文件

### 1. 核心函数库 - `pod_health_check_lib.sh`

这是主要的函数库文件，包含所有健康检查相关的函数。因为Pod内部可能没有NC命令所以调整了这个脚本

```bash
#!/bin/bash
# pod_health_check_lib.sh
# Kubernetes Pod Health Check Function Library
# Version: 1.0.0

# ============================================================================
# 颜色定义
# ============================================================================
export HC_GREEN='\033[0;32m'
export HC_BLUE='\033[0;34m'
export HC_YELLOW='\033[1;33m'
export HC_RED='\033[0;31m'
export HC_CYAN='\033[0;36m'
export HC_NC='\033[0m'

# ============================================================================
# 核心函数: check_pod_health
# 功能: 检查 Pod 内部的健康端点
# 参数:
#   $1 - Pod 名称
#   $2 - Namespace
#   $3 - 协议 (HTTP/HTTPS)
#   $4 - 端口
#   $5 - 路径
#   $6 - 超时时间（可选，默认 2 秒）
# 返回:
#   0 - 健康检查成功 (HTTP 200)
#   1 - 健康检查失败
# 输出:
#   HTTP 状态码
# ============================================================================
check_pod_health() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local timeout="${6:-2}"
    
    # 参数验证
    if [ -z "$pod_name" ] || [ -z "$namespace" ] || [ -z "$scheme" ] || [ -z "$port" ] || [ -z "$path" ]; then
        echo "000"
        return 1
    fi
    
    local http_status_line
    local http_code
    
    if [[ "$scheme" == "HTTPS" ]]; then
        # HTTPS 检查使用 openssl
        http_status_line=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${path}" | \
            kubectl exec -i "${pod_name}" -n "${namespace}" -- sh -c \
            "openssl s_client -connect localhost:${port} -quiet 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
    else
        # HTTP 检查使用 nc
        http_status_line=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${path}" | \
            kubectl exec -i "${pod_name}" -n "${namespace}" -- sh -c \
            "timeout ${timeout} nc localhost ${port} 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
    fi
    
    # 提取状态码
    http_code=$(echo "$http_status_line" | awk '{print $2}')
    
    # 如果没有获取到状态码，返回 000
    if [ -z "$http_code" ]; then
        echo "000"
        return 1
    fi
    
    echo "$http_code"
    
    # 返回值：200 成功，其他失败
    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# 高级函数: check_pod_health_with_retry
# 功能: 带重试机制的健康检查
# 参数:
#   $1 - Pod 名称
#   $2 - Namespace
#   $3 - 协议 (HTTP/HTTPS)
#   $4 - 端口
#   $5 - 路径
#   $6 - 最大重试次数（可选，默认 3）
#   $7 - 重试间隔秒数（可选，默认 2）
# 返回:
#   0 - 健康检查成功
#   1 - 所有重试都失败
# ============================================================================
check_pod_health_with_retry() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local max_retries="${6:-3}"
    local retry_interval="${7:-2}"
    
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        local status_code
        status_code=$(check_pod_health "$pod_name" "$namespace" "$scheme" "$port" "$path")
        
        if [ $? -eq 0 ]; then
            echo "$status_code"
            return 0
        fi
        
        if [ $attempt -lt $max_retries ]; then
            sleep "$retry_interval"
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo "000"
    return 1
}

# ============================================================================
# 工具函数: wait_for_pod_ready
# 功能: 等待 Pod 变为 Ready 状态
# 参数:
#   $1 - Pod 名称
#   $2 - Namespace
#   $3 - 协议 (HTTP/HTTPS)
#   $4 - 端口
#   $5 - 路径
#   $6 - 最大等待次数（可选，默认 60）
#   $7 - 检查间隔秒数（可选，默认 2）
#   $8 - 是否显示进度（可选，yes/no，默认 yes）
# 返回:
#   0 - Pod 已就绪
#   1 - 超时
# 输出:
#   实际等待的秒数
# ============================================================================
wait_for_pod_ready() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local max_attempts="${6:-60}"
    local check_interval="${7:-2}"
    local show_progress="${8:-yes}"
    
    local attempt=1
    local start_time=$(date +%s)
    
    while [ $attempt -le $max_attempts ]; do
        local status_code
        status_code=$(check_pod_health "$pod_name" "$namespace" "$scheme" "$port" "$path")
        
        if [ $? -eq 0 ]; then
            local end_time=$(date +%s)
            local elapsed=$((end_time - start_time))
            echo "$elapsed"
            return 0
        fi
        
        if [[ "$show_progress" == "yes" ]]; then
            local progress_percent=$((attempt * 100 / max_attempts))
            echo -ne "\r   [${attempt}/${max_attempts}] Waiting for Pod ready... ${progress_percent}% (Status: ${status_code})"
        fi
        
        sleep "$check_interval"
        attempt=$((attempt + 1))
    done
    
    echo ""
    echo "-1"
    return 1
}

# ============================================================================
# 工具函数: get_probe_config
# 功能: 从 Pod 中提取探针配置
# 参数:
#   $1 - Pod 名称
#   $2 - Namespace
#   $3 - 探针类型 (startupProbe/readinessProbe/livenessProbe)
# 输出:
#   JSON 格式的探针配置
# ============================================================================
get_probe_config() {
    local pod_name="$1"
    local namespace="$2"
    local probe_type="$3"
    
    kubectl get pod "${pod_name}" -n "${namespace}" \
        -o jsonpath="{.spec.containers[0].${probe_type}}" 2>/dev/null
}

# ============================================================================
# 工具函数: extract_probe_endpoint
# 功能: 从探针配置中提取端点信息
# 参数:
#   $1 - 探针配置 (JSON)
# 输出:
#   格式: "SCHEME PORT PATH"
# ============================================================================
extract_probe_endpoint() {
    local probe_config="$1"
    
    if [ -z "$probe_config" ] || [ "$probe_config" == "null" ]; then
        echo ""
        return 1
    fi
    
    local scheme=$(echo "$probe_config" | jq -r '.httpGet.scheme // "HTTP"')
    local port=$(echo "$probe_config" | jq -r '.httpGet.port // 8080')
    local path=$(echo "$probe_config" | jq -r '.httpGet.path // "/health"')
    
    echo "${scheme} ${port} ${path}"
    return 0
}

# ============================================================================
# 工具函数: calculate_max_startup_time
# 功能: 计算探针配置允许的最大启动时间
# 参数:
#   $1 - 探针配置 (JSON)
# 输出:
#   最大启动时间（秒）
# ============================================================================
calculate_max_startup_time() {
    local probe_config="$1"
    
    if [ -z "$probe_config" ] || [ "$probe_config" == "null" ]; then
        echo "0"
        return 1
    fi
    
    local initial_delay=$(echo "$probe_config" | jq -r '.initialDelaySeconds // 0')
    local period=$(echo "$probe_config" | jq -r '.periodSeconds // 10')
    local failure_threshold=$(echo "$probe_config" | jq -r '.failureThreshold // 3')
    
    local max_time=$((initial_delay + period * failure_threshold))
    echo "$max_time"
    return 0
}

# ============================================================================
# 示例函数: demo_basic_check
# 功能: 演示基本的健康检查用法
# ============================================================================
demo_basic_check() {
    echo -e "${HC_CYAN}=== 基本健康检查示例 ===${HC_NC}\n"
    
    local pod_name="my-app-pod-abc123"
    local namespace="production"
    
    echo "检查 HTTP 端点..."
    local status=$(check_pod_health "$pod_name" "$namespace" "HTTP" "8080" "/health")
    if [ $? -eq 0 ]; then
        echo -e "${HC_GREEN}✓ 健康检查通过，状态码: ${status}${HC_NC}"
    else
        echo -e "${HC_RED}✗ 健康检查失败，状态码: ${status}${HC_NC}"
    fi
    
    echo ""
    echo "检查 HTTPS 端点..."
    status=$(check_pod_health "$pod_name" "$namespace" "HTTPS" "8443" "/health")
    if [ $? -eq 0 ]; then
        echo -e "${HC_GREEN}✓ 健康检查通过，状态码: ${status}${HC_NC}"
    else
        echo -e "${HC_RED}✗ 健康检查失败，状态码: ${status}${HC_NC}"
    fi
}

# ============================================================================
# 版本信息
# ============================================================================
pod_health_check_lib_version() {
    echo "Pod Health Check Library v1.0.0"
}
```


## 💡 使用方法

### 方法 1: Source 引入（推荐）

在你的脚本中引入函数库：

```bash
#!/bin/bash

# 引入健康检查函数库
source /path/to/pod_health_check_lib.sh

# 现在可以使用所有函数
POD_NAME="my-app-pod-abc123"
NAMESPACE="production"

# 基本检查
status=$(check_pod_health "$POD_NAME" "$NAMESPACE" "HTTPS" "8443" "/health")
if [ $? -eq 0 ]; then
    echo "健康检查通过: $status"
fi
```

### 方法 2: 复制函数到脚本中

如果不想依赖外部文件，可以直接复制需要的函数到你的脚本中。

## 📚 实际使用案例

### 案例 1: 测量 Pod 启动时间

创建文件 `measure_startup.sh`:

```bash
#!/bin/bash

# 引入函数库
source ./pod_health_check_lib.sh

# 参数
POD_NAME="$1"
NAMESPACE="$2"

if [ -z "$POD_NAME" ] || [ -z "$NAMESPACE" ]; then
    echo "Usage: $0 <pod-name> <namespace>"
    exit 1
fi

echo -e "${HC_BLUE}测量 Pod 启动时间: ${POD_NAME}${HC_NC}\n"

# 获取容器启动时间
CONTAINER_START=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} \
    -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)

if [ -z "$CONTAINER_START" ]; then
    echo -e "${HC_RED}错误: 容器尚未启动${HC_NC}"
    exit 1
fi

# 获取探针配置
READINESS_PROBE=$(get_probe_config "$POD_NAME" "$NAMESPACE" "readinessProbe")
PROBE_ENDPOINT=$(extract_probe_endpoint "$READINESS_PROBE")

if [ -z "$PROBE_ENDPOINT" ]; then
    echo -e "${HC_RED}错误: 无法获取探针配置${HC_NC}"
    exit 1
fi

# 解析端点信息
read SCHEME PORT PATH <<< "$PROBE_ENDPOINT"

echo -e "${HC_GREEN}探针配置:${HC_NC}"
echo "  - Scheme: $SCHEME"
echo "  - Port: $PORT"
echo "  - Path: $PATH"
echo ""

# 计算启动时间戳
if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CONTAINER_START" "+%s" 2>/dev/null)
else
    START_TIME_SEC=$(date -d "$CONTAINER_START" "+%s" 2>/dev/null)
fi

# 等待 Pod 就绪
echo -e "${HC_YELLOW}等待 Pod 就绪...${HC_NC}"
ELAPSED=$(wait_for_pod_ready "$POD_NAME" "$NAMESPACE" "$SCHEME" "$PORT" "$PATH" 60 2 "yes")

if [ "$ELAPSED" -eq -1 ]; then
    echo -e "\n${HC_RED}超时: Pod 未能在规定时间内就绪${HC_NC}"
    exit 1
fi

echo -e "\n${HC_GREEN}✓ Pod 启动完成!${HC_NC}"
echo -e "${HC_GREEN}启动耗时: ${ELAPSED} 秒${HC_NC}"

# 分析配置
MAX_TIME=$(calculate_max_startup_time "$READINESS_PROBE")
echo ""
echo -e "${HC_YELLOW}配置分析:${HC_NC}"
echo "  当前配置允许的最大启动时间: ${MAX_TIME}s"
echo "  实际启动时间: ${ELAPSED}s"

if [ $ELAPSED -gt $MAX_TIME ]; then
    echo -e "  ${HC_RED}⚠️ 警告: 实际启动时间超过配置!${HC_NC}"
else
    BUFFER=$((MAX_TIME - ELAPSED))
    echo -e "  ${HC_GREEN}✓ 配置合理，缓冲时间: ${BUFFER}s${HC_NC}"
fi
```

使用方法：
```bash
chmod +x measure_startup.sh
./measure_startup.sh my-app-pod-abc123 production
```

### 案例 2: 批量检查多个 Pod

创建文件 `batch_health_check.sh`:

```bash
#!/bin/bash

# 引入函数库
source ./pod_health_check_lib.sh

NAMESPACE="$1"
DEPLOYMENT="$2"

if [ -z "$NAMESPACE" ] || [ -z "$DEPLOYMENT" ]; then
    echo "Usage: $0 <namespace> <deployment>"
    exit 1
fi

echo -e "${HC_BLUE}批量检查 Deployment: ${DEPLOYMENT}${HC_NC}\n"

# 获取所有 Pod
PODS=$(kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT} \
    --no-headers -o custom-columns=":metadata.name")

if [ -z "$PODS" ]; then
    echo -e "${HC_RED}未找到任何 Pod${HC_NC}"
    exit 1
fi

# 获取探针配置（假设所有 Pod 配置相同）
FIRST_POD=$(echo "$PODS" | head -n 1)
READINESS_PROBE=$(get_probe_config "$FIRST_POD" "$NAMESPACE" "readinessProbe")
PROBE_ENDPOINT=$(extract_probe_endpoint "$READINESS_PROBE")
read SCHEME PORT PATH <<< "$PROBE_ENDPOINT"

echo -e "${HC_GREEN}探针端点: ${SCHEME}://localhost:${PORT}${PATH}${HC_NC}\n"

# 检查每个 Pod
TOTAL=0
SUCCESS=0
FAILED=0

for POD in $PODS; do
    TOTAL=$((TOTAL + 1))
    echo -n "检查 Pod: ${POD} ... "
    
    STATUS=$(check_pod_health "$POD" "$NAMESPACE" "$SCHEME" "$PORT" "$PATH")
    
    if [ $? -eq 0 ]; then
        echo -e "${HC_GREEN}✓ 健康 (${STATUS})${HC_NC}"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -e "${HC_RED}✗ 不健康 (${STATUS})${HC_NC}"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo -e "${HC_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HC_NC}"
echo -e "${HC_BLUE}检查结果汇总${HC_NC}"
echo -e "${HC_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HC_NC}"
echo "总计: $TOTAL"
echo -e "${HC_GREEN}成功: $SUCCESS${HC_NC}"
echo -e "${HC_RED}失败: $FAILED${HC_NC}"
```

使用方法：
```bash
chmod +x batch_health_check.sh
./batch_health_check.sh production my-app
```

### 案例 3: CI/CD 流水线健康检查

创建文件 `cicd_health_check.sh`:

```bash
#!/bin/bash

# 引入函数库
source ./pod_health_check_lib.sh

# CI/CD 环境变量
POD_NAME="${K8S_POD_NAME}"
NAMESPACE="${K8S_NAMESPACE}"
SCHEME="${HEALTH_SCHEME:-HTTPS}"
PORT="${HEALTH_PORT:-8443}"
PATH="${HEALTH_PATH:-/health}"
MAX_WAIT="${MAX_WAIT_SECONDS:-300}"

echo "=== CI/CD Health Check ==="
echo "Pod: $POD_NAME"
echo "Namespace: $NAMESPACE"
echo "Endpoint: ${SCHEME}://localhost:${PORT}${PATH}"
echo ""

# 等待 Pod 就绪
echo "Waiting for Pod to be ready..."
ELAPSED=$(wait_for_pod_ready "$POD_NAME" "$NAMESPACE" "$SCHEME" "$PORT" "$PATH" \
    $((MAX_WAIT / 2)) 2 "yes")

if [ "$ELAPSED" -eq -1 ]; then
    echo ""
    echo "ERROR: Pod failed to become ready within ${MAX_WAIT} seconds"
    exit 1
fi

echo ""
echo "SUCCESS: Pod is ready in ${ELAPSED} seconds"

# 额外验证：连续检查 3 次
echo ""
echo "Performing additional verification (3 consecutive checks)..."
for i in {1..3}; do
    STATUS=$(check_pod_health "$POD_NAME" "$NAMESPACE" "$SCHEME" "$PORT" "$PATH")
    if [ $? -ne 0 ]; then
        echo "ERROR: Health check failed on attempt $i (Status: $STATUS)"
        exit 1
    fi
    echo "Check $i/3: OK (Status: $STATUS)"
    sleep 1
done

echo ""
echo "✓ All health checks passed!"
exit 0
```

在 GitLab CI/Jenkins 中使用：
```yaml
# .gitlab-ci.yml
deploy:
  script:
    - kubectl apply -f deployment.yaml
    - export K8S_POD_NAME=$(kubectl get pods -n production -l app=my-app -o jsonpath='{.items[0].metadata.name}')
    - export K8S_NAMESPACE=production
    - ./cicd_health_check.sh
```

### 案例 4: 集成到现有的 pod_status.sh

修改你现有的 `k8s/scripts/pod_status.sh`，添加实时健康检查：

```bash
#!/bin/bash

# 引入健康检查函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../custom-liveness/explore-startprobe/pod_health_check_lib.sh"

# ... 原有代码 ...

for POD in ${PODS}; do
    echo -e "${YELLOW}Pod: ${POD}${NC}"
    
    # ... 原有的信息获取代码 ...
    
    # 新增：实时健康检查
    echo -e "\n${YELLOW}实时健康检查:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ ! -z "$READINESS_PROBE" ]; then
        PROBE_ENDPOINT=$(extract_probe_endpoint "$READINESS_PROBE")
        if [ ! -z "$PROBE_ENDPOINT" ]; then
            read SCHEME PORT PATH <<< "$PROBE_ENDPOINT"
            
            echo "检查端点: ${SCHEME}://localhost:${PORT}${PATH}"
            STATUS=$(check_pod_health_with_retry "$POD" "$NAMESPACE" "$SCHEME" "$PORT" "$PATH" 3 1)
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ 当前状态: 健康 (HTTP ${STATUS})${NC}"
            else
                echo -e "${RED}✗ 当前状态: 不健康 (HTTP ${STATUS})${NC}"
            fi
        fi
    else
        echo "未配置 ReadinessProbe，跳过实时检查"
    fi
    
    # ... 原有代码继续 ...
done
```


## 🔍 深度探索：技术细节

### 1. 为什么使用 `kubectl exec` 而不是外部访问？

**问题场景：**
- Service 可能还没创建
- Ingress 可能有网络策略限制
- 需要测试 Pod 内部视角的健康状态

**解决方案：**
```bash
# 直接在 Pod 内部执行命令
kubectl exec -i pod-name -n namespace -- command
```

这种方式：
- ✅ 绕过所有网络层
- ✅ 模拟 kubelet 探针的行为
- ✅ 不受 Service/Ingress 影响

### 2. HTTP 请求构造详解

#### 标准 HTTP/1.1 请求格式

```http
GET /health HTTP/1.1\r\n
Host: localhost\r\n
Connection: close\r\n
\r\n
```

**关键点：**
- `\r\n` 是 HTTP 协议要求的行结束符（CRLF）
- `Host` 头是 HTTP/1.1 必需的
- `Connection: close` 确保请求完成后关闭连接
- 最后的空行（`\r\n\r\n`）标志请求头结束

#### 使用 printf 构造请求

```bash
printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "/health"
```

**为什么用 printf 而不是 echo？**
- `echo` 在不同系统中对 `\r\n` 的处理不一致
- `printf` 更可靠，跨平台兼容性好

### 3. nc (netcat) 详解

#### 基本用法
```bash
nc localhost 8080
```

#### 带超时
```bash
timeout 2 nc localhost 8080
```

**超时的重要性：**
- 防止连接挂起
- 快速失败，不阻塞脚本
- 模拟 kubelet 的 `timeoutSeconds` 行为

#### 完整示例
```bash
# 发送 HTTP 请求并获取响应
printf "GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | \
  timeout 2 nc localhost 8080
```

**输出示例：**
```
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 15

{"status":"ok"}
```

### 4. openssl s_client 详解

#### 基本用法
```bash
openssl s_client -connect localhost:8443
```

**问题：** 会输出大量 TLS 握手信息

#### 使用 -quiet 参数
```bash
openssl s_client -connect localhost:8443 -quiet
```

**效果：** 只显示应用层数据，隐藏 TLS 握手信息

#### 完整 HTTPS 请求示例
```bash
printf "GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | \
  openssl s_client -connect localhost:8443 -quiet 2>&1
```

**为什么需要 `2>&1`？**
- openssl 的一些信息输出到 stderr
- 重定向到 stdout 以便统一处理

### 5. 状态码提取技巧

#### 使用 grep 和 awk
```bash
# 提取 HTTP 状态行
grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1

# 提取状态码
awk '{print $2}'
```

**完整流程：**
```bash
HTTP_STATUS_LINE=$(... | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1)
HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
```

**为什么用 `head -1`？**
- HTTP 响应可能包含多个状态行（重定向）
- 只取第一个状态行

#### 处理边界情况
```bash
if [ -z "$HTTP_CODE" ]; then
    HTTP_CODE="000"  # 表示连接失败
fi
```

**常见状态码含义：**
- `000` - 连接失败/超时
- `200` - 成功
- `404` - 路径不存在
- `500` - 服务器错误
- `503` - 服务不可用

### 6. 跨平台时间处理

#### macOS (BSD date)
```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
    TIMESTAMP=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ISO_TIME" "+%s")
fi
```

#### Linux (GNU date)
```bash
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    TIMESTAMP=$(date -d "$ISO_TIME" "+%s")
fi
```

**通用模式：**
```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS 命令
else
    # Linux 命令
fi
```

### 7. 进度条实现

```bash
PROGRESS_PERCENT=$((PROBE_COUNT * 100 / MAX_PROBES))
FILLED=$((PROGRESS_PERCENT / 5))

PROGRESS_BAR=""
for i in $(seq 1 20); do
    if [ $i -le $FILLED ]; then
        PROGRESS_BAR="${PROGRESS_BAR}█"
    else
        PROGRESS_BAR="${PROGRESS_BAR}░"
    fi
done

echo -e "[${PROBE_COUNT}/${MAX_PROBES}] ${PROGRESS_BAR} ${PROGRESS_PERCENT}%"
```

**输出效果：**
```
[15/60] ████████░░░░░░░░░░░░ 25%
```

## 🎓 最佳实践建议

### 1. 函数库组织

**推荐目录结构：**
```
k8s/
├── lib/
│   └── pod_health_check_lib.sh    # 函数库
├── scripts/
│   ├── measure_startup.sh          # 使用函数库的脚本
│   ├── batch_health_check.sh
│   └── pod_status.sh
└── custom-liveness/
    └── explore-startprobe/
        └── openssl-verify-health.md
```

**引入方式：**
```bash
# 方法 1: 相对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/pod_health_check_lib.sh"

# 方法 2: 绝对路径
source "/path/to/k8s/lib/pod_health_check_lib.sh"

# 方法 3: 环境变量
source "${K8S_LIB_PATH}/pod_health_check_lib.sh"
```

### 2. 错误处理

**总是检查返回值：**
```bash
STATUS=$(check_pod_health "$POD" "$NS" "HTTPS" "8443" "/health")
if [ $? -ne 0 ]; then
    echo "健康检查失败: $STATUS"
    # 处理错误
fi
```

**参数验证：**
```bash
if [ -z "$POD_NAME" ] || [ -z "$NAMESPACE" ]; then
    echo "错误: 缺少必需参数"
    exit 1
fi
```

### 3. 日志记录

**添加时间戳：**
```bash
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "开始健康检查..."
```

**日志级别：**
```bash
log_info() { echo -e "${HC_GREEN}[INFO]${HC_NC} $*"; }
log_warn() { echo -e "${HC_YELLOW}[WARN]${HC_NC} $*"; }
log_error() { echo -e "${HC_RED}[ERROR]${HC_NC} $*"; }
```

### 4. 性能优化

**并行检查多个 Pod：**
```bash
for POD in $PODS; do
    (
        STATUS=$(check_pod_health "$POD" "$NS" "HTTPS" "8443" "/health")
        echo "$POD: $STATUS"
    ) &
done
wait
```

**缓存探针配置：**
```bash
# 只获取一次，所有 Pod 共享
PROBE_CONFIG=$(get_probe_config "$FIRST_POD" "$NAMESPACE" "readinessProbe")
```

### 5. 安全考虑

**避免在日志中暴露敏感信息：**
```bash
# 不好
echo "Checking https://admin:password@localhost:8443/health"

# 好
echo "Checking HTTPS endpoint on port 8443"
```

**使用 kubectl 的 RBAC：**
```bash
# 确保有足够的权限
kubectl auth can-i get pods -n $NAMESPACE
kubectl auth can-i exec pods -n $NAMESPACE
```

## 🚀 高级用法

### 1. 自定义 HTTP 头

```bash
check_pod_health_with_headers() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local headers="$6"  # 格式: "Header1: value1\r\nHeader2: value2"
    
    local http_request="GET ${path} HTTP/1.1\r\nHost: localhost\r\n${headers}\r\nConnection: close\r\n\r\n"
    
    if [[ "$scheme" == "HTTPS" ]]; then
        printf "$http_request" | \
            kubectl exec -i "${pod_name}" -n "${namespace}" -- \
            openssl s_client -connect localhost:${port} -quiet 2>&1 | \
            grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1 | awk '{print $2}'
    else
        printf "$http_request" | \
            kubectl exec -i "${pod_name}" -n "${namespace}" -- \
            timeout 2 nc localhost ${port} 2>&1 | \
            grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1 | awk '{print $2}'
    fi
}

# 使用示例
CUSTOM_HEADERS="Authorization: Bearer token123\r\nX-Custom-Header: value"
check_pod_health_with_headers "$POD" "$NS" "HTTPS" "8443" "/health" "$CUSTOM_HEADERS"
```

### 2. 检查响应体

```bash
check_pod_health_with_body() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    
    local response
    if [[ "$scheme" == "HTTPS" ]]; then
        response=$(printf "GET ${path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | \
            kubectl exec -i "${pod_name}" -n "${namespace}" -- \
            openssl s_client -connect localhost:${port} -quiet 2>&1)
    else
        response=$(printf "GET ${path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | \
            kubectl exec -i "${pod_name}" -n "${namespace}" -- \
            timeout 2 nc localhost ${port} 2>&1)
    fi
    
    # 提取状态码
    local status_code=$(echo "$response" | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1 | awk '{print $2}')
    
    # 提取响应体（空行之后的内容）
    local body=$(echo "$response" | sed -n '/^\r$/,$p' | tail -n +2)
    
    echo "Status: $status_code"
    echo "Body: $body"
}
```

### 3. 监控模式（持续检查）

```bash
monitor_pod_health() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local interval="${6:-5}"
    
    echo "开始监控 Pod: $pod_name"
    echo "按 Ctrl+C 停止"
    echo ""
    
    while true; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local status=$(check_pod_health "$pod_name" "$namespace" "$scheme" "$port" "$path")
        
        if [ $? -eq 0 ]; then
            echo -e "${timestamp} ${HC_GREEN}✓${HC_NC} Status: ${status}"
        else
            echo -e "${timestamp} ${HC_RED}✗${HC_NC} Status: ${status}"
        fi
        
        sleep "$interval"
    done
}

# 使用
monitor_pod_health "my-app-pod" "production" "HTTPS" "8443" "/health" 10
```


## 📋 完整示例脚本

### 创建函数库文件

将以下内容保存为 `pod_health_check_lib.sh`:

```bash
#!/bin/bash
# pod_health_check_lib.sh - Kubernetes Pod Health Check Function Library
# Version: 1.0.0
# Usage: source this file in your scripts

# 颜色定义
export HC_GREEN='\033[0;32m'
export HC_BLUE='\033[0;34m'
export HC_YELLOW='\033[1;33m'
export HC_RED='\033[0;31m'
export HC_CYAN='\033[0;36m'
export HC_NC='\033[0m'

# 核心健康检查函数
check_pod_health() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local timeout="${6:-2}"
    
    if [ -z "$pod_name" ] || [ -z "$namespace" ] || [ -z "$scheme" ] || [ -z "$port" ] || [ -z "$path" ]; then
        echo "000"
        return 1
    fi
    
    local http_status_line
    local http_code
    
    if [[ "$scheme" == "HTTPS" ]]; then
        http_status_line=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${path}" | \
            kubectl exec -i "${pod_name}" -n "${namespace}" -- sh -c \
            "openssl s_client -connect localhost:${port} -quiet 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
    else
        http_status_line=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${path}" | \
            kubectl exec -i "${pod_name}" -n "${namespace}" -- sh -c \
            "timeout ${timeout} nc localhost ${port} 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
    fi
    
    http_code=$(echo "$http_status_line" | awk '{print $2}')
    
    if [ -z "$http_code" ]; then
        echo "000"
        return 1
    fi
    
    echo "$http_code"
    
    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# 带重试的健康检查
check_pod_health_with_retry() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local max_retries="${6:-3}"
    local retry_interval="${7:-2}"
    
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        local status_code
        status_code=$(check_pod_health "$pod_name" "$namespace" "$scheme" "$port" "$path")
        
        if [ $? -eq 0 ]; then
            echo "$status_code"
            return 0
        fi
        
        if [ $attempt -lt $max_retries ]; then
            sleep "$retry_interval"
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo "000"
    return 1
}

# 等待 Pod 就绪
wait_for_pod_ready() {
    local pod_name="$1"
    local namespace="$2"
    local scheme="$3"
    local port="$4"
    local path="$5"
    local max_attempts="${6:-60}"
    local check_interval="${7:-2}"
    local show_progress="${8:-yes}"
    
    local attempt=1
    local start_time=$(date +%s)
    
    while [ $attempt -le $max_attempts ]; do
        local status_code
        status_code=$(check_pod_health "$pod_name" "$namespace" "$scheme" "$port" "$path")
        
        if [ $? -eq 0 ]; then
            local end_time=$(date +%s)
            local elapsed=$((end_time - start_time))
            echo "$elapsed"
            return 0
        fi
        
        if [[ "$show_progress" == "yes" ]]; then
            local progress_percent=$((attempt * 100 / max_attempts))
            echo -ne "\r   [${attempt}/${max_attempts}] Waiting... ${progress_percent}% (Status: ${status_code})"
        fi
        
        sleep "$check_interval"
        attempt=$((attempt + 1))
    done
    
    echo ""
    echo "-1"
    return 1
}

# 获取探针配置
get_probe_config() {
    local pod_name="$1"
    local namespace="$2"
    local probe_type="$3"
    
    kubectl get pod "${pod_name}" -n "${namespace}" \
        -o jsonpath="{.spec.containers[0].${probe_type}}" 2>/dev/null
}

# 提取探针端点
extract_probe_endpoint() {
    local probe_config="$1"
    
    if [ -z "$probe_config" ] || [ "$probe_config" == "null" ]; then
        echo ""
        return 1
    fi
    
    local scheme=$(echo "$probe_config" | jq -r '.httpGet.scheme // "HTTP"')
    local port=$(echo "$probe_config" | jq -r '.httpGet.port // 8080')
    local path=$(echo "$probe_config" | jq -r '.httpGet.path // "/health"')
    
    echo "${scheme} ${port} ${path}"
    return 0
}

# 计算最大启动时间
calculate_max_startup_time() {
    local probe_config="$1"
    
    if [ -z "$probe_config" ] || [ "$probe_config" == "null" ]; then
        echo "0"
        return 1
    fi
    
    local initial_delay=$(echo "$probe_config" | jq -r '.initialDelaySeconds // 0')
    local period=$(echo "$probe_config" | jq -r '.periodSeconds // 10')
    local failure_threshold=$(echo "$probe_config" | jq -r '.failureThreshold // 3')
    
    local max_time=$((initial_delay + period * failure_threshold))
    echo "$max_time"
    return 0
}

# 版本信息
pod_health_check_lib_version() {
    echo "Pod Health Check Library v1.0.0"
}
```

## 🧪 测试和验证

### 快速测试脚本

创建 `test_health_lib.sh`:

```bash
#!/bin/bash

# 引入函数库
source ./pod_health_check_lib.sh

echo "=== Pod Health Check Library Test ==="
echo ""

# 显示版本
pod_health_check_lib_version
echo ""

# 测试参数
POD_NAME="${1:-my-app-pod-abc123}"
NAMESPACE="${2:-production}"

echo "Testing with:"
echo "  Pod: $POD_NAME"
echo "  Namespace: $NAMESPACE"
echo ""

# 测试 1: 获取探针配置
echo "Test 1: Get probe configuration"
READINESS_PROBE=$(get_probe_config "$POD_NAME" "$NAMESPACE" "readinessProbe")
if [ $? -eq 0 ] && [ -n "$READINESS_PROBE" ]; then
    echo "✓ Successfully retrieved probe config"
    echo "$READINESS_PROBE" | jq '.'
else
    echo "✗ Failed to get probe config"
    exit 1
fi
echo ""

# 测试 2: 提取端点信息
echo "Test 2: Extract endpoint information"
PROBE_ENDPOINT=$(extract_probe_endpoint "$READINESS_PROBE")
if [ $? -eq 0 ]; then
    echo "✓ Successfully extracted endpoint"
    read SCHEME PORT PATH <<< "$PROBE_ENDPOINT"
    echo "  Scheme: $SCHEME"
    echo "  Port: $PORT"
    echo "  Path: $PATH"
else
    echo "✗ Failed to extract endpoint"
    exit 1
fi
echo ""

# 测试 3: 基本健康检查
echo "Test 3: Basic health check"
STATUS=$(check_pod_health "$POD_NAME" "$NAMESPACE" "$SCHEME" "$PORT" "$PATH")
if [ $? -eq 0 ]; then
    echo "✓ Health check passed (Status: $STATUS)"
else
    echo "✗ Health check failed (Status: $STATUS)"
fi
echo ""

# 测试 4: 带重试的健康检查
echo "Test 4: Health check with retry"
STATUS=$(check_pod_health_with_retry "$POD_NAME" "$NAMESPACE" "$SCHEME" "$PORT" "$PATH" 3 1)
if [ $? -eq 0 ]; then
    echo "✓ Health check with retry passed (Status: $STATUS)"
else
    echo "✗ Health check with retry failed (Status: $STATUS)"
fi
echo ""

# 测试 5: 计算最大启动时间
echo "Test 5: Calculate max startup time"
MAX_TIME=$(calculate_max_startup_time "$READINESS_PROBE")
if [ $? -eq 0 ]; then
    echo "✓ Max startup time: ${MAX_TIME}s"
else
    echo "✗ Failed to calculate max startup time"
fi
echo ""

echo "=== All tests completed ==="
```

使用方法：
```bash
chmod +x test_health_lib.sh
./test_health_lib.sh my-app-pod-abc123 production
```

## 📊 性能对比

### 传统方法 vs 函数库方法

| 方法 | 代码行数 | 可维护性 | 可复用性 | 错误处理 |
|------|---------|---------|---------|---------|
| 内联代码 | 50+ | ❌ 低 | ❌ 无 | ⚠️ 基础 |
| 函数库 | 5-10 | ✅ 高 | ✅ 完全 | ✅ 完善 |

### 示例对比

**传统方法（每个脚本都要写）：**
```bash
# 50+ 行代码
HTTP_STATUS_LINE=$(printf "GET /health HTTP/1.1\r\n..." | kubectl exec ...)
HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
if [ -z "$HTTP_CODE" ]; then
    HTTP_CODE="000"
fi
# ... 更多代码
```

**函数库方法（一行搞定）：**
```bash
STATUS=$(check_pod_health "$POD" "$NS" "HTTPS" "8443" "/health")
```

## 🔧 故障排查

### 常见问题

#### 1. 函数库找不到

**错误：**
```
./my_script.sh: line 3: pod_health_check_lib.sh: No such file or directory
```

**解决：**
```bash
# 使用绝对路径
source /full/path/to/pod_health_check_lib.sh

# 或使用相对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/pod_health_check_lib.sh"
```

#### 2. kubectl exec 权限不足

**错误：**
```
Error from server (Forbidden): pods "my-pod" is forbidden
```

**解决：**
```bash
# 检查权限
kubectl auth can-i exec pods -n production

# 如果没有权限，联系集群管理员
```

#### 3. Pod 内没有 openssl 或 nc

**错误：**
```
sh: openssl: not found
```

**解决方案 1：** 使用 HTTP 而不是 HTTPS
```bash
# 如果 Pod 支持 HTTP，使用 HTTP
STATUS=$(check_pod_health "$POD" "$NS" "HTTP" "8080" "/health")
```

**解决方案 2：** 安装工具到镜像
```dockerfile
# Dockerfile
FROM your-base-image
RUN apk add --no-cache openssl netcat-openbsd
```

#### 4. 状态码总是 000

**可能原因：**
- Pod 还没启动完成
- 端口或路径配置错误
- 健康检查端点有问题

**调试：**
```bash
# 手动测试
kubectl exec -it my-pod -n production -- sh
# 在 Pod 内执行
nc -zv localhost 8080
curl http://localhost:8080/health
```

## 📚 参考资源

### 相关文档
- [Kubernetes Probes 官方文档](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [OpenSSL s_client 文档](https://www.openssl.org/docs/man1.1.1/man1/s_client.html)
- [Netcat 使用指南](https://nc110.sourceforge.io/)

### 相关脚本
- `pod_measure_startup_fixed.sh` - 启动时间测量
- `pod_measure_startup_enhance.sh` - 增强版测量脚本
- `pod_status.sh` - Pod 状态分析

### 扩展阅读
- HTTP/1.1 协议规范 (RFC 2616)
- Bash 脚本最佳实践
- Kubernetes 探针配置最佳实践

## 🎯 总结

### 核心优势

1. **可复用性** - 一次编写，到处使用
2. **标准化** - 统一的健康检查方式
3. **易维护** - 集中管理，统一更新
4. **灵活性** - 支持 HTTP/HTTPS，可自定义参数
5. **可靠性** - 完善的错误处理和边界情况处理

### 适用场景总结

| 场景 | 推荐函数 | 说明 |
|------|---------|------|
| 快速检查 | `check_pod_health` | 单次检查，快速返回 |
| 可靠检查 | `check_pod_health_with_retry` | 带重试，更可靠 |
| 等待就绪 | `wait_for_pod_ready` | 持续等待直到就绪 |
| 批量检查 | 循环调用 `check_pod_health` | 检查多个 Pod |
| CI/CD | `wait_for_pod_ready` | 部署后验证 |
| 监控 | 定时调用 `check_pod_health` | 持续监控 |

### 下一步

1. ✅ 将函数库保存到 `k8s/lib/pod_health_check_lib.sh`
2. ✅ 在现有脚本中引入函数库
3. ✅ 测试和验证功能
4. ✅ 根据需要扩展自定义函数
5. ✅ 分享给团队成员使用

---

**文档版本**: 1.0.0  
**创建日期**: 2024-12  
**最后更新**: 2024-12  
**维护者**: DevOps Team


## 🎯 Quick Reference Card

### Installation

```bash
# 1. Copy library to your project
cp pod_health_check_lib.sh /path/to/your/project/k8s/lib/

# 2. Make it executable
chmod +x /path/to/your/project/k8s/lib/pod_health_check_lib.sh
```

### Basic Usage

```bash
# Source the library
source ./pod_health_check_lib.sh

# Check Pod health
STATUS=$(check_pod_health "pod-name" "namespace" "HTTPS" "8443" "/health")
echo "Status: $STATUS"
```

### Common Patterns

#### Pattern 1: Quick Check
```bash
if check_pod_health "$POD" "$NS" "HTTPS" "8443" "/health" >/dev/null; then
    echo "Pod is healthy"
else
    echo "Pod is unhealthy"
fi
```

#### Pattern 2: With Retry
```bash
STATUS=$(check_pod_health_with_retry "$POD" "$NS" "HTTPS" "8443" "/health" 3 2)
```

#### Pattern 3: Wait for Ready
```bash
ELAPSED=$(wait_for_pod_ready "$POD" "$NS" "HTTPS" "8443" "/health" 60 2 "yes")
if [ "$ELAPSED" -ne -1 ]; then
    echo "Pod ready in ${ELAPSED}s"
fi
```

#### Pattern 4: Auto-detect from Probe
```bash
PROBE=$(get_probe_config "$POD" "$NS" "readinessProbe")
read SCHEME PORT PATH <<< $(extract_probe_endpoint "$PROBE")
STATUS=$(check_pod_health "$POD" "$NS" "$SCHEME" "$PORT" "$PATH")
```

### Function Quick Reference

| Function | Purpose | Returns |
|----------|---------|---------|
| `check_pod_health` | Single check | HTTP status code |
| `check_pod_health_with_retry` | Check with retry | HTTP status code |
| `wait_for_pod_ready` | Wait until ready | Elapsed seconds |
| `get_probe_config` | Get probe JSON | JSON string |
| `extract_probe_endpoint` | Parse endpoint | "SCHEME PORT PATH" |
| `calculate_max_startup_time` | Max time | Seconds |
| `monitor_pod_health` | Continuous | N/A (runs forever) |
| `check_pod_exists` | Pod exists? | 0=yes, 1=no |
| `get_pod_status` | Pod phase | "Running", etc. |

### Status Code Meanings

| Code | Meaning | Action |
|------|---------|--------|
| `200` | ✅ Healthy | Continue |
| `404` | ⚠️ Wrong path | Check probe config |
| `500` | ❌ Server error | Check app logs |
| `503` | ⚠️ Not ready | Wait or check app |
| `000` | ❌ Connection failed | Check port/timeout |

### Troubleshooting Commands

```bash
# Check if library is sourced correctly
pod_health_check_lib_version

# Get help
pod_health_check_lib_help

# Test manually in Pod
kubectl exec -it pod-name -n namespace -- sh
nc -zv localhost 8080
openssl s_client -connect localhost:8443
```

### Integration Examples

#### In CI/CD (GitLab)
```yaml
deploy:
  script:
    - kubectl apply -f deployment.yaml
    - source ./pod_health_check_lib.sh
    - POD=$(kubectl get pods -n prod -l app=myapp -o name | head -1)
    - wait_for_pod_ready "$POD" "prod" "HTTPS" "8443" "/health" 60 2 "yes"
```

#### In Monitoring Script
```bash
#!/bin/bash
source ./pod_health_check_lib.sh

while true; do
    for POD in $(kubectl get pods -n prod -l app=myapp -o name); do
        check_pod_health "$POD" "prod" "HTTPS" "8443" "/health" >/dev/null || \
            alert "Pod $POD is unhealthy"
    done
    sleep 60
done
```

#### In Deployment Script
```bash
#!/bin/bash
source ./pod_health_check_lib.sh

kubectl apply -f deployment.yaml
kubectl rollout status deployment/myapp -n prod

# Verify all Pods are healthy
for POD in $(kubectl get pods -n prod -l app=myapp -o name); do
    if ! check_pod_health_with_retry "$POD" "prod" "HTTPS" "8443" "/health" 5 2 >/dev/null; then
        echo "Rollback: Pod $POD failed health check"
        kubectl rollout undo deployment/myapp -n prod
        exit 1
    fi
done

echo "Deployment successful and all Pods healthy"
```

---

## 📝 Changelog

### v1.0.0 (2024-12)
- Initial release
- Core health check functions
- Support for HTTP and HTTPS
- Retry and wait mechanisms
- Probe configuration extraction
- Comprehensive documentation

---

## 🤝 Contributing

Improvements and suggestions are welcome! Please:
1. Test your changes thoroughly
2. Update documentation
3. Add examples for new features
4. Follow existing code style

---

## 📄 License

This library is provided as-is for internal use. Feel free to modify and adapt to your needs.

---

**End of Document**
