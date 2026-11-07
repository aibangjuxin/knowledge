# 11 · GitHub App 概念梳理（Public Link / Home URL / Webhook URL / 源码在哪）＋ 生产变更加闸

<sub>副标题：PR merge 到生产分支前，必须有一个合规的 Change Request（变更单）—— 规则写在哪、GitHub App 能不能做</sub>

> **一句话结论**
> **GitHub App 不是"你的应用"，它是"你用来访问 GitHub 的一个身份（机器人账号）"。**
> Public Link / Home URL / Webhook URL 三个 URL 指向三件完全不同的事；
> **Webhook URL 是"事件通知的收件地址"。**
> 真正的源码在**被 Installation 授权的那个 Git 仓库**里，真正的"发布"发生在
> **Argo CD 把 Git 里的 YAML apply 到目标集群**的那一刻。

> ⚠️ **关于"Webhook URL 是不是应用发布的地方"—— 这里有两种"发布"，必须分开说**
>
> | 说的"发布"是指 | Webhook URL 是不是发布地址？ | 理由 |
> |---|---|---|
> | **① 业务应用上线**（把用户代码里的 YAML apply 到生产集群） | **❌ 不是** | 业务应用跑在目标集群里，它的访问地址由 Ingress/Gateway 决定，与 Webhook URL 毫无关系 |
> | **② 你自己写的 GitHub App 后端服务上线**（把你的 Go 程序部署出去） | **✅ 正是** | Webhook URL **就是**你那个服务的公网地址（域名 + 路径）。你必须先把它部署到 GKE、挂上 Ingress、备好 TLS 证书，GitHub 才有一个地方来"敲门" |
>
> 换句话说：
> **"Webhook URL 绝不是应用发布的地方"这句话，在 Argo CD 的语境里成立，
> 但如果拿它去理解"我要自己写一个 GitHub App 后端"，就会得出错误结论
> —— 你会以为 Webhook URL 指向的是某个第三方托管的东西，而事实上它就是你自己部署的服务的地址。**
>
> 自研场景下的完整表述见
> [`webhook-and-backend-service.md`](./webhook-and-backend-service.md) §4
> 与本文 [§3.4](#34-自研场景下的-app-源码与部署)、
> [§5.5](#55-补充自研-app-场景下的正确表述别把两种发布混在一起)。

> **本文分两部分**
> - **Part A（§0–§10）概念**：GitHub App 是什么、那几个 URL 什么关系、源码在哪
> - **Part B（§11–§19）场景**：GKE 上的应用要加生产变更管控 ——
>   「PR merge 到生产分支前，必须有一个合规的 Change Request（变更单）」，
>   规则写在哪、GitHub App 能不能实现、怎么在 GitOps 里落地。

---

## 0. 先把三个误解拆掉

| 你的说法 | 结论 | 正确说法 |
|---|---|---|
| "Webhook 是这个 App 真正的应用发布的地方" | ⚠️ **取决于"发布"指什么** | ① 若指**业务应用上线**（apply 到生产集群）→ ❌ 不是，Webhook URL 与之无关；② 若指**你自研的 App 后端上线** → ✅ **正是**，Webhook URL 就是你部署出来的那个 Go 服务的公网地址。见 [§5.5](#55-补充自研-app-场景下的正确表述别把两种发布混在一起) |
| "它的源代码管理是在 Webhook 里配置的" | ⚠️ 半对 | Webhook 配置的是**事件订阅范围**；**仓库准入**在 Installation，**拉哪个仓库**在 Argo CD Repository Secret，**拉哪个路径/分支**在 Application。 |
| "Public Link / Home URL / Webhook URL 是一回事" | ❌ | 三者职责完全独立，见 §2 的对照表。 |

---

## 1. GitHub App 到底是什么

GitHub App 是 GitHub 上的**一等身份**，介于「个人 PAT」和「服务账号」之间：

```
个人 PAT ──────► 代表"某个人"，人离职/轮换/泄露 = 全乱
GitHub App ────► 代表"某个机器人"，有独立的权限集、密钥、独立审计
```

一个 GitHub App 由三块组成：

```
┌─────────────────────────────────────────────────────────┐
│ ① GitHub 上的注册配置（App 的"身份档案"）                  │
│    - App ID（数字，唯一标识）                            │
│    - Client ID / Client secret                          │
│    - 权限声明（repositories: read / contents: read ...）  │
│    - 事件订阅（push / pull_request / installation ...）   │
│    - Webhook URL + Webhook secret                       │
│    - Homepage URL / Callback URL / Public link           │
├─────────────────────────────────────────────────────────┤
│ ② Private Key（RSA 私钥，GitHub 生成给你）                │
│    → 用它签 JWT，向 GitHub 换 Installation Access Token   │
├─────────────────────────────────────────────────────────┤
│ ③ Installation（安装实例）★真正的"授权边界"★            │
│    - 装到哪个组织 / 账号                                  │
│    - 装到哪些仓库（All repositories / Selected）           │
│    - 每个组织下有独立的 installation_id                    │
└─────────────────────────────────────────────────────────┘
```

**关键理解：App 是"身份"，Installation 是"这个身份在哪个组织下能碰哪些仓库"。**
Argo CD 侧要同时填 `githubAppID` + `githubAppInstallationID`，
原因就是：App ID 定身份，Installation ID 定边界。见 [`07-repository-githubapp.md`](../07-repository-githubapp.md) §3.1。

---

## 2. 四个 URL 的关系（本节是本文核心）

一个 GitHub App 在界面上会同时出现这几个"看起来都是 URL"的字段：

| 名称 | 填什么 | 谁访问它 | 作用 | Argo CD 场景下是否重要 |
|---|---|---|---|---|
| **Public link**<br>(`github.com/apps/<slug>`) | 不用填，系统给的 | 任何人 | App 的**公开主页**。勾选 **Public** 后这个页面任何人可见、任何组织可安装 | 展示用，不影响功能 |
| **Homepage URL** | 随便填一个合法 URL<br>(建议填 Argo CD 控制台地址) | 人（浏览器） | App 的"宣传主页"。GitHub 在安装页/事件里展示 | ❌ 纯展示，**没有任何鉴权含义** |
| **Webhook URL** | 你的服务的**公网入口地址**（域名 + 路径）<br>· Argo CD 场景 → `argocd-server` 的端点<br>· **自研 App 场景 → 你自己部署的 Go 服务的 Ingress 地址** | **GitHub 服务器**（POST） | GitHub 把事件（push、installation 变更…）推给你的服务 | ✅ **功能核心**，见 §4 |
| **Authorization callback URL** | 任意合法 URL | 浏览器（OAuth 授权后） | GitHub App **走 OAuth 流程**时的回调地址 | ⚠️ 用 installation token 模式时**用不到** |

### 2.1 关系图

```
                       ┌──────────────────────────────────────────┐
   人点"Public link" ─▶│ github.com/apps/<slug>   （App 公开主页）   │
                       └──────────────────────────────────────────┘
                                        │ 展示跳转
                       ┌────────────────▼─────────────────────────┐
   人点"Homepage URL" ▶│ https://argocd.example.com （宣传页/控制台）│
                       └──────────────────────────────────────────┘
   ★ 不参与 ★

   GitHub 服务器 ══POST(push 事件)══▶ ┌───────────────────────────────┐
                                       │  Webhook URL                 │
                                       │  https://argocd.example.com/ │
                                       │  api/webhook/github          │
                                       │  → argocd-server :80/:443    │
                                       └───────────────────────────────┘

   人点"Authorize"(OAuth) ══▶ Callback URL（只有走 OAuth 才用得上）
```

### 2.2 一句话记忆

> **Homepage = 给人看的门牌号；Public link = 商店橱窗；Webhook URL = 收快递的地址。**
> 只有第三个是"机器对机器"的通道。

### 2.3 ⚠️ 部署前验证项

- "Public link" 的确切标签文案、以及 App 的 Public/Private 开关位置，
  以你所用 GitHub 版本的 `Settings → Developer settings → GitHub Apps → <App> → General` 实际界面为准
  （界面文案在不同版本会变，**字段语义不变**）。
- 一个 GitHub App **只有一个** Webhook URL（**官方保证**）。
  所以如果既想触发 Application 刷新、又想触发 ApplicationSet 重新生成，
  不能靠"一个 App 两个 URL"，只能选一个端点 + 依赖另一条链路的轮询兜底（见 §5.3）。

---

## 3. "我想看到这个 App 的源代码，它在哪里？"

"源代码"在这里有**三种完全不同的含义**，必须分开；
**§3.4 单独放"你要自研的那种"** —— 那是完全另一回事，不适用前面的结论。

### 3.1 ① 业务应用的源码（你想部署的那个东西）

**在 Git 仓库里**，具体是：

```
Installation 授权的仓库  →  Application.spec.source.repoURL
                          →  Application.spec.source.path        （子目录）
                          →  Application.spec.source.targetRevision（分支/tag/SHA）
                          →  Application.spec.source.helm.valueFiles / values（Helm 参数）
```

Argo CD 就是按这四个字段把仓库 clone 下来、渲染出 manifest。
换句话说：**Git 仓库就是"源代码管理"的载体，Application 就是"取哪份源码"的说明书。**

- 找它：在 Argo CD UI 打开 Application → **SOURCE** 卡片，直接看 Repo URL / Path / Target Revision。
- 命令：`argocd app get <app> -o jsonpath='{.spec.source}'`

### 3.2 ② GitHub App 自己的源码

**通常不存在，或者不在这个 App 里。**

GitHub App 本质上是**一份注册在 GitHub 上的配置**（权限 + 事件 + webhook URL），
加上**一个可选的后端服务**（只有需要 OAuth 授权流程、需要在本地处理事件时才写）。

- Argo CD 用的模式是 **"private key → installation token"**，
  **不需要**写任何 App 后端代码，也不需要处理 GitHub 推来的事件体内容
  （Argo CD 只用事件里的 repo/branch 做过滤）。
- 你创建 App 时用的那个仓库（组织的私有仓库 / 官方模板仓库）通常只用来生成 manifest，
  里面是 `app.yml`（manifest 形式）或一份 YAML 描述，**不含运行逻辑**。
- 想找 App 的"归属"：组织 `Settings → Developer settings → GitHub Apps → <App>`
  → 能看到 App 的所有方、Public link、权限、事件订阅、**Installations 列表**。

### 3.3 ③ Argo CD 侧的"GitOps 源码"

就是 §3.1 的那一份。补充一点：**GitHub App 在这里的作用只是"钥匙"**，
让 Argo CD 有权限读私有仓库；它不存储源码、不缓存源码、不分发源码。

> 对照表：
>
> | 谁 | 存什么 | 在哪 |
> |---|---|---|
> | GitHub 仓库 | 业务源码 + K8s/Helm manifest | GitHub（组织下） |
> | GitHub App | 权限、事件订阅、webhook 地址 | GitHub 设置页 |
> | Private Key | App 私钥 | Argo CD 的 Repository Secret（K8s Secret） |
> | Argo CD | Application / ApplicationSet 定义、渲染缓存、集群状态 | argocd 集群（Redis + K8s） |

### 3.4 自研场景下的 App 源码与部署

> **需求方的原话（完全正确，这里原样存档）：**
> > "我想看到这个 Git Apps 的源代码，也就是我 Go 语言开发的这个代码，
> > 其实我肯定是我开发的，我肯定知道它的源代码。
> > 不过它的源代码开发出来之后，我肯定是要把这个东西**部署在我的那个服务里面**的，
> > 也就是**给它一个暴露的地址让 Webhook 来调用**的。"

**这段理解没有任何问题。** 把它拆成四个动作就一目了然：

```
① 源码（Source）      →  你写的 Go 代码，在**你自己的 Git 仓库**里
                              └─ 你当然知道它在哪 —— 这不是个问题
② 构建（Build）       →  CI 把它编译成**镜像**，推进 Container Registry
                              └─ 产物：ghcr.io/acme/cr-check:<sha>
③ 部署（Deploy）      →  镜像跑进你的 K8s 集群，变成一个**长期运行的 Pod**
                              └─ 产物：Deployment → ReplicaSet → Pod（监听 :8080）
④ 暴露（Expose）      →  Service + Ingress + 域名 + TLS 证书
                              └─ 产物：https://cr-check.example.com/github/webhook
        ╰───────────────────────────────╯
                  ★ 这就是 Webhook URL ★

⑤ GitHub 敲门         →  GitHub POST 到 ④ 的地址
                          → 你的 handler 跑判定 → 写 check run
```

**所以在你的场景里：**

| 问题 | 答案 |
|---|---|
| **源码在哪？** | **你自己写的**，在**你自己的 Git 仓库**里（独立仓库，不与业务代码同仓） |
| **"发布"是什么？** | **②构建 → ③部署 → ④暴露** 这三步的组合。Git 里的代码自己不会跑起来 |
| **Webhook URL 是什么？** | **④ 暴露出来的那个公网 HTTPS 地址**（域名 + 路径）—— 它就是你那个服务的门牌号 |
| **Webhook URL 是"别人托管的东西"吗？** | ❌ **不是**。它指向的**就是你自己部署的 Pod**（经 Ingress/LB 转发过去） |
| **业务应用（用户代码）的源码在哪？** | **另一个仓库**，跟你的 App 源码无关（见 §3.1） |

#### 3.4.1 为什么 §3.2 说"通常不存在"，而你这里一定存在

| | §3.2 说的（Argo CD 的形态 A） | **你的形态 B** |
|---|---|---|
| 要不要写后端代码 | ❌ 不需要（只用 token clone 仓库） | ✅ **需要，就是你要写的 Go 服务** |
| 源码在哪 | GitHub App 本身**没有**源码 | **你的 Git 仓库** |
| 需不需要公网地址 | 不需要（只 clone 出去） | ✅ **需要**（GitHub 要往里 POST） |
| 需不需要自己部署 | ❌ 不需要 | ✅ **需要**（这正是 §3.4 ②③④ 三步） |
| Webhook URL 指向 | `argocd-server`（**已存在的组件**） | **你自己部署的服务** |

> ★ **一句话区分**：
> **§3.2 回答的是"Argo CD 用的那个 App 有没有代码"→ 没有**；
> **§3.4 回答的是"我自研的 App 的代码在哪、怎么变成一个可被访问的地址"→ 在我手里，在我的仓库里，部署后暴露成 Webhook URL。**
> **两者不矛盾，只是两个形态。**（形态 A / B 的完整对照见
> [`Develop-git-apps.md`](./Develop-git-apps.md) §2 误解 2 与 §3.2）

#### 3.4.2 完整 8 步（从 commit 到 Webhook 生效）

| 步 | 做什么 | 产物 |
|---|---|---|
| ① | 本地写代码 → commit → push 分支 | Git commit |
| ② | 提 PR → CI 构建镜像 | `ghcr.io/acme/cr-check:<sha>` |
| ③ | PR 合并到 main（或打 tag） | 版本引用 |
| ④ | Argo CD 感知 → sync | K8s 对象被 apply |
| ⑤ | K8s 起 Pod | **你的 Go 程序第一次真正运行** |
| ⑥ | Service + Ingress 暴露 | 集群内地址 + 公网地址 |
| ⑦ | GitHub App 后台填 Webhook URL | 事件有了入口 |
| ⑧ | 有人提 PR → GitHub POST → 你的 Pod 处理 → 写 check run | PR 上的 ✓/✗ |

> 📌 **逐步展开（含 Dockerfile / K8s 清单 / 故障速查）**：
> [`webhook-and-backend-service.md`](./webhook-and-backend-service.md) §5。
>
> ★ **特别注意第 ⑤ 步与第 ⑦ 步的顺序**：
> **服务必须先跑起来、地址先能访问，再去 GitHub 填 Webhook URL。**
> 填完 URL 但服务没起来 → GitHub 的 `ping` 投递失败 → 后续所有事件投递失败 → **门禁静默失效**。

---

## 4. "源代码管理是在 Webhook 里配置的" —— 需要拆成四层

这是最容易混淆的地方。**四层各管一件事，互不替代：**

```
┌────────────────────────────────────────────────────────────────┐
│ 第 1 层  Installation（GitHub 侧）                              │
│   回答：这个 App 能读哪些仓库？                                 │
│   位置：GitHub → App → Installations → Configure                │
│   字段：githubAppInstallationID + githubAppID                  │
├────────────────────────────────────────────────────────────────┤
│ 第 2 层  Webhook / 事件订阅（GitHub 侧）                        │
│   回答：仓库发生什么变化时，通知 Argo CD？                       │
│   位置：GitHub → App → Settings → Webhooks / Events             │
│   注意：只影响"延迟"，不影响"是否同步"（见 §5.2）                │
├────────────────────────────────────────────────────────────────┤
│ 第 3 层  Repository Secret（Argo CD 侧）                        │
│   回答：用哪个 App/Installation 去拉哪个仓库？                    │
│   位置：argocd 命名空间的 Secret（label: argocd.argoproj.io/     │
│         secret-type: repository）                                │
│   字段：url / githubAppID / githubAppInstallationID /            │
│         githubAppPrivateKey / project                           │
├────────────────────────────────────────────────────────────────┤
│ 第 4 层  Application / ApplicationSet（Argo CD 侧）            │
│   回答：拉哪个目录、哪个分支？部署到哪、去哪个 namespace？        │
│   位置：Application.spec.source / spec.destination              │
└────────────────────────────────────────────────────────────────┘
```

**所以正确的表述是：**

> "GitHub App 的 **Installation** 决定**能访问哪些源码仓库**；
> **Webhook** 决定**何时通知**；
> 而**真正的源代码管理（哪些文件是部署物、谁改、怎么 review）发生在 Git 仓库本身**，
> Argo CD 只是 Git 的消费者。"

⚠️ 由此推出一条**重要的安全结论**：
**Webhook URL 填错 / 事件没订阅 → 只是延迟变大；**
**Installation 授权范围过大 → 才是真正的越权风险**。
所以审 GitHub App 时，重点看 **Permissions（读什么）+ Installation（装在哪些仓库）**，
而不是盯着 Webhook URL。

---

## 5. Webhook 是不是"真正的发布地方"？—— 要看说的是哪一种"发布"

> ⚠️ **本节以 Argo CD 场景为主**（业务应用由 Argo CD 发布）。
> **自研 GitHub App 后端的场景见 §5.5** —— 那里的结论与本节**相反**，
> 请务必读 §5.5 再下结论。

### 5.1 完整发布链路（Webhook 只是第 2 步）

```
 ① 开发 push
      │  Git 仓库
      ▼
 ② GitHub 收到 push → POST 事件到 Webhook URL
      │  argocd-server /api/webhook/github
      │  ★ Webhook 只做一件事：把对应 Application 标记为"需刷新"
      ▼
 ③ application-controller 感知 → git fetch → 渲染（Kustomize/Helm）
      ▼
 ④ 对比 live state 与目标状态 → OutOfSync
      ▼
 ⑤ sync → 调目标集群的 Kubernetes API → 资源真正被创建/更新
      ▼
 ⑥ 应用"上线"。它的访问地址取决于应用形态：
      - ClusterIP / Service / Ingress / Gateway → 由 Ingress 域名决定
      - 与 Webhook URL 毫无关系
```

**结论（Argo CD 场景）：Webhook URL 指向的是"控制面入口"，不是"应用运行地址"。**
应用跑在目标集群里，它的 URL 由 Ingress / Gateway 决定。

### 5.2 Webhook 挂了会怎样（重要）

**不会永久卡住**，只会变慢。仓库里已有结论（[`poc-argocd-git-to-apply-trigger.md`](../../poc-argocd-git-to-apply-trigger.md) §3）：

| 触发路径 | 正常延迟 | 备注 |
|---|---|---|
| Webhook | 秒级 | 事件驱动 |
| Argo CD 定时 resync | ~2 min + 60s jitter | 兜底 |
| ApplicationSet git generator requeue | 默认 180s | 兜底 |

> **关键认知：webhook 只影响阶段 ① 的延迟，不决定 ②③④ 是否发生。**
> 丢掉 webhook → 退化为周期轮询，不会永久卡住。

### 5.3 本仓库的两套 webhook 端点（选哪个填进 GitHub App）

| 端点 | Service / 端口 | 触发什么 | 需不需要自建 Ingress |
|---|---|---|---|
| **Argo CD API webhook** | `argocd-server` :80/:443 | `POST /api/webhook/github` → **刷新 Application** | 用现有 Argo CD Ingress 即可 |
| **ApplicationSet webhook** | `argocd-applicationset-controller` :7000 (`/api/webhook`) | 重新生成 Application | **需要自建 Ingress**（ClusterIP 不可外网访问） |

> 事实依据（本仓库 `install.yaml`）：`argocd-applicationset-controller` 容器端口
> `containerPort: 7000`（name: webhook）、`containerPort: 8080`（name: metrics）；
> `argocd-server` 容器端口 `containerPort: 8080`。
> 详细推导见 [`poc-argocd-git-to-apply-trigger.md`](../../poc-argocd-git-to-apply-trigger.md) §3.1。

**推荐做法（一个 App 只能有一个 Webhook URL）：**

```
GitHub App ──Webhook URL──▶ https://argocd.example.com/api/webhook/github
                              （argocd-server，已有 Ingress，直接可用）

ApplicationSet 的 180s requeue 作为兜底，不额外建 App
```

如果确实需要 appset 秒级，再单独建**第二个 GitHub App** 指向 `:7000`，
并为 `argocd-applicationset-controller` 单独建 Ingress —— 成本大于收益，
默认不做。

### 5.4 Webhook secret

GitHub 侧配置 Webhook secret，Argo CD 侧必须配同一个值，否则事件会被拒：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  webhook.github.secret: "<与 GitHub Webhook 配置里的 Secret 完全一致>"
```

### 5.5 补充：自研 App 场景下的正确表述（别把两种"发布"混在一起）

前面 §5.1–§5.4 全部站在 **Argo CD 场景**上说话，结论是：
"Webhook URL 不是发布地址，发布发生在下游集群。"

**但如果是你要开发的 CR Check（Go 自研后端），结论要反过来：**

```
你的 Go 代码 (Git 仓库)
      │  CI 构建镜像
      ▼
   镜像 (GHCR / Artifact Registry)
      │  Argo CD apply
      ▼
   K8s Deployment → Pod 监听 :8080
      │  Service :80 → Ingress (TLS, 公网域名)
      ▼
   https://cr-check.example.com/github/webhook   ← ★ 这就是 Webhook URL
      │
      │  GitHub 事件投递进来
      ▼
   你的 handler 跑判定 → 写 check run
```

| 问题 | 自研 App 场景的答案 |
|---|---|
| Webhook URL 是谁提供的？ | **你自己**（DNS + Ingress + 证书 + 你的服务） |
| Webhook URL 和我的服务什么关系？ | **它就是我的服务的公网地址**（域名 + 路径） |
| 我需要"做一次服务发布"吗？ | ✅ **需要**。Git 里的代码不会自己跑起来：镜像 → Deployment → Pod → Service → Ingress → 域名 → TLS → 填进 GitHub App |
| 填完 URL 但服务没起来会怎样？ | GitHub 侧的 `ping` 事件投递失败 → 后续所有事件投递失败 → **门禁静默失效**（详见 [`webhook-and-backend-service.md`](./webhook-and-backend-service.md) §8） |
| 服务换地址怎么办？ | 改 GitHub App 里的 Webhook URL（**旧地址立即失效**），所以要先准备好新地址再切 |

**所以完整、准确的一句话是：**

> **Webhook URL 是"事件通知的收件地址"。**
> 在 **Argo CD** 场景里它指向既有组件（`argocd-server`），与业务应用上线无关；
> 在 **自研 App** 场景里它**恰好就是你自己部署的后端服务的公网地址** ——
> 这也正是"Webhook 和我的服务是什么关系"这个问题的答案：
> **Webhook URL = 你的服务在公网上的地址 + 路径。**

> 📌 **配套专题**：[`webhook-and-backend-service.md`](./webhook-and-backend-service.md)
> 完整讲了"Go 代码怎么从 Git 变成一个 GitHub 能访问到的服务"（8 步 + 配置清单 + 故障速查）。

### 5.6 自研 App 与 Argo CD 的并排对照（收束 §5.5）

| | Argo CD 的 GitHub App（形态 A） | 自研 CR Check App（形态 B） |
|---|---|---|
| Webhook URL 指向 | 既有组件 `argocd-server`（**不用你发布任何东西**） | **你自己部署的 Go 服务**（Ingress + 域名 + TLS） |
| 需不需要写后端代码 | ❌ 不需要 | ✅ 需要 |
| 需不需要公网入口 | ✅（复用现有 Argo CD Ingress） | ✅ **必须新建**（外部 IP + 证书 + DNS） |
| 权限 | `Contents: Read` | `Metadata:R` + `Pull requests:R` + `Checks:Write` |
| 一个 App 只能一个 Webhook URL | ⇒ 天然建议**建两个 App**（权限面也不同） | |

---

## 6. 落到 Argo CD：一份完整配置清单

```
GitHub 侧
├─ App ID                     ─┐
├─ Private Key (RSA)          ─┼─▶ Argo CD Repository Secret
├─ Installation ID            ─┘
├─ Permissions: Contents(Read) + Metadata(Read)
├─ Subscribe events: Push（够用时只勾 Push）
├─ Webhook URL: https://argocd.example.com/api/webhook/github
├─ Webhook secret: <与 argocd-cm 一致>
└─ Install to: 目标组织 → 选择目标仓库

Argo CD 侧
├─ Secret/argocd-cm: webhook.github.secret
└─ Secret/<repo-secret>:
     labels: argocd.argoproj.io/secret-type: repository
     stringData:
       url: https://github.com/example/platform.git
       githubAppID: "123456"
       githubAppInstallationID: "98765432"
       githubAppPrivateKey: |
         -----BEGIN RSA PRIVATE KEY-----
         [REDACTED PRIVATE KEY]
         -----END RSA PRIVATE KEY-----
       project: platform

Application / ApplicationSet 侧
├─ spec.source.repoURL: https://github.com/example/platform.git
├─ spec.source.path: apps/foo
├─ spec.source.targetRevision: main
└─ spec.destination: { server: ..., namespace: foo }
```

完整 Repository Secret 示例见
[`examples/argocd-repositories-githubapp.yaml`](../examples/argocd-repositories-githubapp.yaml)。

---

## 7. 排查表

| 现象 | 根因 | 处理 |
|---|---|---|
| 想知道"这个 App 能读哪些仓库" | Installation 列表才是答案 | GitHub → App → Installations → Configure |
| 想看业务源码在哪 | Application 的 source 字段 | Argo CD UI → Application → SOURCE；`argocd app get <app> -o jsonpath='{.spec.source}'` |
| 找不到"这个 App 的代码" | GitHub App 本身通常**没有**代码 | 它只是配置 + 私钥；只有走 OAuth/本地处理事件才需要写后端 |
| push 了但 Argo CD 没反应 | 事件没订阅 / Webhook URL 不可达 / secret 不一致 | GitHub → App → Webhooks → Recent Deliveries；核对 `argocd-cm` 的 secret |
| 私有仓库报 401/403 | Installation 没勾到这个仓库 / App ID 与私钥不配对 | 核对 installation 授权范围；核对 ID + 私钥同属一个 App |
| Webhook 事件到了但 AppSet 没重新生成 | 装的是 appset webhook 而不是 server webhook | 指向 `:7000` 的端点，或接受 180s 轮询 |
| 想"删掉 webhook 试试" | 会退化为轮询，不是彻底关闭同步 | 临时把 GitHub App 的 Webhook URL 改掉即可观察 |

---

## 8. 速查：谁是谁

```
GitHub App          = 身份（机器人）        → Argo CD 的 Repository Secret 里那三件套
Installation        = 授权边界（哪些仓库）   → githubAppInstallationID
Public link         = 橱窗（公开主页）       → 给人看的
Homepage URL        = 门牌号（宣传页）       → 给人看的
Webhook URL         = 收件地址（入站事件）   → 给 GitHub 服务器 POST 的
Callback URL        = OAuth 回调（本方案不用）→ 给浏览器跳转的
Git 仓库             = 源码 + manifest      → Application.spec.source 指向它
Argo CD             = 消费者 + 执行器       → apply 到集群 = 真正的"发布"
```

---

## 9. 标注说明

| 标注 | 本文中对应内容 |
|---|---|
| **官方保证** | GitHub App 一个只有一个 Webhook URL；App 与 Installation 的区分；Private Key → installation token 机制 |
| **当前清单事实** | `argocd-applicationset-controller` 的 7000/8080 端口；`argocd-server` 的 8080 容器端口（来自本仓库 `install.yaml`） |
| **推荐实现** | Webhook URL 指向 `argocd-server /api/webhook/github`；Homepage URL 填 Argo CD 控制台地址；权限最小化（Contents/Metadata: Read） |
| **部署前验证项** | "Public link" 的界面文案与 Public 开关位置；GitHub 对 Homepage URL 的具体校验规则 |

---

## 10. 关联文档

| 主题 | 文档 |
|---|---|
| GitHub App 三要素 + Repository Secret 完整字段 | [`07-repository-githubapp.md`](../07-repository-githubapp.md) |
| Git → webhook → refresh → apply 全链路 | [`../poc-argocd-git-to-apply-trigger.md`](../../poc-argocd-git-to-apply-trigger.md) |
| Application 字段详解 | [`../argocd-application-guide.md`](../../argocd-application-guide.md) |
| ApplicationSet Git generator | [`05-appset.md`](../05-appset.md) |
| 排障（凭据 / 同步类） | [`09-troubleshooting.md`](../09-troubleshooting.md) |
| **自研 GitHub App 评估 + Go 实现骨架 + 时间窗口难点** | [`Develop-git-apps.md`](./Develop-git-apps.md) |
| **Webhook 与后端服务：代码怎么跑起来、Webhook URL 与服务的关系** | [`webhook-and-backend-service.md`](./webhook-and-backend-service.md) |
| **外部交互模型：轮询(pull) → Webhook(push) 的契约变化与迁移路线** | [`12-webhook-push-vs-pull.md`](./12-webhook-push-vs-pull.md) |
| **CR Check（Go）的设计与实现评估、包结构、接口、里程碑** | [`13-cr-check-go-design.md`](./13-cr-check-go-design.md) |

---
---

# Part B · 场景：生产变更加闸（PR merge 必须有 Change Request）

> **场景复述**
> GKE 上跑着由 Argo CD 管理的应用。开发提 PR，merge 到生产分支就上生产。
> 现在要求：**任何上生产的 PR，必须有一个对应的 Change Request（变更单，
> 一个编号），并且这个变更单通过了规定的审批规则。**
>
> 问题：
> 1. 这套东西**应该在哪里实现**？
> 2. **GitHub App 能不能实现它**？
> 3. 需求还很模糊，**怎么把它变成可编码的规则**？

---

## 11. 需求拆解：把"必须有一个 CR"翻译成可实现的规则

### 11.1 术语消歧：三种 "CR"

这个场景里 "CR" 有三个完全不同的含义，**混用会直接导致方案选错**：

| 缩写 | 含义 | 本文写法 |
|---|---|---|
| **CR** | Change Request，变更单（一个编号，如 `CR-1234`） | **变更单** |
| **CR** | Custom Resource，K8s 自定义资源 | **CustomResource**（如 `ChangeRequest` CRD） |
| **CR** | ClusterRole | **ClusterRole** |

> 下文一律写 **变更单**；如果变更单用 K8s 实现，就叫 `ChangeRequest` 这个 CustomResource。

### 11.2 现有链路（没有闸门时）

```
① 开发提 PR → ② 评审 → ③ merge 到 main
                                     │
                                     ▼
                        ④ Argo CD 检测到 commit 变化
                                     │  (webhook 秒级 / 轮询 120s)
                                     ▼
                        ⑤ sync → apply 到生产 GKE 集群
                                     │
                                     ▼
                        ⑥ 新版本已经在生产上跑
```

**问题：③ 和 ⑤ 之间没有任何检查点。** 评审通过了 ≠ 变更被批准。
"合并"和"上线"是同一个动作，中间没有"变更单"这道闸。

### 11.3 目标链路（加闸后）

```
① 开发提 PR ───────────────────────────────────────────────┐
   PR 上带变更单号（label / body / commit trailer）           │
                                                             ▼
② 【门禁 A】GitHub App 校验变更单 → 回写 Check Run
   check 不绿 → GitHub branch protection 阻止 merge
                                                             │
   ✅ check 绿（= 变更单存在、合规、已审批）
                                                             ▼
③ merge 到 main → ④ Argo CD 检测到变化
                                                             │
                                                             ▼
⑤ 【门禁 B】Argo CD Extension（同步前调用变更查询接口）
   不合规 → deny → sync 失败，Application 停在 OutOfSync，集群零变更
                                                             │
   ✅ 放行
                                                             ▼
⑥ apply 到生产 GKE 集群
                                                             │
                                                             ▼
⑦ 【门禁 C】Gatekeeper / ValidatingAdmissionPolicy（准入兜底）
   任何写入者（包括绕过 Argo CD 的 kubectl）若资源缺少
   "已批准变更单"注解 → 集群 API 直接拒绝
```

**三道闸的作用完全不同，缺一不可：**

| 闸 | 位置 | 拦谁 | 拦不住 |
|---|---|---|---|
| **A · 合并门** | GitHub merge 前 | 走 PR 流程的人 | 直接 `git push`、直接 kubectl |
| **B · 同步门** | Argo CD apply 前 | Argo CD 自己 | 绕过 Argo CD 直接写集群 |
| **C · 准入门** | K8s API 写入时 | **所有人**（含 Argo CD） | 绕过集群入口（几乎没有） |

### 11.4 规则清单（可编码的形态）

需求定稿成下面这张表 —— 每一条都对应"在哪里判、判什么、不通过怎么办"：

| ID | 规则 | 判定数据来源 | 判定位置 | 不通过的后果 |
|---|---|---|---|---|
| **R0** | 触发时机：`pull_request` 的 `opened / synchronize / reopened / labeled / unlabeled / ready_for_review` | GitHub 事件 | GitHub App | —（不触发 = 没人评估） |
| **R1** | PR 必须携带变更单号（`cr/1234` label，或 body 含 `Change-Request: 1234`） | PR 元数据 | GitHub App | check 红，禁 merge |
| **R2** | 变更单存在（编号可在变更系统查到） | 变更系统 / CRD | GitHub App | check 红 |
| **R3** | 变更单状态 = Approved（非 Draft / Rejected / Expired） | 变更系统 / CRD | GitHub App | check 红 |
| **R4** | 审批充分：审批人 ≥ N（默认 2），且审批人 ≠ 提单人，且审批人 ∈ 授权组 | 变更系统 / CRD | GitHub App | check 红 |
| **R5** | 目标一致：变更单的 `targetEnv` = PR base 分支映射的环境；`targetRefs` 覆盖 PR 改动范围 | 变更系统 / CRD | GitHub App | check 红 |
| **R6** | 时效：变更单未过期（默认 7 天），且 merge 时刻在有效期内 | 变更系统 / CRD | GitHub App | check 红 |
| **R7** | 唯一性：同一变更单不能被两个 PR 同时占用（防重复上线） | 变更系统 / CRD | GitHub App | check 红 |
| **R8** | 紧急通道：`emergency/xxx` label + 事后审计（break-glass） | PR label + 变更系统 | GitHub App | 放行但**必须留痕 + 事后复查** |
| **R9** | 放行条件：以上全过 → check 绿，GitHub 允许 merge | — | GitHub App | — |
| **R10** | 反馈可读：check 详情里写明**哪条规则**不通过、缺什么 | — | GitHub App | — |
| **R11** | 审计留痕：谁、何时、哪个 PR、哪个变更单、命中哪些规则、结论 | — | 变更系统 + GitHub check | — |
| **R12** | 部署侧联动：merge 后部署的版本必须能回溯到变更单号（写进镜像 tag / annotation / release 分支） | Git | Argo CD / 变更系统 | 事后无法追溯 |

> **R12 是很多团队漏掉的一条**：只有"卡住 merge"没有"事后可追溯"，
> 半年后问"生产上这版是谁批的"，没人答得上来。
> 最省事的做法：**commit trailer 里带变更单号** ——
> 它同时能被校验器读（门禁 A）、被 Argo CD 侧读到（审计）、被 `git log` 追溯。

### 11.5 需求定稿检查表

```
☐ 变更单编号长什么样？（CR-1234 / 纯数字 1234 / URL）
☐ 变更单存在哪？（外部变更系统 / K8s CRD）
☐ 谁有权批准？（组 / 角色 / 名单）
☐ 需要几个审批？审批人能不能是提单人？
☐ 哪些分支算"生产"？（main / release / prod/* → 环境映射表）
☐ 变更单有效期多长？过期后 merge 怎么办？
☐ 紧急通道走不走？走的话谁授权、事后谁复查？
☐ 生产是自动 sync 还是人工 sync？（影响门禁 B 的位置）
☐ 绕过路径要不要拦？（kubectl 直改 → 门禁 C）
```

---

## 12. 结论先行：GitHub App 能不能实现这个？

**能实现"卡合并"这一半，而且它是这件事最合适的入口；
但它不能单独完成整件事。**

| 能力 | GitHub App 能否做 | 说明 |
|---|---|---|
| 收到 PR 事件（opened / synchronize / labeled） | ✅ | 这正是 App 的本职（webhook 事件） |
| 读取 PR 的 label / body / diff 范围 | ✅ | 需要 `Pull requests: Read` |
| 查询变更单状态 | ✅ | App 后端调用变更系统 API，或读集群内 CRD |
| **回写 Check Run**（绿/红 + 原因） | ✅ | 需要 `Checks: Write` |
| **真正阻止 merge** | ⚠️ **不能自己阻止** | 必须靠 **branch protection 的 required status checks**：check 不绿 → GitHub 不让 merge |
| **审批变更单** | ❌ | 审批是"人"的动作，App 不能替人批准；只能**校验**已发生的审批 |
| 约束"绕过 PR 直接改生产分支" | ❌ | 靠 GitHub 分支保护 / CODEOWNERS / API 令牌权限 |
| 约束"绕过 Git 直接改集群" | ❌ | **必须**靠门禁 C（K8s 准入） |
| 约束 Argo CD 的 apply 行为 | ❌ | App 的事件和 Argo CD 的 sync 是两套系统，**没有任何直接联系** |
| 记住"这个 App 之前被怎么批准过" | ⚠️ | 状态存在变更系统里，不在 App 里 |

> **一句话**：**GitHub App 是"哨兵"（发现越界 + 上报），不是"法官"（规则）和不是"狱警"（强制力）。**
> 规则住在变更系统，强制力住在 branch protection + K8s 准入。

---

## 13. "在哪里实现"：五个候选位置的对比

| 位置 | 放什么 | 强制力 | 覆盖范围 | 评价 |
|---|---|---|---|---|
| **① 变更系统本身** | 审批流、规则引擎、状态机 | 弱（只能"记录"） | 单一系统内 | ✅ **真相源，必备**。规则、审批、留痕都该在这 |
| **② GitHub App 后端** | 事件接收 + 规则判定 + Check 回写 | **中**（只对走 PR 的人有效） | PR 流程 | ✅ **门禁 A 的实现地** |
| **③ GitHub branch protection** | required status checks | **强**（GitHub 层面禁止 merge） | 本仓库分支 | ✅ **门禁 A 的强制力来源**（不是 App，是它） |
| **④ Argo CD Extension** | 同步前调用变更查询接口并 deny | **中**（只对 Argo CD 有效） | Argo CD 同步 | ✅ **门禁 B 的实现地** |
| **⑤ Gatekeeper / ValidatingAdmissionPolicy** | 准入时校验"已批准变更单"注解 | **强**（拦所有写入者） | 集群全部写入 | ✅ **门禁 C，兜底必备** |

**不推荐 / 已排除的位置：**

| 位置 | 为什么不用 |
|---|---|
| **Argo Workflows + `suspend` 人工闸门** | 与 [`10-argo-workflows-evaluation.md`](../10-argo-workflows-evaluation.md) 的结论冲突（**不引入 Argo Workflows**）。人工审批用 Sync Window + RBAC + Extension 已能覆盖 |
| **CI 流水线里校验** | ✅ **能做，也能阻止 merge**（Actions 的 job 同样产生 status check，可设为 required）。短板是 **workflow 文件与被保护代码同仓库 → 可被同一 PR 绕过**、复杂规则难用 YAML 表达。详见 [`Develop-git-apps.md`](./Develop-git-apps.md) §6、§12.1 |
| **Argo CD `syncPolicy.automated` 里写条件** | Argo CD **没有**"条件满足才同步"的原生表达式；要么用 Extension，要么用 AppProject / Sync Window / 手动 sync |

---

## 14. 推荐架构（三层门禁 + 一个真相源）

```
┌──────────────────────────────────────────────────────────────────────────┐
│ 真相源：变更系统                                                          │
│   方案 A：外部变更平台（Jira/自研）                                        │
│   方案 B：K8s CustomResource（ChangeRequest CRD + ChangeRequestApproval） │
│   ★ 规则、审批、留痕都在这里；App 和 Argo CD 都只是它的查询方            │
└──────────────────────────────────────────────────────────────────────────┘
        ▲ 查询（只读）            ▲ 查询（只读）
        │                         │
┌───────┴──────────┐      ┌───────┴────────────────────────┐
│ GitHub App 后端   │      │ Argo CD Extension（同步前校验）   │
│ (pr-gate, 跑在 GKE)│      │ (argocd-cm extensions:)         │
│                   │      │ 渲染 manifest → 调用变更查询    │
│ 收 PR 事件        │      │ → 不合规则 deny，sync 失败      │
│ 跑 §11.4 规则     │      └────────────────┬───────────────┘
│ 回写 Check Run    │                       │ deny
└───────┬──────────┘                       ▼
        │ check 绿                    sync 失败 / OutOfSync
        ▼                            集群零变更
┌────────────────────────┐
│ GitHub 分支保护         │  ← 强制力：required status checks
│ main: require checks   │
│   ✓ change-request/ok  │
└────────────────────────┘
        │
        │ merge 后
        ▼
┌────────────────────────┐   ┌──────────────────────────────┐
│ Argo CD sync（生产应用）│──▶│ 门禁 C：Gatekeeper 准入       │
│ 自动 sync / 变更单驱动  │   │ 资源必须带 approved CR 注解  │
└────────────────────────┘   │ 否则集群 API 拒绝（403）      │
                             └──────────────────────────────┘
```

### 14.1 门禁 B 的两种实现（选一）

**方式 A：Argo CD Extension（推荐 —— 已有本地文档支持）**

```yaml
# argocd-cm
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  extensions: |
    - name: change-request-gate
      extension:
        url: https://pr-gate.change-requests.svc.cluster.local/gate
        headers:
        - name: Authorization
          value: "[REDACTED]"
        timeout: 10
```

同步链路中的位置（与本地 [`06-opa-gatekeeper-impact.md`](../06-opa-gatekeeper-impact.md) §3.1 方式 B 一致）：

```
检测到差异 → 渲染 manifest → 调用 extension → allow / deny
```

- deny 的表现：sync 失败，Application 停在 OutOfSync，**集群零变更**
- Extension 收到的 payload 里带仓库/路径/commit，扩展接口可据此回查该 commit 里的变更单号（commit trailer）
- ⚠️ **部署前验证项**：Argo CD Extensions 能力需确认当前版本（v3.5.6 清单）是否可用，以及 payload 字段名

**方式 B：PreSync Hook**（本地 [`06`](../06-opa-gatekeeper-impact.md) 推荐的最常用做法）

用 Argo CD 的 `syncHooks`（PreSync）跑一个 Job 去查变更单，查不到就 `exit 1` → sync 失败。
- 优点：机制最通用、可跑任意逻辑、能拿到渲染结果
- 缺点：每次同步多一个 Pod 的启动延迟；Hook 失败会持续重试

### 14.2 生产应用本身的加固

```
① 生产 Application 关掉自动同步（syncPolicy.automated 不配）→ 只能由"放行动作"触发
② AppProject 设 disableManualSync: true → 任何人不能在 UI 上手点同步
③ 用 Sync Window 限定发布窗口（allow/deny），只放行既定窗口
④ 放行动作由谁触发？
   - 变更单 Approved 后，变更系统回调 Argo CD API 触发 sync（需 argocd-server 账号）
   - 或把"批准"变成 Git 里的一次提交（release 分支推进）→ 纯 GitOps，无回调
```

> **推荐 ④ 的第二种**：把"审批"物化成 **Git 里的一次提交**（例如推进 `release/prod` 分支或打 tag），
> 这样"批准 → 部署"仍然是纯声明式的、可审计的、无需 Argo CD API 写权限。

---

## 15. GitHub App 侧的具体实现清单

### 15.1 App 注册参数

| 项 | 值 | 说明 |
|---|---|---|
| **Permissions** | `Metadata: Read`（必需）<br>`Contents: Read`<br>`Pull requests: Read`<br>`Checks: Write` | 只读 + 只写 check，**不要**给 `Contents: Write` |
| **Subscribe to events** | `Pull request` | 需要 `opened / synchronize / reopened / labeled / unlabeled / ready_for_review` |
| **Webhook URL** | `https://<gke-ingress>/github/webhook` | 见 §18 |
| **Webhook secret** | 与 Argo CD `argocd-cm` 同一套管理 | 校验 `X-Hub-Signature-256` |
| **Homepage URL** | Argo CD 控制台地址 | 纯展示 |
| **Public link** | 系统生成 | 建议保持 **Private**（只允许本组织安装） |

> 如果还要在 PR 上留评论（把不通过原因贴回 PR 而非只看 check），
> 再加 `Pull requests: Write`；纯 check 详情就够的话不必给。

### 15.2 Check 的命名（必须与分支保护完全一致）

```
check 名称： change-request/approved
```

- 分支保护里的 "required status checks" 填的名字，必须与 App 创建 check run 时的
  `name` **逐字符一致**（含斜杠），否则保护规则不会等这个 check
- check 必须挂在 **PR 的最新 head SHA** 上；
  `synchronize`（又 push 了一次）之后旧 check 失效 → **必须重跑并覆盖同名 check**

### 15.3 变更单号的解析（三种载体，建议双写）

| 载体 | 示例 | 谁读 | 评价 |
|---|---|---|---|
| **PR label** | `cr/1234` | 校验器 | ✅ 最机读，机器友好；label 改名 = 改引用 |
| **PR body marker** | `Change-Request: 1234` | 校验器 + 人 | ✅ 人友好，便于在 PR 模板里固化 |
| **commit trailer** | `Change-Request: 1234` | 校验器 + Argo CD + `git log` | ✅ **部署侧也能读到**，事后追溯用 |

**建议：label + commit trailer 双写**。label 用于门禁判定，trailer 用于部署侧审计与追溯。

### 15.4 校验器服务的实现要点

```
① 验签：X-Hub-Signature-256（HMAC-SHA256，key = webhook secret）
② 幂等：X-GitHub-Delivery 做去重键；GitHub 会重投同一事件
③ 事件白名单：只处理 pull_request / pull_request_review，其余返回 200 忽略
   ★ 推给 Argo CD 的 push 事件如果也到这个端点，要原样透传（§18.3）
④ 判定：按 §11.4 的 R1–R10 逐条求值，收集失败原因
⑤ 回写：创建/更新 check run
   - 通过 → conclusion=success，summary 写变更单号 + 审批人 + 生效时间
   - 不通过 → conclusion=failure，output 里逐条列出 R1/R4… 哪条不满足、缺什么
⑥ 留痕：把本次判定写进变更系统（审计），不要只存在 GitHub check 里
```

### 15.5 校验器的"规则"写在哪

**这是个关键决策点：规则不能写在 App 的代码里，否则改规则 = 改代码 = 走部署。**

| 层 | 放什么 | 变更方式 | 保护 |
|---|---|---|---|
| **规则数据**（阈值、映射表、例外） | ConfigMap（Git 里管理） | 改 Git → Argo CD sync | 受 CODEOWNERS 保护 |
| **规则判定逻辑**（怎么算合规） | 校验器代码（Git 里管理） | 改 Git → CI → 部署 | 受 CODEOWNERS 保护 |
| **变更单状态与审批** | 变更系统 / CRD | 人在变更系统里操作 | 受 RBAC 保护 |

**并且要意识到一个递归问题**：校验器自己也是一个被 Argo CD 部署的应用 ——
**攻击者如果能提一个 PR 改掉校验器的规则，就等于绕过了门禁。**
所以：

- 校验器所在仓库必须**限制修改者**（CODEOWNERS + 保护分支 + 签名 commit 要求）
- 校验器的**配置**（尤其例外名单）要有**双人复核**（CODEOWNERS 要求两人 approve）
- 最强的一层：校验器读取的"例外名单"放在**集群内的 ConfigMap**，由平台仓库管理，
  而集群里的 ConfigMap 改动又会被门禁 C 的 Gatekeeper 策略约束（改配置也要合规变更单）→ **闭环**

---

## 16. 如果变更单用 Kubernetes CustomResource 实现

### 16.1 CRD 骨架

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: changerequests.changes.example.com
spec:
  group: changes.example.com
  names:
    kind: ChangeRequest
    plural: changerequests
  scope: Namespaced
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              number:        { type: integer }
              requester:     { type: string }
              targetEnv:     { type: string }     # dev | staging | prod
              targetRefs:    { type: array, items: { type: string } }
              expiresAt:     { type: string, format: date-time }
              status:        { type: string }     # Draft | Approved | Rejected | Expired
            required: [number, requester, targetEnv, status]
          # ⚠️ 审批不放这里 —— 见 16.2
```

> 术语提醒：这是一个 **CustomResource（CR）**，不是"变更单"的缩写。
> 集群里同时存在 `ChangeRequest` 这种 CR 和"变更单"这个业务概念，
> 命名上建议加前缀区分（例如 `ProdChangeRequest`），否则 code review 时
> "CR" 到底是哪个意思会吵架。

### 16.2 审批为什么要独立成另一个资源

```yaml
apiVersion: changes.example.com/v1alpha1
kind: ChangeRequestApproval
metadata:
  name: cr-1234-approval-bob
spec:
  changeRequestRef: cr-1234
  approver: bob@example.com
  decision: approve
```

**理由：审批动作本身需要被授权。**

```
"审批人" ≠ "任何人能改 status 字段"
```

- 如果审批只是一个 `spec.approvers: [...]` 字段，
  那么**任何有 update 权限的人都能把自己写进去** → 自审批可伪造
- 独立成 `ChangeRequestApproval` 后：
  - **RBAC**：只有审批组能 `create` 这个资源；提单人所在组只有 `create` ChangeRequest
  - **CEL 校验**（`x-kubernetes-validations`，K8s 1.29+ GA）：
    `self.approver != <提单人>` 之类的不变量可以直接写在 CRD 里
  - **Gatekeeper**：跨对象校验（提单人 ≠ 审批人）用 Gatekeeper 更自然

> ⚠️ **部署前验证项**：目标 GKE 版本是否支持 CRD CEL validation rules；
> 若不支持，退化为 Gatekeeper ConstraintTemplate 或外部准入策略。

### 16.3 校验器怎么读到变更单

校验器**跑在集群里**，直接用 ServiceAccount 读 CRD：

```yaml
# ClusterRole（只读，最小权限）
rules:
- apiGroups: ["changes.example.com"]
  resources: ["changelists", "changelists/status"]   # ChangeRequest/Approval
  verbs: ["get", "list", "watch"]
```

**好处**：校验器不需要访问任何外部变更系统 API，也不必把集群数据推到公网。
**注意**：这是 `list` 权限，意味着校验器能读到**全部**变更单 —— 如果变更单含敏感信息，
用 namespace 隔离（专门的 `change-requests` namespace）而不是靠 RBAC 逐条过滤。

### 16.4 门禁 C（准入兜底）的落地

生产资源上强制带注解，Gatekeeper 校验注解引用的变更单已批准：

```yaml
# 生产 Deployment / StatefulSet 等必须有：
metadata:
  annotations:
    changes.example.com/change-request: "1234"
```

Gatekeeper 策略大意：

```
① 若 namespace 属于生产清单：
     必须存在 changes.example.com/change-request 注解
② 该注解引用的 ChangeRequest 必须存在且 status=Approved
③ （可选）该变更单的 targetEnv 必须 = prod
```

- 违规时：K8s API 返回 **403**，Argo CD 侧表现为 sync 失败 + Application OutOfSync
  （本地 [`06-opa-gatekeeper-impact.md`](../06-opa-gatekeeper-impact.md) §4/§5 有完整链路与
  `resource.customizations.ignoreDifferences` 的排障做法）
- ⚠️ Gatekeeper `failurePolicy: Fail` 时 Gatekeeper 挂了 = 整个集群写入中断，
  必须 ≥2 副本 + PDB（本地 doc 06 §4.4 已强调）

---

## 17. 部署形态：校验器放哪、怎么被 GitHub 访问

### 17.1 三种放置方案

| 方案 | 校验器跑在 | GitHub 访问方式 | 优点 | 缺点 |
|---|---|---|---|---|
| **A. GKE 内（与被管应用同集群）** | GKE，namespace 如 `pr-gate` | GKE Ingress（外部 LB + 静态 IP + TLS） | 与变更单 CRD 同集群（读取快、免出网）；完全 GitOps | 需要公网入口 + 证书；出网要 Cloud NAT |
| **B. Cloud Run** | Cloud Run | Cloud Run 默认域名（自带 HTTPS） | 公网入口零成本 | 与"内部开发在 GKE"的要求有偏差；变更单在集群内需出网读 |
| **C. 独立 GKE 集群** | 独立集群 | 该集群 Ingress | 生产与管理面隔离 | 成本高，跨集群读 CRD 麻烦 |

> **推荐 A**：需求是"内部在 GKE 上开发"，且变更单本身就在集群里（§16 的方案）。
> 校验器直接读本地 CRD，链路最短，GitOps 也最自然。

### 17.2 GKE 方案的落地要点

```
① 静态 IP：gcloud compute addresses create pr-gate-ip --region=...
② Ingress（GKE）→ 指向 pr-gate Service 80 → Deployment 8080
③ TLS：Google 托管证书（Certificate Manager / ManagedCertificate）或 cert-manager
④ DNS：pr-gate.example.com → 静态 IP
⑤ 出网：节点/Cloud NAT 能访问 api.github.com（校验器要回写 check）
⑥ 鉴权：只有 GitHub 能打进来不现实 → 靠 HMAC 验签 + 事件类型白名单 + 可选 IP 白名单
```

### 17.3 ⚠️ 一个 App 一个 Webhook URL —— 怎么和 Argo CD 共存

回顾 §2.3：**一个 GitHub App 只能配一个 Webhook URL**，
但这里需要两个接收端：

```
push 事件          → argocd-server  /api/webhook/github   （触发 Application 刷新）
pull_request 事件  → pr-gate        /github/webhook       （触发变更单校验）
```

三种解法：

| 方案 | 做法 | 评价 |
|---|---|---|
| **① 两个 GitHub App** | App-A（Argo CD 凭据用）+ App-B（校验器用） | ✅ **最干净**：权限分离，App-B 权限可以做到极小；代价是多维护一个 App |
| **② 一个 App + 事件路由网关** | webhook 打到网关，网关按 `X-GitHub-Event` 分流 | 优雅但多一个组件，网关自身成了关键路径 |
| **③ 一个 App，校验器内部转发** | webhook 全打到 pr-gate，pr-gate 收到 `push` 事件后**原样透传**给 Argo CD | ✅ **最省事**：20 行代码；透传时 body 不变、连同原 `X-Hub-Signature-256` 一起转发，Argo CD 侧验签自然通过 |

> **推荐 ① 或 ③**。
> ③ 的额外好处：GitHub App 的 Webhook URL 从此有了"真正的业务含义" ——
> 它既是变更单校验的入口，也是生产变更的**唯一事件闸口**，可审计、可限流。
> 代价是 pr-gate 挂了会同时影响"变更单校验"和"秒级同步"（但轮询兜底仍在，不影响最终收敛）。

---

## 18. 校验器本身怎么被 GitOps 管住（自举）

```
Git 仓库（pr-gate 或 gitops 仓库的 tools/pr-gate/）
  ├─ src/                 校验器代码
  ├─ config/rules.yaml    规则数据（阈值、环境映射、例外）
  ├─ deploy/              Deployment / Service / Ingress / ServiceAccount / ClusterRole
  └─ kustomization.yaml
        │
        │ Argo CD（Application，指向这个仓库）
        ▼
   GKE 集群里的 pr-gate Deployment
```

**但要解决"递归问题"**：谁能改这个仓库，谁就能改门禁。

| 控制 | 做法 |
|---|---|
| 谁能改 | CODEOWNERS：校验器目录必须由平台组 approve；保护分支禁止直推 |
| 改规则数据 | 同上，且要求 **2 人 approve** |
| 改例外名单 | 放集群内 ConfigMap，由另一仓库管理；该 ConfigMap 的改动同样受门禁 C 约束 → 闭环 |
| 校验器版本 | 打 tag，Application 指向 tag 或 commit SHA（引 [`07`](../07-repository-githubapp.md) §2.1 的 GitOps 建议） |
| 凭据 | GitHub App private key / webhook secret → Secret Manager + External Secrets，**绝不入 Git**（引 [`07`](../07-repository-githubapp.md) §3.2 的口径） |

---

## 19. 坑、边界与验收

### 19.1 常见坑

| 坑 | 表现 | 处理 |
|---|---|---|
| required check 名字和 App 创建的 check 名字不一致 | 分支保护"永远在等" | 名字逐字符核对；先建 check 再配保护 |
| PR 又 push 了一次（synchronize） | 旧 check 失效但没重跑 | 每次 `synchronize` 重跑 check 并覆盖同名 |
| check 只在第一次 PR 时创建 | 新 commit 没结论 | 用 **check run 复用/覆盖**，别用一次性 commit status |
| GitHub 重投同一个 webhook | 重复判定 / 重复回写 | 用 `X-GitHub-Delivery` 做幂等键 |
| 校验器把 push 事件当 pull_request 处理 | 误判 / 400 | 事件类型白名单；或按 §17.3 方案 ③ 透传 |
| fork 来的 PR | 拿不到 secrets、上下文不同 | 校验器只做**查询 + 回写 check**，不做写操作；fork PR 的 check 权限需单独验证 |
| 审批撤销 / 变更单被作废，但 PR 已合并 | 生产已变更 | 需要"撤销即回滚"机制（§19.3） |
| 规则写在代码里 | 改规则要发版，慢且危险 | 规则数据放 ConfigMap（§15.5） |
| 校验器自己被打穿 | 门禁形同虚设 | CODEOWNERS + 双人复核 + 集群内配置闭环（§18） |
| Gatekeeper `failurePolicy: Fail` 且 Gatekeeper 挂了 | 整个集群写入中断 | ≥2 副本 + PDB + 超时设置（本地 doc 06 §4.4） |

### 19.2 验收：五条绕过路径都要测

门禁做完不等于安全，**必须实测绕过**：

```
① 绕过 PR 直接推分支          → 分支保护 / API 令牌权限 是否挡住？
② 绕过 App，直接 kubectl apply → 门禁 C（准入）是否挡住？
③ 绕过 Extension，手动 sync   → AppProject disableManualSync + Argo CD RBAC 是否挡住？
④ 绕过变更单，改生产配置       → 门禁 A + 门禁 C 是否挡住？
⑤ 校验器自己被改坏            → CODEOWNERS/双人复核 是否生效？
```

### 19.3 "撤销即回滚"（进阶）

变更单在 merge 后被作废时，生产已经变了。三种处理：

| 方案 | 做法 | 代价 |
|---|---|---|
| **A. 只告警** | 记审计 + 通知，人工处理 | 最简单，但弱 |
| **B. Argo CD 自愈** | selfHeal 把资源拉回 Git 里"合规"的版本 | ✅ 便宜；但这是"回到 Git 声明的状态"，不是"回滚到上一个版本" |
| **C. 版本指针回退** | 生产用 tag / release 分支指针，撤销 = 指针回退（一次受控 PR） | ✅ 语义正确、可审计；需要"批准 = 推进指针"的模型 |

> 结论：**要"撤销即回滚"的语义，就必须在生产侧用"指针 + 受控 PR"模型**，
> 而不是让生产直接跟踪 `main` 分支。这会反过来影响 §14.2 的生产应用设计。

### 19.4 分阶段落地（建议顺序）

| 阶段 | 做什么 | 验收标准 | 回滚 |
|---|---|---|---|
| **M0 决策** | 变更单存哪（外部系统 / CRD）；生产分支映射；审批规则 | 规则清单（§11.4）定稿并评审 | — |
| **M1 变更单侧** | 建 CRD + RBAC（或对接外部系统）；审批子资源 | 能创建变更单、审批、改状态；提单人不能自审批 | 停用 CRD |
| **M2 App 侧** | 建 GitHub App（最小权限）+ 校验器 v0 | PR 上能拿到 check（先只报"读到 CR 号"，不判规则） | 删 App / 关 webhook |
| **M3 门禁 A** | 实现 R1–R10 判定；配 branch protection | 不合规 PR **合不了**；合规 PR 能合 | 移除 required check |
| **M4 门禁 B** | Argo CD Extension / PreSync 校验；生产关自动同步 | 不合规时 sync 失败、集群零变更 | 摘掉 extension；恢复自动同步 |
| **M5 门禁 C** | Gatekeeper 约束 + 注解规范 | kubectl 直改被 403 拒绝 | 临时 `failurePolicy: Ignore`（会留违规记录） |
| **M6 演练** | 跑 §19.2 五条绕过路径 + 紧急通道演练 | 全部按预期被拦/放行 | — |

> **顺序理由**：M2 先"只报不拦"，把链路调通再上强制（门禁 A），
> 否则一旦 App 挂了会卡住所有人的合并。

### 19.5 标注

| 标注 | 内容 |
|---|---|
| **官方保证** | GitHub App 一个只有一个 Webhook URL；required status checks 阻塞 merge；Checks API 写 check 需要 `Checks: Write` |
| **当前清单事实** | `argocd-applicationset-controller` 7000/8080 端口；`argocd-server` 8080 容器端口（`install.yaml`） |
| **本地已有方案** | Argo CD Extension 同步前校验（[`06`](../06-opa-gatekeeper-impact.md) §3.1 方式 B）；PreSync Hook（方式 A）；Gatekeeper 影响面与排障（[`06`](../06-opa-gatekeeper-impact.md) §4–§5）；Hooks 人工闸门（[`../argocd-admin-guide.md`](../../argocd-admin-guide.md) §5.5） |
| **推荐实现** | 三层门禁架构；校验器放 GKE + Ingress；规则数据放 ConfigMap；审批独立成子资源 |
| **部署前验证项** | Extensions 在当前 Argo CD 版本可用性与 payload 字段；CRD CEL validation rules 的版本支持；GKE 托管证书与 Ingress 形态；GitHub App "Public" 开关与安装范围行为 |

### 19.6 关联文档

| 主题 | 文档 |
|---|---|
| GitHub App 凭据三要素 + Repository Secret | [`07-repository-githubapp.md`](../07-repository-githubapp.md) |
| Gatekeeper / Admission / Extension 对 Argo CD 的影响 | [`06-opa-gatekeeper-impact.md`](../06-opa-gatekeeper-impact.md) |
| 人工审批为什么不引入 Argo Workflows | [`10-argo-workflows-evaluation.md`](../10-argo-workflows-evaluation.md) |
| AppProject / RBAC / sync 语义 | [`04-appproject-rbac.md`](../04-appproject-rbac.md) |
| Git → apply 逐阶段链路 | [`../poc-argocd-git-to-apply-trigger.md`](../../poc-argocd-git-to-apply-trigger.md) |
| Gatekeeper 现成资料 | [`../../gke/opa-gatekeeper/`../../../gke/opa-gatekeeper/ |
| **Webhook 之后外部交互模型的变化（pull → push）** | [`12-webhook-push-vs-pull.md`](./12-webhook-push-vs-pull.md) |
| **CR Check 的 Go 设计与实现评估** | [`13-cr-check-go-design.md`](./13-cr-check-go-design.md) |

---
---

# Part C · 评估：Argo Workflows 能不能干这件事？GitHub App + Workflows 怎么配合？

> **一句话结论**
> **Workflows 能参与，但只参与"审批编排"这一小块；它不改变 §14 的三层门禁结论。**
> - ❌ Workflows **不能**替代 GitHub App（事件接入 + check 回写 + 合并强制）
> - ❌ Workflows **不能**替代门禁 B / C（Argo CD 同步门、K8s 准入）
> - ✅ Workflows **能**承载"多级审批 / SLA / 超时升级 / 驳回重审"这类审批编排
> - ⚠️ 但**变更单这个长生命周期的业务对象 + 规则判定**，更适合 CRD / 外部系统，**不适合当 Workflow 跑**
>
> **本场景命中了 [`10-argo-workflows-evaluation.md`](../10-argo-workflows-evaluation.md) 的复评触发条件 T6**
> （"Argo CD 侧出现真正的审批工作流需求……且 Sync Window + 角色分离不够"）。
> 但 doc 10 的核心结论**不变**：Workflows 仍**不**做发布执行器。

---

## 20. 为什么这个场景值得重新看一眼 Workflows

doc 10 的 §6.2 映射表里，**12 项能力中 Workflows 只有 1 项净增量**，
且当时"我们还没触发"——现在触发的是 **T6**。

对比一下两份文档的落点：

| | doc 10（当时的语境） | 本场景（Part B） |
|---|---|---|
| 需求形态 | "受治理的发布执行器"（F1–F12） | "PR 合并前的变更单审批" |
| 审批复杂度 | 明确不作为主诉求 | **就是主诉求** |
| Workflows 增量 | 弱（DAG 顺序比 Sync Waves 强一点） | **强**（DAG + suspend + 超时 + exit handler） |
| 结论 | 不引入 | **限定范围复评**（见 §21） |

**关键区分**：

```
"发布执行器"（doc 10 否决的对象）
    = 声明式的、持续的、跨集群的 → Argo CD 天然更强 ✅ 维持不引入

"审批编排器"（本场景可能需要的）
    = 命令式的、跑一次的、等人签字的 → Workflows 确实更强 ✅ 可以考虑
```

> 这正是 doc 10 §4.2 第 4 条列的 Workflows 真正擅长的场景：
> **"人工闸门 + 定时超时：suspend 等待审批，超时自动走另一分支"**。

---

## 21. 三种方案对比

| 维度 | **方案 A**（默认）<br>CRD + Gatekeeper + Extension | **方案 B**<br>CRD（真相源）+ Workflows（只做审批编排） | **方案 C**<br>Workflows 端到端 |
|---|---|---|---|
| 新增常驻组件 | **无** | `argo-server` + `workflow-controller`（+ v4 归档 DB） | 同 B |
| 审批编排能力 | 弱（自己写状态机） | **强** | 强 |
| 规则判定放哪 | 校验器代码 / CEL / Gatekeeper | 同 A（Workflow 只调度，不判定） | Workflow 的 step 里判定 |
| 变更单存储 | CRD | CRD | Workflow 实例（**不建议**） |
| 与 doc 10 结论 | ✅ 不冲突 | ⚠️ 需限定用途复评 | ❌ 冲突（Workflows 变发布执行器） |
| 三层门禁 A/B/C | 仍需全部 | 仍需全部 | 仍需全部 |
| 引入后主要风险 | 审批流要自研（体验一般） | L1/L2 controller 不可水平扩展；L3 DB 依赖；L6 每步一 Pod；L7 双控制环 | 同 B + 事实源漂移 |
| **推荐度** | ★★★ **默认选它** | ★★ 审批复杂度达 L3 时再上 | ★ 不推荐 |

---

## 22. 能力映射：Workflows 在 R0–R12 里到底能顶哪些

| 规则 | Workflows 能不能干 | 说明 |
|---|---|---|
| R0 接收 PR 事件 | ❌（需前置接收器） | Workflows **无原生 GitHub 触发器**；需 GitHub App 后端或 **Argo Events**（doc 10 的 T5）把它 submit 进去 |
| R1 解析变更单号 | ⚠️ 可以，但别扭 | 模板参数能带，但"从 PR 元数据里挖号"是校验器的活 |
| R2–R7 规则判定 | ⚠️ 能跑，但不理想 | 这些是**查询 + 比较**：CRD 字段查询、CEL 表达式、OPA 策略都比"起 Pod 跑脚本"更自然、更快、更省资源 |
| R8 紧急通道 | ✅ 条件分支 | Workflow 的强项 |
| **R9 回写 Check Run** | ❌ 不该由它做 | 需要 GitHub API + `Checks: Write` 凭据；做了就等于重写 GitHub App 的活 |
| R10 反馈可读 | ⚠️ | 写 PR 评论仍是校验器的事 |
| R11 审计留痕 | ⚠️ Workflow 有**另一套**历史 | 两套历史 = 归因成本上升（doc 10 L7/F10 提到"增加归因成本"） |
| R12 部署侧可追溯 | ❌ | 仍靠 commit trailer / Extension / Gatekeeper |
| **审批编排**（多级、会签、SLA、超时升级、驳回重审） | ✅✅ **净增量** | 这才是引入它的理由 |

**一句话**：**Workflows 顶的是"审批怎么流转"，不是"合不合规"。**
"合不合规"是规则引擎（CEL / OPA / 代码）的活，"能不能 merge"是 branch protection 的活。

---

## 23. 如果选方案 B：GitHub App + Workflows 怎么接线

```
┌──────────────┐  pull_request 事件
│  GitHub App  │  （事件入口 + check 报告者，角色不可替代）
└──────┬───────┘
       │ ① 收事件 → 跑 R1–R7 判定 → 写 check（红/绿）
       │    └─ 变更单不存在 / 不合规 → check 红 → merge 被 branch protection 拦住
       │
       │ ② 变更单存在且合规 → 触发审批编排
       ▼
┌──────────────────────────────────────────────┐
│ Argo Workflows（仅审批编排）                  │
│   Workflow 实例名 = 变更单号（如 cr-1234）    │
│   step1  读取变更单 / 确认待审批               │
│   step2  suspend  ←── 人工审批（通知 + resume）│
│   step3  写回 CR status=Approved              │
│   step4  写 check 绿 → 允许 merge              │
│   exit handler：超时/驳回 → 写回 Rejected/Expired │
└──────────────────────────────────────────────┘
       │
       │ ③ merge 后 → 门禁 B（Argo CD Extension）+ 门禁 C（Gatekeeper）
       ▼
   生产部署
```

### 23.1 关键工程点（每条都是真实坑）

| # | 问题 | 处理 |
|---|---|---|
| 1 | **CR 号 ↔ Workflow 名** | 用 Workflow 实例名承载编号（`metadata.name: cr-1234`），编号天然对齐；但**同名不能重复创建** → 重放时先查存在性（幂等键：PR 的 head SHA + 变更单号） |
| 2 | **谁能 resume = 谁能审批** | suspend 的 resume 权限要用 Workflows 的 RBAC 按审批组配置；resume 需带 service account token。别把 resume 权给开发组 |
| 3 | **suspend 挂几天** | 可行，但要配 workflow TTL / GC，**别让待审批的 Workflow 被清掉**；v4 归档 DB 是新增有状态依赖（doc 10 L3 / V6） |
| 4 | **双控制环（L7/L11）** | Workflow 定义若由 Argo CD 持续 reconcile，会永不 OutOfSync/反复覆盖 → **只能用 hook 或由 Argo Events 提交**，不能当常驻期望状态 |
| 5 | **每个 step 一个 Pod（L6）** | 审批编排 3 步 = 3 个 Pod，且 suspend 时 Pod 还在。成本要算：审批并发量 × 步数 × Pod 规格 |
| 6 | **controller 不可水平扩展（L1/L2）** | 审批并发不大时无所谓；但一旦审批量上来，只能加 worker / CPU |
| 7 | **GitHub check 由谁写** | 仍是 **GitHub App**（或校验器）写 check。**Workflows 不要碰 check**——否则要自己处理 App 私钥 → installation token 的签发 |
| 8 | **两套审计** | 审批留痕写在 **CR**（真相源），Workflow 只作为执行痕迹；不要把 Workflow 的历史当审批记录 |
| 9 | **Workflows 挂了怎么办** | 审批流停摆 → 需要降级路径（人工直接改 CR status，或退回方案 A） |

### 23.2 什么时候该用 Argo Events 而不是 Workflows

如果需求只是"**Git push → 触发一个动作**"（doc 10 的 T5），
那 Argo Events 比 Workflows 更贴切、更轻。**本场景不是纯事件驱动**
（要等人审批），所以才落到 Workflows 或方案 A。

> 📌 **想搞清楚 Argo Events 到底是什么、它的四个核心对象、怎么跟 GitHub 事件接起来**，
> 以及"为什么我们的 CR Check 其实不需要它" → 看专题文档
> **[`../argo-event.md`](../argo-event.md)**。

> ⚠️ **但要小心 doc 10 的 T5 的措辞**：T5 说的是"**Argo 家族内部**需要事件驱动"
> （Argo CD 侧要被 Git push 触发一串动作），
> **不是"我们要写一个接收 GitHub 事件的服务"**。
> 我们要写的是**业务逻辑服务**（查 CR 平台 + 跑规则 + 写 check），
> 用普通 Go 服务实现最直接；Argo Events 只做"事件路由"，
> 替代不了业务逻辑 → **纯增加复杂度，不减少工作量**。

---

## 24. 决策建议（按审批复杂度分级）

| 审批形态 | 例子 | 建议 |
|---|---|---|
| **L1 单级审批** | 1–2 人点"同意"，状态置 Approved | **方案 A**。CRD 一个 `status` 字段 + 通知（企微/Slack）就够 |
| **L2 多级串行** | 开发组长 → 安全 → 平台，按顺序审 | **方案 A**（CRD 里用 `approvals[]` + 一个简单状态机）。仍不需要 Workflows |
| **L3 会签 + SLA + 驳回重审** | 3 人任一同意、SLA 2 小时超时自动升级、驳回后需重新发起 | **复评方案 B**（Workflows 只做编排） |

### 24.1 复评触发条件（写进决策记录）

出现下列**任意一条**，把 Workflows 摆回桌面（仅限"审批编排"用途）：

```
☐ 审批链需要 ≥3 级串行，且各级审批人不同
☐ 需要并行会签（多人同时审，票数达标才过）
☐ 需要 SLA 超时自动升级 / 自动提醒 / 自动降级
☐ 驳回后需要重新发起并保留多次尝试记录
☐ 一次变更需要并行处理多个目标（多仓库 / 多集群）
☐ 审批过程中需要自动跑校验（迁移、冒烟）再决定放不放行
```

### 24.2 复评时必须同时更新 doc 10

- doc 10 §8 的 **T6 行**标注"已命中"并链接本文 §20–§24
- doc 10 §0 的 TL;DR 结论**保持不变**（Workflows 不做发布执行器），
  但要补一句："**经限定复评，允许仅用于变更单审批编排**"

---

## 25. 回答你的两个问题

### Q1："这件事是不是也可以由 Argo Workflows 来干？"

**部分可以，但不是你以为的那部分。**

- ✅ **审批的流转**（谁审、顺序、SLA、超时、驳回重审）→ Workflows 是当前栈里最好的工具
- ❌ **判断合不合规** → 规则引擎（CEL / OPA / 代码）更合适
- ❌ **阻止 merge** → 只有 GitHub branch protection 能，Workflows 做不到
- ❌ **阻止部署 / 兜底集群写入** → Argo CD Extension + K8s 准入
- ❌ **变更单的长期状态** → CRD 或外部系统，不要拿 Workflow 实例当数据库

**判断**：Workflows 是"审批流水线"，不是"门禁本身"。门禁 = GitHub 强制力 + 集群准入，
这两块它一块都替不了。

### Q2："Workflows 要和 GitHub App 结合吗？"

**要，而且两者角色完全不重叠，组合起来是自然的：**

| | GitHub App | Argo Workflows |
|---|---|---|
| 角色 | **哨兵 + 报数员** | **调度员** |
| 收事件 | ✅ `pull_request` | ❌（要靠前置接收器） |
| 判规则 | ✅ | ⚠️ 不该归它 |
| 回写 Check / 卡 merge | ✅ | ❌ |
| 审批编排 | ❌ | ✅ |
| 长期状态 | ❌ | ❌ → **归 CRD** |

**三方分工**：`GitHub App（接入+判定+报数） → Workflows（可选，审批编排） → CRD（变更单真相源）`
门禁强制力仍在 **branch protection + Gatekeeper**。

### 25.1 我的建议

```
现在  → 方案 A（CRD + GitHub App + Extension + Gatekeeper），不引入 Workflows
       先把 M0–M5 跑通（§19.4），规则简单时根本用不上 Workflows

将来  → 若审批形态升级到 L3（§24.1 的勾选项命中 2 条以上），
        再引入 Workflows，且严格限定用途为"审批编排"，
        同时更新 doc 10 的 T6 与 TL;DR
```

**成本参照**：引入 Workflows = `argo-server`（2~3 副本）+ `workflow-controller`（**不可水平扩展**）
+ v4 归档 DB + 第二套 RBAC/UI（doc 10 E3/L1–L8）。
为"审批流转"付这个代价，**只有当审批复杂度到 L3 才划算**。

