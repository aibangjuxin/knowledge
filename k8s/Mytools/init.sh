#!/bin/bash

# Kali Linux 容器环境初始化脚本
# 作者: Lex
# 用途: 一键配置开发和安全测试环境

set -e

echo "🚀 开始初始化 Kali Linux 容器环境..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否在容器中运行
if [ ! -f /.dockerenv ]; then
    log_warning "此脚本建议在 Docker 容器中运行"
fi

# 1. 配置 Zsh 和 Oh My Zsh
log_info "配置 Zsh 环境..."
if [ -f "/workspace/.zshrc" ]; then
    cp /workspace/.zshrc ~/.zshrc
    log_success "已复制自定义 .zshrc 配置"
else
    log_info "使用默认 .zshrc 配置"
fi

# 2. 配置别名
log_info "配置命令别名..."
if [ -f "/workspace/aliases.sh" ]; then
    source /workspace/aliases.sh
    echo "source /workspace/aliases.sh" >> ~/.zshrc
    log_success "已加载自定义别名配置"
fi

# 3. 配置代理（如果需要）
if [ -n "$PROXY_HOST" ] && [ -n "$PROXY_PORT" ]; then
    log_info "配置代理设置..."
    export ALL_PROXY="socks5://${PROXY_HOST}:${PROXY_PORT}"
    export HTTP_PROXY="http://${PROXY_HOST}:${PROXY_PORT}"
    export HTTPS_PROXY="http://${PROXY_HOST}:${PROXY_PORT}"
    echo "export ALL_PROXY=\"socks5://${PROXY_HOST}:${PROXY_PORT}\"" >> ~/.zshrc
    echo "export HTTP_PROXY=\"http://${PROXY_HOST}:${PROXY_PORT}\"" >> ~/.zshrc
    echo "export HTTPS_PROXY=\"http://${PROXY_HOST}:${PROXY_PORT}\"" >> ~/.zshrc
    log_success "代理配置完成"
fi

# 4. 配置 kubectl
log_info "检查 kubectl 配置..."
if [ -d "/root/.kube" ] && [ -f "/root/.kube/config" ]; then
    kubectl version --client > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_success "kubectl 配置正常"
    else
        log_warning "kubectl 配置可能有问题"
    fi
else
    log_warning "未找到 kubectl 配置文件，请确保挂载了 ~/.kube 目录"
fi

# 5. 配置 autojump
log_info "配置 autojump..."
if command -v autojump >/dev/null 2>&1; then
    echo ". /usr/share/autojump/autojump.sh" >> ~/.zshrc
    log_success "autojump 配置完成"
else
    log_error "autojump 未安装"
fi

# 6. 创建常用目录
log_info "创建工作目录..."
mkdir -p ~/tools
mkdir -p ~/scripts
mkdir -p ~/reports
mkdir -p ~/wordlists
log_success "工作目录创建完成"

# 7. 下载常用字典文件（可选）
if [ "$DOWNLOAD_WORDLISTS" = "true" ]; then
    log_info "下载常用字典文件..."
    cd ~/wordlists
    
    # SecLists
    if [ ! -d "SecLists" ]; then
        git clone https://github.com/danielmiessler/SecLists.git
        log_success "SecLists 下载完成"
    fi
    
    cd /workspace
fi

# 8. 配置 Git（如果提供了用户信息）
if [ -n "$GIT_USER_NAME" ] && [ -n "$GIT_USER_EMAIL" ]; then
    log_info "配置 Git 用户信息..."
    git config --global user.name "$GIT_USER_NAME"
    git config --global user.email "$GIT_USER_EMAIL"
    log_success "Git 配置完成"
fi

# 9. 显示工具版本信息
log_info "工具版本信息:"
echo "----------------------------------------"
nmap --version | head -1
nikto -Version 2>/dev/null | head -1 || echo "Nikto: 已安装"
kubectl version --client --short 2>/dev/null || echo "kubectl: 配置检查失败"
git --version
nvim --version | head -1
echo "----------------------------------------"

# 10. 显示快捷命令提示
log_success "环境初始化完成！"
echo ""
echo "🎯 快捷命令:"
echo "  j <目录>     - 使用 autojump 跳转目录"
echo "  k            - kubectl 别名"
echo "  ll           - 详细列表"
echo "  la           - 显示隐藏文件"
echo "  ..           - 返回上级目录"
echo "  ...          - 返回上两级目录"
echo ""
echo "📁 工作目录:"
echo "  ~/tools      - 工具目录"
echo "  ~/scripts    - 脚本目录"
echo "  ~/reports    - 报告目录"
echo "  ~/wordlists  - 字典目录"
echo ""
echo "🔧 重新加载配置: source ~/.zshrc"
echo ""

log_success "🎉 初始化完成，开始你的安全测试之旅吧！"