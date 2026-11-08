# 06 Ruleset × `cr-prefix` Action 联合工作详解

> **对象**：
> - 门禁策略：[`06-repo-feature-conventions.json`](./06-repo-feature-conventions.json)（ruleset 名 `dev-branch-guard`）
> - 校验器：`/Users/lex/git/knowledge/.github/workflows/cr-prefix.yml`（仓库内路径：`.github/workflows/cr-prefix.yml`）
> - 实测仓库：`aibangjuxin/knowledge`（本文所有"线上实测"结论均来自 `gh api` 直查，2026-11-08）
>
> **一句话结论**
> 这两个文件是**一套门禁的两半**：
> **06 是"锁"（声明"哪些分支必须通过哪些检查才能合入"），`cr-prefix.yml` 是"钥匙"（真正跑起来、生产出那个 check 结论）**。
> 只有锁没有钥匙 → 门禁永远卡死；只有钥匙没有锁 → 检查只是"建议"，谁都能绕过。
> **两者靠一个字符串咬合：`cr-prefix`（ruleset 里的 `context` == workflow 里 job 的 `name`）。**

---

## 目录

| 章节 | 内容 |
|---|---|
| [§1](#1-分工两个文件各干什么) | 分工：两个文件各干什么 |
| [§2](#2-逐段拆解-06-repo-feature-conventionsjson) | 逐段拆解 `06-repo-feature-conventions.json` |
| [§3](#3-逐段拆解-cr-prefixyml) | 逐段拆解 `cr-prefix.yml` |
| [§4](#4-两者怎么咬合context--job-name) | 两者怎么咬合：`context` == job `name` |
| [§5](#5-完整生命周期一次-pr-从开到合) | 完整生命周期：一次 PR 从开到合 |
| [§6](#6-线上实测状态aibangjuxinknowledge) | 线上实测状态 |
| [§7](#7-★-关键语义澄清ref_name-管的是-pr-的-目标分支) | ★ 关键语义澄清：`ref_name` 管的是 PR 的**目标**分支 |
| [§8](#8-★-五个已确认的缺口) | ★ 五个已确认的缺口 |
| [§9](#9-应用场景) | 应用场景 |
| [§10](#10-与三层判定模型l1--l2--l3的关系) | 与三层判定模型（L1/L2/L3）的关系 |
| [§11](#11-建议的补齐清单按优先级) | 建议的补齐清单 |
| [§12](#12-验收与自查命令清单) | 验收与自查命令清单 |

---

## 1. 分工：两个文件各干什么

| | `06-repo-feature-conventions.json` | `cr-prefix.yml` |
|---|---|---|
| 是什么 | **GitHub Ruleset**（服务端策略声明） | **GitHub Actions workflow**（CI 校验器） |
| 回答的问题 | "**哪些**分支、**必须**满足**哪些**条件才能合入" | "**这条 PR 到底合不合规**"（跑出绿勾/红叉） |
| 运行时机 | **不运行**，是 GitHub 在合并时刻用来**求值**的规则集 | **PR 事件触发就运行**，产出 check run |
| 失败形态 | 合并按钮灰掉 + "Expected — Waiting for status to be reported" | job `exit 1` → check 结论 `failure` → 红色 annotation |
| 谁能绕过 | 只能通过 `bypass_actors`（当前是空） | **能**（任何 workflow 发一个同名 check 都能冒充，见 §8.5） |
| 计划要求 | 仓库级 ruleset：**所有计划都有** ✅ | Actions：**所有计划都有** ✅ |
| 类比 | 锁（合同条款） | 锁匠（真的来验锁的师傅） |

> ★ 关键点：**Ruleset 自己不会"跑"任何东西**。
> 它的 `required_status_checks` 只是一个**约定**：合并前我必须看到名叫 `cr-prefix` 的检查且结论为 success。
> 真正去产生这个结论的，只有 `cr-prefix.yml`。

---

## 2. 逐段拆解 `06-repo-feature-conventions.json`

### 2.1 元信息

```jsonc
{
  "name": "dev-branch-guard",     // ruleset 名字，UI 上显示的名字，apply-rulesets.sh 用它做幂等键
  "target": "branch",             // ★ 作用对象类型：分支（不是 tag、不是 repository）
  "enforcement": "disabled",      // ★ 生效开关：disabled = 规则已建好但不执行
```

| 字段 | 作用 | 你现在的值 | 说明 |
|---|---|---|---|
| `name` | 规则集名字 | `dev-branch-guard` | `apply-rulesets.sh` 靠它判断"已存在→PUT 更新，不存在→POST 创建"，可反复跑 |
| `target` | 规则作用在什么上 | `branch` | `branch` / `tag` / `repository` / `push`。这里是分支 |
| `enforcement` | 是否真的执行 | `disabled` | ⚠️ **文件里是 disabled，但你线上已经是 `active`**（见 §6） |

> ★ **`enforcement: disabled` 是"故意"的安全姿势**：
> 官方 Runbook 的建议是"先建不生效 → 联调 → 再打开"。
> 这样万一 `context` 名字写错、check 永远不出现，也不会把所有人卡死。

### 2.2 `conditions` —— 决定"哪些分支受管"

```jsonc
"conditions": {
  "ref_name": {
    "include": [
      "refs/heads/feature/**",
      "refs/heads/git-apps/**",
      "refs/heads/fix/**",
      "refs/heads/codex/**"
    ],
    "exclude": []
  }
}
```

| 字段 | 语义 |
|---|---|
| `ref_name.include` | fnmatch 模式列表，匹配**受管的分支**（`refs/heads/` 前缀 + 分支名） |
| `ref_name.exclude` | 从 include 里再挖掉的例外（当前空） |
| `*` vs `**` | fnmatch 语义：**`*` 不跨 `/`，`**` 跨层级**。所以 `feature/**` 匹配 `feature/a`、`feature/a/b`，但**不匹配** `feature` 本身 |

> ★★★ **最容易理解错的一条**：这里的 `ref_name` 是"**被保护分支**"，
> 对 `pull_request` 规则来说 = **PR 的目标分支（base）**，**不是**你开发用的源分支。
> 详见 [§7](#7-★-关键语义澄清ref_name-管的是-pr-的-目标分支)。

### 2.3 四条 `rules`

#### ① `deletion` —— 禁止删除受管分支

```jsonc
{ "type": "deletion" }
```

不允许 `git push origin --delete feature/x`、也不允许在 UI 上删分支。
防止"把带着违规历史的分支删掉重建"这种绕过手段。

#### ② `non_fast_forward` —— 禁止强推（force push）

```jsonc
{ "type": "non_fast_forward" }
```

禁止 `--force` / `--force-with-lease` 推送到受管分支。
防止"推一条合规历史 → 通过检查 → 再强推成违规历史"（TOCTOU 绕过）。

#### ③ `pull_request` —— 必须走 PR + 合并方式约束

```jsonc
{
  "type": "pull_request",
  "parameters": {
    "required_approving_review_count": 0,        // ← 不要求人工 review
    "dismiss_stale_reviews_on_push": false,
    "require_code_owner_review": false,
    "require_last_push_approval": false,
    "required_review_thread_resolution": false,
    "allowed_merge_methods": ["squash", "merge"]  // ← 允许 squash 和 merge，禁止 rebase merge
  }
}
```

| 参数 | 作用 | 这里的值意味着 |
|---|---|---|
| `required_approving_review_count: 0` | 需要的审批人数 | **0 人** → 纯自动化门禁，不卡人工审批。个人仓库合理；团队仓库建议 ≥1（注意 `require_last_push_approval` 在单人仓库会把自己锁死） |
| `allowed_merge_methods` | 允许的合并方式 | `squash`（压成一个 commit）+ `merge`（保留 merge commit）。**禁掉了 `rebase`** → 避免历史被改写后已通过的检查"失效" |
| `dismiss_stale_reviews_on_push: false` | 推新 commit 后是否作废旧 review | 保留旧 review（不过没有 review 要求，意义不大） |
| `require_last_push_approval: false` | 必须由"最后推送的人之外"的人批准 | 关（单人仓库不关就死锁） |
| `required_review_thread_resolution: false` | 必须解决所有 review 讨论 | 关 |
| `require_extra_approval_for_unattributed_changes: true` | 线上多出来的字段 | 对"非作者新推的 commit"要求额外一个人批准。因为审批数为 0，实际不生效，但**开着更安全**（GitHub 侧补的默认项） |

> ★ **`pull_request.parameters` 的字段必须写全**。
> 少写一个 → GitHub API 直接 `422 Invalid property /rules/N: data matches no possible input`，
> 报错信息**完全看不出缺了哪个字段**。这是 Runbook §2.5.3 记录的实测坑。
> （本文件 5 个字段齐全 ✅，线上还多了一个 GitHub 侧补的 `required_extra_approval_for_unattributed_changes`。）

#### ④ `required_status_checks` —— ★ 核心：绑定 `cr-prefix`

```jsonc
{
  "type": "required_status_checks",
  "parameters": {
    "required_status_checks": [
      { "context": "cr-prefix" }        // ★★★ 与 workflow 的 job name 逐字符一致
    ],
    "strict_required_status_checks_policy": false,  // 分支不必"追平" base 分支
    "do_not_enforce_on_create": true                // 开 PR 的那一刻不强制
  }
}
```

| 参数 | 语义 | 影响 |
|---|---|---|
| `required_status_checks[].context` | **必须存在的 check 名**。GitHub 在 PR 上找**同名的 check run**，且 `conclusion == success` | ★ 这里写 `"cr-prefix"`，而 workflow 的 job `name: cr-prefix` → **对上了**。写错一个字符 → PR 永远 "Waiting for status to be reported"，**谁都合不了** |
| `strict_required_status_checks_policy` | `true` = 合入前分支必须是最新的（已把 base 的新提交合进来）；`false` = 不用 | 这里是 `false` → base 变了不需要先同步。（对比 [`07-commit-message-cr-prefix-protected.json`](./07-commit-message-cr-prefix-protected.json) 的 `true`） |
| `do_not_enforce_on_create` | `true` = 开 PR 的瞬间不要求 check 已存在 | ⚠️ **只放宽了"创建"这一刻**；一旦再 push（`synchronize`）就恢复强制。所以它不能作为"绕过"的长期漏洞 |
| `integration_id` | **限定这个 check 必须来自哪个 App** | ⚠️ **本文件没写** → 语义是 **"Any source"** → 仓库里任何 workflow（甚至外部 App）发一个叫 `cr-prefix` 的成功结论都能满足门禁。见 §8.5 |

#### ⑤ `bypass_actors: []`

```jsonc
"bypass_actors": []
```

**没有任何人 / 团队可以绕过这条规则**（含管理员）。
这在个人账号仓库上少见（一般会留自己一条）——好处是"门禁真的有效"，代价是**你自己也会被卡**（§8.3 的 PR #219 就是这么死的）。

---

## 3. 逐段拆解 `cr-prefix.yml`
- /Users/lex/git/knowledge/.github/workflows/cr-prefix.yml
### 3.1 触发器

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, edited]
```

| 事件 | 何时触发 | 为什么需要 |
|---|---|---|
| `opened` | 新开 PR | 第一次校验 |
| `synchronize` | **往 PR 分支再推一次 commit** | ★ 最重要：commit 被改写/追加后必须重新校验，否则"先合规后偷改"就绕过了 |
| `reopened` | 关闭后重开 | 重开也要重新校验 |
| `edited` | **改 PR 标题** | ★ 因为 PR 标题参与校验（squash 时它会成为最终 commit message） |

> ★ 注意：**没有** `branches:` 过滤 → 对**所有**目标分支的 PR 都跑。
> 也没有 `workflow_dispatch`（仓库模板 `workflows/cr-prefix-check.yaml` 里有，这里删掉了 → 不能手动重跑）。

### 3.2 权限（最小权限）

```yaml
permissions:
  contents: read
  pull-requests: read
```

只读。不需要写权限 → 即使 workflow 被篡改，token 也写不了东西。**这是安全写法**（仓库模板里只有 `contents: read`，这里更严）。

### 3.3 Job 与名字

```yaml
jobs:
  cr-prefix:
    name: cr-prefix        # ★★★ 这就是 status check 的 context！
    runs-on: ubuntu-latest
    env:
      PREFIX_REGEX: "CH[0-9]+"
```

> ★★★ **全链路最关键的一行**：
> **GitHub Actions 产生的 check run 名字 = job 的 `name`（没写 `name` 时 = job 的 id）**。
> - workflow 顶层的 `name: cr-prefix` → 是 **workflow run** 的名字，**不会**成为 check 名；
> - job 的 `name: cr-prefix` → **这才是 check 名**。
>
> 这里 job 的 id 和 `name` 都是 `cr-prefix`，所以**无论 GitHub 取哪个，结果都是 `cr-prefix`** → 与 ruleset 的 `context` 对上。
> ⚠️ 如果你以后把 job 改成矩阵（`strategy.matrix`），check 名会变成 `cr-prefix (xxx)` → **ruleset 立刻对不上 → 全员卡死**。

### 3.4 步骤一：拉全量历史

```yaml
- name: Checkout PR history
  uses: actions/checkout@v4
  with:
    fetch-depth: 0
```

`fetch-depth: 0` = 克隆**完整历史**（不是默认的浅克隆 1 层）。
不这样 `git log BASE..HEAD` 会因为历史不全而算错/算空。

### 3.5 步骤二：两条校验

```yaml
env:
  PR_TITLE: ${{ github.event.pull_request.title }}
  BASE_SHA: ${{ github.event.pull_request.base.sha }}
  HEAD_SHA: ${{ github.event.pull_request.head.sha }}
```

> ★ **用 `env:` 传值而不是直接插进 `run:` 脚本** —— 这是**防命令注入**的标准做法。
> PR 标题是攻击者可控的字符串，直接 `${{ }}` 拼进 shell 等于把 shell 交给攻击者。
> （仓库模板 `cr-prefix-check.yaml` 的注释里也强调了这一点。）

```bash
set -euo pipefail
fail=0

# 校验 ①：PR 标题
if ! echo "$PR_TITLE" | grep -Eq "$PREFIX_REGEX"; then
  echo "::error::PR title must contain a CR prefix matching $PREFIX_REGEX, ..."
  fail=1
fi

# 校验 ②：PR 内每一个非 merge commit 的 subject
mapfile -t subjects < <(git log --format=%s --no-merges "$BASE_SHA..$HEAD_SHA" || true)
for subject in "${subjects[@]}"; do
  if ! echo "$subject" | grep -Eq "$PREFIX_REGEX"; then
    echo "::error::Commit message must contain a CR prefix ..."
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then exit 1; fi
```

| 设计点 | 为什么这么写 |
|---|---|
| `fail=0` 累加，**最后统一 exit 1** | ★ 一次跑完把**所有**不合规的 commit 全列出来，而不是改一个报一次。体验好得多 |
| `--no-merges` | 跳过 `Merge branch ...` 这类 merge commit —— 它们是 GitHub 生成的，不可能带 CR 号 |
| `|| true` + `mapfile` | `git log` 对空区间返回 0 但输出为空，`mapfile` 在某些 shell 下会因此整体失败 → 加 `|| true` 兜住；空数组再单独 warning |
| `::error::` 注解 | GitHub Actions 语法 → **在 PR 的 Checks 面板和代码 diff 上直接显示红色 annotation**，点进去就能看到是哪一行 commit 不合规 |
| `grep -Eq "$PREFIX_REGEX"` | `-E` 正则扩展语法，`-q` 静默（只关心退出码） |

### 3.6 正则：`CH[0-9]+`（contains 语义）

```yaml
PREFIX_REGEX: "CH[0-9]+"
```

| 判定 | 例子 | 结果 |
|---|---|---|
| ✅ 通过 | `feat(actions): add cr-prefix check for CH013456` | 标题里**含** `CH013456` |
| ✅ 通过 | `CH013456 release: pfb-gcp-v0.1.0: github app` | 开头就是 |
| ✅ 通过 | `fix: bump dep to v1.2.3-rc1` | 无 `CH`+数字 → ❌ 实际不通过 |
| ❌ 不通过 | `release: pfb-gcp-v0.1.0: github app` | 没有 `CH`+数字 |

> ★ **这是"包含"不是"必须开头"**，而且文件头注释里明确说明了原因：
> 仓库里还有一个**本地 Conventional Commits hook** 强制 `<type>(<scope>): <summary>`，
> 如果规则要求"必须以 CH 开头"，会和那个 hook 冲突。
> → **改规则只需要改 `PREFIX_REGEX` 这一处**（设计得不错）。
>
> ⚠️ 但"包含"是有代价的，见 §8.4。

---

## 4. 两者怎么咬合：`context` == job `name`

```
                    ┌──────────────────────────────────────────┐
06 ruleset JSON ───►│ required_status_checks[0].context        │
                    │            = "cr-prefix"                 │
                    └──────────────────┬───────────────────────┘
                                       │  ★ 必须逐字符相等
                                       ▼
cr-prefix.yml ────►  jobs.cr-prefix.name = "cr-prefix"
                            │
                            ▼
              GitHub Actions 跑完 → 产出 check run
              check run.name = "cr-prefix"
              check run.conclusion = success / failure
                            │
                            ▼
      GitHub 合并时刻求值：目标分支命中 ruleset？
              ✅ → 找到名为 "cr-prefix" 的 check 且 success → 放行
              ❌ → 红色 "Expected — Waiting for status to be reported" / 合并按钮灰掉
```

**两条 link 断了会怎样：**

| 断点 | 现象 | 严重度 |
|---|---|---|
| `context` 拼错（如 `cr_prefix`） | check 永远不出现 → **所有 PR 卡死**（不是"拦下来"，是"全都过不去"） | 🔴 致命 |
| check 名字对但 workflow 在 base/head 里都没有 | 同上，**该 PR 卡死**（见 §8.3 实例） | 🔴 致命 |
| `context` 写成 `cr/prod-validation`（CR Check App 的名字） | CR Check App 没在这个仓库跑 → 卡死 | 🔴 致命 |

> ★ 这就是 [§10](#10-与三层判定模型l1--l2--l3的关系) 里 **C1 契约**的含义：
> `context` 必须和"产出这个 check 的东西"的名字对得上。
> `validate-rulesets.py` 的 C1 断言查的就是这个（当前它对的是 `policy.yaml` 的 `checkName`，而 06 用的是 `cr-prefix`，两者是**两套不同的 check**，见 §8.6）。

---

## 5. 完整生命周期：一次 PR 从开到合

```
① 开发者本地 commit
   "feat(actions): add cr-prefix check for CH013456"
        │  ← L1 本地 hook（可选，秒级反馈，可被 SKIP 绕过）
        ▼
② git push origin feat/cr-prefix-action
        │  ← 目标分支若是 feature/** 等受管分支：
        │     · deletion / non_fast_forward 生效
        │     · push 本身不检查 commit message（06 没有 commit_message_pattern）
        ▼
③ 开 PR：feat/cr-prefix-action → git-apps/lex
        │
        ├──────────────────────────────────────────────┐
        ▼                                              ▼
④ GitHub 触发 cr-prefix.yml                    ⑤ 合并时刻 GitHub 求值 06
   （workflow 取自 PR 的 merge ref：base ∪ head，任意一边有就跑）      conditions.ref_name 命中 git-apps/lex？
   ├ checkout --depth 0                              ✅ 命中
   ├ 校验 PR 标题含 CH[0-9]+                        ↓
   ├ 校验每个非 merge commit 的 subject              rules:
   └ exit 0 → check "cr-prefix" = success              · deletion
   （失败 → check = failure + ::error:: 红色标注）      · non_fast_forward
        │                                              · pull_request（必须走 PR）
        │                                              · required_status_checks
        ▼                                                context "cr-prefix" == success ✅
   PR 上出现绿勾 "cr-prefix"                               │
        └──────────────┬─────────────────────────────────┘
                       ▼
⑥ 点 Merge（squash 或 merge 都可以）
        │
        ▼
⑦ 合入目标分支（git-apps/lex）
   · squash → 最终 commit message = PR 标题 + " (#220)"
   · merge  → 生成 "Merge pull request #220 ...\n\n<PR 标题>"
        ▼
⑧ 规则继续生效：不能删分支、不能强推
```

---

## 6. 线上实测状态（`aibangjuxin/knowledge`）

### 6.1 ruleset 现状

| ruleset | 来源文件 | id | enforcement | 覆盖分支 |
|---|---|---|---|---|
| `dev-branch-guard` | **06-repo-feature-conventions.json** | `26786098` | **active** ✅ | `feature/**` `git-apps/**` `fix/**` `codex/**` |
| `main-branch-guard` | 07-commit-message-cr-prefix-protected.json | `26786097` | **disabled** ⚠️ | `main` `*Release`（**当前不生效**） |

变更历史：
```
2026-11-08 12:04:22  aibangjuxin  ← 创建
2026-11-08 12:20:48  aibangjuxin  ← 改成 active
```

### 6.2 分支实际生效情况（`gh api repos/…/rules/branches/<branch>`，权威接口）
```json
      "include": [
        "refs/heads/feature/**",
        "refs/heads/git-apps/**",
        "refs/heads/fix/**",
        "refs/heads/codex/**"
      ],
```

| 分支 | 实际生效的规则 |
|---|---|
| `main` | **（无）** ⚠️ |
| `Lex-Release` | **（无）** ⚠️ |
| `rag` | **（无）** |
| `feat/cr-prefix-action` | **（无）** ⚠️ ← 因为规则写的是 `feature/**`，不是 `feat/**` |
| `feat/CH013456-pfb-gcp-v0.1.0` | **（无）** ⚠️ 同上 |
| `codex/add-cr-prefix-ci` | deletion, non_fast_forward, pull_request, required_status_checks ✅ |
| `codex/dockerfile-md-format` | 同上 ✅ |
| `fix/safe-kms-record-check-and-sa-permission-match` | 同上 ✅ |
| `git-apps/lex` | 同上 ✅ |

### 6.3 PR 实测

| PR | head → base | base 受管？ | `cr-prefix` check | 标题 | 结果 |
|---|---|---|---|---|---|
| **#220** | `feat/cr-prefix-action` → `git-apps/lex` | ✅ | ✅ success | `CH013456 release: 220 fix violation` | **已合并**（merge commit，0 review） |
| **#221** | `feat/cr-prefix-action` → `main` | ❌（main 未启用） | ✅ success（**仅参考性**） | `feat(actions): add cr-prefix check for CH013456` | 已合并 |
| **#219** | `feat/CH013456-pfb-gcp-v0.1.0` → `codex/add-cr-prefix-ci` | ✅ | ❌ **从没跑过** | `CH013456 release: pfb-gcp-v0.1.0: github app` | **被关闭，未合并** 🔴 |
| **#212** | `fix/safe-kms-...` → `main` | ❌（main 未启用） | ❌ | `fix(safe/gcp-safe): use jq -n ...`（**无 CR 号**） | 已合并（2026-08-02，当时 ruleset 还没建） |

> ★ 三条实测结论：
> 1. **#220 是"门禁真正生效"的唯一样本**：base 受管 + check 绿 → 合入。
> 2. **#219 是"workflow 缺失 → PR 卡死"的活样本**（详见 §8.3）。
> 3. **#212 证明了 main 目前是裸奔的**：一个完全没有 CH 号的 PR 直通 main，因为 `main-branch-guard` 还是 disabled。

---

## 7. ★ 关键语义澄清：`ref_name` 管的是 PR 的**目标**分支

这是本次分析里**最容易踩、影响最大**的一条。

```
        ┌──────────────┐   PR   ┌──────────────────┐
        │  head 分支    │ ─────► │   base / target  │
        │ feat/cr-prefix│        │  git-apps/lex    │
        └──────────────┘        └──────────────────┘
           你开发的地方                 ↑ 06 的 ref_name 匹配的是这个
```

**规则集的 `conditions.ref_name` 匹配的是「被保护的分支」**，对 `pull_request` 规则而言 = **PR 的目标分支**。

| 你以为 | 实际 |
|---|---|
| "我建了 `feature/**` 的规则，所以我在 `feat/xxx` 上开的 PR 会被检查" | ❌ 错。规则管的是**合入 `feature/**`** 的 PR |
| "PR 从 `fix/xxx` 提出来 → 会被 `fix/**` 规则管住" | ❌ 错（#212 就是证明：源分支 `fix/...`，目标 `main`，规则**没**生效） |
| "PR 提到 `git-apps/lex` → 会被 `git-apps/**` 规则管住" | ✅ 对（#220 实测） |

**这带来一个直接后果**：06 的实际作用是"**保护 feature/git-apps/fix/codex 这些长生命周期分支本身不被乱改**"，
而**不是**"保护 main 不被乱合"。

```
   06 (dev-branch-guard) 保护的是这些分支作为「合并目标」：
       feature/**  git-apps/**  fix/**  codex/**
       → 往这些分支合 PR，必须先过 cr-prefix 绿勾

   07 (main-branch-guard) 保护的是：
       main  *Release
       → ★ 当前 disabled，所以往 main 合 PR 现在没人管
```

---

## 8. ★ 五个已确认的缺口

### 8.1 🔴 `feat/**` 分支完全没被覆盖

**现象**：仓库里实际用的是 `feat/`（`feat/cr-prefix-action`、`feat/CH013456-pfb-gcp-v0.1.0`），
而 06 写的是 `feature/**`。**`feature` 和 `feat` 是两个不同的字符串。**

**实测**：`rules/branches/feat/cr-prefix-action` → **无规则**。

**影响**：
- 往 `feat/**` 合 PR 时，`dev-branch-guard` 不生效 → **cr-prefix 绿勾不是强制的**；
- 但 `feat/**` 分支本身也享受不到"禁删 / 禁强推 / 必须走 PR"的保护。

**修法**（二选一）：
```jsonc
"include": [
  "refs/heads/feature/**",
  "refs/heads/feat/**",        // ← 加上这个
  "refs/heads/git-apps/**",
  "refs/heads/fix/**",
  "refs/heads/codex/**"
]
```
> 更稳的做法：**统一分支命名规范**，然后用 `branch_name_pattern`（需要 Enterprise）或**在 workflow 里加一条分支名校验**
> （仓库模板 `cr-prefix-check.yaml` 第 3 步就是留好的开关，`^(feature|fix|git-apps|codex)/`）。

### 8.2 🔴 `main` 完全裸奔（07 还是 disabled）

**现象**：`main-branch-guard` = disabled → `rules/branches/main` 返回空。
实测 #212（标题无 CR 号）直通 main。

**后果**：
- `cr-prefix` check 在 PR 上**照跑照绿**，但**没人消费它** → 退化成"参考信息"；
- ★ 更糟的是：**PR 标题里的 CH 号不会被强制**，因为 06/07 里都没有 `commit_message_pattern`
  （个人账号上这条规则 API 直接 422、UI 导入还会静默丢弃 → 只能用 CI 兜，见 §10）。

**修法**：
```bash
cd examples/rulesets
# ★ 必须先 dry-run 看完整 payload，再下发；PUT 是全量替换，不能只传一个字段
CR_CHECK_APP_ID=<你的 App ID> ./apply-rulesets.sh --dry-run --owner aibangjuxin --repo knowledge
CR_CHECK_APP_ID=<你的 App ID> ./apply-rulesets.sh --owner aibangjuxin --repo knowledge \
    --enforcement active --only main-branch-guard
```
> 但注意：启用前必须先做 §12 的"联调"，否则 `main` 会因为 check 没跑起来而**全员卡死**。

### 8.3 🔴 workflow 在 base 和 head 里**都没有** → PR **永久卡死**（实测 #219）

**机制**：`pull_request` 事件用的 workflow 文件取自 **PR 的 merge ref**（base ∪ head 合成的那个合并结果）。
★ 因此 **base 里有、或者 head 里有，任意一边有就会跑**；
**只有两边都没有**时，check 才永远不会产生 →
ruleset 的 required check 永远是 "Expected — Waiting for status to be reported" → **合并按钮永远是灰的**。

**实测（三组对照）**：

| PR | base 有 wf？ | head 有 wf？ | check 跑了？ |
|---|---|---|---|
| #220 | ❌（当时 git-apps/lex 还没有） | ✅ | ✅ 跑了 → 绿 → 合并成功 |
| #219 | ❌（codex/add-cr-prefix-ci 没有） | ❌（feat/CH013456-... 没有） | ❌ **从没跑过** → PR 卡死 → 2026-11-08 05:25:41 被关闭，未合并 |
| lab D | ✅（feature/cr-prefix-verify 有） | ❌（源分支从 codex/... 切出，没有） | ✅ **照样跑了** → 红 → BLOCKED |

> ★ 所以 PR #219 的真正教训不是"head 必须带 workflow"，
> 而是"**base 和 head 都没带**"——而 base 往往是更长期存在、却更容易被忘掉更新的那个。

**修法 / 规避**：
1. **先合 workflow 到 main**（已经做了 ✅，`main` 上有 `cr-prefix.yml`），
   再让新分支从 main 拉出来 → base/head 任意一边都会带上；
2. ★ 更关键：**确保 base 分支上有 workflow**。
   受管分支（`feature/**` `git-apps/**` `fix/**` `codex/**`）如果自己是从"没 workflow 的老分支"切出来的，
   它自己就会成为"两边都没有"的受害者 —— 实测里 `codex/add-cr-prefix-ci` 就是这种分支；
3. 老分支 **base 和 head 都得补**：
   `git checkout main -- .github/workflows/cr-prefix.yml`；
4. 兜底：ruleset 里加 `do_not_enforce_on_create` 只能救"创建那一刻"，救不了"check 从没跑过"。

> ★ 这是本次分析发现的最有价值的一条：**门禁装好后，PR 卡死的最常见原因不是"规则太严"，而是"检查从来没跑过"**。
> 排查口诀（见 §12）：
> ```bash
> gh api repos/O/R/commits/<head_sha>/check-runs --jq '.check_runs[].name'
> # 看不到 cr-prefix → 就是这个问题（不是 PR 标题写错了）
> ```
> 再确认一下 base 侧：
> ```bash
> git ls-tree origin/<base分支> .github/workflows/
> ```

### 8.4 🟡 `CH[0-9]+`（contains）比设计意图弱得多

| 弱在哪 | 例子 | 结果 |
|---|---|---|
| 不要求在开头 | `feat(actions): add cr-prefix check for CH013456` | ✅ 通过（设计如此，为了兼容 Conventional Commits hook） |
| **位数不限** | `CH1` | ✅ 通过 —— 文档里的 CR 号是 6 位（`CH013456`） |
| **不锚定词边界** | `PATCH01`、`MATCH123`、`BATCH9` | ✅ 通过 —— 只要大写 `CH` 后面跟数字就行 |
| **PR 标题和 commit 可以用不同的号** | 标题 `CH013456`、commit `CH999999` | ✅ 都通过 —— **没有任何一致性校验** |

**对比仓库模板的严格版**：`^CR[0-9]{6}(\s|$)`（必须开头 + 恰好 6 位）。

**建议**（看你想要多严）：
```yaml
# A. 保持 contains，但锁死位数 + 词边界（改动最小，仍兼容 Conventional Commits）
PREFIX_REGEX: "(^|[^A-Z])CH[0-9]{6}([^0-9]|$)"
# B. 标题要求"开头"，commit 允许"包含"（最贴近实际诉求）
#    → 拆成两个正则：PREFIX_REGEX_TITLE / PREFIX_REGEX_COMMIT
```
> ★ 无论选哪个，**标题和 commit 里的 CR 号应该一致**才最有价值。
> 现在没有这个约束 —— 可以再加一条：抽取标题里的号，要求每个 commit 里出现**同一个**号。

### 8.5 🟡 没有 `integration_id` → 同名 check 可伪造（C2 断裂）

**现象**：`required_status_checks` 里只有 `{"context": "cr-prefix"}`，**没有 `integration_id`** →
语义是 **"Any source"**。

**影响**：仓库里**任何一个** workflow（甚至外部 PR 提交的 workflow）只要发出一个名叫 `cr-prefix` 的成功 check，
就能满足门禁。规则本身也允许 PR 作者改动 workflow 文件 → **可以自己给自己发绿勾**。

**修法**（二选一）：
- 给规则加上 `integration_id`（指向 GitHub Actions App id = `15368`）：
  ```jsonc
  "required_status_checks": [
    { "context": "cr-prefix", "integration_id": 15368 }
  ]
  ```
  > `15368` = GitHub Actions 官方 App id。
  > ⚠️ 但 **Actions 不在"可信来源"里**：官方文档明确说选 Actions 作为 expected source 时，
  > 它对**来自 PR 的 workflow 改动**不做区分 —— 也就是 `pull_request_target` 那种改 workflow 再发 check 的玩法仍可绕过。
  > → **真正的"来源绑定"要靠 `pull_request_target` + 从 base 分支读 workflow，或用自建 App（见 §10 L3）。**
- 或者：加一条 `pull_request` 规则把 `allowed_merge_methods` 收成 `["squash"]`，
  并要求 `required_approving_review_count ≥ 1` → 至少有个人看过。

### 8.6 🟡 06 只管"格式"，不管"真假"

06 引用的 check 是 `cr-prefix`（纯格式），
而 CR Check App 产出的是 **`cr/prod-validation`**（查 CR 平台，验真伪 + 审批 + 环境 + 窗口）——
**这两个 check 是两回事**，`validate-rulesets.py` 的 C1 契约也是对着 `cr/prod-validation` 的。

**所以现状是**：CR 号 `CH999999` 只要**格式对**就能过 → **假 CR 号畅通无阻**。
真伪校验（CR Check App）在 `aibangjuxin/knowledge` 上**还没接上**（仓库里没有 CR Check App 的 check）。

---

## 9. 应用场景

### 9.1 这套组合在解决什么问题

> **让"每一次变更都能追溯到一个变更单（CR）号"，并且这个约束由服务器强制，而不是靠人自觉。**

具体解决的痛点：

| 痛点 | 06 + workflow 怎么解决 |
|---|---|
| 提交信息五花八门，事后无法追溯是哪次变更 | commit subject + PR 标题都必须带 CR 号 → `git log` 里一眼能查 |
| 开发者绕过流程直接 push | `pull_request` 规则：受管分支**必须走 PR**；`non_fast_forward` 防改历史 |
| 有人强推覆盖掉被审过的历史 | `non_fast_forward` 直接拒 |
| 分支被随手删掉（连同违规历史） | `deletion` 拒 |
| 靠人肉 review 记性检查格式 | 机器判，秒级出红叉，不合规 commit 逐条列出 |

### 9.2 典型使用场景

**场景 A · 功能分支开发（日常主路径）**
```
feat/cr-prefix-action  --PR-->  git-apps/lex      ← 受管 ✓
  commit: "feat(actions): add cr-prefix check for CH013456"   ✓ 含 CH 号
  PR 标题: "CH013456 release: 220 fix violation"              ✓ 含 CH 号
  → cr-prefix 绿勾 → 合并（实测 #220）
```

**场景 B · 修 bug**
```
fix/safe-kms-...  --PR-->  fix/safe-kms-...     ← 受管 ✓（如果 PR 目标是受管分支）
```
> ⚠️ 注意：如果 PR 目标是 `main`（最常见的修 bug 路径），当前 **main 未受管** → 不拦（场景 §8.2）。

**场景 C · AI agent / 自动化分支**
```
codex/add-cr-prefix-ci  --PR-->  codex/add-cr-prefix-ci   ← 受管 ✓
```
> 这类分支往往是 agent 批量产出的 commit，格式最容易乱 → 正是门禁最该拦的地方。
> ★ 但也是 §8.3 卡死的高发区：**agent 拉的分支如果早于 workflow 合入 main 的时间点，就永远合不了**。
> → **纪律：agent 起分支必须从最新 main 拉。**

**场景 D · 合并到 main（★ 当前是缺口）**
```
feat/xxx --PR--> main
```
> 应由 `main-branch-guard`（07）接管：strict=true（必须追平 base）+ cr-prefix 必绿。
> ★ **当前 disabled → 这一步是裸奔的。**

### 9.3 落地形态：这是"路线 B（CI check）"

`git-apps/15-commit-message-cr-prefix.md` §3 给出了两条路线：

| | 路线 A · metadata 规则 | **路线 B · CI check（你现在这条）** |
|---|---|---|
| 实现 | ruleset 的 `commit_message_pattern` | **GitHub Actions + `required_status_checks`** |
| 可用性 | **仅 Enterprise 组织** | **所有计划 + 个人账号** ✅ |
| 拦截时机 | push（ref 不更新） | PR 打开/更新时（check 变红） |
| 本仓库可用？ | ❌ API 422 / UI 静默丢弃 | ✅ |

> ★ **你选路线 B 是正确的**：个人账号 `aibangjuxin` 上 `commit_message_pattern` 会被 GitHub 直接拒绝，
> 而 UI 导入还会**静默丢弃**（ruleset 显示 active 但 `rules: []`）—— 这正是 Runbook §2.5 记录的坑。
> **06 就是路线 B 的"锁"，`cr-prefix.yml` 就是路线 B 的"钥匙"。**

---

## 10. 与三层判定模型（L1/L2/L3）的关系

```
   开发者 git commit -m "feat(actions): ... CH013456"
        │
        ├─ L1 本地 commit-msg hook ──────► 秒级反馈（可绕过，非权威）
        │    · examples/rulesets/commit-msg-hook.sh
        │    · ⚠️ 注意：本地 hook 用的是 ^CR[0-9]{6}，和你线上 workflow 的 CH[0-9]+ 不一致
        │
   git push
        │
        ├─ L2 GitHub Ruleset ────────────► 服务端权威
        │    · ★ 你现在的 06 就在这一层，但它只负责"合并时刻的准入"
        │    · 它不校验 commit message（没有 commit_message_pattern）
        │    · 真正的格式判定在下面的 CI check 里
        │
   开 PR → GitHub 触发 cr-prefix.yml ──► ★ 格式判定发生在这里（服务端、不可绕过）
        │      产出 check "cr-prefix" → 被 06 的 required_status_checks 消费
        │
        ├─ L3 CR Check App ──────────────► 管"真伪"：CR 存在吗？已批准吗？环境对吗？窗口内吗？
        │    · 产出 check "cr/prod-validation"（policy.yaml 的 checkName）
        │    · ★ 当前仓库尚未接入 → 06 也没引用它 → 假 CR 号仍可通行（§8.6）
        │
   点 Merge
        │
        └─ GitHub 求值：L2 规则全过 + 06 要求的 "cr-prefix" 绿
             → 才放行
```

**一句话总结**：
> **06 决定"什么时候必须看那个绿勾"，`cr-prefix.yml` 决定"绿勾什么时候会变绿"。**
> **两者都在服务端 → 都不可绕过 → 这就是它和"靠人自觉写 commit message"的本质区别。**

---

## 11. 建议的补齐清单（按优先级）

| # | 优先级 | 动作 | 命令 / 改动 | 预期效果 |
|---|---|---|---|---|
| 1 | 🔴 P0 | `feat/**` 加入 06 的 `include` | 改 `06-repo-feature-conventions.json`，加 `"refs/heads/feat/**"` | 你实际在用的两条 feat 分支进入门禁 |
| 2 | 🔴 P0 | 启用 `main-branch-guard`（07） | `apply-rulesets.sh --enforcement active --only main-branch-guard`（**先 dry-run + 联调**） | main 不再裸奔；PR 标题的 CH 号变成强制 |
| 3 | 🔴 P0 | 加"base 分支必须带 workflow"的纪律 | 受管分支自己也要有 `.github/workflows/cr-prefix.yml`；agent/新分支一律从最新 main 拉 | 消灭 PR #219 那种"永久卡死" |
| 4 | 🟡 P1 | 收紧正则 | `PREFIX_REGEX: "(^|[^A-Z])CH[0-9]{6}([^0-9]|$)"` | 挡住 `CH1` / `PATCH01` 这类假阳性 |
| 5 | 🟡 P1 | 加"标题与 commit 的 CR 号一致"校验 | workflow 里加一段比对 | 防止标题写 `CH013456`、commit 写 `CH999999` |
| 6 | 🟡 P1 | 本地 hook 与 workflow 正则同源 | 改 `commit-msg-hook.sh` 的正则 = workflow 的 `PREFIX_REGEX` | 本地过了服务器也过，别白折腾 |
| 7 | 🟡 P2 | 收紧合并方式 | `allowed_merge_methods: ["squash"]` | 线性历史、可追溯 |
| 8 | 🟡 P2 | 接 CR Check App（`cr/prod-validation`） | App 装到仓库 + 在 ruleset 里加第二个 required check | ★ 才有"真假"校验（当前只管格式） |
| 9 | 🟢 P3 | `integration_id` 限定来源 | `{"context": "cr-prefix", "integration_id": 15368}` | 缩小同名 check 伪造面（但 Actions 本身仍有局限，见 §8.5） |
| 10 | 🟢 P3 | 加 `workflow_dispatch` + 分支名校验 | workflow 加 `workflow_dispatch`；打开模板里预留的分支名校验步骤 | 能手动重跑；分支命名统一 |

---

## 12. 验收与自查命令清单
- verify-cr-prefix.sh
```bash
REPO=aibangjuxin/knowledge

# ── ① 规则集现状（注意 list 接口不返回 rules，必须按 id 查）────────────
gh api repos/$REPO/rulesets --jq '.[] | "\(.id)\t\(.name)\t\(.enforcement)"'
for id in $(gh api repos/$REPO/rulesets --jq '.[].id'); do
  gh api repos/$REPO/rulesets/$id --jq '"\(.name): rules=\([.rules[]?.type]|join(","))"'
done

# ── ② ★ 权威：某个分支上到底生效了哪些规则 ──────────────────────────
for b in main feat/cr-prefix-action codex/add-cr-prefix-ci git-apps/lex; do
  printf "%-32s " "$b"
  gh api "repos/$REPO/rules/branches/$b" --jq '[.[]|.type]|if length==0 then "(none)" else join(",") end'
done
#    ★ 返回 (none) → 这个分支不受管（06 的 include 没命中）

# ── ③ ★ 排查"PR 卡住"：check 到底有没有跑？──────────────────────────
PR=220
SHA=$(gh api repos/$REPO/pulls/$PR --jq .head.sha)
gh api repos/$REPO/commits/$SHA/check-runs --jq '.check_runs[] | "\(.name)\t\(.conclusion)"'
#    ★ 没有 cr-prefix → 是"base 和 head 都没带 workflow"（§8.3），不是标题写错

# ── ④ 门禁真的拦得住吗？（唯一权威验证）────────────────────────────
#    建一个受管目标分支的 PR，标题和 commit 都故意不带 CH 号
#    → 预期：cr-prefix 变红 + 合并按钮灰掉

# ── ⑤ 静态校验（不连 GitHub）──────────────────────────────────────
cd examples/rulesets && python3 validate-rulesets.py --strict
```

---

## 附：与其它文件的对照

| 文件 | 在本方案里的角色 |
|---|---|
| [`06-repo-feature-conventions.json`](./06-repo-feature-conventions.json) | ★ 本文的"锁"：分支保护 + 绑定 `cr-prefix` |
| [`07-commit-message-cr-prefix-protected.json`](./07-commit-message-cr-prefix-protected.json) | "锁"的主分支版本（**当前 disabled**） |
| [`workflows/cr-prefix-check.yaml`](./workflows/cr-prefix-check.yaml) | "钥匙"的仓库模板（严格版 `^CR[0-9]{6}`，带 `workflow_dispatch` + 分支名校验开关） |
| `/Users/lex/git/knowledge/.github/workflows/cr-prefix.yml` | ★ 你实际使用的"钥匙"（宽松版 `CH[0-9]+` contains 语义） |
| [`apply-rulesets.sh`](./apply-rulesets.sh) | 下发 / 切 enforcement 的脚本（`PUT` 全量替换，用 `--dry-run` 先看） |
| [`validate-rulesets.py`](./validate-rulesets.py) | 静态契约检查（C1/C2/C3 + 字段完整性） |
| [`simulate-commit-gate.py`](./simulate-commit-gate.py) | 三层判定本地模拟（不连 GitHub） |
| [`commit-msg-hook.sh`](./commit-msg-hook.sh) | L1 本地 hook（★ 当前正则与线上 workflow **不一致**，见 §11 第 6 项） |
| [`git-apps/15-commit-message-cr-prefix.md`](../../git-apps/15-commit-message-cr-prefix.md) | 完整方案（两条路线、正则写法、squash 坑、计划限制） |
| [`git-apps/16-ruleset-install-runbook.md`](../../git-apps/16-ruleset-install-runbook.md) | 安装 / 联调 / 验收 / 回滚 Runbook |
