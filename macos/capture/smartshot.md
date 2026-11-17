可以，而且**不需要安装第三方截图 App**。最适合你的方案是：

1. 用系统 `/usr/sbin/screencapture -i` 调出 macOS 原生区域选择。
2. 用户拖选区域后，保存原始 PNG。
3. 用脚本打开一个本地透明标注窗口。
4. 在标注窗口中拖出红色矩形，自动生成 `①、②、③...`。
5. 按 `Enter` 或 `S` 导出最终图片，按 `Esc` 取消。

这样只需要安装 Python 依赖，例如通过 Homebrew 安装 `Pillow`，不依赖第三方截图工具。macOS 原生的区域截图行为本身就是 `Shift-Command-4` 对应的选择区域流程；Apple 的 Preview 也支持对图片添加形状和文字标注。 [support.apple](https://support.apple.com/en-us/102646)

## 推荐实现方式

相比直接操作 Preview，自己写一个小工具更适合你的需求：

```text
系统截图选择区域
        │
        ▼
/usr/sbin/screencapture -i
        │
        ▼
临时 PNG
        │
        ▼
本地标注窗口
        │
        ├── 拖动：画红色方框
        ├── 松开：自动添加 ①、②、③
        ├── Backspace：删除最后一个
        ├── R：重置全部标记
        └── Enter / S：保存
```

关键点是：不要尝试自己实现 macOS 屏幕捕获。直接调用系统的 `/usr/sbin/screencapture`，可以最大限度保持和系统截图一致。

## 安装依赖

如果公司电脑允许通过 Homebrew 安装 Python：

```bash
brew install python
python3 -m pip install --user pillow
```

建议单独创建虚拟环境：

```bash
mkdir -p ~/bin/smartshot
cd ~/bin/smartshot

python3 -m venv .venv
.venv/bin/pip install pillow
```

不需要安装 Tk、Qt 或其他 GUI 框架。macOS 自带 Python 通常不再推荐作为开发环境，但 Homebrew Python 配合 Tk 可能会遇到 GUI 依赖问题。下面这个版本使用 macOS 自带的 AppleScript 选择截图，再用 Pillow 生成标注图片，避免额外 GUI 框架。

## 第一版：自动截图并手动输入坐标

先给你一个**最稳、最容易在公司限制环境运行**的版本。它完成：

- 调用系统区域截图。
- 读取截图。
- 通过终端输入矩形坐标。
- 自动生成红色方框。
- 自动添加 `①`、`②`、`③`。
- 支持多个框。
- 自动保存最终图片。

保存为 `smartshot.py`：

```python
#!/usr/bin/env python3

import os
import sys
import time
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


TMP_DIR = Path.home() / ".smartshot"
TMP_DIR.mkdir(exist_ok=True)

raw_file = TMP_DIR / "raw.png"
output_file = Path.home() / "Desktop" / f"smartshot-{time.strftime('%Y%m%d-%H%M%S')}.png"


def take_screenshot():
    if raw_file.exists():
        raw_file.unlink()

    result = subprocess.run(
        ["/usr/sbin/screencapture", "-i", "-x", str(raw_file)],
        check=False,
    )

    if result.returncode != 0 or not raw_file.exists():
        print("截图已取消")
        sys.exit(1)


def get_font(size):
    candidates = [
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Arial.ttf",
    ]

    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass

    return ImageFont.load_default()


def marker_text(index):
    symbols = [
        "①", "②", "③", "④", "⑤",
        "⑥", "⑦", "⑧", "⑨", "⑩",
    ]

    if index <= len(symbols):
        return symbols[index - 1]

    return str(index)


def draw_marker(draw, x, y, index, font):
    text = marker_text(index)
    bbox = draw.textbbox((0, 0), text, font=font)
    width = bbox [support.apple](https://support.apple.com/guide/preview/annotate-an-image-prvw1501/mac) - bbox[0]
    height = bbox [support.apple](https://support.apple.com/guide/preview/take-a-picture-of-your-screen-prvw1092/mac) - bbox [support.apple](https://support.apple.com/en-us/102646)

    padding = 7
    radius = max(width, height) // 2 + padding

    center_x = x + radius
    center_y = y + radius

    draw.ellipse(
        (
            center_x - radius,
            center_y - radius,
            center_x + radius,
            center_y + radius,
        ),
        fill="red",
        outline="white",
        width=2,
    )

    draw.text(
        (
            center_x - width / 2,
            center_y - height / 2 - bbox [support.apple](https://support.apple.com/en-us/102646),
        ),
        text,
        font=font,
        fill="white",
    )


def ask_rectangles(image):
    print()
    print(f"图片尺寸：{image.width} x {image.height}")
    print("请输入标注框坐标：x1,y1,x2,y2")
    print("例如：100,200,500,400")
    print("直接回车结束输入")
    print()

    rects = []

    while True:
        value = input(f"框 {len(rects) + 1}: ").strip()

        if not value:
            break

        try:
            x1, y1, x2, y2 = [
                int(part.strip()) for part in value.split(",")
            ]

            x1, x2 = sorted((x1, x2))
            y1, y2 = sorted((y1, y2))

            x1 = max(0, min(image.width - 1, x1))
            x2 = max(0, min(image.width - 1, x2))
            y1 = max(0, min(image.height - 1, y1))
            y2 = max(0, min(image.height - 1, y2))

            if x2 - x1 < 5 or y2 - y1 < 5:
                print("矩形太小，请重新输入")
                continue

            rects.append((x1, y1, x2, y2))

        except ValueError:
            print("格式错误，请使用：x1,y1,x2,y2")


def annotate(image, rects):
    result = image.convert("RGBA")
    draw = ImageDraw.Draw(result)

    line_width = max(4, round(min(image.size) / 400))
    font_size = max(28, round(min(image.size) / 28))
    font = get_font(font_size)

    for index, (x1, y1, x2, y2) in enumerate(rects, start=1):
        draw.rectangle(
            (x1, y1, x2, y2),
            outline="red",
            width=line_width,
        )

        marker_x = max(0, x1 - font_size // 2)
        marker_y = max(0, y1 - font_size // 2)

        draw_marker(
            draw,
            marker_x,
            marker_y,
            index,
            font,
        )

    return result


def main():
    print("请拖动鼠标选择截图区域，按 Esc 可取消。")
    take_screenshot()

    image = Image.open(raw_file)
    rects = ask_rectangles(image)

    if not rects:
        print("没有添加标注，保留原始截图")
        image.save(output_file)
    else:
        result = annotate(image, rects)
        result.convert("RGB").save(output_file, quality=95)

    print()
    print(f"已保存：{output_file}")

    subprocess.run(["open", "-R", str(output_file)], check=False)


if __name__ == "__main__":
    main()
```

运行：

```bash
chmod +x smartshot.py
./smartshot.py
```

或者：

```bash
python3 smartshot.py
```

截图完成后，例如输入：

```text
框 1: 100,200,500,400
框 2: 600,300,900,500
框 3:
```

最终图片会保存到桌面，并自动在 Finder 中定位。

## 第二版：真正的拖动标注

上面的版本是为了先验证完整流程。你真正想要的是：

```text
选择截图区域
↓
直接在截图上拖动
↓
自动出现红框和 ①
↓
继续拖动
↓
自动出现红框和 ②
```

这个可以使用 macOS 自带的 `osascript` 创建一个临时 Cocoa 窗口，但代码会明显复杂一些，主要涉及：

- 读取 PNG 图片尺寸。
- 创建全屏透明窗口。
- 在窗口中显示截图。
- 监听鼠标按下、移动、释放。
- 将屏幕坐标转换成图片坐标。
- 处理 Retina 屏幕的缩放比例。
- 把红框和数字绘制到原始图片。
- 窗口退出后保存最终 PNG。

更推荐用 **Swift + AppKit** 实现这一版，而不是 Python。原因是 AppKit 能更自然地处理：

- 鼠标事件。
- Retina 坐标。
- 多显示器。
- 全屏透明窗口。
- 菜单栏图标或快捷键。
- macOS 的权限和窗口行为。

而且 Swift 编译器通常随 Xcode Command Line Tools 提供：

```bash
xcode-select --install
```

不需要安装第三方 GUI 库。

## 更适合你的 Swift 结构

建议项目目录如下：

```text
smartshot/
├── SmartShot.swift
├── smartshot
└── README.md
```

编译：

```bash
swiftc SmartShot.swift \
  -framework Cocoa \
  -framework AppKit \
  -o smartshot
```

运行：

```bash
./smartshot
```

内部流程可以是：

```swift
let screenshotPath = temporaryPath()

run(
    "/usr/sbin/screencapture",
    arguments: ["-i", "-x", screenshotPath]
)

let image = NSImage(contentsOfFile: screenshotPath)

let overlayWindow = AnnotationWindow(image: image)

overlayWindow.runModal()

saveAnnotatedImage()
```

标注窗口的鼠标逻辑：

```text
mouseDown:
    startPoint = event.locationInWindow
    currentRect = empty

mouseDragged:
    currentRect = rectangle(startPoint, currentPoint)
    redraw()

mouseUp:
    append currentRect
    markerIndex += 1
    redraw()
```

绘制逻辑：

```text
draw image
for each rectangle:
    draw red outline
    draw red circle
    draw white number
```

建议快捷键：

| 快捷键          | 功能           |
| --------------- | -------------- |
| `Esc`           | 取消整个操作   |
| `Backspace`     | 删除最后一个框 |
| `R`             | 清除全部标注   |
| `Enter`         | 保存并退出     |
| `S`             | 保存           |
| `Shift + Enter` | 保存到剪贴板   |

## 需要注意的系统权限

调用 `/usr/sbin/screencapture` 时，macOS 可能要求终端获得“屏幕录制”权限。可以到：

```text
系统设置
→ 隐私与安全性
→ 屏幕录制
→ Terminal 或 iTerm
```

如果你的工具由 Terminal 启动，那么通常需要给 Terminal 授权，而不是只给编译出来的二进制授权。

公司设备如果由 MDM 管理，可能无法修改这个权限。这种情况下，系统截图快捷键能不能工作，是最直接的验证方法。

## 我建议的最终体验

你的工具最后可以做成下面这样：

```bash
smartshot
```

工作流程：

1. 运行命令。
2. 屏幕变成系统原生截图选择状态。
3. 鼠标拖动选择区域。
4. 自动进入标注模式。
5. 在截图上拖动一个区域。
6. 自动出现红色矩形和 `①`。
7. 再拖动第二个区域，出现 `②`。
8. 按 `Enter` 保存。
9. 自动打开生成的图片。

建议输出两个文件：

```text
~/Desktop/smartshot-20260928-084800.png
~/Desktop/smartshot-20260928-084800.raw.png
```

其中：

- `.raw.png` 是没有标注的原始截图。
- `.png` 是带红框和编号的最终截图。

这样即使编号位置不满意，也不用重新截图。

从实现角度看，**第一版可以马上用 Python + Pillow 完成**；如果你希望达到“像系统截图一样拖动标注”的体验，建议第二步改成 **Swift/AppKit**。macOS Preview 也能手动画形状和文字，但它更适合偶尔编辑；你这个需求非常固定，做成一个专用本地命令行工具会更快、更可靠。 [support.apple](https://support.apple.com/guide/preview/annotate-an-image-prvw1501/mac)
