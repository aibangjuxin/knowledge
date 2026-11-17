# GKE KSA IAM Based Authentication Flow

基于验证脚本逆推的 GKE Kubernetes Service Account (KSA) IAM based authentication 逻辑流程图。

## 架构流程图

```mermaid
graph TB
    subgraph "GKE Project (project-a)"
        A[GKE Cluster] --> B[Namespace]
        B --> C[Deployment]
        C --> D[Pod]
        D --> E[KSA: my-app-ksa]
        
        E -.->|iam.gke.io/gcp-service-account| F[Annotation]
        F --> G["GCP SA: my-sa\@project-b.iam.gserviceaccount.com"]
    end
    
    subgraph "Service Account Project (project-b)"
        G --> H[GCP Service Account]
        H --> I[Project Level IAM Roles]
        H --> J[SA Level IAM Policy]
        
        I --> K[roles/secretmanager.secretAccessor]
        I --> L[roles/storage.objectViewer]
        I --> M[Custom Roles...]
        
        J --> N[Workload Identity User Binding]
        N --> O["serviceAccount:project-a.svc.id.goog[namespace/my-app-ksa]"]
    end
    
    subgraph "Resource Access"
        H --> P[Secret Manager]
        H --> Q[Cloud Storage]
        H --> R[Other GCP Resources]
        
        P --> S[Secrets in project-b]
        P --> T[Cross-project Secrets]
    end
    
    subgraph "Authentication Flow"
        U[Pod Request] --> V[GKE Metadata Server]
        V --> W[Token Exchange]
        W --> X[GCP Access Token]
        X --> Y[Resource Access]
    end
    
    %% Connections
    D --> U
    G -.->|Cross-project binding| N
    H --> V
    Y --> P
    Y --> Q
    Y --> R
    
    %% Styling
    classDef gkeProject fill:#e1f5fe
    classDef saProject fill:#f3e5f5
    classDef resources fill:#e8f5e8
    classDef flow fill:#fff3e0
    
    class A,B,C,D,E,F gkeProject
    class G,H,I,J,K,L,M,N,O saProject
    class P,Q,R,S,T resources
    class U,V,W,X,Y flow
```

## 详细验证步骤流程

```mermaid
sequenceDiagram
    participant Script as 验证脚本
    participant K8s as Kubernetes API
    participant GKE as GKE Project
    participant SA as SA Project
    participant IAM as IAM Service
    
    Script->>K8s: 1. 获取 Deployment
    K8s-->>Script: Deployment 配置
    
    Script->>K8s: 2. 获取 KSA
    K8s-->>Script: serviceAccountName
    
    Script->>K8s: 3. 获取 KSA Annotation
    K8s-->>Script: iam.gke.io/gcp-service-account
    
    Script->>Script: 4. 拆分 GCP SA
    Note over Script: 提取 SA 名称和项目ID
    
    alt SA Project != GKE Project
        Note over Script,SA: IAM Based Authentication 检测到
        
        Script->>SA: 5a. 检查 SA 项目 IAM
        SA-->>Script: 项目级 IAM 角色
        
        Script->>IAM: 5b. 检查 SA IAM 策略
        IAM-->>Script: SA 级 IAM 策略
        
        Script->>GKE: 5c. 检查跨项目权限
        GKE-->>Script: GKE 项目中的 SA 权限
        
        Script->>IAM: 5d. 验证 Workload Identity
        IAM-->>Script: workloadIdentityUser 绑定
        
    else SA Project == GKE Project
        Note over Script,GKE: 同项目认证
        Script->>GKE: 检查同项目 IAM
        GKE-->>Script: 项目内权限
    end
    
    Script->>SA: 6. 检查资源访问权限
    SA-->>Script: Secret Manager, Storage 等
    
    Script->>Script: 7. 生成验证报告
    Note over Script: 输出认证类型和权限摘要
```

## 权限验证矩阵

```mermaid
graph LR
    subgraph "验证维度"
        A[KSA 绑定] --> B[GCP SA 存在]
        B --> C[项目识别]
        C --> D{跨项目?}
        
        D -->|是| E[IAM Based Auth]
        D -->|否| F[同项目认证]
        
        E --> G[验证跨项目权限]
        E --> H[验证 Workload Identity]
        E --> I[验证资源访问]
        
        F --> J[验证项目内权限]
        F --> K[验证资源访问]
        
        G --> L[权限报告]
        H --> L
        I --> L
        J --> L
        K --> L
    end
    
    classDef decision fill:#ffeb3b
    classDef process fill:#4caf50
    classDef result fill:#2196f3
    
    class D decision
    class A,B,C,E,F,G,H,I,J,K process
    class L result
```

## 关键配置要素

### 1. KSA Annotation
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-ksa
  namespace: my-namespace
  annotations:
    iam.gke.io/gcp-service-account: my-sa@project-b.iam.gserviceaccount.com
```

### 2. Workload Identity 绑定
```bash
gcloud iam service-accounts add-iam-policy-binding \
    my-sa@project-b.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:project-a.svc.id.goog[my-namespace/my-app-ksa]"
```

### 3. 资源权限
```bash
gcloud projects add-iam-policy-binding project-b \
    --member "serviceAccount:my-sa@project-b.iam.gserviceaccount.com" \
    --role "roles/secretmanager.secretAccessor"
```

## 验证要点

1. **跨项目识别**: SA 邮箱中的项目ID与GKE项目ID不同
2. **Workload Identity**: 必须有正确的 workloadIdentityUser 绑定
3. **权限传递**: SA 在其所属项目中的权限会传递给 Pod
4. **资源访问**: 验证实际的资源访问权限（Secret Manager, Storage 等）