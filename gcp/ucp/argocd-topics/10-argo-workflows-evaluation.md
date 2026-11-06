# 10 · Argo Workflows：概念梳理与引入评估

> **本文定位**：概念理解 + 引入决策，**不涉及部署**。
> 上游事实以 **Argo Workflows v4.1**（`v4.1.6`, 2026-10-22 发布）与 **Argo CD stable** 文档为准。
> 标注含义沿用本套文档约定：**官方保证** / **推荐实现** / **部署前验证项** / **本文判断**。

---

## 0. TL;DR

### 一句话结论

> **不引入 Argo Workflows 作为我们 API 交付链路的发布执行器。**
> 我们要的"受治理的发布执行器"，Argo CD 自身 + 既有治理组件（Gatekeeper / Sync Windows / Notifications）
> 已经覆盖；Argo Workflows 提供的是**另一类正交语义**（命令式、跑一次就结束的多步编排），
> 把它放进 CD 主链路会引入**第二个控制面**，与"单控制面"目标直接冲突。

### 三条依据

| # | 依据 | 说明 |
|---|---|---|
| E1 | **语义正交，不是缺失** | Argo CD 是**声明式、持续收敛**（期望状态 → 实际状态）；Argo Workflows 是**命令式、运行一次即结束**（一次 DAG 执行）。前者不因为缺了后者而"不完整"。 |
| E2 | **上游自己就这么切** | Argo Workflows 官方文档的 **CI/CD** 场景页直接写 "Head to the Argo CD docs"；**Infrastructure Automation** 场景页指向 **Argo Events**。官方并未把 Workflows 定位为 CD 流水线引擎。 |
| E3 | **成本不对称** | Workflows = +`argo-server`(2~3 副本) +`workflow-controller` +CRD(v4 需 server-side apply) +归档/同步数据库 +产物仓库 +第二套 RBAC/UI。收益只在"运行时动态编排"这一小块。 |

### 但它不是"没用"

Argo Workflows 在**三种场景**里有不可替代的增量价值（§6.3），只是**都不在我们的 CD 主链路上**：
① 运行时动态计算的批量扇出；② 跨步骤的失败补偿/人工闸门；③ 一次性运维剧本（runbook）自动化。

### 什么时候该回来找它

见 **§8 复评触发条件**。当前 12 项能力需求中，**Workflows 只有 1 项是净增量**，且我们还没触发。

---

## 1. 我们的背景与约束（评估前提）

### 1.1 目标架构

```
                        ┌──────────────────────────────────────────┐
                        │        Git（单一事实源 / 审计基线）        │
                        │  · API manifest (Kustomize overlay)      │
                        │  · AppProject / ApplicationSet           │
                        │  · Sync Windows / 策略声明                │
                        └───────────────────┬──────────────────────┘
                                            │ pull
                        ┌───────────────────▼──────────────────────┐
                        │   UCP 控制面：Argo CD（GKE，单点 HA）      │
                        │   · app-controller（多集群 reconcile）     │
                        │   · appset-controller（批量扇出）          │
                        │   · repo-server / server / dex / redis     │
                        │   · notifications（审计与通告）            │
                        └───────┬──────────────┬───────────────┬────┘
                                │              │               │
             ┌──────────────────▼──┐  ┌────────▼─────────┐  ┌──▼──────────────────┐
             │ GKE 集群 A（proj-1） │  │ GKE 集群 B（proj-2）│  │ GKE 集群 C（proj-N） │
             │ ambient mesh        │  │ ambient mesh      │  │ ambient mesh        │
             │  ├ ztunnel (L4 mTLS)│  │  ├ ztunnel        │  │  ├ ztunnel          │
             │  ├ waypoint (L7)    │  │  ├ waypoint       │  │  ├ waypoint         │
             │  └ Knative Serving  │  │  └ Knative       │  │  └ Knative          │
             └─────────────────────┘  └──────────────────┘  └─────────────────────┘
                    ▲                                          ▲
                    └──── Gatekeeper Admission（准入拦截）──────┘
```

参考实现口径见 [`../../gateway-2.0/k8s-gateway-ambient/case-lex/`](../../gateway-2.0/k8s-gateway-ambient/case-lex/)（ambient + Gateway API + waypoint 的资源组织方式）。

### 1.2 边界（明确做什么 / 不做什么）

| 维度 | 本期范围 | 明确排除 |
|---|---|---|
| 交付物 | **API 的 Deployment / Knative Service / Gateway / HTTPRoute 等** | VPC / Subnet / Cloud SQL / GCS Bucket 等集群外资源（见 [`00-architecture-no-crossplane.md`](./00-architecture-no-crossplane.md) §3 硬边界） |
| 阶段 | **CD**（Git → 集群） | CI（镜像构建/测试）**待后续评估**，本期不预设方案 |
| 平台 | 多项目、多个 GKE 集群 | KCC / Fleet / Config Sync 等云基础设施编排 |
| 网络 | 所有业务 API 最终跑在 **ambient mesh**（ztunnel L4 + waypoint L7） | sidecar 模式 |
| 弹性与流量 | **Knative Serving**（弹性伸缩 + 渐进式流量/金丝雀/蓝绿） | Argo Rollouts（见 §7.2 为什么不混用） |

### 1.3 由背景推出的四条硬约束（评估的判断基准）

| # | 约束 | 含义 | 对 Argo Workflows 的直接影响 |
|---|---|---|---|
| **C1** | **声明式优先** | Git 是唯一事实源；任何"执行器"都不应持有独立的期望状态 | Workflows 是命令式引擎，天然与 C1 争夺事实源 |
| **C2** | **单控制面** | 不引入第二个"能常态改集群状态"的常驻组件 | Workflows 自带 controller + server + DB，违反 C2 |
| **C3** | **治理优先于编排** | 变更必须可审计 / 可冻结 / 可准入 / 可回滚 | Workflows 的一等公民是"跑一次"，不是"守住状态" |
| **C4** | **每个动作可归因** | "谁、为什么、改了什么"要能查 | Workflows 的执行历史在 Workflow 对象里，与 Argo CD 的审计链路不天然对齐 |

> 有了 C1–C4，评估其实已经收敛：**只有当某个能力"无法用声明式持续收敛表达"时，Workflows 才有净增量**（§6.3 列出）。

---

## 2. Argo Workflows 是什么

### 2.1 定位（**官方保证**）

> Argo Workflows is an open source **container-native workflow engine** for orchestrating **parallel jobs on Kubernetes**.
> —— argo-workflows.readthedocs.io，Home 页

拆解这句话里的三个限定词：

| 限定词 | 含义 | 推论 |
|---|---|---|
| **container-native** | 编排单元是容器，不是 VM / 不是函数 | 每个 step 会真的起 Pod（有调度、启动、镜像拉取的延迟与成本） |
| **workflow engine** | 它是**执行引擎**，不是**状态收敛器** | 期望状态 → 实际状态这件事它不做 |
| **on Kubernetes** | 它是 K8s 的一个 CRD + Controller | 它本身要占用一个集群的资源、要有 CRD、有 namespace 边界 |

CNCF 毕业项目，Apache-2.0，官方仓库约 17k star。生态下游包括 Argo Events、Hera(Kotlin/Python SDK)、Kubeflow Pipelines、Kedro、Metaflow、Seldon、SQLFlow 等。**官方保证**：Apache-2.0，v4.1.6（2026-10-22）。

### 2.2 核心对象模型（**官方保证**）

| 对象 | 作用 | 备注 |
|---|---|---|
| `Workflow` | **既是定义，也是状态**。官方原文：Workflow "serves two important functions: defines the workflow to be executed / stores the state of the workflow"，因此被描述为 **a "live" object** | 一次执行 = 一个 Workflow 实例（`generateName`） |
| `WorkflowTemplate` | 集群内可复用的工作流定义 | 同 namespace 内 `templateRef` 调用 |
| `ClusterWorkflowTemplate` | 集群级可复用定义 | 跨 namespace 调用 |
| `CronWorkflow` | 定时触发 | 每次触发生成一个 Workflow |
| `ArtifactRepository` / `Artifact` | 步骤间的数据传递（S3 / GCS / Artifactory / OSS / Azure Blob / HTTP / Git / raw / plugin） | 我们用 GCS，无新增依赖 |
| `Pod` | **每个 step / DAG task 的运行时载体** | 见 §2.4 |

**"live object" 是理解 Argo Workflows 一切设计取舍的钥匙**：
它把"程序"和"进程状态"塞进同一个对象，因此它**天生不适合**做"期望状态持续收敛"——那正是 Argo CD 的活。

### 2.3 九种模板类型（**官方保证**）

分两类：**定义类**（干活的）与**调用类**（控制流的）。

**定义类（7 种）**

| 类型 | 做什么 | 备注 |
|---|---|---|
| `container` | 跑一个容器（等价于 K8s container spec） | 最常用；stdout 自动导出为 `{{steps.x.outputs.result}}` / `{{tasks.x.outputs.result}}` |
| `script` | container 的便捷包装，加 `source:` 内联脚本 | 脚本写文件后执行；stdout 同样自动导出 |
| `resource` | **直接对集群资源做 create/apply/delete/replace/patch/get** | 官方示例即创建 ConfigMap |
| `suspend` | 挂起（定时 or 人工恢复） | 人工闸门的基础 |
| `plugin` | 调用 executor plugin（如发 Slack） | 副作用型动作 |
| `containerSet` | 一个 Pod 内跑多个容器 | |
| `http` | **直接发 HTTP 请求**，响应体自动导出为 `result` 输出 | v3.2+；**这是 Workflows 与 Argo CD API 交互的关键抓手** |

**调用类（2 种）**

| 类型 | 做什么 |
|---|---|
| `steps` | 列表的列表：外层顺序执行，内层并行；支持 `when:` 条件分支、同步屏障 |
| `dag` | 显式依赖图：`dependencies: [A, B]`，无依赖的任务立即并行 |

### 2.4 执行模型：每个 step = 一个 Pod（**官方保证**）

官方架构文档原文要点：

- 每个 Step / DAG Task **各生成一个 Pod**；
- 传统 Pod 布局含 **3 个容器**：
  - `main` —— 挂载 `argoexec` 作为主命令，拉起用户指定的镜像命令
  - `init` —— 拉取 artifact / 参数
  - `wait` —— 保存参数与 artifact、清理
- v4.1 起提供 **init-less pod 布局**（opt-in，Beta）：用 K8s `image volume`（KEP-4639）投递 `argoexec`，`supervisor` 容器接管前后置职责，artifact plugin 变成 sidecar。

> **成本含义**：一个 5 步串行的工作流 = 5 次 Pod 调度 + 5 次容器启动 + 可能的镜像拉取。
> 每次同步都走一遍这样的链路，延迟与费用都是**线性叠加**的。

### 2.5 组件拓扑（**官方保证**）

```
        ┌────────────────────── argo namespace ──────────────────────┐
        │  workflow-controller (Deployment, 1 副本 + hot-standby 可选) │
        │  argo-server           (Deployment, 2~3 副本，UI + REST/gRPC) │
        └───────────────────────────────┬───────────────────────────────┘
                                        │ reconcile
                    ┌───────────────────▼───────────────────┐
                    │  Workflow CR  →  每个 step 一个 Pod       │
                    │  (业务 namespace，可 Managed Namespace) │
                    └─────────────────────────────────────────┘
```

- Controller **可以独立运行**（不装 argo-server 就没有 UI/API，只能用 kubectl）。
- 安装方式三选一：**cluster install**（默认，监听所有 ns）/ **namespace install** / **managed namespace install**。
- v4 起 CRD **带完整校验信息**，官方要求用 **server-side apply** 安装（否则撞 K8s 对象大小限制），另有 `argo-workflows-crdinstaller` 镜像兜底。

### 2.6 与 Argo CD 的本质差异（本文核心表）

| 维度 | Argo CD | Argo Workflows |
|---|---|---|
| 范式 | 声明式持续收敛（reconciliation） | 命令式执行一次（run-to-completion） |
| 真相来源 | Git（+ 目标集群实际状态） | Workflow 对象的 `status` |
| 驱动方式 | 期望 ≠ 实际 → 自动同步 | 显式 submit / cron / 事件 / hook 触发 |
| 产物 | 集群中的资源状态 | 一棵执行树（每步一个 Pod）+ 产出物 |
| 失败语义 | 状态漂移 → 继续收敛；同步失败 → 重试/回滚由 sync policy 决定 | 某步失败 → 按 retry 策略重试；仍失败则整条工作流失败 |
| 谁是"常驻控制面" | 是 | 是（controller + server） |
| 审计 | Argo CD 事件 / Notifications / 操作日志 | Workflow 对象历史（另一个体系） |
| 多集群 | **原生**（集群 secret + ApplicationSet cluster generator） | 需跨集群 kubeconfig，**非一等公民** |
| 与 Git 的关系 | 核心 | 无（工作流定义通常也放 Git，但那是"代码"不是"期望状态"） |

**一句话**：Argo CD 管"**东西该长什么样**"，Argo Workflows 管"**这件事按什么顺序怎么做**"。
两者可以共存（官方就支持把 Workflow 当 Argo CD 的 hook），但**不能互相替代**。

---

## 3. 核心特性清单

> 全部为 **官方保证**（v4.1 文档）；"成熟度"一栏中 `GA/稳定` 与 `Beta` 按上游文档措辞。

| 能力类 | 特性 | 成熟度 | 对我们的意义 |
|---|---|---|---|
| **编排** | `steps` 顺序/并行 | 稳定 | 阶段编排 |
| | `dag` 依赖图 | 稳定 | 依赖编排、并行扇出 |
| | `when:` 条件分支 | 稳定 | 条件执行 |
| | 同步屏障（`synchronization`） | 稳定 | 并发收敛 |
| | `withItems` / `withParam` / `withSequence` 循环 | 稳定 | 批量处理 |
| **执行控制** | 步骤级 / 工作流级 `retry` | 稳定 | 失败重试 |
| | 步骤级 / 工作流级 `timeout` | 稳定 | 超时保护 |
| | `suspend` / `resume`（人工闸门） | 稳定 | 人工审批 |
| | `exit handler`（无论成败都跑的清理步骤） | 稳定 | 补偿逻辑 |
| | `parallelism` / `parallelismLimit` | 稳定 | 并发上限 |
| | 节点选择 / 亲和 / 容忍 / PDB | 稳定 | 落到指定集群节点 |
| | `podGC` / `TTLStrategy` / `workflow GC` | 稳定 | 清理，避免资源堆积 |
| | `memoization`（按 key 复用结果） | 稳定 | 重复执行省算力 |
| **数据** | 参数（global / workflow / step 三层） | 稳定 | 输入 |
| | Artifact + ArtifactRepository（**GCS 支持**） | 稳定 | 步骤间大对象传递 |
| | `resource` 模板直接操作 K8s 资源 | 稳定 | 步骤可直接改集群 |
| | `http` 模板 | v3.2+ | **可调 Argo CD API**（触发 sync、轮询状态） |
| **调度** | `cronWorkflow` | 稳定 | 定时任务 |
| | webhook 触发 | 稳定 | 外部事件拉起 |
| **集成** | Argo Events（EventSource/Sensor/EventBus） | 独立项目 | 事件驱动自动化 |
| | Executor Plugin / Artifact Plugin（v4 新增 artifact plugin） | 稳定 | 扩展动作类型 |
| | 多集群（跨集群 kubeconfig） | 可用 | 非一等公民 |
| | workflow-of-workflows（父工作流用 `resource` 模板创建子 Workflow） | 稳定 | 动态扇出 |
| **可观测** | UI（argo-server） | 稳定 | 需要独立 UI + 独立登录 |
| | REST/gRPC API、CLI（`argo submit/logs/resume/retry`） | 稳定 | 脚本化 |
| | Prometheus 指标 | 稳定 | 需额外接入 |
| | 归档（workflow archive，v4 起可落 MySQL/PostgreSQL） | 稳定 | 执行历史留痕 |
| **治理/安全** | SSO（OIDC，**可直接复用 Argo CD 的 Dex**） | 稳定 | 边际成本低（见 §7.3） |
| | RBAC（K8s 原生）+ ServiceAccount / Token 认证 | 稳定 | 第二套权限模型 |
| | Pod Security Context 模板 | 稳定 | 合规 |
| | "Workflow Restrictions" / 单租户部署模式 | 稳定 | 隔离 |

---

## 4. 它能解决什么问题、解决不了什么

### 4.1 官方认定的典型场景（**官方保证**）

| 场景 | 官方 use-case 页 | 是否我们的场景 |
|---|---|---|
| 机器学习流水线 | ML pipelines | ❌ |
| 数据 / 批处理 | Data & batch processing | ❌ |
| 流式处理 | Stream processing | ❌ |
| **CI/CD** | CI/CD —— **"Learn about webhooks for triggering pipelines. Head to the Argo CD docs."** | ❌ 官方把 CD 让给 Argo CD |
| **基础设施自动化** | Infrastructure Automation —— **"Head to the Argo Events docs."** | ⚠️ 官方指向 Argo Events，而非 Workflows |
| 其他 | Other | ❌ |

> **这两条是本次评估最硬的官方证据**：上游并没有把 Argo Workflows 定位成 CD 流水线或基础设施编排器；
> 在这两件事上，它分别把读者导向 **Argo CD** 与 **Argo Events**。

### 4.2 它真正擅长的问题

1. **运行时才确定的执行图**：扇出目标数在运行时才知道（例如"对所有 `health != Healthy` 的 12 个集群逐个回滚"）。
2. **跨步骤的数据流水线**：A 的产物喂给 B，中间可落 GCS。
3. **多阶段失败补偿**：某步失败 → 重试 → 仍失败 → 走 exit handler 做清理。
4. **人工闸门 + 定时超时**：suspend 等待审批，超时自动走另一分支。
5. **一次性运维剧本**：证书轮转、混沌实验、批量运维脚本、数据迁移。
6. **一次性 fan-out 交付**：父 Workflow 用 `resource` 模板创建 N 个子 Workflow（workflow-of-workflows）。

### 4.3 它不擅长 / 不该干的事（**本文判断**）

| 场景 | 为什么不行 |
|---|---|
| 持续期望状态收敛 | 语义相反。Workflows 不"盯着"资源，run 完就结束 |
| 作为 CD 主链路 | 每步一个 Pod，延迟/成本线性叠加；且发布的事实源会从 Git 漂移到 Workflow 定义 |
| 常态化的多集群发布 | 跨集群非一等公民；Argo CD + ApplicationSet 才是原生方案 |
| 审批流的唯一实现 | Argo CD 侧 Sync Windows + RBAC + Gatekeeper 已能做大部分 |
| 依赖 Argo CD 的健康/差异模型 | 两者对"状态"的定义完全不同，叠加容易互相打架（见 §5 L7） |

---

## 5. 局限性

> **官方保证**的用官方措辞；**本文判断**的是基于机制的推论。

### 5.1 架构与扩展性

| # | 局限 | 性质 |
|---|---|---|
| **L1** | **Controller 不能水平扩展**。官方原文："You cannot horizontally scale the controller."，只能 1 活 + N 热备（leader election）。大规模并发只能靠加 goroutine（`--workflow-workers` / `--pod-cleanup-workers` / `--cron-workflow-workers`）和加 CPU。 | **官方保证** |
| **L2** | **Controller 一次只处理一个 Workflow 的 reconcile**（架构文档："the controller only ever processes a single Workflow at a time"），并发靠 worker 队列；大规模时客户端限流（`--qps`/`--burst`）会打出 throttling 日志。 | **官方保证** |
| **L3** | **v4 引入数据库依赖**：归档（archive）与同步锁（sync）支持 MySQL / PostgreSQL，迁移由 controller 启动时自动执行。这是一条**新增的有状态依赖**（对比：Argo CD 内部 Redis 官方明确设计为不持久化）。 | **官方保证** |
| **L4** | **CRD 体积**：v4 起官方 CRD 带完整校验信息，**必须 server-side apply** 安装，否则撞 K8s 大小上限。对已有 GitOps 流程（`kubectl apply`）是一个额外约束。 | **官方保证** |

### 5.2 成本与运维

| # | 局限 | 性质 |
|---|---|---|
| **L5** | **新增常驻组件**：`argo-server`（官方建议 2~3 副本，且"内存需求与负载无关、可能相当大"）+ `workflow-controller` +（v4）数据库。与 **C2 单控制面**冲突。 | 官方建议 + 本文判断 |
| **L6** | **每个 step 一个 Pod**：调度、启动、镜像拉取的延迟与算力成本线性叠加；Argo CD 同步是"一次 kubectl apply"，没有这一层。 | **官方保证** |
| **L7** | **与 Argo CD 的双控制环风险**：如果让 Argo CD 持续 reconcile `Workflow` 对象，Argo CD 的三方 diff 会面对 Workflow 不断变化的 `status`（节点状态、pod 名、时间戳），极易产生永不收敛的 OutOfSync / 反复覆盖。这与 Knative 对象在 Argo CD 下的经典 diff 问题是同一类。**正解是：让 Workflow 只作为 hook 被"创建一次"，而不是被"持续 reconcile"。** | **本文判断**（机制推论，落地前需验证） |
| **L8** | **第二套身份与权限**：Workflows 有自己的 SA/token 认证、自己的 RBAC 语义、自己的 UI 登录。可复用 Argo CD 的 Dex（边际成本低），但 RBAC 与审计仍是两套。 | **官方保证** + 本文判断 |
| **L9** | **多集群非一等公民**：跨集群要靠 kubeconfig secret，权限模型与 Argo CD 的 cluster secret 不同构。 | 官方保证（隐含在 kubeconfig 机制中） |

### 5.3 与我们技术栈的适配风险

| # | 风险 | 说明 | 验证方式 |
|---|---|---|---|
| **L10** | **Workflow Pod 与 ambient mesh 的关系未定** | 我们的业务 Pod 都在 ambient（ztunnel L4 + waypoint L7）下。Workflow 的 step Pod 是"跑完就走的执行器"，理论上不需要进 mesh（不接业务流量）；但若 ztunnel/waypoint 的 CNI 或 policy 强制注入所有 Pod，Workflow Pod 可能被无谓地纳入甚至被 NetworkPolicy 拦死。 | **部署前验证项**：在目标集群按 ambient 模式起一个最小 Workflow 验证 |
| **L11** | **Workflow Pod 的 GitOps 归属** | 若 Workflow 定义放在 Git 由 Argo CD 管理，会触发 L7 的双控制环。 | **部署前验证项** |

### 5.4 治理侧的局限（对我们最关键）

| # | 局限 |
|---|---|
| **L12** | **Workflows 本身不提供"守住状态"的能力**。它不检测漂移、不自动回滚、不冻结变更。**所有 C3 治理诉求（审计/冻结/准入）仍然必须落在 Argo CD + Gatekeeper + Sync Windows 上**。引入 Workflows 并不能把治理责任转移过去。 |
| **L13** | **审批不是一等公民**。`suspend`/`resume` 能做人工闸门，但审批流、审批人、审批留痕要自己接（Argo CD 侧反而有 Sync Window 的 `allow/deny` + `disableManualSync` 这类原生手段）。 |

---

## 6. 面向我们的问题做能力映射

### 6.1 "受治理的基础设施发布执行器"拆成 12 项能力

| # | 能力 | 说明 |
|---|---|---|
| F1 | 声明式期望状态 | Git 是唯一事实源，漂移自动收敛 |
| F2 | 多集群 / 多项目扇出 | 一个定义 → N 个 GKE 集群 |
| F3 | 分批 / 按序推进 | 先 dev 后 prod；集群 A 健康后再推 B |
| F4 | 阶段编排 | 迁移 → 部署 → 冒烟 → 切流，多个有序阶段 |
| F5 | 阶段失败即停 | 失败阻断后续阶段并告警 |
| F6 | 准入治理 | 不合规资源被 API Server 拒绝 |
| F7 | 变更冻结 / 时间窗 | 非工作日禁止同步 |
| F8 | 删除确认 | 关键资源删除需人工确认 |
| F9 | 人工审批闸门 | 变更前需人工放行 |
| F10 | 审计留痕 | 谁、何时、改了什么 |
| F11 | 渐进式流量 | 金丝雀 / 蓝绿，比例可调、可回滚 |
| F12 | 弹性伸缩 | 按流量自动扩缩 |

### 6.2 映射表：Argo CD 现状 vs Argo Workflows 的增量

| 能力 | Argo CD 侧现有手段（**推荐实现**） | Workflows 增量 | 净增量？ |
|---|---|---|---|
| F1 声明式收敛 | 核心能力，`selfHeal` 自动纠偏 | ❌ 语义相反 | 无 |
| F2 多集群扇出 | ApplicationSet `clusters` generator + cluster secret | ⚠️ 需自备 kubeconfig | 无 |
| F3 分批按序 | **ApplicationSet Progressive Syncs**（v3.3.0+，Beta）：按 health 推进，跨集群分波次 | ✅ 可自定义 DAG 顺序 | 弱（Argo CD 的够用） |
| F4 阶段编排 | **Sync Phases & Waves**（`PreSync`/`Sync`/`PostSync`/`SyncFail`/`PreDelete`/`PostDelete` + wave 序号） | ✅ 更强（DAG + 条件 + 循环） | 弱 |
| F5 失败即停 | Phase 语义：PreSync 失败 → 整体 sync 失败，后续不执行 | ✅ 同样 | 无 |
| F6 准入治理 | **Gatekeeper / GKE Policy Controller**（Admission Webhook，见 [`06-opa-gatekeeper-impact.md`](./06-opa-gatekeeper-impact.md)） | ❌ 不提供 | 无 |
| F7 变更冻结 | **Sync Windows**（allow/deny + `disableManualSync` / `disableSyncOverrun`） | ❌ 不提供 | 无 |
| F8 删除确认 | **Sync Option `Prune=confirm`**（需 UI/CLI 或 `deletion-approved` 注解确认） | ⚠️ 需自建 | 无 |
| F9 人工审批 | Sync Windows + 手动 sync + 角色分离（Argo CD 无原生"一键批准并同步"按钮，需自定义或靠流程） | ✅ `suspend`/`resume` + `argo resume` | **有**（但两边都不够"产品化"，可用 RBAC 分离 + 流程代替） |
| F10 审计留痕 | Argo CD 事件流 + **Notifications**（trigger/template）+ 操作日志 | ⚠️ 另一套历史 | 无（甚至增加归因成本） |
| F11 渐进式流量 | **Knative 自带**：Revision 渐进发布 + `serving.knative.dev/rollout-duration` + `spec.traffic` 百分比/tag 切分 + 回滚 | ❌ 不提供（那是流量层的事） | 无 |
| F12 弹性伸缩 | **Knative Serving**（KPA，按并发/请求速率缩容，scale-to-zero） | ❌ 不提供 | 无 |
| — | **运行时动态扇出**（按运行时数据决定推哪些集群、推几个） | ✅ **DAG + `withItems` + `http` 模板查 Argo CD API** | **有（唯一真正的净增量）** |

### 6.3 结论

> **12 项需求里，Argo Workflows 的净增量只有 1 项（F12 之外的"运行时动态扇出"），且我们当前没有这个需求。**
> 引入它 = 为 1 项弱需求，付出 L1–L13 的全部代价。

**Workflows 真正有增量价值的三个场景（都不在 CD 主链路）**：

1. **运行时条件驱动的一致性修复**：巡检发现某集群漂移 → 动态生成回滚 DAG。
2. **跨步骤补偿 + 人工闸门的运维剧本**：证书轮转、数据库迁移、混沌实验。
3. **一次性 fan-out 运维**（workflow-of-workflows）：父工作流按运行时列表创建子工作流。

---

## 7. 结论与方案

### 7.1 A 方案（**推荐**）：不引入 Argo Workflows

**决策**：本期与可预见的未来，**Argo CD 是我们唯一的发布执行器**，不部署 Argo Workflows。

**理由（奥卡姆剃刀）**：我们需要的每一项能力，要么 Argo CD 原生具备，要么已被 Gatekeeper / Knative / Notifications 覆盖。
引入第二个控制面只为一个弱需求，不划算。

### 7.2 B 方案（**推荐落地形态**）：Argo CD 原生组合

> 这是"如果要用某种机制实现我的核心目的"的答案：**不引入 Workflows，用 Argo CD 自身 + 既有组件拼出来**。

| 需求 | 落地手段 | 文档位置 |
|---|---|---|
| 多集群扇出 | ApplicationSet `clusters` generator | [`05-appset.md`](./05-appset.md) |
| **分批按序发布（跨集群）** | **ApplicationSet Progressive Syncs**（`--enable-progressive-syncs`），按被管 Application 的 `Healthy` 推进 | 本文 §7.5 补充说明 |
| 阶段编排 / 失败即停 | Sync Phases & Waves + Hooks | 本文 §7.4 |
| 准入治理 | Gatekeeper Admission Webhook + `resource.customizations.health` | [`06-opa-gatekeeper-impact.md`](./06-opa-gatekeeper-impact.md) |
| 变更冻结 / 时间窗 | Sync Windows（按 Application / Namespace / Cluster 选择器，支持 allow/deny、manual sync 开关） | 本文 §7.4 |
| 删除确认 | `argocd.argoproj.io/sync-options: Prune=confirm` | 本文 §7.4 |
| 人工审批 | 项目级 `disableManualSync` + 角色分离 + 变更单流程（**后续可增强**） | 本文 §7.4 |
| 审计 | Argo CD Notifications（triggers/templates）+ 事件流 | [`09-troubleshooting.md`](./09-troubleshooting.md) 关联 |
| **渐进式流量（金丝雀/蓝绿）** | **Knative 自身**：`spec.traffic` 切分 + `serving.knative.dev/rollout-duration` 渐进发布 + Revision 回滚 | 本文 §7.5 |
| 弹性伸缩 | Knative Serving（KPA，scale-to-zero） | 业务侧，本期不在 Argo CD 范围 |

> ⚠️ **不要把 Argo Rollouts 和 Knative 流量切分同时用在同一个 Knative Service 上。**
> Argo Rollouts 的作用域是 `Rollout` CRD（它自己管理 ReplicaSet），而 Knative Service 的 Revision/流量由 Knative 自己管。
> 两者对"新版本接多少流量"各有一套控制权，叠加会互相打架。
> 我们的 API 是 Knative Service，**渐进流量只用 Knative**；Argo Rollouts 仅在未来出现"非 Knative 的裸 Deployment + 复杂金丝雀分析"需求时再引入。

### 7.3 C 方案（**条件性备选**）：受限引入 Argo Workflows

若将来命中 §8 的触发条件，引入方式**必须**受限：

| 约束 | 内容 |
|---|---|
| 定位 | **只做运维/校验编排**，不做 CD 主链路 |
| 触发方式 | 作为 Argo CD 的 **PreSync / PostSync Hook**（官方文档明确支持：hook 资源 "tend to be Pod, Job, or Argo Workflows"），**一次性创建、不被持续 reconcile** |
| 治理继承 | Workflow 的 SA 复用目标集群的最小权限 SA；触发它的 Application 必须属于受限 AppProject |
| 身份 | 直接复用 Argo CD 的 Dex（`staticClients` 增加 `argo-workflows-sso`），`argo-server --auth-mode=sso`，SSO 边际成本≈0 |
| 命名空间 | `managed namespace` 模式，Workflow 与 Pod 隔离在专用 ns |
| 部署方式 | 最小安装：只装 `workflow-controller` + `argo-server`（2 副本），**先不接数据库**（归档先用对象存储/K8s 侧兜底） |
| 版本 | v4.x（CRD 需 **server-side apply**；或用 `argo-workflows-crdinstaller`） |
| 触发闸门 | 必须先在沙箱集群验证 L10（ambient 下 Workflow Pod 的注入与网络策略行为） |

### 7.4 其它备选（后续阶段再评估，本期不选）

| 备选 | 适用阶段 | 说明 |
|---|---|---|
| **Argo Events** | 未来做事件驱动（Git push / GCS 事件 / 定时） | 官方把"基础设施自动化"指向它；比 Workflows 更贴合"事件 → 动作" |
| **Cloud Build / GitHub Actions** | **CI 阶段** | 镜像构建、测试、扫描；产出镜像 tag 后由 Argo CD 侧触发同步（webhook / image updater）。**不要用 Argo Workflows 做 CI** |
| **Terraform Cloud / Atlantis / Config Sync** | **云资源阶段**（KCC 之后） | Argo CD 只管 K8s API 能创建的资源；VPC/Subnet/Cloud SQL 属于 IaC 地盘（见 [`00-architecture-no-crossplane.md`](./00-architecture-no-crossplane.md) §3） |
| **Argo Rollouts** | 出现非 Knative 裸工作负载 | 与 Knative 二选一，不要并存 |

### 7.5 补充：跨集群分批发布怎么落（B 方案的关键机制）

**ApplicationSet Progressive Syncs**（官方标注 **Beta, v3.3.0+**）：

- 作用：控制 ApplicationSet 创建/更新其子 Application 的**顺序**；
- 机制：等待被管 Application 变为 `Healthy` 后再进入下一阶段；
- 官方明确：它"**只与被管 Application 的 health 交互，不打算与其他 Rollout 控制器（如原生 ReplicaSet 控制器或 Argo Rollouts）直接集成**"；
- 官方支持 `Argo CD Resource Hooks`（推荐用于"DaemonSet 变更后跑冒烟测试"这类 Argo Rollouts 无法覆盖的场景）。

**开启方式**（三选一）：

```bash
# 方式一：给 appset-controller 加参数
--enable-progressive-syncs

# 方式二：环境变量
ARGOCD_APPLICATIONSET_CONTROLLER_ENABLE_PROGRESSIVE_SYNCS=true

# 方式三：ConfigMap
argocd-cmd-params-cm:
  applicationsetcontroller.enable.progressive.syncs: "true"
```

**渐进流量（Knative）**：

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: my-api
  annotations:
    serving.knative.dev/rollout-duration: "380s"   # 渐进切流：先 1%，再等分递增
spec:
  traffic:
    - revisionName: my-api-v1
      percent: 90
      tag: stable
    - latestRevision: true
      percent: 10
```

> 官方说明：`rollout-duration` 是**基于时间**的，与自动伸缩子系统不联动；
> 影响的是"traffic 指向 Configuration 目标"的场景（新建 Revision ready 后会 100% 切过去，加了 rollout-duration 才会渐进）。

---

## 8. 复评触发条件（Checklist）

出现下列**任意一条**，重新评估 Argo Workflows（或其他编排引擎）：

| # | 触发条件 | 候选方案 |
|---|---|---|
| T1 | 需要"**根据运行时数据**决定推哪些集群 / 推几个"（而不是预先声明的顺序） | Argo Workflows（DAG + `http` 模板查 Argo CD API） |
| T2 | 一次发布需要 **>5 个有依赖关系、且中间要传数据**的阶段 | 先试 Sync Waves；超过能力边界再考虑 Workflows |
| T3 | 需要**跨步骤失败补偿**（某步失败 → 自动清理 → 走另一条路径） | Argo Workflows `exit handler` |
| T4 | 需要把**运维剧本**（证书轮转 / 数据迁移 / 混沌）产品化成可自助触发的一次性任务 | Argo Workflows（独立 ns + Dex SSO + 受限 SA） |
| T5 | 需要**事件驱动**（Git push / GCS 事件 → 动作） | Argo Events |
| T6 | Argo CD 侧出现**真正的审批工作流**需求（多级审批、SLA、审批留痕），且 Sync Window + 角色分离不够 | Argo Workflows（`suspend`）或流程系统 |
| T7 | 出现**非 Knative 的裸 Deployment**，且需要复杂金丝雀分析（自动回滚 / 指标门禁） | Argo Rollouts（不是 Workflows） |

---

## 9. 风险与部署前验证项

> 本期不部署，因此以下是**将来若走 C 方案**的验证清单。

| # | 验证项 | 方法 | 判定 |
|---|---|---|---|
| V1 | Argo Workflows CRD 能否在现有 Argo CD 流程（`kubectl apply`）下安装 | v4 CRD 需 server-side apply；或用 `argo-workflows-crdinstaller` | 能 |
| V2 | **ambient 模式下 Workflow Pod 的行为**（ztunnel/waypoint 是否强制注入、NetworkPolicy 是否误拦） | 在目标集群跑一个 2 步最小 Workflow | 无异常注入、可正常出网 |
| V3 | Argo CD 对 `Workflow` 对象的 diff 行为（是否会永不收敛） | 让 Argo CD 管理一个 hook Workflow，观察 OutOfSync | 确认必须用 hook 而非持续 reconcile |
| V4 | Dex 复用（`staticClients`）是否与现有 `dex.config` 兼容 | 参照官方 `argo-server-sso-argocd` 示例合并配置 | 不破坏现有 SSO |
| V5 | Argo Server 副本数与内存（官方：内存需求与负载无关且可能相当大） | 压测 2 副本下的常驻内存 | 在预算内 |
| V6 | v4 归档数据库是否必须（能否先用对象存储兜底） | 按 `workflow-archive` / `synchronization-config` 文档验证最小配置 | 可不引 DB |
| V7 | Knative Service 在 Argo CD 下的 diff 稳定性（`spec.template` 默认值、Route/Revision 子资源、状态字段） | 观察 `kubectl apply` Knative Service 后 Argo CD 是否持续 OutOfSync | 需要 `ignoreDifferences` 定制 |
| V8 | ApplicationSet Progressive Syncs 在多集群 + Knative 下的行为（health 判定是否可靠） | 观察 Knative Service 的 `Progressing` → `Healthy` 转换 | 可用 |

---

## 10. 参考资料（上游一手）

**Argo Workflows（v4.1）**

| 主题 | 链接 |
|---|---|
| 首页 / 定位 | https://argo-workflows.readthedocs.io/en/release-4.1/ |
| 核心概念（Workflow / 9 种模板） | https://argo-workflows.readthedocs.io/en/release-4.1/workflow-concepts/ |
| 架构（组件拓扑、Pod 布局、controller 行为） | https://argo-workflows.readthedocs.io/en/release-4.1/architecture/ |
| 安装（安装方式、v4 CRD server-side apply） | https://argo-workflows.readthedocs.io/en/release-4.1/installation/ |
| 高可用（leader election / Recreate / argo-server 副本） | https://argo-workflows.readthedocs.io/en/release-4.1/high-availability/ |
| 扩展性（**不能水平扩展**、限流调参） | https://argo-workflows.readthedocs.io/en/release-4.1/scaling/ |
| CI/CD 场景（**→ Argo CD**） | https://argo-workflows.readthedocs.io/en/release-4.1/use-cases/ci-cd/ |
| 基础设施自动化场景（**→ Argo Events**） | https://argo-workflows.readthedocs.io/en/release-4.1/use-cases/infrastructure-automation/ |
| HTTP 模板 | https://argo-workflows.readthedocs.io/en/release-4.1/http-template/ |
| Resource 模板 | https://argo-workflows.readthedocs.io/en/release-4.1/resource-template/ |
| Workflow of Workflows | https://argo-workflows.readthedocs.io/en/release-4.1/workflow-of-workflows/ |
| **复用 Argo CD 的 Dex 做 SSO** | https://argo-workflows.readthedocs.io/en/release-4.1/argo-server-sso-argocd/ |
| 数据库迁移（v4 archive / sync DB） | https://argo-workflows.readthedocs.io/en/release-4.1/database-migrations/ |
| 源码 / 版本 | https://github.com/argoproj/argo-workflows（`v4.1.6`, 2026-10-22, Apache-2.0） |

**Argo CD（stable）**

| 主题 | 链接 |
|---|---|
| Sync Phases and Waves（hooks 机制；hook 可为 Argo Workflow） | https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/ |
| Sync Options（`Prune=confirm` 等） | https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/ |
| Sync Windows（变更冻结 / 时间窗） | https://argo-cd.readthedocs.io/en/stable/user-guide/sync_windows/ |
| Notifications（triggers / templates / 审计通告） | https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/ |
| ApplicationSet Progressive Syncs（Beta, v3.3.0+） | https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Progressive-Syncs/ |
| 自定义健康检查（Knative 等 CRD） | https://argo-cd.readthedocs.io/en/stable/operator-manual/health/ |

**Knative Serving**

| 主题 | 链接 |
|---|---|
| 渐进式流量切分（`rollout-duration`） | https://knative.dev/docs/serving/rolling-out-latest-revision/ |
| 流量管理（Revision 百分比 / tag） | https://knative.dev/docs/serving/traffic-management/ |
| Revision 与渐进发布/回滚 | https://knative.dev/docs/serving/revisions/ |

**Argo Rollouts**（备选，非本期）

| 主题 | 链接 |
|---|---|
| 渐进式交付控制器（蓝绿/金丝雀/分析/自动回滚） | https://argoproj.github.io/argo-rollouts/ |

---

## 11. 术语速查

| 术语 | 含义 |
|---|---|
| `Workflow` | 一次执行实例，同时承载定义与状态（live object） |
| `WorkflowTemplate` / `ClusterWorkflowTemplate` | 可复用的工作流定义（namespace 级 / 集群级） |
| `entrypoint` | 入口模板名（"main 函数"） |
| `steps` / `dag` | 顺序+并行 / 显式依赖图 |
| `artifact` | 步骤间传递的数据（GCS / S3 / Artifactory / OSS / HTTP / Git / plugin） |
| `suspend` | 挂起，等待人工或定时恢复 |
| `exit handler` | 无论成败都执行的收尾模板 |
| `templateRef` | 引用 WorkflowTemplate |
| `workflow-of-workflows` | 父 Workflow 通过 `resource` 模板创建子 Workflow |
| `managed namespace` | controller 只执行指定 ns 中的 Workflow |
| `sync wave` | Argo CD 中资源的应用顺序编号 |
| `sync phase` | Argo CD 的 hook 阶段：PreSync / Sync / PostSync / SyncFail / PreDelete / PostDelete |
| `Progressive Syncs` | ApplicationSet 按 health 顺序分批创建/更新子 Application |
| `Prune=confirm` | Argo CD 同步选项：删除资源前需人工确认 |
| `Sync Window` | Argo CD 的 allow/deny 时间窗 |
| `rollout-duration` | Knative 注解：Revision 渐进切流的时长 |
