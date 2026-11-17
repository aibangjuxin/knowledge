# 跨项目 PSC 结合 Cloud Service Mesh 实现方案

> 文档版本: 1.0  
> 创建日期: 2026-03-14  
> 目标读者: 平台工程 / SRE / 基础设施团队  
> 关联文档: 3.md, 3-add-mesh.md, cross-project-mesh.md, cloud-service-mesh.md, master-project-setup-mesh.md

---

## 1. 问题理解

### 1.1 现有实现（来自 3.md）

你已经通过 PSC NEG 成功打通了跨项目链路：

```
Tenant Project (Consumer)
  └── GLB
      └── PSC NEG
          ↓ (PSC 跨项目隧道)
Master Project (Producer)
  └── Service Attachment
      └── ILB
          └── Backend Service (GKE / VM / MIG)
```

核心特点：
- PSC NEG 指向 Service Attachment
- 不暴露 Backend IP
- Producer 可以控制 Consumer 访问权限

### 1.2 新目标

在 Master Project 的 GKE 上引入 Cloud Service Mesh (CSM)，实现：

- Master 内部服务的 mTLS、授权、限流、重试、熔断、金丝雀、可观测性
- Tenant → Master 的调用仍通过 PSC 边界，在 Master 的 Mesh 入口统一治理

### 1.3 关键约束（V1 推荐）

| 约束项 | 说明 |
|--------|------|
| PSC 仍是跨项目网络边界 | CSM 负责边界之后（Master 内部）的服务治理 |
| 只在 Master 上 Mesh | Tenant 不强制上 Mesh，避免多租户场景的爆炸半径与复杂度 |
| 不追求端到端 mTLS | Tenant 没 sidecar 时做不到，但可以在 Mesh Gateway 边界做强安全（JWT/mTLS/AuthorizationPolicy） |

---

## 2. 架构理解

### 2.1 核心架构图

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Tenant Project (Consumer)                      │
│  ┌─────────────┐    ┌─────────────┐                                │
│  │ Tenant Workloads │ → │    GLB     │ → PSC NEG                 │
│  └─────────────┘    └─────────────┘                                │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                │ PSC 跨项目隧道
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Master Project (Producer)                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ PSC NAT Subnet (purpose=PRIVATE_SERVICE_CONNECT)           │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                │                                    │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              Service Attachment                            │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                │                                    │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              ILB (Internal Passthrough L4)                 │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                │                                    │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │         Mesh Gateway (Envoy Ingress)                      │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                │                                    │
│  ┌──────────────────┐    ┌──────────────────┐                     │
│  │ Service A        │    │ Service B        │   (Cloud Service    │
│  │ (with sidecar)   │    │ (with sidecar)   │    Mesh 内部)       │
│  └──────────────────┘    └──────────────────┘                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 流量路径详解

| 步骤 | 流量阶段 | 说明 |
|------|----------|------|
| 1 | Tenant → GLB | 外部客户端通过 HTTPS 访问 GLB |
| 2 | GLB → PSC NEG | NEG 持有 PSC 接入 IP，将流量发往 Service Attachment |
| 3 | PSC 跨项目隧道 | GCP 内部建立 Tenant VPC → Master VPC 的隔离通道 |
| 4 | Service Attachment → ILB | 流量到达 Master 的 ILB（指向 Mesh Gateway） |
| 5 | Mesh Gateway → Backend | Gateway 进行路由分发，后端服务间自动升级为 mTLS |

### 2.3 为什么这个架构合理

| 维度 | 分析 |
|------|------|
| 边界清晰 | PSC 解决网络边界与接入控制，Mesh 解决边界内的治理 |
| 适合多租户 | Tenant 不需要统一升级/统一控制面，爆炸半径小 |
| 最小改造 | 只需在 Master 侧增加 Mesh Gateway，Tenant 侧无感知 |
| 安全性 | 可以在 Gateway 边界做 JWT 鉴权、mTLS、AuthorizationPolicy |

---

## 3. 实施步骤

### 3.1 准备阶段：确定输入参数

| 输入项 | 示例值 | 说明 |
|--------|--------|------|
| Fleet Host Project | fleet-host-prj | CSM 托管控制面的关键依赖 |
| Master Project | master-prj | GKE 集群所在项目 |
| Network Project | net-host-prj | Shared VPC Host（如果使用） |
| Cluster Location | asia-east1 | 建议 Regional 集群 |
| Cluster Name | master-gke | Master GKE 集群名称 |
| Tenant Project ID | tenant-prj | Consumer 项目 ID |

### 3.2 步骤一：启用必要 API

```bash
# 设置环境变量
FLEET_PROJECT_ID="fleet-host-prj"
MASTER_PROJECT_ID="master-prj"

# 在 Fleet Host Project 启用 API
gcloud services enable \
  mesh.googleapis.com \
  meshca.googleapis.com \
  gkehub.googleapis.com \
  container.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  connectgateway.googleapis.com \
  trafficdirector.googleapis.com \
  networkservices.googleapis.com \
  networksecurity.googleapis.com \
  --project="${FLEET_PROJECT_ID}"

# 在 Master Project 启用 API
gcloud services enable mesh.googleapis.com --project="${MASTER_PROJECT_ID}"
```

### 3.3 步骤二：IAM 权限配置

```bash
# 获取 Fleet Project Number
FLEET_PROJECT_NUMBER=$(gcloud projects describe "${FLEET_PROJECT_ID}" --format="value(projectNumber)")

# CSM Service Account
CSM_SA="service-${FLEET_PROJECT_NUMBER}@gcp-sa-servicemesh.iam.gserviceaccount.com"

# 在 Network Project 授予角色
gcloud projects add-iam-policy-binding "${NETWORK_PROJECT_ID}" \
  --member="serviceAccount:${CSM_SA}" \
  --role="roles/anthosservicemesh.serviceAgent"

# 在 Master Project 授予角色
gcloud projects add-iam-policy-binding "${MASTER_PROJECT_ID}" \
  --member="serviceAccount:${CSM_SA}" \
  --role="roles/anthosservicemesh.serviceAgent"
```

### 3.4 步骤三：注册集群到 Fleet

```bash
CLUSTER_NAME="master-gke"
CLUSTER_LOCATION="asia-east1"

# 将 Master 集群关联到 Fleet
gcloud container clusters update "${CLUSTER_NAME}" \
  --project="${MASTER_PROJECT_ID}" \
  --location="${CLUSTER_LOCATION}" \
  --fleet-project "${FLEET_PROJECT_ID}"

# 验证 Membership
gcloud container fleet memberships list --project "${FLEET_PROJECT_ID}"
```

### 3.5 步骤四：启用 Fleet Managed Cloud Service Mesh

```bash
# 启用 Fleet Mesh
gcloud container fleet mesh enable --project "${FLEET_PROJECT_ID}"

# 对 Master 集群开启自动管理
MEMBERSHIP_NAME="master-gke-membership"
MEMBERSHIP_LOCATION="asia-east1"

gcloud container fleet mesh update \
  --management automatic \
  --memberships "${MEMBERSHIP_NAME}" \
  --project "${FLEET_PROJECT_ID}" \
  --location "${MEMBERSHIP_LOCATION}"

# 验证 Mesh 状态
gcloud container fleet mesh describe --project "${FLEET_PROJECT_ID}"
```

### 3.6 步骤五：启用 Sidecar 注入

```bash
# 查看当前 revision 信息
kubectl get mutatingwebhookconfigurations | grep -E "istio|asm|mesh"
kubectl get pods -A | grep -E "istiod|asm"

# 只对目标 namespace 启用注入（示例：platform 命名空间）
kubectl label namespace platform istio.io/rev=asm-managed --overwrite
```

### 3.7 步骤六：部署 Mesh Ingress Gateway

```yaml
# 1. 创建独立的 Gateway Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: mesh-gw
  labels:
    istio-injection: disabled
```

```yaml
# 2. Gateway Service（创建 Internal ILB）
apiVersion: v1
kind: Service
metadata:
  name: mesh-gateway-ilb
  namespace: mesh-gw
  annotations:
    networking.gke.io/load-balancer-type: "Internal"
spec:
  type: LoadBalancer
  selector:
    app: mesh-gateway
  ports:
  - name: http
    port: 80
    targetPort: 8080
  - name: https
    port: 443
    targetPort: 8443
```

```yaml
# 3. Gateway Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mesh-gateway
  namespace: mesh-gw
spec:
  replicas: 3
  selector:
    matchLabels:
      app: mesh-gateway
  template:
    metadata:
      labels:
        app: mesh-gateway
    spec:
      containers:
      - name: gateway
        image: istio/proxyv2:1.20.0
        args: ["proxy", "router", "--domain", "$(POD_NAMESPACE).svc.cluster.local"]
        ports:
        - containerPort: 8080
        - containerPort: 8443
```

### 3.8 步骤七：更新 Service Attachment 指向 Mesh Gateway

```bash
# 查看 Internal Forwarding Rules
gcloud compute forwarding-rules list \
  --project="${MASTER_PROJECT_ID}" \
  --filter="loadBalancingScheme=INTERNAL"

# 创建/更新 Service Attachment
gcloud compute service-attachments create master-mesh-attachment \
  --project="${MASTER_PROJECT_ID}" \
  --region=asia-east1 \
  --producer-forwarding-rule="YOUR_GW_ILB_FWD_RULE" \
  --connection-preference=ACCEPT_MANUAL \
  --nat-subnets="psc-nat-subnet" \
  --consumer-accept-list="tenant-project-id=100"
```

### 3.9 步骤八：配置 Mesh 内部路由与安全

#### 3.9.1 Gateway + VirtualService 路由

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: master-gw
  namespace: mesh-gw
spec:
  selector:
    app: mesh-gateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "ppd01-ajbx.short.fqdn.aibang"
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: route-master-api
  namespace: mesh-gw
spec:
  hosts:
  - "ppd01-ajbx.short.fqdn.aibang"
  gateways:
  - master-gw
  http:
  - match:
    - uri:
        prefix: /master-api/svc-a/
    route:
    - destination:
        host: service-a.platform.svc.cluster.local
        port:
          number: 80
  - match:
    - uri:
        prefix: /master-api/svc-b/
    route:
    - destination:
        host: service-b.platform.svc.cluster.local
        port:
          number: 80
```

#### 3.9.2 JWT 鉴权（入口边界）

```yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: gw-jwt
  namespace: mesh-gw
spec:
  selector:
    matchLabels:
      app: mesh-gateway
  jwtRules:
  - issuer: "https://issuer.example.com"
    jwksUri: "https://issuer.example.com/.well-known/jwks.json"
```

#### 3.9.3 授权策略（按租户控制）

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: gw-tenant-allow
  namespace: mesh-gw
spec:
  selector:
    matchLabels:
      app: mesh-gateway
  action: ALLOW
  rules:
  - to:
    - operation:
        paths: ["/master-api/*"]
    when:
    - key: request.auth.claims[tenant_id]
      values: ["tenant-a", "tenant-b"]
```

#### 3.9.4 内部 mTLS（按 Namespace 推进）

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: platform
spec:
  mtls:
    mode: STRICT
```

---

## 4. 验证清单

### 4.1 必做验证项

| 验证项 | 命令/方法 |
|--------|-----------|
| Fleet 注册 | gcloud container fleet memberships list |
| Mesh 状态 | gcloud container fleet mesh describe |
| Sidecar 注入 | kubectl get pods -n platform 检查是否有 istio-proxy 容器 |
| Gateway ILB | Master Project 中存在 Internal Forwarding Rule |
| PSC 连接 | gcloud compute service-attachments describe 中 connectedEndpoints 有值 |
| 端到端请求 | Tenant 发起请求，能命中 Master Gateway |

### 4.2 常见问题排查

| 问题 | 可能原因 | 解决方案 |
|------|----------|----------|
| 源 IP 丢失 | PSC NAT 转换 | 使用 X-Forwarded-For Header 或 JWT claim |
| 健康检查失败 | Gateway 未配置健康检查路径 | 配置 /healthz/ready 端口 15021 |
| mTLS 失败 | Tenant 流量非 mesh | 在 Gateway 边界做 TLS 终止，不强制 STRICT |
| 权限不足 | CSM SA 未授权 | 检查 roles/anthosservicemesh.serviceAgent |

---

## 5. 回滚策略

### 5.1 最小回滚方案

只回滚 Producer 侧：
- 将 Service Attachment backend 指回旧 ILB（或旧后端）
- Mesh 保持运行，不影响 PSC 直接打旧后端的能力

```bash
# 回滚命令示例
gcloud compute service-attachments update master-mesh-attachment \
  --project="${MASTER_PROJECT_ID}" \
  --region=asia-east1 \
  --producer-forwarding-rule="OLD_ILB_FWD_RULE"
```

### 5.2 紧急回滚

- 移除 namespace 注入标签并重启 Pod：kubectl label namespace platform istio-injection- --overwrite
- 保持 PSC/ILB 路径不变，确保路由不受影响

---

## 6. 方案评估

### 6.1 合理性分析

| 评估维度 | 评分 | 说明 |
|----------|------|------|
| 架构清晰度 | 5/5 | PSC 边界 + Mesh 治理边界分离，职责明确 |
| 实施复杂度 | 3/5 | 只需在 Master 侧改造，Tenant 无感知 |
| 安全性 | 5/5 | Gateway 边界可做 JWT + mTLS + AuthorizationPolicy |
| 多租户隔离 | 4/5 | Tenant 之间通过 PSC allowlist 隔离，Mesh 内通过 Namespace 隔离 |
| 运维成本 | 4/5 | 不需要管理 Tenant Mesh，爆炸半径可控 |
| 可扩展性 | 4/5 | 新租户只需在 PSC allowlist 添加即可 |

### 6.2 不适合的场景

- 如果需要 Tenant 到 Master 的端到端 mTLS（需要 Tenant 也上 Mesh，形成 Mesh 联邦）
- 如果需要 Tenant 之间通过服务名直接互调（需要跨集群 Mesh 打通）

---

## 7. 总结

### 7.1 方案一句话概括

PSC 保持跨项目网络边界，Mesh 只在 Master 内部做服务治理，Tenant 通过 Mesh Gateway 统一入口访问。

### 7.2 实施路线图

| 阶段 | 任务 | 预计时间 |
|------|------|----------|
| 准备 | 确定 Fleet/Master 项目参数 | 0.5 天 |
| 基础 | 启用 API + IAM 配置 | 0.5 天 |
| Mesh | 安装 CSM + 注册集群 | 1 天 |
| 网关 | 部署 Mesh Gateway | 1 天 |
| 接入 | 更新 Service Attachment | 0.5 天 |
| 策略 | 配置路由 + 安全策略 | 1 天 |
| 验证 | 端到端测试 | 1 天 |

### 7.3 后续优化方向

- 多租户 Gateway：如果租户数量增加，可考虑为每个租户创建独立 Gateway
- 金丝雀发布：利用 Mesh 的流量分割能力做 A/B Testing
- 多集群 Mesh：如果 Master 有多个 GKE 集群，可扩展为多集群 Mesh

---

## 参考资料

- 3.md - 跨项目 PSC NEG 实现方案
- 3-add-mesh.md - 在现有 PSC NEG 架构上引入 Cloud Service Mesh
- cross-project-mesh.md - 跨项目 PSC 结合 Cloud Service Mesh 架构部署指南
- cloud-service-mesh.md - Google Cloud Service Mesh Setup Guide
- master-project-setup-mesh.md - Master Project Setup: Cloud Service Mesh
- Google Cloud Service Mesh 文档: https://cloud.google.com/service-mesh/docs
- Anthos Service Mesh 文档: https://cloud.google.com/anthos/service-mesh

---

**文档维护**: Kilo MiniMax
**审核状态**: 待审核
