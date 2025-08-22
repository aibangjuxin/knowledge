# 架构流程图集合 - All Flow Charts

本文档包含了完整的架构设计、实施流程和部署策略的可视化图表，便于理解和记录整个系统架构。

## 1. 架构演进概览

### 1.1 当前架构 vs 目标架构对比

```mermaid
graph TB
    subgraph "当前架构 (Current Architecture)"
        C1[用户请求] --> C2[TCP GLB]
        C2 --> C3[Nginx A - L7<br/>10.72.x.x]
        C3 --> C4[Nginx B - L4<br/>双网卡]
        C4 --> C5[GKE Gateway<br/>192.168.64.33]
        C5 --> C6[Kong DP]
        C6 --> C7[Runtime Pods]

        C8[❌ 无法使用Cloud Armor]
        C9[❌ 架构复杂]
        C10[❌ 金丝雀部署困难]
    end

    subgraph "目标架构 (Target Architecture)"
        T1[用户请求] --> T2[HTTPS GLB + Cloud Armor]
        T2 --> T3[Merged Nginx<br/>双网卡 L7]
        T3 --> T4[GKE Gateway<br/>192.168.64.33/34]
        T4 --> T5[Kong DP]
        T5 --> T6[Runtime Pods]

        T7[✅ Cloud Armor防护]
        T8[✅ 架构简化]
        T9[✅ 金丝雀部署]
    end

    style C8 fill:#ffebee
    style C9 fill:#ffebee
    style C10 fill:#ffebee
    style T7 fill:#e8f5e8
    style T8 fill:#e8f5e8
    style T9 fill:#e8f5e8
```

### 1.2 架构演进时间线

```mermaid
timeline
    title 架构优化实施时间线

    section 准备阶段
        Week 1 : 架构设计确认
               : 资源规划
               : 团队培训

    section 第一阶段 - 组件合并
        Week 2 : 创建双网卡Nginx实例
               : 配置网络连接
               : 迁移配置文件

        Week 3 : 内部测试验证
               : 流量切换
               : 清理Nginx B组件

    section 第二阶段 - HTTPS升级
        Week 4 : 创建HTTPS负载均衡器
               : 配置Cloud Armor策略
               : DNS切换准备

        Week 5 : 执行DNS切换
               : 监控和优化
               : 清理旧资源

    section 第三阶段 - 金丝雀部署
        Week 6+ : 配置金丝雀逻辑
                : 建立监控体系
                : 持续优化
```

## 2. 详细架构流程图

### 2.1 最终目标架构详图

```mermaid
graph TD
    subgraph "Internet"
        U[用户请求www\.aibang\.com]
    end

    subgraph "GCP Load Balancer"
        LB[External HTTPS<br/>Load Balancer<br/>🔒 SSL Termination]
        CA[Cloud Armor<br/>🛡️ Security Policy]
        LB -.->|附加策略| CA
    end

    subgraph "Shared VPC - 10.72.x.x"
        subgraph "Merged Nginx Instance"
            direction TB
            NX[Nginx Server<br/>🔄 L7 Proxy + Canary Logic]
            NIC1[NIC1: 10.72.x.x<br/>📡 Shared VPC]
            NIC2[NIC2: 192.168.x.x<br/>📡 Private VPC]
            NX --- NIC1
            NX --- NIC2
        end
    end

    subgraph "Private VPC - 192.168.x.x"
        subgraph "GKE Cluster"
            GW1[GKE Gateway Stable<br/>192.168.64.33:443<br/>🟢 Production]
            GW2[GKE Gateway Canary<br/>192.168.64.34:443<br/>🟡 Canary]

            subgraph "Kong Layer"
                K1[Kong DP Stable<br/>🔵 Data Plane]
                K2[Kong DP Canary<br/>🟠 Data Plane]
            end

            subgraph "Application Layer"
                RT1[Runtime Pods v1<br/>🟢 Stable Version]
                RT2[Runtime Pods v2<br/>🟡 Canary Version]
            end
        end
    end

    U --> LB
    LB --> NIC1
    NIC2 -.->|90% Traffic| GW1
    NIC2 -.->|10% Traffic| GW2
    GW1 --> K1 --> RT1
    GW2 --> K2 --> RT2

    style U fill:#e3f2fd
    style LB fill:#f3e5f5
    style CA fill:#ffebee
    style NX fill:#e8f5e8
    style GW1 fill:#e8f5e8
    style GW2 fill:#fff3e0
    style RT1 fill:#e8f5e8
    style RT2 fill:#fff3e0
```

### 2.2 网络拓扑图

```mermaid
graph LR
    subgraph "External Network"
        INT[Internet<br/>0.0.0.0/0]
    end

    subgraph "GCP Project"
        subgraph "Shared VPC Network"
            SN1[Subnet: 10.72.0.0/24<br/>🌐 Public Subnet]
            NGINX[Merged Nginx<br/>10.72.0.188]
        end

        subgraph "Private VPC Network"
            SN2[Subnet: 192.168.0.0/24<br/>🔒 Private Subnet]
            SN3[Subnet: 192.168.64.0/24<br/>🔒 GKE Subnet]

            NGINX2[Nginx Interface<br/>192.168.0.35]
            GKE1[GKE Gateway Stable<br/>192.168.64.33]
            GKE2[GKE Gateway Canary<br/>192.168.64.34]
        end

        subgraph "Static Routes"
            RT[ip route add<br/>192.168.64.0/24<br/>via 192.168.1.1]
        end
    end

    INT --> SN1
    SN1 --> NGINX
    NGINX -.->|Dual NIC| NGINX2
    NGINX2 --> SN2
    SN2 --> SN3
    SN3 --> GKE1
    SN3 --> GKE2
    NGINX2 -.->|Route| RT
    RT -.-> SN3

    style INT fill:#e3f2fd
    style SN1 fill:#f3e5f5
    style SN2 fill:#fff3e0
    style SN3 fill:#e8f5e8
    style NGINX fill:#ffeb3b
    style NGINX2 fill:#ffeb3b
```

## 3. 请求流程序列图

### 3.1 正常请求流程

```mermaid
sequenceDiagram
    participant U as 用户
    participant DNS as DNS服务
    participant LB as HTTPS Load Balancer
    participant CA as Cloud Armor
    participant NX as Merged Nginx
    participant GW as GKE Gateway
    participant K as Kong DP
    participant RT as Runtime Pods

    U->>DNS: 解析 www.aibang.com
    DNS-->>U: 返回 LB IP地址

    U->>+LB: HTTPS请求 /api_name1/v1/
    LB->>+CA: 安全策略检查
    CA-->>-LB: ✅ 允许通过

    LB->>+NX: 转发请求到 Nginx
    Note over NX: 执行金丝雀逻辑<br/>决定路由目标

    alt 90% 流量 - 稳定版
        NX->>+GW: 路由到 192.168.64.33
        GW->>+K: 转发到 Kong Stable
        K->>+RT: 转发到 Runtime v1
        RT-->>-K: 响应数据
        K-->>-GW: 返回响应
        GW-->>-NX: 返回响应
    else 10% 流量 - 金丝雀版
        NX->>+GW: 路由到 192.168.64.34
        Note over GW: Canary Gateway
        GW->>+K: 转发到 Kong Canary
        K->>+RT: 转发到 Runtime v2
        RT-->>-K: 响应数据 (新版本)
        K-->>-GW: 返回响应
        GW-->>-NX: 返回响应
    end

    NX-->>-LB: 返回最终响应
    LB-->>-U: HTTPS响应

    Note over U,RT: 请求完成，用户无感知版本差异
```

### 3.2 Cloud Armor 拦截流程

```mermaid
sequenceDiagram
    participant A as 攻击者
    participant LB as HTTPS Load Balancer
    participant CA as Cloud Armor
    participant NX as Merged Nginx
    participant LOG as Security Logs

    A->>+LB: 恶意请求 /api_name1/v1/
    Note over A: 包含攻击载荷或<br/>来自黑名单IP

    LB->>+CA: 安全策略检查
    Note over CA: CEL表达式匹配:<br/>request.path.matches('/api_name1/v1/.*')

    CA->>CA: 检测到威胁
    CA->>+LOG: 记录安全事件
    LOG-->>-CA: 日志已记录

    CA-->>-LB: ❌ 拒绝请求 (403/429)
    LB-->>-A: HTTP 403 Forbidden

    Note over NX: Nginx 完全不会<br/>收到恶意请求
    Note over A,LOG: 攻击在边缘被阻止<br/>保护后端服务
```

## 4. 金丝雀部署流程图

### 4.1 金丝雀部署决策流程

```mermaid
flowchart TD
    START([用户请求]) --> CHECK_API{API是否启用<br/>金丝雀?}

    CHECK_API -->|否| STABLE[路由到稳定版<br/>192.168.64.33]
    CHECK_API -->|是| CHECK_FORCE{强制金丝雀<br/>标识?}

    CHECK_FORCE -->|Header: x-canary=true| CANARY[路由到金丝雀版<br/>192.168.64.34]
    CHECK_FORCE -->|Cookie: canary=true| CANARY
    CHECK_FORCE -->|否| CHECK_USER{是否金丝雀<br/>用户?}

    CHECK_USER -->|用户ID包含'canary'| CANARY
    CHECK_USER -->|用户ID包含'test'| CANARY
    CHECK_USER -->|否| RANDOM{随机分流<br/>检查}

    RANDOM -->|命中百分比| CANARY
    RANDOM -->|未命中| STABLE

    STABLE --> STABLE_BACKEND[Kong DP Stable<br/>Runtime v1]
    CANARY --> CANARY_BACKEND[Kong DP Canary<br/>Runtime v2]

    STABLE_BACKEND --> RESPONSE[返回响应<br/>X-Canary-Version: stable]
    CANARY_BACKEND --> RESPONSE2[返回响应<br/>X-Canary-Version: canary]

    RESPONSE --> END([请求完成])
    RESPONSE2 --> END

    style START fill:#e3f2fd
    style CANARY fill:#fff3e0
    style STABLE fill:#e8f5e8
    style END fill:#f3e5f5
```

### 4.2 多 API 金丝雀配置架构

```mermaid
graph TB
    subgraph "Nginx Configuration Structure"
        MAIN[nginx.conf<br/>🔧 主配置文件]

        subgraph "Maps Directory"
            MAP1[canary_users.conf<br/>👥 用户映射]
            MAP2[api_backends.conf<br/>🔗 API后端映射]
        end

        subgraph "Shared Directory"
            SHARED1[upstream_stable.conf<br/>🟢 稳定版上游]
            SHARED2[upstream_canary.conf<br/>🟡 金丝雀上游]
            SHARED3[canary_logic.conf<br/>🧠 金丝雀逻辑]
        end

        subgraph "User1 APIs"
            U1A1[api_name1.conf<br/>✅ 金丝雀启用]
            U1A2[api_name2.conf<br/>❌ 普通API]
            U1A3[api_name3.conf<br/>🔄 复杂策略]
        end

        subgraph "User2 APIs"
            U2A1[api_service1.conf<br/>✅ 金丝雀启用]
            U2A2[api_service2.conf<br/>❌ 普通API]
        end

        subgraph "UserN APIs"
            UNA1[api_xxx.conf<br/>📝 更多API...]
        end
    end

    MAIN --> MAP1
    MAIN --> MAP2
    MAIN --> SHARED1
    MAIN --> SHARED2
    MAIN --> SHARED3
    MAIN --> U1A1
    MAIN --> U1A2
    MAIN --> U1A3
    MAIN --> U2A1
    MAIN --> U2A2
    MAIN --> UNA1

    style MAIN fill:#e3f2fd
    style U1A1 fill:#fff3e0
    style U2A1 fill:#fff3e0
    style U1A2 fill:#e8f5e8
    style U2A2 fill:#e8f5e8
```

### 4.3 金丝雀发布生命周期

```mermaid
stateDiagram-v2
    [*] --> Planning: 开始金丝雀发布

    Planning --> Development: 规划完成
    Development --> Testing: 开发完成
    Testing --> Deployment: 测试通过

    state Deployment {
        [*] --> Deploy1: 部署到金丝雀环境
        Deploy1 --> Config1: 配置1%流量
        Config1 --> Monitor1: 监控指标

        Monitor1 --> Config5: 指标正常
        Config5 --> Monitor5: 5%流量监控

        Monitor5 --> Config10: 继续正常
        Config10 --> Monitor10: 10%流量监控

        Monitor10 --> Config50: 继续正常
        Config50 --> Monitor50: 50%流量监控

        Monitor50 --> Config100: 准备全量
        Config100 --> [*]: 100%流量
    }

    state Rollback {
        [*] --> Emergency: 检测到问题
        Emergency --> Config0: 流量切回0%
        Config0 --> Investigation: 问题调查
        Investigation --> [*]: 修复完成
    }

    Deployment --> Rollback: 发现问题
    Rollback --> Deployment: 问题修复
    Deployment --> Success: 发布成功
    Success --> [*]: 清理旧版本

    note right of Planning
        制定发布计划
        准备监控指标
        设置回滚标准
    end note

    note right of Rollback
        自动或手动触发
        快速恢复服务
        保留问题现场
    end note
```

## 5. 实施流程图

### 5.1 第一阶段：组件合并流程

```mermaid
flowchart TD
    START1([开始第一阶段<br/>组件合并]) --> PREP[准备双网卡<br/>Nginx实例]

    PREP --> NET_CONFIG[配置网络连接<br/>- Shared VPC: 10.72.x.x<br/>- Private VPC: 192.168.x.x]

    NET_CONFIG --> ROUTE_CONFIG[配置静态路由<br/>ip route add 192.168.64.0/24<br/>via 192.168.1.1]

    ROUTE_CONFIG --> MIGRATE_CONFIG[迁移配置文件<br/>- 从Nginx A复制配置<br/>- 修改proxy_pass目标]

    MIGRATE_CONFIG --> TEST_INTERNAL[内部测试<br/>- 功能验证<br/>- 性能测试<br/>- 连通性检查]

    TEST_INTERNAL --> TEST_OK{测试通过?}
    TEST_OK -->|否| DEBUG[问题排查<br/>和修复]
    DEBUG --> TEST_INTERNAL

    TEST_OK -->|是| SWITCH_TRAFFIC[切换流量<br/>更新LB后端指向]

    SWITCH_TRAFFIC --> MONITOR[监控新架构<br/>- 流量指标<br/>- 错误率<br/>- 响应时间]

    MONITOR --> STABLE{运行稳定?}
    STABLE -->|否| ROLLBACK[回滚到原架构]
    ROLLBACK --> DEBUG

    STABLE -->|是| CLEANUP[清理资源<br/>- 停止Nginx B<br/>- 释放虚拟机<br/>- 更新文档]

    CLEANUP --> END1([第一阶段完成])

    style START1 fill:#e3f2fd
    style END1 fill:#e8f5e8
    style TEST_OK fill:#fff3e0
    style STABLE fill:#fff3e0
    style ROLLBACK fill:#ffebee
```

### 5.2 第二阶段：HTTPS 升级流程

```mermaid
flowchart TD
    START2([开始第二阶段<br/>HTTPS升级]) --> CREATE_LB[创建HTTPS<br/>负载均衡器]

    CREATE_LB --> SSL_CERT[配置SSL证书<br/>- 上传证书<br/>- 或使用Google管理证书]

    SSL_CERT --> BACKEND_SVC[配置后端服务<br/>- 指向Nginx实例组<br/>- 设置健康检查]

    BACKEND_SVC --> CLOUD_ARMOR[配置Cloud Armor<br/>- 创建安全策略<br/>- 设置CEL规则<br/>- 附加到后端服务]

    CLOUD_ARMOR --> GET_IP[获取新的<br/>静态IP地址]

    GET_IP --> TEST_NEW[测试新LB<br/>- 直接IP访问<br/>- 功能验证<br/>- SSL检查<br/>- Cloud Armor测试]

    TEST_NEW --> TEST_OK2{测试通过?}
    TEST_OK2 -->|否| DEBUG2[问题排查<br/>和修复]
    DEBUG2 --> TEST_NEW

    TEST_OK2 -->|是| LOWER_TTL[降低DNS TTL<br/>从3600s到300s]

    LOWER_TTL --> WAIT[等待24小时<br/>TTL生效]

    WAIT --> DNS_SWITCH[DNS切换<br/>更新A记录到新IP]

    DNS_SWITCH --> MONITOR2[监控切换进度<br/>- DNS传播<br/>- 流量迁移<br/>- 错误监控]

    MONITOR2 --> SWITCH_COMPLETE{切换完成?}
    SWITCH_COMPLETE -->|否| WAIT_MORE[继续等待<br/>DNS传播]
    WAIT_MORE --> MONITOR2

    SWITCH_COMPLETE -->|是| VERIFY[验证新架构<br/>- 所有功能正常<br/>- Cloud Armor生效<br/>- 性能指标正常]

    VERIFY --> CLEANUP2[清理旧资源<br/>- 删除TCP LB<br/>- 释放旧IP<br/>- 恢复DNS TTL]

    CLEANUP2 --> END2([第二阶段完成])

    style START2 fill:#e3f2fd
    style END2 fill:#e8f5e8
    style TEST_OK2 fill:#fff3e0
    style SWITCH_COMPLETE fill:#fff3e0
    style DNS_SWITCH fill:#ffeb3b
```

### 5.3 DNS 切换详细流程

```mermaid
sequenceDiagram
    participant Admin as 管理员
    participant DNS as DNS提供商
    participant Old as 旧TCP LB
    participant New as 新HTTPS LB
    participant Users as 用户群体
    participant Monitor as 监控系统

    Note over Admin,Monitor: DNS切换准备阶段
    Admin->>DNS: 降低TTL到300秒
    Admin->>Monitor: 开始监控准备

    Note over Admin,Monitor: 等待TTL生效 (24小时)
    Admin->>Admin: 等待TTL传播

    Note over Admin,Monitor: 执行DNS切换
    Admin->>DNS: 更新A记录到新IP
    DNS-->>Admin: 确认更新成功

    Admin->>Monitor: 开始切换监控

    loop DNS传播过程
        Users->>DNS: 查询域名
        alt 缓存未过期
            DNS-->>Users: 返回旧IP
            Users->>Old: 请求到旧LB
            Old-->>Users: 响应
        else 缓存已过期
            DNS-->>Users: 返回新IP
            Users->>New: 请求到新LB
            New-->>Users: 响应
        end

        Monitor->>Old: 检查旧LB流量
        Monitor->>New: 检查新LB流量
        Monitor-->>Admin: 报告流量分布
    end

    Note over Admin,Monitor: 切换完成验证
    Admin->>Monitor: 验证切换完成
    Monitor-->>Admin: 确认100%流量到新LB

    Admin->>DNS: 恢复TTL到3600秒
    Admin->>Old: 清理旧资源
```

## 6. 监控和告警流程

### 6.1 金丝雀监控仪表板

```mermaid
graph TB
    subgraph "监控数据源"
        NGINX_LOG[Nginx访问日志<br/>📊 流量分布数据]
        APP_METRICS[应用指标<br/>📈 响应时间/错误率]
        INFRA_METRICS[基础设施指标<br/>🖥️ CPU/内存/网络]
        CA_LOG[Cloud Armor日志<br/>🛡️ 安全事件]
    end

    subgraph "数据处理"
        PARSER[日志解析器<br/>🔍 提取关键指标]
        AGGREGATOR[数据聚合器<br/>📊 统计计算]
        ALERTER[告警引擎<br/>🚨 阈值检查]
    end

    subgraph "可视化界面"
        DASHBOARD[监控仪表板<br/>📱 实时展示]
        REPORT[报告生成器<br/>📋 定期报告]
        ALERT_UI[告警界面<br/>🔔 告警通知]
    end

    subgraph "关键指标"
        TRAFFIC[流量分布<br/>稳定版 vs 金丝雀版]
        ERROR[错误率对比<br/>4xx/5xx统计]
        LATENCY[响应时间<br/>P95/P99延迟]
        SUCCESS[成功率<br/>业务指标]
    end

    NGINX_LOG --> PARSER
    APP_METRICS --> PARSER
    INFRA_METRICS --> PARSER
    CA_LOG --> PARSER

    PARSER --> AGGREGATOR
    AGGREGATOR --> ALERTER
    AGGREGATOR --> DASHBOARD

    DASHBOARD --> TRAFFIC
    DASHBOARD --> ERROR
    DASHBOARD --> LATENCY
    DASHBOARD --> SUCCESS

    ALERTER --> ALERT_UI
    AGGREGATOR --> REPORT

    style DASHBOARD fill:#e3f2fd
    style ALERTER fill:#ffebee
    style TRAFFIC fill:#e8f5e8
    style ERROR fill:#fff3e0
```

### 6.2 自动回滚流程

```mermaid
flowchart TD
    MONITOR[持续监控<br/>金丝雀指标] --> CHECK{指标检查}

    CHECK -->|正常| CONTINUE[继续监控]
    CONTINUE --> MONITOR

    CHECK -->|异常| ALERT[触发告警<br/>🚨 发送通知]

    ALERT --> EVALUATE{评估严重程度}

    EVALUATE -->|轻微异常| MANUAL[人工介入<br/>👨‍💻 手动处理]
    EVALUATE -->|严重异常| AUTO_ROLLBACK[自动回滚<br/>🔄 紧急处理]

    AUTO_ROLLBACK --> STOP_CANARY[停止金丝雀流量<br/>设置比例为0%]

    STOP_CANARY --> RELOAD_NGINX[重载Nginx配置<br/>nginx -s reload]

    RELOAD_NGINX --> VERIFY[验证回滚<br/>✅ 确认流量恢复]

    VERIFY --> NOTIFY[通知团队<br/>📧 回滚完成通知]

    NOTIFY --> INVESTIGATE[问题调查<br/>🔍 根因分析]

    MANUAL --> DECISION{人工决策}
    DECISION -->|回滚| AUTO_ROLLBACK
    DECISION -->|继续观察| MONITOR
    DECISION -->|调整策略| ADJUST[调整金丝雀策略<br/>⚙️ 修改配置]

    ADJUST --> RELOAD_NGINX
    INVESTIGATE --> FIX[问题修复<br/>🔧 代码/配置修复]
    FIX --> REDEPLOY[重新部署<br/>🚀 新版本发布]

    style AUTO_ROLLBACK fill:#ffebee
    style VERIFY fill:#e8f5e8
    style ALERT fill:#fff3e0
    style INVESTIGATE fill:#e3f2fd
```

## 7. 安全防护流程

### 7.1 Cloud Armor 防护层级

```mermaid
graph TD
    subgraph "多层安全防护"
        L1[第一层：边缘防护<br/>🌐 Cloud Armor at LB]
        L2[第二层：应用防护<br/>🔒 Nginx Security Headers]
        L3[第三层：API防护<br/>🛡️ Kong Security Plugins]
        L4[第四层：应用防护<br/>🔐 Application Security]
    end

    subgraph "Cloud Armor规则"
        RULE1[IP黑名单<br/>🚫 恶意IP阻断]
        RULE2[地理位置过滤<br/>🌍 国家/地区限制]
        RULE3[速率限制<br/>⏱️ API调用频率控制]
        RULE4[SQL注入防护<br/>💉 OWASP规则]
        RULE5[XSS防护<br/>🔗 跨站脚本防护]
        RULE6[自定义规则<br/>📝 业务特定规则]
    end

    subgraph "API特定防护"
        API1["/api_name1/v1/<br/>🔴 高风险API<br/>严格限制"]
        API2["/api_name2/v1/<br/>🟡 中风险API<br/>标准限制"]
        API3["/api_name3/v1/<br/>🟢 低风险API<br/>基础限制"]
    end

    L1 --> RULE1
    L1 --> RULE2
    L1 --> RULE3
    L1 --> RULE4
    L1 --> RULE5
    L1 --> RULE6

    RULE6 --> API1
    RULE6 --> API2
    RULE6 --> API3

    L1 --> L2
    L2 --> L3
    L3 --> L4

    style L1 fill:#ffebee
    style API1 fill:#ffcdd2
    style API2 fill:#fff3e0
    style API3 fill:#e8f5e8
```

### 7.2 安全事件处理流程

```mermaid
sequenceDiagram
    participant Attacker as 攻击者
    participant CA as Cloud Armor
    participant LB as HTTPS LB
    participant SIEM as 安全监控
    participant SOC as 安全团队
    participant Admin as 系统管理员

    Attacker->>LB: 发起攻击请求
    LB->>CA: 安全策略检查

    alt 攻击被识别
        CA->>CA: 匹配安全规则
        CA->>SIEM: 记录安全事件
        CA-->>LB: 阻断请求 (403/429)
        LB-->>Attacker: 返回错误响应

        SIEM->>SIEM: 分析攻击模式
        SIEM->>SOC: 发送告警

        alt 严重攻击
            SOC->>Admin: 紧急通知
            Admin->>CA: 更新安全规则
            Admin->>SIEM: 确认处理完成
            Admin-->>SOC: 处理结果反馈
        else 常规攻击
            SOC->>SOC: 记录并监控
        end

        SOC-->>SIEM: 确认告警处理
        SIEM-->>CA: 更新威胁情报

    else 正常请求
        CA-->>LB: 允许通过
        LB->>LB: 转发到后端
        LB-->>Attacker: 正常响应
    end

    Note over Attacker,Admin: 攻击在边缘被阻止<br/>后端服务完全不受影响
```

## 8. 性能优化流程

### 8.1 性能监控和优化循环

```mermaid
graph LR
    subgraph "性能监控循环"
        A[收集性能数据<br/>📊 Metrics Collection] --> B[数据分析<br/>🔍 Performance Analysis]
        B --> C[识别瓶颈<br/>🎯 Bottleneck Identification]
        C --> D[制定优化方案<br/>📋 Optimization Planning]
        D --> E[实施优化<br/>⚙️ Implementation]
        E --> F[验证效果<br/>✅ Validation]
        F --> A
    end

    subgraph "关键性能指标"
        P1[响应时间<br/>⏱️ Response Time]
        P2[吞吐量<br/>📈 Throughput]
        P3[错误率<br/>❌ Error Rate]
        P4[资源利用率<br/>💻 Resource Usage]
    end

    subgraph "优化策略"
        O1[负载均衡优化<br/>⚖️ Load Balancing]
        O2[缓存策略<br/>🗄️ Caching]
        O3[连接池优化<br/>🔗 Connection Pooling]
        O4[资源扩容<br/>📈 Scaling]
    end

    A --> P1
    A --> P2
    A --> P3
    A --> P4

    D --> O1
    D --> O2
    D --> O3
    D --> O4

    style A fill:#e3f2fd
    style C fill:#fff3e0
    style E fill:#e8f5e8
    style F fill:#f3e5f5
```

## 9. 总结

本文档通过多种 Mermaid 图表类型，全面展示了：

### 🏗️ **架构设计**

- 当前架构 vs 目标架构对比
- 详细的网络拓扑和组件关系
- 分阶段实施的演进路径

### 🔄 **流程管控**

- 完整的请求处理流程
- 金丝雀部署的决策逻辑
- DNS 切换的详细步骤

### 🛡️ **安全防护**

- 多层安全防护体系
- Cloud Armor 的防护机制
- 安全事件的处理流程

### 📊 **监控运维**

- 实时监控和告警机制
- 自动回滚的触发条件
- 性能优化的持续改进

这些图表不仅便于技术团队理解架构设计，也为项目管理和决策提供了清晰的可视化参考。每个图表都可以独立使用，也可以组合起来形成完整的架构文档体系。
