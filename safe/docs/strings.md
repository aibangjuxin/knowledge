你选中的这几行本质上都在用 **`strings` 命令做二进制静态分析**。  
它不是反编译工具，而是一个**从可执行文件 / 二进制文件里提取“可读字符串”**的小工具，常用于：

- 逆向工程

- 安全审计

- 排查应用是否包含某些 URL / Key / 协议字段

- 快速判断程序功能线索

下面分层讲清楚。

---

# 一、`strings` 命令的核心原理

## 1. 它做了什么？

`strings` 会：

> 在一个二进制文件中扫描连续的可打印字符，并把长度 ≥ N 的字符串输出。

例如在一个 `.app`、`.dylib`、`.so`、`.exe` 中：

- API URL

- WebSocket 路径

- Debug 文本

- 错误提示

- SQL 语句

- 文件路径

- 协议关键字

都会被直接暴露出来（如果开发者没有加密/混淆）。

---

## 2. 为什么在 macOS App 上有效？

macOS 的 `.app` 本质是一个目录：

```bash
Typeless.app/
 └── Contents/
     ├── MacOS/        # 可执行文件
     ├── Resources/    # 资源
     └── Frameworks/
```

很多 Electron / Node / C++ 程序会把：

- API 地址

- WebSocket 名称

- 事件名

- 功能关键字

直接打进二进制或 asar 包中。

`strings` 不解析语法，只扫字节流。

---

# 二、你看到的命令逐条解释

---

## 1. 查 API URL

```bash
strings app.asar | grep "api.typeless.com"
```

### 含义

|部分|作用|
|---|---|
|strings|提取可读字符串|
|app.asar|Electron 应用资源包|
|grep|过滤关键字|

### 能发现什么？

- REST API 地址

- WebSocket 域名

- CDN

- Debug Server

---

## 2. 查 WebSocket 协议字段

```bash
strings app.asar | grep "rt_voice_flow"
```

这通常是：

- WebSocket 事件名

- 内部协议名称

- 服务端路径

可以判断应用通信模式。

---

## 3. 查键盘监听 dylib

```bash
strings libKeyboardHelper.dylib | grep -i "key pressed"
```

这里是在原生库里找：

- 键盘 hook

- 事件监听

- CGEventTap

- KeyDown / KeyUp

---

# 三、`strings` 常用参数

---

## 1. 指定最小长度

```bash
strings -n 8 binary
```

只显示 ≥8 字符字符串，减少噪音。

---

## 2. 显示偏移量

```bash
strings -t x binary
```

输出十六进制偏移地址：

```
00001fa2 api.typeless.com
```

对逆向很有价值。

---

## 3. 指定编码

```bash
strings -e l binary
```

|参数|含义|
|---|---|
|s|ASCII|
|l|UTF-16 LE|
|b|UTF-16 BE|

很多 macOS 程序字符串是 UTF-16。

---

## 4. 组合 grep 精确过滤

```bash
strings app | grep -Ei "http|ws|token|key"
```

---

# 四、适用场景

---

## 安全审计

- 是否硬编码 Token

- 是否有测试接口

- 是否泄露密钥

---

## 网络分析

- API 域名

- WebSocket 路径

- GRPC 服务名

---

## 权限审计

- Accessibility

- ScreenCapture

- KeyHook

---

## 逆向分析前期

快速判断：

- 是 Electron？

- 用什么框架？

- 是否云端通信？

---

# 五、局限性

---

|限制|说明|
|---|---|
|无法反编译|只提字符串|
|无逻辑|看不到代码流程|
|易被混淆|加密后无效|
|噪音多|需 grep 过滤|

---

# 六、进阶组合（安全分析常用）

---

## 查 URL

```bash
strings binary | grep -E "http|https"
```

## 查权限

```bash
strings binary | grep -i "accessibility"
```

## 查加密关键词

```bash
strings binary | grep -Ei "aes|rsa|encrypt"
```

---

# 七、为什么它在 macOS 特别常用？

因为：

- `.dylib` 原生库

- Electron `app.asar`

- Swift/ObjC 字符串段

- 未混淆资源

几乎一定能扫出东西。

---

# 八、一句话总结

> `strings` 是“最低成本的二进制情报收集工具”，  
> 不懂逆向也能看出程序在“和谁说话、可能做什么”。

from x
<https://x.com/nanshanjukr>

核心结论

Typeless宣称具备“设备端历史记录”和“零数据保留”特性，但实际上所有语音数据都被发送到美国俄亥俄州的AWS服务器进行处理。本地没有任何语音识别模型。

如果仅此而已，它只是一个普通的“云端语音转文字服务”。问题在于其收集的数据范围远超语音本身。

调查内容

在macOS上对Typeless v0.9.3进行了二进制分析、网络通信调查、本地数据库分析以及原生库字符串分析。

已确认的事实

1. 语音处理100%在云端
    应用内不存在Whisper等任何STT模型。语音经Opus压缩后，通过WebSocket（wss://api.typeless.com/ws/rt_voice_flow）实时发送至AWS us-east-2区域的服务器。
    <http://api.typeless.com> → <http://565501648.us-east-2.elb.amazonaws.com>
    其官方隐私政策中确实写有“在我们的云端服务器实时处理”，因此不算说谎。但其营销中使用的“设备端”表述仅限于历史记录保存，具有相当大的误导性。

2. 收集语音之外的广泛数据
    通过分析本地SQLite数据库和原生库，确认其收集以下数据：
    - 正在浏览的网站完整URL（包括Gmail、Google Docs等）
    - 当前聚焦的应用名称、窗口标题
    - 屏幕上的文本（通过无障碍API递归收集的 `collectVisibleTexts` 函数）
    - 剪贴板的读写（甚至能处理密码管理器的TransientType）
    - 通过CGEventTap进行的系统级键盘输入监控
    - 浏览器DOM元素信息（支持Safari、Chrome、Edge、Firefox、Brave）
    - 用户编辑的文本内容（TrackEditTextService → sendTrackResultToServer）

3. 本地数据库明文存储个人信息
    `typeless.db` 中明文保存着语音识别结果文本、浏览URL、应用信息。一边宣称“零数据保留”，一边在本地留存了所有数据。语音文件（.ogg）也未被删除而残留。

4. 过度索取权限
    作为一个语音输入工具，除了麦克风，还要求屏幕录制、摄像头、蓝牙、无障碍权限。内部还集成了截图功能。

5. 公司透明度几乎为零
    - 服务条款和隐私政策中未提及法人名称。
    - 地址仅写“加利福尼亚州旧金山郡”（仅作为服务条款的管辖地）。
    - WHOIS信息为隐私保护状态（GoDaddy + Cloudflare）。
    - 无SOC2、ISO27001等安全审计的说明。
    - 唯一联系方式是 [email protected]。

技术依据（可复现）

任何人都可以通过以下命令进行验证：

```bash
# 网络通信目的地
nslookup http://api.typeless.com

# app.asar 内的API URL
strings /Applications/Typeless.app/Contents/Resources/app.asar | grep "http://api.typeless.com"

# WebSocket通信协议
strings /Applications/Typeless.app/Contents/Resources/app.asar | grep "rt_voice_flow"

# 键盘监控的原生库
strings /Applications/Typeless.app/Contents/Resources/lib/keyboard-helper/build/libKeyboardHelper.dylib | grep -i "key pressed"

# 屏幕文本收集
strings /Applications/Typeless.app/Contents/Resources/lib/context-helper/build/libContextHelper.dylib | grep -i "collectVisibleTexts"

# 本地数据库内容
sqlite3 ~/Library/Application\ Support/Typeless/typeless.db ".schema history"
```

问题所在

CGEventTap（键盘监控）+ 无障碍API（屏幕文本收集）+ 剪贴板访问。这三者的组合在技术上具备了与键盘记录器同等级的能力。

而用户正在将这些权限授予一个运营主体不明的服务。

为了提升语音输入精度而获取上下文信息（如正在使用的应用、输入框信息）本身是合理的设计。但当这些信息被发送到云端时，运营方的可信度和安全体系就至关重要。对于一家连法人名称都不公开的公司，是否值得托付这份信任，请各位自行判断。

替代方案

存在完全在本地运行的语音输入工具：

- Whisper.cpp / MLX Whisper（开源，完全本地，免费）
- macOS 内置语音输入（在Apple Silicon芯片上为设备端处理）
- Superwhisper（基于Whisper，面向Mac，但需自行验证）

总结

- Typeless的语音识别100%依赖云端处理（无本地模型）。
- 其技术架构具备收集语音之外屏幕文本、URL、键盘输入的能力。
- 运营主体不透明（未公开法人名称及地址）。
- 无安全审计证据。

正在使用的用户请在充分认识风险后做出
