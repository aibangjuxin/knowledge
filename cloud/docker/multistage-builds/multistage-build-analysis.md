# Multistage Builds 深度分析与实施方案 (Java 应用)

## 1. 概述
多阶段构建 (Multistage Builds) 是 Docker 17.05 引入的一项重要功能，它允许在一个 Dockerfile 中使用多个 `FROM` 指令。每个 `FROM` 指令都可以使用不同的基础镜像，并且每个指令都开始构建的一个新阶段。你可以选择性地将工件从一个阶段复制到另一个阶段，从而在最终镜像中只保留运行应用所需的内容。

对于 Java 应用，这意味着我们可以将 **编译环境** (Maven/Gradle + JDK) 与 **运行环境** (JRE) 分离。

## 2. 现状分析 (As-Is)
根据您提供的旧模板 (`multistage-build-concepts.md`)，目前的构建流程存在以下特点：
1.  **外部构建**: `COPY ${API_NAME}-${API_VERSION}.jar` 表明 JAR 包是在 Docker 构建之前由 CI 工具 (如 Jenkins) 生成的。
2.  **基础镜像臃肿**: 使用了 `zuljava-jre-Ubuntu-17`。Ubuntu 基础镜像通常包含大量未使用的系统库，导致镜像体积大，攻击面广。
3.  **手动安装依赖**: 在 Dockerfile 中运行 `apt-get update` 安装 `curl`, `wget` 等。这增加了构建时间，且使得镜像层变大。
4.  **依赖 Shell 脚本**: 使用 `wrapper.sh` 启动应用。这要求基础镜像必须包含 Shell (`/bin/bash`)。

## 3. 目标方案 (To-Be) - Multistage + Distroless
根据您的需求 ("Java类型的应用", "Use distroless image")，我们推荐以下架构：

### 3.1 架构设计
*   **Stage 1: Builder (构建层)**
    *   **Base Image**: `maven:3.8-eclipse-temurin-17` (或 Gradle 对应镜像)。
    *   **任务**: 下载依赖，编译源码，打包生成 JAR 文件。
    *   **产物**: `app.jar`。
*   **Stage 2: Runtime (运行层)**
    *   **Base Image**: `gcr.io/distroless/java17-debian11`。
    *   **特点**: Google 提供的极简镜像，**不包含 Shell**，不包含包管理器 (apt/yum)，只包含运行 Java 所需的最小依赖。
    *   **优势**:
        *   **安全性**: 攻击者无法在容器内运行 Shell 命令，极大减少了攻击面。
        *   **体积**: 通常只有几十 MB (相比 Ubuntu 的几百 MB)。
        *   **合规**: 扫描出的 CVE 漏洞极少。

### 3.2 关键挑战与解决方案
1.  **Wrapper Script (`wrapper.sh`)**:
    *   *问题*: Distroless 镜像没有 `/bin/bash` 或 `/bin/sh`，无法运行 shell 脚本。
    *   *解决*: 直接在 Dockerfile 中使用 `ENTRYPOINT ["java", "-jar", "/app/app.jar"]`。如果 `wrapper.sh` 中有复杂的启动逻辑 (如动态计算参数)，建议将这些逻辑移入 Java 代码中 (例如在 `main` 函数启动前处理)，或者使用 Kubernetes 的 `initContainers` 处理环境准备。
2.  **调试工具 (`curl`, `wget`)**:
    *   *问题*: Distroless 不包含这些工具。
    *   *解决*:
        *   **Healthcheck**: 使用 Kubernetes 的 HTTP Probe 或 TCP Probe，或者使用 Java 编写的轻量级 Healthcheck。
        *   **调试**: 如果必须进入容器调试，可以使用 `gcr.io/distroless/java17-debian11:debug` 标签 (包含 busybox shell)，或者使用 `kubectl debug` 临时挂载调试容器。

## 4. 迁移步骤
1.  **整合构建过程**: 将 Maven/Gradle 构建步骤移入 Dockerfile。
2.  **移除 Shell 依赖**: 废弃 `wrapper.sh`，改用直接命令启动。
3.  **调整用户权限**: Distroless 默认支持 `nonroot` 用户，或者我们可以复用您定义的 `apiadmin` (但在 Distroless 中创建用户比较麻烦，通常建议使用内置的 `nonroot` 或通过 ID 运行)。

---

## 5. 新 Dockerfile 模板建议

以下是基于您旧模板改造的 Multistage Build 模板。

### 方案 A: 标准 Multistage (推荐，使用 Distroless)
*适用于追求极致安全和最小体积的场景。注意：此方案无法运行 shell 脚本。*

```dockerfile
# ==========================================
# Stage 1: Builder
# ==========================================
FROM maven:3.9-eclipse-temurin-17 AS builder

# 设置工作目录
WORKDIR /build

# 优化: 先拷贝 pom.xml 下载依赖，利用 Docker 缓存
COPY pom.xml .
# 如果有 settings.xml 私服配置，也需要拷贝
# COPY settings.xml /usr/share/maven/ref/

# 下载依赖 (这一步会缓存，除非 pom.xml 变动)
RUN mvn dependency:go-offline

# 拷贝源码
COPY src ./src

# 构建打包 (跳过测试以加快构建，测试应在 CI 流水线前置步骤完成)
RUN mvn package -DskipTests

# ==========================================
# Stage 2: Runtime
# ==========================================
# 使用 Google Distroless Java 17 镜像
FROM gcr.io/distroless/java17-debian11 AS runtime

# 设置环境变量
ENV API_NAME=myapp \
    API_VERSION=1.0.0

# 从 Builder 阶段拷贝 JAR 包
# 假设构建出的 jar 在 target 目录下，重命名为 app.jar 方便管理
COPY --from=builder /build/target/*.jar /app/app.jar

# Distroless 默认以 nonroot (uid: 65532) 运行，无需手动 useradd
# 如果必须使用特定 UID (如 3000)，Distroless 比较困难，建议适应 nonroot
USER 65532:65532

# 工作目录
WORKDIR /app

# 启动命令 (Distroless 必须使用 exec 格式 ["cmd", "arg"])
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 方案 B: 兼容型 Multistage (使用 Slim JRE)
*如果您**必须**保留 `wrapper.sh` 或需要在容器内运行 `curl` 等命令，请使用此方案。*

```dockerfile
# ==========================================
# Stage 1: Builder (同上)
# ==========================================
FROM maven:3.9-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn package -DskipTests

# ==========================================
# Stage 2: Runtime
# ==========================================
# 使用轻量级 JRE 镜像 (基于 Alpine 或 Slim Debian)
FROM eclipse-temurin:17-jre-focal AS runtime

ENV API_NAME=myapp \
    API_VERSION=1.0.0

# 安装必要的工具 (如果必须)
# RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# 创建用户 (保留您原有的逻辑)
RUN groupadd -g 3000 apigroup && \
    useradd -u 3000 -g 3000 -ms /bin/bash apiadmin

WORKDIR /opt/apps

# 从 Builder 拷贝 JAR
COPY --from=builder /build/target/*.jar ./app.jar
COPY wrapper.sh /opt/wrapper.sh

RUN chmod +x /opt/wrapper.sh && \
    chown -R apiadmin:apigroup /opt

USER apiadmin

CMD ["/opt/wrapper.sh"]
```

## 6. 总结
对于您的平台：
1.  **推荐尝试方案 A (Distroless)**。这是云原生最佳实践，虽然初期可能需要调整习惯 (放弃 shell)，但长远来看维护成本和安全风险最低。
2.  **如果阻力较大，使用方案 B**。它保留了 shell 环境，但依然享受了 Multistage Builds 带来的构建环境分离和镜像体积减小的红利。
