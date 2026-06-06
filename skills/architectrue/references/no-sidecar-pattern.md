---
name: no-sidecar-pattern
description: Istio No-Sidecar Same Namespace Pattern — Gateway + HTTPRoute + DestinationRule in same NS, Runtime NS only has Service. Use when designing multi-tenant Istio ingress without sidecar proxies on GKE.
category: architectrue
---

# Istio No-Sidecar: Same Namespace Pattern

**核心规则**: Gateway + HTTPRoute + DestinationRule 放在同一个 Namespace，Runtime Namespace 只放 Service 和 Pod。

## ⚠️ 重要：区分 GKE Gateway vs Istio Gateway API

| 对比项 | GKE Gateway | Istio Gateway API (`gatewayClassName: istio`) |
|--------|-------------|---------------------------------------------|
| **API 版本** | `gateway.networking.k8s.io/v1` | `gateway.networking.k8s.io/v1` |
| **底层设施** | Google Cloud Load Balancer (GCLB) — 在集群外部 | Envoy Pods — 在集群内部 |
| **Pod 管理** | Google 自动管理 | ASM/Istiod 自动管理 |
| **配额限制** | GCLB Forwarding Rules (默认 500/Region) | Ingress Gateway Envoy 共享池 |
| **Cloud Armor** | ✅ 支持 | ❌ 不支持（需要叠加 GKE Gateway） |
| **mTLS** | ❌ 不支持 | ✅ 支持 |

**常见误区**: "Gateway CRD 不创建 Pod = 可以无限创建"

**这是错误的**。所有 Gateway 资源共享同一个 Ingress Gateway Envoy 代理池：
- Envoy 配置大小有上限（大量路由 → 超大配置 → OOM）
- Istiod 内存有限（1000 个 Gateway ≈ 500MB+ Istiod）
- Ingress Gateway Pod 有实际 CPU/内存限制

**实测规模参考**：
- < 50 个 Gateway：无感
- 50-200：监控 Istiod 内存，考虑 HPA
- 200-500+：需要水平扩展 ingressgateway，分 namespace

## 最小工作集（3 个资源）

| Resource | Namespace | 作用 |
|----------|-----------|------|
| **Gateway** | `tenant-gateway-ns` | TLS 终止 + 监听 |
| **HTTPRoute** | `tenant-gateway-ns` | 路由规则（可与 Gateway 同 NS） |
| **DestinationRule** | `tenant-gateway-ns` | TLS re-encrypt（必须在 Gateway 同 NS） |
| **Service** | `tenant-runtime-ns` | 后端（istio-injection: disabled） |

## ReferenceGrant 何时需要

| 场景 | 需要 RefGrant? | 位置 |
|------|---------------|------|
| Gateway → 同 NS Secret | ❌ 不需要 | — |
| HTTPRoute + Gateway 同 NS | ❌ 不需要 | — |
| HTTPRoute → 跨 NS Service | ✅ 需要 | 目标 Service 所在 NS |
| Gateway → 跨 NS Secret | ✅ 需要 | Secret 所在 NS |

## 多租户模式

**一对一（推荐）**:
```
tenant-a-gateway-ns/  →  Gateway + HTTPRoute + DestinationRule
tenant-a-runtime-ns/ →  Service (no sidecar)
```

**共享 Gateway**:
```
shared-gateway-ns/     →  Gateway + DestinationRules
tenant-a-ns/           →  HTTPRoute (需要 RefGrant)
```

## 参考资料

- `/Users/lex/git/gcp/istio/no-sidecar/` — deploy.yaml, deploy-shared.yaml, v4.html
- `/Users/lex/git/knowledge/docs/gcp/asm/diagram/v4.html`
