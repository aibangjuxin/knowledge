# PSC Firewall Cheat Sheet — 横向决策工具

> 跨项目 PSC + LB 类型的快速判定表 + debug 命令。
>
> 本文档是 `../README.md` 的横向补充：README 是"哪些层需要 firewall"，本文档是"具体怎么判定 + 怎么 debug"。
>
> 内容继承自上级目录的 `psc-firewall.md` §17-§22（更详细的判定路径），但精简到 cheatsheet 形态。

---

## 1. 一句话判定原则

**不要看 LB 名字里有 `gateway`、`ilb`、`proxy` 就下结论。最稳的方式是看 forwarding rule 的 `target` 字段：**

- `target: targetHttpProxies/...` / `targetHttpsProxies/...` / `targetTcpProxies/...` / `targetSslProxies/...` → **Proxy 类** → 放 `proxy-only subnet`
- `backendService: ...` 且无 target proxy → **Passthrough 类** → 放 `PSC NAT subnet`

---

## 2. Producer LB 类型 × Backend source 速查表

| Producer LB 类型 | 底层实现 | backend 看到的 source | firewall 该放通 |
|-----------------|---------|---------------------|----------------|
| Internal passthrough NLB | forwarding rule → backend service 直连 | `PSC NAT subnet CIDR` | PSC NAT subnet + hc ranges |
| Internal protocol forwarding | forwarding rule → target service | `PSC NAT subnet CIDR` | PSC NAT subnet |
| Port mapping service | 端口映射 | `PSC NAT subnet CIDR` | PSC NAT subnet |
| Internal Application LB（regional） | target HTTP/HTTPS proxy + URL map | **`proxy-only subnet CIDR`** | proxy-only subnet + hc ranges |
| Cross-region internal Application LB | 同上，跨 region | `proxy-only subnet CIDR` | proxy-only subnet + hc ranges |
| Internal proxy NLB | target TCP/SSL proxy | `proxy-only subnet CIDR` | proxy-only subnet + hc ranges |
| Secure Web Proxy | proxy service | `proxy-only subnet CIDR` | proxy-only subnet + hc ranges |
| **GKE internal Gateway (`gke-l7-rilb` / `gke-l7-internal`)** | regional internal Application LB | **`proxy-only subnet CIDR`** | proxy-only subnet + hc ranges |
| MIG 直连（无 LB） | MIG instance + 后端自己 listen | 上游 LB 的 source（passthrough 或 proxy） | 看上游 LB |

**永远叠加**（任何类型都需要）：

- Google health check probe ranges：`130.211.0.0/22` + `35.191.0.0/16`

---

## 3. 判定你的 LB 是 passthrough 还是 proxy

### 3.1 路线 1：从 Service Attachment 出发（推荐）

```bash
# Step 1: 看 Service Attachment 的 target service
gcloud compute service-attachments describe ${SA_NAME} \
  --project=${PRODUCER_PROJECT} \
  --region=${REGION} \
  --format='value(targetService)'

# Step 2: 用 target service URI 找到 forwarding rule name
TARGET_FR=$(gcloud compute service-attachments describe ${SA_NAME} \
  --project=${PRODUCER_PROJECT} \
  --region=${REGION} \
  --format='value(targetService)' | awk -F'/' '{print $NF}')

# Step 3: 看 forwarding rule 的 target
gcloud compute forwarding-rules describe ${TARGET_FR} \
  --project=${PRODUCER_PROJECT} \
  --region=${REGION} \
  --format='yaml(target,backendService,loadBalancingScheme)'
```

**判读结果**：

```yaml
# 如果看到这种 → Proxy 类
target: https://compute.googleapis.com/compute/v1/projects/P/regions/R/targetHttpProxies/xxx
loadBalancingScheme: INTERNAL_MANAGED
backendService: https://...

# 如果看到这种 → Passthrough 类
loadBalancingScheme: INTERNAL
backend: https://.../regions/R/backendServices/xxx  # 注意字段名是 backend，不是 backendService
```

### 3.2 路线 2：看 proxy-only subnet 是否存在（粗判）

```bash
gcloud compute networks subnets list \
  --project=${PRODUCER_PROJECT} \
  --filter='purpose="REGIONAL_MANAGED_PROXY" OR purpose="INTERNAL_HTTPS_LOAD_BALANCER"'
```

- 有结果 → 这个 region/VPC 用过 proxy 类 LB
- 无数结果 → 可能是 passthrough（但也可能还没建）

### 3.3 路线 3：从 GKE Gateway 推出（变体 B 专用）

如果你用的是 GKE Gateway，**100% 是 proxy 类**：

```yaml
spec:
  gatewayClassName: gke-l7-internal  # 或 gke-l7-rilb
```

→ 底层 = regional internal Application LB = **proxy 类**

→ backend source = `proxy-only subnet CIDR`

→ firewall 必须放 `proxy-only subnet`（不是 `PSC NAT subnet`）

---

## 4. Debug 命令集

### 4.1 看 PSC 链路状态

```bash
# PSC Endpoint (Consumer 侧)
gcloud compute forwarding-rules describe ${PSC_ENDPOINT_NAME} \
  --project=${CONSUMER_PROJECT} \
  --region=${REGION} \
  --format='yaml(IPAddress,target,pscConnectionStatus,allowPscGlobalAccess)'

# Service Attachment (Producer 侧)
gcloud compute service-attachments describe ${SA_NAME} \
  --project=${PRODUCER_PROJECT} \
  --region=${REGION} \
  --format='yaml(connectedEndpoints,pscConnectionStatus,natSubnets,targetService)'
```

### 4.2 看 LB 类型 + backend

```bash
# Forwarding rule 全字段
gcloud compute forwarding-rules describe ${FR_NAME} \
  --project=${PRODUCER_PROJECT} \
  --region=${REGION}

# Backend service
gcloud compute backend-services describe ${BS_NAME} \
  --project=${PRODUCER_PROJECT} \
  --region=${REGION} \
  --format='yaml(backends,healthChecks,loadBalancingScheme,protocol)'
```

### 4.3 看 firewall 规则（按 target tag 过滤）

```bash
# Master MIG firewall
gcloud compute firewall-rules list \
  --project=${PRODUCER_PROJECT} \
  --filter='targetTags=master-mig-nginx'

# GKE 自动 firewall
gcloud compute firewall-rules list \
  --project=${PRODUCER_PROJECT} \
  --filter='targetTags:gke-node'

# 看 hierarchical firewall policy 是否覆盖
gcloud compute firewall-policies list \
  --organization=${ORG_ID}

# 看某条规则的完整定义
gcloud compute firewall-rules describe ${RULE_NAME} \
  --project=${PROJECT}
```

### 4.4 看 NetworkPolicy（K8s 层）

```bash
# 列出所有 NetworkPolicy
kubectl get networkpolicy -A

# 看特定 namespace 的所有 NP
kubectl get networkpolicy -n ${NS}

# 看 NP 详情
kubectl describe networkpolicy ${NP_NAME} -n ${NS}

# 看 default deny 状况（最常被忽视的坑）
kubectl get networkpolicy -n ${NS} -o yaml | grep "policyTypes"
```

### 4.5 看实际流量来源（debug 终极信号）

```bash
# Producer MIG instance 上抓包（需要 SSH）
gcloud compute ssh ${MIG_INSTANCE_NAME} \
  --project=${PRODUCER_PROJECT} \
  --zone=${ZONE} \
  --command='sudo tcpdump -i any -nn "src host $(gcloud compute networks subnets describe ${PSC_NAT_SUBNET} --project=${PRODUCER_PROJECT} --region=${REGION} --format="value(ipCidrRange)" | sed "s|/.*||") and port 443" -c 20'

# Master GKE Pod 上看连接（distroless 镜像 fallback）
kubectl exec -it <pod> -n <ns> -- bash -c '
  # /proc/net/tcp 第一列是 local，第二列是 remote，第三列是 state
  awk "\$4 == \"0A\" {print \$2,\$3}" /proc/net/tcp | head -20
'

# 用 ss（如果镜像里有）
kubectl exec -it <pod> -n <ns> -- ss -ntap 2>/dev/null | grep :8080
```

---

## 5. 常见反模式（一定不要这么写）

| 反模式 | 问题 | 修法 |
|--------|------|------|
| `--destination-ranges=0.0.0.0/0` | 等于没限制，破坏 deny-all | 用具体 CIDR |
| `--rules=tcp:0-65535` 或 `--rules=all` | 等于没限制 | 用具体端口 |
| `priority=65535`（最低） | 可能被更高优先级 deny 覆盖 | `priority=1000` 或更低数字 |
| 同一规则多个 target tags 用 `--target-tags=a,b` | 容易混 tag，遗漏安全上下文 | 拆成多条规则 |
| `source-ranges=10.0.0.0/8`（过大） | 把整个 RFC1918 都放进来 | 缩到具体 subnet |
| `allow egress 0.0.0.0/0`（默认 deny-all 下） | 整个 deny-all 失效 | 只放必要 destination |
| 把 firewall rule 写在 deny-all 的 VPC 上但 priority 不够 | 被 implicit deny 覆盖 | priority ≤ 1000 |
| NetworkPolicy `podSelector: {}` + 无 Egress 规则 | 等于 deny-all egress（如果你忘了开 DNS / apiserver 也会卡） | 永远先开 DNS |
| 在 Shared VPC 里给 host project 写 firewall | host project 跟 service project firewall 不互通 | 区分清楚 |

---

## 6. Shared VPC / Hierarchical Firewall Policy 注意事项

### 6.1 Shared VPC 场景

- firewall rule 写在 **host project**，影响所有 service project 的 attached VPC
- `gcloud compute firewall-rules list --project=${HOST_PROJECT}`
- 给 GKE controller service account 在 **host project** 的 `compute.networkUser` + `compute.securityAdmin` 权限，否则 controller 创建 firewall 会失败

### 6.2 Hierarchical Firewall Policy（HFP）

```bash
# 列出所有 HFP
gcloud compute firewall-policies list --organization=${ORG_ID}

# 看某条 policy 详情
gcloud compute firewall-policies describe ${POLICY_NAME} \
  --organization=${ORG_ID}

# 看 policy 关联到哪些 folders/projects
gcloud compute firewall-policies get-ancestor ${POLICY_NAME} \
  --organization=${ORG_ID}
```

**判定优先级**：

```
Hierarchical Firewall Policy (Org/Folder/Project)
  ↓ 覆盖
VPC Firewall Rules
  ↓
Implicit Deny (default)
```

如果 HFP 写了 deny 规则，**VPC 里的 allow 会被覆盖**。这是 deny-all 项目的隐藏坑。

---

## 7. 关键 CIDR 速记

| CIDR | 用途 |
|------|------|
| `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` | RFC1918 私网（不要随便整个放） |
| `130.211.0.0/22` | Google health check probe 一段 |
| `35.191.0.0/16` | Google health check probe 另一段 |
| `199.36.153.4/30` | `restricted.googleapis.com`（PGA 走内部 Google API） |
| `199.36.153.8/30` | `private.googleapis.com` |
| `34.96.0.0/20` 等 | 部分 GCP 服务的固定 IP 段（具体看文档） |

---

## 8. References

- 上级：`../README.md`（总览 + 变体对比）
- 横向判定详细版：`../../psc-firewall.md` §17-§22
- 实施详情：`./scenario-a-via-mig-jumphost.md`、`./scenario-b-via-gke-gateway.md`
- GCP 文档：
  - [Publish services by using Private Service Connect](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer)
  - [Make the service accessible from other VPC networks](https://cloud.google.com/vpc/docs/make-service-accessible-other-vpc-networks)
  - [Firewall rules for Cloud Load Balancing](https://cloud.google.com/load-balancing/docs/firewall-rules)
  - [Internal Application Load Balancer overview](https://cloud.google.com/load-balancing/docs/l7-internal)
  - [GKE firewall rules](https://cloud.google.com/kubernetes-engine/docs/concepts/firewall-rules)
  - [Deploying Gateways](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)

---

*最后更新：2026-08-16 · Lex 个人知识库*