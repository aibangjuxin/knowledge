# Cloud Run 监控与性能评估实战指南

本文档是为开发者提供的一份实战指南，旨在帮助您掌握监控和评估 Google Cloud Run 服务性能的核心技能。有效的监控是快速调试问题、优化性能和控制成本的关键。

Cloud Run 的监控主要依赖两个核心工具：

1.  **Cloud Logging**：用于深入分析每次请求的详细日志和应用内部打印的日志。
2.  **Cloud Monitoring**：用于观察服务的宏观性能指标、趋势和设置告警。

---

## Part 1: 使用 Cloud Logging 进行深度调试

Cloud Logging 是您排查具体问题的“显微镜”。当出现 500 错误、非预期行为或需要追踪单个请求时，这里是您的第一站。

### 如何访问日志

1.  **进入 Google Cloud Console**。
2.  导航到 **Cloud Run**。
3.  点击您想要监控的服务（例如 `my-app-service`）。
4.  选择 **LOGS (日志)** 标签页。

默认情况下，这里会展示与该服务相关的所有日志，并按时间倒序排列。

### 理解两种核心日志

在日志流中，您会看到两种主要类型的日志条目，它们通常交织在一起：

#### 1. 请求日志 (Request Logs)

这是由 Cloud Run 平台为 **每一个** HTTP 请求自动生成的结构化日志。它告诉您请求的“元数据”。

-   **关键字段解读**：
    *   `httpRequest.status`：HTTP 响应状态码 (例如 `200`, `404`, `500`)。**这是查找错误的第一个线索**。
    *   `httpRequest.latency`：请求处理的总延迟（例如 `1.234s`）。**这是定位性能瓶颈的关键**。
    *   `httpRequest.requestMethod` 和 `httpRequest.requestUrl`：请求的方法 (GET/POST) 和路径。
    *   `httpRequest.protocol`：请求使用的协议 (例如 `HTTP/2.0`)。
    *   `trace`：请求的追踪 ID。您可以用这个 ID 筛选出与单次请求相关的所有日志，非常适合追踪复杂的调用链。

#### 2. 应用日志 (Application Logs)

这是由您服务内部的代码通过标准输出 (`stdout`) 或标准错误 (`stderr`) 打印的日志。例如 `console.log()` (Node.js), `print()` (Python), `log.info()` (Java)。

-   **关键字段解读**：
    *   `textPayload`：如果您的日志是纯文本字符串，会显示在这里。
    *   `jsonPayload`：如果您的日志是 JSON 格式的字符串，Cloud Logging 会自动解析并结构化地展示在这里。**强烈推荐使用 JSON 格式打印日志**，因为它让查询和过滤变得极其强大。
    *   `severity`：日志级别 (例如 `INFO`, `WARNING`, `ERROR`)。

### 实用的查询技巧 (Logs Explorer)

为了更高效地查找信息，您需要使用 **Logs Explorer** 的查询功能。

**基础查询**：

```gcl
# 筛选特定 Cloud Run 服务的日志
resource.type="cloud_run_revision"
resource.labels.service_name="your-service-name"
```

**高级查询示例**：

```gcl
# 查找所有 5xx 错误
resource.type="cloud_run_revision"
resource.labels.service_name="your-service-name"
httpRequest.status >= 500
```

```gcl
# 查找延迟超过 3 秒的请求
resource.type="cloud_run_revision"
resource.labels.service_name="your-service-name"
httpRequest.latency >= "3s"
```

```gcl
# 查找应用日志中包含特定错误文本的日志
resource.type="cloud_run_revision"
resource.labels.service_name="your-service-name"
(textPayload:"timeout" OR jsonPayload.message:"timeout")
severity>=ERROR
```

---

## Part 2: 使用 Cloud Monitoring 进行性能评估

如果说 Logging 是“微观”的，那么 Monitoring 就是“宏观”的。它帮助您了解服务的整体健康状况、性能趋势和资源使用情况。

### 如何访问指标

1.  在您的 Cloud Run 服务页面，选择 **METRICS (指标)** 标签页。
2.  您可以选择不同的时间范围，例如 `1 hour`, `6 hours`, `1 day`。

### 核心性能指标 (KPIs) 解读

#### 1. 请求计数 (Request Count)

*   **做什么**：显示在选定时间内的总请求量。
*   **为什么重要**：帮助您了解服务的负载情况，并将其他指标（如延迟）与流量模式相关联。

#### 2. 请求延迟 (Request Latency)

*   **做什么**：以图表形式展示请求的响应时间分布，通常提供 50th, 95th, 99th 百分位数（p50, p95, p99）。
*   **为什么重要**：
    *   **p50 (中位数)**：一半的请求快于这个时间。
    *   **p95/p99**：代表最慢的 5% 或 1% 的请求。**这对于评估用户体验至关重要**。高的 p99 延迟意味着有部分用户正在经历非常慢的响应，这正是导致 `AsyncRequestTimeoutException` 的元凶。

#### 3. 实例数 (Instance Count)

*   **做什么**：显示在任何给定时间点，正在运行的容器实例数量。
*   **为什么重要**：
    *   **评估扩缩容行为**：您可以看到服务是如何根据流量自动扩容和缩容的。
    *   **识别冷启动**：如果您看到实例数频繁地从 0 变为 1，说明您的服务正在经历频繁的冷启动。这是优化延迟的一个重要方向。

#### 4. 容器 CPU 利用率 (Container CPU Utilization)

*   **做什么**：显示实例的 CPU 使用百分比。
*   **为什么重要**：如果 CPU 利用率持续接近 100%，说明服务是 CPU 密集型的，可能需要分配更多的 CPU 才能降低延迟。

#### 5. 容器内存利用率 (Container Memory Utilization)

*   **做什么**：显示实例的内存使用百分比。
*   **为什么重要**：如果内存利用率持续接近 100%，您的服务可能会因为内存溢出 (Out of Memory, OOM) 而崩溃和重启。这是导致请求失败和高延迟的常见原因。

### 设置告警 (Alerting)

监控的最终目的是为了主动响应。您可以基于上述任何指标创建告警策略。

**常见告警策略示例**：

*   **高延迟告警**：当“p99 请求延迟”在 5 分钟内持续高于 5 秒时，发送通知。
*   **高错误率告警**：当“5xx 响应计数”占“总请求计数”的比例在 10 分钟内超过 1% 时，发送通知。
*   **资源耗尽告警**：当“容器内存利用率”在 5 分钟内持续高于 90% 时，发送通知。

要创建告警，请点击指标图表右上角的 **CREATE ALERTING POLICY**。

## 总结与最佳实践

1.  **养成习惯**：遇到问题时，**先看 Cloud Logging** 找到具体的错误日志和请求；**再看 Cloud Monitoring** 理解问题发生时服务的宏观状态（例如，是否正处于流量高峰或资源瓶颈）。
2.  **结构化日志**：在您的应用代码中，尽量使用 JSON 格式打印日志。这会极大地提升您在 Cloud Logging 中的查询效率。
3.  **设置告警**：不要等到用户报告问题。为您最关心的指标（如延迟和错误率）设置告警，以便在问题萌芽时就能收到通知。
