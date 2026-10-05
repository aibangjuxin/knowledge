# 17 · DC 实战回填(第二轮)—— 有状态服务、跨区、身份与命名

> **接续 [`16-backfill-from-dc-experience.md`](./16-backfill-from-dc-experience.md)。**
> 第一轮扫了 `psa-psc/`、`secret-manage/`、`sql/`。
> **这一轮扫到了更深的两层** —— `gke/`、`cross-project/`,发现了**三条会改变 CaaS 架构判断**的事实。

---

## 1. 🆕 最重要的一条:GCP 服务分两类,私有访问路径完全不同

`cross-project/cross-project-bigquery.md` 记录了 GCP 官方的一段关键分类:

> **Google Cloud offers two types of services:**
>
> 1. **Google APIs and services that run on Google's production infrastructure** — 例:
>    **Google APIs, including those that have `*.googleapis.com` API service endpoints.**
> 2. **VPC-hosted services that run on Compute Engine VMs in VPC networks** — 例:
>    **Cloud SQL, Filestore, Memorystore for Redis**

| 服务类型                      | 例子                                                       | 私有访问方式                                                        |
| ----------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------- |
| **Google 生产基础设施 API**   | BigQuery、Cloud Storage、Compute Engine API、KMS、IAM      | **Private Google Access(PGA)+ `*.googleapis.com` private VIP**,或 PSC endpoints for Google APIs |
| **VPC-hosted 服务**          | **Cloud SQL**、Filestore、**Memorystore/Redis**              | **PSC Service Attachment**(producer 暴露)+ PSCEP(consumer 建);或 PSA / VPC peering |

> #### 🔴 这条对 CaaS 的影响很大
>
> **BigQuery 走 PGA,不走 PSC。** 因为它是 PaaS,Google 把它当"Google API"运营,
> **不暴露 producer VPC,所以没有 PSC Service Attachment 可以申请。**
>
> 而 **Cloud SQL / Redis 走 PSC**,因为它们是 VPC-hosted 服务。
>
> **对 CaaS 的三个具体后果:**
>
> | # | 后果                                                                 |
> | - | -------------------------------------------------------------------- |
> | 1 | **能力目录不能笼统写"支持 PSC"** —— 必须区分**哪类服务走哪条路**      |
> | 2 | **CaaS 的跨项目网络编排要处理两条独立路径**,不是一条                    |
> | 3 | **业务方常见误解**:以为所有 GCP 服务都能用 PSC 串起来                 |
>
> **建议写进 §8 的 `scope`**:`private_access_method: pga | psc | public`
> —— 这是一个新的、跨云也通用的建模维度(阿里云的对应物是内网访问 endpoint,AWS 是 VPC endpoint / PrivateLink)。

### 1.1 BigQuery 跨项目要"两条腿"同时具备

`cross-project-bigquery.md` 的架构图说明得很清楚:

```
Auth 侧(Workload Identity):  Pod(KSA) → GKE metadata → STS → impersonate master GSA
                              ↓
                        (GSA token 持有)
                              ↓
Network 侧(Private Google Access): *.googleapis.com private VIP
```

> **⚠️ 只有网络侧不通没有用 —— 因为 API 侧还要 IAM 授权。只有 IAM 没有私有 VIP,则流量走公网。**
>
> **这是一个典型的"看起来配置了一半,实际完全没生效"的场景。**
> CaaS 的合规检查如果只看一边,会给出错误的"已私有化"结论。
>
> **建议**:把"auth 侧 + network 侧双确认"作为 CaaS 的一项**联合检查**。

---

## 2. 🆕 PSC 跨 Region:两个 flag 缺一不可

`psa-psc/psc-cross-region.md` 记录了跨区 PSC 的完整规则:

| 场景                                           | 支持? | 关键配置                                                                                    |
| ---------------------------------------------- | ----- | ------------------------------------------------------------------------------------------- |
| Consumer 与 Producer 同 Region                | ✅    | 标准 PSC 配置即可                                                                            |
| Consumer 与 Producer **跨 Region**            | ✅    | Producer ILB 开 `--allow-global-access` **+** Consumer Endpoint 开 `--allow-psc-global-access` |
| VPN/Interconnect 访问跨 Region Producer       | ✅    | Consumer Endpoint 开 `--allow-psc-global-access`                                            |
| **VPC Peering 访问跨 Region Producer**        | ❌    | **PSC 流量不支持跨 VPC Peering 传递**                                                        |

### 2.1 两个 flag 极易混淆

| 开关                              | 层级                          | 作用方向                          |
| --------------------------------- | ----------------------------- | --------------------------------- |
| `--allow-global-access`          | ILB Forwarding Rule(Producer) | 允许跨 Region 流量**进入** SA      |
| `--allow-psc-global-access`      | PSCEP Forwarding Rule(Consumer)| 允许跨 Region VM **使用**该 Endpoint |

> **两个 flag 名字极像,方向相反,必须两端同时开。漏一个就不通 —— 而且症状是"能建但连不上",非常难排查。**

### 2.2 补上了 `16` 里 D6 的另一个论据

`16` 说 D6(网络底座不进 CaaS 权限)是对的,论据是 proxy-only subnet 单点。
**这一轮又多一条**:

> **PSC 流量不支持跨 VPC Peering。** 这意味着 DC 的 Hub-Spoke 拓扑
> **不是"能用就行"的结构,而是 PSC 能工作的前提条件。**
>
> **如果有人提议把 Hub-Spoke 改成 VPC Peering 拓扑以简化,会直接导致 PSC 全面失效。**
>
> **这是一个"看起来是架构优化,实际会打断全链路"的决策 —— 值得写进 §14 决策记录。**

**建议新增 D10**:
> `跨项目网络采用 Hub-Spoke + PSA/PSC 拓扑,不使用 VPC Peering。
> 理由:PSC 流量不支持跨 VPC Peering 传递。`

---

## 3. 🆕 Redis 走 PSC,不是 PSA

`psa-psc/psc-Redis.md`(716 行)证明 **Memorystore for Redis 是 VPC-hosted 服务,走 PSC**:

```
Producer 项目(Redis 提供者)          Consumer 项目(应用)
├── 创建 VPC                         ├── 创建 VPC + 应用
├── 创建 Redis 实例                  ├── 创建 PSC Endpoint
├── 启用 Private Service Connect     ├── 内部 IP 连接,无需公网
├── Redis 自动创建服务附件           └── 配置防火墙规则
└── 配置授权的 Consumer 项目
```

**注意一个易错点**:**Redis 是"自动创建服务附件"**,不像 Cloud SQL 需要手工建 ILB + Service Attachment。

> **这意味着 Cloud SQL 和 Redis 的 CaaS 编排流程不同。**
> 如果 CaaS 把两者当同一种"有状态服务"处理,会在 Redis 上多出不必要的人工步骤。
>
> **建议**:能力目录里有状态服务维度要**按服务逐个列**,不要写"有状态服务:走 PSC"就完事。

### 3.1 Redis 的第二个瓶颈:连接数

和 Cloud SQL 同理 —— **Redis 有 `maxmemory` 与最大客户端连接数**,
而几十个集群共享一个实例时同样是共享池。

> 加上 `16` 里的 N4(有状态服务连接数预算),我建议把 N4 扩展为:
> **N4 · CaaS 的容量模型是否覆盖对 Cloud SQL / Memorystore 的连接数预算?**
> —— 两类服务的限制维度不同(数据库看 `max_connections`,Redis 看连接数 + `maxmemory`),
> 但**都是跨集群共享**,所以是同一个架构问题。

---

## 4. 🆕 Workload Identity:你的知识库有一份"它不做什么"的清单

`gke/workload-with-annotate.md` 记录了 namespace 的 Pod Security label,并明确划清了边界:

> ### 它不做什么
> - 不给 Pod GCP 权限
> - **不影响 Workload Identity**
> - 不决定 Pod 能否访问 Secret Manager
> - 不负责 image pull 的认证
>
> 它只管:**这个 Pod 的安全姿态是否允许进入这个 namespace。**

### 4.1 为什么这条对 CaaS 有价值

**这是一份"职责边界"清单,不是一份"能力清单"。**

CaaS 在实现安全基线时,极容易把 Pod Security label、Workload Identity、
image pull secret、Secret Manager 访问**混为一谈**,以为打了 label 就全都受控了。

> **建议**:把这份"不做什么"清单直接交给安全架构师,
> 作为 §11 控制项映射时**避免误判**的依据。
>
> **这是你已经有的、别人大概率没有的东西** —— 一份实测过的职责边界。

### 4.2 Pod Security Standard 的档位

同一份文档提到 `pod-security.kubernetes.io/enforce=baseline`:

| 档位      | 含义                                        |
| --------- | ------------------------------------------- |
| privileged | 无限制(不要用)                            |
| **baseline** | 阻止已知的提权路径,**大多数工作负载无需改动** |
| restricted | 最严格,**多数工作负载需改**                 |

> **对 CaaS 的意义**:不同档位对应不同的"改造成本"。
> 选 `baseline` 是绝大多数业务的可接受点;直接上 `restricted` 会让接入门槛陡增。
>
> **建议在 §9 的准入画像里把 Pod Security 档位作为一个"可协商默认值"**,
> 而非全局强制一个档位。

---

## 5. 🆕 GAR:你的实际用法是"多区域 pkg.dev 端点"

`cloud-run/` 和 `psa-psc/psc-sql-flow-demo/` 里出现的镜像地址模式:

```
europe-west2-docker.pkg.dev/project/containers/my-agent:latest
gcr.io/${PROJECT_ID}/db-app:latest
```

| 观察                             | 对 CaaS 的意义                                        |
| -------------------------------- | ----------------------------------------------------- |
| **同时用 GAR(`*.pkg.dev`)和 GCR** | Binary Authorization 需覆盖**两个** registry           |
| **GAR 端点带 region 前缀**        | 镜像仓库的**物理位置跟随 region** —— 跨 region 拉取有延迟/出网成本 |
| 实践中大量用 `:latest`           | ⚠️ **与生产可复现性冲突** —— CaaS 若要强制 tag 策略,会撞上 |

> #### 🔴 两条要写进能力目录的
>
> **① Binary Authorization 覆盖面**
> 我在 `03` 里写的是"仅覆盖 GCR / Artifact Registry" —— **实证是对的**,
> 但更精确的表述是:**需要分别配置 GCR 和 GAR,且 GAR 有多区域端点需要选择。**
>
> **② `:latest` 的使用习惯**
> 你的实证里大量使用 `:latest`。这与"生产集群应该用不可变 tag + digest"直接冲突。
>
> **这不是能力问题,是治理问题** —— 但它会在 CaaS 纳管时浮出来:
> 存量集群全是 `:latest`,CaaS 的准入画像如果要求不可变镜像,**几十个集群会集体不合规**。
>
> **建议**:在 §9.1 准入条件里明确——**存量集群的镜像引用规范不作为 BYOC 硬门槛**,
> 但新集群默认强制 digest。否则你会自己把 BYOC 卡死。

---

## 6. 🆕 Cloud Run:它和 CaaS 是什么关系?

`cloud-run/` 有 15+ 篇,包括一个完整的 **onboarding 证书签发流水线**(Cloud Run Job + GCS + Terraform)。

**这引出一个 CaaS 必须回答的问题**:

> **Cloud Run 上的工作负载,归不归 CaaS 管?**

| 立场              | 含义                                    | 影响                                       |
| ----------------- | --------------------------------------- | ------------------------------------------ |
| **A. 归 CaaS**    | Cloud Run 是一种"无集群的部署形态"     | 能力目录要加一个"Serverless"模式维度       |
| **B. 不归**      | CaaS 只管 K8s 集群                       | 但你已经有 Cloud Run 流水线,边界要写清楚   |
| **C. 灰色**      | 独立管理,但共用身份/密钥/网络底座       | 边界最复杂,但最可能符合你的现实            |

> **我的判断:选 C,且必须写进 RFC。**
>
> 理由:你的 Cloud Run onboarding 流水线**已经在用** GCS + Secret Manager + Workload Identity
> —— 这些和 CaaS 共用。**如果 RFC 完全不提 Cloud Run,这些共用资源就没有归属方。**
>
> **建议新增开放问题 N7**:
> `CaaS 的覆盖范围是否包含 Cloud Run 等 serverless 形态?
> 若不包含,其与 CaaS 共用的身份、密钥、网络底座由谁治理?`

---

## 7. 本轮回填汇总

| # | 发现                                          | 来源                                    | 对 CaaS 的影响                |
| - | --------------------------------------------- | --------------------------------------- | ----------------------------- |
| 1 | **GCP 服务分两类,私有访问路径不同**            | `cross-project-bigquery.md`             | 🆕 能力目录需 `private_access_method` 维度 |
| 2 | **BigQuery 跨项目要 auth + network 双腿**       | 同上                                    | 🆕 需联合检查,否则误判"已私有化" |
| 3 | **PSC 跨区要两个 flag,缺一不可**                | `psc-cross-region.md`                   | 🔶 运维易错点                 |
| 4 | **PSC 不支持跨 VPC Peering**                   | 同上                                    | 🆕 **D10:Hub-Spoke 是 PSC 前提**  |
| 5 | **Redis 走 PSC 且自动建 SA**                   | `psc-Redis.md`                         | 🆕 有状态服务需按服务逐个建模   |
| 6 | **Workload Identity 的"不做什么"清单**         | `gke/workload-with-annotate.md`        | 🆕 防止 §11 误判控制项         |
| 7 | **Pod Security 三档位**                        | 同上                                    | 🆕 准入画像应可协商             |
| 8 | **GAR + GCR 双 registry,多区域端点**          | `cloud-run/`、`psc-sql-flow-demo/`     | 🔶 Binary Auth 覆盖面          |
| 9 | **大量使用 `:latest`**                        | 同上                                    | ⚠️ **会让 BYOC 批量不合规**    |
| 10| **Cloud Run 存在且已投产**                     | `cloud-run/onboarding/`                | 🆕 **N7:CaaS 覆盖范围待定**    |

### 7.1 新增的决策与开放问题

| ID  | 内容                                                                   | 性质 |
| --- | ---------------------------------------------------------------------- | ---- |
| **D10** | 跨项目网络采用 Hub-Spoke + PSA/PSC,**不使用 VPC Peering**(PSC 不支持跨 peering) | 决策 |
| **N7**  | CaaS 是否覆盖 Cloud Run 等 serverless 形态?共用的身份/密钥/网络由谁治理? | 开放问题 |
| **N4 扩展** | 容量模型覆盖 Cloud SQL **和** Memorystore 的连接数预算              | 开放问题 |

---

## 8. 关于"GCP 当模板"的阶段判断

两轮回填后,我的判断更明确了:

| 维度           | 状态                                                        |
| -------------- | ----------------------------------------------------------- |
| **schema**     | ✅ 完成(15 号文件,跨云复用)                                 |
| **提问集**     | ✅ 完成(15 号文件 20 维)                                    |
| **GCP 填表**   | 🟡 **约 70% 有实证** —— 网络/身份/有状态已扎实,加速器/合规仍待补 |
| **实证密度**   | 🟢 显著提升 —— 从"推演"变成"我环境里在用"                  |

> **还差的 30% 大致是**:
> - GPU / Vertex AI 的实际用法(有 `vertex-ai/byoc-*.md` 但我还没细读)
> - 可观测性(Cloud Logging / Monitoring 在你这套架构里的实际用法)
> - 成本与配额的实际数值
> - 合规控制项的实际映射
>
> **这四块里,前三块可以再扫一轮知识库,第四块要找安全架构师。**

---

## 9. 一条元观察

两轮回填下来,一个规律很清楚:

> **你最独特的价值不在于"知道 GCP 支持什么",而在于"知道你这套架构里哪些地方会连着一起坏"。**

比如:
- proxy-only subnet 改一个 → 该 VPC 该 region 所有集群的入口都断
- Hub-Spoke 改拓扑 → PSC 全面失效 → 所有跨项目访问断
- Cloud SQL 连接池打满 → **报的是"性能下降"**,没人知道是共享池满了

**这些都不是能力目录能表达的**,它们是"这个组织的架构知识"。

> **所以对 RFC 最重要的是第 4 点(职责边界清单)和第 2 点(双腿检查)——
> 它们是"怎么做对"的隐性知识,不是"能不能做"的显性知识。**

---

**修订记录**

| 日期       | 内容                                                          |
| ---------- | ------------------------------------------------------------- |
| 2026-09-29 | 初版。扫 `gke/`、`cross-project/`、`cloud-run/`,发现 10 条     |
