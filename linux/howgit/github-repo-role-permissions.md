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

---

## §11 进阶:让"特定组"审批才能 merge 到 main — CODEOWNERS + Branch Protection

> 本节回应 Lex 的 follow-up 疑问:"如果我想 merge 到 master 的时候必须有特殊的一个组内的成员审批,应该怎么实现?"
>
> 答案:**两个机制叠加**——`CODEOWNERS` 文件(声明谁是 owner)+ Branch protection rule(必须 owner approve 才能 merge)。

### §11.1 实现路径总览(3 步)

```
    Step 1 ─→  Step 2 ─→  Step 3 ─→   完成
   在 repo 加    设 branch     PR 试图    特定组的人
   CODEOWNERS    protection    merge to    必须 approve
   文件, 声明    rule, 打开    main 时     否则 merge
   哪个组是      "Require      被挡住      按钮 disable
   owner         review from   (灰色)
                 Code Owners"
```

**关键点**:Role (§0-§9 讲的) 跟 CODEOWNERS 是**完全独立的两层**:
- **Role** 决定"这个用户能不能 push / 合 / 改设置"
- **CODEOWNERS** 决定"这次 PR 改的是这部分代码,需要哪些人来审批"

所以即使你给一个人 **Write** 角色,他没在 CODEOWNERS 里,他**也能 push**,但他自己提的 PR 想 merge 时,**也必须等 CODEOWNERS 列出的那个人 approve**(包括他自己的 approve 也不算)。

### §11.2 官方原话(已直接 curl 验证)

[GitHub Docs · CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) 原话:

> "Repository owners can update branch protection rules to ensure that changed code is reviewed by the owners of the changed files."
>
> "Edit your branch protection rule and enable the option **'Require review from Code Owners'**."
>
> "When someone with admin or owner permissions has enabled required reviews, **they also can optionally require approval from a code owner before the author can merge a pull request in the repository.**"
>
> "When the code owner is a team, **that team must be visible and it must have write permissions**, even if all the individual members of the team already have write permissions directly, through organization membership, or through another team membership."

[GitHub Docs · Branch protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) 原话:

> "Optionally, you can choose to **require reviews from code owners**. If you do, any pull request that affects code with a code owner **must be approved by that code owner** before the pull request can be merged into the protected branch."

### §11.3 Step 1 — 写 CODEOWNERS 文件

CODEOWNERS 文件的位置(任选其一):

| 位置 | 优先级 |
| --- | --- |
| `.github/CODEOWNERS` | **推荐**(GitHub 2020+ 官方推荐)|
| 仓库根目录 `/CODEOWNERS` | OK |
| `docs/CODEOWNERS` | OK |

**文件内容** 用冒号分隔 `path-pattern` 和 `owner`:

```gitignore
# CODEOWNERS
# 语法: <pattern>      @<username> | @<org>/<team>
#
# pattern 跟 .gitignore 类似,但有几个不能用:[ ] 字符范围 / ! 否定 / \ 转义

# ─────── 全局 owner ───────
# 任意文件改 PR → 默认所有改动都需要 admin-team 这个 org team 审批
*                       @caep/admin-team

# ─────── 子目录 owner ───────
# 改 /src/db/ 目录的所有文件 → db-team 这个 team 审批
/src/db/               @caep/db-team

# ─────── 多个 owner(任一即可) ───────
# 改 /src/payments/ 目录 → payments-team OR security-team 任何一个人审批
/src/payments/         @caep/payments-team @caep/security-team

# ─────── 具体文件 ───────
# 单文件 owner
README.md              @lex
SECURITY.md            @caep/security-team

# ─────── 通配符模式 ───────
# 任意 .sql 文件
*.sql                  @caep/db-team

# 任意 docs/ 目录下的 .md 文件 (不递归)
/docs/*.md             @caep/docs-team

# 任意 docs/ 目录及其子目录下的 .md 文件 (递归)
/docs/**/*.md          @caep/docs-team

# ─────── 行末注释 ───────
# 这行只有 final approver(team 必须配 write 权限,详见 §11.5)
/src/core/             @caep/core-team     # 核心代码组双重审批
```

**注意**:CODEOWNERS 的**路径是相对仓库根**,`/` 开头 = 锚定根,`/` 结尾 = 目录(递归),不带 `/` 结尾 = 单文件或匹配 glob。

### §11.4 Step 2 — 配 Branch Protection Rule

> 网页路径:**Repo Settings → Rules → Rules and rulesets → Branch protection rules → Create/Edi**

下面用网页 UI 和 GitHub API 两种方式给具体步骤。

#### 11.4.1 网页 UI(最直观)

```
1. 进入 repo → Settings tab
2. 左侧 Rules → Rules and rulesets
3. 点 "New branch protection rule" 按钮

   ← 旧版(还在)
   ← 或 "Add rule" / "Edit rule"

4. Branch name pattern(分支名模式):
   main            # 全限定 main
   *               # 全部分支
   releases/*      # releases/ 前缀的所有分支

5. 勾选以下选项(其它保持默认):
   ☑ Require a pull request before merging
       ☑ Require approvals: 1   (或更多,例如 2)
   ☑ Require review from Code Owners    ← 关键!
   ☑ Include administrators  ← 让 admin 也要过这一关(可选但强烈推荐)

6. 点 "Create" / "Save changes"
```

**关键选项说明**:

| 选项 | 含义 | Lex 需要的场景 |
| --- | --- | --- |
| **Require a pull request before merging** | 不允许直接 push,必须 PR | 始终勾选 |
| **Require approvals: N** | PR 需要 N 个 approve | 1 通常够,关键团队可能要 2 |
| **Require review from Code Owners** ⭐ | **触发了 CODEOWNERS 文件生效** | **必须勾选** |
| **Dismiss stale pull request approvals when new commits are pushed** | push 新 commit 后旧 approve 失效 | 推荐勾选(防止 approve 完之后悄悄改代码)|
| **Require approval of the most recent reviewerable push** | 最后一次 push 必须被非 author 的人 approve | 推荐 |
| **Include administrators** | admin 也要被这条 rule 限制 | 推荐(否则 admin 绕过整个流程)|
| **Restrict who can dismiss pull request reviews** | 谁能"撤销 review" | 不是 Lex 关心的 |
| **Allow specified actors to bypass required pull requests** | 谁可以绕过 review 直接 push | 给 hotfix 留口子时用 |

#### 11.4.2 GitHub API v3(用 API 配,可以进 CI/CD / IaC)

```bash
# 给 main 分支设保护规则(包含 CODEOWNERS 要求)
curl -X PUT \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/OWNER/REPO/branches/main/protection \
  -d '{
    "required_status_checks": null,
    "enforce_admins": true,
    "required_pull_request_reviews": {
      "dismissal_restrictions": {},
      "dismiss_stale_reviews": true,
      "require_code_owner_reviews": true,        ← 关键!
      "required_approving_review_count": 1,
      "require_last_push_approval": true
    },
    "restrictions": null,
    "required_linear_history": false,
    "allow_force_pushes": false,
    "allow_deletions": false,
    "required_signatures": false,
    "block_creations": false,
    "required_conversation_resolution": true
  }'
```

**关键字段**:

- `"require_code_owner_reviews": true` ← 触发了 CODEOWNERS 强制
- `"enforce_admins": true` ← admin 也要遵循此规则
- `"required_approving_review_count": 1` ← PR 至少需要 1 个 approve

### §11.5 让你的 team 真的能 approve(很容易踩坑)

**关键陷阱**:**team 必须有 write 权限才被 GH 承认是合法的 CODEOWNERS owner。**

来自 [GitHub Docs 原话](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners):

> "When the code owner is a team, **that team must be visible and it must have write permissions**, even if all the individual members of the team already have write permissions directly, through organization membership, or through another team membership."

**"即使每个 team member 个人都是 Write,"他作为 team 名义出现时,team 必须**显式**有 Write 权限**,否则 GH 拒绝识别成 owner**。

具体配法(让 team 有 Write 权限):

| 步骤 | 路径 | 设置 |
| --- | --- | --- |
| 1 | Org Settings → Teams → 选 team | 确认 team 是 visible(不是 secret)| 
| 2 | Repo Settings → Collaborators and teams → Add teams | 选 db-team,Role = **Write**(或更高) |
| 3 | 在 CODEOWNERS 里写 `@<org>/db-team` 不是 `@db-team`(注意带 org 名前缀)| |

> ⚠ **Org 内 5 档 role 里 Triage 是不够的** — Triage 角色不能 push,GH 会报"team doesn't have write permissions"。**至少要 Write**。Maintain / Admin 也行(都包含 write)。

### §11.6 PR 想 merge 时,流程是怎么被挡的

Lex 最关心的"具体怎么 work":

```
[1] Developer X 提 PR: 修改 src/payments/test.py
    (src/payments/ 的 CODEOWNERS 是 @caep/payments-team)

[2] GitHub 检查 PR 修改的文件
    → 哪些文件落在哪个 CODEOWNERS pattern 上
    → src/payments/test.py → @caep/payments-team

[3] Branch protection rule "Require review from Code Owners" 开启
    → 合并按钮被 lock,直到满足:
        ✓ 一般 N 个 approve(假设 N=1)
        ✓ @caep/payments-team 中至少 1 人 approve
        ✓ PR author 自己的 approve 不算
        ✓ 旧的 stale approval 被 dismiss(dismiss_stale_reviews=true 时)

[4] Developer X 是 payments-team 成员:
    → 自己的 approve 不算,必须找 **别人** approve
    → 或者 developer X 不在 payments-team:
    → 必须找一个在 payments-team 的同事 approve

[5] X 可以请求 review:
    → 点 PR 右上 "Reviewers" → 选 @caep/payments-team
    → 会通知整个 team(每个 member 都看到 pending)

[6] 当所有条件满足:
    → "Merge pull request" 按钮变绿可点
```

### §11.7 完成态 Lex 的实际配置示例

**目标**:Lex 的 aibang knowledge repo main 分支,只有 `caep/security-team` 的成员 approve 才能 merge 到 main。

#### 11.7.1 创建安全 team(如果还没有)

```
Org Settings → People → Teams → New team
  Team name:    security-team
  Description:  Security review team for sensitive changes
  Visibility:   Visible  ← 必须!
```

#### 11.7.2 给这个 team 配 Write 权限 到 repo

```
Repo Settings → Collaborators and teams → Add teams
  输入 "security-team" → 角色: Write (或 Maintain,推荐)
```

#### 11.7.3 写 CODEOWNERS

提交到 `.github/CODEOWNERS`:

```gitignore
# 默认全文件 → security-team 才有审批权(可选更宽泛)
# 这个例子演示全 repo 受安全组保护
*                       @caep/security-team

# 例外:doc 文件开放给任何人审批
/docs/                  # (无 owner = 不需要 CODEOWNER approval)
/README.md              # (无 owner)
```

#### 11.7.4 设 Branch Protection

按 §11.4.1 步骤 + 勾选:

```
Branch name pattern: main
☑ Require a pull request before merging
    ☑ Require approvals: 1
    ☑ Require review from Code Owners
    ☑ Dismiss stale pull request approvals when new commits are pushed
    ☑ Require approval of the most recent reviewerable push
☑ Include administrators
```

#### 11.7.5 验收

```
场景 A — security-team 成员提 PR
  → 提了 PR,自己点 "Merge" 还是被 lock
  → 需要另一个 security-team 成员 approve
  → 找谁: 在 PR 页面右 "Reviewers" 边输入 @caep/security-team
  → 等任意 member approve 后,"Merge" 按钮激活

场景 B — 非 security-team 成员提 PR  
  → PR 自动 wait for code owner review
  → 必须在 security-team 里找 1 个 member approve
  → 在 PR 评论里会显示 "Review required from @caep/security-team"
  → member 收到 email / GitHub notification
```

### §11.8 常见踩坑(精选 5 个)

#### 11.8.1 "我设了 CODEOWNERS + branch protection,但 PR 还是能合并"

**根因**:branch protection rule 里**没勾选 "Require review from Code Owners"**。

**验证**:

```bash
gh api repos/OWNER/REPO/branches/main/protection | jq '.required_pull_request_reviews.require_code_owner_reviews'
# 期望: true
# 实际: false 或 null → 这就是问题
```

**修法**:去 Branch protection rule 勾上,或 API 加 `"require_code_owner_reviews": true`。

#### 11.8.2 "我的 team 显示为 owner,但 PR 说 'not a valid code owner'"

**根因**:team 没有 Write 权限到 repo(§11.5 那个陷阱)。

**验证**:

```bash
gh api repos/OWNER/REPO/collaborators/OWNER/TEAM_SLUG/permission
# 期望: admin / maintain / push / write (任一都包含 write)
# 实际: pull / triage / null → 权限不够
```

**修法**:到 Repo Settings → Collaborators and teams → 给这个 team 配 Write 或更高。

#### 11.8.3 "我的 team 是 secret 的,在 CODEOWNERS 里用不了"

**根因**:GitHub 官方说的:

> "When the code owner is a team, that team must be **visible**"

secret team 不能跨 org 公开,GitHub 不允许它做 CODEOWNERS owner。

**修法**:Org Settings → Teams → 改 team visibility 为 Visible(或者用 secret team 之外再创一个 visible team 来当 owner)。

#### 11.8.4 "我 push 的 CODEOWNERS 文件没生效"

**根因**:通常是 commit 的不是 main 分支(在 PR 状态),或者文件位置错了。

**验证**:`.github/CODEOWNERS` / `/CODEOWNERS` / `/docs/CODEOWNERS` 之一:
- 不支持其他路径(如 `/root/CODEOWNERS`、`/src/CODEOWNERS`)
- 支持多个位置(三个都会被读,优先级从大到小:.github/CODEOWNERS > repo 根 > docs/)

**修法**:移到正确路径,commit 到你要保护的分支(或 PR 合入)。

#### 11.8.5 "我已经 approve 了,但 PR 还是不让 merge"

**可能根因**:
1. **你是 PR author**:GitHub 禁止 self-approval,作者自己的 approve 不算
2. **dismiss_stale_reviews**:你 approve 之后有新的 commit,旧 approval 自动失效,必须重新 approve
3. **CODEOWNERS 改了**:你 review 的文件 pattern 变了,你不再 match,需要新的 CODEOWNER review
4. **minimum_approving_review_count 不止 1**:需要 2 个 approve,你只有 1 个

**验证**:

```bash
gh pr view PR_NUMBER --json reviewDecision,reviews,files
```

### §11.9 跟 §2.3 写过的 "Push to protected branches" 的关系

| 角色 | 是否能 push 到 protected branch | 是否能 approve 自己的 PR |
| --- | --- | --- |
| Read | ✗ | ❌ not applicable |
| Triage | ✗ | ❌ |
| **Write** | **✓(默认)** | ✗(no self-approval)|
| **Maintain** | ✓(在 branch protection "Allow specified actors to bypass" 里)| ✗ |
| **Admin** | ✗(**如果 branch protection "Include administrators" 开启**)| ✗ |

**洞察**:开启"Include administrators" + "Require review from Code Owners" 之后,**Admin 角色也受同样的限制**。也就是说 admin 既要当 CODEOWNER(被推为 owner 之一),又要被其他 CODEOWNER review。这是 GitHub 防止"管理员一手遮天"的设计。

### §11.10 进阶:Repo rulesets 才是 2024+ 推荐的写法

GitHub 2024 年开始推 **Repository rulesets**(取代 Branch protection),理由:

| 维度 | Branch protection rule | Repository ruleset |
| --- | --- | --- |
| 适用分支 | 逐个 branch 配 | 一组 branch 用 pattern 配 |
| 优先级 | 各自独立 | 可设 priority |
| 跨 repo 复用 | 不行 | 可以 |
| 状态:GA(正式)| Stable | **Stable(2025-09 推荐)|

**Ruleset 配置里也有相同选项**:"Require code owner review before merging" — 跟 §11.4.1 那张表选项名不同但功能一致。

**Lex 现在可以先用 Branch protection(简单),后期如果团队壮大再迁到 Ruleset**。迁移工具:`gh api -X POST repos/OWNER/REPO/rulesets` 创建新 ruleset,把旧的 branch protection rule 字段对应过去。

---

## §12 同目录后续文档推荐阅读

`linux/howgit/` 已经有 `How-to-get-commitid.md` / `README.md` / `config/` / `docs/` / `scripts/` 等。后续如需展开:

| 主题 | 候选文件名 |
| --- | --- |
| Branch Protection 单独深入(配合 §11 上下文) | `github-branch-protection.md` |
| CODEOWNERS 完整语法 + examples | `github-codeowners-syntax.md` |
| Repository Rulesets(2025+ 新)| `github-repository-rulesets.md` |
| GitHub Actions `permissions:` 字段 | `github-actions-permissions.md` |
| Org-Level Role 系统(Owner/Member/Security Manager 等)| `github-org-level-roles.md` |

## §13 引用文档来源

| 来源 | URL |
| --- | --- |
| GitHub 官方原档(能力表 § 0-9)| [docs.github.com/.../repository-roles-for-an-organization](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization) |
| GitHub 官方原档(CODEOWNERS § 11)| [docs.github.com/.../about-code-owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) |
| GitHub 官方原档(Branch Protection § 11)| [docs.github.com/.../about-protected-branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) |
| GitHub 官方原档(Repository Rulesets § 11.10)| [docs.github.com/.../managing-rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets) |
| GitHub API v3 `permission` 取值 | [docs.github.com/.../collaborators#add-a-repository-collaborator](https://docs.github.com/en/rest/collaborators/collaborators?apiVersion=2022-11-28#add-a-repository-collaborator) |
| GH Actions `permissions:` 字段 | [docs.github.com/.../workflow-syntax-for-github-actions#permissions](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#permissions) |
| GITHUB_TOKEN 权限范围 | [docs.github.com/.../automatic-token-authentication](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication) |
| Org vs Repo 角色体系 | [docs.github.com/.../roles-in-an-organization](https://docs.github.com/en/organizations/managing-peoples-access-to-your-organization-with-roles/roles-in-an-organization) |

