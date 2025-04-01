你的流量路径如下：

用户请求 -> A(7层Nginx) -> B(4层Nginx) -> C(Kong DP) -> D(GKE RT)

你的问题可以拆分成几个关键点：
	1.	经过多个 LB（多层负载均衡）后，流量如何确保均匀分布到 8 个 Pod？
	2.	连接复用（Keep-Alive）是否会导致负载不均？
	3.	在哪一层应该关注负载均衡算法？
	4.	最佳实践方案有哪些？

⸻

1. 多层 LB 负载均衡的挑战

你的架构涉及多个负载均衡器：
	•	A (7层Nginx) 负责 HTTP 处理和路由（可能使用 proxy_pass 方式转发）
	•	B (4层Nginx) 负责 TCP 连接的跨网络转发
	•	C (Kong DP) 作为 API Gateway
	•	D (GKE RT) 作为最终业务 Pod 运行层

当流量层层经过多个 LB 时，负载均衡可能受到以下因素影响：
	•	连接复用：HTTP/1.1、HTTP/2 的 Keep-Alive 可能导致长连接请求固定在某些后端 Pod 上，而不是均匀分布。
	•	会话粘性（Sticky Session）可能让部分请求始终命中同一后端。
	•	不均衡的 Hash 负载策略：某些层的 LB 可能默认使用 Source IP Hash，这可能会导致不均衡流量分布。
	•	TCP 连接池：部分 Nginx 层可能会复用 TCP 连接到固定的后端，导致流量集中。

⸻

2. 负载均衡的策略分析

你需要在 每一层 关注负载均衡算法，并合理选择策略：

A (7层Nginx - L7 LB)
	•	你可以在 nginx.conf 里配置 proxy_pass 时使用 轮询（round-robin） 或 least_conn（最少连接）。
	•	确保 keepalive_requests 和 keepalive_timeout 合理，以防止连接长时间绑定某些后端。

示例：

upstream backend {
    least_conn;
    server B1;
    server B2;
    keepalive 32;
}

server {
    location / {
        proxy_pass http://backend;
        proxy_set_header Connection "";
    }
}

建议：
	•	使用 least_conn 或 round-robin，避免 ip_hash（会导致部分 Pod 负载过高）。
	•	短连接超时（keepalive_timeout 10s ），减少连接固定到某些后端。

⸻

B (4层Nginx - L4 LB)
	•	由于 B 仅仅是 TCP 代理，它不会解析 HTTP 头部，而是直接转发 TCP 连接，因此负载均衡策略主要依赖 stream 模块的 least_conn 或 round-robin。
	•	需要注意 TCP 连接复用，如果 B 复用了一些连接到 Kong DP，可能会导致部分 Kong DP 处理更多流量。

示例：

stream {
    upstream kong_nodes {
        least_conn;
        server C1:8000;
        server C2:8000;
    }

    server {
        listen 443;
        proxy_pass kong_nodes;
        proxy_timeout 10s;
        proxy_connect_timeout 5s;
    }
}

建议：
	•	使用 least_conn，确保新连接尽可能均匀分布。
	•	短连接超时 proxy_timeout 10s，防止 TCP 连接长时间绑定到单个 Kong 实例。

⸻

C (Kong DP - API Gateway)
	•	Kong 的默认负载均衡策略是 round-robin，但你可以自定义。
	•	Kong 也会复用连接池，因此如果 Kong 长时间连接到同一后端 GKE SVC，则负载可能会集中在某些 Pod 上。
	•	你可以在 Kong 配置 balancer.strategy 选项：
	•	round-robin
	•	least-connections
	•	consistent-hashing

示例：

upstream:
  name: my-gke-service
  algorithm: least-connections

建议：
	•	使用 least-connections，减少连接集中到单个 Pod
	•	调整 keepalive 以防止 Kong 过度绑定某些 Pod
	•	避免 ip_hash 负载策略，可能导致部分 Pod 负载不均。

⸻

D (GKE RT - Kubernetes Service)

Kubernetes Service 默认采用 iptables 或 IPVS 进行负载均衡：
	•	ClusterIP：基于 iptables 规则，默认是 random 轮询。
	•	IPVS 模式：如果启用了 kube-proxy 的 ipvs，可以支持 rr（round-robin） 或 least-conn。
	•	HPA：如果 GKE RT 有 HPA 扩展，Pod 可能会动态变化，需要负载均衡能适应。

你可以检查 kube-proxy 的模式：

kubectl logs -n kube-system kube-proxy-xxxx

如果是 iptables，建议改用 ipvs：

kubectl edit configmap -n kube-system kube-proxy

修改：

mode: "ipvs"

建议：
	•	使用 IPVS，配置 rr 或 least-conn
	•	确保 kube-proxy 使用 ipvs 而不是 iptables
	•	使用 HPA 确保 Pod 可以弹性扩展

⸻

3. 最佳实践方案

方案 1：优化 LB 层的连接复用
	•	Nginx (A/B) 使用 least_conn 代替 round-robin
	•	调整 keepalive_timeout 让连接超时，减少连接固定
	•	Kong DP 负载均衡使用 least-connections

方案 2：优化 Kubernetes Service
	•	确保 kube-proxy 使用 IPVS
	•	调整 keepalive_requests 和 keepalive_timeout
	•	GKE RT 采用 readinessProbe 确保新 Pod 只有在准备好时才接受流量

⸻

4. 负载均衡算法的关注点

组件	负载均衡策略	关键优化点
A (7层Nginx)	least_conn or round-robin	确保 Keep-Alive 不固定到某些 B 实例
B (4层Nginx)	least_conn	避免 TCP 长连接绑定到单一 Kong DP
C (Kong DP)	least-connections	避免 Kong 复用连接过度集中在某些 Pod
D (GKE RT)	IPVS (rr or least-conn)	确保 kube-proxy 采用 IPVS



⸻

总结

你需要在 每一层 关注负载均衡策略：
	1.	Nginx (A/B) 使用 least_conn，减少 Keep-Alive 影响
	2.	Kong 采用 least-connections，避免长连接固定
	3.	GKE RT 确保 IPVS 负载均衡模式
	4.	优化 keepalive_timeout，减少连接绑定问题

最终，你需要在 GKE RT（K8S Service） 这个层级确认流量是否真正均匀分布，可用 kubectl top pod 检查 CPU/MEM 使用情况。





如何确认 GKE RT（K8S Service） 层级的流量负载均衡情况

在 GKE RT 这一层，我们的目标是确保流量均匀地分布到 8 个 Pod 上。由于 Kubernetes Service 默认使用 kube-proxy 进行负载均衡，我们需要验证它的工作情况，并找到合适的方法来观测流量分布。

⸻

1. 如何查看 K8S Service 采用的默认负载均衡算法？

(1) Kubernetes Service 的负载均衡方式

GKE（Kubernetes）默认的 Service 负载均衡方式有两种：
	•	基于 iptables（默认方式）：随机选择一个 Pod，连接建立后不会变更后端 Pod。
	•	基于 IPVS（推荐方式）：可以支持 round-robin、least-conn 等策略。

(2) 检查当前 kube-proxy 使用的模式

kubectl get configmap -n kube-system kube-proxy -o yaml | grep "mode:"

如果返回：
	•	mode: "iptables"（默认方式）
	•	mode: "ipvs"（更好的方式）

如果是 iptables，GKE Service 的负载均衡是随机（random）的，并且连接一旦建立，就会固定到某个 Pod，直到连接断开。这种方式对于短连接（HTTP 请求）较为均匀，但对于长连接（如 HTTP/2、gRPC）可能导致部分 Pod 负载过重。

⸻

2. 如何确认流量是否均匀分布？

(1) 使用 kubectl top pod 观察 CPU/MEM

你可以用 kubectl top pod 检查 Pod 之间的 CPU 和内存使用情况，判断负载是否均匀：

kubectl top pod -n <namespace>

示例输出：

NAME           CPU(cores)   MEMORY(bytes)
pod-1         50m          200Mi
pod-2         450m         500Mi
pod-3         60m          210Mi
pod-4         30m          190Mi
pod-5         20m          180Mi
pod-6         70m          220Mi
pod-7         40m          190Mi
pod-8         50m          200Mi

	•	如果某个 Pod 负载明显高于其他 Pod（如 pod-2 远高于其他），说明流量分布不均。
	•	如果所有 Pod 负载相近，则说明流量是均匀分布的。

⸻

(2) 使用 kubectl get endpoints 确认后端 Pod

Kubernetes Service 通过 Endpoints 绑定到 Pod。你可以查看 Service 绑定的 Pod：

kubectl get endpoints <your-service> -n <namespace> -o wide

示例输出：

NAME          ENDPOINTS                                      AGE
my-service    10.0.0.1:8080,10.0.0.2:8080,10.0.0.3:8080     10d

	•	确保所有 Pod 都在 ENDPOINTS 列表中，否则可能有些 Pod 没有接收流量。

⸻

(3) 使用 kubectl logs 检查 Pod 访问情况

如果你的应用日志中有请求日志，你可以检查不同 Pod 是否都收到了类似数量的请求：

kubectl logs -n <namespace> -l app=my-app --tail=50 | grep "Request received"

如果部分 Pod 的日志比其他 Pod 明显少，可能意味着流量不均衡。

⸻

(4) 使用 kubectl port-forward 直接测试流量分布

你可以手动从本地发请求，查看是否能轮询到不同的 Pod：

kubectl port-forward svc/<your-service> 8080:80 -n <namespace>

然后在本地运行：

for i in {1..10}; do curl http://localhost:8080; done

	•	如果每次请求返回的 Pod 名字不同，则表明负载均衡有效。
	•	如果请求总是命中相同的 Pod，可能是 kube-proxy 没有正确均衡。

⸻

3. 如何优化 GKE Service 的负载均衡？

如果 kubectl top pod 发现流量不均衡，你可以考虑以下优化方式：

(1) 切换 kube-proxy 为 IPVS

如果 kube-proxy 采用 iptables，你可以切换到 IPVS，使其支持 round-robin 负载均衡：

kubectl edit configmap -n kube-system kube-proxy

修改：

mode: "ipvs"

然后重启 kube-proxy：

kubectl delete pod -n kube-system -l k8s-app=kube-proxy



⸻

(2) 调整 sessionAffinity 选项

如果你的 Service 默认使用 None，那么它会随机分配流量。如果你发现某些 Pod 负载过高，可能是因为 sessionAffinity 绑定了请求到某些 Pod。你可以检查 Service 配置：

kubectl get svc <your-service> -o yaml

如果 sessionAffinity: ClientIP，则可能是部分客户端的流量固定到了某些 Pod。你可以修改：

kubectl patch svc <your-service> -p '{"spec": {"sessionAffinity": "None"}}'



⸻

(3) 确保 readinessProbe 配置正确

如果有些 Pod 的 readinessProbe 配置错误，可能会导致 Service 不会将流量分配到这些 Pod。你可以检查：

kubectl get pod -o wide

如果发现某些 Pod 状态是 NotReady，说明它们没有被 Service 使用，你需要修正 readinessProbe 配置。

⸻

(4) 使用 HPA 进行自动扩展

如果流量经常不均衡，考虑使用 Horizontal Pod Autoscaler (HPA) 自动扩展 Pod：

kubectl autoscale deployment my-deployment --cpu-percent=50 --min=4 --max=16

这样，当某些 Pod 负载过高时，系统会自动增加 Pod 来均衡负载。

⸻

4. 结论

方法	作用
kubectl top pod	检查 Pod 的 CPU/MEM 负载情况
kubectl get endpoints	确保 Service 绑定了所有 Pod
kubectl logs	观察请求是否均匀分布在不同 Pod
kubectl port-forward	本地测试流量是否正确轮询不同 Pod
切换 kube-proxy 为 IPVS	使 Service 负载均衡更均匀
关闭 sessionAffinity	避免流量绑定到某些 Pod
调整 readinessProbe	确保所有 Pod 都可以接收流量
使用 HPA 进行扩展	根据负载动态增加 Pod

你可以先用 kubectl top pod 确认流量是否均衡，如果发现问题，再逐步优化 Service 负载均衡配置。