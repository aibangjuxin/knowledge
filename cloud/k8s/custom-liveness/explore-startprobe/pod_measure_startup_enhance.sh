#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Pod 启动时间测量与探针配置优化工具                          ║${NC}"
echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Pod: ${POD_NAME}${NC}"
echo -e "${BLUE}║  Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"

# 1. 获取 Pod 基本信息
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 步骤 1/6: 获取 Pod 基本信息${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

POD_STATUS=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null)
START_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.startTime}' 2>/dev/null)
CONTAINER_START=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[0].state.running.startedAt}' 2>/dev/null)
CONTAINER_NAME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].name}' 2>/dev/null)
CONTAINER_IMAGE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].image}' 2>/dev/null)
NODE_NAME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.nodeName}' 2>/dev/null)

if [ -z "$CONTAINER_START" ]; then
    echo -e "${RED}❌ 错误: 容器尚未启动或 Pod 不存在${NC}"
    exit 1
fi

echo -e "${GREEN}   Pod 状态:${NC} ${POD_STATUS}"
echo -e "${GREEN}   容器名称:${NC} ${CONTAINER_NAME}"
echo -e "${GREEN}   容器镜像:${NC} ${CONTAINER_IMAGE}"
echo -e "${GREEN}   运行节点:${NC} ${NODE_NAME}"
echo -e "${GREEN}   Pod 创建时间:${NC} ${START_TIME}"
echo -e "${GREEN}   容器启动时间:${NC} ${CONTAINER_START}"

# 2. 获取所有探针配置
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 步骤 2/6: 分析探针配置${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

STARTUP_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].startupProbe}' 2>/dev/null)
READINESS_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].readinessProbe}' 2>/dev/null)
LIVENESS_PROBE=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].livenessProbe}' 2>/dev/null)

# 显示当前配置
echo -e "${YELLOW}📌 当前探针配置概览:${NC}"
echo ""

if [ -n "$STARTUP_PROBE" ] && [ "$STARTUP_PROBE" != "null" ]; then
    echo -e "${GREEN}   ✓ StartupProbe: 已配置${NC}"
    STARTUP_INITIAL=$(echo "$STARTUP_PROBE" | jq -r '.initialDelaySeconds // 0')
    STARTUP_PERIOD=$(echo "$STARTUP_PROBE" | jq -r '.periodSeconds // 10')
    STARTUP_FAILURE=$(echo "$STARTUP_PROBE" | jq -r '.failureThreshold // 3')
    STARTUP_MAX_TIME=$((STARTUP_INITIAL + STARTUP_PERIOD * STARTUP_FAILURE))
    echo -e "     - initialDelaySeconds: ${STARTUP_INITIAL}s"
    echo -e "     - periodSeconds: ${STARTUP_PERIOD}s"
    echo -e "     - failureThreshold: ${STARTUP_FAILURE}"
    echo -e "     ${MAGENTA}→ 最大允许启动时间: ${STARTUP_MAX_TIME}s${NC}"
else
    echo -e "${YELLOW}   ⚠ StartupProbe: 未配置${NC}"
fi

echo ""

if [ -n "$READINESS_PROBE" ] && [ "$READINESS_PROBE" != "null" ]; then
    echo -e "${GREEN}   ✓ ReadinessProbe: 已配置${NC}"
    READINESS_INITIAL=$(echo "$READINESS_PROBE" | jq -r '.initialDelaySeconds // 0')
    READINESS_PERIOD=$(echo "$READINESS_PROBE" | jq -r '.periodSeconds // 10')
    READINESS_FAILURE=$(echo "$READINESS_PROBE" | jq -r '.failureThreshold // 3')
    READINESS_MAX_TIME=$((READINESS_INITIAL + READINESS_PERIOD * READINESS_FAILURE))
    echo -e "     - initialDelaySeconds: ${READINESS_INITIAL}s"
    echo -e "     - periodSeconds: ${READINESS_PERIOD}s"
    echo -e "     - failureThreshold: ${READINESS_FAILURE}"
    if [ -z "$STARTUP_PROBE" ] || [ "$STARTUP_PROBE" == "null" ]; then
        echo -e "     ${MAGENTA}→ 最大允许启动时间: ${READINESS_MAX_TIME}s (无 StartupProbe 时)${NC}"
    fi
else
    echo -e "${RED}   ✗ ReadinessProbe: 未配置${NC}"
    exit 1
fi

echo ""

if [ -n "$LIVENESS_PROBE" ] && [ "$LIVENESS_PROBE" != "null" ]; then
    echo -e "${GREEN}   ✓ LivenessProbe: 已配置${NC}"
    LIVENESS_INITIAL=$(echo "$LIVENESS_PROBE" | jq -r '.initialDelaySeconds // 0')
    LIVENESS_PERIOD=$(echo "$LIVENESS_PROBE" | jq -r '.periodSeconds // 10')
    LIVENESS_FAILURE=$(echo "$LIVENESS_PROBE" | jq -r '.failureThreshold // 3')
    echo -e "     - initialDelaySeconds: ${LIVENESS_INITIAL}s"
    echo -e "     - periodSeconds: ${LIVENESS_PERIOD}s"
    echo -e "     - failureThreshold: ${LIVENESS_FAILURE}"
else
    echo -e "${YELLOW}   ⚠ LivenessProbe: 未配置${NC}"
fi

# 3. 提取探针参数（优先使用 ReadinessProbe）
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📋 步骤 3/6: 提取探针检测参数${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

PROBE_SCHEME=$(echo "$READINESS_PROBE" | jq -r '.httpGet.scheme // "HTTP"')
PROBE_PORT=$(echo "$READINESS_PROBE" | jq -r '.httpGet.port // 8080')
PROBE_PATH=$(echo "$READINESS_PROBE" | jq -r '.httpGet.path // "/health"')

echo -e "${GREEN}   探测端点信息:${NC}"
echo "   - Scheme: ${PROBE_SCHEME}"
echo "   - Port: ${PROBE_PORT}"
echo "   - Path: ${PROBE_PATH}"
echo -e "   ${MAGENTA}→ 完整 URL: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}${NC}"

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

# 5. 检查 Pod 是否已经 Ready
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}⏱️  步骤 4/6: 测量实际启动时间${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

READY_CONDITION=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
READY_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)

if [ "$READY_CONDITION" == "True" ] && [ -n "$READY_TIME" ] && [ "$READY_TIME" != "null" ]; then
    # Pod 已经 Ready，直接从 Kubernetes 状态计算
    echo -e "${GREEN}   ✓ Pod 已处于 Ready 状态${NC}"
    echo -e "${GREEN}   Ready 时间: ${READY_TIME}${NC}"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        READY_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$READY_TIME" "+%s" 2>/dev/null)
    else
        READY_TIME_SEC=$(date -d "$READY_TIME" "+%s" 2>/dev/null)
    fi
    
    STARTUP_TIME=$((READY_TIME_SEC - START_TIME_SEC))
    PROBE_COUNT=0
    MEASUREMENT_SOURCE="Kubernetes Ready 状态"
else
    # Pod 还未 Ready，需要实时探测
    echo -e "${YELLOW}   ⏳ Pod 尚未 Ready，开始实时探测...${NC}"
    echo -e "${GREEN}   目标: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}${NC}"
    echo ""
    
    PROBE_COUNT=0
    MAX_PROBES=180
    SCRIPT_START_TIME=$(date +%s)
    
    while [ $PROBE_COUNT -lt $MAX_PROBES ]; do
        PROBE_COUNT=$((PROBE_COUNT + 1))
        
        # 根据协议选择探测方式
        if [[ "$PROBE_SCHEME" == "HTTPS" ]]; then
            HTTP_STATUS_LINE=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PROBE_PATH}" | \
                kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "openssl s_client -connect localhost:${PROBE_PORT} -quiet 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
            HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
            if [ -z "$HTTP_CODE" ]; then
                HTTP_CODE="000"
            fi
        else
            HTTP_STATUS_LINE=$(printf "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" "${PROBE_PATH}" | \
                kubectl exec -i ${POD_NAME} -n ${NAMESPACE} -- sh -c "timeout 2 nc localhost ${PROBE_PORT} 2>&1 | grep -E 'HTTP/[0-9.]+ [0-9]+' | head -1" 2>/dev/null || echo "")
            HTTP_CODE=$(echo "$HTTP_STATUS_LINE" | awk '{print $2}')
            if [ -z "$HTTP_CODE" ]; then
                HTTP_CODE="000"
            fi
        fi
        
        CURRENT_TIME_SEC=$(date +%s)
        POD_AGE=$((CURRENT_TIME_SEC - START_TIME_SEC))
        
        if [[ "$HTTP_CODE" == "200" ]]; then
            echo -e "${GREEN}   ✅ 健康检查通过 (HTTP 200 OK)!${NC}"
            
            # 等待 Kubernetes 更新 Ready 状态
            sleep 2
            
            # 再次获取 Ready 时间
            READY_TIME=$(kubectl get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' 2>/dev/null)
            
            if [ -n "$READY_TIME" ] && [ "$READY_TIME" != "null" ]; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    READY_TIME_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$READY_TIME" "+%s" 2>/dev/null)
                else
                    READY_TIME_SEC=$(date -d "$READY_TIME" "+%s" 2>/dev/null)
                fi
                STARTUP_TIME=$((READY_TIME_SEC - START_TIME_SEC))
                MEASUREMENT_SOURCE="Kubernetes Ready 状态"
            else
                # Kubernetes 还没更新，使用探测时间估算
                STARTUP_TIME=$POD_AGE
                MEASUREMENT_SOURCE="实时探测估算"
            fi
            
            break
        else
            # 显示进度条
            PROGRESS_BAR=""
            PROGRESS_PERCENT=$((PROBE_COUNT * 100 / MAX_PROBES))
            FILLED=$((PROGRESS_PERCENT / 5))
            for i in $(seq 1 20); do
                if [ $i -le $FILLED ]; then
                    PROGRESS_BAR="${PROGRESS_BAR}█"
                else
                    PROGRESS_BAR="${PROGRESS_BAR}░"
                fi
            done
            echo -e "   [${PROBE_COUNT}/${MAX_PROBES}] ${PROGRESS_BAR} ${PROGRESS_PERCENT}% | Pod 运行: ${POD_AGE}s | 状态码: ${HTTP_CODE}"
            sleep 2
        fi
    done
    
    if [ $PROBE_COUNT -ge $MAX_PROBES ]; then
        echo -e "\n${RED}❌ 超时: 探测超过 ${MAX_PROBES} 次仍未成功${NC}"
        exit 1
    fi
fi

# 6. 显示测量结果
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📊 步骤 5/6: 启动时间分析${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "${GREEN}   ✅ 应用程序实际启动耗时: ${STARTUP_TIME} 秒${NC}"
echo -e "${GREEN}   📍 测量数据来源: ${MEASUREMENT_SOURCE}${NC}"
if [ $PROBE_COUNT -gt 0 ]; then
    echo -e "${GREEN}   🔍 探测次数: ${PROBE_COUNT}${NC}"
fi

# 时间线可视化
echo -e "\n${YELLOW}   ⏱️  启动时间线:${NC}"
echo "   ┌─────────────────────────────────────────────────────────┐"
echo "   │ 0s                                          ${STARTUP_TIME}s │"
echo "   │ ├───────────────────────────────────────────┤           │"
echo "   │ 容器启动                              应用就绪           │"
echo "   └─────────────────────────────────────────────────────────┘"

# 配置对比分析
echo -e "\n${YELLOW}   📊 配置对比分析:${NC}"

if [ -n "$STARTUP_PROBE" ] && [ "$STARTUP_PROBE" != "null" ]; then
    CURRENT_MAX_TIME=$STARTUP_MAX_TIME
    CONFIG_TYPE="StartupProbe"
else
    CURRENT_MAX_TIME=$READINESS_MAX_TIME
    CONFIG_TYPE="ReadinessProbe (无 StartupProbe)"
fi

echo -e "   当前配置类型: ${CONFIG_TYPE}"
echo -e "   当前允许的最大启动时间: ${CURRENT_MAX_TIME}s"
echo -e "   实际启动时间: ${STARTUP_TIME}s"

BUFFER_TIME=$((CURRENT_MAX_TIME - STARTUP_TIME))
if [ $STARTUP_TIME -gt $CURRENT_MAX_TIME ]; then
    echo -e "   ${RED}⚠️  风险: 实际启动时间超过配置 $((STARTUP_TIME - CURRENT_MAX_TIME))s!${NC}"
    echo -e "   ${RED}   Pod 可能会被 Kubernetes 误判为启动失败并重启${NC}"
elif [ $BUFFER_TIME -lt 10 ]; then
    echo -e "   ${YELLOW}⚠️  警告: 缓冲时间不足 (仅 ${BUFFER_TIME}s)${NC}"
    echo -e "   ${YELLOW}   建议增加缓冲以应对启动时间波动${NC}"
else
    echo -e "   ${GREEN}✓ 配置合理，缓冲时间: ${BUFFER_TIME}s${NC}"
fi

# 7. 配置建议
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}💡 步骤 6/6: 配置优化建议${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 计算建议的 failureThreshold (实际时间 * 1.5 / period + 1)
RECOMMENDED_STARTUP_PERIOD=10
RECOMMENDED_READINESS_PERIOD=5
RECOMMENDED_STARTUP_THRESHOLD=$(echo "scale=0; ($STARTUP_TIME * 1.5 / $RECOMMENDED_STARTUP_PERIOD) + 1" | bc)
RECOMMENDED_READINESS_THRESHOLD=3

echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  方案 1: 使用 StartupProbe + ReadinessProbe (推荐)           ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}优势:${NC}"
echo "  • 启动阶段和运行阶段分离，更精确的健康检查"
echo "  • StartupProbe 允许较长的启动时间"
echo "  • ReadinessProbe 快速响应运行时状态变化"
echo "  • 避免启动慢的应用被误判为不健康"
echo ""
echo -e "${CYAN}配置示例:${NC}"
echo ""
echo "  startupProbe:"
echo "    httpGet:"
echo "      path: ${PROBE_PATH}"
echo "      port: ${PROBE_PORT}"
echo "      scheme: ${PROBE_SCHEME}"
echo "    initialDelaySeconds: 0"
echo "    periodSeconds: ${RECOMMENDED_STARTUP_PERIOD}"
echo "    failureThreshold: ${RECOMMENDED_STARTUP_THRESHOLD}"
echo -e "    ${MAGENTA}# 最大启动时间: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s (实际: ${STARTUP_TIME}s × 1.5 倍缓冲)${NC}"
echo ""
echo "  readinessProbe:"
echo "    httpGet:"
echo "      path: ${PROBE_PATH}"
echo "      port: ${PROBE_PORT}"
echo "      scheme: ${PROBE_SCHEME}"
echo "    initialDelaySeconds: 0"
echo "    periodSeconds: ${RECOMMENDED_READINESS_PERIOD}"
echo "    failureThreshold: ${RECOMMENDED_READINESS_THRESHOLD}"
echo -e "    ${MAGENTA}# 运行时快速检测，最多 $((RECOMMENDED_READINESS_PERIOD * RECOMMENDED_READINESS_THRESHOLD))s 标记为 NotReady${NC}"

if [ -n "$LIVENESS_PROBE" ] && [ "$LIVENESS_PROBE" != "null" ]; then
    echo ""
    echo "  livenessProbe:"
    echo "    httpGet:"
    echo "      path: ${PROBE_PATH}"
    echo "      port: ${PROBE_PORT}"
    echo "      scheme: ${PROBE_SCHEME}"
    echo "    initialDelaySeconds: 0"
    echo "    periodSeconds: 10"
    echo "    failureThreshold: 3"
    echo -e "    ${MAGENTA}# 检测死锁等严重问题，30s 后重启容器${NC}"
fi

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  方案 2: 仅使用 ReadinessProbe (简单场景)                    ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}适用场景:${NC}"
echo "  • 应用启动时间稳定且较短 (< 30s)"
echo "  • 不需要区分启动阶段和运行阶段"
echo ""
echo -e "${CYAN}配置示例:${NC}"
echo ""
echo "  readinessProbe:"
echo "    httpGet:"
echo "      path: ${PROBE_PATH}"
echo "      port: ${PROBE_PORT}"
echo "      scheme: ${PROBE_SCHEME}"
echo "    initialDelaySeconds: 0"
echo "    periodSeconds: ${RECOMMENDED_STARTUP_PERIOD}"
echo "    failureThreshold: ${RECOMMENDED_STARTUP_THRESHOLD}"
echo -e "    ${MAGENTA}# 最大启动时间: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s${NC}"

# 对比表格
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  配置对比总结                                                  ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
printf "  %-20s %-20s %-20s\n" "项目" "当前配置" "推荐配置"
echo "  ────────────────────────────────────────────────────────────"

if [ -n "$STARTUP_PROBE" ] && [ "$STARTUP_PROBE" != "null" ]; then
    printf "  %-20s %-20s %-20s\n" "StartupProbe" "已配置" "优化参数"
    printf "  %-20s %-20s %-20s\n" "  - Period" "${STARTUP_PERIOD}s" "${RECOMMENDED_STARTUP_PERIOD}s"
    printf "  %-20s %-20s %-20s\n" "  - Threshold" "${STARTUP_FAILURE}" "${RECOMMENDED_STARTUP_THRESHOLD}"
    printf "  %-20s %-20s %-20s\n" "  - 最大时间" "${STARTUP_MAX_TIME}s" "$((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s"
else
    printf "  %-20s %-20s %-20s\n" "StartupProbe" "未配置" "建议添加"
fi

printf "  %-20s %-20s %-20s\n" "ReadinessProbe" "已配置" "优化参数"
printf "  %-20s %-20s %-20s\n" "  - Period" "${READINESS_PERIOD}s" "${RECOMMENDED_READINESS_PERIOD}s"
printf "  %-20s %-20s %-20s\n" "  - Threshold" "${READINESS_FAILURE}" "${RECOMMENDED_READINESS_THRESHOLD}"

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  关键指标总结                                                  ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✓${NC} 实际启动时间: ${STARTUP_TIME}s"
echo -e "  ${GREEN}✓${NC} 推荐最大启动时间: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD))s (1.5倍缓冲)"
echo -e "  ${GREEN}✓${NC} 缓冲时间: $((RECOMMENDED_STARTUP_PERIOD * RECOMMENDED_STARTUP_THRESHOLD - STARTUP_TIME))s"
echo -e "  ${GREEN}✓${NC} 探测端点: ${PROBE_SCHEME}://localhost:${PROBE_PORT}${PROBE_PATH}"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  分析完成！请根据以上建议优化您的 Pod 配置                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
