# Nginx Logrotate 配置详解与调试指南

## 当前配置分析

```bash
/var/log/nginx/*.log {
    daily
    rotate 1
    compress
    notifempty
    create 640 root root
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/nginx.pid 2> /dev/null ` 2 > /dev/null  ||  true
    endscript
}
```

### 逐行详解

#### 1. `/var/log/nginx/*.log {`
- **作用**: 指定要轮转的日志文件路径模式
- **含义**: 匹配 `/var/log/nginx/` 目录下所有以 `.log` 结尾的文件
- **示例**: `access.log`, `error.log`, `custom.log` 等

#### 2. `daily`
- **作用**: 设置轮转频率
- **含义**: 每天执行一次日志轮转
- **触发时机**: 通常由 cron 在每天凌晨执行（具体时间取决于系统配置）

#### 3. `rotate 1`
- **作用**: 设置保留的轮转文件数量
- **含义**: 只保留 1 个轮转后的文件
- **文件命名**: 
  - 当前: `access.log`
  - 轮转后: `access.log.1.gz`（压缩后）
  - 下次轮转: 删除 `access.log.1.gz`，创建新的

#### 4. `compress`
- **作用**: 启用压缩功能
- **含义**: 轮转后的日志文件会被 gzip 压缩
- **效果**: `access.log.1` → `access.log.1.gz`

#### 5. `notifempty`
- **作用**: 空文件不轮转
- **含义**: 如果日志文件为空（0 字节），跳过轮转
- **好处**: 避免创建无意义的空压缩文件

#### 6. `create 640 root root`
- **作用**: 创建新日志文件的权限和所有者
- **含义**: 
  - 权限: `640` (rw-r-----)
  - 所有者: `root`
  - 所属组: `root`

#### 7. `sharedscripts`
- **作用**: 多个文件共享 postrotate 脚本
- **含义**: 即使匹配多个 `.log` 文件，`postrotate` 脚本只执行一次
- **好处**: 避免多次重载 nginx

#### 8. `postrotate` 脚本详解
```bash
/bin/kill -HUP `cat /var/run/nginx.pid 2> /dev/null ` 2 > /dev/null  ||  true
```

**命令分解**:
- `cat /var/run/nginx.pid 2> /dev/null`: 读取 nginx 主进程 PID，错误输出重定向
- `` `...` ``: 命令替换，将 PID 作为参数传递
- `/bin/kill -HUP <PID>`: 发送 SIGHUP 信号给 nginx
- `2 > /dev/null`: 将 kill 命令的错误输出重定向
- `|| true`: 如果前面命令失败，返回 true（避免 logrotate 报错）

**SIGHUP 信号的作用**:
- 重新打开日志文件
- 重新加载配置文件
- 优雅重启工作进程

## 压缩问题分析

### 可能导致未压缩的原因

#### 1. **文件正在使用中**
```bash
# 检查文件是否被进程占用
lsof /var/log/nginx/access.log.1
```

#### 2. **权限问题**
```bash
# 检查 logrotate 是否有压缩权限
ls -la /var/log/nginx/
```

#### 3. **磁盘空间不足**
```bash
# 检查磁盘空间
df -h /var/log/
```

#### 4. **gzip 命令不可用**
```bash
# 检查 gzip 是否可用
which gzip
gzip --version
```

#### 5. **logrotate 执行失败**
```bash
# 检查 logrotate 状态文件
cat /var/lib/logrotate/logrotate.status | grep nginx
```

#### 6. **配置语法错误**
```bash
# 测试配置语法
logrotate -d /etc/logrotate.d/nginx
```

## 调试方法

### 1. 手动测试轮转
```bash
# 强制执行轮转（调试模式）
logrotate -d /etc/logrotate.d/nginx

# 强制执行轮转（实际执行）
logrotate -f /etc/logrotate.d/nginx
```

### 2. 检查执行日志
```bash
# 查看系统日志
journalctl -u logrotate
grep logrotate /var/log/syslog
```

### 3. 监控文件变化
```bash
# 轮转前后对比
ls -la /var/log/nginx/ | grep -E "\.(log|gz)$"
```

### 4. 验证 nginx 信号处理
```bash
# 检查 nginx 进程
ps aux | grep nginx
cat /var/run/nginx.pid

# 手动发送 HUP 信号测试
kill -HUP $(cat /var/run/nginx.pid)
```

## 优化建议

### 1. 改进的配置
```bash
/var/log/nginx/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 nginx nginx
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
            run-parts /etc/logrotate.d/httpd-prerotate; \
        fi \
    endscript
    postrotate
        if [ -f /var/run/nginx.pid ]; then \
            kill -USR1 `cat /var/run/nginx.pid` \
        fi
    endscript
}
```

### 2. 关键改进点

#### `delaycompress`
- 延迟一个周期再压缩
- 避免 nginx 仍在写入时压缩文件

#### `rotate 7`
- 保留 7 天的日志
- 更好的故障排查能力

#### 改进的 postrotate 脚本
- 添加 PID 文件存在性检查
- 使用 USR1 信号（更标准的日志重开信号）

#### 权限调整
- 使用 `nginx nginx` 而不是 `root root`
- 更符合最小权限原则

## 故障排查清单

### 日常检查
```bash
# 1. 检查 logrotate 状态
systemctl status logrotate

# 2. 检查最近的轮转记录
cat /var/lib/logrotate/logrotate.status | grep nginx

# 3. 检查日志文件
ls -la /var/log/nginx/

# 4. 检查 cron 任务
cat /etc/cron.daily/logrotate

# 5. 测试配置
logrotate -d /etc/logrotate.d/nginx
```

### 问题诊断
```bash
# 如果发现未压缩的文件
file /var/log/nginx/access.log.1  # 检查文件类型
lsof /var/log/nginx/access.log.1  # 检查是否被占用

# 手动压缩测试
gzip -t /var/log/nginx/access.log.1.gz  # 测试已压缩文件
gzip /var/log/nginx/access.log.1        # 手动压缩测试
```

## 监控脚本

### 创建监控脚本
```bash
#!/bin/bash
# nginx-logrotate-monitor.sh

LOG_DIR="/var/log/nginx"
ALERT_FILE="/tmp/logrotate-alert"

# 检查是否有未压缩的轮转文件
uncompressed=$(find $LOG_DIR -name "*.log.[0-9]*" ! -name "*.gz" -mtime +1)

if [ -n "$uncompressed" ]; then
    echo "发现未压缩的日志文件:" > $ALERT_FILE
    echo "$uncompressed" >> $ALERT_FILE
    echo "时间: $(date)" >> $ALERT_FILE
    
    # 可以添加邮件通知或其他告警机制
    # mail -s "Nginx日志压缩异常" admin@example.com < $ALERT_FILE
fi

# 检查磁盘使用率
disk_usage=$(df /var/log | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $disk_usage -gt 80 ]; then
    echo "磁盘使用率过高: ${disk_usage}%" >> $ALERT_FILE
fi
```

## 总结

你的配置基本正确，但 `rotate 1` 可能过于激进。未压缩的主要原因可能是：

1. **时机问题**: nginx 仍在写入文件时尝试压缩
2. **权限问题**: logrotate 没有足够权限
3. **资源问题**: 磁盘空间或 CPU 资源不足
4. **进程问题**: nginx 进程异常或 PID 文件问题

建议使用改进的配置，并定期运行监控脚本来及时发现问题。