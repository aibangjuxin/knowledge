# PSC Service Attachment firewall 决策（按实例视角）

> **本文是你日常排查 firewall 的入口文档**。判定逻辑就一句：
>
> **Service Attachment 通过哪个实例 backend 暴露？→ 放通该实例所在 subnet 的 ingress 规则**
>
> 不需要先想 "passthrough vs proxy"。本文按流量物理路径组织，每条路径给你一张 firewall 表 + 一段验证命令。

---

## 0. 原始问题（保留 Lex 原话 verbatim）

> "我不太关注你的类型是什么（指 passthrough vs proxy 这种分类），我关心的是流量流经哪些组件，或者说经过哪些网络。那么对于一个所有 deny all 的场景来说，我关心的是允许它的流入和流出，这样的话就清晰一点。"
>
> "GKE Gateway，100% 是 proxy 类：其实 service attachment 我就是比如通过 instance 来 create attachment，我就要允许这个对应的 subnet ip range ingress 到我的这个 instance，就这么简单。"

**你的判定逻辑翻译成机器版**：

```
1. 看 Service Attachment 的 backend service 指向什么
2. backend service 后面是什么实例
3. 找这个实例所在的 subnet CIDR
4. 放通该 subnet CIDR ingress 到该实例
```

**就这么简单**。下面是 3 种典型物理路径 + 每条的 firewall 清单。

---

## 1. 物理路径总览：3 种形态

不管 LB 叫什么名字（passthrough NLB / Internal ALB / GKE Gateway / Cross-region ALB / Secure Web Proxy），按 backend 是什么实例来分，只有 3 种形态：

| 路径 | 拓扑形状 | backend 是什么 | 你的判定 |
|------|---------|---------------|---------|
| **路径 A** | Tenant GLB → PSC NEG → PSC Tunnel → Producer ILB → **MIG / GCE Instance（直接）** | GCE VM / MIG | 放通 `<instance 所在 subnet CIDR>` ingress 到该 instance |
| **路径 B** | Tenant GLB → PSC NEG → PSC Tunnel → Producer ILB → **GKE Gateway → GKE Pod** | GKE Pod | 放通 GKE pod CIDR（或 proxy-only subnet）ingress 到 pod，NetworkPolicy 层做 |
| **路径 C** | Tenant workload → 同 VPC 或 Private Google Access → Producer API endpoint | API endpoint / VM | 放通 `<Tenant 实际到达 producer 的源 IP>` ingress |

> **路径 A / B 是正向（Tenant 调 Master），路径 C 是反向（Master 调 Tenant 或 Tenant 调 Master 但不经 PSC）**。

---

## 2. 路径 A：backend 是 GCE Instance / MIG（直接）

### 2.1 流量物理路径

```text
Tenant Project                          Master Project
─────────────                          ──────────────
External Client (e.g. 34.x.x.x)
  │
  ↓
Tenant GLB (External HTTPS LB)
  │
  ↓
Tenant Backend Service
  │
  ↓
Tenant PSC NEG  ←──┐
  │                │  GCP 内部骨干网
  ↓                │  (PSC tunnel)
PSC Endpoint       │
(forwarding rule)  │
  │                │
  │ ←──────────────┘
  ↓
Master Service Attachment
  │
  ↓ (passthrough: SNAT → PSC NAT Subnet)
  │
Master Internal LB (passthrough NLB)
  │
  ↓
Master Backend Service
  │
  ↓
Master MIG / GCE Instance  ←── 你在这里做 firewall
  │
  │ (instance 上跑 nginx / 业务进程)
  ↓
[可选] 上游服务（GKE Gateway / 别的 instance）
```

### 2.2 关键问题：instance 实际看到的 source IP 是什么？

取决于 LB 类型（这一步绕不开）：

| LB 类型 | instance 看到的 source IP | 你 firewall 该放通 |
|--------|------------------------|-------------------|
| **Internal passthrough NLB** | PSC NAT Subnet CIDR | PSC NAT Subnet CIDR |
| **Internal protocol forwarding** | PSC NAT Subnet CIDR | PSC NAT Subnet CIDR |
| **Port mapping service** | PSC NAT Subnet CIDR | PSC NAT Subnet CIDR |

**怎么查 LB 类型？** 跑一次：

```bash
gcloud compute service-attachments describe ${SA_NAME} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --format='value(targetService)'
```

输出的 URI 是 forwarding rule，再 describe 它：

```bash
FR=$(gcloud compute service-attachments describe ${SA_NAME} \
  --project=${MASTER_PROJECT} --region=${REGION} \
  --format='value(targetService)' | awk -F'/' '{print $NF}')

gcloud compute forwarding-rules describe ${FR} \
  --project=${MASTER_PROJECT} --region=${REGION} \
  --format='yaml(loadBalancingScheme,backendService,target)'
```

**判定点**（30 秒）：

- `loadBalancingScheme: INTERNAL` + 无 `target` 字段 + 有 `backend` 字段 → **passthrough** → 放 PSC NAT Subnet
- 有 `target: targetHttpProxies/...` 或 `targetHttpsProxies/...` 等 → **proxy** 类（这条路径 A 不常见，但理论上存在）

### 2.3 Firewall 清单（路径 A）

> **位置**：Master Project，所有规则都加在 `<MASTER_VPC>` 上。

| 优先级 | 名称 | direction | source | destination | port | target | 用途 |
|--------|------|-----------|--------|-------------|------|--------|------|
| 1000 | `m-mig-ingress-from-psc-nat` | INGRESS | **PSC NAT Subnet CIDR** | `<instance>` | 业务端口 | `<INSTANCE_TAG>` 或 service account | PSC 流量进 instance |
| 1000 | `m-mig-hc-allow-probes` | INGRESS | `130.211.0.0/22,35.191.0.0/16` | `<instance>` | hc 端口 | `<INSTANCE_TAG>` | health check |
| 1000 | `m-mig-egress-to-upstream` | EGRESS | `<instance>` tag | `<上游服务 IP/CIDR>` | 业务端口 | — | instance → 上游 |
| — | 默认 deny-all | — | — | — | — | — | 兜底 |

**实际命令**（passthrough LB 场景）：

```bash
# 拿到 PSC NAT Subnet CIDR（如果之前没记）
PSC_NAT_CIDR=$(gcloud compute networks subnets list \
  --project=${MASTER_PROJECT} \
  --filter='purpose="PRIVATE_SERVICE_CONNECT"' \
  --format='value(ipCidrRange)' | head -1)
echo "PSC NAT subnet: ${PSC_NAT_CIDR}"

# 拿到 instance tag / SA（创建 instance 时设置的）
INSTANCE_TAG="mig-nginx-backend"  # 替换为你的 tag

# Allow PSC NAT subnet → instance
gcloud compute firewall-rules create m-mig-ingress-from-psc-nat \
  --project=${MASTER_PROJECT} \
  --network=${MASTER_VPC} \
  --direction=INGRESS \
  --action=ALLOW \
  --priority=1000 \
  --source-ranges="${PSC_NAT_CIDR}" \
  --target-tags="${INSTANCE_TAG}" \
  --rules=tcp:443 \
  --description="Allow PSC NAT subnet → MIG instance (nginx backend)"

# Allow Google health check
gcloud compute firewall-rules create m-mig-hc-allow-probes \
  --project=${MASTER_PROJECT} \
  --network=${MASTER_VPC} \
  --direction=INGRESS \
  --action=ALLOW \
  --priority=1000 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags="${INSTANCE_TAG}" \
  --rules=tcp:<HC_PORT> \
  --description="Allow Google health check probes"
```

### 2.4 你的判定关键句

> "Service Attachment 通过 instance 来 create attachment，我就要允许对应的 subnet ip range ingress 到这个 instance"

完全对应路径 A。

### 2.5 常见子变体

| 子变体 | backend | firewall 改动 |
|--------|---------|-------------|
| **A.1 instance 上跑 nginx，转发到上游 GKE Gateway** | MIG → 上游 GKE Gateway | 上面 + `m-mig-egress-to-upstream`（instance → GKE Gateway VIP:443）|
| **A.2 instance 直接 serve 业务** | MIG only | 上面两行就够 |
| **A.3 instance 在 Shared VPC，PSC 在独立 VPC** | MIG 在 Shared VPC 内的不同 subnet | source CIDR 不变（PSC NAT 在 PSC 那个 VPC），destination 改成 Shared VPC MIG subnet CIDR |
| **A.4 instance 有公网 IP，承接 internet 流量** | MIG only | 加上 `0.0.0.0/0` ingress（但仍要 deny-all 兜底）|

---

## 3. 路径 B：backend 是 GKE Pod（通过 GKE Gateway）

### 3.1 流量物理路径

```text
Tenant Project                          Master Project
─────────────                          ──────────────
External Client
  │
  ↓
Tenant GLB
  │
  ↓
Tenant Backend Service
  │
  ↓
Tenant PSC NEG  ←──┐
  │                │
  ↓                │  PSC tunnel
PSC Endpoint       │
  │                │
  │ ←──────────────┘
  ↓
Master Service Attachment
  │
  ↓ (proxy 类：经 Envoy 转发)
  │
Master Internal ALB (target HTTP/HTTPS proxy + URL map)
  │
  ↓ 来自 Envoy proxy
  │  ←── key: source IP = proxy-only subnet
  │
Master GKE Gateway (Pod)  ←── 你在这里做 NetworkPolicy
  │
  │ Gateway controller 转发到
  ↓
Master Backend Pod (e.g. team1 backend)
  │ ←── 这里 Pod 看到的 source IP = proxy-only subnet CIDR
  │
  ↓ 处理请求，返回
```

### 3.2 关键问题：GKE Pod 实际看到的 source IP 是什么？

> **GKE Gateway = 100% proxy 类。** Pod 看到的 source 永远来自 proxy-only subnet（不是 PSC NAT subnet）。

GCP 官方原文（[Proxy-only subnets for Envoy-based load balancers](https://cloud.google.com/load-balancing/docs/proxy-only-subnets)）：

> "Packets sent from a proxy to a backend VM or endpoint has a source IP address from the proxy-only subnet."

### 3.3 Firewall / NetworkPolicy 清单（路径 B）

> **位置**：Master Project GKE 集群，**NetworkPolicy 在 K8s 层**，VPC firewall 大部分由 GKE controller 自动管。

| 优先级 / 名字 | 类型 | 位置 | source | destination | port | 用途 |
|---------------|------|------|--------|-------------|------|------|
| **GKE controller 自动** | VPC firewall | Master VPC | proxy-only subnet CIDR | gke-node | NodePort | NEG health check（自动）|
| **GKE controller 自动** | VPC firewall | Master VPC | proxy-only subnet CIDR | gke-node | node port | ILB 流量到 backend |
| **GKE controller 自动** | VPC firewall | Master VPC | `130.211.0.0/22,35.191.0.0/16` | gke-node | NodePort | health check |
| **你必须写** | NetworkPolicy | K8s namespace | **proxy-only subnet CIDR** | Pod (port) | 业务端口 | Pod 接收 ingress（deny-all namespace 必须）|
| **你必须写** | NetworkPolicy | K8s namespace | Pod | DNS | 53 | DNS egress（默认 deny 必备）|
| **可选** | NetworkPolicy | K8s namespace | Pod | Tenant VPC CIDR | 443 | 反向 egress（如 audit pull）|

**NetworkPolicy 关键 YAML**：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-from-gateway-proxy
  namespace: <BACKEND_NAMESPACE>
spec:
  podSelector:
    matchLabels:
      app: backend-app  # 你 backend pod 的 label
  policyTypes:
    - Ingress
  ingress:
    - from:
        - ipBlock:
            cidr: <PROXY_ONLY_SUBNET_CIDR>/<MASK>
      ports:
        - protocol: TCP
          port: 8080
```

**怎么拿到 proxy-only subnet CIDR？**

```bash
gcloud compute networks subnets list \
  --project=${MASTER_PROJECT} \
  --regions=${REGION} \
  --filter='purpose="REGIONAL_MANAGED_PROXY"' \
  --format='value(ipCidrRange)'
```

### 3.4 你的判定关键句

> "GKE Gateway 100% 是 proxy 类"

对的。路径 B 的 firewall / NetworkPolicy **永远**只看 **proxy-only subnet**，**不要去看 PSC NAT subnet**（PSC NAT 在这条路径里也用，但只在 SA 入口 SNAT 一次，backend Pod 看到的是 proxy-only subnet）。

### 3.5 路径 B 子变体

| 子变体 | 拓扑 | 你要做的 |
|--------|------|----------|
| **B.1 单层 Gateway** | SA → GKE Gateway → Pod | NetworkPolicy: from proxy-only subnet |
| **B.2 多层 Gateway** | SA → GKE Gateway-A → GKE Gateway-B → Pod | NetworkPolicy: from proxy-only subnet（同一 subnet）|
| **B.3 GKE Service + NEG** | SA → ILB → NEG → Pod (无 Gateway) | NetworkPolicy: from proxy-only subnet（同 ILB 都用这个池）|

---

## 4. 路径 C：反向（Master → Tenant）

**反向场景 4 种**，每种的 firewall 路径不同：

### 4.1 反向路径表

| 场景 | 触发 | 走的路径 | firewall 关键 |
|------|------|---------|-------------|
| **C.1 Master audit 拉 Tenant 数据** | Audit/计量服务 | Master Pod → Tenant API（不走 PSC，走 Tenant API endpoint IP）| Master egress: Tenant API IP；Tenant ingress: Master VPC CIDR |
| **C.2 Master Pod webhook 回调 Tenant** | 业务回调 | Master Pod → Tenant webhook URL | 同上 |
| **C.3 Tenant 直接调 Master API（非 PSC 路径）** | Tenant 直连 | Tenant → Master LB（不经过 SA）| Master LB ingress: Tenant VPC CIDR |
| **C.4 Master 给 Tenant 推送数据** | 数据回流 | Master → Tenant 接收端 | 同 C.1 |

### 4.2 反向 firewall 清单

| 规则 | 位置 | direction | source | destination | port |
|------|------|-----------|--------|-------------|------|
| Master Pod egress → Tenant API | Master VPC | EGRESS | GKE pod CIDR | Tenant VPC CIDR（或单个 API IP）| 443 |
| Tenant API ingress ← Master | Tenant VPC | INGRESS | Master VPC CIDR | Tenant API instance/Pod | 443 |

### 4.3 关键判定

> 反向要不要 firewall，**取决于是否走网络层**：
>
> - 走 **IAM-only**（如 Secret Manager / BigQuery cross-project read）— 不靠 firewall，靠 IAM binding
> - 走 **网络层**（webhook / API endpoint 直连）— 需要 firewall（Master egress + Tenant ingress 配对）

---

## 5. 三条路径快速判定（30 秒内完成）

```
你的 Service Attachment 在哪里？
│
├─ backend 是 GCE Instance / MIG（直接） → 路径 A
│   └─ firewall: source = PSC NAT Subnet CIDR（passthrough LB 时）
│      或 source = proxy-only Subnet CIDR（proxy LB 时，但通常路径 A 不这么走）
│
├─ backend 是 GKE Pod → 路径 B
│   └─ NetworkPolicy: source = proxy-only Subnet CIDR（永远）
│
└─ 反向 / 跨 project 但不走 PSC → 路径 C
    └─ Master egress + Tenant ingress 配对
```

---

## 6. 验证清单（每条路径都跑）

### 6.1 路径 A（MIG instance）

```bash
# 1. 看 SA 绑的 forwarding rule 类型（passthrough vs proxy）
FR=$(gcloud compute service-attachments describe ${SA_NAME} \
  --project=${MASTER_PROJECT} --region=${REGION} \
  --format='value(targetService)' | awk -F'/' '{print $NF}')
gcloud compute forwarding-rules describe ${FR} \
  --project=${MASTER_PROJECT} --region=${REGION} \
  --format='yaml(loadBalancingScheme,backend,backendService,target)'

# 2. 看 firewall 规则（按 instance tag 过滤）
gcloud compute firewall-rules list \
  --project=${MASTER_PROJECT} \
  --filter='targetTags=<INSTANCE_TAG>'

# 3. 看 instance 是否真的 listen 在声明的端口（SSH 到 instance）
gcloud compute ssh ${INSTANCE_NAME} --zone=${ZONE} --project=${MASTER_PROJECT} \
  --command='ss -nltp | grep :443'

# 4. 从 Tenant 跑 connectivity test
gcloud network-management connectivity-tests create tenant-to-mig-test \
  --source-ip=<tenant-workload-ip> \
  --destination-ip=<mig-private-ip> \
  --destination-port=443 \
  --protocol=TCP \
  --project=${TENANT_PROJECT}
```

### 6.2 路径 B（GKE Pod）

```bash
# 1. 看 GKE Gateway 状态
kubectl get gateway -n <ns>
kubectl describe gateway <gw-name> -n <ns>

# 2. 看 NetworkPolicy 是否覆盖 backend pod
kubectl get networkpolicy -A
kubectl describe networkpolicy <np-name> -n <ns>

# 3. 从 Pod 内验证 TCP 握手（distroless fallback 用 /dev/tcp）
kubectl exec -it <pod> -n <ns> -- bash -c '
  timeout 3 bash -c "echo > /dev/tcp/<proxy-only-ip>/8080" && echo TCP_OK || echo BLOCKED
'

# 4. 看 controller 自动创建的 firewall（按 gke-node tag）
gcloud compute firewall-rules list \
  --project=${MASTER_PROJECT} \
  --filter='targetTags:gke-node'
```

### 6.3 路径 C（反向）

```bash
# 1. 看 Master Pod 是否能出到 Tenant
kubectl exec -it <master-pod> -n <ns> -- bash -c '
  timeout 3 bash -c "echo > /dev/tcp/<tenant-api-ip>/443" && echo TCP_OK || echo BLOCKED
'

# 2. 看 Tenant 端 firewall 是否 allow Master VPC
gcloud compute firewall-rules list \
  --project=${TENANT_PROJECT} \
  --filter='direction=INGRESS AND sourceRanges:<MASTER_VPC_CIDR>'
```

---

## 7. 故障排查速查（按错误信号定位路径）

| 现象 | 大概率路径 | 第一步检查 |
|------|-----------|-----------|
| **Tenant curl 超时（无响应）** | A / B 都可能 | connectivity test，看是网络不通还是被 deny |
| **Tenant curl 拿到 503** | SA 未 accept | `gcloud compute service-attachments describe ${SA}` 看 `pscConnectionStatus` |
| **Tenant curl 拿到 502/504** | backend 不通 | 路径 A：SSH 到 MIG 看 nginx；路径 B：`kubectl describe pod` |
| **Tenant curl 拿到 connection refused** | firewall 拦 | 路径 A：查 instance firewall；路径 B：查 NetworkPolicy |
| **Master MIG log 看到 connection 但无 nginx access log** | firewall 拦了 upstream | 看 instance egress firewall |
| **GKE Pod 完全没看到流量** | NetworkPolicy 拦了 proxy-only | 看 NP 规则 + controller 创建的 firewall |
| **Health check 失败但应用正常** | hc firewall 拦 / 端口错 | `gcloud compute firewall-rules list --filter='sourceRanges=130.211.0.0/22'` |

---

## 8. 与上层 / 配套文档的关系

- **本文 ≠ 概念讲解**：概念（PSC NAT subnet vs proxy-only subnet 是什么）见 `../psc-subnet/psc-nat-vs-proxy-only-subnet.md`
- **本文 ≠ 场景实施**：变体 A / B 详细实施见 `../../cross-project/cross-project-firewall-netpol/references/scenario-{a,b}-*.md`
- **本文 = 决策入口**：当你在生产环境遇到 firewall 问题时，**先翻本文**，按"路径 A/B/C"快速定位规则
- **本文的配套文档**：把规则定位好后，**配套翻 `log-capture-by-3-step-method.md`**（同目录下），按"3 步法"抓日志确认 firewall 行为。两文档合起来就是完整的"定位规则 + 验证"闭环

---

## 9. References

### 9.1 GCP 一手文档

- [Publish services by using Private Service Connect](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer) — SA + PSC NAT Subnet 绑定
- [Proxy-only subnets for Envoy-based load balancers](https://cloud.google.com/load-balancing/docs/proxy-only-subnets) — proxy-only subnet 的 source IP 规则
- [Firewall rules for Cloud Load Balancing](https://cloud.google.com/load-balancing/docs/firewall-rules) — backend 该放通哪类 source 的官方分类
- [GKE firewall rules](https://cloud.google.com/kubernetes-engine/docs/concepts/firewall-rules) — GKE controller 自动创建的 firewall

### 9.2 上下文文档

- `../psc-subnet/psc-nat-vs-proxy-only-subnet.md` — 概念详解（按 LB 类型分类）— **作为参考材料**
- `../../cross-project/cross-project-firewall-netpol/README.md` — 跨项目 firewall 总览
- `../../cross-project/cross-project-firewall-netpol/references/scenario-a-via-mig-jumphost.md` — 路径 A 实施细节
- `../../cross-project/cross-project-firewall-netpol/references/scenario-b-via-gke-gateway.md` — 路径 B 实施细节
- `../../cross-project/cross-project-firewall-netpol/references/psc-firewall-cheatsheet.md` — passthrough vs proxy 速判表（参考材料）
- `../../cross-project/cross-project-firewall-netpol/references/log-capture-by-3-step-method.md` — **配套日志抓取 SOP**（按"3 步法"抓日志验证 firewall）|

---

*最后更新：2026-08-16 · Lex 个人知识库 · 按"实例视角 + 流量物理路径"组织*
*判定逻辑：Service Attachment → 看 backend 是什么实例 → 放通该实例所在 subnet ingress*