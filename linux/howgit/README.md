# How Git

Git 使用与原理知识库。

## 目录结构
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
├── why-to-using-githubapps.md                  # 为什么用 GitHub Apps —— App 是什么、跟 OAuth/PAT/Webhook 区别、GitHub→GitLab 触发场景
├── github-repo-role-permissions.md        # GitHub 仓库角色权限详解
└── README.md
```

## 顶层文档

- `How-to-get-commitid.md`: PR rebase 后如何拿到最新的 commit ID(gh CLI / REST API / GitLab / Gitee / 本地 git)
- `How-to-understand-tree-id-and-commit-id.md`: tree id 和 commit id 的本质 —— 它们的字节级结构、决定字段、互相关系,以及 SHA-1 为何被一改就全改(配套上文的"概念扫盲"篇)
- `why-to-using-githubapps.md`: **为什么用 GitHub Apps** —— GitHub App 是什么(first-class actor + 1h token + fine-grained permission)、跟 OAuth App / PAT / Webhook 的根本区别,以及"GitHub 变更 → GitLab pipeline" 的 3 条真实路径(自建 App / GitLab external repo / pull mirror)。**关键澄清:GitHub App 装不到 GitLab 上**,装在 GitHub 自己的 repo/org 上
- `github-repo-role-permissions.md`: GitHub 仓库角色权限(RBAC)详解

## 子目录内容

- `config/`: 4 文件
- `docs/`: 30 文件
- `gitimg/`: 5 文件
- `scripts/`: 4 文件
- `scripts_new/`: 1 文件

## 阅读顺序建议

如果你刚开始接触 Git 的内部 ID 机制:

1. 先读 `How-to-understand-tree-id-and-commit-id.md` —— 了解什么是 tree id / commit id / blob id,以及它们为什么改一个 bit 全部 hash 都变
2. 再读 `How-to-get-commitid.md` —— 当你真正在 PR 流程里需要拿 commit id 的时候怎么拿(GitHub / GitLab / Gitee / 本地 git)

如果你想搞懂 GitHub 协作 + 自动化的"权限 + 事件"体系:

1. 先读 `why-to-using-githubapps.md` —— 理解 App / OAuth / PAT / Webhook 四种身份,以及 GitHub→GitLab 触发的 3 条路径
2. 再读 `github-repo-role-permissions.md` —— 理解**人**的 5 档权限(R/T/W/M/A)跟 App 权限是两条正交体系

## 关键交叉引用

- `why-to-using-githubapps.md` (App 权限,bot) ↔ `github-repo-role-permissions.md` (collaborator 权限,人) — 互补,两个一起看
- `why-to-using-githubapps.md` §3.4 / §4.1 (webhook) ↔ `docs/webhook.md` (裸 webhook 的 chatgpt 风格教程) — 前者讲 App 自带 webhook 带身份,后者只讲裸 webhook
