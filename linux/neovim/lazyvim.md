# baking my old neovim
https://github.com/LazyVim/LazyVim

Make a backup of your current Neovim files:

mv ~/.config/nvim ~/.config/nvim.bak
mv ~/.local/share/nvim ~/.local/share/nvim.bak
Clone the starter

git clone https://github.com/LazyVim/starter ~/.config/nvim
Remove the .git folder, so you can add it to your own repo later

rm -rf ~/.config/nvim/.git
Start Neovim!

nvim
Refer to the comments in the files on how to customize LazyVim.


# reference
https://www.lazyvim.org/installation
- init.lua
```lua
-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
require("lazy").setup({
  -- 在这里添加你的插件配置
  opts = {
    -- 基本配置
    number = true, -- 显示行号
    relativenumber = true, -- 显示相对行号
    tabstop = 4, -- Tab 长度设置为 4 个空格
    shiftwidth = 4, -- 自动缩进为 4 个空格
    expandtab = true, -- 将 Tab 转换为空格
    syntax = "ON", -- 启用语法高亮
  },
}, {})
```


testing a shell 
#!/bin/bash

Using space trigger 
