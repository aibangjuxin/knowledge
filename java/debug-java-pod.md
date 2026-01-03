# Debug Java Pod: Inspect Failed JAR Images with Sidecar Network-Multitool

## Overview

针对 GKE 中 Java 应用 Pod 启动失败（CrashLoopBackOff/Error）的场景，使用此方法无侵入式检查 JAR 包内容（依赖版本、MANIFEST 等），无需修改原镜像。

**核心思路**：
- 创建 Debug Deployment：使用目标镜像，但覆盖 `command` 为 `sleep`，确保 Pod `Running`。
- 使用 `kubectl debug` 注入 **network-multitool** 作为临时 Sidecar，共享目标容器的进程命名空间（`/proc/1/root/`）。
- 在 Debug 容器中直接"透视" JAR 文件系统。

此方法基于 [@java/debug-jar.md](java/debug-jar.md) 和 [@java/debug-Java-jar.md](java/debug-Java-jar.md) 的最佳实践优化。

## Prerequisites

- kubectl 配置好 GKE 集群上下文
- 对目标命名空间有 Deployment/Pod 创建权限
- 可拉取 GAR 镜像（若私有，配置 imagePullSecrets）
- 假设 JAR 路径：`/opt/apps/*.jar`（根据实际调整）

## Process Visualization

```infographic
infographic sequence-snake-steps-simple
data
  title Debug Failed Java Pod Process
  items
    - label 1. Prepare Images
      desc Target: GAR Java image
      desc Sidecar: praqma/network-multitool:latest
    - label 2. Run a.sh Script
      desc ./a.sh -t <target-image> [-s <sidecar-image>]
    - label 3. Deployment Applied
      desc kubectl apply -f debug-deploy.yaml
    - label 4. Pod Running
      desc Wait for Pod status: Running
    - label 5. kubectl debug
      desc kubectl debug -it <pod> --image=<sidecar> --target=app -- sh
    - label 6. Inspect JAR
      desc cd /proc/1/root/opt/apps/
      desc unzip -l *.jar | grep snakeyaml
```

## Detailed Steps

### Step 1: Run Automation Script

```bash
git clone ...  # 或直接使用生成的 a.sh
chmod +x a.sh
./a.sh -s praqma/network-multitool:latest -t asia-docker.pkg.dev/PROJECT/REPO/java-application:latest
```

脚本会：
- 生成 `debug-deploy.yaml`
- `kubectl apply`
- 输出 Pod 名称和 Debug 命令

### Step 2: Verify Resources

```bash
# 当前 Namespace
kubectl get deployment,pod -l app=debug-java-application

# Rollout status
kubectl rollout status deployment/debug-java-application --timeout=120s
```

### Step 3: Launch Debug Session

使用脚本输出的命令：

```bash
kubectl debug -it debug-java-application-xxxx -n default --image=praqma/network-multitool:latest --target=app -- sh
```

### Step 4: JAR Forensic Analysis (Inside Debug Container)

```bash
# 进入目标容器文件系统
cd /proc/1/root/opt/apps/

# 1. 列出 JAR
ls -lah *.jar

# 2. 校验完整性 (对比 CI 构建 log)
sha256sum *.jar
md5sum *.jar

# 3. 检查依赖版本 (不解压)
unzip -l *.jar | grep -i spring-boot
unzip -l *.jar | grep -i snakeyaml
jar tf *.jar | head -20 | grep BOOT-INF/lib

# 4. MANIFEST.MF
unzip -p *.jar META-INF/MANIFEST.MF | grep -E 'Spring-Boot|Built-By|Created-By'

# 5. 复制分析 (可选)
cp *.jar /tmp/my-app.jar
unzip /tmp/my-app.jar -d /tmp/extracted/
ls -lah /tmp/extracted/BOOT-INF/lib/ | grep yaml
```

## Deployment YAML Template

脚本生成的模板（可手动编辑）：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: debug-java-application
  namespace: default  # 当前 NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: debug-java-application
  template:
    metadata:
      labels:
        app: debug-java-application
    spec:
      containers:
      - name: app
        image: asia-docker.pkg.dev/PROJECT/REPO/java-application:latest
        command: ["/bin/sh", "-c"]
        args: ["sleep 36000"]
        # resources: {}  # 如需添加
        # securityContext:
        #   runAsUser: 0
```

**Distroless 镜像调整**：
- 无 sh：`command: ["sleep", "36000"]` 或 `["busybox", "sleep", "36000"]`

## Cleanup

```bash
kubectl delete deployment debug-java-application --now
rm -f debug-deploy.yaml a.sh  # 可选
```

## Script: debug-pod.sh (Full Content)

```bash
#!/bin/bash
# ... (见下方生成的文件)
```

## Troubleshooting

- **Pod Pending/ImagePullBackOff**：检查 imagePullSecrets / GAR auth (`gcloud auth configure-docker`)
- **Debug 失败**：确保 cluster 版本支持 ephemeral containers (GKE 1.23+)
- **No unzip**：network-multitool 有 busybox unzip；或用 `praqma/network-multitool:alpine` 等变体

---

**基于用户记忆**：适用于 GKE/GitOps 环境，结合 Squid/Kong 网络调试。