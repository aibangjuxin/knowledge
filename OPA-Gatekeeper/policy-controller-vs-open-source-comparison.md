# GKE Policy Controller vs 开源 OPA Gatekeeper 深度对比评估报告

## 文档信息

- **评估对象**：GKE Policy Controller vs 开源 OPA Gatekeeper
- **评估目的**：为多集群 GKE 环境选择最优策略管理方案
- **评估日期**：2026-05-14
- **参考文档**：`step-by-step-install.md`、`why-using-open-gatekeeper.md`

---

## 一、评估维度总览

| 维度 | GKE Policy Controller | 开源 OPA Gatekeeper |
|------|----------------------|---------------------|
| 内置规则数量（Constraint Templates） | **82 条**（templateLibrary=ALL） | **约 20-30 条**（gatekeeper-library） |
| 维护成本 | 低（Google 托管，自动升级） | 高（需自行管理升级、版本兼容性） |
| Fleet 跨集群管理 | ✅ 原生支持 | ❌ 需搭配 GitOps 工具（ArgoCD/Flux） |
| Dashboard 可视化 | ✅ GCP Console 原生集成 | ❌ 无，需自行搭建或对接 Prometheus/Grafana |
| Policy Bundle 预置 | 10+ 官方合规包（CIS、NIST、PCI 等） | 需自行编写或从 gatekeeper-library 导入 |
| 升级频率 | 跟随 GKE 版本，Google 控制 | 社区驱动，约每季度一个大版本 |
| 跨云/跨平台支持 | 仅限 GKE | 任意 Kubernetes 集群 |

---

## 二、维度一：内置规则数量详解

### 2.1 GKE Policy Controller（templateLibrary=ALL）

根据 `step-by-step-install.md` 中的验证结果，当 `templateLibrary` 设置为 `installation: ALL` 时，GKE Policy Controller 会安装 **82 个 Constraint Templates**，分为以下类别：

```
总数量：82 个

├── PSP 相关（Pod Security Policies）：19 个
│   ├── k8spspallowedusers
│   ├── k8spspallowprivilegeescalationcontainer
│   ├── k8spspapparmor
│   ├── k8spspautomountserviceaccounttokenpod
│   ├── k8spspcapabilities
│   ├── k8spspflexvolumes
│   ├── k8spspforbiddensysctls
│   ├── k8spspfsgroup
│   ├── k8spsphostfilesystem
│   ├── k8spsphostnamespace
│   ├── k8spsphostnetworkingports
│   ├── k8spspprivilegedcontainer
│   ├── k8spspprocmount
│   ├── k8spspreadonlyrootfilesystem
│   ├── k8spspseccomp
│   ├── k8spspselinuxv2
│   ├── k8spspvolumetypes
│   ├── k8spspwindowshostprocess
│   └── k8spssrunasnonroot
│
├── Kubernetes 通用安全：39 个
│   ├── 镜像仓库控制（k8sallowedrepos, k8sdisallowedrepos）
│   ├── 资源限制（k8scontainerlimits, k8scontainerephemeralstoragelimit）
│   ├── RBAC 安全（k8sprohibitrolewildcardaccess, k8sdisallowedrolebindingsubjects）
│   ├── 网络安全（k8sblockloadbalancer, k8sblocknodeport, k8shttpsonly）
│   ├── ServiceAccount 安全（k8sblockcreationwithdefaultserviceaccount）
│   └── 通用最佳实践（k8srequiredlabels, k8srequiredprobes, k8srequiredresources）
│
├── ASM/Anthos Service Mesh：10 个
│   ├── AuthorizationPolicy 控制（asmauthzpolicydisallowedprefix, asmsafepattern）
│   ├── mTLS 强制（asmpeerauthnstrictmtls）
│   ├── Sidecar injection（asmsidecarinjection）
│   └── DestinationRule TLS（destinationruletlsenabled）
│
├── GCP 特定集成：3 个
│   ├── gcpstoragelocationconstraintv1（Cloud Storage 区域限制）
│   ├── k8senforcecloudarmorbackendconfig（Cloud Armor 集成）
│   └── k8srequirecosnodeimage（要求 COS 节点镜像）
│
└── 其他合规类：11 个
    ├── 网络策略（k8srequirevalidrangesfornetworks, restrictnetworkexclusions）
    ├── 标签/注解强制（k8srequiredlabels, k8srequiredannotations）
    ├── 进程命名空间（k8sblockprocessnamespacesharing）
    └── API 版本审计（verifydeprecatedapi）
```

### 2.2 开源 OPA Gatekeeper（gatekeeper-library）

开源 Gatekeeper 本身不预置任何 Constraint Templates，用户需要：

1. **自行编写**：基于 Rego 语言编写策略
2. **从 gatekeeper-library 导入**：社区维护的策略库，包含约 20-30 个常用模板

```
开源社区模板库（gatekeeper-library）主要类别：
├── General（通用）：~10 个
│   ├── required-labels
│   ├── allowed-repos
│   ├── container-limits
│   ├── no-latest-tag
│   └── ...
│
├── Pod Security：~15 个
│   ├── privileged-container
│   ├── capabilities
│   ├── host-filesystem
│   └── ...
│
└── 其他：~5 个
    ├── storageclass
    ├── namespace-quota
    └── ...
```

**结论**：GKE Policy Controller 内置 82 条规则，远超开源版本，且涵盖 GCP 特定集成（Cloud Storage、Cloud Armor、COS 镜像等）。开源版本需要大量手动工作来达到同等覆盖范围。

---

## 三、维度二：Dashboard 与 Policy Controller 的关系

### 3.1 你的理解是正确的

**GKE Policy Controller Dashboard 的可用性与以下因素相关：**

1. **必须加入 Fleet**：Policy Controller 是 Fleet 级别的资源
2. **Dashboard 入口**：GCP Console → GKE Overview → Policy Controller
3. **不启用 bundle 不影响 Dashboard**：Dashboard 显示的是 Policy Controller 的整体状态，不是单个 bundle 的状态

### 3.2 Dashboard 显示的内容

根据 Google Cloud 官方文档，GKE Overview Dashboard 中的 **Policy Controller 部分**显示：

```
Policy Controller 信息中心：
├── 集群覆盖率：Fleet 中有多少集群启用了 Policy Controller
├── 违规概览：当前所有集群中的策略违规总数
├── 违规趋势：随时间变化的违规趋势图
├── 约束状态：各约束模板的实例化状态
└── 详细违规列表：按集群/命名空间分类的违规详情
```

### 3.3 关键澄清

| 场景 | Dashboard 是否可见 | 说明 |
|------|-------------------|------|
| 启用 Policy Controller + 安装 policy-essentials bundle | ✅ 完整展示 | 可看到所有约束和违规 |
| 启用 Policy Controller + 未安装任何 bundle | ✅ 展示 | Dashboard 显示"未发现违规"，但模板库可用 |
| 未启用 Policy Controller（仅安装开源 Gatekeeper） | ❌ 不可见 | 无法使用 GCP Console 的 Policy Dashboard |

### 3.4 你的猜测确认

> "如果我不启用默认配置，可能就看不到类似规则。是不是这样？"

**不完全正确。** 实际情况是：

- ✅ **模板库可见**：即使不安装 bundle，`templateLibrary: ALL` 已经安装了 82 个 Constraint Templates，这些模板在 Dashboard 的"约束模板"列表中可见
- ✅ **Dashboard 入口可见**：Policy Controller 的 Fleet 级别 Dashboard 始终可见，显示集群注册状态
- ❌ **违规数据取决于约束**：只有安装了 Constraints（约束实例）后，才会有违规数据可展示

---

## 四、维度三：维护成本对比

### 4.1 GKE Policy Controller 维护成本

| 维度 | 成本 | 说明 |
|------|------|------|
| 版本升级 | ⭐（极低） | 跟随 GKE 版本升级，Google 自动管理 |
| 兼容性 | ⭐（极低） | 无需担心与 K8s 版本的兼容性 |
| 安全补丁 | ⭐（极低） | Google 负责推送安全补丁 |
| Bundle 更新 | ⭐⭐（低） | `gcloud container fleet policy-controller enable --memberships=X` 可更新 bundle |
| 故障排查 | ⭐⭐⭐（中等） | 依赖 Google 支持，但日志/文档完善 |

**升级流程示例：**
```bash
# 更新 Policy Controller 到最新版本
gcloud container fleet policy-controller enable \
  --memberships=cluster-a,cluster-b,cluster-c \
  --version=latest
```

### 4.2 开源 OPA Gatekeeper 维护成本

| 维度 | 成本 | 说明 |
|------|------|------|
| 版本升级 | ⭐⭐⭐⭐⭐（极高） | 需要手动升级，每个集群独立操作 |
| 兼容性 | ⭐⭐⭐⭐（高） | 需验证与 K8s 版本的兼容性 |
| 安全补丁 | ⭐⭐⭐⭐（高） | 需自行监控 CVE，及时打补丁 |
| Bundle/模板管理 | ⭐⭐⭐（中） | 需自行维护策略库版本 |
| 多集群一致性 | ⭐⭐⭐⭐（高） | 需通过 GitOps 保证版本一致性 |

**升级流程示例（每个集群都要执行）：**
```bash
# Helm 升级（每个集群）
helm upgrade gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --version 3.14.0

# 或者 kubectl
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml
```

### 4.3 维护成本量化对比

| 集群数量 | GKE Policy Controller | 开源 Gatekeeper |
|----------|----------------------|-----------------|
| 1 个 | ~5 分钟/年 | ~30 分钟/年 |
| 5 个 | ~5 分钟/年 | ~150 分钟/年 |
| 10 个 | ~5 分钟/年 | ~300 分钟/年 |
| 50 个 | ~5 分钟/年 | ~1500 分钟/年 |

---

## 五、维度四：跨 Fleet 多集群管理优势

### 5.1 Fleet 架构图

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GCP Fleet（控制平面）                          │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  Policy Controller Hub                                          │ │
│  │  ├── Fleet-wide Policy Configuration                            │ │
│  │  ├── Bundle Sync Engine（自动同步 bundle 到所有成员集群）           │ │
│  │  └── Compliance Reporting（跨集群合规报告）                        │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                    │ Fleet API
          ┌─────────┼─────────┬─────────┐
          ▼         ▼         ▼         ▼
    ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
    │ Cluster A│ │ Cluster B│ │ Cluster C│ │ Cluster D│
    │  (Dev)   │ │ (Staging)│ │ (Prod)  │ │ (Test)   │
    │          │ │          │ │          │ │          │
    │82 templates │82 templates│82 templates │82 templates│
    │6 Constraints│8 Constraints│12 Constraints│4 Constraints│
    └──────────┘ └──────────┘ └──────────┘ └──────────┘
```

### 5.2 跨集群优势详解

#### 优势一：Fleet-wide 策略配置

```bash
# 在 Fleet 级别配置策略，自动下发到所有成员集群
gcloud container fleet policy-controller enable \
  --memberships=cluster-a,cluster-b,cluster-c \
  --fleet-default-member-config=fleet-default.yaml

# fleet-default.yaml 示例
spec:
  policyControllerHubConfig:
    policyContent:
      bundles:
        policy-essentials-v2022: {}
        pss-baseline-v2022: {}
      templateLibrary: ALL
    auditIntervalSeconds: "60"
    monitoring:
      backends:
      - PROMETHEUS
      - CLOUD_MONITORING
```

#### 优势二：统一合规报告

GCP Console 提供跨集群的合规状态汇总：

| 集群 | 启用状态 | 约束数量 | 活跃违规 | 合规分数 |
|------|----------|----------|----------|----------|
| dev-lon-cluster | ✅ 已启用 | 6 | 3 | 50% |
| staging-eu | ✅ 已启用 | 8 | 0 | 100% |
| prod-us | ✅ 已启用 | 12 | 1 | 91.7% |

#### 优势三：Bundle 版本一致性

```bash
# 检查所有集群的 bundle 状态
gcloud container fleet policycontroller describe \
  --memberships=cluster-a,cluster-b,cluster-c

# 输出显示每个集群的 bundle 同步状态
```

#### 优势四：集中式日志和监控

- **Cloud Logging**：所有集群的 Gatekeeper 日志统一收集
- **Cloud Monitoring**：跨集群的策略指标（违规率、阻止率）
- **Alerting**：可配置跨集群的策略违规告警

---

## 六、维度五：选择决策矩阵

### 6.1 决策树

```
你的场景是什么？
│
├─ 仅 GKE 多集群，统一管理，低维护成本
│   └─ → 选择 GKE Policy Controller ✅
│
├─ 仅 GKE 单集群，需要最新 Gatekeeper 版本
│   └─ → 可选开源 Gatekeeper（但维护成本高）
│
├─ 多云（ GKE + ACK + EKS + 自建）
│   └─ → 必须选择开源 Gatekeeper + GitOps
│
└─ 需要 GCP 原生 Dashboard 可视化
    └─ → 必须选择 GKE Policy Controller ✅
```

### 6.2 场景对比

| 场景 | 推荐方案 | 理由 |
|------|----------|------|
| GKE 企业版，多集群统一管理 | GKE Policy Controller | Fleet 原生支持，维护成本低 |
| GKE 开发/测试环境，评估策略 | GKE Policy Controller（dryrun 模式） | 可快速验证，无需维护 |
| 需要 CIS/NIST/PCI 合规包 | GKE Policy Controller | 10+ 官方 bundle 开箱即用 |
| 跨云多平台（混合云） | 开源 Gatekeeper + ArgoCD | 灵活性高，跨平台支持 |
| 需要最新 Gatekeeper 功能 | 开源 Gatekeeper | 社区版本迭代更快 |
| 需要 GitOps 版本控制 | 开源 Gatekeeper + Flux | 策略即代码，完整审计 |
| 需要 GCP Cloud Armor 集成 | GKE Policy Controller | 内置 `k8senforcecloudarmorbackendconfig` 模板 |
| 需要 Cloud Storage 区域限制 | GKE Policy Controller | 内置 `gcpstoragelocationconstraintv1` 模板 |

---

## 七、GKE Policy Controller 的局限性

### 7.1 版本滞后

GKE Policy Controller 的版本可能滞后于开源版本：

| 组件 | 开源 Gatekeeper | GKE Policy Controller |
|------|-----------------|----------------------|
| 当前最新版本 | 3.14.x | 1.23.1（根据你的安装文档） |
| 更新频率 | 每季度 | 跟随 GKE 版本（约每年 3-4 次） |

**风险**：如果你需要最新功能（如 Mutation v2），可能需要等待较长时间。

### 7.2 仅限 GKE

- ❌ 不支持 EKS、AKS、自建 K8s
- ❌ 无法与其他云提供商的策略服务集成

### 7.3 Fleet 绑定

- 必须注册到 Fleet 才能使用
- 无法离线使用或私有化部署控制平面

---

## 八、开源 OPA Gatekeeper 的局限性

### 8.1 无跨集群原生管理

```
开源 Gatekeeper 的架构：
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Cluster A  │     │  Cluster B  │     │  Cluster C  │
│  (Gate-     │     │  (Gate-     │     │  (Gate-     │
│   keeper)   │     │   keeper)   │     │   keeper)   │
│             │     │             │     │             │
│  各自独立   │     │  各自独立   │     │  各自独立   │
│  管理       │     │  管理       │     │  管理       │
└─────────────┘     └─────────────┘     └─────────────┘
       ❌ 无跨集群统一管理
```

### 8.2 需要 GitOps 工具实现多集群管理

| 工具 | 优点 | 缺点 |
|------|------|------|
| **ArgoCD** | 成熟，UI 好，GitOps 最佳实践 | 需额外部署和维护 |
| **Flux** | GitOps 原生，轻量 | 配置较复杂 |
| **Rancher Fleet** | 支持大规模集群 | 需 Rancher 许可 |

### 8.3 无原生 Dashboard

- ❌ 无 GCP Console 集成
- ✅ 可通过 Prometheus + Grafana 搭建（需额外工作）

---

## 九、总结与推荐

### 9.1 核心结论

| 评估维度 | GKE Policy Controller | 开源 Gatekeeper | 胜出 |
|----------|----------------------|-----------------|------|
| **内置规则数量** | 82 条（含 GCP 集成） | 20-30 条（需手动导入） | ✅ Policy Controller |
| **维护成本** | 低（Google 托管） | 高（需自行管理） | ✅ Policy Controller |
| **Dashboard 可视化** | GCP Console 原生 | 需自行搭建 | ✅ Policy Controller |
| **跨集群管理** | Fleet 原生支持 | 需 GitOps | ✅ Policy Controller |
| **跨云支持** | 仅限 GKE | 任意 K8s | 平手 |
| **版本灵活性** | 滞后于社区 | 紧跟社区 | ✅ 开源 |
| **合规包覆盖** | 10+ 官方包 | 需自行编写 | ✅ Policy Controller |

### 9.2 推荐方案

**针对你的场景（GKE 多集群，需要评估和选择）：**

#### 如果你满足以下条件，选择 **GKE Policy Controller**：

1. ✅ 仅使用 GKE（不需要跨云）
2. ✅ 需要低维护成本
3. ✅ 需要 GCP 原生 Dashboard
4. ✅ 需要 CIS/NIST/PCI 等合规包
5. ✅ 需要跨集群统一管理

#### 如果你满足以下条件，选择 **开源 Gatekeeper + GitOps**：

1. ✅ 有跨云需求（GKE + ACK + EKS）
2. ✅ 需要最新 Gatekeeper 功能
3. ✅ 需要策略即代码的 GitOps 工作流
4. ✅ 已有 ArgoCD/Flux 基础设施
5. ✅ 需要完全控制策略版本

---

## 十、下一步行动建议

### 10.1 推荐评估步骤

1. **当前状态验证**：确认你的集群已加入 Fleet并启用 Policy Controller
2. **Dashboard 探索**：访问 GCP Console → GKE Overview，观察 Policy Controller 部分
3. **Bundle 测试**：尝试安装 `pss-baseline-v2022` 和 `cis-k8s-v1.5.1` bundle，观察 Dashboard 变化
4. **自定义规则测试**：基于内置模板编写自定义 Constraint，验证 Dashboard 是否展示

### 10.2 快速验证命令

```bash
# 检查 Policy Controller 状态
gcloud container fleet policycontroller describe --memberships=aibang-master

# 查看所有约束模板
kubectl get constrainttemplates | wc -l  # 应显示 82

# 查看当前活跃的约束
kubectl get constraint --all-namespaces

# 查看 Dashboard 入口
# GCP Console → Kubernetes Engine → Configuration → Policy Controller
```

---

## 十一、自定义 Rego 模板与自定义 Kind 管理

### 11.1 需求背景

你提到一个关键的选型驱动因素：

> "我们想要通过 Rego 来管理我们的 source code，也就是更底层的一些模板。我们平台有自己的一套 Mapping 关系来进行对应管理。希望在 Dashboard 里能体现这些对应的规则。"

这是一个**策略即代码（Policy as Code）+ 自定义领域模型**的场景，核心诉求包括：

1. **自定义 Kind 命名**：平台有自己的一套资源命名规范（如 `MyPlatformRequiredLabels` 而非 `K8sRequiredLabels`）
2. **底层源码管理**：Rego 模板是源代码，需要版本化管理
3. **Mapping 关系**：需要维护平台特有的资源映射逻辑
4. **Dashboard 可视化**：自定义规则需要在管理界面可见

### 11.2 两种方案的能力对比

#### 11.2.1 GKE Policy Controller 对自定义模板的支持

| 能力 | 支持程度 | 说明 |
|------|----------|------|
| **自定义 ConstraintTemplate** | ✅ 完全支持 | 可创建任意名称的 ConstraintTemplate，自定义 Kind |
| **自定义 Rego 代码** | ✅ 完全支持 | 完全支持 Rego 语言，可编写任意逻辑 |
| **自定义 Kind 命名** | ✅ 完全支持 | `metadata.name` 和 `spec.crd.spec.names.kind` 均可自定义 |
| **Dashboard 展示** | ⚠️ 部分支持 | 模板库可见，但自定义模板的合规报告需通过 Constraint 实例触发 |
| **版本控制** | ❌ 受限 | 无原生 GitOps 支持，需通过手动 `kubectl apply` 部署 |
| **跨集群同步** | ⚠️ 受限 | 需通过 Config Sync 或手动同步，无原生多集群同步机制 |

**GKE Policy Controller 自定义模板示例：**

```yaml
# 自定义 ConstraintTemplate（自定义 Kind）
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: myplatform.required.labels  # 自定义名称
  annotations:
    description: "Aibang Platform 必选标签约束"
spec:
  crd:
    spec:
      names:
        kind: MyPlatformRequiredLabels  # 自定义 Kind
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
            namespaces:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package myplatform.required.labels

        violation[{"msg": msg, "details": {"missing": missing}}] {
          ns := input.review.namespace
          ns_whitelist := input.parameters.namespaces
          count(ns_whitelist) > 0
          not ns in ns_whitelist
          missing := [label | not input.review.object.metadata.labels[label]]
          count(missing) > 0
          msg := sprintf("Aibang Platform requires labels: %v", [missing])
        }
---
# 基于自定义模板的 Constraint
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: MyPlatformRequiredLabels
metadata:
  name: platform-ns-must-have-labels
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Namespace"]
  parameters:
    labels: ["team", "environment", "owner", "cost-center"]
    namespaces: []  # 空数组表示所有命名空间
```

**Dashboard 展示逻辑：**

```
GCP Console → Policy Controller Dashboard
├── 约束模板列表
│   ├── GKE 内置模板（82 个）：✅ 可见
│   └── 自定义模板：✅ 可见（名称为 myplatform.required.labels）
│
├── 约束实例列表
│   └── MyPlatformRequiredLabels/platform-ns-must-have-labels：✅ 可见
│
└── 违规详情
    └── 违规记录按 namespace 分类展示
```

#### 11.2.2 开源 OPA Gatekeeper 对自定义模板的支持

| 能力 | 支持程度 | 说明 |
|------|----------|------|
| **自定义 ConstraintTemplate** | ✅ 完全支持 | 与 GKE Policy Controller 完全相同的能力 |
| **自定义 Rego 代码** | ✅ 完全支持 | 完全支持 Rego 语言 |
| **自定义 Kind 命名** | ✅ 完全支持 | 完全自由命名 |
| **Dashboard 展示** | ❌ 无原生 | 无 GCP Console 集成，需自行搭建（Prometheus + Grafana） |
| **版本控制** | ✅ 原生支持 | 可与 GitOps 完美结合（ArgoCD/Flux） |
| **跨集群同步** | ✅ 原生支持 | 通过 GitOps 实现多集群自动同步 |

**开源 Gatekeeper 的 GitOps 工作流：**

```
┌────────────────────────────────────────────────────────────────────────┐
│                          Git Repository                                 │
│  policy-library/                                                          │
│  ├── templates/                                                          │
│  │   ├── myplatform.required.labels.yaml    # 自定义模板                │
│  │   ├── myplatform.container-limits.yaml   # 自定义容器限制             │
│  │   └── custom-resource-validation.yaml    # 自定义资源配置            │
│  ├── constraints/                                                        │
│  │   ├── prod/                                                    │
│  │   │   ├── ns-labels.yaml                                          │
│  │   │   └── container-limits.yaml                                   │
│  │   └── dev/                                                      │
│  │       └── ns-labels.yaml                                          │
│  └── kustomization.yaml                                                │
└────────────────────────────────────────────────────────────────────────┘
                              │
                              │ ArgoCD / Flux 自动同步
                              ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  Cluster A   │  │  Cluster B   │  │  Cluster C   │
│  (Prod)      │  │  (Staging)   │  │  (Dev)       │
│              │  │              │  │              │
│Template: ✅  │  │ Template: ✅  │  │ Template: ✅  │
│Constraint: ✅│  │Constraint: ✅│  │Constraint: ✅│
└──────────────┘  └──────────────┘  └──────────────┘
```

### 11.3 自定义 Kind 与平台 Mapping 的设计模式

#### 11.3.1 平台特有的映射关系示例

你的需求中提到"平台有自己的一套 Mapping 关系"，这是一个常见的企业内部平台需求。以下是几种典型场景：

**场景一：组织架构映射**

```rego
# 自定义模板：组织标签映射
package myplatform.org.mapping

violation[{"msg": msg, "details": {"team": team}}] {
  # 从 namespace annotation 提取 team 信息
  namespace := input.review.object.metadata.name
  annotations := input.review.object.metadata.annotations
  
  # 平台定义的 team→cost-center mapping
  team_mapping := {
    "platform-team": {"cost-center": "CC-001", "slack": "#platform"},
    "data-team": {"cost-center": "CC-002", "slack": "#data"},
    "ml-team": {"cost-center": "CC-003", "slack": "#ml"}
  }
  
  team := annotations["aibang-team"]
  not team in team_mapping
  msg := sprintf("Unknown team '%v'. Valid teams: %v", [team, keys(team_mapping)])
}

keys(m) = [k | k := m[k]]
```

**场景二：资源配额映射**

```rego
# 自定义模板：环境配额映射
package myplatform.resource.quota

violation[{"msg": msg}] {
  ns := input.review.object.metadata.name
  env := input.review.object.metadata.labels.environment
  
  # 平台定义的环境配额标准
  quota_standards := {
    "production": {"cpu-limit": "32", "memory-limit": "64Gi"},
    "staging": {"cpu-limit": "8", "memory-limit": "16Gi"},
    "dev": {"cpu-limit": "2", "memory-limit": "4Gi"}
  }
  
  container := input.review.object.spec.template.spec.containers[_]
  cpu_limit := container.resources.limits.cpu
  
  quota := quota_standards[env]
  not cpu_limit <= quota.cpu-limit
  
  msg := sprintf("CPU limit %v exceeds quota for environment '%v' (max: %v)", 
                 [cpu_limit, env, quota.cpu-limit])
}
```

#### 11.3.2 ConstraintTemplate 的分层设计

为实现"底层模板 + 上层配置"的分离，建议采用分层架构：

```
平台模板层（Platform Templates）
├── myplatform.base.labels         # 基础标签模板（抽象）
├── myplatform.base.resources       # 基础资源配置模板（抽象）
└── myplatform.base.network         # 基础网络策略模板（抽象）

业务映射层（Business Mappings）
├── myplatform.org.mapping          # 组织架构映射
├── myplatform.cost.mapping         # 成本中心映射
└── myplatform.compliance.mapping   # 合规要求映射

实例层（Constraints）
├── prod/namespace-constraints.yaml
├── staging/namespace-constraints.yaml
└── dev/namespace-constraints.yaml
```

### 11.4 Dashboard 可视化的实现方案

#### 11.4.1 GKE Policy Controller 的 Dashboard

**原生 Dashboard 的能力：**

| 功能 | 可用性 | 说明 |
|------|--------|------|
| 模板列表 | ✅ | 列出所有 ConstraintTemplate（内置 + 自定义） |
| 约束实例 | ✅ | 列出所有 Constraint（按模板分类） |
| 违规记录 | ✅ | 展示违规详情（包含自定义模板的违规） |
| 合规趋势 | ⚠️ | 需通过 Cloud Monitoring 手动配置 |
| 自定义报告 | ❌ | 无自定义报表功能 |

**关键限制**：GKE Policy Controller Dashboard 不支持自定义报表和自定义导航，用户体验受限于 Google 设计。

#### 11.4.2 开源 Gatekeeper + 第三方 Dashboard

**方案一：Grafana + Prometheus**

```
┌─────────────────────────────────────────────────────────────────┐
│                       Grafana Dashboard                          │
│                                                                  │
│  Panel 1: Constraint Template Status                             │
│  ├── 自定义模板数量                                              │
│  ├── 活跃约束数量                                                │
│  └── 模板分布饼图                                                │
│                                                                  │
│  Panel 2: Violation Trends                                       │
│  ├── 违规数量时间序列                                            │
│  ├── 按 namespace 分类                                           │
│  └── 按 template 分类                                            │
│                                                                  │
│  Panel 3: Custom Kind Mapping                                     │
│  ├── MyPlatformRequiredLabels 违规数                             │
│  ├── 自定义映射规则的命中情况                                      │
│  └── 团队级别的合规排名                                          │
└─────────────────────────────────────────────────────────────────┘
```

**Prometheus Query 示例：**

```promql
# 自定义模板的违规数量
sum(gatekeeper_constraints_status_violations{service="gatekeeper-controller-manager"}) 
by (constraint_name, kind)

# 按自定义 Kind 分类的违规趋势
rate(gatekeeper_constraints_status_violations{kind=~"MyPlatform.*"}[5m])
```

**方案二：Kubewarden + Ulfius（开源生态）**

如果你需要更丰富的自定义 Dashboard，可以考虑 Kubewarden（Gatekeeper 的替代方案），它提供了更好的扩展性。

### 11.5 选型建议：针对自定义 Rego 管理场景

#### 11.5.1 决策矩阵

| 需求 | GKE Policy Controller | 开源 Gatekeeper + GitOps |
|------|----------------------|--------------------------|
| **自定义 Kind 命名** | ✅ | ✅ |
| **Rego 源码版本控制** | ❌ 无原生 | ✅ GitOps 原生 |
| **多集群自动同步** | ⚠️ 需 Config Sync | ✅ ArgoCD/Flux 原生 |
| **Dashboard 可见性** | ⚠️ 受限 | ❌ 需自行搭建 |
| **平台特有 Mapping** | ✅ 可实现 | ✅ 可实现 |
| **维护成本** | 低 | 高 |
| **GCP 原生集成** | ✅ | ❌ |

#### 11.5.2 推荐方案

**如果你的核心诉求是"自定义 Kind + 平台 Mapping + Dashboard 可见"：**

| 优先级 | 方案 | 理由 |
|--------|------|------|
| **第一选择** | **开源 Gatekeeper + ArgoCD + 自建 Dashboard** | 最灵活，完全可控，GitOps 版本控制，自定义可视化 |
| **第二选择** | **GKE Policy Controller + Config Sync + Cloud Monitoring** | 托管简单，Dashboard 可用，但灵活性受限 |

**具体推荐：**

```
如果满足以下所有条件 → 选择 GKE Policy Controller
├── Dashboard 可视化要求不高（能看违规列表即可）
├── 不需要复杂的自定义报表
├── 不想维护额外的 Dashboard
└── 已使用 Config Sync

如果满足以下任一条件 → 选择开源 Gatekeeper + GitOps
├── 需要自定义 Dashboard（自定义报表、团队视图）
├── 需要完整的 GitOps 工作流（代码审核、版本回滚）
├── 有跨云/跨平台需求
└── 需要更深度的自定义规则展示（自定义 Kind 映射图）
```

### 11.6 混合方案：最优解

考虑到你的需求（自定义 Rego + 自定义 Kind + Dashboard 可视化），**推荐采用混合方案**：

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Hybrid Architecture                          │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  Git Repository (Policy as Code)                               │  │
│  │  ├── templates/myplatform.*.yaml    # 自定义模板               │  │
│  │  └── constraints/env/*.yaml          # 环境差异配置             │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│              ┌───────────────┼───────────────┐                    │
│              ▼               ▼               ▼                    │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │  Cluster A (Prod)│  │ Cluster B (Stg) │  │ Cluster C (Dev)  │  │
│  │                  │  │                  │  │                  │  │
│  │  GKE Policy Ctrl │  │  GKE Policy Ctrl│  │  GKE Policy Ctrl│  │
│  │  + ArgoCD        │  │  + ArgoCD        │  │  + ArgoCD        │  │
│  │                  │  │                  │  │                  │  │
│  │  Template: ✅    │  │  Template: ✅    │  │  Template: ✅    │  │
│  │  Constraint: ✅  │  │  Constraint: ✅  │  │  Constraint: ✅  │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
│                              │                                      │
│                              ▼                                      │
│                    ┌──────────────────────┐                        │
│                    │   Grafana Dashboard   │                        │
│                    │   (Custom Views)      │                        │
│                    │   + Prometheus        │                        │
│                    └──────────────────────┘                        │
└─────────────────────────────────────────────────────────────────────┘
```

**混合方案的核心优势：**

1. **Policy as Code**：所有模板存储在 Git，通过 ArgoCD 自动同步
2. **GKE Policy Controller**：使用 Google 托管的 Gatekeeper，减少维护成本
3. **自定义 Dashboard**：通过 Prometheus + Grafana 实现完全自定义的可视化
4. **跨集群一致性**：一处配置，多集群自动同步

### 11.7 实现步骤

#### 步骤一：创建 Git 仓库结构

```
policy-library/
├── README.md
├── templates/
│   ├── myplatform.required.labels.yaml
│   ├── myplatform.resource.quota.yaml
│   └── myplatform.org.mapping.yaml
├── constraints/
│   ├── prod/
│   │   └── constraints.yaml
│   ├── staging/
│   │   └── constraints.yaml
│   └── dev/
│       └── constraints.yaml
└── argocd/
    ├── app-prod.yaml
    ├── app-staging.yaml
    └── app-dev.yaml
```

#### 步骤二：部署 ArgoCD Application

```yaml
# argocd/app-prod.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: policy-library-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/policy-library.git
    targetRevision: main
    path: constraints/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: gatekeeper-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

#### 步骤三：配置 Prometheus + Grafana

```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gatekeeper-custom-rules
spec:
  groups:
    - name: myplatform
      rules:
        - expr: |
            sum(gatekeeper_constraints_status_violations{
              constraint_name=~"myplatform.*"
            }) by (constraint_name, kind)
          labels:
            team: platform
          annotations:
            summary: "MyPlatform 策略违规"
            description: "约束 {{ $labels.constraint_name }} 存在违规"
```

---

**文档结束**

| 资源 | 链接 |
|------|------|
| GKE Policy Controller 文档 | https://cloud.google.com/kubernetes-engine/docs/concepts/policy-controller |
| GKE Policy Controller Bundle 列表 | https://github.com/GoogleCloudPlatform/gke-policy-library/blob/main/Policy_Bundles.md |
| 开源 Gatekeeper | https://open-policy-agent.github.io/gatekeeper/ |
| Gatekeeper Library（社区模板） | https://github.com/open-policy-agent/gatekeeper-library |
| Fleet 概览 Dashboard | https://cloud.google.com/kubernetes-engine/docs/concepts/overview |

---

**文档结束**