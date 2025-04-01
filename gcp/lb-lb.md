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