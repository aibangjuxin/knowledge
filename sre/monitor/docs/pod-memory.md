# GKE Pod 内存监控指标详解（以 Java Application 为核心视角）

## 1. 问题分析

在 GKE 中，**Pod 的内存相关指标 = Kubernetes 调度语义 + Linux cgroup 实际使用情况**。

你当前关注的 4 个指标，本质上分别回答了 4 个问题：

- **我承诺给 Pod 多少内存？（Request）**

- **Pod 实际吃了多少内存？（Used）**

- **实际使用占承诺的比例是多少？（Request % Used）**

- **还有多少“被预留但没用”的内存？（Request Unused）**

对于 **Java 应用**，还需要额外考虑：

- JVM Heap / Metaspace / Direct Memory

- Container Memory Limit 与 `-Xmx` 的匹配关系

- GC 行为对瞬时内存的影响

---

## 2. 指标逐项详细解释

### 2.1 Memory Used

| 字段 | 含义 |

|----|----|

| **Memory Used** | Pod / Container 当前**实际使用的物理内存** |

**来源**

- Linux cgroup（`memory.usage_in_bytes`）

- 包含：

- JVM Heap

- Metaspace

- Direct / NIO Buffer

- Thread Stack

- Native Library

- Page Cache（部分场景）

**单位**

- Bytes / Mi

**关键点**

- **这是 OOMKill 的直接依据**

- 一旦接近 `limits.memory` → 风险极高

---

### 2.2 Requested Memory

| 字段 | 含义 |

|----|----|

| **Requested Memory** | Pod 在 `spec.containers[].resources.requests.memory` 中声明的内存 |

**作用**

- **调度保证（Scheduling Guarantee）**

- Node 上可分配内存 = Node Capacity - Σ Requests

**重要原则**

> Kubernetes **只保证 request，不保证 limit**

**示例**

````yaml

resources:

  requests:

    memory: "2Gi"

  limits:

    memory: "4Gi"









2.3 Memory Request % Used



|   |   |
|---|---|
|字段|含义|
|Memory Request % Used|Memory Used / Requested Memory|

公式

Memory Request % Used = Used / Request × 100%

解读维度

|   |   |
|---|---|
|比例|含义|
|< 50%|request 明显偏大|
|70%–90%|较合理|
|> 100%|实际使用已超过调度承诺|

⚠️ 超过 100% 并不违规，但意味着：



- Node 级别存在被挤压风险
- 大规模 Pod 同时膨胀时容易触发 Eviction











2.4 Requested Memory Unused



|   |   |
|---|---|
|字段|含义|
|Requested Memory Unused|Request - Used（最小值为 0）|

核心含义



你“占坑”了但没用的内存



对平台的影响



- Node 内存利用率下降
- 限制整体 Pod 密度
- 影响成本（GKE 节点规格）











3. Java Application 专项解读







3.1 JVM 内存结构 vs GKE 指标



Container Memory Used

│

├─ JVM Heap (-Xmx)

├─ Metaspace (-XX:MaxMetaspaceSize)

├─ Direct Memory (-XX:MaxDirectMemorySize)

├─ Thread Stack (-Xss × threads)

└─ Native / libc / page cache

➡️ GKE 看到的是总和，不是 Heap









3.2 典型 Java Pod 示例







Pod 资源定义



resources:

  requests:

    memory: "3Gi"

  limits:

    memory: "4Gi"



JVM 参数



-Xms2g

-Xmx2g

-XX:MaxMetaspaceSize=256m

-XX:MaxDirectMemorySize=512m

-Xss1m



实际运行监控



|   |   |
|---|---|
|指标|数值|
|Heap Used|1.6 Gi|
|Non-Heap + Native|0.7 Gi|
|Memory Used|2.3 Gi|
|Requested Memory|3 Gi|
|Request % Used|76%|
|Request Unused|0.7 Gi|

➡️ 这是一个健康状态









3.3 危险配置示例（真实常见）



requests:

  memory: "2Gi"

limits:

  memory: "2Gi"

-Xmx2g

问题



- JVM 认为自己有 2Gi
- 实际 Container 需要 Heap + Native
- Used > 2Gi → 直接 OOMKilled











4. 如何评估「用户内存是否合理」







4.1 推荐评估方法（平台视角）







Step 1：看长期 P95 / P99





- Memory Used（不是瞬时峰值）
- GC 稳态后的使用量







Step 2：对齐关系检查



Xmx ≤ limits.memory × 60%–70%

request.memory ≈ P95 Used + 20%



Step 3：看 Request Unused



|   |   |
|---|---|
|状态|判断|
|Unused > 40%|request 偏大|
|Unused ≈ 10–30%|合理 buffer|
|Unused ≈ 0|高风险|









4.2 平台推荐模板（Java）



resources:

  requests:

    memory: "3Gi"

  limits:

    memory: "4Gi"

-Xms2g

-Xmx2.4g

-XX:MaxMetaspaceSize=256m

-XX:MaxDirectMemorySize=512m









5. 指标之间的关系总结



|   |   |
|---|---|
|指标|本质|
|Memory Used|真实消耗（OOM依据）|
|Requested Memory|调度承诺（节点维度）|
|Request % Used|是否高估/低估 request|
|Request Unused|资源浪费程度|









6. 平台级最佳实践（GKE + Java）





- 不允许 Xmx == limits.memory
- request 以 P95 Used 为基准
- limit 给 JVM 留 30% Native buffer
- 用 HPA 时避免只看 CPU
- 定期做 Request Rightsizing











7. 一句话总结





GKE 看的是容器内存总量，JVM 只控制其中一部分；

Request 决定你能不能被调度，Limit 决定你会不会被杀。



如果你愿意，我可以下一步帮你做：



- 👉 Java Pod 内存 sizing 标准化文档
- 👉 基于 GKE Metrics 的自动 request 推荐公式
- 👉 OOM / Eviction 排障流程图（Mermaid）




# GKE Pod OOM / Eviction 排障流程图



## 1. 问题分析



在 GKE 中，Pod 被 Kill 或重启，**本质只有三大类原因**：



1. **Container 超过 limits.memory → OOMKilled**

2. **Node 内存压力 → Eviction**

3. **应用自身崩溃（非内存）**



OOM 与 Eviction 的**根本区别**在于：

- **OOMKilled**：cgroup 触发（容器级）

- **Eviction**：kubelet 触发（节点级）



---



## 2. OOM / Eviction 统一排障流程图



```mermaid

graph TD

    A["Pod 重启 / 被 Kill"] --> B["kubectl describe pod"]

    B --> C{"Exit Code 是否为 137?"}



    C -->|Yes| D["查看 Container Status: OOMKilled"]

    C -->|No| E["查看 Last State / Application Exit"]



    D --> F["确认 limits.memory"]

    F --> G{"Memory Used >= limits.memory?"}



    G -->|Yes| H["容器级 OOMKilled"]

    G -->|No| I["短时峰值或统计延迟"]



    H --> J["检查 JVM Xmx / Native Memory"]

    J --> K{"Xmx + Native 是否接近 Limit?"}



    K -->|Yes| L["内存配置不合理"]

    K -->|No| M["疑似 Direct / Thread 泄漏"]



    E --> N["检查 Node 事件"]

    N --> O{"是否有 Evicted 事件?"}



    O -->|Yes| P["Node 内存压力 Eviction"]

    O -->|No| Q["应用主动退出 / Bug"]



    P --> R["查看 Node Memory Pressure"]

    R --> S{"Node Available < Eviction Threshold?"}



    S -->|Yes| T["节点资源不足"]

    S -->|No| U["QoS 等级低被优先驱逐"]









3. OOMKilled 排障路径详解







3.1 快速确认 OOM



kubectl describe pod <pod> -n <ns>

关注字段：

State:      Terminated

Reason:     OOMKilled

Exit Code:  137









3.2 OOMKilled 常见根因（Java）



|   |   |
|---|---|
|根因|说明|
|Xmx = limits|未给 Native 留空间|
|Direct Memory 泄漏|Netty / NIO|
|Metaspace 膨胀|动态 ClassLoader|
|Thread 爆炸|每线程默认 1M 栈|
|GC 瞬时扩容|CMS / G1 阶段性峰值|









3.3 Java OOM 经验公式



Container Memory Limit

≈ Xmx / 0.65

示例：



- limit = 4Gi
- Xmx ≤ 2.5Gi











4. Eviction 排障路径详解







4.1 Evicted 的典型特征



Reason: Evicted

Message: The node was low on resource: memory.









4.2 Node 级检查



kubectl describe node <node>

重点关注：

MemoryPressure=True









4.3 Eviction 决策顺序（简化）



BestEffort → Burstable → Guaranteed

|   |   |
|---|---|
|QoS|条件|
|Guaranteed|request == limit|
|Burstable|request < limit|
|BestEffort|无 request / limit|

⚠️ Burstable 且 request 偏小的 Java Pod 是高风险对象









5. OOM vs Eviction 快速对照表



|   |   |   |
|---|---|---|
|维度|OOMKilled|Evicted|
|触发层|Container|Node|
|Exit Code|137|无|
|describe pod|OOMKilled|Evicted|
|是否受 QoS 影响|否|是|
|常见原因|limit 太小|Node 超卖|









6. 平台级最佳实践







6.1 防 OOM





- limit ≥ P99 Used × 1.3
- Xmx ≤ limit × 65%
- 显式设置 Direct / Metaspace
- 避免 request == limit（Java）











6.2 防 Eviction





- request 基于 P95 Used
- Node 不过度超卖
- 核心服务使用 PDB
- 避免 BestEffort Pod











7. 排障 Checklist（可直接复用）



[ ] 是否 OOMKilled?

[ ] limits.memory 是否合理

[ ] Xmx 是否小于 limit

[ ] Native Memory 是否可控

[ ] Node 是否 MemoryPressure

[ ] Pod QoS 等级

[ ] request 是否严重偏小









8. 一句话总结





OOM 是你给得太少，Eviction 是大家一起不够用。



如果你需要，我可以继续帮你输出：



- 👉 Java OOM 定位命令清单（jcmd / jmap / NMT）
- 👉 GKE Eviction Threshold & Node Sizing 模型
- 👉 平台级 Memory Rightsizing 自动化方案
````
