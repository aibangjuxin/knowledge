
# Cross-Project MIG / Backend Service 跨项目调用

这是一个非常实用的架构需求。简短的回答是：**可以，但有前提条件。**

在 GCP 中，这种跨项目（Cross-project）的负载均衡配置主要通过 **Shared VPC（共享 VPC）** 或 **Cross-Project Service Referencing（跨项目服务引用）** 功能来实现。

---

## 方案对比

| 方案 | 复杂度 | 适用场景 | 网络要求 |
|------|--------|----------|----------|
| Shared VPC | 中 | 生产环境，多项目共享网络 | 同一 VPC 内 |
| Cross-Project Service Referencing | 低 | 项目已存在，不想重构网络 | VPC Peering 或 Shared VPC |
| Global External LB + Backend Connection | 低 | 需要跨区域/公网暴露 | 无特殊要求 |

---

## 1. 核心架构：Shared VPC (最推荐)

这是生产环境中最标准做法。你需要在组织（Organization）层面建立一个"宿主项目"（Host Project）来管理网络。

* **项目 A (Host Project):** 管理 VPC、子网和 Internal Load Balancer 的前端（Forwarding Rule）。
* **项目 B (Service Project):** 部署你的 MIG（托管实例组）。
* **如何关联：** 你的 MIG 虽然在项目 B，但它使用的网卡（NIC0）必须连接到项目 A 的共享子网中。这样，项目 A 的 Internal GLB 就可以直接将项目 B 的 MIG 选为后端。

### 适用场景
- 多项目需要共享同一套网络基础设施
- 需要统一的网络策略和防火墙规则
- 对网络隔离有严格要求

---

## 2. 高级方案：Cross-Project Service Referencing

如果你不想用 Shared VPC，或者项目已经存在，Google 现在支持一种更灵活的方式：**跨项目后端服务引用**。

* **原理：** 你可以在 **项目 A** 中创建一个 Load Balancer 的前端和 URL Map，然后让它引用 **项目 B** 里的 `Backend Service`。
* **要求：**
  * 两个项目必须属于同一个 **Organization**。
  * 通常依然需要某种网络连通性（如 VPC Peering 或都在 Shared VPC 内），因为 Internal LB 的流量无法跨越完全隔离的网络。
  * **权限分配：** 你需要授予项目 A 的负载均衡器服务账号（Service Agent）访问项目 B 后端服务的权限：
    * 角色：`roles/compute.loadBalancerServiceUser`

### 权限配置命令

```bash
# 在项目 B 中执行，授予项目 A 的 LB 服务账号权限
PROJECT_A="project-a-id"
PROJECT_B="project-b-id"

# 获取项目 A 的 Compute Engine Service Agent
SERVICE_ACCOUNT="service-${PROJECT_A}@gcp-sa-cloud-lb.iam.gserviceaccount.com"

# 授予跨项目访问权限
gcloud projects add-iam-policy-binding ${PROJECT_B} \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/compute.loadBalancerServiceUser"
```

---

## 3. 替代方案：Global External Load Balancer

如果你的场景允许使用 **External Load Balancer**（可以是内部或外部），可以使用更简单的架构：

- 在 **项目 A** 创建 Global External HTTP(S) Load Balancer
- 在 Backend Service 中引用 **项目 B** 的 Instance Group 或 Network Endpoint Group (NEG)
- 通过 **VPC Peering** 或 **Shared VPC** 实现网络连通

### 配置要点
- 需要 VPC Peering 或 Shared VPC 连接
- 支持 Global 负载均衡（跨区域流量调度）
- 适用于需要公网暴露或跨区域HA的场景

---

## 4. 配置建议与注意事项

| 关注点                | 细节建议                                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------------------- |
| **网络隔离**          | Internal LB 是区域性（Regional）资源，确保项目 A 的 Frontend 和项目 B 的 MIG 在 **同一个 Region**。     |
| **Proxy-only Subnet** | Internal HTTP(S) LB 需要一个专门的代理子网。在 Shared VPC 架构下，这个子网通常定义在 **Host Project**。 |
| **防火墙**            | 你必须在宿主项目中允许来自代理子网（Proxy-only Subnet）的流量进入项目 B 的 MIG。                        |
| **配额消耗**          | 就像我们之前讨论的，URL Map 的字符数限制依然适用。如果跨项目引用过多，建议在命名上保持简洁以节省空间。  |
| **服务账号**          | 确保 LB Service Agent 有跨项目访问后端服务的权限。                                                      |

---

## 5. 实施步骤（以 Shared VPC 为例）

### Step 1: 在组织层面配置 Shared VPC

```bash
# 1. 在 Host Project 开启 Shared VPC
HOST_PROJECT="host-project-id"
gcloud compute shared-vpc enable ${HOST_PROJECT}

# 2. 将 Service Project 关联到 Host Project
SERVICE_PROJECT="service-project-id"
gcloud compute shared-vpc associated-projects add ${SERVICE_PROJECT} \
  --host-project=${HOST_PROJECT}
```

### Step 2: 在 Service Project 创建 MIG

```bash
# 确保 MIG 使用共享子网
gcloud compute instance-groups managed create my-mig \
  --project=${SERVICE_PROJECT} \
  --zone=us-central1-a \
  --template=my-template \
  --size=2 \
  --subnet=projects/${HOST_PROJECT}/regions/us-central1/subnets/my-subnet
```

### Step 3: 在 Host Project 创建 Internal HTTP(S) LB

```bash
# 创建 Backend Service 并引用项目 B 的 MIG
gcloud compute backend-services create my-backend-service \
  --project=${HOST_PROJECT} \
  --load-balancing-scheme=INTERNAL \
  --region=us-central1

# 添加跨项目的后端
gcloud compute backend-services add-backend my-backend-service \
  --project=${HOST_PROJECT} \
  --region=us-central1 \
  --instance-group=projects/${SERVICE_PROJECT}/zones/us-central1-a/instanceGroups/my-mig
```

### Step 4: 配置防火墙规则（关键！）

```bash
# 在 Host Project 中允许 LB 流量
gcloud compute firewall-rules create allow-lb-proxy \
  --project=${HOST_PROJECT} \
  --allow=tcp:80,tcp:443 \
  --source-ranges=<proxy-subnet-cidr> \
  --target-tags=<mig-instance-tag> \
  --network=projects/${HOST_PROJECT}/global/networks/my-vpc
```

---

## 6. 验证步骤

```bash
# 1. 验证 Shared VPC 关联状态
gcloud compute shared-vpc get-host-project ${SERVICE_PROJECT}

# 2. 验证防火墙规则
gcloud compute firewall-rules list --project=${HOST_PROJECT} --filter="network:my-vpc"

# 3. 验证 Backend Service 关联
gcloud compute backend-services describe my-backend-service \
  --project=${HOST_PROJECT} --region=us-central1

# 4. 测试连通性（从项目 A 的 VM）
curl http://<internal-lb-ip>/health
```

---

## 7. 常见问题排查

| 问题 | 可能原因 | 解决方案 |
|------|----------|----------|
| LB 无法发现后端 MIG | MIG 不在共享子网 | 检查 MIG 的网卡配置 |
| 流量无法到达后端 | 防火墙规则未放行 | 检查 Proxy-only Subnet 范围 |
| 403 权限错误 | LB Service Agent 权限不足 | 授予 `roles/compute.loadBalancerServiceUser` |
| 健康检查失败 | 健康检查 IP 未放行 | 添加 `35.191.0.0/16` 和 `130.211.0.0/22` |
