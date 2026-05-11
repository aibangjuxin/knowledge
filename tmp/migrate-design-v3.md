# 1.0 到 2.0 架构迁移最终设计

## 1. 目标与约束

本文档定义 1.0 到 2.0 的最终迁移方案。目标是在既有生产 VPC 内引入 2.0 架构能力，让新用户直接进入 2.0，老用户继续稳定运行并按节奏迁移。

核心目标：

- 1.0 老用户零停机。
- 2.0 新用户不再进入 1.0 架构。
- GCE/MIG 与 GKE 网络保持明确隔离。
- 保留既有 VPC，降低 MIG refresh、CI/CD、DNS、firewall、GCE 到 GKE 链路的改造量。
- 首期使用 Cloud Service Mesh / Istio API，后续保留迁移 Gloo Mesh 的空间。

核心约束：

| 约束 | 说明 |
|---|---|
| 生产优先 | 1.0 不因 2.0 引入而中断 |
| 同 VPC 共存 | 2.0 首期不新建 VPC，在既有生产 VPC 中扩展 |
| 网络隔离 | GCE subnet、GKE Node subnet、Pod secondary range、Service secondary range 分层隔离 |
| IP 不重叠 | 2.0 所有新建 Node/Pod/Service/Control Plane/PSC CIDR 不与 1.0 重叠 |
| 可回滚 | 新用户 onboarding、入口切流、mesh policy 都必须有明确回滚点 |

---

## 2. 推荐架构

推荐方案：

```text
Same GCP Project
  └─ Same Production VPC
      ├─ 1.0 GKE cluster
      │    ├─ 继续服务老用户
      │    └─ 网络与 workload 保持不变
      │
      └─ 2.0 GKE clusters
           ├─ 从 cluster-03 开始创建
           ├─ Node 使用原 2.0 cluster-03+ 规划
           ├─ Pod 使用新的 100.72.0.0/14 地址池
           ├─ Service 使用新的 100.76.0.0/14 地址池
           ├─ PSC NAT 使用 192.168.240.0/20 地址池
           └─ 入口使用 PSC + ILB + Mesh Gateway
```

复杂度：**Moderate**  
推荐度：**高**  
关键前提：**2.0 Pod/Service CIDR 重新规划，并通过企业 IPAM 审批。**

### 2.1 流量路径

```text
Tenant Project
  -> PSC Endpoint
  -> Master Project Service Attachment
  -> Internal Load Balancer
  -> Cloud Service Mesh / Istio Gateway
  -> 2.0 Runtime Workloads
```

| 场景 | 推荐路径 | 说明 |
|---|---|---|
| 新 tenant 进入 2.0 | Tenant PSC Endpoint -> Service Attachment -> ILB -> Mesh Gateway -> Runtime | 新用户直接进入 2.0 |
| 1.0 老用户保持现状 | Existing entry -> 1.0 GCE/GKE | 老用户无感知 |
| 老用户迁移到 2.0 | 在入口层按 tenant/backend 切到 2.0 PSC/ILB | 优先入口层切流 |
| 2.0 内部灰度 | Mesh Gateway / VirtualService / HTTPRoute 权重 | 仅用于 2.0 内部版本灰度 |

### 2.2 为什么选择同 VPC 方案

| 原因 | 好处 |
|---|---|
| 不新建 VPC | 减少 MIG refresh、CI/CD、DNS、firewall、CI runner 的改造量 |
| 1.0 零改动 | 既有 GKE、Pod/Service CIDR、老用户入口不动 |
| 网络模型延续 | GCE components 到 GKE ingress 的现有链路仍在同一 VPC 内治理 |
| IP 冲突可通过重规划解决 | Node/Control Plane 从 cluster-03 开始，Pod/Service 使用新地址池 |
| 2.0 尚无真实用户 | 当前重建或调整 2.0 测试集群的业务影响最低 |
| 安全边界仍清晰 | 同 VPC 不等于同 subnet，GCE 与 GKE 仍通过 subnet、secondary range、policy 隔离 |

---

## 3. 现有 1.0 网络基线

| 类型 | 1.0 网段 | 说明 |
|---|---|---|
| GKE Node | `192.168.64.0/19` | 覆盖 `192.168.64.0 - 192.168.95.255` |
| GKE Pod | `100.64.0.0/14` | 覆盖 `100.64.0.0 - 100.67.255.255` |
| GKE Service | `100.68.0.0/17` | 覆盖 `100.68.0.0 - 100.68.127.255` |
| GKE Control Plane | `192.168.224.0/28` | 1.0 private control plane CIDR |

这些网段在 1.0 退役前不可复用。

---

## 4. 2.0 IPAM 规划

### 4.1 地址池

| 用途 | 地址池 | 分配方式 | 说明 |
|---|---|---|---|
| GKE Node | `192.168.96.0/20` 起 | 每 cluster 一个 `/20` | 从 cluster-03 开始，避开 1.0 Node `/19` |
| GKE Pod | `100.72.0.0/14` | 每 cluster 一个 `/18` | 避开 1.0 Pod `100.64.0.0/14` |
| GKE Service | `100.76.0.0/14` | 每 cluster 一个 `/18` | 避开 1.0 Service `100.68.0.0/17` |
| GKE Control Plane | `192.168.224.64/28` 起 | 每 cluster 一个 `/28` | 从 cluster-03 开始，避开 1.0 control plane `/28` |
| PSC NAT | `192.168.240.0/20` | 按 attachment 拆 `/26` | 用于 PSC producer NAT subnet |

### 4.2 cluster-03 到 cluster-10 分配表

| Cluster | Node subnet | Pod secondary range | Service secondary range | Control plane CIDR |
|---|---|---|---|---|
| cluster-03 | `192.168.96.0/20` | `100.72.0.0/18` | `100.76.0.0/18` | `192.168.224.64/28` |
| cluster-04 | `192.168.112.0/20` | `100.72.64.0/18` | `100.76.64.0/18` | `192.168.224.96/28` |
| cluster-05 | `192.168.128.0/20` | `100.72.128.0/18` | `100.76.128.0/18` | `192.168.224.128/28` |
| cluster-06 | `192.168.144.0/20` | `100.72.192.0/18` | `100.76.192.0/18` | `192.168.224.160/28` |
| cluster-07 | `192.168.160.0/20` | `100.73.0.0/18` | `100.77.0.0/18` | `192.168.224.192/28` |
| cluster-08 | `192.168.176.0/20` | `100.73.64.0/18` | `100.77.64.0/18` | `192.168.224.224/28` |
| cluster-09 | `192.168.192.0/20` | `100.73.128.0/18` | `100.77.128.0/18` | `192.168.225.0/28` |
| cluster-10 | `192.168.208.0/20` | `100.73.192.0/18` | `100.77.192.0/18` | `192.168.225.32/28` |

说明：

- `100.72.0.0/14` 可切 16 个 `/18`，当前只使用 8 个。
- `100.76.0.0/14` 可切 16 个 `/18`，当前只使用 8 个。
- cluster-01/02 暂时保留编号空洞，等 1.0 退役后再决定是否回填。
- GKE private control plane 创建参数使用 `/28`；如需内部管理对齐，可以按 `/27` 作为规划预留块，但不要直接把 `/27` 当作创建参数。

### 4.3 PSC NAT 子网

| 子网名称 | 用途 | CIDR | 可用 IP 规模 |
|---|---|---|---|
| `cinternal-vpc1-${REGION}-abjx-psc-int-ingress-03` | 内部 ingress | `192.168.240.0/26` | 约 60 个 |
| `cinternal-vpc1-${REGION}-abjx-psc-ext-ingress-03` | 外部 ingress | `192.168.240.64/26` | 约 60 个 |
| 后续 attachment | 扩展 | `192.168.240.128/26` 起 | 按需扩展 |

PSC NAT IP 按 connected endpoint/backend 消耗，不按单个 TCP 连接数消耗。需要监控 PSC producer NAT IP 使用量，避免 attachment 扩展后地址不足。

---

## 5. 2.0 测试环境 CIDR 调整策略

如果当前 2.0 测试环境已经创建过 cluster，但还没有真实用户，推荐直接重建测试 cluster，而不是尝试只重启 Deployment。

| 对象 | 处理建议 | 原因 |
|---|---|---|
| Cluster default Pod range | 重建 cluster 最干净 | 默认 Pod range 是 cluster IPAM 基线 |
| Existing node pool Pod range | 不做原地替换 | node pool 的 Pod range 是创建时绑定的 |
| Service range | 按重建 cluster 处理 | Service ClusterIP 范围属于 cluster 级基础设置 |
| Deployment/Pod | 重启不足以完成 CIDR 切换 | Pod 只会从所在 node pool 的 Pod range 获取 IP |

推荐动作：

1. 保留现有测试环境配置作为参考。
2. 创建新的 subnet secondary ranges。
3. 用新 Pod/Service ranges 重建 cluster-03。
4. 重新安装 Cloud Service Mesh、Gateway、基础策略。
5. 重新跑 onboarding pipeline。
6. 重新部署测试应用。
7. 验证 PSC、ILB、Mesh Gateway、AuthorizationPolicy、NetworkPolicy、DNS、日志和监控。

可选方案：如果必须保留已创建 cluster，可以添加 additional Pod range，再新建 node pool 并迁移 workload。但这只解决 Pod range，不解决 Service range 的整体替换问题，因此不作为首选。

---

## 6. 实施计划

### Phase 0：设计冻结与 IPAM 审批

目标：冻结同 VPC 下的 2.0 网络基线。

交付物：

- [ ] Pod 池 `100.72.0.0/14` 通过企业 IPAM 审批。
- [ ] Service 池 `100.76.0.0/14` 通过企业 IPAM 审批。
- [ ] cluster-03+ 的 Node subnet、secondary ranges、control plane CIDR 命名冻结。
- [ ] PSC NAT subnet 容量模型确认。
- [ ] 首期 mesh 选型确认：Cloud Service Mesh / Istio API。
- [ ] CI/CD、onboarding、MIG refresh 的 target 参数模型确认。

### Phase 1：创建 subnet 与 secondary ranges

cluster-03 示例：

```bash
gcloud compute networks subnets create \
  cinternal-vpc1-${REGION}-abjx-gke-core-03 \
  --network=${SHARED_PROD_VPC_NAME} \
  --region=${REGION} \
  --range=192.168.96.0/20 \
  --secondary-range=pods-03=100.72.0.0/18,svc-03=100.76.0.0/18
```

PSC NAT subnet 示例：

```bash
gcloud compute networks subnets create \
  cinternal-vpc1-${REGION}-abjx-psc-int-ingress-03 \
  --network=${SHARED_PROD_VPC_NAME} \
  --region=${REGION} \
  --range=192.168.240.0/26 \
  --purpose=PRIVATE_SERVICE_CONNECT

gcloud compute networks subnets create \
  cinternal-vpc1-${REGION}-abjx-psc-ext-ingress-03 \
  --network=${SHARED_PROD_VPC_NAME} \
  --region=${REGION} \
  --range=192.168.240.64/26 \
  --purpose=PRIVATE_SERVICE_CONNECT
```

### Phase 2：创建 cluster-03

```bash
gcloud container clusters create \
  abjx-${ENV}-${REGION}-cluster-03 \
  --region=${REGION} \
  --network=${SHARED_PROD_VPC_NAME} \
  --subnetwork=cinternal-vpc1-${REGION}-abjx-gke-core-03 \
  --cluster-secondary-range-name=pods-03 \
  --services-secondary-range-name=svc-03 \
  --enable-ip-alias \
  --enable-private-nodes \
  --enable-private-endpoint \
  --enable-master-authorized-networks \
  --master-ipv4-cidr=192.168.224.64/28
```

生产建议：

- 使用 regional cluster。
- 为关键 gateway、control-plane addon、runtime workload 配置 PDB。
- Node pool 使用 surge upgrade，避免升级时容量不足。
- 使用独立 node pool 区分 gateway、system、runtime workload。
- 预留 autoscaling 上限，并确认区域 quota。

### Phase 3：部署 PSC + ILB + Mesh Gateway

交付物：

- [ ] Internal Load Balancer。
- [ ] PSC service attachment。
- [ ] Consumer accept list。
- [ ] Cloud Service Mesh / Istio ingress gateway。
- [ ] Gateway、VirtualService 或 Gateway API resources。
- [ ] tenant endpoint / DNS / health check 验证。

建议入口模型：

```text
PSC Endpoint
  -> Service Attachment
  -> Internal Load Balancer
  -> Mesh Ingress Gateway
  -> Runtime Service
```

### Phase 4：CI/CD 与 Onboarding 接入

Pipeline 必须显式表达目标平台：

```yaml
platform:
  version: "2.0"
  vpc_name: "${SHARED_PROD_VPC_NAME}"
  region: "${REGION}"
  cluster_id: "03"
  cluster_name: "abjx-${ENV}-${REGION}-cluster-03"
  ingress_mode: "psc"
  mesh_mode: "cloud-service-mesh"
```

必须调整：

| 模块 | 调整内容 |
|---|---|
| Onboarding | 新用户默认 target 2.0，老用户保留 1.0 target |
| Cluster selector | 使用 `platform_version + region + cluster_id` |
| Helm values | 增加 `ingress_mode`、`mesh_mode`、`cluster_id`、gateway host |
| IAM / Workload Identity | 确认 KSA/GSA 绑定和最小权限 |
| Policy baseline | 自动创建 namespace、NetworkPolicy、AuthorizationPolicy、PeerAuthentication |
| Validation | onboarding 后自动探测 PSC、Gateway、Runtime health |

### Phase 5：并行运行与迁移

迁移顺序：

1. 新用户默认进入 2.0。
2. 选择低风险老 tenant，在 2.0 创建影子环境。
3. 同步配置、Secret、依赖服务、DNS/endpoint。
4. 在入口层按 tenant 切换到 2.0 PSC/ILB。
5. 观察错误率、延迟、PSC NAT IP、ILB backend health、mesh telemetry。
6. 确认无回滚需求后，下线 1.0 对应 workload。

---

## 7. MIG Refresh 与运维改造

即使当前保持同 VPC，也建议将 MIG refresh 从隐式单 VPC 改成显式 target 配置。

```yaml
mig_refresh_targets:
  - platform_version: "1.0"
    vpc_name: "${SHARED_PROD_VPC_NAME}"
    enabled: true
  - platform_version: "2.0"
    vpc_name: "${SHARED_PROD_VPC_NAME}"
    cluster_selector:
      - "cluster-03"
      - "cluster-04"
    enabled: true
```

要求：

- dry-run 默认开启。
- 先对 2.0 做 canary refresh。
- refresh 报告按 platform version 和 cluster 输出。
- 如果未来切到新 VPC，只需要新增 target，不重写脚本主体。

---

## 8. 验证清单

| 验证项 | 方法 |
|---|---|
| IPAM 审批 | 确认 `100.72.0.0/14`、`100.76.0.0/14`、`192.168.240.0/20` 无企业路由冲突 |
| Subnet 与 secondary ranges | `gcloud compute networks subnets describe` |
| GKE IP allocation | `gcloud container clusters describe` 检查 `ipAllocationPolicy` |
| Pod IP | 创建 test pod，确认 Pod IP 落在 `100.72.0.0/18` |
| Service IP | 创建 test service，确认 ClusterIP 落在 `100.76.0.0/18` |
| Private control plane | 从授权 GCE/MIG 或 CI runner 执行 `kubectl get ns` |
| PSC attachment | 检查 service attachment connected endpoints |
| PSC NAT 容量 | 监控 producer used NAT IP 指标 |
| ILB backend health | 检查 backend service health |
| Mesh gateway | 请求测试域名，验证 route、mTLS、policy、telemetry |
| Onboarding | 创建测试 tenant，完整跑通部署和访问 |
| MIG refresh | 先 dry-run，再 canary refresh |

---

## 9. 回滚策略

| 场景 | 回滚动作 |
|---|---|
| 2.0 新用户 onboarding 失败 | 暂停 2.0 onboarding，pipeline target 切回 1.0 或停止新用户接入 |
| PSC/ILB 异常 | tenant endpoint/DNS 不切换，1.0 继续承载 |
| Mesh gateway/policy 异常 | 回滚 Gateway、VirtualService、AuthorizationPolicy、PeerAuthentication |
| 单 tenant 迁移异常 | 入口层切回 1.0 endpoint/backend |
| CIDR 冲突或 IPAM 未审批 | 停止 cluster-03+ 创建，回滚 subnet/secondary range 变更 |
| MIG refresh 异常 | 停止 2.0 refresh target，保留 1.0 refresh |

---

## 10. 1.0 退役后的 cluster-01/02 处理

1.0 完全退役后，cluster-01/02 有两个选择。

### 10.1 推荐默认：保持 cluster-03+ 编号

优点：

- 不需要二次迁移。
- 不影响已上线 tenant。
- 运维风险最低。

缺点：

- cluster-01/02 编号长期空缺。

### 10.2 可选：回填 cluster-01/02

适用场景：

- 组织强制要求编号连续。
- 1.0 已完全下线，所有释放网段已经确认无残留路由。
- 能接受额外 cluster 创建、mesh 部署、CI/CD target 更新和 tenant 迁移动作。

回填建议：

| Cluster | Node subnet | Pod secondary range | Service secondary range | Control plane CIDR |
|---|---|---|---|---|
| cluster-01 | `192.168.64.0/20` | `100.64.0.0/18` | `100.68.0.0/18` | 使用未分配 `/28`，例如 `192.168.225.96/28` |
| cluster-02 | `192.168.80.0/20` | `100.64.64.0/18` | `100.68.64.0/18` | 使用未分配 `/28`，例如 `192.168.225.112/28` |

注意：

- 回填前必须确认 1.0 GKE cluster 已删除，Node/Pod/Service/Control Plane CIDR 无残留。
- Control Plane CIDR 不建议复用存在争议的早期预留块，优先选择经 IPAM 确认的干净 `/28`。
- 回填不是迁移必需项，默认不做更稳。

---

## 11. 关键设计决策

| 决策 | 选择 | 理由 |
|---|---|---|
| VPC 模型 | 同 VPC 共存 | 降低首期工程改造量 |
| 起始 cluster | cluster-03 | 避开 1.0 Node 和 control plane 范围 |
| Pod CIDR | `100.72.0.0/14` | 避开 1.0 Pod `100.64.0.0/14`，连续、易扩展 |
| Service CIDR | `100.76.0.0/14` | 避开 1.0 Service `100.68.0.0/17`，与 Pod 池分离 |
| Control Plane CIDR | 每 cluster `/28` | 符合 GKE private cluster 创建要求 |
| PSC NAT | `192.168.240.0/20` | 与 1.0/2.0 GKE 网段隔离，支持按 attachment 拆分 |
| 2.0 测试环境调整 | 重建 cluster | 避免 default Pod/Service range 残留 |
| Mesh 首期 | Cloud Service Mesh / Istio API | GCP 原生，后续可向 Gloo Mesh 演进 |
| 迁移切流 | 优先入口层 | Mesh 权重只负责 2.0 内部灰度 |

---

## 12. 参考依据

- [Understand IP addressing in GKE](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/about-ip-addressing)
- [Configure clusters with Shared VPC](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/cluster-shared-vpc)
- [Adding Pod IPv4 address ranges](https://cloud.google.com/kubernetes-engine/docs/how-to/multi-pod-cidr)
- [Creating a private cluster](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/legacy/network-isolation)
- [About published services - NAT subnet sizing](https://cloud.google.com/vpc/docs/about-vpc-hosted-services#nat-subnet-sizing)
- [Cloud Service Mesh overview](https://docs.cloud.google.com/service-mesh/docs/overview)
