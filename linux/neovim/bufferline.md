for my mac 
Ctrl-h 可以切换回左侧导航栏目
Ctrl-l 可以切换到工作区
My Leader key is 空格 Space 
" 将领导键设置为空格键
let mapleader = " "

所以这里我先按空格
然后会有提示
比如切换窗口之类的



在 Vim 或 Neovim 中，`<Leader>` 是指领导键 (Leader key)，默认情况下为 `\` 键。但是您可以根据自己的偏好重新映射 Leader 键。

要重新映射 Leader 键，您可以在您的 Neovim 配置文件中添加以下内容:

```vim
" 将领导键设置为空格键
let mapleader = " "
```

或者在 Lua 配置中:

```lua
vim.g.mapleader = " "
```

上面的例子将 Leader 键映射为空格键。

因此，当您看到像 `<Leader>bh` 或 `<Leader>bn` 这样的快捷键映射时，它的含义是先按下您设置的 Leader 键，然后再按下 `b`、`h` 或 `n`。

例如，如果您将 Leader 键设置为空格键，那么:

- `<Leader>bh` 实际上就是 `<Space>bh`
- `<Leader>bn` 实际上就是 `<Space>bn

您可以根据自己的喜好和习惯来设置 Leader 键。一些流行的选择包括空格键、逗号键 (`,`) 或反斜杠键 (`\`)。


在 Neovim 中使用 `bufferline.nvim` 插件时，您可以使用以下快捷键快速在不同的缓冲区之间进行切换:

1. **使用键盘方向键:**
   - `<Left>` 或 `<C-h>`: 切换到左侧的缓冲区
   - `<Right>` 或 `<C-l>`: 切换到右侧的缓冲区

2. **使用快捷键跳转:**
   - `<Leader>bh` 或 `<Leader>bn`: 切换到上一个缓冲区
   - `<Leader>bl` 或 `<Leader>bp`: 切换到下一个缓冲区

3. **使用缓冲区索引号:**
   - `<Leader>b1`: 切换到第 1 个缓冲区
   - `<Leader>b2`: 切换到第 2 个缓冲区
   - ...

4. **使用缓冲区名称的模糊搜索:**
   - `<Leader>b/`: 输入缓冲区名称的一部分，然后使用 `<Tab>` 或 `<S-Tab>` 在匹配的缓冲区之间循环切换

5. **在缓冲区选择器中选择:**
   - `<Leader>bb`: 打开缓冲区选择器，您可以在列表中使用键盘上下键或者输入缓冲区名称的前几个字符进行搜索，然后按 `<Enter>` 切换到选中的缓冲区

这些快捷键都是默认的映射，您可以在 `bufferline.nvim` 的配置中进行自定义。例如，如果您希望使用 `<Leader>j` 和 `<Leader>k` 来切换缓冲区，可以在配置文件中添加以下内容:

```lua
require("bufferline").setup({
  -- 其他配置...
  mappings = {
    nav = {
      prev = "<Leader>j", -- 切换到上一个缓冲区
      next = "<Leader>k", -- 切换到下一个缓冲区
    },
  },
})
```

根据您的使用习惯和偏好，选择合适的快捷键映射即可轻松在多个缓冲区之间切换。



