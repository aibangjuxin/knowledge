# Rex × Kitty 图形协议：在窗格里画图

> 用 [Kitty 图形协议](https://sw.kovidgoyal.net/kitty/graphics-protocol/) 把图片直接画进 Rex 终端窗格。
>
> 典型用途：代理遇到**不能直接复述的词**（构建日志里的脏话、用户粘贴的冒犯性词、注释里的咒骂）时，
> 不复述它，而是**在旁边的 Rex 分屏里画一张消音后的卡片**——原词不进命令行、不进对话记录，
> 用户照样看得到上下文。
>
> 整理日期：2026-11-12 · 环境：macOS 27.2 · Rex 0.1.0-preview.14（api_revision 12）· librsvg 2.63.4 · ImageMagick 7.1.2

---

## 📖 一、它是什么 / 装完能干什么

| 能力 | 说明 |
| --- | --- |
| 窗格直接收图 | Rex 终端内建 Ghostty，原生支持 Kitty 图形协议，`a=T` 传图即显示，不用开浏览器 |
| 一行命令开分屏 | `rex-draw.sh` 在当前窗格右边开分屏、画图、原地等待，不用手动拼 `rex split` |
| 消音词卡 | `word-card.sh` 生成一张深色卡片：标签 + 消音后的词 + 上下文说明（语气 / 出处） |
| 原词不落盘 | 调用方先把词消音好再传参，原词既不进 shell 历史也不进对话记录 |
| 零额外常驻进程 | 全是 `printf` 出来的转义序列，脚本跑完就退出；分屏里只有一条 `sleep` 循环等用户关 |
| 通用 | 同一套工具画任何 PNG：架构图、报错截图、把文本渲染成图 |

---

## 🧩 二、探索结论：Rex 到底支不支持 Kitty 图形协议

结论：**支持**，而且是 Ghostty 原生级别的支持。三条证据：

### 证据 1：Rex 二进制里带着 Ghostty 的图形实现

Rex 服务端是 Go 写的，但终端渲染层链接了 `libghostty`：

```bash
REX="/Users/lex/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"
strings "$REX" | grep -iE "kitty|graphics" | grep -iE "protocol|placement|image"
# kitty graphics protocol error: ...
# failed to create pin for Kitty graphics
# *libghostty.KittyGraphics
# *libghostty.KittyGraphicsPlacementData
```

客户端 `Rex Beta.app` 里同样有 `libghostty.KittyGraphics*` 符号和
`kitty color protocol` / `kitty clipboard` 等一整套 Kitty 扩展。

### 证据 2：协议握手有回复（最硬的证据）

Kitty 图形协议支持 `a=q` 查询动作：终端会往 tty 输入里回一条
`ESC_Gi=<id>;OK` 或 `ESC_Gi=<id>;<错误>`。写个探针脚本丢进 Rex 窗格里：

```bash
cat > /tmp/probe.sh <<'EOF'
#!/usr/bin/env bash
magick -size 8x8 xc:red /tmp/tiny.png
b64=$(base64 < /tmp/tiny.png | tr -d '\n')
printf '\033_Ga=q,i=42,f=100,t=d;%s\033\\' "$b64"
EOF
chmod +x /tmp/probe.sh

rex split -s "$REX_SESSION" -b "$REX_BLOCK" --split=below --label probe -- \
  sh -c '/tmp/probe.sh; sleep 60'
```

再读窗格：

```bash
rex capture -s "$REX_SESSION" -b <probe_block> --trim --format=vt | cat -v
# ^[_Gi=42;OK^[\^M          ← 终端确认收到并成功解码了 PNG
```

回复 `OK` 说明：**Rex 认得 APC 图形转义序列，并且成功解码了这张 PNG**。

### 证据 3：正常传图时服务端日志干净

Rex 服务端日志路径在 `rex whoami --json` 的 `log_path` 字段里。传图成功后：

```bash
grep -ci "kitty\|graphics" "$(rex whoami --json | jq -r .log_path)"
# 0    ← 没有 graphics 报错
```

---

## 📐 三、协议要点（实测可用）

Kitty 图形协议用 APC 转义序列传图：

```
ESC _ G <控制数据> ; <base64 负载> ESC \
```

| 键 | 含义 | 本方案取值 |
| --- | --- | --- |
| `a` | 动作 | `T` = 传输并显示（`p` = 只放置，`q` = 查询，`d` = 删除） |
| `f` | 格式 | `100` = PNG |
| `t` | 传输方式 | `d` = 负载是 base64 直接数据（`f` = 终端自己读本地文件，`s` = 共享内存） |
| `c` / `r` | 显示尺寸 | 按**单元格**算的列数 / 行数，省略则按像素原始大小 |
| `m` | 分块标记 | 除最后一块外都是 `1`，最后一块 `0` |

分块规则（kitty 官方要求，踩错就白屏）：

- 每块 base64 **不超过 4096 字节**
- **除最后一块外**，每块长度必须是 4 的倍数（base64 对齐）
- 最后一块用 `m=0` 收尾
- 只有第一块带完整控制数据，后续块只带 `m`

本机验证过的完整序列（8×8 红块）：

```
ESC_Ga=q,i=42,f=100,t=d;<base64>ESC\
```

> 密钥顺序：kitty 文档没有强制字母序，实践中 `a,f,t` 打头、`m` 收尾即可。

官方参考：<https://sw.kovidgoyal.net/kitty/graphics-protocol/>

---

## ✅ 四、前置依赖

| 依赖 | 检查命令 | 要求 |
| --- | --- | --- |
| Rex 终端 | `which rex` / `rex whoami --json` | 必需。Rex.app / Rex Beta.app，需支持 Kitty graphics |
| `rsvg-convert` | `rsvg-convert --version` | 可选但推荐，`brew install librsvg`，用于渲染词卡 SVG |
| ImageMagick | `magick --version` | 可选，`brew install imagemagick`，`rsvg-convert` 缺失时兜底，也能生成任意 PNG |
| `jq` | `jq --version` | 可选，`rex-draw.sh` 在拿不到 `$REX_SESSION` / `$REX_BLOCK` 时用来解析 `rex whoami --json` |
| bash 3.2+ | `bash --version` | macOS 自带 bash 即可，脚本没用 bash 4 特性 |

本机检查结果：

```bash
which rex jq rsvg-convert magick
# /Users/lex/Library/Application Support/com.superlogical.rex/.../rex
# /opt/homebrew/bin/jq
# /opt/homebrew/bin/rsvg-convert
# /opt/homebrew/bin/magick

rex whoami --json | jq '{session_id, window_id, block_id, rex_version, log_path}'
# {
#   "session_id": "session:01a18b82-...",
#   "window_id":  "window:01a1aafe-...",
#   "block_id":   "block:01a1aafe-...",
#   "rex_version": "0.1.0-preview.14",
#   "log_path": "/Users/lex/Library/Application Support/rex/servers/a9fca5a9....log"
# }
```

---

## 🛠 五、安装步骤（可复现）

脚本源码在本机仓库：`/Users/lex/git/go/tools/kitty-draw/`

```
tools/kitty-draw/
├── kitty-send.sh    # Kitty 图形协议发图器（零依赖）
├── word-card.sh     # 消音词卡生成器（SVG → PNG）
├── rex-draw.sh      # 在 Rex 右边开分屏并画图
└── README.md        # 简版说明
```

### 步骤 1：装依赖（缺什么装什么）

```bash
brew install librsvg imagemagick jq
```

### 步骤 2：拿到脚本

```bash
git -C /Users/lex/git/go pull
ls -la /Users/lex/git/go/tools/kitty-draw/
```

### 步骤 3：安装到 PATH（可选）

```bash
mkdir -p ~/.local/bin
install -m 0755 /Users/lex/git/go/tools/kitty-draw/*.sh ~/.local/bin/
ls -la ~/.local/bin/kitty-*.sh ~/.local/bin/word-card.sh ~/.local/bin/rex-draw.sh
```

不装也行，直接用绝对路径调用即可（`rex-draw.sh` 会用自身所在目录去找 `kitty-send.sh`，
所以两个脚本要放在一起）。

### 步骤 4：验证协议可用

```bash
# 丢一个探针进 Rex 窗格，应看到 ^[_Gi=42;OK^[
printf '\033_Ga=q,i=42,f=100,t=d;%s\033\\' "$(base64 < /tmp/tiny.png | tr -d '\n')"
```

---

## 🎮 六、使用方式

### 6.1 标准流程：消音词卡

```bash
# 1. 生成卡片（TERM 自己先消音好，原词不进命令行）
./tools/kitty-draw/word-card.sh /tmp/card.png "s**t" "语气: 愤怒 · 出自 build.log:42"

# 2. 在当前窗格右边开分屏，把卡片画进去
./tools/kitty-draw/rex-draw.sh /tmp/card.png "draw" 46
```

`rex-draw.sh` 实际执行的是：

```bash
rex split -s "$REX_SESSION" -b "$REX_BLOCK" --split=right --ratio 40 \
  --label "$label" --focus=false --json -- \
  sh -c "'$here/kitty-send.sh' '$img_abs' '$cols'; while :; do sleep 3600; done"
```

- 分屏标签是 `draw`，宽 40%，**不抢焦点**（`--focus=false`），代理继续留在原窗格。
- 分屏里画完图就 `sleep` 循环，用户看完 `Ctrl+C` 关掉。
- 传的是**绝对路径**：分屏的默认工作目录不一定是仓库根目录。

### 6.2 画任意 PNG

```bash
rsvg-convert -o /tmp/arch.png /tmp/arch.svg     # 架构图
magick screenshot: /tmp/shot.png                # 截图
./tools/kitty-draw/rex-draw.sh /tmp/arch.png "arch" 60
```

### 6.3 只要发图，不要分屏

在已有的 Rex 窗格里直接画：

```bash
./tools/kitty-draw/kitty-send.sh /tmp/card.png 46
```

`kitty-send.sh` 往 stdout 写转义序列，stdout 就是终端。
但**别在自己所在窗格里画**——那会把代理的输入区冲掉。

### 6.4 代理守的规矩

1. **原词不进命令行、不进对话。** 只传消音后的形式（`s**t`、`f***`），原词只留在代理上下文里。
2. **卡片只示意"在说什么"。** 放语气、出处、上下文，不放可以直接复制的原词。
3. **一次一张。** 多张内容合成一张，说明文字写进 `NOTE`。
4. **画完即关。** 不要留一堆空窗格。
5. **别画在自己窗格里。** 用 `rex split` 在旁边开分屏。

---

## 🧪 七、验证

### 7.1 分屏确实开出来了

```bash
rex block ls -s "$REX_SESSION" --json | jq -r '.blocks[] | "\(.label // "-")  \(.block_id)"'
# shell     block:01a1aafe-...
# draw      block:01a1cde7-...      ← 标签是 draw
```

### 7.2 分屏里的进程还活着（在等用户）

```bash
rex block call -s "$REX_SESSION" -b block:01a1cde7-... process | jq '{last_exit, foreground: .foreground.name}'
# { "last_exit": null, "foreground": "bash" }
```

### 7.3 终端认协议

见 §二 证据 2：`rex capture --format=vt` 里应看到 `^[_Gi=42;OK^[\`。

### 7.4 服务端日志无图形报错

```bash
grep -ci "kitty\|graphics" "$(rex whoami --json | jq -r .log_path)"
# 0
```

---

## 🩺 八、故障排查

| 现象 | 原因 / 处理 |
| --- | --- |
| 窗格里什么都没出现 | 终端不支持图形协议。用 §五 步骤 4 的 `a=q` 探针验证，无回复即不支持 |
| 图片只显示一半 / 花屏 | 分块没对齐：每块 ≤4096 且除最后一块外是 4 的倍数，最后一块 `m=0` |
| 图片太大撑爆窗格 | 用 `c=`/`r=` 限制显示列数行数：`kitty-send.sh img.png 46` |
| 窗格立刻退出、图片没了 | 进程跑完就退。分屏里要 `sleep` 循环兜住（`rex-draw.sh` 已经带了） |
| `word-card.sh` 报错找不到渲染器 | 装 `librsvg`（`rsvg-convert`）或 `imagemagick`（`magick`） |
| 中文变成方块 | 字体回退：SVG 里字体族写成 `Menlo, Hiragino Sans GB, PingFang SC, monospace` |
| `rex-draw.sh` 说定位不到会话 | 没在 Rex 里跑，且 `rex whoami --json` 没给出 `session_id`/`block_id`；在 Rex 窗格内跑即可 |
| 服务端日志里 `kitty graphics protocol error` | 负载或控制数据不合法，对照 §三 的表逐项核 |

---

## 🔗 九、参考链接

- Kitty 图形协议官方文档：<https://sw.kovidgoyal.net/kitty/graphics-protocol/>
- Rex 官方文档：<https://www.superlogical.com/rex/docs>
- 本机相关笔记：[Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md)（同一套 Rex + Kitty graphics 生态的另一个用法）
- 脚本源码：`/Users/lex/git/go/tools/kitty-draw/`，仓库 README 里有配套说明

---

## 📝 十、附录：本次实测用到的命令流水

```bash
# 环境探查
rex whoami --json
rex __internal skill                    # 内置的 CLI 使用指南（比 --help 详细）
rex api list                            # 服务端 API 列表
strings "$REX_BIN" | grep -i kitty      # 二进制里确认 Ghostty 图形实现

# 协议探测
magick -size 8x8 xc:red /tmp/tiny.png
printf '\033_Ga=q,i=42,f=100,t=d;%s\033\\' "$(base64 < /tmp/tiny.png | tr -d '\n')"
rex split ... -- sh -c '/tmp/probe.sh; sleep 60'
rex capture -s "$REX_SESSION" -b <block> --trim --format=vt | cat -v   # → ^[_Gi=42;OK^[

# 生成并发送卡片
./tools/kitty-draw/word-card.sh /tmp/card.png "s**t" "语气: 愤怒 · 出自 build.log:42"
./tools/kitty-draw/rex-draw.sh /tmp/card.png "draw" 46

# 事后确认
rex block ls -s "$REX_SESSION" --json | jq -r '.blocks[].label'
rex block call -s "$REX_SESSION" -b <block> process
grep -ci "kitty\|graphics" "$(rex whoami --json | jq -r .log_path)"
```
