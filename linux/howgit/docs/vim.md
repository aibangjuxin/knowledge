在 Vim 中，复制和粘贴的行数限制主要与 `viminfo` 设置有关。默认情况下，Vim 对每个寄存器（register）保存的行数有限制，通常是 50 行或 10 KiB 的文本，这可能导致在跨文件粘贴时只粘贴出部分内容。

## 解决方案

要解决这个问题，可以通过以下方式调整 `viminfo` 设置：

1. **查看当前设置**：
   在 Vim 中输入以下命令查看当前的 `viminfo` 设置：
   ```
   :set viminfo?
   ```

2. **修改 `viminfo` 设置**：
   可以通过以下命令来修改 `viminfo` 设置，以增加寄存器保存的行数：
   ```
   :set viminfo='100,<1000,s100,h
   ```
   这里的 `<1000` 表示每个寄存器最多保存 1000 行。如果想要去掉这个限制，可以将 `<1000` 移除。

3. **在 `.vimrc` 中设置**：
   如果希望每次启动 Vim 时都应用这个设置，可以将其添加到你的 `.vimrc` 文件中：
   ```vim
   set viminfo='100,<1000,s100,h
   ```

4. **使用系统寄存器**：
   另一种方法是使用系统寄存器，通过在命令前加上 `"+` 来进行复制和粘贴，例如：
   ```
   "+300yy  // 复制 300 行
   "+p      // 粘贴
   ```

通过这些设置，您可以在 Vim 中有效地管理复制和粘贴的行数限制，确保在跨文件操作时不会丢失数据[1][2][3][4][5]。

Citations:
[1] https://stackoverflow.com/questions/3676855/vim-limited-line-memory
[2] https://superuser.com/questions/775421/vim-only-storing-first-50-lines-when-yanking-between-files
[3] https://groups.google.com/g/vim_use/c/WQdUy6HmtL8/m/vTp5bDetXMMJ
[4] https://unix.stackexchange.com/questions/279362/why-vim-is-pasting-50-lines-instead-of-96
[5] https://www.unix.com/unix-for-dummies-questions-and-answers/210359-there-limit-number-lines-copy-pasted-vi-editor.html


set nocompatible              " 不兼容模式
set viminfo='100,<1000,s100,h " 设置 viminfo 选项
syntax on                     " 启用语法高亮
set number                    " 显示行号




确保 Vim 支持剪贴板
首先，检查您的 Vim 是否支持剪贴板功能。可以在终端中运行以下命令：
bash
vim --version | grep clipboard

如果输出中包含 +clipboard，则表示支持。如果是 -clipboard，您可能需要安装支持剪贴板的 Vim 版本。


# for Alpine install gvim


