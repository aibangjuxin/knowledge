# 问题分析

落地 GKE 这条线，本质是把"创建一个符合生产标准的 GKE 集群"这个动作，沉淀成一套**可复用的自助式交付流水线**，而不是每次手动 `gcloud container clusters create`。

结合你已有的技术栈，这条线要解决四个层面的问题：

1. **集群本身怎么标准化创建**（Standard 私有集群、VPC-native；节点层配置由 DC/CaaS 负责）
2. **网络基线怎么自动注入**（Gateway API、mTLS、Ingress 接入你现有的 Gloo/Istio Ambient 体系）
3. **多租户模型怎么定义**（Namespace 隔离 vs 独立集群，这直接关系到你正在处理的 **Gateway API URL Map 配额瓶颈** —— 如果 CaaS 从一开始就按 Gateway-per-namespace 分片设计，可以规避未来大规模迁移再踩同一个坑）
4. **怎么用 GitOps 交付而不是脚本裸跑**（Config Sync / Fleet 统一策略下发）

---

# 解决方案

## 分层架构

```mermaid
graph TD
    A[自助请求 ClusterSpec YAML/API] --> B[Day-0 校验层]
    B --> B1[命名规范检查]
    B --> B2[配额预检查 Gateway URL Map size]
    B --> B3[网络模式校验 VPC-native/Private]
    B --> C[Terraform Module 层]
    C --> C1[GKE Standard 集群创建]
    C --> C2[Workload Identity 绑定]
    C --> C3[私有集群 + 授权网络]
    C --> D[GitOps 策略注入层 Config Sync/Fleet]
    D --> D1[Gateway API GatewayClass 预置]
    D --> D2[网关分片策略 Gateway-per-namespace]
    D --> D3[mTLS Server TLS Policy 注入]
    D --> D4[RBAC/多租户基线]
    D --> E[可观测性接入]
    E --> E1[Cloud Logging/Monitoring]
    E --> E2[成本标签 FinOps]
    E --> F[交付完成 集群可用]
```

## 关键设计决策

| 决策点                | 选择                                                                             | 理由                                                                   |
| --------------------- | -------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Autopilot vs Standard | **锁死 `standard`**（C3 修复，2026-10-05）                                   | DC 立场确认全量 Standard；且 RFC §5 要求"默认值来自画像，不是 schema"。Autopilot 能力降级为**未来画像候选**，不进 schema |
| **Release channel** 🆕 | **`STABLE`（enum 锁死，无逃逸）**                                                 | 生产环境；官方明示 RAPID 排除在 GKE SLA 外，且 Extended 与 DC 基线冲突。C9 修复 |
| **集群粒度**          | 团队级共享集群 + Namespace 隔离为主，独占集群作为强隔离逃逸舱口                   | 结合你正处理的 ~1000 API 迁移，独立集群成本过高                        |
| 网关配额治理          | **CaaS 交付集群时强制预置 Gateway-per-namespace 分片模板**，不等到超限再补       | 直接对应你已知的 URL Map size limit 阻塞项，从设计上前置规避           |
| 策略下发方式          | GKE Fleet + Config Sync（GitOps），不用裸 kubectl apply                          | 保证多集群策略一致性、可审计                                           |
| 网络接入              | 集群创建时即挂载到统一 GatewayClass / Gloo Gateway 数据面                        | 避免"集群交付了但网络没打通"的割裂                                     |

---

# 代码示例

## 1. ClusterSpec 抽象（自助请求的输入 Schema）

```yaml
# clusterspec-example.yaml
apiVersion: caas.internal/v1
kind: ClusterRequest
metadata:
  name: bbuk-team-a-prod
spec:
  cloudProvider: gcp
  region: asia-east1
  tier: standard # ⚠️ C3 修复:enum 锁死 ["standard"],Autopilot 不再是选项
  environment: prod # prod | staging | dev
  # ⚠️ C9(2026-10-05):生产环境固定 Stable,业务方无需理解 release channel 概念。
  # 保留该字段是为了让"版本策略"在 CRD 层可见可审计,而不是散落在 Terraform 里。
  versionStrategy:
    channel: STABLE # enum 锁死,无逃逸选项
    minorUpgradePolicy: auto
    eolNoticeDays: 60
    cdb:
      patchIntervalDays: 1
      minorIntervalDays: 30 # 不要配到 90
  network:
    mode: private # private | public
    vpc: shared-vpc-prod
    subnet: bbuk-prod-subnet
  gatewayStrategy:
    mode: per-namespace # per-namespace | shared | per-cluster
    initialShards: 3 # 提前规划分片数，避免单 Gateway URL Map 超限
  multiTenancy:
    isolationLevel: namespace
    teams:
      - team-a
      - team-b
  observability:
    monitoringEnabled: true
    costLabel: "bbuk-team-a"
```

## 2. Terraform Module 骨架（Standard Golden Path）

> ⚠️ **C3 修复(2026-10-05)**:本节原标题为 "Autopilot Golden Path",骨架里写着
> `enable_autopilot = true`。现 DC 全量 Standard,该骨架与 `spec.tier` 锁死值矛盾,
> 已改为 Standard 形态。**Autopilot 模块不再作为 golden path** ——
> 若将来某个画像需要它,应作为**独立 module** 新增,而不是把 golden path 改回去。

```hcl
# modules/gke-standard/main.tf
resource "google_container_cluster" "this" {
  name             = var.cluster_name
  location         = var.region
  # ⚠️ C3 修复(2026-10-05):原为 enable_autopilot = true。
  # Standard 模式下不设该字段(或置 false)即为标准集群。
  enable_autopilot = false

  network    = var.vpc_self_link
  subnetwork = var.subnet_self_link

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }

  # ⚠️ C3 + Standard 的后果:节点层归 DC/CaaS 负责(Autopilot 时代不需要这些)。
  # 这是"锁死 standard"真正的成本所在 —— 不是 CRD 少一个 enum 值,
  # 而是 CaaS 必须补齐节点生命周期编排。详见文末「Standard 模式的责任转移」章节。
  # remove_default_node_pool = true
  # initial_node_count = 0   # 节点池由独立的 node_pool resource 管理

  # ⚠️ C9 修复(2026-10-05):原为 channel = "REGULAR",与 DC 立场冲突。
  # DC 全量生产集群 → Stable。理由见文末「版本与升级策略」章节。
  # 注意:这不是"默认值",是 CaaS 强制值 —— RAPID 排除在 GKE SLA 之外,
  # 业务方不得自行选择。逃逸舱口见 ClusterRequest.spec.versionStrategy.
  release_channel {
    channel = "STABLE"
  }

  # ⚠️ 生产集群必须配置维护窗口(时区/频次由 CaaS 按 DC 画像统一注入)。
  # 缺这一项 = 升级在任意时刻发生,变更不在流程内。
  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_window_start  # 例 "03:00"
      duration   = var.maintenance_window_duration # 例 "4h0m0s"
    }
  }

  # ⚠️ 标准支持期内禁止 minor 升级(EOL 前由 CaaS 主动通告并编排,不靠 exclusion 拖时间)。
  # 官方:GKE 会在 end of support 时无视 exclusion 强制升级。
  # 该字段仅作为 CaaS 编排的产物写入,不由业务方填写。
  # maintenance_exclusions {
  #   exclusion {
  #     # 仅在 CaaS 编排的升级窗口内使用
  #   }
  # }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  resource_labels = {
    cost-center = var.cost_label
    managed-by  = "caas"
  }
}
```

## 3. 配额预检查脚本（jq 风格，接你现有工具习惯）

```bash
#!/usr/bin/env bash
# precheck-gateway-quota.sh
# 交付前检查目标命名空间下 HTTPRoute 数量，预估 URL Map 是否会逼近限额

NAMESPACE=$1
LIMIT_WARN=800   # 提前预警阈值，避开已知的 URL Map size limit 硬上限

ROUTE_COUNT=$(kubectl get httproute -n "$NAMESPACE" -o json \
  | jq '[.items[].spec.rules[]] | length')

echo "命名空间 [$NAMESPACE] 当前 HTTPRoute 规则数: $ROUTE_COUNT"

if [ "$ROUTE_COUNT" -gt "$LIMIT_WARN" ]; then
  echo "⚠️ 接近 URL Map 配额上限，建议触发 Gateway 分片（新增 shard）"
  exit 1
fi
```

---

# 注意事项

1. **配额问题要设计前置，不是事后补救**：你已经在处理的 ~1000 API 迁移遇到的 Gateway API URL Map size limit，说明"网关分片策略"必须是 CaaS 交付集群时的**默认能力**，而不是后期补丁——建议在 ClusterSpec 里把 `gatewayStrategy.initialShards` 设为必填项。
2. **Preview 配额扩容是临时解**：GCP 的配置大小限制 Preview 程序能缓解但不是长期方案，CaaS 的分片能力才是根本解法，两者可以并行推进。
3. **⚠️ Standard 锁死后,节点层编排从"可选"变"必需"(C3 修复 2026-10-05)**：本条原为"Autopilot 逃逸舱口要预留"，现已翻转 —— **Autopilot 不再是选项，Standard 是唯一模式**。真实后果是：节点升级策略、Cluster Autoscaler 边界、节点池数量收敛、NAP 都要由 DC/CaaS 负责。见文末「Standard 模式的责任转移」章节。
4. **执行 Terraform apply 前务必 `terraform plan` 并检查 IAM 权限**，尤其是 Shared VPC 场景下的跨项目网络管理员权限。
5. **部署 GatewayClass/Fleet 策略前用 `kubectl apply --dry-run=server` 校验 YAML**，避免 Config Sync 同步失败导致集群交付中断。

需要我把 ClusterSpec 进一步细化成完整 CRD（带 OpenAPI Schema 校验），还是先把 Gateway-per-namespace 分片策略的具体 HTTPRoute/Gateway 拆分方案画出来？

# 问题分析

要让 `ClusterRequest` 从"一份人读的 YAML 约定"升级成"K8S 原生可校验的资源"，需要用 **CustomResourceDefinition + OpenAPI v3 Schema**（K8S 1.25+ 还可以加 CEL 表达式做跨字段校验），这样无效请求在 `kubectl apply` 阶段就会被 API Server 拒绝，而不用等到 Terraform/Controller 执行到一半才报错——这对你的 Gateway 分片策略这种"必须提前规划、不能事后补"的字段尤其重要。

---

# 解决方案

## 设计要点

1. **枚举约束**：`cloudProvider`、`tier`、`gatewayStrategy.mode` 等用 `enum` 锁死取值范围
2. **跨字段校验**：用 `x-kubernetes-validations`（CEL）确保 "`gatewayStrategy.mode: per-namespace` 时 `initialShards` 必须 ≥1"，"`isolationLevel: namespace` 时 `teams` 不能为空"
3. **Status 子资源**：区分 spec（用户期望态）和 status（Controller 实际交付态），Controller 只能改 status，权限隔离更清晰
4. **打印列**：`kubectl get clusterrequest` 直接看到 phase、shard 数、region，不用每次 `-o yaml`

## 校验流程

```mermaid
graph TD
    A[kubectl apply ClusterRequest] --> B{API Server OpenAPI Schema 校验}
    B -->|字段类型/枚举/必填 不通过| C[拒绝 报错返回]
    B -->|通过| D{CEL 跨字段规则校验}
    D -->|per-namespace 但 initialShards 缺失| C
    D -->|通过| E[写入 etcd status.phase=Pending]
    E --> F[Controller Reconcile Loop]
    F --> F1[Day-0 配额预检查]
    F1 -->|超限风险| G[status.phase=QuotaBlocked]
    F1 -->|通过| H[Terraform Apply 集群创建]
    H --> I[GitOps 策略注入 Gateway分片/mTLS]
    I --> J[status.phase=Ready]
```

---

# 代码示例

## 1. 完整 CRD 定义（含 OpenAPI Schema + CEL 校验）

```yaml
# crd-clusterrequest.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: clusterrequests.caas.internal
spec:
  group: caas.internal
  scope: Namespaced
  names:
    plural: clusterrequests
    singular: clusterrequest
    kind: ClusterRequest
    shortNames: ["cr", "clreq"]
    categories: ["caas"]
  versions:
    - name: v1
      served: true
      storage: true
      subresources:
        status: {}
      additionalPrinterColumns:
        - name: Provider
          type: string
          jsonPath: .spec.cloudProvider
        - name: Tier
          type: string
          jsonPath: .spec.tier
        - name: GatewayShards
          type: integer
          jsonPath: .spec.gatewayStrategy.initialShards
        - name: Phase
          type: string
          jsonPath: .status.phase
        - name: Age
          type: date
          jsonPath: .metadata.creationTimestamp
      schema:
        openAPIV3Schema:
          type: object
          required: ["spec"]
          properties:
            spec:
              type: object
              required:
                [
                  "cloudProvider",
                  "region",
                  "tier",
                  "environment",
                  "versionStrategy",
                  "network",
                  "gatewayStrategy",
                  "multiTenancy",
                ]
              properties:
                cloudProvider:
                  type: string
                  enum: ["gcp", "aws", "aliyun", "onprem"]
                  description: "目标云厂商，决定使用哪个 Terraform Provider Adapter"
                region:
                  type: string
                  minLength: 1
                  pattern: "^[a-z0-9-]+$"
                tier:
                  type: string
                  # ⚠️ C3 修复(2026-10-05):删掉 default: "autopilot" → enum 单值锁死 standard。
                  #
                  # 三条独立理由,任何一条都足以否定原来的 default:
                  #  1) DC 立场(2026-09-29 确认):全部 Standard。default 会让第一份
                  #     纳管请求就走错分支,而且错得没有任何提示。
                  #  2) RFC §5 "Declare intent; resolve provider details from approved
                  #     profiles" —— default 的本质是"消费方没选时系统替他选",
                  #     恰是 §5 禁止的行为。默认值应来自画像,不是来自 schema。
                  #  3) 锁死 = 删掉一个没人用的选项。DC 不用 Autopilot,
                  #     而"默认走 Autopilot"会静默继承它的限制
                  #     (禁 privileged / hostPath 写 / hostNetwork)。
                  #
                  # ⚠️ 为什么不 enum: ["autopilot","standard"] 保留选项?
                  #   因为 14 号文件 C3 建议"若 DC 只支持 Standard,enum 锁死即可"。
                  #   其它团队若将来要用 Autopilot,是新增一个**画像**,
                  #   不是把一个未论证的默认值放回 schema。
                  #   画像扩容 = 加版本化 profile;CaaS 不为没签过的立场预留后门。
                  enum: ["standard"]
                # ⚠️ C9 配套(2026-10-05):environment 是版本策略规则的判据,
                # 也是 BYOC 分类自查(21 号文件)要求的第一项事实。
                # 此前 CRD 无此字段 → 无法区分生产与非生产,
                # 导致"生产不得开 EOL 紧急 exclusion"这类规则无从校验。
                environment:
                  type: string
                  enum: ["prod", "staging", "dev"]
                  description: "环境标识;prod 触发更严格的版本与 EOL 规则"
                # ⚠️ C9 修复(2026-10-05):release channel 从隐式 Terraform 默认值
                # 提升为 CRD 强字段。理由:版本策略是 WP-3 的 P0 交付物,
                # 且 9 份底稿此前无一处定义它 —— 定义缺失会直接变成实现偏差。
                # DC 立场(2026-10-05 确认):全量生产集群 → Stable。
                versionStrategy:
                  type: object
                  required: ["channel"]
                  properties:
                    channel:
                      type: string
                      # ⚠️ 不含 RAPID:官方明示 Rapid 排除在 GKE SLA 之外。
                      # 不含 EXTENDED:其官方禁用清单含 Config Sync 与 Policy Controller,
                      #   而 DC 的 CaaS 基线依赖这两者(见 20-wp3-version-policy.md §2.4)。
                      # 不含 UNSPECIFIED / NO_CHANNEL:官方标注 deprecated,将被移除。
                      enum: ["STABLE"]
                      default: "STABLE"
                    # 逃逸舱口:仅允许向"更保守"方向偏移,不允许向"更激进"方向。
                    # 业务方可以要求更长的 minor soak / 更大的 CDB,但不能要求更快的通道。
                    minorUpgradePolicy:
                      type: string
                      enum: ["auto", "manual-soak"]
                      default: "auto"
                      description: "auto=GKE 自主编排(24h soak);manual-soak=CaaS 编排 6h–7d soak"
                    # CDB(cluster disruption budget)。⚠️ 建议保留默认值:
                    # 配到 90 天上限会提高 EOL 时刻被强制升级的概率。
                    cdb:
                      type: object
                      properties:
                        patchIntervalDays:
                          type: integer
                          minimum: 0
                          maximum: 90
                          default: 1 # 官方默认 24h
                        minorIntervalDays:
                          type: integer
                          minimum: 0
                          maximum: 90
                          default: 30 # 官方默认 30 天;不要配到 90
                    # EOL 提前通告义务:业务方承诺的响应窗口。
                    # CaaS 在 EOL 前 N 天主动通告;N 由 DC 统一配置,业务方只确认"知悉"。
                    eolNoticeDays:
                      type: integer
                      minimum: 30
                      maximum: 180
                      default: 60
                      description: "EOL 提前通告天数;不得小于 30,保证业务方有准备时间"
                    # 显式承认"急事可以不等":官方允许 EOL 后用 No upgrades scope
                    # 延迟至多 90 天,但明确不推荐。默认 false = 需走 break-glass。
                    allowEolEmergencyExclusion:
                      type: boolean
                      default: false
                      description: "官方不推荐;置 true 需在 break-glass 记录中留痕"
                network:
                  type: object
                  required: ["mode", "vpc", "subnet"]
                  properties:
                    mode:
                      type: string
                      enum: ["private", "public"]
                      default: "private"
                    vpc:
                      type: string
                      minLength: 1
                    subnet:
                      type: string
                      minLength: 1
                    masterCidr:
                      type: string
                      pattern: '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'
                gatewayStrategy:
                  type: object
                  required: ["mode"]
                  properties:
                    mode:
                      type: string
                      enum: ["per-namespace", "shared", "per-cluster"]
                    initialShards:
                      type: integer
                      minimum: 1
                      maximum: 20
                    quotaWarnThresholdRoutes:
                      type: integer
                      minimum: 1
                      default: 800
                      description: "单 Gateway 下 HTTPRoute 规则数预警阈值，避开 URL Map size limit"
                  x-kubernetes-validations:
                    - rule: "self.mode != 'per-namespace' || has(self.initialShards)"
                      message: "gatewayStrategy.mode 为 per-namespace 时必须设置 initialShards"
                multiTenancy:
                  type: object
                  required: ["isolationLevel"]
                  properties:
                    isolationLevel:
                      type: string
                      enum: ["namespace", "cluster"]
                    teams:
                      type: array
                      items:
                        type: string
                      minItems: 0
                  x-kubernetes-validations:
                    - rule: "self.isolationLevel != 'namespace' || (has(self.teams) && size(self.teams) > 0)"
                      message: "isolationLevel 为 namespace 时 teams 至少填一个团队"
                observability:
                  type: object
                  properties:
                    monitoringEnabled:
                      type: boolean
                      default: true
                    costLabel:
                      type: string
                      pattern: "^[a-z0-9-]+$"
              x-kubernetes-validations:
                # ⚠️ C3 修复(2026-10-05):原第 1 条 Autopilot 规则已删除。
                #   原规则:self.tier != 'autopilot' || self.network.mode == 'private'
                #   删除理由:tier 已 enum 锁死 ["standard"] → autopilot 永不可达,
                #   该规则成了永远为真的死代码。**留着比删掉更糟** ——
                #   它会让人误以为"autopilot 是支持的,只是有条件"。
                #
                # ⚠️ C6(2026-10-05 同步修复):Autopilot 时代的 multiTenancy
                #   兼容性规则失去判据,故改为对 Standard 的**实际**约束。
                #   标准集群同样有隔离要求,且这一条与 C3 的锁死方向一致:
                #   把"租户隔离"从文档约定变成 API Server 强制。
                # 1) per-cluster 隔离必须显式给出 teams(一个集群也要知道归谁管)
                - rule: "self.multiTenancy.isolationLevel != 'per-cluster' || (has(self.multiTenancy.teams) && size(self.multiTenancy.teams) > 0)"
                  message: "isolationLevel 为 per-cluster 时必须指定 teams:独占集群同样需要明确责任人"
                # 2) ⚠️ C9(2026-10-05):版本策略的三条硬规则,全部以 CEL 强制。
                # ⚠️ CEL 语义提醒:CEL **没有可选链**,has() 也不会自动向下传播。
                #   规则必须逐层 has() 守卫,否则字段缺省时会触发 runtime error
                #   而不是返回 false。下面每条规则的多层 !has() 不是啰嗦,是必需的。
                #   2.1) EOL 通告义务不得低于 30 天 —— 否则业务方毫无预警被强升。
                - rule: "!has(self.versionStrategy) || !has(self.versionStrategy.eolNoticeDays) || self.versionStrategy.eolNoticeDays >= 30"
                  message: "eolNoticeDays 不得小于 30:GKE 强制升级不可拦截,提前通告是唯一补救手段"
                # 2.2) minor CDB 不得配到 90 天上限。
                #    官方明示:配到上限会增大 EOL 时刻被强制升级的概率,
                #    且 EOL 时 GKE 改用 7 天预算并不遵守任何已配置的 CDB。
                - rule: "!has(self.versionStrategy) || !has(self.versionStrategy.cdb) || !has(self.versionStrategy.cdb.minorIntervalDays) || self.versionStrategy.cdb.minorIntervalDays <= 30"
                  message: "minorIntervalDays 不得超过 30:配到 90 会提高 EOL 被强制升级的概率,且 EOL 时该配置不生效"
                # 2.3) EOL 紧急 exclusion 不允许与"生产环境"共存。
                #    官方明确不推荐;若确需,必须走 break-glass 留痕而非默认开启。
                - rule: "!has(self.versionStrategy) || !has(self.versionStrategy.allowEolEmergencyExclusion) || self.versionStrategy.allowEolEmergencyExclusion == false || !has(self.environment) || self.environment != 'prod'"
                  message: "生产集群不得开启 allowEolEmergencyExclusion:官方不推荐该做法,紧急情况走 break-glass 流程"
            status:
              type: object
              properties:
                phase:
                  type: string
                  enum:
                    [
                      "Pending",
                      "QuotaBlocked",
                      "Provisioning",
                      "Ready",
                      "Failed",
                    ]
                assignedGatewayShards:
                  type: integer
                clusterEndpoint:
                  type: string
                conditions:
                  type: array
                  items:
                    type: object
                    properties:
                      type: { type: string }
                      status: { type: string }
                      reason: { type: string }
                      lastTransitionTime: { type: string, format: date-time }
```

## 2. 应用与校验效果

```bash
kubectl apply -f crd-clusterrequest.yaml
kubectl apply -f clusterspec-example.yaml
```

若提交的实例违反 CEL 规则（比如 `mode: per-namespace` 但漏填 `initialShards`），API Server 会在准入阶段直接拒绝：

```text
error: ClusterRequest.caas.internal "bbuk-team-a-prod" is invalid:
spec.gatewayStrategy: Invalid value: "object":
gatewayStrategy.mode 为 per-namespace 时必须设置 initialShards
```

## 3. 查看资源状态（用到新增的打印列）

```bash
kubectl get clusterrequest -A
```

```text
NAMESPACE   NAME                PROVIDER   TIER        GATEWAYSHARDS   PHASE     AGE
bbuk        bbuk-team-a-prod    gcp        standard   3               Ready     2h
```

---

# 注意事项

1. **CEL 校验（`x-kubernetes-validations`）要求 K8S 1.25+**（1.25 beta，1.29 GA），先确认你的 GKE 集群管理这套 CRD 的控制面版本满足要求，低版本需要退化成 Admission Webhook 做跨字段校验。
2. **`additionalPrinterColumns` 修改后需要重新 `kubectl apply` CRD 本身**，已存在的实例不受影响，但列展示需要 CRD 生效后才刷新。
3. **CRD 校验只能挡住"格式错误"，挡不住"业务超限"**：比如 `initialShards: 3` 格式合法，但实际 HTTPRoute 数已经逼近 URL Map 限额，这类判断仍需 Controller 在 Reconcile 阶段做运行时检查（对应前面 `precheck-gateway-quota.sh` 的逻辑），建议把结果写回 `status.conditions`。
4. **部署前用 `kubectl apply --dry-run=server -f crd-clusterrequest.yaml` 先做服务端校验**，避免 Schema 本身有语法错误导致 CRD 安装失败。

需要我接着把这个 CRD 对应的 **Controller Reconcile 逻辑（伪代码/Go controller-runtime 骨架）** 写出来，还是先把 `QuotaBlocked` 这个 phase 触发后的自动分片（自动创建新 Gateway shard）流程细化

# 搭建 ClusterRequest 控制器的协调循环骨架

# 问题分析

Controller 要做的事情，本质是一个标准的 **Reconcile Loop**：监听 `ClusterRequest` 的增删改，根据 `spec` 与当前 `status.phase` 的差异，驱动状态机往前推进（Pending → QuotaBlocked/Provisioning → Ready），并且要处理**幂等性**（Reconcile 可能被重复触发）和**外部长耗时操作**（Terraform Apply 集群创建不是秒级完成的，不能同步阻塞 Reconcile）。

---

# 解决方案

## 状态机设计

```mermaid
stateDiagram-v2
    [*] --> Pending
    Pending --> QuotaBlocked: 配额预检查未通过
    Pending --> Provisioning: 配额预检查通过
    QuotaBlocked --> Pending: 分片扩容后重新排队
    Provisioning --> Ready: Terraform Apply + GitOps 注入完成
    Provisioning --> Failed: 执行出错
    Failed --> Provisioning: 用户修复后重新触发
    Ready --> [*]
```

## Reconcile 核心逻辑分层

1. **Fetch + Finalizer 处理**：先判断是否为删除请求，走清理逻辑
2. **幂等性校验**：根据 `status.observedGeneration` 判断 spec 是否有实际变更，避免重复执行 Terraform
3. **状态机分发**：按 `status.phase` 分支处理，而不是每次都从头跑一遍全流程
4. **长耗时操作异步化**：Terraform Apply 通过 Job/外部 Provisioner 触发，Controller 只负责状态流转和轮询结果
5. **RequeueAfter**：而不是 busy-loop，配额检查/Terraform 状态查询都用退避重试

---

# 代码示例

## 1. Controller 骨架（controller-runtime）

```go
package controllers

import (
 "context"
 "fmt"
 "time"

 corev1 "k8s.io/api/core/v1"
 apierrors "k8s.io/apimachinery/pkg/api/errors"
 metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
 ctrl "sigs.k8s.io/controller-runtime"
 "sigs.k8s.io/controller-runtime/pkg/client"
 "sigs.k8s.io/controller-runtime/pkg/log"

 caasv1 "internal/caas/api/v1"
)

const (
 finalizerName = "caas.internal/cluster-cleanup"
)

// ClusterRequestReconciler 依赖的外部客户端，全部走接口，方便单测 mock
type ClusterRequestReconciler struct {
 client.Client
 QuotaChecker      QuotaChecker      // 对应 precheck-gateway-quota.sh 逻辑的 Go 化
 TerraformRunner   TerraformRunner   // 触发/查询 Terraform Apply Job
 GatewayShardMgr   GatewayShardManager
 GitOpsPolicyApplier GitOpsPolicyApplier
}

func (r *ClusterRequestReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
 logger := log.FromContext(ctx)

 // 1. Fetch 当前实例
 var cr caasv1.ClusterRequest
 if err := r.Get(ctx, req.NamespacedName, &cr); err != nil {
  if apierrors.IsNotFound(err) {
   return ctrl.Result{}, nil // 对象已删除，无需处理
  }
  return ctrl.Result{}, err
 }

 // 2. 删除逻辑：Finalizer 处理
 if !cr.ObjectMeta.DeletionTimestamp.IsZero() {
  return r.handleDeletion(ctx, &cr)
 }
 if !containsString(cr.Finalizers, finalizerName) {
  cr.Finalizers = append(cr.Finalizers, finalizerName)
  if err := r.Update(ctx, &cr); err != nil {
   return ctrl.Result{}, err
  }
 }

 // 3. 幂等性检查：spec 未变更且已是终态，直接跳过
 if cr.Status.ObservedGeneration == cr.Generation &&
  (cr.Status.Phase == caasv1.PhaseReady || cr.Status.Phase == caasv1.PhaseFailed) {
  return ctrl.Result{}, nil
 }

 // 4. 按状态机分发处理
 switch cr.Status.Phase {
 case "", caasv1.PhasePending:
  return r.reconcilePending(ctx, &cr)
 case caasv1.PhaseQuotaBlocked:
  return r.reconcileQuotaBlocked(ctx, &cr)
 case caasv1.PhaseProvisioning:
  return r.reconcileProvisioning(ctx, &cr)
 case caasv1.PhaseFailed:
  logger.Info("等待用户修复 spec 后重新触发", "name", cr.Name)
  return ctrl.Result{}, nil
 default:
  return ctrl.Result{}, fmt.Errorf("未知 phase: %s", cr.Status.Phase)
 }
}

// ---- Pending: 配额预检查 ----
func (r *ClusterRequestReconciler) reconcilePending(ctx context.Context, cr *caasv1.ClusterRequest) (ctrl.Result, error) {
 if cr.Spec.GatewayStrategy.Mode == "per-namespace" {
  ok, currentRoutes, err := r.QuotaChecker.CheckGatewayQuota(ctx, cr)
  if err != nil {
   return ctrl.Result{}, err
  }
  if !ok {
   cr.Status.Phase = caasv1.PhaseQuotaBlocked
   setCondition(cr, "QuotaCheck", metav1.ConditionFalse,
    "RouteCountNearLimit",
    fmt.Sprintf("当前路由数 %d 接近 URL Map 限额，需先扩容分片", currentRoutes))
   return r.updateStatus(ctx, cr, ctrl.Result{RequeueAfter: 5 * time.Minute})
  }
 }

 cr.Status.Phase = caasv1.PhaseProvisioning
 setCondition(cr, "QuotaCheck", metav1.ConditionTrue, "Passed", "配额预检查通过")
 return r.updateStatus(ctx, cr, ctrl.Result{Requeue: true})
}

// ---- QuotaBlocked: 等待分片扩容 ----
func (r *ClusterRequestReconciler) reconcileQuotaBlocked(ctx context.Context, cr *caasv1.ClusterRequest) (ctrl.Result, error) {
 shardAdded, err := r.GatewayShardMgr.TryAutoExpand(ctx, cr)
 if err != nil {
  return ctrl.Result{}, err
 }
 if shardAdded {
  cr.Status.Phase = caasv1.PhasePending // 回到 Pending 重新走一遍配额检查
  return r.updateStatus(ctx, cr, ctrl.Result{Requeue: true})
 }
 // 未能自动扩容（比如已达 initialShards 上限），保持 QuotaBlocked，退避轮询
 return ctrl.Result{RequeueAfter: 10 * time.Minute}, nil
}

// ---- Provisioning: 触发 Terraform + GitOps 注入 ----
func (r *ClusterRequestReconciler) reconcileProvisioning(ctx context.Context, cr *caasv1.ClusterRequest) (ctrl.Result, error) {
 status, err := r.TerraformRunner.EnsureApplied(ctx, cr) // 幂等：已存在则查询状态，不存在则触发
 if err != nil {
  cr.Status.Phase = caasv1.PhaseFailed
  setCondition(cr, "TerraformApply", metav1.ConditionFalse, "ApplyError", err.Error())
  return r.updateStatus(ctx, cr, ctrl.Result{})
 }

 switch status {
 case TerraformRunning:
  return ctrl.Result{RequeueAfter: 30 * time.Second}, nil // 轮询，不阻塞
 case TerraformSucceeded:
  if err := r.GitOpsPolicyApplier.ApplyBaseline(ctx, cr); err != nil {
   return ctrl.Result{}, err // 网络基线注入失败，下次 Reconcile 重试
  }
  cr.Status.Phase = caasv1.PhaseReady
  cr.Status.ObservedGeneration = cr.Generation
  setCondition(cr, "Ready", metav1.ConditionTrue, "ClusterProvisioned", "集群创建与策略注入完成")
  return r.updateStatus(ctx, cr, ctrl.Result{})
 default:
  cr.Status.Phase = caasv1.PhaseFailed
  return r.updateStatus(ctx, cr, ctrl.Result{})
 }
}

// ---- 删除：清理云上资源 ----
func (r *ClusterRequestReconciler) handleDeletion(ctx context.Context, cr *caasv1.ClusterRequest) (ctrl.Result, error) {
 if containsString(cr.Finalizers, finalizerName) {
  if err := r.TerraformRunner.EnsureDestroyed(ctx, cr); err != nil {
   return ctrl.Result{RequeueAfter: time.Minute}, err // 销毁失败，重试而不是丢弃 Finalizer
  }
  cr.Finalizers = removeString(cr.Finalizers, finalizerName)
  if err := r.Update(ctx, cr); err != nil {
   return ctrl.Result{}, err
  }
 }
 return ctrl.Result{}, nil
}

func (r *ClusterRequestReconciler) updateStatus(ctx context.Context, cr *caasv1.ClusterRequest, result ctrl.Result) (ctrl.Result, error) {
 if err := r.Status().Update(ctx, cr); err != nil {
  return ctrl.Result{}, err
 }
 return result, nil
}

func (r *ClusterRequestReconciler) SetupWithManager(mgr ctrl.Manager) error {
 return ctrl.NewControllerManagedBy(mgr).
  For(&caasv1.ClusterRequest{}).
  Complete(r)
}
```

## 2. 关键接口定义（便于 mock 单测）

```go
type QuotaChecker interface {
 // 对应 shell 脚本 precheck-gateway-quota.sh 的逻辑
 CheckGatewayQuota(ctx context.Context, cr *caasv1.ClusterRequest) (ok bool, currentRoutes int, err error)
}

type TerraformRunner interface {
 EnsureApplied(ctx context.Context, cr *caasv1.ClusterRequest) (TerraformStatus, error)
 EnsureDestroyed(ctx context.Context, cr *caasv1.ClusterRequest) error
}

type TerraformStatus string

const (
 TerraformRunning   TerraformStatus = "Running"
 TerraformSucceeded TerraformStatus = "Succeeded"
 TerraformFailed    TerraformStatus = "Failed"
)

type GatewayShardManager interface {
 TryAutoExpand(ctx context.Context, cr *caasv1.ClusterRequest) (expanded bool, err error)
}

type GitOpsPolicyApplier interface {
 // 通过 Config Sync/Fleet 下发 GatewayClass、mTLS Policy、RBAC 基线
 ApplyBaseline(ctx context.Context, cr *caasv1.ClusterRequest) error
}
```

---

# 注意事项

1. **`Reconcile` 必须是幂等的**：controller-runtime 的 WorkQueue 可能因为 Watch 事件重放、Leader 切换等原因重复触发同一个 Reconcile，上面用 `status.observedGeneration` 做了基本防重，实际生产建议再结合 Terraform 状态查询（`EnsureApplied` 内部应该先查是否已存在再决定是否 Apply）。
2. **长耗时操作（Terraform Apply）不要同步阻塞 Reconcile**：建议用 Kubernetes Job 或者外部 Provisioner（比如 Crossplane / Config Connector）异步执行，Controller 只负责查询状态和轮询，`RequeueAfter` 用退避策略（30s → 1min → 5min）避免打爆 API。
3. **`Status().Update` 和 `Update` 要分开调用**：如果 CRD 开启了 `subresources.status`（前一步 CRD 定义里已经加了），修改 `status` 字段必须用 `r.Status().Update()`，用普通 `Update()` 不会生效。
4. **Finalizer 逻辑要考虑销毁失败重试**：如果 Terraform Destroy 失败就直接移除 Finalizer，会导致云上资源孤儿（集群还在但 K8S 对象已经没了），上面示例里销毁失败会保留 Finalizer 并 `RequeueAfter` 重试。
5. **建议引入 `client-go` 的 `event recorder`**（`r.Recorder.Event(...)`），把关键状态变化同时写成 K8S Event，方便 `kubectl describe clusterrequest` 直接看到历史，而不用只看 status。

需要我接着把 `GatewayShardManager.TryAutoExpand` 的具体分片扩容逻辑（比如自动创建新 Gateway + 迁移部分 HTTPRoute）细化出来，还是先补充这个 Controller 对应的单元测试骨架（用 `envtest`/`fake client`）？

# 问题分析

`TryAutoExpand` 要解决的核心问题不是"建一个新 Gateway"这么简单，而是：

1. **往哪个新 Gateway 迁移哪些 HTTPRoute**（选择策略要按租户边界，不能把同一个团队的路由拆散到两个 shard）
2. **迁移过程不能中断流量**——因为在 GKE Gateway API 里，一个 Gateway 对应一个独立的 GCP 外部 LB（独立 IP），把 HTTPRoute 从 Gateway A 挪到 Gateway B，意味着**流量入口地址变了**，必须做"双挂载 + 确认健康 + 切流 + 摘除旧挂载"的安全下线流程，而不是一步 `kubectl apply` 切过去
3. **要有扩容边界**：不能无限自动建 shard，超出 `ClusterRequest` 声明的 `initialShards` 预算时要停下来要求人工介入（改 spec），否则会有失控的 LB 成本和治理黑洞

---

# 解决方案

## 迁移流程（双挂载安全切流）

```mermaid
sequenceDiagram
    participant C as Controller
    participant S1 as 旧 Gateway (shard-1, 超限)
    participant S2 as 新 Gateway (shard-2, 新建)
    participant R as HTTPRoute (待迁移)
    participant F as 前置路由器 Kong/Gloo

    C->>S2: 1. 创建新 Gateway shard-2
    C->>C: 等待 shard-2 status.Programmed=True
    C->>R: 2. Patch parentRefs 追加 shard-2（双挂载，shard-1 仍保留）
    C->>C: 3. 轮询 route.status.parents[shard-2].Accepted=True
    C->>F: 4. 探活确认 shard-2 服务正常后，切换前置路由器 host 映射指向 shard-2 LB IP
    C->>R: 5. Patch parentRefs 移除 shard-1（摘除旧挂载）
    C->>C: 6. 更新 status.gatewayShards 路由计数
```

## 扩容边界控制

```mermaid
graph TD
    A[TryAutoExpand 触发] --> B{当前 shard 数 >= initialShards?}
    B -->|是| C[status.phase 保持 QuotaBlocked<br/>设置 condition 要求人工提升 initialShards]
    B -->|否| D{距上次扩容 < 冷却时间?}
    D -->|是| E[跳过本次 Reconcile RequeueAfter]
    D -->|否| F[执行分片扩容流程]
```

---

# 代码示例

## 1. Shard 状态数据模型（扩展 CRD status）

```go
type GatewayShardStatus struct {
 Name            string   `json:"name"`
 RouteCount      int      `json:"routeCount"`
 Namespaces      []string `json:"namespaces"`
 LBAddress       string   `json:"lbAddress,omitempty"`
 CreatedAt       metav1.Time `json:"createdAt"`
}

// 追加到之前定义的 ClusterRequestStatus
type ClusterRequestStatus struct {
 Phase                 string                `json:"phase"`
 ObservedGeneration    int64                 `json:"observedGeneration,omitempty"`
 GatewayShards         []GatewayShardStatus  `json:"gatewayShards,omitempty"`
 LastShardExpansionAt  *metav1.Time          `json:"lastShardExpansionAt,omitempty"`
 Conditions            []metav1.Condition    `json:"conditions,omitempty"`
}
```

## 2. `TryAutoExpand` 主逻辑

```go
const shardExpansionCooldown = 10 * time.Minute

func (m *gatewayShardManager) TryAutoExpand(ctx context.Context, cr *caasv1.ClusterRequest) (bool, error) {
 logger := log.FromContext(ctx)

 // 1. 冷却时间检查，避免短时间内反复扩容抖动
 if cr.Status.LastShardExpansionAt != nil &&
  time.Since(cr.Status.LastShardExpansionAt.Time) < shardExpansionCooldown {
  logger.Info("处于扩容冷却期，跳过本次", "name", cr.Name)
  return false, nil
 }

 // 2. 找出超限的 shard
 overloaded := filterOverloaded(cr.Status.GatewayShards, cr.Spec.GatewayStrategy.QuotaWarnThresholdRoutes)
 if len(overloaded) == 0 {
  return false, nil
 }

 // 3. 扩容预算边界检查——不能悄悄超出 spec 声明的 initialShards
 currentShardCount := len(cr.Status.GatewayShards)
 if currentShardCount >= cr.Spec.GatewayStrategy.InitialShards {
  setCondition(cr, "ShardBudgetExceeded", metav1.ConditionTrue,
   "ManualInterventionRequired",
   fmt.Sprintf("当前 shard 数 %d 已达 initialShards 预算，需人工提升该值后才能继续扩容", currentShardCount))
  return false, nil // 不 error，交给上层保持 QuotaBlocked 状态并退避重试
 }

 // 4. 对每个超限 shard 执行扩容
 for _, shard := range overloaded {
  newShardName := nextShardName(cr, currentShardCount)

  newGW, err := m.createShardGateway(ctx, cr, newShardName)
  if err != nil {
   return false, fmt.Errorf("创建新 shard %s 失败: %w", newShardName, err)
  }
  if err := m.waitForGatewayProgrammed(ctx, newGW, 2*time.Minute); err != nil {
   return false, fmt.Errorf("新 shard %s 未就绪: %w", newShardName, err)
  }

  // 5. 按租户边界挑选待迁移路由（不拆散同一团队）
  reduceTarget := shard.RouteCount - cr.Spec.GatewayStrategy.QuotaWarnThresholdRoutes/2 // 迁移到安全水位以下
  candidates, err := m.selectMigrationCandidatesByTenant(ctx, shard, reduceTarget)
  if err != nil {
   return false, err
  }

  // 6. 执行安全切流迁移
  if err := m.migrateRoutes(ctx, candidates, shard.Name, newShardName); err != nil {
   return false, fmt.Errorf("迁移路由到 %s 失败: %w", newShardName, err)
  }

  m.recordShardExpansion(cr, newShardName, candidates)
 }

 now := metav1.Now()
 cr.Status.LastShardExpansionAt = &now
 return true, nil
}
```

## 3. 按租户边界选择迁移候选（避免拆散团队）

```go
// selectMigrationCandidatesByTenant 按 namespace 为最小迁移单元，
// 累加到达到 reduceTarget 路由数即停止，保证同一租户的路由始终在同一个 shard
func (m *gatewayShardManager) selectMigrationCandidatesByTenant(
 ctx context.Context, shard GatewayShardStatus, reduceTarget int,
) ([]HTTPRouteRef, error) {

 nsRouteMap, err := m.groupRoutesByNamespace(ctx, shard.Name)
 if err != nil {
  return nil, err
 }

 // 按 namespace 路由数升序排序，优先迁小的 namespace，减少影响面
 sortedNS := sortNamespacesByRouteCountAsc(nsRouteMap)

 var candidates []HTTPRouteRef
 migrated := 0
 for _, ns := range sortedNS {
  if migrated >= reduceTarget {
   break
  }
  candidates = append(candidates, nsRouteMap[ns]...)
  migrated += len(nsRouteMap[ns])
 }
 return candidates, nil
}
```

## 4. 安全切流迁移（双挂载 → 探活 → 切前置路由 → 摘旧挂载）

```go
func (m *gatewayShardManager) migrateRoutes(
 ctx context.Context, routes []HTTPRouteRef, oldShard, newShard string,
) error {
 logger := log.FromContext(ctx)

 // Step 1: 双挂载——追加新 Gateway 为 parentRef，旧的先保留
 for _, r := range routes {
  if err := m.patchAddParentRef(ctx, r, newShard); err != nil {
   return fmt.Errorf("route %s 双挂载失败: %w", r.Name, err)
  }
 }

 // Step 2: 轮询确认所有路由在新 shard 上 Accepted
 if err := m.waitForRoutesAccepted(ctx, routes, newShard, 3*time.Minute); err != nil {
  // 回滚：移除刚追加的 parentRef，避免留下悬挂状态
  for _, r := range routes {
   _ = m.patchRemoveParentRef(ctx, r, newShard)
  }
  return fmt.Errorf("新 shard 上路由未能全部 Accepted，已回滚: %w", err)
 }

 // Step 3: 探活确认新 shard 实际可服务流量（非仅 API 状态）
 if err := m.probeShardHealth(ctx, newShard, routes); err != nil {
  for _, r := range routes {
   _ = m.patchRemoveParentRef(ctx, r, newShard)
  }
  return fmt.Errorf("新 shard 探活失败，已回滚: %w", err)
 }

 // Step 4: 切换前置路由器（Kong/Gloo）host 映射到新 shard LB 地址
 if err := m.frontRouterUpdater.SwitchHostMapping(ctx, routes, newShard); err != nil {
  return fmt.Errorf("前置路由切流失败，保留双挂载状态待人工介入: %w", err)
 }

 logger.Info("前置路由已切换到新 shard，开始摘除旧 shard 挂载", "newShard", newShard)

 // Step 5: 摘除旧 Gateway 挂载，真正释放旧 URL Map 空间
 for _, r := range routes {
  if err := m.patchRemoveParentRef(ctx, r, oldShard); err != nil {
   // 旧挂载摘除失败不回滚新流量（流量已在新 shard 正常），只记录告警待人工清理
   logger.Error(err, "摘除旧 shard 挂载失败，需人工清理", "route", r.Name)
  }
 }
 return nil
}
```

---

# 注意事项

1. **跨 Gateway 迁移会改变外部 IP，必须有前置路由器兜底**：这也是为什么设计里假设你的架构里有 Kong/Gloo 这类前置层做 host 级路由——如果没有这一层，直接让 DNS 指向单个 Gateway IP，那么分片迁移会导致该 host 的对外地址变化，需要走 DNS TTL 生效周期，风险和延迟都大得多。
2. **双挂载期间两个 Gateway 都在消耗各自的 URL Map 配额**：这是临时状态，Step 5 摘除旧挂载不能省略，否则旧 shard 的配额并没有真正释放，等于没解决问题。
3. **`reduceTarget` 取阈值的一半而不是刚好压线**：给后续新增路由留缓冲，避免刚扩容完就立刻又逼近限额触发新一轮扩容抖动。
4. **`probeShardHealth` 的具体实现要真实发流量验证**（比如带 Host header 的 curl 探测，可以复用你现有的 `k8s-gateway-fqdn-claude.sh` 思路做 E2E 验证），只看 K8S status 的 `Accepted=True` 不代表 GCP LB 侧真的把流量转发通了。
5. **Step 5 失败要走告警而不是回滚**：因为此时新 shard 已经在服务流量了，回滚会造成二次风险，正确做法是记录告警、人工介入清理旧挂载，控制器不做自动回滚。
6. **`initialShards` 触顶后的人工介入路径要打通**：建议对接告警系统（比如 PagerDuty/企业内部 IM），`ShardBudgetExceeded` condition 一旦出现就主动通知负责人去评估是否提升 `spec.gatewayStrategy.initialShards`。

---

# 🆕 Standard 模式的责任转移（C3 修复 · 2026-10-05）

> **这一节是 C3 修复的"另一半"，也是更重要的一半。**
> 删掉 `default: autopilot` 只用了 3 行；把 Standard 锁死之后**CaaS 要多干的活**才是真正的工作量。
> **只锁死 tier 而不补这部分，等于把 Autopilot 省的活悄悄推给了 DC 平台组。**

## 1. 为什么不能只改 CRD

Autopilot 的核心价值是**没有节点层**。锁死 Standard 意味着：

| 原本由 GKE 托管            | 锁死后归谁      | 若无人编排会怎样                     |
| -------------------------- | --------------- | ------------------------------------ |
| 节点池版本与扩缩            | **DC / CaaS**   | 伸缩失控，成本泄漏                   |
| 节点升级策略选择            | **DC / CaaS**   | 升级时业务中断                       |
| 节点池数量                  | **DC / CaaS**   | **长期成本泄漏，最隐蔽**             |
| NAP(节点自动预配)           | **DC / CaaS**   | 容量与成本都不可预测                 |
| 节点镜像与补丁              | **DC / CaaS**   | 节点层漏洞窗口拉长                   |

> **但也要说清另一半**:DC 现有做法(Standard + auto-upgrade + 维护窗口 + 强制自动升级要求)
> **完全是 GKE 标准用法,升级执行仍由 GKE 完成,CaaS 不需要重做编排。**
>
> 正确定位:**CaaS 提供安全默认值与边界,不接管执行。**
> 详见 [`03-gcp-capability-profile.md` §3.1](./dc-owner-feedback/03-gcp-capability-profile.md) 与
> [`09-p0-execution-pack.md` §3.1](./dc-owner-feedback/09-p0-execution-pack.md) 的修正说明。

## 2. 因此 CaaS 必须补的四件事

| #   | 能力                       | 落地形态                                     | 优先级 |
| --- | -------------------------- | -------------------------------------------- | ------ |
| 1   | **节点层配置基线**          | Day-0 按画像注入 min/max、升级策略、镜像基线   | **P0** |
| 2   | **节点池数量收敛**          | 定期对账 + `ShardsBudgetExceeded` 同类的告警   | **P0** ⚠️ 最易被忽略 |
| 3   | **升级编排**                | 复用 GKE auto-upgrade,只编排窗口与顺序        | P1     |
| 4   | **节点层成本归集**          | 与 `caas-finops.md` 的 CostObject 对齐         | P1     |

> **第 2 条值得单独强调**:节点池数量膨胀是所有四项里**最隐蔽**的 ——
> 没有任何一次变更会报错,账单只是慢慢涨。Autopilot 时代不存在这个问题(CaaS 不管节点池)。

## 3. 需要补的 CRD 字段（本节不写实,只列清单）

> ⚠️ **这些字段本节刻意没给出完整 schema** —— 因为它们依赖 DC 对
> 节点机型/容量/成本的实际决策,现在定下来没有约束力(同 C9 的判断)。
> 建议与 SRE 开一次会定稿,再落到 CRD。

| 字段                                | 说明                                        | 待定内容                     |
| ----------------------------------- | ------------------------------------------- | ---------------------------- |
| `nodePoolProfile`                   | 节点池画像引用(按业务分级)                 | 机型、min/max、升级策略      |
| `autoscaling`                       | Cluster Autoscaler 边界                     | 是否 CaaS 托管,还是业务方自配 |
| `napEnabled`                        | 是否启用节点自动预配                        | 成本 vs 弹性取舍             |
| `nodeImageBaseline`                 | 节点镜像基线与补丁窗口                      | COS milestone 策略           |
| `maxNodePools`                      | **节点池数量上限(硬约束)**                  | 按成本倒推                   |

> **`maxNodePools` 建议做成 CEL 硬约束而非建议值** ——
> 与 C9 的 `minorIntervalDays <= 30` 同理:**能被绕过的治理等于没有治理。**

## 4. 与其它文件的关系

| 冲突 ID | 状态    | 说明                                                        |
| ------- | ------- | ----------------------------------------------------------- |
| **C3**  | ✅ 本次修复 | `default: autopilot` → `enum: ["standard"]`                |
| **C6**  | ✅ 同步修复 | Autopilot 兼容性规则失去判据,改为 Standard 的实际隔离约束  |
| C4      | ⬜ 未修   | 缺 `dataClassification` 字段                               |
| C5      | ⬜ 未修   | 缺 `Cluster` CRD                                           |

> ⚠️ **C3 与 C6 必须一起修** —— 只锁死 `tier` 而留着 Autopilot 的 CEL 规则,
> 会得到一条永远为真的死规则,以及一个"autopilot 好像还能用"的错觉。

---

# 🆕 版本与升级策略（C9 修复 · 2026-10-05）

> **为什么补这一节**：`14-doc-conflict-review.md` 的 C9 判定原文是"9 份文档里没有任何一处提到 GKE release channel"。
> 修复前的实际情况更糟一点——`gke-caas.md` 的 Terraform 骨架里**写死了 `channel = "REGULAR"`**，
> 那是一个从未被论证过的值，与 DC 立场（生产用 Stable）直接冲突。
>
> **本节事实依据**：`dc-owner-feedback/20-wp3-version-policy.md`，9 条 GKE 官方文档来源，查阅日期 2026-10-05。

## 1. 决策:生产 = Stable,且没有讨论空间

| 维度          | 结论                                                                              |
| ------------- | --------------------------------------------------------------------------------- |
| **环境范围**  | **CaaS 交付的全部生产集群**。dev/staging 可另议，但**不通过本 CRD 的 `channel` 字段**——它是 enum 锁死的 |
| **选择 Stable** | 生产环境优先稳定性；官方对生产集群明确推荐 Stable                                  |
| **RAPID**     | **明确禁令**（非"不推荐"）。官方明示 Rapid 及其 patch 版本**排除在 GKE SLA 之外** |
| **Extended**  | **不可用**。其官方禁用清单含 Config Sync 与 Policy Controller，而 DC 的 CaaS 基线依赖这两者 |
| **No channel**| 官方标注 deprecated 且将被移除；且**不支持 rollout sequencing**，无灰度能力          |

> **把决定固化为 `enum: ["STABLE"]` 而不是 `default: "STABLE"`** —— 这是本次修复的要点。
> `default` 允许业务方显式改成别的值；`enum` 单值则**在 API Server 层就拒绝**。
> 版本策略不是"默认值"，是**平台承诺**。用 `default` 等于把承诺变成建议。

## 2. GKE 强制的三条规则 —— CaaS 必须硬编码，不可协商

| 规则                     | 内容                                                                                | CaaS 的义务                                    |
| ------------------------ | ----------------------------------------------------------------------------------- | ---------------------------------------------- |
| **控制面 90 天 patch 底线** | 控制面至少每 90 天升一次 patch/minor；超时 GKE **无视所有策略强制升级**            | 纳管校验检查 patch 时间戳，超期拒绝；CRD 强字段  |
| **EOL 强制升级**         | 到达 end of standard support 时自动升级，maintenance exclusion **无法阻止**          | **提前 60 天主动通告业务方**（唯一补救手段）   |
| **节点 skew ≤ 2 minor**  | 节点最多落后控制面 2 个 minor；不得跑已 EOL 的 minor                                 | 纳管校验检查 skew，**原 RFC §9.1 准入条件缺此条** |

> **第 3 条是本次修复的意外收获。** 它原本不在 C9 范围内，是查 `20` 号文件时发现的：
> 一个 skew 超限的集群，控制面一升级就连带触发节点池重建 —— 这是"纳管后突然出事"最典型的来源，
> **而 RFC §9.1 的 BYOC 准入条件里没有这一条。** 建议单独提给 RFC。

## 3. 逃逸舱口：只允许向"更保守"方向偏

平台的价值是**约束**，不是提供选项。因此 `versionStrategy` 的所有可调项都刻意设计成单向下调：

| 字段                       | 可调范围            | 不可调的原因                                              |
| -------------------------- | ------------------- | --------------------------------------------------------- |
| `channel`                  | **锁死 STABLE**     | RAPID 无 SLA；Extended 与基线冲突                          |
| `minorUpgradePolicy`       | `auto` / `manual-soak` | 只能更保守（更长 soak），不能更激进                       |
| `cdb.minorIntervalDays`    | ≤ **30**（CEL 强制） | 官方明示配到 90 会提高 EOL 被强升的概率                   |
| `eolNoticeDays`            | ≥ **30**（CEL 强制） | 低于 30 天等于没有通告                                     |
| `allowEolEmergencyExclusion` | **prod 下禁止**（CEL 强制） | 官方不推荐；紧急情况走 break-glass 留痕      |

> ⚠️ **CDB 那一行值得单独说**：很多团队会想把 minor 间隔配到 90 天"减少打扰"。
> 官方明确指出这会**增大 EOL 时刻被强制升级的概率**，而且 **EOL 时 GKE 改用 7 天预算、
> 不遵守你配置的任何 CDB**。所以这条 CEL 不是洁癖，是拦住一个真实且常见误配。

### 3.1 CEL 写法上必须注意的一个坑

上面三条规则里，每条都带了**多层 `!has()` 守卫**，这不是冗余：

> **CEL 没有可选链，`has()` 也不会自动向下传播。**
> 写 `!has(self.versionStrategy) || self.versionStrategy.eolNoticeDays >= 30` 时，
> 如果一个请求填了 `versionStrategy` 但**省略** `eolNoticeDays`，
> CEL 会去访问一个不存在的字段 → **runtime error，而不是返回 false**。
> 正确写法必须逐层守卫：
> `!has(vs) || !has(vs.eolNoticeDays) || vs.eolNoticeDays >= 30`

已用 8 个用例验证（含"完全省略 versionStrategy""只填 channel""cdb 缺 minorIntervalDays" 等缺省场景）：

| 用例                                  | 结果   |
| ------------------------------------- | ------ |
| 完全不填 `versionStrategy`             | PASS   |
| 只填 `channel`                         | PASS   |
| 标准生产配置                           | PASS   |
| `eolNoticeDays: 10`                   | REJECT |
| `minorIntervalDays: 90`               | REJECT |
| `prod` + `allowEolEmergencyExclusion: true` | REJECT |
| `dev` + `allowEolEmergencyExclusion: true`  | PASS   |
| `cdb` 缺 `minorIntervalDays`          | PASS（守卫生效，未 crash） |

## 4. ⚠️ 已标注的推断与未验证项（诚实留白）

| 项                                                       | 状态                | 说明                                                                              |
| -------------------------------------------------------- | ------------------- | --------------------------------------------------------------------------------- |
| **Standard 模式是否真可加入 Extended**                     | `⬜ 待实测`          | 官方禁用清单只明示 Autopilot，Standard 未被点名。**推测可行，但不影响结论**——DC 基线特性无论如何都被禁 |
| **Control Plane 默认是 1 个还是 3 个（zonal/regional）**     | `⬜ 待确认`          | 需查 `google_container_cluster` 默认值与 `master_ipv4_cidr_block` 互斥关系           |
| **CDB 的 gcloud flag 与 Terraform 字段对应关系**           | `⬜ 待确认`          | 官方给的是 CLI flag（`--maintenance-minor-version-disruption-interval`）；需确认 Terraform provider 字段名，**本节未写对应 HCL** |
| **Accelerated patch auto-upgrades 是否启用**              | `⬜ 待决策`          | 更快拿安全补丁，但**跳过 qualification 步骤**且所有 patch 都提前升                 |

> **纪律**：这四项在写进 `03-gcp-capability-profile.md` 之前必须实测或查证。
> **不实测就不写** —— 否则就是我自己在犯"尚未评估被当已支持"的错。

## 5. 与其它文件的衔接

| 相关文件                                                | 衔接点                                                              |
| ------------------------------------------------------ | ------------------------------------------------------------------ |
| [`dc-owner-feedback/20-wp3-version-policy.md`](./dc-owner-feedback/20-wp3-version-policy.md) | 本节全部 GKE 事实的来源（9 条官方引用）                           |
| [`dc-owner-feedback/21-byoc-classification-toolkit.md`](./dc-owner-feedback/21-byoc-classification-toolkit.md) | §2 第 3 条 skew 约束应加入 BYOC 准入判定                          |
| [`dc-owner-feedback/09-p0-execution-pack.md`](./dc-owner-feedback/09-p0-execution-pack.md) | §3 的 WP-3 交付即本节                                                |
| [`dc-owner-feedback/14-doc-conflict-review.md`](./dc-owner-feedback/14-doc-conflict-review.md) | C9 在此关闭；建议新增 C10（skew 缺失）                          |

---

需要我接着把 `probeShardHealth` 的具体探活实现（结合你现有的 FQDN 追踪脚本思路）细化出来，还是先把 `frontRouterUpdater.SwitchHostMapping` 对接 Kong/Gloo 的具体配置方式写出来？
