- [核心概念：GKE Gateway API 无网关模式下的版本控制与平滑切换](#核心概念gke-gateway-api-无网关模式下的版本控制与平滑切换)
  - [1. 架构核心组件 (Core Architecture)](#1-架构核心组件-core-architecture)
    - [1.1 整体架构视图](#11-整体架构视图)
    - [1.2 对象关系图 (ER Diagram)](#12-对象关系图-er-diagram)
  - [2. 版本控制策略 (Versioning Strategy)](#2-版本控制策略-versioning-strategy)
    - [URL 抽象模型](#url-抽象模型)
    - [多版本并存架构视图](#多版本并存架构视图)
    - [关键配置：URL 重写](#关键配置url-重写)
  - [3. 平滑切换流程与配置示例 (Workflow \& Configuration)](#3-平滑切换流程与配置示例-workflow--configuration)
    - [3.0 版本切换全流程视图](#30-版本切换全流程视图)
    - [3.1 阶段一：资源准备 (Pre-deployment)](#31-阶段一资源准备-pre-deployment)
      - [1. 创建新版本 Service](#1-创建新版本-service)
      - [2. 绑定 HealthCheckPolicy](#2-绑定-healthcheckpolicy)
      - [3. 绑定 GCPBackendPolicy](#3-绑定-gcpbackendpolicy)
      - [4. 验证就绪状态 (Pre-switch Verification)](#4-验证就绪状态-pre-switch-verification)
        - [4.1 验证 K8s 资源与 Endpoint](#41-验证-k8s-资源与-endpoint)
        - [4.2 验证 Policy 绑定状态](#42-验证-policy-绑定状态)
        - [4.3 验证 GCP 后端 (NEG) 健康状况 (关键点)](#43-验证-gcp-后端-neg-健康状况-关键点)
        - [4.4 内部预验证 (Shadow Test)](#44-内部预验证-shadow-test)
    - [3.2 阶段二：流量切换 (Traffic Switching)](#32-阶段二流量切换-traffic-switching)
      - [场景：从 v11-24 升级到 v11-25](#场景从-v11-24-升级到-v11-25)
      - [流量分配机制](#流量分配机制)
    - [3.3 升级流程序列图](#33-升级流程序列图)
    - [3.4 资源清理生命周期](#34-资源清理生命周期)
  - [4. 常见问题 (FAQ)](#4-常见问题-faq)
    - [Q1: 为什么不能新建一个 HTTPRoute 来发布新版本？](#q1-为什么不能新建一个-httproute-来发布新版本)
    - [Q2: 如何验证网关已准备就绪？](#q2-如何验证网关已准备就绪)
    - [Q3: Ingress 和 Gateway API 在切换上有什么区别？](#q3-ingress-和-gateway-api-在切换上有什么区别)

# 核心概念：GKE Gateway API 无网关模式下的版本控制与平滑切换

本文档总结了基于 GKE Gateway API 直接管理后端服务版本控制与平滑升级的核心概念与最佳实践，并提供了详细的部署配置示例。

## 1. 架构核心组件 (Core Architecture)

在无独立 API 网关（No-Gateway）模式下，GKE Gateway 承担了流量入口与路由分发的职责。架构设计遵循**不可变基础设施**原则。

*   **HTTPRoute (路由契约)**: 
    *   定义对外的 API 结构（如 `/v2025`）。
    *   **不承载**后端具体行为配置，仅负责匹配（Match）、过滤器（Filter/Rewrite）和分发（BackendRefs）。
    *   作为版本切换的**唯一原子操作点**。

*   **Service (不可变后端)**: 
    *   每一个发布版本（Release）对应一个独立的 Kubernetes Service（例如 `service-v11-25`）。
    *   发布新版本意味着**创建新 Service**，而不是更新旧 Service。

*   **Policies (策略绑定)**: 
    *   **HealthCheckPolicy** & **GCPBackendPolicy**: 必须**独立绑定**到每一个版本的 Service 上。
    *   Policy 的 `metadata.name` 不参与路由逻辑，唯一生效条件是 `targetRef` 指向对应的 Service。

### 1.1 整体架构视图

```mermaid
graph TB
    subgraph "外部流量入口"
        Client[客户端请求<br/>dev.goole.cloud.uk.aibang]
        Nginx[Nginx L7 负载均衡<br/>location /api-name-type-ri-sb-samples]
    end
    
    subgraph "GKE Gateway Layer"
        Gateway[GKE Gateway<br/>abjx-common-gateway]
        HTTPRoute[HTTPRoute<br/>api-name-type-ri-sb-samples-route]
    end
    
    subgraph "Backend Services"
        SvcOld[Service 2025-11-19<br/>Port 443]
        SvcNew[Service 2025-12-18<br/>Port 443]
    end
    
    subgraph "应用层 Pods"
        PodOld1[Pod v2025-11-19-1]
        PodOld2[Pod v2025-11-19-2]
        PodOld3[Pod v2025-11-19-3]
        PodNew1[Pod v2025-12-18-1]
        PodNew2[Pod v2025-12-18-2]
        PodNew3[Pod v2025-12-18-3]
    end
    
    Client -->|HTTPS| Nginx
    Nginx -->|proxy_pass| Gateway
    Gateway -->|路由规则| HTTPRoute
    
    HTTPRoute -->|weight: 80| SvcOld
    HTTPRoute -->|weight: 20| SvcNew
    
    SvcOld -.->|selector: version=2025-11-19| PodOld1
    SvcOld -.->|selector: version=2025-11-19| PodOld2
    SvcOld -.->|selector: version=2025-11-19| PodOld3
    
    SvcNew -.->|selector: version=2025-12-18| PodNew1
    SvcNew -.->|selector: version=2025-12-18| PodNew2
    SvcNew -.->|selector: version=2025-12-18| PodNew3
    
    style Client fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    style Nginx fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style Gateway fill:#f3e5f5,stroke:#4a148c,stroke-width:3px
    style HTTPRoute fill:#e8f5e9,stroke:#1b5e20,stroke-width:3px
    style SvcOld fill:#fff9c4,stroke:#f57f17,stroke-width:2px
    style SvcNew fill:#c8e6c9,stroke:#2e7d32,stroke-width:2px
```

### 1.2 对象关系图 (ER Diagram)

```mermaid
erDiagram
    GATEWAY ||--o{ HTTPROUTE : "references"
    HTTPROUTE ||--o{ SERVICE : "backendRefs"
    SERVICE ||--o{ DEPLOYMENT : "selector"
    DEPLOYMENT ||--o{ POD : "creates"
    
    GATEWAY {
        string name "abjx-common-gateway"
        string gatewayClassName "gke-l7-global-external-managed"
    }
    
    HTTPROUTE {
        string name "v2025-route"
        string pathPrefix "/api/v2025"
    }
    
    SERVICE {
        string name "service-v2025-12-18"
        int weight "20"
    }
    
    POD {
        string status "Running"
        map labels "version=2025-12-18"
    }
```

---

## 2. 版本控制策略 (Versioning Strategy)

目标是实现**外部契约的稳定性**与**内部发布的灵活性**分离。

### URL 抽象模型

*   **外部 URL (External)**: `https://api.example.com/api/v2025/...`
    *   使用主版本号（Major Version），保持对客户端的长期承诺。
*   **内部路由 (Internal)**: 转发至 `service-v11-25`
    *   使用具体的补丁版本（Patch Version），便于回滚和排查。

    *   使用具体的补丁版本（Patch Version），便于回滚和排查。

### 多版本并存架构视图

```mermaid
graph TB
    subgraph "命名空间: ns-int-common-ms"
        subgraph "Gateway & Routing"
            GW[Gateway<br/>abjx-common-gateway]
            HR[HTTPRoute<br/>版本路由控制器]
        end
        
        subgraph "Version Old (v11-24)"
            Deploy1[Deployment<br/>v11-24]
            Svc1[Service<br/>v11-24]
            Svc1 -.-> Pod1[Pod v11-24]
        end
        
        subgraph "Version New (v11-25)"
            Deploy2[Deployment<br/>v11-25]
            Svc2[Service<br/>v11-25]
            Svc2 -.-> Pod2[Pod v11-25]
        end
    end
    
    GW --> HR
    HR -->|weight: 80%| Svc1
    HR -->|weight: 20%| Svc2
    
    style GW fill:#9c27b0,stroke:#4a148c,color:#fff,stroke-width:3px
    style HR fill:#7b1fa2,stroke:#4a148c,color:#fff,stroke-width:2px
    style Svc1 fill:#ff8a65,stroke:#bf360c,stroke-width:2px
    style Svc2 fill:#9ccc65,stroke:#33691e,stroke-width:2px
```

### 关键配置：URL 重写

利用 Gateway API 的 `URLRewrite` 过滤器，将外部的通用路径映射到内部的具体版本路径（如果后端应用需要路径版本感知）。

```mermaid
graph TD
    Client[客户端请求] -->|/api/v2025/users| GW[GKE Gateway]
    GW -->|匹配 PathPrefix: /api/v2025| Route[HTTPRoute]
    Route -->|URLRewrite: ReplacePrefix /api/v2025.11.23| Svc[Service: v2025.11.23]
    Svc --> Pod[Pod: v2025.11.23]
```

---

## 3. 平滑切换流程与配置示例 (Workflow & Configuration)

为实现**零停机（Zero-Downtime）**部署，必须严格遵循以下流程。核心原则是：**先部署验证，后原子切换**。

### 3.0 版本切换全流程视图

```mermaid
flowchart TD
    Start([开始版本升级]) --> PrepDeploy[准备新版本 Deployment]
    
    PrepDeploy --> CreateYAML[创建 Deployment YAML]
    CreateYAML --> ApplyDeploy[kubectl apply]
    
    ApplyDeploy --> WaitPods{等待 Pod Ready}
    WaitPods -->|超时| RollbackDeploy[回滚]
    WaitPods -->|Ready| CreateService[创建新版本 Service]
    
    CreateService --> ApplyService[绑定 Health/Backend Policies]
    ApplyService --> UpdateHTTPRoute[更新 HTTPRoute 配置]
    
    UpdateHTTPRoute --> Stage1[阶段 1: 灰度 20%]
    Stage1 --> Monitor{监控指标}
    
    Monitor -->|异常| Rollback[切回 100% 旧版本]
    Monitor -->|正常| Stage2[阶段 2: 全量切换 100%]
    
    Stage2 --> FinalVerify{最终验证}
    FinalVerify -->|稳定| Cleanup[清理旧资源]
    
    style Start fill:#4fc3f7,stroke:#0277bd,stroke-width:2px
    style Stage1 fill:#ffb74d,stroke:#ef6c00,stroke-width:2px
    style Stage2 fill:#81c784,stroke:#2e7d32,stroke-width:2px
    style Rollback fill:#ef5350,stroke:#b71c1c,stroke-width:2px
```

### 3.1 阶段一：资源准备 (Pre-deployment)

在此阶段，我们需要创建新版本的后端 Service 及其配套的 GKE Policy。

#### 1. 创建新版本 Service
新版本 Service (`service-v11-25`) 必须独立存在，不能覆盖旧版本。

```yaml
apiVersion: v1
kind: Service
metadata:
  name: service-v11-25
  namespace: abjx-int-common
spec:
  selector:
    app: api-name-sprint-samples-v11-25
  ports:
  - port: 8443
    targetPort: 8443
```

#### 2. 绑定 HealthCheckPolicy
**必须**为新 Service 显式定义健康检查策略。

```yaml
apiVersion: cloud.google.com/v1
kind: HealthCheckPolicy
metadata:
  name: hcp-service-v11-25
  namespace: abjx-int-common
spec:
  healthCheck:
    type: HTTP
    httpHealthCheck:
      port: 8443
      requestPath: /.well-known/healthcheck
  targetRef:
    group: ""
    kind: Service
    name: service-v11-25
```

#### 3. 绑定 GCPBackendPolicy
配置超时、连接排空（Connection Draining）等后端参数。

```yaml
apiVersion: cloud.google.com/v1
kind: GCPBackendPolicy
metadata:
  name: gbp-service-v11-25
  namespace: abjx-int-common
spec:
  backendConfig:
    # 这里配置具体的后端参数，例如超时时间
    timeoutSec: 40
  targetRef:
    group: ""
    kind: Service
    name: service-v11-25
```

#### 4. 验证就绪状态 (Pre-switch Verification)

在更新 `HTTPRoute` 进行一键切换前，运维/CI 必须执行以下检查，确保后端已具备承接公网流量的能力。

##### 4.1 验证 K8s 资源与 Endpoint
确保 Pod 已经成功启动并挂载到 Service 下。
```bash
# 1. 检查 Service 的 Endpoints 列表，确保 IP 数量符合预期
kubectl get endpoints service-v11-25 -n abjx-int-common

# 2. 检查 Pod 的就绪探针 (Readiness Probe) 状态
kubectl get pods -l app=api-name-sprint-samples-v11-25 -n abjx-int-common
```

##### 4.2 验证 Policy 绑定状态
检查 GKE Policy 是否成功被 Gateway 控制器 Accepted。
```bash
# 检查 HealthCheckPolicy 是否生效 (Status.Conditions 应为 Accepted: True)
kubectl describe healthcheckpolicy hcp-service-v11-25 -n abjx-int-common

# 检查 GCPBackendPolicy 状态
kubectl describe gcpbackendpolicy gbp-service-v11-25 -n abjx-int-common
```

##### 4.3 验证 GCP 后端 (NEG) 健康状况 (关键点)
GKE Gateway 模式通过 NEG 直接转发。在切流前，必须确保 GCP 负载均衡器的健康检查已通过。
```bash
# 1. 获取 Service 对应的 NEG 名称 (通常在 annotation 中)
kubectl get svc service-v11-25 -n abjx-int-common -o jsonpath='{.metadata.annotations.cloud\.google\.com/neg-status}'

# 2. (进阶) 使用 gcloud 或控制台验证 NEG 中的流量状态
# 确保所有 Endpoint 在 GCP 端显示为 HEALTHY
```

##### 4.4 内部预验证 (Shadow Test)
在不改动公网入口的情况下，内部直接访问 Service 测试。
```bash
# 使用 kubectl port-forward 直接请求新版本接口，验证业务逻辑是否正常
kubectl port-forward svc/service-v11-25 8443:8443 -n abjx-int-common
curl -vk https://localhost:8443/.well-known/healthcheck
```

---

### 3.2 阶段二：流量切换 (Traffic Switching)

**关键点：** 必须在**同一个 HTTPRoute 对象**上进行更新。

#### 场景：从 v11-24 升级到 v11-25

更新 HTTPRoute 的 `backendRefs` 和 `URLRewrite` 配置。

**更新前 (指向 v11-24):**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-name-sprint-samples-route-v2025
  namespace: abjx-int-common
spec:
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api-name-sprint-samples/v2025
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /api-name-sprint-samples/v2025.11.24/
    backendRefs:
    - name: service-v11-24
      port: 8443
      weight: 1
```

**更新后 (指向 v11-25):**
你可以选择直接替换，或者使用权重进行金丝雀发布。

*   **原子全量切换 (Atomic Switch)**:
    直接修改 `replacePrefixMatch` 为新路径，并将 `backendRefs` 修改为新 Service。

*   **金丝雀权重切换 (Canary Switch - 推荐)**:
    ```yaml
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: api-name-sprint-samples-route-v2025
      namespace: abjx-int-common
    spec:
      rules:
      - matches:
        - path:
            type: PathPrefix
            value: /api-name-sprint-samples/v2025
        # 注意：在使用权重分流到不同路径版本的 Service 时，
        # 单一的 URLRewrite 可能无法满足两个后端不同的重写需求。
        # 如果新旧版本路径不一致，建议直接全量切换，或者分阶段更新。
        # 这里展示全量切换后的最终状态：
        filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /api-name-sprint-samples/v2025.11.25/
        backendRefs:
        - name: service-v11-25  # 新服务
          port: 8443
          weight: 1
    ```

#### 流量分配机制

```mermaid
graph LR
    subgraph "HTTPRoute 流量分配逻辑"
        Input[100 个请求进入]
        
        Input -->|weight: 80| Old[80 个请求<br/>→ v11-24]
        Input -->|weight: 20| New[20 个请求<br/>→ v11-25]
        
        Old -->|Round Robin| OldPod1[Pod-1]
        New -->|Round Robin| NewPod1[Pod-1]
    end
    style Input fill:#bbdefb,stroke:#0d47a1,stroke-width:2px
    style Old fill:#ffccbc,stroke:#bf360c,stroke-width:2px
    style New fill:#c5e1a5,stroke:#33691e,stroke-width:2px
```

### 3.3 升级流程序列图

```mermaid
sequenceDiagram
    participant Dev as Ops/CI
    participant K8s as K8s API
    participant GW as GKE Gateway
    participant SvcOld as Old Service (v11-24)
    participant SvcNew as New Service (v11-25)

    Note over Dev, SvcNew: Phase 1: Resource Preparation
    Dev->>K8s: 1. Create Service (v11-25)
    Dev->>K8s: 2. Bind HealthCheck/BackendPolicy (v11-25)
    K8s->>SvcNew: Deploy Pods and register Endpoints
    K8s->>SvcNew: GCP starts health check probing
    SvcNew-->>K8s: Health Check Passed (Healthy)

    Note over Dev, SvcNew: Phase 2: Verification
    Dev->>K8s: Check Service and Policy status
    K8s->>Dev: Resources Ready

    Note over Dev, SvcNew: Phase 3: Switching
    Dev->>K8s: Update HTTPRoute (Point to v11-25)
    K8s->>GW: Atomically update forwarding rules
    
    par Smooth Traffic Migration
        GW->>SvcOld: Stop forwarding traffic
        GW->>SvcNew: Start forwarding traffic
    end

    Note over Dev, SvcNew: Phase 4: Verification & Cleanup
    Dev->>GW: Verify /v2025/health response
    Dev->>K8s: Delete Old Service (v11-24)
```
---
```mermaid
sequenceDiagram
    autonumber
    participant Dev as 运维 / CI Control
    participant K8s as K8s API Server
    participant GW as GKE Gateway (LB)
    participant SvcOld as 旧服务 (v11-24)
    participant SvcNew as 新服务 (v11-25)

    rect rgb(235, 245, 255)
        Note over Dev, SvcNew: 阶段一：资源准备 (Resource Preparation)
        Dev->>K8s: 创建 Service / HealthCheck / Policy (v11-25)
        K8s-->>SvcNew: 部署 Pods 并注册 Endpoint
        K8s-->>GW: GCP 探测器开始健康检查
        SvcNew-->>K8s: Health Check Passed (Healthy)
    end

    rect rgb(255, 255, 240)
        Note over Dev, SvcNew: 阶段二：预取验证 (Verification)
        Dev->>K8s: 检查 Service 与 Policy 状态
        K8s-->>Dev: 资源就绪且后端健康
    end

    rect rgb(235, 255, 235)
        Note over Dev, SvcNew: 阶段三：原子切换 (Traffic Switching)
        Dev->>K8s: 更新 HTTPRoute (指向 v11-25)
        K8s->>GW: 同步转发规则 (Atomic Update)
        
        par 流量平滑平移
            GW->>SvcOld: 按照 Draining 策略停止流量
            GW->>SvcNew: 开始分发流量至新版本
        end
    end

    rect rgb(255, 240, 240)
        Note over Dev, SvcNew: 阶段四：拨测与清理 (Post-deployment)
        Dev->>GW: 验证外部健康检查接口响应
        Dev->>K8s: 删除旧服务与关联资源 (v11-24)
    end
```

### 3.4 资源清理生命周期

```mermaid
timeline
    title 版本清理生命周期管理
    section 新版本部署
        T+0h : 部署 Deployment v2
             : 创建 Service v2
             : HTTPRoute 灰度 20%
    section 灰度验证
        T+2h : 增加至 100% 流量
    section 稳定观察
        T+24h : 移除旧 backendRef
    section 资源清理
        T+72h : 删除 Service v1
              : 删除 Deployment v1
```

---

## 4. 常见问题 (FAQ)

### Q1: 为什么不能新建一个 HTTPRoute 来发布新版本？
GKE Gateway 遵循 **Oldest Wins（最早创建者优先）** 原则。如果两个 HTTPRoute 配置了相同的 `host` 和 `path`，最早创建的那个会生效，后创建的会被忽略。因此，必须更新原有的 HTTPRoute 对象。

### Q2: 如何验证网关已准备就绪？
检查 HTTPRoute 的状态：
```bash
kubectl get httproute <name> -o jsonpath='{.status.parents[0].conditions}'
```
应确保 `Accepted` 为 `True` 且 `ResolvedRefs` 为 `True`。
同时可以使用 `curl` 命令验证：
```bash
curl -vk https://env-region.aliyun.cloud.uk.aibang/api-name-sprint-samples/v2025/health
```

### Q3: Ingress 和 Gateway API 在切换上有什么区别？
*   **Ingress**: 通常依赖 NGINX 的 Reload 或复杂的 Annotation 配置来实现灰度，重写规则能力较弱。
*   **Gateway API**: 原生支持多后端权重（Weight）分发，支持标准的 URLRewrite 过滤器，且状态反馈更清晰，更适合自动化发布。