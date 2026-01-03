#!/bin/bash
#
# macOS Bash 升级与脚本修复工具
# 功能:
# 1. 添加 Homebrew Bash 到 /etc/shells
# 2. 修改用户默认 Shell
# 3. 批量替换脚本 shebang -> #!/usr/bin/env bash

BREW_BASH="/opt/homebrew/bin/bash"
TARGET_DIR="${1:-$HOME/projects}" # 默认扫描 ~/projects，可以传参指定

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
