直接给你可以复制粘贴到 `.md` 的 Mermaid 源码：

```mermaid
flowchart TB
  Client(["🌐 Client / PSC Consumer"])
  ILB["⚖️ Internal LB\nGKE ILB / PSC"]

  subgraph istio-system ["🔧 istio-system namespace"]
    direction LR
    istiod["istiod\n控制面 / xDS 下发"]
    webhook["MutatingWebhook\nsidecar 注入"]
  end

  subgraph abjx-int ["📦 namespace: abjx-int  ·  istio.io/rev=asm-managed"]
    direction TB

    subgraph gw-layer ["🚪 网关层 Gateway"]
      direction LR
      GW_SVC["Service\nabjx-int-gw\ntype: LoadBalancer"]
      GW_DEP["Deployment\nabjx-int-gw\nEnvoy Pod × 2"]
      GW_CR["Gateway CR\nabjx-int-gw\nhost / port / TLS"]
      TLS_SECRET["Secret 可选\nabjx-int-gw-tls\nTLS 证书"]
    end

    subgraph route-layer ["🗺️ Istio 路由配置层"]
      direction LR
      VS["VirtualService\nabjx-health-check-api-vs\ngateways: abjx-int-gw"]
      PA["PeerAuthentication 可选\nmode: STRICT\n确认全注入后启用"]
    end

    subgraph api-layer ["🛠️ 业务服务层 API"]
      direction LR
      API_DEP["Deployment\nabjx-health-check-api\nreplicas:2 + istio-proxy"]
      API_SVC["Service\nabjx-health-check-api\nport:80  name:http"]
      PDB["PDB 可选\nminAvailable: 1\n防止驱逐"]
    end
  end

  Client -->|"HTTPS / HTTP"| ILB
  ILB -->|"内网流量"| GW_SVC
  GW_SVC -->|"selector match"| GW_DEP
  GW_CR -. "配置监听规则" .-> GW_DEP
  TLS_SECRET -. "credentialName" .-> GW_CR
  GW_DEP -->|"路由匹配"| VS
  VS -->|"转发"| API_SVC
  API_SVC -->|"负载均衡"| API_DEP
  istiod -. "xDS 下发" .-> GW_DEP
  istiod -. "xDS 下发" .-> API_DEP
  webhook -. "注入 sidecar" .-> API_DEP

  classDef ext  fill:#F1EFE8,stroke:#5F5E5A,color:#2C2C2A
  classDef ctrl fill:#EEEDFE,stroke:#534AB7,color:#26215C
  classDef gw   fill:#E1F5EE,stroke:#0F6E56,color:#04342C
  classDef cfg  fill:#FAEEDA,stroke:#854F0B,color:#412402
  classDef api  fill:#E6F1FB,stroke:#185FA5,color:#042C53
  classDef opt  fill:#F1EFE8,stroke:#888780,color:#444441,stroke-dasharray:4 3

  class Client,ILB ext
  class istiod,webhook ctrl
  class GW_SVC,GW_DEP gw
  class GW_CR,VS cfg
  class API_DEP,API_SVC api
  class TLS_SECRET,PA,PDB opt
```

---

**颜色说明**（`classDef` 对应关系）：

| class | 颜色 | 含义 |
|-------|------|------|
| `ext` | 灰色 | 集群外部：Client、ILB |
| `ctrl` | 紫色 | 控制面：istiod、Webhook |
| `gw` | 绿色 | 网关工作负载：Service、Deployment |
| `cfg` | 橙色 | Istio 配置对象：Gateway CR、VirtualService |
| `api` | 蓝色 | 业务服务：API Deployment、Service |
| `opt` | 灰色虚线 | 可选资源：Secret、PeerAuthentication、PDB |

这份 Mermaid 在 GitHub、GitLab、Obsidian、Typora 等主流 Markdown 渲染器里都可以直接显示颜色。


# ASM on GKE — 资源分层部署图 (Mermaid)

本文档通过 Mermaid 图表展示 ASM 部署中各类资源在 Namespace 下的分布关系，帮助更清晰地理解部署架构。

---

## 1. Namespace 分层总览

```mermaid
flowchart TB
    subgraph GKE["GKE Cluster"]
        subgraph istio-system["istio-system (Control Plane)"]
            istiod["istiod<br/>(ASM Control Plane)"]
        end
        
        subgraph abjx-int["abjx-int (Tenant Namespace)"]
            direction TB
            subgraph workload["Workloads"]
                api Deploy["Deployment<br/>abjx-health-check-api"]
                gw DeployGW["Deployment<br/>abjx-int-gw"]
            end
            
            subgraph svc["Services"]
                api SVC["Service<br/>abjx-health-check-api"]
                gw SVCGW["Service<br/>abjx-int-gw<br/>(ILB/ClusterIP)"]
            end
            
            subgraph asmcr["ASM CRDs"]
                gw CR["Gateway CR<br/>abjx-int-gw"]
                vs["VirtualService<br/>abjx-health-check-api-vs"]
                pa["PeerAuthentication<br/>default (可选)"]
            end
            
            subgraph sec["Secrets"]
                tls["Secret<br/>abjx-int-gw-tls<br/>(可选)"]
            end
        end
    end
    
    istiod -.->|"xDS Config"| gw DeployGW
    istiod -.->|"xDS Config"| Deploy
```

---

## 2. 资源分布详情

### 2.1 Namespace 层级

```mermaid
flowchart TB
    subgraph Cluster["GKE Cluster"]
        NS1["istio-system"]
        NS2["abjx-int"]
        
        subgraph NS1
            istiod1["istiod"]
        end
        
        subgraph NS2
            direction LR
            R1["Deployment<br/>abjx-health-check-api"]
            R2["Service<br/>abjx-health-check-api"]
            R3["Deployment<br/>abjx-int-gw"]
            R4["Service<br/>abjx-int-gw"]
            R5["Gateway CR"]
            R6["VirtualService"]
            R7["Secret (TLS)"]
            R8["PeerAuthentication"]
        end
    end
```

---

## 3. 资源与 Namespace 对照表

```mermaid
erDiagram
    NAMESPACE ||--o{ DEPLOYMENT : contains
    NAMESPACE ||--o{ SERVICE : contains
    NAMESPACE ||--o{ GATEWAY : contains
    NAMESPACE ||--o{ VIRTUALSERVICE : contains
    NAMESPACE ||--o{ SECRET : contains
    NAMESPACE ||--o{ PEERAUTHENTICATION : contains
    
    NAMESPACE {
        string name
        string istio_rev
    }
    
    DEPLOYMENT {
        string name
        string namespace
        string app_label
    }
    
    SERVICE {
        string name
        string namespace
        string type
    }
    
    GATEWAY {
        string name
        string namespace
        string selector
    }
    
    VIRTUALSERVICE {
        string name
        string namespace
        string gateway_ref
    }
    
    SECRET {
        string name
        string namespace
        string type
    }
    
    PEERAUTHENTICATION {
        string name
        string namespace
        string mtls_mode
    }
```

---

## 4. 数据流与控制流

### 4.1 控制面配置流

```mermaid
flowchart LR
    subgraph ControlPlane["Control Plane"]
        istiod
    end
    
    subgraph ConfigObjects["ASM CRDs (abjx-int)"]
        GW["Gateway CR<br/>abjx-int-gw"]
        VS["VirtualService<br/>abjx-health-check-api-vs"]
        PA["PeerAuthentication<br/>(可选)"]
    end
    
    subgraph DataPlane["Data Plane (abjx-int)"]
        subgraph GatewayWorkload["Gateway Workload"]
            GWPod["Gateway Pod<br/>(Envoy)"]
        end
        subgraph AppWorkload["App Workload"]
            AppPod["App Pod<br/>(+ istio-proxy)"]
        end
    end
    
    istiod -->|"1. Watch"| GW
    istiod -->|"2. Watch"| VS
    istiod -->|"3. Watch"| PA
    istiod -->|"4. xDS Protocol"| GWPod
    GWPod -.->|"5. Route Config"| VS
```

### 4.2 数据面流量

```mermaid
sequenceDiagram
    participant Client as Client / PSC
    participant ILB as Internal LB
    participant GWSvc as Service: abjx-int-gw
    participant GWPod as Gateway Pod (Envoy)
    participant AppSvc as Service: abjx-health-check-api
    participant AppPod as App Pod
    
    Client->>ILB: 1. Request (Host: abjx-int.internal...)
    ILB->>GWSvc: 2. Forward to ClusterIP
    GWSvc->>GWPod: 3. Route to Gateway Pod
    GWPod->>AppSvc: 4. Match VS Route
    AppSvc->>AppPod: 5. Forward to Backend
    AppPod-->>GWPod: 6. Response
    GWPod-->>ILB: 7. Response
    ILB-->>Client: 8. Response
```

---

## 5. 资源部署顺序

```mermaid
flowchart LR
    subgraph Phase1["Phase 1: 基础设施"]
        N1["1. Namespace<br/>abjx-int"]
    end
    
    subgraph Phase2["Phase 2: 业务应用"]
        D1["2. Deployment<br/>abjx-health-check-api"]
        S1["3. Service<br/>abjx-health-check-api"]
    end
    
    subgraph Phase3["Phase 3: 网关"]
        D2["4. Deployment<br/>abjx-int-gw"]
        S2["5. Service<br/>abjx-int-gw"]
    end
    
    subgraph Phase4["Phase 4: ASM 配置"]
        G["6. Gateway CR"]
        V["7. VirtualService"]
    end
    
    subgraph Phase5["Phase 5: 安全 (可选)"]
        T["8. Secret (TLS)"]
        P["9. PeerAuthentication"]
    end
    
    N1 --> D1
    D1 --> S1
    S1 --> D2
    D2 --> S2
    S2 --> G
    G --> V
    V --> T
    T --> P
```

---

## 6. 资源清单汇总

### 6.1 abjx-int Namespace

| 资源类型 | 名称 | 说明 |
|----------|------|------|
| `Namespace` | `abjx-int` | 租户隔离 namespace |
| `Deployment` | `abjx-health-check-api` | 业务 API 应用 |
| `Service` | `abjx-health-check-api` | 业务 API 服务暴露 |
| `Deployment` | `abjx-int-gw` | Gateway Envoy 工作负载 |
| `Service` | `abjx-int-gw` | Gateway 服务 (ILB/ClusterIP) |
| `Gateway` | `abjx-int-gw` | Gateway CR 定义监听 |
| `VirtualService` | `abjx-health-check-api-vs` | 路由规则绑定 Gateway |
| `Secret` | `abjx-int-gw-tls` | TLS 证书 (HTTPS 时) |
| `PeerAuthentication` | `default` | mTLS 配置 (可选) |

### 6.2 istio-system Namespace

| 资源类型 | 名称 | 说明 |
|----------|------|------|
| `Deployment` | `istiod` | ASM 控制面 |
| `Service` | `istiod` | 控制面服务 |

---

## 7. 关键映射关系

```mermaid
flowchart TB
    subgraph Gateway_Resource_Mapping
        GWCR["Gateway CR<br/>name: abjx-int-gw<br/>namespace: abjx-int"]
        GWSelector["spec.selector.istio<br/>= abjx-int-gw"]
        GWDeploy["Deployment<br/>name: abjx-int-gw<br/>label: istio=abjx-int-gw"]
        GWSvc["Service<br/>name: abjx-int-gw<br/>selector: istio=abjx-int-gw"]
    end
    
    GWCR --> GWSelector
    GWSelector -.->|"匹配"| GWDeploy
    GWDeploy -->|"暴露"| GWSvc
    
    subgraph VirtualService_Binding
        VS["VirtualService<br/>name: abjx-health-check-api-vs<br/>spec.gateways: abjx-int-gw"]
        VSRoute["spec.http.route<br/>destination.host<br/>= abjx-health-check-api.abjx-int.svc"]
    end
    
    VS --> VSRoute
```

---

## 8. 快速参考

### 资源查找命令

```bash
# 查看 abjx-int namespace 所有资源
kubectl get all,gateways,virtualservices,secrets -n abjx-int

# 查看 Gateway CR 配置
kubectl get gateway abjx-int-gw -n abjx-int -o yaml

# 查看 VirtualService 配置
kubectl get virtualservice abjx-health-check-api-vs -n abjx-int -o yaml

# 验证 selector 匹配
kubectl get gateway abjx-int-gw -n abjx-int -o jsonpath='{.spec.selector}'
kubectl get pods -n abjx-int -l istio=abjx-int-gw
```
