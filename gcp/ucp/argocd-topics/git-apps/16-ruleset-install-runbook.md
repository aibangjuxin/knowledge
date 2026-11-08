# 16 · Ruleset 安装与生效 Runbook（从 JSON 到"真的拦住 merge"）

> **副标题**：JSON 文件本身不会生效。这篇讲**怎么把它装上去、怎么确认生效、怎么回滚**。
>
> **一句话结论**
> **装 ruleset = 一次 API 写入（`POST` / `PUT`），但"生效"要过三关：**
> **① App 先跑出过一次 check run（否则选不到它当来源）→ ② ruleset 的 `enforcement` 必须是 `active` → ③ 联调证明它真的拦得住。**
> 三关都过了，门禁才算装好。只做第 1 步 = 什么都没装。

> **前置阅读**
> [`14-rulesets-and-gitapp-gate.md`](./14-rulesets-and-gitapp-gate.md)（Ruleset 概念 + 与 App 的耦合）、
> [`15-commit-message-cr-prefix.md`](./15-commit-message-cr-prefix.md)（最小示例）、
> [`examples/rulesets/`](../examples/rulesets/)（配置与脚本）。

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-tldr) | TL;DR：7 条结论 |
| [§1](#1-先分清两种装（组织级-vs-仓库级）) | 先分清两种"装"：组织级 vs 仓库级 |
| [§2](#2-★-安装顺序（六步）与每一步的验收) | ★ **安装顺序（6 步）** 与每一步的验收 |
| [§3](#3-路径-a-·-ui-导入-json（点鼠标，10-分钟）) | 路径 A · UI 导入 JSON |
| [§4](#4-路径-b-·-gh-api--一键脚本（★-推荐）) | 路径 B · `gh api` / 一键脚本（★ 推荐） |
| [§5](#5-路径-c-·-iac（声明式）) | 路径 C · IaC（Terraform/local-exec） |
| [§6](#6-路径-d-·-gitops（配置进仓库--ci-apply）★-最贴合你们) | 路径 D · GitOps（配置进仓库 + CI apply + 漂移检测） |
| [§7](#7-★-怎么确认真的生效了) | ★ **怎么确认"真的生效了"**（配置 + 聚合 + 联调） |
| [§8](#8-回滚与熔断) | 回滚与熔断 |
| [§9](#9-权限与-token) | 权限与 token |
| [§10](#10-安装失败的报错对照表) | 安装失败的报错对照表 |
| [§11](#11-关联文档) | 关联文档 |

---

## 0. TL;DR

1. **JSON → GitHub 只有两条路**：**UI 的 "Import a ruleset"**（点鼠标）或
   **`POST /repos/{owner}/{repo}/rulesets` / `POST /orgs/{org}/rulesets`**（脚本）。
   两者都是"导入同一份 JSON"，没有区别。

2. **★ 组织级和仓库级是两种不同的东西**，连 API 端点都不一样：
   组织级 → `orgs/{org}/rulesets`（conditions 必须同时含 `repository_name` + `ref_name`），
   仓库级 → `repos/{owner}/{repo}/rulesets`（conditions 只有 `ref_name`）。
   **用错端点 = 404**。

3. **★ 安装顺序不能颠倒**：必须先让 **CR Check App 在目标仓库跑出过一次 check run**，
   再去 ruleset 里选它当 "expected source"（官方硬性要求：`must have recently submitted a check run`）。
   顺序反了 → 下拉框里**根本看不到**我们的 App。

4. **★ `PUT` 是全量替换，不是增量更新。**
   `gh api -X PUT .../rulesets/{id} -f enforcement=active` 会把**所有规则清空**（只留下 enforcement）。
   正确做法：**取回完整 JSON → 改一个字段 → 整体 PUT 回去**（我们的脚本就是这么做的）。

5. **★ "装好了"不等于"生效了"。** 生效要同时满足：
   `enforcement=active` + 目标分支命中 `conditions.ref_name` + 目标仓库命中 `repository_name`。
   权威检查：`gh api repos/{o}/{r}/rules/branches/main`（看**聚合后实际生效**的规则）。

6. **唯一的真验证是联调**：提一个**故意不合规**的 PR，确认合不了。
   任何配置层面的检查都替代不了这一步。

7. **★ 回滚优先用 `disabled` 而不是删除**：规则留着、只是不执行，
   审计记录（`/history`）还在；删了就没痕迹了。

---

## 1. 先分清两种"装"（组织级 vs 仓库级）

| 维度 | **组织级 ruleset** | **仓库级 ruleset** |
|---|---|---|
| UI 位置 | Org → Settings → Repository → Rulesets | Repo → Settings → Code, planning, and automation → Rulesets |
| API 端点 | `POST/PUT /orgs/{org}/rulesets` | `POST/PUT /repos/{owner}/{repo}/rulesets` |
| JSON 的 `conditions` | **必须同时**有 `repository_name` + `ref_name` | **只有** `ref_name` |
| 作用范围 | 一组仓库（`~ALL` / 名单 / 名称模式 / 自定义属性过滤） | 单个仓库 |
| 谁能改 | ★ **只有 org owner** | repo admin，或有 "edit repository rules" 权限的角色 |
| 叠加关系 | 仓库级 ruleset 只能**加严**、不能放松（官方明确） | 同左 |
| 我们的哪几份 | `01-org-baseline`、`07-`、`08-`（含 `repository_name`） | `02`–`06` |

> ★ **本目录的 JSON 是按"scope 由 `conditions` 里有没有 `repository_name` 自动判定"的**：
> `apply-rulesets.sh` 会逐个文件判断该打到哪个端点，**不需要你手动指定**。
> （★ 早期版本有个坑：所有文件都打到同一个端点 → 组织级文件会 404。现在已修。）

---

## 2. ★ 安装顺序（六步）与每一步的验收

```
① 准备 App          ──▶ App 装到目标仓库；权限含 statuses:write + checks:write；
                       私钥/webhook secret 配好；服务在线
② App 先跑一次      ──▶ 在测试仓库提一个 PR，让 CR Check 写出第一个 check run
                       ★ 官方要求：App 必须 "recently submitted a check run"
                         才能被选为 expected source
③ 建 ruleset        ──▶ enforcement = disabled（先建不生效）
④ 联调              ──▶ 不合规 PR 合不了 / 合规 PR 能合 / PR 标题不带前缀合不了
⑤ 打开强制          ──▶ enforcement = active
⑥ 观察              ──▶ 看 bypass 记录、unreachable commit、规则命中情况
```

### 为什么不能颠倒 ② 和 ③

官方原文（Required status checks → 选 expected source 时）：

> *The app must be installed in the repository with the `statuses:write` permission,
> **must have recently submitted a check run**, and must be associated with a pre-existing required status check in the ruleset.*

翻译成操作：

```
没跑过 check run  →  UI 的 "expected source" 下拉框里**选不到**我们的 App
                  →  只能选 "Any source" → 等于放弃了 C2 契约（同名 check 可伪造）
```

### 每步的验收命令

```bash
# ② App 跑过 check run 了吗
gh api repos/<org>/<repo>/commits/<sha>/check-runs \
  --jq '.check_runs[] | "\(.name)\t\(.conclusion)\t\(.app.id)"'

# ⑥ 看 ruleset 有没有被绕过（★ 审计）
gh api repos/<org>/<repo>/rulesets/<id>/history --jq '.[] | "\(.created_at)\t\(.actor)\t\(.version)"'
```

---

## 3. 路径 A · UI 导入 JSON（点鼠标，10 分钟）

### 3.1 组织级

```
右上角头像 → Organizations → 选组织
  → Settings（看不到就是权限不够）
  → 侧栏：Code, planning, and automation → Repository → Rulesets
  → New ruleset（下拉）→ Import a ruleset        ★ 导入入口
  → 选 07-commit-message-cr-prefix-protected.json
  → Review the imported ruleset → Create
```

### 3.2 仓库级

```
仓库 → Settings → Code, planning, and automation → Rulesets → Rulesets
  → New ruleset（下拉）→ Import a ruleset
  → 选 04-repo-prod-branches.json
  → Review → Create
```

### 3.3 导入后要改的三处

| 位置 | 改成什么 | 为什么 |
|---|---|---|
| **Enforcement status** | 先 `Disabled`，联调通过再 `Active` | 避免一上来就卡所有人 |
| **`required_status_checks` 的来源** | 选我们的 App（**不是** "Any source"） | C2 契约；下拉里能看到 = 第 ② 步做过了 |
| **`integration_id` / Team / actor id** | 换成你们真实的 ID（JSON 里是占位符） | `123456`、`42` 都是示例值 |

### 3.4 其它 UI 操作

| 操作 | 路径 |
|---|---|
| 编辑 | 点 ruleset 名字 → 改 → 底部 **Save changes** |
| **临时禁用**（推荐回滚方式） | 同上 → Enforcement status → `Disabled` |
| 删除 | 点 ruleset 名字 → 右侧 `...` → **Delete ruleset** |
| 看谁被规则管着 | 任意有 read 权限的人都能在仓库的 Rulesets 页面看到 active ruleset |
| 看规则命中统计（Enterprise） | Org → Settings → Repository → **Dashboard**（Rule insights） |

---

## 4. 路径 B · `gh api` / 一键脚本（★ 推荐）

### 4.1 准备

```bash
gh auth login
gh auth refresh -s admin:org      # ★ 组织级 ruleset 需要（仓库级不需要）
gh auth status
```

### 4.2 一键安装（本仓库脚本）

```bash
cd examples/rulesets

# ① 先看现状
./apply-rulesets.sh --list --owner <org> --repo <repo>

# ② 静态校验 + 看 payload（不连 GitHub）
CR_CHECK_APP_ID=<App ID> ./apply-rulesets.sh --dry-run --owner <org> --repo <repo>

# ③ 安装（★ 先 disabled）
CR_CHECK_APP_ID=<App ID> ./apply-rulesets.sh --owner <org> --repo <repo> \
    --enforcement disabled

# ④ 联调通过后，打开强制（只动这一条）
CR_CHECK_APP_ID=<App ID> ./apply-rulesets.sh --owner <org> --repo <repo> \
    --enforcement active --only prod-branch-gate

# ⑤ 回滚
./apply-rulesets.sh --delete prod-branch-gate --owner <org> --repo <repo>
```

脚本做三件关键事：

```
① 逐文件判定 scope（org / repo）→ 打对端点
② 同名已存在 → PUT 更新；不存在 → POST 创建（幂等，可反复跑）
③ ★ PUT 用的是「源 JSON 重建的完整 payload」→ 不会因为只传一个字段
   就把其它规则全清空（见 §4.4）
```

### 4.3 手动 `gh api`（不用脚本时）

```bash
# 创建仓库级
gh api -X POST repos/<org>/<repo>/rulesets \
  --input 04-repo-prod-branches.json

# 创建组织级
gh api -X POST orgs/<org>/rulesets \
  --input 07-commit-message-cr-prefix-protected.json

# 查 id
gh api repos/<org>/<repo>/rulesets \
  --jq '.[] | "\(.id)\t\(.name)\t\(.enforcement)"'
```

### 4.4 ★★ 只切 enforcement 的正确姿势（别用 `-f`）

```bash
# ❌ 错：PUT 是全量替换，这条命令会把规则清空，只剩 enforcement
gh api -X PUT repos/<org>/<repo>/rulesets/<id> -f enforcement=active

# ✅ 对：取回完整 JSON → 改一个字段 → 整体 PUT 回去
gh api repos/<org>/<repo>/rulesets/<id> > /tmp/rs.json
jq '.enforcement = "active"' /tmp/rs.json \
  | gh api -X PUT repos/<org>/<repo>/rulesets/<id> --input -
```

> ★ 这是最容易造成生产事故的 API 细节：
> `PUT` 语义 = **替换整个 ruleset**。
> 我们的 `apply-rulesets.sh --enforcement` 就是从源 JSON 重建完整 payload 再 PUT，天然规避了这个问题。

---

## 5. 路径 C · IaC（声明式）

### 5.1 现状：没有一等公民的 ruleset 资源

> ★ 已核对（2026-11）：`hashicorp/github` provider 的资源列表里**没有** ruleset 资源
> （provider 仓库全文检索无 `ruleset` 条目；Terraform Registry 上也没有对应资源页）。
> → **不要指望 `resource "github_ruleset" { ... }` 能用。**

### 5.2 可行做法：`local-exec` + `gh api`

```hcl
terraform {
  required_providers {
    local = { source = "hashicorp/local", version = "~> 2.5" }
  }
}

variable "ruleset_json" { type = string }

resource "local_file" "ruleset" {
  filename        = "${path.module}/ruleset.json"
  content         = var.ruleset_json
  file_permission = "0644"
}

# ★ 真正的写入还是 API —— Terraform 只负责"把 JSON 生成出来 + 触发写入"
resource "local-exec" "apply" {
  command = "cd ${path.module} && ./apply-rulesets.sh --owner ${var.org} --repo ${var.repo}"
  # ★ 幂等性由脚本保证（同名 → PUT）
}
```

### 5.3 更实际的做法

> ★ **推荐**：别硬套 Terraform。
> **Ruleset 的本质是"一条安全策略声明"，用 GitOps 管更顺**（下一节）：
> JSON 进仓库 → PR 评审 → CI apply → 定时漂移检测。
> 这套流程你们已经有（Argo CD / GitHub Actions），不用为 ruleset 单独引入一套 IaC。

---

## 6. 路径 D · GitOps（配置进仓库 + CI apply）★ 最贴合你们

### 6.1 目录结构

```
platform-repo/
├── .github/
│   ├── rulesets/                      # ★ 声明式真相源
│   │   ├── 01-org-baseline.json
│   │   ├── 04-repo-prod-branches.json
│   │   └── ...
│   └── workflows/
│       ├── rulesets-apply.yaml        # 合并后自动 apply
│       └── rulesets-drift.yaml        # 定时漂移检测
```

### 6.2 合并后自动 apply

```yaml
# .github/workflows/rulesets-apply.yaml
name: rulesets-apply
on:
  push:
    paths: ['.github/rulesets/**']
  workflow_dispatch:
permissions:
  contents: read
  administration: write        # ★ 改 ruleset 需要
jobs:
  apply:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.11' }
      - name: 静态校验（契约 C1/C2/C3）
        run: python3 examples/rulesets/validate-rulesets.py --strict
      - name: 下发
        env:
          GH_TOKEN: ${{ secrets.GH_RULESET_TOKEN }}
          CR_CHECK_APP_ID: ${{ secrets.CR_CHECK_APP_ID }}
          ORG: ${{ vars.GITHUB_ORG }}
          REPO: ${{ vars.GITHUB_REPO }}
        run: |
          cd examples/rulesets
          ./apply-rulesets.sh --owner "$ORG" --repo "$REPO" --enforcement active
```

### 6.3 ★ 漂移检测（GitOps 的灵魂）

**别人在 UI 上改了 ruleset → 仓库里的 JSON 和线上就不一致了。**
CI 必须能发现这件事，否则"声明式"只是装饰。

```yaml
# .github/workflows/rulesets-drift.yaml
name: rulesets-drift
on:
  schedule: [{ cron: '17 3 * * *' }]     # 每天凌晨
  workflow_dispatch:
jobs:
  drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: 比对线上 vs 仓库里的 JSON
        env:
          GH_TOKEN: ${{ secrets.GH_RULESET_TOKEN }}
        run: |
          cd examples/rulesets
          for f in [0-9][0-9]-*.json; do
            name=$(jq -r .name "$f")
            live=$(gh api "repos/$ORG/$REPO/rulesets" --jq ".[]|select(.name==\"$name\")" || echo "")
            [ -z "$live" ] && { echo "❌ $name 线上不存在（被删了？）"; exit 1; }
            # 逐字段比对（enforcement / rules / conditions）
            diff <(jq -S '{enforcement,rules,conditions,bypass_actors}' "$f") \
                 <(echo "$live" | jq -S '{enforcement,rules,conditions,bypass_actors}') \
              || { echo "❌ $name 与线上不一致 —— 有人在 UI 上改过，或该用 PR 改"; exit 1; }
          done
          echo "✅ 无漂移"
```

### 6.4 GitOps 管 ruleset 的额外好处

| 好处 | 说明 |
|---|---|
| **改规则 = 提 PR** | 有评审、有审计、有回滚（`git revert`） |
| **和 App 配置同源** | `policy.yaml` 和 ruleset JSON 在同一个 PR 里改 → C1/C2/C3 契约不会漂 |
| **CI 门禁** | `validate-rulesets.py` 在 PR 上就能拦"你把 checkName 改坏了" |
| **审计** | 变更历史在 Git 里，比 UI 里的版本历史更好查 |

> ★ **一条纪律**：**禁止用 UI 直接改 ruleset**（除了应急）。
> UI 改的东西 CI 会检测到漂移并报错 → 逼着你走 PR。
> 应急改完，**立刻**把改动同步回仓库的 JSON。

---

## 7. ★ 怎么确认"真的生效了"

### 7.1 三层验证（缺一不可）

```bash
# ── 第 1 层：配置在不在
./apply-rulesets.sh --list --owner <org> --repo <repo>
#    期望：看到 ruleset 名 + enforcement=active

# ── 第 2 层：规则聚不聚合到目标分支（★ 最权威）
gh api repos/<org>/<repo>/rules/branches/main | jq -r '.[] |
  "\(.ruleset_source_type)\t\(.ruleset_source)\t#\(.ruleset_id)\t\(.type)"'
#    期望：能看到 Repository / Organization 两种来源的规则都列出来了

# ── 第 3 层：联调（★ 唯一能证明"拦得住"的）
```

### 7.2 第 3 层：联调脚本（照着做一遍）

```bash
# ① 建一个不合规的分支
git checkout -b feature/CAEP-0001-verify-ruleset
echo x > README.tmp && git add README.tmp
git commit -m "test: 不带 CR 前缀"        # 若装了 hook，这里就会被拦
git push -u origin feature/CAEP-0001-verify-ruleset
#   期望：push 被拒（ref 不更新）

# ② 改成合规的再推
git commit --amend -m "CR123456 test: 带 CR 前缀"
git push -u origin feature/CAEP-0001-verify-ruleset
#   期望：正常推送

# ③ 开 PR，标题故意不带前缀
#   期望：★ merge 被拒（squash 后的 commit message 不合规）
# ④ 改标题为 "CR123456 test: 带 CR 前缀"
#   期望：合入
```

### 7.3 验收清单

| # | 检查项 | 通过标准 |
|---|---|---|
| 1 | `enforcement` | `active`（不是 `disabled`） |
| 2 | 目标分支命中 | `rules/branches/main` 里能看到我们的 rule |
| 3 | 目标仓库命中 | 组织的 `repository_name` 模式匹配到我们的仓库 |
| 4 | 来源限定 | PR 上那个 check 显示的来源是我们的 App（不是 "Any source"） |
| 5 | 不合规 PR | 合不了，且报错信息能看懂 |
| 6 | 合规 PR | 能合 |
| 7 | 绕过路径 | 直接 push / 用 PAT 强推 → 都被拒 |
| 8 | 审计 | `rulesets/<id>/history` 能看到变更记录 |

---

## 8. 回滚与熔断

| 场景 | 动作 | 命令 / 路径 | 恢复 |
|---|---|---|---|
| **门禁误伤（最常见）** | 临时禁用 | `enforcement: disabled`（脚本 `--enforcement disabled`） | 修好后改回 `active` |
| 规则配错了 | 禁用 → 改 JSON → 走 PR → 重新 apply | —— | —— |
| 要彻底移除 | 删除 | `./apply-rulesets.sh --delete <name>` 或 UI `... → Delete` | 重新 apply |
| **App 挂了** | 禁用相关 ruleset（人工、限时、留痕） | 见 §8.1 | App 恢复后重新 `active` |
| 紧急变更 | 用 `bypass_actors` 里那个团队的 `pull_request` 模式 | 直接在 PR 里合 | —— |

### 8.1 熔断纪律（写进 oncall runbook）

```
触发条件：CR Check 服务不可用 > 15 分钟 / CR 平台故障导致全员误拦
执行人  ：值班 SRE（★ 提前指定，不能是"谁有空谁上"）
执行方式：enforcement → disabled（★ 不要删规则）
时限    ：≤ 2 小时内必须恢复或升级
审计    ：ruleset 版本历史会留下变更记录；事后补一条变更说明
```

> ⚠️ **不要把"App 挂了自动放行"做成自动化**。
> 那等于给门禁留了一个后门 —— 让 App 挂掉就能绕过。
> 熔断必须是**人工、有时限、有审计**的动作。

---

## 9. 权限与 token

| 操作 | 需要什么 |
|---|---|
| 读 ruleset 列表 | 仓库 read 权限（**任何人**都能看 active ruleset） |
| 改**仓库级** ruleset | 仓库 admin，或有 "edit repository rules" 权限的 custom role |
| 改**组织级** ruleset | ★ **组织 owner**（只有 owner 能改） |
| `gh` token scope | 仓库级：默认 token 即可；组织级：`gh auth refresh -s admin:org` |
| CR Check App 的权限 | `checks:write`（写 check）+ **`statuses:write`**（★ 能被选为 expected source 的硬前提） |
| CR Check App 的仓库范围 | Installation 要**包含**目标仓库（Selected repositories 时别漏） |

> ★ **组织级 ruleset 的"只有 owner 能改"** 意味着：
> 想让平台组自己维护 ruleset → 要么给 owner，要么全部走仓库级 ruleset。

---

## 10. 安装失败的报错对照表

| 现象 / 报错 | 根因 | 解法 |
|---|---|---|
| `404 Not Found`（打 `repos/...` 却失败） | 仓库不存在 / 名字拼错 / 私有仓库没权限 | 检查 owner/repo；确认 token 有该仓库权限 |
| `404`（打 `orgs/...` 失败） | ★ **scope 用错**：这个 JSON 是仓库级的 | 脚本会自动判定；手动打 API 时注意 01/07/08 → orgs，其余 → repos |
| `403 Forbidden` | 组织级 ruleset 需要 owner；或 token 缺 `admin:org` | `gh auth refresh -s admin:org`；或找 owner |
| `422 Unprocessable Entity` | ★ **字段名/取值不合法**（如 `operator` 缺、pattern 非法、conditions 组合非法） | `python3 validate-rulesets.py` 先自检；错误信息里有 `path` 字段指到具体位置 |
| `422` + 提到 `integration_id` | App ID 不是整数 / 该 App 在此仓库不存在 | 用真实 App ID；确认 Installation 包含该仓库 |
| 同名规则报冲突 | 已存在同名 ruleset | 用 `PUT` 更新（脚本已自动处理） |
| **PUT 之后规则全没了** | ★ `PUT` 是全量替换 | 取回完整 JSON 改一个字段再整体 PUT（§4.4） |
| UI 里选不到我们的 App | ★ App 没跑过 check run / 缺 `statuses:write` | 回到 §2 的 ①② 步 |
| 规则"配了但没生效" | `enforcement` 还是 `disabled`；或目标分支/仓库没命中 | `--list` 看 enforcement；`rules/branches/<branch>` 看聚合 |
| 合并框里看不到任何限制 | ruleset 没命中这个 base 分支 | 检查 `conditions.ref_name.include` 的 fnmatch 写法（`release/**` vs `release/*`） |
| 提交进去了但分支没动 | 正常现象：metadata 规则是"ref 不更新"，不是"拒绝 push" | 改 message 后 `--amend` 重新推 |
| 老仓库没被管 | 组织的 `repository_name` 模式没匹配上（注意 `*` 不跨 `/`） | 改成 `platform-*` 或 `~ALL` |
| CI 里 apply 成功但线上没变 | 改的是仓库级、但发到组织级（或反之） | `--list` 对比两端点的清单 |

---

## 11. 关联文档

| 主题 | 文档 |
|---|---|
| Ruleset 概念 / 与 App 的唯一耦合点 / 4 种静默失效 | [`14-rulesets-and-gitapp-gate.md`](./14-rulesets-and-gitapp-gate.md) |
| 最小示例（commit message 以 `CR123456` 开头） | [`15-commit-message-cr-prefix.md`](./15-commit-message-cr-prefix.md) |
| ★ 配置 + 脚本 + 校验器 | [`examples/rulesets/`](../examples/rulesets/) |
| ★ 一键安装脚本 | [`examples/rulesets/apply-rulesets.sh`](../examples/rulesets/apply-rulesets.sh) |
| ★ 契约静态检查（CI 里跑） | [`examples/rulesets/validate-rulesets.py`](../examples/rulesets/validate-rulesets.py) |
| 官方 REST（仓库级 / 组织级） | https://docs.github.com/en/rest/repos/rules · https://docs.github.com/en/rest/orgs/rules |
| 官方 UI 文档（组织级，含 Import a ruleset） | https://docs.github.com/en/organizations/managing-organization-settings/managing-rulesets-for-repositories-in-your-organization |

### 标注

| 标注 | 内容 |
|---|---|
| **官方保证** | UI 有 "Import a ruleset" 入口（JSON 导入）；组织级 ruleset 只有 owner 能改；仓库级与组织级**叠加取最严**；App 被选为 expected source 需 `statuses:write` + **最近提交过 check run**；metadata 规则 push 时是"ref 不更新"；组织级 ruleset 可按 `~ALL` / 名单 / 名称模式 / 自定义属性筛选仓库；任何人有 read 权限都能看到 active ruleset；Rule insights dashboard（Enterprise） |
| **推荐实现** | 脚本自动判定 scope；同名 → PUT 幂等；**PUT 用完整 payload 重建**（不做增量）；先 `disabled` 再 `active`；GitOps 管 ruleset + 定时漂移检测；熔断走 `disabled` 不删规则 |
| **需实测 / 部署前验证项** | 你们的计划是否开放 metadata 规则（Enterprise）；`hashicorp/github` provider **目前没有 ruleset 资源**（若后续新增，此节需更新）；`gh` 的 `admin:org` scope 在你们环境是否可用；组织级 ruleset 的 owner 授权流程；UI 导入后 `integration_id` 的呈现方式 |
