# Istio Revision 机制详解 — K8s 资源管理视角的完整图谱

> **TL;DR**:
> - **Istio revision 不是简单"标签"**,它是一整套 **K8s 资源管理机制**(标签 + Webhook + Service + Deployment + Revision Tag 间接别名)
> - **核心能力**:在同一集群里**同时跑多个独立 istiod**,通过 `istio.io/rev` namespace label 切流,**实现零中断升级**
> - **不只能做版本控制**:还能做 **A/B 环境隔离 / 蓝绿发布 / 多团队独立控制面 / 灰度迁移**
> - **本场景已用 minimal profile**(无 revision),未来切 ambient 时引入 `revision=1-30` 命名 + 双 revision canary

---

## 0. 这篇文档要解决什么

> Lex 通读本目录后,在 `PERSONAL-FOCUS-LIST.md` 关注 5.1/5.2 / `12-revision-canary-mtls-compat.md` 反复看到 revision 概念,但没看到完整的资源管理视角。
>
> **疑问**:revision 是什么?K8s 资源层面它做了什么?它能实现什么应用场景?

**本文档的目标**:
1. **机制层** — revision 在 K8s 上**实际由哪些资源构成**(Deployment / Service / MutatingWebhook / labels)
2. **流程层** — **namespace label → Webhook → 注入 → istiod 选哪个** 的完整链路
3. **场景层** — **版本控制 / 灰度 / A/B / 多团队** 等典型应用场景
4. **限制层** — revision **能做什么 / 不能做什么**
5. **本场景现状与未来** — 当前 minimal 怎么用,未来 ambient 怎么用

---

## 1. 一句话定位

| 概念 | 一句话定位 |
|---|---|
| **Revision** | Istio 控制面(istiod)的**实例标识** + **namespace selector**,允许同一集群跑多个独立 istiod |
| **`istio.io/rev` 标签** | Namespace 上的"我要哪个 istiod 管我"标记 |
| **Revision Tag** | **间接别名机制** — `prod-stable` 是标签,背后指向真正的 `1-9-5` revision |

---

## 2. K8s 资源管理 — revision 由哪些资源构成?

> revision **不是某个 K8s 资源类型**,而是**多个资源的组合模式**。

### 2.1 核心资源构成

| 资源类型 | 资源名 | 数量 | 作用 |
|---|---|---|---|
| **Deployment** | `istiod-<revision>` | 每个 revision 一个 | 跑 istiod 实例 |
| **Service** | `istiod-<revision>` | 每个 revision 一个 | 工作负载连这个 Service 拉 XDS 配置 |
| **ConfigMap** | `istio-<revision>` | 每个 revision 一个 | istiod 自己的 config(bootstrap 配置等)|
| **MutatingWebhookConfiguration** | `istio-revision-tag-<tag>` 或 `istio-sidecar-injector-<revision>` | 每个 revision 一个 | 拦截 pod 创建,注入 sidecar |
| **ClusterRole / ClusterRoleBinding** | `istiod-<revision>` | 每个 revision 一个 | RBAC 权限 |

### 2.2 实际清单(双 revision 例子)

```bash
# 假设集群装了两个 revision:"1-30" 和 "1-31-canary"

# 1. Deployments
kubectl get deploy -n istio-system -l app=istiod
# NAME                        READY   UP-TO-DATE   AVAILABLE
# istiod                      2/2     2            2          ← revision="1-30" 但不带后缀
# istiod-1-31-canary          2/2     2            2          ← revision="1-31-canary"

# 2. Services
kubectl get svc -n istio-system -l app=istiod
# NAME                       TYPE        CLUSTER-IP    PORT(S)
# istiod                     ClusterIP   10.96.x.x     15010/TCP,15012/TCP,443/TCP,15014/TCP
# istiod-1-31-canary         ClusterIP   10.96.y.y     15010/TCP,15012/TCP,443/TCP,15014/TCP

# 3. Webhooks(MutatingWebhookConfiguration 是 K8s 原生类型)
kubectl get mutatingwebhookconfigurations | grep istio
# NAME                          WEBHOOKS   AGE
# istio-revision-tag-default    1          100d
# istio-sidecar-injector-1-31-canary   1   5d   ← 新 revision 注册的 webhook
# (老 revision "1-30" 通常不显式注册,用 "default" tag 兜底)

# 4. ConfigMap
kubectl get cm -n istio-system -l istio.io/rev
# NAME                       DATA   AGE
# istio                      1      100d
# istio-1-31-canary          1      5d
```

### 2.3 Service 是关键 — workload 怎么选 istiod?

```bash
# 验证:business pod 的 istio-agent 连哪个 istiod
istioctl proxy-config endpoint <business-pod> -n <business-ns> | grep istiod

# 输出示例:
# ENDPOINT                CLUSTER      STATUS
# 10.96.x.x:15010         xds-grpc     HEALTHY    ← 这个 IP 是 istiod-1-30
```

**Service 名 = 路由键** — namespace 的 `istio.io/rev` label 决定 pod 的 istio-agent 连哪个 Service。

---

## 3. 完整调用链 — "namespace label → 注入 → 配置下发"

> 这是 revision 机制的**核心链路**。每一步都标注 K8s 资源类型。

```
Step 1: 用户给 namespace 加 label
   kubectl label ns team-a-runtime istio.io/rev=1-31-canary

Step 2: 新 pod 创建
   kubectl apply -f deployment.yaml  (创建 pod)
   ↓
Step 3: K8s API server 收到 PodCreate 请求
   ↓ MutatingWebhookConfiguration 拦截
   ↓ K8s 查询所有 MutatingWebhookConfigurations
   ↓ 匹配 namespaceSelector + objectSelector

   例如:
   - 假设有两个 webhook:"istio-revision-tag-default" 和 "istio-sidecar-injector-1-31-canary"
   - 第一个的 namespaceSelector:
     matchExpressions:
       - key: istio.io/rev
         operator: In
         values: ["default"]                          ← 不匹配 team-a-runtime
   - 第二个的 namespaceSelector:
     matchExpressions:
       - key: istio.io/rev
         operator: In
         values: ["1-31-canary"]                      ← ✅ 匹配 team-a-runtime

   ↓ K8s 把请求发给 "istio-sidecar-injector-1-31-canary" 的 webhook service
   ↓ 这个 service 后端是 istiod-1-31-canary (port 443)
   ↓ istiod-1-31-canary 收到请求,根据 chart 模板注入 sidecar

Step 4: istiod 修改 pod spec(添加 sidecar 容器 + volumes)
   ↓ 返回修改后的 pod spec
   ↓ K8s 接受修改,创建带 sidecar 的 pod

Step 5: pod 启动
   ↓ pod 内 istio-agent 启动
   ↓ istio-agent 通过环境变量 ISTIO_META_ISTIOD_ADDR 或
     Pod Annotation "sidecar.istio.io/istiod" 知道要连哪个 istiod
   ↓ 连 istiod-1-31-canary.istio-system.svc:15012(mTLS)
   ↓ 拉 XDS 配置(LDS / RDS / CDS / EDS)
   ↓ 开始正常工作
```

### 3.1 关键引用:Webhook 配置

> 来源:[Istio manifests/charts/default/templates/mutatingwebhook.yaml](https://github.com/istio/istio/blob/master/manifests/charts/default/templates/mutatingwebhook.yaml)

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: istio-sidecar-injector-1-31-canary
  labels:
    istio.io/rev: "1-31-canary"
    istio.io/tag: "1-31-canary"             # revision tag
webhooks:
- name: rev.namespace.sidecar-injector.istio.io
  clientConfig:
    service:
      name: istiod-1-31-canary             # ← webhook 后端指向新 revision
      namespace: istio-system
      path: /inject
  rules:
    - operations: ["CREATE"]
      apiGroups: [""]
      apiVersions: ["v1"]
      resources: ["pods"]
  namespaceSelector:                        # ← 这个 webhook 只对特定 ns 生效
    matchExpressions:
      - key: istio.io/rev
        operator: In
        values: ["1-31-canary"]
  objectSelector:                           # ← 排除 pod-level 显式说不注入的
    matchExpressions:
      - key: sidecar.istio.io/inject
        operator: NotIn
        values: ["false"]
```

**这是 revision 机制的核心** — 每个 revision 注册自己的 MutatingWebhook,namespaceSelector 限定作用范围,**互不干扰**。

### 3.2 标签优先级与互斥规则

| 优先级 | 标签 | 行为 |
|---|---|---|
| **最高** | `sidecar.istio.io/inject=false`(pod 上)| 强制**不**注入 sidecar |
| 高 | `istio-injection=disabled`(ns 上)| 强制不注入 |
| 中 | `istio-injection=enabled`(ns 上)| 注入,用**默认 revision**(tag `default` 指向的)|
| 中 | `istio.io/rev=<revision>`(ns 上)| 注入,用**指定 revision** |
| 低 | (无 label) | 默认不注入(`enableNamespacesByDefault=false`)|

**冲突规则**:
- `istio-injection=enabled` + `istio.io/rev=canary` **同时存在** → `istio-injection` 优先(用默认 revision,**忽略** `istio.io/rev`)
- `istio.io/rev=canary` + `istio-injection=disabled` 同时存在 → `istio-injection` 优先(不注入)
- `istio.io/rev=canary` + 没 `istio-injection` → 用 `istio.io/rev` 指定的 revision 注入

> 来源原文: "If the `istio-injection` label and the `istio.io/rev` label are both present on the same namespace, the `istio-injection` label will take precedence." — [Istio Sidecar Injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/)

---

## 4. Revision Tag — "间接别名"机制(1.10+ 引入)

> Lex 在 12 文 / 05 文看到 `prod-stable` 这种 tag,这是 Revision Tag 概念。

### 4.1 为什么需要 Revision Tag?

**问题场景**:
```bash
# 你装了 revision 1-9-5,所有 ns 都打了 istio.io/rev=1-9-5
kubectl label ns prod-a istio.io/rev=1-9-5
kubectl label ns prod-b istio.io/rev=1-9-5

# 升版时:把所有 ns 改成 1-10-0?
# 问题 1:100 个 ns 改 label 工作量大
# 问题 2:改 label 不会触发 pod 重启(需手动 rollout restart)
```

**Revision Tag 解决**:
```bash
# 1. 装 revision 1-10-0(平行)
istioctl install -y --set profile=minimal --revision 1-10-0

# 2. 创建 tag "prod-stable" 指向 1-9-5
istioctl x revision tag set prod-stable --revision 1-9-5

# 3. 给 ns 贴 tag(不是 revision!)
kubectl label ns prod-a istio.io/rev=prod-stable   # 注意:贴的是 tag 名

# 4. 现在升版,只改 tag 指向
istioctl x revision tag set prod-stable --revision 1-10-0 --overwrite
# ↓
# 所有贴 prod-stable 的 ns 自动切到 1-10-0(还需 rollout restart pod)
```

### 4.2 Revision Tag 是 K8s 资源吗?

**是**。`istioctl tag set` 实际创建的是:

```bash
# 列出 tag 的 MutatingWebhookConfigurations
kubectl get mutatingwebhookconfigurations -l istio.io/tag
# NAME                          WEBHOOKS
# istio-revision-tag-prod-stable    1
# istio-revision-tag-default        1
```

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: istio-revision-tag-prod-stable
  labels:
    istio.io/tag: "prod-stable"              # ← tag 名
    istio.io/rev: "1-9-5"                    # ← 真实 revision
webhooks:
  - name: rev.namespace.sidecar-injector.istio.io
    clientConfig:
      service:
        name: istiod                          # ← 1-9-5 对应的 Service
        namespace: istio-system
    namespaceSelector:
      matchExpressions:
        - key: istio.io/rev
          operator: In
          values: ["prod-stable"]             # ← 匹配 tag 名
```

**关键**:**tag 也是一个 MutatingWebhookConfiguration**,只是 label 不同。

### 4.3 `default` Tag 的特殊地位

> 来源:[Istio Helm Upgrade with Revision Tags](https://istio.io/latest/docs/setup/upgrade/helm/)

```bash
# 列出所有 tag
istioctl x revision tag list
# TAG         REVISION   NAMESPACES
# default     1-9-5      istioinaction
# prod-stable 1-9-5      <none>
# prod-canary 1-10-0     istioinaction-canary
```

**`default` tag 是特殊的** — 它做的事:

| 职责 | 详情 |
|---|---|
| **注入没 explicit label 的 pod** | 默认 revision 注入 `istio-injection=enabled` ns + `sidecar.istio.io/inject=true` pod + `istio.io/rev=default` ns |
| **验证 Istio 资源** | 集群中所有 Istio CRD(AuthorizationPolicy 等)的 schema 验证 |
| **Steals leader lock** | 从其他 revision 偷 K8s leader lock,做单例 mesh 职责(更新资源状态)|
| **CRD status 更新** | 集群级 status 由 default revision 负责 |

> 来源原文: "The default revision performs the following functions: Injects sidecars for the `istio-injection=enabled` namespace selector, the `sidecar.istio.io/inject=true` object selector, and the `istio.io/rev=default` selectors; Validates Istio resources; Steals the leader lock from non-default revisions and performs singleton mesh responsibilities." — [Istio Helm Upgrade](https://istio.io/latest/docs/setup/upgrade/helm/)

### 4.4 Revision Tag 与 Revision 的关系

```
Revision(实体,如 1-9-5)
  ↓ 由 istioctl install --revision=1-9-5 部署
  ↓ 对应 Deployment istiod-1-9-5、Service istiod-1-9-5、ConfigMap istio-1-9-5

Revision Tag(别名,如 prod-stable)
  ↓ 由 istioctl x revision tag set prod-stable --revision=1-9-5 创建
  ↓ 对应 MutatingWebhookConfiguration istio-revision-tag-prod-stable
  ↓ 指向"已存在的某个 revision"

Namespace 上的 istio.io/rev 标签
  ↓ 既可以贴 revision(如 1-9-5)
  ↓ 也可以贴 tag(如 prod-stable)
  ↓ 区别:贴 tag 可以不改 ns label 就切 revision
```

---

## 5. Revision 能做什么 — 应用场景矩阵

### 5.1 核心场景:版本控制(零中断升级)

```
┌────────────────────────────────────────────────────────────┐
│ 时序                                                     │
│                                                            │
│ T0: 装 revision 1-30,所有 ns 贴 istio.io/rev=1-30          │
│                                                            │
│ T1: 装 revision 1-31-canary(平行,不影响生产)              │
│                                                            │
│ T2: 给 canary ns 贴 istio.io/rev=1-31-canary,           │
│     滚动重启 pod,验证 1-2 周                              │
│                                                            │
│ T3: 全量切流:                                              │
│     for ns in $(kubectl get ns -l ... -o name); do       │
│       kubectl label "$ns" istio.io/rev=1-31-canary        │
│       kubectl rollout restart deployment -n "$ns"        │
│     done                                                   │
│                                                            │
│ T4: 退役老 revision:                                       │
│     kubectl get pods -A -o json |                          │
│       jq '.items[].metadata.labels["istio.io/rev"]'        │
│     # 确认无 pod 还在用 1-30                               │
│     helm uninstall istiod -n istio-system  # 卸 1-30     │
└────────────────────────────────────────────────────────────┘
```

**业务影响** = 零(切流期间老 pod 不动,新 pod 用新 revision)
**回滚** = 把 label 改回老 revision

### 5.2 A/B 环境隔离(多团队独立控制面)

```
同一集群,装 2 个 revision:
  - revision "team-a": team-a 专属配置(NetworkPolicy / AuthZ 收紧)
  - revision "team-b": team-b 专属配置(NetworkPolicy / AuthZ 宽松)

team-a-runtime ns 贴 istio.io/rev=team-a
team-b-runtime ns 贴 istio.io/rev=team-b

结果:
  - 团队间互不干扰
  - 可独立升级 team-a vs team-b
  - 适合多团队共享大集群
```

### 5.3 蓝绿发布(GitOps 友好)

```
# 蓝环境(revision "blue" 指向 1-30)
istioctl x revision tag set blue --revision 1-30

# 绿环境(revision "green" 指向 1-31)
istioctl x revision tag set green --revision 1-31

# ns 切换 tag 即可蓝绿切流
kubectl label ns prod blue=   # 用蓝色
kubectl label ns prod green= # 用绿色
```

### 5.4 多版本 mesh 联邦

```
# 同一集群装多个 mesh ID 的 revision
istioctl install --revision=1-30 --set meshConfig.meshId=mesh-prod
istioctl install --revision=1-30 --set meshConfig.meshId=mesh-staging --set revision=1-30-staging

# ns 选 mesh
kubectl label ns prod-a istio.io/rev=1-30
kubectl label ns staging-a istio.io/rev=1-30-staging

# 适合:
# - 测试环境用 staging mesh
# - 生产用 prod mesh
```

### 5.5 灰度迁移(从 sidecar 到 ambient)

```
# 这个最相关本场景:从 sidecar 切 ambient 时用 revision

Phase 1: 装 ambient control plane,revision "ambient-1-30"
Phase 2: 业务 ns 切 dataplane-mode=ambient + istio.io/rev=ambient-1-30
Phase 3: 验证 1-2 周
Phase 4: 全量切流
Phase 5: 退役老 sidecar revision
```

### 5.6 不能做什么?

| 场景 | 限制 |
|---|---|
| **多 revision 跨集群联邦** | 需要每个集群独立装 revision,通过 EW Gateway 联通 |
| **同一 revision 跨大版本**(1.30 → 1.31)| 必须装新 revision,不能 in-place 升级 |
| **revision 之间的策略共享** | 每个 revision 独立处理 Istio CRD(CRD 共享但 webhook 独立)|
| **revision 之间的证书共享** | 同一 trust domain 下共享,详见 `12-revision-canary-mtls-compat.md` |

---

## 6. 严格定义 vs 简化解释(关键限定)

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **Revision** | "istiod 的版本标签" | "A revision is a label applied to istiod (and dependent charts) that namespaces opt into via the `istio.io/rev` label; multiple revisions may coexist in one cluster." — [Istio Canary Upgrades](https://istio.io/latest/docs/setup/upgrade/canary/) |
| **`istio.io/rev` 标签** | "ns 选哪个 istiod" | "Istio control plane revision or tag associated with the resource; e.g. `canary`. Feature Status: Beta. Resource Types: Namespace, Gateway, Pod." — [Istio Resource Labels](https://istio.io/latest/docs/reference/config/labels/) |
| **Revision Tag** | "间接别名" | "Revision tags allow for the creation of mutable aliases referring to control plane revisions for sidecar injection. With revision tags, rather than relabeling a namespace from 'istio.io/rev=revision-a' to 'istio.io/rev=revision-b' to change which control plane revision handles injection, it's possible to create a revision tag 'prod' and label our namespace 'istio.io/rev=prod'." — [istioctl/pkg/tag/tag.go](https://github.com/istio/istio/blob/master/istioctl/pkg/tag/tag.go) |
| **Default revision** | "默认那个" | "The revision pointed to by the tag `default` is considered the default revision and has additional semantic meaning. The default revision performs the following functions: Injects sidecars for the `istio-injection=enabled` namespace selector, the `sidecar.istio.io/inject=true` object selector, and the `istio.io/rev=default` selectors; Validates Istio resources; Steals the leader lock from non-default revisions and performs singleton mesh responsibilities (such as updating resource statuses)." — [Istio Helm Upgrade](https://istio.io/latest/docs/setup/upgrade/helm/) |
| **`istio-injection` vs `istio.io/rev`** | "两种注入开关" | "If the `istio-injection` label and the `istio.io/rev` label are both present on the same namespace, the `istio-injection` label will take precedence." — [Istio Sidecar Injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) |

---

## 7. 决策树 — 我该不该用 revision?

```
我现在的场景?
  │
  ├─ 单集群 + 接受升级短暂中断
  │   └─ ❌ 不用 revision(单 revision 原地升即可)
  │
  ├─ 单集群 + 不能中断
  │   └─ ✅ 用 revision + 双 canary(本场景 Phase 3)
  │
  ├─ 单集群 + 多团队 / 多环境
  │   └─ ✅ 用 revision(A/B 隔离 / 蓝绿)
  │
  ├─ 多集群 + 联邦
  │   └─ ✅ 用 revision(每集群独立验证)
  │
  ├─ sidecar → ambient 迁移
  │   └─ ✅ 用 revision(05 文 §6 + 本场景 Phase 2-4)
  │
  └─ dev / test 集群
      └─ ⚠️ 单 revision 即可(revision 是 Beta,稳定但有复杂度)
```

---

## 8. 本场景当前用法与未来引入

### 8.1 当前用法(2026-09-17)

```bash
# 当前 dev 集群:minimal profile + revision=""(默认)
kubectl get deploy -n istio-system -l app=istiod
# NAME      READY
# istiod    2/2     ← 没有后缀 = revision=""(默认)

# 验证当前是 default revision
istioctl x revision list
# TAG       REVISION
# default   default
```

**当前状态**:**单 revision**(default),没有用 revision 机制。

### 8.2 未来引入路径

| Phase | revision 用法 |
|---|---|
| **Phase 0(当前)** | default revision(`""`),namespace 不打 `istio.io/rev` |
| **Phase 1(装 ambient 控制面)** | 装 ambient 组件,保持 default revision(`""`) |
| **Phase 2(业务 ns 迁 ambient)** | ns 改 `istio.io/dataplane-mode=ambient`,**保持 default revision** |
| **Phase 3(双 revision 升 1.31)** | **首次用 revision** — 装 `1-31-canary`,ns 改 `istio.io/rev=1-31-canary`,退役 `1-30` |
| **Phase 4(引入 L7)** | 仍用 `1-31-canary`,policy 配 `istio.io/rev` label 防老版本误读 |

### 8.3 本场景首次用 revision 的步骤

```bash
# Step 1: 装 canary revision(平行装,不替换)
helm upgrade --install istiod-1-31-canary \
  oci://gcr.io/istio-release/charts/istiod \
  --namespace istio-system \
  --version 1.31.3 \
  -f values/istiod-1-31.yaml              # 含 revision: "1-31-canary"

# Step 2: 验证双 revision 并存
kubectl get deploy -n istio-system -l app=istiod
# NAME                       READY
# istiod                     2/2     ← revision "" (老)
# istiod-1-31-canary         2/2     ← revision "1-31-canary" (新)

kubectl get svc -n istio-system -l app=istiod
# NAME                       TYPE
# istiod                     ClusterIP     ← revision "" Service
# istiod-1-31-canary         ClusterIP     ← revision "1-31-canary" Service

kubectl get mutatingwebhookconfigurations | grep istio
# NAME                                          WEBHOOKS
# istio-revision-tag-default                    1
# istio-sidecar-injector-1-31-canary            1   ← 新 revision 注册的 webhook

# Step 3: 给 canary ns 贴新 revision label
kubectl label namespace canary-ns istio.io/rev=1-31-canary --overwrite
kubectl rollout restart deployment -n canary-ns

# Step 4: 验证 canary ns 业务 pod 连新 istiod
istioctl proxy-config endpoint <canary-pod> -n canary-ns | grep istiod
# 应显示 istiod-1-31-canary

# Step 5: 全量切流(逐 ns)
for ns in $(kubectl get ns -l istio.io/dataplane-mode=ambient -o name); do
  kubectl label "$ns" istio.io/rev=1-31-canary --overwrite
  kubectl rollout restart deployment -n "${ns#namespace/}"
  sleep 60
done

# Step 6: 退役老 revision
kubectl get pods -A -o json | \
  jq -r '.items[] | {ns: .metadata.namespace, rev: (.metadata.labels["istio.io/rev"] // "<none>")} |
  "\(.ns)\t\(.rev)"' | sort | uniq -c | sort -rn
# 预期:所有 ns 都是 1-31-canary

helm uninstall istiod -n istio-system   # 卸老 revision
```

---

## 9. 反向:revision 机制的限制与坑

| 限制 | 详情 |
|---|---|
| **每个 revision 都需要资源** | Deployment + Service + ConfigMap + Webhook,双 revision ≈ 双倍 istiod 资源 |
| **改 revision label 不重启 pod** | 必须 `kubectl rollout restart` 才生效(05 文 §6 已说明)|
| **退役前必须验证** | 否则老 revision 卸载后,残留 pod 失去 istiod 接入 |
| **default revision 是单例** | 集群中只能有一个 default tag,做验证 / leader lock / status 更新 |
| **跨 revision 资源验证** | Istio CRD(AuthZ / Telemetry)由 default revision 验证,可能引发版本兼容问题 |
| **revision 数量上限** | 官方建议 ≤ 3 个(资源消耗 + Webhook 路由复杂度)|
| **跨 trust domain 不支持 revision 互通** | revision 只在同 cluster / 同 trust domain 下有意义 |
| **revision 不替代 multicluster** | multicluster 需独立部署 + EW Gateway 联通 |

---

## 10. 与 K8s 原生概念的类比

| K8s 原生 | Istio revision | 类比 |
|---|---|---|
| **Deployment ReplicaSet 标签** | `istio.io/rev` label | 都是 selector 机制 |
| **Service selector → Pod** | Service istiod-rev → Deployment istiod-rev | 都是路由键 |
| **K8s Webhook 拦截 pod 创建** | MutatingWebhookConfiguration 注入 sidecar | 同样的拦截模式 |
| **Helm Release name** | revision 是 helm install 的差异化 | 同样的命名空间隔离思路 |
| **Git branch** | revision tag 切换 | 间接别名,可改指向 |

---

## 11. References

### 11.1 权威来源

- [Istio Canary Upgrades](https://istio.io/latest/docs/setup/upgrade/canary/) — 双 revision 安装
- [Istio Revision Tags Blog](https://istio.io/latest/blog/2021/revision-tags/) — Revision Tag 起源
- [Istio Helm Upgrade with Revision Tags](https://istio.io/latest/docs/setup/upgrade/helm/) — Helm 升版 + tag
- [Istio Sidecar Injection](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) — `istio.io/rev` 标签机制
- [Istio Resource Labels](https://istio.io/latest/docs/reference/config/labels/) — `istio.io/rev` Feature Status: Beta
- [Istio mutatingwebhook.yaml 模板](https://github.com/istio/istio/blob/master/manifests/charts/default/templates/mutatingwebhook.yaml) — Webhook 实际配置
- [Istio istioctl/pkg/tag/tag.go](https://github.com/istio/istio/blob/master/istioctl/pkg/tag/tag.go) — Revision Tag 源码

### 11.2 本目录关联文档

- `05-upgrade-strategies.md` — 双 revision canary 升级流程
- `12-revision-canary-mtls-compat.md` — 双 revision 的 mTLS / 证书兼容
- `11-l7-zero-downtime-constraint.md` — L7 AuthZ 与 revision 的关联
- `06-policy-capabilities.md` — AuthorizationPolicy 与 revision
- `ADR-LOCAL-001-migrate-minimal-to-ambient.md` — Phase 3 升 1.31 用 revision
- `PERSONAL-FOCUS-LIST.md` — Lex 个人关注清单

### 11.3 现有架构参考

- `k8s-gateway/01-platform/install-istio.sh` — 当前 minimal 装(无 revision)
- `k8s-gateway/k8s-Gateay-README.md` — Gateway + ListenerSet 多租户架构

---

## 12. 关键认知 checklist(自测)

读完本文后,你能回答下列问题吗?

| # | 问题 | 答案要点 |
|---|---|---|
| 1 | revision 在 K8s 资源层面**由什么构成**? | Deployment + Service + ConfigMap + MutatingWebhookConfiguration + ClusterRole |
| 2 | namespace 的 `istio.io/rev` label **怎么决定** 业务 pod 连哪个 istiod? | label 决定哪个 webhook 拦截;webhook 后端是哪个 istiod Service;pod 的 istio-agent 连那个 Service |
| 3 | **`istio-injection` 与 `istio.io/rev` 冲突时谁优先**? | `istio-injection` 优先 |
| 4 | **Revision Tag 与 Revision 区别**? | Tag 是**间接别名**(可变指向),Revision 是**实体**;改 tag 指向 = 不改 ns label 切 revision |
| 5 | **Default revision 的特殊职责**? | 注入未显式标的 pod + 验证 Istio 资源 + 抢 leader lock + 更新 status |
| 6 | revision 机制能做的**典型应用场景**? | 零中断升级 / A/B 隔离 / 蓝绿 / 多 mesh / 灰度迁移 |
| 7 | 退役老 revision 前的**硬性前置**? | 验证无 pod 引用老 revision(`kubectl get pods -A -o jsonpath='{.items[].metadata.labels.istio\.io/rev}'`)|
| 8 | 本场景**首次用 revision 的时机**? | Phase 3 — 升 1.31 时装 1-31-canary |

> 自测 8/8 = 已掌握;6-7 = 大部分懂;≤ 5 = 重读 §3-5