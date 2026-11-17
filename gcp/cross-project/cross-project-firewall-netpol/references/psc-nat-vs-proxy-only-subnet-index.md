# PSC NAT Subnet vs Proxy-Only Subnet（精简索引）

> 本文档是 `../../../../gcp/network/psc-subnet/psc-nat-vs-proxy-only-subnet.md` 的**精简索引**。完整讲解见主版本。
>
> 在 cross-project firewall 设计中，正确识别"backend 实际看到的 source IP 是 PSC NAT subnet 还是 proxy-only subnet"是 firewall 放通的关键前置 — 见主文档 §5 三种场景。
>
> 本文只列核心判定要点，方便 firewall 决策时快速查询。

---

## 1. 核心对照（背下来）

| 子网类型 | `purpose` | 绑定对象 | backend 看到 source IP 的条件 |
|---------|-----------|---------|----------------------------|
| **PSC NAT Subnet** | `PRIVATE_SERVICE_CONNECT` | Service Attachment（`--nat-subnets`） | **passthrough 类 LB** 时（Internal passthrough NLB 等）|
| **Proxy-Only Subnet** | `REGIONAL_MANAGED_PROXY`（旧名 `INTERNAL_HTTPS_LOAD_BALANCER`）| Envoy-based LB（Internal ALB / GKE Gateway）| **proxy 类 LB** 时（所有带 target proxy 的 LB）|

**GCP 官方原文**（主文档 §3.1 verbatim）：

> "Packets sent from a proxy to a backend VM or endpoint has a source IP address from the proxy-only subnet."
>
> — [Proxy-only subnets for Envoy-based load balancers](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)

**GCP 官方硬约束**：

- Proxy-only subnet **≥ 64 IP**（即 `/26` 或更短）；推荐 `/23`（512 IP）起步
- PSC NAT subnet **每 SA 最多 10 个**；典型 `/28`（经验值，详见主文档 §9.1）
- Proxy-only subnet **每 VPC 每 region 仅 1 个 active**
- **每 VPC 每 region 1 个 active proxy-only subnet 服务所有 Envoy-based LB**（Regional internal/external ALB、internal/external proxy NLB、Secure Web Proxy）— 不限制 LB 数量，限制的是总吞吐能力。**扩不了原地扩**，必须走新建 BACKUP subnet → 切 ACTIVE → 删旧的流程。详见主文档 **§12**。

---

## 2. Firewall 设计中的 30 秒判定

```
1. Producer LB 是什么类型？
   ├─ passthrough (Internal passthrough NLB / Port Mapping / Protocol Forwarding)
   │    → firewall 放通 PSC NAT subnet CIDR
   │
   └─ proxy (Internal ALB / GKE Gateway / Internal proxy NLB / SWP)
        → firewall 放通 proxy-only subnet CIDR

2. 不论哪种，再叠加：
   → Google health check probe ranges (130.211.0.0/22 + 35.191.0.0/16)
```

**怎么判定 LB 类型** — 详见 `psc-firewall-cheatsheet.md` §3（含 `target: targetHttpProxies/...` 等关键字段识别）。

---

## 3. 创建顺序

| LB 类型 | 必须建 | firewall source |
|---------|-------|----------------|
| passthrough (Internal passthrough NLB) | PSC NAT subnet | PSC NAT subnet CIDR |
| proxy (Internal ALB / GKE Gateway / Internal proxy NLB) | **PSC NAT subnet** + **proxy-only subnet** | **proxy-only subnet CIDR** |

> ⚠️ proxy 类 LB 路径下：**PSC NAT subnet 仍然要建**（Service Attachment 强依赖），但 backend 看不到它 — 它只用于 SA 的 SNAT。

---

## 4. 完整内容请跳主文档

- 主文档位置：`gcp/network/psc-subnet/psc-nat-vs-proxy-only-subnet.md`
- 主文档包含：5 大节（定义 / NAT subnet / Proxy-only subnet / 对照 / 关系）+ 流量路径图 + 验证命令 + 决策树 + 容量规划 + 速查表 + 完整 References

---

*最后更新：2026-08-16 · 主版本 `gcp/network/psc-subnet/psc-nat-vs-proxy-only-subnet.md` 维护*