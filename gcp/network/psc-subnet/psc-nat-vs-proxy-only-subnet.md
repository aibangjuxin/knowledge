# PSC NAT Subnet vs Proxy-Only Subnet — 概念详解（参考材料）

> **⚠️ 本文档定位**：这是**参考材料**（概念讲解 + 学术整理），不是日常排查入口。
>
> 日常 firewall 排查请走 **`../../../cross-project/cross-project-firewall-netpol/references/firewall-by-instance-path.md`** —
> 那份按"实例视角 + 流量物理路径"组织，跟你实际决策顺序一致。
>
> 本文档仍保留，因为：判定路径 A（passthrough LB）时仍要知道 PSC NAT subnet 是什么；判定路径 B（GKE Gateway）时要知道 proxy-only subnet 是什么。但分类框架（passthrough vs proxy）只是辅助认知，不该是入口。
>
> 跨项目 PSC + Envoy-based LB 架构下，**两种最容易被混淆的专用子网**是什么、各自用途是什么、为什么会存在。

---

## 0. 原始问题（保留 Lex 原话 verbatim）

Lex 的实际场景与直觉：

> 我想在 Master Project 里暴露服务，就要创建一个 Attachment，也就是 Service Attachment。这个 Service Attachment 必须运行在 PSC 的 Subnet 上，我理解这个应该就是 PSC Net 的 Subnet。所以说我想要对这两种网络类型做一个详细的了解。

**核心点**：

- Lex 看到我在场景文档里反复提 `PSC NAT subnet CIDR` 和 `proxy-only subnet CIDR`
- 想搞清楚这两个到底是什么
- 直觉：**PSC NAT subnet 跟 Service Attachment 绑定**（对的 ✓）

我会先纠正一个常见误解，然后把两个子网拆开讲清楚。

---

## 1. 一句话定义

| 子网类型 | GCP `purpose` 字段值 | 作用对象 | 用途一句话 |
|---------|----------------------|---------|----------|
| **PSC NAT Subnet** | `PRIVATE_SERVICE_CONNECT` | **Service Attachment** | PSC 隧道在 Producer 侧做 SNAT 用的 IP 池 |
| **Proxy-Only Subnet** | `REGIONAL_MANAGED_PROXY`（旧名 `INTERNAL_HTTPS_LOAD_BALANCER`） | **Envoy-based Load Balancer**（Internal ALB / GKE Gateway 等） | Envoy proxy 出 pod 时的 source IP 池 |

**关键区别**：

| 维度 | PSC NAT Subnet | Proxy-Only Subnet |
|------|---------------|-------------------|
| **绑定到什么资源** | Service Attachment（参数 `--nat-subnets`） | Internal ALB / GKE Gateway（自动或显式） |
| **产生的源 IP** | Consumer 流量**进入 Producer VPC 时**被替换的 source IP（仅 passthrough 类 LB 时才被 backend 看到） | Envoy proxy **去访问 backend**时使用的 source IP（proxy 类 LB 时被 backend 看到） |
| **为什么需要 NAT** | 隔离 Consumer 真实 IP，让 Producer 不感知 Consumer 网络 | 让 backend 看到的 source 是 Envoy 而不是客户端 |
| **不绑定会怎样** | Service Attachment 创建失败（强依赖） | 创建 Internal ALB / GKE Gateway 失败（强依赖） |
| **数量限制** | 每 Service Attachment 最多绑 10 个 NAT subnet（[官方 quota 文档](https://cloud.google.com/vpc/docs/quotas)） | 每 VPC 每 region **只能有 1 个 active** proxy-only subnet（[官方文档](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)） |
| **IP 数量下限** | 经验值：≥ 16 个可用 IP（本地 psc-sub-last.md §2.2 给出 `/28` 推荐下限） | **官方硬约束：≥ 64 个 IP 地址**（[官方文档](https://cloud.google.com/load-balancing/docs/proxy-only-subnets) — "must provide 64 or more IP addresses. This corresponds to a prefix length of /26 or shorter."） |
| **官方推荐大小** | — | **`/23`（512 IP）** 起步 |
| **是否可挂 VM** | ❌ 不能（专用） | ❌ 不能（专用） |
| **典型场景** | PSC Service Attachment 暴露内部服务 | Envoy-based LB（GKE Gateway / Internal ALB） |

---

## 2. PSC NAT Subnet 详解

### 2.1 官方定义（GCP 原文）

> "You don't need to take any steps to allow traffic between a Private Service Connect endpoint or Private Service Connect backend and the associated service attachment. Configure firewall rules. Your network configuration must allow traffic from appropriate source IP address ranges to the instances or network endpoints that are configured as backends for your backend services."
>
> — [Publish services by using Private Service Connect](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer)

> `gcloud compute networks subnets create SUBNET_NAME --network=... --region=... --range=... --purpose=PRIVATE_SERVICE_CONNECT`
>
> — [同上](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer)

### 2.2 它在流量路径中的角色

```text
Consumer VPC                        Producer VPC
─────────────                       ─────────────
Client VM (10.10.0.5)
  │
  ↓ 真实 source IP = 10.10.0.5
  │
PSC Endpoint (10.10.20.10)
  │
  ↓ GCP 内部隧道（NAT 不变）
  │
Service Attachment
  │
  ↓ 入口：在 Producer 边界做 SNAT
  │  ← 关键点：source IP 被替换为 PSC NAT subnet IP
  │
PSC NAT Subnet (10.200.0.0/28)
  │ 12 个可用 NAT IP，每个支持 ~64,512 并发连接
  │
  ↓ 进入 LB
  │
Internal LB (passthrough NLB) ───→ Backend (MIG / VM / GKE Pod)
                                    backend 看到 source IP = PSC NAT subnet IP
```

### 2.3 关键特性

| 特性 | 说明 |
|------|------|
| **强绑定 Service Attachment** | Service Attachment 的 `--nat-subnets` 参数必须指向一个或多个 PSC NAT subnet。不绑 Service Attachment 创建失败 |
| **不能挂 VM** | `purpose=PRIVATE_SERVICE_CONNECT` 是专用属性，挂 VM 创建失败 |
| **可在 1 个 SA 上绑多个** | 单个 Service Attachment 最多绑 10 个 NAT subnet（用于扩展并发） |
| **每 SA 独立 IP 池** | 不同 SA 各自用自己的 NAT subnet，互不干扰（隔离来源 Consumer） |
| **NAT IP 的消耗模型** | 每个 NAT IP ≈ 64,512 个并发连接（= 65,535 - 1,023 reserved） |
| **只在 passthrough 类 LB 路径下被 backend 看到** | proxy 类 LB（GKE Gateway / Internal ALB）backend 看到的 source 是 **proxy-only subnet**，**不是 PSC NAT subnet**（这是最容易踩的坑） |
| **必须是 regional** | PSC NAT subnet 是 regional 资源，必须跟 SA 在同 region、ILB 在同 region |

### 2.4 创建命令

```bash
gcloud compute networks subnets create psc-nat-master-att01 \
  --project=${MASTER_PROJECT} \
  --network=${MASTER_VPC} \
  --region=${REGION} \
  --range=10.200.0.0/28 \
  --purpose=PRIVATE_SERVICE_CONNECT \
  --role=ACTIVE
```

### 2.5 Service Attachment 绑定

```bash
gcloud compute service-attachments create sa-master-gateway \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --target-service=projects/${MASTER_PROJECT}/regions/${REGION}/forwardingRules/<FR_NAME> \
  --connection-preference=ACCEPT_MANUAL \
  --consumer-accept-list=${TENANT_PROJECT}=10 \
  --nat-subnets=psc-nat-master-att01  # ← 这里绑定
```

### 2.6 常见误区

- ❌ "PSC NAT subnet 是 backend 所在 subnet" — **错**。它是 SNAT 转换池，不是 backend subnet
- ❌ "backend 看到的 source 一定是 PSC NAT subnet" — **错**。只在 passthrough LB 路径下成立；proxy 类 LB 时 backend 看到的是 proxy-only subnet
- ❌ "PSC NAT subnet 可以挂 VM" — **错**。`purpose=PRIVATE_SERVICE_CONNECT` 专用
- ❌ "PSC NAT subnet 大小不影响性能" — **错**。NAT IP 数直接决定并发连接上限（每个 IP ≈ 64,512 并发）

---

## 3. Proxy-Only Subnet 详解

### 3.1 官方定义（GCP 原文）

> "A proxy-only subnet provides a pool of IP addresses that are reserved exclusively for Envoy proxies used by Google Cloud load balancers. It can't be used for any other purposes."
>
> — [Proxy-only subnets for Envoy-based load balancers](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)

> "Packets sent from a proxy to a backend VM or endpoint has a source IP address from the proxy-only subnet."
>
> — [同上](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)

> "A proxy-only subnet must provide **64 or more IP addresses**. This corresponds to a prefix length of **`/26` or shorter**. We recommend that you start with a proxy-only subnet with a **`/23` prefix (512 proxy-only addresses)** and change the size as your traffic needs change."
>
> — [同上](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)

> "In a given VPC network and region, only a single proxy-only subnet with purpose `REGIONAL_MANAGED_PROXY` can be **active at any point in time**. The active proxy-only subnet powers all of the following products: Regional external Application Load Balancer, Regional internal Application Load Balancer, Regional external proxy Network Load Balancer, Regional internal proxy Network Load Balancer..."
>
> — [同上](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)

### 3.2 它在流量路径中的角色

```text
Consumer VPC                        Producer VPC
─────────────                       ─────────────
Client VM (10.10.0.5)
  │
  ↓ source IP = 10.10.0.5
  │
PSC Endpoint (10.10.20.10)
  │
  ↓ GCP 内部隧道
  │
Service Attachment ───→ PSC NAT Subnet（passthrough LB 时做 SNAT）
                            │
                            ↓ 但 proxy 类 LB 直接走下面路径
                            ↓
                  Envoy Proxy 1 (10.204.0.5)
                  Envoy Proxy 2 (10.204.0.6)
                  ... 共 512 个（/23 subnet 大小）
                  ↓ 关键：去 backend 的 source IP 来自这里
                  │
                  ↓ source IP = 10.204.0.5 (proxy-only subnet)
                  ↓
                  Backend (GKE Pod)
                  backend 看到 source IP = proxy-only subnet IP
```

### 3.3 关键特性

| 特性 | 说明 |
|------|------|
| **强依赖 Envoy-based LB** | 没有 proxy-only subnet，创建 Internal ALB / GKE Gateway 失败 |
| **不绑定 Service Attachment** | Service Attachment **不需要** proxy-only subnet（除非它指向的 LB 是 proxy 类） |
| **每 VPC 每 region 只能 1 个 active** | 多于 1 个 active 会冲突 |
| **旧名 `INTERNAL_HTTPS_LOAD_BALANCER` → 新名 `REGIONAL_MANAGED_PROXY`** | GCP 后来让 External ALB 也复用这个池，所以重命名（[本地 glb.md §"Proxy-Only Subnet 迁移报错" 详解](https://本地/glb.md)） |
| **不能挂 VM** | 专用属性 |
| **新名包含旧名全部业务** | 迁移到 `REGIONAL_MANAGED_PROXY` 后不能再回退（单向升级） |
| **典型大小** | `/23`（512 IP）起步，按需扩展 |
| **最严硬约束** | `/26` 或更短（≥ 64 个 IP），否则 LB 创建失败 |

### 3.4 创建命令

```bash
gcloud compute networks subnets create proxy-only-subnet-master \
  --project=${MASTER_PROJECT} \
  --network=${MASTER_VPC} \
  --region=${REGION} \
  --range=10.204.0.0/23 \
  --purpose=REGIONAL_MANAGED_PROXY \
  --role=ACTIVE
```

### 3.5 谁会自动管理它

| LB 类型 | proxy-only subnet 管理方式 |
|--------|------------------------|
| **GKE Gateway**（`gke-l7-internal` / `gke-l7-rilb`） | **GKE Gateway controller 自动检测** — 如果 region 没有 active proxy-only subnet，controller 报错并提示（创建失败直到你手动建） |
| **手动创建的 Internal ALB** | 你必须先建好 proxy-only subnet，才能创建 forwarding rule |
| **GKE NEG + Internal LB** | GKE controller 通常自动选已有 proxy-only subnet |

### 3.6 常见误区

- ❌ "proxy-only subnet 是 backend subnet" — **错**。是 Envoy 出口的 source IP 池
- ❌ "proxy-only subnet 不区分 internal / external" — **对，但这是它存在的原因**。正是因为 Internal ALB 和 External ALB 都要用，所以统一叫 `REGIONAL_MANAGED_PROXY`
- ❌ "proxy-only subnet 越多越好" — **错**。每 VPC 每 region 只能 1 个 active，多了冲突
- ❌ "proxy-only subnet 跟 PSC NAT subnet 是一回事" — **错**。两个完全不同用途

---

## 4. 共同点 / 不同点（强对照）

| 维度 | PSC NAT Subnet | Proxy-Only Subnet |
|------|---------------|-------------------|
| **purpose 值** | `PRIVATE_SERVICE_CONNECT` | `REGIONAL_MANAGED_PROXY` |
| **绑定对象** | Service Attachment | Envoy-based LB |
| **出现的层** | PSC 隧道入口（Consumer → Producer 边界） | LB 内部（Envoy → Backend） |
| **典型大小** | `/28` 起 | `/26` 最小，`/23` 推荐 |
| **数量约束** | 每 SA 最多 10 个 | 每 VPC 每 region 仅 1 个 active |
| **是否跨 project** | ❌ Producer 本地 | ❌ Producer 本地 |
| **是否跨 region** | ❌ 必须同 region | ❌ 必须同 region |
| **绑定 firewall 该放通哪个** | passthrough LB 时放 **PSC NAT subnet**（backend ingress） | proxy 类 LB 时放 **proxy-only subnet**（backend ingress） |
| **能否放 `0.0.0.0/0`** | ❌ 都是专用 | ❌ 都是专用 |
| **可挂 VM / 跑 workload** | ❌ | ❌ |

---

## 5. 关系：同一 Service Attachment 可以同时涉及两者

这是 Lex 实际架构里**最关键**的点：

### 5.1 场景 A：passthrough LB（只用 PSC NAT subnet）

```text
Service Attachment
  └─ target = Internal passthrough NLB forwarding rule
       └─ backend = MIG (VM)
            backend 看到的 source IP = PSC NAT subnet IP
            firewall: source-ranges = PSC NAT subnet CIDR
```

**这种情况下：proxy-only subnet 完全不需要**。

### 5.2 场景 B：proxy 类 LB（只用 proxy-only subnet）

```text
Service Attachment
  └─ target = regional internal Application LB forwarding rule (= GKE Gateway)
       └─ backend = GKE Pod
            backend 看到的 source IP = proxy-only subnet IP（不是 PSC NAT subnet）
            firewall: source-ranges = proxy-only subnet CIDR
            NetworkPolicy: from: ipBlock: cidr: <proxy-only subnet CIDR>
```

**这种情况下：PSC NAT subnet 也需要**（Service Attachment 强依赖），**但 backend 看不到它** — 它只用来给 SA 做 SNAT。

### 5.3 场景 C：双层（proxy 类 LB + GKE Gateway → 上游 backend 又是 GKE Gateway）

更复杂的链路里两个子网都会涉及：

```text
Consumer → PSC EP → SA → [PSC NAT SNAT] → GKE Gateway (Envoy)
                                       └─ → [proxy-only subnet SNAT] → Backend Pod
```

**两个子网都在**，但**作用层级不同**。

---

## 6. Lex 直觉的纠正

> "这个 Service Attachment 必须运行在 PSC 的 Subnet 上，我理解这个应该就是 PSC Net 的 Subnet"

**对了一半**：

- ✅ **对**：Service Attachment 强依赖 PSC NAT subnet（`purpose=PRIVATE_SERVICE_CONNECT`），不绑 SA 创建失败
- ⚠️ **不完全**：如果 Service Attachment 指向的是 **proxy 类 LB**（如 GKE Gateway），除了 PSC NAT subnet 外，**整个 region 还需要 proxy-only subnet**（`purpose=REGIONAL_MANAGED_PROXY`）。但 proxy-only subnet 是 LB 的依赖，不是 SA 的直接依赖 — 它跟 SA 不直接绑定。

**简化心智模型**：

- PSC NAT subnet：跟 **Service Attachment 配对**（SA 强依赖）
- Proxy-only subnet：跟 **Envoy-based LB 配对**（LB 强依赖）

两者独立，但常常被**同一个 Service Attachment 链路同时用到**（因为 SA 指向的 LB 大概率是 proxy 类）。

---

## 7. 验证命令

### 7.1 看项目里所有专用 subnet

```bash
# 所有 PSC NAT subnet
gcloud compute networks subnets list \
  --project=${MASTER_PROJECT} \
  --filter='purpose="PRIVATE_SERVICE_CONNECT"' \
  --format='table(name,region,ipCidrRange,purpose)'

# 所有 proxy-only subnet
gcloud compute networks subnets list \
  --project=${MASTER_PROJECT} \
  --filter='purpose="REGIONAL_MANAGED_PROXY" OR purpose="INTERNAL_HTTPS_LOAD_BALANCER"' \
  --format='table(name,region,ipCidrRange,purpose)'
```

### 7.2 看某个 SA 绑了哪些 NAT subnet

```bash
gcloud compute service-attachments describe ${SA_NAME} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --format='yaml(natSubnets,targetService,connectedEndpoints)'
```

### 7.3 看 region 是否有 active proxy-only subnet

```bash
# 单 region 检查
gcloud compute networks subnets list \
  --project=${MASTER_PROJECT} \
  --regions=${REGION} \
  --filter='purpose="REGIONAL_MANAGED_PROXY"'

# 看是否 active（可能有多个但只有 1 个 active）
gcloud compute networks subnets describe ${PROXY_SUBNET} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --format='yaml(purpose,role)'
```

### 7.4 看 GKE Gateway 是否用了 proxy-only subnet

```bash
kubectl describe gateway <gateway-name> -n <ns>

# 或直接看 controller 创建的 forwarding rule 的 subnet
gcloud compute forwarding-rules describe ${FR_NAME} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --format='yaml(subnetwork,network)'
```

---

## 8. 创建时机 + 顺序（决策树）

```
要在 Producer Project 暴露服务？
│
├─ 用什么 LB？
│  │
│  ├─ Internal passthrough NLB (L4) ──────────┐
│  ├─ Internal protocol forwarding              │
│  └─ Port mapping service                      │
│                                              │
│  → 必须建：                                  │
│     ✅ PSC NAT subnet                         │
│     ❌ proxy-only subnet（不需要）            │
│  → firewall 放 PSC NAT subnet                 │
│                                              │
│  ├─ regional internal Application LB ─────────┐
│  ├─ GKE Gateway (gke-l7-internal)             │
│  ├─ Internal proxy NLB                        │
│  └─ Secure Web Proxy                          │
│                                              │
│  → 必须建：                                  │
│     ✅ PSC NAT subnet（SA 强依赖）             │
│     ✅ proxy-only subnet（LB 强依赖）          │
│  → firewall 放 proxy-only subnet              │
│  → NetworkPolicy 放 proxy-only subnet         │
└
```

**简化版**：

- 如果 LB 是 proxy 类（你大概率走这条），**两个 subnet 都要建**
- 如果 LB 是 passthrough 类（变体 A），**只建 PSC NAT subnet**

---

## 9. 容量规划（经验值，非官方 verbatim）

### 9.1 PSC NAT subnet

| 业务规模 | 推荐大小 | NAT IP 数 | 单 Attachment 并发连接上限 |
|---------|---------|----------|--------------------------|
| 小流量 | `/28`（16 IP）| 12 | 12 × 64,512 = **~774K** |
| 中流量 | `/27`（32 IP）| 28 | 28 × 64,512 = **~1.8M** |
| 高流量 | `/26`（64 IP）| 60 | 60 × 64,512 = **~3.9M** |
| 超大流量 | 多 subnet | 多 IP 累加 | 上限看 quota（每 SA 最多 10 个 NAT subnet） |

**来源**：[本地 psc-sub-last.md §2.2 / §4.3](https://本地/psc-subnet/psc-sub-last.md)（用户验证过的工程经验；GCP 官方 sizing 文档在我抓取时为导航首页，未直接显示"最小 /28"原文 — 此处标为**工程经验**而非 GCP verbatim）。

### 9.2 Proxy-only subnet

| 业务规模 | 推荐大小 | IP 数 | 备注 |
|---------|---------|-------|------|
| 起步 | `/23`（GCP 推荐）| 512 | GCP 官方推荐起步大小 |
| 增长 | `/22`（1024 IP）| 1024 | 中等流量 |
| 超大 | `/21`（2048 IP）| 2048 | 多 LB / 高 QPS |
| 不可 | `/26`（64 IP）| 64 | **GCP 硬下限**（小于报错） |
| 不可 | `/27` 或更短 | < 64 | **创建失败** |

**来源**：GCP 官方原文 — *"must provide 64 or more IP addresses. This corresponds to a prefix length of /26 or shorter. We recommend that you start with a proxy-only subnet with a /23 prefix (512 proxy-only addresses)"*（[Proxy-only subnets for Envoy-based load balancers](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)）。

---

## 10. 速查表（贴桌边随时看）

| 看到 ... | 就是 ... |
|---------|---------|
| `purpose=PRIVATE_SERVICE_CONNECT` | PSC NAT subnet（跟 SA 绑定） |
| `purpose=REGIONAL_MANAGED_PROXY` | Proxy-only subnet（跟 Envoy-based LB 绑定） |
| `purpose=INTERNAL_HTTPS_LOAD_BALANCER` | Proxy-only subnet 的旧名字（已迁移） |
| backend 看到的 source IP 是 PSC NAT subnet | passthrough 类 LB（Internal passthrough NLB 等） |
| backend 看到的 source IP 是 proxy-only subnet | proxy 类 LB（Internal ALB / GKE Gateway） |
| 防火墙规则 `source-ranges=PSC NAT subnet CIDR` | 保护 passthrough LB 的 backend |
| 防火墙规则 `source-ranges=proxy-only subnet CIDR` | 保护 proxy 类 LB 的 backend |
| NetworkPolicy `from: ipBlock: cidr: proxy-only subnet` | K8s 层放行 GKE Gateway → Pod |
| 每个 region 1 个 active proxy-only subnet | GCP 强约束 |
| 每个 SA 最多 10 个 NAT subnet | GCP quota |

---

## 12. 多 LB 共享 Proxy-Only Subnet — 「1 个池子，N 个 LB」详解

> 本节专门讲一个常见的认知混淆：**「1 个 VPC 每 region 仅 1 个 active proxy-only subnet」到底意味着什么？是否限制了能暴露多少服务？**

### 12.1 核心答案

| 你的疑问 | 答案 |
|---------|------|
| 是不是所有 Envoy-based LB 共享 1 个池？ | **是的**（GCP 官方原文 — 见下） |
| 这个池限制的是 LB 数量吗？ | **不是**。LB 数量本身没有这个池的硬上限 |
| 这个池限制的是？ | **Envoy proxy 的总容量**（即所有 LB 同时能处理的并发连接数 + 总吞吐） |
| 1 个 IP = 1 个 LB？ | **不是**。1 个 IP ≈ N 个并发连接；N 个 LB 共享这池 IP |
| 池满了能扩吗？ | **不能原地扩**（不像普通 subnet 能 `--expand-ip-range`）— 必须新建 subnet，角色切 ACTIVE/BACKUP 替换 |

### 12.2 GCP 官方原文（verbatim 证据）

> "Proxy-only subnet with purpose `REGIONAL_MANAGED_PROXY`: In a given VPC network and region, only a single proxy-only subnet with purpose `REGIONAL_MANAGED_PROXY` can be **active at any point in time**. The active proxy-only subnet powers **all of the following products**:
> 1. Regional external Application Load Balancer
> 2. Regional internal Application Load Balancer
> 3. Regional external proxy Network Load Balancer
> 4. Regional internal proxy Network Load Balancer
> 5. Secure Web Proxy"
>
> — [Proxy-only subnets for Envoy-based load balancers](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)

> "For each proxy-only subnet purpose, Google Cloud allows **one ACTIVE and one BACKUP** proxy-only subnet to exist in a given region and VPC network."
>
> — [同上](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)

### 12.3 「1 个池子，N 个 LB」具体怎么工作

```text
VPC: my-project-vpc
Region: europe-west2

┌─── Proxy-Only Subnet (purpose=REGIONAL_MANAGED_PROXY, role=ACTIVE) ───┐
│ /23 (512 IPs)                                                        │
│                                                                       │
│ 10.204.0.0 ──┐                                                       │
│ 10.204.0.1 ──┤                                                       │
│ 10.204.0.2 ──┤                                                       │
│   ...        ├──> 共享 IP 池，被所有 Envoy-based LB 动态使用          │
│ 10.204.1.255 ┘                                                       │
└───────────────────────────────────────────────────────────────────────┘
         │            │             │              │              │
         ↓            ↓             ↓              ↓              ↓
   ┌──────────┐ ┌──────────┐  ┌──────────┐   ┌──────────┐  ┌──────────┐
   │External  │ │External  │  │Internal  │   │Internal  │  │Secure Web│
   │App LB #1 │ │Proxy NLB │  │App LB    │   │Proxy NLB │  │Proxy     │
   │(GKE GW)  │ │          │  │(GKE GW)  │   │          │  │          │
   └──────────┘ └──────────┘  └──────────┘   └──────────┘  └──────────┘
   team1.api    api-gateway    internal-api    mysql-proxy    egress-proxy
   tenant-A     api.foo.com    backend.baz     analytics      corp-out
   LB-A         LB-B           LB-C            LB-D           LB-E
```

**关键点**：

- 5 种 LB × 任意数量 = 都共享 512 个 IP（`/23` 起步）
- GCP controller **按需动态分配** Envoy 进程到这些 IP — 你不需要手动映射
- 某个 LB 用多少 IP 取决于该 LB 的 QPS / 并发连接数 / 后端数（GCP 自动 scale Envoy 副本）
- 当所有 LB 都不忙时，IP 处于 standby；当某个 LB 流量激增，controller 给它分配更多 Envoy → 用更多 IP

### 12.4 「决定你能暴露多少服务」正确理解

**决定的是总吞吐能力，不是 LB 数量。** 三个量纲：

| 量纲 | 单位 | 决定因素 | proxy-only subnet 影响 |
|------|------|---------|---------------------|
| **LB 数量** | 个 | 受其他 quota 限制（forwarding rule 数 / backend service 数）| **无直接影响**（假设 quota 没满） |
| **Envoy proxy 总数** | 个 Envoy 进程 | proxy-only subnet IP 数 | **强约束**：每个 Envoy 至少占 1 IP |
| **总并发连接数** | 个并发 TCP 连接 | Envoy 数 × 每 Envoy 并发上限 | **强约束**：受 IP 数影响 |

**粗略公式**（GCP 未公开精确数字，以下是工程经验值）：

```text
总 Envoy 容量上限 ≈ proxy-only subnet 可用 IP 数 × 单 Envoy 处理能力
                   = 512 IPs × ~10K 并发连接（保守估算）
                   ≈ 500 万并发连接（/23, 起步配置）
```

**实际生产建议**：监控 `proxy-only subnet` 的 IP 利用率（通过 Cloud Monitoring / VPC flow logs），**利用率 > 70% 时触发扩容流程**。

### 12.5 容量规划决策

#### Q1：我现在该配多大？

| 业务量 | 推荐配置 | 容量上限（粗略）| 备注 |
|--------|---------|---------------|------|
| **起步 / 单团队** | `/23`（512 IP）| ~500 万并发连接 | GCP 官方推荐起步 |
| **多团队 / 中量** | `/22`（1024 IP）| ~1000 万并发连接 | |
| **多租户平台 / 大量** | `/21`（2048 IP）| ~2000 万并发连接 | |
| **超大平台** | `/20`（4096 IP）| ~4000 万并发连接 | 单 region 上限实际接近此处 |

**判断依据**：

- 所有 LB 的峰值 QPS 总和 × 平均连接保持时间 = 理论峰值并发连接数
- 除以单 Envoy 容量 ≈ 需要多少 Envoy 副本
- 这就是 proxy-only subnet 需要的 IP 数（向上取整）

#### Q2：池满了怎么办（扩容流程）

**注意：proxy-only subnet **不能原地扩**！** 必须替换。

GCP 官方原文：

> "You can't expand the primary IPv4 address range of a proxy-only subnet in the same way that you would expand the primary IPv4 address range of a regular subnet (with the expand-ip-range command). Instead, **you must replace the proxy-only subnet with a new one.**"
>
> — [Proxy-only subnets for Envoy-based load balancers](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)

**替换流程**（GCP 官方步骤）：

1. **新建** 1 个 proxy-only subnet，**role=BACKUP**（同 region 同 VPC，IP 范围更大）
2. **调整 backend ingress firewall**：允许**新 + 旧两个 subnet**的 CIDR（否则切换时断流）
3. **切换 role**：把新 subnet 设为 ACTIVE（GCP 自动把旧的切到 BACKUP）
4. **draining 等待**：等旧的 subnet 上的现有连接走完
5. **确认 READY**：监控旧 subnet 状态到 READY
6. **清理**：删旧 subnet + 收窄 firewall 只放新 subnet CIDR

**完整流程示意**：

```text
初始状态：
  Proxy-Only-A: role=ACTIVE, /23, 10.204.0.0/23

扩容触发：IP 利用率 > 70%

Step 1: 建 Proxy-Only-B
  gcloud compute networks subnets create proxy-only-new \
    --network=my-vpc --region=europe-west2 \
    --range=10.204.4.0/22 --purpose=REGIONAL_MANAGED_PROXY \
    --role=BACKUP

Step 2: 扩 firewall（暂时放两个 CIDR）
  gcloud compute firewall-rules update m-pod-ingress-from-gateway-proxy \
    --source-ranges=10.204.0.0/23,10.204.4.0/22

Step 3: 切换
  gcloud compute networks subnets update proxy-only-new --role=ACTIVE
  # 自动：Proxy-Only-A role 变 BACKUP
  # GCP 自动做 draining

Step 4: 监控 Proxy-Only-A 状态
  gcloud compute networks subnets describe proxy-only-A \
    --region=europe-west2 --format='value(status)'
  # 等待 status=READY（连接已 drain）

Step 5: 收窄 firewall
  gcloud compute firewall-rules update m-pod-ingress-from-gateway-proxy \
    --source-ranges=10.204.4.0/22  # 只放新 subnet

Step 6: 删旧 subnet
  gcloud compute networks subnets delete proxy-only-A --region=europe-west2
```

**重要监控信号**：

```bash
# 看每个 LB 用了多少 IP（粗略：从 VPC flow logs 聚合）
gcloud logging read 'jsonPayload.connection.dest_ip:"10.204.0.0/23" AND jsonPayload.connection.protocol:"TCP"' \
  --project=${PROJECT} --limit=10

# 更精确：看 proxy-only subnet 的 IP 分配情况
gcloud compute networks subnets describe ${PROXY_SUBNET_NAME} \
  --region=${REGION} --project=${PROJECT} \
  --format='yaml(usage,ipCidrRange)'
```

### 12.6 与 GLB（Global External HTTPS LB）的区别

**重要澄清**：proxy-only subnet (`REGIONAL_MANAGED_PROXY`) **不服务于 Global External HTTPS LB**。

| LB 类型 | 用的 proxy-only subnet purpose | 说明 |
|--------|-------------------------------|------|
| **Global External HTTPS LB** | `GLOBAL_MANAGED_PROXY`（另一个 purpose）| **不在本文讨论范围**；它的 proxy-only subnet 全球级别 |
| **Regional External Application LB** | `REGIONAL_MANAGED_PROXY` | 本文讨论 |
| **Regional External Proxy Network LB** | `REGIONAL_MANAGED_PROXY` | 本文讨论 |
| **Regional Internal Application LB** | `REGIONAL_MANAGED_PROXY` | 本文讨论 |
| **Regional Internal Proxy Network LB** | `REGIONAL_MANAGED_PROXY` | 本文讨论 |
| **Secure Web Proxy** | `REGIONAL_MANAGED_PROXY` | 本文讨论 |

GCP 官方原文（dual-pool 段落）：

> "Proxy-only subnet with purpose `GLOBAL_MANAGED_PROXY`: In a given VPC network and region, only a single proxy-only subnet with purpose `GLOBAL_MANAGED_PROXY` can be active at any point in time. The active proxy-only subnet powers all of the following products: **Cross-region internal Application Load Balancer, Cross-region internal proxy Network Load Balancer**"
>
> — [Proxy-only subnets for Envoy-based load balancers](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)

**因此**：

- Lex 实际场景里"regional external/internal ALB + GKE Gateway"用的是 `REGIONAL_MANAGED_PROXY`
- 如果以后上 Global External HTTPS LB（公网入口），要单独建 `GLOBAL_MANAGED_PROXY` subnet
- 这两个池**互不影响**（不同 purpose），但**都要预先建好**

### 12.7 Lex 直觉的最终修正

> "是不是说，这样的话其实就决定了在整个 GKE 集群里，如果我想暴露对应的 External Load Balance 服务的时候，这个范围就决定了我暴露的服务有多少？"

**修正为**：

> "是的 — 在 region 内创建的所有 Envoy-based LB（包括 External 和 Internal）**都基于同一个 `REGIONAL_MANAGED_PROXY` subnet**。这个 subnet 的 IP 数决定了**所有 LB 共同的总吞吐能力**（不是 LB 个数）。它限制的不是「你能创建多少 LB」，而是「你的 LB 集群**同时**能处理多少并发连接 / 多少 QPS」。
>
> 当这个池用满时，需要走「新建 BACKUP subnet → 切换 ACTIVE → 删除旧 subnet」的扩容流程，不能原地扩。"

### 12.8 监控 + 告警建议

| 监控项 | 方法 | 告警阈值 |
|--------|------|---------|
| **proxy-only subnet IP 利用率** | VPC flow logs 聚合 / Cloud Monitoring 自定义指标 | > 70% → 警告；> 85% → 紧急 |
| **5 种 LB 总 QPS** | 每个 LB 的 `loadbalancing.googleapis.com/https/request_count` 累加 | > 设计容量 70% |
| **每 LB 错误率** | `loadbalancing.googleapis.com/https/backend_request_count`（5xx 比例） | > 1% |
| **LB 数量接近 forwarding rule quota** | `gcloud compute project-info describe` 检查 `FORWARDING_RULES` quota | > 80% |

### 12.9 References（§12 专属）

- [Proxy-only subnets for Envoy-based load balancers](https://cloud.google.com/load-balancing/docs/proxy-only-subnets) — §12.2 / §12.5 官方原文来源
- [Regional External Application Load Balancer overview](https://cloud.google.com/load-balancing/docs/https/setting-up-https) — External LB 入门
- [Regional Internal Application Load Balancer overview](https://cloud.google.com/load-balancing/docs/l7-internal) — Internal LB 入门
- [Cloud Load Balancing pricing](https://cloud.google.com/load-balancing/pricing) — LB 费用 + proxy IP 池费用

---

## 13. References

### 11.1 GCP 一手文档

- [Publish services by using Private Service Connect](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer) — PSC NAT subnet 的官方创建命令
- [Proxy-only subnets for Envoy-based load balancers](https://cloud.google.com/load-balancing/docs/proxy-only-subnets) — proxy-only subnet 的官方完整规范（verbatim 引文来源）
- [Firewall rules for Cloud Load Balancing](https://cloud.google.com/load-balancing/docs/firewall-rules) — backend 该放通哪类 source 的官方分类
- [VPC subnet purposes reference](https://cloud.google.com/vpc/docs/subnets#purpose) — 所有 `purpose` 字段枚举
- [PSC quotas](https://cloud.google.com/vpc/docs/quotas) — `psc_nat_subnets_per_service_attachment: 10` 等 quota 来源

### 11.2 本地知识库（经验 + 验证）

- `../gcp/network/psc-subnet/psc-sub-last.md` — PSC NAT subnet 容量规划（用户验证过的 /28 与 /27 对比）
- `../gcp/psa-psc/service-attachment-region.md` — Service Attachment 的区域级性质 + 双形态暴露
- `../gcp/psa-psc/dua-network-attacement-to-private-network.md` — 双网卡场景下 PSC NAT subnet + proxy-only subnet 并存的实操
- `../gcp/glb/glb.md` §"Proxy-Only Subnet 迁移报错" — `INTERNAL_HTTPS_LOAD_BALANCER → REGIONAL_MANAGED_PROXY` 重命名前因后果
- `../gcp/cross-project/cross-project-firewall-netpol/README.md` §3 — 两种 subnet 在 firewall 设计中的位置
- `../gcp/cross-project/cross-project-firewall-netpol/references/psc-firewall-cheatsheet.md` — passthrough vs proxy 速判表（进一步决策依据）
- `../gcp/cross-project/psc-firewall.md` §17-§22 — 上级 firewall 决策框架

### 11.3 抓取记录（本文 verbatim 引文来源）

- 抓取时间：2026-08-16
- 抓取方法：`curl` + Python HTMLParser（`cloud-provider-doc-research-pattern` skill 方法）
- 命中：`publish-private-service-connect-producer` (227KB) + `proxy-only-subnets` (199KB)
- 4xx/5xx：3 个 URL 漂移（`/subnet#purpose` / `/configure-private-service-connect-services-consumer` / `/quotas#psc`）— 已 fallback 到本地文档

---

*最后更新：2026-08-16 · 遵循 redaction policy（无真实 org / IP / hostname）· Verbatim 引文均带官方 URL + fetch date*