# Rex Markdown for Pi

> 在 Pi（终端里的编码 Agent）里点击本地 Markdown 链接，自动在 Rex 终端当前 pane **右侧开一个分屏**，用 terminal-browser 渲染出带样式的预览，Pi 保持焦点不被抢走。
>
> 安装日期：2026-11-12 · 环境：macOS 27.2 · Pi 1.5.2 · Rex 0.0.1793981048-g01d6c4 · Node v26.12.1
>
> **2026-11-12 追加**：[第十四节](#十四-让-agent-稳定输出可点链接2026-11-12-补充) —— 「Agent 输出的 .md 一个都点不开」的排查与三层自动化改造（system prompt 规则 + 技能 + 自检工具）。
>
> **延伸**：不想在 Pi 里看文档、想直接在终端里 Review Markdown（glow / fzf / Rex 分屏预览） → [How-to-view-markdown.md](./How-to-view-markdown.md)。

---

## 📖 一、它是什么 / 装完能干什么

| 能力 | 说明 |
| --- | --- |
| 点击 `.md` 链接开预览 | Pi 消息里出现 `[设计文档](./docs/design.md)` 这类链接时，点击 → Rex 右侧自动开分屏渲染 Markdown |
| 焦点不抢 | 预览在旁边的 pane，Pi 保持前台，可以边看边继续对话 |
| 关闭 | 预览 pane 里按 `Ctrl+Q` |
| 链接不变形 | 只改**显示层**，不改写存进会话的消息、不影响模型上下文；网页链接行为不变 |
| 支持的路径 | 项目相对路径、绝对路径、`~/` 开头、本地 `file:` URL |
| 不误伤 | 代码块、图片、缺失文件、远程 `file:` URL、网页链接都不会被改写 |
| 安全 | 链接里是随机 256-bit ticket，不是可执行命令；参数不经 shell |
| 无常驻进程 | 没有外部浏览器窗口、没有 HTTP server、没有常驻 bridge，用完即退 |

来源：被收录在 [beejmaxx/awesome-rex](https://github.com/beejmaxx/awesome-rex) 的 *Previews and media* 分类里，指向 [jal-co/jalco-dotfiles/tree/main/tools/rex-markdown](https://github.com/jal-co/jalco-dotfiles/tree/main/tools/rex-markdown)。

---

## 🧩 二、工作原理（架构）

```
Pi 扩展 rex-markdown.ts
   │  pi.registerMarkdownTransformer()
   │  把消息里的本地 .md 链接 → rex-md://open/<64位ticket>
   ▼
macOS LaunchServices 捕获 rex-md: 协议
   ▼
~/Applications/Rex Markdown.app   (Swift, LSUIElement 后台 App)
   │  Process 启动 node open.mjs <url>
   ▼
open.mjs
   │  1) 读 ticket 文件 → 取出目标 .md 绝对路径 + session/block/server
   │  2) 校验 ticket（格式、session/block 合法、server 必须是 unix://、文件必须存在）
   │  3) 先 rex block inspect 确认目标 pane 还在
   │  4) 调 rex run --session --block --split right --ratio 45 --focus=false --shell=none
   ▼
Rex 在当前 pane 右侧创建分屏（label = "Markdown"）
   ▼
分屏里运行 terminal-browser open terminal-browser-file://file/<path>
   │  用 terminal-browser 内置的 Markdown 渲染器 + Kitty graphics
   └ 独立 HOME / profile / config / cache / daemon：~/.local/state/rex-markdown-browser
```

关键点：

- **bridge.mjs** 是核心库（路径解析、链接改写、ticket 存取、browser 参数拼装），Pi 扩展和 Node 端 dispatcher 共用。
- **ticket** 是一次性的：内容是 `{session, block, server, path}`，写在 `~/Library/Application Support/Rex Markdown/tickets/<token>.json`（0600）。Pi 关闭/重载时删除，旧终端回滚屏幕里的链接会失效。
- **不经过 shell**：文件名作为 argv 直接传给 `rex` 和 `terminal-browser`，防注入。

---

## ✅ 三、前置依赖

| 依赖 | 检查命令 | 要求 |
| --- | --- | --- |
| macOS | `sw_vers` | 必需（Swift App + LaunchServices） |
| Rex 本地终端 | `which rex` / `rex whoami --json` | 必需，且支持 Kitty graphics；**仅支持本地 Rex，远程 server 不行** |
| Pi | `pi --version` | 必须 ≥ 支持 `registerMarkdownTransformer` 的版本（本机 1.5.2 ✓） |
| Node.js | `node -v` | 必需（installer 和 dispatcher 都是 Node 脚本） |
| Xcode CLT | `xcode-select -p` | 必需（`swiftc` 编译 Handler.swift、`codesign` 签名） |
| terminal-browser | `brew list --cask terminal-browser` | 必需，渲染 Markdown 的终端浏览器 |

本机检查结果：

```bash
which brew node swiftc rex terminal-browser
# /opt/homebrew/bin/brew
# /opt/homebrew/bin/node
# /usr/bin/swiftc
# /Users/lex/Library/Application Support/com.superlogical.rex/.../rex
# /opt/homebrew/bin/terminal-browser   ← 装完之后才有

xcode-select -p
# /Applications/Xcode-beta.app/Contents/Developer
```

---

## 🛠 四、完整安装步骤（可复现）

### 步骤 0：前置检查

```bash
sw_vers
which node swiftc rex
rex whoami --json | head -20     # 确认 session_id / block_id / endpoint 都在
xcode-select -p
```

> 在 Rex 里跑 Pi 时，进程环境里会有 `REX_SESSION` / `REX_BLOCK`，扩展靠它们定位"发起点击的那个 pane"。不在 Rex 里跑 Pi 时扩展会自动跳过（不报错）。

### 步骤 1：装 terminal-browser

```bash
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --cask terminal-browser
# → Linking Binary 'terminal-browser' to '/opt/homebrew/bin/terminal-browser'
```

### 步骤 2：下载源码

上游假设目录是 `~/dotfiles/tools/rex-markdown/`，本机改成 `~/.pi/tools/rex-markdown/`：

```bash
mkdir -p ~/.pi/tools/rex-markdown
cd ~/.pi/tools/rex-markdown
for f in Handler.swift README.md bridge.mjs bridge.test.mjs install.mjs open.mjs; do
  curl -sSL -o "$f" \
    "https://raw.githubusercontent.com/jal-co/jalco-dotfiles/main/tools/rex-markdown/$f"
done
ls -la
```

文件职责：

| 文件 | 作用 |
| --- | --- |
| `bridge.mjs` | 核心库：路径解析 / 链接改写 / ticket / browser 环境变量与参数 |
| `open.mjs` | dispatcher：校验 ticket → 调 Rex 建分屏 → 在分屏里跑 terminal-browser |
| `install.mjs` | 安装器：编译 Swift handler、打包 .app、注册 `rex-md:` 协议、写 programs.json |
| `Handler.swift` | macOS URL handler（LSUIElement 后台 App） |
| `bridge.test.mjs` | 测试套件（13 个用例） |

### 步骤 3：安装 Pi 扩展

上游把扩展放在 `~/dotfiles/pi/agent/extensions/rex-markdown.ts`，通过 `~/.pi/agent/extensions` 软链暴露。
本机 `~/.pi/agent/extensions` 是**真实目录**（已有 4 个扩展），所以直接放进去，并改两处路径：

```bash
curl -sSL -o ~/.pi/agent/extensions/rex-markdown.ts \
  https://raw.githubusercontent.com/jal-co/jalco-dotfiles/main/pi/agent/extensions/rex-markdown.ts
```

**改动点 1** —— bridge.mjs 的相对导入（上游 `../../../tools/...` 是从 `~/dotfiles/pi/agent/extensions/` 数起的）：

```diff
-  const { createTickets, resolveMarkdownPath, rewriteMarkdown } = await import(new URL("../../../tools/rex-markdown/bridge.mjs", source).href);
+  const { createTickets, resolveMarkdownPath, rewriteMarkdown } = await import(new URL("../../tools/rex-markdown/bridge.mjs", source).href);
```

**改动点 2** —— 未安装 handler 时的提示路径：

```diff
-      ctx.ui.notify("Rex Markdown needs its URL handler installed from ~/dotfiles/tools/rex-markdown/install.mjs", "warning");
+      ctx.ui.notify("Rex Markdown needs its URL handler installed from ~/.pi/tools/rex-markdown/install.mjs", "warning");
```

**改动点 3** —— 让 Pi 运行时能解析 `marked`：

扩展顶部用 `createRequire(import.meta.resolve("@earendil-works/pi-tui"))` 拿 `marked` 的 lexer。
Pi 用 jiti 加载扩展并给 `import.meta.resolve` 注入 alias，所以**在 Pi 里能正常解析**；但在普通 Node 里跑测试时解析不到，需要软链兜底：

```bash
mkdir -p ~/.pi/node_modules/@earendil-works
ln -sfn /Users/lex/.local/lib/node_modules/@earendil-works/pi-coding-agent \
  ~/.pi/node_modules/@earendil-works/pi-coding-agent
ln -sfn /Users/lex/.local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui \
  ~/.pi/node_modules/@earendil-works/pi-tui
```

### 步骤 4：跑安装器

```bash
node ~/.pi/tools/rex-markdown/install.mjs
```

它会：

1. `mkdir ~/Applications/Rex Markdown.app/Contents/MacOS`
2. 建 ticket 目录 `~/Library/Application Support/Rex Markdown/tickets`（0700）
3. 建隔离浏览器目录 `~/.local/state/rex-markdown-browser/*`（0700）
4. `terminal-browser config set render.fps 30`（**必须 30**，默认帧率会在滚动时以 ~100fps 压垮 Rex）
5. 写 `~/Library/Application Support/Rex Markdown/programs.json`（记录 node / rex / terminal-browser 的绝对路径，0600）
6. 生成 `Info.plist`（`CFBundleURLSchemes = [rex-md]`、`LSUIElement = true`）
7. `swiftc Handler.swift -o .../RexMarkdown` 编译
8. `codesign --force --sign - "Rex Markdown.app"`（ad-hoc 签名）
9. `lsregister -f` + `LSSetDefaultHandlerForURLScheme("rex-md")` 注册协议

输出：

```
Installed /Users/lex/Applications/Rex Markdown.app
Reload Pi with /reload to enable Markdown clicks.
```

### 步骤 5：适配测试文件（可选但推荐）

`bridge.test.mjs` 里有两处硬编码上游路径，改掉才能在本机跑：

```diff
-const require = createRequire(new URL("../../pi/agent/extensions/rex-markdown.ts", import.meta.url));
+const require = createRequire(new URL("../../agent/extensions/rex-markdown.ts", import.meta.url));
...
-  const { createJiti } = createRequire(new URL("../../pi/agent/extensions/node_modules/@earendil-works/pi-coding-agent/package.json", import.meta.url))("jiti");
+  const { createJiti } = createRequire(new URL("../../node_modules/@earendil-works/pi-coding-agent/package.json", import.meta.url))("jiti");
```

### 步骤 6：重载 Pi

在每个已开的 Pi 会话里执行：

```
/reload
```

Reload 会重新注册 markdown transformer 并签发新的 ticket。**没 reload 之前链接不会变成可点击的预览链接。**

---

## 🧪 五、验证

### 1. 单元/集成测试

```bash
cd ~/.pi/tools/rex-markdown && node --test bridge.test.mjs
```

结果（13/13 通过）：

```
✔ resolve relative, absolute, escaped, encoded, and file-URL Markdown paths
✔ repair a leading slash only when the absolute target is missing
✔ leave remote, missing, malformed, non-Markdown, and directory targets alone
✔ rewrite inline and reference links while preserving text, titles, and web links
✔ rewrite links in headings, lists, blockquotes, and tables
✔ do not rewrite code, images, HTML blocks, or an unfinished streamed link
✔ preserve multiline quote and list prefixes without rewriting their code examples
✔ ticket URLs are opaque, stable per file, private, and revoked on close
✔ reject arbitrary URLs, traversal, unknown tickets, and invalid destinations
✔ pass filenames as literal argv, preserve Pi focus, and do not start a shell
✔ Markdown browsers have a separate profile and daemon with telemetry disabled
✔ dispatcher rejects an unregistered URL before invoking Rex
✔ Pi rewrites presentation only and revokes tickets at session shutdown
ℹ tests 13  ℹ pass 13  ℹ fail 0
```

### 2. 协议调度是否注册成功

```bash
open "rex-md://open/$(printf '0%.0s' {1..64})"
sleep 3
cat ~/Library/Application\ Support/"Rex Markdown"/handler.log
# Rex Markdown: ENOENT: ... tickets/000...0.json   ← 说明 macOS 成功路由到了 handler
```

也可用 LaunchServices 查绑定：

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump \
  | grep -A2 -i "rex-md"
# claimed schemes: rex-md:
# handlerpref id: rex-md (0xf4)
```

### 3. 端到端（会真的开一个分屏）

```bash
mkdir -p /tmp/rexmd
printf '# Rex Markdown 测试\n\n这是一个 [内链](README.md) 和一个 [网页链接](https://example.com)。\n' > /tmp/rexmd/demo.md

node --input-type=module -e '
import { createTickets } from "/Users/lex/.pi/tools/rex-markdown/bridge.mjs";
const t = createTickets({
  session: process.env.REX_SESSION,
  block: process.env.REX_BLOCK,
  server: "unix:///Users/lex/Library/Application%20Support/rex/server.sock",
});
console.log(t.link("/tmp/rexmd/demo.md"));
' > /tmp/rexmd/url.txt

cd ~/.pi/tools/rex-markdown && node open.mjs "$(cat /tmp/rexmd/url.txt)"
```

输出类似：

```json
{
  "anchor_id": "block:01a1b5d5-...",
  "block_ids": ["block:01a1cd74-..."],
  "split_ids": ["split:01a1cd74-..."],
  "revision": 581
}
```

确认分屏和浏览器进程：

```bash
rex block inspect block:<新的 block_id> --session "$REX_SESSION" --json | head -20
# label: "Markdown", flavor: com.superlogical.terminal.shell

ps aux | grep terminal-browser | grep -v grep | head
```

### 4. 检查隔离浏览器配置

```bash
env HOME=~/.local/state/rex-markdown-browser/home \
    TERMINAL_BROWSER_APPDATA=~/.local/state/rex-markdown-browser/profiles \
    TERMINAL_BROWSER_CONFIG_DIR=~/.local/state/rex-markdown-browser/config \
    XDG_CONFIG_HOME=~/.local/state/rex-markdown-browser/config \
    terminal-browser config list | grep -E "render|telemetry"
# render.fps=30
# render.presenter=auto
# telemetry.usage=on        ← 这是终端浏览器自己的默认值；预览实例靠 TERMINAL_BROWSER_NO_TELEMETRY=1 关闭
```

---

## 📦 六、装完之后的文件清单

| 路径 | 说明 |
| --- | --- |
| `~/.pi/tools/rex-markdown/{bridge,open,install}.mjs`、`Handler.swift`、`bridge.test.mjs` | 源码 |
| `~/.pi/agent/extensions/rex-markdown.ts` | Pi 扩展（改过 2 处路径） |
| `~/Applications/Rex Markdown.app` | macOS URL handler（Swift 编译 + ad-hoc 签名） |
| `~/Library/Application Support/Rex Markdown/programs.json` | 记录 node / rex / terminal-browser 路径（0600） |
| `~/Library/Application Support/Rex Markdown/handler.log` | handler 日志 |
| `~/Library/Application Support/Rex Markdown/tickets/*.json` | 一次性 ticket（0600，Pi 关闭时清理） |
| `~/.local/state/rex-markdown-browser/` | terminal-browser 的隔离 HOME / profile / config / cache / daemon |
| `~/.pi/node_modules/@earendil-works/{pi-coding-agent,pi-tui}` | 软链，给测试与 marked 解析兜底 |
| `/opt/homebrew/bin/terminal-browser` | Homebrew cask 安装的渲染器 |
| `~/.pi/agent/APPEND_SYSTEM.md` | **2026-11-12 追加**：把「.md 引用必须写成可点链接」写进 system prompt（见第十四节） |
| `~/.pi/agent/skills/rex-md-links/SKILL.md` | **2026-11-12 追加**：按需加载的详细规则手册 |
| `~/.pi/agent/skills/rex-md-links/check.sh` | **2026-11-12 追加**：路径能不能被改写的自检工具 |

---

## 🎮 七、使用方式

1. 在 Rex 的 Pi 会话里让 Agent 输出 Markdown 链接（例如让它引用 `docs/design.md`）。
2. `/reload` 之后，这条消息里的链接会变成 `rex-md://open/<ticket>` 形式，终端里可点击。
3. 点击 → 右侧开 "Markdown" 分屏 → terminal-browser 渲染出预览。
4. 预览 pane 里 `Ctrl+Q` 关闭。

> 提示：链接改写发生在**渲染层**，所以已经滚过去的旧消息不会被改写，需要重新输出一遍（或 reload 后重新看当前这条）。
>
> 什么样的链接才会被改写、怎么自检 → 见第十节「链接可点性规则与自检」。

---

## 🩺 八、故障排查

| 现象 | 排查 |
| --- | --- |
| 链接不可点击 | 没跑 `/reload`；或 Pi 不在 Rex 里（无 `REX_SESSION`/`REX_BLOCK`）；或 Pi 提示 "Rex Markdown requires a local Rex terminal"（当前是远程 Rex server） |
| **Agent 输出的路径点了没反应** | Agent 把路径写成了行内代码 / 纯文本 / 代码块，而不是 `[文字](路径)` 语法 → 扩展根本没得可改写。**详见第十四节** |
| 提示 handler 未安装 | 跑 `node ~/.pi/tools/rex-markdown/install.mjs` |
| 预览开了但空白/报错 | 看 `~/Library/Application Support/Rex Markdown/handler.log`，以及 Rex 分屏的启动报错；浏览器日志在 `~/.local/state/rex-markdown-browser/state` |
| 滚动预览很卡/掉帧 | `render.fps` 必须是 30；`terminal-browser config get render.fps`（用上面的 env）确认 |
| 点了没反应 | ticket 可能已被清理（Pi reload/shutdown 会删）；重新输出一遍消息 |
| 报 "Invalid Rex Markdown link" / ENOENT ticket | 链接被改写了或 ticket 已失效 |
| `node` / `rex` / `terminal-browser` 路径变了 | 重跑 `node ~/.pi/tools/rex-markdown/install.mjs`（路径写死在 programs.json 和 Info.plist 里） |
| 协议没注册 | 重跑安装器；它会 `lsregister -f` 并 `LSSetDefaultHandlerForURLScheme` |

---

## 🧹 九、卸载

```bash
# 1. 删 Pi 扩展
rm ~/.pi/agent/extensions/rex-markdown.ts

# 2. 注销协议并删 app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -u "$HOME/Applications/Rex Markdown.app"
rm -rf ~/Applications/"Rex Markdown.app"

# 3. 清数据
rm -rf ~/Library/Application\ Support/"Rex Markdown"
rm -rf ~/.local/state/rex-markdown-browser

# 4. 可选：卸载浏览器与软链
brew uninstall --cask terminal-browser
rm -rf ~/.pi/tools/rex-markdown
rm -rf ~/.pi/node_modules/@earendil-works
```

---

## 🔍 十、链接可点性规则与自检

### 10.1 结论

**不需要做任何额外处理**。只要链接满足下面的条件，Pi 渲染每一条新消息时都会自动把它改写成 `rex-md://open/<ticket>`，终端里直接可点。你要做的只是让 Agent 在消息里写出 `.md` 链接。

> ⚠️ **反过来说**：Agent 如果把路径写成行内代码、纯文本或塞在代码块里，扩展就一个都扫不到 → 一个都不会可点。
> 这一条是实际踩过的坑，完整排查与自动化改造见 **[第十四节](#十四-让-agent-稳定输出可点链接2026-11-12-补充)**。

### 10.2 判定规则（来自 `bridge.mjs` 的 `resolveMarkdownPath()`）

必须**同时**满足 4 条：

| # | 条件 | 说明 |
| --- | --- | --- |
| 1 | 扩展名是 `.md` / `.markdown` | 大小写不敏感；`.txt`、`.pdf`、`.mdx` 都**不行** |
| 2 | 路径能解析成本地路径 | 相对路径 / 绝对路径 / `~/` 开头 / 本地 `file://` URL |
| 3 | **文件真实存在** | 不存在就不改写（不会给死链接） |
| 4 | 不在代码/图片/HTML 里 | 行内代码、代码块、`![](...)` 图片、HTML 块、未写完的流式链接都跳过 |

路径语义：

- **相对路径** → 相对 **Pi 启动时的 cwd**（不是相对你当时所在的子目录）
- **`/xxx` 开头** → 先当绝对路径；绝对路径不存在时，再退化为 `cwd/xxx`（`/.reviews/report.md` → `cwd/.reviews/report.md`）
- **`~/xxx`** → 相对 home 展开
- **`file://` URL** → 只认本机（host 为空或 `localhost`）；远程 `file://remote/...` 忽略
- **网页链接** → 永远不改写，保持普通链接（点了开浏览器）

### 10.3 怎么一眼看出可不可点

在终端里 **Cmd+hover / Ctrl+hover** 链接（或复制链接看目标）：

| 看到的目标 | 含义 |
| --- | --- |
| `rex-md://open/<64位hex>` | ✅ 预览分屏可点 |
| `https://...` / `http://...` | 网页链接，走浏览器 |

### 10.4 自检命令

判断某个路径会不会被改写（在目标项目目录下执行）：

```bash
cd <你的项目目录> && node -e 'import("/Users/lex/.pi/tools/rex-markdown/bridge.mjs").then(m=>{
  for(const p of process.argv.slice(1)) console.log(p.padEnd(45), "→", m.resolveMarkdownPath(p, process.cwd()) ?? "不改写")
})' "REX-MARKDOWN-DEMO.md" "./nope.md" "/abs/path.md" "https://a.com/b.md"
```

实测输出：

```
REX-MARKDOWN-DEMO.md                   → /Users/lex/git/go/REX-MARKDOWN-DEMO.md
./nope.md                              → 不改写
docs/x.md                              → 不改写
~/x.md                                 → 不改写
https://a.com/b.md                    → 不改写
/Users/lex/git/go/REX-MARKDOWN-DEMO.md → /Users/lex/git/go/REX-MARKDOWN-DEMO.md
```

### 10.5 跨项目：优先用绝对路径或 file:// URL

相对路径绑定在 Pi 的 cwd 上，跨项目时最稳的是**绝对路径**或 **`file://` URL**：

```
[设计文档](file:///Users/lex/git/knowledge/macos/terminal/Rex/Rex-Markdown-for-pi.md)
```

这样不管在哪个 cwd 下跑 Pi，只要文件存在就一定可点。

### 10.6 🧪 随时可用的测试口子

本机留了一个演示文件专门用来验证：

```
/Users/lex/git/go/REX-MARKDOWN-DEMO.md
```

在 Pi 里随便让 Agent 输出下面这行，就能拿到一个可点的预览链接：

```markdown
[打开 Rex Markdown 演示](file:///Users/lex/git/go/REX-MARKDOWN-DEMO.md)
```

改写后终端里 hover 会看到 `rex-md://open/<64位hex>`，点它即可在右侧开 "Markdown" 分屏。

也可以在终端里手动造一个 ticket 测试（不经过 Pi）：

```bash
node --input-type=module -e '
import { createTickets } from "/Users/lex/.pi/tools/rex-markdown/bridge.mjs";
const t = createTickets({
  session: process.env.REX_SESSION,
  block: process.env.REX_BLOCK,
  server: "unix:///Users/lex/Library/Application%20Support/rex/server.sock",
});
console.log(t.link("/Users/lex/git/go/REX-MARKDOWN-DEMO.md"));
'
```

拿到 `rex-md://open/...` 后：

```bash
open "rex-md://open/<上面的token>"        # 走 macOS 协议分发
# 或
node ~/.pi/tools/rex-markdown/open.mjs "rex-md://open/<上面的token>"
```

---

### 10.7 “Pi 消息”到底指什么 —— 哪些界面会被改写

“Pi 消息”= **终端 TUI 里 Pi 渲染出来的对话气泡**，不是磁盘上的 `.md` 文件内容，也不是模型上下文。

Pi 源码依据：`dist/modes/interactive/components/markdown-transform.js` + 各 message 组件里调用 `createMarkdownTransform(...)` 的位置。

| 界面 | 是否会被扫描改写 | 说明 |
| --- | --- | --- |
| **assistant（Agent 的回答）** | ✅ | 主要场景 |
| **user（你自己输入的回显）** | ✅ | 你输入里的 `.md` 链接同样能点 |
| **summary（compact 摘要 / 分支摘要）** | ✅ | `compaction-summary-message` / `branch-summary-message` |
| **custom（自定义消息、skill 调用消息）** | ✅ | `custom-message` / `skill-invocation-message` |
| assistant-thinking（思考过程） | ❌ | 本扩展**主动跳过**（`context.messageType === "assistant-thinking"` 直接返回原文） |
| **工具执行结果 / bash 输出** | ❌ | 这些组件不走 markdown 渲染，链接不会被改写 |
| 已经滚过去的旧消息 | ⚠️ | 渲染层当时改写过就还是 `rex-md://`；但 reload 后旧 ticket 被删，链接变“死链”（点击报 ENOENT） |

时序（很重要）：

```
1. 消息产生 → 原文写入 session 的 .jsonl（不变）
2. Pi 把这条消息画到 TUI → 此时 markdown transformer 扫描文本
3. 符合条件的 .md 链接被替换成 rex-md://open/<ticket>，此时才签发 ticket
4. 终端里显示为可点链接
```

所以：

- **不需要额外操作**：以后每次会话，新出现的 Agent 消息里的 `.md` 链接自动可点。
- **流式输出中**未闭合的链接（`[a](b` 还没写完）不会被改写；消息完整后会被重新渲染 → 立刻变成可点。
- 链接文本本身、消息内容、模型上下文**都不受影响**，改的只是终端里显示出来的链接目标。
- 同一个文件路径在同一会话里复用同一个 ticket，不会刷屏式地产生一堆 ticket 文件。

---

## 🔐 十一、安全模型（上游设计，值得知道）

- 链接里只有随机 256-bit ticket，**不含可执行命令，也不含文件系统路径**；真实路径存在 0600 权限的 ticket 文件里。
- 未知 ticket、非本地 Rex 目标（远程 server）、非法 session/block 一律拒绝。
- 参数直接进 argv，不走 shell，文件名用 terminal-browser 的 `terminal-browser-file:` 预览 scheme 传（调用其 Markdown 渲染器，不是下载）。
- ticket 文件夹 0700、ticket 文件 0600，Pi 关闭时删除。
- 预览浏览器使用**完全隔离**的 HOME / profile / config / cache / daemon，**绝不接入**个人浏览器 profile，也不与其它 terminal-browser 实例合并。
- `TERMINAL_BROWSER_NO_TELEMETRY=1` 关闭使用统计与崩溃上报；但预览打开期间 Chromium 引擎仍在跑，最后一个预览关闭后 daemon 退出。
- 已知局限：**不支持远程 Rex server**；Pi 崩溃可能残留无用 ticket 文件。

---

## 🔗 十二、参考链接

| 内容 | 链接 |
| --- | --- |
| 收录页（含简介） | https://github.com/beejmaxx/awesome-rex |
| 上游源码 | https://github.com/jal-co/jalco-dotfiles/tree/main/tools/rex-markdown |
| 上游 README | `~/.pi/tools/rex-markdown/README.md` |
| terminal-browser | https://terminal-browser.com/ · `brew install --cask terminal-browser` |
| Rex 官方文档 | https://www.superlogical.com/rex/docs |
| Pi 扩展 API（`registerMarkdownTransformer`） | `@earendil-works/pi-coding-agent` → `dist/core/extensions/types.d.ts` |

---

## 📝 十三、附：本次安装实际执行的命令流水

```bash
# 1. 依赖
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --cask terminal-browser

# 2. 源码
mkdir -p ~/.pi/tools/rex-markdown && cd ~/.pi/tools/rex-markdown
for f in Handler.swift README.md bridge.mjs bridge.test.mjs install.mjs open.mjs; do
  curl -sSL -o "$f" "https://raw.githubusercontent.com/jal-co/jalco-dotfiles/main/tools/rex-markdown/$f"
done

# 3. Pi 扩展（下载后改了 2 处路径，见正文）
curl -sSL -o ~/.pi/agent/extensions/rex-markdown.ts \
  https://raw.githubusercontent.com/jal-co/jalco-dotfiles/main/pi/agent/extensions/rex-markdown.ts

# 4. 软链兜底（marked / jiti 解析）
mkdir -p ~/.pi/node_modules/@earendil-works
ln -sfn /Users/lex/.local/lib/node_modules/@earendil-works/pi-coding-agent \
  ~/.pi/node_modules/@earendil-works/pi-coding-agent
ln -sfn /Users/lex/.local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui \
  ~/.pi/node_modules/@earendil-works/pi-tui

# 5. 安装器（编译 Swift handler + 注册 rex-md: 协议）
node ~/.pi/tools/rex-markdown/install.mjs

# 6. 改测试文件里的 2 处路径，然后跑测试
cd ~/.pi/tools/rex-markdown && node --test bridge.test.mjs

# 7. 协议调度验证
open "rex-md://open/$(printf '0%.0s' {1..64})"; sleep 3
cat ~/Library/Application\ Support/"Rex Markdown"/handler.log

# 8. 最后：在 Pi 会话里执行 /reload
```

---

## 🔗 十四、让 Agent 稳定输出可点链接（2026-11-12 补充）

> 这一节记录一次真实踩坑：**“为什么 Agent 列了一堆 Markdown，我一个都点不开”**，
> 以及为了让 Agent **每次都自动**写成可点链接而做的三层改造。

### 14.1 起因：不是工具坏了，是 Agent 写错了格式

现象：Agent 回答里列了几十个 `.md` 文件，**一个都点不开**，但 hover 链接看到的是原始路径而不是 `rex-md://`。

定位结论：**扩展只改写「真正的 Markdown 链接 token」**。
`bridge.mjs` 的 `rewriteMarkdown()` 只处理 `token.type === "link"`，其余一律跳过：

```js
if (token.type === "link") {                    // ← 只有这种会被改写
  const target = linkFor(token.href);
  ...
} else if (!["code", "codespan", "html", "image"].includes(token.type)) {
  // 递归处理子节点
}
```

用真实代码验证（`marked` 的 lexer + `bridge.mjs` 的 rewriteMarkdown）：

| Agent 写的 | 改写结果 | 能预览？ |
| --- | --- | --- |
| `` `base/00-index.md` `` | 原样不动（`codespan`） | ❌ |
| `base/01-struct.md`（纯文本） | 原样不动 | ❌ |
| ` ```代码块``` 里的路径` | 原样不动（`code`） | ❌ |
| `![图](a.md)` | 原样不动（`image`） | ❌ |
| `[base/01-struct.md](base/01-struct.md)` | → `rex-md://open/<ticket>` | ✅ |
| `[跨项目](file:///Users/lex/git/.../x.md)` | → `rex-md://open/<ticket>` | ✅ |

**结论：链接可点与否，完全取决于 Agent 有没有“写成链接”。**
扩展本身、ticket 机制、handler 调度全都是好的。

> 这也解释了第十节 10.7 的结论：“Pi 消息”指的是**终端 TUI 里渲染出来的对话气泡**，
> 改写发生在渲染层，所以模型上下文里存的永远是原文。

### 14.2 定位手法（下次遇到直接照抄）

```bash
# 1) 确认 Pi 在 Rex 里跑（扩展靠这两个环境变量定位发起点击的 pane）
env | grep -E '^REX_(SESSION|BLOCK|SERVER)'

# 2) 看 ticket 有没有在签发（有 = 扩展扫到了链接）
ls -lt ~/Library/Application\ Support/"Rex Markdown"/tickets/ | head

# 3) 看 handler 有没有真的被调用
tail -20 ~/Library/Application\ Support/"Rex Markdown"/handler.log

# 4) 直接验证某个写法会不会被改写（最直接）
node --input-type=module -e '
import { rewriteMarkdown, resolveMarkdownPath } from "/Users/lex/.pi/tools/rex-markdown/bridge.mjs";
import { createRequire } from "node:module";
const require = createRequire("/Users/lex/.pi/node_modules/@earendil-works/pi-coding-agent/package.json");
const { lexer } = require("marked");
const cwd = process.cwd();
const linkFor = (h) => { const p = resolveMarkdownPath(h, cwd); return p ? "rex-md://open/<ticket>" : null; };
const s = "- [a.md](a.md)\n- `b.md`\n";
console.log(rewriteMarkdown(s, lexer(s), linkFor));
'
```

### 14.3 三层改造（让 Agent 每次都自动写成可点链接）

| 层 | 文件 | 作用 | 生效时机 |
| --- | --- | --- | --- |
| L1 · 常驻 | `~/.pi/agent/APPEND_SYSTEM.md` | 把规则写进 **system prompt** | **新会话**（见 14.4） |
| L2 · 按需 | `~/.pi/agent/skills/rex-md-links/SKILL.md` | 详细规则 + 对照表 + 坑位，命中任务时加载 | `/reload` 后可用 |
| L3 · 工具 | `~/.pi/agent/skills/rex-md-links/check.sh` | 输出前自检路径，避免给死链 | 随时 |

#### L1：`~/.pi/agent/APPEND_SYSTEM.md`（全文）

```markdown
# 输出规范：Markdown 文件引用必须用可点击链接

当你在回答中引用磁盘上的 .md / .markdown 文件时（列目录、指向刚写的笔记、给出“看这篇/看那个”），
必须写成真正的 Markdown 链接，而不是行内代码或纯文本。

## 规则

1. 用真正的 Markdown 链接：`[文件名.md](路径)`
2. 显示文字就是文件名本身，不要再套反引号。
3. 路径必须能解析到真实存在的文件：
   - 同项目内 → 相对 Pi 启动 cwd 的相对路径
   - 跨项目 / 不确定 cwd → `file://` 绝对 URL
4. 绝对不要用下面这些写法（都不会被改写）：
   - 行内代码 `docs/a.md`
   - 纯文本 docs/a.md
   - 放在 ``` 代码块里的路径
   - `![a](a.md)` 图片语法
   - 指向目录的链接 `[d03/](d03/)`
   - 指向 .go / .sh / .pdf 的链接（只支持 .md / .markdown）

## 为什么要这么写

本机装了 Rex Markdown 扩展：它在 Pi 渲染你的消息时扫描 `[文字](链接)`，
把指向本地 .md 的链接换成 rex-md://open/<ticket>，
点击后在 Rex 终端当前 pane 右侧开一个分屏，用 terminal-browser 渲染出带样式的预览。

改写发生在渲染层，所以：
- 只有真正的链接语法才会被扫描 → 你必须“写成链接”才行
- 已经滚过去的旧消息不会被回溯改写 → 需要重新输出一遍（或 /reload）
- 模型上下文里存的仍是原文 → 不影响任何功能

## 自检

bash ~/.pi/agent/skills/rex-md-links/check.sh path/to/file.md
输出 OK → /绝对路径 才会被改写；输出 SKIP 就别把它写成链接。

验证：Cmd/Ctrl + hover 链接，目标应是 rex-md://open/<64位hex>。
```

> ⚠️ `APPEND_SYSTEM.md` 的**项目版优先级高于全局版**（不合并）：
> `.pi/APPEND_SYSTEM.md` > `~/.pi/agent/APPEND_SYSTEM.md`。
> 源码依据：`dist/core/resource-loader.js:970` `discoverAppendSystemPromptFile()`。

#### L2：`~/.pi/agent/skills/rex-md-links/SKILL.md`

frontmatter 里的 `description` 决定路由命中率，写全了关键词：

```yaml
---
name: rex-md-links
description: Make Markdown file references clickable so the Rex Markdown extension renders them in a
  side-by-side preview pane. Use when listing, enumerating, summarizing, or pointing at .md /
  .markdown files (docs, notes, READMEs, design docs) in your reply — e.g. "list the markdown files",
  "which doc should I read", "here are the notes", or whenever your answer contains file paths the
  user may want to open. Triggers on mentions of Rex Markdown preview, rex-md:// links, markdown
  links not clickable, or "怎么让文档能点开".
---
```

正文包含：判定规则、写法对照表、什么时候该主动加链接、验证方法、常见问题。

#### L3：`~/.pi/agent/skills/rex-md-links/check.sh`

```bash
#!/usr/bin/env bash
# 输出： OK → /绝对路径   会被改写
#        SKIP             不会被改写，别写成链接
set -uo pipefail
BRIDGE="$HOME/.pi/tools/rex-markdown/bridge.mjs"
[ -f "$BRIDGE" ] || { echo "SKIP   找不到 bridge.mjs：$BRIDGE" >&2; exit 1; }
[ "$#" -eq 0 ] && { echo "用法: bash $0 <路径...>" >&2; exit 1; }
node --input-type=module -e '
const { resolveMarkdownPath } = await import(process.argv[1]);
for (const p of process.argv.slice(2)) {
  const r = resolveMarkdownPath(p, process.cwd());
  console.log(r ? "OK    → " + r : "SKIP");
}
' "$BRIDGE" "$@"
```

实测输出：

```
daydayup/md/03-if-for.md       OK    → /Users/lex/git/go/daydayup/md/03-if-for.md
base/00-index.md               OK    → /Users/lex/git/go/base/00-index.md
nonexistent.md                 SKIP
https://a.com/b.md            SKIP
daydayup/d03/main.go           SKIP
file:///Users/lex/git/knowledge/macos/terminal/Rex/Rex-Markdown-for-pi.md
                               OK    → /Users/lex/git/knowledge/macos/terminal/Rex/Rex-Markdown-for-pi.md
```

### 14.4 ⚠️ 激活：`/reload` 不够，**必须开新会话**

读 Pi 源码得到的结论（`@earendil-works/pi-coding-agent` 1.5.2）：

```
dist/core/agent-session.js:2794   this._rebuildSystemPrompt(this.getActiveToolNames());
                                     └─ 唯一调用点，在 extendResourcesFromExtensions() 里
dist/core/agent-session.js:2783   if (!this._extensionRunner.hasHandlers("resources_discover")) return;
                                     └─ 没有扩展提供 resources_discover → 直接 return
dist/core/agent-session.js:3132   await this.extendResourcesFromExtensions("reload");   ← reload 时也会走到上面那个 early-return
```

即：**`/reload` 会重新注册 markdown transformer、重新签发 ticket（渲染层），
但不会重建 system prompt（L1 的规则、L2 的技能清单）。**

| 操作 | 效果 |
| --- | --- |
| `/reload` | ✅ 重新注册 transformer + 重新签发 ticket → **旧消息里的链接复活** |
| **重启 Pi / 开新会话** | ✅ 加载 `APPEND_SYSTEM.md` + 新技能 → **规则真正生效** |

### 14.5 已知硬限制

| 限制 | 说明 |
| --- | --- |
| 只支持 `.md` / `.markdown` | `.go` / `.sh` / `.pdf` / `.txt` 一律不能预览 |
| 指向目录的链接不生效 | 要预览目录得指它的 `README.md` |
| 链接必须指向**真实存在**的文件 | 不存在就不改写（避免死链） |
| 相对路径绑定 Pi 启动 cwd | 跨项目用 `file://` 绝对 URL |
| 需要新做 `rex-src://` handler | 想预览源码得复制一份 `Handler.swift` + `open.mjs`，把渲染器换成源码高亮 |

### 14.6 验收清单

- [ ] `env | grep REX_SESSION` 有输出
- [ ] `ls ~/Library/Application\ Support/"Rex Markdown"/tickets/` 有新 ticket
- [ ] `tail ~/Library/Application\ Support/"Rex Markdown"/handler.log` 有 split 记录
- [ ] Agent 输出的 `[x.md](x.md)` hover 显示 `rex-md://open/<64位hex>`
- [ ] 点击 → Rex 右侧开 “Markdown” 分屏 → 渲染正常
- [ ] `bash ~/.pi/agent/skills/rex-md-links/check.sh <路径>` 返回 `OK`
- [ ] **重启 Pi 后**，新会话里的 Agent 已经会自动写可点链接

### 14.7 本次追加改造的命令流水

```bash
# 1. L1：system prompt 规则
cat > ~/.pi/agent/APPEND_SYSTEM.md <<'EOF'
...（内容见 14.3）
EOF

# 2. L2：技能
mkdir -p ~/.pi/agent/skills/rex-md-links
cat > ~/.pi/agent/skills/rex-md-links/SKILL.md <<'EOF'
...（内容见 14.3）
EOF

# 3. L3：自检工具
cat > ~/.pi/agent/skills/rex-md-links/check.sh <<'EOF'
...（内容见 14.3）
EOF
chmod +x ~/.pi/agent/skills/rex-md-links/check.sh

# 4. 验证自检工具
cd /Users/lex/git/go && bash ~/.pi/agent/skills/rex-md-links/check.sh \
  daydayup/md/03-if-for.md base/00-index.md nonexistent.md https://a.com/b.md

# 5. 验证改写行为（真实调用 bridge.mjs）
node --input-type=module -e '...（见 14.2 第 4 条）'

# 6. 最后：重启 Pi（或开新会话）让 APPEND_SYSTEM.md 生效
#    /reload 只够复活旧消息的链接，不够加载新规则
```
