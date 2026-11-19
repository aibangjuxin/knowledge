# LazyGit 实战指南（macOS 终端里的 Git TUI）

> 安装记录：2026-11-19，macOS (darwin arm64)，Homebrew。
> `brew install lazygit` → lazygit **0.66.3** (`/opt/homebrew/bin/lazygit`)
> 附带 `brew install git-delta` → delta **0.20.1**（`git log/diff` 彩色高亮）

## 1. LazyGit 是什么

一个终端里的 Git 图形界面（TUI）：把 `git status` / `git add` / `git commit` /
`git log` / `git merge` / `git rebase` / `git stash` 全塞进一个全屏界面，
用方向键 + 单键快捷键操作，不用记长命令，也不用开 GUI。

**什么时候用它**：日常「改了文件 → 看 diff → 选片段 → 暂存 → 提交 → 推送」这一整条链路。
**什么时候不用**：脚本化/CI 里仍然用原生 git 命令；查「某段字符串/某个命令在哪次 commit 出现」
这类历史检索，终端命令反而更快（见 §4）。

启动：在任意 git 仓库根目录执行 `lazygit`（也支持 `lazygit <子目录>`，会向上找仓库根）。

## 2. 界面布局

```
┌──────────────┬───────────────────────────────────────────┐
│ 1 Status     │                                           │
│ 2 Files      │              主视图（diff / commit 详情）  │
│ 3 Branches   │                                           │
│ 4 Commits    │                                           │
│ 5 Stash      │                                           │
└──────────────┴───────────────────────────────────────────┘
```

- `1`~`5`：切换左侧面板；`Tab`：在主视图的两个 diff 面板间切换
- `0`：聚焦主视图；`Esc`：从主视图退回侧栏
- `?`：查看当前面板的全部快捷键（**最权威的速查表，界面里直接按**）
- `q` / `Ctrl+C`：退出
- `/`：在当前面板按文本过滤（commit message、文件名、分支名都能过滤）
- `<Ctrl+G>`：跳转到指定文件

## 3. 常用快捷键（官方 Keybindings，2026-11 核对）

### Files 面板（第 2 栏）
| 键 | 作用 |
|:---|:---|
| `<Space>` | 暂存 / 取消暂存（可多选） |
| `a` | 切换「按 hunk 选」/「按行选」 |
| `d` | 丢弃改动（未暂存）或取消暂存（已暂存） |
| `E` | 用外部编辑器编辑选中的 hunk |
| `e` | 用外部编辑器打开文件 |
| `c` | 提交已暂存的改动 |
| `w` | 跳过 pre-commit hook 提交 |
| `C` | 用 git editor 提交（自己写 commit message） |
| `<Ctrl+F>` | **Find base commit for fixup**：直接找到当前改动该 amend 到哪个 commit |
| `G` | 对选中行打开 PR（仅 GitHub） |
| `n` / `N` | 下一个 / 上一个文件 |

### Commits 面板（第 4 栏）
| 键 | 作用 |
|:---|:---|
| `y` | 复制 commit 属性到剪贴板（hash / URL / diff / message / author） |
| `o` | 在浏览器打开该 commit |
| `<Space>` | checkout 该 commit（detached HEAD） |
| `C` | 标记为 copied，之后按 `V` 粘贴（cherry-pick） |
| `*` | 选中当前分支的全部 commit |
| `g` | reset 选项（soft/mixed/hard） |
| `n` / `N` | 从该 commit 新建分支 / 把未推送 commit 挪到新分支 |
| `w` | 为该 commit 创建 worktree |
| `<Enter>` | 查看该 commit 涉及的文件 |

### Branches 面板（第 3 栏）
| 键 | 作用 |
|:---|:---|
| `n` | 新建分支 |
| `M` | 合并（含 squash merge 选项） |
| `r` | rebase 到选中分支 |
| `u` | 设为 upstream |
| `<Space>` | checkout |
| `g` | reset |
| `s` | 排序方式 |

### Remotes / Stash / Tags
| 面板 | 键 | 作用 |
|:---|:---|:---|
| Remotes | `f` | fetch；`n` 新建 remote；`e` 改 URL |
| Stash | `<Space>` | apply；`g` pop；`d` drop；`n` 从 stash 建分支 |
| Tags | `n` 新建 / `d` 删除 / `P` push / `<Space>` checkout |

> 主视图与各面板的键位会随版本变化，**以界面里按 `?` 看到的为准**，本文档只是速查。

## 4. 核心场景：「这个命令 / 这段配置有没有对应的 commit 记录」

这是最常用的历史检索需求。LazyGit 能做的是**按文件**看历史（Files 面板选中文件 →
主视图看 diff → Commits 面板切到该文件的 log）；但**按字符串/按命令**检索必须用原生 git：

```bash
# 1) 某段字符串何时被引入/删除（最常用，能回答"这条命令是哪次 commit 加的"）
git log -S "kubectl apply" --oneline          # 字符串出现次数变化
git log -S "kubectl apply" -p                # 带上 diff
git log -G "regex.*kubectl" --oneline        # 正则匹配改动行

# 2) 按 commit message 搜
git log --grep="sanitize" --oneline
git log --grep="fix" --grep="deploy" --oneline   # 多个 --grep 是 OR
git log --grep="fix" --grep="deploy" --all-match  # AND

# 3) 某个文件/目录的全部改动史
git log --oneline -- path/to/file
git log --follow --oneline -- path/to/file       # 跟踪重命名

# 4) 某一行代码的来历
git blame -L 120,140 path/to/file
git log -L 120,140:path/to/file                  # 某行的演变历史

# 5) 谁在什么时候改过这个分支
git log --oneline --graph --decorate --all
```

**在 LazyGit 里做同样的事**：Commits 面板按 `/` 输入关键字过滤 commit message；
Files 面板选中文件后 `<Enter>` 看该文件在当前分支上的 commit 列表。

**配合 fzf 更好用**（本机已装 `fzf`）：
```bash
git log --oneline --all | fzf --preview 'git show --color=always {}' | cut -d' ' -f1 | xargs git show
```

## 5. git-delta：让 `git log -p` / `git diff` 好看

```bash
brew install git-delta
# 写入 ~/.gitconfig
[core]
    pager = delta
[delta]
    navigate = true            # 方向键可左右翻页
    line-numbers = true
    syntax-theme = GitHub
```

验证：`git log -p | less`，diff 会带行号、语法高亮、左右分栏。

## 6. 备选工具对比

| 工具 | 定位 | 什么时候选它 |
|:---|:---|:---|
| **lazygit** | 全功能 TUI，本文档主角 | 日常改代码、提交、解决分支交互；**综合体验最好** |
| **gitui** | Rust 写的 TUI，界面更现代 | 喜欢更清爽的视觉风格；功能比 lazygit 少一点 |
| **tig** | 经典 pager 风格（`tig log` / `tig status`） | 想要纯「看历史」不进入全屏交互模式 |
| **git-delta** | diff 渲染器，不是 TUI | 只要 `git log -p` / `git diff` 好看、轻量 |
| **fzf** | 模糊查找器 | 想把 git 历史接到任何管道里 |
| **git-open** | 打开对应 GitHub 页面 | 只想快速跳网页看 PR/Issue |
| **onefetch / gitkraken / Sourcetree** | 图形/半图形 | 不习惯终端 |

本机现状：`lazygit` ✅ `delta` ✅ `fzf` ✅ `bat` ✅；`gitui` / `tig` 未装。

## 7. 常见坑

1. **在错误的目录启动**：lazygit 找不到 `.git` 会报 `not a git repository`，`cd` 到仓库根再跑。
2. **submodule**：需要先进 submodule 再退出，`Esc` 可退回父仓库。
3. **commit message 编辑器**：lazygit 默认内置编辑器；想用 vim 设 `git config core.editor vim`。
4. **懒加载**：lazygit 用 `git` 命令实时取数，大仓库首次启动有几秒延迟属正常。
5. **`d` 丢改动不可逆**：在 Files 面板对未暂存改动按 `d` 是真的 `git reset` 掉工作区内容，没有撤销。
6. **和仓库自己的 `push.sh` / `pushc` 流程冲突**：本仓库有自带的脱敏 push 流程（见 `../../AGENTS.md`），
   在这个仓库里**用仓库脚本推送**，别用 lazygit 的 push 覆盖掉闸门逻辑。
7. **SSH / GPG 认证弹窗**：lazygit 走的是普通 git 命令，认证失败会提示回终端处理。

## 8. 相关文档

- 官方快捷键（权威）：<https://github.com/jesseduffield/lazygit/blob/master/docs/keybindings/Keybindings_en.md>
- 官方配置（`~/.config/lazygit/config.yml`）：<https://github.com/jesseduffield/lazygit/blob/master/docs/Config.md>
- 本仓库相关：`../../AGENTS.md`（脱敏与 push 闸门）、`How-to-get-commitid.md`、`gh-user-guide.md`
