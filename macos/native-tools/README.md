# native-tools

只用 macOS 自带工具的单文件命令行工具,零第三方依赖(无 brew / jq / python)。
公司 MacBook Pro 装机受限,所有脚本只用系统原生 binary + zsh + awk。

## 脚本一览

| 脚本 | 用途 | 数据源 | 模式 |
|---|---|---|---|
| `sysinfo` | neofetch 风格系统总览 | sw_vers, system_profiler, sysctl | 单次 / `--compact` / `--json` |
| `cpuwatch` | CPU 实时 + Top 进程 | top -l 1, ps -Ao | 刷新 / `--once` |
| `memwatch` | 内存 / swap / 内存压力 | vm_stat, sysctl hw.memsize, ps | 刷新 / `--once` |
| `diskwatch` | 磁盘容量 + I/O + APFS + 快照 | df, iostat, du, tmutil, diskutil | 刷新 / `--once` |
| `netwatch` | 网络接口 + 吞吐 + 活跃连接 | ifconfig, route, scutil, netstat, lsof | 刷新 / `--once` |
| `batwatch` | 电池健康 + pmset 电源 | system_profiler SPPowerDataType, pmset | 刷新 / `--once` |
| `appmenu` | 已安装 app 清单 + 架构 | plutil, du, lipo, stat | 单次 / `--json` |
| `wifiwatch` | Wi-Fi 信号 / SSID / 信道 / 邻居 | system_profiler SPAirPortDataType, networksetup | 刷新 / `--once` |
| `portwatch` | 监听端口 + 活跃外连(安全审计) | lsof -nP | 刷新 / `--once` |
| `procwatch` | 进程树(pstree 风格)+ 资源 | ps -axo | 刷新 / `--once` |
| `tempwatch` | 芯片 / 散热压力 / 热源进程 | sysctl, system_profiler, ps -Ao | 刷新 / `--once` |
| `loginwatch` | 登录会话 / 历史 / sudo 审计 | who, last, log show, dscl | 刷新 / `--once` |
| `findbig` | 大文件 / 大目录清理助手(只读) | du, find, stat | 单次 |
| `launchwatch` | LaunchAgents / Daemons 自启动项 | plutil, launchctl list | 单次 |
| `displaywatch` | 显示器 / HiDPI 缩放 / 刷新率 / 像素带宽 | system_profiler SPDisplaysDataType, ioreg | 单次 / `--watch` |
| `devtreewatch` | USB / Thunderbolt / 蓝牙 设备树 | ioreg -r -c IOUSBHostDevice, system_profiler SP{Thunderbolt,Bluetooth}DataType | 单次 / `--watch` |
| `audiowatch` | 音频设备 / 声道 / 采样率 / 系统音量 | system_profiler SPAudioDataType, osascript | 单次 / `--watch` |

## 安装

```sh
chmod +x <脚本名>          # 仓库里已是 755
ln -s "$PWD/<脚本名>" /usr/local/bin/<脚本名>   # 可选
```

直接 `./<脚本名>` 或加进 PATH 均可,无配置依赖。

## 约定

- `zsh -n <脚本>` 做语法检查
- 刷新类脚本:`--interval N` 改刷新间隔,`--once` 单次输出(给脚本消费)
- 非 TTY(重定向/管道)时自动禁用颜色
- `Ctrl-C` 退出,`_cleanup` trap 恢复光标
- 修 bug 优先用 red/green TDD,断言用精确的 `--only=file:line` 目标

---

# macOS / zsh 踩坑记录

写这批脚本时踩到的坑,全部有真实表现,值得单独记下来。

## 1. zsh:循环体内重复 `local VAR` 会把变量值回显到 stdout

**最坑的一个。** 症状是终端里莫名多出 `color=$'\C-[[32m'`、`row=$'...'` 这类行。

```zsh
# 错:local 在 while 体内,且变量在上一轮已有值
while read -r line; do
  local color          # ← 重复声明,把上一轮的值回显
  color=$(some_cmd)
  printf '%s' "$color"
done <<< "$data"
```

**修法:** `local` 全部提到循环外,或每段用不同变量名。更好的做法是把渲染整段交给 awk,zsh 只负责取数。

受影响的脚本:`wifiwatch`、`portwatch`、`findbig`、`launchwatch` 都中过招。

## 2. zsh:`((n++))` 在 n=0 时触发 errexit

```zsh
setopt errexit
n=0
while ...; do
  ((n++))    # ← 表达式值是自增前的 0,errexit 直接退出
done
```

**修法:** 用 `(( n += 1 ))` 或 `(( ++n ))`。`wifiwatch` 踩过。

## 3. zsh:同名变量遮蔽内建/外部命令

- `status` 是 zsh **只读**变量(`launchwatch` 用 `read -r ... status` 直接报错)
- `log` 是 zsh 内建(数学函数),会遮蔽 `/usr/bin/log`,`log show` 报 "too many arguments"
- `pid` / `uid` 等也建议避开

**修法:** `command log show ...`,或用 `_proc_status` 这类带前缀的名字。

## 4. BSD awk 没有 GNU 扩展

macOS 的 `/usr/bin/awk` 是 BWK awk(20200816),不支持:

```awk
match(str, /re/, arr)     # ✗ GNU 扩展,BSD 报 syntax error
strtonum("0x1f")          # ✗ gawk only
gensub(/a/, "b", "g")     # ✗ gawk only
```

**修法:** 用 `RSTART` / `RLENGTH` + `substr()` 手写提取:

```awk
if (match(name, /\[[^]]+\]:[0-9]+/)) {
  s = substr(name, RSTART, RLENGTH)
  rb = index(s, "]:")
  bind = substr(s, 2, rb - 2)
  port = substr(s, rb + 2)
}
```

另外 **长三元链 `?:` 在 BSD awk 里会解析失败**,查表更稳:

```awk
BEGIN { S["22"]="ssh"; S["443"]="https" }
function svc(p) { return (p in S) ? S[p] : "?" }
```

## 5. `head` 提前关管道导致上游 SIGPIPE(141)

`setopt pipefail` 下,`| head -30` 会让上游收到 SIGPIPE,整个管道返回 141,在 errexit 里等于脚本失败。

**修法:** 用 `awk 'NR<=30'` 截断,或 `|| true` 兜住。

## 6. `plutil -extract` 对不存在的 key 返回 exit 1

```zsh
label=$(plutil -extract Label raw -o - "$plist" 2>/dev/null)   # ✗ errexit 下杀掉脚本
label=$(plutil -extract Label raw -o - "$plist" 2>/dev/null || raw="")   # ✓
```

`launchwatch` 逐个 plist 解析时踩过。另外 **`KeepAlive` 常是 dict 而非 bool**,`raw` 模式会输出多行,破坏 TSV,需要 `v=${v//$'\n'/ }` 压成单行。

## 7. `plutil -extract` 参数用 `-o -`

新版 macOS 推荐 `plutil -extract KEY raw -o - FILE`;`raw` 不加 `-o -` 在某些版本会输出 plutil 自己的提示。

## 8. Wi-Fi:`airport` 已被移除,`wdutil` 需要 sudo

macOS 14+ 不再提供 `/System/Library/PrivateFrameworks/Apple80211.framework/.../airport`,
`wdutil info` 必须 `sudo`。**唯一不需 sudo 的实时 Wi-Fi 源是 `system_profiler SPAirPortDataType`**(约 1s,可接受)。

解析时注意层级缩进(SSID 行比 key/value 多缩进 2 空格):

```
Wi-Fi:                                          0
      Interfaces:                                6
        en1:                                     8
          Status: Connected                      10
          Current Network Information:           10
            <SSID>:                              12   ← SSID 在这
              PHY Mode: 802.11ax                 14
              Channel: 40 (5GHz, 160MHz)         14
              Signal / Noise: -47 dBm / -85 dBm  14
```

要点:
- Wi-Fi 接口**不一定是 en0**(这台 M4 上是 en1),必须动态探测
- 同样输出里还有 `awdl0`(AirDrop/Handoff),也有自己的 `Current Network Information`,别搞混
- macOS 14+ **不再输出 BSSID**(隐私)
- `Signal / Noise: -47 dBm / -85 dBm` 按空白切分后 RSSI 是 `$4`、Noise 是 `$7`(不是 `$6`)
- 同一台机器还会输出 `awdl0` / `llw0` 等,接口探测要按"Wi-Fi: → Interfaces: → 第一个接口"来走

## 9. 温度:真正读不到 °C

`kern.thermal_state` / `machdep.xcpm.cpu_thermal_level` 在 Apple Silicon 上**都不存在**,
真温度在 SMC 里需要 `sudo powermetrics --samplers smc`。

`tempwatch` 因此改用**间接信号**判断散热压力:当前频率 vs 最大频率、Top CPU 进程(发热相关)、
进程调度状态、内存压力。脚本底部明确标注了这条限制,不假装能读温度。

## 10. `zsh -n` 查不出运行时问题

`zsh -n` 只做语法检查,上面 1/2/3/6/7 全部能通过语法检查却在运行时炸。
写完必须实跑,并检查:

```sh
./script --once 2>&1 | grep -cE '^[a-z_]+='   # 变量回显残留,应为 0
./script --once 2>&1 | grep -E 'command not found|syntax error|read-only'
```

## 11. 终端宽度导致的"假空行"

`printf "%-40s"` 之类补齐宽度的字段,在输出被管道捕获时看起来像空行,
但内容其实是一串空格。`cat -A` / `od -c` 能看清,不要被终端渲染误导。

## 12. BSD awk 的 `match()` 不支持 `+` 重复量词

```awk
match(ui, /@[0-9.]+Hz/)     # ✗ 静默不匹配(BWK awk)
match(ui, /@[0-9.]*Hz/)     # ✗ 同样不匹配
```

`wifiwatch` / `displaywatch` 的刷新率提取都栽在这里,表现为"值莫名其妙全是 ?"。
**修法:** 改用 `split()` 按分隔符切,别用正则量词。

```awk
n = split(ui, parts, "@"); sub(/[[:space:]]*Hz.*$/, "", parts[2])
```

## 13. `ioreg` 三种调用方式各缺一半数据

写 `devtreewatch` 时逐个实测:

| 命令 | 节点树 | USB 属性 |
|---|---|---|
| `ioreg -p IOUSB -w 0` | ✅ | ❌ |
| `ioreg -w 0` | ✅ | ❌ |
| `ioreg -c IOUSBHostDevice -w 0` | ❌ | ✅ |
| `ioreg -r -c IOUSBHostDevice -w 0` | ✅ | ✅ |

`-r`(raw)不能省:默认输出会重复 `| ` 前缀,导致缩进计算全错。
属性行缩进 = 所属节点缩进 + 4,靠这个关联。

另外提取属性 key 时**必须先剥掉行首缩进**(含 `|`),否则 key 会变成
`"  | |   USB Product Name"`,永远匹配不上。

## 14. `system_profiler` 里字段名是子串匹配会互相覆盖

```
"          Status: No device connected"
"          Link Status: 0x100"     ← /Status:/ 也会匹配这一行
```

`/Status:/` 命中 `Link Status:`,把真正的 Status 覆盖掉。
**修法:** 用锚定正则 `^[[:space:]]*Status:/`,并显式排除 `Link Status:`。

## 15. awk 脚本的 `-v` 必须放在程序之前

```awk
awk '...' -v b="$C_BOLD"     # ✗ awk 以为 -v 是输入文件名
awk -v b="$C_BOLD" '...'     # ✓
```

`devtreewatch` / `audiowatch` 各踩一次,报错是 `awk: can't open file -v`。

## 16. 按字节切分会切坏中文

`awk` 的 `substr()` / `length()` 按**字节**算,中文 3 字节。
按 26 字符截断含中文的设备名会切出乱码半个字。
**修法:** 给含中文的列留足宽度,或干脆不截断。

## 17. `osascript` 输出的分隔

```
output volume:39, input volume:89, alert volume:0, output muted:false
```

用 `tr ',' '\n'` 切会连 `volume:39` 一起切坏。
**修法:** `sed 's/,[[:space:]]*/\n/g'` 只在逗号后接空白处断行。

---

## 可继续扩展的方向

现有 14 个脚本覆盖了硬件(内存/CPU/磁盘/电池/温度/网络/Wi-Fi)、
进程(进程树/端口)、安全(登录审计/自启动项)、运维(大文件清理)。
尚未覆盖的原生数据源:

- **键盘 / 输入法** — `defaults read com.apple.HIToolbox`,查布局与快捷键冲突
- **剪贴板历史** — `pbpaste` + `osascript`,不依赖第三方剪贴板工具
- **TLS 证书有效期** — `openssl s_client` 检查内网/公司证书是否过期
- **网络诊断** — ping / traceroute / `dscacheutil -q host` 组合,定位办公网问题
- **Spotlight 索引状态** — `mdutil -sa`,公司机常被 MDM 关掉
- **Time Machine 备份历史** — `tmutil listbackups` + `tmutil calculatedrift`
