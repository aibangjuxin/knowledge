# Cross-Project Firewall & NetworkPolicy 路线图

> 跨项目 PSC 架构下，哪些地方需要防火墙规则、哪些地方需要 NetworkPolicy — 一张清单 + 两个 packaging 变体的实施手册。
>
> **🎯 你的判定逻辑（一句话版）**：
>
> **Service Attachment 的 backend 是什么实例？→ 放通该实例所在 subnet 的 ingress 规则。**
>
> 不需要先想 LB 是 passthrough 还是 proxy — 看实例，按 subnet 放通。
> 详细判定路径见 `references/firewall-by-instance-path.md`（**日常排查入口**）。

---

## 0. 原始问题（保留 Lex 原话 verbatim）

**场景**

- Lex 在 Tenant Project + Master Project 之间跨项目部署
- 两 Project 通过 PSC 连接
- 所有 firewall 默认 **deny-all**
- 所有 NetworkPolicy 默认 **deny-all**
- Tenant 侧持有 PSC endpoint IP，需要直接访问对应端口

**问题**

- 这种 deny-all 配置下，哪些 firewall 规则需要开？
- Tenant 侧是不是通常不需要改防火墙？
- 重点应该是 Master Project 的 firewall
- Server Attachment 在 Master Project 暴露时：
  - 如果暴露的是 MIG instance，那 MIG 需要 ingress 规则允许"它的 subnet 的 IP 范围"访问对应端口
  - 如果上游是 GKE Gateway（GKE 是多个 node + 多个 LB），对应的 GKE-集群级别也需要 NetworkPolicy 放行
- 需要识别**所有可能的 firewall / NetworkPolicy 来源** — 至少给一份路线图：哪个组件需要 inbound allow、哪个需要 outbound allow

**两个 packaging 变体**（Lex 提问的关键区分点）

1. **变体 A**：Tenant → MIG (VM 跑 nginx 作 jump host) → Master GKE Gateway
2. **变体 B**：Tenant → Master GKE Gateway（无中间 MIG）

---

## 1. 一句话结论

**真正需要 firewall/NetworkPolicy 放行的"源地址"，永远是 backend 实际看到的那个 IP — 不是 PSC endpoint、不是 Service Attachment、不是 LB VIP，而是 backend 视角的 source。**

按 backend 类型，可见的 source 永远只有这几类（互斥）：

| Backend 实际看到的 source 类型 | 适用条件 | 关键资源 |
|-------------------------------|---------|----------|
| **PSC NAT subnet CIDR** | Producer 用 passthrough LB（Internal passthrough NLB / Port Mapping / Protocol Forwarding） | `purpose=PRIVATE_SERVICE_CONNECT` subnet |
| **proxy-only subnet CIDR** | Producer 用 proxy 类 LB（Internal ALB / GKE Gateway / Internal proxy NLB / Secure Web Proxy） | `purpose=REGIONAL_MANAGED_PROXY` subnet |
| **GKE cluster pod CIDR** | Producer backend 是 GKE Pod（集群内部 LB 直连，无 external LB） | GKE node / pod CIDR |
| **MIG instance subnet CIDR** | Producer backend 是 MIG instance，流量从同 VPC 的另一个实例来 | 该 MIG 所在 subnet |
| **Google health check probe ranges** | 任何 backend service 开了 health check 时**必须**叠加 | `130.211.0.0/22` + `35.191.0.0/16` |
| **Internet / external** | 仅 LB frontend 接收外部流量时 | GLB 路径 |

**判定规则**：看 Producer forwarding rule 指向的是 target proxy 还是直接 backend service。

- `target: targetHttpProxies/...` / `targetHttpsProxies/...` / `targetTcpProxies/...` / `targetSslProxies/...` → **proxy 类** → 放 `proxy-only subnet`
- 直接 `backendService: ...`、无 target proxy → **passthrough 类** → 放 `PSC NAT subnet`

---

## 2. 哪些层"不需要" firewall

按 Google PSC 官方文档，下面这些**逻辑组件本身不是网卡**，你不需要为它们写单独的 firewall rule：

| 链路段 | 是否需要 firewall |
|--------|------------------|
| Consumer workload → PSC endpoint IP (VIP) | ✅ **egress 需要**（VM/Pod 出去） |
| PSC endpoint ↔ Service Attachment | ❌ 隧道本身，不需要 |
| Service Attachment → Producer LB frontend | ❌ 内部自动建立 |
| LB frontend → backend | ✅ **backend ingress 需要**（这是重点） |
| backend → 上游服务（如 gateway） | ✅ **egress 需要**（看 backend 类型） |
| Health check → backend | ✅ **需要**（永远叠加） |

**常见误区**：

- ❌ "我要开放 PSC endpoint IP" — PSC endpoint 是 forwarding rule / VIP，不是传统 NIC
- ❌ "Service Attachment 和 LB 之间要单独开 firewall" — 官方明确不需要
- ❌ "只要放 PSC NAT subnet 就够" — 只在 passthrough 类 producer 下成立，proxy 类要放 `proxy-only subnet`
- ❌ "Producer 放通就够了" — Consumer 侧 egress + K8s NetworkPolicy 也可能挡

---

## 3. 总路线图：每个组件的 ingress / egress 要求

> 详细每条规则在 scenario-A / scenario-B 各自的 references 文件展开。**这一节只列"哪些点"**，给一张清单。

### 3.1 Tenant Project（Consumer 侧）

| 组件 | 入向 (ingress) | 出向 (egress) | 备注 |
|------|---------------|--------------|------|
| **Tenant GLB (Public/External HTTPS)** | 来源: Internet (`0.0.0.0/0:443`) | → Cloud Armor → Backend Service → PSC NEG | Cloud Armor 已绑 GLB 时生效 |
| **Tenant PSC NEG + Backend Service** | 不适用（逻辑组件） | → PSC Endpoint forwarding rule | 内部隧道，不需要 firewall |
| **Tenant VM/Pod 工作负载** | 不需要额外（自己就是 source） | → **PSC endpoint IP:port**（通常 443） | deny-all 项目下 egress 必须显式开 |
| **Tenant GKE Pod NetworkPolicy** | pod-to-pod 业务流量 | egress to PSC endpoint IP:port | 必须显式开，否则 K8s 层 deny |
| **Tenant → Master 反向** | ✅（看场景） | ✅（看场景） | Master→Tenant 的 audit/ETL 路径，详见 §6 |

### 3.2 Master Project（Producer 侧） — **重点**

| 组件 | 入向 (ingress) | 出向 (egress) | 备注 |
|------|---------------|--------------|------|
| **PSC NAT Subnet** | 不适用（专用于 NAT 转换） | 不适用 | `purpose=PRIVATE_SERVICE_CONNECT` |
| **Service Attachment** | ❌ 不需要 firewall（逻辑组件 + 准入控制） | ❌ 不需要 firewall | 但需检查 `connectedEndpoints` 状态 + `consumer-accept-list` |
| **Producer LB frontend (Internal passthrough NLB / ILB)** | 来源: PSC NAT subnet (passthrough) 或 proxy-only subnet (proxy 类) | → Backend Service | 视 LB 类型 |
| **Producer Proxy-only Subnet** | ❌ 不直接接收外部流量 | 内部 LB proxy 路径 | `purpose=REGIONAL_MANAGED_PROXY` |
| **Producer Backend Service** | ❌ 逻辑组件 | ❌ | 但要绑 health check firewall |
| **Backend = MIG (VM)** | 来源: PSC NAT subnet **或** 同 VPC 来源 IP；端口: backend port | → 上游 service（如果上游是 GKE Gateway，需要再 egress） | 见 scenario-A |
| **Backend = GKE Pod（直连 GKE Gateway）** | 来源: proxy-only subnet (GKE Gateway) **或** 同 NS pod | → 上游 service | 见 scenario-B |
| **Health check probe** | 来源: Google health check ranges; 端口: hc 端口 | 不适用 | **永远叠加** |
| **Master → Tenant 反向** | ✅ audit / metering 回流 | ✅ ETL pull | 详见 §6 |

---

## 4. 两个 packaging 变体对比

| 维度 | 变体 A: via MIG (jump host) | 变体 B: via GKE Gateway (direct) |
|------|---------------------------|-------------------------------|
| **链路** | Tenant GLB → Tenant PSC NEG → Master PSC SA → Master ILB → **MIG (nginx)** → Master GKE Gateway → Master Pod | Tenant GLB → Tenant PSC NEG → Master PSC SA → **Master GKE Gateway (直接内部 LB)** → Master Pod |
| **中间层** | VM 跑 nginx，做 path rewrite / TLS 终止 | 无中间层 |
| **Master ILB 类型** | Internal passthrough NLB（指向 MIG） | regional internal Application LB (`gke-l7-rilb`) |
| **backend source 类型** | MIG 看到 `PSC NAT subnet CIDR`（passthrough） | Pod 看到 `proxy-only subnet CIDR`（proxy 类） |
| **MIG firewall rules** | 需要：allow `PSC NAT subnet` → port 80/443；allow `health check ranges` → hc port | 不需要 MIG |
| **GKE NetworkPolicy** | Tenant Pod egress → PSC EP；Master Pod egress → 上游（同集群内通常不需，但 deny-all 时要） | Tenant Pod egress → PSC EP；**Master Pod 接收 ingress from proxy-only subnet** |
| **proxy-only subnet** | 不一定需要（看 ILB 类型） | **必须有**（`gke-l7-rilb` 强依赖） |
| **复杂度** | `Advanced`（多一跳，要管理 VM lifecycle） | `Moderate`（少一跳，纯 managed） |

---

## 5. 实施文件地图

| 你想看的内容 | 打开哪个文件 |
|-------------|-------------|
| **🔰 日常排查入口：按"实例视角 + 流量物理路径"找 firewall** | **`references/firewall-by-instance-path.md`** ← **最先翻这个** |
| **🔰 配套日志抓取 SOP：按"3 步法"（先窄过滤 → 各平台 → 逐步丰富）** | **`references/log-capture-by-3-step-method.md`** ← firewall 排障时配对看 |
| 决策树、判断 passthrough vs proxy、debug 命令 | `references/psc-firewall-cheatsheet.md`（参考材料）|
| 变体 A: Tenant → MIG nginx → Master GKE Gateway 的 firewall + NetworkPolicy | `references/scenario-a-via-mig-jumphost.md` |
| 变体 B: Tenant → Master GKE Gateway 直接的 firewall + NetworkPolicy | `references/scenario-b-via-gke-gateway.md` |
| PSC NAT Subnet vs Proxy-Only Subnet 概念详解 | `gcp/network/psc-subnet/psc-nat-vs-proxy-only-subnet.md`（参考材料）|
| 跨项目日志聚合架构（Log Scope / Sink） | `gcp/logs/cross-project-sharing-logs.md`（长期方案）|
| 反向：Master → Tenant 路径（audit / ETL） | 各 scenario 文件 §"反向路径"小节（README §6 总览） |

---

## 6. 反向路径说明（Master → Tenant）

防火墙路线图不仅要走正向，**Master Project 也可能主动发起跨项目访问**：

| 触发场景 | 方向 | 涉及 firewall |
|---------|------|--------------|
| Audit / metering 拉取 Tenant 数据 | Master Pod → Tenant API | Master egress: Tenant API endpoint；Tenant ingress: allow Master VPC range |
| ETL / 数据回流 | Master → Tenant BigQuery / GCS | Tenant ingress: allow Master SA / range |
| Tenant 共享给 Master 的资源（如 Secret Manager） | Master Pod → Tenant Secret | Tenant ingress: allow Master GSA；不靠 firewall，靠 IAM |
| Tenant → Master 回调 webhook | Tenant Pod → Master LB | Master LB ingress: allow Tenant VPC range + PSC NAT subnet |

**判断反向需不需要 firewall**：

- 如果走 **IAM-only**（如 Secret Manager / BigQuery）— 不靠 firewall，靠 IAM binding
- 如果走 **网络层**（如 Tenant 调 Master 的 webhook endpoint）— 需要反向 firewall

详见各 scenario 文件的"反向路径"小节。

---

## 7. 验证清单（哪个场景都跑一遍）

### 7.1 静态验证（资源就绪）

```bash
# 1. PSC NAT subnet 存在
gcloud compute networks subnets list \
  --project=${PRODUCER_PROJECT} \
  --filter='purpose="PRIVATE_SERVICE_CONNECT"'

# 2. proxy-only subnet 存在（仅 proxy 类 LB 需要）
gcloud compute networks subnets list \
  --project=${PRODUCER_PROJECT} \
  --filter='purpose="REGIONAL_MANAGED_PROXY"'

# 3. Service Attachment 状态
gcloud compute service-attachments describe ${SA_NAME} \
  --project=${PRODUCER_PROJECT} \
  --region=${REGION} \
  --format='value(connectedEndpoints,pscConnectionStatus)'

# 4. forwarding rule 类型（看 target 是 proxy 还是 backend service）
gcloud compute forwarding-rules describe ${FR_NAME} \
  --project=${PRODUCER_PROJECT} \
  --region=${REGION} \
  --format='yaml(target,backendService,loadBalancingScheme)'
```

### 7.2 VPC firewall 规则核对

```bash
# 列出所有 firewall，重点看 priority / source / target tags / port
gcloud compute firewall-rules list \
  --project=${PROJECT} \
  --filter='direction=INGRESS AND disabled=false' \
  --format='table(name,priority,sourceRanges.list(),targetTags.list(),allowed[].map().firewall_rule().list())'

# 看 hierarchical firewall policy 是否覆盖
gcloud compute firewall-policies list --organization=${ORG_ID}
```

### 7.3 NetworkPolicy 核对

```bash
# 列出集群内所有 NetworkPolicy
kubectl get networkpolicy -A

# 看特定 namespace 的所有规则
kubectl get networkpolicy -n ${NS} -o yaml | less

# 看 Pod 是否被 default deny 命中（deny 时 Pod 间连接会超时）
kubectl exec -it <pod> -- bash -c '
  timeout 3 bash -c "echo > /dev/tcp/<target-pod-ip>/<port>" && echo "TCP_OK" || echo "BLOCKED"
'
```

### 7.4 端到端连通性测试

```bash
# 网络层（不依赖应用）
gcloud network-management connectivity-tests create psc-validate \
  --source-ip=<consumer-vm-or-pod-ip> \
  --destination-ip=<psc-endpoint-ip> \
  --destination-port=443 \
  --protocol=TCP \
  --project=${CONSUMER_PROJECT}

# 应用层（curl 验证路由 + host header）
kubectl exec -it <pod> -n ${NS} -- \
  curl -v -H "Host: ${TARGET_FQDN}" http://${PSC_ENDPOINT_IP}/${PATH}
```

---

## 8. 常见误区（强约束）

| 误区 | 真相 |
|------|------|
| "PSC endpoint 是 backend，要给它开 firewall" | PSC endpoint 是 forwarding rule（VIP），不是传统 NIC。给 consumer workload 开 egress 到这个 VIP 即可 |
| "Service Attachment 和 LB 之间要开 firewall" | 官方明确不需要，逻辑组件 |
| "只要放 PSC NAT subnet 一定够" | passthrough 类才行；proxy 类要放 proxy-only subnet |
| "MIG 在 PSC NAT subnet 里" | **错**。MIG 在 backend subnet，PSC NAT subnet 只是 NAT pool |
| "Proxy-only subnet 是 backend subnet" | **错**。Proxy-only subnet 是 Envoy 出口的源池 |
| "只要 Producer 放通就够了" | Consumer 的 K8s NetworkPolicy / egress firewall 也可能挡 |
| "Health check 跟业务流量来源一样" | 不一定。health check 走 Google 固定 probe range |
| "我把 firewall 优先级写很高（数字小）就够了" | Hierarchical firewall policy 可能从 Org 覆盖 VPC 规则 |
| "10.x.x.x 段都是私网所以不需要 firewall" | VPC firewall 默认仍生效，deny-all 必须显式 allow |

---

## 9. 关键 GCP 文档锚点

- [Publish services by using Private Service Connect](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer) — Service Attachment 配置 + Producer firewall 说明
- [Make the service accessible from other VPC networks](https://cloud.google.com/vpc/docs/make-service-accessible-other-vpc-networks) — PSC endpoint 创建
- [Firewall rules for Cloud Load Balancing](https://cloud.google.com/load-balancing/docs/firewall-rules) — LB 类型 ↔ backend source IP 完整表
- [Internal Application Load Balancer overview](https://cloud.google.com/load-balancing/docs/l7-internal) — proxy-only subnet 解释
- [Deploying Gateways](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways) — GKE Gateway 行为
- [GKE firewall rules](https://cloud.google.com/kubernetes-engine/docs/concepts/firewall-rules) — GKE controller 自动创建的 firewall rule
- [Internal load balancing across VPC networks](https://cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing-across-vpc-net) — GKE 跨 VPC LB 文档（**用户原话引用**，此 URL 内容在 WebFetch 时未成功加载，但 Lex 明确引用 — 实施时需补一手验证）

---

## 10. 一句话原则

**Cross-Project firewall 的设计不是"为 PSC 开洞"，而是先识别 backend 实际看到的 source IP 是 PSC NAT subnet / proxy-only subnet / GKE pod CIDR / MIG instance CIDR 中的哪一类，然后只对那一个真实来源做最小放通，并永远叠加 health check probe ranges。**

---

## 子目录索引

- `references/scenario-a-via-mig-jumphost.md` — 变体 A 详细实施（Tenant → MIG nginx → Master GKE Gateway）
- `references/scenario-b-via-gke-gateway.md` — 变体 B 详细实施（Tenant → Master GKE Gateway 直接）
- `references/psc-firewall-cheatsheet.md` — 横向决策 cheat sheet（passthrough vs proxy 判定 + debug 命令）

---

*最后更新：2026-08-16 · 本文档为 Lex 个人知识库条目，遵循 redaction policy（org 名 / numeric ID / env hostname 已脱敏）*