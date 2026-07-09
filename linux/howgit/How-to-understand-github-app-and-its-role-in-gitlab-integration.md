# 如何理解 GitHub App —— 跟 OAuth App / PAT / Webhook 的区别,以及它在 GitHub→GitLab 触发链路里的真实角色

> **TL;DR — 30 秒版本**
>
> - **GitHub App 是一等公民(first-class actor),不是 user 代理**。装在 GitHub repo / org 上之后,它**自己就是 actor**(`@my-app[bot]`),跟 user/team 同级。Org owner 离职不会影响 App。
> - **Token 寿命 1 小时**。`installation access token` 必须用 App private key 签 JWT 持续换;OAuth token 不手动 revoke 就一直有效;PAT(classic)也是长期 token。
> - **权限细粒度**。OAuth 想拿 PR 权限必须给 `repo` scope(顺带把整个代码也给了),GitHub App 只勾 "Pull requests: Read" 即可,不会自动拿到代码。
> - **关键澄清**:**你不能在 GitLab 里装 GitHub App**。GitHub App 只能装在 GitHub 自己的 repo/org 上。**真正的"GitHub 变更 → GitLab pipeline"路径有 3 条**:① 自建 GitHub App + 你的 receiver(最灵活);② GitLab 内置 "CI/CD for external repository"(Premium);③ GitLab pull mirroring(容忍 5 分钟延迟)。
> - **App 跟 Webhook 的关系**:App **自带**一个集中 webhook(所有 installation 共享),payload 里**带** `installation.id`,receiver 凭这个 ID 换 access token **回 call GitHub API**;裸 webhook 只单向 push 通知,不能回问。
> - **App 权限 ≠ Collaborator 角色**。App 权限是 bot 的"能力清单"(几十种细粒度 ability);Collaborator 角色是人的 5 档身份(Read / Triage / Write / Maintain / Admin)。**两条独立 / 正交体系**,跟 [`github-repo-role-permissions.md`](./github-repo-role-permissions.md) 互补。

如果你只想记住一句话:

> 📌 **"触发下游" webhook 就够;"读 GitHub + 触发"必须 GitHub App。** GitHub App 装不到 GitLab — 你想 GitHub 当 source-of-truth、GitLab 跑 pipeline,真正的方案是 GitHub 端装 App(或者用裸 webhook)+ receiver 服务跑在 GitLab 侧。

---

## 1. 为什么这篇文档要存在?

姊妹文章 [`github-repo-role-permissions.md`](./github-repo-role-permissions.md) 已经在讲 GitHub 仓库**对人**的 5 档 RBAC 权限(Read / Triage / Write / Maintain / Admin)。但日常工程师碰到的另一个常见困惑是:

|| 你困惑的问题 | 本文核心解答 |
|--|--|--|
| "团队要把 GitHub 当 source-of-truth,触发 GitLab pipeline,该用啥?" | **3 条真实路径,选 1 条**(见 §5) |
| "GitHub App 跟 OAuth App 到底啥区别?" | **身份模型 + token 寿命 + 权限粒度 3 个维度**(见 §3.1) |
| "GitHub App 跟 PAT(Personal Access Token)啥区别?" | App 是 actor / PAT 是绑死 user 的 token(见 §3.2) |
| "GitHub App 跟 Webhook 啥区别?" | App webhook **带身份**(`installation.id`),裸 webhook **只通知**(见 §3.3) |
| "App 权限跟 collaborator role 是同一套吗?" | **两条正交体系** — App 权限管 bot,collaborator role 管人(见 §3.4) |
| "我能在 GitLab 装一个 GitHub App 吗?" | **不能**。GitHub App 只能装在 GitHub 自己的 repo/org 上(见 §4) |
| "App 收 webhook 时,receiver 怎么回 call GitHub API?" | 从 payload 读 `installation.id` → 签 JWT → 换 1h token → 调 API(见 §6) |

把这篇读完,你会用**一张心智模型**把"GitHub 通知 + 触发"这件事在 3 个不同的解法路径里**精确选型**,而不是听别人说"用 App"你就用 App。

---

## 2. 三种视角:同一件事的三个切面

为了不让你"看了定义还是不会用",下文用三种视角讲同一事实,任选你舒服的那个入口:

- **§3 抽象视角**:从"GitHub 的身份模型"出发 — actor / token / permission 三个轴
- **§4 朴素视角**:从"具体场景:GitHub→GitLab trigger"出发 — 一步一步把 App 装上、webhook 配好、receiver 写好
- **§5 严格视角**:**3 条真实路径的 trade-off 矩阵** + 选型决策树

**(还有一个 §6 "1 小时 token 的精确续期流程",给"我就要看代码"的人用。)**

---

## 3. 抽象视角:GitHub 的 3 个轴 — actor / token / permission

把 GitHub 想象成一个对**仓库 + 用户 + 自动化**建模的系统,核心抽象是 **3 个独立轴**。

### 3.1 轴 1 — 身份模型(actor model)

GitHub 上"能代表一个身份调 API"的方式有 3 类:

```
                       ┌──────────────────────────────────┐
                       │      "我能用啥身份调 GitHub API"     │
                       └──────────────────────────────────┘
                          │                │                │
                          ▼                ▼                ▼
                  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
                  │  GitHub App  │  │  OAuth App   │  │  PAT         │
                  │  (actor)     │  │  (proxy)     │  │  (token)     │
                  └──────────────┘  └──────────────┘  └──────────────┘
```

|| 身份类型 | 本质 | 装在哪 | Token 寿命 | 寿命证据 |
|--|--|--|--|--|
| **GitHub App** | **first-class actor**(`@my-app[bot]`,不是 user 代理) | GitHub repo / org | 1 小时 | "The installation access token will expire after 1 hour" |
| **OAuth App** | **impersonate** 一个 user,所有动作以该 user 身份 | 用户授权 | 长期(手动 revoke) | "OAuth tokens remain active until they're revoked by the customer" |
| **PAT**(Personal Access Token) | 绑死到 user 的 token,本质是"有额外权限的密码" | user 自己生成 | 长期(classic)/ 1 年(fine-grained) | 用户自管 |

**关键证据**(GitHub 官方原话,from <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/differences-between-github-apps-and-oauth-apps>):

> "Like OAuth apps, GitHub Apps use OAuth 2.0 and can act on behalf of a user. **Unlike OAuth apps, GitHub Apps can also act independently of a user.**"

> "An installation token identifies the app as the GitHub Apps bot, such as @jenkins-bot."

> "An access token identifies the app as the user who granted the token to the app, such as @octocat."

**核心判断**:GitHub App 装在 repo/org 之后,**自己就是 actor**(`@my-app[bot]`),不是某个工程师的马甲。Org owner 离职不会影响 App;**PAT 跟 OAuth App 会**。这就是为什么 GitHub 在 2022 年起强烈推荐把 OAuth App 迁成 GitHub App([Migrating OAuth apps to GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/migrating-oauth-apps-to-github-apps))。

### 3.2 轴 2 — Token 寿命(token lifetime)

|| 类型 | Token 寿命 | 续期方式 |
|--|--|--|--|
| GitHub App | **1 小时** | 用 App private key 签 JWT → `POST /app/installations/{id}/access_tokens` 换新 |
| OAuth App | 长期 | 用户手动 revoke(或者 token 失效) |
| PAT(classic) | 长期 | 用户自己轮换 |
| PAT(fine-grained) | 自定义,最长 1 年 | 用户自己轮换 |

**GitHub 官方原话**(from <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation>):

> "The installation access token will expire after 1 hour."

**为什么这个对 GitHub→GitLab 场景很重要?** 因为你的 receiver 服务必须**自动续 token**,不能依赖人手动操作。如果用 PAT,那个人离职就停摆;如果用 GitHub App,token 1h 过期但**自动续**,运维完全无感。

### 3.3 轴 3 — 权限粒度(permission granularity)

|| Access | GitHub App permission | OAuth scope |
|--|--|--|
| Repository code/contents | `Contents: Read/Write` | `repo` |
| Issues, labels, milestones | `Issues: Read/Write` | `repo`(粗) |
| Pull requests, labels | `Pull requests: Read/Write` | `repo`(粗) |
| Commit statuses(CI builds) | `Commit statuses: Read/Write` | `repo:status` |
| Deployments | `Deployments: Read/Write` | `repo_deployment` |
| Receive events via webhook | (默认开启) | `write:repo_hook` 等 |

**GitHub 官方原话**(from <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/differences-between-github-apps-and-oauth-apps>):

> "Unlike OAuth apps, GitHub Apps have targeted permissions that allow them to request access only to what they need. For example, a Continuous Integration (CI) GitHub App can request read access to repository content and write access to the status API. **Another GitHub App can have no read or write access to code but still have the ability to manage issues, labels, and milestones. OAuth apps can't use granular permissions.**"

**关键判断**:OAuth 想拿 PR 权限必须给 `repo` scope,顺带把整个 repo 代码也给了 — 这是"过度授权"的典型。GitHub App 想要 PR 权限只勾 "Pull requests: Read",**不会**自动拿到代码。这就是为什么金融/医疗/合规场景**必须用 GitHub App**,不能用 OAuth App。

### 3.4 轴 4 — Webhook 的"双向"能力(actor vs 通知)

这一条最容易被忽略,也是 GitHub App 跟裸 webhook 真正的本质区别:

|| 场景 | 裸 webhook | GitHub App webhook |
|--|--|--|
| 通知 / 触发下游(发邮件、起 pipeline) | ✅ | ✅(更干净) |
| 读 commit / PR / repo 详细内容 | ❌ 没有 token,得另搞 PAT | ✅ installation access token |
| 写 status check / comment / approve PR 回 GitHub | ❌ | ✅ |
| 验签(确认消息来自 GitHub) | ✅ HMAC SHA-256(`X-Hub-Signature-256`) | ✅ 同上 |
| Webhook 单点 vs 每 repo 配 | 每 repo 配一个 | **App 单点收所有 installation** |

**GitHub 官方原话**(from <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/differences-between-github-apps-and-oauth-apps#webhooks>):

> "By default, GitHub Apps have a single webhook that receives the events they are configured to receive for every repository they have access to. Conversely, OAuth apps must configure webhooks individually for each repository and organization."

> "Webhooks are automatically disabled when the GitHub App is uninstalled."

**关键原话**(payload 字段,from <https://docs.github.com/en/webhooks-and-events/webhooks/webhook-events-and-payloads>):

> "`installation` | `object` | The GitHub App installation. Webhook payloads contain the installation property when the event is configured for and sent to a GitHub App."

**判断口诀**:
- **"被通知 + 触发下游"** → 裸 webhook 就够了
- **"读 GitHub 数据 + 触发"** → **必须用 App**(只有 App 的 webhook payload 带 `installation.id`,能换 access token 回 call)

### 3.5 三轴合并:四类身份的"决策矩阵"

|| 场景 | 推荐 | 理由 |
|--|--|--|
| CI/CD 跑 pipeline(读 commit + 写 status check) | **GitHub App** | 细粒度权限 + 1h token + 双向 webhook |
| 给 GitHub PR 写自动 review bot | **GitHub App** | 同上 |
| 通知 / Slack 提醒(只读 push 事件) | 裸 webhook | 最简单,够用 |
| 用户自己跑一次性脚本调 API | **PAT(fine-grained)** | 个人用,1 年过期,免安装 |
| 老旧的"我用 `repo` scope 写脚本" | ❌ 改用 App 或 fine-grained PAT | OAuth coarse scope 已被 GitHub 官方 deprecate |

---

## 4. 朴素视角:具体场景 "GitHub→GitLab trigger" 怎么落地

> **关键澄清**:你不能在 GitLab 里装 GitHub App。**GitHub App 只能装在 GitHub 自己的 user account / organization / repository 上**。如果听到"在 GitLab 装 GitHub App"这种说法,基本可以判定是误用词。
>
> GitHub 官方原话(from <https://docs.github.com/en/apps/using-github-apps/installing-a-github-app-from-a-third-party>):
>
> > "In order to use a GitHub App on your resources, you must install the app on your organization or personal account."

那"GitHub 变更 → GitLab pipeline"的真正路径是什么?**有 3 条,选 1 条**。

### 4.1 路径 A:自建 GitHub App + 你的 receiver(最灵活)

**架构**:

```
[GitHub repo] ─── push / PR ──→ [GitHub App] ←── 装在 GitHub org/repo 上
                                  │
                                  │  (webhook, HTTP POST,payload 带 installation.id)
                                  ↓
                  [你的 receiver 服务,跑在 GitLab 侧 / 独立 / K8s]
                                  │
                                  │  POST /api/v4/projects/{id}/trigger/pipeline
                                  ↓
                          [GitLab Pipeline] → 触发 Argo CD sync
```

**具体步骤**:

1. 你**自己**写一个 GitHub App(或者用现有 scaffold,如 [Probot](https://probot.github.io/))
2. 在 GitHub App 注册时配 webhook URL = `https://your-receiver.example.com/github-webhook`
3. 订阅 events: `push`, `pull_request`, `create`, `delete`(按需)
4. Permissions 勾: `Contents: Read` + `Pull requests: Read` + `Checks: Write`(如果要回写 status)
5. 把 App 装到 GitHub org
6. receiver 收到 webhook → 解析 `installation.id` → 拿 installation token → 解析 payload → 调 `POST /api/v4/projects/{id}/trigger/pipeline`(ref = payload 里 commit SHA)

**GitHub 官方原话**(from <https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps>):

> "A GitHub App that uses webhooks to react to an event given a certain set of criteria."

**适用条件**:
- 你需要"GitHub push 触发 GitLab pipeline"**且** "pipeline 还要回查 GitHub 拿更多上下文"(比如读 commit diff 决定要不要 deploy)
- 你愿意自己写 receiver 服务
- 你需要回写 GitHub status check(`Checks: Write` 权限)

### 4.2 路径 B:GitLab 内置 "CI/CD for external repository"(更简单)

GitLab 自带一个功能:**用 GitHub 当 remote,GitLab 跑 CI**。GitLab 直接订阅 GitHub 的 push / pull_request webhook,**不用你写 GitHub App**。

**GitLab 官方原话**(from <https://docs.gitlab.com/ci/ci_cd_for_external_repos/>):

> "GitLab CI/CD can be used with GitHub, Bitbucket Cloud, or any other Git server. ... Instead of moving your entire project to GitLab, you can connect your external repository to get the benefits of GitLab CI/CD."

> "When a repository is imported from GitHub, **GitLab subscribes to webhooks for push and pull_request events.**"

**适用条件**:
- GitLab Premium / Ultimate(tier 限制)
- 你接受"GitLab 是 CI runner,GitHub 才是 source of truth"的模型
- 你不需要从 GitHub 回传 status check(虽然 GitLab 提供 GitHub integration 做反向 status,见 §4.4)

### 4.3 路径 C:GitLab Pull Mirroring(单向同步,最轻量)

更轻量:**GitLab 主动定时拉 GitHub**。GitLab 自己 5 分钟(默认)pull 一次 GitHub 的 commit。

**GitLab 官方原话**(from <https://docs.gitlab.com/user/project/repository/mirror/>):

> "Pull: Mirror a repository from another location."

**适用条件**:
- 你不需要 PR 事件触发,只要 main / release branch 变了就触发
- 可以接受 5 分钟延迟
- 不想要 webhook 复杂度

### 4.4 路径 D(反向):GitLab → GitHub 写 status check

这不是 trigger 路径。这是 **GitLab → GitHub 单向**:GitLab pipeline 跑完,把 status 写回 GitHub PR。跟 GitHub App 没关系,需要的是 GitHub PAT with `repo:status` scope。

**GitLab 官方原话**(from <https://docs.gitlab.com/user/project/integrations/github/>):

> "You can update GitHub with pipeline status updates from GitLab. The GitHub integration can help you if you use GitLab for CI/CD."

> "This integration requires a GitHub API token with **repo:status** access granted."

**适用条件**:
- GitHub 当 source-of-truth + 显示入口
- GitLab pipeline 跑完后希望 PR 上能看到 ✅ / ❌ 状态

### 4.5 路径选型总结

| 你的需求 | 路径 | 复杂度 |
|--|--|--|
| 实时 push/PR 触发 + 需要回查 GitHub 上下文(status / comment) | **路径 A 自建 GitHub App** | 中 |
| 实时 push/PR 触发 + 不需要回查 GitHub | **路径 B GitLab external repo** | 低 |
| 容忍 5 分钟延迟 + 极简 | **路径 C GitLab pull mirroring** | 极低 |
| GitLab pipeline → 回写 GitHub status check | **路径 D GitHub integration** | 低 |
| 既要 A 又要 D | A + D 组合 | 中 |

---

## 5. 严格视角:3 条路径的 trade-off 矩阵 + 选型决策树

### 5.1 4 个维度对比

|| 维度 | 路径 A 自建 App | 路径 B External Repo | 路径 C Pull Mirror | 路径 D Status Check |
|--|--|--|--|--|
| **GitHub 端装什么** | GitHub App(自己写) | 啥都不装(GitLab 订阅 GitHub webhook) | 啥都不装 | PAT with `repo:status` |
| **GitLab 端装什么** | 你的 receiver 服务 + GitLab API token | GitLab 内置功能(Premium) | GitLab 内置功能(free) | GitLab integration |
| **触发延迟** | 实时(webhook) | 实时(webhook) | **5 分钟** | 反向,不触发 |
| **GitHub → GitLab 单向?** | ✅ | ✅ | ✅ | ❌(反向) |
| **回查 GitHub context?** | ✅ installation token | ❌ | ❌ | ❌ |
| **回写 GitHub status?** | ✅ Checks: Write | ❌(除非配 D) | ❌ | ✅ |
| **需要 Premium?** | 否 | **是** | 否 | 否 |
| **人离职风险** | 低(用 App) | 低 | 低 | **高**(用 PAT) |
| **复杂度** | 中 | 低 | 极低 | 低 |

### 5.2 决策树

```
你的需求是什么?
  │
  ├── "GitHub 变 → 立刻触发 GitLab pipeline,容忍 Premium tier"
  │     │
  │     ├── "需要 pipeline 读 GitHub 上下文(diff / 关联 PR)"
  │     │     → 路径 A 自建 GitHub App ★
  │     │
  │     └── "pipeline 只需要知道 commit SHA 就够"
  │           → 路径 B GitLab external repo (Premium) ★
  │
  ├── "5 分钟延迟没问题 + 不想付 Premium"
  │     → 路径 C GitLab pull mirroring ★
  │
  ├── "GitLab pipeline 跑完 → GitHub PR 上要看到 ✅/❌"
  │     → 路径 D GitHub integration (独立) ★
  │
  └── "既要触发 + 又要 status check 回写"
        → 路径 A + 路径 D 组合
```

### 5.3 默认建议

**最常见组合**:
- **路径 B**(Premium 用户,只要触发)+ **路径 D**(回写 status)— "GitLab 当 CI,GitHub 当 source-of-truth + 显示入口"
- **路径 A**(自建,需要细粒度控制) — 适合金融/医疗/合规场景,或者需要"读 commit 决定 deploy 策略"的复杂 CI

**别用**:
- 路径 A 用 OAuth App 替代 GitHub App(粗粒度权限,过度授权)
- 路径 D 用 classic PAT(长期 token,人离职风险高)
- 任何方案用裸 webhook 触发 + 想"回查 GitHub"(裸 webhook 没身份,做不到)

---

## 6. 1 小时 token 的精确续期流程(给"我就要看代码"的人)

> 这一节是 §3.2 + §3.4 的代码级展开 — 如果你只想知道"App webhook 是单向还是双向",看 §3.4 就够;想看 receiver 怎么续 token,看这里。

### 6.1 完整流程时序

```
[GitHub repo] ─── push event ──→
                                 │
                                 ↓
[GitHub App webhook 触发] ────→ POST https://your-receiver.example.com/github-webhook
                                 │  body: { action, installation: { id: 12345 }, ... }
                                 ↓
[你的 receiver 服务]
   │
   │ 1. 验签 X-Hub-Signature-256 (确认来自 GitHub)
   │ 2. 从 payload 读 installation.id (= 12345)
   │ 3. 用 App private key 签 JWT
   │    header: { alg: RS256 }
   │    payload: { iat: now, exp: now+10min, iss: <APP_ID> }
   │ 4. POST https://api.github.com/app/installations/12345/access_tokens
   │      Authorization: Bearer <JWT>
   │    → response: { token: "ghs_xxx", expires_at: "2026-07-09T..." }
   │ 5. 缓存这个 token,expires_at 之前复用,过期前再走 3-4
   │ 6. 解析 payload(commit SHA / PR number / etc.)
   │ 7. POST https://gitlab.example.com/api/v4/projects/{id}/trigger/pipeline
   │      body: { token: <GITLAB_PIPELINE_TOKEN>, ref: <commit SHA>, variables: {...} }
                                 │
                                 ↓
                         [GitLab Pipeline] → Argo CD sync
```

### 6.2 receiver 伪代码(Python)

```python
# receiver.py — 装在 GitLab 侧 / 独立 K8s
import jwt
import time
import hmac
import hashlib
import requests
from flask import Flask, request, abort

app = Flask(__name__)

GITHUB_APP_ID = 123456  # from App settings page
GITHUB_WEBHOOK_SECRET = b"..."  # from App webhook config
GITLAB_PIPELINE_TOKEN = "..."   # GitLab project settings → CI/CD → Pipeline triggers
GITLAB_PROJECT_ID = 42

token_cache = {}  # {installation_id: (token, expires_at)}

def get_installation_token(installation_id: int) -> str:
    """续一个 1 小时有效的 installation access token。"""
    if installation_id in token_cache:
        token, expires_at = token_cache[installation_id]
        if time.time() < expires_at - 60:  # 提前 60s 刷新
            return token

    # 1. 签 JWT(用 App private key)
    now = int(time.time())
    payload = {
        "iat": now,
        "exp": now + 600,  # JWT 本身最多 10 分钟
        "iss": GITHUB_APP_ID,
    }
    with open("/secrets/app-private-key.pem", "rb") as f:
        private_key = f.read()
    jwt_token = jwt.encode(payload, private_key, algorithm="RS256")

    # 2. 换 installation token
    r = requests.post(
        f"https://api.github.com/app/installations/{installation_id}/access_tokens",
        headers={
            "Authorization": f"Bearer {jwt_token}",
            "Accept": "application/vnd.github+json",
        },
    )
    r.raise_for_status()
    data = r.json()
    token = data["token"]
    expires_at = int(time.mktime(time.strptime(data["expires_at"], "%Y-%m-%dT%H:%M:%SZ")))

    token_cache[installation_id] = (token, expires_at)
    return token


@app.route("/github-webhook", methods=["POST"])
def github_webhook():
    # 1. 验签
    signature = request.headers.get("X-Hub-Signature-256", "")
    expected = "sha256=" + hmac.new(GITHUB_WEBHOOK_SECRET, request.data, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(signature, expected):
        abort(401)

    payload = request.json
    installation_id = payload["installation"]["id"]
    event = request.headers.get("X-GitHub-Event")

    if event == "push":
        ref = payload["ref"]  # e.g. "refs/heads/main"
        sha = payload["after"]  # commit SHA
    elif event == "pull_request":
        if payload["action"] not in ("opened", "synchronize", "reopened"):
            return "ignored", 200
        ref = payload["pull_request"]["head"]["ref"]
        sha = payload["pull_request"]["head"]["sha"]
    else:
        return "event not handled", 200

    # 2. 拿 token(其实这一步对这个 trigger 场景不是必须 — 见注释)
    # 如果你只是要 trigger GitLab pipeline,**不调 GitHub API**,这步可以省。
    # 只有当你需要回查 GitHub(读 diff、写 status check)时才需要。
    # gh_token = get_installation_token(installation_id)

    # 3. trigger GitLab pipeline
    r = requests.post(
        f"https://gitlab.example.com/api/v4/projects/{GITLAB_PROJECT_ID}/trigger/pipeline",
        data={"token": GITLAB_PIPELINE_TOKEN, "ref": ref, "variables[GITHub_SHA]": sha},
    )
    r.raise_for_status()
    return "ok", 200
```

**关键点**:
- 第 1 步的 JWT 寿命 10 分钟(不是 1 小时)— JWT 是"换 token 的钥匙",短一点更安全
- 第 2 步换出的 installation token 才是 1 小时,缓存复用
- 如果 receiver 只是 trigger GitLab pipeline,**根本不需要 GitHub token**(GitLab pipeline trigger 走 GitLab 的 pipeline trigger token,跟 GitHub 无关)。只有当你需要"回查 GitHub diff 决定 deploy 策略"才需要 token

### 6.3 安装到 GitHub 的步骤(界面流)

1. GitHub → Settings → Developer settings → GitHub Apps → New GitHub App
2. 填: GitHub App name / Homepage URL / Webhook URL = `https://your-receiver.example.com/github-webhook` / Webhook secret = 任意强密码
3. Repository permissions: Contents: Read-only, Pull requests: Read-only, Checks: Read & write(如果要回写 status)
4. Subscribe to events: 勾 push, pull_request, create, delete(按需)
5. "Create GitHub App" → 记下 App ID → 生成 private key(下载 .pem)
6. 左边菜单 "Install App" → 选 org → All repositories(或 select repos)
7. 安装完会给你一个 `installation_id`(在 URL 里能看到) — receiver 凭这个 ID 换 token

---

## 7. 跟 Collaborator 角色的关系 — 两条正交体系

这一节呼应姊妹文章 [`github-repo-role-permissions.md`](./github-repo-role-permissions.md),澄清"App 权限"跟"人权限"是两套独立体系。

### 7.1 对照表

| 维度 | GitHub App 权限 | Collaborator Role |
|--|--|--|
| **主体** | App(bot,first-class actor) | 人(organization member / outside collaborator) |
| **粒度** | 几十种细粒度 ability(Contents / PRs / Checks / Issues / ...) | 5 档(R / T / W / M / A) |
| **作用域** | Repository / Organization / Account | Repository |
| **作用** | 决定 App 能不能调某个 API / 收某个 webhook | 决定人能不能 push / merge / 设 branch protection |
| **跟 seat 关系** | App bot 不占 Enterprise seat | 一个人一档 role,占一个 seat |

**GitHub 官方原话**(from <https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app>):

> "GitHub Apps don't have any permissions by default. When you register a GitHub App, you can select permissions for the app. The permissions that you select determine what the app can do with GitHub's APIs and what webhooks the app can subscribe to. **You should select the minimum permissions required for the app.**"

> "App permissions are classified as repository, organization, or account permissions."

> "GitHub App bots do not consume a GitHub Enterprise seat."

**关键判断**:**App 权限 ≠ 人的权限**。给 App 勾 `Contents: Write` 不会让某个 collaborator 变强;给某 collaborator 提 Admin 也不会影响 App 看到什么。两条正交体系。

### 7.2 常见误解

|| 误解 | 事实 |
|--|--|--|
| "App 勾 Contents: Write,collaborator 就能 push" | ❌ App 写 Contents 是 **App 自己**写,不是 collaborator。collaborator 的 push 权限仍由他的 role 决定 |
| "给 collaborator Admin 角色,App 就能调所有 API" | ❌ App 权限是注册时定的,跟任何 collaborator 的 role 无关 |
| "App 必须有 Write 权限才能用 webhook 通知" | ❌ Read 权限就够了,webhook 是 event 订阅不是写操作 |
| "App 安装到 org 后,所有 repo 自动都受它控制" | 部分对 — 如果装时选 "All repositories" 就全选;但 App 仍受 permissions 限制,不能调所有 API |

---

## 8. 引用来源 / 权威证据

### 8.1 GitHub App 核心概念
- 📘 **Differences between GitHub Apps and OAuth apps**: <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/differences-between-github-apps-and-oauth-apps>
  - 本文 §3.1 / §3.3 / §3.4 / §7.1 的核心依据
  - 直接引用:
    > "Unlike OAuth apps, GitHub Apps have targeted permissions that allow them to request access only to what they need."
    > "By default, GitHub Apps have a single webhook that receives the events they are configured to receive for every repository they have access to."
- 📘 **About creating GitHub Apps**: <https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps>
  - §4.1 路径 A 的依据
- 📘 **About authentication with a GitHub App**: <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/about-authentication-with-a-github-app>
- 📘 **Authenticating as a GitHub App installation**(1 小时 token): <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation>
  - §3.2 / §6.1 的 1 小时 token 依据
  - 直接引用:
    > "The installation access token will expire after 1 hour."
- 📘 **Choosing permissions for a GitHub App**(细粒度权限 + subscribed events 联动): <https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app>
  - §3.3 / §7.1 的依据
  - 直接引用:
    > "On your GitHub App registration page, the available webhook events will change as you change your app's permissions."
- 📘 **Installing a GitHub App from a third party**: <https://docs.github.com/en/apps/using-github-apps/installing-a-github-app-from-a-third-party>
  - §4 关键澄清的锚点
  - 直接引用:
    > "In order to use a GitHub App on your resources, you must install the app on your organization or personal account."
- 📘 **Migrating OAuth apps to GitHub Apps**: <https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/migrating-oauth-apps-to-github-apps>
  - §3.1 "为什么 GitHub 强烈推荐迁移"的依据

### 8.2 GitHub Webhook
- 📘 **About webhooks**: <https://docs.github.com/en/webhooks-and-events/webhooks/about-webhooks>
  - §3.4 / §4.1 的依据
- 📘 **Webhook events and payloads**(`installation` 字段在 Common payload parameters): <https://docs.github.com/en/webhooks-and-events/webhooks/webhook-events-and-payloads>
  - §3.4 "App webhook 带 `installation.id`" 的直接证据
- 📘 **Building a GitHub App that responds to webhook events**(tutorial): <https://docs.github.com/en/apps/creating-github-apps/writing-code-for-a-github-app/building-a-github-app-that-responds-to-webhook-events>
  - §6 receiver 实现的 tutorial reference

### 8.3 GitHub Collaborator Role(姊妹文章)
- 📘 **Repository roles for an organization**(R/T/W/M/A 5 档): <https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization>
  - §7 跟 App 权限对比的依据
  - 完整解读见 [`github-repo-role-permissions.md`](./github-repo-role-permissions.md)

### 8.4 GitLab 集成(下游消费方)
- 📘 **CI/CD for external repositories**(路径 B 主文档): <https://docs.gitlab.com/ci/ci_cd_for_external_repos/>
  - §4.2 路径 B 的依据
  - 直接引用:
    > "When a repository is imported from GitHub, GitLab subscribes to webhooks for push and pull_request events."
- 📘 **Repository mirroring**(路径 C pull / push mirror): <https://docs.gitlab.com/user/project/repository/mirror/>
  - §4.3 路径 C 的依据
- 📘 **GitHub integration**(路径 D 反向 status check): <https://docs.gitlab.com/user/project/integrations/github/>
  - §4.4 路径 D 的依据
  - 直接引用:
    > "This integration requires a GitHub API token with repo:status access granted."

---

## 9. 跟本仓库既有文档的交叉

|| 本文档概念 | 既有文档 |
|--|--|
| Collaborator 5 档(R/T/W/M/A) | [`github-repo-role-permissions.md`](./github-repo-role-permissions.md) — 详细 RBAC 矩阵(逐项核对) |
| Webhook 用法(bare) | [`docs/webhook.md`](./docs/webhook.md) — 旧版 chatgpt 风格的 PR trigger 教程,**没覆盖 GitHub App** |
| Git 内部机制(tree id / commit id) | [`How-to-understand-tree-id-and-commit-id.md`](./How-to-understand-tree-id-and-commit-id.md) |
| PR commit id 怎么拿 | [`How-to-get-commitid.md`](./How-to-get-commitid.md) |

> **本文跟 `github-repo-role-permissions.md` 是 sibling** — 那个是"人的权限",本文是"App 的权限"。读者先看哪个都行,但要把两个一起看才能形成完整图景。

---

## 10. 一句话原则

> 📌 **GitHub App 装不到 GitLab — 它只能装在 GitHub repo/org 上。**"GitHub 变更 → GitLab pipeline" 的真实路径有 3 条(自建 App / external repo / pull mirror),选 1 条;**"读 GitHub + 触发"必须 App,只"通知触发"裸 webhook 就够**;**App 权限跟 Collaborator Role 是两条正交体系**(前者管 bot,后者管人)。

---

## 11. 未验证 / 探索期假设

(以下"事实"未在这次 explore 中独立 verify,留给你 prod 落地时或在第二个探索会话中专项确认)

- [ ] **App installation 数量上限**:GitHub 对 org 安装的 App 数量有没有上限?(没在 docs 找到明确数字 — 通常不受限,但需要 confirm)
- [ ] **GitLab Premium tier 当前定价**:路径 B 强依赖 Premium,但 Premium 价格随 seat 数变 — 落地前要算 ROI
- [ ] **GitHub Enterprise Cloud + GitLab Self-hosted 跨 IDP 联合**:大企业场景下,GitHub Enterprise 跟 GitLab 之间可能要走 SAML/OIDC 联合认证,本文没覆盖
- [ ] **App Webhook 的 retry 机制**:GitHub 推 webhook 失败时的重试次数和 backoff(目前没在官方文档找到具体数字,可能有 SLA 但不确定)
- [ ] **Cross-organization installation 边界**:一个 GitHub App 装在 Org A,能否对 Org B 的 repo 起作用?(推测需要 Org B owner 显式授权,但需要 confirm)
- [ ] **GitHub App 跟 GitHub Actions 的关系**:能不能用 GitHub App 触发 GitHub Actions workflow?(这个跟 GitLab 路径是另一条线,但应该短说一句 — `on: push` 触发跟 webhook 不冲突,跟 App 也并存)

---

✅ 全文完毕。配套阅读:`github-repo-role-permissions.md`(人的 RBAC)+ `docs/webhook.md`(裸 webhook 用法)+ `How-to-understand-tree-id-and-commit-id.md`(Git 内部机制)— 这 4 篇一起构成"GitHub 协作 + 自动化"完整图景。
