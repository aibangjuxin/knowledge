brew install duti
brew install duti

在 macOS 命令行中设置文件的默认打开方式，并没有一个系统自带的简单命令（如 `set-default`），但我们可以通过一款非常强大的第三方工具 **`duti`** 来实现。

`duti` 是 macOS 社区公认的通过命令行管理文件关联的标准方案。

---

### 第一步：安装 `duti`

你可以通过 Homebrew 快速安装：

```bash
brew install duti

```

### 第二步：获取终端工具的 Bundle ID

在 macOS 中，`duti` 是通过 **Bundle Identifier**（包标识符）来识别软件的。

- **iTerm2**: `com.googlecode.iterm2`
- **自带终端 (Terminal)**: `com.apple.Terminal`
- **Warp**: `dev.warp.Warp-Stable`
- **VS Code**: `com.microsoft.VSCode`

如果你想确认某个 App 的 Bundle ID，可以使用以下命令：

```bash
osascript -e 'id of app "iTerm"'

➜  knowledge git:(main) osascript -e 'id of app "iTerm"'
com.googlecode.iterm2
➜  knowledge git:(main) ✗ osascript -e 'id of app "Warp"'
dev.warp.Warp-Stable


```

### 第三步：使用 `duti` 修改默认打开方式

`duti` 的命令语法是：`duti -s <BundleID> <扩展名> <角色>`

其中 **Role**（角色）通常设为 `all`（代表查看、编辑等所有操作）。

#### 常用配置示例

1. **设置所有 `.sh` 脚本默认用 iTerm2 打开：**

```bash
duti -s com.googlecode.iterm2 .sh all

```

2. **设置 `.command` 文件默认用 iTerm2 打开：**

```bash
duti -s com.googlecode.iterm2 .command all

```

3. **设置所有文本文件 (`.txt`) 默认用 VS Code 打开：**

```bash
duti -s com.microsoft.VSCode .txt all

```

---

### 进阶：如何批量设置？

如果你有一堆文件类型想修改，建议创建一个配置文件（例如 `~/.mimetypes`），内容如下：

```text
# BundleID            Extension   Role
com.googlecode.iterm2  .sh         all
com.googlecode.iterm2  .command    all
com.microsoft.VSCode   .json       all

```

然后运行：

```bash
duti ~/.mimetypes

```

### 验证是否生效

你可以通过 `duti -x` 命令来查询某个后缀名当前被谁接管：

```bash
duti -x sh

```

---

### 为什么不用原生命令？

macOS 的默认关联信息存储在系统的数据库中（Launch Services）。虽然可以通过修改 `~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist` 配置文件来实现，但那是加密的二进制格式，手动修改极易导致系统 UI 崩溃，**因此 `duti` 是目前最稳妥、最快捷的方案。**

**你是想把所有的脚本文件都改成用某个特定终端（如 iTerm2）打开吗？如果是的话，直接运行上面的第一条命令即可。**
