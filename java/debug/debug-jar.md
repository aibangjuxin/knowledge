# Debug Guide: 如何在 GKE 中“解剖”无法启动的 JAR 包

**场景描述**：
- 你的 CI/CD Pipeline 已经成功构建并推送了镜像到 GCP GAR。
- 部署到 GKE 后，Pod 状态为 `CrashLoopBackOff` 或 `Error`。
- 你需要确认：**“镜像里的 JAR 包到底是不是我预期的那个？里边是不是混进了旧版本的依赖？”**
- **难点**：Pod 起不来，`kubectl exec` 进不去；或者镜像为了安全（Distroless）里面根本没有 `sh`, `ls`, `jar` 等命令。

本文档提供一套标准化的 **“法医式”排查流程**，重点介绍如何使用工具容器（Sidecar）进行无侵入式文件分析。

---

## 1️⃣ 第一步：让 Pod “活”下来 (Hold the Door)

如果应用一启动就挂，我们首先要“阉割”掉启动命令，强行让容器保持运行状态，以便我们进去检查。

### 修改 Deployment 入口

修改你的 Deployment YAML（或直接在 GKE 控制台/Lens 编辑），将 `command` 覆盖为 **休眠命令**。

**YAML 修改示例：**

```yaml
spec:
  containers:
    - name: my-java-app
      image: us-docker.pkg.dev/my-project/my-repo/my-app:v1.0.0
      # 👇 关键修改：覆盖默认的 java -jar 启动命令
      command: ["/bin/sh", "-c"]
      args: ["echo 'Debug Mode Started'; sleep 36000"]
      # 如果是 Distroless 镜像（没有 shell），请尝试 ["/busybox/sleep", "36000"] 或直接跳到下文“方案二”
```

*应用更改后，Pod 应该会变成 `Running` 状态，但什么都不做。*

---


## 2️⃣ 第二步：注入“工具人” Sidecar (Ephemeral Container)

这是你提到的 **“类似 network-multitool”** 的核心用法。
如果你的业务镜像很精简（如基于 Alpine 或 Distroless），里面没有 `jar`, `unzip`, `vi` 等工具，我们需要**动态挂载一个装满工具的 Sidecar** 到这个 Pod 里。

### 使用 `kubectl debug` 注入工具容器

假设你的 Pod 名字是 `my-java-app-pod-xyz`，容器名是 `my-java-app`。

我们使用 `wbitt/network-multitool`（或者你自己构建的带 JDK 的工具镜像）作为 Debug 容器。

```bash
# 语法：kubectl debug -it <POD_NAME> --image=<TOOL_IMAGE> --target=<APP_CONTAINER>

kubectl debug -it my-java-app-pod-xyz \
  --image=wbitt/network-multitool \
  --target=my-java-app \
  -- sh
```

### 🧐 核心原理：`--target` 参数

*   **如果不加 `--target`**：Debug 容器和业务容器只是在同一个 Pod 里，文件系统是隔离的。你看不到业务容器里的 JAR。
*   **加上 `--target`**：Debug 容器会 **共享业务容器的进程命名空间 (Process Namespace)**。
    *   这意味着：你可以通过 `/proc/1/root/` 目录直接访问业务容器的文件系统！

---


## 3️⃣ 第三步：像法医一样解剖 JAR 包

现在你已经在 Debug 容器（`network-multitool`）的 Shell 里了。

### 1. 找到目标 JAR 文件

业务容器的文件系统映射在 `/proc/1/root` 下。

```bash
# 进入业务容器的目录结构
cd /proc/1/root/opt/apps/

# 确认文件存在
ls -lh
# 预期输出：app-1.0.0.jar
```

### 2. 检查 JAR 包指纹 (Hash)

首先确认这是不是你刚刚构建的那个包（防止 CI 没推上去，或者拉了旧镜像）。

```bash
md5sum app-*.jar
# 或
sha256sum app-*.jar
```

*对比 CI 构建日志中的 Hash 值。*

### 3. “透视” JAR 包内容 (不解压)

如果在 `network-multitool` 里安装了 `zip` 或 `jdk` 工具（如果原装没有，可以 `apk add openjdk17` 安装），你可以直接透视 JAR。

**场景 A：检查是否混入了旧版 Spring Boot**

```bash
# 列出 JAR 包内所有文件，过滤 spring-boot
unzip -l app-*.jar | grep "spring-boot"

# 预期输出示例：
# 05-20-2023 10:00   BOOT-INF/lib/spring-boot-2.7.10.jar  <-- ✅ 期望版本
# 05-20-2023 10:00   BOOT-INF/lib/spring-boot-2.6.6.jar   <-- ❌ 发现旧版本毒瘤！
```

**场景 B：检查 SnakeYAML 版本（针对之前的报错）**

```bash
unzip -l app-*.jar | grep "snakeyaml"
```

**场景 C：查看 MANIFEST.MF (构建元数据)**

```bash
unzip -p app-*.jar META-INF/MANIFEST.MF
```

### 4. 暴力拆解 (如果需要反编译 class)

如果需要把文件拿出来分析：

1.  **复制出来**：`cp /proc/1/root/opt/apps/app.jar /tmp/analyzed.jar`
2.  **解压**：`unzip /tmp/analyzed.jar -d /tmp/output`
3.  **检查具体 Class**：
    如果你怀疑某个 `.class` 文件不仅版本对，但内容不对（比如被篡改），可以计算它的 Hash：
    ```bash
    md5sum /tmp/output/BOOT-INF/lib/some-lib.jar
    ```

---


## 4️⃣ 替代方案：本地 Docker 分析 (Local Debug)

如果你有权限拉取镜像到本地电脑，这通常比在 K8S 上操作更方便。

```bash
# 1. 拉取镜像
docker pull us-docker.pkg.dev/my-project/repo/app:v1.0.0

# 2. 交互式启动（覆盖入口）
docker run -it --entrypoint sh us-docker.pkg.dev/my-project/repo/app:v1.0.0

# 3. 如果是 Distroless (无 Shell) 镜像，无法进入，则使用 export 导出文件系统
docker create --name temp-container us-docker.pkg.dev/my-project/repo/app:v1.0.0
docker export temp-container > image_fs.tar
tar -tvf image_fs.tar | grep ".jar" # 在 tar 包里直接搜
```

---


## 5️⃣ 总结 Checklist

当你怀疑 JAR 包内容有问题时，按此顺序排查：

1.  **Hold**: 修改 Deployment `command` 为 `sleep 3600`，让 Pod 保持 Running。
2.  **Inject**: `kubectl debug ... --target=app --image=network-multitool`。
3.  **Locate**: `cd /proc/1/root/opt/apps/`。
4.  **Inspect**:
    *   `md5sum` 校验整体完整性。
    *   `unzip -l ... | grep <lib>` 校验依赖版本冲突。
5.  **Fix**: 如果发现旧包，回到 CI Pipeline 检查 Maven Cache (`mvn dependency:tree`)。
