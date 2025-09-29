# Nginx Master-Worker 架构深度探测报告

## 目录
- [1. Nginx Master-Worker 架构概述](#1-nginx-master-worker-架构概述)
- [2. Master 进程详细分析](#2-master-进程详细分析)
- [3. Worker 进程详细分析](#3-worker-进程详细分析)
- [4. Master-Worker 通信机制](#4-master-worker-通信机制)
- [5. 进程生命周期管理](#5-进程生命周期管理)
- [6. Linux 文件描述符限制深度分析](#6-linux-文件描述符限制深度分析)
- [7. 性能调优与监控](#7-性能调优与监控)
- [8. 故障排查与诊断](#8-故障排查与诊断)
- [9. 实战案例分析](#9-实战案例分析)

---

## 1. Nginx Master-Worker 架构概述

### 1.1 架构设计理念

Nginx 采用多进程单线程的架构模式，这种设计具有以下优势：

```
┌─────────────────────────────────────────────────────────┐
│                    Nginx 架构图                          │
├─────────────────────────────────────────────────────────┤
│  Master Process (主进程)                                │
│  ├── 配置文件解析和验证                                   │
│  ├── 创建和管理 Worker 进程                              │
│  ├── 信号处理和进程间通信                                │
│  └── 平滑重启和配置重载                                  │
│                                                         │
│  Worker Process 1    Worker Process 2    Worker Process N│
│  ├── 处理客户端连接   ├── 处理客户端连接   ├── 处理客户端连接│
│  ├── HTTP 请求处理   ├── HTTP 请求处理   ├── HTTP 请求处理│
│  ├── 事件循环        ├── 事件循环        ├── 事件循环     │
│  └── 内存管理        └── 内存管理        └── 内存管理     │
└─────────────────────────────────────────────────────────┘
```

### 1.2 核心特性

- **进程隔离**: 每个 Worker 进程独立运行，一个进程崩溃不影响其他进程
- **无锁设计**: Worker 进程之间不共享内存，避免锁竞争
- **事件驱动**: 基于 epoll/kqueue 的异步非阻塞 I/O 模型
- **平滑重启**: 支持不中断服务的配置重载和版本升级

---

## 2. Master 进程详细分析

### 2.1 Master 进程职责

Master 进程是 Nginx 的控制中心，主要负责：

```c
// Master 进程主要功能模块
struct ngx_master_process {
    pid_t                 pid;           // 主进程 PID
    ngx_cycle_t          *cycle;         // 配置周期
    ngx_process_t        *processes;     // Worker 进程数组
    ngx_uint_t            process_slot;  // 进程槽位
    ngx_socket_t          channel[2];    // 进程间通信管道
    ngx_msec_t            delay;         // 延迟时间
    ngx_uint_t            sigio;         // SIGIO 信号标志
    ngx_uint_t            sigalrm;       // SIGALRM 信号标志
};
```

### 2.2 Master 进程启动流程

```bash
# Master 进程启动序列
1. 解析命令行参数
   └── ngx_get_options()
2. 初始化配置结构
   └── ngx_init_cycle()
3. 解析配置文件
   └── ngx_conf_parse()
4. 创建 PID 文件
   └── ngx_create_pidfile()
5. 创建 Worker 进程
   └── ngx_start_worker_processes()
6. 进入事件循环
   └── ngx_master_process_cycle()
```

### 2.3 信号处理机制

Master 进程处理的关键信号：

| 信号 | 作用 | 处理函数 |
|------|------|----------|
| SIGTERM/SIGINT | 快速关闭 | ngx_signal_handler() |
| SIGQUIT | 优雅关闭 | ngx_signal_handler() |
| SIGHUP | 重载配置 | ngx_signal_handler() |
| SIGUSR1 | 重新打开日志文件 | ngx_signal_handler() |
| SIGUSR2 | 平滑升级 | ngx_signal_handler() |
| SIGCHLD | 子进程状态变化 | ngx_signal_handler() |
| SIGWINCH | 优雅关闭 Worker | ngx_signal_handler() |

---

## 3. Worker 进程详细分析

### 3.1 Worker 进程架构

```c
// Worker 进程核心结构
struct ngx_worker_process {
    ngx_cycle_t          *cycle;         // 配置周期
    ngx_connection_t     *connections;   // 连接池
    ngx_event_t          *read_events;   // 读事件数组
    ngx_event_t          *write_events;  // 写事件数组
    ngx_uint_t            connection_n;  // 连接数量
    ngx_listening_t      *listening;     // 监听套接字
    ngx_event_actions_t  *actions;       // 事件处理函数
};
```

### 3.2 事件循环机制

Worker 进程的核心是事件循环：

```c
// 简化的事件循环伪代码
void ngx_worker_process_cycle() {
    for (;;) {
        // 1. 处理定时器事件
        ngx_event_expire_timers();
        
        // 2. 处理网络事件 (epoll_wait)
        ngx_process_events_and_timers();
        
        // 3. 处理 posted 事件
        ngx_event_process_posted();
        
        // 4. 检查进程退出标志
        if (ngx_exiting) {
            ngx_worker_process_exit();
        }
    }
}
```

### 3.3 连接处理流程

```
客户端连接 → accept() → 创建 ngx_connection_t → 
设置读写事件 → 加入 epoll → 事件触发 → 
HTTP 请求解析 → 业务逻辑处理 → 响应发送 → 
连接复用或关闭
```

---

## 4. Master-Worker 通信机制

### 4.1 进程间通信方式

Nginx 使用多种 IPC 机制：

#### 4.1.1 信号通信
```bash
# Master 向 Worker 发送信号
kill -QUIT <worker_pid>  # 优雅关闭
kill -TERM <worker_pid>  # 快速关闭
kill -USR1 <worker_pid>  # 重新打开日志
```

#### 4.1.2 管道通信
```c
// 创建进程间通信管道
if (socketpair(AF_UNIX, SOCK_STREAM, 0, ngx_processes[s].channel) == -1) {
    ngx_log_error(NGX_LOG_ALERT, cycle->log, ngx_errno,
                  "socketpair() failed while spawning \"%s\"", name);
    return NGX_INVALID_PID;
}
```

#### 4.1.3 共享内存
```c
// 共享内存结构
typedef struct {
    ngx_slab_pool_t  *shpool;
    ngx_rbtree_t      rbtree;
    ngx_rbtree_node_t sentinel;
} ngx_http_limit_req_shctx_t;
```

### 4.2 消息传递机制

```c
// 进程间消息结构
typedef struct {
    ngx_uint_t  command;    // 命令类型
    ngx_pid_t   pid;        // 进程 ID
    ngx_int_t   slot;       // 进程槽位
    ngx_fd_t    fd;         // 文件描述符
} ngx_channel_t;
```

---

## 5. 进程生命周期管理

### 5.1 Worker 进程创建

```c
// Worker 进程创建流程
static void ngx_start_worker_processes(ngx_cycle_t *cycle, ngx_int_t n, ngx_int_t type) {
    ngx_int_t      i;
    ngx_channel_t  ch;

    ch.command = NGX_CMD_OPEN_CHANNEL;

    for (i = 0; i < n; i++) {
        ngx_spawn_process(cycle, ngx_worker_process_cycle,
                         (void *) (intptr_t) i, "worker process", type);
        
        ch.pid = ngx_processes[ngx_process_slot].pid;
        ch.slot = ngx_process_slot;
        ch.fd = ngx_processes[ngx_process_slot].channel[0];

        ngx_pass_open_channel(cycle, &ch);
    }
}
```

### 5.2 进程监控与重启

Master 进程持续监控 Worker 进程状态：

```c
// 进程状态监控
static void ngx_master_process_cycle(ngx_cycle_t *cycle) {
    for (;;) {
        sigsuspend(&set);  // 等待信号
        
        if (ngx_reap) {
            ngx_reap = 0;
            ngx_log_debug0(NGX_LOG_DEBUG_EVENT, cycle->log, 0, "reap children");
            
            live = ngx_reap_children(cycle);
        }
        
        if (!live && (ngx_terminate || ngx_quit)) {
            ngx_master_process_exit(cycle);
        }
    }
}
```

### 5.3 平滑重启机制

```bash
# 平滑重启流程
1. 发送 SIGHUP 信号给 Master
   └── kill -HUP <master_pid>
2. Master 重新解析配置文件
   └── ngx_init_cycle()
3. 创建新的 Worker 进程
   └── ngx_start_worker_processes()
4. 向旧 Worker 发送 SIGQUIT 信号
   └── 优雅关闭旧进程
5. 等待旧进程处理完现有连接后退出
```

---

## 6. Linux 文件描述符限制深度分析

### 6.1 文件描述符概念

文件描述符 (File Descriptor, FD) 是 Linux 系统中用于标识打开文件的整数：

```c
// 文件描述符在内核中的表示
struct files_struct {
    atomic_t count;              // 引用计数
    struct fdtable __rcu *fdt;   // 文件描述符表
    struct fdtable fdtab;        // 默认文件描述符表
    spinlock_t file_lock;        // 自旋锁
    int next_fd;                 // 下一个可用 FD
    unsigned long close_on_exec_init[1];  // exec 时关闭标志
    unsigned long open_fds_init[1];       // 打开文件标志
    struct file __rcu * fd_array[NR_OPEN_DEFAULT];  // 文件指针数组
};
```

### 6.2 系统级别限制

#### 6.2.1 内核参数
```bash
# 查看系统级别文件描述符限制
cat /proc/sys/fs/file-max          # 系统最大文件描述符数
cat /proc/sys/fs/file-nr           # 当前分配的文件描述符数
cat /proc/sys/fs/nr_open           # 单个进程最大文件描述符数

# 设置系统级别限制
echo 1000000 > /proc/sys/fs/file-max
# 或在 /etc/sysctl.conf 中添加
fs.file-max = 1000000
fs.nr_open = 1048576
```

#### 6.2.2 内核数据结构
```c
// 系统文件表
struct files_stat_struct {
    unsigned long nr_files;      // 当前打开文件数
    unsigned long nr_free_files; // 空闲文件结构数
    unsigned long max_files;     // 最大文件数
};
```

### 6.3 进程级别限制

#### 6.3.1 ulimit 设置
```bash
# 查看当前进程限制
ulimit -n                    # 软限制
ulimit -Hn                   # 硬限制
ulimit -a                    # 所有限制

# 设置进程限制
ulimit -n 65535              # 临时设置
ulimit -Hn 65535             # 设置硬限制
```

#### 6.3.2 systemd 服务限制
```ini
# /etc/systemd/system/nginx.service
[Unit]
Description=The nginx HTTP and reverse proxy server
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
KillSignal=SIGQUIT
TimeoutStopSec=5
KillMode=process
PrivateTmp=true
LimitNOFILE=65535              # 设置文件描述符限制
LimitNPROC=65535               # 设置进程数限制

[Install]
WantedBy=multi-user.target
```

### 6.4 用户级别限制

#### 6.4.1 limits.conf 配置
```bash
# /etc/security/limits.conf
# 格式: <domain> <type> <item> <value>

# 为 nginx 用户设置限制
nginx    soft    nofile    65535
nginx    hard    nofile    65535
nginx    soft    nproc     65535
nginx    hard    nproc     65535

# 为所有用户设置限制
*        soft    nofile    65535
*        hard    nofile    65535

# 为特定组设置限制
@nginx   soft    nofile    65535
@nginx   hard    nofile    65535
```

#### 6.4.2 PAM 模块配置
```bash
# /etc/pam.d/common-session
session required pam_limits.so

# /etc/pam.d/login
session required pam_limits.so
```

### 6.5 Nginx 特定配置

#### 6.5.1 worker_rlimit_nofile 指令
```nginx
# nginx.conf 全局配置
user nginx;
worker_processes auto;
worker_rlimit_nofile 65535;    # Worker 进程文件描述符限制

events {
    worker_connections 16384;   # 每个 Worker 的连接数
    use epoll;
    multi_accept on;
}
```

#### 6.5.2 计算公式
```
总连接数 = worker_processes × worker_connections
所需 FD = 总连接数 × 2 (每个连接需要 2 个 FD: 客户端 + 上游)
推荐设置: worker_rlimit_nofile ≥ worker_connections × 2
```

### 6.6 监控文件描述符使用情况

#### 6.6.1 系统级监控
```bash
# 查看系统文件描述符使用情况
cat /proc/sys/fs/file-nr
# 输出格式: 已分配 已使用 最大值

# 查看进程文件描述符使用情况
ls -la /proc/<pid>/fd | wc -l
lsof -p <pid> | wc -l

# 实时监控
watch -n 1 'cat /proc/sys/fs/file-nr'
```

#### 6.6.2 Nginx 进程监控
```bash
# 查看 Nginx Master 进程 FD 使用情况
nginx_master_pid=$(cat /var/run/nginx.pid)
ls -la /proc/$nginx_master_pid/fd | wc -l

# 查看所有 Nginx Worker 进程 FD 使用情况
for pid in $(pgrep -f "nginx: worker"); do
    echo "Worker PID $pid: $(ls -la /proc/$pid/fd 2>/dev/null | wc -l) FDs"
done
```

#### 6.6.3 监控脚本
```bash
#!/bin/bash
# nginx_fd_monitor.sh

NGINX_PID_FILE="/var/run/nginx.pid"
LOG_FILE="/var/log/nginx/fd_monitor.log"

if [ ! -f "$NGINX_PID_FILE" ]; then
    echo "Nginx PID file not found" >> $LOG_FILE
    exit 1
fi

MASTER_PID=$(cat $NGINX_PID_FILE)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# 系统级别 FD 使用情况
SYSTEM_FD=$(cat /proc/sys/fs/file-nr | awk '{print $1}')
SYSTEM_MAX=$(cat /proc/sys/fs/file-max)

# Master 进程 FD 使用情况
MASTER_FD=$(ls -la /proc/$MASTER_PID/fd 2>/dev/null | wc -l)

# Worker 进程 FD 使用情况
WORKER_FDS=""
for pid in $(pgrep -P $MASTER_PID); do
    worker_fd=$(ls -la /proc/$pid/fd 2>/dev/null | wc -l)
    WORKER_FDS="$WORKER_FDS Worker-$pid:$worker_fd"
done

echo "[$TIMESTAMP] System: $SYSTEM_FD/$SYSTEM_MAX Master: $MASTER_FD $WORKER_FDS" >> $LOG_FILE
```

---

## 7. 性能调优与监控

### 7.1 关键性能指标

#### 7.1.1 进程级指标
```bash
# CPU 使用率
top -p $(pgrep nginx)
htop -p $(pgrep nginx | tr '\n' ',' | sed 's/,$//')

# 内存使用情况
ps aux | grep nginx
pmap -d <nginx_pid>

# 文件描述符使用情况
lsof -p <nginx_pid> | wc -l
```

#### 7.1.2 系统级指标
```bash
# 网络连接状态
ss -tuln | grep :80
ss -tuln | grep :443
netstat -an | grep :80 | wc -l

# 系统负载
uptime
cat /proc/loadavg
```

### 7.2 性能调优参数

#### 7.2.1 Worker 进程优化
```nginx
# 基于 CPU 核心数的配置
worker_processes auto;
worker_cpu_affinity auto;

# 基于内存的配置
worker_rlimit_nofile 65535;
worker_rlimit_core 50M;

events {
    worker_connections 16384;
    use epoll;
    multi_accept on;
    accept_mutex off;
}
```

#### 7.2.2 内存优化
```nginx
http {
    # 连接池大小
    connection_pool_size 256;
    
    # 请求池大小
    request_pool_size 4k;
    
    # 客户端缓冲区
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    client_body_buffer_size 128k;
    
    # 代理缓冲区
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;
    proxy_busy_buffers_size 8k;
}
```

### 7.3 监控工具集成

#### 7.3.1 Prometheus 监控
```nginx
# nginx-prometheus-exporter 配置
location /nginx_status {
    stub_status on;
    access_log off;
    allow 127.0.0.1;
    deny all;
}
```

#### 7.3.2 自定义监控脚本
```bash
#!/bin/bash
# nginx_performance_monitor.sh

NGINX_STATUS_URL="http://localhost/nginx_status"
METRICS_FILE="/var/log/nginx/metrics.log"

# 获取 Nginx 状态
STATUS=$(curl -s $NGINX_STATUS_URL)
ACTIVE_CONNECTIONS=$(echo "$STATUS" | grep "Active connections" | awk '{print $3}')
ACCEPTS=$(echo "$STATUS" | tail -n 1 | awk '{print $1}')
HANDLED=$(echo "$STATUS" | tail -n 1 | awk '{print $2}')
REQUESTS=$(echo "$STATUS" | tail -n 1 | awk '{print $3}')

# 计算处理率
HANDLED_RATE=$(echo "scale=2; $HANDLED / $ACCEPTS * 100" | bc)

# 记录指标
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$TIMESTAMP] Active: $ACTIVE_CONNECTIONS, Handled Rate: $HANDLED_RATE%" >> $METRICS_FILE
```

---

## 8. 故障排查与诊断

### 8.1 常见问题诊断

#### 8.1.1 文件描述符耗尽
```bash
# 症状检查
dmesg | grep "Too many open files"
journalctl -u nginx | grep "Too many open files"

# 诊断步骤
1. 检查系统限制: cat /proc/sys/fs/file-max
2. 检查进程限制: cat /proc/<pid>/limits
3. 检查当前使用: lsof -p <pid> | wc -l
4. 检查配置: grep worker_rlimit_nofile /etc/nginx/nginx.conf
```

#### 8.1.2 Worker 进程异常退出
```bash
# 检查错误日志
tail -f /var/log/nginx/error.log

# 检查系统日志
journalctl -u nginx -f

# 检查核心转储
ls -la /var/crash/
gdb nginx core.<pid>
```

#### 8.1.3 性能问题诊断
```bash
# CPU 使用率分析
perf top -p <nginx_pid>
strace -p <nginx_pid> -c

# 内存使用分析
valgrind --tool=massif nginx -g 'daemon off;'
pmap -x <nginx_pid>

# 网络连接分析
ss -tuln | grep nginx
tcpdump -i any -w nginx_traffic.pcap port 80
```

### 8.2 调试工具

#### 8.2.1 GDB 调试
```bash
# 附加到运行中的进程
gdb -p <nginx_pid>

# 常用 GDB 命令
(gdb) info threads          # 查看线程信息
(gdb) bt                    # 查看调用栈
(gdb) print variable        # 打印变量值
(gdb) continue              # 继续执行
```

#### 8.2.2 SystemTap 脚本
```systemtap
#!/usr/bin/env stap
# nginx_monitor.stp

probe process("/usr/sbin/nginx").function("ngx_http_process_request") {
    printf("Processing request: %s\n", user_string($r->uri.data))
}

probe process("/usr/sbin/nginx").function("ngx_http_finalize_request") {
    printf("Request completed\n")
}
```

---

## 9. 实战案例分析

### 9.1 高并发场景优化

#### 9.1.1 问题描述
- 服务器: 8 核 CPU, 32GB 内存
- 并发连接: 50,000+
- 问题: Worker 进程 CPU 使用率过高，响应延迟增加

#### 9.1.2 诊断过程
```bash
# 1. 检查当前配置
grep -E "worker_processes|worker_connections" /etc/nginx/nginx.conf
# 输出: worker_processes 1; worker_connections 1024;

# 2. 检查系统资源
top -p $(pgrep nginx)
# CPU 使用率: 95%+

# 3. 检查文件描述符
ulimit -n
# 输出: 1024 (不足)

# 4. 检查网络连接
ss -s
# TCP: 45000 (established)
```

#### 9.1.3 优化方案
```nginx
# 优化后的配置
user nginx;
worker_processes 8;                    # 匹配 CPU 核心数
worker_rlimit_nofile 65535;           # 增加 FD 限制
worker_cpu_affinity auto;             # CPU 亲和性

events {
    worker_connections 8192;           # 增加连接数
    use epoll;
    multi_accept on;
    accept_mutex off;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 30;
    
    # 优化缓冲区
    client_body_buffer_size 128k;
    client_max_body_size 10m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    
    # 启用压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript;
}
```

#### 9.1.4 系统级优化
```bash
# /etc/security/limits.conf
nginx soft nofile 65535
nginx hard nofile 65535

# /etc/sysctl.conf
fs.file-max = 1000000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
```

#### 9.1.5 优化结果
```bash
# 优化前后对比
指标                优化前      优化后      改善
CPU 使用率          95%        65%        -30%
平均响应时间        500ms      150ms      -70%
并发连接数          10,000     50,000     +400%
错误率              2%         0.1%       -95%
```

### 9.2 内存泄漏问题排查

#### 9.2.1 问题现象
- Nginx Worker 进程内存持续增长
- 系统可用内存逐渐减少
- 最终导致 OOM Killer 杀死进程

#### 9.2.2 排查步骤
```bash
# 1. 监控内存使用趋势
while true; do
    ps aux | grep nginx | grep -v grep
    sleep 60
done > memory_usage.log

# 2. 使用 Valgrind 检测内存泄漏
valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all \
         --track-origins=yes --log-file=valgrind.log \
         nginx -g 'daemon off;'

# 3. 分析内存映射
pmap -x <nginx_pid> > memory_map.txt
cat /proc/<nginx_pid>/smaps > smaps.txt
```

#### 9.2.3 解决方案
```nginx
# 配置内存限制和回收
http {
    # 限制请求体大小
    client_max_body_size 1m;
    client_body_buffer_size 128k;
    
    # 设置合理的超时
    client_body_timeout 10s;
    client_header_timeout 10s;
    send_timeout 10s;
    
    # 启用连接复用
    upstream backend {
        server 127.0.0.1:8080;
        keepalive 32;
        keepalive_requests 100;
        keepalive_timeout 60s;
    }
}
```

---

## 总结

Nginx 的 Master-Worker 架构是一个高效、稳定的多进程模型，通过合理配置和系统调优，可以充分发挥其性能优势。关键要点包括：

1. **架构理解**: 掌握 Master-Worker 的职责分工和通信机制
2. **资源配置**: 合理设置 worker_processes 和 worker_connections
3. **系统限制**: 正确配置文件描述符和其他系统资源限制
4. **性能监控**: 建立完善的监控体系，及时发现和解决问题
5. **故障排查**: 掌握常用的调试工具和排查方法

通过深入理解这些概念和实践，可以构建高性能、高可用的 Nginx 服务。