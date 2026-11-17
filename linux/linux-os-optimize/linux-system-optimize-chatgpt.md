明白了 👍

你上传的脚本 /mnt/data/Linux-system-optimize.sh 我可以基于它优化出一个 **适用于 GCP Linux 实例（运行 Nginx Web 服务）** 的系统级性能调优脚本，重点关注：

- 系统资源限制（ulimit / systemd limits）
    
- 文件描述符（nofile）
    
- 网络内核参数（sysctl）
    
- CPU 与 I/O 优化
    

  

不包含 Nginx 的 nginx.conf 相关配置。

---

## **🧠 优化目标分析**

  

针对 GCP 上运行的 Nginx Web 服务器，系统层面瓶颈主要集中在：

1. **文件句柄限制不足（open files too many）**
    
2. **epoll/socket 连接数受限**
    
3. **TIME_WAIT 连接堆积**
    
4. **网络缓冲区过小**
    
5. **文件系统 IO 调度器未优化（尤其是虚拟化环境）**
    

---

## **✅ 优化脚本：**

## **linux-nginx-system-optimize.sh**

```
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

---

## **🧩 核心优化点说明**

|**类别**|**参数**|**说明**|
|---|---|---|
|**系统限制**|nofile|最大打开文件数（默认 1024 → 提升到 1M）|
|**进程数**|nproc|最大进程数限制|
|**TCP backlog**|net.core.somaxconn|提高监听队列长度，防止高并发丢包|
|**TIME_WAIT 优化**|tcp_tw_reuse|允许复用 TIME_WAIT 连接|
|**内核 socket 缓冲**|tcp_rmem/tcp_wmem|提升 TCP 吞吐能力|
|**端口范围**|ip_local_port_range|扩展可用临时端口范围|
|**BBR 拥塞控制**|tcp_congestion_control=bbr|提升高延迟网络性能|
|**Conntrack**|nf_conntrack_max|提升 NAT/防火墙跟踪表容量|

---

## **🔍 验证命令**

```
ulimit -n
systemctl show nginx | grep Limit
sysctl net.core.somaxconn
sysctl net.ipv4.tcp_congestion_control
```

---

## **⚠️ 注意事项**

1. **运行前请确认 root 权限**，否则 limits 无法生效。
    
2. **修改 systemd 限制后必须执行**：
    

```
systemctl daemon-reexec
systemctl daemon-reload
systemctl restart nginx
```

2.   
    
3. 如果 Nginx 以非 root 用户启动，请确保 /etc/security/limits.d/nginx.conf 中配置的用户一致。
    
4. 如为 **GCE e2 / n2 实例**，BBR 拥塞控制已默认支持。
    

---

是否希望我帮你在这个脚本基础上加入 **GCE 机器类型自动检测与动态优化**（例如根据 vCPU 调整 somaxconn、conntrack_max）？

那样可以在不同规格的 instance 上自动适配最优参数。