# PRIVATE_SERVICE_CONNECT 定义与规划（单区域 10 集群 / 单集群内多 Attachment / 高访问量版）

## 1. Goal and Constraints

### 背景

当前前提如下：

- 所有集群都在 **同一个 Region**，例如 `europe-west2`
- VPC 现有地址体系中，GKE Node Subnet 已经规划为：
  - `192.168.64.0/20`
  - `192.168.80.0/20`
  - ...
  - `192.168.208.0/20`
- Master Project 负责创建 `PSC Service Attachment`
- 单个 Cluster 不只是暴露一个 attachment，而是可能暴露 **多个 attachment**
- 平台访问量大，需要考虑：
  - endpoint / consumer 数量
  - 并发 TCP session
  - attachment 扩容路径

### 这个问题的核心

前一版“每个 Cluster 绑定一个 `/24` PSC Pool”的思路，**只适合轻量场景**，不适合你当前这个“单集群内多 attachment + 高访问量”的模型。

因为真实情况是：

- `一个 Service Attachment = 至少一个独立 PSC NAT subnet`
- `一个 PSC NAT subnet 不能复用给多个 attachment`
- 所以一个 Cluster 如果暴露多个 attachment，就一定需要 **多个不同的 PSC 子网**

这意味着：

- 规划粒度不能只停留在“Cluster 对应一个 PSC Pool”
- 还必须定义：
  - `Cluster 内 attachment 如何切分`
  - `高流量 attachment 如何扩容`
  - `同 cluster attachment 用完本地池后如何外溢`

---

## 2. Recommended Architecture (V1)

### 推荐结论

这次推荐的设计不是：

```text
1 Cluster = 1 PSC subnet
```

而是：

```text
1 Cluster = 1 Home PSC Pool
1 Attachment = 1 or more PSC NAT subnets
多个 attachment 从该 Cluster 的 Home Pool 中切分
Home Pool 不够时，再使用 Shared Overflow Pool
```

### 为什么这是更合理的 V1

它同时满足：

- 单区域统一治理
- 多 Cluster 归属清晰
- 单 Cluster 内多 attachment 可扩展
- 高流量 attachment 可继续追加 NAT subnet
- 未来不会因为“最初切得太小”而重构整套地址规划

---

## 3. PSC Capacity Model

## 3.1 PSC NAT subnet 决定什么

PSC NAT subnet 主要影响的是：

- 可接入的 consumer endpoints / backends 数量
- producer 侧 NAT IP 容量
- producer 侧并发 TCP session 的容量墙

它 **不是直接的 QPS 上限**。

QPS 更主要取决于：

- Internal Load Balancer
- Backend Service / NEG
- 实际连接模型

## 3.2 两个必须同时看的公式

### 公式 A：NAT IP 需求

```text
Required NAT IPs
= 预计 PSC endpoints 数量
+ 预计 PSC backends 数量
+ propagated connections 附加消耗
+ 20%~30% buffer
```

### 公式 B：并发 TCP 连接容量

对于 NAT 子网中的每一个 IP，它理论上能支持的并发 TCP 连接数受限于源端口范围：

$$Concurrent\_Connections \approx \text{NAT\_IP\_Count} \times 63,488$$

## 3.3 按子网规模换算

Google Cloud 子网有 4 个不可用地址，因此可以先用下面这个粗略表：

| NAT Subnet | Usable NAT IPs | 理论并发 TCP 连接上限（近似） |
| :--------- | :------------- | :---------------------------- |
| `/26`      | `60`           | `60 × 63,488 ≈ 3.81M`         |
| `/25`      | `124`          | `124 × 63,488 ≈ 7.87M`        |
| `/24`      | `252`          | `252 × 63,488 ≈ 15.99M`       |

### 如何正确理解这个公式

这个公式不是说：

- `/24` 就天然能扛住 1600 万 QPS

而是说：

- 如果这个 attachment 需要承载大量并发 TCP 会话
- 而且这些会话都要通过 PSC producer NAT IP 做端口映射
- 那么 NAT subnet 会形成一个真实的连接容量上限

所以对你们这种平台型场景，规划上不能把 `/26` 作为生产默认。

---

## 4. Addressing Strategy

## 4.1 不推荐继续用“每个 Cluster 一个 /24，然后就结束”

这种设计的问题是：

- 一个 Cluster 里如果出现 2~4 个 attachment，很快就把 `/24` 切碎
- 高流量 attachment 如果需要独占 `/24`，同 cluster 的其它服务就没有空间
- 后续扩容会非常依赖人工临时决策

### 结论

**Cluster 要有 Home Pool，但不能把 Home Pool 等同于唯一可用空间。**

---

## 4.2 推荐总池

### 推荐生产版

建议把 PSC 专用保留池正式定义为：

- **`172.20.0.0/18` = Master Project PSC Dedicated Supernet**

### 为什么这里推荐换到 `172.20.0.0/18`

虽然 `192.168.240.0/20` 也能用，但如果你已经明确：

- 单区域
- 10 个 Cluster
- 单 Cluster 内多 attachment
- 高访问量

那么 `/20` 很快会从“够用”变成“需要精打细算”。

而 `172.20.0.0/18` 的优势是：

1. 完全避开当前 `192.168.64.0/20 ~ 192.168.208.0/20` 的 Node 规划语义
2. 给你一个真正独立的 PSC 地址域
3. 有 64 个 `/24`
4. 足以支撑：
   - 10 个 Cluster 的 Home Pool
   - 大量 shared pools
   - 大量 overflow pools
   - migration / DR buffer

### 如果你坚持保留 192.168 风格

那我会把它定义成：

- `192.168.240.0/20` = 过渡版 PSC Pool

但从长期生产视角，我更推荐直接把 PSC 抽到：

- `172.20.0.0/18`

这样最清晰，也最不容易和已有 `192.168.*` 规划发生语义混用。

---

## 5. Recommended Pool Model

### 设计原则

把 PSC 池拆成三层：

1. **Cluster Home Pool**
2. **Shared Service Pool**
3. **Overflow / Expansion Pool**

### 规则

- 每个 Cluster 先分配一个 **Home Pool**
- 每个 attachment 从自己所属 Cluster 的 Home Pool 中切出独立 subnet
- 如果 attachment 很大，允许直接从 Shared 或 Overflow 池取更大的 subnet
- 同一个 attachment 需要扩容时，优先给它追加第二个 PSC NAT subnet，而不是重建原 subnet

---

## 6. 推荐切分方案

## 6.1 每个 Cluster 分一个 `/23` Home Pool

这是这次的关键变化。

不再是：

- `1 Cluster = 1 /24`

而是：

- **`1 Cluster = 1 /23 Home Pool`**

每个 `/23` 有 512 个地址，等价于：

- 2 个 `/24`
- 4 个 `/25`
- 8 个 `/26`
- 或混合切分

这正好适合“一个 Cluster 内多 attachment”的现实需求。

### 10 个 Cluster 的 Home Pool 规划

| Cluster ID | Cluster Name | Node Subnet        | PSC Home Pool (/23) |
| :--------- | :----------- | :----------------- | :------------------ |
| `01`       | `core-01`    | `192.168.64.0/20`  | `172.20.0.0/23`     |
| `02`       | `core-02`    | `192.168.80.0/20`  | `172.20.2.0/23`     |
| `03`       | `core-03`    | `192.168.96.0/20`  | `172.20.4.0/23`     |
| `04`       | `core-04`    | `192.168.112.0/20` | `172.20.6.0/23`     |
| `05`       | `tenant-01`  | `192.168.128.0/20` | `172.20.8.0/23`     |
| `06`       | `tenant-02`  | `192.168.144.0/20` | `172.20.10.0/23`    |
| `07`       | `staging-01` | `192.168.160.0/20` | `172.20.12.0/23`    |
| `08`       | `staging-02` | `192.168.176.0/20` | `172.20.14.0/23`    |
| `09`       | `mgmt-01`    | `192.168.192.0/20` | `172.20.16.0/23`    |
| `10`       | `mgmt-02`    | `192.168.208.0/20` | `172.20.18.0/23`    |

这 10 个 `/23` 总共只消耗：

- `172.20.0.0/23` 到 `172.20.19.255`

也就是只用了整个 `/18` 的一小部分。

## 6.2 Shared / Overflow / DR Pool

### 推荐保留

| 用途                       | CIDR             |
| :------------------------- | :--------------- |
| `shared-services-01`       | `172.20.20.0/22` |
| `high-traffic-overflow-01` | `172.20.24.0/22` |
| `high-traffic-overflow-02` | `172.20.28.0/22` |
| `migration-buffer-01`      | `172.20.32.0/21` |
| `dr-reserved-01`           | `172.20.40.0/21` |
| `future-growth-01`         | `172.20.48.0/20` |

这意味着：

- 正常集群内 attachment 有 Home Pool
- 平台共享入口有 Shared Pool
- 大流量 attachment 有专门 Overflow Pool
- 未来迁移和 DR 也有明确预留

---

## 7. Attachment Allocation Policy

## 7.1 推荐 attachment profile

| Attachment 类型 | 起始网段 | 适用场景                     |
| :-------------- | :------- | :--------------------------- |
| `Small`         | `/26`    | 测试、低租户、低并发         |
| `Medium`        | `/25`    | 普通生产 attachment          |
| `Large`         | `/24`    | 平台共享服务、高租户、高并发 |

## 7.2 生产默认值

对于你们当前场景，建议：

- **普通生产 attachment：`/25` 起步**
- **共享平台入口 attachment：`/24` 起步**
- **测试 / staging attachment：`/26` 或 `/25`**

## 7.3 单 Cluster 内多 attachment 的切分示例

### 以 `core-02` 为例

`core-02` 的 Home Pool：

- `172.20.2.0/23`

它可以这样切：

| Attachment             | CIDR              | 类型   |
| :--------------------- | :---------------- | :----- |
| `psc-core02-api-01`    | `172.20.2.0/25`   | Medium |
| `psc-core02-api-02`    | `172.20.2.128/25` | Medium |
| `psc-core02-shared-01` | `172.20.3.0/24`   | Large  |

这个例子说明：

- 同一个 Cluster 内完全可以暴露多个 attachment
- attachment 之间各自使用不同 subnet
- 而且不需要一开始就跳到共享池

### 再看一个更碎片化的例子

如果 `tenant-01` 里有多个小 attachment：

- `172.20.8.0/26`
- `172.20.8.64/26`
- `172.20.8.128/25`
- `172.20.9.0/24`

这也完全成立。

关键不是“一个 Cluster 对一个网段”，而是：

- **一个 Cluster 对一个 Home Pool**
- **一个 Attachment 对一个独立 PSC NAT subnet**

---

## 8. 扩容策略

## 8.1 同 attachment 扩容

如果某个 attachment 增长很快，不要试图改原有子网大小。

正确做法是：

- 直接给该 attachment 追加第二个 PSC NAT subnet

例如：

```text
psc-core02-api-01
  -> 172.20.2.0/25
  -> 172.20.24.0/25
```

这是 PSC producer 官方模型天然支持的。

## 8.2 同 cluster 内 attachment 用完 Home Pool

如果某个 Cluster 内 attachment 很多，Home Pool `/23` 不够：

### 优先顺序

1. 先看能否把低优先级 attachment 保持在 `/26`
2. 大 attachment 直接外溢到 `high-traffic-overflow`
3. 平台共享入口直接用 `shared-services`

### 不建议

- 不要为了“地址整齐”强行把所有 attachment 都塞在 cluster home pool
- 也不要反过来完全放弃 cluster ownership

更好的做法是：

- `80%` attachment 在 Home Pool
- `20%` 特殊高流量 / 共享 attachment 在 Shared / Overflow Pool

---

## 9. 性能与容量评估方法

## 9.1 四个输入

对每个 attachment 都要评估：

1. `consumer endpoints` 数量
2. `propagated connections` 是否开启
3. 流量模型是长连接还是短连接
4. 这个 attachment 是不是平台共享入口

## 9.2 快速 sizing 规则

### 规则 1

如果 attachment 是普通内部服务：

- 默认 `/25`

### 规则 2

如果 attachment 是平台共享入口、租户数量多、连接创建频繁：

- 默认 `/24`

### 规则 3

如果 attachment 预估 consumer endpoint 很少，且流量稳定：

- 可以 `/26`

### 规则 4

如果一个 attachment 明显可能长期增长：

- 从一开始就接受“未来加第二个 subnet”的设计

## 9.3 监控指标

重点监控：

- `private_service_connect/producer/used_nat_ip_addresses`

并建议用下面阈值：

- `>= 60%`：开始评估扩容
- `>= 75%`：准备追加 NAT subnet
- `>= 85%`：高优先级扩容，避免 consumer 接入失败

---

## 10. Final Recommendation

### 最终建议

在你这个场景下，推荐正式定义为：

- **`172.20.0.0/18` = Master Project PSC Dedicated Supernet**
- **每个 Cluster 固定拥有 1 个 `/23` Home Pool**
- **每个 Attachment 拥有 1 个或多个独立 PSC NAT subnet**
- **普通生产 attachment 默认 `/25` 起步**
- **高流量 / 平台共享 attachment 默认 `/24` 起步**
- **共享服务与超大流量 attachment 使用 Shared / Overflow Pool**

### 为什么这版比上一版更合适

因为它真正解决了你提到的核心问题：

- 不是一个 Cluster 只对应一个 attachment
- 而是一个 Cluster 可以自然地承载多个 attachment
- 同时还能保持 ownership、可扩容性和地址体系清晰

---

## 11. References

- [Publish services by using Private Service Connect](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer)
- [About published services](https://cloud.google.com/vpc/docs/about-vpc-hosted-services)

---

## 12. VPC1 约束下的 192.168.224.0/19 替代规划

这一节专门回应你的实际环境约束：

- 你希望继续使用 `192.168.x.x`
- 重点只看 `VPC1`
- 你提出把 **`192.168.224.0/19`** 作为 `Master Project PSC Dedicated Supernet`
- 同时要考虑：
  - **10 个 Cluster**
  - **每个 Cluster 可能有 10 个 attachment**

### 12.1 先看 VPC1 已知占用

基于你提供的信息，`VPC1` 里至少已有下面这些地址：

| 名称                                              | CIDR               | 用途              |
| :------------------------------------------------ | :----------------- | :---------------- |
| `cinternal-vpc1-us-east4-abjx-core`               | `192.168.0.0/18`   | 主业务子网        |
| `cinternal-vpc1-us-east4-abjx-gke-core-01`        | `192.168.64.0/20`  | GKE Node Subnet   |
| `cinternal-vpc1-us-east4-abjx-gke-core-master-01` | `192.168.224.0/27` | GKE Master 管理段 |
| `cinternal-vpc1-us-east4-abjx-gke-core-lb`        | `192.168.228.0/23` | LB / Infra 子网   |

### 12.2 关键结论

`192.168.224.0/19` 可以继续作为一个 **逻辑上的 Infra / PSC Supernet**。

但它 **不能被当成“纯净、完整、零占用”的 PSC 总池**，因为：

- `192.168.224.0/27` 已经被 Master 使用
- `192.168.228.0/23` 已经被 LB 使用

所以更准确的定义应该是：

```text
192.168.224.0/19 = VPC1 Infra Supernet
其中一部分用于 PSC
其中一部分已经用于 Master / LB
```

也就是说：

- **可以保留这个父范围**
- 但真正可分配给 PSC 的地址，需要剔除已有占用后再做规划

### 12.3 为什么这里不能再按“每个 Cluster 一个 /23 Home Pool”照搬

如果完全照搬上一版：

- 10 个 Cluster
- 每个 Cluster 一个 `/23 Home Pool`

那需要：

- `10 × /23 = 5120` 个地址

这在 `192.168.224.0/19` 的理论容量里是能塞下的。

但问题在于：

1. 你这里已经有 `master + lb` 先占了一部分
2. 你还要求 **每个 Cluster 可能有 10 个 attachment**
3. 如果这些 attachment 很多都要用 `/25` 甚至 `/24`，单纯给每个 Cluster 一个 `/23` 很快又会不够

所以：

- **`192.168.224.0/19` 适合做“统一父池”**
- 但 **不适合做“按 Cluster 刚性均分”**

在这个受限地址空间下，最好的方法是：

- 保留 Cluster ownership
- 但使用 **分层池 + 配额式分配 + Overflow Pool**

---

192.168.226.0/21
这个包含了我的master 
```bash
ipcalc 192.168.226.0/21
Address:   192.168.226.0        11000000.10101000.11100 010.00000000
Netmask:   255.255.248.0 = 21   11111111.11111111.11111 000.00000000
Wildcard:  0.0.7.255            00000000.00000000.00000 111.11111111
=>
Network:   192.168.224.0/21     11000000.10101000.11100 000.00000000
HostMin:   192.168.224.1        11000000.10101000.11100 000.00000001
HostMax:   192.168.231.254      11000000.10101000.11100 111.11111110
Broadcast: 192.168.231.255      11000000.10101000.11100 111.11111111
Hosts/Net: 2046                  Class C, Private Internet
```

ipcalc 192.168.240.0/20
Address:   192.168.240.0        11000000.10101000.1111 0000.00000000
Netmask:   255.255.240.0 = 20   11111111.11111111.1111 0000.00000000
Wildcard:  0.0.15.255           00000000.00000000.0000 1111.11111111
=>
Network:   192.168.240.0/20     11000000.10101000.1111 0000.00000000
HostMin:   192.168.240.1        11000000.10101000.1111 0000.00000001
HostMax:   192.168.255.254      11000000.10101000.1111 1111.11111110
Broadcast: 192.168.255.255      11000000.10101000.1111 1111.11111111
Hosts/Net: 4094                  Class C, Private Internet

---

## 13. 严格按 `192.168.240.0/20` 演算：10 Clusters × 10 Attachments

这一节只回答一个纯数学与切分问题：

- 固定总池：`192.168.240.0/20`
- 固定集群数：`10`
- 固定每个集群的 attachment 数：`10`
- 目标：严格保证能切出 **100 个独立 PSC NAT subnets**

这里先不讨论：

- attachment 是否高流量
- 子网是不是太小
- 是否适合作为长期生产标准

这部分只做 **可分配性验证**。

### 13.1 总池容量

`192.168.240.0/20` 的总地址数：

```text
2^(32-20) = 4096 addresses
```

如果只从“能不能切出来 100 个 attachment subnet”这个角度看，那么这个池子的容量是足够的。

### 13.2 最规整的切法

在 `192.168.240.0/20` 里，最规整、最容易执行的方式是：

1. **每个 Cluster 固定拿 1 个 `/24`**
2. **每个 Attachment 固定拿 1 个 `/28`**

因为：

- 一个 `/20` 一共包含 `16 x /24`
- 你只需要 `10 x /24` 给 10 个 Cluster
- 一个 `/24` 一共可以切出 `16 x /28`
- 你每个 Cluster 只需要 `10 x /28`

所以：

```text
1 Cluster = 1 /24
1 /24 = 16 x /28
实际使用 10 x /28
剩余 6 x /28
```

### 13.3 结论

如果你严格要求：

- `10 Clusters`
- `每个 Cluster 10 Attachments`
- 总池只能用 `192.168.240.0/20`

那么答案是：

- **完全可以做到**

而且这版切法很整齐：

- `10 x /24` 用于 10 个 Cluster
- 每个 `/24` 内切 `10 x /28` 给 10 个 attachment

---

## 14. 具体切分结果

## 14.1 10 个 Cluster 对应的 `/24`

| Cluster      | PSC Pool           |
| :----------- | :----------------- |
| `cluster-01` | `192.168.240.0/24` |
| `cluster-02` | `192.168.241.0/24` |
| `cluster-03` | `192.168.242.0/24` |
| `cluster-04` | `192.168.243.0/24` |
| `cluster-05` | `192.168.244.0/24` |
| `cluster-06` | `192.168.245.0/24` |
| `cluster-07` | `192.168.246.0/24` |
| `cluster-08` | `192.168.247.0/24` |
| `cluster-09` | `192.168.248.0/24` |
| `cluster-10` | `192.168.249.0/24` |

这样会用掉：

- `10 x /24`

同时还剩下：

- `192.168.250.0/24`
- `192.168.251.0/24`
- `192.168.252.0/24`
- `192.168.253.0/24`
- `192.168.254.0/24`
- `192.168.255.0/24`

也就是还剩 **6 个完整 `/24`**。

---

## 14.2 每个 Cluster 内 10 个 attachment 的标准模板

### 以 `cluster-01 = 192.168.240.0/24` 为例

| Attachment | PSC NAT Subnet       |
| :--------- | :------------------- |
| `att-01`   | `192.168.240.0/28`   |
| `att-02`   | `192.168.240.16/28`  |
| `att-03`   | `192.168.240.32/28`  |
| `att-04`   | `192.168.240.48/28`  |
| `att-05`   | `192.168.240.64/28`  |
| `att-06`   | `192.168.240.80/28`  |
| `att-07`   | `192.168.240.96/28`  |
| `att-08`   | `192.168.240.112/28` |
| `att-09`   | `192.168.240.128/28` |
| `att-10`   | `192.168.240.144/28` |

这个 `/24` 内还会剩下：

- `192.168.240.160/28`
- `192.168.240.176/28`
- `192.168.240.192/28`
- `192.168.240.208/28`
- `192.168.240.224/28`
- `192.168.240.240/28`

也就是 **6 个 `/28` reserve**。

### 这套模板可以直接平移到每个 Cluster

例如：

#### cluster-02

- Pool: `192.168.241.0/24`
- Attachments:
  - `192.168.241.0/28`
  - `192.168.241.16/28`
  - `192.168.241.32/28`
  - `192.168.241.48/28`
  - `192.168.241.64/28`
  - `192.168.241.80/28`
  - `192.168.241.96/28`
  - `192.168.241.112/28`
  - `192.168.241.128/28`
  - `192.168.241.144/28`

#### cluster-03

- Pool: `192.168.242.0/24`
- Attachments:
  - `192.168.242.0/28`
  - `192.168.242.16/28`
  - `192.168.242.32/28`
  - `192.168.242.48/28`
  - `192.168.242.64/28`
  - `192.168.242.80/28`
  - `192.168.242.96/28`
  - `192.168.242.112/28`
  - `192.168.242.128/28`
  - `192.168.242.144/28`

其余 Cluster 以此类推，统一套用同一模板即可：

- `243.0/24`
- `244.0/24`
- `245.0/24`
- `246.0/24`
- `247.0/24`
- `248.0/24`
- `249.0/24`

---

## 15. 严格结果的意义

### 15.1 你要的“100 个 attachment 能不能切出来”

答案是：

- **能**

而且不仅能切出来，还保留了显著余量：

1. 每个 Cluster 内多出 **6 个 `/28`**
2. 总池额外剩下 **6 个 `/24`**

### 15.2 这个结果适合拿来做什么

这版结果非常适合：

- 评估“地址数量上是否可行”
- 做 attachment 数量上限讨论
- 作为最小颗粒度切分的参考模板

### 15.3 这个结果不等价于什么

这版结果 **不等价于**：

- `/28` 就一定适合高流量生产 attachment

也就是说：

- 它是“严格满足 100 attachments”的子网演算结果
- 不是“高流量生产最优解”

---

## 16. 最终追加结论

如果你的当前目标只是：

- **严格按照 `192.168.240.0/20`**
- **严格支持 `10 Clusters × 10 Attachments`**

那么最规整的切法就是：

```text
192.168.240.0/20
  -> 10 x /24   (one /24 per cluster)
  -> each /24 split into 10 x /28
```

这个结果满足：

- `100 attachments`
- 每个 Cluster 还有 `6 x /28 reserve`
- 整体还保留 `6 x /24` 未使用

如果你下一步需要，我可以继续基于这个结果，直接再给你生成一版：

- **10 个 Cluster × 100 个 attachment 的完整 CIDR 对照表**

也就是把每一个 attachment 的名字和具体网段全部展开成一张可以直接复制进 Terraform `locals` 的清单。  

---

## 17. `/28` 最小子网的容量估算

如果继续沿用前面文档里的近似公式：

$$Concurrent\_Connections \approx \text{NAT\_IP\_Count} \times 63,488$$

那么对于类似：

- `192.168.240.0/28`

这种最小粒度 attachment subnet，可以做下面的估算。

### 17.1 `/28` 的地址数量

`/28` 的总地址数：

```text
2^(32-28) = 16 addresses
```

在 GCP 子网语义下，通常需要扣掉云平台保留地址，因此生产估算建议按 **12 个 usable NAT IP** 来算。

### 17.2 `/28` 的理论并发 TCP 连接上限

按 `12` 个 usable NAT IP 估算：

```text
Concurrent_Connections
≈ 12 × 63,488
≈ 761,856
```

也就是：

- **`/28` 大约可承载 76 万理论并发 TCP 连接**

如果你采用更保守估算，把 usable NAT IP 按 `11` 个算：

```text
11 × 63,488 ≈ 698,368
```

也就是：

- **大约 70 万理论并发 TCP 连接**

### 17.3 这个数字怎么理解

这个数字不是说：

- `/28` 就能稳定承载 70 万 QPS

它表示的是：

- producer 侧 NAT 端口空间的大致连接容量墙

换句话说：

- 如果客户端大量使用长连接，`/28` 可能已经够小型 attachment 用
- 如果客户端大量使用短连接、连接 churn 很高、consumer endpoint 很多，那么 `/28` 会很快变成瓶颈

### 17.4 结论

因此在 PSC attachment 设计里：

- `/28` 适合：
  - 小型 attachment
  - 低租户数量
  - 非共享生产入口
  - 仅用于“先切出来评估”
- `/28` 不适合默认作为：
  - 平台级共享入口
  - 高并发短连接服务
  - 高流量生产 attachment 的默认规模

---

## 18. 单个 `/24` 池的“四小加两大”规划

这一节基于你最新确认的模型来做：

- 每个 Cluster 先拿一个 `/24`，例如：
  - `192.168.240.0/24`
- Cluster 内的 attachment 不平均分配
- 采用：
  - **4 个小 attachment**
  - **2 个大 attachment**

也就是你说的：

- 小的用 `/28`
- 剩余空间尽量让“大 attachment”做到最大化

## 18.1 目标

在一个 `/24` 中实现：

- `4 x Small`
- `2 x Large`

并尽量让：

- `2 个大 attachment` 尺寸最大
- 切分仍然保持规整、可执行

---

## 18.2 先算小 attachment 占用

每个 `/28`：

- 总地址数：16

4 个 `/28` 一共占用：

```text
4 × 16 = 64 addresses
```

所以一个 `/24` 扣掉 4 个 `/28` 之后，还剩：

```text
256 - 64 = 192 addresses
```

这 192 个地址需要再分给：

- `2 个大 attachment`

---

## 18.3 最大化两个大 attachment 的最佳切法

CIDR 不能随意切成任意大小，必须按二进制边界对齐。

在剩余 192 个地址里，要尽可能给两个大 attachment 做到最大，最自然且最规整的方式是：

- **1 个 `/25`**
- **1 个 `/26`**

因为：

- `/25 = 128 addresses` ==> for our internal attachement 
- `/26 = 64 addresses` ==> for our external attachement 
- `128 + 64 = 192`

这刚好把剩余空间全部吃满。

### 结论

在一个 `/24` 池里，按照“四小加两大”模型，**最优规整切法**就是：

- `4 x /28`
- `1 x /25`
- `1 x /26`

这已经是“两个大 attachment 尽可能大”的最佳结果。

因为你不可能把剩余 192 地址切成：

- `2 x /25`

那需要 256 地址，不够。

也不可能切成两个完全一样的大块并同时保持 CIDR 合法边界。

---

## 18.4 具体切分示例

以：

- `192.168.240.0/24`

为例，一个很规整的切法如下：

### 四个小 attachment

| Attachment | CIDR                | 类型  |
| :--------- | :------------------ | :---- |
| `small-01` | `192.168.240.0/28`  | Small |
| `small-02` | `192.168.240.16/28` | Small |
| `small-03` | `192.168.240.32/28` | Small |
| `small-04` | `192.168.240.48/28` | Small |

### 两个大 attachment

| Attachment | CIDR                 | 类型  |
| :--------- | :------------------- | :---- |
| `large-01` | `192.168.240.64/26`  | Large |
| `large-02` | `192.168.240.128/25` | Large |

### 地址校验

这套切法总共占用：

- `4 x /28 = 64`
- `1 x /26 = 64`
- `1 x /25 = 128`

合计：

```text
64 + 64 + 128 = 256
```

也就是：

- **刚好用满一个 `/24`**

---

## 18.5 容量估算

### 小 attachment (`/28`)

按前面的近似算法：

```text
Concurrent_Connections ≈ NAT_IP_Count × 63,488
```

`/28` 约可提供：

- `12 usable NAT IPs`
- `≈ 761,856` 理论并发 TCP 连接

### 大 attachment (`/26`)

`/26` 约可提供：

- `60 usable NAT IPs`
- `60 × 63,488 ≈ 3.81M`

### 大 attachment (`/25`)

`/25` 约可提供：

- `124 usable NAT IPs`
- `124 × 63,488 ≈ 7.87M`

---

## 18.6 这个模型怎么理解

这说明如果你一个 Cluster 只打算实际暴露：

- 4 个低访问量 attachment
- 2 个高访问量 attachment

那么：

- **一个 `/24` 池已经非常适合**

而且它比“10 个 `/28` 平均切法”更符合真实业务权重。

### 对比“平均切 10 个 `/28`”

平均切法的优点：

- attachment 数量多
- 非常整齐

平均切法的问题：

- 每个 attachment 都只有 `/28`
- 没有把地址资源优先分给真正高流量的服务

而“四小加两大”的优点是：

- 小服务继续保持小网段
- 大服务获得明显更高的容量
- 一个 `/24` 被利用得更接近真实业务结构

---

## 18.7 最终建议

如果你现在已经确认：

- 一个 Cluster 并不需要平均暴露很多 attachment
- 实际更接近：
  - **4 个小 attachment**
  - **2 个大 attachment**

那么一个 `/24` 的推荐切法就是：

```text
192.168.240.0/24
  -> 192.168.240.0/28
  -> 192.168.240.16/28
  -> 192.168.240.32/28
  -> 192.168.240.48/28
  -> 192.168.240.64/26
  -> 192.168.240.128/25
```

也就是说：

- **4 Small + 2 Large**
- **刚好用满 `/24`**
- **是这类需求下最规整、最大化的切分方式**

---

## 19. PSC NAT Quota / Capacity 详细解释

这一节单独解释这条公式在 API 平台里的实际意义：

$$Concurrent\_Connections \approx \text{NAT\_IP\_Count} \times 63,488$$

你关心的核心问题其实是：

- 这个数字到底和我的 **并发量** 有什么关系
- 和我的 **TPS / QPS** 有什么关系
- 对一个运行了上千条 API 的平台来说，它到底限制了什么

### 19.1 先给一个直白结论

这条公式描述的不是：

- 你的平台每秒最多能处理多少请求

它描述的是：

- **PSC producer 侧 NAT 端口资源能够同时容纳多少活跃 TCP 会话**

所以它更像：

- `Connection Capacity`

而不是：

- `Request Throughput Capacity`

### 19.2 为什么是 `63,488`

一条 TCP 会话在做 NAT 映射时，除了源 IP 之外，还要占用一个源端口。

单个 IP 的端口理论空间接近 `65,535`，但要扣掉：

- 系统保留端口
- 不可用端口
- 实际实现留出的保护空间

所以工程上常用一个近似值：

- **`63,488 ports per NAT IP`**

这意味着：

- `1 个 NAT IP`
  - 大约可以承载 `63,488` 条并发 TCP 会话
- `N 个 NAT IP`
  - 大约可以承载 `N × 63,488` 条并发 TCP 会话

### 19.3 “并发连接” 和 “并发请求” 不是一回事

这是最重要的理解点。

#### 并发连接（Concurrent Connections）

指的是：

- 某一时刻同时处于活跃状态的 TCP 会话数量

例如：

- 客户端到 API Gateway 的 TCP 连接
- HTTP/1.1 keep-alive 连接
- HTTP/2 multiplexed 长连接

#### 并发请求 / TPS / QPS

指的是：

- 单位时间内处理的请求数量

例如：

- 每秒 `10,000` 次 API 请求
- 每秒 `100,000` 次 API 请求

### 关键区别

一个连接可以承载：

- 1 个请求
- 10 个请求
- 1000 个请求

取决于：

- 是否启用 keep-alive
- 是否启用 HTTP/2
- 请求时延
- 客户端复用连接的能力

所以：

- **高 QPS 不一定需要很多连接**
- **很多连接也不一定意味着高 QPS**

---

## 19.4 这条公式和 TPS / QPS 的关系

### 一个近似关系

如果定义：

- `C = 并发 TCP 连接数`
- `R = 每条连接平均每秒承载的请求数`

那么：

```text
QPS ≈ C × R
```

而：

```text
C ≤ NAT_IP_Count × 63,488
```

所以可以得到一个近似上限关系：

```text
QPS ≤ (NAT_IP_Count × 63,488) × 每连接请求速率
```

### 这意味着什么

同一个 `/28` 子网，在不同连接模型下，QPS 能差很多个数量级。

例如 `/28` 按 12 个 usable NAT IP 算：

```text
12 × 63,488 ≈ 761,856 concurrent connections
```

#### 情况 A：短连接模型

如果客户端每个请求都新建连接，或者连接复用很差：

- 每个连接的价值很低
- NAT 端口会快速被消耗
- 你可能还没把后端打满，PSC NAT 就先成瓶颈

#### 情况 B：长连接 / keep-alive / HTTP/2 模型

如果客户端高度复用连接：

- 每条连接可以承载很多请求
- 相同的 NAT 容量可以支撑更高的 QPS
- PSC NAT 不一定是第一瓶颈

---

## 19.5 API 平台场景下如何理解

你说你们是 API 访问平台，而且有上千条 API。

这个背景下，真正要看的不是“API 数量”，而是下面几个维度：

### 1. 有多少 consumer / client

如果 API 数量很多，但实际 consumer 不多：

- NAT 压力不一定大

如果 API 数量很多，同时 consumer project、客户端实例、接入方很多：

- NAT subnet 容量会变得重要

### 2. 请求是不是短连接为主

如果是：

- 移动端
- 外部系统集成
- 没有良好 keep-alive

那么：

- 同样的 QPS 会消耗更多连接
- NAT subnet 更容易成为瓶颈

### 3. 是否走 HTTP/2 / gRPC / 长连接

如果大量流量是：

- HTTP/2
- gRPC
- 长连接 keep-alive

那么：

- 一个连接上能跑很多 request
- PSC NAT 端口的压力会小得多

### 4. 请求平均耗时

如果请求耗时长：

- 连接被占用时间更长
- 相同 QPS 需要更多并发连接

如果请求耗时短：

- 相同连接可以更快复用
- NAT 压力相对小

---

## 19.6 一个更实用的评估方法

对于 API 平台，可以先用下面这个近似方法做一轮 sizing：

### 第一步：估算并发请求数

```text
Concurrent Requests ≈ QPS × 平均请求耗时（秒）
```

例如：

- `QPS = 50,000`
- `平均耗时 = 200ms = 0.2s`

那么：

```text
Concurrent Requests ≈ 50,000 × 0.2 = 10,000
```

### 第二步：估算连接复用率

再乘一个“连接复用系数”：

- 短连接差模型：接近 `1`
- 普通 keep-alive：可能 `0.2 ~ 0.5`
- HTTP/2 / gRPC：可能更低

例如：

```text
Concurrent TCP Connections ≈ Concurrent Requests × Connection Factor
```

如果：

- `Concurrent Requests = 10,000`
- `Connection Factor = 0.5`

那么：

```text
Concurrent TCP Connections ≈ 5,000
```

然后再对照 PSC NAT 容量公式：

```text
NAT_IP_Count × 63,488
```

看 attachment subnet 是否足够。

---

## 19.7 对 `/28`、`/26`、`/25`、`/24` 的平台级理解

### `/28`

- 约 `12 usable NAT IPs`
- 理论连接上限约 `761,856`

适合：

- 小型 attachment
- 内部低流量服务
- 少 consumer
- 长连接为主

不适合作为默认生产入口：

- 平台共享 API
- 外部接入型服务
- 高 churn 短连接流量

### `/26`

- 约 `60 usable NAT IPs`
- 理论连接上限约 `3.81M`

适合：

- 中等规模 attachment
- 普通生产服务
- 有一定增长空间的内部 API 域

### `/25`

- 约 `124 usable NAT IPs`
- 理论连接上限约 `7.87M`

适合：

- 普通生产 attachment 默认值
- 较多 consumer
- 请求模式不完全可控的 API 服务

### `/24`

- 约 `252 usable NAT IPs`
- 理论连接上限约 `15.99M`

适合：

- 平台级共享入口
- 高租户聚合服务
- 高并发短连接模型
- 明确预期会扩张的 attachment

---

## 19.8 真正的瓶颈顺序

在 API 平台里，真实瓶颈通常按下面顺序出现：

1. **后端服务 / NEG / 应用线程池**
2. **L7/L4 Load Balancer**
3. **客户端连接模型**
4. **PSC NAT 子网容量**

但如果你的场景是：

- consumer 多
- 外部接入多
- 短连接多
- attachment 被大量 tenant 共用

那么第 4 点会明显提前出现。

所以 PSC NAT subnet 规划的价值在于：

- 提前避免“服务看起来不忙，但新连接接不进来”的问题

---

## 19.9 Quota 视角下怎么落地

建议你把 PSC 容量管理拆成三类 quota：

### A. Address Quota

看的是：

- 这个 attachment 分到了多少 NAT IP
- 剩余多少可扩容空间

### B. Connection Quota

看的是：

- `NAT_IP_Count × 63,488`
- 当前活跃连接接近了多少比例

### C. Consumer Quota

看的是：

- 接入的 consumer endpoint / backend 数量
- 每个 consumer 是否需要单独 connection limits

这三类 quota 一起看，才是 PSC attachment 的真实容量画像。

---

## 19.10 对你们平台的建议

如果你们的平台：

- 运行上千条 API
- 有多租户或多 consumer
- 并且未来很可能出现流量集中在少数入口 attachment

那么建议：

- 小服务可以继续 `/28`
- 普通生产 attachment 默认 `/25`
- 共享入口、平台入口默认 `/24`
- 不要把所有 attachment 都等价对待
- 对热点 attachment 预留“追加第二个 NAT subnet”的策略

### 一个非常实用的判断标准

如果某个 attachment 满足下面任一条件，就不要从 `/28` 起步：

- 面向大量外部 consumer
- 预期高并发短连接
- 作为平台共享 API 入口
- 很难预测增长上限

这类 attachment 应该至少：

- `/25` 起步

甚至直接：

- `/24` 起步
