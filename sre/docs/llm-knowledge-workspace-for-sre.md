# LLM Knowledge Workspace 方案

## 1. Goal and Constraints

### Goal

把你现在这个以 Markdown、脚本、架构说明、排障文档、实验记录为主的 repo，串成一个可持续运行的本地知识工作台，让 LLM 不只是“回答问题”，而是持续做这几件事：

1. 收集本地和外部资料
2. 把原始资料编译成结构化知识
3. 基于知识生成需求澄清、架构总结、SRE 监控项、Runbook、对外说明
4. 把新产出再回写到知识库，形成可累计资产

### Constraints

- 你的核心职业场景不是通用知识管理，而是 GCP、GKE、Kong、Nginx、网络链路、SRE、排障、方案设计
- 你的 repo 已经天然是 Markdown-first，不适合再引入很重的知识库产品
- 你真正需要的是“知识编译流水线”，不是优先上复杂 RAG
- 输出应该继续以 `.md`、脚本、图、Runbook、方案文档为主，方便在 Obsidian 或 Git 中查看

---

## 2. Current Workspace Assessment

从当前 workspace 看，你已经具备了 70% 的基础，只是还没有被串成一个统一系统。

### 你现在已经有的东西

- 大量主题型知识目录
  - `gcp/`
  - `gke/`
  - `kong/`
  - `nginx/`
  - `k8s/`
  - `network/`
  - `sre/`
  - `sql/`
- 大量 Markdown 文档，适合被 LLM 编译
- 一部分脚本和 demo，可作为“知识 + 执行工具”的组合
- 已经开始有 skill 思维
  - [`/Users/lex/git/knowledge/skills/extract-requirements-target/SKILL.md`](/Users/lex/git/knowledge/skills/extract-requirements-target/SKILL.md)
  - [`/Users/lex/git/knowledge/skills/files-to-requirements/SKILL.md`](/Users/lex/git/knowledge/skills/files-to-requirements/SKILL.md)

### 当前缺口

- 没有统一的“原始资料层”和“编译后知识层”边界
- 没有统一的索引文件和主题汇总页
- 很多知识还停留在“按目录堆文档”，没有进入“知识对象”层
- 缺少周期性 health check 流程来找重复、冲突、过期结论
- 缺少稳定的产出目录约定，导致 LLM 虽然能写，但不容易持续积累

---

## 3. Recommended Architecture (V1)

### 结论

对你最合适的不是“先做一个问答系统”，而是先做一个 **本地 Markdown 编译型知识工作台**。

推荐 V1 架构：

```text
External Sources / Local Notes / Repos / PDFs / Images
  ->
raw/
  ->
LLM compile pipeline
  ->
wiki/
  -> topic pages
  -> entity pages
  -> summaries
  -> indexes
  -> decision notes
  ->
ops/
  -> runbooks
  -> sre requirements
  -> checklists
  ->
outputs/
  -> ad hoc analysis
  -> slide decks
  -> reports
  ->
health-check/
  -> duplication checks
  -> stale knowledge checks
  -> gap candidates
```

### Why This Fits You

- 你写的内容本来就以文档和方案为核心
- 你的很多任务本质上是“从散乱材料中提炼结论”
- 你的输出经常要变成：
  - 架构文档
  - SRE 监控需求
  - 排障文档
  - onboarding 文档
  - English explanation
- 这些都更适合“知识编译 + 回写”，而不是一次性问答

### Complexity

`Moderate`

不需要先做向量数据库、embedding pipeline、检索服务、Web UI。
V1 先靠目录约定、索引页、摘要页、LLM 编译流程就能跑起来。

---

## 4. Directory Model for Your Repo

建议不是重构整个仓库，而是在现有 repo 上叠加一层统一约定。

## 4.1 建议新增顶层目录

```text
kb/
  raw/
  wiki/
  outputs/
  checks/
  inbox/
```

### `kb/raw/`

放原始材料，不追求整洁，但要可追溯。

适合放：

- Obsidian Web Clipper 导出的网页
- PDF 转换出的 Markdown
- 临时研究资料
- 会议纪要原稿
- 外部回答原文
- 截图说明

建议按主题或日期拆：

```text
kb/raw/gcp/cross-project/
kb/raw/kong/runtime/
kb/raw/sre/incidents/
```

### `kb/wiki/`

这是“编译后知识层”，不是原文堆放区。

适合放：

- 主题页
- 概念页
- 方案对比页
- 统一结论页
- 常见误区页
- 索引页

例如：

```text
kb/wiki/gcp/cross-project-psc-neg.md
kb/wiki/gcp/service-attachment.md
kb/wiki/kong/retry-timeout-model.md
kb/wiki/sre/monitoring-patterns.md
kb/wiki/index/gcp-index.md
```

### `kb/outputs/`

放任务型产出，不直接污染 wiki 主干。

例如：

- 某次需求澄清
- 某个架构评审稿
- 某次 standup 支撑材料
- Marp 幻灯片

### `kb/checks/`

放健康检查结果。

例如：

- 重复文档清单
- 过期结论清单
- 缺失主题候选
- 术语不一致清单

### `kb/inbox/`

放待编译的新材料。
这是最关键的“缓冲层”，可以避免你把所有新资料直接塞进正式知识区。

---

## 5. Content Model

你这个 workspace 最适合把知识分成 5 类对象。

## 5.1 Source Note

原始材料摘要。

字段建议：

- source path
- source type
- created / modified
- short summary
- key claims
- related topics
- confidence

## 5.2 Topic Page

针对一个主题的编译页。

例如：

- cross-project PSC
- Kong DP health
- Cloud Armor traffic path
- GKE egress model

建议结构：

```markdown
# Topic

## Summary
## Key Concepts
## Recommended Pattern
## Known Trade-offs
## Common Failure Modes
## Related Docs
## Open Questions
```

## 5.3 Entity Page

针对概念对象建立单页。

例如：

- PSC NEG
- Service Attachment
- Cloud Armor
- Gateway
- HPA

这会让 LLM 在写方案时更容易链接已有知识，而不是每次重写概念定义。

## 5.4 Operational Page

针对生产运行的页面。

例如：

- monitoring requirements
- runbook
- rollback checklist
- pre-launch validation

这类页面对你价值很高，因为它们直接服务你的本职工作。

## 5.5 Decision / ADR Page

记录你最终为什么选某个方案。

例如：

- 为什么选 PSC NEG 而不是 `NON_GCP_PRIVATE_IP_PORT NEG`
- 为什么保留 Cloud Armor 在入口层
- 为什么单 Region 先上线

这会大幅减少你以后重复解释方案背景的成本。

---

## 6. Core Workflow

## Step 1: Ingest

把资料统一收到 `kb/inbox/` 或 `kb/raw/`。

来源包括：

- 现有 repo 文档
- 网页剪藏
- 图片
- PDF
- 外部 LLM 回答
- 命令输出
- 实验记录

### 最低要求

- 每批资料都要有来源路径
- 不要求一开始就干净
- 先收，再编译

## Step 2: Compile

让 LLM 做“知识编译”，而不是直接问答。

编译动作包括：

1. 抽取摘要和元数据
2. 归类到主题
3. 找到重复和冲突
4. 生成主题页和概念页
5. 回写索引页

这一步最适合结合你刚做的 `files-to-requirements` skill。

## Step 3: Normalize

做统一化处理：

- 术语统一
- 标题统一
- 文件命名统一
- 链接补齐
- 旧文档标记 superseded

## Step 4: Operate

在已有 wiki 上做真实工作输出：

- 需求澄清
- 方案对比
- SRE 监控项
- Incident pre-check
- Runbook
- 培训材料
- 英文说明

## Step 5: File Back

把高价值结果回写到 wiki 或 ops 文档中。

不是所有输出都要回写，但这几类应该尽量回写：

- 稳定结论
- 常见问题
- 方案最终版
- 通用排障路径
- 监控标准

## Step 6: Health Check

定期跑“知识库体检”，这是你最容易把 LLM 用出价值的地方。

检查内容：

- 重复知识
- 冲突结论
- 过期方案
- 没有索引到的高价值文档
- 应该升级成 wiki 页的候选文档

---

## 7. What Not To Build First

你现在不应该优先做这些：

- 大而全的向量数据库平台
- 在线多用户知识库产品
- 复杂权限系统
- 自研前端搜索产品
- 先做微服务化 ingest pipeline

### 原因

你的问题不是“检索能力不够”，而是“知识没有被编译成稳定结构”。

如果知识结构没建立好，上 RAG 只是把脏文档更快地喂给模型。

---

## 8. Best-Fit Tooling for You

## Frontend

- Obsidian 继续做主前端

理由：

- 你本来就在 Markdown 工作流里
- 适合浏览原始资料、编译结果和派生产出
- 适合 backlinks、graph、图片本地化

## Authoring Engine

- Codex / Claude Code 这类本地代理继续做“编译器”

职责：

- 收集目录
- 读取文档
- 生成结构化页
- 更新索引
- 输出报告

## Search

V1 用简单搜索就够了：

- `rg`
- 目录索引页
- 手工维护少量 `index.md`

如果后续文档量到几十万字以上，再补本地搜索 CLI 即可。

## Output Formats

优先保留这些：

- Markdown
- Mermaid
- Marp
- CSV / checklist
- PNG 图表

这跟你的工作交付物最匹配。

---

## 9. How This Maps to Your Job

这是最关键的一段。你的知识工作台不应该是“个人学习仓库”，而应该是“架构与运行知识引擎”。

### 你最适合沉淀的 6 类资产

1. 架构模式
   - GKE / PSC / ILB / Kong / Nginx / Cloud Armor 链路模式

2. 方案对比
   - 例如 PSC vs Peering vs NEG
   - Gateway vs Kong vs Nginx

3. 运行知识
   - SRE 监控项
   - alert model
   - runbook
   - rollback path

4. 接入与交付模板
   - onboarding checklist
   - requirement brief
   - validation checklist

5. 英文表达资产
   - architecture explanation
   - escalation mail
   - summary deck

6. 个人决策资产
   - 为什么某方案被选中
   - 哪些坑已经踩过
   - 哪些结论已废弃

### 这会直接帮助你的场景

- 做方案时，不再每次从零组织材料
- 做排障时，可以按链路快速落到已知知识页
- 做 SRE 要求时，可以从已有监控模式页派生
- 做英文沟通时，可以从知识页自动转写
- 做跨团队说明时，可以输出更稳定、更可复用的文档

---

## 10. Suggested V1 Implementation Plan

## Phase 1: 先把规则立起来

建议你先落这几个约定：

1. 新增 `kb/raw/`
2. 新增 `kb/wiki/`
3. 新增 `kb/outputs/`
4. 新增 `kb/checks/`
5. 每个主题至少有一个 `index` 或 `summary` 页

## Phase 2: 先挑 2 到 3 个高价值主题试跑

建议直接选：

1. `gcp/cross-project/`
2. `kong/`
3. `sre/`

原因：

- 最贴近你当前工作
- 文档已经很多
- 很容易产生重复知识和版本冲突
- 最能体现“编译型知识库”的价值

## Phase 3: 固化 3 个最常用编译动作

1. 目录 -> 主题摘要
2. 多文件 -> 需求澄清
3. 主题知识 -> SRE / Runbook / 架构说明

## Phase 4: 增加健康检查

每周或每两周跑一次：

- 重复检测
- 冲突检测
- 过期结论检测
- 缺失索引检测

---

## 11. Concrete Recommendation for You

如果只给一个最实际的建议：

**不要把你的 repo 先改造成“问答知识库”，而是改造成“LLM 可持续编译的 Markdown wiki”。**

对你来说，最值得做的产品化方向不是搜索，而是这条流水线：

```text
收资料
  -> 编译成主题页
  -> 从主题页生成需求/方案/SRE文档
  -> 把产出回写成长期资产
  -> 定期体检修正
```

这条路径和你的职业完全贴合，因为你的核心产出本来就是“把复杂系统讲清楚、落清楚、跑稳”。

---

## 12. Next Best Actions

如果你要继续往前推，我建议下一步按这个顺序做：

1. 在 repo 里创建 `kb/` 四层目录
2. 选 `gcp/cross-project/` 作为第一批试点
3. 我帮你写一个“目录编译到 wiki”的 skill 或脚本
4. 再补一个“知识库 health check” skill
5. 最后再决定要不要加轻量搜索或本地 RAG

如果这个方向对，你下一步最合理的动作不是继续讨论概念，而是让我直接把 `kb/` 目录骨架和第一版编译规范给你搭出来。
