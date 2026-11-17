# Argo Events 是什么 · 事件驱动自动化的最小认知

> **本文回答**
> 1. **Argo Events 是个什么东西？**（一句话 + 四个核心对象）
> 2. **它和 Argo Workflows / Argo CD / CronJob 什么关系？**（谁干什么）
> 3. **落到我们的场景怎么接？**（GitHub App → Argo Events 的三种接线方式）
> 4. **什么时候该用它、不该用它？**（决策表）

> **它是被引用的，不是被推荐的**
> 本仓库 [`10-argo-workflows-evaluation.md`](./10-argo-workflows-evaluation.md) 的结论是
> **"不引入 Argo Workflows"**；[`git-apps/11-github-app-concepts.md`](./git-apps/11-github-app-concepts.md) §23.2
> 只是**顺带提了一句**"如果需求只是 Git push → 触发一个动作，Argo Events 比 Workflows 更贴切"。
> **本文是概念说明，不是引入建议** —— 当前的 CR Check 门禁**不需要**它（理由见 §8）。

---

## 目录

| 章节 | 内容 |
|---|---|
| [§0](#0-一句话) | 一句话 + 一张全景图 |
| [§1](#1-它解决什么问题) | 从 CronJob 轮询到事件驱动 |
| [§2](#2-四个核心对象) | EventBus / EventSource / Sensor / Trigger |
| [§3](#3-一条事件的完整旅程) | 数据怎么流 |
| [§4](#4-支持的事件源与触发器) | 清单（**含内置 GitHub 事件源**） |
| [§5](#5-与 Argo 家族其它组件的关系) | 三方对照 + 官方指向 |
| [§6](#6-最小可用示例) | 一套能跑的 YAML |
| [§7](#7-触发一个 Argo Workflow) | Trigger kind: Workflow |
| [§8](#8-落到我们的场景怎么接) | GitHub App → Argo Events 三种接法 + 结论 |
| [§9](#9-该不该用：决策表) | 用 / 不用 |
| [§10](#10-运维要点与坑) | 安装、HA、投递语义、已知坑 |
| [§11](#11-标注与待验证项) | 标注 |
| [§12](#12-关联文档) | 关联文档 |

---

## 0. 一句话

```
Argo Events = Kubernetes 原生的"事件总线 + 事件路由"框架。
              把"某件事发生了"（事件源）变成"触发某个动作"（触发器），
              中间可以用 Sensor 做过滤 / 依赖 / 转换。
```

**它不是**：工作流引擎（那是 Argo Workflows）、不是持续同步引擎（那是 Argo CD）、
不是定时任务（那是 CronJob，虽然 Argo Events 也能做定时源）。

**全景图**：

```
   ┌──────────────┐   写入    ┌────────────┐   订阅    ┌──────────┐
   │ EventSource  │──────────▶│ EventBus   │◀─────────│  Sensor  │
   │ 事件生产者    │           │ 事件总线    │          │ 过滤/依赖 │
   └──────────────┘           └────────────┘          └────┬─────┘
         ▲                        ▲                        │ 写入
         │  GitHub / GCS /         │  NATS / MQTT /          ▼
         │  Kafka / Cron /         │  Redis / Kafka    ┌────────────┐
         │  Webhook ...            │                   │  Trigger   │
         └──────────────┘           └──────────────────│  动作触发器 │
                                                        └─────┬──────┘
                                                              │ 执行
                    ┌─────────────────────────────────────────┼──────────────┐
                    ▼                    ▼                    ▼              ▼
              HTTP 调服务        触发 Argo Workflow     发 Kafka      写 S3 ...
```

> ★ **记住这条链路就够了**：
> `EventSource → EventBus → Sensor → EventBus → Trigger`
> **中间那个 EventBus 出现两次不是笔误** —— 这是 Argo Events 的固定拓扑：
> EventSource 把事件写进总线，Sensor 从总线读出来做加工，再写回总线，Trigger 从总线读出来执行动作。

---

## 1. 它解决什么问题

### 1.1 没有事件总线的时候：靠轮询

```
想做"仓库有变更 → 跑个校验"，最常见的土办法：

CronJob（每 5 分钟）
   → 调 GitHub API 列出 PR
   → 对比上次状态
   → 有变化就干活

问题：
  · 无事也消耗 API 配额（轮询成本随规模线性增长）
  · 延迟 = 轮询间隔
  · N 个需求 → N 个 CronJob → N 份轮询逻辑、各自的重试/幂等/告警
```

### 1.2 有了事件总线之后

```
GitHub（事件源）──▶ EventBus ──▶ Sensor（只处理 PR 事件、过滤分支）
                                    │
                                    ├──▶ Trigger A：调 CR 平台校验
                                    ├──▶ Trigger B：发通知
                                    └──▶ Trigger C：触发 Argo Workflow
```

**收益**：

| | CronJob 轮询 | Argo Events |
|---|---|---|
| 配额消耗 | 持续消耗 | **只在有事时消耗** |
| 延迟 | 一个轮询周期 | 秒级 |
| 多个消费者 | 复制 N 份轮询 | **一个事件源，多个 Trigger** |
| 声明式 | 逻辑写在脚本里 | **CRD 声明**（可以用 GitOps 管） |
| 幂等/重试 | 自己写 | 部分由框架承担（**仍需注意，见 §10**） |

> 📌 **这个"从拉变推"的思路，和我们 GitHub App 那条线索是同一件事**
> —— 详见 [`git-apps/12-webhook-push-vs-pull.md`](./git-apps/12-webhook-push-vs-pull.md)。

---

## 2. 四个核心对象

| 对象 | 角色 | 关键字段 | 回答什么问题 |
|---|---|---|---|
| **EventBus** | 事件总线（传输层） | `spec.nats` / `spec.mqtt` / `spec.redis` / `spec.kafka` / `spec.gcppubsub` | 事件在哪儿流转？ |
| **EventSource** | 事件生产者（对接外部系统） | `spec.github` / `spec.gcs` / `spec.webhook` / `spec.schedule` … | **谁**产生了这个事件？ |
| **EventSensor** | 事件的处理者（过滤 / 依赖 / 转换） | `spec.dependencies` / `spec.dependencies.*.filters` / `spec.template` | **哪些**事件值得响应？ |
| **Trigger** | 动作执行者 | `spec.template.http` / `spec.template.workflow` / `spec.template.kafka` … | 收到后**做什么**？ |

### 2.1 EventBus

```
EventBus 只是"消息通道"，不存业务语义。
可选实现：NATS（官方最常用，支持 JetStream 持久化）/ MQTT / Redis / Kafka / Google Cloud Pub/Sub。
★ 官方文档默认示例用 NATS。
```

### 2.2 EventSource

```
EventSource = "我盯着某个外部系统，有动静就往总线里写一条"。

典型：github / gitlab / gcs / s3 / kafka / amqp / mqtt / pubsub / cron(定时) / webhook(通用 HTTP 接收)
```

### 2.3 EventSensor

```
EventSensor = "我订阅总线上的事件，判断一下要不要响应，加工后写回总线"。

三件事：
  ① 过滤（filters）：按 event payload 的字段筛掉不关心的
     例：只处理 base 分支 == main 的 PR
  ② 依赖（dependencies）：多个条件同时满足才触发
     例：PR 事件 且 维护窗口开启 且 变更单状态变成 Approved
  ③ 转换（transform）：改写事件内容后再往下传
```

### 2.4 Trigger

```
Trigger = "我从总线取事件，执行动作"。

典型：http（调一个 Webhook 接口）/ workflow（起一个 Argo Workflow）/
      kafka / mqtt / nats / log / gcppubsub / sqs / opentelemetry
```

> ★ **Sensor 和 Trigger 的区别**：
> **Sensor 决定"要不要"（判断），Trigger 决定"做什么"（执行）。**
> 一个 Sensor 可以挂多个 Trigger → 这就是"一个事件源、多个消费者"的实现方式。

---

## 3. 一条事件的完整旅程

```
① GitHub 产生事件（PR opened）
        ▼
② EventSource（github 类型）收到 → 转成 Argo Events 的 CloudEvent 格式
        → 写入 EventBus（nats: my-bus）
        ▼
③ Sensor 订阅 my-bus
   3.1 取到事件
   3.2 跑 filters（例：action == "opened" 且 base.ref == "main"）→ 不通过就丢弃
   3.3 跑 dependencies（例：另一个 Sensor 说"窗口已开"）→ 不满足就挂起等待
   3.4 transform（可选）→ 加工 payload
   3.5 写回 EventBus（另一个 subject，如 `cr-check`）
        ▼
④ Trigger 订阅 cr-check
   4.1 收到事件
   4.2 按 template 执行动作
       例：http → POST https://cr-check.example.com/evaluate
   4.3 记录执行状态
        ▼
⑤ 你的服务收到请求 → 干活
```

> ★ **注意 3.3**：Sensor 的"依赖"机制是它最有价值的能力 ——
> **它让"多个条件同时满足"变成声明式的**，而不是散落在各处的 if。

---

## 4. 支持的事件源与触发器

### 4.1 EventSource 类型（部分）

| 类型 | 说明 | 对我们有没有用 |
|---|---|---|
| **`github`** | **内置 GitHub 事件源**（支持 webhook 模式，也支持用 token 轮询） | ★ **有** —— 见 §8 |
| `gitlab` | GitLab 事件源 | 无 |
| `gcs` / `s3` / `azureblob` | 对象存储事件 | 可能有（构建产物落地） |
| `kafka` / `amqp` / `mqtt` / `nats` / `redis` | 消息中间件 | 视接入系统而定 |
| `gcppubsub` / `awsSqs` | 云消息队列 | 可能有 |
| **`schedule`** | **定时产生事件**（等价于 CronJob，但走事件总线） | ★ **有** —— 正好解决"时间窗口过期"这类"没发生任何事"的场景 |
| **`webhook`** | **通用 HTTP 接收端点**（任何系统 POST 过来都行） | ★ **有** —— 我们的 GitHub App 后端可以 POST 到这里 |

### 4.2 Trigger 类型（部分）

| 类型 | 说明 |
|---|---|
| **`http`** | 调一个 HTTP 接口（最通用）—— 可以直接打到 CR Check 服务 |
| **`workflow`** | **触发一个 Argo Workflow**（见 §7） |
| `kafka` / `mqtt` / `nats` / `redis` | 发消息 |
| `log` | 打日志（调试用） |
| `gcppubsub` / `awsSqs` | 发云消息 |
| `opentelemetry` | 发 OTel 事件 |

---

## 5. 与 Argo 家族其它组件的关系

### 5.1 三方对照

| | **Argo Events** | **Argo Workflows** | **Argo CD** |
|---|---|---|---|
| **本质** | 事件总线 + 路由 | 工作流/DAG 引擎 | 持续同步引擎（Git → 集群） |
| **核心对象** | EventBus / EventSource / Sensor / Trigger | Workflow / WorkflowTemplate / CronWorkflow | Application / AppSet / AppProject |
| **执行模型** | 事件触发一次动作 | 一次 DAG 编排（可 suspend 等人） | 持续 reconcile 到期望状态 |
| **状态** | 有状态但轻（Sensor 状态） | **有状态**（Workflow 实例、归档） | **有状态**（Redis + K8s） |
| **典型问题** | "发生了 X → 做 Y" | "做一件有 5 个依赖步骤的事" | "让集群等于 Git 里的声明" |
| **是否引入（doc 10 结论）** | ❌ 本期不引入 | ❌ **不引入** | ✅ 已在用 |

### 5.2 官方文档的指向（**官方保证**）

Argo Workflows 官方文档的用例页把读者**分别导向另外两个项目**：

```
CI/CD 用例页          → "Head to the Argo CD docs."
基础设施自动化用例页   → "Head to the Argo Events docs."
```

> ★ **也就是说：官方自己认为"事件驱动自动化"该用 Argo Events，
> 而不是硬塞进 Argo Workflows。**
> 这就是 doc 10 §7.4 把 Argo Events 列为"未来做事件驱动时的备选"的依据。

### 5.3 组合关系

```
        事件（GitHub push / 定时 / GCS）
                 │
                 ▼
          Argo Events
         （路由 + 过滤）
                 │
                 ├──▶ Trigger: http ──▶ 你的服务（校验 / 通知）
                 │
                 └──▶ Trigger: workflow ──▶ Argo Workflow（多步编排）
                                              │
                                              └──▶ 可以再调 Argo CD API 触发同步
```

> ★ **Events 与 Workflows 不是二选一，是上下游**：
> **Events 决定"什么时候开始"，Workflows 决定"怎么一步步做完"。**

---

## 6. 最小可用示例

> 一套能跑通的组合：**GitHub 事件源 → NATS 总线 → Sensor 过滤 → HTTP Trigger 调我们的服务**

```yaml
# ── ① EventBus ─────────────────────────────────────────
apiVersion: argoproj.io/v1alpha1
kind: EventBus
metadata:
  name: default
  namespace: argo-events
spec:
  nats:
    url: nats://argo-events-nats-svc:4222
    # ★ 生产建议开 JetStream 持久化，否则 EventBus 重启期间的事件会丢
    #   jetstream: { enabled: true }

---
# ── ② EventSource：盯 GitHub ──────────────────────────
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: github-src
  namespace: argo-events
spec:
  eventBusName: default
  github:
    owner: acme
    repositories:
      - platform
    # 事件类型白名单（只订阅需要的）
    events:
      - pull_request
      - push
    # webhook 模式需要 GitHub 侧把 Webhook 指向下面这个地址
    webhook:
      url: "http://argo-events-argo-events-webhook-gateway-svc:12000/github"
      secretRef:
        name: github-events-secret
        key: secretToken

---
# ── ③ Sensor：过滤 + 加工 ─────────────────────────────
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: cr-check-sensor
  namespace: argo-events
spec:
  eventBusName: default
  dependencies:
    - name: pr-on-prod-branch
      filters:
        # 例：只处理 base 分支命中受管集合的 PR
        - data:
            - '{"body.action": "opened"}'
            - '{"body.pull_request.base.ref": "release/prod"}'
      # 依赖另一个 Sensor 的状态（"窗口已开"）
      # - name: maintenance-window
      #   strict: true
  triggers:
    - name: to-cr-check
      template:
        http:
          method: POST
          url: "https://cr-check.example.com/evaluate"   # ← 我们的 Go 服务
          headers:
            - name: Content-Type
              value: application/json
          # ★ 失败重试策略（至少一次投递的兜底）
          retryStrategy:
            steps: 3
            duration: 5s
            factor: 2
            maxDuration: 1m
```

### 6.1 用 `schedule` 做定时事件源

```yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: cron-src
  namespace: argo-events
spec:
  eventBusName: default
  schedule:
    # cron 表达式（UTC）
    schedule: "*/5 * * * *"
    # 每次触发的 payload
    template:
      event:
        payload: '{"reason": "recheck-window"}'
```

> ★ **这个用法对我们特别有价值**：
> "Maintenance Window 关闭了但 PR 上还挂着旧的绿勾" —— 这是**没有事件发生**的情况，
> Webhook 天然管不到，而 `schedule` 事件源正好补上（见 §8.3）。

---

## 7. 触发一个 Argo Workflow

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Trigger
metadata:
  name: to-workflow
  namespace: argo-events
spec:
  dependencies:
    - name: cr-check-sensor
  template:
    workflow:
      spec:
        entrypoint: main
        templates:
          - name: main
            steps:
              - - name: run
                  template:
                    http:
                      url: "https://cr-check.example.com/evaluate"
```

> ⚠️ **注意**：一旦用了 `Trigger: workflow`，就等于**把 Argo Workflows 拉进来了** ——
> 而本仓库 doc 10 的结论是**不引入 Workflows**（见 §9.4）。

---

## 8. 落到我们的场景怎么接

### 8.1 我们的架构现状

```
GitHub ──POST──▶ CR Check 后端（Go, GKE）──▶ 查 CR 平台 ──▶ 写 check run
                     ▲
                     └── 这是我们自己写的 Go 服务
```

**这个架构里，Argo Events 目前是"多余的"。**

### 8.2 三种接线方式（如果要用）

| 方案 | 链路 | 评价 |
|---|---|---|
| **A. 不接**（推荐） | CR Check 就是一个普通 Go 服务，自己收 webhook、自己查平台、自己写 check | ✅ **最简单**。我们要的逻辑是"查外部系统 + 比对规则"，用 Argo Events 表达不出来 |
| **B. Argo Events 做总线** | GitHub ──▶ EventSource(github) ──▶ Sensor(过滤) ──▶ Trigger(http) ──▶ CR Check | ⚠️ 多 3 个 CRD + 一个 NATS；好处只是"过滤逻辑声明化" |
| **C. 混合** | CR Check 收 webhook 后，**把"窗口开/关"这类事件转发给 EventBus**，由 Sensor + Trigger 驱动 | ⚠️ 适合"事件很多、消费者更多"的场景 |

### 8.3 如果只借 Argo Events 的一个能力

**唯一真正有价值的用法：`schedule` 事件源 + Sensor + Trigger → 定时重扫。**

```
cron("*/5 * * * *")
   → Sensor（不筛选，全量）
   → Trigger(http → CR Check /internal/recheck)
   → CR Check 重扫受管分支上未合并的 PR，重算并覆盖 check
```

> ⚠️ **但这用一个 `time.Ticker` / Kubernetes CronJob 也能做，而且更简单。**
> Argo Events 在这里提供的额外价值主要是"声明式 + 可被 Argo CD 管"，而不是"必须用它"。

### 8.4 结论

```
★ 当前 CR Check 门禁**不需要** Argo Events：
  · 判定逻辑是"查外部 CR 平台 + 多条规则比对"，不是"事件路由"
  · 我们只有 1 个事件源（GitHub PR）+ 1 个消费者（CR Check）
  · 引入它 = 多一套 CRD + 多一个 NATS 有状态组件 + 多一套运维

★ 它真正适合的场景（我们暂时没有）：
  · 事件源多（GitHub + GCS + Kafka + 云事件…）
  · 消费者多（校验 / 通知 / 建 PR / 起流水线…）
  · 需要"多个条件同时满足才触发"的声明式编排（Sensor dependencies）
```

---

## 9. 该不该用：决策表

### 9.1 判据

| 问自己 | 是 → | 否 → |
|---|---|---|
| 事件源 ≥ 3 种，或消费者 ≥ 3 个？ | Argo Events 有价值 | 用普通服务更省事 |
| 需要"条件 A 且 条件 B 同时满足才动作"的声明式编排？ | Sensor dependencies 合适 | 用代码写更直白 |
| 已有 Argo 生态（CD / Workflows / Rollouts）并且想统一风格？ | 考虑 | 独立实现 |
| 只是"Git push → 跑个校验"？ | ⚠️ 一个 Go 服务 + 一个 webhook 就够 | 别引新框架 |
| 只是"每 5 分钟跑一次"？ | CronJob / 内置 ticker 就够 | 别引新框架 |
| 团队没有 Argo Events 运维经验？ | 先别 | 学习成本真实存在 |

### 9.2 四个候选方案的横向对照

| | 普通 Go 服务 | Argo Events | Argo Workflows | Argo CD |
|---|---|---|---|---|
| 引入成本 | 低（一个镜像） | 中（CRD + NATS + 控制器） | 高（控制器 + UI + 归档 DB） | 已在用 |
| 有状态组件 | 无 | NATS / Sensor 状态 | Workflow 实例 + 归档 | Redis |
| 表达能力 | **最强**（任意逻辑） | 路由 + 过滤 + 简单条件 | DAG + suspend + 补偿 | 期望状态同步 |
| 适合我们的 CR Check | ✅ **就是它** | ⚠️ 多余 | ❌ doc 10 结论 | 部署侧用它 |

### 9.3 与 doc 10 的 T5 触发条件对照

doc 10 的复评触发条件里有一条：

```
T5 | 需要**事件驱动**（Git push / GCS 事件 → 动作） | Argo Events
```

> ★ **注意 T5 的措辞**：它说的是"需要事件驱动"。
> 我们的 CR Check **确实是事件驱动**（GitHub PR 事件 → 判定）——
> 但 **T5 指的是"Argo 家族内部的自动化"**（Argo CD 侧需要被 Git push 触发一串动作），
> **不是"我们要写一个接收 GitHub 事件的服务"**。
>
> 我们要写的是**业务逻辑服务**（查 CR 平台、跑规则、写 check），
> **它用普通 Go 服务实现最直接**。用 Argo Events 只是把"接收事件"这一层框架化，
> 而判定逻辑仍要写在我们的服务里 → **纯增加复杂度，不减少工作量**。

### 9.4 最终结论

```
☐ 本期不引入 Argo Events（与 doc 10 "不引入 Workflows" 的结论一致）。
☐ 记入"未来备选"：当出现 ≥3 个事件源 / ≥3 个消费者 / 复杂条件编排时复评。
☐ 即便将来引入，CR Check 的**判定逻辑仍然在我们自己的服务里**——
   Argo Events 只做"事件路由"，替代不了业务逻辑。
```

---

## 10. 运维要点与坑

| # | 要点 | 说明 |
|---|---|---|
| 1 | **安装不是一个组件** | `argo-events` namespace 里至少有：controller、eventbus（默认带 NATS）、argo-events-webhook-gateway、sensors/triggers 的工作负载 |
| 2 | **EventBus 建议开 JetStream** | 不开则 EventBus 重启期间的事件**直接丢**（无持久化） |
| 3 | **投递语义：至少一次** | 消费者必须**幂等**（和 Webhook 一样的道理，见 [`git-apps/12-webhook-push-vs-pull.md`](./git-apps/12-webhook-push-vs-pull.md) §6.1） |
| 4 | **Sensor 状态存在 K8s ConfigMap 里** | 事件量大时可能触及 ConfigMap 1MB 上限 → 需评估 ⚠️ **需实测** |
| 5 | **已知的历史问题：事件重复投递** | 旧版本出现过同一事件触发多次 → 消费端幂等不能省 ⚠️ **需按当前版本验证** |
| 6 | **Webhook 事件源需要公网地址** | 和 GitHub App 后端一样：需要 Ingress + 域名 + TLS → **多一个公网暴露面** |
| 7 | **Trigger 的 HTTP 调用也会失败** | 必须配 `retryStrategy`，且**下游必须幂等** |
| 8 | **GitOps 管它** | EventBus/EventSource/Sensor/Trigger 都是 CRD → 可以被 Argo CD 管（**但注意它们自身也是"期望状态"**） |

---

## 11. 标注与待验证项

| 标注 | 内容 |
|---|---|
| **官方保证** | ① Argo Workflows 官方用例页把"CI/CD"指向 Argo CD、把"基础设施自动化"指向 Argo Events；② Argo Events 的核心 CRD 为 EventBus / EventSource / EventSensor / Trigger；③ EventBus 支持 NATS / MQTT / Redis / Kafka / GCP PubSub；④ 内置 `github` EventSource 与 `schedule` EventSource；⑤ Trigger 支持 `workflow` 类型（可起 Argo Workflow） |
| **本仓库结论** | 本期**不引入** Argo Events（doc 10 §7.4 列为"未来备选"）；CR Check 门禁用普通 Go 服务实现最直接；复评条件 = ≥3 事件源 / ≥3 消费者 / 复杂条件编排 |
| **需实测 / 部署前验证** | ① 当前版本的 CNCF 成熟度与最新版本号；② Sensor 状态 ConfigMap 的实际容量上限与大规模事件下的表现；③ 当前版本是否仍存在事件重复投递问题；④ 内置 `github` EventSource 在你们 GitHub 计划（Enterprise / 私有仓库）下的可用性与配额行为；⑤ EventBus JetStream 的资源开销；⑥ `github` EventSource 与我们自研 GitHub App 后端**并存**时的权限与配额冲突 |

---

## 12. 关联文档

| 主题 | 文档 |
|---|---|
| Argo Workflows 概念与引入评估（**为什么不用 Workflows**） | [`10-argo-workflows-evaluation.md`](./10-argo-workflows-evaluation.md) |
| Argo Events 在 CR Check 场景里的定位（§23.2 提到它的地方） | [`git-apps/11-github-app-concepts.md`](./git-apps/11-github-app-concepts.md) §23.2 |
| **从轮询到 Webhook 的契约变化**（Argo Events 是同一思路的通用版） | [`git-apps/12-webhook-push-vs-pull.md`](./git-apps/12-webhook-push-vs-pull.md) |
| CR Check（Go）的设计与实现评估 | [`git-apps/13-cr-check-go-design.md`](./git-apps/13-cr-check-go-design.md) |
| 事件驱动如何改变我们与 GitHub 的交互 | [`git-apps/12-webhook-push-vs-pull.md`](./git-apps/12-webhook-push-vs-pull.md) |

### 官方链接

| 主题 | 链接 |
|---|---|
| Argo Events 官网 / 文档 | https://argoproj.github.io/argo-events/ |
| EventSource 列表 | https://argoproj.github.io/argo-events/event-sources/ |
| Trigger 列表 | https://argoproj.github.io/argo-events/triggers/ |
| Sensors（过滤 / 依赖） | https://argoproj.github.io/argo-events/sensors/ |
| Workflows 用例页（指向 Argo Events 的那段） | https://argo-workflows.readthedocs.io/en/release-4.1/use-cases/infrastructure-automation/ |
