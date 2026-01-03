- `brew install font-hack-nerd-font`
```bash
==> Fetching downloads for: font-hack-nerd-font
✔︎ Cask font-hack-nerd-font (3.4.0)                                                                                                                           [Verifying    18.0MB/ 18.0MB]
==> Fetching downloads for: font-hack-nerd-font
✔︎ Cask font-hack-nerd-font (3.4.0)                                                                                                                           [Verifying    18.0MB/ 18.0MB]
==> Upgrading 1 outdated package:
font-hack-nerd-font 3.3.0 -> 3.4.0
==> Upgrading font-hack-nerd-font
==> Purging files for version 3.4.0 of Cask font-hack-nerd-font
Error: font-hack-nerd-font: It seems the Font source '/Users/lex/Library/Fonts/HackNerdFont-Bold.ttf' is not there.
➜  Downloads brew install font-hack-nerd-font
==> Fetching downloads for: font-hack-nerd-font
✔︎ Cask font-hack-nerd-font (3.4.0)                                                                                                                           [Verifying    18.0MB/ 18.0MB]
==> Fetching downloads for: font-hack-nerd-font
✔︎ Cask font-hack-nerd-font (3.4.0)                                                                                                                           [Verifying    18.0MB/ 18.0MB]
==> Upgrading 1 outdated package:
font-hack-nerd-font 3.3.0 -> 3.4.0
==> Upgrading font-hack-nerd-font
==> Purging files for version 3.4.0 of Cask font-hack-nerd-font
Error: font-hack-nerd-font: It seems the Font source '/Users/lex/Library/Fonts/HackNerdFont-Bold.ttf' is not there.
➜  Downloads 
```
- need uninstall
- `brew uninstall --cask --force font-hack-nerd-font`
```bash
➜  Downloads brew uninstall --cask --force font-hack-nerd-font

==> Uninstalling Cask font-hack-nerd-font
==> Purging files for version 3.3.0 of Cask font-hack-nerd-font
```

install again
`brew install --cask font-hack-nerd-font`

```bash
Warning: formula.jws.json: update failed, falling back to cached version.                                                                                    [Downloading  32.2MB/-------]
Warning: cask.jws.json: update failed, falling back to cached version.                                                                                       [Downloading  15.1MB/-------]
✔︎ JSON API formula.jws.json                                                                                                                                  [Downloaded   32.2MB/ 32.2MB]
✔︎ JSON API cask.jws.json                                                                                                                                     [Downloaded   15.1MB/ 15.1MB]
==> Downloading https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/Hack.zip
Already downloaded: /Users/lex/Library/Caches/Homebrew/downloads/d810cc8816833dad12eec378924f5b2a95554a650a2b1bd44fb5669cfb3b1348--Hack.zip
==> Installing Cask font-hack-nerd-font
==> Moving Font 'HackNerdFont-Bold.ttf' to '/Users/lex/Library/Fonts/HackNerdFont-Bold.ttf'
==> Moving Font 'HackNerdFont-BoldItalic.ttf' to '/Users/lex/Library/Fonts/HackNerdFont-BoldItalic.ttf'
==> Moving Font 'HackNerdFont-Italic.ttf' to '/Users/lex/Library/Fonts/HackNerdFont-Italic.ttf'
==> Moving Font 'HackNerdFont-Regular.ttf' to '/Users/lex/Library/Fonts/HackNerdFont-Regular.ttf'
==> Moving Font 'HackNerdFontMono-Bold.ttf' to '/Users/lex/Library/Fonts/HackNerdFontMono-Bold.ttf'
==> Moving Font 'HackNerdFontMono-BoldItalic.ttf' to '/Users/lex/Library/Fonts/HackNerdFontMono-BoldItalic.ttf'
==> Moving Font 'HackNerdFontMono-Italic.ttf' to '/Users/lex/Library/Fonts/HackNerdFontMono-Italic.ttf'
==> Moving Font 'HackNerdFontMono-Regular.ttf' to '/Users/lex/Library/Fonts/HackNerdFontMono-Regular.ttf'
==> Moving Font 'HackNerdFontPropo-Bold.ttf' to '/Users/lex/Library/Fonts/HackNerdFontPropo-Bold.ttf'
==> Moving Font 'HackNerdFontPropo-BoldItalic.ttf' to '/Users/lex/Library/Fonts/HackNerdFontPropo-BoldItalic.ttf'
==> Moving Font 'HackNerdFontPropo-Italic.ttf' to '/Users/lex/Library/Fonts/HackNerdFontPropo-Italic.ttf'
==> Moving Font 'HackNerdFontPropo-Regular.ttf' to '/Users/lex/Library/Fonts/HackNerdFontPropo-Regular.ttf'
🍺  font-hack-nerd-font was successfully installed!
```

Ghostty setting 
```
font-family = "ZedMono NFM Extd"

font-style-bold = "Medium"
font-style-bold-italic = "Medium Italic"
font-size = 13.4
font-thicken = true
grapheme-width-method = "unicode"

adjust-cell-width = -5%
palette = 0=#212733
palette = 1=#f08778
palette = 2=#53bf97
palette = 3=#fdcc60
palette = 4=#60b8d6
palette = 5=#ec7171
palette = 6=#98e6ca
palette = 7=#fafafa
palette = 8=#686868
palette = 9=#f58c7d
palette = 10=#58c49c
palette = 11=#ffd165
palette = 12=#65bddb
palette = 13=#f17676
palette = 14=#9debcf
palette = 15=#ffffff
background = #1f2430
foreground = #cbccc6

selection-invert-fg-bg = true
cursor-style = "bar"
cursor-style-blink = true
scrollback-limit = 100000
window-padding-x = 20
window-padding-y = 2,10
window-save-state = "always"

copy-on-select = clipboard

command = "/usr/local/bin/zsh"
working-directory = "/Users/lex/git/knowledge"

```

How to setting 

现在问题只剩下 **Ghostty 该如何正确引用 Hack Nerd Font**。

下面我按 **结论 → 推荐配置 → 验证方法 → 常见坑** 的顺序来说明。

---

## 一、先给结论（最推荐的写法）

👉 **Ghostty 应该使用 `Hack Nerd Font Mono`，而不是普通的 `Hack Nerd Font`**

原因很简单：

- `*Mono*` = 等宽字体（终端必需）
    
- 普通 `Hack Nerd Font` 里包含比例字形，容易导致对齐问题
    

---

## 二、Ghostty 推荐配置（直接可用）

把你原来的配置：

```ini
font-family = "ZedMono NFM Extd"
font-style-bold = "Medium"
font-style-bold-italic = "Medium Italic"
```

改成👇 **Hack Nerd Font Mono 官方规范写法**：

```ini
font-family = "Hack Nerd Font Mono"

font-style-regular = "Regular"
font-style-bold = "Bold"
font-style-italic = "Italic"
font-style-bold-italic = "Bold Italic"

font-size = 13.4
font-thicken = true
grapheme-width-method = "unicode"
```

> ✅ 这是 **最稳妥、最不容易踩坑** 的配置

---

## 三、为什么这样写是“对的”（对应你安装的文件）

你安装的这些文件：

```text
HackNerdFontMono-Regular.ttf
HackNerdFontMono-Bold.ttf
HackNerdFontMono-Italic.ttf
HackNerdFontMono-BoldItalic.ttf
```

在 macOS 的 **Font PostScript / Family Name** 中对应的是：

|文件名|Ghostty 识别名|
|---|---|
|HackNerdFontMono-Regular.ttf|Regular|
|HackNerdFontMono-Bold.ttf|Bold|
|HackNerdFontMono-Italic.ttf|Italic|
|HackNerdFontMono-BoldItalic.ttf|Bold Italic|

Ghostty **不是按文件名匹配**，而是按 **字体内部 metadata** 匹配  
👉 所以写 `Medium` 是一定找不到的（Hack 没有 Medium）

---

## 四、如果你想确认字体名字（100%保险）

在 macOS 上可以这样查：

```bash
system_profiler SPFontsDataType | grep -A5 "Hack Nerd Font Mono"
```

你会看到类似：

```text
➜  ~ system_profiler SPFontsDataType | grep -A5 "Hack Nerd Font Mono"
          Full Name: Hack Nerd Font Mono Bold
          Family: Hack Nerd Font Mono
          Style: Bold
          Version: Version 3.003;[3114f1256]-release; ttfautohint (v1.7) -l 6 -r 50 -G 200 -x 10 -H 260 -D latn -f latn -m "Hack-Bold-TA.txt" -w G -W -t -X "";Nerd Fonts 3.4.0
          Vendor: Source Foundry
          Unique Name: Hack Nerd Font Mono Bold 3.4.0
          Designer: Source Foundry Authors
          Copyright: Copyright (c) 2018 Source Foundry Authors / Copyright (c) 2003 by Bitstream, Inc. All Rights Reserved.
          Outline: Yes
          Valid: Yes
          Enabled: Yes
--
          Full Name: Hack Nerd Font Mono Regular
          Family: Hack Nerd Font Mono
          Style: Regular
          Version: Version 3.003;[3114f1256]-release; ttfautohint (v1.7) -l 6 -r 50 -G 200 -x 10 -H 181 -D latn -f latn -m "Hack-Regular-TA.txt" -w G -W -t -X "";Nerd Fonts 3.4.0
          Vendor: Source Foundry
          Unique Name: Hack Nerd Font Mono Regular 3.4.0
          Designer: Source Foundry Authors
          Copyright: Copyright (c) 2018 Source Foundry Authors / Copyright (c) 2003 by Bitstream, Inc. All Rights Reserved.
          Outline: Yes
          Valid: Yes
          Enabled: Yes
--
          Full Name: Hack Nerd Font Mono Bold Italic
          Family: Hack Nerd Font Mono
          Style: Bold Italic
          Version: Version 3.003;[3114f1256]-release; ttfautohint (v1.7) -l 6 -r 50 -G 200 -x 10 -H 265 -D latn -f latn -m "Hack-BoldItalic-TA.txt" -w G -W -t -X "";Nerd Fonts 3.4.0
          Vendor: Source Foundry
          Unique Name: Hack Nerd Font Mono Bold Italic 3.4.0
          Designer: Source Foundry Authors
          Copyright: Copyright (c) 2018 Source Foundry Authors / Copyright (c) 2003 by Bitstream, Inc. All Rights Reserved.
          Outline: Yes
          Valid: Yes
          Enabled: Yes
--
          Full Name: Hack Nerd Font Mono Italic
          Family: Hack Nerd Font Mono
          Style: Italic
          Version: Version 3.003;[3114f1256]-release; ttfautohint (v1.7) -l 6 -r 50 -G 200 -x 10 -H 145 -D latn -f latn -m "Hack-Italic-TA.txt" -w G -W -t -X "";Nerd Fonts 3.4.0
          Vendor: Source Foundry
          Unique Name: Hack Nerd Font Mono Italic 3.4.0
          Designer: Source Foundry Authors
          Copyright: Copyright (c) 2018 Source Foundry Authors / Copyright (c) 2003 by Bitstream, Inc. All Rights Reserved.
          Outline: Yes
          Valid: Yes
          Enabled: Yes

Family: Hack Nerd Font Mono
Style: Regular
Style: Bold
Style: Italic
Style: Bold Italic
```

👉 这些 `Style:` 后面的名字，就是 **Ghostty 能用的值**

---

## 五、常见错误总结（你刚好踩过）

### ❌ 错误 1：用非 Mono 版本

```ini
font-family = "Hack Nerd Font"   # 不推荐
```

### ❌ 错误 2：用不存在的 style

```ini
font-style-bold = "Medium"       # Hack 没有 Medium
```

### ❌ 错误 3：以为 Ghostty 认文件名

```ini
font-style-bold = "HackNerdFontMono-Bold.ttf"  # ❌ 完全不认
```

---

## 六、如果你想要更 Nerd / 更 Powerline 稳定

你可以额外验证图标是否正常（在 Ghostty 里）：

```bash
echo -e "\uf115  \uf120  \uf121  \ue0b0  \ue0b2"
```

如果 Powerline 分隔符、Devicons 都是正常的  
👉 说明 **Hack Nerd Font Mono 已完全生效**

---

## 七、总结一句话

> **Ghostty + Nerd Fonts：永远优先用 `*Nerd Font Mono*`，style 用 `Regular / Bold / Italic / Bold Italic`，不要自己发明名字**

如果你愿意，下一步我可以帮你：

- 对比 **Hack Nerd Font Mono vs JetBrainsMono Nerd Font**
    
- 或给你一份 **Ghostty + zsh + Starship 的完整字体/图标最佳实践配置**



/Users/lex/Library/Application Support/com.mitchellh.ghostty/config:4:font-style-regular: unknown field
```bash
ghostty +show-config | grep font
font-family = Hack Nerd Font Mono
font-family-bold = Hack Nerd Font Mono
font-family-italic = Hack Nerd Font Mono
font-family-bold-italic = Hack Nerd Font Mono
font-style-bold = Bold
font-style-italic = Italic
font-style-bold-italic = Bold Italic
font-size = 13.4
font-thicken = true
```
这个报错信息本身已经把**问题点得非常准了**：

```
font-style-regular: unknown field
```

👉 **Ghostty 的配置里根本没有 `font-style-regular` 这个字段**，所以解析时直接报错。

下面我一步一步帮你把 **Hack Nerd Font** 在 Ghostty 里正确配置好。

---

## 一、先明确 Ghostty 的字体配置规则（重点）

Ghostty 的设计是：

- **`font-family` 决定整个字体家族**
    
- **Regular / Bold / Italic / Bold Italic 是自动匹配的**
    
- ❌ 不支持 `font-style-regular`
    
- ❌ 也不需要你手动指定 `Regular`
    

Ghostty **只支持下面这些字段**（和你这个问题相关的）：

|配置项|是否支持|
|---|---|
|`font-family`|✅|
|`font-style-bold`|✅|
|`font-style-italic`|✅|
|`font-style-bold-italic`|✅|
|`font-style-regular`|❌ **不存在**|

---

## 二、你现在安装的字体，应该怎么选？

你现在系统里有 **三套 Hack Nerd Font**：

```
HackNerdFont-*.ttf        → 等宽（推荐终端用）
HackNerdFontMono-*.ttf   → 强制 mono（字形更紧）
HackNerdFontPropo-*.ttf  → 非等宽（不适合终端）
```

### 👉 **推荐 Ghostty 使用：**

```
Hack Nerd Font
```

而不是 `Mono` 或 `Propo`，除非你非常明确要用它们。

---

## 三、正确的 Ghostty 配置（可直接用）

### ✅ **最简 & 推荐配置**

```ini
font-family = "Hack Nerd Font"
font-size = 13.4
font-thicken = true
grapheme-width-method = "unicode"
```

💡 **重点**：

- `Regular / Bold / Italic` 会自动匹配
    
- 不写任何 `font-style-*` 是完全 OK 的
    

---

## 四、如果你想显式指定 Bold / Italic（可选）

只有在你**确认字体内部 Style 名称不标准**时才需要：

```ini
font-family = "Hack Nerd Font"

font-style-bold = "Bold"
font-style-italic = "Italic"
font-style-bold-italic = "Bold Italic"

font-size = 13.4
font-thicken = true
grapheme-width-method = "unicode"
```

⚠️ **注意**：

- Style 名称必须和 macOS「字体册」里显示的 **完全一致**
    
- `Medium`、`Book` 这类名字 **Hack Nerd Font 并不存在**
    

---

## 五、为什么你原来的 ZedMono 配置不能直接照搬？

你之前用的是：

```ini
font-family = "ZedMono NFM Extd"
font-style-bold = "Medium"
font-style-bold-italic = "Medium Italic"
```

原因是：

- **ZedMono** 的 Style 命名比较特殊（`Medium`）
    
- **Hack Nerd Font 是标准的 `Regular / Bold / Italic`**
    

👉 所以 **Style 名称不能复用**

---

## 六、快速自检（非常推荐）

如果你还不确定 Ghostty 实际识别到什么字体：

```bash
ghostty +show-config | grep font
```

或者直接在 Ghostty 里：

```bash
Cmd + Shift + P
→ Show Config
```

看有没有 fallback / warning。

---

## 七、结论（TL;DR）

✔ 删掉 `font-style-regular`  
✔ `font-family = "Hack Nerd Font"` 就够了  
✔ Hack Nerd Font 不存在 `Medium`  
✔ Ghostty 会自动匹配 Regular / Bold / Italic

---

如果你愿意，我可以帮你 **对照 macOS 字体册**，精确确认每个 Style 名称，或者帮你在 **Ghostty + Nerd Font + Powerline / Starship** 场景下做一套最佳配置。

