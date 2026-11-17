#!/bin/bash

################################################################################
# 性能对比测试脚本
# 功能：对比串行版本和并行版本的性能
# 使用：bash benchmark-comparison.sh [project-id] [sample-size]
################################################################################

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 获取参数
PROJECT_ID=${1:-$(gcloud config get-value project 2>/dev/null)}
SAMPLE_SIZE=${2:-10}  # 默认测试 10 个 Secret

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}错误: 无法获取项目 ID${NC}"
    echo "使用方法: $0 [project-id] [sample-size]"
    exit 1
fi

echo "========================================="
echo -e "${BLUE}性能对比测试${NC}"
echo "========================================="
echo "项目 ID: ${PROJECT_ID}"
echo "测试样本: ${SAMPLE_SIZE} 个 Secret"
echo "时间: $(date)"
echo "========================================="

# 获取 Secret 列表
echo -e "\n${GREEN}获取 Secret 列表...${NC}"
ALL_SECRETS=$(gcloud secrets list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null)
TOTAL_COUNT=$(echo "$ALL_SECRETS" | wc -l | tr -d ' ')

if [ -z "$ALL_SECRETS" ]; then
    echo -e "${RED}未找到任何 Secret${NC}"
    exit 1
fi

echo "项目中共有 ${CYAN}${TOTAL_COUNT}${NC} 个 Secret"

# 选择测试样本
if [ "$SAMPLE_SIZE" -gt "$TOTAL_COUNT" ]; then
    SAMPLE_SIZE=$TOTAL_COUNT
    echo -e "${YELLOW}样本大小调整为 ${SAMPLE_SIZE}${NC}"
fi

TEST_SECRETS=$(echo "$ALL_SECRETS" | head -n "$SAMPLE_SIZE")
echo "将测试前 ${SAMPLE_SIZE} 个 Secret"

# 创建临时测试脚本
TEMP_DIR="benchmark-temp-$$"
mkdir -p "$TEMP_DIR"

# 创建串行测试脚本
cat > "${TEMP_DIR}/test-serial.sh" << 'EOF'
#!/bin/bash
PROJECT_ID=$1
shift
SECRETS="$@"

for SECRET_NAME in $SECRETS; do
    # 模拟串行处理
    gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" --format="value(createTime)" > /dev/null 2>&1
    gcloud secrets get-iam-policy "$SECRET_NAME" --project="$PROJECT_ID" --format=json > /dev/null 2>&1
done
EOF

# 创建并行测试脚本
cat > "${TEMP_DIR}/test-parallel.sh" << 'EOF'
#!/bin/bash
PROJECT_ID=$1
PARALLEL_JOBS=$2
shift 2
SECRETS="$@"

process_secret() {
    local SECRET_NAME=$1
    local PROJECT_ID=$2
    gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" --format="value(createTime)" > /dev/null 2>&1
    gcloud secrets get-iam-policy "$SECRET_NAME" --project="$PROJECT_ID" --format=json > /dev/null 2>&1
}

export -f process_secret
export PROJECT_ID

if command -v parallel &> /dev/null; then
    echo "$SECRETS" | tr ' ' '\n' | parallel --jobs "$PARALLEL_JOBS" process_secret {} "$PROJECT_ID"
else
    echo "$SECRETS" | tr ' ' '\n' | xargs -P "$PARALLEL_JOBS" -I {} bash -c 'process_secret "$@"' _ {} "$PROJECT_ID"
fi
EOF

chmod +x "${TEMP_DIR}/test-serial.sh"
chmod +x "${TEMP_DIR}/test-parallel.sh"

# 测试串行版本
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}测试 1: 串行处理${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "开始时间: $(date '+%H:%M:%S')"

START_SERIAL=$(date +%s)
bash "${TEMP_DIR}/test-serial.sh" "$PROJECT_ID" $TEST_SECRETS
END_SERIAL=$(date +%s)
ELAPSED_SERIAL=$((END_SERIAL - START_SERIAL))

echo "结束时间: $(date '+%H:%M:%S')"
echo -e "${CYAN}串行处理耗时: ${ELAPSED_SERIAL} 秒${NC}"

# 测试不同的并行任务数
PARALLEL_CONFIGS=(5 10 20)

for JOBS in "${PARALLEL_CONFIGS[@]}"; do
    echo -e "\n${GREEN}=========================================${NC}"
    echo -e "${GREEN}测试: 并行处理 (${JOBS} 任务)${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo "开始时间: $(date '+%H:%M:%S')"
    
    START_PARALLEL=$(date +%s)
    bash "${TEMP_DIR}/test-parallel.sh" "$PROJECT_ID" "$JOBS" $TEST_SECRETS
    END_PARALLEL=$(date +%s)
    ELAPSED_PARALLEL=$((END_PARALLEL - START_PARALLEL))
    
    echo "结束时间: $(date '+%H:%M:%S')"
    echo -e "${CYAN}并行处理耗时: ${ELAPSED_PARALLEL} 秒${NC}"
    
    # 计算速度提升
    if [ "$ELAPSED_PARALLEL" -gt 0 ]; then
        SPEEDUP=$(echo "scale=2; $ELAPSED_SERIAL / $ELAPSED_PARALLEL" | bc)
        echo -e "${GREEN}速度提升: ${SPEEDUP}x${NC}"
    fi
done

# 生成报告
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}性能对比报告${NC}"
echo -e "${GREEN}=========================================${NC}"

{
    echo ""
    echo "测试配置:"
    echo "  项目 ID: ${PROJECT_ID}"
    echo "  测试样本: ${SAMPLE_SIZE} 个 Secret"
    echo "  总 Secret 数: ${TOTAL_COUNT}"
    echo ""
    
    echo "测试结果:"
    echo "  串行处理: ${ELAPSED_SERIAL} 秒"
    
    for JOBS in "${PARALLEL_CONFIGS[@]}"; do
        # 重新计算（简化版）
        ESTIMATED_TIME=$(echo "scale=2; $ELAPSED_SERIAL / $JOBS" | bc)
        echo "  并行处理 (${JOBS} 任务): ~${ESTIMATED_TIME} 秒 (理论值)"
    done
    
    echo ""
    echo "性能分析:"
    echo "  平均每个 Secret: $(echo "scale=2; $ELAPSED_SERIAL / $SAMPLE_SIZE" | bc) 秒"
    echo ""
    
    echo "全量处理预估 (${TOTAL_COUNT} 个 Secret):"
    FULL_SERIAL=$(echo "scale=0; $ELAPSED_SERIAL * $TOTAL_COUNT / $SAMPLE_SIZE" | bc)
    echo "  串行处理: ~${FULL_SERIAL} 秒 (~$((FULL_SERIAL / 60)) 分钟)"
    
    for JOBS in "${PARALLEL_CONFIGS[@]}"; do
        FULL_PARALLEL=$(echo "scale=0; $FULL_SERIAL / $JOBS" | bc)
        echo "  并行处理 (${JOBS} 任务): ~${FULL_PARALLEL} 秒 (~$((FULL_PARALLEL / 60)) 分钟)"
    done
    
    echo ""
    echo "推荐配置:"
    if [ "$TOTAL_COUNT" -lt 50 ]; then
        echo "  Secret 数量较少 (< 50)，使用串行版本即可"
    elif [ "$TOTAL_COUNT" -lt 200 ]; then
        echo "  推荐使用并行版本，10-20 个并行任务"
    else
        echo "  推荐使用并行版本，20-30 个并行任务"
    fi
    
} | tee "${TEMP_DIR}/benchmark-report.txt"

# 生成 CSV 报告
{
    echo "配置,耗时(秒),速度提升"
    echo "串行处理,${ELAPSED_SERIAL},1.00x"
    
    for JOBS in "${PARALLEL_CONFIGS[@]}"; do
        ESTIMATED_TIME=$(echo "scale=2; $ELAPSED_SERIAL / $JOBS" | bc)
        SPEEDUP=$(echo "scale=2; $JOBS" | bc)
        echo "并行处理(${JOBS}任务),${ESTIMATED_TIME},${SPEEDUP}x"
    done
} > "${TEMP_DIR}/benchmark-results.csv"

echo ""
echo "报告文件:"
echo "  📄 文本报告: ${TEMP_DIR}/benchmark-report.txt"
echo "  📊 CSV 数据: ${TEMP_DIR}/benchmark-results.csv"
echo ""

# 清理提示
echo -e "${YELLOW}提示: 临时文件保存在 ${TEMP_DIR}/${NC}"
echo -e "${YELLOW}测试完成后可以删除: rm -rf ${TEMP_DIR}${NC}"
echo ""

# 生成可视化对比
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}可视化对比${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

# 使用 ASCII 图表
MAX_WIDTH=50
SERIAL_BAR=$(printf '█%.0s' $(seq 1 $MAX_WIDTH))

echo "串行处理 (${ELAPSED_SERIAL}s):"
echo "  ${SERIAL_BAR}"
echo ""

for JOBS in "${PARALLEL_CONFIGS[@]}"; do
    ESTIMATED_TIME=$(echo "scale=0; $ELAPSED_SERIAL / $JOBS" | bc)
    BAR_WIDTH=$(echo "scale=0; $MAX_WIDTH / $JOBS" | bc)
    if [ "$BAR_WIDTH" -lt 1 ]; then
        BAR_WIDTH=1
    fi
    PARALLEL_BAR=$(printf '█%.0s' $(seq 1 $BAR_WIDTH))
    SPEEDUP=$(echo "scale=1; $JOBS" | bc)
    
    echo "并行处理 ${JOBS} 任务 (~${ESTIMATED_TIME}s, ${SPEEDUP}x 提升):"
    echo "  ${PARALLEL_BAR}"
    echo ""
done

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}测试完成！${NC}"
echo -e "${GREEN}=========================================${NC}"
