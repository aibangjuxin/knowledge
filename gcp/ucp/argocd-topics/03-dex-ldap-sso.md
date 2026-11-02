# 03 · Dex / LDAP 身份打通与禁用内置 admin

> 目标：用 Dex 接 LDAP 认证，禁用 Argo CD 内置 `admin` 账号，
> 改由 LDAP 组（如 `devops-admin`）授权管理权限。

在 Argo CD 和云原生生态中，**Dex** 是一个开源的**身份联合系统（Identity Federation）与 OIDC（OpenID Connect）提供商**（由 CNCF 托管维护）。

简而言之：**Dex 充当了一个“身份认证转换代理 / 翻译官”**。

---

### 1. 为什么这里需要 Dex？

* **Argo CD 本身只原生支持 OIDC**（如 Okta、Keycloak、Google 等标准的 OAuth2/OIDC 认证协议），**它自己并不会直接去连 LDAP、SAML 等传统企业身份系统**。
* 企业内部通常使用 **LDAP / Active Directory** 存储员工账号与部门信息。
* **Dex 的作用**：
  * **向上对接 Argo CD**：Dex 对外暴露标准的 OIDC 接口给 Argo CD。
  * **向下对接企业 LDAP**：Dex 去连接企业的 LDAP 服务器进行账号密码验证和组（Groups）信息查询。
  * **打通链路**：用户在 Argo CD 点击登录时，Argo CD 将用户重定向到 Dex，Dex 向 LDAP 校验凭据，验证成功后 Dex 签发一个包含用户身份和所属 Group 的 OIDC ID Token 给 Argo CD。

---

### 2. 架构关系流程

```
[ 用户浏览器 ]
     │
     │ 1. 访问 Argo CD 登录
     ▼
[ Argo CD ]  ──(标准 OIDC 协议)──>  [ Dex Server ]
                                        │
                                        │ 2. 查询用户 / 校验密码 / 读取 Groups
                                        ▼
                                  [ 企业 LDAP / AD ]
```

---

### 3. 文档中提到的关键点解释

* **内置 Dex 组件**：Argo CD 官方安装包默认就带了一个 `argocd-dex-server` 部署组件，专门用来降低对接 LDAP、GitHub、GitLab、SAML 等非标准 OIDC 系统的难度。
* **禁用内置 `admin`**：在配置了 Dex + LDAP 后，所有研发/运维人员都通过公司的企业 LDAP 账号单点登录（SSO），同时关闭 Argo CD 本地的缺省 `admin` 账号，以符合安全合规和审计要求。


---

## 1. 三个必须分开的动作

初学者最容易把下面三件事当成一件，从而出现"配置都写了但进不去"的局面。

| # | 动作 | 配置位置 | 作用 |
|---|---|---|---|
| **①** | **禁用内置 admin** | `argocd-cm` 的 `admin.enabled: "false"` | 让 `admin` 这个本地账号**不能登录** |
| **②** | **让 LDAP 组传到 Argo CD** | `argocd-cm` 的 `dex.config`（`insecureEnableGroups` + `scopes`） | 让 ID Token 里带上 `groups` claim |
| **③** | **把组映射成角色** | `argocd-rbac-cm` 的 `policy.csv` | 让 `devops-admin` 组 → `role:admin` |

**只做 ①** → 所有人都进不去（内置 admin 也没了，外部组还没生效）。
**只做 ②③ 不做 ①** → 能用，但 `admin` 账号仍可登录（安全隐患）。
**正确顺序：先 ②③，验证外部管理员能登录并有权限，再做 ①。**

---

## 2. ① 禁用内置 admin

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
- 禁用后，`argocd` 本地账号（`argocd admin account bcrypt` 改的那个）也不能登录

---

## 3. ② Dex + LDAP connector

### 3.1 完整配置

完整可复制版本见 [`examples/dex-ldap-config.yaml`](./examples/dex-ldap-config.yaml)。
以下是核心结构：

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

    # ↓↓↓ 关键：这三个开关决定 LDAP 组能不能传到 Argo CD ↓↓↓
    insecureEnableGroups: true
    scopes:
    - profile
    - email
    - groups
    # getUserInfo: true     # 组不在 ID Token 里时才需要开
```

### 3.2 Dex LDAP connector 字段说明（据 Dex 上游 LDAP 文档）

| 字段 | 必需 | 说明 |
|---|---|---|
| `host` | ✅ | `host:port`。不写端口时按 `insecureNoSSL` / `startTLS` 推断：389 或 636 |
| `insecureNoSSL` | | 纯明文连接（389）。**会泄露密码**，未来版本可能移除，不建议用 |
| `insecureSkipVerify` | | 跳过 TLS 证书校验。**仅限探索期** |
| `startTLS` | | 先用 `ldap://` 连再 `StartTLS`；不设则用 `ldaps://` |
| `rootCA` | | CA 证书路径 |
| `rootCAData` | | CA 证书内容（base64 PEM） |
| `bindDN` | | 服务账号 DN。LDAP 允许匿名搜索时可不填 |
| `bindPW` | | 服务账号密码。**含 `$` 时必须放环境变量**（见下） |
| `usernamePrompt` | | 登录框提示文字 |
| `userSearch.baseDN` | ✅ | 用户搜索根 DN |
| `userSearch.filter` | | 附加过滤条件，如 `(objectClass=person)` |
| `userSearch.username` | ✅ | 用户名匹配属性 |
| `userSearch.idAttr` | | 用户唯一标识属性。无 email 时也可用它 |
| `userSearch.emailAttr` | | 映射到 Email 的属性。**映射不到就没有 email claim**，会影响 `email` scope 的 RBAC 匹配 |
| `userSearch.nameAttr` | | 显示名属性 |
| `userSearch.preferredUsernameAttr` | | 登录名属性 |
| `groupSearch.baseDN` | | 组搜索根 DN |
| `groupSearch.filter` | | 组对象过滤 |
| `groupSearch.userMatchers[].userAttr` | ✅ | 组里存的是哪种用户标识 |
| `groupSearch.userMatchers[].groupAttr` | ✅ | 组对象里存成员的属性名 |
| `groupSearch.nameAttr` | ✅ | 组名属性 → **这个值就是 Argo CD 里看到的组名** |
| `groupSearch.recursionGroupAttr` | | 递归查找嵌套组 |

### 3.3 `userMatchers` 怎么配（最容易错的地方）

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

### 3.4 密码含 `$` 的处理

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

---

## 4. ② 让组传到 Argo CD（最关键的一步）

### 4.1 三个开关

```yaml
  dex.config: |
    connectors:
    - type: ldap
      ...

    # 开关 1：允许 Dex 在 ID Token 中携带 groups
    insecureEnableGroups: true

    # 开关 2：请求 groups scope
    scopes:
    - profile
    - email
    - groups

    # 开关 3（可选）：组不在 ID Token 里时，改从 UserInfo 端点取
    # getUserInfo: true
```

### 4.2 为什么必须显式开启

**LDAP 的组不会自动出现在 Argo CD 里。**

链路是：
```
LDAP 组 → Dex 解析 → Dex 写入 ID Token 的 groups claim → Argo CD 读 groups → Casbin 匹配
```

任何一环断了，`g, devops-admin, role:admin` 就匹配不上：
- Dex 默认**不**在 ID Token 里放组（安全默认）→ 需要 `insecureEnableGroups: true`
- Dex 只在请求了 `groups` scope 时才解析组 → 需要 `scopes` 含 `groups`
- 如果组在 Dex 侧被过滤掉了（例如不在 `groupSearch` 范围内），
  ID Token 里就没有 → 需要 `getUserInfo: true` 从 UserInfo 端点再取一次

### 4.3 组信息只在认证时刷新

**上游明确说明：组成员信息只在用户认证（登录）时刷新。**

推论（必须写进运维手册）：

| 场景 | 结果 |
|---|---|
| 员工加入 `devops-admin` 组 | **下次登录**才生效 |
| 员工被移出 `devops-admin` 组 | **下次登录**才失效 ⚠️ |
| 已登录用户被降权 | 旧 Token 仍带旧组，权限未回收 ⚠️ |
| 修改 LDAP 组定义 | 同上，需重新登录 |

**风险**：离职/降权后，旧的 Dex session 在 Token 过期前仍持有管理员权限。

缓解措施：
1. 缩短 ID Token 有效期（Dex 的 `expiry` 配置）
2. Argo CD 侧开启 Token 吊销（见 §6.3）
3. **定期复核 LDAP 组成员**（这是唯一可靠的解法）

---

## 5. ③ 组映射成角色

配置在 **`argocd-rbac-cm`**（不是 `argocd-cm`）：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    # LDAP 组 → 全局管理员
    g, devops-admin, role:admin

    # 只读组
    g, devops-readonly, role:readonly

    # 开发组：可同步指定项目
    p, devops-dev, applications, sync, dev/*, allow
    g, devops-dev, role:readonly

  policy.default: role:readonly
  scopes: '[groups, email]'
```

完整示例见 [`examples/argocd-rbac-cm.yaml`](./examples/argocd-rbac-cm.yaml)。

### 5.1 `policy.csv` 语法（上游 RBAC 文档）

```
p, subject, resource, action, object, effect
g, subject, inherited-subject
```

| 字段 | 取值 |
|---|---|
| `resource` | `applications`、`applicationsets`、`projects`、`repositories`、`clusters`、`logs`、`exec` |
| `action` | `get`、`create`、`update`、`delete`、`sync`、`override`、`*` |
| `object` | `*`、`<project>/*`、`<project>/<app>`、`<app>` |
| `effect` | `allow` / `deny` |

**内置角色**：`role:readonly`（只读全部）、`role:admin`（无限制）。

### 5.2 `scopes` 必须包含 `groups`

```yaml
  scopes: '[groups, email]'
```

上游默认是 `'[groups]'`。这个字段控制 **Argo CD 拿哪些 OIDC claim 去做 RBAC 匹配**。
如果你的 LDAP 组名和 email 都可能作为主体被引用，就两个都写上。

**关键**：如果 `scopes` 里没有 `groups`，`g, devops-admin, role:admin`
这条规则就**永远不会生效**——即使 Dex 已经把组正确放进了 Token。

### 5.3 `policy.default` 的安全陷阱

上游明确说明：

> When a user is authenticated in Argo CD, it will be granted the role specified in `policy.default`.

**并且：默认权限无法被 `deny` 规则阻止。**

这意味着 `policy.default: role:readonly` 会让**所有已认证用户**
（包括任意一个能通过 LDAP 认证的人）都能读所有 Application。

**推荐做法**：自己定义一个最小权限角色作为默认。

```yaml
data:
  policy.csv: |
    p, role:authenticated, applications, get, *, allow
    p, role:authenticated, projects, get, *, allow
    p, role:authenticated, repositories, get, *, allow
    p, role:authenticated, clusters, get, *, allow
    g, role:authenticated, role:readonly    # 继承只读
    g, devops-admin, role:admin
  policy.default: role:authenticated
```

> 注意 `g, role:authenticated, role:readonly` 这种**角色继承**是上游文档支持的语法。
> 但如果你想让 `role:authenticated` 严格最小，就不要继承 `role:readonly`，
> 直接写上面那四条 `p` 规则。

---

## 6. 会话与 Token 行为

### 6.1 嵌入式 Dex 的登录会话

| 机制 | 适用 | 说明 |
|---|---|---|
| `refreshTokenThreshold` | **仅 Argo CD 直连外部 OIDC** | 距上次刷新超过该时长则强制重新认证 |
| Dex ID Token 过期 | **嵌入式 Dex Web 登录** | **不受 `refreshTokenThreshold` 控制**，过期后需重新登录 |

**这是一个高频误解点。** 用嵌入式 Dex 时，配置 `refreshTokenThreshold`
不会延长嵌入式登录的会话。Dex 发出的 ID Token 过期后，用户必须重新走 LDAP 登录。

### 6.2 Dex 的存储后端

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

### 6.3 Token 吊销

上游 `docs/operator-manual/user-management/index.md` 有 "Token Revocation and
Session Management" 章节。要点：Argo CD 支持吊销特定用户的 token，
用于「员工离职立即踢下线」这类场景。

结合 LDAP 组变更只在登录时刷新的特性，建议：
- 紧急踢人 → 用 Argo CD 的 token 吊销功能（主动）
- 常规降权 → 依赖 Token 自然过期（被动，见 §4.3 的缓解措施）

---

## 7. 实施顺序（防锁死）

```
步骤 1  配置 dex.config（LDAP connector + insecureEnableGroups + scopes）
        ↓ kubectl apply
步骤 2  重启 dex-server，确认 Dex 健康
        ↓ kubectl -n argocd rollout restart deploy/argocd-dex-server
步骤 3  配置 argocd-rbac-cm（组映射），先不动 admin.enabled
        ↓ kubectl apply
步骤 4  【关键验证】用 devops-admin 组账号登录，确认：
        · 能登录
        · 权限正确（能管理 Application）
        · Token 里带 groups claim（看浏览器 F12 → id_token → payload）
步骤 5  准备 break-glass 账号（见下）
步骤 6  设置 admin.enabled: "false"
        ↓ kubectl apply
步骤 7  验证 admin 账号确实无法登录，devops-admin 仍正常
```

### 6.1 break-glass 方案

**禁用 admin 前必须准备**，否则一旦 RBAC 配错就完全锁死。

推荐：**用 Argo CD 的本地账号**（不是 `admin`），并在禁用 admin 前验证它可用：

```bash
# 创建/更新本地账号（密码用 bcrypt）
argocd account update --password

# 或直接改 argocd-secret 里的 admin.passwordMtime
# 但这依赖 admin 账号存在
```

**更好的方案**（不依赖内置账号）：
在 `argocd-rbac-cm` 里预留一个只有特定 OIDC subject 能匹配的规则：

```yaml
  policy.csv: |
    g, devops-admin, role:admin
    p, break-glass-email@corp.example.com, applications, *, *, allow
    g, break-glass-email@corp.example.com, role:admin
```

或者**准备一条 kubectl 直通的应急路径**（集群 admin 权限），
在 runbook 里写清楚。

> ⚠️ 应急账号方案要评估审计要求——很多组织不允许长期存在的后门账号。
> 折中做法：平时禁用，紧急时通过修改 `argocd-rbac-cm` 临时开启。

---

## 8. 验证

```bash
# ① Dex 是否健康
kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-dex-server
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-dex-server --tail=50

# ② 确认配置已加载
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.dex\.config}' | grep -E 'insecureEnableGroups|groups'

# ③ 确认 RBAC 规则
kubectl -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.policy\.csv}'
kubectl -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.scopes}'

# ④ 确认 admin 已禁用
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.admin\.enabled}'

# ⑤ 看某个用户的有效权限（需要 admin 权限）
argocd account list
argocd rbac list
```

**浏览器端验证 ID Token 是否带组**：
F12 → Network → 找到 `id_token` → Base64 解码 payload → 应该有 `groups` 数组。

---

## 9. 排障

| 现象 | 根因 | 处理 |
|---|---|---|
| 登录后没有权限，UI 里看不到 Application | `groups` 没进 Token | 查 `insecureEnableGroups: true` + `scopes` 含 `groups` |
| `g, devops-admin, role:admin` 不生效 | `argocd-rbac-cm` 的 `scopes` 没含 `groups` | 加 `scopes: '[groups, email]'` |
| 组名对得上但仍无权限 | 组名取自 `groupSearch.nameAttr` | 确认 LDAP 组的 `cn` 与策略里的字符串**完全一致**（大小写敏感） |
| Dex 报 "failed to search groups" | `userMatchers` 的 `userAttr`/`groupAttr` 不匹配 | 用 `ldapsearch` 验证，见 §3.3 |
| 改了 `argocd-cm` 但没生效 | ConfigMap 变更不会自动重启 Dex | `kubectl -n argocd rollout restart deploy/argocd-dex-server` |
| 用户被移出组但仍有权限 | 组只在登录时刷新 | 缩短 Token 有效期 / 主动吊销 token |
| 所有人都进不去 | `admin.enabled: "false"` 已生效但组映射没生效 | 从集群外用 kubectl 改回 `argocd-cm`，或按 §7 应急 |
| Dex 登录报 "invalid password" 但密码没错 | `bindPW` 里的 `$` 被当变量展开 | 用 Secret + 环境变量，见 §3.4 |
| `dex.config` 改了格式报错 | YAML 缩进错误 | `kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.dex\.config}' \| python3 -c 'import sys,yaml;yaml.safe_load(sys.stdin)'` |

---

## 10. 关联文档

| 主题 | 文档 |
|---|---|
| 项目级权限（`proj:<project>:<role>`） | [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| HA 下的 dex-server 副本约束 | [`02-ha.md`](./02-ha.md) §2 |
| 实施顺序 | [`08-implementation-playbook.md`](./08-implementation-playbook.md) |
