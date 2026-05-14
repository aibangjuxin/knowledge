

在 GCP 工程中统计资源消耗情况,有多种方式和工具可供选择:

1. **Cloud Monitoring**

Cloud Monitoring 可以监控 GKE 集群、Pod、容器等资源的 CPU、内存、网络等指标。您可以创建仪表板查看整体资源使用情况,或根据标签(如namespace、deployment等)分组查看指标。

那么我是否可以将我需要的比如不同的过滤条件,比如按照标签来过滤出属于aibang团队的namespace和deployment,然后将这个过滤条件作为参数传递给Cloud Monitoring,从而实现对资源消耗情况的统计和分析呢?
再比如我想要获取这个组的所有的Pod的对应的一些内存和CPU信息,我不仅仅是想通过Cloud Monitoring来查看,还想将对应的数据或者数值存储到我们的Bigquery中,是否可行?

1. **Billing 导出到 BigQuery** 

将 Billing 数据导出到 BigQuery 中,利用 SQL 查询分析资源使用情况。您可以结合标签等元数据进行分组统计。

3. **Cloud Asset Inventory**

Cloud Asset Inventory 可以导出您在 GCP 工程中的所有资源清单,包括 GKE 集群、Pod 等。结合其他监控数据,可以全面分析资源使用情况。

3.1  introduction

    Cloud Asset Inventory is a service offered by Google Cloud that allows you to view, monitor, and analyze all your Google Cloud and Anthos assets across projects and services. It essentially provides an inventory of your resources in Google Cloud.

Here's a breakdown of its key functionalities:

* **Visibility into Assets:** Cloud Asset Inventory offers a centralized view of all your Google Cloud assets, including compute engines, storage buckets, Kubernetes resources, and IAM policies. This allows you to understand what resources you have, where they are located, and how they are configured.

* **Historical Analysis:** The service maintains a 35-day history of your asset metadata. This enables you to track changes made to your resources over time and identify potential security risks or configuration drifts.

* **Search Functionality:** You can leverage a custom query language to search for specific assets based on various attributes like project, location, or resource type. This simplifies the process of finding the resources you need.

* **Monitoring and Notifications:** Cloud Asset Inventory allows you to monitor changes to your resources and receive real-time notifications when these changes occur. This can be helpful for identifying security incidents or configuration errors promptly.


Here are some advantages of using Cloud Asset Inventory:

* **Improved Resource Management:** By having a comprehensive view of your resources, you can optimize their usage and avoid unnecessary costs.
* **Enhanced Security:** Cloud Asset Inventory helps you identify potential security risks associated with your resources and enforce IAM policies more effectively.
* **Simplified Compliance:** It can streamline compliance audits by providing a central location for documenting and tracking your resources.

云资产清单
概述

云资产清单是 Google Cloud 提供的一项服务，可让您跨项目和服务查看、监控和分析所有 Google Cloud 和 Anthos 资产。它本质上提供了一个 Google Cloud 中资源的清单。

主要功能:

资产可见性: 云资产清单提供所有 Google Cloud 资产的集中视图，包括计算引擎、存储桶、Kubernetes 资源和 IAM 策略。这使您可以了解您拥有的资源、它们的位置以及它们的配置方式。
历史分析: 该服务维护 35 天的资产元数据历史记录。这使您可以跟踪一段时间内对资源所做的更改并识别潜在的安全风险或配置漂移。
搜索功能: 您可以利用自定义查询语言根据项目、位置或资源类型等各种属性搜索特定资产。这简化了查找所需资源的过程。
监控和通知: 云资产清单允许您监控资源更改并接收有关这些更改的实时通知。这对于及时识别安全事件或配置错误很有帮助。
优势:

改进资源管理: 通过全面了解您的资源，您可以优化它们的利用率并避免不必要的成本。
增强安全性: 云资产清单可帮助您识别与您的资源相关的潜在安全风险并更有效地实施 IAM 策略。
简化合规性: 它可以通过提供一个集中位置来记录和跟踪您的资源来简化合规性审计。
总体而言，云资产清单是管理和保护您的 Google Cloud 和 Anthos 部署的宝贵工具。它使您能够深入了解资源使用情况，识别潜在问题并就您的云基础架构做出明智的决策。

一些其他细节:

Cloud Asset Inventory 使用 Cloud Logging 和 Cloud Monitoring 收集数据。
您可以使用 Cloud Console、gcloud 命令行工具或 API 访问 Cloud Asset Inventory。
Cloud Asset Inventory 是免费提供的，但您需要为 Cloud Logging 和 Cloud Monitoring 支付费用。
有关 Cloud Asset Inventory 的更多信息，请参阅以下资源:

Cloud Asset Inventory 文档: https://cloud.google.com/asset-inventory/docs/
Cloud Asset Inventory 简介: https://cloud.google.com/asset-inventory/docs/overview


Overall, Cloud Asset Inventory is a valuable tool for managing and securing your Google Cloud and Anthos deployments. It empowers you to gain insights into your resource usage, identify potential issues, and make informed decisions about your cloud infrastructure.

4. **Kubecost**

Kubecost 是一款开源工具,专注于 Kubernetes 集群的资源分析和成本可视化。它整合了多种云服务商的计费数据,提供丰富的仪表板和报告。

5. **GKE Cluster AutoScaler** 

GKE 自带的 Cluster Autoscaler 不仅可以自动扩缩节点池,还可以在 Kubernetes 事件中心页面查看资源使用情况、缩放记录等。

6. **自定义可视化工具**

您也可以考虑结合上述数据源,利用类似 Grafana、Data Studio 等可视化工具自行构建符合团队需求的统计报表。

总的来说,GCP 提供了诸多原生和第三方工具来监控和分析资源使用情况。您可以根据团队需求和技术栈进行选型和集成,以获得更好的可视性和成本控制能力。

我们的环境运行在Google GKE 上
每一个用户的API都部署在不同的namespace上

我们Deployment的模版定义中有如下部分定义
```yaml
  template:
    metadata:
      annotations:
        clusters-autoscaler.kubernetes.io/safe-to-evict: "true"
      creationTimestamp: null
      labels:
        app: woup-wcl-bblsmp-pa-woup-servicenow-1-1-16
        category: springboot
        kdp: aib-internal-kdp
        nexthop: ksp-srs-abj-abcde
        sambs: enabled
        team: abj-abcde
        timestamp: "1700451805942"
        type: pa
```
- 这个命令会显示所有具有标签 team:aibang 的 Pod 的 CPU 和内存占用情况
- `kubectl top pods --all-namespaces -l team=aibang`
那么对于GCP工程来说,我想更好的去统计我的资源消耗情况，我需要做哪些工作？或者有什么好的办法,或者成熟的工具?


比如我可以按照标签来过滤出属于aibang团队的namespace和deployment
team: aibang
kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.team=="aibang")]}{@.metadata.namespace} {@.metadata.name}{"\n"}{end}'


如果是按照计划任务来收集属于aibang团队的所有namespace下的deployment下的Pod的CPU和内存使用情况，可以用下面的命令：
- 这个命令会列出所有属于 "aibang" 团队的命名空间下的部署，并显示每个 Pod 的 CPU 和内存请求
```bash
kubectl get deployments --all-namespaces -o jsonpath='{range .items[?(@.spec.template.metadata.labels.team=="aibang")]}{@.metadata.namespace} {@.metadata.name} {.status.availableReplicas} {.spec.template.spec.containers[0].resources.requests.cpu} {.spec.template.spec.containers[0].resources.requests.memory}{"\n"}{end}'

kubectl get pods --all-namespaces -o jsonpath='{range .items[?(@.metadata.labels.team=="aibang")]}{@.metadata.namespace} {@.metadata.name} {.spec.containers[0].resources.requests.cpu} {.spec.containers[0].resources.requests.memory}{"\n"}{end}'
kubectl get pods --all-namespaces -o jsonpath='{range .items[?(@.metadata.labels.sambs=="enabled")]}{@.metadata.namespace} {@.metadata.name} {.spec.containers[0].resources.requests.cpu} {.spec.containers[0].resources.requests.memory}{"\n"}{end}'
```
- 这个命令会显示所有具有标签 team:aibang 的 Pod 的 CPU 和内存占用情况
- `kubectl top pods --all-namespaces -l team=aibang`

-
kubectl top pods --all-namespaces -l sambs=enabled
NAMESPACE      NAME                                                              CPU(cores)   MEMORY(bytes)
bass-internal-kdp   abj-ccom-gcp-wcas-ukal-wrapper-papi-1-0-15-deployment-7c4d89h8b   2m           0Mi
lex-ext-kdp    busybox-app-77bf6f8649-4qzg9                                      3m           1Mi
aibang          abj-ccom-gcp-wcas-ukal-wrapper-papi-1-0-14-deployment-6fb79d449   2m           1Mi
aibang          nginx-app-549664c599-wtqq9                                        0m           6Mi



kubectl get pods --all-namespaces -o jsonpath='{range .items[?(@.metadata.namespace=="aibang-namespace")].spec.containers[*]}{@.name}{"\t"}{@.resources.requests.cpu}{"\t"}{@.resources.requests.memory}{"\t"}{@.resources.limits.cpu}{"\t"}{@.resources.limits.memory}{"\n"}{end}'
这个命令会列出所有属于aibang-namespace命名空间的Pod的容器名称、CPU和内存请求和限制。

因为用户的API都部署在不同的namespace上，所以需要获取所有的namespace来过滤。



创建监控仪表板：
您可以使用 Stackdriver Monitoring 创建自定义仪表板来显示您的 Kubernetes 集群的资源消耗情况。

有关使用 Stackdriver Monitoring 监控 Kubernetes 集群的更多信息，请参阅 监控 Kubernetes 集群: https://cloud.google.com/kubernetes-engine/docs/tutorials/logging-monitoring/enable-kubernetes-logging-monitoring


