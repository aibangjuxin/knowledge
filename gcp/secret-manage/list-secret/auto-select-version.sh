#!/bin/bash

################################################################################
# 智能版本选择脚本
# 功能：根据 Secret 数量自动选择最合适的审计脚本版本
# 使用：bash auto-select-version.sh [project-id]
################################################################################

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 获取项目 ID
PROJECT_ID=${1:-$(gcloud config get-value project 2>/dev/null)}

if [ -z "$PROJECT_ID" ]; then
    echo "错误: 无法获取项目 ID"
    echo "使用方法: $0 [project-id]"
    exit 1
fi

echo "========================================="
echo -e "${BLUE}智能版本选择${NC}"
echo "========================================="
echo "项目 ID: ${PROJECT_ID}"
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查脚本是否存在
check_script() {
    local script=$1
    if [ ! -f "${SCRIPT_DIR}/${script}" ]; then
        echo "错误: 脚本 ${script} 不存在"
        return 1
    fi
    return 0
}

echo -e "${GREEN}正在分析项目...${NC}"

# 获取 Secret 数量
echo "获取 Secret 列表..."
SECRET_COUNT=$(gcloud secrets list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null | wc -l | tr -d ' ')

if [ "$SECRET_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}未找到任何 Secret${NC}"
    exit 0
fi

echo -e "找到 ${CYAN}${SECRET_COUNT}${NC} 个 Secret"
echo ""

# 根据数量选择版本
echo "========================================="
echo -e "${GREEN}推荐方案${NC}"
echo "========================================="

if [ "$SECRET_COUNT" -lt 50 ]; then
    # 小规模：串行版
    SELECTED_SCRIPT="list-all-secrets-permissions.sh"
    REASON="Secret 数量较少，串行版本简单可靠"
    ESTIMATED_TIME="< 5 分钟"
    
elif [ "$SECRET_COUNT" -lt 300 ]; then
    # 中等规模：并行版
    SELECTED_SCRIPT="list-all-secrets-permissions-parallel.sh"
    PARALLEL_JOBS=20
    REASON="Secret 数量适中，并行版本平衡速度和稳定性"
    ESTIMATED_TIME="$(echo "scale=1; $SECRET_COUNT * 0.6 / 60" | bc) 分钟"
    
else
    # 大规模：最优版
    SELECTED_SCRIPT="list-all-secrets-optimized.sh"
    REASON="Secret 数量较多，最优版本提供最快速度"
    ESTIMATED_TIME="$(echo "scale=1; $SECRET_COUNT * 0.4 / 60" | bc) 分钟"
fi

echo "推荐版本: ${SELECTED_SCRIPT}"
echo "原因: ${REASON}"
echo "预计耗时: ${ESTIMATED_TIME}"
echo ""

# 检查脚本是否存在
if ! check_script "$SELECTED_SCRIPT"; then
    echo "请确保所有脚本文件都在 ${SCRIPT_DIR} 目录中"
    exit 1
fi

# 检查依赖
echo "========================================="
echo -e "${GREEN}检查依赖${NC}"
echo "========================================="

# 检查 gcloud
if command -v gcloud &> /dev/null; then
    echo -e "${GREEN}✓${NC} gcloud CLI"
else
    echo -e "${YELLOW}✗${NC} gcloud CLI 未安装"
    exit 1
fi

# 检查 jq (并行版和最优版需要)
if [[ "$SELECTED_SCRIPT" == *"parallel"* ]] || [[ "$SELECTED_SCRIPT" == *"optimized"* ]]; then
    if command -v jq &> /dev/null; then
        echo -e "${GREEN}✓${NC} jq"
    else
        echo -e "${YELLOW}⚠${NC} jq 未安装（推荐安装以获得最佳性能）"
        echo "  安装方法:"
        echo "    macOS: brew install jq"
        echo "    Ubuntu: sudo apt-get install jq"
        echo ""
        echo "  将使用串行版本替代..."
        SELECTED_SCRIPT="list-all-secrets-permissions.sh"
    fi
fi

# 检查 GNU parallel (可选)
if [[ "$SELECTED_SCRIPT" == *"parallel"* ]]; then
    if command -v parallel &> /dev/null; then
        echo -e "${GREEN}✓${NC} GNU parallel (可选，提供进度条)"
    else
        echo -e "${YELLOW}⚠${NC} GNU parallel 未安装（可选）"
        echo "  将使用 xargs 替代（功能相同，无进度条）"
    fi
fi

echo ""

# 询问用户是否继续
echo "========================================="
echo -e "${GREEN}准备执行${NC}"
echo "========================================="
echo "将要执行: ${SELECTED_SCRIPT}"

if [[ "$SELECTED_SCRIPT" == *"parallel"* ]]; then
    echo "并行任务数: ${PARALLEL_JOBS}"
fi

echo ""
read -p "是否继续? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# 执行选定的脚本
echo ""
echo "========================================="
echo -e "${GREEN}开始执行${NC}"
echo "========================================="
echo ""

cd "${SCRIPT_DIR}"

if [[ "$SELECTED_SCRIPT" == *"parallel"* ]]; then
    bash "${SELECTED_SCRIPT}" "${PROJECT_ID}" "${PARALLEL_JOBS}"
else
    bash "${SELECTED_SCRIPT}" "${PROJECT_ID}"
fi

# 显示结果
echo ""
echo "========================================="
echo -e "${GREEN}执行完成${NC}"
echo "========================================="
echo ""
echo "提示:"
echo "  - 查看汇总报告: cat secret-audit-*/summary.txt"
echo "  - 使用 Excel 打开: open secret-audit-*/secrets-permissions.csv"
echo "  - 查看 HTML 报告: open secret-audit-*/report.html"
echo ""
