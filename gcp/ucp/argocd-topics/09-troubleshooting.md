# 09 · 排障手册

> 按**现象**索引。每条给出：根因 → 定位命令 → 处理。
> 关联专题文档见每节末尾。

---

## 0. 通用排查顺序

遇到 Argo CD 问题，按这个顺序走：

```
① 状态是什么？
   argocd app get <app>
   kubectl -n argocd get application <app> -o jsonpath='{.status.conditions}'

② 同步卡在哪一步？
   kubectl -n argocd get application <app> -o jsonpath='{.status.operationState.phase}{"\n"}'
   kubectl -n argocd get application <app> -o jsonpath='{.status.operationState.message}{"\n"}'

③ 是渲染问题还是应用问题？
   argocd app manifests <app>        # 渲染失败 → 看 ①
   argocd app diff <app>             # diff 失败 → 看 ②
   kubectl -n argocd logs deploy/argocd-server --tail=100 | grep <app>

④ 涉及哪个组件？
   argocd-server / repo-server / application-controller / applicationset-controller / redis / dex
```

### 组件与日志对照

| 组件 | 日志命令 | 负责什么 |
|---|---|---|
| `argocd-server` | `kubectl -n argocd logs deploy/argocd-server` | API、UI、鉴权、RBAC |
| `argocd-repo-server` | `kubectl -n argocd logs deploy/argocd-repo-server` | Git 拉取、Kustomize/Helm 渲染、凭据 |
| `argocd-application-controller` | `kubectl -n argocd logs statefulset/argocd-application-controller` | 同步执行、diff、健康检查 |
| `argocd-applicationset-controller` | `kubectl -n argocd logs deploy/argocd-applicationset-controller` | 生成 Application |
| `argocd-dex-server` | `kubectl -n argocd logs deploy/argocd-dex-server` | LDAP 认证、Token 签发 |
| `argocd-redis` | `kubectl -n argocd logs deploy/argocd-redis` | Redis |

---

## 1. 登录 / 身份

| 现象 | 根因 | 定位 | 处理 |
|---|---|---|---|
| 所有人都登录失败 | 禁用了 admin 但组映射没生效 | `kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.admin\.enabled}'`；`argocd rbac list` | 见 [`03-dex-ldap-sso.md`](./03-dex-ldap-sso.md) §9 |
| 能登录但看不到任何 Application | `groups` 没进 Token，或 `scopes` 没含 groups | 浏览器 F12 看 id_token payload | 模式 A：查 IdP 的 groups claim / 开 `enableUserInfoGroups`；模式 B（Dex+OIDC）：connector 里开 `insecureEnableGroups: true` + `scopes: [groups]`；模式 C（Dex+LDAP）：查 `groupSearch`；见 [`03`](./03-dex-ldap-sso.md) §3.5 / §5.1.1 |
| `g, devops-admin, role:admin` 不生效 | `argocd-rbac-cm` 的 `scopes` 缺 groups | `kubectl -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.scopes}'` | 改 `scopes: '[groups, email]'` |
| 意外拥有 admin 权限 | `g` 的 subject 与 SSO claim 撞名 | `argocd rbac list` 看所有 `g` 规则 | 换带命名空间的组名，如 `my-org:devops-admin` |
| LDAP 报 "failed to search groups" | `userMatchers` 的 `userAttr`/`groupAttr` 不匹配 | `ldapsearch` 手工验证 | 见 [`03`](./03-dex-ldap-sso.md) §5.3 |
| 组名不生效 | `groupSearch.nameAttr` 与策略里的字符串不一致 | `ldapsearch ... "(objectClass=groupOfNames)" cn` | 大小写敏感，必须完全一致 |
| 密码明明对但认证失败 | `bindPW` 里的 `$` 被当变量展开 | 检查是否用了 Secret + 环境变量 | 见 [`03`](./03-dex-ldap-sso.md) §5.4 |
| 改了 `argocd-cm` 无效 | ConfigMap 变更不重启 Dex | — | `kubectl -n argocd rollout restart deploy/argocd-dex-server` |
| 员工离职后仍有权限 | 组只在登录时刷新 | 检查 Token 有效期 | 缩短 Token 生命周期 / 主动吊销；见 [`03`](./03-dex-ldap-sso.md) §8.2 |
| 登录被限流拒绝 | `ARGOCD_MAX_CONCURRENT_LOGIN_REQUESTS_COUNT` 与副本数不匹配 | 检查 `ARGOCD_API_SERVER_REPLICAS` | 见 [`02-ha.md`](./02-ha.md) §2 约束 3 |
| dex-server 重启后所有人掉线 | dex 用内存存储 | — | 预期行为；改用 Kubernetes CRD 后端 |

---

## 2. 同步 / 应用

| 现象 | 根因 | 定位 | 处理 |
|---|---|---|---|
| Application 一直 `OutOfSync`，集群里啥也没有 | 策略拒绝（Gatekeeper）或渲染为空 | `kubectl -n argocd get application <app> -o jsonpath='{.status.operationState.message}'` | 见 §5 |
| `OutOfSync` 但集群里资源是新的 | Argo CD 算出了 diff | `argocd app diff <app>` | 配置 `ignoreDifferences`；见 §6 |
| 渲染失败 "failed to generate manifest" | Kustomize/Helm 报错 | `argocd app manifests <app>`；repo-server 日志 | 修 Git 里的 manifest |
| 仓库拉取失败 | 凭据 / 网络 / CA | `kubectl -n argocd logs deploy/argocd-repo-server \| grep -i auth` | 见 §4 |
| 同步超时 | gRPC 消息过大 | 查 `ARGOCD_GRPC_MAX_SIZE_MB`（默认 200） | 调大；见 [`02-ha.md`](./02-ha.md) §7 |
| `Multi-Attach error for volume` | 给 Redis 挂了 RWO PVC + 滚动更新 | `kubectl -n argocd describe pod argocd-redis-*` | 摘掉 PVC；见 [`01-redis-persistence.md`](./01-redis-persistence.md) §4.2 |
| 同步后资源没出现 | 目标 namespace 不存在且没开 `CreateNamespace=true` | `kubectl get ns` | 加 `CreateNamespace=true` 或预建 namespace |
| `prune` 删掉了不该删的资源 | `prune: true` + AppProject 有 finalizers | — | 谨慎使用 prune；见 §7 |

---

## 3. ApplicationSet

| 现象 | 根因 | 定位 | 处理 |
|---|---|---|---|
| 生成的 Application 报 "path not found" | 模板变量名写错，渲染成空字符串 | `kubectl -n argocd get application <gen> -o jsonpath='{.spec.source.path}'` | 开 `goTemplate: true` + `missingkey=error`；见 [`05-appset.md`](./05-appset.md) §3.4 |
| 全部落在 `default` 项目 | `template.spec.project` 没写 | `kubectl -n argocd get applications -o jsonpath='{range .items[?(@.spec.project=="default")]}{.metadata.name}{"\n"}{end}'` | **必须显式写 project** |
| AppSet 报 generator 错误 | Merge 里多个生成器写在同一数组元素 | AppSet controller 日志 | 每个生成器独立成 `- xxx:` |
| AppSet 不生成任何 Application | Git generator 路径无匹配 / 目录缺 kustomization.yaml | `argocd appset list`；controller 日志 | 检查 `path` glob 和目录内容 |
| `valuesFiles` 里的 Helm 变量被 Argo CD 渲染掉了 | 模板变量冲突 | 看生成 Application 的 source.helm | 用 `${{.xxx}}`（双写 `$`） |
| 改了单个 Application 的分支被还原 | AppSet 把手工修改还原成模板值 | — | 改 AppSet 的 `template.spec.source.targetRevision`；见 [`07`](./07-repository-githubapp.md) §2.2 |
| 生成数量爆炸、controller 压力大 | Git 源不受控 | `kubectl -n argocd get applications \| wc -l` | 限制仓库写权限；见 [`05`](./05-appset.md) §5.2 |
| 删 AppSet 导致业务资源全没 | 生成的 Application 无 `preserveResourcesOnDeletion` | — | 只能从 Git 重新 apply 恢复 |

---

## 4. 仓库凭据 / GitHub App

| 现象 | 根因 | 定位 | 处理 |
|---|---|---|---|
| **想改分支但找不到字段** | 分支不属于 Repository | — | 改 `Application.spec.source.targetRevision`；见 [`07`](./07-repository-githubapp.md) §1 |
| GitHub App 仓库 UI 里没有凭据编辑入口 | UI 对 GitHub App 类型不渲染编辑表单 | 上游 UI 源码确认 | 正常行为，改用声明式管理 |
| Repository 不被识别 | Secret 缺 `argocd.argoproj.io/secret-type: repository` label | `kubectl -n argocd get secret <n> -o jsonpath='{.metadata.labels}'` | 补 label |
| GitHub App 认证失败 | App ID / installation ID / 私钥不匹配 | `kubectl -n argocd get secret <n> -o yaml`（**注意脱敏**） | 三者必须属于同一个 App |
| 私钥已轮换但仍失败 | 检查的是旧 Secret | `kubectl -n argocd get secret <n> -o jsonpath='{.data.githubAppPrivateKey}' \| base64 -d \| head -1` | Argo CD 不缓存凭据，确认 Secret 真的更新了 |
| 某项目用不了该仓库 | Secret 的 `project` 字段不含该项目 / AppProject 的 `sourceRepos` 不含 | `argocd repo list` | 两边都配 |
| SSH 仓库 host key 错误 | 没配 known_hosts | — | 配 `insecure: "true"`（不推荐）或配置 host key |
| 私有仓库 "authentication required" | HTTPS 没配凭据 | repo-server 日志 | 补 `username` + `password`/`bearerToken` |

---

## 5. OPA / Gatekeeper

| 现象 | 根因 | 定位 | 处理 |
|---|---|---|---|
| 同步报 403 `admission webhook ... denied` | Gatekeeper 拒绝 | 看 `status.conditions[].message` | 修 manifest（预期行为） |
| 集群所有写入都失败 | Webhook 挂了 + `failurePolicy: Fail` | `kubectl get validatingwebhookconfiguration` | 恢复 Gatekeeper；紧急改 `Ignore` |
| Application 永久 OutOfSync 但集群无变化 | 同上 | `kubectl -n argocd logs statefulset/argocd-application-controller` | 同上 |
| 违规信息是一坨 JSON | 没配 health check | — | 配 `resource.customizations.health.*`；见 [`06`](./06-opa-gatekeeper-impact.md) §5 |
| CR 一直 `Progressing`，`selfHeal` 空转 | 没配 CR 的 health check | `kubectl -n argocd get application <app> -o jsonpath='{.status.resources[0].health}'` | 配 `resource.customizations.health.<g>.<v>.<k>` |
| Gatekeeper 拒绝 Argo CD 自己的资源 | 约束太严 | webhook 日志 | `excludedNamespaces: [argocd]` |
| Argo CD API 返回 403 | **Casbin RBAC，不是 OPA** | `argocd rbac list` | 见 [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| 同步卡在 Pending，提示 extension 错误 | 同步前策略引擎拒绝 | extension 日志 | 看 extension 配置的 `timeout` |

---

## 6. Diff / 健康检查

| 现象 | 根因 | 定位 | 处理 |
|---|---|---|---|
| 集群资源是对的，但 Argo CD 说 OutOfSync | API Server 注入的字段造成 diff | `argocd app diff <app>` | `ignoreDifferences`；见 §6.1 |
| `managedFields` 造成噪音 | kubectl 客户端侧字段 | diff 里可见 | `jqPathExpressions: ['.metadata.managedFields[]']` |
| `helm.sh/chart` 之类注入字段造成 diff | Helm chart 注入 | — | 配 `ignoreDifferences` 或在 Helm 里关掉 |
| `selfHeal` 反复触发但没实际变化 | CR 健康状态永远不健康 | `kubectl -n argocd get application <app> -o jsonpath='{.status.resources[*].health}'` | 修 health check |
| diff 里看到 `replicas` 一直变 | HPA 在改 | — | 排除 HPA 管理的字段 |

### 6.1 `ignoreDifferences` 配置

```yaml
# argocd-cm
data:
  resource.customizations.ignoreDifferences.all: |
    jqPathExpressions:
      - '.metadata.managedFields[]'
      - '.metadata.annotations."kubectl.kubernetes.io/restartedAt"'
      - '.spec.template.metadata.annotations."checksum/config"'
```

或单个 Application：

```yaml
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
```

> ⚠️ **不要用 `ignoreDifferences` 掩盖真实问题**。它让 Argo CD 不再纠正该字段。
> 只对"确实由其他 controller 管理"的字段使用。

---

## 7. 权限边界

| 现象 | 根因 | 定位 | 处理 |
|---|---|---|---|
| 同步报 "not permitted" | Argo CD 的 ServiceAccount 权限不足 | `kubectl auth can-i --as=system:serviceaccount:argocd:<sa> create deployments -n <ns>` | 补 ClusterRole/Role；见 [`04`](./04-appproject-rbac.md) §4 |
| 报 "destination not allowed" | AppProject 的 `destinations` 不含目标 | `argocd proj get <proj>` | 补 destinations |
| 报 "resource not permitted" | 不在白名单 / 命中黑名单 | `argocd proj get <proj>` | 调白/黑名单 |
| 用户能同步但不该能 | `policy.default` 权限过大 | `argocd rbac list` | 改 `policy.default` 指向最小角色；见 [`04`](./04-appproject-rbac.md) §2.6 |
| `deny` 规则不生效 | 默认权限不能被 deny 阻止 | — | 改 `policy.default` 本身 |
| 项目角色不生效 | 角色名不符合 `proj:<proj>:<role>` | `argocd proj role list <proj>` | 严格按格式改 |
| 删了 AppProject，资源也被删了 | AppProject 有 `resources-finalizer.argocd.argoproj.io` | `kubectl -n argocd get appproject <p> -o jsonpath='{.metadata.finalizers}'` | 去掉 finalizer |
| 改项目名后行为诡异 | `-` 触发 project inheritance | 上游 projects 文档 | 用 `_` 或明确配置 |

---

## 8. Redis / 持久化

| 现象 | 根因 | 定位 | 处理 |
|---|---|---|---|
| `argocd-redis` 重启后所有人掉线 | Redis 无持久化（**设计如此**） | `kubectl -n argocd get deploy argocd-redis -o jsonpath='{.spec.template.spec.containers[0].args}'` | 预期行为；见 [`01-redis-persistence.md`](./01-redis-persistence.md) |
| 业务 Redis Pod `Pending` | PVC 未绑定 / StorageClass 不存在 | `kubectl get storageclass`；`kubectl describe pvc` | 用集群里实际存在的 StorageClass；`WaitForFirstConsumer` |
| StatefulSet 只有第 1 个 Pod 就绪 | RWO 只能单挂载，`volumeClaimTemplates` 没生效 | `kubectl -n <ns> get statefulset redis -o yaml` | 确认 `volumeClaimTemplates` 在 `spec` 下 |
| 业务 Redis 数据写进去读不到 | Service 没指向 StatefulSet | `kubectl -n <ns> get svc redis -o jsonpath='{.spec.selector}'` | `serviceName` 与 StatefulSet 一致 |
| Sentinel 探测不到 master | HAProxy 或 sentinel 配置问题 | `kubectl -n argocd exec argocd-redis-0 -- redis-cli -p 26379 SENTINEL masters` | 见 [`01`](./01-redis-persistence.md) §5 |

---

## 9. HA 相关

| 现象 | 根因 | 定位 | 处理 |
|---|---|---|---|
| 登录被限流误拒 | `ARGOCD_API_SERVER_REPLICAS` ≠ `replicas` | 对比两个值 | 同步改；见 [`02-ha.md`](./02-ha.md) §2 |
| 部分 Application 状态更新慢 | controller 分片变化 | `kubectl -n argocd get sts argocd-application-controller` | 正常现象，短暂 |
| dex-server 多副本登录态不均匀 | dex 用内存数据库 | — | **保持 1 副本**；见 [`02`](./02-ha.md) §2 约束 2 |
| sentinel 数量不是 3 | 被改过 | `kubectl -n argocd get pods -l app.kubernetes.io/name=redis` | 官方只支持 3，不要扩缩 |
| 滚动更新卡住 | Redis 挂了 RWO PVC | `kubectl -n argocd describe pod argocd-redis-*` | 摘 PVC |

---

## 10. 快速诊断脚本

仓库里有一份可直接使用的体检脚本：

```bash
# 纯只读，不修改任何集群资源
./examples/argocd-health.sh              # 全局体检
./examples/argocd-health.sh my-app       # 附带某个 Application 的详情
NS=argocd-prod ./examples/argocd-health.sh
```

它会检查：副本数与 `ARGOCD_API_SERVER_REPLICAS` 是否一致、dex-server 是否为 1 副本、
Redis 是否挂了持久卷、`rbac scopes` 是否含 `groups`、`admin.enabled` 状态、
是否有 Application 落在 `default` 项目、AppProject / ApplicationSet 状态、
Gatekeeper 的 `failurePolicy`。

退出码 `0` = 无异常，`1` = 有异常项，`2` = 环境不可用（无集群 / namespace 不存在）。

> 脚本内容也可直接复制使用：

```bash
#!/usr/bin/env bash
# argocd-health.sh —— 一键体检
set -uo pipefail
NS=${NS:-argocd}
APP=${1:-}

echo "=== 组件状态 ==="
kubectl -n $NS get pods -o wide
echo
echo "=== 副本数 vs API_SERVER_REPLICAS ==="
kubectl -n $NS get deploy argocd-server -o jsonpath='replicas={.spec.replicas}{"\n"}'
kubectl -n $NS get deploy argocd-server -o jsonpath='API_SERVER_REPLICAS={.spec.template.spec.containers[0].env[?(@.name=="ARGOCD_API_SERVER_REPLICAS")].value}{"\n"}'
echo
echo "=== Redis 参数 ==="
kubectl -n $NS get deploy argocd-redis -o jsonpath='args={.spec.template.spec.containers[0].args}{"\n"}'
kubectl -n $NS get deploy argocd-redis -o jsonpath='volumes={.spec.template.spec.volumes}{"\n"}'
echo
echo "=== admin.enabled / RBAC ==="
kubectl -n $NS get cm argocd-cm -o jsonpath='admin.enabled={.data.admin\.enabled}{"\n"}'
kubectl -n $NS get cm argocd-rbac-cm -o jsonpath='scopes={.data.scopes}{"\n"}'
echo
echo "=== Application 项目分布（default 应为空）==="
kubectl -n $NS get applications -o jsonpath='{range .items[?(@.spec.project=="default")]}{.metadata.name}{"\n"}{end}'
echo
echo "=== AppSet 状态 ==="
kubectl -n $NS get applicationsets
echo
if [ -n "$APP" ]; then
  echo "=== $APP 详情 ==="
  kubectl -n $NS get application $APP -o jsonpath='project={.spec.project}{"\n"}'
  kubectl -n $NS get application $APP -o jsonpath='revision={.spec.source.targetRevision}{"\n"}'
  kubectl -n $NS get application $APP -o jsonpath='phase={.status.operationState.phase}{"\n"}'
  kubectl -n $NS get application $APP -o jsonpath='message={.status.operationState.message}{"\n"}'
  kubectl -n $NS get application $APP -o jsonpath='health={.status.health.status}{"\n"}'
fi
```

---

## 11. 关联文档

| 专题 | 文档 |
|---|---|
| 身份与组映射 | [`03-dex-ldap-sso.md`](./03-dex-ldap-sso.md) |
| 权限边界 | [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| ApplicationSet | [`05-appset.md`](./05-appset.md) |
| OPA / Gatekeeper | [`06-opa-gatekeeper-impact.md`](./06-opa-gatekeeper-impact.md) |
| 仓库凭据 | [`07-repository-githubapp.md`](./07-repository-githubapp.md) |
| 实施与回滚 | [`08-implementation-playbook.md`](./08-implementation-playbook.md) |
| Redis 与 HA | [`01-redis-persistence.md`](./01-redis-persistence.md)、[`02-ha.md`](./02-ha.md) |
| 已有总览 | [`../argocd-admin-guide.md`](../argocd-admin-guide.md) |
| Gatekeeper 完整资料 | [`../../gke/opa-gatekeeper/`](../../gke/opa-gatekeeper/) |
