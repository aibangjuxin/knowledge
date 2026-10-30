我先直接从 Argo CD 源码仓库拉取 v3.5.6 对应的 swagger.json，用官方定义来整理接口清单。

# Argo CD v3.5.6 API 接口清单

## 问题分析

`/api/version` 本身只返回版本信息，不会列出接口。官方的接口定义在源码的 `assets/swagger.json` 里。我直接拉取了 **v3.5.6 tag** 的这份文件，再对照 `server/server.go` 核对了 swagger 之外手写注册的路由。

结论：

| 类别 | 数量 |
|------|------|
| REST 接口（swagger 中，13 个 Service） | **106 个操作 / 82 个路径** |
| 非 swagger 的手写路由 | 约 10 个 |

所有 REST 接口都在 `/api/v1/` 下，只有 `/api/version` 例外。

## 一、REST API（swagger 定义）

### 1. VersionService（1）

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/version` | 返回 API Server 版本信息，无需认证 |

### 2. SessionService（3）

| 方法 | 路径 | 功能 |
|------|------|------|
| POST | `/api/v1/session` | 用用户名密码换取 JWT，同时 Set-Cookie |
| DELETE | `/api/v1/session` | 删除会话 Cookie（登出） |
| GET | `/api/v1/session/userinfo` | 获取当前登录用户信息（是否登录、用户名、groups） |

### 3. SettingsService（2）

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/settings` | 获取 Argo CD 全局设置（URL、OIDC/Dex 配置、状态徽章、exec 开关等） |
| GET | `/api/v1/settings/plugins` | 获取已配置的 Config Management Plugin 列表 |

### 4. AccountService（6）

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/account` | 列出所有本地账号 |
| GET | `/api/v1/account/{name}` | 获取指定账号详情 |
| PUT | `/api/v1/account/password` | 修改账号密码 |
| GET | `/api/v1/account/can-i/{resource}/{action}/{subresource}` | 检查当前账号是否有某操作权限，返回 yes/no |
| POST | `/api/v1/account/{name}/token` | 为账号创建 API Token |
| DELETE | `/api/v1/account/{name}/token/{id}` | 删除账号 Token |

### 5. ApplicationService（32）

**CRUD**

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/applications` | 列出应用，支持 `name`/`projects`/`selector`/`repo` 等过滤 |
| POST | `/api/v1/applications` | 创建应用 |
| GET | `/api/v1/applications/{name}` | 获取应用详情，`?refresh=normal\|hard` 可触发刷新 |
| PUT | `/api/v1/applications/{application.metadata.name}` | 整体更新应用 |
| PUT | `/api/v1/applications/{name}/spec` | 仅更新 spec |
| PATCH | `/api/v1/applications/{name}` | Patch 应用（JSON/Merge Patch） |
| DELETE | `/api/v1/applications/{name}` | 删除应用，`?cascade=` 控制是否级联删资源 |

**同步 / 回滚 / 操作**

| 方法 | 路径 | 功能 |
|------|------|------|
| POST | `/api/v1/applications/{name}/sync` | 触发同步（可指定 revision、prune、dryRun、resources 等） |
| POST | `/api/v1/applications/{name}/rollback` | 回滚到历史部署 ID |
| DELETE | `/api/v1/applications/{name}/operation` | 终止正在运行的 sync/rollback 操作 |

**状态 / 资源树 / 清单**

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/applications/{applicationName}/resource-tree` | 获取资源树 |
| GET | `/api/v1/applications/{applicationName}/managed-resources` | 获取受管资源列表（含 live/target 状态，用于 diff） |
| GET | `/api/v1/applications/{appName}/server-side-diff` | 服务端 dry-run apply 方式计算 diff |
| GET | `/api/v1/applications/{name}/manifests` | 获取渲染后的目标清单 |
| POST | `/api/v1/applications/manifestsWithFiles` | 以流方式上传本地文件，渲染清单 |
| GET | `/api/v1/applications/{name}/events` | 获取应用相关 K8s Event |
| GET | `/api/v1/applications/{name}/syncwindows` | 获取应用适用的 sync window |

**单个资源操作**

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/applications/{name}/resource` | 获取应用内某个资源的 live manifest |
| POST | `/api/v1/applications/{name}/resource` | Patch 某个资源（接口命名如此，实为 patch） |
| DELETE | `/api/v1/applications/{name}/resource` | 删除某个资源 |
| GET | `/api/v1/applications/{name}/resource/actions` | 列出资源可用的 Resource Action（如 Rollout restart） |
| POST | `/api/v1/applications/{name}/resource/actions` | 执行 Resource Action |
| POST | `/api/v1/applications/{name}/resource/actions/v2` | 执行 Resource Action，支持传参数 |

**日志**

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/applications/{name}/logs` | 流式日志，按 group/kind/resourceName 选 Pod（推荐） |
| GET | `/api/v1/applications/{name}/pods/{podName}/logs` | 流式获取指定 Pod 日志，较早的写法 |

**Revision 元数据**

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/applications/{name}/revisions/{revision}/metadata` | 获取 commit 作者、时间、message、tags |
| GET | `/api/v1/applications/{name}/revisions/{revision}/chartdetails` | 获取 Helm Chart 元数据 |
| GET | `/api/v1/applications/{name}/revisions/{revision}/ocimetadata` | 获取 OCI 制品元数据 |

**Deep Links / Watch**

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/applications/{name}/links` | 应用级 Deep Link 列表 |
| GET | `/api/v1/applications/{name}/resource/links` | 资源级 Deep Link 列表 |
| GET | `/api/v1/stream/applications` | **流**：监听应用变更事件 |
| GET | `/api/v1/stream/applications/{applicationName}/resource-tree` | **流**：监听资源树变化 |

### 6. ApplicationSetService（8）

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/applicationsets` | 列出 ApplicationSet |
| POST | `/api/v1/applicationsets` | 创建 ApplicationSet |
| GET | `/api/v1/applicationsets/{name}` | 获取详情 |
| DELETE | `/api/v1/applicationsets/{name}` | 删除 |
| POST | `/api/v1/applicationsets/generate` | 预览：根据 ApplicationSet 生成 Application 列表，不落地 |
| GET | `/api/v1/applicationsets/{name}/events` | 获取相关 Event |
| GET | `/api/v1/applicationsets/{name}/resource-tree` | 获取资源树 |
| GET | `/api/v1/stream/applicationsets` | **流**：监听 ApplicationSet 变更 |

### 7. ProjectService（12）

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/projects` | 列出项目 |
| POST | `/api/v1/projects` | 创建项目 |
| GET | `/api/v1/projects/{name}` | 获取项目 |
| PUT | `/api/v1/projects/{project.metadata.name}` | 更新项目 |
| DELETE | `/api/v1/projects/{name}` | 删除项目 |
| GET | `/api/v1/projects/{name}/detailed` | 获取项目详情，含 global project 与关联资源 |
| GET | `/api/v1/projects/{name}/globalprojects` | 获取继承的 global project（虚拟项目） |
| GET | `/api/v1/projects/{name}/events` | 项目 Event |
| GET | `/api/v1/projects/{name}/links` | 项目 Deep Link |
| GET | `/api/v1/projects/{name}/syncwindows` | 当前 sync window 状态 |
| POST | `/api/v1/projects/{project}/roles/{role}/token` | 创建项目角色 Token |
| DELETE | `/api/v1/projects/{project}/roles/{role}/token/{iat}` | 删除项目角色 Token（以签发时间 `iat` 标识） |

### 8. ClusterService（7）

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/clusters` | 列出已注册集群 |
| POST | `/api/v1/clusters` | 注册集群 |
| GET | `/api/v1/clusters/{id.value}` | 获取集群，`id.value` 为 server URL（需 URL 编码）或 name |
| PUT | `/api/v1/clusters/{id.value}` | 更新集群 |
| DELETE | `/api/v1/clusters/{id.value}` | 删除集群 |
| POST | `/api/v1/clusters/{id.value}/invalidate-cache` | 清除集群缓存，强制重新同步 |
| POST | `/api/v1/clusters/{id.value}/rotate-auth` | 轮换集群访问 Token |

### 9. RepositoryService（17）

**只读仓库**

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/repositories` | 列出仓库 |
| POST | `/api/v1/repositories` | 添加仓库 |
| GET | `/api/v1/repositories/{repo}` | 获取仓库 |
| PUT | `/api/v1/repositories/{repo.repo}` | 更新仓库 |
| DELETE | `/api/v1/repositories/{repo}` | 删除仓库 |
| POST | `/api/v1/repositories/{repo}/validate` | 校验仓库访问权限 |
| GET | `/api/v1/repositories/{repo}/apps` | 列出仓库中可识别的应用目录 |
| GET | `/api/v1/repositories/{repo}/helmcharts` | 列出 Helm Chart |
| GET | `/api/v1/repositories/{repo}/oci-tags` | 列出 OCI 仓库的 tags |
| GET | `/api/v1/repositories/{repo}/refs` | 列出 Git 分支和 tags |
| POST | `/api/v1/repositories/{source.repoURL}/appdetails` | 获取某路径下应用详情（类型、Helm values、参数等） |

**Write 仓库**（用于 Source Hydrator 回写，3.x 新增）

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/write-repositories` | 列出 |
| POST | `/api/v1/write-repositories` | 添加 |
| GET | `/api/v1/write-repositories/{repo}` | 获取 |
| PUT | `/api/v1/write-repositories/{repo.repo}` | 更新 |
| DELETE | `/api/v1/write-repositories/{repo}` | 删除 |
| POST | `/api/v1/write-repositories/{repo}/validate` | 校验写权限 |

### 10. RepoCredsService（8）

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/repocreds` | 列出凭据模板（按 URL 前缀匹配） |
| POST | `/api/v1/repocreds` | 创建凭据模板 |
| PUT | `/api/v1/repocreds/{creds.url}` | 更新 |
| DELETE | `/api/v1/repocreds/{url}` | 删除 |
| GET | `/api/v1/write-repocreds` | 列出写权限凭据模板 |
| POST | `/api/v1/write-repocreds` | 创建 |
| PUT | `/api/v1/write-repocreds/{creds.url}` | 更新 |
| DELETE | `/api/v1/write-repocreds/{url}` | 删除 |

### 11. CertificateService（3）

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/certificates` | 列出仓库 TLS/SSH known_hosts 证书 |
| POST | `/api/v1/certificates` | 添加证书 |
| DELETE | `/api/v1/certificates` | 按查询条件（hostNamePattern、certType 等）删除 |

### 12. GPGKeyService（4）

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/gpgkeys` | 列出 GPG 公钥 |
| POST | `/api/v1/gpgkeys` | 添加公钥 |
| DELETE | `/api/v1/gpgkeys` | 删除公钥（`?keyID=`） |
| GET | `/api/v1/gpgkeys/{keyID}` | 获取单个公钥信息 |

### 13. NotificationService（3）

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/notifications/services` | 列出已配置的通知服务 |
| GET | `/api/v1/notifications/templates` | 列出通知模板 |
| GET | `/api/v1/notifications/triggers` | 列出通知触发器 |

## 二、非 swagger 的手写路由

这些接口在 swagger 里查不到，是 `server.go` 中直接注册的。

| 路径 | 功能 |
|------|------|
| `/api/webhook` | 接收 GitHub/GitLab/Bitbucket 等 Git Webhook，触发应用刷新 |
| `/api/badge` | 应用状态徽章（SVG），需在设置里启用 |
| `/auth/login` | SSO 登录入口（重定向到 Dex/OIDC） |
| `/auth/callback` | OIDC 登录回调 |
| `/auth/logout` | OIDC 登出 |
| `/api/dex/` | 反向代理到内置 Dex |
| `/terminal` | WebSocket，Web 终端（exec 进入 Pod），需启用 exec 功能 |
| `/extensions/` | Proxy Extensions 代理入口（需认证） |
| `/download/argocd-linux-<arch>` | 下载 CLI 二进制 |
| `/healthz` | 健康检查 |
| `/swagger-ui` | Swagger UI 页面 |

另外，Metrics 不在主端口：API Server 的 metrics 在 **8083**，Application Controller 的在 **8082**。

## 三、调用示例

```bash
# 1. 登录换 token（不需要认证）
TOKEN=$(curl -sk https://argocd.example.com/api/v1/session \
  -d '{"username":"admin","password":"<password>"}' | jq -r .token)

# 2. 之后统一带 Bearer
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://argocd.example.com/api/v1/applications | jq '.items[].metadata.name'

# 3. 触发同步
curl -sk -X POST -H "Authorization: Bearer $TOKEN" \
  https://argocd.example.com/api/v1/applications/myapp/sync \
  -d '{"prune":true}'

# 4. 检查当前账号权限
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://argocd.example.com/api/v1/account/can-i/sync/applications/default%2Fmyapp
```

在你自己的集群上，可以导出实际运行的版本对应的接口定义，用来做二次确认：

```bash
# 浏览器访问 Swagger UI
kubectl -n argocd port-forward svc/argocd-server 8080:443
# https://localhost:8080/swagger-ui

# 或者直接拉取对应 tag 的定义文件
curl -sSL https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/assets/swagger.json -o argocd-swagger.json
```

## 四、注意事项

- **认证**：除 `/api/version`、`POST /api/v1/session`、`GET /api/v1/settings`、`/healthz` 等少数接口外，其余都需要 `Authorization: Bearer <JWT>`，或 Cookie `argocd.token`。自动化场景建议用账号 Token（`POST /account/{name}/token`），需要先在 `argocd-cm` 里给账号开 `apiKey` 能力。
- **多 namespace 应用**：如果启用了 Apps in any namespace，应用相关接口要加 `?appNamespace=<ns>`，否则默认只在 Argo CD 所在 namespace 查找。
- **项目隔离**：很多应用接口支持 `?project=<name>` 做校验，传错会返回权限错误。
- **流式接口**（`/stream/*`、`/logs`）：返回按行分隔的 JSON（`{"result": {...}}`），需要客户端按流读取，并且代理层不能缓冲或设置过短的超时。
- **路径参数里的 `/`**：集群 server URL、仓库 URL 作为 `{id.value}`、`{repo}` 时必须 URL 编码，例如 `https%3A%2F%2Fkubernetes.default.svc`。
- **RBAC**：每个接口都会按 `argocd-rbac-cm` 里的策略检查，`can-i` 接口可以在调用前先做预判。
- **稳定性**：swagger 里这些接口是 UI 和 CLI 自己使用的，兼容性上没有像 K8s API 那样严格的保证。跨大版本升级前，建议拿新旧两个 tag 的 `swagger.json` 做一次 diff。

