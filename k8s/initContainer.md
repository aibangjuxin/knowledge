# How to quick refresh node images

- 其实我核心的目的是想要强制刷新我 GKE Node 上可能的 APPD 缓存

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: abc
  namespace: ns
spec:
  initContainers:
    - name: appd-init-service
      image: appd-java-agent:latest
      imagePullPolicy: Always
      command: ["sh", "-c", "cp -r /tmp/appdynamics/. /tmp/appdynamics-java"]
  containers:
    - name: nginx
      image: nginx
      imagePullPolicy: Always
  nodeSelector:
    kubernetes.io/hostname: gke-node-abcd
```

这个配置文件是一个 Kubernetes 的 Pod 定义文件，下面我将对内容进行解释，并结合你提到的核心目的——强制刷新 GKE 节点上的 APPD 缓存——进行说明。

### 配置文件内容解释

1. **基本信息**：

    - `apiVersion: v1`：指定了 Kubernetes API 的版本，这里是 v1。
    - `kind: Pod`：定义了资源类型为 Pod，即一个最小的调度单位。
    - `metadata`：包含 Pod 的元数据。
        - `name: abc`：Pod 的名称为“abc”。
        - `namespace: ns`：Pod 所在的命名空间为“ns”。

2. **Spec 部分（Pod 的规格定义）**：
    - `initContainers`：定义了一个初始化容器，通常用于在主容器启动前完成一些初始化任务。
        - `name: appd-init-service`：初始化容器的名称。
        - `image: appd-java-agent:latest`：使用的镜像为最新的 AppDynamics Java 代理镜像。
        - `imagePullPolicy: Always`：镜像拉取策略为“始终拉取”，确保每次都从镜像仓库拉取最新镜像。
        - `command: ["sh", "-c", "cp -r /tmp/appdynamics/. /tmp/appdynamics-java"]`：容器启动时执行的命令，将`/tmp/appdynamics/`目录下的内容复制到`/tmp/appdynamics-java`目录。
    - `containers`：定义了主容器。
        - `name: nginx`：主容器的名称。
        - `image: nginx`：使用的镜像为 Nginx。
        - `imagePullPolicy: IfNotPresent`：镜像拉取策略为“如果不存在则拉取”，即本地有镜像则不重新拉取。
    - `nodeSelector`：指定 Pod 调度到特定的节点上。
        - `kubernetes.io/hostname: gke-node-abcd`：强制将 Pod 调度到主机名为`gke-node-abcd`的节点上。

### 与核心目的的关联

你提到核心目的是“强制刷新 GKE 节点上可能的 APPD 缓存”。从配置文件来看，以下几点可能与你的目标相关：

1. **初始化容器（initContainers）的作用**：

    - 初始化容器使用了 AppDynamics 的 Java 代理镜像（`appd-java-agent:latest`），并且通过`command`复制了某些文件（可能是代理相关的配置或缓存文件）。这可能是在尝试更新或重新加载 AppDynamics 的相关文件，以达到清除或刷新缓存的目的。
    - 镜像拉取策略`Always`确保了每次部署 Pod 时都会拉取最新的 AppDynamics 代理镜像，避免使用本地缓存的老版本镜像。

2. **节点选择（nodeSelector）**：

    - 通过`nodeSelector`将 Pod 强制调度到特定的 GKE 节点（`gke-node-abcd`）上，这可能是因为你希望在该节点上执行缓存刷新操作，确保 AppDynamics 的相关缓存或配置在该节点上被更新。

3. **主容器（nginx）**：
    - 主容器只是运行一个 Nginx 服务，可能是为了测试或占位，与刷新 APPD 缓存的直接关系不大。

### 总结与建议

从配置来看，你的意图可能是通过初始化容器更新 AppDynamics 代理的相关文件或配置，以达到刷新 GKE 节点上 APPD 缓存的目的。以下是几点分析和建议：

- 如果初始化容器的命令（`cp -r /tmp/appdynamics/. /tmp/appdynamics-java`）确实是为了覆盖或更新缓存文件，请确保这些目录和文件与 AppDynamics 的缓存机制相关。
- 使用`imagePullPolicy: Always`是正确的做法，可以避免使用本地镜像缓存，确保获取最新的代理版本。
- 如果刷新缓存的效果不明显，可以考虑在初始化容器中添加额外的命令，比如清理特定的缓存目录，或者重启与 AppDynamics 相关的进程（如果可能）。
- 确认`nodeSelector`指定的节点是否确实是需要刷新缓存的目标节点。如果缓存问题涉及多个节点，可能需要调整策略，比如使用 DaemonSet 而不是 Pod，以便在每个节点上都运行刷新操作。

如果你有更详细的背景信息（例如 AppDynamics 缓存的具体位置或刷新机制），我可以进一步帮助优化配置。

# initContainers

## About dir

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: lex-ext-kdp
  name: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      initContainers:
      - name: init-appd-dir
        image: python:latest
        command: ["sh", "-c", "mkdir -p /opt/appdynamics && touch /opt/appdynamics/a.txt && echo abc > /opt/appdynamics/a.txt"]
        volumeMounts:
        - name: appd-volume
          mountPath: /opt # 定义了 initContainer，它挂载了名为 appd-volume 的 Volume 到 /opt 目录
      containers:
      - name: app
        image: nginx
        volumeMounts:
        - name: appd-volume
          mountPath: /opt # 定义了主应用容器，它挂载了名为 appd-volume 的 Volume 到 /opt 目录
      volumes:
      - name: appd-volume
        emptyDir: {}

```

- eg:

```bash
initContainers:
       command: ["sh", "-c", "mkdir -p /opt/appdynamics && touch /opt/appdynamics/a.txt && echo abc > /opt/appdynamics/a.txt"]

Containers
        - name: appd-volume
          mountPath: /opt
```

- Result

```bash
在initContainers中，我们使用mkdir -p /opt/appdynamics && touch /opt/appdynamics/a.txt && echo abc > /opt/appdynamics/a.txt创建了一个名为a.txt的文件，
并将其写入了abc内容到a.txt

需要注意的是后面 Containers的mountPath这里

我mountPath is /opt

root@app-74d7fb884-7p9rv:/opt/appdynamics# pwd
/opt/appdynamics
root@app-74d7fb884-7p9rv:/opt/appdynamics# cat a.txt
abc
```

- ask

```
假如我有这样一个需求
我想构建一个deployment其包含2个部分一个是
initContainers一个是containers
我想要在initContainers中创建一个目录,然后这个目录里面在构建的时候将我的代码逻辑放在里面比如里面是一个start.sh 和一个 delete.sh
我在deploy的时候首先执行这个start.sh
然后在containers中将这个目录挂载到容器中. 普通的这个Containers是一个用户的API,等待用户的API启动之后
我要在容器中执行delete.sh
如果这样的逻辑是否可行? 如果可以行 请给我一个具体的deployment.yaml
```

是的，你的逻辑是可行的。你可以使用 Kubernetes 的 `initContainers` 来执行一些初始化操作，然后将生成的文件或目录挂载到主容器中。以下是一个简单的 `Deployment` YAML 文件，展示了如何实现这一逻辑：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      initContainers:
      - name: init-scripts
        image: busybox
        command:
        - sh
        - -c
        - |
          mkdir -p /app-scripts
          echo "echo Start Script Executed!" > /app-scripts/start.sh
          echo "echo Delete Script Executed!" > /app-scripts/delete.sh
        volumeMounts:
        - name: scripts-volume
          mountPath: /app-scripts
      containers:
      - name: user-api
        image: your-user-api-image:latest
        volumeMounts:
        - name: scripts-volume
          mountPath: /app-scripts
      volumes:
      - name: scripts-volume
        emptyDir: {}
```

这个 YAML 文件创建了一个 `Deployment`，其中包含了一个 `initContainers`，它使用 `busybox` 镜像执行一些初始化命令，生成了 `/app-scripts` 目录，并在其中创建了 `start.sh` 和 `delete.sh`。接着，这个目录被挂载到主容器中。

主容器使用了你的用户 API 镜像，并挂载了 `/app-scripts` 目录。你可以在用户 API 中通过 `/app-scripts/start.sh` 来执行启动逻辑，在用户 API 启动之后再执行 `/app-scripts/delete.sh`。

注意：这里使用了 `emptyDir` 类型的 Volume，这意味着它是临时的，Pod 重启后会丢失。如果需要更持久的存储，你可能需要使用 Persistent Volume 和 Persistent Volume Claim。此外，请确保你的用户 API 镜像中具备执行这两个脚本的执行权限。

你可以根据实际需求调整镜像和脚本的内容。

如果你想在 `Deployment` 中调用执行脚本 `/app-scripts/delete.sh`，你可以通过在 `Deployment` 的 `spec` 中的 `containers` 下的 `command` 字段来指定需要在容器启动时执行的命令。下面是一个示例：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      initContainers:
      - name: init-scripts
        image: busybox
        command:
        - sh
        - -c
        - |
          mkdir -p /app-scripts
          echo "echo Start Script Executed!" > /app-scripts/start.sh
          echo "echo Delete Script Executed!" > /app-scripts/delete.sh
        volumeMounts:
        - name: scripts-volume
          mountPath: /app-scripts
      containers:
      - name: user-api
        image: your-user-api-image:latest
        command:
        - sh
        - -c
        - |
          /app-scripts/start.sh
        volumeMounts:
        - name: scripts-volume
          mountPath: /app-scripts
      volumes:
      - name: scripts-volume
        emptyDir: {}
```

在上述示例中，`command` 字段被添加到了 `containers` 下的 `user-api` 容器中。这里将 `/app-scripts/start.sh` 添加到了容器的启动命令中。你可以按照类似的方式将 `/app-scripts/delete.sh` 加入到需要执行的命令中。

请注意，你的用户 API 镜像需要包含能够执行这两个脚本的执行权限。如果你遇到权限问题，可能需要在 Dockerfile 中为这两个脚本添加执行权限。

这只是一个简单的示例，你可以根据实际需求调整脚本和命令
