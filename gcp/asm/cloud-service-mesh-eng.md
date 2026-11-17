# 多租户 GKE 平台 Google Cloud Service Mesh 配置指南

> 文档版本：1.0
> 最后更新：2026-02-27
> 目标受众：平台工程师、SRE、基础设施团队
> 前置条件：运行在 Master/Tenant 项目结构中的 GKE 集群

---

## 执行摘要

本文档为在多租户 GKE 平台中实施 **Google Cloud Service Mesh (GCSM)** 提供全面指南。基于您当前的架构：

- **Master 项目**：共享平台能力（GKE、Redis、Proxy、AI 模型）
- **Tenant 项目**：隔离的租户工作负载，专用资源
- **入口点**：用于南北流量的 Global HTTPS Load Balancer
- **网络模型**：跨项目 VPC 对等互联（IDMZ ↔ EDMZ）

**核心建议**：GCSM 用于集群内的**东西向服务治理**，而非作为主要的南北流量入口。您现有的 Global HTTPS LB + URL Map 架构仍然是外部流量管理的正确选择。

---

## 目录

1. [理解 Google Cloud Service Mesh](#1-理解-google-cloud-service-mesh)
2. [架构适配分析](#2-架构适配分析)
3. [部署模型](#3-部署模型)
4. [实施指南](#4-实施指南)
5. [服务导出与暴露模式](#5-服务导出与暴露模式)
6. [多 GKE 集群场景](#6-多-gke-集群场景)
7. [与现有架构集成](#7-与现有架构集成)
8. [运维考虑](#8-运维考虑)
9. [迁移路径](#9-迁移路径)
10. [附录](#10-附录)

---

## 1. 理解 Google Cloud Service Mesh

### 1.1 什么是 Google Cloud Service Mesh？

Google Cloud Service Mesh (GCSM) 是一个基于 Istio 的托管服务网格，提供以下能力：

| 能力 | 描述 |
|------|------|
| **流量管理** | 细粒度的服务间通信控制 |
| **安全性** | 服务间自动 mTLS、策略执行 |
| **可观测性** | 跨服务的统一指标、日志和链路追踪 |
| **可靠性** | 重试、超时、熔断、故障注入 |
| **金丝雀部署** | 用于渐进式发布的流量分割 |

### 1.2 GCSM 不是什么

❌ **不是 API 网关** - 不替代 Global HTTPS LB
❌ **不用于南北流量** - 设计用于东西向（服务到服务）
❌ **不替代 Kong/Apigee** - 缺少 API 生命周期管理
❌ **默认不支持多项目** - 每个网格通常生活在项目边界内

### 1.3 GCSM 与您当前架构的对比

| 层级 | 当前方案 | GCSM 角色 |
|------|---------|----------|
| **南北入口** | Global HTTPS LB + URL Map | ✅ 保持原样 |
| **API 管理** | Kong（可选）/ Cloud Armor | ✅ 保持原样 |
| **服务到服务** | 直接 Kubernetes Services | ⚠️ **GCSM 在此增值** |
| **安全性** | 网络策略、IAM | ✅ GCSM 增加 mTLS |
| **可观测性** | 每项目 Cloud Monitoring | ✅ GCSM 统一服务视图 |

---

## 2. 架构适配分析

### 2.1 您当前的多租户模型

```
┌─────────────────────────────────────────────────────────┐
│ Master 项目（平台）                                      │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ GKE 共享集群                                         │ │
│ │ - t1-*.gke-ns (租户 1 工作负载)                       │ │
│ │ - t2-*.gke-ns (租户 2 工作负载)                       │ │
│ │ - common-rt-gke-ns (共享服务)                        │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ 租户项目 A                                               │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ GKE 租户集群                                         │ │
│ │ - API / UI / 微服务                                  │ │
│ │ - Kong Gateway / GKE Gateway                         │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Service Mesh 在哪里适配？

**推荐的平台部署模型：**

```
┌──────────────────────────────────────────────────────────────┐
│ 外部流量流（南北向）                                          │
│ Client → Global HTTPS LB → R-PROXY → GKE Ingress → Service   │
│ ✅ 无需更改 - 保持现有架构                                    │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ 内部流量流（东西向）- GCSM 增值                                │
│ Service A → Sidecar Proxy → mTLS → Sidecar Proxy → Service B │
│                 ↑                                    ↑       │
│                 └──── Service Mesh Control Plane ────┘       │
│ ✅ GCSM 提供：安全性、可观测性、弹性                           │
└──────────────────────────────────────────────────────────────┘
```

### 2.3 决策矩阵：您需要 GCSM 吗？

| 场景 | 建议 |
|------|------|
| 每租户单个服务 | ❌ 不需要 |
| 每租户多个微服务 | ✅ 考虑 GCSM |
| 需要服务间 mTLS | ✅ 强候选 |
| 需要服务级金丝雀部署 | ✅ 强候选 |
| 需要跨服务的统一可观测性 | ✅ 强候选 |
| 仅需外部 API 网关 | ❌ 使用 Kong/Apigee |
| 需要租户间通信 | ⚠️ 复杂 - 见第 6 节 |

---

## 3. 部署模型

### 3.1 模型 A：每租户网格（多租户推荐）

**架构：**
```
┌─────────────────────────────────────────────────────────┐
│ 租户项目 A                                                │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ GKE 集群 A                                            │ │
│ │ ┌─────────────────────────────────────────────────┐ │ │
│ │ │ Service Mesh A (Istio)                          │ │ │
│ │ │ - Control Plane (托管)                           │ │ │
│ │ │ - Data Plane (sidecars)                         │ │ │
│ │ │ - Services: t1-api, t1-ui, t1-ms                │ │ │
│ │ └─────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ 租户项目 B                                                │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ GKE 集群 B                                            │ │
│ │ ┌─────────────────────────────────────────────────┐ │ │
│ │ │ Service Mesh B (Istio)                          │ │ │
│ │ │ - 独立于租户 A                                     │ │ │
│ │ │ - Services: t2-api, t2-ui, t2-ms                │ │ │
│ │ └─────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**优点：**
- ✅ 清晰的爆炸半径隔离
- ✅ 租户特定策略
- ✅ 独立升级周期
- ✅ 符合 1 Team = 1 Project 模型

**缺点：**
- ❌ 无统一跨租户服务发现
- ❌ 每网格运维开销更大
- ❌ 平台必须提供模板/护栏

**最适合：** 具有强隔离要求的多租户平台

---

### 3.2 模型 B：平台范围网格（多租户不推荐）

**架构：**
```
┌─────────────────────────────────────────────────────────┐
│ Master 项目                                               │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ GKE 共享集群                                         │ │
│ │ ┌─────────────────────────────────────────────────┐ │ │
│ │ │ 统一 Service Mesh                                │ │ │
│ │ │ - 所有租户共享同一控制平面                         │ │ │
│ │ │ - 仅命名空间隔离                                   │ │ │
│ │ │ - t1-ns, t2-ns, common-ns                       │ │ │
│ │ └─────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**优点：**
- ✅ 统一策略执行
- ✅ 更简单的跨服务通信
- ✅ 单一可观测平面

**缺点：**
- ❌ 大爆炸半径
- ❌ 复杂的多项目网络
- ❌ 租户工作负载共享控制平面
- ❌ 更难满足隔离要求

**最适合：** 单组织内部微服务（非多租户 SaaS）

---

### 3.3 模型 C：混合（平台服务 + 租户服务）

**架构：**
```
┌─────────────────────────────────────────────────────────┐
│ Master 项目 - 平台服务网格                                 │
│ - 共享基础设施服务                                        │
│ - Redis、公共 API、平台服务                               │
└─────────────────────────────────────────────────────────┘
                          ↕ (受控网关)
┌─────────────────────────────────────────────────────────┐
│ 租户项目 - 租户服务网格                                     │
│ - 租户特定微服务                                          │
│ - 与其他租户隔离                                          │
└─────────────────────────────────────────────────────────┘
```

**优点：**
- ✅ 平台服务获得网格优势
- ✅ 保持租户隔离
- ✅ 受控的跨网格通信

**缺点：**
- ❌ 实施最复杂
- ❌ 需要多网格网关模式
- ❌ 需要高级运维知识

**最适合：** 具有清晰平台/租户服务边界的成熟平台

---

## 4. 实施指南

### 4.1 前置条件

部署 GCSM 前，确保：

1. **GKE 版本**：推荐 1.26 或更高
2. **项目权限**：`roles/container.admin`、`roles/meshconfig.admin`
3. **API 已启用**：
   ```bash
   gcloud services enable mesh.googleapis.com \
     container.googleapis.com \
     monitoring.googleapis.com \
     logging.googleapis.com \
     --project=${PROJECT_ID}
   ```

4. **网络要求**：
   - Workload Identity 已启用
   - 推荐私有集群
   - 足够的 IP 范围供 sidecars 使用

---

### 4.2 逐步：在租户 GKE 上部署 GCSM

#### 步骤 1：启用所需 API

```bash
PROJECT_ID="your-tenant-project-id"
CLUSTER_NAME="tenant-gke-cluster"
LOCATION="asia-southeast1"

gcloud services enable mesh.googleapis.com \
  container.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  --project=${PROJECT_ID}
```

#### 步骤 2：创建支持 Mesh 的 GKE 集群

```bash
gcloud container clusters create ${CLUSTER_NAME} \
  --location=${LOCATION} \
  --workload-pool=${PROJECT_ID}.svc.id.goog \
  --mesh-certificates=enable=true \
  --enable-ip-alias \
  --enable-intra-node-visibility \
  --num-nodes=3 \
  --machine-type=e2-standard-4 \
  --network=edmz-vpc \
  --subnetwork=edmz-subnet
```

#### 步骤 3：注册集群到 GCSM

```bash
gcloud container memberships register ${CLUSTER_NAME}-membership \
  --gke-cluster=${LOCATION}/${CLUSTER_NAME} \
  --enable-workload-identity
```

#### 步骤 4：创建 Service Mesh 部署

```bash
gcloud container mesh create \
  --location=${LOCATION} \
  --cluster=${CLUSTER_NAME} \
  --cluster-membership=${CLUSTER_NAME}-membership
```

#### 步骤 5：验证 Mesh 状态

```bash
gcloud container mesh describe \
  --location=${LOCATION} \
  --cluster=${CLUSTER_NAME}
```

---

### 4.3 逐步：注入 Sidecar 代理

#### 选项 A：自动注入（推荐）

```yaml
# 为命名空间启用 sidecar 注入
apiVersion: v1
kind: Namespace
metadata:
  name: t1-api
  labels:
    istio-injection: enabled
```

#### 选项 B：手动注入

```bash
# 向现有 deployment 注入 sidecar
kubectl get deployment my-service -n t1-api -o yaml | \
  istioctl kube-inject -f - | \
  kubectl apply -f -
```

---

### 4.4 逐步：配置 mTLS

```yaml
# 网格级 mTLS 策略（严格模式）
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: t1-api
spec:
  mtls:
    mode: STRICT
```

```yaml
# 仅允许 mTLS 流量到此服务
apiVersion: security.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-service-mtls
  namespace: t1-api
spec:
  host: my-service.t1-api.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
```

---

### 4.5 逐步：流量管理

#### 金丝雀部署示例

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-service-vs
  namespace: t1-api
spec:
  hosts:
  - my-service
  http:
  - match:
    - headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: my-service
        subset: canary
  - route:
    - destination:
        host: my-service
        subset: stable
      weight: 90
    - destination:
        host: my-service
        subset: canary
      weight: 10
```

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-service-dr
  namespace: t1-api
spec:
  host: my-service
  subsets:
  - name: stable
    labels:
      version: stable
  - name: canary
    labels:
      version: canary
```

---

## 5. 服务导出与暴露模式

### 5.1 内部服务暴露（网格内）

网格内的服务通过 Kubernetes DNS 自动可发现：

```
# Service A 调用 Service B
http://service-b.t1-api.svc.cluster.local:8080
```

**无需额外配置** - sidecars 处理服务发现和 mTLS。

---

### 5.2 外部服务暴露（南北向）

**重要**：GCSM 不是您的外部入口点。使用现有架构：

```
External Client
    ↓
Global HTTPS LB (Entry Project)
    ↓
R-PROXY (IDMZ)
    ↓
GKE Ingress / Gateway API
    ↓
Service (with sidecar)
```

#### 选项 A：GKE Ingress（推荐）

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-service-ingress
  namespace: t1-api
  annotations:
    kubernetes.io/ingress.class: "gce"
    networking.gke.io/managed-certificates: "my-service-cert"
spec:
  rules:
  - host: my-service.aibang.com
    http:
      paths:
      - path: /*
        pathType: ImplementationSpecific
        backend:
          service:
            name: my-service
            port:
              number: 8080
```

#### 选项 B：Istio Ingress Gateway（高级）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: my-service-gateway
  namespace: t1-api
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: my-service-tls
    hosts:
    - my-service.aibang.com
```

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-service-vs
  namespace: t1-api
spec:
  hosts:
  - my-service.aibang.com
  gateways:
  - my-service-gateway
  http:
  - route:
    - destination:
        host: my-service
        port:
          number: 8080
```

⚠️ **警告**：Istio Ingress Gateway 增加复杂性。仅在需要 GKE Ingress 不支持的高级 L7 路由时使用。

---

### 5.3 跨项目服务暴露

用于跨项目暴露服务（Master ↔ Tenant）：

#### 模式 1：Backend Service + NEG（推荐）

```
Tenant Project Service
    ↓
NEG (Network Endpoint Group)
    ↓
Cross-Project Backend Service (Entry Project)
    ↓
Global HTTPS LB
```

**配置：**

```bash
# 在租户项目 - 创建 NEG
gcloud compute network-endpoint-groups create my-service-neg \
  --network-endpoint-type=gce-vm-ip-port \
  --zone=${ZONE} \
  --project=${TENANT_PROJECT}

# 在入口项目 - 引用跨项目 NEG
gcloud compute backend-services create my-service-backend \
  --global \
  --project=${ENTRY_PROJECT}

gcloud compute backend-services add-backend my-service-backend \
  --network-endpoint-group=my-service-neg \
  --network-endpoint-group-zone=${ZONE} \
  --project=${ENTRY_PROJECT}
```

#### 模式 2：Private Service Connect (PSC)

用于 service-as-a-product 模型：

```
Service Producer (Master/Tenant)
    ↓
PSC Endpoint
    ↓
VPC Peering / Network
    ↓
Service Consumer (Other Tenants)
```

---

## 6. 多 GKE 集群场景

### 6.1 您需要多个 GKE 集群吗？

**问题**："如果我们的 GCP master 项目需要多个 GKE？"

**答案**：取决于您的隔离要求：

| 场景 | 建议 |
|------|------|
| 多租户，共享基础设施 | ✅ 单集群 + 命名空间隔离 |
| 多租户，强隔离 | ✅ 多集群（每租户一个） |
| 生产 + 非生产 | ✅ 分离集群 |
| 不同区域 | ✅ 区域集群或多集群 |
| 不同合规要求 | ✅ 分离集群 |
| 规模 > 1000 pods/集群 | ✅ 考虑多集群 |

---

### 6.2 多集群 Mesh 模式

#### 模式 A：独立网格（推荐）

每个集群有自己的 service mesh：

```
Cluster A (Tenant 1)          Cluster B (Tenant 2)
┌─────────────────┐           ┌─────────────────┐
│ Mesh A          │           │ Mesh B          │
│ - Control Plane │           │ - Control Plane │
│ - Services      │           │ - Services      │
└─────────────────┘           └─────────────────┘
       ↓                             ↓
  No direct mesh communication (isolated)
```

**优点：**
- 最大隔离
- 独立升级
- 清晰爆炸半径

**缺点：**
- 无跨集群服务发现
- 需要网关进行集群间通信

---

#### 模式 B：多集群 Mesh（高级）

连接多个集群到单一网格：

```
Cluster A                      Cluster B
┌─────────────────────────────────────────┐
│         Unified Service Mesh            │
│  ┌────────────┐    ┌────────────┐      │
│  │ Control    │◄──►│ Control    │      │
│  │ Plane A    │    │ Plane B    │      │
│  └────────────┘    └────────────┘      │
│         ▲                   ▲           │
│         └───────┬───────────┘           │
│                 ▼                       │
│         Shared Service Discovery        │
└─────────────────────────────────────────┘
```

**要求：**
- 所有集群注册到同一 GCSM 控制平面
- 集群间网络连接（VPC Peering）
- 信任域对齐
- 高级运维专业知识

**⚠️ 不推荐用于多租户隔离** - 增加爆炸半径

---

### 6.3 跨集群通信

如果需要 Cluster A → Cluster B 通信：

#### 选项 1：网关模式（推荐）

```yaml
# 通过 Cluster B 中的 Gateway 暴露服务
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: cross-cluster-gateway
  namespace: t2-api
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - t2-service.internal.aibang.com
```

```yaml
# Cluster A 通过网关调用 Cluster B
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: t2-service-external
  namespace: t1-api
spec:
  hosts:
  - t2-service.internal.aibang.com
  ports:
  - number: 443
    name: https
    protocol: HTTPS
  location: MESH_EXTERNAL
  resolution: DNS
```

#### 选项 2：多集群 Service Entry

用于统一网格场景：

```yaml
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: remote-service
  namespace: t1-api
spec:
  hosts:
  - my-service.t2-api.global
  location: MESH_INTERNAL
  ports:
  - number: 8080
    name: http
    protocol: HTTP
  resolution: NONE
```

---

## 7. 与现有架构集成

### 7.1 当前架构集成点

基于您现有的文档：

```
┌─────────────────────────────────────────────────────────────┐
│ Internet                                                    │
│   ↓                                                         │
│ Global HTTPS LB (Entry Project) ← 保持原样                  │
│   ↓                                                         │
│ Cloud Armor / WAF / Cert Manager ← 保持原样                 │
│   ↓                                                         │
│ R-PROXY (TLS/mTLS) ← 保持原样                               │
│   ↓                                                         │
│ Bridge Proxy (L4) ← 保持原样                                │
│   ↓                                                         │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ GKE Cluster (Master or Tenant)                          │ │
│ │   ↓                                                     │ │
│ │ GKE Ingress / Gateway API ← 保持原样                    │ │
│ │   ↓                                                     │ │
│ │ ┌─────────────────────────────────────────────────────┐ │ │
│ │ │ Service Mesh Sidecar (NEW)                          │ │ │
│ │ │   ↓                                                 │ │ │
│ │ │ Application Container                               │ │ │
│ │ └─────────────────────────────────────────────────────┘ │ │
│ │   ↕ (east-west traffic via mesh)                        │ │
│ │ ┌─────────────────────────────────────────────────────┐ │ │
│ │ │ Other Services with Sidecars                        │ │ │
│ │ └─────────────────────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

### 7.2 与 Kong Gateway 集成

如果使用 Kong 作为 API 网关：

```
External Client
    ↓
Global HTTPS LB
    ↓
Kong Gateway (on GKE)
    ↓
┌─────────────────────────────┐
│ Service Mesh Sidecar        │
│   ↓                         │
│ Microservice A              │
│   ↕ (mesh-managed traffic)  │
│ Microservice B              │
└─────────────────────────────┘
```

**Kong 处理：**
- API 认证
- 速率限制
- 请求/响应转换
- 开发者门户

**Service Mesh 处理：**
- 服务间 mTLS
- 流量分割
- 重试和超时
- 可观测性

---

### 7.3 与 VPC Peering 集成

现有的 IDMZ ↔ EDMZ VPC peering：

```
Master Project (IDMZ VPC)
    ↓
VPC Peering
    ↓
Tenant Project (EDMZ VPC)
    ↓
GKE Cluster with Service Mesh
```

**关键考虑：**

1. **Sidecar 流量**：确保 VPC 防火墙规则允许 sidecar 通信
2. **服务发现**：Kubernetes DNS 在集群内工作；跨集群使用 Gateway
3. **mTLS**：在网格内工作；在网关处为外部流量终止

**所需防火墙规则：**

```bash
# 允许 Istio sidecar 通信
gcloud compute firewall-rules create allow-mesh-communication \
  --project=${TENANT_PROJECT} \
  --network=edmz-vpc \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:15001,tcp:15006,tcp:15011,tcp:15012,tcp:15014,tcp:15017 \
  --source-ranges=${GKE_POD_CIDR}
```

---

### 7.4 与跨项目日志记录集成

现有的集中式日志记录：

```
GKE with Service Mesh
    ↓
Cloud Logging (automatic)
    ↓
Log Router Sink
    ↓
Central Log Bucket (logging-hub-project)
```

**Service Mesh 增加这些日志类型：**

- `istio-access-log`：请求/响应日志
- `istio-audit-log`：策略执行日志
- `istio-error-log`：Sidecar 和控制平面错误

**确保这些包含在 sink 过滤器中：**

```text
logName:"istio"
OR logName:"mesh"
OR resource.type="k8s_container" AND labels.k8s-istio-mesh="*"
```

---

## 8. 运维考虑

### 8.1 监控和可观测性

GCSM 与 Cloud Monitoring 集成：

```bash
# 在 Cloud Monitoring 中查看网格指标
gcloud monitoring dashboards create --config-from-file=mesh-dashboard.json
```

**关键监控指标：**

| 指标 | 描述 | 告警阈值 |
|------|------|---------|
| `istio_requests_total` | 总请求数 | 错误率 > 1% |
| `istio_request_duration_milliseconds` | 请求延迟 | p99 > 500ms |
| `istio_tcp_connections_opened_total` | TCP 连接 | 突然下降 |
| `pilot_k8s_endpoints` | Endpoint 发现 | Count = 0 |
| `istio_build` | 组件版本 | 检测到不匹配 |

---

### 8.2 升级策略

**GCSM 升级路径：**

1. **先在非生产环境测试**
2. **遵循 Google 的升级顺序：**
   - 先控制平面
   - 后数据平面（sidecars）
3. **使用金丝雀部署进行 sidecar 升级**

```bash
# 检查当前 mesh 版本
gcloud container mesh describe --location=${LOCATION}

# 升级 mesh
gcloud container mesh update --location=${LOCATION}
```

---

### 8.3 备份和灾难恢复

**备份内容：**

- Istio 配置（VirtualServices、DestinationRules 等）
- 命名空间标签（istio-injection=enabled）
- Gateway 配置
- 自定义证书

**备份脚本示例：**

```bash
#!/bin/bash
BACKUP_DIR="istio-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p ${BACKUP_DIR}

kubectl get virtualservices --all-namespaces -o yaml > ${BACKUP_DIR}/virtualservices.yaml
kubectl get destinationrules --all-namespaces -o yaml > ${BACKUP_DIR}/destinationrules.yaml
kubectl get gateways --all-namespaces -o yaml > ${BACKUP_DIR}/gateways.yaml
kubectl get serviceentries --all-namespaces -o yaml > ${BACKUP_DIR}/serviceentries.yaml
```

---

### 8.4 安全最佳实践

1. **启用严格 mTLS：**
   ```yaml
   apiVersion: security.istio.io/v1beta1
   kind: MeshConfig
   spec:
     mtlsMode: STRICT
   ```

2. **实施授权策略：**
   ```yaml
   apiVersion: security.istio.io/v1beta1
   kind: AuthorizationPolicy
   metadata:
     name: require-jwt
     namespace: t1-api
   spec:
     rules:
     - from:
       - source:
           requestPrincipals: ["*"]
   ```

3. **定期轮换证书：**
   - GCSM 自动轮换工作负载证书
   - 每 90 天手动轮换网关证书

4. **审计网格配置：**
   - 对所有 Istio 资源使用 GitOps
   - 需要 PR 审查网格变更
   - 为网格控制平面启用审计日志

---

### 8.5 成本考虑

**GCSM 定价组成：**

1. **托管控制平面**：约 $50/月/集群
2. **数据平面（Sidecars）**：无额外成本
3. **Cloud Monitoring**：适用标准定价

**成本优化：**

- 不要向不需要网格功能的服务注入 sidecars
- 使用命名空间级注入控制
- 考虑非关键工作负载使用共享集群

---

## 9. 迁移路径

### 9.1 阶段 1：基础（第 1-2 月）

**目标：**
- 在一个非生产集群部署 GCSM
- 为 1-2 个服务启用 sidecar 注入
- 验证 mTLS 和可观测性

**任务：**
1. 启用 GCSM APIs
2. 部署测试集群
3. 部署示例微服务
4. 配置基础流量策略
5. 验证 Cloud Monitoring 集成

---

### 9.2 阶段 2：试点（第 3-4 月）

**目标：**
- 在一个租户生产集群部署 GCSM
- 迁移 2-3 个关键服务
- 实施金丝雀部署

**任务：**
1. 生产集群设置
2. 服务迁移（一次一个）
3. 实施流量管理策略
4. 设置告警和仪表板
5. 编写运维手册

---

### 9.3 阶段 3：扩展（第 5-6 月）

**目标：**
- 推广到所有租户集群
- 实施平台护栏
- 自动化网格供应

**任务：**
1. 创建 GCSM Terraform 模块
2. 定义平台基线策略
3. 实施自动化 onboarding
4. 培训租户团队网格功能
5. 建立升级流程

---

### 9.4 阶段 4：优化（第 7 月+）

**目标：**
- 高级流量管理
- 跨集群通信（如需要）
- 持续优化

**任务：**
1. 实施高级金丝雀模式
2. 优化资源分配
3. 审查和 refine 策略
4. 衡量和报告 ROI

---

## 10. 附录

### 10.1 常见故障排除命令

```bash
# 检查 sidecar 注入状态
kubectl get pods -n t1-api -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.istio-injection}{"\n"}{end}'

# 验证 mTLS 状态
istioctl analyze --all-namespaces

# 检查代理配置
istioctl proxy-config listeners <pod-name>.<namespace>

# 查看访问日志
istioctl proxy-config log <pod-name>.<namespace> --level access:debug

# 测试连接性
istioctl proxy-config route <pod-name>.<namespace> --name http.8080
```

---

### 10.2 Terraform 模块示例

```hcl
# GCSM-enabled GKE Cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.location
  project  = var.project_id

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  mesh_certificates {
    enable_certificates = true
  }

  # ... 其他配置
}

# 注册集群到 GCSM
resource "google_gke_hub_membership" "membership" {
  membership_id = "${var.cluster_name}-membership"
  project       = var.project_id
  location      = var.location

  endpoint {
    gke_cluster {
      resource_link = google_container_cluster.primary.id
    }
  }

  authority {
    issuer = "https://container.googleapis.com/${google_container_cluster.primary.id}"
  }
}
```

---

### 10.3 决策检查清单

部署 GCSM 前，确认：

- [ ] 每租户是否有多个微服务？
- [ ] 是否需要服务间 mTLS？
- [ ] 是否需要高级流量管理（金丝雀、重试、超时）？
- [ ] 是否有运维能力管理网格配置？
- [ ] GKE 版本是否兼容（1.26+）？
- [ ] 是否已启用 Workload Identity？
- [ ] 是否有足够的 IP 范围供 sidecars 使用？
- [ ] 是否已定义网格治理策略？
- [ ] 团队是否已接受 Istio 概念培训？
- [ ] 是否有回滚计划？

---

### 10.4 参考资料

- [Google Cloud Service Mesh 文档](https://cloud.google.com/service-mesh/docs)
- [Istio 文档](https://istio.io/latest/docs/)
- [GKE 最佳实践](https://cloud.google.com/kubernetes-engine/docs/best-practices)
- [多集群 Service Mesh](https://cloud.google.com/service-mesh/docs/multi-cluster-setup-overview)
- [Service Mesh vs API Gateway](https://cloud.google.com/architecture/service-meshes)

---

### 10.5 术语表

| 术语 | 定义 |
|------|------|
| **GCSM** | Google Cloud Service Mesh（托管 Istio） |
| **Sidecar** | 部署在每个服务容器旁边的 Envoy 代理 |
| **Control Plane** | 管理和配置所有 sidecar 代理 |
| **Data Plane** | 处理服务流量的 sidecar 代理网络 |
| **mTLS** | 服务间双向 TLS 认证 |
| **VirtualService** | 用于流量路由规则的 Istio 资源 |
| **DestinationRule** | 用于服务流量策略的 Istio 资源 |
| **Gateway** | 用于管理入站流量的 Istio 资源 |
| **NEG** | Network Endpoint Group（GCP 负载均衡后端） |
| **PSC** | Private Service Connect（GCP 服务暴露） |

---

## 总结和建议

### 对于您的多租户平台：

1. **✅ 采用 GCSM 用于集群内东西向服务治理**
2. **✅ 保持 Global HTTPS LB 用于南北流量**（不要用 mesh ingress 替代）
3. **✅ 使用每租户网格模型**实现隔离（模型 A）
4. **✅ 从非生产试点开始**再生产推广
5. **✅ 与现有日志/监控集成**（logging-hub-project）
6. **❌ 不使用网格进行跨项目路由**（使用 Backend Service + NEG）
7. **❌ 不部署多集群网格**除非绝对必要

### 下一步：

1. **第 1-2 周**：启用 GCSM APIs，部署测试集群
2. **第 3-4 周**：部署示例微服务，验证 mTLS
3. **第 2 月**：与一个租户工作负载试点
4. **第 3 月**：创建 Terraform 模块，定义护栏
5. **第 4 月+**：逐步推广到所有租户

---

**文档负责人**：基础设施团队
**审查周期**：季度
**反馈**：联系 platform-architecture@aibang.com
