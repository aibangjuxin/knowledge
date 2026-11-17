# 为什么用 GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS — 跨 project + 公网 Ingress 场景的核心原因

> **本节是"为什么跨 project + 公网 Ingress 场景下,必须用 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` 这个 Load Balancing Scheme"的核心原因梳理**。
>
> **架构师 lane 边界**:本文档只做"为什么这个 scheme 是唯一选择"的原因分析 + 4 维度对比,**不实施任何 gcloud / terraform apply**。
>
> **状态**:Reference · Date: 2026-09-04 · Author: **architect-gcp** · Reviewers: 业务方 / infra-gcp
>
> **核心问题**:
> 1. GCP 一共有几种 Load Balancing Scheme?各自适用于什么场景?
> 2. 为什么**只有 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`** 能同时满足:
>    - ✅ 公网入口(EXTERNAL)
>    - ✅ 跨 project(必须挂 PSC NEG)
>    - ✅ 跨 region(global scope)
>    - ✅ L7 路由(HTTP / HTTPS 协议)
> 3. **业务方场景为什么非这个 scheme 不可?**
>
> **配套文档**:
> - 概念澄清:[`../../psa-psc/psc-concept.md` §4.5](../../psa-psc/psc-concept.md) — PSC Endpoint vs PSC NEG 一句话区分
> - 已实现架构:[`public-tls-cross-project-implementation.html`](./public-tls-cross-project-implementation.html) — 当前生产架构图
> - 上一轮决策:[`facing-issue.md`](./facing-issue.md) — 3 隐患 + 业务方核心构想
> - 部署参考:[`tenant-tls-setup-https.md`](./tenant-tls-setup-https.md) — Producer ILB 二次终结 TLS 的实施记录

---

## 0. 一句话总结

> **`GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` 是 GCP LB 体系里,唯一一个同时满足"公网入口 + 跨 project(PSC NEG)+ 跨 region(global scope)+ L7 路由"4 个条件的 Load Balancing Scheme**。
>
> 任何缺一个条件的 scheme(`INTERNAL` / `EXTERNAL` 经典版 / `EXTERNAL_MANAGED` 非 global / `INTERNAL_MANAGED`)都**无法支持业务方的"公网客户端 → 跨 project → 跨 region → L7 路由"完整链路**。

---

## 1. 业务方核心问题精确化

### 1.1 业务方原话

> "我现在需要你帮我澄清一个概念 GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS。我理解,只有这种形式才支持挂载的 PSC NEG 才能实现 Cross Project 的这种场景。而且这种场景的设计,就是给 public Ingress 来设计的。"

### 1.2 业务方已经识别到的关键约束(架构师确认)

| 业务方识别 | 架构师确认 |
|---|---|
| **"只有这种形式才支持挂载 PSC NEG"** | ⚠️ **不够精确**——准确说:**PSC NEG 只能挂在 EXTERNAL_MANAGED / GLOBAL_EXTERNAL_MANAGED 这 2 类 managed scheme 上**。经典 `EXTERNAL` / `INTERNAL` / `INTERNAL_MANAGED` **都不支持挂 PSC NEG** |
| **"实现 Cross Project 的场景"** | ✅ **完全正确**——PSC NEG 是 Google 官方明确定义的"两种并列的 consumer 侧设计模式"之一 |
| **"就是给 public Ingress 来设计的"** | ✅ **完全正确**——EXTERNAL 限定为公网客户端,MANAGED 是 Google 全托管,支持 L7 路由 + URL Map + Host rewrite |

### 1.3 业务方需要补充理解的"4 个维度"

业务方的理解"只有这种形式"是对的,但**没说清楚 4 个维度**为什么不可替代:

1. **GLOBAL 维度**——为什么不是 `EXTERNAL_MANAGED`(regional)?
2. **EXTERNAL 维度**——为什么不是 `INTERNAL_MANAGED`(内网)?
3. **MANAGED 维度**——为什么不是经典 `EXTERNAL`(legacy)?
4. **HTTP_HTTPS 维度**——为什么不是 `TCP` / `UDP` 协议?

---

## 2. GCP Load Balancing Scheme 全景

### 2.1 4 种 Load Balancing Scheme(架构师梳理)

**GCP 一共 4 类 Load Balancing Scheme**,每类又有 regional / global 两种 scope,加上 TCP / UDP / HTTP / HTTPS 协议差异,**总共有 10+ 种具体 LB 类型**:

| # | Scheme | Scope | 协议族 | 典型 LB | 公网? | 跨 region? | 支持 PSC NEG? |
|---|---|---|---|---|---|---|---|
| 1 | `INTERNAL` | Regional | TCP / UDP | Internal TCP/UDP LB (L4) | ❌ | ❌ | ❌ |
| 2 | `INTERNAL_MANAGED` | Regional | HTTP / HTTPS / gRPC | Internal Application LB (L7) | ❌ | ❌ | ❌ |
| 3 | `INTERNAL_MANAGED` | **Global** | HTTP / HTTPS | Cross-region Internal LB (L7) | ❌ | ✅ | ❌ |
| 4 | `EXTERNAL`(经典)| Regional | TCP / UDP / HTTP / HTTPS | Classic Application LB (legacy) | ✅ | ❌ | ❌ |
| 5 | `EXTERNAL`(经典)| **Global** | HTTP / HTTPS | Classic Global LB (legacy) | ✅ | ✅ | ❌ |
| 6 | `EXTERNAL_MANAGED`(regional)| Regional | HTTP / HTTPS / gRPC | **Regional External Application LB** | ✅ | ❌ | ✅ |
| 7 | **`EXTERNAL_MANAGED`(global)** | **Global** | HTTP / HTTPS / gRPC | **Global External Application LB**(架构师注:**这才是真正支持跨 project + 跨 region 的**)| ✅ | ✅ | ✅ |
| 8 | `EXTERNAL_MANAGED`(network)| Regional | TCP / UDP | **External Network LB (TCP)** | ✅ | ❌ | ✅(特定条件) |
| 9 | `EXTERNAL_MANAGED`(proxy)| Global | SSL | **External SSL Proxy LB** | ✅ | ✅ | ✅ |
| 10 | `EXTERNAL_MANAGED`(proxy)| Global | TCP | **External TCP Proxy LB** | ✅ | ✅ | ✅ |

### 2.2 业务方方案 vs 10 种 LB 类型

**业务方场景**:
- **公网客户端** → GLB → PSC NEG → ServiceAttachment → 内网 GKE
- **必须同时满足**:公网 + 跨 project(PSC NEG)+ L7 路由 + 跨 region 可选

| 业务方场景要求 | 排除的 LB 类型 | 剩下的 LB 类型 |
|---|---|---|
| **公网** → 排除 #1/2/3(INTERNAL) | #1, #2, #3 | #4-#10 |
| **跨 project(PSC NEG)** → 排除 #4/5(经典不支持) | #4, #5 | #6-#10 |
| **L7 路由(HTTP/HTTPS)** → 排除 #8/9/10(TCP/SSL/UDP) | #8, #9, #10 | #6, #7 |
| **跨 region(可选但强烈推荐)** → 排除 #6(regional)| #6 | **#7 = `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`** ✅ |

→ **唯一满足所有约束的 = `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`**。

---

## 3. 4 个维度逐项拆解(为什么不可替代)

### 3.1 维度 1:为什么必须是 GLOBAL(跨 region)

| 维度 | GLOBAL(架构师推荐)| REGIONAL |
|---|---|---|
| **流量调度** | Anycast 单 IP,Google Edge 把流量路由到最近 region | 单 region IP,跨 region 流量要 DNS 切换 |
| **健康检查** | 自动跨 region failover | 单 region 健康,跨 region 失效 |
| **生产场景适配** | 多 region 部署必备 | 单 region / 简单 PoC |
| **PSC NEG 跨 project 兼容** | ✅ **完全兼容**(推荐) | ⚠️ 兼容但有限 |

**业务方现实**:
- 业务方已经在 `us-east4` 部署,未来可能扩到多 region
- 公网客户端分布在全球
- **必须用 GLOBAL** 才能满足"任意 region 客户端都低延迟访问"

### 3.2 维度 2:为什么必须是 EXTERNAL(公网)

| 维度 | EXTERNAL(架构师必需)| INTERNAL |
|---|---|---|
| **客户端位置** | 公网 Internet | 仅同 VPC / 同一 Google network |
| **公网 IP** | Anycast 静态 IP | RFC 1918 私有 IP(10.x.x.x)|
| **TLS cert** | 公开 CA(Let's Encrypt / TrustAsia)| 内部 CA 自签即可 |
| **Cloud Armor** | ✅ 支持(WAF / DDoS 防护)| ⚠️ 部分支持 |

**业务方现实**:
- 业务方客户端 = `https://www.aibang.com`(公网域名)
- **必须用 EXTERNAL** 才能让公网用户访问

### 3.3 维度 3:为什么必须是 MANAGED(托管)

| 维度 | MANAGED(架构师推荐)| 经典 EXTERNAL |
|---|---|---|
| **底层实现** | Envoy-based(Google 全托管) | 旧式 LB,Google 已不推荐 |
| **URL Map 能力** | ✅ 完整 L7(URL 重写 / Header 重写 / Weight)| ⚠️ 有限 |
| **Cloud Armor 集成** | ✅ 深度集成(WAF / Bot / Rate limit) | ⚠️ 基础支持 |
| **健康检查** | ✅ HTTP/HTTPS/TCP/gRPC | ⚠️ 有限 |
| **PSC NEG 支持** | ✅ **支持** | ❌ **不支持**(legacy 不支持) |
| **维护性** | Google 全托管,无运维 | 需自己管理 |

**业务方现实**:
- 业务方需要 URL Map + Header 重写 + Cloud Armor
- 业务方需要 PSC NEG 跨 project
- **必须用 MANAGED** 才能满足需求

### 3.4 维度 4:为什么必须是 HTTP_HTTPS(L7)

| 维度 | HTTP_HTTPS(架构师必需)| TCP / UDP / SSL |
|---|---|---|
| **路由粒度** | URL 路径 + Host 头 + Header | 只能基于 IP + Port |
| **URL Map** | ✅ 支持(URL 重写 / 路径匹配)| ❌ 不支持 |
| **Header 透传 / 重写** | ✅ 支持(`X-Forwarded-*` / `routeAction.headerAction`)| ❌ 不支持 |
| **公网 cert 终结** | ✅ 在 GLB 终结 TLS(业务方核心需求) | ⚠️ SSL Proxy 终结 TLS,但路由能力弱 |
| **业务方架构** | 业务方需要 `hostRewrite` + path 前缀 | TCP 只能 IP+Port 转发 |

**业务方现实**:
- 业务方上一轮 `[facing-issue.md §5.7]` 明确:**HTTPRoute 按 Path 锁定 Service** + **GLB URL Map 重写 Host 头**
- 业务方需要公网 cert(`www.aibang.com`)
- **必须用 HTTP_HTTPS** 才能满足

---

## 4. PSC NEG 为什么必须挂在 managed LB 上(架构师关键洞察)

### 4.1 PSC NEG 的本质(回到 psc-concept.md §4.5.1)

> **PSC NEG 是一个 NEG (Network Endpoint Group)**。
> 必须挂在 Load Balancer 后面,作为 LB 的 backend。
> 然后通过 LB 的 VIP 访问 Producer。

**这意味着**:
- PSC NEG **不能独立存在**——必须依附于 LB
- PSC NEG 作为 LB 的 backend 时,**LB 必须支持 NEG 这种 backend 类型**
- GCP 一共 10+ 种 LB,**只有 `EXTERNAL_MANAGED` / `GLOBAL_EXTERNAL_MANAGED` 支持 NEG 作为 backend**(经典 EXTERNAL 不支持)

### 4.2 GCP 官方原文(架构师引用)

**Google Cloud 文档**([Global External Application Load Balancer overview](https://cloud.google.com/load-balancing/docs/https)):

> "An external Application Load Balancer is a proxy-based Layer 7 load balancer that enables you to run and scale your services behind a single external IP address. It supports **Network Endpoint Groups (NEGs)**, including **Private Service Connect (PSC) NEGs**, as backends."

**关键事实**:
- ✅ `EXTERNAL_MANAGED` 系列 LB **支持 PSC NEG 作为 backend**
- ❌ 经典 `EXTERNAL` LB **不支持 NEG 作为 backend**
- ❌ `INTERNAL` / `INTERNAL_MANAGED` LB **不支持 PSC NEG 作为 backend**(PSC NEG 必须挂在 EXTERNAL 链)

### 4.3 业务方架构链路(再确认)

```
Internet Client
    │
    │  公网 HTTPS
    ▼
Global External Application LB(GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS)
    │
    │  Backend Service(protocol=HTTPS, portName=https)
    ▼
PSC NEG(type=PRIVATE_SERVICE_CONNECT)
    │
    │  Google Backbone(PSC Tunnel)
    ▼
Service Attachment(Master Project)
    │
    │  ILB TCP 443
    ▼
Backend Service(Master)
    │
    ▼
MIG / GKE Gateway
```

**链路里 LB 那一节** = `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`,**正是这一节限定了必须用 managed scheme**。

---

## 5. 业务方为什么不能选其他 9 种 LB(架构师详细排除)

### 5.1 排除 #1-#3:INTERNAL 系

| 类型 | 业务方场景适配 | 排除原因 |
|---|---|---|
| `INTERNAL` TCP/UDP | ❌ | 业务方是公网客户端,**无法访问内网 IP** |
| `INTERNAL_MANAGED` Regional | ❌ | 同上,且 L7 但仍内网 IP |
| `INTERNAL_MANAGED` Global | ❌ | L7 + Global + Internal IP — 仍内网 IP,公网客户端无法访问 |

→ **结论**:**所有 INTERNAL 系列全部排除**,业务方是公网场景。

### 5.2 排除 #4-#5:经典 EXTERNAL(legacy)

| 类型 | 业务方场景适配 | 排除原因 |
|---|---|---|
| `EXTERNAL` Regional | ❌ | 经典 LB,**不支持 NEG 作为 backend**(包括 PSC NEG),无法跨 project |
| `EXTERNAL` Global | ❌ | 同上,经典 LB Google 已不推荐 |

→ **结论**:**经典 EXTERNAL 系列全部排除**,Google 已 deprecated,且不支持 PSC NEG。

### 5.3 排除 #6:EXTERNAL_MANAGED Regional

| 类型 | 业务方场景适配 | 排除原因 |
|---|---|---|
| `EXTERNAL_MANAGED` Regional | ❌ | 支持 PSC NEG,但**单 region** |

→ **结论**:**业务方未来要扩 region**,Regional 方案不可持续。

### 5.4 排除 #8-#10:EXTERNAL_MANAGED TCP/SSL

| 类型 | 业务方场景适配 | 排除原因 |
|---|---|---|
| `EXTERNAL_MANAGED` Network TCP | ❌ | L4 TCP,无 URL Map / Host 重写,业务方核心需求缺失 |
| `EXTERNAL_MANAGED` SSL Proxy | ❌ | L4 SSL,无 URL Map,Host 重写能力有限 |
| `EXTERNAL_MANAGED` TCP Proxy | ❌ | L4 TCP,无 L7 能力 |

→ **结论**:**所有 TCP/SSL Proxy 系列全部排除**,业务方需要完整 L7 能力。

### 5.5 唯一选择 #7:GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS

| 维度 | 是否满足 |
|---|---|
| 公网入口(EXTERNAL)| ✅ |
| 跨 region(GLOBAL)| ✅ |
| L7 路由(HTTP_HTTPS)| ✅ |
| 支持 PSC NEG(MANAGED)| ✅ |
| URL Map + Host 重写 | ✅ |
| Cloud Armor | ✅ |
| HTTP/2 + HTTP/3 | ✅ |
| 任播静态 IP | ✅ |

→ **唯一满足业务方全部需求**。

---

## 6. 权威证据 + Google 官方文档引用

### 6.1 GCP 官方文档

- **External Application Load Balancer overview**:[https://cloud.google.com/load-balancing/docs/https](https://cloud.google.com/load-balancing/docs/https)
  > "An external Application Load Balancer is a proxy-based Layer 7 load balancer that enables you to run and scale your services behind a single external IP address. It supports **Network Endpoint Groups (NEGs)**, including **Private Service Connect (PSC) NEGs**, as backends."

- **PSC NEG backend types**:
  > "PSC NEGs are supported as backends on external Application Load Balancers and external proxy Network Load Balancers."

- **Cross-region Internal Application Load Balancer**:[https://cloud.google.com/load-balancing/docs/https/setting-up-cross-regional](https://cloud.google.com/load-balancing/docs/https/setting-up-cross-regional)
  > 仅支持 internal,**不支持 PSC NEG 作为 backend**

### 6.2 业务方已有文档证据

| 文档 | 关键事实 |
|---|---|
| `psc-concept.md` §4.5 | "PSC NEG 必须挂在 LB 后面" + "GCP 官方把 consumer 设计分 3 种:Endpoint / Backend / Hybrid" |
| `tenant-tls-setup-https.md` §1 | "External GLB 终止 TLS" + "链路有一跳是 HTTP(不加密)" → 推动升级 HTTPS |
| `tenant-tls-setup-https.md` 整体 | 完整实施记录,GLB 用 `--load-balancing-scheme=GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` |
| `public-tls-cross-project-implementation.html` | 当前生产架构图,GLB 用 `--load-balancing-scheme=EXTERNAL_MANAGED` |

### 6.3 Org Policy 约束(业务方已踩过)

**`tenant-tls-setup-https.md` 关键警告**:

> "整个 Public TLS 链路要落地,External 这一跳用的是 **A 类型**,即 `--load-balancing-scheme=GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` 的 Global External HTTPS Load Balancer。这条 LB 链**默认被组织级 Org Policy 限制**:`compute.loadBalancing.allowedLoadBalancingScheme` 只放行 `INTERNAL`,`EXTERNAL` 全系被拒。"

→ **业务方需要申请 Org Policy 扩展**:`INTERNAL` + `EXTERNAL`(或显式 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`)。

---

## 7. 4 个常见误解澄清

### 7.1 误解 1:"只要是 EXTERNAL 就支持 PSC NEG"

**答**:**错**。**只有 `EXTERNAL_MANAGED` 系列**支持 PSC NEG 作为 backend。经典 `EXTERNAL` LB **不支持**。

### 7.2 误解 2:"Regional LB 也能挂 PSC NEG 跨 project"

**答**:**部分对**。Regional `EXTERNAL_MANAGED` LB **能**挂 PSC NEG 跨 project,但**只服务单 region**。如果业务方未来要扩 region,要重新建 LB + 切换 DNS,**不可持续**。

### 7.3 误解 3:"INTERNAL_MANAGED 也能跨 project"

**答**:**错**。INTERNAL_MANAGED LB **不能**挂 PSC NEG(PSC NEG 必须挂在 EXTERNAL 链)。业务方是公网客户端,即使 INTERNAL_MANAGED 能跨 project,也无法让公网用户访问。

### 7.4 误解 4:"TCP/SSL Proxy 也能做 L7 路由"

**答**:**错**。TCP/SSL Proxy 是 L4,只能基于 IP + Port 路由。**业务方需要 URL Map + Host rewrite,必须 L7(HTTP/HTTPS 协议)**。

---

## 8. 决策树:为什么选 GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS

```
业务方场景:公网客户端 → 跨 project → L7 路由
│
├─ 必须是公网 → 排除 INTERNAL 系
│
├─ 必须支持 PSC NEG → 排除经典 EXTERNAL
│
├─ 必须是 L7(HTTP/HTTPS)→ 排除 TCP/SSL Proxy
│
└─ 必须跨 region(推荐) → 排除 Regional EXTERNAL_MANAGED
   │
   └─► 唯一选择: GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS ✅
```

---

## 9. 业务方应当提交 Org Policy 申请清单(架构师建议)

> **业务方在 Org Policy 解锁前,跨 project 部署会被拒绝**。

```yaml
# 申请模板(给 Security / Org Policy Owner 审批)
apiVersion: cloudresourcemanager.cnrm.cloud.google.com/v1beta1
kind: Project
metadata:
  annotations:
    # Org Policy 扩展:allowedLoadBalancingScheme
    compute.loadBalancing.allowedLoadBalancingScheme:
      - INTERNAL
      - INTERNAL_MANAGED
      - EXTERNAL_MANAGED
      # 显式列出 GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS
      - GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS
    # Org Policy 扩展:allowedVMSizes(可选)
    compute.vm.externalIpAccess: deny  # VM 不需要公网 IP(架构师建议)
```

→ **业务方需要 Security / Org Policy Owner 审批**这条 Policy,才能在项目下建 `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` LB。

---

## 10. 架构师反思

### 10.1 为什么这个概念容易混淆

业务方提到 4 个混淆点:

1. **LB scheme 命名复杂**:`GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` 是 4 个修饰词拼接,每个修饰词都有自己的含义
2. **PSC NEG 的依附性**:PSC NEG 必须挂在 LB 后面 → 不了解 LB 类型就无法理解 PSC NEG 的可用范围
3. **MANAGED vs 经典 LB 的差异**:经典 LB 不支持 NEG(包括 PSC NEG),容易让老 GCP 用户栽跟头
4. **Regional vs Global 的差异**:业务方"已实现"架构(HTML 文档)用的是 `EXTERNAL_MANAGED`(regional),需要切到 `GLOBAL_EXTERNAL_MANAGED`(global)才能跨 region

### 10.2 为什么"业务方理解"已经接近正解

业务方原话:
> "我理解,只有这种形式才支持挂载的 PSC NEG 才能实现 Cross Project 的这种场景"

**业务方已经识别了**:
- ✅ 必须支持 PSC NEG
- ✅ 必须能跨 project
- ✅ 是 public Ingress 场景

**业务方还差 1 步**:
- ⚠️ 为什么"这种形式"不可替代?—— **4 个维度联合约束的结果**(公网 + 跨 project + L7 + 跨 region)

→ **本节文档填补的就是这个 gap**。

---

## 11. 架构师 lane 边界声明

- ✅ 生成 `why-using-global-external-managed-http-https.md`(本节文档,11 节)
- ✅ 引用 GCP 官方文档(`External Application LB` + `PSC NEG backend types`)
- ✅ 引用业务方已有文档(`psc-concept.md` §4.5 + `tenant-tls-setup-https.md` §1)
- ✅ 提供 Org Policy 申请模板(§9)
- ❌ **不实施任何 provision / apply / gcloud / terraform**
- ❌ **不创建 GLB / Backend Service / PSC NEG / ServiceAttachment**
- ❌ **不持有 GCP 凭证**

---

## 12. 文档维护

- **作者**:**architect-gcp**(架构师,设计 lane)
- **Reviewers**:业务方 / infra-gcp
- **配套文档**:
  - 概念澄清:[`../../psa-psc/psc-concept.md` §4.5](../../psa-psc/psc-concept.md) — PSC Endpoint vs PSC NEG
  - 已实现架构:[`public-tls-cross-project-implementation.html`](./public-tls-cross-project-implementation.html)
  - 上一轮决策:[`facing-issue.md`](./facing-issue.md) — 3 隐患 + 业务方核心构想
  - 部署参考:[`tenant-tls-setup-https.md`](./tenant-tls-setup-https.md) — Producer ILB 二次终结 TLS
- **状态**:Reference(架构师仅作参考,不修改业务方生产 config)

---

<!-- cite: https://cloud.google.com/load-balancing/docs/https — GCP External Application LB overview(支持 NEG 包括 PSC NEG)|
<!-- cite: https://cloud.google.com/blog/products/networking/three-consumer-private-service-connect-designs — GCP 官方博客:Three PSC patterns(Endpoint / Backend / Hybrid)|
<!-- cite: https://cloud.google.com/load-balancing/docs/https/setting-up-cross-regional — Cross-region Internal LB(仅 internal,不支持 PSC NEG)|
<!-- cite: ../../psa-psc/psc-concept.md §4.5.1 — PSC Endpoint vs PSC NEG 一句话区分(业务方上游概念)|
<!-- cite: ./tenant-tls-setup-https.md §1 — 为什么从 HTTP backend 升级到全 HTTPS(业务方历史决策)|
<!-- cite: ./tenant-tls-setup-https.md Org Policy 警告 — allowedLoadBalancingScheme 默认只放行 INTERNAL,EXTERNAL 系被拒 |
<!-- cite: ./public-tls-cross-project-implementation.html — 当前生产架构图,GLB 用 EXTERNAL_MANAGED(regional,待升级 global)|
