# MIG `target-distribution-shape` EVEN → BALANCED — 架构影响与概念澄清

> **背景**(2026-09-07):UK 区域生产环境的 MIG 在自动扩缩容时遇到 `zone_resource_exhausted` —— 因为 `EVEN` distribution 要求各 zone VM 数量差异 ≤1,某个 zone 没容量时 MIG 整个卡住。计划把 `target-distribution-shape` 从 `EVEN` 改为 `BALANCED` 缓解。
>
> **本文档范围**:**概念澄清 + 架构层面影响**。**不包含**:
> - ❌ gcloud / REST 命令细节
> - ❌ Terraform 字段细节(已知 Terraform 改这个字段会 destroy/recreate,需用 gcloud in-place update)
> - ❌ 具体回滚脚本(由专门团队负责)
> - ❌ GCP Support ticket 跟进(团队已知 zone 资源不足,与谷歌已达成一致)
>
> **核心答案**:
> 1. **EVEN vs BALANCED**:EVEN 像"严格平均分座位"(即使角落没座位,其他座位也不能坐满);BALANCED 像"哪里有座位就坐哪"(可能 3:2:0)
> 2. **Instance redistribution** 必须改成 **NONE**——因为 BALANCED 的"哪里有座位就坐哪"语义**自带重平衡**(再 enable 会冲突)
> 3. **对生产的影响**:**主要损失** canary deployment(双版本灰度)能力 + zone 故障时负载不均分;**主要收益** autoscaling 不再被 zone 容量卡死

---

## TL;DR

| 维度 | EVEN → BALANCED 影响 |
|---|---|
| **生产可用性** | ⚠️ **轻微下降** —— zone 故障时,流量会先涌到剩余 zone 但**不自动均衡**(enable redistribution 不能用了) |
| **autoscaling 行为** | ✅ **改善** —— 这就是本变更的目的(绕过 `zone_resource_exhausted`) |
| **canary deployment(双版本灰度)** | ❌ **失去能力** —— BALANCED 强制 single version,**全量替换** |
| **zone 分布均匀性** | ❌ **失去保证** —— 可能 3:2:0 这种不均匀,依赖容量可用性 |
| **Instance redistribution** | ⚠️ **强制改成 NONE** —— 见 §2.2 详细解释 |
| **回滚** | ✅ 可行 —— gcloud in-place update 改回 EVEN + PROACTIVE |

---

## 1. 4 种 `target-distribution-shape` 一句话比喻

| Shape | 一句话比喻 | 业务语义 |
|---|---|---|
| **EVEN**(default) | **严格平均分座位** —— 即使角落没座位,其他座位也不能坐满 | "我要保证每个 zone 的 VM 数差异 ≤1" |
| **BALANCED** | **哪里有座位就坐哪** —— 尽量平均但不保证 | "我先保证能扩,均匀性是次要的" |
| **ANY** | **随便坐** —— 各 zone 数量完全没约束(可能 0:0:N)| "我不在乎分布,只要有 VM 就行" |
| **ANY_SINGLE_ZONE** | **所有座位集中在同一排** —— 全 zone 都在一个 zone | "Batch 任务,VM 间需低延迟" |

### 1.1 EVEN 下的 zone_resource_exhausted 行为详解

```
场景:target size = 9 (期望 3 zone 各 3 个),zone C 容量满

  Zone A        Zone B        Zone C
  ┌─────┐       ┌─────┐       ┌─────┐
  │VM1  │       │VM1  │       │???  │ ← C 没容量
  │VM2  │       │VM2  │       │???  │
  │VM3  │       │VM3  │       │???  │
  └─────┘       └─────┘       └─────┘
   3/3 ✓         3/3 ✓         0/3 ✗ zone_resource_exhausted
                                     ↑
                            EVEN 要求差异 ≤1,
                            A/B 不能扩到 4 来"补"
                            → 整个 scale-out 卡死
```

### 1.2 BALANCED 下的同一场景

```
场景:target size = 9,zone C 容量满(同上)

  Zone A        Zone B        Zone C
  ┌─────┐       ┌─────┐       ┌─────┐
  │VM1  │       │VM1  │       │???  │ ← C 没容量,MIG 跳过
  │VM2  │       │VM2  │       │???  │
  │VM3  │       │VM3  │       │???  │
  │VM4  │       │VM4  │       │???  │ ← A 扩到 4
  │VM5  │       │VM5  │       │???  │ ← A 扩到 5(B 同样)
  └─────┘       └─────┘       └─────┘
   5/5 ✓         4/5 ✓         0/5 ⚠ 不均匀但容量够

 → 9 个 VM 总数达成,即使 zone C 没容量
 → 失衡代价: zone A/B 流量将不均匀,单 zone 故障时 RPS 压力大
```

---

## 2. Instance Redistribution 详解(本次最关键的疑问)

### 2.1 这个参数是什么?

`Instance redistribution` 是 MIG 的**自愈机制** —— 当 MIG 发现各 zone VM 数**不均匀**时,主动删除多余的、补充缺少的,让分布**重新变均匀**。

类比:**教室里的"纠察员"**,看到哪排多了就去搬走一个到少的那排。

### 2.2 EVEN 和 BALANCED 下 redistribution 的语义完全不同

| Mode | EVEN + Proactive | BALANCED + None |
|---|---|---|
| **何时触发** | MIG 主动巡查到不均 | ❌ **永不触发**(参数被强制 NONE) |
| **删除多余 VM 的位置** | 多的 zone | N/A(无纠察员) |
| **zone 故障恢复后** | 自动补齐缺少的 zone | ❌ **不补齐**(手残党,坏了也不管) |
| **MIG 内部状态** | "强制均匀" | "哪能扩就扩哪" |

### 2.3 为什么 BALANCED 必须强制 NONE?

**核心原因**:两种模式**目标函数相反**:

- **EVEN + Proactive** = "我要均匀,所以我要主动纠偏"
- **BALANCED** = "我要容量优先,均匀不保证"

如果 BALANCED 强制 enable redistribution,会出现**死循环**:

```
T0: BALANCED 在 zone A 扩到 5 个
    ↓
T1: redistribution 看到不均,删除 zone A 多余 2 个
    ↓
T2: autoscaler 又在 zone A 扩(因为 zone C 还是没容量)
    ↓
T3: redistribution 又删除 ...
    ↓
    无限循环,VM 反复创建/删除
```

→ GCP 设计上直接**禁止**这种组合。

### 2.4 改后丢失的能力(架构影响)

**改前**(EVEN + Proactive):
- ✅ zone 故障恢复 → 容量自动恢复
- ✅ 手动删 VM → MIG 自动补齐
- ✅ MIG 跨 zone 自愈均衡

**改后**(BALANCED + None):
- ❌ zone C 容量恢复 → **容量不会自动回到 zone C**
- ❌ 手动删 VM → MIG 不会主动补
- ❌ zone 分布永久不均,需手动 `gcloud ... resize` 拉大 target size 触发重平衡

→ **实际影响**:**zone 故障的恢复速度变慢**(从"分钟级自动"变成"人工手动")。

---

## 3. EVEN → BALANCED 的架构层面影响汇总

| 维度 | 改前(EVEN)| 改后(BALANCED)| 架构结论 |
|---|---|---|---|
| **autoscaling 触发** | 卡在 `zone_resource_exhausted` | ✅ 跳过受限 zone | **本次变更的目的** |
| **zone 分布均匀性** | 差异 ≤1 强制 | 不保证(可能 3:2:0)| ⚠️ 单 zone 故障时负载不均 |
| **单 zone 故障后恢复** | 自动重平衡(分钟级)| ❌ 手动 resize(小时级)| ⚠️ 恢复 SLA 变差 |
| **canary deployment** | ✅ 双版本灰度 | ❌ single version 全量替换 | ❌ **若团队依赖 canary 必须先评估** |
| **新 zone 容量恢复** | 自动迁移 VM | ❌ 不会迁移(永久不均)| ⚠️ 需主动 resize 触发 |
| **Reservation 利用** | 每 zone 独立 | region 共享 | ✅ 利用更充分 |

---

## 4. 架构师建议(高层判断,不含操作)

### 4.1 本次变更是否合理?

✅ **合理** —— `zone_resource_exhausted` 是 GCP 已知问题,BALANCED 是官方推荐的 zonal capacity 受限时的备选。

### 4.2 三个核心 trade-off

```
当前 EVEN  +Proactive        改后 BALANCED + None
┌──────────────────┐         ┌──────────────────┐
│ ✅ 严格均匀       │         │ ❌ 分布不均       │
│ ✅ canary 灰度    │         │ ❌ 单 version 全量│
│ ✅ 自愈重平衡     │         │ ❌ zone 故障恢复慢│
│ ❌ 扩缩容卡死     │         │ ✅ 扩缩容宽容     │
└──────────────────┘         └──────────────────┘
```

→ **交换的本质**:**用"分布均匀性 + 自愈能力 + canary"换"扩缩容宽容"**。

### 4.3 必须先回答的问题(给业务方)

| # | 问题 | 影响决策 |
|---|---|---|
| Q1 | 团队**是否在用 canary deployment**?(GKE Deployment + Argo Rollouts / Spinnaker canary 等)| 是 → **强烈反对此次变更**(canary 是高频灰度需求)|
| Q2 | 单 zone 故障的**恢复 SLA** 是多少?(分钟级 vs 小时级)| 是小时级 SLA → 需配自动 resize 告警 |
| Q3 | zone 资源耗尽是**几天内临时** 还是**长期几个月**? | 是长期 → 考虑申请 GCP capacity reservation 而非改 shape |

### 4.4 架构师强观点

1. ⚠️ **若 canary deployment 是核心发布流程**——**不要做此次变更**。改用 GCP capacity reservation(预留资源)或增加 MIG over-provisioning size 应对。
2. ⚠️ **若 canary 是可选**——做本次变更,但**必须配手动 resize 流程 + 监控告警**应对 zone 故障恢复。
3. ❌ **不要回退方案不明**——本次是临时缓解还是长期方案?若是临时,zone 容量恢复后必须改回 EVEN。
4. ✅ **本变更不应进入 Terraform**——会触发 destroy/recreate。需手工用 gcloud 维护。

---

## 5. 简明总结

**EVEN 模式**(当前):
- 像严格平均分座位 — 各 zone VM 数永远差异 ≤1
- 自带纠察员(Instance Redistribution) — 不均时自动重平衡
- 支持 canary 灰度
- **坑**:zonal 资源耗尽时,autoscaling 卡死

**BALANCED 模式**(目标):
- 像哪里有座位坐哪 — 跳过没容量的 zone
- **没有纠察员**(强制 NONE) — 改后不均会永久不均
- **不支持 canary** — 必须 single version
- **坑**:单 zone 故障后,容量不能自动恢复

**核心 trade-off**:**用"均匀性 + 自愈 + 灰度"换"扩缩容宽容"**。

---

## 6. 一句话回答 Lex 的具体疑问

> "Target distribution shape == Even (Maintain an equal number of instances across zones. May fail to scale if a zone lacks capacity)"
>
> ✅ **这句话完全准确**。EVEN = 均匀优先,可能扩不动;BALANCED = 容量优先,均匀不保证。

> "Instance redistribution ==> Enable ... 如果改成 balanced 的话 这里只能是 none 了,实例再分配就没有这个选项了,他有什么影响?"
>
> ✅ **完全正确**。EVEN + Proactive redistribution = "纠察员"模式,zone 不均时主动调平;BALANCED + NONE redistribution = "放养"模式,zone 永久不均需人工干预。
>
> **架构影响**:**zone 故障恢复变慢** —— 以前是 MIG 自动把流量切到剩余 zone 并自动补齐容量(分钟级),改后变成手动 resize 拉大 target size(小时级)。
>
> **架构师判断**:若业务方 SLA 容许小时级恢复,本变更可接受;若要求分钟级,**应优先申请 GCP capacity reservation** 而非改 shape。

---

**作者备注**:2026-09-07 v2.0 精简版(由业务方反馈"不需操作细节"后重写)。原版含完整 gcloud / Terraform 命令 + 实施 checklist — 这些由专门团队负责,本文档聚焦**概念 + 架构 trade-off**。