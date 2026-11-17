---
name: gke-policy-controller-vs-gatekeeper
description: GKE Policy Controller 与开源 OPA Gatekeeper 选型决策指南。涵盖单集群/多集群支持、Fleet 依赖、跨云场景推荐。
---

# GKE Policy Controller vs Open Source OPA Gatekeeper

## TL;DR Summary

| 场景 | GKE Policy Controller | 开源 Gatekeeper |
|------|---------------------|-----------------|
| 单集群安装 | ✅ 支持 | ✅ 支持 |
| 多集群统一管理 | ✅ Fleet 原生支持 | ❌ 需 GitOps 工具 |
| Fleet 依赖 | **必须** | 不需要 |
| 跨云（GKE + ACK） | ❌ 仅限 GKE | ✅ 支持 |
| 策略包 | 100+ 官方预置 | 需自行编写/导入 |
| 版本更新 | 跟随 GKE | 独立迭代 |

---

## Key Architectural Decision

### Fleet 依赖澄清

**GKE Policy Controller 必须加入 Fleet** —— 这不是技术限制，而是产品设计选择。Policy Controller 是 Anthos（Google 企业级混合云解决方案）的一部分，Fleet 是其统一控制平面。

**开源 OPA Gatekeeper 不需要 Fleet** —— 如果选择开源方案，可以完全独立运行，不受 GCP 绑定限制。

### Multi-Cluster Scenarios

**方案 A: GKE Policy Controller + Fleet**
- 适用：仅 GKE，多集群统一管理
- 特点：Fleet 原生管理，一处配置全舰生效
- 限制：不支持跨云

**方案 B: 开源 Gatekeeper + GitOps (ArgoCD/Flux)**
- 适用：跨云（GKE + ACK + EKS + 自建 K8s）
- 特点：Git 作为单一真相来源，策略版本化管理
- 优势：不受 GCP 版本绑定限制

### Selection Decision Tree

```
你的需求？
│
├─ 仅 GKE，单/多集群统一管理
│   └─ → GKE Policy Controller + Fleet
│
├─ 仅 GKE，但需要最新 Gatekeeper 版本
│   └─ → 开源 Gatekeeper + GitOps
│
├─ 多云（ GKE + ACK + ...）
│   └─ → 开源 Gatekeeper + GitOps
│
└─ 不想用 Fleet，想要策略代码版本化管理
    └─ → 开源 Gatekeeper + GitOps
```

---

## Installation Commands

### GKE Policy Controller

```bash
# 注册到 Fleet
gcloud container fleet memberships register <NAME> \
  --gke-cluster=<LOCATION>/<CLUSTER_NAME> \
  --enable-workload-identity

# 启用 Policy Controller
gcloud container fleet policy-controller enable \
  --memberships=<MEMBERSHIP_NAME>
```

### Open Source Gatekeeper

```bash
# Helm 部署（每个集群独立）
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --version 3.14.0
```

---

## Key References

- [GCP IAP TCP Tunneling skill](../gcp-iap-tunnel): 包含 IAP 隧道原理和 NumPy 安装位置澄清
- [GKE Policy Controller 文档](https://cloud.google.com/kubernetes-engine/docs/policy-controller)
- [OPA Gatekeeper 官方文档](https://open-policy-agent.github.io/gatekeeper/)
- [Gatekeeper Library](https://github.com/open-policy-agent/gatekeeper-library)
