# Cloud Logging 日志存储桶 (Log Buckets) 详解

`gcloud logging buckets list` 命令的输出结果展示了项目中的日志存储桶（Log Buckets）列表。每一行都代表一个用于存储特定类型日志的容器。

一个典型的输出如下：

| LOCATION | BUCKET_ID | RETENTION_DAYS |
| :--- | :--- | :--- |
| global | `_Default` | 30 |
| global | `_Required` | 400 |

下面，我将为您详细解释这些字段的含义以及 `_Default` 和 `_Required` 这两个核心存储桶的区别。

---

## 1. 各个字段的含义

-   **`LOCATION`**
    -   `global` 代表日志桶存储在全局位置（跨区域）。
    -   您也可以创建区域性（region-specific）的日志桶，例如 `us-central1`。
-   **`BUCKET_ID`**
    -   `_Default`：项目自带的默认日志桶。所有没有被日志路由器（Log Router）特别路由的日志都会存放在这里。
    -   `_Required`：强制保留的系统审计日志桶。这个桶是 **不能被删除或修改的**。
-   **`RETENTION_DAYS`**
    -   `30`：表示 `_Default` 桶中的日志在保存30天后会被自动删除。您可以修改这个保留期（例如，缩短为7天）。
    -   `400`：表示 `_Required` 桶中的日志会强制保存400天。这是 Google Cloud 为满足合规性设定的策略，不能更改。

---

## 2. `_Default` vs `_Required` 的区别

| 特性 | `_Default` | `_Required` |
| :--- | :--- | :--- |
| **存储内容** | 普通应用日志、GKE 系统日志、Data Access Audit logs（如果开启） | Admin Activity Audit Logs、System Event Audit Logs（关键审计日志） |
| **是否可删除** | ✅ 可以删除或修改 | ❌ 不可删除 |
| **保留时间可修改** | ✅ 可配置（最短1天，最长3650天） | ❌ 固定400天 |
| **成本可控性** | ✅ 主要成本来源，可以通过缩短保留期和设置排除规则来控制 | ❌ 不可控，但日志量通常较小（只包含核心审计日志） |

---

## 3. 为什么要有 `_Required` 桶？

-   Google Cloud 强制要求保留关键的审计日志，例如“谁创建/删除了虚拟机”、“谁修改了IAM权限”等。
-   这是为了满足 **安全与合规 (Security and Compliance)** 的要求。
-   这些关键日志必须至少保存 **400天**，即使用户不希望保留，也无法关闭或修改此策略。

---

## 4. 工程上如何利用？

-   **成本优化重点**：您的所有优化工作都应聚焦于 `_Default` 桶，因为 `_Required` 桶的日志体量小且策略不可控。
-   **您可以采取的措施**：
    -   修改 `_Default` 桶的保留期（例如，非生产环境设置为7天，生产环境设置为30天）。
    -   创建新的自定义日志桶（Custom Buckets），用于专门存放某类日志，以实现更精细的控制。
    -   使用日志排除规则（Log Exclusion）来减少写入 `_Default` 桶的日志量，从源头降低成本。

---

✅ **总结一句话**

-   `_Default` = 普通日志桶，默认保留30天，**可修改**。
-   `_Required` = 系统强制审计日志桶，固定保留400天，**不可修改**。

---

要不要我帮你画一个 **日志存储结构的流程图** (Mermaid)，把 `_Default` 和 `_Required` 在整个 Logging 架构中的作用直观表示出来？

好的 👍

您可以使用 `gcloud logging buckets update` 命令来修改 `_Default` 日志桶的保留时间 (Retention Days)。

### 示例：将 `_Default` 的保留时间改成 7 天

```bash
gcloud logging buckets update _Default \
  --location=global \
  --retention-days=7 \
  --project=PROJECT_ID
```

#### 参数说明

-   `_Default` → 您要修改的日志桶的 ID。
-   `--location=global` → `_Default` 桶的位置，通常是 `global`。
-   `--retention-days=7` → 您希望修改为的保留天数（支持1–3650天）。
-   `--project=PROJECT_ID` → 您要操作的目标 GCP 项目 ID。

### 示例：将 `_Default` 的保留时间改成 90 天（适用于生产环境）

```bash
gcloud logging buckets update _Default \
  --location=global \
  --retention-days=90 \
  --project=PROD_PROJECT_ID
```

---

⚠️ **注意**：

-   此修改只影响 `_Default` 桶，不会影响 `_Required` 桶。
-   修改会立即生效，任何超过新保留期的现有日志将被自动清理。

要不要我帮你写一个 **脚本**，可以批量对多个 **非生产项目** 执行这个修改，把 `_Default` 统一设置成 7 天？

---

# `_Default` 桶里到底有什么？

👌 好问题，这个必须讲清楚。您担心修改 `_Default` 桶的保留期会影响哪些日志，下面我为您详细拆解。

## 1. `_Default` 桶是什么？

-   每个 GCP 项目都会自动创建一个名为 `_Default` 的日志桶，其位置通常是 `global`。
-   如果您没有配置任何自定义的日志路由器（Log Router Sink）或日志桶，那么**项目中的所有日志**都会默认流入 `_Default` 桶。
-   因此，您可以把它理解为一个“收集所有日志的默认容器”。

## 2. `_Default` 桶里常见的日志类别

### (A) 应用与服务日志

-   GKE Pod 容器的标准输出（stdout / stderr）
-   Cloud Run / App Engine 应用日志
-   Compute Engine VM 的系统日志（syslog, serial console）

### (B) 系统组件日志

-   GKE 系统组件日志（kubelet, kube-proxy, fluentd, etc.）
-   Cloud Load Balancing / Cloud CDN 访问日志
-   Cloud NAT 连接日志
-   VPC Flow Logs（如果开启）

### (C) 部分审计日志

-   **Data Access audit logs**（例如：记录某人调用API读取数据的行为）。这类日志**默认写入 `_Default` 桶**。
    ⚠️ **注意**：这类日志量通常很大，是主要的成本来源之一。可以考虑在非生产环境中关闭或为其设置更短的保留期。
-   **Admin Activity logs** 和 **System Event logs** → **不会** 存放在 `_Default` 桶中，它们被强制写入 `_Required` 桶。

## 3. `_Required` vs `_Default` 的日志存放示例

| 日志类型 | 示例 | 存放位置 |
| :--- | :--- | :--- |
| **Admin Activity** | `gcloud iam roles create ...` (谁创建了角色) | `_Required` (400天强制保留) |
| **System Event** | `VM terminated by system` (系统事件) | `_Required` |
| **Data Access** | 用户调用 `BigQuery jobs.query` API | `_Default` (30天默认，可改) |
| **GKE 应用日志** | Pod 打印 `INFO Starting server on port 8080` | `_Default` |
| **负载均衡访问日志** | HTTP LB 返回 `200 OK` | `_Default` |
| **VPC Flow Logs** | 源IP:目标IP的流量记录 | `_Default` |

## 4. 修改 `_Default` 保留期的影响

👉 如果您将 `_Default` 桶的保留期从 **30天缩短为7天**：

-   **会受影响的日志**：
    -   GKE Pod 日志
    -   Cloud Run 日志
    -   VM 系统日志
    -   VPC Flow Logs
    -   Load Balancer 访问日志
    -   **Data Access Audit Logs**
-   **不会受影响的日志**：
    -   Admin Activity Logs
    -   System Event Logs
        (因为它们存放在 `_Required` 桶中，固定保留400天)

## 5. 实际例子

假设您有一个非生产项目 `my-nonprod-proj`：

-   开发同事部署了一个 GKE 服务，其 Pod 每分钟都会打印 `INFO health check ok`。
-   同时，该项目启用了 VPC Flow Logs。
-   当前 `_Default` 桶的保留期是30天，每月累计了 GB/TB 级别的日志。

如果您执行以下命令：

```bash
gcloud logging buckets update _Default \
  --location=global \
  --retention-days=7 \
  --project=my-nonprod-proj
```

那么结果是：

-   该项目中的 Pod 日志、VPC Flow Logs 将只保存7天。
-   8天前的这些日志会被自动删除。
-   但该项目中的 Admin Activity 日志（例如 IAM 权限修改记录）仍然会保留400天，不受影响。

---

✅ **一句话总结**：

`_Default` 桶包含**所有没有被特别路由的普通日志**，例如 GKE 应用日志、系统组件日志、VPC/Load Balancer 日志和 Data Access 审计日志。

如果您缩短 `_Default` 的保留期，主要影响的是**工程运行日志**和**Data Access Logs**，但**不会影响关键的合规性审计日志 (Admin Activity/System Event)**，因为它们安全地存放在 `_Required` 桶中。

---

要不要我帮你写一个 **过滤器命令**，让您直接查看 `_Default` 桶里目前到底有哪些日志类别？这样您可以明确知道缩短保留期会删掉哪些类型的日志。

---

# GKE `loggingConfig` 与 `_Default` 桶的关系

✅ 好问题！GKE 集群的 `loggingConfig.enableComponents` 和 `_Default` 日志桶是**直接相关的**。我为您拆解一下。

## 1. GKE 日志与 `_Default` 桶的关系

-   GKE 集群中的**节点/系统组件日志**和**容器应用日志**，默认都会通过 **GKE Logging Agent (基于 FluentBit/Fluentd)** 进行收集，并最终写入 Cloud Logging。
-   如果您没有配置自定义的日志路由器（Log Router Sink），这些从 GKE 收集的日志都会被发送到项目的 `_Default` 日志桶中。
-   因此，您看到的 `_Default` 桶占用大量存储空间，其中很大一部分通常源自 GKE 集群。

## 2. `loggingConfig.enableComponents` 是什么？

当您运行以下命令时：

```bash
gcloud container jiquns describe "$CLUSTER_NAME" --location "$LOCATION" \
  --format="value(loggingConfig.enableComponents)"
```

您可能会看到类似以下的 YAML 格式输出：

```yaml
loggingConfig:
  enableComponents:
  - SYSTEM_COMPONENTS
  - WORKLOADS
  - APISERVER
  - CONTROLLER_MANAGER
  - SCHEDULER
```

这些值的含义如下：

| 值 | 含义 | 日志类型 | 默认存放桶 |
| :--- | :--- | :--- | :--- |
| `SYSTEM_COMPONENTS` | 节点和 K8s 系统组件 (kubelet, kube-proxy 等) | 系统运行日志 | `_Default` |
| `WORKLOADS` | Pod 容器的 stdout/stderr | 应用日志 | `_Default` |
| `APISERVER` | kube-apiserver 日志 | 控制平面日志 | `_Default` |
| `CONTROLLER_MANAGER` | kube-controller-manager 日志 | 控制平面日志 | `_Default` |
| `SCHEDULER` | kube-scheduler 日志 | 控制平面日志 | `_Default` |

## 3. 如何调整 `loggingConfig`？

您可以在创建或更新集群时，通过 `--logging` 标志指定要启用的组件日志。

### 示例：只启用 Workload 和 System Logs

```bash
gcloud container jiquns update "$CLUSTER_NAME" \
  --location "$LOCATION" \
  --logging=SYSTEM_COMPONENTS,WORKLOADS
```

### 示例：完全禁用 GKE Logging（仅适合测试/非生产环境）

```bash
gcloud container jiquns update "$CLUSTER_NAME" \
  --location "$LOCATION" \
  --logging=NONE
```

## 4. `loggingConfig` 对成本的影响

-   **减少 `enableComponents`** → 从源头减少收集的日志量 → `_Default` 桶的**注入量**减少，直接降低成本。
-   **缩短 `_Default` 保留期** → 即使收集了日志，但缩短存储时间 → 降低**存储成本**。

将两者结合使用，效果最佳：

-   在**非生产环境**：可以考虑禁用不必要的组件日志（如 `APISERVER`, `SCHEDULER`），只保留 `WORKLOADS`。
-   在**生产环境**：保留所有关键组件的日志，但通过调整 `_Default` 的保留期来控制长期存储成本。

---

✅ **一句话总结**

-   GKE 的 `loggingConfig.enableComponents` 控制**哪些日志被收集并发送到 Cloud Logging**。
-   `_Default` 桶的保留期设置控制**这些被收集的日志能在桶里保存多久**。
-   两者结合使用，才能同时优化**日志的注入成本**和**存储成本**。

---

要不要我帮你画个 **Mermaid 流程图**，把 GKE 日志采集 → `_Default` 桶 → 保留/删除的关系画出来？

---

# 如何验证 `_Default` 桶的存储用量

👌 要查看 `_Default` 桶到底占用了多少存储空间，您可以使用 **Cloud Monitoring 的指标** 或 **Billing 报表**。以下是几种具体方法：

## 1. 使用 `gcloud` 命令查看桶配置

```bash
gcloud logging buckets describe _Default \
  --location=global \
  --project=PROJECT_ID
```

⚠️ **请注意**：此命令只能查看桶的配置信息（如保留策略），**并不会显示当前的存储用量**。要查看具体用量，需要使用 Metrics Explorer 或 Billing。

## 2. 在 Metrics Explorer 中可视化存储用量

1.  打开 [Cloud Monitoring → Metrics Explorer](https://console.cloud.google.com/monitoring/metrics-explorer)。
2.  选择 **Metric**：
    ```
    Logging → Bucket → Log bucket storage utilization
    ```
3.  在 **Resource** 中进行筛选：
    -   Resource type: `logging_bucket`
    -   bucket_id: `_Default`
    -   location: `global`
4.  图表将显示 `_Default` 桶的当前存储量（单位为 bytes）。

## 3. 使用 `gcloud` 查询监控指标（命令行方式）

```bash
gcloud monitoring time-series list \
  --project=PROJECT_ID \
  --filter='metric.type="logging.googleapis.com/bucket/bytes_used" AND resource.label."bucket_name"="_Default"' \
  --format="table(points[0].value.doubleValue, metric.labels.bucket_name, resource.labels.location)"
```

#### 示例输出

```console
POINTS[0].VALUE.DOUBLEVALUE  METRIC.LABELS.BUCKET_NAME  RESOURCE.LABELS.LOCATION
1234567890                   _Default                   global
```

输出值的单位是**字节 (bytes)**。您可以将其除以 `1024*1024*1024` (或 1024^3) 来转换为 GB。

## 4. 从 Billing 报表中分析日志成本

在您的 Billing 报表中，通过 SKU 进行筛选，可以找到与日志相关的费用：

-   **Cloud Logging → Ingested bytes** (日志注入量)
-   **Cloud Logging → Storage bytes** (日志存储量)

通过这种方式，您可以直接了解 `_Default` 桶的存储占用了多少费用。

---

✅ **一句话总结**

-   `_Default` 桶的存储使用量无法通过 `gcloud logging buckets list` 直接查看。
-   需要使用 **Cloud Monitoring 指标 (`logging.googleapis.com/bucket/bytes_used`)** 或 **Billing 报表** 来确认其占用的存储空间大小。

---

要不要我帮您写一个**脚本**，可以自动统计某个项目里 `_Default` 桶的当前存储量（以GB为单位），让您一键就能查询？

👌 明白了，我给您一个脚本，可以直接查询某个 GCP 项目里 `_Default` 桶的当前存储量（单位为 GB）。

---

### Bash 脚本：查询 `_Default` 存储量

```bash
#!/bin/bash
#
# 功能: 查询指定GCP项目中 _Default 日志桶的当前存储占用空间 (GB)
# 用法: ./check_default_logging_storage.sh <PROJECT_ID>
#

PROJECT_ID=$1

if [ -z "$PROJECT_ID" ]; then
  echo "错误: 请提供一个 GCP 项目 ID。"
  echo "用法: $0 <PROJECT_ID>"
  exit 1
fi

echo "正在查询项目 [$PROJECT_ID] 的 _Default 日志桶存储使用情况..."

# 调用 gcloud monitoring API 获取最新的 'bytes_used' 指标值
bytes_used=$(gcloud monitoring time-series list \
  --project="$PROJECT_ID" \
  --filter='metric.type="logging.googleapis.com/bucket/bytes_used" AND resource.label."bucket_name"="_Default"' \
  --format="value(points[0].value.doubleValue)" \
  --limit=1)

if [ -z "$bytes_used" ]; then
    echo "未能获取到项目 [$PROJECT_ID] 的存储数据。请检查项目ID是否正确或您是否有足够权限。"
    exit 1
fi

# 使用 awk 将字节转换为 GB 并格式化输出
echo "$bytes_used" | awk '{printf "当前存储量: %.2f GB\n", $1/1024/1024/1024}'
```

---

### 使用示例

1.  将脚本内容保存为 `check_default_logging_storage.sh`。
2.  授予执行权限：`chmod +x check_default_logging_storage.sh`。
3.  运行脚本并传入您的项目ID：

```bash
./check_default_logging_storage.sh my-nonprod-project
```

#### 可能的输出

```console
正在查询项目 [my-nonprod-project] 的 _Default 日志桶存储使用情况...
当前存储量: 3.45 GB
```

---

### 脚本说明

-   该脚本通过调用 `gcloud monitoring time-series list` 来获取 `_Default` 桶的 `bytes_used` 指标的最新数据点。
-   然后使用 `awk` 将返回的字节数转换为 **GB**，并保留两位小数，使结果更具可读性。
-   您可以在非生产环境中批量执行此脚本，快速了解每个项目 `_Default` 桶的存储占用情况。

---

要不要我帮您再扩展一下脚本 👉 **支持传入多个项目 ID**（比如测试/开发/预发），然后自动汇总成一张 Markdown 表格，方便您对比哪个环境的日志占用最多？

```