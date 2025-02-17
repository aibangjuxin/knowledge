
- https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/pod-lifecycle/
# Pod 的终止
- [pod-lifecycle.md](./pod-lifecycle.md)
```
Pod 的终止

由于 Pod 所代表的是在集群中节点上运行的进程，当不再需要这些进程时允许其体面地终止是很重要的。 一般不应武断地使用 KILL 信号终止它们，导致这些进程没有机会完成清理操作。

设计的目标是令你能够请求删除进程，并且知道进程何时被终止，同时也能够确保删除操作终将完成。 当你请求删除某个 Pod 时，集群会记录并跟踪 Pod 的体面终止周期， 而不是直接强制地杀死 Pod。在存在强制关闭设施的前提下， kubelet 会尝试体面地终止 Pod。

通常 Pod 体面终止的过程为：kubelet 先发送一个带有体面超时限期的 TERM（又名 SIGTERM） 信号到每个容器中的主进程，将请求发送到容器运行时来尝试停止 Pod 中的容器。 停止容器的这些请求由容器运行时以异步方式处理。 这些请求的处理顺序无法被保证。许多容器运行时遵循容器镜像内定义的 STOPSIGNAL 值， 如果不同，则发送容器镜像中配置的 STOPSIGNAL，而不是 TERM 信号。 一旦超出了体面终止限期，容器运行时会向所有剩余进程发送 KILL 信号，之后 Pod 就会被从 API 服务器上移除。 如果 kubelet 或者容器运行时的管理服务在等待进程终止期间被重启， 集群会从头开始重试，赋予 Pod 完整的体面终止限期。

Pod 终止流程，如下例所示：

你使用 kubectl 工具手动删除某个特定的 Pod，而该 Pod 的体面终止限期是默认值（30 秒）。

API 服务器中的 Pod 对象被更新，记录涵盖体面终止限期在内 Pod 的最终死期，超出所计算时间点则认为 Pod 已死（dead）。 如果你使用 kubectl describe 来查验你正在删除的 Pod，该 Pod 会显示为 "Terminating" （正在终止）。 在 Pod 运行所在的节点上：kubelet 一旦看到 Pod 被标记为正在终止（已经设置了体面终止限期），kubelet 即开始本地的 Pod 关闭过程。

如果 Pod 中的容器之一定义了 preStop 回调 且 Pod 规约中的 terminationGracePeriodSeconds 未设为 0， kubelet 开始在容器内运行该回调逻辑。默认的 terminationGracePeriodSeconds 设置为 30 秒.

如果 preStop 回调在体面期结束后仍在运行，kubelet 将请求短暂的、一次性的体面期延长 2 秒。
```
在 Kubernetes 中，Pod 的终止信号 (SIGTERM) 发送的时机，以及其他与 Pod 终止相关的操作，可以通过以下几个方式进行查看和监控。特别是对于 GKE 和 Kubernetes 平台，您可以使用不同的命令和工具来获取相关信息。

1. 查看 Pod 的终止时间和状态

当您删除一个 Pod 时，它会进入 “Terminating” 状态，您可以使用 kubectl describe pod 命令来查看 Pod 的详细信息，包括容器接收到 SIGTERM 的时间和相关的事件。

kubectl describe pod <pod-name>

输出中会包括以下信息：
	•	状态：Pod 是否处于 “Terminating” 状态。
	•	事件：每个容器收到 SIGTERM 的时间，以及是否执行了 preStop 钩子（如果有的话）。
	•	TerminationGracePeriodSeconds：Pod 的终止宽限期（默认为 30 秒）。

例如，您可以在事件部分看到类似以下的内容：
```bash
Events:
  Type    Reason             Age   From               Message
  ----    ------             ----  ----               -------
  Normal  Killing            4s    kubelet, gke-cluster-xyz-1234  Killing container with id docker://<container-id>: Container failed liveness probe
  Normal  PreStopHook        3s    kubelet, gke-cluster-xyz-1234  Running preStop hook for container <container-name>
  Normal  TerminationGracePeriodExceeded  2s    kubelet, gke-cluster-xyz-1234  Termination grace period exceeded, sending SIGKILL
```
在这里，您会看到 Killing 事件，以及是否有 PreStopHook 被触发的记录。

2. 查看容器接收到 SIGTERM 的时间

Kubernetes 并没有直接提供一个命令来显示 SIGTERM 信号发送的具体时间，但您可以通过查看容器日志来间接了解这一过程。如果容器中有日志输出在收到 SIGTERM 时（例如，通过自定义的应用逻辑记录），则可以通过以下命令查看日志：

`kubectl logs <pod-name> -c <container-name> --timestamps`

在容器日志中，您可以查找 SIGTERM 信号触发的相关输出，通常在收到 SIGTERM 后会有相应的日志（例如，SIGTERM received, shutting down...）。

3. 查看 GKE 上的 Pod 终止日志

在 GKE 中，您还可以通过 Stackdriver（现在是 Google Cloud Operations Suite）查看与 Pod 终止相关的日志。您可以通过 GCP 控制台访问日志：
	1.	打开 Google Cloud Console.
	2.	导航到 Logging -> Log Explorer。
	3.	在查询框中输入类似以下的查询：
```bash
resource.type="k8s_container"
resource.labels.cluster_name="<your-cluster-name>"
resource.labels.namespace_name="<your-namespace>"
"pod" AND "Killing"
```
这将显示与 Pod 终止相关的日志，您可以看到 Pod 是否正常收到 SIGTERM 信号，以及是否有任何与容器关闭或钩子相关的日志。

4. 其他检查项
	•	Pod 的生命周期事件：可以使用 kubectl get events 来查看与 Pod 终止相关的所有事件，特别是与 Pod 终止和重新启动相关的事件。

`kubectl get events --sort-by='.lastTimestamp'`



总结：
	•	使用 kubectl describe pod 查看 Pod 状态和事件，包括收到 SIGTERM 信号的时间。
	•	查看容器日志 可以了解容器在收到 SIGTERM 后的行为。
	•	在 GKE 上使用 Google Cloud Logging 来检查与 Pod 终止相关的日志，特别是容器终止过程中的事件和错误。

# Rolling pod Logs  

对于 GKE 上已经经过 Rolling 更新的 Pod，历史的 Pod 会被替换，通常无法直接通过 kubectl logs 查看已终止的 Pod 的日志。除了 Stackdriver（Google Cloud Logging）之外，您可以通过以下几种方式来查看历史 Pod 终止的日志：

1. 使用 kubectl logs 查看已终止的 Pod

即使 Pod 已经被删除，Kubernetes 仍然会保留一段时间的容器日志，特别是对于已经终止的容器。如果您知道旧 Pod 的名字并且 Pod 并没有被完全清理，您可以尝试使用 kubectl logs 命令并指定已终止 Pod 的名字和容器名称。即使 Pod 被滚动更新替换，Kubernetes 会在一定时间内保留其容器日志。

kubectl logs <pod-name> -c <container-name> --previous

	•	--previous 参数允许查看已终止容器的日志，特别是当容器由于失败或停止而被重启时。此命令将显示容器的历史日志（即使 Pod 已经被替换）。

	注意：该方法适用于 Pod 在容器运行时没有被完全删除的情况。如果容器被删除或经过很长时间，日志可能会被清除。

2. GKE 自动创建的 Kubernetes 日志聚合

如果您有设置日志聚合系统（如 Fluentd、Elasticsearch 等），这些工具会将日志集中存储在一个外部位置，您可以通过查询来访问历史日志。GKE 默认集成了 Stackdriver 日志（Google Cloud Logging），但如果您已集成其他日志聚合系统（例如，通过 Fluentd 将日志发送到其他存储），您可以在集群中配置日志保存策略。

如果您的集群已经集成了其他日志聚合工具，可以通过相应的查询系统访问这些历史日志。

3. 查看 Pod 终止的事件

如果您只是想了解 Pod 是否体面终止并获取终止的事件信息，可以通过 kubectl get events 命令查看与 Pod 终止相关的历史事件。

kubectl get events --sort-by='.lastTimestamp' -n <namespace>

查看相关的事件，尤其是与 Pod 的终止相关的 Killing、PreStopHook 等事件。

4. 启用持久化日志存储

如果您的集群未启用持久化日志存储，可以考虑配置如下的日志存储方式，以便将日志保存到外部系统（例如 Google Cloud Storage、Elasticsearch、或其他日志管理平台）。

例如，您可以使用 Fluentd 或 Logstash 等工具将 GKE 集群的容器日志发送到外部存储系统，并通过这些系统查看历史日志。这样即使 Pod 被删除或替换，日志仍然可以保留。

5. 使用 Prometheus 和 Grafana

如果您有 Prometheus 集群监控系统和 Grafana 可视化工具，并且已配置它们来监控 Pod 和容器的健康状况，您可以查看历史监控数据。虽然这主要用于监控指标，但它也能帮助您理解 Pod 的生命周期、重启原因等。这样，您也能更好地追踪 Pod 终止的原因。

总结

对于 GKE 上已经滚动更新的 Pod，除了 Stackdriver（Google Cloud Logging）外，您还可以尝试以下方式来查看 Pod 的终止日志：
	1.	使用 kubectl logs <pod-name> -c <container-name> --previous 查看已终止容器的日志。
	2.	查看 GKE 集群的历史事件（kubectl get events）。
	3.	配置并使用外部日志存储系统，如 Elasticsearch 或 Fluentd 以持久化日志。
	4.	如果您有 Prometheus 和 Grafana 配置，查看与 Pod 生命周期和健康状态相关的监控数据。

    # 获取当前状态
    `READY_STATUS=$(kubectl get pod ${POD} -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")]}')`
	