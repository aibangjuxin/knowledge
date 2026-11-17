# 分析 Antigravity.app：使用 strings 命令进行静态分析指南

本文档旨在指导你如何使用 `strings` 命令对 macOS 下的 `/Applications/Antigravity.app` 进行静态分析。通过这种方法，你可以提取出应用程序中包含的 URL、API 端点、错误信息等关键线索，从而了解其潜在的行为和通信目标。

---

## 一、 准备工作

在开始之前，请确保你已经安装了 macOS 的开发者工具（通常包含 `strings` 命令）。如果没有，可以通过在终端运行以下命令安装：

```bash
xcode-select --install
```

确认 `strings` 命令可用：

```bash
which strings
# 输出: /usr/bin/strings
```

---

## 二、 定位可执行文件

macOS 的应用程序（`.app`）实际上是一个文件夹（Bundle）。我们需要找到其中的核心二进制文件。

通常结构如下：
`/Applications/Antigravity.app/Contents/MacOS/Antigravity`

你可以使用 `ls` 命令确认其位置：

```bash
ls -F /Applications/Antigravity.app/Contents/MacOS/
```

如果看到名为 `Antigravity` 的文件（末尾带有 `*` 表示可执行），那就是我们的目标。

**注意**：有些应用可能是 Electron 应用，核心逻辑可能包裹在 `.asar` 文件中，路径通常在：
`/Applications/Antigravity.app/Contents/Resources/app.asar`

---

## 三、 执行分析步骤

我们将分步骤提取不同类型的信息。

### 1. 基础提取：查看所有字符串

直接运行 `strings` 命令会输出大量信息，建议输出到文件以便查看：

```bash
strings /Applications/Antigravity.app/Contents/MacOS/Antigravity > antigravity_strings.txt
```

### 2. 分析网络通信 (API & URL)

查找应用可能连接的服务器、API 接口或 WebSocket 地址。

```bash
# 查找 HTTP/HTTPS 链接
strings /Applications/Antigravity.app/Contents/MacOS/Antigravity | grep -Ei "http://|https://"

# 查找 WebSocket 链接
strings /Applications/Antigravity.app/Contents/MacOS/Antigravity | grep -Ei "ws://|wss://"

# 查找特定域名（假设你怀疑它连接到 google.com 或其他已知域名）
strings /Applications/Antigravity.app/Contents/MacOS/Antigravity | grep -i "google.com"
```

### 3. 查找敏感关键词

分析应用是否包含 Token、密钥或加密相关的关键词。

```bash
# 查找 Token, Key, Secret 等常见敏感词
strings /Applications/Antigravity.app/Contents/MacOS/Antigravity | grep -Ei "token|secret|api_key|password|auth"

# 查找加密算法相关线索
strings /Applications/Antigravity.app/Contents/MacOS/Antigravity | grep -Ei "aes|rsa|encrypt|decrypt|public_key|private_key"
```

### 4. 分析功能与权限线索

查看应用是否尝试请求系统权限或包含特定功能的描述。

```bash
# 查找与权限相关的字符串
strings /Applications/Antigravity.app/Contents/MacOS/Antigravity | grep -Ei "permission|access|contact|location|camera|microphone"

# 查找系统调用或框架引用（例如 Accessibility, ScreenCapture）
strings /Applications/Antigravity.app/Contents/MacOS/Antigravity | grep -Ei "accessibility|CGEvent|ScreenCapture"
```

---

## 四、 进阶技巧

### 1. 过滤短字符串

为了减少噪音，可以指定 `-n` 参数，只显示长度大于等于 N 的字符串（常用 8 或 10）。

```bash
# 只显示长度 >= 10 的字符串
strings -n 10 /Applications/Antigravity.app/Contents/MacOS/Antigravity | grep -Ei "http"
```

### 2. 指定编码格式

macOS 应用中可能包含 Unicode 字符串（如 UTF-16）。使用 `-e` 参数指定编码：

- `-e s`: ASCII (默认)
- `-e l`: UTF-16 Little Endian (常见于 Windows/Unicode)
- `-e b`: UTF-16 Big Endian

试着通过 UTF-16 扫描：

```bash
strings -e l /Applications/Antigravity.app/Contents/MacOS/Antigravity | grep -Ei "http"
```

### 3. 显示偏移量 (Offset)

如果你需要配合反汇编工具（如 Hopper 或 IDA）使用，可以显示字符串在文件中的偏移量：

```bash
# 输出十六进制偏移量
strings -t x /Applications/Antigravity.app/Contents/MacOS/Antigravity | grep "Upload"
```

---

## 五、 Electron 应用特别说明

如果 `Antigravity.app` 是基于 Electron 开发的（检查 `Contents/Frameworks` 下是否有 Electron Framework），你应该重点分析 `app.asar` 文件。

```bash
# 检查是否存在 app.asar
ls /Applications/Antigravity.app/Contents/Resources/app.asar

# 对 .asar 文件运行 strings
strings /Applications/Antigravity.app/Contents/Resources/app.asar | grep -Ei "http|https|ws|wss"
```

Electron 应用的源码（JS通常被混淆或压缩）都在 `app.asar` 中，`strings` 往往能发现大量未加密的配置信息和 API 地址。

---

## 六、 总结与下一步

通过以上步骤，你应该能生成一份关于 `Antigravity.app` 的“字符串情报”。

**你可以尝试回答以下问题：**
1.  它连接了哪些服务器？（分析 URL）
2.  它使用了哪些第三方服务？（如 AWS, Firebase, Sentry 等）
3.  它是否包含可疑的权限请求或关键字？（如 "upload", "track", "record"）

将发现的可疑字符串记录下来，可以作为进一步抓包分析（使用 Wireshark 或 Charles）或逆向工程的线索。
