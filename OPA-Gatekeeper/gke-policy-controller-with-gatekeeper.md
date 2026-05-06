# GKE Policy Controller vs Standalone Gatekeeper 选型指南

> **文档版本**: 2.0.0
> **更新日期**: 2026-05-01
> **目标读者**: 平台架构师、SRE、DevOps 工程师

---

## 1. 背景与核心问题

### 1.1 你的实际环境

| 平台 | 当前状态 | Policy Controller 支持 |
|------|----------|----------------------|
| **GKE** | 生产环境 | ✅ 原生集成，Fleet 统一管理 |
| **阿里云 ACK** | 规划/部分上线 | ⚠️ 需手动部署 Gatekeeper |
| **其他原生 K8s** | 未来可能 | ❌ 需独立部署 |

### 1.2 核心选型问题

```
Q: GKE Policy Controller（托管版）还是 Standalone Gatekeeper（开源版）？
   └── 约束：阿里云 ACK 也需要运行同一套策略
```

**结论预览**：多云场景下，**Standalone Gatekeeper 是唯一正确的选择**。理由见下文。

---

## 2. 产品本质对比

### 2.1 不是什么神秘感，先破除误区

| 误区 | 真相 |
|------|------|
| "GKE Policy Controller 和 Gatekeeper 是两个不同东西" | **两者代码完全相同**。Policy Controller 是 Google 托管 + 增强的 Gatekeeper。 |
| "GKE Policy Controller 功能更多" | **核心功能完全一致**。差异在于：预置策略库、Console 集成、Fleet 管理平面。 |
| "Standalone Gatekeeper 升级很危险" | Gatekeeper **版本高度向后兼容**，升级很少破坏已有 Constraint。 |
| "阿里云上没有 Gatekeeper" | **完全可以在 ACK 上运行**，没有任何限制。 |

### 2.2 官方定义

```
GKE Policy Controller = Gatekeeper 社区版 + Google 托管控制平面 + 预置策略库 + Fleet 管理
```

Google 从未对 Gatekeeper 本身做 Fork，所有新增代码都在 Gatekeeper 上游。

---

## 3. 架构评估框架（系统化选型方法论）

### 3.1 决策树

```
你的集群类型？
├── 全部是 GKE？
│   └── 需要多集群统一管理？
│       ├── YES → GKE Policy Controller + Fleet（最省心）
│       └── NO  → 两者皆可，GKE Policy Controller 略优
│
└── 包含 GKE + 阿里云 ACK + 其他 K8s？
    └── 唯一选项：Standalone Gatekeeper + GitOps
    └── 理由：GKE Policy Controller 无法在非 GKE 集群运行
```

### 3.2 评估维度与权重（多云场景）

| 评估维度 | 权重 | 说明 |
|----------|------|------|
| **跨平台一致性** | 35% | 同一套 Rego 代码能否在所有集群运行 |
| **运维可控性** | 25% | 版本升级节奏、故障排查复杂度 |
| **功能完整性** | 20% | 预置策略、审计、日志、UI |
| **多集群管理效率** | 15% | 策略下发、多集群一致性 |
| **初始落地速度** | 5% | POC 阶段的快慢（权重最低，因为这是短期因素） |

**关键洞察**：多云场景下，"跨平台一致性"权重最高（35%），而 GKE Policy Controller 在这一项得分为 **0**（根本无法在 ACK 运行），所以综合得分必然低于 Standalone Gatekeeper。

---

## 4. GKE Policy Controller 深度分析

### 4.1 优势

| 优势 | 说明 |
|------|------|
| **零运维安装** | `gcloud container fleet policy-controller enable` 一键启用，Google 负责升级 |
| **预置策略库** | 100+ 官方策略，覆盖 CIS Benchmark、Security Best Practices，开箱即用 |
| **Fleet 统一管理** | 多集群策略通过 Fleet 单一控制平面下发，无需 SSH 到每个集群 |
| **Console 原生集成** | 在 GKE Console 直接查看策略违规情况 |
| **Cloud Logging 原生** | 违规日志自动写入 Cloud Logging，无需额外配置 |
| **支持 Policy Bundles** | 支持通过 `Policy` CRD 引用远程策略库 URL |

### 4.2 劣势

| 劣势 | 说明 |
|------|------|
| **版本滞后** | Gatekeeper 更新后，GCP 通常延迟 1-3 个月才同步 |
| **功能上限** | 无法使用社区最新 Gatekeeper 功能（如最新 Rego 特性） |
| **跨云不兼容** | **无法在阿里云 ACK、其他 K8s 上运行**——这是致命问题 |
| **黑盒调试** | 问题排查需要看 GCP 文档，有限的社区支持 |
| **成本** | GKE Standard/Autopilot 费用已包含，但失去独立选择权 |
| **Helm/Templating 限制** | 预置策略通过 Config Sync 管理，不够灵活 |

### 4.3 版本现状（截至 2026-05）

GCP 托管的 Policy Controller 版本通常落后社区 1-2 个 minor 版本。如果需要最新 Gatekeeper 功能（如 OPA 2.0 特性），GKE Policy Controller 无法提供。

---

## 5. Standalone Gatekeeper 深度分析

### 5.1 优势

| 优势 | 说明 |
|------|------|
| **跨平台运行** | 任何 K8s 集群均可运行：GKE、ACK、EKS、自建 |
| **版本自主** | 可选择任意版本，按需升级，不受云厂商限制 |
| **社区活跃** | CNCF 毕业项目，社区驱动，文档丰富 |
| **GitOps 原生** | 可与 ArgoCD、Flux 完全集成，策略即代码 |
| **灵活部署** | 支持 Helm、kubectl、Operator 多种部署方式 |
| **完全透明** | 调试无黑盒，直接访问所有日志和状态 |
| **最新功能** | 第一时间使用社区新特性和 Bug 修复 |

### 5.2 劣势

| 劣势 | 说明 |
|------|------|
| **需要手动升级** | 升级 Gatekeeper 版本需要人工操作（或自动化 pipeline） |
| **无原生预置策略** | 需从 [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library) 手动导入 |
| **多集群管理需额外工具** | 无 Fleet 级别的统一控制平面；需要 ArgoCD/Flux 或商业产品 |
| **无原生 Console UI** | 策略违规查看依赖 `kubectl` 或自建 Dashboard |
| **日志需自行配置** | 审计日志需要额外配置 Cloud Logging、ELK 或类似方案 |
| **初始安装复杂度** | 比 GKE Policy Controller 多 5-10 个步骤 |

### 5.3 阿里云 ACK 兼容性确认

ACK 对 Gatekeeper **没有做任何定制或限制**。Gatekeeper 以 DaemonSet + Deployment 方式运行在 ACK 上，行为与社区完全一致。

| 检查项 | ACK 兼容情况 |
|--------|-------------|
| Kubernetes API | ✅ 完全兼容 |
| RBAC | ✅ 完全兼容（使用 RAM 权限体系） |
| 网络策略 | ✅ 与 Cilium/Calico/Terway 均兼容 |
| Hel安装 | ✅ `helm install gatekeeper` 正常工作 |
| Admission Webhook | ✅ 标准 Mutating/ValidatingWebhook 配置 |
| 阿里云服务账号集成 | ⚠️ 需要额外配置（无 Workload Identity 直接对应） |

---

## 6. 策略可移植性：Rego 代码跨平台要点

### 6.1 核心原则：仅使用 Kubernetes 原生数据

```rego
# ✅ GOOD：完全可移植
input.review.kind.kind
input.review.namespace
input.review.object.metadata.labels
input.review.object.spec.containers

# ❌ BAD：平台特定依赖
data.google_storage_bucket.example   # GCP 特定
data.aliyunoss_bucket.example        # 阿里云特定
```

### 6.2 版本要求

| 组件 | 最低版本 | 推荐版本 |
|------|----------|----------|
| Gatekeeper | v3.9.0 | **v3.14.x**（最新稳定版） |
| ConstraintTemplate API | v1 | v1 |
| Constraint API | v1beta1 或 v1 | v1 |
| Kubernetes | 1.20+ | 1.26+ |

### 6.3 可移植性验证流程

```
Step 1: 在 GKE 测试 ConstraintTemplate + Constraint
Step 2: 导出 YAML（kubectl get -A -o yaml）
Step 3: 在 ACK 应用相同 YAML
Step 4: 验证 ConstraintTemplate CRD 创建成功
Step 5: 验证 Constraint 实例化成功
Step 6: 提交到 GitOps 仓库
```

---

## 7. 多集群管理方案对比

### 7.1 GKE Policy Controller + Fleet（GKE Only）

```
✅ 优点：
  - 单命令启用，多集群自动同步
  - 策略违规统一视图
  - GCP Console 原生集成

❌ 缺点：
  - 只能管理 GKE 集群
  - 阿里云 ACK 完全无法加入
```

### 7.2 Standalone Gatekeeper + ArgoCD/GitOps（推荐）

```
✅ 优点：
  - 统一 Git 仓库管理所有集群策略
  - 声明式配置，版本可追溯
  - 任何 K8s 集群均可加入
  - PR Code Review 流程天然具备

❌ 缺点：
  - 需要维护 ArgoCD/Flux 安装
  - 初始配置比 Fleet 多
```

### 7.3 多集群管理架构图

```
┌─────────────────────────────────────────────────────────┐
│                    GitOps Repository                     │
│   (policy-library/: templates + constraints + values)   │
└────────────────────────┬────────────────────────────────┘
                         │ push / PR merge
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  GKE Cluster │  │ ACK Cluster │  │  EKS Cluster │
│ (Standalone) │  │ (Standalone) │  │ (Standalone) │
│  Gatekeeper  │  │  Gatekeeper  │  │  Gatekeeper  │
└─────────────┘  └─────────────┘  └─────────────┘
         ▲               ▲               ▲
         │               │               │
    ArgoCD Sync     ArgoCD Sync     ArgoCD Sync
```

---

## 8. 关键风险与缓解措施

### 8.1 Standalone Gatekeeper 风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| 版本升级导致策略失效 | 低 | 高 | 升级前在 dev 环境测试；Gatekeeper 升级向后兼容性强 |
| 多集群策略不一致 | 中 | 中 | GitOps 强制单一真相来源；CI 检查 |
| ACK 上 Gatekeeper 性能不足 | 低 | 中 | 监控 Gatekeeper Pod CPU/内存，按需扩容 replica |
| 策略误判导致集群故障 | 低 | 高 | initial 版本 enforcementAction=dryrun；确认后再 warn/enforce |

### 8.2 GKE Policy Controller 风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| 版本落后导致无法使用新特性 | 中 | 低 | 评估新功能必要性；等待 GCP 更新 |
| 阿里云无法接入 Fleet | N/A | 高 | **若有多云计划，开始就别选这条路** |
| 策略库与社区不同步 | 低 | 中 | 定期对比 gatekeeper-library 版本与 Fleet 版本 |

---

## 9. 总拥有成本（TCO）对比

### 9.1 运维成本

| 维度 | GKE Policy Controller | Standalone Gatekeeper |
|------|----------------------|----------------------|
| **初始安装** | 5 分钟 | 30-60 分钟 |
| **月度维护** | ~0（Google 托管） | ~2-4 小时（版本追踪、升级测试） |
| **多集群管理** | Fleet 原生（仅 GKE） | ArgoCD/Flux（所有集群） |
| **故障排查** | 依赖 GCP 文档 | 社区 + 代码，透明度高 |
| **升级风险** | 低（Google 保证兼容性） | 低-中（需测试） |

### 9.2 真实成本估算

假设 5 个集群（3 GKE + 2 ACK），维护周期 1 年：

| 方案 | 工程时间 | 说明 |
|------|----------|------|
| GKE Policy Controller（仅 GKE） + ACK 无策略 | ~0 | ACK 无保护，**不建议** |
| GKE Policy Controller + ACK 独立 Gatekeeper | ~40h/年 | 两套体系，维护成本高 |
| **统一 Standalone Gatekeeper + GitOps** | **~60h/年（初期）/ ~20h/年（稳定后）** | 一次投入，长期收益 |

---

## 10. 推荐架构（你的具体场景）

### 10.1 最终推荐：统一 Standalone Gatekeeper + ArgoCD

```
理由：
1. 阿里云 ACK 必须能运行 —> GKE Policy Controller 排除
2. GKE Policy Controller 的 Fleet 管理优势在多云场景下消失
3. Standalone Gatekeeper 在 GKE 上同样完美运行
4. GitOps 提供了比 Fleet 更强的跨云管理能力
```

### 10.2 推荐的 Gatekeeper 版本

| 组件 | 推荐版本 | 备注 |
|------|----------|------|
| Gatekeeper | **v3.14.x** | 最新稳定版，3.15 即将发布 |
| Helm Chart | 3.14.x | 与 Gatekeeper 版本对齐 |
| gatekeeper-library | release-2026.04 | 预置策略库 |

### 10.3 推荐目录结构

```
policy-library/
├── Chartfile                          # Helm chart (可选)
├── Chart.yaml
├── values.yaml                        # 公共配置
├── values/
│   ├── gke.yaml                       # GKE 集群特定值
│   ├── ack.yaml                       # ACK 集群特定值
│   └── common.yaml                    # 共享值
├── templates/                         # ConstraintTemplate（跨集群复用）
│   ├── k8srequiredlabels/
│   │   ├── ConstraintTemplate.yaml
│   │   └── lib/
│   │       └── helpers.rego
│   ├── k8scontainerlimits/
│   └── nocontainersecuritycontext/
├── constraints/                       # Constraint 实例
│   ├── prod/                          # 生产环境
│   │   ├── gke/
│   │   │   └── require-labels.yaml
│   │   └── ack/
│   │       └── require-labels.yaml
│   └── dev/                           # 开发环境（规则可能更宽松）
└── scripts/
    └── validate.sh                    # CI 验证脚本
```

**关键原则**：`templates/` 目录内容**完全不区分云平台**；`constraints/` 按集群差异化配置。

---

## 11. GKE 上要不要禁用 Policy Controller

### 11.1 如果你决定使用 Standalone Gatekeeper

**推荐：在 GKE 上禁用 GKE Policy Controller，避免双重运行。**

```bash
# 禁用 GKE Policy Controller
gcloud container clusters update my-cluster \
  --disable-policy-controller \
  --region=europe-west2

# 确认禁用
gcloud container clusters describe my-cluster \
  --region=europe-west2 \
  --format="value(policyController)"
```

**原因**：GKE Policy Controller 和 Standalone Gatekeeper **不能同时启用**针对同一集群的 Admission Webhook，否则会产生冲突（双重拦截）。

### 11.2 如果你暂时无法关闭 Policy Controller

可以保留 Policy Controller 用于 GKE 集群的防护，同时在 ACK 上安装独立的 Gatekeeper。此方案缺点是维护两套策略代码（虽然 Rego 可以复用），短期可接受。

---

## 12. 迁移路径（如果已用 GKE Policy Controller）

### 12.1 平滑迁移步骤

```
Phase 1: 在测试集群验证（1-2天）
  ├── 禁用 GKE Policy Controller
  ├── 安装 Standalone Gatekeeper v3.14.x
  ├── 应用现有 ConstraintTemplate YAML
  ├── 验证策略效果一致
  └── 记录差异（如有）

Phase 2: 灰度推广（1周）
  ├── 选择 1 个非生产 GKE 集群
  ├── 禁用 Policy Controller，启用 Standalone
  ├── 观察 1 周
  └── 确认无问题后继续

Phase 3: 全量切换（1-2周）
  ├── 所有 GKE 集群切换
  ├── ACK 集群同步部署
  └── 建立 GitOps 工作流

Phase 4: 清理
  └── 移除所有 Policy Controller 配置
```

### 12.2 导出 GKE Policy Controller 策略

```bash
# 导出所有 ConstraintTemplate
kubectl get constrainttemplate -A -o yaml > /tmp/exported-templates.yaml

# 导出所有 Constraint
kubectl get constraint -A -o yaml > /tmp/exported-constraints.yaml

# 审查导出的 YAML（确认无 GCP 特定依赖）
grep -E "google_storage|google_project|gcp" /tmp/exported-templates.yaml
# 应返回空
```

---

## 13. 选型决策矩阵（完整版）

| 评估维度 | GKE Policy Controller | Standalone Gatekeeper | 权重 |
|----------|----------------------|----------------------|------|
| **跨平台一致性** | ❌ 0（仅 GKE） | ✅ 10（所有 K8s） | 35% |
| **运维可控性** | 7（托管，但版本受限） | 8（自主，工具成熟） | 25% |
| **功能完整性** | 8（有预置库） | 7（社区库需手动导入） | 20% |
| **多集群管理效率** | 8（Fleet，仅 GKE） | 8（GitOps，任意集群） | 15% |
| **初始落地速度** | 10（一键启用） | 6（需手动部署） | 5% |
| **加权总分** | **~4.9** | **~8.5** | |

> **结论**：在你的多云场景下，Standalone Gatekeeper 综合得分 **8.5**，GKE Policy Controller 仅 **4.9**（且跨平台得分为 0）。

---

## 14. 常见问题 FAQ

### Q1: GKE Policy Controller 的预置策略能复制到 Standalone Gatekeeper 吗？

**能**。GKE Policy Controller 的预置策略源码全部在 [gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library)。直接 `kubectl apply -f` 即可。

### Q2: 阿里云 ACK 是否有类似 GKE Policy Controller 的托管服务？

阿里云没有推出类似 GKE Policy Controller 的托管策略服务。但阿里云 ACK 提供了**策略管理**相关的企业版功能（如阿里云配置审计 Config审计），与 Gatekeeper 不是同一层。

### Q3: Gatekeeper 和 OPA 的关系是什么？

Gatekeeper 是 OPA 的一个子项目，专门用于 Kubernetes Admission Control。OPA 本身是一个通用策略引擎，Gatekeeper 是其 K8s 专用实现。两者 Rego 语法完全一致。

### Q4: 多集群策略一致性如何保证？

通过 GitOps（ArgoCD/Flux）。所有策略 YAML 存在单一 Git 仓库，ArgoCD 持续监控并同步到所有注册集群。Git 是唯一真相来源，PR 流程提供审计。

### Q5: Gatekeeper 升级会影响已有 Constraint 吗？

**几乎不会**。Gatekeeper 团队严格遵守向后兼容承诺。升级前只需在 dev 环境验证即可。

### Q6: 是否需要 Gatekeeper Operator？

**推荐使用**。Gatekeeper Operator 提供声明式 CRD 管理 Gatekeeper 安装，版本控制更清晰，与 GitOps 工作流天然契合。

```bash
# 安装 Gatekeeper Operator
kubectl apply -f https://operatorhub.io/install/gatekeeper.yaml

# 通过 Operator CR 部署
kubectl apply -f - <<EOF
apiVersion: operator.govmware.com/v1alpha1
kind: Gatekeeper
metadata:
  name: gatekeeper
spec:
  auditInterval: 300s
  validationInterval: 300s
  version: 3.14.0
EOF
```

---

## 15. 参考链接

| 资源 | URL |
|------|-----|
| Gatekeeper 官方文档 | https://open-policy-agent.github.io/gatekeeper/ |
| Gatekeeper GitHub | https://github.com/open-policy-agent/gatekeeper |
| Gatekeeper Library（预置策略） | https://github.com/open-policy-agent/gatekeeper-library |
| GKE Policy Controller 文档 | https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/overview |
| Gatekeeper Operator | https://operatorhub.io/operator/gatekeeper |
| ArgoCD | https://argo-cd.readthedocs.io/ |

---

---

## 16. 真实生产环境评估（50 集群 / 1000 API 场景）

### 16.1 规模参数

| 参数 | 数值 | 备注 |
|------|------|------|
| **GKE 集群** | 40 | 占总数 80% |
| **阿里云 ACK 集群** | 10 | 占总数 20% |
| **API 总量** | ~1000 | 估算值 |
| **GCP 平台 API** | ~800 | 占总量 80% |
| **非 GCP 平台 API** | ~200 | 主要在阿里云 |
| **团队规模** | 未知（假设 5-10 人平台团队） | |

### 16.2 场景特殊性分析

这个比例意味着：

1. **GCP 是绝对主阵地**：80% 的业务负载和 API 在 GKE 上运行
2. **ACK 是扩展阵地**：承载 20% 的 API，通常是地域性或合规性需求
3. **跨平台一致性风险不对称**：ACK 上的 200 个 API 如果策略不一致，风险虽然存在但占比有限
4. **API 数量 vs 集群数量**：40 GKE 集群承载 800 API，平均每集群 20 API；10 ACK 集群承载 200 API，平均每集群也是 20 API，负载分布相对均衡

### 16.3 在这个规模下的选型影响

#### 场景 A：GKE Policy Controller（GKE Only）+ 独立方案处理 ACK

```
GKE 40 集群：
  → GKE Policy Controller（Fleet 统一管理）
  → 优点：原生、零运维、策略库丰富
  → 缺点：ACK 无法接入

ACK 10 集群：
  → 独立部署 Standalone Gatekeeper
  → 优点：完全隔离，ACK 自主管理
  → 缺点：两套策略体系，但模板层 YAML 完全通用
```

**Rego 代码管理策略**：

```
templates/           ← Git 统一管理，GKE 和 ACK 共用
  K8sRequiredLabels/
  NoPrivilegedContainer/

constraints/
  gke/               ← GKE Policy Controller 用（CRD API 相同，YAML 完全通用）
  ack/               ← ACK Standalone Gatekeeper 用（YAML 完全通用）
```

> **关键发现**：如果 `templates/`（ConstraintTemplate）统一管理，`constraints/` 的 YAML 格式在 GKE Policy Controller 和 Standalone Gatekeeper 之间**完全通用**。真正需要分开的只是**安装方式**，不是策略代码本身。

#### 场景 B：全部 Standalone Gatekeeper

```
50 集群全部安装 Standalone Gatekeeper
  → 统一 GitOps 管理，50 集群策略一致
  → ACK 集群通过 ArgoCD/Flux 接入
  → GKE 不再使用 GKE Policy Controller
```

### 16.4 量化对比（50 集群 / 1 年）

| 维度 | 场景 A（GKE PC + ACK 独立） | 场景 B（全 Standalone） |
|------|--------------------------|------------------------|
| **GKE 管理复杂度** | 低（Fleet 原生） | 中（通过 ArgoCD/GitOps） |
| **ACK 管理复杂度** | 中（独立集群，各自维护） | 中（统一 ArgoCD） |
| **两套安装流程** | 需要（PC + Standalone） | 不需要（全部 Standalone） |
| **策略代码复用度** | 模板层 100%，Constraint 层 100% | 100% |
| **Fleet 价值** | ✅ 完全发挥（40 GKE 集群） | ❌ 放弃 |
| **ACK 接入 Fleet** | ❌ 不支持 | ✅ 全部接入 GitOps |
| **年度运维时间估算** | GKE: ~0（托管）+ ACK: ~40h/年 | ~60-80h/年（初始）/ ~25h/年（稳定后） |
| **初期建设成本** | 低（GKE 直接启用）+ ACK 手动 | 中（全量 ArgoCD 建设） |

### 16.5 推荐方案（这个规模下）

**推荐：场景 A 的变种 — GKE Policy Controller + Standalone Gatekeeper 混合，模板层统一**

具体做法：

```
GKE 40 集群：
  → 启用 GKE Policy Controller（Fleet 管理）
  → 享受原生预置策略库、CIS Benchmark 等开箱即用
  → 无需手动维护 Gatekeeper 安装

ACK 10 集群：
  → 安装 Standalone Gatekeeper v3.14.x（Helm 部署）
  → 通过 GitOps（ArgoCD）管理模板层和 Constraint 层
  → ConstraintTemplate 与 GKE Policy Controller 完全共用同一套 YAML

策略代码统一层：
  → 所有 ConstraintTemplate YAML 存放在统一 Git 仓库
  → GKE Policy Controller 通过 Config Sync 或手动方式消费同一套模板
  → 实际上：GKE Policy Controller 的 ConstraintTemplate = ACK Standalone Gatekeeper 的 ConstraintTemplate
```

**为什么这样设计**：

1. **GKE Policy Controller 的 Fleet 价值在 40 集群规模下巨大**。不用 SSH 到每个集群，F5 可以统一看到所有 40 个 GKE 集群的策略违规，这在 40 集群规模下省下的运维成本非常可观。
2. **Rego 代码（模板层）天然跨平台**。GKE Policy Controller 和 Standalone Gatekeeper 使用完全相同的 ConstraintTemplate CRD，Git 仓库里的 YAML 两边都可以用。
3. **ACK 10 集群单独维护成本可控**。10 个集群的 Standalone Gatekeeper 维护（年度 ~40h）对于 5-10 人团队来说完全可以接受。
4. **不要让 10 个 ACK 集群拖垮 40 个 GKE 集群的运维体验**。Fleet 的统一视图、统一策略是 GKE 集群的巨大优势，不应该为了追求"完全统一"而放弃。

### 16.6 这个规模下的风险再评估

| 风险 | GKE PC + ACK 独立 | 全 Standalone | 缓解 |
|------|------------------|---------------|------|
| GKE Policy Controller 版本落后 | 中（影响 40 GKE） | 无 | 定期评估；版本一般 1-2 个月延迟，可接受 |
| ACK Gatekeeper 版本需手动升级 | 中（10 ACK 集群） | 中 | 通过 ArgoCD 管理版本；升级前测试 |
| 策略代码两套 | 无（模板层共用） | 无 | — |
| ACK 策略与 GKE 不一致 | 低-中 | 无 | Git 仓库统一管理；CI 检查策略一致性 |
| Fleet 无法管理 ACK | 高（设计如此） | 低（全 GitOps） | ACK 独立 ArgoCD；策略 YAML 仍然统一 |
| 阿里云网络策略与 GKE 不同 | 低 | 低 | Constraint match 规则按集群标签差异化 |

### 16.7 结论

| 维度 | 建议 |
|------|------|
| **GKE 40 集群** | 继续使用 GKE Policy Controller + Fleet |
| **ACK 10 集群** | Standalone Gatekeeper，通过 GitOps 管理 |
| **策略代码** | 统一 Git 仓库存储 ConstraintTemplate，两边共用 |
| **年度成本** | GKE: ~0 + ACK: ~40h/年 ≈ 可以接受 |
| **要不要迁移现有 GKE** | **不要**。已有的 GKE Policy Controller 继续用，收益远大于迁移成本 |

> **一句话总结**：在 40 GKE + 10 ACK 这个配比下，**不要为了统一而统一**。GKE Policy Controller 在 GKE 上的体验优势是真实的，不应该放弃。ACK 上的 10 个集群单独维护 Gatekeeper，成本可控。真正需要统一的是 **ConstraintTemplate（Rego 代码层）**，而不是安装层。

---

*文档版本: 2.0.0 — 2026-05-01*
*Section 16 added: Real production scenario (50 clusters / 1000 API)*
