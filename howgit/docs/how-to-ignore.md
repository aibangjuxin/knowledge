# Git 忽略指南：保护敏感文件不被推送到仓库

## 目录

1. [.gitignore 是什么](#1-gitignore-是什么)
2. [当前仓库的忽略规则](#2-当前仓库的忽略规则)
3. [敏感文件分类与处理](#3-敏感文件分类与处理)
4. [推送前检查清单](#4-推送前检查清单)
5. [如果已经推送了敏感文件怎么办](#5-如果已经推送了敏感文件怎么办)
6. [最佳实践总结](#6-最佳实践总结)

---

## 1. .gitignore 是什么

`.gitignore` 是 Git 的忽略规则配置文件。放在仓库根目录（或任意子目录），告诉 Git "这些文件不要管，不要跟踪，不要推送"。

**核心原则**：一旦文件被 `git add` 并提交，哪怕后来加到 `.gitignore` 里，它依然会被跟踪。所以**敏感文件要在第一次提交前就忽略**。

---

## 2. 当前仓库的忽略规则

当前 `knowledge` 仓库的 `.gitignore` 覆盖以下类别：

### 2.1 操作系统文件 (macOS)

```gitignore
.DS_Store          # macOS 文件夹视图配置
.AppleDouble       # macOS 临时文件
.LSOverride        # macOS 登录项缓存
._*                # macOS 跨平台文件（如从 NTFS 复制来的）
Thumbs.db          # Windows 缩略图缓存
```

**风险**：无害，但不推送为宜。

### 2.2 Python 字节码与构建产物

```gitignore
__pycache__/       # Python 运行时缓存目录
*.py[cod]         # 编译后的 Python 字节码
*.pyc
*.pyo
*.pyd
.Python            # pip 安装目录标记
*.so               # C 扩展模块
*.egg              # Python 包分发格式
*.egg-info/
dist/
build/
.eggs/
```

**风险**：无害，但会让仓库膨胀且多人协作时产生大量 diff。

### 2.3 虚拟环境

```gitignore
venv/
ENV/
env/
.venv/
```

**风险**：无害，团队成员各自用本地 venv 即可。

### 2.4 IDE / 编辑器配置

```gitignore
.idea/             # JetBrains 全家桶
.vscode/           # VS Code
*.swp              # Vim 临时文件
*.swo
*~                 # 临时备份文件
```

**风险**：IDE 配置因人而异，不该统一推送。尤其是 `.vscode/extensions.json` 和 `.vscode/settings.json`，容易混入个人偏好。

### 2.5 凭证与密钥（最重要）

```gitignore
.env               # 环境变量文件
.env.*             # .env.local, .env.production 等所有变体
*.pem              # PEM 格式证书（公钥/私钥）
*.key              # 私钥文件
credentials.json   # 通用凭证文件
service-account.json  # GCP 服务账户 JSON
```

**风险**：

| 文件类型 | 泄露后果 |
|----------|----------|
| `.env` | 数据库密码、API 密钥、第三方 token |
| `*.key` / `*.pem` | TLS 私钥、可伪造身份、中间人攻击 |
| `credentials.json` | AWS/GCP 凭证，可直接入侵云资源 |
| `service-account.json` | GCP 服务账户，可横向移动 |

**一旦推送**，即使立即删除，密钥已留在 Git 历史中。攻击者可以通过遍历 Git 历史提取密钥，这是自动化的攻击手段。

### 2.6 Agent / AI 工具配置

```gitignore
.agent/            # Agent 运行时配置
.claude/           # Claude 桌面版配置
.gemini/           # Gemini 配置
.kilo/             # Kilo 配置
.qwen/             # Qwen 配置
```

**风险**：这些目录可能包含 API 密钥、对话历史、项目路径等敏感信息。

### 2.7 其他工具

```gitignore
.obsidian/         # Obsidian 编辑器插件和主题
java-code/.mvn/    # Maven wrapper JAR
.alma-snapshots/   # Alma 快照
```

---

## 3. 敏感文件分类与处理

### 3.1 敏感等级分类

| 等级 | 文件类型 | 举例 | 泄露后果 |
|------|----------|------|----------|
| **P0 - 灾难级** | 云服务私钥 | `*.pem`, `*.key`, `service-account.json` | 可直接入侵云账号 |
| **P1 - 严重** | 数据库/API 凭证 | `.env`, `credentials.json` | 数据泄露或第三方服务被盗用 |
| **P2 - 中等** | 个人配置 | `.vscode/settings.json`, `.obsidian/` | 信息收集、隐私泄露 |
| **P3 - 低** | 构建产物 | `__pycache__/`, `dist/` | 仓库膨胀，无实际风险 |

### 3.2 正确的凭证管理方案

**原则**：凭证文件只存在于本地，绝不进入 Git。

```
~/.hermes/                        # 不推送
├── .env                          # 所有凭证放这里
│   ├── WEIXIN_OFFICIAL_APPID=...
│   └── WEIXIN_OFFICIAL_SECRET=...
└── scripts/                      # 私密脚本
    ├── wechat-article-generator.py
    └── test-wechat-draft.sh

~/git/knowledge/                 # 只推这里的内容
├── .gitignore                    # 忽略所有敏感文件
└── ...

~/git/private/                   # 可选：其他私有大文件
```

**代码中读取凭证的正确方式**：

```python
# ✅ 正确：从环境变量读取
import os
app_id = os.environ.get("WEIXIN_OFFICIAL_APPID")
if not app_id:
    raise RuntimeError("缺少环境变量 WEIXIN_OFFICIAL_APPID")

# ❌ 错误：硬编码凭证
app_id = "wx1234567890abcdef"  # 绝不可以
```

```bash
# ✅ 正确：运行时注入环境变量
WEIXIN_OFFICIAL_APPID=xxx WEIXIN_OFFICIAL_SECRET=yyy python3 script.py

# ✅ 正确：从 .env 文件加载（使用 dotenv 库）
# .env 文件已被 .gitignore 忽略，绝不推送
```

### 3.3 通用的敏感文件模式

以下文件**禁止**推送到任何公开或私有 Git 仓库：

```gitignore
# 密钥与证书
*.key
*.pem
*.crt
*.p12           # PKCS#12 证书包
*.pfx           # 同上

# 云服务凭证
*.credentials
service-account.json
*.firebase.json
aws_credentials
azure_credentials.json

# 环境变量
.env
.env.*
!.env.example   # 只有示例文件可以推送

# 数据库连接
*.sqlite
*.db
*.sql           # 如果包含真实数据

# 日志与调试文件
*.log
debug/
```

---

## 4. 推送前检查清单

每次 `git push` 前，执行以下检查：

### 4.1 自动检查命令

```bash
# 检查是否有新增的敏感文件（未忽略的）
git status --short | grep -E '\.(key|pem|env|json)$'

# 检查是否有新增的 __pycache__ 或 .pyc
git status --short | grep -E '__pycache__|\.pyc$'

# 检查是否有大文件（> 5MB）
git status --short | awk '{print $2}' | xargs -I{} ls -lh {} 2>/dev/null | awk '$5 ~ /[0-9]+G|[0-9]{2,}M/ {print}'

# 完整安全扫描（推荐工具：gittyleaks）
pip install gittyleaks
gittyleaks --no-commits .
```

### 4.2 手动检查要点

- [ ] 新增的 `.json` 文件是否是配置文件（需审查内容）
- [ ] 新增的 `.py` 文件是否有硬编码凭证
- [ ] 新增的 `.env` 文件是否已忽略
- [ ] 新增的私钥/证书是否已忽略

### 4.3 预提交钩子（进阶）

在 `.git/hooks/pre-push` 中加入自动检查脚本：

```bash
#!/bin/bash
# .git/hooks/pre-push

# 检查是否有敏感文件被追踪
SENSITIVE_FILES=$(git ls-files | grep -E '\.(key|pem|env)$')
if [ -n "$SENSITIVE_FILES" ]; then
    echo "ERROR: 敏感文件已被追踪，无法推送:"
    echo "$SENSITIVE_FILES"
    exit 1
fi
```

---

## 5. 如果已经推送了敏感文件怎么办

### 5.1 立即重置vs历史删除

**警告**：重写 Git 历史会影响所有协作者。只在确认无其他人在你分支上工作时使用。

**步骤 1**：从所有分支的历史中移除敏感文件

```bash
# 使用 git filter-repo（推荐）或 git filter-branch
git filter-repo --path-glob '*.key' --invert-paths --force
git filter-repo --path-glob '*.pem' --invert-paths --force
git filter-repo --path-glob '.env' --invert-paths --force
git filter-repo --path-glob 'service-account.json' --invert-paths --force
```

**步骤 2**：重新添加所有文件

```bash
git add --all
git commit -m "chore: remove sensitive files from history"
```

**步骤 3**：强制推送（会覆盖远程）

```bash
git push origin --force --all
```

**步骤 4**：立即轮换所有被泄露的密钥

即使删除了，密钥可能已被爬取。必须：
- 重新生成所有泄露的 API 密钥
- 重新生成 TLS 证书和私钥
- 更新所有数据库密码

### 5.2 如果文件在远程分支历史中

使用 BFG Repo-Cleaner：

```bash
brew install bfg
bfg --delete-files *.key
bfg --delete-files *.pem
bfg --delete-files '.env*'
git reflog expire --expire=now --all && git gc --prune=now --aggressive
git push --force
```

### 5.3 GitHub 的敏感文件删除功能

如果仓库在 GitHub 上且文件刚推送，可以尝试：

1. 在 GitHub 仓库页面找到文件
2. 点击 "Delete file"
3. 提交更改

但这**不会**清除 Git 历史中的内容。对于真正的敏感泄露，GitHub 建议联系 GitHub Support 并提供详情。

---

## 6. 最佳实践总结

### 6.1 防御原则

| 原则 | 说明 |
|------|------|
| **零信任本地文件** | 所有凭证文件默认不推送，`.gitignore` 优先匹配 |
| **分层忽略** | 系统级忽略（OS）→ 语言级忽略（Python/JS）→ 项目级忽略（凭证） |
| **例外要明确** | 不要用 `.*` 一刀切，这样会误忽略 `.gitignore` 本身 |
| **先忽略后提交** | 敏感文件在第一次 `add` 前就要在 `.gitignore` 中 |
| **定期审计** | 每季度检查一次 `.gitignore` 是否覆盖了所有新增的敏感文件类型 |

### 6.2 通用的最小 .gitignore 模板

以下模板适合任何项目，在项目初始化时创建：

```gitignore
# OS
.DS_Store
Thumbs.db

# Credentials & Secrets（最优先）
.env
.env.*
*.key
*.pem
credentials.json

# Language builds
__pycache__/
*.pyc
node_modules/
dist/
build/

# IDE
.vscode/
.idea/
```

### 6.3 团队协作建议

1. **不要把 `gitignore` 本身加入忽略** — `.gitignore` 必须提交，否则新成员会丢失规则
2. **提供 `.env.example`** — 创建一个 `.env.example` 文件，包含所有环境变量的键名（但无值），放入仓库供团队参考
3. **CI/CD 分离** — 敏感配置通过环境变量或密钥管理服务（如 GCP Secret Manager、AWS Secrets Manager）注入，不要放在仓库里
4. **使用 1Password / Bitwarden** — 团队共享密钥用密码管理器，不要用微信/邮件传密钥

### 6.4 当前仓库的安全状态

当前 `knowledge` 仓库的 `.gitignore` 已覆盖：

- ✅ Python 字节码和构建产物
- ✅ 所有主流密钥格式（`*.key`, `*.pem`）
- ✅ 环境变量文件（`.env` 及所有变体）
- ✅ 云服务账户配置（`service-account.json`）
- ✅ AI Agent 配置（`.claude/`, `.gemini/`, `.kilo/`, `.qwen/`）
- ✅ Obsidian 编辑器配置

**建议补充（如果涉及以下场景）**：

```gitignore
# 如果有 Firebase 项目
*.firebase.json

# 如果有 AWS 凭证
aws_credentials
*.aws/credentials

# 如果有 Kubernetes 配置（含 kubeconfig）
kubeconfig*
*kubeconfig*

# 如果有 Terraform 状态
*.tfstate
*.tfstate.*
```

---

## 附录：常用 .gitignore 生成工具

| 工具 | 地址 |
|------|------|
| gitignore.io | https://gitignore.io |
| GitHub .gitignore 模板 | https://github.com/github/gitignore |

用法（生成 Python + macOS + VS Code 的忽略规则）：

```bash
curl -sL https://gitignore.io/api/python,macos,vscode >> .gitignore
```
