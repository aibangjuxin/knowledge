# 如何获取 Rebase 后 PR 的最新 Commit ID

## 场景描述

你和同事各自基于同一个旧 `master` 提交 A 开 PR：

```
                    A (旧 master tip, commit X)
                   / \
       同事 PR#68 →   B --- C (同事先合到 master)
                   \
       我的 PR#67 →   D --- E --- F (我的分支,基于旧 master)
```

同事的 PR#68 **先合并**到 `master`，于是 `master` 指针前进到 `C`。
你为了让 PR#67 顺利合入，对自己的分支做了 `rebase`（或 `merge master`）：

```
                          B --- C (新 master tip)
                         /       \
       同事已合入 →   A         D' --- E' --- F' (我的 PR#67,内容不变,commit ID 全变)
                                  ↑
                            这个 D' 就是你要的"最新 commit ID"
```

**核心矛盾**：

- PR 编号 (`#67`) 不变 —— 它只是个序号，不会被 rebase 影响
- 但你分支上**每一个 commit 的 hash 都会变**（因为 parent 变了，时间戳变了）
- 你在 issue / ticket / CI / 流水线里硬编码的旧 hash `D` 失效了
- 合并到 master 之前，需要拿到分支最新的 tip commit ID

---

## 推荐方案：GitHub CLI（gh）

> ✅ **最直接、最稳、最适合 CI/CD 自动化**

### 1) 获取 PR 当前 head 的完整 commit ID

```bash
gh pr view 67 --json headRefOid --jq '.headRefOid'
```

输出示例：

```
a1b2c3d4e5f67890abcdef1234567890abcdef12
```

### 2) 获取短 hash（前 7 位）

```bash
gh pr view 67 --json headRefOid --jq '.headRefOid' | cut -c1-7
# 输出: a1b2c3d
```

### 3) 获取 PR 的所有 commits（最后一个就是 head）

```bash
gh pr view 67 --json commits --jq '.commits[-1].oid'
```

### 4) 一次性输出关键字段

```bash
gh pr view 67 \
  --json number,title,headRefOid,baseRefOid,state,mergeable \
  --jq '"\(.number) |\(.title) | head=\(.headRefOid[0:7]) | base=\(.baseRefOid[0:7]) | state=\(.state) | mergeable=\(.mergeable)"'
```

输出示例：

```
67 | Add OAuth login | head=a1b2c3d | base=9f8e7d6 | state=OPEN | mergeable=MERGEABLE
```

### 5) 配合 rebase 工作流的标准三步曲

```bash
# Step 1: 同步 master 并 rebase
git fetch origin
git checkout feature/oauth-login
git rebase origin/master

# Step 2: 强制推送（注意用 --force-with-lease）
git push --force-with-lease origin feature/oauth-login

# Step 3: 立刻拿最新的 head commit ID
gh pr view 67 --json headRefOid --jq '.headRefOid'
```

---

## 备选方案

### 方案 A：GitHub REST API

适合不能用 `gh` 的 CI 环境（裸 curl 即可）：

```bash
# 完整 hash
curl -s \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  https://api.github.com/repos/OWNER/REPO/pulls/67 \
  | jq -r '.head.sha'

# 短 hash
curl -s \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  https://api.github.com/repos/OWNER/REPO/pulls/67 \
  | jq -r '.head.sha[:7]'
```

`OWNER/REPO` 替换成你自己的，例如 `lex/k8s-platform`。

**注意**：`/pulls/{n}` 返回的是 PR 的**最新 head**，会自动反映 rebase 后的状态 —— 这正是我们想要的。

### 方案 B：本地 git 命令（前提：本地分支已 rebase 且推送）

```bash
# 当前分支的完整 hash
git rev-parse HEAD

# 短 hash
git rev-parse --short HEAD

# 当前分支在远端的最新 hash
git rev-parse origin/feature/oauth-login

# 最近一次提交的 hash（无论在哪个分支）
git log -1 --format=%H
git log -1 --format=%h   # 短 hash

# 显示最近 N 次提交 + 关联 PR（如果有 gh 集成）
git log -5 --oneline
```

**适用场景**：

- 你刚 `git push --force-with-lease` 完，本地 HEAD 就是最新 hash
- 不需要联网查询 GitHub
- 缺点：分支没拉下来就没法用

### 方案 C：GitLab Merge Request 场景

```bash
# GitLab API
curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://gitlab.com/api/v4/projects/${PROJECT_ID}/merge_requests/67" \
  | jq -r '.sha'

# GitLab CLI (glab)
glab mr view 67 --output json | jq -r '.sha'

# 本地 git（如果你有 clone 这个 MR）
git rev-parse HEAD
```

### 方案 D：Gitee / 码云场景

```bash
# Gitee Open API
curl -s \
  -H "Authorization: bearer ${GITEE_TOKEN}" \
  "https://gitee.com/api/v5/repos/OWNER/REPO/pulls/67" \
  | jq -r '.head.sha'

# Gitee Go CLI（如果团队在使用）
# 详见 https://gitee.com/help/articles/4294
```

### 5) 从 PR 的 Commits 页面直接拿（✅ 最直观、最权威的来源）

GitHub 为每个 PR 都提供了一个**专用的 commits 列表页**:

```
https://github.com/OWNER/REPO/pull/67/commits
```

这个页面有这些关键属性:

- ✅ **页面里出现的所有 commit,都是 PR 当前 head 分支上的真实 commit**
- ✅ **列表里最后一个 commit = 当前最新 commit ID**(也就是分支 tip)
- ✅ 只要你的分支 update 到 latest branch(rebase/merge master 之后),这个页面会自动刷新成新的 commits 列表
- ✅ 不需要登录认证,不需要 gh CLI,不需要 API token,浏览器直接看

**使用步骤**:

1. 打开 `https://github.com/OWNER/REPO/pull/67/commits`
2. 滚到列表**最底部**,最后一个 commit 右侧的 hash(短码 `a1b2c3d`)就是最新 commit ID
3. 点 commit 标题可以进入详情页,URL 里 `commit/<full-hash>` 就是完整 40 位 hash
4. 如果列表里只有一个 commit,那它就是最新的;如果有多个,只看**最后一个**

**典型场景示例**:

```
场景 A: 你的 PR#67 只 rebase 了一次,还没改过代码
PR#67/commits 页面:
   └── a1b2c3d Update README       ← 只有 1 个,这就是最新的 commit ID

场景 B: rebase 之后又改了一轮代码,新增了一个 fix commit
PR#67/commits 页面:
   ├── abc1234 Add OAuth login
   └── def5678 Fix login redirect   ← 最后这个是最新 commit ID

场景 C: 你 push 了 N 次,rebase 了 M 次
PR#67/commits 页面:
   ├── xxxxxxx (旧 commit 1, rebase 后内容变了但你重新 push 不会留着)
   ├── xxxxxxx (旧 commit 2)
   └── zzzzzzz (最近一次 push 的最后一个 commit)  ← 这就是最新 commit ID
```

**和 headRefOid 的关系**:

`https://github.com/OWNER/REPO/pull/67/commits` 列表里**最后一个 commit 的 hash**,和 API 返回的 `headRefOid` 是**同一个值**。
两者是同一个数据源的不同呈现方式 —— 页面给人类看,API 给脚本读。

**对应 API 验证(可选,自动化场景)**:

```bash
# API 和页面是同一个数据源 —— 用 API 拿到的就是页面最后一个 commit
gh pr view 67 --json headRefOid,commits --jq '{
  page_last_commit: .commits[-1].oid,
  api_head_ref: .headRefOid,
  match: (.commits[-1].oid == .headRefOid)
}'
# match: true → API 和页面一致
```

> 💡 **一句话总结**: 只要你保持分支 update 到 latest branch(rebase/merge master 后再 push),
> 打开 `https://github.com/OWNER/REPO/pull/67/commits`,**列表最下面那个 commit 就是最新的 commit ID** —— 不需要 gh,不需要 API,只需要一个浏览器。

---

### 5.1) PR 多次提交后,"最新的 commit ID" 到底指哪个？

你和同事的改动都在 `master` 上做,但 PR 会记录**每一次 push 到 PR 分支的新提交**。
当 PR 里出现多个 commit 时,**最新的 commit ID 永远 = 分支 tip 那个 hash**,也就是**列表里最后一个 commit**。

**两种查看方式,本质上是同一个数据源**:

```bash
# 方式 1: 通过 GitHub commits 页面(浏览器,最直观)
# https://github.com/OWNER/REPO/pull/67/commits
# 滚到最下面,最后一个 commit 就是最新的

# 方式 2: 通过 gh CLI(脚本自动化)
gh pr view 67 --json headRefOid,commits --jq '{
  最新commitID: .commits[-1].oid,
  短码: .commits[-1].oid[0:7],
  标题: .commits[-1].messageHeadline,
  时间: .commits[-1].committedDate,
  与headRefOid一致: (.commits[-1].oid == .headRefOid)
}'
```

如果 `与headRefOid一致` 输出 `true`,说明页面显示的最后一个 commit 就是当前最新的 commit ID —— 这就是合并前需要锁定的那一个。

---

## 通过个人分支查 Commit ID（个人账户默认 branch 场景）

### 场景背景

你和同事的改动都直接 commit 在 `master` 上，没有单独开 feature 分支。
你们各自把改动 push 到自己的 fork / 个人账户下的 `master` 默认分支：

```
upstream/master (origin/master)
   └── PR#67  ← 你的改动, base = upstream/master
        └── head 指向 你个人账户的 master 分支 tip

upstream/master
   └── PR#68  ← 同事的改动, base = upstream/master
        └── head 指向 同事个人账户的 master 分支 tip
```

这时候有两条路径可以拿到 commit ID：

### 方案 1：通过 PR head 查（✅ 最推荐）

个人账户的 master 分支 tip **理论上等于** PR 的 head，但中间可能有延迟或自动 sync 逻辑不一致 —— **永远以 PR API 为准**。

```bash
# GitHub 上 PR 的 head 永远指向它对应的源分支 tip
gh pr view 67 --json headRefOid,headRefName --jq '"\(.headRefName) -> \(.headRefOid)"'
# 输出: lex:master -> a1b2c3d4e5f67890abcdef1234567890abcdef12
```

注意 `headRefName` 格式是 `OWNER:BRANCH`，例如 `lex:master`、`zhangsan:master`。

### 方案 2：直接查个人账户的默认分支（⚠️ 慎用，备选）

如果你出于某些原因拿不到 PR 信息（例如 PR 还没创建、或者只在命令行操作），可以直接查个人分支的 tip：

```bash
# GitHub API: 查 lex 这个用户下 k8s-platform 仓库的 master 分支 SHA
curl -s \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  https://api.github.com/repos/lex/k8s-platform/branches/master \
  | jq -r '.commit.sha'

# 短 hash
curl -s \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  https://api.github.com/repos/lex/k8s-platform/branches/master \
  | jq -r '.commit.sha[:7]'
```

或者用 `gh`：

```bash
# 查看个人账户下某仓库某分支的最新 commit
gh api repos/lex/k8s-platform/branches/master --jq '.commit.sha'
```

### 方案 3：本地 git 查（如果你 clone 了自己的 fork）

```bash
# 添加个人 fork 作为 remote（如果还没加）
git remote add personal git@github.com:lex/k8s-platform.git
git fetch personal

# 查个人账户 master 的 tip
git rev-parse personal/master

# 短 hash
git rev-parse --short personal/master

# 查看最近 5 次提交，确认是不是你的最新改动
git log personal/master -5 --oneline
```

### ⚠️ 个人分支查 commit ID 的三大坑

**坑 1：自动 sync 导致的"幽灵 commit"**

很多团队设置 GitHub Actions 自动把 `upstream/master` sync 到个人 fork 的 `master`，
sync 动作本身会产生一个 merge commit 出现在你的 `personal/master` tip 上 —— 但这个 commit **不在你的 PR 里**。

```bash
# 验证: 如果 personal/master 的 tip 不在 PR 的 commits 数组里,说明是 sync 提交
PERSONAL_SHA=$(gh api repos/lex/k8s-platform/branches/master --jq '.commit.sha')
PR_SHA=$(gh pr view 67 --json headRefOid --jq '.headRefOid')

if [ "$PERSONAL_SHA" != "$PR_SHA" ]; then
  echo "⚠️  personal/master tip ($PERSONAL_SHA) ≠ PR#67 head ($PR_SHA)"
  echo "    大概率是 upstream sync 动作产生的 commit,不要用 personal/master 的 SHA"
fi
```

**解法**：永远以 PR API 为准，不要相信个人分支的 tip。

**坑 2：base 滞后导致看似"未同步"**

upstream master 已经前进，但你个人 master 还停在旧位置 —— 此时你 push 的 commit 会被 rebase 到一个旧 base 上，
PR 的 `headRefOid` 也会是 rebase 后的新 hash。如果直接用个人 master 的 SHA，拿到的是错的。

```bash
# 强制同步
git fetch upstream master
git checkout master
git reset --hard upstream/master
git push personal master --force-with-lease
```

**坑 3：个人账户 branch 命名 ≠ `master`**

有些团队或 fork 流程会改默认分支名（比如改成 `main`），或者你本地分支叫 `feature/oauth` 但个人账户 fork 的默认分支叫 `master`。

```bash
# 先查清楚 PR 的 head ref 到底是什么
gh pr view 67 --json headRefName,headRepository --jq '{
  headRef: .headRefName,
  headRepo: .headRepository.nameWithOwner
}'
# 输出: { "headRef": "master", "headRepo": "lex/k8s-platform" }
```

再去查 `lex/k8s-platform` 仓库的 `master` 分支 tip。

---

## 推荐决策流程（个人 master 分支场景）

```
                    你想拿 PR#67 最新 commit ID
                              │
                              ▼
        ┌────────────────────────────────────┐
        │  用 gh pr view 拿 headRefOid       │ ← ✅ 唯一权威来源
        │  gh pr view 67 -json headRefOid    │
        │    --jq '.headRefOid'              │
        └────────────────────────────────────┘
                              │
                              ▼
              ┌──────────────────────────────┐
              │ 拿不到？（PR 不存在 / 还没建） │
              └──────────────────────────────┘
                              │
                              ▼
        ┌────────────────────────────────────┐
        │ 查个人账户 master 分支 tip          │
        │ gh api repos/USER/REPO/branches/   │
        │   master --jq '.commit.sha'        │
        └────────────────────────────────────┘
                              │
                              ▼
              ┌──────────────────────────────┐
              │  验证: 这个 SHA 是不是        │
              │  你预期的那次提交              │
              │  git log <sha> -1 --stat       │
              └──────────────────────────────┘
```

**一句话原则**：

> 📌 **PR 是 commit ID 的"稳定锚点"，个人 fork 的默认 branch 只是"镜像"，可能延迟、可能含 sync 噪声。永远优先用 PR API，branch tip 只作交叉验证。**

---

## 实战脚本：rebase 完一键打印所有需要的 ID

放进你的 `~/.gitconfig` 的 `[alias]` 段，或者保存为 `git-prid` 脚本：

### 脚本 1：单条 alias（最快上手）

```bash
git config --global alias.prid '!f() { \
  gh pr view "$1" --json headRefOid,baseRefOid,number,title \
    --jq "\"\n  PR     : #\(.number) - \(.title)\n  head   : \(.headRefOid)\n  base   : \(.baseRefOid)\n  short  : head=\(.headRefOid[0:7]) base=\(.baseRefOid[0:7])\n\""; \
}; f'
```

使用：

```bash
git prid 67
```

输出：

```
  PR     : #67 - Add OAuth login
  head   : a1b2c3d4e5f67890abcdef1234567890abcdef12
  base   : 9f8e7d6543210fedcba9876543210fedcba9876
  short  : head=a1b2c3d base=9f8e7d6
```

### 脚本 2：完整 sync 流水线

保存为 `scripts/sync-pr.sh`，给执行权限 `chmod +x`：

```bash
#!/usr/bin/env bash
# sync-pr.sh — rebase 当前分支到最新 master,推送,并打印新的 head commit ID
# 用法: ./sync-pr.sh <PR_NUMBER>

set -euo pipefail

PR_NUMBER="${1:?Usage: $0 <PR_NUMBER>}"
MAIN_BRANCH="${MAIN_BRANCH:-master}"

echo "==> 1. 同步 origin/$MAIN_BRANCH"
git fetch origin "$MAIN_BRANCH"

echo "==> 2. Rebase 当前分支到 origin/$MAIN_BRANCH"
CURRENT_BRANCH=$(git symbolic-ref --short HEAD)
git rebase "origin/$MAIN_BRANCH"

echo "==> 3. 强制推送 (--force-with-lease, 安全)"
git push --force-with-lease origin "$CURRENT_BRANCH"

echo "==> 4. 获取 PR#$PR_NUMBER 的最新 head commit ID"
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')
echo "    full : $HEAD_SHA"
echo "    short: ${HEAD_SHA:0:7}"

echo "==> 5. 可选: 把 commit ID 写到一个文件,供 CI 使用"
echo "$HEAD_SHA" > .last_pr_head_sha
echo "    saved to .last_pr_head_sha"

echo ""
echo "✅ 完成! PR#$PR_NUMBER 最新 head commit: ${HEAD_SHA:0:7}"
```

使用：

```bash
./sync-pr.sh 67
# 一键完成:fetch → rebase → push → 拿 ID
```

### 脚本 3：CI 里记录每次 PR 的最新 commit

```yaml
# .github/workflows/record-pr-head.yml
name: Record PR Head SHA
on:
  push:
    branches-ignore: [master, main]

jobs:
  record:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Get current PR head SHA
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          PR_NUMBER=$(gh pr list --head "${{ github.ref_name }}" --json number --jq '.[0].number')
          HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')
          echo "PR=#$PR_NUMBER HEAD=$HEAD_SHA"
          echo "##[set-output name=head_sha;]$HEAD_SHA"   # 老语法
          # 实际现代用法见下方注释
```

> 现代用法：用 `$GITHUB_OUTPUT` 而不是 `set-output`，这里只是演示思路。

---

## 关键注意事项

### 1) 为什么不能用本地 HEAD 直接相信？

- 如果你 `rebase` 完没推送，本地 HEAD 和 GitHub 上的 head **是不同的**
- 本地 HEAD 是新的 hash；GitHub 上的还是旧 hash（因为 PR branch tip 没更新）
- **一定要从 GitHub API 拿**，不要从 `git rev-parse HEAD` 拿 —— 除非你刚 push 过

### 2) Rebase vs Merge 对 commit ID 的影响

| 操作 | commit ID 是否变 | 历史是否线性 | 适合场景 |
|------|------------------|--------------|----------|
| `git rebase master` | ✅ 全部变 | ✅ 线性 | 个人 feature 分支、追求干净历史 |
| `git merge master`  | ✅ merge commit 新增 | ❌ 多分叉 | 协作分支、保留完整历史 |
| `git pull --rebase` | ✅ 本地未推送 commit 变 | ✅ 线性 | 日常 sync，避免 merge 噪声 |

所以**只要 master 前进过、你的分支要跟上，commit ID 一定会变** —— 这是 git 的设计，不是 bug。

### 3) 如何减少 ID 漂移带来的混乱

- **不要在代码注释、issue、ticket 里硬编码 commit hash** —— 它一定会失效
- **用 PR 编号而不是 commit hash 引用变更** —— PR 编号跨 rebase 稳定
- **CI 里需要锁定某个 commit，用 tag 而不是 branch tip**：`git tag pr-67-stable <sha>` 后用 tag 引用
- **频繁 rebase + force push 会让 reviewer 抓狂** —— 一次 PR 期间 rebase 次数 ≤ 2 次为佳

### 4) `force-with-lease` vs `--force`

```bash
# ❌ 危险:覆盖远端,可能丢同事的提交
git push --force

# ✅ 安全:如果远端比你预期的要新,拒绝推送
git push --force-with-lease
```

永远用 `--force-with-lease`，它会检查你本地记录的远端 ref 是否还是你 fetch 时的那个。

### 5) `--force-with-lease` 在 PR 协作中的注意事项

如果同事也在往同一个 PR 分支 push，force push 会覆盖他的提交。
**解决方案**：

- PR 分支只归一个人所有 → 其他人开新分支
- 或者用 `git push --force-with-lease --force-if-includes`（Git 2.30+）

---

## 快速决策表

| 你要做什么 | 用什么命令 |
|------------|------------|
| 在本机拿到当前分支最新 hash | `git rev-parse HEAD` |
| 拿到 PR 在 GitHub 上的最新 hash | `gh pr view 67 --json headRefOid --jq '.headRefOid'` |
| 在 CI 里拿 PR 最新 hash | GitHub API + curl + jq |
| 拿到 merge 后的最终 commit | `gh pr view 67 --json mergeCommit --jq '.mergeCommit.oid'` |
| 拿到 base 分支 hash | `gh pr view 67 --json baseRefOid --jq '.baseRefOid'` |
| 列出 PR 的所有 commit | `gh pr view 67 --json commits --jq '.commits[].oid'` |
| 拿到短 hash（7 位） | `cut -c1-7` 或 `${SHA:0:7}` |

---

## 总结

**最推荐的一行命令**（GitHub 场景）：

```bash
gh pr view <PR_NUMBER> --json headRefOid --jq '.headRefOid'
```

不管你的分支被 rebase 多少次、commit ID 怎么变，**PR 编号是稳定的锚点**，
通过它去 GitHub API 查 `head.sha` / `headRefOid`，永远能拿到**合并前那一刻**的最新 commit ID。

记住：

> 📌 **不要追踪 commit ID，追踪 PR 编号。** PR 编号通过 API 解析出当前 commit ID —— 这是最稳的工作流。
