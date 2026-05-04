# Mac mini 电源管理方案

## 状态：已生效

| 设置         | 当前值          | 说明                       |
| ------------ | --------------- | -------------------------- |
| 系统睡眠     | `1`（启用）     | idle 1 分钟后允许进入睡眠  |
| 磁盘休眠     | `10`（分钟）    | 无操作 10 分钟后磁盘停转   |
| 显示器休眠   | `10`（分钟）    | 无操作 10 分钟后显示器关闭 |
| 网络唤醒     | `womp=1`        | 允许网络唤醒               |
| 断电自启     | `autorestart=1` | 断电恢复后自动开机         |
| 计划睡眠     | `23:30` 每天    | 自动进入系统睡眠           |
| 计划唤醒     | `06:00` 每天    | 自动从睡眠中唤醒           |
| LaunchDaemon | 已部署          | 开机自动应用电源计划       |

---

## 1. 需求

| #   | 需求           | 说明                                    |
| --- | -------------- | --------------------------------------- |
| R1  | 夜间休眠       | 每天 23:30 自动进入系统睡眠             |
| R2  | 早晨唤醒       | 每天 06:00 自动从睡眠中唤醒             |
| R3  | 白天服务器模式 | 唤醒后系统保持运行，显示器可休眠        |
| R4  | 开机自动注册   | 每次启动自动将电源计划写入系统          |
| R5  | 显示器休眠     | 10 分钟无操作后显示器休眠，节省屏幕耗电 |

---

## 2. 冲突说明

### server_mode enable vs schedule repeat — 冲突

`macos_power_server_mode.sh enable` 执行 `pmset -a sleep 0`（永久禁用系统睡眠），与 `pmset repeat sleep 23:30` 冲突 —— 后者设置的睡眠时间永远不会执行。

解决方案：不使用 `server_mode`，仅用 `pmset repeat` 控制睡眠/唤醒时间，天然满足所有需求。

### 日志文件权限问题

LaunchDaemon 执行报错 `badly formatted repeating power event`，原因是 plist 中 `pmset repeat` 命令格式不正确，已修正。

---

## 3. 生效配置

### 3.1 电源计划（立即生效）

```bash
sudo pmset repeat wakeorpoweron MTWRFSU 06:00:00 sleep MTWRFSU 23:30:00
sudo pmset -a disksleep 10 displaysleep 10 sleep 1
```

**格式要点（重要）：**
- `wakeorpoweron` 和 `sleep` 必须写在同一行
- 必须指定星期：`MTWRFSU` = 每天
- 时间格式必须是 `HH:MM:SS`（带秒）
- `pmset repeat` 只支持一组重复计划（wake + sleep 各一个）

**验证：**
```bash
pmset -g sched
pmset -g custom | grep -E "sleep|displaysleep|disksleep|womp"
```

当前输出：
```
Repeating power events:
  wakepoweron at 6:00AM every day
  sleep at 11:30PM every day

 displaysleep         10
 sleep                1
 disksleep            10
 womp                 1
 autorestart          1
```

### 3.2 开机自动应用（LaunchDaemon）

plist 文件路径：`/Library/LaunchDaemons/com.lex.macos-power-schedule.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lex.macos-power-schedule</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>pmset repeat wakeorpoweron MTWRFSU 06:00:00 sleep MTWRFSU 23:30:00 && pmset -a disksleep 10 displaysleep 10 sleep 1</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LaunchOnlyOnce</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/com.lex.macos-power-schedule.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/com.lex.macos-power-schedule.err</string>
</dict>
</plist>
```

**部署命令：**

```bash
# 1. 复制 plist
sudo cp /path/to/com.lex.macos-power-schedule.plist /Library/LaunchDaemons/

# 2. 设置权限
sudo chown root:wheel /Library/LaunchDaemons/com.lex.macos-power-schedule.plist
sudo chmod 644 /Library/LaunchDaemons/com.lex.macos-power-schedule.plist

# 3. 注册到 launchd（Mac mini 用 bootstrap，MacBook 用 load）
sudo launchctl bootstrap system /Library/LaunchDaemons/com.lex.macos-power-schedule.plist

# 4. 验证日志（正常情况下只有 disk sleep 的 warning，无 error）
cat /var/log/com.lex.macos-power-schedule.err
```

**关于 LaunchOnlyOnce：**
由于 `LaunchOnlyOnce: true`，Daemon 启动执行完命令后立即退出，不会持续运行。这是预期行为。下次开机时 launchd 会重新读取 plist 并执行命令。

**日志路径：**
- 正常日志：`/var/log/com.lex.macos-power-schedule.log`
- 错误日志：`/var/log/com.lex.macos-power-schedule.err`

---

## 4. 白天临时阻止睡眠

如果白天需要系统持续运行（例如跑长时间任务），临时阻止睡眠：

```bash
macos/scripts/macos_power_keepawake.sh --hours 8 --background
```

`caffeinate` assertion 生效期间，系统不会进入 idle sleep，但 23:30 的定时睡眠计划仍会执行（定时睡眠优先级高于 caffeinate）。

---

## 5. 验证清单

- [ ] `pmset -g sched` 显示 `wakepoweron at 6:00AM` 和 `sleep at 11:30PM`
- [ ] `pmset -g custom` 显示 `sleep 1 / displaysleep 10 / disksleep 10`
- [ ] `/Library/LaunchDaemons/com.lex.macos-power-schedule.plist` 存在且命令格式正确
- [ ] `launchctl bootstrap system ...` 成功执行
- [ ] 重启后 `pmset -g sched` 仍显示计划

```bash
➜  ~ pmset -g sched
Repeating power events:
  wakepoweron at 6:00AM every day
  sleep at 11:30PM every day
Scheduled power events:
 [0]  wake at 05/04/2026 07:52:28 by 'com.apple.alarm.user-invisible-com.apple.osanalytics.hardhighengagementtimer'
➜  ~ cat /Library/LaunchDaemons/com.lex.macos-power-schedule.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lex.macos-power-schedule</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>pmset repeat wakeorpoweron MTWRFSU 06:00:00 sleep MTWRFSU 23:30:00 && pmset -a disksleep 10 displaysleep 10 sleep 1</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LaunchOnlyOnce</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/com.lex.macos-power-schedule.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/com.lex.macos-power-schedule.err</string>
</dict>
</plist>
```

---

## 6. 回滚

```bash
# 取消电源重复计划
sudo pmset repeat cancel

# 恢复 macOS 默认电源设置
sudo pmset restoredefaults

# 卸载 LaunchDaemon
sudo launchctl bootout system/com.lex.macos-power-schedule
sudo rm /Library/LaunchDaemons/com.lex.macos-power-schedule.plist




```
