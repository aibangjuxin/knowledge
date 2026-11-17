#!/bin/bash

# CI/CD Pipeline 集成脚本
# 用于在构建流程中集成认证扫描

set -e

# 配置参数
SCANNER_JAR="auth-scanner.jar"
TARGET_JAR="$1"
CONFIG_PATH="$2"
OUTPUT_DIR="${3:-./scan-reports}"
STRICT_MODE="${4:-false}"

# 检查参数
if [ -z "$TARGET_JAR" ]; then
    echo "错误: 请指定要扫描的 JAR 文件路径"
    echo "用法: $0 <target-jar> [config-path] [output-dir] [strict-mode]"
    exit 1
fi

if [ ! -f "$TARGET_JAR" ]; then
    echo "错误: JAR 文件不存在: $TARGET_JAR"
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 生成报告文件名
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$OUTPUT_DIR/auth-scan-report-$TIMESTAMP.json"

echo "开始认证扫描..."
echo "目标 JAR: $TARGET_JAR"
echo "配置路径: ${CONFIG_PATH:-未指定}"
echo "输出目录: $OUTPUT_DIR"
echo "严格模式: $STRICT_MODE"

# 构建扫描命令
SCAN_CMD="java -jar $SCANNER_JAR $TARGET_JAR --output $REPORT_FILE"

if [ -n "$CONFIG_PATH" ]; then
    SCAN_CMD="$SCAN_CMD --config-path $CONFIG_PATH"
fi

if [ "$STRICT_MODE" = "true" ]; then
    SCAN_CMD="$SCAN_CMD --strict"
fi

# 执行扫描
echo "执行命令: $SCAN_CMD"
if $SCAN_CMD; then
    echo "✅ 认证扫描通过"
    echo "报告文件: $REPORT_FILE"
    
    # 提取关键信息用于 CI 展示
    if command -v jq &> /dev/null; then
        echo "扫描摘要:"
        jq -r '.jarComponents | length as $total | map(select(.found)) | length as $found | "发现认证组件: \($found)/\($total)"' "$REPORT_FILE"
        
        # 显示错误和警告
        ERRORS=$(jq -r '.errors | length' "$REPORT_FILE")
        WARNINGS=$(jq -r '.warnings | length' "$REPORT_FILE")
        
        if [ "$ERRORS" -gt 0 ]; then
            echo "错误数量: $ERRORS"
            jq -r '.errors[]' "$REPORT_FILE" | sed 's/^/  - /'
        fi
        
        if [ "$WARNINGS" -gt 0 ]; then
            echo "警告数量: $WARNINGS"
            jq -r '.warnings[]' "$REPORT_FILE" | sed 's/^/  - /'
        fi
    fi
    
    exit 0
else
    echo "❌ 认证扫描失败"
    echo "报告文件: $REPORT_FILE"
    
    # 显示失败原因
    if command -v jq &> /dev/null && [ -f "$REPORT_FILE" ]; then
        echo "失败原因:"
        jq -r '.errors[]' "$REPORT_FILE" | sed 's/^/  - /'
    fi
    
    exit 1
fi