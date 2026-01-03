
Kong 确实有 **后端存活 (Upstream Health Check)** 的概念，并且提供了非常强大的健康检查机制，用于判断其所代理的后端服务 (在你的场景中是 GKE RT SVC 背后的 Pods) 是否健康可用。

**Kong 健康检查的核心概念:**

Kong 的健康检查机制旨在确保 Kong 能够智能地将流量路由到健康的后端实例，避免将流量发送到不健康的实例，从而提高整体系统的可用性和稳定性。

Kong 的健康检查主要分为两种类型：

1. **主动健康检查 (Active Health Checks):**
2. **被动健康检查 (Passive Health Checks):**

**1. 主动健康检查 (Active Health Checks)**

* **工作原理:**  Kong 会定期主动地向配置的 Upstream Service 的后端地址发送健康检查请求 (Probe)。根据健康检查请求的响应结果来判断后端是否健康。
* **支持的协议:**
    * **HTTP/HTTPS:**  Kong 可以发送 HTTP/HTTPS GET 请求到指定的路径，并根据 HTTP 响应状态码 (例如 2xx, 3xx 视为健康，4xx, 5xx 视为不健康) 和响应体内容 (可选) 来判断健康状态。
    * **TCP:** Kong 可以尝试建立 TCP 连接到指定的端口，如果连接成功建立，则视为健康。
    * **gRPC (Kong Enterprise):** Kong Enterprise 版本支持 gRPC 健康检查。
* **配置选项 (部分重要选项):**
    * **`type`:** 健康检查类型，可以是 `http`, `tcp`, `grpc` (Enterprise)。
    * **`interval`:**  健康检查的频率 (秒)。 例如 `interval: 30` 表示每 30 秒进行一次健康检查。
    * **`timeout`:**  健康检查请求的超时时间 (秒)。
    * **`healthy.interval`:**  当后端被标记为健康后，健康检查的频率 (秒)。 可以设置比 `interval` 更长的值，减少健康后端上的健康检查开销。
    * **`healthy.http_statuses`:**  被视为健康的 HTTP 状态码列表。 默认是 `[200, 201, 202, 203, 204, 205, 206, 207, 208, 226, 300, 301, 302, 303, 304, 305, 306, 307, 308]`.
    * **`healthy.successes`:**  连续多少次健康检查成功才将后端标记为健康。 默认是 `1`.
    * **`unhealthy.interval`:** 当后端被标记为不健康后，健康检查的频率 (秒)。 可以设置比 `interval` 更短的值，更快地检测后端是否恢复健康。
    * **`unhealthy.http_statuses`:** 被视为不健康的 HTTP 状态码列表。 默认是 `[400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 421, 422, 423, 424, 425, 426, 428, 429, 431, 451, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 520, 521, 522, 523, 524, 525, 526, 527, 530]`.
    * **`unhealthy.failures`:** 连续多少次健康检查失败才将后端标记为不健康。 默认是 `3`.
    * **`unhealthy.tcp_failures`:** 连续多少次 TCP 连接失败才将后端标记为不健康。 默认是 `3`.
    * **`path` (HTTP 健康检查):**  HTTP 健康检查请求的路径。 默认是 `/`.
    * **`host` (HTTP 健康检查):**  HTTP 健康检查请求的 Host Header。 默认是 Upstream Service 的主机名。
    * **`port` (TCP 健康检查):** TCP 健康检查的端口。 默认是 Upstream Service 的端口。

**2. 被动健康检查 (Passive Health Checks)**

* **工作原理:**  Kong 不会主动发送健康检查请求。 它会根据实际的用户请求流量和后端响应来被动地判断后端是否健康。
* **基于请求失败:** 当 Kong 向后端发送用户请求并收到错误响应 (例如 connection refused, timeout, 5xx 错误) 时，会将后端标记为不健康。
* **基于请求成功:** 当 Kong 向后端发送用户请求并收到成功响应 (例如 2xx, 3xx) 时，会将后端标记为健康。
* **配置选项 (部分重要选项):**
    * **`type`:** 健康检查类型，设置为 `passive`.
    * **`healthy.http_statuses`:**  被视为健康的 HTTP 状态码列表 (同主动健康检查).
    * **`unhealthy.http_statuses`:** 被视为不健康的 HTTP 状态码列表 (同主动健康检查).
    * **`unhealthy.tcp_failures`:**  连续多少次 TCP 连接失败才将后端标记为不健康 (同主动健康检查).
    * **`timeouts.tcp`:**  TCP 连接超时时间 (秒)。
    * **`timeouts.http`:**  HTTP 请求超时时间 (秒)。

**Kong 如何判断 GKE RT SVC 后端的存活?**

在你的架构中，Kong 是配置为路由到 GKE RT 的 SVC (`gke-rt-svc`)。  这意味着：

* **Kong 的健康检查目标是 SVC 的 endpoints:**  Kong 实际上并不知道 SVC 后端具体的 Pods 实例。 Kong 的健康检查是针对 SVC 解析到的 **endpoints** 进行的。  Kubernetes Service 会维护一个 endpoints 列表，其中包含了 Ready 状态的 Pods 的 IP 地址和端口。
* **SVC endpoints 的更新与 Pod Readiness Probe:**  GKE 控制平面 (kube-controller-manager) 会根据 Deployment 中 Pod 的 `readinessProbe` 的结果来更新 SVC 的 endpoints 列表。 只有 `readinessProbe` 返回成功的 Pod 才会加入到 SVC 的 endpoints 列表中。
* **Kong 的健康检查和 SVC endpoints 的联动:**
    1. **Pod 不健康 (Readiness Probe 失败):**  如果 GKE RT 的一个 Pod 的 `readinessProbe` 失败，Kubernetes 会将该 Pod 从 `gke-rt-svc` 的 endpoints 列表中移除。
    2. **Kong 健康检查发现 endpoint 不健康:**
        * **主动健康检查:**  如果 Kong 配置了主动健康检查，它会定期探测 `gke-rt-svc` 的 endpoints。  当 Pod 从 endpoints 移除后，Kong 的健康检查探测可能会失败 (例如连接超时或 HTTP 状态码错误)。
        * **被动健康检查:**  当用户请求被 Kong 路由到已经被从 SVC endpoints 移除的 Pod (如果还有残留连接或短暂的延迟)，可能会遇到连接错误或 5xx 错误，触发 Kong 的被动健康检查。
    3. **Kong 标记后端不健康并停止路由:**  无论通过主动还是被动健康检查，一旦 Kong 判断某个 SVC endpoint 不健康，它会将该 endpoint 标记为 "down" (不健康)，并停止将新的请求路由到该 endpoint。
    4. **Kong 重新探测并恢复健康:**  Kong 会继续按照配置的频率进行健康检查。 当 Kubernetes 替换不健康的 Pod，新的 Pod `readinessProbe` 通过并加入到 `gke-rt-svc` 的 endpoints 列表后，Kong 的健康检查可能会再次成功，将该 endpoint 标记为 "up" (健康)，并重新开始路由流量。

**配置 Kong 健康检查示例 (Declarative Configuration):**

```yaml
services:
- name: gke-rt-service
  url: "http://gke-rt-svc:80" # 指向你的 GKE Service
  healthchecks: # 健康检查配置
    active: # 主动健康检查
      type: http # HTTP 健康检查
      interval: 10 # 每 10 秒检查一次
      timeout: 3 # 超时时间 3 秒
      http_path: "/health" # 健康检查路径
      http_statuses: [200] # 只有 200 状态码被认为是健康
      healthy:
        interval: 60 # 健康后，每 60 秒检查一次
        successes: 1 # 连续 1 次成功即标记为健康
      unhealthy:
        interval: 5 # 不健康后，每 5 秒检查一次
        failures: 3 # 连续 3 次失败即标记为不健康
    passive: # 被动健康检查
      type: passive
      healthy:
        http_statuses: [200, 201, 202, 203] # 这些状态码被认为是健康
      unhealthy:
        http_statuses: [500, 502, 503, 504] # 这些状态码被认为是不健康
        tcp_failures: 3 # 连续 3 次 TCP 连接失败也认为不健康
```

**配置 Kong 健康检查示例 (Kong Admin API, 例如 `curl`):**

```bash
# 更新 Service 配置，添加健康检查
curl -i -X PATCH http://kong-admin:8001/services/{service_id} \
  --data "healthchecks.active.type=http" \
  --data "healthchecks.active.interval=10" \
  --data "healthchecks.active.timeout=3" \
  --data "healthchecks.active.http_path=/health" \
  --data "healthchecks.active.http_statuses=200" \
  --data "healthchecks.active.healthy.interval=60" \
  --data "healthchecks.active.healthy.successes=1" \
  --data "healthchecks.active.unhealthy.interval=5" \
  --data "healthchecks.active.unhealthy.failures=3" \
  --data "healthchecks.passive.type=passive" \
  --data "healthchecks.passive.healthy.http_statuses=200,201,202,203" \
  --data "healthchecks.passive.unhealthy.http_statuses=500,502,503,504" \
  --data "healthchecks.passive.unhealthy.tcp_failures=3"
```

**关键点总结:**

* **Kong 确实有后端健康检查机制，包括主动和被动两种类型。**
* **Kong 健康检查的目标是 Upstream Service 的后端地址，在你的场景中是 GKE RT SVC 的 endpoints。**
* **Kong 的健康检查与 GKE RT Pod 的 Readiness Probe 协同工作，共同确保服务的高可用性。**  Readiness Probe 决定 Pod 是否加入 SVC endpoints，Kong 健康检查决定哪些 SVC endpoints (代表后端的 Pods) Kong 认为是健康的并路由流量。
* **合理配置 Kong 的健康检查参数 (例如 interval, timeout, healthy/unhealthy thresholds, HTTP 状态码等) 非常重要，以确保 Kong 能够及时准确地判断后端健康状态，并做出正确的路由决策。**

通过配置 Kong 的健康检查，你可以提高你的 GKE 工程的整体可用性，让 Kong 能够智能地避开不健康的 GKE RT 后端实例，并将流量路由到健康的实例，从而减少用户遇到的错误，并提升用户体验。