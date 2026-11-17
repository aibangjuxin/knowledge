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
