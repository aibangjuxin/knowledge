# 企业版落地 Runbook（从"什么都没有"到"全组织生效"）

> **副标题**：企业版的下发和生效要过六关，任何一关没过，**表现都是"看起来装好了"**。
>
> **一句话结论**
> 企业版落地的顺序是：**能力实测 → 契约校验 → 灰度仓库 → disabled 联调 → 分层放开 → 漂移监控**。
> 任何一步跳过，代价都是**全组织一起出问题**，而组织级 ruleset 只有 org owner 能改。

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-tldr) | TL;DR |
| [§1](#1-阶段-0-·-准备（1-天）) | 阶段 0 · 准备（1 天） |
| [§2](#2-阶段-1-·-能力实测（1-小时）) | 阶段 1 · 能力实测（1 小时） |
| [§3](#3-阶段-2-·-契约校验（半天）) | 阶段 2 · 契约校验（半天） |
| [§4](#4-阶段-3-·-灰度仓库（12-天）) | 阶段 3 · 灰度仓库（1–2 天） |
| [§5](#5-阶段-4-·-分层放开) | 阶段 4 · 分层放开（按能力影响面排序） |
| [§6](#6-阶段-5-漂移与治理（长期）) | 阶段 5 · 漂移与治理（长期） |
| [§7](#7-验收清单) | ★ 验收清单（逐条打勾） |
| [§8](#8-熔断与回滚) | ★ 熔断与回滚 |
| [§9](#9-常见报错对照表) | 常见报错对照表 |
| [§10](#10-关联文档) | 关联文档 |

---

## 0. TL;DR

1. **能力实测必须在最前面**：不支持的 rule type 会**静默丢弃**（UI 导入），
   出来一个"active 但 `rules: []`"的空壳 → 什么都不拦，还以为装好了。

2. **组织级 ruleset 只有 org owner 能改** → 熔断权限要**提前**给到值班的人。

3. **永远先 `disabled`**：企业版 `disabled` 的规则依然出现在审计历史里，
   而"先 active 再回滚"的代价是全组织卡死的那几分钟。

4. **先在一个测试仓库上联调**，再分层放开。

5. **放开顺序 = 影响面从小到大**：
   `tag 规范` → `分支名规范` → `commit message 规范` → `push 门禁` → `生产门禁` → `合并队列`。

6. **漂移检测是长期项**，不是可选项：企业版的价值全在"一次配置管全部"，
   有人点一下 UI 就全废了。

---

## 1. 阶段 0 · 准备（1 天）

### 1.1 确认身份与权限

```bash
gh auth status                      # 需要 admin:org scope
gh auth refresh -s admin:org        # ★ 组织级 ruleset 必须
gh auth refresh -s workflow          # 装 CI 兜底时需要

# 确认你在 org 里是不是 owner（决定谁能改组织级 ruleset）
gh api orgs/<org> --jq '.login, .members_count'
```

> ★ **只有 org owner 能改组织级 ruleset。**
> 如果你们平台组不是 owner，就只有两条路：
> ① 把 owner 权限交给平台组（推荐，熔断时救命）
> ② 全部走**仓库级** ruleset（代价：N 个仓库要维护 N 份，失去"一次下发"的价值）

### 1.2 填 `enterprise-profile.yaml`

```yaml
org:
  name: "example-corp"        # ← 换成你们的
  plan: "enterprise"          # ← 改成实际计划
  ghHost: "github.com"        # GHES 改成你们的 host
  repos:
    production: ["platform-*", "core-*"]   # ← 生产仓库的命名模式
    standard:   ["app-*", "svc-*"]
    sandbox:    ["sandbox-*"]
crCheck:
  appId: 123456               # ← CR Check 这个 GitHub App 的 ID
  checkName: "cr/prod-validation"
```

> ★ `appId` 怎么拿：
> `gh api apps/<slug>` → `.id`；或组织设置 → Developer settings → GitHub Apps → CR Check。

### 1.3 准备 CR Check App

```
① App 装到目标仓库（Installation 要覆盖所有生产仓库）
② 权限含 statuses:write（★ 能被选为 expected source 的硬前提）+ checks:write
③ 私钥 / webhook secret 配好，服务在线
```

---

## 2. 阶段 1 · 能力实测（1 小时）

```bash
cd examples/rulesets-enterprise

# ★ 探针（用一个测试仓库；建了即删，不污染其它仓库）
./probe-enterprise-capabilities.sh --probe-repo <测试仓库>
```

**产出**：一张能力表。

**决策**：

| 探针结果 | 下一步 |
|---|---|
| metadata / push 都 ✅ | 走完整流程 |
| metadata ✅、push ❌ | 去掉 `07-org-push-guard.json`，其它照走 |
| metadata ❌ | ★ **别用本目录**，回去走个人版的 CI 路线 |
| merge_queue ❌ | 去掉 `06-org-merge-queue.json` |

> ★ **把探针输出贴进 PR**（`--out capabilities.md`）——
> 让评审的人知道配置是基于实测，而不是基于文档。

---

## 3. 阶段 2 · 契约校验（半天）

```bash
# ① 静态校验（15 条契约）
python3 validate-rulesets.py --strict

# ② 三层判定模拟（不连 GitHub）
python3 simulate-commit-gate.py --all

# ③ 看 payload（不连 GitHub）
./apply-rulesets.sh --dry-run
```

**逐条看懂输出**：

| 断言 | 拦的是什么 |
|---|---|
| E1 计划 | 计划不对 → metadata 规则静默失效 |
| E2 App ID | 门禁没有来源限定 → 同名 check 可伪造 |
| E3/E4 check 名 + integration_id | 全员卡死 / 门禁形同虚设 |
| E5 正则同源 | 服务端与本地 hook 判出两套结果 |
| E6 managedBranches | 某个分支永远等不到 check |
| E7 scope | 组织级 JSON 打到仓库端点 → 作用范围只剩 1 个仓库 |
| E8 分支底线 | 受保护分支能被直推 / 删 / 强推 |
| E9 生产严格度 | 生产分支 reviewer 不够 / 合并方式不唯一 |
| E10 豁免纪律 | 有人能无痕绕过 |
| E11 push 门禁 | 密钥能进仓库 |
| E12 字段白名单 | GitHub 422 |
| E13 命名唯一 | apply 脚本误更新 |
| E14 merge queue | 队列建立不起来 |
| E15 能力匹配 | 用错计划下的能力 |

---

## 4. 阶段 3 · 灰度仓库（1–2 天）

### 4.1 先让 CR Check 跑出一次 check run

> ★ **官方硬要求**：App 必须 "recently submitted a check run"，
> 才能被选为 required status check 的 expected source。
> 顺序反了 → UI 下拉框里**根本看不到**我们的 App → 只能选 "Any source"。

```bash
# 在测试仓库提一个 PR，确认 CR Check 写出了 check run
gh api repos/<org>/<test-repo>/commits/<sha>/check-runs \
  --jq '.check_runs[] | "\(.name)\t\(.conclusion)\t\(.app.id)"'
```

### 4.2 下发（★ disabled）

```bash
cd examples/rulesets-enterprise

./apply-rulesets.sh --apply --owner <org> --enforcement disabled
```

### 4.3 联调（在测试仓库上，逐条验）

```bash
# ① 违规的 commit message → ★ 分支指针不更新（不是"push 被拒"）
git switch -c feature/CR-000001-test
echo x > README.tmp && git add README.tmp
git commit -m "test: 不带 CR 前缀"          # 若装了 hook，这一步就被拦
SKIP_CR_PREFIX=1 git commit -m "test: 不带 CR 前缀"
git push -u origin feature/CR-000001-test
#   期望：push 报错，且 origin/feature/CR-000001-test 没有这个 commit

# ② 合规的 → 能推
git commit --amend -m "CR123456 test: 带 CR 前缀"
git push -u origin feature/CR-000001-test
#   期望：正常推送

# ③ 不合规分支名 → 同样 ref 不更新
git switch -c my-temp-branch && git push -u origin my-temp-branch
#   期望：拒绝

# ④ PR 标题不带前缀 → 合不了（squash 语义）
#   期望：merge 被拒

# ⑤ 合规 PR → 能合
```

### 4.4 打开强制（只开这一条）

```bash
./apply-rulesets.sh --apply --owner <org> --enforcement active --only org-commit-message-convention
```

---

## 5. 阶段 4 · 分层放开

> ★ **顺序 = 影响面从小到大**。每开一条，观察 **1 个工作日**再开下一条。

| # | 打开什么 | 影响面 | 观察什么 |
|---|---|---|---|
| 1 | `04-org-tag-name-convention` | 只有打 tag 的人 | 有没有人打错 tag |
| 2 | `03-org-branch-name-convention` | 所有新建分支的人 | 命名不合规的 push 次数 |
| 3 | `02-org-commit-message-convention` | ★ 所有人 | 开发者是否理解"ref 不更新"（→ 本地 hook 要先装好） |
| 4 | `07-org-push-guard` | 推文件的人 | 机器人/大文件是否被误伤（→ 需要时登记豁免） |
| 5 | `05-org-prod-branch-gate` | ★ 生产仓库 | reviewer 是否够、CR Check 是否稳定 |
| 6 | `06-org-merge-queue` | ★ 生产仓库 | 队列行为、通知、异步合入的适应 |
| 7 | `08-org-required-workflows` | 全组织 | 中央 workflow 的稳定性 |
| 8 | `09-org-code-scanning` | 生产仓库 | 需要 GHAS |

**每开一条之后的检查**：

```bash
# 规则是否真的聚合到目标分支
gh api repos/<org>/<repo>/rules/branches/main \
  | jq -r '.[] | "\(.ruleset_source_type)\t\(.ruleset_source)\t\(.type)"'
```

### 5.1 ★ 开发者体验要一起做

打开 metadata 规则之前，**先**把这两个装了（否则大家会怨声载道）：

```bash
mkdir -p .githooks
cp examples/rulesets-enterprise/commit-msg-hook.sh .githooks/commit-msg
cp examples/rulesets-enterprise/branch-name-hook.sh .githooks/pre-push
chmod +x .githooks/commit-msg .githooks/pre-push
git config core.hooksPath .githooks
```

> ★ 更好的做法：让各仓库的 `.githooks/` 由**中央模板仓库**生成（避免各写各的）。

---

## 6. 阶段 5 · 漂移与治理（长期）

### 6.1 开启漂移检测

```bash
# 在策略仓库里启用 workflows/rulesets-drift.yaml
# 需要 secret: GH_RULESET_TOKEN（repo + admin:org）
# 需要 variable: ORG
```

### 6.2 开启 GitOps 自动下发

```bash
# workflows/rulesets-apply.yaml
# 路径触发：examples/rulesets-enterprise/**
# ★ 触发后默认 disabled —— 打开 active 要人工在 workflow_dispatch 里选
```

### 6.3 定期复核

| 周期 | 做什么 |
|---|---|
| 每天 | 漂移检测（workflow 自动跑） |
| 每月 | 重跑能力探针（★ 计划/版本可能变） |
| 每次 GHES 升级 | ★ 重跑探针 + 重跑联调 |
| 每季度 | 复核豁免名单（`bypassAllowlist`）—— 过期的豁免要删掉 |
| 每半年 | 复核仓库分层（`org.repos`）—— 新仓库进来了没？老仓库下线了没？ |

### 6.4 ★ 纪律

```
① 禁止用 UI 直接改 ruleset（除了应急）
   → UI 改的东西漂移检测会抓到 → 逼着你走 PR
② 应急改完，立刻把改动同步回仓库的 JSON
③ 组织级 ruleset 的改动必须两人评审
```

---

## 7. ★ 验收清单

| # | 检查项 | 通过标准 |
|---|---|---|
| 1 | 能力探针 | 表已生成并贴在 PR 里 |
| 2 | `validate-rulesets.py --strict` | 无 ERROR |
| 3 | `simulate-commit-gate.py --all` | 全部"符合预期" |
| 4 | CR Check 跑出过 check run | `check-runs` 里能看到 `cr/prod-validation` 且 `app.id` 是我们的 App |
| 5 | enforcement | 目标 ruleset = `active` |
| 6 | 聚合生效 | `rules/branches/main` 里能看到 **Organization** 来源的规则 |
| 7 | 来源限定 | PR 上那个 check 的来源是我们的 App（不是 "Any source"） |
| 8 | 违规 commit | push 时 **ref 不更新** |
| 9 | 违规分支名 | 同上 |
| 10 | 违规 PR 标题 | merge 被拒 |
| 11 | 合规 PR | 能合 |
| 12 | 绕过路径 | 直接 push / PAT 强推 → 都被拒 |
| 13 | 豁免可见 | `bypassAllowlist` 里每一条都有 reason，且被审计记录 |
| 14 | 漂移检测 | 人为在 UI 改一条 → 下一次跑必须报红 |
| 15 | 熔断演练 | ★ 演练一次"改成 disabled"并恢复（**没演练过的熔断 = 出事时不会用**） |
| 16 | 审计 | `rulesets/<id>/history` 能看到变更记录 |

---

## 8. ★ 熔断与回滚

### 8.1 熔断动作

| 场景 | 动作 | 命令 |
|---|---|---|
| 门禁误伤 | 改 `disabled`（★ 不要删） | `./apply-rulesets.sh --apply --enforcement disabled --only <name>` |
| 某条规则本身有问题 | 只禁用那一条 | 同上 + `--only` |
| CR Check 服务挂了 | 禁用依赖它的 `05`/`06` | 同上（**限时**，见下） |
| 紧急变更 | 用 `bypass_actors` 里登记过的团队 | PR 里直接合 |
| 要彻底移除 | 删除 | `./apply-rulesets.sh --delete <name>` |

### 8.2 熔断纪律

```
触发条件  ：CR Check 不可用 > 15 分钟 / CR 平台故障导致全员误拦 / 规则误伤生产
执行人    ：★ 值班 SRE（提前指定，不能是"谁有空谁上"）
执行方式  ：enforcement → disabled（不要删规则）
时限      ：≤ 2 小时内必须恢复或升级
审计      ：ruleset 版本历史留下变更记录；事后补一条变更说明
```

> ⚠️ **不要把"App 挂了自动放行"做成自动化**。
> 那等于给门禁留了一个后门 —— 让 App 挂掉就能绕过。
> 熔断必须是**人工、有时限、有审计**的动作。

### 8.3 ★ 组织级权限的应急准备

```
组织级 ruleset 只有 org owner 能改 →
① 提前把 owner 权限（或一个能改 ruleset 的组织角色）给到值班 SRE
② 把熔断命令写进 oncall runbook（一条命令，别让人现想）
③ 每季度演练一次
```

---

## 9. 常见报错对照表

| 现象 / 报错 | 根因 | 解法 |
|---|---|---|
| `404` 打 `orgs/<org>/rulesets` | org 名错 / token 没 admin:org | `gh auth refresh -s admin:org` |
| `403` | 不是 org owner | 找 owner，或降级为仓库级 ruleset |
| `422 Invalid rule 'xxx'` | 该 rule type 你们的计划/版本不支持 | ★ 跑探针确认；不支持就别写 |
| `422 Invalid property /rules/N` | `pull_request.parameters` 字段不全 | 校验器 E12 会查 |
| **UI 导入不报错但 `rules: []`** | 不认识的 rule type 被**静默丢弃** | ★ 改用 API 下发 + 跑校验器 |
| 合不了但看不出原因 | 缺 `integration_id` → 等一个不存在的 check | 检查 C1/E3/E4 |
| **push "成功"了但分支没动** | metadata 规则的正常语义 | 改 message 后 `--amend` 重推 |
| 合规 commit 也合不了 | **PR 标题**没带 CR 前缀（squash 语义） | 改 PR 标题 |
| 规则配了但没生效 | 分支不在 `ref_name.include` | `gh api repos/../rules/branches/<分支>` 看聚合 |
| 老仓库没被管 | `repository_name` 模式没匹配上（`*` 不跨 `/`） | 改模式（如 `platform-*`） |
| 机器人提交被拦 | Dependabot 之类 | 在 `bypassAllowlist` 登记 |
| CI apply 成功但线上没变 | 改的是仓库级、发到组织级（或反之） | `--list` 对比两端点 |
| 漂移检测一直报红 | 有人在 UI 改过 | 人工判断：同步回 JSON 还是改回去 |
| merge queue 行为变怪 | 队列开启后合入变成异步 | 观察期放在最后，先教会团队 |

---

## 10. 关联文档

| 主题 | 文档 |
|---|---|
| ★ 差异对照 | [`personal-vs-enterprise.md`](./personal-vs-enterprise.md) |
| ★ 能力矩阵 | [`00-enterprise-capabilities.md`](./00-enterprise-capabilities.md) |
| 本目录说明 | [`README.md`](./README.md) |
| 通用安装 Runbook | [`git-apps/16-ruleset-install-runbook.md`](../../git-apps/16-ruleset-install-runbook.md) |
| Ruleset × GitHub App 方案 | [`git-apps/14-rulesets-and-gitapp-gate.md`](../../git-apps/14-rulesets-and-gitapp-gate.md) |
