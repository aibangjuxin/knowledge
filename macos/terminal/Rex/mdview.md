# mdview 是什么（技术说明）

> **一句话**：`mdview` 是我（Pi 里的编码 Agent）为你**现写的一个 bash 脚本**，不是任何上游/现成工具。
> 它本身**不做渲染**，只是把「Rex 的分屏能力」和「terminal-browser 的渲染能力」缝在一起，
> 再加上 `glow` / `fzf` 两个现成工具做「当前 pane 速读」和「目录浏览」。
>
> 脚本本体：[mdview](./mdview)（约 146 行 bash，随本目录一起进 git）
> 软链：`~/.local/bin/mdview` → `/Users/lex/git/knowledge/macos/terminal/Rex/mdview`
> 关联文档：[How-to-view-markdown.md](./How-to-view-markdown.md)（怎么用）· [Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md)（Pi 侧方案）

---

## 一、血缘：哪些是我写的，哪些是现成的

```
┌─ 上游现成的 ────────────────────────────────────────────────┐
│  rex (Rex 多路复用器 CLI)          ← 开分屏、管 focus、管 label      │
│  terminal-browser v0.15.3         ← 真正的 Markdown 渲染器          │
│  glow / bat / fzf                 ← 速读、列目录、模糊选择            │
│  node                             ← 只用来做 URL 转义（pathToFileURL） │
└──────────────────────────────────────────────────────────────┘
                              ▲
                              │ 我写的 glue（mdview，约 146 行）
┌─ 借鉴但不依赖 ──────────────────────────────────────────────┐
│  jal-co/dotfiles 的 rex-markdown                             │
│    └ 复用其中 3 个「机制」，但完全不依赖它的其余部分            │
└──────────────────────────────────────────────────────────────┘
```

**从 rex-markdown 借来的 3 个机制**（上游作者：jal-co，见 [Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md)）：

| 借来的机制 | 具体内容 | 为什么要借 |
| --- | --- | --- |
| ① `rex run --split right --ratio 45 --focus=false` | 用 Rex 多路复用器在**当前 pane 右侧**开新窗格，且**不抢焦点** | 这是「一边跟 Agent 说话、一边看文档」体验的核心 |
| ② `terminal-browser-file://file<abs-path>` 这个 URL scheme | 让 terminal-browser 把本地 `.md` 当**文档**渲染（带样式的 Markdown 渲染器），而不是下载 | 上游用它渲染预览，我直接复用同一 URL 形式 |
| ③ 隔离的浏览器 profile（`~/.local/state/rex-markdown-browser`） | 8 个环境变量把 HOME / profile / config / cache / daemon 全隔离，**不碰你的个人浏览器**，并关掉 telemetry | 预览是自动化产物，不该污染日常浏览器环境 |

**完全不依赖**上游的部分（这正是 `mdview` 存在的意义）：

- ❌ 不依赖 Pi、不依赖 Pi 扩展
- ❌ 不依赖 `rex-md://` 协议、不依赖 macOS LaunchServices URL handler
- ❌ 不依赖 ticket 文件（`~/Library/Application Support/Rex Markdown/tickets/*.json`）
- ❌ 不做 Markdown 解析、不改写链接
- ✅ 只是一个命令行入口：**参数 → 拼一条 `rex run` 命令 → 结束**

---

## 二、依赖清单

| 依赖 | 作用 | 本机 | 缺失时 |
| --- | --- | --- | --- |
| `rex` | 开分屏、管焦点、管 label | `/Users/lex/Library/Application Support/com.superlogical.rex/.../rex` | 降级为当前终端全屏渲染 |
| `terminal-browser` | 真正的渲染器 | `/opt/homebrew/bin/terminal-browser` (v0.15.3) | 报错退出 |
| `glow` | `-c` 模式渲染 + fzf 预览 | `/opt/homebrew/bin/glow` | 退回 `bat` / `cat` |
| `fzf` | 目录模糊选择 | `/opt/homebrew/bin/fzf` | 退化为打印文件列表 |
| `bat` | `-c` 模式的源码渲染后备 | `/opt/homebrew/bin/bat` | — |
| `node` | 仅用于把路径安全转成 `file://` URL | `/opt/homebrew/bin/node` | 必需 |
| `bash` | 脚本本体 | 系统 | 必需 |

环境变量依赖：`REX_SESSION`、`REX_BLOCK`（Rex 启动子进程时注入，用来定位「发起调用的那个 pane」）。缺失 → 走降级分支。

---

## 三、四种模式

| 命令 | 走哪条路 | 是否开分屏 | 是否抢焦点 |
| --- | --- | --- | --- |
| `mdview FILE.md` | `open_pane` | ✅ Rex 右侧窗格 | ❌ 不抢 |
| `mdview DIR/` | `browse_dir`（fzf）→ 选中后 `open_pane` | ✅（选中后） | ❌ |
| `mdview -c FILE.md` | `open_inline`（glow） | ❌ 当前 pane 直接渲染 | — （本来就是前台） |
| `mdview -l DIR/` | `list_md`（find） | ❌ 只打印路径 | — |
| `mdview --pane FILE.md` | `open_pane`（fzf 内部调用时的内部入口） | ✅ | ❌ |

---

## 四、`mdview FILE.md` 完整执行流程（逐段拆解）

### 4.1 路径规范化

```bash
file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
```

- 把相对路径变成**绝对路径**；
- 顺带解决了文件名带空格的问题（后面拼 URL 要用）；
- 之前先用 `[ -f "$file" ]` 判存在，避免对着目录跑。

### 4.2 找渲染器

```bash
browser_bin() {
  if command -v terminal-browser >/dev/null 2>&1; then command -v terminal-browser; return 0; fi
  # 退路：读 Rex Markdown 安装器写的 programs.json
  node -e '...JSON.parse(...).browser...' "$HOME/Library/Application Support/Rex Markdown/programs.json"
}
```

先用 PATH；PATH 里没有就从 `programs.json` 读（那是 `install.mjs` 记录的绝对路径）。

### 4.3 生成 URL

```bash
file_url() {
  node -e 'const {pathToFileURL}=require("url");
            console.log("terminal-browser-file://file"+pathToFileURL(process.argv[1]).pathname)' "$1"
}
```

- `pathToFileURL` 会做 **percent-encoding**（空格 → `%20`），所以带空格/中文的文件名不会破；
- 拼出来长这样：`terminal-browser-file://file/Users/lex/git/knowledge/macos/terminal/Rex/README.md`
  （注意是 `//file` + 绝对路径，这是 terminal-browser 的自定义 scheme，不是标准 `file://`）。

### 4.4 隔离浏览器环境（8 个变量）

```bash
HOME=$HOME/.local/state/rex-markdown-browser/home
TERMINAL_BROWSER_NO_TELEMETRY=1
TERMINAL_BROWSER_PRESENT=animation
TERMINAL_BROWSER_APPDATA=$HOME/.local/state/rex-markdown-browser/profiles
TERMINAL_BROWSER_CONFIG_DIR=$HOME/.local/state/rex-markdown-browser/config
XDG_DATA_HOME=.../data
XDG_STATE_HOME=.../state
XDG_CACHE_HOME=.../cache
XDG_RUNTIME_DIR=.../run
```

| 变量 | 作用 |
| --- | --- |
| `HOME` | 把浏览器主目录挪走，**不会读你的 shell/zsh 配置，也不会碰个人浏览器 profile** |
| `TERMINAL_BROWSER_APPDATA` | 浏览器 profile（cookie / 缓存 / 登录态）隔离目录 |
| `TERMINAL_BROWSER_CONFIG_DIR` / `XDG_CONFIG_HOME` | 配置文件隔离 |
| `XDG_DATA_HOME` / `XDG_STATE_HOME` / `XDG_CACHE_HOME` / `XDG_RUNTIME_DIR` | 数据 / 状态 / 缓存 / 运行时目录隔离（daemon 的 socket 也在这） |
| `TERMINAL_BROWSER_NO_TELEMETRY=1` | 关闭使用统计 / 崩溃上报 |
| `TERMINAL_BROWSER_PRESENT=animation` | 让它以「动画渲染」模式呈现（配合 Kitty 图形协议） |

> 这套环境和 Pi 里的 Rex Markdown 预览**完全一致** → 两者共用同一个浏览器 daemon，不会起两份实例。

### 4.5 拼 `rex run` 命令

```bash
local args=(run --session "$REX_SESSION")
[ -n "${REX_BLOCK:-}" ] && args+=(--block "$REX_BLOCK")
args+=(--split right --ratio 45 --focus=false --shell=none --cwd "$dir" --label "MD" --json --)

rex "${args[@]}" /usr/bin/env "${env_pairs[@]}" "$browser" open --no-merge "$url"
```

每个参数的作用：

| 参数 | 作用 |
| --- | --- |
| `run` | 在**新 block**（终端窗格）里跑命令 |
| `--session "$REX_SESSION"` | 定位到当前 Rex 会话（不传就落到默认会话） |
| `--block "$REX_BLOCK"` | **锚点**：新窗格相对哪个 block 摆放（= 你当前所在的 pane） |
| `--split right` | 在锚点**右侧**开窗格 |
| `--ratio 45` | 新窗格占 45% 宽度（左边保留 55% 给原 pane） |
| `--focus=false` | ⭐ **建好但不切焦点**：你还在原来的 pane 里打字，文档在旁边更新 |
| `--shell=none` | 直接执行命令，**不经过 shell** → 文件名里的空格 / 引号 / `$` 不会被解释，也不会有注入风险 |
| `--cwd "$dir"` | 新窗格的工作目录 = 文档所在目录 |
| `--label "MD"` | 窗格标签，Rex 里一眼能认出 |
| `--json` | 让 rex 输出创建结果 JSON（便于脚本/验证） |
| `--` | 后面的全部是 COMMAND，不给 rex 解析 |

`/usr/bin/env "${env_pairs[@]}"` 是**故意**的：环境变量用 `env` 注入到子进程，避免 bash 的 `VAR=val cmd` 形式在 `--shell=none` 下被当成参数。

`terminal-browser open --no-merge "$url"`：
- `--no-merge` = 不要把自己挂到**邻近 pane 里已经开着的 terminal-browser** 上，当成新标签页；每个预览独立实例。

### 4.6 实际执行的完整命令（展开后）

```bash
rex run \
  --session "session:01a18b82-7f29-753f-93c2-b953705ed874" \
  --block   "block:01a1aafe-4831-7027-a937-9ea1d66b262b" \
  --split right --ratio 45 --focus=false --shell=none \
  --cwd "/Users/lex/git/knowledge/macos/terminal/Rex" \
  --label "MD" --json -- \
  /usr/bin/env \
    HOME=/Users/lex/.local/state/rex-markdown-browser/home \
    TERMINAL_BROWSER_NO_TELEMETRY=1 \
    TERMINAL_BROWSER_PRESENT=animation \
    TERMINAL_BROWSER_APPDATA=... TERMINAL_BROWSER_CONFIG_DIR=... \
    XDG_DATA_HOME=... XDG_STATE_HOME=... XDG_CACHE_HOME=... XDG_RUNTIME_DIR=... \
  /opt/homebrew/bin/terminal-browser open --no-merge \
    "terminal-browser-file://file/Users/lex/git/knowledge/macos/terminal/Rex/README.md"
```

### 4.7 返回值

```json
{
  "anchor_id": "block:01a1aafe-4831-7027-a937-9ea1d66b262b",   // 锚点（原 pane）
  "block_ids": ["block:01a1d2b9-6f31-7f2e-a85d-58388d9b0b21"],  // 新建的窗格
  "split_ids": ["split:01a1d2b9-6f46-7509-a86a-49567901bc3e"], // 分屏关系
  "revision": 819                                             // 服务器端布局版本号
}
```

脚本本身**不消费**这个 JSON，只是打印出来（方便你确认「分屏到底建没建」）。

---

## 五、`mdview DIR/`（fzf 目录浏览）流程

1. `find DIR -type f \( -name '*.md' -o -name '*.markdown' \)`，排除 `.git/`、`node_modules/`；
2. 用 `-exec sh -c` 把结果**统一转成绝对路径**（相对路径会依赖调用时的 cwd，容易错）；
3. 灌进 fzf：
   - `--preview 'glow --style=dark --width 120 {}'` → 右侧实时渲染（不是源码）
   - `--preview-window 'right:62%:wrap'` → 长行折行不截断
   - `--bind "enter:execute(bash '$SELF' --pane {1})+abort"` → **Enter = 起一个后台进程去开分屏 + 立刻关掉 fzf**
4. `--pane` 是脚本内部的隐藏入口：fzf 里调 `mdview --pane <file>` → 走 `open_pane`，避免再套一层 fzf。

> fzf 是全屏 TUI，会盖住当前终端；想并排用可以 `rex run --split=right -- fzf ...`。

---

## 六、安全模型

| 点 | 做法 |
| --- | --- |
| 命令注入 | `--shell=none` + 路径全部进 **argv**，从不拼接成 shell 字符串 |
| 文件名含空格/引号/`$` | `pathToFileURL` 做 percent-encoding；`--cwd`/`--label` 走 argv |
| 浏览器污染个人环境 | 8 个环境变量隔离 HOME / profile / config / cache / daemon |
| 数据外传 | `TERMINAL_BROWSER_NO_TELEMETRY=1`；渲染的是本地文件，不联网 |
| 权限 | 脚本以普通用户权限运行，无 setuid、无写系统目录 |

---

## 七、和 Pi 里那套预览的对照

| | Pi 的 Rex Markdown | `mdview` |
| --- | --- | --- |
| 触发 | 消息里的 `.md` 链接被**点击** | 命令行**执行** |
| 依赖 Pi | ✅ | ❌ |
| 依赖 ticket + `rex-md://` + URL handler | ✅ | ❌ |
| Markdown 解析/链接改写 | ✅（`marked` lexer） | ❌（不做解析） |
| 分屏命令 | `rex run --session --block --split right --ratio 45 --focus=false` | **同一条** |
| 渲染器 | terminal-browser | **同一个** |
| 浏览器 profile | `~/.local/state/rex-markdown-browser` | **同一个** |
| 窗口标签 | `Markdown` | `MD` |

> 也就是说：**手动 `mdview` 打开的视图，和 Pi 里点链接打开的视图是同一种东西**。

---

## 八、不装脚本时的手工等价命令

```bash
# 在 Rex 的任意 pane 里手工执行，效果与 mdview FILE.md 一致
rex run --session "$REX_SESSION" --block "$REX_BLOCK" \
  --split right --ratio 45 --focus=false --shell=none \
  --label "MD" -- \
  /usr/bin/env HOME="$HOME/.local/state/rex-markdown-browser/home" \
    TERMINAL_BROWSER_NO_TELEMETRY=1 TERMINAL_BROWSER_PRESENT=animation \
    TERMINAL_BROWSER_APPDATA="$HOME/.local/state/rex-markdown-browser/profiles" \
    TERMINAL_BROWSER_CONFIG_DIR="$HOME/.local/state/rex-markdown-browser/config" \
    XDG_DATA_HOME="$HOME/.local/state/rex-markdown-browser/data" \
    XDG_STATE_HOME="$HOME/.local/state/rex-markdown-browser/state" \
    XDG_CACHE_HOME="$HOME/.local/state/rex-markdown-browser/cache" \
    XDG_RUNTIME_DIR="$HOME/.local/state/rex-markdown-browser/run" \
  terminal-browser open --no-merge \
    "terminal-browser-file://file/Users/lex/git/knowledge/macos/terminal/Rex/README.md"
```

---

## 九、验证与排错

```bash
# 1) 脚本自检
mdview --help
bash -n mdview          # 语法检查

# 2) 开分屏，看返回 JSON
mdview /Users/lex/git/knowledge/macos/terminal/Rex/README.md

# 3) 确认新窗格在跑 terminal-browser
rex block inspect block:<新 block_id> --session "$REX_SESSION" --json | head -12
ps aux | grep "[t]erminal-browser" | head

# 4) 确认隔离目录被用起来了
ls -la ~/.local/state/rex-markdown-browser/

# 5) 渲染帧率必须是 30（否则滚动会压垮 Rex）
env HOME=~/.local/state/rex-markdown-browser/home \
    TERMINAL_BROWSER_CONFIG_DIR=~/.local/state/rex-markdown-browser/config \
    terminal-browser config get render.fps
```

| 现象 | 原因 / 处理 |
| --- | --- |
| `mdview: 不在 Rex 终端里，直接在当前终端渲染` | 没有 `REX_SESSION`（在 Terminal.app / iTerm 里跑）→ 降级，全屏预览，`Ctrl+Q` 退出 |
| `mdview: 没找到 terminal-browser` | 装 cask，或重跑 `node ~/.pi/tools/rex-markdown/install.mjs` 刷新 `programs.json` |
| 分屏开了但空白 | 看 `~/Library/Application Support/Rex Markdown/handler.log` 与 `ps aux | grep terminal-browser` |
| 滚动卡顿掉帧 | `render.fps` 必须是 30 |
| 窗格没出现但 JSON 有输出 | 分屏建在**另一个 session**（`--session` 指错了）→ 用 `rex ls` 看会话列表 |
| 焦点被抢走 | 少了 `--focus=false`（或用了 `rex split` 默认行为） |

---

## 十、可以继续扩展的方向

| 想法 | 改动点 |
| --- | --- |
| 预览 `.go/.py` 等源码 | `file_url` 已经支持任意本地文件，只需放开扩展名限制（`terminal-browser` 会按文本/代码渲染） |
| 换个分屏方向 / 宽度 | 改 `args+=(--split right --ratio 45 ...)` 里的 `--split` / `--ratio` |
| 预览 PDF / 图片 | `terminal-browser-file://file/<path>` 已能渲染，`mdview` 传路径即可 |
| 目录摘要模式 | `mdview -l` 出列表 + 每篇 `glow \| head -20` 拼摘要 |
| 走个人浏览器 profile | 删掉 `browser_env_args` 的隔离变量即可（不建议，会污染日常环境） |

---

## 十一、相关文件

| 路径 | 说明 |
| --- | --- |
| `macos/terminal/Rex/mdview` | 脚本本体（git 跟踪） |
| `~/.local/bin/mdview` | 指向脚本本体的软链（PATH 里） |
| `~/.pi/tools/rex-markdown/bridge.mjs` | 上游实现，含 `browserEnvironment()` / `browserArguments()`，mdview 的隔离环境与之对齐 |
| `~/.pi/tools/rex-markdown/open.mjs` | 上游的 ticket dispatcher；mdview **不走**这条路 |
| `~/Library/Application Support/Rex Markdown/programs.json` | 记录 node / rex / terminal-browser 的绝对路径 |
| `~/.local/state/rex-markdown-browser/` | 隔离的浏览器 HOME / profile / config / cache / daemon |
