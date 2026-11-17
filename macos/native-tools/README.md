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
| `secwatch` | 安全态势:FileVault / SIP / Gatekeeper / 防火墙 / 隔离区 | fdesetup, csrutil, spctl, socketfilterfw, sqlite3 | 单次 |
| `crashwatch` | 崩溃日志 / panic / 内存不足 / 资源异常 | ~/Library/Logs/DiagnosticReports | 单次 |
| `extwatch` | 系统扩展 / 后台登录项 / launchd 常驻任务 | systemextensionsctl, sfltool dumpbtm, launchctl | 单次 |
| `backupwatch` | Time Machine / APFS 快照占用 / 备份盘 | tmutil, diskutil apfs listSnapshots, mount | 单次 |
| `inputwatch` | 键盘布局 / 输入法 / 快捷键 / 指针设置 | defaults read, system_profiler | 单次 |
| `netpath` | 网络路径决策:这个包走哪条路 | route, scutil --nc/--dns/--nwi, netstat -rn | 单次 / `--services` / `--dns` / `--watch` |
| `netdiag` | 连通性诊断包(DNS→ping→端口→traceroute→MTU) | ping, nc -z, traceroute, dscacheutil, route | 单次 / `--quick` / `--tcp` |
| `shareprint` | 文件共享点 / guest access / 打印队列 / 共享端口 | /usr/sbin/sharing, lpstat, lsof, dns-sd | 单次 / `--json` |
| `logtriage` | 系统日志分诊:谁在刷错误 / 签名异常 / 循环失败 | log show --style json | 单次 / `--gatekeeper` / `--timeline` / `--raw` |
| `proxytrace` | 代理链路:TUN vs 系统代理 vs PAC 谁在生效 | scutil --proxy/--dns, networksetup, route | 单次 / `--mode` / `--json` |
| `codesignaudit` | App 签名与供应链:签名完整性 / Team 来源 / Hardened Runtime / quarantine | codesign, spctl, xattr | 单次 / `--issues` / `--teams` / `--app` / `--json` |
| `devstack` | 开发环境全景:PATH 链 / Xcode 与 CLT / SDK 矩阵 / 语言运行时 / 版本冲突 | xcode-select, xcodebuild, xcrun, pkgutil, whence | 单次 / `--path` / `--xcode` / `--langs` / `--json` |
| `tccaudit` | 隐私权限审计:谁拿到了完全磁盘 / 屏幕录制 / 辅助功能 | sqlite3 (TCC.db), date | 单次 / `--disk` / `--screen` / `--zombies` / `--json` |
| `sleepaudit` | 睡眠 / 唤醒 / 电源事件审计 + 谁在阻止休眠 | pmset -g log, pmset -g batt, sysctl | 单次 / `--hours` / `--days` / `--timeline` / `--holders` / `--json` |
| `installhist` | 安装历史 + 自动更新策略(装过什么、谁装的、策略有没有被关) | system_profiler SPInstallHistoryDataType, defaults | 单次 / `--recent` / `--policy` / `--json` |
| `spaceaudit` | APFS 空间对账:容器 / 卷 / 快照 / 差额(空间到底去哪了) | diskutil apfs list, listSnapshots, df -k, tmutil | 单次 / `--containers` / `--volumes` / `--snapshots` / `--json` |
| `mdwatch` | Spotlight 索引观察器:搜不到文件 / 开机卡 | mdutil, mdfind, pgrep | 单次 / `--volumes` / `--excluded` / `--deep` / `--json` |
| `dupescan` | 重复文件扫描(先按大小筛,再 SHA-256 校验) | find, stat, shasum | 单次 / `--dir` / `--min-size` / `--no-hash` / `--json` |
| `permcheck` | 权限与 ACL 体检:世界可写 / SUID / 越权 ACL | stat, ls -le, find -perm | 单次 / `--dir` / `--system` / `--json` |
| `bandwidth` | 带宽 / 响应性实测 + 缓冲膨胀 + 历史趋势 | networkQuality -c, scutil --proxy, route | 单次 / `--seconds` / `--quick` / `--interface` / `--history` / `--json` |
| `dualview` | 多显示器拓扑:排列几何 / HiDPI / 刷新率 / 主屏 | osascript -l JavaScript (NSScreen + CoreGraphics), system_profiler | 单次 / `--map` / `--list` / `--json` |

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

## 18. awk 单引号块内不能用 `\` 续行

```awk
awk '
  printf "a %s b\n", \
    x, y
'                          # ✗ syntax error near '\'
```

`\` 只在 **shell 层**是续行;进了 awk 的单引号字符串后就是字面反斜杠。
本项目里反复栽在这个上面(`extwatch` / `crashwatch` / `backupwatch` 各一次)。
**修法:** awk 内的长语句一律写成一行;或先把 `-v` 赋值写成独立变量再进 printf。

## 19. shell 里 `grep -v '^$'` 无匹配时返回 1

`setopt errexit` 下,过滤器一个都没匹配到 → 退出码 1 → 整个脚本静默中断。
表现是"输出到某一行就没了",没有任何报错。
**修法:** 过滤后必须接 `|| true`。这坑在 `crashwatch` 让明细表整个消失。

## 20. `${(f)"$(...)"}` 数组捕获可能丢分隔符

```zsh
rows=(${(f)"$(cmd)"})       # 按行切,行内 tab 保留
print -r -- "${rows[@]}"     # 但这样输出会粘成一行
```

`secwatch` 一开始隔离区表格整行挤在一起,就是这个原因。
**修法:** 拿到单个变量后直接 `print -r -- "$out" | awk -F'	'` 管道给 awk,
不要走数组。

## 21. 传 `-g` 给 `defaults` 会被 zsh 当 glob

```zsh
defaults read -g com.apple.keyboard.KeyboardRepeat   # ✗ no matches found: -g*
_d -g com.apple.keyboard.KeyboardRepeat              # ✗ 同上
_d NSGlobalDomain com.apple.keyboard.KeyboardRepeat  # ✓
```

`emulate -L zsh` 默认开着 glob,`-g*` 匹配不到文件就报错。
**修法:** 用 `NSGlobalDomain` 代替 `-g`,对 `defaults` 完全等价。

## 22. `sqlite3` 的三个坑

```sh
# ① SQL 必须单行 —— 多行 SQL 在 $() 里可能拿不到结果
# ② CASE ... ELSE 'prefix'||col 会被误解析(把 - 当运算符)
sql="select ..., case t when 0 then 'file' end from ..."
# ③ 列名为空时要显式兜底,否则 awk 的 $N 会错位
```

## 23. 工具的错误信息可能走 stdout 而非 stderr

```sh
tmutil listbackups 2>/dev/null     # ✗ 错误信息照样漏出来
# 实际输出:
#   No machine directory found for host.
#   Command exited with status 1.
tmutil listbackups 2>&1 | grep -E '^/Volumes/.*\.backup$'   # ✓ 内容判定
```

**修法:** 对这类"失败也算成功返回"的工具,拿 `2>&1` 存变量后**按内容判定**,
而不是靠退出码。

## 24. zsh 函数必须先定义后调用

`_print_checks` 定义在 `_render` 之后 → 调用时 function not found → 静默退出。
`secwatch` 因此只输出了前两段就停。写完顺手核对一下定义顺序。

---

## 25. `local path=...` 会把 `PATH` 整个覆盖掉 ⚠ 最隐蔽

`path` 在 zsh 里是**与 `PATH` 绑定的数组变量**,不像 bash 那样是独立变量。

```zsh
local nm path proto ...
while read -r nm path ...; do ... done
print -r -- "$rows" | awk ...
```

症状:**只报一个** `command not found: awk` 就再无输出,前面所有解析都正常。
`zsh -x` 会看到 `local path=/Users/lex/Public` 之后所有外部命令都找不到。

```zsh
# 实测
$ zsh -c 'f(){ local path=/foo; print $PATH }; f'
/foo          ← PATH 被吃掉了
```

**修法:** zsh 层变量一律避开 `path`,用 `sh_path` / `target_dir` 之类。
**注意:** awk 内部的 `path` 变量无害(awk 不是 shell,不绑定 PATH),只有 zsh 层要避。
`shareprint` 的 `_shares_block` 中过这个坑。

## 26. `[[ $host != *[!0-9.]* ]]` 在 `emulate -L zsh` 下会静默返回假

写"判断是不是主机名"时用了这个 glob:

```zsh
if [[ -n $host && $host != *[![0-9.]]* ]]; then   # ✗
```

`netpath --dns github.com` 的解析段**整个不执行**,不报错、不中断,
`zsh -x` 显示从该行直接跳到函数末尾。

**修法:** 用 `case` 而不是 `[[ != glob ]]`:

```zsh
_is_ipv4() {
  case $1 in
    <->.<->.<->.<->) return 0 ;;
    *)              return 1 ;;
  esac
}
```

`netpath` 三处、`netdiag` 一处都改成了 `case`。

## 27. `route -n get` 的 MTU 在表头下一行,不在 `mtu:` 行

```sh
route -n get 8.8.8.8
#      recvpipe  sendpipe  ssthresh  rtt,msec    rttvar  hopcount      mtu     expire
#            0         0         0         0         0         0      4000         0
```

没有 `mtu: 4000` 这种独立行 —— MTU 是那张表的**第 7 列**。
而且数据行是纯数字,**不含 `recvpipe` 字样**,所以 `grep recvpipe` 只匹配到表头行,
`awk '{print $7}'` 会输出字符串 `mtu`。

**修法:** 先匹配表头行,再 `getline` 取下一行:

```sh
awk '/recvpipe[[:space:]]+sendpipe/ { getline; print $7; exit }'
```

## 28. 靠退出码判断的工具必须兜住,否则 `errexit` 静默杀脚本

```zsh
out=$(nc -z -G 3 -w 3 "$host" "$p" 2>&1)   # ✗ 端口关闭 → nc 返回 1 → 脚本死在这
rc=$?                                          #   永远到不了
```

症状:**输出到第 N 个端口就静默停止**,没有任何错误信息。
`./netdiag --quick <host> 80,443,22` 里 22 是关闭端口,结果 80/443 打完就没了。

**修法:** `rc=0` 先初始化,再用 `|| rc=$?` 只在失败时覆盖:

```zsh
rc=0
out=$(nc -z ... 2>&1) || rc=$?
```

同类工具:`nc` / `ping` / `traceroute` / `tmutil` / `mdutil`,凡是对"目标不可达"
返回非 0 的,都不能裸写 `$(...)`。跟 §23 是同一个根因的不同表现。

## 29. `scutil --nc list` 的第 1 行是表头说明,不是数据

```
Available network connection services in the current set (*=enabled):
* (Disconnected)   248C68ED-... VPN (io.tailscale.ipn.macsys) "Tailscale"   [VPN:...]
```

不跳过第一行,表格里会多出一行 `network / ? / connecti`。

**字段序(实测):** `[1]=*` `[2]=(Status)` `[3]=UUID` `[4]=VPN`
`[5]=(bundle.id)` `[6]="Name"` `[7]=[VPN:bundle.id]`

区分多条 VPN 的键是 **字段 5 的 bundle id**,不是字段 4 —— 不同客户端注册的
`type` 全都是 `VPN`。同名显示名也可能重复(本机两个都叫 "Loon")。

## 30. `scutil --dns` 的接口名在括号里,不是 `$3`

```
  if_index : 37 (utun4)
```

`$1=if_index` `$2=:` `$3=37` `$4=(utun4)`。
取 `$3` 会得到纯数字 `37`,显示成"iface: 37"。要从括号里抠:

```awk
if (match($0, /\([^)]+\)/)) idx = substr($0, RSTART + 1, RLENGTH - 2)
else idx = $3
```

另外 `resolver #1` 只有两个字段,编号在 `$2` 且**带前导 `#`**,要 `sub(/^#/, "", rid)`。

## 31. `netstat -rn` 的 `default` 行会被数字过滤误杀

```awk
NR>2 && $1 ~ /^[0-9]/ { print }    # ✗ "default" 不是数字开头,全被过滤
```

而 `default` 行恰恰是最关键的(它直接告诉你谁在吃默认路由)。

**修法:** `awk 'NR>2 && ($1 ~ /^[0-9]/ || $1 == "default")'`。

列序是 `$1=Destination $2=Gateway $3=Flags $4=Netif $5=Expire`,
`Expire` 常为空 —— 按 `$NF` 取列会取到 `Netif`。

## 32. `/usr/sbin/sharing -l` 是 tab + 空格混合缩进,数空格会失败

实测每行的前导字符:

| 行 | 前导 |
|---|---|
| `name:` / `path:` | 无 |
| `smb:` | **1 个 TAB** |
| 块内 `shared:` / `guest access:` | **4 空格 + 2 TAB** |
| `}` | **1 个 TAB** |

而且协议名后面**直接跟 `\t{` 在同一行**,不是另起一行。
"数缩进空格"的启发式在这里全军覆没 —— `awk` 的 `substr` 逐字符判断
只能数空格,数不到 tab。

**修法:** 用状态机而不是缩进启发 —— 看到 `^<TAB>字母+:` 进块,
看到 `^<TAB>}` 出块并输出。

另外共享名里可能有 UTF-8 右单引号(`’`),`awk -F'\t'` 按字节处理时
会报 `towc: multibyte conversion failure`,JSON 输出整个数组变空。
加 `LC_ALL=C awk` 按字节走即可。

## 33. `--json` 模式的 trap 不能往 stdout 写任何东西

```zsh
_cleanup() { printf '\033[?25h\033[0m'; echo; }   # ✗ 跟在 `}` 后面
```

消费方 `json.load()` 报 `Extra data: line 10 column 1`,
`jq` 报 `Unexpected character`。肉眼完全看不出问题 —— 终端里就是一行。

**修法:**

```zsh
_cleanup() {
  $DO_JSON && return
  printf '\033[?25h\033[0m'; echo
}
```

**通用原则:** 任何承诺机器可读的输出模式,`_render` 和 `_cleanup` 两处都不能污染 stdout。
非 TTY 时 `_cleanup` 仍会输出 1 个 ESC(和 `inputwatch` 等现有脚本行为一致,
因为光标恢复只在 TTY 下有意义),所以 G4 闸口要排除这一行。

## 34. VPN 全局模式下"默认路由"拿不到本地网关

```sh
route -n get default
#   interface: utun4        ← 没有 gateway 行(点对点隧道)
```

这时测网关延迟测的是隧道,不是 Wi-Fi —— 而用户真正想知道的是 Wi-Fi 有没有问题。

**修法:** 回退到物理接口自己的 default 路由:

```sh
phy=$(netstat -rn -f inet | awk '$1 == "default" && $NF !~ /^utun/ { print $NF; exit }')
```

本机实测:`utun4`(Loon)吃默认路由,但 `en1` 仍有独立的 `default → 192.168.31.1`,
回退后测得 9.5ms —— 这才是真实的本地链路延迟。

## 35. fake-ip:DNS 解析结果可能是假地址

TUN 模式代理(Loon / Clash / Surge)接管 DNS 后,域名会被映射到保留段的假地址,
真实连接由代理端发起。本机实测 `github.com → 198.0.0.74`(Loon 用的 `198.0.0.0/16`;
Clash / Surge 常用 `198.18.0.0/16`)。

后果很实在:**ping / nc / curl 到的不是服务器,是本地代理入口**,
测出来的延迟(本机 0.2ms)完全是代理本地的延迟,没有参考价值。

判断:落在 `198.0.0.0/8`(RFC 2544 benchmarking 保留段,不做公网路由)即命中。

---

## 36. zsh 里 `log` 是数学函数,必须 `command log` ⚠

§3 记过"`log` 会遮蔽 `/usr/bin/log`",但没写清楚**根因和确切症状**:

```zsh
$ zsh -c 'log show --last 1s --style compact'
zsh:log:1: too many arguments          ← zsh 自己报的,不是 log 报的

$ zsh -c 'command log show --last 1s --style compact'
Timestamp  Ty  Process[PID:TID]        ← 正常
```

`log` 在 zsh 里是数学函数(对数十进制底),裸调用会被 zsh 内建截获并
对参数做求值,`--last 1s` 不是合法数学表达式 → 直接报 too many arguments。

**注意:** 如果调用被包在 `$(...)` 里再喂给 `awk`,错误信息会变成
`log: too many arguments` 混进数据流,更难定位。

**修法:** 所有 `log show` / `log stream` 都加 `command` 前缀。
`logtriage` 三处全部踩过。

## 37. `log show` 必须用 `--style json`,compact 模式是废的

```sh
log show --last 1h --predicate 'messageType == error' --style compact \
  | awk '{print $NF}' | sort | uniq -c | sort -rn | head
#  ref 105350 / directory 90318 / out 8611 / 3 8104 ...   ← 全是噪音
```

消息体被替换成 `<private>`,`awk '{print $NF}'` 只能切出碎片。

```sh
log show ... --style json
#  "subsystem" : "com.apple.CarbonCore"
#  "processImagePath" : "\/usr\/sbin\/cfprefsd"
#  "formatString" : "%s: FSNode(%d): asked for zero entry ref"
```

**修法:** 用 json 模式。本机实测 30 分钟错误日志 = 519 万行 / 4.6 秒,性能完全可接受。

**predicate 的引号:** 整体必须用**单引号**包住。写成
`--predicate "a == \"x\""` 时 shell 先吃掉一层引号,`log show` 收到残缺 predicate,
**返回空结果且不报错** —— 静默失效,极难发现。

```zsh
command log show --last 1h --predicate 'process == "syspolicyd"' --style json  # ✓
```

另外 `log show` 的 predicate **接受单引号字符串**:
`--predicate "process == 'cfprefsd'"` 实测也有效(976 条命中),
所以变量插值时用双引号包外层、单引号包值最安全。

## 38. 大 JSON 绝对不能进 shell 变量

2 分钟窗口的错误日志 = **29 万行 ≈ 30MB**。存进变量后:

- 每个 block 再 `print -r` 出来 + `tr` + `grep` + `sort`
- 5 个 block = **5 次 30MB 复制**
- 实测直接 **>180 秒超时**

**修法:** 落临时文件,block 引用路径;更狠的是把提取结果也落盘一次:

```zsh
LOG_JSON=$(mktemp ...)
command log show ... --style json >"$LOG_JSON"
_extract >"$LOG_JSON.tsv"      # 只解析一次
# block 全部 cat "$LOG_JSON.tsv" | awk ...
```

实测降到 **1.6 秒**。`_cleanup` trap 里记得删临时文件。

## 39. 从 JSON 提值要跳过键名的引号对

```awk
p = index($0, "\"processImagePath\"")
if (match(substr($0, p), /"[^"]*"/)) proc = substr(..., RSTART+1, RLENGTH-2)
# ✗ 提取到的是 processImagePath 这个键名本身,不是值
```

结果:整张表所有行都显示成 `processImagePath` / `subsystem` / `formatString`,
计数还挺大 —— 看起来像在跑,其实全是垃圾。

**修法:** 先匹配到键名后面的冒号,再从那里开始找值的引号对:

```awk
if (match(rest, /"[^"]*"[[:space:]]*:/)) {
  v = substr(rest, RSTART + RLENGTH)      # 跳过键名,从值开始
  if (match(v, /"[^"]*"/)) val = substr(v, RSTART + 1, RLENGTH - 2)
}
```

## 40. `uniq -c` 的输出不能用 `awk '{print $1, $2}'`

时间线要按分钟分桶,而分钟串 `2026-09-28 18:04` **本身含空格**:

```awk
uniq -c | awk '{ print $1, $2 }'
#  8118 2026-09-28        ← 时间部分整个丢了
```

**修法:** 剥前导空白后按首个空白切成两段,再用 tab 传给 shell:

```awk
sed 's/^[[:space:]]*//' | awk -v OFS='\t' '{ c=$1; $1=""; sub(/^[[:space:]]+/,""); print c, $0 }'
```

## 41. BSD awk 的 `match()` 对日期正则会少截字符

```awk
match(rest, /"[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}"/)
# 实际只匹配到 "2026-09-28 18:0"  ← RLENGTH 少算了
```

跟 §12 是同一个坑的延伸:**不要用 `match` + `RLENGTH` 提取定长格式**。
拆成 `split()` 按分隔符切:

```awk
match(rest, /"[^"]*"/) && { v = substr(...) }
nf = split(v, dt, /[ T]/)
ts = dt[1] " " substr(dt[2], 1, 5)     # 秒数再截掉
```

## 42. `networksetup` 对不存在的服务名报错且返回非 0

```sh
networksetup -getwebproxy "Thunderbolt Bridge"
# ** Error: Unable to find item in network database.
# exit 1
```

如果循环里不加 `|| true`,`errexit` 会杀掉整个脚本(§28 同根因)。

另外 `-listallnetworkservices` 的**第 1 行是表头说明**
("An asterisk (*) denotes that a network service is disabled."),
不是服务名 —— 直接 `tail -n +2` 剥掉。服务名可能带 `*` 前缀(禁用),
传参给 `-getwebproxy` 前要去掉。

## 43. 同一函数里同一个变量只能 `local` 一次

§1 说的是"循环体内重复 local",但真正的原因更宽:**同函数内二次声明同一变量**。

```zsh
for (( i=1; i<=${#lines[@]}; i++ )); do
  svc=${lines[$i]}          # 循环一里 svc='Loon for Mac'
done

local i svc st web ...      # 循环二里又 local svc
for (( i=1; i<=${#names[@]}; i++ )); do ... done
# → stdout 顶部多出一行 "svc='Loon for Mac'"
```

即使两个 `local` 都在循环体**外面**、中间还有别的语句,也照样回显。
`proxytrace` 的服务表格上方就是这么多出一行的。

**修法:** 把一个函数里所有要用的变量在函数开头一次性 `local` 完。
这个习惯值得在整个项目里执行 —— 它同时规避 §1 和 §43。

## 44. zsh 双引号串里不能再直接嵌双引号

```zsh
echo "  ${C_DIM}  所以下面这些"看着没开代理"的配置...${C_RESET}"
# ✗ 前面的双引号提前闭合,后半段被当命令执行
```

看起来能跑,但输出会被截断或报错。**修法:** 用中文引号 `「」`,
或者把整段拆成两次 `echo`。


---

## 45. `codesignaudit` 踩坑:三个真 bug,都是"看起来在跑其实早死了"

写 `codesignaudit` 时连续踩了三个坑,都是**脚本静默退出但没有报错**。
单独列出来,因为它们的症状(空输出 / 只输出一半)和"正常运行"很难区分。

### 45.1 `status` 是 zsh 只读变量

```zsh
local status=OK
# → _audit_one:19: read-only variable: status
```

zsh 的只读/特殊变量:`status`、`signame`、`signum`、`uid`、`gid`、`pid`、
`EGID`、`GID`、`LINENO`、`HISTCMD`、`path`(覆盖 `PATH`)。

**约定:结果变量叫 `sig` / `sev` / `nm`,不要用 `status` / `name` / `type`。**

### 45.2 数组不加引号 → 整体 exit 141

```zsh
for app in $apps; do        # ✗
  codesign --verbose=2 "$app"
done
```

`apps` 里有 `ChatGPT Atlas.app`、`TRAE SOLO CN.app`、`Loon 3.app` 这种带空格的名字。
不加引号时 zsh 按 IFS 拆开,`/Applications/ChatGPT` 不存在 → codesign 报错,
`setopt pipefail` 把这个错误一路上抛,**整个脚本 exit 141(SIGPIPE)**。

```zsh
for app in "${apps[@]}"; do  # ✓
```

**鉴别**:`echo $?` 是 141 而不是 1;`grep 'for [a-z_]* in \$'`(没有引号)能静态扫出来。

### 45.3 `grep | head -1` 在巨量输入上会杀掉整个脚本

最隐蔽的一个。`codesign --verify` 对签名损坏的 App 会输出**数千行**:

```
ChatGPT Atlas.app: a sealed resource is missing or invalid
file missing: .../Resources/sl_NEUTER.lproj/locale.pak
file missing: .../Resources/pt_PT_NEUTER.lproj/locale.pak
...  (实测 2000+ 行)
```

我写的是:

```zsh
detail=$(print -r -- "$out" | grep -oE '(file modified|file added): .*' | head -1)
# → exit 141,脚本静默死在这里,只输出了 banner
```

`head -1` 拿到第一行就退出并**关闭管道**,上游 `grep` 收到 SIGPIPE(141),
`pipefail` 把这个非 0 状态当成致命错误。数据量越大越容易触发——
小规模测试时不会暴露。

**修法:用 awk 的"找到就 exit"代替 head,让上游自然读到 EOF**:

```zsh
detail=$(print -r -- "$out" | awk '
  /file modified/ || /file missing/ || /sealed resource/ {
    if (!seen) { print; seen = 1; exit }   # exit 在 awk 内,管道正常关闭
  }
' || true)
```

**鉴别**:同样的 grep/head 在小输入上正常、在真实数据上 exit 141
→ 就是 SIGPIPE,把 `head` 换成 `awk '{...; exit}'`。

### 通用判据

任何 `cmd | grep PATTERN | head -1` 形式的**赋值语句**,在 `setopt errexit pipefail` 下都有风险。
要么末尾加 `|| true`,要么改用 awk 内部 exit,要么先 `head -c` 限制输入量。
`if` 条件里的 `grep -q` 不受影响(无匹配走 else 分支,不算错误)。

### 45.4 单 App 路径解析:候选顺序有讲究

`--app Loon` 解析失败,但 `/Applications/Loon.app` 明明存在。原因是我先做了
`${p%/}.app`,在当前目录生成了 `Loon.app` 相对路径。

```zsh
# ✗ 顺序错:先补 .app,当前目录没有就直接判失败
for p in "$SINGLE" "/Applications/$SINGLE"; do ...

# ✓ 顺序对:原样 → 补 .app → 路径拼接
for c in "$SINGLE" "$SINGLE.app" "/Applications/$SINGLE" \
         "/Applications/${SINGLE%.app}.app" ...; do
  [[ -d $c ]] || continue
  print -r -- "$c"; return 0
done
```

现在 `--app Loon` / `--app Loon.app` / `--app /Applications/Loon 3.app` 三种形式都能命中。

### 45.5 别对每个 App 跑 spctl

`spctl --assess` 对 178 个 App 要 20 秒以上,而它给出的结论和
`codesign --verify` 高度重叠。Gatekeeper 判定留到 `--app` 单个模式,
全量模式只用 `codesign` + `xattr`。

**签名状态的四档不要混淆**(README 表格里的 `codesign --verify` 输出):

| 输出 | 含义 | 是安全问题吗 |
|---|---|---|
| `satisfies its Designated Requirement` | 签名完好 | 否 |
| `resource envelope is obsolete` | 签名完好,资源封套格式旧 | 否 —— 开发方没更新而已 |
| `file modified` / `file added` / `a sealed resource is missing` | 签名与内容对不上 | **是** —— 通常被打过补丁 |
| `code object is not signed at all` | 无签名 | 看来源 |

**这正好解释了 `logtriage` 里 `syspolicyd` 为什么疯狂刷日志**:
前两档 App 不会被反复校验,只有第三档(签名损坏)会触发
Gatekeeper 持续重新验证。本机实测 178 个 App 里有 3 个是第三档。

---

## 46. `log stream` 把 "Filtering the log data using …" 打到 stdout

```zsh
# 实测
$ log stream --style compact --predicate 'x == 1' > out.txt 2>err.txt
head -1 out.txt
# → Filtering the log data using "x == 1"      ← 这不是日志,是横幅
$ cat err.txt                                 # ← 空的
```

后果:任何 `log stream … | grep/awk` 都会先吃到这一行,统计结果永远多 1 条。
做实时跟随脚本时必须 `--predicate` 之后立刻过滤掉以 `Filtering the log data` 开头的行,
或者干脆改用 `log show --last 1s` 轮询。

## 47. zsh 不对未加引号的参数做分词(bash 会)

```zsh
kindflag="-type f"
find "$dir" $kindflag -perm -002          # ✗ find 收到的是**一个**叫 "-type f" 的参数
find "$dir" ${=kindflag} -perm -002        # ✓ ${=var} 强制分词
find "$dir" -type f -perm -002             # ✓ 最省事:别用变量拼参数

# 正确做法:数组
local -a kindflag; kindflag=(-type f)
find "$dir" "${kindflag[@]}" -perm -002    # ✓
```

实测踩过的现场:写 `permcheck` 时把 `-type f/-type d` 抽成变量,
结果 find 静默不匹配任何东西,**不报错、不输出、统计为 0** ——
看起来像"这台机器权限没问题",其实是根本没扫。

## 48. BSD awk 的 printf:参数多于转换符时**静默丢弃**

```awk
# 10 个参数,格式串只有 8 个 %s
printf "  %s%s%s %-52s %s%s  %s%s\n", col, mark, r, $2, d, $5, r, d, reason, r
#                                                                        ↑↑ 没了
```

不报错、不循环补行(这是 zsh 的 `printf` 行为,两者不一样),
表现为"某一列永远是空的"。**写完 printf 立刻数一遍 %s 和参数**。
另外格式串里的空格是**字面量**,不会被"对齐"到列上 ——
`"%s%s%s  %s%s%s"` 里的两个空格是第 3 组和第 4 组之间的分隔,
不是"值和说明之间"的分隔,放错组的位置就会看到值和说明粘在一起。

## 49. zsh 函数里 `X || return` 会带着失败状态返回

```zsh
f() { $FLAG || return; ... }     # ✗ $FLAG 为假时 return,返回码是 1
g() { $FLAG || return 0; ... }   # ✓
```

`$FLAG || return` 里 `return` 继承上一条命令(`$FLAG`)的退出码 = 1,
调用方立刻被 `errexit` 打死。现场表现是脚本跑完前半段后 **exit 1 且不打印任何错误**。
排查这类"静默死亡"时用 `zsh -x 脚本 2>&1 | tail` 看最后一条 trace 停在哪。

## 50. `find` 遇到读不了的目录会 exit 1,pipefail 会把它变成静默死亡

```zsh
out=$(find ~ -type f -exec stat -f '%Sp' {} + | awk '...')   # ✗
# find 遇到 ~/Library 里某个受保护目录 → exit 1
# pipefail → 管道状态 1 → errexit → 脚本当场死掉,stdout 一个字都没有
out=$(find ~ -type f -exec stat -f '%Sp' {} + 2>/dev/null | awk '...' || true)  # ✓
```

同理适用于任何"可能部分失败"的采集命令:`stat`、`diskutil`、`mdutil`。
**采集阶段一律 `|| true`,让"某一项没采到"变成空数据而不是整脚本死亡。**

## 51. 解析系统日志必须 `LC_ALL=C`

```zsh
pmset -g log | awk '{ if (match($0, /…/)) … }'
# awk: towc: multibyte conversion failure on: 'Lex\x92s Magic Trackpad …'
# input record number 41172
```

`pmset` / `log show` / `system_profiler` 的输出里混着非 UTF-8 字节(设备名、人名),
BSD awk 默认按多字节处理,遇到坏字节就**整条管道死掉**,而且报错行号是几万行之后的那行。
所有解析系统输出的 awk 一律加 `LC_ALL=C`,顺带 `length()` 变成字节语义,
对 ASCII 日志正是想要的(渲染中文时另说,见 #16)。

## 52. 绝对不要在 awk 里把"一组多行"拼进一个字段再交给 `while read`

```zsh
# ✗ awk 里 p[h] = p[h] "\n" path,输出一个"含换行的字段"
print -r -- "$out" | while IFS=$'\t' read -r n paths; do …; done
# read 是按行读的:paths 只拿到第一行,剩下的行被当成新记录
# → 出现 count=0 / wasted 为负数的垃圾数据,而且不报错
```

**凡是"一组多行"的数据,一律保持行式流**:
每行一条记录 + 组 id,回到 shell 后用关联数组在内存里聚合
(`paths_of[$size]+="$path"$'\n'`)。`dupescan` 整条流水线都是按这个原则写的。

## 53. `${(f)…}` 对位置参数的三种写法只有一种能用

```zsh
for p in ${(f)"$1"}; do …; done     # ✗ bad substitution
for p in ${(f)$1};   do …; done     # ✗ bad substitution
for p in ${(f)1};    do …; done     # ✓ 只有裸位置参数行
for p in ${(f)x};    do …; done     # ✓ 具名变量也行
for p in ${(@f)arr}; do …; done     # ✓ 数组要用 @,否则元素会被空格拼成一串
```

`${(f)"$(cmd)"}` 可以用(命令替换),`${(f)"$var"}` 和 `${(f)$var}` 都不行。
数组尤其注意:${(f)arr} 会把数组用空格 join 之后再按换行切,等于没切。

## 54. `${(j:sep:)arr}` 的分隔符带空格会 bad substitution

```zsh
print -r -- "${(j:, :)out}"    # ✗ bad substitution(空格被当成 expansion 结束)
sep=', '
print -r -- "${(pj:$sep:)out}" # ✓
print -r -- "${(j.$sep.)out}"  # ✗ 不展开变量,安静地拼出字面量 "$sep"
```

## 55. `ls -lde` 的 ACL 行带一个前导空格

```zsh
[[ $line == [0-9]*:* ]]          # ✗ 一条都匹配不上
line=${line##[[:space:]]}         # ✓
[[ $line == [0-9]*:* ]]
```

同理 `${name## }` 只去掉**一个**空格(zsh 里 " " 是单字符模式,不是"空格串"),
清完还剩一串空格,再 `%% ' '` 一刀切下去整行变空 —— 快照一条都收集不到。
trim 交给 `sed 's/.*Name:[[:space:]]*//'`。

## 56. BSD `date` 的 `-v` 与 awk 里的逐行 `date` = 分钟级开销

```zsh
# ✗ 四万行日志 = 四万个 date 进程,整个脚本 2 分 39 秒
awk '{ cmd = "date -j -f …"; cmd | getline epoch; … }'

# ✓ pmset 的时间戳是 "YYYY-MM-DD HH:MM:SS",字典序 == 时间序,直接比字符串
cutoff=$(date -v-${HOURS}H '+%Y-%m-%d %H:%M:%S')
awk -v cutoff="$cutoff" '($1 " " $2) < cutoff { next } …'
```

`sleepaudit` 用这个办法从 159 秒降到 3 秒。凡是日志时间戳都是 ISO 格式的场景都适用。

## 57. `${name## }` vs `stat -f %Sp` vs `df -k` 的三个小陷阱

- `stat -f '%Sp'` 给符号权限串;GNU 的 `%s`(文件大小)在 macOS 上会得到"权限串",别照抄。
- `df -k` 的单位是 **KB**;拿它当字节算,1.8T 会显示成 1862 GB。
- `diskutil apfs list` 的行首 `|` 会把 `Size (Capacity Ceiling):` 拆成
  `Size` / `(Capacity` / `Ceiling):` 三个字段,`$(NF-2)` 取到的是字符串 `"B"` → 结果恒为 0。
  用正则抓第一段 `<数字> B` 才稳。

## 58. zsh:重定向挂在 `read` 上 = 死循环,必须挂在 `while` 循环上

同一个循环,只因为重定向写在哪一侧,一个正常一个原地转圈:

```zsh
# ✗ 死循环:<<< 挂在 read 上,永远读到第一行
while IFS=$'\t' read -r a b c <<< "$data"
do
  print "$a"
done

# ✓ 正常:<<< 挂在 while 循环上(do…done 之后)
while IFS=$'\t' read -r a b c
do
  print "$a"
done <<< "$data"
```

```zsh
# 文件重定向同理:写在 read 上死循环,写在 done 上正常
while read -r l < /tmp/file; do print "$l"; done             # ✗
while read -r l; do print "$l"; done < /tmp/file             # ✓

{ while read -r l; do …; done; } < /tmp/file               # ✓ 整块重定向
cat /tmp/file | while read -r l; do …; done                # ✓ 管道(循环体在子 shell 里)
```

原因:zsh 给**内建命令**附加的输入重定向会被保存/还原,每次 `read` 结束
文件偏移量就回到原处,于是第一行被反复读。bash 没这个行为,所以照抄 bash 的写法
就会中招。现场表现:CPU 跑满、一行输出都没有,只有 `zsh -x 脚本 2>&1 | tail`
能看出它卡在 `read` 上。写循环时养成习惯:**重定向一律写在 `done` 后面**。

## 59. `IFS=$'\t'` 会**折叠连续 tab**,空字段直接消失 → 后面所有值整体左移

```zsh
row=$(printf 'a\t\tb\tc')          # 中间是空字段
IFS=$'\t' read -r x y z w <<< "$row"
# x=a  y=c  z=w  w=(空)   ← b 跑到了 y,整体错一位
```

因为 tab 属于 IFS 的**空白字符**,连续空白会被当成一个分隔符。
后果:解析系统输出时,某一项没取到值(正则没匹配上)就会让后面所有列错位,
症状非常迷惑(比如"刷新率"那一列显示 `Supported` —— 那是 Rotation 的值)。

两条纪律:

- **awk 永远不要吐空字段**,没取到就写 `-`,读进 shell 之后再换回空串。
- 需要区分"空字段"和"分隔符"时,换用非空白分隔符,例如
  `IFS=$'\x01'`(记得告诉 awk `-v OFS="\x01"`)。

## 60. JXA 拿不到的东西(写显示/窗口类脚本前先看这段)

```javascript
ObjC.import('AppKit'); ObjC.import('CoreGraphics');
const s = $.NSScreen.screens.objectAtIndex(0);
s.frame                 // ✓ 逻辑矩形(Quartz 坐标,y 向下)
s.backingScaleFactor    // ✓ 1 或 2
s.maximumFramesPerSecond// ✓ 当前刷新率
s.localizedName         // ✓ 屏名(和 system_profiler 里的名字一致,可用来 join)
s.screenNumber          // ✗ undefined!NSScreen 早就不有这个属性了
$.CGDisplayBounds(id)   // ✓ 像素/点矩形 + 原点(排左右关系就靠它)
$.CGDisplayIsBuiltin(id) / IsMain / IsOnline / IsAsleep / IsInMirrorSet  // ✓
$.CGDisplayMaximumRefreshRate(id)   // ✗ 本机(macOS 27)已不存在
$.CGDisplayCopyAllDisplayModes(id, null)  // ✗ 返回 CFArrayRef,JXA 里是个 "function",
                                           //    没法下标,拿不到"这块屏支持哪些刷新率"
```

- 屏号要从 `deviceDescription.objectForKey('NSScreenNumber')` 取,
  而且两边都要 `.intValue` 再比:对象用 `===` 比的是引用,永远 false。
- `NSScreen.frame` 是 **Cocoa 坐标**(原点在左下、y 向上),
  `CGDisplayBounds` 是 **Quartz 坐标**(原点在左上、y 向下),画拓扑图必须用后者,
  否则整张图上下颠倒。
- 想列出"这块屏支持的所有刷新率",系统自带接口在 JXA 里够不着,
  只能改看 `system_profiler` 的当前模式 + 让用户自己去系统设置里选。

## 61. `networkQuality -c` 的三个坑

```zsh
networkQuality -c -M 15      # ✓ 正常
```

1. **JSON 排版是 `"key" : value`,冒号前有空格**。
   所以 awk 里 `$1` 是键名、`$2` 是 `":"` —— 按 `$2` 取值会拿到一串冒号,
   所有数字变 0(实测"下行 0.0 Mbps")。取值要自己剥:
   `val=$0; sub(/^[^:]*:[[:space:]]*/,"",val)`。
2. **`dl_throughput` / `ul_throughput` 的单位是 bit/s**,不是 byte/s。
   实测 905216013 字节 / 19.9 秒 = 363 Mbps,字段值 385357120 = 385 Mbps。
   再乘 8 会凭空放大 8 倍。
3. **`other` 是三层嵌套对象,而且是多行排版**:
   `"other" : { "interface-type" : { "wifi" : 70 }, … }`。
   想按"一行里有键和值"来解析只对单行紧凑格式有效,多行格式下取到的永远是外层键名。
   要用状态机:记住外层键,吃下一行的内层键。

另外 `responsiveness` 就是**满载延迟(ms)**,和 `base_rtt`(空闲 RTT)相减
就是缓冲膨胀 —— 这是"带宽够但一开下载就卡"的量化指标。
`logtriage` 里的 `log show --style json` 是紧凑排版(`{"k":v}`),和这里不同,
别把两套解析混用。

---

## 可继续扩展的方向

现有 **38 个脚本**覆盖了硬件(内存/CPU/磁盘/电池/温度/网络/Wi-Fi/显示器/音频)、
进程(进程树/端口/资源)、安全(登录审计/自启动项/代码签名/隐私权限/权限 ACL)、
网络(路由/DNS/TCP 链路/代理链路/带宽实测)、系统诊断(Unified Log 分诊/Spotlight 索引)、
运维(大文件清理/重复文件/共享打印/空间对账/权限体检)、
开发环境(工具链全景/安装历史)、显示(单屏参数 + 多屏拓扑)。

下一批值得做的(按"能救最多人的排障场景"排序):

- **`loglive`** — 实时日志跟随。`logtriage` 是**回溯**分诊("刚才那一小时谁在刷错误"),
  缺的是**实时**视角:`log stream` 自带的输出没法过滤高亮、不能按进程/级别聚合。
  注意 `log stream` 会把 "Filtering the log data using ..." 这行打到 **stdout**,
  不去掉的话下游全被污染(坑见 #46)。
- **`trashwatch`** — 废纸篓体检。`~/.Trash` 几十 G 是 macOS 最常见的空间黑洞,
  而且 Finder 里根本看不到(Finder 显示的是"清倒废纸篓"前的可用空间)。
  零成本:du + stat。
- **`launchsched`** — 定时任务全景。`launchwatch` 看了 LaunchAgents/Daemons,
  但没解析 `StartCalendarInterval` / `StartInterval`(谁在半夜 3 点跑东西)
  和 `/etc/periodic/*`。
- **`fontlist`** — 字体清单与来源(系统 / 用户 / 某个 App 自带),
  排查"文档排版在同事机器上不一样"。`system_profiler SPFontsDataType` 很慢,
  直接遍历三个字体目录 + `atsutil` 更快。
- **`clippaste`** — 剪贴板元信息(来源 App、格式、大小)。**优先级最低**:
  `pbpaste` 只能读当前一条,没有历史功能,而那正是需要第三方工具的原因。

不建议做的:

- **凭据/Keychain 读取** — 需要交互解锁,且涉及敏感数据,不适合放进诊断工具集。
- **任何需要 sudo 的** — 这批脚本的设计前提是完全免 sudo 即可跑通。
- **实时高频采样类(powermetrics / fs_usage / networkQuality 循环)** — 要么要 root,
  要么一次采样几秒起,和"单文件、秒级响应"的设计前提冲突。
