# GLB URL Map 大规模 API 配置评估方案 (1000+ API 场景)

本文针对 `springboot-app[X].aibang-id.uk.aibang` 模式的大规模 API 接入场景（假设 1000 个 API），从 GCP 资源配额 (Quota)、路由性能、权重 (Weight) 设置以及自动化运维等维度进行深度评估。

---

## 1. GCP GLB 配额 (Quotas) 评估

当 API 数量激增到 1000 个时，首要挑战是 GCP 项目和 URL Map 的硬限制。

### 1.1 关键配额限制 (默认参考值)

| 资源项 | 默认上限 (每项目/URL Map) | 1000 个 API 的影响 | 评估结果 |
| :--- | :--- | :--- | :--- |
| **Host Rules** | 50 - 250 (视 LB 类型) | 需要 1000 个 | **超限**。通常需要申请扩容。 |
| **Path Matchers** | 50 - 250 | 需要 1000 个 | **超限**。且 Path Matcher 过多会显著增加下发配置的延迟。 |
| **Route Rules** | 100 - 200 (每 Path Matcher) | 1000 个 | 如果将 API 归类，单 Matcher 也会超限。 |
| **URL Map 字符数** | 约 64KB - 256KB | 1000 个规则约 500KB+ | **极易超限**。JSON/YAML 文件过大会导致更新操作超时或失败。 |

### 1.2 应对策略：规则收敛
*   **泛域名匹配**：不要为每个 API 定义一个独立的 `hostRule`。
    *   *方案*：使用 `*.aibang-id.uk.aibang` 匹配所有长域名。
    *   *结果*：将 1000 个 `hostRule` 压缩到 **1 个**。
*   **Matcher 路由分发**：在同一个 `pathMatcher` 内部使用 `routeRules` 配合 `headerMatches` (Host 头部) 来区分不同的 API。

---

## 2. 路由权重 (Weight) 设置建议

在当前配置中，`weight: 100` 表示 100% 的流量流向指定的后端服务。

### 2.1 权重范围与定义
*   **范围**：0 到 1000 (GCP 内部计算单位通常在 0-100 之间分配比例)。
*   **总和验证**：同一个 `weightedBackendServices` 数组下，所有后端的 `weight` 总和必须正好等于 **100**。

### 2.2 生产环境建议值
*   **单后端 (当前场景)**：始终设为 `weight: 100`。
*   **灰度发布/蓝绿部署**：
    *   `v1-backend`: 90
    *   `v2-backend`: 10
*   **故障隔离**：不建议手动通过改 Weight 来剔除后端，应依靠健康检查 (Health Check) 自动摘除。

---

## 3. 大规模配置方案 (1000 API)

为了规避上述 Quota 限制并提高可维护性，建议采用以下架构：

### 3.1 架构优化：Host Header 匹配流
不再为每个 API 创建 Path Matcher，而是统一使用一个域名入口。

```json
{
  "hosts": ["*.aibang-id.uk.aibang"],
  "pathMatcher": "unified-api-matcher"
}
```

在 `unified-api-matcher` 内部：
```json
"routeRules": [
  {
    "priority": 10,
    "matchRules": [{ "prefixMatch": "/", "headerMatches": [{ "headerName": "Host", "exactMatch": "springboot-app1..." }] }],
    "routeAction": { "urlRewrite": { "pathPrefixRewrite": "/springboot-app1" } }
  },
  {
    "priority": 20,
    "matchRules": [{ "prefixMatch": "/", "headerMatches": [{ "headerName": "Host", "exactMatch": "springboot-app2..." }] }],
    "routeAction": { "urlRewrite": { "pathPrefixRewrite": "/springboot-app2" } }
  }
]
```

### 3.2 性能与维护风险
1.  **优先级冲突 (Priority Order)**：1000 个 API 的 `priority` 必须唯一。建议以 10 为步长 (10, 20, 30...)，为未来的微调留出空间。
2.  **更新延迟 (Propogation Time)**：当 `urlMap` 配置量极大时，执行 `gcloud compute url-maps import` 可能需要 **2-5 分钟** 才能在全球边缘生效。

---

## 4. 自动化管理方案 (GitOps)

手动维护 1000 个 JSON 字段几乎不可能，建议流程：

1.  **配置源 (CSV/YAML)**：维护一个简单的映射表。
    ```yaml
    apis:
      - name: springboot-app1
        rewrite: /springboot-app1
      - name: springboot-app2
        rewrite: /springboot-app2
    ```
2.  **生成脚本 (Python/Golang)**：编写脚本读取映射表，填充 `routeRules` 模板。
3.  **CI/CD 集成**：
    *   每次修改 Git 中的 YAML 后，自动触发脚本生成完整的 GLB JSON。
    *   自动运行 `gcloud compute url-maps validate` 检查语法和 Quota。
    *   通过 `gcloud compute url-maps import` 热更新 LB。

---

## 5. 总结建议

| 评估维度 | 建议方案 |
| :--- | :--- |
| **Host Rules** | **不扩容**。改用 `*.aibang-id.uk.aibang` 泛域名。 |
| **Path Matchers** | **维持在 5 个以内**。将 API 按 Team 或环境归类，不要按单个 API 划 matcher。 |
| **Route Rules** | **分片管理**。如果 API 超过 1000 个，建议考虑拆分多个 Load Balancer 来隔离风险。 |
| **Weight** | **静态 100**。仅在需要灰度发布时进行动态调整。 |
| **运维** | **自动化生成**。拒绝手动编辑 JSON，采用脚本生成机制。 |
