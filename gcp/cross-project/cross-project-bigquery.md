# 跨项目 BigQuery 访问:Master 项目 GKE → Tenant 项目 BigQuery(Private Google Access / PGA 路线)

> **TL;DR**
>
> **场景**:Pod 在 master 项目的 GKE 里,需要查询 tenant 项目里 BigQuery dataset 的数据。
> **要求**:**网络不走公网** — 全部流量走 Google 私有骨干网(master VPC 内的 internal IP → Google backbone → BQ API)。
>
> **核心结论**:**BigQuery 自身没有 PSC Service Attachment**(不像 Cloud SQL 可以让 consumer VPC 创建 PSCEP)。
> BigQuery 是 Google 管理的 `*.googleapis.com` PaaS,**标准私有访问方式 = Private Google Access (PGA) +
> `restricted.googleapis.com` 这个所有 Google API 共享的 private VIP**(`199.36.153.4/30`)。
>
> **网络侧链路**(本篇重点):
>
> ```
> Pod → Pod-internal (无网络)
>      → Node (GKE node IP, internal)
>      → Subnet(PGA enabled,无 external IP 也能出去)
>      → Cloud DNS 解析 bigquery.googleapis.com → restricted.googleapis.com A 199.36.153.4/30
>      → VPC 默认路由 → Google backbone(走 internal IP,不公网)
>      → bigquery.googleapis.com (BQ API)
>      → tenant project IAM verify(GSA 有 dataset IAM)→ 返回数据
> ```
>
> **IAM 侧链路**(本篇不重复细节,引用母文档):
> - KSA → GSA via Workload Identity Federation(auth-side)
> - GSA → tenant dataset IAM via `bigquery.dataViewer` + `bigquery.jobUser`(resource-side)
>
> 详见姊妹篇 [`cross-project-bigquery-master-to-tenant.md`](./cross-project-bigquery-master-to-tenant.md) §3-§4。
>
> **本文重点在网络侧**:把 master 的 GKE VPC 配成"internal-only,走 PGA + restricted.googleapis.com",
> 然后让 IAM 链照常工作。这个套路**借鉴** Cloud SQL PSC 的"网络侧方案设计哲学"(强制走 private path),
> 但**机制完全不同** — 见 §5 对照表。

---

## 1. 为什么这篇文档要存在?

姊妹文章 [`./cross-project-bigquery-master-to-tenant.md`](./cross-project-bigquery-master-to-tenant.md) 覆盖了
**6 种 BigQuery 跨项目联邦方案**的完整 trade-off 矩阵(§5)。其中**方案 6** = "Private Google Access +
tenant 自家 VPC endpoint" — 但母文档 §5.3 的方案 6 只写了 30 行纲要,**没有具体命令栈、没有 DNS 配置、
没有验证脚本、没有架构图**。

本文 = **方案 6 的 full 工程实现版本**,聚焦在 "Private Google Access + `restricted.googleapis.com`" 这一条路径,
补足:

1. **§2 抽象视角** — 解释 BigQuery 为什么"没有 PSC Service Attachment" → 解释"为什么 PGA 是唯一选择"
2. **§3 朴素视角** — 完整命令栈 + YAML:subnet enable PGA、Private DNS zone、IAM grant、bq 测试
3. **§4 严格视角** — 跟 Cloud SQL PSC 的 1-to-1 对照表,**避免"误以为两者是同一回事"**
4. **§5 决策树** — 什么时候选方案 6(PGA + IAM)、什么时候选方案 1(WI + IAM,默认)
5. **§6 验证脚本** — DNS 解析 / VPC Flow Logs / bq query 端到端
6. **§7 引用来源 / 权威证据** — Google 官方原话 anchor

---

## 2. 抽象视角:为什么 BigQuery 走 PGA,而不是 PSC?

### 2.1 Google Cloud 上"私有访问 Google API"的两个层次

摘自 <https://cloud.google.com/vpc/docs/private-access-options>(Google 官方分类):

> **Google Cloud offers two types of services:**
>
> 1. **Google APIs and services that run on Google's production infrastructure** — Example services include:
>    **Google APIs, including those that have `*.googleapis.com` API service endpoints.**
>    Services in Google's production infrastructure **might offer private connectivity through
>    Private Service Connect, Private Google Access, or both.**
>
> 2. **VPC-hosted services that run on Compute Engine VMs in VPC networks** — Example services include:
>    **Cloud SQL, Filestore, Memorystore for Redis**.
>    VPC-hosted services **might offer private connectivity through Private Service Connect,
>    private services access, VPC Network Peering, or a combination of those options.**

这一段是**全篇最关键的事实** — 它解释了为什么 BigQuery 跟 Cloud SQL 走完全不同的"私有访问"路径:

| 服务类型 | 例子 | 私有访问方式 |
|--|--|--|
| **Google production infrastructure APIs** | BigQuery, Cloud Storage, Compute Engine API, KMS, IAM | **PGA + `*.googleapis.com` private VIP**,或 **PSC endpoints for Google APIs** |
| **VPC-hosted services**(跑在 GCP 项目里的 VM 上) | **Cloud SQL**, Filestore, Memorystore, Redis | **PSC Service Attachment**(producer 项目 expose)+ PSCEP(consumer 项目建);或 private services access / VPC peering |

**BigQuery 属于第一类** — 它是一个 `*.googleapis.com` PaaS,Google 把它**当 Google API 来运营**,不暴露 producer VPC,
所以**没有 PSC Service Attachment** 可以让你"申请"。这就是为什么用户要"用 PSC 实现 BQ 跨项目" 的根本误解需要纠正 —

> ⚠️ **Lex,你原话里"通过 PSC 的方式来实现 beauty create cross project"在 BigQuery 这个语境下是不存在的**。
> 你想要的"private 访问 + 跨项目 IAM"是有的,但它**走的是 PGA 这条路,不是 PSC**。
> 这跟 Cloud SQL 完全不同 — Cloud SQL 是 VPC-hosted 服务,真的可以走 PSC。

### 2.2 BigQuery 跨项目 private 访问的"两条腿"

```
       ┌──────────────────────────────────────┐
       │  Auth-side (Workload Identity)        │  ← 母文档 §3 / §4 覆盖
       │  Pod (KSA) → GKE metadata → STS       │
       │  → impersonate master GSA             │
       └──────────────────────────────────────┘
                          ↓
                  (GSA token 持有)
                          ↓
       ┌──────────────────────────────────────┐
       │  Network-side (Private Google Access) │  ← 本文档覆盖
       │  Pod → Node → Subnet(PGA on)          │
       │  → Cloud DNS 解析 bigquery.googleapis.com
       │  → restricted.googleapis.com (199.36.153.4/30)
       │  → Google backbone → BQ API           │
       └──────────────────────────────────────┘
                          ↓
                  (网络包到达 BQ API endpoint)
                          ↓
       ┌──────────────────────────────────────┐
       │  Resource-side (tenant IAM)           │  ← 母文档 §3.1 / §5.3 覆盖
       │  BQ IAM verify GSA 是否有 dataset IAM │
       │  (dataViewer + jobUser)               │
       └──────────────────────────────────────┘
```

**两条腿都缺,query 都跑不通**:

- 缺 IAM 链 → `403 Permission denied`(即使 IP 通)
- 缺网络链(节点有 external IP,但要 disable 强制走 private)→ 流量走公网,**违反"private 访问"承诺**

### 2.3 `restricted.googleapis.com` vs `private.googleapis.com`

摘自 <https://cloud.google.com/vpc/docs/configure-private-google-access#domain-options>(Google 官方原文):

| Domain | IPv4 段 | IPv6 段 | VPC-SC 行为 | Google Workspace | BigQuery |
|--|--|--|--|--|--|
| `private.googleapis.com` | `199.36.153.8/30` | `2600:2d00:0002:2000::/56` | **不强制** — 即使 service 不受 VPC-SC 保护也能通 | ✅ 支持 Gmail/Docs 等 | ✅ |
| `restricted.googleapis.com` | `199.36.153.4/30` | `2600:2d00:0002:1000::/56` | **强制 VPC-SC** — 不受 VPC-SC 保护的服务被阻断 | ❌ 不支持 Gmail/Docs 等 | ✅ |

**Google 原文**:

> "Choose `private.googleapis.com` to access Google APIs and services by using a set of IP addresses
> only routable from within Google Cloud. Choose `private.googleapis.com` under these circumstances:
> You don't use VPC Service Controls. You do use VPC Service Controls, but you also need to access
> Google APIs and services that are not supported by VPC Service Controls."
>
> "Use `restricted.googleapis.com` to access Google APIs and services by using a set of IP addresses
> only routable from within Google Cloud. Choose `restricted.googleapis.com` when you only need
> access to Google APIs and services that are supported by VPC Service Controls.
> The `restricted.googleapis.com` domain does not permit access to Google APIs and services that do
> not support VPC Service Controls."

**选型建议**:

- **你的 tenant 项目受 VPC-SC 保护**(金融/医疗/合规场景)→ 用 **`restricted.googleapis.com`** ✅
- **你的 tenant 项目不受 VPC-SC 保护**(开发/测试/非合规)→ 用 `private.googleapis.com` 更宽
- **本篇默认按用户要求**,选 **`restricted.googleapis.com`** — 因为它是文档 §5.3 方案 6 "私有 + VPC-SC 强制"
  的官方推荐选项

---

## 3. 朴素视角:完整命令栈

### 3.1 前置假设

- `MASTER_PROJECT` = master 项目 ID(跑 GKE + 应用 Pod 的项目)
- `TENANT_PROJECT` = tenant 项目 ID(拥有 BigQuery dataset 的项目)
- `MASTER_REGION` = GKE cluster 所在 region(例:`europe-west2`)
- `GKE_CLUSTER` = GKE cluster 名
- `K8S_NAMESPACE` / `KSA_NAME` = 工作负载 namespace + KSA 名
- `GSA_NAME` = master 项目里创建的 GSA 名(例:`master-bq-reader`)
- `BQ_DATASET` = tenant 项目里的 dataset 名(例:`analytics`)
- `MASTER_VPC` = master 项目的 VPC(假设 Shared VPC 或独立 VPC,本例按独立 VPC 写)
- `GKE_NODE_SUBNET` = GKE 节点所在 subnet 名(例:`gke-node-subnet`)

### 3.2 命令栈(分 5 个阶段)

#### 阶段 A — 节点 subnet 启用 Private Google Access

**关键事实**(摘自 <https://cloud.google.com/vpc/docs/private-google-access>):

> "You enable Private Google Access on a subnet by subnet basis. **Private Google Access has no effect
> on instances that have external IP addresses.**"

也就是说:
- **必须**给 GKE 节点 subnet enable PGA — 否则没有 external IP 的节点**根本出不去**
- 已经分配 external IP 的节点**不需要 PGA 也能出去**(但那就走公网,违反"private"承诺)

**最干净的姿势**:GKE cluster / node pool **完全不开 external IP**(私有 cluster 或 private node pool),
然后 enable PGA。

```bash
# 假设 GKE 集群已经存在,这里改 subnet 设置
gcloud compute networks subnets update "$GKE_NODE_SUBNET" \
  --project="$MASTER_PROJECT" \
  --region="$MASTER_REGION" \
  --enable-private-ip-google-access

# 验证
gcloud compute networks subnets describe "$GKE_NODE_SUBNET" \
  --project="$MASTER_PROJECT" \
  --region="$MASTER_REGION" \
  --format="value(privateIpGoogleAccess)"
# 期望:True
```

> 💡 **如果你的 GKE 集群已经是私有 cluster**(节点全 internal IP),这一步可能是默认状态,但仍要 confirm。

#### 阶段 B — Private DNS zone + A record

**关键事实**:PGA 本身**不做 DNS 劫持** — 它只让 subnet 内的 VM **能路由到**`199.36.153.4/30`。要让 Pod
`bigquery.googleapis.com` 真正解析到 restricted VIP,**必须配 Cloud DNS private zone**。

```bash
# 1) 创建 private DNS zone(对 *.googleapis.com 私有解析)
gcloud dns managed-zones create "googleapis-private" \
  --project="$MASTER_PROJECT" \
  --dns-name="googleapis.com." \
  --description="Private zone for restricted.googleapis.com resolution" \
  --visibility=private \
  --networks="$MASTER_VPC"

# 2) 加 A record:把 googleapis.com CNAME 到 restricted.googleapis.com
gcloud dns record-sets transaction start --zone="googleapis-private" --project="$MASTER_PROJECT"

gcloud dns record-sets transaction add "199.36.153.4" \
  --name="restricted.googleapis.com." \
  --ttl=300 \
  --type=A \
  --zone="googleapis-private" --project="$MASTER_PROJECT"

gcloud dns record-sets transaction add "199.36.153.5" \
  --name="restricted.googleapis.com." \
  --ttl=300 \
  --type=A \
  --zone="googleapis-private" --project="$MASTER_PROJECT"

gcloud dns record-sets transaction add "199.36.153.6" \
  --name="restricted.googleapis.com." \
  --ttl=300 \
  --type=A \
  --zone="googleapis-private" --project="$MASTER_PROJECT"

gcloud dns record-sets transaction add "199.36.153.7" \
  --name="restricted.googleapis.com." \
  --ttl=300 \
  --type=A \
  --zone="googleapis-private" --project="$MASTER_PROJECT"

# 3) 加 wildcard:把所有 *.googleapis.com 解析到 restricted VIP
gcloud dns record-sets transaction add \
  "restricted.googleapis.com." \
  --name="*.googleapis.com." \
  --ttl=300 \
  --type=CNAME \
  --zone="googleapis-private" --project="$MASTER_PROJECT"

gcloud dns record-sets transaction execute --zone="googleapis-private" --project="$MASTER_PROJECT"

# 验证
gcloud dns record-sets list --zone="googleapis-private" --project="$MASTER_PROJECT"
```

**为什么用 wildcard CNAME 而不是给每个服务写一条 A record?**

- BigQuery → `bigquery.googleapis.com`
- IAM / STS → `iam.googleapis.com` / `sts.googleapis.com`(GKE metadata-server 用)
- Cloud Resource Manager → `cloudresourcemanager.googleapis.com`(project list 用)
- KMS → `cloudkms.googleapis.com`(如果用 CMEK)
- Logging → `logging.googleapis.com`(audit log 写)

所有这些 `*.googleapis.com` 一次性走 wildcard CNAME 到 `restricted.googleapis.com`,然后再走 4 个 A record
解析到 `199.36.153.4-7`。**配一次,全 API 通**。

> ⚠️ **如果你的 GKE cluster 同时用 `gcr.io` / `*.gcr.io`(拉 container image)**,这些不在 `googleapis.com` 域,
> 但在 restricted 域列表里(`*.gcr.io` → 见 §2.3 表格),所以**不用额外配** — Cloud DNS 已经涵盖。

#### 阶段 C — VPC firewall 放行 restricted VIP

**为什么需要?**默认 egress firewall 是 allow-all,但有些组织设了 `deny-all egress`。
restricted VIP `199.36.153.4/30` 是**所有 Google API 共享的 VIP**,必须能从 master VPC 出去。

```bash
# Egress allow rule(如果是 deny-all 集群,这条必须加)
gcloud compute firewall-rules create "allow-egress-to-restricted-googleapis" \
  --project="$MASTER_PROJECT" \
  --network="$MASTER_VPC" \
  --direction=EGRESS \
  --action=ALLOW \
  --rules=tcp:443 \
  --destination-ranges="199.36.153.4/30" \
  --priority=1000 \
  --description="Allow egress to restricted.googleapis.com (BQ/Cloud APIs)"
```

#### 阶段 D — IAM 链(master GSA + tenant dataset IAM)

> **本节是母文档 §4 的浓缩摘要**。完整命令栈见
> [`cross-project-bigquery-master-to-tenant.md`](./cross-project-bigquery-master-to-tenant.md) §4。

```bash
GSA_EMAIL="${GSA_NAME}@${MASTER_PROJECT}.iam.gserviceaccount.com"

# D.1 master 项目创建 GSA
gcloud iam service-accounts create "$GSA_NAME" \
  --project="$MASTER_PROJECT" \
  --description="BQ reader from master GKE → tenant BQ (PGA + restricted)"

# D.2 master GSA 接受 KSA 的 WI impersonate
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
  --project="$MASTER_PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${MASTER_PROJECT}.svc.id.goog[${K8S_NAMESPACE}/${KSA_NAME}]"

# D.3 tenant 项目给 GSA dataset-level IAM
gcloud bigquery datasets add-iam-policy-binding "$BQ_DATASET" \
  --project="$TENANT_PROJECT" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="roles/bigquery.dataViewer"

gcloud bigquery datasets add-iam-policy-binding "$BQ_DATASET" \
  --project="$TENANT_PROJECT" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="roles/bigquery.jobUser"

# D.4 K8s KSA 注解
kubectl annotate serviceaccount "$KSA_NAME" -n "$K8S_NAMESPACE" \
  iam.gke.io/gcp-service-account="$GSA_EMAIL"
kubectl label namespace "$K8S_NAMESPACE" iam.gke.io/workload-identity=true
```

#### 阶段 E — VPC-SC 边界双向 allow(如果用 restricted.googleapis.com)

`restricted.googleapis.com` **强制走 VPC-SC** — 如果 master 或 tenant 在 VPC-SC perimeter 里,必须**双向**
allow 对面的 service identity。

> 完整细节 + 命令见 [`cross-project-bigquery-master-to-tenant.md`](./cross-project-bigquery-master-to-tenant.md) §5.6 坑 6。

```bash
# master perimeter access level 包含 tenant 的 service identity
gcloud access-context-manager perimeters update "$MASTER_PERIMETER" \
  --policy="$ACCESS_POLICY" \
  --add-access-levels="..." \
  --project="$ACCESS_POLICY_PROJECT"

# tenant perimeter 同理
```

---

## 4. 严格视角:跟 Cloud SQL PSC 的 1-to-1 对照

### 4.1 机制对照表

用户原始要求是 "参考 Cloud SQL PSC 的实现方式" — 但**这两个东西在 Google 内部架构上完全不同**。
下面这张表是**事实校对**,让你看清为什么不能简单"套模板":

| 维度 | **Cloud SQL PSC** | **BigQuery Private Google Access** |
|--|--|--|
| **服务类别** | VPC-hosted service(跑在 GCP 项目 VM 上) | Google production API(PaaS) |
| **服务暴露方式** | Producer 项目 expose **Service Attachment** (一个 SA URL) | **无 Service Attachment** — 直接由 Google 全球 API 端点提供 |
| **Consumer 入口** | Consumer VPC 创建 **PSCEP IP** (一个 IP 绑定 forwarding rule) | Consumer subnet 用 **PGA 默认路由** + DNS 把 `*.googleapis.com` 解析到 `199.36.153.4/30` |
| **Producer 在哪个项目** | 必须是数据/服务的 owner 项目 | **不存在 producer** — Google 自己的基础设施 |
| **跨项目 IAM** | SA(impersonate)+ Cloud SQL IAM user(IAM DB auth) | GSA(impersonate)+ BQ dataset IAM(`dataViewer` + `jobUser`) |
| **NetworkPolicy 出站** | 必须放 `3306`(直连)或 `3307`(Auth Proxy)(见 [`why-psc-netpolicy-3307.md`](../psa-psc/psc-sql-flow-demo/k8s/why-psc-netpolicy-3307.md)) | 必须放 `443`(HTTPS)到 `199.36.153.4/30` |
| **DNS 处理** | 不需要 — PSCEP 已经是 IP | **需要** Cloud DNS 把 `*.googleapis.com` → `restricted.googleapis.com` → `199.36.153.4-7` |
| **VPC-SC 关联** | 一般不强制(Cloud SQL 在 VPC-SC 支持列表里独立处理) | **强制**(`restricted.googleapis.com` = VPC-SC 强制) |
| **跨项目流量拓扑** | Pod → Node → PSCEP IP (in master VPC) → Google backbone → Tenant VPC SA → Cloud SQL VM | Pod → Node → 199.36.153.4/30 (in master VPC) → Google backbone → BQ API endpoint (Google-managed) |
| **GKE 节点 IP 要求** | 不要 external IP(否则走公网绕过 PSCEP) | 不要 external IP(否则走公网绕过 PGA) |
| **可视化的架构图 reference** | [`cloud-sql-proxy-psc-3307-debug-flow.html`](../psa-psc/psc-sql-flow-demo/k8s/cloud-sql-proxy-psc-3307-debug-flow.html)(3-zone:Pod / NetworkPolicy / PSCEP) | [`cross-project-bigquery-architecture.html`](./cross-project-bigquery-architecture.html)(3-zone:Pod / Cloud DNS + PGA subnet / BQ API) |

### 4.2 借鉴 Cloud SQL PSC 的"设计哲学",而不是"机制"

Cloud SQL PSC 流程图教给我们 3 个**抽象的设计原则** — 这些在 BigQuery PGA 上**完全适用**:

| Cloud SQL PSC 原则 | BigQuery PGA 对应 |
|--|--|
| **节点无 external IP** | **节点无 external IP**(GKE private cluster / private node pool) |
| **NetworkPolicy 出站必须显式 allow** | **NetworkPolicy 出站必须显式 allow 443 → `199.36.153.4/30`**(母文档 §5.6 坑 4 同源) |
| **debug 信号 = pod cmdline + ss/netstat** | **debug 信号 = pod 内 `dig` + `tcpdump` + `nc -vz 199.36.153.4 443`** |

### 4.3 完整数据流(端到端 trace)

下面是从 Pod 发起一次 `bq query` 到数据返回的**全链路 trace**:

```
GKE Pod (master-project-prod)
  ↓ kubectl exec → bq query --project_id=tenant-project-data ...
  ↓
  bq client → google-cloud-python → google.auth.default()
  ↓
  GET metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token
  ↓ GKE metadata-server 拦截(注入 WI 链路)
  KSA annotation → master GSA impersonate
  ↓ STS exchange
  返回 GCP access token (1 小时)
  ↓
  DNS 解析:bigquery.googleapis.com
  ↓ Cloud DNS private zone (阶段 B)
  *.googleapis.com (CNAME) → restricted.googleapis.com
  restricted.googleapis.com (A) → 199.36.153.4
  ↓
  TCP 三次握手:Pod IP:ephemeral → 199.36.153.4:443
  ↓ Node iptables (network policy 放行 443 → 199.36.153.4/30)
  ↓ Subnet 默认路由 → default-internet-gateway
  ↓ Google backbone (private, internal IP)
  ↓
  bigquery.googleapis.com (Google API frontend)
  ↓ verify GSA token signature + project scope
  ↓ IAM check: GSA 在 tenant-project-data:analytics 有 dataViewer + jobUser? YES
  ↓
  返回 query 结果,流量沿原路 back
```

**关键观察**:

1. **每个 hop 都是 Google 内部 IP**(Pod IP / Node IP / 199.36.153.4/30 / BQ API endpoint),**没有任何公网 IP**
2. **DNS 解析是 Cloud DNS private zone 完成的**,不是节点本地的 `/etc/hosts` 也不是 metadata-server
3. **GSA token 是不透明字符串**,Google API frontend 在收到 token 后**独立 verify**(不依赖任何网络 trust)

---

## 5. 决策树:什么时候走 PGA + IAM(方案 6)?什么时候走纯 IAM(方案 1)?

```
你的 cross-project BigQuery 需求
  │
  ├── "我只要 query 通,不在意走不走公网"
  │     → 方案 1 (WI + IAM, default)
  │       母文档 §3-§4 完整覆盖,无网络配置成本
  │
  ├── "必须走 private path(节点无 external IP)"
  │     │
  │     ├── "我不用 VPC-SC"
  │     │     → 方案 6a: PGA + private.googleapis.com
  │     │       DNS A record → 199.36.153.8/30
  │     │
  │     ├── "我要 VPC-SC 强制覆盖"
  │     │     → 方案 6b: PGA + restricted.googleapis.com  ← 本文档重点
  │     │       DNS A record → 199.36.153.4/30
  │     │       + 双向 perimeter allow
  │     │
  │     └── "我要 tenant 数据永远不出 tenant"
  │           → 方案 2 (Authorized Dataset)  ← 母文档 §5.3
  │
  └── "我要 batch + 实时性不敏感"
        → 方案 4 (GCS) / 方案 5 (BQ transfer)
```

### 5.1 方案 6 适用场景

- **金融/医疗/合规** — VPC-SC 是强制要求
- **节点零 external IP** — private cluster(成本 + 攻击面 ↓)
- **跨 region 流量监管** — 所有 GCP API 走 internal,审计统一

### 5.2 方案 6 不适用场景

- **快速原型 / dev env** — 节点有 external IP,方案 1 足够
- **tenant 数据治理严格** — 走 Authorized Dataset(方案 2),不依赖 network-level 限制
- **VPC-SC 还没启用** — 走 `private.googleapis.com` 而不是 `restricted.googleapis.com`

---

## 6. 验证脚本(端到端)

### 6.1 静态验证 — IAM + DNS + subnet 一次过

```bash
#!/usr/bin/env bash
# verify-cross-project-bq-pga.sh
# 用法: ./verify-cross-project-bq-pga.sh
# 依赖: gcloud, kubectl (master cluster context), bq, dig (or nslookup)
set -euo pipefail

MASTER_PROJECT="${MASTER_PROJECT:-master-project-prod}"
TENANT_PROJECT="${TENANT_PROJECT:-tenant-project-data}"
GKE_CLUSTER="${GKE_CLUSTER:-app-cluster}"
MASTER_REGION="${MASTER_REGION:-europe-west2}"
GSA_NAME="${GSA_NAME:-master-bq-reader}"
GSA_EMAIL="${GSA_NAME}@${MASTER_PROJECT}.iam.gserviceaccount.com"
K8S_NAMESPACE="${K8S_NAMESPACE:-app}"
KSA_NAME="${KSA_NAME:-app-ksa}"
BQ_DATASET="${BQ_DATASET:-analytics}"
GKE_NODE_SUBNET="${GKE_NODE_SUBNET:-gke-node-subnet}"
MASTER_VPC="${MASTER_VPC:-master-vpc}"
DNS_ZONE="${DNS_ZONE:-googleapis-private}"

ok()   { echo "  ✅ $*"; }
fail() { echo "  ❌ $*"; exit 1; }
warn() { echo "  ⚠️  $*"; }

echo "==> [1/8] subnet 启用 PGA?"
PGA=$(gcloud compute networks subnets describe "$GKE_NODE_SUBNET" \
  --project="$MASTER_PROJECT" --region="$MASTER_REGION" \
  --format="value(privateIpGoogleAccess)")
[[ "$PGA" == "True" ]] && ok "subnet $GKE_NODE_SUBNET PGA=True" || fail "subnet PGA=$PGA(应为 True)"

echo "==> [2/8] Private DNS zone 存在?"
ZONE_EXISTS=$(gcloud dns managed-zones describe "$DNS_ZONE" \
  --project="$MASTER_PROJECT" --format="value(name)" 2>/dev/null || echo "")
[[ -n "$ZONE_EXISTS" ]] && ok "zone $DNS_ZONE 存在" || fail "zone $DNS_ZONE 缺失"

echo "==> [3/8] restricted.googleapis.com A 记录正确?"
RECORD=$(gcloud dns record-sets list --zone="$DNS_ZONE" \
  --project="$MASTER_PROJECT" --name="restricted.googleapis.com." \
  --type=A --format="value(rrdata)" 2>/dev/null | sort | tr '\n' ',' )
EXPECTED="199.36.153.4,199.36.153.5,199.36.153.6,199.36.153.7,"
[[ "$RECORD" == "$EXPECTED" ]] \
  && ok "A record = $RECORD" \
  || fail "A record=$RECORD(应为 $EXPECTED)"

echo "==> [4/8] master GSA + WI binding 存在?"
WI_BINDING=$(gcloud iam service-accounts get-iam-policy "$GSA_EMAIL" \
  --project="$MASTER_PROJECT" --format=json | \
  jq -e --arg m "serviceAccount:${MASTER_PROJECT}.svc.id.goog[${K8S_NAMESPACE}/${KSA_NAME}]" \
    '.bindings[] | select(.role=="roles/iam.workloadIdentityUser") | .members[] | select(.==$m)')
[[ -n "$WI_BINDING" ]] && ok "KSA → GSA binding" || fail "WI binding 缺失"

echo "==> [5/8] tenant-side dataset IAM 给 GSA?"
DATA_ROLE=$(gcloud bigquery datasets get-iam-policy "$BQ_DATASET" \
  --project="$TENANT_PROJECT" --format=json | \
  jq -e --arg m "$GSA_EMAIL" \
    '.bindings[] | select(.role=="roles/bigquery.dataViewer") | .members[] | select(.==$m)')
[[ -n "$DATA_ROLE" ]] && ok "bigquery.dataViewer" || fail "dataViewer 缺失"

JOB_ROLE=$(gcloud bigquery datasets get-iam-policy "$BQ_DATASET" \
  --project="$TENANT_PROJECT" --format=json | \
  jq -e --arg m "$GSA_EMAIL" \
    '.bindings[] | select(.role=="roles/bigquery.jobUser") | .members[] | select(.==$m)')
[[ -n "$JOB_ROLE" ]] && ok "bigquery.jobUser" || fail "jobUser 缺失"

echo "==> [6/8] KSA annotation?"
ANNO=$(kubectl get serviceaccount -n "$K8S_NAMESPACE" "$KSA_NAME" \
  -o jsonpath='{.metadata.annotations."iam\.gke\.io/gcp-service-account"}' 2>/dev/null || echo "")
[[ "$ANNO" == "$GSA_EMAIL" ]] && ok "KSA annotation → $GSA_EMAIL" || fail "annotation 是 '$ANNO'"

echo "==> [7/8] Pod 内 DNS 解析 → restricted VIP?"
# kubectl exec ... dig; 如果容器没装 dig,改用 nslookup 或 getent hosts
RESOLVED=$(kubectl exec -n "$K8S_NAMESPACE" deploy/your-app -- \
  sh -c "getent hosts bigquery.googleapis.com" 2>/dev/null | awk '{print $1}' | head -1)
[[ "$RESOLVED" =~ ^199\.36\.153\.[4-7]$ ]] \
  && ok "bigquery.googleapis.com → $RESOLVED(restricted VIP)" \
  || fail "解析到 $RESOLVED(应在 199.36.153.4/30)"

echo "==> [8/8] Pod 内 TCP 443 → restricted VIP 通?"
kubectl exec -n "$K8S_NAMESPACE" deploy/your-app -- \
  sh -c "timeout 5 bash -c '</dev/tcp/199.36.153.4/443' && echo TCP_OK" \
  || fail "TCP 443 → 199.36.153.4 不通"

echo ""
echo "✅ 静态链路全部就绪"
echo ""
echo "==> (可选) 真 query 验证"
echo "    kubectl exec -n $K8S_NAMESPACE deploy/your-app -- \\"
echo "      bq query --project_id=$TENANT_PROJECT --use_legacy_sql=false \\"
echo "        'SELECT COUNT(*) FROM \`${TENANT_PROJECT}.${BQ_DATASET}.__TABLES__\`'"
```

### 6.2 动态验证 — VPC Flow Logs 看是否走 internal IP

```bash
# 在 master project 开 VPC Flow Logs(如果还没开)
gcloud compute networks subnets update "$GKE_NODE_SUBNET" \
  --project="$MASTER_PROJECT" --region="$MASTER_REGION" \
  --enable-flow-logs

# 等几分钟后查 log:Pod IP → 199.36.153.4:443
gcloud logging read \
  'resource.type="gce_subnetwork" AND jsonPayload.connection.destination_ip="199.36.153.4"' \
  --project="$MASTER_PROJECT" --limit=5 --format=json | jq '.[].jsonPayload.connection'
```

**期望看到**:
```json
{
  "destination_ip": "199.36.153.4",
  "destination_port": 443,
  "protocol": "tcp",
  "bytes_sent": "1234",
  "packets_sent": "10"
}
```

**如果看到 source/destination 都是 GCP 内部 IP**(Pod IP / 199.36.153.4)= **private 路径生效** ✅
**如果 destination_ip 是公网 IP** = 走了公网 → **PGA 没配对,回去查阶段 A/B/C**

---

## 7. 踩坑清单(从母文档 §5.6 继承 + 本篇新增)

### 坑 1:节点有 external IP,PGA 形同虚设
**症状**:Flow Logs 显示 destination 是公网 IP
**原因**:`Private Google Access has no effect on instances that have external IP addresses`(官方原话)
**修法**:建 private node pool(`--create-node-pool --no-enable-autorepair ...` 之外加 `--no-address` 或用 private cluster)

### 坑 2:Cloud DNS zone 没绑到 VPC
**症状**:`getent hosts bigquery.googleapis.com` 解析到公网 IP
**原因**:`--networks` 参数漏了,zone 是孤儿
**修法**:`gcloud dns managed-zones update "$DNS_ZONE" --networks="$MASTER_VPC"`

### 坑 3:wildcard CNAME 跟 A record 顺序错
**症状**:nslookup `restricted.googleapis.com` → NXDOMAIN
**原因**:先加 wildcard 再加 A record,zone 顺序错乱
**修法**:`transaction start → add A → add CNAME → execute`(按文档 §3.2 顺序)

### 坑 4:NetworkPolicy 只放 443 to `0.0.0.0/0`,但 §4 流程图要求细化
**症状**:Pod 能通 `199.36.153.4`,但被 deny-all 拦掉
**原因**:`egress.to = []` 空目标 + 仅 `port: 443` → 默认匹配所有 IP,但 deny-all 优先级可能更高
**修法**:
```yaml
egress:
  - to:
    - ipBlock:
        cidr: 199.36.153.4/30
    ports:
    - protocol: TCP
      port: 443
```

### 坑 5:用了 `restricted.googleapis.com` 但 VPC-SC 没启用
**症状**:`Connection reset by peer` 或 `400 Bad Request` from BQ API
**原因**:`restricted.googleapis.com` 强制 VPC-SC,未启用 perimeter 时 API 直接拒绝
**修法**:要么启用 VPC-SC + 双向 perimeter allow,要么改用 `private.googleapis.com`(放松限制)

### 坑 6:跨 region BQ endpoint
**症状**:master `europe-west2`,tenant `us-central1` BQ,偶发 timeout
**原因**:BQ 有 region-specific endpoint(`eu-bigquery.googleapis.com`),PGA 默认走 `*.googleapis.com`
**修法**:在 client library 显式 `client.WithEndpoint("https://eu-bigquery.googleapis.com")` 或接受默认

### 坑 7:Cloud DNS resolver 缓存
**症状**:改了 DNS record 后,Pod 内 5 分钟内仍解析到旧 IP
**原因**:kubelet / nodelocaldns cache
**修法**:`kubectl rollout restart ds/nodelocaldns -n kube-system`(nodelocaldns 模式) 或 `systemctl restart dnsmasq`(systemd-resolved 模式)

---

## 8. 引用来源 / 权威证据

### 8.1 Private Google Access 概览
- 📘 **Private access options for services**: <https://cloud.google.com/vpc/docs/private-access-options>
  - 本文档 §2.1 直接引用 — 区分 "Google production APIs"(BQ)vs "VPC-hosted services"(Cloud SQL)的根本依据
  - Google 原文:
    > "Google APIs and services that run on Google's production infrastructure… might offer private
    > connectivity through Private Service Connect, Private Google Access, or both."
    > "VPC-hosted services… might offer private connectivity through Private Service Connect,
    > private services access, VPC Network Peering, or a combination of those options."

### 8.2 Private Google Access 配置 / Domain options
- 📘 **Configure Private Google Access**: <https://cloud.google.com/vpc/docs/configure-private-google-access>
  - §3.2 命令栈的依据
  - §2.3 IP / DNS 表格(`199.36.153.4/30` / `199.36.153.8/30`)的依据
- 📘 **Private Google Access overview**: <https://cloud.google.com/vpc/docs/private-google-access>
  - §2.2 关键事实 — "Private Google Access has no effect on instances that have external IP addresses"

### 8.3 PSC for Google APIs(alternative 选项,本文不用但可参考)
- 📘 **About Private Service Connect for Google APIs**: <https://cloud.google.com/vpc/docs/about-private-service-connect-google-apis>
  - 备选方案 — 给 `*.googleapis.com` 配 PSCEP,代替 `restricted.googleapis.com`
  - 本文选 PGA(更轻量),但客户场景如有 VPC-SC perimeter 内 LB 时可考虑 PSC

### 8.4 Workload Identity Federation for GKE(IAM 链)
- 完整 anchor 见 [`cross-project-bigquery-master-to-tenant.md`](./cross-project-bigquery-master-to-tenant.md) §13.1

### 8.5 BigQuery Access Control
- 完整 anchor 见 [`cross-project-bigquery-master-to-tenant.md`](./cross-project-bigquery-master-to-tenant.md) §13.2

### 8.6 VPC Service Controls
- 📘 **VPC Service Controls**: <https://cloud.google.com/vpc-service-controls/docs/overview>
  - `restricted.googleapis.com` 的强制项

### 8.7 Cloud SQL PSC 对照 reference
- 📘 **Cloud SQL Private Service Connect overview**: <https://cloud.google.com/sql/docs/mysql/about-private-service-connect>
  - 用来对照 §4.1 — 注意 BQ **不是** VPC-hosted,所以**不走 PSC**,走 PGA
- 📘 **PSC NetworkPolicy 3307 解释**: [`../psa-psc/psc-sql-flow-demo/k8s/why-psc-netpolicy-3307.md`](../psa-psc/psc-sql-flow-demo/k8s/why-psc-netpolicy-3307.md)
  - 设计原则 reference — 节点无 external IP + NetworkPolicy 显式 allow

---

## 9. 与本仓库既有文档的交叉

| 本文档概念 | 既有文档 |
|--|--|
| IAM 链(WI + dataset IAM)| [`cross-project-bigquery-master-to-tenant.md`](./cross-project-bigquery-master-to-tenant.md) §3-§4,**完整覆盖** — 本文档 §3 阶段 D 是摘要 |
| 方案对比矩阵 / 决策树 | 同上 §5 — 本文档 §5 是方案 6 的专门展开 |
| 反方向(tenant → master BigQuery)| 同上 §9 — 如果 tenant BI 反向 query master BQ,**网络侧同样适用 PGA** |
| Cloud SQL PSC 流程图 | [`../psa-psc/psc-sql-flow-demo/k8s/cloud-sql-proxy-psc-3307-debug-flow.html`](../psa-psc/psc-sql-flow-demo/k8s/cloud-sql-proxy-psc-3307-debug-flow.html) — 本文档 §4 借鉴其 3-zone 设计 |
| GKE Workload Identity | [`../gke/workload-identify.md`](../gke/workload-identify.md) — 同主题,但不覆盖跨项目 BQ |

---

## 10. 一句话原则

> 📌 **BigQuery 跨项目"private 访问"的官方推荐 = PGA + `restricted.googleapis.com`(`199.36.153.4/30`)。
> 不是 PSC — BQ 没有 PSC Service Attachment。**
>
> 配法一次性完成:subnet enable PGA + Cloud DNS zone wildcard CNAME → `restricted.googleapis.com` + A records,
> 再加 IAM 链(KSA → GSA + tenant dataset IAM),整个 master GKE → tenant BQ 流量全部走 Google internal IP,
> 不经过公网。
>
> 借鉴 Cloud SQL PSC 的"设计哲学"(节点无 external IP、NetworkPolicy 显式 allow、debug 信号可视化),
> 但**机制完全不同** — BQ 是 `*.googleapis.com` PaaS,Cloud SQL 是 VPC-hosted 服务。

---

## 11. 未验证 / 探索期假设

- [ ] **PGA + Cloud DNS 在 GKE Autopilot 集群的行为**:本文按 Standard 集群写;Autopilot 节点 IP 行为可能略有差异(待 verify)
- [ ] **Cloud DNS 私有 zone 的 SOA 记录**:本文没显式配 SOA,默认 Google 接管;**multi-VPC / multi-zone 时可能要 explicit SOA**
- [ ] **跨 region BQ endpoint(`eu-bigquery.googleapis.com`)在 restricted VIP 下的解析**:本文假设 wildcard 覆盖,但需验证 EU 区域 BQ endpoint 是否在 restricted 支持列表内
- [ ] **`restricted.googleapis.com` 对 BigQuery Storage API / BigQuery Connection Service 的支持**:Storage Read API 用 `bigquerystorage.googleapis.com`,需 verify
- [ ] **PGA + IPv6 only 节点**:本文按 IPv4 写,IPv6-only 节点需要 `2600:2d00:0002:1000::/56` 配套

---

✅ 全文完毕。配合 [`cross-project-bigquery-master-to-tenant.md`](./cross-project-bigquery-master-to-tenant.md)(IAM + 决策矩阵)
+ [`cross-project-bigquery-architecture.html`](./cross-project-bigquery-architecture.html)(可视化架构图)
一起使用,完整覆盖 master 项目 GKE → tenant 项目 BigQuery 的所有路径。
