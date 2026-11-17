#!/bin/bash

echo "测试 Bash 算术运算在 set -euo pipefail 下的行为"
echo "================================================"
echo ""

# 测试 1: 不使用 set -e
echo "测试 1: 正常模式"
COUNTER=0
((COUNTER++))
echo "COUNTER = $COUNTER (成功)"
echo ""

# 测试 2: 使用 set -e
echo "测试 2: set -e 模式"
(
    set -e
    COUNTER=0
    ((COUNTER++)) || true  # 需要 || true 来避免退出
    echo "COUNTER = $COUNTER (成功)"
)
echo ""

# 测试 3: 演示问题
echo "测试 3: 演示 ((COUNTER++)) 的退出码"
COUNTER=0
((COUNTER++))
echo "退出码: $?"
echo "COUNTER = $COUNTER"
echo ""

# 测试 4: 当值为 0 时
echo "测试 4: 当值为 0 时的退出码"
COUNTER=0
if ((COUNTER)); then
    echo "COUNTER 为真"
else
    echo "COUNTER 为假 (退出码: $?)"
fi
echo ""

# 测试 5: 安全的递增方式
echo "测试 5: 安全的递增方式"
set -euo pipefail
COUNTER=0

# 方式 1: 使用 let
let COUNTER++ || true
echo "方式 1 (let): COUNTER = $COUNTER"

# 方式 2: 使用算术展开
COUNTER=$((COUNTER + 1))
echo "方式 2 (算术展开): COUNTER = $COUNTER"

# 方式 3: 使用 (()) 但加 || true
((COUNTER++)) || true
echo "方式 3 ((++)) || true: COUNTER = $COUNTER"

# 方式 4: 最安全的方式
: $((COUNTER++))
echo "方式 4 (: $((++))): COUNTER = $COUNTER"

echo ""
echo "结论: 在 set -e 模式下，((COUNTER++)) 可能导致脚本退出！"
echo "推荐使用: COUNTER=\$((COUNTER + 1)) 或 : \$((COUNTER++))"
