# Git 知识库

## 目录描述
本目录包含Git版本控制系统相关的知识、工作流程、实践经验和解决方案。

## 目录结构
```
howgit/
├── config/                   # 配置文件
├── docs/                     # Markdown文档
├── gitimg/                   # Git相关图片资源
├── scripts/                  # Git相关脚本
├── scripts_new/              # 新的脚本文件
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `how-git-working.md`: Git工作原理
- `git-flow.md`: Git工作流程
- `git-log.md`: Git日志操作
- `git-rebase.md`: Git rebase操作
- `fork.md`, `delete-fork.md`: Fork相关操作
- `housekeep-branch.md`: 分支整理
- `ignore.md`: Git忽略文件配置
- `git-sheet.md`: Git常用命令速查
- `git-error.md`: Git错误处理
- `webhook.md`: Git Webhook配置
- `Release-git.md`: Git发布流程
- `chemistry.html`: 化学相关HTML文档

### config/ - 配置文件
- `validate-ip-list*.yml`: IP验证相关配置
- `api_list.yaml`: API列表配置

### scripts_new/ - 脚本
- `ip_validator.py`: IP验证Python脚本

## 快速检索
- Git工作流程: 查看 `docs/` 目录中的 `git-flow.md`
- Git日志: 查看 `docs/` 目录中的 `git-log.md`
- Git rebase: 查看 `docs/` 目录中的 `git-rebase.md`
- 分支管理: 查看 `docs/` 目录中的 `housekeep-branch.md` 和 `fork.md`
- 错误处理: 查看 `docs/` 目录中的 `git-error.md`
- 配置忽略: 查看 `docs/` 目录中的 `ignore.md`
- 配置文件: 查看 `config/` 目录
- 脚本: 查看 `scripts_new/` 目录