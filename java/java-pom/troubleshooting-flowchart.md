# Java Maven 依赖问题排查流程图

## 完整排查流程

```mermaid
graph TD
    Start[CI Pipeline 构建失败] --> Error{错误类型?}
    
    Error -->|package does not exist| CompileError[编译错误]
    Error -->|Could not transfer| DownloadError[下载错误]
    Error -->|COPY failed| DockerError[Docker 错误]
    Error -->|ClassNotFoundException| RuntimeError[运行时错误]
    
    CompileError --> CheckPom{pom.xml 中<br/>有依赖声明?}
    CheckPom -->|否| AddDep[添加依赖声明]
    CheckPom -->|是| CheckScope{Scope<br/>配置正确?}
    
    CheckScope -->|否| FixScope[修正 Scope]
    CheckScope -->|是| CheckEnv[对比本地与 CI 环境]
    
    CheckEnv --> EnvDiff{发现差异?}
    EnvDiff -->|Maven 版本| UnifyMaven[统一 Maven 版本]
    EnvDiff -->|JDK 版本| UnifyJDK[统一 JDK 版本]
    EnvDiff -->|settings.xml| ConfigSettings[配置 settings.xml]
    EnvDiff -->|网络访问| CheckNetwork[检查网络/Nexus]
    
    DownloadError --> CheckSettings{settings.xml<br/>配置正确?}
    CheckSettings -->|否| ConfigSettings
    CheckSettings -->|是| CheckNexus{Nexus<br/>可访问?}
    
    CheckNexus -->|否| FixNetwork[修复网络/代理]
    CheckNexus -->|是| CheckRepo{依赖在<br/>仓库中?}
    
    CheckRepo -->|否| UploadDep[上传依赖到 Nexus]
    CheckRepo -->|是| CheckAuth[检查认证信息]
    
    DockerError --> CheckJar{JAR 包<br/>是否生成?}
    CheckJar -->|否| BackToMaven[返回 Maven 构建问题]
    CheckJar -->|是| CheckPath[检查 COPY 路径]
    
    RuntimeError --> CheckRuntimeScope{依赖 Scope<br/>是 test?}
    CheckRuntimeScope -->|是| ChangeScope[改为 compile]
    CheckRuntimeScope -->|否| CheckPackaging[检查打包配置]
    
    AddDep --> Verify[验证修复]
    FixScope --> Verify
    UnifyMaven --> Verify
    UnifyJDK --> Verify
    ConfigSettings --> Verify
    CheckNetwork --> Verify
    FixNetwork --> Verify
    UploadDep --> Verify
    CheckAuth --> Verify
    CheckPath --> Verify
    ChangeScope --> Verify
    CheckPackaging --> Verify
    
    Verify --> Test{构建成功?}
    Test -->|是| Success[问题解决]
    Test -->|否| DeepDive[深度诊断]
    
    DeepDive --> RunScript[运行诊断脚本]
    RunScript --> AnalyzeLog[分析详细日志]
    AnalyzeLog --> ContactSupport[联系技术支持]
    
    BackToMaven --> CompileError
    
    style CompileError fill:#ff6b6b
    style DownloadError fill:#ff6b6b
    style DockerError fill:#ffd93d
    style RuntimeError fill:#ff6b6b
    style Success fill:#51cf66
```

## 责任判定流程

```mermaid
graph TD
    Issue[构建问题] --> Stage{发生阶段?}
    
    Stage -->|Maven compile| UserIssue1[用户责任]
    Stage -->|Maven package| UserIssue2[用户责任]
    Stage -->|Dockerfile COPY| CheckJar{JAR 存在?}
    Stage -->|容器运行时| CheckType{错误类型?}
    
    CheckJar -->|否| UserIssue3[用户责任:<br/>Maven 构建失败]
    CheckJar -->|是| PlatformIssue1[平台责任:<br/>COPY 路径错误]
    
    CheckType -->|ClassNotFoundException| UserIssue4[用户责任:<br/>依赖 Scope 错误]
    CheckType -->|系统库缺失| PlatformIssue2[平台责任:<br/>基础镜像问题]
    
    UserIssue1 --> UserAction[用户自查:<br/>pom.xml<br/>settings.xml<br/>网络配置]
    UserIssue2 --> UserAction
    UserIssue3 --> UserAction
    UserIssue4 --> UserAction
    
    PlatformIssue1 --> PlatformAction[平台支持:<br/>检查 Dockerfile<br/>修复配置]
    PlatformIssue2 --> PlatformAction
    
    style UserIssue1 fill:#ff6b6b
    style UserIssue2 fill:#ff6b6b
    style UserIssue3 fill:#ff6b6b
    style UserIssue4 fill:#ff6b6b
    style PlatformIssue1 fill:#4ecdc4
    style PlatformIssue2 fill:#4ecdc4
```

## 快速诊断决策树

```mermaid
graph TD
    Start[错误: package does not exist] --> Q1{本地构建<br/>是否成功?}
    
    Q1 -->|是| EnvDiff[环境差异问题]
    Q1 -->|否| LocalIssue[本地配置问题]
    
    EnvDiff --> Q2{CI 有<br/>settings.xml?}
    Q2 -->|否| A1[配置 CI settings.xml]
    Q2 -->|是| Q3{Maven/JDK<br/>版本一致?}
    
    Q3 -->|否| A2[统一版本]
    Q3 -->|是| Q4{CI 有<br/>依赖缓存?}
    
    Q4 -->|否| A3[启用缓存或<br/>首次下载依赖]
    Q4 -->|是| Q5{网络可访问<br/>Nexus?}
    
    Q5 -->|否| A4[配置网络/代理]
    Q5 -->|是| DeepCheck[深度检查:<br/>运行诊断脚本]
    
    LocalIssue --> Q6{pom.xml 中<br/>有依赖?}
    Q6 -->|否| A5[添加依赖声明]
    Q6 -->|是| Q7{Scope<br/>正确?}
    
    Q7 -->|否| A6[修正 Scope]
    Q7 -->|是| Q8{settings.xml<br/>配置正确?}
    
    Q8 -->|否| A7[配置 settings.xml]
    Q8 -->|是| Q9{Nexus<br/>可访问?}
    
    Q9 -->|否| A8[检查网络]
    Q9 -->|是| A9[检查 Nexus<br/>是否有该依赖]
    
    A1 --> Verify[验证修复]
    A2 --> Verify
    A3 --> Verify
    A4 --> Verify
    A5 --> Verify
    A6 --> Verify
    A7 --> Verify
    A8 --> Verify
    A9 --> Verify
    DeepCheck --> Verify
    
    Verify --> Success{成功?}
    Success -->|是| Done[问题解决]
    Success -->|否| Support[联系技术支持]
    
    style A1 fill:#51cf66
    style A2 fill:#51cf66
    style A3 fill:#51cf66
    style A4 fill:#51cf66
    style A5 fill:#51cf66
    style A6 fill:#51cf66
    style A7 fill:#51cf66
    style A8 fill:#51cf66
    style A9 fill:#51cf66
    style Done fill:#51cf66
```

## 依赖解析流程

```mermaid
graph LR
    A[Maven 构建开始] --> B[读取 pom.xml]
    B --> C[读取 settings.xml]
    C --> D[解析依赖声明]
    
    D --> E{本地仓库<br/>有缓存?}
    E -->|是| F[使用缓存]
    E -->|否| G[从远程仓库下载]
    
    G --> H{配置了<br/>镜像?}
    H -->|是| I[从镜像下载]
    H -->|否| J[从 Maven Central 下载]
    
    I --> K{下载成功?}
    J --> K
    
    K -->|是| L[保存到本地仓库]
    K -->|否| M[构建失败]
    
    L --> N[解析传递依赖]
    N --> O[编译源码]
    
    O --> P{编译成功?}
    P -->|是| Q[打包 JAR]
    P -->|否| R[报错: package not exist]
    
    F --> N
    
    M --> S[错误: Could not transfer]
    R --> T[错误: package does not exist]
    
    Q --> U[构建成功]
    
    style M fill:#ff6b6b
    style R fill:#ff6b6b
    style S fill:#ff6b6b
    style T fill:#ff6b6b
    style U fill:#51cf66
```

## CI/CD 完整流程

```mermaid
graph TB
    subgraph "用户责任范围"
        A[源码提交] --> B[触发 CI Pipeline]
        B --> C[Maven 环境准备]
        C --> D[读取 pom.xml]
        D --> E[读取 settings.xml]
        E --> F[下载依赖]
        F --> G{依赖解析<br/>成功?}
        G -->|否| H[构建失败]
        G -->|是| I[编译源码]
        I --> J{编译<br/>成功?}
        J -->|否| H
        J -->|是| K[运行测试]
        K --> L[打包 JAR]
    end
    
    subgraph "平台责任范围"
        L --> M[Dockerfile 构建]
        M --> N[COPY JAR 到镜像]
        N --> O[配置运行环境]
        O --> P[构建容器镜像]
        P --> Q[推送到镜像仓库]
        Q --> R[部署到 GKE]
    end
    
    H --> X[用户排查:<br/>依赖配置<br/>环境配置<br/>网络配置]
    
    style H fill:#ff6b6b
    style X fill:#ff6b6b
    style R fill:#51cf66
```

## 问题分类矩阵

```mermaid
graph TD
    subgraph "编译时问题 (用户责任)"
        C1[package does not exist]
        C2[Could not resolve dependencies]
        C3[Version conflict]
        C4[Could not transfer artifact]
    end
    
    subgraph "构建时问题 (用户/平台)"
        B1[COPY failed: no JAR]
        B2[COPY failed: path error]
        B3[Docker build timeout]
    end
    
    subgraph "运行时问题 (用户/平台)"
        R1[ClassNotFoundException]
        R2[NoClassDefFoundError]
        R3[UnsatisfiedLinkError]
        R4[java: command not found]
    end
    
    C1 --> U1[用户: 添加依赖]
    C2 --> U2[用户: 配置仓库]
    C3 --> U3[用户: 版本管理]
    C4 --> U4[用户: 网络配置]
    
    B1 --> U5[用户: 检查 Maven 构建]
    B2 --> P1[平台: 修复 Dockerfile]
    B3 --> P2[平台: 优化构建]
    
    R1 --> U6[用户: 修正 Scope]
    R2 --> U7[用户: 检查打包]
    R3 --> P3[平台: 系统库]
    R4 --> P4[平台: 基础镜像]
    
    style C1 fill:#ff6b6b
    style C2 fill:#ff6b6b
    style C3 fill:#ff6b6b
    style C4 fill:#ff6b6b
    style B1 fill:#ffd93d
    style B2 fill:#4ecdc4
    style B3 fill:#4ecdc4
    style R1 fill:#ff6b6b
    style R2 fill:#ff6b6b
    style R3 fill:#4ecdc4
    style R4 fill:#4ecdc4
```

## 使用说明

### 如何使用这些流程图

1. **遇到问题时**
   - 从"完整排查流程"开始
   - 根据错误类型选择分支
   - 按照流程逐步排查

2. **判断责任时**
   - 使用"责任判定流程"
   - 快速确定是用户还是平台问题
   - 采取相应措施

3. **快速诊断时**
   - 使用"快速诊断决策树"
   - 回答一系列是/否问题
   - 快速定位问题

4. **理解流程时**
   - 查看"依赖解析流程"
   - 了解 Maven 如何解析依赖
   - 理解问题发生的位置

5. **全局视角时**
   - 查看"CI/CD 完整流程"
   - 理解用户和平台的责任边界
   - 把握整体架构

### 颜色说明

- 🔴 红色 (#ff6b6b): 用户责任问题
- 🔵 蓝色 (#4ecdc4): 平台责任问题
- 🟡 黄色 (#ffd93d): 需要进一步判断
- 🟢 绿色 (#51cf66): 成功/解决方案

### 相关文档

- [完整排查指南](./wiremock-dependency-troubleshooting.md)
- [快速排查清单](./dependency-issue-checklist.md)
- [诊断脚本](./ci-diagnostic-script.sh)
- [README](./README.md)
