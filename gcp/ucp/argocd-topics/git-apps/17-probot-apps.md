# 11 · Probot 是什么

> 📌 **一句话**：Probot 是一个 **Node.js 框架**，专门用来写 **GitHub App**（机器人），
> 把"收 webhook、验签、换 token、调 GitHub API"这些脏活干完，让你只写业务逻辑。
> 官网 <https://probot.github.io/> ｜ 源码 <https://github.com/probot/probot>（约 9.6k star，ISC 协议）

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-tldr) | TL;DR |
| [§1](#1-probot-是什么) | Probot 是什么 |
| [§2](#2-核心概念) | 核心概念：App / Webhook / Octokit |
| [§3](#3-hello-world-长什么样) | Hello World 长什么样 |
| [§4](#4-部署形态与所需配置) | 部署形态与所需配置 |
| [§5](#5-生态现成应用) | 生态里现成的应用 |
| [§6](#6-和本仓库的关系probot-vs-go) | 和本仓库 CR Check 的关系（Probot vs Go） |
| [§7](#7-一句话记住) | 一句话记住 |

---

## 0. TL;DR

1. **GitHub App 才是"一等公民"**：可以装到组织/用户账号，权限是**细粒度**的，安装在**指定仓库**上，带**内置 webhook**。
2. **Probot = 用 Node.js 写 GitHub App 的脚手架**，帮你干掉验签、鉴权、API 调用这些重复劳动。
3. **一个 Probot app 就是一个导出函数**：`export default (app) => { app.on("issues.opened", async (context) => {...}) }`。
4. **`context.octokit` 是"已认证"的 GitHub 客户端**（REST + GraphQL），`context.payload` 是事件原始载荷。
5. **部署只需 3 个环境变量**：`APP_ID`、`WEBHOOK_SECRET`、`PRIVATE_KEY`（或 `PRIVATE_KEY_PATH`）。
6. **大部分热门 Probot app 已有官方托管版**，你**可以一行不部署直接用**。
7. **对本仓库**：我们要写的是 **Go** 的 CR Check（状态机 + 时间窗口 + 查外部平台），
   Probot **不是**我们的技术选型，但它是理解 "GitHub App 长什么样" 的最佳参照物。

---

## 1. Probot 是什么

> 原文：*"Probot is a framework for building GitHub Apps in Node.js.
> It aims to eliminate all the drudgery—like receiving and validating webhooks,
> and doing authentication handstands—so you can focus on the features you want to build."*

拆开看三层含义：

| 层 | 说明 |
|---|---|
| **它不是什么** | 它不是 GitHub 官方的 App 平台，也不是一个"应用商店"。它是**你自己用的开发框架**。 |
| **它是什么** | 一个 npm 包（`probot`）+ 一套约定，把 GitHub App 的**协议层**封装掉。 |
| **它解决什么** | ① 接收并**验证** webhook 签名；② 用 App 的 private key **换 installation token**；③ 拿到一个**已认证**的 API 客户端。 |

**GitHub App vs 它的替代品**（这才是 Probot 存在的意义）：

| 方案 | 身份 | 权限粒度 | 适合 |
|---|---|---|---|
| **GitHub App** | 安装制机器人 | 细粒度，可只装部分仓库 | 组织级自动化 ✅ |
| Personal Access Token | 个人身份 | = 那个人的全部权限 | 个人脚本 |
| GitHub Actions | 仓库内脚本 | 受 Actions 权限限制 | 跟仓库强绑定的任务 |

> 官方一句话：**"Apps are first class actors within GitHub."**

---

## 2. 核心概念

```
GitHub 事件 ──POST /api/github/webhooks──▶ 你的 Probot 服务
                                              │ ① 验签（WEBHOOK_SECRET）
                                              │ ② 查 installation → 换 access token
                                              ▼
                                    context.octokit（已认证客户端）
                                              │ ③ 调 REST / GraphQL
                                              ▼
                                    写回 GitHub（评论、check run、label…）
```

| 概念 | 作用 |
|---|---|
| **`app.on(event, handler)`** | 订阅 webhook 事件，如 `issues.opened`、`pull_request.opened` |
| **`context`** | 事件上下文：`context.payload`（原始载荷）、`context.issue()`（提取 owner/repo/number）、`context.log` |
| **`context.octokit`** | **已认证**的 GitHub 客户端（Octokit），可直接调 REST 和 GraphQL |
| **`app.onAny()`** | 兜底订阅所有事件（做审计日志常用） |

> 注意：Probot 是 **push 模型**——GitHub 主动推事件给你，服务端负责快速 ACK 后异步处理。
> 这与我们自研 CR Check 的契约完全一致，见 [12-webhook-push-vs-pull.md](./12-webhook-push-vs-pull.md)。

---

## 3. Hello World 长什么样

一个 Probot app **就是一个导出函数**：

```js
// index.js
export default (app) => {
  app.on("issues.opened", async (context) => {
    // 提取 { owner, repo, number }
    const params = context.issue({ body: "Hello World!" });
    // 用已认证客户端回写评论
    return context.octokit.issues.createComment(params);
  });
};
```

就这么多。**没有** webhook 端点代码、**没有**验签代码、**没有** token 刷新逻辑。

---

## 4. 部署形态与所需配置

### 4.1 三个环境变量

| 变量 | 说明 |
|---|---|
| `APP_ID` | GitHub App 设置页里的 App ID |
| `WEBHOOK_SECRET` | 你自己生成的随机串（`openssl rand -base64 32`），用于**验签** |
| `PRIVATE_KEY` | App 的私钥内容（**优先于** `PRIVATE_KEY_PATH`） |

### 4.2 GitHub App 后台要填的东西

| 字段 | 填什么 |
|---|---|
| Homepage URL | 你的 GitHub 仓库地址 |
| Webhook URL | 部署后的公网地址，如 `https://your-app.com/api/github/webhooks` |
| Webhook Secret | 同上 `WEBHOOK_SECRET` |
| Private Key | 下载 .pem |

### 4.3 可选部署目标（官方列出的）

- **Node 常驻进程**：`probot run ./app.js`
- **Serverless**：AWS Lambda / Azure Functions / Google Cloud Functions / Vercel / Netlify Functions
- **PaaS**：Heroku / Render
- **GitHub Actions**（把 app 跑在 Actions 里）
- 也可以**多个 app 合并到一个部署**里（每个 app 一个路由前缀）

> 💡 **实用提示**：官方 Probot 生态里绝大多数 app 都有**托管版**，
> 仓库首页直接展示（Pull / Release Drafter / Settings / WIP / Mergeable …），
> **能装托管版就不要自己部署**。

---

## 5. 生态现成应用

官方案例（均开源免费）：

| App | 作用 |
|---|---|
| **Pull** | 保持 fork 与上游同步 |
| **Release Drafter** | 合并 PR 时自动起草 release notes |
| **Settings** | 把仓库设置做成 PR 来改 |
| **Work In Progress** | 标题带 "WIP" 的 PR 禁止合并 |
| **Mergeable** | 按配置规则禁止合并 PR |

文档里点名的经典例子：**In Solidarity**（inclusive language 加 status check）、
**Issue Labeler**（按标题/正文自动打 label）、**Request Info**（催 issue 补充信息）、**Reminders**。

> 💡 **对我们最有用的是「Mergeable」和「Settings」的思路**：
> 前者证明"用 App + 分支保护拦住不合规 PR"是可行且有先例的，
> 后者证明"配置变更也能走 PR 审查"这一模式。

---

## 6. 和本仓库的关系（Probot vs Go）

我们自研的 **CR Check** 已经定了用 **Go**（见 [13-cr-check-go-design.md](./13-cr-check-go-design.md)）。
Probot 不是我们的选型，但它是最好的**对照组**：

| 维度 | Probot (Node) | 我们的 CR Check (Go) |
|---|---|---|
| 定位 | 通用 GitHub App 框架 | 单一门禁场景的专用服务 |
| 语言/运行时 | Node.js | Go（编译产物，容器化，GKE 部署） |
| 协议层 | 框架内置（验签/换 token 都不用写） | 用 `ghinstallation` + `go-github` 自己拼（§10 依赖选型） |
| 状态 | **无状态**，事件驱动 | **有状态**（PR → 合规性判定、时间窗口） |
| 外部依赖 | 基本无 | 需查 CR 管理平台 + 维护窗口（跨系统、有状态机） |
| 部署 | Serverless / PaaS / Actions 都行 | GKE + Ingress + TLS（长期在线） |
| 判定逻辑 | `app.on()` 里同步处理即可 | 必须**异步**：ACK → 入队 → 判定 → 写 check run |

**结论**：CR Check 的难点不在"接 webhook"（Probot 帮得上忙但我们用 Go），
而在 **「时间窗口必须有第二个触发源」** 和 **「需要查外部 CR 平台」**——
这两件事 Probot 都不解决，因为它们是**业务问题**不是**协议问题**。

> 但 Probot 值得记住的一点：**GitHub App 本身是一等公民**，
> 细粒度权限 + 指定仓库安装 + 内置 webhook 这三点，
> 就是我们 [11-github-app-concepts.md](./11-github-app-concepts.md) 讨论的"自研 App 到底值不值"的基础。

---

## 7. 一句话记住

```
Probot = "写 GitHub App 的 Node.js 脚手架"：
         你只写 "收到某事件 → 调 GitHub API 做某事"，
         验签/鉴权/客户端它全包。
         生态里已有大量托管好的现成 app（能直接装就别自己写）。
         我们自己不走这条路，但它是理解 GitHub App 的最佳参照。
```

---

## 关联文档

| 文档 | 关系 |
|---|---|
| [11-github-app-concepts.md](./11-github-app-concepts.md) | GitHub App / Installation / Private Key 概念源头 |
| [12-webhook-push-vs-pull.md](./12-webhook-push-vs-pull.md) | Probot 用的就是 push 模型 |
| [13-cr-check-go-design.md](./13-cr-check-go-design.md) | 我们的 Go 版实现（对照 Probot） |
| [14-rulesets-and-gitapp-gate.md](./14-rulesets-and-gitapp-gate.md) | 与 App 配合的门禁强制层 |
| [Develop-git-apps.md](./Develop-git-apps.md) | 自研可行性评估（vs Actions vs Probot 式框架） |

**参考来源**
- Probot 官网 <https://probot.github.io/>
- Probot 文档 <https://probot.github.io/docs/>
- Hello World <https://probot.github.io/docs/hello-world>
- Deployment <https://probot.github.io/docs/deployment>
- 源码仓库 <https://github.com/probot/probot>
