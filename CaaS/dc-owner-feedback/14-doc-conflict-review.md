# 14 · Q7 · 9 份 CaaS 文档 × RFC 反向校验

> **这是什么**:拿 RFC 的硬约束,反向检查 `CaaS/` 下已有 9 份设计文档,
> **找出互相矛盾的地方** —— 也就是"你交的东西可能和自己已有的设计打架"的风险。
>
> **方法**:纯文档比对。不需要集群、不需要取数、不需要任何人配合。
> 依据:`/Users/lex/git/gcp/CaaS/rfc-cn.md` 逐条约束 vs 9 份文档的结构性声明。
>
> **结论摘要**:
>
> | 严重度 | 数量 | 说明                                       |
> | ------ | ---- | ------------------------------------------ |
> | 🔴 **阻断** | 2  | **按现在的设计,CaaS 满足不了 RFC 硬要求** |
> | 🟠 重要    | 4  | 设计可以工作,但与 RFC 表述冲突            |
> | 🟡 提示    | 3  | 命名/覆盖不一致,迟早返工                  |

---

## 🔴 C1 · `onprem` 的必填字段自相矛盾(阻断)

**两份文档直接打架:**

| 文档                 | 声明                                                                    |
| -------------------- | ----------------------------------------------------------------------- |
| `gke-caas.md` L230-238 | `required: [cloudProvider, region, tier, network, gatewayStrategy, multiTenancy]` —— **`region` 是必填** |
| `caas-onprem.md` L66    | **"没有 region/tier/network,是自建场景下的硬约束"**                    |

**问题**:如果 `region` 在 CRD 里是 required,那么 `ClusterRegistration`
(或任何 onprem 路径的资源)在 apply 阶段就会被 API Server 拒绝。
`caas-onprem.md` 声称"自建场景没有 region",但 schema 不允许。

**更糟的是 `tier`**:`tier` 的 enum 是 `["autopilot","standard"]`
—— 这是 **GCP 专属的取值**。自建集群没有 Autopilot 这个概念。
把 GCP 的概念写进四云通用 CRD,本身就是一层错误抽象。

**修复方向**:两条路,选一条:
- **A. 分成两个 CRD**(`ClusterRequest` / `ClusterRegistration`),
  各自有独立 schema —— `caas-onprem.md` 已经这么设计了,但 `gke-caas.md` 的 schema 没跟上
- **B. 用 `oneOf` / CEL 把 `cloudProvider` 与必填字段绑定**,
  单一 CRD 内按取值分支校验

**我的建议:选 A。** `caas-onprem.md` 的判断是对的(自建和公有云生命周期不同),
错的是 `gke-caas.md` 的 schema 没有体现这个区分。

---

## 🔴 C2 · 状态机与 RFC §6.2 几乎不重叠(阻断)

**RFC §6.2 的 17 个状态 / 24 条迁移**(已由源图核实):

```
Requested → Validating → {Provisioning | Discovery | Rejected}
Provisioning → Configuring → Verifying → Managed
Discovery → Assessment → OnboardingRemediation → HandoverReady → Handover → Managed
Managed → {NonCompliant | Retiring} ...
```

**`gke-caas.md` L394-401 的状态机**:

```
[*] → Pending → {QuotaBlocked | Provisioning} → Ready → [*]
```

**重叠情况:**

| RFC 状态        | 9 份文档里有吗 |
| --------------- | -------------- |
| `Requested`     | ❌             |
| `Validating`    | ❌             |
| `Configuring`   | ❌             |
| `Verifying`     | ❌             |
| `NonCompliant`  | ❌             |
| `Suspended`     | ❌             |
| `ManagedRemediation` | ❌        |
| `Retiring`      | ❌             |
| **BYOC 整条路径** | ❌ **完全没有**(Discovery/Assessment/Handover 全部缺失) |

**问题不是"名字不一样"**,而是:

1. **RFC 的状态机表达的是"合规性与移交"**(有 `NonCompliant`、有 `Suspended`、有 BYOC 全流程),
   9 份文档的状态机表达的是"**资源创建进度**"(Pending→Ready)。
   **这是两个不同维度的状态,被压成了一个。**

2. **BYOC 路径在 9 份文档里只有一个 `ClusterRegistration` 概设**,
   没有 `Discovery → Assessment → Handover` 的状态设计。
   而你确认了 DC 有几十个集群要走这条路。

3. **`QuotaBlocked` 是文档独有的,RFC 没有** —— 这其实是个**好设计**
   (配额预检查失败要能停在可恢复状态),但它需要**映射到 RFC 的某个状态**,
   否则 CaaS 报表会出现"这个集群在一个 RFC 里不存在的状态"。

**建议**:明确"两层状态"的分工:
- **层 1 · 生命周期状态**(对外,等于 RFC §6.2 的 17 状态)
- **层 2 · 资源就绪状态**(内部,`QuotaBlocked` / `Provisioning` / `Ready` 属于这层)

**一个 `ClusterRequest.status` 同时承载两层,而不是改 RFC 的状态名。**

---

## 🟠 C3 · `default: autopilot` 与 DC 现实相反(已升级为设计缺陷)

> **⚠️ 2026-09-29 更新**:DC 已确认**全部使用 Standard 模式**。
> 因此本条**不是"设计原则问题",而是"设计与现实直接矛盾"** —— 严重度实际上更高。

`gke-caas.md` L251:`tier` 的 default 是 `"autopilot"`。
L43 亦称"默认 Autopilot(golden path)"。`caas-portal.md` L212 帮助文案也写"默认 Autopilot"。

**但 DC 实际全部用 Standard。** 也就是说:**这份设计从第一天起就和 DC 的现实用法相反。**

### 三个层面的问题

| 层面           | 问题                                                                     |
| -------------- | ------------------------------------------------------------------------ |
| **① 事实**     | 设计说默认 Autopilot,DC 实际全 Standard。**第一份纳管集群就会走错分支。** |
| **② 原则**     | 即便 DC 用 Autopilot,`default:` 也不该由 CRD 定 —— 见下                |
| **③ 后果**     | Autopilot 的限制(禁 privileged / hostPath 写 / hostNetwork)会**静默继承** |

### 为什么 `default:` 本身就不该由 CRD 定

RFC §5:

> **声明意图;云厂商细节从已批准的画像中解析。** 消费方在申请集群时声明用途、环境数量、位置、
> 容量区间与所需能力;他们**不**通过一个未经校验的申请单去自行挑选管控平面配置

`default:` 的本质是"**消费方没选时,系统替他选**"—— 这恰好是 §5 禁止的行为。
**默认值应该来自画像,不是来自 schema。**

而且 `gke-caas.md` L313 有一条 CEL 规则:
```
self.tier != 'autopilot' || self.network.mode == 'private'
```
即"用 Autopilot 必须 private 网络"。

**在 `default: autopilot` 下,业务方若只填 public 网络,会在准入阶段被拒,
而他从未主动选过 Autopilot。** 这是最糟糕的一种失败:约束是隐式的,报错是显式的。

### 与 Standard 相关的连锁问题(新增)

既然确认全 Standard,下面这些**从"可选设计"变成"必须做"**:

| 能力                     | Standard 下的责任归属                      | 若无人编排会怎样              |
| ------------------------ | ------------------------------------------ | ----------------------------- |
| **节点升级策略**          | DC 必须选 surge / blue-green / blue-green  | 升级时业务中断                |
| **Cluster Autoscaler 边界** | DC 必须配 min/max                         | 伸缩失控,成本泄漏            |
| **节点池数量治理**        | 无人收敛会持续膨胀                          | **长期成本泄漏,最隐蔽**      |
| **NAP(节点自动预配)**     | 需显式配置                                  | 影响成本与弹性                |

> **CaaS 的 Node 生命周期编排从"加分项"升级为"必需项"。**
> 建议在 §8 能力目录里明确:
> `Standard 模式 → 节点层运维责任归 CaaS/DC,平台需提供编排能力`
> 这也正是 D3(能力目录需带 scope)的又一个实例。

### 建议

| 动作                                              | 谁改         |
| ------------------------------------------------- | ------------ |
| **删掉 `tier` 的 `default: "autopilot"`**          | `gke-caas.md` |
| 改为:tier 由**画像按数据分级/工作负载类别推导**     | Compute      |
| 若 DC 立场是"只支持 Standard",更简单:**enum 锁死 `["standard"]`** | `gke-caas.md` |
| 补节点层编排的 Day-2 设计                          | `caas-day2-ops.md` |

> **第三条是最省事的**:如果 DC 确定长期只用 Standard,
> 那 `tier` 根本不需要 enum,直接去掉这个字段比让它有默认值更干净。
> **但要先问清"以后会不会开 Autopilot"** —— 见 `03-gcp-capability-profile.md` §0.5 的概念澄清。


---

## 🟠 C4 · 缺少"数据分级"作为一等字段

搜索全部 9 份文档,**`dataClassification` / `data_classification` 作为一个 CRD 字段没有出现过**。
只在 `caas-compliance-baseline.md` 出现"数据分级"作为一个概念。

**RFC §7 数据类工作负载**:

> 数据体量与位置、存储类型与吞吐 / 时延、保留期、备份与恢复、数据流动、数据驻留、
> 处理规模与访问模式。| 选定满足数据驻留与恢复要求的集群及存储 / 网络画像

**RFC §9.1 BYOC 准入**:

> 应用归属方必须提供云厂商、位置、租户 / 应用清单、**Kubernetes 版本、数据分级**、
> 工作负载与依赖关系、维护窗口约束,以及当前运维模式。

**问题**:

- 数据分级缺失 → 放置校验无法判断"这个工作负载能放哪"
- 数据驻留缺失 → 合规要求无法自动校验
- 而 `04-input-templates.md`(我写的)已经把 `data_classification` 列为必填 ——
  **我的模板和你们的 CRD schema 对不上。**

**这是一个可以直接修的具体缺口。** 建议在 `ClusterRequest.spec` 加:

```yaml
dataClassification:     # ⛔ 当前 9 份文档中缺失
  level: ""             # 公开 | 内部 | 机密 | 受监管
  residencyConstraint: ""   # 必须留在哪些 region
  retention: ""         # 保留期要求(受监管数据通常绑定期限)
```

---

## 🟠 C5 · 集群级 CRD 缺失(CRD 定义了两个,但没有集群 CRD)

`gke-caas.md` L188 定义了 `ClusterRequest` CRD,`caas-finops.md` L269 也定义了一个 CRD。
**但 RFC §6.3 契约项 1 要求**:

> **一份 CaaS 集群资源（CRD）。** 一份版本化的 Kubernetes 自定义资源定义,描述该集群的身份、
> 元数据与置备配置。**新集群应基于 CRD 中的声明自动置备。所有 app.caep 集群都应具备该定义,
> BYOC 集群亦然。**

**也就是说,RFC 要求的是 `Cluster` 资源(集群本身),不是 `ClusterRequest`(请求)。**

**9 份文档里没有 `kind: Cluster` 的自定义资源定义。** 只有 `ClusterRequest`(意图)和
`ClusterRegistration`(BYOC 登记)。

**这是一个真实的结构性缺口**:

```
现状:  ClusterRequest ──(controller)──> 直接操作 Terraform
RFC 要: ClusterRequest ──> Cluster CRD(集群的身份与声明)
                        └──> 纳管后 Cluster 也存在(BYOC 也一样)
```

**为什么这条重要**:RFC §6.3 说"BYOC 集群亦然" —— 意味着 BYOC 纳管后,
应该能创建一个描述该集群的 `Cluster` 资源,让 BYOC 路径和新建路径**收敛到同一个资源模型**。
而现在 9 份文档里,BYOC 路径**终止于 `ClusterRegistration`**,没有收敛点。

**这正是 RFC 附录 A.2 强调的结构**:

> 两条进入路径的独立性比正文所暗示的更强……仅在 `Managed` 汇合。

**建议**:补一个 `Cluster` CRD 作为两条路径的**汇合点**。这是你这次给 RFC 反馈时
**最有价值的一条技术意见** —— 它直接指出了 9 份文档缺失的架构收敛点。

---

## 🟠 C6 · `multiTenancy` 取值与 Autopilot 兼容性未验证

`gke-caas.md` L275:`multiTenancy` enum 是
`["per-namespace", "shared", "per-cluster"]`。

`gke-caas.md` L313 的 CEL 规则:
```
self.tier != 'autopilot' || self.network.mode == 'private'
```

**问题**:文档里**没有任何地方声明 `per-cluster` 隔离模式在 Autopilot 上可行**。

而事实是:

- **Autopilot 没有节点概念** → `per-cluster` 物理隔离在 Autopilot 上**不可能实现**
- `per-cluster` 通常意味着"一个集群只给一个团队" —— 这个在 Autopilot 上是可以的
  (一个 Autopilot 集群本身就是一个隔离单元)
- 但如果 `per-cluster` 指的是**节点级**隔离(taint/affinity 专用节点池),
  **Autopilot 做不到**

**`gke-caas.md` 没有区分这两种含义。** 这正是我在 `03-gcp-capability-profile.md`
里主张 D3(能力目录必须带 scope)的同一个问题的另一面。

**建议**:明确 `per-cluster` 的定义,并在 CRD 里用 CEL 加上 Autopilot 兼容性校验:
```
self.multiTenancy != 'per-cluster-node' || self.tier != 'autopilot'
```

---

## 🟡 C7 · 命名不一致:`ack` vs `aliyun`

| 文档                   | 取值        |
| ---------------------- | ----------- |
| `gke-caas.md` L242    | `"aliyun"`  |
| `caas-onprem.md` L49  | `{gcp, aws, ack}` |
| `caas-providers.md`   | "ACK" / "阿里云 ACK" |

**同一个云,三个写法。** CRD enum 一旦定下来就是 API 契约,改是破坏性的。
**必须在写第一行 controller 代码前定死。**

---

## 🟡 C8 · 缺少 IKP(内部云)这一整个 Provider

**RFC §1、§8 明确要求支持四个云厂商**:AWS、GCP、Ali 与 **IKP(caep 内部云)**。

**9 份文档只有三云 + 自建**:`gcp` / `aws` / `aliyun` / `onprem`。
`caas-concepts.md` L5 提到"内部 K8S",但那指的是自建 K8S,**不是 IKP**。

**`onprem`(自建)≠ `IKP`(内部云)**。RFC 把 IKP 列为与 AWS/GCP/Ali **并列的云厂商**,
说明它是一个有 API、有配额、有区域概念的内部基础设施平台。

**这是 9 份文档相对 RFC 的最大范围缺口。**

**要确认的事**:
- IKP 有没有 API?有没有配额概念?有没有 region/zone?
- IKP 跑的是托管 K8s 还是裸机自建?
- 如果是托管的,它更接近 GKE(有控制面托管)还是 EKS?

> **建议**:这一条**先不要自己猜**。在 RFC 评审会上直接问:
> **"IKP 是什么形态?现有 9 份设计文档完全没有它,是否需要补充?"**
> 这个问题的答案会决定 CaaS 是不是要重做 Adapter 层。

---

## 🟡 C9 · 版本策略缺失

搜索结果:**9 份文档里没有任何一处提到 GKE release channel**。

而这是你在 `01-workplan.md` WP-3 要交的核心内容,且直接关系到:

- RFC §10 "升级管理 | 跟踪支持窗口"
- RFC §6.3 契约项 5(备份恢复 DR)
- 存量集群的 EOL 风险

**9 份文档假设集群会自己保持在支持版本上,但没有任何设计处理"版本会过期"**。

---

## 📋 汇总与建议动作

| ID  | 严重度 | 问题                            | 谁该改            | 改法                          |
| --- | ------ | ------------------------------- | ----------------- | ----------------------------- |
| C1  | 🔴     | onprem 必填字段自相矛盾         | `gke-caas.md`     | 拆两个 CRD 或加 oneOf          |
| C2  | 🔴     | 状态机与 RFC §6.2 不重叠         | `gke-caas.md`     | 分两层状态                     |
| C3  | 🟠 → **实际更高** | `default: autopilot` **与 DC 现实相反** | `gke-caas.md` | **删 default;DC 全 Standard,enum 可锁死 `["standard"]`** |
| C4  | 🟠     | 缺 `dataClassification` 字段     | `gke-caas.md`     | 加 spec 字段                   |
| C5  | 🟠     | **缺 `Cluster` CRD(汇合点)**   | `gke-caas.md`     | 补资源定义                     |
| C6  | 🟠     | multiTenancy × Autopilot 未验证 | `gke-caas.md`     | 定义清楚 + CEL 校验            |
| C7  | 🟡     | `ack` vs `aliyun`               | 全部含 CRD 的     | 定死一个                       |
| C8  | 🟡     | **缺 IKP 整个 Provider**        | 全部              | 评审会上问清楚                 |
| C9  | 🟡     | 缺版本策略                      | `gke-caas.md`     | 补 channel 策略                |

### 我建议的处理顺序

| 顺序 | 动作                            | 理由                                              |
| ---- | ------------------------------- | ------------------------------------------------- |
| 1    | **C5 · 补 `Cluster` CRD**      | 这是架构收敛点,定错了后面全要返工                |
| 2    | **C8 · 问清 IKP**               | 决定 Adapter 层要不要重做,影响最大                |
| 3    | **C1 · 拆 CRD**                | 阻断级,而且是纯 schema 工作,最快                  |
| 4    | C2 · 分两层状态                | 改动大,但不改的话 BYOC 状态无处安放                |
| 5    | C3/C4/C6 · schema 补字段       | 可以一次 CEL/schema 改动一起做                    |
| 6    | C7/C9 · 补齐                   | 收尾                                |

### 三条要带到评审会的话

1. **"C5:9 份文档没有 Cluster CRD,而 RFC §6.3 要求它是两条路径的汇合点 —— 我们缺了架构收敛点。"**
2. **"C8:RFC 要求支持 IKP,但现有设计里没有 IKP。IKP 是什么形态?这决定 Adapter 层要不要重做。"**
3. **"C2:RFC 的状态机表达合规与移交,现有设计的状态机表达资源创建进度 —— 建议分两层,不互相替代。"**

---

## 附:校验覆盖说明

**我查了什么**:CRD schema 必填字段与 enum、`cloudProvider` 取值、状态机定义、
tier 默认值、多租户模式、CRD 资源种类、版本/channel 提及、IKP 提及。

**我没查什么**:

- 代码示例的**逻辑正确性**(只看结构性声明,没逐行验证伪代码)
- `caas-portal-temporal-demo/` 里可运行 Demo 的实现细节(它是个独立 demo,不参与设计冲突)
- 各文档的**表述风格**差异(不构成矛盾)
- **DC 内部现实** —— 9 份文档里的"bbuk-team-a-prod"等命名是假设的,
  实际集群情况只有你知道

> **诚实说明**:这份校验基于**文本比对**。
> 如果某些"矛盾"是有意的(比如作者知道 C1 的情况但打算后面修),
> 那我标错了。**建议你逐条确认后再传给 app.caep Compute。**

---

**修订记录**

| 日期       | 内容                                                       |
| ---------- | ---------------------------------------------------------- |
| 2026-09-29 | 初版。9 条冲突(C1–C2 阻断,C3–C6 重要,C7–C9 提示)         |
