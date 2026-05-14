# BFG Repo-Cleaner 详解

## 1. 什么是 BFG

**BFG Repo-Cleaner** 是一个用 Scala 编写的 Git 仓库清理工具，专门用于从 Git 历史中移除大文件或敏感数据。它是 `git filter-branch` 的替代品，**比后者快 10 到 720 倍**。

| 属性 | 说明 |
|------|------|
| 名称 | BFG Repo-Cleaner |
| 作者 | Roberto Tyley (@rtyley) |
| 语言 | Scala |
| 仓库 | https://github.com/rtyley/bfg-repo-cleaner |
| 官网 | https://rtyley.github.io/bfg-repo-cleaner/ |
| Star | 12.1k+ |
| Fork | 580+ |
| 最新版本 | v1.15.0 |

**核心能力**：
- 删除仓库中的大文件（大到几个 GB 都可以处理）
- 从所有历史记录中移除密码、密钥、凭证等敏感数据
- 清理从其他版本控制系统（如 Mercurial）迁移时遗留的问题文件

---

## 2. 为什么不用 git filter-branch

Git 自带 `git filter-branch` 也能做同样的事，但 BFG 更好：

| 对比项 | `git filter-branch` | BFG Repo-Cleaner |
|--------|---------------------|------------------|
| 速度 | 慢（逐个 commit 重写） | 快 10-720 倍 |
| 内存占用 | 高，容易 OOM | 低 |
| 配置复杂度 | 高，需要写 Bash 脚本 | 简单，命令行参数即可 |
| 并行处理 | 无 | 有 |
| 用途 | 通用，可做任何过滤 | 专精：删文件 / 删大文件 / 替换文本 |

BFG 只做三件事：删文件、删大文件、替换文本。专注所以简单，简单所以快。

---

## 3. 安装方法

### 方式一：Homebrew（推荐 macOS）

```bash
brew install bfg
```

安装后直接用 `bfg` 命令。

### 方式二：下载 JAR 文件

```bash
# 下载最新版
curl -sL https://repo1.maven.org/maven2/com/madgag/bfg-repo-cleaner/1.15.0/bfg-1.15.0.jar -o bfg.jar

# 以后每次用这个命令运行
java -jar bfg.jar
```

### 方式三：通过 SDKMAN

```bash
sdk install bfg
```

---

## 4. 工作原理

BFG 的清理流程分三步：

```
Step 1: git clone --mirror       克隆一个 bare repo（纯 Git 数据库，无工作目录）
         ↓
Step 2: bfg --delete-files xxx   扫描历史，重写所有受影响的 commit、branch、tag
         ↓
Step 3: git reflog expire + gc   物理删除旧的历史对象，释放磁盘空间
         ↓
Step 4: git push                  推送清理后的结果到远端
```

**关键点**：BFG 不会直接删除文件，而是重写历史 commit，把敏感内容从所有 commit 中移除。之后通过 `git gc` 告诉 Git 这些旧对象已经无效，可以物理删除。

---

## 5. 核心用法

### 5.1 准备工作：克隆 mirror 副本

```bash
git clone --mirror https://github.com/yourname/your-repo.git
```

这会创建一个 `.git` 目录（bare repo），没有工作目录，是完整的 Git 数据库副本。

> **重要**：克隆后、运行 BFG 前，**务必备份这个目录**。

### 5.2 删除指定文件

删除所有名为 `id_rsa` 或 `id_dsa` 的文件：

```bash
bfg --delete-files id_{dsa,rsa}  my-repo.git
```

### 5.3 按文件名模式删除

删除所有 `.key` 文件：

```bash
bfg --delete-files *.key  my-repo.git
```

### 5.4 删除大于指定大小的文件

删除所有大于 100MB 的文件：

```bash
bfg --strip-blobs-bigger-than 100M  my-repo.git
```

### 5.5 用文件内容替换敏感信息

创建一个 `banned.txt`，每行写一个要替换的词（默认替换为 `***REMOVED***`）：

```
my-secret-password
api-key-12345
regex:super-secret-\d+
```

然后运行：

```bash
bfg --replace-text banned.txt  my-repo.git
```

### 5.6 完整流程示例（清理密钥）

```bash
# 1. 克隆 bare repo
git clone --mirror git@github.com:yourname/your-repo.git

# 2. 运行 BFG 删除所有 .key 和 .pem 文件
bfg --delete-files *.key --delete-files *.pem your-repo.git

# 3. 物理清理旧对象
cd your-repo.git
git reflog expire --expire=now --all && git gc --prune=now --aggressive

# 4. 推送（mirror 克隆的 push 会更新所有 refs）
git push
```

---

## 6. 常见选项详解

| 选项 | 说明 | 示例 |
|------|------|------|
| `--delete-files <pattern>` | 按文件名模式删除 | `--delete-files "*.key"` |
| `--delete-folders <pattern>` | 按文件夹名删除 | `--delete-folders .git` |
| `--strip-blobs-bigger-than <size>` | 删除大于指定大小的 blob | `--strip-blobs-bigger-than 50M` |
| `--replace-text <file>` | 将文件中列出的词替换为 `***REMOVED***` | `--replace-text passwords.txt` |
| `--no-blob-protection` | 允许删除最新 commit 中的文件 | 默认保护最新 commit |
| `--massive-non-permanent-objects` | 允许删除大量对象（用于仓库初始化错误） | |
| `--message-cleanup <mode>` | 清理 commit 消息中的敏感信息 | `--message-cleanup VICTIM_REMOVED` |

### 关于 `--no-blob-protection`

BFG 默认**不修改最新 commit（HEAD）中的内容**，因为：
- 最新 commit 通常是生产环境的代码
- 直接删除可能造成代码缺失（如硬编码的密钥被删了，但代码还在引用它）
- 正确的做法是：先在最新 commit 中修复问题，再运行 BFG 清理历史

如果确认要修改最新 commit，加这个选项：

```bash
bfg --delete-files *.key --no-blob-protection  my-repo.git
```

---

## 7. 与 git filter-branch 的对比

| 场景 | 推荐工具 |
|------|----------|
| 删除大文件 | BFG ✅ |
| 删除敏感文件（密码/密钥） | BFG ✅ |
| 修改 commit 作者信息 | git filter-branch |
| 修改提交内容（不只是删） | git filter-branch |
| 从其他 VCS 迁移历史 | BFG（删 `.git` 冲突文件）|

---

## 8. 注意事项和风险

### 8.1 风险提示

- **会重写历史**：所有 commit hash 会改变，所有分支和 tag 的引用也会变
- **影响所有协作者**：清理后所有人需要重新克隆仓库，不能再用旧的
- **必须强制推送**：`git push --force` 会覆盖远端历史
- **备份第一**：操作前必须确认已备份

### 8.2 BFG 不会做的事情

- 不会删除当前 working directory 中的文件（最新 commit 是被保护的）
- 不会自动 push（需要手动 push）
- 不会删除 Git 内部的 `.git` 目录（除非加 `--no-blob-protection`）

### 8.3 推送后团队成员的处理

清理完成后，需要通知所有团队成员：

```bash
# 告诉他们删掉旧仓库，重新克隆
git clone git@github.com:yourname/your-repo.git
```

**不要直接 pull**，因为本地分支的 history 已经和远端不一致了，pull 会把脏历史带回来。

---

## 9. 在本知识库场景下的应用

在 `knowledge` 仓库中，如果发现某个敏感文件被误推送（比如 `*.key`、`.env`、证书等），使用 BFG 清理的步骤如下：

```bash
# 1. 进入仓库目录
cd ~/git/knowledge

# 2. 克隆 mirror 副本
git clone --mirror . ../knowledge-backup.git

# 3. 运行 BFG 清理
bfg --delete-files "*.key" --delete-files "*.pem" --delete-folders ".env" ../knowledge-backup.git

# 4. 清理旧对象
cd ../knowledge-backup.git
git reflog expire --expire=now --all && git gc --prune=now --aggressive

# 5. 强制推送
git push --force
```

清理完成后，所有历史记录中的密钥/证书都将被永久删除。

---

## 10. 相关工具

| 工具 | 用途 |
|------|------|
| [git-filter-repo](https://github.com/newren/git-filter-repo) | Python 写的 filter-branch 替代品，功能更全 |
| [git-filter-branch](https://git-scm.com/docs/git-filter-branch) | Git 内置，功能最强但最慢 |
| [gitilex](https://github.com/bast/gitilex) | Git 历史分析工具 |
| [trufflehog](https://github.com/trufflesecurity/trufflehog) | 在 Git 历史中扫描泄露的密钥 |

---

## 附录：安装验证

```bash
# 验证 BFG 已安装
bfg --version
# 输出示例: bfg version 1.15.0

# 或通过 Java
java -jar bfg.jar --version
```
