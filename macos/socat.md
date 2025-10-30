非常好的问题。你在 macOS 上运行的这条命令：

```
socat TCP4-LISTEN:6443,bind=192.168.31.168,reuseaddr,fork TCP4:127.0.0.1:6443
```

它的作用是**将本机 192.168.31.168:6443 端口的请求转发到 127.0.0.1:6443**。

你希望它能在后台常驻运行，并且如果进程异常退出，能够自动重启。

下面我给你几种稳定的方式（从简单到推荐生产级的）👇

---

## **✅ 方案 1：使用** 

## **nohup + while true**

## **（最简单）**

  

这种方式最直观、无依赖、适合快速测试。
socat.sh

```bash
#!/bin/bash

LOG_FILE=/tmp/socat.log
echo "Starting socat monitor..." >> "$LOG_FILE"

while true; do
  echo "Launching socat..." >> "$LOG_FILE"
  socat TCP4-LISTEN:6443,bind=192.168.31.168,reuseaddr,fork TCP4:127.0.0.1:6443 >> "$LOG_FILE" 2>&1
  echo "$(date) - socat crashed, restarting..." >> "$LOG_FILE"
  sleep 2
done
```

保存为nohup /Users/lex/socat.sh &，然后执行：

```

👉 这样即使 socat 退出，也会自动重启。日志会保存在 /tmp/socat.log。

不过缺点是：

- 不能随系统自动启动；
    
- 没有监控机制。
    

---

## **✅ 方案 2：使用** 

## **launchd**

## **（macOS 官方推荐方式）**

  

macOS 没有 systemd，用 launchd 是最佳实践。

  

创建配置文件：

```
sudo vim /Library/LaunchDaemons/com.local.socat.plist
```

内容如下：

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.socat</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/socat</string>
        <string>TCP4-LISTEN:6443,bind=192.168.31.168,reuseaddr,fork</string>
        <string>TCP4:127.0.0.1:6443</string>
    </array>

    <!-- 自动重启 -->
    <key>KeepAlive</key>
    <true/>

    <!-- 开机自动运行 -->
    <key>RunAtLoad</key>
    <true/>

    <!-- 标准输出和错误日志 -->
    <key>StandardOutPath</key>
    <string>/var/log/socat.out.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/socat.err.log</string>
</dict>
</plist>
```

然后加载配置：

```
sudo launchctl load /Library/LaunchDaemons/com.local.socat.plist
sudo launchctl start com.local.socat
```

验证状态：

```
sudo launchctl list | grep com.local.socat
```

这样：

- 系统开机自动启动；
    
- 如果进程崩溃会被自动重启；
    
- 有标准日志文件可查；
    
- 无需人工干预。
    

---

## **✅ 方案 3：使用** 

## **supervisord**

## **（适合开发环境）**

  

如果你经常管理多个后台进程，可以使用 supervisor：

  

安装：

```
brew install supervisor
```

配置（例如 /usr/local/etc/supervisord.d/socat.ini）：

```
[program:socat]
command=/usr/local/bin/socat TCP4-LISTEN:6443,bind=192.168.31.168,reuseaddr,fork TCP4:127.0.0.1:6443
autostart=true
autorestart=true
stderr_logfile=/usr/local/var/log/socat.err.log
stdout_logfile=/usr/local/var/log/socat.out.log
```

启动：

```
supervisord -c /usr/local/etc/supervisord.conf
supervisorctl start socat
```

---

## **🧩 小结**

|**方案**|**适用场景**|**是否自动重启**|**是否随系统启动**|**推荐程度**|
|---|---|---|---|---|
|nohup + while true|快速临时运行|✅|❌|⭐|
|launchd|macOS 原生持久服务|✅|✅|⭐⭐⭐⭐⭐|
|supervisord|多进程管理或开发环境|✅|✅|⭐⭐⭐⭐|

---

## **✅ 推荐**

  

在 macOS 环境下，**使用 launchd 是最优解**，稳定、无外部依赖、自动重启、系统集成度高。

---

是否希望我帮你直接生成一个完整的 com.local.socat.plist 文件（含路径检测和日志目录自动创建）？可以直接放进 /Library/LaunchDaemons/ 使用。