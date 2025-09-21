

## **问题分析**

  

在 macOS 上，系统自带的 /bin/bash 版本是 **3.2.x**，这是因为 Apple 出于 GPLv3 许可证的原因，不再更新系统内置的 Bash。

如果你通过 **Homebrew** 安装了新版 Bash（比如 /opt/homebrew/bin/bash），那么你会发现：

- 默认调用 bash 仍然会使用 /bin/bash
    
- 脚本中写 #!/bin/bash 也会走系统版本
    
- 新 Bash 存在但不会自动替换系统 Bash
    

  

所以需要手动配置，让系统层面能够使用 Bash 5.x。

---

## **解决方案**

  

### **方法一：修改默认登录 Shell（推荐）**

1. 将新版本 bash 加入允许列表：
    

```
sudo bash -c 'echo /opt/homebrew/bin/bash >> /etc/shells'
```

1.   
    
2. 修改用户默认 shell：
    

```
chsh -s /opt/homebrew/bin/bash
```

2.   
    
3. 验证：
    

```
echo $SHELL
# 输出应为 /opt/homebrew/bin/bash
bash --version
```

  

  

这样你打开终端时默认就是 Bash 5.x。

---

### **方法二：调整 PATH 优先级**

  

在 ~/.bash_profile 或 ~/.zshrc（如果你用 zsh 作为 login shell）里加上：

```
export PATH="/opt/homebrew/bin:$PATH"
```

这样命令行执行 bash 时会优先用新版本。

不过要注意：脚本里写 #!/bin/bash 还是会走系统的 /bin/bash。

---

### **方法三：修改脚本 Shebang**

  

如果你控制脚本文件，可以在文件头改成：

```
#!/usr/bin/env bash
```

这样会根据 PATH 里优先级找到 bash，从而用到 Homebrew 的版本。

---

## **注意事项**

- **不建议直接替换 /bin/bash**，因为 macOS 系统更新可能会覆盖或者引起系统脚本不兼容。
    
- 如果你需要系统层面脚本都能跑新版本，**推荐方法一（修改默认登录 Shell）+ 方法三（改 Shebang 用 env）** 结合使用。
    
- 你可能还会遇到 macOS 默认用 **zsh** 作为登录 shell（Catalina 以后），这时你要注意 zsh 调用 bash 的逻辑是否符合你的 PATH 配置。
    

---

要不要我帮你写一个 **自动化脚本**，一步到位帮你配置好默认 shell，并把 /usr/bin/env bash 替换进你项目里的脚本 shebang？

```bash
#!/bin/bash
#
# macOS Bash 升级与脚本修复工具
# 功能:
# 1. 添加 Homebrew Bash 到 /etc/shells
# 2. 修改用户默认 Shell
# 3. 批量替换脚本 shebang -> #!/usr/bin/env bash

BREW_BASH="/opt/homebrew/bin/bash"
TARGET_DIR="${1:-$HOME/projects}"   # 默认扫描 ~/projects，可以传参指定

echo ">>> 检查 Homebrew Bash 是否存在..."
if [ ! -x "$BREW_BASH" ]; then
  echo "错误: $BREW_BASH 未找到，请先执行: brew install bash"
  exit 1
fi

echo ">>> 将 $BREW_BASH 添加到 /etc/shells..."
if ! grep -q "$BREW_BASH" /etc/shells; then
  echo "$BREW_BASH" | sudo tee -a /etc/shells
fi

echo ">>> 修改当前用户默认 Shell..."
chsh -s "$BREW_BASH"

echo ">>> 当前 shell:"
echo $SHELL
$SHELL --version

echo ">>> 开始扫描并修复脚本 shebang..."
find "$TARGET_DIR" -type f -perm +111 -exec sed -i.bak '1s|^#!/bin/bash|#!/usr/bin/env bash|' {} \;

echo ">>> 替换完成 (已生成 .bak 备份文件)"
```