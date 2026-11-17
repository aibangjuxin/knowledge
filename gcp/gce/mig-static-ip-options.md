# 让 MIG / Instance 拥有静态 IP:GCP 全路径评估(含双网卡 MIG)

> **一句话结论**:GCP 提供了 **7 条**能让 MIG 实例拿到固定 IP 的路径,能力差异很大。结合 NHF 的实际约束(双网卡、Shared VPC、只需 2 个 IP、iptables 不吃 CPU),**推荐组合是:statefulPolicy(只声明 nic0)+ per-instance config(逐实例绑定)+ regional MIG 关闭 proactive redistribution**。
>
> **三个此前遗漏、但会直接导致方案失败的关键点**:
> 1. **双网卡 MIG 完全支持按网卡固定 IP** —— statefulPolicy 的 `internalIPs` 是**按网卡名( nic0 / nic1 )分别声明**的,官方就有多网卡示例。你要的"只固定其中一块网卡"是原生支持的,不需要任何 hack。
> 2. **regional MIG 必须关掉 proactive redistribution**(`--instance-redistribution-type NONE`)。它**默认开启**,会为了均衡 AZ 分布而**主动删除实例** —— 这会连带销毁你的 stateful IP 绑定。**这条不做,前面的配置全部白做。**
> 3. **instance template 的 `networkIP` 在 MIG 里不可用** —— 所有实例会抢同一个地址,只有一台能起来。这是最容易踩的坑。
>
> **关于你说的"UIG"**:如果指的是 **Unmanaged Instance Group(非托管实例组)**,那它确实是这个选项空间里的一个正式候选 —— 静态 IP 完全可控,但代价是 autoheal / 滚动更新 / autoscaling **全部失去**。本文 §5.6 有专门评估。

---

## 1. 需求与约束(更新版)

| 项 | 值 / 约束 | 来源 |
| --- | --- | --- |
| 组件 | NHF:Shared VPC 上的 GCE **MIG**,双网卡 + iptables 做 L3 NAT | `~/git/gcp/linux/networking/nhf.md` |
| 网卡 | **nic0** = ens4 = Shared VPC(`10.72.x.x`,**出局源地址**)<br>**nic1** = ens5 = Private VPC(`192.168.0.x`,ILB 后端) | `nhf.md` §4.4(metadata 取 `network-interfaces/0/ip` 与 `/1/gateway`) |
| 区域类型 | **regional MIG**,europe-west2,跨 AZ | `nhf.md` §3 |
| 目标 | DRN 侧按**固定 IP 清单**授权白名单,而不是按网段 | 本次需求 |
| **规模** | **iptables 转发不吃 CPU,单个 vCPU 足够 → 只需 2 个 IP**(2 台实例) | 本次需求(新增,直接改变方案取舍) |
| 地址归属 | `10.72.x.x` 来自**公司内部 Shared VPC 既有子网**;**不能另划新网段**;但**可以预留静态 IP** | 本次需求(前一轮确认) |
| 现状约束 | stateful 与 autoscaler 互斥;NHF 不依赖弹性伸缩 | `gcp/gce/stateful-mig-and-autoscaling.md` |

> 💡 **"只需 2 台"这个新事实的杀伤力**:它让"失去 autoscaling"从一个需要论证的取舍,变成**一个几乎无痛的让步** —— 出网组件的容量取决于**峰值并发连接数**,不取决于 CPU,也就不需要跟着负载抖。同时它让 **UIG(非托管实例组)** 从"不推荐"变成了"值得认真评估的候选"。

---

## 2. 术语:双网卡 MIG 里的网卡命名

这是理解你问题的前提 —— GCP 里网卡的编号**不是按 ens4/ens5 这种系统命名**,而是按**创建顺序**:

> "The first interface is always created as **nic0**, and it is always the **default interface**."[1]

| 概念 | NHF 的对应 | 说明 |
| --- | --- | --- |
| **nic0** | **ens4** / eth0 | 第一块网卡 = **默认网卡**。NHF 这里是 **Shared VPC**(出局面,`10.72.x.x`)。**默认路由走 nic0** |
| **nic1** | **ens5** / eth1 | 第二块网卡 = Private VPC(`192.168.0.x`),ILB 后端面 |

**两条必须知道的细节**:

1. **只有 nic0 有内部 DNS 记录** —— "Compute Engine creates internal DNS name A and PTR records only for the primary internal IPv4 address of the **nic0** network interface of an instance."[2] → 不影响 SNAT 源地址,但排查 DNS 时别找错网卡。
2. **metadata 的路径与网卡编号一致** —— `network-interfaces/0/ip` = nic0,`network-interfaces/1/gateway` = nic1。`nhf.md` §4.4 正是这么取的,所以 **SNAT 的源地址永远来自 nic0**。

> ✅ **结论:statefulPolicy 里 `interface-name=nic0` 精确指向 Shared VPC 出网卡,`nic1` 是 Private VPC 入口网卡。** 这正是"只固定一块网卡"所需要的粒度。

---

## 3. 全路径评估总表

| # | 路径 | 粒度 | 抗重建 | 保留 autoheal | 保留滚动更新 | 保留 autoscaling | 改造量 | 评价 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **1** | **statefulPolicy(组级)** | 每网卡自动 | ✅ | ✅ | ✅ | ❌ | 极小 | ★★★★★ **推荐作为底座** |
| **2** | **per-instance config** | 每实例指定地址 | ✅ | ✅ | ✅ | ❌ | 小 | ★★★★★ **推荐作为精确绑定** |
| **3** | `create-instance`(带 stateful IP) | 每实例指定地址 | ✅ | ✅ | ✅ | ❌ | 小 | ★★★★☆ 适合**从零建** MIG |
| **4** | instance template `networkIP` | —— | ❌ | ✅ | ✅ | ✅ | —— | ❌ **MIG 里不可用**,见 §5.4 |
| **5** | alias IP range + 启动脚本 | 每实例自取 | ✅(脚本保证) | ✅ | ⚠️ | ✅ | **大(改脚本)** | ★★☆☆☆ 需改 `abj-nat.sh`,见 §5.5 |
| **6** | **UIG(非托管实例组)** | 每实例完全手工 | ❌ | ❌ | ❌ | ❌ | 中 | ★★★☆☆ **可行但要自建自愈**,见 §5.6 |
| **7** | 托管 NAT(Private NAT) | 网关级 | ✅ | ✅ | ✅ | ✅ | **极大** | ★★☆☆☆ 换架构,见 §5.7 |

---

## 4. 你的核心问题:双网卡 MIG 怎么只固定一块网卡

### 4.1 答案:statefulPolicy 的 `internalIPs` 本来就是按网卡分别声明的

官方 statefulPolicy 结构体(多网卡示例,`nic0` 与 `nic1` 并列):

```json
{
  "statefulPolicy": {
    "preservedState": {
      "internalIPs": {
        "nic0": { "autoDelete": "ON_PERMANENT_INSTANCE_DELETION" },
        "nic1": { "autoDelete": "ON_PERMANENT_INSTANCE_DELETION" }
      },
      "externalIPs": {
        "nic0": { "autoDelete": "ON_PERMANENT_INSTANCE_DELETION" }
      }
    }
  }
}
```

> "**NI_NAME**: (Required) Network interface name. **The primary network interface is named nic0. If you have multiple network interfaces, you can specify multiple NI_NAMES.**"[3]

→ **在双网卡 MIG 上,`--stateful-internal-ip=interface-name=nic0` 只声明 nic0 的内网 IP 为 stateful,nic1 完全不受影响。** 这就是你要的粒度,原生支持。

### 4.2 NHF 应该怎么配(为什么只固定 nic0)

| 网卡 | 子网 | 角色 | 要不要 stateful | 理由 |
| --- | --- | --- | --- | --- |
| **nic0**(ens4) | Shared VPC `10.72.0.0/18` | **SNAT 出口面,源地址在这里** | ✅ **必须固定** | 它就是白名单要填的值 |
| **nic1**(ens5) | Private VPC `192.168.0.0/18` | ILB 后端入口面 | ❌ **保持临时** | ILB 按健康实例分发,后端地址不需要固定;固定了反而增加约束 |

```bash
# 只固定 nic0(Shared VPC 出网卡);nic1 不出现在声明里
gcloud compute instance-groups managed update <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=europe-west2 \
  --stateful-internal-ip=interface-name=nic0,auto-delete=never
```

### 4.3 逐实例精确绑定(同样是按网卡)

```bash
gcloud compute instance-groups managed instance-configs create <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=europe-west2 \
  --instance=<INSTANCE_NAME> \
  --stateful-internal-ip=address=10.72.x.y,interface-name=nic0,auto-delete=never
```

官方示例同时演示了跨网卡组合(一个 internal 落在 nic0、external 落在 nic1)[4]:

> "To create a per-instance config with a stateful internal IP 192.168.0.10 … on instance my-instance, run: `gcloud compute instance-groups managed instance-configs create my-group --instance=my-instance --stateful-internal-ip=address=192.168.0.10`"

### 4.4 从零建 MIG 时可以一次性声明

```bash
gcloud compute instance-groups managed create <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=europe-west2 \
  --template=<NHF_TEMPLATE> \
  --size=2 \
  --stateful-internal-ip=interface-name=nic0,auto-delete=never \
  --instance-redistribution-type=NONE \
  --update-policy=most-disruptive-allowed-action=REPLACE,max-surge=0,max-unavailable=1,replacement-method=RECREATE
```

---

## 5. 逐条路径详解

### 5.1 路径 1:statefulPolicy(组级)—— 推荐作为底座

**做什么**:声明"本组所有实例的 nicX 内网 IP 都是 stateful"。

**三个关键行为**:

1. **现有地址原地提升** —— "For existing instances, the MIG promotes in-use ephemeral internal or external IP addresses to static addresses by **reserving** the corresponding static IP addresses."[5] → **地址不变,零中断**。
2. **自动应用** —— "The MIG automatically applies your stateful policy configuration to new and existing instances."[6] → 不用手动逐台操作。
3. **不打断运行中实例** —— "Updates to a stateful policy do not disrupt running virtual machine (VM) instances."[6]

**局限**:只能"让所有实例的 nic0 都 stateful",**不能指定"哪台用哪个地址"** → 需要配合路径 2。

**NHF 用法**:第一步就把当前 4~2 个地址固化,白名单立刻可以提交;之后再用路径 2 精确绑定。

### 5.2 路径 2:per-instance config(实例级)—— 推荐作为精确绑定

**做什么**:把**指定的预留地址**钉到**指定实例**(按实例名)。

**为什么必须用它**:白名单要的是一份**确定的清单**,而不是"这组实例当前碰巧用的地址"。per-instance config 让清单**可预测、可审计、可复现**。

**存储位置**:`preservedStateFromConfig`。**优先级高于 statefulPolicy**(官方:"A managed instance's per-instance configuration takes priority over conflicting configuration in the instance template or in a stateful policy.")[6]

**回退规则**:"If you remove the stateful configuration of a resource from a per-instance configuration, and you configured the same resource in the stateful policy, then the resource remains stateful according to the stateful policy."[6]

> 💡 **组级 + 实例级配合的正确姿势**:
> - 组级 statefulPolicy(nic0)→ 保证**兜底**:即使某台实例漏了 per-instance 配置,它的 nic0 依然是 stateful,不会变回随机地址;
> - per-instance config → 保证**精确**:这 2 台明确绑定在 `10.72.x.y` / `10.72.x.z`。
> - 两层不冲突:per-instance 覆盖 policy 的同项,policy 兜底 per-instance 的缺项。

### 5.3 路径 3:`create-instance` —— 从零建 MIG 时最干净

这是一个**专门用于"MIG 内创建带 stateful 配置的指定名称实例"**的命令,很多人不知道:

```bash
gcloud compute instance-groups managed create-instance <MIG> \
  --project=$SERVICE_PROJECT --region=europe-west2 \
  --instance=<INSTANCE_NAME> \
  --stateful-internal-ip=address=10.72.x.y,interface-name=nic0,auto-delete=never
```

**官方行为**:

> "creates a virtual machine instance with a defined name and optionally its stateful configuration: stateful disk, stateful metadata key-values, and stateful IP addresses. Stateful configuration is stored in the corresponding newly created per-instance config. An instance with a per-instance config will preserve its given name, specified disks, specified metadata key-values, and specified internal and external IPs during instance recreation, auto-healing, updates, and any other lifecycle transitions of the instance."[4]

**关于地址是否要先预留**:

> "**If the provided IP address is reserved**, the group assigns the reservation to the instance. **If the provided IP address is not yet reserved**, the managed instance group automatically creates the corresponding IP address reservation."[4]

→ **两种都行**:可以先 `compute addresses create` 预留好(推荐,地址归属清晰),也可以让 MIG 自动创建预留。

**适用场景**:NHF 如果要**重建**(而不是在现有 MIG 上改造),用这条最干净 —— 名字、地址、stateful 配置一次性到位。

### 5.4 路径 4:instance template 的 `networkIP` —— ❌ 在 MIG 里不可用

instance template 的 API 确实有这个字段:

> "**networkIP** | string — An IPv4 internal IP address to assign to the instance for this network interface. If not specified by the user, an unused internal IP is assigned by the system."[7]

**看起来能解决问题,但在 MIG 里是错的。** 原因:

- 模板是**所有实例共用的**。模板里写死 `10.72.x.y` → **每一台实例都要求这个地址**;
- 而一个内部 IP 在同一时刻**只能绑定给一台实例**;
- 结果:第一台起来后,第二台因为地址已被占用而**创建失败**。MIG 会反复重试、最终报错。

**结论**:`networkIP` 只适用于**单台独立实例**(`gcloud compute instances create --network-ip=...`),**不适用于 MIG**。在 MIG 里要"指定某台用某地址",唯一正确的机制就是 **per-instance config / create-instance**。

> ⚠️ 这是最容易踩的坑:看到 API 有 `networkIP` 就以为能解决 MIG 静态 IP 问题。

### 5.5 路径 5:alias IP range + 启动脚本 —— 需要改脚本的社区方案

**思路**(社区常用做法):实例从模板拿到一个**固定的 alias IP 段**,启动脚本按"实例名 → 预留地址"查表,把该地址作为 alias 绑到网卡上,SNAT 指向这个 alias 而不是 nic0 主地址。

**示意**:

```bash
# 启动脚本中(示意,非官方文档)
INSTZONE=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/zone)
ZONE=$(basename "$INSTZONE")
INSTIP=$(gcloud compute addresses list \
  --filter="name:mq01-$ZONE-ip" --format="value(address:label=address)")
gcloud compute instances network-interfaces update "$INSTNAME" \
  --zone="$ZONE" --aliases="$INSTIP/32"
ip addr add "$INSTIP/32" dev eth0
```

**优点**:不需要 stateful(因此**可以保留 autoscaler**)。

**代价(对 NHF 尤其致命)**:

| 问题 | 说明 |
| --- | --- |
| **必须改 `abj-nat.sh`** | SNAT 目标要从 `network-interfaces/0/ip` 改成那个 alias IP —— **动了核心转发脚本** |
| **启动竞态** | alias 要等启动脚本跑完才生效,期间 SNAT 可能用错地址 |
| **重建竞态** | 社区方案本身就提到:"the alias IP may already be assigned to the machine … the startup script may throw an error" |
| **回程路由** | alias IP 的回程需要额外确认可达性 |
| **可审计性差** | 地址来源是脚本查表,不是 GCP 资源状态 |

→ **不推荐**。stateful 路径能做到"零脚本改动",没必要退化到要改核心脚本的方案。

### 5.6 路径 6:UIG(Unmanaged Instance Group,非托管实例组)

**这就是你说的"UIG"。它是这个选项空间里的正式候选,不是伪概念。**

**它是什么**:一个"篮子",你把**自己创建**的实例放进去。它**不使用 instance template**。

**官方定位**:

> "A managed instance group (MIG) is a group of virtual machine (VM) instances that you treat as a single entity. Each VM in a MIG is based on an instance template."[8]
> "Although Compute Engine has both managed and unmanaged instance groups, **only managed instance groups can be used with an autoscaler**."[9]

**UIG 在本场景的能力与代价**:

| 维度 | UIG | MIG(stateful) |
| --- | --- | --- |
| 静态 IP 完全可控 | ✅ **最强** —— 你自己 `instances create --address=10.72.x.y`,地址从创建那刻就是你的 | ✅ 同样可控(per-instance config) |
| 实例名可控 | ✅ | ✅ |
| autoheal(自愈重建) | ❌ **没有** —— 实例挂了要你自己发现并重建 | ✅ 有 |
| 滚动更新 | ❌ | ✅ |
| autoscaling | ❌ | ❌(与 stateful 互斥) |
| 重建后地址保持 | ⚠️ **要自己保证** —— 你重建时必须再传同一个 `--address` | ✅ **平台保证** |
| ILB 后端组 | ✅ 可以做 ILB 后端 | ✅ |

**评估**:对于 NHF 这种**必须有 HA(不能单点)**的出网组件,UIG 的致命短板是 **autoheal 没了** —— 实例故障后,它的那个静态 IP 会"失联",而你需要人工介入才能恢复。**NHF 有 2 台,两台都靠人工盯着,这是不可接受的运维退化。**

> ✅ **但 UIG 在一个变体场景下很有价值**:如果把 MIG 缩到 **1 台** 单实例(放弃 ILB 后端组和 HA),那么 UIG 就变得合理 —— 地址绝对可控、无自动伸缩、运维简单。**代价是单点。**

### 5.7 路径 7:托管 NAT(Private NAT / Cloud NAT)—— 换架构

用托管服务取代自建 iptables NAT。**详细评估见 `linux/network/nhf-static-egress-ip.md` §7**。要点重述:

- **Private NAT** 支持 VPC ↔ on-premises,且 NAT 地址可预留指定 → 天然"单 IP";
- 但**不支持 auto mode VPC**、**仅 TCP/UDP**、需重做回程路由与 GCP 侧收口模型;
- **Cloud NAT** 源地址是公网 IP,与当前"Shared VPC → 办公网出口 → DRN"的路径模型不兼容。

→ **除非"必须恰好 1 个 IP"是硬性合规要求**,否则不建议。

---

## 6. 关键补充:stateful regional MIG 的两个必做项

> ⚠️ **这一节是本文相对既有文档最重要的增量。** NHF 是 **regional MIG**,而 regional MIG 有两个默认行为会**破坏 stateful 绑定**。

### 6.1 必做项 A:关闭 proactive redistribution

**官方限制原文**:

> "A MIG with stateful configuration — a stateful MIG — has the following limitations:
> - You cannot use autoscaling if your MIG has stateful configuration.
> - **If you want to use automated rolling updates, you must set the replacement method to RECREATE.**
> - **For stateful regional MIGs, you must disable proactive redistribution (set the redistribution type to NONE) to prevent deletion of instances with stateful workloads.**"[10]

**为什么这条是"必做"**:

> "**Proactive instance redistribution is turned on by default for regional MIGs.**"[11]
> "Turning off proactive instance redistribution is useful if you need to: […] **Protect VMs with stateful workloads from unwanted automatic deletion due to proactive redistribution.**"[11]

→ regional MIG 默认会为了**让各 AZ 的实例数均匀**而**主动删除并重建**多出来的实例。对普通 MIG 这是好事(保证均衡);对 stateful MIG,**它删掉的正是你精心绑定好的那台** → 地址预留被释放 → 白名单出现空洞。

**处置**:

```bash
gcloud compute instance-groups managed update <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=europe-west2 \
  --instance-redistribution-type=NONE
```

> 注:官方文档说明,非 autoscaled 的 regional MIG(或 mode 为 `OFF` / `ONLY_SCALE_OUT` 的 autoscaled MIG)用 `regionInstanceGroupManagers.patch` 即可;**mode 为 `ON` 的 autoscaled regional MIG 需要走 beta 端点**。NHF 删掉 autoscaler 后用普通 `update` 即可。

### 6.2 必做项 B:滚动更新用 `recreate`

官方原文见上:"**If you want to use automated rolling updates, you must set the replacement method to RECREATE.**"

- `RECREATE` → **保留实例名** → per-instance config 按名重放 → **地址不变**;
- `SUBSTITUTE` → 换新名 → 绑定关系丢失 → **地址漂移**。

### 6.3 两个必做项合并后的完整更新参数

```bash
gcloud compute instance-groups managed set-instance-template <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=europe-west2 \
  --template=<NEW_TEMPLATE> \
  --instance-redistribution-type=NONE \
  --update-policy=most-disruptive-allowed-action=REPLACE,max-surge=0,max-unavailable=1,replacement-method=RECREATE
```

**三个参数各自的理由**:

| 参数 | 值 | 理由 |
| --- | --- | --- |
| `instance-redistribution-type` | `NONE` | 否则主动再分布会删掉带 stateful 的实例(§6.1) |
| `replacement-method` | `RECREATE` | 保留实例名 → 绑定关系保住(§6.2) |
| `max-surge` | `0` | surge 会临时多出一个**无绑定的实例**(新名字),它的随机 IP 不在白名单里 → 部分连接被拒 |
| `max-unavailable` | `1` | 同一时刻少一台健康后端;**容量前提:2 台里少 1 台时,剩下那台能扛住峰值出网量** |

> ⚠️ **规模从 4 缩到 2 时要特别注意容量**:之前 `max-unavailable=1` 意味着 4 台里有 3 台扛;缩到 2 台后,1 台扛全部。**请先按峰值并发连接数核实单台承载能力**(iptables 转发本身不吃 CPU,瓶颈通常在 conntrack 表项数与带宽,而非 CPU)。

### 6.4 顺带一个相关的 autoscaling 限制

最新的 autoscaling 限制清单还多了一条:

> "You cannot use autoscaling with the following instance groups …: Unmanaged instance groups · **MIGs with stateful configuration** · MIGs with VM repairs turned off · **Regional MIGs with a target distribution shape of ANY or ANY_SINGLE_ZONE**"[9]

→ **stateful 的 regional MIG 只能用 `BALANCED` 分布形状**;若想用 `ANY` / `ANY_SINGLE_ZONE`,就不能同时开 stateful。NHF 是固定 2 台跨 AZ,`BALANCED` 正是想要的语义。

---

## 7. 针对"只需 2 个 IP"的最终建议

### 7.1 结论

**方案:保持 MIG(2 台)+ stateful(nic0)+ per-instance 精确绑定 + 关闭 proactive redistribution + 删 autoscaler 改固定 size。**

**为什么这是最优解**:

| 候选 | 评价 |
| --- | --- |
| **MIG + stateful(推荐)** | 地址精确可控 ✅ / autoheal ✅ / 滚动更新 ✅ / 多 AZ ✅ / 改一行 stateful 配置 + 一个 redistribution 参数 ✅ |
| UIG(2 台) | 地址可控 ✅ / **autoheal ❌** / 滚动更新 ❌ / 需自建自愈 ❌ |
| 单实例 + 预留 IP | 地址可控 ✅ / **单点,NHF 挂了全断** ❌ |
| Private NAT | 地址可控 ✅ / **要重做路由与收口模型** ❌ |
| 不改,按网段授权 | 白名单仍要填 `10.72.0.0/18`(含无关资产) ❌ |

### 7.2 执行序列

```bash
HOST_PROJECT=<SHARED_VPC_HOST_PROJECT>
SERVICE_PROJECT=<NHF_MIG 所在项目>
REGION=europe-west2

# ── 0) 取基线:当前实例的 nic0 地址 = 白名单清单初稿 ──
gcloud compute instances list --project=$SERVICE_PROJECT \
  --filter="name~<NHF_MIG>" \
  --format="table(name,zone,networkInterfaces[0].networkIP,networkInterfaces[1].networkIP)"

# ── 1) stateful 与 autoscaler 互斥 → 若有 autoscaler 先删 ──
gcloud compute instance-groups managed describe <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=$REGION \
  --format="value(autoscaler)"
gcloud compute instance-groups managed delete-autoscaler <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=$REGION

# ── 2) 固定规模(2 台) ──
gcloud compute instance-groups managed resize <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=$REGION --size=2

# ── 3) regional MIG 必做:关闭 proactive redistribution ──
gcloud compute instance-groups managed update <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=$REGION \
  --instance-redistribution-type=NONE

# ── 4) 组级 stateful:只固定 nic0,现有地址原地提升为静态(零中断) ──
gcloud compute instance-groups managed update <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=$REGION \
  --stateful-internal-ip=interface-name=nic0,auto-delete=never

# ── 5) 实例级:把具体预留地址钉到具体实例 ──
gcloud compute instance-groups managed instance-configs create <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=$REGION \
  --instance=<INSTANCE_NAME> \
  --stateful-internal-ip=address=10.72.x.y,interface-name=nic0,auto-delete=never
# (对第二台重复一次,换一个 address)

# ── 6) 验证 ──
gcloud compute instance-groups managed describe <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=$REGION \
  --format="yaml(statefulPolicy,updatePolicy)"
gcloud compute instance-groups managed instance-configs list <NHF_MIG> \
  --project=$SERVICE_PROJECT --region=$REGION \
  --format="table(name,preservedStateFromConfig)"
gcloud compute addresses list --project=$HOST_PROJECT --region=$REGION \
  --filter="name~nhf-egress" --format="table(name,address,status,users)"
```

### 7.3 白名单交付物

```
10.72.x.y     # NHF 转发实例 1(nic0 / Shared VPC)
10.72.x.z     # NHF 转发实例 2(nic0 / Shared VPC)
```

**只有 2 条**,精确到单个 IP。

### 7.4 运维纪律(缩到 2 台后更严格)

| 纪律 | 原因 |
| --- | --- |
| **实例数 ≤ 已绑定地址数** | 2 台就绑 2 个地址;多出来的实例拿不到绑定 → 随机 IP → 出网被拒 |
| **扩缩容前先绑定地址、再更新白名单** | 顺序反了会出现窗口期 |
| **不用手工删实例** | 绕过 per-instance config 的保留逻辑 |
| **保留 `auto-delete=never`** | 实例永久删除时预留不释放 |
| **保持 redistribution=NONE** | 改回 PROACTIVE 会重新引入删实例风险 |

---

## 8. 决策树

```
你要的是"固定 IP 的清单"吗?
│
├─ 是 ──► 在 MIG 里 → stateful(nic0)+ per-instance config  ★推荐
│         ├─ 顺带:删 autoscaler → 固定 size
│         ├─ 顺带:regional MIG 必须 --instance-redistribution-type NONE  ★别漏
│         └─ 顺带:滚动更新 replacement-method=RECREATE + max-surge=0
│
├─ 可以接受"按网段授权" → 什么都不改(白名单填 10.72.0.0/18)
│
├─ 要"恰好 1 个 IP" → 架构级取舍(单实例单点 / Private NAT),见 §5.7
│
└─ 想要"固定 IP + 保留 autoscaling" → ❌ 平台不支持
          └─ 唯一折中:alias IP + 启动脚本(需改 abj-nat.sh),见 §5.5
```

---

## 9. 各方案的运维负担对比

| | MIG + stateful(推荐) | UIG | 单实例 + 预留 IP | Private NAT |
| --- | --- | --- | --- | --- |
| 地址可控性 | ✅ 精确 | ✅ 精确 | ✅ 精确 | ✅ 精确 |
| 实例故障自愈 | ✅ **平台托管** | ❌ **人工** | ⚠️ 单点无自愈意义 | ✅ 平台托管 |
| 滚动更新 | ✅ 平台托管 | ❌ 人工 | ❌ 人工 | ✅ 平台托管 |
| 脚本改动 | ❌ **零** | ❌ 零 | ❌ 零 | ✅ **重写收口** |
| 路由/防火墙改动 | ❌ **零** | ❌ 零 | ❌ 零 | ⚠️ 重做 |
| 人工干预频率 | 低 | **高** | 中 | 低 |
| HA | ✅ 多 AZ | ⚠️ 手工 | ❌ 单点 | ✅ |
| 适合"只要 2 台" | ✅ | ⚠️ 可用但运维退化 | ⚠️ 单点 | ❌ 过度设计 |

---

## 10. 待确认项

| # | 待确认 | 为什么重要 | 怎么查 |
| --- | --- | --- | --- |
| 1 | **NHF 是否已配 autoscaler** | stateful 与它互斥,必须先删 | §7.2 步骤 1 |
| 2 | **NHF 当前实例数与 target size** | 决定缩到 2 台后是否需要重新绑定地址 | `describe` 的 `targetSize` |
| 3 | **单台 NHF 的峰值承载能力**(conntrack 表项数、带宽) | 缩到 2 台后 `max-unavailable=1` 意味着只剩 1 台扛,必须先核实 | 压测 + conntrack 计数 |
| 4 | **`instanceRedistributionType` 当前值** | 默认 PROACTIVE,必须改 NONE | `describe` 的 `updatePolicy` |
| 5 | **`replacementMethod` 当前值** | 必须是 RECREATE,否则滚动更新丢绑定 | `describe` 的 `updatePolicy` |
| 6 | **静态内网 IP 配额** | 预留 2~3 个地址是否超配额 | `gcloud compute regions describe <REGION> --format="value(quotas)"` |
| 7 | **地址在 host 还是 service project 预留** | 决定地址资源归属与清理责任 | `nhf-static-egress-ip.md` §6.3 |
| 8 | **对端白名单条目数上限** | 只有 2 条,通常无压力;若对方只吃 1 条则需 CIDR 聚合或架构调整 | 问 DRN 侧 |

---

## 11. 权威证据 / 最终定型依据

### 11.1 GCP 官方原文

**① 网卡编号规则**:[1]

> "The first interface is always created as nic0, and it is always the default interface."

**② 只有 nic0 有内部 DNS 记录**:[2]

> "Compute Engine creates internal DNS name A and PTR records only for the primary internal IPv4 address of the nic0 network interface of an instance."

**③ statefulPolicy 按网卡分别声明(多网卡示例)**:[3]

> "statefulPolicy": { "preservedState": { "internalIPs": { "nic0": {"autoDelete": "ON_PERMANENT_INSTANCE_DELETION"}, "nic1": {"autoDelete": "ON_PERMANENT_INSTANCE_DELETION"} }, "externalIPs": { "nic0": {"autoDelete": "ON_PERMANENT_INSTANCE_DELETION"} } } }
> "NI_NAME: (Required) Network interface name. The primary network interface is named nic0. If you have multiple network interfaces, you can specify multiple NI_NAMES."

**④ `create-instance` 与 per-instance config 的行为**:[4]

> "creates a virtual machine instance with a defined name and optionally its stateful configuration … An instance with a per-instance config will preserve its given name, specified disks, specified metadata key-values, and specified internal and external IPs during instance recreation, auto-healing, updates, and any other lifecycle transitions of the instance."
> "If the provided IP address is reserved, the group assigns the reservation to the instance. If the provided IP address is not yet reserved, the managed instance group automatically creates the corresponding IP address reservation."

**⑤ stateful IP 的原地提升**:[5]

> "For existing instances, the MIG promotes in-use ephemeral internal or external IP addresses to static addresses by reserving the corresponding static IP addresses."

**⑥ 配置应用方式与优先级**:[6]

> "The MIG automatically applies your stateful policy configuration to new and existing instances." / "Updates to a stateful policy do not disrupt running virtual machine (VM) instances." / "A managed instance's per-instance configuration takes priority over conflicting configuration in the instance template or in a stateful policy." / "If you remove the stateful configuration of a resource from a per-instance configuration, and you configured the same resource in the stateful policy, then the resource remains stateful according to the stateful policy."

**⑦ instance template 的 networkIP 字段(及其 MIG 局限)**:[7]

> "networkIP | string — An IPv4 internal IP address to assign to the instance for this network interface. If not specified by the user, an unused internal IP is assigned by the system."
> (**局限为架构推导**:模板为全组共用,同一地址无法同时绑定多台实例)

**⑧ MIG 与 UIG 的定位差异**:[8]

> "A managed instance group (MIG) is a group of virtual machine (VM) instances that you treat as a single entity. Each VM in a MIG is based on an instance template."

**⑨ autoscaling 的限制清单**:[9]

> "You cannot use autoscaling with the following instance groups, which don't allow the autoscaler to create or delete VMs according to demand: Unmanaged instance groups · MIGs with stateful configuration · MIGs with VM repairs turned off · Regional MIGs with a target distribution shape of ANY or ANY_SINGLE_ZONE"

**⑩ stateful MIG 的完整限制(含 redistribution 与 RECREATE)**:[10]

> "You cannot use autoscaling if your MIG has stateful configuration. If you want to use automated rolling updates, you must set the replacement method to RECREATE. For stateful regional MIGs, you must disable proactive redistribution (set the redistribution type to NONE) to prevent deletion of instances with stateful workloads."

**⑪ proactive redistribution 的默认开启与用途**:[11]

> "Proactive instance redistribution is turned on by default for regional MIGs." / "Turning off proactive instance redistribution is useful if you need to: … Protect VMs with stateful workloads from unwanted automatic deletion due to proactive redistribution."

### 11.2 内部资料

- **`~/git/gcp/linux/networking/nhf.md`** —— NHF 的 SNAT 规则与 metadata 取址(确定 nic0 = Shared VPC 出网卡)、回程机制(同机 conntrack)、路由表。§2、§4、§7 的判断基于此。
- **`linux/network/nhf-static-egress-ip.md`** —— NHF 场景的预留静态 IP 方案、地址数量决策、Shared VPC 归属规则。
- **`gcp/gce/stateful-mig-and-autoscaling.md`** —— stateful 与 autoscaling 的概念互斥原理。

### 11.3 本文档的核验方式

| 结论 | 核验手段 |
| --- | --- |
| 双网卡 MIG 支持按网卡固定 IP | 引用 GCP 官方多网卡 statefulPolicy 示例与 NI_NAME 说明[3] |
| nic0 = Shared VPC 出网卡 | 读 `nhf.md` §4.4:`PRIMARY_NIC_IP` 取 `network-interfaces/0/ip`,`SECONDARY_NIC_GW` 取 `/1/gateway` |
| regional MIG 必须关 redistribution | 引用 GCP 官方 stateful 限制与 redistribution 文档原文[10][11] |
| 滚动更新必须 RECREATE | 引用 GCP 官方原文[10] |
| **instance template 的 networkIP 在 MIG 里不可用** | **架构推导** —— 模板全组共用 + 内部 IP 同一时刻只能绑一台;**未实测**,建议在测试项目用 size=2 的 MIG 验证一次 |
| **缩到 2 台后单台可承载** | **待核实** —— 取决于 conntrack 表项数与带宽,见 §10 第 3 项 |
| UIG 失去 autoheal | 官方文档与实践共识:UIG 无 autoheal / rolling update / autoscaling[8][9] |

---

## 相关文档

- [`stateful-mig-and-autoscaling.md`](./stateful-mig-and-autoscaling.md) —— stateful 与 autoscaling 两个概念的详解与互斥原理
- [`static-ip.md`](./static-ip.md) —— 静态 IP 与 Cloud NAT 配置
- [`instance-groups.md`](./instance-groups.md) —— 实例组滚动替换脚本
- [`MIG-target-distribution-shape-even-to-balanced.md`](./MIG-target-distribution-shape-even-to-balanced.md) —— 分布形状与 autoscaling 的关系
- [`linux/network/nhf-static-egress-ip.md`](../../linux/network/nhf-static-egress-ip.md) —— NHF 场景的完整落地方案
- [`linux/network/nhf-egress-ip.md`](../../linux/network/nhf-egress-ip.md) —— 出局 IP 定位与白名单口径
- `~/git/gcp/linux/networking/nhf.md` —— NHF 实现细节(路由表 / 防火墙 / iptables 脚本)

---

## Sources

[1] https://cloud.google.com/compute/docs/create-use-multiple-interfaces — Create VMs with multiple network interfaces
    > "The first interface is always created as nic0, and it is always the default interface."

[2] https://cloud.google.com/compute/docs/internal-dns — Overview of internal DNS
    > "Compute Engine creates internal DNS name A and PTR records only for the primary internal IPv4 address of the nic0 network interface of an instance."

[3] https://cloud.google.com/compute/docs/instance-groups/configuring-stateful-ip-addresses-in-migs — Configuring stateful IP addresses in MIGs
    > "statefulPolicy": { "preservedState": { "internalIPs": { "nic0": {...}, "nic1": {...} }, "externalIPs": { "nic0": {...} } } } / "NI_NAME: (Required) Network interface name. The primary network interface is named nic0. If you have multiple network interfaces, you can specify multiple NI_NAMES."

[4] https://cloud.google.com/sdk/gcloud/reference/compute/instance-groups/managed/create-instance — gcloud compute instance-groups managed create-instance
    > "creates a virtual machine instance with a defined name and optionally its stateful configuration … will preserve its given name, specified disks, specified metadata key-values, and specified internal and external IPs during instance recreation, auto-healing, updates, and any other lifecycle transitions of the instance." / "If the provided IP address is reserved, the group assigns the reservation to the instance. If the provided IP address is not yet reserved, the managed instance group automatically creates the corresponding IP address reservation."

[5] https://cloud.google.com/compute/docs/instance-groups/configuring-stateful-ip-addresses-in-migs — Configuring stateful IP addresses in MIGs
    > "For existing instances, the MIG promotes in-use ephemeral internal or external IP addresses to static addresses by reserving the corresponding static IP addresses."

[6] https://cloud.google.com/compute/docs/instance-groups/how-stateful-migs-work — How stateful MIGs work
    > "The MIG automatically applies your stateful policy configuration to new and existing instances." / "Updates to a stateful policy do not disrupt running virtual machine (VM) instances." / "A managed instance's per-instance configuration takes priority over conflicting configuration in the instance template or in a stateful policy." / "If you remove the stateful configuration of a resource from a per-instance configuration, and you configured the same resource in the stateful policy, then the resource remains stateful according to the stateful policy."

[7] https://cloud.google.com/compute/docs/reference/rest/v1/instanceTemplates — InstanceTemplate API
    > "networkIP | string — An IPv4 internal IP address to assign to the instance for this network interface. If not specified by the user, an unused internal IP is assigned by the system."

[8] https://cloud.google.com/compute/docs/instance-groups — Instance groups
    > "A managed instance group (MIG) is a group of virtual machine (VM) instances that you treat as a single entity. Each VM in a MIG is based on an instance template."

[9] https://cloud.google.com/compute/docs/autoscaler/scaling-cpu-load-balancing — Autoscaling groups of instances
    > "You cannot use autoscaling with the following instance groups, which don't allow the autoscaler to create or delete VMs according to demand: Unmanaged instance groups · MIGs with stateful configuration · MIGs with VM repairs turned off · Regional MIGs with a target distribution shape of ANY or ANY_SINGLE_ZONE"

[10] https://cloud.google.com/compute/docs/instance-groups/configuring-stateful-disks-in-migs — Configuring stateful persistent disks in MIGs (Limitations)
    > "You cannot use autoscaling if your MIG has stateful configuration. If you want to use automated rolling updates, you must set the replacement method to RECREATE. For stateful regional MIGs, you must disable proactive redistribution (set the redistribution type to NONE) to prevent deletion of instances with stateful workloads."

[11] https://cloud.google.com/compute/docs/instance-groups/regional-mig-enable-disable-proactive-redistribution — Disable and re-enable proactive VM redistribution in a regional MIG
    > "Proactive instance redistribution is turned on by default for regional MIGs." / "Turning off proactive instance redistribution is useful if you need to: … Protect VMs with stateful workloads from unwanted automatic deletion due to proactive redistribution."
