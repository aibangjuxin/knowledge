# GitHub CLI (`gh`) 实用指南

> 目标：**不打开浏览器**也能把 PR / Issue / CI 的完整流程跑完；必须看网页时，只拿 URL，不被浏览器打断。
>
> 环境：macOS + `gh` v2.103.2，仓库 `git@github.com:aibangjuxin/knowledge.git`（SSH）。

---

## 0. 核心认知：`gh` 默认就「不打开浏览器」

这是最多人误解的一点。`gh` 的设计原则是 **终端优先**：

| 命令 | 默认行为 | 想开浏览器才加 |
| --- | --- | --- |
| `gh pr create` | 创建后**在终端打印 PR URL**，不开浏览器 | `--web` |
| `gh pr view` | 在终端打印 PR 详情 | `--web` |
| `gh pr list` | 在终端打印表格 | `--web` |
| `gh issue list` | 在终端打印表格 | `--web` |
| `gh run view` | 在终端打印运行详情 | `--web` |
| `gh browse` | ⚠️ **默认会打开浏览器** | 改用 `-n / --no-browser` 只打印 URL |

结论：

- 凡是 `gh pr/issue/run ...`，**不加 `--web` 就永远不会弹浏览器**。
- 唯一会主动弹浏览器的是 `gh browse`（以及各命令的 `--web`），需要 URL 时用 `gh browse -n`。
- 想拿到网页内容又不想开浏览器 → 用 `--json` + `--jq` 把 API 数据直接格式化到终端（本文档第 3 节）。

---

## 1. 环境准备

```bash
# 安装（macOS）
brew install gh

# 登录（推荐用浏览器设备码，不用敲密码）
gh auth login
#   → GitHub.com / HTTPS / Login with a web browser
#   → 复制一次性验证码粘贴到浏览器完成授权

# 查看当前登录状态 / 权限范围
gh auth status
#   ✓ Logged in to github.com account aibangjuxin (keyring)
#   Token scopes: 'gist', 'read:org', 'repo', 'workflow'

# 让 git push/pull 也走 gh 的凭据（用 token 免密）
gh auth setup-git

# 切换多个账号
gh auth switch --hostname github.com --user <other-user>
```

### 常用配置

```bash
gh config set git_protocol ssh        # clone/push 用 SSH（推荐）
gh config set prompt disabled          # CI/脚本里禁止交互式提问
gh config set prefer_editor_prompt disabled
gh config set editor vim              # gh pr create -e 用哪个编辑器
```

`gh config list` 可查看所有当前配置。

---

## 2. 认证与身份相关的只读命令

```bash
gh auth status                       # 我是谁、token scope、有哪些 host
gh auth token                        # 打印 token（慎用，别进日志）
gh auth refresh -s workflow          # 给已有 token 加权限（如触发 workflow 需要 workflow scope）
```

---

## 3. PR：全生命周期（不开浏览器）

### 3.1 创建 PR

**最基础**（你给的那条命令的通用形式）：

```bash
gh pr create \
  --base feature/cr-prefix-verify \
  --head docs/cr-prefix-lab \
  --title "CH113456 docs: sync docs to feature resolve only testing" \
  --body "sync docs to feature resolve only testing"
```

要点：

- `--base` = 目标分支（合入到哪里），`--head` = 源分支（改动来自哪里）。
- `--head` 一旦显式指定，`gh` **不会再提示 push**，也**不会自动 fork**。所以必须自己先 push：
  ```bash
  git push -u origin docs/cr-prefix-lab
  ```
- 命令执行完，终端会打印 PR 链接，**直接复制到终端里看就行**，不用开浏览器。

**从 commit 自动填 title/body**（不用手敲）：

```bash
gh pr create --base main --fill            # 用最近一条 commit 的标题+正文
gh pr create --base main --fill-first      # 用第一条 commit
gh pr create --base main --fill-verbose    # 带上 commit body
```

`--fill` 与 `--title/--body` 同时给时，显式传的**优先级更高**。

**先预览、不真建**（推荐在脚本/CI 里用）：

```bash
gh pr create --base main --fill --dry-run
# → 打印将要创建的 PR 内容，不真正创建
```

**从文件读 body**（长描述、写文档时最舒服）：

```bash
cat > /tmp/pr-body.md <<'EOF'
## 变更内容
- 更新 cr-prefix 校验逻辑
- 补充单元测试

## 验证方式
`make test`
EOF

gh pr create --base main --title "CH113456 fix: cr prefix verify" --body-file /tmp/pr-body.md
# 也支持从 stdin 读
gh pr create --base main --title "..." --body-file -
```

**从模板开始**：

```bash
gh pr create --base main --template .github/pull_request_template.md
```

**加标签 / 评审人 / 里程碑 / 草稿**：

```bash
gh pr create --base main --fill \
  --label "docs" --label "ch113456" \
  --reviewer "alice,bob" \
  --assignee "@me" \
  --milestone "v1.2" \
  --draft
```

**带截图**（自动上传成附件，Markdown 里的相对路径会被改写）：

```bash
gh pr create --base main --title "..." --body-file /tmp/body.md \
  --attach "./screenshot.png#登录报错页面"
```

**关联 Issue**（写 `Fixes #123`，PR 合并后自动关 Issue）：

```bash
gh pr create --base main --title "..." --body "Fixes #123"
```

### 3.2 查看 PR：终端里直接读「页面信息」

这是「不想开浏览器但想看网页内容」的核心手段。

**看当前分支的 PR（最常用）**：

```bash
gh pr view
```

输出包含：标题、状态、作者、正文、labels、assignees、reviewers、里程碑、关联 Issue、merge 状态、以及底部一行评论摘要。

**带上评论和 review 记录**：

```bash
gh pr view --comments
# 注意：输出被管道/重定向时，只会打印 comments 和 reviews
gh pr view --comments | less
```

**结构化输出（拿网页上的字段）**：

```bash
# 只取 URL
gh pr view --json url --jq .url

# 取几个关键字段组成一行（注意：pr view 返回的是「对象」，不是数组）
gh pr view --json number,title,state,url,author,baseRefName,headRefName \
  --jq '"#\(.number) [\(.state)] \(.title) \(.url)"'

# 取「能不能合 + 检查是否全绿」（脚本里判断合并就绪最常用）
gh pr view --json mergeable,mergeStateStatus,reviewDecision,statusCheckRollup \
  --jq '{mergeable, mergeStateStatus, reviewDecision,
        checks: [.statusCheckRollup[] | {name, conclusion}]}'
```

> 忘了字段名？直接执行 `gh pr view --json`（不带字段），它会把所有可用字段列出来给你挑。

> `--json` 支持的字段（部分）：
> `number, url, title, body, state, isDraft, author, assignees, labels, reviewers, latestReviews, reviewDecision, baseRefName, headRefName, additions, deletions, changedFiles, files, commits, comments, mergeable, mergeStateStatus, statusCheckRollup, createdAt, updatedAt, mergedAt, closedAt, closingIssuesReferences, milestone, projectItems, headRepository, isCrossRepository, autoMergeRequest, maintainerCanModify`

**用 Go template 格式化**（不想装 jq 时）：

```bash
gh pr view --json number,title,url --template '{{.number}} {{.title}} -> {{.url}}{{"\n"}}'
```

**看当前仓库所有 PR（表格）**：

```bash
gh pr list
gh pr list --state all --limit 50
gh pr list --base feature/cr-prefix-verify
gh pr list --author "@me"
gh pr list --assignee "@me" --label "bug"
gh pr list --draft
gh pr list --json number,title,author,updatedAt --jq '.[] | [.number,.author.login,.updatedAt,.title] | @tsv'
```

**看 PR 的合并冲突状态**：

```bash
gh pr status --conflict-status
```

### 3.3 看 diff（不打开网页的 diff）

```bash
gh pr diff                    # 当前分支的 PR 完整 diff
gh pr diff 123                # 指定 PR
gh pr diff --name-only        # 只看改了哪些文件
gh pr diff --patch            # 强制 patch 格式
gh pr diff --color never      # 管道输出时不要 ANSI 色
gh pr diff --exclude "*.lock" --exclude "vendor/*"
```

### 3.4 看 CI 检查（不用点 Actions 网页）

```bash
gh pr checks                 # 列出所有 check 及结论
gh pr checks --required      # 只看 required 的
gh pr checks --watch         # 实时轮询直到跑完（默认 10s 一次）
gh pr checks --watch --fail-fast --interval 5
gh pr checks --json name,state,bucket --jq '.[] | "\(.bucket)\t\(.name)\t\(.state)"'
```

### 3.5 Review（终端里做 Code Review）

```bash
gh pr review 123 --approve
gh pr review 123 --request-changes --body "这里请补充错误处理"
gh pr review 123 --comment --body "只是留言，不表态"
gh pr review 123 --body-file /tmp/review.md --comment
```

### 3.6 合并 & 收尾

```bash
gh pr merge --squash --delete-branch       # 压缩合并 + 删分支（最常用）
gh pr merge --merge --delete-branch        # 保留 merge commit
gh pr merge --rebase --delete-branch       # rebase 合并
gh pr merge --auto --delete-branch         # 等 CI 通过后自动合
gh pr merge --admin                        # 绕过保护规则强行合（需管理员）
gh pr merge 123 --squash -b "merge body" -t "merge subject"
```

`--auto` 配合 `--delete-branch` 是 CI 环境下最省事的组合：**挂上自动合并，不用盯着**。

**PR 状态流转**：

```bash
gh pr ready 123                             # draft -> ready for review
gh pr close 123
gh pr reopen 123
gh pr edit 123 --title "新标题" --add-label "bug" --add-reviewer alice --remove-label "wip"
gh pr edit 123 --body-file /tmp/body.md
```

**本地检出别人的 PR**：

```bash
gh pr checkout 123                                   # 切到 PR 分支
gh pr checkout 123 --detach                          # detached HEAD
gh pr checkout 123 --branch my-review                # 指定本地分支名
gh pr checkout 123 --force                           # 强制重置本地分支
gh pr checkout 123 --worktree ../pr-123              # 检出到独立 worktree（并行 review 很好用）
```

### 3.7 PR 相关速查表

| 目的 | 命令 |
| --- | --- |
| 当前分支有没有 PR | `gh pr status` |
| 看 PR 详情 | `gh pr view` |
| 看 PR URL | `gh pr view --json url --jq .url` |
| 看 diff | `gh pr diff` |
| 看 CI | `gh pr checks --watch` |
| 拉别人的 PR 到本地 | `gh pr checkout 123` |
| 合并并清理 | `gh pr merge --squash --delete-branch` |
| 只拿 URL 不开浏览器 | `gh browse -n 123` |

---

## 4. Issue

```bash
# 列表 / 过滤
gh issue list
gh issue list --assignee "@me" --label "bug"
gh issue list --author "@me" --state all --limit 100
gh issue list --milestone "v1.2"
gh issue list --search "cr prefix"

# 创建
gh issue create --title "Bug: cr-prefix 校验未覆盖多级目录" --body "复现步骤..."
gh issue create --title "..." --body-file /tmp/issue.md --label "bug" --assignee "@me"
gh issue create --title "..." --body "..." --template "bug_report.md"   # .github/ISSUE_TEMPLATE 下的模板名

# 查看 / 关闭
gh issue view 42 --comments
gh issue view 42 --json title,state,labels,assignees --jq '.labels[].name'
gh issue close 42 --comment "已由 PR #123 修复"
gh issue reopen 42
gh issue edit 42 --add-label "in-progress" --remove-assignee "@me"

# 看板式聚合（跨仓库）
gh issue list --search "is:open label:bug repo:aibangjuxin/knowledge"
```

---

## 5. Actions / CI（最省事的一节）

```bash
# 最近运行记录
gh run list
gh run list --workflow "docs-deploy.yml" --branch main
gh run list --status failure --limit 10
gh run list --event push --json databaseId,conclusion,workflowName --jq '.[] | "\(.databaseId)\t\(.conclusion)\t\(.workflowName)"'

# 看某次运行详情
gh run view 123456789
gh run view 123456789 --verbose          # 展开每个 job 的每个 step
gh run view 123456789 --job build        # 只看某个 job

# 看日志（不需要点网页）
gh run view 123456789 --log              # 完整日志
gh run view 123456789 --log-failed       # 只看失败步骤的日志 ← 最常用
gh run view 123456789 --log-failed | grep -A5 "ERROR"

# 实时跟
gh run watch 123456789
gh run watch 123456789 --exit-status --interval 5   # 失败时返回非 0（CI 里用）

# 重跑
gh run rerun 123456789
gh run rerun 123456789 --failed          # 只重跑失败的 job
gh run rerun 123456789 --debug          # 带 debug 日志

# 手动触发 workflow
gh workflow list
gh workflow run deploy.yml --ref main
gh workflow run deploy.yml --ref main -f env=prod -f version=1.2.3
```

**实用组合**：CI 挂了 → `gh run list --status failure -L 1` 拿到 ID → `gh run view <id> --log-failed` 直接看失败原因。

---

## 6. Repo 与分支

```bash
gh repo view                          # 终端看仓库信息
gh repo view --json name,description,defaultBranchRef,stargazerCount,url \
  --jq '{name, default: .defaultBranchRef.name, stars: .stargazerCount, url}'

gh repo clone aibangjuxin/knowledge
gh repo fork aibangjuxin/knowledge --clone
gh repo create my-repo --private --clone --add-readme

gh repo sync                           # fork 同步上游
gh repo rename new-name
gh repo archive --yes aibangjuxin/knowledge

gh api repos/aibangjuxin/knowledge/branches --jq '.[].name'
```

### 只要 URL，不开浏览器

```bash
gh browse -n                    # 仓库首页 URL
gh browse -n 123                # PR/Issue #123 的 URL
gh browse -n cmd/gh/main.go     # 某个文件的 URL
gh browse -n --commit abc123    # 某个 commit 的 URL
gh browse -n -s                 # settings 页 URL
```

---

## 7. `gh api`：网页能做的，API 都能做

当 `gh pr/issue` 没有对应子命令时，直接打 REST / GraphQL API。

```bash
# GET（默认）
gh api repos/aibangjuxin/knowledge
gh api repos/aibangjuxin/knowledge/pulls --jq '.[].title'

# 路径参数替换
gh api repos/{owner}/{repo} --jq .full_name

# POST + JSON body
gh api repos/aibangjuxin/knowledge/issues \
  --method POST \
  -f title="标题" \
  -f body="正文" \
  -f labels[]="bug"

# 带类型参数的字段
gh api repos/{owner}/{repo}/pulls --method POST \
  -f title="..." -f head=docs/cr-prefix-lab -f base=feature/cr-prefix-verify

# 翻页拿全量数据
gh api --paginate repos/{owner}/{repo}/issues --jq '.[].number'

# GraphQL
gh api graphql -f query='
  query { viewer { login } repository(owner:"aibangjuxin", name:"knowledge") {
    pullRequests(states:OPEN, first:10) { nodes { number title } } } }'

# 只看 HTTP 状态码 / 静默
gh api -i repos/{owner}/{repo}
gh api --silent repos/{owner}/{repo}/actions/runs
```

---

## 8. `gh search`：跨仓库搜索

```bash
# 搜 PR
gh search prs "cr prefix" --repo aibangjuxin/knowledge
gh search prs --author "@me" --state open --limit 20
gh search prs --review required --owner aibangjuxin
gh search prs --checks failure --json number,title,url

# 搜 issue / 代码 / 仓库
gh search issues "cr-prefix" --repo aibangjuxin/knowledge --label bug
gh search code "cr_prefix" --repo aibangjuxin/knowledge --limit 20
gh search repos "knowledge base" --owner aibangjuxin
```

---

## 9. 扩展生态：`gh extension`

官方子命令不够用时，可以装社区扩展（扩展仓库名必须以 `gh-` 开头）：

```bash
gh extension list                      # 已安装的扩展
gh extension search <keyword>          # 搜索可用扩展
gh extension install <owner/gh-ext>    # 安装
gh extension upgrade <owner/gh-ext>    # 升级
gh extension remove <owner/gh-ext>     # 卸载
gh extension install <owner/gh-ext> --pin v1.2.0   # 锁定版本
```

注意事项：

- 扩展**不能覆盖**核心命令（`gh pr` 等）；万一重名，用 `gh extension exec <name>` 调用。
- 扩展**未被 GitHub 签名或背书**，安装前自己审一下源码。
- 扩展列表：https://github.com/topics/gh-extension

### Codespaces（内置命令，非扩展）

```bash
gh codespace list                    # 列出所有 codespace（别名 gh cs）
gh codespace create --repo aibangjuxin/knowledge
gh codespace ssh -c <name>           # 直接 ssh 进去
gh codespace cp <local> <remote>     # 本地/远程文件互传
gh codespace stop -c <name>
gh codespace delete -c <name>
```

---

## 10. 脚本化 & 别名

### 存常用命令为别名

```bash
# 交互式：gh alias set
gh alias set prs 'pr list --author "@me" --state open'
gh alias set prc 'pr create --base main --fill'
gh alias set prm 'pr merge --squash --delete-branch'

# 非交互：直接写配置文件
cat >> ~/.config/gh/config.yml <<'EOF'
aliases:
  myprs: pr list --author "@me" --state open
  prc: pr create --base main --fill
  prm: pr merge --squash --delete-branch
EOF

gh alias list
gh alias delete prs
```

### CI 里用（关掉交互 + 检查退出码）

```bash
export GH_PROMPT_DISABLED=1

gh pr checks --required --watch
gh run view "$RUN_ID" --log-failed
gh pr merge "$PR" --auto --squash --delete-branch

# --exit-status 让失败体现在退出码上
gh run watch "$RUN_ID" --exit-status
gh pr checks --watch --fail-fast
```

### 一条命令看全当前分支状态（最实用的自检脚本）

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /Users/lex/git/knowledge

echo "=== 当前分支 ==="
git branch --show-current

echo "=== 未推送 commit ==="
git log --oneline @{u}..HEAD 2>/dev/null || echo "(无上游分支)"

echo "=== PR 状态 ==="
gh pr status --conflict-status || echo "(当前分支没有 PR)"

echo "=== PR 关键字段 ==="
gh pr view --json number,title,url,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup \
  --jq '{n: .number, title, url, mergeable, mergeStateStatus, reviewDecision,
        checks: [.statusCheckRollup[]? | {name, conclusion}]}' 2>/dev/null || true
```

---

## 11. 常见坑速查

| 现象 | 原因 / 解法 |
| --- | --- |
| `gh pr create` 提示 "head branch not pushed" | 显式 `--head` 会跳过自动 push，先 `git push -u origin <branch>` |
| `gh pr create` 开了浏览器 | 用了 `--web`，去掉即可 |
| `gh browse` 弹浏览器 | `gh browse` 默认开浏览器，加 `-n/--no-browser` 只打印 URL |
| `gh pr view` 提示找不到 PR | 当前分支没 PR；用 `gh pr list` 或 `gh pr view <number>` |
| `gh pr view --comments` 只有评论 | 输出被管道/重定向时行为不同，改用 `gh pr view --comments > f.txt` 或直接看终端 |
| `gh pr view --json` 报字段名错 | 字段名区分大小写，先 `gh pr view --json \| jq -r 'keys[]'` 看可用字段 |
| `gh run view --log` 说找不到日志 | 日志有保留期（默认 90 天），或该 job 还在跑 |
| `gh` 报 403 但 git push 正常 | token scope 不够，`gh auth refresh -s repo`（或 `workflow`） |
| `gh` 报 GraphQL 字段不存在 | API 版本差异，改用 REST `gh api repos/...` |
| CI 里卡住不动 | 有交互式提问，`export GH_PROMPT_DISABLED=1` |

---

## 12. 记忆法

```
gh auth status          # 我是谁
gh pr status            # 我这个分支现在啥状态
gh pr view              # 详情（网页信息终端版）
gh pr diff              # 改了什么
gh pr checks --watch    # CI 过了吗
gh pr merge --squash --delete-branch   # 合了、清理
gh run view <id> --log-failed          # CI 挂了看日志
gh browse -n            # 实在想点网页时，只拿 URL
```

**核心原则**：`gh` 的所有 `pr/issue/run` 子命令默认都在终端输出；只有 `gh browse` 和显式 `--web` 会开浏览器。
