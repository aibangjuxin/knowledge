# How Git

Git 使用与原理知识库。

## 目录结构
```
howgit/
├── config/                                # Git 配置
├── docs/                                  # Git 文档
├── gitimg/                                # 图片资源
├── scripts/                               # 脚本
├── scripts_new/                           # 新脚本
├── How-to-get-commitid.md                 # Rebase 后获取 PR 最新 commit ID(实用操作)
├── How-to-understand-tree-id-and-commit-id.md  # 理解 tree id / commit id 是什么(概念原理)
├── How-to-understand-git-pull-rebase.md   # 理解 git pull --rebase:跟 merge 的区别、内部机制、何时用何时不能用
├── How-to-understand-git-diff-a-b-prefix.md # 读懂 git diff 输出:diff --git a/xxx b/xxx 里的 a/b 到底指什么(不是分支)
├── why-to-using-githubapps.md                  # 为什么用 GitHub Apps —— App 是什么、跟 OAuth/PAT/Webhook 区别、GitHub→GitLab 触发场景
├── github-repo-role-permissions.md        # GitHub 仓库角色权限详解
├── codeowners-guide.md                  # CODEOWNERS 完全指南 —— 文件放哪、语法、ruleset 门禁、单人仓库死锁
├── gh-user-guide.md                       # GitHub CLI (gh) 实用指南 —— PR/Issue/CI 全流程,终端内完成不打开浏览器
├── lazygit-guide.md                       # LazyGit 实战指南 —— 终端 Git TUI 快捷键、"某段命令/配置对应的 commit" 检索、git-delta、备选工具对比
└── README.md
```

## 顶层文档

- `gh-user-guide.md`: **GitHub CLI (`gh`) 实用指南** —— 认证配置、PR 全生命周期(创建/查看/diff/checks/review/合并)、Issue、Actions CI 监控、`gh api`/`gh search` 兜底、脚本化与别名、常见坑速查。核心原则:**`gh` 默认在终端输出,不开浏览器;想看网页信息用 `--json` + `--jq`**
- `How-to-get-commitid.md`: PR rebase 后如何拿到最新的 commit ID(gh CLI / REST API / GitLab / Gitee / 本地 git)
- `How-to-understand-tree-id-and-commit-id.md`: tree id 和 commit id 的本质 —— 它们的字节级结构、决定字段、互相关系,以及 SHA-1 为何被一改就全改(配套上文的"概念扫盲"篇)
- `How-to-understand-git-diff-a-b-prefix.md`: **读懂 git diff 输出** —— `diff --git a/X b/Y` 逐行解剖(`index <hash>..<hash> 100644` 里的 blob 缩写与文件模式、`@@` hunk 头);**核心澄清:`a/`、`b/` 是 diff 两侧的位置占位符(a=左边=旧版,b=右边=新版),既不是分支,也不是 after/before 的首字母**;哪条命令比的是哪两个版本(`diff`=index↔worktree、`--cached`=HEAD↔index、`diff HEAD`=HEAD↔worktree、`show`=parent↔commit);`--no-prefix` / `--src-prefix` / `--mnemonic-prefix`(i/w/c/o 助记前缀)亲手验证
- `How-to-understand-git-pull-rebase.md`: `git pull --rebase` 是什么 —— 跟默认 merge 模式的对比、内部 transplant 步骤、何时该用 / 绝对不能用、出错怎么 recover、跟 `--autostash` / `pull.rebase=true` 等常见组合
- `why-to-using-githubapps.md`: **为什么用 GitHub Apps** —— GitHub App 是什么(first-class actor + 1h token + fine-grained permission)、跟 OAuth App / PAT / Webhook 的根本区别,以及"GitHub 变更 → GitLab pipeline" 的 3 条真实路径(自建 App / GitLab external repo / pull mirror)。**关键澄清:GitHub App 装不到 GitLab 上**,装在 GitHub 自己的 repo/org 上
- `github-repo-role-permissions.md`: GitHub 仓库角色权限(RBAC)详解
- `codeowners-guide.md`: **CODEOWNERS 完全指南** —— 文件放在 `.github/`(优先级最高)、`docs/`(最低,且会被站点构建吃掉)还是仓库根;GitHub 与 GitLab 位置优先级不同;pattern 语法与三个不支持的写法(`!`取反 / `[a-z]` 字符范围 / `\#` 转义);如何与 branch protection / ruleset 的 `require_code_owner_review` 组合;**单人仓库开了这个门禁必然死锁**(PR 作者不能批准自己的 PR)
- `lazygit-guide.md`: **LazyGit 实战指南** —— macOS 已安装 lazygit 0.66.3 + git-delta 0.20.1;TUI 面板布局与 Files/Commits/Branches/Remotes/Stash 快捷键速查;**「某个 git 命令 / 一段配置有没有对应 commit」的两套解法**(lazygit 按文件看 + `git log -S/-G/--grep`、`git blame -L` 按字符串查);git-delta 配置;gitui/tig/fzf 备选工具对比;常见坑(含本仓库自带 push 闸门,别用 lazygit 的 push 覆盖它)

## 子目录内容

- `config/`: 4 文件
- `docs/`: 31 文件(含 `gh.md` —— 指向 `../gh-user-guide.md` 的入口指针)
- `gitimg/`: 5 文件
- `scripts/`: 4 文件
- `scripts_new/`: 1 文件

## 阅读顺序建议

如果你刚开始接触 Git 的内部 ID 机制:

1. 先读 `How-to-understand-tree-id-and-commit-id.md` —— 了解什么是 tree id / commit id / blob id,以及它们为什么改一个 bit 全部 hash 都变
2. 再读 `How-to-get-commitid.md` —— 当你真正在 PR 流程里需要拿 commit id 的时候怎么拿(GitHub / GitLab / Gitee / 本地 git)

如果你看不懂 `git diff` 的输出头:

1. 先读 `How-to-understand-git-diff-a-b-prefix.md` —— 搞清 `a/` `b/` 是「改动前/改动后」而不是分支,以及 `index` 行那两个 hash 是什么

如果你想搞懂 GitHub 协作 + 自动化的"权限 + 事件"体系:

1. 先读 `why-to-using-githubapps.md` —— 理解 App / OAuth / PAT / Webhook 四种身份,以及 GitHub→GitLab 触发的 3 条路径
2. 再读 `github-repo-role-permissions.md` —— 理解**人**的 5 档权限(R/T/W/M/A)跟 App 权限是两条正交体系

## 关键交叉引用

- `gh-user-guide.md` (gh CLI 命令) ↔ `docs/gh.md` (旧入口,已合并) —— 同源,以后只维护 `gh-user-guide.md`
- `gh-user-guide.md` §3.1 (创建 PR) ↔ `How-to-get-commitid.md` (rebase 后拿 commit id) —— PR 流程的上下游
- `why-to-using-githubapps.md` (App 权限,bot) ↔ `github-repo-role-permissions.md` (collaborator 权限,人) — 互补,两个一起看
- `why-to-using-githubapps.md` §3.4 / §4.1 (webhook) ↔ `docs/webhook.md` (裸 webhook 的 chatgpt 风格教程) — 前者讲 App 自带 webhook 带身份,后者只讲裸 webhook
- `codeowners-guide.md` §6.2 (ruleset API 写法) ↔ `gcp/ucp/argocd-topics/git-apps/14-rulesets-and-gitapp-gate.md` —— 后者把 `require_code_owner_review` 当成独立 rule type,实际它是 `pull_request` 规则的参数
- `codeowners-guide.md` §2.3 (平台对照) ↔ `github-repo-role-permissions.md` —— 前者管"谁审",后者管"谁能做什么"
