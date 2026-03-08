**GCP GLB URL Map 核心限制与配额深度指南**
*（修订版 · 基于 2026-03 官方文档复核）*
## 编者按：这篇文章里哪些点需要修正

这篇文章的主线判断是对的：`URL maps per project` 属于项目级软配额，而单个 URL Map 的容量瓶颈主要来自系统限制。但原稿把几类限制混在了一起，导致几个关键结论不够严谨。最需要修正的是这 6 点：

1. `128 KB` 不是所有 GLB 通用值。官方口径是 `Size of URL maps` 对 External ALB 为 `64 KB`，对 Internal ALB 为 `128 KB`，而且这是不可提升的系统限制。
2. `Internal ALB 最多 2000 个 Host Rules` 不是“无法验证”，官方 Quotas 页面明确写的是 `Host rules, path matchers per URL map`：External 为 `1000`，Internal 为 `2000`。
3. `单 matcher 大约 200 / 50 条 route rules` 这个说法不应再作为正式结论。官方限制分成两层：`Path rules or route rules per path matcher = 1000`，同时 `Predicates per path matcher = 1000`。对透明代理这类 `1 prefixMatch + 1 headerMatch` 的规则来说，实际更接近“单 matcher 约 500 条规则先撞到 predicates 限制”，不是 200 或 50。
4. `match conditions` / `predicates` 才是 routeRules 设计时更容易忽略的真正瓶颈，尤其是你用了 `headerMatches`、`queryParameterMatches` 之后，规则数和条件数不再是一回事。
5. `务必配置 tests 数组` 只适用于支持 URL map tests 的产品。官方 Quotas 页面明确写了 Internal ALB `N/A`，也就是内部 ALB 不支持 URL map tests，这条建议需要限定适用范围。
6. `证书池默认 15，扩容后约 100` 需要拆开写。官方区分了三种证书挂载方式：`Compute Engine SSL certificates per target proxy = 15`、`Certificate Manager certificates per target proxy = 100`、`Certificate Manager certificate maps per target proxy = 1`。这不是简单的“15 扩到 100”，而是取决于你采用哪种证书配置方式。

一句话总结：原稿在“URL Map 会先撞大小与 matcher 维度限制、需要尽早做分片”这个方向上是对的，但要把 `配置大小`、`host/path matcher 数量`、`route rules 数量`、`predicates 数量`、`证书挂载方式` 这些限制拆开看，否则很容易把设计容量估小或估错。

# GCP GLB URL Map 核心限制与配额 (Quotas & Limits) 深度指南

> [!IMPORTANT]
> **核心结论摘要 (Core Summary)**：
> 1. **配额性质**：`URL maps per project` (默认 250) 是**软配额**，可以在控制台申请扩展（无特殊硬性上限）。
> 2. **物理瓶颈**：`Size of URL maps` 对 **Internal ALB = 128 KB**、对 **External ALB = 64 KB**，这是系统限制
> 3. **能力上限**：`Host rules, path matchers per URL map` 对 **Internal ALB = 2000**、对 **External ALB = 1000**；`Path rules or route rules per path matcher = 1000`；`Predicates per path matcher = 1000`。
> 4. **设计含义**：对 `prefixMatch + headerMatch` 这类透明代理规则，实践中的瓶颈通常先落在 `predicates` 和 URL Map 大小，而不是“单 matcher 只有 200 或 50 条 route rules”。
> 5. **推荐架构**：针对大规模 API，建议采用 **“泛域名匹配 + 统一 Matcher”** 方案，通过请求头 (Header Matches) 分发流量，并在 `predicates` 或 URL Map 大小接近阈值时做分片。

在构建生产级、多租户或复杂的 API 流量链路时，对 URL Map 的配额（Quotas）和系统限制（Limits）的理解至关重要。本文针对 Internal HTTP(S) Load Balancing（内部负载均衡）进行专项探索。

---

## 1. 核心配额 (Quotas) 与 可调整性

### 1.1 项目级资源配额 (Soft Quotas)
这是你在 GCP 控制台“配额”页面看到的 `URL maps per project` 或 `URL maps per region`。
- **默认值**：通常为 **250**。
- **可调整性**：**是**。这是一个软配额。正如你在工程中观察到的，可以向 GCP 申请提高该上限（例如 500 或 1000）。
- **说明**：该配额限制的是**项目内 URL Map 资源对象的总数**，而不是单个 URL Map 内部规则的数量。

### 1.2 单个 URL Map 内部限制 (Hard Limits)
这些通常是**硬限制（System Limits）**，通过控制台申请调整通常非常困难或不支持。

| 限制项                      | 内部负载均衡 (Internal)  | 外部负载均衡 (External) | 评估建议                                           |
| :-------------------------- | :----------------------- | :---------------------- | :------------------------------------------------- |
| **URL Map 配置大小**        | **128 KB**               | **64 KB**               | 核心限制。限制的是整个配置对象的序列化字节数。     |
| **主机规则数 (Host Rules)** | **2000 个**              | 1000 个                 | 决定了你能配置多少个独立域名入口。                 |
| **单 Matcher 路由规则数**   | **1000 个**              | **1000 个**             | 官方限制项是 `path rules or route rules per path matcher`。 |
| **单 Matcher predicates**   | **1000 个**              | **1000 个**             | `headerMatches` / `queryParameterMatches` 会额外计数。 |

单 Matcher 路由规则数约 200 / 50 这个说法不应作为官方结论。
官方文档的限制需要拆开看：
每条 routeRule 的 predicates = 1（`prefixMatch` 或 `fullPathMatch`）
                        + `headerMatches` 数量
                        + `queryParameterMatches` 数量
因此规则数上限和 predicates 上限是两个不同维度。
---

## 2. URL Map 大小限制 (128KB) 深入解析

### 2.1 这个大小限制针对什么？
- **定义**：它指的是 **URL Map 资源对象的 JSON/YAML 序列化后的总字节数**。
- **包含内容**：所有的 `hostRules`、`pathMatchers`、`routeRules`、`urlRewrite`，以及在产品支持时可用的 `tests` 数组。
- **影响因子**：
    - 域名和路径的字符串长度。
    - 规则的数量。
    - 复杂的重写（Rewrite）和重定向（Redirect）逻辑描述。

### 2.2 为什么 128KB 会成为瓶颈？
如果你有 1000 个 API，且每个 API 都配置了：
1. 独立的长域名 `springboot-app[X]...`
2. 复杂的 `headerMatches`
3. 透明代理 `urlRewrite`
那么单个规则可能占用 300-500 字节。1000 个规则很容易突破 128KB 的物理限制。

---

## 3. 高级管理与预防性配置方法

针对复杂的 API 流量链路，建议采用以下“预防性”架构设计：

### 3.1 方案 A：泛域名 + 统一 Matcher (推荐)
避免为每个 API 创建 `hostRule`。
- **做法**：使用 `*.aibang-id.uk.aibang` 匹配所有请求。
- **优势**：极大地减少了 `hostRules` 的数量，节省了配置空间。
- **控制逻辑**：在 `pathMatcher` 内部使用 `routeRules` 进行精确分发。

### 3.2 方案 B：分片 (Sharding) 架构
如果单个 URL Map 的大小接近 128KB 警戒线：
- **做法**：按照业务线或 API 类型拆分多个负载均衡器（GLB）。
- **优势**：故障隔离，且每个逻辑组拥有独立的配额空间。

### 3.3 方案 C：自动化压缩验证
- **工具化**：使用脚本（如你目录下的 `verify-urlmap-json.sh`）在下发配置前预估大小。
- **GitOps**：通过 Git 管理配置，并在 CI/CD 中加入 `url-maps validate` 步骤。

---

## 4. 性能评定与生产建议

### 4.1 性能影响
- **匹配延迟**：Envoy 底层对前缀匹配和精确匹配进行了高度优化。即使有 1000 条规则，匹配延迟通常在微秒级别，对用户几乎无感。
- **传播延迟**：当配置接近 128KB 时，配置下发到全量边缘节点（Propagation Time）的时间会增加（可能从几英镑秒延长到分钟级）。

### 4.2 运维红线
1. **不要手动编辑 100+ 规则的 JSON**：极易出错且难以调试。
2. **务必配置 `tests` 数组**：由于规则多，容易出现优先级覆盖问题。`tests` 可以在下发前确保逻辑正确。
3. **监控 Quota 警报**：在 GCP 指标中监控 `url_maps/usage`。

## 5. 进阶架构：多 GLB 分片 (Sharding) 与 后端解耦

### 5.1 一个 URL Map 只能绑定一个 GLB 吗？
- **技术逻辑**：在 GCP 中，链路是 `Forwarding Rule` (IP) -> `Target Proxy` -> `URL Map`。
- **核心结论**：虽然一个 `Target Proxy` 必须指向一个 `URL Map`，但多个不同的 `Target Proxy`（甚至隶属于不同的 GLB）**可以引用同一个 URL Map**。
- **但为了突破 Quota**：如果你是为了解决 128KB 的硬限制，那么必须创建 **独立的 URL Map 资源**。通常配合独立的 GLB 使用，以实现完全的隔离。

### 5.2 方案：多 GLB + 独立 IP + 独立 URL Map
如果你面临以下生产级挑战，建议采用多 GLB 架构：
1.  **容量翻倍**：每个 URL Map 拥有独立的 128KB 配置空间。通过 2 个 GLB，你可以获得 256KB 的总路由表达能力。
2.  **物理隔离 (IP 层级)**：不同的 GLB 分配不同的 IP 地址。你可以为“核心 API”和“边缘 API”分配不同的入口 IP，防止流量冲击。
3.  **证书池扩展**：单个 Target Proxy 绑定的证书数量有限（默认 15，扩容后约 100）。多 GLB 可以绕过 SSL 证书数量瓶颈。

### 5.3 后端 MIG 的“万能复用”
你可以通过在 Backend Service 层面做文章，实现“物理收敛、逻辑分散”：
-   **共享 MIG**：GLB-A 和 GLB-B 的 Backend Services 可以同时挂载 **同一个 Nginx MIG**。
-   **逻辑分流**：
    -   `GLB-A` -> `BS-1` -> `Nginx MIG`
    -   `GLB-B` -> `BS-2` -> `Nginx MIG`
-   **优势**：在 LB 边缘你是多入口、多 Quota 空间的，但在后端维护上，你依然只需要维护一套 Nginx 集群，极大降低了运维成本。

> [!TIP]
> **方案 5 核心确认 (Key Confirmations)**：
> *   **绑定关系**：一个 `Target Proxy` 必须且只能绑定一个 `URL Map`。但是，你可以创建多个 `Target Proxy`（对应不同的 GLB 前端/IP）来引用不同的 `URL Map`。
> *   **突破 128KB**：通过创建多个逻辑独立的 URL Map 资源，可以完美绕过单文件 128KB 的序列化硬限制。
> *   **物理与逻辑解耦**：实现“前端多入口、多 Quota；后端物理发散、运维合一”的理想状态。

---

## 6. 终极架构方案：基于域名泛解析的 Team-based 分层分片 (Multi-Tenant Architecture)

这是一个极其优秀的“平台级”演进方案。通过**利用 DNS 泛解析的继承关系**配合 **IP 级别的分片**，你可以构建一个不仅能规避 Quota，还能实现“多租户自主管理”的弹性负载均衡中台。

### 6.1 核心逻辑流 (DNS -> IP -> LB -> URL Map)

1.  **域名层 (DNS Wildcards)**：
    *   在域名管理端配置多条泛解析记录：
        - `*.team-a.aibang.com` -> A 记录指向 `IP-A` (GLB-A)
        - `*.team-b.aibang.com` -> A 记录指向 `IP-B` (GLB-B)
2.  **入口层 (IP/Forwarding Rules)**：
    *   `IP-A` 绑定到 `GLB-A`，拥有独立的证书池。
    *   `IP-B` 绑定到 `GLB-B`，拥有独立的证书池。
3.  **路由层 (Sharded URL Maps)**：
    *   `GLB-A` 加载 `URLMap-TeamA`：内部只维护 Team A 的 API 改写逻辑（独立 128KB 空间）。
    *   `GLB-B` 加载 `URLMap-TeamB`：内部只维护 Team B 的 API 改写逻辑（独立 128KB 空间）。
4.  **后端实现层 (Backend Convergence)**：
    *   两个 GLB 的所有映射，最终都可以统一改写到 `Host: env-shortname...`，并透传给 **同一个后端 Nginx 资源栈**。

### 6.2 这种架构带来的核心优势：

| 维度                        | 优势说明                                                                                                          |
| :-------------------------- | :---------------------------------------------------------------------------------------------------------------- |
| **彻底规避 Quota**          | 将 128KB 的“全局配额”转化为“团队级配额”。理论上，通过增加团队（和对应的 GLB），总路由容量是 **无限扩展** 的。     |
| **故障隔离 (Blast Radius)** | 如果 Team A 的管理员不小心写错了一个优先级冲突，只会影响 Team A 域名下的流量，Team B 和全局核心域名完全不受影响。 |
| **配置复杂度降低**          | 每个 URL Map 的文件更小、逻辑更内聚，显著缩短了下发时的 **传播延迟 (Propagation Time)**。                         |
| **多租户自服务**            | 在 GitOps 模式下，你可以允许不同团队并发提交代码，而不需要全局锁定同一个巨大的 JSON 文件进行同步修改。            |

### 6.3 最佳实践思路
*   **分配子域**：为每一个接入的 Team 分配一个二级子域（如 `team-auth.aibang...`）。
*   **预留 IP 池**：在 GCP 提前申请并保留若干静态 IP 地址，作为负载均衡器的插槽。
*   **按需挂载**：当一个 Team 的 API 数量快达到 128KB 瓶颈时，再为该 Team 独立创建一个 GLB 实例进行分流。

> [!NOTE]
> **方案 6 逻辑精髓 (Logic Essence)**：
> 1. **DNS 层分流**：利用泛解析将不同团队的请求在“解析阶段”就精确导流给不同的 VIP。
> 2. **配额指数级增长**：每一个团队专用的 GLB 都拥有完整的 128KB 路由空间，理论上总容量无限。
> 3. **故障隔离 (Blast Radius)**：单一团队的配置错误或 Quota 撑爆不会对全局或其他团队产生任何连锁反应。
> 4. **维护成本平衡**：在 LB 边缘实现了流量的分而治之，但在物理层（Nginx 集群）依然共享资源，维持了极低的运维复杂度。

---

## 参考资料
- [GCP Load Balancing Quotas - URL Maps](https://cloud.cloud.google.com/load-balancing/docs/quotas#url_maps)
- [URL Masking vs Transparent Proxy Patterns](./flow-url-map.md)

## 补充参考资料（官方核查来源）
- [Google Cloud Load Balancing quotas and limits](https://cloud.google.com/load-balancing/docs/quotas)
- [Google Cloud URL map concepts](https://cloud.google.com/load-balancing/docs/url-map-concepts)
- [Google Cloud Internal Application Load Balancer traffic management](https://cloud.google.com/load-balancing/docs/l7-internal/traffic-management)
