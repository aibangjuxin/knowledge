1. **Pub/Sub PULL 模式完整流程图**
2. **StreamingPull 并发机制详解**
3. **消费堆积 ➝ 指标异常 ➝ 告警 ➝ 自动扩容 ➝ 恢复** 全链路演化图
4. 建议告警阈值表格



---

## **📡 Google Pub/Sub PULL 模式 + GKE StreamingPull 架构说明**

### **1️⃣ 消费流程图（含 StreamingPull 细节）**

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
    - 每个 Pod 是独立的 Subscriber Client\n
    - 每个 Pod 维护自己的 StreamingPull 会话与 ack 逻辑\n
    - 每条消息都有独立的 ackDeadline（由拉取方管理）\n
    - 某个 Pod 崩溃或处理失败不会影响其他 Pod 的消费\n
    - Pub/Sub 会在 ackDeadline 到期后将消息重新分发给其他 Pod\n
    - 扩容 Pod 数量 == 横向扩展 StreamingPull 并发能力，提升吞吐并降低堆积


---

### **2️⃣ 指标异常 ➝ 告警 ➝ 自动修复流程图**

```mermaid
graph TD
    A[Pub/Sub Message Publish] --> B[unacked_messages_by_region ↑]
    B --> C[oldest_unacked_message_age ↑]
    C --> D[ack_message_count 下降]
    D --> E[Stackdriver/Cloud Monitoring 告警规则触发]
    E --> F[通知 SRE / PagerDuty]
    E --> G[触发 GKE HPA 或 KEDA 扩容]

    G --> H[Scheduler Pods 数量增加]
    H --> I[StreamingPull 并发能力上升]
    I --> J[ack rate 提升，堆积下降]
    J --> K[unacked_messages_by_region 恢复正常]

    style B fill:#FFF8DC,stroke:#FFA500,stroke-width:2px
    style C fill:#FFE4E1,stroke:#FF6347,stroke-width:2px
    style D fill:#FFDDDD,stroke:#FF0000,stroke-width:2px
    style E fill:#FAFAD2,stroke:#B8860B,stroke-width:2px
    style F fill:#F0FFFF,stroke:#00CED1,stroke-width:1px
    style G fill:#E0FFFF,stroke:#00CED1,stroke-width:1px
    style H fill:#E6FFE6,stroke:#32CD32,stroke-width:2px
    style I fill:#E6FFE6,stroke:#228B22,stroke-width:2px
    style J fill:#E6FFE6,stroke:#228B22,stroke-width:2px
    style K fill:#E6FFE6,stroke:#006400,stroke-width:2px
```

---

### **3️⃣ 推荐告警指标与阈值配置表格**

| **指标名**                             | **建议阈值**                       | **告警等级** | **含义说明**             |
| -------------------------------------- | ---------------------------------- | ------------ | ------------------------ |
| unacked_messages_by_region             | ≥ 500 持续 5 分钟                  | 高           | 消费端积压               |
| oldest_unacked_message_age             | ≥ 60 秒                            | 高           | ack 过慢导致重试延迟     |
| ack_message_count / send_message_count | < 60% 比例维持 5 分钟              | 中           | ack 成功率下降           |
| GKE Pod CPU 使用率                     | < 40% 持续 10 分钟（但堆积在增长） | 提醒         | 可能过限流或客户端未扩容 |

---


