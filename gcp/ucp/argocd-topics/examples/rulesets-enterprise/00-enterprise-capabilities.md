# 00 · 企业版能力矩阵（哪些 rule type 要什么条件）

> **副标题**：企业版的价值全在"多出来的那些能力"上；
> 但**能不能用取决于计划、仓库可见性、（GHES 的）版本**。
>
> **一句话结论**
> ★ **不要查文档后拍脑袋** —— 直接跑
> [`probe-enterprise-capabilities.sh`](./probe-enterprise-capabilities.sh)，
> 2 分钟得到你们环境的**真实能力表**。本文档是"怎么读那张表"和"每条能力怎么配"。

---

## 目录

| 章节 | 内容 |
|---|---|
| [§1](#1-能力矩阵) | 能力矩阵（rule type × 计划） |
| [§2](#2-★-先跑探针（实测优先于文档）) | ★ 先跑探针（实测优先于文档） |
| [§3](#3-每条企业能力的配置要点) | 每条企业能力的配置要点 + 坑 |
| [§4](#4-ghes-自建版要额外确认的) | GHES 自建版要额外确认的 |
| [§5](#5-能力上限决定了你的部署路径) | 能力上限决定了你的部署路径 |
| [§6](#6-关联文档) | 关联文档 |

---

## 1. 能力矩阵

### 1.1 基础门禁（所有计划都有）

| rule type | 用途 | 我们用它 |
|---|---|---|
| `pull_request` | 必须走 PR、reviewer 数、合并方式 | 所有分支保护 |
| `deletion` | 禁删分支 | 所有分支保护 |
| `non_fast_forward` | 禁强推 | 所有分支保护 |
| `required_linear_history` | 线性历史 | release / prod |
| `required_status_checks` | 必须过的 check | `cr/prod-validation`（CR Check App） |
| `required_deployments` | 部署环境必须成功 | 可选 |
| `creation` / `update` | 限制新建/改名 | tag 规则 |

### 1.2 ★ Enterprise 专属

| rule type | 个人账号 | Team/Pro 组织 | Enterprise Cloud | GHES | 备注 |
|---|---|---|---|---|---|
| `commit_message_pattern` | ❌ | ❌（私有仓库） | ✅ | ★ 看版本 | 格式门禁的核心 |
| `branch_name_pattern` | ❌ | ❌（私有仓库） | ✅ | ★ 看版本 | 分支命名 |
| `tag_name_pattern` | ❌ | ❌（私有仓库） | ✅ | ★ 看版本 | tag 命名 |
| push ruleset（`target: push`） | ❌ | ❌ | ✅ | ★ 看版本 | 密钥 / 大文件 / 凭据 |
| `merge_queue` | ❌ | ❌（私有仓库） | ✅ | ★ 看版本 | 合入前批量验证 |
| `required_signatures` | ❌ | 部分 | ✅ | ★ 看版本 | 生产签名提交 |
| `required_workflows` | ❌ | ❌ | ✅ | ★ 看版本 | 组织级强制 CI |
| code scanning ruleset | ❌ | ❌ | ✅（需 GHAS） | ★ 看版本 | 扫描门禁 |

> ★ **公开仓库通常更宽松**（官方对 public repo 放开了部分能力）。
> 上表按"**私有仓库**"这个最严格口径写 —— 私有仓库都可用 ⇒ 公开仓库必然可用。
>
> ★ **GHES 的能力是跟着版本走的**：自建版升级节奏与云版不同，
> **同一份 ruleset JSON 在不同 GHES 版本上结果可能不同** → 必须实测。

### 1.3 非 rule type 的治理能力

| 能力 | Enterprise 才有 |
|---|---|
| 组织级 ruleset（一次管所有仓库） | Team 起就有（但只有 org owner 能改） |
| `repository_property`（按自定义属性筛仓库） | ✅ |
| Rule insights（规则命中统计） | ✅ |
| 组织审计日志 / SAML / 自定义组织角色 | ✅ |
| 合并队列、私有仓库的规则放宽 | ✅ |

---

## 2. ★ 先跑探针（实测优先于文档）

```bash
cd examples/rulesets-enterprise

./probe-enterprise-capabilities.sh --probe-repo <某个测试仓库>
```

**它做什么**（安全，不会污染环境）：

```
① 在**组织级**建一条 ruleset，conditions.repository_name 只含探针仓库
② enforcement = disabled（建了也不执行）
③ 立刻 DELETE
→ 其余仓库完全不受影响；探针仓库上只多一条"已删除"的记录
```

**输出**：一张 `rule type × 可用/不可用` 的表。不可用的会附上 GitHub 的原始报错。

**判定标准**：

| 输出 | 含义 | 动作 |
|---|---|---|
| `✅ 可用` | 你们的环境支持 | 可以写进 ruleset |
| `❌ 不可用` + `Invalid rule 'xxx'` | 计划/版本不支持 | ★ **不要**写进 ruleset（UI 导入会静默丢弃 → 空壳 ruleset） |
| `❌ 不可用` + 其它报错 | 多半是权限或参数问题 | 先修参数/权限再重跑 |

> ★ **强烈建议**：把这张表**贴进 PR**（`--out capabilities.md`），
> 让评审的人知道"这份配置是基于实测的，不是基于文档的"。

---

## 3. 每条企业能力的配置要点

### 3.1 `commit_message_pattern`（核心）

```jsonc
{
  "type": "commit_message_pattern",
  "parameters": {
    "name": "commit subject 必须以 CR<6位数字> 开头",  // 必填
    "negate": false,                                  // false = 必须匹配
    "operator": "regex",                              // ★ 必须是 "regex"，默认不是
    "pattern": "^CR[0-9]{6}(\\s|$)"                   // RE2 语法
  }
}
```

**坑**：

| 坑 | 现象 | 解法 |
|---|---|---|
| 忘写 `operator: "regex"` | 规则不生效 | 显式写死 |
| 用 `(?!)` 负向预查 | RE2 不支持 → 规则报错 | 改用 `negate: true` |
| 写成 `^CR[0-9]+` | `CR1`、`CR123` 都能混过去 | 用 `{6}` 锁死位数 |
| 行尾用 `$` | 部分 push 路径判定异常 | 官方建议 `\n?$`（我们用 `(\s|$)` 覆盖） |
| push 失败形态误解 | 以为 push 被拒 | ★ 是 **ref 不更新**（commit 变 unreachable） |

### 3.2 `branch_name_pattern`

```jsonc
{
  "type": "branch_name_pattern",
  "parameters": {
    "name": "分支名必须是 feature|fix|hotfix|git-apps|codex/<名字>",
    "negate": false,
    "operator": "regex",
    "pattern": "^(feature|fix|hotfix|git-apps|codex)/[A-Za-z0-9._-]+$"
  }
}
```

**坑**：

- ★ **它作用在"所有分支"上**（包括 `main`）→ 必须用 `conditions.ref_name.exclude`
  把默认分支和 release 分支排除掉，否则 `main` 自己都不合规。
- `*` 不跨 `/`，`**` 跨层级（fnmatch 语义）。

### 3.3 `tag_name_pattern`

- `target` 必须是 `"tag"`（不是 `branch`）。
- 建议同时加 `creation` / `update` / `deletion` 规则 → tag 也禁删禁改。

### 3.4 push ruleset（`target: push`）

```jsonc
{
  "name": "org-push-guard",
  "target": "push",              // ★ 不是 "branch"
  "conditions": { "repository_name": {...}, "ref_name": {...} },
  "rules": [
    { "type": "file_extension_restriction",
      "parameters": { "restricted_file_extensions": [".pem", ".key", ".p12", ".env"] } },
    { "type": "file_path_restriction",
      "parameters": { "restricted_file_paths": ["releases/**", "**/*.tfstate"], "ignored_file_paths": [] } },
    { "type": "max_file_size", "parameters": { "max_file_size": 10 } },   // ★ 单位 MB
    { "type": "block_credential_changes",
      "parameters": { "credential_types": ["password", "personal_access_token", "ssh_key"] } }
  ]
}
```

**坑**：

| 坑 | 现象 | 解法 |
|---|---|---|
| ★ `max_file_size` 单位是 **MB** | 写 10 以为是 10 字节 | 单位 MB；校验器 E11 会查 |
| `ignored_file_paths` 漏了 | 白名单路径也被拦 | 显式列出例外的路径 |
| 机器人提交被拦 | Dependabot 推 `.env` 之类 | 用 `bypassAllowlist` 显式登记 |
| 忘了它只在 push 生效 | 以为"改历史"也会被查 | 它拦的是**新的 push** |

### 3.5 `merge_queue`

```jsonc
{
  "type": "merge_queue",
  "parameters": {
    "merge_method": "squash",
    "min_entries_to_merge": 1,
    "max_entries_to_merge": 5,
    "grouping_strategy": "ALLGREEN"
  }
}
```

**坑**：

- ★ **同一条 ruleset 里必须有 `pull_request` 规则**，否则队列不建立（校验器 E14 会查）。
- ★ **私有仓库**才支持 merge queue（公开仓库本来就能直接合）。
- 队列会让"合并"变成异步的 → 通知/回滚策略要重新设计。
- ★ **先 `disabled` 联调**：队列一开，"合并"的行为就变了，团队需要适应期。

### 3.6 `required_signatures`

- 无 parameters。
- ★ 生效前要确认**开发者已经配置了签名密钥**（否则全部推不动）。
- 先在非生产仓库开，确认覆盖率。

### 3.7 `required_workflows`

```jsonc
{
  "type": "required_workflows",
  "parameters": {
    "required_workflows": [
      { "path": ".github/workflows/org-policy-guard.yaml",
        "ref": "refs/heads/main",
        "repository_id": 654321 }        // ★ 必须是"工作流所在仓库"的数字 ID
    ]
  }
}
```

- ★ `repository_id` 是**仓库的数字 ID**（不是名字）：`gh api repos/<o>/<r> --jq .id`。
- 被引用的工作流必须在**同一个仓库**里，且路径要真实存在。
- 需要中心仓库放这条 workflow。

### 3.8 code scanning ruleset

- `target: "code_scanning"`（**不是** `branch`）。
- 条件里用 `repository_name`，**不要**用 `ref_name`（校验器会提示）。
- 需要仓库已启用 GHAS。

---

## 4. GHES 自建版要额外确认的

| 项 | 怎么确认 |
|---|---|
| GHES 版本 | `gh api /meta` 或设置页 |
| 组织的 ruleset 端点是否可用 | `gh api orgs/<org>/rulesets`（404 = 不支持） |
| metadata 规则是否可用 | ★ 跑探针 |
| push ruleset 是否可用 | ★ 跑探针 |
| merge queue / required_workflows | ★ 跑探针（这两条版本差异最大） |
| API 基址 | GHES 是 `https://<host>/api/v3`（`gh --hostname <host>` 会自动处理） |
| 升级节奏 | ★ **每次 GHES 升级后重跑一次探针** —— 新能力可能出现，旧规则也可能行为变化 |

> ★ **一条纪律**：把探针挂进**定期任务**（每月一次 + 每次 GHES 升级后一次），
> 结果存进仓库 → 能力变化有记录。

---

## 5. 能力上限决定了你的部署路径

```
探针结果 → 按下面的顺序取用能力，别贪多
```

| 探针结果 | 部署策略 |
|---|---|
| 只有基础门禁可用 | 走**个人版的 CI 路线**（`examples/rulesets/`） |
| metadata 可用，push 不可用 | ★ 最有价值的组合：**格式门禁上服务端**，内容门禁靠 CI/CODEOWNERS 补 |
| metadata + push 都可用 | ★★ 本目录的完整形态 |
| 再加上 merge_queue | 生产分支开队列；其它分支不开 |
| 再加上 required_workflows | 把"必须跑的 CI"收归组织级，不再靠每个仓库自觉 |

> ★ **每加一条能力，就多一条"配错 = 全组织卡死"的路径**。
> → 上线顺序 = **从影响面最小的开始**：
> `tag 规范` → `分支名规范` → `commit message 规范` → `push 门禁` → `生产门禁` → `合并队列`。

---

## 6. 关联文档

| 主题 | 文档 |
|---|---|
| ★ 探针脚本 | [`probe-enterprise-capabilities.sh`](./probe-enterprise-capabilities.sh) |
| ★ 差异对照（个人版 ↔ 企业版） | [`personal-vs-enterprise.md`](./personal-vs-enterprise.md) |
| ★ 落地步骤 | [`enterprise-rollout.md`](./enterprise-rollout.md) |
| 校验器（E1–E15） | [`validate-rulesets.py`](./validate-rulesets.py) |
| 官方文档 | <https://docs.github.com/en/organizations/managing-organization-settings/managing-rulesets-for-repositories-in-your-organization> |
