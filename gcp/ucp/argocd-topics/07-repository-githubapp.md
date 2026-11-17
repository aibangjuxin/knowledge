# 07 · Repository 凭据、GitHub App 与目标分支

> 核心问题：**"创建了 GitHub App 类型的 Repository 之后，为什么没法编辑 Branch 详细信息？"**
> 答案：**Branch 根本不是 Repository 的属性。** 它属于 Application 的
> `spec.source.targetRevision`。

---

## 1. 先纠正一个概念模型

### 1.1 三者互不隶属

```
┌──────────────────────────────────────────────────────────────┐
│ Repository Secret（argocd 命名空间的 K8s Secret）              │
│ 记录：仓库地址 + **访问身份**（凭据）+ 归属哪个 AppProject      │
│ 不记录：目标分支、目标 tag、目标 commit                        │
└──────────────────────────────────────────────────────────────┘
                            │
                   凭据用于拉取
                            ▼
┌──────────────────────────────────────────────────────────────┐
│ Application / ApplicationSet                                 │
│ spec.source.targetRevision  ← **目标分支在这里**               │
│ spec.source.repoURL        ← 引用哪个 Repository               │
└──────────────────────────────────────────────────────────────┘
```

### 1.2 字段归属对照表

| 字段 | 归属 | 在哪配置 | 备注 |
|---|---|---|---|
| 仓库 URL | Repository Secret | `stringData.url` | |
| **访问凭据**（token / SSH key / GitHub App 私钥） | Repository Secret | `stringData.*` | 见 §3 |
| **凭据类型**（GitHub App / Azure SP） | Repository Secret | `stringData.githubAppID` 等 | 决定 UI 是否显示编辑入口 |
| 归属 AppProject | Repository Secret | `stringData.project` | |
| **目标分支 / tag / commit** | **Application** | `spec.source.targetRevision` | ⭐ |
| 目标 namespace / 集群 | Application | `spec.destination` | |
| 自动同步 | Application | `spec.syncPolicy` | |

### 1.3 为什么 UI 里"没有 Branch 字段"

两条原因叠加：

**原因 1：UI 层面，GitHub App 类型的仓库不提供凭据编辑入口。**

上游 UI 源码（`ui/src/app/settings/components/repos-list/repos-list.tsx`）中的判断：

```js
return isHTTPOrHTTPSUrl(repo.repo) && repo.type === 'git'
  && !repo.githubAppID && !repo.azureServicePrincipalClientId;
```

即：**GitHub App 类型和 Azure SP 类型的仓库，UI 直接不渲染更新凭据的表单**。
因为凭据来自 GitHub App installation，不在 Argo CD 里以静态 Secret 形式存在。

**原因 2：分支从来就不在这个表单里。** 改分支要改 Application。

> 注意：Repository 对象的字段是 `repo.name` / `repo.repo` / `repo.project` /
> `repo.githubAppID` 等——**没有任何"目标分支"字段**。
> 这是从源码确认的事实，不是 UI 的缺失。

---

## 2. 目标分支到底怎么改

### 2.1 单个 Application

```yaml
spec:
  source:
    repoURL: https://github.com/example/platform.git
    targetRevision: main          # ← 分支在这里
```

或用 CLI：

```bash
argocd app set myapp --revision main
```

**`targetRevision` 可以是：**

| 类型 | 示例 | 说明 |
|---|---|---|
| 分支 | `main` | 跟分支走，随时会变 |
| tag | `v1.2.3` | 固定版本 |
| commit SHA | `a1b2c3d4e5f6...` | 最精确，不可变 |
| 语义化版本范围 | `v1.2.*` | Helm chart 常见 |

> **GitOps 实践建议**：生产环境用 **commit SHA** 或 **tag**，
> 分支只用于开发环境。分支会漂移，SHA 不会。
> 代价是每次更新要改 SHA —— 这正是 PR 的价值。

### 2.2 ApplicationSet（批量改分支）

改的是 **模板**：

```yaml
  template:
    spec:
      source:
        repoURL: https://github.com/example/platform.git
        targetRevision: '{{.revision}}'    # ← 模板里的分支
```

或者硬编码：

```yaml
      source:
        targetRevision: v1.2.3     # ← 一次性全部改掉
```

**批量改分支的正确入口永远是 ApplicationSet 的 `template.spec.source.targetRevision`，
不是逐个改 Application。**

### 2.3 常见误解澄清

| 误解 | 事实 |
|---|---|
| "改 Repository 的分支，所有 Application 都跟着切" | ❌ Repository 里没有分支概念。**每个 Application 的 `targetRevision` 独立** |
| "在 Repository 里配置了默认分支，Application 会继承" | ❌ Argo CD 没有这个继承机制 |
| "ApplicationSet 生成后改单个 Application 的分支会被覆盖" | ✅ **会**。ApplicationSet 会把手工修改还原成模板渲染的结果。要持久修改，改模板 |

---

## 3. 凭据类型与 Secret 字段

### 3.1 全部字段（来自上游 `util/db/repository_secrets.go`）

| Secret key | 类型 | 用途 |
|---|---|---|
| `url` | string | 仓库地址 |
| `username` | string | 用户名 |
| `password` | string | 密码（也用作 PAT） |
| `bearerToken` | string | Bearer Token |
| `sshPrivateKey` | string | SSH 私钥 |
| `githubAppPrivateKey` | string | **GitHub App 私钥** |
| `githubAppID` | int | **GitHub App ID** |
| `githubAppInstallationID` | int | **Installation ID**（可省略，Argo CD 会按组织自动探测） |
| `githubAppEnterpriseBaseUrl` | string | GitHub Enterprise 专用 |
| `project` | string | 归属的 AppProject |
| `name` | string | Helm/OCI 仓库的显示名 |
| `type` | string | `git` / `helm` / `oci` |
| `insecure` | bool | 跳过 TLS 校验 |
| `enableLfs` | bool | Git LFS |
| `forceHttpBasicAuth` | bool | 强制 HTTP Basic |
| `enableOCI` | bool | OCI 仓库 |
| `useAzureWorkloadIdentity` | bool | Azure 托管身份 |

### 3.2 声明式管理（推荐）

**不要用 UI 点。** 用 Git 管理 Repository Secret：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: platform-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository    # ← 这个 label 必须有
type: Opaque
stringData:
  url: https://github.com/example/platform.git
  project: platform
```

完整示例见 [`examples/argocd-repositories-githubapp.yaml`](./examples/argocd-repositories-githubapp.yaml)。

> **关键点**：`argocd.argoproj.io/secret-type: repository` 这个 label 是
> Argo CD 识别"这是 Repository Secret"的唯一依据。缺了它，Argo CD 不认。

### 3.3 GitHub App 类型的 Repository

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: platform-githubapp
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  url: https://github.com/example/platform.git
  githubAppID: "123456"                 # ← 数字，但 Secret 里是字符串
  githubAppInstallationID: "98765432"   # 可省略
  githubAppPrivateKey: |
    -----BEGIN RSA PRIVATE KEY-----
    [REDACTED PRIVATE KEY]
    -----END RSA PRIVATE KEY-----
```

> ⚠️ **本文档不含任何真实凭据**，私钥一律 `[REDACTED]`。
> 实际部署时用 Sealed Secrets / SOPS / External Secrets，
> **不要把明文私钥提交进 Git**。

### 3.4 CLI 等价命令

```bash
# GitHub App
argocd repo add https://github.com/example/platform.git \
  --github-app-id 123456 \
  --github-app-installation-id 98765432 \
  --github-app-private-key-path ./private-key.pem

# 上游文档说明：--github-app-installation-id 可省略，
# Argo CD 会根据仓库的组织自动探测 installation ID
```

### 3.5 凭据模板（一个账号管多个仓库）

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds
type: Opaque
stringData:
  url: https://github.com/myorg
  username: myorg
  password: my-token
```

上游说明：用模板时只填**前缀 URL**（`https://github.com/myorg`），
不是完整仓库 URL。这样该组织下的所有仓库都能用这套凭据。

---

## 4. GitHub App 的正确管理姿势

### 4.1 为什么应该声明式

| 方面 | UI / CLI | 声明式（Git） |
|---|---|---|
| 审计 | 命令历史里，容易丢 | 有 diff、有 review |
| 轮换 | 手动操作，容易漏 | 改 Git → 自动同步 |
| 复现 | 新环境要重来一遍 | 一份 YAML 走天下 |
| 权限 | 需要 `repositories, *` 权限 | 只需改 Git 仓库的权限 |

### 4.2 凭据轮换

**GitHub App 的凭据轮换不在 Argo CD 侧做。** 流程是：

```
① GitHub App 侧：轮换 private key（GitHub App settings → Private keys）
        ↓
② 新的私钥更新到 Secret（Git 提交 / External Secrets 同步）
        ↓
③ Argo CD 自动感知（repo-server 每次拉取时读 Secret）
```

**注意**：Argo CD 没有"缓存 Repository 凭据"的机制——
repo-server 每次 git 操作都会读 Secret。所以更新 Secret 后**无需重启**。

如果轮换的是 **GitHub App installation 本身**（比如换了 organization），
则需要更新 `githubAppID` / `githubAppInstallationID`，
这时 Secret 里的内容变了，Argo CD 同样会自动感知。

---

## 5. 与 AppProject 的交互

Repository Secret 的 `project` 字段决定**这个仓库可以被哪些 AppProject 使用**：

```yaml
stringData:
  url: https://github.com/example/platform.git
  project: platform-dev      # ← 只有 platform-dev 项目能用这个仓库
```

**配合 `AppProject.spec.sourceRepos` 构成双重约束：**

| 层 | 约束 |
|---|---|
| Repository Secret 的 `project` | 这个凭据**归属于**哪个项目 |
| AppProject 的 `sourceRepos` | 这个项目**允许**哪些仓库 |

两边都要配。缺一个就放行。

**多项目共享一个仓库**：`project` 字段留空表示"全局可用"，
但那样就失去了这一层约束 —— 通常配合更严的 `sourceRepos` 使用。

---

## 6. 集群凭据（同类机制，一并说明）

目标集群凭据也是同一种 Secret 机制：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gke-dev-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
stringData:
  name: gke-dev
  server: https://<GKE_CLUSTER_ENDPOINT>
  config: |
    {
      "bearerToken": "[REDACTED]",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "[REDACTED_BASE64_CA]"
      }
    }
```

**GKE 上的推荐做法**：用 **Workload Identity** 而不是长期 token。
Argo CD 的 repo-server / server 通过 GKE metadata server 取短期凭据，
无需管理长期密钥。相关字段是 `useAzureWorkloadIdentity` 类似的思路，
GKE 侧通过 `server` 字段的 URL 或集群 Secret 的 `config` 传入。

> 具体 GKE Workload Identity 配置请查阅官方文档：
> `https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity`
> 本轮无法访问该页面（文档站限制），实施前请直接核对。

---

## 7. 验证

```bash
# ① 列出所有 Repository
argocd repo list
kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=repository

# ② 查看某个 Repository 的详情（不显示凭据明文）
argocd repo get https://github.com/example/platform.git

# ③ 确认 GitHub App 字段已设置
kubectl -n argocd get secret platform-githubapp -o jsonpath='{.data.githubAppID}' | base64 -d; echo
kubectl -n argocd get secret platform-githubapp -o jsonpath='{.data.githubAppInstallationID}' | base64 -d; echo
# 私钥不要打印，只确认 key 存在
kubectl -n argocd get secret platform-githubapp -o jsonpath='{.data.githubAppPrivateKey}' | base64 -d | head -1

# ④ 测试仓库连通性
argocd repo list   # 带凭据的仓库应能正常列出
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-repo-server --tail=50 | grep -iE 'error|auth|fail'

# ⑤ 确认 Application 的目标分支
kubectl -n argocd get application <app> -o jsonpath='{.spec.source.targetRevision}{"\n"}'

# ⑥ 确认 ApplicationSet 模板的分支（批量修改的入口）
kubectl -n argocd get applicationset <appset> -o jsonpath='{.spec.template.spec.source.targetRevision}{"\n"}'
```

---

## 8. 排障

| 现象 | 根因 | 处理 |
|---|---|---|
| Repository 创建后 UI 里没有编辑凭据的入口 | GitHub App / Azure SP 类型，UI 不提供 | 正常。改用声明式管理（Git） |
| **想改分支但找不到地方** | 分支不在 Repository 上 | 改 Application 的 `spec.source.targetRevision`；批量改改 ApplicationSet 模板 |
| 改了 Application 的分支，AppSet 管理的应用又变回去 | AppSet 会把手工修改还原 | 改 AppSet 的 `template.spec.source.targetRevision` |
| Application 报 "repository not found" | Secret 缺 `argocd.argoproj.io/secret-type: repository` label | 补 label |
| GitHub App 仓库报认证失败 | `githubAppPrivateKey` / `githubAppID` / `githubAppInstallationID` 不匹配 | 核对 App ID、installation ID、私钥是否属于同一个 App |
| 私钥换了但还报认证失败 | Argo CD 缓存了旧 Secret | Argo CD 不缓存凭据，检查的是 Secret 是否真的更新（`kubectl get secret -o yaml`） |
| 私有仓库报 "authentication required" | 用 HTTPS 但没配凭据 | 补 `username` + `password`/`bearerToken` |
| SSH 仓库报 host key 错误 | 没配 `insecure` 或缺 known_hosts | 配 `insecure: "true"`（不推荐）或配置 host key |
| 某个项目用不了这个仓库 | Secret 的 `project` 字段不含该项目 | 补 `project` 或清空（全局） |
| AppSet 生成的 Application 拉不到 Git | ApplicationSet controller 无权访问该 Repository | 检查 Repository Secret 的 `project` 与 AppProject 的 `sourceRepos` |

---

## 9. 关联文档

| 主题 | 文档 |
|---|---|
| AppProject 与仓库白名单 | [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| ApplicationSet 的 Git generator | [`05-appset.md`](./05-appset.md) |
| `Application` 字段详解 | [`../argocd-application-guide.md`](../argocd-application-guide.md) |
| 集群凭据与 ServiceAccount | [`04-appproject-rbac.md`](./04-appproject-rbac.md) §4 |
