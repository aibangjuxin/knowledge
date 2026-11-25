# Argo CD 3.5.5 跨项目多集群 GKE Workload Identity 授权实施方案

> 起因：`argocd app get-resource ... --kind CustomResourceDefinition --resource-name gateways.gateway.networking.k8s.io` → `PermissionDenied`
> 身份：`serviceAccount:<PROJECT_ID>.svc.id.goog[argocd/argocd-server]`
> 环境：Argo CD 3.5.5 Control Plane（单集群）→ 多个跨项目 GKE Target Cluster
> 关联：[04 AppProject 与权限模型](./04-appproject-rbac.md)、[09 排障手册](./09-troubleshooting.md)、[argocd-admin-guide.md §7](../argocd-admin-guide.md)

---

## 0. 结论速览

**不是 Workload Identity 配置失败，而是授权不完整。**

| 层次 | 职责 | 本例状态 |
|---|---|---|
| **Authentication** | Argo CD 是谁（KSA → GSA / KSA Principal） | ✅ 已成功（报错主体形态就是证明） |
| **Authorization** | 这个身份能不能 `get customresourcedefinitions` | ❌ 缺失 |

四个必须记住的事实：

1. **CRD 是集群级资源（cluster-scoped）。**
   已有 `gateway.networking.k8s.io` 下 Gateway 资源的**命名空间级**权限，
   不代表能读 `gateways.gateway.networking.k8s.io` 这个 **CRD 对象**。
   → 必须 ClusterRole/ClusterRoleBinding，或项目级 IAM 权限。

2. **GKE 的 IAM 与 RBAC 是 fallback 关系，不是二选一。**（官方原文）
   > To authorize an action, GKE checks for an RBAC policy first.
   > If there isn't an RBAC policy, GKE checks for IAM permissions.
   > If the user has enough permission according to **either** the RBAC policy
   > or the IAM permission, the request is authorized.

   → **RBAC 优先，不放行才回落查 IAM。**
   → 所以「两边都要配」是误解；**任一处放行即可**，
     但**不要两边盲目重复授权**。

3. **报错形态决定修复位置。**
   - `requires one of ["container.customResourceDefinitions.get"] permission(s)`
     → 走的是 **IAM 路径且失败** → 说明**集群内 RBAC 没有匹配授权**。
     → **首选在集群内加 RBAC**（细粒度、只影响该集群）。
   - `User "..." cannot get resource "customresourcedefinitions"`
     → 纯 RBAC 拒绝 → 同样在集群内加 RBAC。

4. **`roles/container.clusterViewer` 不含 CRD 权限。**
   它只有 `container.clusters.connect/get/list`，是**「能连上集群」**的权限，
   不是「能读集群里的 CRD」。含 CRD 读权限的是
   `container.viewer` / `developer` / `editor` / `admin`。
   → **本方案用 `clusterViewer`（IAM 侧）+ 集群内 RBAC（资源侧）**，
     两者职责不重叠，天然避免了「给项目级 viewer」的越权。

---

## 1. 目标架构

```
ArgoCD Control Plane  (Project: argocd-control)
  argocd-server / argocd-repo-server / argocd-application-controller
        │  KSA + iam.gke.io/gcp-service-account 注解
        ▼
  Workload Identity Federation for GKE
        ▼
  GSA Impersonation: argocd-gke-access@argocd-control.iam.gserviceaccount.com
        │  (KSA → GSA 需要 roles/iam.workloadIdentityUser)
        ▼
  GKE IAM  ──▶ roles/container.clusterViewer
        │        （在每个 Target Project 授予：connect/get/list）
        ▼
  Target GKE Cluster
        │
        └─ Kubernetes RBAC  ◀── 授权主战场
             ClusterRole / ClusterRoleBinding（集群级资源：CRD、GatewayClass、Namespace）
             Role / RoleBinding（命名空间级：Gateway、HTTPRoute、Deployment…）

  Target Cluster A (Project: gke-project-a)
  Target Cluster B (Project: gke-project-b)
  Target Cluster C (Project: gke-project-c)
```

**设计原则（贯穿全文）：**

- GKE IAM 只负责「**连得上**目标集群」。
- Kubernetes RBAC 负责「**能操作什么**」。
- ❌ 不给 GSA 授予 `roles/container.admin`。
- ❌ 不用项目级 `roles/container.viewer` 解决单个 CRD 权限问题。
- ✅ 多集群共用统一授权模板，但**每个 Cluster 独立部署 RBAC**。
- ✅ 初期共用一个 GSA 快速解封；后续如需隔离 server / controller 权限再拆分。

---

## 2. 认证链路与「实际身份」判读

### 2.1 两种 Workload Identity 模式

| | 模式 A：KSA 直接 Federation | 模式 B：KSA → GSA Impersonation |
|---|---|---|
| 身份 | KSA 对应的 IAM Principal | GSA |
| KSA 上 | **不需要** GSA 注解 | `iam.gke.io/gcp-service-account: <gsa>@<PROJECT_ID>.iam.gserviceaccount.com` |
| GSA 上 | 不需要 | 需 `roles/iam.workloadIdentityUser` 授给 KSA |
| IAM 成员 | `principal://iam.googleapis.com/...` | `serviceAccount:<gsa>@<PROJECT_ID>.iam.gserviceaccount.com` |
| API Server 识别的用户名 | `serviceAccount:<PROJECT_ID>.svc.id.goog[ns/ksa]` | GSA 邮箱（或其 `uniqueId`） |

> **Google 官方明确说明**：启用 Workload Identity Federation
> **不会自动赋予工作负载任何 IAM 权限**，必须另外配置授权策略。
> 绑定 ≠ 有权限。

### 2.2 ⚠️ 你当前报错的身份形态与「模式 B」不一致

这是**实施前必须解决的第一个验证点**：

| | 期望（模式 B：GSA Impersonation） | 实际（你的报错） |
|---|---|---|
| API Server 识别的主体 | `argocd-gke-access@argocd-control.iam.gserviceaccount.com` | `serviceAccount:<PROJECT_ID>.svc.id.goog[argocd/argocd-server]` |

**实际报错的形态是模式 A（KSA 直接 Federation）的形态。**
两种可能：

1. **你确实跑的是模式 A**（KSA 上没有 GSA 注解）→ 那就应该给 **KSA Principal** 授权，
   而不是给 GSA 绑 RBAC。
2. **你跑的是模式 B 但链路没走到 Impersonation**（注解没生效 /
   `roles/iam.workloadIdentityUser` 没授 / `argocd-k8s-auth` 用的不是同一个 KSA）
   → 先修认证链路，再谈授权。

> **不要凭报错文案直接抄字符串当 RBAC subject。**
> 用 §5 Step 5 的 `kubectl auth whoami` / `kubectl auth can-i` 实测。

### 2.3 模式 A 的 IAM 成员格式

```
principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<PROJECT_ID>.svc.id.goog/subject/ns/argocd/sa/argocd-server
```

⚠️ 这里的 `PROJECT_NUMBER` / `PROJECT_ID` 指 **Workload Identity Pool 所属项目**
（= Argo CD 所在集群的项目），**不一定是目标 GKE Cluster 所在项目**。

### 2.4 Argo CD 三个组件都要覆盖

| 组件 | 职责 | 何时访问目标集群 |
|---|---|---|
| `argocd-server` | UI / CLI / API，`get-resource`、`get-manifests`、Pod 日志 | ✅（本例报错主体） |
| `argocd-repo-server` | 渲染 Helm/Kustomize，按需回读集群状态 | ✅ |
| `argocd-application-controller` | diff / sync / health check | ✅（**同步成败的关键**） |

Argo CD 官方 GKE WI 示例要求配 `argocd-server` 与 `argocd-application-controller`；
但 **`argocd-repo-server` 也需要**（它同样要读目标集群做渲染回读与 secret 获取）。
本方案统一给三个都绑。

> `argocd-server` 能查了 ≠ 同步能成功。**同步是否恢复要单独验证**（§6 Step 3）。

---

## 3. 需要哪些权限

### 3.1 GKE 官方 API 权限表（节选）

| 操作 | 所需 IAM 权限 |
|---|---|
| `GET /apis/apiextensions.k8s.io/v1/customresourcedefinitions/{name}` | `container.customResourceDefinitions.get` |
| `GET /apis/apiextensions.k8s.io/v1/customresourcedefinitions` | `container.customResourceDefinitions.list` |
| `GET /apis/{path_to_custom_resource}/{name}`（Gateway 实例） | `container.thirdPartyObjects.get` |
| `GET /apis/{path_to_custom_resource}` | `container.thirdPartyObjects.list` |
| 写 Deployment/StatefulSet | `container.deployments.*`、`container.statefulSets.*` |
| 绑定 ClusterRole / Role | `container.clusterRoles.bind` / `container.roles.bind` |
| 获取集群连接信息 | `container.clusters.get`、`container.clusters.connect` |

> **CRD 与 CR 实例是两套权限**：
> 读 CRD（discovery）要 `customResourceDefinitions.*`，
> 读 Gateway 实例要 `thirdPartyObjects.*`。
> 只给前者，discovery 过了但取资源仍失败。

### 3.2 角色对照表（易踩坑）

| IAM Role | 含 `container.customResourceDefinitions.get`？ | 主要用途 | 本方案用？ |
|---|---|---|---|
| `roles/container.clusterViewer` | ❌ **不含** | `clusters.connect/get/list`——**连接集群** | ✅ **IAM 侧用它** |
| `roles/container.viewer` | ✅ 含（`get`/`getStatus`/`list`） | 集群资源只读（**161 个 `container.*`**，项目级所有集群） | ❌ 不用于本问题 |
| `roles/container.developer` | ✅ 含（全套 `.*`） | Kubernetes API 对象开发访问 | ⚠️ 仅在确实需要 IAM 兜底时 |
| `roles/container.editor` | ✅ 含（全套 `.*`） | 编辑 | ❌ |
| `roles/container.admin` | ✅ 含（`container.*`） | 全管理 | ❌ **生产红线** |

> `container.viewer` 虽能解封，但它是**项目级、覆盖所有集群、161 个权限**的宽角色，
> 多租户生产环境不要直接用。

---

## 4. 实施步骤（可直接执行）

### 4.0 变量约定

```bash
export CONTROL_PROJECT_ID="argocd-control"       # Argo CD 所在项目
export CONTROL_PROJECT_NUMBER="$(gcloud projects describe "${CONTROL_PROJECT_ID}" --format='value(projectNumber)')"
export GSA_NAME="argocd-gke-access"
export GSA_EMAIL="${GSA_NAME}@${CONTROL_PROJECT_ID}.iam.gserviceaccount.com"
export ARGOCD_NAMESPACE="argocd"

export TARGET_PROJECT_A="gke-project-a"
export TARGET_PROJECT_B="gke-project-b"
export TARGET_PROJECT_C="gke-project-c"
```

### 4.1 第一步：创建 GSA（Control Plane 项目）

```bash
gcloud iam service-accounts create "${GSA_NAME}" \
  --project="${CONTROL_PROJECT_ID}" \
  --display-name="ArgoCD GKE Cross Cluster Access"
```

### 4.2 第二步：允许 KSA Impersonate GSA

```bash
for SA in argocd-server argocd-repo-server argocd-application-controller; do
  gcloud iam service-accounts add-iam-policy-binding "${GSA_EMAIL}" \
    --project="${CONTROL_PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:${CONTROL_PROJECT_ID}.svc.id.goog[${ARGOCD_NAMESPACE}/${SA}]"
done
```

> ⚠️ 这里的 Workload Identity Pool 用的是 **Argo CD 所在集群的项目**，
> 不是目标 GKE 项目。成员串里的 `PROJECT_ID` 同理。

### 4.3 第三步：KSA 注解

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    iam.gke.io/gcp-service-account: argocd-gke-access@argocd-control.iam.gserviceaccount.com
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-repo-server
  namespace: argocd
  annotations:
    iam.gke.io/gcp-service-account: argocd-gke-access@argocd-control.iam.gserviceaccount.com
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-application-controller
  namespace: argocd
  annotations:
    iam.gke.io/gcp-service-account: argocd-gke-access@argocd-control.iam.gserviceaccount.com
```

> ⚠️ **Helm / Kustomize 管理这些 SA 时，直接 `kubectl apply` 会被下一次 Helm upgrade 覆盖。**
> 正确做法是用 kustomize patch：

```yaml
# kustomization.yaml
patches:
  - target:
      kind: ServiceAccount
      name: argocd-server
    patch: |-
      - op: replace
        path: /metadata/annotations/iam.gke.io~1gcp-service-account
        value: "argocd-gke-access@argocd-control.iam.gserviceaccount.com"
```

（`argocd-repo-server`、`argocd-application-controller` 同理。）

验证：

```bash
kubectl -n "${ARGOCD_NAMESPACE}" get sa \
  argocd-server argocd-repo-server argocd-application-controller -o yaml \
  | grep -A2 'iam.gke.io'
```

### 4.4 第四步：在所有 Target Project 授予 GKE IAM 连接权限

```bash
for PROJECT_ID in "${TARGET_PROJECT_A}" "${TARGET_PROJECT_B}" "${TARGET_PROJECT_C}"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${GSA_EMAIL}" \
    --role="roles/container.clusterViewer"
done
```

**为什么是 `clusterViewer`？**

它包含 `container.clusters.connect` / `container.clusters.get` / `container.clusters.list`，
正是 GKE 认证连接所需。它**不含** CRD 读权限——
这正好把「连集群」和「读资源」分成两层，权限面干净。

> 若目标集群是 **Private cluster** 或使用 **Control Plane 授权**，
> 还需要网络层打通，见 [admin-guide §7.5](../argocd-admin-guide.md)。

**检查授权是否落地**：

```bash
for PROJECT_ID in "${TARGET_PROJECT_A}" "${TARGET_PROJECT_B}" "${TARGET_PROJECT_C}"; do
  echo "===== ${PROJECT_ID} ====="
  gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten="bindings[].members" \
    --filter="bindings.members:serviceAccount:${GSA_EMAIL}" \
    --format="table(bindings.role,bindings.members)"
done
```

> ⚠️ **IAM 传播有延迟**：授权后 1–2 分钟内仍失败通常是时序问题，先核对策略再重试。

### 4.5 第五步：在每个 Target Cluster 部署 Kubernetes RBAC

#### argocd-crd-reader.yaml

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-crd-reader
rules:
  # CRD discovery：集群级资源
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list", "watch"]
  # Gateway API 的 CRD 与实例是两回事：这里读的是 GatewayClass（集群级）
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["gatewayclasses"]
    verbs: ["get", "list", "watch"]
  # Namespace 本身是集群级资源
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "watch"]
```

> **为什么带 `list` 和 `watch`**：
> `get` = 读指定 CRD；`list` = 列出 CRD；`watch` = 监听变化。
> Argo CD 不只是读单个 CRD，还要做 API discovery、缓存与监听。
> 首次只想验证报错，可先只留 `get`，成功后再按 Argo CD 实际调用补齐。

#### argocd-crd-reader-binding.yaml（**两种模式二选一**）

**模式 B（GSA Impersonation）**——前提是实测确认 API Server 识别的就是 GSA：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-crd-reader-binding
subjects:
  - kind: User
    name: "argocd-gke-access@argocd-control.iam.gserviceaccount.com"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: argocd-crd-reader
  apiGroup: rbac.authorization.k8s.io
```

**模式 A（KSA 直接 Federation）**——subject 用报错里那个形态：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-crd-reader-binding
subjects:
  - kind: User
    name: "serviceAccount:<PROJECT_ID>.svc.id.goog[argocd/argocd-server]"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: argocd-crd-reader
  apiGroup: rbac.authorization.k8s.io
```

> **判定方法见 §5 Step 5，先测再绑。**

也可以用 GSA 的 `uniqueId` 作为 subject（官方 RBAC 文档给了这种写法）：

```bash
gcloud iam service-accounts describe "${GSA_EMAIL}" --format="value(uniqueId)"
kubectl create clusterrolebinding argocd-crd-reader-binding \
  --clusterrole=argocd-crd-reader --user=<GSA_UNIQUE_ID>
```

#### 部署到每个 Target Cluster

```bash
kubectl --context=gke-project-a apply -f argocd-crd-reader.yaml
kubectl --context=gke-project-a apply -f argocd-crd-reader-binding.yaml
kubectl --context=gke-project-b apply -f argocd-crd-reader.yaml
kubectl --context=gke-project-b apply -f argocd-crd-reader-binding.yaml
```

> `--context` 是示例名，请替换为实际 kubeconfig context。
> **多集群场景请把这两个 YAML 放进 Git**，通过既有的集群初始化 / 平台配置流程统一分发，
> 不要人工逐个操作。

### 4.6 第六步：命名空间级业务资源授权（同步用）

CRD 读通了只解决 discovery。真正部署 Gateway/HTTPRoute/Deployment 需要**命名空间级**权限：

| 资源类型 | Scope | 推荐授权 |
|---|---|---|
| CustomResourceDefinition | Cluster | ClusterRole ✅ |
| GatewayClass | Cluster | ClusterRole ✅ |
| Namespace | Cluster | ClusterRole ✅ |
| Gateway | Namespace | Role / RoleBinding |
| HTTPRoute | Namespace | Role / RoleBinding |
| Service | Namespace | Role / RoleBinding |
| Deployment | Namespace | Role / RoleBinding |
| ConfigMap | Namespace | Role / RoleBinding |
| Secret | Namespace | Role / RoleBinding |

示例（按命名空间下发）：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argocd-app-deployer
  namespace: <APP_NAMESPACE>
rules:
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["gateways", "httproutes", "grpcroutes", "referencegrants"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["services", "configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: argocd-app-deployer
  namespace: <APP_NAMESPACE>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: argocd-app-deployer
subjects:
  - kind: User
    name: "<按 §5 Step 5 实测的主体>"
    apiGroup: rbac.authorization.k8s.io
```

> 生产建议：**CRD 查询权限（ClusterRole）与业务资源部署权限（Role/RoleBinding）拆成两套**，
> 不要混在一起。
> Argo CD 的资源发现还可能需要读 API discovery、APIService 等其他集群级资源，
> **最终权限集合应根据实际 Application 的资源类型 + Argo CD 审计日志逐步完善**，
> 不能凭当前一条报错就认定「get CRD 是全部所需权限」。

### 4.7 第七步：Argo CD 3.5.5 Cluster Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gke-project-a
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: gke-project-a
  server: https://<TARGET_GKE_ENDPOINT>
  config: |
    {
      "execProviderConfig": {
        "command": "argocd-k8s-auth",
        "args": ["gcp"],
        "apiVersion": "client.authentication.k8s.io/v1beta1"
      },
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<BASE64_ENCODED_CA>"
      }
    }
```

**取 CA 与 endpoint**：

```bash
gcloud container clusters describe <TARGET_CLUSTER> \
  --region <REGION> --project <TARGET_PROJECT_ID> \
  --format="value(endpoint)"

gcloud container clusters describe <TARGET_CLUSTER> \
  --region <REGION> --project <TARGET_PROJECT_ID> \
  --format="value(masterAuth.clusterCaCertificate)"
```

> CA 证书非敏感，可直接放 Git 仓库。

**三个注意点**：

1. `argocd-k8s-auth` 必须存在于**执行认证的那个容器镜像**里。
   它是 Argo CD 自带的 exec credential 插件（子命令 `aws` / `gcp` / `azure`），
   但 **自定义镜像 / 精简镜像可能没打包进去**。
2. `caData` 要对应**目标集群**的 CA。
3. **绝不要**在 Secret 里放长期 GSA JSON Key。

> **Argo CD 3.5.5 特别提醒**：3.5 引入了**内部组件强制 mTLS**（repo-server 要求客户端证书）。
> 这影响的是 Argo CD 内部组件间通信，**不影响** Argo CD → 目标集群的这条链路，
> 但如果你在排查「repo-server 报证书错误」时会看到它，别与本问题混淆。

### 4.8 部署顺序（推荐先单集群验证）

```
① Create GSA in Control Project
        ↓
② Bind KSA → GSA（roles/iam.workloadIdentityUser）
        ↓
③ Configure KSA Annotation
        ↓
④ Grant roles/container.clusterViewer in Target Projects
        ↓
⑤ ★ Verify actual identity（argocd-k8s-auth gcp → whoami）
        ↓
   ┌──────────────┴──────────────┐
 实际主体 = GSA 邮箱            实际主体 = KSA Principal
   ↓                              ↓
用 GSA subject 绑 RBAC          用 KSA principal 绑 RBAC
   └──────────────┬──────────────┘
                  ↓
⑥ Deploy CRD ClusterRole + ClusterRoleBinding
                  ↓
⑦ Test kubectl auth can-i
                  ↓
        ┌─────────┴─────────┐
      Yes                 No
        ↓                  ↓
⑧ argocd app get-resource  检查 IAM/RBAC + IAM 传播延迟
        ↓
⑨ 验证 diff / refresh / sync
        ↓
⑩ Roll out to remaining clusters
```

> **先选一个非生产 Target Cluster 跑通全流程，再批量推广。**

---

## 5. 验证步骤（不能省略）

### Step 1：确认 KSA 注解

```bash
kubectl -n "${ARGOCD_NAMESPACE}" get sa argocd-server \
  -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}'
echo
# 期望：argocd-gke-access@argocd-control.iam.gserviceaccount.com
```

### Step 2：确认 GSA 的 Impersonation 策略

```bash
gcloud iam service-accounts get-iam-policy "${GSA_EMAIL}" \
  --project="${CONTROL_PROJECT_ID}" \
  --flatten="bindings[].members" \
  --filter="bindings.role=roles/iam.workloadIdentityUser" \
  --format="table(bindings.members)"
# 期望包含 serviceAccount:argocd-control.svc.id.goog[argocd/argocd-server]
#              serviceAccount:argocd-control.svc.id.goog[argocd/argocd-repo-server]
#              serviceAccount:argocd-control.svc.id.goog[argocd/argocd-application-controller]
```

### Step 3：确认认证插件可用

```bash
kubectl -n "${ARGOCD_NAMESPACE}" exec deploy/argocd-server -- which argocd-k8s-auth
kubectl -n "${ARGOCD_NAMESPACE}" exec deploy/argocd-server -- argocd-k8s-auth --help
```

### Step 4：确认 Pod 拿到的身份

```bash
kubectl -n "${ARGOCD_NAMESPACE}" exec deploy/argocd-server -- \
  curl -sH "Metadata-Flavor: Google" \
  "http://169.254.169.254/computeMetadata/v1/instance/service-accounts/"
# 期望：显示注解里配置的 GSA 邮箱
```

或用 `gcloud`（Pod 内需装 gcloud）：

```bash
kubectl -n "${ARGOCD_NAMESPACE}" exec deploy/argocd-server -- \
  gcloud auth list --filter=status:ACTIVE --format='value(account)'
```

### Step 5：★ 确认「实际认证身份」与权限（最关键的一步）

**必须用与 Argo CD Cluster Secret 相同的 exec 认证配置**，
不能直接用你本机 Mac 的 gcloud 登录身份（Mac 上多半是个人 Google 账号）。

在 Argo CD Pod 内构造一个临时 kubeconfig（目标集群 endpoint + CA + 相同 execProviderConfig）：

```bash
kubectl -n "${ARGOCD_NAMESPACE}" exec deploy/argocd-server -- sh -c 'cat > /tmp/target-kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- name: target
  cluster:
    server: https://<TARGET_GKE_ENDPOINT>
    certificate-authority-data: <BASE64_ENCODED_CA>
contexts:
- name: target
  context:
    cluster: target
    user: target
current-context: target
users:
- name: target
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: argocd-k8s-auth
      args: ["gcp"]
EOF
echo written'
```

然后：

```bash
kubectl -n "${ARGOCD_NAMESPACE}" exec deploy/argocd-server -- \
  kubectl --kubeconfig=/tmp/target-kubeconfig auth whoami

kubectl -n "${ARGOCD_NAMESPACE}" exec deploy/argocd-server -- \
  kubectl --kubeconfig=/tmp/target-kubeconfig auth can-i get \
  customresourcedefinitions --api-group=apiextensions.k8s.io
# 期望：yes

kubectl -n "${ARGOCD_NAMESPACE}" exec deploy/argocd-server -- \
  kubectl --kubeconfig=/tmp/target-kubeconfig get crd \
  gateways.gateway.networking.k8s.io
```

**结果解读**：

| `whoami` 输出 | 结论 | RBAC subject 应该写 |
|---|---|---|
| `argocd-gke-access@argocd-control.iam.gserviceaccount.com` | 模式 B 正常 | GSA 邮箱（或 uniqueId） |
| `serviceAccount:<PROJECT_ID>.svc.id.goog[argocd/argocd-server]` | 模式 A，或模式 B 链路未生效 | KSA Principal 形态 |

> 如果你**期望** GSA 邮箱但实际显示 KSA Principal，
> **先不要绑 GSA 的 RBAC**，去查认证链路：
> 注解没生效？`roles/iam.workloadIdentityUser` 没授？
> `argocd-k8s-auth` 用的 KSA 和你以为的不是同一个？
> 节点池的 Workload Metadata Server 没开？

> `kubectl auth whoami` 需要 K8s 1.27+ 且服务端支持 SelfSubjectReview；
> 不支持时用 `kubectl auth can-i` 代替（但 `can-i` 只能验证"能不能"，
> 不能告诉你"你是谁"，此时可用审计日志反查主体）。

### Step 6：确认 RBAC 绑定落地（用管理员身份连目标集群）

```bash
kubectl --context=gke-project-a get clusterrole argocd-crd-reader -o yaml

kubectl --context=gke-project-a describe clusterrolebinding argocd-crd-reader-binding
# 确认 subject 与 Step 5 实测主体一致
```

### Step 7：确认 Argo CD 侧

```bash
argocd cluster list
argocd app get-resource <APP> \
  --group apiextensions.k8s.io \
  --kind CustomResourceDefinition \
  --resource-name gateways.gateway.networking.k8s.io
```

---

## 6. 验收清单

```bash
# ① 复现命令（改前 / 改后各跑一次）
argocd app get-resource <APP> \
  --group apiextensions.k8s.io \
  --kind CustomResourceDefinition \
  --resource-name gateways.gateway.networking.k8s.io

# ② 组件日志里是否还有 PermissionDenied
kubectl -n "${ARGOCD_NAMESPACE}" logs deploy/argocd-server --tail=200 | grep -i permissiondenied
kubectl -n "${ARGOCD_NAMESPACE}" logs statefulset/argocd-application-controller --tail=200 | grep -i permissiondenied

# ③ 同步是否真的恢复（★ 读 CRD 成功 ≠ 整个 Application 权限完整）
argocd app sync <APP>
argocd app get <APP>        # status.sync.status == Synced
argocd app health <APP>

# ④ IAM 侧是否落到位
gcloud projects get-iam-policy "${TARGET_PROJECT_A}" \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${GSA_EMAIL}" \
  --format="table(bindings.role)"

# ⑤ 兜底：查审计日志确认被拒请求
gcloud logging read \
  'resource.type="k8s_cluster" AND protoPayload.status.code=403' \
  --limit=20 --project="${TARGET_PROJECT_A}" --format=json
```

---

## 7. 常见坑

| 现象 | 真因 | 处理 |
|---|---|---|
| 加了 ClusterRole 还是 PermissionDenied | RBAC subject 写错（模式 A/B 主体不同） | `kubectl auth whoami` 实测后重绑 |
| 加了 IAM 角色还是 PermissionDenied | 只授了 `customResourceDefinitions.get`，没授 `thirdPartyObjects.get` | 补齐 CR 实例权限 |
| 授了 `container.deployments.get` 但 diff 仍错 | 缺 `container.thirdPartyObjects.*` | 补权限 |
| 用了 `container.clusterViewer` 以为能读 CRD | 该角色**不含** CRD 权限 | 本方案靠集群内 RBAC 补齐 |
| 授予后 1–2 分钟内仍失败 | IAM 传播延迟 | 核对策略后重试 |
| 授予后长期失败 | token 未刷新 | 重启 Argo CD Pod + 清 gcloud token 缓存 |
| `kubectl apply` 加的注解被覆盖 | Helm/Kustomize 管理着 SA | 改用 kustomize patch |
| `argocd app get-resource` 通了但同步仍失败 | 只授了 `argocd-server`，controller/repo-server 没授 | 三个组件 KSA 都绑 |
| 只建了命名空间级 Role | CRD 是 cluster-scoped | 用 ClusterRole + ClusterRoleBinding |
| 跨项目授权没生效 | 授在了 Argo CD 所在项目 | 授到目标集群所在项目 |
| 多租户下越权 | IAM 角色默认覆盖项目内所有集群 | 优先集群内 RBAC；IAM 用 `--condition` 限定单集群 |
| `argocd-k8s-auth: not found` | 自定义/精简镜像没打包该插件 | 换官方镜像或自行打包 |
| Argo CD 同步 Role 报 "attempting to grant RBAC permissions not currently held" | Argo CD 只有 IAM 权限，没有对应 K8s RBAC 权限 | 用 RBAC 显式授出这些 verb，或授 `container.roles.bind` / `container.clusterRoles.bind` |
| 授权正确但连接超时 | 网络不通（Private cluster / VPC-SC / Control Plane 授权） | 见 [admin-guide §7.5](../argocd-admin-guide.md) |
| `kubectl auth whoami` 报不支持 | K8s < 1.27 或服务端未开 SelfSubjectReview | 用 `auth can-i` + 审计日志 |

---

## 8. 与其他文档的关系

- 三层权限模型（Argo CD RBAC × AppProject × K8s RBAC）→ [04-appproject-rbac.md](./04-appproject-rbac.md)
- 通用排障路径 → [09-troubleshooting.md](./09-troubleshooting.md)
- 多集群凭据与 cluster secret 写法 → [argocd-admin-guide.md §7](../argocd-admin-guide.md)
- Workload Identity 与 GCP 侧集成（Secret Manager 等）→ [argocd-admin-guide.md §7.8](../argocd-admin-guide.md)

---

## 9. 冲突与待确认点

### 9.1 三份材料间的冲突（已按核实结果裁决）

| # | 冲突点 | 裁决 | 依据 |
|---|---|---|---|
| C1 | 「GKE IAM 与 RBAC 二选一」 vs 「先 RBAC 后 IAM 的 fallback」 | **fallback**（RBAC 优先，IAM 兜底），任一放行即可 | GKE RBAC 官方文档原文 |
| C2 | 建议用 `roles/container.clusterViewer` 读 CRD | **错**。该角色不含 CRD 权限 | GKE IAM 角色清单：clusterViewer 仅 `clusters.connect/get/list` |
| C3 | RBAC subject 该写 KSA principal 还是 GSA 邮箱 | **取决于实际认证身份**，必须实测 | `kubectl auth whoami` |
| C4 | 只配 `argocd-server` + `application-controller` | **漏了 `argocd-repo-server`** | repo-server 也需回读目标集群 |
| C5 | 「集群内 RBAC 无效」 | **不准确**。RBAC 永远优先且优先检查 | 见 C1 |
| C6 | 方案只覆盖 CRD 读取 | **不够**。同步还需命名空间级 Role/RoleBinding | 见 §4.6 |

### 9.2 当前报错里最需要先解开的疑义

> 报错身份 `serviceAccount:<PROJECT_ID>.svc.id.goog[argocd/argocd-server]`
> 与方案 B 预期的 `argocd-gke-access@argocd-control.iam.gserviceaccount.com` **不一致**。

**这是实施前必须解决的第一个验证点**（§2.2 / §5 Step 5）。
如果实际请求使用的是 KSA Federation Principal 而非 GSA Impersonation，
就应该针对**实际的 KSA Principal** 配置目标集群授权，而不是给 GSA 绑权限。

### 9.3 已确认的环境信息

| 项 | 值 | 状态 |
|---|---|---|
| Argo CD 版本 | 3.5.5 | ✅ 已确认（3.5 GA 于 2026-08-04，3.5.5 为补丁版） |
| Control Plane 集群数 | 1 | ✅ 已确认 |
| Target 集群分布 | 多个、跨多个 GCP Project | ✅ 已确认 |
| 目标资源 | Gateway API CRD（cluster-scoped） | ✅ 已确认 |
| Workload Identity 模式 | 疑为 **模式 A（KSA 直接 Federation）** | ⚠️ **待实测确认**（§5 Step 5） |
| GSA 策略 | 一个共享 GSA 先解封，后续再拆分 | ✅ 已定 |

### 9.4 仍待确认

1. **实际认证身份**（GSA 邮箱 vs KSA Principal）→ 决定 RBAC subject 写法（**最关键**）
2. **Target 集群数量与项目清单** → 决定 IAM 批量脚本的变量列表
3. **Argo CD 镜像是否自带 `argocd-k8s-auth`** → 定制镜像需确认
4. **目标集群是否 Private / 有无 Control Plane 授权** → 决定网络前置条件
5. **Argo CD 是否需要创建 ClusterRole/RoleBinding** → 需要额外授
   `container.clusterRoles.bind` / `container.roles.bind`
   （注意：K8s 的 privilege-escalation 检查**不认 IAM 授权器**，
   Argo CD 若只有 IAM 权限，同步一个 Role 会报
   `attempting to grant RBAC permissions not currently held`）

---

## 10. 参考

- GKE API permissions（Kubernetes API ↔ `container.*` 权限映射表）：https://docs.cloud.google.com/kubernetes-engine/docs/reference/api-permissions
- GKE IAM 角色与权限（各 `roles/container.*` 实际包含哪些权限）：https://docs.cloud.google.com/iam/docs/roles-permissions/container
- GKE RBAC：IAM 与 RBAC 的 fallback 关系、subject 写法、escalate/bind 限制：https://docs.cloud.google.com/kubernetes-engine/docs/how-to/role-based-access-control
- GKE 访问权限控制总览：https://docs.cloud.google.com/kubernetes-engine/docs/concepts/access-control
- Workload Identity Federation for GKE（KSA Principal 格式、两种模式）：https://docs.cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
- GKE 身份验证问题排查：https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/authentication
- Argo CD Declarative Setup（cluster secret / GKE WI 官方示例）：https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/
- Argo CD v3.5 发布说明（内部 mTLS、ApplicationSet UI、Impersonation Beta）：https://github.com/argoproj/argo-cd/releases
