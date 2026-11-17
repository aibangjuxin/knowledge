#!/bin/bash

################################################################################
# 快速测试脚本 - 验证修复是否生效
################################################################################

echo "=========================================="
echo "快速测试：验证计数器修复"
echo "=========================================="
echo ""

# 模拟脚本的 set -euo pipefail 环境
set -euo pipefail

echo "1. 测试变量初始化"
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0
echo "   ✓ 变量初始化成功"
echo ""

echo "2. 测试计数器递增（新方式）"
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
echo "   TOTAL_CHECKS = $TOTAL_CHECKS"

PASSED_CHECKS=$((PASSED_CHECKS + 1))
echo "   PASSED_CHECKS = $PASSED_CHECKS"

WARNING_CHECKS=$((WARNING_CHECKS + 1))
echo "   WARNING_CHECKS = $WARNING_CHECKS"

FAILED_CHECKS=$((FAILED_CHECKS + 1))
echo "   FAILED_CHECKS = $FAILED_CHECKS"
echo "   ✓ 所有计数器递增成功"
echo ""

echo "3. 测试多次递增"
for i in {1..5}; do
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
done
echo "   TOTAL_CHECKS 经过 5 次递增 = $TOTAL_CHECKS"
echo "   ✓ 循环递增成功"
echo ""

echo "4. 测试在函数中使用"
test_function() {
    local local_counter=0
    local_counter=$((local_counter + 1))
    echo "   函数内计数器 = $local_counter"
}
test_function
echo "   ✓ 函数内递增成功"
echo ""

echo "5. 模拟实际使用场景"
simulate_check() {
    local check_name="$1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [[ "$check_name" == "success" ]]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        echo "   [✓] $check_name 检查"
    elif [[ "$check_name" == "warning" ]]; then
        WARNING_CHECKS=$((WARNING_CHECKS + 1))
        echo "   [⚠] $check_name 检查"
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        echo "   [✗] $check_name 检查"
    fi
}

simulate_check "success"
simulate_check "warning"
simulate_check "success"

echo ""
echo "   最终统计:"
echo "   - 总检查: $TOTAL_CHECKS"
echo "   - 通过: $PASSED_CHECKS"
echo "   - 警告: $WARNING_CHECKS"
echo "   - 失败: $FAILED_CHECKS"
echo "   ✓ 实际场景模拟成功"
echo ""

echo "=========================================="
echo "✅ 所有测试通过！"
echo "=========================================="
echo ""
echo "修复已生效，脚本不会因为计数器递增而退出。"
echo "现在可以安全地运行主脚本了。"
