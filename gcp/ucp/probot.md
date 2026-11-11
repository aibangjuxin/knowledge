# Probot 是什么

> 一句话结论：**Probot 是一个用 Node.js / TypeScript 编写 GitHub Apps 的开源框架**——它把"接收并校验 webhook、处理鉴权、调用 GitHub API"这些脏活包起来，让你几行代码就能写出一个能自动响应 Issue/PR/Commit 等事件的机器人应用。

## 它解决什么问题

"如果 GitHub 能……就好了" —— 大部分需求都可以通过 **GitHub App** 实现：可安装到组织或用户账号、按仓库授权、拥有细粒度权限（granular permissions）和内置 webhook，是 GitHub 里的一等公民。

但直接写 GitHub App 很啰嗦：要自己搭 HTTP 服务校验 webhook 签名、自己做 App 的 JWT 换取 installation token、自己处理 OAuth 流程。**Probot 把这些重复劳动全部吃掉**，让开发者专注业务逻辑。

## 核心模型

```js
export default (app) => {
  app.on("issues.opened", async (context) => {
    await context.octokit.issues.createComment(
      context.issue({ body: "Thanks for opening this issue!" })
    );
  });
};
```

- `app.on(event, handler)` — 订阅 webhook 事件（如 `issues.opened`、`pull_request.labeled`）
- `app.onAny()` / `app.onError()` — 兜底处理所有事件与错误
- `context` — 单次事件的上下文：事件名、payload、发起者、仓库信息、Octokit 客户端
- `context.octokit` — 已完成鉴权的 GitHub API 客户端（REST + GraphQL），直接调

## 生态

- **probot.github.io / Explore**：官方应用市场，收集社区写好的 App（多数已托管、免费可用）
- **典型应用**：
  - *Pull* — 自动同步 fork 仓库
  - *Release Drafter* — 根据 PR 合并自动起草 Release Notes
  - *Settings* — 统一管理仓库设置
  - *WIP* / *Mergeable* — 阻止带 WIP 标题或不合规的 PR 被合并
  - *Stale* / *Request Info* / *Issue Labeler* 等社区经典应用
- **Extensions**：插件机制（Octokit 扩展、认证方式、Sentry 集成等）
- **Probot Run / Probot Adapter**：把本地 Probot App 部署为 Serverless 或传统 Node 服务

## 部署模式

1. **托管应用**：Probot 官方托管或第三方托管，直接安装到仓库，零运维
2. **自建**：用 Probot Adapter 部署到自己的 Serverless（AWS Lambda 等）或 Node 服务器
3. **Probot Run**（官方托管平台）：把 App 部署到 Probot 的云环境

## 与相近方案对比

| 方案 | 定位 |
|---|---|
| **GitHub Actions** | GitHub 内置的 CI/CD 工作流引擎，跑流水线/自动化任务 |
| **GitHub App（原生）** | 平台提供的扩展模型，需要自己处理 webhook 校验与鉴权 |
| **Probot** | 构建 GitHub App 的**框架/SDK**，专注"事件驱动地修改仓库数据" |
| **Octokit** | GitHub API 的客户端库；Probot 内部用它并已封装好鉴权 |
| **webhooks（库）** | 同样封装了 webhook 签名校验，但不含 GitHub App 的安装/权限模型 |

## 快速上手要点

```bash
npm init probot my-app   # 脚手架创建
npx probot run           # 本地起服务 + 接收测试 webhook
npx probot receive       # 模拟一条 webhook 事件
```

---

# 附：Go vs Probot 评估（基于 `cr-check` Go Demo）

评估对象：`/Users/lex/git/go/cr-check` —— 一个用 Go 写的 **GitHub App**，功能是接收 `pull_request` webhook、拉取变更单（CR）平台数据、按规则判定后回写 GitHub Check。
规模：约 **3.3k 行 Go**（cmd/server + internal 11 个包：webhook、gh、rules、check、recheck、queue、audit、observability、config、crplatform、webhook 签名校验），带单测、YAML 策略配置、Dockerfile、GKE/ArgoCD 部署清单。

## 关键澄清：Probot 不是 Go 的"官方对手"

Probot 本质是**写 GitHub App 的脚手架/框架**（Node.js）。Go 侧的对应物不是某个"Probot for Go"，而是**直接用 `go-github` + `ghinstallation` 自己搭**——也就是 cr-check 现在做的事。

所以真正的比较是：

> **手写 Go GitHub App（自己造轮子） vs 用 Probot 框架（JS，轮子现成）**

## 逐项对比

| 维度 | Go（cr-check 现状） | Probot |
|---|---|---|
| **webhook 验签** | 手写 HMAC（`internal/webhook/signature.go`）+ 单测 | 框架内置，零代码 |
| **App 鉴权 / token** | `ghinstallation` 自动签 JWT + 缓存/续期 installation token，`Factory` 按 installation 缓存 client | 框架内置 `context.octokit`，已鉴权 |
| **GitHub API 调用** | `go-github v88`（强类型、结构体清晰） | Octokit（REST + GraphQL，JS 动态类型） |
| **业务逻辑代码量** | 判定规则/CR 平台对接/审计/指标/幂等队列 全部自己写（约占 90% 的代码） | 同样要自己写（这部分**不会因为用 Probot 而变少**） |
| **事件模型 / 异步** | 自己实现 `queue`（幂等、delivery TTL）+ `recheck` 注册表；webhook 同步返回、判定异步 | Probot 是**请求-响应式**，耗时长任务需自行接队列（BullMQ/SQS） |
| **fail-closed 语义** | 已内建（CR 平台故障 → `failure`，绝不误判 success），有专门铁律说明 | 可实现，但需自己写全套 |
| **配置策略化** | `config/policy.yaml` + 环境变量覆盖，敏感项不进 Git | 需自己引入配置方案（无内置等价物） |
| **可观测性** | 内建 Prometheus metrics + audit sink + 结构化日志 | 需自行接 Sentry/Prom/OpenTelemetry |
| **部署** | 单静态二进制 → GKE / Cloud Run；配 External Secrets 拉私钥；ArgoCD 同步 | Node 运行时 → Cloud Run / Lambda / GKE 均可；Probot Adapter 已封装 |
| **运行时成本** | 镜像 ~20MB，冷启动毫秒级，内存占用低 | Node 常驻，内存/冷启动明显更高（GKE 上每 Pod 多几百 MB） |
| **类型安全** | 编译期保证，payload 变更编译不过 | 运行时才炸，payload 需额外校验 |
| **上手速度** | 慢（要研究 webhook/App/权限模型） | **极快**（`npm init probot`，几行代码跑通） |
| **生态复用** | 无现成 App 可抄 | **probot.github.io 应用市场**：Pull、Release Drafter、Stale、Mergeable… 大量成熟实现可借鉴/直接装 |
| **测试** | 已写单测（签名、handler、rules） | 生态有 `probot run/receive` 本地模拟 webhook |

## 结论与建议

**1. Probot 确实"更简单"，但简单的是那 10% 的管道胶水，不是这个项目的核心。**
cr-check 里 Probot 能替你省下的只有：验签、installation token 续期、API 客户端封装 —— 合计大概 **100~200 行**。而真正的工作量在 CR 平台对接、fail-closed 判定引擎、幂等/去重、recheck、审计、指标、策略配置，这些 Probot **一点忙都帮不上**，换 JS 后仍然要一行行写。

**2. 对 cr-check 这个项目，建议保留 Go。** 理由：
- 已经有 ~3.3k 行可运行实现，换 JS 等于**重写**，收益不抵成本；
- fail-closed 这类安全语义需要编译期类型保障，Go 更合适；
- 生产部署形态（GKE + External Secrets + ArgoCD）对二进制天然友好；
- 长期看这是要上生产的系统，不是玩具。

**3. Probot 的甜点区是"小而快的自动化"**，这类需求更值得用 Probot：
- 给开源项目装个 Stale / Release Drafter / Mergeable —— 直接装现成的，别自己写；
- 临时机器人（给 PR 自动贴标签、@ 特定人、在 CI 挂钩子）；
- 团队内部 1~2 天的自动化脚本，需要快速验证想法。

**4. 如果确实想用 Probot 而不重写业务逻辑**，有一个折中路径：
**保持 Go 二进制作为"判定引擎"**（保留 rules / crplatform / fail-closed / 配置），用 Probot 只做一个**薄壳**：负责接收 webhook、鉴权、把事件转发给 Go 服务、再把结果写回 GitHub Check。这样既拿到 Probot 的开发体验，又不牺牲核心逻辑与类型安全。
—— 但坦白说，这层壳本身用 Go 写也就 200 行（`internal/webhook/handler.go` + `internal/gh/client.go` 已经把这事做完了），**为了它引入 Node 运行时并不划算**。

**5. 一句话建议**：*cr-check 继续用 Go；把 Probot 记在"快速自动化/现成应用"工具箱里，而不是 cr-check 的技术选型里。*

## 参考：若真要用 Probot 重写，映射关系

| cr-check 的 Go 模块 | Probot 侧对应物 |
|---|---|
| `internal/webhook/signature.go`（HMAC 验签） | 框架内置，删除 |
| `internal/gh/client.go`（ghinstallation + token 缓存） | `context.octokit`，删除 |
| `internal/webhook/handler.go`（payload 解析） | `app.on("pull_request.opened", ...)` + `context.payload` |
| `internal/rules/*`（判定引擎） | 原样重写为 TS/JS，**无框架帮助** |
| `internal/crplatform/*`（CR 平台 SDK） | 原样重写，**无框架帮助** |
| `internal/queue/*`（幂等队列） | 需自建（Probot 无内置异步队列） |
| `internal/audit` + `internal/observability` | 需自建（Sentry / Prom / OTel） |
| `internal/config`（policy.yaml） | 需自建配置方案 |
| `internal/check/writer.go`（回写 Check） | `context.octokit.checks.create` |
