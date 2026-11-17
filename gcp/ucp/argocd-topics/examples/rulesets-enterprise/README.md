# examples/rulesets-enterprise/ · GitHub Enterprise 版的规则集（组织级治理）

> 这个目录是 [`examples/rulesets/`](../rulesets/) 的**企业版对应物**。
> 个人版管的是"**一个仓库别把自己锁死**"，企业版管的是"**一次配置，全组织一起生效**"。
>
> ★ **一句话结论**
> 企业版真正多出来的不是"更严的规则"，而是三件事：
> **① 组织级 ruleset（改一次管所有仓库）→ ② metadata 规则（格式门禁从 CI 挪到服务端 push 时刻）→ ③ push ruleset（密钥/大文件/凭据在进仓库之前就被挡）**。
> 代价是：**配错一次 = 全组织一起卡死，而且组织级 ruleset 只有 org owner 能改**。

---

## 1. 一眼看懂：个人版 vs 企业版

| | 个人版 [`examples/rulesets/`](../rulesets/) | 企业版（本目录） |
|---|---|---|
| **治理面** | 仓库级为主（逐仓库下发） | ★ **组织级为主**（一次下发，全部仓库） |
| **格式门禁** | CI check（`cr-prefix`） | ★ **metadata 规则**（`commit_message_pattern`）——服务端、push 时刻生效 |
| **分支名 / tag 名** | ❌ 没有（非 Enterprise API 直接 422） | ★ `branch_name_pattern` / `tag_name_pattern` |
| **push 门禁** | ❌ 用不了（个人版的 `05-push-secrets.json` 在个人账号上是装饰品） | ★ `target: push` ruleset（密钥扩展名 / 受限路径 / 大小 / 凭据） |
| **合并队列** | ❌ | ★ `merge_queue`（私有仓库） |
| **签名提交** | ❌ | ★ `required_signatures` |
| **组织级 CI 定义** | ❌ | ★ `required_workflows` |
| **代码扫描门禁** | ❌ | ★ `code_scanning` ruleset（需 GHAS） |
| **配置一致性** | C1/C2/C3 三条契约 | ★ E1–E15 十五条契约（多了能力/一致性/治理三类） |
| **下发脚本** | 单仓库 | ★ 组织级 + 按分层批量仓库 |
| **漂移检测** | runbook 里给了模板 | ★ 落地成 workflow（每天跑） |

完整对照（**含"这条能力值不值"和部署动作**）→ [`personal-vs-enterprise.md`](./personal-vs-enterprise.md)

---

## 2. 文件清单

| 文件 | 是什么 | 下发到哪 |
|---|---|---|
| [**`enterprise-profile.yaml`**](./enterprise-profile.yaml) | ★ **唯一真相源**：org 名、计划、仓库分层、CR Check App ID、三个规范正则、严格度、豁免名单 | —— （被所有脚本读取） |
| [`01-org-baseline.json`](./01-org-baseline.json) | 组织级基线：所有仓库的默认分支 → 走 PR、1 reviewer、禁删禁强推 | `orgs/<org>/rulesets` |
| [`02-org-commit-message-convention.json`](./02-org-commit-message-convention.json) | ★ **Enterprise 专属**：commit subject 必须 `^CR[0-9]{6}(\s|$)` | 同上 |
| [`03-org-branch-name-convention.json`](./03-org-branch-name-convention.json) | ★ **Enterprise 专属**：分支名必须 `feature\|fix\|hotfix\|git-apps\|codex/<名字>` | 同上 |
| [`04-org-tag-name-convention.json`](./04-org-tag-name-convention.json) | ★ **Enterprise 专属**：tag 必须 `v<major>.<minor>.<patch>` | 同上 |
| [`05-org-prod-branch-gate.json`](./05-org-prod-branch-gate.json) | ★ **核心**：生产仓库的 `main`/`release/prod` → 2 reviewer + code owner + `cr/prod-validation`（限定来源 App）+ 签名 + 仅 squash | 同上 |
| [`06-org-merge-queue.json`](./06-org-merge-queue.json) | ★ 合并队列（私有仓库需 Enterprise）—— 先 `disabled` 联调 | 同上 |
| [`07-org-push-guard.json`](./07-org-push-guard.json) | ★ **Enterprise 专属**：禁密钥扩展名、禁改 `releases/**`、禁 >10MB、扫凭据 | 同上（`target: push`） |
| [`08-org-required-workflows.json`](./08-org-required-workflows.json) | ★ 组织级强制 CI 定义（Enterprise Cloud）—— 先 `disabled` | 同上 |
| [`09-org-code-scanning.json`](./09-org-code-scanning.json) | 代码扫描门禁（需 GHAS）—— 先 `disabled` | 同上 |
| [`10-repo-dev-branches.json`](./10-repo-dev-branches.json) | `dev` 集成分支 → 1 reviewer + CI check + squash | `repos/<owner>/<repo>/rulesets` |
| [`11-repo-release-branches.json`](./11-repo-release-branches.json) | `release/**` → 2 reviewer + linear history + squash + strict | 同上 |
| [`12-repo-feature-conventions.json`](./12-repo-feature-conventions.json) | 功能分支保护（PR 必需，0 reviewer） | 同上 |
| [`13-repo-tag-release.json`](./13-repo-tag-release.json) | 仓库级 tag 规范（组织级没覆盖到的仓库用） | 同上 |
| [`validate-rulesets.py`](./validate-rulesets.py) | ★ **E1–E15 契约检查**（能力 / 一致性 / 治理） | —— |
| [`apply-rulesets.sh`](./apply-rulesets.sh) | ★ 下发：组织级 + 按分层批量仓库；幂等；自动覆盖 `integration_id` | —— |
| [`probe-enterprise-capabilities.sh`](./probe-enterprise-capabilities.sh) | ★ **实测**：你们的 org 到底支持哪些 rule type（建了即删，不污染） | —— |
| [`simulate-commit-gate.py`](./simulate-commit-gate.py) | ★ 三层判定模拟（commit / 分支名 / tag 名 + squash 语义） | —— |
| [`commit-msg-hook.sh`](./commit-msg-hook.sh) | L1 本地 commit-msg hook（正则与 ruleset 同源） | 装到 `.githooks/commit-msg` |
| [`branch-name-hook.sh`](./branch-name-hook.sh) | L1 本地 pre-push 分支名 hook（★ 企业版专属体验补丁） | 装到 `.githooks/pre-push` |
| [`install-ci-check.sh`](./install-ci-check.sh) | 可选：把 CI 兜底批量装进各仓库 | —— |
| [`workflows/rulesets-apply.yaml`](./workflows/rulesets-apply.yaml) | ★ GitOps：合并后自动下发（组织级需 `admin:org`） | —— |
| [`workflows/rulesets-drift.yaml`](./workflows/rulesets-drift.yaml) | ★ 漂移检测：有人改了 UI 就报警 | —— |
| [`workflows/cr-prefix-check.yaml`](./workflows/cr-prefix-check.yaml) | 可选：CI 兜底（把"ref 不更新"变成"PR 上一个红叉"） | —— |
| [`00-enterprise-capabilities.md`](./00-enterprise-capabilities.md) | ★ 能力矩阵：哪些 rule type 要什么计划 / GHES 版本 | —— |
| [`personal-vs-enterprise.md`](./personal-vs-enterprise.md) | ★★ **差异对照**：差距是什么、值不值、怎么部署 | —— |
| [`enterprise-rollout.md`](./enterprise-rollout.md) | ★ 分阶段落地 + 验收清单 + 熔断纪律 | —— |

---

## 3. 60 秒跑起来（不连 GitHub）

```bash
cd examples/rulesets-enterprise

# ① 静态检查：15 条契约（模板状态下用 --allow-placeholders）
python3 validate-rulesets.py --allow-placeholders

# ② 三层判定模拟：commit / 分支名 / tag 名 / squash 语义
python3 simulate-commit-gate.py --all

# ③ 看将要提交给 GitHub 的 payload（不连 GitHub）
./apply-rulesets.sh --dry-run
```

> ★ **先改 `enterprise-profile.yaml`**：
> `org.name` · `org.plan` · `org.repos`（仓库分层）· `crCheck.appId`（CR Check 的 App ID）。
> 不改就下发 = `org.name` 指向一个不存在的组织 → 404。

---

## 4. 部署顺序（六步）——★ 别颠倒

```
① 装 CR Check App      → 装到目标仓库；权限含 statuses:write + checks:write
② App 先跑出一次 check → 官方硬要求：没跑过 check run，UI 里选不到它当来源
③ 实测能力             → ./probe-enterprise-capabilities.sh --probe-repo <测试仓库>
④ 建 ruleset           → enforcement = disabled（先建不生效）
⑤ 联调                 → 不合规的必须拦得住，合规的必须放行
⑥ 打开强制             → enforcement = active
```

**为什么 ② 必须在 ④ 之前**
官方要求：App 必须 "recently submitted a check run" 才能被选为 expected source。
顺序反了 → 下拉框里**根本看不到**我们的 App → 只能选 "Any source" → 门禁形同虚设。

**为什么 ③ 不能省**
`commit_message_pattern` / `push` ruleset / `merge_queue` 这些能力，
**取决于你们的计划与（GHES 的）版本**。不实测就下发 → API 422，
或者更糟：**UI 导入静默丢弃 → ruleset 显示 active 但 `rules: []` → 什么都不拦**。

完整清单 → [`enterprise-rollout.md`](./enterprise-rollout.md)

---

## 5. 验收（★ 别跳过）

```bash
# ① 配置在不在
./apply-rulesets.sh --list

# ② ★ 聚合后真的生效了吗（权威口径）
gh api repos/<org>/<repo>/rules/branches/main \
  | jq -r '.[] | "\(.ruleset_source_type)\t\(.ruleset_source)\t\(.type)"'
#   期望：Organization（组织级）+ Repository（仓库级）两种来源都列出来了

# ③ ★ 联调（唯一能证明"拦得住"的方法）
#    · push 一个不带 CR 号的 commit → ★ 分支指针不更新（不是"push 被拒"）
#    · PR 标题不带 CR 前缀 → 合不了
#    · 分支名不合规 → 同上
#    · 合规的 → 全过
```

---

## 6. 熔断（写进 oncall runbook）

| 场景 | 动作 | 注意 |
|---|---|---|
| 门禁误伤（最常见） | `enforcement: disabled` | ★ **不要删规则**（删了就没审计痕迹了） |
| CR Check 服务挂了 | 禁用 `05`/`06` 里依赖它的部分 | ★ **不要把 App 做成自动放行** —— 那等于留后门 |
| 配错了 | 禁用 → 改 JSON → 走 PR → 重新 apply | —— |
| 紧急变更 | 用 `bypass_actors` 里显式列出的团队 | 必须在 `enterprise-profile.yaml` 的 `bypassAllowlist` 里登记 |

> ★ **组织级 ruleset 只有 org owner 能改** —— 这意味着：
> 熔断权限必须**提前**给到值班的人，别等出事再申请。

---

## 7. 关联文档

| 主题 | 文档 |
|---|---|
| ★★ **个人版 ↔ 企业版差异对照** | [`personal-vs-enterprise.md`](./personal-vs-enterprise.md) |
| ★ 能力矩阵（计划 / GHES 版本） | [`00-enterprise-capabilities.md`](./00-enterprise-capabilities.md) |
| ★ 分阶段落地 + 验收 + 熔断 | [`enterprise-rollout.md`](./enterprise-rollout.md) |
| ★ 个人版目录（对照基准） | [`examples/rulesets/`](../rulesets/) |
| Ruleset × GitHub App 完整方案 | [`git-apps/14-rulesets-and-gitapp-gate.md`](../../git-apps/14-rulesets-and-gitapp-gate.md) |
| commit message 规范原理 | [`git-apps/15-commit-message-cr-prefix.md`](../../git-apps/15-commit-message-cr-prefix.md) |
| 安装 Runbook（通用） | [`git-apps/16-ruleset-install-runbook.md`](../../git-apps/16-ruleset-install-runbook.md) |
| CR Check 的 `policy.yaml`（C1/E3 的"右边"） | [`git-apps/cr-check/config/policy.yaml`](../../git-apps/cr-check/config/policy.yaml) |
