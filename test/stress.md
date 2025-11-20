完全明白，既然你已经在 GKE 环境里，最简单、最快的方法就是利用 Kubernetes 原生命令启动一个临时的“发压容器”。你不需要在本地电脑安装任何软件，也不需要配置复杂的防火墙规则，直接在集群内部打流量。
这里有两套方案：一套是极其简陋但零依赖（用 curl），另一套是推荐的标准做法（用轻量级压测工具 hey 或 ab）。
准备工作：获取目标地址
首先，你要拿到你要测试的那个 Java 应用的 Service IP 或者 Pod IP。
# 获取 Service IP (推荐)
kubectl get svc -n <你的命名空间>

# 或者直接获取 Pod IP
kubectl get pod -o wide -n <你的命名空间>

假设你的应用内部地址是：http://10.100.1.50:8080 (请替换为你实际的 IP 和端口)。
方案一：零依赖极简法 (Shell Loop)
如果你不想拉取任何新镜像，只想简单地让 CPU 动起来，制造一些内存分配，可以在集群的任意一个能连通的 Pod 里（或者直接开一个 busybox）跑个死循环。
操作步骤：
 * 启动一个临时的 curler 容器：
   kubectl run -i --tty load-generator --image=curlimages/curl --restart=Never -- /bin/sh

 * 在进入的终端里，粘贴下面这个循环命令（模拟连续请求）：
   # 替换下面的 URL
while true; do curl -s -o /dev/null http://10.100.1.50:8080/health; done

<!-- end list -->
 * 优点： 只要有 curl 就能跑。
 * 缺点： 单线程，压力非常小，可能看不出明显的 AppD 资源开销差异（因为并发不够高，Agent 的拦截逻辑触发不够密集）。
方案二：推荐法 (使用 hey 工具)
这是我最推荐的方法。hey 是一个用 Go 写的现代 HTTP 压测工具，非常轻量。我们可以通过 kubectl run 直接拉起它，用完即焚。
为什么用这个？ 它可以设置并发（Concurrency），这对于测试 AppD 很重要，因为 Agent 在处理并发请求时 CPU 和内存的 Buffer 占用才会显现出来。
操作步骤：
直接在你的终端运行以下命令（这是一行命令，直接复制修改 URL 即可）：
kubectl run hey-load-test --rm -i --tty \
  --image=williamyeh/hey \
  --restart=Never \
  -- \
  -z 5m \
  -c 10 \
  -q 5 \
  http://10.100.1.50:8080/你的API路径

参数解释：
 * --rm: 测试完自动删除这个 Pod。
 * -z 5m: 持续压测 5分钟（足够你观察内存爬升了）。
 * -c 10: 10个并发连接（模拟10个人同时在用）。
 * -q 5: 限制每个并发每秒请求数（QPS），防止把你服务打挂。
 * http://...: 你的目标应用地址。
方案三：如何一边压测一边“肉眼”观察资源？
在执行上面的压测命令之前，请打开第二个终端窗口，使用 kubectl top 命令进行实时监控。这是最直观的对比方式。
操作指令：
# --containers 可以让你看到 Pod 内部具体的资源分配（如果能区分的话）
# --watch 可以让你像看电影一样看到数字跳动
kubectl top pod -n <你的命名空间> --containers --watch | grep <你的应用关键词>

完整的对比测试流程（SOP）：
 * 窗口 A (监控)： 运行 kubectl top ... --watch。记录下当前的空闲内存（比如 300Mi）。
 * 窗口 B (发压)： 运行上面提到的 方案二 (hey) 命令。
 * 观察窗口 A：
   * 你会看到 CPU 飙升。
   * 你会看到 Memory 缓慢或快速上升。
   * 记录下压测期间的峰值内存（比如 600Mi）。
 * 测试结束后： 看看内存回落到多少。
 * 替换环境： 修改 Deployment 去掉 AppD，重复步骤 1-4。
核心分析逻辑
 * Δ (Delta) = (有 AppD 的峰值内存) - (无 AppD 的峰值内存)
 * 这个 Δ 就是你要找的答案。通常 AppD 需要额外的 Buffer 来处理这 10 个并发产生的 Metrics，这部分开销只有在有流量时才会暴露。
Next Step
你想让我基于 kubectl top 的输出逻辑，帮你写一个简单的 Shell 脚本 吗？它可以自动每隔 5 秒把内存数据记录到一个文件里，方便你最后做图表对比，而不用一直盯着屏幕看。
