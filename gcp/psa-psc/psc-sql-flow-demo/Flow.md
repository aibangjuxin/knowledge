# PSC Demo 流程图和架构说明

## 整体架构流程

```mermaid
graph TB
    subgraph "Producer Project (数据库项目)"
        SQL[Cloud SQL Instance]
        PSA[PSC Service Attachment]
        VPC1[Producer VPC]
        
        SQL --> PSA
        SQL -.-> VPC1
    end
    
    subgraph "Consumer Project (应用项目)"
        GKE[GKE Cluster]
        PSE[PSC Endpoint]
        VPC2[Consumer VPC]
        APP[Application Pods]
        SA[Service Account]
        
        GKE --> APP
        APP --> PSE
        PSE -.-> VPC2
        APP -.-> SA
    end
    
    subgraph "Google Cloud Infrastructure"
        PSC[Private Service Connect]
        WI[Workload Identity]
    end
    
    PSA -.-> PSC
    PSE -.-> PSC
    SA -.-> WI
    
    APP -->|Private Traffic| PSE
    PSE -->|PSC Connection| PSA
    PSA -->|Database Access| SQL
    
    style SQL fill:#e1f5fe
    style GKE fill:#f3e5f5
    style PSC fill:#fff3e0
    style APP fill:#e8f5e8
```

## 详细部署流程

### 阶段 1: 环境准备

```mermaid
sequenceDiagram
    participant User as 用户
    participant Env as 环境配置
    participant GCP as Google Cloud
    
    User->>Env: 1. 编辑 env-vars.sh
    Note over Env: 配置项目ID、区域等
    User->>Env: 2. source env-vars.sh
    Env->>User: 环境变量已加载
    
    User->>GCP: 3. 验证项目权限
    GCP->>User: 权限确认
```

### 阶段 2: Producer 项目设置

```mermaid
sequenceDiagram
    participant Script as setup-producer.sh
    participant GCP as Google Cloud
    participant SQL as Cloud SQL
    participant PSC as PSC Service
    
    Script->>GCP: 1. 启用 APIs
    Note over GCP: compute, sqladmin, servicenetworking
    
    Script->>GCP: 2. 创建 Producer VPC
    GCP->>Script: VPC 创建完成
    
    Script->>GCP: 3. 配置私有 IP 范围
    GCP->>Script: IP 范围分配完成
    
    Script->>SQL: 4. 创建 Cloud SQL 实例
    Note over SQL: MySQL 8.0, 私有 IP
    SQL->>Script: 实例创建完成
    
    Script->>SQL: 5. 启用 PSC
    SQL->>PSC: 创建 Service Attachment
    PSC->>Script: PSC 配置完成
    
    Script->>SQL: 6. 创建数据库和用户
    SQL->>Script: 数据库初始化完成
```

### 阶段 3: Consumer 项目设置

```mermaid
sequenceDiagram
    participant Script as setup-consumer.sh
    participant GCP as Google Cloud
    participant GKE as GKE Service
    participant PSC as PSC Service
    participant IAM as IAM Service
    
    Script->>GCP: 1. 启用 APIs
    Note over GCP: compute, container, privateconnect
    
    Script->>GCP: 2. 创建 Consumer VPC
    GCP->>Script: VPC 和子网创建完成
    
    Script->>GCP: 3. 创建静态 IP
    GCP->>Script: PSC 端点 IP 分配
    
    Script->>PSC: 4. 创建 PSC 端点
    Note over PSC: 连接到 Producer 的 Service Attachment
    PSC->>Script: PSC 端点创建完成
    
    Script->>GCP: 5. 配置防火墙规则
    GCP->>Script: 网络规则配置完成
    
    Script->>GKE: 6. 创建 GKE 集群
    Note over GKE: 启用 Workload Identity
    GKE->>Script: 集群创建完成
    
    Script->>IAM: 7. 配置 Service Account
    IAM->>Script: Workload Identity 配置完成
```

### 阶段 4: 应用部署

```mermaid
sequenceDiagram
    participant Script as deploy-app.sh
    participant Docker as Docker Registry
    participant K8s as Kubernetes
    participant App as Application
    
    Script->>Docker: 1. 构建应用镜像
    Docker->>Script: 镜像构建完成
    
    Script->>Docker: 2. 推送到 GCR
    Docker->>Script: 镜像推送完成
    
    Script->>K8s: 3. 创建 Namespace
    K8s->>Script: Namespace 创建完成
    
    Script->>K8s: 4. 部署 ConfigMap/Secret
    K8s->>Script: 配置部署完成
    
    Script->>K8s: 5. 部署 Service Account
    Note over K8s: 配置 Workload Identity 注解
    K8s->>Script: SA 部署完成
    
    Script->>K8s: 6. 部署应用 Deployment
    K8s->>App: 启动 Pod
    App->>K8s: 健康检查通过
    K8s->>Script: 应用部署完成
    
    Script->>K8s: 7. 部署 Service/HPA
    K8s->>Script: 所有资源部署完成
```

## 网络流量流程

### 应用启动流程

```mermaid
sequenceDiagram
    participant Pod as Application Pod
    participant CM as ConfigMap
    participant Secret as Secret
    participant PSC as PSC Endpoint
    participant SQL as Cloud SQL
    
    Pod->>CM: 1. 读取数据库配置
    CM->>Pod: DB_HOST, DB_PORT, DB_NAME
    
    Pod->>Secret: 2. 读取数据库密码
    Secret->>Pod: DB_PASSWORD
    
    Pod->>PSC: 3. 连接 PSC 端点
    Note over PSC: IP: 10.1.1.x:3306
    
    PSC->>SQL: 4. 转发到 Cloud SQL
    Note over SQL: 通过 PSC Service Attachment
    
    SQL->>PSC: 5. 建立连接
    PSC->>Pod: 连接成功
    
    Pod->>Pod: 6. 初始化连接池
    Pod->>Pod: 7. 启动 HTTP 服务器
```

### API 请求流程

```mermaid
sequenceDiagram
    participant Client as 客户端
    participant Service as K8s Service
    participant Pod as Application Pod
    participant Pool as 连接池
    participant SQL as Cloud SQL
    
    Client->>Service: 1. HTTP 请求
    Service->>Pod: 2. 路由到 Pod
    
    Pod->>Pool: 3. 获取数据库连接
    Pool->>SQL: 4. 执行 SQL 查询
    SQL->>Pool: 5. 返回查询结果
    Pool->>Pod: 6. 释放连接
    
    Pod->>Service: 7. HTTP 响应
    Service->>Client: 8. 返回结果
```

## 安全架构流程

### Workload Identity 认证流程

```mermaid
sequenceDiagram
    participant Pod as Application Pod
    participant KSA as K8s Service Account
    participant GSA as Google Service Account
    participant GCP as Google Cloud APIs
    
    Pod->>KSA: 1. 使用 K8s SA Token
    Note over KSA: 注解: iam.gke.io/gcp-service-account
    
    KSA->>GSA: 2. 映射到 Google SA
    Note over GSA: db-app-gsa@project.iam.gserviceaccount.com
    
    GSA->>GCP: 3. 访问 Google Cloud 服务
    Note over GCP: 权限: roles/cloudsql.client
    
    GCP->>GSA: 4. 返回访问令牌
    GSA->>Pod: 5. 提供服务访问权限
```

### 网络安全流程

```mermaid
graph TB
    subgraph "Pod Network Security"
        Pod[Application Pod]
        NP[Network Policy]
        FW[Firewall Rules]
    end
    
    subgraph "PSC Security"
        PSE[PSC Endpoint]
        SA[Service Attachment]
        AL[Allowed Projects]
    end
    
    subgraph "Database Security"
        SQL[Cloud SQL]
        PIP[Private IP Only]
        AUTH[Database Authentication]
    end
    
    Pod --> NP
    NP --> PSE
    PSE --> FW
    FW --> SA
    SA --> AL
    AL --> SQL
    SQL --> PIP
    SQL --> AUTH
    
    style NP fill:#ffebee
    style FW fill:#ffebee
    style AL fill:#ffebee
    style AUTH fill:#ffebee
```

## 监控和健康检查流程

### 健康检查流程

```mermaid
sequenceDiagram
    participant K8s as Kubernetes
    participant Pod as Application Pod
    participant Health as Health Endpoint
    participant DB as Database
    
    loop 每 30 秒
        K8s->>Pod: Liveness Probe
        Pod->>Health: GET /health
        Health->>DB: 测试数据库连接
        DB->>Health: 连接状态
        Health->>Pod: 健康状态响应
        Pod->>K8s: HTTP 200/500
        
        alt 健康检查失败
            K8s->>K8s: 重启 Pod
        end
    end
    
    loop 每 10 秒
        K8s->>Pod: Readiness Probe
        Pod->>Health: GET /ready
        Health->>Pod: 就绪状态
        Pod->>K8s: HTTP 200/500
        
        alt 就绪检查失败
            K8s->>K8s: 从 Service 移除 Pod
        end
    end
```

### 自动扩缩容流程

```mermaid
sequenceDiagram
    participant HPA as HPA Controller
    participant Metrics as Metrics Server
    participant Pod as Application Pods
    participant Deploy as Deployment
    
    loop 每 15 秒
        HPA->>Metrics: 获取 Pod 指标
        Metrics->>Pod: 收集 CPU/内存使用率
        Pod->>Metrics: 返回指标数据
        Metrics->>HPA: 聚合指标
        
        alt CPU > 70% 或 Memory > 80%
            HPA->>Deploy: 增加副本数
            Deploy->>Pod: 创建新 Pod
        else CPU < 50% 且 Memory < 60%
            HPA->>Deploy: 减少副本数
            Deploy->>Pod: 删除多余 Pod
        end
    end
```

## 故障排除流程

### 连接问题诊断流程

```mermaid
flowchart TD
    Start[应用无法连接数据库] --> CheckPod{Pod 状态正常?}
    
    CheckPod -->|否| PodIssue[检查 Pod 日志和事件]
    CheckPod -->|是| CheckConfig{配置正确?}
    
    CheckConfig -->|否| FixConfig[更新 ConfigMap/Secret]
    CheckConfig -->|是| CheckNetwork{网络连通性?}
    
    CheckNetwork -->|否| NetworkIssue[检查防火墙和 PSC]
    CheckNetwork -->|是| CheckDB{数据库状态?}
    
    CheckDB -->|异常| DBIssue[检查 Cloud SQL 状态]
    CheckDB -->|正常| CheckAuth{认证问题?}
    
    CheckAuth -->|是| AuthIssue[检查 Workload Identity]
    CheckAuth -->|否| DeepDebug[深度调试]
    
    PodIssue --> Restart[重启 Pod]
    FixConfig --> Restart
    NetworkIssue --> FixNetwork[修复网络配置]
    DBIssue --> FixDB[修复数据库问题]
    AuthIssue --> FixAuth[修复认证配置]
    
    Restart --> Test[测试连接]
    FixNetwork --> Test
    FixDB --> Test
    FixAuth --> Test
    DeepDebug --> Test
    
    Test --> Success[问题解决]
```

## 清理流程

### 资源清理顺序

```mermaid
sequenceDiagram
    participant Script as cleanup.sh
    participant K8s as Kubernetes
    participant GKE as GKE Service
    participant GCP as Google Cloud
    participant SQL as Cloud SQL
    
    Script->>K8s: 1. 删除 Namespace
    Note over K8s: 删除所有应用资源
    K8s->>Script: Namespace 删除完成
    
    Script->>GKE: 2. 删除 GKE 集群
    GKE->>Script: 集群删除完成
    
    Script->>GCP: 3. 删除 PSC 端点
    GCP->>Script: PSC 端点删除完成
    
    Script->>GCP: 4. 删除网络资源
    Note over GCP: 防火墙规则、静态IP、VPC
    GCP->>Script: 网络资源删除完成
    
    opt 用户选择删除数据库
        Script->>SQL: 5. 删除 Cloud SQL 实例
        SQL->>Script: 数据库删除完成
    end
    
    Script->>Script: 6. 清理本地配置文件
```

## 最佳实践流程

### 生产部署检查清单

```mermaid
flowchart TD
    Start[开始生产部署] --> Security{安全检查}
    
    Security --> SecOK{✓ Workload Identity<br/>✓ Network Policy<br/>✓ Secret 管理}
    SecOK --> Reliability{可靠性检查}
    
    Reliability --> RelOK{✓ 健康检查<br/>✓ 资源限制<br/>✓ 反亲和性}
    RelOK --> Monitoring{监控检查}
    
    Monitoring --> MonOK{✓ 日志聚合<br/>✓ 指标收集<br/>✓ 告警配置}
    MonOK --> Performance{性能检查}
    
    Performance --> PerfOK{✓ 连接池配置<br/>✓ HPA 配置<br/>✓ 资源优化}
    PerfOK --> Deploy[部署到生产环境]
    
    Deploy --> Validate[验证部署]
    Validate --> Success[部署成功]
    
    Security -->|不通过| FixSec[修复安全问题]
    Reliability -->|不通过| FixRel[修复可靠性问题]
    Monitoring -->|不通过| FixMon[修复监控问题]
    Performance -->|不通过| FixPerf[修复性能问题]
    
    FixSec --> Security
    FixRel --> Reliability
    FixMon --> Monitoring
    FixPerf --> Performance
```

这个流程图详细展示了整个 PSC Demo 的各个阶段和组件之间的关系，帮助你更好地理解整个架构和部署过程。