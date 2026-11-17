# Kali Linux 容器 Zsh 配置
# 优化的安全测试和开发环境配置

# Oh My Zsh 配置路径
export ZSH="$HOME/.oh-my-zsh"

# 主题设置 - 使用 agnoster 主题，适合安全测试环境
ZSH_THEME="agnoster"

# 插件配置
plugins=(
    git
    docker
    kubectl
    python
    pip
    autojump
    zsh-autosuggestions
    zsh-syntax-highlighting
    history-substring-search
    colored-man-pages
    command-not-found
)

# 加载 Oh My Zsh
source $ZSH/oh-my-zsh.sh

# ============================================================================
# 环境变量配置
# ============================================================================

# 编辑器设置
export EDITOR='nvim'
export VISUAL='nvim'

# 语言设置
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 历史记录配置
export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILE=~/.zsh_history
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY

# ============================================================================
# 别名配置
# ============================================================================

# 基础命令别名
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Git 别名
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gb='git branch'
alias gco='git checkout'
alias glog='git log --oneline --graph --decorate'

# Kubernetes 别名
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'
alias kgd='kubectl get deployments'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias kds='kubectl describe service'
alias kdd='kubectl describe deployment'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'

# Docker 别名
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias dpa='docker ps -a'
alias di='docker images'
alias drm='docker rm'
alias drmi='docker rmi'

# 安全工具别名
alias nmap-quick='nmap -T4 -F'
alias nmap-full='nmap -T4 -A -v'
alias nmap-udp='nmap -sU -T4'
alias nikto-quick='nikto -h'
alias sslscan-quick='sslscan --targets='

# 系统信息别名
alias myip='curl -s ifconfig.me'
alias ports='netstat -tulanp'
alias listening='netstat -tlnp'
alias meminfo='free -h'
alias cpuinfo='lscpu'
alias diskinfo='df -h'

# 文件操作别名
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias tree='tree -C'
alias mkdir='mkdir -pv'

# ============================================================================
# 函数定义
# ============================================================================

# 快速端口扫描函数
portscan() {
    if [ $# -eq 0 ]; then
        echo "用法: portscan <目标IP或域名> [端口范围]"
        echo "示例: portscan 192.168.1.1 1-1000"
        return 1
    fi
    
    local target=$1
    local ports=${2:-"1-65535"}
    
    echo "🔍 扫描目标: $target"
    echo "📡 端口范围: $ports"
    nmap -T4 -p $ports $target
}

# 快速子域名发现
subdomain() {
    if [ $# -eq 0 ]; then
        echo "用法: subdomain <域名>"
        echo "示例: subdomain example.com"
        return 1
    fi
    
    local domain=$1
    echo "🔍 发现子域名: $domain"
    amass enum -d $domain
}

# 快速 SSL 检查
sslcheck() {
    if [ $# -eq 0 ]; then
        echo "用法: sslcheck <域名:端口>"
        echo "示例: sslcheck example.com:443"
        return 1
    fi
    
    local target=$1
    echo "🔒 SSL 检查: $target"
    sslscan $target
}

# 创建项目目录结构
mkproject() {
    if [ $# -eq 0 ]; then
        echo "用法: mkproject <项目名>"
        return 1
    fi
    
    local project=$1
    mkdir -p ~/reports/$project/{nmap,nikto,screenshots,notes}
    echo "📁 项目目录已创建: ~/reports/$project"
    cd ~/reports/$project
}

# 快速 Web 扫描
webscan() {
    if [ $# -eq 0 ]; then
        echo "用法: webscan <URL>"
        echo "示例: webscan https://example.com"
        return 1
    fi
    
    local url=$1
    echo "🌐 Web 扫描: $url"
    nikto -h $url
}

# 显示网络接口信息
netinfo() {
    echo "🌐 网络接口信息:"
    ip addr show
    echo ""
    echo "🔗 路由信息:"
    ip route show
    echo ""
    echo "🌍 DNS 配置:"
    cat /etc/resolv.conf
}

# 快速目录跳转到常用位置
cdtools() { cd ~/tools; }
cdscripts() { cd ~/scripts; }
cdreports() { cd ~/reports; }
cdwordlists() { cd ~/wordlists; }

# ============================================================================
# 自动补全配置
# ============================================================================

# kubectl 自动补全
if command -v kubectl >/dev/null 2>&1; then
    source <(kubectl completion zsh)
fi

# Docker 自动补全
if command -v docker >/dev/null 2>&1; then
    # Docker 补全通常由插件提供
fi

# ============================================================================
# 提示符配置
# ============================================================================

# 自定义提示符（如果不使用 agnoster 主题）
# PROMPT='%F{red}┌──(%f%F{yellow}%n%f%F{green}@%f%F{blue}%m%f%F{red})-[%f%F{white}%~%f%F{red}]%f
# %F{red}└─%f%F{red}$%f '

# ============================================================================
# 加载额外配置
# ============================================================================

# 加载 autojump
if [ -f /usr/share/autojump/autojump.sh ]; then
    . /usr/share/autojump/autojump.sh
fi

# 加载自定义别名（如果存在）
if [ -f /workspace/aliases.sh ]; then
    source /workspace/aliases.sh
fi

# 加载挂载配置（如果存在）
if [ -f /opt/share/mount-config.sh ]; then
    echo "🔧 检测到挂载配置，正在加载..."
    source /opt/share/mount-config.sh
fi

# 加载本地配置（如果存在）
if [ -f ~/.zshrc.local ]; then
    source ~/.zshrc.local
fi

# ============================================================================
# 启动信息
# ============================================================================

# 显示欢迎信息
echo "🛡️  Kali Linux 安全测试环境"
echo "📅 $(date)"
echo "🖥️  主机: $(hostname)"
echo "👤 用户: $(whoami)"
echo ""
echo "🚀 快速命令:"
echo "  portscan <IP>     - 端口扫描"
echo "  webscan <URL>     - Web 扫描"
echo "  subdomain <域名>  - 子域名发现"
echo "  sslcheck <域名>   - SSL 检查"
echo "  mkproject <名称>  - 创建项目目录"
echo "  netinfo           - 网络信息"
echo ""

# 检查重要工具
missing_tools=()
for tool in nmap nikto kubectl git nvim; do
    if ! command -v $tool >/dev/null 2>&1; then
        missing_tools+=($tool)
    fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
    echo "⚠️  缺少工具: ${missing_tools[*]}"
    echo "   请运行初始化脚本: /workspace/init.sh"
    echo ""
fi
