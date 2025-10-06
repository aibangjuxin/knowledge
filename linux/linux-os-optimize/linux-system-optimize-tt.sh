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