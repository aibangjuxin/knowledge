#!/bin/bash

# QNAP 系统检测测试脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info "QNAP 系统检测测试"
echo "===================="

# 检查系统信息
print_info "系统基本信息:"
echo "  主机名: $(hostname)"
echo "  内核: $(uname -r)"
echo "  架构: $(uname -m)"
echo "  系统: $(uname -s)"

echo ""

# 检查 QNAP 特征
print_info "检查 QNAP 特征:"

# 1. qpkg 命令
if command -v qpkg &> /dev/null; then
    print_success "找到 qpkg 命令"
    echo "  版本: $(qpkg --version 2>/dev/null || echo '未知')"
else
    print_warning "未找到 qpkg 命令"
fi

# 2. 平台配置文件
if [[ -f /etc/platform.conf ]]; then
    print_success "找到 /etc/platform.conf"
    echo "  内容预览:"
    head -5 /etc/platform.conf | sed 's/^/    /'
else
    print_warning "未找到 /etc/platform.conf"
fi

# 3. QNAP 平台配置
if [[ -f /etc/qnap_platform.conf ]]; then
    print_success "找到 /etc/qnap_platform.conf"
else
    print_warning "未找到 /etc/qnap_platform.conf"
fi

# 4. 共享目录结构
print_info "检查共享目录结构:"
for dir in "/share" "/share/homes" "/share/CACHEDEV1_DATA"; do
    if [[ -d "$dir" ]]; then
        print_success "找到目录: $dir"
    else
        print_warning "未找到目录: $dir"
    fi
done

# 5. QNAP 进程
print_info "检查 QNAP 相关进程:"
if pgrep -f "qnap" > /dev/null 2>&1; then
    print_success "找到 QNAP 相关进程"
    echo "  进程列表:"
    pgrep -f "qnap" | head -5 | while read pid; do
        echo "    PID $pid: $(ps -p $pid -o comm= 2>/dev/null || echo '未知')"
    done
else
    print_warning "未找到 QNAP 相关进程"
fi

# 6. 容器相关
print_info "检查容器环境:"
if command -v docker &> /dev/null; then
    print_success "找到 Docker 命令"
    echo "  版本: $(docker --version 2>/dev/null || echo '无法获取版本')"
else
    print_warning "未找到 Docker 命令"
fi

if [[ -f /usr/local/bin/docker ]]; then
    print_success "找到 /usr/local/bin/docker"
elif [[ -f /opt/docker/bin/docker ]]; then
    print_success "找到 /opt/docker/bin/docker"
else
    print_warning "未找到 Docker 二进制文件"
fi

# 7. 网络测试
print_info "网络连接测试:"
test_urls=(
    "https://www.baidu.com"
    "https://www.google.com"
    "https://registry.aliyuncs.com"
    "https://dl.k8s.io"
)

for url in "${test_urls[@]}"; do
    if curl -s --connect-timeout 3 --max-time 5 "$url" > /dev/null 2>&1; then
        print_success "可以访问: $url"
    else
        print_warning "无法访问: $url"
    fi
done

echo ""
print_info "检测完成！"

# 综合判断
is_qnap=false
qnap_indicators=0

if command -v qpkg &> /dev/null; then
    ((qnap_indicators++))
fi

if [[ -f /etc/platform.conf ]] || [[ -f /etc/qnap_platform.conf ]]; then
    ((qnap_indicators++))
fi

if [[ -d /share/homes ]] || [[ -d /share/CACHEDEV1_DATA ]]; then
    ((qnap_indicators++))
fi

if pgrep -f "qnap" > /dev/null 2>&1; then
    ((qnap_indicators++))
fi

echo ""
if [[ $qnap_indicators -ge 2 ]]; then
    print_success "综合判断: 这是一个 QNAP 系统 (指标: $qnap_indicators/4)"
elif [[ $qnap_indicators -ge 1 ]]; then
    print_warning "综合判断: 可能是 QNAP 系统 (指标: $qnap_indicators/4)"
else
    print_error "综合判断: 不是 QNAP 系统 (指标: $qnap_indicators/4)"
fi