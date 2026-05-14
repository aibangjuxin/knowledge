# Multistage Builds 迁移指南

本指南详细说明了如何将现有的 Java 应用 Docker 构建流程迁移到 Multistage Builds (多阶段构建) 模式。

## 1. 准备工作
*   确保您拥有项目的完整源代码 (不仅仅是 JAR 包)。
*   确保项目根目录下有构建描述文件 (如 `pom.xml` 或 `build.gradle`)。
*   确认 Docker 版本 >= 17.05。

## 2. 迁移步骤

### 步骤 1: 调整项目结构
目前的构建依赖于外部生成的 JAR 包。我们需要将构建过程移入 Docker。
确保您的项目结构类似如下：
```text
.
├── pom.xml
├── src/
│   ├── main/
│   └── test/
└── Dockerfile (我们将新建这个文件)
```

### 步骤 2: 备份旧配置
将原有的 `Dockerfile` 重命名备份：
```bash
mv Dockerfile Dockerfile.legacy
```

### 步骤 3: 创建新的 Dockerfile
在项目根目录创建名为 `Dockerfile` 的文件，内容参考同目录下的 `Dockerfile.new`。

**关键修改点说明**:
*   **移除 `apt-get`**: 我们不再需要在运行时安装 `curl` 或 `wget` (除非用于特殊调试)。
*   **移除 `wrapper.sh`**: 启动逻辑直接写在 `ENTRYPOINT` 中。
*   **移除 `COPY *.jar`**: 改为 `COPY --from=builder ...`。

### 步骤 4: 执行构建
使用标准的 Docker build 命令。注意，现在不需要传入 `API_NAME` 或 `API_VERSION` 来定位 JAR 包了，因为 JAR 包是在构建过程中生成的。

```bash
# 旧命令 (示例)
# docker build -t myapp:v1 --build-arg API_NAME=myapp ... .

# 新命令
docker build -t myapp:v1 .
```

如果需要传入版本号作为构建参数，可以在 Dockerfile 中使用 `ARG`：

```dockerfile
# 在 Dockerfile 中添加
ARG APP_VERSION=1.0.0
RUN mvn versions:set -DnewVersion=${APP_VERSION}
```

### 步骤 5: 验证与测试

由于使用了 Distroless 镜像，您无法使用 `docker exec -it <container> /bin/bash` 进入容器。

**如何验证应用是否正常运行？**
1.  **查看日志**:
    ```bash
    docker logs <container_id>
    ```
2.  **检查端口**:
    确保应用端口 (如 8080) 能够被外部访问。
3.  **调试模式 (如果必须)**:
    如果容器启动失败且日志不清晰，可以使用 debug 版本的 distroless 镜像临时调试：
    *   修改 Dockerfile: `FROM gcr.io/distroless/java17-debian11:debug AS runtime`
    *   重新构建并运行。
    *   进入容器: `docker exec -it <container> /busybox/sh`

## 3. 常见问题排查

*   **问题**: 构建速度变慢。
    *   **原因**: 每次都需要下载 Maven 依赖。
    *   **解决**: 确保 Dockerfile 中先 `COPY pom.xml` 并运行 `mvn dependency:go-offline`，然后再 `COPY src`。这样只要 `pom.xml` 不变，依赖下载层就会被 Docker 缓存。

*   **问题**: 缺少运行时配置文件。
    *   **解决**: 如果应用需要读取 `/opt/config` 下的文件，请在 Dockerfile 的 `Stage 2` 中使用 `COPY` 指令将配置文件从本地或 Builder 阶段复制进去。
