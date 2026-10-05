# 20 · WP-3 版本与升级策略能力表(可交付版)

> **这是什么**:`09-p0-execution-pack.md` §3 下午 1 那一个半天的交付 —— 从"决定书草稿"升级为
> **可提交给 RFC 的能力表**。所有 GKE 事实均以 Google 官方文档为准,逐条带链接 + 查阅日期。
>
> **状态**:GCP 侧事实**已核实并落表**;DC 侧决策(节奏/窗口/负责人)**留空待填**。
> **本文不含任何猜测数据** —— 凡未核实的一律标 `⬜ 待填`,不填示例值。
>
> 查阅日期:**2026-10-05**

---

## 0. 一页结论

| 项                | 结论                                          | 依据                                    |
| ----------------- | --------------------------------------------- | --------------------------------------- |
| 集群模式          | `Standard`                                    | DC 立场 2026-09-29 确认                 |
| Release channel   | `Stable`                                      | DC 立场 2026-09-29 确认                 |
| Rapid             | **禁用**(明确禁令,非"不推荐")                | GKE 官方明示排除在 SLA 外[3]            |
| No channel        | 不用,且它本身是**待废弃配置**                | 官方标注 deprecated[2]                  |
| Extended          | 不用                                          | 与 Standard 模式**互斥** —— 见 §2.4 ⚠️   |
| 控制面 patch 底线 | **90 天**                                     | 官方强制策略,超时 GKE 自行升级[3]        |
| 存量版本高危区    | 官方**明确禁止降级**控制面                     | 纳管前必须逐个查版本[8]                  |

> ⚠️ **本文档修正了 `09` 号执行包的一处口径** —— 见 §5「三处修正」。

---

## 1. Release channel 能力表(WP-3 核心交付)

### 1.1 Channel 属性对照

| Channel          | minor 可用时间                  | 成为 auto-upgrade target  | 定位                              | SLA   | DC 立场 |
| ---------------- | ------------------------------- | ------------------------- | --------------------------------- | ----- | ------- |
| **Rapid**        | 上游 GA 后 1–2 周                | 到 Rapid 后 1–2 个月       | 最早拿新特性                      | **❌ 无**[3] | **禁用** |
| **Regular**(默认) | 到 Rapid 后约 2 个月             | 到 Regular 后约 3 个月     | 特性/稳定性平衡,**官方推荐多数用户** | ✅    | 未采用 |
| **Stable** ✅    | 到 Regular 后 3–4 个月           | 到 Stable 后约 2 个月      | 稳定优先,**已在 Rapid+Regular 双轮验证**[2] | ✅    | **采用** |
| **Extended**     | 与 Regular 对齐                  | 与 Regular 对齐             | 长期支持(minor 最多撑 24 个月)[2] | ✅    | **不用** ⚠️ 见 §2.4 |
| **No channel**   | 与 Regular 对齐                  | 与 Stable 对齐             | **已废弃配置,将被移除**[2]        | ✅    | **禁用** |

来源:[2] release-channels · [3] versioning

> **⚠️ 一条容易被忽略的 SLA 边界:patch 版本也算。**
> GKE 文档明确: Rapid channel 提供的 patch 版本**同样排除在 GKE SLA 之外**,
> "because the Rapid channel provides the newest GKE patch versions, these versions are
> excluded from the GKE SLA and might contain issues without known workarounds".[3]
> → DC 禁 Rapid,同时也意味着**禁掉了一批"最新 patch"**。这是自觉接受的代价,不是疏漏。

> ⚠️ **引用纪律**:本文所有 minor 版本的可用/废弃/EOL 日期都取自 GKE release schedule[1],
> 它**按月滚动更新**。任何写入能力目录或决定书的日期,必须标注查阅日期并在引用前重新核对[1]。
> maintenance window / exclusion 的能力边界取自官方 maintenance 文档[5]。

### 1.2 选择 Stable 的四条理由(评审会版)

| #   | 理由                                                                                    | 出处 |
| --- | --------------------------------------------------------------------------------------- | ---- |
| 1   | **在 GKE SLA 范围内**(Rapid 明确排除)                                                    | [3]  |
| 2   | 新版本在 Rapid 与 Regular 之后**额外经历两轮验证**才进 Stable                            | [2]  |
| 3   | 获得**完整的 maintenance exclusion 权限** —— 官方能力对照表明确:在 channel 内可配三种 scope 的 exclusion;"No upgrades" 最长 **90 天**,"No minor upgrades" 可持续到 end of support[2] | [2]  |
| 4   | 官方对**生产集群**明确推荐:"If your requirement is maturity, especially for production clusters, use the Stable channel."[2] | [2]  |

**代价(必须一起说,不能只说好处)**:新特性延后。minor 版本从上游 GA 到进 Stable 需
Rapid(1–2 周)→ Regular(约 2 个月)→ Stable(3–4 个月),**累计约 6–7 个月**。[2]
→ **要求 CaaS**:能力目录里凡依赖新 minor 特性的项,必须标注"该特性进 Stable 的时间",否则业务方会误以为"GA 了就能用"。

---

## 2. 硬约束:四条 CaaS 必须硬编码的规则

### 2.1 控制面 90 天 patch 底线(强制,不可协商)

> 官方原文口径:"GKE requires that a cluster's control plane is upgraded to a new patch (or minor)
> version **at least every 90 days**."[3]

| 项              | 内容                                                                    |
| --------------- | ----------------------------------------------------------------------- |
| 规则            | 控制面至少每 90 天升一次 patch(或 minor)                                |
| 超时后果        | **GKE 自动升级,无视你配置的 policy** —— "if you have a GKE cluster that hasn't been upgraded as required, GKE automatically upgrades your cluster to a later patch version **regardless of any policies that you configured**"[3] |
| 官方默认行为    | GKE 默认升级频率**高于** 90 天[3]                                        |
| 能否关掉        | ❌ **不能**。"control plane upgrades happen regularly and **can't be disabled**"[6] |
| 集群断代预算    | 默认 patch 间隔 **24 小时**、minor 间隔 **30 天**;可配 0–90 天[9] ⚠️ 见 §2.5 |
| **要求 CaaS**   | ① 纳管校验阶段检查 `currentMasterVersion` 的 patch 时间戳,超期拒绝;<br>② 把 90 天作为 CRD 强字段而非文档约定;<br>③ EOL 通告义务(§2.3)必须自动化 |

> **这条对 CaaS 的真正含义**:升级不在 CaaS 的"可选能力"清单里,而是**CaaS 存在的基础前提**。
> 如果 CaaS 纳管了一个超 90 天的集群却没告警,那这个集群的升级变更**不会出现在任何流程里** —— 出事时没有变更记录。

### 2.2 EOL 强制升级(你挡不住,只能提前告警)

| 项                | 内容                                                                                     |
| ----------------- | ---------------------------------------------------------------------------------------- |
| 触发              | minor 版本到达 **end of standard support**(原 EOL)                                          |
| 后果              | GKE **自动升级**控制面与节点,维护 exclusion 无法阻止                                        |
| 极端情况          | "**At the end of extended support**: GKE upgrades all clusters still running the now-unsupported minor version, **regardless of blocking issues**."[2] |
| 临时手段          | 可配 "No upgrades" scope 的 maintenance exclusion 延迟**至多 90 天**,官方明确**不推荐**[3] |
| 官方会先发邮件    | 客户会通过 project contact 收到 end of support 通知[3]                                      |
| **要求 CaaS**     | **EOL 前 [⬜ 待填:建议 60] 天主动通告业务方 —— 此为强制要求,不是 best practice**          |

> **这条是 `09` §3.2 说的"三个不能省的点"之一,现在有官方依据了。**
> 价值不在于"提前升级"(你控制不了),而在于**业务方至少有时间准备**。
> 官方邮件只发给 project contact —— CaaS 应当把通告直接推给**集群的业务 owner**,而不是等官方邮件。

### 2.3 版本 skew 与节点约束

| 约束                       | 值                                    | 出处 |
| -------------------------- | ------------------------------------- | ---- |
| 节点最多落后控制面          | **2 个 minor 版本**                   | [7]  |
| 节点版本不得高于控制面      | 是                                    | [7]  |
| 节点不得跑已 EOL 的 minor   | 是                                    | [7]  |
| 默认一次只升一个节点池      | 是(可开 Preview 并发节点池升级)       | [8]  |

> **给 CaaS 的具体要求**:BYOC 纳管校验必须检查 **节点池版本与控制面的 skew**。
> 原 RFC §9.1 准入条件里没有这一条 —— 一个 skew 超限的集群,控制面升级时会连带触发节点池重建,
> 这正是"纳管后突然出事"的典型来源。

### 2.4 ⚠️ Extended channel 与 Standard 模式互斥(原文档完全没写)

**这是本次核查新发现的一条硬冲突。**

Extended channel 官方明确列出的**不可加入清单**包含:

> - **Autopilot cluster mode**
> - Alpha clusters
> - 显式启用的 Kubernetes beta APIs
> - Gateway(**仅 1.30+ 的 Extended channel 支持**)
> - Windows Server node pools
> - Config Connector
> - **多集群特性**:Managed Cloud Service Mesh、Service Directory for GKE、Config Sync、Policy Controller、Multi-cluster Gateway、Multi Cluster Ingress、Multi-cluster Services[2]

> **推断(标注为推断,需实测确认)**:该列表主语是 "a cluster that uses the following features",
> Autopilot 明确在列,而 Standard 未被列入禁止项 → **Standard + Extended 理论可行**。
> **但** 列表里同时禁止了 Config Sync 与 Policy Controller ——
> 而 DC 的 CaaS 基线**恰好依赖这两者**。→ **结论:Extended channel 对 DC 的 CaaS 基线是不可用的,
> 无论 Standard/Autopilot。** 这一点比"Stable 窄区间"重要得多,因为它直接关掉了"用 Extended 拖时间"这条退路。
>
> **动作**:标 `⬜ 待实测` —— 在任何集群上尝试 enroll Extended,确认 DC 基线特性是否被拒。
> **不实测就不要写进能力目录。**

### 2.5 集群断代预算(CDB)的隐藏交互 ⚠️

原 `09` 文档完全没提这条,但它**直接改变升级节奏的可行区间**:

| 项                | 值                                            | 出处 |
| ----------------- | --------------------------------------------- | ---- |
| 默认 patch 间隔   | **24 小时**                                    | [9]  |
| 默认 minor 间隔   | **30 天**                                      | [9]  |
| 可配范围          | 0–90 天                                        | [9]  |
| ⚠️ **陷阱**       | 若把 minor 间隔配到 **90 天上限**,就**增大了 GKE 在 EOL 时强制升级的概率** | [9] |
| EOL 时的例外      | EOL 时 GKE 改用 **7 天** 的 minor 断代预算,**且不遵守你配的任何 CDB** | [9] |

> **可写进决定书的一句话**:
> "把 minor 断代预算配到 90 天上限以'减少打扰',会显著提高 EOL 时刻被强制升级的概率。
> **留 30 天默认值,把 90 天留给有正当理由的例外。**"

### 2.6 两步升级(1.33+)—— 原文档口径成立

| 项        | 内容                                                                     | 出处 |
| --------- | ------------------------------------------------------------------------ | ---- |
| 适用范围 | minor 版本 **1.33+** 的控制面升级                                         | [8]  |
| 流程      | ① Binary upgrade(升级二进制但模拟旧 minor)→ ② soak → ③ emulated upgrade | [8]  |
| soak 时长 | 手动:6 小时–7 天;**自动升级:24 小时**                                     | [8]  |
| 回滚      | 仅在 binary 之后、emulated 完成之前可回滚;**完成后不可回滚**               | [8]  |
| 自动执行  | GKE 对未加入 rollout sequence 的集群**自动**用两步流程升到 1.33+          | [8]  |
| 命令      | `gcloud beta container clusters upgrade --control-plane-soak-duration ...` | [8]  |

> **对 CaaS 灰度的价值**:自动 minor 升级有 **24 小时 soak**,等于 GKE 免费送了 24 小时观察窗。
> **要求 CaaS**:把"升级后 24h 内的异常检测"写进 Day-2 runbook,而不是等 7 天后再看。

---

## 3. Rollout sequencing(灰度编排)—— 架构前提

| 项                | 内容                                                                    | 出处 |
| ----------------- | ----------------------------------------------------------------------- | ---- |
| 前提              | **集群必须归入 fleet**(逻辑分组,映射到环境)                             | [4]  |
| 能力范围          | Fleet-based sequencing(**GA,官方推荐用于生产**)                          | [4]  |
| 进阶版            | Custom stages(**Preview**)—— 用 label 在 fleet 内做更细粒度分组          | [4]  |
| 轻量成员          | 支持 lightweight membership,可不启用 fleet 级配置就用 sequencing          | [4]  |
| **官方明确不可用** | **No channel 集群不支持 rollout sequencing**                            | [2]  |
| 权限              | 需能配置 rollout sequence 的角色:⬜ 待填                                   | —    |

**为什么这条对 DC 重要**:DC 确认用 Stable + Standard。[2]
→ **No channel 不能用 sequencing**(若 DC 存量集群里有 No channel 的,它们既不合规也无灰度能力)
→ **所有要纳管的集群必须先归入 fleet** —— 这应当是 BYOC 阶段 1 的动作,**不是 Day-2 才做的事**。

### 3.1 DC 现状对照(基于 `03-gcp-capability-profile.md` §0.5)

DC 已有 **GKE Fleet 实践**(`01-platform` 脚本、`apply_istio.sh`、ListenerSet 多租户等均为 fleet 上下文操作)。
→ **rollout sequencing 无需新建能力,只需把 fleet 归组从"可选"变成"纳管必做"。**

---

## 4. 待填项清单(DC 侧决策,需要你和 SRE 定)

| #   | 待填项                              | 建议值                        | 决定人 |
| --- | ----------------------------------- | ----------------------------- | ------ |
| 1   | minor 升级节奏(每 __ 周/季度)        | 参考官方:minor 一年约 3 次     | DC + SRE |
| 2   | 是否接受 GKE 自动 patch 升级        | 建议 **是**(与 90 天底线一致)   | DC + SRE |
| 3   | 是否接受 **accelerated patch**      | 🔶 需权衡:更快拿安全补丁,但**跳过 qualification 步骤**,所有 patch(含非安全)都提前升[2] | DC + 安全 |
| 4   | 业务方维护窗口(频次/时长/时区)       | ⬜                              | 业务方共识 |
| 5   | 冲突规则(业务窗口 vs GKE 自动升级)    | ⬜                              | DC + SRE |
| 6   | **EOL 提前通告天数**                 | **建议 60 天**                 | DC 决定  |
| 7   | CDB:patch 间隔 / minor 间隔         | **建议保留默认 24h / 30d**     | DC + SRE |
| 8   | rollout sequencing 启用?            | **建议是**(需 fleet 归组)     | DC + SRE |
| 9   | EOL 90 天延迟 exclusion 是否放行     | 官方**不推荐**,建议仅紧急用    | DC + 安全 |
| 10  | fleet 归组规则(env → fleet 映射)     | ⬜                              | DC + SRE |
| 11  | rollout sequence 权限角色           | ⬜                              | DC |
| 12  | Extended channel 是否真不可用        | **必须实测**(§2.4)            | Lex |

---

## 5. 对 `09-p0-execution-pack.md` 的三处修正

| #   | 原文档写法                                              | 修正                                                                       |
| --- | ------------------------------------------------------- | -------------------------------------------------------------------------- |
| 1   | 硬约束只列了 4 条(90 天 / EOL / 两步 / Stable 窄区间)   | **漏了 4 条更硬的**:CDB 默认 24h/30d、EOL 时 CDB 改 7 天且不遵守配置、节点 skew ≤2、No channel 无 sequencing[9][7][2] |
| 2   | 未提 Extended channel                                    | **Extended 与 DC 基线(Config Sync / Policy Controller)冲突**,关掉"用 Extended 拖时间"这条退路[2] |
| 3   | "1.33+ 两步升级"表述含糊                                 | 补精确口径:**自动 minor 升级 soak 仅 24 小时**;emulated 完成后**不可回滚**[8] |

> **最重要的一条修正**:原文档把"Stable 窄区间"当成主要风险(存量集群版本过高加不进)。
> **实际上更大的风险是:即使降级成功,一旦 EOL,你也失去所有阻挡能力。**
> 所以纳管前检查版本,**不是"加不进就以后再说",而是"现在就把版本对齐到 Stable 区间内"**。

---

## 6. 修订记录

| 日期       | 内容                                                                       |
| ---------- | -------------------------------------------------------------------------- |
| 2026-10-05 | 依 GKE 官方文档重写:补 4 条遗漏硬约束、发现 Extended 冲突、精确化两步升级口径 |

---

## Sources

[1] https://docs.cloud.google.com/kubernetes-engine/docs/release-schedule — GKE release schedule
[2] https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels — About release channels
[3] https://docs.cloud.google.com/kubernetes-engine/versioning — GKE versioning and support
[4] https://docs.cloud.google.com/kubernetes-engine/docs/concepts/about-rollout-sequencing — About cluster upgrades with rollout sequencing
[5] https://docs.cloud.google.com/kubernetes-engine/docs/concepts/maintenance-windows-and-exclusions — Maintenance windows and exclusions
[6] https://docs.cloud.google.com/kubernetes-engine/upgrades — About GKE cluster upgrades
[7] https://docs.cloud.google.com/kubernetes-engine/docs/concepts/cluster-upgrades — Standard cluster upgrades
[8] https://docs.cloud.google.com/kubernetes-engine/docs/how-to/upgrading-a-cluster — Manually upgrade a cluster or node pool
[9] https://docs.cloud.google.com/kubernetes-engine/docs/release-notes-stable — GKE release notes (Stable channel)
