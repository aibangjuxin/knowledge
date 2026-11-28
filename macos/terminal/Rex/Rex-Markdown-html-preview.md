# Rex Markdown 支持 HTML 预览（本地改动记录）

> 记录时间：2026-11-27 · 环境：macOS 27.2 · Pi 1.5.2 · Node v26.13.1 · Rex 0.1.0-preview.x
>
> 起因：想把手头 Archify 生成的架构图（`release-ob-flow.html`，内联 SVG + 单文件）直接在 Rex 终端里预览，
> 发现扩展只认 `.md` / `.markdown`，HTML 链接点不动。
>
> 相关文档：[Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md)（功能与安装）、
> [Rex-Markdown-tools-migration.md](./Rex-Markdown-tools-migration.md)（运行时目录迁移）、
> [mdview.md](./mdview.md)（终端预览命令）

---

## 📖 一、症状与根因

### 症状

Pi 消息里写 `[架构图](path/to/diagram.html)`，终端里 hover 显示的还是原始路径，
不是 `rex-md://open/<ticket>`，点了也没反应。同一时刻 `.md` 链接一切正常。

### 根因不在渲染端

第一反应是"渲染器不支持 HTML"，**这是错的**。渲染链路：

```
Pi 消息 → bridge.mjs 改写成 rex-md://open/<ticket>
        → Handler.swift（URL scheme 处理器）
        → open.mjs（读 ticket）
        → browserArguments() 拼出 terminal-browser-file://file<abs-path>
        → terminal-browser 打开
```

最后一步的 `terminal-browser` 是**完整浏览器**（不是纯 Markdown 渲染器），
你自己的笔记里就写着：[How-to-view-markdown.md](./How-to-view-markdown.md)

> | 完整浏览器（图片 / HTML / 目录树） | terminal-browser | `terminal-browser open terminal-browser-file://file/<abs>` | ✅ 已装 |

所以 **HTML 本来就能显示**。卡住的是**桥接层不发 ticket**。

### 真正的根因：bridge.mjs 里两处扩展名白名单

```js
// bridge.mjs  resolveMarkdownPath()
if (!/\.(md|markdown)$/i.test(extname(path))) return;      // ← ① 不给 HTML 发 ticket

// bridge.mjs  readTicket()
... || !/\.(md|markdown)$/i.test(ticket.path) || ...        // ← ② 即使伪造 ticket 也被拒
```

Pi 扩展本体（`~/.pi/agent/extensions/rex-markdown.ts`）**没有第二道扩展名过滤**，
它只是把 href 丢给 `resolveMarkdownPath()`：

```ts
const path = resolveMarkdownPath(href, cwd);
if (path) replacement = `[${token.text}](${tickets.link(path)})`;
```

### 为什么"我记得以前 HTML 是能预览的"

**因为走的是另一条路：`mdview`**。

`mdview`（[mdview.md](./mdview.md) 里你自己写的胶水脚本）的 `open_pane()` **完全没有扩展名检查**，
任何文件都能在 Rex 右侧分屏用 terminal-browser 渲染。

实测（本次验证过）：

```bash
mdview --pane /Users/lex/git/knowledge/gcp/secret-manage/ob/docker/release-ob-flow.html
# → {"anchor_id": "block:...", "split_ids": ["split:..."], "revision": ...}
```

分屏确实开出来了、图确实渲染了。

> **结论**：HTML 一直能预览，只是**Pi 消息里的链接**不能。
> `mdview` 是"手动开一个文件"，`rex-md://` 是"消息里的链接可点"——两件事。

### 一个容易误读的源码细节

`bridge.mjs` 的 `rewriteMarkdown()` 里有这么一行：

```js
} else if (!["code", "codespan", "html", "image"].includes(token.type)) {
```

这里的 `"html"` 是 **markdown-it 的 token 类型**（markdown 源码里的 HTML 块），
跟 `.html` **文件扩展名毫无关系**。查根因时在这里绕了很久。

---

## 🧩 二、方案与取舍

| 方案 | 改动量 | 优点 | 缺点 |
|---|---|---|---|
| **A. 放宽 bridge 白名单**（采纳） | 2 处正则 | 复用现有 ticket 机制；不新增 URL scheme；改动可回滚 | 属于本地 patch，上游升级会冲突 |
| B. 新增 `rex-html://` scheme | 新 `Handler.swift` + `open.mjs` + `Info.plist` + 安装器 | 语义更清晰（Markdown vs HTML 分开） | 要重编 Swift、重签名 app、注册新 scheme，工作量大 5 倍 |
| C. 只用 `mdview` | 0 | 零风险 | 消息里的链接仍不可点，每次要手动敲命令 |
| D. 让 Agent 输出终端可渲染的 ASCII 图 | 0 | 无需浏览器 | 图形质量差，丢失交互 |

**选 A**，理由：白名单本来就是"可预览的文件类型"这一语义，
而 `terminal-browser` 本来就能显示 HTML —— **能力早就有了，只是门没开**。

---

## 🔧 三、实际改动（3 处）

### 3.1 `bridge.mjs` —— 抽成共享常量

```js
// 能在 Rex 终端里预览的本地文件扩展名：
//   .md / .markdown  -> 按 Markdown 渲染
//   .html / .htm     -> terminal-browser 当完整浏览器渲染（内联 SVG 架构图等）
// terminal-browser 两种都能显示，区别只在渲染方式，所以共用同一套 ticket 机制。
const PREVIEWABLE_EXTENSIONS = /\.(md|markdown|html?)$/i;
```

### 3.2 `bridge.mjs` —— 两处白名单改用常量

```diff
- if (!/\.(md|markdown)$/i.test(extname(path))) return;
+ if (!PREVIEWABLE_EXTENSIONS.test(extname(path))) return;

- ... || !/\.(md|markdown)$/i.test(ticket.path) || ...
+ ... || !PREVIEWABLE_EXTENSIONS.test(ticket.path) || ...
```

### 3.3 `bridge.mjs` —— 分屏标签按类型区分

```diff
- "--label", "Markdown",
+ "--label", /\.html?$/i.test(ticket.path) ? "HTML" : "Markdown",
```

（不改也能用；改了之后 Rex 分屏标题能一眼看出渲染的是哪种。）

### 3.4 `rex-markdown.ts` —— **加 cache-buster（最关键的一处）**

这一处**不改的话，上面的改动在当前 Pi 会话里根本不生效**（详见坑 1）：

```diff
- const bridgeUrl = pathToFileURL(join(bridgeDirectory, "bridge.mjs")).href;
+ const bridgeUrl = `${pathToFileURL(join(bridgeDirectory, "bridge.mjs")).href}?v=${Date.now()}`; // ?v= 绕过 Node ESM 的 URL 缓存
```

---

## 🪤 四、三个关键坑

### 坑 1：Node ESM 按 URL 缓存 → `/reload` 不够

**现象**：改完 `bridge.mjs` 后 `/reload`，链接还是不可点。

**根因**：`bridge.mjs` 是被扩展用 `await import()` 进来的 **ESM 模块**，
Node 的 ESM loader **按 URL 缓存**——同一进程内再 import 同一个 URL 直接返回缓存实例，
**不会重新读盘**。

实测（最小复现）：

```js
// /tmp/esmtest/drive.mjs
const url = pathToFileURL("/tmp/esmtest/mod.mjs").href;
const a = await import(url);          // → OLD
writeFileSync("/tmp/esmtest/mod.mjs", 'export const V = "NEW";');
const b = await import(url);          // → 仍是 OLD  ← 缓存生效
```

输出：

```
1st import -> OLD
2nd import (same URL, after file change) -> OLD
=> ESM 已缓存（同一进程内不会重新读盘）
```

**为什么 Pi 的 `/reload` 救不了**：

| 环节 | 机制 | 会重读吗 |
|---|---|---|
| 扩展 `.ts` | jiti 加载，`moduleCache: false`（`dist/core/extensions/loader.js:504`） | ✅ 会 |
| `bridge.mjs` | Node 原生 ESM `import()`，按 URL 缓存 | ❌ 不会 |

所以：**扩展重新加载了，但它 import 到的是旧 bridge。**

**解法**：给 URL 加时间戳 `?v=${Date.now()}`，URL 变了 → 缓存不命中 → 重新读盘。
`/reload` 就能生效，不用重启 Pi。

> 这也解释了 [Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md) 第 14.4 节那句
> "`/reload` 不够，**必须开新会话**" —— 同一个根因的不同表现。

### 坑 2：`"html"` 是 markdown-it token 类型

见 [第一节](#一个容易误读的源码细节)。查根因时容易把这里当成"扩展名白名单"。

### 坑 3：多行注释塌成一行，把 `const` 吞进 `//` 注释

改 `bridge.mjs` 时用脚本插入多行注释，第一次生成的代码长这样：

```js
// 能在 Rex 终端里预览的本地文件扩展名：//   .md / .markdown  -> ...const PREVIEWABLE_EXTENSIONS = /.../;
```

**整段都在 `//` 注释里** → 常量根本没定义。

```
$ node --check bridge.mjs     # 语法合法 ✔（因为它就是一句注释）
$ node -e "import('./bridge.mjs')"   # 运行时 ReferenceError ✘
```

**`node --check` 查不出这种错**。教训：
改完跑一次真实 `import()`，别只跑语法检查。
（同一次改动里 `rex-markdown.ts` 也踩了同样的坑——`const bridgeUrl` 被吞进注释，
扩展直接失效。最后从备份恢复 + **改成单行替换**才绕过去。）

---

## ✅ 五、验证清单

| # | 项 | 方法 | 结果 |
|---|---|---|---|
| 1 | 改动前测试基线 | `node --test bridge.test.mjs` | 13/13 通过 |
| 2 | bridge.mjs 语法 | `node --check` | 通过 |
| 3 | bridge.mjs 运行期 | `node -e "import('./bridge.mjs')"` | 通过，常量已定义 |
| 4 | 扩展能被加载 | jiti 实际 `import()` 扩展 | `factory = function` |
| 5 | 新增测试用例 | 新增 "resolve local HTML targets for browser preview" | 通过 |
| 6 | 改动后测试套件 | `node --test bridge.test.mjs` | **14/14 通过** |
| 7 | HTML 判定 | `resolveMarkdownPath(".../release-ob-flow.html", cwd)` | 返回绝对路径 |
| 8 | 非白名单仍被排除 | `.json` / `.py` / `.txt` | 全部 undefined |
| 9 | 自检工具 | `check.sh docker/release-ob-flow.html` | `OK → /绝对路径` |
| 10 | cache-buster 生效 | 同一进程 import 两次（带/不带 `?v=`） | 带 `?v=` 得到新实例 |
| 11 | mdview 旁路可用 | `mdview --pane <html>` | 成功开分屏 |

### 测试用例改动

```diff
- test("leave remote, missing, malformed, non-Markdown, and directory targets alone", (t) => {
+ test("leave remote, missing, malformed, non-previewable, and directory targets alone", (t) => {
      ...
+   writeFileSync(join(directory, "not-preview.txt"), "text");
      for (const href of [..., "not-md.txt", "not-preview.txt", "#section"]) {

+ test("resolve local HTML targets for browser preview", (t) => {
+   const html = join(directory, "diagram.html");
+   const htm = join(directory, "diagram.htm");
+   writeFileSync(html, "<!doctype html><title>Diagram</title>");
+   writeFileSync(htm, "<html/>");
+   for (const href of ["diagram.html", html, pathToFileURL(html).href]) {
+     assert.equal(resolveMarkdownPath(href, directory), html, href);
+   }
+   assert.equal(resolveMarkdownPath("diagram.htm", directory), htm);
+ });
```

---

## 🔙 六、回滚

改动前全部备份过，同目录 `*.bak-*`：

```bash
cd ~/.local/share/rex-markdown
cp bridge.mjs.bak-20261127-184926      bridge.mjs
cp bridge.test.mjs.bak-20261127-184926 bridge.test.mjs

cd ~/.pi/agent/extensions
cp rex-markdown.ts.bak-20261127-185353 rex-markdown.ts

# 然后 /reload（或重启 Pi）
```

> 只回滚 `bridge.mjs` 不回滚扩展的 cache-buster 也没问题——cache-buster 只是让重读更快更可控。

---

## 📎 七、命令流水

```bash
# 1. 定位根因：读源码 + 实测
grep -n 'md|markdown' ~/.local/share/rex-markdown/bridge.mjs
grep -n 'extname' ~/.pi/agent/extensions/rex-markdown.ts        # 无扩展名过滤
grep -n 'terminal-browser-file' ~/.local/share/rex-markdown/bridge.mjs
grep -n '完整浏览器' macos/terminal/Rex/How-to-view-markdown.md

# 2. 确认 mdview 这条旁路可用
mdview --pane /path/to/diagram.html

# 3. 备份
cp -p bridge.mjs      bridge.mjs.bak-$(date +%Y%m%d-%H%M%S)
cp -p bridge.test.mjs bridge.test.mjs.bak-$(date +%Y%m%d-%H%M%S)
cp -p ~/.pi/agent/extensions/rex-markdown.ts ~/.pi/agent/extensions/rex-markdown.ts.bak-$(date +%Y%m%d-%H%M%S)

# 4. 改 bridge.mjs（3 处：常量 + 2 处白名单 + 标签）
# 5. 改 rex-markdown.ts（加 ?v= cache-buster）
# 6. 补测试用例
node --test ~/.local/share/rex-markdown/bridge.test.mjs     # 14/14

# 7. 验证
bash ~/.pi/agent/skills/rex-md-links/check.sh /path/to/diagram.html
node --input-type=module -e 'const {resolveMarkdownPath}=await import("/Users/lex/.local/share/rex-markdown/bridge.mjs"); console.log(resolveMarkdownPath(process.argv[1], process.cwd()))' /path/to/diagram.html

# 8. 激活：Pi 里 /reload
```

---

## 🔗 八、相关链接

- [Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md) —— 功能、安装、原理、判定规则
- [Rex-Markdown-tools-migration.md](./Rex-Markdown-tools-migration.md) —— 运行时目录迁移（同类"本地改动"记录）
- [How-to-view-markdown.md](./How-to-view-markdown.md) —— terminal-browser 是完整浏览器
- [mdview.md](./mdview.md) —— `mdview` 命令说明
- 上游扩展：https://github.com/tt-a1i/archify（无关）／Rex Markdown 上游仓库
