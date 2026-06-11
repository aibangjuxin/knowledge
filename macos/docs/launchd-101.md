# macOS launchd 入门

> 把后台进程交给 macOS 自己管 — plist 在哪、怎么看、怎么改。
> 本文档基于 macmini 上**真实存在的 plist** 写就，所有命令可以直接复制粘贴验证。

---

## 1. 一句话定位

`launchd` 是 macOS 的 init 系统（PID 1）。它开机时第一个跑，**接管所有后台进程** — 替代了传统的 `cron` / `systemd` / `rc.d`。你在 mac 上看到的所有"自启服务"（微信代理、Docker daemon、Hermes gateway、RAG server）全是它管的。

学习它 = 学会两件事：**plist 在哪里 / 怎么写**，**launchctl 怎么查 / 怎么改**。

---

## 2. 三个 plist 目录 — 决定服务的"权限级别"

```
~/Library/LaunchAgents/        ← 你（用户）的服务，最常用
/Library/LaunchAgents/         ← 系统给所有用户装的 agent（要 sudo）
/Library/LaunchDaemons/        ← 开机就跑，不依赖任何登录用户（要 sudo）
```

| 目录 | 谁拥有 | 何时启动 | 是否需要 GUI 登录 | 典型用途 |
|---|---|---|---|---|
| `~/Library/LaunchAgents/` | 当前用户 ($UID) | 登录后 | **是** — 没登录就不跑 | 你的 dev 工具、gateway、本地 server |
| `/Library/LaunchAgents/` | root | 任意用户登录后 | 是 | 多用户共享的 GUI 工具 |
| `/Library/LaunchDaemons/` | root | **开机即跑**，不依赖登录 | **否** — 即使没登录也跑 | 必须在登录前就起来的 daemon |

**陷阱（macmini 真踩过）**：`~/Library/LaunchAgents/` 下的服务依赖 GUI session。凌晨机器 DarkWake（不开屏）时 launchd **不会 spawn** 它。要么改用 `/Library/LaunchDaemons/`，要么让机器一直登录。见第 9 节。

---

## 3. macmini 上现在跑了什么 — 真实清单

```bash
# 列出所有加载的 job（不管 user 还是 system）
launchctl list

# 只看我自己的
launchctl list | awk 'NR==1 || $3 ~ /^(com\.lex|ai\.hermes|com\.parantoux)/'
```

刚才跑出来的结果（节选）：

```
PID     Status  Label
30004   0       com.parantoux.hermes-webui        ← Hermes WebUI
-       0       com.lex.rag-ingest                ← RAG 夜间 ingest（凌晨 2 点）
99367   1       ai.hermes.gateway-architecture    ← 当前正在跑的架构 gateway
1567    0       ai.hermes.gateway-blackswallow
-       0       ai.hermes.gateway
1543    0       com.lex.rag-server                ← RAG HTTP server (127.0.0.1:8080)
-       0       com.lex.rag-autoresearch          ← 周一周三周五周日 3 点跑
```

**列含义**：
- **PID** 列：`30004` = 真有进程在跑；`-` = 已注册但当前没跑（周期任务等待中 / 或上次挂了）
- **Status** 列：最近一次退出的 exit code。`0` = 干净退出 / 还在跑；`1` = 异常退出

---

## 4. plist 文件长什么样 — 用真文件举例

打开 `~/Library/LaunchAgents/com.lex.rag-server.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>Label</key>                              <!-- 唯一 ID，全机不重复 -->
    <string>com.lex.rag-server</string>

    <key>ProgramArguments</key>                   <!-- 要执行的命令（数组形式） -->
    <array>
        <string>/Users/lex/.local/bin/uv</string> <!-- 必须是绝对路径 -->
        <string>run</string>
        <string>--project</string>
        <string>/Users/lex/git/rag</string>
        <string>rag</string>
        <string>serve</string>
        <string>--host</string>
        <string>127.0.0.1</string>
        <string>--port</string>
        <string>8080</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/lex/git/rag</string>            <!-- 进程 cwd -->

    <key>RunAtLoad</key>                          <!-- launchctl load 时立即启动 -->
    <true/>

    <key>KeepAlive</key>                          <!-- 挂了自动拉起 -->
    <dict>
        <key>SuccessfulExit</key>                 <!-- 只在异常退出时拉起 -->
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>

    <key>ThrottleInterval</key>                   <!-- 重启间隔最少 10 秒（防爆） -->
    <integer>10</integer>

    <key>StandardOutPath</key>                    <!-- stdout 落到文件 -->
    <string>/Users/lex/git/rag/data/logs/rag-server.log</string>

    <key>StandardErrorPath</key>                  <!-- stderr 落到文件 -->
    <string>/Users/lex/git/rag/data/logs/rag-server.err.log</string>

    <key>EnvironmentVariables</key>               <!-- 注入环境变量 -->
    <dict>
        <key>PATH</key>
        <string>/Users/lex/.local/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/lex</string>
    </dict>
</dict>
</plist>
```

### 关键字段速查

| 字段 | 必填？ | 作用 |
|---|---|---|
| `Label` | ✅ | 唯一 ID。改了就等于新建服务。`com.<反域>.<名>` 是惯例 |
| `ProgramArguments` | ✅ | 数组形式，**全部用绝对路径**（launchd 不读 `~/.zshrc`，找不到 `python` / `uv`） |
| `WorkingDirectory` | ❌ 但强烈推荐 | 进程 cwd。很多脚本 `cd` 假设 |
| `EnvironmentVariables.PATH` | ❌ 但必设 | launchd 默认 PATH 只有 `/usr/bin:/bin:/usr/sbin:/sbin`，**没有 Homebrew，没有 `~/.local/bin`**。不设就找不到 `python3` / `uv` / `brew` |
| `RunAtLoad` | ❌ | `true` = `launchctl load` 那一刻立即启动 |
| `KeepAlive` | ❌ | 进程死后是否自动拉起。`true` = 任何死法都拉；`{SuccessfulExit: false}` = 只在异常退出时拉（推荐） |
| `ThrottleInterval` | ❌ 但必设 | 最小重启间隔（秒）。**不设的话 crash loop 几毫秒一次，秒爆日志** |
| `StandardOutPath` / `StandardErrorPath` | ❌ | 不设的话丢到 `/dev/null`，出问题没法 debug |
| `StartCalendarInterval` | ❌ | 周期任务（替代 cron）。见第 6 节 |

---

## 5. 查看服务 — 4 个核心命令

### 5.1 列清单

```bash
launchctl list                                          # 全部
launchctl list | grep com.lex                           # 按 label 过滤
launchctl list | awk '$3 ~ /^com\.lex/'                 # 按正则
```

### 5.2 看一个服务的全部细节（最有用的一个）

```bash
launchctl print gui/501/com.lex.rag-server
```

输出（节选）：

```
gui/501/com.lex.rag-server = {
    active count = 1                            ← 1 = 正在跑
    path = /Users/lex/Library/LaunchAgents/com.lex.rag-server.plist
    type = LaunchAgent
    state = running                             ← 状态

    program = /Users/lex/.local/bin/uv
    arguments = { /Users/lex/.local/bin/uv, run, --project, ... }

    working directory = /Users/lex/git/rag

    stdout path = /Users/lex/git/rag/data/logs/rag-server.log
    stderr path = /Users/lex/git/rag/data/logs/rag-server.err.log
    ...
}
```

**重点看 4 行**：
- `state` = `running` / `not running` / `waiting` — 服务的当前状态
- `active count` = `1` 表示有进程在跑，`0` 没跑
- `last exit code` — 上次退出的 code（异常时排查必看）
- `stdout/stderr path` — 日志位置

### 5.3 看服务的最近日志

```bash
# 先拿到 log 路径
launchctl print gui/501/com.lex.rag-server | grep -E "stdout|stderr"
# 然后
tail -f /Users/lex/git/rag/data/logs/rag-server.log
```

### 5.4 查进程实际是不是 launchd 在管的

```bash
ps -o pid,ppid,command -p $(launchctl list | awk '/com.lex.rag-server/ && $1 != "-" {print $1}')
# 跑出：
#   PID  PPID  COMMAND
#  1543     1  ...   ← PPID=1 就是 launchd 在管它
```

`PPID = 1` = 它是 launchd 直接 spawn 的。如果 PPID 是别的（比如 bash terminal），说明是手动启的，**launchd 不知道它的存在**。

---

## 6. 改一个服务 — 完整工作流

以"改 `com.lex.rag-server` 的端口从 8080 到 9090"为例。

### Step 1：先看现在跑没跑

```bash
launchctl list | grep com.lex.rag-server
# → 1543   0   com.lex.rag-server
```

### Step 2：改 plist

用编辑器打开 `~/Library/LaunchAgents/com.lex.rag-server.plist`，把 `--port 8080` 改成 `--port 9090`。

### Step 3：lint

```bash
plutil -lint ~/Library/LaunchAgents/com.lex.rag-server.plist
# → OK
```

**必跑**。launchd 拒绝加载格式错的 plist，错误信息有时很迷惑。

### Step 4：unload → 再 load（让 launchd 重读 plist）

```bash
launchctl bootout gui/501/com.lex.rag-server
launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.lex.rag-server.plist
```

或者一行（先 SIGTERM，再 spawn 新进程）：

```bash
launchctl kickstart -k gui/501/com.lex.rag-server
```

> **注意**：光改文件**没用**。launchd 在内存里有 plist 的快照，**改完文件后必须重读**。区别：
> - `kickstart -k` — 只 SIGTERM 当前进程并重新 spawn，**不重读磁盘 plist**。适合：只想清进程、让 KeepAlive 拉起新版本
> - `bootout` + `bootstrap` — 卸载整个 job 再重新加载，**会重读磁盘 plist**。适合：plist 内容改了（端口、参数、环境变量）
>
> 如果你改了 plist 内容但只跑 `kickstart -k`，新进程会用**旧 plist 的配置**起 — 这是最常见的"我改了配置没生效"陷阱。

### Step 5：验证

```bash
launchctl print gui/501/com.lex.rag-server | head -20
lsof -nP -iTCP:9090 -sTCP:LISTEN
tail -5 /Users/lex/git/rag/data/logs/rag-server.log
```

---

## 7. 周期任务（替代 cron）

macOS 自带的 `cron` 还在，但 launchd 提供了更精细的控制。**这个 macmini 上 `com.lex.rag-ingest` 就是周期任务**。

### 7.1 每天 2 点跑一次

plist 关键字段：

```xml
<key>StartCalendarInterval</key>
<dict>
    <key>Hour</key>
    <integer>2</integer>
    <key>Minute</key>
    <integer>0</integer>
</dict>
```

### 7.2 多时间点（macmini 上 `com.lex.rag-autoresearch` 的真实例子）

周日、周一、周三、周五 03:00：

```xml
<key>StartCalendarInterval</key>
<array>
    <dict>
        <key>Weekday</key><integer>0</integer>   <!-- 0 或 7 = 周日 -->
        <key>Hour</key><integer>3</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <dict>
        <key>Weekday</key><integer>1</integer>   <!-- 1 = 周一 -->
        <key>Hour</key><integer>3</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <!-- ... 周三、周五同理 -->
</array>
```

**Weekday 编码**：`0` 和 `7` 都表示周日。

### 7.3 看周期任务的"下次运行时间"

```bash
launchctl print gui/501/com.lex.rag-ingest | grep -i "next run\|last run"
```

### 7.4 手动触发一次（不等周期）

```bash
launchctl kickstart gui/501/com.lex.rag-ingest
```

---

## 8. 启停 / 删除 — 4 个核心命令

```bash
# 启动（如果 RunAtLoad=true，load 时就启了；否则需要 kickstart）
launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.example.foo.plist
launchctl kickstart gui/501/com.example.foo

# 干净重启（SIGTERM → 等死 → 再 spawn）
launchctl kickstart -k gui/501/com.example.foo

# 停止（仅本 session，plist 还在）
launchctl bootout gui/501/com.example.foo

# 完全删除（plist 也删）
launchctl bootout gui/501/com.example.foo
rm ~/Library/LaunchAgents/com.example.foo.plist
```

**Bootout vs unload 的区别**（macOS 11+）：
- `launchctl unload` 旧命令，仍然能用
- `launchctl bootout` 新命令，**干净** — 等当前进程退出、清理 IPC、移除注册
- 永远推荐用 `bootout` 而不是 `unload`

**Domain 前缀**：
- `gui/$UID/` = 用户 agent（你日常用的就是这个，UID 通常 501）
- `system/` = 系统 daemon（要 sudo）

---

## 9. macmini 上踩过的坑 — 实战经验

### 9.1 DarkWake 时 LaunchAgent 不跑 ⚠️

**症状**：`com.lex.rag-ingest` plist 写着 02:00 跑，但机器凌晨 DarkWake（不亮屏）后日志没更新。

**原因**：`~/Library/LaunchAgents/` 依赖 GUI session — 没登录 = launchd 不调度它。DarkWake 状态机器没有 active user session。

**解决**：迁移到 `/Library/LaunchDaemons/`（system domain，不依赖登录）。

迁移脚本在 `/Users/lex/git/knowledge/bin/fix-rag-ingest-launchd.sh`，关键 diff：

```bash
# 源
SRC=~/Library/LaunchAgents/com.lex.rag-ingest.plist
# 目标
DST=/Library/LaunchDaemons/com.lex.rag-ingest.plist

# 必须 root 拥有、644 权限，launchd 才肯加载
sudo chown root:wheel "$DST"
sudo chmod 644 "$DST"

# 用 system 域加载
sudo launchctl bootstrap system "$DST"
```

**判别你该不该搬**：你的服务必须"机器没登录也跑"吗？（凌晨任务、远程唤醒、家庭自动化）→ 搬。不是的话（dev server、gateway）→ 别搬，LaunchAgent 就够。

### 9.2 launchd 状态判断陷阱

`launchctl print` 的 `runs = N` 是 launchd 启动后该 job 的累计重启次数（重置条件 = 机器重启 / launchd 重启）。**不是"历史累计"，也不是"今天跑了几次"**。要判断周期任务**历史上跑没跑过**，ground truth 在被调度的程序本身：
- 检查它的日志 mtime：`ls -la /tmp/rag-ingest-stdout.log`
- 检查它的产物：`ls -la /Users/lex/git/rag/data/index/*`
- 看数据库记录数

`launchctl list` 里的 PID 列如果一直是 `-`，意味着**它在 schedule 上**但**当前没在跑**（正常现象）— 不要误判为"挂了"。

### 9.3 PATH 没设导致 `python: command not found`

**症状**：launchctl load 成功，但 `launchctl print` 显示 `state = not running`，stderr log 一片 `python: command not found`。

**原因**：launchd 默认 PATH 只有 `/usr/bin:/bin:/usr/sbin:/sbin`，没有 Homebrew。

**解决**：plist 里加 `EnvironmentVariables.PATH`：

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PATH</key>
    <string>/Users/lex/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
</dict>
```

### 9.4 改 plist 后没生效

launchd 把 plist 加载到内存里。**光改文件没用**，必须：

```bash
launchctl bootout gui/501/<label>
launchctl bootstrap gui/501 ~/Library/LaunchAgents/<label>.plist
```

或者 `launchctl kickstart -k gui/501/<label>`（会先 SIGTERM 再 spawn，但**不会重读 plist**，只有 stdout/stderr 路径变了这种才需要 bootout/bootstrap）。

---

## 10. 速查卡片

```
┌─ 在哪 ────────────────────────────────────────────────┐
│ ~/Library/LaunchAgents/      我的服务（最常用）         │
│ /Library/LaunchAgents/       多用户 GUI 工具 (sudo)    │
│ /Library/LaunchDaemons/      不依赖登录 (sudo)         │
└────────────────────────────────────────────────────────┘

┌─ 查看 ────────────────────────────────────────────────┐
│ launchctl list                    所有                 │
│ launchctl print gui/501/<label>   单个详细             │
│ launchctl print gui/501/<label>|grep -E "state|active|stdout|stderr"
│ ps -o pid,ppid,command -p <pid>  确认 launchd 在管      │
└────────────────────────────────────────────────────────┘

┌─ 改 ──────────────────────────────────────────────────┐
│ 1. 编辑 ~/Library/LaunchAgents/<label>.plist            │
│ 2. plutil -lint <plist>                                │
│ 3. launchctl bootout gui/501/<label>                   │
│ 4. launchctl bootstrap gui/501 <plist>                 │
│ 5. launchctl print gui/501/<label>  验证               │
└────────────────────────────────────────────────────────┘

┌─ 启停 ────────────────────────────────────────────────┐
│ launchctl bootstrap gui/501 <plist>    加载并启动       │
│ launchctl kickstart gui/501/<label>   启动（已加载的）  │
│ launchctl kickstart -k gui/501/<label> 干净重启         │
│ launchctl bootout gui/501/<label>     停止 + 卸载       │
└────────────────────────────────────────────────────────┘
```

---

## 11. 进一步阅读

- `man launchd.plist` — 所有 plist 字段权威文档
- `man launchctl` — 所有命令权威文档
- Apple Technical Note TN2083 — Daemons and Agents（已淘汰但网上有存档）
- macmini 实战脚本：`/Users/lex/git/knowledge/bin/fix-rag-ingest-launchd.sh`
- 真实 plist 样例（直接打开看）：
  - `~/Library/LaunchAgents/com.lex.rag-server.plist` — KeepAlive + ThrottleInterval 完整范例
  - `~/Library/LaunchAgents/com.lex.rag-ingest.plist` — 周期任务范例
  - `~/Library/LaunchAgents/com.lex.rag-autoresearch.plist` — 多时间点周期任务
  - `~/Library/LaunchAgents/ai.hermes.gateway-architecture.plist` — KeepAlive=true 范例
  - `/Library/LaunchDaemons/com.lex.macos-no-sleep.plist` — system daemon 范例