# Explorer 2.0: FQDN, SAN, URLMap, and Nginx Simplification
- SAN 负责证书和 TLS 收敛，URL Map 负责 host/path 路由与内部 rewrite，Nginx 尽量退化成稳定后端
- SAN 能不能把“新增短域名”带来的证书与 listener 复杂度降下来；URL Map 能不能把“rewrite 和 host/path 兼容转换”尽量前移出 Nginx
- 如果短域名继续用 api01.team01.app.aibang 这种两层子域格式，单张 *.app.aibang wildcard 证书是覆盖不了的。
这意味着证书和 SAN 策略会直接受域名命名规则影响，所以“短域名命名设计”本身就是架构简化的关键点，不只是证书配置问题。
## 1. Goal and Current Context

你的现状可以抽象成两套入口并存：

### 旧模式：长域名

- `https://www.aibang.com/API01`
- `https://www.aibang.com/API02`

特点：

- 统一 GLB 入口
- 统一域名
- 依赖 Nginx `location /APIxx` 做路径分流

### 新目标：短域名

- `https://api01.team01.app.aibang`
- `https://api02.team02.app.aibang`

你的诉求不是“替换旧链路”，而是：

1. 保持现有长域名链路继续可用
2. 新增短域名入口
3. 长域名请求进入 GLB 后，不改变浏览器地址栏
4. 尽量减少为了短域名而新增的大量 Nginx listener / server_name / rewrite / 证书维护

---

## 2. 从你之前的历史探索里能复用什么

我在仓库里检索到两条与你现在这个问题高度相关的历史思路：

### 2.1 URL Map 路线

你之前已经探索过这些能力：

- `hostRules`
- `pathMatchers`
- `routeRules`
- `urlRewrite`
- `defaultService`

相关历史材料：

- [URLmapMatch.md](/Users/lex/git/knowledge/gcp/cloud-armor/dedicated-armor/URLmapMatch.md)
- [cloud-armor-change.md](/Users/lex/git/knowledge/gcp/cloud-armor/cloud-armor-change.md)
- [qwen-read-cross-project.md](/Users/lex/git/knowledge/gcp/network/qwen-read-cross-project.md)

其中最有价值的结论是：

**如果对外是一个简洁入口，但后端仍然依赖老路径，URL Map 的 `routeRules + urlRewrite` 可以把“外部短路径/短域名”映射成“内部老路径”，而不需要让浏览器发生 30x 跳转。**

这点和你的“浏览器地址栏不变”目标完全一致。

### 2.2 Nginx 路线

你也已经有存量模式：

- `location /APIxx`
- `proxy_set_header Host www.aibang.com`
- `rewrite`

相关痕迹：

- [flow-debug-gemini.md](/Users/lex/git/knowledge/sre/docs/flow-debug-gemini.md)
- [how-to-debug-flow.md](/Users/lex/git/knowledge/sre/docs/how-to-debug-flow.md)
- [cloud-armor-change.md](/Users/lex/git/knowledge/gcp/cloud-armor/cloud-armor-change.md)

这说明你当前架构里，Nginx 实际承担了两件事：

- 路由适配
- Host/path 兼容转换

所以现在真正值得问的问题不是“SAN 能不能替代一切”，而是：

**SAN 能不能把“新增短域名”带来的证书与 listener 复杂度降下来；URL Map 能不能把“rewrite 和 host/path 兼容转换”尽量前移出 Nginx。**

---

## 3. SAN 在这个需求里真正能做什么

### 3.1 SAN 能解决“证书覆盖多个域名”

如果你要同时支持：

- `www.aibang.com`
- `api01.team01.app.aibang`
- `api02.team02.app.aibang`

那么 SAN 可以让同一张证书声明自己覆盖这些 host。

这意味着：

- 不一定要为每个短域名单独维护一张证书
- 也不一定要在 Nginx 上为每个域名单独做一套 TLS 终止

### 3.2 SAN 能配合 SNI，让 GLB 按 Host 提供正确证书

当客户端访问：

```text
https://api01.team01.app.aibang
```

TLS 握手时会带上 SNI。负载均衡器或入口代理可以根据这个 hostname 选择匹配的证书。

如果证书 SAN 覆盖该域名，请求就能在 TLS 层合法通过。

### 3.3 SAN 可以减少 Nginx 的证书负担

如果 TLS 终止放在 GLB，而不是放在 Nginx，那么 Nginx 就不必：

- 为每个短域名新增 `listen 443 ssl`
- 为每个短域名挂单独证书
- 为每个短域名做单独 `server_name`

这就是 SAN 最直接的简化价值。

---

## 4. SAN 不能单独解决什么

这里要特别明确，避免误判。

### 4.1 SAN 不能替代路由

SAN 只解决“证书是否匹配这个域名”，不解决：

- `api01.team01.app.aibang` 应该去哪个 backend
- 是否要映射到旧路径 `/API01`
- 是否要改写 Host 为 `www.aibang.com`

这些仍然属于：

- URL Map
- Gateway / Ingress
- 或 Nginx

### 4.2 SAN 不能自动减少所有 Nginx 配置

如果你还是让 Nginx 来做：

- TLS 终止
- Host 识别
- 路径改写

那么 SAN 只是减少证书张数，不会根本消除 Nginx 的配置复杂度。

真正能明显简化 Nginx 的前提是：

**把 TLS 终止和尽可能多的 host/path rewrite 上移到 GLB/URL Map。**

---

## 5. 一个关键现实：你的短域名格式对 wildcard 很不友好

你给出的短域名是：

- `api01.team01.app.aibang`
- `api02.team02.app.aibang`

这类域名最需要先澄清 wildcard 证书边界。

根据 Google Cloud Certificate Manager 文档，wildcard 只匹配**第一层子域**，不能覆盖更深层级的名字。比如 `*.myorg.example.com` 只能覆盖一级子域，不能覆盖 `sub.subdomain.myorg.example.com` 这类更深层级域名。[来源](https://docs.cloud.google.com/certificate-manager/docs/certificate-manager-best-practices) [来源](https://docs.cloud.google.com/certificate-manager/docs/certificate-selection-logic)

这意味着：

- `*.app.aibang` 可以匹配 `foo.app.aibang`
- 但**不能**匹配 `api01.team01.app.aibang`

所以对你现在这种命名方式：

### 不能直接用一张 `*.app.aibang` 证书全覆盖

这点非常关键，因为它直接决定 SAN 能否“极大简化”你的证书与 Nginx 设计。

### 你有三种证书策略

#### 策略 A：显式多 SAN

把每个短域名单独加入 SAN：

- `api01.team01.app.aibang`
- `api02.team02.app.aibang`
- ...

优点：

- 最直接
- 不改域名设计

缺点：

- SAN 会快速膨胀
- 每新增一个短域名，证书都可能要重新签发或更新

#### 策略 B：按 team 用 wildcard

例如：

- `*.team01.app.aibang`
- `*.team02.app.aibang`

优点：

- 每个 team 下的 API 可以复用 wildcard
- 比逐条 SAN 好一些

缺点：

- team 越多，证书项越多
- 仍然不是一张全局 wildcard 解决

#### 策略 C：调整短域名命名规则

例如改成：

- `team01-api01.app.aibang`
- `team02-api02.app.aibang`

或者：

- `api01-team01.app.aibang`

这样一来：

- `*.app.aibang` 就可以统一覆盖

这是我认为**最值得认真评估**的架构点。

因为它不是微观配置优化，而是直接改变了证书和入口治理的复杂度。

---

## 6. SAN + URLMap 能否简化你的架构

答案是：**能，但关键不在 SAN 单独发力，而在 SAN 和 URL Map 分工明确。**

### 6.1 SAN 负责 TLS 入口收敛

你可以让 GLB 挂：

- `www.aibang.com`
- 短域名证书（显式 SAN、按 team wildcard，或统一 `*.app.aibang`）

这样 TLS 终止统一在 GLB。

### 6.2 URL Map 负责 Host-based routing 和内部 rewrite

你之前探索过的 `hostRules + routeRules + urlRewrite` 正好适合这个场景。

基于官方 URL Map 文档，URL Map 可以按 host/path 选择 backend，并在转发前做 `urlRewrite`。`urlRewrite` 同时支持 `pathPrefixRewrite` 和 `hostRewrite`。[来源](https://docs.cloud.google.com/compute/docs/reference/rest/v1/urlMaps)

这带来两个非常重要的能力：

#### 能力 1：短域名流量进入后，内部重写成老路径

例如：

- 用户访问：`https://api01.team01.app.aibang/`
- URL Map 内部转发为：`/API01/`

这样后端仍然可以沿用老路径模型。

#### 能力 2：必要时把后端看到的 Host 改写成旧域名

例如：

- 客户端看到的 Host：`api01.team01.app.aibang`
- 后端 Nginx 实际收到的 Host：`www.aibang.com`

这样就能大幅减少后端对“新短域名”的感知。

---

## 7. 对你当前诉求的三种可行架构

### 方案 1：最小改动方案

#### 做法

- 继续保留现有 `www.aibang.com/APIxx`
- 新增短域名证书覆盖
- GLB 仅按 host 把短域名流量送到现有 Nginx
- Nginx 继续做 rewrite 到旧路径

#### 优点

- 改动最小
- 风险最低

#### 缺点

- Nginx 仍然要感知短域名
- 仍可能需要新增 `server_name` / rewrite 逻辑

#### SAN 的价值

- 主要用于减少证书复杂度
- 对 Nginx 路由复杂度帮助有限

### 方案 2：推荐的平衡方案

#### 做法

- TLS 终止放到 GLB
- GLB 通过 SAN/证书覆盖长域名和短域名
- URL Map 用 `hostRules + routeRules + urlRewrite`
- 对短域名流量做内部 path rewrite，必要时做 `hostRewrite`
- Nginx 只保留少量通用 upstream 配置，不再为每个短域名写独立监听和证书

#### 优点

- 同时满足长域名和短域名并存
- 浏览器地址栏不变，因为是内部 rewrite，不是 redirect
- 最大化减少 Nginx 中的 listener / cert / rewrite 数量

#### 缺点

- URL Map 配置复杂度上升
- 需要更严格地管理 host/path 规则

#### SAN 的价值

- 很高
- 它让 GLB 能承接短域名 TLS 终止，前提是证书策略设计合理

### 方案 3：长期理想方案

#### 做法

- 重新设计短域名命名，使其可被 `*.app.aibang` 覆盖
- GLB 做统一 TLS 终止
- URL Map 做 host/path 分流与内部 rewrite
- 后端逐步摆脱“老路径”模型

#### 优点

- 证书治理最简单
- Nginx 最轻
- 新增短域名成本最低

#### 缺点

- 需要调整命名规范
- 涉及产品和平台层面的迁移

---

## 8. 推荐的 V1 实现思路

如果你现在要做一个现实、可落地的版本，我建议按这个顺序：

### Step 1：先保留现有长域名完全不动

保留：

- `https://www.aibang.com/API01`
- `https://www.aibang.com/API02`

不要先改老链路。

### Step 2：短域名只新增入口，不做 30x 跳转

例如：

- `https://api01.team01.app.aibang`

进入 GLB 后，内部 rewrite 到老路径：

- `/API01`

但客户端地址栏保持短域名不变。

这一步应该用：

- `routeRules`
- `urlRewrite`

而不是 `urlRedirect`

因为 `urlRedirect` 会改变浏览器地址栏，不符合你的要求。

### Step 3：把 TLS 终止统一放到 GLB

这样 Nginx 不再为短域名做新证书挂载。

### Step 4：把 Nginx 变成“尽量无感知短域名”的后端

理想状态下，Nginx 只处理：

- 来自 GLB 的标准化 Host
- 来自 GLB rewrite 后的标准化 Path

也就是让它更像一个稳定 backend，而不是入口网关。

---

## 9. URL Map 示例思路

下面是概念示意，不是可直接执行的最终生产 YAML。

### 9.1 长域名继续走老路径

```yaml
hostRules:
  - hosts:
      - www.aibang.com
    pathMatcher: long-domain
  - hosts:
      - api01.team01.app.aibang
      - api02.team02.app.aibang
    pathMatcher: short-domain
```

### 9.2 Path matcher：长域名

```yaml
pathMatchers:
  - name: long-domain
    defaultService: bs-nginx
    pathRules:
      - paths:
          - /API01
          - /API01/*
        service: bs-nginx
      - paths:
          - /API02
          - /API02/*
        service: bs-nginx
```

### 9.3 Path matcher：短域名

```yaml
pathMatchers:
  - name: short-domain
    defaultService: bs-nginx
    routeRules:
      - priority: 10
        matchRules:
          - prefixMatch: /
        service: bs-nginx
        routeAction:
          urlRewrite:
            pathPrefixRewrite: /API01/
            hostRewrite: www.aibang.com
```

这个模型的意义是：

- 客户端访问短域名
- GLB 内部把路径改成老路径
- 后端继续像处理 `www.aibang.com/API01` 一样处理请求

这样 Nginx 就不需要额外维护很多“短域名 -> 老路径”的手工逻辑。

---

## 10. Nginx 能被简化到什么程度

### 10.1 可以被明显简化的部分

如果把 TLS 和 rewrite 前移到 GLB，Nginx 可以少掉：

- 每个短域名一套 TLS 证书配置
- 每个短域名一套 `server_name`
- 每个短域名一套入口 rewrite

### 10.2 不一定能完全消失的部分

如果后端应用仍然强依赖：

- 特定 Host
- 特定路径结构
- 特定 header

那么 Nginx 可能仍要保留：

- 通用反代逻辑
- header 补充
- 少量兼容 rewrite

但这已经比“每加一个 team/api 就加一段 Nginx server/location”轻很多了。

---

## 11. 对 SAN 的实际评估结论

### SAN 能帮你简化什么

- 减少短域名接入时的证书管理复杂度
- 支持在 GLB 统一做 TLS 终止
- 为 host-based routing 提供合法证书基础

### SAN 不能单独简化什么

- 不能自动替代 URL Map
- 不能自动把短域名映射成老路径
- 不能单独消除 Nginx 的全部兼容逻辑

### 对你这个需求，真正起决定作用的是

**`SAN/证书策略 + URL Map host/path/rewrite 设计 + 短域名命名规则`**

这三件事缺一不可。

---

## 12. 我对你这个场景的直接建议

### 建议 1：不要把希望都压在 SAN 上

SAN 是证书层能力，不是路由层能力。

### 建议 2：优先推进“GLB 终止 TLS + URL Map 内部 rewrite”

这是最有机会减少 Nginx 配置的方向。

### 建议 3：认真复盘短域名命名

如果你坚持：

- `api01.team01.app.aibang`

那么证书治理会比看上去复杂很多，因为 `*.app.aibang` 无法覆盖它。

如果你能改成：

- `team01-api01.app.aibang`

或者：

- `api01-team01.app.aibang`

那么一张 `*.app.aibang` 的 wildcard 证书就能显著简化架构。

这一步的价值，甚至可能大于后续所有微观配置优化。

### 建议 4：V1 先做“并存”，不要先做“替换”

先做到：

- 长域名继续用
- 短域名可接入
- 地址栏不变
- Nginx 配置新增最少

这是最稳妥的版本。

---

## 13. Final Recommendation

基于你现在的需求，我给出的结论是：

**SAN 可以成为短域名方案的重要组成部分，但它最适合承担“统一证书与 TLS 入口”的职责；真正能够简化 Nginx 和兼容旧长域名路径模型的，应该是 URL Map 的 host/path 路由与内部 rewrite 能力。**

最推荐的落地方向是：

1. 保留 `www.aibang.com/APIxx` 不动
2. 新增短域名入口
3. 在 GLB 统一终止 TLS
4. 用 URL Map 对短域名做 host/path 匹配和内部 rewrite
5. 尽可能让 Nginx 退化成稳定后端，而不是继续做入口适配层

如果只做一句话总结：

**对你的场景，SAN 更像“入口证书收敛器”，URL Map 才是“短域名落地与 Nginx 简化器”。**

---

## Sources

- [Use URL maps](https://docs.cloud.google.com/load-balancing/docs/url-map)
- [URL Maps REST reference](https://docs.cloud.google.com/compute/docs/reference/rest/v1/urlMaps)
- [Certificate Manager best practices](https://docs.cloud.google.com/certificate-manager/docs/certificate-manager-best-practices)
- [Certificate selection logic](https://docs.cloud.google.com/certificate-manager/docs/certificate-selection-logic)
- [URLmapMatch.md](/Users/lex/git/knowledge/gcp/cloud-armor/dedicated-armor/URLmapMatch.md)
- [cloud-armor-change.md](/Users/lex/git/knowledge/gcp/cloud-armor/cloud-armor-change.md)
- [qwen-read-cross-project.md](/Users/lex/git/knowledge/gcp/network/qwen-read-cross-project.md)
