# 磁盘空间受限环境下的 Nginx Logrotate 最佳实践

## 针对磁盘限制的优化配置

### 推荐配置 (立即压缩版本)

```bash
/var/log/nginx/*.log {
    daily
    rotate 1
    compress
    notifempty
    missingok
    create 640 nginx nginx
    sharedscripts
    prerotate
        # 确保有足够空间进行压缩
        AVAILABLE=$(df /var/log | tail -1 | awk '{print $4}')
        LOG_SIZE=$(du -sk /var/log/nginx/*.log 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
        if [ $AVAILABLE -lt $((LOG_SIZE * 2)) ]; then
            echo "磁盘空间不足，跳过轮转" >&2
            exit 1
        fi
    endscript
    postrotate
        # 使用更可靠的信号发送方式
        if [ -f /var/run/nginx.pid ]; then
            /bin/kill -USR1 $(cat /var/run/nginx.pid) 2>/dev/null || true
        fi
        # 立即验证压缩是否成功
        for file in /var/log/nginx/*.log.1; do
            if [ -f "$file" ] && [ ! -f "$file.gz" ]; then
                gzip "$file" 2>/dev/null || true
            fi
        done
    endscript
}
```

## 关键优化点解析

### 1. 磁盘空间预检查 (prerotate)
```bash
AVAILABLE=$(df /var/log | tail -1 | awk '{print $4}')
LOG_SIZE=$(du -sk /var/log/nginx/*.log 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
if [ $AVAILABLE -lt $((LOG_SIZE * 2)) ]; then
    echo "磁盘空间不足，跳过轮转" >&2
    exit 1
fi
```
- **作用**: 轮转前检查磁盘空间
- **逻辑**: 确保可用空间至少是日志文件大小的2倍
- **好处**: 避免轮转过程中磁盘满导致的问题

### 2. 改进的信号处理
```bash
/bin/kill -USR1 $(cat /var/run/nginx.pid) 2>/dev/null || true
```
- **USR1 vs HUP**: USR1 专门用于重新打开日志文件，不会重载配置
- **$(...)**: 比反引号更现代和可靠的命令替换
- **错误处理**: 确保即使信号发送失败也不会中断 logrotate

### 3. 压缩验证和补救
```bash
for file in /var/log/nginx/*.log.1; do
    if [ -f "$file" ] && [ ! -f "$file.gz" ]; then
        gzip "$file" 2>/dev/null || true
    fi
done
```
- **作用**: 确保所有轮转文件都被压缩
- **场景**: 处理压缩失败的情况

## 更激进的磁盘节省方案

### 方案A: 小时级轮转 + 立即压缩
```bash
/var/log/nginx/*.log {
    hourly
    rotate 24
    compress
    notifempty
    missingok
    create 640 nginx nginx
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            /bin/kill -USR1 $(cat /var/run/nginx.pid) 2>/dev/null || true
        fi
    endscript
}
```
- **优点**: 更频繁的压缩，减少未压缩文件的存在时间
- **缺点**: 更频繁的 I/O 操作

### 方案B: 基于大小的轮转
```bash
/var/log/nginx/*.log {
    size 100M
    rotate 1
    compress
    notifempty
    missingok
    create 640 nginx nginx
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            /bin/kill -USR1 $(cat /var/run/nginx.pid) 2>/dev/null || true
        fi
    endscript
}
```
- **优点**: 基于实际文件大小，更精确控制磁盘使用
- **缺点**: 可能导致不规律的轮转时间

## 实时监控脚本

### 磁盘空间监控
```bash
#!/bin/bash
# nginx-disk-monitor.sh

LOG_DIR="/var/log/nginx"
THRESHOLD=85  # 磁盘使用率阈值

# 检查磁盘使用率
USAGE=$(df /var/log | tail -1 | awk '{print $5}' | sed 's/%//')

if [ $USAGE -gt $THRESHOLD ]; then
    echo "警告: /var/log 磁盘使用率 ${USAGE}%"
    
    # 紧急清理：删除超过1天的压缩日志
    find $LOG_DIR -name "*.log.*.gz" -mtime +1 -delete
    
    # 强制压缩未压缩的轮转文件
    find $LOG_DIR -name "*.log.[0-9]*" ! -name "*.gz" -exec gzip {} \;
    
    echo "执行紧急清理后的使用率: $(df /var/log | tail -1 | awk '{print $5}')"
fi
```

### 压缩状态检查
```bash
#!/bin/bash
# check-compression.sh

LOG_DIR="/var/log/nginx"

# 检查未压缩的轮转文件
UNCOMPRESSED=$(find $LOG_DIR -name "*.log.[0-9]*" ! -name "*.gz" -mtime +0.1)

if [ -n "$UNCOMPRESSED" ]; then
    echo "发现未压缩的轮转文件:"
    echo "$UNCOMPRESSED"
    
    # 尝试手动压缩
    echo "$UNCOMPRESSED" | while read file; do
        if [ -f "$file" ]; then
            echo "压缩 $file"
            gzip "$file" 2>/dev/null || echo "压缩失败: $file"
        fi
    done
fi
```

## Cron 任务配置

### 添加监控任务
```bash
# 编辑 crontab
crontab -e

# 添加以下行
# 每10分钟检查磁盘使用率
*/10 * * * * /path/to/nginx-disk-monitor.sh

# 每小时检查压缩状态
0 * * * * /path/to/check-compression.sh

# 每天凌晨强制清理（备用）
0 2 * * * find /var/log/nginx -name "*.log.*.gz" -mtime +1 -delete
```

## 故障处理预案

### 磁盘满的紧急处理
```bash
#!/bin/bash
# emergency-cleanup.sh

echo "执行紧急磁盘清理..."

# 1. 立即压缩所有未压缩的日志
find /var/log/nginx -name "*.log.[0-9]*" ! -name "*.gz" -exec gzip {} \;

# 2. 删除超过6小时的压缩日志
find /var/log/nginx -name "*.log.*.gz" -mmin +360 -delete

# 3. 如果仍然空间不足，截断当前日志文件
USAGE=$(df /var/log | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $USAGE -gt 95 ]; then
    echo "磁盘使用率仍然过高，截断当前日志文件"
    > /var/log/nginx/access.log
    > /var/log/nginx/error.log
    
    # 重新打开日志文件
    if [ -f /var/run/nginx.pid ]; then
        kill -USR1 $(cat /var/run/nginx.pid)
    fi
fi

echo "清理完成，当前磁盘使用率: $(df /var/log | tail -1 | awk '{print $5}')"
```

## 最终推荐配置

基于你的磁盘限制，我推荐使用这个配置：

```bash
/var/log/nginx/*.log {
    daily
    rotate 1
    compress
    notifempty
    missingok
    create 640 nginx nginx
    sharedscripts
    prerotate
        # 磁盘空间检查
        AVAILABLE=$(df /var/log | tail -1 | awk '{print $4}')
        LOG_SIZE=$(du -sk /var/log/nginx/*.log 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
        if [ $AVAILABLE -lt $((LOG_SIZE * 2)) ]; then
            # 紧急清理
            find /var/log/nginx -name "*.log.*.gz" -mtime +0.5 -delete 2>/dev/null || true
        fi
    endscript
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            /bin/kill -USR1 $(cat /var/run/nginx.pid) 2>/dev/null || true
        fi
        # 确保压缩成功
        sleep 1
        for file in /var/log/nginx/*.log.1; do
            if [ -f "$file" ] && [ ! -f "$file.gz" ]; then
                gzip "$file" 2>/dev/null || true
            fi
        done
    endscript
}
```

## 关键特性

1. **立即压缩**: 不使用 delaycompress
2. **磁盘预检**: 轮转前检查空间
3. **紧急清理**: 空间不足时自动清理
4. **压缩验证**: 确保压缩成功
5. **错误容忍**: 所有操作都有错误处理

这个配置在保证磁盘空间的同时，最大化了日志轮转的可靠性。