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