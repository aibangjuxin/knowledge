# Knative on GKE：Serverless 基础概念

> 面向对象：刚接触云原生 / GKE 平台工程的同学
> 目标：理解 Knative 是什么、Serving 和 Eventing 怎么分、在 GKE 上怎么用、和 Cloud Run 什么关系

---

## 1. 一句话定义

**Knative = 跑在 Kubernetes 上的 Serverless（无服务器）平台。**

它让你用"写一个容器 + 一个 YAML"的方式，得到一个**能自动扩缩容到零**的 HTTP 服务，
以及一套**事件驱动的消息路由**能力。

一个很关键的事实，很多人不知道：

> **Google Cloud Run 的控制面就是基于 Knative Serving 构建的。**
> 所以 Knative 可以理解为"**自己运维版的 Cloud Run**"——在 GKE 里跑，收益是**可移植 + 不绑定 GCP**，代价是**要自己运维**。

---

## 2. 先搞懂 Serverless 是什么

| 传统（有服务器） | Serverless |
|----------------|------------|
| 你要预估流量、买机器、开机 | 平台按请求量自动分配 |
| 流量为 0 时机器还在烧钱 | 流量为 0 时缩到零，**不花钱** |
| 扩容要分钟级 | 扩容秒级（Knative 的冷启动通常是亚秒级到数秒） |
| 平台不支持事件驱动 | 事件驱动是一等公民 |

**Serverless 不是"没有服务器"，而是"服务器由平台管理、计费跟着请求走"。**

### Serverless 的三种形态

| 形态 | 代表 | 你怎么用 |
|------|------|---------|
| FaaS（函数） | Cloud Functions | 传一段代码，平台跑 |
| **Serverless Container** | **Cloud Run / Knative Serving** | 传一个容器镜像，平台跑 |
| Serverless 消息 | Cloud Run jobs / Eventarc | 传一个任务，平台跑 |

Knative 覆盖的是 **Serverless Container** 和 **事件驱动**两块。

---

## 3. Knative 的两个子项目

```text
Knative
├── Serving   ── 把容器变成自动扩缩容的 HTTP 服务
└── Eventing  ── 把各种事件（Pub/Sub、存储变更……）路由到服务
```

**类比**：

- **Serving** = 餐厅的厨房（客人来了才开火，没人时熄火）
- **Eventing** = 传菜口 / 叫号系统（谁点的菜，做完端给谁）

---

## 4. Knative Serving：四个核心对象

这是 Serving 最需要理解的部分，因为它的对象链有点绕。

```text
Service (ksvc)  ── 用户直接创建的对象
      │
      ├── Configuration  ── 应用的"配置"（镜像 + 环境变量）
      │       │
      │       └── Revision (版本)  ── 一个不可变的具体版本
      │                │
      └── Route (路由)  ── 把流量分发到不同 Revision
```

| 对象 | 作用 | 小白理解 |
|------|------|---------|
| `Service` (ksvc) | 对外唯一入口，用户只跟它打交道 | "我下单的那个窗口" |
| `Configuration` | 定义用哪个镜像、什么配置 | "厨房的菜单" |
| `Revision` | **不可变**的一个版本快照（镜像 + 配置 + 扩缩容策略） | "菜单里的某一版菜谱，做出来就不再改" |
| `Route` | 把外部 URL 的流量按比例分给不同 Revision | "把 90% 的单给新菜谱，10% 给老菜谱做灰度" |

### 4.1 关键特性

| 特性 | 说明 |
|------|------|
| **Scale to Zero** | 无请求时把副本缩到 0，Pod 完全消失 |
| **按请求并发扩缩** | 不是按 CPU，而是按**并发请求数 / RPS**，更贴近真实负载 |
| **流量切分** | 一个 Service 后面挂多个 Revision，权重任意分配 → 天然金丝雀 / 蓝绿 |
| **每次变更产生新 Revision** | 天然版本化 + 天然回滚（把流量切回旧 Revision） |
| **不依赖 HPA / 复杂弹性策略** | 扩缩容逻辑内置 |

### 4.2 最小示例

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello
  namespace: default
spec:
  template:
    spec:
      containers:
        - image: gcr.io/my-project/hello:1.0.0
          ports:
            - containerPort: 8080
          env:
            - name: TARGET
              value: "GKE"
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits:   { memory: "512Mi" }
```

```bash
# 装 Knative Serving（官方安装指南按版本给出 URL）
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.x.x/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.x.x/serving-core.yaml

kubectl apply -f hello.yaml
kubectl get ksvc            # 看 URL
kubectl get revision        # 看版本
```

> 安装 URL 请以 knative.dev 官方 release 页面为准（版本号会变）。

---

## 5. Knative Eventing：事件怎么流转

Eventing 提供一套**标准事件协议（CloudEvents 1.0）** + 事件路由。

| 对象 | 作用 | 小白理解 |
|------|------|---------|
| `Broker` | 事件入口，一个"总接线盒" | "所有人把信投进同一个信箱" |
| `Trigger` | 订阅规则：从 Broker 取事件并转发给 Sink | "规定什么样的信送给谁" |
| `Channel` | 事件通道（底层实现，如 Pub/Sub / Kafka） | "信实际走的管道" |
| `Source` | 事件生产者 | "产生信的系统" |
| `Sink` | 事件消费者 | "收到信并干活的系统" |
| `EventDisplay` | 调试用，把收到的事件打印出来 | "看看信里写了什么" |

**GKE 上的典型链路（Pub/Sub 驱动）**：

```text
[上游写 GCS / 发 Pub/Sub]
        │
        ▼
  Pub/Sub Topic  ──►  [Source/Adapter]
        │
        ▼
  Knative Broker
        │  (Trigger: 过滤条件)
        ▼
  Knative Service (ksvc)  ──►  处理事件  ──►  写回下游
```

好处：**发布方不需要知道谁在消费**；消费方可以随时增删。
Pub/Sub + Knative Broker 的组合，在 GCP 上可以直接用 Pub/Sub 作为 Channel 实现。

---

## 6. 在 GKE 上怎么落地（历史与现状）

Knative 在 GCP 上的落地方式**变过**，这点很重要，选型前必须搞清楚。

| 形态 | 状态 | 说明 |
|------|------|------|
| **Cloud Run for Anthos** | **已归档 / 停止支持** | 早期的 GKE add-on 方式安装 Knative + Istio。后来 Google 转向 GKE Enterprise 路线。 |
| **GKE Enterprise fleet 版 Cloud Run** | **当前推荐** | `gcloud container fleet cloudrun enable` 在集群上启用 Knative Serving + Cloud Service Mesh，并纳入 fleet 统一管理 |
| **自己装 Knative 开源版** | 可行但自担 | 完全自管版本，版本升级、网络 Ingress 都要自己搞 |

```bash
# 当前推荐：在集群上启用 fleet 版 Cloud Run（Knative Serving + Cloud Service Mesh）
gcloud container fleet cloudrun enable \
  --project=my-project \
  --location=asia-southeast1 \
  --cluster=my-gke-cluster
```

> 具体参数与前置条件（版本要求、是否需要 GKE Enterprise 许可、Cloud Service Mesh 依赖）
> 请以 Google Cloud 官方文档为准：https://cloud.google.com/kubernetes-engine/docs/concepts/cloudrun-fleet

---

## 7. Cloud Run vs Knative on GKE

| 维度 | Cloud Run（托管） | Knative on GKE（自管） |
|------|------------------|----------------------|
| 运维 | Google 负责 | **你自己负责**（升级、Ingress、证书、扩缩容调优） |
| 扩缩容 | 托管平台调优 | 默认参数够用；要极限性能需自己调 min/max scale、并发数 |
| 网络入口 | Google 托管的负载均衡 + Cloud Armor | 自选 Ingress（Gateway API / Istio / GKE Gateway）+ Cloud Armor 需自己接 |
| 可移植性 | 绑定 GCP | **可移植**，任何 K8s 集群都能跑 |
| 事件生态 | Eventarc + Cloud Run 集成开箱即用 | Knative Eventing 自建，Pub/Sub 需要 Adapter |
| 成本结构 | 请求 + CPU 时长计费 | **按 GKE 节点资源计费**（即使 scale-to-zero，节点本身还在） |
| 与 GKE 现有能力结合 | 弱（另起一套） | **强**：同集群、同一套网络、同一套 IAM、同一套节点池 |
| 适合 | 独立微服务、对外 API | 已有 GKE 集群、需访问集群内服务、需要 mTLS / 内部流量治理 |

### 一个必须直说的取舍

> **Knative on GKE 的 scale-to-zero 只省"Pod 资源"，不省"节点钱"。**
> 节点池还在，节点还在计费。真正的成本节省要靠节点池本身能缩容，或者 Pod 混部（只省容器资源）。
> 如果你的诉求纯粹是省钱，Cloud Run 更直接。

---

## 8. 什么时候用 / 什么时候不用

| ✅ 适合用 Knative on GKE | ❌ 不适合 |
|------------------------|-----------|
| 已有 GKE 集群，想加 Serverless 能力，不想再引入一套托管平台 | 团队不想承担 Knative 版本升级和 Ingress 运维 |
| 服务需要访问集群内其他服务（内网调用、共享 Redis / DB） | 纯粹想省钱（节点成本还在） |
| 需要 mTLS、服务间流量治理（配合 Gateway / Service Mesh） | 大量长连接 / 长时间后台任务（Knative 会按请求超时回收） |
| 多团队共享集群，希望按"服务"而不是按"集群"扩缩容 | 已有 Cloud Run 且完全够用 |
| 事件驱动架构，需要 Pub/Sub 等事件源直接触发服务 | 需要复杂批处理（改用 Job / Kueue，见 `gke-job-runner.md`） |
| 想保持可移植性，未来可能出 GCP | 强依赖 GCP 专有能力（Cloud Run jobs、Eventarc 深度集成） |

---

## 9. 小结

| 记住这几点 | 内容 |
|-----------|------|
| Knative = K8s 上的 Serverless 平台 | 两个子项目：Serving（服务）+ Eventing（事件） |
| Serving 对象链 | Service → Configuration → Revision → Route |
| 核心特性 | Scale to Zero、按并发扩缩、流量切分、版本天然化 |
| 和 Cloud Run 的关系 | **Cloud Run 控制面基于 Knative Serving**；Knative on GKE = 自管版、可移植 |
| GKE 落地方式 | 优先 fleet 版 Cloud Run（`gcloud container fleet cloudrun enable`）；旧 add-on 已归档 |
| 成本真相 | Scale-to-zero 省 Pod 不省节点 |
| 事件链路 | Pub/Sub → Broker → Trigger → Service（CloudEvents 1.0） |

**复杂度评估**：简单（装 Serving，跑一个 ksvc）→ 中等（+ 事件驱动 + 流量切分 + Cloud Armor 对接）→ 高级 / 企业级（+ 服务网格 mTLS + 多集群 + 成本调优）

---

## 10. 参考链接

- Knative 官网 / 文档：https://knative.dev/docs/
- Knative Serving 概览：https://knative.dev/docs/serving/
- Knative Eventing 概览：https://knative.dev/docs/eventing/
- CloudEvents 规范：https://cloudevents.io/
- Google Cloud Run 概览：https://cloud.google.com/run/docs
- GKE fleet 版 Cloud Run：https://cloud.google.com/kubernetes-engine/docs/concepts/cloudrun-fleet
- Cloud Run for Anthos（历史文档，注意已归档）：https://cloud.google.com/anthos/docs/cloud-run
- Cloud Run 架构（基于 Knative）：https://cloud.google.com/run/docs/fundamentals/architecture
