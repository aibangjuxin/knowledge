# Shell Scripts Collection

Generated on: 2025-12-12 12:22:27
Directory: /Users/lex/git/knowledge/k8s/scripts

## `pod_exec.sh`

```bash
#!/bin/bash

# Set color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check parameters
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 -n <namespace> <deployment-name> [command]"
    echo "Example:"
    echo "  $0 -n default my-deployment              # Enter interactive shell"
    echo "  $0 -n default my-deployment /usr/bin/pip freeze  # Execute specified command"
    exit 1
fi

# Parse parameters
while getopts "n:" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG";;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND-1))
DEPLOYMENT=$1
COMMAND=${@:2}

echo -e "${BLUE}Finding first Pod for Deployment: ${DEPLOYMENT} in namespace ${NAMESPACE}${NC}\n"

# Extract app name from deployment name (remove -deployment suffix)
app_name=${DEPLOYMENT%-deployment}

# Get the first pod
POD=$(kubectl get pods -n ${NAMESPACE} -l app=${app_name} --no-headers -o custom-columns=":metadata.name" | head -n 1)

if [ -z "$POD" ]; then
    echo -e "${YELLOW}Error: No Pod found for Deployment ${DEPLOYMENT} in namespace ${NAMESPACE}${NC}"
    exit 1
fi

echo -e "${GREEN}Pod found: ${POD}${NC}"

# If no command provided, enter interactive shell, otherwise execute the specified command
if [ -z "$COMMAND" ]; then
    echo -e "${BLUE}Entering interactive shell in Pod...${NC}"
    kubectl exec -it ${POD} -n ${NAMESPACE} -- sh -c "(bash || ash || sh)"
else
    echo -e "${BLUE}Executing command: ${COMMAND}${NC}"
    kubectl exec ${POD} -n ${NAMESPACE} -- $COMMAND
fi
```

## `pod_measure_startup.sh`

```bash
#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 检查参数
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 -n <namespace> <pod-name>"
    echo "Example: $0 -n default my-api-pod-abc123"
    exit 1
fi

# 解析参数
while getopts "n:" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG";;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND-1))
POD_NAME=$1

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}测量 Pod 启动时间: ${POD_NAME} (命名空间: ${NAMESPACE})${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# 1. 获取 Pod 基本信息
echo -e "${YELLOW}📋 步骤 1: 获取 Pod 基本信息${NC}"
START_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.startTime}' 2>/dev/null)
CONTAINER_START=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)

if [ -z "$CONTAINER_START" ]; then
    echo -e "${RED}❌ 错误: 容器尚未启动或 Pod 不存在${NC}"
    exit 1
fi

echo -e "${GREEN}   Pod 创建时间:${NC} ${START_TIME}"
echo -e "${GREEN}   容器启动时间:${NC} ${CONTAINER_START}"

# 2. 获取就绪探针配置
echo -e "\n${YELLOW}📋 步骤 2: 分析就绪探针配置${NC}"
READINESS_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].readinessProbe}' 2>/dev/null)

if [ -z "$READINESS_PROBE" ]; then
    echo -e "${RED}❌ 错误: 未找到就绪探针配置${NC}"
    exit 1
fi

echo -e "${GREEN}   就绪探针配置:${NC}"
echo "$READINESS_PROBE" | jq '.'

# 3. 提取探针参数
PROBE_SCHEME=$(echo "$READINESS_PROBE" | jq -r '.httpGet.scheme // "HTTP"')
PROBE_PORT=$(echo "$READINESS_PROBE" | jq -r '.httpGet.port // 8080')
PROBE_PATH=$(echo "$READINESS_PROBE" | jq -r '.httpGet.path // "/health"')
INITIAL_DELAY=$(echo "$READINESS_PROBE" | jq -r '.initialDelaySeconds // 0')
PERIOD=$(echo "$READINESS_PROBE" | jq -r '.periodSeconds // 10')
FAILURE_THRESHOLD=$(echo "$READINESS_PROBE" | jq -r '.failureThreshold // 3')

echo -e "\n${GREEN}   提取的探针参数:${NC}"
echo "   - Scheme: ${PROBE_SCHEME}"
echo "   - Port: ${PROBE_PORT}"
echo "   - Path: ${PROBE_PATH}"
echo "   - Initial Delay: ${INITIAL_DELAY}s"
echo "   - Period: ${PERIOD}s"
echo "   - Failure Threshold: ${FAILURE_THRESHOLD}"

# 4. 计算容器启动时间戳
if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CONTAINER_START" "+%s" 2>/dev/null)
else
    START_TIME_SEC=$(date -d "$CONTAINER_START" "+%s" 2>/dev/null)
fi

if [ -z "$START_TIME_SEC" ]; then
    echo -e "${RED}❌ 错误: 无法解析容器启动时间${NC}"
    exit 1
fi

echo -e "\n${YELLOW}⏱️  步骤 3: 开始探测健康检查端点${NC}"
echo -e "${GREEN}   目标: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}${NC}"
echo ""

# 5. 循环探测直到成功
PROBE_COUNT=0
MAX_PROBES=180  # 最多探测 3 分钟

while [ $PROBE_COUNT -lt $MAX_PROBES ]; do
    PROBE_COUNT=$((PROBE_COUNT + 1))
    
    # 根据协议选择探测方式
    if [[ "$PROBE_SCHEME" == "HTTPS" ]]; then
        # 使用 openssl 探测 HTTPS (忽略证书验证)
        HTTP_RESPONSE=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- sh -c "echo -e 'GET ${PROBE_PATH} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' | openssl s_client -connect localhost:${PROBE_PORT} -quiet -verify_return_error 2>/dev/null" 2>/dev/null || echo "")
        
        # 提取 HTTP 状态码
        HTTP_CODE=$(echo "$HTTP_RESPONSE" | grep -oP 'HTTP/[0-9.]+ \K[0-9]+' | head -1)
        
        # 如果没有提取到状态码，尝试另一种方式
        if [ -z "$HTTP_CODE" ]; then
            HTTP_CODE="000"
        fi
    else
        # 使用 openssl 探测 HTTP (通过 TCP 连接)
        HTTP_RESPONSE=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- sh -c "echo -e 'GET ${PROBE_PATH} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' | timeout 2 nc localhost ${PROBE_PORT}" 2>/dev/null || echo "")
        
        # 提取 HTTP 状态码
        HTTP_CODE=$(echo "$HTTP_RESPONSE" | grep -oP 'HTTP/[0-9.]+ \K[0-9]+' | head -1)
        
        if [ -z "$HTTP_CODE" ]; then
            HTTP_CODE="000"
        fi
    fi
    
    CURRENT_TIME_SEC=$(date +%s)
    ELAPSED=$((CURRENT_TIME_SEC - START_TIME_SEC))
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        echo -e "${GREEN}✅ 健康检查通过 (HTTP 200 OK)!${NC}"
        echo ""
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}📊 最终结果 (Result)${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}应用程序启动耗时:${NC} ${ELAPSED} 秒"
        echo -e "${GREEN}探测次数:${NC} ${PROBE_COUNT}"
        echo ""
        
        # 6. 分析当前配置
        echo -e "${YELLOW}📋 当前探针配置分析:${NC}"
        CURRENT_MAX_TIME=$((INITIAL_DELAY + PERIOD * FAILURE_THRESHOLD))
        echo "   - 当前配置允许的最大启动时间: ${CURRENT_MAX_TIME} 秒"
        echo "   - 实际启动时间: ${ELAPSED} 秒"
        
        if [ $ELAPSED -gt $CURRENT_MAX_TIME ]; then
            echo -e "   ${RED}⚠️  警告: 实际启动时间超过当前配置!${NC}"
        else
            echo -e "   ${GREEN}✓ 当前配置足够${NC}"
        fi
        
        echo ""
        echo -e "${YELLOW}💡 建议的优化配置:${NC}"
        echo "   readinessProbe:"
        echo "     httpGet:"
        echo "       path: ${PROBE_PATH}"
        echo "       port: ${PROBE_PORT}"
        echo "       scheme: ${PROBE_SCHEME}"
        echo "     initialDelaySeconds: 0"
        echo "     periodSeconds: ${PERIOD}"
        
        # 计算建议的 failureThreshold (实际时间 * 1.5 / period + 1)
        RECOMMENDED_THRESHOLD=$(echo "scale=0; ($ELAPSED * 1.5 / $PERIOD) + 1" | bc)
        echo "     failureThreshold: ${RECOMMENDED_THRESHOLD}"
        
        echo ""
        echo -e "${YELLOW}📋 或者使用 startupProbe (推荐):${NC}"
        echo "   startupProbe:"
        echo "     httpGet:"
        echo "       path: ${PROBE_PATH}"
        echo "       port: ${PROBE_PORT}"
        echo "       scheme: ${PROBE_SCHEME}"
        echo "     initialDelaySeconds: 0"
        echo "     periodSeconds: 10"
        echo "     failureThreshold: ${RECOMMENDED_THRESHOLD}"
        echo "   readinessProbe:"
        echo "     httpGet:"
        echo "       path: ${PROBE_PATH}"
        echo "       port: ${PROBE_PORT}"
        echo "       scheme: ${PROBE_SCHEME}"
        echo "     initialDelaySeconds: 0"
        echo "     periodSeconds: 5"
        echo "     failureThreshold: 3"
        
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        break
    else
        echo -e "   [${PROBE_COUNT}] 仍在启动中... (耗时: ${ELAPSED}s, 状态码: ${HTTP_CODE})"
        sleep 2
    fi
done

if [ $PROBE_COUNT -ge $MAX_PROBES ]; then
    echo -e "\n${RED}❌ 超时: 探测超过 ${MAX_PROBES} 次仍未成功${NC}"
    exit 1
fi

```

## `pod_status.sh`

```bash
#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查参数
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 -n <namespace> <deployment-name>"
    exit 1
fi

# 解析参数
while getopts "n:" opt; do
    case $opt in
        n) NAMESPACE="$OPTARG";;
        *) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done
shift $((OPTIND-1))
DEPLOYMENT=$1

echo -e "${BLUE}分析 Deployment: ${DEPLOYMENT} 在命名空间: ${NAMESPACE} 中的 Pod 状态${NC}\n"

# 获取所有相关的 pods
PODS=$(kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT} --no-headers -o custom-columns=":metadata.name")

for POD in ${PODS}; do
    echo -e "${YELLOW}Pod: ${POD}${NC}"
    
    # 获取 Pod 详细信息
    START_TIME=$(kubectl get pod ${POD} -n ${NAMESPACE} -o jsonpath='{.status.startTime}')
    CONTAINER_START=$(kubectl get pod ${POD} -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}')
    
    # 获取探针配置
    STARTUP_PROBE=$(kubectl get pod ${POD} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].startupProbe}')
    READINESS_PROBE=$(kubectl get pod ${POD} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].readinessProbe}')
    LIVENESS_PROBE=$(kubectl get pod ${POD} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].livenessProbe}')
    
    # 获取 Pod 事件
    EVENTS=$(kubectl get events -n ${NAMESPACE} --field-selector involvedObject.name=${POD} --sort-by='.lastTimestamp' -o json)
    
    echo "时间线分析:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}1. Pod 创建时间:${NC} ${START_TIME}"
    echo -e "${GREEN}2. 容器启动时间:${NC} ${CONTAINER_START}"
    
    # 分析探针配置
    echo -e "\n探针配置:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ ! -z "$STARTUP_PROBE" ]; then
        echo -e "${GREEN}启动探针:${NC}"
        kubectl get pod ${POD} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].startupProbe}' | jq '.'
    fi
    
    if [ ! -z "$READINESS_PROBE" ]; then
        echo -e "${GREEN}就绪探针:${NC}"
        kubectl get pod ${POD} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].readinessProbe}' | jq '.'
    fi
    
    if [ ! -z "$LIVENESS_PROBE" ]; then
        echo -e "${GREEN}存活探针:${NC}"
        kubectl get pod ${POD} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].livenessProbe}' | jq '.'
    fi
    
    # 分析关键事件
    echo -e "\n关键事件时间线:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$EVENTS" | jq -r '.items[] | select(.reason == "Scheduled" or .reason == "Started" or .reason == "Created" or .reason == "Pulled") | "\(.lastTimestamp) [\(.reason)] \(.message)"' | sort
    
    # 获取当前状态
    READY_STATUS=$(kubectl get pod ${POD} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")]}')
    
    echo -e "\n当前状态:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$READY_STATUS" | jq '.'
    
    echo -e "\n${BLUE}服务可用性分析:${NC}"
    READY_TIME=$(echo "$READY_STATUS" | jq -r '.lastTransitionTime')
    # 时间计算部分的修改
    if [ ! -z "$START_TIME" ] && [ ! -z "$READY_TIME" ]; then
        # 将 UTC 时间转换为时间戳
        START_SECONDS=$(date -d "$(echo $START_TIME | sed 's/Z$//')" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo $START_TIME | sed 's/Z$//')" +%s)
        READY_SECONDS=$(date -d "$(echo $READY_TIME | sed 's/Z$//')" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo $READY_TIME | sed 's/Z$//')" +%s)
        
        if [ ! -z "$START_SECONDS" ] && [ ! -z "$READY_SECONDS" ]; then
            TOTAL_SECONDS=$((READY_SECONDS - START_SECONDS))
            echo "从 Pod 创建到就绪总共耗时: ${TOTAL_SECONDS} 秒"
            
            # 添加更详细的时间信息
            echo "Pod 创建时间: $(date -d "@$START_SECONDS" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $START_SECONDS '+%Y-%m-%d %H:%M:%S')"
            echo "Pod 就绪时间: $(date -d "@$READY_SECONDS" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $READY_SECONDS '+%Y-%m-%d %H:%M:%S')"
        else
            echo "时间计算失败: 无法解析时间格式"
        fi
    else
        echo "时间计算失败: 缺少必要的时间信息"
    fi
    echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
done
```

## `pod-system-version.sh`

```bash
#!/bin/bash

# 脚本名称: check-pod-versions-concurrent.sh
# 用途: 并发查询 GKE 中每个 Deployment 的 Pod 系统版本

set -e

# 默认值
NAMESPACE="default"
MAX_JOBS=10

# 使用说明
usage() {
  cat <<EOF
使用方法: $0 [选项]

选项:
    -n NAMESPACE    指定 Kubernetes namespace (默认: default)
    -j JOBS         最大并发任务数 (默认: 10)
    -h              显示此帮助信息

示例:
    $0 -n production
    $0 -n staging -j 20
EOF
  exit 1
}

# 解析命令行参数
while getopts "n:j:h" opt; do
  case $opt in
  n)
    NAMESPACE="$OPTARG"
    ;;
  j)
    MAX_JOBS="$OPTARG"
    ;;
  h)
    usage
    ;;
  \?)
    echo "无效选项: -$OPTARG" >&2
    usage
    ;;
  esac
done

# 检查 kubectl 是否可用
if ! command -v kubectl &>/dev/null; then
  echo "错误: kubectl 未安装或不在 PATH 中"
  exit 1
fi

# 检查 namespace 是否存在
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "错误: Namespace '$NAMESPACE' 不存在"
  exit 1
fi

echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "查询时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "并发任务数: $MAX_JOBS"
echo "=========================================="
echo ""

# 创建临时目录和文件
TEMP_DIR=$(mktemp -d)
TEMP_FILE="$TEMP_DIR/results.txt"
LOCK_DIR="$TEMP_DIR/locks"
mkdir -p "$LOCK_DIR"

# 清理函数
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# 确定 Deployment 名称的函数
determine_deployment_name() {
  local pod_name="$1"
  local app_label="$2"
  local owner_name="$3"
  local deployment_name=""

  # 方法1: 从 owner reference 获取(适用于 ReplicaSet)
  if [[ "$owner_name" =~ ^(.+)-[a-z0-9]+$ ]]; then
    deployment_name="${BASH_REMATCH[1]}"
  fi

  # 方法2: 使用 app 标签
  if [ -z "$deployment_name" ] && [ -n "$app_label" ] && [ "$app_label" != "null" ]; then
    deployment_name="$app_label"
  fi

  # 方法3: 从 Pod 名称推断
  if [ -z "$deployment_name" ]; then
    if [[ "$pod_name" =~ ^(.+)-[a-z0-9]+-[a-z0-9]+$ ]]; then
      deployment_name="${BASH_REMATCH[1]}"
    else
      deployment_name="$pod_name"
    fi
  fi

  echo "$deployment_name"
}

# 查询单个 Pod 的函数
query_pod_version() {
  local pod_name="$1"
  local app_label="$2"
  local owner_name="$3"
  local namespace="$4"

  # 确定 Deployment 名称
  local deployment_name
  deployment_name=$(determine_deployment_name "$pod_name" "$app_label" "$owner_name")

  # 使用文件锁实现去重
  local lock_file="$LOCK_DIR/$deployment_name.lock"

  # 尝试创建锁文件(原子操作)
  if mkdir "$lock_file" 2>/dev/null; then
    # 成功创建锁,表示此 Deployment 未被处理

    # 执行查询
    local os_version
    os_version=$(kubectl exec -n "$namespace" "$pod_name" -- cat /etc/issue 2>/dev/null | head -n 1 | tr -d '\n' || echo "无法获取")

    # 清理版本信息
    os_version=$(echo "$os_version" | sed 's/\\[a-z]//g' | xargs)

    # 写入结果(使用追加模式并加锁)
    (
      flock -x 200
      echo "$deployment_name|$pod_name|$os_version" >>"$TEMP_FILE"
    ) 200>"$TEMP_FILE.lock"

  fi
  # 如果锁已存在,说明此 Deployment 已被其他进程处理,直接跳过
}

# 导出函数和变量供子进程使用
export -f determine_deployment_name
export -f query_pod_version
export TEMP_FILE
export LOCK_DIR
export NAMESPACE

# 获取所有 Running 状态的 Pod
PODS=$(kubectl get pods -n "$NAMESPACE" \
  --field-selector=status.phase=Running \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.app}{"\t"}{.metadata.ownerReferences[0].name}{"\n"}{end}')

# 检查是否有 Running 的 Pod
if [ -z "$PODS" ]; then
  echo "警告: 在 namespace '$NAMESPACE' 中没有找到 Running 状态的 Pod"
  exit 0
fi

# 并发处理每个 Pod
job_count=0
while IFS=$'\t' read -r pod_name app_label owner_name; do
  # 跳过空行
  [ -z "$pod_name" ] && continue

  # 后台执行查询
  query_pod_version "$pod_name" "$app_label" "$owner_name" "$NAMESPACE" &

  ((job_count++))

  # 控制并发数
  while [ "$(jobs -r | wc -l)" -ge "$MAX_JOBS" ]; do
    sleep 0.1
  done

done <<<"$PODS"

# 等待所有后台任务完成
wait

echo "处理了 $job_count 个 Pod"
echo ""

# 输出表头
printf "%-40s %-40s %-50s\n" "DEPLOYMENT" "POD" "OS VERSION"
printf "%-40s %-40s %-50s\n" "$(printf '%.0s-' {1..40})" "$(printf '%.0s-' {1..40})" "$(printf '%.0s-' {1..50})"

# 输出结果(按 Deployment 名称排序)
if [ -f "$TEMP_FILE" ]; then
  sort "$TEMP_FILE" | while IFS='|' read -r deployment pod version; do
    printf "%-40s %-40s %-50s\n" "$deployment" "$pod" "$version"
  done
else
  echo "没有收集到任何数据"
fi

echo ""
echo "查询完成!"

```

