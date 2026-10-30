# Argo CD v3.5.6 API 接口参考

> 数据来源：官方源码仓库 `v3.5.6` tag 的 `assets/swagger.json`（Argo CD API Server 实际 serve 的同一份文件），并与 `server/server.go` 的路由注册、`server/*/*.proto` 的 RPC 定义逐条交叉核对。

```bash
# 拉取官方接口定义
curl -sSL -o swagger.json https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/assets/swagger.json
# sha256: 5cfd43dfd31446d875ab35244b19f2aaccc8120c8ddfafd90e2c25b668acaee6
```

## 0. 总览

| 类别 | 数量 |
|------|------|
| REST 接口（swagger 定义，13 个 Service） | **106 个操作 / 82 个路径** |
| 非 swagger 的运行时路由（`server.go` 手写注册） | 13 个 |
| gRPC Service（与 REST 同源） | 13 个 |

所有 REST 接口都在 `/api/v1/` 下，**只有 `/api/version` 例外**。

接口按 Service 的分布：

| Service | 操作数 | | Service | 操作数 |
|---|---|---|---|---|
| AccountService | 6 | | ApplicationService | 32 |
| ApplicationSetService | 8 | | CertificateService | 3 |
| ClusterService | 7 | | GPGKeyService | 4 |
| NotificationService | 3 | | ProjectService | 12 |
| RepoCredsService | 8 | | RepositoryService | 17 |
| SessionService | 3 | | SettingsService | 2 |
| VersionService | 1 | |  |  |

---

## 1. 调用前置条件

### 1.1 Base URL 与端口

| 组件 | 端口 | 用途 |
|---|---|---|
| argocd-server | 443 (https) / 8080 (http) | REST API + gRPC + UI + Webhook |
| argocd-server metrics | 8083 | Prometheus 指标（**不在主端口**） |
| argocd-application-controller metrics | 8082 | Prometheus 指标 |
| argocd-repo-server | 8081 | Helm/Chart 渲染 |
| argocd-dex | 5556/5557/5558 | 内置 Dex（OIDC） |
| argocd-redis | 6379 | 缓存 |

### 1.2 认证方式

认证按以下优先级（见 `server/server.go` 的 `getToken()`）：

1. `Authorization: Bearer <token>` —— **推荐**，自动化场景用这个
2. gRPC metadata `token: <token>`
3. Cookie `argocd.token=<jwt>` —— 浏览器/UI 使用

Token 有三种来源：

| 类型 | 获取方式 | 作用域 |
|---|---|---|
| 会话 JWT | `POST /api/v1/session`（用户名密码） | 该账号当前 RBAC 权限，有效期短 |
| 账号 API Token | `POST /api/v1/account/{name}/token` | 该账号 RBAC 权限，长期有效 |
| 项目角色 Token | `POST /api/v1/projects/{project}/roles/{role}/token` | 仅该项目的该角色权限 |

> 账号 API Token 需要该账号在 `argocd-cm` 中带 `apiKey` 能力位（例如 `accounts.<name>: apiKey`）。

**免认证接口**：`GET /api/version`、`POST /api/v1/session`、`GET /api/v1/settings`、`/healthz`。

### 1.3 分组与 RBAC

- 每个接口都会按 `argocd-rbac-cm` 中的策略做鉴权。
- 启用 *Apps in any namespace* 时，应用类接口需要加 `?appNamespace=<ns>`，否则只在 Argo CD 自身 namespace 内查找。
- 应用类接口普遍支持 `?project=<name>` 做归属校验，传错会直接返回权限错误而不是 404。

---

## 2. REST API 全量清单

> 路径中的 `{name}` 等占位符需要 URL 编码其实际值（含 `/` 时必须编码，如 `https%3A%2F%2Fkubernetes.default.svc`）。

### 版本信息 — `VersionService`（1）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/version` | 返回 API Server 版本信息（GitTag、编译时间、Kustomize/Helm/Jsonnet/Kubectl 版本等）。**无需认证** |

### 会话与登录 — `SessionService`（3）

| 方法 | 路径 | 说明 |
|------|------|------|
| DELETE | `/api/v1/session` | 删除会话 Cookie（登出） |
| POST | `/api/v1/session` | 用用户名密码换取 JWT，同时下发 `argocd.token` Cookie。**无需认证** |
| GET | `/api/v1/session/userinfo` | 获取当前登录用户信息（是否登录、用户名、所属 groups、issuer） |

### 全局设置 — `SettingsService`（2）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/settings` | 获取 Argo CD 全局设置（URL、OIDC/Dex 配置、status badge、exec 开关、resource.customizations 等） |
| GET | `/api/v1/settings/plugins` | 获取已配置的 Config Management Plugin（ CMP ）列表 |

### 账号与 Token — `AccountService`（6）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/account` | 列出所有本地账号 |
| GET | `/api/v1/account/can-i/{resource}/{action}/{subresource}` | 校验当前账号是否有某资源操作的权限，返回 `yes`/`no`。调用前预判权限用 |
| PUT | `/api/v1/account/password` | 修改当前账号密码（旧密码 + 新密码） |
| GET | `/api/v1/account/{name}` | 获取指定账号详情 |
| POST | `/api/v1/account/{name}/token` | 为账号签发 API Token（返回 token 明文，仅此一次可见） |
| DELETE | `/api/v1/account/{name}/token/{id}` | 吊销指定账号的 Token（按 token id） |

### Application 核心操作 — `ApplicationService`（32）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/applications` | 列出应用，支持按 project / name / selector / repo / appNamespace 过滤 |
| POST | `/api/v1/applications` | 创建应用 |
| POST | `/api/v1/applications/manifestsWithFiles` | 以 multipart 文件流方式提供本地文件，渲染出目标 manifest（不落库，用于 CLI 侧渲染） |
| GET | `/api/v1/applications/{appName}/server-side-diff` | 服务端 dry-run apply 计算出的 diff（Server-Side Apply 语义） |
| PUT | `/api/v1/applications/{application.metadata.name}` | 全量更新应用（PUT 语义，字段缺失会被清空） |
| GET | `/api/v1/applications/{applicationName}/managed-resources` | 列出受管资源及 live / target 状态，用于算 diff |
| GET | `/api/v1/applications/{applicationName}/resource-tree` | 获取应用的资源树（父子关系、health、sync wave、连接信息） |
| DELETE | `/api/v1/applications/{name}` | 删除应用。`?cascade=true` 同时删除受管资源，默认仅删 Application CR |
| GET | `/api/v1/applications/{name}` | 获取应用详情。`?refresh=normal` 或 `hard` 触发刷新（hard 会重新拉取 Git 并重建 manifest） |
| PATCH | `/api/v1/applications/{name}` | 局部更新应用（JSON Merge Patch / Strategic Merge Patch） |
| GET | `/api/v1/applications/{name}/events` | 列出与该应用相关的 K8s Event |
| GET | `/api/v1/applications/{name}/links` | 应用级 Deep Link 列表 |
| GET | `/api/v1/applications/{name}/logs` | 流式拉取 Pod 日志，按 group/kind/resourceName 选 Pod（推荐写法） |
| GET | `/api/v1/applications/{name}/manifests` | 渲染并返回目标 manifest（Helm/Kustomize/Jsonnet 渲染后的 YAML） |
| DELETE | `/api/v1/applications/{name}/operation` | 终止正在执行的 sync / rollback 操作 |
| GET | `/api/v1/applications/{name}/pods/{podName}/logs` | 流式拉取指定 Pod 的日志（较早的接口写法） |
| DELETE | `/api/v1/applications/{name}/resource` | 删除应用内的单个资源 |
| GET | `/api/v1/applications/{name}/resource` | 获取应用内某个资源的 live manifest（按 namespace/resourceName/group/kind 定位） |
| POST | `/api/v1/applications/{name}/resource` | Patch 应用内的单个资源（注意：路径是 resource，语义是 patch） |
| GET | `/api/v1/applications/{name}/resource/actions` | 列出该资源可用的 Resource Action（如 Deployment 的 rollout restart） |
| POST | `/api/v1/applications/{name}/resource/actions` | 执行 Resource Action（不带参数） |
| POST | `/api/v1/applications/{name}/resource/actions/v2` | 执行 Resource Action 并传入参数（v2 支持带参） |
| GET | `/api/v1/applications/{name}/resource/links` | 资源级 Deep Link 列表 |
| GET | `/api/v1/applications/{name}/revisions/{revision}/chartdetails` | 获取指定 revision 的 Helm Chart 元数据（description、maintainers、home） |
| GET | `/api/v1/applications/{name}/revisions/{revision}/metadata` | 获取指定 revision 的 Git 元数据（author、date、tags、message） |
| GET | `/api/v1/applications/{name}/revisions/{revision}/ocimetadata` | 获取指定 revision 的 OCI 制品元数据 |
| POST | `/api/v1/applications/{name}/rollback` | 回滚到历史部署 ID（用 rollback 的 `id`） |
| PUT | `/api/v1/applications/{name}/spec` | 仅更新应用的 spec 部分，其余字段不动 |
| POST | `/api/v1/applications/{name}/sync` | 触发同步：可指定 revision、prune、dryRun、resources、syncOptions 等 |
| GET | `/api/v1/applications/{name}/syncwindows` | 获取该应用适用的 sync window 状态 |
| GET | `/api/v1/stream/applications` | **流式**：持续推送应用变更事件（类似 watch） |
| GET | `/api/v1/stream/applications/{applicationName}/resource-tree` | **流式**：持续推送资源树变化 |

### ApplicationSet（GitOps 生成器） — `ApplicationSetService`（8）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/applicationsets` | 列出 ApplicationSet |
| POST | `/api/v1/applicationsets` | 创建 ApplicationSet |
| POST | `/api/v1/applicationsets/generate` | 按给定的 ApplicationSet 生成 Application 列表（预览，**不落库**） |
| DELETE | `/api/v1/applicationsets/{name}` | 删除 ApplicationSet |
| GET | `/api/v1/applicationsets/{name}` | 获取 ApplicationSet 详情 |
| GET | `/api/v1/applicationsets/{name}/events` | 列出与该 ApplicationSet 相关的 K8s Event |
| GET | `/api/v1/applicationsets/{name}/resource-tree` | 获取 ApplicationSet 的资源树 |
| GET | `/api/v1/stream/applicationsets` | **流式**：持续推送 ApplicationSet 变更 |

### 项目（RBAC 边界） — `ProjectService`（12）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/projects` | 列出项目（AppProject） |
| POST | `/api/v1/projects` | 创建项目 |
| DELETE | `/api/v1/projects/{name}` | 删除项目 |
| GET | `/api/v1/projects/{name}` | 获取项目详情 |
| GET | `/api/v1/projects/{name}/detailed` | 获取项目详情，含 global project 与其关联的资源 |
| GET | `/api/v1/projects/{name}/events` | 列出项目相关 Event |
| GET | `/api/v1/projects/{name}/globalprojects` | 获取该项目继承的 global project（虚拟项目视图） |
| GET | `/api/v1/projects/{name}/links` | 项目级 Deep Link 列表 |
| GET | `/api/v1/projects/{name}/syncwindows` | 查询当前是否有生效的 sync window |
| PUT | `/api/v1/projects/{project.metadata.name}` | 更新项目 |
| POST | `/api/v1/projects/{project}/roles/{role}/token` | 签发项目角色 Token（project role token，细粒度授权） |
| DELETE | `/api/v1/projects/{project}/roles/{role}/token/{iat}` | 吊销项目角色 Token（以签发时间 `iat` 标识） |

### 集群注册与管理 — `ClusterService`（7）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/clusters` | 列出已注册集群 |
| POST | `/api/v1/clusters` | 注册集群 |
| DELETE | `/api/v1/clusters/{id.value}` | 删除集群 |
| GET | `/api/v1/clusters/{id.value}` | 获取集群详情（`id.value` 为 server URL，需 URL 编码） |
| PUT | `/api/v1/clusters/{id.value}` | 更新集群配置 |
| POST | `/api/v1/clusters/{id.value}/invalidate-cache` | 清除集群缓存，强制重新同步集群状态 |
| POST | `/api/v1/clusters/{id.value}/rotate-auth` | 轮换集群访问用的 bearer token |

### 仓库管理（只读 + 可写） — `RepositoryService`（17）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/repositories` | 列出已配置仓库 |
| POST | `/api/v1/repositories` | 添加仓库 |
| PUT | `/api/v1/repositories/{repo.repo}` | 更新仓库配置 |
| DELETE | `/api/v1/repositories/{repo}` | 删除仓库 |
| GET | `/api/v1/repositories/{repo}` | 获取仓库配置 |
| GET | `/api/v1/repositories/{repo}/apps` | 列出该仓库下可识别的 Application 目录 |
| GET | `/api/v1/repositories/{repo}/helmcharts` | 列出该仓库下的 Helm Chart |
| GET | `/api/v1/repositories/{repo}/oci-tags` | 列出该 OCI 仓库的 tags |
| GET | `/api/v1/repositories/{repo}/refs` | 列出该 Git 仓库的分支与 tags |
| POST | `/api/v1/repositories/{repo}/validate` | 校验仓库访问权限（连通性 + 凭据有效性） |
| POST | `/api/v1/repositories/{source.repoURL}/appdetails` | 获取仓库中某路径的应用详情（类型、Helm values、参数、目录结构） |
| GET | `/api/v1/write-repositories` | 列出可写仓库（Source Hydrator 回写用，3.x 新增） |
| POST | `/api/v1/write-repositories` | 添加可写仓库 |
| PUT | `/api/v1/write-repositories/{repo.repo}` | 更新可写仓库配置 |
| DELETE | `/api/v1/write-repositories/{repo}` | 删除可写仓库 |
| GET | `/api/v1/write-repositories/{repo}` | 获取可写仓库配置 |
| POST | `/api/v1/write-repositories/{repo}/validate` | 校验仓库的**写**权限 |

### 仓库凭据模板 — `RepoCredsService`（8）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/repocreds` | 列出仓库凭据模板（按 URL 前缀匹配生效） |
| POST | `/api/v1/repocreds` | 创建仓库凭据模板 |
| PUT | `/api/v1/repocreds/{creds.url}` | 更新仓库凭据模板 |
| DELETE | `/api/v1/repocreds/{url}` | 删除仓库凭据模板 |
| GET | `/api/v1/write-repocreds` | 列出可写仓库的凭据模板 |
| POST | `/api/v1/write-repocreds` | 创建可写仓库的凭据模板 |
| PUT | `/api/v1/write-repocreds/{creds.url}` | 更新可写仓库的凭据模板 |
| DELETE | `/api/v1/write-repocreds/{url}` | 删除可写仓库的凭据模板 |

### 仓库证书（TLS / SSH） — `CertificateService`（3）

| 方法 | 路径 | 说明 |
|------|------|------|
| DELETE | `/api/v1/certificates` | 按查询条件（hostNamePattern、certType 等）批量删除证书 |
| GET | `/api/v1/certificates` | 列出仓库的 TLS / SSH known_hosts 证书 |
| POST | `/api/v1/certificates` | 添加仓库证书 |

### GPG 公钥 — `GPGKeyService`（4）

| 方法 | 路径 | 说明 |
|------|------|------|
| DELETE | `/api/v1/gpgkeys` | 删除 GPG 公钥（`?keyID=`） |
| GET | `/api/v1/gpgkeys` | 列出已注册的 GPG 公钥 |
| POST | `/api/v1/gpgkeys` | 添加 GPG 公钥（用于校验签名 commit） |
| GET | `/api/v1/gpgkeys/{keyID}` | 获取单个 GPG 公钥信息 |

### 通知服务 / 模板 / 触发器 — `NotificationService`（3）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/notifications/services` | 列出已配置的通知服务（Slack/Email/Webhook 等） |
| GET | `/api/v1/notifications/templates` | 列出通知模板 |
| GET | `/api/v1/notifications/triggers` | 列出通知触发器 |

---

## 3. 关键请求体与参数

### 3.1 登录换 Token

`POST /api/v1/session`

| 字段 | 类型 | 说明 |
|---|---|---|
| `username` | string | 用户名（必填） |
| `password` | string | 密码（必填） |
| `projects` | string[] | 登录后默认选中的项目 |

响应 `sessionSessionResponse`：`token`（JWT）、`expiresAt`。

### 3.2 同步应用

`POST /api/v1/applications/{name}/sync` —— body 为 `applicationApplicationSyncRequest`：

| 字段 | 类型 | 说明 |
|---|---|---|
| `appNamespace` | string | 应用所在 namespace |
| `dryRun` | boolean | 只做 dry-run，不实际变更 |
| `infos` | array |  |
| `manifests` | array |  |
| `name` | string | 目标 revision |
| `project` | string |  |
| `prune` | boolean | 是否删除不在 manifest 中的资源 |
| `resources` | array | 只同步指定资源（K8s resource 列表） |
| `retryStrategy` | v1alpha1RetryStrategy |  |
| `revision` | string | 目标 revision（与 name 二选一） |
| `revisions` | array |  |
| `sourcePositions` | array |  |
| `strategy` | v1alpha1SyncStrategy | 同步策略：`hook` / `hook-delete` |
| `syncOptions` | applicationSyncOptions | 同步选项，如 `Replace=true`、`PruneLast=true` |

### 3.3 回滚

`POST /api/v1/applications/{name}/rollback` —— body 为 `applicationApplicationRollbackRequest`：

| 字段 | 类型 | 说明 |
|---|---|---|
| `appNamespace` | string |  |
| `dryRun` | boolean | dry-run |
| `id` | integer | 要回滚到的部署 ID（history 中的 id） |
| `name` | string |  |
| `project` | string |  |
| `prune` | boolean | 是否 prune |

### 3.4 列表过滤参数

`GET /api/v1/applications` 的 query 参数：

| 参数 | 类型 | 说明 |
|---|---|---|
| `name` | string | 按应用名过滤 |
| `projects` / `project` | string[] | 按项目过滤 |
| `selector` | string | 标签选择器，如 `env=prod` |
| `repo` | string | 按仓库 URL 过滤 |
| `appNamespace` | string | 应用所在 namespace |
| `resourceVersion` | string | 资源版本，用于一致性读 |
| `refresh` | string | `normal` / `hard`，顺带触发刷新 |

`GET /api/v1/applications/{name}/manifests` 的 query 参数：

| 参数 | 类型 | 说明 |
|---|---|---|
| `revision` | string | 指定 revision |
| `revisions` / `sourcePositions` | string[] | 多源场景 |
| `noCache` | boolean | 跳过 manifest 缓存 |
| `appNamespace` / `project` | string | 归属校验 |

`GET /api/v1/applications/{name}/resource` 的 query 参数：

| 参数 | 类型 | 说明 |
|---|---|---|
| `resourceName` | string | 资源名 |
| `namespace` | string | 资源 namespace |
| `group` / `kind` / `version` | string | 资源类型 |
| `appNamespace` / `project` | string | 归属校验 |

`GET /api/v1/applications/{name}/logs` 的 query 参数：

| 参数 | 类型 | 说明 |
|---|---|---|
| `group` / `kind` / `resourceName` | string | 按资源定位 Pod |
| `namespace` / `podName` / `container` | string | 直接指定 Pod |
| `follow` | boolean | 持续跟随输出 |
| `tailLines` | string | 末尾行数 |
| `sinceSeconds` / `sinceTime` / `untilTime` | string | 时间范围 |
| `previous` | boolean | 读上一个容器（崩溃排查） |
| `filter` / `matchCase` | string/bool | 日志行过滤 |

---

## 4. 非 swagger 的运行时路由

这些路径在 `swagger.json` 里查不到，由 `server/server.go` 直接注册。

| 路径 | 方法 | 说明 |
|---|---|---|
| `/api/webhook` | POST | 接收 GitHub / GitLab / Bitbucket 等 Git Webhook，触发应用刷新 |
| `/api/badge` | GET | 应用状态徽章（SVG）。query：`namespace`、`name`、`project`、`revision`、`width`、`showAppName`、`keepFullRevision` |
| `/api/dex/` | * | 反向代理到内置 Dex（OIDC provider） |
| `/auth/login` | GET | SSO 登录入口，重定向到 Dex/OIDC 授权页 |
| `/auth/callback` | GET | OIDC 登录回调 |
| `/auth/logout` | GET | OIDC 登出，使会话失效 |
| `/terminal` | GET (WS) | Web 终端，exec 进入 Pod。需开启 `exec.enabled` |
| `/extensions/` | * | Proxy Extensions 代理入口（需认证） |
| `/extensions.js` | GET | 前端扩展清单 |
| `/swagger.json` | GET | 官方接口定义（本文件的数据源） |
| `/swagger-ui` | GET | ReDoc 文档页面 |
| `/healthz` | GET | 健康检查，异常时返回 503 |
| `/metrics` | GET | Prometheus 指标，**在 8083 端口** |
| `/download/argocd-linux-<arch>` | GET | 下载 CLI 二进制 |

---

## 5. gRPC Service

REST 接口由 gRPC-Gateway 转发而来，同一份 `v1alpha1` 类型定义同时用于 gRPC。argocd-server 的 443 端口同时支持 gRPC。

| Service | 方法数 | 对应 REST 前缀 |
|---|---|---|
| `VersionService` | 1 | `/api/version` |
| `SessionService` | 3 | `/api/v1/session` |
| `SettingsService` | 2 | `/api/v1/settings` |
| `AccountService` | 6 | `/api/v1/account` |
| `ApplicationService` | 32 | `/api/v1/applications` |
| `ApplicationSetService` | 8 | `/api/v1/applicationsets` |
| `ProjectService` | 12 | `/api/v1/projects` |
| `ClusterService` | 7 | `/api/v1/clusters` |
| `RepositoryService` | 17 | `/api/v1/repositories` |
| `RepoCredsService` | 8 | `/api/v1/repocreds` |
| `CertificateService` | 3 | `/api/v1/certificates` |
| `GPGKeyService` | 4 | `/api/v1/gpgkeys` |
| `NotificationService` | 3 | `/api/v1/notifications` |

---

## 6. 调用示例

```bash
# 1) 登录换 token（免认证）
TOKEN=$(curl -sk https://argocd.example.com/api/v1/session \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<password>"}' | jq -r .token)

# 2) 之后统一带 Bearer
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://argocd.example.com/api/v1/applications | jq -r '.items[].metadata.name'

# 3) 触发同步（prune 掉不再声明的资源）
curl -sk -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  https://argocd.example.com/api/v1/applications/myapp/sync -d '{"prune":true}'

# 4) 预览 diff（服务端 dry-run）
curl -sk -H "Authorization: Bearer $TOKEN" \
  'https://argocd.example.com/api/v1/applications/myapp/server-side-diff'

# 5) 权限预判（can-i）
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://argocd.example.com/api/v1/account/can-i/sync/applications/default%2Fmyapp

# 6) 拉取 Pod 日志（按资源类型定位，推荐）
curl -sk -N -H "Authorization: Bearer $TOKEN" \
  'https://argocd.example.com/api/v1/applications/myapp/logs?group=apps&kind=Deployment&resourceName=myapp&tailLines=100'

# 7) 监听应用变更（流式）
curl -skN -H "Authorization: Bearer $TOKEN" \
  https://argocd.example.com/api/v1/stream/applications
```

### 用项目角色 Token 做最小权限集成

```bash
# 在 Argo CD UI: 项目 → 角色 → 新建 Token（可选指定过期时间）
# 得到的 token 只具备该项目的该角色权限
curl -sk -H "Authorization: Bearer <project-role-token>" \
  https://argocd.example.com/api/v1/applications?project=myproject
```

---

## 7. 注意事项

1. **流式接口**（`/stream/*`、`/logs`）返回按行分隔的 JSON（形如 `{"result": {...}}`），客户端必须按流读取；反向代理不能缓冲，且 read timeout 要放长（`proxy_read_timeout` 建议 ≥ 3600s）。
2. **路径参数含斜杠必须编码**：`{id.value}`（集群 server URL）、`{repo}`（仓库 URL）编码后形如 `https%3A%2F%2Fkubernetes.default.svc`。
3. **`PUT` 是全量语义**：`PUT /api/v1/applications/{name}` 会用请求体覆盖整个 Application，改单个字段请用 `PATCH` 或 `PUT .../spec`。
4. **`POST .../resource` 实际是 patch**：`PATCH /api/v1/applications/{name}/resource` 走的是 `POST` 动词，别被命名误导。
5. **`DELETE` 默认不删资源**：`DELETE /api/v1/applications/{name}` 只删 Application CR，要连带删除受管资源必须显式加 `?cascade=true`。
6. **`GET /api/v1/applications/{name}?refresh=hard` 会真正拉 Git 并重建 manifest**，代价高，CI 里慎用；`normal` 只刷新缓存。
7. **稳定性**：这些接口是 UI 和 CLI 自己也在用的内部 API，没有 K8s API 那样的兼容性承诺。跨大版本升级前，建议 diff 两个 tag 的 `assets/swagger.json`：

```bash
for v in v3.4.0 v3.5.6; do
  curl -sSL https://raw.githubusercontent.com/argoproj/argo-cd/$v/assets/swagger.json -o swagger-$v.json
done
jq -r '.paths | keys[]' swagger-v3.4.0.json | sort > p-old.txt
jq -r '.paths | keys[]' swagger-v3.5.6.json | sort > p-new.txt
diff p-old.txt p-new.txt
```

8. **服务端自带的校验**：`argocd-cm` 的 `resource.customizations`、project 的 `orphanedResources` 白名单等会在同步时生效，API 返回 200 不代表集群状态一定符合预期，建议再读一次 `status` 校验。

