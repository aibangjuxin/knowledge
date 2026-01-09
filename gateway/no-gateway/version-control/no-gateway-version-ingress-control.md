# Ingress Controller 平滑版本切换与重写最佳实践

本指南针对无法使用 GKE Gateway 的环境，探索如何通过传统的 Ingress Controller（以 NGINX Ingress 为例）实现 API 版本的平滑切换、URL 重写以及高可用发布。

---

## 1. Ingress vs. Gateway API：核心心智差异

| 特性 | GKE Gateway API | Ingress (NGINX) |
| :--- | :--- | :--- |
| **重写机制** | 原生 `URLRewrite` 过滤器 | 注解 `rewrite-target` |
| **流量切分** | `backendRefs` 权重 (Weight) | Canary 注解及独立 Ingress 对象 |
| **多版本共存** | Longest Match / Oldest Wins | 路径正则表达式优先级 |
| **冲突管理** | 严格的 Admission Webhook 校验 | 依赖 Controller 逻辑（可能发生合并或覆盖） |

---

## 2. NGINX Ingress 重写与版本抽象

在 Ingress 中实现类似 `ReplacePrefixMatch` 的效果，需要借助于捕获组（Capture Groups）和 `rewrite-target` 注解。

### 示例配置：大版本 v2025 路由

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-samples-ingress-v2025
  namespace: caep-int-common
  annotations:
    kubernetes.io/ingress.class: nginx
    # 开启正则支持
    nginx.ingress.kubernetes.io/use-regex: "true"
    # 将外部路径 /v2025/(.*) 重写为内部路径 /v2025.11.23/$1
    nginx.ingress.kubernetes.io/rewrite-target: /api-name-sprint-samples/v2025.11.23/$1
spec:
  rules:
  - host: env-region.aliyun.cloud.uk.aibang
    http:
      paths:
      - path: /api-name-sprint-samples/v2025/(.*)  # 使用 $1 捕获后续路径
        pathType: Prefix
        backend:
          service:
            name: api-name-sprint-samples-2025-11-23-service
            port:
              number: 8443
```

---

## 3. 冲突评估：同路径（Same Path）行为

### ❓ 场景：两个 Ingress 分别定义了相同的路径
如果 Ingress A 指向 Service A，Ingress B 指向 Service B，且 Path 都是 `/v2025`。

- **NGINX 行为**: NGINX Ingress Controller 通常会将这些规则**合并 (Merge)** 到同一个 Server 块下。
- **风险**: 具体的生效顺序往往取决于 Ingress 对象的名称（字母序）或创建时间，但这在高可用环境下是**不确定**的。
- **推荐**: 对于相同的外部路径，**不要创建多个 Ingress 对象**。应该通过更新现有 Ingress 的 `backend` 或使用官方的 Canary 机制。

---

## 4. 高可用平滑切换 (Canary 方案)

Ingress 环境下实现零停机发布最稳妥的方法是使用 **Canary Ingress**。

### 步骤 1：主 Ingress (Stable) 保持指向旧版
```yaml
metadata:
  name: api-samples-stable
```

### 步骤 2：部署 Canary Ingress (指向新版)
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-samples-canary
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10" # 10% 流量
spec:
  rules:
  - host: env-region.aliyun.cloud.uk.aibang
    http:
      paths:
      - path: /api-name-sprint-samples/v2025/(.*)
        pathType: Prefix
        backend:
          service: 
            name: service-v11-24 # 新版 Service
            port: { number: 8443 }
```

### 步骤 3：切流完成
当 Canary 流量验证通过后，将 Stable Ingress 的 `serviceName` 更新为新版，然后删除 Canary Ingress。

---

## 5. 常见问题总结 (FAQ)

**Q: 在 Ingress 中能实现“最长匹配优先”吗？**
A: 可以。NGINX 会优先匹配更长的正则表达式。如果你有一个 `/v2025/specific` 和一个 `/v2025`，前者会被优先匹配。

**Q: 为什么推荐在一个 Ingress 中更新而不是新建？**
A: 
1. **原子性**: `kubectl apply` 更新单个 Ingress 对象是原子的，Controller 会加载新配置而不中断现有链接。
2. **确定性**: 避免了多个对象竞争同一个 Path 导致的路由抖动（Flapping）。
3. **可维护性**: 一个外部契约（Host + Path）对应一个集群对象，逻辑清晰。

**Q: 如何验证 Ingress 重写是否成功？**
A: 开启 `nginx.ingress.kubernetes.io/enable-access-log: "true"` 并在日志中查看 `$request_uri` 和 `$upstream_addr`。
