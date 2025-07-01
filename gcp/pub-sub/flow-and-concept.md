   1. 任务触发：Cloud Scheduler 按预定计划，向指定的 Pub/Sub Topic 发布一条消息。
   2. 消息路由：Pub/Sub Topic 接收到消息后，立即将其路由到所有关联的 Subscription。
   3. 消息消费 (StreamingPull)：
       * GKE 中的每个 Pod 都作为一个独立的订阅者客户端，与 Subscription 建立一个持久的 gRPC StreamingPull 连接。
       * Pub/Sub 通过这些长连接实时地将消息流式传输给可用的 Pod。
   4. 任务处理：
       * Pod 收到消息后，调用后端的 Backend API 来执行实际的业务逻辑。
   5. 结果反馈 (ACK/NACK)：
       * 成功路径：如果 Backend API 在预设时间内成功返回，Pod 会向 Pub/Sub 发送一个 ACK（确认）信号，该消息被视为处理完毕，将从订阅中永久删除。
       * 失败路径：如果 Backend API 返回错误或处理超时，Pod 不会发送 ACK。
   6. 自动重试：
       * 对于未被 ACK 的消息，一旦其 ackDeadlineSeconds 到期，Pub/Sub 会认为该消息处理失败，并将其重新投递给一个可用的消费者（可能是同一个 Pod 或其他
         Pod）。
   7. 死信队列 (DLQ)：
       * 如果在多次重试（由 maxDeliveryAttempts 参数定义）后，某条消息仍然无法被成功处理，Pub/Sub 会停止重试，并将其发送到预先配置好的 Dead Letter Queue 
         (DLQ) 中。这可以防止“毒消息”无限循环，阻塞整个系统。
   8. 并发扩展：
       * 当消息量增大时，只需增加 GKE 中 Pod 的副本数。每个新的 Pod 都会建立自己的 StreamingPull 连接，从而线性地提升整个系统的消息处理能力。
- the streaming pull

```mermaid
sequenceDiagram
    participant SS as GKE Pod<br/>(Subscriber Client)
    participant PS as Pub/Sub Server<br/>(gRPC Endpoint)

    SS->>+PS: Establish gRPC StreamingPull()
    loop 持续消息流
        PS-->>SS: Deliver messages (streaming)
        SS->>PS: ack / modifyAckDeadline
        Note right of SS: 本地缓存处理，按需 ack
    end
```

- for show streaming pull

```mermaid
sequenceDiagram
    %% 上层业务流程
    participant CS as Cloud Scheduler
    participant PS as Pub/Sub Topic
    participant SS as GKE Pod<br/>(Scheduler Service)
    participant API as Backend API

    Note over CS,PS: 定时任务触发
    CS->>+PS: Publish message

    Note over SS,PS: GKE Pod 使用 gRPC StreamingPull 拉取消息

    %% 内部 StreamingPull 流程作为子图展开
    rect rgb(240, 240, 255)
        participant SS as GKE Pod<br/>(Subscriber Client)
        participant GRPC as Pub/Sub Server<br/>(StreamingPull)

        SS->>+GRPC: 建立 gRPC StreamingPull 连接
        loop 持续消息流
            GRPC-->>SS: stream message<br/>+ ackId
            alt 成功处理
                SS->>+API: 调用后端 API
                API-->>-SS: Response
                SS->>GRPC: acknowledge(ackId)
            else 失败或超时
                SS-->>GRPC: 未 ack（ackDeadline 触发重投递）
            end
        end
    end
```

fix this one 
```mermaid
sequenceDiagram
    %% 上层业务流程
    participant CS as Cloud Scheduler
    participant PS as Pub/Sub Topic
    participant SS as GKE Pod<br/>(Scheduler Service)
    participant API as Backend API

    Note over CS,PS: 定时任务触发
    CS->>+PS: Publish message

    Note over SS,PS: GKE Pod 使用 gRPC StreamingPull 拉取消息

    %% 内部 StreamingPull 流程作为子图展开
    rect rgb(240, 240, 255)
        participant SS as GKE Pod<br/>(Subscriber Client)
        participant GRPC as Pub/Sub Server<br/>(StreamingPull)

        SS->>+GRPC: 建立 gRPC StreamingPull 连接
        loop 持续消息流
            GRPC-->>SS: stream message<br/>+ ackId
            SS->>GRPC: acknowledge(ackId)
            SS->>+API: 调用后端 API（异步或独立处理）
            API-->>-SS: Response
        end
    end
```

- merged
    - core concept
    - 开启并发 [StreamingPull](./pub-sub-monitor-parameter.md#streamingpull)其实单独扩展 Pod 的数量也就是扩展了并发能力
    - [streaming_pull_response_count](./pub-sub-monitor-parameter.md#streaming_pull_response_count)

```mermaid
sequenceDiagram
    participant CS as Cloud Scheduler
    participant PS as Pub/Sub Topic<br/>(Server端也负责 StreamingPull)
    participant SS as GKE Pod<br/>(Scheduler Service)
    participant API as Backend API

    Note over CS,PS: 定时任务触发
    CS->>+PS: Publish message

    Note over SS,PS: GKE Pod 使用 gRPC StreamingPull 拉取消息

    opt GKE Pod 与 Pub/Sub 建立 StreamingPull（长连接）
        SS->>+PS: 建立 gRPC StreamingPull 连接
        loop 消息持续流式传输
            PS-->>SS: stream message<br/>+ ackId
            alt 成功处理
                SS->>+API: 调用后端 API
                API-->>-SS: Response
                SS->>PS: acknowledge(ackId)
            else 失败或超时
                SS-->>PS: 不 ack ➝ 等待 ackDeadline 超时
            end
        end
    end
```
fix this one 

```mermaid
sequenceDiagram
    participant CS as Cloud Scheduler
    participant PS as Pub/Sub Topic<br/>(Server端也负责 StreamingPull)
    participant SS as GKE Pod<br/>(Scheduler Service)
    participant API as Backend API

    Note over CS,PS: 定时任务触发
    CS->>+PS: Publish message

    Note over SS,PS: GKE Pod 使用 gRPC StreamingPull 拉取消息

    opt GKE Pod 与 Pub/Sub 建立 StreamingPull（长连接）
        SS->>+PS: 建立 gRPC StreamingPull 连接
        loop 消息持续流式传输
            PS-->>SS: stream message<br/>+ ackId
            SS->>PS: acknowledge(ackId)
            SS->>+API: 调用后端 API（异步处理）
            API-->>-SS: Response
        end
    end
```

```mermaid
sequenceDiagram
    participant CS as Cloud Scheduler
    participant PS as Pub/Sub Topic<br/>(含 StreamingPull 服务)
    participant Pod1 as GKE Pod #1<br/>(Scheduler Client)
    participant Pod2 as GKE Pod #2<br/>(Scheduler Client)
    participant API as Backend API

    Note over CS,PS: 定时触发任务
    CS->>+PS: Publish message

    Note over Pod1,PS: 每个 Pod 与 Pub/Sub 建立 gRPC StreamingPull

    opt Pod #1 StreamingPull 流
        Pod1->>+PS: 建立 gRPC StreamingPull
        loop 持续处理消息
            PS-->>Pod1: message + ackId
            alt 成功处理
                Pod1->>+API: 调用后端 API
                API-->>-Pod1: 返回响应
                Pod1->>PS: acknowledge(ackId)
            else 失败 / 未 ack
                Pod1-->>PS: ackDeadline 到期前未 ack
            end
        end
    end

    opt Pod #2 StreamingPull 流
        Pod2->>+PS: 建立 gRPC StreamingPull
        loop 持续处理消息
            PS-->>Pod2: message + ackId
            alt 成功处理
                Pod2->>+API: 调用后端 API
                API-->>-Pod2: 返回响应
                Pod2->>PS: acknowledge(ackId)
            else 失败 / 未 ack
                Pod2-->>PS: ackDeadline 到期前未 ack
            end
        end
    end

    Note over Pod1,Pod2: ⬆️ 扩容多个 Pod 即增加并发 StreamingPull 能力
```
- fix this one 
```mermaid
sequenceDiagram
    participant CS as Cloud Scheduler
    participant PS as Pub/Sub Topic<br/>(含 StreamingPull 服务)
    participant Pod1 as GKE Pod #1<br/>(Scheduler Client)
    participant Pod2 as GKE Pod #2<br/>(Scheduler Client)
    participant API as Backend API

    Note over CS,PS: 定时触发任务
    CS->>+PS: Publish message

    Note over Pod1,PS: 每个 Pod 与 Pub/Sub 建立 gRPC StreamingPull

    opt Pod #1 StreamingPull 流
        Pod1->>+PS: 建立 gRPC StreamingPull
        loop 持续处理消息
            PS-->>Pod1: message + ackId
            Pod1->>PS: acknowledge(ackId)
            Pod1->>+API: 调用后端 API（异步处理）
            API-->>-Pod1: 返回响应
        end
    end

    opt Pod #2 StreamingPull 流
        Pod2->>+PS: 建立 gRPC StreamingPull
        loop 持续处理消息
            PS-->>Pod2: message + ackId
            Pod2->>PS: acknowledge(ackId)
            Pod2->>+API: 调用后端 API（异步处理）
            API-->>-Pod2: 返回响应
        end
    end

    Note over Pod1,Pod2: ⬆️ 扩容多个 Pod 即增加并发 StreamingPull 能力
```

以下是你提供的时序图的修复版本，已将 ack 与后端 API 调用解耦，符合你目前的实际逻辑 —— GKE 中的多个 Pod 一旦拉取到消息就立即 ack，不等待后端处理完成
✅ 修复关键点：

修复内容	说明
ack 提前	ack 操作在收到消息后立即执行
后端调用独立	调用后端 API 不再决定是否 ack，逻辑上解耦
多 Pod 拉取并发能力	每个 Pod 都有独立 StreamingPull 连接并独立 ack


⸻

这个图现在准确反映了 Pub/Sub StreamingPull 的客户端 ack 模型，并且支持横向扩容多个 Pod 并发拉取和独立处理。如果你下一步想对 “失败重试”、“DLQ”、“重放消息” 建模，也可以继续扩展这张图。需要的话可以告诉我场景，我来画。

- About 扩容多个 Pod 即增加并发 StreamingPull 能力

| 特性                                             | 状态 | 说明                                     |
| ------------------------------------------------ | ---- | ---------------------------------------- |
| 每个 Pod 是独立的 Subscriber 客户端              | ✅   | 建立独立 StreamingPull 会话              |
| 每条消息有自己的 ackDeadline，Pod 负责自己的消息 | ✅   | ack 是 per-message 的，逻辑上由 Pod 管理 |
| Pub/Sub 会在 ackDeadline 到期后将消息重新分发给其他 Pod | ✅   | 重新分发消息, 确保公平性和高吞吐         |
| Pod 崩溃不影响其他 Pod                           | ✅   | 影响范围只限其未 ack 消息                |
| 多 Pod 并发能防止阻塞和堆积                      | ✅   | 是扩展 StreamingPull 并发的推荐做法      |


---

```mermaid
sequenceDiagram
    participant CS as Cloud Scheduler
    participant PS as Pub/Sub Topic<br/>(含 StreamingPull 服务)
    participant Pod1 as GKE Pod #1<br/>(Scheduler Client)
    participant Pod2 as GKE Pod #2<br/>(Scheduler Client)
    participant API as Backend API

    Note over CS,PS: 定时触发任务
    CS->>+PS: Publish message

    Note over Pod1,PS: 每个 Pod 与 Pub/Sub 建立 gRPC StreamingPull

    opt Pod #1 StreamingPull 流
        Pod1->>+PS: 建立 gRPC StreamingPull
        loop 持续处理消息
            PS-->>Pod1: message + ackId
            alt 成功处理
                Pod1->>+API: 调用后端 API
                API-->>-Pod1: 返回响应
                Pod1->>PS: acknowledge(ackId)
            else 失败 / 未 ack
                Pod1-->>PS: ackDeadline 到期前未 ack
            end
        end
    end

    opt Pod #2 StreamingPull 流
        Pod2->>+PS: 建立 gRPC StreamingPull
        loop 持续处理消息
            PS-->>Pod2: message + ackId
            alt 成功处理
                Pod2->>+API: 调用后端 API
                API-->>-Pod2: 返回响应
                Pod2->>PS: acknowledge(ackId)
            else 失败 / 未 ack
                Pod2-->>PS: ackDeadline 到期前未 ack
            end
        end
    end
```
- fix this one 
```mermaid
sequenceDiagram
    participant CS as Cloud Scheduler
    participant PS as Pub/Sub Topic<br/>(含 StreamingPull 服务)
    participant Pod1 as GKE Pod #1<br/>(Scheduler Client)
    participant Pod2 as GKE Pod #2<br/>(Scheduler Client)
    participant API as Backend API

    Note over CS,PS: 定时触发任务
    CS->>+PS: Publish message

    Note over Pod1,PS: 每个 Pod 与 Pub/Sub 建立 gRPC StreamingPull

    opt Pod #1 StreamingPull 流
        Pod1->>+PS: 建立 gRPC StreamingPull
        loop 持续处理消息
            PS-->>Pod1: message + ackId
            Pod1->>PS: acknowledge(ackId)
            Pod1->>+API: 调用后端 API（异步处理）
            API-->>-Pod1: 返回响应
        end
    end

    opt Pod #2 StreamingPull 流
        Pod2->>+PS: 建立 gRPC StreamingPull
        loop 持续处理消息
            PS-->>Pod2: message + ackId
            Pod2->>PS: acknowledge(ackId)
            Pod2->>+API: 调用后端 API（异步处理）
            API-->>-Pod2: 返回响应
        end
    end
```

Note over Pod1,Pod2:
    - 每个 Pod 是独立的 Subscriber Client
    - 每个 Pod 维护自己的 StreamingPull 会话与 ack 逻辑
    - 每条消息都有独立的 ackDeadline（由拉取方管理
    - 某个 Pod 崩溃或处理失败不会影响其他 Pod 的消费
    - Pub/Sub 会在 ackDeadline 到期后将消息重新分发给其他 Pod
    - 扩容 Pod 数量 == 横向扩展 StreamingPull 并发能力，提升吞吐并降低堆积

- Pub/Sub Topics、Subscriptions、Cloud Scheduler Jobs 三者的关系：

    - Cloud Scheduler 定时触发 Pub/Sub Topic 发布消息
    - Pub/Sub Topic 负责消息路由，将消息推送给所有订阅了该 Topic 的 Subscriptions
    - GKE Pod 与 Pub/Sub 建立 StreamingPull 长连接，持续接收消息
    - reference
        - [3 components](./pub-sub-command.md)
        - Schedule Job
            - [scheduler-jobs-describe](./scheduler-jobs-describe.md)
            - maxBackoffDuration
                - 当消息处理失败时，Pub/Sub 会根据指数退避算法（指数退避算法）重新路由消息，直到达到最大重试次数（maxDeliveryAttempts）
            - [maxBackoffDuration](./pub-sub-max-delivery-attempts.md#2-maxbackoffdurationcloud-scheduler)
                - []
        - [Subscriptions](./pub-sub-subscriptions.md)
	        - ackDeadlineSeconds
  	        - 个人理解因为ackDeadlineSeconds等于是一个总开关一样,后面的时间处理都不应该超过这个时间
  	        - 确保在 PULL 模式下，所有处理都在 ackDeadlineSeconds 限制内完成，以避免消息堆积
    	        - [方案1: 客户端控制超时 (推荐)](./pub-sub-subscriptions.md#方案1-客户端控制超时-推荐)
    	        - [方案2: 快速失败 + 智能重试](./pub-sub-subscriptions.md#方案2-快速失败--智能重试)
    	        - [方案3. 快速失败的 HTTP 配置](./pub-sub-subscriptions.md#方案3-快速失败的-http-配置)
	        ```bash
            ackDeadlineSeconds: 600s (10分钟)
            Kong 超时: 6分钟 × 3次重试 = 18分钟
            重试间隔: 0s + 10s + 20s = 30s  
            总处理时间: ≈ 18分30秒 >> 600s ❌
            ```
	        - the ackDeadlineSeconds flow
	        - the flow next
```mermaid
	sequenceDiagram
    participant PS as Pub/Sub Server
    participant SS as Schedule Service
    participant Kong as Kong Gateway
    participant BS as Backend Service
    
    Note over PS,BS: ackDeadlineSeconds 计时开始 ⏰
    PS->>SS: 消息可供拉取 (available)
    SS->>PS: Pull Request
    PS->>SS: 返回消息 (delivery)
    
    Note over SS: 消息处理开始
    SS->>SS: 解析消息
    SS->>Kong: HTTP请求 (Retry 1)
    Kong->>BS: 转发请求
    BS-->>Kong: 响应超时/失败
    Kong-->>SS: 超时响应
    
    SS->>Kong: HTTP请求 (Retry 2) 
    Kong->>BS: 转发请求
    BS-->>Kong: 响应超时/失败
    Kong-->>SS: 超时响应
    
    SS->>Kong: HTTP请求 (Retry 3)
    Kong->>BS: 转发请求
    BS-->>Kong: 成功响应
    Kong-->>SS: 成功响应
    
    SS->>PS: ACK 确认
    Note over PS,BS: ackDeadlineSeconds 计时结束 ⏹️
```
- fix 
```mermaid
sequenceDiagram
    participant PS as Pub/Sub Server
    participant SS as Schedule Service<br/>(GKE Pod)
    participant Kong as Kong Gateway
    participant BS as Backend Service

    Note over PS: ackDeadlineSeconds 计时开始 ⏰
    PS->>SS: 消息可供拉取 (available)
    SS->>PS: Pull Request
    PS->>SS: 返回消息 (delivery)

    Note over SS: 接收消息即刻 ACK
    SS->>PS: ACK 确认 ✅
    Note over PS: ackDeadlineSeconds 计时结束 ⏹️

    SS->>SS: 解析消息
    SS->>Kong: HTTP请求 (Retry 1)
    Kong->>BS: 转发请求
    BS-->>Kong: 响应超时/失败
    Kong-->>SS: 超时响应

    SS->>Kong: HTTP请求 (Retry 2)
    Kong->>BS: 转发请求
    BS-->>Kong: 响应超时/失败
    Kong-->>SS: 超时响应

    SS->>Kong: HTTP请求 (Retry 3)
    Kong->>BS: 转发请求
    BS-->>Kong: 成功响应
    Kong-->>SS: 成功响应
```
- DLQ
        - [DLQ](./dlq.md)
            - 当消息处理失败时，Pub/Sub 会将消息重新路由到 DLQ
            - 如果原来的 subscription 没有配置 DLQ，那么需要 update subscription，添加 DLQ
            - pub-sub ==> maxDeliveryAttempts
                - 用于控制消息进入死信队列 DLQ 的时机
                - [pub-sub-max-delivery-attempts](./pub-sub-max-delivery-attempts.md)


- monitor

    - [pub-sub-monitor-parameter](./pub-sub-monitor-parameter.md)
    - core parameter
        - [streaming_pull_response_count](./pub-sub-monitor-parameter.md#streaming_pull_response_count)
        - [send_message_count](./pub-sub-monitor-parameter.md#send_message_count)
        - [unacked_messages_by_region](./pub-sub-monitor-parameter.md#unacked_messages)
        - [unacked_messages_by_region](./unacked-message-by-region.md)



```mermaid

```



