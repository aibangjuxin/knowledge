cat init.vim
" 基本配置
set number          " 显示行号
set relativenumber  " 显示相对行号
set tabstop=4       " Tab 长度设置为 4 个空格
set shiftwidth=4    " 自动缩进为 4 个空格
set expandtab       " 将 Tab 转换为空格

" 启用语法高亮
syntax on

" 安装 vim-plug 插件管理器
call plug#begin('~/.config/nvim/plugged')
Plug 'junegunn/vim-easy-align'
Plug 'tpope/vim-surround'
Plug 'preservim/nerdtree'
Plug 'morhetz/gruvbox'
" 添加 nvim-tree 插件
Plug 'nvim-tree/nvim-tree.lua'
call plug#end()

" 主题设置
colorscheme gruvbox

lua << EOF
require'nvim-tree'.setup {}
EOF

nnoremap <C-n> :NvimTreeToggle<CR>


