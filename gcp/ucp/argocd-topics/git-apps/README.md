# git-apps/ · 自研 GitHub App（CR Check）专题

> **一句话**：我们要自己用 **Go** 写一个 GitHub App（暂名 **CR Check**），
> 部署到 GKE，对每个 PR 做「**变更单（CR）合规性**」门禁：
> PR 必须携带 CR 号 → CR 在内部 **CR 管理平台**上处于**可执行（implement/approved）状态**
> → 合并必须落在 **Maintenance Window** 内 → 否则**合不了**。

## 阅读顺序

| # | 文档 | 直接回答你的哪个问题 |
|---|---|---|
| 1 | [`Develop-git-apps.md`](./Develop-git-apps.md) | 「**要不要自研？自研要写多少代码？时间窗口难在哪？**」<br>可行性评估（自研 App vs Actions vs 纯配置）、R0–R13a 规则表、需求「6.1 合并门禁流程」八步映射、Go 技术栈与目录结构、24 条工程坑、M0–M7 路线图 |
| 2 | [`webhook-and-backend-service.md`](./webhook-and-backend-service.md) | 「**Webhook 到底是什么？我写的 Go 服务怎么变成一个 GitHub 能访问到的 URL？**」<br>一页纸总结 + 完整流程图、Webhook vs 后端服务、**Git → 生效的完整 8 步**、K8s 清单、GitHub App 后台逐项填什么、故障速查、本地调试 |
| 3 | [`12-webhook-push-vs-pull.md`](./12-webhook-push-vs-pull.md) | 「**有了 Webhook 之后，和 GitHub 的交互逻辑到底变了什么？**」<br>pull vs push 量化对比、**push 模式下的六个新契约**、扇出拓扑、迁移路线、反模式清单 |
| 4 | [`13-cr-check-go-design.md`](./13-cr-check-go-design.md) | 「**Go 代码怎么组织？要写哪些接口？怎么测？要多久？**」<br>需求边界与 MVP、架构图、包结构、**Go 接口定义**、数据模型与状态机映射、规则引擎、端点契约、`policy.yaml` 全量示例、测试策略、指标、**M0–M5 ≈ 17–25 人日**、风险表 |
| 5 | [`11-github-app-concepts.md`](./11-github-app-concepts.md) | 「**GitHub App 的那几个 URL 什么关系？源码在哪？规则该写在哪？**」<br>App / Installation / Private Key、四个 URL 对照表、源码的三种含义、**§3.4 自研场景的源码与部署**、四层拆解、**三层门禁架构**、R0–R12 规则表、Argo Workflows 能不能干这件事 |
| 6 | [`14-rulesets-and-gitapp-gate.md`](./14-rulesets-and-gitapp-gate.md) | 「**GitHub Rulesets 怎么配？怎么和 GitHub App 联合成合并门禁？**」<br>零基础 Ruleset 教程（分层/叠加/enforcement/bypass）、25 条 API 规则清单、**Ruleset ↔ App 的唯一耦合点 `integration_id`**、4 种静默失效、分层 ruleset 完整 JSON、与 release 流程 14 步的逐条映射、Merge Queue、18 条坑 |
| 7 | [`15-commit-message-cr-prefix.md`](./15-commit-message-cr-prefix.md) | 「**commit message 必须以 `CR123456` 开头，Ruleset 怎么配？**」<br>最小可跑示例：两个例子（正/反）、三层判定模型（L1 本地 hook / L2 Ruleset / L3 CR Check App）、两条最小 ruleset JSON、**RE2 正则约束**、**squash merge 时到底校验谁**、本地模拟器、Enterprise 降级方案 |
| 8 | [`16-ruleset-install-runbook.md`](./16-ruleset-install-runbook.md) | 「**JSON 怎么装上去才会生效？**」<br>组织级 vs 仓库级端点差异、**安装六步顺序**（App 先跑一次 check run）、UI 导入 / `gh api` / IaC / GitOps 四条路径、**PUT 是全量替换的坑**、**三层验证（配置+聚合+联调）**、熔断纪律、权限矩阵、**报错对照表** |
| 9 | [`17-probot-apps.md`](./17-probot-apps.md) | 「**Probot 是什么？我们为什么不用它？**」<br>Probot = 写 GitHub App 的 Node.js 脚手架、App/Installation/webhook/Octokit 核心概念、Hello World 源码、3 个环境变量与部署形态、生态现成 app 清单、**Probot vs 我们的 Go 版 CR Check 对照** |
| ★ | [`cr-check/`](./cr-check/) | **★ 可运行的 Go 实现**（本文档集的代码部分）<br>CR Check 服务的完整代码：`cmd/server` + 9 个 `internal` 包、策略配置、K8s 清单、测试脚本。<br>**30 秒跑起来** → 见 [`cr-check/README.md`](./cr-check/README.md) §0 |
| ★ | [`../examples/rulesets/`](../examples/rulesets/) | **★ 可直接下发的 Ruleset 配置 ＋ 契约静态检查 ＋ commit 前缀模拟器**<br>8 份 ruleset JSON（org 基线 / feature 规范 / dev / release / prod / push / **CR 前缀 ×2**）+ `apply-rulesets.sh` + `validate-rulesets.py` + `simulate-commit-gate.py` |

## 三句话记住这套东西

```
① GitHub App = 身份（机器人）+ 你自己服务器上的一个后端服务。
   "装到 Org" 只等于授予权限；逻辑生效 = 你的服务在线 + 分支保护要求了这个 check。

② Webhook URL = 事件通知的收件地址。
   ⚠️ 它在 Argo CD 场景指向既有组件（与业务应用上线无关）；
      但在自研场景下，它**恰恰就是**你部署的 Go 服务的公网地址（Ingress + 域名 + TLS）。
   两种"发布"必须分开 —— 见 doc 11 §5.5。

③ App 只是「哨兵 + 报数员」；真正拦住 merge 的是 GitHub 分支保护的 required status checks。
   部署侧还需要 Argo CD 同步门 + K8s 准入门兜底（三层门禁）。

④ GitHub Rulesets = 强制力那一层的现代写法。Ruleset 与 App 只有一个耦合点：
   required_status_checks 里的 context（= policy.yaml 的 checkName）+ integration_id（来源 App）。
   ★ 这条线接错 → 门禁**静默失效** → 见 doc 14 §4.5 + examples/rulesets/validate-rulesets.py。
```

## 核心链路（一图）

```
GitHub(PR 事件) ──POST /github/webhook──▶ CR Check(Go, GKE)
                                              │ 验签 → 去重 → 入队 → 200
                                              ▼
                                    查 CR 管理平台（存在? Approved/Implement? 审批? 有效期?）
                                              ▼
                                    跑规则 R1–R13a（含 Maintenance Window）
                                              ▼
GitHub(PR 上的 ✓/✗) ◀──POST /check-runs──  CR Check
        │
        ▼
GitHub 分支保护：required check = cr/prod-validation → 不绿就合不了
        │  merge
        ▼
Argo CD（+ PreSync Hook 二次校验 + 准入兜底）→ PRD / 生产集群
```

## 代码在哪

| 路径 | 内容 |
|---|---|
| [`cr-check/`](./cr-check/) | **CR Check 服务的 Go 实现**（本目录的代码部分） |
| [`cr-check/cmd/server/`](./cr-check/cmd/server/main.go) | 入口：依赖组装、路由、优雅退出 |
| [`cr-check/internal/rules/`](./cr-check/internal/rules/engine.go) | ★ 判定引擎（collect-all 规则编排、CR 号解析、维护窗口） |
| [`cr-check/internal/webhook/`](./cr-check/internal/webhook/handler.go) | ★ 入站：验签 → 幂等 → 分发 → ACK |
| [`cr-check/internal/recheck/`](./cr-check/internal/recheck/recheck.go) | ★ 定时重扫重评（兜底） |
| [`cr-check/config/policy.yaml`](./cr-check/config/policy.yaml) | 规则数据（改这里不用发版） |
| [`cr-check/deploy/`](./cr-check/deploy/) | K8s 清单（Deployment/Service/Ingress/ConfigMap/PDB） |

```bash
# 30 秒跑起来
cd cr-check && make run
# 另开一个终端
./scripts/send-test-event.sh          # → 看到逐条规则的判定结果
```

## 上手前必须问清的 5 个问题

```
Q1  CR 平台的 targetEnv 字面量是什么？（prd / PRD / pre-prod / staging？）
Q2  "可执行的 implement 状态"在平台里的准确枚举值？平台还有哪些状态？
Q3  Maintenance Window 定义在哪：我们配置（固定时段）还是平台侧（每张 CR 自带）？
Q4  CR 号写在 PR 的哪里？label / body / trailer？
Q5  受管分支清单：PRD 分支叫什么？生产分支叫什么？
```

> 更多问题见 [`Develop-git-apps.md`](./Develop-git-apps.md) §13。

---

返回：[上级 README](../README.md)
