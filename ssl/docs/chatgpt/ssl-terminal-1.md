# 单一 GKE Gateway 方案评估（基于 ssl-terminal.md 的“想要的配置”）

## 1. 结论

可以实现：使用一个 `gke-gateway.intra.aibang.com` 承接所有来自 Nginx 的请求。  
前提是你接受“路由主维度从 Host 变成 Path（或 Header）”并完成配套改造。

不满足这些前提时，则不建议合并为单 Gateway。

复杂度：`Moderate`

---

## 2. 为什么可以实现

你的新配置核心是：

- Nginx 对外终止 TLS（短域名和长域名都在 Nginx 层完成证书处理）
- Nginx 转发到同一个上游 `https://gke-gateway.intra.aibang.com`
- 转发时统一 `Host: www.aibang.com`
- 通过 URI 前缀（如 `/api-name-team-name/`）区分后端路由

这意味着 GKE Gateway 不再依赖“不同 Host 对应不同 Gateway/证书”，而是可用一个 Gateway + 多条 HTTPRoute（path match）完成分流。

---

## 3. 什么情况下不可以（或不该）合并

以下任一项成立时，不建议只用一个 Gateway：

1. 后端应用强依赖原始 Host（多租户识别、绝对跳转、Cookie Domain、OAuth 回调、签名校验）。
2. 你需要在 Gateway 层做按域名隔离的安全策略（不同 Cloud Armor 策略、不同 mTLS/认证策略、不同配额）。
3. 你希望保留“域名级”可观测性与故障隔离（按 Host 统计 SLA、限流、熔断、回滚）。
4. Path 命名无法长期保证全局唯一，未来团队增多会出现路由冲突。

---

## 4. 最大影响（你最需要关注的）

最大影响是：**租户/业务边界从“域名隔离”退化为“路径隔离”**。

它会带来：

1. 隔离粒度下降：
   一个 Gateway 变更可能影响全部租户流量。
2. 安全与治理复杂化：
   原先按 Host 生效的策略，需要改成 path/header 维度，规则更脆弱。
3. 可观测性语义变化：
   指标从 Host 聚合变成 Path 聚合，排障模型要重建。
4. 应用兼容风险：
   固定 `Host: www.aibang.com` 后，依赖原域名的服务可能出现重定向/CORS/Cookie 异常。

---

## 5. 必评估清单（上线前）

### A. 路由与协议

- 是否所有 API 都有稳定且唯一的 path 前缀？
- 是否需要在 Nginx 做 `rewrite` 去掉前缀，再转发到后端？
- 是否保留 `X-Forwarded-Host` 传递原始 Host 给后端？

建议至少加：

```nginx
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Proto https;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```

### B. TLS 与证书

- Nginx -> Gateway 的 TLS 校验是否开启（`proxy_ssl_verify on`）？
- Gateway 证书是否覆盖 Nginx 实际校验名（SNI/`proxy_ssl_name`）？
- 如果你目标是“TLS 终止前移到 Nginx”，是否可接受内网改 HTTP（仅在明确安全边界时）？

### C. 安全与策略

- Cloud Armor 规则是否仍能精确区分不同 API/租户？
- 是否需要用 header（如 `X-Tenant-ID`）增强策略匹配，而不只靠 path？
- 单 Gateway 失误发布是否会扩大 blast radius？

### D. 可靠性与发布

- 单 Gateway 是否有独立变更窗口、灰度和回滚机制？
- 是否设置了 per-route 超时、重试、熔断避免相互拖垮？
- Nginx 与 Gateway 的容量/HPA/PDB 是否按“全量流量”重新评估？

### E. 观测与审计

- 日志是否记录原始 Host、重写后 path、目标 service？
- SLI/SLO 是否从“按域名”调整为“按 API 前缀/租户”看板？

---

## 6. 建议落地路径（V1）

1. 新建单一 Gateway（或在现有短域名 Gateway 扩展）并加入全部 path 规则。  
2. Nginx 保留原 Host 到 `X-Forwarded-Host`，先不要让后端失去原域名信息。  
3. 小流量灰度：先迁移 1~2 个长域名 API，验证重定向/CORS/Cookie/OAuth。  
4. 通过后再批量迁移，最后下线 `gke-gateway-for-long-domain.intra.aibang.com`。  
5. 保留快速回切：Nginx 按 location 可一键切回旧 Gateway。

---

## 7. 对你问题的直接回答

- 能否用一个 `gke-gateway.intra.aibang.com` 处理所有请求？  
  - **可以**，在“统一 Host + path 分流”模型下可行。

- 如果可以，理由是什么？  
  - 因为你的流量入口已统一在 Nginx，Gateway 只需按 path 路由，不再需要按域名拆多个 Gateway 和证书。

- 如果不可以，理由是什么？  
  - 当后端/策略必须依赖原始 Host 做隔离与治理时，不应强行合并。

- 最大影响是什么？  
  - 隔离边界从 Host 降到 Path，导致变更风险面扩大。

- 还要评估什么？  
  - Host 兼容性、TLS 校验链路、安全策略粒度、单点变更风险、观测模型重构（详见第 5 节）。
