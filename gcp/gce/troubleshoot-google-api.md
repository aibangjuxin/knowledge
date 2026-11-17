https://cloud.google.com/run/docs/securing/private-networking?hl=zh-cn




在与来源服务关联的子网上启用专用 Google 访问通道，并配置 DNS 以将 run.app 网址解析为 private.googleapis.com (199.36.153.8/30) 或 restricted.googleapis.com (199.36.153.4/30) 范围。发送到这些范围的请求会通过 VPC 网络进行路由



199.36.153.4/30


Network:   199.36.153.4/30      11000111.00100100.10011001.000001 00
HostMin:   199.36.153.5         11000111.00100100.10011001.000001 01
HostMax:   199.36.153.6         11000111.00100100.10011001.000001 10
Broadcast: 199.36.153.7         11000111.00100100.10011001.000001 11
Hosts/Net: 2                     Class C


在我的GCP工程中有一条默认的路由是访问199.36.153.4/30.我现在GCP工程中的GKE访问这个接口的时候,出现不稳定或者超时的情况,比如我的GKE 需要访问另一个工程的Firestore,出现了超时,那么我如何来排查类似的问题,比如日志?网络的命中?另外我想了解GCP工程中路由跟踪如何解决?


在您的 GCP 工程中，GKE 访问 199.36.153.4/30 接口时出现不稳定或超时的情况，您可以通过以下方法进行排查：

* **检查日志：**首先，检查 GKE 容器的日志，查看是否有任何错误或异常信息。您可以使用 Google Cloud 控制台或 Cloud Logging API 来查看日志。
[Image of Google Cloud 控制台上的日志]

* **检查网络命中：**如果日志中没有任何错误或异常信息，您可以检查网络命中。您可以使用 Cloud Monitoring 来查看网络性能指标，例如丢包率、延迟和抖动。


* **检查路由：**如果网络命中正常，您可以检查路由。您可以使用 Cloud Shell 或 Cloud SDK 来检查路由。

```
gcloud compute routes list
```

这个命令将列出所有可用的路由。您可以使用 `-d` 标志来指定路由的目的地址。例如，要列出所有指向 199.36.153.4/30 的路由，请使用以下命令：

```
gcloud compute routes list -d 199.36.153.4/30
```

* **使用 Cloud Profiler 进行路由跟踪：**如果您仍然无法确定问题的原因，您可以使用 Cloud Profiler 进行路由跟踪。Cloud Profiler 可以帮助您分析应用程序的网络性能。

要使用 Cloud Profiler 进行路由跟踪，您需要先启用 Profiler。您可以通过 Google Cloud 控制台或 Cloud Profiler API 来启用 Profiler。

启用 Profiler 后，您可以使用 Cloud Profiler 仪表板来查看路由跟踪数据。
[Image of Cloud Profiler 仪表板]

路由跟踪数据将显示应用程序如何通过 Google Cloud 网络进行通信。您可以使用此数据来分析应用程序的网络性能并确定问题的原因。

以下是一些具体的示例：

* 如果日志中显示了网络错误，例如 `ECONNRESET` 或 `ETIMEDOUT`，则表明网络连接可能出现问题。您可以检查网络命中和路由，以确定问题的原因。
* 如果日志中没有显示任何错误或异常信息，但网络命中和路由都正常，则表明应用程序可能正在生成过多的流量。您可以使用 Cloud Monitoring 来监控应用程序的流量，以确定是否存在问题。
* 如果您使用 Cloud Profiler 进行路由跟踪，则可以查看应用程序如何通过 Google Cloud 网络进行通信。您可以使用此数据来分析应用程序的网络性能并确定问题的原因。

希望这些信息对您有所帮助。



在GCP工程中，如果你的GKE访问接口出现不稳定或超时的情况，你可以通过以下几种方式进行排查：

1. **查看日志**：你可以查看VPC流日志，这些日志记录了虚拟机实例（包括用作GKE节点的实例）发送和接收的网络流样本，这些日志可用于网络监控、取证、实时安全分析和费用优化[3]。你也可以使用负载均衡器日志进行问题排查[5]。

2. **检查网络配置**：检查你的网络配置，包括网络策略和防火墙规则，确保它们允许你的GKE集群访问Firestore。例如，你需要确保允许从你的GKE集群到Firestore的IP地址范围的出站流量[2]。

3. **检查应用配置**：如果你的应用或Google Cloud客户端库配置了较短的超时，可能会在Pod生命周期的前几秒内出现超时错误，因为GKE元数据服务器需要几秒钟的时间才能开始在Pod上接受新请求[2]。你可以尝试更新使用的Google Cloud客户端库，或者更改应用代码，让它在开始请求前等待几秒钟[2]。

4. **使用SSH进行排查**：如果你的应用运行在GKE的柔性环境中，你可以通过SSH连接到柔性环境实例，获取线程转储信息，对此类问题进行排查[1]。

关于GCP工程中的路由跟踪，你可以使用Google Cloud的网络智能中心进行网络性能监控和诊断。网络智能中心提供了一种可视化的方式来理解、优化和管理Google Cloud的网络性能和行为。例如，你可以使用网络拓扑功能来查看你的网络资源之间的通信，或者使用性能仪表板来查看网络性能的详细指标。你也可以使用连接测试功能来诊断网络连接问题，包括路由问题。

Citations:
[1] https://cloud.google.com/appengine/docs/flexible/python/flexible-for-standard-users?hl=zh-cn
[2] https://cloud.google.com/kubernetes-engine/docs/troubleshooting/troubleshooting-security?hl=zh-cn
[3] https://cloud.google.com/architecture/network-architecture?hl=zh-cn
[4] https://cloud.google.com/architecture/security-log-analytics?hl=zh-cn
[5] https://cloud.google.com/kubernetes-engine/docs/troubleshooting/troubleshoot-load-balancing?hl=zh-cn
[6] https://cloud.google.com/architecture/twelve-factor-app-development-on-gcp?hl=zh-cn
[7] https://www.cisco.com/c/zh_cn/support/docs/cloud-systems-management/hybrid-cloud-platform-google-cloud/217774-configure-google-cloud-interconnect-as-a.html
[8] https://firebase.google.com/docs/firestore/real-time_queries_at_scale?hl=zh-cn
[9] https://devpress.csdn.net/cicd/62ed4b01c6770329307f226b.html
[10] https://www.infoq.cn/article/07fytcixirqz1prlfbe6
[11] https://www.googlecloudcommunity.com/gc/Serverless/How-to-troubleshoot-Firestore-quot-Total-timeout-quot-from/m-p/598447
[12] https://cloud.tencent.com/developer/ask/sof/116382047
[13] https://access.redhat.com/documentation/zh-cn/openshift_dedicated/4/html-single/introduction_to_openshift_dedicated/index
[14] https://firebase.google.com/docs/firestore/query-data/listen?hl=zh-cn
[15] https://www.cnblogs.com/apachecn/p/17325449.html
[16] https://stevenjokess.github.io/2bPM/chapter_idea/understand_tech.html
[17] https://dbaplus.cn/news-134-3935-1.html
[18] https://repost.aws/zh-Hans/knowledge-center/network-issue-vpc-onprem-ig
[19] https://zhuanlan.zhihu.com/p/186046733?utm_id=0
[20] http://gitbook.liupdhc.com/istio-handbook/GLOSSARY.html
[21] http://www.vandorcloud.com/product/222.html/
