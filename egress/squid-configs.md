# Squid 代理配置文件

## 1. GKE 内部 Squid 配置 (一级代理)

### 1.1 squid.conf (GKE Squid)

```bash
# /etc/squid/squid.conf - GKE 内部 Squid 配置

# 基本配置
http_port 3128
coredump_dir /var/spool/squid

# 内存和缓存配置
cache_mem 256 MB
maximum_object_size_in_memory 512 KB
cache_dir ufs /var/spool/squid 1000 16 256

# 日志配置
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
pid_filename /var/run/squid.pid

# ACL 定义
acl localnet src 10.0.0.0/8     # GKE Pod CIDR
acl localnet src 172.16.0.0/12  # GKE Service CIDR
acl localnet src 192.168.0.0/16

# 允许的目标域名
acl allowed_domains dstdomain .microsoft.com
acl allowed_domains dstdomain .microsoftonline.com
acl allowed_domains dstdomain .azure.com
acl allowed_domains dstdomain login.microsoft.com

# HTTP 方法控制
acl Safe_ports port 80          # http
acl Safe_ports port 443         # https
acl CONNECT method CONNECT

# 访问控制规则
http_access deny !Safe_ports
http_access deny CONNECT !allowed_domains
http_access allow localnet allowed_domains
http_access deny all

# 二级代理配置 (关键配置)
cache_peer int-proxy.aibang.com parent 3128 0 no-query default
never_direct allow all

# 转发配置
forwarded_for on
via on

# 错误页面
error_directory /usr/share/squid/errors/English

# 刷新模式
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320

# 性能优化
client_lifetime 1 hour
half_closed_clients off
```

### 1.2 启动脚本

```bash
#!/bin/bash
# start-squid.sh

# 创建必要目录
mkdir -p /var/log/squid
mkdir -p /var/spool/squid
mkdir -p /var/run

# 初始化缓存目录
squid -z

# 启动 Squid
exec squid -N -d 1
```

## 2. GCE VM Squid 配置 (二级代理)

### 2.1 squid.conf (GCE VM)

```bash
# /etc/squid/squid.conf - GCE VM 二级代理配置

# 基本配置
http_port 3128
coredump_dir /var/spool/squid

# 内存和缓存配置
cache_mem 512 MB
maximum_object_size_in_memory 1 MB
cache_dir ufs /var/spool/squid 5000 16 256

# 日志配置 - 详细审计
access_log /var/log/squid/access.log combined
cache_log /var/log/squid/cache.log
pid_filename /var/run/squid.pid

# 自定义日志格式 - 包含更多审计信息
logformat combined %>a %[ui %[un [%tl] "%rm %ru HTTP/%rv" %>Hs %<st "%{Referer}>h" "%{User-Agent}>h" %Ss:%Sh %tr

# ACL 定义
acl gke_cluster src 10.128.0.0/20    # GKE 集群 CIDR
acl gke_squid src 10.128.1.100/32    # GKE Squid IP (示例)

# 允许的目标域名 (更严格的控制)
acl microsoft_domains dstdomain .microsoft.com
acl microsoft_domains dstdomain .microsoftonline.com
acl microsoft_domains dstdomain .azure.com
acl microsoft_domains dstdomain login.microsoft.com
acl microsoft_domains dstdomain graph.microsoft.com

# 时间控制 (可选)
acl business_hours time MTWHF 08:00-18:00

# HTTP 方法和端口
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

# 访问控制规则
http_access deny !Safe_ports
http_access deny CONNECT !microsoft_domains
http_access allow gke_squid microsoft_domains
http_access deny all

# 直接访问外网
never_direct deny all
always_direct allow all

# 转发配置
forwarded_for on
via on

# 错误页面
error_directory /usr/share/squid/errors/English

# 刷新模式
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320

# 性能优化
client_lifetime 2 hours
half_closed_clients off
tcp_outgoing_address 10.128.2.100  # VM 的出口 IP

# 审计增强
strip_query_terms off
log_fqdn on
```

### 2.2 日志轮转配置

```bash
# /etc/logrotate.d/squid
/var/log/squid/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 640 squid squid
    postrotate
        /usr/bin/systemctl reload squid
    endscript
}
```

## 3. 监控和告警配置

### 3.1 Squid 状态监控

```bash
# squid-monitor.sh
#!/bin/bash

# 检查 Squid 状态
check_squid_status() {
    if ! pgrep squid > /dev/null; then
        echo "ERROR: Squid is not running"
        return 1
    fi
    
    # 检查端口监听
    if ! netstat -ln | grep :3128 > /dev/null; then
        echo "ERROR: Squid is not listening on port 3128"
        return 1
    fi
    
    echo "OK: Squid is running"
    return 0
}

# 检查连接数
check_connections() {
    local conn_count=$(netstat -an | grep :3128 | grep ESTABLISHED | wc -l)
    echo "INFO: Current connections: $conn_count"
    
    if [ $conn_count -gt 100 ]; then
        echo "WARNING: High connection count: $conn_count"
    fi
}

# 检查缓存使用率
check_cache_usage() {
    local cache_usage=$(squidclient -h localhost cache_object://localhost/info | grep "Storage LRU Expiration Age" | awk '{print $5}')
    echo "INFO: Cache usage: $cache_usage"
}

# 主函数
main() {
    echo "=== Squid Monitor $(date) ==="
    check_squid_status
    check_connections
    check_cache_usage
    echo "=========================="
}

main "$@"
```

## 4. 测试配置

### 4.1 连通性测试

```bash
# test-proxy.sh
#!/bin/bash

PROXY_HOST="microsoft.intra.aibang.local"
PROXY_PORT="3128"
TEST_URL="https://login.microsoft.com"

echo "Testing proxy connectivity..."

# 测试代理连接
curl -x http://${PROXY_HOST}:${PROXY_PORT} \
     -H "User-Agent: Test-Client/1.0" \
     -v \
     --connect-timeout 10 \
     --max-time 30 \
     ${TEST_URL}

echo "Exit code: $?"
```

### 4.2 ACL 测试

```bash
# test-acl.sh
#!/bin/bash

PROXY="http://microsoft.intra.aibang.local:3128"

# 测试允许的域名
echo "Testing allowed domain..."
curl -x $PROXY https://login.microsoft.com -I

# 测试被拒绝的域名
echo "Testing blocked domain..."
curl -x $PROXY https://google.com -I

# 测试 HTTPS CONNECT
echo "Testing HTTPS CONNECT..."
curl -x $PROXY https://graph.microsoft.com -I
```