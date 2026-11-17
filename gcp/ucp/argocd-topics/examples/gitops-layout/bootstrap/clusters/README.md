# bootstrap/clusters/ · 集群清单（Cluster Manifest）

> 📌 **本目录是 `bootstrap/` 引导层的一部分**。
> bootstrap 到底是什么、为什么需要它、完整时序 → 看 [`../README.md`](../README.md)；
> 整条链路（PR → 门禁 → 点火 → 同步）→ 看 [`../../bootstrap-flow.md`](../../bootstrap-flow.md)。
>
> **一句话**：这个目录是「**集群 × 组件**」的**事实来源**（source of truth），
> 里面**没有任何一个文件是 Kubernetes 资源**，它们全部由 Argo CD 的
> **git 文件生成器**读取，用来展开成一个个 Application。

---

## 0. 先回答三个问题（本文档存在的理由）

| 你的疑问 | 结论 | 详见 |
|---|---|---|
| 一个 GCP project 下有多个 cluster，目录怎么放？ | **平铺**：`clusters/<cluster>/`，一个集群一个目录。集群多了不会让目录变深 | §4 |
| 集群名和环境绑定，那 `env` 字段是不是冗余？ | `env` 是**派生属性**（由集群名前缀决定），但**必须显式写**——git 文件生成器拿不到文件路径，字段是唯一数据来源。一致性靠 `validate-clusters.py` 保证 | §5 |
| 每个集群要一份**独立配置**（OPA 策略、Gateway…），放哪？ | **不放这里**。这里只放「开关」，配置放 `apps/<component>/overlays/cluster/<cluster>/` | §6 |

---

## 1. 这里面有什么、没有什么

```
bootstrap/clusters/
├── README.md                    ← 你正在读的这份
├── _templates/                  ← 复制模板（*.example 后缀 → 生成器永远读不到）
│   ├── cluster.yaml.example
│   ├── component.yaml.example
│   └── cluster-scoped-component.yaml.example
│
├── dev-01/                      ← 一个集群 = 一个目录
│   ├── cluster.yaml             ←   集群元信息（人 + 工具读）
│   └── components/              ←   「这个集群启用哪些组件」
│       ├── nginx.yaml           ←     一个文件 = 一个 (集群 × 组件) 组合
│       ├── api.yaml
│       ├── redis.yaml
│       ├── gatekeeper.yaml      ←     集群级：OPA 策略
│       └── gateway.yaml         ←     集群级：Gateway（Solo Mesh）
├── dev-02/                      ← 同一个 GCP project 里的第二个集群
├── prod-01/                     ← 第一个 GCP project 的 prod
└── prod-02/                     ← 第二个 GCP project 的 prod
```

| 是 | 不是 |
|---|---|
| ApplicationSet 的 git 文件生成器的**输入数据** | Kubernetes 资源（不会被 apply） |
| 「文件存在 = 该集群启用该组件」的**开关面板** | 组件代码本体（组件本体在 `apps/<component>/`） |
| 集群元信息（server / env / project / namespace / GCP 归属） | Cluster Secret 的声明（`argocd cluster add` 是另一件事） |

> ⚠️ **不会被 apply 这件事靠什么保证？**
> `bootstrap/kustomization.yaml` 只列了 10 个 Argo CD 资源，**故意不列 `clusters/`**。
> 没有这一步，目录源会递归扫描并尝试 apply 这些文件 → `failed to generate manifest for source`。
> 详见 [`../kustomization.yaml`](../kustomization.yaml)。

---

## 2. 三类文件，三种职责

| 文件 | 角色 | 谁读 | 缺了会怎样 |
|---|---|---|---|
| `cluster.yaml` | **集群身份**：server / env / project / namespace / GCP 归属 | 人 + `validate-clusters.py` | AppSet 仍能跑，但失去一致性校验的锚点 |
| `components/<name>.yaml` | **组件开关 + 目标坐标**（6 个扁平字段） | git 文件生成器 → ApplicationSet | 该集群就没这个组件 |
| `apps/<c>/overlays/cluster/<cluster>/` | **集群私有配置**（OPA 策略、Gateway 参数…） | Argo CD repo-server（渲染 Kustomize） | 渲染失败 → Application 报错 |

> **为什么 `components/*.yaml` 要把 `server` / `env` / `project` / `namespace` 都抄一遍？**
> 因为 **git 文件生成器（files generator）不暴露文件路径**——它只把文件内容摊平成参数。
> 想知道「这个文件在哪个集群目录下」，只能把 `cluster` 写进文件里。
> 这带来**重复**，重复就会**漂移**，所以才需要 §5.4 的校验脚本。

---

## 3. 字段约定（6 个必填字段）

`components/*.yaml` 的字段必须与 ApplicationSet 的 `flatten` 列表**完全一致**，
少一个字段，`missingkey=error` 会让**整个 ApplicationSet**报错（不是这一个 Application）。

| 字段 | 含义 | 约定 | 校验规则 |
|---|---|---|---|
| `component` | 组件名 | **必须等于文件名**（`nginx.yaml` → `nginx`） | ❌ 不一致即失败 |
| `cluster` | 集群名 | **必须等于所在目录名** | ❌ 不一致即失败 |
| `server` | K8s API 地址 | 必须与 Argo CD 里注册的 Cluster Secret 的 server **逐字一致** | ❌ 与 `cluster.yaml` 不一致即失败 |
| `env` | 环境 | `dev` / `stg` / `prod`；**必须等于集群名前缀** | ❌ 不一致即失败 |
| `project` | AppProject 名 | 约定 `platform-<env>` | ⚠️ 不一致告警 |
| `namespace` | 组件落点 | 约定 `platform-<env>` | ⚠️ 不一致告警 |

**扩展字段**（只写在 `cluster.yaml` 里，**不参与** ApplicationSet 展开，供人和工具读）：

| 字段 | 含义 | 为什么要它 |
|---|---|---|
| `gcpProject` | 集群归属的 GCP project | 多 project 场景下定位集群 |
| `gcpRegion` | 区域 | 生成 cluster secret / 网络配置时要用 |
| `vpc` | 所属 VPC | 网络排查 |
| `argocdClusterSecret` | 对应的 Argo CD Cluster Secret 名 | 排查「Secret 和清单对不上」 |
| `workloadIdentityServiceAccount` | 集群内 Argo CD 使用的 GSA | 多 project 身份隔离 |

---

## 4. 目录怎么放：平铺，按集群不按 project

**结论：`clusters/<cluster>/` 平铺，不要按 GCP project 再分一层。**

理由：

| 问题 | 平铺（现在这样） | 按 project 分层（`clusters/<gcpProject>/<cluster>/`） |
|---|---|---|
| 一个集群的组件清单在哪 | 一眼看到 | 多跳一层 |
| AppSet 的 glob | `bootstrap/clusters/*/components/nginx.yaml` | 变成 `bootstrap/clusters/*/*/components/nginx.yaml`，**多一层通配** |
| 集群跨 project 迁移 | 改 `cluster.yaml` 一处 + 挪目录 | 同上，但目录路径变了，glob 要跟着改 |
| 集群数量 | 与 project 数量无关 | 与 project 数量耦合 |

> 集群归属哪个 GCP project，是**集群的属性**（`gcpProject` 字段），
> 不是**目录的层级**。属性用字段表达，层级只表达「集群身份」。

### 4.1 AppProject 按**环境**分，不按 GCP project 分

```
platform-dev   → dev-01, dev-02          （可以跨 project）
platform-prod  → prod-01, prod-02         （可以跨 project）
```

`destinations` 里按 server 逐个列出：

```yaml
destinations:
- server: 'https://dev-01.k8s.example.com'
  namespace: 'platform-dev'
- server: 'https://dev-02.k8s.example.com'
  namespace: 'platform-dev'
```

> 💡 如果你确实要**按 project 隔离权限**（比如 prod-02 不许用 dev 的镜像仓库），
> 那就再拆一个 AppProject（`platform-prod-b`）。代价：AppProject 数量随 project 数量增长，
> 组件清单里的 `project` 字段也要跟着分叉。**先按环境拆，project 隔离用别的方式做**
> （源仓库白名单 / 镜像仓库策略）。

### 4.2 一个 GCP project 多个 cluster

`dev-01` 和 `dev-02` 都在 `acme-platform-dev`：

```yaml
# clusters/dev-01/cluster.yaml
gcpProject: acme-platform-dev
# clusters/dev-02/cluster.yaml
gcpProject: acme-platform-dev
```

它们各自：
- 有**独立的 Cluster Secret**（`argocd cluster add` 两次 → 两个 Secret，两套凭据）
- 有**独立的组件清单目录**（`clusters/dev-01/components/`、`clusters/dev-02/components/`）
- 走**同一个 AppProject**（`platform-dev`）和**同一套 overlay**（`apps/nginx/overlays/dev/`）

---

## 5. 「集群名和环境绑定」这件事怎么处理

### 5.1 前提

```
cluster 名 = <env>-<序号>        dev-01 / dev-02 / stg-01 / prod-01 / prod-02
env        = dev / stg / prod
project    = platform-<env>
namespace  = platform-<env>
```

即：**env 是集群名的派生属性**，不是独立维度。

### 5.2 为什么 `env` 字段还要写

| 理由 | 说明 |
|---|---|
| **生成器给不了路径** | git **文件**生成器只摊平**文件内容**，不提供文件所在目录。所以「这个文件属于哪个集群」只能写进文件里 |
| **overlay 路径要用它** | `apps/nginx/overlays/{{.env}}` —— 模板要靠它选环境层 |
| **显式优于隐式** | 目录名是给人看的，字段是给机器读的；字段缺失时 `missingkey=error` 会**立刻报错**，比"猜目录名"安全 |

### 5.3 为什么不改成 `clusters/<env>/<cluster>/`

| 理由 | 说明 |
|---|---|
| 信息**重复** | 目录已经是 `dev/`，文件名又是 `dev-01` → env 出现两次，**还可能出现两层不一致**（目录 `dev/`、目录里的集群叫 `prod-07`） |
| **解决不了任何问题** | 生成器依然只读文件内容，`env` 字段该写还得写 |
| **glob 变复杂** | `bootstrap/clusters/*/*/components/nginx.yaml`，且 `*` 会匹配到任何中间层 |
| 真正想解决的是「**每集群一份配置**」，那件事的答案是 §6 的 overlay 分层，不是目录分层 | |

> **什么时候才该改目录？** 当集群名**不带**环境含义时（例如 `cluster-a` / `cluster-b`，
> 或者用 GKE 的 `projects/*/locations/*/clusters/*` 原始名）。
> 那时环境信息就**只**存在于字段里，目录就不该再暗示环境。
> 当前命名约定是「名字带环境」，所以目录**保持平铺**。

### 5.4 一致性靠工具，不靠人记

```bash
# 在 gitops-layout/ 目录执行
# 校验 clusters/** 与 components/** 的一致性、字段完整性、渲染路径是否存在
python3 validate-clusters.py

# 预览展开结果（哪些集群会生成哪些 Application）
python3 preview-appset.py
```

`validate-clusters.py` 会检查：

| # | 检查项 | 级别 |
|---|---|---|
| 1 | `cluster.yaml` 存在，`cluster` 字段 == 目录名 | ❌ |
| 2 | 集群名前缀 == `env` | ❌ |
| 3 | `components/*.yaml` 的 6 个字段齐全 | ❌（对应 `missingkey=error`） |
| 4 | `component` == 文件名、`cluster` == 目录名 | ❌ |
| 5 | `server`/`env`/`project`/`namespace` 与 `cluster.yaml` 一致 | ❌ |
| 6 | `project`/`namespace` 是否符合 `platform-<env>` 约定 | ⚠️ |
| 7 | ApplicationSet 模板渲染出的 **source path 目录真实存在** | ❌ |
| 8 | 集群的 server 在对应 AppProject 的 `destinations` 里 | ❌（对应 "not match any of the allowed destinations"） |
| 9 | 集群级组件的 overlay 引用了**正确的环境层** | ❌ |

> 第 8 条尤其值钱：AppProject 与集群清单对不上，是最常见的「应用同步被拒」根因，
> 而且报错信息在 Argo CD 里很不直观。

---

## 6. 每个集群一份独立配置：base → env → cluster 三层 overlay

### 6.1 组件分两类，overlay 布局不同

| 组件类型 | 例子 | overlay 布局 | ApplicationSet 的 `source.path` |
|---|---|---|---|
| **环境级**（同环境所有集群一样） | nginx / api / redis | `apps/<c>/overlays/<env>/` | `apps/<c>/overlays/{{.env}}` |
| **集群级**（每个集群不一样） | gatekeeper / gateway | `apps/<c>/overlays/env/<env>/` + `apps/<c>/overlays/cluster/<cluster>/` | `apps/<c>/overlays/cluster/{{.cluster}}` |

### 6.2 三层各管什么

```
apps/gatekeeper/
├── base/                                  ← 组件本体（所有集群、所有环境共用）
│   ├── constrainttemplate.yaml            ←   ConstraintTemplate：策略逻辑
│   └── constraint.yaml                    ←   Constraint：策略参数（放哪个资源上）
└── overlays/
    ├── env/                               ← 环境层
    │   ├── dev/kustomization.yaml         ←   dev：enforcementAction=dryrun（先观察）
    │   └── prod/kustomization.yaml        ←   prod：enforcementAction=deny（真拦）
    └── cluster/                           ← 集群层（**每个集群一份**）
        ├── dev-01/kustomization.yaml      ←   dev-01：豁免名单、quota、白名单
        ├── dev-02/kustomization.yaml
        ├── prod-01/kustomization.yaml
        └── prod-02/kustomization.yaml
```

**叠加顺序**：`base` → `env/<env>` → `cluster/<cluster>`，越靠下越具体，后面的 patch 覆盖前面的。

```yaml
# apps/gatekeeper/overlays/cluster/dev-01/kustomization.yaml
resources:
  - ../../env/dev            # ← 环境层（已包含 base）
patches:
  - target:
      group: constraints.gatekeeper.sh
      kind: K8sRequiredLabels
      name: require-owner-label
    patch: |-
      - op: replace
        path: /spec/match/excludedNamespaces
        value: ["kube-system", "gatekeeper-system", "argocd", "platform-dev"]
```

### 6.3 ⚠️ 为什么 `overlays/<env>/<cluster>/` 嵌套写法不行

直觉上会想写成 `overlays/dev/dev-01/`，让集群层 `resources: - ..` 引用环境层。
**Kustomize 会直接报错**：

```
$ kubectl kustomize apps/gatekeeper/overlays/dev/dev-01
error: accumulating resources: accumulation err='accumulating resources from '..':
'/…/overlays/dev' must resolve to a file': cycle detected:
candidate root '/…/overlays/dev' contains visited root '/…/overlays/dev/dev-01'
```

原因：Kustomize 检测到**引用目标包含了自己**（父目录里有子目录）→ 判定为循环引用。

✅ 正确写法：`env/` 和 `cluster/` **是兄弟目录**，引用时不构成包含关系：

```
overlays/env/dev/          →  resources: [../../../base]
overlays/cluster/dev-01/   →  resources: [../../env/dev]
```

### 6.4 集群层里引用的环境层，必须和集群的 `env` 对上

`clusters/dev-01/cluster.yaml` 的 `env: dev` → 集群层必须引用 `../../env/dev`。
引用错了（dev-01 引用 `env/prod`）Kustomize **不会报错**，但 prod 的策略会跑到 dev 集群上。
→ 由 `validate-clusters.py` 第 9 条兜住。

---

## 7. 新增一个集群（checklist）

以新增 `dev-03` 为例：

```bash
# 1. 目录 + 集群元信息
mkdir -p bootstrap/clusters/dev-03/components
cp bootstrap/clusters/_templates/cluster.yaml.example bootstrap/clusters/dev-03/cluster.yaml
cp bootstrap/clusters/_templates/component.yaml.example bootstrap/clusters/dev-03/components/nginx.yaml
#    ↑ 改 cluster / server / env / project / namespace / gcpProject / gcpRegion …

# 2. 集群级组件的 overlay（gatekeeper / gateway …）
mkdir -p apps/gatekeeper/overlays/cluster/dev-03
cp apps/gatekeeper/overlays/cluster/dev-01/kustomization.yaml apps/gatekeeper/overlays/cluster/dev-03/
#    ↑ 改里面的集群特有参数（豁免名单等）

# 3. AppProject 的 destinations 加一条 server
#    bootstrap/appprojects/platform-dev.yaml

# 4. 注册集群到 Argo CD（这一步**不在 Git 里**）
argocd cluster add https://dev-03.k8s.example.com \
  --name dev-03 --project platform-dev

# 5. 校验
python3 validate-clusters.py && python3 preview-appset.py
kubectl kustomize apps/gatekeeper/overlays/cluster/dev-03 >/dev/null && echo "render OK"
```

> 🔁 **第 4 步是唯一不在 Git 里的一步**，也是最容易被忽略的一步：
> Git 里写了清单，但 Argo CD 里没注册这个 cluster → Application 会卡在
> `Unable to connect to server` / `cluster not found`。

## 8. 新增一个组件（checklist）

```bash
# 1. 组件本体
mkdir -p apps/<c>/base && cp apps/nginx/base/* apps/<c>/base/
# 2. overlay（环境级 or 集群级，见 §6.1）
mkdir -p apps/<c>/overlays/dev apps/<c>/overlays/prod
# 3. ApplicationSet（一个组件一个 AppSet）
cp bootstrap/applicationsets/component-nginx.yaml bootstrap/applicationsets/component-<c>.yaml
#    ↑ 改 generator 的 path（指向 components/<c>.yaml）、template 的 source.path
# 4. 在 bootstrap/kustomization.yaml 里列上这个 AppSet
# 5. 在目标集群的 components/ 下放开关文件
touch bootstrap/clusters/dev-01/components/<c>.yaml   # ← 文件存在 = 该集群启用
# 6. 校验
python3 validate-clusters.py
```

> ⭐ **组件开关 = 文件是否存在**。
> 加一个集群要用某组件 → 加一个文件；停用 → 删文件（集群资源因
> `preserveResourcesOnDeletion: true` 保留，需人工清理）。

---

## 9. 集群级组件示例 ①：OPA / Gatekeeper

> 你们的第一个目标：**每个集群接入 Argo CD 之后，都有一份自己的 OPA 策略。**

### 9.1 分工

| 部分 | 谁装 | 走不走 Argo CD |
|---|---|---|
| Gatekeeper 控制面（controller / webhook） | Helm / 官方 YAML，**装一次** | ❌ 走 Helm（或单独的 Application） |
| **策略**（ConstraintTemplate + Constraint） | **Git → Argo CD** | ✅ 每个集群一份 |

> ⚠️ 控制面如果也走 Argo CD，记得 AppProject 的 **cluster 级白名单**要放行
> `constraints.gatekeeper.sh` 的 `ConstraintTemplate` / `Constraint`
> （集群级资源默认被 `platform-prod` 的白名单挡住 → 同步报 "not permitted"）。

### 9.2 三层分别放什么

| 层 | 内容 | 例子 |
|---|---|---|
| `base/` | 策略**逻辑** + 策略**作用范围** | 「所有 Namespace 必须带 `owner` 和 `cost-center` 标签」 |
| `overlays/env/<env>/` | **强制力度** | dev = `dryrun`（只记录不拦），prod = `deny` |
| `overlays/cluster/<cluster>/` | **本集群的例外** | 豁免 namespace 列表、该项目特有的豁免规则 |

### 9.3 集群接入 OPA 的顺序（别搞反）

```
① Helm 装 Gatekeeper 控制面（failurePolicy=Ignore，观察期）
② Argo CD 应用 base（策略进入集群，但 dryrun，不拦）
③ 跑一段观察期：kubectl get constraints → 看 audit 违规统计
④ 调策略：改 base 或 env 层
⑤ 把 failurePolicy 从 Ignore 切 Fail（控制面层面）
⑥ 把 enforcementAction 从 dryrun 切 deny（策略层面）    ← prod 集群
⑦ 把 enforcementAction 切 deny（dev 集群）              ← dev 集群
```

> 🔴 **切 deny 之前一定先看违规统计**。Gatekeeper 挂了 + `failurePolicy: Fail`
> = **整个集群写不进去**，Argo CD 只会一直 OutOfSync。

### 9.4 Argo CD 侧必须配的 health check

Gatekeeper 的 CR（`Constraint` / `ConstraintTemplate`）有 `status`，
Argo CD **不知道**它们是否健康 → 不配 `resource.customizations.health.*` 的话
`selfHeal` 会对着 CR 空转。见 [`../../../../06-opa-gatekeeper-impact.md`](../../../../06-opa-gatekeeper-impact.md) §5。

---

## 10. 集群级组件示例 ②：Gateway（Solo Mesh）

### 10.1 分工

| 部分 | 谁装 | 走不走 Argo CD |
|---|---|---|
| Solo / Gloo 控制面（controller、CRD） | Helm | ❌ 一次性 |
| **数据面声明**（`Gateway`、`HTTPRoute`、`GatewayParameters`…） | **Git → Argo CD** | ✅ 每个集群一份 |
| 数据面 **Pod**（Deployment/ReplicaSet） | **控制器生成** | ❌ Argo CD 看不见，也管不了 |

### 10.2 控制面要不要也交给 Argo CD？

可以，而且这是「安装 / 升级」最省事的做法：把 Helm chart 做成 Argo CD 的 **Helm source**，
用一个**每集群一个**的 Application 管：

```yaml
# 这不是本示例的 AppSet（那个管的是数据面声明），而是控制面 Application 的形状
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gateway-control-plane-dev-01
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/example/platform.git
    targetRevision: main
    path: charts/gateway            # 里面是 Chart.yaml + values.yaml
    helm:
      releaseName: gloo-gateway
      valueFiles: [values-dev-01.yaml]   # 每集群一份 values
  destination:
    server: 'https://dev-01.k8s.example.com'
    namespace: gloo-gateway
```

| 好处 | 说明 |
|---|---|
| 升级 = 改 `Chart.yaml` / `targetRevision` | 走 PR + 审计 |
| 每集群不同版本 | `valueFiles` 按集群给 |
| 卸载 = 删 Application | 需确认 `prune` 与 CRD 的处理（CRD 不会被 helm 卸载） |

> ⚠️ **CRD 是另一件事**：Helm 不负责升级 CRD，`helm upgrade` 不会更新 CRD。
> CRD 升级要单独 `kubectl apply`（且要先备份现有 CR —— CRD 删了会连带删掉所有 CR）。
>
> ⚠️ 控制面和数据面分成两个 Application 后，**顺序**要保证：
> 控制面（CRD + controller）先就绪，再同步数据面声明。
> 最稳的做法是让数据面声明带 `wait` 依赖，或把两者合进同一个 Application 用 sync wave。

### 10.3 升级怎么做

| 升级对象 | 做法 | 走 Argo CD 吗 |
|---|---|---|
| 控制面（controller / CRD） | 改 Helm values 的 version → helm upgrade | ❌（或由专门的 Argo CD Application 管 Helm release） |
| CRD 版本 | 手动 `kubectl apply` + `helm upgrade`（CRD 不随 helm 升级） | ⚠️ 单独一步 |
| 数据面版本 | 改 `Gateway`/`GatewayParameters` 里的版本字段 → 控制器滚动重建 Pod | ✅ 走 Argo CD，但**Pod 不是 Argo 管的** |
| 集群级参数（副本数、超时、灰度） | `apps/gateway/overlays/cluster/<cluster>/` | ✅ |

> ⚠️ **别把控制器生成的 Deployment 写进 Git**——Argo CD 会和控制器抢所有权，
> 表现为两边互相 revert（Argo CD 说 "OutOfSync: extra resource"，控制器说 "recreated"）。
> 想让 Argo CD 管数据面 Deployment，就让控制器**不要**生成它。

### 10.4 蓝绿（blue-green）

先分清两种"蓝绿"：

| 层次 | 谁做 | 怎么做 |
|---|---|---|
| **Argo CD 同步级**蓝绿 | Argo CD | `syncOptions: [BlueGreen=true]`。**前提**：这个 Application 里**恰好一个 Deployment + 一个 Service**，且 Service 的 selector 能选中 Deployment 的 Pod |
| **数据面**蓝绿 | Solo / Gloo 控制器 | 控制器自己的替换/滚动策略（如 `replacementMode`）。因为数据面 Pod 是控制器生成的，**Argo CD 的 BlueGreen 对它无效** |

> ⚠️ `BlueGreen=true` 有前置条件，不满足会被 Argo CD 直接拒绝：
> 「Application 必须只包含一个 Deployment 和一个 Service」。
> 所以它**不能**用在 `apps/gateway/`（只有 Gateway/HTTPRoute，没有 Deployment）。
> 详见 [`../../../../05-appset.md`](../../../../05-appset.md) 与 Argo CD 官方
> "Blue-Green Deployment" 文档（版本差异较大，落地前按目标版本核对）。

### 10.5 同步顺序

多个 Application 之间要按顺序（比如：先装策略 → 再装网关 → 最后装业务）：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "10"    # 数字小的先同步
```

> ⚠️ sync wave 跨 Application 的生效行为**依赖 Argo CD 版本与是否在同一 namespace**，
> 落地前请在目标集群实测（`kubectl -n argocd get applications -o custom-columns=...`）。
> 最稳的做法：**把有顺序依赖的组件合并进同一个 Application**（用 Kustomize 的
> `resources` 组织），这样 wave 在一个 Application 内，一定生效。

---

## 11. 同步策略与失败模式

| 场景 | 现象 | 根因 | 处理 |
|---|---|---|---|
| 清单字段少一个 | **整个 AppSet** 报错，所有组件都不生成 | `missingkey=error` | 补字段；`validate-clusters.py` 能提前发现 |
| server 写错 | Application 卡 `Unable to connect` | 与 Cluster Secret 的 server 不一致 | 逐字比对（`kubectl -n argocd get secret <name> -o jsonpath='{.data.config}'`） |
| project / namespace 写错 | 同步被拒 `not match any of the allowed destinations` | AppProject 的 destinations 没覆盖 | `validate-clusters.py` 第 8 条 |
| 集群级 overlay 引用错环境层 | 策略静默跑错环境 | `cluster/dev-01` 引用了 `env/prod` | 同上第 9 条 |
| Gatekeeper 拒绝 | Application 一直 OutOfSync，集群里啥也没建 | 策略不通过 / webhook 挂了 | 看 `status.conditions[].message` |
| CR 一直 Progressing | `selfHeal` 空转 | 没配 CR health check | `resource.customizations.health.*` |
| 删了组件开关文件 | Application 消失，但集群资源还在 | `preserveResourcesOnDeletion: true` | 需要人工清理 |

---

## 12. 规模化之后再切：Merge 生成器（去重）

现在的形态每个集群要写 `1 + N` 个文件，其中 `components/*.yaml` 重复了 4 个字段。
**集群数超过 ~10、或组件数超过 ~5 时**，可以换成 **Merge 生成器**：
`cluster.yaml` 写一次元信息，组件文件只写 2 行。

```
clusters/dev-01/
├── cluster.yaml          ← cluster / server / env / project / namespace（唯一出处）
└── components/
    └── nginx.yaml        ← 只有：component: nginx / cluster: dev-01
```

```yaml
# bootstrap/applicationsets/_alternatives/component-nginx-merge.yaml
generators:
- merge:
    mergeKeys: [cluster]
    generators:
    - git:                     # 子生成器 1：集群元信息
        files:
        - path: "bootstrap/clusters/*/cluster.yaml"
          flatten: [cluster, server, env, project, namespace]
    - git:                     # 子生成器 2：组件开关
        files:
        - path: "bootstrap/clusters/*/components/nginx.yaml"
          flatten: [component, cluster]
```

**收益**：元信息只写一遍，**结构上**不可能漂移。
**代价**：多一层生成器间接；合并时某个集群缺 `cluster.yaml` 会让 AppSet 报错
（报错本身是好事，但错误信息不如逐文件清晰）。

> ⭐ **建议**：现在（Phase 1，先跑通）**保持当前扁平形态**——
> 它直观、可读、出错信息清楚。等集群/组件数量上来了再切 Merge，
> 切换时 `validate-clusters.py` 可以帮你把 `cluster.yaml` 和组件文件对齐。

---

## 13. 相关文档

| 主题 | 文档 |
|---|---|
| ApplicationSet 生成器全解 | [`../../../../05-appset.md`](../../../../05-appset.md) |
| AppProject / RBAC | [`../../../../04-appproject-rbac.md`](../../../../04-appproject-rbac.md) |
| OPA 三层与 Gatekeeper 影响面 | [`../../../../06-opa-gatekeeper-impact.md`](../../../../06-opa-gatekeeper-impact.md) |
| 概念速查（组件启停真相、目录职责） | [`../../../../argo-concept-sheet.md`](../../../../argo-concept-sheet.md) §3–4 |
| 本示例的顶层说明 | [`../../README.md`](../../README.md) |
