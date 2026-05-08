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

## 附录：你的知识库文件清单

已在生成文档前阅读以下文件：

- `psc-subnet.md` - PSC NAT Subnet容量与QPS关系解析
- `ip-range.md` - GKE多集群IP规划
- `psc-sub-last-eng.md` - 生产级PSC容量规划（英文）
- `psc-subnet-enhance.md` - PSC定义与规划（10集群高访问量版）
- `psc-sub-last.md` - 完整PSC子网规划与Quota分析
