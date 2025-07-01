

### 场景描述：
当前 Java Pub/Sub 客户端运行在 GKE Pod 中，采用 StreamingPull 拉取消息，使用线程池（executor-threads）进行 HTTP 调用（同步阻塞）。为避免线程阻塞导致系统卡顿，通过 HPA 对 CPU 占用进行监控并触发自动扩容。



✅ 线程池占用与 GKE HPA 扩容关系图

#### 线程池占用与 GKE HPA 扩容关系图

```mermaid
flowchart TD
    PS[Pub/Sub Topic] -->|StreamingPull| Pod1
    PS -->|StreamingPull| Pod2

    subgraph Pod1 [GKE Pod #1 (1 vCPU)]
        direction TB
        T1[Thread 1 ➝ waiting HTTP]
        T2[Thread 2 ➝ waiting HTTP]
        T3[Thread 3 ➝ waiting HTTP]
        T4[Thread 4 ➝ waiting HTTP]
        CPU1[CPU 使用率提升] -->|触发 HPA| HPA[Pod 扩容触发]
    end

    subgraph Pod2 [GKE Pod #2 (1 vCPU)]
        direction TB
        T5[Thread 1 ➝ waiting HTTP]
        T6[Thread 2 ➝ waiting HTTP]
        T7[Thread 3 ➝ waiting HTTP]
        T8[Thread 4 ➝ waiting HTTP]
        CPU2[CPU 使用率提升] -->|触发 HPA| HPA
    end

    HPA --> Pod3[🆕 Pod #3 启动]
    Pod3 -->|建立 StreamingPull| PS

    note right of HPA
        并发线程等待 backend 响应 ➝ CPU 调度变高 ➝ HPA 检测到 CPU 上升 ➝ 自动扩容 Pod
    end note

---

### ✅ Pub/Sub 消息进入处理线程的流转路径

```markdown
#### Pub/Sub 消息进入处理线程的流转路径

```mermaid
flowchart TD
    PS[Pub/Sub Topic] -->|StreamingPull| SubClient[Java Subscriber Client]

    subgraph SubClient [GKE Pod 中的 Subscriber Client]
        direction TB
        Queue[Message Queue(Buffer)]
        ThreadPool[Thread Pool (executor-threads)]
        API[调用 backend API（阻塞同步）]
        Queue -->|1| Thread1[线程1 ➝ message1 ➝ HTTP请求] --> API
        Queue -->|2| Thread2[线程2 ➝ message2 ➝ HTTP请求] --> API
        Queue -->|...| ThreadN[线程N ➝ messageN ➝ HTTP请求] --> API
    end

    note right of ThreadPool
        Pub/Sub StreamingPull 会预先填充消息队列，
        空闲线程拉出消息处理，
        如果线程都被阻塞，会出现处理 backlog
    end note

---


