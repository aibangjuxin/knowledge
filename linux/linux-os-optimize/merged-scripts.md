# Shell Scripts Collection

Generated on: 2025-10-06 11:35:18
Directory: /Users/lex/git/knowledge/linux/linux-os-optimize

## `linux-nginx-system-optimize.sh`

```bash
#!/bin/bash
# ==========================================
# Linux System Optimization for Nginx on GCP
# ==========================================
# Author: ChatGPT
# Description: Optimize Linux system limits and kernel parameters
# Note: This script does NOT touch nginx.conf
# ==========================================

set -e

# ---- 1. Check root privileges ----
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root."
  exit 1
fi

echo "✅ Starting system optimization for Nginx..."

# ---- 2. Backup original configs ----
backup_dir="/etc/sysctl_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$backup_dir"
cp /etc/security/limits.conf "$backup_dir"/limits.conf.bak 2>/dev/null || true
cp /etc/systemd/system.conf "$backup_dir"/system.conf.bak 2>/dev/null || true
cp /etc/systemd/user.conf "$backup_dir"/user.conf.bak 2>/dev/null || true
cp /etc/sysctl.conf "$backup_dir"/sysctl.conf.bak 2>/dev/null || true

echo "🗂 Backup created at: $backup_dir"

# ---- 3. System Limits (nofile / nproc / memlock) ----
cat <<'EOF' >/etc/security/limits.d/nginx.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc  65535
* hard nproc  65535
* soft memlock unlimited
* hard memlock unlimited
EOF

echo "📈 Updated /etc/security/limits.d/nginx.conf"

# ---- 4. Systemd service limits (for Nginx or general) ----
# Ensure higher limits apply when service starts under systemd
cat <<'EOF' >/etc/systemd/system/nginx.service.d/limits.conf
[Service]
LimitNOFILE=1048576
LimitNPROC=65535
LimitCORE=infinity
EOF

systemctl daemon-reexec
systemctl daemon-reload
echo "🧩 Applied systemd service limits for Nginx."

# ---- 5. Kernel parameters (network tuning) ----
cat <<'EOF' >/etc/sysctl.d/99-nginx-tuning.conf
# ---- File Descriptor / Epoll ----
fs.file-max = 2097152

# ---- Networking (TCP/UDP) ----
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65000

# ---- TCP performance ----
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_rmem = 4096 87380 6291456
net.ipv4.tcp_wmem = 4096 65536 6291456
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# ---- Connection tracking ----
net.netfilter.nf_conntrack_max = 524288

# ---- Avoid TIME_WAIT overflow ----
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1

# ---- Enable TCP fast open ----
net.ipv4.tcp_fastopen = 3
EOF

sysctl --system

echo "⚙️  Kernel parameters updated and reloaded."

# ---- 6. Disable unnecessary services (optional) ----
# systemctl disable --now rsyslog || true

# ---- 7. Verify results ----
ulimit -n
sysctl fs.file-max
sysctl net.core.somaxconn

echo "✅ Optimization completed successfully!"

```

## `linux-system-optimize-gemini.sh`

```bash
#!/bin/bash

# =================================================================
# Linux System Optimization for Nginx on GCP
#
# Description:
# This script applies system-level optimizations for a Linux server,
# specifically tuned for high-performance web services like Nginx.
# It focuses on increasing resource limits such as max open files
# and tuning the TCP/IP stack.
#
# Note:
# - This script should be run with root privileges.
# - A system reboot is recommended for some changes to take effect.
# - It's always a good practice to backup before applying changes.
#
# =================================================================

# Function to backup a file if it exists
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        local backup_file="${file}.$(date +%Y%m%d_%H%M%S).bak"
        echo "Backing up $file to $backup_file..."
        cp "$file" "$backup_file"
    fi
}

# --- Step 1: Increase System-wide File Descriptor Limits ---

echo "--- Applying File Descriptor Limits ---"

# Define the new limits configuration
LIMITS_CONF_SNIPPET="
# Added for Nginx optimization
*    soft    nofile    65535
*    hard    nofile    65535
*    soft    nproc     65535
*    hard    nproc     65535
root soft    nofile    65535
root hard    nofile    65535
root soft    nproc     65535
root hard    nproc     65535
"

# Backup and update /etc/security/limits.conf
backup_file "/etc/security/limits.conf"
echo "Updating /etc/security/limits.conf with higher file and process limits..."
echo "$LIMITS_CONF_SNIPPET" >> /etc/security/limits.conf

# Ensure pam_limits is used
if [ -f /etc/pam.d/common-session ] && ! grep -q "session required pam_limits.so" /etc/pam.d/common-session; then
    echo "session required pam_limits.so" >> /etc/pam.d/common-session
fi
if [ -f /etc/pam.d/common-session-noninteractive ] && ! grep -q "session required pam_limits.so" /etc/pam.d/common-session-noninteractive; then
    echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive
fi


# --- Step 2: Tune Kernel Parameters (sysctl) ---

echo "--- Applying Kernel Parameter Tuning (sysctl) ---"

SYSCTL_CONF_FILE="/etc/sysctl.d/99-nginx-optimizations.conf"

# Create a new sysctl configuration file for our changes
cat > "$SYSCTL_CONF_FILE" <<EOF
# Nginx and Web Server Optimizations

# Increase system-wide max open files limit
fs.file-max = 2097152

# TCP/IP Stack Tuning for High Performance
# Increase the size of the listen queue for incoming connections
net.core.somaxconn = 65535

# Increase the number of packets allowed to queue when an interface receives them faster than the kernel can process
net.core.netdev_max_backlog = 65535

# Increase the maximum number of remembered connection requests, which helps against SYN flood attacks
net.ipv4.tcp_max_syn_backlog = 65535

# Allow reuse of sockets in TIME-WAIT state for new connections (safer than tcp_tw_recycle)
net.ipv4.tcp_tw_reuse = 1

# Reduce the time sockets stay in FIN-WAIT-2 state
net.ipv4.tcp_fin_timeout = 15

# Widen the range of ephemeral ports available for outgoing connections
net.ipv4.ip_local_port_range = 1024 65535

# TCP keepalive settings
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5

# Lower the tendency of the kernel to swap. Recommended for database/web servers.
vm.swappiness = 10

EOF

echo "Created sysctl configuration at $SYSCTL_CONF_FILE"

# Apply the changes immediately
echo "Applying new sysctl settings..."
sysctl -p "$SYSCTL_CONF_FILE"

# --- Completion ---

echo ""
echo "================================================================="
echo "System optimization script finished."
echo ""
echo "Summary of changes:"
echo "1. Increased user-level file open and process limits in /etc/security/limits.conf."
echo "2. Applied kernel-level tuning for network performance and file limits via sysctl."
echo ""
echo "IMPORTANT:"
echo "A system reboot is highly recommended for all changes to take full effect,"
echo "especially the 'limits.conf' modifications."
echo "================================================================="


```

## `linux-system-optimize-tt.sh`

```bash
#!/bin/bash

# Linux System Optimization Script for GCP Nginx Web Server
# Focus: System limits, file descriptors, and kernel parameters
# Author: System Administrator
# Date: $(date)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

log "Starting Linux system optimization for GCP Nginx web server..."

# Backup original configurations
BACKUP_DIR="/root/system-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "$BACKUP_DIR/"
        log "Backed up $file to $BACKUP_DIR/"
    fi
}

# Backup important files
backup_file "/etc/security/limits.conf"
backup_file "/etc/sysctl.conf"
backup_file "/etc/systemd/system.conf"

log "Configuration files backed up to: $BACKUP_DIR"

# 1. System Limits Configuration (/etc/security/limits.conf)
log "Configuring system limits..."

cat >> /etc/security/limits.conf << 'EOF'

# Nginx Web Server Optimizations
# Soft and hard limits for file descriptors
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536

# Process limits
* soft nproc 32768
* hard nproc 32768

# Memory limits (in KB)
* soft memlock unlimited
* hard memlock unlimited

# Core dump size
* soft core unlimited
* hard core unlimited
EOF

# 2. Kernel Parameters (/etc/sysctl.conf)
log "Configuring kernel parameters..."

cat >> /etc/sysctl.conf << 'EOF'

# ===========================================
# Nginx Web Server System Optimizations
# ===========================================

# File system limits
fs.file-max = 2097152
fs.nr_open = 1048576

# Network optimizations
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216

# TCP optimizations
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535

# Connection tracking
net.netfilter.nf_conntrack_max = 1048576
net.nf_conntrack_max = 1048576

# Virtual memory
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# Kernel limits
kernel.pid_max = 4194304
EOF

# 3. Systemd Configuration
log "Configuring systemd limits..."

# Update systemd system.conf
sed -i 's/#DefaultLimitNOFILE=/DefaultLimitNOFILE=65536/' /etc/systemd/system.conf
sed -i 's/#DefaultLimitNPROC=/DefaultLimitNPROC=32768/' /etc/systemd/system.conf

# 4. Create systemd drop-in for nginx service
mkdir -p /etc/systemd/system/nginx.service.d/
cat > /etc/systemd/system/nginx.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=65536
LimitNPROC=32768
LimitCORE=infinity
LimitMEMLOCK=infinity
EOF

# 5. PAM limits
log "Configuring PAM limits..."
if ! grep -q "pam_limits.so" /etc/pam.d/common-session; then
    echo "session required pam_limits.so" >> /etc/pam.d/common-session
fi

# 6. Apply sysctl changes
log "Applying sysctl changes..."
sysctl -p

# 7. Reload systemd
log "Reloading systemd configuration..."
systemctl daemon-reload

# 8. Display current limits
log "Current system limits:"
echo "File descriptor limits:"
ulimit -n
echo "Process limits:"
ulimit -u
echo "Core dump size:"
ulimit -c

# 9. Display network parameters
log "Current network parameters:"
echo "somaxconn: $(cat /proc/sys/net/core/somaxconn)"
echo "file-max: $(cat /proc/sys/fs/file-max)"
echo "nr_open: $(cat /proc/sys/fs/nr_open)"

# 10. Create monitoring script
log "Creating system monitoring script..."
cat > /usr/local/bin/check-limits.sh << 'EOF'
#!/bin/bash
echo "=== System Limits Check ==="
echo "Current file descriptor limit: $(ulimit -n)"
echo "Current process limit: $(ulimit -u)"
echo "Open files: $(lsof | wc -l)"
echo "Active connections: $(ss -tun | wc -l)"
echo "Load average: $(uptime | awk -F'load average:' '{print $2}')"
echo "Memory usage: $(free -h | grep Mem)"
EOF

chmod +x /usr/local/bin/check-limits.sh

# 11. Create optimization verification script
cat > /usr/local/bin/verify-optimization.sh << 'EOF'
#!/bin/bash
echo "=== Optimization Verification ==="
echo "File descriptor limits:"
echo "  Soft limit: $(ulimit -Sn)"
echo "  Hard limit: $(ulimit -Hn)"
echo "Process limits:"
echo "  Soft limit: $(ulimit -Su)"
echo "  Hard limit: $(ulimit -Hu)"
echo "Kernel parameters:"
echo "  fs.file-max: $(sysctl -n fs.file-max)"
echo "  net.core.somaxconn: $(sysctl -n net.core.somaxconn)"
echo "  vm.swappiness: $(sysctl -n vm.swappiness)"
EOF

chmod +x /usr/local/bin/verify-optimization.sh

log "System optimization completed successfully!"
log "Backup directory: $BACKUP_DIR"
log "Monitoring script: /usr/local/bin/check-limits.sh"
log "Verification script: /usr/local/bin/verify-optimization.sh"

warn "IMPORTANT: A system reboot is recommended to ensure all changes take effect."
warn "After reboot, run: /usr/local/bin/verify-optimization.sh to verify settings."

log "Optimization script finished. Please reboot the system when convenient."
```

## `Linux-system-optimize.sh`

```bash
#!/usr/bin/env bash
# Linux-system-optimize.sh
# GCP Linux 实例 + Nginx Web 服务器系统优化脚本
# 专注于文件描述符、系统限制、内核参数优化

set -Eeuo pipefail

ACTION="${1:-apply}"
SYSCTL_FILE="/etc/sysctl.d/99-nginx-optimize.conf"
LIMITS_FILE="/etc/security/limits.d/99-nginx-optimize.conf"
SYSTEMD_LIMITS_DIR="/etc/systemd/system.conf.d"
SYSTEMD_LIMITS_FILE="${SYSTEMD_LIMITS_DIR}/99-nginx-limits.conf"
NGINX_LIMITS_DIR="/etc/systemd/system/nginx.service.d"
NGINX_LIMITS_FILE="${NGINX_LIMITS_DIR}/99-limits.conf"
BACKUP_DIR="/opt/system-optimize-backup"

#------------- 辅助函数 -------------
ok(){   printf "\033[32m✓ %s\033[0m\n" "$*"; }
warn(){ printf "\033[33m⚠ %s\033[0m\n" "$*"; }
err(){  printf "\033[31m✗ %s\033[0m\n" "$*"; }
info(){ printf "\033[36mℹ %s\033[0m\n" "$*"; }

# 创建备份
create_backup() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp "$file" "$BACKUP_DIR/$(basename "$file").$(date +%Y%m%d_%H%M%S).bak"
        info "已备份原文件: $file"
    fi
}

# 检测系统信息
detect_system() {
    echo "=== 系统信息检测 ==="
    echo "操作系统: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "内核版本: $(uname -r)"
    echo "CPU 核心数: $(nproc)"
    echo "内存大小: $(free -h | awk '/^Mem:/ {print $2}')"
    echo "当前用户最大文件数: $(ulimit -n)"
    echo "系统最大文件数: $(cat /proc/sys/fs/file-max)"
    
    # 检测 Nginx
    if systemctl is-active nginx >/dev/null 2>&1; then
        echo "Nginx 状态: 运行中"
        echo "Nginx 版本: $(nginx -v 2>&1 | cut -d' ' -f3)"
    elif command -v nginx >/dev/null 2>&1; then
        echo "Nginx 状态: 已安装但未运行"
        echo "Nginx 版本: $(nginx -v 2>&1 | cut -d' ' -f3)"
    else
        warn "Nginx 未安装"
    fi
    echo
}

# 应用系统内核参数优化
apply_sysctl() {
    info "正在应用内核参数优化..."
    create_backup "$SYSCTL_FILE"
    
    cat >"$SYSCTL_FILE" <<'EOF'
# === Nginx Web 服务器内核参数优化 ===
# 文件系统优化
fs.file-max = 2097152
fs.nr_open = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# 网络核心参数
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 30000
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.core.optmem_max = 25165824

# TCP 参数优化
net.ipv4.tcp_max_syn_backlog = 30000
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_rmem = 8192 262144 16777216
net.ipv4.tcp_wmem = 8192 262144 16777216
net.ipv4.tcp_congestion_control = bbr

# IP 参数
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.ip_forward = 0
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.default.accept_source_route = 0

# 虚拟内存管理
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
vm.min_free_kbytes = 65536

# 进程和线程限制
kernel.pid_max = 4194304
kernel.threads-max = 4194304
EOF

    # 应用配置
    sysctl --system >/dev/null 2>&1 || true
    ok "内核参数优化已应用: $SYSCTL_FILE"
}

# 应用系统限制优化
apply_limits() {
    info "正在应用系统限制优化..."
    create_backup "$LIMITS_FILE"
    
    # PAM limits 配置
    cat >"$LIMITS_FILE" <<'EOF'
# === Nginx Web 服务器系统限制优化 ===
# 文件描述符限制
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576

# 进程数限制
* soft nproc 1048576
* hard nproc 1048576
root soft nproc unlimited
root hard nproc unlimited

# 内存锁定限制
* soft memlock unlimited
* hard memlock unlimited

# 核心转储大小
* soft core unlimited
* hard core unlimited

# 栈大小限制
* soft stack 8192
* hard stack 8192
EOF

    # systemd 全局限制
    mkdir -p "$SYSTEMD_LIMITS_DIR"
    create_backup "$SYSTEMD_LIMITS_FILE"
    
    cat >"$SYSTEMD_LIMITS_FILE" <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
DefaultLimitMEMLOCK=infinity
DefaultLimitCORE=infinity
EOF

    ok "系统限制优化已应用: $LIMITS_FILE"
}

# 优化 Nginx 服务限制
apply_nginx_limits() {
    if ! command -v nginx >/dev/null 2>&1; then
        warn "Nginx 未安装，跳过 Nginx 专项优化"
        return 0
    fi
    
    info "正在应用 Nginx 服务限制优化..."
    mkdir -p "$NGINX_LIMITS_DIR"
    create_backup "$NGINX_LIMITS_FILE"
    
    cat >"$NGINX_LIMITS_FILE" <<'EOF'
[Service]
# Nginx 进程限制优化
LimitNOFILE=1048576
LimitNPROC=1048576
LimitMEMLOCK=infinity
LimitCORE=infinity

# 私有临时目录
PrivateTmp=true

# 进程优先级
Nice=-5
IOSchedulingClass=1
IOSchedulingPriority=4
EOF

    systemctl daemon-reload
    ok "Nginx 服务限制优化已应用: $NGINX_LIMITS_FILE"
    
    # 如果 Nginx 正在运行，提示重启
    if systemctl is-active nginx >/dev/null 2>&1; then
        warn "Nginx 正在运行，建议执行 'systemctl restart nginx' 使配置生效"
    fi
}

# 显示状态报告
show_status() {
    echo "=== 系统优化状态报告 ==="
    echo "时间: $(date '+%F %T')"
    echo
    
    echo "📁 配置文件状态:"
    [[ -f "$SYSCTL_FILE" ]] && echo "  ✓ 内核参数: $SYSCTL_FILE" || echo "  ✗ 内核参数: 未配置"
    [[ -f "$LIMITS_FILE" ]] && echo "  ✓ 系统限制: $LIMITS_FILE" || echo "  ✗ 系统限制: 未配置"
    [[ -f "$SYSTEMD_LIMITS_FILE" ]] && echo "  ✓ systemd 限制: $SYSTEMD_LIMITS_FILE" || echo "  ✗ systemd 限制: 未配置"
    [[ -f "$NGINX_LIMITS_FILE" ]] && echo "  ✓ Nginx 限制: $NGINX_LIMITS_FILE" || echo "  ✗ Nginx 限制: 未配置"
    echo
    
    echo "🔧 当前系统参数:"
    echo "  文件描述符软限制: $(ulimit -Sn)"
    echo "  文件描述符硬限制: $(ulimit -Hn)"
    echo "  系统最大文件数: $(cat /proc/sys/fs/file-max)"
    echo "  进程软限制: $(ulimit -Su)"
    echo "  进程硬限制: $(ulimit -Hu)"
    echo "  TCP 拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '未知')"
    echo "  最大连接队列: $(sysctl -n net.core.somaxconn 2>/dev/null || echo '未知')"
    echo
    
    if command -v nginx >/dev/null 2>&1; then
        echo "🌐 Nginx 状态:"
        if systemctl is-active nginx >/dev/null 2>&1; then
            echo "  状态: 运行中"
            echo "  进程数: $(pgrep nginx | wc -l)"
            echo "  主进程 PID: $(pgrep -f 'nginx: master' || echo '未找到')"
        else
            echo "  状态: 未运行"
        fi
        echo "  版本: $(nginx -v 2>&1 | cut -d' ' -f3)"
    fi
    echo
    
    echo "📊 系统资源使用:"
    echo "  CPU 负载: $(uptime | awk -F'load average:' '{print $2}')"
    echo "  内存使用: $(free | awk '/^Mem:/ {printf "%.1f%%", $3/$2 * 100.0}')"
    echo "  磁盘使用: $(df / | awk 'NR==2 {print $5}')"
}

# 生成 Nginx 配置建议
nginx_config_suggestions() {
    if ! command -v nginx >/dev/null 2>&1; then
        return 0
    fi
    
    echo "=== Nginx 配置优化建议 ==="
    echo "在 nginx.conf 中添加以下配置:"
    echo
    cat <<'EOF'
# 工作进程数（建议设置为 CPU 核心数）
worker_processes auto;

# 每个工作进程的最大文件描述符数
worker_rlimit_nofile 1048576;

events {
    # 每个工作进程的最大连接数
    worker_connections 65535;
    
    # 使用高效的事件模型
    use epoll;
    
    # 允许一个工作进程同时接受多个连接
    multi_accept on;
}

http {
    # 开启高效文件传输
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    
    # 连接超时设置
    keepalive_timeout 65;
    keepalive_requests 10000;
    
    # 客户端请求体大小限制
    client_max_body_size 100m;
    client_body_buffer_size 128k;
    
    # 压缩设置
    gzip on;
    gzip_vary on;
    gzip_min_length 1000;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    
    # 缓存设置
    open_file_cache max=100000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
}
EOF
    echo
}

#------------- 主程序 -------------
case "$ACTION" in
    apply)
        detect_system
        apply_sysctl
        apply_limits
        apply_nginx_limits
        show_status
        nginx_config_suggestions
        echo
        ok "🎉 系统优化完成！建议重启系统或重新登录以确保所有配置生效"
        warn "⚠️  如需重启 Nginx: systemctl restart nginx"
        ;;
    status)
        detect_system
        show_status
        ;;
    suggestions)
        nginx_config_suggestions
        ;;
    *)
        echo "用法: $0 [apply|status|suggestions]"
        echo
        echo "命令说明:"
        echo "  apply       - 应用所有系统优化配置"
        echo "  status      - 显示当前系统状态"
        echo "  suggestions - 显示 Nginx 配置建议"
        echo
        echo "示例:"
        echo "  $0 apply      # 应用优化"
        echo "  $0 status     # 查看状态"
        exit 1
        ;;
esac
```

## `universal_optimize.sh`

```bash
#!/usr/bin/env bash
# universal_optimize.sh
# https://github.com/buyi06/-Linux-/blob/main/universal_optimize.sh
# 通用安全网络优化（UDP/TCP缓冲、关闭网卡offload、可选IRQ绑定、开机自检）
# - 幂等可重复执行
# - 失败默认忽略（不锁机、不卡网）
# - 不修改应用/防火墙/代理配置
set -Eeuo pipefail

ACTION="${1:-apply}"
SYSCTL_FILE="/etc/sysctl.d/99-universal-net.conf"
LIMITS_FILE="/etc/security/limits.d/99-universal.conf"
SYSTEMD_LIMITS_DIR="/etc/systemd/system.conf.d"
SYSTEMD_LIMITS_FILE="${SYSTEMD_LIMITS_DIR}/99-universal-limits.conf"
OFFLOAD_UNIT="/etc/systemd/system/univ-offload@.service"
IRQPIN_UNIT="/etc/systemd/system/univ-irqpin@.service"
HEALTH_UNIT="/etc/systemd/system/univ-health.service"
ENV_FILE="/etc/default/universal-optimize"

#------------- helpers -------------
ok(){   printf "\033[32m%s\033[0m\n" "$*"; }
warn(){ printf "\033[33m%s\033[0m\n" "$*"; }
err(){  printf "\033[31m%s\033[0m\n" "$*"; }

detect_iface() {
  # IFACE 可由环境变量覆盖：IFACE=ens3 bash universal_optimize.sh apply
  if [[ -n "${IFACE:-}" && -e "/sys/class/net/${IFACE}" ]]; then
    echo "$IFACE"; return
  fi
  # 1) 优先路由探测
  local dev
  dev="$(ip -o route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
  if [[ -n "$dev" && -e "/sys/class/net/${dev}" ]]; then
    echo "$dev"; return
  fi
  # 2) 第一个非 lo 的 UP 接口
  dev="$(ip -o link show up 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}' || true)"
  if [[ -n "$dev" && -e "/sys/class/net/${dev}" ]]; then
    echo "$dev"; return
  fi
  # 3) 兜底：第一个非 lo 接口
  dev="$(ip -o link show 2>/dev/null | awk -F': ' '$2!="lo"{print $2; exit}' || true)"
  [[ -n "$dev" ]] && echo "$dev"
}

pkg_install() {
  # 仅在缺失时尝试安装 ethtool（静默失败也无所谓）
  command -v ethtool >/dev/null 2>&1 && return 0
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y ethtool >/dev/null 2>&1 || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install ethtool >/dev/null 2>&1 || true
  elif command -v yum >/dev/null 2>&1; then
    yum -y install ethtool >/dev/null 2>&1 || true
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install ethtool >/dev/null 2>&1 || true
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm ethtool >/dev/null 2>&1 || true
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache ethtool >/dev/null 2>&1 || true
  fi
}

runtime_sysctl_safe() {
  # 按键值对运行态注入，忽略不存在的键，避免报错
  local k v
  while IFS='=' read -r k v; do
    k="$(echo "$k" | xargs)"; v="$(echo "$v" | xargs)"
    [[ -z "$k" || "$k" =~ ^# ]] && continue
    sysctl -w "$k=$v" >/dev/null 2>&1 || true
  done <<'KV'
net.core.rmem_default=4194304
net.core.wmem_default=4194304
net.core.optmem_max=8388608
net.core.netdev_max_backlog=50000
net.core.somaxconn=16384
net.ipv4.ip_local_port_range=10240 65535
net.ipv4.udp_mem=8192 16384 32768
net.ipv4.udp_rmem_min=131072
net.ipv4.udp_wmem_min=131072
KV
}

apply_sysctl() {
  # 持久化 sysctl（键都很通用，内核缺失也无碍；加载失败不阻塞）
  cat >"$SYSCTL_FILE" <<'CONF'
# === universal-optimize: safe network tuning ===
net.core.rmem_default = 4194304
net.core.wmem_default = 4194304
net.core.optmem_max   = 8388608
net.core.netdev_max_backlog = 50000
net.core.somaxconn = 16384
net.ipv4.ip_local_port_range = 10240 65535
# UDP pages triple ≈ 32MB / 64MB / 128MB (4K page)
net.ipv4.udp_mem      = 8192 16384 32768
net.ipv4.udp_rmem_min = 131072
net.ipv4.udp_wmem_min = 131072
CONF
  # 运行态注入（避免因某些键不存在而报错）
  runtime_sysctl_safe
  # 持久加载（即使有键不存在也忽略退出码）
  sysctl --system >/dev/null 2>&1 || true
  ok "[universal-optimize] sysctl 已应用并持久化：$SYSCTL_FILE"
}

apply_limits() {
  # 提升文件句柄数（对交互用户与大多数服务友好）
  mkdir -p "$(dirname "$LIMITS_FILE")"
  cat >"$LIMITS_FILE" <<'LIM'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc  unlimited
* hard nproc  unlimited
LIM
  mkdir -p "$SYSTEMD_LIMITS_DIR"
  cat >"$SYSTEMD_LIMITS_FILE" <<'SVC'
[Manager]
DefaultLimitNOFILE=1048576
SVC
  # 不强制 daemon-reexec，留到下次引导或服务重启生效
  ok "[universal-optimize] ulimit 默认提升（新会话/服务生效）"
}

apply_offload_unit() {
  local iface="$1"
  # systemd 模板单元：绑定网卡设备、等待链路UP、关闭常见 offload
  cat >"$OFFLOAD_UNIT" <<'UNIT'
[Unit]
Description=Universal: disable NIC offloads for %i
BindsTo=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device network-online.target
Wants=network-online.target
ConditionPathExists=/sys/class/net/%i

[Service]
Type=oneshot
# 等链路UP（最长8秒）
ExecStartPre=/bin/sh -c 'for i in $(seq 1 16); do ip link show %i 2>/dev/null | grep -q "state UP" && exit 0; sleep 0.5; done; exit 0'
# 容错：自动寻找 ethtool；不支持的特性忽略
ExecStart=-/bin/bash -lc '
  ET=$(command -v ethtool || echo /usr/sbin/ethtool)
  if ! command -v ethtool >/dev/null 2>&1 && [[ ! -x "$ET" ]]; then
    echo "[offload] ethtool 不存在，跳过"
    exit 0
  fi
  $ET -K %i gro off gso off tso off lro off scatter-gather off rx-gro-hw off rx-udp-gro-forwarding off 2>/dev/null || true
'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable "univ-offload@${iface}.service" >/dev/null 2>&1 || true
  systemctl restart "univ-offload@${iface}.service" >/dev/null 2>&1 || true
  ok "[universal-optimize] systemd 持久化 offload 关闭：univ-offload@${iface}.service"

  # 立即尝试一次（即便 systemd 未生效也尽量落地）
  if command -v ethtool >/dev/null 2>&1 || [[ -x /usr/sbin/ethtool ]]; then
    (ethtool -K "$iface" gro off gso off tso off lro off scatter-gather off rx-gro-hw off rx-udp-gro-forwarding off >/dev/null 2>&1 || true)
    ok "[universal-optimize] 已对 $iface 进行一次性 offload 关闭尝试"
  fi
}

apply_irqpin_unit() {
  local iface="$1"
  # IRQ 绑定（KVM/virtio 多数没有主 IRQ / MSI，这里全程容错）
  cat >"$IRQPIN_UNIT" <<'UNIT'
[Unit]
Description=Universal: pin NIC IRQs of %i to CPU0 (safe)
BindsTo=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device
ConditionPathExists=/sys/class/net/%i

[Service]
Type=oneshot
ExecStart=-/bin/bash -lc '
  IF="%i"
  main_irq=$(cat /sys/class/net/$IF/device/irq 2>/dev/null || true)
  if [[ -n "$main_irq" && -w /proc/irq/$main_irq/smp_affinity ]]; then
    echo 1 > /proc/irq/$main_irq/smp_affinity 2>/dev/null && echo "[irq] 主 IRQ $main_irq -> CPU0"
  else
    echo "[irq] 未发现主 IRQ（虚拟网卡常见，跳过）"
  fi
  for f in /sys/class/net/$IF/device/msi_irqs/*; do
    [[ -f "$f" ]] || continue
    irq=$(basename "$f")
    echo 1 > /proc/irq/$irq/smp_affinity 2>/dev/null && echo "[irq] MSI IRQ $irq -> CPU0"
  done
  exit 0
'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable "univ-irqpin@${iface}.service" >/dev/null 2>&1 || true
  systemctl restart "univ-irqpin@${iface}.service" >/dev/null 2>&1 || true
  ok "[universal-optimize] IRQ 绑定服务已配置（缺 IRQ 时自动跳过）"
}

apply_health_unit() {
  # 持久记录一次自检到日志（不依赖网络，不依赖脚本路径）
  cat >"$ENV_FILE" <<EOF
IFACE="${IFACE}"
SYSCTL_FILE="${SYSCTL_FILE}"
EOF

  cat >"$HEALTH_UNIT" <<'UNIT'
[Unit]
Description=Universal Optimize: boot health report
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -lc '
  source /etc/default/universal-optimize 2>/dev/null || true
  IF="${IFACE:-$(ip -o route get 1.1.1.1 2>/dev/null | awk "/dev/ {for(i=1;i<=NF;i++) if(\$i==\"dev\"){print \$(i+1); exit}}")}"
  ET=$(command -v ethtool || echo /usr/sbin/ethtool)
  echo "=== 自检报告 ($(date "+%F %T")) ==="
  systemctl is-active "univ-offload@${IF:-$IF}.service" >/dev/null 2>&1 && echo "offload: active" || echo "offload: inactive"
  systemctl is-active "univ-irqpin@${IF:-$IF}.service"   >/dev/null 2>&1 && echo "irqpin : active" || echo "irqpin : inactive/ignored"
  [[ -n "${SYSCTL_FILE:-}" && -f "${SYSCTL_FILE:-}" ]] && echo "sysctl : ${SYSCTL_FILE}" || echo "sysctl : missing"
  if [[ -x "$ET" && -n "$IF" ]]; then
    $ET -k "$IF" 2>/dev/null | egrep -i "gro|gso|tso|lro|scatter-gather" | sed -n "1,40p" || true
  fi
  sysctl -n net.core.rmem_default net.core.wmem_default net.core.optmem_max \
             net.core.netdev_max_backlog net.core.somaxconn net.ipv4.udp_mem \
             net.ipv4.udp_rmem_min net.ipv4.udp_wmem_min 2>/dev/null | nl -ba || true
'
UNIT
  systemctl daemon-reload
  systemctl enable univ-health.service >/dev/null 2>&1 || true
}

status_report() {
  local iface="$1"
  echo "=== 状态报告 ($(date '+%F %T')) ==="
  echo "- 目标网卡：$iface"
  echo "- sysctl 文件：$SYSCTL_FILE"
  sysctl -n net.core.rmem_default net.core.wmem_default net.core.optmem_max \
           net.core.netdev_max_backlog net.core.somaxconn net.ipv4.udp_mem \
           net.ipv4.udp_rmem_min net.ipv4.udp_wmem_min 2>/dev/null | nl -ba || true
  echo
  local ET
  ET=$(command -v ethtool || echo /usr/sbin/ethtool)
  if [[ -x "$ET" ]]; then
    $ET -k "$iface" 2>/dev/null | egrep -i 'gro|gso|tso|lro|scatter-gather' | sed -n '1,60p' || true
  else
    warn "ethtool 不存在，无法显示 offload 细节"
  fi
  echo
  systemctl is-enabled "univ-offload@${iface}.service" 2>/dev/null || true
  systemctl is-active  "univ-offload@${iface}.service" 2>/dev/null || true
  systemctl is-enabled "univ-irqpin@${iface}.service" 2>/dev/null || true
  systemctl is-active  "univ-irqpin@${iface}.service" 2>/dev/null || true
}

repair_missing() {
  # 只补缺，不动已有
  [[ -f "$SYSCTL_FILE" ]] || apply_sysctl
  [[ -f "$LIMITS_FILE" ]] || apply_limits
  [[ -f "$OFFLOAD_UNIT" ]] || apply_offload_unit "$IFACE"
  [[ -f "$IRQPIN_UNIT"  ]] || apply_irqpin_unit "$IFACE"
  [[ -f "$HEALTH_UNIT"  ]] || apply_health_unit
  ok "✅ 缺失项已自动补齐"
}

#------------- main -------------
IFACE="$(detect_iface || true)"
if [[ -z "$IFACE" ]]; then
  err "[universal-optimize] 无法自动探测网卡，请用 IFACE=xxx 再试"
  exit 1
fi

case "$ACTION" in
  apply)
    pkg_install
    apply_sysctl
    apply_limits
    apply_offload_unit "$IFACE"
    apply_irqpin_unit "$IFACE"
    apply_health_unit
    status_report "$IFACE"
    ;;
  status)
    status_report "$IFACE"
    ;;
  repair)
    pkg_install
    repair_missing
    status_report "$IFACE"
    ;;
  *)
    echo "用法：bash $0 [apply|status|repair]"
    echo "示例：IFACE=ens3 bash $0 apply    # 手动指定网卡"
    exit 1
    ;;
esac
```

