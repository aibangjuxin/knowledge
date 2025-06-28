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
        - [Subscriptions](./pub-sub-subscription.md)
    - DLQ
        - [DLQ](./dlq.md)
            - 当消息处理失败时，Pub/Sub 会将消息重新路由到 DLQ
            - 如果原来的 subscription 没有配置 DLQ，那么需要 update subscription，添加 DLQ
            - pub-sub ==> maxDeliveryAttempts
                - 用于控制消息进入死信队列 DLQ 的时机
                - [pub-sub-max-delivery-attempts](./pub-sub-max-delivery-attempts.md)
    -

- monitor

    - [pub-sub-monitor-parameter](./pub-sub-monitor-parameter.md)
    - core parameter
        - [streaming_pull_response_count](./pub-sub-monitor-parameter.md#streaming_pull_response_count)
        - [send_message_count](./pub-sub-monitor-parameter.md#send_message_count)
        - [unacked_messages_by_region](./pub-sub-monitor-parameter.md#unacked_messages)
        - [unacked_messages_by_region](./unacked-message-by-region.md)



