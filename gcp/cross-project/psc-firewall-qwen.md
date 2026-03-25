# Cross Project PSC Firewall 完整指南（增强版）

> 基于官方文档验证的 Cross Project PSC 防火墙设计指南
> 最后更新：2026 年 3 月

---

## 1. Goal and Constraints

### 目标

在 Cross Project 场景下，Consumer Project 通过 PSC 访问 Producer Project 的服务时，准确设计防火墙规则，避免常见误区。

### 核心问题

- Consumer 到 Producer 通过 PSC 通信时，哪些地方需要防火墙配置？
- Producer backend 实际看到的源地址是谁？（PSC NAT subnet vs proxy-only subnet）
- 不同 LB 类型对应的防火墙设计有何区别？
- Health check 的源地址范围是什么？

### 适用范围

- Cross Project PSC 通信
- GKE Gateway (`gke-l7-rilb`)
- Internal Application Load Balancer
- Internal Passthrough Network Load Balancer
- Shared VPC 场景

---

## 2. Executive Summary

### 最核心结论

**不要把 PSC endpoint、service attachment、producer LB frontend 都当成"需要单独开防火墙的网卡"。**

### 判断框架

```
┌─────────────────────────────────────────────────────────────────┐
│                    防火墙设计判断框架                            │
├─────────────────────────────────────────────────────────────────┤
│ 1. Consumer 侧：允许 workload 出站到 PSC endpoint VIP            │
│ 2. Producer 侧：backend ingress 允许真实流量来源                 │
│    - Passthrough 类 LB → 允许 PSC NAT subnet                     │
│    - Proxy/Envoy 类 LB → 允许 proxy-only subnet                  │
│ 3. Health check：允许 Google health check probe ranges          │
└─────────────────────────────────────────────────────────────────┘
```

### 一句话版本

- `PSC endpoint ↔ service attachment ↔ LB frontend` 这段链路**通常不需要手动开防火墙**
- **真正要开的是 Producer backend 的 ingress allow**
- 放通谁取决于 LB 类型：
  - **Passthrough 类**：允许 **PSC NAT subnet** (`PSC NAT subnet CIDR`)
  - **Proxy/Envoy 类**：允许 **proxy-only subnet** (`proxy-only subnet CIDR`)
- 如果有 health check，还必须允许 **health check probe ranges**

---

## 3. 官方边界：哪些地方不需要单独开防火墙

根据 Google Cloud 官方 PSC producer 文档明确说明：

### 不需要配置防火墙的场景

| 链路段 | 原因 |
|--------|------|
| PSC endpoint ↔ Service attachment | 这些是逻辑组件，不参与实际流量传输 |
| Service attachment ↔ Load balancer frontend | 同上 |
| Load balancer frontend ↔ Backend (仅指 LB 内部转发) | LB 内部转发由 GCP 管理 |

### 需要配置防火墙的场景

| 链路段 | 配置位置 | 说明 |
|--------|----------|------|
| Consumer workload → PSC endpoint VIP | Consumer VPC egress | 确保 workload 可以出站访问 |
| LB/Proxy → Backend | Producer VPC ingress | 确保 backend 允许真实流量来源 |
| Health check probes → Backend | Producer VPC ingress | 确保健康检查可以通过 |

**参考文档：**
- [Publish services by using Private Service Connect](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer)

---

## 4. 关键判断点：Producer 发布的是什么类型的服务

这是整个防火墙设计的**分水岭**。

### 4.1 类型判断表（官方验证版）

| Producer 服务类型 | 典型底层资源 | Backend 看到的 Source | 防火墙重点 |
|------------------|-------------|----------------------|-----------|
| **Internal Passthrough NLB** | Forwarding rule + Backend service | `PSC NAT subnet CIDR` | 放通 PSC NAT subnet |
| **Internal Protocol Forwarding** | Forwarding rule (透传类) | `PSC NAT subnet CIDR` | 放通 PSC NAT subnet |
| **Port Mapping Service** | 端口映射服务 | `PSC NAT subnet CIDR` | 放通 PSC NAT subnet |
| **Regional Internal ALB** | Target HTTP/HTTPS proxy + URL map | `proxy-only subnet CIDR` | 放通 proxy-only subnet |
| **Cross-region Internal ALB** | Target HTTP/HTTPS proxy + URL map | `proxy-only subnet CIDR` | 放通 proxy-only subnet |
| **Regional Internal Proxy NLB** | Target TCP/SSL proxy + Backend service | `proxy-only subnet CIDR` | 放通 proxy-only subnet |
| **GKE Internal Gateway (`gke-l7-rilb`)** | Internal ALB + Gateway controller | `proxy-only subnet CIDR` | 放通 proxy-only subnet |
| **Secure Web Proxy** | Proxy service | `proxy-only subnet CIDR` | 放通 proxy-only subnet |

### 4.2 快速判断法则

**看到这些特征 → Proxy/Envoy 类：**
- `target HTTP/HTTPS/TCP/SSL proxy`
- `URL map`
- `proxy-only subnet`
- GKE Gateway (`gke-l7-rilb`)

**看到这些特征 → Passthrough 类：**
- Forwarding rule 直接连 Backend service
- 没有 target proxy
- 没有 URL map
- 没有 proxy-only subnet

### 4.3 实战判断路径

#### 路径 1：从 Service Attachment 出发

```bash
# 1. 查看 service attachment 指向的 target service
gcloud compute service-attachments describe SERVICE_ATTACHMENT \
  --region=REGION \
  --project=PRODUCER_PROJECT

# 2. 如果 targetService 是 forwarding rule，继续查看
gcloud compute forwarding-rules describe FORWARDING_RULE \
  --region=REGION \
  --project=PRODUCER_PROJECT
```

**关键字段判断：**
- 有 `target: ...targetHttpProxies/...` → **Proxy 类**
- 直接 `backendService` 无 target proxy → **Passthrough 类**

#### 路径 2：从 Subnet 反推

```bash
# 查看是否有 proxy-only subnet
gcloud compute networks subnets list \
  --project=PRODUCER_PROJECT \
  --filter='purpose="REGIONAL_MANAGED_PROXY" OR purpose="INTERNAL_HTTPS_LOAD_BALANCER"'
```

如果存在 proxy-only subnet，通常说明使用 **Proxy/Envoy 类 LB**。

---

## 5. Health Check Probe Ranges（官方完整版）

### 5.1 IPv4 Health Check Ranges

**通用范围（大多数 LB）：**
```
35.191.0.0/16
130.211.0.0/22
```

**Regional External Passthrough NLB 特殊范围：**
```
35.191.0.0/16
209.85.152.0/22
209.85.204.0/22
```

### 5.2 IPv6 Health Check Ranges

| LB 类型 | IPv6 范围 |
|--------|----------|
| Global External Application LB | `2600:2d00:1:b029::/64`<br>`2600:2d00:1:1::/64` |
| Global External Proxy Network LB | `2600:2d00:1:b029::/64`<br>`2600:2d00:1:1::/64` |
| Regional External Passthrough Network LB | `2600:1901:8001::/48` |
| Internal Passthrough Network LB | `2600:2d00:1:b029::/64` |

### 5.3 GKE 场景的 Health Check 来源

**GKE Gateway / Ingress Controller 创建的规则来源：**
```
35.191.0.0/16
130.211.0.0/22
209.85.152.0/22  (仅 Ingress)
209.85.204.0/22  (仅 Ingress)
Proxy-only subnet CIDR (Internal ALB)
```

**参考文档：**
- [Firewall rules for Cloud Load Balancing](https://cloud.google.com/load-balancing/docs/firewall-rules)

---

## 6. Consumer 侧防火墙检查清单

### 6.1 Workload 到 PSC endpoint VIP 的 Egress

**检查点：**
- Consumer workload 可以访问 PSC endpoint VIP
- 对应端口已允许（如 `80` / `443`）

**注意：** VPC firewall rules 作用在 VM/NIC 上，不是作用在 forwarding rule 本身。

### 6.2 GKE / Kubernetes 额外限制

如果 Consumer 是 GKE workload，还要检查：

| 检查项 | 说明 |
|--------|------|
| Kubernetes NetworkPolicy | 是否限制 egress |
| Sidecar / Mesh policy | 是否限制外呼 |
| 节点级 egress firewall | 是否有 deny 规则 |

### 6.3 DNS 配置

如果走 Private DNS zone 或 Response Policy，确认：
- Consumer 侧能够正常解析 FQDN 到 PSC endpoint IP
- DNS 解析指向正确的 PSC endpoint VIP

---

## 7. Producer 侧防火墙检查清单

### 7.1 Service Attachment 准入控制

虽然不是 VPC firewall rule，但要检查：
- 自动批准还是手动批准
- Accept list / Reject list
- 是否允许对应 Consumer project / network / endpoint 连接

### 7.2 Backend Ingress Allow 规则

**根据 LB 类型设计：**

#### Passthrough 类 LB
```
允许：
  Source: PSC NAT subnet CIDR
  Destination: backend app port

允许（如有 health check）：
  Source: health check probe ranges
  Destination: health check port
```

#### Proxy/Envoy 类 LB
```
允许：
  Source: proxy-only subnet CIDR
  Destination: backend app port

允许（如有 health check）：
  Source: health check probe ranges
  Destination: health check port
```

### 7.3 如果 Backend 是 GCE VM

重点检查：
- VPC ingress firewall rule
- Target tags / target service accounts
- 业务端口是否和 backend service / named port 一致
- Health check 端口是否真的在监听

### 7.4 如果 Backend 是 GKE / NEG / Gateway

重点检查：
- Proxy-only subnet 是否已配置
- GKE Gateway / Ingress 是否自动创建了相关 firewall rule
- Shared VPC / 受限权限场景下，controller 是否有权限改防火墙
- 是否有组织级 / hierarchical firewall policy 覆盖掉 allow 规则

**GKE Gateway 自动创建的规则：**
```
规则名称：gkegw1-l7-[network]-[region/global]
来源：
  - 35.191.0.0/16
  - 130.211.0.0/22
  - Proxy-only subnet (Internal ALB)
目标：节点标记
端口：所有容器目标端口
```

**参考文档：**
- [GKE automatically created firewall rules](https://cloud.google.com/kubernetes-engine/docs/concepts/firewall-rules)

---

## 8. GKE Gateway / Internal ALB 的特殊点

### 8.1 真正访问 backend 的是 proxy-only subnet

对于 Internal Application LB / GKE Gateway (`gke-l7-rilb`)：
- 后端看到的来源是 **proxy-only subnet**
- 不是 Gateway VIP
- 不是 PSC endpoint IP
- 通常也不是原始 Consumer IP

### 8.2 Proxy-only Subnet 配置要求

**创建命令：**
```bash
gcloud compute networks subnets create SUBNET_NAME \
    --purpose=REGIONAL_MANAGED_PROXY \
    --role=ACTIVE \
    --region=COMPUTE_REGION \
    --network=VPC_NETWORK_NAME \
    --range=CIDR_RANGE
```

**关键要求：**
| 要求项 | 具体说明 |
|--------|----------|
| Purpose | `REGIONAL_MANAGED_PROXY` (不支持旧的 `INTERNAL_HTTPS_LOAD_BALANCER`) |
| 子网掩码 | 不能超过 `/26` (至少 64 个 IP) |
| 推荐掩码 | `/23` |
| 覆盖范围 | 每个使用内部/区域 LB 的区域都需要一个 |

### 8.3 GKE Gateway 防火墙规则验证

```bash
# 查看 Gateway controller 创建的防火墙规则
gcloud compute firewall-rules list \
  --project=PRODUCER_PROJECT \
  --filter='name~"gkegw1-l7"'

# 查看规则详情
gcloud compute firewall-rules describe RULE_NAME \
  --project=PRODUCER_PROJECT
```

**验证要点：**
- 规则是否真的创建成功
- Shared VPC / 受限权限场景下是否失败
- 是否被更高优先级 firewall policy 覆盖

**参考文档：**
- [Deploying Gateways](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)

---

## 9. Cross Project 下最常见的误区

| 误区 | 正确理解 |
|------|----------|
| **误区 1：我要开放 PSC endpoint IP** | PSC endpoint 是 Consumer 侧 VIP，不是 backend NIC，通常不需要这样开 |
| **误区 2：Service Attachment 和 LB 之间要单独开防火墙** | 官方明确不需要，这些是逻辑组件 |
| **误区 3：只开放 PSC NAT subnet 一定没问题** | 只有 passthrough 类服务才成立；Internal ALB/Gateway 需要开放 proxy-only subnet |
| **误区 4：只要 Producer 放通就够了** | Consumer 侧的 egress policy、NetworkPolicy、mesh policy 也可能挡住 |
| **误区 5：健康检查和真实业务流量来源一定一样** | Health check 来自 Google probe IP ranges，和业务流量来源不同 |
| **误区 6：Backend 看到的是 Consumer 原始 IP** | 通常看到的是 PSC NAT subnet 或 proxy-only subnet（经过 NAT） |

---

## 10. 完整检查清单

### 10.1 Consumer 侧

- [ ] Workload 能解析到正确 PSC endpoint FQDN / VIP
- [ ] Workload 出站到 PSC endpoint VIP:port 没被 deny
- [ ] 如果是 GKE，NetworkPolicy / mesh egress 没挡住
- [ ] 组织级 egress firewall / hierarchical policy 没挡住

### 10.2 Producer 侧

- [ ] Service attachment 已批准对应 consumer
- [ ] PSC NAT subnet 已配置，容量足够
- [ ] 确认发布的 producer service 类型（passthrough vs proxy）
- [ ] Backend ingress 防火墙开放的来源地址正确
- [ ] Health check ranges 已放行
- [ ] 没有更高优先级 deny policy 覆盖

### 10.3 GKE Gateway / Internal ALB

- [ ] Proxy-only subnet 存在且 region 正确
- [ ] Backend 放行 proxy-only subnet
- [ ] Health check ranges 已允许
- [ ] Gateway controller 创建的 firewall rules 存在且生效
- [ ] Shared VPC 场景下 controller 有足够权限

---

## 11. Validation / Debug 命令

### 11.1 查看 Service Attachment

```bash
gcloud compute service-attachments describe SERVICE_ATTACHMENT \
  --region=REGION \
  --project=PRODUCER_PROJECT
```

**关注字段：**
- `connectedEndpoints`
- `natSubnets`
- `targetService`
- approval / accept 配置

### 11.2 查看 Forwarding Rule / LB 类型

```bash
gcloud compute forwarding-rules describe FORWARDING_RULE \
  --region=REGION \
  --project=PRODUCER_PROJECT
```

**关注字段：**
- `loadBalancingScheme`
- `target` (是否有 target proxy)
- `backendService`
- `region` / `global`

### 11.3 查看 Producer 防火墙

```bash
gcloud compute firewall-rules list \
  --project=PRODUCER_PROJECT \
  --format='table(name,sourceRanges,targetTags,allowed)'
```

**核对要点：**
- Source ranges 是否正确
- Target tags / service accounts 是否匹配
- Destination ports 是否正确
- Priority 是否合理

### 11.4 查看 Proxy-only Subnet

```bash
gcloud compute networks subnets list \
  --project=PRODUCER_PROJECT \
  --filter='purpose="REGIONAL_MANAGED_PROXY" OR purpose="INTERNAL_HTTPS_LOAD_BALANCER"'
```

### 11.5 查看 GKE Gateway 防火墙

```bash
gcloud compute firewall-rules list \
  --project=PRODUCER_PROJECT \
  --filter='name~"gkegw1-l7"'
```

### 11.6 查看高层策略覆盖

```bash
# 查看组织级 firewall policy
gcloud resource-manager firewall-policies list

# 查看规则是否被覆盖
gcloud resource-manager firewall-policies rules list \
  --firewall-policy=POLICY_NAME
```

---

## 12. 推荐实施流程

### Step 1: 确认 LB 类型

```bash
# 从 Service Attachment 找到 target service
gcloud compute service-attachments describe SERVICE_ATTACHMENT \
  --region=REGION \
  --project=PRODUCER_PROJECT

# 查看 forwarding rule 详情
gcloud compute forwarding-rules describe FORWARDING_RULE \
  --region=REGION \
  --project=PRODUCER_PROJECT
```

### Step 2: 确认源地址范围

```bash
# Passthrough 类：查看 PSC NAT subnet
gcloud compute service-attachments describe SERVICE_ATTACHMENT \
  --region=REGION \
  --project=PRODUCER_PROJECT \
  --format='value(natSubnets)'

# Proxy 类：查看 proxy-only subnet
gcloud compute networks subnets list \
  --project=PRODUCER_PROJECT \
  --filter='purpose="REGIONAL_MANAGED_PROXY"' \
  --format='table(name,ipCidrRange,region)'
```

### Step 3: 设计防火墙规则

```bash
# Passthrough 类示例
gcloud compute firewall-rules create ALLOW_PSC_TO_BACKEND \
  --project=PRODUCER_PROJECT \
  --network=NETWORK_NAME \
  --source-ranges=PSC_NAT_SUBNET_CIDR \
  --target-tags=BACKEND_TAG \
  --rules=tcp:APP_PORT

# Proxy 类示例
gcloud compute firewall-rules create ALLOW_PROXY_TO_BACKEND \
  --project=PRODUCER_PROJECT \
  --network=NETWORK_NAME \
  --source-ranges=PROXY_ONLY_SUBNET_CIDR \
  --target-tags=BACKEND_TAG \
  --rules=tcp:APP_PORT

# Health check 规则示例
gcloud compute firewall-rules create ALLOW_HEALTH_CHECK \
  --project=PRODUCER_PROJECT \
  --network=NETWORK_NAME \
  --source-ranges=35.191.0.0/16,130.211.0.0/22 \
  --target-tags=BACKEND_TAG \
  --rules=tcp:HEALTH_CHECK_PORT
```

### Step 4: 验证连通性

```bash
# 从 Consumer 侧测试
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never \
  -- curl -v http://PSC_ENDPOINT_VIP

# 查看 Service Attachment 连接状态
gcloud compute service-attachments describe SERVICE_ATTACHMENT \
  --region=REGION \
  --format='value(connectionPreference)'
```

---

## 13. 最终落地建议

### 防火墙设计原则

1. **先分类，后设计**：先确认 LB 类型，再决定放通谁
2. **最小权限**：只放通真实流量来源，不要过度开放
3. **分层验证**：Consumer egress → Producer ingress → Health check
4. **自动化优先**：GKE Gateway 等尽量利用自动创建的规则

### 快速决策表

| 场景 | 放通来源 | 额外注意 |
|------|---------|---------|
| Internal Passthrough NLB | PSC NAT subnet | 确认 natSubnets CIDR |
| Internal ALB / Gateway | Proxy-only subnet | 确认 proxy-only subnet 存在 |
| 有 Health Check | Health check ranges | 35.191.0.0/16, 130.211.0.0/22 等 |
| GKE Backend | 确认自动规则 | 验证 gkegw1-l7-* 规则存在 |

### 常见排障路径

```
连通性问题
    ↓
1. Consumer 侧能否访问 PSC endpoint VIP?
    ├─ 否 → 检查 Consumer egress firewall / NetworkPolicy
    └─ 是 → 继续
    ↓
2. Service Attachment 是否批准 Consumer?
    ├─ 否 → 检查 approval 配置
    └─ 是 → 继续
    ↓
3. Producer backend 是否收到流量?
    ├─ 否 → 检查 Producer ingress firewall (PSC NAT vs proxy-only)
    └─ 是 → 继续
    ↓
4. Health check 是否通过?
    ├─ 否 → 检查 health check ranges 是否放行
    └─ 是 → 问题可能在应用层
```

---

## 14. One-line Conclusion

**Cross Project PSC 场景下，防火墙设计的关键不是"给 PSC 开洞"，而是准确识别 Producer backend 实际看到的源地址（PSC NAT subnet、proxy-only subnet 或 health check probes），然后只对这些真实来源做最小放通。**

---

## 15. References

### 核心文档

- [Publish services by using Private Service Connect](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer)
- [Firewall rules for Cloud Load Balancing](https://cloud.google.com/load-balancing/docs/firewall-rules)
- [Internal Application Load Balancer overview](https://cloud.google.com/load-balancing/docs/l7-internal)

### GKE 相关

- [GKE automatically created firewall rules](https://cloud.google.com/kubernetes-engine/docs/concepts/firewall-rules)
- [Deploying Gateways](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)

### 补充文档

- [Make the service accessible from other VPC networks](https://cloud.google.com/vpc/docs/make-service-accessible-other-vpc-networks)

---

## Appendix A: 完整源地址范围速查表

| 用途 | IPv4 范围 | 说明 |
|------|----------|------|
| **Health Check (通用)** | `35.191.0.0/16`<br>`130.211.0.0/22` | 大多数 LB 的健康检查 |
| **Health Check (Regional External Passthrough)** | `35.191.0.0/16`<br>`209.85.152.0/22`<br>`209.85.204.0/22` | Regional External Passthrough NLB |
| **Health Check (IPv6)** | `2600:2d00:1:b029::/64`<br>`2600:2d00:1:1::/64` | Global External ALB / Proxy NLB |
| **PSC NAT Subnet** | 用户定义 | Passthrough 类 LB 的 backend source |
| **Proxy-only Subnet** | 用户定义 | Proxy 类 LB 的 backend source |
| **GFE Proxy (Global LB)** | 从 `_cloud-eoips.googleusercontent.com` DNS TXT 获取 | Global External ALB 的 backend source |

---

## Appendix B: 文档版本历史

| 版本 | 日期 | 更新内容 |
|------|------|----------|
| v1.0 | 2026-03-25 | 基于官方文档验证的完整版本 |
| - | - | 更新了完整的 health check probe ranges |
| - | - | 补充了 GKE Gateway 防火墙规则细节 |
| - | - | 添加了 IPv6 health check 范围 |
| - | - | 完善了 LB 类型判断表和实战命令 |
