# 08-main-ruleset.json · 逐字段解读 + 安装（UI 导入 JSON）

> **副标题**：这是本目录里"最小但最狠"的一条 —— 只做一件事：
> **把 commit message 的格式要求，交给 GitHub 平台自己判**，
> 而不是靠"webhook 自检 + 写 status + `required_status_checks` 拦"那一圈往返。
>
> **一句话结论**
> ★ **`commit_message_pattern` 是 Enterprise 专属 rule type**：
> 个人账号 / Team 组织上 **API 直接 `422`、UI 导入会"静默丢弃"**
> → 导入完**必须**核对 `rules` 数组还在不在（详见 §5）。
> 有 Enterprise → 用它顶掉自建的那层校验；没有 → 走
> [`workflows/cr-prefix-check.yaml`](./workflows/cr-prefix-check.yaml) + `required_status_checks`。

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-tldr) | TL;DR：6 条结论 |
| [§1](#1-逐字段解读) | ★ 逐字段解读（这份 JSON 到底在说什么） |
| [§2](#2-它到底拦的是哪一步) | ★ 它拦的是哪一步（本地 / push / PR / merge 时序） |
| [§3](#3-★-ruleset-与-webhook-的边界你的思路落地) | ★ **ruleset 与 webhook 的边界**（"用 ruleset 替换 webhook"的思路落地） |
| [§4](#4-安装路径-a--ui-导入-json点鼠标) | 安装路径 A · UI 导入 JSON（点鼠标，10 分钟） |
| [§5](#5-★-导入后必须做的-3-个核对) | ★ 导入后必须做的 3 个核对（不做 = 装了个空壳） |
| [§6](#6-安装路径-b--api--脚本) | 安装路径 B · API / 脚本 |
| [§7](#7-回滚) | 回滚 |
| [§8](#8-常见坑清单) | 常见坑清单 |
| [§9](#9-关联文档) | 关联文档 |

---

## 0. TL;DR

1. **这一条只管一件事**：commit message 必须以 `<工单代号>-<数字>:` 开头。
   它**不要求走 PR、不要求 reviewer、不管分支名** —— 它不是"分支保护"，是"格式门禁"。

2. **作用域是"这个仓库的默认分支"**：`~DEFAULT_BRANCH` 是 ruleset 的特殊 token，
   每个仓库各指各的默认分支。想覆盖 `release/**`、`*Release`，
   得自己往 `conditions.ref_name.include` 里加（对比
   [`07-commit-message-cr-prefix-protected.json`](./07-commit-message-cr-prefix-protected.json)）。

3. **它是仓库级 ruleset**（`conditions` 里**没有** `repository_name`）→
   API 端点是 `repos/{owner}/{repo}/rulesets`。
   想全组织生效 → 加 `repository_name` → 端点换成 `orgs/{org}/rulesets`。

4. **★ Enterprise 专属**：`commit_message_pattern` 在个人账号 / Team 组织上
   **API 报 `422 Invalid rule`、UI 导入静默丢弃**。
   → **导入后第一件事：确认 `rules` 没被丢空**（§5）。

5. **★ 它顶掉的是"自建校验"，不是 webhook 本身**：
   webhook 还要留着（Argo CD 靠它触发同步），但**合规性判定从你的服务挪到了平台**。
   详见 §3。

6. **★ 它拦的是 ref 更新，不是本地 commit**：本地 `git commit` 永远成功，
   失败发生在 `git push`（形态是"**分支没动**"而不是"push 被拒"）。

---

## 1. 逐字段解读

原始文件：[`08-main-ruleset.json`](./08-main-ruleset.json)

```json
{
  "name": "Require ticket prefix in commit messages",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "commit_message_pattern",
      "parameters": {
        "name": "APIYUND, AIBNG, TEAMNAME or APPABJX ticket prefix",
        "operator": "regex",
        "pattern": "^(APIYUND|AIBNG|TEAMNAME|APPABJX)-[0-9]+:"
      }
    }
  ]
}
```

| 字段 | 值 | 含义 | 踩坑点 |
|---|---|---|---|
| `name` | 人类可读的名字 | **显示名 + 幂等键**（脚本按名字找同名 ruleset 做 `PUT` 更新） | 本目录其它文件用 slug（`main-branch-guard`），这份用句子 —— 能用，但**改名 = 变成新规则** |
| `target` | `branch` | 作用对象是**分支**（不是 tag、不是 push 全局） | tag 要另外写 `target: tag` |
| `enforcement` | `active` | **立即生效** | 建议先 `disabled` 联调再切 `active`（见 §4.3） |
| `bypass_actors` | `[]` | **没有任何角色可以绕过**（含 admin） | GitHub 默认允许 admin 绕过；显式留空 = 关掉这个后门 |
| `conditions.ref_name.include` | `["~DEFAULT_BRANCH"]` | 只管**默认分支** | `~DEFAULT_BRANCH` 是特殊 token，不是 fnmatch；写 `refs/heads/main` 就写死了分支名 |
| `conditions.ref_name.exclude` | `[]` | 不排除任何分支 | — |
| `rules[0].type` | `commit_message_pattern` | ★ **Enterprise 专属** rule type | 个人/Team 上 422 或静默丢弃 |
| `rules[0].parameters.name` | 描述文字 | 只在 UI 里显示 | 随便写 |
| `rules[0].parameters.operator` | `regex` | 用正则 | ★ 只能 `regex`（另可选 `starts_with`/`ends_with`/`contains`/`any_of`） |
| `rules[0].parameters.pattern` | `^(...)-[0-9]+:` | 合规的 commit message 长这样 | RE2 语法：**不支持反向引用 / lookahead** |

> ★ **`negate` 没写**：默认 `false`（= 必须匹配）。写成 `true` 就是"禁止匹配"（用于"禁止某关键词"）。

### 1.1 正则拆解

```
^(APIYUND|AIBNG|TEAMNAME|APPABJX)-[0-9]+:
 │      │      │        │      │      │      └─ 必须紧跟一个英文冒号
 │      │      │        │      │      └──────── 数字 1~n 位
 │      │      │        │      └─────────────── 连字符
 │      │      │        └────────────────────── 四个工单系统代号之一
 │      │      └─────────────────────────────── 备选分支
 │      └────────────────────────────────────── 备选分支
 └───────────────────────────────────────────── 必须从第一个字符开始（不是"包含"）
```

**为什么这么写**：

- `^` 锚定开头 → `fix: APIYUND-123:` **不合规**（前缀必须在最前面）。
- `[0-9]+` 而不是 `[0-9]{6}` → 不锁死工单号位数（不同系统位数不一样）。
- 结尾的 `:` → 强制"工单号 + 分隔符"，避免 `APIYUND-1234abc` 这种糊弄过去。
- **省略号后面随便写什么**（subject 自由）。

### 1.2 想改的话，改哪几个字

| 想改成 | 改哪 |
|---|---|
| 只认一个系统 | `pattern` 里只留一个代号 |
| 允许 `#123` 风格 | `pattern` 改成 `^(#\\[0-9]+:\|APIYUND-[0-9]+:)` |
| 也管 release 分支 | `include` 加 `"refs/heads/release/**"`、`"refs/heads/*Release"` |
| 全组织生效 | `conditions` 加 `"repository_name": {"include": ["~ALL"], "exclude": []}` → **改打 orgs 端点** |
| 改成"禁止某关键词" | 加 `"negate": true` |

---

## 2. 它到底拦的是哪一步

```
本地 git commit          →  ✅ 永远成功（GitHub 管不到本地）
   ↓ git push
GitHub 收到 ref 更新      →  ★ 在这里判 ruleset
   ├─ commit message 不合规 → ❌ 拒绝更新这个 ref（★ 分支"没动"，不是"push 被拒"）
   └─ 合规                → ✅ ref 更新
                            ↓
                       push 事件 / webhook 投递   ← ★ 走的是"ref 已更新"这条路
                            ↓
                    PR 打开 → review → merge
                            ↓
              squash merge 时：★ commit message = PR 标题（+ "#123"）
                            ↓
                       ref 再更新一次 → ruleset 再判一次
```

★ **三个必须记住的点**：

1. **本地 commit 不会被拦** —— "我提交的时候没人拦我" **不能**证明规则没装（详见
   [`git-apps/16-ruleset-install-runbook.md`](../../git-apps/16-ruleset-install-runbook.md) §2.5.5）。

2. **★ squash merge 会把 PR 标题变成 commit message** →
   PR 标题也必须带工单前缀，否则**合并那一步**被拒（PR 标题不显示工单号 = 白提）。

3. **★ 不合规的 commit 不会产生 webhook 事件** ——
   ref 都没更新，GitHub 不会推送 push 事件。
   → 你的服务里**收不到脏数据**，这是"把校验挪到平台"最大的收益之一。

---

## 3. ★ ruleset 与 webhook 的边界（你的思路落地）

> 原始想法：**"用 ruleset 装到 branch 上，等于是用平台能力替换一些企业级别的东西，
> 比如 webhook 那套设置。"**
> 这个方向**对**，但要精确到"替换哪一段"。

### 3.1 两者根本不是一类东西

| | **webhook** | **ruleset** |
|---|---|---|
| 本质 | **事件投递**（"发生了 push，快来看"） | **平台内置门禁**（"这次 ref 更新不合规，不许动"） |
| 方向 | GitHub → 你的服务 | 你的配置 → GitHub 执行 |
| 同步性 | 异步（可能延迟、可能丢） | 同步（判定完才动 ref） |
| 依赖你的服务在线吗 | ✅ 依赖 | ❌ 不依赖 |
| 回答的问题 | "发生了什么？" | "允不允许发生？" |

### 3.2 ★ 真正被替换掉的，是这一段

**替换前（自建 webhook 校验）**：

```
开发者 git push
   → GitHub 更新 ref
   → GitHub 投递 push 事件（webhook）
   → 你的服务收到 → 校验 commit message → 不合规就写一个 failing status
   → `required_status_checks` 看到 failing → 挡住合并
   ↑ 往返延迟几秒~几十秒；服务挂了 → 门禁形同虚设（或永远卡住）
```

**替换后（ruleset metadata 规则）**：

```
开发者 git push
   → GitHub 在更新 ref **之前**自己判 commit message
   → 不合规 → 直接拒绝更新 ref（连 webhook 都不会发）
   → 合规   → 更新 ref → webhook 照常投递（Argo CD 同步不受影响）
```

### 3.3 结论表

| 问题 | 答案 |
|---|---|
| ruleset 能替代 webhook 吗？ | ❌ **不能**。webhook 是事件通道，ruleset 是判定器 |
| ruleset 能替代"自建的 webhook 校验 + status 拦截"吗？ | ✅ **能**，而且更好（无延迟、不依赖服务在线） |
| 那 webhook 还要不要配？ | ✅ **要**。Argo CD 同步、IM 通知、审计外送都靠它 |
| 装完 ruleset 后 webhook 要改吗？ | ❌ 不用。两条链路是**互补**的：ruleset 管"合不合法"，webhook 管"通知谁" |
| 什么时候仍然只能用 webhook + CI？ | **没有 Enterprise**（metadata 规则不可用）→ 只能用 `required_status_checks` + Actions |

> ★ **一句话**：**ruleset 把"判断"从你的服务挪到了平台；webhook 继续负责"通知"。**
> 两者不是竞争关系，是**门禁 + 通知**。

### 3.4 和同目录其它文件的分工

| 文件 | 管什么 | 和 08 的关系 |
|---|---|---|
| `08-main-ruleset.json`（本文件） | **message 格式**（原生、Enterprise 专属） | — |
| `07-commit-message-cr-prefix-protected.json` | main 分支**必须走 PR + CI check** | 互补：08 管格式，07 管流程 |
| `04-repo-prod-branches.json` | prod 分支 reviewer / 状态检查 / 合并方式 | 互补 |
| `workflows/cr-prefix-check.yaml` | **没有 Enterprise 时的替代实现** | 08 不可用时的 Plan B |
| `05-push-secrets.json` | 禁密钥扩展名 / 大文件 | 互补（另一个 Enterprise 专属） |

★ **别拿 08 当"分支保护"用**：它**不要求 PR、不要求 reviewer**。
直接往 main 推一个带合规前缀的 commit，08 是放行的。
要"主分支必须走 PR"→ 用 `07-`（或企业目录的 `05-org-prod-branch-gate.json`）。

---

## 4. 安装：路径 A · UI 导入 JSON（点鼠标）

> ★ **JSON 文件不会自己生效**。两条路：UI 导入（点鼠标）或 API 写入（脚本）。
> 两条路**导入的是同一份 JSON**，没有区别。
> 完整 Runbook（权限、顺序、回滚）：
> [`git-apps/16-ruleset-install-runbook.md`](../../git-apps/16-ruleset-install-runbook.md)。

### 4.1 仓库级（这份 JSON 的正确落点）

```
仓库 → Settings → Code, planning, and automation → Rulesets
  → Rulesets 标签页
  → New ruleset（下拉）→ **Import a ruleset**      ★ 导入入口
  → 选 08-main-ruleset.json
  → Review the imported ruleset（★ 逐项核对 §5 的三条）
  → Create
```

### 4.2 组织级（想一次管所有仓库）

```
头像 → Organizations → 选组织
  → Settings（看不到 = 权限不够；改组织级 ruleset 只有 **org owner** 能改）
  → Code, planning, and automation → Repository → Rulesets
  → New ruleset（下拉）→ **Import a ruleset**
  → 选 08-main-ruleset.json
  → ★ 导入前先把 JSON 改成组织级：
       conditions 里加 "repository_name": {"include": ["~ALL"], "exclude": []}
  → Review → Create
```

### 4.3 导入后要改的（★ 建议）

| 位置 | 改成什么 | 为什么 |
|---|---|---|
| **Enforcement status** | 先 `Disabled` → 联调通过再 `Active` | 免得一上来卡住所有人 |
| **分支范围** | 想覆盖 release 就加 `refs/heads/release/**` | `~DEFAULT_BRANCH` 只管默认分支 |
| **bypass 列表** | 保持空 = 谁都不能绕过 | 空列表也意味着 admin 不能开后门 |

---

## 5. ★ 导入后必须做的 3 个核对

> **不做这三步 = 大概率装了个空壳。**
> GitHub 在 UI 导入时**不报错**，但会把不认识的 rule type **静默丢弃**。

```bash
# ① 规则还在吗？（★ list 接口不返回 rules，必须按 id 查）
gh api repos/<owner>/<repo>/rulesets | jq -r '.[] | "\(.id)\t\(.name)\t\(.enforcement)"'
for id in <上面的 id>; do
  gh api repos/<owner>/<repo>/rulesets/$id | jq -r '"\(.name): rules=\([.rules[]?.type]|join(","))"'
done
#    ★ rules= 是空的 → 这条 ruleset 是装饰品，一条都不执行

# ② 目标分支真的命中了吗？（★ 这才是权威）
gh api repos/<owner>/<repo>/rules/branches/main | jq -r '.[].type'
#    ★ 返回 [] → 没有任何规则命中这个分支

# ③ 联调（★ 唯一的真验证）
#    在测试分支提交一个不带工单前缀的 commit → push 必须被拒（分支没动）
#    再改成一个带前缀的 commit → push 必须成功
```

**如果 ① 查到 `rules=[]`**：

| 现象 | 根因 | 解法 |
|---|---|---|
| 规则被丢空、状态仍显示 `active` | ★ **计划不支持 `commit_message_pattern`**（个人账号 / Team 组织） | ① 先用探针确认能力：[`examples/rulesets-enterprise/probe-enterprise-capabilities.sh`](../../examples/rulesets-enterprise/probe-enterprise-capabilities.sh)；② 不支持就改走 CI：[`workflows/cr-prefix-check.yaml`](./workflows/cr-prefix-check.yaml) + `required_status_checks` |
| API 报 `422 Invalid rule 'commit_message_pattern'` | 同上 | 同上 |
| 规则在、但 push 没被拦 | 分支没命中 `ref_name` | 看 ② 的输出 |

---

## 6. 安装：路径 B · API / 脚本

```bash
# ① 直接打 API（仓库级）
gh api -X POST repos/<owner>/<repo>/rulesets --input 08-main-ruleset.json

# ② 或者用本目录的一键脚本（会自动判定 org/repo scope、同名自动 PUT、幂等）
cd examples/rulesets
./apply-rulesets.sh --owner <owner> --repo <repo> --enforcement disabled
./apply-rulesets.sh --owner <owner> --repo <repo> --enforcement active --only "Require ticket prefix in commit messages"

# ③ 静态自检（不连 GitHub；★ 改完 JSON 跑一下）
python3 validate-rulesets.py
```

> ★ **`PUT` 是全量替换，不是增量**：
> `gh api -X PUT .../rulesets/<id> -f enforcement=active` 会把**所有规则清空**。
> 正确做法：取回完整 JSON → 改一个字段 → 整体 PUT 回去（脚本就是这么做的）。

---

## 7. 回滚

| 动作 | 怎么做 | 说明 |
|---|---|---|
| **临时关掉（首选）** | UI：点 ruleset → Enforcement status → `Disabled`；或 `gh api -X PUT ... -f enforcement=disabled`（**注意全量替换**，走脚本） | 规则留着、审计记录还在 |
| 删掉 | UI：点 ruleset → `...` → Delete ruleset；或 `gh api -X DELETE .../rulesets/<id>` | 没有痕迹 |
| 只放行紧急修复 | 加一个 `bypass_actors`（人 / Team / App） | ★ 就是开后门，慎用、要有时限 |

---

## 8. 常见坑清单

| # | 坑 | 现象 | 解法 |
|---|---|---|---|
| 1 | ★ **计划不支持 metadata 规则** | ruleset 显示 `active`，但什么都不拦 | §5 的 ①；改走 CI 路线 |
| 2 | ★ **squash merge 用 PR 标题当 message** | PR 标题没前缀 → 合并被拒 | PR 标题也带 `<代号>-<数字>:` |
| 3 | **本地 commit 不拦** | "我提交时没人拦我" | 去看 push 有没有被拒（分支没动 ≠ push 被拒） |
| 4 | **`~DEFAULT_BRANCH` 只管默认分支** | release 分支随便提交 | `include` 里补 `refs/heads/release/**` |
| 5 | **pattern 没锚定 `^`** | 消息中间出现工单号也放行 | 保持 `^` |
| 6 | **忘了 `:`** | `APIYUND-123` 放行、`APIYUND-123x` 混淆 | 结尾保留 `:` |
| 7 | **拿 08 当分支保护** | 直接 push 到 main 也放行 | 08 只管格式；流程要靠 `07-` |
| 8 | **`PUT` 只传一个字段** | 规则全被清空 | 全量 payload 整体 PUT（脚本已处理） |
| 9 | **改了 JSON 但线上没变** | 忘了重新导入 / 忘了 `enforcement` | 导入后走 §5 的三核对 |
| 10 | **多个 ruleset 叠加** | 仓库级不能放松组织级 | 叠加取最严；要改组织级得 org owner |

---

## 9. 关联文档

| 主题 | 文档 |
|---|---|
| ★ **安装 Runbook**（权限、顺序、验证、回滚、报错对照表） | [`git-apps/16-ruleset-install-runbook.md`](../../git-apps/16-ruleset-install-runbook.md) |
| ★ 企业版能力矩阵（哪些 rule type 要什么计划） | [`examples/rulesets-enterprise/00-enterprise-capabilities.md`](../../examples/rulesets-enterprise/00-enterprise-capabilities.md) |
| ★ 计划探测脚本（实测你们环境到底支持什么） | [`examples/rulesets-enterprise/probe-enterprise-capabilities.sh`](../../examples/rulesets-enterprise/probe-enterprise-capabilities.sh) |
| commit message 前缀的最小方案（CI 版） | [`git-apps/15-commit-message-cr-prefix.md`](../../git-apps/15-commit-message-cr-prefix.md) |
| 三层门禁（合并门 / 同步门 / 准入门） | [`git-apps/11-github-app-concepts.md`](../../git-apps/11-github-app-concepts.md) |
| webhook 的 push vs pull 语义 | [`git-apps/12-webhook-push-vs-pull.md`](../../git-apps/12-webhook-push-vs-pull.md) |
| 契约静态检查器 | [`examples/rulesets/validate-rulesets.py`](./validate-rulesets.py) |
