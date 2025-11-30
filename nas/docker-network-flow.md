# Docker 网络流程图集

本文档包含多个 Mermaid 图表，用于可视化 Docker 在 QNAP NAS 上的网络架构和流程。

## 1. Docker 三层架构总览

```mermaid
graph TB
    subgraph User["用户层"]
        SSH[SSH 会话]
        Shell[Shell 环境变量<br/>HTTP_PROXY]
    end
    
    subgraph Docker["Docker 层"]
        CLI[Docker CLI<br/>/share/.../docker]
        Daemon[Docker Daemon<br/>dockerd]
        DaemonConfig[daemon.json<br/>代理配置]
    end
    
    subgraph Container["容器层"]
        K3s[K3s 容器]
        Containerd[Containerd<br/>镜像拉取]
        EnvVars[环境变量<br/>-e HTTP_PROXY]
    end
    
    subgraph Network["网络层"]
        Proxy[代理服务器<br/>192.168.31.198:7222]
        Registry[镜像仓库<br/>docker.io/gcr.io]
    end
    
    SSH --> Shell
    Shell -.不继承.-> CLI
    CLI -->|API 请求| Daemon
    DaemonConfig -->|配置| Daemon
    Daemon -->|拉取基础镜像| Proxy
    Daemon -->|启动容器| K3s
    EnvVars -->|注入| K3s
    K3s --> Containerd
    Containerd -->|拉取系统镜像| Proxy
    Proxy --> Registry
    
    style Shell fill:#ffcccc
    style DaemonConfig fill:#ccffcc
    style EnvVars fill:#ccffcc
    style Proxy fill:#cce5ff
```

## 2. Docker Pull 详细流程

```mermaid
sequenceDiagram
    participant User as 用户
    participant CLI as Docker CLI
    participant Daemon as Docker Daemon
    participant Proxy as 代理服务器
    participant Registry as Docker Registry
    
    User->>CLI: docker pull rancher/k3s
    CLI->>Daemon: API 请求 (Unix Socket)
    
    Note over Daemon: 检查本地镜像缓存
    
    alt 镜像不存在
        Daemon->>Daemon: 读取 daemon.json 代理配置
        Daemon->>Proxy: HTTP CONNECT
        Proxy->>Registry: 查询镜像 manifest
        Registry-->>Proxy: 返回 manifest
        Proxy-->>Daemon: 返回 manifest
        
        loop 每个镜像层
            Daemon->>Proxy: 下载层
            Proxy->>Registry: 请求层数据
            Registry-->>Proxy: 返回层数据
            Proxy-->>Daemon: 返回层数据
        end
        
        Daemon->>Daemon: 保存镜像到本地
        Daemon-->>CLI: 拉取成功
        CLI-->>User: 显示进度和结果
    else 镜像已存在
        Daemon-->>CLI: 镜像已是最新
        CLI-->>User: 显示消息
    end
```

## 3. Docker Run 与 K3s 启动流程

```mermaid
sequenceDiagram
    participant User as 用户
    participant CLI as Docker CLI
    participant Daemon as Docker Daemon
    participant K3s as K3s 容器
    participant Containerd as Containerd
    participant Proxy as 代理服务器
    participant Registry as 镜像仓库
    
    User->>CLI: docker run -e HTTP_PROXY=... rancher/k3s
    CLI->>Daemon: 创建容器请求
    
    Daemon->>Daemon: 创建命名空间和 cgroups
    Daemon->>K3s: 启动容器进程
    Note over K3s: 继承 -e 环境变量
    
    K3s->>K3s: 初始化 Kubernetes
    K3s->>Containerd: 拉取 pause 镜像
    
    Containerd->>Containerd: 读取 HTTP_PROXY 环境变量
    Containerd->>Proxy: 请求镜像
    Proxy->>Registry: 转发请求
    Registry-->>Proxy: 返回镜像
    Proxy-->>Containerd: 返回镜像
    
    Containerd->>Containerd: 拉取 coredns 镜像
    Containerd->>Proxy: 请求镜像
    Proxy->>Registry: 转发请求
    Registry-->>Proxy: 返回镜像
    Proxy-->>Containerd: 返回镜像
    
    K3s-->>User: K3s 就绪
```

## 4. 网络模式对比：Host vs Bridge

```mermaid
graph TB
    subgraph HostMode["Host 网络模式 (--network host)"]
        direction TB
        NAS1[QNAP NAS<br/>IP: 192.168.31.88]
        K3sHost[K3s 容器]
        
        NAS1 -.共享网络栈.-> K3sHost
        
        HostPorts[端口直接绑定<br/>6443, 80, 443]
        K3sHost --> HostPorts
    end
    
    subgraph BridgeMode["Bridge 网络模式 (默认)"]
        direction TB
        NAS2[QNAP NAS<br/>IP: 192.168.31.88]
        Bridge[Docker Bridge<br/>docker0]
        K3sBridge[K3s 容器<br/>IP: 172.17.0.2]
        
        NAS2 --> Bridge
        Bridge --> K3sBridge
        
        NAT[NAT 转换<br/>-p 6443:6443]
        K3sBridge --> NAT
        NAT --> NAS2
    end
    
    Internet[互联网]
    
    HostPorts -.直接访问.-> Internet
    NAS2 --> Internet
    
    style K3sHost fill:#ccffcc
    style K3sBridge fill:#ffcccc
    style HostPorts fill:#ccffcc
    style NAT fill:#ffcccc
```

## 5. 代理配置的两个阶段

```mermaid
graph LR
    subgraph Stage1["阶段 1: 拉取基础镜像"]
        direction TB
        User1[用户执行<br/>docker pull]
        Daemon1[Docker Daemon]
        Config1[daemon.json<br/>代理配置]
        Proxy1[代理服务器]
        Registry1[Docker Hub]
        
        User1 --> Daemon1
        Config1 -.配置.-> Daemon1
        Daemon1 --> Proxy1
        Proxy1 --> Registry1
    end
    
    subgraph Stage2["阶段 2: K3s 拉取内部镜像"]
        direction TB
        User2[用户执行<br/>docker run -e HTTP_PROXY]
        K3s2[K3s 容器]
        Containerd2[Containerd]
        EnvVar2[环境变量<br/>HTTP_PROXY]
        Proxy2[代理服务器]
        Registry2[gcr.io/k8s.io]
        
        User2 --> K3s2
        EnvVar2 -.注入.-> K3s2
        K3s2 --> Containerd2
        Containerd2 --> Proxy2
        Proxy2 --> Registry2
    end
    
    Stage1 -.基础镜像就绪.-> Stage2
    
    style Config1 fill:#ffeb99
    style EnvVar2 fill:#ffeb99
```

## 6. 完整的网络数据流

```mermaid
flowchart TD
    Start([用户开始部署 K3s])
    
    CheckDaemonProxy{Docker Daemon<br/>配置了代理?}
    ConfigDaemon[配置 daemon.json]
    PullBase[docker pull rancher/k3s]
    PullSuccess{拉取成功?}
    
    CheckEnvProxy{docker run<br/>传递了 -e HTTP_PROXY?}
    AddEnvProxy[添加 -e 参数]
    RunK3s[启动 K3s 容器]
    
    K3sInit[K3s 初始化]
    PullInternal[拉取内部镜像<br/>pause/coredns/traefik]
    InternalSuccess{拉取成功?}
    
    K3sReady([K3s 就绪])
    Failed([部署失败])
    
    Start --> CheckDaemonProxy
    CheckDaemonProxy -->|否| ConfigDaemon
    CheckDaemonProxy -->|是| PullBase
    ConfigDaemon --> PullBase
    
    PullBase --> PullSuccess
    PullSuccess -->|否| Failed
    PullSuccess -->|是| CheckEnvProxy
    
    CheckEnvProxy -->|否| AddEnvProxy
    CheckEnvProxy -->|是| RunK3s
    AddEnvProxy --> RunK3s
    
    RunK3s --> K3sInit
    K3sInit --> PullInternal
    PullInternal --> InternalSuccess
    
    InternalSuccess -->|否| Failed
    InternalSuccess -->|是| K3sReady
    
    style ConfigDaemon fill:#ffe6e6
    style AddEnvProxy fill:#ffe6e6
    style K3sReady fill:#e6ffe6
    style Failed fill:#ff9999
```

## 7. QNAP 特定路径和组件

```mermaid
graph TB
    subgraph QNAP["QNAP NAS 文件系统"]
        direction TB
        
        subgraph ContainerStation["Container Station"]
            BinPath["/share/CACHEDEV1_DATA/.qpkg/<br/>container-station/bin/docker"]
            InitScript["/etc/init.d/<br/>container-station.sh"]
        end
        
        subgraph DockerConfig["Docker 配置"]
            DaemonJSON["/etc/docker/daemon.json"]
            DockerSock["/var/run/docker.sock"]
        end
        
        subgraph K3sConfig["K3s 配置"]
            K3sRegistry["/etc/rancher/k3s/<br/>registries.yaml"]
            K3sData["/var/lib/rancher/k3s"]
        end
    end
    
    subgraph Process["运行时进程"]
        DockerD[dockerd<br/>守护进程]
        K3sContainer[k3s 容器]
    end
    
    BinPath -.调用.-> DockerD
    InitScript -.启动.-> DockerD
    DaemonJSON -.配置.-> DockerD
    DockerD -.监听.-> DockerSock
    DockerD -.管理.-> K3sContainer
    K3sRegistry -.配置.-> K3sContainer
    K3sContainer -.数据.-> K3sData
    
    style DaemonJSON fill:#ffeb99
    style K3sRegistry fill:#ffeb99
```

## 8. 故障排查决策树

```mermaid
graph TD
    Problem([K3s 部署问题])
    
    Q1{docker pull<br/>能工作吗?}
    Q2{检查 daemon.json<br/>代理配置}
    Q3{K3s pods<br/>ImagePullBackOff?}
    Q4{检查 docker run<br/>-e HTTP_PROXY}
    Q5{检查 NO_PROXY<br/>设置}
    
    Fix1[配置 daemon.json<br/>重启 Docker]
    Fix2[添加 -e HTTP_PROXY<br/>到 docker run]
    Fix3[添加 NO_PROXY<br/>排除内部网络]
    
    Check1[检查代理服务器<br/>是否可达]
    Check2[检查防火墙规则]
    Check3[查看 K3s 日志<br/>docker logs k3s]
    
    Success([问题解决])
    
    Problem --> Q1
    Q1 -->|否| Q2
    Q1 -->|是| Q3
    
    Q2 -->|未配置| Fix1
    Q2 -->|已配置| Check1
    
    Q3 -->|是| Q4
    Q3 -->|否| Check3
    
    Q4 -->|未配置| Fix2
    Q4 -->|已配置| Q5
    
    Q5 -->|未配置| Fix3
    Q5 -->|已配置| Check2
    
    Fix1 --> Success
    Fix2 --> Success
    Fix3 --> Success
    Check1 --> Success
    Check2 --> Success
    Check3 --> Success
    
    style Fix1 fill:#ffe6e6
    style Fix2 fill:#ffe6e6
    style Fix3 fill:#ffe6e6
    style Success fill:#e6ffe6
```

## 9. 网络流量路径对比

```mermaid
graph LR
    subgraph Correct["✅ 正确配置"]
        direction TB
        C1[Docker CLI]
        C2[Docker Daemon<br/>+ daemon.json]
        C3[代理]
        C4[Registry]
        C5[K3s 容器<br/>+ HTTP_PROXY env]
        C6[Containerd]
        
        C1 --> C2
        C2 --> C3
        C3 --> C4
        C2 --> C5
        C5 --> C6
        C6 --> C3
    end
    
    subgraph Wrong["❌ 错误配置"]
        direction TB
        W1[Docker CLI<br/>+ export HTTP_PROXY]
        W2[Docker Daemon<br/>无代理配置]
        W3[K3s 容器<br/>无环境变量]
        W4[Containerd]
        W5[Registry<br/>连接失败]
        
        W1 -.不继承.-> W2
        W2 -.X.-> W5
        W2 --> W3
        W3 --> W4
        W4 -.X.-> W5
    end
    
    style C2 fill:#ccffcc
    style C5 fill:#ccffcc
    style W2 fill:#ffcccc
    style W3 fill:#ffcccc
    style W5 fill:#ffcccc
```

## 10. 时间线：从零到 K3s 运行

```mermaid
gantt
    title K3s 部署时间线
    dateFormat X
    axisFormat %s
    
    section 准备阶段
    配置 daemon.json           :done, prep1, 0, 30
    重启 Docker Daemon        :done, prep2, 30, 40
    
    section 镜像拉取
    docker pull rancher/k3s   :active, pull1, 40, 120
    验证镜像                   :pull2, 120, 130
    
    section 容器启动
    docker run with -e        :run1, 130, 140
    K3s 初始化                :run2, 140, 160
    
    section 内部镜像
    拉取 pause 镜像           :internal1, 160, 180
    拉取 coredns 镜像         :internal2, 180, 210
    拉取 traefik 镜像         :internal3, 210, 240
    
    section 就绪
    K3s 集群就绪              :crit, ready, 240, 250
```

---

## 使用说明

这些图表可以帮助你：

1. **理解架构**：图 1、4、7 展示了整体架构
2. **追踪流程**：图 2、3、6 展示了详细的执行流程
3. **对比方案**：图 4、9 对比了不同的配置方式
4. **排查问题**：图 8 提供了故障排查路径
5. **规划部署**：图 10 展示了部署时间线

所有图表都可以在支持 Mermaid 的 Markdown 查看器中渲染（如 GitHub、GitLab、Obsidian、Typora 等）。
