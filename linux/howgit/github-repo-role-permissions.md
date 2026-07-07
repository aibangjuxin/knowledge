# GitHub Repo Collaborator Role 5 档权限详解(Read / Triage / Write / Maintain / Admin)

> **本文目的**:讲清 GitHub repo collaborator 5 个角色档的**精确权限差异**——不是社区经验总结,是直接从 [GitHub 官方文档](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization)的 **Capabilities table** 抓出来的逐行核对。
>
> **场景**:Settings → Collaborators and teams → Add collaborator / Manage access → Role 下拉框,你看到的 5 个档位的真实含义。

---

## §0 30 秒选型表(给懒得读完整篇的人)

如果你是 owner,正在给一个新成员加权限,**直接对照下表**:

| 你要这个人能做的事 | 给的角色 | 能不能合并 PR 到 main? |
| ------------------ | -------- | ---------------------- |
| **只看代码 / issue / 评论**,不动任何东西 | **Read** | ❌ |
| **管理 issue/discussion/PR**(分类、贴标签、评论、关 issue),但不 push 代码 | **Triage** | ❌(但能 approve/reject review) |
| **自己 push + 发 PR + 合自己的 PR** | **Write** | ✅(branch protection 不挡的话)|
| **合 PR / 改 repo 设置 / 改 branch protection**,**不删 repo** | **Maintain** | ✅ |
| **所有事,包括删 repo、转让、修改危险 settings** | **Admin** | ✅ |

**经验法则**(如果你只能记一条):

```
Read     → 看
Triage   → 整理(issue triage)
Write    → 写代码
Maintain → 运维(不动 repo 本身)
Admin    → 全部
```

---

## §1 GitHub 官方原话定义(Read → Admin)

直接引用 [GitHub Docs](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization):

> "From least access to most access, the roles for an organization repository are:
>
> **Read**: Recommended for non-code contributors who want to view or discuss your project
>
> **Triage**: Recommended for contributors who need to proactively manage issues, discussions, and pull requests without write access
>
> **Write**: Recommended for contributors who actively push to your project
>
> **Maintain**: Recommended for project managers who need to manage the repository without access to sensitive or destructive actions
>
> **Admin**: Recommended for people who need full access to the project, including sensitive and destructive actions like managing security or deleting a repository"

| 角色 | 缩写含义 | 适合谁 |
| ---- | ------- | ----- |
| **Read** | 只读 | 只想看代码、issue、PR 评论的贡献者(产品 / PM / 文档作者)|
| **Triage** | 整理 | 想主动推进 issue / discussion / PR,但不需要 push 代码 |
| **Write** | 写 | 在 repo 里有规律的 contributor,会 push 代码、发 PR |
| **Maintain** | 维护 | 项目经理 / 技术 lead,需要管 branch protection、CODETOWNERS、Release 等 |
| **Admin** | 完全控制 | 组织里 owner 的代管,所有事(包括删 repo)都能做 |

---

## §2 完整能力矩阵(逐项核对 5 档)

下面是从 GitHub 官方文档原表抓出来的,每行都是 **Read / Triage / Write / Maintain / Admin** 在这一项的真实 ✓/✗:

> ✓ = 有权限,✗ = 没有,**X** = 该角色存在但 GitHub 单独注了"Not applicable"或"doesn't apply"

### §2.1 基础读写能力

| Capability | Read | Triage | Write | Maintain | Admin |
| --- | --- | --- | --- | --- | --- |
| **Pull from the repo** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Fork the repo** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Edit/delete OWN comments** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **View published releases** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **View GitHub Actions workflow runs** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **View/install packages** | ✓ | ✓ | ✓ | ✓ | ✓ |

### §2.2 Issues(请注意 Read 的"只能关自己开的 issue")

| Capability | Read | Triage | Write | Maintain | Admin |
| --- | --- | --- | --- | --- | --- |
| **Open issues** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Close issues they opened themselves** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Reopen issues they closed themselves** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Have an issue assigned to them** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Apply/dismiss labels** | ✗ | ✓ | ✓ | ✓ | ✓ |
| **Create, edit, delete labels** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Close, reopen, and assign ALL issues** | ✗ | ✓ | ✓ | ✓ | ✓ |
| **Mark duplicate issues** | ✗ | ✓ | ✓ | ✓ | ✓ |
| **Create, edit, delete milestones** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Apply milestones** | ✗ | ✓ | ✓ | ✓ | ✓ |
| **Delete an issue**(管理员级别) | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Transfer issues to another repo** | ✗ | ✗ | ✓ | ✓ | ✓ |

### §2.3 Pull Requests

| Capability | Read | Triage | Write | Maintain | Admin |
| --- | --- | --- | --- | --- | --- |
| **Send pull requests from forks** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Submit reviews on PRs** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Approve/request changes on required reviews** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Apply suggested changes to PRs** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Enable/disable auto-merge on PRs** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Request PR reviews** | ✗ | ✓ | ✓ | ✓ | ✓ |
| **Merge a pull request** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Edit/delete ANYONE's comments on PRs** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Hide anyone's comments** | ✗ | ✓ | ✓ | ✓ | ✓ |
| **Lock conversations** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Act as a designated code owner** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Mark a draft PR as ready / convert to draft** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Push to protected branches**(单独看 protected branch 规则)| ✗ | ✗ | ✓ | ✓ | ✓ |
| **Merge PRs on protected branches WITHOUT required reviews** | ✗ | ✗ | ✗ | ✗ | ✓ |

### §2.4 GitHub Actions / Secrets / Variables

| Capability | Read | Triage | Write | Maintain | Admin |
| --- | --- | --- | --- | --- | --- |
| **Create, edit, run, re-run, cancel GH Actions workflows** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Create, update, delete GH Actions secrets on github.com** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Create, update, delete GH Actions secrets via REST API** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Create, update, delete GH Actions variables on github.com** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Create, update, delete GH Actions variables via REST API** | ✗ | ✗ | ✓ | ✓ | ✓ |

### §2.5 Releases / packages / topics

| Capability | Read | Triage | Write | Maintain | Admin |
| --- | --- | --- | --- | --- | --- |
| **Create and edit releases** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **View draft releases** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Publish packages** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Delete and restore packages** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Manage topics** | ✗ | ✗ | ✗ | ✓ | ✓ |

### §2.6 Repo settings 与 destructive actions(Admin-only 居多)

| Capability | Read | Triage | Write | Maintain | Admin |
| --- | --- | --- | --- | --- | --- |
| **Edit repo description** | ✗ | ✗ | ✗ | ✓ | ✓ |
| **Enable wikis and restrict wiki editors** | ✗ | ✗ | ✗ | ✓ | ✓ |
| **Configure PR merge settings** | ✗ | ✗ | ✗ | ✓ | ✓ |
| **Configure publishing source for GH Pages** | ✗ | ✗ | ✗ | ✓ | ✓ |
| **View Copilot content exclusion settings** | ✗ | ✗ | ✗ | ✓ | ✓ |
| **Manage branch protection rules and rulesets** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Push to protected branches**(with bypass policy)| ✗ | ✗ | ✓(看 bypass 规则) | ✓ | ✓ |
| **Manage webhooks and deploy keys** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Manage the forking policy** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Edit/repo default branch / rename default branch** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Rename a branch OTHER than the default branch** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Change repo visibility (public ↔ private)** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Make the repo a template** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Change repo settings** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Manage team and collaborator access to the repo** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Add a repo to a team** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Manage outside collaborator access** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Archive the repo** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Display sponsor button** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Edit custom property values for the repo** | ✗ | ✗ | ✗ | ✗ | ✓ |

### §2.7 Repo-level destructive actions(transfer / delete)

> **这段是 Maintain 和 Admin 的真正分水岭**

| Capability | Read | Triage | Write | Maintain | Admin |
| --- | --- | --- | --- | --- | --- |
| **Transfer the repo INTO the organization** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Delete or transfer the repo OUT of the org** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Create autolink references to external resources** | ✗ | ✗ | ✗ | ✗ | ✓ |

### §2.8 Discussions

| Capability | Read | Triage | Write | Maintain | Admin |
| --- | --- | --- | --- | --- | --- |
| **Create new discussions + comment** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Move discussion to different category** | ✗ | ✓ | ✓ | ✓ | ✓ |
| **Transfer discussion to new repo** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Manage pinned discussions** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Lock/unlock discussions** | ✗ | ✓ | ✓ | ✓ | ✓ |
| **Delete a discussion** | ✗ | ✓ | ✓ | ✓ | ✓ |
| **Create/edit categories for GH Discussions** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Enable GH Discussions in a repo** | ✗ | ✗ | ✗ | ✓ | ✓ |

### §2.9 Wikis

| Capability | Read | Triage | Write | Maintain | Admin |
| --- | --- | --- | --- | --- | --- |
| **Edit wikis in PUBLIC repositories** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Edit wikis in PRIVATE repositories** | ✗ | ✗ | ✓ | ✓ | ✓ |

### §2.10 Codespaces(云开发环境)

| Capability | Read | Triage | Write | Maintain | Admin |
| --- | --- | --- | --- | --- | --- |
| **Create codespaces for public repos** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Create codespaces for private repos** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **Create codespaces for private repos WITH Codespaces secrets access** | ✓ | ✓ | ✓ | **✓** | **✓** |

### §2.11 Security / Dependabot / Code Scanning

| Capability | Read | Triage | Write | Maintain | Admin |
| --- | --- | --- | --- | --- | --- |
| **Receive Dependabot alerts for insecure deps** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Dismiss Dependabot alerts** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **Create security advisories** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Manage access to GitHub Advanced Security features** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Enable dependency graph for a private repo** | ✗ | ✗ | ✗ | ✗ | ✓ |
| **View code scanning alerts on PRs** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **List, dismiss, delete code scanning alerts** | ✗ | ✗ | ✓ | ✓ | ✓ |
| **View and dismiss secret scanning alerts in a repo** | ✗ | ✗ | ✓ | ✓ | ✓ |

> ⚠ **GitHub 官方注解**:"Repository writers and maintainers can only directly view secret scanning alert information for their own commits. They cannot access the alert list view." — 即 Write/Maintain 看到的是 "自己 commit 的 secret scanning",**不能看 alert 列表**(这是 Admin 才行的)。

---

## §3 关键权限差异一句话总结

每两档之间只有**少量**具体差异,挑最能选型的维度:

### §3.1 Read vs Triage

| Read 不能但 Triage 能 |
| --- |
| 贴标签 / dismiss 标签 |
| 关闭自己**没有开的**issue |
| 给所有人 reassign issue |
| 标记 duplicate issue |
| Mark/unmark / lock conversations |
| 移动 discussion 到不同 category |

**Read 只看,Triage 才能主动"整理"**。

### §3.2 Triage vs Write

| Triage 不能但 Write 能 |
| --- |
| push 代码到任何分支 |
| 创建 / 删除 label |
| 创建 / 删除 milestone |
| 合 PR / merge -- squash / rebase |
| 改 wiki(私有仓库)|
| 编辑**任何人**的评论 |
| Lock conversations |
| transfer issues |
| 跑 GH Actions workflows |
| 改/删 GH Actions secrets |
| 创建/编辑 releases |
| 发布 packages |

**Triage 只整理 issue,Write 才能动代码**。

### §3.3 Write vs Maintain

| Write 不能但 Maintain 能 |
| --- |
| 改 repo description |
| 管理 topics |
| 启用 wiki + 限制 wiki editors |
| 配置 PR merge settings |
| 启用 GH Pages + 配置 publishing source |
| 启用 GH Discussions |
| **看 Copilot content exclusion settings** |

**Maintain 多了"管 repo 设置"(但不动敏感 destructive 的)**。

### §3.4 Maintain vs Admin(**核心分水岭**)

| Maintain 不能但 Admin 能 |
| --- |
| 管理 branch protection rules / rulesets |
| 改 repo settings(包括"转移 / 删除 / 设为 template")|
| 改 repo visibility(public ↔ private) |
| 改 default branch / rename default branch |
| 加 repo 到一个 team |
| 管理 outside collaborator |
| Archive repo |
| 添加 sponsor button |
| 创建 security advisories |
| 管理 GH Advanced Security 访问 |
| 启用 private repo 的 dependency graph |
| 删除 secret scanning alert list(和 codespace secrets with access) |

**Maintain 跟 Admin 的最大差别是"如果做错了会怎么样":**

- Maintain → 改错 issue 标签 = "哦,删掉就行,不影响别人"
- Admin → 改错 branch protection / 删错 repo / 改错 visibility = **可能影响全团队的工作**

---

## §4 跟 GitHub 其他机制组合时的角色表

### §4.1 Branch Protection Rules

Branch protection rules 的 **"Required number of approvals before merging"** 跟 role 互动时:

| Branch protection rule | 谁必须 approve / review 才让 PR merge |
| --- | --- |
| (无 rule) | Write+ 任意成员(包括 PR author 自己)|
| Required reviews = N | **任何人不算 PR author 自己**——即使是 Write/Maintain/Admin 都需要别人 approve |
| `CODEOWNERS` 文件存在 | **指定的 CODEOWNERS 成员**必须 approve(这就是为什么 owner 常同时拉同事做 CODEOWNERS) |

> ⚠ **Write 角色默认不能"merge 自己提的 PR"(如果开了 branch protection)**。这就是 GitHub "no self-approval" 的设计。

### §4.2 Repository Rulesets(GitHub 推出的下一代 branch protection)

| Capability | 必须 Admin 才能改的是 |
| --- | --- |
| Edit rulesets | Admin |
| Bypass rules(临时的,只在 PR/CI 跑)| 看 bypass policy 配置 |

> 详见[GitHub rulesets 文档](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets),跟 branch protection 是平行的两套机制(GH 正在迁移到 rulesets)。

### §4.3 CODEOWNERS 文件

- 写 `CODEOWNERS` 文件到 repo root(就一行是 username/team/path 映射)— 需要 **Write+** 就能 push
- 但是当 branch protection 开了 "Require review from Code Owners" 时,**只有指定的 CODEOWNERS 用户/team** 才能 approve/merge PR
- CODEOWNERS 身份是**附加**在角色上的,不替换角色

### §4.4 GitHub Teams 与 Repo-level 角色

给一个 team 加 collaborator 权限,实际上是把 team 当成一个"超级 collaborator":

- Team 可以拿 Read / Triage / Write / Maintain / Admin 角色
- Team 成员继承该角色
- 取消单个成员权限 = 把 team 中此成员**移出 team**

> 推荐用 team 而不是单个 user,理由跟 GCP IAM IAM 给 group 而不是 user 一个意思。

---

## §5 实战操作(Lex 怎么真去给某个人配)

### §5.1 通过 UI

```
1. Repo 页面 → 顶部 "Settings" tab
2. 左侧 "Collaborators and teams"
3. "Manage access" 按钮
4. "Invite a collaborator" 按钮(输入 username)
5. 在下拉框选 Role:
   - Read
   - Triage
   - Write
   - Maintain
   - Admin
6. "Add [username] to [repository]" 按钮
```

### §5.2 通过 GitHub API

```bash
# 给某用户加 Write 权限
curl -X PUT \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/OWNER/REPO/collaborators/USERNAME \
  -d '{"permission": "write"}'

# permission 可选值:
#   pull     = Read
#   triage   = Triage  (注意:不是 "triage",而是只有这一个值)
#   push     = Write
#   maintain = Maintain
#   admin    = Admin
```

> ⚠ API 的 permission 命名跟 UI 不完全一致——`pull/push` 是 v3 API 旧名,`triage/maintain/admin` 是 v3 API 新加值。但 README、code review 时应该用 Read/Triage/Write/Maintain/Admin 这一套 UI 名。

### §5.3 通过 GitHub Actions 的 GITHUB_TOKEN 临时权限

```yaml
jobs:
  my-job:
    runs-on: ubuntu-latest
    permissions:
      contents: write      # ← 这个改动 = GITHUB_TOKEN 临时拿 Write 权限
      pull-requests: write
      issues: write
    steps:
      - run: gh pr create ...
```

> 这跟"用户角色"完全不同——这里 GITHUB_TOKEN 是 Action 内临时身份,它会**继承** repo 的默认 token 权限,再用 `permissions:` 字段调整。

---

## §6 跟其它 role/身份系统的关系(避免混淆)

GitHub 上有很多"看起来像权限"但其实是不同概念的东西,这里给一个清晰的边界:

| 概念 | 作用范围 | 谁配 | 谁能升级 |
| --- | --- | --- | --- |
| **Org Owner** | 整个 org(不是 repo) | Org 自己的 settings | 别的 Owner |
| **Repo Admin** | 单个 repo | Repo Owner 或 Org Owner | Org Owner |
| **Team Maintainer**(对 team 而言) | 只能在 team 自己 settings 里改 description、私有性 | Org Owner / Org admin | Org Owner |
| **Outside Collaborator** | 一类用户身份,人在 org 外但被 invited 到某个 repo | Repo Owner / Org Owner | Repo Owner / Org Owner |
| **App Install permissions** | 安装的 GitHub App 在 repo 内的权限 | App 自身的 settings | App 创建者 |
| **Branch protection "required review"** | 单个 branch | Repo Maintain/Admin | Admin |

> 注意 **Org Owner 不在 5 档里**——Org Owner 是**单独一档**(整个 org 的全权),跟 repo Admin 不冲突但有更高权限,可以改 repo Admin 改不了的事(transfer org、收费管理)。

---

## §7 给 Lex 的几个常见场景速答

| 场景 | 给什么 role? |
| --- | --- |
| **新人刚加入,先看代码熟悉** | Read |
| **新人要给他写权限,但有 branch protection 守门** | Write(branch protection 已经挡坏 merge)|
| **第三方公司的人,只想让他看 issue 帮我整理**(如 support 公司)| Triage |
| **要 release manager 帮我管 release、CODETOWNERS、wiki** | Maintain |
| **我信任的同事,平时自己处理 PR / 修 branch protection** | Maintain(不要直接给 Admin!)|
| **要替 owner 的人,不在 owner 名下也能管** | Admin |
| **GH Advanced Security / Dependabot / codespace secrets 你都需要管理** | Admin(Admin-only 区域)|

---

## §8 FAQ(常见踩坑)

### §8.1 为什么我给某个人 "Write",他还是不能 merge 自己的 PR?

**Branch protection**。最常见的是 **`master`/`main` 分支上 Require pull request reviews before merging = 1**——这种 rule 强制要求"至少 1 个不是 PR author 的人 approve"。

**修法**:不是改 user role(改成 Maintain/Admin 也帮不了),而是去 Settings → Branches → main → **取消"Require approval"或者把它改成 0(但强烈不推荐)**。

### §8.2 为什么我给了 Write 但 `gh pr merge` 在 gh CLI 里失败?

跟 §8.1 一样——是 branch protection,不是 role 不够。

**验证命令**:

```bash
gh api repos/OWNER/REPO/branches/main/protection | jq .
# 如果是空 {} —— 无保护
# 有内容 —— 看 "required_pull_request_reviews" 段
```

### §8.3 我加协作成员,但是 UI 提示"invitation declined"怎么办?

多半是因为对方账号 email 与 GitHub 注册 email 不匹配,或者对方在组织里被 ban。改用 GitHub CLI:

```bash
gh api -X PUT repos/OWNER/REPO/collaborators/USERNAME \
  -f permission=push
```

### §8.4 Read-only 角色能下载私有 repo 的代码吗?

**能**。**Read 角色可以 git clone**(pull 权限)。这跟 GitLab "Guest" 角色不同(GitLab Guest 看 issue 不看代码)。

**"只能 clone + 不能 push"是 Read 角色唯一能干的事**——对有些场景这就够了(比如让 contractor 临时拉代码 review 不动代码)。

### §8.5 Maintainer 跟 Admin 看起来差不多,我应该给谁用 Maintain?

经验法则:

```
"如果这个人不小心出错,会让我 (owner) 心里痛多久?"
   痛很久 → Admin 不给,自己上
   痛一下 → Maintain OK
```

具体哪些事 Maintain 不能干(才需要 Admin):**删 / 转移 / 改 visibility / 改 branch protection / 改 default branch / archive**。这些都是"动完不容易恢复的"。

---

## §9 参考链接

| 来源 | 链接 |
| --- | --- |
| GitHub 官方原档(能力表原文) | [docs.github.com/.../repository-roles-for-an-organization](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization) |
| GitHub API v3 `permission` 取值 | [docs.github.com/.../collaborators#add-a-repository-collaborator](https://docs.github.com/en/rest/collaborators/collaborators?apiVersion=2022-11-28#add-a-repository-collaborator) |
| Branch Protection Rules | [docs.github.com/.../about-protected-branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) |
| Repository Rulesets(新一代)| [docs.github.com/.../managing-rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets) |
| CODEOWNERS | [docs.github.com/.../about-code-owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) |
| GH Actions `permissions:` 字段 | [docs.github.com/.../workflow-syntax-for-github-actions#permissions](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#permissions) |
| GITHUB_TOKEN 权限范围 | [docs.github.com/.../automatic-token-authentication](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication) |
| Org vs Repo 角色体系 | [docs.github.com/.../roles-in-an-organization](https://docs.github.com/en/organizations/managing-peoples-access-to-your-organization-with-roles/roles-in-an-organization) |

---

## §10 同目录其他文档索引(规划中)

> `howgit/` 目录目前只有本文件。后续按主题新增(branch protection rules / CODEOWNERS / GitHub Actions permissions / ...)。
