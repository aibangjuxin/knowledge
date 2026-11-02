# Argo CD CLI 实战手册（v3.5.6）

> 适用范围：本目录 `install.yaml` 中部署的 **Argo CD v3.5.6**。
> 配套文档：[`argo-api-claude.md`](./argo-api-claude.md)（REST API 清单）、[`argocd-admin-guide.md`](./argocd-admin-guide.md)（架构与管理手册）。
> 命令与参数均以 v3.5.6 tag 的官方 CLI 参考（`docs/user-guide/commands/`）逐条核对过。

---

## 0. 先说清楚三件事

### 0.1 CLI 不是"另一套接口"，而是 API 的同源客户端

```
                    ┌──────────────────────────────┐
                    │        Argo CD Server        │
  Web UI  ─gRPC-Web┼─▶  ApplicationService        │
  CLI     ─gRPC-Web┼─▶  ProjectService / ...      │
  REST   ─HTTP/JSON┼─▶  (同一套 Service 定义)      │
  kubectl ─K8s API▶│  Controller / Repo-Server    │
                    └──────────────────────────────┘
```

- **Web UI 和 CLI 走的是同一套 gRPC-Web Service**；`argo-api-claude.md` 里的 `/api/v1/**` REST 路径，是同一套 Service 的 HTTP/JSON 传输形式。
- 所以：**CLI 能做的事 = UI 能做的事 = REST API 能做的事**（除去个别纯 UI 能力）。
- 绝大多数 CLI 命令最终落到这些 Service：`ApplicationService`、`ApplicationSetService`、`ProjectService`、`ClusterService`、`RepositoryService`、`RepoCredsService`、`AccountService`、`CertificateService`、`GPGKeyService`、`SessionService`。

### 0.2 两条执行通道

| 模式 | 触发方式 | 行为 | 用途 |
|------|----------|------|------|
| **API Server 模式**（默认） | `argocd app list` | 调用 `argocd-server` 的 API Server | 日常操作、CI/CD、审计走这条 |
| **Core 模式** | 加 `--core` | **绕过 API Server**，CLI 直接读写 Kubernetes | API Server 挂了但仍要救火；只支持部分 app 子命令 |

```bash
argocd app list --core          # 不依赖 argocd-server，只读 K8s
argocd app get myapp --core     # 支持
argocd app sync --core          # 不支持（sync 必须经由 Server 触发操作）
```

### 0.3 版本必须对齐

CLI 是 gRPC 客户端，**低版本 CLI 连高版本 Server 通常没问题，高版本 CLI 连低版本 Server 会报 unknown field / unsupported**。

```bash
# 1) 查 Server 版本
curl -sk https://argocd.example.com/api/version
# {"Version":"v3.5.6+..."}

# 2) 查 CLI 版本
argocd version --client

# 3) 三者对齐
kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}'
# quay.io/argoproj/argocd:v3.5.6
```

安装（版本号与集群保持一致）：

```bash
# macOS
brew install argocd

# Linux / 任意平台（推荐，版本可控）
VERSION=v3.5.6
curl -sSL -o argocd \
  "https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-amd64"
install -m 0755 argocd /usr/local/bin/argocd

# 不想装本地？argocd 镜像自带 CLI
kubectl -n argocd exec deploy/argocd-server -- which argocd
kubectl -n argocd exec deploy/argocd-server -- argocd version --client
```

---

## 1. 连接与认证

### 1.1 三种连接方式

```bash
# A) 直连 Server（生产常用）
argocd login argocd.example.com --username admin --password 'xxx' --insecure

# B) SSO
argocd login argocd.example.com --sso

# C) 端口转发（开发/内网常用，无需暴露入口）
argocd login argocd.example.com --port-forward
```

登录成功后，凭证写入本地配置 `~/.config/argocd/config`（可用 `--config` 指定），其中保存 server 地址与 token。

### 1.2 全局（父命令级）参数速查

这些参数对**所有**子命令生效，是最常被忽略的部分：

| 参数 | 用途 | 典型场景 |
|------|------|----------|
| `--server` | Argo CD Server 地址 | CI 里动态指定 |
| `--auth-token` / `ARGOCD_AUTH_TOKEN` | Bearer Token | **CI/CD 首选** |
| `--client-crt` / `--client-crt-key` | mTLS 客户端证书 | Server 侧强制 mTLS |
| `--server-crt` | 自签 CA 证书 | 内网私有 CA |
| `--insecure` / `--plaintext` | 跳过证书校验 / 关闭 TLS | 临时排障，**不要**用于生产 |
| `--grpc-web` / `--grpc-web-root-path` | 走 gRPC-Web 及 Web Root | 前面是 nginx/ALB 时需要 |
| `--port-forward` / `--port-forward-namespace` | 自动 port-forward 到 Server | 内网免暴露 |
| `--core` | 直连 Kubernetes，不走 API Server | Server 故障时 |
| `--kube-context` | 指定 kubeconfig context | 多集群 |
| `--argocd-context` | 指定 Argo CD context（多 Server） | 同一台机器连多个 Argo CD |
| `-H, --header` | 追加自定义 HTTP 头 | 透传 tracing header、租户标识 |
| `--http-retry-max` | 建连重试次数 | 弱网环境 |
| `--loglevel` / `--logformat` | 日志级别与格式（默认 json） | 调试 |
| `--prompts-enabled` | 强制开/关交互提示 | 无人值守必须显式关 |

> **`--prompts-enabled=false` 是所有 CI 脚本的必备项**，否则交互式命令（`sync` 确认、`delete` 确认）会挂住。

### 1.3 Token 与 Service Account

```bash
# 交互式登录后，生成一个长期 Token（给人用）
argocd account generate-token --account my-user --expires-in 720h

# 用 Token 直接调 CLI（CI 用）
export ARGOCD_SERVER=argocd.example.com
export ARGOCD_AUTH_TOKEN=eyJhbGciOi...
argocd app list -o name
```

项目角色 Token（绑定 AppProject RBAC，用于流水线，见 `argocd-admin-guide.md` §2.4）：

```bash
argocd login argocd.example.com --username proj-role-user --password 'xxx'
argocd account session-token
```

### 1.4 context 管理

```bash
argocd context list              # 列出已保存的 Argo CD context
argocd configure                 # 交互式配置（server / auth / namespace 等）
argocd logout                    # 清理当前 context 的 token
argocd relogin                   # 刷新过期 token（SSO 场景常用）
```

### 1.5 权限预检

调用前先问 RBAC，避免"看起来是 NotFound 其实是 PermissionDenied"：

```bash
argocd account can-i sync applications 'default/myapp'
argocd account can-i update applications 'default/*'
argocd account get-user-info
```

对应 REST：`GET /api/v1/account/can-i/{resource}/{action}/{subresource}`。

---

## 2. 命令树全清单（v3.5.6）

```
argocd
├── account      账号管理（list/get/generate-token/delete-token/update-password/bcrypt/can-i/get-user-info/session-token）
├── admin        管理员命令（需直连 K8s）
│   ├── app          diff-reconcile-results / generate-spec / get-reconcile-results
│   ├── cluster      generate-spec / kubeconfig / namespaces / shards / stats
│   ├── proj         generate-allow-list / generate-spec / update-role-policy
│   ├── repo         generate-spec
│   ├── notifications
│   ├── settings
│   ├── export / import          整体备份与恢复
│   ├── dashboard                本地拉起 Web UI
│   ├── initial-password
│   └── redis-initial-password
├── app          应用管理（最常用）
│   ├── list / get / create / set / unset / edit / patch / delete
│   ├── sync / wait / terminate-op / rollback / history
│   ├── diff / manifests / resources / logs
│   ├── actions (list/run)、get-resource / patch-resource / delete-resource
│   ├── add-source / remove-source / confirm-deletion
├── appset       ApplicationSet（create/delete/generate/get/list）
├── cert         仓库证书与 SSH known_hosts（add-tls/add-ssh/list/rm）
├── cluster      集群凭据（add/get/list/rm/set/rotate-auth）
├── completion   shell 补全（bash/zsh/fish）
├── configure    本地配置
├── context      context 切换
├── gpg          GPG 公钥（add/get/list/rm）
├── login / logout / relogin
├── proj         项目（create/delete/edit/get/list/set/add-source/add-destination/
│               allow-*/deny-*/remove-*/windows/role/source-integrity）
├── repo         仓库连接（add/get/list/rm）
├── repocreds    仓库凭据模板（add/list/rm）
└── version
```

---

## 3. `argocd app`：日常运维主战场

### 3.1 查状态

```bash
argocd app list                              # wide 表格（默认）
argocd app list -o name                      # 只要名字，适合脚本
argocd app list -o json | jq '.items[].metadata.name'
argocd app list -p team-a                    # 按项目过滤
argocd app list -l app.kubernetes.io/instance=root   # 按 label 过滤
argocd app list -c prod-cluster              # 按目标集群过滤
argocd app list -r https://github.com/org/repo.git     # 按仓库过滤

argocd app get myapp                         # 详情（wide）
argocd app get myapp -o yaml                 # 完整 spec（= REST GET application）
argocd app get myapp --show-operation        # 当前正在跑的 sync/rollback
argocd app get myapp --show-params           # 参数覆盖情况
argocd app get myapp --refresh               # 强制刷新（读集群实时状态）
argocd app get myapp --hard-refresh          # 连目标 manifest 缓存一起刷新
argocd app get myapp -o tree=detailed        # 资源树 + AGE/HEALTH/REASON

argocd app resources myapp -o tree=detailed  # 资源层级
argocd app resources myapp --orphaned        # 只看孤儿资源（prune 风险排查）
argocd app history myapp                     # 部署历史（回滚要用 ID）
```

> `--refresh` / `--hard-refresh` 映射到 REST 的 `?refresh=normal|hard`。

### 3.2 看差异（最安全的"能不能发"判断）

```bash
argocd app diff myapp
argocd app diff myapp --revision main        # 对比某个 commit
argocd app diff myapp --local ./manifests    # 本地清单 vs 集群
argocd app diff myapp --server-side-diff     # 用 server-side dry-run 算差异
```

**退出码语义**（脚本里很好用）：

| 退出码 | 含义 |
|--------|------|
| `0` | 无差异 |
| `1` | 有差异（可用 `--diff-exit-code N` 改） |
| `2` | 通用错误 |

```bash
# 典型门禁：有差异就阻断流水线（1=有差异，2=执行出错，0=无差异）
set +e
argocd app diff myapp --diff-exit-code 20 >/dev/null
rc=$?
set -e
if [ "$rc" -eq 20 ]; then
  echo "存在漂移，终止发布"; exit 1
elif [ "$rc" -ne 0 ]; then
  echo "diff 执行异常"; exit 2
fi
```

### 3.3 发布 / 同步

```bash
# 最常见：同步到 Git 里声明的状态
argocd app sync myapp

# 常用组合
argocd app sync myapp --prune                # 允许删除 Git 里已不存在的资源
argocd app sync myapp --revision abc123      # 固定版本
argocd app sync myapp --dry-run              # 只预览
argocd app sync myapp --preview-changes      # 预览 + 交互确认（CI 需配 --prompts-enabled=false）
argocd app sync myapp --server-side          # server-side apply
argocd app sync myapp --replace              # kubectl create/replace 语义
argocd app sync myapp --async                # 不等待完成

# 批量
argocd app sync -l app.kubernetes.io/part-of=prod
argocd app sync -p team-a team-b

# 只同步部分资源（GROUP:KIND:NAME）
argocd app sync myapp --resource apps:Deployment:api
argocd app sync myapp --resource '!*:Service:*'

# 多源应用：按 source 位置/名字指定版本
argocd app sync myapp --revisions 0.0.1 --source-positions 1 \
                       --revisions 0.0.2 --source-positions 2
argocd app sync myapp --revisions 0.0.1 --source-names my-chart
```

**失败重试**（v3.x 起 sync 支持退避重试）：

```bash
argocd app sync myapp \
  --retry-limit 3 \
  --retry-backoff-duration 30s \
  --retry-backoff-factor 2 \
  --retry-backoff-max-duration 5m \
  --retry-refresh
```

> `--prune` 是删除生产资源的动作。CLI 侧只是"允许"，真正删除由 controller 执行。请配合 AppProject 的资源白名单约束。

### 3.4 等状态（流水线收尾）

```bash
argocd app wait myapp                        # 默认等 Synced + Healthy
argocd app wait myapp --sync --health --operation --timeout 300
argocd app wait -l app.kubernetes.io/part-of=prod --timeout 600
```

| 等待条件 | 含义 |
|----------|------|
| `--sync` | 期望状态与实际一致 |
| `--health` | 健康检查通过 |
| `--operation` | 没有正在运行的操作 |
| `--hydrated` | Source Hydrator 完成（3.x） |
| `--degraded` / `--suspended` / `--delete` | 等待进入对应状态（用于下线流程） |

### 3.5 日志

```bash
argocd app logs myapp
argocd app logs myapp -f                              # 跟随
argocd app logs myapp --tail 100
argocd app logs myapp --since-seconds 3600
argocd app logs myapp --until-time "2026-10-30T15:30:00Z"
argocd app logs myapp --filter "error" --match-case
argocd app logs myapp -c my-container
argocd app logs myapp --previous                      # 已终止容器的日志（排查 CrashLoop）
argocd app logs myapp --kind Deployment --name api --namespace prod
```

> `argocd app logs` 走的是 REST 的流式接口 `/api/v1/applications/{name}/logs`，返回按行分隔 JSON，**代理层不能缓冲**（Nginx `proxy_buffering off`、ALB idle timeout ≥ 60s）。

### 3.6 回滚

```bash
argocd app history myapp                # 找到 ID
argocd app rollback myapp 12            # 回滚到第 12 次部署
argocd app rollback myapp               # 回滚到上一个版本
argocd app rollback myapp 12 --prune    # 回滚时也允许删除多余资源
```

对应 REST：`POST /api/v1/applications/{name}/rollback`。

### 3.7 Resource Action（重启 / 重跑 Hook）

```bash
argocd app actions list myapp
argocd app actions run myapp restart --kind Deployment --resource-name api --namespace prod
```

对应 REST：`GET/POST /api/v1/applications/{name}/resource/actions`（带参数用 `/actions/v2`）。

### 3.8 单个资源的读 / 改 / 删

```bash
argocd app get-resource myapp --resource-name api --kind Deployment --namespace prod
argocd app patch-resource myapp --resource-name api --kind Deployment \
  --namespace prod --type merge -p '{"spec":{"replicas":3}}'
argocd app delete-resource myapp --resource-name api --kind Deployment --namespace prod
```

> `patch-resource` 属于**临时改动**，GitOps 下会被下一次 sync 打回。要持久化，必须改 Git。

### 3.9 创建 / 修改应用

```bash
# 从 Helm 仓库创建
argocd app create myapp \
  --repo https://charts.helm.sh/stable \
  --helm-chart nginx-ingress \
  --revision 1.24.3 \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace prod \
  --project team-a \
  --sync-policy automated --self-heal --auto-prune

# 从 Git 目录创建
argocd app create myapp --repo https://github.com/org/repo.git --path apps/myapp \
  --dest-server https://kubernetes.default.svc --dest-namespace prod

# 从 YAML/URL 声明式创建（推荐：与 GitOps 一致）
argocd app create myapp -f ./myapp.yaml --upsert

# 参数覆盖（临时）
argocd app set myapp -p image.tag=v1.2.3
argocd app unset myapp -p image.tag

# 改 spec
argocd app edit myapp                       # 交互式编辑
argocd app patch myapp --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true}}}}'

# 多源应用增删 source
argocd app add-source myapp --repo https://github.com/org/values.git --path values --source-name values
argocd app remove-source myapp --source-name values

# 删除
argocd app delete myapp
argocd app delete myapp --cascade            # 级联删除目标集群上的资源
argocd app confirm-deletion myapp           # 配合 AppProject 的 deletion confirmation
```

> `argocd app create --upsert`：同名应用已存在时覆盖（spec 不同也会覆盖）。生产环境慎用。

### 3.10 终止正在进行的操作

```bash
argocd app terminate-op myapp
```

对应 REST：`DELETE /api/v1/applications/{name}/operation`。

---

## 4. `argocd appset`：批量应用

```bash
argocd appset list
argocd appset get my-appset
argocd appset create ./appset.yaml           # 也支持 URL
argocd appset delete my-appset
argocd appset generate my-appset             # 预览生成哪些 Application（不落地）
```

> `appset generate` 是排查"ApplicationSet 没生成应用"的第一把尺，对应 REST `POST /api/v1/applicationsets/generate`。

---

## 5. `argocd proj`：项目与权限边界

```bash
argocd proj list
argocd proj get team-a
argocd proj create team-a
argocd proj edit team-a
argocd proj delete team-a

argocd proj set team-a --description "Team A"
argocd proj add-source team-a --repo 'https://github.com/org/*'
argocd proj remove-source team-a --repo https://github.com/org/legacy
argocd proj add-destination team-a --server https://kubernetes.default.svc --namespace prod
argocd proj remove-destination team-a --server https://kubernetes.default.svc --namespace prod
argocd proj add-destination-service-account team-a --server https://kubernetes.default.svc \
  --namespace prod --serviceaccount deployer

argocd proj allow-namespace-resource team-a --group '*' --kind '*'
argocd proj deny-cluster-resource team-a --group '*' --kind '*'
argocd proj windows add team-a --schedule '* * * * *' --duration 1h
argocd proj role list team-a
```

> `argocd proj set` 生成的资源最终落在 `AppProject` CR 上；用 `argocd proj get team-a -o yaml` 可以核对 RBAC 里 `project` 字段与项目名是否一致。

---

## 6. `argocd cluster` / `argocd repo` / `argocd repocreds`：接入面

```bash
# 集群
argocd cluster list -o json
argocd cluster add prod-cluster                       # 取自当前 kubeconfig context
argocd cluster get prod-cluster -o wide
argocd cluster set prod-cluster --name new-name --namespace '*'
argocd cluster rm prod-cluster
argocd cluster rotate-auth prod-cluster              # v3.x：轮换集群访问凭据

# 仓库
argocd repo add https://github.com/org/repo.git --username git --password 'xxx'
argocd repo list
argocd repo get https://github.com/org/repo.git
argocd repo rm https://github.com/org/repo.git

# 凭据模板（按 URL 前缀匹配）
argocd repocreds add https://github.com --username git --password 'xxx'
argocd repocreds list
argocd repocreds rm https://github.com

# 证书与 GPG
argocd cert add-tls --from ./ca.pem git.internal
argocd cert add-ssh --batch git.internal < known_hosts
argocd cert list --cert-type https
argocd cert rm --cert-type https git.internal
argocd gpg add < public.asc
argocd gpg list
argocd gpg rm <KEYID>
```

> `argocd cluster add` 会在**目标集群**的 `kube-system` 下创建 `argocd-manager` SA（GKE 上建议改用 Workload Identity，见 `argocd-admin-guide.md` §7.8）。

---

## 7. `argocd admin`：需要直连 Kubernetes 的管理命令

```bash
argocd admin dashboard                 # 本地端口转发起 Web UI
argocd admin initial-password          # 打印初始 admin 密码
argocd admin redis-initial-password    # 确保 Redis 密码存在

argocd admin app generate-spec myapp -o yaml      # 生成声明式 Application
argocd admin app get-reconcile-results myapp       # 采集一次 reconcile 结果
argocd admin app diff-reconcile-results myapp      # 对比两次 reconcile 结果

argocd admin cluster generate-spec my-cluster -o yaml
argocd admin cluster kubeconfig my-cluster         # 导出目标集群 kubeconfig
argocd admin cluster namespaces my-cluster          # 每个集群被 Argo CD 管理的 namespace
argocd admin cluster shards                         # controller shard 分布
argocd admin cluster stats                          # 集群统计与推断 shard

argocd admin proj generate-spec team-a -o yaml
argocd admin proj update-role-policy team-a        # 批量补齐/清理项目角色策略
argocd admin proj generate-allow-list clusterrole.yaml

argocd admin repo generate-spec https://github.com/org/repo.git -o yaml
argocd admin settings                               # 设置校验与排障
argocd admin notifications
```

### 7.1 备份 / 恢复（比逐条 `kubectl get -o yaml` 更完整）

```bash
# 导出全部 Argo CD 数据
argocd admin export - > backup/argocd-$(date +%F).tar.gz

# 恢复
argocd admin import backup/argocd-2026-10-30.tar.gz --namespace argocd
```

### 7.2 生成声明式规格（GitOps 化的关键一步）

```bash
# 把 UI 里点出来的应用导出成 YAML，提交进 Git
argocd admin app generate-spec myapp -o yaml > gitops/apps/myapp.yaml

# 集群凭据转成 Secret 声明
argocd admin cluster generate-spec prod-cluster -o yaml > gitops/clusters/prod-cluster.yaml
```

> 有了这一步，"UI 后台操作"就能被完整搬到 Git 里，CLI 只负责**校验**（`app diff`）和**触发**（`app sync`），这才是 GitOps 的正确姿势。

---

## 8. CLI ↔ REST API 对照表

| CLI | REST API | 备注 |
|-----|-----------|------|
| `argocd login` | `POST /api/v1/session` | 换 JWT |
| `argocd account list` | `GET /api/v1/account` | |
| `argocd account generate-token` | `POST /api/v1/account/{name}/token` | 需 `argocd-cm` 开 `apiKey` |
| `argocd account can-i` | `GET /api/v1/account/can-i/...` | |
| `argocd app list` | `GET /api/v1/applications` | |
| `argocd app get` | `GET /api/v1/applications/{name}` | `--refresh` → `?refresh=normal` |
| `argocd app create` | `POST /api/v1/applications` | |
| `argocd app set/edit/patch` | `PUT/PATCH /api/v1/applications/{name}` | |
| `argocd app delete` | `DELETE /api/v1/applications/{name}` | `--cascade` → `?cascade=true` |
| `argocd app sync` | `POST /api/v1/applications/{name}/sync` | |
| `argocd app rollback` | `POST /api/v1/applications/{name}/rollback` | |
| `argocd app terminate-op` | `DELETE /api/v1/applications/{name}/operation` | |
| `argocd app diff` | `GET /api/v1/applications/{name}/managed-resources` + `server-side-diff` | |
| `argocd app manifests` | `GET /api/v1/applications/{name}/manifests` | `--source live` 走 live manifest |
| `argocd app resources` | `GET /api/v1/applications/{name}/resource-tree` | |
| `argocd app logs` | `GET /api/v1/applications/{name}/logs`（流式） | |
| `argocd app actions list/run` | `GET/POST .../resource/actions`（v2：`/actions/v2`） | |
| `argocd app get/patch/delete-resource` | `GET/POST/DELETE .../resource` | 注意路径是 `/resource` |
| `argocd appset list/get/create/delete` | `/api/v1/applicationsets` 系列 | |
| `argocd appset generate` | `POST /api/v1/applicationsets/generate` | |
| `argocd proj list/get/create/delete` | `/api/v1/projects` 系列 | |
| `argocd cluster list/get/add/rm` | `/api/v1/clusters` 系列 | URL 需 URL 编码 |
| `argocd cluster rotate-auth` | `POST /api/v1/clusters/{id}/rotate-auth` | |
| `argocd repo list/add/rm` | `/api/v1/repositories` 系列 | |
| `argocd repocreds list/add/rm` | `/api/v1/repocreds` 系列 | |
| `argocd cert list/add/rm` | `/api/v1/certificates` 系列 | |
| `argocd gpg list/add/rm` | `/api/v1/gpgkeys` 系列 | |

**没有 CLI 直接对应、但 REST 有的能力**（需要用 curl 或写脚本）：

- `GET /api/v1/applications/{name}/events`（K8s Event 列表）
- `GET /api/v1/applications/{name}/revisions/{rev}/metadata`（commit 作者/时间/tag）
- `GET /api/v1/applications/{name}/links`（Deep Link）
- `GET /api/v1/stream/applications`（应用变更事件流）
- `GET /api/v1/settings`、`/api/v1/notifications/*`

---

## 9. 可直接抄的场景脚本

### 9.1 巡检：找出所有不健康 / 长期 OutOfSync 的应用

```bash
argocd app list -o json \
  | jq -r '.items[] | select(.status.health.status != "Healthy") | .metadata.name'

argocd app list -o json \
  | jq -r '.items[] | select(.status.sync.status == "OutOfSync") | .metadata.name' \
  | xargs -I{} argocd app diff {} --diff-exit-code 20
```

### 9.2 发布流水线：Git 提交 → 校验 → 同步 → 等待

```bash
set -euo pipefail
export ARGOCD_SERVER=argocd.example.com
export ARGOCD_AUTH_TOKEN="${ARGOCD_TOKEN}"

argocd app diff myapp --diff-exit-code 20 >/dev/null || {
  echo "存在漂移或 diff 失败，终止发布"; exit 1
}

argocd app sync myapp --prune --revision "${GIT_SHA}" --prompts-enabled=false
argocd app wait myapp --sync --health --operation --timeout 300
```

### 9.3 环境晋级：同一 Git 仓库推到两个集群

```bash
argocd app set myapp --dest-server https://prod.cluster.local --dest-namespace prod \
  --sync-policy automated --self-heal --auto-prune
argocd app sync myapp --prune
```

### 9.4 回滚

```bash
LAST_GOOD=$(argocd app history myapp -o id | head -2 | tail -1)
argocd app rollback myapp "${LAST_GOOD}" --prune
argocd app wait myapp --sync --health --timeout 300
```

### 9.5 批量改参数

```bash
argocd app list -p team-a -o name | xargs -I{} argocd app set {} -p image.tag=v1.2.3
```

### 9.6 事故现场取证

```bash
argocd app get myapp -o yaml            > /tmp/myapp.yaml
argocd app manifests myapp --source live > /tmp/live.yaml
argocd app history myapp                 > /tmp/history.txt
argocd app logs myapp --tail 2000        > /tmp/logs.txt
argocd app resources myapp --orphaned    > /tmp/orphans.txt
kubectl -n argocd get events --sort-by=.lastTimestamp | tail -50 > /tmp/events.txt
```

### 9.7 shell 补全

```bash
argocd completion bash > /etc/bash_completion.d/argocd
argocd completion zsh  > "${fpath[1]}/_argocd"
```

---

## 10. 容易踩的坑

| 现象 | 原因 | 处理 |
|------|------|------|
| CLI 报 `unknown field` | CLI 版本高于 Server | 对齐版本（见 §0.3） |
| `context deadline exceeded` | gRPC-Web 被代理缓冲 / 超时太短 | Nginx 关 buffering、加长 ALB idle timeout、必要时 `--grpc-web` |
| `rpc error: Unauthenticated` | token 过期 / 没带 `--auth-token` | `argocd relogin` 或更新 `ARGOCD_AUTH_TOKEN` |
| 权限不足却报 `not found` | AppProject 隔离导致 | `argocd account can-i` 预检；确认 `project` 字段 |
| `argocd app logs` 无输出 | 应用不在 Argo CD 所在 namespace | 加 `-N <app-namespace>` |
| 找不到已注册集群 | 集群 secret 名不对 | `kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=cluster` |
| sync 后资源没变 | 目标是别的集群 | `argocd app get --show-operation` 看实际 destination |
| `diff` 永远有差异 | 缺 diff 自定义或 secret 字段 | 配 `resource.customizations` |
| CI 卡住不返回 | 交互提示没关 | `--prompts-enabled=false` |
| `argocd app delete` 删不掉 | AppProject 开了 deletion confirmation | `argocd app confirm-deletion` |

---

## 11. 推荐的使用边界（工程约定）

1. **声明走 Git，操作走 CLI**：应用/项目/集群/仓库定义全部进 Git；CLI 只用于 `diff` 校验、`sync` 触发、`wait` 确认、`rollback` 应急。
2. **UI 的一次性操作，事后必须落到 Git**：否则下一次 sync 会被覆盖回去。用 `argocd admin app generate-spec` 把 UI 的结果导出成 YAML 提交。
3. **CI/CD 用 Token + Project Role**，不要用 admin 账号；权限最小化到 `argocd app sync` / `argocd app get`。
4. **破坏性动作加人工门禁**：`--prune`、`--cascade`、`argocd app delete` 在生产上应先 `--dry-run` / `--preview-changes`。
5. **CLI 版本随集群走**：把 `argocd version --client` 写进 CI 的前置检查。
6. **排查优先级**：`argocd app get --show-operation` → `argocd app diff` → `argocd app resources --orphaned` → `argocd app logs` → `argocd admin app get-reconcile-results`。

---

## 12. 官方参考

- CLI 参考（本手册来源）：`https://argo-cd.readthedocs.io/en/v3.5.6/user-guide/commands/`
- REST API：`https://argo-cd.readthedocs.io/en/v3.5.6/developer-guide/rest-api/`
- 源码对应目录：`argoproj/argo-cd` → `docs/user-guide/commands/`

```bash
# 在自己集群上核对 CLI 支持的子命令
kubectl -n argocd exec deploy/argocd-server -- argocd --help
```
