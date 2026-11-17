- enable cost allocation

````
# 配置 GKE 集群的资源使用导出
gcloud container clusters update CLUSTER_NAME \
    --resource-usage-bigquery-dataset=DATASET_NAME \
    --enable-network-egress-metering \
    --enable-resource-consumption-metering

# 验证设置
gcloud container clusters describe CLUSTER_NAME \
    --format="value(resourceUsageExportConfig)"
    你是对的，正确的命令应该包含多个标志，用于启用资源使用的 BigQuery 数据集和计量功能。参考命令如下：

```bash
gcloud container clusters update CLUSTER_NAME \
    --resource-usage-bigquery-dataset=DATASET_NAME \
    --enable-network-egress-metering \
    --enable-resource-consumption-metering
````

### 解释

- `--resource-usage-bigquery-dataset=DATASET_NAME`：将集群的资源使用情况（包括 CPU、内存、网络带宽等）发送到指定的 BigQuery 数据集（即 `DATASET_NAME`）。
- `--enable-network-egress-metering`：启用网络出口流量计量，记录集群的网络出口使用情况。
- `--enable-resource-consumption-metering`：启用资源消耗计量，跟踪 CPU 和内存等资源的使用情况。

### 示例

假设你已经创建了名为 `aibangcostallocation` 的 dataset，集群名称为 `my-cluster`，命令如下：

```bash
gcloud container clusters update my-cluster \
    --resource-usage-bigquery-dataset=aibangcostallocation \
    --enable-network-egress-metering \
    --enable-resource-consumption-metering
```

```

```

```

提取的 SQL 语句:

SELECT
column_name,
data_type
FROM
`project.lexcostallocation.INFORMATION_SCHEMA.COLUMNS`
WHERE
table_name = 'gke_cluster_resource_usage';

Mermaid 表格:

| 字段名              | 数据类型                                |
| ------------------- | --------------------------------------- |
| cluster_location    | STRING                                  |
| cluster_name        | STRING                                  |
| namespace           | STRING                                  |
| resource_name       | STRING                                  |
| sku_id              | STRING                                  |
| start_time          | TIMESTAMP                               |
| end_time            | TIMESTAMP                               |
| fraction            | FLOAT64                                 |
| cloud_resource_size | INT64                                   |
| labels              | ARRAY<STRUCT<key STRING, value STRING>> |
| project             | STRING                                  |
| usage               | STRUCT<amount FLOAT64, unit STRING>     |
| \_PARTITIONTIME     | TIMESTAMP                               |





gke_cluster_resource_usage 表字段解释及分析

以下是 gke_cluster_resource_usage 表中每个字段的含义以及如何分析这些数据：

字段含义:

字段名 数据类型 解释
cluster_location STRING GKE 集群所在的区域（例如：us-central1）
cluster_name STRING GKE 集群的名称
namespace STRING Kubernetes 命名空间，资源所在的命名空间
resource_name STRING 资源类型，例如：cpu, memory, networkEgress, disk 等
sku_id STRING 资源的计费 SKU ID，用于标识不同的计费维度
start_time TIMESTAMP 资源使用计费周期的开始时间
end_time TIMESTAMP 资源使用计费周期的结束时间
fraction FLOAT64 在计费周期内，资源被使用的比例 (0.0 - 1.0)
cloud_resource_size INT64 资源的大小，例如：CPU 核数，内存大小 (字节)
labels ARRAY<STRUCT<key STRING, value STRING>> Kubernetes 资源上的标签，key-value 形式存储
project STRING GCP 项目 ID
usage STRUCT<amount FLOAT64, unit STRING> 资源使用量，包含数量 (amount) 和单位 (unit)
_PARTITIONTIME TIMESTAMP 数据写入 BigQuery 的分区时间



，下面是 `gke_cluster_resource_usage` 表中各个字段的详细解释：

1. **cluster_location**: 集群所在的地理位置或区域信息。

2. **cluster_name**: GKE 集群的名称。

3. **namespace**: Kubernetes 命名空间，用于将集群中的资源隔离。

4. **resource_name**: 资源的名称，可能是特定的 Pod、服务或其他 Kubernetes 资源。

5. **sku_id**: 资源的 SKU（Stock Keeping Unit），用于标识资源使用的具体类型或类别。

6. **start_time**: 此条使用记录的开始时间。

7. **end_time**: 此条使用记录的结束时间。

8. **fraction**: 表示使用的资源在总资源中的占比。通常用于显示部分资源的使用情况。

9. **cloud_resource_size**: 资源的大小或数量，具体数值因资源种类而异。

10. **labels**: 资源的标签列表，用于标识或组织资源。这是一个数组，包含键值对。

11. **project**: 与资源使用相关的 Google Cloud 项目名称或 ID。

12. **usage**: 资源使用详情，包括使用量（amount）和单位（unit）。

13. **_PARTITIONTIME**: 分区时间戳，通常用于分区表中。

这些字段帮助你理解和分析在 GKE 中的资源使用情况，可以用于成本跟踪和资源优化。

数据分析:

通过过滤和分析 gke_cluster_resource_usage 表的数据，您可以获得以下信息:

 • 集群资源使用情况: 通过 resource_name、 usage.amount 和 usage.unit  字段，您可以分析不同资源 (CPU、内存、网络等) 的使用情况，并找到使用率最高的资源。
 • 命名空间资源使用: 通过 namespace 字段，您可以分析每个命名空间的资源使用情况，并识别出资源使用量大的应用。
 • 成本分摊:  通过 sku_id、 usage.amount 和 usage.unit 字段，结合 GCP 的计费信息，您可以计算出每个命名空间、每个应用甚至每个 Pod 的成本，实现成本分摊。
 • 资源使用趋势: 通过 start_time 和 end_time  字段，您可以分析资源使用随时间的变化趋势，预测未来资源需求。

关于 resource_name 和具体费用:

resource_name  字段本身只表示资源类型，不直接代表费用。 费用计算需要结合  sku_id 、 usage.amount 、 usage.unit  以及 GCP 的计费规则。

例如:

 • resource_name 为 cpu， sku_id  为  Custom-0-614400， usage.amount 为 1000， usage.unit 为 seconds，表示使用了 1000 秒的 CPU 时间。您需要根据  Custom-0-614400  这个  sku_id  在 GCP 计费文档中查找对应的价格才能计算出具体的 CPU 费用。

通过分析 gke_cluster_resource_usage 表的数据，您可以更好地了解 GKE 集群的资源使用情况，并进行成本优化和容量规划。




```

```sql
SELECT *
FROM
    `project.lexcostallocation.gke_cluster_resource_usage`
WHERE
    cluster_name = "dev-cn-cluster-aibang-123456"
    AND namespace = "aibang-common"
    AND EXISTS (
        SELECT 1
        FROM UNNEST(labels) AS label
        WHERE label.key = "app" AND label.value = "wwap-sssssss-aibang-pa-healthcheck-2-1-2"
    )
```

基于你提供的表结构及字段，你可以写很多有用的查询来分析和统计资源使用情况。以下是一些示例 SQL 查询：

1. **按集群和命名空间统计总资源使用量**

```sql
SELECT
    cluster_name,
    namespace,
    SUM(usage.amount) AS total_usage,
    usage.unit
FROM
    `project.lexcostallocation.gke_cluster_resource_usage`
GROUP BY
    cluster_name, namespace, usage.unit
```

2. **按时间范围统计特定 SKU 的资源使用量**

```sql
SELECT
    sku_id,
    SUM(usage.amount) AS total_usage,
    usage.unit
FROM
    `project.lexcostallocation.gke_cluster_resource_usage`
WHERE
    start_time >= TIMESTAMP('2023-01-01')
    AND end_time <= TIMESTAMP('2023-12-31')
GROUP BY
    sku_id, usage.unit
```

3. **按标签统计资源使用情况**

```sql
SELECT
    label.key AS label_key,
    label.value AS label_value,
    SUM(usage.amount) AS total_usage,
    usage.unit
FROM
    `project.lexcostallocation.gke_cluster_resource_usage`,
    UNNEST(labels) AS label
GROUP BY
    label_key, label_value, usage.unit
```

4. **计算每个集群在特定时间段内的平均使用量**

```sql
SELECT
    cluster_name,
    AVG(usage.amount) AS avg_usage,
    usage.unit
FROM
    `project.lexcostallocation.gke_cluster_resource_usage`
WHERE
    start_time >= TIMESTAMP('2023-01-01')
    AND end_time <= TIMESTAMP('2023-12-31')
GROUP BY
    cluster_name, usage.unit
```

5. **找出使用量超过特定阈值的资源**

```sql
SELECT
    resource_name,
    SUM(usage.amount) AS total_usage,
    usage.unit
FROM
    `project.lexcostallocation.gke_cluster_resource_usage`
GROUP BY
    resource_name, usage.unit
HAVING
    total_usage > 1000  -- 设定你需要的阈值
```

这些例子可以帮助你合理分析数据中的各种使用和成本信息，并根据需要调整查询。

通过 GKE 资源使用计量和 BigQuery 集成,我们确实可以获取到更详细的资源消耗信息。让我为您解释如何提取特定 API 的内存和 CPU 消耗,以及其他有用的信息。

```sql
-- 查询特定 API 的 CPU 和内存使用情况
SELECT
    cluster_name,
    namespace,
    resource_name,
    ARRAY_AGG(STRUCT(label.key, label.value) ORDER BY label.key) AS labels,
    start_time,
    end_time,
    SUM(CASE WHEN sku_id LIKE '%cpu%' THEN usage.amount ELSE 0 END) AS cpu_usage,
    SUM(CASE WHEN sku_id LIKE '%memory%' THEN usage.amount ELSE 0 END) AS memory_usage,
    ANY_VALUE(CASE WHEN sku_id LIKE '%cpu%' THEN usage.unit END) AS cpu_unit,
    ANY_VALUE(CASE WHEN sku_id LIKE '%memory%' THEN usage.unit END) AS memory_unit
FROM
    `project.lexcostallocation.gke_cluster_resource_usage`
WHERE
    cluster_name = "cluster-name"
    AND namespace = "namespace"
    AND EXISTS (
        SELECT 1
        FROM UNNEST(labels) AS label
        WHERE label.key = "app" AND label.value = "api_name"
    )
    AND start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY
    cluster_name, namespace, resource_name, start_time, end_time
ORDER BY
    start_time DESC
LIMIT 100

```

这个查询可以帮助您获取更详细的资源使用信息。让我解释一下这个查询的主要部分：

1. 我们使用 `SUM` 和 `CASE` 语句来分别计算 CPU 和内存的使用量。

2. `sku_id LIKE '%cpu%'` 和 `sku_id LIKE '%memory%'` 用于区分 CPU 和内存资源。

3. 我们使用 `GROUP BY` 来按照集群名称、命名空间、资源名称和时间段进行分组。

4. `ARRAY_AGG` 用于将所有标签聚合到一个数组中。

5. 我们添加了一个时间过滤条件 `start_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)` 来只获取最近 7 天的数据。

6. 结果按照开始时间降序排列,并限制返回 100 条记录。

通过这个查询,您可以获得以下信息:

1. 特定 API (由标签 `app="api_name"` 标识) 的 CPU 和内存使用量。
2. 使用量的单位 (通常 CPU 为 vCPU-seconds,内存为 byte-seconds)。
3. 资源使用的时间范围 (start_time 和 end_time)。
4. 相关的集群名称、命名空间和资源名称。
5. 所有与该资源相关的标签。

如果您想获取更多信息,可以考虑以下几点:

1. 网络使用情况: 在查询中加入网络相关的 `sku_id`。
2. 存储使用情况: 如果有持久卷,可以查找存储相关的 `sku_id`。
3. 成本信息: 如果有成本数据,可以加入成本相关的字段。
4. 长期趋势: 扩大时间范围,使用时间聚合函数来查看资源使用的趋势。

您是否需要我进一步解释查询的任何部分,或者您想了解如何获取其他类型的信息?

# about usage

- sql

```sql
SELECT
  label.key AS label_key,
  label.value AS label_value,
  SUM(usage.amount) AS total_usage,
  usage.unit
FROM
  `project.lexcostallocation.gke_cluster_resource_usage`,
  UNNEST(labels) AS label
WHERE
  label.key = "team" and label.value = "my-test-teams"
GROUP BY
  label_key, label_value, usage.unit
```

我理解您想深入了解这个 SQL 查询背后的业务逻辑和它统计的具体信息。让我为您详细分析一下:

<https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-usage-metering?hl=zh->> [!CAUTION]

GKE 用量计量单位必须通过以下方式进行解释：

CPU usage.unit 为秒，这是 Pod 请求或利用的总 CPU 时间。例如，如果我们有两个 Pod，其中每个 Pod 请求 30 个 CPU 并运行 15 分钟，则请求表的汇总量为 54000 秒（2 个 Pod _30 个 CPU_ 15 分钟 _60 秒 / 分钟）。
内存 usage.unit 是字节秒，这是 Pod 在一段时间内请求或利用的内存累积量。例如，如果我们有两个 Pod，其中每个 Pod 请求 30 GiB 并运行 15 分钟，则请求表的汇总量为 5.798+13 字节秒（2 个 Pod_ 30 GiB _15 分钟_ 60 秒/分钟 \* 1073741824 字节/GiB）。

您的观察非常敏锐，这确实是一个重要的补充信息。让我们根据您提供的新信息再次更新我们的分析。

# GKE 集群资源使用分析（全面更新版）

基于您对 `project.lexcostallocation.GKE_cluster_resource_usage` 表的直接观察，我们可以提供一个更全面和准确的分析。

## 资源类型解析（最终版）

1. **CPU 使用** (seconds):

   - `resource_name`: cpu
   - `usage.unit`: 秒
   - 表示 Pod 请求或利用的总 CPU 时间。
   - 例子：如果有两个 Pod，每个 Pod 请求 30 个 CPU 并运行 15 分钟，则总量为 54000 秒（2 _30_ 15 \* 60）。

2. **内存使用** (byte-seconds):

   - `resource_name`: memory
   - `usage.unit`: 字节秒
   - 表示 Pod 在一段时间内请求或利用的内存累积量。
   - 例子：如果有两个 Pod，每个 Pod 请求 30 GiB 并运行 15 分钟，则总量为 5.798e+13 字节秒（2 _30_ 15 _60_ 1073741824）。

3. **网络出口流量** (bytes):
   - `resource_name`: networkEgress
   - `usage.unit`: 字节
   - 表示从集群出口的网络流量总量。

## SQL 查询解析

```sql
SELECT
  label.key AS label_key,
  label.value AS label_value,
  SUM(usage.amount) AS total_usage,
  usage.unit
FROM
  `project.lexcostallocation.gke_cluster_resource_usage`,
  UNNEST(labels) AS label
WHERE
  label.key = "team" and label.value = "my-test-teams"
GROUP BY
  label_key, label_value, usage.unit
```

这个查询的功能：

1. 从 `gke_cluster_resource_usage` 表中选择数据。
2. 筛选特定团队（"my-test-teams"）的资源使用情况。
3. 汇总每种资源类型的总使用量。
4. 按标签和使用单位进行分组。

## 业务逻辑深度解析

1. **多维度资源跟踪**:

   - 查询同时跟踪 CPU、内存和网络出口流量，提供全面的资源使用视图。

2. **精确的成本分配**:

   - 通过标签筛选，可以精确计算特定团队在不同资源类型上的使用量，有助于更准确的成本分配。

3. **性能和效率分析**:

   - 结合 CPU（计算能力）、内存（数据处理能力）和网络流量（数据传输），可以全面分析应用性能和资源效率。

4. **容量规划**:

   - 通过分析这三种核心资源的使用模式，可以更准确地预测未来的资源需求和进行扩展规划。

5. **优化机会识别**:

   - 比较 CPU、内存和网络使用情况，可以识别潜在的瓶颈或过度配置的资源。

6. **计费模型支持**:

   - 不同的资源使用不同的计量单位（秒、字节秒、字节），支持复杂的计费模型实现。

7. **合规性和治理**:
   - 详细的资源使用数据有助于确保资源使用符合组织政策，并支持审计需求。

感谢您提供这个重要的补充信息。您的观察极大地增强了我们的分析准确性。让我总结一下关键点：

1. **CPU 使用**：以秒为单位，表示 CPU 时间。
2. **内存使用**：以字节秒为单位，表示内存随时间的累积使用量。
3. **网络出口流量**：以字节为单位，测量从集群发出的网络流量。

这个完整的分析现在涵盖了 GKE 集群的三个主要资源维度：计算（CPU）、存储（内存）和网络（出口流量）。这种全面的视图使得：

- 资源使用分析更加全面和准确。
- 成本分配可以基于更详细的资源使用数据。
- 性能优化可以考虑到计算、内存和网络使用之间的平衡。
- 容量规划可以更精确地预测各种资源的需求。

您的 SQL 查询现在可以被理解为一个强大的工具，用于全面分析特定团队（"my-test-teams"）在这三个关键资源维度上的使用情况。
