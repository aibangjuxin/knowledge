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

