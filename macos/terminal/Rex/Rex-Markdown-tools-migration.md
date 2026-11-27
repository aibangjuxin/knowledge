# Rex Markdown 运行时目录迁移（~/.pi/tools/ → ~/.local/share/rex-markdown/）

> 记录时间：2026-11-27 · 环境：macOS 27.2 · Pi 1.5.2 · Node v26.13.1 · Rex 0.1.0-preview.x
>
> 起因：一次「目录清理」顺手删掉了 `~/.pi/tools/`，导致 pi **完全起不来**；
> 恢复之后又暴露了 Pi 的 `tools/` 迁移警告，于是顺势把运行时迁出 Pi 目录树。
>
> 相关文档：[Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md)（功能与安装）、[mdview.md](./mdview.md)（终端预览命令）

---

## 📖 一、两个症状，两级根因

### 症状 1：pi 拒绝启动

```
Error: Failed to load extension "/Users/lex/.pi/agent/extensions/rex-markdown.ts":
Failed to load extension: Cannot find module '/Users/lex/.pi/tools/rex-markdown/bridge.mjs'
Require stack:
- /Users/lex/.pi/agent/extensions/rex-markdown.ts
Hint: Start without extensions using "pi -ne".
```

**根因**：扩展用相对路径动态 import bridge：

```ts
const source = pathToFileURL(realpathSync(fileURLToPath(import.meta.url)));
await import(new URL("../../tools/rex-markdown/bridge.mjs", source).href);
//                 ↑ 解析成 /Users/lex/.pi/tools/rex-markdown/bridge.mjs
```

`~/.pi/tools/` 整个目录不存在 → import 抛异常 → **扩展加载失败直接中断 pi 启动**（连 TUI 都进不去）。

> ⚠️ 关键教训：**一个可选功能不该能弄死整个进程**。扩展已加降级保护：
> bridge 拿不到就只发一条 warning、跳过该功能，pi 照常启动。

### 症状 2：启动时刷警告

```
Warning: Project tools/ directory contains custom tools. Custom tools have been merged into extensions.

Move your extensions to the extensions/ directory.
Migration guide: https://github.com/earendil-works/pi/blob/main/packages/coding-agent/CHANGELOG.md#extensions-migration
```

**根因**：Pi 启动时跑一次迁移检查，源码在 `packages/coding-agent/src/migrations.ts`：

```ts
function checkDeprecatedExtensionDirs(baseDir, label) {
  const toolsDir = join(baseDir, "tools");
  // ...
  const customTools = entries.filter((e) => {
    const lower = e.toLowerCase();
    return lower !== "fd" && lower !== "rg" && lower !== "fd.exe" && lower !== "rg.exe" && !e.startsWith(".");
  });
  if (customTools.length > 0) warnings.push(`${label} tools/ directory contains custom tools. ...`);
}
```

调用点：

```ts
migrateExtensionSystem(cwd) {
  const agentDir = getAgentDir();                    // ~/.pi/agent
  const projectDir = join(cwd, CONFIG_DIR_NAME);    // <cwd>/.pi
  return [
    ...checkDeprecatedExtensionDirs(agentDir, "Global"),
    ...checkDeprecatedExtensionDirs(projectDir, "Project"),
  ];
}
```

三个必须知道的细节：

| 细节 | 说明 |
| --- | --- |
| **只看顶层条目名** | 不递归、不看扩展名。`~/.pi/tools/rex-markdown/` 这个**子目录本身**就是触发项 |
| **例外只有 fd / rg** | 那是 Pi 自己解出来的二进制，会被迁到 `bin/`；其余一律算「custom tools」 |
| **标签取决于 cwd** | 全局位是 `~/.pi/agent/tools/`；项目位是 `<cwd>/.pi/tools/`。在 `~` 下跑 pi 时 cwd=`~`，项目位正好就是 `~/.pi/tools` → 所以显示 **"Project"**。换个目录跑就没有这条警告 |

而且 Pi 现在**根本不再从 `tools/` 加载自定义工具**（`resource-loader.ts` 只扫 `extensions/`），
这个目录已经是纯遗留位置——**继续放东西只会一直触发警告，没有任何收益**。

---

## 🧩 二、方案与取舍

| 方案 | 做法 | 取舍 |
| --- | --- | --- |
| **A（已执行）** | 迁到 `~/.local/share/rex-markdown/`，同步改 3 处路径 + 重装 URL handler | 一次性成本；目录语义正确；与 Pi 后续版本兼容 |
| B | 维持现状 | 只是 warning，但 `~/.pi/tools/` 是废弃位置，Pi 后续版本行为不可预期 |
| C | 放弃 Rex Markdown 功能 | 警告消失，但失去「点 md 链接开预览」 |

> 方案 A 原本就有一份迁移脚本 `fix-pi-tools.sh`，但它被**终端 TUI 快照污染**了
> （文件里混进了 `Code Mode enabled` / `tool: read on` / `Enter/Space to change` 等 UI 文本，
> 尾部还有野 `FIXEOF`），跑到一半夭折 → 目录被删了、目标目录是空的、路径没改。
> 本次已把它重写成干净、幂等、可复现的版本（见第五节）。

---

## 🔧 三、方案 A 的完整步骤（可复现）

```bash
# 0. 备份（务必！这一步出问题就是重装整个工具）
cp -a ~/.pi/tools ~/.pi-tools-backup-$(date +%Y%m%dT%H%M%S)

# 1. 搬运文件
mkdir -p ~/.local/share/rex-markdown
cp -a ~/.pi/tools/rex-markdown/. ~/.local/share/rex-markdown/
rm -rf ~/.pi/tools/rex-markdown
rmdir ~/.pi/tools

# 2. 改扩展的 import 路径：相对路径 → 绝对路径
#    ~/.pi/agent/extensions/rex-markdown.ts
#    new URL("../../tools/rex-markdown/bridge.mjs", source).href
#  → pathToFileURL(join(homedir(), ".local", "share", "rex-markdown", "bridge.mjs")).href
#    同时把提示文案 ~/.pi/tools/rex-markdown/install.mjs → ~/.local/share/rex-markdown/install.mjs

# 3. 改 skill 自检脚本的 BRIDGE 路径
#    ~/.pi/agent/skills/rex-md-links/check.sh
#    BRIDGE="$HOME/.pi/tools/rex-markdown/bridge.mjs"
#  → BRIDGE="$HOME/.local/share/rex-markdown/bridge.mjs"

# 4. ⚠️ 必须重装 URL handler（见下方「关键坑 2」）
cd ~/.local/share/rex-markdown && node install.mjs

# 5. 修测试文件里的两处相对路径依赖（见下方「关键坑 3」）

# 6. 校验
cd ~/.local/share/rex-markdown && node --test bridge.test.mjs
bash ~/.pi/agent/skills/rex-md-links/check.sh ~/git/knowledge/macos/terminal/Rex/README.md
```

---

## 🪤 四、五个关键坑

### 坑 1：只搬文件不改路径 = 换个姿势继续报错

扩展、skill 自检脚本、知识库文档里一共有 **26 处**路径引用指向 `~/.pi/tools/rex-markdown`。
漏改任何一处，就会出现「一半能用一半不能用」的诡异状态。

### 坑 2：URL handler 的 Info.plist 里写死了绝对路径

`install.mjs` 会把 `open.mjs` 的**绝对路径**写进 `~/Applications/Rex Markdown.app/Contents/Info.plist`：

```xml
<key>RexMarkdownScript</key><string>/Users/lex/.pi/tools/rex-markdown/open.mjs</string>
```

只搬文件、不重跑 `install.mjs` → 点链接时 handler 找不到脚本 → **预览静默失败**。

```bash
plutil -p ~/Applications/Rex\ Markdown.app/Contents/Info.plist | grep RexMarkdownScript
# 迁移后必须是：
#   "RexMarkdownScript" => "/Users/lex/.local/share/rex-markdown/open.mjs"
```

重跑 `install.mjs` 会一并做完：编译 Swift handler（`swiftc`）→ ad-hoc 签名（`codesign`）
→ 注册 `rex-md:` 协议（`lsregister` + `LSSetDefaultHandlerForURLScheme`）→ 刷新 `programs.json`。

> 顺带一提：`programs.json` 与 `Info.plist` 里还记着 `node` 的绝对路径。
> 本次迁移时 Homebrew 已把 node 从 26.12.1 升到 26.13.1，`install.mjs` 顺带刷新成了新路径——
> 这也是「节点路径变了要重跑 install.mjs」那条排障项的由来。

### 坑 3：上游测试文件里有相对路径依赖

`bridge.test.mjs` 用**相对位置**去找扩展和 node_modules：

```js
const require = createRequire(new URL("../../agent/extensions/rex-markdown.ts", import.meta.url));
//                                          ↑ 迁移前成立；迁移后指向 ~/.local/agent/... ✗

const { createJiti } = createRequire(new URL("../../node_modules/@earendil-works/pi-coding-agent/package.json", import.meta.url))("jiti");
//                                          ↑ 同上 ✗
```

报错长这样（**不是**「文件不存在」，而是「模块解析不到」）：

```
Error: Cannot find module '@earendil-works/pi-tui'
Require stack:
- /Users/lex/.local/agent/extensions/rex-markdown.ts
```

修法：改成绝对路径（`homedir()` + `join`），与文件里第 155 行已有的写法保持一致：

```js
const require = createRequire(pathToFileURL(join(homedir(), ".pi/agent/extensions/rex-markdown.ts")));
const { createJiti } = createRequire(pathToFileURL(join(homedir(), ".pi/node_modules/@earendil-works/pi-coding-agent/package.json")))("jiti");
```

### 坑 4：Pi 的 `~/.pi/node_modules` 软链农场是刚需

扩展第 8 行的 `createRequire(import.meta.resolve("@earendil-works/pi-tui"))` 依赖这组软链：

```
~/.pi/node_modules/@earendil-works/pi-coding-agent -> ~/.local/lib/node_modules/@earendil-works/pi-coding-agent
~/.pi/node_modules/@earendil-works/pi-tui           -> .../pi-coding-agent/node_modules/@earendil-works/pi-tui
```

它们同时给 `marked` 解析兜底。**迁移 runtime 不影响这组软链**，但别顺手删。

### 坑 5：`~/.pi/tools` 是 Pi 的「项目位」，不是「用户位」

在 `~` 下跑 pi 时 `<cwd>/.pi` == `~/.pi`，于是 `~/.pi/tools` 被当成**项目级**目录检查，标签是 "Project"。
换到 `~/git/go` 下跑 pi 就看不到这条警告了——**别被「换个目录就好了」骗了**，那只是没扫到而已。

---

## ✅ 五、本次实际执行流水与验证

### 执行流水（2026-11-27 11:28–11:35）

| # | 操作 | 结果 |
| --- | --- | --- |
| 1 | `cp -a ~/.pi/tools ~/.pi-tools-backup-20261127T112854` | ✅ 备份留存 |
| 2 | `cp -a ~/.pi/tools/rex-markdown/. ~/.local/share/rex-markdown/` | ✅ 6 个文件就位 |
| 3 | `rm -rf ~/.pi/tools/rex-markdown && rmdir ~/.pi/tools` | ✅ 旧目录清除 |
| 4 | 改写 `~/.pi/agent/extensions/rex-markdown.ts`（import 路径 + 提示文案 + 本地类型声明） | ✅ |
| 5 | 改写 `~/.pi/agent/skills/rex-md-links/check.sh`（`BRIDGE=`） | ✅ |
| 6 | `node ~/.local/share/rex-markdown/install.mjs` | ✅ Swift handler 重编译 + 重签名 + 协议重注册 |
| 7 | 修 `bridge.test.mjs` 两处相对路径 | ✅ |
| 8 | 同步知识库文档 26 处路径（3 个 .md） | ✅ |
| 9 | 重写 `fix-pi-tools.sh` 为干净幂等版本 | ✅ |
| 10 | 跑 `bash fix-pi-tools.sh --dry-run` + 实跑一次 | ✅ 幂等性验证通过 |

### 验证清单

| # | 验证项 | 命令 | 结果 |
| --- | --- | --- | --- |
| 1 | pi 启动无 `tools/` 警告 | `pi --mode rpc --offline --no-session` | ✅ 0 命中 |
| 2 | 扩展正常加载（bridge import 成功） | 同上，看有无 "Rex Markdown disabled" | ✅ 0 命中 |
| 3 | bridge 导出完整 | `import(bridge.mjs)` 检查 3 个函数 | ✅ |
| 4 | 扩展自测套件 | `node --test bridge.test.mjs` | ✅ **13/13 通过** |
| 5 | skill 自检脚本 | `bash check.sh <某个 .md>` | ✅ `OK → /Users/lex/.../README.md` |
| 6 | Info.plist 指向新路径 | `plutil -p .../Info.plist` | ✅ `RexMarkdownScript → ~/.local/share/rex-markdown/open.mjs` |
| 7 | URL handler 端到端 | `open "rex-md://open/000...0"` → 看 `handler.log` | ✅ handler 被唤起并执行到 `open.mjs`（无效 ticket 报错 = 链路通） |
| 8 | `rex-md:` 协议注册 | `lsregister -dump` | ✅ `claimed schemes: rex-md:` |

> 验证 4 里包含一条 `Pi rewrites presentation only and revokes tickets at session shutdown`——
> 它会用 jiti 真实加载扩展并走一遍改写逻辑，等于把扩展本身也测了。

### 文件变更清单

| 路径 | 变更 |
| --- | --- |
| `~/.pi/tools/rex-markdown/` | **删除**（迁出） |
| `~/.local/share/rex-markdown/` | **新增**：`bridge.mjs` `bridge.test.mjs` `open.mjs` `install.mjs` `Handler.swift` `README.md` |
| `~/.pi/agent/extensions/rex-markdown.ts` | import 改绝对路径；加本地类型声明；加 bridge 缺失时的降级保护 |
| `~/.pi/agent/skills/rex-md-links/check.sh` | `BRIDGE=` 改新路径 |
| `~/Applications/Rex Markdown.app` | 重新编译 + 重新签名（`Info.plist` 路径刷新） |
| `~/Library/Application Support/Rex Markdown/programs.json` | 刷新 node 路径（26.12.1 → 26.13.1） |
| `~/.pi-tools-backup-20261127T112854/` | 新增备份（回滚用） |

---

## 🔙 六、回滚

```bash
# 完整回滚到迁移前
cp -a ~/.pi-tools-backup-20261127T112854/rex-markdown ~/.pi/tools/ 2>/dev/null || \
  { mkdir -p ~/.pi/tools && cp -a ~/.pi-tools-backup-20261127T112854/rex-markdown ~/.pi/tools/; }
# 扩展路径改回相对/旧绝对路径 + check.sh 改回 + 重跑 install.mjs
```

或者直接用另一份更早的备份：`~/.pi-tools-backup-20261127T105956/`（含未修改的原始 6 个文件）。

---

## 📎 七、脚本：`fix-pi-tools.sh`

幂等的迁移脚本，可反复执行；`--dry-run` 只打印不改动。

```bash
bash fix-pi-tools.sh --dry-run   # 预演
bash fix-pi-tools.sh              # 实跑
```

7 个阶段：前置检查 → 备份 → 搬运 → 改扩展 → 改 skill → 重装 handler → 清理 → 校验。

> ⚠️ 写这类脚本的教训：**别用 shell heredoc 往文件里塞代码**。
> 终端 TUI 的快照（Code Mode 开关提示、工具面板状态）会被一起捕获进文件，
> 产出语法错误 / 逻辑残缺的脚本——本次那份坏脚本就是这么来的。
> 用编辑器工具落文件，或落盘后再 `bash -n` 过一遍。

---

## 🔗 八、相关链接

| 用途 | 链接 |
| --- | --- |
| Pi 扩展迁移 changelog | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/CHANGELOG.md#extensions-migration |
| Pi 扩展开发文档 | https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md |
| 上游源码 | https://github.com/jal-co/jalco-dotfiles/tree/main/tools/rex-markdown |
| Rex 官方文档 | https://www.superlogical.com/rex/docs |
| 本机功能文档 | [Rex-Markdown-for-pi.md](./Rex-Markdown-for-pi.md) · [mdview.md](./mdview.md) · [How-to-view-markdown.md](./How-to-view-markdown.md) |
