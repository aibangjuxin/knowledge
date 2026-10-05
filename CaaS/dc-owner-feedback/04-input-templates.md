# 04 · 输入与声明模板

> **用途**:RFC 要求消费方"声明意图;云厂商细节从已批准的画像中解析"(§5)。
> 也就是说 —— **业务方填的表单不应该有"选哪个 VPC""用哪个机型"这类字段。**
> 这些由 CaaS 从画像解析。
>
> 本文件给两张表:① 新建路径(ClusterRequest)② BYOC 路径(ClusterRegistration / 发现授权)。
> **所有 `☐` 需要你或业务方填写;所有 `🔶` 是你必须先定好的边界。**

---

## 一、模板 A · 新建路径:集群申请输入

对应 RFC §9.1 准入条件 + §7 工作负载声明。

```yaml
# ============================================================
# DC 集群申请 · 输入表
# 提交给 app.caep CaaS Portal。此处不出现任何云厂商专有字段。
# ============================================================

meta:
  request_id: ""              # 由 CaaS 生成
  submitted_by: ""            # 申请人
  business_owner: ""          # 业务负责人(邮件)—— CaaS 会用于升级/迁移通告
  submitted_at: ""

# ---------- 1. 用途与类别(RFC §7 四类之一) ----------
workload:
  category: ""                # ☐ 通用应用
                            # ☐ 大型/专业客户  ← 触发专属集群评估
                            # ☐ AI / Agent     ← 触发加速器校验,见下方 accelerators
                            # ☐ 数据类          ← 触发数据驻留强校验
  purpose: ""                 # 一句话。例:"承载支付网关的异步对账"
  criticality: ""             # ☐ 生产 ☐ 非生产 —— 决定 profile 与 SLA 路径

# ---------- 2. 环境与集群数量(RFC §9.1 硬要求) ----------
environments:
  number: 0                  # 需要几个环境实例
  instances:                 # 每个实例独立登记、独立纳管
    - env: ""                # ☐ dev ☐ staging ☐ test ☐ prod
      region_preference: []  # 偏好 region。🔶 必须 ⊆ DC 允许清单(见 WP-2)
      sized_for: ""          # 该环境预期承载什么
  # ⚠️ RFC §9.1:非生产与生产必须是"相互独立"的集群实例。
  #    混用型集群会被 CaaS 拒绝。DC 若有存量混用集群,先看 05 号文件 §4。

# ---------- 3. 能力诉求(不是云配置,是"需要什么") ----------
capabilities_required:
  needs_accelerator: false   # true → 必须填 accelerators
  needs_service_mesh: false  # 🔶 取决于 WP-5 的 mesh 立场
  needs_private_nodes: true  # 控制面无公网 IP?
  needs_confidential_compute: false   # 🔶 注意三条限制(见 03 号文件 §3.4)
  needs_cmek: false          # 静态加密密钥自管
  needs_scheduled_autoscaling: true
  needs_multi_region: false  # 跨 region 部署 → 触发数据流动治理(§7 数据类)
  other: ""

accelerators:                # 仅当 needs_accelerator: true
  type: ""                   # ☐ NVIDIA GPU ☐ TPU ☐ 高内存(A3 类)
  gpu_type: ""               # e.g. A100 / L4 / H100
  count_per_pod: 1
  isolation_requirement: ""  # ⚠️ "独占拓扑"?GCP 给不了(见 03 号文件 §3.5)
                            #    → 这里填的如果是"独占",CaaS 放置校验会拒绝
  count: 0
  quota_budget: ""           # 该项目的 GPU 配额(🔶 需你提供查法)

# ---------- 4. 网络诉求 ----------
network:
  ingress_from: ""           # 内网 / 公网 / 专线 / 混合
  cross_project_dependencies: []   # 需要访问哪些其它项目的内部服务
  egress_external: []        # 需要出网访问的外部 API(如模型服务、GitHub)
  # 🔶 出口管控政策由你提供(03 号文件 §3.3)
  data_classification: ""    # ☐ 公开 ☐ 内部 ☐ 机密 ☐ 受监管
  data_residency_constraint: ""   # 是否有数据必须留在特定区域的要求

# ---------- 5. 可用性与恢复(RFC §6.3 契约项 5) ----------
availability:
  target_availability: ""    # 描述即可,数值 SLO 由 SRE 定(RFC §3 非目标)
  tolerates_control_plane_upgrade: true   # GKE 升级可能需短暂影响
  tolerates_node_drain: true
  maintenance_window: ""     # 🔶 窗口由你定义(见 WP-3)
  backup_requirement:
    rpo: ""
    rto: ""
    retention: ""            # 🔶 保留期与数据分级挂钩
    drill_frequency: ""      # RFC §6.3 要求"恢复与灾备演练按约定周期执行"

# ---------- 6. 规模与成本(RFC §7 / FinOps) ----------
scale:
  initial_size: ""           # 初始规模区间
  expected_growth: ""
  autoscaling_bounds: { min: , max: }
  cost_center: ""            # 🔶 成本归集字段
  budget_alert_threshold: ""

# ---------- 7. 声明性输入的边界(关键) ----------
# 申请人【不应】在此填写:
#   ❌ VPC 名 / 子网名 / CIDR      → CaaS 从画像解析
#   ❌ 机器型号 / 节点数             → CaaS 按 profile 选
#   ❌ release channel              → CaaS 统一管理
#   ❌ 安全例外                     → 走独立审批流,不在申请单里塞
#   ❌ 任何 service 账号 / 密钥      → 绝不在申请单中出现
#
# 例外(可申请,但需 justification + 审批):
#   · providerOverrides(逃逸舱口)   → 需 justification
#   · 额外安全例外                  → 需指定审批人 + 有效期
```

---

## 二、模板 B · BYOC 路径:存量集群登记与发现授权

对应 RFC §9.1 + §9.2 阶段 1–2。

```yaml
# ============================================================
# DC 存量集群登记 · ClusterRegistration
# ⚠️ 阶段顺序是强制的:先 Register,再授权只读发现(Discover),
#    之后才谈移交。没有 Discover 授权就没有 Assessment。
# ============================================================

# ---------- 阶段 1:Register(登记) ----------
registration:
  cluster:
    gcp_project_id: ""
    cluster_name: ""
    location: ""              # region 或 zone
    mode: ""                  # ☐ Standard ☐ Autopilot
    k8s_version: ""
    release_channel: ""       # 🔶 若为"(未加入频道)"需整改 —— 标为已知差距
    created_at: ""
  ownership:
    business_owner: ""        # 责任人(到人,不是到部门)
    technical_contact: ""
    cost_center: ""
  scope:
    # CaaS 发现后需要能识别的边界
    environments_served: []   # 🔶 若同时含 dev+prod → 触发 §9.1 冲突
    namespace_count: 0
    workload_count: ""
    node_count: ""
  known_gaps:                 # 现在就知道的,提前写,省掉阶段 3 的来回
    - ""
  constraints:
    maintenance_window: ""
    cannot_be_disrupted_dates: []
    data_classification: ""

# ---------- 阶段 2:Discover(发现)—— 授权书 ----------
discovery_authorization:
  granted_to: ""             # CaaS 服务身份
  scope:
    read_only: true           # 明确声明只读
    cloud_iam_roles: []       # 🔶 需你提供具体的只读角色
                             #    (见 01 号文件 WP-4 的三身份模型)
    cluster_rbac: []          # 🔶 集群内只读 RBAC
  validity:
    granted_at: ""
    expires_at: ""            # ⬜ 强烈建议设过期。永久只读授权 = 长期敞口
  revocation_procedure: ""    # 怎么撤销 —— 保留原运维方的安全退路
  conditions: []              # 例:"发现阶段不得写入任何资源"

# ---------- 阶段 3-8 的前置检查(自评用,不用填) ----------
readiness_checklist:
  separate_nonprod_and_prod: []       # §9.1 硬要求
  has_release_channel: []
  has_release_authorization: []       # §9.2 阶段 6,谁签字
  has_backup_and_restore: []          # §6.3 契约项 5
  has_data_classification: []         # §9.1
  has_workload_inventory: []          # §6.3 契约项 6
  has_exit_plan: []                   # §6.3 契约项 4
```

> #### ⚠️ 关于 `discovery_authorization.expires_at`
>
> 我建议**强制要求一个过期时间**,理由:
> BYOC 阶段 2–5(Discover / Assess / Remediate / Integrate)可能拖几个月。
> 如果授权是永久的,那么当这个项目**最终放弃纳管**时,
> CaaS 仍然持有这个集群的只读访问权,而**没有任何机制会自动撤销**。
>
> RFC §9.4 有 `Suspended or management withdrawn` 状态,
> 但它描述的是"已被纳管后被收回",没有覆盖"纳管从未完成"的场景。
> **这是一个 RFC 的空白点,值得作为一条开放问题提上去**(见 `07-decisions-and-open-questions.md` O9)。

---

## 三、模板 C · 写给业务的填写指引(可直接转发)

给 DC 业务方的三句话版本,避免他们填出 CaaS 拒收的东西:

> **1. 你填的是"要什么",不是"怎么建"。**
> 不要在申请单里选 VPC、机器型号、节点数。填了也会被忽略,且可能误导排期。
>
> **2. "数据分级"和"数据驻留"不是形式。**
> 这两项直接决定你的集群会被放到哪个 region。如果你的数据有监管要求,
> 填错会在放置阶段被拒 —— 而那时你可能已经改了很多配置。
>
> **3. 有三件事填了会被打回,请提前确认:**
> - **非生产和生产必须在不同集群**。同集群混用不接受。
> - **AI/GPU 工作负载**如果需要"独占拓扑" —— GCP 目前给不了,会在放置阶段被拒。
>   请改成"配额隔离 + 专用节点池"。
> - **维护窗口**要填。GKE 升级会自动发生,你有权知道发生的时间。

---

**修订记录**

| 日期       | 内容                    |
| ---------- | ----------------------- |
| 2026-09-29 | 初版                    |
