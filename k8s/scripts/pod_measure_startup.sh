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
        # 直接在 Pod 内执行命令并提取状态行
        # echo -e "GET /apiname/v1.28.0/.well-known/health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | openssl s_client -connect localhost:8443 -quiet 2>&1 | grep -E "HTTP/[0-9.]+ [0-9]+" | head -1
        HTTP_STATUS_LINE=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- sh -c "echo -e \"GET ${PROBE_PATH} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n\" | openssl s_client -connect localhost:${PROBE_PORT} -quiet 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
        
        # 提取 HTTP 状态码
        HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
        
        # 如果没有提取到状态码，设置为 000
        if [ -z "$HTTP_CODE" ]; then
            HTTP_CODE="000"
        fi
    else
        # 使用 nc 探测 HTTP (通过 TCP 连接)
        HTTP_STATUS_LINE=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- sh -c "echo -e \"GET ${PROBE_PATH} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n\" | timeout 2 nc localhost ${PROBE_PORT} 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
        
        # 提取 HTTP 状态码
        HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
        
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
