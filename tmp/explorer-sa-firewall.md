# GCP Firewall Rules — Service Account & GKE 深度探索

> 本文档基于 GCP 官方文档调研，对以下三个场景进行深度分析：
> 1. 基于 Service Account 的防火墙规则（Ingress / Egress）
> 2. GCE 与 GKE (Node/Pod/Service) 之间的通信防火墙规则
> 3. GKE Pod 经由 GCE NAT Gateway 出口的防火墙配置

---

## 1. Service Account 作为防火墙过滤条件

### 1.1 核心限制

GCP VPC Firewall Rules 对 Service Account 作为 source/destination 的支持是**方向相关**的：

| 规则方向    | Target 可用 SA？ | Source 可用 SA？           |
| ----------- | ---------------- | -------------------------- |
| **Ingress** | ✅ Yes            | ✅ Yes                      |
| **Egress**  | ✅ Yes            | ❌ **No**（仅支持 IP CIDR） |

**关键限制**：Egress 规则的 source 只能是 IP 范围，不能是 Service Account。

### 1.2 Ingress 规则 — Service Account 作为 Source

入站规则可以将 source 指定为同一 VPC 中的服务账号：

```
入站规则 source = <Service Account>
  → 数据包来源：使用该 SA 的实例的主要内部 IP
  → 隐含：不会使用别名 IP 范围或外部 IP
```

**匹配逻辑**：
- 网络接口必须在定义防火墙规则的 VPC 中
- 虚拟机必须与防火墙规则的 source service account 匹配
- 数据包必须使用该网络接口的主要内部 IPv4 地址（或 IPv6）

### 1.3 Egress 规则 — Service Account 作为 Target

Egress 规则可以使用 Service Account 作为 **target**（规则应用到哪些实例），但 **source 只能是 IP**：

```
出站规则：
  Target   = <Service Account> ✅ 可以
  Source   = <IP CIDR>        ❌ 只能是 IP，不能是 SA
  Destination = <IP CIDR>     ✅ 可以
```

### 1.4 nginx → squid 通信案例
- 其实在这里这样理解会更简单一点。对于我的squid来说，就需要一个Ingress。
- 对于我的Nginx来说，就是一个Egress。
- target-service-accounts 就是这个对应的目标主机。这个目标主机需要Egress规则。
```
场景：Nginx (abjx-nginx@project.iam.gserviceaccount.com) → Squid (abjx-squid@project.iam.gserviceaccount.com)
```

**正确配置方式：**

```
# Nginx 端：Egress 规则（target = nginx SA，destination = squid IP range）
gcloud compute firewall-rules create allow-nginx-to-squid-egress \
  --network=vpc \
  --allow=tcp:3128 \
  --target-service-accounts=abjx-nginx@projectid.iam.gserviceaccount.com \
  --destination-ranges=<SQUID_IP>/32 \
  --direction=EGRESS

# Squid 端：Ingress 规则（target = squid SA，source = squid 可接受的范围）
gcloud compute firewall-rules create allow-nginx-to-squid-ingress \
  --network=vpc \
  --allow=tcp:3128 \
  --target-service-accounts=abjx-squid@projectid.iam.gserviceaccount.com \
  --source-ranges=<SQUID_IP>/32 \
  --direction=INGRESS
```

**局限性**：
- Egress destination 仍需要 IP 范围，无法用 SA 名称解耦
- 如果 Squid IP 变化，必须更新 Nginx 的 Egress 规则

### 1.5 解耦方案对比

| 方案                       | 原理                                   | 优点              | 缺点                      |
| -------------------------- | -------------------------------------- | ----------------- | ------------------------- |
| **Target SA + IP CIDR**    | Egress target 用 SA，destination 用 IP | 规则与源实例解耦  | destination IP 仍需维护   |
| **Firewall Policy + FQDN** | NGFW Standard 支持 FQDN 过滤           | 完全按域名而非 IP | 需要 NGFW Standard 许可证 |
| **GKE NetworkPolicy**      | Pod 级别 L3/L7 策略，基于标签          | 与 IP 完全解耦    | 仅适用于 GKE Pod          |
| **Istio/Service Mesh**     | VirtualService + AuthorizationPolicy   | L7 策略，完全解耦 | 引入 mesh 复杂度          |

---

## 2. GCE ↔ GKE 通信防火墙规则

### 2.1 GKE 网络地址体系

GKE 在 VPC 环境中使用多个 IP 范围：

| 组件              | 来源                              | 示例 CIDR          |
| ----------------- | --------------------------------- | ------------------ |
| **Node**          | 节点子网（primary range）         | `10.0.0.0/24`      |
| **Pod**           | Secondary range（VPC alias）      | `100.64.0.0/14`    |
| **Service**       | Secondary range（另一 VPC alias） | `100.68.0.0/17`    |
| **Control Plane** | Master IP range（私有集群）       | `192.168.224.0/28` |

### 2.2 GCE VM 访问 GKE Pod

```
GCE VM (10.0.1.0/24) → GKE Pod (100.64.0.0/14)
```

**需要的防火墙规则：**

```
# 1. 允许 GCE VM 的入站流量（如果 GCE 是被访问方）
gcloud compute firewall-rules create allow-gce-to-gke-pods \
  --network=vpc \
  --allow=tcp:80,tcp:443 \
  --source-ranges=10.0.1.0/24 \
  --target-tags=gke-nodes \
  --direction=INGRESS

# 2. GKE 节点允许来自 GCE VM 子网的流量（用于 NodePort/LoadBalancer）
gcloud compute firewall-rules create allow-gce-subnet-to-gke-nodes \
  --network=vpc \
  --allow=tcp:30000-32767 \
  --source-ranges=10.0.0.0/16 \
  --target-tags=gke-nodes \
  --direction=INGRESS

# 3. GKE Pod 返回流量（stateful，自动允许返回）
# VPC 防火墙是有状态的，返回流量自动放行
```

### 2.3 GKE Pod 访问 GCE VM

```
GKE Pod (100.64.0.0/14) → GCE VM (10.0.1.0/24)
```

**需要的防火墙规则：**

```
# 1. GKE Pod 出站规则（target = GKE nodes，destination = GCE 子网）
# 注意：Egress source 不能用 SA，必须用 IP 范围
gcloud compute firewall-rules create allow-pods-to-gce-egress \
  --network=vpc \
  --allow=tcp:5432 \
  --source-ranges=100.64.0.0/14 \
  --destination-ranges=10.0.1.0/24 \
  --direction=EGRESS

# 2. GCE VM 入站规则
gcloud compute firewall-rules create allow-pods-to-gce-ingress \
  --network=vpc \
  --allow=tcp:5432 \
  --source-ranges=100.64.0.0/14 \
  --target-tags=gce-vms \
  --direction=INGRESS
```

### 2.4 GKE 节点健康检查注意事项

GKE 私有集群中，L7 ILB 健康检查源 IP 来自：
- `35.191.0.0/16`（Google 托管范围）
- `130.211.0.0/22`（Google 负载均衡器）

这些需要在节点入站规则中允许。

### 2.5 GKE NetworkPolicy vs VPC Firewall Rules

| 层面       | 工具           | 作用范围            | 基于           |
| ---------- | -------------- | ------------------- | -------------- |
| **VPC 层** | Firewall Rules | GCE Instance / Node | IP / Tag / SA  |
| **Pod 层** | NetworkPolicy  | Pod-to-Pod          | Label selector |

**最佳实践**：
- VPC Firewall Rules 管理 Node 级别入口
- GKE NetworkPolicy 管理 Pod 级别细粒度策略
- 两者配合使用（纵深防御）

---

## 3. GKE Pod 经由 GCE NAT Gateway 出口

### 3.1 架构说明

```
Pod (100.64.x.x)
  → Node eth0
  → NAT Instance (iptables SNAT)
  → Internet

返回流量自动经由 NAT 实例追踪返回。
```

### 3.2 NAT Instance 上的防火墙规则

NAT 实例需要允许来自 GKE Node 和 Pod 的所有流量转发：

```
# NAT 实例入站规则
gcloud compute firewall-rules create allow-gke-to-nat-ingress \
  --network=vpc \
  --allow=tcp,udp,icmp \
  --source-ranges=10.0.0.0/20,100.64.0.0/14 \
  --target-tags=nat-gateway \
  --direction=INGRESS
```

### 3.3 GKE 节点出站规则

```
# 允许 GKE 节点将流量发送到 NAT 实例
gcloud compute firewall-rules create allow-gke-nodes-to-nat-egress \
  --network=vpc \
  --allow=tcp,udp,icmp \
  --source-tags=gke-nodes \
  --destination-ranges=<NAT_INSTANCE_INTERNAL_IP>/32 \
  --direction=EGRESS
```

### 3.4 NAT Instance iptables 配置

在 NAT 实例上配置 SNAT：

```bash
# 启用 IP forwarding
sysctl -w net.ipv4.ip_forward=1
# 持久化：echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# iptables SNAT 规则（Pod IP → NAT IP）
iptables -t nat -A POSTROUTING -s 100.64.0.0/14 -o eth0 -j SNAT --to-source <NAT_IP>
iptables -t nat -A POSTROUTING -s 10.0.0.0/20 -o eth0 -j SNAT --to-source <NAT_IP>

# 如果需要 DNAT（外部流量进入 Pod）
iptables -t nat -A PREROUTING -i eth0 -d <NAT_IP> -j DNAT --to-destination <POD_IP>
```

### 3.5 Cloud NAT vs 手动 iptables NAT

| 维度          | Cloud NAT          | 手动 iptables NAT         |
| ------------- | ------------------ | ------------------------- |
| 配置复杂度    | 低（一键启用）     | 高（需手动配置 iptables） |
| 日志追踪      | Cloud Logging 集成 | 需自行配置 log            |
| 自动连接追踪  | ✅ 是               | 需额外配置                |
| 端口消耗      | 按连接数计费       | 无额外费用                |
| Pod CIDR 支持 | 原生支持           | 需正确配置 source range   |
| 推荐场景      | 生产环境首选       | 实验/简单场景             |

### 3.6 GKE ip-masquerade-agent 配合

GKE 默认使用 ip-masquerade-agent 将 Pod 流量 SNAT 为节点 IP。如果使用自定义 NAT 网关，需要：

```yaml
# 配置非 masquerade CIDRs，让 Pod 流量走 NAT 网关而非节点 IP
apiVersion: v1
kind: ConfigMap
metadata:
  name: ip-masquerade-config
  namespace: kube-system
data:
  config: |
    nonMasqueradeCIDRs:
      - <CUSTOM_NAT_SUBNET>/24
```

---

## 4. 总结：最佳实践

### 4.1 规则设计原则

1. **最小权限**：默认拒绝，仅允许所需流量
2. **使用 SA 而非 Tag 作为 Target**：
   - SA 与实例绑定关系由 IAM 控制，不易被意外修改
   - Tag 可被 Compute Instance Admin 直接修改
3. **Ingress 优先使用 SA 作为 Source**：
   - 同 VPC 内实例间通信，用 SA 比 IP 更稳定
4. **Egress 始终需要 IP 范围**：
   - 无法用 SA 解耦 destination
   - 配合 FQDN Firewall Policy 或 GKE NetworkPolicy 补充

### 4.2 GKE 场景的特殊性

- **GKE Node**：可用 Firewall Rule 的 target/tag/sa
- **GKE Pod**：Firewall Rule 作用在 Node 层面，不直接作用于 Pod
- **Pod 级别策略**：使用 GKE NetworkPolicy (Calico/GKE Dataplane V2)
- **Service 通信**：通过 ClusterIP/NodePort/LoadBalancer，Firewall Rule 作用于 Node 端口

### 4.3 地址变化应对策略

| 场景           | 解决方案                                                 |
| -------------- | -------------------------------------------------------- |
| IP 频繁变化    | 使用 GKE NetworkPolicy 或 Istio（基于 label/name）       |
| 需要 IP 白名单 | Firewall Policy + FQDN 对象（NGFW Standard）             |
| 混合场景       | VPC Firewall Rule（粗粒度）+ GKE NetworkPolicy（细粒度） |

---

## 5. 参考文档

- [VPC Firewall Rules](https://cloud.google.com/firewall/docs/firewalls)
- [Filter by service account](https://cloud.google.com/vpc/docs/firewalls#service-accounts)
- [GKE Network Policy](https://cloud.google.com/kubernetes-engine/docs/how-to/network-policy)
- [Cloud NAT Documentation](https://cloud.google.com/nat/docs)
