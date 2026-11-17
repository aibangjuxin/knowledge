#!/bin/bash

# 应用入口点脚本
# 在启动实际应用之前执行校验

set -e

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

function log_info() { echo -e "${GREEN}[ENTRYPOINT]${NC} $1"; }
function log_warn() { echo -e "${YELLOW}[ENTRYPOINT]${NC} $1"; }
function log_error() { echo -e "${RED}[ENTRYPOINT]${NC} $1"; }

log_info "🚀 容器启动中..."

# 1. 执行启动校验
log_info "执行环境校验..."
if ! /usr/local/bin/startup-validator.sh; then
    log_error "❌ 启动校验失败，容器退出"
    exit 1
fi

# 2. 设置信号处理 (优雅关闭)
function cleanup() {
    log_info "🛑 接收到终止信号，正在优雅关闭..."
    if [[ -n "$APP_PID" ]]; then
        kill -TERM "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    log_info "✅ 应用已关闭"
    exit 0
}

trap cleanup SIGTERM SIGINT

# 3. 启动应用
log_info "🎯 启动应用: $*"

# 如果没有提供命令参数，使用默认命令
if [[ $# -eq 0 ]]; then
    set -- "node" "dist/index.js"
fi

# 在后台启动应用并获取PID
"$@" &
APP_PID=$!

log_info "✅ 应用已启动 (PID: $APP_PID)"

# 4. 等待应用结束
wait "$APP_PID"
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    log_info "✅ 应用正常退出"
else
    log_error "❌ 应用异常退出 (退出码: $EXIT_CODE)"
fi

exit $EXIT_CODE