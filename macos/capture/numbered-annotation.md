# macOS 区域截图 + 自动编号标注：可行性探索

> 状态：**只做方案探讨，未实施**。本文所有"实测"结论都来自在 `Mac-mini.local`（macOS 27.2.1, arm64）上跑过的探针命令；
> 公司那台 Mac 是另一台机器，权限结论**必须在公司机上重跑探针**（见 §7）。
>
> 前置笔记：[smartshot.md](knowledge/macos/capture/smartshot.md)（上一轮"自建 smartshot 工具"的草案，本文是它的**纠偏 + 收敛版**：
> 草案假设可以直接调 `screencapture` 抓屏，实测在这台机器上**不成立**）。

---

## 1. 需求复述

想要的效果，一句话：

> 按系统默认快捷键截图 → 框选一片区域 → 在框上自动出现 `1`、`2`、`3` 的编号标记（可再配说明文字）→ 导出/粘贴。

约束：

- 公司 Mac **不允许安装第三方截图工具**（大概率也不允许装第三方 Python 包）。
- 系统自带的截图工具和 `screencapture` 命令**大概率可用**（这是需求里的假设，实测需要修正）。

## 2. 结论速览

| # | 结论 | 影响 |
|---|---|---|
| 1 | **终端里跑 `screencapture` 在这台机器上失败**：`could not create image from display`；而且 `-i` 交互模式**静默 exit 0 但不产出文件** | 自建工具**不能自己抓屏**，"截屏 + 标注"必须拆成两段 |
| 2 | **系统快捷键截图是走系统进程**，不受终端权限限制 | 截图环节**继续用系统原生快捷键**（⌃⇧⌘4 / ⇧⌘4 / ⇧⌘5） |
| 3 | **读剪贴板图片不需要屏幕录制权限**（已用真实 PNG 验证） | 用「⌃⇧⌘4 复制到剪贴板」作为系统→我们工具的**交接通道** |
| 4 | **写 Swift + AppKit 工具零安装可行**（Xcode CLT 已装，swiftc 编译通过） | 自动编号标注用 AppKit 自绘，不需要任何第三方 GUI 库 |
| 5 | **合成按键（AppleScript/System Events）被系统拒绝**：`osascript is not allowed to send keystrokes` | 不能用脚本"模拟按快捷键"来驱动系统截图；全局热键也不能靠 CGEvent 注入 |
| 6 | **系统快捷键绑定**（系统设置 → 键盘快捷键 → App 快捷键 → 快捷指令）是唯一干净的"一键触发"入口 | 用「快捷指令」包一层，绑定自定义热键调我们的工具 |
| 7 | 系统自带标注工具栏（⇧⌘5）**不能自动编号**，只能手打数字 | 手打编号 = 兜底方案（0 安装），不是目标方案 |
| 8 | 本机是**双屏 + 混合缩放**（5K@2x + UWQHD@1x） | 自绘工具的坐标/缩放处理是主要技术难点 |

**推荐路线（分层）**：

```text
┌─ 截图层（用系统原生，零折腾）──────────────────────────┐
│  ⌃⇧⌘4  框选区域 → 图片进剪贴板                          │
│  ⇧⌘4  框选区域 → 文件落 ~/Pictures/Screenshots         │
└───────────────┬────────────────────────────────────────┘
                │  交接通道：剪贴板 / 新文件 / 命令行传参
                ▼
┌─ 编号层（自建，Swift + AppKit，零安装）────────────────┐
│  读图 → 弹出标注窗口 → 拖框自动生成 ①②③ → Enter 导出      │
└───────────────┬────────────────────────────────────────┘
                │
                ▼
┌─ 触发层（系统快捷键绑定，零安装）───────────────────────┐
│  系统设置 → 键盘快捷键 → App 快捷键 → 快捷指令 → ⌘⇧⌥N     │
│  快捷指令里 "Run Shell Script" 调 ./annotator             │
└────────────────────────────────────────────────────────┘
```

## 3. 实测探针与原始结果

在 `Mac-mini.local` 上跑，全部原样记录（可复制到公司机重跑）。

### 3.1 权限类

```bash
# 探针 A：终端能不能自己抓屏？
screencapture -x /tmp/probe.png ; echo "exit=$?" ; ls -l /tmp/probe.png
# → could not create image from display
# → exit=1，文件不存在

# 探针 B：交互式区域截图（同 A 的静默陷阱）
screencapture -i -x /tmp/probe2.png ; echo "exit=$?" ; ls -l /tmp/probe2.png
# → exit=0，但 /tmp/probe2.png 不存在   ⚠️ 静默失败，脚本里绝不能只看 exit code

# 探针 C：能不能模拟按键（辅助功能权限）
osascript -e 'tell application "System Events" to keystroke "s" using {command down, shift down}'
# → execution error: osascript is not allowed to send keystrokes. (1002)

# 探针 D：能不能读 TCC 权限表（需要完全磁盘访问）
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db"   "select client,auth_value from access where service='kTCCServiceScreenCapture'"
# → unable to open database file（读不到，只能靠上面的行为探针反推）
```

> **探针 A/B 的意义**：`screencapture` 不是"不能用"，而是**要屏幕录制权限**，而权限授予的是**父进程（Terminal / iTerm / Ghostty / 你的 shell）**。
> 公司 MDM 若没给终端这个权限，`screencapture` 这条路整个封死——而且是静默封死。

### 3.2 工具链类

```bash
sw_vers                       # → macOS 27.2.1 (26B131)
swift --version               # → Apple Swift 6.4，Xcode-beta CLT 在 /Applications/Xcode-beta.app
xcode-select -p               # → CLT 已装 ✅（swiftc 可用，不需要装任何东西）
command -v osascript shortcuts automator sips qlmanage   # → 全有 ✅
python3 -c "import PIL"       # → ModuleNotFoundError（且公司机大概率不让 pip 装）
python3 -c "import Quartz"    # → ModuleNotFoundError
command -v magick             # → /opt/homebrew/bin/magick（本机有，公司机不一定）
ls -d /System/Applications/Utilities/Screenshot.app          # → 系统截图 App 在
ls -d "/Applications/Google Chrome.app"                       # → 有（用于 HTML 渲染路线）
```

### 3.3 显示与截图落盘

```bash
system_profiler SPDisplaysDataType | grep -iE "resolution|UI Looks"
# → 5120x2880 (5K)   UI Looks like 2560x1440     ← 逻辑 2560×1440，物理 5120×2880（2x）
# → 3440x1440 (UWQHD) UI Looks like 3440x1440     ← 1x

defaults read com.apple.screencapture
# → location = "/Users/lex/Pictures/Screenshots"
# → last-selection = { X=971; Y=601; Width=719; Height=605; } last-selection-display = 0
#   ↑ 系统会记住上次框选矩形（配合 screencapture -R 可复用同一区域）

ls -lt ~/Pictures/Screenshots | head
# → 里面混着 IMG_0594.jpg 等手机照片 ⚠️ 不能"取最新文件"当截图
```

### 3.4 三条渲染路线（全部用真实像素验证过）

**路线 1：Swift + AppKit（推荐）**——读剪贴板 → 画红圈数字 → 存 PNG，实测输出 1600×1000（2x），圆点像素 `srgba(255,56,60,1)` ✅

```swift
import AppKit

let pb = NSPasteboard.general

// ⚠️ 坑：NSPasteboard 没有 .image 属性（编译报 no member 'image'），必须这样取：
func loadImage() -> NSImage? {
    if let objs = pb.readObjects(forClasses: [NSImage.self], options: nil),
       let img = objs.first as? NSImage { return img }
    for t in [NSPasteboard.PasteboardType.png, .tiff] {
        if let d = pb.data(forType: t), let img = NSImage(data: d) { return img }
    }
    return nil
}

guard let img = loadImage() else { print("NO_IMAGE"); exit(2) }
print("clipboard image size: \(img.size)")   // → (800.0, 500.0) 逻辑点

let sz = img.size
let out = NSImage(size: sz)
out.lockFocus()
img.draw(at: NSPoint(x: 0, y: 0), from: NSRect(origin: .zero, size: sz),
         operation: .copy, fraction: 1.0)

let d: CGFloat = 60
let circle = NSBezierPath(ovalIn: NSRect(x: 30, y: sz.height - 90, width: d, height: d))
NSColor.systemRed.setFill(); circle.fill()
NSColor.white.setStroke(); circle.lineWidth = 3; circle.stroke()

let attrs: [NSAttributedString.Key: Any] =
    [.font: NSFont.boldSystemFont(ofSize: 34), .foregroundColor: NSColor.white]
let label = NSAttributedString(string: "1", attributes: attrs)
let ts: NSSize = label.size()
label.draw(at: NSPoint(x: 30 + (d - ts.width) / 2, y: sz.height - 90 + (d - ts.height) / 2))
out.unlockFocus()

guard let tiff = out.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(3) }
try png.write(to: URL(fileURLWithPath: "/tmp/_out.png"))
// → wrote /tmp/_out.png bytes=37141，sips 读出 pixelWidth=1600 pixelHeight=1000 ✅
```

编译（零安装，CLT 自带 swiftc）：

```bash
swiftc annotator.swift -framework AppKit -o annotator
```

**路线 2：HTML + Chrome headless**——适合"编号 + 一整段说明文字"的富标注

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu   --hide-scrollbars --screenshot=out.png --window-size=820,540 file:///tmp/anno.html
# → 820×540 PNG，徽章位置像素 = 白（数字笔画）/ 背景 = 原图蓝 ✅
```

HTML 骨架（编号徽章用绝对定位 div）：

```html
<div class="wrap"><img src="file:///shot.png">
  <div class="b b1">1</div><div class="b b2">2</div></div>
<style>
.b{position:absolute;width:34px;height:34px;border-radius:50%;background:#e11d48;color:#fff;
   font:bold 22px/34px Helvetica;text-align:center}
.b1{left:60px;top:40px} .b2{left:300px;top:200px}
</style>
```

**路线 3：ImageMagick 命令行**——只有机器上已经装了才用（公司机大概率没有）

```bash
magick shot.png -font /System/Library/Fonts/Helvetica.ttc -fill red -stroke white -strokewidth 3   -pointsize 40 -gravity northwest -draw "circle 60,60 60,25"   -fill white -stroke none -annotate +50+78 "1" out.png
# → 实测圆点像素 srgb(255,0,0) ✅
# ⚠️ 坑：不加 -font 路径会报 "unable to read font `'"
```

## 4. 系统自带能力盘点（哪些能白嫖，哪些不能）

| 能力 | 入口 | 能否自动编号 | 依赖权限 | 评价 |
|---|---|---|---|---|
| 区域截图 → 剪贴板 | **⌃⇧⌘4** | ✗（只是拿到图） | 无（系统进程） | ⭐ 首选交接通道 |
| 全屏截图 → 剪贴板 | ⌃⇧⌘5 | ✗ | 无 | 备选 |
| 区域截图 → 落盘 | ⇧⌘4 | ✗ | 无 | 备选通道（文件监听） |
| 截图/录屏控制条 | ⇧⌘5 | ✗ | 无 | 里面有**选区 + 标注工具栏**（文字/形状/笔/荧光笔/放大镜/尺子） |
| 控制条里的"文字"工具 | 手打 | 手动输入数字 | 无 | **0 安装兜底**：点文字框→敲 1/2/3 |
| Preview 标注 | 打开 PNG → 标记 | 手动输入数字 | 无 | 兜底，比工具栏慢 |
| 系统设置 → 键盘快捷键 → App 快捷键 | 绑定到"快捷指令" | — | 无 | ⭐ **一键触发的正解** |
| 快捷指令（Shortcuts.app） | "Run Shell Script" 调我们的二进制 | 由我们的工具负责 | 无 | ⭐ 触发层 |
| Automator | 同上（老派） | 同上 | 无 | 备选，Shortcuts 已取代 |
| AppleScript 模拟按键 | `System Events keystroke` | — | **辅助功能（被拒）** | ❌ 不可用 |
| `screencapture -i` 交互选择 | CLI | — | **屏幕录制（被拒）** | ❌ 静默失败 |
| `screencapture -R` 重复上次区域 | CLI + `defaults` | — | 屏幕录制 | ❌ 同上（但 `last-selection` 值得记住） |
| Chrome headless 渲染 | CLI | ✅ CSS 自由画 | 无 | 适合富文本标注 |

**结论：系统能力里能"白嫖"的只有截图和图片的搬运；编号必须由我们自己的程序画。**

## 5. 四个候选方案

### 方案 A：纯手动（0 安装，0 开发）

⌃⇧⌘4 框选 → 系统工具栏 → 文字工具 → 手打 `1`、`2`、`3`。

- 优点：立刻可用，不碰权限，不装东西。
- 缺点：每个编号要"点一下 + 敲一下"，3 个编号 ≈ 10~15 秒；编号位置不能微调。
- 定位：**兜底**，不是目标。

### 方案 B：剪贴板 + 自建标注器（推荐主线）

⌃⇧⌘4（截图进剪贴板）→ 触发标注器 → 拖框自动编号 → 导出。

- 交接靠**剪贴板**，这是关键设计：读剪贴板**不需要屏幕录制权限**，绕开了 MDM 封禁。
- 标注器用 Swift/AppKit 写，零第三方依赖，CLT 直接编译。
- 触发靠**快捷指令绑定系统快捷键**（不依赖辅助功能权限）。

### 方案 C：监听截图落盘目录

⇧⌘4 框选 → 文件落到 `~/Pictures/Screenshots/Screenshot <时间戳>.png` → 标注器监听该目录的新文件。

- 优点：不碰剪贴板，用户体验更"原生"（截图后自动弹标注窗）。
- 坑：① 目录里混着手机照片（实测），必须**按文件名模式 + mtime** 过滤；② 弹窗时机要跟系统截图的保存动作对齐，有竞态；③ 目录位置由 `defaults read com.apple.screencapture` 决定，不保证固定。

### 方案 D：HTML/Chrome 富标注（编号 + 说明文字）

标注器 = 生成 HTML（图 + 编号徽章 + 编号对应的说明列表）→ Chrome headless 截图 → PNG。

- 优点：文字排版自由，能做"1️⃣ 登录框 2️⃣ 验证码 3️⃣ 提交按钮"这种带说明的图；实现成本低（就是拼 HTML）。
- 缺点：需要点选位置（不能"拖框"），交互不如 AppKit；依赖 Chrome 存在（属于已有 app，不是新装）。

## 6. 交互设计建议（如果要做得顺手）

### 标注范式

| 范式 | 描述 | 适用 |
|---|---|---|
| **A. 框 + 徽章** | 拖一个矩形 → 框左上角自动贴红色圆形徽章，序号自增 `①②③` | "指出 3 个关键元素"（用户原始诉求） |
| **B. 点 + 徽章** | 在图上点一下 → 就地出现徽章，序号自增 | 精确定位，不需要框 |
| **C. 引线 + 标签** | 从元素拖一条引线到标签框，标签里输入说明文字 | 元素密集、需要文字说明 |

建议 **A 为默认**，B/C 作为可切换模式。

### 建议快捷键（标注窗口内）

| 键 | 功能 |
|---|---|
| 拖拽 | 框选区域，自动生成下一个编号 |
| `Backspace` | 撤销最后一个框 |
| `R` | 清空所有标注 |
| `1`~`9` | 直接跳到/添加第 n 个编号 |
| `Enter` | 保存 PNG 到目录 |
| `⇧Enter` | 保存并复制到剪贴板（方便粘到 IM/文档） |
| `Esc` | 取消 |

### 输出约定

```text
~/Desktop/shot-20260928-084800.png        ← 最终图（带编号）
~/Desktop/shot-20260928-084800.raw.png    ← 原始图（重标不用重截）
```

## 7. 公司机上必须重跑的探针（30 秒）

```bash
# 1) 终端能不能自己抓屏？（能 → 方案可以升级为"工具自己截 + 原地浮窗标注"，体验最好）
screencapture -x /tmp/probe.png && ls -l /tmp/probe.png

# 2) 剪贴板通道（这是推荐路线的地基，必须通）
#    手动按 ⌃⇧⌘4 框选一块 → 然后：
osascript -e 'clipboard info' | tr ',' '\n' | grep -i png

# 3) 模拟按键（决定能不能做"脚本一键触发"）
osascript -e 'tell application "System Events" to keystroke "a"' 2>&1 | head -2

# 4) 编译器在不在
xcode-select -p && swiftc --version

# 5) 系统截图落盘位置
defaults read com.apple.screencapture | head -20
```

判定规则：

- 探针 1 **通** → 可以做"工具直接抓屏 + 原地浮窗标注"（CleanShot 那种体验），不再依赖剪贴板。
- 探针 1 **不通** + 探针 2 **通** → 走方案 B（剪贴板交接），**这是最可能的结果**。
- 探针 2 也不通 → 只能退到方案 A（手打编号）或方案 C（文件监听）。

## 8. 风险清单

1. **权限不可控**：屏幕录制/辅助功能权限由 MDM 决定，随时可能被收回 → 工具必须**运行时探测**并优雅降级（探针 1 的检查逻辑直接写进工具启动流程）。
2. **静默失败坑**：`screencapture -i` 无权限时 `exit 0` 但无文件；`osascript keystroke` 报 1002。任何自动化都要"验产物"而不是"看 exit code"。
3. **剪贴板覆盖**：读剪贴板会清掉用户原本复制的内容；建议读入后**立刻把原剪贴板内容备份**（或只取 PNG 类型再放回）。
4. **Retina 与多屏**：逻辑点 vs 物理像素 2x；两台显示器缩放不同（5K@2x + UWQHD@1x）→ 徽章尺寸、线宽、坐标换算要按**图像像素尺寸**算，而不是按屏幕点数算。
5. **代码审计**：自编二进制可能被安全团队问"为什么自己截屏" → 准备好说明：只读剪贴板/指定目录，不联网、不常驻。
6. **数据不出机**：整个流程本地完成，不上传任何图片（若涉及业务截图，这点需向合规确认）。
7. **别装第三方**：Python 路线（`pip install pillow`）在公司机基本走不通；ImageMagick 同理。**唯一稳定的是 Swift + 系统框架**。

## 9. 分阶段落地路线（待你确认后执行）

| 阶段 | 交付物 | 工作量 | 前置 |
|---|---|---|---|
| M0 | 探针脚本在公司机跑一遍，出"权限结论表" | 10 min | 无 |
| M1 | 最小标注器：读剪贴板 → 拖框 → 编号 → 存 PNG（Swift，~200 行） | 半天 | M0 |
| M2 | 增强：多屏/Retina 坐标、撤销、剪贴板回写、说明文字、HTML 富标注模式 | 1~2 天 | M1 |
| M3 | 触发层：快捷指令 + 系统快捷键绑定 + 可选菜单栏常驻 | 半天 | M2 |
| M4 | （仅当 M0 探针 1 通过）原地浮窗模式：直接抓屏、框选即标 | 1 天 | 权限 |

## 10. 与既有笔记的关系

- [smartshot.md](knowledge/macos/capture/smartshot.md) 提出了"`screencapture -i` + Pillow 画红框"的方案。**实测该方案在受限机器上不成立**（无屏幕录制权限 / 无第三方 pip 包）。
- 它提出的 Swift/AppKit 方向是**对的**，本文补充了：交接通道设计、权限探测、剪贴板 API 坑、Retina/多屏坐标、触发层解法。

## 附录：命令速查

```bash
# 系统截图（原生，零依赖）
⌃⇧⌘4   区域 → 剪贴板      ⇧⌘4  区域 → 文件      ⇧⌘5  控制条

# 读取剪贴板图（无需权限）
osascript -e 'clipboard info' | tr ',' '\n' | grep -i png
swiftc annotator.swift -framework AppKit -o annotator && ./annotator

# 系统里"上次框选矩形"（可用于 -R 复用区域）
defaults read com.apple.screencapture | grep -A5 last-selection

# 权限自检
screencapture -x /tmp/probe.png && ls -l /tmp/probe.png
osascript -e 'tell application "System Events" to keystroke "a"' 2>&1 | head -2

# 编译产物自检
sips -g pixelWidth -g pixelHeight out.png
```
