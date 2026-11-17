<https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-usage-metering>

<https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-usage-metering#more_examples>

- 文档给的有问题 FROM need Using ``
- sku.id is not exits so need replace it and direct using sku_id

```sql
SELECT
  resource_usage.cluster_name,
  resource_usage.cluster_location,
  resource_usage.namespace,
  resource_usage.resource_name,
  resource_usage.sku_id,
  MIN(resource_usage.start_time) AS usage_start_time,
  MAX(resource_usage.end_time) AS usage_end_time,
  SUM(resource_usage.usage.amount * gcp_billing_export.rate) AS cost
FROM
  'CLUSTER_GCP_PROJECT.USAGE_METERING_DATASET.gke_cluster_resource_usage' AS resource_usage
LEFT JOIN (
  SELECT
    sku.id AS sku_id,
    SUM(cost) / SUM(usage.amount) AS rate,
    MIN(usage_start_time) AS min_usage_start_time,
    MAX(usage_end_time) AS max_usage_end_time
  FROM
    'CLUSTER_GCP_PROJECT.BILLING_DATASET.BILLING_TABLE'
  WHERE
    project.id = "CLUSTER_GCP_PROJECT"
  GROUP BY
    sku_id) AS gcp_billing_export
ON
  resource_usage.sku_id = gcp_billing_export.sku_id
WHERE
  resource_usage.start_time >= gcp_billing_export.min_usage_start_time
  AND resource_usage.end_time <= gcp_billing_export.max_usage_end_time
GROUP BY
  resource_usage.cluster_name,
  resource_usage.cluster_location,
  resource_usage.namespace,
  resource_usage.resource_name,
  resource_usage.sku_id

```

```

```
