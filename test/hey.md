hey 是一个非常流行、轻量级的 HTTP 负载测试工具，是用 Go 语言编写的。可以把它看作是现代版的 Apache Bench (ab)，但它的输出更直观，参数也更人性化。
针对你在 GKE 环境下的需求，以下是关于 hey 的详细资料、镜像来源以及实用的操作文档。
1. 镜像来源与获取
虽然 hey 是开源软件，但官方作者并没有维护一个“官方”Docker 镜像。社区中最常用、最稳定的是由 williamyeh 构建的版本。
 * 镜像名称: williamyeh/hey
 * Docker Hub 地址: https://hub.docker.com/r/williamyeh/hey
 * 特点: 极小（基于 Alpine Linux，仅几 MB），非常适合在 Kubernetes 中作为临时 Pod 快速拉起。
2. 核心参数速查表 (Cheat Sheet)
在使用 kubectl run 启动它之前，你需要了解以下几个核心参数，这对评估资源消耗至关重要：
| 参数 | 全称 | 作用 | 适用场景 |
|---|---|---|---|
| -z | Duration | 压测时长 (如 5m, 30s)。 | 推荐。用于观察内存/CPU在一段时间内的稳定性。 |
| -n | Number | 请求总数 (如 10000)。 | 用于测试完成特定数量请求后的最终资源状态。 |
| -c | Concurrency | 并发连接数。默认为 50。 | 模拟多少个用户同时在用。测试 AppD 时建议设为 10-50。 |
| -q | QPS Limit | 每秒请求速率限制 (Rate Limit)。 | 防止把服务打挂，保持平稳的流量输入。 |
| -m | Method | HTTP 方法 (GET, POST, PUT 等)。 | 默认是 GET。测 API 通常要改 POST。 |
| -d | Data | HTTP Body 数据。 | 发送 JSON 等内容。 |
| -H | Header | 自定义 Header。 | 比如 Content-Type: application/json。 |
| -t | Timeout | 超时时间。 | 默认为 20秒。 |
> 注意： -z (按时间跑) 和 -n (按次数跑) 通常二选一。
> 
3. 在 Kubernetes (GKE) 中的实战用法
你可以直接复制以下命令在你的 GKE 终端运行。
场景 A：简单的 GET 请求（保持 2 分钟压力）
这是最基础的用法，用于让 CPU 和内存动起来。
kubectl run hey-test --rm -i --tty \
  --image=williamyeh/hey \
  --restart=Never \
  -- \
  -z 2m \
  -c 20 \
  http://<你的ServiceIP>:<端口>/<API路径>

场景 B：发送 POST 请求 (带 JSON 数据)
如果你的 API 是业务接口，通常需要 POST 数据。这更能触发 Java 应用的实际业务逻辑，从而让 AppD 采集到更有意义的 Transaction 数据。
# 假设你的 API 需要这样的 JSON: {"userId": "123", "action": "login"}

kubectl run hey-post-test --rm -i --tty \
  --image=williamyeh/hey \
  --restart=Never \
  -- \
  -m POST \
  -H "Content-Type: application/json" \
  -d '{"userId": "123", "action": "login"}' \
  -z 2m \
  -c 10 \
  http://<你的ServiceIP>:<端口>/api/login

4. 结果解读
当 hey 运行结束后，它会输出一份摘要。除了关注 GKE 的资源监控外，你也可以看看这份报告，它能侧面反映 AppD 对性能的影响。
输出示例解读：
Summary:
  Total:	2.0005 secs
  Slowest:	0.1569 secs
  Fastest:	0.0054 secs
  Average:	0.0193 secs   <-- 关注这个：平均响应时间
  Requests/sec:	2498.34   <-- 关注这个：吞吐量 (RPS)

Response time histogram:  <-- 响应时间分布图
  0.005 [1]	|
  0.021 [4832]	|■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.036 [152]	|■
  ...

 * 比较点： 如果带 AppD 的 Pod 平均响应时间是 20ms，而不带 AppD 的是 18ms，说明 AppD 的性能损耗极小，可以忽略不计。
5. 官方文档与源码
如果你想深入了解所有参数，可以访问 GitHub 仓库：
 * GitHub 源码库: https://github.com/rakyll/hey
   (注：原作者 rakyll 是 Google 的工程师，这个工具非常可靠)
Next Step
考虑到你的 API 可能需要认证 (Authentication) 才能访问（比如 Header 里需要带 Token），直接跑上面的命令可能会返回 401 Unauthorized。
你需要我告诉你如何通过 hey 发送带有 Bearer Token 或 Cookie 的请求吗？
