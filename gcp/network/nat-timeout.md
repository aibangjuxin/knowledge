# Cloud NAT TCP TIME_WAIT 从 120s 到 30s 的影响评估

> 背景邮件：`We changing the default TCP time_wait from 120 seconds to 30 seconds for new Cloud NAT gateway.`

> 目标：从架构角度评估这项变化对 Google Cloud 上 user runtime egress 的真实影响，重点判断风险点、收益点、验证方式和建议动作。

---

## 1. Goal And Constraints

### 1.1 当前背景

你们运行在 Google Cloud 上，内部工作负载通过 `Cloud NAT` 做 egress 出网。

目前最主要的使用场景是：

- user runtime egress
- 大量到外部系统的主动出站连接
- 很可能包含大量短连接 HTTP/HTTPS 请求
- 也可能包含 SDK、Webhook、第三方 API、镜像拉取、依赖下载等混合流量

### 1.2 这次变更的对象是什么

邮件描述的是：

`新建 Cloud NAT gateway 的默认 TCP TIME_WAIT timeout 从 120 秒调整为 30 秒`

注意这里有三个限定词：

1. `default`
2. `TCP TIME_WAIT`
3. `for new Cloud NAT gateway`

这意味着最需要确认的是：

- 是不是仅影响“新建 NAT”
- 现有 NAT 是否保持旧配置不变
- 只有“未显式配置 timeout”的 NAT 才受影响

### 1.3 Google 官方资料中目前能确认的事实

截至 2026-04-08，我查到的 Google 官方资料存在两类信号：

1. Cloud NAT 调优文档仍写：
   `TCP TIME_WAIT Timeout` 默认值是 `120 seconds`，并明确说明缩短该值会更快复用 NAT 端口，但可能让无关重传包命中新连接。[Source: Google Cloud NAT tune configuration](https://cloud.google.com/nat/docs/tune-nat-configuration)
2. Compute Engine API / client references 中，`tcpTimeWaitTimeoutSec` 出现了“`Defaults to 30s if not set`”的描述。[Source: Compute Engine REST beta routers docs](https://cloud.google.com/compute/docs/reference/rest/beta/routers), [Python/.NET client refs](https://cloud.google.com/python/docs/reference/compute/latest/google.cloud.compute_v1.types.RouterNat)

从架构角度，这更像是：

`控制面默认值正在从旧默认 120 秒迁移到新默认 30 秒，但产品文档还没有完全统一。`

### 1.4 复杂度评级

`Moderate`

原因：

- 变更点单一，只涉及一个 timeout
- 但影响面不小，因为它直接影响 NAT 端口复用和高并发 egress
- 对短连接密集型 workload 可能是收益
- 对异常网络、重传较多、连接模式不健康的 workload 可能引入边缘问题

---

## 2. Recommended Architecture (V1)

### 2.1 先说结论

对你们这种以 user runtime egress 为主的场景，这个改动最大的架构影响通常不是“连接会更快断”，而是：

`NAT 端口会更快回收和复用，从而改变出网容量模型与边缘重传风险的平衡点。`

### 2.2 最可能的直接收益

如果 runtime egress 以大量短连接为主，那么把 `TIME_WAIT` 从 120 秒降到 30 秒，最可能带来的正面效果是：

- NAT source port 更快可复用
- 相同 NAT IP 下可承载更高的新建连接速率
- 更不容易因为 TIME_WAIT 积压导致端口耗尽
- 对 bursty egress 流量更友好

### 2.3 最可能的直接风险

Google 官方文档明确指出：

- `TCP TIME_WAIT Timeout` 用于在连接关闭后保留 Cloud NAT mapping
- 这个机制的作用是保护内部 endpoint，避免收到属于旧连接的重传包
- 减小 timeout 可以提升端口复用速度，但代价是“可能收到与先前已关闭连接无关的重传包”[Source: Google Cloud NAT tune configuration](https://cloud.google.com/nat/docs/tune-nat-configuration)

所以这次改动最大的风险不是“性能变差”，而是：

`在端口更快复用的前提下，旧连接残留重传包更容易和新连接时序重叠。`

### 2.4 对你们场景的架构判断

如果你们的 user runtime egress 具有这些特点：

- 到同一批外部 API endpoint 高频短连接
- 每个 node / pod 出网并发高
- 某些第三方响应慢或网络 jitter 大
- 某些客户端库频繁建连，不复用连接池

那么这个变更对你们最可能的影响排序是：

1. `正向`: NAT 端口复用速度更快，缓解端口压力
2. `中性`: 正常 keepalive / connection pool 场景几乎无感
3. `负向边缘`: 在异常网络或不健康连接模式下，更容易暴露旧包重传、RST、偶发建连异常

---

## 3. Trade-offs And Alternatives

### 3.1 TIME_WAIT 变短，究竟换来了什么

Cloud NAT 的一个五元组不能在 `TCP TIME_WAIT timeout` 内被复用。[Source: Cloud NAT troubleshooting](https://cloud.google.com/nat/docs/troubleshooting)

所以从 120 秒到 30 秒，本质上是在做这个交换：

| 维度 | 120s | 30s |
| --- | --- | --- |
| 旧连接映射保留时间 | 更长 | 更短 |
| NAT 端口复用速度 | 更慢 | 更快 |
| 抗旧包重传保护 | 更强 | 更弱 |
| 高新建连接速率承载能力 | 更低 | 更高 |

### 3.2 对 user runtime egress 的最大影响是什么

如果只说一个最大的影响，我会这样表述：

`同样的 NAT IP 池，在短连接密集场景下，理论上可以承受更高的新连接创建速率，但代价是异常网络下的连接隔离窗口变短。`

这是最需要团队理解的点。

### 3.3 哪类 workload 最容易受影响

#### 更可能受益的 workload

- 高频短连接 HTTP/HTTPS
- 对同一第三方 endpoint 大量并发调用
- 端口消耗高、连接寿命短
- 曾经接近 NAT 端口耗尽或出现 `OUT_OF_RESOURCES`

#### 更可能暴露边缘问题的 workload

- 网络质量差、丢包或重传明显
- 频繁对同一 destination 3-tuple 快速重连
- 应用侧没有良好重试、超时和连接池
- 对 TCP reset / sporadic handshake failure 很敏感

### 3.4 什么不是最大风险

以下通常不是这次变更的主要风险：

- 长连接 idle 被更快清掉
- 已建立 TCP 连接整体超时策略改变
- UDP 行为改变

原因：

- 这次变更只针对 `TCP TIME_WAIT`
- 它不等于 `TCP Established Idle Timeout`
- Cloud NAT 默认 established timeout 仍是 20 分钟，transitory timeout 仍是 30 秒。[Source: Google Cloud NAT tune configuration](https://cloud.google.com/nat/docs/tune-nat-configuration)

---

## 4. Implementation Steps

### 4.1 先确认你们当前 NAT 实际值

不要先假设一定是 120 或 30，先查当前实际配置：

```bash
gcloud compute routers nats describe NAT_NAME \
  --router=ROUTER_NAME \
  --region=REGION \
  --format="yaml(name,tcpTimeWaitTimeoutSec,tcpEstablishedIdleTimeoutSec,tcpTransitoryIdleTimeoutSec,udpIdleTimeoutSec,enableDynamicPortAllocation,minPortsPerVm,maxPortsPerVm)"
```

如果 `tcpTimeWaitTimeoutSec` 没显式出现在配置里，就要警惕：

- 老网关可能仍然跑旧默认
- 新网关可能采用新默认

### 4.2 建议的第一步动作

建议先做 inventory：

| 检查项 | 目的 |
| --- | --- |
| 哪些 NAT 是老网关 | 判断是否受新默认影响 |
| 哪些 NAT 显式设置了 `tcpTimeWaitTimeoutSec` | 判断是否会被默认值变化波及 |
| 哪些 NAT 承载 user runtime egress | 确定评估重点 |
| 哪些 NAT 已启用 dynamic port allocation | 判断端口弹性空间 |
| 当前 NAT IP 数量和 `min-ports-per-vm` | 判断端口压力基线 |

### 4.3 架构上最该评估的指标

如果你要评估这次变更值不值得担心，优先看这些：

| 指标/信号 | 说明 |
| --- | --- |
| `compute.googleapis.com/nat/port_usage` | 看 NAT 端口压力 |
| `nat_allocation_failed` | 看是否有 IP/port tuple 不足 |
| `dropped_sent_packets_count` with `OUT_OF_RESOURCES` | 看端口耗尽丢包 |
| 应用侧 5xx / connect timeout / handshake error | 看业务影响 |
| 到固定第三方 endpoint 的连接错误率 | 看是否存在重连敏感场景 |

### 4.4 对 user runtime egress 的重点分析方法

建议把 egress 流量按四类拆开：

#### 类型 A：高频短连接 HTTP 调用

最可能受益于 30 秒 TIME_WAIT。

#### 类型 B：连接池健康的 HTTP client

通常几乎无感，因为连接复用好，本来就不频繁进入 TIME_WAIT。

#### 类型 C：异常网络或第三方慢响应

更值得观察 sporadic reset / retry spike。

#### 类型 D：极高并发、固定目标三元组

既可能受益于更快端口复用，也更可能暴露旧包与新连接时序问题。

### 4.5 如果你们历史上碰到过这些问题，要特别关注

如果你们以前有：

- NAT allocation dropped
- `OUT_OF_RESOURCES`
- 高频 burst 时出网失败
- 单个 node / pod 对外并发极高

那这次变化反而可能是利好。

如果你们以前更常见的是：

- 少量但诡异的 TCP reset
- 偶发第三方握手异常
- 网络质量不稳定时 sporadic failure

那就要更谨慎。

---

## 5. Validation And Rollback

### 5.1 验证策略

不要只看 NAT 配置本身，要做“配置 + 指标 + 应用”的三层验证。

#### 配置层

```bash
gcloud compute routers nats describe NAT_NAME \
  --router=ROUTER_NAME \
  --region=REGION
```

确认：

- `tcpTimeWaitTimeoutSec`
- `minPortsPerVm`
- `maxPortsPerVm`
- `enableDynamicPortAllocation`

#### 指标层

重点观察：

- `nat/port_usage`
- `nat_allocation_failed`
- dropped sent packets

#### 应用层

重点观察 runtime egress：

- connect timeout
- TLS handshake error
- connection reset
- 上游 502/504 或 SDK retry spike

### 5.2 灰度验证建议

如果你们能控制 NAT 新建节奏，建议：

1. 先选一组低风险 runtime subnet / region 做新 NAT
2. 仅迁移一部分 egress workload
3. 观察 3 到 7 天
4. 对比旧 NAT 与新 NAT 在端口使用率和错误率上的差异

### 5.3 回滚策略

如果确认 30 秒带来问题，回滚非常直接：

```bash
gcloud compute routers nats update NAT_NAME \
  --router=ROUTER_NAME \
  --region=REGION \
  --tcp-time-wait-timeout=120
```

注意：

- 如果你们已经依赖了 30 秒带来的更高端口复用，回到 120 秒后端口压力会重新上升
- 回滚 timeout 前，先确认 NAT IP 容量和端口余量是否足够

---

## 6. Reliability And Cost Optimizations

### 6.1 对你们最现实的建议

#### 建议 1：不要把它当成纯风险公告

对 user runtime egress 来说，这更像是：

`容量与隔离保护窗口之间的重新平衡`

而不是单向坏消息。

#### 建议 2：优先修应用连接模式，而不是先怪 NAT

如果 runtime egress 还在：

- 不复用连接池
- 每个请求都新建 TCP/TLS
- 重试策略粗暴

那 NAT timeout 变化只是把原本隐藏的问题更早暴露出来。

#### 建议 3：把 NAT timeout 和端口模型一起看

单看 `TIME_WAIT` 没意义，至少要一起看：

- NAT IP 数量
- `min-ports-per-vm`
- dynamic port allocation
- 真实连接创建速率

### 6.2 对成本和容量的架构影响

如果 30 秒默认值生效，通常会带来两个方向的变化：

#### 正向

- 相同 NAT IP 池可能承载更多短连接 egress
- 某些场景下减少为缓解端口压力而额外扩 NAT IP 的需求

#### 负向边缘

- 需要更严格监控 connection reset / retry
- 对异常流量模型更敏感

### 6.3 我对这次变更的总体判断

对于“user runtime egress 为主”的平台，最大的影响通常不是 availability 级灾难，而是：

`它会改变 NAT 端口复用的节奏，因此更容易让流量模型健康与否变得可见。`

如果你们工作负载本来就是：

- 短连接多
- 端口压力高
- 连接池不够好

那这次变更既可能帮你缓解端口瓶颈，也可能让边缘连接问题更早暴露。

---

## 7. Handoff Checklist

### 7.1 先确认的事实

- 邮件是否明确“只影响新建 NAT”
- 现有 NAT 是否显式配置了 `tcpTimeWaitTimeoutSec`
- 哪些 NAT 承载 user runtime egress
- 当前 `nat/port_usage` 是否高

### 7.2 优先评估的问题

- 你们是更接近“端口压力型”问题，还是“网络抖动型”问题
- 你们的 runtime client 是否普遍复用连接池
- 是否存在大量对同一第三方 endpoint 的高频重连

### 7.3 我给你的最终建议

如果只保留一句架构判断，我会这样写：

`Cloud NAT TCP TIME_WAIT 从 120s 降到 30s，最大的影响不是连接超时，而是 NAT 端口会更快复用；对短连接密集的 runtime egress 往往是利好，但会缩短对旧连接重传包的隔离窗口，因此要重点监控 sporadic reset、握手失败和端口使用率。`

### 7.4 推荐参考

- [Tune NAT configuration](https://cloud.google.com/nat/docs/tune-nat-configuration)
- [Cloud NAT troubleshooting](https://cloud.google.com/nat/docs/troubleshooting)
- [Ports and addresses](https://cloud.google.com/nat/docs/ports-and-addresses)
- [Compute Engine routers beta reference](https://cloud.google.com/compute/docs/reference/rest/beta/routers)
