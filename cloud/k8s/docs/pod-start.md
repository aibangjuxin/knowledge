好的，要获取一个命名空间下所有正在运行的 Pod 的详细时间信息，可以使用以下命令组合，以满足不同程度的详细需求：

**核心命令**

首先，我们需要基本的 `kubectl get pods` 命令，并结合状态过滤和输出格式控制。

**1. 最简洁的版本：只显示名称和启动时间**

```bash
kubectl get pods -n <namespace> --field-selector status.phase=Running -o custom-columns=NAME:.metadata.name,START_TIME:.status.startTime
```

*   `<namespace>`: 替换成你的目标命名空间。
*   `--field-selector status.phase=Running`:  只选择 `status.phase` 为 `Running` 的 Pod。
*   `-o custom-columns=NAME:.metadata.name,START_TIME:.status.startTime`:  自定义输出格式，显示 Pod 的名称 (`.metadata.name`) 和启动时间 (`.status.startTime`)。

**2. 显示创建时间 (creationTimestamp) 而非启动时间 (startTime):**

```bash
kubectl get pods -n <namespace> --field-selector status.phase=Running -o custom-columns=NAME:.metadata.name,CREATION_TIME:.metadata.creationTimestamp
```

和上面一样，只是把 `START_TIME` 换成了 `CREATION_TIME`，`.status.startTime` 换成了 `.metadata.creationTimestamp`。

**3.  更详细的版本：显示更多信息**

如果需要更多的信息，例如 Pod IP、节点名称等，可以添加到 `custom-columns` 中：

```bash
kubectl get pods -n <namespace> --field-selector status.phase=Running -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[*].ready,STATUS:.status.phase,IP:.status.podIP,NODE:.spec.nodeName,START_TIME:.status.startTime,CREATION_TIME:.metadata.creationTimestamp
```

*   `READY:.status.containerStatuses[*].ready`: 显示容器是否准备就绪 (True/False)。 注意这里使用了 `[*]` 来访问容器状态列表，如果一个Pod有多个容器，那么会显示多个Ready状态。
*   `STATUS:.status.phase`:  Pod 的当前状态。
*   `IP:.status.podIP`:  Pod 的 IP 地址。
*   `NODE:.spec.nodeName`:  Pod 运行的节点名称。
*   `START_TIME:.status.startTime`: Pod 的启动时间
*   `CREATION_TIME:.metadata.creationTimestamp`: Pod 的创建时间。

**4. 使用 Go 模板获得更精细的控制：**

Go 模板提供了最大的灵活性，可以自定义输出格式。 例如：

```bash
kubectl get pods -n <namespace> --field-selector status.phase=Running -o go-template='{{range .items}}{{"Name: "}}{{.metadata.name}}{{"\n  Creation Time: "}}{{.metadata.creationTimestamp}}{{"\n  Start Time: "}}{{.status.startTime}}{{"\n"}}{{end}}'
```

这个命令会输出每个 Running Pod 的名称、创建时间和启动时间，并使用更易读的格式。

**5. 格式化时间输出 (使用 `date` 命令)**

上面输出的时间戳都是 ISO 8601 格式。 如果需要格式化成更易读的格式，需要结合 `xargs` 和 `date` 命令。  **注意：这种方式会使命令变得非常复杂，不推荐在需要大量输出的情况下使用。**  更推荐在查看单个Pod的时间信息时使用。

```bash
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.metadata.creationTimestamp}' | xargs -I {} date -d {}
```

因为要获取 *所有* 正在运行的 Pod 的信息，需要对每个 Pod 执行此操作，会导致命令非常复杂且效率低下。

**6. 使用 `jq` 进行更复杂的 JSON 处理**

如果需要对JSON数据进行更复杂的处理，例如格式化时间，可以使用 `jq` 工具。

首先，你需要安装 `jq`:  `sudo apt-get install jq` (Debian/Ubuntu) 或 `brew install jq` (macOS)。

然后，可以使用以下命令：

```bash
kubectl get pods -n <namespace> --field-selector status.phase=Running -o json | jq '.items[] | {name: .metadata.name, creationTimestamp: .metadata.creationTimestamp, startTime: .status.startTime}'
```

这个命令会输出一个 JSON 数组，包含每个 Pod 的名称、创建时间和启动时间。  你可以使用 `jq` 的更多功能来进一步格式化输出。

**选择哪个命令？**

*   对于快速查看名称和启动时间，使用 **1**。
*   如果需要创建时间，使用 **2**。
*   如果需要更多详细信息，使用 **3**。
*   如果需要完全自定义输出格式，并且熟悉 Go 模板，使用 **4**。
*   避免在需要大量输出的情况下使用 **5**，因为效率低下。
*   对于复杂 JSON 处理，使用 **6** 并结合 `jq`。

**示例：**

假设你要查看 `my-namespace` 命名空间下所有正在运行的 Pod 的名称和启动时间，可以使用以下命令：

```bash
kubectl get pods -n my-namespace --field-selector status.phase=Running -o custom-columns=NAME:.metadata.name,START_TIME:.status.startTime
```

输出可能类似于：

```
NAME          START_TIME
my-pod-1      2023-10-27T13:00:00Z
my-pod-2      2023-10-27T13:05:00Z
```

选择最适合你需求的命令，根据实际情况进行调整。 推荐优先使用 `custom-columns`，因为它简单易用且性能良好。 如果需要更复杂的格式化，则使用 `go-template` 或 `jq`。
