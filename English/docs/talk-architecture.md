# Architecture Talk Guide - English & Chinese对照

## Table of Contents
- [Meeting Opening & Introducing Architecture](#meeting-opening--introducing-architecture)
- [Core Components Explanation](#core-components-explanation)
- [Scaling & High Availability](#scaling--high-availability)
- [Diagram Navigation & Interaction](#diagram-navigation--interaction)
- [Request Flow & Data Flow](#request-flow--data-flow)
- [Network Issues & Troubleshooting](#network-issues--troubleshooting)
- [Common Meeting Scenarios](#common-meeting-scenarios)
- [Q&A Session Phrases](#qa-session-phrases)
- [Quick Reference Template](#quick-reference-template)

---

## Meeting Opening & Introducing Architecture

### Standard Opening Phrases

| English | Chinese |
|---------|---------|
| Let me walk you through our system architecture. | 我先带大家过一遍我们的系统架构。 |
| I'll start with a high-level overview. | 我先从整体架构讲起。 |
| This diagram shows the end-to-end request flow. | 这张图展示的是端到端请求链路。 |
| I'll explain this step by step. | 我会一步一步说明。 |
| Let me give you a quick overview of our architecture. | 我先快速介绍一下整体架构。 |
| I'll use this diagram to explain how everything fits together. | 我会结合这张图来说明各个组件如何协作。 |

### Sample Dialogue

**You:** Let me walk you through our system architecture. I'll start with a high-level overview.

**中文:** 我先带大家过一遍我们的系统架构，从整体开始讲。

---

## Core Components Explanation

### Standard Architecture Description Patterns

| English | Chinese |
|---------|---------|
| The system is built on a microservices architecture. | 系统采用微服务架构。 |
| We use Kubernetes for container orchestration. | 我们使用 Kubernetes 做容器编排。 |
| PostgreSQL is used for relational data, while MongoDB handles unstructured data. | PostgreSQL 用于结构化数据，MongoDB 用于非结构化数据。 |
| Our services communicate via REST APIs and message queues. | 我们的微服务通过 REST API 和消息队列通信。 |
| We leverage cloud-native technologies for scalability. | 我们利用云原生技术实现可扩展性。 |
| The frontend connects to backend services through API gateways. | 前端通过 API 网关连接后端服务。 |

### Complete Component Description

**English:**
The core modules follow a microservices pattern. We run everything on Kubernetes for orchestration. For data storage, we use PostgreSQL for relational data and MongoDB for unstructured or flexible schemas. Our services communicate via REST APIs and message queues, and we leverage cloud-native technologies for scalability.

**中文:**
核心模块采用微服务模式，整体运行在 Kubernetes 上进行编排。数据层面，关系型数据使用 PostgreSQL，非结构化或灵活 Schema 使用 MongoDB。我们的微服务通过 REST API 和消息队列通信，并利用云原生技术实现可扩展性。

---

## Scaling & High Availability

### Auto-Scaling Descriptions

| English | Chinese |
|---------|---------|
| We have auto-scaling rules based on CPU and memory usage. | 我们基于 CPU 和内存配置了自动扩缩容。 |
| Scale out when CPU reaches 70%. | CPU 达到 70% 时扩容。 |
| Scale in when usage drops below 30%. | 低于 30% 时缩容。 |
| Minimum replicas is 3. | 最小副本数是 3。 |
| We cap the maximum at 10 pods. | 最大限制为 10 个 Pod。 |
| Memory usage over 80% for five minutes also triggers scaling. | 如果内存使用率连续 5 分钟超过 80%，也会触发扩容。 |

### Complete Scaling Explanation

**English:**
We use HPA for auto-scaling. When CPU usage hits 70%, we scale out by two pods. If it drops below 30%, we scale in by one. Memory usage over 80% for five minutes also triggers scaling. The minimum is three pods, and we can manually scale up to ten during peak events.

**中文:**
我们使用 HPA 做自动扩缩容。CPU 达到 70% 时扩容两个 Pod，低于 30% 时缩容一个。如果内存使用率连续 5 分钟超过 80%，也会触发扩容。最小是 3 个 Pod，高峰期可以手动扩到 10 个。

---

## Diagram Navigation & Interaction

### Zoom Operations

| English | Chinese |
|---------|---------|
| Let's zoom in on this part. | 我们放大看这一块。 |
| Zoom out to see the full flow. | 缩小看整体流程。 |
| Focus on the GKE Gateway here. | 看一下这里的 GKE Gateway。 |
| This part handles traffic routing. | 这部分负责流量路由。 |
| Can we zoom in on the database layer? | 我们能放大看看数据库层吗？ |
| Let's zoom out to see the entire system. | 让我们缩小看看整个系统。 |

### Moving Elements and Arrows

| English | Chinese |
|---------|---------|
| Can we move the "role" component to the top? | 我们能把 "role" 这个组件移到上面吗？ |
| Let's bring this element to the front for clarity. | 为了更清楚，我们把这个元素放到最前面。 |
| Move the 'authentication service' to the left side. | 把 '认证服务' 移到左边。 |
| Bring the 'database' to the back. | 把 '数据库' 放到后面。 |
| Point the arrow toward the load balancer. | 让箭头指向负载均衡器。 |
| Draw an arrow from the API gateway to the user service. | 从 API 网关画一条箭头到用户服务。 |
| Adjust the arrow to show the data flow direction. | 调整箭头显示数据流向。 |
| Highlight the connection between these two components. | 突出这两个组件之间的连接。 |
| Rotate the component 90 degrees clockwise. | 将组件顺时针旋转 90 度。 |
| Align the services horizontally. | 将服务水平对齐。 |

### Sample Diagram Interaction Dialogue

**Colleague:** Can you explain this part?

**You:** Sure. Let's zoom in on the GKE Gateway. This is where we apply routing and priority rules.

**中文:**
同事：能解释一下这部分吗？
你：当然。我们放大看一下 GKE Gateway。这里主要做路由和优先级控制。

---

## Request Flow & Data Flow

### Common Flow Descriptions

| English | Chinese |
|---------|---------|
| Requests come in through the load balancer. | 请求先进入负载均衡。 |
| Traffic is forwarded to the gateway layer. | 流量被转发到网关层。 |
| Then it reaches the backend services. | 接着到后端服务。 |
| Responses follow the same path back. | 响应沿相同路径返回。 |
| The request first hits the HTTPS load balancer. | 请求首先到达 HTTPS 负载均衡器。 |
| Authentication happens before authorization. | 认证发生在授权之前。 |
| Data flows from the client to the API gateway. | 数据从客户端流向 API 网关。 |

### Complete Flow Example

**English:**
The request first hits the HTTPS load balancer, then goes through the gateway, and finally reaches the backend services running in GKE. After processing, the response follows the same path back to the client.

**中文:**
请求首先到达 HTTPS 负载均衡器，然后经过网关，最后到达在 GKE 中运行的后端服务。处理完成后，响应沿相同路径返回给客户端。

---

## Network Issues & Troubleshooting

### Common Network Problem Expressions

| English | Chinese |
|---------|---------|
| Sorry, the network is lagging. | 不好意思，网络有点卡。 |
| I didn't catch that. | 我没听清。 |
| Could you repeat that? | 能再说一遍吗？ |
| Could you repeat your question about the architecture? | 能再重复一下你刚刚关于架构的问题吗？ |
| You were breaking up a bit. | 刚刚你那边有点断断续续。 |
| Let me make sure I understood you correctly. | 我确认一下我是否理解正确。 |
| The connection seems unstable. | 连接似乎不太稳定。 |
| I'm experiencing some audio delay. | 我这边有些音频延迟。 |
| Can you hear me clearly? | 你能清楚地听到我说话吗？ |
| My screen is freezing. | 我的屏幕卡住了。 |
| The video feed is choppy. | 视频画面断断续续。 |

### Troubleshooting Phrases

| English | Chinese |
|---------|---------|
| Let me reconnect to the meeting. | 让我重新连接会议。 |
| I'll share my screen again. | 我重新分享屏幕。 |
| Can you see my screen now? | 你现在能看到我的屏幕吗？ |
| The presentation isn't loading properly. | 演示文稿没有正常加载。 |
| I need to refresh the diagram. | 我需要刷新图表。 |
| Let's switch to audio-only mode. | 让我们切换到仅音频模式。 |

---

## Common Meeting Scenarios

### Scenario 1: Explaining System Bottleneck

**English:**
We've identified a bottleneck in the authentication service during peak hours. The current setup handles about 1000 requests per second, but during peak times we see up to 1500 requests. We're considering implementing caching strategies and optimizing database queries to address this.

**中文:**
我们在高峰时段发现了认证服务的瓶颈。当前设置每秒处理约 1000 个请求，但在高峰时段我们看到最多 1500 个请求。我们正在考虑实施缓存策略并优化数据库查询来解决这个问题。

### Scenario 2: Discussing Migration Strategy

**English:**
Our migration strategy involves a phased approach. First, we'll migrate non-critical services to validate our deployment pipeline. Then we'll gradually move customer-facing services with minimal downtime using blue-green deployments. Finally, we'll handle the legacy data migration with proper backup and rollback procedures.

**中文:**
我们的迁移策略采用分阶段方法。首先，我们将迁移非关键服务以验证我们的部署管道。然后我们将在使用蓝绿部署的情况下逐步迁移面向客户的服 务，以实现最小停机时间。最后，我们将通过适当的备份和回滚程序处理遗留数据迁移。

### Scenario 3: Handling Security Concerns

**English:**
Security is a top priority in our architecture. We implement mTLS for service-to-service communication, enforce RBAC for access control, and regularly scan for vulnerabilities. Additionally, we encrypt data both in transit and at rest, and maintain audit logs for compliance purposes.

**中文:**
安全性是我们架构中的首要任务。我们实施 mTLS 用于服务间通信，强制执行 RBAC 进行访问控制，并定期扫描漏洞。此外，我们对传输中和静态的数据进行加密，并维护审计日志以满足合规要求。

---

## Q&A Session Phrases

### Asking Questions

| English | Chinese |
|---------|---------|
| Can you elaborate on the database sharding strategy? | 能详细说明一下数据库分片策略吗？ |
| What's the failover mechanism in case of a region outage? | 如果某个区域发生故障，故障转移机制是什么？ |
| How do you handle data consistency across services? | 你们如何处理跨服务的数据一致性？ |
| What monitoring and alerting systems are in place? | 有哪些监控和告警系统？ |
| Could you explain the disaster recovery plan? | 能解释一下灾难恢复计划吗？ |

### Answering Questions

| English | Chinese |
|---------|---------|
| That's a great question. | 这是个很好的问题。 |
| Let me explain how that works. | 让我解释一下它是如何工作的。 |
| The reason we chose this approach is... | 我们选择这种方法的原因是... |
| We considered several alternatives before deciding on this solution. | 在决定这个解决方案之前，我们考虑了几种替代方案。 |
| In practice, this has worked well for us because... | 实际上，这对我们很有效，因为... |
| We're still evaluating this aspect of the architecture. | 我们仍在评估架构的这一方面。 |

---

## Quick Reference Template

Here's a complete template you can use for architecture presentations:

**English:**
Let me walk you through our system architecture. I'll start with a high-level overview.

The system is built on a microservices architecture and runs on Kubernetes. Requests come in through the load balancer, go through the gateway, and finally reach the backend services.

We use HPA for auto-scaling based on CPU and memory. Let's zoom in on this part to see the gateway configuration.

For data storage, we use PostgreSQL for relational data and MongoDB for unstructured data. The authentication service handles user validation before requests reach the business logic layer.

During peak hours, we scale out automatically when CPU usage hits 70%. Memory usage over 80% for five minutes also triggers scaling.

Sorry, the network is lagging—could you repeat that? Happy to answer any questions.

**中文:**
我先带大家过一遍我们的系统架构，从整体开始讲。

系统采用微服务架构，运行在 Kubernetes 上。请求通过负载均衡器进入，经过网关，最后到达后端服务。

我们使用 HPA 基于 CPU 和内存进行自动扩缩容。让我们放大看看这部分的网关配置。

对于数据存储，我们使用 PostgreSQL 存储关系型数据，MongoDB 存储非结构化数据。认证服务在请求到达业务逻辑层之前处理用户验证。

在高峰时段，当 CPU 使用率达到 70% 时，我们会自动扩容。如果内存使用率连续 5 分钟超过 80%，也会触发扩容。

不好意思，网络有点卡——你能重复一下吗？很高兴回答任何问题。

---

## Additional Useful Phrases

### Time Management
| English | Chinese |
|---------|---------|
| Let's move on to the next section. | 让我们继续下一部分。 |
| We're running short on time. | 我们时间不多了。 |
| Can we circle back to this later? | 我们稍后再回到这一点好吗？ |
| Let's table this discussion for now. | 我们暂时搁置这个讨论。 |

### Agreement & Disagreement
| English | Chinese |
|---------|---------|
| I agree with your assessment. | 我同意你的评估。 |
| That aligns with our findings. | 这与我们的发现一致。 |
| I see your point, but... | 我明白你的观点，但是... |
| I respectfully disagree because... | 我恭敬地不同意，因为... |
| Let's explore this alternative approach. | 让我们探讨这种替代方法。 |

### Follow-up Actions
| English | Chinese |
|---------|---------|
| I'll send you the detailed specs after the meeting. | 会议结束后我会把详细规格发给你。 |
| Let's schedule a follow-up session to discuss this further. | 让我们安排后续会议进一步讨论。 |
| I'll create a POC to validate this idea. | 我将创建一个概念验证来验证这个想法。 |
| We should document this decision. | 我们应该记录这个决定。 |