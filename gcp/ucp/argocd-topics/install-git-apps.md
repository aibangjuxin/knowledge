# install-git-apps · 在 Org / 仓库上安装 GitHub App 的操作指引

> **副标题**：装 App 到底点哪里？Org 级和仓库级有什么区别？能不能按分支装？
>
> **一句话结论**
> **GitHub App 的安装永远发生在「账号（Account）」这一层，不是仓库层、也不是分支层。**
> 你在安装页上做的唯一选择是：**装到哪个账号（个人 / 某个 Org）** + **给这个账号开哪些仓库**。
> 分支（Branch）**不是安装维度**，它是 Ruleset 的过滤条件或后端的判断条件。


 Document created: /Users/lex/git/gcp/ucp/argocd-topics/install-git-apps.md

 直接回答你的三个问题

 1. 装在哪里？
 安装入口永远在 App 自己的页面，不在 Org Settings 里：

 ┌──────────────────┬───────────────────────────────────────────────────────────────────────────────────────────────────────┐
 │ 场景             │ 路径                                                                                                  │
 ├──────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ 装自己开发的 App │ 头像 → Your organizations → 组织名旁 Settings → Developer settings → GitHub Apps → Edit → Install App │
 ├──────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────┤
 │ 装第三方 App     │ github.com/apps/<slug> → Install 按钮（或直接 github.com/apps/<slug>/installations/new）              │
 └──────────────────┴───────────────────────────────────────────────────────────────────────────────────────────────────────┘

 2. Org Settings 下面装 vs 仓库里装？
 这是个常见误解——Org Settings → Third-party Access → GitHub Apps 那一页是"管理已安装的 App"，不是安装入口。仓库的 Settings → Integrations → GitHub Apps 同理，而且官方明确警告：从仓库侧进去的改动会影响该账号下所有仓库。

 真正决定"Org 级还是仓库级"的，是安装页上那个 Repository access: All repositories / Only select repositories 开关。

 3. Branch 能装吗？
 不能。GitHub 没有"给某个分支装 App"的入口。 分支不是安装维度——它属于 Ruleset 的 ref_name 过滤（GitHub 侧判定要不要卡）或 后端判断 payload.pull_request.base.ref（业务侧判定通过/失败）。

 文档里最关键的一条差异

 ┌───────────────────────────────────────┬──────────────────────┬──────────────────────────┐
 │                                       │ installation_id 数量 │ Argo CD 要建几个 Secret  │
 ├───────────────────────────────────────┼──────────────────────┼──────────────────────────┤
 │ Org 级（All 或 Only select N 个仓库） │ 1 个                 │ 1 个（url 里写多个仓库） │
 ├───────────────────────────────────────┼──────────────────────┼──────────────────────────┤
 │ 跨 N 个 Org/账号各装一次              │ N 个                 │ N 个                     │
 └───────────────────────────────────────┴──────────────────────┴──────────────────────────┘

 常见误区是"每个仓库装一次 = 每个仓库一个 installation_id"，其实只要装在同一个 Org 上就只有 1 个——后续请求是扩展已有 Installation。而改仓库范围（Configure → Repository access → Save）不会改变 installation_id；只有换账号重装才会。

 
---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-tldr) | TL;DR：先记住这 7 条 |
| [§1](#1-先摆正概念app--installation--仓库--分支) | 先摆正概念：App / Installation / 仓库 / 分支 |
| [§2](#2-三种装法对照表) | **三种装法对照表**（Org 全量 / Org 选仓库 / 单仓库） |
| [§3](#3--到底在哪里点五条-ui-路径) | ★ **到底在哪里点：五条 UI 路径** |
| [§4](#4-org-级-vs-仓库级到底差在哪) | **Org 级 vs 仓库级：到底差在哪** |
| [§5](#5--关于branch为什么不能按分支装该怎么做) | ★ **关于「Branch」：不能按分支装，该怎么做** |
| [§6](#6-对-argo-cd-的直接影响) | **对 Argo CD 的直接影响**（`githubAppInstallationID`） |
| [§7](#7-安装后的验证) | **安装后的验证**（UI + `gh api` + 后端） |
| [§8](#8-改范围--暂停--卸载) | **改范围 / 暂停 / 卸载** |
| [§9](#9-常见报错对照表) | 常见报错对照表 |
| [§10](#10-一页速查清单) | 一页速查清单 |
| [§11](#11-官方文档) | 官方文档 |

---

## 0. TL;DR

1. **安装 = 在「账号」上装一次**，账号 = 你的个人账号，或某个 **Organization**。
   App 的安装**不存在仓库级**这个选项——仓库只决定"这个账号下开哪些仓库"。
2. **分支不是安装维度。** GitHub 没有任何"给某个分支装 App"的入口。
   要按分支生效，用 **Ruleset 的 `ref_name` 过滤** 或 **后端自己判 `payload.ref`**。
3. **"在 Org 的 Settings 下面去装"是个误解。** Org Settings → Third-party Access → GitHub Apps
   那一页是**管理已安装的 App**（Configure / 改仓库范围 / Suspend / Uninstall），**不是安装入口**。
   安装入口在 **App 自己的页面**。
4. **仓库级入口也是同一个安装页**，只是"账号"选 Org、"仓库"选 `Only select repositories` 且只勾一个。
   它和 Org 全量装的区别不在"点哪里"，而在 **你勾了哪些仓库**。
5. **一个账号 = 一个 Installation = 一个 `installation_id`。**
   所以 Org 级全量装 → **1 个 installation_id 覆盖 N 个仓库**；
   每个仓库单独装 → **N 个 installation_id**。这直接决定 Argo CD 要配几个 Repository Secret。
6. **谁能装**：Org owner 随时能装；repo admin 只有在 **App 不申请组织权限、也不申请 "Repository administration" 权限**时才能自己装，
   且只能装到自己管理的仓库；普通成员点了会变成 **Request**，需要 owner 审批。
7. **"Install" vs "Install and request" vs "Request"** 三个按钮的区别 = 组织 owner 需要审批「全部 / 部分 / 全部」权限。

---

## 1. 先摆正概念：App / Installation / 仓库 / 分支

安装之前必须把这四层分清，否则点按钮的时候一定会懵。

```
┌─────────────────────────────────────────────────────────────────┐
│ ① GitHub App（应用本体 / 身份）                                   │
│    归属：一个个人账号 或 一个 Organization                         │
│    页面：github.com/apps/<slug>                                 │
│    决定：App ID、私钥、Webhook URL、申请的权限、订阅的事件          │
│    ★ 可见性：Public（谁都能装） / Private（只有归属账号能装）        │
└───────────────────────────┬─────────────────────────────────────┘
                            │  安装（Installation）
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ ② Installation（安装实例 / 授权边界）★真正的"装"★                 │
│    装在：一个账号（个人 或 Org）上                                │
│    一个账号 = 一个 installation_id                               │
│    ★ 决定：这个 App 在这个账号下能碰哪些仓库、能干什么              │
└───────────────────────────┬─────────────────────────────────────┘
                            │  授权范围
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ ③ 仓库范围（Repository access）                                  │
│    All repositories  |  Only select repositories（勾选清单）      │
│    ★ 只有仓库级，没有分支级                                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ ④ 分支（Branch）—— ★不属于安装体系★                              │
│    它是：Ruleset 的过滤条件 / 后端逻辑的判断输入 /                 │
│          Argo CD 的 spec.source.targetRevision                    │
└─────────────────────────────────────────────────────────────────┘
```

**必须区分的两组概念**（GitHub 官方文档专门有一节讲这个）：

| | install（安装） | authorize（授权） |
|---|---|---|
| 干什么 | 给 App 访问**组织与仓库资源**的权限，并指定**哪些仓库** | 给 App 访问**你的账号**的权限，代表你行事 |
| 粒度 | 账号 + 仓库 | 用户 |
| 谁能做 | Org owner / repo admin / 个人账号本人 | 你自己 |
| 缺了会怎样 | App 拿不到 installation token，读不到仓库 | App 不能代表你行事 |
| 典型场景 | Argo CD 拉代码、CR Check 跑 check run | App 要调你的邮箱 / 你的 gist |

> **可以只安装不授权，也可以只授权不安装。**
> 我们的 Argo CD / CR Check 场景**只需要 install**，不需要 authorize。

**一个官方细节**（安装页会写，但容易被忽略）：

- App **始终**至少对 GitHub 上**所有公开仓库**有只读权限（哪怕你只勾了一个私有仓库）。
- 如果 App 后续**自己创建了仓库**，那些仓库会自动被授权给该 App。

---

## 2. 三种装法对照表

| | **A. Org 级 · All repositories** | **B. Org 级 · Only select repositories** | **C. 单仓库级** |
|---|---|---|---|
| 安装页操作 | 账号=Org，仓库=**All** | 账号=Org，仓库=**Only select** + 勾 N 个 | 账号=Org，仓库=**Only select** + 勾 1 个 |
| **installation_id 数量** | **1** | **1** | **1**（只要装在同一个 Org 上就还是 1 个） |
| 覆盖仓库数 | Org 下**全部**（含未来新建的） | 勾选的 N 个 | 1 个 |
| 新建仓库是否自动纳入 | ✅ 自动 | ✅ App 自建的自动；**别人手动建的不自动** | ❌ |
| 谁执行安装 | Org owner | Org owner（也可 repo admin 扩展，见 §3.5） | Org owner **或** repo admin（有条件）|
| installation_id 取值 | 一个，所有仓库共用 | **一个**，所有勾选仓库共用（不是每仓库一个！） | 一个（该 Org 若已有安装，则是**扩展**它而不是新建）|
| 典型场景 | 全 Org 统一治理（如 commit message 规范、CR 门禁） | 生产仓库白名单（推荐默认） | 单仓库试点 / PoC |
| Argo CD 需要几个 Repository Secret | **1 个**（配多个 `url`） | **1 个**（配多个 `url`） | **1 个**（同 Org 内）；跨 N 个账号则 N 个 |

> ⚠️ **最容易搞错的一点**：
> **B 和 C 的 installation_id 数量是一样的**——只要装在**同一个账号（Org）**上，就只有 **1 个** installation。
> B 勾了 3 个仓库、C 勾了 1 个仓库，installation 数量一样，只是授权面不同。
>
> **真正会让 installation_id 变多的，是「装在不同的账号上」**：
> 你在 3 个不同的 Org（或 1 个 Org + 你的个人账号）各装一次 → **3 个 installation_id** → Argo CD 要建 3 个 Repository Secret。
>
> 另外：即使每个仓库单独发起安装请求，**也未必**产生独立的 Installation 对象——
> 只要该 Org 上已经存在同一 App 的安装，后续请求就是**扩展已有 Installation**（官方明确说明），
> installation_id 不变。

---

## 3. ★ 到底在哪里点：五条 UI 路径

> 全部按 GitHub 当前 UI（英文标签）写。中文界面名称可能略有差异，以括号里的英文为准。

### 3.1 路径 ①：安装**我们自己开发**的 App（CR Check 这类）

这是本仓库的主场景。

```
右上角头像
  └─ Your organizations
       └─ 组织名右侧的 Settings
            └─ 左侧栏 Developer settings
                 └─ GitHub Apps
                      └─ 找到目标 App，点右侧 Edit
                           └─ 页面内点 Install App
                                ├─ 选安装位置（你的个人账号 / 某个 Org）
                                ├─ 仓库范围：All repositories | Only select repositories
                                │    └─ 选 Only select 时，在 Select repositories 下拉里勾仓库
                                ├─ 检查权限清单
                                └─ Install
```

> **同一个 App 可以装多次**（个人账号一次、Org 一次、甚至多个 Org 各一次），
> 每一次都会产生**独立的 installation_id**。

### 3.2 路径 ②：安装**第三方**的 App

```
访问 App 主页：github.com/apps/<slug>
  └─ 点 Install 按钮
       （或直接访问 https://github.com/apps/<slug>/installations/new）
            ├─ Select location：选你的个人账号 / 你所属的 Org
            ├─ 仓库范围：All repositories | Only select repositories
            ├─ Select repositories（下拉里勾选）
            ├─ 复核权限清单
            └─ 点 Install / Install and request / Request
```

**三个按钮的含义**（由"组织 owner 需要审批多少"决定）：

| 按钮 | 什么时候出现 | 结果 |
|---|---|---|
| `Install` | owner 无需审批（权限都是仓库级的） | 立刻生效 |
| `Install and request` | 部分权限需要 owner 审批 | 仓库权限先给，需要审批的部分挂起 |
| `Request` | 全部权限需要 owner 审批 | 变成一条**安装请求**，等 owner 批 |

> **普通成员没有 org 安装权限时**：在安装页选 Org，GitHub 会把 `Install` 变成 `Request`，
> 并**通知组织 owner**。owner 批完即完成安装。
> 组织可以配置策略**禁止成员发起安装请求**（见 §11 的 org policy 文档）。

### 3.3 路径 ③：管理**已安装**的 App（Org 侧）

> ⚠️ **这一页不是安装入口**，是最容易误解的地方。

```
右上角头像
  └─ Your organizations
       └─ 组织名右侧的 Settings
            └─ 左侧栏 Third-party Access
                 └─ GitHub Apps        ← 已安装的 App 列表
                      └─ 目标 App 右侧 Configure
                           ├─ Permissions      → 复核权限
                           ├─ Repository access → All | Only select + Select repositories
                           └─ Save
```

### 3.4 路径 ④：从**仓库**侧进入（很多人以为能"在仓库里装"）

```
仓库主页
  └─ Settings
       └─ Integrations
            └─ GitHub Apps            ← 有权限访问本仓库的 App 列表
                 └─ 目标 App 右侧 Configure
```

> ⚠️ **官方明确警告**：从这里进入后你会被带到**该 App 所在账号的设置页**，
> **你在这里做的改动会影响该账号下的所有仓库**，不只是你刚点的这个仓库。
>
> 想只给当前仓库开权限，要在 `Repository access` 里用 **`Only select repositories`** 精确勾选，
> 而**不是**在这里改。

### 3.5 路径 ⑤：repo admin 自己装 / 扩展

**前置条件（两者都要满足）**：

1. App **没有申请任何 organization permissions**，也**没有申请 `Administration: Repository administration`** 权限；
2. repo admin 只在自己有 admin 权限的仓库范围内操作。

**满足时**：repo admin 可以在安装页选 Org + `Only select repositories` + 勾自己的仓库，直接完成安装。

**Org owner 已经装过 App 时**：repo admin 可以**扩展已有 Installation**，
把自己管理的仓库加进去——**这一步不需要重新审批**，因为 owner 装的时候已经批准过权限了。

**组织可以禁止 repo admin 自行安装**：Owner 设置里可以开启限制，
开启后 repo admin 只能发 **Request**，必须由 owner 代装。

> **"app manager" 角色 ≠ 能装 App。**
> 被指派为 app manager 的人**不能**代表组织安装 GitHub App。

---

## 4. Org 级 vs 仓库级：到底差在哪

| 维度 | Org 级安装 | 仓库级安装 |
|---|---|---|
| **授权边界的载体** | 一个 `installation_id` 覆盖 Org 下的一批仓库 | 同样是 Installation，只是仓库范围更小 |
| **对 Argo CD** | 1 个 installation_id → 1 个 Repository Secret，可写多个 `repoURL` | 若在 N 个账号/仓库分别安装 → N 个 installation_id → N 个 Repository Secret |
| **新建仓库** | `All repositories` 时自动纳入；`Only select` 时不自动（App 自建的除外） | 不会自动纳入 |
| **权限被 App 升级** | 需要 owner 重新批准（App 会发通知） | 同样需要重新批准 |
| **谁能改范围** | Org owner 随便改；repo admin 只能加自己的仓库 | 同左 |
| **审计视角** | 一次授权覆盖全 Org，**影响面大但好管理** | 授权面小，但**安装数会随仓库数线性增长**，容易漏配 |
| **适合** | 统一门禁（commit message 规范、CR 审批）、需要跨仓库统一策略 | 单仓库试点、只对特定仓库开权限 |

### 4.1 选型建议（本项目场景）

```
问自己三个问题：
  1) 这个 App 要覆盖的仓库，是不是都在同一个 Org 里？
       → 是 → 优先 Org 级安装（哪怕用 Only select 勾选）
       → 否 → 每个 Org 装一次（installation_id 会变多）
  2) 未来会不会新增仓库需要同样策略？
       → 会 → 用 All repositories，省掉"新仓库没被覆盖"的坑
       → 不会 → Only select repositories 更安全
  3) 这个 App 的权限是否敏感（能写代码 / 能写 checks）？
       → 是 → 只勾必要仓库（Only select），别图省事全开
```

**本仓库的推荐默认**：**Org 级 + Only select repositories（生产仓库白名单）**。
理由：
- installation_id 只有 1 个 → Argo CD 侧配置最简单；
- 新建仓库默认不被授权 → 符合最小权限；
- 生产仓库清单变更时，在 Configure 里增删勾选即可，**不需要重新安装、不会换 installation_id**。

> ⚠️ **注意**：在 Configure 里改仓库范围**不会**改变 installation_id。
> 只有**换账号安装**或**卸载重装**才会拿到新的 installation_id。

---

## 5. ★ 关于「Branch」：为什么不能按分支装，该怎么做

### 5.1 结论

**GitHub 不提供任何"按分支安装 App"的能力。** 安装体系的最小粒度是**仓库**。
你看到的分支相关配置，全都在别的地方：

| 你想达到的效果 | 正确的实现位置 | 参考 |
|---|---|---|
| 只在 `main` 上要求 CR 单号 | **Ruleset** 的 `ref_name` 过滤 | [`git-apps/14`](./git-apps/14-rulesets-and-gitapp-gate.md)、[`git-apps/16`](./git-apps/16-ruleset-install-runbook.md) |
| 只在特定分支上跑 App 的逻辑 | **后端代码**判断 `payload.ref` / `pull_request.base.ref` | [`git-apps/13`](./git-apps/13-cr-check-go-design.md) |
| Argo CD 只部署某条分支 | **Application** 的 `spec.source.targetRevision` | [`07-repository-githubapp.md`](./07-repository-githubapp.md) |
| 只允许某些分支能被推到 | **Branch protection / Ruleset** | — |
| 只让 App 能看到某些分支的事件 | ❌ **GitHub App 没有 webhook 分支过滤** | — |

### 5.2 为什么 App 没有"分支级安装"

1. **权限模型决定的**：App 的权限是**仓库 + 权限类型**（`contents:read`、`checks:write`…），
   GitHub 的权限体系里**没有**"分支"这一维。加进来会让 OAuth scope 模型爆炸。
2. **Installation 是账号级对象**：一个账号一个 installation_id，
   如果再按分支拆，installation_id 会爆炸，token 管理无从谈起。
3. **Checks 是 commit 级的**：CR Check 产生的 check run 挂在 **commit SHA** 上，
   与分支无关。分支语义由 **Ruleset 的 `ref_name`** 在"要不要卡它"这一步处理。

### 5.3 想按分支生效的标准做法（两层）

```
第 1 层｜GitHub 侧（判定"这个 PR 要不要被卡"）
  └─ Ruleset，conditions.ref_name 匹配目标分支
     → 只有匹配到的分支才要求 check 必须成功
     → App 本身对所有 PR 都出 check run（无害）

第 2 层｜后端侧（判定"这个 check 应该是通过还是失败"）
  └─ 读 payload.pull_request.base.ref
     → 非目标分支 → check 报 success（带说明）
     → 目标分支   → 跑 CR 校验，通过/失败
```

> 这样拆的好处：**安装只做一次、覆盖全 Org**（§4 推荐的 Org 级），
> 分支策略完全由 Ruleset + 后端逻辑控制，改分支不用重装 App、不换 installation_id。

---

## 6. 对 Argo CD 的直接影响

> 背景见 [`07-repository-githubapp.md`](./07-repository-githubapp.md)（GitHub App 凭据配在哪、怎么改分支）。

### 6.1 三个字段的分工

| 字段 | 来源 | 值会不会变 |
|---|---|---|
| `githubAppID` | App 本身 | **永不变** |
| `githubAppPrivateKey` | App 的私钥（.pem） | 除非你重新生成私钥 |
| `githubAppInstallationID` | **Installation**（= 装在哪个账号 + 开了哪些仓库） | **换账号重装 / 卸载重装才会变**；改仓库范围不变 |

Argo CD 的 Repository Secret 结构：

```yaml
# argocd 命名空间的 Secret
stringData:
  url: https://github.com/<org>/<repo>.git     # 可以一个 Secret 写多个 url
  type: git
  project: <appproject>
  githubAppID: "<app-id>"
  githubAppInstallationID: "<installation-id>"   # ★ org 级安装时，所有仓库共用这一个
  githubAppPrivateKey: |
    -----BEGIN RSA PRIVATE KEY-----
    ...
    -----END RSA PRIVATE KEY-----
```

### 6.2 安装范围 → Secret 数量的映射

| 安装方式 | installation_id | Repository Secret | 每个 Secret 的 `url` |
|---|---|---|---|
| Org 级（All 或 Only select N 个） | **1 个** | **1 个** | 可写 N 个仓库的 url（每行一个） |
| 单仓库级 × N（分散在 N 个账号） | **N 个** | **N 个** | 每个 1 个 url |
| 同一 Org 里对每个仓库各装一次 | **通常仍是 1 个**（Owner 装过一次后，repo admin 只是在扩展） | 1 个 | 可写多个 url |

> ★ **最容易踩的坑**：
> 有人以为"每个仓库装一次 = 每个仓库一个 installation_id"，
> 然后在 Argo CD 里建了 8 个 Secret，其实 **1 个就够**。
> 反过来，如果你们跨了 3 个 Org/账号，那确实是 3 个 installation_id，要建 3 个 Secret。

### 6.3 装完 App 之后，Argo CD 侧要做的 3 件事

1. 拿到 `installation_id`（见 §7.1）；
2. 在 Argo CD 里建 Repository Secret，填 `url` / `githubAppID` / `githubAppInstallationID` / `githubAppPrivateKey`；
3. 在 Application 里指定 `spec.source.repoURL` 与 `spec.source.targetRevision`（**分支在这里**）。

---

## 7. 安装后的验证

### 7.1 UI 验证 + 抄下 installation_id

```
Org Settings → Third-party Access → GitHub Apps → 目标 App → Configure
  ├─ Permissions      → 确认授予的权限和你申请的一致
  ├─ Repository access → 确认仓库清单正确
  └─ 页面里能看到 Installation ID
```

> 💡 **Installation ID 就在 Configure 页面**（页面上会显示 `Installation ID`）。
> 这是最直接的取数方式，不用装任何工具。

### 7.2 CLI 验证（`gh`）

```bash
# ① 列出你自己的 App 在各账号下的安装情况
gh api /app/installations \
  --jq '.[] | {id, account: .account.login, repo_selection, repo_count: (.repository_selection == "all")}'

# ② 列出某个 Org 下的所有 App 安装（需要 admin:org scope）
gh api /orgs/<ORG>/installations \
  --jq '.[] | {id, app: .app_slug, repo_selection}'

# ③ 查某个安装实例覆盖了哪些仓库
gh api /orgs/<ORG>/installations/<INSTALLATION_ID>/repositories \
  --jq '.repositories[].full_name'

# ④ 验证能不能换到 installation token（最硬的验证）
gh api --method POST /app/installations/<INSTALLATION_ID>/access_tokens \
  --jq '{token: .token, expires_at, repos: (.repositories|length)}'

# ⑤ 列出安装请求（有人发了 Request 但还没批）
gh api /app/installation_requests --jq '.[] | {id, account: .account.login, requester: .requester.login}'
```

> ④ 能拿到 token 就说明 **App ID + 私钥 + installation ID 三者配对正确**、且该安装有权访问目标仓库。
> 这是 Argo CD 能不能拉代码的**前置条件**。

### 7.3 后端验证（收到事件）

安装完成后，端点应该开始收到 webhook：

```bash
# 本地起一个监听器，把收到的 delivery 头打出来
# （或直接看 CR Check 后端 / GKE 里的日志）
```

**验证清单**：

- [ ] App 出现在 Org Settings → Third-party Access → GitHub Apps
- [ ] Repository access 里的仓库清单 = 预期
- [ ] `gh api /app/installations/<id>/access_tokens` 能换到 token
- [ ] 提一个 PR，后端日志里能看到 `X-GitHub-Event: pull_request` 且 **仓库名正确**
- [ ] 后端用 `installation_id` 换到的 token 访问该仓库返回 200（而不是 404/403）

---

## 8. 改范围 / 暂停 / 卸载

| 操作 | 入口 | 效果 | installation_id |
|---|---|---|---|
| **改仓库范围** | Configure → Repository access → All / Only select → Save | 增减仓库 | **不变** ✅ |
| **暂停（Suspend）** | Configure → Suspend | App 暂时无法访问该账号资源。**用户的授权不受影响** | 不变 |
| **恢复（Unsuspend）** | Configure → Unsuspend | 必须由**当初 suspend 的人**来恢复 | 不变 |
| **卸载（Uninstall）** | Configure → Uninstall | App 失去该账号的资源访问权；**其他账号的安装不受影响** | 该账号的 installation 消失 |
| **彻底停用（个人账号）** | Settings → Integrations → Applications → Authorized GitHub Apps → Revoke | 作废所有以你身份签发的 token | — |
| **改 App 申请的权限** | App 侧（Edit）→ 会触发 Org owner 审批 | 审批前旧权限继续生效 | 不变 |

> ⚠️ **Suspend 的对称性**：owner suspend 的，owner 能 unsuspend；账号侧 suspend 的，账号侧能 unsuspend。
> **不能交叉解除**。这也是"凭证泄露时立刻 Suspend"要先想清楚谁来恢复的原因。
>
> ⚠️ **Uninstall 后重装 → installation_id 会变** → Argo CD 的 Repository Secret **必须同步更新**，
> 否则会直接 401/404。这是"卸载重装"最常见的连带事故。

---

## 9. 常见报错对照表

| 现象 | 原因 | 处理 |
|---|---|---|
| 安装页没有 Org 可选 | 你不是该 Org 成员，或 App 是 Private 且不归你所有 | 确认成员身份；Private App 只能装在归属账号 |
| 按钮是 `Request` 而不是 `Install` | 组织策略要求 owner 审批 | 找 owner；或 owner 在设置里放开策略 |
| 点了 Install 但"没有反应" | 走的是 Request 流程，**请求已发出但没人批** | 查 `gh api /app/installation_requests`；owner 在 Settings → GitHub Apps → Requests 里批 |
| repo admin 装不了 | App 申请了 organization 权限或 `Administration: repository` 权限 | 找 owner 装；或换权限更小的 App |
| `Configure` 里改了仓库范围，但 App 仍报 404 | token 缓存未过期（installation token 有效期 1 小时） | 等待 token 刷新，或重启后端清缓存 |
| 后端 404（不是 403） | installation_id 指向的安装已卸载/换账号重装了 | 重新抄 installation_id，更新 Argo CD Secret |
| 后端 403 | 仓库没在 `Repository access` 清单里，或权限类型不够 | Configure 里加仓库；核对 Permissions |
| Argo CD 拉私有仓库 401 | App ID 与私钥不配对 | 确认 `.pem` 是这个 App 的私钥 |
| 找不到"按分支安装"的选项 | **不存在这个功能** | 见 §5，改用 Ruleset `ref_name` + 后端过滤 |
| Ruleset 里选不到 CR Check 当 expected source | App 从没在这个仓库跑出过一次 check run | 见 [`git-apps/16`](./git-apps/16-ruleset-install-runbook.md) §2（六步安装顺序） |

---

## 10. 一页速查清单

```
□ 确认 App 可见性（Public / Private）是否符合预期
□ 确认 App 申请的权限是最小集
□ 确认 App 的 Webhook URL 可公网访问
□ 决定安装位置：Org（推荐）而不是个人账号
□ 决定仓库范围：Only select repositories（白名单）而不是 All
□ 执行安装（App 页面 → Install → 选 Org → 勾仓库 → Install）
□ 回 Org Settings → Third-party Access → GitHub Apps → Configure
    → 抄下 Installation ID
    → 核对 Repository access 清单
□ 验证换 token：
    gh api --method POST /app/installations/<ID>/access_tokens
□ Argo CD：建 Repository Secret
    url / githubAppID / githubAppInstallationID / githubAppPrivateKey
□ Argo CD：Application.spec.source.repoURL + targetRevision（分支在这里）
□ 分支策略：Ruleset ref_name + 后端 base.ref 判断（不要指望安装能按分支）
□ 联调：提一个 PR，确认后端收到事件 + check run 正常
```

---

## 11. 官方文档

| 主题 | 链接 |
|---|---|
| 安装自己开发的 App（UI 逐步） | https://docs.github.com/en/apps/using-github-apps/installing-your-own-github-app |
| 安装第三方 App（含 Request 流程） | https://docs.github.com/en/apps/using-github-apps/installing-a-github-app-from-a-third-party |
| 管理/修改已安装的 App | https://docs.github.com/en/apps/using-github-apps/reviewing-and-modifying-installed-github-apps |
| GitHub App 基础概念 | https://docs.github.com/en/apps/using-github-apps/about-using-github-apps |
| App 可见性（Public / Private） | https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/making-a-github-app-public-or-private |
| 权限升级的重新审批 | https://docs.github.com/en/apps/using-github-apps/approving-updated-permissions-for-a-github-app |
| 暂停安装 | https://docs.github.com/en/apps/maintaining-github-apps/suspending-a-github-app-installation |
| App manager 角色 | https://docs.github.com/en/apps/maintaining-github-apps/about-github-app-managers |
| REST API · Apps | https://docs.github.com/en/rest/apps/apps |
| REST API · Installations | https://docs.github.com/en/rest/apps/installations |
| 组织策略：限制安装请求 | https://docs.github.com/en/organizations/managing-organization-settings/limiting-oauth-app-and-github-app-access-requests-and-installations |

**本仓库相关文档**

| 文档 | 用途 |
|---|---|
| [`07-repository-githubapp.md`](./07-repository-githubapp.md) | GitHub App 凭据在 Argo CD 哪里配、分支为什么不在 Repository 里 |
| [`git-apps/11-github-app-concepts.md`](./git-apps/11-github-app-concepts.md) | App / Installation / Webhook 概念与源码对应 |
| [`git-apps/14-rulesets-and-gitapp-gate.md`](./git-apps/14-rulesets-and-gitapp-gate.md) | Ruleset + App 组成合并门禁（**按分支生效的正解**） |
| [`git-apps/16-ruleset-install-runbook.md`](./git-apps/16-ruleset-install-runbook.md) | ruleset 装上去的 Runbook（组织级 vs 仓库级端点差异） |
| [`git-apps/13-cr-check-go-design.md`](./git-apps/13-cr-check-go-design.md) | CR Check 后端：拿到事件后怎么判分支 |
| [`git-apps/webhook-and-backend-service.md`](./git-apps/webhook-and-backend-service.md) | 安装 → Webhook → 后端的完整链路 |
