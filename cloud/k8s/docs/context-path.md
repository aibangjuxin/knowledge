# 平台统一 Context Path 注入策略 — 评估与可行性分析

> 范围：评估通过平台 ConfigMap 强制注入 `server.servlet.context-path`（Servlet 栈）与 `spring.webflux.base-path`（WebFlux 栈）为 `/${apiName}/v${minorVersion}` 的方案是否可行，并从**平台架构**视角说明其与 K8s 探针、网关路由、健康检查、SSL 注入之间的关系。

## 0. 摘要（TL;DR）

| 项 | 结论 |
|---|---|
| **可行性** | ✅ 可行，**前提**是同时定义 `startupProbe` / `livenessProbe` / `readinessProbe` |
| **核心收益** | 路径 = 版本标签；网关路由可模板化；多租户天然隔离 |
| **必要配套** | 探针 `httpGet.path` 必须**显式带上** `/${apiName}/v${minorVersion}` 前缀（K8s kubelet 不读应用 context-path） |
| **建议落地** | 与 `mini-change.md` 的"端口 8443 + SSL 注入 + TCP 探针"三件套一并下发，而不是只下发 context-path |

---

## 1. 问题陈述：为什么"统一 context path"会反过来强制我们必须定义 startup/liveness probe？

### 1.1 用户的原始问题

> "we want to remove the default context path for springboot and python API，因为如果用户没有用 `.well-known/health` 我们需要告诉他们 context path 是什么 就需要去定义 start liveness probe"

这句话的**因果链**拆开来其实是这样的：

```
【原因】.well-known/health 不是 Spring/Python 框架默认的探活端点
   ↓
【结果 1】用户的真实探活端点路径 = /${apiName}/v${minorVersion}/<user-defined>
   ↓
【结果 2】这个真实路径，**只有平台在注入 context-path 之后才能算出来**
   ↓
【结论】平台必须把"算出来的真实路径"塞进 K8s probe
   ↓
【推论】如果不塞进 probe，probe 就会去打 /healthz（200 路径不存在 / 默认 404 / 默认 401）
        → 探针通过 ≠ 业务可用 → 平台被迫定义 startup/liveness probe 来对齐
```

### 1.2 `.well-known/health` 是不是一个标准？

**严格意义上不是。** RFC 8615 (`Well-Known Uniform Resource Identifiers (URIs)`, 2019-05) 只定义了 `/.well-known/` 这个**路径前缀的保留机制**，并未把 `/health` 注册为 well-known 端点（IANA `Well-Known URIs` 注册表里没有 `health` 这一项）。生态中常见的"探活"惯例是：

| 框架 / 生态 | 探活端点（默认） | 是否在 context-path 下 |
|---|---|---|
| Spring Boot (Actuator) | `/actuator/health` | ✅ 受 `server.servlet.context-path` 影响 |
| Spring Boot (裸 Web) | 用户自定义 | ✅ 同上 |
| Spring WebFlux | 用户自定义 | ✅ 受 `spring.webflux.base-path` 影响 |
| FastAPI / Flask | 用户自定义 | ✅ 取决于 WSGI 框架（多数中间件支持） |
| Nginx L7 upstream check | `/` | N/A（不走应用） |

**结论**：因为**没有跨框架公认的"探活金标准"**，所以平台必须**自己定义**这个路径——而定义它的最佳方式，就是**复用已经注入的 context-path**。

### 1.3 这就是问题里说的"如果用户没有用 .well-known/health 我们需要告诉他们 context path 是什么" — 实际上有两层含义：

1. **用户层**：我们要给用户文档/错误信息，告诉他们"你们的探活端点真实路径是 X"，不要让用户自己猜。
2. **平台层**：K8s 探针 `httpGet.path` 必须**写完整路径**（含 context-path 前缀），否则它打不到正确的端点。

---

## 2. 方案本身：注入哪个属性、怎么注入

### 2.1 注入的两个属性

| 栈 | 属性 | 来源 |
|---|---|---|
| **Servlet 栈**（Spring MVC、Spring Web on Servlet 容器） | `server.servlet.context-path` | Spring Boot 官方属性 |
| **WebFlux 栈**（Spring WebFlux on Netty/Undertow） | `spring.webflux.base-path` | Spring Boot 官方属性 |

> 详细 ConfigMap 设计见 `mini-change.md` §3.2；本节只说明**两个属性同时下发**的原因（一个项目里通常只用一个栈，但平台不知道用户用了哪个，所以两个都发，应用按自己加载的栈自动识别）。

### 2.2 推荐的 ConfigMap 内容（修正版）

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mycoat-common-sprint-conf
  namespace: ${namespace}
data:
  server-conf.properties: |
    # ── 统一端口 + SSL（mini-change.md 要求 1）──
    server.port=8443
    server.ssl.enabled=true
    server.ssl.key-store=/opt/keystore/mycoat-sbrt.p12
    server.ssl.key-store-type=PKCS12
    server.ssl.key-store-password=${KEY_STORE_PWD}

    # ── 统一 Context Path（Servlet 栈）──
    server.servlet.context-path=/${apiName}/v${minorVersion}

    # 统一 Base Path (WebFlux 栈)
    spring.webflux.base-path=/${apiName}/v${minorVersion}
```

> 详细 ConfigMap 设计已在 `mini-change.md` §3.2 给出；本节只明确**两个属性必须同时下发**的原因（一个项目里通常只用一个栈，但平台不知道用户用了哪个，所以两个都发，应用按自己加载的栈自动识别）。

---

## 3. 关键架构问题：注入 context-path 之后，K8s 探针**必须**重新定义

### 3.1 为什么 TCP 探针不够用了

`mini-change.md` §"要求 2" 选了 TCP 探针作为兜底，理由是"用户 HTTP 健康接口完全不统一"。这在 **"只关心进程存活"** 的场景下成立，但引入 context-path 后会暴露一个**新的盲区**：

```
TCP 探针通过 (8443 端口可连接)
    ≠  Spring 容器已就绪 (Tomcat 接受连接但 DispatcherServlet 还没初始化完)
    ≠  Context-path 已生效 (用户代码里 @RequestMapping 已注册)
    ≠  业务健康 (DB / 下游依赖可访问)
```

**结论**：当 context-path 注入生效后，**必须**叠加 `startupProbe` + `httpGet` 的 `livenessProbe` / `readinessProbe` 来对齐"业务级健康"语义，而不能再只用 TCP。

### 3.2 K8s `httpGet` probe 的 `path` 必须显式带 context-path

这一点**反直觉但非常关键**：

> **K8s kubelet 在执行 `httpGet` 探针时，请求的是 Pod IP + containerPort + `path` 字段，路径是绝对路径，不会被任何反向代理、Istio sidecar 改写，也不会被应用的 `server.servlet.context-path` 改写。**

也就是说：

```yaml
# ❌ 错误：probe 路径没带 context-path
livenessProbe:
  httpGet:
    path: /actuator/health   # 实际打的是 GET /actuator/health
    port: 8443

# Spring 应用 context-path=/myapi/v1，Tomcat 看到的是：
#   GET /actuator/health  → 404 (没匹配任何 handler)
# K8s 判定: Probe failed → 容器被 kill → 启动崩溃循环
```

```yaml
# ✅ 正确：probe 路径 = 真实 context-path + 探活端点
livenessProbe:
  httpGet:
    path: /${apiName}/v${minorVersion}/actuator/health
    port: 8443
    scheme: HTTPS
```

### 3.3 探针分层推荐

| Probe | 探针类型 | path | 失败语义 | 平台策略 |
|---|---|---|---|---|
| `startupProbe` | `httpGet` | `/${apiName}/v${minorVersion}/<startup>` | 启动期失败 = 重启容器 | 必填，覆盖慢启动 |
| `readinessProbe` | `httpGet` | `/${apiName}/v${minorVersion}/<ready>` | 失败 = 从 Service endpoints 摘除 | 必填，与 Service / Pod readiness gate 对齐 |
| `livenessProbe` | `httpGet` | `/${apiName}/v${minorVersion}/<live>` | 失败 = kill 容器 | 必填，但要**轻量**（不要在 live 里查 DB） |

> 三个 path 的差异（`<startup>` / `<ready>` / `<live>`）建议由平台在 ConfigMap 模板里**统一下发**为同一个端点（如 `actuator/health`），减少用户理解成本；区分语义只对高级用户开放。

---

## 4. 平台架构视角的可行性评估

### 4.1 收益（对齐已有平台策略）

| 维度 | 评估 |
|---|---|
| **网关路由模板化** | ✅ Kong / GKE Gateway 可基于 `/${apiName}/v${minorVersion}` 自动生成 Route / HTTPRoute；与 `mini-change.md` "要求 3" 一致 |
| **多租户隔离** | ✅ 每个租户 `apiName` 独立 → 路径天然隔离；与 `istio-context.md` §7.2 "统一域名 + 租户路径" 模式一致 |
| **版本管理** | ✅ `${minorVersion}` 直接对应 Istio DestinationRule subset / GKE Gateway HTTPRoute 后端权重；与 `istio-context.md` §2 "Context Path 即 Version Tag" 一致 |
| **健康检查可发现** | ✅ 探针 path 由平台算出并下发，**用户不需要猜** |
| **Service Mesh 透明** | ✅ Istio / CSM 路由的是应用层 path，与 K8s kubelet 探针的 path 一致（两边都从同一个 ConfigMap 取值），不出现"探针通但 mesh 路由 404"的撕裂 |

### 4.2 风险与缓解

| 风险 | 严重度 | 缓解 |
|---|---|---|
| 用户应用**代码里写死**了 `@RequestMapping("/api/foo")`，没考虑 context-path | 🟡 中 | 大多数 Spring 用户习惯 `server.servlet.context-path`，能自动适配；少数写死的，需要在接入文档中明确 |
| `spring.webflux.base-path` 未在 ConfigMap 中正确下发 | 🟡 中 | ConfigMap 模板里此属性是必填项；漏配会导致 WebFlux 栈 context-path 不生效 |
| Python 框架（FastAPI / Flask）context-path 支持差异 | 🟡 中 | 多数 Python 框架通过 WSGI/ASGI middleware 模拟 context-path；平台应允许用户**自定义** `app.root_path` 之类的覆盖，或在 Nginx/Ingress 层做 prefix 剥离 |
| 用户自定义了 `server.servlet.context-path`，与平台注入冲突 | 🟡 中 | 平台 ConfigMap 用 `SPRING_CONFIG_LOCATION` 注入并放在用户 `application.yml` 之前，确保**平台值优先** |
| `startupProbe` `httpGet` 在 SSL 握手失败时也会"通过"吗？ | 🟢 低 | 不会。`httpGet` 用 scheme 字段显式指定 HTTP/HTTPS；SSL 配置错误会让 kubelet 报 `connection refused` 或 `tls handshake failure` |
| 探针 path 长度超过 K8s 限制？ | 🟢 低 | K8s 1.30+ 支持最长 4096 字符的 path；`/${apiName}/v${minorVersion}/actuator/health` 远低于此 |

### 4.3 与现有平台文档的一致性

| 平台已有立场 | 本方案的关系 |
|---|---|
| `gateway/docs/Design.md` "要求 1/2/3" | ✅ 完全对齐 — 8443 端口 + SSL + context-path 三件套 |
| `gateway/docs/Design.md` "健康检查统一使用 TCP" | ⚠️ **需要升级** — TCP 是兜底；引入 context-path 后必须叠加 httpGet probe |
| `gcp/asm/istio-context.md` §1 "Context Path 与 Request Path 一致性" | ✅ 完全对齐 — K8s probe path 与 Istio VS prefix 取同一个值 |
| `cloud/k8s/docs/mini-change.md` §3.2 ConfigMap 模板 | ✅ 已对齐 |

---

## 5. 落地建议（推荐方案）

### 5.1 实施 Checklist

| # | 改动 | 状态 |
|---|---|---|
| 1 | ConfigMap 模板双下发 `server.servlet.context-path` + `spring.webflux.base-path`（见 `mini-change.md` §3.2） | ✅ 已落 |
| 2 | `startupProbe` / `livenessProbe` / `readinessProbe` 全部用 `httpGet` 形式，path = `/${apiName}/v${minorVersion}/actuator/health`（TCP 探针保留作兜底） | ✅ 已落 |

### 5.2 完整 Probe 模板（推荐）

```yaml
startupProbe:
  httpGet:
    path: /${apiName}/v${minorVersion}/actuator/health
    port: 8443
    scheme: HTTPS
  periodSeconds: 10
  failureThreshold: 30   # 启动期 5 分钟宽容窗口
  timeoutSeconds: 3

readinessProbe:
  httpGet:
    path: /${apiName}/v${minorVersion}/actuator/health
    port: 8443
    scheme: HTTPS
  periodSeconds: 10
  failureThreshold: 3
  timeoutSeconds: 3

livenessProbe:
  httpGet:
    path: /${apiName}/v${minorVersion}/actuator/health
    port: 8443
    scheme: HTTPS
  periodSeconds: 20
  failureThreshold: 3
  timeoutSeconds: 3
```

### 5.3 给用户文档的话术（建议）

> 你的 API 探活真实路径 = **`/${apiName}/v${minorVersion}/<你的探活端点>`**
> - 已被平台注入到 K8s `startupProbe` / `livenessProbe` / `readinessProbe`，**你不需要自己写**
> - 如果你需要在代码里调用自己的健康端点，请使用上面的完整路径
> - 如果你需要自定义探活端点（如 `/livez` / `/readyz`），请在接入申请中说明，平台会同步更新 probe path

---

## 6. API 版本与计费

### 6.1 核心问题

`/${apiName}/v${minorVersion}` 这个 context path 把"版本号"直接固化到了**请求路径**里。这引出一个自然的担心：

> **路径即版本 → 计费维度会不会被路径锁死？平台的版本控制 / 计费粒度是不是丢掉了？**

答案：**没有丢掉。** 路径里的版本号是**计费维度的入口（key）**，不是计费维度本身。

### 6.2 路径版本号 ≠ 计费维度

| 维度 | 是不是"路径里那个版本号" | 平台能不能控制 |
|---|---|---|
| **大版本**（`v1` / `v2`，不兼容升级） | ✅ 是 `minorVersion` | ✅ 完全控制 — `minorVersion` 是平台变量 |
| **小版本 / 补丁**（`v1.1` / `v1.2`） | ⚠️ 默认不是（`minorVersion` 语义上指大版本） | ✅ 由 `${minorVersion}` 编码规则定义 |
| **计费等级**（免费 / 基础 / 企业） | ❌ 路径里**不体现** | ✅ 由计费服务独立判定（API Gateway 层） |
| **调用配额**（QPS / 月调用量） | ❌ 路径里不体现 | ✅ API Gateway 限流策略 |
| **用户身份**（租户 / 订阅 tier） | ❌ 路径里不体现 | ✅ 鉴权 + 路由层 |

**关键认知**：路径里的 `v${minorVersion}` 是**接口契约的版本**（用户调用的 API 形态），**计费维度是另一条独立链路**。

### 6.3 推荐的计费 ↔ 版本绑定模型

```
请求进入
   ↓
[1] API Gateway (Kong / GKE Gateway) 解析 path
      ↓
      /{apiName}/v{minorVersion}/...
   ↓
[2] 路由层：根据 apiName + minorVersion → 找到 Service + Subset
      ↓
[3] 计费层（独立）：从请求上下文读 (apiName, minorVersion, tenantId, userId) → 查计费规则 → 写计量
      ↓
[4] 转发到后端 Pod（context-path 已注入，无需二次处理）
```

**计费维度的来源**（与路径正交）：

| 计费字段 | 来源 | 路径里有吗 |
|---|---|---|
| `apiName` | ✅ 路径第 1 段 | ✅ |
| `minorVersion` | ✅ 路径第 2 段 | ✅ |
| `tenantId` | JWT / API Key / Header | ❌ |
| 调用次数 | API Gateway 计量插件 | ❌ |
| 响应大小 / 计费 unit | API Gateway 计量插件 | ❌ |
| 计费 tier（free/basic/enterprise） | 用户订阅系统（独立 DB） | ❌ |

### 6.4 大版本 vs 小版本 vs 补丁的语义约定

平台应在接入规范中**显式定义** `${minorVersion}` 的编码规则，否则会出现"两个用户对 v2 的理解完全不同"的情况。推荐：

| Path 片段 | 含义 | 计费规则 | 例子 |
|---|---|---|---|
| `v1` / `v2` / `v3` | **大版本**（不兼容升级） | 同一 apiName 下，**大版本可分别计费**（v2 可以是 v1 的 1.5x 单价） | `/${apiName}/v1/...` vs `/${apiName}/v2/...` |
| `v1.1` / `v1.2` | **小版本**（向后兼容） | 同一大版本下，**小版本不区分计费**（都是 v1 的单价） | `/${apiName}/v1.1/...` |
| `v1.1.3` | **补丁版本** | 平台不强制下放到 path（`minorVersion` 只取前两段即可） | — |

> **关键**：计费的"粒度"由 `${minorVersion}` 编码规则决定，**不是**由"路径里有没有版本"决定。平台可以决定"v1 和 v2 同价"或"v2 是 v1 的 2x"，这是**计费策略**问题，不是 context-path 设计问题。

### 6.5 多版本共存的计费案例

```yaml
# 同一个 apiName=order-api，多版本共存
# 计费规则：v1 = ¥0.01/call, v2 (含新字段) = ¥0.015/call

# 路由层（VirtualService / HTTPRoute）
http:
  - match: [{ uri: { prefix: "/order-api/v1" }}]
    route: [{ destination: { host: order-api, subset: v1 }}]
  - match: [{ uri: { prefix: "/order-api/v2" }}]
    route: [{ destination: { host: order-api, subset: v2 }}]

# 计费层（Kong 插件 / 独立计费服务）
billing_rules:
  - match: { apiName: "order-api", minorVersion: "v1" }
    unit_price: 0.01
  - match: { apiName: "order-api", minorVersion: "v2" }
    unit_price: 0.015
```

**用户**调用 `POST /order-api/v2/orders` → 平台按 `v2` 单价 ¥0.015 计费。context-path 的存在**让计费 key 自动可计算**。

### 6.6 反向情形：如果 context-path 不固化版本号会怎样？

假设改成 `/api/{apiName}/<user-defined-suffix>`（让用户自由定义版本）：

| 问题 | 影响 |
|---|---|
| 用户在代码里写 `@RequestMapping("/v1/orders")` | 路径散落，无法模板化 |
| 计费规则要逐个服务配置 | 平台维护成本 💥 |
| Istio VirtualService prefix 无法统一 | 多版本路由要 N 条规则 |
| K8s probe path 无法对齐 | 探针还是要依赖用户写死路径 |
| 用户可绕过计费（把 v2 接口写进 v1 path） | 治理失序 |

**结论**：**让路径带 `${minorVersion}` 不是"丢了计费粒度"，而是"让计费粒度可被平台控制"**。这正是 context-path 注入的核心架构价值。

### 6.7 一句话总结

> **路径版本号 = 计费 key 的输入，不是计费规则本身。平台对版本/计费的双重控制，来自于"路径 = 平台可计算 + 计费规则独立维护"的解耦设计，而不是来自"路径里有没有版本"。**

---

## 7. 结论

**这个方案可行，但不是一个独立可下发的最小单元**。它必须与 `mini-change.md` 已经规划的三件套（8443 端口 + SSL 注入 + 健康检查）**同步上线**，并把后者的探针从 TCP-only 升级为 "TCP 兜底 + httpGet 业务级" 双层结构。

一句话总结：

> **"统一 context path" 的本质是把路径变成"平台可计算的输入"——一旦可计算，K8s probe、Istio VS prefix、网关 Route 全部可以模板化。这是把平台从"用户填什么我接什么"升级为"用户什么都不填，平台算好下发"的关键一步。**

**配套资源模板**：

- Secret 模板见 `mini-change.md` §6（含 Java `springboot.conf` + Python `gunicorn.conf` 双栈示例 + Keystore 挂载方式）

---

## 8. 参考

- `cloud/k8s/docs/mini-change.md` — 平台最小化适配策略（端口 + SSL + context-path + 双层探针）
- `gateway/docs/Design.md` §3 — 平台最小化适配策略（probe + context-path 要求）
- `gcp/asm/istio-context.md` §1, §2, §7 — Context Path = Version Tag / 多租户场景
- RFC 8615 — *Well-Known Uniform Resource Identifiers (URIs)* (IETF, 2019-05) — 定义了 `/.well-known/` 路径前缀的保留机制；**未注册 `health` 端点**，所以 `.well-known/health` 不是标准
- Spring Boot 3.x Reference — `server.servlet.context-path` (Servlet 栈) / `spring.webflux.base-path` (WebFlux 栈)
