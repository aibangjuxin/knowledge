在 GCP 工程中，如果您想基于某个 Deployment 的 Labels 信息（如 k8s-pod/app）过滤 Pods，并统计它们在一个时间段内的所有 不重复的 pod_name，以下是可行的方法：

方法 1：通过 GCP Logs Explorer

GCP 的 Logs Explorer 支持查询 GKE 的日志数据，您可以利用 LogQL 或 GCP Advanced Filters 来实现过滤和统计：

步骤 1：编写过滤条件

在 Logs Explorer 中设置以下过滤条件：

resource.type="k8s_pod"
resource.labels.cluster_name="your-cluster-name"
resource.labels.namespace_name="your-namespace-name"
labels."k8s-pod/app"="aibangjuxin-1.1.1"

步骤 2：提取 pod_name

在 Logs Explorer 的结果中，查看日志字段 resource.labels.pod_name，并点击 “Group By” 或直接导出日志进行后续处理。

步骤 3：统计不重复的 pod_name

使用以下查询扩展以统计不重复的 pod_name：

resource.type="k8s_pod"
resource.labels.cluster_name="your-cluster-name"
resource.labels.namespace_name="your-namespace-name"
labels."k8s-pod/app"="aibangjuxin-1.1.1"
| count_distinct(resource.labels.pod_name)

上述语句会返回符合条件的 去重的 pod 名称总数。

方法 2：通过 Kubernetes API 与 Prometheus

如果您在 GKE 中配置了 Prometheus，可以直接查询 Deployment 的扩缩记录，并获取时间段内 Pods 的数量及名称。

使用 PromQL 查询

Prometheus 的 kube_pod_labels 和 kube_pod_info 两个指标可以帮助过滤 Pods：

kube_pod_labels{label_k8s_pod_app="aibangjuxin-1.1.1"}

方法 3：通过 kubectl 和 Shell 脚本

如果需要在集群中直接查询，可以使用 kubectl 配合 jq 或 awk 处理不重复的 pod_name。

示例命令

kubectl get pods -n <namespace> \
  -l k8s-pod/app=aibangjuxin-1.1.1 \
  -o json | jq -r '.items[].metadata.name' | sort | uniq

这将直接列出指定 Deployment 的所有 Pods，并去重。

如果需要统计数量

kubectl get pods -n <namespace> \
  -l k8s-pod/app=aibangjuxin-1.1.1 \
  -o json | jq -r '.items[].metadata.name' | sort | uniq | wc -l

方法 4：BigQuery 日志分析

如果您已将 GKE 的日志导出到 BigQuery，可以使用 SQL 查询分析。

示例 SQL 查询

SELECT 
  resource.labels.pod_name,
  COUNT(DISTINCT resource.labels.pod_name) AS unique_pod_count
FROM 
  `your-project-id.dataset-id.logs-table`
WHERE 
  resource.type = "k8s_pod" 
  AND labels."k8s-pod/app" = "aibangjuxin-1.1.1"
  AND timestamp BETWEEN TIMESTAMP("start-time") AND TIMESTAMP("end-time")
GROUP BY 
  resource.labels.pod_name
ORDER BY 
  unique_pod_count DESC;

通过这段查询，您可以获取指定时间范围内所有符合条件的 Pods，并统计数量。

总结

	•	实时需求：使用 GCP Logs Explorer 或 kubectl 是最快速的方案。
	•	历史分析需求：推荐将日志导入 BigQuery 并使用 SQL 处理。
	•	监控和扩缩记录：Prometheus 是一个长期监控扩缩情况的理想方案。


我来帮你解决这个GCP监控查询的问题。为了获取特定Deployment的Pod扩缩容情况，我们可以使用MQL(Monitoring Query Language)来查询。

让我们分步骤来实现：

1. 首先，要获取特定Label的Pod并统计不重复的pod_name，可以使用以下查询：

```
fetch k8s_container
| metric 'kubernetes.io/container/uptime'
| filter resource.labels."k8s-pod/app" = "aibangjuxin-1.1.1"
| group_by [resource.pod_name]
```

2. 如果你想看一段时间内的变化趋势，可以加上时间聚合：

```
fetch k8s_container
| metric 'kubernetes.io/container/uptime'
| filter resource.labels."k8s-pod/app" = "aibangjuxin-1.1.1"
| group_by [resource.pod_name], [count_distinct(resource.pod_name)]
| every 1m
```

3. 如果只想获取Pod总数的变化：

```
fetch k8s_container
| metric 'kubernetes.io/container/uptime'
| filter resource.labels."k8s-pod/app" = "aibangjuxin-1.1.1"
| group_by [], [count_distinct(resource.pod_name)]
| every 1m
```

一些建议：
- 使用`count_distinct`可以避免重复计数同一个Pod
- 可以通过调整`every`参数来改变时间粒度
- 如果需要特定时间范围，可以在查询界面上直接设置时间范围

你也可以在GCP Console的Metrics Explorer中直接使用这些查询。如果你想进一步分析这些数据，比如：
- 查看最大/最小Pod数
- 分析扩缩容触发时间
- 查看特定时间点的Pod列表


明白了，在 Logs Explorer 中我们可以使用查询语法来实现这个需求。以下是几种方法：

1. 基本的查询语句，获取特定应用的 Pod 日志：

```
resource.type="k8s_container"
resource.labels.cluster_name="你的集群名称"
labels."k8s-pod/app"="aibangjuxin-1.1.1"
```

2. 如果要统计不重复的 pod_name，可以使用 `| distinct`：

```
resource.type="k8s_container"
resource.labels.cluster_name="你的集群名称"
labels."k8s-pod/app"="aibangjuxin-1.1.1"
| distinct resource.labels.pod_name
```

3. 如果要统计数量，可以使用 `| count_distinct`：

```
resource.type="k8s_container"
resource.labels.cluster_name="你的集群名称"
labels."k8s-pod/app"="aibangjuxin-1.1.1"
| count_distinct resource.labels.pod_name
```

4. 如果要按时间间隔统计，可以添加时间分组：

```
resource.type="k8s_container"
resource.labels.cluster_name="你的集群名称"
labels."k8s-pod/app"="aibangjuxin-1.1.1"
| count_distinct resource.labels.pod_name
| group_by timestamp_trunc(@timestamp, HOUR)
```

提示：
- 你可以在界面上直接设置时间范围
- 可以将 `HOUR` 改为 `MINUTE` 或 `DAY` 来调整时间粒度
- 如果日志量很大，建议适当缩小时间范围
- 可以添加其他过滤条件，比如特定的命名空间：
  ```
  resource.labels.namespace_name="your-namespace"
  ```

如果你想要更细致的分析，比如：
- 查看每个时间点具体的 Pod 列表
- 分析 Pod 的创建和删除事件
- 观察特定时间段内的变化

我可以帮你进一步优化查询语句。​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​​






