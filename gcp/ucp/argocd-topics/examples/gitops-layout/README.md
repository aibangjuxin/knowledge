# Argo CD · GitOps 仓库骨架示例（bootstrap + 组件 + 集群清单）

> **用途**：把 [`../../argo-concept-sheet.md`](../../argo-concept-sheet.md) 里的拓扑
> 落成一份**可读的最小仓库**，让你直观看到每个文件长什么样、放在哪、谁读它。
>
> **这是示例，不是可直接 apply 的生产配置**：所有 server 地址、仓库地址、凭据都是假的。

> 📌 **本目录有三个子文档**：
> - [`bootstrap/README.md`](./bootstrap/README.md) —— **引导层**的详细说明
>   （bootstrap 到底是什么、为什么需要它、11 步完整时序、每个文件的作用、常见失败）
> - [`bootstrap/clusters/README.md`](./bootstrap/clusters/README.md) —— **集群清单**的完整说明
>   （命名约定、多 GCP Project、每集群一份独立配置、OPA / Gateway 落位、演进路线）
> - 本文件 —— 整体骨架与操作顺序

---

## 目录结构

```
gitops-layout/
├── bootstrap/                          ← Root Application 只同步这个目录
│   ├── README.md                       ←   ⭐ 引导层详解（先读这份）
│   ├── kustomization.yaml              ←   控制"根应用到底 apply 哪些资源"
│   ├── root-application.yaml           ←   根应用自己（App of Apps 入口）
│   ├── repositories.yaml               ←   Git 凭据（GitHub App / PAT）
│   ├── appprojects/                    ←   边界层：能做什么
│   │   ├── platform.yaml               ←     父项目（公共约束，被继承）
│   │   ├── platform-dev.yaml           ←     dev 环境边界
│   │   └── platform-prod.yaml          ←     prod 环境边界
│   ├── applicationsets/                ←   生成层：生成什么、生成到哪
│   │   ├── component-nginx.yaml        ←     每个组件一个 AppSet
│   │   ├── component-api.yaml
│   │   ├── component-redis.yaml
│   │   ├── component-gatekeeper.yaml   ←     ⭐ 集群级组件（OPA 策略）
│   │   ├── component-gateway.yaml      ←     ⭐ 集群级组件（Gateway）
│   │   └── _alternatives/              ←     备选方案（不 apply）
│   │       └── component-nginx-merge.yaml  ← 规模化后切 Merge 生成器去重
│   └── clusters/                       ←   集群事实来源（不是 K8s 资源）
│       ├── README.md                   ←     ⭐ 本目录的完整说明
│       ├── _templates/                 ←     复制模板（*.example → 生成器读不到）
│       ├── dev-01/                     ←     一个集群 = 一个目录
│       │   ├── cluster.yaml            ←       集群元信息（server/env/project/…）
│       │   └── components/             ←       该集群启用哪些组件
│       │       ├── nginx.yaml          ←         文件存在 = 该集群启用该组件
│       │       ├── api.yaml
│       │       ├── redis.yaml
│       │       ├── gatekeeper.yaml     ←         集群级：OPA 策略
│       │       └── gateway.yaml        ←         集群级：Gateway
│       ├── dev-02/                     ←     同一 GCP project 的第二个集群
│       ├── prod-01/                    ←     第一个 GCP project 的 prod
│       └── prod-02/                    ←     第二个 GCP project 的 prod
│
├── apps/                               ← 组件本体（base + overlay）
│   ├── nginx/
│   │   ├── base/{kustomization.yaml,deployment.yaml,service.yaml}
│   │   └── overlays/{dev,prod}/kustomization.yaml
│   ├── api/
│   │   ├── base/{kustomization.yaml,deployment.yaml}
│   │   └── overlays/{dev,prod}/kustomization.yaml
│   ├── redis/
│   │   ├── base/{kustomization.yaml,statefulset.yaml}
│   │   └── overlays/dev/kustomization.yaml
│   ├── gatekeeper/                     ← ⭐ 集群级组件：OPA 策略
│   │   ├── base/                       ←   策略本体（ConstraintTemplate + Constraint）
│   │   └── overlays/
│   │       ├── env/{dev,prod}/         ←   环境层：强制力度（dryrun / deny）
│   │       └── cluster/{dev-01,…}/     ←   集群层：本集群的豁免名单
│   └── gateway/                        ← ⭐ 集群级组件：Gateway（Solo Mesh）
│       ├── base/                       ←   Gateway + HTTPRoute
│       └── overlays/
│           ├── env/{dev,prod}/
│           └── cluster/{dev-01,…}/
│
├── preview-appset.py                   ← 离线模拟 ApplicationSet 展开
├── validate-clusters.py                ← 校验集群清单的一致性（防手抄漂移）
└── demo.sh                             ← ⭐ 一键 Demo：命令行跑完整套 GitOps 流程
```

---

## ⭐ 一键 Demo：`demo.sh`

```bash
cd examples/gitops-layout

./demo.sh plan      # 只打印将要执行的命令（离线，不需要 docker/kind/集群）
./demo.sh apply     # 真跑：建集群 → 装 Argo CD → 建 AppProject/AppSet/App → 同步
./demo.sh verify    # 只做验证与资源清单罗列
./demo.sh cleanup   # 删 kind 集群 / 停后台服务 / 删工作目录
./demo.sh           # = plan + apply + verify
```

它按 **11 个步骤** 把整套体系用命令行跑一遍：

| STEP | 做什么 | 对应的 Argo CD 概念 |
|---|---|---|
| 00 | 环境自检（docker / kind / kubectl / argocd CLI） | —— |
| 01 | kind 建 5 个集群：`argocd`（控制面）+ 4 个业务集群 | 模拟多集群 |
| 02 | 安装 Argo CD 控制面 | —— |
| 03 | 起本地 Git HTTP 服务，把示例仓库**改写**成演示仓库（repoURL / 各集群 server） | Repository 拉取源 |
| 04 | `argocd login` + 端口转发 | —— |
| 05 | 注册 Git 仓库 | **Repository** |
| 06 | 注册被纳管集群（声明式 Cluster Secret） | **Cluster Secret** |
| 07 | `kubectl apply` 三个 AppProject | **AppProject**（边界层，必须先于根应用） |
| 08 | `argocd app create` 根应用 → Argo CD 自己从 Git 拉 AppSet | **Application**（App of Apps 入口） |
| 09 | 等 ApplicationSet 生成 Application 并同步 | **ApplicationSet**（生成层） |
| 10 | 验证：AppProject / AppSet / App 清单 + 集群内真实资源 + 渲染结果抽样 | —— |
| 11 | 清理 | —— |

> ⚠️ 脚本**不会**动你的原始仓库：所有改写都发生在 `$WORKDIR`（默认
> `/tmp/ucp-gitops-demo`）下的副本里。
>
> 依赖：docker、kind、kubectl、argocd CLI、git、python3。
> 缺 kind / argocd CLI 时可以加 `--install-tools` 让脚本自动下载。
> macOS 与 Linux 都跑得起来（脚本处理了两边的 `base64` / `sed -i` / `docker 网关` 差异）。

---

## 三个开关，两层含义

| 开关 | 载体 | 生效动作 | 取消后的结果 |
|---|---|---|---|
| **组件全局启用** | `bootstrap/applicationsets/component-<name>.yaml` 存在 | Root App 同步出该 ApplicationSet → 生成各集群的 Application | AppSet 被 prune → 它生成的 Application 随之删除 → 集群资源被 prune |
| **组件在某集群启用** | `bootstrap/clusters/<cluster>/components/<name>.yaml` 存在 | Git generator 枚举到该文件 → 生成指向该集群的 Application | 该集群的这个 Application 消失 → 该集群资源被 prune |
| **组件整体下线（安全）** | 两者都删 + `preserveResourcesOnDeletion: true` | Application 消失但**保留**集群资源 | 需要人工清理 |

> `preserveResourcesOnDeletion: true` 写在 ApplicationSet 模板里，
> 对**所有**生成的 Application 生效 —— 这是防误删的关键一行。

### ⭐ 还有第四个开关：**组件是"环境级"还是"集群级"**

| | 环境级（nginx / api / redis） | 集群级（gatekeeper / gateway） |
|---|---|---|
| overlay 路径 | `apps/<c>/overlays/{{.env}}` | `apps/<c>/overlays/cluster/{{.cluster}}` |
| overlay 结构 | base → env | base → env → **cluster** |
| 同环境多集群 | 共用一份 | **每集群一份** |
| 典型 | 业务工作负载 | OPA 策略、Gateway、集群 agent |

---

## 一次展开的完整链路（以 nginx 为例）

```
bootstrap/applicationsets/component-nginx.yaml
        │  template.spec.project: '{{.project}}'（由 cluster 清单决定）
        │  source.path: apps/nginx/overlays/{{.env}}
        ▼
git generator: 匹配 bootstrap/clusters/*/components/nginx.yaml
        │  dev-01/components/nginx.yaml  → {cluster: dev-01, server: …, env: dev,  …}
        │  dev-02/components/nginx.yaml  → {cluster: dev-02, server: …, env: dev,  …}
        │  prod-01/components/nginx.yaml → {cluster: prod-01, server: …, env: prod, …}
        │  prod-02/components/nginx.yaml → {cluster: prod-02, server: …, env: prod, …}
        ▼
生成 Application × 4
        ├── nginx-dev-01   → server=dev-01  ns=platform-dev   project=platform-dev
        ├── nginx-dev-02   → server=dev-02  ns=platform-dev   project=platform-dev
        ├── nginx-prod-01  → server=prod-01 ns=platform-prod  project=platform-prod
        └── nginx-prod-02  → server=prod-02 ns=platform-prod  project=platform-prod
```

> 集群级组件（gatekeeper / gateway）走同一条链路，只是 `source.path` 换成
> `overlays/cluster/{{.cluster}}` → 每个集群渲染自己的那份 overlay。

### 离线预览展开结果（不用连集群）

```bash
$ python3 preview-appset.py

清单文件: 17 个   组件: 5 个

ApplicationSet/api  →  生成 4 个 Application
    api-dev-01   project=platform-dev   ns=platform-dev   server=https://dev-01.k8s.example.com
    api-dev-02   project=platform-dev   ns=platform-dev   server=https://dev-02.k8s.example.com
    api-prod-01  project=platform-prod  ns=platform-prod  server=https://prod-01.k8s.example.com
    api-prod-02  project=platform-prod  ns=platform-prod  server=https://prod-02.k8s.example.com

ApplicationSet/gatekeeper  →  生成 4 个 Application
    gatekeeper-dev-01   project=platform-dev   ns=platform-dev   server=https://dev-01.k8s.example.com
    gatekeeper-dev-02   project=platform-dev   ns=platform-dev   server=https://dev-02.k8s.example.com
    gatekeeper-prod-01  project=platform-prod  ns=platform-prod  server=https://prod-01.k8s.example.com
    gatekeeper-prod-02  project=platform-prod  ns=platform-prod  server=https://prod-02.k8s.example.com

ApplicationSet/gateway  →  生成 4 个 Application
    gateway-dev-01   project=platform-dev   ns=platform-dev   server=https://dev-01.k8s.example.com
    gateway-dev-02   project=platform-dev   ns=platform-dev   server=https://dev-02.k8s.example.com
    gateway-prod-01  project=platform-prod  ns=platform-prod  server=https://prod-01.k8s.example.com
    gateway-prod-02  project=platform-prod  ns=platform-prod  server=https://prod-02.k8s.example.com

ApplicationSet/nginx  →  生成 4 个 Application
    nginx-dev-01   project=platform-dev   ns=platform-dev   server=https://dev-01.k8s.example.com
    nginx-dev-02   project=platform-dev   ns=platform-dev   server=https://dev-02.k8s.example.com
    nginx-prod-01  project=platform-prod  ns=platform-prod  server=https://prod-01.k8s.example.com
    nginx-prod-02  project=platform-prod  ns=platform-prod  server=https://prod-02.k8s.example.com

ApplicationSet/redis  →  生成 1 个 Application
    redis-dev-01   project=platform-dev   ns=platform-dev   server=https://dev-01.k8s.example.com

集群视角（组件装在哪些集群）
    dev-01   5 个组件: api, gatekeeper, gateway, nginx, redis
    dev-02   4 个组件: api, gatekeeper, gateway, nginx
    prod-01  4 个组件: api, gatekeeper, gateway, nginx
    prod-02  4 个组件: api, gatekeeper, gateway, nginx

合计应生成 17 个 Application
```

> `redis` 只有 1 个 Application —— 因为只有 `dev-01` 有 `components/redis.yaml`。
> **这就是「文件存在即启用」的直接证据。**

### 本地校验（不连集群）

```bash
# ① YAML 语法 + 根应用到底会 apply 什么（应为 10 个：3 AppProject + 5 ApplicationSet + 1 Repository + 1 Application）
kubectl kustomize bootstrap | grep -E '^kind:|^  name:'

# ② 集群清单一致性（字段齐全 / 与 cluster.yaml 一致 / 渲染路径存在 / destinations 覆盖）
python3 validate-clusters.py

# ③ 组件 overlay 渲染
kubectl kustomize apps/nginx/overlays/prod | grep -E 'replicas:|count:'

# ④ 集群级 overlay 渲染（base → env → cluster 三层叠加）
kubectl kustomize apps/gatekeeper/overlays/cluster/prod-01 | grep enforcementAction   # → deny
kubectl kustomize apps/gatekeeper/overlays/cluster/dev-01  | grep enforcementAction   # → dryrun
```

---

## 谁读哪个文件

| 文件 | 读者 | 读取方式 | 备注 |
|---|---|---|---|
| `bootstrap/**` | Root Application | Argo CD 目录/Kustomize 源 | 只有 `kustomization.yaml` 里列出的才会被 apply |
| `bootstrap/clusters/**` | ApplicationSet controller | `git` 文件生成器 | **不是** K8s 资源，不会被 apply |
| `bootstrap/appprojects/**` | Argo CD 校验器 + Casbin | 资源约束 | 被 `spec.project` 逻辑引用 |
| `bootstrap/applicationsets/**` | ApplicationSet controller | 生成器 | 生成的 Application 带 ownerReference |
| `apps/**` | Argo CD repo-server | `spec.source.path` | 真正被 apply 到集群的内容 |

---

## 应用顺序（本地试跑）

```bash
# 1. 先 apply AppProject（否则 Application 会落到 default 项目）
kubectl apply -f bootstrap/appprojects/

# 2. 再 apply ApplicationSet（会立刻生成 Application）
kubectl apply -f bootstrap/applicationsets/

# 3. 最后 apply 根应用（之后交给 Git 管）
kubectl apply -f bootstrap/root-application.yaml

# 4. 看生成结果
kubectl -n argocd get applications -o wide
kubectl -n argocd get applicationsets
```

> 真实生产里这一步不需要手动 —— Root Application 会做同样的事。
> 但 Root Application 需要**先存在**，所以首次安装走“手动 apply 根应用”这一步。
> 注意顺序：**AppProject 必须先于根应用**，否则根应用引用的 `project: platform`
> 不存在，第一次同步会报 “project not found”。
>
> 还有一步在 Git 之外：**`argocd cluster add` 注册集群**。
> Git 里写了清单但没注册集群 → Application 卡 “Unable to connect”。

---

## 五个必须知道的坑（本示例已规避）

| # | 坑 | 后果 | 本示例怎么规避 |
|---|---|---|---|
| 1 | `bootstrap/` 里混入**非 K8s 资源**的文件（本文的 `clusters/**`） | 目录源会递归扫描并尝试 apply → `failed to generate manifest for source` | 用 `bootstrap/kustomization.yaml` 限定根应用只 apply 10 个资源 |
| 2 | `syncPolicy.automated.prune` / `selfHeal` 在 CRD 里是 **boolean** | 写成 `'{{.prune}}'` 会被 API server 拒掉（schema 校验失败） | 不做环境差异化模板；prod 要人工审批就拆一个 prod 专用 AppSet（用 `selector: 'env == "prod"'`） |
| 3 | Kustomize 的 `commonLabels` 会**改写 selector** | 滚动升级时新旧 Pod 互不匹配 → 滚动更新卡住 | 用 `labels:` + `includeSelectors: false` |
| 4 | 删组件清单文件 → Application 消失 → `prune` 把集群资源也删了 | 误删线上组件 | 模板里统一开 `preserveResourcesOnDeletion: true`，下线组件保留资源待人工确认 |
| 5 | 集群层 overlay 写成 `overlays/<env>/<cluster>/` 且 `resources: [..]` | Kustomize 报 `cycle detected`（父目录包含子目录） | 用**兄弟目录**：`overlays/env/<env>/` + `overlays/cluster/<cluster>/` |

> 坑 #2 的 schema 依据：本仓库 `install.yaml:8015-8017`（v3.5.6 官方清单）
> 中 `automated.prune` / `selfHeal` 的类型是 `boolean`。
> 部署前可用 `kubectl apply --dry-run=server` 在目标集群复核。
>
> 坑 #5 的实测报错：
> ```
> $ kubectl kustomize apps/gatekeeper/overlays/dev/dev-01
> error: accumulating resources: accumulation err='accumulating resources from '..':
> '/…/overlays/dev' must resolve to a file': cycle detected
> ```

---

## 与现有专题的对应

| 本示例 | 详见 |
|---|---|
| **`bootstrap/`（引导层）** | [`./bootstrap/README.md`](./bootstrap/README.md) |
| `appprojects/*` | [`../../04-appproject-rbac.md`](../../04-appproject-rbac.md) |
| `applicationsets/*` | [`../../05-appset.md`](../../05-appset.md) |
| `apps/gatekeeper/*`（OPA） | [`../../06-opa-gatekeeper-impact.md`](../../06-opa-gatekeeper-impact.md) |
| `bootstrap/clusters/**` | [`./bootstrap/clusters/README.md`](./bootstrap/clusters/README.md) |
| `bootstrap/` 与根应用 | [`../../../argocd-admin-guide.md`](../../../argocd-admin-guide.md) §6.1–6.2 |
| 概念速查表 | [`../../argo-concept-sheet.md`](../../argo-concept-sheet.md) |
