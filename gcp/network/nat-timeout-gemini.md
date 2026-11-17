# Cloud NAT TCP TIME_WAIT Timeout 变更架构评估 (Gemini)

> **背景**：内部邮件通知，针对新建的 Cloud NAT gateway，默认的 TCP TIME_WAIT timeout 将从 120 秒缩减为 30 秒。
> **场景**：User Runtime Egress（大量内部工作负载、运行时代买通过 NAT 访问外部服务）。
> **目标**：从架构、可用性、并发容量和网络稳定性角度，深度评估此次变更对现有 User Runtime 业务的影响。

---

## 1. Goal and Constraints（目标与约束）

- **核心场景特点**：User Runtime 的出网（Egress）通常具有**高频、短连接、突发性强（Bursty）**的特点。可能涉及调用第三方 API、Webhooks、下载依赖、抓取网页等。在使用短连接时，连接结束后产生大量的 TIME_WAIT 状态是不可避免的。
- **约束边界**：
  - 此变更仅针对**新创建的 (new)** Cloud NAT Gateway，现有网关的默认配置不受影响（但建议主动对齐或进行验证）。
  - 该变更只涉及 `TCP TIME_WAIT` 状态超时，不影响 UDP 协议，也不涉及 `TCP Established`（连接中） 或 `TCP Transitory`（半开）的空闲超时。

---

## 2. Recommended Architecture Evaluation（架构级影响面评估）

### 2.1 核心机制：TIME_WAIT 在 NAT 中的作用
当 TCP 连接正常关闭（双向 FIN 交互完成）后，发送最后一条 ACK 的一方会将连接放入 TIME_WAIT 状态。
在 Cloud NAT 层面，在此冷却期内，**该源 IP 和源端口的五元组组合（Source IP, Source Port, Dest IP, Dest Port, Protocol）会被锁定，不被分配给新的连接**。其初衷是为了防止网络中迷途（延迟串扰）的旧连接数据包，错误地发送到刚好复用了这个端口的新连接中。

### 2.2 核心评估：最大影响是什么？（The Biggest Impact）

> **架构定性结论：这是一次“用安全性冗余换取吞吐和并发上限”的重要优化。对 User Runtime Egress 而言，总体是个【巨大利好】，但对于弱网环境可能产生极低概率的【连接串扰（RST）边缘风险】。**

#### 🟢 最大收益：显著降低端口耗尽风险，提升 Egress 并发上限
- **120s 时代**：短连接一旦关闭，其占用的 NAT 端口会被锁定整整 **2分钟**。若 Runtime 产生极高的爆发调用，VM极易耗尽分配到的端口范围（也就是你之前在文档 `nat.md` 中排查的 `allocation_status: DROPPED` 问题）。
- **30s 时代**：端口释放与回收速度提升了 **4 倍**。这意味着，在 NAT IP 数量和 `min-ports-per-vm` 配置保持不变的情况下，网关可以支撑比原来高得多（理论最高 4 倍）的短连接新建速率（Connection Rate）。

#### 🔴 最大风险：边缘的 Connection Reset (RST) 重置升高
- 如果调用的第三方目标服务器响应极其缓慢，或者存在严重的网络丢包与拥堵（导致前面的旧包延迟到 30 秒后才抵达），恰好此时 NAT 已经复用了这个端口和目标地址建连。目标服务器或客户端收到错乱包时，大概率会触发 `RST` 连接重置。
- **风险减缓**：当今调用绝大多数为 HTTPS(TLS)。即便发生由于串扰导致的数据乱入，TLS 内部的 MAC 及证书校验也会由于解密失败而直接废弃脏数据包，只要客户端具有常见的（例如 1-2 次）重试机制，此边缘风险的业务体感几乎为 0。

---

## 3. Trade-offs and Alternatives（权衡与备选方案）

| 对比维度 | 120s TIME_WAIT（旧默认机制） | 30s TIME_WAIT（新机制） |
| --- | --- | --- |
| **NAT 端口回收与复用效率** | 极低（滞留两分钟） | **极高（快 4 倍释放）** |
| **应对爆发型短连接能力** | 较弱（频繁触发 Dynamic分配甚至 DROPPED） | **极强（天然契合 Runtime Egress）** |
| **对极端弱网重传包的防御度** | 极强（120秒可消化绝大多数网络中的游离包） | **中等（极小概率在 30s 后产生端口串扰）** |

**架构决策权衡**：
对于现代 API 调用和微服务生态，获取**成倍的端口复用能力与并发容量，远比维持 120s 的极端游离包防御有价值。这相当于彻底从底层帮你解决了 `min-ports-per-vm` 不够用的通病。** 

---

## 4. Implementation Steps（实施与配置步骤）

你可以不被动等待新建，而是通过以下命令在当前（非高峰期的）网关中主动实施并验证此影响：

### Step 1: 检查现在的 NAT 配置和指标
```bash
# 获取当前 NAT 的超时配置和端口分配情况，注意如果没显示，说明在沿用旧默认 (120s)
gcloud compute routers nats describe <YOUR_NAT_NAME> \
  --router=<YOUR_ROUTER_NAME> \
  --region=<REGION> \
  --format="yaml(name,tcpTimeWaitTimeoutSec,minPortsPerVm,enableDynamicPortAllocation)"
```

### Step 2: 结合过往工单（历史 DROPPED）主动分析
去翻阅由于 `allocation_status: DROPPED` 导致的出网失败告警发生时的场景：
- 如果多数发生于 Runtime 突增流量、大批量压测，或某个服务瞬发海量连接——这一改动能直接缓解甚至消灭这个问题。

### Step 3: 更新为新的 Baseline
如果是现有网关，你可以逐步更新应用新标准：
```bash
gcloud compute routers nats update <YOUR_NAT_NAME> \
  --router=<YOUR_ROUTER_NAME> \
  --region=<REGION> \
  --tcp-time-wait-timeout=30s
```

---

## 5. Validation and Rollback（验证与回滚）

### 5.1 需要监控的验证指标 (Metrics to Monitor)
1. **`compute.googleapis.com/nat/port_usage`（分配的端口使用量）**
   - **预期**：在同等的并发模型下，波峰变得显著更平缓，不再有长达数分钟的高点滞留（因为旧端口 30 秒就清理掉了）。
2. **`compute.googleapis.com/nat/allocated_ports` 与 `nat_allocation_failed`**
   - **预期**：如果你开启了动态端口分配，你会发现触发动态增容的频率将直线降低。DROPPED 会显著减少。
3. **VM 层面的网络和应用错误率**
   - **潜在问题观测**：留意应用侧是否有轻微增加的 `Connection Reset by Peer`，或者 SDK 和 HTTP 客户端层的重试次数是否有突增。

### 5.2 安全与回滚方案
如果在极少数依赖不稳定第三方网络的场景发现长连接干扰或频繁握手故障，可使用以下命令秒级回滚：
```bash
gcloud compute routers nats update <YOUR_NAT_NAME> \
  --router=<YOUR_ROUTER_NAME> \
  --region=<REGION> \
  --tcp-time-wait-timeout=120s
```

---

## 6. Reliability and Cost Optimizations（演进与成本优化建议）

- **网络可靠性 (Reliability)**：此优化本质上消除了 75% 的端口锁定浪费，User Runtime 在遭受高频调度或突发任务时的整体 Egress 可靠性大幅度提升。
- **成本优化 (Cost Optimization)**：
  - 过去为了缓解 120s 造成的虚假“端口瓶颈”，可能被迫增加了多个外网 IP 供 NAT 轮询，或者配置了极大的 `min-ports-per-vm`。
  - 在调整为 30s 且平稳运行一周后，您可以重新审视 NAT 的公网 IP 数量。**极大概率可以释放部分冗余 NAT IP 并缩小单 VM 保留端口数量，从而直接降低网络侧的闲置和固定使用成本。**
- **应用侧最佳实践**：
  - 治标还需治本：NAT 层的优化固然好，但在 User Runtime 的代码和中间件规范中，仍要**强制约束开发者开启并合理配置连接池（Connection Pool）和 Keep-Alive**，将重复的“短连接”变为可复用的“长会话”，这是提高运行时通信性能的终极解法。

---

## 7. Handoff Checklist（交接与执行清单）

- [ ] 审阅邮件确认上下文：变更仅对“New Cloud NAT”有效，确认是否有计划通过 Terraform/gcloud 主动统一存量 NAT 的超时为 30s，保证环境配置一致性。
- [ ] 复查此前发生过端口枯竭（DROPPED）的 VM 池子，推演 30s 状态下是否能完全缓解，如果是，可更新对应架构和 SRE playbook 指导文档。
- [ ] 建立或刷新包含 `nat/port_usage` 和 HTTP `502/RST` 的观测面板，明确 SRE 关注点：出现类似现象时，不急于怪罪超时缩短，应优先查实第三方对端情况或提升自身客户端重试策略的能力。
- [ ] 根据后续验证数据，启动 NAT 成本梳理优化项，削减无用 IP 储备。

*文档输出日期：2026-04-08，基于 GCP 当期网络变更行为模式发布*
