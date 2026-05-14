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