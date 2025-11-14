#!/bin/bash

################################################################################
# 测试脚本：验证计数器修复
# 用途：验证 set -e 环境下的计数器是否正常工作
################################################################################

echo "========================================="
echo "测试计数器修复"
echo "========================================="

# 测试 1: 问题代码（会退出）
echo -e "\n测试 1: 问题代码 ((COUNT++))"
echo "----------------------------------------"
(
    set -e
    COUNT=0
    echo "COUNT 初始值: $COUNT"
    ((COUNT++)) 2>/dev/null
    echo "COUNT 递增后: $COUNT"
    echo "✓ 这行不应该执行"
) && echo "✓ 成功" || echo "✗ 失败（预期行为：脚本退出）"

# 测试 2: 修复后的代码（正常）
echo -e "\n测试 2: 修复后的代码 COUNT=\$((COUNT + 1))"
echo "----------------------------------------"
(
    set -e
    COUNT=0
    echo "COUNT 初始值: $COUNT"
    COUNT=$((COUNT + 1))
    echo "COUNT 递增后: $COUNT"
    echo "✓ 这行应该执行"
) && echo "✓ 成功（预期行为）" || echo "✗ 失败"

# 测试 3: 多次递增
echo -e "\n测试 3: 多次递增"
echo "----------------------------------------"
(
    set -e
    COUNT=0
    echo "开始递增..."
    for i in {1..5}; do
        COUNT=$((COUNT + 1))
        echo "  第 $i 次: COUNT = $COUNT"
    done
    echo "✓ 所有递增成功"
) && echo "✓ 成功（预期行为）" || echo "✗ 失败"

# 测试 4: 模拟脚本中的实际使用场景
echo -e "\n测试 4: 模拟实际使用场景"
echo "----------------------------------------"
(
    set -e
    
    GROUP_COUNT=0
    SA_COUNT=0
    
    # 模拟找到 3 个 Groups
    echo "模拟处理 Groups..."
    for i in {1..3}; do
        GROUP_COUNT=$((GROUP_COUNT + 1))
        echo "  找到 Group $i, 总数: $GROUP_COUNT"
    done
    
    # 模拟找到 2 个 ServiceAccounts
    echo "模拟处理 ServiceAccounts..."
    for i in {1..2}; do
        SA_COUNT=$((SA_COUNT + 1))
        echo "  找到 SA $i, 总数: $SA_COUNT"
    done
    
    echo "✓ 最终统计: Groups=$GROUP_COUNT, ServiceAccounts=$SA_COUNT"
) && echo "✓ 成功（预期行为）" || echo "✗ 失败"

# 测试 5: 条件递增
echo -e "\n测试 5: 条件递增"
echo "----------------------------------------"
(
    set -e
    
    SECRETS_WITH_GROUPS=0
    SECRETS_WITH_SAS=0
    
    # 模拟 3 个 Secret
    for secret in {1..3}; do
        HAS_GROUP=false
        HAS_SA=false
        
        # 随机决定是否有 Group 或 SA
        if [ $((secret % 2)) -eq 0 ]; then
            HAS_GROUP=true
        fi
        if [ $((secret % 3)) -eq 0 ]; then
            HAS_SA=true
        fi
        
        # 条件递增
        [ "$HAS_GROUP" = true ] && SECRETS_WITH_GROUPS=$((SECRETS_WITH_GROUPS + 1))
        [ "$HAS_SA" = true ] && SECRETS_WITH_SAS=$((SECRETS_WITH_SAS + 1))
        
        echo "  Secret $secret: Group=$HAS_GROUP, SA=$HAS_SA"
    done
    
    echo "✓ 统计: 有 Groups 的 Secret=$SECRETS_WITH_GROUPS, 有 SA 的 Secret=$SECRETS_WITH_SAS"
) && echo "✓ 成功（预期行为）" || echo "✗ 失败"

echo ""
echo "========================================="
echo "测试完成"
echo "========================================="
echo ""
echo "总结:"
echo "  - 测试 1 应该失败（演示问题）"
echo "  - 测试 2-5 应该全部成功（验证修复）"
echo ""
