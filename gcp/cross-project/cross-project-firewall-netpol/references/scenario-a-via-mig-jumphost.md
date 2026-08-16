# Scenario A — Tenant → MIG (nginx jump host) → Master GKE Gateway

> 详细实施：跨项目 PSC + MIG (VM 跑 nginx) 作内部 LB backend，nginx 转发到 Master GKE Gateway 后端的路径。
>
> 对应 README §4 中的"变体 A"。

---

## 1. 链路全貌

```text
Tenant (Consumer)
  ├─ [Internet → 443] → Tenant GLB (External HTTPS LB)
  └─ → Tenant PSC NEG (type=PRIVATE_SERVICE_CONNECT)
        └─ → PSC Endpoint forwarding rule (私网 IP)
              ↓ PSC 跨项目隧道（无需 VPC peering，无需额外 firewall）
                ↓
Master (Producer)
  ├─ → PSC NAT Subnet (purpose=PRIVATE_SERVICE_CONNECT, 只 NAT 用)
  ├─ → Service Attachment (consumer-accept-list=Tenant)
  └─ → Internal Load Balancer (passthrough NLB，指向 MIG)
        └─ → MIG (VM 跑 nginx，proxy_pass <Master GKE Gateway VIP>)
              ├─ nginx.conf: upstream { server <MASTER_GW_VIP>:443; ... }
              ├─ proxy_ssl_server_name on + SNI=<Master FQDN>
              └─ → Master GKE Gateway (class=gke-l7-internal)
                    └─ → HTTPRoute → Service → Backend Pod
```

**关键中间层**：MIG 跑 nginx，做 path rewrite / TLS 终止 / 自定义 header。这是**多一跳**的代价。

---

## 2. 组件 × firewall / NetworkPolicy 矩阵

| 组件 | 类型 | 需要 ingress allow from | 需要 egress allow to | firewall rule 编号建议 |
|------|------|------------------------|---------------------|---------------------|
| **Tenant GLB** | GCP managed | Internet `0.0.0.0/0:443`（隐式） | → Tenant backend service | GLB 自动 |
| **Tenant Backend Service** | GCP managed | 不适用（逻辑组件） | → PSC NEG | 自动 |
| **Tenant PSC NEG** | GCP managed | 不适用（逻辑组件） | → PSC Endpoint | 自动 |
| **Tenant VM/Pod** | workload | 同 NS pod CIDR | → PSC endpoint IP:443 | T-WS-INGRESS / T-WS-EGRESS |
| **Tenant GKE NetworkPolicy** | K8s | pod selector | egress to PSC endpoint IP:443 | T-NP-* |
| **Master PSC NAT Subnet** | subnet | ❌ 不接收业务 | ❌ | — |
| **Master Service Attachment** | GCP managed | ❌ 不需要 | ❌ | — |
| **Master ILB (Internal passthrough NLB)** | GCP managed | 不直接接收流量（通过 backend service） | → MIG | 自动 |
| **Master MIG instance** | GCE VM | **PSC NAT subnet** CIDR:port + health check ranges:hc port | → Master GKE Gateway VIP:443 | M-MIG-INGRESS / M-MIG-EGRESS |
| **Master MIG instance** → health check | GCE VM | health check probe ranges | — | M-MIG-HC |
| **Master GKE Gateway** | K8s Gateway class=gke-l7-internal | — | — | GKE controller 自动 |
| **Master GKE Pod** | K8s workload | proxy-only subnet CIDR:port + 同 NS pod | → 上游（同集群通常不需） | M-NP-INGRESS / M-NP-EGRESS |
| **Google health check probes** | Google infra | hc port | — | M-MIG-HC / M-POD-HC |

---

## 3. Tenant 侧 firewall + NetworkPolicy 配置

### 3.1 假设拓扑

```text
Tenant Project = <TENANT_PROJECT>
Tenant VPC = <TENANT_VPC>
Tenant workload subnet = <TENANT_WS_SUBNET> (e.g. 10.10.0.0/20)
PSC endpoint IP = <PSC_ENDPOINT_IP> (e.g. 10.10.20.10)
PSC endpoint port = 443
```

### 3.2 VPC Firewall — Tenant 侧

#### T-WS-EGRESS：允许 workload 出向到 PSC endpoint

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

- `--direction=EGRESS`：明确出向规则（deny-all 项目必须）
- `--destination-ranges=<PSC_ENDPOINT_IP>/32`：**只放单个 PSC endpoint IP**，不要 `0.0.0.0/0`
- `--rules=tcp:443`：只放 HTTPS（producer 通常 listen 443）
- `--target-tags=tenant-workload`：精准定向，避免影响其他 workload

#### T-WS-INGRESS（如需）：workload 之间互访

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

**注意**：GKE Pod 流量在 node 内部走 iptables/kube-proxy，不一定走 VPC firewall。但如果跨 node 通信仍会经过 VPC。

### 3.3 K8s NetworkPolicy — Tenant GKE 集群

#### T-NP-EGRESS：Pod → PSC endpoint IP

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

**关键点**：

- `deny-all` namespace 下必须显式 Egress
- `ipBlock.cidr`：**只放单个 IP**（或 PSC endpoint 所在 subnet `/32` 单个）
- `ports.port=443`：精确端口，**不要**写 `0-65535`
- 必须给该 namespace 打 `podSelector` 选中的 pod 的 label，**否则不生效**

#### T-NP-INGRESS（如需）：Pod 接收入口流量

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-from-glb
  namespace: tenant-workloads
spec:
  podSelector:
    matchLabels:
      app: tenant-app
  policyTypes:
    - Ingress
  ingress:
    - from:
        - ipBlock:
            cidr: <TENANT_PROXY_ONLY_SUBNET_CIDR>
      ports:
        - protocol: TCP
          port: 8080
```

**注意**：Tenant GLB 如果走 **regional external Application LB（proxy 类）**，tenant 集群也需要 `proxy-only subnet`（purpose=REGIONAL_MANAGED_PROXY），并把该 subnet CIDR 放进 ingress allow。

---

## 4. Master 侧 firewall + NetworkPolicy 配置（重点）

### 4.1 假设拓扑

```text
Master Project = <MASTER_PROJECT>
Master VPC = <MASTER_VPC>
Master Region = <REGION>
PSC NAT subnet = <MASTER_PSC_NAT_SUBNET> (purpose=PRIVATE_SERVICE_CONNECT, e.g. 10.200.0.0/24)
MIG subnet = <MASTER_MIG_SUBNET> (e.g. 10.201.0.0/24)
MIG instance tag = master-mig-nginx
MIG listen port = 443
GKE Gateway class = gke-l7-internal
GKE node subnet = <MASTER_GKE_NODE_SUBNET> (e.g. 10.202.0.0/20)
GKE pod CIDR = <MASTER_GKE_POD_CIDR> (e.g. 10.203.0.0/16)
proxy-only subnet = <MASTER_PROXY_ONLY_SUBNET> (purpose=REGIONAL_MANAGED_PROXY, e.g. 10.204.0.0/23)
```

### 4.2 VPC Firewall — Master 侧

#### M-MIG-INGRESS：允许 PSC NAT subnet 访问 MIG

**为什么是 PSC NAT subnet**？

本场景用的是 **Internal passthrough Network Load Balancer**（不是 proxy 类）。passthrough LB 的 backend 看到的 source IP 是经过 PSC NAT subnet 转换后的地址 — 因为 PSC 隧道在 producer 边界做了 SNAT。

```bash
gcloud compute firewall-rules create m-mig-ingress-from-psc-nat \
  --project=${MASTER_PROJECT} \
  --network=${MASTER_VPC} \
  --direction=INGRESS \
  --action=ALLOW \
  --priority=1000 \
  --source-ranges=<MASTER_PSC_NAT_SUBNET_CIDR> \
  --target-tags=master-mig-nginx \
  --rules=tcp:443 \
  --description="Allow PSC NAT subnet to reach MIG (nginx on 443)"
```

**关键点**：

- `source-ranges=<MASTER_PSC_NAT_SUBNET_CIDR>`：**PSC NAT subnet 是 source**，不是 PSC endpoint IP，不是 LB VIP
- `target-tags=master-mig-nginx`：MIG instance 的 tag（创建 MIG 时打的）
- `tcp:443`：MIG 上 nginx listen 端口

#### M-MIG-HC：允许 Google health check probes

```bash
gcloud compute firewall-rules create m-mig-hc-allow-probes \
  --project=${MASTER_PROJECT} \
  --network=${MASTER_VPC} \
  --direction=INGRESS \
  --action=ALLOW \
  --priority=1000 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=master-mig-nginx \
  --rules=tcp:<HC_PORT> \
  --description="Allow Google health check probes to MIG"
```

**关键点**：

- `source-ranges=130.211.0.0/22,35.191.0.0/16`：Google 固定 health check probe 段（**永远叠加**）
- `<HC_PORT>` 必须和 backend service 的 health check port 一致
- 如果 hc 用的就是 443，这条和 M-MIG-INGRESS 合并为一条规则即可

#### M-MIG-EGRESS：允许 MIG → Master GKE Gateway VIP

MIG 上的 nginx 用 `proxy_pass http://<MASTER_GW_VIP>` 转发，需要 egress allow。

```bash
gcloud compute firewall-rules create m-mig-egress-to-gke-gateway \
  --project=${MASTER_PROJECT} \
  --network=${MASTER_VPC} \
  --direction=EGRESS \
  --action=ALLOW \
  --priority=1000 \
  --source-tags=master-mig-nginx \
  --destination-ranges=<MASTER_GKE_GATEWAY_IP>/32 \
  --rules=tcp:443 \
  --description="Allow MIG (nginx) egress to Master GKE Gateway VIP"
```

**关键点**：

- `source-tags=master-mig-nginx`：source tag 而非 destination
- `destination-ranges=<MASTER_GKE_GATEWAY_IP>/32`：**GKE Gateway 分配的实际 IP**，不是 cluster IP
- 如果 GKE Gateway 用 hostname 而非 IP（不推荐），改成放整个 `<MASTER_GKE_NODE_SUBNET_CIDR>` 或 `<MASTER_PROXY_ONLY_SUBNET_CIDR>`（看流量方向）

### 4.3 K8s NetworkPolicy — Master GKE 集群

#### M-NP-INGRESS：Pod 接收来自 MIG 的流量

如果 MIG 直接打到 Pod（不走 GKE Gateway），Ingress allow source = MIG subnet CIDR。

如果走 GKE Gateway（`gke-l7-internal`），Ingress allow source = **proxy-only subnet CIDR**（GKE Gateway 是 Envoy proxy 类 LB，Pod 看到的是 Envoy 出的 source）。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-from-mig-or-gateway
  namespace: backend-services
spec:
  podSelector:
    matchLabels:
      app: backend-app
  policyTypes:
    - Ingress
  ingress:
    # 路径 1：如果流量经过 GKE Gateway（gke-l7-internal）
    - from:
        - ipBlock:
            cidr: <MASTER_PROXY_ONLY_SUBNET_CIDR>
      ports:
        - protocol: TCP
          port: 8080
    # 路径 2：如果 MIG 直连 Pod（不走 Gateway）
    - from:
        - ipBlock:
            cidr: <MASTER_MIG_SUBNET_CIDR>
      ports:
        - protocol: TCP
          port: 8080
```

**关键点**：

- 同时放两条规则，覆盖两种部署形态
- `proxy-only subnet` 用途：GKE Gateway 内的 Envoy 出去时的 source IP 池
- 真实部署中通常**只走一条**（取决于是否真的有 GKE Gateway 介入）

#### M-NP-EGRESS：Pod → 外部（如 Tenant 回调）

如果 backend Pod 需要回调 Tenant（如 webhook），需要 egress allow。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-to-tenant
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
            cidr: <TENANT_VPC_CIDR>
      ports:
        - protocol: TCP
          port: 443
```

**注意**：大多数场景 backend Pod 不需要主动出去。如果有 audit / ETL 需求才需要。

---

## 5. 验证命令（按顺序跑）

### 5.1 Master 侧 — MIG firewall 验证

```bash
# 看 MIG 防火墙规则
gcloud compute firewall-rules list \
  --project=${MASTER_PROJECT} \
  --filter='targetTags=master-mig-nginx'

# 看 PSC NAT subnet CIDR（要塞进 firewall）
gcloud compute networks subnets describe ${MASTER_PSC_NAT_SUBNET} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --format='value(ipCidrRange)'

# 看 Service Attachment 状态（确认 PSC 已通）
gcloud compute service-attachments describe ${SA_NAME} \
  --project=${MASTER_PROJECT} \
  --region=${REGION} \
  --format='value(connectedEndpoints,pscConnectionStatus)'
```

### 5.2 Tenant → PSC endpoint 连通性测试

```bash
# 网络层（不依赖应用）
gcloud network-management connectivity-tests create tenant-to-psc-test \
  --source-ip=<tenant-workload-ip> \
  --destination-ip=${PSC_ENDPOINT_IP} \
  --destination-port=443 \
  --protocol=TCP \
  --project=${TENANT_PROJECT}

# 看结果（通常 30s 内出）
gcloud network-management connectivity-tests describe tenant-to-psc-test \
  --project=${TENANT_PROJECT}
```

### 5.3 Tenant → Master 完整链路测试

```bash
# 从 Tenant Pod 内 curl（应返回 backend 响应）
kubectl exec -it <tenant-pod> -n tenant-workloads -- \
  curl -v -H "Host: <MASTER_FQDN>" \
  --resolve <MASTER_FQDN>:443:${PSC_ENDPOINT_IP} \
  https://<MASTER_FQDN>/<PATH>
```

**期望**：HTTP 200 + backend 响应体。

如果失败，按 README §7 决策树排障。

### 5.4 Master GKE Pod 端验证

```bash
# 看 Pod 是否真被 NetworkPolicy 放行（用 /dev/tcp 模拟 TCP 握手）
kubectl exec -it <master-pod> -n backend-services -- bash -c '
  timeout 3 bash -c "echo > /dev/tcp/<mig-instance-ip>/443" && echo "TCP_OK" || echo "BLOCKED"
'

# 看 Pod 的 ingress 来源 IP（如果能拿到 tcpdump/conntrack 最好）
kubectl exec -it <master-pod> -n backend-services -- bash -c '
  cat /proc/net/tcp | head -20  # 限 distroless 镜像
'
```

---

## 6. 常见故障模式 + 排查

| 现象 | 根因 | 排查命令 | 修复 |
|------|------|---------|------|
| **Tenant curl 超时** | Tenant egress 没开或 PSC endpoint IP 不对 | `gcloud compute firewall-rules list --filter='direction=EGRESS'` | 加 T-WS-EGRESS |
| **Tenant curl 拿到 503** | Producer Service Attachment 未 accept | `gcloud compute service-attachments describe ${SA}` | 手动 accept 或改 `ACCEPT_AUTOMATIC` |
| **Tenant curl 拿到 connection refused** | MIG firewall 没开 | `gcloud compute firewall-rules list --project=${MASTER_PROJECT}` | 加 M-MIG-INGRESS |
| **MIG nginx 拿到 502** | MIG egress 到 GKE Gateway 被拦 | 看 MIG 上 `curl http://${GW_VIP}` | 加 M-MIG-EGRESS |
| **MIG nginx 拿到 504** | GKE Gateway 上游不通 / NetworkPolicy 拦 | 看 master pod log + `kubectl get netpol` | 加 M-NP-INGRESS |
| **Backend pod 看不到流量** | Master Pod NetworkPolicy deny-all | `kubectl get netpol -A` + `kubectl describe netpol` | 加 M-NP-INGRESS |
| **Health check 持续失败** | hc firewall 没开 / 端口不对 | `gcloud compute firewall-rules list --filter='sourceRanges=130.211.0.0/22'` | 加 M-MIG-HC |
| **流量到了 MIG 但 MIG log 没记录** | firewall 已通但 nginx listen 端口不对 | SSH 到 MIG 看 `ss -nltp` | 修 nginx.conf |

---

## 7. 反向路径（Master → Tenant）

变体 A 场景下，Master → Tenant 反向通常发生在：

- **Audit / metering pull**：Master Pod 拉 Tenant 的审计数据
- **Webhook 回调**：Master 服务完成后回调 Tenant
- **ETL**：Master 把 Tenant 数据回写到自己的 BigQuery

### 7.1 Audit pull 的 firewall 配置

```bash
# Master 侧：Pod egress → Tenant VPC
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

```yaml
# Master GKE NetworkPolicy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-to-tenant-vpc
  namespace: audit-services
spec:
  podSelector:
    matchLabels:
      app: audit-pull
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: <TENANT_VPC_CIDR>
      ports:
        - protocol: TCP
          port: 443
```

```bash
# Tenant 侧：允许 Master VPC 访问 Tenant API endpoint
gcloud compute firewall-rules create t-allow-master-pod-ingress \
  --project=${TENANT_PROJECT} \
  --network=${TENANT_VPC} \
  --direction=INGRESS \
  --action=ALLOW \
  --priority=1000 \
  --source-ranges=<MASTER_VPC_CIDR> \
  --rules=tcp:443 \
  --target-tags=tenant-api-endpoint \
  --description="Allow Master VPC ingress to Tenant API"
```

### 7.2 Webhook 回调（Master 服务完成后回调 Tenant）

走 PSC 反向（不太常见，但可行）：Master 创建 Service Attachment，Tenant 创建 PSC Endpoint。或走 internet（不安全）。通常不推荐反向 PSC，建议走 API endpoint + IAM。

---

## 8. 完整 firewall 规则清单（合并去重后）

假设都在 `<REGION>` / `<MASTER_PROJECT>`：

| 优先级 | firewall rule 名 | direction | source | dest | port | target tag | 用途 |
|--------|-----------------|-----------|--------|------|------|-----------|------|
| 1000 | `m-mig-ingress-from-psc-nat` | INGRESS | PSC NAT subnet | MIG | 443 | master-mig-nginx | PSC 流量进 MIG |
| 1000 | `m-mig-hc-allow-probes` | INGRESS | 130.211.0.0/22 + 35.191.0.0/16 | MIG | hc port | master-mig-nginx | health check |
| 1000 | `m-mig-egress-to-gke-gateway` | EGRESS | master-mig-nginx | GW VIP | 443 | — | nginx → GKE Gateway |
| 1000 | `m-pod-egress-to-tenant` | EGRESS | GKE pod CIDR | Tenant VPC | 443 | gke-node | 反向 audit |
| 1000 | `t-ws-egress-to-psc-ep` | EGRESS | Tenant ws subnet | PSC EP IP | 443 | tenant-workload | Tenant 出向 PSC |
| 1000 | `t-allow-master-pod-ingress` | INGRESS | Master VPC | Tenant API | 443 | tenant-api-endpoint | 反向 webhook |

**NetworkPolicy 合并**：

| Name | namespace | podSelector | direction | rule |
|------|-----------|-------------|-----------|------|
| `allow-egress-to-psc-endpoint` | tenant-workloads | app=tenant-app | Egress | to PSC EP IP:443 |
| `allow-ingress-from-gateway` | backend-services | app=backend-app | Ingress | from proxy-only subnet:8080 |
| `allow-ingress-from-mig` | backend-services | app=backend-app | Ingress | from MIG subnet:8080 |
| `allow-egress-to-tenant-vpc` | audit-services | app=audit-pull | Egress | to Tenant VPC:443 |

---

## 9. 一句话总结（变体 A）

**变体 A 是"passthrough + 多跳"组合 — Tenant egress 放 PSC EP，Master MIG ingress 放 PSC NAT subnet + hc，MIG egress 放 GKE Gateway IP，Master Pod ingress 放 proxy-only subnet；MIG 是中间一跳，因此比变体 B 多 4 条规则。**

---

## 10. References

- [Publish services by using Private Service Connect](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer)
- [Firewall rules for Cloud Load Balancing](https://cloud.google.com/load-balancing/docs/firewall-rules)
- [Internal passthrough Network Load Balancer overview](https://cloud.google.com/load-balancing/docs/internal)
- [GKE automatically created firewall rules](https://cloud.google.com/kubernetes-engine/docs/concepts/firewall-rules)
- [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- 上级文档：`../README.md` §4（变体对比表）+ `../../psc-firewall.md` §17-§22（passthrough vs proxy 判定）
- 决策脚本（待补）：`scripts/audit-firewall-rules.sh`

---

*最后更新：2026-08-16 · Lex 个人知识库，遵循 redaction policy*