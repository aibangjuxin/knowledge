# 03 · SSO 身份打通：OIDC 直连 / Dex + OIDC / Dex + LDAP

> 目标：把 Argo CD 的登录方式从"内置 `admin` 账号"换成
> **"公司 SSO 个人账号 + 组授权"**，并**禁用内置 `admin`**。
>
> 本文覆盖**三种接入模式**，每种都给出：什么时候用 / 完整配置 / 验证方法 / 排障。
> 文件名保留 `03-dex-ldap-sso.md` 是为了不破坏仓库里已有的链接，**内容已按三种模式重构**。

---

## 0. 结论先行：先选模式

| 你的实际情况 | 选这个模式 | 配置写在 | 额外组件 |
|---|---|---|---|
| **公司已有统一 IdP**（Okta / Entra ID / Keycloak / Auth0 / Google Workspace），员工用个人账号 SSO | **模式 A：OIDC 直连** ✅ 首选 | `argocd-cm` 的 `oidc.config` | 无 |
| IdP 是 OIDC，但**组不在 ID Token 里**、或要同时接多个 IdP、或要给 CI 做**令牌交换** | 模式 B：Dex + OIDC | `argocd-cm` 的 `dex.config` | 内置 `argocd-dex-server` |
| **只有 LDAP / AD**，没有 OIDC | 模式 C：Dex + LDAP | `argocd-cm` 的 `dex.config` | 内置 `argocd-dex-server` |
| IdP 只有 **SAML** | 模式 B 的 `type: saml` connector | `argocd-cm` 的 `dex.config` | 内置 `argocd-dex-server` |

**一句话原则：企业已经有 OIDC，就别装 Dex。**
Dex 存在的唯一价值是"把非 OIDC 的身份系统翻译成 OIDC"，以及"从 UserInfo 端点补组"、
"多连接器"、"令牌交换"这几个附加能力。用 Dex 多引入一个需要维护的有状态组件
（登录态存在 Dex 里），换来一堆坑。

> **模式 A 能满足你说的"个人 ID 号 + SSO"形态**：
> 员工在 IdP 里有个人账号 → 点登录 → 跳到公司 IdP → 输自己的账号密码 / 走 MFA →
> 回到 Argo CD → 靠 IdP 里的**组**决定权限。整条链路里**没有密码落在 Argo CD 里**。

---

## 1. 背景：Argo CD 的认证模型

### 1.1 Argo CD 没有用户目录

Argo CD 自己**不存用户、不存密码**（LDAP 模式下也不存）。它只有三类身份：

| 身份来源 | 怎么来的 | 谁能用 |
|---|---|---|
| 内置 `admin` | 安装时随机生成密码，存在 `argocd-secret` | 一直能用，直到你设 `admin.enabled: "false"` |
| 本地账号 | `argocd-cm` 的 `accounts.<name>: login,apiKey` + `argocd-secret` 的 bcrypt | 一直能用（**SSO 之后应该清掉**） |
| 外部 IdP | OIDC / Dex | 你配好才有 |

### 1.2 SSO 的成败只取决于两件事

```
认证（Authentication）：能不能用公司账号登进来 → 由 IdP + oidc.config/dex.config 决定
授权（Authorization）：登进来的人能看到什么   → 由 token 里的 claim + policy.csv 决定
```

所以**任何"配了 SSO 但进不去 / 没权限"的问题，只可能出在这两处**：
要么 token 根本没拿到（认证），要么 token 里没有你以为的那个 claim（授权）。

Argo CD 拿 claim 的链路（模式 A）：

```
IdP  ── 签发 ID Token ──▶  argocd-server 验证签名/iss/aud
                                    │
                                    ├─ subject（用户主体）= token 的 sub
                                    └─ 候选主体（组/邮箱）= token 里 scopes 指定的那些 claim
                                             │
                                             ▼
                              Casbin: g, <主体>, <角色>  ← argocd-rbac-cm/policy.csv
```

> 上游源码依据（`util/jwt/jwt.go`）：
> `GetUserIdentifier()` → 取 `sub`（有 `federated_claims.user_id` 时优先用它）；
> `GetScopeValues(claims, scopes)` → **按 `scopes` 里的名字去 token 里取 claim 值**
> （数组/字符串都算），取到的每一个值都当作候选 RBAC 主体。
> 👉 这里的 `scopes` **是 claim 的名字**，不是 OAuth 的 scope。详见 §6.2。

### 1.3 三种模式的链路对比

```
模式 A：OIDC 直连
[ 浏览器 ] → [ Argo CD /auth/callback ] ⇄ [ 公司 IdP ]
                        (argocd-server 直接验签，无中间层)

模式 B / C：Dex
[ 浏览器 ] → [ Argo CD ] → [ argocd-dex-server ] ⇄ [ IdP ]
                                  (Dex 是翻译官：LDAP/SAML → OIDC)
```

| 维度 | 模式 A（直连） | 模式 B / C（Dex） |
|---|---|---|
| 额外组件 | 无 | `argocd-dex-server`（有状态） |
| 登录回调地址 | `https://argocd.example.com/auth/callback` | `https://argocd.example.com/api/dex/callback` |
| 组刷新时机 | 每次登录 + **Token 刷新时**（`refreshTokenThreshold` 会换新 ID Token） | **只在认证时**（Dex 不会回头查上游） |
| `refreshTokenThreshold` | ✅ 生效 | ❌ 不生效（Dex 的 Token 过期即需重登） |
| 能否拿 UserInfo 里的组 | ✅ `enableUserInfoGroups` | ✅ `getUserInfo` |
| 多 IdP / 多连接器 | ❌（一个 `oidc.config` 一个 issuer） | ✅ |
| CI 令牌交换（RFC 8693） | ❌ | ✅ |
| HA 约束 | 无 | Dex 必须 1 副本（内存存储） |
| 出问题时怀疑对象 | `oidc.config` + IdP | `oidc.config` + `dex.config` + Dex 存储 + IdP |

---

## 2. 四个必须分开的动作

初学者最容易把下面四件事当成一件，从而出现"配置都写了但进不去"的局面。

| # | 动作 | 配置位置 | 作用 |
|---|---|---|---|
| **①** | **打通登录链路** | `argocd-cm` 的 `oidc.config`（模式 A）或 `dex.config`（模式 B/C） | 让用户能用公司账号登录 |
| **②** | **让组出现在 token 里** | 模式 A：IdP 侧配置 + `requestedIDTokenClaims` / `enableUserInfoGroups`；模式 B（Dex+OIDC）：connector 里的 `insecureEnableGroups` + `scopes`；模式 C（Dex+LDAP）：配好 `groupSearch` | 让 token 带上 `groups` |
| **③** | **把组映射成角色** | `argocd-rbac-cm` 的 `policy.csv`（+ `scopes`） | 让 `platform-admins` 组 → `role:admin` |
| **④** | **禁用内置 admin** | `argocd-cm` 的 `admin.enabled: "false"` | 让 `admin` 本地账号**不能登录** |

**只做 ①** → 能登录，但没有任何组权限（大概率只看到空列表）。
**只做 ②③ 不做 ④** → 能用，但 `admin` 账号仍可登录（安全隐患）。
**正确顺序：做 ① → 做 ②③ → 用外部账号验证 → 最后做 ④。**

---

## 3. 模式 A：OIDC 直连（企业主流形态）

> 适用：公司已有 OIDC IdP，员工用个人账号走 SSO。

### 3.1 IdP 侧要准备什么

| # | 项目 | 说明 | 常见坑 |
|---|---|---|---|
| 1 | **应用注册** | 在 IdP 里注册一个"OIDC 应用 / App Registration / Client" | — |
| 2 | **clientID** | 放进 `argocd-cm` | — |
| 3 | **clientSecret** | 放 `argocd-secret`，**不要**明文写进 ConfigMap | 明文进 Git = 事故 |
| 4 | **Redirect URI（Web）** | `https://argocd.example.com/auth/callback` | ❗不是 `/api/dex/callback`（那是 Dex 模式） |
| 5 | **Redirect URI（CLI）** | `http://localhost:8085/auth/callback`；或改用 device code（§3.8） | 漏配 → CLI `argocd login --sso` 失败 |
| 6 | **组 claim 能力** | 确认组放在 `groups` claim 里；Entra 还要去 Token Configuration 点 "Add groups claim" | 没开 → token 里没有组 |
| 7 | **证书信任** | 公有 CA 直接用；自签/私有 CA → `oidc.config` 里放 `rootCA` | — |
| 8 | **授权范围** | 把 Argo CD 应用分配给对应用户/组（Entra："Users and groups"） | 没分配 → 登录后无权限甚至被 IdP 拒 |

Secret 放法（**官方推荐**，避免明文进 Git）：

```bash
kubectl -n argocd patch secret argocd-secret \
  --patch='{"stringData": {"oidc.okta.clientSecret": "[REDACTED]"}}'
```

然后在 `oidc.config` 里写 `clientSecret: $oidc.okta.clientSecret`。
引用规则（上游 `replaceStringSecret`）：

| 写法 | 含义 |
|---|---|
| `$oidc.okta.clientSecret` | 取 `argocd-secret` 里的同名 key |
| `$my-secret:clientSecret` | 取指定 Secret 的指定 key（该 Secret 需要带 `app.kubernetes.io/part-of: argocd` 标签） |

### 3.2 `argocd-cm` 配置：最小可用版

> 完整可复制版本见 [`examples/oidc-direct-config.yaml`](./examples/oidc-direct-config.yaml)。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
    app.kubernetes.io/name: argocd-cm
data:
  # Argo CD 的外部访问地址（回调地址由它推导）
  url: https://argocd.example.com

  oidc.config: |
    name: Okta
    issuer: https://your-org.okta.com/oauth2/default
    clientID: aaaabbbbccccddddeee
    clientSecret: $oidc.okta.clientSecret
```

就这四行就能登进去。**但只有 email，没有组** → 所有人都只能拿到默认策略的权限。

### 3.3 `argocd-cm` 配置：生产推荐版

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
    app.kubernetes.io/name: argocd-cm
data:
  url: https://argocd.example.com

  oidc.config: |
    name: Okta
    issuer: https://your-org.okta.com/oauth2/default
    clientID: aaaabbbbccccddddeee
    clientSecret: $oidc.okta.clientSecret

    # ---- 请求哪些 scope ----
    # 上游默认就是 ["openid","profile","email","groups"]，写出来是为了让 reviewer 看得见
    requestedScopes: ["openid", "profile", "email", "groups"]

    # ---- 请求 ID Token 里的额外 claim（部分 IdP 需要显式声明）----
    requestedIDTokenClaims:
      groups:
        essential: true
        # value: platform-admins      # 可选：只接受某个组（IdP 支持时）

    # ---- 私有 CA（自签证书的 IdP 必填）----
    # rootCA: |
    #   -----BEGIN CERTIFICATE-----
    #   ...
    #   -----END CERTIFICATE-----

    # ---- PKCE：防止授权码被截获，IdP 支持就开 ----
    enablePKCEAuthentication: true

    # ---- Token 提前刷新：让会话不中断，同时让"组"跟着刷新 ----
    # 必须 < IdP 的 ID Token 有效期，否则每次请求都要重新签发
    refreshTokenThreshold: 5m

    # ---- 登出时顺带结束 IdP 的 SSO 会话 ----
    # logoutURL: https://your-org.okta.com/oauth2/default/logout?id_token_hint={{token}}

  # ---- 可选：不用内置 Dex 的时候关掉它（减少一个有状态组件 + 攻击面）----
  # （Helm：dex.enabled=false；原生安装：把 argocd-dex-server 缩容到 0）
```

> ⚠️ `refreshTokenThreshold` 与 IdP 的 Token 有效期要配套。
> Keycloak 默认 access token 只有 5 分钟 → 阈值设 5m 会导致**每次请求都重新签发**，
> 上游明确提示这时应设成比 Token 生命周期**短**（比如 `1m`）。

### 3.4 `oidc.config` 字段全表

> 依据：上游 `util/settings/settings.go` 的 `OIDCConfig` / `oidcConfig` 结构体 + 上游用户管理文档。

| 字段 | 默认值 | 说明 |
|---|---|---|
| `name` | — | IdP 显示名（登录页上显示） |
| `issuer` | — | **必填**。IdP 的 issuer URL，必须能取到 `/.well-known/openid-configuration` |
| `clientID` | — | **必填**。OIDC 客户端 ID |
| `clientSecret` | — | 客户端密钥。写成 `$oidc.xxx.clientSecret` 引用 Secret |
| `cliClientID` | 同 `clientID` | CLI 用**另一个** clientID 时才填（部分 IdP 要求分开注册） |
| `requestedScopes` | `["openid","profile","email","groups"]` | 向 IdP 请求的 OAuth scope |
| `requestedIDTokenClaims` | — | 用 OIDC Claims Parameter 请求 ID Token 里的额外 claim，如 `groups` |
| `enableUserInfoGroups` | `false` | 从 UserInfo 端点取组（IdP 不把组放 ID Token 时用） |
| `userInfoBaseURL` | — | UserInfo 端点所在站点（不含路径） |
| `userInfoPath` | — | UserInfo 路径，如 `/userinfo` |
| `userInfoCacheExpiration` | 跟随 ID Token 有效期 | 组缓存时长。**不设 = 缓存到 Token 过期**，改组不会立刻生效 |
| `logoutURL` | — | 登出跳转地址。`{{token}}` / `{{logoutRedirectURL}}` 是 Argo CD 注入的占位符 |
| `rootCA` | — | 自签 CA 的 PEM 内容（多行） |
| `enablePKCEAuthentication` | `false` | 开启 PKCE（IdP 与客户端都要支持） |
| `refreshTokenThreshold` | `0s` | 提前多久刷新 ID Token（必须小于 Token 有效期） |
| `allowedAudiences` | `[clientID]` | 允许的 aud 列表。**一旦显式设置，就必须把 `clientID` 自己写进去** |
| `skipAudienceCheckWhenTokenHasNoAudience` | `< 2.6.0` 为 `true`；`>= 2.6.0` 为 `false` | 无 aud 的 token 是否放行 |
| `domainHint` | — | 传给 IdP 的登录域提示（多租户 IdP 有用） |
| `deviceURL` / `tokenURL` | 从 discovery 自动发现 | IdP 不在 discovery 里声明 device 端点时手动指定 |
| `azure.enableUserGroupOverageClaim` | `false` | Entra ID 用户组 > 200 时的溢出解析（§3.5） |
| `azure.graphApiEndpoint` | `https://graph.microsoft.com/v1.0` | 主权云改这里（如 `https://graph.microsoft.us/v1.0`） |
| `azure.useWorkloadIdentity` | `false` | 用 AKS 工作负载身份代替 client secret |
| `azure.userGroupOverageClaimCacheExpiration` | 跟随 Token 有效期 | 溢出组缓存时长 |

### 3.5 组 claim 的三条来源路径（选一条）

```
                    ┌─ ① ID Token 的 groups claim ────────┐
IdP  ─── token ───▶┤  ② UserInfo 端点的 groups ─────────┼─▶ token.claims["groups"]
                    └─ ③ Microsoft Graph（组溢出）────────┘
```

| 路径 | 什么时候用 | 怎么配 | 坑 |
|---|---|---|---|
| **① ID Token** | IdP 默认就返回组（Okta / Entra ID / Keycloak / Auth0） | `requestedScopes` 含 `groups`；部分 IdP 还要 `requestedIDTokenClaims: {groups: {essential: true}}` | Okta 即使请求了也常常只在 UserInfo 返回 |
| **② UserInfo** | IdP 不肯把组放进 ID Token | `enableUserInfoGroups: true` + `userInfoBaseURL` + `userInfoPath` + `userInfoCacheExpiration` | **不设缓存过期 = 组缓存到 Token 过期**，改组不生效 |
| **③ Graph API** | Entra ID 用户组数 > 200（`groups` 被换成 `_claim_names` 溢出标记） | `azure.enableUserGroupOverageClaim: true`（需 `User.Read` 委托权限） | Graph 不可达 → 这批用户**直接登不进来**（401） |

### 3.6 各 IdP 的差异速查表

| IdP | `issuer` 示例 | 组在哪 | 组名形态 | 必做事项 |
|---|---|---|---|---|
| **Okta** | `https://your-org.okta.com/oauth2/default` | `groups`（常在 UserInfo） | Okta 组名（如 `platform-admins`） | 请求 `groups` scope；必要时开 `enableUserInfoGroups` |
| **Microsoft Entra ID** | `https://login.microsoftonline.com/{tenant}/v2.0` | `groups`（**GUID**） | 组对象 ID | Token Configuration 点 **Add groups claim**；组数 > 200 开 `azure.enableUserGroupOverageClaim`；secret 用 Workload Identity 更好 |
| **Keycloak** | `https://kc.example.com/realms/{realm}` | `groups` | **完整路径**（如 `/platform/admin`） | realm 路径别错（<17 版本还要带 `/auth`）；组名要写全路径；CLI 需开 device code grant |
| **Auth0** | `https://tenant.auth0.com/` | `groups` | Auth0 组名 | 在 Auth0 给应用加 `groups` scope，并在 Action 里加 groups claim |
| **Google Workspace** | `https://accounts.google.com` | ❌ 不返回 | — | Google **没有** groups claim → 要用组只能用 Dex 的 `type: google` connector（需 adminEmail 授权），或改用 email 做主体 |

### 3.7 RBAC 主体语义（模式 A 最容易错的地方）

模式 A 下，token 里同时有好几种"可以当主体"的东西，用错一个就"配了规则没反应"。

| 想授权的对象 | token 里的来源 | 需要在 `argocd-rbac-cm` 的 `scopes` 里写吗 | `policy.csv` 写法 | 可读性 |
|---|---|---|---|---|
| **用户**（ID Token 的 `sub`） | `sub` claim | ❌ 不需要（`sub` 永远参与匹配） | `g, 00u1abc..., role:admin` | ❌ Opta 不透明 ID / Entra GUID，**不要用** |
| **用户邮箱** | `email` claim | ✅ 需要 `email` | `g, alice@corp.example.com, role:admin` | ✅ 推荐用于个别授权 |
| **组** | `groups` claim | ✅ 需要 `groups` | `g, platform-admins, role:admin` | ✅ **推荐主路径** |

⚠️ 模式 A 下 `sub` 是 IdP 的**内部标识**（Okta 是 `00u...`，Entra 是成对 GUID），
**不是邮箱**。所以"按邮箱授权"必须靠 `scopes: '[groups, email]'` 把 `email` claim
也纳入候选主体，光写 `g, alice@corp.com, ...` 而 `scopes` 里没有 `email` 是无效的。

### 3.8 会话、刷新、登出、吊销

| 机制 | 模式 A（直连） | 模式 B/C（Dex） |
|---|---|---|
| ID Token 过期 | 按 IdP 的 Token 有效期 | 按 Dex 发出的 Token 有效期 |
| `refreshTokenThreshold` | ✅ **生效**：提前用 refresh token 换新 ID Token（新 token 带**新的组**） | ❌ 不生效（Dex 的组只在认证时取） |
| `logoutURL` | ✅ 可配，登出时同时结束 IdP 会话 | 配在 `dex.config` 的 connector 上 |
| 服务端吊销 | ✅ 登出把 token 加入 Redis 吊销列表（多副本通过 Redis pub/sub 广播） | 同左 |
| 降权生效时间 | 下次登录 / 下次刷新 | **下次登录**（旧 token 有效期内仍带旧组） |

> 上游补充：吊销列表靠 Redis pub/sub 实时广播，另外每个副本会定期全量重载一次，
> 周期由 `ARGOCD_SESSION_REVOKED_TOKEN_RESYNC_DURATION` 控制（默认 `5m`）。

### 3.9 CLI 登录

```bash
# 浏览器模式（本地有浏览器）
argocd login argocd.example.com --sso

# 无浏览器模式（远程开发机 / 容器 / 云 IDE）→ device code 流程
argocd login argocd.example.com --sso --no-browser
# 输出：https://argocd.example.com/api/dex/device?user_code=ABCD-1234
# 在任意机器的浏览器里打开即可
```

device code 要求 IdP 支持 `urn:ietf:params:oauth:grant-type:device_code`
并在 discovery 里声明 `device_authorization_endpoint`（Okta / Entra / Keycloak / Google 都支持）。
Keycloak 需要额外给客户端开 device code grant。

### 3.10 顺手关掉内置 Dex（可选但推荐）

模式 A 下 `argocd-dex-server` 没有任何用途，留着只是多一个对外暴露的 Pod：

```yaml
# Helm
dex:
  enabled: false
```

```bash
# 原生安装
kubectl -n argocd scale deploy/argocd-dex-server --replicas=0
```

> 关掉后 `argocd login --sso` 的 device code 页面地址仍会显示 `/api/dex/device`，
> 那是 Argo CD 自己的路由外壳，**不代表 Dex 还在跑**。

---

## 4. 模式 B：Dex + OIDC

> 适用：IdP 是 OIDC，但组只在 UserInfo 里 / 要接多个 IdP / 要给 CI 做令牌交换。

### 4.1 什么时候真的需要 Dex

| 需求 | 模式 A 能做吗 | Dex 的增量价值 |
|---|---|---|
| 组在 ID Token 里 | ✅ | — |
| 组只在 UserInfo 端点 | ✅（`enableUserInfoGroups`） | — |
| 同时接 Okta + GitHub 两套账号 | ❌（一个 issuer） | ✅ 多 connector，登录页可选 |
| CI 用 OIDC Token 换 Argo CD Token（RFC 8693） | ❌ | ✅ `urn:ietf:params:oauth:grant-type:token-exchange` |
| IdP 是 SAML / LDAP | ❌ | ✅ 这是 Dex 的主业 |

### 4.2 配置

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.example.com

  dex.config: |
    connectors:
    - type: oidc
      id: okta
      name: Okta
      config:
        issuer: https://your-org.okta.com/oauth2/default
        clientID: aaaabbbbccccddddeee
        clientSecret: $dex.okta.clientSecret
        # 下面三个都是 **connector 级** 字段（Dex + OIDC 必填）
        insecureEnableGroups: true
        scopes: [openid, profile, email, groups]
        # 组不在 ID Token 里（只在 UserInfo 端点）时才需要开
        getUserInfo: true
```

> Dex 模式下 **IdP 侧的回调地址是 `https://argocd.example.com/api/dex/callback`**，
> 不是 `/auth/callback`。这是模式 A / B 最容易搞混的一个参数。

### 4.3 Dex 侧的组开关（都是 **connector 级**字段）

| 开关 | 写在哪个 connector 上 | 作用 | 不开的症状 |
|---|---|---|---|
| `insecureEnableGroups: true` | **OIDC connector** 的 `config` 里 | 允许 Dex 把上游 IdP 返回的组放进 ID Token | token 里没有 `groups` |
| `scopes: [openid, profile, email, groups]` | **OIDC connector** 的 `config` 里 | 向**上游 IdP** 请求组 | 上游不返回组 |
| `getUserInfo: true` | **OIDC connector** 的 `config` 里 | 组不在 ID Token 里时去上游 UserInfo 端点取 | 同上 |

> ⚠️ **这三个都是 connector 内部的字段**，必须写在 `config:` 下面，
> 写在 `dex.config` 顶层是无效的（Dex 会忽略未知字段）。
>
> ⚠️ 另外：**LDAP connector 没有这三个开关**（见 §5.1.1）。

### 4.4 多连接器：强制跳某一个

Dex 登录页会把所有 connector 列出来。CI 用的 connector 对人没意义，
可以在 `argocd-cm` 里指定默认跳哪个：

```yaml
data:
  dex.auth.connectorId: okta
```

### 4.5 CI 令牌交换（可选）

需要在 CI 里用"CI 平台自己的 OIDC 身份"换 Argo CD Token 时（无浏览器场景）：

```yaml
  dex.config: |
    oauth2:
      grantTypes:
        - authorization_code
        - refresh_token
        - urn:ietf:params:oauth:grant-type:token-exchange
    connectors:
    - type: oidc
      id: github-actions
      name: GitHub Actions
      config:
        issuer: https://token.actions.githubusercontent.com
        scopes: [openid]
        userNameKey: sub
        insecureSkipEmailVerified: true
        claimMapping:
          email: sub
```

> ⚠️ `insecureSkipEmailVerified: true` 会**对整个 connector 的所有身份**跳过邮箱校验，
> CI 的 connector 必须和人类用户的 connector 分开建。

---

## 5. 模式 C：Dex + LDAP

> 适用：公司只有 LDAP / AD。

### 5.1 完整配置

完整可复制版本见 [`examples/dex-ldap-config.yaml`](./examples/dex-ldap-config.yaml)。
核心结构：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.example.com

  dex.config: |
    connectors:
    - type: ldap
      id: ldap
      name: Corporate LDAP
      config:
        host: ldap.corp.example.com:636
        insecureNoSSL: false
        insecureSkipVerify: false
        startTLS: false
        rootCA: /etc/dex/ldap.ca
        bindDN: cn=svc-argocd,ou=services,dc=corp,dc=example,dc=com
        bindPW: $dex.ldap.bindPW
        usernamePrompt: Email Address
        userSearch:
          baseDN: ou=people,dc=corp,dc=example,dc=com
          filter: "(objectClass=person)"
          username: mail
          idAttr: uid
          emailAttr: mail
          nameAttr: cn
          preferredUsernameAttr: uid
        groupSearch:
          baseDN: ou=groups,dc=corp,dc=example,dc=com
          filter: "(objectClass=groupOfNames)"
          userMatchers:
          - userAttr: dn
            groupAttr: member
          nameAttr: cn

    # ------------------------------------------------------------------
    # 组怎么进 token（Dex + LDAP）：**不需要任何开关**。
    #
    # · Argo CD 向 Dex 请求的 scope 固定包含 groups
    #   （上游 util/oidc/oidc.go → getScopes() → openid, profile, email, groups）
    # · Dex 的 LDAP connector 只要配了 groupSearch，就会把组写进 ID Token
    #
    # ⚠️ 网上常见的「dex.config 顶层写 insecureEnableGroups: true / scopes: [...]」
    #    不是 Dex 的配置字段 → 会被 Dex 忽略（只有 Dex 的 **OIDC connector** 里
    #    这两个才是真字段，见 §4.3）。真正决定成败的是上面的 groupSearch。
    # ------------------------------------------------------------------
```

### 5.1.1 三个"组开关"到底谁管用（常见误传澄清）

| 写法 | Dex 认不认 | 后果 |
|---|---|---|
| `dex.config` 顶层 `insecureEnableGroups: true` | ❌ 不是 Dex 的顶层字段 | 被忽略；Dex 开了严格模式还会直接启动失败 |
| `dex.config` 顶层 `scopes: [profile, email, groups]` | ❌ 不是 Dex 的顶层字段 | 被忽略 |
| connector 的 `config` 里 `scopes` / `insecureEnableGroups` / `getUserInfo` | ✅（**仅 OIDC connector**） | Dex + OIDC 时必填 |
| **只配 `groupSearch`**（LDAP connector） | ✅ | 组就会进 token（Argo CD 已经请求了 groups scope） |

> 源码依据：
> · Argo CD 侧：`util/oidc/oidc.go` → `getScopes()` → Dex 分支固定用
>   `openid, profile, email, groups` + `federated:id`。
> · Dex 侧：`connector/ldap/ldap.go` → `if s.Groups { ident.Groups = groups }`；
>   `connector/oidc/oidc.go` → `if c.insecureEnableGroups { ... }`（只有 OIDC connector 有）。

### 5.2 Dex LDAP connector 字段说明（据 Dex 上游 LDAP 文档）

| 字段 | 必需 | 说明 |
|---|---|---|
| `host` | ✅ | `host:port`。不写端口时按 `insecureNoSSL` / `startTLS` 推断：389 或 636 |
| `insecureNoSSL` | | 纯明文连接（389）。**会泄露密码**，未来版本可能移除，不建议用 |
| `insecureSkipVerify` | | 跳过 TLS 证书校验。**仅限探索期** |
| `startTLS` | | 先用 `ldap://` 连再 `StartTLS`；不设则用 `ldaps://` |
| `rootCA` | | CA 证书路径 |
| `rootCAData` | | CA 证书内容（base64 PEM） |
| `bindDN` | | 服务账号 DN。LDAP 允许匿名搜索时可不填 |
| `bindPW` | | 服务账号密码。**含 `$` 时必须放环境变量**（见 §5.4） |
| `usernamePrompt` | | 登录框提示文字 |
| `userSearch.baseDN` | ✅ | 用户搜索根 DN |
| `userSearch.filter` | | 附加过滤条件，如 `(objectClass=person)` |
| `userSearch.username` | ✅ | 用户名匹配属性 |
| `userSearch.idAttr` | ✅ | 用户唯一标识属性。Dex 的 `sub` 由它 + connector id 编码而成（base64 JSON），**不是可读字符串** |
| `userSearch.emailAttr` | | 映射到 Email 的属性。**映射不到就没有 email claim** |
| `userSearch.nameAttr` | | 显示名属性 |
| `userSearch.preferredUsernameAttr` | | 登录名属性 |
| `groupSearch.baseDN` | ✅ | 组搜索根 DN |
| `groupSearch.filter` | | 组对象过滤 |
| `groupSearch.userMatchers[].userAttr` | ✅ | 组里存的是哪种用户标识 |
| `groupSearch.userMatchers[].groupAttr` | ✅ | 组对象里存成员的属性名 |
| `groupSearch.nameAttr` | ✅ | 组名属性 → **这个值就是 Argo CD 里看到的组名** |
| `groupSearch.recursionGroupAttr` | | 递归查找嵌套组 |

### 5.3 `userMatchers` 怎么配（最容易错的地方）

Dex 是用**同一个属性**去匹配"用户"和"组成员"的，两边必须对得上。

| LDAP 组对象里的成员属性 | `userAttr` 应该填 | `groupAttr` |
|---|---|---|
| `member` 存完整 DN | `DN` | `member` |
| `memberUid` 存 uid | `uid` | `memberUid` |
| `uniqueMember` 存完整 DN | `DN` | `uniqueMember` |

**常见错误**：用户属性用 `uid`，但组里存的是 DN →
`userAttr: uid` / `groupAttr: member` 匹配不上 → **组永远查不到**。

上游文档特别提示：

> Use "DN" here not "uid"

**验证办法**（在能访问 LDAP 的机器上）：

```bash
# 以服务账号身份查用户
ldapsearch -x -H ldap://ldap.corp.example.com \
  -D "cn=svc-argocd,ou=services,dc=corp,dc=example,dc=com" -W \
  -b "ou=people,dc=corp,dc=example,dc=com" \
  "(objectClass=person)" dn mail uid

# 以服务账号身份查组（把 <user-dn> 换成上面查到的真实 DN）
ldapsearch -x -H ldap://ldap.corp.example.com \
  -D "cn=svc-argocd,ou=services,dc=corp,dc=example,dc=com" -W \
  -b "ou=groups,dc=corp,dc=example,dc=com" \
  "(&(objectClass=groupOfNames)(member=<user-dn>))" dn cn
```

**两条都能查到，才说明 Dex 的配置是对的。**

### 5.4 密码含 `$` 的处理

Dex 上游明确说明：如果 bind 密码含 `$`，必须用环境变量，
且**不能放在 `argocd-cm` 的 `dex.config` 明文里**。

标准做法（Secret + 环境变量引用）：

```yaml
# ① 放到 Secret
apiVersion: v1
kind: Secret
metadata:
  name: argocd-dex-ldap
  namespace: argocd
type: Opaque
stringData:
  bindPW: "实际的 LDAP 绑定密码"
```

然后在 `argocd-cm` 的 `dex.config` 里写：

```yaml
        bindPW: $dex.ldap.bindPW
```

并在 `argocd-dex-server` Deployment 的 `env` 里加：

```yaml
        - name: dex.ldap.bindPW
          valueFrom:
            secretKeyRef:
              name: argocd-dex-ldap
              key: bindPW
```

> ⚠️ **本文档不包含任何真实凭据**。所有密码、令牌、私钥一律 `[REDACTED]`。
> 生成的 YAML 里请用你自己的 Secret 引用，不要把明文提交进 Git。

### 5.5 Dex 模式下组只在认证时刷新

**上游明确说明：组成员信息只在用户认证（登录）时刷新。**

| 场景 | 结果 |
|---|---|
| 员工加入 `devops-admin` 组 | **下次登录**才生效 |
| 员工被移出 `devops-admin` 组 | **下次登录**才失效 ⚠️ |
| 已登录用户被降权 | 旧 Token 仍带旧组，权限未回收 ⚠️ |
| 修改 LDAP 组定义 | 同上，需重新登录 |

**缓解措施**：缩短 ID Token 有效期 / 开启 Token 吊销 / **定期复核组成员**（唯一可靠解法）。

> 对比：模式 A（OIDC 直连）因为 `refreshTokenThreshold` 会换新 ID Token，
> 组会随刷新一起更新，窗口小得多（见 §3.8）。

---

## 6. RBAC：把组映射成角色（三种模式通用）

配置在 **`argocd-rbac-cm`**（不是 `argocd-cm`）：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    # 平台管理员组 → 全局管理员
    g, my-org:platform-admins, role:admin

    # 只读组
    g, my-org:platform-readonly, role:authenticated

    # 开发组：可同步指定项目
    p, my-org:platform-dev, applications, sync, dev/*, allow
    g, my-org:platform-dev, role:authenticated

  policy.default: role:authenticated
  scopes: '[groups, email]'
```

完整示例见 [`examples/argocd-rbac-cm.yaml`](./examples/argocd-rbac-cm.yaml)。

### 6.1 `policy.csv` 语法（上游 RBAC 文档）

```
p, subject, resource, action, object, effect
g, subject, inherited-subject
```

| 字段 | 取值 |
|---|---|
| `resource` | `applications`、`applicationsets`、`projects`、`repositories`、`write-repositories`、`clusters`、`logs`、`exec`、`accounts`、`certificates`、`gpgkeys` |
| `action` | `get`、`create`、`update`、`delete`、`sync`、`rollback`、`action`、`override`、`invoke`、`*` |
| `object` | `*`、`<project>/*`、`<project>/<app>`、`<app>` |
| `effect` | `allow` / `deny` |

**内置角色**：`role:readonly`（只读全部）、`role:admin`（无限制）。

> 上游注意：**组必须先被赋予角色**（`g, <组>, <角色>`），
> 直接写 `p, <组>, applications, ...` 是**不生效**的。

### 6.2 `scopes` 的真实语义（最容易误解的字段）

上游原文：

> The `scopes` field controls which OIDC scopes to examine during RBAC enforcement
> (in addition to `sub` scope). If omitted, it defaults to `'[groups]'`.

**注意这里的措辞陷阱**：这个字段里的名字被当作 **token 里的 claim 名**去取值
（源码 `jwtutil.GetScopeValues(claims, scopes)`），**不是** OAuth 的 scope。

| `scopes` 里写了 | Argo CD 会去 token 里取 | 得到的候选主体 |
|---|---|---|
| `groups` | `claims["groups"]`（数组） | 每个组名 |
| `email` | `claims["email"]`（字符串） | 该邮箱 |
| `roles` | `claims["roles"]` | 每个角色名（有些 IdP 用这个 claim 装组） |
| `sub` | 永远参与匹配，不用写 | 用户主体 |

> **关键**：如果 `scopes` 里没有 `groups`，`g, platform-admins, role:admin`
> 这条规则**永远不会生效**——即使 IdP 已经把组正确放进了 Token。

### 6.3 `policy.default` 的安全陷阱

上游明确说明：

> When a user is authenticated in Argo CD, it will be granted the role specified in `policy.default`.

**并且：默认权限无法被 `deny` 规则阻止。**

这意味着 `policy.default: role:readonly` 会让**所有已认证用户**
（包括任意一个能通过 IdP 认证的人）都能读所有 Application。

**推荐做法**：自己定义一个最小权限角色作为默认。

```yaml
data:
  policy.csv: |
    p, role:authenticated, applications, get, *, allow
    p, role:authenticated, projects, get, *, allow
    p, role:authenticated, repositories, get, *, allow
    p, role:authenticated, clusters, get, *, allow
    g, role:authenticated, role:readonly    # 角色继承（上游支持）
    g, my-org:platform-admins, role:admin
  policy.default: role:authenticated
```

> 注意 `g, role:authenticated, role:readonly` 这种**角色继承**是上游文档支持的语法。
> 但如果你想让 `role:authenticated` 严格最小，就不要继承 `role:readonly`，
> 直接写上面那四条 `p` 规则。

### 6.4 组名规范

* **组名大小写敏感**，必须和 token 里的值**完全一致**（Keycloak 是 `/platform/admin` 这种完整路径）。
* 建议加前缀（`my-org:platform-admins` 而不是 `admins`），避免和别的 claim 值撞名。
  前提是**IdP 里的组名也按同样的规范建**——前缀只是命名约定，最终仍以 token 里的值为准。
* Entra ID 只能拿到**组 GUID**（除非走 Graph），建议在 IdP 侧用"组名"字段做映射，或在
  `policy.csv` 里直接写 GUID（上游 Entra 文档就是这么示例的）。

### 6.5 项目级角色

组也可以直接授权到 AppProject（细节见 [`04-appproject-rbac.md`](./04-appproject-rbac.md)）：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-beta-project
  namespace: argocd
spec:
  roles:
    - name: admin
      description: Admin privileges to team-beta
      policies:
        - p, proj:team-beta-project:admin, applications, *, team-beta-project/*, allow
      groups:
        - user@example.org         # email claim 的值
        - my-org:platform-admins   # groups claim 的值
```

---

## 7. 禁用内置 admin

上游 `docs/operator-manual/user-management/index.md` 的写法：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  admin.enabled: "false"
```

**注意事项：**

- 值必须是**字符串** `"false"`，不是布尔 `false`（ConfigMap 的 value 必须是字符串）
- 这**只**禁用内置 `admin` 账号的登录，**不会**自动把管理员权限给任何人
- 禁用后，`argocd` 本地账号（`argocd admin account bcrypt` 改的那个）**也不能登录**
- 上游建议：**创建了其他账号之后**就禁用 admin

### break-glass 方案

**禁用 admin 前必须准备**，否则一旦 RBAC 配错就完全锁死。

方案一：**本地账号**（不依赖 IdP，IdP 挂了也能进）

```bash
# 1) 先在 argocd-cm 里声明账号能力：accounts.<name>: login,apiKey
# 2) 生成 bcrypt hash（或用 CLI 改密码）
argocd account bcrypt --password        # 打印 hash，放进 argocd-secret
argocd account update-password --account break-glass \
  --current-password '<当前密码>' --new-password '<新密码>'
```

对应 `argocd-cm`：

```yaml
data:
  accounts.break-glass: login
```
对应 `argocd-secret`：

```yaml
stringData:
  accounts.break-glass.password: $2a$10$...   # bcrypt hash
```

⚠️ 内置 `admin` 的初始密码是**安装时随机生成**的（记在 `argocd-secret` 和
`argocd-server` Pod 日志里），不是固定字符串；本地账号的 hash 也必须自己设。
⚠️ 本地账号密码不经过 IdP 的 MFA / 离职回收流程 → **必须有审计**，
或者平时禁用（`accounts.break-glass.enabled: "false"`）、紧急时通过修改 `argocd-cm` 临时开启。

方案二：**预留一条只匹配特定 OIDC subject 的规则**

```yaml
  policy.csv: |
    g, my-org:platform-admins, role:admin
    p, break-glass@corp.example.com, applications, *, *, allow
    g, break-glass@corp.example.com, role:admin
```

⚠️ 注意：模式 A 下这个 subject 要么是 email claim（需 `scopes` 含 `email`），
要么是 `sub`（不透明 ID，不可用）。所以**方案二在模式 A 下要配合 `scopes: '[groups, email]'`**。

方案三：**kubectl 直通**（集群 admin 权限）——写进 runbook：

```bash
kubectl -n argocd patch cm argocd-cm --type='merge' \
  -p '{"data":{"admin.enabled":"true"}}'
# 恢复后改回来
kubectl -n argocd patch cm argocd-cm --type='merge' \
  -p '{"data":{"admin.enabled":"false"}}'
```

> ⚠️ 应急账号方案要评估审计要求——很多组织不允许长期存在的后门账号。
> 折中做法：平时禁用，紧急时通过修改 `argocd-cm` 临时开启。

---

## 8. 会话与 Token 行为

### 8.1 Dex 的存储后端（Dex 模式才需要）

Dex 默认用**内存**存储，Pod 重启后所有登录态丢失。
持久化后端有三种：

| 后端 | 说明 |
|---|---|
| Kubernetes CRD（`AuthCodes` / `RefreshTokens` / `SigningKeys`） | Argo CD 常用方式 |
| SQL（SQLite / Postgres / MySQL） | 外部数据库 |
| 文件（仅单机） | 不适合生产 |

用 Kubernetes 后端时，**Argo CD 内置的 Dex ServiceAccount 需要额外 RBAC**，
才能操作 Dex 的 CR、ConfigMap 和 Secret：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-dex-server
rules:
# Dex CRD 后端
- apiGroups: ["argoproj.io"]
  resources: ["authcodes", "refreshtokens", "signingkeys"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
# Dex 的 ConfigMap / Secret
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
```

> 上游用户管理文档明确指出：**修改 Dex 后端配置后需要重启 Dex Pod** 才生效。

### 8.2 Token 吊销（两种模式都支持）

上游 "Token Revocation and Session Management" 章节：

1. 用户登出（UI 或 `argocd logout`）→ token 加入 Redis 吊销列表 + 本地移除
2. 若配了 `logoutURL` → 跳转到 IdP 结束 SSO 会话
3. 被吊销的 token 即使没过期也不能再调 API

Server 不可达时 `argocd logout` 会降级：本地登出成功，但服务端吊销要等 token 自然过期。

结合"组只在登录时刷新"的特性（§5.5）：

* 紧急踢人 → 用 Argo CD 的 token 吊销功能（主动）
* 常规降权 → 依赖 Token 自然过期（被动）或缩短有效期

### 8.3 登录失败限流（上游自带）

| 环境变量 | 默认 | 作用 |
|---|---|---|
| `ARGOCD_SESSION_FAILURE_MAX_FAIL_COUNT` | 5 | 连续失败多少次后开始拒绝 |
| `ARGOCD_SESSION_FAILURE_WINDOW_SECONDS` | 300（5 分钟） | 失败计数窗口 |
| `ARGOCD_SESSION_MAX_CACHE_SIZE` | 1000 | 失败记录缓存条数 |
| `ARGOCD_MAX_CONCURRENT_LOGIN_REQUESTS_COUNT` | 50 | 并发登录请求上限（HA 下注意） |

---

## 9. 实施顺序（防锁死）

### 9.1 模式 A（OIDC 直连）

```
步骤 1  IdP 侧注册应用，拿到 clientID / clientSecret
        ↓ 配好 Redirect URI：/auth/callback（+ CLI 的 localhost:8085/auth/callback）
步骤 2  argocd-secret 写入 oidc.<name>.clientSecret
        ↓ kubectl -n argocd patch secret argocd-secret --patch=...
步骤 3  argocd-cm 写 url + oidc.config（先最小版：issuer/clientID/clientSecret）
        ↓ kubectl apply
步骤 4  【关键验证】用真实账号登录，确认：
        · 能登录（本地账号仍开着，此时 admin 还能用）
        · 浏览器 F12 → id_token → payload 里能看到 groups / email
        · argocd account get-user-info 能看到 Username 和 Groups
步骤 5  确认组名和 policy.csv 里写的**完全一致**（大小写、路径）
步骤 6  配置 argocd-rbac-cm：policy.csv + scopes + policy.default
        ↓ kubectl apply（RBAC 热加载，一般无需重启）
步骤 7  【再次验证】用组内账号登录 → 权限正确；用组外账号登录 → 只有默认权限
步骤 8  准备 break-glass（§7），演练一次"改回来"的 kubectl 命令
步骤 9  设置 admin.enabled: "false"
        ↓ kubectl apply
步骤 10 验证 admin 账号确实无法登录，外部账号仍正常
步骤 11 （可选）关掉 argocd-dex-server
```

### 9.2 模式 B / C（Dex）

```
步骤 1  配置 dex.config
        （模式 B：Dex+OIDC → connector 里加 insecureEnableGroups + scopes + getUserInfo；
          模式 C：Dex+LDAP → 配好 groupSearch 即可）
        ↓ kubectl apply
步骤 2  重启 dex-server，确认 Dex 健康
        ↓ kubectl -n argocd rollout restart deploy/argocd-dex-server
步骤 3  配置 argocd-rbac-cm（组映射），先不动 admin.enabled
        ↓ kubectl apply
步骤 4  【关键验证】用 devops-admin 组账号登录，确认：
        · 能登录
        · 权限正确（能管理 Application）
        · Token 里带 groups claim（看浏览器 F12 → id_token → payload）
步骤 5  准备 break-glass 账号（见 §7）
步骤 6  设置 admin.enabled: "false"
        ↓ kubectl apply
步骤 7  验证 admin 账号确实无法登录，devops-admin 仍正常
```

---

## 10. 验证

```bash
# ① 确认配置已加载
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.oidc\.config}'
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.dex\.config}'

# ② 确认 RBAC 规则
kubectl -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.policy\.csv}'
kubectl -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.scopes}'

# ③ 确认 admin 已禁用
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.admin\.enabled}'

# ④ 看某个用户的有效权限（需要 admin 权限）
argocd account list
argocd account get-user-info      # ← 看 Username（= sub）和 Groups
argocd rbac list

# ⑤ Dex 模式：确认 Dex 健康
kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-dex-server
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-dex-server --tail=50
```

**浏览器端验证 ID Token 里有什么**：
F12 → Network → 找到 `id_token` → Base64 解码 payload → 应该能看到 `groups` 数组。
或者在终端：

```bash
# 把 id_token 粘进来（base64url + 可能缺 padding，用 python 解最稳）
python3 -c "
import base64, json, sys
p = sys.argv[1].split('.')[1]
p += '=' * (-len(p) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=2, ensure_ascii=False))
" "<ID_TOKEN>"
```

> 看三样东西：**`groups`**（数组，值要和 `policy.csv` 逐字一致）、
> **`email`**（按邮箱授权时要用）、**`sub`**（用户主体，注意它往往不可读）。

**验证 IdP 的 discovery 文档**（配置 issuer 前先查，能省掉一半的排障时间）：

```bash
curl -s https://your-org.okta.com/oauth2/default/.well-known/openid-configuration \
  | python3 -m json.tool | head -40
# 重点看：authorization_endpoint / token_endpoint / device_authorization_endpoint
#          / userinfo_endpoint / scopes_supported
```

**验证组在不在 token 里**（模式 A，最快的办法是直接查 IdP 的 token 端点，
但更简单的是在浏览器里看，见上）。

---

## 11. 排障

### 11.1 通用（三种模式都适用）

| 现象 | 根因 | 处理 |
|---|---|---|
| 登录后没有权限，UI 里看不到 Application | 组没进 token | 模式 A：查 IdP 是否返回 groups / 开 `enableUserInfoGroups`；模式 B：查 OIDC connector 的 `insecureEnableGroups` + `scopes`；模式 C：查 LDAP 的 `groupSearch` |
| `g, <组名>, role:admin` 不生效 | `argocd-rbac-cm` 的 `scopes` 没含 `groups` | 加 `scopes: '[groups, email]'` |
| 组名对得上但仍无权限 | 组名和 token 里的值不一致（大小写 / Keycloak 路径 / Entra GUID） | 用 `argocd account get-user-info` 看真实的组值，逐字对齐 |
| 所有人都进不去 | `admin.enabled: "false"` 已生效但组映射没生效 | 从集群外用 kubectl 改回 `argocd-cm`，或按 §7 应急 |
| 所有人都进不去（没禁 admin 时） | IdP 侧应用没分配用户/组 | IdP → Applications → Argo CD → Users and groups |
| CLI `argocd login --sso` 报 redirect_uri 错误 | IdP 没登记 CLI 回调 | 登记 `http://localhost:8085/auth/callback`，或用 `--no-browser` |
| 浏览器报 `invalid_client` | `clientSecret` 没被替换（Secret 里 key 写错） | `kubectl -n argocd get secret argocd-secret -o yaml \| grep clientSecret` |

### 11.2 模式 A 专属

| 现象 | 根因 | 处理 |
|---|---|---|
| 登录跳转后 IdP 报 `redirect_uri_mismatch` | 登记成了 `/api/dex/callback` | 改成 `/auth/callback` |
| 登录成功但 Argo CD 报 401 / 无组 | IdP 不把组放 ID Token | 开 `enableUserInfoGroups` + `userInfoPath` |
| 用户组很多时登不进（Entra） | 组数 > 200 触发 overage | `azure.enableUserGroupOverageClaim: true` + `User.Read` 权限 |
| 每次请求都很慢 | `refreshTokenThreshold` ≥ IdP Token 有效期 | 阈值改小（如 `1m`） |
| 组改了不生效 | `userInfoCacheExpiration` 没设，缓存到 Token 过期 | 显式设缓存时长（如 `5m`） |

### 11.3 Dex 模式专属

| 现象 | 根因 | 处理 |
|---|---|---|
| Dex 报 "failed to search groups" | `userMatchers` 的 `userAttr`/`groupAttr` 不匹配 | 用 `ldapsearch` 验证，见 §5.3 |
| 密码明明对但认证失败 | `bindPW` 里的 `$` 被当变量展开 | 用 Secret + 环境变量，见 §5.4 |
| 改了 `argocd-cm` 但没生效 | ConfigMap 变更不会自动重启 Dex | `kubectl -n argocd rollout restart deploy/argocd-dex-server` |
| 用户被移出组但仍有权限 | 组只在登录时刷新 | 缩短 Token 有效期 / 主动吊销 token（§8.2） |
| `dex.config` 改了格式报错 | YAML 缩进错误 | `kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.dex\.config}' \| python3 -c 'import sys,yaml;yaml.safe_load(sys.stdin)'` |

---

## 12. 关联文档

| 主题 | 文档 |
|---|---|
| 项目级权限（`proj:<project>:<role>`） | [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| HA 下的 dex-server 副本约束 | [`02-ha.md`](./02-ha.md) §2 |
| 实施顺序 | [`08-implementation-playbook.md`](./08-implementation-playbook.md) |
| 登录/权限类故障 | [`09-troubleshooting.md`](./09-troubleshooting.md) |

### 12.1 上游参考

| 主题 | 上游文档 |
|---|---|
| 用户管理总览 | <https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/> |
| RBAC | <https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/> |
| Entra ID | <https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/microsoft/> |
| Keycloak | <https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/keycloak/> |
| Google | <https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/google/> |
| Dex 文档 | <https://dexidp.io/docs/> |
