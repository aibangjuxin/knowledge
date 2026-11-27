# How to view Markdown（在终端里直接 Review Markdown）

> 需求：**不开 Pi**，也能在 Rex 终端里直接读 / 预览 / 批量浏览目录下的 Markdown。
> `cat` 只有源码没有排版；`glow` 有排版但只能单文件；`mdview` 能按目录浏览，并能在 **Rex 右侧开分屏**渲染。
>
> 环境：macOS 27.2 · Rex 0.1.0-preview.18 · glow 3.0.0 · fzf 0.74.5 · bat 0.26.1 · terminal-browser 0.15.3 · node 22.22.3
> 关联文档：[mdview-setup-and-dependencies.md](./mdview-setup-and-dependencies.md)（依赖清单与跨机安装）· [Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md)（Pi 里点 `.md` 链接 → Rex 分屏预览）

---

## 〇、一句话结论

```bash
cat FILE.md      →  glow -p FILE.md      # 单文件，带排版，可分页
目录浏览          →  mdview DIR/          # fzf 列表 + 右侧实时预览
Rex 分屏预览      →  mdview FILE.md       # 右侧开窗渲染，焦点留在当前 pane
```

---

## 一、工具速查

| 场景 | 工具 | 命令 | 本机状态 |
| --- | --- | --- | --- |
| 看**单个**文件，要排版 | **glow** | `glow -p FILE.md` | ✅ 已装 |
| 看单个文件的**源码**（行号+高亮） | **bat** | `bat -l md FILE.md` | ✅ 已装 |
| 浏览**一个目录**下的所有 md | **mdview**（自建） | `mdview DIR/` | ✅ 已装（本文） |
| **Rex 右侧分屏**渲染（Pi 预览同款） | **mdview** | `mdview FILE.md` | ✅ 已装（本文） |
| 完整浏览器（图片 / HTML / 目录树） | terminal-browser | `terminal-browser open terminal-browser-file://file/<abs>` | ✅ 已装 |
| `cat` 手感但带排版 | mdcat | `mdcat FILE.md` | ❌ 未装（`pipx install mdcat`） |
| 交互式 TUI 目录浏览器 | glow 目录模式 | `glow DIR/` | ✅ 已装 |

---

## 二、单文件：glow / bat

glow 是最稳的“终端版 Markdown 阅读器”，把 Markdown 渲染成带样式的文本：

```bash
glow FILE.md              # 直接输出渲染结果
glow -p FILE.md           # 用 less 分页（长文档推荐）
glow -s dark FILE.md      # 暗色主题
glow -w 100 FILE.md       # 指定折行宽度
glow FILE.md | less -R    # 手动接管管道
```

辅助：

```bash
bat -l md FILE.md                  # 看原始 Markdown 源码
glow FILE.md | grep -n '关键词'     # 先渲染再搜中文
```

> `glow` 默认走 TUI（bubbletea），需要真 TTY；管道里用 `glow -s dark` 输出纯 ANSI 更稳。

---

## 三、目录浏览：fzf + glow（零开发成本）

```bash
find . -name '*.md' -not -path '*/.git/*' | \
  fzf --preview 'glow -s dark --width 120 {}' \
      --preview-window 'right:62%:wrap' \
      --border 'rounded' --height '90%'
```

- 左侧模糊搜索文件名，右侧**渲染后**的实时预览；
- `--preview-window 'right:62%:wrap'` 让长行折行而不是被截断；
- fzf 是全屏 TUI 会盖住终端；在 Rex 里可放进分屏：`rex run --split=right -- fzf ...`。

---

## 四、Rex 分屏预览：`mdview`（自建，绕过 Pi）

### 4.1 为什么需要它

Pi 里的 Rex Markdown 扩展只在 **Pi 渲染消息时**才改写链接。想在**任何终端**里直接 Review Markdown，需要一条独立通路。

`mdview` 复用同一套底层机制（`rex run --split` + `terminal-browser` + 隔离浏览器 profile），但**不经过 Pi、不需要 ticket、不需要点链接、不需要 macOS URL handler**：

```
mdview FILE.md
   │
   ├─ 在 Rex 里 → rex run --session $REX_SESSION --block $REX_BLOCK
   │              --split right --ratio 45 --focus=false --label MD --shell=none
   │              → 分屏里跑 terminal-browser open --no-merge terminal-browser-file://file/<abs>
   │                 （复用 ~/.local/state/rex-markdown-browser 隔离 profile，与 Pi 预览同一个 daemon）
   └─ 不在 Rex 里 → 直接在当前终端全屏渲染 terminal-browser（Ctrl+Q 退出）
```

关键点：`--focus=false` —— 新分屏建好但**不抢焦点**，你在左边继续跟 Agent 说话，右边同步显示文档。这正是 Pi 预览体验好的原因。

### 4.2 安装（本机已装）

脚本源文件就放在本目录：[mdview](./mdview)（跟本文一起进 git，方便改和升级）。

```bash
# 1) 仓库里已经有脚本：macos/terminal/Rex/mdview
# 2) 在 PATH 里暴露一个软链（~/.local/bin 已在 PATH 中）
mkdir -p ~/.local/bin
ln -sfn /Users/lex/git/knowledge/macos/terminal/Rex/mdview ~/.local/bin/mdview
chmod +x /Users/lex/git/knowledge/macos/terminal/Rex/mdview

# 3) 验证
mdview --help
```

改脚本直接改仓库里的 `mdview`，软链自动生效（单一真相源）。

> **换一台 Mac 时**：必需依赖是 `node` + `terminal-browser`（cask）+ Rex Beta.app，
> 可选是 `glow` / `fzf` / `bat`。完整清单、安装步骤和排错表见
> **[mdview-setup-and-dependencies.md](./mdview-setup-and-dependencies.md)**；
> 一键自检：`./mdview-doctor`。

### 4.3 用法

```bash
mdview FILE.md          # Rex 右侧开分屏预览（焦点留在当前 pane）
mdview DIR/             # fzf 浏览该目录下所有 .md，右侧 glow 预览，Enter 在分屏里打开
mdview -d DIR/          # 强制目录浏览（同上，DIR 是文件时也能强制走 fzf）
mdview -c FILE.md       # 不开分屏，直接在当前 pane 用 glow 渲染（≈ glow -p）
mdview -l DIR/          # 只列出该目录下所有 .md 路径
mdview --pane FILE.md   # 隐藏入口：fzf 内部调用它来开分屏（等价于 mdview FILE.md）
```

典型场景：**一边跟 Pi 干活，一边 Review 文档**

```bash
mdview ~/git/knowledge/macos/terminal/Rex/
# fzf 里选中 README.md → Enter → 右边开分屏渲染，焦点自动回到你原来的 pane
```

### 4.4 顺手加的 shell 快捷键

```bash
# ~/.zshrc
alias md='mdview'
alias mdl='mdview -l'
```

### 4.5 脚本全文

> 仓库里的实际文件：[mdview](./mdview)（下面是它的内容，方便直接看/复制）

```bash
#!/usr/bin/env bash
# mdview — 在终端里直接看 Markdown
#
#   mdview FILE.md          在 Rex 右侧开一个分屏，用 terminal-browser 渲染（焦点留在当前 pane）
#   mdview DIR|              浏览目录下的所有 .md（fzf + glow 预览，Enter 打开分屏）
#   mdview -c FILE.md       在当前 pane 用 glow 直接渲染（不另开分屏）
#   mdview -l DIR           只列出目录下的 .md（树状）
#
# 必需：bash、node(路径转 file:// URL)、terminal-browser(渲染器)
# 可选：rex(分屏模式)、glow(-c 模式/预览)、bat(-c 后备)、fzf(目录浏览)
# 详见 mdview-setup-and-dependencies.md
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
MD_ROOT="$HOME/.local/state/rex-markdown-browser"
SUPPORT_DIR="$HOME/Library/Application Support/Rex Markdown"

# ── 浏览器可执行文件 ───────────────────────────────────────────────
# 从 Rex Markdown 安装器写的 programs.json 里取绝对路径
programs_json_get() {
  [ -f "$SUPPORT_DIR/programs.json" ] || return 1
  node -e 'try{const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(d[process.argv[2]]||"")}catch(e){}' \
    "$SUPPORT_DIR/programs.json" "$1"
}

browser_bin() {
  # type -P：只查 PATH 里的可执行文件，不会误命中 shell 函数/别名
  if type -P terminal-browser >/dev/null 2>&1; then
    type -P terminal-browser
    return 0
  fi
  programs_json_get browser
}

# rex CLI：先找 PATH，再退到 programs.json 记录的绝对路径
# （Rex Beta.app 把 rex 装在 ~/Library/Application Support/com.superlogical.rex/ 下，
#  默认不在 PATH 里，只靠 command -v rex 会让分屏模式静默降级）
rex_bin() {
  if type -P rex >/dev/null 2>&1; then
    type -P rex
    return 0
  fi
  programs_json_get rex
}

# ── 隔离的浏览器环境（和 Pi 预览用同一套 profile/daemon）────────────
browser_env_args() {
  printf '%s\n' \
    "HOME=$MD_ROOT/home" \
    "TERMINAL_BROWSER_NO_TELEMETRY=1" \
    "TERMINAL_BROWSER_PRESENT=animation" \
    "TERMINAL_BROWSER_APPDATA=$MD_ROOT/profiles" \
    "TERMINAL_BROWSER_CONFIG_DIR=$MD_ROOT/config" \
    "XDG_DATA_HOME=$MD_ROOT/data" \
    "XDG_STATE_HOME=$MD_ROOT/state" \
    "XDG_CACHE_HOME=$MD_ROOT/cache" \
    "XDG_RUNTIME_DIR=$MD_ROOT/run"
}

file_url() {
  node -e 'const {pathToFileURL}=require("url");console.log("terminal-browser-file://file"+pathToFileURL(process.argv[1]).pathname)' "$1"
}

# ── 在 Rex 右侧开分屏渲染 ──────────────────────────────────────────
open_pane() {
  local file="$1"
  [ -f "$file" ] || { echo "mdview: 找不到文件：$file" >&2; return 1; }
  file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
  local browser; browser="$(browser_bin)"
  [ -n "$browser" ] || { echo "mdview: 没找到 terminal-browser" >&2; return 1; }
  local url; url="$(file_url "$file")"
  local dir; dir="$(dirname "$file")"
  local base; base="$(basename "$file")"

  local -a fallback_env=()
  while IFS= read -r kv; do fallback_env+=("$kv"); done < <(browser_env_args)
  fallback_render() {
    exec /usr/bin/env "${fallback_env[@]}" "$browser" open --no-merge "$url"
  }

  local rex_path; rex_path="$(rex_bin)"

  # 不在 Rex 里跑 → 退化成当前终端全屏预览
  if [ -z "${REX_SESSION:-}" ]; then
    echo "mdview: 不在 Rex 终端里，直接在当前终端渲染（Ctrl+Q 退出）" >&2
    fallback_render
  fi

  # 在 Rex 里但找不到 rex CLI → 同样降级，但要说明原因
  if [ -z "$rex_path" ]; then
    echo "mdview: 找不到 rex CLI，无法开分屏（安装 Rex Beta.app，或把 rex 加进 PATH）" >&2
    echo "mdview: 改为在当前终端渲染（Ctrl+Q 退出）" >&2
    fallback_render
  fi

  local -a env_pairs=()
  while IFS= read -r kv; do env_pairs+=("$kv"); done < <(browser_env_args)

  local args=(run --session "$REX_SESSION")
  [ -n "${REX_BLOCK:-}" ] && args+=(--block "$REX_BLOCK")
  args+=(--split right --ratio 45 --focus=false --shell=none --cwd "$dir" --label "MD" --json --)

  if ! "$rex_path" "${args[@]}" /usr/bin/env "${env_pairs[@]}" "$browser" open --no-merge "$url"; then
    echo "mdview: rex 开分屏失败（服务器在跑吗？'rex server status'）" >&2
    return 1
  fi
}

# ── 当前 pane 用 glow 渲染 ─────────────────────────────────────────
open_inline() {
  local file="$1"
  [ -f "$file" ] || { echo "mdview: 找不到文件：$file" >&2; return 1; }
  if type -P glow >/dev/null 2>&1; then
    exec glow --style=dark --pager "$file"
  fi
  exec bat --language=md --style=numbers --color=always --paging=always "$file"
}

# ── 列出目录下的 .md ──────────────────────────────────────────────
list_md() {
  local dir="${1:-.}"
  find "$dir" -type f \( -name '*.md' -o -name '*.markdown' \) \
    -not -path '*/.git/*' -not -path '*/node_modules/*' | sort
}

# ── fzf 浏览目录 ──────────────────────────────────────────────────
browse_dir() {
  local dir="${1:-.}"
  local files
  files="$(find "$dir" -type f \( -name '*.md' -o -name '*.markdown' \) \
            -not -path '*/.git/*' -not -path '*/node_modules/*' -exec sh -c \
            'for f; do case "$f" in /*) echo "$f";; *) echo "$PWD/$f";; esac; done' _ {} + | sort)"
  if [ -z "$files" ]; then echo "mdview: $dir 下没有 .md 文件" >&2; return 1; fi
  if ! type -P fzf >/dev/null 2>&1; then
    printf '%s\n' "$files"
    return 0
  fi
  local preview="glow --style=dark --width 120"
  type -P glow >/dev/null 2>&1 || preview="cat"
  printf '%s\n' "$files" | fzf \
    --preview "$preview {}" \
    --preview-window 'right:62%:wrap' \
    --border 'rounded' --height '90%' \
    --bind "enter:execute(bash '$SELF' --pane {1})+abort,ctrl-o:execute(bash '$SELF' --pane {1})+abort" \
    --header "mdview · Enter 在 Rex 右侧分屏预览 · Esc 退出"
}

# ── 参数解析 ──────────────────────────────────────────────────────
MODE="auto"; TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--cat)   MODE="cat"; shift ;;
    -l|--list)  MODE="list"; shift ;;
    --pane)     MODE="pane"; shift ;;
    -d|--dir)   MODE="browse"; shift ;;
    -h|--help)  awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *)          TARGET="$1"; shift ;;
  esac
done

case "$MODE" in
  cat)  [[ -n "$TARGET" ]] || { echo "用法: mdview -c FILE.md" >&2; exit 1; }
        open_inline "$TARGET" ;;
  list) list_md "${TARGET:-.}" ;;
  pane) [[ -n "$TARGET" ]] || { echo "用法: mdview --pane FILE.md" >&2; exit 1; }
        open_pane "$TARGET" ;;
  browse)
        [[ -n "$TARGET" ]] || TARGET="."
        browse_dir "$TARGET" ;;
  auto)
        if [[ -z "$TARGET" ]]; then TARGET="."
        fi
        if [ -d "$TARGET" ]; then
          browse_dir "$TARGET"
        else
          open_pane "$TARGET"
        fi ;;
esac
```

### 4.6 验证

```bash
# 1) 开分屏（返回 JSON：anchor / block / split）
mdview ~/git/knowledge/macos/terminal/Rex/README.md
# {
#   "anchor_id": "block:01a1aafe-...",
#   "block_ids": ["block:01a1d2b9-..."],
#   "split_ids": ["split:01a1d2b9-..."],
#   "revision": 819
# }

# 2) 确认分屏在跑 terminal-browser
rex block inspect block:<新的 block_id> --session "$REX_SESSION" --json | head -10
ps aux | grep "[t]erminal-browser" | head

# 3) 列出目录里的 md
mdview -l ~/git/knowledge/macos/terminal/Rex
```

分屏里按 `Ctrl+Q` 关闭。

---

## 五、和 Pi 预览的关系

| | Pi 里的 Rex Markdown | mdview |
| --- | --- | --- |
| 触发方式 | Agent 消息里的 `.md` 链接被点 | 命令行直接执行 |
| 依赖 Pi | ✅ | ❌ |
| 依赖 ticket / `rex-md://` 协议 / macOS URL handler | ✅ | ❌（直接调 `rex run`） |
| 渲染器 | terminal-browser | terminal-browser（同一个） |
| 浏览器 profile | `~/.local/state/rex-markdown-browser` | 同一个 |
| 焦点处理 | 不抢 | 不抢（`--focus=false`） |

**手动 `mdview` 打开的视图 = Pi 里点链接的视图**，可以互相印证。

---

## 六、排错

| 现象 | 排查 |
| --- | --- |
| `mdview: 不在 Rex 终端里` | 正常降级：当前终端全屏渲染（Ctrl+Q 退出） |
| `mdview: 找不到 rex CLI，无法开分屏` | `rex` 不在 PATH 且没有 `programs.json` → 见 [mdview-setup-and-dependencies.md](./mdview-setup-and-dependencies.md) §3 |
| `mdview: rex 开分屏失败` | Rex server 没起 → 启动 Rex Beta.app 或 `rex server start` |
| `Unsupported terminal: this terminal cannot display graphics` | 终端不支持 kitty graphics（Terminal.app 不支持）→ 换 Ghostty/Kitty，或直接在 Rex 窗格里跑 |
| 分屏开了但空白 | `tail ~/Library/Application\ Support/"Rex Markdown"/handler.log`；`ps aux | grep terminal-browser` |
| 滚动卡顿 | `render.fps` 必须是 30：`terminal-browser config get render.fps` |
| `mdview: 没找到 terminal-browser` | 重装 cask，或重跑 `node ~/.local/share/rex-markdown/install.mjs` 刷新 `programs.json` |
| fzf 预览空白 | 管道里 glow 需要 ANSI 输出：`glow -s dark --width 120 {}` |
| 链接/相对路径找不到 | `mdview` 内部会把路径转成绝对路径；跨项目直接给绝对路径最稳 |
| 不知道缺什么 | 跑 `./mdview-doctor`（一键列出缺失依赖） |

---

## 七、还能折腾的方向

| 想法 | 做法 |
| --- | --- |
| 预览源码（.go/.py）而不只是 .md | `terminal-browser` 也能渲染代码文件；把 `mdview` 的扩展名白名单放宽即可 |
| 目录树 + 每篇摘要 | `mdview -l` 出列表，再对每篇 `glow \| head -20` 拼摘要 |
| 边写边预览 | nvim + `markdown-preview.nvim` |
| 快捷键 | `alias md='mdview'`、`alias mdl='mdview -l'` |
| 全文检索 | `rg --type md`（ripgrep 原生识别 md 代码块） |
| 导出静态站 | `mdBook` / `pandoc` |

---

## 八、参考

| 内容 | 链接 |
| --- | --- |
| glow | https://github.com/charmbracelet/glow · `brew install glow` |
| fzf | https://github.com/junegunn/fzf |
| bat | https://github.com/sharkdp/bat |
| mdcat | https://github.com/swsnr/mdcat |
| terminal-browser | https://terminal-browser.com |
| Pi 侧方案 | [Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md) |
| 依赖与跨机安装 | [mdview-setup-and-dependencies.md](./mdview-setup-and-dependencies.md) |
| 目录总览 | [README.md](./README.md) |
| 脚本本体 | [mdview](./mdview)（`~/.local/bin/mdview` 是它的软链） |
| 依赖自检 | [mdview-doctor](./mdview-doctor)（`./mdview-doctor`） |
