- [summary](#summary)
    - [2. 组件层级关系](#2-组件层级关系)

# summary 
- describe 


```
UK Region (Host Project)
├── Shared VPC UK (10.72.0.0/10)
│   ├── Project A (Service Project)
│   │   └── VM Instance (10.72.22.3) OR it's src_gateway
│   ├── Project B (Service Project)
│   └── Project C (Service Project)
└── Interconnect Attachment

CN Region (Host Project)
├── Shared VPC CN (10.92.0.0/10)
│   ├── Project X (Service Project)
│   │   └── VM Instance (10.92.22.3)
│   ├── Project Y (Service Project)
│   └── Project Z (Service Project)
└── Interconnect Attachment
```

- IP 10.72.22.3 出现在 src_gateway 字段中，这表明它是 Interconnect Attachment 的网关 IP，而不是 VM 实例的 IP
- 分析 Interconnect 流量日志 filter using `resource.type="gce_interconnect_attachment"`
- 分层的一些说明
  
| **组件**                                        | **说明**                                                          |
| --------------------------------------------- | --------------------------------------------------------------- |
| **Interconnect**                              | 实体物理链路（专线或Partner）连接 GCP 与本地数据中心                                |
| **VLAN Attachment (Interconnect Attachment)** | Interconnect 上的逻辑接口，每个 attachment 对应一个 Cloud Router             |
| **Cloud Router**                              | 控制层资源，负责通过 BGP 交换路由                                             |
| **Shared VPC Host Project**                   | 定义网络（VPC/Subnet）的宿主工程                                           |
| **Service Project**                           | 连接到 Shared VPC 的工程，VM 实际存在于这里，但使用 Host Project 的网络              |
| **VM Instance**                               | 最终分配 IP 的计算节点，可属于任意 Service Project，但 IP 属于 Shared VPC 的 subnet |


### 2. 组件层级关系

|层级|组件|作用|示例|
|---|---|---|---|
|**L1 物理层**|Interconnect|物理专线连接|`aibang-vpc-europe-prod-eqld6-z2-3`|
|**L2 链路层**|VLAN Attachment|虚拟链路，承载流量|`aibang-vpc1-eq1d6-z2-3b`|
|**L3 网络层**|Cloud Router|BGP 路由交换|动态学习/通告路由|
|**L4 网络层**|VPC|逻辑网络空间|`10.72.0.0/10`|

- flow 
- [flow](./vpc-claude.md#架构全景图)

- [flow-gpt](./cross-project-vpc-anaylize-ChatGPT.md#一跨工程-shared-vpc--interconnect-网络拓扑图)
```mermaid
graph TB
    subgraph "UK Region (europe-west2)"
        UK_HOST[UK Host Project<br/>aibang-1231231-vpchost-eu-prod]
        UK_VPC[UK Shared VPC<br/>10.72.0.0/10<br/>cinternal-vpc1]
        UK_ROUTER[Cloud Router UK<br/>BGP Speaker]
        UK_ATTACH[VLAN Attachment<br/>aibang-vpc1-eq1d6-z2-3b<br/>Gateway IP: 10.72.22.3]
        
        subgraph "UK Service Projects"
            UK_PROJ_A[Project A<br/>真实 VM 发起者]
            UK_PROJ_B[Project B]
            UK_PROJ_C[Project C]
        end
        
        UK_HOST --> UK_VPC
        UK_VPC --> UK_ROUTER
        UK_ROUTER --> UK_ATTACH
        UK_VPC -.共享给.-> UK_PROJ_A
        UK_VPC -.共享给.-> UK_PROJ_B
        UK_VPC -.共享给.-> UK_PROJ_C
    end
    
    subgraph "Interconnect Layer"
        INTERCONNECT[Cloud Interconnect<br/>aibang-vpc-europe-prod-eqld6-z2-3<br/>物理专线连接]
    end
    
    subgraph "CN Region"
        CN_HOST[CN Host Project<br/>aibang-1231231-vpchost-cn-prod]
        CN_VPC[CN Shared VPC<br/>10.92.0.0/10]
        CN_ROUTER[Cloud Router CN]
        CN_ATTACH[VLAN Attachment CN]
        
        subgraph "CN Service Projects"
            CN_PROJ_X[Project X]
            CN_PROJ_Y[Project Y<br/>Target VM: 10.92.22.3]
        end
        
        CN_HOST --> CN_VPC
        CN_VPC --> CN_ROUTER
        CN_ROUTER --> CN_ATTACH
        CN_VPC -.共享给.-> CN_PROJ_X
        CN_VPC -.共享给.-> CN_PROJ_Y
    end
    
    UK_ATTACH <-->|物理连接| INTERCONNECT
    INTERCONNECT <-->|物理连接| CN_ATTACH
    
    UK_PROJ_A -.->|流量路径<br/>真实VM → Gateway 10.72.22.3 → 目标 10.92.22.3| CN_PROJ_Y
    
    style UK_ATTACH fill:#ff6b6b,stroke:#333,stroke-width:3px
    style CN_ATTACH fill:#4ecdc4,stroke:#333,stroke-width:3px
    style INTERCONNECT fill:#45b7d1,stroke:#333,stroke-width:4px
    style UK_PROJ_A fill:#96ceb4,stroke:#333,stroke-width:2px
    style CN_PROJ_Y fill:#ffeaa7,stroke:#333,stroke-width:2px
```


```mermaid
graph LR
    subgraph UK_Host[UK Host Project: aibang-1231231-vpchost-eu-prod]
        UK_VPC[Shared VPC UK 10.72.0.0/10]
        UK_Router[Cloud Router UK]
        UK_Attach[VLAN Attachment UK<br/>aibang-...-eqld6-z2-3b<br/>type: INTERCONNECT_ATTACHMENT]
    end

    subgraph UK_Service[Service Project A]
        UK_VM[VM Instance<br/>10.72.22.3]
    end

    subgraph CN_Host[CN Host Project: aibang-1231231-vpchost-cn-prod]
        CN_VPC[Shared VPC CN 10.92.0.0/10]
        CN_Router[Cloud Router CN]
        CN_Attach[VLAN Attachment CN]
    end

    subgraph CN_Service[Service Project X]
        CN_VM[VM Instance<br/>10.92.22.3]
    end

    UK_Service -->|使用 Shared VPC 网络| UK_VPC
    CN_Service -->|使用 Shared VPC 网络| CN_VPC

    UK_VM -->|出向流量| UK_Router
    CN_VM -->|出向流量| CN_Router

    UK_Router -->|BGP 广告 / 传递路由| UK_Attach
    CN_Router -->|BGP 广告 / 传递路由| CN_Attach

    UK_Attach <--> |物理链路| Interconnect[Dedicated/Partner Interconnect Link]
    CN_Attach <--> |物理链路| Interconnect
```