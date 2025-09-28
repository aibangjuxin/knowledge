#!/bin/bash

# 挂载配置模板脚本
# 放置在宿主机目录中，容器启动时自动加载
# 挂载路径: /opt/share/mount-config.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[MOUNT-CONFIG]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[MOUNT-CONFIG]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[MOUNT-CONFIG]${NC} $1"
}

log_info "🔧 开始加载挂载配置..."

# ============================================================================
# 个人配置区域 - 根据需要修改
# ============================================================================

# 1. 代理配置
PROXY_ENABLED=true
PROXY_HOST="192.168.31.198"
PROXY_PORT="7221"

# 2. Git 配置
GIT_USER_NAME="Your Name"
GIT_USER_EMAIL="your.email@example.com"

# 3. 自定义环境变量
export CUSTOM_TOOLS_PATH="/opt/share/tools"
export CUSTOM_SCRIPTS_PATH="/opt/share/scripts"
export CUSTOM_WORDLISTS_PATH="/opt/share/wordlists"

# 4. 工作目录配置
WORKSPACE_ROOT="/workspace"
REPORTS_DIR="$HOME/reports"
TOOLS_DIR="$HOME/tools"

# ============================================================================
# 代理配置
# ============================================================================

if [ "$PROXY_ENABLED" = true ]; then
    log_info "配置代理设置..."
    export ALL_PROXY="socks5://${PROXY_HOST}:${PROXY_PORT}"
    export HTTP_PROXY="http://${PROXY_HOST}:${PROXY_PORT}"
    export HTTPS_PROXY="http://${PROXY_HOST}:${PROXY_PORT}"
    export NO_PROXY="localhost,127.0.0.1,::1"
    
    # 添加到 .zshrc
    cat >> ~/.zshrc << EOF

# 挂载配置 - 代理设置
export ALL_PROXY="socks5://${PROXY_HOST}:${PROXY_PORT}"
export HTTP_PROXY="http://${PROXY_HOST}:${PROXY_PORT}"
export HTTPS_PROXY="http://${PROXY_HOST}:${PROXY_PORT}"
export NO_PROXY="localhost,127.0.0.1,::1"
EOF
    log_success "代理配置完成"
fi

# ============================================================================
# Git 配置
# ============================================================================

if [ -n "$GIT_USER_NAME" ] && [ -n "$GIT_USER_EMAIL" ]; then
    log_info "配置 Git 用户信息..."
    git config --global user.name "$GIT_USER_NAME"
    git config --global user.email "$GIT_USER_EMAIL"
    git config --global init.defaultBranch main
    git config --global pull.rebase false
    log_success "Git 配置完成"
fi

# ============================================================================
# 自定义工具路径
# ============================================================================

log_info "配置自定义工具路径..."

# 创建符号链接到挂载的工具目录
if [ -d "/opt/share/tools" ]; then
    ln -sf /opt/share/tools ~/tools-shared
    log_success "工具目录链接创建完成: ~/tools-shared"
fi

if [ -d "/opt/share/scripts" ]; then
    ln -sf /opt/share/scripts ~/scripts-shared
    log_success "脚本目录链接创建完成: ~/scripts-shared"
fi

if [ -d "/opt/share/wordlists" ]; then
    ln -sf /opt/share/wordlists ~/wordlists-shared
    log_success "字典目录链接创建完成: ~/wordlists-shared"
fi

# ============================================================================
# 自定义别名和函数
# ============================================================================

log_info "加载自定义别名和函数..."

# 添加自定义别名到 .zshrc
cat >> ~/.zshrc << 'EOF'

# 挂载配置 - 自定义别名
alias tools-shared='cd ~/tools-shared'
alias scripts-shared='cd ~/scripts-shared'
alias wordlists-shared='cd ~/wordlists-shared'

# 快速访问挂载目录
alias cdshare='cd /opt/share'
alias lsshare='ls -la /opt/share'

# 自定义扫描函数
quick-scan() {
    if [ $# -eq 0 ]; then
        echo "用法: quick-scan <目标IP>"
        return 1
    fi
    
    local target=$1
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local output_dir="$HOME/reports/quick-scan_${target}_${timestamp}"
    
    mkdir -p "$output_dir"
    
    echo "🚀 开始快速扫描: $target"
    echo "📁 输出目录: $output_dir"
    
    # Nmap 快速扫描
    nmap -T4 -F -oN "$output_dir/nmap_quick.txt" $target
    
    # 如果是 Web 服务，进行 Nikto 扫描
    if nmap -p 80,443,8080,8443 $target | grep -q "open"; then
        echo "🌐 发现 Web 服务，开始 Nikto 扫描..."
        nikto -h $target -o "$output_dir/nikto.txt"
    fi
    
    echo "✅ 扫描完成，结果保存在: $output_dir"
}

# 环境信息函数
show-env() {
    echo "🔧 当前环境配置:"
    echo "  代理: ${ALL_PROXY:-未配置}"
    echo "  Git 用户: $(git config --global user.name 2>/dev/null || echo '未配置')"
    echo "  Git 邮箱: $(git config --global user.email 2>/dev/null || echo '未配置')"
    echo "  工作目录: $(pwd)"
    echo "  挂载目录: $(ls -d /opt/share 2>/dev/null || echo '未挂载')"
}
EOF

# ============================================================================
# 加载自定义配置文件
# ============================================================================

# 如果存在自定义配置文件，则加载
if [ -f "/opt/share/custom.sh" ]; then
    log_info "加载自定义配置文件..."
    source /opt/share/custom.sh
    log_success "自定义配置加载完成"
fi

# 如果存在自定义 .zshrc 配置，则追加
if [ -f "/opt/share/.zshrc.custom" ]; then
    log_info "加载自定义 .zshrc 配置..."
    cat /opt/share/.zshrc.custom >> ~/.zshrc
    log_success "自定义 .zshrc 配置加载完成"
fi

# ============================================================================
# SSH 密钥配置
# ============================================================================

if [ -d "/opt/share/.ssh" ]; then
    log_info "配置 SSH 密钥..."
    cp -r /opt/share/.ssh ~/
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/* 2>/dev/null || true
    log_success "SSH 密钥配置完成"
fi

# ============================================================================
# Kubernetes 配置
# ============================================================================

if [ -d "/opt/share/.kube" ]; then
    log_info "配置 Kubernetes..."
    cp -r /opt/share/.kube ~/
    chmod 600 ~/.kube/config 2>/dev/null || true
    log_success "Kubernetes 配置完成"
fi

# ============================================================================
# 完成配置
# ============================================================================

log_success "🎉 挂载配置加载完成！"
log_info "💡 提示:"
echo "  - 使用 'show-env' 查看当前环境配置"
echo "  - 使用 'quick-scan <IP>' 进行快速扫描"
echo "  - 使用 'cdshare' 快速访问挂载目录"
echo "  - 重新加载配置: source ~/.zshrc"