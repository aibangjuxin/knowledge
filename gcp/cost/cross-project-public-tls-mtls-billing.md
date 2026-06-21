# Cross-Project × Public TLS / mTLS 服务暴露的 GCP 计费深度分析

> **Scope**: 这是一份**通用计费原则报告**。不针对任何特定工程实例,只回答"如果你的工程同时具备
> (1) 跨 GCP Project、(2) 通过 Public TLS 或 mTLS 暴露服务、(3) 涉及 PSC,
> 这套架构会产生哪些 SKU、费用落在哪一侧、长期运行的月费结构如何"。
>
> **数字来源分层**(诚信标注):
> - `[kb]` = 用户知识库 `gcp/psa-psc/psc-with-vpc-peering-quota-cost.md` 等已有数字(Aug 2025 版,仅作历史基线)
> - `[log]` = 用户知识库 `gcp/cost/gcp-cost/gcp-log-cost.md` 等日志成本数字
> - `[std]` = GCP 公开定价页长期稳定基线(industry-standard baseline,2024-2026 多源对照)
> - `[live]` = **Cloud Billing Catalog API 实时拉取**(脚本见 §8)— 这是生产决策唯一可信源
>
> **本文不替代实时定价**。所有 `[std]` 数字在生产报告里都应该走 §8 脚本重新拉一次。

---

## 0. 30 秒 TL;DR

一个长期运行的"Cross-Project × Public TLS / mTLS"服务,典型月费用结构(同区域、稳态):

| 类别 | 估算月费占比 | 谁付钱 |
|---|---:|---|
| **L7 LB Envoy 代理实例** (GLB / INTERNAL_MANAGED) | **30-55%** | Consumer side(挂 PSC NEG 或被挂的 BS 所在 project) |
| **LB 数据处理费** (per GB, ingress + egress 都算) | 15-30% | Consumer side |
| **Cloud Logging**(尤其 LB 日志 / Cloud Audit Logs) | 10-25% | **每个 project 各自付自己的** |
| **Forwarding Rules 小时费** (5 条后开始叠加) | 3-8% | 各自付各自的 |
| **PSC Endpoint + 数据处理**(若走 PSC) | 5-15% | Consumer 付, Producer 不付 |
| **Cloud Armor**(Standard / Managed Plus) | 0-10% | 各自付各自的 |
| **证书**(Self-managed / Google-managed / Certificate Manager) | 0-2% | 通常 Consumer 付 |
| **Egress**(若暴露公网服务,有下行到 Internet 的流量) | 0-50% | Consumer 付(公网 LB 所在 project) |

**三个最容易爆的隐形雷**:
1. **L7 Envoy 代理实例** — GLB / INTERNAL_MANAGED / ILB 一旦 create+ENABLED,**按小时计费持续到 delete**。"暂停"=删 LB,不是 stop instance。
2. **Cloud Logging LB logs 默认开启** — URL map 访问日志每条请求都写, 高 QPS 服务的日志量很容易 >100GB/天,$50/天 起步。
3. **Forwarding Rule 阶梯价** — 前 5 条免费,但**是按 region 计**;只要某 region 有 6+ 条就开始每条 $0.025/hr ≈ $18/月。

---

## 1. 资源模型与计费归属

### 1.1 三种典型架构拓扑

**A. PSC NEG 模式(Cross-Project,推荐)**
```
[Internet] → [Consumer Project: GLB / ILB / mTLS LB]
                          │ PSC NEG
                          ▼
                   [PSC Endpoint (consumer)]
                          │
                          │  (跨 project traffic)
                          ▼
                   [Producer Project: Service Attachment]
                          │
                          ▼
                   [Producer: MIG / GKE / Cloud Run]
```

**B. Service Attachment direct (Cross-Project,Internal only)**
```
[Other Project] → [Producer Project: ILB]
                       │
                       ▼
                  [Consumer: PSC Endpoint → 直接挂 BS/MIG]
```

**C. Self-hosted mTLS in cluster(不依赖 GLB mTLS,Sidecar/Istio)**
```
[Internet] → [Consumer Project: GLB (TLS termination)]
                       │ (in-VPC HTTP)
                       ▼
                  [GKE Pod (Istio sidecar: mTLS to backend)]
                       │
                       ▼
                  [Producer: backend pod]
```

**计费边界判定规则**:
- **"谁创建"这个资源,这个 project 的账单就记** — 这是 GCP 的唯一规则。SKU 写在 `usage.unit` 里(`pib/month`, `hour`, `gib`),`project.id` 是计费载体。
- 跨 project 流量通过 PSC 时:**Consumer 一侧**全部付 PSC 数据费 + Endpoint 小时费;**Producer 一侧不付 PSC 相关费用**,只付自己 LB / MIG / Compute / Logging。
- LB 数据处理费: **跟随 LB 所在 project 付**,不管请求来自哪。
- Logging: **每个 project 各自付自己的日志量**(即使同一个请求的日志可能跨 project 各产一份)。

---

## 2. Forwarding Rules(F Rules)— 计费基石

### 2.1 SKU 与小时费

| Scheme | Scope | 小时费 | 数据处理费 | 备注 |
|---|---|---:|---:|---|
| `EXTERNAL` | Global | $0.025/hr `[kb]` | Premium tier egress 单独计 | 经典 L4 网络 LB |
| `EXTERNAL_MANAGED` | Global / Regional | $0.025/hr `[kb]` | $0.008-$0.025/GB `[std]` | Global External HTTPS LB 走这个 |
| `INTERNAL` | Regional | $0.01/hr `[std]` | 同区域免费 | L4 ILB |
| `INTERNAL_MANAGED` | Regional | $0.025/hr `[kb]` | $0.008/GB `[kb]` | L7 ILB(Regional Internal Application LB) |
| `INTERNAL_TCP_UDP` | Regional | $0.01/hr `[std]` | 同区域免费 | L4 ILB TCP/UDP |

### 2.2 Forwarding Rule "前 5 条免费" 的真相

GCP 文档常写"前 5 条 forwarding rules per project per region 免费",但实际:
- **是按 "loadBalancingScheme × scope" 分组的前 5 条免费**,不是总数
- 例:`EXTERNAL_MANAGED` 一个 scheme 占一个 bucket,该 bucket 前 5 条免费;`INTERNAL_MANAGED` 另一个 bucket,前 5 条免费
- 真实账单里: GLB 链条 7-10 条 FR 的 project,通常 2-5 条已经在付费

**月费估算**(720 hr):
| 条数 | 月费 |
|---:|---:|
| 1-5 条 / scheme / region | **$0** |
| 第 6 条起 | +$18/条/月 |
| 12 条 | +$126/月(单 scheme 单 region)|

**应对**:
- 删除测试用 FR(很多 "我先建一个看看" 的 FR 在跑生产时仍然保留)
- 多个 LB 共用 FR 的设计 → 用 host rule(URL map) + single FR,不要 "每个域名一个 FR"
- 用 `gcloud compute forwarding-rules list --format='table(name,loadBalancingScheme,region,target)'` 列清单,挑出可合并的

---

## 3. L7 LB Proxy Instance(Envoy)— 隐形大魔王

### 3.1 为什么单独列

`EXTERNAL_MANAGED` / `INTERNAL_MANAGED` 这两类 L7 LB,因为要做 TLS termination / URL routing / header injection / mTLS handshake,**每个 FR 背后都会拉 1 个或多个 Envoy 代理实例**,按小时计费。

### 3.2 SKU

| LB 类型 | Envoy 实例费 | 数据处理费 |
|---|---|---:|
| **Regional Internal Application LB** (`INTERNAL_MANAGED`) | **~$0.025/小时 ≈ $18/月/实例** `[std]`(不同文档报 $0.013-$0.025,差 2 倍) | $0.008/GB |
| **Global External Application LB** (`EXTERNAL_MANAGED` global) | **~$0.035-$0.045/小时 ≈ $25-32/月/实例** `[std]`(Global 比 Regional 贵) | $0.025/GB |
| **Regional External Application LB** (`EXTERNAL_MANAGED` regional) | ~$0.035/小时 | $0.008-0.025/GB |

### 3.3 真实账单复盘(Lex 2026-06-20 工程 `aibang-12345678-ajbx-dev` europe-west2)

| 来源 | L7 Envoy 月费 |
|---|---:|
| `Networking $63.92`(其中 ~55% 是 Envoy) | **~$35/月** |
| 反推: 2 条 INTERNAL_MANAGED L7 ILB × $17.71/月 ≈ $35 | ✓ 匹配 |

**关键事实**: 这 $35 是"上班了"才收的。LB `ENABLED` = Envoy 拉起 = 按小时开始计费。**`stop-migs.sh` 停 instance 没用,删 LB 才停**。

### 3.4 mTLS / Server TLS / Client TLS 是否增加 Envoy 实例?

**默认不会**。但:
- **`--mtls-policy` / `ServerTlsPolicy`** 是 metadata + caCert,proxy 复用同一个 Envoy 实例处理,**不增加实例费**
- **Cloud Armor Managed Protection Plus**(防 bot/anti-DoS) 在大流量场景下可能拉更多 proxy 实例,**间接增加 $**
- **TrustConfig + ClientTlsPolicy** 同上,纯策略,不增加实例

**容易踩的坑**: 改了 `--mtls-policy` 之后,有些人觉得"应该会重启 Envoy",实际不会。但 mTLS handshake 比 plain TLS 慢 20-50%,**数据处理费(按 GB)不会变,但 QPS 会下降 → 实际用户体验变差**。

---

## 4. 数据处理费(Data Processing)— 跟流量走的隐形大头

### 4.1 三类计费点

| 类型 | 计费方向 | 触发场景 |
|---|---|---|
| **LB Data Processing** | **入 + 出都算** | 任何流量经过 L7 LB / L4 LB |
| **VPC Egress(同区域免费,跨区域收费)** | 出向 | Consumer 在 A region,Producer 在 B region |
| **Internet Egress(Premium tier)** | 出向 | 公网 GLB 响应下行到 Internet 客户端 |

### 4.2 跨 project 流量在 PSC 模式下的计费细节

| 流量方向 | 计费 | 哪个 project |
|---|---|---|
| Internet → Consumer GLB | Premium Egress 按目的地计 | Consumer |
| Consumer GLB → PSC NEG → Producer SA | **PSC Data Processing**(consumer endpoint 端计) | Consumer |
| Producer SA → Backend (Producer VPC 内) | **Producer LB 数据处理**(如果 producer 也有 LB) | Producer |
| Backend → Client response (走同样路径回) | 反向同理 | 同上 |

**关键: PSC Endpoint 的数据处理费是 0.01/GB tier-1 阶梯计价**(知识库 `[kb]` 数字)。

### 4.3 Premium vs Standard Network Tier

| Tier | 适用 | 同区域 | 跨区域 |
|---|---|---|---|
| **Premium** | 默认 | 免费 | $0.02-$0.12/GB(随距离) |
| **Standard** | 需要显式 opt-in,适合批量数据 | $0.01/GB 内部 | 较低 |

**默认是 Premium**。如果你的流量是 "Client → Internet → GLB → Producer backend",下行到 Internet 的部分走 Premium tier,通常 $0.12-$0.23/GB(随客户端地理位置)。

### 4.4 公网 GLB 的下行费陷阱(被反复忽略)

**Internet → Cloud LB 是免费的**,但 **Cloud LB → Internet(响应)** 按 Premium tier 算,且**任何 HTTPS 响应都算**。

例: 一个 API 服务,平均响应体 50 KB,QPS 100,日 PV 8.64M,响应数据 432 GB/天 = 12.96 TB/月。
- 按 US/Europe → Asia $0.12/GB 计: **$1555/月 仅下行费**
- 按 US → US $0.02/GB 计: $259/月

**优化**:
- 客户端缓存(ETag / Cache-Control)
- 响应压缩(gzip / br)— 减少 60-80% 流量
- 选对 region(不要 Global LB 跨洲转发)
- 用 Tiered Caching / CDN-like 缓存层(不在 GLB,但前面加)

---

## 5. Private Service Connect(PSC)— Consumer / Producer 分账原则

### 5.1 计费归属表(来自知识库 `[kb]`,Aug 2025 基线)

#### Consumer 端费用

| 费用项 | 价格 `[kb]` | 计费单位 | 备注 |
|---|---|---|---|
| PSC Endpoint 小时费 | **$0.01** | 每小时/每个端点 | 不分 published service 还是 Google API |
| PSC 数据处理(0-1 PiB) | **$0.01/GiB** | 每 GiB | **入 + 出都算** |
| PSC 数据处理(1-5 PiB) | $0.006/GiB | 阶梯 | 同一 project 月累计 |
| PSC 数据处理(>5 PiB) | $0.004/GiB | 阶梯 |  |
| 跨区域传输(Global Access) | $0.02-$0.12/GB | 跨 region | **仅 Consumer 单方付** |
| 跨 Zone 传输 | $0 | - | PSC Endpoint 流量在同区域内跨 Zone 不收费 |

#### Producer 端费用

| 费用项 | 价格 | 备注 |
|---|---|---|
| Service Attachment | **$0** | PSC 本身不收费 |
| Producer LB / MIG / Compute | 正常计费 | 与 PSC 无关 |
| 跨区域传输 | **$0** | **Producer 不付**跨区传输费 |

### 5.2 关键决策:跨区域用 PSC 还是 VPC Peering?

知识库 `[kb]` 已对比,核心结论:
- **跨区域同区域**: PSC + 数据处理费 vs Peering + 免费 → **VPC Peering 便宜**($8/月 vs $137/月)
- **跨大洲**: PSC(Consumer 单付)vs Peering(双向付)→ **PSC 便宜**($137/月 vs $240/月)
- **IP 重叠要求**: PSC 支持,VPC Peering 不支持

### 5.3 PSC NEG 模式 vs 直接挂 Service Attachment 模式

| 模式 | 适用 | 计费差异 |
|---|---|---|
| **PSC NEG**(BS 引用 PSC NEG) | GLB / GKE-based LB 链 | LB 数据处理 + PSC 数据处理 **双重计费** |
| **直接 PSC endpoint → BS** | 简化场景 | 同上,但少一层 forwarding rule |
| **跨 project 但同 VPC(Shared VPC)** | 用 PSC 反而绕弯 | **VPC Peering / Shared VPC 不收费** |

**关键 insight**: PSC NEG 模式下,请求经过 LB(GLB 数据费)再通过 PSC(PSC 数据费)— **同一字节可能被计两次**。这就是为什么跨 project LB + PSC 的工程,**数据费总是比想象的贵**。

---

## 6. Cloud Logging — 你提到的"日志大头"

### 6.1 定价基线(知识库 `[log]`)

| 项目 | 价格 | 备注 |
|---|---|---|
| **注入(Ingestion)** | **$0.50/GiB** | 标准日志,含 30 天默认索引 + 查询能力 |
| 存储 >30 天(Retention) | **$0.01/GiB/月** | 月度累加 |
| 免费配额 | **每 project 50 GiB/月** | 默认 `_Default` 桶前 50GB 免注入费 |
| Admin Activity Audit Logs | 强制保留 **400 天** | 不可改 |
| Data Access Audit Logs | 默认 30 天 | 可调,但开启即付费 |

### 6.2 跨 project 工程的日志费分布

每个 project **各自付自己的日志**,所以跨 project 工程有"日志费被分散"的效果 — 但单看每个 project,**LB 日志 + Audit Logs 经常是单 project 第二大成本**(仅次于 L7 Envoy)。

### 6.3 三大日志源(按"体积 × 单价"算成本)

| 日志源 | 典型体积 | 单价 | 月费估算(100 QPS) |
|---|---|---|---:|
| **LB Access Logs(URL map 日志)** | 高(每请求 1 行) | $0.50/GiB | **$200-500/月**(看 detail level) |
| **Cloud Audit Logs(Admin Activity)** | 中(每个 admin op) | 免费(SIEM 类目) | $0 |
| **GKE / 容器 stdout** | 极高(高频 + debug log) | $0.50/GiB | **$100-1000+/月** |
| **VPC Flow Logs** | 极高(每个 flow 记录) | $0.50/GiB | **$500+/月**(常被忽略) |
| **Cloud Armor Logs**(开启 logging) | 高 | $0.50/GiB | **$50-200/月** |

### 6.4 跨 project 工程的日志特别注意点

1. **Producer 写 access log 到自己 project,但请求是 Consumer 的** — Producer 的 LB 日志量跟 Consumer 的 QPS 直接相关。Producer 在自己 project 看到"日志量暴涨",很可能不是 producer 自己的 QPS, 而是 consumer 在放大。
2. **Audit Logs 跨 project 视角不同** — `aibang-consumer` 项目的 admin 操作产生的 Audit Log 计入 `aibang-consumer`,而不是 billing account。这对"哪边付日志费"的判定很重要。
3. **Log Sink 可以跨 project 导出** — 设 `_Default` sink 把 Producer 日志全部转到一个 centralized project,可以统一归档,但**仍然每个 project 付自己的注入费**(只是 storage 集中了)。

### 6.5 节省策略

| 策略 | 节省 |
|---|---|
| **关闭不必要的 Access Log**(Detail = NONE) | 60-90% LB 日志量 |
| **VPC Flow Logs**: 采样率从 1.0 降到 0.1 | 90% |
| **Log exclusion**: GKE 排除 `kube-system` `nodejs` 等 verbose 日志 | 50%+ |
| **Log-based metrics only**: 用 metric 替代日志查询(几乎免费) | 90%+ on 那些只用来查的日志 |
| **Default 桶 50GB 配额用完就停**: 把次要日志路由到 GCS Bucket, 直接写 GCS($0.02/GB) 不走 Logging | 70-80% |

---

## 7. Cloud Armor、证书、Cross-Project 额外项

### 7.1 Cloud Armor(挂在 LB 上的安全策略)

| SKU | 价格 `[std]` | 计费 |
|---|---|---|
| Standard policy | **$5/月/policy** | 每个 attached policy |
| Managed Protection Plus | **$25/月/policy + $0.003/1000 req** | 攻击防护型 |
| Adaptive Protection(ML) | $0.00025/请求 | 异常检测 |
| Rule evaluation cost | 通常 $0 | 部分高级规则按请求计 |

**关键**: Cloud Armor 经常被"附加"而不是"删除" — 测试时附加后没摘下来。`gcloud compute backend-services describe` 看 `securityPolicy` 字段,有就摘。

### 7.2 证书(Certificate Manager / SSL Cert / mTLS)

| 类型 | 价格 | 计费 |
|---|---|---|
| Google-managed SSL(Public cert) | **$0** | 自动续期 |
| Self-managed SSL cert | **$0** | 自管 |
| Certificate Manager(trust store / mTLS) | **$0** | 仅元数据 |
| Server TLS Policy / Client TLS Policy | **$0** | 配置,不计费 |
| Trust Config(CA bundle) | **$0** | 配置 |

**证书基本不直接花钱**,但**注意 renew 操作如果启用了 LB 日志 detail=HIGH,会有大量 renew 事件**。

### 7.3 其他常被忽略的隐性 SKU

| 项 | 价格 | 触发 |
|---|---|---|
| Cloud DNS(每个 zone) | $0.20/zone/月 + $0.40/百万 query | 任何用 Cloud DNS 的工程 |
| Static IP(Reserved,未使用) | **$7.32/月/IP** | 静态 IP 即使没绑 LB 也在收 |
| Static IP(in-use) | **$0** | 绑定到 FR 就免费 |
| Snapshot / Disk(不删) | 按 GB/月 | EBS-like |
| Cloud NAT(allocate 但未用) | $0.045/hr = $32/月 | NAT gateway 创建即开始计费 |

---

## 8. 实时定价拉取脚本(唯一生产可信源)

GCP 公开的 **Cloud Billing Catalog API** 是**唯一**官方授权的实时定价 API。下面是立即可跑的 bash 脚本:

```bash
#!/usr/bin/env bash
# fetch-gcp-pricing.sh — pull current SKU pricing from Cloud Billing Catalog API
# Run any time you need accurate numbers; output is JSON.
# Requires: gcloud auth (user) + billing account read permission.
set -euo pipefail

# Get an access token
TOKEN=$(gcloud auth print-access-token)

# The catalog API has /v1/services for all GCP services
curl -sL \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "https://cloudbilling.googleapis.com/v1/services?pageSize=200" \
  | jq '.services[] | select(.displayName | test("Compute|Networking|Logging|Armor"; "i")) | {id: .serviceId, name: .displayName}' \
  > /tmp/gcp-services.json

# Pick "Compute Engine" (most networking SKUs are here)
# Fetch the SKUs — filter for forwarding rules / LB / proxy / egress
SVC_ID=$(jq -r '.[] | select(.name=="Compute Engine") | .id' /tmp/gcp-services.json)
curl -sL \
  -H "Authorization: Bearer $TOKEN" \
  "https://cloudbilling.googleapis.com/v1/services/${SVC_ID}/skus?pageSize=5000" \
  | jq '.skus[] | select(
      (.description | test("Forwarding Rule|Load Balancing|Envoy|Proxy|GIGABYTE|egress"; "i")) and
      (.category.resourceFamily == "Compute")
    ) | {
      sku: .skuId,
      desc: .description,
      service_region: .serviceRegions[0],
      unit: .pricingInfo[0].pricingExpression.usageUnit,
      rate_usd: .pricingInfo[0].pricingExpression.tieredRates[0].unitPrice.units,
      nanos: .pricingInfo[0].pricingExpression.tieredRates[0].unitPrice.nanos
    }' \
  > /tmp/gcp-network-skus.json

# Quick view
echo "=== Forwarding rules ==="
jq 'select(.desc | test("Forwarding Rule"; "i"))' /tmp/gcp-network-skus.json
echo "=== Load Balancing (data processing) ==="
jq 'select(.desc | test("Load Balancing.*[Gg]igabyte|GIGABYTE"; "i"))' /tmp/gcp-network-skus.json | head -40
echo "=== Proxy / Envoy ==="
jq 'select(.desc | test("Envoy|Proxy|Hour.*proxy"; "i"))' /tmp/gcp-network-skus.json
echo "=== Egress ==="
jq 'select(.desc | test("Egress|Internet"; "i"))' /tmp/gcp-network-skus.json | head -20
```

或者直接查 BigQuery 公开数据集(已 cache 在 Google 的 public dataset):

```sql
-- In BigQuery console: project = bigquery-public-data
SELECT
  service.description AS service,
  sku.description AS sku,
  pricing.unit_price,
  pricing.currency_code,
  pricing.unit_of_measure
FROM `cloud-pricing-public.cloud_pricing_export.skus` AS sku,
     UNNEST(sku.pricing) AS pricing
WHERE
  (sku.description LIKE '%Forwarding Rule%'
   OR sku.description LIKE '%Load Balancing%'
   OR sku.description LIKE '%Envoy%'
   OR sku.description LIKE '%Service Connect%'
   OR sku.description LIKE '%Armor%')
  AND pricing.currency_code = 'USD'
ORDER BY service.description, sku.description;
```

---

## 9. 长期运行的月费估算模型

### 9.1 输入参数(用 §8 脚本拉到的实际值替换)

```yaml
# billing-model-cross-project-public-tls-mtls.yaml
# Replace [std] values with results from §8 scripts.

project_consumer:
  load_balancers:
    - scheme: EXTERNAL_MANAGED   # 公网 GLB
      count: 1
      forwarding_rule_hourly: 0.025    # [std]
      data_processing_per_gb: 0.025    # [std]
      envoy_instance_hourly: 0.040     # [std] (Global LB 比 Regional 贵)
      expected_gb_per_month: 5000      # 5 TB / 月
    - scheme: INTERNAL_MANAGED    # 内部 mTLS LB
      count: 2
      forwarding_rule_hourly: 0.025    # [kb]
      data_processing_per_gb: 0.008    # [kb]
      envoy_instance_hourly: 0.025     # [std]
      expected_gb_per_month: 200

  psc:
    endpoints:
      count: 3
      hourly: 0.01                    # [kb]
      data_per_gb: 0.01               # [kb] (1st tier, 0-1 PiB)
      expected_gb_per_month: 5000

  cloud_armor:
    policies: 2
    hourly_per_policy: 0.005          # $5/mo ÷ 720h ≈ $0.007

  static_ips:
    reserved_unused: 1                # ⚠️ $7.32/月
    in_use: 5

  logging:
    monthly_gb: 200                   # LB 日志 + GKE 日志 + Audit
    retention_days: 30
    free_quota_gb: 50                 # [log] 默认

  certs:
    google_managed: 2
    self_managed: 0
    certificate_manager: 1
    trust_config: 1

  dns:
    zones: 1
    queries_millions: 5

project_producer:
  load_balancers:
    - scheme: INTERNAL              # ILB TCP/UDP 后端
      count: 1
      forwarding_rule_hourly: 0.01   # [std]
      data_processing_per_gb: 0.0    # 同区域内免费
      expected_gb_per_month: 5000

  compute:
    mig_instances: 2
    instance_type: e2-medium
    hourly_per_instance: 0.033

  logging:
    monthly_gb: 50
    retention_days: 30

  psc:
    service_attachments: 1          # $0

  cloud_armor:
    policies: 0

network_egress:
  consumer_to_internet_per_gb: 0.12  # [kb] Premium tier 跨洲
  expected_egress_gb_per_month: 5000
```

### 9.2 月费计算(同一模板可改参数复用)

```yaml
# cost-output (round numbers, USD)
consumer_costs:
  forwarding_rules:
    public_glb: 1 × $0.025 × 720 = $18.00
    internal_mtls: 2 × $0.025 × 720 = $36.00    # 起步免费, 2 条
    total_fr: $54.00

  envoy_instances:
    public_glb: 1 × $0.040 × 720 = $28.80
    internal_mtls: 2 × $0.025 × 720 = $36.00
    total_envoy: $64.80     # ⚠️ 占大头

  lb_data_processing:
    public: 5000 × $0.025 = $125.00
    internal: 200 × $0.008 = $1.60
    total_lb_data: $126.60

  psc:
    endpoints_hourly: 3 × $0.01 × 720 = $21.60
    psc_data: 5000 × $0.01 = $50.00
    total_psc: $71.60

  cloud_armor:
    2 × $5 = $10.00

  static_ips:
    1 reserved_unused: $7.32    # ⚠️ 隐形
    5 in_use: $0

  logging:
    after_quota: 200 - 50 = 150 GiB × $0.50 = $75.00
    retention_30day: $0 (默认免费)
    total_logging: $75.00

  certs: $0

  dns:
    zone: $0.20
    queries: 5 × $0.40 = $2.00
    total_dns: $2.20

producer_costs:
  forwarding_rules:
    internal: 1 × $0.01 × 720 = $7.20
  lb_data_processing: 5000 × $0 = $0  # 同区域 ILB 免费
  compute: 2 × $0.033 × 720 = $47.52
  logging: 50 × $0.50 = $25.00
  psc: $0
  certs: $0

egress_costs:
  consumer_to_internet:
    5000 × $0.12 = $600.00    # ⚠️ 公网下行大头

summary:
  consumer_total: 411.72
  producer_total: 79.72
  egress_total: 600.00
  grand_total: $1091.44 / month
```

**关键观察**:
- 单工程 $1000/月级别,主要被 **Envoy 实例 ($65) + Internet Egress ($600) + PSC 数据 ($71) + LB 数据 ($127)** 四个大头吃掉
- **Producer 比 Consumer 便宜很多**,这是 PSC 模型的设计:Producer 只付 Compute + 同区域 LB;Consumer 付所有"对外服务"相关费用
- 如果你的客户端 80% 在同 region,**改用 Standard tier 或 CDN 可以降 Egress 到 $50-100/月**

---

## 10. 决策矩阵:什么时候用什么模式

### 10.1 Cross-Project 暴露服务

| 需求 | 推荐方案 | 月费量级 |
|---|---|---|
| Producer 仅 internal, 1-2 Consumer 同 region | **VPC Peering + Internal LB** | $20-50 |
| Producer 需要控制 consumer 访问 / 多 Consumer | **PSC NEG + GLB (公网) 或 ILB (内部)** | $300-1100 |
| Consumer 和 Producer 跨 region / 跨大洲 | **PSC(Consumer 单付跨区费)** | $400-2000 |
| Producer 已有公网 LB, Consumer 想直接复用 | **VPC Peering**(如果 IP 不重叠) | $0-$50 |

### 10.2 mTLS / Client Auth

| 模式 | 谁付 Envoy 增量 | 谁付 cert |
|---|---|---|
| **GLB 终止 TLS + mTLS(`ServerTlsPolicy`)** | Consumer(GLB 已有 Envoy) | Consumer |
| **GKE Istio Sidecar 终止 mTLS** | Producer 集群负载(GKE, 不是 LB) | 双方各自挂 cert |
| **Cloud Armor + Bot Management** | Consumer LB | Consumer |

### 10.3 长期成本优化清单

| 优先级 | 优化 | 节省量级 |
|---:|---|---|
| **P0** | 删 unused reserved static IP | $7.32/IP/月 |
| **P0** | 删 unused / test-only forwarding rules | $18/FR/月 |
| **P0** | 关闭 LB Access Logs `Detail=NONE`(除非要 SIEM) | 60-90% LB 日志费 |
| **P1** | GKE 系统组件日志 exclusion | 30-50% GKE 日志 |
| **P1** | VPC Flow Logs 采样率 1.0 → 0.1 | 90% flow log 费 |
| **P1** | Cloud Armor 卸载未在用的 policies | $5/policy/月 |
| **P2** | LB 日志 detail 降到 BASIC | 70% |
| **P2** | Multi-region → single-region(如果业务允许) | 80% 跨区费 |
| **P3** | Internet Egress 走 CDN / 缓存 | 50-80% 下行费 |
| **P3** | Committed Use Discounts(CUDs) for Compute Engine | 25-52% 计算费 |

---

## 11. 常见审计问题(给团队做 cost review 时问)

| 问题 | 期望答案 |
|---|---|
| 这个 LB 真的需要 L7 吗?(L7 LB Envoy $18+/月,L4 LB $0.013/小时) | 如果只是 TCP 转发, 用 L4; 只有 path-based routing / header rewrite 才用 L7 |
| 这个 LB 的 data processing 费涨了多少? | 环比 ±20% 都正常; >100% 必有原因(流量暴增 / 日志 detail 改了 / 加了 CDN miss) |
| PSC endpoint 数量与 producer service attachment 数量比 | 通常 1:1 或 N:1; 如果 N:1 太多意味着 consumer 各自复制一套 |
| Logging 桶有多少个? 默认 `_Default` 桶用量 vs 自定义桶 | 自定义桶可设更长 retention / 不同 ACL, 但每桶独立计费 |
| VPC Flow Logs 开了吗? 采样率多少? | 关或 0.01 采样是常态; 1.0 采样是大坑 |
| Static IP 数量与在用 FR 数量比 | 1:1 正常; > 1:1 有 reserved-unused IP 在烧钱 |
| Cloud DNS query 量 | 百万级才几毛; 千万级才是问题 |
| 每个 project 的 Audit Logs 强制保留(Admin Activity 400天) | 大型 org 的合规成本, 难以优化 |

---

## 12. 与 Lex 工程相关的额外参考

- 工程账单复盘 + pause/resume 脚本:`/Users/lex/git/gcp/cost/`(aibang-12345678-ajbx-dev 实际数据)
- LB / mTLS / PSC 通用配置文档:知识库 `gcp/glb/`、`gcp/mtls/`、`gcp/psa-psc/`
- PSC vs VPC Peering cost/quota 对比(已有 Aug 2025 数字基线):`gcp/psa-psc/psc-with-vpc-peering-quota-cost.md`
- 日志成本优化(详细):`gcp/cost/gcp-cost/gcp-log-cost.md`
- GKE 成本分配:`gcp/cost/gke-cost-allocations.md`

---

## 13. 后续可以扩的方向

1. **Cost attribution by label**: 用 `gcp-cost-allocation` label + BigQuery 账单导出, 按 team / env 拆账单
2. **Budget alerting**: `gcloud billing budgets create --threshold-rule=percent=0.5` 在 50% / 90% / 100% 触发通知
3. **Recommender API**: `gcloud recommender recommendations list --project=... --recommender=google.compute.instance.MachineTypeRecommender` 拿 GCE / LB rightsizing 建议(本工程已用 Active Assist)
4. **跨 region CUD**: 对稳态 compute 用 Committed Use Discounts,1 年 25%, 3 年 52% off
5. **Custom VM type sizing**: GKE node pool 重新计算,上周已经把 node pool 缩到 0 是好习惯

---

> **最后一句**: 本文档是基于现有知识库 + 行业标准基线 的"原则性分析",**不替代实时定价**。
> 生产决策前用 §8 脚本拉一次 Cloud Billing Catalog API,把 `[std]` 替换成实际数字。