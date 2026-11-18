# CODEOWNERS 完全指南：文件放哪、语法、门禁组合

> **一句话结论**：文件放 **`.github/CODEOWNERS`**（GitHub 优先级最高的合法位置）；
> CODEOWNERS 本身**只负责"标注谁负责哪片路径"**，
> 真正的强制力来自 branch protection / ruleset 里的 **require code owner review**。
> 两个东西不配套，CODEOWNERS 就只是一份没牙的文档。

本文基于 GitHub 官方文档（About code owners / Available rules for rulesets / REST API）
核对整理，并对照 GitLab 的 CODEOWNERS 差异，最后给出本知识库（`aibangjuxin/knowledge`）的落地建议。

---

## 1. TL;DR 决策表

| 问题 | 答案 |
|---|---|
| 文件放哪 | `.github/CODEOWNERS`（GitHub）；GitLab 则是仓库根目录优先 |
| 能放几个位置 | 三个合法位置，但**只生效其中一个**（按优先级取第一个命中的），**不是叠加** |
| 优先级顺序（GitHub） | `.github/` > 仓库根目录 > `docs/` |
| 优先级顺序（GitLab） | 仓库根目录 > `docs/` > `.gitlab/` |
| CODEOWNERS 本身能拦住人吗 | **不能**。它只在 PR 打开时自动 @ owner；不配保护分支/规则集就等于没生效 |
| 谁批准算数 | 同一行多个 owner，**任意一个**批准即满足门禁（不是要全部批准） |
| 作者能自己批自己吗 | **不能**。GitHub 不允许 approve 自己的 PR → 单人仓库开这个门禁 = 死锁（见 §9） |
| owner 必须有权限吗 | 必须有 **write** 权限；否则该 owner 被静默忽略 |

---

## 2. 文件放哪个目录

### 2.1 GitHub 的三个合法位置与优先级

官方原文（GitHub Docs · About code owners）：

> To use a CODEOWNERS file, create a new file called `CODEOWNERS` in the `.github/`, root, or
> `docs/` directory of the repository, in the branch where you'd like to add the code owners.
> **If CODEOWNERS files exist in more than one of those locations, GitHub will search for them in
> that order and use the first one it finds.**

| 位置 | 优先级 | 文件名 | 什么时候选它 |
|---|---|---|---|
| `.github/CODEOWNERS` | **1（最高）** | `CODEOWNERS`（无扩展名） | **默认选它**。GitHub 专用配置目录，与 workflows / ISSUE_TEMPLATE / PULL_REQUEST_TEMPLATE 同居 |
| `CODEOWNERS`（根目录） | 2 | `CODEOWNERS` | 仓库根目录已经当"配置文件堆放区"；或 `.github/` 被别的工具占用 |
| `docs/CODEOWNERS` | 3（最低） | `CODEOWNERS` | 仓库根目录已有另一份（这份永远不会生效）；或团队约定统一放 docs |

> ⚠️ **最高频踩坑**：照着老文章把文件放在 `docs/CODEOWNERS`，但根目录早就有一份
> → GitHub 永远只读根目录那份 → "我改了 CODEOWNERS 为什么没反应"。
> **先 `ls` 确认仓库里没有第二份 CODEOWNERS。**

### 2.2 为什么推荐 `.github/CODEOWNERS`

1. **官方明确点名它是"最安全"的位置**。GitHub 文档在讲怎么防止"改门禁的门禁"时写：
   > The most secure method is to define a CODEOWNERS file in the `.github` directory of the
   > repository and define the repository owner as the owner of either the CODEOWNERS file
   > (`/.github/CODEOWNERS @owner_username`) or the whole directory (`/.github/ @owner_username`).

   原因很实在：`.github/` 本身被 owner 保护后，**没人能悄悄改掉 CODEOWNERS 再提 PR**。
   放根目录时，你还得单独写一条 `CODEOWNERS @owner` 来保护根目录那个文件；
   放 `docs/` 时要保护 `docs/`，而 `docs/` 往往还塞着别的东西。

2. **语义分组**：`.github/` 已经是"GitHub 平台相关配置"的约定目录，CODEOWNERS 放进去
   一眼就知道是 GitHub 的东西；放根目录会污染 monorepo 的根（根目录通常留给 README / LICENSE）。

3. **避免和文档站打架**：`docs/` 常被 mkdocs / Hugo / Docusaurus 当作**站点内容目录**。
   丢一个 `CODEOWNERS` 进去，轻则被 strict build 报 "file not in nav"，重则把配置文件一起发布出去。
   本仓库的 `docs/` 正是 GitHub Pages 的**发布产物目录**（`docs/index.html` 等），
   更不可能往里塞 CODEOWNERS。

4. **优先级最高 = 确定性最高**：`.github/` 排第一，就算将来有人在根目录丢了一份，行为也可预期。

### 2.3 各平台对照（同一份内容要迁的话）

| 平台 | 合法位置 | 优先级 | 备注 |
|---|---|---|---|
| **GitHub** | `.github/`、根、`docs/` | `.github/` > 根 > `docs/` | 只用第一个命中的；语法是 gitignore 风格 glob |
| **GitLab** | 根、`docs/`、`.gitlab/` | 根 > `docs/` > `.gitlab/` | 顺序与 GitHub **不同**；Code Owners 是 Premium/Ultimate 功能 |
| **Gitea** | 根、`docs/`、`.gitea/` | 根 > `docs/` > `.gitea/` | **语法完全不同**：用 Go 正则（`frontend/src/.*\.js @org/team`），不是 glob；且**支持** `!` 取反 |
| **Gerrit** | `OWNERS` / `MAINTAINERS`（根） | — | 文件名就不是 CODEOWNERS，语法也完全不同（per-file 形式） |
| **Bitbucket Cloud** | 根目录 `CODEOWNERS` | — | 需要在仓库设置里开启 code owners；套餐限制以官方为准 |

> 结论：**GitHub 上放 `.github/CODEOWNERS`；要同时兼容 GitLab，只能放仓库根目录**。
> 两者只能二选一时，看你在哪个平台上花的时间多。
>
> ⚠️ 语法层面同样不可移植：GitHub/GitLab 用 gitignore 风格 glob，
> Gitea 用 **Go 正则**（`!` 可用、`*` 不跨 `/` 的语义也不同）。
> 一份文件想跨平台通用，只能写在"根目录"这个**两边都合法**的位置，
> 并接受"glob / 正则"二选一的风险。

### 2.4 分支差异：每个分支一份

> Each CODEOWNERS file assigns the code owners for a single branch in the repository.

也就是说 `main` 和 `gh-pages` 可以各自有一份 CODEOWNERS，互不影响。
对做 GitHub Pages 的仓库很常见：主分支的代码归开发组，站点分支归文档组。

---

## 3. 生效规则（比"放哪里"更容易翻车的地方）

| # | 规则 | 后果 / 注意 |
|---|---|---|
| 1 | **只看 PR，直推不受管** | 绕过 PR 直接 push 到分支，CODEOWNERS 一点作用没有 → 必须同时禁直推 |
| 2 | **用 base 分支的 CODEOWNERS** | PR 里改 CODEOWNERS，**当次 PR 不生效**（读到的是 base 分支那份），要合并后才对后续 PR 生效 |
| 3 | **fork PR 用上游 base 分支那份** | 你在自己 fork 里改 CODEOWNERS 对上游 PR 无效 |
| 4 | **owner 必须有 write 权限** | 写了不存在的用户 / 没权限的团队 → **静默不分配 owner**（不报错，最容易误判成"语法没生效"） |
| 5 | **团队必须可见且有 write 权限** | 成员个人都有权限不算，团队本身必须被授予 write |
| 6 | **Draft PR 不自动请求评审** | 转成 ready for review 时才通知 owner |
| 7 | **文件 < 3 MB** | 超限直接不加载（静默失效） |
| 8 | **路径大小写敏感** | GitHub 用大小写敏感文件系统；**你在 macOS 上写 `Docs/` 不会匹配 `docs/`** |
| 9 | **一行语法错误 → 整行跳过** | 其他行照常生效，所以"局部不生效"很常见；用 API 查错（见 §7） |
| 10 | **只对改动的文件生效** | 没被 PR 触碰的文件，owner 不会被请求 |

---

## 4. 语法速查

### 4.1 基本形态

```
# 注释：整行注释和行内注释都支持
<pattern>  <owner1> <owner2> ...
```

- owner 写法：`@username`、`@org/team-name`、`user@example.com`（企业托管账号 EMU 不能用邮箱）
- 同一行的多个 owner：**任意一个批准即可**满足"需要 code owner 审批"的门禁
- owner **不在同一行**就等于**只认最后一个**（`pattern` 会被后一行覆盖）

### 4.2 pattern 规则（基本同 .gitignore）

| 写法 | 含义 |
|---|---|
| `*` | 匹配任意字符，但**不跨 `/`** |
| `**` | 跨任意层级（`**/logs` 匹配 `build/logs`、`scripts/logs`、`deeply/nested/logs`） |
| `/build/logs/` | 锚定**仓库根**下的 `build/logs` 目录及其所有子目录 |
| `apps/` | 任意层级名为 `apps` 的目录及其子目录 |
| `/apps/` | 仅仓库根下的 `apps` 目录及其子目录 |
| `docs/*` | 只匹配 `docs/` 的**直接**子文件，不匹配 `docs/a/b.md`（要 `docs/**`） |
| `*.go` | 任意层级的 `.go` 文件 |

**顺序**：**最后一个匹配的 pattern 生效**（后写的覆盖先写的）。

### 4.3 不支持 / 反直觉的写法（官方 Warning）

> There are some syntax rules for gitignore files that **do not work** in CODEOWNERS files:
> - Escaping a pattern starting with `#` using `\` so it is treated as a pattern and not a comment doesn't work
> - **Using `!` to negate a pattern doesn't work**
> - **Using `[ ]` to define a character range doesn't work**

**没有 `!` 取反** → 想"排除某个子目录"要用**空 owner**：

```
/apps/          @octocat
/apps/github              # ← 空 owner：该子目录不由 code owner 管，等于取消继承
```

```
/apps/          @octocat
/apps/github    @doctocat   # ← 或者直接给它换个 owner
```

其他注意：

- 大小写敏感（macOS 用户踩坑重灾区）
- `#` 开头的转义 `\#` 无效 → 没法匹配以 `#` 开头的文件名（实践中无解，忽略）
- 历史版本支持过 `@@org/team-name` 写法，当前官方文档已不再列出；用标准 `@org/team-name`
- team 名含特殊字符（如 `:`）时，老版本文档要求 HTML 实体编码（`@org/team-%3Aname`）；
  当前文档未再列出该条 → 建议 team 名只用小写字母 / 数字 / `-`

### 4.4 官方示例（含注释，值得整段抄走）

```text
# This is a comment.
# Each line is a file pattern followed by one or more owners.

# 默认 owner：任何 PR 都会请求这两人
*       @global-owner1 @global-owner2

# 顺序重要：最后一个匹配优先。只改 JS 文件时只请求 @js-owner
*.js    @js-owner #This is an inline comment.

# 也可用邮箱
*.go docs@example.com

# 团队必须是 @org/team-name，且团队本身要有 write 权限
*.txt @octo-org/octocats

# 仓库根的 build/logs 目录及其子目录
/build/logs/ @doctocat

# 只匹配 docs/ 的直接子文件，不含 docs/build-app/troubleshooting.md
docs/* docs@example.com

# 任意层级的 apps 目录
apps/ @octocat

# 仅根目录下的 /docs 及其子目录
/docs/ @doctocat

# 目录及其子目录，任一人批准即可
/scripts/ @doctocat @octocat

# 任意层级的 logs 目录
**/logs @octocat

# 排除子目录：空 owner
/apps/ @octocat
/apps/github

# 或者给子目录换个 owner
/apps/ @octocat
/apps/github @doctocat
```

---

## 5. 最佳实践清单

1. **放 `.github/CODEOWNERS`**，并且**保证仓库里只有这一份**。
2. **兜底一行 `* @owner`**，保证任何文件都有默认责任人（否则"没匹配到的文件"谁都能改）。
3. **兜底 owner 不要写成 10 个人**：门禁是"任一批准即通过"，写一堆人等于没人管。
   宁可用 **2–3 人的小团队**（`@org/team-x`），也不要 `@org/team-with-40-people`。
4. **自我保护**（防"改门禁的门禁"）：
   ```text
   /.github/            @owner
   /.github/CODEOWNERS  @owner
   ```
   再配合 ruleset 的 `require_code_owner_review`，改 CODEOWNERS 本身就需要 owner 批准。
5. **按目录分层，而不是按文件枚举**：`/gcp/`、`/linux/`、`/scripts/` 这种粒度最好；
   枚举几百个文件既难维护，又容易漏。
6. **owner 写"团队"而不是"某个人"**：人会离职、会休假，团队是组织资产。
   （例外：个人仓库只能写自己。）
7. **CODEOWNERS 的变更本身要走 PR**，并让 CODEOWNERS 的 owner 审批它。
8. **配合禁直推**：光有 CODEOWNERS 而允许直推，等于没设门禁。
9. **大小写写对**：写之前对一下真实路径（`git ls-files`），别在 macOS 上凭感觉写 `Docs/`。
10. **定期用错误检查 API 验证**：语法错误是"静默跳过单行"，不主动查根本发现不了。
11. **在 monorepo 里给"公共基础设施"单独一个 owner**（CI 配置、IaC、发布脚本），
    这类路径是事故高发区。
12. **别把它当成唯一防线**：CODEOWNERS 只管"谁来审"，不管"审得对不对"。
    CI（lint / policy-as-code / 测试）才是质量底线，两者互补。

---

## 6. 与分支保护 / 规则集组合（CODEOWNERS 的"牙齿"）

CODEOWNERS 单独存在 = 自动 @ 人；配上保护规则才是门禁。

### 6.1 两条路子

| 方案 | 配置位置 | 优点 |
|---|---|---|
| **Branch protection** | Settings → Branches → Add rule → Require pull request review → 勾 **Require review from Code Owners** | 直观，老仓库已经在用 |
| **Ruleset**（推荐） | Settings → Rules → Rulesets → New ruleset | 可多条并存、不需要 admin 才能查看、状态检查更完整、可按路径细分 |

GitHub 官方也提到 ruleset 的优势：
> Rulesets have a few advantages over branch protection rules, such as statuses, and better
> discoverability without requiring admin access. You can also apply multiple rulesets at the same time.

### 6.2 API 里的准确写法（容易搞错）

在 ruleset 的 JSON 里，**不是一个独立的 rule type**，而是 `pull_request` 规则的一个参数：

```json
{
  "type": "pull_request",
  "parameters": {
    "required_approving_review_count": 1,
    "require_code_owner_review": true,
    "dismiss_stale_reviews_on_push": true,
    "require_last_push_approval": true,
    "allowed_merge_methods": ["squash", "merge"]
  }
}
```

> 注意：本仓库 `gcp/ucp/argocd-topics/git-apps/14-rulesets-and-gitapp-gate.md` 里把
> `require_code_owner_review` 列成了独立 rule type；按 REST API schema，
> 它是 `pull_request` 规则的 **参数**，写脚本时别当成 rule type 传。

CLI 查看现有规则集：

```bash
gh api repos/:owner/:repo/rulesets --jq '.[] | {id, name, enforcement, target}'
gh api repos/:owner/:repo/rulesets/<id> --jq '.rules'
```

### 6.3 门禁语义

- 需要 code owner 审批时：**多个 owner 中任意一个批准即满足**。
- `require_last_push_approval`：最后那次 push 必须由**非 push 者本人**批准 → 堵"自己推了自己批"。
- `dismiss_stale_reviews_on_push`：新 commit 会作废旧批准 → 堵"批完再偷偷改"。
- **PR 作者不能批准自己的 PR**：这是单人仓库的死锁点，见 §9。

---

## 7. 实操：怎么验证生效

### 7.1 查语法错误（最有用的一个 API）

```bash
gh api repos/:owner/:repo/codeowners/errors
```

```json
{ "errors": [] }
```

出错时会列出具体的行与原因。REST 路径：
`GET /repos/{owner}/{repo}/codeowners/errors`（需要 `Contents: read`）。
网页版在仓库里直接打开 CODEOWNERS 文件，非法行会**高亮标红**。

### 7.2 三种确认方式

1. **开一个 PR 改任意文件** → 右侧 Reviewers 里应自动出现 owner。
   ```bash
   gh pr view <PR> --json reviewRequests
   ```
2. **浏览器 hover 文件名旁的盾牌图标** → tooltip 显示 `Owned by @user (from CODEOWNERS line N)`，
   同时告诉你命中的是**第几行**（排查 pattern 时非常好用）。
3. **查 ruleset 是否真的挂了 code owner 要求**：
   ```bash
   gh api repos/:owner/:repo/rulesets --jq '.[] | select(.rules[]?.type=="pull_request") | .rules'
   ```
   看 `require_code_owner_review` 是否为 `true`。

### 7.3 常见"看起来没生效"的原因对照

| 现象 | 大概率原因 |
|---|---|
| PR 里完全没人被请求 | 文件不在 base 分支的 CODEOWNERS 覆盖范围 / owner 没 write 权限 / 改的是文档站目录 |
| 只请求了一个人而不是两个 | 同一 pattern 写了两行 → 只认最后一行 |
| 改了 CODEOWNERS 当次不生效 | 正常，要合并后才对后续 PR 生效 |
| fork PR 不请求 | 用的是上游 base 分支的 CODEOWNERS；或 owner 在你 fork 里没 write 权限 |
| 某人改了文件却没被拦 | 该路径没有 owner（漏配）或写了空 owner；或该 PR 走了直推 |
| 路径写了但没匹配 | 大小写不对 / 用了 `docs/*` 却期望匹配深层 / 用了 `[a-z]` / 用了 `!` |

---

## 8. 可直接抄的模板

### 8.1 团队仓库（推荐基线）

```text
# .github/CODEOWNERS
# 规则：
#   - 一行 = <path pattern> <owner...>
#   - 最后一条匹配的行生效
#   - 同一行多个 owner，任意一人批准即可
#   - 路径大小写敏感

# ---- 兜底：默认责任人 ----
*                                    @example-org/platform-team

# ---- 目录级 owner ----
/apps/                               @example-org/app-team
/services/api/                       @example-org/api-team @example-org/security-team
/libs/shared/                        @example-org/platform-team

# ---- 基础设施：事故高发区，必须人工过 ----
/.github/                            @example-org/platform-team
/.github/CODEOWNERS                  @example-org/platform-team
/.github/workflows/                  @example-org/platform-team
/deploy/                             @example-org/sre-team
/infra/                              @example-org/sre-team
/scripts/                            @example-org/platform-team

# ---- 文档 ----
/docs/                               @example-org/docs-team
/README.md                           @example-org/docs-team
```

### 8.2 配套的 ruleset 骨架

```json
{
  "name": "code-owner-gate",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"] } },
  "rules": [
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "require_code_owner_review": true,
        "dismiss_stale_reviews_on_push": true,
        "require_last_push_approval": true,
        "allowed_merge_methods": ["squash", "merge"]
      }
    }
  ],
  "bypass_actors": []
}
```

### 8.3 单人 / 小型仓库

```text
# .github/CODEOWNERS
*   @your-handle
```

但**不要**同时打开 `require_code_owner_review`（见 §9）。此时 CODEOWNERS 的作用是：

- 自动把 owner 填进 Reviewers（自己审自己的 PR，虽然是同一个人，但流程上多一步确认）
- 给未来的协作者一个默认落点
- 文件页 hover 显示归属，属于"软文档"

---

## 9. 单人仓库的死锁陷阱（务必先读）

GitHub 规定：**PR 作者不能批准自己的 PR**。因此在一个只有你自己的仓库里：

```
CODEOWNERS:  *  @you
ruleset:     require_code_owner_review = true
```

⇒ 你的每一个 PR 都需要"@you 批准" ⇒ @you 就是作者 ⇒ **无法批准** ⇒ **永远无法合并**。

可选出路：

| 方案 | 说明 |
|---|---|
| **不开 code owner 门禁** | 推荐给单人仓库。CODEOWNERS 只做标注；真正的护栏用"禁直推 + 必需 CI 检查" |
| ruleset 排除规则 | 规则集里给该分支/路径加例外，或对某些规则不启用 code owner 要求 |
| `bypass_actors` | 给某个角色（如 repo owner）配置绕过权限，但等于门禁对 owner 失效 |
| 引入第二个人 | 有第二个有 write 权限的人（哪怕是另一个账号/机器人）才能真正用起来 |

> 同理：**机器人账号（GitHub App / bot）提的 PR** 需要真人 code owner 批准；
> 如果唯一 owner 也是那个 bot，就是死锁。

---

## 10. 对本知识库（`aibangjuxin/knowledge`）的建议

现状：

- 仓库所有者只有 1 个（`Lex`），历史提交也全部来自这一个人。
- 已有 `.github/workflows/cr-prefix.yml`（PR 标题 / commit 必须含 `CH<数字>` 前缀）。
- 已有 ruleset `dev-branch-guard`，对 `feature/**`、`git-apps/**`、`fix/**`、`codex/**` 要求 `cr-prefix` 检查通过。
- `docs/` 是 GitHub Pages 的**发布产物目录**，不能放 CODEOWNERS。

结论与建议：

1. **可以放，但价值有限**。单人仓库开 `require_code_owner_review` 必然死锁（§9）；
   所以本仓库的 CODEOWNERS 定位是**"责任标注 + 给 AI/脚本改文件留痕"**，不是门禁。
2. **如果放，就放 `.github/CODEOWNERS`**，且只放一份：
   ```text
   # .github/CODEOWNERS
   # 单人仓库：只做责任标注，不开启 require_code_owner_review
   *                 @aibangjuxin

   # 改动风险最高的几处，单独点名（未来有人接手时立刻生效）
   /.github/         @aibangjuxin
   /.github/workflows/  @aibangjuxin
   /scripts/         @aibangjuxin
   /push.sh          @aibangjuxin
   /push-llama.sh    @aibangjuxin
   /AGENTS.md        @aibangjuxin
   ```
3. **真正的护栏继续走 CI + ruleset**：现有 `cr-prefix` 已经挡住了"提交信息不合规"。
   若要再加一道，可加 required status check（测试 / 脱敏扫描 `scripts/sanitize-check.sh`），
   这比 CODEOWNERS 在单人仓库有效得多。
4. **一旦引入第二个协作者**，再回来把 `require_code_owner_review` 打开，并把 owner 从
   个人改成 `@<org>/<team>`。

---

## 11. 速查表（打印版）

| 想要的效果 | 写法 |
|---|---|
| 兜底所有文件 | `* @owner` |
| 仓库根某目录及其子目录 | `/dir/ @owner` |
| 任意层级的同名目录 | `dir/ @owner` |
| 深层路径 | `docs/** @owner` 或 `**/logs @owner` |
| 某扩展名 | `*.go @owner` |
| 多个人任一即可 | `*.go @a @b` |
| 排除某子目录（取消继承） | `/apps/ @owner` ＋ `/apps/github`（空 owner） |
| 换子目录 owner | `/apps/ @owner` ＋ `/apps/github @other` |
| 保护 CODEOWNERS 自身 | `/.github/CODEOWNERS @owner`（或 `/.github/ @owner`） |
| 注释 | `# 整行` 或行尾 ` # 说明` |
| 查语法错误 | `gh api repos/:owner/:repo/codeowners/errors` |
| 看命中了哪一行 | 仓库页面 hover 文件名旁的盾牌图标 |

---

## 参考

- GitHub Docs — About code owners：
  <https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners>
- GitHub Docs — Available rules for rulesets：
  <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets>
- GitHub Docs — REST API · List CODEOWNERS errors：
  <https://docs.github.com/en/rest/repos/repos#list-codeowners-errors>
- GitLab Docs — Code Owners（含 GitLab 的位置优先级）：
  <https://docs.gitlab.com/user/project/codeowners/>
- Gitea Docs — Code Owners（含 Gitea 的位置优先级与 Go 正则语法）：
  <https://docs.gitea.com/usage/code-owners>
- 本仓库相关文档：
  - `linux/howgit/github-repo-role-permissions.md` —— 仓库角色（R/T/W/M/A）权限体系
  - `linux/howgit/why-to-using-githubapps.md` —— App / OAuth / PAT / Webhook 身份体系
  - `linux/howgit/gh-user-guide.md` —— gh CLI 实战（本文的 `gh api` 用法基础）
  - `gcp/ucp/argocd-topics/git-apps/14-rulesets-and-gitapp-gate.md` —— ruleset 与门禁整体设计
    （注意其中 `require_code_owner_review` 的 rule type 说法与 REST API schema 不一致，见 §6.2）
