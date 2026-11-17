# 4-Bot 团队使用指南

> 速查手册: 跟哪个 bot 对话、发什么格式的消息、什么时候越界。

---

## 🚀 一分钟上手

```bash
# 列所有 bot
hermes profile list

# 跟单个 bot 对话(交互式)
architect-gcp chat
infra-gcp chat
devops-gcp chat
qa-gcp chat

# 单条 query
infra-gcp chat -q "按 ADR-007 把 dev 环境 provision 起来"

# 看 session 历史
hermes --profile architect-gcp sessions list
```

---

## 📋 速查 — 4 个 bot 的边界

| 我想做... | 应该找 | **不**应该找 |
|---|---|---|
| 设计新架构 / 写 ADR / 选型对比 / 画架构图 | `architect-gcp` | infra / devops / qa |
| 实际 `gcloud create` / `terraform apply` / `kubectl apply` | `infra-gcp` | architect / devops / qa |
| 写 `.github/workflows/` / Cloud Build / onboarding runbook | `devops-gcp` | architect / infra / qa |
| 验证 cert chain / Network Policy / 跑故障演练 / 出验证报告 | `qa-gcp` | architect / infra / devops |
| 调研 GCP 文档 / 找 Google 官方原话 | `architect-gcp` (有 `vendor-docs-research`) | 其他 |
| 写脚本 bootstrap 环境 / 准备 engineer onboarding 脚本 | `infra-gcp` | 其他 |
| 监控 dashboard / 告警策略 / SLO 治理 | `devops-gcp` | 其他 |

**核心规则**:每个 bot **拒绝**做上游的活儿。看到越界请求会**明确拒绝**并 hand off 给对的 bot。

---

## 🤝 Bot Chat 协作(给 bot 用,人类可参考)

### 发送 handoff 给另一个 bot

```bash
# 1. 写到 /tmp/dm.txt
cat > /tmp/dm.txt <<'EOF'
Message from 🤖 <sender-bot> (@<sender-profile>):

<real handoff content following the 4-section template>
EOF

# 2. 接收方读
hermes -p <receiver-bot> chat --in ~ -c "Bot Chat" --create-if-missing -Q \
       --query-file /tmp/dm.txt
```

### Handoff 消息模板(4 段)

每个 bot 的 SOUL.md 都强制要求 **What / Why / Where to start / Known pitfalls** 4 段。

**architect → infra**:
```markdown
**What**: [具体的 provision 清单 / 资源类型 / region / project]
**Why**: [1-3 句设计意图]
**Where to start**: [ADR 具体章节 + 入口命令]
**Known pitfalls**: 
- [陷阱 1: 具体 gcloud bug / API 限制 / 配额]
- [陷阱 2: ...]
- [陷阱 3: ...]
```

**architect → devops**:
```markdown
**What**:
- **CI/CD tool**: [Cloud Build / GitHub Actions + 理由]
- **Triggers**: [PR / main / tag — 各自行为]
- **Promotion path**: [dev → staging → prod 的门控]
**Why**: [...]
**Where to start**: [具体 config 文件路径 + 触发器创建命令]
**Known pitfalls**: [...]
```

**architect → qa**:
```markdown
**What — scope (N lanes)**: [网络 / IAM / MIG state / audit log / cert chain ...]
**Why — what's at stake**: [production-gating / blast-radius / SOC]
**Where to start**: [验证命令分类 + 执行顺序]
**Known pitfalls — N traps**: [silent pass / 默认 VPC 污染 / cert preflight looping ...]
```

### 反馈(下游 → 上游)

禁止 "looks fine" / "LGTM"。每个 gap 必须含:
- **What was checked**
- **What failed**
- **Reproducer** (exact command + output)
- **Owning Bot**
- **Severity**

---

## 🔁 典型工作流

### 场景 1:新功能上线

```
1. 你跟 architect-gcp 说"设计 X 功能怎么落"
2. architect-gcp 输出 ADR + 架构图
3. architect-gcp 给 infra-gcp 发 handoff
4. infra-gcp provision 资源,给你 runbook
5. infra-gcp 给 devops-gcp 发 handoff
6. devops-gcp 写 pipeline + 监控 + onboarding
7. devops-gcp 给 qa-gcp 发 handoff
8. qa-gcp 跑验证清单,出验证报告
9. qa-gcp 反馈 blocker 给 devops-gcp / infra-gcp / architect-gcp(任一)
```

### 场景 2:线上事故

```
1. 你跟 qa-gcp 说"X 服务故障,验证一下"
2. qa-gcp 跑 cert chain / Network Policy / 监控数据
3. qa-gcp 报根因 + 缺陷给 architect-gcp(架构问题)/ infra-gcp(资源问题)/ devops-gcp(监控盲区)
4. 对应 bot 修复
6. qa-gcp 复测,出 "before/after" 报告
```

### 场景 3:工程师 onboarding

```
1. 你跟 devops-gcp 说"给新人 Y 准备 onboarding"
2. devops-gcp 写 runbook(必装 tools / IAM 绑定 / 凭据 / kubectl context)
3. devops-gcp 跟 infra-gcp 协调环境 access
4. 新人按 runbook 30 分钟到位
```

---

## ⚠️ 常见越界场景(不要犯)

| 越界请求 | 谁会拒 | 正确处理 |
|---|---|---|
| "帮 architect-gcp 跑一下 terraform plan" | architect-gcp 拒绝 | → infra-gcp |
| "让 devops-gcp 验证一下 cert chain" | devops-gcp 拒绝 | → qa-gcp |
| "让 infra-gcp 写 .github/workflows/" | infra-gcp 拒绝 | → devops-gcp |
| "让 qa-gcp 改个配置" | qa-gcp 拒绝 | → infra-gcp(devops-gcp 验证后改) |
| "4 个 bot 一起讨论 X" | 每个 bot 各自定义边界 | 把任务拆成"设计 → 实现 → 测试",分发给对应 bot |

---

## 🛠️ 怎么加 / 改 / 删一个 bot

### 加新 bot(以 `sre-gcp` 为例)

```bash
# 1. 写 4 个文件
# - SOUL.md: 身份 / 职责 / 边界 / 交接协议
# - MEMORY.md: 本角色相关经验
# - USER.md: 从 architecture profile 复制
# - .env: 从 architecture profile 复制(strip deprecated 行)

# 2. 复用 bootstrap 模板
cp /tmp/bootstrap_infra.sh /tmp/bootstrap_sre.sh
# 改 PROFILE_DIR / SOURCE 路径 / SOUL / MEMORY 引用

# 3. 跑
bash /tmp/bootstrap_sre.sh
sre-gcp chat -c "Bot Chat" -Q --query-file /tmp/sre_smoke.txt
```

详细见 `README.md` §5 Bootstrap 流程。

### 改 bot 的 SOUL

⚠️ SOUL 改动会影响该 bot 之后所有 session 的行为,谨慎:

```bash
# 1. 改 SOUL.md
vi ~/.hermes/profiles/<bot>/SOUL.md

# 2. 重启 bot 的 gateway session(如果运行中)
hermes --profile <bot> gateway restart

# 3. 验证
<bot> chat -c "Bot Chat" -Q --query-file /tmp/verify.txt
```

### 删 bot

```bash
hermes profile delete <bot-name>
# → 删除 ~/.hermes/profiles/<bot>/ + wrapper script
```

---

## 📊 健康度监控

```bash
# 列出所有 profile + 当前状态
hermes profile list

# 看某个 bot 的最近 session
hermes --profile <bot> sessions list

# 看 cron jobs(每个 bot 独立)
hermes --profile <bot> cron list

# 看 bot 的 MEMORY 大小(避免 context 压力)
wc -c ~/.hermes/profiles/<bot>/memories/MEMORY.md
# 建议 < 2500 chars,精简到本角色相关
```

---

## 🧰 模板文件位置

| 文件 | 路径 | 用途 |
|---|---|---|
| Bootstrap 脚本 | `/tmp/bootstrap_*.sh` | 3 个示例(infra/devops/qa) |
| `.env` wrapper | `/tmp/wxwrap.sh` | WeChat API 推送(避免 IFS 空格陷阱) |
| `wxwrap.sh` 复用 | `~/.hermes/scripts/` | 以后可以挪过去供其他脚本复用 |
| 团队 README | `~/git/knowledge/devops/hermes-bot-team/README.md` | 完整结构 / 协议 / 验证结果 |
| 团队 usage | `~/git/knowledge/devops/hermes-bot-team/usage.md` | 本文件 |

---

## 💡 经验教训(踩过的坑)

1. **`cp -R src/ dst/` 会嵌套** → 用 `src/.dst/` 或先 `rm -rf dst`
2. **builtin skills 物理裁剪无效** → smoke test 后被 reseed,用 SOUL.md 约束
3. **`wechat-draft.py` 用错 type=image** → 必须 `type=thumb` 上传才能进 `draft/add`(见 `wechat-official-account-publishing` skill §4 P9)
4. **memory tool drift guard** → 写 MEMORY.md 失败时不要硬撑,改用脚本 / 文档 / skill 持久化
5. **每个 bot `.env` 必须从 architecture 复制 + strip MESSAGING_CWD**,否则 smoke test 报 "No usable credentials"
6. **5 段模板的 Pitfalls 段是 load-bearing wall** — 不是装饰,下游 bot 在那里抓上游没看到的 scope bleed

---

**有疑问?** 看 `README.md` 或问 architect-gcp。