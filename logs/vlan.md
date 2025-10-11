# **gcloud compute interconnects attachments list**

#  **详解 + 什么是 VLAN（面向 GCP Interconnect 的角度）**

下面把命令拆解、常用参数、典型输出字段、排查示例都讲清楚；然后再从网络层解释 VLAN（802.1Q）概念、为什么在 GCP Interconnect/Attachment 场景下会频繁看到 VLAN id（vlanTag8021q）以及需要注意的点。

---

# **1. 命令用途（一句话）**

gcloud compute interconnects attachments list 用来列出 **某个项目/区域下的 VLAN Attachment（VLAN 附着/attachment）** —— 也就是连接到某个 Interconnect（Dedicated/Partner）的逻辑接口，每个 attachment 通常对应一个 VLAN tag + 对应的 Cloud Router BGP 会话，用于把流量引入/引出 GCP VPC。

---

# **2. 常见用法 & 参数示例**

基本语法：

```
gcloud compute interconnects attachments list \
  --project=<HOST_PROJECT> \
  --region=<REGION> \
  --filter='<FILTER_EXPR>' \
  --format='<FORMAT>'
```

常用例子：

- 列出某 project、某 region 下的 attachments（表格形式）：

```
gcloud compute interconnects attachments list \
  --project=aibang-1231231-vpchost-eu-prod \
  --region=europe-west2 \
  --format="table(name,interconnect,router,vlanTag8021q,edgeAvailabilityDomain)"
```

- 输出 JSON（方便用 jq 解析）：

```
gcloud compute interconnects attachments list \
  --project=aibang-1231231-vpchost-eu-prod \
  --format=json | jq .
```

- 按 VLAN id 过滤：

```
gcloud compute interconnects attachments list \
  --project=... \
  --filter='vlanTag8021q=1234' \
  --format="table(name,region,interconnect,router,vlanTag8021q)"
```

- 查看某个 attachment 的完整详情（建议在定位到 name 后使用）：

```
gcloud compute interconnects attachments describe <ATTACHMENT_NAME> \
  --project=<HOST_PROJECT> --region=<REGION> --format=json | jq .
```

---

# **3. 常见输出字段（说明 + 如何解读）**

> **注意**：不同 gcloud / API 版本返回的字段名可能会有细微差别。建议使用 --format=json 或 describe 来查看完整字段，并以你当前环境的真实字段为准。下面给出常见且最有用的字段说明（示例化说明）：

示例 JSON（仅示意）：

```
{
  "name": "aibang-1231231-vpchost-eu-prod-vpc1-eqld6-z2-3b",
  "id": "1234567890123456789",
  "region": "europe-west2",
  "interconnect": "aibang-1231231-vpc-europe-prod-eqld6-z2-3",
  "router": "uk-cloud-router-01",
  "vlanTag8021q": 2001,
  "ipAddress": "10.72.22.3",            // 接口分配的对端/本端 IP（字段名可能不同）
  "edgeAvailabilityDomain": "AVAILABILITY_DOMAIN_1",
  "type": "DEDICATED" | "PARTNER",      // 视情况（示意）
  "pairingKey": "..."                   // partner interconnect 可能会有
}
```

字段解释（重点）：

- name：attachment 的唯一名字 —— 日志中 src_gateway.name 常就是这个值。
- region：attachment 所在的 GCP 区域（region）。
- interconnect：指向该 attachment 所属的 Interconnect（物理链路/配置）。
- router：关联的 Cloud Router 名称 —— BGP 会话通过此 router 建立并学习/交换路由。
- vlanTag8021q：**关键字段**，表示该 attachment 对应的 VLAN ID（802.1Q）。这是 carrier/对端用来区分不同客户/通道的 VLAN tag。
- ipAddress（如果存在）：attachment 接口上的 IP 地址（BGP 邻居用到的地址）。并非所有环境字段名完全相同，建议 describe 查看真实字段。
- edgeAvailabilityDomain：attachment 在同一区域内的可用域（与物理交换机相关）。
- type / pairingKey：Partner Interconnect 时会出现 partner 相关的元数据（如 pairing key、合作方信息）。

---

# **4. 如何快速用命令把** 

# **10.72.22.3**

#  **映射到 attachment（排查套路）**

1. 在 Host Project（Shared VPC 的宿主工程）查看 flow logs（或直接看你已有的 log）中 src_gateway.name 对应的 attachment name。
2. 用 describe 查看该 attachment 详情并确认 vlanTag8021q、ipAddress、router 等信息：

```
gcloud compute interconnects attachments describe aibang-1231231-vpchost-eu-prod-vpc1-eqld6-z2-3b \
  --project=aibang-1231231-vpchost-eu-prod --region=europe-west2 --format=json | jq .
```

3. 如果需要确认 BGP / 路由对端信息：

```
gcloud compute routers describe uk-cloud-router-01 --project=aibang-1231231-vpchost-eu-prod --region=europe-west2 --format=json | jq .
# 或者查看 router 状态
gcloud compute routers get-status uk-cloud-router-01 --project=... --region=europe-west2
```

4. 如果你只想用 list 找到包含某 IP 的 attachment（取决于字段名是否存在）：

```
gcloud compute interconnects attachments list --project=<HOST_PROJECT> --format=json \
  | jq '.[] | select(.ipAddress=="10.72.22.3")'
```

> 若 ipAddress 字段不存在，改用 describe 并手动 grep/解析。

---

# **5. VLAN（802.1Q）概念（简明 + 与 GCP 的关系）**

## **VLAN（802.1Q）基础**

- VLAN（Virtual LAN）是 L2（第 2 层）分隔不同广播域的技术，通常通过 **802.1Q tag** 在以太帧中插入 4 字节的 VLAN 标记来区分不同虚拟网络。
- VLAN ID 范围：**1–4094**（0 和 4095 保留）。
- 802.1Q 会在以太帧中插入一个标记（Tag）包含 VLAN ID；这就区分了不同租户/不同逻辑网络的流量。
- **Trunk port**：携带多个 VLAN（打标签的链路）。
- **Access port**：通常属于某个 VLAN（不打标签，或会被 switch 在入口处打上标签）。

## **VLAN 对 MTU 的影响**

- 802.1Q tag 增加 4 字节，会影响路径上的 MTU（需要考虑或调整 FRAGMENT / PMTU）。

## **Q-in-Q（802.1ad）**

- provider 做二层封装（在 customer 的 tag 外再加 provider tag），用于隔离租户或实现多层 VLAN。

---

# **6. 在 GCP Interconnect 场景中，VLAN（**

# **vlanTag8021q**

# **）代表什么？**

- 每个 **VLAN Attachment** 在 GCP 侧会分配一个 VLAN tag（vlanTag8021q）。对端（on-prem 或 partner）必须在对等端把对应的 VLAN tag 绑定到客户线路上。
- VLAN 用于把物理/逻辑链路上的流量“分桶”到某个 attachment：换言之，**带有该 VLAN tag 的流量会被送到对应的 GCP attachment，然后由 GCP 的 Cloud Router 将流量引导到对应的 VPC/subnet**。
- **BGP session**：attachment 通常会和 Cloud Router 建立 BGP 邻居（使用该 attachment 的接口 IP）。路由的传播基于 BGP，流量按路由表转发到 VPC。

简单示意图（Mermaid）：

```
graph LR
    OnPrem[On-Prem Switch] ---|Tagged VLAN 2001| Carrier
    Carrier ---|VLAN 2001| GCP_Attach[VLAN Attachment (vlanTag8021q=2001)]
    GCP_Attach --> CloudRouter[Cloud Router]
    CloudRouter --> SharedVPC[Shared VPC Subnet -> VM]
```

---

# **7. Dedicated vs Partner Interconnect（和 VLAN 的关系）**

- **Dedicated Interconnect**：你直接向 GCP 申请物理链路，并在 GCP 控制台/CLI 创建 attachment，指定 VLAN tag。
- **Partner Interconnect**：通过合作伙伴接入，partner 会代为创建/配置 VLAN attachment，通常会暴露 pairingKey、partner metadata 给你来对接。
- 无论哪种方式，**VLAN tag 都是关键“区分通路”的标识**。

---

# **8. 权限 / IAM（谁可以 run 这些命令）**

- 查看/列出 Attachment 一般需要具备网络相关只读权限：如 roles/compute.networkViewer（或 roles/compute.viewer）以及/或更高的 roles/compute.networkAdmin。
- 如果收到权限错误，检查是否拥有 compute.interconnectAttachments.list、compute.routers.get 等权限。

---

# **9. 实战常见问题 & 诊断建议**

- **日志里看到 src_gateway.type = "INTERCONNECT_ATTACHMENT"，但 instances list 找不到 IP** → 说明流量源自 attachment（对端或中转），不是 GCE VM。使用 attachments describe + 查看 vlanTag8021q 与 ipAddress 来确认。
- **对端 IP 与 attachment IP 不一致** → 对端可能是后端网络（on-prem）或另外一个 region 的 VM；检查 router 的 BGP learned routes。
- **MTU 导致分包/性能问题** → 考虑 802.1Q tag 会增加 4 字节，确认路径 MTU（尤其当使用 GRE/VXLAN/双标签时要更谨慎）。
- **Partner Interconnect 出现 pairing 问题** → 与 partner 对接时，核对 pairingKey、VLAN id、对端设备是否已按约定打 tag。

---

# **10. 快速命令清单（拷贝即用）**

```
# 1) 列所有 attachments（表格）
gcloud compute interconnects attachments list \
  --project=<HOST_PROJECT> \
  --region=<REGION> \
  --format="table(name,interconnect,router,vlanTag8021q,edgeAvailabilityDomain)"

# 2) 详细 describe（JSON）
gcloud compute interconnects attachments describe <ATTACHMENT_NAME> \
  --project=<HOST_PROJECT> --region=<REGION> --format=json | jq .

# 3) 查 router（查看 BGP peers / learned routes）
gcloud compute routers describe <CLOUD_ROUTER_NAME> \
  --project=<HOST_PROJECT> --region=<REGION> --format=json | jq .

# 4) 查 router 的运行状态（BGP 状态）
gcloud compute routers get-status <CLOUD_ROUTER_NAME> --project=<HOST_PROJECT> --region=<REGION>

# 5) 在 Host Project 用 Logging 查 flow logs（找来源 IP）
gcloud logging read 'resource.type="gce_subnetwork" AND jsonPayload.connection.src_ip="10.72.22.3"' \
  --project=<HOST_PROJECT> --limit=50 --format=json

# 6) 检查某 IP 是否属于某实例（service project）
gcloud compute instances list --filter="networkInterfaces.networkIP=10.72.22.3" --project=<SERVICE_PROJECT> --format=json
```

---

# **11. 总结（快速记忆点）**

- interconnect attachment = GCP 侧的 **VLAN/逻辑接口**，用来把物理 Interconnect 上的某个 VLAN 对接到 Cloud Router / Shared VPC。
- vlanTag8021q 是 key：它标识“这条 VLAN 的流量进来后应进入哪个 attachment”。
- 在跨 Project/Shared VPC 场景中，大多数 **网络级的日志/flow logs 在 Host Project**（Shared VPC 的宿主工程），要在 Host Project 去查。
- 如果日志里 src_gateway 是 attachment，说明该流量并非直接来自 GCE VM，而是来自对端/Interconnect。

---

如果你愿意，我可以继续帮你：

- 把你当前的 Host Project 的 interconnects attachments list 输出格式化为 CSV/BigQuery schema（便于导入中央日志表）。
- 或者基于你当前的日志样本（把 src_gateway 的 JSON 发来）我帮你逐字段解析并画一个针对你环境的拓扑图与排查步骤（包含具体 gcloud 命令序列）。
