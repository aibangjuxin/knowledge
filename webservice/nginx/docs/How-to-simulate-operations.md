# Nginx "Too many open files" 模拟测试操作指南

## 目录
- [1. 背景与目标](#1-背景与目标)
- [2. 原理分析](#2-原理分析)
- [3. 方法一：低 FD 限制 + 高并发压测](#3-方法一低-fd-限制--高并发压测)
- [4. 方法二：慢请求耗尽连接](#4-方法二慢请求耗尽连接)
- [5. 方法三：打开文件泄漏（Keep-Alive 不释放）](#5-方法三打开文件泄漏keep-alive-不释放)
- [6. 方法四：ulimit 降级 + ab/wrk 并发](#6-方法四ulimit-降级--abwrk-并发)
- [7. 方法五：代理上游 FD 泄漏](#7-方法五代理上游-fd-泄漏)
- [8. 方法六：子请求链耗尽 FD](#8-方法六子请求链耗尽-fd)
- [9. 各方法对比与选择建议](#9-各方法对比与选择建议)
- [10. 配置参考：让 Nginx 恢复正常](#10-配置参考让-nginx-恢复正常)

---

## 1. 背景与目标

### 1.1 什么是 "Too many open files"

```
# 内核报错通常是这种形式
nginx[12345]: worker process 12346 exited with code 1
nginx[12345]: signal process started
nginx: could not open error log file: Too many open files
```

根本原因是 **文件描述符（FD）耗尽**。每个 TCP 连接、打开的文件、socket 都占用一个 FD，而 FD 有系统级、用户级、进程级三层限制。

### 1.2 FD 消耗账本

Nginx 典型场景下一个连接/请求消耗的 FD 数量：

| 资源类型 | FD 消耗 | 说明 |
|---------|--------|------|
| 客户端连接 | 1 | accept 后 |
| upstream 连接 | 1 | 代理到后端 |
| 静态文件打开 | 1 | `open()` 一个文件 |
| 日志文件打开 | 1 | error/access log |
| 共享内存映射 | 1 | `shmopen()` |
| **单请求总计** | **2～4+** | 视配置而定 |

**核心公式**（来自 nginx-master-worker.md §6.5.2）：
```
总 FD 需求 = (worker_connections × 2) + worker_processes × 固定开销
```

### 1.3 测试目标

1. **稳定复现** — 在任意环境下都能触发 `Too many open files`
2. **可逆可控** — 不需要重启进程，改配置即恢复
3. **工具通用** — 不依赖特定商业软件，用开源/系统工具

---

## 2. 原理分析

### 2.1 三层 FD 限制

```
┌─────────────────────────────────────────────────────────┐
│  系统级 (fs.file-max)                                    │
│  ┌─────────────────────────────────────────────────┐     │
│  │  用户级 (/etc/security/limits.conf)               │    │
│  │  ┌─────────────────────────────────────────┐     │    │
│  │  │  进程级 (worker_rlimit_nofile / ulimit)   │    │    │
│  │  │  ┌─────────────────────────────────┐     │    │    │
│  │  │  │  Nginx Worker 可用 FD           │     │    │    │
│  │  │  └─────────────────────────────────┘     │    │    │
│  │  └─────────────────────────────────────────┘     │    │
│  └─────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Nginx 何时检查 FD

Nginx 在以下路径检查/消耗 FD：

```
启动阶段:
  ngx_init_cycle()
    → open() PID 文件            → 1 FD
    → open() 配置文件            → 1 FD
    → open() error_log 文件      → 1 FD
    → shm_open() 共享内存        → 1 FD
    → socketpair() 进程间通道    → 2 FD/worker

运行阶段:
  ngx_http_init_connection()    → 每个客户端连接 1 FD
  ngx_http_file_cache_open()    → 静态文件 1 FD
  upstream keepalive            → upstream 1 FD
```

### 2.3 触发思路汇总

| 触发思路 | 核心机制 | 操作难度 | 风险 |
|---------|---------|---------|------|
| 压测连接耗尽 | 并发 > FD 上限 | ⭐⭐ | 低 |
| 慢客户端占位 | 请求不释放连接 | ⭐⭐ | 低 |
| 文件描述符泄漏 | keepalive_timeout=0 | ⭐ | 低 |
| 上游连接泄漏 | upstream 超时不释放 | ⭐⭐⭐ | 中 |
| 子请求链耗尽 | internal redirect 循环 | ⭐⭐⭐ | 中 |
| 日志文件耗尽 | 每个请求写不同文件 | ⭐⭐⭐ | 中 |

---

## 3. 方法一：低 FD 限制 + 高并发压测

### 3.1 思路

直接用压测工具（ab/wrk/hey）发起大量并发请求，配合人为压低的 FD 限制，让连接数超过 Nginx 可用 FD 数量。

### 3.2 操作步骤

**Step 1: 设置极低的 FD 限制**

```bash
# 当前默认（通常较高）
ulimit -n
# 输出: 65535 或更高

# 临时降级到极低值（模拟低资源环境）
ulimit -n 256
ulimit -Hn 256
```

**Step 2: 启动 Nginx（限制生效）**

```bash
# 检查当前 worker_rlimit_nofile 配置
grep -E "worker_rlimit_nofile|worker_connections" /etc/nginx/nginx.conf

# 如果要更严格限制，直接写入配置
# 在 /etc/nginx/nginx.conf 的 events {} 之前插入:
# worker_rlimit_nofile 200;
```

**Step 3: 压测**

```bash
# 用 wrk（推荐，比 ab 更强）
wrk -t4 -c200 -d30s http://localhost:80/

# 或用 ab（系统自带）
ab -k -t 30 -c 200 -n 1000000 http://localhost:80/

# 或用 hey（支持 HTTP/2）
hey -t 30 -c 200 -m GET http://localhost:80/
```

> **关键参数**：并发数 `c` 必须 **超过** `worker_rlimit_nofile`。假设 `worker_rlimit_nofile = 200`，`worker_connections = 100`，两个 worker 共 200 连接容量，一旦并发 >200 立即耗尽。

### 3.3 观察报错

```bash
# error.log 中的典型错误
tail -f /var/log/nginx/error.log | grep -i "too many open files"

# dmesg 也会出现
dmesg | grep "Too many open files"

# 查看 FD 使用情况
watch -n 0.5 'ls -la /proc/$(pgrep -f "nginx: worker")./fd 2>/dev/null | wc -l'
```

### 3.4 验证脚本

```bash
#!/bin/bash
# simulate_via_load.sh
# 压测触发 Too many open files

set -e
ULIMIT_N=${1:-200}
TARGET_URL=${2:-"http://127.0.0.1:80/"}
CONCURRENCY=${3:-250}
DURATION=${4:-20}

echo "[*] 临时降低 FD 限制到 $ULIMIT_N"
ulimit -n $ULIMIT_N
ulimit -Hn $ULIMIT_N
echo "[*] 当前 ulimit -n: $(ulimit -n)"

echo "[*] 等待 2s 让配置生效"
sleep 2

echo "[*] 开始压测 (并发=$CONCURRENCY, 时间=${DURATION}s)"
wrk -t4 -c$CONCURRENCY -d${DURATION}s "$TARGET_URL" &

PID=$!
sleep 1

echo "[*] 监控 error.log..."
timeout $DURATION tail -f /var/log/nginx/error.log &
TAIL_PID=$!

wait $PID
kill $TAIL_PID 2>/dev/null || true

echo ""
echo "[*] 检查 dmesg..."
dmesg | grep -i "too many open files" && echo "[+] 成功触发！" || echo "[-] 未触发，检查日志"
```

**用法**:
```bash
bash simulate_via_load.sh 200 http://127.0.0.1:80/ 250 20
```

---

## 4. 方法二：慢客户端占位（Slow Loris）

### 4.1 思路

慢客户端只发送 HTTP 请求头但不发送 body，占用连接但几乎不消耗 CPU。配合短 timeout 配置，让连接迟迟不释放，快速耗尽 worker_connections。

### 4.2 操作步骤

**Step 1: 配置短超时 + 宽松连接限制（故意让问题更快出现）**

```nginx
# nginx.conf
http {
    # 设置极短的读超时，强制客户端保持连接
    client_header_timeout 5s;
    client_body_timeout 5s;
    
    # 保持连接不释放
    keepalive_timeout 65s;
    keepalive_requests 100;
    
    # 禁掉 client_body 限制（让客户端发数据）
    client_max_body_size 100m;
}
```

**Step 2: 用 slowhttptest 或脚本制造慢客户端**

```bash
# slowhttptest（推荐）
slowhttptest -c 1000 -B -i 100 -r 50 -t GET -u http://127.0.0.1:80/ -timeout 30

# 或者用 Python 脚本（无需安装额外工具）
python3 - <<'EOF'
import socket, time
for i in range(500):
    s = socket.socket()
    s.settimeout(300)
    s.connect(('127.0.0.1', 80))
    # 发送请求头，不发送 body
    s.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
    time.sleep(65)  # 保持连接不释放
EOF
```

### 4.3 验证

```bash
# 观察 established 连接数
watch -n 1 'ss -tn | grep :80 | grep ESTAB | wc -l'

# 当连接数接近 worker_connections × workers 时会开始报错
```

---

## 5. 方法三：文件描述符泄漏（Keep-Alive 不释放）

### 5.1 思路

利用 `keepalive_requests=1` 配合不关闭连接，让每个请求都留下一个"漏掉的" FD。或者利用 `open_file_cache` 误配置导致 FD 不释放。

### 5.2 操作步骤

**Step 1: 配置易泄漏的场景**

```nginx
http {
    # 打开文件缓存，但max过小会导致重复打开
    open_file_cache max=10 inactive=30s;
    open_file_cache_min_uses 1;
    open_file_cache_valid 30s;
    
    # keepalive 设置让连接复用
    keepalive_timeout 60s;
    keepalive_requests 1000;
}
```

**Step 2: 触发方式 — 大量短命文件**

```bash
#!/bin/bash
# simulate_via_file_leak.sh
# 为每个请求打开不同的文件，耗尽 FD

for i in $(seq 1 10000); do
    curl -s "http://127.0.0.1:80/static/file_$i.txt" > /dev/null &
    # 每个文件都会导致 Nginx open() 消耗一个 FD
    [ $((i % 100)) -eq 0 ] && echo "[*] Sent $i requests..."
done
wait
```

**Step 3: 配合低 FD 限制**

```nginx
# worker_rlimit_nofile 设置很低
worker_rlimit_nofile 100;

events {
    worker_connections 50;
}
```

这样每个 worker 只有 50 个连接容量，一旦文件缓存占用 + 连接超过 100 就立即报 `Too many open files`。

---

## 6. 方法四：ulimit 降级 + ab/wrk 并发

### 6.1 思路

这是最直接、最通用的方法。不改 Nginx 配置，直接用系统 `ulimit` 把 FD 限制降到一个很低的值，然后用高并发压测击穿这个限制。

### 6.2 操作步骤

**Step 1: 查询当前所有限制**

```bash
echo "=== 系统级 ==="
cat /proc/sys/fs/file-max
cat /proc/sys/fs/nr_open

echo "=== 用户级 ==="
cat /etc/security/limits.conf | grep nofile

echo "=== 进程级（当前 shell）==="
ulimit -n
ulimit -Hn

echo "=== Nginx 进程 ==="
for pid in $(pgrep -f "nginx: worker"); do
    echo "PID $pid: $(cat /proc/$pid/limits | grep 'Max open files' | awk '{print $4}')"
done
```

**Step 2: 降级 ulimit + 启动 Nginx**

```bash
# 临时降级（仅影响当前 shell 及其子进程）
ulimit -n 128
ulimit -Hn 128

# 如果 Nginx 通过 systemd 启动，需要改 service 文件
# /etc/systemd/system/nginx.service
# [Service]
# LimitNOFILE=128

# 重载 systemd 并重启
sudo systemctl daemon-reload
sudo systemctl restart nginx
```

**Step 3: 压测**

```bash
# 高并发 ab
ab -k -t 20 -c 150 -n 10000000 http://127.0.0.1:80/

# 或 wrk
wrk -t4 -c150 -d20s http://127.0.0.1:80/
```

### 6.3 关键：找到精确的临界值

```bash
#!/bin/bash
# find_threshold.sh
# 二分查找触发报错的最小并发数

ULIMIT_N=200
TARGET_URL="http://127.0.0.1:80/"
ulimit -n $ULIMIT_N

low=50; high=500
while [ $low -le $high ]; do
    mid=$(( (low + high) / 2 ))
    echo "[*] Testing concurrency=$mid (ulimit=$ULIMIT_N)"
    
    if wrk -t2 -c$mid -d5s -s /dev/null "$TARGET_URL" 2>&1 | grep -q "Too many open files\|Socket errors"; then
        echo "[+] 触发报错 at c=$mid"
        high=$((mid - 1))
    else
        echo "[-] 未触发"
        low=$((mid + 1))
    fi
    sleep 1
done
echo "[*] 临界值接近 c=$low"
```

---

## 7. 方法五：代理上游 FD 泄漏

### 7.1 思路

Nginx 作为反向代理时，每个 upstream 连接也消耗一个 FD。如果 upstream 服务响应慢或超时，大量 upstream 连接堆积，会把 FD 耗尽。配合 `proxy_cache` 或 `keepalive` 误配置会加剧。

### 7.2 操作步骤

**Step 1: 配置有问题的 upstream**

```nginx
http {
    upstream slow_backend {
        server 127.0.0.1:9999;  # 不存在的慢服务
        keepalive 100;           # 错误的 keepalive 设置
    }
    
    server {
        location / {
            proxy_pass http://slow_backend;
            proxy_connect_timeout 2s;
            proxy_read_timeout 2s;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            
            # 缓冲太小，导致响应需要长时间占用连接
            proxy_buffering off;
            proxy_buffer_size 4k;
        }
    }
}
```

**Step 2: 触发**

```bash
# 用 slowhttptest 或自定义脚本快速发请求
# 配合低 worker_rlimit_nofile
```

---

## 8. 方法六：子请求链耗尽 FD

### 8.1 思路

Nginx 的 `rewrite` 配合 `proxy_pass` 可以制造内部 redirect 循环或超长子请求链。每个 internal redirect / subrequest 都会打开额外的 FD。如果配置不当导致 rewrite 循环，FD 会在短时间内耗尽。

### 8.2 操作步骤

**Step 1: 配置 rewrite 循环**

```nginx
server {
    listen 80;
    
    # 注意：这里故意制造 rewrite 循环
    # 请求 /a → 重写到 /b → 重写到 /a → 循环...
    location /a {
        rewrite ^ /b redirect;
    }
    location /b {
        rewrite ^ /a redirect;
    }
}
```

**Step 2: 触发**

```bash
# 只用 1 个请求就能快速触发
curl -v http://localhost:80/a

# Nginx 会快速生成大量子请求，消耗 FD
```

**Step 3: 更隐蔽的写法 — 内部子请求泄漏**

```nginx
server {
    listen 80;
    
    location /internal-leak {
        # 每层都 include 同样的 subrequest
        rewrite ^ /internal-leak break;
        # 或者配置 subrequest loop
        proxy_pass http://127.0.0.1:80/self;
    }
}
```

> ⚠️ **危险**：Rewrite 循环会导致 Nginx worker 陷入 CPU 100%，可能需要 `kill -9` 才能恢复。

---

## 9. 各方法对比与选择建议

| 方法 | 触发可靠性 | 操作难度 | 可逆性 | 风险等级 |
|-----|-----------|---------|--------|---------|
| 方法一：低 FD + 高并发压测 | ⭐⭐⭐⭐⭐ | ⭐ | ✅ 好 | 低 |
| 方法二：慢客户端占位 | ⭐⭐⭐ | ⭐⭐ | ✅ 好 | 低 |
| 方法三：文件泄漏 | ⭐⭐⭐ | ⭐⭐ | ✅ 好 | 低 |
| 方法四：ulimit 降级 | ⭐⭐⭐⭐⭐ | ⭐ | ✅ 最好 | 低 |
| 方法五：上游 FD 泄漏 | ⭐⭐ | ⭐⭐⭐ | ✅ 中 | 中 |
| 方法六：rewrite 循环 | ⭐⭐⭐⭐ | ⭐⭐⭐ | ❌ 难 | 高 |

### 推荐测试顺序

```
1. 方法四（ulimit 降级 + wrk）   ← 最简单，5 分钟内可复现
   ↓
2. 方法一（低 worker_rlimit_nofile + 高并发）  ← 最接近生产场景
   ↓
3. 方法二（慢客户端）             ← 理解连接占用问题
   ↓
4. 方法三（文件泄漏）            ← 理解 FD 和缓存的关系
   ↓
5. 方法五/六                    ← 高级场景，按需探索
```

### 生产模拟 Checklist

```bash
# 1. 检查当前 Nginx FD 使用情况
for pid in $(pgrep -f "nginx: worker"); do
    echo "Worker $pid: $(ls /proc/$pid/fd 2>/dev/null | wc -l) FDs"
done

# 2. 确认限制值
grep worker_rlimit_nofile /etc/nginx/nginx.conf
cat /proc/sys/fs/file-max
ulimit -n

# 3. 设置复现环境
ulimit -n 128

# 4. 压测
wrk -t4 -c150 -d30s http://127.0.0.1:80/

# 5. 验证报错
tail -20 /var/log/nginx/error.log
dmesg | tail -5
```

---

## 10. 配置参考：让 Nginx 恢复正常

### 10.1 紧急修复

```nginx
# 立即在 /etc/nginx/nginx.conf 的全局块加入/修改
worker_rlimit_nofile 65535;

events {
    worker_connections 16384;
}
```

然后 `nginx -t && systemctl reload nginx`

### 10.2 系统级永久设置

```bash
# /etc/security/limits.conf
nginx soft nofile 65535
nginx hard nofile 65535

# /etc/sysctl.conf
fs.file-max = 1000000
fs.nr_open = 1048576

# 应用
sudo sysctl -p
```

### 10.3 验证修复

```bash
# 重载后验证 FD 限制已提升
for pid in $(pgrep -f "nginx: worker"); do
    echo "Worker $pid: $(cat /proc/$pid/limits | grep 'Max open files')"
done

# 再跑一次压测，应该不再出现 Too many open files
wrk -t4 -c200 -d30s http://127.0.0.1:80/
```

---

## 参考文档

- `nginx-master-worker.md` — Nginx Master-Worker 架构深度分析（本文档的原理基础）
- [Nginx 文档：worker_rlimit_nofile](http://nginx.org/en/docs/ngx_core.html#worker_rlimit_nofile)
- [Nginx 文档：worker_connections](http://nginx.org/en/docs/events.html#worker_connections)
- [Linux 内核：file-nr / file-max 解释](https://www.kernel.org/doc/Documentation/sysctl/fs.txt)