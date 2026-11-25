# examples/rulesets/ · GitHub Rulesets 可落地配置 ＋ 契约静态检查

> 这个目录把 [`git-apps/14-rulesets-and-gitapp-gate.md`](../../git-apps/14-rulesets-and-gitapp-gate.md)
> 里的方案变成**可以直接下发到 GitHub 的 JSON**，以及**能在 CI 里跑的断言**。

---

## 1. 文件清单

| 文件 | 是什么 | 下发到哪 |
|---|---|---|
| [`01-org-baseline.json`](./01-org-baseline.json) | 组织级基线：所有仓库的默认分支 → 必须走 PR、≥1 reviewer、禁删禁强推 | `orgs/<org>/rulesets` |
| [`02-repo-dev-branches.json`](./02-repo-dev-branches.json) | `dev` 集成分支 → 1 reviewer + CI check + squash | `repos/<owner>/<repo>/rulesets` |
| [`03-repo-release-branches.json`](./03-repo-release-branches.json) | `release/**` 发布候选分支 → 2 reviewer + linear history + squash | 同上 |
| [**`04-repo-prod-branches.json`**](./04-repo-prod-branches.json) | ★ **核心**：`main` + `release/prod` → 2 reviewer + **`cr/prod-validation`（限定来源 App）** + strict | 同上 |
| [`05-push-secrets.json`](./05-push-secrets.json) | push 规则：禁 `.pem/.key/.p12` 等密钥扩展名、禁改 `releases/**`、禁 >10MB 文件 | 同上（`target: push`） |
| [`06-repo-feature-conventions.json`](./06-repo-feature-conventions.json) | **功能/开发分支保护**（PR 必需 + `cr-prefix` check）：管 `feature/**` `git-apps/**` `fix/**` `codex/**` | 仓库级（所有计划可用） |
| [**`06-dev-branch-guard-x-cr-prefix-action.md`](./06-dev-branch-guard-x-cr-prefix-action.md)** | ★ **06 ruleset × `cr-prefix` Action 联合工作详解**：两个文件怎么咬合、完整生命周期、线上实测状态、**5 个已确认的缺口** | —— （解读文档） |
| [**`ruleset-action-sample.md`](./ruleset-action-sample.md)** | ★★ **全套实验手册（A~I 共 10 个实验）**：每条都是真实跑过的输出，含验收清单、清理流程、逃生通道、故障排查表 | —— （实操手册） |
| [`07-commit-message-cr-prefix-protected.json`](./07-commit-message-cr-prefix-protected.json) | **主分支保护**（PR 必需 + `cr-prefix` check + 禁删/禁强推）：管 `main` `*Release` | 仓库级（所有计划可用） |
| [**`08-main-ruleset.json`**](./08-main-ruleset.json) | ★ **平台原生格式门禁**：`commit_message_pattern` —— 默认分支的 commit message 必须以 `<工单代号>-<数字>:` 开头（**Enterprise 专属 rule type**，非 Enterprise 会被静默丢弃） | 仓库级 `repos/...`；`conditions` 里加 `repository_name` 即变组织级 |
| [**`08-main-ruleset.md`**](./08-main-ruleset.md) | ★ **08 的逐字段解读 + 安装（UI 导入 JSON）+「ruleset 顶替 webhook 自检」的边界说明** | —— （解读文档） |
| [`workflows/cr-prefix-check.yaml`](./workflows/cr-prefix-check.yaml) | ★ **CI 校验器**：commit message + PR 标题必须 `^CR[0-9]{6}` | 装进 `<repo>/.github/workflows/` |
| [`install-ci-check.sh`](./install-ci-check.sh) | ★ 一键把 CI 校验器装进仓库（建分支 + 提交 + 开 PR） | 需要 `gh auth refresh -s workflow` |
| [`simulate-commit-gate.py`](./simulate-commit-gate.py) | ★ **三层判定模拟器**（L1 hook / L2 Ruleset / L3 App），不连 GitHub | —— |
| [`commit-msg-hook.sh`](./commit-msg-hook.sh) | ★ L1 本地 commit-msg hook（秒级反馈） | 安装到 `.githooks/commit-msg` |
| [`apply-rulesets.sh`](./apply-rulesets.sh) | 下发脚本：先静态校验 → 再 CREATE / UPDATE | —— |
| [`validate-rulesets.py`](./validate-rulesets.py) | ★ 静态检查：把 **C1/C2/C3** 三条契约变成断言 | —— |

---

## 2. 30 秒跑起来

```bash
cd examples/rulesets

# ① 静态检查（不连 GitHub）
python3 validate-rulesets.py

# ② 看将要提交给 GitHub 的 payload（不连 GitHub）
CR_CHECK_APP_ID=<你的 CR Check App ID> \
  ./apply-rulesets.sh --dry-run --owner <owner> --repo <repo>

# ③ 真正下发（★ 建议先把 enforcement 改成 disabled 再跑）
CR_CHECK_APP_ID=<你的 CR Check App ID> \
  ./apply-rulesets.sh --owner <owner> --repo <repo> --enforcement disabled

# ④ 看现状 / 回滚
./apply-rulesets.sh --list --owner <owner> --repo <repo>
./apply-rulesets.sh --delete prod-branch-gate --owner <owner> --repo <repo>
```

> ★ **`CR_CHECK_APP_ID` 一定要给**。
> 不给的话 `integration_id` 会停在占位符 `123456` → 那个"expected source"指向一个不存在的 App →
> 门禁要么永远等、要么接受任何来源的同名 check。

> ★ **脚本会自动判定每个 JSON 是"组织级"还是"仓库级"**
> （看 `conditions` 里有没有 `repository_name`）→ 不用手动指定端点。
> **安装的完整步骤（权限、顺序、验证、回滚）见
> [`git-apps/16-ruleset-install-runbook.md`](../../git-apps/16-ruleset-install-runbook.md)。**

---

## 2.5 ★ 不想用脚本？UI 后台导入 JSON（点鼠标，10 分钟）

> ★ **JSON 文件自己不会生效。** 把它装到 GitHub 上只有三条路，
> **导入的是同一份 JSON，没有区别**：

| 路径 | 怎么做 | 适合谁 | 文档 |
|---|---|---|---|
| **A · UI 导入** | Settings → Rulesets → **New ruleset → Import a ruleset** → 选 JSON → Review → Create | 一次性、手工、小仓库 | 本文 §2.5 ↓ |
| **B · API / 脚本** | `POST /repos/.../rulesets` 或本目录的 `apply-rulesets.sh` | ★ 批量、要幂等、要 CI 化 | Runbook §4 |
| **C · IaC / GitOps** | Terraform / 把 JSON 放仓库里由 CI apply + 漂移检测 | 长期维护 | Runbook §5 / §6 |

### 2.5.1 UI 导入的具体点法

```
# 仓库级（本目录绝大多数 JSON 的落点）
仓库 → Settings → Code, planning, and automation → Rulesets
  → New ruleset（下拉）→ **Import a ruleset**      ★ 导入入口
  → 选 <你的>.json → Review the imported ruleset → Create

# 组织级（只有 org owner 能改；JSON 的 conditions 必须带 repository_name）
头像 → Organizations → 选组织 → Settings
  → Code, planning, and automation → Repository → Rulesets
  → New ruleset（下拉）→ **Import a ruleset** → 选 <你的>.json → Review → Create
```

### 2.5.2 ★ 导入后必须做的 3 个核对（不做 = 可能装了个空壳）

```bash
# ① 规则还在吗？（★ list 接口不返回 rules，必须按 id 查）
gh api repos/<owner>/<repo>/rulesets | jq -r '.[] | "\(.id)\t\(.name)\t\(.enforcement)"'
for id in <上面的 id>; do
  gh api repos/<owner>/<repo>/rulesets/$id | jq -r '"\(.name): rules=\([.rules[]?.type]|join(","))"'
done
#    ★ rules= 为空 → 这条 ruleset 是装饰品，一条都不执行

# ② 目标分支真的命中了吗？（★ 权威口径）
gh api repos/<owner>/<repo>/rules/branches/main | jq -r '.[].type'

# ③ 联调：提一个故意不合规的 PR / push 一个不合规的 commit → 必须被拒
```

> ★★ **UI 导入最坑的一点：GitHub 不报错，但会把不认识的 rule type 静默丢弃。**
> 典型例子：`commit_message_pattern`（Enterprise 专属）、`branch_name_pattern`、
> `merge_queue`、`target: push` 的规则 —— 在个人账号 / Team 组织上导入后
> **rules 变成空数组，但页面仍显示 `active`** → 什么都不拦。
> → 导入前先跑探针确认能力：
> [`examples/rulesets-enterprise/probe-enterprise-capabilities.sh`](../rulesets-enterprise/probe-enterprise-capabilities.sh)

### 2.5.3 导入后建议改的三处

| 位置 | 改成什么 | 为什么 |
|---|---|---|
| **Enforcement status** | 先 `Disabled` → 联调通过再 `Active` | 免得一上来卡住所有人 |
| **`integration_id` / actor id** | 换成真实 ID | JSON 里 `123456`、`42` 都是占位符 |
| **分支范围 / 规则来源** | 覆盖要管的分支；status check 的来源选自己的 App（不是 "Any source"） | 见 Runbook §2、§3.3 |

> 完整 Runbook（权限、安装顺序、报错对照表、回滚）：
> [`git-apps/16-ruleset-install-runbook.md`](../../git-apps/16-ruleset-install-runbook.md)。
> ★ **以 `08-main-ruleset.json` 为例的逐字段解读 + 安装步骤 + 「ruleset 与 webhook 的边界」**：
> [`08-main-ruleset.md`](./08-main-ruleset.md)。

---

## 3. `validate-rulesets.py` 检查什么
```
C1  context == cr-check/config/policy.yaml 的 checkName       （名字不一致 → 全员卡死）
C2  CR Check 的 check 必须带非 0 的 integration_id             （没带 → 同名 check 可伪造）
C3  policy.yaml 的 managedBranches 每条都被 ruleset 覆盖         （没覆盖 → 缺口或死锁）
④   每条受保护分支 ruleset 都要有 pull_request / deletion / non_fast_forward
⑤   覆盖 main 的 ruleset：reviewer ≥ 2、只允许 squash、strict = true
⑥   任何 ruleset 都不得有 bypass_mode = "always"，也不得把 GitHub App 列为 bypass
⑦   push ruleset 必须限制密钥类扩展名
⑧   rule parameters 的字段名必须是官方定义过的（抄错 → GitHub 返回 422）
```

退出码：`0` = 通过；`1` = 有 ERROR（`--strict` 下 WARN 也算失败）。

> ★ **为什么值得在 CI 里跑**：
> Ruleset 配错的默认表现是**静默失效**（GitHub 不报错，只是门禁不生效或全员卡住）。
> 有了这个脚本，改坏 `checkName` / 漏填 `integration_id` / 分支范围写歪，
> **会在 PR 上直接红**，而不是在生产事故里才发现。

接入 CI（示例）：

```yaml
# .github/workflows/checks.yaml
- name: Ruleset 契约检查
  run: python3 examples/rulesets/validate-rulesets.py --strict
```

---

## 4. 下发之后的验收（★ 别跳过）

```bash
# ① 确认 enforcement 是不是 active
gh api repos/<owner>/<repo>/rulesets --jq '.[] | {name, enforcement}'

# ② ★ 联调验证（这一步才证明门禁真的活了）
#    提一个不带 CR 号的 PR  → 必须合不了
#    提一个带合规 CR 号的 PR → 能合

# ③ 确认来源 App 对得上
gh api repos/<owner>/<repo>/rulesets --jq \
  '.[] | select(.name=="prod-branch-gate") | .rules[] | select(.type=="required_status_checks")'
```

**两条容易踩的顺序问题**：

1. **必须先让 CR Check 在目标仓库跑出过一次 check run**，
   再去 ruleset 里选它作为 expected source（官方要求 App "最近提交过一个 check run"）。
2. **App 的权限里要有 `statuses:write`** ——
   否则 UI 里根本选不到我们的 App（详见 doc 14 §4.3）。

---

## 5. ★ 最小示例：commit message 以 `CR123456` 开头

完整方案见 **[`git-apps/15-commit-message-cr-prefix.md`](../../git-apps/15-commit-message-cr-prefix.md)**。
这里只列怎么跑：

```bash
# ① 看三层判定（不连 GitHub）
python3 simulate-commit-gate.py            # 两个例子：正例 / 反例
python3 simulate-commit-gate.py --all      # 5 个例子（含“格式对但 CR 号是假的”）

# ② 试自己的 message
python3 simulate-commit-gate.py "CR123456 release: example-gcp-v0.1.0: github app"

# ③ 装本地 hook（秒级反馈）
mkdir -p .githooks
cp commit-msg-hook.sh .githooks/commit-msg && chmod +x .githooks/commit-msg
git config core.hooksPath .githooks
```

> ★ 模拟器的正则**从 07-*.json 里读出来**，所以改 ruleset 就改模拟器 —— 不会“文档一套、配置另一套”。
> ★ 模拟器会额外模拟 squash merge（`PR 标题 + (#PR号)`），
> 专门用来暴露“commit 都合规、但 PR 标题没带 CR 前缀 → 合并被拒”这个坑。

---

## 6. ★ 个人账号 / 非 Enterprise：规则类型的可用性（实测）

在个人账号（`User`）上实测各 rule type：

| rule type | 结果 |
|---|---|
| `pull_request` / `deletion` / `non_fast_forward` / `required_linear_history` / `required_status_checks` / `required_deployments` | ✅ 可用 |
| `commit_message_pattern` / `branch_name_pattern` / `merge_queue` / push ruleset | ❌ `422 Invalid rule` |

★ **UI 导入时不会报错**，而是**静默丢弃** → ruleset 显示 `active` 但 `rules: []` → 什么都不拦。

**自查（30 秒）**：

```bash
gh api repos/<owner>/<repo>/rulesets | jq -r '.[] | "\(.id)\t\(.name)\t\(.enforcement)"'
for id in <id>; do
  gh api repos/<owner>/<repo>/rulesets/$id | jq -r '"\(.name): rules=\([.rules[]?.type]|join(","))"'
done
gh api repos/<owner>/<repo>/rules/branches/main | jq -r '.[].type'   # 目标分支上实际生效的规则
```

→ 个人账号请走 **CI 路线**（`workflows/cr-prefix-check.yaml` + `required_status_checks`）。
→ ★ 同理，[`08-main-ruleset.json`](./08-main-ruleset.json) 用的 `commit_message_pattern`
也是 **Enterprise 专属** → 非 Enterprise 环境请直接用
[`08-main-ruleset.md`](./08-main-ruleset.md) §5 里的 **Plan B（CI 路线）**。

---

## 7. 关联文档

| 主题 | 文档 |
|---|---|
| ★ **08 逐字段解读 + UI 导入 + ruleset 与 webhook 的边界** | [`08-main-ruleset.md`](./08-main-ruleset.md) |
| ★ **企业版能力矩阵**（哪些 rule type 要什么计划） | [`examples/rulesets-enterprise/00-enterprise-capabilities.md`](../rulesets-enterprise/00-enterprise-capabilities.md) |
| ★ **安装 Runbook**（怎么装、怎么确认生效、怎么回滚） | [`git-apps/16-ruleset-install-runbook.md`](../../git-apps/16-ruleset-install-runbook.md) |
| ★ Ruleset × GitHub App 完整方案 | [`git-apps/14-rulesets-and-gitapp-gate.md`](../../git-apps/14-rulesets-and-gitapp-gate.md) |
| CR Check 的 `policy.yaml`（C1/C3 的"右边"） | [`git-apps/cr-check/config/policy.yaml`](../../git-apps/cr-check/config/policy.yaml) |
| 三层门禁（合并门 / 同步门 / 准入门） | [`git-apps/11-github-app-concepts.md`](../../git-apps/11-github-app-concepts.md) §11.3 |
