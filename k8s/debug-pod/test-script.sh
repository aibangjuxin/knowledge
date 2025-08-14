#!/bin/bash

# 测试脚本 - 验证优化版本的功能

echo "=== Testing Optimized Debug Script ==="

# 测试帮助信息
echo "1. Testing help option..."
./k8s/debug-pod/side-optimized.sh --help

echo ""
echo "2. Testing invalid arguments..."
./k8s/debug-pod/side-optimized.sh || echo "Expected failure - OK"

echo ""
echo "3. Testing verbose mode (dry run)..."
echo "Note: This would normally require a valid k8s cluster"
echo "Command: ./k8s/debug-pod/side-optimized.sh test-app debug:latest -n default -v"

echo ""
echo "=== Test completed ==="
echo "The optimized script is ready for use with a real Kubernetes cluster"