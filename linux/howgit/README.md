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
├── github-repo-role-permissions.md        # GitHub 仓库角色权限详解
└── README.md
```

## 顶层文档

- `How-to-get-commitid.md`: PR rebase 后如何拿到最新的 commit ID(gh CLI / REST API / 完整 sync 脚本)
- `How-to-understand-tree-id-and-commit-id.md`: tree id 和 commit id 的本质 —— 它们的字节级结构、决定字段、互相关系,以及 SHA-1 为何被一改就全改(配套上文的"概念扫盲"篇)
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
