你帮我去探索 主题
在 Shared VPC 环境下 Internal HTTPS Load Balancer 跨项目绑定 Backend 的可行性确认
⸻
背景说明
我们正在 Google Cloud 上设计一个多租户架构，希望确认跨项目 Backend 绑定的官方支持方式。
当前架构
	•	Tenant 项目 主要是想要用户控制自己的入口 绑定自己对应的规则 比如说其对应的cloud armor 规则的改动，不会影响我们其他的用户也可以支持自己的独立机会 安全隐患分摊到tenant
	•	Internal HTTPS Load Balancer（INTERNAL_MANAGED）
	•	URL Map + Routing Rules
	•	Backend Service（归 Tenant 项目所有）
	•	Cloud Armor 绑定在 Backend Service 上
	•	TLS 证书在 Tenant 项目中管理
	•	Master 项目 这个也是我们平台方做一个核心来提供一些对应的GKE
	•	Managed Instance Group（MIG） GKE  neg
	•	运行 Compute Engine VM 工作负载 vm 通过一定的方式来暴露我们的GKE
	•	两个项目已挂载在同一个 Shared VPC（同一 Host Project + 同一 VPC）
⸻

目标架构

我们希望：
	•	保持 Internal HTTPS LB 和 Backend Service 在 Tenant 项目
                       我们已经实现了，通过修改tenant ilb 可以绑定到cross project到master的 backend service .当然虽然这个已经实现了， 我们也可以针对每个talent过来的用户创建自己对应的backend service 但是我可能还要评估一下对应的工程的授权情况要做安全评估，现在只是实现了访问
                        放在tenant好像必须得给tenant project的sa compuer.instanse的adm
	•	将 Tenant 项目的 Backend Service 绑定到 Master 项目中的 MIG 或者neg GKE
	•	Cloud Armor 依然在 Tenant 项目侧生效
	•	通过 Shared VPC 实现跨项目网络共享

希望确认的问题
	1.	在 Shared VPC 条件下，Backend Service（Project A）绑定 MIG（Project B）是否属于官方支持架构？
	2.	是否存在以下方面的限制或最佳实践：
	•	跨项目 IAM 权限要求
	•	Health Check 的归属和可见性
	•	Backend 生命周期管理影响
	•	Region 限制
	3.	在生产环境中是否存在已知风险或边界情况？
	4.	从 Google 推荐架构角度，是否更推荐：
	•	跨项目 MIG 绑定 以及该方案是否可行？
	•	跨项目 NEG 绑定以及该方案是否可行？
	•	或使用 Private Service Connect 实现更强隔离
如果这种方案可行的话，我们还需要考虑一下一些安全的设置，或者是对应工程授权的一些问题以及对应的一些计费原则，我们想对tenant的用户进行独立计费，也要考虑计费的方便性
我们希望在进入生产环境前确认该设计符合 Google Cloud 官方支持的架构模式。
所以我希望你至于上面的这个背景，我去探索一下是否能够实现
目前有两种架构实现方案可供评估：
方案一是将 Backend Server 部署在 Talent 项目中；方案二（即我当前的实现）是将 Backend Server 直接部署在 Master 项目下。方案 B 不是“共用一个 Backend Service”，而是“每个 Tenant 一个 Backend Service，但都在 Master 项目”。
除了安全性之外，我重点关注权限管控（Authorization）与计费架构（Billing）。
若采用全量部署在 Master 项目的方案，所有 Cloud Armor 的计费费用将由 Master 项目承担。且由于我需要在 Master 项目中创建多个不同的 Backend Server，各服务的计费维度也需要做进一步的拆分。


# Shared VPC 跨项目 Internal HTTPS LB 绑定 Backend 可行性分析

## 🔍 问题分析

核心问题是在 Shared VPC 环境下，评估两种架构方案的**可行性、权限模型、计费拆分**：

- **方案 A**：Backend Service 在 Tenant 项目，绑定 Master 项目的 MIG/NEG（跨项目 Backend 绑定）
- **方案 B**：Backend Service 在 Master 项目，每个 Tenant 独立一个 Backend Service（当前已实现）

---

## 🛠 可行性确认

### 方案 A：Backend Service（Tenant）→ MIG/NEG（Master）跨项目绑定

#### ✅ MIG 跨项目绑定

| 维度 | 结论 |
|------|------|
| 官方支持 | **有限支持**，需 Shared VPC 且满足 IAM 条件 |
| 网络层 | Shared VPC 同 VPC 网络下 **可达** |
| GCP API 层 | Backend Service 引用跨项目 MIG 需要显式 IAM 授权 |
| Health Check | **必须与 Backend Service 同项目**，或明确授权 |

**关键 IAM 授权要求（方案 A MIG）**：

```bash
# Tenant 项目的 Cloud Load Balancing Service Agent 需要访问 Master 项目的 MIG
# 在 Master 项目授权
gcloud projects add-iam-policy-binding <MASTER_PROJECT_ID> \
  --member="serviceAccount:service-<TENANT_PROJECT_NUMBER>@compute-system.iam.gserviceaccount.com" \
  --role="roles/compute.networkViewer"

# 同时需要授权访问 MIG
gcloud compute instance-groups managed add-iam-policy-binding <MIG_NAME> \
  --region=<REGION> \
  --member="serviceAccount:service-<TENANT_PROJECT_NUMBER>@compute-system.iam.gserviceaccount.com" \
  --role="roles/compute.viewer" \
  --project=<MASTER_PROJECT_ID>
```

#### ✅ NEG（GKE）跨项目绑定

| NEG 类型 | 跨项目支持 | 说明 |
|----------|-----------|------|
| Zonal NEG | ⚠️ 受限 | 需要 Shared VPC + 特定 IAM |
| Serverless NEG | ❌ 不支持跨项目 | 同项目限制 |
| Internet NEG | ❌ 不适用 | 外部场景 |
| **PSC NEG** | ✅ 推荐 | 通过 Private Service Connect 实现强隔离 |

---

### 方案 B：Backend Service 全在 Master 项目（当前实现）

```
✅ 完全官方支持，无跨项目 API 绑定问题
⚠️ 权限问题：Tenant 需要修改自己 ILB 的 URL Map 指向 Master 的 Backend Service
⚠️ 计费问题：Cloud Armor 费用全归 Master 项目
```

---

## 📊 两种方案架构对比

```mermaid
graph TD
    subgraph HostProject[Host Project - Shared VPC]
        VPC[Shared VPC Network]
    end

    subgraph TenantProject[Tenant Project]
        ILB["Internal HTTPS LB (INTERNAL_MANAGED)"]
        URLMap[URL Map]
        FwdRule[Forwarding Rule]
        CertA[TLS Certificate]
    end

    subgraph MasterProject[Master Project]
        GKE[GKE Cluster]
        NEG["Zonal NEG (GKE Pods)"]
        MIG["MIG (VM Workload)"]
    end

    subgraph SchemeA[方案A - Backend in Tenant]
        BS_A["Backend Service (Tenant Project)"]
        CA_A["Cloud Armor Policy (Tenant)"]
        HC_A["Health Check (Tenant)"]
    end

    subgraph SchemeB[方案B - Backend in Master]
        BS_B["Backend Service (Master Project)"]
        CA_B["Cloud Armor Policy (Master)"]
        HC_B["Health Check (Master)"]
    end

    FwdRule --> URLMap --> BS_A
    FwdRule --> URLMap
    BS_A -->|"跨项目绑定 IAM Required"| NEG
    BS_A --> CA_A
    BS_A --> HC_A

    URLMap -->|"方案B"| BS_B
    BS_B --> NEG
    BS_B --> CA_B
    BS_B --> HC_B

    NEG --> GKE
    MIG --> VPC
    GKE --> VPC
```

---

## 💳 计费架构分析

### 方案 A（Tenant 拥有 Backend Service）

| 费用项 | 归属 | 说明 |
|--------|------|------|
| ILB Forwarding Rule | Tenant 项目 | 按规则数计费 |
| Backend Service | Tenant 项目 | 免费资源对象 |
| **Cloud Armor** | **Tenant 项目** | ✅ 天然隔离，Tenant 自行承担 |
| 出站流量 | Shared VPC Host | 取决于流量路径 |
| Health Check | Tenant 项目 | 按探测次数计费 |

### 方案 B（Backend Service 全在 Master）

| 费用项 | 归属 | 问题 |
|--------|------|------|
| ILB Forwarding Rule | Tenant 项目 | ✅ 独立 |
| **Cloud Armor** | **Master 项目** | ❌ 无法直接拆分账单到 Tenant |
| Backend Service | Master 项目 | 混合在一起 |

**方案 B 计费拆分补救方案**：

```bash
# 通过 Labels 打标，再用 Billing Export 到 BigQuery 进行费用归因
gcloud compute backend-services update <BS_NAME_FOR_TENANT_X> \
  --global \
  --update-labels tenant=tenant-x,env=prod,cost-center=tenant-x-billing \
  --project=<MASTER_PROJECT_ID>

# BigQuery 查询示例（billing export 表）
# SELECT labels.value as tenant, SUM(cost) as total_cost
# FROM `billing_dataset.gcp_billing_export`
# WHERE labels.key = 'tenant'
# GROUP BY tenant
```

> ⚠️ Labels 计费拆分是 **软性拆分**，无法在 GCP Console 账单页直接体现到 Tenant 项目，需要通过 BigQuery Billing Export 二次分析。

---

## 🔐 权限管控（Authorization）关键差异

### 方案 A 权限矩阵

| 操作 | 执行方 | 所需权限 | 风险 |
|------|--------|----------|------|
| 修改 Cloud Armor | Tenant SA | `compute.securityPolicies.*`（Tenant 项目） | ✅ 低，租户自治 |
| 绑定跨项目 MIG | Tenant SA | `compute.instanceGroups.use`（Master 项目） | ⚠️ 需要精确授权 |
| 修改 Health Check | Tenant SA | `compute.healthChecks.*`（Tenant 项目） | ✅ 低 |
| 删除 Backend Service | Tenant SA | 需防止误删影响 LB | ⚠️ 需 OrgPolicy 保护 |

```bash
# 方案A：在 Master 项目给 Tenant SA 最小权限（仅允许 use MIG，不允许 delete）
gcloud projects add-iam-policy-binding <MASTER_PROJECT_ID> \
  --member="serviceAccount:<TENANT_SA>@<TENANT_PROJECT>.iam.gserviceaccount.com" \
  --role="roles/compute.viewer"

# 自定义 Role 仅授予 use 权限
gcloud iam roles create tenantMigUser \
  --project=<MASTER_PROJECT_ID> \
  --permissions="compute.instanceGroups.use,compute.instanceGroups.get"
```

### 方案 B 权限矩阵

| 操作 | 执行方 | 风险 |
|------|--------|------|
| 修改 Cloud Armor | Master SA / Platform Team | ❌ Tenant 无法自主修改，需通过平台接口 |
| 修改 URL Map | Tenant SA | ⚠️ 需授予 Tenant 对 Master 项目 URLMap 的写权限 |
| 隔离性 | — | ❌ 一个 SA 误操作可能影响多 Tenant |

---

## 📋 三种方案横向对比（含 PSC）

| 维度 | 方案A：跨项目 Backend | 方案B：Master 统一 Backend | 方案C：PSC 隔离 |
|------|----------------------|--------------------------|----------------|
| 官方支持度 | ⚠️ 有限支持，需 IAM 配置 | ✅ 完全支持 | ✅ 完全支持 |
| Cloud Armor 归属 | ✅ Tenant 独立 | ❌ Master 统一 | ✅ Tenant 独立 |
| 计费天然隔离 | ✅ 按项目自然隔离 | ❌ 需 Label + BigQuery | ✅ 按项目自然隔离 |
| Tenant 自治能力 | ✅ 高 | ⚠️ 低，依赖平台 | ✅ 高 |
| 实现复杂度 | ⚠️ 中（IAM 配置复杂） | ✅ 低（已实现） | ❌ 高（需 PSC 配置） |
| 网络安全隔离 | ⚠️ 中（同 VPC） | ⚠️ 中（同 VPC） | ✅ 强（服务边界隔离） |
| 跨项目 MIG 绑定 | ⚠️ 支持但非主流 | N/A | N/A |
| 跨项目 GKE NEG 绑定 | ⚠️ 受限 | N/A | ✅ via PSC NEG |

---

## ⚠️ 生产环境已知风险

### 方案 A 风险点

1. **Health Check 跨项目可见性**：Health Check 必须与 Backend Service **同项目**，无法直接探测跨项目 MIG 的私有 IP（需确认 Firewall 规则放行 `35.191.0.0/16` 和 `130.211.0.0/22` 到 Master 项目 VM）

```bash
# Master 项目必须放行 GCP Health Check 探针源 IP
gcloud compute firewall-rules create allow-health-check-from-tenant-lb \
  --network=<SHARED_VPC_NETWORK> \
  --action=ALLOW \
  --rules=tcp:<BACKEND_PORT> \
  --source-ranges=35.191.0.0/16,130.211.0.0/22 \
  --project=<MASTER_PROJECT_ID>
```

2. **跨项目 NEG 绑定 GKE**：GKE NEG 通常只能被**同项目**的 Backend Service 直接引用，跨项目引用需要通过 **PSC** 或者将 NEG 创建动作委托给 Master 项目

3. **Tenant SA 需要 `compute.instances.admin`**：你提到已发现这个问题，这个权限过大，应通过**自定义 Role** 缩小权限面

### 方案 B 风险点

1. Master 项目 SA 误操作影响范围扩大
2. Cloud Armor 规则变更需要平台团队介入，Tenant 自治性差
3. 计费无法在项目维度自然拆分

---

## 🏆 推荐结论

```
短期（已实现方案 B）：
  → 通过 Label + Billing Export BigQuery 实现软性计费拆分
  → 为每个 Tenant 的 Backend Service 统一打 tenant=xxx 标签
  → 用自定义 IAM Role 收紧 Tenant 对 Master 项目的操作权限

中期（演进到方案 A）：
  → 使用 Shared VPC + 跨项目 MIG 绑定（配合精确 IAM Custom Role）
  → Health Check 放在 Tenant 项目，Firewall 规则在 Master 项目放行
  → Cloud Armor 计费天然归 Tenant 项目

长期（规模化多租户）：
  → 考虑 Private Service Connect（PSC）
  → Master 项目发布 PSC Service Attachment
  → Tenant 项目通过 PSC NEG 接入，实现服务边界级隔离
  → 完全解耦两个项目的生命周期依赖
```

---

## 🔧 方案 A 落地最小 IAM 配置参考

```bash
# 1. 创建自定义 Role（Master 项目），仅允许 Tenant 引用 MIG/NEG，不允许删除
gcloud iam roles create crossProjectBackendUser \
  --project=<MASTER_PROJECT_ID> \
  --title="Cross Project Backend User" \
  --permissions="compute.instanceGroups.use,compute.instanceGroups.get,compute.networkEndpointGroups.use,compute.networkEndpointGroups.get,compute.instances.get"

# 2. 授权 Tenant 项目的 LB Service Agent
gcloud projects add-iam-policy-binding <MASTER_PROJECT_ID> \
  --member="serviceAccount:service-<TENANT_PROJECT_NUMBER>@compute-system.iam.gserviceaccount.com" \
  --role="projects/<MASTER_PROJECT_ID>/roles/crossProjectBackendUser"

# 3. 同时授权 compute.networkViewer 以便 LB 解析 Shared VPC 网络
gcloud projects add-iam-policy-binding <MASTER_PROJECT_ID> \
  --member="serviceAccount:service-<TENANT_PROJECT_NUMBER>@compute-system.iam.gserviceaccount.com" \
  --role="roles/compute.networkViewer"
```

---

**核心结论**：
- 方案 A（Tenant 拥有 Backend + 跨项目 MIG）**技术可行但 IAM 配置复杂**，Cloud Armor 和计费天然隔离，是长期推荐方向
- 方案 B（当前实现）**工程最简单**，但计费和权限隔离需要额外工程保障
- 如果你的核心诉求是 **Tenant 独立计费 + Cloud Armor 自治**，应优先推进方案 A 或 PSC 方案

# PSC 大规模多租户可行性分析与落地指南

## 🔍 问题分析

核心评估维度：
1. PSC 的网络/IP/Quota 限制
2. 100+ Tenant 连接单一 Master 的可行性
3. 具体落地操作步骤

---

## 📊 PSC 核心限制速查

### Quota & 规模限制

| 限制项 | 默认值 | 是否可申请提升 | 100 Tenant 影响 |
|--------|--------|---------------|----------------|
| PSC Endpoints per VPC | 20 | ✅ 可提升 | **每个 Tenant VPC 消耗 1 个** → 需确认每个 Tenant VPC 配额 |
| PSC Service Attachments per Region | 20 | ✅ 可提升 | **Master 侧消耗**，100 Tenant 共用 1 个 SA 即可 |
| NAT Subnets per Service Attachment | 10 | ✅ 可提升 | Master 侧 NAT 子网规划关键项 |
| Consumer Connections per Service Attachment | **250** | ✅ 可提升 | ✅ 100 Tenant 默认可满足 |
| Forwarding Rules per Project | 15（内部） | ✅ 可提升 | 每个 Tenant 消耗 1 个 PSC Endpoint（Forwarding Rule） |

> **关键结论**：100 Tenant 连接 1 个 Master PSC Service Attachment，**默认 Quota 250 Consumer Connections 已够用**，但需要关注每个 Tenant 项目的 Forwarding Rule 配额。

---

### IP 地址规划限制

```
PSC Endpoint（Consumer 侧）：
  - 每个 Tenant 项目需要 1 个 Internal IP（来自 Tenant 的子网）
  - IP 由 Tenant 自行管理，不消耗 Master 的 IP 空间
  - ✅ 完全独立，互不影响

PSC NAT Subnet（Producer/Master 侧）：
  - 需要专用 NAT 子网，与业务子网严格隔离
  - 每个 NAT 子网支持的并发连接数 = 子网 IP 数量 × 64000 端口
  - 推荐：/24 子网（254 IP × 64000 = ~1600 万并发连接）
  - ⚠️ NAT 子网不能用于其他 VM 或服务
```

**NAT Subnet 容量规划**：

| 子网大小 | 可用 IP | 最大并发连接 | 适用 Tenant 规模 |
|----------|---------|------------|----------------|
| /28 | 11 | ~700K | < 20 Tenant |
| /24 | 254 | ~16M | 100~500 Tenant ✅ |
| /22 | 1022 | ~65M | 1000+ Tenant |

---

## 📐 100 Tenant PSC 架构设计

```mermaid
graph TD
    subgraph MasterProject[Master Project]
        GKE[GKE Cluster]
        ILB_MASTER["Internal LB (ILB) - Producer"]
        SA["PSC Service Attachment\n(1个或按Region多个)"]
        NAT_SUBNET["NAT Subnet /24\n(专用，不可复用)"]
        AcceptList["Accept List\n(Tenant Project 白名单)"]
    end

    subgraph TenantA[Tenant A Project]
        EP_A["PSC Endpoint (Forwarding Rule)\nInternal IP: 10.1.0.5"]
        ILB_A["Internal HTTPS LB"]
        BS_A["Backend Service"]
        CA_A["Cloud Armor (Tenant A)"]
        PSC_NEG_A["PSC NEG\n指向 EP_A"]
    end

    subgraph TenantB[Tenant B Project]
        EP_B["PSC Endpoint (Forwarding Rule)\nInternal IP: 10.2.0.5"]
        ILB_B["Internal HTTPS LB"]
        BS_B["Backend Service"]
        CA_B["Cloud Armor (Tenant B)"]
        PSC_NEG_B["PSC NEG\n指向 EP_B"]
    end

    subgraph TenantN[Tenant N Project ...]
        EP_N["PSC Endpoint N"]
    end

    GKE --> ILB_MASTER
    ILB_MASTER --> SA
    SA --> NAT_SUBNET
    SA --> AcceptList

    EP_A -->|"PSC Connection"| SA
    EP_B -->|"PSC Connection"| SA
    EP_N -->|"PSC Connection"| SA

    ILB_A --> BS_A --> CA_A --> PSC_NEG_A --> EP_A
    ILB_B --> BS_B --> CA_B --> PSC_NEG_B --> EP_B
```

---

## 🛠 详细操作步骤

### Step 1：Master 项目 - 创建 NAT 专用子网

```bash
# NAT 子网必须专用，purpose=PRIVATE_SERVICE_CONNECT
gcloud compute networks subnets create psc-nat-subnet \
  --network=<SHARED_VPC_OR_MASTER_VPC> \
  --region=<REGION> \
  --range=10.100.0.0/24 \
  --purpose=PRIVATE_SERVICE_CONNECT \
  --project=<MASTER_PROJECT_ID>

# 验证
gcloud compute networks subnets describe psc-nat-subnet \
  --region=<REGION> \
  --project=<MASTER_PROJECT_ID> \
  --format="value(purpose)"
# 期望输出: PRIVATE_SERVICE_CONNECT
```

### Step 2：Master 项目 - 创建 Producer 侧 Internal LB

```bash
# 2.1 创建 Health Check
gcloud compute health-checks create http gke-backend-hc \
  --port=8080 \
  --request-path=/healthz \
  --region=<REGION> \
  --project=<MASTER_PROJECT_ID>

# 2.2 创建 Backend Service（指向 GKE NEG）
gcloud compute backend-services create gke-producer-bs \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --protocol=HTTP \
  --region=<REGION> \
  --health-checks=gke-backend-hc \
  --health-checks-region=<REGION> \
  --project=<MASTER_PROJECT_ID>

# 2.3 添加 GKE NEG 到 Backend Service
gcloud compute backend-services add-backend gke-producer-bs \
  --network-endpoint-group=<GKE_NEG_NAME> \
  --network-endpoint-group-zone=<ZONE> \
  --region=<REGION> \
  --project=<MASTER_PROJECT_ID>

# 2.4 创建 URL Map
gcloud compute url-maps create gke-producer-urlmap \
  --default-service=gke-producer-bs \
  --region=<REGION> \
  --project=<MASTER_PROJECT_ID>

# 2.5 创建 Target HTTP Proxy
gcloud compute target-http-proxies create gke-producer-proxy \
  --url-map=gke-producer-urlmap \
  --region=<REGION> \
  --project=<MASTER_PROJECT_ID>

# 2.6 创建 Forwarding Rule（ILB，仅内部，不暴露外部）
gcloud compute forwarding-rules create gke-producer-ilb \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --network=<VPC_NETWORK> \
  --subnet=<BACKEND_SUBNET> \
  --address=<RESERVED_INTERNAL_IP> \
  --region=<REGION> \
  --target-http-proxy=gke-producer-proxy \
  --target-http-proxy-region=<REGION> \
  --ports=80 \
  --project=<MASTER_PROJECT_ID>
```

### Step 3：Master 项目 - 创建 PSC Service Attachment

```bash
# 关键参数说明：
# --nat-subnets: 上面创建的专用 NAT 子网
# --connection-preference: ACCEPT_MANUAL 手动审批（推荐，安全可控）
# --consumer-accept-list: 预填写已知 Tenant 项目，后续可动态添加

gcloud compute service-attachments create gke-psc-service-attachment \
  --region=<REGION> \
  --producer-forwarding-rule=gke-producer-ilb \
  --connection-preference=ACCEPT_MANUAL \
  --nat-subnets=psc-nat-subnet \
  --consumer-accept-list=<TENANT_PROJECT_1>=10,<TENANT_PROJECT_2>=10 \
  --project=<MASTER_PROJECT_ID>

# 获取 Service Attachment URI（后续 Tenant 需要用到）
gcloud compute service-attachments describe gke-psc-service-attachment \
  --region=<REGION> \
  --project=<MASTER_PROJECT_ID> \
  --format="value(selfLink)"
# 输出示例: projects/master-project/regions/us-central1/serviceAttachments/gke-psc-service-attachment
```

### Step 4：动态添加新 Tenant 到白名单

```bash
# 每当新增一个 Tenant，执行此操作
TENANT_PROJECT_ID="new-tenant-project-id"

gcloud compute service-attachments update gke-psc-service-attachment \
  --region=<REGION> \
  --add-consumer-accept-list=${TENANT_PROJECT_ID}=10 \
  --project=<MASTER_PROJECT_ID>

# 查看当前 Accept List
gcloud compute service-attachments describe gke-psc-service-attachment \
  --region=<REGION> \
  --project=<MASTER_PROJECT_ID> \
  --format="json(consumerAcceptLists)"
```

### Step 5：Tenant 项目 - 创建 PSC Endpoint

```bash
# 在每个 Tenant 项目执行（可自动化/Terraform 模板化）
SA_URI="projects/<MASTER_PROJECT_ID>/regions/<REGION>/serviceAttachments/gke-psc-service-attachment"

# 5.1 预留内部 IP（PSC Endpoint IP）
gcloud compute addresses create psc-endpoint-ip \
  --region=<REGION> \
  --subnet=<TENANT_SUBNET> \
  --project=<TENANT_PROJECT_ID>

# 获取 IP
PSC_EP_IP=$(gcloud compute addresses describe psc-endpoint-ip \
  --region=<REGION> \
  --project=<TENANT_PROJECT_ID> \
  --format="value(address)")

# 5.2 创建 PSC Endpoint（Forwarding Rule 指向 SA）
gcloud compute forwarding-rules create psc-endpoint-to-master \
  --region=<REGION> \
  --network=<TENANT_VPC> \
  --address=psc-endpoint-ip \
  --target-service-attachment=${SA_URI} \
  --project=<TENANT_PROJECT_ID>

echo "PSC Endpoint IP: ${PSC_EP_IP}"
```

### Step 6：Master 项目 - 审批 PSC 连接请求

```bash
# 查看待审批的连接
gcloud compute service-attachments describe gke-psc-service-attachment \
  --region=<REGION> \
  --project=<MASTER_PROJECT_ID> \
  --format="json(connectedEndpoints)"

# 审批指定连接（取 connectedEndpoints 中的 pscConnectionId）
gcloud compute service-attachments accept-psc-connections \
  gke-psc-service-attachment \
  --region=<REGION> \
  --consumer-forwarding-rules=projects/<TENANT_PROJECT>/regions/<REGION>/forwardingRules/psc-endpoint-to-master \
  --project=<MASTER_PROJECT_ID>
```

### Step 7：Tenant 项目 - 创建 PSC NEG 并绑定到 Backend Service

```bash
# 7.1 创建 PSC NEG（指向 PSC Endpoint IP）
gcloud compute network-endpoint-groups create psc-neg \
  --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
  --psc-target-service=${SA_URI} \
  --network=<TENANT_VPC> \
  --subnet=<TENANT_SUBNET> \
  --region=<REGION> \
  --project=<TENANT_PROJECT_ID>

# 7.2 创建 Tenant 侧 Backend Service
gcloud compute backend-services create tenant-backend-service \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --protocol=HTTPS \
  --region=<REGION> \
  --no-health-checks \
  --project=<TENANT_PROJECT_ID>

# 7.3 添加 PSC NEG 到 Backend Service
gcloud compute backend-services add-backend tenant-backend-service \
  --network-endpoint-group=psc-neg \
  --network-endpoint-group-region=<REGION> \
  --region=<REGION> \
  --project=<TENANT_PROJECT_ID>

# 7.4 绑定 Cloud Armor（Tenant 自主管理）
gcloud compute backend-services update tenant-backend-service \
  --security-policy=<TENANT_CLOUD_ARMOR_POLICY> \
  --region=<REGION> \
  --project=<TENANT_PROJECT_ID>
```

---

## 🔄 完整连接流程

```mermaid
sequenceDiagram
    participant Client
    participant TenantILB as Tenant ILB + Cloud Armor
    participant TenantBS as Tenant Backend Service
    participant PSC_NEG as PSC NEG (Tenant)
    participant PSC_EP as PSC Endpoint IP
    participant SA as Service Attachment (Master)
    participant MasterILB as Master Internal LB
    participant GKE as GKE Backend

    Client->>TenantILB: HTTPS Request
    TenantILB->>TenantBS: 路由匹配
    TenantBS->>TenantBS: Cloud Armor 检查
    TenantBS->>PSC_NEG: 转发到 PSC NEG
    PSC_NEG->>PSC_EP: 内部 IP 解析
    PSC_EP->>SA: PSC Tunnel
    SA->>MasterILB: NAT 转换后到达 Master ILB
    MasterILB->>GKE: 转发到 GKE Pod
    GKE-->>Client: Response 原路返回
```

---

## 🤖 100 Tenant 自动化 Onboarding 脚本模板

```bash
#!/bin/bash
# onboard_tenant_psc.sh - 新 Tenant PSC 接入自动化

set -euo pipefail

MASTER_PROJECT="<MASTER_PROJECT_ID>"
REGION="<REGION>"
SA_NAME="gke-psc-service-attachment"
SA_URI="projects/${MASTER_PROJECT}/regions/${REGION}/serviceAttachments/${SA_NAME}"

TENANT_PROJECT="$1"
TENANT_VPC="$2"
TENANT_SUBNET="$3"

echo "=== [1/4] 添加 Tenant 到 PSC Accept List ==="
gcloud compute service-attachments update ${SA_NAME} \
  --region=${REGION} \
  --add-consumer-accept-list=${TENANT_PROJECT}=10 \
  --project=${MASTER_PROJECT}

echo "=== [2/4] Tenant 侧创建 PSC Endpoint ==="
gcloud compute addresses create psc-endpoint-ip \
  --region=${REGION} \
  --subnet=${TENANT_SUBNET} \
  --project=${TENANT_PROJECT}

gcloud compute forwarding-rules create psc-endpoint-to-master \
  --region=${REGION} \
  --network=${TENANT_VPC} \
  --address=psc-endpoint-ip \
  --target-service-attachment=${SA_URI} \
  --project=${TENANT_PROJECT}

echo "=== [3/4] 等待连接请求并自动审批 ==="
sleep 10
gcloud compute service-attachments accept-psc-connections ${SA_NAME} \
  --region=${REGION} \
  --consumer-forwarding-rules=projects/${TENANT_PROJECT}/regions/${REGION}/forwardingRules/psc-endpoint-to-master \
  --project=${MASTER_PROJECT}

echo "=== [4/4] Tenant 侧创建 PSC NEG + Backend Service ==="
gcloud compute network-endpoint-groups create psc-neg \
  --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
  --psc-target-service=${SA_URI} \
  --network=${TENANT_VPC} \
  --subnet=${TENANT_SUBNET} \
  --region=${REGION} \
  --project=${TENANT_PROJECT}

gcloud compute backend-services create tenant-backend-service \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --protocol=HTTPS \
  --region=${REGION} \
  --no-health-checks \
  --project=${TENANT_PROJECT}

gcloud compute backend-services add-backend tenant-backend-service \
  --network-endpoint-group=psc-neg \
  --network-endpoint-group-region=${REGION} \
  --region=${REGION} \
  --project=${TENANT_PROJECT}

echo "✅ Tenant ${TENANT_PROJECT} PSC 接入完成"
echo "   PSC Endpoint IP: $(gcloud compute addresses describe psc-endpoint-ip --region=${REGION} --project=${TENANT_PROJECT} --format='value(address)')"
```

---

## ⚠️ 注意事项与生产建议

### Quota 提前申请清单

```
Master 项目：
□ compute.serviceAttachments per region: 申请 10+（按 Region 多活需求）
□ NAT subnet IP 容量：确认 /24 满足并发需求

每个 Tenant 项目：
□ compute.forwardingRules（internal）: 默认 15，100+ Tenant 各自消耗 1 个，通常够用
□ compute.addresses（internal）: 默认 200，充足
```

### 安全加固

```bash
# 1. Service Attachment 使用 ACCEPT_MANUAL，禁止任意 Consumer 接入
# 2. 为每个 Tenant 设置独立的 connection limit（=10 防止滥用）
gcloud compute service-attachments update ${SA_NAME} \
  --region=${REGION} \
  --add-consumer-accept-list=${TENANT_PROJECT}=5 \  # 按需调整连接上限
  --project=${MASTER_PROJECT}

# 3. Master ILB 前置 Cloud Armor（平台级防护）
# 4. 开启 PSC 连接日志审计
gcloud compute service-attachments update ${SA_NAME} \
  --region=${REGION} \
  --enable-proxy-protocol \
  --project=${MASTER_PROJECT}
```

### 已知边界情况

| 问题 | 说明 |
|------|------|
| 跨 Region | PSC Endpoint 与 SA 必须**同 Region**，跨 Region 需在每个 Region 独立部署 SA |
| IPv6 | PSC 目前仅支持 IPv4 |
| UDP | PSC 不支持 UDP，仅 TCP |
| 连接断开重连 | PSC 连接建立后，Consumer 端 IP 固定，Master 侧扩缩容对 Consumer 透明 |
| Shared VPC Consumer | 若 Tenant 使用 Shared VPC，PSC Endpoint 需创建在 Host Project 的子网 |

---

**最终推荐**：100 Tenant 接入单一 Master PSC Service Attachment **完全可行**，默认 250 Consumer Connections 配额满足需求，核心工作在于 **NAT 子网 /24 规划** + **Tenant Onboarding 自动化脚本** + **提前申请 Quota**。


# studio



针对你在 Shared VPC 环境下进行多租户架构设计（Internal HTTPS LB 跨项目挂载后端）的疑问，基于 Google Cloud 官方最新的架构支持和网络限制，以下是深入的探索结果和可行性确认。

### 1. 核心问题确认：Backend Service（Project A）绑定 MIG/NEG（Project B）是否官方支持？

**结论：官方不支持这种架构方向。**

Google Cloud 官方文档中有明确的硬性限制：
> **“对于实例组 (MIG) 和可用区级 NEG (Zonal NEGs)，所有后端（Backend）都必须与后端服务 (Backend Service) 位于同一个项目和同一个区域中。”**

这意味着，如果你想将后端的 MIG 或 GKE NEG 放在 Master 项目，那么 **Backend Service 也必须强制建在 Master 项目**。因此，“方案一（将 Backend Service 放在 Tenant 项目中，直接指向 Master 的 MIG/NEG）”在底层 API 层面是无法实现的。

---

### 2. 方案二（当前实现方案）的评估与最佳实践

你当前实现的**方案二**（Frontend / URL Map 在 Tenant 项目 $\rightarrow$ Backend Service 在 Master 项目 $\rightarrow$ MIG 在 Master 项目），这在 GCP 中被称为 **Cross-project service referencing（跨项目服务引用）**。**这是官方完全支持并推荐的架构模式**。

如果你决定继续沿用此架构，以下是相关的最佳实践与限制：

*   **跨项目 IAM 权限管控（非常重要）**：
    你提到“放在 tenant 好像必须得给 tenant project 的 sa compute.instances.admin”。**这是不安全且不需要的**。
    在官方支持的“跨项目引用”中，你只需要赋予 Tenant 项目的负载均衡管理员/服务账号在目标 Backend Service（Master侧）上 **`roles/compute.loadBalancerServiceUser`（负载均衡器服务用户）** 的权限即可。这使得 Tenant 只能将流量路由到该 Backend Service，而绝对无法管理或重启 Master 项目的底层虚机和 GKE。
*   **Health Check 归属与可见性**：
    健康检查（Health Check）必须与 Backend Service 位于同一个项目（即 Master 项目）。这意味着 Tenant 侧无法在其 GCP Console 中直观地看到后端的健康状态，发生 `502 Bad Gateway` 时排障依赖平台方。
*   **生命周期管理限制**：
    Tenant 销毁其项目时，无法自动级联删除 Master 项目中的 Backend Service。Master 侧必须建立完善的自动化回收机制，防止僵尸 Backend Service 长期消耗配额。
*   **计费架构痛点**：
    如你所忧虑的，因为 **Cloud Armor 必须绑定在 Backend Service 上**，而 Backend Service 位于 Master 项目，这意味着**所有的 Cloud Armor 请求费用、DDoS 防护费用均会出在 Master 项目的账单上**。如果仅仅依赖 GCP 原始账单，无法做到多租户直接分账。

---

### 3. 从多租户隔离、授权与独立计费角度，推荐何种架构？

面对你希望**“租户独立管理 Cloud Armor 并自担费用”**以及**“高度网络和权限安全管控”**的需求，单纯的 Shared VPC 跨项目引用存在计费和耦合缺陷。

为此，**强烈推荐 Google Cloud 的 Private Service Connect (PSC) 架构模式。**

#### 推荐方案：基于 PSC 的多租户架构（Google 官方最推荐的 SaaS/多租户方案）
通过 Private Service Connect，你可以将 Master 中的 GKE 或 MIG 打包发布为一个“内部服务”，供各 Tenant 消费：

1.  **Master 项目（服务提供方）**：
    *   在 MIG/GKE 前面部署一个 Internal Load Balancer（充当发布层）。
    *   通过创建 **Service Attachment** 将这个服务暴露出来。此时不需要给任何 Tenant 授予底层 Compute 相关的 IAM 权限。
2.  **Tenant 项目（服务消费方）**：
    *   在 Tenant 项目中创建 **PSC NEG（Private Service Connect NEG）**。这个 NEG 直接指向 Master 项目的 Service Attachment。
    *   **关键点来了**：因为 PSC NEG 属于 Tenant 项目，所以 **Backend Service 就可以创建在 Tenant 项目中了！**
    *   Tenant 项目的完整链路：Tenant 自己的 ILB $\rightarrow$ Tenant 自己的 Backend Service $\rightarrow$ Tenant 自己的 Cloud Armor $\rightarrow$ Tenant 自己的 PSC NEG $\rightarrow$ (PSC 魔法隧道) $\rightarrow$ Master 项目的 GKE。

**采用 PSC 架构的核心优势：**
*   **完美解决计费痛点**：Backend Service 和 Cloud Armor 全部落在了 Tenant 项目内。GCP 原生就会将针对该入口的所有 Cloud Armor 防护费用、安全扫描费用和 Load Balancer 流量费用精准计入 Tenant 项目。
*   **权限管控做到极致（Zero IAM Crossing）**：Master 和 Tenant 之间不需要跨项目授予任何 IAM 角色（甚至不再依赖 Shared VPC）。Tenant 的故障或恶意操作完全被隔离在 Tenant 项目边界内，彻底消除了越权隐患。
*   **扩展性**：每个 Tenant 可以独立申请属于自己的 SSL 证书、自定义 URL Map 路由规则，随意修改属于自己的 WAF 拦截策略，而无需与 Master 平台方产生任何运维交集。

### 总结建议

如果你希望尽早进入生产环境且**预算允许一定的开发改造**：
请立刻评估并向 **Private Service Connect (PSC) NEG** 模式转型。这是唯一能满足“Cloud Armor 配置与计费完全下放给 Tenant”，同时“后端重负载完全归属 Master”的 Google Cloud 官方最佳实践。

如果你决定**维持现状的方案 B（Cross-project referencing）**：
1.  收回 Tenant 项目对 Master 项目高危的 `compute.instances.admin` 授权，改为使用最低权限策略的 `roles/compute.loadBalancerServiceUser`。
2.  为了解决计费问题，在通过 IaC（如 Terraform）为 Tenant 创建 Master 项目下的 Backend Service 时，必须打上 GCP 资源 Label（例如 `tenant: company-a`）。随后通过将 GCP 账单导出至 BigQuery，基于 Label 按资源维度进行二次成本摊派（Chargeback）。





针对你的问题，**结论是非常明确的：这不仅完全可行，而且是 Google Cloud 官方、以及各大 SaaS 厂商（如 Elastic, Databricks, MongoDB 等）在 GCP 上实现多租户互联的“事实标准”架构。**

面对 100 个甚至更多 Tenant 连接到 1 个 Master Project 的场景，Private Service Connect (PSC) 展现出了极强的伸缩性和架构优势。

以下是针对网络限制、IP 规划、配额（Quota）以及多租户扩展性的深入分析：

### 1. 核心网络与 IP 限制（极大简化了网络规划）

传统 VPC Peering 最大痛点是**不允许 IP 地址冲突**，如果有 100 个 Tenant，管理不重叠的 IP 网段简直是灾难。**PSC 完美解决了这个问题，它允许所有 Tenant 甚至使用完全相同的 IP 网段。**

*   **Master 侧的 IP 消耗（PSC NAT Subnet）：**
    *   在 Master 项目中创建 Service Attachment 时，你需要为其分配一个专用的 **PSC NAT 子网**。
    *   **消耗规则**：**1 个 Tenant 的 PSC NEG 连接，只占用 Master NAT 子网中的 1 个 IP 地址**。不论这个 Tenant 背后有多少百万级的并发请求，都只占 1 个 IP。
    *   **容量规划**：如果你规划一个 `/24` 的 PSC NAT 子网（可用 IP 约 252 个），就足以支撑 250 多个独立的 Tenant 项目连接。如果你有更多租户，分配一个 `/22` 即可支持上千个 Tenant。
*   **Tenant 侧的 IP 消耗：**
    *   Tenant 侧只需要正常的 IP 资源来部署他们自己的 Internal HTTPS LB，PSC NEG 本身几乎不额外占用复杂的路由 IP。

### 2. 核心 Quota (配额) 考量

Google Cloud 对 PSC 有默认配额，但对于“多对一”的架构，默认配额通常已经足够，且可以通过提交工单轻易提升：

*   **Master 侧配额（生产者）：**
    *   **Service Attachments 数量**：每个 Region 每个 Project 默认上限是 75 个。由于你所有的 100+ 个 Tenant 都会指向 **同一个（或少数几个）** Service Attachment，所以这个配额对你完全没有压力。
    *   **并发连接数**：单个 Producer VM（底层 Master 节点）可以接受来自单个 Tenant 的 64,512 个并发 TCP 连接。这对于绝大部分 HTTPS 流量已经绰绰有余。
*   **Tenant 侧配额（消费者）：**
    *   **PSC 转发规则/后端数 (Forwarding Rules / NEGs)**：每个 Tenant Project 每 Region 默认限额 75 个。由于每个 Tenant 只需要建 1 个 PSC NEG 指向 Master，因此也完全不会触碰限额。

### 3. 多租户架构下的控制与安全性（Consumer Accept List）

当你有 100+ 个外部 Tenant 时，如何防止恶意用户恶意连接你的 Master 服务？

*   **项目级白名单 (Project-based Accept List)**：Service Attachment 支持配置“消费者接受列表”。你可以精确配置**只允许指定的 Tenant Project IDs** 发起连接。
*   **连接数限制**：你可以在白名单中为每个 Tenant Project 设定连接数上限（例如：限制 Project A 只能建立 1 个 PSC 连接），防止单个租户耗尽你的 PSC NAT IP 资源。
*   **断开隔离**：如果某个 Tenant 欠费或者有违规操作，Master 平台方可以在 Service Attachment 的控制台中直接“Reject”该租户的连接，实现秒级物理隔离。

### 4. 架构实施中必须注意的“限制与盲区”

虽然该方案极其优秀，但在工程落地时，你需要注意以下几个技术边界：

**A. 真实客户端 IP 丢失问题 (SNAT 效应)**
*   **现象**：因为流量在进入 Master 项目时会经过 PSC NAT 子网的源地址转换 (SNAT)，Master 项目的 GKE/MIG 收到的所有请求，其 Source IP 都会变成 Master 侧 NAT 子网的内部 IP，而不再是 Tenant 用户的真实 IP。
*   **解决方案**：
    1. Tenant 侧的 Internal HTTPS LB 默认会在 HTTP Header 中自动注入 `X-Forwarded-For`。Master 侧的 GKE 业务代码直接读取该 Header 获取真实 IP 即可。
    2. 如果是纯四层 TCP 流量，Master 侧的内部负载均衡器必须开启 **PROXY Protocol** 功能来透传真实 IP。

**B. Region（区域）严格限制**
*   **限制**：PSC NEG 连接属于**区域级 (Regional)** 资源。Tenant 的 PSC NEG 与 Master 的 Service Attachment **必须在同一个 GCP Region**（例如都必须在 `asia-northeast1`）。
*   **应对**：如果你的 Master 服务部署在多区域，你需要在每个区域建立一个 Service Attachment。Tenant 可以在其全局负载均衡（Global External ALB）后挂载多个区域的 PSC NEGs，实现跨可用区高可用。

**C. Health Check（健康检查）的隔离可见性**
*   **限制**：在 PSC 架构中，Tenant 的 Backend Service **不支持**配置指向 Master 的直接 Health Check（因为跨越了信任边界）。
*   **应对**：Tenant 侧只需将请求盲转给 PSC NEG，实际的健康检查由 Master 项目自己的 Internal Load Balancer 在 Master 内部完成。如果 Master 服务完全宕机，Tenant 的 LB 会直接返回 `502 Bad Gateway`。

### 总结：是否可行？

**绝对可行，且是 Google 最推荐的方案。**

针对 100 个甚至几百个 Tenant：
1. **计费完美拆分**：Tenant 自己付他们 LB 和 Cloud Armor 的钱，独立出账单；Master 只付底层算力集群的钱。
2. **零权限交叉**：不再需要授予 Tenant 任何 Master 项目的 `compute` 权限，仅靠 Project ID 白名单完成握手。
3. **极简网络**：没有复杂的 VPC Peering 路由表，不用管 100 个 Tenant 的 IP 段是否互相冲突。

你目前的团队如果准备实施，只需在 Master 划出一个 `/24` 的 `purpose=PRIVATE_SERVICE_CONNECT` 子网，并通过 Terraform 为每个 Tenant 自动注册 Accept List 即可进入生产。

# Gemini

This is a classic "Platform vs. Tenant" architectural challenge. In a Shared VPC environment, Google Cloud provides several paths, but the choice between Cross-Project Backend Attachment and Private Service Connect (PSC) hinges on how much "trust" you have between the Master and Tenant projects.
As your Technical Partner, here is the architectural breakdown and feasibility confirmation.
1. Feasibility Confirmation
Is it officially supported?
Yes. In a Shared VPC environment, a Regional Internal HTTP(S) Load Balancer (Project A) can officially reference Backends (NEGs or MIGs) located in Project B, provided both projects are service projects attached to the same Shared VPC Host Project.
Implementation Logic
 * The Network context: Since both projects share the same VPC, the underlying IP reachability is native.
 * The Resource context: The Backend Service (in Tenant Project) points to the self_link of the NEG or MIG (in Master Project).
 * The Region constraint: The ILB, Backend Service, and the NEGs/MIGs must reside in the same GCP Region. Cross-region backend binding is not supported for Internal HTTPS LBs.
2. Architecture Comparison: Option A vs. Option B vs. PSC
Based on your requirements for independent billing and Tenant-level Cloud Armor, here is how the options stack up:
| Feature | Option A: Backend Service in Tenant (Your Current) | Option B: Backend Service in Master | Option C: Private Service Connect (Recommended) |
|---|---|---|---|
| Cloud Armor Policy | Owned by Tenant | Owned by Master (Hard to split) | Owned by Tenant |
| Billing (LB + WAF) | Tenant Project | Master Project | Tenant Project |
| IAM Complexity | High (Cross-project perms) | Low | Medium |
| Security Isolation | Network-level (Shared VPC) | Shared | Consumer-Provider Abstraction |
| Scalability | Good | Hard to manage at scale | Best (Cleanest handoff) |
Why Private Service Connect (PSC) might be your "North Star"
While your current cross-project binding works, PSC is the Google-recommended way for multi-tenant platforms.
 * Producer (Master): You create a "Service Attachment" pointing to your GKE internal load balancer.
 * Consumer (Tenant): The tenant creates a PSC NEG in their project.
 * Result: The Tenant’s ILB points to the PSC NEG. The Tenant pays for their own ILB and Cloud Armor. You (Master) only pay for the GKE resources. No cross-project IAM on MIGs/NEGs is required.
3. Deep Dive: Cross-Project IAM & Permissions
If you stick with Option A (Backend Service in Tenant), you must solve the "Permission Leakage" issue you mentioned.
Required Roles
To allow the Tenant Project to "see" and "use" the Master Project's backends:
 * LB Service Agent: The service-PROJECT_NUMBER@gcp-sa-compute.iam.gserviceaccount.com in the Tenant Project needs:
   * roles/compute.networkUser on the Shared VPC Host subnet.
   * roles/compute.loadBalancerServiceUser on the Master Project (to bind NEGs).
 * Automation/User Identity: The principal creating the Backend Service needs compute.instances.use or compute.networkEndpointGroups.use on the Master resources.
> Risk Warning: Giving a Tenant Project Service Account compute.instanceAdmin on the Master project is a critical security risk. You should use a custom role or strictly scoped compute.loadBalancerServiceUser to ensure the Tenant cannot delete or modify your GKE nodes.
> 
4. Billing & Cost Attribution
In Option A (Tenant-side ILB/Backend Service):
 * Load Balancing Fees: Charged to the Tenant Project.
 * Cloud Armor Fees: Charged to the Tenant Project.
 * Data Processing: Charged to the project where the LB is defined (Tenant).
 * Compute (GKE Nodes): Charged to the Master Project.
This aligns perfectly with your goal of independent billing for security and traffic-heavy features (WAF).
5. Summary & Recommendation
Which Backend type?
 * Use NEGs (Network Endpoint Groups): Since you are on GKE, standalone NEGs are superior to MIGs. They allow container-native load balancing (skipping the NodePort hop), reducing latency and simplifying health checks.
Final Verdict
 * Immediate Fix (Current Path): Continue with Cross-Project NEG binding. Refine IAM: Remove instanceAdmin and replace it with compute.loadBalancerServiceUser at the project level, or better, granted only on specific NEGs via IAM conditions.
 * Structural Improvement (Long-term): Move to Private Service Connect (PSC). It removes the need for the Tenant to have any direct IAM visibility into your Master Project. The interface becomes a "Service Attachment" URL.
Next Step
Would you like me to provide the Terraform/YAML manifest for setting up a PSC Service Attachment in the Master project and a PSC NEG in the Tenant project to see how that simplifies your security boundary?



# Cross-Project Backend Service 绑定 Master MIG 可行性分析

## 澄清你的架构意图

```mermaid
graph LR
    subgraph Tenant Project
        CA[Cloud Armor WAF]
        ILB[HTTPS ILB]
        BS[Backend Service]
        CA --> ILB --> BS
    end
    subgraph Master Project
        MIG[Managed Instance Group]
        GKE[GKE Nodes]
        MIG --> GKE
    end
    BS -->|Cross-Project 直接绑定?| MIG
```

---

## 结论：**不可行（硬限制）**

> GCP Backend Service **只能绑定同 Project 内的 Instance Group（MIG/UIG）**。  
> 这不是权限问题，是 GCP 资源引用模型的硬约束。

验证一下：
```bash
# 尝试跨 Project 添加 MIG 到 Backend Service 会直接报错
gcloud compute backend-services add-backend TENANT_BS \
    --instance-group=projects/MASTER_PROJECT/zones/ZONE/instanceGroups/master-mig \
    --project=TENANT_PROJECT_ID

# 报错：
# ERROR: Invalid value for field 'resource.backends[0].group':
# 'projects/MASTER_PROJECT/...' Backend must be in the same project
```

---

## 但你说的「Cross-Project Backend」是另一回事

```mermaid
graph LR
    subgraph Tenant Project
        ILB[HTTPS ILB Forwarding Rule]
        BS_T[Backend Service - Tenant 自己的]
    end
    subgraph Master Project
        BS_M[Backend Service - Master 的]
        MIG[MIG]
        BS_M --> MIG
    end
    ILB -->|routing rule cross-project| BS_M
    ILB --> BS_T
```

**GCP 支持的 Cross-Project 是：**  
ILB 的 **URL Map routing rule** 直接引用另一个 Project 的 **Backend Service**  
→ 但 Cloud Armor Policy 是绑在 **Tenant 自己的 Backend Service** 上的  
→ 流量走到 Master 的 Backend Service 时，**Cloud Armor 不会生效**

---

## 你的核心诉求 vs 实际限制

| 诉求 | 是否可行 |
|------|---------|
| Cloud Armor 在 Tenant Project | ✅ |
| Backend Service 在 Tenant Project | ✅ |
| Tenant BS 直接绑定 Master MIG | ❌ 硬限制 |
| ILB routing 到 Master BS（Cloud Armor 失效） | ✅ 但不满足 WAF 需求 |

---

## 真正可行的方案：Cross-Project NEG（非 MIG）

```mermaid
graph LR
    subgraph Tenant Project
        CA[Cloud Armor]
        ILB[HTTPS ILB]
        BS[Backend Service]
        CA --> BS
        ILB --> BS
    end
    subgraph Master Project
        NEG[Zonal NEG - 指向 GKE Pod/VM IP:Port]
        GKE[GKE Workload]
        NEG -.->|endpoint| GKE
    end
    BS -->|✅ 支持跨 Project| NEG
```

**关键区别：MIG 不能跨 Project，但 NEG 可以。**

```bash
# Master Project 创建 NEG
gcloud compute network-endpoint-groups create master-workload-neg \
    --network-endpoint-type=GCE_VM_IP_PORT \
    --zone=ZONE \
    --project=MASTER_PROJECT_ID

# 添加 GKE Node/Pod endpoints
gcloud compute network-endpoint-groups update master-workload-neg \
    --add-endpoint='instance=INSTANCE_NAME,ip=POD_IP,port=8080' \
    --zone=ZONE \
    --project=MASTER_PROJECT_ID

# Tenant Project Backend Service 绑定 Master NEG ✅
gcloud compute backend-services add-backend TENANT_BS \
    --network-endpoint-group=projects/MASTER_PROJECT_ID/zones/ZONE/networkEndpointGroups/master-workload-neg \
    --network-endpoint-group-zone=ZONE \
    --project=TENANT_PROJECT_ID \
    --global
```

---

## 如果你的 Master 必须用 MIG，唯一路径

```mermaid
graph LR
    subgraph Tenant Project
        CA[Cloud Armor]
        BS_T[Backend Service]
        CA --> BS_T
    end
    subgraph Master Project
        MIG[MIG]
        ILB_M[Internal LB - passthrough]
        MIG --> ILB_M
        NEG_PSC[PSC / ILB IP 作为 Serverless NEG]
    end
    BS_T -->|Internet NEG 或 PSC NEG| NEG_PSC
    NEG_PSC --> ILB_M
```

在 Tenant BS 里用 **Private Service Connect NEG** 或 **Hybrid NEG** 指向 Master 的 Internal LB IP，间接打通，Cloud Armor 依然在 Tenant 侧生效。

---

## 总结建议

**如果 Master 是 GKE** → 改用 Cross-Project Zonal NEG，完全满足你的需求  
**如果 Master 必须是 MIG** → PSC NEG 间接绑定，多一跳但 WAF 不受影响


# Cross-Project Zonal NEG 方案细化

## 前提条件确认

```mermaid
graph TD
    A[前提检查] --> B[Shared VPC 已配置]
    A --> C[Master GKE 集群已存在]
    A --> D[Tenant HTTPS ILB + Cloud Armor 已存在]
    B --> E{NEG 类型选择}
    E -->|GKE Pod 直连| F[GKE_VM_IP_PORT NEG]
    E -->|GKE Service 端口| G[Standalone Zonal NEG]
```

---

## 整体架构

```mermaid
graph LR
    subgraph Tenant Project
        CA[Cloud Armor Policy]
        BS[Backend Service]
        HC[Health Check]
        ILB[HTTPS ILB URL Map]
        FW_RULE[Forwarding Rule VIP]
        CA --> BS
        HC --> BS
        BS --> ILB
        ILB --> FW_RULE
    end

    subgraph Master Project
        NEG[Zonal NEG GKE_VM_IP_PORT]
        GKE_NODE[GKE Node VM]
        POD[Pod :8080]
        NEG -.->|endpoint: NodeIP:NodePort| GKE_NODE
        GKE_NODE --> POD
    end

    BS -->|Cross-Project NEG| NEG
    FW_RULE -->|Client Request| CA
```

---

## 详细实施步骤

### Step 1：Master Project - 准备 GKE Service 暴露方式

GKE 侧需要让流量可以通过 **NodePort** 或 **Pod IP 直连** 进来：

```yaml
# Master Project - K8s Service 使用 NodePort
apiVersion: v1
kind: Service
metadata:
  name: master-workload-svc
  namespace: default
spec:
  type: NodePort
  selector:
    app: master-workload
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080   # 固定 NodePort，便于 NEG 配置
```

```bash
kubectl apply -f service.yaml --context=MASTER_GKE_CONTEXT
```

---

### Step 2：Master Project - 创建 Standalone Zonal NEG

```bash
# 创建 NEG，网络指向 Shared VPC
gcloud compute network-endpoint-groups create master-gke-neg \
    --network-endpoint-type=GCE_VM_IP_PORT \
    --zone=asia-east1-b \
    --network=projects/HOST_PROJECT_ID/global/networks/SHARED_VPC_NAME \
    --subnetwork=projects/HOST_PROJECT_ID/regions/asia-east1/subnetworks/SUBNET_NAME \
    --project=MASTER_PROJECT_ID

# 查看 GKE Node 实例名
kubectl get nodes -o wide --context=MASTER_GKE_CONTEXT
# 记录 NODE_NAME 和 INTERNAL_IP

# 将 GKE Node 加入 NEG（NodePort 方式）
gcloud compute network-endpoint-groups update master-gke-neg \
    --add-endpoint='instance=GKE_NODE_INSTANCE_NAME,ip=NODE_INTERNAL_IP,port=30080' \
    --zone=asia-east1-b \
    --project=MASTER_PROJECT_ID

# 多节点全部加入
gcloud compute network-endpoint-groups update master-gke-neg \
    --add-endpoint='instance=GKE_NODE_2,ip=NODE_2_IP,port=30080' \
    --zone=asia-east1-b \
    --project=MASTER_PROJECT_ID
```

> ⚠️ GKE 节点 Auto Scaling 时，需要自动同步 NEG endpoints，见 Step 6。

---

### Step 3：IAM 授权 - Tenant 可以使用 Master NEG

```bash
# 方式一：精细化到具体 NEG 资源（推荐）
gcloud compute network-endpoint-groups add-iam-policy-binding master-gke-neg \
    --member="serviceAccount:TENANT_COMPUTE_SA@TENANT_PROJECT.iam.gserviceaccount.com" \
    --role="roles/compute.networkEndpointGroupAdmin" \
    --zone=asia-east1-b \
    --project=MASTER_PROJECT_ID

# 方式二：Project 级别（权限较大，不推荐生产）
gcloud projects add-iam-policy-binding MASTER_PROJECT_ID \
    --member="serviceAccount:TENANT_COMPUTE_SA@TENANT_PROJECT.iam.gserviceaccount.com" \
    --role="roles/compute.networkViewer"
```

---

### Step 4：Tenant Project - Backend Service 绑定 Master NEG

```bash
# 4.1 创建 Health Check（在 Tenant Project，探测 Master GKE NodePort）
gcloud compute health-checks create http master-neg-hc \
    --port=30080 \
    --request-path=/healthz \
    --check-interval=10s \
    --timeout=5s \
    --healthy-threshold=2 \
    --unhealthy-threshold=3 \
    --project=TENANT_PROJECT_ID \
    --global

# 4.2 创建 Backend Service 并绑定 Cloud Armor
gcloud compute backend-services create tenant-bs-master \
    --protocol=HTTP \
    --health-checks=master-neg-hc \
    --security-policy=YOUR_CLOUD_ARMOR_POLICY \
    --global \
    --project=TENANT_PROJECT_ID

# 4.3 绑定 Master Project 的 NEG ✅
gcloud compute backend-services add-backend tenant-bs-master \
    --network-endpoint-group=projects/MASTER_PROJECT_ID/zones/asia-east1-b/networkEndpointGroups/master-gke-neg \
    --network-endpoint-group-zone=asia-east1-b \
    --balancing-mode=RATE \
    --max-rate-per-endpoint=100 \
    --global \
    --project=TENANT_PROJECT_ID
```

---

### Step 5：防火墙规则 - 允许 Health Check 和流量进入 Master GKE

```bash
# Health Check 源 IP 范围（GCP 固定）
gcloud compute firewall-rules create allow-tenant-hc-to-master-gke \
    --network=SHARED_VPC_NAME \
    --allow=tcp:30080 \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=gke-MASTER_CLUSTER_NAME-node \
    --project=HOST_PROJECT_ID \   # 防火墙规则在 Host Project
    --description="Allow GCP HC to Master GKE NodePort"

# 允许 ILB Proxy 子网流量到 Master GKE
gcloud compute firewall-rules create allow-tenant-ilb-to-master-gke \
    --network=SHARED_VPC_NAME \
    --allow=tcp:30080 \
    --source-ranges=PROXY_SUBNET_CIDR \
    --target-tags=gke-MASTER_CLUSTER_NAME-node \
    --project=HOST_PROJECT_ID
```

---

### Step 6：Node 动态扩缩容时 NEG 自动同步

GKE 节点变化时需要自动更新 NEG，推荐使用 **GKE + Custom Controller** 或脚本：

```bash
# 方案：GKE Node 加 label，配合 DaemonSet 自注册（简化版用脚本）
# 监听 GKE Node 变化，自动 add/remove NEG endpoint

#!/bin/bash
# sync-neg-endpoints.sh

ZONE="asia-east1-b"
NEG_NAME="master-gke-neg"
MASTER_PROJECT="MASTER_PROJECT_ID"
NODE_PORT="30080"

# 获取当前所有 Ready Node
CURRENT_NODES=$(kubectl get nodes --context=MASTER_GKE_CONTEXT \
    -o jsonpath='{range .items[*]}{.metadata.name},{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')

# 获取当前 NEG 中的 endpoints
CURRENT_NEG=$(gcloud compute network-endpoint-groups list-network-endpoints $NEG_NAME \
    --zone=$ZONE --project=$MASTER_PROJECT \
    --format="value(networkEndpoint.instance,networkEndpoint.ipAddress)")

echo "$CURRENT_NODES" | while IFS=',' read -r name ip; do
    gcloud compute network-endpoint-groups update $NEG_NAME \
        --add-endpoint="instance=$name,ip=$ip,port=$NODE_PORT" \
        --zone=$ZONE \
        --project=$MASTER_PROJECT 2>/dev/null
done
```

> 💡 **更优方案**：使用 GKE Ingress with Container-native Load Balancing，GKE 会自动管理 NEG endpoints，但这需要 GKE 侧也做对应配置。

---

## 完整流量路径验证

```mermaid
sequenceDiagram
    participant Client
    participant FWD as Forwarding Rule (Tenant VIP)
    participant PROXY as Envoy Proxy (Tenant)
    participant CA as Cloud Armor (Tenant)
    participant BS as Backend Service (Tenant)
    participant NEG as Zonal NEG (Master)
    participant NODE as GKE Node (Master)
    participant POD as Pod (Master)

    Client->>FWD: HTTPS Request
    FWD->>PROXY: TLS Termination
    PROXY->>CA: WAF 检查
    CA-->>PROXY: Allow/Deny
    PROXY->>BS: 转发请求
    BS->>NEG: 选择 Endpoint
    NEG->>NODE: NodeIP:NodePort
    NODE->>POD: kube-proxy 转发
    POD-->>Client: Response
```

---

## 关键注意事项

| 项目 | 注意点 |
|------|--------|
| NEG 与 GKE 同 Zone | NEG 必须在 GKE Node 相同的 Zone，多 Zone 需创建多个 NEG |
| Health Check 端口 | 需要与 NodePort 一致，且防火墙放通 HC 源 IP |
| GKE Node Autoscaler | 节点扩缩容需要同步更新 NEG endpoints |
| Shared VPC 子网 | NEG 创建时必须指定 Shared VPC 的 subnet |
| Cloud Armor 生效位置 | 绑定在 Tenant BS 上，在流量进入 NEG 之前已生效 ✅ |
| 多 Zone 高可用 | 每个 Zone 创建独立 NEG，BS 绑定所有 Zone 的 NEG |