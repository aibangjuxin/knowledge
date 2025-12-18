# GKE Gateway API 版本管理完整流程可视化

## 整体架构图

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

---

## 流量分配机制详解

```mermaid
graph LR
    subgraph "HTTPRoute 流量分配逻辑"
        Input[100 个请求进入]
        
        Input -->|weight: 80| Old[80 个请求<br/>→ Service 2025-11-19]
        Input -->|weight: 20| New[20 个请求<br/>→ Service 2025-12-18]
        
        Old -->|Round Robin| OldPod1[Pod-1]
        Old -->|Round Robin| OldPod2[Pod-2]
        Old -->|Round Robin| OldPod3[Pod-3]
        
        New -->|Round Robin| NewPod1[Pod-1]
        New -->|Round Robin| NewPod2[Pod-2]
        New -->|Round Robin| NewPod3[Pod-3]
    end
    
    style Input fill:#bbdefb,stroke:#0d47a1,stroke-width:3px
    style Old fill:#ffccbc,stroke:#bf360c,stroke-width:2px
    style New fill:#c5e1a5,stroke:#33691e,stroke-width:2px
    style OldPod1 fill:#ffecb3,stroke:#ff6f00
    style OldPod2 fill:#ffecb3,stroke:#ff6f00
    style OldPod3 fill:#ffecb3,stroke:#ff6f00
    style NewPod1 fill:#dcedc8,stroke:#558b2f
    style NewPod2 fill:#dcedc8,stroke:#558b2f
    style NewPod3 fill:#dcedc8,stroke:#558b2f
```

---

## 完整灰度发布生命周期
---

## HTTPRoute 配置演进时间线

```mermaid
gantt
    title API 版本灰度发布时间线
    dateFormat HH:mm
    axisFormat %H:%M
    
    section 部署阶段
    部署新版本 Deployment        :done, deploy, 00:00, 10m
    创建新版本 Service           :done, svc, 00:10, 5m
    验证 Pod 健康状态            :done, health, 00:15, 5m
    
    section 灰度发布
    配置 20% 流量到新版本        :active, canary20, 00:20, 30m
    监控错误率和延迟             :active, monitor20, 00:20, 30m
    
    section 流量增加
    增加至 50% 流量              :canary50, 00:50, 30m
    持续监控性能指标             :monitor50, 00:50, 30m
    
    section 进一步验证
    增加至 80% 流量              :canary80, 01:20, 30m
    全面性能测试                 :monitor80, 01:20, 30m
    
    section 完全切换
    100% 流量切换到新版本        :switch100, 01:50, 15m
    最终验证                     :final, 02:05, 25m
    
    section 清理阶段
    移除旧版本 backendRef        :cleanup1, 02:30, 5m
    删除旧版本 Service           :cleanup2, 02:35, 5m
    删除旧版本 Deployment        :cleanup3, 02:40, 10m
```

---

## 请求路由决策树

```mermaid
graph TD
    Start([客户端请求到达]) --> CheckHost{检查 Hostname<br/>dev.goole.cloud.uk.aibang}
    
    CheckHost -->|匹配| CheckPath{检查 Path<br/>/api-name-type-ri-sb-samples}
    CheckHost -->|不匹配| Reject1[404 Not Found]
    
    CheckPath -->|PathPrefix 匹配| HTTPRouteMatch[HTTPRoute 规则匹配]
    CheckPath -->|不匹配| Reject2[404 Not Found]
    
    HTTPRouteMatch --> WeightCalc{流量权重计算}
    
    WeightCalc -->|80%| RouteOld[路由到旧版本<br/>Service 2025-11-19]
    WeightCalc -->|20%| RouteNew[路由到新版本<br/>Service 2025-12-18]
    
    RouteOld --> EndpointOld{Service Endpoints<br/>健康检查}
    RouteNew --> EndpointNew{Service Endpoints<br/>健康检查}
    
    EndpointOld -->|有可用 Pod| PodOld[转发到旧版本 Pod]
    EndpointOld -->|无可用 Pod| Error503Old[503 Service Unavailable]
    
    EndpointNew -->|有可用 Pod| PodNew[转发到新版本 Pod]
    EndpointNew -->|无可用 Pod| Error503New[503 Service Unavailable]
    
    PodOld --> ResponseOld[返回响应]
    PodNew --> ResponseNew[返回响应]
    
    style Start fill:#e3f2fd,stroke:#1565c0,stroke-width:3px
    style HTTPRouteMatch fill:#f3e5f5,stroke:#6a1b9a,stroke-width:3px
    style WeightCalc fill:#fff3e0,stroke:#e65100,stroke-width:3px
    style RouteOld fill:#ffebee,stroke:#c62828,stroke-width:2px
    style RouteNew fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style PodOld fill:#fce4ec,stroke:#880e4f
    style PodNew fill:#c8e6c9,stroke:#1b5e20
    style ResponseOld fill:#f8bbd0,stroke:#ad1457
    style ResponseNew fill:#a5d6a7,stroke:#388e3c
    style Reject1 fill:#ffcdd2,stroke:#b71c1c
    style Reject2 fill:#ffcdd2,stroke:#b71c1c
    style Error503Old fill:#ff8a80,stroke:#d32f2f
    style Error503New fill:#ff8a80,stroke:#d32f2f
```

---

## 版本切换操作流程图

```mermaid
flowchart TD
    Start([开始版本升级]) --> PrepDeploy[准备新版本 Deployment]
    
    PrepDeploy --> CreateYAML[创建 Deployment YAML<br/>version: 2025-12-18]
    CreateYAML --> ApplyDeploy[kubectl apply -f deployment.yaml]
    
    ApplyDeploy --> WaitPods{等待 Pod Ready}
    WaitPods -->|超时| RollbackDeploy[回滚 Deployment]
    WaitPods -->|Ready| CreateService[创建新版本 Service]
    
    CreateService --> ApplyService[kubectl apply -f service.yaml]
    ApplyService --> UpdateHTTPRoute[更新 HTTPRoute 配置]
    
    UpdateHTTPRoute --> Stage1[阶段 1: 灰度 20%]
    Stage1 --> Monitor1{监控 15-30 分钟}
    
    Monitor1 -->|错误率高| EmergencyRollback[紧急回滚<br/>weight: 100 to old]
    Monitor1 -->|指标正常| Stage2[阶段 2: 增加至 50%]
    
    Stage2 --> Monitor2{监控 30 分钟}
    Monitor2 -->|性能下降| ReduceTraffic[降低至 20%]
    Monitor2 -->|持续稳定| Stage3[阶段 3: 增加至 80%]
    
    ReduceTraffic --> Monitor1
    
    Stage3 --> Monitor3{监控 30 分钟}
    Monitor3 -->|出现问题| ReduceTraffic2[降低至 50%]
    Monitor3 -->|全面验证通过| Stage4[阶段 4: 完全切换 100%]
    
    ReduceTraffic2 --> Monitor2
    
    Stage4 --> Monitor4{观察期 24-48 小时}
    Monitor4 -->|严重问题| FullRollback[完全回滚]
    Monitor4 -->|稳定运行| CleanupOld[清理旧版本资源]
    
    CleanupOld --> DeleteBackendRef[移除 HTTPRoute 旧 backendRef]
    DeleteBackendRef --> DeleteService[删除旧版本 Service]
    DeleteService --> DeleteDeploy[删除旧版本 Deployment]
    
    DeleteDeploy --> End([升级完成])
    
    RollbackDeploy --> End
    EmergencyRollback --> End
    FullRollback --> End
    
    style Start fill:#4fc3f7,stroke:#0277bd,stroke-width:3px
    style Stage1 fill:#ffb74d,stroke:#ef6c00,stroke-width:2px
    style Stage2 fill:#ffa726,stroke:#e65100,stroke-width:2px
    style Stage3 fill:#ff9800,stroke:#d84315,stroke-width:2px
    style Stage4 fill:#81c784,stroke:#2e7d32,stroke-width:3px
    style Monitor1 fill:#fff9c4,stroke:#f9a825
    style Monitor2 fill:#fff9c4,stroke:#f9a825
    style Monitor3 fill:#fff9c4,stroke:#f9a825
    style Monitor4 fill:#fff9c4,stroke:#f9a825
    style EmergencyRollback fill:#ef5350,stroke:#b71c1c,stroke-width:3px
    style FullRollback fill:#ef5350,stroke:#b71c1c,stroke-width:3px
    style End fill:#66bb6a,stroke:#1b5e20,stroke-width:3px
```

---

## 多版本并存架构图

```mermaid
graph TB
    subgraph "命名空间: ns-int-common-ms"
        subgraph "Gateway & Routing"
            GW[Gateway<br/>abjx-common-gateway]
            HR[HTTPRoute<br/>版本路由控制器]
        end
        
        subgraph "Version 2025-11-19 旧版本"
            Deploy1[Deployment<br/>api-samples-2025-11-19<br/>replicas: 3]
            Svc1[Service<br/>port: 443]
            
            Deploy1 --> Pod1_1[Pod 1<br/>v2025-11-19]
            Deploy1 --> Pod1_2[Pod 2<br/>v2025-11-19]
            Deploy1 --> Pod1_3[Pod 3<br/>v2025-11-19]
            
            Svc1 -.selector.-> Pod1_1
            Svc1 -.selector.-> Pod1_2
            Svc1 -.selector.-> Pod1_3
        end
        
        subgraph "Version 2025-12-18 新版本"
            Deploy2[Deployment<br/>api-samples-2025-12-18<br/>replicas: 3]
            Svc2[Service<br/>port: 443]
            
            Deploy2 --> Pod2_1[Pod 1<br/>v2025-12-18]
            Deploy2 --> Pod2_2[Pod 2<br/>v2025-12-18]
            Deploy2 --> Pod2_3[Pod 3<br/>v2025-12-18]
            
            Svc2 -.selector.-> Pod2_1
            Svc2 -.selector.-> Pod2_2
            Svc2 -.selector.-> Pod2_3
        end
        
        subgraph "Version 2026-01-15 预发布"
            Deploy3[Deployment<br/>api-samples-2026-01-15<br/>replicas: 2]
            Svc3[Service<br/>port: 443]
            
            Deploy3 --> Pod3_1[Pod 1<br/>v2026-01-15]
            Deploy3 --> Pod3_2[Pod 2<br/>v2026-01-15]
            
            Svc3 -.selector.-> Pod3_1
            Svc3 -.selector.-> Pod3_2
        end
    end
    
    GW --> HR
    HR -->|weight: 70| Svc1
    HR -->|weight: 25| Svc2
    HR -->|weight: 5| Svc3
    
    style GW fill:#9c27b0,stroke:#4a148c,color:#fff,stroke-width:3px
    style HR fill:#7b1fa2,stroke:#4a148c,color:#fff,stroke-width:2px
    
    style Deploy1 fill:#ffccbc,stroke:#d84315,stroke-width:2px
    style Svc1 fill:#ff8a65,stroke:#bf360c,stroke-width:2px
    style Pod1_1 fill:#ffab91,stroke:#d84315
    style Pod1_2 fill:#ffab91,stroke:#d84315
    style Pod1_3 fill:#ffab91,stroke:#d84315
    
    style Deploy2 fill:#c5e1a5,stroke:#558b2f,stroke-width:2px
    style Svc2 fill:#9ccc65,stroke:#33691e,stroke-width:2px
    style Pod2_1 fill:#aed581,stroke:#558b2f
    style Pod2_2 fill:#aed581,stroke:#558b2f
    style Pod2_3 fill:#aed581,stroke:#558b2f
    
    style Deploy3 fill:#b3e5fc,stroke:#0277bd,stroke-width:2px
    style Svc3 fill:#81d4fa,stroke:#01579b,stroke-width:2px
    style Pod3_1 fill:#4fc3f7,stroke:#0277bd
    style Pod3_2 fill:#4fc3f7,stroke:#0277bd
```

---

## 监控与回滚决策流程

```mermaid
flowchart TD
    Start([灰度发布启动]) --> Monitor[开始监控新版本]
    
    Monitor --> CollectMetrics[收集关键指标]
    
    CollectMetrics --> ErrorRate{错误率检查}
    CollectMetrics --> Latency{延迟检查}
    CollectMetrics --> CPU{CPU 使用率}
    CollectMetrics --> Memory{内存使用率}
    
    ErrorRate -->|> 5%| Alert1[触发告警]
    ErrorRate -->|≤ 5%| CheckLatency
    
    Latency -->|> P99 阈值| Alert2[触发告警]
    Latency -->|正常| CheckCPU
    
    CPU -->|> 80%| Alert3[触发告警]
    CPU -->|正常| CheckMemory
    
    Memory -->|> 85%| Alert4[触发告警]
    Memory -->|正常| Healthy[指标健康]
    
    Alert1 --> Severity{严重程度评估}
    Alert2 --> Severity
    Alert3 --> Severity
    Alert4 --> Severity
    
    Severity -->|严重| ImmediateRollback[立即回滚<br/>weight: 0]
    Severity -->|中等| ReduceWeight[降低权重 50%]
    Severity -->|轻微| ContinueMonitor[继续观察]
    
    ImmediateRollback --> NotifyTeam[通知运维团队]
    ReduceWeight --> ExtendedMonitor[延长监控周期]
    ContinueMonitor --> WaitPeriod[等待下一监控周期]
    
    ExtendedMonitor --> ReEvaluate{重新评估}
    ReEvaluate -->|改善| IncreaseWeight[恢复权重]
    ReEvaluate -->|恶化| ImmediateRollback
    
    WaitPeriod --> Monitor
    IncreaseWeight --> Monitor
    
    Healthy --> NextStage{是否进入下一阶段}
    NextStage -->|是| IncreaseTraffic[增加流量权重]
    NextStage -->|否| Monitor
    
    IncreaseTraffic --> Monitor
    
    NotifyTeam --> PostMortem[问题分析]
    PostMortem --> End([回滚完成])
    
    style Start fill:#4fc3f7,stroke:#0277bd,stroke-width:3px
    style Monitor fill:#fff9c4,stroke:#f9a825,stroke-width:2px
    style Healthy fill:#81c784,stroke:#2e7d32,stroke-width:2px
    style Alert1 fill:#ffab91,stroke:#d84315,stroke-width:2px
    style Alert2 fill:#ffab91,stroke:#d84315,stroke-width:2px
    style Alert3 fill:#ffab91,stroke:#d84315,stroke-width:2px
    style Alert4 fill:#ffab91,stroke:#d84315,stroke-width:2px
    style ImmediateRollback fill:#ef5350,stroke:#b71c1c,stroke-width:3px
    style ReduceWeight fill:#ffb74d,stroke:#e65100,stroke-width:2px
    style End fill:#66bb6a,stroke:#1b5e20,stroke-width:3px
```

---

## Service Selector 工作原理

```mermaid
graph LR
    subgraph "Service 选择器机制"
        Svc[Service<br/>api-samples-2025-12-18]
        
        Svc -->|selector| MatchLabels{匹配 Labels}
        
        MatchLabels -->|app=api-name-type-ri-sb-samples<br/>version=2025-12-18| SelectPods[选中的 Pods]
    end
    
    subgraph "Namespace 所有 Pods"
        Pod1[Pod A<br/>app: api-name-type-ri-sb-samples<br/>version: 2025-11-19]
        Pod2[Pod B<br/>app: api-name-type-ri-sb-samples<br/>version: 2025-12-18]
        Pod3[Pod C<br/>app: api-name-type-ri-sb-samples<br/>version: 2025-12-18]
        Pod4[Pod D<br/>app: other-service<br/>version: 2025-12-18]
        Pod5[Pod E<br/>app: api-name-type-ri-sb-samples<br/>version: 2025-12-18]
    end
    
    Pod1 -.不匹配: version 不同.-> MatchLabels
    Pod2 -.匹配: 所有标签符合.-> SelectPods
    Pod3 -.匹配: 所有标签符合.-> SelectPods
    Pod4 -.不匹配: app 不同.-> MatchLabels
    Pod5 -.匹配: 所有标签符合.-> SelectPods
    
    SelectPods --> Endpoints[Service Endpoints<br/>10.0.1.10:8443<br/>10.0.1.11:8443<br/>10.0.1.12:8443]
    
    Endpoints --> LoadBalance[负载均衡分发]
    
    style Svc fill:#9c27b0,stroke:#4a148c,color:#fff,stroke-width:3px
    style MatchLabels fill:#7b1fa2,stroke:#4a148c,color:#fff,stroke-width:2px
    style SelectPods fill:#ba68c8,stroke:#6a1b9a,color:#fff,stroke-width:2px
    style Pod1 fill:#ffccbc,stroke:#d84315
    style Pod2 fill:#c8e6c9,stroke:#2e7d32,stroke-width:2px
    style Pod3 fill:#c8e6c9,stroke:#2e7d32,stroke-width:2px
    style Pod4 fill:#e0e0e0,stroke:#616161
    style Pod5 fill:#c8e6c9,stroke:#2e7d32,stroke-width:2px
    style Endpoints fill:#81c784,stroke:#388e3c,stroke-width:2px
    style LoadBalance fill:#66bb6a,stroke:#1b5e20,stroke-width:2px
```

---

## 完整配置对象关系图

```mermaid
erDiagram
    GATEWAY ||--o{ HTTPROUTE : "references"
    HTTPROUTE ||--o{ SERVICE : "backendRefs"
    SERVICE ||--o{ DEPLOYMENT : "selector"
    DEPLOYMENT ||--o{ POD : "creates"
    
    GATEWAY {
        string name "abjx-common-gateway"
        string namespace "abjx-common-gateway-ns"
        string gatewayClassName "gke-l7-global-external-managed"
    }
    
    HTTPROUTE {
        string name "api-name-type-ri-sb-samples-route"
        string namespace "ns-int-common-ms"
        string hostname "dev.goole.cloud.uk.aibang"
        string pathPrefix "/api-name-type-ri-sb-samples"
    }
    
    SERVICE {
        string name "api-name-type-ri-sb-samples-2025-12-18"
        int port "443"
        int weight "20"
        map selector "app version"
    }
    
    DEPLOYMENT {
        string name "api-samples-2025-12-18"
        int replicas "3"
        string image "gcr.io/project/api:2025-12-18"
    }
    
    POD {
        string name "api-samples-2025-12-18-xxx"
        string status "Running"
        map labels "app version"
    }
```

---

## 资源清理时间线

```mermaid
timeline
    title 版本清理生命周期管理
    section 新版本部署
        T+0h : 部署新版本 Deployment
             : 创建新版本 Service
             : HTTPRoute 添加 backendRef weight 20
    section 灰度发布
        T+1h : 增加至 weight 50
        T+2h : 增加至 weight 80
        T+3h : 完全切换 weight 100
    section 稳定观察
        T+24h : 移除旧版本 HTTPRoute backendRef
              : 保留旧版本 Service 和 Deployment
        T+48h : 确认无需回滚
    section 资源清理
        T+72h : 删除旧版本 Service
              : 删除旧版本 Deployment
              : Pods 自动清理
```

---

这些图表涵盖了从架构概览、流量分配、版本切换、监控回滚到资源清理的完整流程。每个图表都可以独立使用，也可以组合展示给团队成员理解整个灰度发布系统。