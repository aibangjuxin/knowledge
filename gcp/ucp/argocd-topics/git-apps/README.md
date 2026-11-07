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
| ★ | [`cr-check/`](./cr-check/) | **★ 可运行的 Go 实现**（本文档集的代码部分）<br>CR Check 服务的完整代码：`cmd/server` + 9 个 `internal` 包、策略配置、K8s 清单、测试脚本。<br>**30 秒跑起来** → 见 [`cr-check/README.md`](./cr-check/README.md) §0 |

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
