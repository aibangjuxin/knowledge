# GCP 平台工程 — Hermes 4-Bot 团队

> 一个 GCP 平台工程团队由 4 个隔离的 Hermes profile bot 组成。每个 bot 有独立 SOUL、memory、skills,职责边界清晰,通过 Bot Chat 协作。本文档记录团队结构、协作协议、bootstrap 流程与实战验证结果。

---

## 目录

1. [为什么要这样做](#1-为什么要这样做)
2. [4-Bot 团队结构](#2-4-bot-团队结构)
3. [Bot Chat 协作协议](#3-bot-chat-协作协议)
4. [Handoff 消息模板](#4-handoff-消息模板)
5. [Bootstrap 流程](#5-bootstrap-流程)
6. [实战验证结果](#6-实战验证结果)
7. [踩过的坑](#7-踩过的坑)
8. [扩展指南](#8-扩展指南)
9. [权威依据](#9-权威依据)

---

## 1. 为什么要这样做

传统方式:单个 Claude Code / Codex 跑全场,角色边界靠 prompt 模糊约束。问题:
- **上下文污染**:架构师不需要看到 MLOps / IM 工具的 skill description
- **记忆串味**:agent 写"cron 模板"和"架构选型"塞同一份 MEMORY,越来越臃肿
- **角色越界**:一个对话里既设计又实现又测试,边界不自觉松

**Profile-as-bot 模式**:
- 每个 bot 是独立 Hermes profile (`~/.hermes/profiles/<name>/`),有独立 `SOUL.md` / `MEMORY.md` / `skills/` / `cron/`
- 强制职责分离:bot 的 SOUL 明确"做什么 / 不做什么",越界由 prompt 自我约束
- Bot Chat 跨 profile 通信:`hermes -p <other-bot> chat` 显式发起,traceable
- 上下游关系:架构师 → 基建 → DevOps + QA,QA 反馈给任一上游,形成闭环

---

## 2. 4-Bot 团队结构

```
        ┌──────────────────┐
        │  architect-gcp   │  设计 / 选型 / ADR / 架构图
        └────────┬─────────┘
                 │ ADR + 架构图 + 关键 placeholder
                 ▼
        ┌──────────────────┐
        │   infra-gcp      │  provision / IaC / 脚本 / 环境 bootstrap
        └────────┬─────────┘
                 │ 环境 + 启动方式 + runbook
                 ▼
        ┌──────────────────┐
        │   devops-gcp     │  CI/CD / onboarding / 监控告警
        └────────┬─────────┘
                 │ pipeline + dashboard + runbook
                 ▼
        ┌──────────────────┐
        │    qa-gcp        │  验证 / 故障演练 / 合规审计
        └────────┬─────────┘
                 │ 验证报告 / 缺陷 (闭环)
                 ▼
        (回到 architect-gcp, 或打回任一上游)
```

### Bot 详情

| Bot | Wrapper | 主要职责 | 主要 Skills | SOUL/MEMORY |
|---|---|---|---|---|
| `architect-gcp` | `architect-gcp` | 架构设计 / ADR 撰写 / 可行性 & POC / 选型对比 / 架构图 | `architecture-diagram` + `architectrue` + `cross-project-mig-nginx-edge` + `gcp-cross-project-resource-scoping` + `gke-pv-multi-tenant-isolation` 等 7 | 6.4K / 2.2K |
| `infra-gcp` | `infra-gcp` | 资源 provision / IaC / 启动脚本 / 环境 bootstrap / 凭据模板 | `gcloud` + `gke-basics` + `google-cloud-recipe-onboarding` + `google-cloud-waf-cost-optimization` + `cert-format-preflight` 等 | 6.5K / 2.8K |
| `devops-gcp` | `devops-gcp` | CI/CD pipeline / onboarding 自动化 / 监控告警 / 凭据轮换 / release engineering | `github-pr-workflow` + `github-issue-to-pr` + `google-cloud-recipe-onboarding` + `google-cloud-waf-reliability` 等 | 5.4K / 2.1K |
| `qa-gcp` | `qa-gcp` | 端到端验证 / 安全合规审计 / 故障演练 / cert chain 验证 / 审计日志核查 | `pod-tls-cert-verification` + `cert-format-preflight` + `google-cloud-waf-reliability` + `google-cloud-waf-security` + `google-cloud-networking-observability` 等 | 6.1K / 2.1K |

### 共享资产

| 资产 | 共享方式 | 说明 |
|---|---|---|
| `USER.md` | 从 architecture profile 复制 | Lex 全部偏好(写作纪律 / 命名约定 / 完整交付三件套 / 脱敏等) |
| `MEMORY.md` | 每个 bot 自己精简 | 仅保留本角色相关的 GCP / shell / 排错经验 |
| `SOUL.md` | 每个 bot 自己专属 | 身份 / 职责 / 边界 / 交接协议 / Skills 优先级 |
| `.env` | 从 architecture profile `cp` 复制 | 同一把 `MINIMAX_CN_API_KEY`,strip `MESSAGING_CWD` deprecated 行 |
| `config.yaml` | `hermes --profile <bot> config set` | 统一 `MiniMax-M3` + `minimax-cn` |

---

## 3. Bot Chat 协作协议

### 3.1 发送消息

```bash
# 1. 把消息写到 /tmp/dm.txt
cat > /tmp/dm.txt <<'EOF'
Message from 🤖 <sender-bot> (@<sender-profile>):

<real message body, following the handoff template below>
EOF

# 2. 让接收方读取并回复
hermes -p <receiver-bot> chat --in ~ -c "Bot Chat" --create-if-missing -Q --query-file /tmp/dm.txt
```

**关键点**:
- 消息前缀 `Message from 🤖 <bot-name> (@<profile>):` 是必需的 — 接收方据此识别 sender 身份
- `--in ~` 让 bot 从 home 目录启动(继承当前 cwd)
- `--create-if-missing` 第一次自动创建 "Bot Chat" session,后续复用同一会话
- `-Q` 静默 banner,只看实质回复
- `--query-file` 走 file 而非 inline,避免引号截断 / `$( )` 执行风险

### 3.2 接收消息

Bot 在 "Bot Chat" session 启动时,**自动加载该 session 的所有历史消息**。sender 的新消息和 receiver 的旧回复都在 context 里。

### 3.3 Round-trip 模式

**不要 one-shot** — 每次 handoff 后要求 explicit ack,形成闭环:

```
architect-gcp  →  infra-gcp     (handoff)
infra-gcp      →  architect-gcp  (ack: 收到了 + 我会做 X)
architect-gcp  →  devops-gcp     (next handoff)
...
```

验证 ack 让 sender 确认消息真的被接收 + receiver 正确理解 scope + 没有越界风险。

---

## 4. Handoff 消息模板

每个 bot 的 SOUL.md 都强制要求 handoff 消息含 **What / Why / Where to start / Known pitfalls** 4 段。这不是形式主义 — 这 4 段是 load-bearing wall,pitualls 段尤其关键(下游 Bot 在那里抓住上游没看到的 scope bleed)。

### 4.1 architect → infra handoff

```markdown
Message from 🤖 architect-gcp (@architect-gcp):

Handing off ADR-XXX to infra-gcp for execution. The artifact is...

**What**: [具体的 provision 清单 / 资源类型 / region / project]
**Why**: [1-3 句设计意图]
**Where to start**: [ADR 具体章节 + 入口命令]
**Known pitfalls**: 
- [陷阱 1: 具体 gcloud bug / API 限制 / 配额]
- [陷阱 2: ...]
- [陷阱 3: ...]

Standing by — once resource IDs land, I'll update ADR-XXX with the traced-back config.
```

### 4.2 architect → devops handoff

```markdown
Message from 🤖 architect-gcp (@architect-gcp):

Handing off ADR-XXX to devops-gcp. The artifact is the CI/CD pipeline design...

**What**:
- **CI/CD tool**: [Cloud Build / GitHub Actions + 理由]
- **Triggers**: [PR / main / tag — 各自行为]
- **Promotion path**: [dev → staging → prod 的门控]

**Why**: [1-3 句]

**Where to start**: [具体 config 文件路径 + 触发器创建命令]

**Known pitfalls**:
- [陷阱 1]
- [陷阱 2]
- [陷阱 3]
```

### 4.3 architect → qa handoff

```markdown
Message from 🤖 architect-gcp (@architect-gcp):

Handing off ADR-XXX verification scope to qa-gcp. The artifact is the end-to-end verification checklist for [deployed state].

**What — scope (N lanes)**:
1. [Lane 1: 网络可达性]
2. [Lane 2: IAM 绑定]
3. [Lane 3: ...]
4. ...
5. ...

**Why — what's at stake**: [production-gating / blast-radius / SOC]

**Where to start**: [验证命令分类 + 执行顺序]

**Known pitfalls — N traps**:
- [陷阱 1: silent pass on size-0 / 默认 VPC 污染 / cert preflight looping / 缺 negative test / sink IAM drift / region vs zone]
- ...
```

### 4.4 跨阶段反馈(infra → qa / devops → qa / qa → 上游)

反馈必须含 **What checked / What failed / Reproducer / Owning Bot / Severity**,禁止 "looks fine" / "LGTM":

```markdown
Message from 🤖 qa-gcp (@qa-gcp):

Verification FAIL on Lane 3 (MIG state).

**What was checked**: `gcloud compute instance-groups managed describe adr-001-mig`
**What failed**: instanceTemplate references `template-v1` but ADR-XXX specifies `template-v2`
**Reproducer**: [exact command + actual output]
**Owning Bot**: architect-gcp (template version mismatch in §3) → infra-gcp (apply wrong template)
**Severity**: blocker (can't proceed to prod gate)

Not silently passing.
```

---

## 5. Bootstrap 流程

### 5.1 创建 profile

```bash
hermes profile create <bot-name>
# → ~/.hermes/profiles/<bot-name>/
# → wrapper script /Users/lex/.local/bin/<bot-name>
```

### 5.2 复制共享资产

```bash
PROFILE=~/.hermes/profiles/<bot-name>

# USER.md (完整 Lex 偏好)
cp ~/.hermes/profiles/architecture/memories/USER.md $PROFILE/memories/USER.md

# .env (strip deprecated MESSAGING_CWD)
grep -v "^MESSAGING_CWD" ~/.hermes/profiles/architecture/.env > $PROFILE/.env
chmod 600 $PROFILE/.env
```

### 5.3 配置 model

```bash
hermes --profile <bot-name> config set model.default MiniMax-M3
hermes --profile <bot-name> config set model.provider minimax-cn
```

### 5.4 写角色专属文件

每个 bot 的 SOUL.md 和 MEMORY.md **手工撰写** — 不同角色边界、Skills 优先级、相关经验都不同。模板见 §5.6。

### 5.5 复制 hub skills 并裁剪

```bash
# google/ 从 architecture profile 复制
cp -R ~/.hermes/profiles/architecture/skills/google $PROFILE/skills/google

# 按角色裁剪(详见 §5.7)
cd $PROFILE/skills/google
mkdir -p _unused/skills/cloud
# 把非本角色用的 skill mv 到 _unused/
```

⚠️ **关键陷阱**:`cp -R src/ dst/` 会嵌套成 `dst/src/`。必须用 `cp -R src/. dst/`(带 `.`),或者确保 `dst/` 不存在。

### 5.6 SOUL.md 模板要点

```yaml
## Identity — <一句话身份>

## 核心职责 — What I DO (5-8 条具体职责)

## 核心边界 — What I DON'T DO (4-6 条明确拒绝的事)

## 交接协议 — Handoff
### Upstream (从哪个 bot / 接收什么)
### Downstream (交给哪个 bot / 交付什么)

## 架构纪律 — Lex's preferences
(直接引用 USER.md 的核心纪律)

## Core Truths
(简化的 Hermes SOUL 通用原则)

## Skills (in priority order)
(列出 10-15 个本角色用得到的 skill,按加载优先级)

## Boundaries & Safety
(prod mutation / 跨 profile / 审计等红线)

## Continuity
(MEMORY.md / SOUL.md 是你的记忆)

## Vibe
(一句收尾)
```

### 5.7 Skills 裁剪矩阵

| Bot | 保留 | 归档 |
|---|---|---|
| `architect-gcp` | `architecture-diagram` + `architectrue` + GCP cross-project skills + `obsidian` + `grounded-citations` | provisioning / pipeline / testing 工具 |
| `infra-gcp` | `gcloud` + `gke-basics` + `recipe-onboarding` + `recipe-auth` + `waf-cost-optimization` + `cert-format-preflight` + `shell-review` | architect-only + qa-only + ML/data + 全套 social-media / apple / email |
| `devops-gcp` | `github-*` (7 个) + `devops/*` (git / hermes-cron / ffmpeg / kanban) + `recipe-onboarding` + `waf-reliability` | provisioning-only (gcloud / gke-basics) + qa-only + ML |
| `qa-gcp` | `waf-reliability` + `waf-security` + `networking-observability` + `waf-cost-optimization` + `pod-tls-cert-verification` + `cert-format-preflight` + `shell-review` | 全部 provisioning / pipeline / 创作工具 |

**每个 bot 保留 5-12 个核心 skill**,其余归档到 `_unused/` 物理目录(为以后恢复保留,只是不让 bot 在 system prompt 里看到)。

---

## 6. 实战验证结果

### 6.1 Smoke test 全员通过

4 个 bot 启动后都被问"你是谁 / 做什么 / 不做什么",回答一致:

| Bot | 身份 ✓ | 3 职责 ✓ | 3 边界 ✓ | 4-Bot 关系 ✓ |
|---|---|---|---|---|
| `architect-gcp` | ✅ | ✅ | ✅ | ✅ |
| `infra-gcp` | ✅ | ✅ | ✅ | ✅ |
| `devops-gcp` | ✅ | ✅ | ✅ | ✅ |
| `qa-gcp` | ✅ | ✅ | ✅ | ✅ |

每个 bot 都**准确**说出上下游 Bot 名字,说明 SOUL.md / MEMORY.md 都被正确加载。

### 6.2 Round-trip 通信验证

#### A. architect → infra → architect

1. architect-gcp 收到"给 infra-gcp 写 ADR-001 handoff" → 生成完整 handoff(What/Why/Where/Pitfalls 4 段,严格遵守 SOUL.md 协议,提到 `gcloud compute instance-groups managed create` 默认 size1 陷阱,引用 Lex "ID 可追溯" 偏好)
2. infra-gcp 接收 → 识别为 channel test,**主动拒绝 provision**("zero infrastructure changes made"),完全遵守 SOUL.md 边界
3. architect-gcp 收到回执 → 准确描述真实项目下给 devops-gcp 和 qa-gcp 的分工(Cloud Build 触发器 / health checks / autoscaling probes)

#### B. architect → devops / qa → architect

1. architect-gcp 同时生成 ADR-002 给 devops-gcp(5 真实陷阱:MIG rolling update on size-0 hang、WIF vs JSON key、TF plan in PR、state file location、branch protection)和 ADR-002 给 qa-gcp(5 验证陷阱:silent pass on size-0、默认 VPC 污染、cert preflight looping、缺 negative test、sink IAM drift)
2. devops-gcp 接收 → §6 push-back 选择 **Cloud Build**(理由: GCP-native + SA impersonation + 与 architect-gcp 的 infra handoff 一致 + 以后可逆),**不会写任何 pipeline YAML**
3. qa-gcp 接收 → 抓到 Network Policy existence-vs-effectiveness 陷阱 + cert CRLF/BOM 陷阱,**主动确认 Lex MEMORY 的 cert preflight 规则**
4. architect-gcp 最终总结:"4-Bot chain holds cleanly... What/Why/Where/Pitfalls 顺序是 load-bearing... round-trip acks 比 one-shot handoffs 强"

### 6.3 关键观察

- **Pitfalls 段是 load-bearing wall**:不是装饰。每个 bot 的真实价值在于抓到上游没看到的 scope bleed(如 devops-gcp 推 Cloud Build 时的 reversible 论证、qa-gcp 提的 Network Policy 实战验证)
- **Round-trip ack 比 one-shot 强**:infra-gcp 主动说"channel test, zero infra changes",这就是 SOUL.md 边界生效 — 比 silent pass 强 10 倍
- **每个 bot 自带 Lex 偏好继承**:architect-gcp 主动用"覆盖双向"、"完整交付三件套"、"ID 可追溯"等概念,qa-gcp 主动确认 cert preflight 规则

---

## 7. 踩过的坑

### 7.1 cp -R src/ dst/ 会嵌套成 dst/src/

**症状**:`cp -R ~/.hermes/profiles/architecture/skills/devops ~/.hermes/profiles/devops-gcp/skills/devops` → 结果是 `devops-gcp/skills/devops/devops/`

**根因**:`cp -R src/ dst/` 把 src 的 basename 也带上,所以 dst 变成 `dst/<src-basename>/`。

**正确做法**:
```bash
cp -R src/. dst/  # 带 . 表示"src 的内容"
# 或
rm -rf dst && cp -R src/ dst/  # 先确保 dst 不存在
```

### 7.2 Builtin skills 物理裁剪无效

**症状**:把 builtin skill(apple/email/mlops) 移到 `_unused/` 目录后,smoke test 启动 bot 时,Hermes 又把 builtin reseed 回 `skills/` 顶层。

**根因**:Hermes 在第一次 `chat` 启动时把 builtin skills reseed 到 profile。物理移动只会影响当次启动前的 state,启动时被覆盖。

**正确做法**:
- 不要靠物理裁剪 builtin skills
- 在 SOUL.md 的 Skills 段落明确"必装 vs 不要关注",让 bot 自我约束
- 或者用 `hermes skills config`(interactive UI,目前 agent 不能用)

### 7.3 Profile 共享 API key

**症状**:每个 bot 都用同一把 `MINIMAX_CN_API_KEY`,但 `.env` 在 profile 创建时是空的。

**正确做法**:
```bash
# 1. 把 architecture profile 的 .env 复制(agent 可以 cp,不暴露内容)
cp ~/.hermes/profiles/architecture/.env ~/.hermes/profiles/<bot>/.env
chmod 600 ~/.hermes/profiles/<bot>/.env

# 2. 删除 deprecated MESSAGING_CWD 行(从 architecture profile 复制过来的)
grep -v "^MESSAGING_CWD" ~/.hermes/profiles/<bot>/.env > /tmp/cleaned && mv /tmp/cleaned ~/.hermes/profiles/<bot>/.env
```

**为什么不自动复制**:即使技术上可行,跨 profile 复制 secret 应该用户显式授权 — 跟创建 SOUL.md/MEMORY.md 时 `cross_profile=True` 同原则。

### 7.4 Deprecated MESSAGING_CWD 警告

**症状**:`MESSAGING_CWD=/Users/lex/.openclaw/workspace` 在 architecture profile 的 `.env` 里,被 Hermes 标记 deprecated。

**修法**:bot 用不到 messaging,直接 grep -v 删掉那行。

### 7.5 Agent 看到 builtin 82 全部 enabled

**症状**:`hermes --profile <bot> skills list` 显示全部 82 个 builtin skill 都是 `enabled`,即使物理归档了 75 个。

**根因**:这是 Hermes 的 built-in skill registry,跟磁盘位置不完全挂钩。`_unused/` 不影响 enabled 状态。

**实际影响**:session 启动时 82 个 builtin skill 都注入 system prompt,占 context token。但 hermes-agent 本身按"按需加载 SKILL.md"工作 — 没用到的 skill 不增加 token,只是名字出现在列表里。

**接受**:可以接受,只在真用 skill 时(`skill_view`)才加载完整内容。

---

## 8. 扩展指南

### 8.1 加第 5 个 bot (sre-gcp)

```bash
# 1. 复制 bootstrap 模板
cp /tmp/bootstrap_infra.sh /tmp/bootstrap_sre.sh
# 改里面的 PROFILE_DIR、SOURCE 路径、SOUL/MEMORY 引用

# 2. 写 SRE 专属 SOUL.md + MEMORY.md
# - SOUL: 职责 = 生产稳定性 / oncall / 事故响应 / 容量规划 / SLO 治理
# - SOUL: 边界 = 不做架构设计 / 不 provision / 不写 pipeline / 不做业务测试
# - 上下游: 从 qa-gcp 接验证报告 + 报警;反馈给 architect-gcp 容量规划建议

# 3. Skills: 保留 SRE 专用
# - google-cloud-waf-reliability (SLO 治理)
# - macos-launchd-services (oncall 自动化)
# - 暂不需要更多,其余靠 ad-hoc

# 4. 跑 bootstrap + smoke test
bash /tmp/bootstrap_sre.sh
sre-gcp chat -c "Bot Chat" -Q --query-file /tmp/sre_smoke.txt
```

### 8.2 加新角色(产品/前端/数据)

**SOUL.md 模板不变**,但需要:
- 重新定义职责 / 边界
- 重选 skills 矩阵(产品可能用 `notion` / `airtable`,前端用 `creative/architecture-diagram` + `sketch`,数据用 `mlops`)
- 重写精简的 MEMORY.md

### 8.3 跨 bot 共享 MEMORY 笔记

当前每个 bot 自己的 MEMORY 是独立的。如果某条 Lex 偏好要在所有 bot 都生效,**写在 USER.md 而不是 MEMORY.md**。USER.md 是 user-level preferences,MEMORY.md 是 agent-level notes。

### 8.4 监控 4-Bot 健康度

```bash
# 列出所有 profile + model + gateway 状态
hermes profile list

# 检查每个 bot 的最近 session 是否有错误
hermes --profile <bot> sessions list

# 检查每个 bot 的 cron jobs(每个 bot 独立)
hermes --profile <bot> cron list
```

---

## 9. 权威依据

### Hermes 官方

- **Profile 模型**:每个 profile 是独立 agent,有专属 skills / memories / cron / plugin,Bot 之间通过 `hermes -p <name> chat` 通信 — 见 `hermes-agent` skill
- **Cross-profile write guard**:write_file 拒绝写到其他 profile 的 skills/memories/cron/plugins,需要 `cross_profile=True` — 设计意图是 agent 不误改其他 profile 配置
- **Python Runtime Environment**:`/opt/homebrew/Caskroom/miniconda/base/bin/python`,hermes-agent v0.12.0 editable install 在 `~/.hermes/hermes-agent/`

### Lex 偏好(从 USER.md 继承)

- **完整交付三件套**:答案 + 来源 + 命令输出。Lex 偏好引用 Google docs 原话 + GitHub issue 实证
- **覆盖双向**:架构图必须覆盖正向 + 反向(谁连谁 / 谁授权 / 审计落哪)
- **ID 可追溯**:架构图 / 文档里出现的所有 ID 都要可追溯回配置细节,不能黑箱
- **真实环境标识符脱敏**:commit 前 redact org name / numeric ID / hostname / API gateway / domain suffix

### 实战验证(2026-08-21)

- 4 bot 全部 smoke test 通过
- architect → infra / devops / qa 三条 round-trip 全部闭环
- 每个 bot 准确按 SOUL.md 边界行事(infra 拒绝 test provision、qa 不 silent pass、devops 不写 pipeline)