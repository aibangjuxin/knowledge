**Cloud Logging 的日志存储桶 (Log Buckets)** 列表。

执行 gcloud logging buckets list 时，每一行都代表一个 **日志桶 (bucket)**，里面存储了一类日志。

你提到的结果大概是这样的：

| **LOCATION** | **BUCKET_ID** | **RETENTION_DAYS** |
| ------------ | ------------- | ------------------ |
| global       | \_Default     | 30                 |
| global       | \_Required    | 400                |

下面我帮你详细解释这几个格子含义和这两个桶的区别：

---

## **1. 各个字段的含义**

- **LOCATION**
    - global 代表日志桶存储在全局位置（跨区域）。
    - 你也可以创建 region-specific 的日志桶，比如 us-central1。
- **BUCKET_ID**
    - **\_Default**：项目自带的默认日志桶，所有没有特别路由的日志都会存进去。
    - **\_Required**：强制保留的系统审计日志桶。这个桶是 **不能删除或修改的**。
- **RETENTION_DAYS**
    - **30**：表示日志在桶里保存 30 天后会被自动删除。你可以修改 \_Default 的保留期（比如改成 7 天）。
    - **400**：表示日志会保存 400 天，这是 Google 规定的强制保留期，不能更改。

---

## **2.** 

## **\_Default**

##  **vs** 

## **\_Required**

##  **的区别**

| **项目**       | \_Default                                                      | \_Required                                                         |
| -------------- | -------------------------------------------------------------- | ------------------------------------------------------------------ |
| 存储内容       | 普通应用日志、GKE 系统日志、Data Access Audit logs（如果开启） | Admin Activity Audit Logs、System Event Audit Logs（关键审计日志） |
| 是否可删除     | ✅ 可以删除或修改                                              | ❌ 不可删除                                                        |
| 保留时间可修改 | ✅ 可配置（最短 1 天，最长 3650 天）                           | ❌ 固定 400 天                                                     |
| 成本可控性     | ✅ 主要成本来源，可以通过缩短保留和过滤控制                    | ❌ 不可控，但量比较小（只包含核心审计日志）                        |

---

## **3. 为什么要有** 

## **\_Required**

- Google Cloud 强制保留关键审计日志（例如谁创建/删除了 VM、谁修改了 IAM 权限），
- 这是为了满足 **安全合规 (Compliance)** 要求。
- 这些日志必须至少保存 **400 天**，即使你不想要，也不能关掉。

---

## **4. 工程上如何利用**

- **成本优化重点**：只需要管 \_Default，因为 \_Required 体量小、不可控。
- 你可以：
    - 修改 \_Default 保留期（例如非生产 7 天，生产 30 天）。
    - 创建新的自定义 bucket，专门存某类日志（方便控制）。
    - 使用 log exclusion 减少写入 \_Default 的日志量。

---

✅ **总结一句话**

- \_Default = 普通日志桶，30 天默认保留，可改。
- \_Required = 系统强制审计日志桶，400 天固定保留，不可改。

---

要不要我帮你画一个 **日志存储结构的流程图** (Mermaid)，把 \_Default 和 \_Required 在整个 Logging 架构中的作用直观表示出来？

好的 👍

你要修改 \_Default 日志桶的保留时间 (Retention Days)，可以用 gcloud logging buckets update。

### **示例：把** 

### **\_Default**

###  **的保留时间改成** 

### **7 天**

```
gcloud logging buckets update _Default \
  --location=global \
  --retention-days=7 \
  --project=PROJECT_ID
```

### **参数说明**

- **\_Default** → 要修改的日志桶 ID。
- **–location=global** → \_Default 桶的位置，通常是 global。
- **–retention-days=7** → 修改为保留 7 天（支持 1–3650 天）。
- **–project=PROJECT_ID** → 你要操作的 GCP 项目。

### **示例：改成** 

### **90 天**

### **（比如生产环境）**

```
gcloud logging buckets update _Default \
  --location=global \
  --retention-days=90 \
  --project=PROD_PROJECT_ID
```

---

⚠️ 注意：

- 修改只影响 \_Default 桶，不影响 \_Required。
- 修改后会立即生效，过期的日志会被自动清理。

要不要我帮你写一个 **脚本**，可以批量对多个 **非生产项目** 执行这个修改，把 \_Default 统一设置成 7 天？

# About Default

👌 好问题，这个必须讲清楚。

你担心修改 \_Default 桶的保留期会影响哪些日志 —— 我帮你拆解下：

---

## **1.** 

## **\_Default**

##  **桶是什么**

- 每个 GCP 项目都会有一个 \_Default 日志桶，位置一般是 global。
- 如果你没有配置任何 **Log Router Sink** 或 **自定义日志桶**，那么**所有日志**都会进入 \_Default。
- 所以它其实就是一个 “收集所有日志的默认桶”。

---

## **2.** 

## **\_Default**

##  **桶里常见的日志类别**

### **(A)** 

### **应用与服务日志**

- GKE Pod 容器标准输出（stdout / stderr）
- Cloud Run / App Engine 应用日志
- Compute Engine VM 的系统日志（syslog, serial console）

### **(B)** 

### **系统组件日志**

- GKE system 组件日志（kubelet, kube-proxy, fluentd, etc.）
- Load Balancer / Cloud CDN 访问日志
- Cloud NAT 连接日志
- VPC Flow Logs（如果开启了）

### **(C)** 

### **审计日志的一部分**

- **Data Access audit logs**（比如：某人调用了某个 API 读取数据），**默认写入 \_Default**
    ⚠️ 这些日志量大、最耗钱，可以考虑关闭或缩短保留。
- **Admin Activity logs**、**System Event logs** → **不会在 \_Default**，它们强制写入 \_Required。

---

## **3.** 

## **\_Required**

##  **vs** 

## **\_Default**

##  **的区别举例**

| **日志类型**         | **示例**                                   | **存放位置**                |
| -------------------- | ------------------------------------------ | --------------------------- |
| **Admin Activity**   | gcloud iam roles create ... (谁创建了角色) | \_Required (400 天强制保留) |
| **System Event**     | VM terminated by system                    | \_Required                  |
| **Data Access**      | 用户调用 BigQuery jobs.query API           | \_Default (30 天默认，可改) |
| **GKE 应用日志**     | Pod 打印 INFO Starting server on port 8080 | \_Default                   |
| **负载均衡访问日志** | HTTP LB 返回 200 OK                        | \_Default                   |
| **VPC Flow Logs**    | 源 IP:目标 IP 流量                         | \_Default                   |

---

## **4. 修改** 

## **\_Default**

##  **的影响**

👉 如果你把 \_Default 的保留期从 **30 天 → 7 天**：

- **会受影响的日志**：
    - GKE Pod 日志
    - Cloud Run 日志
    - VM 系统日志
    - VPC Flow Logs
    - Load Balancer 访问日志
    - **Data Access Audit Logs**
- **不会受影响的日志**：
    - Admin Activity Logs
    - System Event Logs
        （因为它们在 \_Required 桶，固定 400 天）

---

## **5. 实际例子**

假设你有个项目 my-nonprod-proj：

- Dev 同事部署了一个 GKE 服务，Pod 每分钟打印 INFO health check ok。
- 同时项目启用了 VPC Flow Logs。
- 你现在的 \_Default 是 30 天 → 每个月累计 GB/TB 级日志。

如果你执行：

```
gcloud logging buckets update _Default \
  --location=global \
  --retention-days=7 \
  --project=my-nonprod-proj
```

那么结果是：

- Pod 日志、VPC Flow Logs 只会保存 7 天。
- 8 天前的日志会自动删除。
- Admin Activity（比如 IAM 修改日志）仍然保留 400 天，不受影响。

---

✅ **一句话总结**：

\_Default 桶包含 **所有没有特别路由的普通日志**，例如 GKE 应用日志、系统组件日志、VPC/Load Balancer 日志和 Data Access 审计日志。

如果你缩短 \_Default 的保留期，主要影响的是 **工程运行日志** 和 **Data Access Logs**，但 **不会影响关键审计日志 (Admin Activity/System Event)**，因为它们在 \_Required。

---

要不要我帮你写一个 **过滤器命令**，让你直接查看 \_Default 桶里目前到底有哪些日志类别？这样你可以明确知道缩短保留会删掉哪些。

# loggingConfig.enableComponents 和 \_Default 日志桶

✅ 好问题！你说的这个 loggingConfig.enableComponents 和 \_Default 日志桶是 **直接相关的**。

我帮你拆开讲：

---

## **1. GKE 日志和** 

## **\_Default**

##  **的关系**

- GKE 里的 **节点/系统组件日志**、**容器应用日志** 默认都会通过 **GKE Logging Agent (FluentBit/Fluentd)** 收集，最后写入 Cloud Logging。
- 如果你没有配置 **log router sink**，这些日志都会写到项目的 \_Default 桶里。
- 所以你看到 \_Default 占用很多存储，很大一部分就是 GKE 的日志。

---

## **2.** 

## **loggingConfig.enableComponents**

##  **是什么**

当你跑：

```
gcloud container jiquns describe "$CLUSTER_NAME" --location "$LOCATION" \
  --format="value(loggingConfig.enableComponents)"
```

你可能会看到类似输出：

```
loggingConfig:
  enableComponents:
  - SYSTEM_COMPONENTS
  - WORKLOADS
  - APISERVER
  - CONTROLLER_MANAGER
  - SCHEDULER
```

含义如下：

| **值**             | **含义**                                     | **日志类型** | **默认存放桶** |
| ------------------ | -------------------------------------------- | ------------ | -------------- |
| SYSTEM_COMPONENTS  | 节点和 K8s 系统组件 (kubelet, kube-proxy 等) | 系统运行日志 | \_Default      |
| WORKLOADS          | Pod 容器 stdout/stderr                       | 应用日志     | \_Default      |
| APISERVER          | kube-apiserver 日志                          | 控制面日志   | \_Default      |
| CONTROLLER_MANAGER | kube-controller-manager 日志                 | 控制面日志   | \_Default      |
| SCHEDULER          | kube-scheduler 日志                          | 控制面日志   | \_Default      |

---

## **3. 如何调整**

你可以在创建集群或更新集群时指定要启用哪些组件日志。

### **示例：只启用 Workload 和 System Logs**

```
gcloud container jiquns update "$CLUSTER_NAME" \
  --location "$LOCATION" \
  --logging=SYSTEM_COMPONENTS,WORKLOADS
```

### **示例：完全禁用 GKE Logging（仅适合测试/非生产）**

```
gcloud container jiquns update "$CLUSTER_NAME" \
  --location "$LOCATION" \
  --logging=NONE
```

---

## **4. 对成本的影响**

- **减少 enableComponents** → 少收集日志 → \_Default 里的数据量减少，直接降低存储和查询成本。
- **缩短 \_Default 保留期** → 即便收集日志，但存得更短时间，也能降成本。

两者结合起来效果最好：

- 在 **非生产环境**：禁用不必要的组件日志（比如 APISERVER, SCHEDULER），只留 WORKLOADS。
- 在 **生产环境**：保留关键日志，但可以通过 \_Default retention 控制存储时长。

---

✅ **一句话总结**

- GKE 的 loggingConfig.enableComponents 控制 **哪些日志被收集进 Cloud Logging**。
- \_Default 控制 **这些日志在桶里保存多久**。
- 两个结合使用，才能同时减少 **日志写入量** 和 **存储成本**。

---

要不要我帮你画个 **Mermaid 流程图**，把 GKE 日志采集 → \_Default → 保留/删除的关系画出来？

# How to Verify default

loggingConfig.enableComponents 和 \_Default 日志桶
👌 要看 \_Default 桶到底占了多少存储，可以用 **Cloud Logging 的指标** 或 **Billing 报表**。我给你几种方式：

---

## **1. 用 gcloud 命令查看 Logging Buckets 的存储使用情况**

```
gcloud logging buckets describe _Default \
  --location=global \
  --project=PROJECT_ID
```

⚠️ 不过注意，这个命令只能看到配置（retention 等），**不会显示存储用量**。

要看具体存储大小，需要用 **Metrics Explorer** 或 **Billing**。

---

## **2. 在 Metrics Explorer 查看** 

## **\_Default**

##  **存储使用量**

1. 打开 [Cloud Monitoring → Metrics Explorer](https://console.cloud.google.com/monitoring/metrics-explorer).
2. 选择 **Metric**:

```
Logging → Bucket → Log bucket storage utilization
```

2.

3.  在 **Resource** 里选：

    - Resource type: logging_bucket
    - bucket_id: \_Default
    - location: global

4.  就能看到 \_Default 桶的当前存储量 (bytes)。

---

## **3. 用 gcloud 查询监控指标（命令行）**

```
gcloud monitoring time-series list \
  --project=PROJECT_ID \
  --filter='metric.type="logging.googleapis.com/bucket/bytes_used" AND resource.label."bucket_name"="_Default"' \
  --format="table(points[0].value.doubleValue, metric.labels.bucket_name, resource.labels.location)"
```

示例输出：

```
POINTS[0].VALUE.DOUBLEVALUE  METRIC.LABELS.BUCKET_NAME  RESOURCE.LABELS.LOCATION
1234567890                   _Default                   global
```

单位是 **字节 (bytes)** → 你可以除以 1024^3 转换成 GB。

---

## **4. 从 Billing 里看日志存储费用**

在 Billing 报表里：

- **Cloud Logging → Ingested bytes** (写入量)
- **Cloud Logging → Storage bytes** (存储量)

这样能知道 \_Default 占用多少费用。

---

✅ **一句话总结**

- \_Default 的存储使用量不能直接用 gcloud logging buckets list 看出来。
- 需要用 **Cloud Monitoring 指标 (logging.googleapis.com/bucket/bytes_used)** 或 **Billing 报表** 来确认占用存储大小。

---

要不要我帮你写一个 **脚本**，自动统计某个项目里 \_Default 桶的当前存储量（GB），这样一键就能查？

👌 明白了，我给你一个脚本，可以直接查询某个 GCP 项目里 \_Default 桶的当前存储量（单位 GB）。

---

### **Bash 脚本：查询** 

### **\_Default**

###  **存储量**

```
#!/bin/bash
# 查询 GCP Logging _Default bucket 占用存储 (GB)
# 用法: ./check_default_logging_storage.sh <PROJECT_ID>

PROJECT_ID=$1

if [ -z "$PROJECT_ID" ]; then
  echo "用法: $0 <PROJECT_ID>"
  exit 1
fi

echo "正在查询项目 [$PROJECT_ID] 的 _Default 日志桶存储使用情况..."

gcloud monitoring time-series list \
  --project="$PROJECT_ID" \
  --filter='metric.type="logging.googleapis.com/bucket/bytes_used" AND resource.label."bucket_name"="_Default"' \
  --format="value(points[0].value.doubleValue)" \
  --limit=1 \
  | awk '{printf "%.2f GB\n", $1/1024/1024/1024}'
```

---

### **使用示例**

```
chmod +x check_default_logging_storage.sh
./check_default_logging_storage.sh my-nonprod-project
```

可能输出：

```
正在查询项目 [my-nonprod-project] 的 _Default 日志桶存储使用情况...
3.45 GB
```

---

### **脚本说明**

- 调用 gcloud monitoring time-series list 获取 \_Default 桶的 bytes_used 指标。
- 用 awk 把字节转换为 **GB**，保留两位小数。
- 你可以在 **非生产环境** 批量执行，快速知道每个项目 \_Default 的存储占用。

---

要不要我帮你再扩展一下脚本 👉 **支持传入多个项目 ID**（比如测试/开发/预发），然后自动汇总成一张 Markdown 表格，方便你对比哪个环境日志占用最多？
