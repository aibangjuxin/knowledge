# 高频轮转策略 - 平稳的磁盘空间管理

## 核心思路

通过增加轮转频率，减少单次轮转的文件大小，让磁盘使用更平稳，避免突发的大文件压缩导致的磁盘压力。

## 方案对比

| 方案 | 频率 | rotate | 优点 | 缺点 |
|------|------|--------|------|------|
| 原方案 | daily | 1 | 简单 | 单次压缩文件大，磁盘压力集中 |
| 方案A | 每6小时 | 1 | 文件更小，压力分散 | 轮转次数增加4倍 |
| 方案B | 每4小时 | 1 | 压力更分散 | 轮转次数增加6倍 |
| 方案C | 每2小时 | 1 | 最平稳 | 轮转次数最多 |

## 推荐方案A: 每6小时轮转

### 配置文件
```bash
/var/log/nginx/*.log {
    # 每6小时轮转一次
    size 1K
    hourly
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
        # 确保压缩成功
        for file in /var/log/nginx/*.log.1; do
            if [ -f "$file" ] && [ ! -f "$file.gz" ]; then
                gzip "$file" 2>/dev/null || true
            fi
        done
    endscript
}
```

### 对应的 Cron 配置
```bash
# 编辑 /etc/cron.d/logrotate-nginx
# 每6小时执行一次 (00:00, 06:00, 12:00, 18:00)
0 */6 * * * root /usr/sbin/logrotate /etc/logrotate.d/nginx
```

## 方案B: 每4小时轮转 (更平稳)

### 配置文件
```bash
/var/log/nginx/*.log {
    size 1K
    hourly  
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

### 对应的 Cron 配置
```bash
# 每4小时执行一次 (00:00, 04:00, 08:00, 12:00, 16:00, 20:00)
0 */4 * * * root /usr/sbin/logrotate /etc/logrotate.d/nginx
```

## 方案C: 基于文件大小的智能轮转

### 配置文件
```bash
/var/log/nginx/*.log {
    # 当文件达到50MB时轮转
    size 50M
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

### 对应的 Cron 配置
```bash
# 每小时检查一次文件大小
0 * * * * root /usr/sbin/logrotate /etc/logrotate.d/nginx
```

## 混合方案: 时间+大小双重触发

### 最智能的配置
```bash
/var/log/nginx/*.log {
    # 每6小时或文件超过100MB时轮转
    size 100M
    hourly
    rotate 1
    compress
    notifempty
    missingok
    create 640 nginx nginx
    sharedscripts
    prerotate
        # 记录轮转时间和文件大小
        echo "$(date): 轮转 $(ls -lh /var/log/nginx/*.log)" >> /var/log/logrotate-nginx.log
    endscript
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            /bin/kill -USR1 $(cat /var/run/nginx.pid) 2>/dev/null || true
        fi
        # 记录压缩结果
        echo "$(date): 压缩完成 $(ls -lh /var/log/nginx/*.log.*.gz 2>/dev/null)" >> /var/log/logrotate-nginx.log
    endscript
}
```

### 对应的 Cron 配置
```bash
# 每6小时检查一次
0 */6 * * * root /usr/sbin/logrotate /etc/logrotate.d/nginx

# 每小时额外检查文件大小（用于大小触发）
0 * * * * root /usr/sbin/logrotate /etc/logrotate.d/nginx
```

## 实际效果对比

### 磁盘使用模式对比

#### 原方案 (每天轮转)
```
时间轴: |----24小时----|----24小时----|
文件大小: 0MB → 500MB → 0MB → 500MB
磁盘压力: 低 --------→ 高 → 低 --------→ 高
```

#### 新方案 (每6小时轮转)
```
时间轴: |-6h-|-6h-|-6h-|-6h-|-6h-|-6h-|-6h-|-6h-|
文件大小: 0→125→0→125→0→125→0→125→0→125→0→125→0→125→0→125
磁盘压力: 低→中→低→中→低→中→低→中→低→中→低→中→低→中→低→中
```

### 优势分析

1. **磁盘压力分散**: 单次压缩文件从500MB降到125MB
2. **故障恢复快**: 最多只丢失6小时日志，而不是24小时
3. **I/O更平稳**: 避免集中的大文件I/O操作
4. **监控更精细**: 可以更快发现日志异常

## 监控脚本优化

### 高频轮转监控脚本
```bash
#!/bin/bash
# nginx-frequent-rotation-monitor.sh

LOG_DIR="/var/log/nginx"
ROTATION_LOG="/var/log/logrotate-nginx.log"

# 检查轮转频率是否正常
check_rotation_frequency() {
    local last_rotation=$(tail -10 $ROTATION_LOG 2>/dev/null | grep "轮转" | tail -1 | cut -d: -f1-2)
    if [ -n "$last_rotation" ]; then
        local last_time=$(date -d "$last_rotation" +%s 2>/dev/null)
        local current_time=$(date +%s)
        local diff=$((current_time - last_time))
        
        # 如果超过7小时没有轮转，发出警告
        if [ $diff -gt 25200 ]; then
            echo "警告: 超过7小时未进行日志轮转"
            echo "上次轮转时间: $last_rotation"
        fi
    fi
}

# 检查当前日志文件大小
check_current_log_size() {
    local max_size=104857600  # 100MB in bytes
    
    for log_file in $LOG_DIR/*.log; do
        if [ -f "$log_file" ]; then
            local size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null)
            if [ $size -gt $max_size ]; then
                echo "警告: $log_file 大小超过100MB ($size bytes)"
                echo "建议立即执行轮转: logrotate -f /etc/logrotate.d/nginx"
            fi
        fi
    done
}

# 执行检查
check_rotation_frequency
check_current_log_size

# 清理过期的轮转日志记录
if [ -f "$ROTATION_LOG" ]; then
    # 只保留最近100行记录
    tail -100 "$ROTATION_LOG" > "${ROTATION_LOG}.tmp" && mv "${ROTATION_LOG}.tmp" "$ROTATION_LOG"
fi
```

## 实施建议

### 1. 渐进式迁移
```bash
# 第一周: 每12小时轮转
0 */12 * * * root /usr/sbin/logrotate /etc/logrotate.d/nginx

# 第二周: 每8小时轮转  
0 */8 * * * root /usr/sbin/logrotate /etc/logrotate.d/nginx

# 第三周: 每6小时轮转
0 */6 * * * root /usr/sbin/logrotate /etc/logrotate.d/nginx
```

### 2. 测试验证
```bash
# 手动测试6小时轮转
logrotate -d /etc/logrotate.d/nginx  # 调试模式
logrotate -f /etc/logrotate.d/nginx  # 强制执行

# 观察效果
watch -n 60 'ls -lh /var/log/nginx/ && df -h /var/log'
```

### 3. 回滚方案
```bash
# 如果高频轮转有问题，快速回滚到每日轮转
# 修改配置文件，改回 daily
# 修改 cron，改回每日执行
```

## 最终推荐

基于你的磁盘限制，我推荐**方案A (每6小时轮转)**：

1. **平衡性好**: 既分散了磁盘压力，又不会过于频繁
2. **易于管理**: 一天4次，便于监控和故障排查
3. **资源友好**: 单次压缩文件小，对系统影响小
4. **故障恢复**: 最多丢失6小时日志，可接受

你觉得这个方案怎么样？需要我帮你准备具体的实施步骤吗？