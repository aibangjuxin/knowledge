# 09 · P0 立即执行包(约 1.5 天)

> **这是什么**:`01-workplan.md` 里三个 P0 工作包的**可执行展开** —— 按天排,每半天有明确产出。
> **今天就能开始,不需要等任何人。**
>
> **前置**:先做 [`01-workplan.md`](./01-workplan.md) §1 的 WP-0 帽子判断(5 分钟)。

---

## 0. 时间预算

| 时段       | 做什么                          | 产出                                | 谁能独立完成 |
| ---------- | ------------------------------- | ----------------------------------- | ------------ |
| **上午 1** | WP-0 帽子判断 + 约安全架构师    | 一次会的议程 + WP-4 输入            | ✅           |
| **上午 2** | WP-2 配额 / 区域包络            | 2 个 YAML + 1 页说明                | ✅           |
| **下午 1** | WP-3 维护与支持边界            | 1 页 release channel 决定书         | ✅           |
| **下午 2** | WP-1 能力目录(只做"最硬"的部分) | §3.5/§3.6 两节填实                 | ✅           |
| **可选 +2h**| §14/§15 两张表                  | 见 `07-decisions-and-open-questions.md` | ✅       |

> **四个时段全部可以独立完成,不需要 app.caep Compute 配合。**
> 这是刻意的 —— 你不是在他们前面交作业,你是在给他们输入。

---

## 1. 上午 1 · 帽子判断 + 约安全架构师

### 1.1 WP-0 帽子判断(5 分钟)

回答一个问题:

> **DC/DC 基础架构团队要向 CaaS 提要求吗?**

| 答案             | 你走哪条路                                                              |
| ---------------- | ----------------------------------------------------------------------- |
| 是               | 帽子 A(云侧)。本执行包全部适用。                                        |
| 否,我是 DC 业务方 | 帽子 B(业务侧)。**只做** [`04-input-templates.md`](./04-input-templates.md) §一,然后把 WP-2/WP-3 转给 DC 平台组 |
| 两者都有         | 先 A 后 B。**注意顺序** —— B 的申请单会被 A 的能力目录校验,反了会返工   |

### 1.2 约安全架构师(这是本次投入产出比最高的一小时)

**为什么要约**:RFC §11 承认 caep Kubernetes Security Standard 需 Confluence 认证,
他们**还没有拿到控制项映射**。你有 GCP 侧的可自动化性判断,她/他有标准条款。
**两边都有对方没有的东西,这是一次天然的双赢会。**

**发出去的会前材料**(一封邮件 / 一条消息即可):

> 主题:CaaS RFC §11 控制项映射 —— GCP 侧可自动化性输入
>
> 我这边整理了 GCP 对常见安全控制项的支撑情况(见下表),想占用你 1 小时对齐一下。
> 你带标准条款,我带能力现状,当场确认哪些能自动化、哪些只能人工。
>
> | 控制项类别 | GCP 侧现状(初判) |
> |---|---|
> | 静态加密(CMEK) | 支持,但**非所有服务都支持 CMEK**,需逐服务核对 |
> | 使用中加密 | Confidential GKE Nodes(2023-02 GA),**限 N2D/C2D、不兼容 sole-tenant、仅 local SSD 临时存储、不支持 Windows** |
> | 工作负载身份 | Workload Identity Federation,标准做法 |
> | 网络隔离 | VPC-native / Private cluster / Network Policy 齐备 |
> | 审计 | Cloud Audit Logs 覆盖 Admin Activity;**Data Access 默认关闭,需显式开启** |
> | 镜像准入 | Binary Authorization,**仅覆盖 GCR / Artifact Registry** |
> | 特权访问 | Autopilot privileged 准入由 org policy `container.autopilotPrivilegedAdmission` 管理 |
> | 策略审计 | Policy Controller 可**回溯审计既有资源**;⚠️ 超上限违规只计数不列明细,证据包不能把计数当清单 |
>
> 我不需要你把映射表写完,我只需要知道**哪几项在 GCP 上做不到自动化**。

### 1.3 顺便把 WP-4 的两身份原则提出来

在同一次沟通里说一句:

> "我们建议 CaaS 的权限分成**云厂商侧**和**集群内**两套,分别授权、分别审批。
> 因为爆炸半径完全不同 —— 改一个集群的 RBAC 和改一个项目的 IAM 不是一回事。"

这句话 RFC §9.4 结尾的 `[待补充]` 正好需要,而且**你提出来比 CaaS 提出来更有说服力** ——
因为你是会被它授权的人。

---

## 2. 上午 2 · WP-2 配额 / 容量 / 区域包络

### 2.1 交付 1:区域允许清单

```yaml
# dc-region-allowlist.yaml
# 维护方:DC 平台组    版本:v1    生效日期:YYYY-MM-DD
# CaaS 用途:放置校验时按 region 查表;不在表内 → 直接拒绝申请
apiVersion: caas.internal/dc/v1
kind: RegionAllowlist
metadata:
  name: gcp-regional-allowlist
  version: 1                      # 每次变更递增;CaaS 需记录它读到的版本号
regions:
  # 例 —— 请替换为 DC 真实值
  - id: asia-northeast1           # 东京
    tier: primary
    allowed_data_classification: [公开, 内部, 机密]     # 受监管数据是否允许?
    supported_modes: [standard, autopilot]
    available_accelerators: []    # 空 = 该区无 GPU 供给
    notes: ""
  - id: asia-northeast2           # 首尔
    tier: secondary
    allowed_data_classification: [公开, 内部]
    supported_modes: [standard]
    available_accelerators: []
    notes: ""
# 明确列出"暂不允许"的区域比不写更有价值:
denied_regions:
  - pattern: "*"                  # 默认拒绝
    reason: "不在 DC 允许清单内"
```

> 💡 **默认拒绝优于默认允许。** 这份清单里 `denied_regions` 的显式声明不是形式 ——
> 它让 CaaS 的校验逻辑有一个明确的兜底分支,而不是"查不到就当允许"。

### 2.2 交付 2:配额四元组

```yaml
# dc-quota-baseline.yaml
# ⚠️ 下面的数字是 GKE 默认值,不是你 DC 的实际值 —— 必须替换
quota:
  - resource: clusters_per_zone
    default: 50
    current: ??                    # 🔶 查:gcloud compute regions describe / console Quotas 页
    approved: ??
    increase_lead_time: "?? 天"    # 🔶 提额实际要多久
    owner: ""
  - resource: regional_clusters_per_region
    default: 50
    current: ??
    approved: ??
    increase_lead_time: "?? 天"
    owner: ""
  - resource: gpus_per_region      # GPU 是 AI 场景的真正瓶颈
    default: ??                    # 🔶 按机型分别查
    current: ??
    approved: ??
    increase_lead_time: "?? 天"    # GPU 提额通常远慢于普通配额
    owner: ""
  - resource: cpus_per_region
    current: ??
    approved: ??
    increase_lead_time: "?? 天"
    owner: ""
```

**查法**:`gcloud compute regions describe <region>` 或 Console → Quotas 页面。
**GPU 配额要按机型分开查**(A100 / L4 / H100 各自独立)。

### 2.3 交付 3:一页说明(口头讲清楚的部分)

| 问题                       | 你要给出的答案                                        |
| -------------------------- | ----------------------------------------------------- |
| 配额提额走什么流程          | 找谁?工单?多久有回音?                                 |
| **有没有预留 buffer**        | 例如"申请 100,承诺业务方不超过 80"                    |
| 单项目最多支撑多少集群      | 举例说明(50/zone 或 50/regional 是默认上限)           |
| 什么算"饱和"               | 指标名 + 阈值,例如 CPU 配额用量 >80% 持续 1h          |
| 饱和时 CaaS 该做什么         | 告警?排队?拒绝新申请?                                 |

### 2.4 ⚠️ 别忘了 `gke-resource-quotas`

在这份交付里**单独加一节**:

```markdown
## GKE 自身的隐式配额(CaaS 必须感知)

GKE 对节点数 <100 的集群,自动对每个 namespace 施加名为 `gke-resource-quotas`
的资源配额。该配额不可删除,随节点数自动缩放。

**这不是 CaaS 设的配额。** 业务方"申请不到资源"时,查 CaaS 会查不到任何东西。

查询:kubectl get resourcequota gke-resource-quotas -o yaml

**要求 CaaS**:
1. 申请校验阶段读取该对象,把"可用余量"显示给业务方
2. 容量告警覆盖该配额,而非只覆盖 CaaS 自己设的配额
3. 集群超过 100 节点后重新评估(GKE 会移除该配额)
```

---

## 3. 下午 1 · WP-3 维护与支持边界

### 3.0 ✅ 已确认的部分(2026-09-29)

| 项                    | 值        |
| --------------------- | --------- |
| **集群模式**           | `Standard` |
| **Release channel**   | **`Stable`** |
| **Rapid**             | 不使用(且它在 GKE SLA 之外,建议写成明确禁令) |
| **`No channel`**      | 不使用   |

**这三个确认让 WP-3 的一半内容确定了。剩下的只有"节奏"和"窗口"。**

### 3.1 交付:版本与升级策略决定书(一半已定)

```markdown
# GKE 版本与升级策略决定书 v1

## 已确认(2026-09-29)

**集群模式**:Standard
**Release channel**:Stable

**选择 Stable 的理由**:
  ✅ 在 GKE SLA 内(Rapid 明确被排除)
  ✅ 获得完整 maintenance exclusion 权限
  ✅ 新版本在 Rapid 之后额外经历 Regular、Stable 两轮验证
  ⚠️ 代价:新特性延后 2–3 个月

**禁用 Rapid 的理由**:
  GKE 官方明确 Rapid 排除在 SLA 之外。
  → **建议写成明确禁令**,而非"不推荐"。

## 待定:节奏与窗口

  · minor 升级频率:每 __ 周/季度 一次
    (参考:minor 升级本身一年约 3 次,DC 不需要每次都跟)
  · patch 升级:接受 GKE 自动(每周可能发生)☐ 是 ☐ 否
  · 业务方维护窗口:频次 __ / 时长 __ / 时区 __
  · 冲突规则:业务窗口 vs GKE 自动升级窗口 → __

## 硬约束(CaaS 必须知晓并实现)

1. **控制面 90 天底线**:GKE 要求控制面至少每 90 天升一次 patch。
   超时 GKE 自行升级。→ CaaS 升级管理必须以此为**强制规则**。

2. **EOL 强制升级**:版本过 EOL 后 GKE 强制升级,
   maintenance exclusion **无法阻止**(紧急情况除外)。
   → **CaaS 必须在 EOL 前 [__] 天主动通告业务方**,此为强制要求。

3. **两步升级(1.33+)**:minor 升级可 soak、可回滚。
   → CaaS 的灰度策略可利用这一点。

4. **⚠️ Stable 的窄区间**:一个跑在较新 minor 版本上的存量集群,
   可能无法加入 Stable(需降级或暂留 No channel)。
   → **纳管前必须逐个检查**(见 12 号文件 §1.2)。

## 升级编排

  · 是否启用 rollout sequencing:☐ 是 ☐ 否
  · 若启用:需集群归入 fleet,每序列最多 5 组,soak 上限 30 天
  · 持有 roles/gkehub.editor 的角色:🔶 填
  · ⚠️ **架构前提**:用 GKE 官方灰度编排 = 集群必须已在 fleet 中。

## 🆕 Standard 模式带来的 Day-2 责任(新增,重要)

因为 DC 用 Standard 而非 Autopilot,**节点层归 DC/CaaS 管**:

| 事项                     | DC 的责任                    | CaaS 要编排的                |
| ------------------------ | ---------------------------- | ---------------------------- |
| **节点升级策略**          | 选 surge / blue-green        | 按画像统一 + 维护窗口执行    |
| **Cluster Autoscaler**    | 配置 min/max 边界            | Day-0 注入 + 持续对账        |
| **NAP(节点自动预配)**     | 决定是否启用                 | 属画像决策                   |
| **节点池数量收敛**        | ⚠️ 无人收敛会持续膨胀        | **成本治理,最易被忽略**      |
| **Pod 密度规划**          | 机型与资源分配               | 容量模型                     |

> **这一节是 WP-3 相对上一版最重要的新增。**
>
> **⚠️ 2026-09-29 修正**:这里原写"选 Standard = 少一个云厂商能力,多一套 CaaS 编排责任"
> —— **说法过头了。**
>
> **DC 实际做法(Standard + auto-upgrade + maintenance window + 强制自动升级要求)
> 完全是 GKE 标准用法,升级执行由 GKE 完成,CaaS 不需要重做编排。**
>
> **正确的定位:CaaS 提供安全默认值与边界,不接管执行。**
> 详见 [`03-gcp-capability-profile.md` §3.1](./03-gcp-capability-profile.md)。


### 3.2 三个不能省的点

| 点                            | 为什么不能省                                                |
| ----------------------------- | ----------------------------------------------------------- |
| **EOL 通告义务**               | GKE 强制升级你挡不住 —— **唯一能做的是提前告警**。不定 = 业务方毫无预警被升级 |
| **90 天底线是强制**             | CaaS 若不知道,会以为可以拖;结果 GKE 自行升级,变更不在流程内 |
| **Rapid 不签 SLA**              | 给业务方挂 Rapid = 你签了单但没签 SLA。写清楚这条,避免未来扯皮 |

---

## 4. 下午 2 · WP-1 能力目录(只做最硬的两节)

**为什么只做两节**:§3.1–§3.8 全部 20 个维度需要和 SRE/Compute 一起过。
但 **§3.5(加速器)和 §3.6(配额)** 是**纯云侧事实,不需要协商** —— 现在就能填实。

### 4.1 §3.5 加速器:填实后的样子

> **⚠️ 已被 `18-gpu-ai-assessment.md` 取代(2026-09-29)。**
> **DC 平台不支持 GPU 场景** —— 下表的 `✅` 是"技术可行性",**不是 DC 的实际提供状态**。
> 实际写法见 `18` §6.1:GPU 相关能力标 `尚未评估` + "DC 主动不支持,非技术限制"。

| 能力(技术可行性,非 DC 提供状态) | 状态 | caveat                                                       |
| --------------------------------- | ---- | ------------------------------------------------------------ |
| NVIDIA GPU 节点池                  | ✅   | 按机型与区域供给,**受配额强约束**;GPU 提额周期通常远长于普通配额 |
| TPU                                | ✅   | 每 zone 上限 2,000 TPU 节点                                   |
| 高内存机型(A3 等)                 | 🔶   | 供给有限,配额与区域可得性是主要约束                          |
| **每 Pod 独占 GPU**               | ✅   | Accelerator 类 Pod **每节点限 1 个 Pod**                      |
| **GPU 独占拓扑隔离**               | **❌** | **GKE 不提供 per-cluster GPU 隔离保证,只有 quota 隔离**    |
| GPU 节点自动伸缩                  | 🔶   | Autopilot 支持;Standard 需节点自动配置                        |
| 设备插件 socket 名长度            | 🔶   | 网络名 **超 41 字符** 导致 device plugin 启动失败             |

> #### 📌 关于 §3.5 那条 `❌`(定位已更新,2026-09-29)
>
> ~~**它是这份交付里最重要的一行**~~ —— **这个判断现在不成立了。**
>
> 当时的理由是"阻止一个失信":怕 DC 已对外承诺 GPU 独占。
> **但 DC 本身不提供 GPU 场景,就不存在这个承诺。** 理由消失了,重要性也一起消失。
>
> **它现在的价值:是"将来评估 GPU 时不要重踩的坑",不是"现在要交的坏消息"。**
> 详见 [`18-gpu-ai-assessment.md`](./18-gpu-ai-assessment.md)。

### 4.2 §3.6 配额:填实后的样子

直接用 §2 的 `dc-quota-baseline.yaml` + 上面 2.4 的 `gke-resource-quotas` 一节。
**这份 YAML 同时是 WP-2 的交付和 WP-1 的 §3.6 节内容** —— 一次写两处用。

### 4.3 今天不做的部分

§3.1 / §3.2 / §3.3 / §3.4 / §3.7 / §3.8 留到与 Compute + SRE 的会。
**理由**:这些维度的取值依赖 DC 的实际选择(开不开 Autopilot、选不走 mesh、
用不用 Config Controller),你一个人定不了,而且**现在定了也没有约束力**。

---

## 5. 可选 +2 小时 · §14 / §15 两张表

直接用 [`07-decisions-and-open-questions.md`](./07-decisions-and-open-questions.md)。
9 条决策 + 12 条开放问题都已填好,你要做的是:

1. 删掉不认同的
2. 把"建议责任人"换成真实的人
3. 优先把 **O3(版本窗口)/ O4(网络边界)/ O7(GPU 隔离)** 标为"评审会当场决"

**为什么这 2 小时值得**:
§14/§15 现在是 `example` / `Example`。**填满这两张表,是让 RFC 从"待办清单"
变成"可签字文档"的最短路径。** 而且"未解决时的影响"这一列是 RFC 原文丢掉的 ——
你填上它,本身就是一项独立贡献。

---

## 6. 本执行包的完成判据

半天结束时,你手上应该有:

- [ ] 帽子判断结论明确(一句话)
- [ ] 一封发给安全架构师的会邀(带 §1.2 的表格)
- [ ] `dc-region-allowlist.yaml` —— 带版本号,默认拒绝
- [ ] `dc-quota-baseline.yaml` —— 四元组填实
- [ ] 一页纸:GKE 隐式配额说明(含 `gke-resource-quotas`)
- [ ] release channel 决定书 v1(含 EOL 通告义务)
- [ ] 能力目录 §3.5 + §3.6 填实
- [ ] (可选)§14/§15 两张表

**这八样东西加起来,你在 RFC 评审会上的位置
就从"来旁听的云工程师"变成"没有他签不了字的技术评审人"。**

---

## 7. 接下来(第二周)

| 动作                              | 依赖谁              | 你的文件              |
| --------------------------------- | ------------------- | --------------------- |
| 与 Compute + SRE 开能力目录定稿会 | 约 `03` 的人        | `03-gcp-capability-profile.md` 全部 20 维 |
| 交 break-glass 条款(走安全评审)   | Cyber               | `06-boundary-and-raci.md` §4 |
| 填管理边界十行表                  | 与 SRE 一起         | `06-boundary-and-raci.md` §2.1 |
| 若有存量集群:启动 BYOC 登记        | 业务方              | `05-byoc-onboarding-pack.md` |
| 把 §14/§15 提交评审               | 全员                | `07-decisions-and-open-questions.md` |

---

**修订记录**

| 日期       | 内容                                      |
| ---------- | ----------------------------------------- |
| 2026-09-29 | 初版                                      |
| 2026-09-29 | 依 03 号文件复核结果,修正 Workload Identity 不可变之说(见该文件与 `08-sources.md`) |
