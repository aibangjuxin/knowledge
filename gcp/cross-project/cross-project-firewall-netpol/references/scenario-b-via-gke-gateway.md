# Scenario B — Tenant → Master GKE Gateway (直接)

> 详细实施：跨项目 PSC + GKE Gateway 直接作为 Service Attachment backend（无中间 MIG）。
>
> 对应 README §4 中的"变体 B"。
>
> 这是 Lex 实际生产里"k8s gateway"那条路径 — Tenant Project 持有 PSC Endpoint，Master GKE Gateway 通过 Service Attachment 暴露给 Tenant。

---

## 1. 链路全貌

```text
Tenant (Consumer)
  ├─ [Internet → 443] → Tenant GLB (External HTTPS LB)
  └─ → Tenant PSC NEG (type=PRIVATE_SERVICE_CONNECT)
        └─ → PSC Endpoint forwarding rule (私网 IP)
              ↓ PSC 跨项目隧道（无需 VPC peering）
                ↓
Master (Producer)
  ├─ → PSC NAT Subnet (purpose=PRIVATE_SERVICE_CONNECT)
  ├─ → Service Attachment (consumer-accept-list=Tenant)
  └─ → GKE Gateway (class=gke-l7-internal 或 gke-l7-rilb)
        └─ 底层是 regional internal Application Load Balancer (proxy 类)
              ├─ target HTTPS proxy + URL map
              ├─ → proxy-only subnet (Envoy 出 pod 时的 source IP 池)
              └─ → Backend Service (Neg/instance group)
                    └─ → Backend Pod (GKE workload)
```

**关键点**：

- Service Attachment **直接指向** GKE Gateway 创建的 forwarding rule
- GKE Gateway 底层是 **regional internal Application LB**（proxy 类）
- **proxy-only subnet 必须存在**（GKE Gateway controller 自动管理）
- backend 看到的 source IP = **`proxy-only subnet CIDR`**（不是 PSC NAT subnet）

---

## 2. 组件 × firewall / NetworkPolicy 矩阵

| 组件 | 类型 | 需要 ingress allow from | 需要 egress allow to | firewall rule 编号建议 |
|------|------|------------------------|---------------------|---------------------|
| **Tenant GLB** | GCP managed | Internet `0.0.0.0/0:443`（隐式） | → Tenant backend service | GLB 自动 |
| **Tenant Backend Service** | GCP managed | 不适用 | → PSC NEG | 自动 |
| **Tenant PSC NEG** | GCP managed | 不适用 | → PSC Endpoint | 自动 |
| **Tenant VM/Pod** | workload | 同 NS pod | → **PSC endpoint IP:443** | T-WS-EGRESS |
| **Tenant GKE NetworkPolicy** | K8s | pod selector | egress to PSC EP:443 | T-NP-EGRESS |
| **Master PSC NAT Subnet** | subnet | ❌ 不接收业务 | ❌ | — |
| **Master Service Attachment** | GCP managed | ❌ 不需要 | ❌ | — |
| **Master proxy-only subnet** | subnet | ❌ 不直接接收流量 | Envoy 出口 | `purpose=REGIONAL_MANAGED_PROXY` |
| **Master internal ALB (GKE Gateway 底层)** | GCP managed | — | → Backend Service | 自动 |
| **Master Backend Service** | GCP managed | ❌ 逻辑组件 | ❌ | — |
| **Master GKE Pod (Backend)** | K8s workload | **proxy-only subnet CIDR:port** + 同 NS pod | → 上游（同集群通常不需） | M-NP-INGRESS |
| **Google health check probes** | Google infra | hc port | — | M-POD-HC |
| **GKE Gateway controller auto firewall** | GCP managed | **GKE 自动创建** + 健康检查 | — | GKE controller 自动 |

---

## 3. 与变体 A 的核心差异

| 维度 | 变体 A (via MIG) | 变体 B (直接 GKE GW) |
|------|-----------------|---------------------|
| **Producer LB 类型** | Internal passthrough NLB | regional internal Application LB (proxy) |
| **Service Attachment target** | MIG ILB forwarding rule | GKE Gateway forwarding rule |
| **proxy-only subnet** | 不需要（passthrough） | **必须有** |
| **backend source 类型** | PSC NAT subnet | **proxy-only subnet** |
| **Master 防火墙规则数** | 5+ 条（MIG + hc + egress + ingress + 反向） | 1-2 条（hc + 可选反向） |
| **MIG lifecycle 管理** | 需要 | 不需要 |
| **GKE controller 角色** | 仅 backend | **核心**（创建 LB + firewall + NEG） |
| **复杂度** | Advanced | Moderate |

**为什么变体 B 更简单？**

- 少一跳，少一组 firewall
- GKE Gateway controller 自动创建大部分防火墙规则
- backend Pod 只需要 NetworkPolicy Ingress allow proxy-only subnet

---

## 4. Tenant 侧 firewall + NetworkPolicy 配置

### 4.1 假设拓扑

```text
Tenant Project = <TENANT_PROJECT>
Tenant VPC = <TENANT_VPC>
Tenant workload subnet = <TENANT_WS_SUBNET> (e.g. 10.10.0.0/20)
PSC endpoint IP = <PSC_ENDPOINT_IP> (e.g. 10.10.20.10)
PSC endpoint port = 443
```

### 4.2 VPC Firewall — Tenant 侧

#### T-WS-EGRESS：workload → PSC endpoint

```bash
gcloud compute firewall-rules create t-ws-egress-to-psc-ep \
  --project=${TENANT_PROJECT} \
  --network=${TENANT_VPC} \
  --direction=EGRESS \
  --action=ALLOW \
  --priority=1000 \
  --source-ranges=<TENANT_WS_SUBNET_CIDR> \
  --destination-ranges=<PSC_ENDPOINT_IP>/32 \
  --rules=tcp:443 \
  --target-tags=tenant-workload \
  --description="Allow Tenant workload egress to PSC endpoint"
```

**关键点**：

- **和变体 A 完全一致**（Tenant 侧的 firewall 不依赖 Producer 内部结构）
- `--destination-ranges=<PSC_ENDPOINT_IP>/32`：单个 IP，不放 `0.0.0.0/0`
- `--rules=tcp:443`：HTTPS，**如果 producer 是 HTTP 80，改成 80**

#### T-WS-INGRESS（如需）

```bash
gcloud compute firewall-rules create t-ws-ingress-from-same-subnet \
  --project=${TENANT_PROJECT} \
  --network=${TENANT_VPC} \
  --direction=INGRESS \
  --action=ALLOW \
  --priority=1000 \
  --source-ranges=<TENANT_WS_SUBNET_CIDR> \
  --rules=tcp,udp,icmp \
  --target-tags=tenant-workload \
  --description="Allow intra-subnet workload traffic"
```

### 4.3 K8s NetworkPolicy — Tenant GKE

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-to-psc-endpoint
  namespace: tenant-workloads
spec:
  podSelector:
    matchLabels:
      app: tenant-app
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: <PSC_ENDPOINT_IP>/32
      ports:
        - protocol: TCP
          port: 443
```

**和变体 A 一样** — Tenant 侧 NetworkPolicy 与 Producer 内部结构无关。

---

## 5. Master 侧 firewall + NetworkPolicy 配置（重点）

### 5.1 假设拓扑

```text
Master Project = <MASTER_PROJECT>
Master VPC = <MASTER_VPC>
Master Region = <REGION>
PSC NAT subnet = <MASTER_PSC_NAT_SUBNET> (purpose=PRIVATE_SERVICE_CONNECT, e.g. 10.200.0.0/24)
proxy-only subnet = <MASTER_PROXY_ONLY_SUBNET> (purpose=REGIONAL_MANAGED_PROXY, e.g. 10.204.0.0/23)
GKE cluster name = <MASTER_GKE_CLUSTER>
GKE node subnet = <MASTER_GKE_NODE_SUBNET> (e.g. 10.202.0.0/20)
GKE pod CIDR = <MASTER_GKE_POD_CIDR> (e.g. 10.203.0.0/16)
GKE Gateway class = gke-l7-internal
Backend namespace = backend-services
Backend pod label = app=backend-app, port=8080
```

### 5.2 VPC Firewall — Master 侧

#### 自动 vs 手动

**GKE Gateway controller 会自动创建以下 firewall rules**（详见 [GKE firewall docs](https://cloud.google.com/kubernetes-engine/docs/concepts/firewall-rules)）：

1. **Health check firewall** — allow Google probe ranges 到 GKE node port
2. **Master cluster firewall** — GKE master 到 node:443 / node:10250

**你必须手动确认或补充**：

1. **proxy-only subnet 到 backend Pod** 的路径 — **通常被 GKE controller 自动管理**，但要验证
2. **Backend Pod 到 Tenant 反向** — GKE 不会自动加

#### 验证 GKE 自动创建的 firewall

```bash
gcloud compute firewall-rules list \
  --project=${MASTER_PROJECT} \
  --filter='targetTags=gke-node'

# 期望看到这些：
# - gke-<cluster>-<uuid>-all  (allow all within cluster)
# - gke-<cluster>-<uuid>-master  (master to nodes)
# - gke-<cluster>-<uuid>-hc-<N>  (health check ranges)
```

#### M-POD-HC：如 GKE 自动规则没覆盖，手动补 health check

```bash
gcloud compute firewall-rules create m-pod-hc-allow-probes \
  --project=${MASTER_PROJECT} \
  --network=${MASTER_VPC} \
  --direction=INGRESS \
  --action=ALLOW \
  --priority=1000 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=gke-node \
  --rules=tcp:<HC_PORT> \
  --description="Allow Google health check probes to GKE nodes"
```

**关键点**：

- 实际生产中这条**通常已被 GKE 自动创建**（priority 1000+），先 list 验证，没的话再手动加
- 如果 health check 端口是 NEG 的 namedPort（如 `http:8080`），hc 实际 probe 的是 node port，规则 `tcp:NodePort` 范围

#### M-POD-EGRESS（如需）：Pod → Tenant 反向

如果 backend Pod 不需要回调 Tenant，这条**不需要**。

```bash
gcloud compute firewall-rules create m-pod-egress-to-tenant \
  --project=${MASTER_PROJECT} \
  --network=${MASTER_VPC} \
  --direction=EGRESS \
  --action=ALLOW \
  --priority=1000 \
  --source-ranges=<MASTER_GKE_POD_CIDR> \
  --destination-ranges=<TENANT_VPC_CIDR> \
  --rules=tcp:443 \
  --target-tags=gke-node \
  --description="Allow Master GKE Pod egress to Tenant VPC"
```

### 5.3 K8s NetworkPolicy — Master GKE 集群

#### M-NP-INGRESS：Pod 接收来自 proxy-only subnet 的流量

**这是变体 B 的核心规则**。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-from-gateway-proxy
  namespace: backend-services
spec:
  podSelector:
    matchLabels:
      app: backend-app
  policyTypes:
    - Ingress
  ingress:
    - from:
        - ipBlock:
            cidr: <MASTER_PROXY_ONLY_SUBNET_CIDR>
      ports:
        - protocol: TCP
          port: 8080
```

**为什么是 proxy-only subnet 而不是 PSC NAT subnet？**

- 流量路径：`Tenant Pod → PSC EP → PSC tunnel → Producer Service Attachment → GKE Gateway (Envoy proxy)`
- Envoy proxy 在 backend Pod 视角是 source
- Envoy 出口用 `proxy-only subnet` 的 IP（这是 GCP 设计的固定分配）
- **绝不能放 PSC NAT subnet**，因为 PSC NAT 只在 passthrough 路径下生效

**如果 backend Pod 也需要被同 namespace 其他 Pod 调用**（如 debug / sidecar），加第二条：

```yaml
ingress:
  - from:
      - ipBlock:
          cidr: <MASTER_PROXY_ONLY_SUBNET_CIDR>
      ports:
        - protocol: TCP
          port: 8080
  - from:
      - podSelector:
          matchLabels:
            app: same-namespace-app
      ports:
        - protocol: TCP
          port: 8080
```

#### M-NP-EGRESS：Pod → 外部（如 Tenant 回调 / 外部 API）

默认 deny-all namespace 必须显式开：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-dns-and-external
  namespace: backend-services
spec:
  podSelector:
    matchLabels:
      app: backend-app
  policyTypes:
    - Egress
  egress:
    # 必须：DNS 解析
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # 必须：kube-apiserver（如有 leader election）
    - to:
        - ipBlock:
            cidr: <MASTER_GKE_MASTER_IPV4_CIDR>
      ports:
        - protocol: TCP
          port: 443
    # 可选：Tenant 反向
    - to:
        - ipBlock:
            cidr: <TENANT_VPC_CIDR>
      ports:
        - protocol: TCP
          port: 443
```

**关键点**：

- **`DNS egress 永远要开**（kube-system 内 kube-dns 服务，UDP/TCP 53）— 这是 K8s 默认 network policy 的隐藏坑
- **`kube-apiserver egress` 视情况**（如果 controller / leader election 需要）
- **Tenant VPC egress** 只在反向场景需要

---

## 6. GKE Gateway controller 自动行为详解

### 6.1 自动创建的 VPC firewall

参考 [GKE firewall docs](https://cloud.google.com/kubernetes-engine/docs/concepts/firewall-rules)：

| 自动规则名 pattern | direction | source | target | 用途 |
|-------------------|-----------|--------|--------|------|
| `gke-<cluster>-<uuid>-all` | INGRESS | `<NODE_SUBNET>`, `<POD_CIDR>`, `<CLUSTER_POD_CIDR>`, `<MASTER_CIDR>` | gke-node | cluster 内部互访 |
| `gke-<cluster>-<uuid>-master` | INGRESS | GKE master CIDR | gke-node:443, gke-node:10250 | kubelet 通信 |
| `gke-<cluster>-<uuid>-hc-<N>` | INGRESS | `130.211.0.0/22`, `35.191.0.0/16` | gke-node:NodePort | NEG health check |
| `gke-<cluster>-<uuid>-mcsd` | INGRESS | cluster CIDR | gke-node:mcsd port | Multi-cluster Service Discovery |

**GKE Gateway 还会自动创建**：

- NEG + health check + firewall for **每个 HTTPRoute backend**
- 具体规则名带 `gke-l7-rilb` / `gke-l7-internal` 前缀

### 6.2 必须显式声明的（deny-all 环境）

虽然 GKE 创建了规则，**你仍然必须**：

1. **K8s NetworkPolicy**：GKE 不会自动写 NetworkPolicy（NetworkPolicy 是 K8s 层资源）
2. **proxy-only subnet 已配置**：GKE Gateway 强依赖

### 6.3 验证 controller 是否成功创建规则

```bash
# 1. Gateway 状态
kubectl describe gateway <gateway-name> -n <ns>

# 2. 自动生成的 firewall
gcloud compute firewall-rules list \
  --project=${MASTER_PROJECT} \
  --filter='name~"gke-.*l7-.*"'

# 3. NEG 状态
gcloud compute network-endpoint-groups list \
  --project=${MASTER_PROJECT} \
  --region=${REGION}
```

---

## 7. 验证命令（按顺序跑）

### 7.1 Master 侧 — 自动 firewall 验证

```bash
# 看所有 GKE 相关 firewall
gcloud compute firewall-rules list \
  --project=${MASTER_PROJECT} \
  --filter='targetTags:gke-node OR targetTags:gke-'

# 看 proxy-only subnet
gcloud compute networks subnets list \
  --project=${MASTER_PROJECT} \
  --filter='purpose="REGIONAL_MANAGED_PROXY"'

# 看 Service Attachment 状态
gcloud compute service-attachments describe ${SA_NAME} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --format='value(connectedEndpoints,pscConnectionStatus)'
```

### 7.2 Tenant → PSC endpoint 网络层测试

```bash
gcloud network-management connectivity-tests create tenant-to-master-gw \
  --source-ip=<tenant-workload-ip> \
  --destination-ip=${PSC_ENDPOINT_IP} \
  --destination-port=443 \
  --protocol=TCP \
  --project=${TENANT_PROJECT}

# 30s 后看结果
gcloud network-management connectivity-tests describe tenant-to-master-gw \
  --project=${TENANT_PROJECT}
```

### 7.3 Tenant → Master 应用层测试

```bash
# 从 Tenant Pod 内 curl
kubectl exec -it <tenant-pod> -n tenant-workloads -- \
  curl -v -H "Host: <MASTER_FQDN>" \
  --resolve <MASTER_FQDN>:443:${PSC_ENDPOINT_IP} \
  https://<MASTER_FQDN>/<PATH>
```

**期望**：HTTP 200 + backend 响应。

### 7.4 Master Pod 端验证（确认 source 是 proxy-only）

```bash
# 在 master pod 上看 conntrack 或 netstat，看 source IP 是否落在 proxy-only subnet
kubectl exec -it <master-pod> -n backend-services -- bash -c '
  cat /proc/net/tcp | awk "{print \$2,\$3}" | head -10
'

# 或用 ss（如果有）
kubectl exec -it <master-pod> -n backend-services -- ss -nta

# 测试从 proxy-only subnet 段来的 TCP 握手
kubectl exec -it <master-pod> -n backend-services -- bash -c '
  timeout 3 bash -c "echo > /dev/tcp/<proxy-only-ip>/8080" && echo "TCP_OK" || echo "BLOCKED"
'
```

---

## 8. 常见故障模式 + 排查

| 现象 | 根因 | 排查 | 修复 |
|------|------|------|------|
| **Tenant curl 超时** | Tenant egress 没开 | `gcloud compute firewall-rules list --filter='direction=EGRESS'` | 加 T-WS-EGRESS |
| **Tenant curl 拿到 503** | Service Attachment 未 accept | `gcloud compute service-attachments describe` | 手动 accept |
| **Tenant curl 拿到 502/504** | Gateway 未 Programmed | `kubectl describe gateway` | 等 controller 落资源 |
| **Tenant curl 拿到 connection refused** | proxy-only subnet 没建 / 没绑 VPC | `gcloud compute networks subnets list --filter='purpose=REGIONAL_MANAGED_PROXY'` | 加 proxy-only subnet |
| **Gateway controller 没创建 firewall** | GKE controller 权限不足 / Shared VPC 受限 | 看 controller log / IAM | 给 controller service account `compute.firewalls.create` |
| **Backend Pod 看不到流量** | NetworkPolicy Ingress 没放 proxy-only subnet | `kubectl get netpol -A` | 加 M-NP-INGRESS |
| **Backend Pod 拿到流量但 egress DNS 失败** | 默认 deny namespace 没放 kube-dns | `kubectl exec -- nslookup` | 加 M-NP-EGRESS DNS rule |
| **Health check 失败** | hc firewall 被 hierarchical policy 覆盖 | `gcloud compute firewall-rules list --organization` | 检查 Org Policy |
| **Pod 拿不到请求但 controller log 显示流量到 NEG** | Pod readiness probe 失败 | `kubectl describe pod` | 修 readiness probe path |

---

## 9. 反向路径（Master → Tenant）

变体 B 中 Master → Tenant 反向同样存在，主要场景：

### 9.1 Webhook 回调

```yaml
# Master GKE Pod NetworkPolicy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-to-tenant-webhook
  namespace: backend-services
spec:
  podSelector:
    matchLabels:
      app: backend-app
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: <TENANT_WEBHOOK_ENDPOINT_IP>/32
      ports:
        - protocol: TCP
          port: 443
```

```bash
# Tenant 侧 ingress
gcloud compute firewall-rules create t-allow-master-webhook \
  --project=${TENANT_PROJECT} \
  --network=${TENANT_VPC} \
  --direction=INGRESS \
  --action=ALLOW \
  --priority=1000 \
  --source-ranges=<MASTER_VPC_CIDR> \
  --rules=tcp:443 \
  --target-tags=tenant-webhook \
  --description="Allow Master VPC ingress to Tenant webhook endpoint"
```

### 9.2 Audit / Metering pull

通常走 **API + IAM**（不靠 firewall）。如必须走网络：

- Master Pod egress → Tenant API endpoint（专用 IP，不在 deny-all 范围）
- Tenant 端 ingress allow Master VPC

### 9.3 BigQuery / GCS 反向写入

**走 IAM，不走 firewall**。给 Master GSA `roles/bigquery.dataEditor` 即可。

---

## 10. 完整 firewall 规则清单

| 优先级 | firewall rule 名 | direction | source | dest | port | target tag | 用途 |
|--------|-----------------|-----------|--------|------|------|-----------|------|
| 1000 | `t-ws-egress-to-psc-ep` | EGRESS | Tenant ws subnet | PSC EP IP | 443 | tenant-workload | Tenant 出向 PSC |
| 1000 | `t-allow-master-webhook` | INGRESS | Master VPC | Tenant webhook | 443 | tenant-webhook | 反向 webhook |
| auto | `gke-<cluster>-<uuid>-all` | INGRESS | node/pod/master CIDR | node | 0-65535 | gke-node | GKE 内部 |
| auto | `gke-<cluster>-<uuid>-master` | INGRESS | master CIDR | node | 443,10250 | gke-node | kubelet |
| auto | `gke-<cluster>-<uuid>-hc-<N>` | INGRESS | 130.211.0.0/22 + 35.191.0.0/16 | node | NodePort | gke-node | NEG hc |
| auto | `gke-<cluster>-l7-rilb-<uuid>` | INGRESS | proxy-only subnet | node | NodePort | gke-node | Gateway hc |
| 1000 | `m-pod-egress-to-tenant` | EGRESS | Master pod CIDR | Tenant VPC | 443 | gke-node | 反向 audit |

**NetworkPolicy 合并**：

| Name | namespace | podSelector | direction | rule |
|------|-----------|-------------|-----------|------|
| `allow-egress-to-psc-endpoint` | tenant-workloads | app=tenant-app | Egress | to PSC EP IP:443 |
| `allow-ingress-from-gateway-proxy` | backend-services | app=backend-app | Ingress | from proxy-only subnet:8080 |
| `allow-egress-dns-and-external` | backend-services | app=backend-app | Egress | DNS + kube-apiserver + Tenant VPC |
| `allow-egress-to-tenant-webhook` | backend-services | app=backend-app | Egress | to Tenant webhook:443 |

---

## 11. 变体 A vs 变体 B 防火墙规则数对比

| 规则类型 | 变体 A | 变体 B | 差异原因 |
|---------|--------|--------|----------|
| Tenant egress | 1 | 1 | 一样 |
| Tenant ingress | 0-1 | 0-1 | 一样 |
| Master MIG ingress | 2（PSC NAT + hc） | 0 | 变体 B 无 MIG |
| Master MIG egress | 1（→ GW） | 0 | 变体 B 无 MIG |
| Master Pod ingress | 1（proxy-only 或 MIG） | 1（proxy-only） | source 不同 |
| Master Pod egress | 0-1（DNS + 反向） | 0-1（DNS + 反向） | 一样 |
| **GKE 自动规则** | 0（不变体 B 依赖 GKE Gateway 介入） | 4-6 | 变体 B 重度依赖 |
| **反向路径** | 0-2 | 0-2 | 视场景 |
| **总计** | **5-7** | **3-5** | 变体 B 简单 |

---

## 12. 一句话总结（变体 B）

**变体 B 是"proxy + 少跳"组合 — Tenant egress 放 PSC EP，Master Pod ingress 放 proxy-only subnet；GKE Gateway controller 自动管理 4-6 条 firewall，你只需要在 NetworkPolicy 层显式声明 Ingress from proxy-only subnet。**

---

## 13. References

- [Publish services by using Private Service Connect](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer)
- [Internal Application Load Balancer overview](https://cloud.google.com/load-balancing/docs/l7-internal)
- [Deploying Gateways](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)
- [GKE automatically created firewall rules](https://cloud.google.com/kubernetes-engine/docs/concepts/firewall-rules)
- [Firewall rules for Cloud Load Balancing](https://cloud.google.com/load-balancing/docs/firewall-rules)
- [Internal load balancing across VPC networks](https://cloud.google.com/kubernetes-engine/docs/how-to/internal-load-balancing-across-vpc-net)（Lex 原话引用 URL — 实施前需补一手验证内容）
- 上级文档：`../README.md` §4（变体对比表）+ `../../psc-firewall.md` §17-§22

---

*最后更新：2026-08-16 · Lex 个人知识库，遵循 redaction policy*