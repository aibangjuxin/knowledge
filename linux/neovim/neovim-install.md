要在 Neovim 中安装插件，如 `nvim-tree`，你可以使用插件管理器。这里我们将使用 `vim-plug` 作为插件管理器来安装 `nvim-tree`。以下是详细的步骤：

### 1. 安装 `vim-plug`

首先，确保你已经安装了 `vim-plug`。如果没有，可以使用以下命令安装：

```sh
curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
```

### 2. 配置 `nvim-tree` 插件

编辑你的 Neovim 配置文件 `init.vim` 或 `init.lua` 来添加 `nvim-tree` 插件。

#### 使用 `init.vim`

如果你使用的是 `init.vim`：

```sh
nvim ~/.config/nvim/init.vim
```

在文件中添加以下内容：

```vim
" 使用 vim-plug 插件管理器
call plug#begin('~/.config/nvim/plugged')

" 添加 nvim-tree 插件
Plug 'kyazdani42/nvim-tree.lua'

" 其他插件...
call plug#end()

" nvim-tree 配置
lua << EOF
require'nvim-tree'.setup {}
EOF
```

#### 使用 `init.lua`

如果你使用的是 `init.lua`：

```sh
nvim ~/.config/nvim/init.lua
```

在文件中添加以下内容：

```lua
-- 使用 vim-plug 插件管理器
vim.cmd [[packadd packer.nvim]]

require('packer').startup(function()
  use 'wbthomason/packer.nvim'
  use 'kyazdani42/nvim-tree.lua'
  -- 其他插件...
end)

-- nvim-tree 配置
require'nvim-tree'.setup {}
```

### 3. 安装插件

保存配置文件后，启动 Neovim 并运行以下命令来安装插件：

```vim
:PlugInstall
```

### 4. 使用 `nvim-tree`

安装完成后，你可以使用以下命令来打开 `nvim-tree`：

```vim
:NvimTreeToggle
```

### 5. 配置快捷键（可选）

你可以在配置文件中添加快捷键来更方便地打开和关闭 `nvim-tree`。例如，在 `init.vim` 中：

```vim
nnoremap <C-n> :NvimTreeToggle<CR>
```

在 `init.lua` 中：

```lua
vim.api.nvim_set_keymap('n', '<C-n>', ':NvimTreeToggle<CR>', { noremap = true, silent = true })
```

### 总结

通过上述步骤，你可以在 Neovim 中安装并配置 `nvim-tree` 插件，并使用它来浏览文件系统。你可以根据需要进一步定制 `nvim-tree` 的配置和快捷键，以提高工作效率。

Lex add a new line and split windows
