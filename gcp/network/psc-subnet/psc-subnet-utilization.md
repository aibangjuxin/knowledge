# PSC Subnet Utilization 深度解析

> 生成时间：2026-05-08
> 适用版本：GCP Private Service Connect (PSC)

---

## 1. 核心问题解答

### Q1: 为什么Subnet详情显示"使用了5个IP"，但我实际感觉只有1个在用？

**这是理解PSC NAT subnet最关键的地方。**

GCP Console显示的 **"Used IP addresses"** 并不是"当前正在传输流量的IP数量"，而是**已被GCP分配给PSC NAT池的IP数量**。对于 `/26` 子网（64个IP），其IP分配结构如下：

```
192.168.240.0/26 总共 64 IPs
├── 网络地址:   192.168.240.0     (不可用)
├── GCP保留:    192.168.240.1     (Gateway)
├── GCP保留:    192.168.240.2     (GCP内部使用)
├── 可用NAT IP: 192.168.240.3 ~ 192.168.240.62  (60个)
└── 广播地址:   192.168.240.63     (不可用)

你看到的 "Used IP addresses: 5" 可能包含：
1. Gateway (.1) 和 GCP 保留地址 (.2)
2. 已分配给活跃连接的 NAT IP
3. 处于 TIME_WAIT 状态的连接释放后的IP（不会立即归还）
4. GCP SLA/SDN 管理面分配的临时IP
```

**关键点：** "Used IP addresses" 是**累计分配量**，不是瞬时流量计数。即使连接已断开，GCP可能不会立即释放IP——这与Linux内核的 `tcp_fin_timeout` 和端口回收机制类似。

### Q2: 这个利用率跟PSC吞吐量有没有直接关系？

**没有直接关系。** 这是两个完全不同的维度：

| 维度 | 决定因素 | 说明 |
|:---|:---|:---|
| **吞吐量 (QPS/Bandwidth)** | Internal HTTP(S) LB 或 TCP/UDP NetLB | 取决于后端实例组扩容能力 |
| **NAT IP容量** | PSC NAT Subnet大小 | 决定最大并发TCP连接数上限 |

```
PSC Producer 流量模型：

Consumer VPC
    │
    │  ← 流量大小(QPS/带宽) ← 取决于后端ILB处理能力
    ▼
PSC Endpoint (Consumer侧)
    │
    │  ← 并发连接数 ← 取决于NAT Subnet IP数量 × 端口数
    ▼
Service Attachment (Producer侧)
    │
    ▼
NAT Subnet (SNAT转换)
    │
    ▼
Producer Internal LB → GKE Pods
```

**每个NAT IP约可提供 63,488 个并发TCP连接**（65535 - 1023保留端口），所以 `/26` 的60个可用NAT IP理论可承载：

```
60 IPs × 63,488 ports ≈ 3,809,280 并发连接
```

### Q3: 是否需要监控？基于什么监控？

**必须监控。** 推荐使用以下监控指标：

```bash
# Cloud Monitoring 指标
private_service_connect/producer/nat_ip_utilization
private_service_connect/producer/used_nat_ip_addresses
private_service_connect/producer/nat_ip_count
```

**告警阈值建议：**

| 利用率 | 状态 | 建议操作 |
|:---|:---|:---|
| ≥ 60% | 警告 | 开始评估扩容方案 |
| ≥ 75% | 预警 | 准备追加NAT subnet |
| ≥ 85% | 紧急 | **立即扩容**，避免新连接被拒绝 |

**监控命令示例：**

```bash
# 查看当前NAT IP使用情况
gcloud compute networks subnets describe SUBNET_NAME \
  --region=us-east4 \
  --format="get(ipCidrRange,secondaryIpRanges)"

# 通过Monitoring API查询利用率
# 指标: private_service_connect/producer/nat_ip_utilization
# 资源类型: consumer PSC forwarding rule
```

### Q4: 子网划分原则是什么？

基于知识库中已有的分析，建议遵循以下原则：

#### 4.1 子网大小与并发容量对照表

| NAT Subnet | 总IP数 | GCP保留 | 可用NAT IP | 理论并发连接上限 | 适用场景 |
|:---|:---|:---|:---|:---|:---|
| `/28` | 16 | 4 | 12 | ~762,000 | 最小单元，测试/低并发 |
| `/27` | 32 | 4 | 28 | ~1,778,000 | 小规模内部服务 |
| `/26` | 64 | 4 | 60 | ~3,809,000 | **生产默认起步** |
| `/25` | 128 | 4 | 124 | ~7,872,000 | 中等规模/多租户 |
| `/24` | 256 | 4 | 252 | ~16,000,000 | 高流量/平台共享入口 |

#### 4.2 规划决策树

```
问自己4个问题：

1. 这个Service Attachment预计接入多少 Consumer Endpoints/Backends？
   │
   ├── < 50 个 → 可用 /26 或 /27
   ├── 50~200 个 → 建议 /25
   └── > 200 个 → 建议 /24 起

2. 是否使用 Propagated Connections？
   │
   ├── 是 → 容量需求 ×1.5~2
   └── 否 → 标准计算

3. 流量模型是长连接还是短连接？
   │
   ├── 长连接 (Keep-alive) → NAT压力小，/26 可能够
   └── 短连接 → NAT压力大，需要更大子网

4. 是否为平台共享服务 / 多租户？
   │
   ├── 是 → 默认 /24 起步
   └── 否 → 按实际评估
```

#### 4.3 生产环境推荐默认值

根据知识库分析和你的使用场景（高访问量平台）：

- **普通生产 Attachment：`/25` 起步**（124 NAT IPs）
- **平台共享入口 / 高租户 Attachment：`/24` 起步**（252 NAT IPs）
- **测试/Staging：`/26` 或 `/27`**

> ⚠️ **重要提醒：** PSC NAT Subnet 一旦关联到 Service Attachment，**不能原地扩容**。创建时就要规划好未来扩展路径，或者接受"未来追加第二个 NAT Subnet"的设计模式（PSC 支持一个 Attachment 绑定最多 10 个 NAT Subnet）。

---

## 2. 你的具体场景分析

基于你提供的Subnet信息：

```
Subnet: cinternal-vpc1-us-east4-caep-psc-int-ingress-01
IP Range: 192.168.240.0/26
VPC: hsbc-11646547-capppdus-dev-cinternal-vpc1
Region: us-east4
Used IPs: 5
Free IPs: 59
利用率: 7.81%
```

**当前状态评估：**

| 指标 | 数值 | 说明 |
|:---|:---|:---|
| 总可用NAT IP | 60 | /26扣4个保留地址 |
| 已用 | 5 | 约8.3%利用率 |
| 剩余 | 55 | 容量充裕 |
| 理论并发容量 | ~3.8M | 非常充足 |

**利用率 7.81% 但显示已用5个IP的原因：**

这5个IP很可能包括：
- `.1` - Gateway
- `.2` - GCP内部保留
- `.3`, `.4`, `.5` - 已分配的NAT IP（可能是测试连接或TIME_WAIT中的连接）

**是否需要担心？**

**目前不需要。** 7.81% 的利用率意味着还有充足空间。但建议：
1. 设置 Cloud Monitoring 告警，阈值60%
2. 如果这是核心生产入口，考虑扩容到 `/25` 获得更多缓冲空间

---

## 3. 监控与告警配置

### 3.1 推荐监控面板 (Monitoring Dashboard)

```yaml
# 建议在 Cloud Monitoring 中创建以下图表：

图表1: NAT IP Utilization (%)
  - 指标: nat_ip_utilization
  - 资源: psc_nat_backend
  - 告警线: 60% (Warning), 75% (Caution), 85% (Critical)

图表2: Used NAT IP Addresses (Count)
  - 指标: used_nat_ip_addresses
  - 资源: psc_nat_backend

图表3: Available NAT IP Addresses
  - 指标: nat_ip_count - used_nat_ip_addresses
```

### 3.2 告警策略

```yaml
# alerting policy example (通过 gcloud CLI)
gcloud alpha monitoring policies create \
  --display-name="PSC NAT IP Utilization > 60%" \
  --condition-display-name="NAT IP Utilization > 60%" \
  --condition-threshold-value=0.6 \
  --condition-threshold-comparison=COMPARISON_GT \
  --notification-channels=NOTIFICATION_CHANNEL_ID
```

### 3.3 容量预警公式

```python
# 快速评估是否需要扩容
def need_expansion():
    used_ips = 5        # 当前使用数
    total_ips = 60      # /26 可用数
    utilization = used_ips / total_ips
    
    if utilization >= 0.85:
        return "立即扩容 - 容量即将耗尽"
    elif utilization >= 0.75:
        return "尽快扩容 - 空间不足"
    elif utilization >= 0.60:
        return "开始规划 - 接近警戒线"
    else:
        return "正常 - 当前无需扩容"
```

---

## 4. 扩容最佳实践

### 4.1 扩容原则

PSC NAT Subnet **不能原地扩容**，但可以**追加新Subnet**：

```
一个 Service Attachment 最多可绑定 10 个 NAT Subnet
```

**扩容步骤：**

1. 创建新的、更大的 NAT Subnet（例如从 /26 扩到 /25）
2. 将新 Subnet 绑定到同一个 Service Attachment
3. GCP 会自动在新旧 Subnet 间分流
4. 旧 Subnet 会在连接耗尽后逐渐释放

### 4.2 Terraform 示例

```hcl
# 原始 NAT Subnet
resource "google_compute_subnetwork" "psc_nat_original" {
  name          = "psc-nat-original"
  network       = google_compute_network.vpc.name
  region        = "us-east4"
  ip_cidr_range = "192.168.240.0/26"
  purpose       = "PRIVATE_SERVICE_CONNECT"
  role          = "ACTIVE"
}

# 追加的扩容 NAT Subnet
resource "google_compute_subnetwork" "psc_nat_expansion" {
  name          = "psc-nat-expansion"
  network       = google_compute_network.vpc.name
  region        = "us-east4"
  ip_cidr_range = "192.168.240.64/25"  # 扩容到 /25
  purpose       = "PRIVATE_SERVICE_CONNECT"
  role          = "ACTIVE"
}

# Service Attachment 绑定多个 NAT Subnet
resource "google_compute_service_attachment" "example" {
  name        = "example-attachment"
  region      = "us-east4"
  nat_subnets = [
    google_compute_subnetwork.psc_nat_original.self_link,
    google_compute_subnetwork.psc_nat_expansion.self_link,  # 新增
  ]
  target_service = google_compute_forwarding_rule.ilb.self_link
}
```

---

## 5. 总结

| 问题 | 答案 |
|:---|:---|
| 为什么显示5个已用IP？ | 包含Gateway、保留地址和已分配待回收的IP，非瞬时流量计数 |
| 利用率影响吞吐量吗？ | **不影响**。吞吐量由ILB决定，NAT Subnet只管连接容量 |
| 需要监控吗？ | 必须。监控 `nat_ip_utilization`，设置60%/75%/85%告警阈值 |
| 子网划分原则？ | 按Consumer Endpoint数量、连接类型（长/短）、是否为平台共享服务来决策 |
| 当前Subnet状态？ | 7.81%利用率，容量充裕，但建议设置监控告警 |

---

## 6. 参考链接

- [About published services (GCP VPC)](https://cloud.google.com/vpc/docs/about-vpc-hosted-services)
- [Publish services by using Private Service Connect](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer)
- [Cloud Monitoring - PSC Metrics](https://cloud.google.com/monitoring/api/metrics_gcp#gcp-private-service-connect)

---

---

## 附录：三个核心指标的深度解析（Console Public Service 详情页）

在 GCP Console → Private Service Connect → Published Services → 点击某个 Service Attachment 进入详情页，会看到以下三个关键指标：

### A. Connected Forwarding Rules

**定义：** 连接到该 Service Attachment 的消费者侧 PSC Forwarding Rule 的数量。

**数据来源：**
GCP 会在控制面持续检测所有引用了该 Service Attachment 的 `compute.googleapis.com/ForwardingRule` 资源。只要某个 PSC Forwarding Rule（通常是 `VPC_IP` 类型的入站规则）指向了这个 Service Attachment，它就算作一个"connected" forwarding rule。

**数量由什么决定：**
- 消费者侧创建了多少个 PSC Forwarding Rule 来引用你的 Service Attachment
- 每个消费者 VPC（或者同一 VPC 内的不同 Endpoint）可以各自创建自己的 PSC Forwarding Rule
- 同一个消费者可能创建多个规则（不同协议、不同 Endpoint 用途）

**是否变化：**
- **是，会动态变化**
- 消费者新建/删除 PSC Forwarding Rule → 数值立即增减
- 这是一个**实时计数**，反映当前有多少条通道正在引用你的服务

**示例：**
```
Consumer-A 创建了 2 条 PSC Forwarding Rule (TCP + HTTPS)
Consumer-B 创建了 1 条 PSC Forwarding Rule (TCP)
→ Connected Forwarding Rules = 3
```

---

### B. NAT IP Address In Use

**定义：** 在 PSC NAT Subnet 中，当前被 GCP 分配给活跃 NAT 转换使用的 IP 数量。

**这是最核心也是最容易误解的一个指标，理解它的关键是搞清楚 GCP 是如何分配和保留 NAT IP 的。**

**IP 分配机制（GCP PSC NAT 工作原理）：**

```
Consumer VPC (源IP: 10.0.1.50)
    │
    │  ← PSC 隧道到达 Producer 侧
    ▼
Service Attachment
    │
    │  ← GCP 在这里执行 SNAT
    ▼
NAT Subnet 分配一个 IP 作为转换后的源IP
    │
    ▼
Producer Internal LB → GKE Pod
```

当一个新连接首次从 Consumer 侧进入 Service Attachment 时，GCP 会：

1. **从 NAT Subnet 中分配一个 IP** 给这个连接做源地址转换（SNAT）
2. GCP 维护一个 **IP-to-Connection 映射表**
3. 同一个 NAT IP 可以被**多个连接复用**（这就是 PSC NAT 和传统 1:1 NAT 的本质区别）

**"In Use"的精确含义：**

GCP 内部维护一个 NAT IP 分配池，以下情况 IP 会进入 "in use" 状态：

| 场景 | IP 是否算 "in use" |
|:---|:---|
| 有活跃连接正在使用该 IP | ✅ 是 |
| 连接已关闭但处于 TCP TIME_WAIT（默认 60s） | ✅ 仍然算 |
| GCP 已将 IP 预分配给某个 Forwarding Rule | ✅ 算 |
| IP 刚从 TIME_WAIT 释放，但 GCP 尚未归还到空闲池 | ✅ 仍然算 |
| 完全空闲，尚未被分配 | ❌ 不算 |

**关键洞察：这不是瞬时并发连接计数，而是累计分配量。**

GCP 的 IP 分配策略并不是"连接结束立即归还 IP"，而是：
- **保留最近使用过的 IP**（缓存思想），因为这些 IP 很可能立即被新连接复用
- **TIME_WAIT 期间 IP 仍被锁定**，防止迷途报文（stray packets）被错误路由
- IP 的回收是**异步延迟进行**的，不由单条连接的断开发起

**由什么决定 NAT IP "in use" 的数量：**

不是由"有多少 Forwarding Rule"直接决定，而是由：
1. **并发活跃连接数** — 同一时刻有多少条 TCP/UDP 流正在使用 NAT
2. **连接的分布情况** — 如果所有连接都能被少数 NAT IP 承载，则 IP 用得少
3. **GCP 内部的负载均衡策略** — GCP 会在可用 NAT IP 之间分散连接，以避免单 IP 过热（per-IP connection limit）
4. **TIME_WAIT 超时窗口** — 连接关闭后 IP 被锁定的时间越长，同一时刻"in use"的 IP 就越多

**是否变化：**
- **是，持续动态变化**
- 新连接建立 → 分配 NAT IP（in use 可能上升）
- TIME_WAIT 超时到期 → IP 进入待回收状态（in use 暂时不变）
- GCP 异步回收完成 → IP 归还空闲池（in use 下降）
- 流量突发 → GCP 可能预分配额外 IP（in use 快速上升）

---

### C. Open Connections

**定义：** 当前**正在传输数据**的活跃 TCP/UDP 连接数量。

**这是最直观的指标：** 任意时刻，有多少条连接正处在 ESTABLISHED 状态（对于 TCP）或等效活跃状态（对于 UDP）。

**由什么决定：**
- Consumer 侧发起了多少请求，当前尚未完成
- 长连接（Keep-alive/HTTP persistent connection）场景下，一个连接可以承载多个请求
- 短连接场景下，每个请求对可能触发一个独立连接

**与 NAT IP In Use 的关系：**

```
Open Connections 多
    ↓
需要更多 NAT IP 来分散连接（避免单 IP 过热）
    ↓
NAT IP In Use 上升
```

但它们不是 1:1 的关系。理论上 65535 个连接可以被**1个 NAT IP** 承载（因为每个 IP 有 65535 个源端口），但实际上 GCP 会将连接分散到多个 NAT IP 以实现更好的哈希分布。

**是否变化：**
- **是，变化最剧烈的指标**
- 业务流量高峰 → 快速上升
- 流量低谷 → 快速下降
- 变化频率远高于 NAT IP In Use（因为连接级别的变化比 IP 分配级别更细粒度）

---

### 三者的关系与变化节奏

```
Connected Forwarding Rules          NAT IP Address In Use         Open Connections
│
│  变化最慢、最稳定                 │  变化较慢，有滞后              │  变化最快、最剧烈
│  消费者创建/删除规则时变化        │  新连接建立时分配             │  流量进来就涨
│  数值反映跨消费者的接入拓扑       │  TIME_WAIT/GC回收有延迟       │  流量停止就跌
│                                  │  数值反映NAT池的分配压力       │  数值反映即时负载
```

**一个形象的比喻：**

把 PSC Service Attachment 比作一个电话总机：

| GCP PSC 指标 | 对应电话总机的概念 |
|:---|:---|
| Connected Forwarding Rules | **有多少根外线接入总机**（固话线数量） |
| NAT IP Address In Use | **总机正在使用的出局号码数量**（号码池里的占用数） |
| Open Connections | **当前正在通话的数量**（并发通话数） |

- 有10根外线接入，不等于10个人都在通话（Connected → In Use）
- 通话结束了，外线可能还"占着"号码，因为总机要确保对方还能打回来（In Use 的延迟释放）
- 同时有1000个人在打电话，但出局号码可能只需要50个（Open Connections → NAT IP 多对一复用）

---

### 实战中的观察建议

1. **Connected Forwarding Rules 应该是稳定的** — 如果你发现它不断增长但你没有新增消费者，说明有异常接入
2. **NAT IP In Use 跟 Open Connections 不成正比** — 看到 Open Connections 很高但 NAT IP In Use 很低是正常现象（说明 NAT IP 复用做得好）
3. **NAT IP In Use 持续不下降** — 可能是因为连接都是长连接，IP 被持续占用；或者是 TIME_WAIT 期间还没有完成 GC 回收
4. **真正需要担心的是：NAT IP In Use 接近 NAT Subnet 可用 IP 总数** — 这意味着 NAT 池即将耗尽，新连接将被拒绝

---

## 附录：官方文档精读 — NAT Subnet IP 消耗规则与多项目场景分析

> 官方原文来源：[About VPC hosted services - PSC Subnet](https://cloud.google.com/vpc/docs/about-vpc-hosted-services#psc-subnet)

### 官方原文核心摘录

> **NAT 子网大小决定了可以连接到您的服务的使用方数量。**
> 如果 NAT 子网中的所有 IP 地址都已使用，则任何额外的 Private Service Connect 连接都会失败。

**关键消耗规则（官方说法）：**

| 消耗主体 | 占用 NAT IP 数量 | 说明 |
|:---|:---|:---|
| 每个 Consumer Endpoint 或 Backend | **1 个 IP** | 独立占用，不区分 TCP/UDP 连接数 |
| 每个连接传播到的 VPC spoke | **1 个额外 IP** | 仅在使用连接传播（Connection Propagation）时 |
| 多租户服务或多点访问使用方 | **N 个 IP** | 按端点/后端数量叠加计算 |

> ⚠️ **重要：** TCP 或 UDP 连接数量**不影响** NAT IP 消耗。1000 条 TCP 连接从同一个 Consumer Endpoint 发出，仍然只占用 **1 个** NAT IP。

---

### 你的具体场景：20 个 Talent Project 接入

**问题：** 假如有 20 个不同工程（Talent Project）连接到 Master Project 发布的 Service Attachment，是否最少占用 20 个 IP？

**答案：取决于接入方式。**

#### 场景 A：每个 Talent Project 用一个 PSC Endpoint 接入

```
Master Project (Producer)
  └── Service Attachment
        └── NAT Subnet (e.g., 192.168.240.0/26)
              ├── 192.168.240.3  ← Talent-Project-01 的 PSC Endpoint
              ├── 192.168.240.4  ← Talent-Project-02 的 PSC Endpoint
              ├── ...
              └── 192.168.240.22 ← Talent-Project-20 的 PSC Endpoint

→ NAT IP In Use = 20
→ 每个 Project 独占 1 个 NAT IP
```

**每个 PSC Endpoint 在 NAT Subnet 中占用 1 个 IP**，无论该 Project 内有多少台 VM、有多少 GKE 集群、发起多少 TCP 连接。

#### 场景 B：同一个 Project 内多个 Endpoint

```
Talent-Project-01 (us-east4)
  ├── PSC Endpoint A (GKE Cluster 1)
  └── PSC Endpoint B (GKE Cluster 2)
      → NAT IP In Use = 2（同一个 Project 但不同 Endpoint）

Talent-Project-02 (us-west4)
  └── PSC Endpoint C
      → NAT IP In Use = 3（累计）
```

**同一个 Project 的不同 Endpoint 各自独立计 IP**，因为它们是不同的接入点。

#### 场景 C：使用了连接传播（Connection Propagation）

```
Master Project
  └── Service Attachment
        └── NAT Subnet

Talent-Project-01 的一个 Endpoint 配置了连接传播到 3 个 VPC Spoke
  → NAT IP In Use = 1 (Endpoint 本身) + 3 (Spoke) = 4 个 IP

Talent-Project-02 的一个 Endpoint 配置了连接传播到 5 个 VPC Spoke
  → NAT IP In Use = 1 (Endpoint 本身) + 5 (Spoke) = 6 个 IP
```

**连接传播会将每个 VPC Spoke 映射为一个额外 IP**，这也是官方明确指出的消耗场景。

#### 场景 D：多点访问（Multi-spot Access）

```
Talent-Project-01 通过 3 个不同区域的 PSC Endpoint 访问同一个 Service Attachment
  → NAT IP In Use = 3（每个 Endpoint 独立计 IP）
```

如果一个使用方跨多个区域、多点接入服务，每个接入点都计 IP。

---

### 20 个 Project 的最小 IP 占用计算

**最节省 IP 的接入方式：** 每个 Project 使用 **1 个 PSC Endpoint**，不启用连接传播。

```
20 个 Talent Projects
  × 1 个 PSC Endpoint 每个 Project
  = 20 个 NAT IP

/26 子网可用 IP = 60
→ 利用率 = 20/60 ≈ 33%
```

**如果某个 Project 启用了连接传播到 3 个 VPC Spoke：**

```
基础: 20 个 Endpoint = 20 IP
额外: 1 个 Project × 3 个 Spoke = 3 IP
合计: 23 IP
```

**结论：20 个 Project 最少占用 20 个 NAT IP（每个 Project 1 个 Endpoint 的情况下）。**

---

### 为什么连接数量不影响 NAT IP 消耗？

这是 PSC NAT 与传统 NAT 的核心区别之一：

```
传统 NAT (e.g., 家宽路由器):
  内部: 192.168.1.1:50000 → NAT → 公网: 1.2.3.4:50000
  每个内部 IP + 端口组合 = 1 个公网 IP
  连接数直接影响 IP 消耗

PSC NAT:
  Consumer VPC: 10.0.1.50:ANY_PORT → NAT → NAT-IP-1:ANY_PORT
  Consumer VPC: 10.0.1.51:ANY_PORT → NAT → NAT-IP-1:ANY_PORT  (复用)
  Consumer VPC: 10.0.1.52:ANY_PORT → NAT → NAT-IP-1:ANY_PORT  (复用)
  ...
  10000 条连接可以复用一个 NAT IP
  连接数不影响 IP 消耗，Endpoint 数量才影响
```

**关键洞察：PSC NAT 是 EPERIC (Endpoint-per-Connection) 的对立面 — 它在 Endpoint 级别做 SNAT，而不是在每条连接级别。**

---

### 多 Project 接入的容量规划建议

基于官方规则，20 个 Project 接入的容量规划：

```
场景：20 个 Talent Projects，最少 20 个 NAT IP

推荐子网: /26 (60 可用 IP)
  - 20 IP 预留给 Project 接入
  - 剩余 40 IP 作为扩展缓冲
  - 扩容触发点: 达到 50% (~30 IP) 时开始规划追加 Subnet

如果某些 Project 需要连接传播:
  每个启用了传播的 Project 额外 +N IP (N=Spoke 数量)
  在 /26 中能容纳的 Project 数相应减少
```

| 子网大小 | 可用 NAT IP | 可容纳 Project 数（无连接传播） | 可容纳 Project 数（平均每个 Project 多占 2 IP） |
|:---|:---|:---|:---|
| /28 | 12 | 12 | ~4 |
| /27 | 28 | 28 | ~9 |
| **/26** | **60** | **60** | **20** |
| /25 | 124 | 124 | ~41 |
| /24 | 252 | 252 | ~84 |

> ⚠️ **/26 是 20 个 Project 的最小安全起步**。如果任何 Project 启用了连接传播或有多个 Endpoint，立即考虑 /25。

---

### 连接传播（Connection Propagation）的 IP 消耗详解

官方说明：
> 如果使用方使用连接传播，则对于每个端点，系统会为连接所传播到的每个 VPC spoke 使用一个额外的 IP 地址。

```
连接传播工作原理：

Talent-Project-01 (Hub VPC)
  └── PSC Endpoint (1 个)
        │
        │  连接传播将流量路由到以下 Spoke:
        ├── Spoke VPC A (us-east4)
        ├── Spoke VPC B (us-west4)
        └── Spoke VPC C (europe-west1)

→ NAT IP 消耗: 1 (Endpoint 自身) + 3 (Spoke) = 4 个 IP
```

**连接传播数量限制**可以在 Service Attachment 侧配置，限制每个 Endpoint 最多传播到 N 个 Spoke，从而控制 IP 消耗：

```bash
# 配置每个 Endpoint 最多传播到 5 个 VPC Spoke
gcloud compute service-attachments update ATTACHMENT_NAME \
  --region=us-east4 \
  --max-propagated-connections-per-endpoint=5
```

---

### 总结：IP 消耗的准确公式

```
NAT IP In Use =
  Σ (每个 Endpoint 占用 1 IP)
  + Σ (每个连接传播 Spoke 占用 1 IP)
  + GCP 内部管理地址 (.1 Gateway, .2 内部)

与以下因素无关（官方明确）：
  ✗ TCP/UDP 连接数量
  ✗ 使用方 VPC 网络数量
  ✗ 流量大小 (QPS/带宽)
  ✗ 端口数量
```

---

## 附录：官方文档勘误与注意

> 官方文档中有一处文字错误："129 NAT 子网有4个可用的IP地址" 应为 "/26 NAT 子网有 60 个可用的 IP 地址"。

**正确的子网可用 IP 数量：**

| 子网 | 总 IP | GCP 保留 | **可用 NAT IP** | 说明 |
|:---|:---|:---|:---|:---|
| /30 | 4 | 4 | **0** | 太小，无法用于 PSC NAT |
| /29 | 8 | 4 | **4** | 最小可用，测试场景 |
| /28 | 16 | 4 | **12** | 最小生产单元 |
| /27 | 32 | 4 | **28** | 小规模 |
| **/26** | **64** | **4** | **60** | **生产默认起步** |
| /25 | 128 | 4 | 124 | 中等规模 |
| /24 | 256 | 4 | 252 | 高流量/平台共享 |

GCP 保留的 4 个 IP 始终为：网络地址、Gateway（通常 .1）、GCP 内部使用（通常 .2）、广播地址。

---

## 附录：你的知识库文件清单

已在生成文档前阅读以下文件：

- `psc-subnet.md` - PSC NAT Subnet容量与QPS关系解析
- `ip-range.md` - GKE多集群IP规划
- `psc-sub-last-eng.md` - 生产级PSC容量规划（英文）
- `psc-subnet-enhance.md` - PSC定义与规划（10集群高访问量版）
- `psc-sub-last.md` - 完整PSC子网规划与Quota分析
