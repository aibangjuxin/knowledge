#!/bin/bash

################################################################################
# KMS 验证脚本调试工具
# 用于快速诊断环境问题
################################################################################

set -euo pipefail

echo "=========================================="
echo "KMS 验证脚本环境诊断"
echo "=========================================="
echo ""

# 1. 检查 Shell 环境
echo "1. Shell 环境:"
echo "   Shell: $SHELL"
echo "   Bash 版本: $BASH_VERSION"
echo ""

# 2. 检查必需命令
echo "2. 检查必需命令:"
if command -v gcloud &> /dev/null; then
    echo "   ✓ gcloud: $(command -v gcloud)"
    gcloud_version=$(gcloud version --format="value(core)" 2>&1 || echo "无法获取版本")
    echo "     版本: $gcloud_version"
else
    echo "   ✗ gcloud: 未找到"
fi

if command -v jq &> /dev/null; then
    echo "   ✓ jq: $(command -v jq)"
    jq_version=$(jq --version 2>&1 || echo "无法获取版本")
    echo "     版本: $jq_version"
else
    echo "   ✗ jq: 未找到"
fi
echo ""

# 3. 检查 gcloud 认证
echo "3. 检查 gcloud 认证:"
if command -v gcloud &> /dev/null; then
    echo "   尝试获取活动账号..."
    
    # 方法 1: 使用 filter
    auth_account1=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>&1 || echo "ERROR")
    echo "   方法1 (filter): $auth_account1"
    
    # 方法 2: 不使用 filter
    auth_account2=$(gcloud auth list --format="value(account)" 2>&1 | head -1 || echo "ERROR")
    echo "   方法2 (no filter): $auth_account2"
    
    # 方法 3: 使用 config
    auth_account3=$(gcloud config get-value account 2>&1 || echo "ERROR")
    echo "   方法3 (config): $auth_account3"
    
    # 显示完整的认证列表
    echo ""
    echo "   完整认证列表:"
    gcloud auth list 2>&1 | sed 's/^/     /'
else
    echo "   跳过 (gcloud 未安装)"
fi
echo ""

# 4. 检查临时目录权限
echo "4. 检查临时目录:"
TEMP_TEST_DIR="/tmp/kms-validator-test-$$"
if mkdir -p "$TEMP_TEST_DIR" 2>&1; then
    echo "   ✓ 可以创建临时目录: $TEMP_TEST_DIR"
    if echo "test" > "$TEMP_TEST_DIR/test.txt" 2>&1; then
        echo "   ✓ 可以写入文件"
    else
        echo "   ✗ 无法写入文件"
    fi
    rm -rf "$TEMP_TEST_DIR"
else
    echo "   ✗ 无法创建临时目录"
fi
echo ""

# 5. 测试 set -euo pipefail 行为
echo "5. 测试错误处理:"
test_function() {
    local result
    result=$(false 2>&1 || true)
    echo "   ✓ 使用 '|| true' 可以捕获错误"
}
test_function
echo ""

# 6. 测试 jq 解析
echo "6. 测试 jq 解析:"
if command -v jq &> /dev/null; then
    test_json='{"test": "value", "number": 123}'
    parsed=$(echo "$test_json" | jq -r '.test' 2>&1 || echo "ERROR")
    if [[ "$parsed" == "value" ]]; then
        echo "   ✓ jq 解析正常"
    else
        echo "   ✗ jq 解析失败: $parsed"
    fi
else
    echo "   跳过 (jq 未安装)"
fi
echo ""

echo "=========================================="
echo "诊断完成"
echo "=========================================="
echo ""
echo "如果所有检查都通过，请尝试运行:"
echo "  ./verify-kms-enhanced.sh --verbose [其他参数]"
echo ""
echo "如果仍有问题，请提供以上输出信息"
