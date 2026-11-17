# how-to-using-git-apps · 装好 GitHub App 之后，我的仓库到底怎么用它

> **副标题**：App 装到 Org 了、也装成功了，那我的 Repository 还需要做什么？那个 Webhook 我能直接用吗？
>
> **一句话结论**
> **装完 ≠ 生效。** 安装只解决了「这个 App 能看到哪些仓库、能拿到哪些权限」。
> 你的仓库还要做 **3 件事**才能真正用上它：
> **① 确认仓库在授权范围内 → ② 让 App 真的跑出第一个 check → ③ 把这个 check 加进「必需状态检查 / Ruleset」，它才会拦住合并。**
> **第 ③ 步只有你能做，App 不会替你做。**

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-tldr) | TL;DR |
| [§1](#1-直接回答你的三个问题) | **直接回答你的三个问题** |
| [§2](#2-装完之后事件到底怎么流动) | 装完之后，事件到底怎么流动（机制图） |
| [§3](#3--一个实测发现cr-check-是个-private-app) | ★ **一个实测发现：cr-check 是个 private App** |
| [§4](#4-你的仓库要做的-4-件事) | **你的仓库要做的 4 件事**（含点击路径） |
| [§5](#5--怎么把-check-变成真正的门禁) | ★ **怎么把 check 变成真正的门禁**（两条路） |
| [§6](#6-审计这个-app-在你仓库里到底能干什么) | 审计这个 App 在你仓库里到底能干什么 |
| [§7](#7-装第三方-app-的安全审查清单) | 装第三方 App 的安全审查清单 |
| [§8](#8-常见误解对照表) | 常见误解对照表 |
| [§9](#9-端到端验证清单) | 端到端验证清单 |
| [§10](#10-官方文档--本仓库文档) | 官方文档 + 本仓库文档 |

---

## 0. TL;DR

1. **安装 ≠ 配置 ≠ 生效**，是三件事。安装只完成了第一件。
2. **Webhook 不是配在仓库上的，是配在 App 注册上的，全 App 只有一个 URL。**
   你装第三方 App → 事件送到**他们的服务器**，不是你的。你**改不了**这个 URL（除非你就是 App 拥有者）。
3. **Webhook secret 也不是你填的**——那是 App 拥有者填的，服务端用它验签 `X-Hub-Signature-256`。
   **你不需要这个 secret。**
4. **App 不用 webhook 来"代表你操作仓库"**。它收到事件后，用
   **`App ID + Private Key + installation_id`** 换 **installation access token**（1 小时有效），再回调 GitHub API。
   **webhook 里的 payload 自带 `installation.id`**，所以对方后端不需要你再告诉它什么。
5. **你的仓库唯一必须做的"硬"动作**：把 App 产生的 check 加进 **Required status checks / Ruleset**。
   不加 → App 照样跑、照样显示结果，但**拦不住任何东西**。
6. **前提**：要在下拉框里选中 `cr-check`，**App 必须最近在该仓库上报过这个 check**（官方明文要求）。
   所以顺序是：**先提一个 PR 让它跑一次 → 再去配门禁**。

---

## 1. 直接回答你的三个问题

### Q1. "我 Org 下面的 repository 就能工作了吗？"

**半对。** 分三层看：

| 层 | 装完 App 之后的状态 |
|---|---|
| **能看到你的仓库** | ✅ 自动。安装时勾选的仓库，App 的 installation token 就能访问 |
| **App 会对你的仓库做事** | ✅ 自动（如果订阅了对应事件且有权限）——不需要你在仓库里做任何配置 |
| **App 的结果会拦住你的合并** | ❌ **不会**。这需要**你**去仓库设置里把它加进「必需状态检查」或 Ruleset |

> **类比**：
> 安装 = 给 App 发了你的**门禁卡 + 访客证**
> 订阅事件 = 它**会被叫到**
> 配 required status check = 你**在门上装了锁**，它才有意义
>
> 少了第三步，它只是一个「会在 PR 上留言的旁观者」。

### Q2. "Webhook 指向他们自己的地址，我是不是直接用就行了？"

**可以直接用——但你要清楚"用"的是什么。**

- ✅ **你不需要在任何仓库里配置 webhook。** GitHub App 的 webhook 是 **App 级**的，
  一个 App **全局只有一个 webhook URL**，装到 100 个 Org 也还是发到同一个地址。
- ✅ **你装上之后，你 Org 里那些被勾选的仓库的事件，就会自动开始 POST 到那个地址。**
  不需要你再做任何"对接"动作。
- ⚠️ **但那个地址背后是别人的服务器**：
  - 你仓库的 PR 标题、正文、diff、文件内容（取决于授予的权限）**会离开你的 Org**；
  - 对方的服务会代表你的 Org 调 GitHub API（用 installation token）。
- ❌ **你改不了这个 URL**。Webhook URL 属于 **App 注册**，
  只有 **App 拥有者**（`Developer settings → GitHub Apps → Edit`）能改。
  **安装者改不了。**

### Q3. "我自己 Org 下面的 Repository 需要做些什么工作？"

按顺序做这 4 件（细节见 §4）：

| # | 做什么 | 在哪做 | 谁做 |
|---|---|---|---|
| 1 | 确认仓库在 installation 的授权范围内 | Install 时勾选 / `Configure → Repository access` | 你（Org owner）|
| 2 | 让 App 真的跑起来：提一个 PR，看 Checks 面板 | 仓库里提 PR | 你（开发者）|
| 3 | **把 check 加进「必需状态检查」/ Ruleset** | 仓库 Settings → Branches / Rulesets，或 Org 级 Rulesets | **你（唯一的关键动作）** |
| 4 | 按 App 的要求补配置（配置文件 / 站点设置页） | 看该 App 的文档 | 你 |

---

## 2. 装完之后，事件到底怎么流动

这是理解"它怎么利用这个 Git App"的核心。**注意：这条链路里没有"仓库配置"这一步。**

```
 ①  你的 Org 里某个仓库发生事件
     （PR opened / PR synchronize / push …）
     │
     ▼
 ②  GitHub 判断：这个仓库在 cr-check 的 installation 范围内吗？
     │  不在 → 什么都不发生
     │  在   ↓
 ③  GitHub 把事件 POST 到 cr-check 的 webhook URL
     │  Headers:
     │    X-GitHub-Event: pull_request
     │    X-GitHub-Delivery: <uuid>
     │    X-Hub-Signature-256: sha256=...   ← ★ 用 App 拥有者配的 secret 验签
     │  Body 里自带：
     │    installation.id  ← ★★ 对方后端由此知道"我代表哪个安装说话"
     │    repository.full_name
     │    pull_request.{number, head, base, ...}
     ▼
 ④  对方后端验签 → 用 App ID + Private Key + installation.id
     换 installation access token（有效期 1 小时）
     ▼
 ⑤  对方后端用该 token 调 GitHub API：
     POST /repos/{owner}/{repo}/check-runs
       { name: "cr-check", status: "in_progress" → "completed",
         conclusion: "success" | "failure" }
     ▼
 ⑥  你的 PR 页面出现 check run
     ┌────────────────────────────────────────────┐
     │  Checks                                   │
     │   ✅ cr-check — 2s                        │
     └────────────────────────────────────────────┘
     ▼
 ⑦  ★ 只有当你把 "cr-check" 加进「必需状态检查」或 Ruleset，
     GitHub 才会在这里拦住合并：
     "All checks were not successful" / 合并按钮变灰
```

**三个必须记住的点**：

1. **② 之外，仓库不做任何配置。** 仓库"参与"这件事完全由 installation 的授权范围决定。
2. **③ 的 payload 里自带 `installation.id`**，所以对方后端**不需要**你额外给它 installation id。
3. **⑦ 是你的活。** 前六步 App 全自动，第七步不做 = 不设防。

---

## 3. ★ 一个实测发现：cr-check 是个 private App

> 这一节是**实测结论**，直接决定你能不能改那个 webhook URL。

**实测（2026-11-09，匿名访问）**：

```bash
# ① cr-check 的公开页：看它是不是 private
curl -s https://github.com/apps/cr-check | grep -oE 'cr-check is a (private|public)'
# → cr-check is a private

# ② Marketplace 搜索：看它是不是公开上架的
curl -sL 'https://github.com/marketplace?query=cr-check&type=apps' \
  | grep -oE 'Search results for [^<]*|[0-9]+ results'
# → Search results for “cr-check”
# → 0 results
```

**GitHub 官方规则（原文）**：

> "If you set your GitHub App registration to private, it can only be installed on
> the account that owns the app."
> —— *Making a GitHub App public or private*

**推论（重要）**：

> **既然你成功把 cr-check 装进了你自己的 Org，那么你的 Org 就是这个 App 的拥有者**
> （或者你是那个拥有者 Org 的 owner / app manager）。
> **Private App 装不进别的账号。**

**这个推论直接改变你的处境**：

| 你以为的 | 实际情况（如果上面的推论成立） |
|---|---|
| "这是第三方团队的 App，webhook 是他们的地址，我只能用" | **这个 App 注册在你们自己 Org 名下**，那个 webhook URL 是**你们自己 Org 配置的** |
| "我改不了 webhook" | **你能改**——你们 Org 的 owner / app manager 可以进 `Developer settings → GitHub Apps → Edit` 直接编辑 |
| "我只能被动接受他们的服务" | 你可以把 webhook 指向**你自己的后端**，把 secret 换成你自己的 |

### 3.1 自查动作（30 秒）

**能编辑 = 你是拥有者，webhook 可改**：

```
头像 → Your organizations → <你的 Org> → Settings
   → 左侧栏 Developer settings
        → GitHub Apps
             → cr-check → Edit
                → 这里能看到并修改：Webhook URL / Webhook secret / 权限 / 事件订阅
```

**只读 = 你是安装者，webhook 不可改**：

```
头像 → Your organizations → <你的 Org> → Settings
   → 左侧栏 Third-party Access
        → GitHub Apps
             → cr-check → Configure
                → 只能看：Permissions / Repository access / Suspend / Uninstall
```

> **判据**：能看到 **Edit** 按钮 → 拥有者；只能看到 **Configure** → 安装者。
> 两者的差别就是"能不能改 webhook"。

### 3.2 如果你确实是拥有者（推荐路径）

这意味着你完全可以**自建**，不必依赖第三方团队：

```
Option A｜继续用他们的部署
  → 什么都不用改，先按 §4 走通"能跑 + 能拦"
  → 适合：想先验证效果

Option B｜改成自己的后端（★推荐）
  ① 把他们的后端换成你的服务：
     Developer settings → GitHub Apps → cr-check → Edit → Webhook URL
     改成 https://<你的域名>/github/webhook
  ② 换 secret：
     同一页 → Webhook secret → 改成你自己的随机串
     ⚠️ 换完 secret 后，他们的后端立刻收不到带正确签名的请求
        （旧 secret 失效）→ 所以必须**先**把你的服务切上去，**再**换 secret
  ③ 你的后端用 App ID + Private Key + installation_id 换 token 调 API
     （Private Key 在 Edit 页面可以重新生成）
  ④ 重新部署你的后端 → 提 PR 验证

  ⚠️ 注意：改 Webhook URL / secret 会影响**这个 App 的所有 installation**
     （你 Org 下的、以及任何其他人装的）。换之前想清楚。
```

> 本仓库的 [`git-apps/webhook-and-backend-service.md`](./git-apps/webhook-and-backend-service.md)
> 和 [`git-apps/cr-check/`](./git-apps/cr-check/) 里已经有一份**可运行的 Go 实现**，
> 可以直接接上你的后端，不用从零写。

---

## 4. 你的仓库要做的 4 件事

### Step 1 · 确认仓库在授权范围内

```
Org Settings → Third-party Access → GitHub Apps → cr-check → Configure
   → Repository access
       ○ All repositories
       ● Only select repositories  → Select repositories 里勾你的仓库
```

**要点**：

- `Only select repositories` 时，**别人手动新建的仓库不会被自动纳入**——新仓库要手工补勾。
- **确认你的目标仓库确实在清单里**。不在清单 = App 完全看不到它，什么都不会发生。
- 改这里**不会**改变 installation_id。

**命令行核对**：

```bash
# 列出该 Org 下所有 App 安装
gh api /orgs/<ORG>/installations \
  --jq '.[] | {id, app_slug, repository_selection, created_at}'

# 列出某个 installation 覆盖的仓库
gh api /orgs/<ORG>/installations/<INSTALLATION_ID>/repositories \
  --jq '.repositories[].full_name'
```

### Step 2 · 让 App 真的跑起来

**在任意一个已授权仓库里提一个 PR（或往已有 PR 推一个 commit）**，然后：

```
PR 页面 → Checks 面板（或底部状态区）
```

**三种可能结果**：

| 现象 | 含义 | 下一步 |
|---|---|---|
| 出现 `cr-check` 且跑起来了 | ✅ 链路通了 | 进 Step 3 |
| **完全没有 cr-check** | App 没订阅该事件 / 缺权限 / 仓库不在范围内 | 查 Step 1 + 查 §6 的事件订阅 |
| 出现了但一直 `pending` | 对方后端挂了/没部署/网络不通 | 这是**对方**的问题，不是你的 |

**命令行核对（拿到 check 名和 App ID，后面配门禁要用）**：

```bash
gh api repos/<ORG>/<REPO>/commits/<SHA>/check-runs \
  --jq '.check_runs[] | {name, app: .app.slug, app_id: .app.id, status, conclusion}'
```

> ★ **顺手记下 `name` 和 `app_id`**：
> `name` = 后面在「必需状态检查」里要选的**上下文名**；
> `app_id` = ruleset 里要填的 **`integration_id`**。

### Step 3 · 把 check 变成门禁 ← **★ 最关键的一步**

见 §5 详解。

### Step 4 · 按 App 的要求补配置

不同 App 的"额外配置"不一样，**查该 App 的文档/仓库 README**。常见形态：

| 形态 | 说明 |
|---|---|
| **仓库内配置文件** | 例如 `.github/cr-check.yml` / `.cr-check.yaml`——App 读仓库里的配置 |
| **App 自己的站点设置页** | App 给你一个网页，填规则、映射仓库→策略 |
| **Org 级设置** | 在 App 的站点里按 Org 配一次，对全 Org 生效 |
| **默认策略直接生效** | 什么都不用配，装完就按内置规则跑 |

> ⚠️ **配置文件放哪个仓库**很关键：
> 如果 App 读的是**被检查的那个仓库**里的配置文件 → 每个仓库都要放一份；
> 如果 App 读的是**一个中心配置仓库** → 只需要放一份，但要确认是哪个仓库。

---

## 5. ★ 怎么把 check 变成真正的门禁

有两条路，**可以只用一条，也可以两条叠加**。

### 5.1 路线 A · 仓库级 Branch protection（最快，5 分钟）

```
仓库 → Settings → Branches → Branch protection rules
   → Add rule（或 Edit existing rule）
      ├─ Branch name pattern: main（或 main, release/*）
      ├─ ☑ Require status checks to pass before merging
      │     └─ ☑ cr-check          ← ★ 从下拉框里选
      │        └─ "Status checks that are required" 右侧的
      │           ⓘ "Require branches to be up to date" 可选
      │     └─ ★ 选中 cr-check 后，下方会出现
      │        "Source: [ app 名称 ▾ ]"
      │        → 选 **cr-check**（不要选 "any source"）
      └─ Save changes
```

> ★★ **两个必须注意的点**：
>
> **① 下拉框里可能根本看不到 `cr-check`。**
> 官方原文：
> > "When you add a required status check, you can select an app that has **recently set this check**
> > as the expected source of status updates."
>
> 也就是说：**App 必须最近在这个仓库上报过这个 check，你才选得到它。**
> **所以 Step 2（先跑一次）必须排在 Step 3 前面。**
> 如果列表里没有 → 回 Step 2 提个 PR / 推个 commit 触发它。
>
> **② 一定要把 Source 选成 `cr-check`（而不是 "any source"）。**
> 官方原文：
> > "Any person or integration with write permissions to a repository can set the state of any status
> > check in the repository... If the status is set by any other person or integration,
> > **merging won't be allowed.**"
>
> 只选 "any source" 的话，任何有写权限的人都能自己伪造一个同名 check 把它"骗绿"。← **这是真实的安全漏洞，不是理论问题。**

**命令行核对当前门禁**：

```bash
gh api repos/<ORG>/<REPO>/branches/main/protection \
  --jq '.required_status_checks'
```

### 5.2 路线 B · Ruleset（组织级一次覆盖，★ 推荐）

**Branch protection 的局限**：每个仓库都要配一遍，仓库一多就漏。
**Ruleset** 可以在 **Org 级**一次覆盖全 Org（注意：**组织级 ruleset 需要 GitHub Enterprise 计划**，
Team 计划只有仓库级 ruleset）。

**UI 路径**：

```
Org Settings → Rulesets（Enterprise 才有组织级）
  → New ruleset → New repository ruleset
     ├─ Target: Branch / Tag
     ├─ Enforcement status: Active
     ├─ Rules → Add rule → Require status checks to pass
     │     └─ ☑ cr-check
     │        └─ Integration source: 选 cr-check
     └─ Save

仓库级：仓库 Settings → Rules → Rulesets → New ruleset
```

**API 方式（可进 GitOps，★ 本仓库推荐路径）**：

```bash
cat > /tmp/rs.json <<'EOF'
{
  "name": "cr-check-required",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "required_status_checks": [
          { "context": "cr-check", "integration_id": <STEP2 拿到的 app_id> }
        ],
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": true
      }
    }
  ]
}
EOF

gh api --method PUT repos/<ORG>/<REPO>/rulesets/cr-check-required \
  -H 'Accept: application/vnd.github+json' \
  --input /tmp/rs.json
```

> ⚠️ **`PUT` 是全量替换**：不带完整 ruleset 直接 PUT 会把其它规则清掉。
> 完整 Runbook 见 [`git-apps/16-ruleset-install-runbook.md`](./git-apps/16-ruleset-install-runbook.md)。
>
> ⚠️ **组织级 ruleset 的 `conditions` 必须同时含 `repository_name` 和 `ref_name`**，
> 端点是 `orgs/{org}/rulesets`（和仓库级 `repos/{owner}/{repo}/rulesets` 不是同一个）。
>
> ⚠️ **组织级 ruleset 只有 owner 能改**，`gh` token 需要 `admin:org` scope。

### 5.3 两条路怎么选

| | Branch protection | Ruleset（组织级）|
|---|---|---|
| 覆盖范围 | 单仓库 | **全 Org 一次覆盖** |
| 计划要求 | 免费 | **组织级需 Enterprise** |
| 分支粒度 | 每条规则一个 pattern | 同一套规则的 `ref_name` 模式 |
| 谁能改 | 仓库 admin | **只有 Org owner** |
| 适合 | 试点、单仓库 | **生产统一门禁** |

**本仓库的既有结论**：组织级 ruleset 做**基线兜底**（`~ALL` + `~DEFAULT_BRANCH`），
仓库级 ruleset 做**分支分层规范**（dev / release / main），两层叠加取最严。
详见 [`git-apps/14-rulesets-and-gitapp-gate.md`](./git-apps/14-rulesets-and-gitapp-gate.md)。

### 5.4 配完之后怎么确认真的拦住了

```bash
# ① 规则确实生效（enforcement 必须是 active）
gh api repos/<ORG>/<REPO>/rulesets --jq '.[] | {id, name, enforcement}'

# ② 聚合视图：这个分支实际命中了哪些规则
gh api repos/<ORG>/<REPO>/rules/branches/main --jq '.[] | {source, source_type, rules}'
```

**端到端联调（唯一可信的验证）**：

```
故意提一个不合规的 PR（例如 commit message 不带 CR 单号）
  → 期望：cr-check check = failure
  → 期望：合并按钮变灰 / 提示 "All checks were not successful"
  → 期望：改合规后 → check 转 success → 合并按钮恢复
```

> ⚠️ **不要只看"规则配上了"就宣布完成。**
> 本仓库已经踩过的坑见 [`git-apps/16-ruleset-install-runbook.md`](./git-apps/16-ruleset-install-runbook.md) §2.5
> 「**实测诊断**：装上了却什么都不拦（三个根因 + 两条只读检查）」。

---

## 6. 审计这个 App 在你仓库里到底能干什么

### 6.1 看授予的权限

```
Org Settings → Third-party Access → GitHub Apps → cr-check → Configure
   → Permissions  → Repository permissions / Organization permissions
```

**命令行**（需要 `admin:org`）：

```bash
gh api /orgs/<ORG>/installations --jq '.[] | {app_slug, id, permissions, events, repository_selection}'
```

或者从一次已经跑过的 check 反查（不需要 admin scope）：

```bash
gh api repos/<ORG>/<REPO>/commits/<SHA>/check-runs \
  --jq '.check_runs[0].app | {slug, id, permissions, events}'
```

### 6.2 权限即能力 —— 对照表

| 权限 | 它能干什么 | 风险 |
|---|---|---|
| `metadata: read` | 读仓库基本信息 | 低（几乎所有 App 都有）|
| `contents: read` | **读仓库所有文件内容（含私有仓库）** | ⚠️ **你的代码会离开你的 Org** |
| `contents: write` | **往你的仓库写/改代码** | 🔴 **等同于给了写权限** |
| `pull_requests: read` | 读 PR | 低 |
| `checks: write` | 在 PR 上创建/更新 check run | 中（能做门禁）|
| `statuses: write` | 设置 commit status | 中 |
| `administration: write` | **改分支保护 / Ruleset** | 🔴 **能自己给自己放行** |
| `issues: write` / `discussions: write` | 发评论 | 低 |
| `members: read`（组织权限）| 读组织成员 | 中 |
| `organization_administration` | **改组织设置** | 🔴 高 |

### 6.3 ★ 一定要自己审的三条红线

1. **`contents: write` 或 `administration: write`** — 有这个权限，App 背后的团队
   **可以直接往你的仓库写代码**，或者**自己改掉你刚配好的门禁**。
   → **不要授予**。如果对方坚持要，说明它的设计有问题。
2. **`contents: read` + 私有仓库** — 你的私有代码会**离开你的 Org**，
   存到对方（可能第三方、可能境外）的服务器上。
   → 确认这在你们的安全/合规政策里可接受；不可接受就只授权公开仓库。
3. **App 拥有 `administration: write`** — 它能**自己把 required status check 删掉**。
   → 这会让你的门禁形同虚设。

---

## 7. 装第三方 App 的安全审查清单

装之前 / 装之后过一遍：

```
□ 这个 App 是 public 还是 private？
    → private + 你能装 ⇒ 你的 Org 就是拥有者（§3）
□ 它申请的权限，逐条对照 §6.2 红线
    → 有 contents:write / administration:write 吗？
    → 有 contents:read 且仓库是私有的吗？
□ 它订阅了哪些事件？
    → 在 App 的 Edit 页看 "Active events"
    → 订阅越宽，暴露面越大
□ 它的 webhook URL 指向哪里？域名归属是谁？
    → 你们自己？还是第三方 / 境外？
□ 数据流向：你的 PR 内容/diff 会落到谁手里？留在哪里？多久？
□ 有没有隐私政策、服务条款、数据处理协议？
□ 它挂了 / 被入侵了会怎样？
    → 有 contents:write ⇒ 攻击者可以直接往你仓库推后门
□ 出问题怎么撤销？
    → Configure → Suspend（保留安装但断访问）
    → Configure → Uninstall（彻底移除）
    → 有 installation token 在外面 ⇒ Suspend 立即失效
□ 我们自己能不能接管（改 webhook URL / 自建后端）？
```

---

## 8. 常见误解对照表

| ❌ 误解 | ✅ 事实 |
|---|---|
| 装完 App，仓库就自动被保护了 | 装完只是"App 能看到仓库"。**门禁要你自己配**（§5）|
| 我要在仓库 Settings 里配 webhook | GitHub App 的 webhook 是 **App 级**的，一个 App 全局一个 URL，**不存在仓库级 webhook** |
| Webhook secret 我也得填一个 | 那是 **App 拥有者**填的，服务端用它验签。你用不上 |
| 我可以改这个 App 的 webhook URL | **只有 App 拥有者能改**。你是安装者就改不了 |
| App 会自动给我所有仓库都装上 | 只在 **installation 授权范围内**。`Only select` 时新仓库不会自动纳入 |
| 下拉框里选不到 `cr-check` | App **还没在这个仓库跑过 check**。先提个 PR 触发它（§5.1 ①）|
| 我选了 "any source" 应该也一样 | ⚠️ **不一样**。任何有写权限的人都能伪造同名 check 骗绿（§5.1 ②）|
| 私有 App 装不进我的 Org | 除非**你的 Org 就是拥有者**——那就说明它其实是"你们的 App"（§3）|
| 配好规则就万事大吉 | 要**端到端联调**证明它真拦得住（§5.4）|
| App 挂了不影响我 | 若它被设为必需检查，它挂了 = **你的合并全被卡住**。准备好降级预案 |

---

## 9. 端到端验证清单

```
【安装层】
□ Org Settings → Third-party Access → GitHub Apps → 能看到 cr-check
□ Configure → Permissions：逐条核对（对照 §6.2 红线）
□ Configure → Repository access：目标仓库在清单里
□ 记住 Installation ID（Configure 页面）

【运行层】
□ 提一个 PR → Checks 面板出现 cr-check
□ gh api repos/<ORG>/<REPO>/commits/<SHA>/check-runs
    → 记下 name（= check context 名）和 app_id（= integration_id）
□ 确认它订阅了 pull_request / pull_request_review 等需要的事件

【门禁层】
□ 仓库 Settings → Branches → Rule 里加了 cr-check
□ Source 选的是 cr-check，不是 "any source"
□ 或：Ruleset 里 required_status_checks 加了 cr-check + integration_id
□ gh api repos/<ORG>/<REPO>/rulesets --jq '.[] | {name, enforcement}'
    → enforcement == "active"

【联调层】★ 唯一可信的验证
□ 提一个不合规 PR → cr-check = failure → 合并按钮变灰
□ 改成合规 → cr-check = success → 合并按钮恢复
□ 验证绕过路径：让一个只有写权限的人伪造同名 check → 仍然被拦

【兜底层】
□ 知道出事时怎么做：Configure → Suspend
□ 知道怎么查：App 的日志 / 你自己的部署日志
```

---

## 10. 官方文档 + 本仓库文档

### 官方文档

| 主题 | 链接 |
|---|---|
| 安装自己开发的 App（UI 逐步） | https://docs.github.com/en/apps/using-github-apps/installing-your-own-github-app |
| 安装第三方 App | https://docs.github.com/en/apps/using-github-apps/installing-a-github-app-from-a-third-party |
| 管理/修改已安装的 App | https://docs.github.com/en/apps/using-github-apps/reviewing-and-modifying-installed-github-apps |
| **App 可见性（public/private）** | https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/making-a-github-app-public-or-private |
| **Webhook 与 webhook secret（App 级）** | https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/using-webhooks-with-github-apps |
| **以 installation 身份认证（换 token）** | https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation |
| **保护分支 / 必需状态检查** | https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches |
| REST API · Apps | https://docs.github.com/en/rest/apps/apps |
| REST API · Installations | https://docs.github.com/en/rest/apps/installations |
| REST API · Check runs | https://docs.github.com/en/rest/checks/runs |
| REST API · Rulesets | https://docs.github.com/en/rest/repos/rules |

### 本仓库文档

| 文档 | 用途 |
|---|---|
| [`install-git-apps.md`](./install-git-apps.md) | **装在哪：Org 级 vs 仓库级 vs 分支的五条 UI 路径** |
| [`07-repository-githubapp.md`](./07-repository-githubapp.md) | GitHub App 凭据在 Argo CD 哪里配、目标分支在哪 |
| [`git-apps/11-github-app-concepts.md`](./git-apps/11-github-app-concepts.md) | App / Installation / Webhook 概念与源码对应 |
| [`git-apps/12-webhook-push-vs-pull.md`](./git-apps/12-webhook-push-vs-pull.md) | 事件类型与投递语义 |
| [`git-apps/13-cr-check-go-design.md`](./git-apps/13-cr-check-go-design.md) | CR Check 后端设计：拿到事件后怎么判 |
| [`git-apps/14-rulesets-and-gitapp-gate.md`](./git-apps/14-rulesets-and-gitapp-gate.md) | **★ Ruleset + App 组成合并门禁（本文 §5 的完整版）** |
| [`git-apps/16-ruleset-install-runbook.md`](./git-apps/16-ruleset-install-runbook.md) | **★ ruleset 装上去的 Runbook + 六个根因排查** |
| [`git-apps/webhook-and-backend-service.md`](./git-apps/webhook-and-backend-service.md) | 安装 → Webhook → 后端的完整链路（§2 的展开） |
| [`git-apps/cr-check/`](./git-apps/cr-check/) | **★ 可运行的 Go 实现**（30 秒起服务，接自己的后端） |
