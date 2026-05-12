# GKE Gateway API 配额限制分析

## 结论

GKE Gateway API 的部署数量**没有直接的 Gateway 个数配额**，真正的限制来自底层 GCP Load Balancer 资源配额，其中**最核心的是 `FORWARDING_RULES`（转发规则）配额**。

---

## 限制层级

```
GKE Gateway 资源
    │
    ▼
GCP Load Balancer（全球外部 / 区域内部 HTTP(S) LB）
    │
    ├── Forwarding Rules（转发规则）  ← 主要瓶颈
    ├── Backend Services（后端服务）
    ├── URL Maps（URL 映射）
    ├── SSL Certificates（SSL 证书）
    ├── Target Proxies（目标代理）
    │
    ▼
Subnet IP 地址（Pod IP / Node IP）
    │
    ▼
GCP Region Quota（区域配额）
```

### 1. Forwarding Rules（转发规则）— **最关键限制**

| Gateway 类型 | 底层 LB 类型 | 每个 Gateway 消耗的转发规则数 |
|---|---|---|
| `gke-l7-gxlb`（外部全局 HTTP(S) LB） | 全球外部 HTTP(S) LB | **每个 listener 1 条**，典型 Gateway 有 2 个 listener（HTTP+HTTPS）= 2 条 |
| `gke-l7-rilb`（内部区域 HTTP(S) LB） | 区域内部 HTTP(S) LB | 同上，每个 listener 1 条 |
| `gke-l7-gxlb-mc`（多集群外部全局 LB） | 全球外部 HTTP(S) LB | 同上 |
| `gke-l7-rilb-mc`（多集群内部区域 LB） | 区域内部 HTTP(S) LB | 同上 |

**默认配额**：每个 region **1,000 条**转发规则（可申请提升）
**计算公式**：`最大 Gateway 数 ≈ 配额上限 / 每 Gateway listener 数`

### 2. Backend Services（后端服务）

每个 Gateway 的后端会创建 Backend Service：
- **默认配额**：每个 project **100 个**（可申请提升）
- 如果 Gateway 绑定多个 HTTPRoute 且配置了不同后端，消耗更多

### 3. URL Maps

每个 HTTP(S) LB 使用 1 个 URL Map：
- **默认配额**：每个 project **100 个**（可申请提升）
- 与 Backend Services 配额联动

### 4. SSL 证书

HTTPS listener 需要 SSL 证书：
- Google 托管证书：**默认 100 个**（可申请提升）
- 证书按域名数量计，每域名算 1 个配额

### 5. Subnet / IP 地址（PSC 场景）

使用 Private Service Connect（PSC）时：
- 每个 PSC endpoint 占用 **1 个内部 IP**（`IN_USE_ADDRESSES` 配额）
- **默认配额**：每个 region **8000 个** IP（可申请提升）
- 如果 Gateway 使用 NEG（网络端点组），还受 NEG 数量限制

---

## 与 Subnet 的关系

### GKE Pod IP 消耗

| 配置项 | 说明 |
|---|---|
| **Secondary Range for Pods** | 决定集群可分配的 Pod IP 总数 |
| **Pod IP 池大小** | 例如 `/14` 掩码 = 约 262,144 个 IP |
| **每 Node Pod 数量** | GKE 默认每 Node 最多 110 个 Pod |
| **节点数量** | 影响总 Pod IP 需求量 |

Gateway 本身**不直接消耗 Pod IP**，但如果：
- Gateway 绑定的 Backend Service 后端是 **ClusterIP Service**
- GKE 使用 ** VPC-native** 网络模式（而非 routes-based）

则集群 Pod 规模受 Subnet secondary range 大小限制。

### PSC / Internal LB 场景

内部 HTTP(S) LB 会分配 **内部转发 IP**：
- 每个 listener 分配 1 个内部 IP
- **消耗的是 Subnet IP 范围**，不是 Pod IP 池
- 需要确保 Subnet 有足够的可用 IP 空间

---

## 实际部署建议数量

### 保守估算（默认值）

| 配额项 | 默认上限 | 每 Gateway 消耗 | **估算最大 Gateway 数** |
|---|---|---|---|
| Forwarding Rules | 1,000 / region | 2 条（HTTP+HTTPS） | **~500 个** |
| Backend Services | 100 / project | 1 条 | **~100 个** |
| URL Maps | 100 / project | 1 条 | **~100 个** |
| Google Managed SSL Certs | 100 / project | 1 条（可选） | **~100 个** |

> ⚠️ **瓶颈在 Backend Services 和 URL Maps（默认 100 个）**，约 100 个 Gateway 就可能触及配额。

### 申请提升配额后的估算

| 配额项 | 可申请上限 | 每 Gateway 消耗 | **估算最大 Gateway 数** |
|---|---|---|---|
| Forwarding Rules | 2,000~10,000 / region | 2 条 | **1,000~5,000 个** |
| Backend Services | 500~2,000 / project | 1 条 | **500~2,000 个** |
| URL Maps | 500~2,000 / project | 1 条 | **500~2,000 个** |

---

## 查看实际配额

```bash
# 查看当前项目所有配额
gcloud compute project-info describe --project <PROJECT_ID>

# 查看特定 region 的配额
gcloud compute regions describe <REGION> --project <PROJECT_ID>

# 过滤查看 FORWARDING_RULES 配额
gcloud compute regions describe <REGION> \
  --project <PROJECT_ID> \
  --flatten="quotas[]" \
  --filter="quota:FORWARDING_RULES"

# 查看已使用的转发规则数量
gcloud compute forwarding-rules list \
  --regions=<REGION> \
  --project=<PROJECT_ID> \
  --format="value(name)" | wc -l
```

---

## 配额申请

如果配额不足，通过以下方式申请提升：

1. **Google Cloud Console** → IAM & Admin → Quotas → 选择服务 → "Edit Quotas"
2. **支持案例**：提交 GCP 支持案例，说明业务需求
3. **预计审批时间**：1-3 个工作日

---

## 最佳实践

1. **单集群多 Gateway 复用**：一个 Gateway 可绑定多个 HTTPRoute，路由规则复用同一个 LB 资源
2. **合并 listener**：将多个服务合并到同一 Gateway，减少资源消耗
3. **监控配额使用**：设置 Cloud Monitoring 告警，在配额使用达 80% 时预警
4. **多 region 部署**：如果单 region 配额不够，考虑跨 region 部署

---

## 参考资料

- [GKE Gateway API 文档](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api)
- [GCP 配额管理](https://cloud.google.com/docs/quotas)
- [HTTP(S) Load Balancing 配额](https://cloud.google.com/load-balancing/docs/quotas)
- [VPC 配额](https://cloud.google.com/vpc/docs/quota)
