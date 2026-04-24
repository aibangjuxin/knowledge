# PSC 跨 Region 连接：平台 Consumer 访问不同 Region 的 Producer

## 需求背景

我现在有这样一个问题，我们是一个平台，我们是作为一个 GCP 平台里边的 consumer。假如说我们在 region 是 Asia east2，也就是说亚洲区，那么我们要连用户的 produce 工程，是不是他的 produce 工程也必须和我们是在同一个 region，这样才能连上呢？

## 简单直接的回答

**不需要必须在同一个 Region，但必须正确配置两端（Producer + Consumer）的全局访问开关。**

---

## 一、PSC 连接规则

在 GCP 的 Private Service Connect (PSC) 架构中，Service Attachment（生产端）和 PSC Endpoint（消费端）都是**区域性资源 (Regional Resources)**。

### 1. 默认情况：同 Region 连接

按照标准操作，如果你在 `asia-east2` 创建消费端 Endpoint，它默认只能连接同在 `asia-east2` 的生产端 Service Attachment。

### 2. 跨 Region 连接的“钥匙”：双向 Global Access

如果你（Consumer）在 `asia-east2`，而用户的生产端（Producer）在另一个 Region（比如 `us-central1`），你们**可以**连通，但需要**两端同时开启 Global Access**：

#### Producer 端配置
```
Service Attachment 背后挂载的 ILB Forwarding Rule 必须配置 --allow-global-access
```
**作用**：允许来自其他 Region 的 Consumer 流量跨区域送达 Service Attachment。

#### Consumer 端配置
```
PSC Endpoint（Forwarding Rule）需要开启 --allow-psc-global-access
```
**作用**：开启后，虽然你的 Endpoint 静态 IP 绑定在 `asia-east2` 的子网，但 GCP 全球网络允许其他 Region 或本地（On-premises）的流量通过这个 Endpoint 路由到 Producer 端。

#### 两种 Global Access 的区别

| 开关                        | 层级                                        | 作用对象                                  |
| --------------------------- | ------------------------------------------- | ----------------------------------------- |
| `--allow-global-access`     | ILB Forwarding Rule（Producer 侧）          | 允许跨 Region 流量进入 Service Attachment |
| `--allow-psc-global-access` | PSC Endpoint Forwarding Rule（Consumer 侧） | 允许跨 Region VM 使用该 PSC Endpoint      |

> ⚠️ **容易混淆的点**：这两个 flag 名字很像，但作用于不同方向。跨 Region 场景**两端都需要开启**，缺一不可。

### 3. 跨 Region 流量的特殊限制

如果你是通过 **VPN/Interconnect** 从本地（On-premises）访问跨 Region 的 Producer，同样需要 Consumer 端开启 `--allow-psc-global-access`。

---

## 二、架构对比表

| 场景                                         | 是否支持 | 关键配置                                                                                           |
| -------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------- |
| Consumer 与 Producer 在同 Region             | ✅ 是     | 标准 PSC 配置即可                                                                                  |
| Consumer 与 Producer 跨 Region               | ✅ 是     | Producer ILB 开启 `--allow-global-access` **+** Consumer Endpoint 开启 `--allow-psc-global-access` |
| 通过 VPN/Interconnect 访问跨 Region Producer | ✅ 是     | Consumer Endpoint 开启 `--allow-psc-global-access`                                                 |
| VPC Peering 访问跨 Region Producer           | ❌ 否     | PSC 流量不支持跨 VPC Peering 传递（Transitive Peering 限制）                                       |

---

## 三、PSC 跨 Region 的已知限制

### 1. VPC Peering 不可传递

PSC **不支持**跨 VPC Peering 传递流量。即使 A↔B 和 B↔C 建立了 VPC Peering，A 也无法通过 B 访问 C 的 PSC Service Attachment。这是因为 PSC 使用独立的路由空间，不依赖 VPC Peering 的路由表。

### 2. Service Attachment 永远是 Regional

Service Attachment 是严格区域级的资源，不能是 Global。它的能力受限于底层 ILB 和 PSC NAT Subnet 的区域属性。

### 3. PSC NAT Subnet 端口耗尽风险

PSC 使用 SNAT 机制，Consumer 侧的真实源 IP 会被转换为 PSC NAT Subnet 的 IP 地址。如果你的平台有 100+ 租户，使用过小的 NAT Subnet（如 /29 仅 5 个可用 IP）会遇到端口耗尽。**建议**：PSC NAT Subnet 至少使用 /24（253 个可用 IP）。

### 4. 配额限制

| 资源                                 | 默认限制         | 说明                      |
| ------------------------------------ | ---------------- | ------------------------- |
| PSC Endpoints per region per project | 50               | 100+ 租户需要申请配额提升 |
| Service Attachments per region       | 50               | 可申请提升                |
| PSC ILB Consumer Forwarding Rules    | Per Producer VPC | 需要提 Support Ticket     |

---

## 四、成本考量

跨 Region PSC 流量会产生额外的数据传输费用：

| 费用项                              | 单价                   |
| ----------------------------------- | ---------------------- |
| PSC Endpoint（每小时）              | $0.01/endpoint/hour    |
| 数据处理费                          | $0.01/GiB              |
| **跨 Region 数据传输（Asia ↔ US）** | **$0.12/GiB**          |
| Producer 侧跨 Region 传出           | $0（由 Consumer 支付） |

> 💡 作为平台方，如果你的 Consumer 和 Producer 必然跨 Region，这个流量成本需要纳入考量。

---

## 五、总结建议

作为平台方（Consumer），如果你的用户（Producer）在不同 Region：

1. **优先推荐同地域部署**：跨地域流量会产生额外的 Cross-region Data Transfer 费用，且延迟（Latency）会增加。

2. **技术可行，但需要正确配置**：
   - **Producer 端**：确保用户的 ILB Forwarding Rule 开启了 `--allow-global-access`
   - **Consumer 端**：确保你的 PSC Endpoint 开启了 `--allow-psc-global-access`

3. **自动化 Onboarding 校验**：建议在流程中加入校验逻辑：
   - 检测 Producer 和 Consumer 区域是否一致
   - 如不一致，自动触发两端 Global Access 配置
   - 提示用户潜在的跨 Region 流量费用
   - 检查 PSC NAT Subnet 容量是否足够（建议 /24）

---

## 六、验证步骤

创建完跨 Region PSC 连接后，可通过以下方式验证：

```bash
# 1. 验证 Consumer Endpoint 配置
gcloud compute forwarding-rules describe <FWD_RULE_NAME> \
  --region=<CONSUMER_REGION> \
  --format="get(allowPscGlobalAccess)"

# 2. 验证 Producer Service Attachment 可达性
gcloud compute service-attachments describe <SERVICE_ATTACHMENT_NAME> \
  --region=<PRODUCER_REGION> \
  --format="get(enableProxyProtocol)"

# 3. 从 Consumer 侧 VM 测试连通性
curl -v --connect-timeout 5 https://<PSC_ENDPOINT_IP>:<PORT>
```

---

## 参考文档

- [PSC 概念详解](./psc-concept.md)
- [Service Attachment 与 Region 关系](./service-attachment-region.md)
- [PSC Consumer 连接配置](./psc-connect-consumer.md)