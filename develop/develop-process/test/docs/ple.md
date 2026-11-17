# PLE (Production-Like Environment) 隔离架构深度评估

## 背景与问题定义

### 场景描述

```
┌─────────────────────────────────────────────────────────────────┐
│                    理想中的 PLE                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  PRD Network Infrastructure (VPC, Subnet, Firewall)      │   │
│  │                                                          │   │
│  │  ┌─────────┐         ┌─────────┐                        │   │
│  │  │  PRD    │◀──────▶│  PLE    │  ← 用户希望 PLE       │   │
│  │  │ (Real)  │         │(Simulate)│    使用 PRD 网络      │   │
│  │  └────┬────┘         └────┬────┘                        │   │
│  │       │                   │                              │   │
│  │       └───── ✖ ──────────┘                              │   │
│  │              不应互通！                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 核心矛盾

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  用户需求：使用 PRD 网络基础设施（相同的 VPC、Subnet、Firewall）│
│                                                             │
│  安全原则：PRD 和 non-PRD 完全隔离，不能互通                 │
│                                                             │
│  矛盾点：                                                   │
│    "在同一网络中" + "完全隔离" = 逻辑上不可能共存            │
│                                                             │
│    如果 PLE 在 PRD VPC 内：                                  │
│      → PLE 可以路由到 PRD 资源（同一 subnet/IP 空间）        │
│      → Firewall 规则可能允许某些流量                         │
│      → 服务发现（DNS）可能解析到 PRD                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 深度分析：隔离层次

### 隔离不是单一层次，而是多层控制

```
┌─────────────────────────────────────────────────────────────────┐
│                     隔离层次金字塔                               │
│                                                             │
│                         ▲                                    │
│                        /█\                                   │
│                       / █ \          L7: 应用层隔离           │
│                      /  █  \         (API Gateway, Auth)       │
│                     /───█───\                                │
│                    /    █    \       L4: 网络层隔离           │
│                   /     █     \      (Firewall, VPC, Route)    │
│                  /──────█──────\                             │
│                 /       █       \    L3: IAM/身份隔离          │
│                /        █        \   (Service Account, RBAC)    │
│               /─────────█─────────\                          │
│              /          █          \  L2: 数据层隔离           │
│             /           █           \ (Secret, DB, Storage)    │
│            /─────────────────────────\                        │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### 每一层的隔离能力

| 层次 | 控制点 | 能否单独保证"PRD隔离" | 失效后果 |
|------|--------|----------------------|---------|
| **L7 应用层** | API Gateway、Auth、JWT | ❌ 否 | 应用层被攻破则网络层无防护 |
| **L4 网络层** | VPC、Firewall、Route | ⚠️ 部分 | 内部威胁、0-day 漏洞 |
| **L3 身份层** | IAM、SA、RBAC | ⚠️ 部分 | 权限配置错误 |
| **L2 数据层** | Secret Manager、KMS、DB | ✅ 可独立 | 数据不泄露 |

**结论：网络层隔离是必要条件，但不是充分条件。**

---

## 核心问题拆解

### 问题 1：什么叫"使用 PRD 网络基础设施"？

```
用户可能的意图（需要澄清）：
  A. 希望 PLE 使用与 PRD 相同的网络配置
     → 相同的 CIDR、相同的架构模式、相同的 Firewall 规则

  B. 希望 PLE 与 PRD 在同一 VPC/Subnet 中
     → 共享 IP 地址空间
     → 可以直接网络互通

  C. 希望 PLE 使用 PRD 的网络服务（ILB、Cloud DNS）
     → 使用相同的负载均衡器配置
     → 使用相同的 DNS 解析规则

  D. 希望 PLE 看起来像 PRD（用于欺骗/蜜罐）
     → 相同的主机名、相同的证书、相同的路径
```

**关键问题：需要和用户确认 "PRD 网络基础设施" 的具体含义**

### 问题 2：隔离的目标是什么？

```
┌──────────────────────────────────────────────────────────────┐
│  隔离要防什么？                                               │
│                                                              │
│  场景 1: 防止 PLE 用户访问 PRD 资源                           │
│    → 隔离方向：PLE 不能访问 PRD                               │
│    → PRD 可以访问 PLE？（取决于业务需求）                      │
│                                                              │
│  场景 2: 防止 PRD 被 PLE 中的恶意代码影响                      │
│    → 隔离方向：双向隔离                                       │
│    → PLE 被攻破不影响 PRD                                     │
│                                                              │
│  场景 3: 防止 PLE 中的测试数据污染 PRD 数据                   │
│    → 隔离方向：数据层隔离                                     │
│    → 网络隔离不够，需要存储/数据库隔离                        │
│                                                              │
│  场景 4: 合规要求（等保、金融行业）                           │
│    → 监管要求：PRD 和 测试环境必须网络隔离                     │
│    → 审计要求：任何跨环境访问必须记录                         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 问题 3：攻击面分析

```
如果 PLE 和 PRD 在同一 VPC 中，攻击路径有哪些？

┌──────────────────────────────────────────────────────────────┐
│  攻击路径 1: DNS 劫持                                         │
│  ┌────────┐      ┌────────┐      ┌────────┐                  │
│  │  PLE   │────▶│  DNS   │────▶│  PRD   │                  │
│  │  App   │     │ Resolver│     │  Real  │                  │
│  └────────┘      └────────┘      └────────┘                  │
│                   如果 PLE 可以控制 DNS 解析                  │
│                   可能将 PRD 域名解析到 PLE IP                │
├──────────────────────────────────────────────────────────────┤
│  攻击路径 2: 内网横向移动                                     │
│  ┌────────┐      ┌────────┐      ┌────────┐                  │
│  │  PLE   │────▶│ Firewall│────▶│  PRD   │                  │
│  │  Pod   │     │  Allow  │     │  DB    │                  │
│  └────────┘      └────────┘      └────────┘                  │
│                   如果 Firewall 规则配置错误                  │
│                   PLE 可能绕过访问 PRD 数据库                 │
├──────────────────────────────────────────────────────────────┤
│  攻击路径 3: 服务发现                                         │
│  ┌────────┐      ┌────────┐      ┌────────┐                  │
│  │  PLE   │────▶│ Kubernetes│───▶│  PRD   │                │
│  │ Service│     │   API    │    │ Service│                 │
│  └────────┘      └────────┘      └────────┘                  │
│                   如果使用相同的服务账户                      │
│                   PLE 可以冒充 PRD 服务进行通信               │
├──────────────────────────────────────────────────────────────┤
│  攻击路径 4: 元数据服务                                       │
│  ┌────────┐      ┌────────┐                                  │
│  │  PLE   │────▶│  GCP    │                                  │
│  │  VM    │     │Metadata │                                  │
│  └────────┘      │ Service │                                  │
│                   └────────┘                                  │
│                   每个 VM 都可以访问 metadata (169.254.169.254)│
│                   获取 Service Account token                  │
│                   如果 SA 权限过大，可直接操作 PRD 资源       │
├──────────────────────────────────────────────────────────────┤
│  攻击路径 5: 共享存储                                         │
│  ┌────────┐      ┌────────┐      ┌────────┐                  │
│  │  PLE   │────▶│  GCS    │────▶│  PRD   │                  │
│  │ Bucket │     │  Bucket │     │Bucket  │                  │
│  └────────┘      └────────┘      └────────┘                  │
│                   如果 PLE 有 PRD bucket 的访问权限            │
│                   可以读写 PRD 数据                           │
└──────────────────────────────────────────────────────────────┘
```

---

## 深度评估维度

### 维度 1：网络架构隔离

#### 方案 A：完全独立 VPC（最安全）

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   VPC PRD (10.0.0.0/16)          VPC PLE (10.1.0.0/16)   │
│   ┌──────────────────┐            ┌──────────────────┐    │
│   │   PRD Services    │            │   PLE Services    │    │
│   │   10.0.1.0/24     │   ✖       │   10.1.1.0/24     │    │
│   └──────────────────┘   隔离     └──────────────────┘    │
│                                                             │
│   优点：完全网络隔离，攻击面最小                             │
│   缺点：用户认为"没有使用 PRD 网络基础设施"                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 方案 B：Shared VPC + 不同 Project

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   Shared VPC Host Project                                   │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  Subnet: 10.0.0.0/16                                 │  │
│   │                                                       │  │
│   │  ┌─────────────┐         ┌─────────────┐             │  │
│   │  │ PRD Project  │         │ PLE Project │             │  │
│   │  │ 10.0.1.0/24  │   ✖    │ 10.0.2.0/24  │             │  │
│   │  └─────────────┘   隔离  └─────────────┘             │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   优点：共享网络基础设施（Subnet、路由），但项目级隔离       │
│   缺点：同一 Subnet 内的 VM 可能通过 firewall 互通           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 方案 C：VPC Peering / PSC + 严格 Firewall

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   VPC PRD ◀────── VPC Peering ─────▶ VPC PLE              │
│              (或 PSC Tunnel)                                 │
│                                                             │
│   Firewall 规则：                                           │
│     PRD → PLE:  DROP (所有流量)                            │
│     PLE → PRD:  DROP (所有流量)                            │
│                                                             │
│   优点：逻辑上分离，可通过 peering 连接复用                  │
│   缺点：依赖 Firewall 配置正确性；配置错误即隔离失效        │
│                                                             │
│   ⚠️  关键问题：                                           │
│       GCP Firewall 是 Stateful！                            │
│       如果 PLE → PRD 允许任意流量，                          │
│       PRD → PLE 响应流量也会被自动放行                      │
│       必须使用 Firewall Policy 或更细粒度控制                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 维度 2：Identity & Access 隔离

```
┌─────────────────────────────────────────────────────────────┐
│  GCP IAM 隔离层次                                          │
│                                                             │
│  1. Project 级别：                                         │
│     PRD Project:  project-prd-xxx                          │
│     PLE Project:  project-ple-xxx                          │
│     → 默认情况下不同项目的资源不能互相访问                   │
│                                                             │
│  2. Service Account 级别：                                  │
│     PLE 中的 VM/服务使用的 SA 必须是 PLE Project 的         │
│     → 不能使用 PRD 的 SA                                    │
│     → 不能跨 Project 使用 SA                                │
│                                                             │
│  3. Workload Identity 级别（如果使用 K8s）：                │
│     PLE Cluster 的 Workload Identity 应该绑定 PLE SA        │
│     → 禁止绑定 PRD Service Account                          │
│                                                             │
│  4. Firewall SA 限制：                                      │
│     GCP Metadata API (169.254.169.254)                      │
│     → 每个 VM 只能获取自己 Project 的 SA token              │
│     → 如果 PLE VM 被入侵，攻击者只能获取 PLE SA            │
│                                                             │
│  ⚠️  常见错误：                                            │
│      在 PLE 中使用 PRD 的 Service Account Key               │
│      → 这会让 PLE 完全拥有 PRD 的权限                       │
│      → 无论网络隔离做得多好，都是徒劳                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 维度 3：数据层隔离

```
┌─────────────────────────────────────────────────────────────┐
│  数据层隔离关键点                                          │
│                                                             │
│  1. 数据库：                                               │
│     PRD 使用 RDS P1 (10.0.1.0/24)                          │
│     PLE 必须使用不同的 RDS 实例                            │
│     → 不能共享同一个数据库                                  │
│     → 不能访问 PRD 的数据库                                 │
│                                                             │
│  2. 缓存（Redis/Memcached）：                               │
│     PLE 必须使用独立的缓存实例                              │
│     → 不能与 PRD 共享                                       │
│     → 防止数据泄露                                          │
│                                                             │
│  3. Secret Manager：                                       │
│     PRD Secret: projects/prd/secrets/...                   │
│     PLE Secret: projects/ple/secrets/...                   │
│     → PLE 不能访问 PRD 的 Secret                           │
│     → 建议：PLE 使用不同的密钥加密                          │
│                                                             │
│  4. KMS：                                                  │
│     如果 PLE 需要解密 PRD 的数据（不应该）                  │
│     → 需要 PLE 有 KMS 解密权限                              │
│     → 建议：使用不同的 KMS Key                              │
│                                                             │
│  5. 对象存储（GCS）：                                        │
│     PRD Bucket: gs://app-prd-data/                         │
│     PLE Bucket: gs://app-ple-data/                        │
│     → PLE 不能有 PRD Bucket 的访问权限                      │
│     → 如果需要"模拟 PRD"，可以同步脱敏后的数据              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 维度 4：DNS & 服务发现隔离

```
┌─────────────────────────────────────────────────────────────┐
│  Cloud DNS 隔离问题                                        │
│                                                             │
│  场景：PRD 和 PLE 在不同 Project，但使用相同的私有域名       │
│                                                             │
│  PRD: api.internal.company.com → 10.0.1.50 (PRD Service)   │
│  PLE: api.internal.company.com → 10.1.1.50 (PLE Service)  │
│                                                             │
│  问题：                                                     │
│     Cloud DNS 是 Project 级私有 DNS                         │
│     不同 Project 的私有 DNS Zone 不能直接共享               │
│                                                             │
│  解决方案：                                                 │
│                                                             │
│  方案 1: 独立 DNS Zone                                     │
│     PRD Zone: prd.internal.company.com                     │
│     PLE Zone: ple.internal.company.com                     │
│     → 完全隔离，但域名不同                                  │
│                                                             │
│  方案 2: Shared VPC + DNS Policy                           │
│     在 Host Project 创建 DNS Zone                          │
│     PRD 和 PLE Project 共享此 Zone                         │
│     → 需要 DNS Policy 控制解析规则                          │
│     → PLE 的解析结果指向 PLE IP                             │
│     → PRD 的解析结果指向 PRD IP                             │
│                                                             │
│  方案 3: 使用不同的服务名                                   │
│     PRD: api.prd.internal.company.com                      │
│     PLE: api.ple.internal.company.com                      │
│     → 最简单，但不"像" PRD                                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 维度 5：日志 & 监控隔离

```
┌─────────────────────────────────────────────────────────────┐
│  日志和监控的隔离要求                                      │
│                                                             │
│  1. Cloud Logging：                                         │
│     PRD logs → PRD Log Sink → PRD BigQueryDataset          │
│     PLE logs → PLE Log Sink → PLE BigQueryDataset          │
│     → 不能混合，防止 PLE 日志污染 PRD 数据                   │
│                                                             │
│  2. Cloud Monitoring:                                       │
│     PLE 应该有自己的 Metrics Scope                         │
│     → 避免 PLE 的告警发送到 PRD 告警渠道                    │
│     → 避免 PLE 的 SLO/SLI 影响 PRD Dashboard               │
│                                                             │
│  3. Alerting:                                               │
│     PRD Alert: 发给 SRE 团队                               │
│     PLE Alert: 发给测试团队或 PLE 管理员                    │
│     → 绝对不能混用                                          │
│                                                             │
│  4. Trace (Cloud Trace):                                   │
│     PRD 和 PLE 应该有独立的 Trace Project                   │
│     → 防止追踪数据泄露                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 维度 6：成本 & 资源隔离

```
┌─────────────────────────────────────────────────────────────┐
│  成本隔离                                                   │
│                                                             │
│  1. Billing Account：                                       │
│     PRD 和 PLE 应该绑定不同的 Billing Account               │
│     → 方便成本分摊和核算                                    │
│     → 避免 PLE 费用计入 PRD                                 │
│                                                             │
│  2. Quota：                                                │
│     每个 Project 有独立的 Quota                            │
│     → PLE 不会消耗 PRD 的配额                               │
│     → 也不会因为 PRD 配额耗尽而受影响                       │
│                                                             │
│  3. Resource Group / Label：                               │
│     统一资源标签规范：                                       │
│     env=prd, env=ple                                        │
│     → 用于成本分析和资源筛选                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 关键风险点评估

### 风险矩阵

| 风险 | 严重性 | 可能性 | 缓解措施 |
|------|--------|--------|---------|
| **Firewall 配置错误导致跨环境互通** | 🔴 严重 | 🟡 中 | Firewall Policy + 定期审计 |
| **PLE 使用了 PRD 的 Service Account** | 🔴 严重 | 🟢 低（如果规范明确） | IAM Org Policy 禁止 |
| **DNS 解析指向错误环境** | 🟠 高 | 🟡 中 | DNS Policy + 解析验证 |
| **共享 KMS Key 导致数据泄露** | 🔴 严重 | 🟡 中 | 不同 Project 不同 Key |
| **GCS Bucket 权限过大** | 🟠 高 | 🟡 中 | Bucket Policy + ACL 最小化 |
| **网络带宽共享导致 PRD 性能下降** | 🟡 低 | 🟢 低 | 独立 Subnet + 配额 |
| **审计日志混合导致合规问题** | 🟡 中 | 🟡 中 | 独立 Log Sink |

### 高危场景

```
┌─────────────────────────────────────────────────────────────┐
│  场景 1: PLE 测试代码意外访问 PRD 数据库                    │
│                                                             │
│  原因：连接字符串配置错误 / 环境变量泄露                     │
│  影响：测试数据写入 PRD，生产事故                           │
│                                                             │
│  缓解：                                                      │
│  1. 代码扫描：禁止硬编码 PRD 连接字符串                     │
│  2. IAM 最小化：PLE SA 不能访问 PRD DB                     │
│  3. 网络层：即使 IAM 错误，Firewall 也阻止连接             │
│  4. 审计：所有 DB 访问必须有日志                           │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  场景 2: PLE 被攻破，攻击者尝试横向移动到 PRD               │
│                                                             │
│  原因：网络隔离不彻底 / IAM 权限过大                        │
│  影响：PRD 数据泄露 / 服务中断                               │
│                                                             │
│  缓解：                                                      │
│  1. 深度防御：多层隔离（网络+IAM+应用）                    │
│  2. PLE SA 使用最小权限                                     │
│  3. PRD 对 PLE 的访问完全不可达                            │
│  4. 入侵检测：异常流量告警                                  │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  场景 3: 误操作导致 PRD 配置被应用到 PLE                   │
│                                                             │
│  原因：IaC 配置错误 / GitOps 流程问题                       │
│  影响：PLE 意外获得 PRD 配置，可能暴露敏感信息             │
│                                                             │
│  缓解：                                                      │
│  1. Git 分支隔离：PRD 和 PLE 使用不同分支                  │
│  2. CI/CD 验证：部署前必须通过环境检查                     │
│  3. IaC drift 检测：发现配置漂移立即告警                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 推荐架构方案

### 方案：Project 级完全隔离 + 可选网络连接

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Organization Level                     │    │
│  │                                                       │    │
│  │   ┌─────────────────┐      ┌─────────────────┐     │    │
│  │   │  PRD Project     │      │  PLE Project    │     │    │
│  │   │  project-prd-xxx │      │  project-ple-xxx│     │    │
│  │   │                   │      │                  │     │    │
│  │   │  VPC: vpc-prd    │      │  VPC: vpc-ple   │     │    │
│  │   │  Subnet: /24     │      │  Subnet: /24    │     │    │
│  │   │                   │      │                  │     │    │
│  │   │  ┌───────────┐  │      │  ┌───────────┐  │     │    │
│  │   │  │ Services  │  │  ✖  │  │ Services  │  │     │    │
│  │   │  └───────────┘  │  隔离 │  └───────────┘  │     │    │
│  │   │                   │      │                  │     │    │
│  │   │  SA: sa-prd-xxx │      │  SA: sa-ple-xxx│     │    │
│  │   └─────────────────┘      └─────────────────┘     │    │
│  │          │                        │               │    │
│  │          │                        │               │    │
│  │          └──────────┬─────────────┘               │    │
│  │                     │                              │    │
│  │              Shared VPC Host (可选)                 │    │
│  │              (复用Subnet规划，不复用流量)           │    │
│  │                                                       │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 共享基础设施的方式（逻辑复用，非网络复用）

```
┌─────────────────────────────────────────────────────────────┐
│  "使用 PRD 网络基础设施" 的正确理解                         │
│                                                             │
│  ✅ 可以共享/复用的：                                       │
│     1. IP 地址规划（CIDR 分配表）                           │
│     2. Subnet 划分策略                                      │
│     3. Firewall 规则模板                                     │
│     4. 网络架构图（topology）                                │
│     5. 路由策略设计                                          │
│     6. 负载均衡配置模式                                      │
│     7. DNS 命名规范                                          │
│                                                             │
│  ❌ 不能共享/复用的：                                       │
│     1. VPC ID / Subnet IP Range（必须独立）                 │
│     2. Firewall 实际规则（必须隔离）                        │
│     3. 实际的网络流量（完全隔离）                           │
│     4. 共享的服务发现结果                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 如果必须跨 VPC 连接（仅某些场景）

```
┌─────────────────────────────────────────────────────────────┐
│  特殊情况：PLE 需要调用 PRD 的某些 API                       │
│                                                             │
│  例如：PLE 中的监控系统需要读取 PRD 的 Metrics              │
│                                                             │
│  可控方案：PSC (Private Service Connect)                    │
│                                                             │
│     PLE          PSC Tunnel         PRD                     │
│   ┌──────┐                         ┌──────┐               │
│   │Service│────────────────────────▶│Service│               │
│   └──────┘    仅允许特定 API       └──────┘               │
│               (通过 SA 和 IAM 控制)                         │
│                                                             │
│  关键约束：                                                 │
│     1. 只能单向：PLE → PRD                                  │
│     2. PRD 不能主动连接 PLE                                 │
│     3. 只暴露必要的 API，不暴露全部服务                     │
│     4. 所有调用必须通过 IAM 授权                            │
│     5. 所有流量必须记录审计日志                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## GCP 原生隔离控制措施

### 1. Organization Policy (Org Policy)

```yaml
# 强制每个 Project 使用独立 VPC
orgPolicies:
  - name: "restrict-shared-vpc"
    spec:
      inheritFromParent: false
      rules:
        - condition:
            expression: "resource.type == 'compute.googleapis.com/Project'"
          enforce: true

# 禁止跨 Project Service Account 使用
  - name: "disable-cross-project-service-account"
    spec:
      rules:
        - condition:
            expression: "resource.service == 'compute.googleapis.com'"
          deny:
            values: ["iam.googleapis.com"]

# 强制 PLE Project 的 VM 不能有 PRD SA
  - name: "allowed-service-accounts"
    spec:
      rules:
        - condition:
            expression: "project.environment == 'prd'"
          allow:
            values: ["projects/project-prd-xxx/serviceAccounts/*"]
        - condition:
            expression: "project.environment == 'ple'"
          allow:
            values: ["projects/project-ple-xxx/serviceAccounts/*"]
```

### 2. VPC Firewall Rules

```yaml
# PLE Project 的 Firewall
firewall_rules:
  # 拒绝所有来自 PRD 的流量
  - name: "deny-from-prd"
    direction: INGRESS
    priority: 100
    sourceRanges:
      - "10.0.0.0/16"  # PRD VPC CIDR
    action: DENY
    logConfig:
      enabled: true  # 所有拒绝流量都记录

  # 允许 PLE 内部流量
  - name: "allow-internal-ple"
    direction: INGRESS
    priority: 1000
    sourceRanges:
      - "10.1.0.0/16"  # PLE VPC CIDR
    action: ALLOW

  # 拒绝所有出站到 PRD
  - name: "deny-to-prd"
    direction: EGRESS
    priority: 100
    destinationRanges:
      - "10.0.0.0/16"  # PRD VPC CIDR
    action: DENY
    logConfig:
      enabled: true
```

### 3. IAM 条件（Conditional IAM）

```yaml
# PLE Service Account 的权限限制
- role: roles/compute.admin
  members:
    - serviceAccount:ple-workspace@project-ple-xxx.iam.gserviceaccount.com
  condition:
    title: "只允许在 PLE Project 操作"
    expression: "resource.name.startsWith('projects/project-ple-xxx')"
```

---

## 验证和测试

### 隔离验证清单

```
┌─────────────────────────────────────────────────────────────┐
│  网络层验证                                                │
│                                                             │
│  [ ] PLE VM 不能 ping PRD VM (同一 subnet 不同 project)    │
│  [ ] PLE VM 不能 telnet PRD 端口                           │
│  [ ] PLE egress 到 PRD CIDR 被 firewall 拒绝             │
│  [ ] PRD egress 到 PLE CIDR 被 firewall 拒绝              │
│  [ ] Firewall 日志中有预期的 DENY 记录                    │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  IAM 层验证                                                │
│                                                             │
│  [ ] PLE SA 不能列出 PRD Project 的资源                   │
│  [ ] PLE SA 不能访问 PRD 的 GCS Bucket                    │
│  [ ] PLE SA 不能解密 PRD 的 KMS Key                       │
│  [ ] PLE VM metadata 只返回 PLE SA token                   │
│  [ ] 尝试跨 Project 访问会被拒绝                           │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  DNS 层验证                                                │
│                                                             │
│  [ ] PLE 内部 DNS 解析到 PLE Service IP                   │
│  [ ] PRD 内部 DNS 解析到 PRD Service IP                   │
│  [ ] PLE 不能通过 DNS 发现 PRD Service                    │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  数据层验证                                                │
│                                                             │
│  [ ] PLE 不能访问 PRD 的数据库                             │
│  [ ] PLE 不能访问 PRD 的 Secret Manager                    │
│  [ ] PLE 不能访问 PRD 的 KMS Key                          │
│  [ ] PLE 只能访问自己的 GCS Bucket                        │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  日志层验证                                                │
│                                                             │
│  [ ] PRD 日志只包含 PRD 资源                               │
│  [ ] PLE 日志只包含 PLE 资源                               │
│  [ ] 跨环境访问尝试被记录                                  │
│  [ ] 审计日志完整可追溯                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 自动化验证脚本

```bash
#!/bin/bash
# ple-isolation-test.sh - PLE 隔离验证脚本

set -e

PRD_CIDR="10.0.0.0/16"
PLE_CIDR="10.1.0.0/16"
PRD_PROJECT="project-prd-xxx"
PLE_PROJECT="project-ple-xxx"

echo "=== PLE 隔离验证测试 ==="

# 1. 网络层验证
echo "[1/4] 测试网络隔离..."
# PLE VM ping PRD (应该失败)
if gcloud compute ssh ple-vm --project=$PLE_PROJECT --command="ping -c 3 10.0.1.50" 2>/dev/null; then
    echo "❌ FAIL: PLE 可以访问 PRD 内网"
    exit 1
else
    echo "✅ PASS: PLE 无法访问 PRD 内网"
fi

# 2. IAM 验证
echo "[2/4] 测试 IAM 隔离..."
# 尝试列出 PRD 资源 (应该失败)
if gcloud compute instances list --project=$PLE_PROJECT 2>&1 | grep -q "prd-"; then
    echo "❌ FAIL: PLE 可以看到 PRD 资源"
    exit 1
else
    echo "✅ PASS: PLE IAM 隔离正常"
fi

# 3. GCS 验证
echo "[3/4] 测试存储隔离..."
# 尝试访问 PRD bucket (应该失败)
if gsutil ls gs://app-prd-data/ --project=$PLE_PROJECT 2>/dev/null; then
    echo "❌ FAIL: PLE 可以访问 PRD GCS"
    exit 1
else
    echo "✅ PASS: PLE 无法访问 PRD 存储"
fi

# 4. Firewall 日志验证
echo "[4/4] 测试 Firewall 日志..."
# 检查是否有异常的跨环境流量
DENY_COUNT=$(gcloud logging read \
    'resource.type="gce_subnetwork" AND jsonPayload.enforcement.action="DENY"' \
    --project=$PLE_PROJECT --format="value(timestamp)" | wc -l)

if [ $DENY_COUNT -gt 0 ]; then
    echo "✅ PASS: Firewall DENY 日志正常 ($DENY_COUNT 条)"
else
    echo "⚠️  WARNING: 未发现 Firewall DENY 日志，请检查日志配置"
fi

echo "=== 验证完成 ==="
```

---

## 合规与审计

### 合规要求对照

| 合规标准 | 相关要求 | PLE 如何满足 |
|---------|---------|-------------|
| **等保 2.0** | 三级系统要求网络隔离 | PLE 与 PRD 完全网络隔离 |
| **PCI-DSS** | 测试环境与生产环境隔离 | 使用独立 Project 和 VPC |
| **SOC 2** | 环境隔离、控制变更 | 不同 Project、不同 SA |
| **ISO 27001** | 网络分段、访问控制 | VPC + Firewall + IAM |

### 审计日志要求

```
必须记录的跨环境访问尝试：
  1. 所有被 Firewall 拒绝的流量（source, dest, port, timestamp）
  2. 所有跨 Project 的 IAM 访问尝试
  3. 所有跨 Project 的 API 调用
  4. 所有 Secret / KMS 解密尝试
  5. 所有 GCS 访问（尤其是跨 Project）

日志保留：
  → 至少 1 年（合规要求）
  → 建议 3 年
  → 使用 Cloud Log Storage + 生命周期管理
```

---

## 结论与建议

### 核心结论

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  1. "使用 PRD 网络基础设施" 和 "与 PRD 完全隔离"           │
│     是两个相互矛盾的目标。                                   │
│                                                             │
│  2. 正确的理解应该是：                                      │
│     → 复用网络架构设计（拓扑、规划）                        │
│     → 但使用独立的网络资源（VPC、Subnet、IP）               │
│                                                             │
│  3. 推荐方案：                                              │
│     → PLE 和 PRD 在不同 Project                             │
│     → 使用 Shared VPC Host 统一管理网络规划                 │
│     → 但 PLE 和 PRD 是不同 Service Project                 │
│     → 严格 Firewall + IAM 隔离                             │
│                                                             │
│  4. 绝对不应该：                                           │
│     → PLE 和 PRD 在同一 VPC                                 │
│     → PLE 使用 PRD 的 Service Account                      │
│     → PLE 访问 PRD 的存储/KMS/数据库                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 决策建议

```
┌─────────────────────────────────────────────────────────────┐
│  澄清问题清单（需要与业务/安全团队确认）                     │
│                                                             │
│  Q1: PLE 的目的是什么？                                     │
│      → 功能测试？性能测试？安全测试？用户培训？              │
│                                                             │
│  Q2: PLE 用户需要访问哪些 PRD 资源？                       │
│      → 如果需要访问任何 PRD 资源，PLE 就不是真正的隔离     │
│      → 如果需要读取 PRD 数据，是否有脱敏方案？              │
│                                                             │
│  Q3: PLE 是否需要"像 PRD"（用于 UAT）？                    │
│      → 如果需要，可能需要数据复制/模拟                      │
│      → 复制的是真实数据还是脱敏数据？                      │
│                                                             │
│  Q4: 合规要求是什么？                                      │
│      → 等保/PCI-DSS/SOC2 可能有硬性隔离要求                │
│      → 是否需要监管审计？                                   │
│                                                             │
│  Q5: PLE 的预算和运维责任是谁？                            │
│      → 独立团队管理？共享 SRE？                            │
│      → 成本如何分摊？                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 下一步行动

```
高优先级：
  [ ] 与安全团队确认隔离要求和合规标准
  [ ] 与业务团队确认 PLE 的使用场景和需求
  [ ] 评估是否可以接受 Project 级隔离（最安全）

中优先级：
  [ ] 设计 PLE 的 VPC/Subnet 规划（复用地址规划）
  [ ] 制定 Firewall 规则模板
  [ ] 设计 IAM 权限模型
  [ ] 规划日志和审计方案

低优先级：
  [ ] 如果需要跨 PLE/PRD 通信，设计 PSC 方案
  [ ] 设计 PLE 数据初始化方案（脱敏数据复制）
  [ ] 制定 PLE 运维流程
```

---

*Document version: 1.0 — Last updated: 2026-05-19*
