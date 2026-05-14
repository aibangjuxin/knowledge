# GKE Java Native Memory Tracking (NMT) 日志采集方案

针对你提到的 "不想放在 Pod 里面（/tmp），担心 Pod 重置丢失" 的问题，以及希望将 NMT (Native Memory Tracking) 日志集成到 **Google Cloud Logging (Log Explorer)** 的需求，以下是标准的云原生解决方案。

核心思路：**不要写文件，全部打到 Standard Output (标准输出)**。GKE 的 logging agent 会自动采集 stdout/stderr 并发送到 Cloud Logging，即使 Pod 挂了，日志也会保留在云端。

---

## 方案一：启动参数自动输出（适用于正常退出）

你提到的参数：
```yaml
env:
  - name: JAVA_TOOL_OPTIONS
    value: "-XX:NativeMemoryTracking=detail -XX:+UnlockDiagnosticVMOptions -XX:+PrintNMTStatistics"
```
*   **机制**：`PrintNMTStatistics` 会在 JVM **正常退出**（调用 exit 钩子）时，将内存统计信息打印到 **Stdout**（标准输出）。
*   **效果**：这些日志会自动出现在 Google Log Explorer 中。
*   **局限性**：如果 Pod 是被 `OOMKilled`（SIGKILL）杀掉的，JVM 来不及运行退出钩子，**这条日志不会打印**。这通常是用户最头痛的地方——**死因不明，且死前没留遗言**。

---

## 方案二：周期性快照（强烈推荐，针对 OOMKilled）

为了解决 "崩溃前不仅没日志，文件还丢了" 的问题，你需要一个**周期性任务**，每隔一段时间（如 1 分钟）执行一次 `jcmd` 并将结果打印到标准输出。

### 实现方式 1：Entrypoint 脚本（最简单，无需 Sidecar）

修改 Docker 镜像的启动命令，或者在 K8s deployment 的 `command` 中注入脚本。

**Deployment YAML 示例：**

```yaml
spec:
  containers:
  - name: java-app
    image: your-java-image
    env:
    - name: JAVA_TOOL_OPTIONS
      value: "-XX:NativeMemoryTracking=detail -XX:+UnlockDiagnosticVMOptions"
    command: ["/bin/sh", "-c"]
    args:
    - |
      # 1. 后台启动 Java 应用
      java -jar /app/app.jar &
      PID=$!

      # 2. 启动监控循环
      # 每 60 秒打印一次 NMT Summary 到标准输出
      while kill -0 $PID > /dev/null 2>&1; do
        echo "=== [NMT Monitor] Timestamp: $(date) ==="
        jcmd $PID VM.native_memory summary
        sleep 60
      done &

      # 3. 等待 Java 进程结束（传递信号）
      wait $PID
```

**优点**：
1.  **日志持久化**：`echo` 和 `jcmd` 的输出直接进入容器 stdout，最终进入 Google Log Explorer。
2.  **抗 OOM**：即使 Pod 下一秒被杀，上一分钟的 NMT 快照已经上传到云端，你可以看到内存增长的趋势。
3.  **无临时文件**：不需要 `/tmp` 存储。

---

## 方案三：Sidecar 模式（更解耦，适用于 Distroless 镜像）

如果你的主镜像很精简（Distroless），没有 shell 或 `jcmd`，你可以用一个带 JDK 工具的 Sidecar。

**前提**：开启 `shareProcessNamespace: true`。

```yaml
spec:
  shareProcessNamespace: true # 关键！允许 Sidecar 看到主容器进程
  containers:
  - name: java-app
    image: your-distroless-java-image
    # ... 你的 Java 配置 ...

  - name: nmt-monitor
    image: eclipse-temurin:17-jdk # 使用带 jcmd 的镜像
    command: ["/bin/sh", "-c"]
    args:
    - |
      # 循环查找 Java 进程并打印 NMT
      while true; do
        # 在共享进程空间中找到 Java 进程 PID (通常不是 1 了)
        PID=$(jps | grep jar | cut -d ' ' -f 1)
        if [ -n "$PID" ]; then
           echo "=== [Sidecar NMT] ==="
           jcmd $PID VM.native_memory summary
        fi
        sleep 60
      done
```

---

## Google Log Explorer 查询技巧

日志进云端了，怎么在海量日志里找到它？

在 Google Cloud Console -> Logging -> Logs Explorer 中使用以下查询：

**1. 查找 NMT 统计块：**

```text
resource.type="k8s_container"
jsonPayload.message =~ "Native Memory Tracking:"
```

**2. 查找我们自定义的脚本输出：**

```text
jsonPayload.message =~ "=== \[NMT Monitor\]"
```

**3. 排除干扰（使用 log-based metric 进阶）：**
你可以将这些特定日志转化为 Metric，直接在 Monitoring 面板画出 Non-Heap 内存增长曲线。

---

## 总结建议

1.  **不要依赖文件**：Pod 中写文件既不持久也不方便查看。
2.  **Stdout 是王道**：GKE 完美集成了 stdout -> Cloud Logging，利用这一点。
3.  **应对 OOMKilled**：仅靠 `-XX:+PrintNMTStatistics` 是不够的，必须配合 **Shell Loop** 或 **Sidecar** 进行周期性采样。
4.  **Java 版本注意**：NMT 会带来 5%-10% 的性能损耗，生产环境建议只开启 `summary` 级别（`-XX:NativeMemoryTracking=summary`），只有在深度排查泄漏时才开 `detail`。
