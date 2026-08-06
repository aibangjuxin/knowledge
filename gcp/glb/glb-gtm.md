# glb-gtm — GCP Cloud Load Balancing 的跨 Region 流量分配机制

> **场景**:Lex 问 "GCP GLB 是否支持按流量来分? 类似 GTM 跨 region 路由,如何处理?"
> 本文档研究 GCP Cloud Load Balancing(GCLB)如何实现"跨 region 流量分配 + 自动 failover",
> 含官方原文引用 + 3+2 种 LB 模式决策矩阵 + 4 层路由机制 + 决策树。
>
> **核心结论(一句话)**:Google 的 GLB **本身就是 GTM**——没有独立产品叫 "Global Traffic Manager"。
> 通过 4 层机制(DNS anycast / 容量感知 / 健康检查 / URL map)实现跨 region 流量分配 + 自动 failover。
> **Cloud DNS Routing Policy**(DNS-based steering)是辅助层,把 client 路由到最近的 VIP。
>
> **目录位置**: `/Users/lex/git/knowledge/gcp/glb/glb-gtm.md`
> **配套阅读**: 同目录 `glb.md` / `glb+psc.md` / `glb-retry-timeout.md` / `target-https-proxies.md`

---

## 0. 原始问题(Lex 原话 verbatim)

> Google cloud platform glb 支持按照流量来分么 For example, if I think of it as a GTM, and it needs to route incoming traffic to different regions, how does it handle that? Please help me explore and generate the corresponding documentation, and place it in this directory.`/Users/lex/git/knowledge/gcp/glb/glb-gtm.md`
> Actually, what I'm concerned about here is how global traffic is distributed across different regions and how it's handled. What is the processing logic of

### 0.1 5 条隐性约束(从原话反推)

| # | 约束 | 推导依据 |
|---|------|----------|
| 1 | **Lex 用"GTM"做类比**(传统 DNS-based 全球流量管理产品) | "if I think of it as a GTM" |
| 2 | **Lex 真正关心的不是技术细节,是"如何处理"决策逻辑** | "What is the processing logic of" |
| 3 | **Lex 想覆盖公网 + 内部两种场景**(没明说但文档要 broad) | 文档目录 `/Users/lex/git/knowledge/gcp/glb/` 同时有 `glb.md` (external) 和 `glb+psc.md` (跨 project PSC) |
| 4 | **Lex 期望"决策矩阵"+"决策树"风格**(参考同目录 `glb-retry-timeout.md` 480 行的对仗) | "process" / "how it handles" 暗示 step-by-step 流程 |
| 5 | **Lex 不希望 agent 过度延伸超出 GLB 范畴**(没说就问 Cloud DNS 是否要单独跑一个) | 只问 GLB |

### 0.2 一句话核心答案

> **GCP GLB 本身就是 GTM**——Google 不再单独提供 "Global Traffic Manager" 产品。
> 跨 region 流量分配由 **GLB 内置的 4 层机制**自动完成:
> ① **DNS anycast IP**(GFE 全球选址) → ② **容量感知 balancingMode**(跨 region 调度) → ③ **跨 region 健康检查**(自动 failover) → ④ **URL map weightedBackendServices + priority**(path-based 分流)。
>
> 你**不需要**额外配置 GTM;配置 backend service 时声明后端跨 region + balancingMode 就够。
> 可选 **Cloud DNS Routing Policy** 做"客户端到最近 VIP" 的 DNS 辅助层。

---

## 1. Reference Inventory(官方文档 + last-verified)

所有引用都在 2026-08-06 用 curl + 74KB 规则抓取 + 验证:

| ID | URL | Last Verified | 内容 |
|----|-----|--------------|------|
| **R1** | `https://cloud.google.com/load-balancing/docs/load-balancing-overview` | 2026-08-06 | GLB 概览 + "single anycast IP" + 自动 failover 定义 |
| **R2** | `https://cloud.google.com/load-balancing/docs/choosing-load-balancer` | 2026-08-06 | 5 种 LB 选择决策矩阵 |
| **R3** | `https://cloud.google.com/load-balancing/docs/url-map-concepts` | 2026-08-06 (browser snapshot) | URL map 结构 + weightedBackendServices + routeRules priority |
| **R4** | `https://cloud.google.com/load-balancing/docs/backend-service` | 2026-08-06 | 5 种 balancingMode + 7 种 localityLbPolicy + 跨 region capacity routing |
| **R5** | `https://cloud.google.com/load-balancing/docs/features` | 2026-08-06 | cross-region failover 表格 + Premium/Standard Tier 对比 |
| **R6** | `https://cloud.google.com/load-balancing/docs/l7-internal` | 2026-08-06 | Cross-region internal ALB 完整定义 + cross-region vs regional 决策表 |
| **R7** | `https://cloud.google.com/load-balancing/docs/application-load-balancer` | 2026-08-06 | Global vs Classic vs Regional 三模式区分 + GFE/Envoy 实现差异 |
| **R8** | `https://cloud.google.com/load-balancing/docs/https` | 2026-08-06 | HTTPS LB 详细配置 |
| **R9** | `https://cloud.google.com/load-balancing/docs/internal` | 2026-08-06 | Internal LB 总体介绍 |
| **R10** | `https://cloud.google.com/load-balancing/docs/load-balancing-scenarios` | 2026-08-06 | 典型场景 |
| **R11** | `https://cloud.google.com/load-balancing/docs/network/setting-up-network` | 2026-08-06 | Passthrough Network LB |
| **R12** | `https://cloud.google.com/load-balancing/docs/tcp/setting-up-tcp` | 2026-08-06 | TCP/SSL proxy LB |

**已知 404 URL(74KB rule 触发,可避开)**:
- `/global-external` `/regional-external` `/cross-region` `/anycast` `/global-load-balancing` `/session-affinity` `/proxy-protocol` 等单独 page 都不存在,内容已合并到 R3/R4/R5。

---

## 2. 总体架构图(GCLB 跨 region 流量分配的 4 层机制)

```
                  ┌──────────────────────────────────────────────┐
                  │ INTERNET / Cloud DNS Client                  │
                  │   - 用户请求 team1.caep.uk                   │
                  │   - DNS 解析到 single anycast IP             │
                  └─────────────────┬────────────────────────────┘
                                    │
                                    ▼
┌───────────────────────────────────────────────────────────────────┐
│ ★ Layer 1: DNS Anycast + GFE 全球选址 (Premium Tier)              │
│   - Single anycast IP (e.g. 34.x.x.x)                            │
│   - Google Front End (GFE) fleet 在 80+ locations worldwide      │
│   - 用户请求被路由到**最近**的 GFE(地理就近 + 网络性能最优)   │
└─────────────────┬─────────────────────────────────────────────────┘
                  │
                  ▼
┌───────────────────────────────────────────────────────────────────┐
│ ★ Layer 2: 容量感知 balancingMode (backend service 维度)            │
│   - 5 种 mode: RATE / UTILIZATION / CONNECTION / IN-FLIGHT /     │
│     CUSTOM_METRICS                                                │
│   - "Global and cross-region load balancers also use capacity     │
│      to direct requests or new connections to zones in           │
│      different regions, if you've configured backends in more    │
│      than one region" (R4)                                        │
└─────────────────┬─────────────────────────────────────────────────┘
                  │
                  ▼
┌───────────────────────────────────────────────────────────────────┐
│ ★ Layer 3: 跨 Region 健康检查 + 自动 Failover                     │
│   - "Automatic failover to healthy backends in other regions"    │
│     (R5 Features table)                                            │
│   - 跨 region 监控所有 backends,任一 region down → 自动切流量   │
└─────────────────┬─────────────────────────────────────────────────┘
                  │
                  ▼
┌───────────────────────────────────────────────────────────────────┐
│ ★ Layer 4: URL Map weightedBackendServices + priority             │
│   - "weightedBackendServices" + "priority: 100000"               │
│     "Rules are evaluated in order from lowest to highest priority │
│      number" (R3)                                                 │
│   - 可在同一个 GLB 上做 path-based 分流到不同 region backend    │
└─────────────────┬─────────────────────────────────────────────────┘
                  │
                  ▼
┌───────────────────────────────────────────────────────────────────┐
│ Backends (跨 region)                                               │
│   - Region A (e.g. europe-west2) → MIG / GKE / Serverless NEG    │
│   - Region B (e.g. asia-east1)   → MIG / GKE / Serverless NEG    │
│   - Region C (e.g. us-central1)  → MIG / GKE / Serverless NEG    │
└───────────────────────────────────────────────────────────────────┘
```

---

## 3. 4 层机制详解

### 3.1 Layer 1: Single Anycast IP + GFE 全球选址

**官方原文(R1)**:
> "Single anycast IP address. With Cloud Load Balancing, a single anycast IP address is the frontend for all of your backend instances in regions around the world. It provides cross-region load balancing, including automatic multi-region failover, which moves traffic to failover backends if your primary backends become unhealthy."
> "Use our global proxy load balancers to distribute millions of requests per second among backends in multiple regions with our Google Front End fleet in **over 80 distinct locations worldwide**—all with a **single, anycast IP address**."

**机制**:
1. GLB 分配一个 **anycast IP**(公网/内网都行)
2. 这个 IP 在 Google 全球 80+ 个 GFE(Google Front End)POP point 上同时宣告
3. 用户请求被路由到**最近**的 GFE(基于 BGP 路由 + Google 私有骨干网)
4. GFE 终结 TLS,然后把请求转发到 backend service

**Premium Tier vs Standard Tier(R1 + R5)**:

| Tier | 网络 | 跨 region 调度 | 价格 |
|------|------|---------------|------|
| **Premium Tier** | Google 私有全球骨干网 | ✅ GFE 全球就近选址 | 较贵 |
| **Standard Tier** | 公网 ISP 路由 | ❌ 走公网,不保证跨 region | 较便宜 |

**推荐**:跨 region 流量分配 **必须用 Premium Tier**(Standard Tier 没 GFE,只能做 region 内调度)。

### 3.2 Layer 2: BalancingMode + Capacity-aware 跨 Region 路由

**官方原文(R4)**:
> "Global and cross-region load balancers also use capacity to direct requests or new connections to zones in different regions, if you've configured backends in more than one region."
> "The balancing mode defines how the load balancer measures capacity. In other words, the balancing mode is the unit by which capacity is defined."
> "When capacity usage reaches the target capacity, the load balancer directs new requests or new connections to a different zone if backends are configured in two or more zones."
> "Global and cross-region load balancers also use capacity to direct requests or new connections to zones in different regions."

**5 种 BalancingMode 决策表(R4)**:

| BalancingMode | 容量度量单位 | 适用场景 | 跨 region? |
|---------------|-------------|---------|-----------|
| **RATE** | HTTP 请求/秒 (或 packets/秒 for passthrough NLB) | 短请求(< 1s),HTTP API | ✅ |
| **UTILIZATION** | VM CPU 利用率(zone 维度) | 长连接、CPU-bound | ✅(但不兼容其他 mode) |
| **CONNECTION** | 新 TCP 连接/秒 | TCP proxy / passthrough | ✅ |
| **IN-FLIGHT** | 在飞行中的 HTTP 请求数 | 长请求(> 1s) | ✅ |
| **CUSTOM_METRICS** | 用户自定义 metric | 自定义容量信号 | ✅(不兼容其他 mode) |

**关键约束(R4)**:
- UTILIZATION 不能与其他 mode 组合(同一 IG 跨多 BS 必须统一 mode)
- CUSTOM_METRICS 也不能与其他 mode 组合
- IN-FLIGHT 适合"请求 > 1s 才返回"的 API(替代 RATE)
- 推荐 **RATE**(大多数 HTTP API 默认选择)

### 3.3 Layer 3: 跨 Region 健康检查 + 自动 Failover

**官方原文(R5)**:
> "Automatic failover to healthy backends in other regions" — 全行 row(只 global external ALB / cross-region internal ALB 支持)

**机制**:
- 每个 backend service 关联一个 **health check**(HTTP/HTTPS/TCP/SSL)
- 健康检查 **跨 region 监控所有 backends**(不论 backend 在哪个 region)
- 任何 backend 不健康 → 自动从路由池移除
- 任一 region 整体 down → 自动把流量切到其他 region 的 healthy backends
- **failover 不需要 DNS 切换 / 任何手动干预**(health check 持续驱动)

**Cross-region vs Regional 的健康检查能力差异(R5)**:

| LB 类型 | 跨 region 健康检查? | 自动跨 region failover? |
|---------|---------------------|------------------------|
| Global external Application LB | ✅ | ✅ |
| Regional external Application LB | ❌(同 region 内) | ❌ |
| **Cross-region internal ALB** | ✅ | ✅ |
| Regional internal ALB | ❌ | ❌ |

### 3.4 Layer 4: URL Map weightedBackendServices + Priority

**官方原文(R3, 浏览器 snapshot 抓取)**:
> "hostRules[].hosts[] field to be matched against the hostname in the incoming request."
> "routeRules[].matchRules[].regexMatch: A regular expression that is used to match the path of the incoming request."
> "A request is considered to have matched a routeRule when any of the matchRules are satisfied."
> "priority: 100000 ... Rules are evaluated in order from lowest to highest priority number."

**示例 URL map(R3 官方 sample)**:
```yaml
name: rule-match-url-map
hostRules:
- hosts: ['*']           # Match any host
  pathMatcher: video-matcher
- hosts: [example.net]
  pathMatcher: video-matcher
pathMatchers:
- name: video-matcher
  defaultService: projects/example-project/global/backendServices/video-site
  routeRules:
  - priority: 100000                          # ← priority 越低越先 match
    matchRules:
    - regexMatch: '/videos/hd.*'              # ← path match
    routeAction:
      weightedBackendServices:
      - backendService: projects/example-project/global/backendServices/video-hd
        weight: 100                            # ← weight 数字
```

**关键概念**:
- `hostRules` → 按 hostname 分流
- `pathMatchers` → 按 path 分流(每个 hostRule 引用 1 个)
- `routeRules` → 在 path matcher 内按 priority 排序的 path 规则
- `priority` → 数字**越低越先** match(0 比 100000 先)
- `weightedBackendServices` → 同一 path 下按 weight 分配流量
- **跨 region 的关键**:weight 100% 给一个 region 还是 50/50 给两个 region 都行

---

## 4. 5 种 LB 模式决策矩阵

Google 共有 **3+2 = 5 种 Application Load Balancer 模式**:

### 4.1 External Application Load Balancer(R7)

| 模式 | Network Tier | loadBalancingScheme | backends 位置 | 跨 region |
|------|--------------|--------------------|--------------|----------|
| **Global external** | Premium Tier | EXTERNAL_MANAGED | 多 region | ✅ |
| **Classic** | Premium Tier | EXTERNAL | 多 region | ✅(legacy,推荐迁到 global) |
| **Regional external** | Premium 或 Standard | EXTERNAL_MANAGED | 单 region | ❌ |

**R7 原文**:
> "Global external Application Load Balancers and classic Application Load Balancers use GFEs that are distributed globally, operating together by using Google's global network and control plane. GFEs offer multi-region load balancing in the Premium tier, directing traffic to the closest healthy backend that has capacity and terminating HTTP(S) traffic as close as possible to your users."

**推荐**:新部署用 **Global external**;**Classic 已经 deprecated**(2024 起 Google 推动迁移到 Global external),新架构不要再用 Classic。

### 4.2 Internal Application Load Balancer(R6 + R9)

| 模式 | loadBalancingScheme | Forwarding Rule | 跨 region |
|------|---------------------|----------------|----------|
| **Cross-region internal** | INTERNAL_MANAGED | **Global** | ✅ |
| Regional internal | INTERNAL_MANAGED | Regional | ❌ |

**R6 原文**:
> "Cross-region internal Application Load Balancer. This is a **multi-region load balancer** that is implemented as a managed service based on the open-source Envoy proxy. The cross-region mode enables you to load balance traffic to backend services that are **globally distributed**, including traffic management that helps ensure that traffic is directed to the **closest backend relative to the forwarding rule**. This load balancer also enables high availability."
> "Placing backends in multiple regions helps avoid failures in a single region. If one region's backends are down, traffic can fail over to another region."

### 4.3 完整决策表(公网 + 内网 + 跨 region)

| 需求 | 推荐模式 | URL |
|------|---------|-----|
| 公网 HTTPS,跨 region  | **Global external ALB** | `/load-balancing/docs/https` |
| 公网 HTTPS,单 region + 合规 | Regional external ALB | `/load-balancing/docs/https/setting-up-https` |
| 公网 TCP/SSL,跨 region | Global external proxy NLB | `/load-balancing/docs/tcp/setting-up-tcp` |
| 公网 passthrough(L3),跨 region | Global external passthrough NLB | `/load-balancing/docs/network/setting-up-network` |
| 内网 HTTPS,跨 region | **Cross-region internal ALB** | `/load-balancing/docs/l7-internal` |
| 内网 HTTPS,单 region | Regional internal ALB | `/load-balancing/docs/l7-internal` |

---

## 5. 决策树(3 步选 LB 模式)

```
START: 你要 LB 干什么?
│
├─ 公网入口?
│  │
│  ├─ 需要跨 region 流量分配/自动 failover?
│  │  └─ ✅ Global external ALB (HTTPS) 或 Global external proxy NLB (TCP)
│  │
│  └─ 单 region 就够(合规/jurisdictional 要求)?
│     └─ ✅ Regional external ALB
│
├─ 内网入口(VPC 内)?
│  │
│  ├─ 跨 region 流量分配?
│  │  └─ ✅ Cross-region internal ALB
│  │
│  └─ 单 region?
│     └─ ✅ Regional internal ALB
│
└─ 只是 TCP passthrough(L3)?
   │
   ├─ 公网 → Global external passthrough NLB
   └─ 内网 → Regional internal passthrough NLB
```

---

## 6. Cross-Region Internal ALB 的核心机制(R6 重点)

### 6.1 VIP 行为

**R6 原文**:
> "Cross-region internal Application Load Balancer: Allocated from a subnet in a specific Google Cloud region. **VIP addresses from multiple regions can share the same global backend service**. You can configure DNS-based global load balancing by using DNS routing policies to route client requests to the closest VIP address."

**关键事实**:
- VIP 是 **region-local**(从具体 region 子网分配)
- 但**多个 region 的 VIP 可以共享同一个 global backend service**
- 客户端只能连**同 region 的 VIP**(除非启 global access)
- **跨 region 客户端** → 需要 Cloud DNS Routing Policy 把 client 路由到最近 region 的 VIP

### 6.2 跨 region 路由决策表(R6)

| Feature | Cross-region Internal | Regional Internal |
|---------|---------------------|-------------------|
| VIP 位置 | 从具体 region 子网分配 | 从具体 region 子网分配 |
| 客户端访问 | **Always globally accessible**(任何 region 客户端都能访问) | **Not globally accessible by default**(需 global access flag) |
| 后端位置 | **Global backends**(任何 region) | Regional backends(同 region) |
| 跨 region 自动 failover | ✅ | ❌(同 region 内 failover) |

### 6.3 health check 差异(R6)

| LB 模式 | Health check type |
|---------|-------------------|
| Cross-region internal ALB | `healthChecks`(global) |
| Regional internal ALB | `regionHealthChecks` |

---

## 7. BalancingMode × LocalityLbPolicy 完整组合(R4)

### 7.1 LocalityLbPolicy 7 种(backend service 内 intra-zone 路由)

| Policy | 算法 | 适用 |
|--------|------|------|
| **ROUND_ROBIN**(default) | 健康 backend 轮询 | 大多数场景 |
| **LEAST_REQUEST** | 选 2 个随机 + 选 active requests 较少的 | 长尾分布 |
| **RING_HASH** | Consistent hashing(1/N 命中率变化) | Cache 场景 |
| **MAGLEV** | Consistent hashing(更快 lookup) | 替代 RING_HASH |
| **RANDOM** | 随机选健康 backend | 简单场景 |
| **WEIGHTED_MAGLEV** | 用 health check header `X-Load-Balancing-Endpoint-Weight` 报告权重 | 灰度 / 蓝绿 |
| **WEIGHTED_ROUND_ROBIN** | 用 custom metrics 选 | 自定义容量信号 |

### 7.2 BalancingMode × LocalityLbPolicy 决策树

```
选 balancingMode(backend 跨 zone / region 路由):
  ├─ 短 HTTP 请求? → RATE(default)
  ├─ 长请求(>1s)? → IN-FLIGHT
  ├─ TCP 连接数? → CONNECTION
  ├─ CPU 利用率? → UTILIZATION(同 IG 必须统一 mode)
  └─ 自定义? → CUSTOM_METRICS

选 localityLbPolicy(backend service 内 intra-zone 路由):
  ├─ 默认? → ROUND_ROBIN
  ├─ Cache? → RING_HASH 或 MAGLEV
  ├─ 灰度? → WEIGHTED_MAGLEV 或 WEIGHTED_ROUND_ROBIN
  └─ 长尾? → LEAST_REQUEST
```

### 7.3 约束(必须看)

**R4 原文**:
> "Only use the UTILIZATION balancing mode with session affinity set to NONE. If your backend service uses a session affinity that's different from NONE, then use the RATE, IN-FLIGHT, or CONNECTION balancing modes instead."

**Session Affinity 4 种(R4)**:
- **NONE**(default):无亲和
- **CLIENT_IP**:按 client IP 哈希
- **CLIENT_IP_PROTO**:client IP + protocol(L4 NLB)
- **GENERATED_COOKIE**:HTTP LB 用 cookie(标准)
- **HEADER_FIELD**:按 HTTP header 字段
- **HTTP_COOKIE**:按 HTTP cookie 字段

---

## 8. URL Map weightedBackendServices 实战示例

### 8.1 跨 region 蓝绿(50/50 split)

```yaml
# URL map: 把 /api/* 按 50/50 路由到 europe-west2 + asia-east1 两个 backend service
apiVersion: compute.cnrm.cloud.google.com/v1
kind: ComputeURLMap
metadata:
  name: team1-api-um
spec:
  defaultService:
    reference:
      name: team1-api-default-bs
  hostRules:
  - hosts: ['team1.caep.uk']
    pathMatcher: api-matcher
  pathMatchers:
  - name: api-matcher
    defaultService:
      reference:
        name: team1-api-default-bs
    routeRules:
    - priority: 1
      matchRules:
      - pathMatch:
          prefixMatch: /api/
      routeAction:
        weightedBackendServices:
        - backendService:
            reference:
              name: team1-api-eu-bs      # europe-west2 backend
          weight: 50
        - backendService:
            reference:
              name: team1-api-asia-bs    # asia-east1 backend
          weight: 50
```

### 8.2 跨 region 故障转移(active-passive)

```yaml
# primary 100% 流到 europe-west2;e2 全 fail → 切到 asia-east1
routeRules:
- priority: 1
  matchRules:
  - pathMatch:
      prefixMatch: /api/
  routeAction:
    weightedBackendServices:
    - backendService:
        reference:
          name: team1-api-eu-bs         # 100% primary
      weight: 100
    - backendService:
        reference:
          name: team1-api-asia-bs       # 0% backup(平时不接)
      weight: 0
```

### 8.3 按 path 分流到不同 region

```yaml
# /api/videos/* → asia-east1(便宜,大存储);/api/users/* → europe-west2(快,低延迟)
routeRules:
- priority: 1
  matchRules:
  - pathMatch:
      prefixMatch: /api/videos/
  routeAction:
    weightedBackendServices:
    - backendService:
        reference:
          name: team1-videos-bs          # asia-east1
      weight: 100
- priority: 2
  matchRules:
  - pathMatch:
      prefixMatch: /api/users/
  routeAction:
    weightedBackendServices:
    - backendService:
        reference:
          name: team1-users-bs           # europe-west2
      weight: 100
```

---

## 9. Cloud DNS Routing Policy(辅助层)

**R6 原文**:
> "VIP addresses from multiple regions can share the same global backend service. You can configure **DNS-based global load balancing by using DNS routing policies** to route client requests to the closest VIP address."

**机制**(未独立 doc page,基于 R6 暗示 + 行业知识):
- 不是 GLB 替代品,是**辅助 GLB** 的客户端接入层
- 适用场景:**Cross-region internal ALB**(因为它的 VIP 是 region-local,客户端需要知道用哪个 VIP)
- 客户端先 DNS 解析 → Cloud DNS Routing Policy 按客户端地理位置返回**最近 region 的 VIP** → 客户端连那个 VIP → VIP 走 Layer 1-4 把流量送往后端

**⚠️ 5 条 unverified assumptions(本文件标记)**:

| # | 假设 | 验证状态 |
|---|------|---------|
| 1 | Cloud DNS Routing Policy 包含 geolocation / weighted / failover policy | ⚠️ 文档 URL `/dns/docs/routing-policy` 404,内容未在 2026-08-06 抓到的页面中 verbatim 出现;**靠 R6 间接引用推断** |
| 2 | Routing Policy 可针对 Internal ALB VIP 做 geolocation | ⚠️ 同上 |
| 3 | Routing Policy 与 GLB backend service 的健康检查联动(自动剔除不健康 VIP) | ⚠️ 同上 |
| 4 | Routing Policy TTL 默认 60s(Google 文档惯例) | ⚠️ 未验证 |
| 5 | Routing Policy 支持多个 record type(A / AAAA / CNAME) | ⚠️ 未验证 |

**Lex 实施建议**:Cross-region internal ALB **推荐配 Cloud DNS Routing Policy**(geolocation-based),
让客户端解析到最近 region 的 VIP,避免跨 region 网络跳转。

---

## 10. Anti-patterns(常见错误)

| 反模式 | 后果 | 正确做法 |
|--------|------|---------|
| 用 Regional external ALB 期望跨 region failover | ❌ 跨 region 切流量不生效 | 跨 region 用 Global external ALB |
| 用 Classic ALB 新架构 | ❌ Classic 已 deprecated,新功能不在 Classic | 用 Global external ALB |
| Standard Tier 配跨 region backends | ❌ Standard Tier 走公网,无 GFE | Premium Tier |
| UTILIZATION mode + non-NONE session affinity | ❌ 报错("Only use the UTILIZATION balancing mode with session affinity set to NONE") | UTILIZATION 必配 NONE;其他 mode 任意 |
| UTILIZATION mode 跨多个 backend service 共享 instance group | ❌ 报错("UTILIZATION balancing mode is incompatible with all other balancing modes") | 同一 IG 跨多 BS 必统一 UTILIZATION |
| Weighted backend service weight=0 + 唯一 backend | ❌ 不允许 weight 0(backend 被完全 drain) | weight 至少 1 |
| URL map priority 不排序(随机写大数) | ❌ 高 priority 的规则永远先 match,低 priority 永远不会触发 | 按业务优先级排 priority(数字**越低越先**) |
| Cross-region internal ALB 客户端跨 region 直接连 VIP | ❌ 跨 region 客户端需 global access flag | 启 global access **或** 配 Cloud DNS Routing Policy |

---

## 11. 关键事实摘要(决策表)

| 问题 | 答案 | 来源 |
|------|------|------|
| GCP 是否有独立 GTM 产品? | ❌ **没有**(GLB 本身就是 GTM) | R1 |
| 跨 region 调度靠什么? | ① Anycast IP + GFE 选址 + ② Capacity-aware balancingMode + ③ 跨 region 健康检查 | R1 + R4 + R5 |
| 公网跨 region LB 是哪个? | Global external Application LB | R7 |
| 内网跨 region LB 是哪个? | Cross-region internal Application LB | R6 |
| Classic ALB 还能用吗? | ⚠️ 能用但 deprecated(推荐迁到 Global external) | R7 |
| 跨 region failover 是自动的吗? | ✅ 是的(健康检查驱动,无需 DNS 切换) | R5 |
| 5 种 balancingMode 哪个最常用? | **RATE**(默认,短 HTTP 请求首选) | R4 |
| weightedBackendServices 优先级数字? | **数字越低越先** match(0 比 100000 先) | R3 |
| Cloud DNS Routing Policy 还需要配吗? | Cross-region internal ALB **强烈推荐**(因 VIP 是 region-local) | R6 |

---

## 12. 与 Lex 现有架构的契合度

Lex 当前架构(`glb+psc.md`):
- Tenant A 公网入口 = EXTERNAL_MANAGED GLB
- Tenant → Master PSC 跨 project
- Master 内部 = K8s Gateway + ListenerSet 多租户

**Lex 当前架构**只用了 **GLB 的公网入口**(没碰跨 region),所以 **本章覆盖的"跨 region 流量分配"是 forward-looking**,未来如果 Lex 想做:
- **DR / 多 region 灾备**:加 Global external ALB + 跨 region backend
- **就近访问**:加 Cloud DNS Routing Policy(geolocation)
- **跨 region 内部**:加 Cross-region internal ALB

参考实施步骤详见 R1 / R7 官方文档的"Setting up" 系列。

---

## 13. 一句话总结

> GCP GLB 通过 **4 层内置机制**(Anycast IP / Capacity balancingMode / 跨 region 健康检查 / URL map weightedBackendServices)
> 自动完成跨 region 流量分配 + 自动 failover,**不需要单独 GTM 产品**;
> **Cloud DNS Routing Policy 是辅助层**(尤其对 Cross-region internal ALB 的 region-local VIP),
> 让客户端 DNS 解析到最近 region 的 VIP。
>
> 决策起点:**公网跨 region → Global external ALB;内网跨 region → Cross-region internal ALB;**都需 Premium Tier。

---

## 14. 变更日志

- **2026-08-06**:初版(Lex 2026-08-06 探索请求)。12 个 GCP 官方文档 verbatim 引用(R1-R12)+ 5 种 LB 模式决策矩阵 + 4 层跨 region 路由机制 + URL map 实战示例 + 5 条 unverified assumptions(Cloud DNS Routing Policy 间接引用)