# 使用 JVM **Native Memory Tracking（NMT）** 精准拆分 App vs AppDynamics

修改启动参数，添加：

```bash
-XX:NativeMemoryTracking=detail
-XX:+UnlockDiagnosticVMOptions
-XX:+PrintNMTStatistics
```

然后通过命令抓 JVM 和 AppD 的内存结构：

```bash
jcmd <pid> VM.native_memory summary
```

输出示例会包括：

```
- Java Heap
- Class
- Thread
- Code
- GC
- Compiler
- Internal
- Symbol
- NMT
- Arena Chunk
- GC locker
- AppDynamicsAgent  ← 这部分可以明确看到！！！
```
## meet a error
```bash
这个错误 AttachNotSupportedException: Unable to open socket file 是因为 Debug Sidecar 和目标容器的文件系统是隔离的。

虽然你通过 shareProcessNamespace (Debug Sidecar 默认行为) 看到了 PID 9，但 JVM 在目标容器的 /tmp/.java_pid9 创建了通信 Socket，而你的 Sidecar 里的 /tmp 是空的，所以 jcmd 找不到它。
```
### 🚀 解决方案
请在 Sidecar 中尝试以下两种方法之一：

方法 1：使用 nsenter 进入目标容器环境（推荐）
如果你的 Sidecar 镜像里有 nsenter（Alpine/Busybox 都有），这是最直接的方法。它会“穿越”到目标容器的命名空间内执行命令。


# -t 9: 目标 PID
# -m -u -i -n -p: 进入所有命名空间 (Mount, UTS, IPC, Network, PID)
nsenter -t 9 -m -u -i -n -p -- jcmd 9 VM.native_memory summary

nsenter 报错了 nsenter: operation not permitted 

而 nsenter 需要 SYS_ADMIN 或 SYS_PTRACE 权限才能“穿越”到另一个容器的 Namespace

出现 nsenter: operation not permitted 是因为你的 Sidecar 容器权限不足。

Kubernetes 默认会丢弃容器的大部分 Linux Capabilities，而 nsenter 需要 SYS_ADMIN 或 SYS_PTRACE 权限才能“穿越”到另一个容器的 Namespace

How to fix this 
containers:
  - name: debug-sidecar
    securityContext:
      capabilities:
        add: ["SYS_PTRACE", "SYS_ADMIN"]  # 👈 必须加这个


方法 2：手动映射 Socket 文件（如果目标容器是 Distroless）
如果目标容器里没有 jcmd 或 sh，你必须在 Sidecar 里运行 jcmd。你需要把目标容器的 Socket "借" 过来。

建立软链接：通过 /proc 文件系统访问目标容器的 /tmp
建立软链接：通过 /proc 文件系统访问目标容器的 /tmp
bash
`ln -s /proc/9/root/tmp/.java_pid9 /tmp/.java_pid9`

ln -s /proc/9/root/tmp/.java_pid9 /tmp/.java_pid9 也同样会报错啊。 cannot access '/proc/9/root/tmp/.java_pid9 ' Permission denied
/tmp/.java_pid9 no such file or directory

这说明你的环境安全限制非常严格（可能是非 Root 用户运行，或者有 AppArmor/SELinux 策略阻挡）。

既然“偷渡”的方法（nsenter, /proc）都被权限墙挡住了，你需要修改 Deployment YAML 来显式授权。

这里有两个方案，选一个即可：

方案 1：最简单的暴力解法（赋予 Sidecar Root 权限）
让 Sidecar 以 Root 身份运行，通常就能通过 /proc 访问了

containers:
  - name: debug-sidecar
    image: ...
    securityContext:
      runAsUser: 0  # 👈 强制使用 Root
      privileged: true # 👈 如果还不行，加上这个（慎用，权限全开）

方案 2：K8s 原生解法（共享 /tmp 目录）
这是最标准、最安全的方法。既然 jcmd 靠 /tmp 下的文件通信，那就让两个容器共享这个目录。

定义一个 emptyDir 卷
挂载到两个容器的 /tmp

spec:
  volumes:
    - name: tmp-dir
      emptyDir: {}  # 👈 创建一个临时卷

  containers:
    - name: app
      volumeMounts:
        - name: tmp-dir
          mountPath: /tmp  # 👈 目标应用挂载它

    - name: debug-sidecar
      volumeMounts:
        - name: tmp-dir
          mountPath: /tmp  # 👈 Sidecar 也挂载它
注意：使用方案 2 时，Sidecar 里的用户 UID 最好和 App 容器一致（例如都是 1000），否则 jcmd 可能会因为“用户不匹配”拒绝连接。

总结： 现在的报错是因为你被关在“小黑屋”里，且没有钥匙。必须找管理员（修改 YAML）给你开门（共享目录）或者给你万能钥匙（Root/Privileged）。




切换用户执行：JVM 要求调用者必须是同一个用户。如果 Java 进程是 app (uid 1000) 跑的，而你是 root，必须切换身份：


🔍 路径解析：/proc/9/root/tmp/.java_pid9 这是一个非常好的问题。这个路径利用了 Linux 内核的一个“后门”特性，专门用来跨越容器（Namespace）的文件系统隔离。

这个路径由四部分组成，每一部分都有特殊的含义：

/proc: 这是 Linux 的虚拟文件系统。它不是硬盘上的真实文件，而是内核在内存中生成的，包含了系统运行时的所有状态信息。
/9 (PID): 这是目标 Java 进程在当前 Sidecar 容器视角下的进程 ID。
因为你开启了 shareProcessNamespace: true，Sidecar 才能看到目标容器的进程（PID 9）。
如果没有开启共享 PID Namespace，你是看不到这个目录的。
/root (关键魔法所在 ✨): 这是一个特殊的符号链接（Magic Symlink）。
它指向该进程（PID 9）所看到的文件系统根目录 (/)。
重点：即使目标进程在一个独立的容器（Mount Namespace）里，它的文件系统与 Sidecar 是隔离的，但通过 /proc/9/root，内核允许你直接“穿透”进它的文件系统。
/tmp/.java_pid9: 这是目标容器内部的实际路径。
JVM 启动时，会在 /tmp 下创建一个名为 .java_pid<pid> 的 Unix Domain Socket 文件，用于接收 jcmd、jstack 等工具的指令




bash
# 假设目标用户是 app (uid 1000)
su -s /bin/bash 1000 -c "jcmd 9 VM.native_memory summary"


```

既然你是用 kubectl debug 命令，那就更简单了！你不需要写 YAML，只需要在命令中加一个参数。

✅ 解决方案：使用 --profile=sysadmin
kubectl debug 有一个 --profile 参数，设置为 sysadmin 会自动帮你开启 Root 身份 和 Privileged (特权) 模式。

请使用这个命令：

bash
kubectl debug -it <你的Pod名字> \
  --image=<你的调试镜像> \
  --target=<目标容器名字> \
  --profile=sysadmin  # 👈 关键就是加这个！
💡 加上这个参数后会发生什么？
自动获得 Root 权限：你不再是普通用户，而是 uid 0。
自动获得完整 Capabilities：包括 SYS_PTRACE 和 SYS_ADMIN。
nsenter 复活了：因为有了特权，你之前失败的 方法 1 (nsenter) 现在可以直接用了！
bash
# 加上 --profile=sysadmin 进入后，直接运行这个，一定能成功：
nsenter -t 9 -m -u -i -n -p -- jcmd 9 VM.native_memory summary
/proc 访问也通了：如果你还是想用软链接法，现在 Root 身份也能直接访问 /proc/9/root/... 了。
一句话总结：下次调试直接加上 --profile=sysadmin，它就是你要的“万能钥匙”。

# when I using --profile=sysadmin 

我已经通过上面方式登录了 ，但是我的登录还是被拒绝的。因为我们配置了violates podsercurity "baseline:latest" privileged (container must not set securityCONtext .priviledged=true) 

明白了，你们集群启用了 Pod Security Admission (PSA)，并且强制执行 baseline 策略，这明确禁止了 privileged: true。

这意味着你绝对无法使用 --profile=sysadmin，因为那个 profile 必须要求特权模式。

🔐 最终解决方案：在“非特权”下完成调试
既然不能用特权，我们只能利用 baseline 策略允许的特性：shareProcessNamespace 是允许的。

我们不提升权限，而是利用“共享进程命名空间”来手动操作。

步骤 1：使用 general Profile（不申请特权）
使用 --profile=general（或者不加 profile，默认就是 general），这个模式不会申请 privileged: true，所以能通过安全检查。
```bash
kubectl debug -it <你的Pod名字> \
  --image=<你的调试镜像> \
  --target=<目标容器名字> \
  --profile=general  # 👈 改用这个，或者直接不写这行
```
步骤 2：手动解决“文件系统隔离”问题
进去之后，你又回到了最初的问题：能看到进程，但摸不到文件。 因为没有 Root/Privileged 权限，nsenter 和 /proc/9/root 的魔法可能会再次失效（取决于你的 User ID）。

关键破局点： 你必须让 Sidecar 的 User ID (UID) 与目标容器的 User ID 完全一致！

1 确认目标容器的 UID： 先用 kubectl exec 进目标容器看一眼：
```bash
kubectl exec -it <你的Pod名字> -- id
```
2 让 Debug 容器以相同 UID 启动： kubectl debug 允许你覆盖启动命令。我们可以在启动时“变身”。 但是 kubectl debug 命令行很难直接指定 runAsUser。 最稳妥的办法是生成一个 Ephemeral Container 的 JSON，修改后再应用：
```bash
# 1. 生成调试容器配置 (不执行)
kubectl debug -it <POD_NAME> \
  --image=<DEBUG_IMAGE> \
  --target=<APP_CONTAINER> \
  --profile=general \
  --copy-to=debug-pod-spec.json \
  --dry-run=client -o json
```
(这一步比较繁琐，通常我们推荐更直接的办法 👇) 更直接的办法：在 Debug 容器里 su 切换 如果你的调试镜像（如 ubuntu 或 busybox）是 Root 启动的，虽然没有 Privileged，但你通常还是 Root。 只要你是 Root (uid 0)，你就可以 su 切换成目标用户：
```bash
# 1. 启动调试容器 (默认 profile=general)
kubectl debug -it <pod> --image=ubuntu --target=<app>

# 2. 在调试容器里，安装 jcmd (如果镜像里没有)
apt-get update && apt-get install -y openjdk-17-jdk-headless

# 3. 建立软链接 (Root 通常有权读取 /proc/9/root，即使没有 privileged)
ln -s /proc/9/root/tmp/.java_pid9 /tmp/.java_pid9

# 4. 切换身份执行 (关键！必须用目标用户的身份去连 Socket)
# 假设目标是 uid 1000
su -s /bin/bash 1000 -c "jcmd 9 VM.native_memory summary"
```
核心逻辑： baseline 策略允许 Root 用户（非特权），也允许读取 /proc。只要你不用 nsenter（它需要 SYS_ADMIN），而是用 “软链接 + 切换 UID” 的组合拳，通常是可以通过安全检查的。