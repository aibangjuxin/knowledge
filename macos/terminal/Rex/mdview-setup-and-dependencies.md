# mdview 依赖清单与跨机安装指南

> **要解决的问题**：这台 Mac 上的 `mdview` 能跑通，**换一台 macOS 到底要装什么**？
>
> 结论先给：**3 个必需软件 + 1 个必需 App + 3 个可选工具**。必需项装齐就能跑；
> 可选项只影响降级路径，不会报错。
>
> 关联文档：[mdview.md](./mdview.md)（脚本逐段执行流程）· [How-to-view-markdown.md](./How-to-view-markdown.md)（怎么用）· [Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md)（Pi 侧方案）
> 自检脚本：[mdview-doctor](./mdview-doctor)（一条命令核对本机全部依赖）

---

## 〇、一句话结论

```bash
# 必需
brew install node                                   # 路径 → file:// URL
brew install --cask terminal-browser                # 真正的渲染器
# 必需 App：Rex Beta.app（Superlogical）             # mdview FILE.md 的分屏模式

# 可选（缺失只降级）
brew install glow fzf bat

# 装完软链 + 自检
ln -sfn ~/git/knowledge/macos/terminal/Rex/mdview ~/.local/bin/mdview
./mdview-doctor
```

---

## 一、依赖总表

### 1.1 必需项

| 依赖 | 用来干什么 | 装法 | 缺失时的表现 |
| --- | --- | --- | --- |
| **bash ≥ 3.2** | 脚本宿主 | macOS 自带 `/bin/bash` 3.2.57 | 无法运行（脚本兼容 3.2，见 §5.1） |
| **node ≥ 18** | ① `pathToFileURL` 把路径安全转成 `file://` URL ② 读 `programs.json` | `brew install node` | **静默失败**：URL 变空串，渲染器打不开文件 |
| **terminal-browser ≥ 0.15** | 真正的 Markdown 渲染器（Chromium 引擎 + kitty 图形协议） | `brew install --cask terminal-browser` | 报 `mdview: 没找到 terminal-browser` 并退出 |
| **Rex（CLI + server）** | `mdview FILE.md` 在右侧开分屏 | 装 [Rex Beta.app](https://superlogical.com/)（Superlogical 官方） | 降级为「当前终端全屏渲染」，并打印明确提示 |

> `node` 是**最容易踩坑**的一项：它不参与渲染，只在两处做「路径 → URL」和「读 JSON」，
> 但没有它整个脚本会安静地坏掉。

### 1.2 可选项（缺失只降级，不报错）

| 依赖 | 作用 | 缺失时的降级行为 | 装法 |
| --- | --- | --- | --- |
| **glow** 3.x | `mdview -c` 排版渲染；fzf 右侧实时预览 | `-c` 退回 `bat`；预览退回 `cat`（看源码） | `brew install glow` |
| **bat** | `mdview -c` 的后备渲染器 | 没有 glow 也没有 bat → `-c` 直接失败 | `brew install bat` |
| **fzf** | 目录模糊选择 | `mdview DIR/` 退化为「打印文件列表」 | `brew install fzf` |

### 1.3 宿主环境要求（不是软件包，但决定能不能真跑通）

| 要求 | 说明 | 不满足的后果 |
| --- | --- | --- |
| **终端支持 kitty graphics 协议** | terminal-browser 用它把 Chromium 画面画进终端 | 报 `Unsupported terminal: this terminal cannot display graphics` |
| **在 Rex 里跑时，Rex server 在跑** | `rex server status` 能返回 pid | `rex run` 失败，mdview 打印「rex 开分屏失败」 |
| **macOS** | 脚本用了 `~/Library/Application Support` 等 macOS 专属路径 | Linux 上路径全错 |

---

## 二、终端要求：kitty graphics 协议

terminal-browser 不是文本浏览器，它把 **Chromium 的真实像素**用 [kitty 图形协议](https://sw.kovidgoyal.net/kitty/graphics-protocol/)画进终端格子里。
所以**终端本身必须实现这个协议**，否则什么都看不到。

| 终端 | 支持情况 |
| --- | --- |
| **Ghostty**（Rex 内嵌的就是它） | ✅ 原生支持，terminal-browser 官方首推 |
| **Kitty** | ✅ 原生支持（kitty 图形协议的发明者） |
| **WezTerm** / **cmux** / **Herdr** / **tmux** | ✅ terminal-browser 官方 FAQ 明确点名 |
| **iTerm2** | ⚠️ iTerm2 自身支持 kitty 图形协议的**子集**（terminfo.dev 记录 3.6.9 起支持），但 terminal-browser 的官方 FAQ 未点名 → 以实际渲染为准 |
| **VS Code 集成终端** | ⚠️ 版本相关：部分资料列为支持，终端能力库标为不支持 → 以实际渲染为准 |
| **Terminal.app**（macOS 自带） | ❌ **官方 FAQ 明确不支持** → 只会看到 `Unsupported terminal` |
| **Alacritty** | ❌ 不支持 kitty 图形协议 |

> **判断方法**（比查表更可靠）：在目标终端里直接跑一次
> ```bash
> terminal-browser open "terminal-browser-file://file$HOME/任意.md"
> ```
> 出现 `Unsupported terminal: this terminal cannot display graphics` 就是不支持；
> 出现画面就是支持。terminal-browser 自己的报错信息最准。
>
> **好消息**：在 **Rex 窗格内**永远是安全的 —— Rex 服务端链接了 `libghostty`，本身就说 kitty 图形协议
> （验证过程见 [Rex-Kitty-Graphics.md](./Rex-Kitty-Graphics.md)）。
> 只有「不在 Rex 里、直接在 Terminal.app / iTerm2 里跑 `mdview` 的降级分支」才会踩这个坑。

---

## 三、`rex` 的解析逻辑（这里本机踩过坑，已修）

Rex Beta.app 把 CLI 装在：

```
~/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex
```

这个路径**默认不在 PATH 里**。本机实测 `command -v rex` → 空。

> ### ⚠️ 已修复的缺陷
>
> 旧版 `mdview` 判断「要不要走分屏模式」用的是 `command -v rex`：
>
> ```bash
> if [ -z "${REX_SESSION:-}" ] || ! command -v rex >/dev/null 2>&1; then
>   # 降级成当前终端全屏渲染
> ```
>
> 结果：**即使人在 Rex 里，也永远走不到分屏分支**，只会静默降级成全屏渲染，
> 而提示语还写着「不在 Rex 终端里」，极具误导性。
>
> 新版改成**两级解析**（和上游 Pi 扩展 `programs.json` 的做法一致）：
>
> ```bash
> rex_bin() {
>   if type -P rex >/dev/null 2>&1; then type -P rex; return 0; fi   # ① PATH
>   programs_json_get rex                                          # ② programs.json
> }
> ```
>
> `programs.json` 由 Pi 的 Rex Markdown 安装器写入：
> `~/Library/Application Support/Rex Markdown/programs.json`
>
> ```json
> {"rex":"/Users/lex/Library/Application Support/com.superlogical.rex/.../rex",
>  "browser":"/opt/homebrew/bin/terminal-browser"}
> ```
>
> **修复后实测**：在本机（`rex` 不在 PATH）执行 `mdview --pane README.md`，
> Rex 成功建出 `label=MD` 的右侧分屏，返回 `block_ids: ["block:01a1e819-..."]`。
>
> → 新机器上**要么**把 `rex` 放进 PATH，**要么**装 Pi 的 `rex-markdown` 扩展生成 `programs.json`。
> 两种都没有时，mdview 会明确提示「找不到 rex CLI，无法开分屏」而不是假装成功。

> 用的是 `type -P` 而不是 `command -v`：前者只查 PATH 里的可执行文件，
> 不会误命中同名 shell 函数/别名；`command -v -p` 更不行 —— 它会漏掉 `/opt/homebrew/bin` 下的可执行文件。

---

## 四、完整依赖清单（按安装顺序）

| # | 依赖 | 类型 | 装法 | 验证命令 |
| --- | --- | --- | --- | --- |
| 1 | Homebrew | 前置 | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` | `brew --version` |
| 2 | **node** | 必需 | `brew install node` | `node -v` |
| 3 | **terminal-browser** | 必需 | `brew install --cask terminal-browser` | `terminal-browser --version` |
| 4 | **Rex Beta.app** | 必需（分屏模式） | Superlogical 官网下载安装，启动一次 | `rex server status`（需 `rex` 在 PATH，见 §3） |
| 5 | glow | 可选 | `brew install glow` | `glow --version` |
| 6 | fzf | 可选 | `brew install fzf` | `fzf --version` |
| 7 | bat | 可选 | `brew install bat` | `bat --version` |
| 8 | mdview 脚本 | 本体 | 克隆本仓库 + 软链 | `mdview --help` |
| 9 | Pi 的 rex-markdown（可选） | 可选 | `node ~/dotfiles/tools/rex-markdown/install.mjs` | `cat "$HOME/Library/Application Support/Rex Markdown/programs.json"` |

> **终端浏览器也可以不装 cask**：上游还提供 `curl -fsSL https://terminal-browser.sh/install | bash`。
> 本机用的是 **cask**（`/opt/homebrew/Caskroom/terminal-browser/0.15.3`，347 MB），
> `brew info --cask terminal-browser` 可以核对版本。

---

## 五、在新 Mac 上安装（照着敲）

### 5.1 装 Homebrew + 三个命令行工具

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install node            # 必需
brew install --cask terminal-browser   # 必需
brew install glow fzf bat    # 可选，一起装省事
```

### 5.2 装 Rex

1. 从 <https://superlogical.com/> 下载 **Rex Beta.app**，拖进 `/Applications`；
2. 启动一次，让它把 RexServer 装到
   `~/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/`；
3. 决定 `rex` CLI 怎么暴露 —— 二选一：

```bash
# 方案 A：放进 PATH（推荐，所有终端通用）
mkdir -p ~/.local/bin
ln -sfn "$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex" \
       ~/.local/bin/rex
rex version      # 应打印 rex 0.1.0-preview.xx

# 方案 B：不装 Pi 扩展时，靠 mdview 读 programs.json（见 §3）
#   → 需要先跑一次 Pi 的 rex-markdown install.mjs 生成 programs.json
```

### 5.3 装 mdview 脚本

```bash
git clone git@github.com:aibangjuxin/knowledge.git ~/git/knowledge
chmod +x ~/git/knowledge/macos/terminal/Rex/mdview
mkdir -p ~/.local/bin
ln -sfn ~/git/knowledge/macos/terminal/Rex/mdview ~/.local/bin/mdview
```

> `~/.local/bin` 要在 PATH 里。本机的 `~/.zshrc` / `~/.zprofile` / `~/.bashrc` 都有：
> ```bash
> export PATH="$HOME/.local/bin:$PATH"
> ```

### 5.4 （可选）装 Pi 的 rex-markdown 扩展

只为生成 `programs.json`（记录 node / rex / terminal-browser 的绝对路径），让 mdview 在
`rex` 不在 PATH 时也能开分屏：

```bash
node ~/dotfiles/tools/rex-markdown/install.mjs
```

它还会：创建 `~/Applications/Rex Markdown.app`、注册 `rex-md://` URL scheme、
把隔离 profile 的 `render.fps` 设为 30。

### 5.5 一键自检

```bash
~/git/knowledge/macos/terminal/Rex/mdview-doctor
```

输出示例（本机 2026-11-17 实测）：

```
【2】node —— 必需（路径转 file:// URL、读 programs.json）
  ✅ node v22.22.3 → /Users/lex/.local/bin/node

【3】terminal-browser —— 必需（真正的 Markdown 渲染器）
  ✅ terminal-browser → /opt/homebrew/bin/terminal-browser

【4】rex CLI —— mdview FILE.md 的分屏模式必需
  ✅ rex → /Users/lex/Library/Application Support/com.superlogical.rex/.../rex
  ✅ Rex server 在跑（pid: 972）

【7】隔离 profile（~/.local/state/rex-markdown-browser）
  ✅ render.fps = 30（滚动不压垮 Rex）

通过 12 · 警告 1 · 失败 0
结论：✅ 必需依赖齐了（警告项按需处理）
```

---

## 六、验证清单（逐条手动确认）

```bash
# 1) 脚本能跑
mdview --help

# 2) 目录列举（只依赖 find/sort，零外部依赖）
mdview -l ~/git/knowledge/macos/terminal/Rex

# 3) 当前 pane 渲染（依赖 glow 或 bat）
mdview -c ~/git/knowledge/macos/terminal/Rex/README.md

# 4) 分屏模式（依赖 rex + terminal-browser；在 Rex 窗格里跑）
mdview ~/git/knowledge/macos/terminal/Rex/README.md
# 期望：右侧出现 label=MD 的分屏，并打印 JSON：
# {
#   "anchor_id": "block:01a1aafe-...",
#   "block_ids": ["block:01a1e819-..."],
#   "split_ids": ["split:01a1e819-..."],
#   "revision": 1000
# }

# 5) 确认分屏里跑的是 terminal-browser
ps aux | grep "[t]erminal-browser" | head

# 6) 确认隔离 profile 被用起来了
ls -la ~/.local/state/rex-markdown-browser/

# 7) 渲染帧率必须是 30（否则滚动会压垮 Rex）
env HOME=~/.local/state/rex-markdown-browser/home \
    TERMINAL_BROWSER_CONFIG_DIR=~/.local/state/rex-markdown-browser/config \
    terminal-browser config get render.fps
```

---

## 七、故障排查

| 现象 | 根因 | 处理 |
| --- | --- | --- |
| `mdview: 没找到 terminal-browser` | 没装 cask，且无 `programs.json` | `brew install --cask terminal-browser` |
| `mdview: 找不到 rex CLI，无法开分屏` | 没装 Rex，或 `rex` 不在 PATH 且无 `programs.json` | 见 §3 的方案 A / B |
| `mdview: rex 开分屏失败（服务器在跑吗？）` | Rex server 没起 | 启动 Rex Beta.app，或 `rex server start` |
| `mdview: 不在 Rex 终端里` | 当前终端拿不到 session（Terminal.app / iTerm2 里跑） | 正常降级：当前终端全屏渲染，`Ctrl+Q` 退出。
> Rex 0.1.0-preview.25 起不再注入 `REX_SESSION`，但 `mdview` 会回退到 `rex whoami --json`，在 Rex 里仍能开分屏 |
| `Unsupported terminal: this terminal cannot display graphics` | 当前终端不支持 kitty graphics | 换 Ghostty/Kitty/WezTerm，或直接在 Rex 窗格里跑 |
| 渲染出来是空白 | `terminal-browser` 启动即退 | 看 `~/Library/Application Support/Rex Markdown/handler.log` 和 `ps aux \| grep terminal-browser` |
| 滚动卡顿掉帧 | `render.fps` 不是 30 | `terminal-browser config set render.fps 30`（需带隔离环境变量，见 §6 第 7 条） |
| 分屏开了但不在右边 / 找不到 | `--session` 指错会话 | `rex ls` 看会话列表；`--block` 是锚点（当前 pane） |
| 焦点被抢走 | 少了 `--focus=false` | 脚本已固定带这个参数，别手改 |
| fzf 预览显示源码不是排版 | glow 没装 | `brew install glow` |
| `mdview -c` 报 `bat: command not found` | glow 和 bat 都没装 | `brew install glow bat` |
| 路径含空格 / 中文 | — | 已处理：`pathToFileURL` 做 percent-encoding，路径走 argv 不走 shell 字符串 |

---

## 八、本机基线（2026-11-17 实测）

| 项 | 值 |
| --- | --- |
| macOS | 27.2（Build 26B123）· arm64 |
| Homebrew | 7.0.13（`/opt/homebrew`） |
| bash | PATH 里是 Homebrew 5.3.20；系统 `/bin/bash` 3.2.57 同样兼容 |
| node | v22.22.3（`~/.local/bin/node`；Homebrew 另有 node 26.12.1 但被前者遮蔽） |
| terminal-browser | v0.15.3（cask，`/opt/homebrew/bin/terminal-browser`） |
| rex | 0.1.0-preview.18（commit `baf79e0`，api revision 13）；Rex Beta.app 0.1.0（build 1973） |
| Rex server | pid 972，socket `~/Library/Application Support/rex/server.sock` |
| glow / fzf / bat | 3.0.0 / 0.74.5 / 0.26.1 |
| 隔离 profile | `~/.local/state/rex-markdown-browser`（home/profiles/config/data/state/cache/run），`render.fps=30` |

### 脚本兼容性说明

`mdview` 只用了 bash 3.2 就有的特性（数组、`[[ ]]`、`case`、`printf`、进程替换），
**没有**用关联数组、`mapfile`、`${var^^}` 等 bash 4+ 语法。
实测 `bash -n` 在 5.3.20 与 3.2.57 上均通过。

---

## 九、相关文件

| 路径 | 说明 |
| --- | --- |
| `macos/terminal/Rex/mdview` | 脚本本体（git 跟踪，单一真相源） |
| `macos/terminal/Rex/mdview-doctor` | 依赖自检脚本（`mdview-doctor` / `mdview-doctor -v`） |
| `~/.local/bin/mdview` | 指向脚本本体的软链（PATH 里） |
| `~/Library/Application Support/Rex Markdown/programs.json` | 记录 node / rex / terminal-browser 的绝对路径 |
| `~/.local/state/rex-markdown-browser/` | 隔离的浏览器 HOME / profile / config / cache / daemon |
| `~/Library/Application Support/rex/server.sock` | Rex server 的 unix socket |
