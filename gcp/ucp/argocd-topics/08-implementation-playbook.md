# 08 · 实施顺序与验收手册

> 一条**防锁死、可回滚、每步可验证**的落地路径。
> 阶段顺序有依赖关系，**不要跳步**——尤其是阶段 3 和 4（身份与权限）。

---

## 0. 总体顺序

```
阶段 0  基线核查与备份          ← 不改任何东西，先看清楚现状
   ↓
阶段 1  部署 Argo CD（单实例）    ← 先能跑通
   ↓
阶段 2  注册集群 + 仓库凭据       ← 打通链路
   ↓
阶段 3  Dex / LDAP + 组映射       ← 先做组映射
   ↓
阶段 4  禁用内置 admin            ← 验证阶段 3 通过后再做
   ↓
阶段 5  AppProject + RBAC 收紧
   ↓
阶段 6  ApplicationSet 批量分发
   ↓
阶段 7  Gatekeeper 接入
   ↓
阶段 8  升级到 HA
```

**关键依赖：**
- 阶段 3 → 阶段 4：**必须**先验证外部组能登录并有权限，否则会锁死
- 阶段 5 必须在阶段 6 之前：**先有项目边界，再批量生成**
- 阶段 8 放最后：HA 会改变网络拓扑，越早做变更越大

---

## 阶段 0 · 基线核查与备份

### 0.1 记录现状

```bash
# 集群信息
kubectl version
kubectl get nodes -o wide
kubectl get storageclass
gcloud container clusters describe <CLUSTER> --region <REGION> \
  --format='value(locations,currentMasterVersion,network,privateClusterConfig,resourceLabels)'

# 现有 Argo CD（如果有）
kubectl get applications -A -o wide
kubectl get appprojects -A
kubectl get applicationsets -A

# 现有的准入控制器
kubectl get validatingwebhookconfiguration
kubectl get mutatingwebhookconfiguration

# 已有的 Gatekeeper / Policy Controller
kubectl get pods -n gatekeeper-system 2>/dev/null
```

### 0.2 备份

```bash
mkdir -p backup/$(date +%Y%m%d)

# Argo CD 资源
argocd admin export > backup/$(date +%Y%m%d)/argocd-export.yaml

# 关键 ConfigMap / Secret
for cm in argocd-cm argocd-rbac-cm argocd-cm-ssh-known-hosts; do
  kubectl -n argocd get cm $cm -o yaml > backup/$(date +%Y%m%d)/$cm.yaml 2>/dev/null
done
kubectl -n argocd get secret argocd-secret -o yaml > backup/$(date +%Y%m%d)/argocd-secret.yaml

# ⚠️ argocd-secret 含凭据，务必 chmod 600 且不要提交进 Git
chmod 600 backup/$(date +%Y%m%d)/argocd-secret.yaml
```

### 0.3 验收标准

- [ ] 集群信息已记录
- [ ] `argocd-export.yaml` 存在且包含预期的 Application 数量
- [ ] `argocd-secret.yaml` 权限为 600

---

## 阶段 1 · 部署 Argo CD（单实例）

### 1.1 部署

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/manifests/install.yaml

kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl -n argocd get pods
```

### 1.2 暴露入口

```bash
# 临时用端口转发验证（先别急着配 Ingress）
kubectl -n argocd port-forward svc/argocd-server 8080:80
# 浏览器打开 http://localhost:8080，用 admin / 初始密码登录
# 初始密码：kubectl -n argocd get secret argocd-initial-admin-password -o jsonpath='{.data.password}' | base64 -d
```

### 1.3 验收标准

- [ ] 所有 Pod `Running`
- [ ] 能用 `admin` 登录
- [ ] `argocd version` 与清单版本一致

```bash
argocd version --client
kubectl -n argocd get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
```

---

## 阶段 2 · 注册集群 + 仓库凭据

### 2.1 注册目标集群

**优先用 Workload Identity**（GKE 推荐），避免长期密钥。

```bash
# 用 gcloud 拿集群信息
CLUSTER=<CLUSTER>
REGION=<REGION>
gcloud container clusters get-credentials $CLUSTER --region $REGION

# 通过 Argo CD CLI 注册（带 ServiceAccount）
argocd cluster add gke-$CLUSTER \
  --service-account-issuer=https://container.googleapis.com/v1 \
  --service-account-key-file=./$CLUSTER.key
```

> GKE 上更完整的 Workload Identity 方案（含 metadata server 取 token）
> 需要查官方文档核对：
> `https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity`
> 本轮无法访问该页面，实施前请自行核对。

### 2.2 配置仓库凭据（声明式）

```bash
kubectl apply -f examples/argocd-repositories-githubapp.yaml
```

### 2.3 验收标准

- [ ] `argocd cluster list` 显示目标集群 `Connected`
- [ ] `argocd repo list` 能看到仓库
- [ ] 创建一个测试 Application，能成功同步（`spec.syncPolicy.automated` 先不开）

```bash
argocd cluster list
argocd repo list
# 用 UI 建一个 Application，手动 sync 一次
argocd app get <test-app>
argocd app diff <test-app>
```

---

## 阶段 3 · Dex / LDAP + 组映射（**先做组映射**）

### 3.1 步骤

```bash
# ① 先在 LDAP 侧验证 connector 配置正确
#    （用 ldapsearch 验证，见 03-dex-ldap-sso.md §3.3）

# ② 放 LDAP 绑定密码到 Secret
kubectl -n argocd create secret generic argocd-dex-ldap \
  --from-literal=bindPW='<你的 LDAP 绑定密码>'

# ③ 应用 Dex 配置
kubectl apply -f examples/dex-ldap-config.yaml

# ④ 重启 Dex（ConfigMap 变更不会自动重启）
kubectl -n argocd rollout restart deployment/argocd-dex-server
kubectl -n argocd rollout status deployment/argocd-dex-server --timeout=180s

# ⑤ 应用 RBAC 配置（此时先不动 admin.enabled）
kubectl apply -f examples/argocd-rbac-cm.yaml
```

### 3.2 验证（**这一步不通过，绝对不能做阶段 4**）

```bash
# ① Dex 健康
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-dex-server --tail=50

# ② 用 devops-admin 组的账号登录（浏览器）
#    F12 → Network → id_token → Base64 解码 → 应有 groups 数组

# ③ 确认权限生效
argocd rbac list
#    应能看到 g, devops-admin, role:admin

# ④ 在 UI 里确认该账号能看到并管理 Application
```

### 3.3 验收标准（全部满足才能进入阶段 4）

- [ ] Dex Pod 无错误日志
- [ ] LDAP 账号能成功登录
- [ ] ID Token 里**确实有** `groups` claim，且值包含 `devops-admin`
- [ ] `argocd rbac list` 显示 `g, devops-admin, role:admin`
- [ ] 该账号在 UI 里能管理 Application

### 3.4 回滚

```bash
kubectl -n argocd delete cm argocd-rbac-cm     # 或还原备份
kubectl apply -f backup/<date>/argocd-rbac-cm.yaml
kubectl -n argocd rollout restart deployment/argocd-dex-server
```

---

## 阶段 4 · 禁用内置 admin（**高风险阶段**）

### 4.1 前置条件

- [ ] 阶段 3 的 5 条验收标准**全部**通过
- [ ] break-glass 方案已就绪（见 `03-dex-ldap-sso.md` §7）

### 4.2 执行

```bash
kubectl -n argocd patch cm argocd-cm --type merge \
  -p '{"data":{"admin.enabled":"false"}}'

# 验证
kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.admin\.enabled}{"\n"}'
```

### 4.3 验收标准

- [ ] 用 `admin` 账号登录被拒绝
- [ ] 用 `devops-admin` 组账号**仍能登录**并有管理员权限
- [ ] Argo CD UI 各页面可正常访问

### 4.4 回滚（**锁死时的应急路径**）

```bash
# 从集群外用 kubectl 改回（需要有集群写权限）
kubectl -n argocd patch cm argocd-cm --type merge \
  -p '{"data":{"admin.enabled":"true"}}'
# 然后用 admin + 初始密码登录
kubectl -n argocd get secret argocd-initial-admin-password -o jsonpath='{.data.password}' | base64 -d
```

> ⚠️ **这条应急路径必须提前演练一遍**。
> 如果你的 Argo CD 管理权限完全依赖 Argo CD 自己，
> 那么"禁用 admin"这一步必须有独立的集群级逃生通道。

---

## 阶段 5 · AppProject + RBAC 收紧

### 5.1 创建 AppProject

```bash
kubectl apply -f examples/appproject-multi-env.yaml
kubectl -n argocd get appprojects
```

### 5.2 收紧 `default` 项目（**破坏性操作**）

```bash
# ⚠️ 先把所有 Application 迁到正式项目
kubectl -n argocd get applications -o custom-columns='NAME:.metadata.name,PROJECT:.spec.project'
# 确认没有 Application 还在 default 项目

# 然后再收紧
kubectl apply -f examples/appproject-multi-env.yaml
```

### 5.3 验收标准

- [ ] 每个团队有独立 AppProject
- [ ] `default` 项目的 `sourceRepos` / `destinations` 已置空
- [ ] 项目角色生效（用受限账号验证）
- [ ] Argo CD 用的 ServiceAccount 权限已收窄（`kubectl auth can-i` 验证）

```bash
# 验证 K8s RBAC 边界
kubectl auth can-i --as=system:serviceaccount:argocd:argocd-deployer \
  create rolebindings -n <ns>          # 应为 no
kubectl auth can-i --as=system:serviceaccount:argocd:argocd-deployer \
  create deployments -n <ns>           # 应为 yes
```

### 5.4 回滚

```bash
kubectl apply -f backup/<date>/argocd-export.yaml   # 会还原 AppProject
```

---

## 阶段 6 · ApplicationSet 批量分发

### 6.1 步骤

```bash
# ① 先用 dry-run 确认渲染结果
kubectl -n argocd apply --dry-run=server -f examples/applicationset-matrix.yaml

# ② 正式应用
kubectl -n argocd apply -f examples/applicationset-matrix.yaml

# ③ 观察生成
kubectl -n argocd get applicationset
kubectl -n argocd get applications -l argocd.argoproj.io/application-set-name=platform-apps
```

### 6.2 验收标准

- [ ] ApplicationSet 状态 `Healthy`
- [ ] 生成的 Application 数量符合预期（集群数 × 应用数）
- [ ] **每个 Application 的 `spec.project` 都不是 `default`**
- [ ] 没有 Application 落到未授权的项目

```bash
# 关键检查：有没有落到 default
kubectl -n argocd get applications -o jsonpath='{range .items[?(@.spec.project=="default")]}{.metadata.name}{"\n"}{end}'
# 期望输出为空
```

### 6.3 回滚

```bash
kubectl -n argocd delete applicationset platform-apps
# ⚠️ 会级联删除生成的 Application，进而删除集群资源
#    除非 Application 上有 preserveResourcesOnDeletion: true
```

---

## 阶段 7 · Gatekeeper 接入

### 7.1 部署（用仓库已有的资料）

```bash
# 参考 gke/opa-gatekeeper/single-cluster-opa-gatekeeper-setup.md
kubectl apply -f gke/opa-gatekeeper/gatekeeper-release-3.14.yaml

# 验证（仓库自带脚本）
./gke/opa-gatekeeper/verify-gatekeeper.sh
```

### 7.2 观察期（`failurePolicy: Ignore`）

```bash
# 确认当前是 Ignore
kubectl get validatingwebhookconfiguration gatekeeper-validating-webhook-configuration \
  -o jsonpath='{.webhooks[*].failurePolicy}{"\n"}'

# 收集违规
kubectl get constraints -o yaml | grep -A5 violation
```

### 7.3 切到 Fail

```bash
# 确认观察期内违规数归零后再切
kubectl patch validatingwebhookconfiguration gatekeeper-validating-webhook-configuration \
  --type=json \
  -p='[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Fail"}]'
```

### 7.4 验收标准

- [ ] Gatekeeper ≥2 副本 Running
- [ ] `failurePolicy: Fail` 后，违规资源确实被拒
- [ ] Argo CD 的 `resource.customizations.health.*` 已配（CR 场景必做）
- [ ] `argocd` 命名空间已加入 `excludedNamespaces`

---

## 阶段 8 · 升级到 HA

### 8.1 步骤

```bash
# 用 Helm chart 升级（推荐）
helm upgrade argocd argo/argo-cd \
  --namespace argocd \
  --set global.domain=argocd.example.com \
  --set controller.replicas=3 \
  --set server.replicas=3 \
  --set repoServer.replicas=3 \
  --set dex.replicas=1 \
  --values examples/ha-values-override.yaml

kubectl -n argocd rollout status deployment --all --timeout=600s
```

### 8.2 验收标准

- [ ] `argocd-server` 3 副本且 `ARGOCD_API_SERVER_REPLICAS=3`
- [ ] `argocd-repo-server` 3 副本
- [ ] `argocd-application-controller` 3 副本（StatefulSet）
- [ ] Redis HA：3 master + 3 sentinel + HAProxy
- [ ] `argocd-dex-server` **1 副本**
- [ ] 滚动更新期间服务不中断
- [ ] 登录不出现限流误报

```bash
# 副本数一致性检查
kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.replicas}{"\n"}'
kubectl -n argocd get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ARGOCD_API_SERVER_REPLICAS")].value}{"\n"}'
# 两个数字必须相同

# Sentinel 状态
kubectl -n argocd exec argocd-redis-0 -- redis-cli -p 26379 SENTINEL masters
```

---

## 全流程回滚策略

| 阶段 | 回滚方式 | 数据影响 |
|---|---|---|
| 0 | — | 无 |
| 1 | `kubectl delete -n argocd -f install.yaml` | 删集群里的 Argo CD 资源（**业务资源不受影响**，除非 Application 有 prune） |
| 2 | 删除 cluster / repository Secret | 无 |
| 3 | 还原 `argocd-rbac-cm` + `argocd-cm` 备份 | 无 |
| 4 | `kubectl patch cm argocd-cm` 改回 `admin.enabled: "true"` | 无 |
| 5 | `kubectl apply -f argocd-export.yaml` | **可能删资源**（AppProject 的 `finalizers`） |
| 6 | 删 ApplicationSet | **会删集群资源**（除非 `preserveResourcesOnDeletion: true`） |
| 7 | 把 `failurePolicy` 改回 `Ignore` | 无 |
| 8 | `helm upgrade` 回旧 values | 无 |

> **通用回滚原则**：
> 1. 每个阶段改之前先 `kubectl get -o yaml > backup/<stage>-before.yaml`
> 2. **加 `finalizers` / `preserveResourcesOnDeletion` 前必须想清楚**
> 3. 阶段 6 的回滚最危险——删 AppSet 等于删业务

---

## 验收总表

| 阶段 | 关键验收项 | 验证命令 |
|---|---|---|
| 0 | 备份完整 | `ls -la backup/<date>/` |
| 1 | Pod 全 Running | `kubectl -n argocd get pods` |
| 2 | 集群 Connected、仓库可见 | `argocd cluster list` / `argocd repo list` |
| 3 | ID Token 带 groups、RBAC 生效 | `argocd rbac list` |
| 4 | admin 被拒、外部组可登录 | UI 验证 |
| 5 | 无 Application 在 default | `kubectl -n argocd get appprojects` |
| 6 | AppSet Healthy、project 正确 | `kubectl -n argocd get applicationset` |
| 7 | 违规被拒、业务不受影响 | `verify-gatekeeper.sh` |
| 8 | 副本数一致、滚动更新无中断 | `kubectl -n argocd get pods` |
