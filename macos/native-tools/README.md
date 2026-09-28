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

## 可继续扩展的方向

现有 14 个脚本覆盖了硬件(内存/CPU/磁盘/电池/温度/网络/Wi-Fi)、
进程(进程树/端口)、安全(登录审计/自启动项)、运维(大文件清理)。
尚未覆盖的原生数据源:

- **剪贴板历史** — `pbpaste` + `osascript`,不依赖第三方剪贴板工具
- **TLS 证书有效期** — `openssl s_client` 检查内网/公司证书是否过期
- **网络诊断** — ping / traceroute / `dscacheutil -q host` 组合,定位办公网问题
- **Spotlight 索引状态** — `mdutil -sa`,公司机常被 MDM 关掉
- **软件更新状态** — `softwareupdate -l`,检查是否有待装补丁
- **打印队列** — `lpstat -p / -d`,公司常配共享打印机
- **字体清单** — `system_profiler SPFontsDataType`,排查排版问题
- **通知与专注模式** — `defaults read com.apple.ncprefs`,看哪些 app 在打扰你
- **能耗与电池循环** — `pmset -g` 补充 `batwatch` 缺的维度
