# TODO
- tls and secret 
- dns fqdn 
- curl health 
- API dependency
- network Policy
# K8s 集群资源迁移后验证清单

本文档旨在提供一个清晰的验证清单，用于在将 Kubernetes 资源从一个集群迁移到另一个集群后，确保所有服务按预期工作。迁移的核心改动点在于 Ingress 层的域名和证书，而工作负载（Deployment 等）本身保持不变。

## 验证核心思路

验证流程应遵循从外到内、逐层深入的原则：

1.  **外部入口**：验证域名解析、TLS 证书和 Ingress 路由规则。
2.  **服务连接**：验证 Ingress 是否能正确将流量转发到对应的 Service。
3.  **核心应用**：验证 Deployment 和 Pod 是否正常运行，应用日志是否无异常。
4.  **配置与依赖**：验证 ConfigMap、Secret 等配置是否正确加载，以及服务间的依赖是否正常。

---

## 详细验证点列表
### 
### **0. 基础资源**

- **Namespace**：确认新集群中已创建对应的 namespace，资源落在正确的 namespace 下。
    
- **Resource Quota / LimitRange**：是否需要迁移或调整，避免因限制导致 Pod 启动失败。
    
- **RBAC（ServiceAccount / Role / RoleBinding）**：权限是否完整迁移，Pod 能否正常访问所需的 AP

### 1. 入口层 (Ingress) 验证

这是本次迁移改动的核心，需要重点验证。

-   [ ] **DNS 解析验证**
    -   确认新的域名已正确解析到新集群 Ingress Controller 的 LoadBalancer IP。
    -   **方法**：使用 `dig <新域名>` 或 `nslookup <新域名>` 命令检查返回的 IP 地址。

-   [ ] **TLS/SSL 证书验证**
    -   确认新域名使用了正确的 TLS 证书。
    -   **方法 1**：通过浏览器访问 `https://<新域名>`，检查证书的颁发者、有效期和使用者名称 (Subject Alternative Name)。
    -   **方法 2**：使用 `openssl` 命令检查证书详情：`openssl s_client -connect <新域名>:443 -servername <新域名>`。
    -   **方法 3**：在 K8s 中检查 Ingress 资源引用的 Secret 是否存在且内容正确：`kubectl get secret <证书secret名称> -n <命名空间> -o yaml`。

-   [ ] **Ingress 路由规则验证**
    -   确认 Ingress 规则中的 `host` 和 `path` 配置正确，并且 `serviceName` 指向了正确的后端 Service。
    -   **方法**：`kubectl get ingress <ingress名称> -n <命名空间> -o yaml`，仔细检查 `rules` 和 `backend` 部分。

-   [ ] **HTTP/HTTPS 连通性验证**
    -   确认可以通过新域名访问到服务，并且 HTTP 到 HTTPS 的重定向（如果配置了）工作正常。
    -   **方法**：使用 `curl -vL http://<新域名>` 和 `curl -vL https://<新域名>`，检查响应状态码和返回内容。

### 2. 服务层 (Service) 验证

-   [ ] **Service 与 Pod 端点 (Endpoint) 关联验证**
    -   确认 Service 能够正确关联到后端的 Pod。
    -   **方法**：`kubectl describe service <service名称> -n <命名空间>`，检查 `Endpoints` 字段是否有正确的 Pod IP 列表。如果为空，说明 Service 的 `selector` 可能与 Deployment 的 `labels` 不匹配。

### 3. 工作负载层 (Deployment/Pod) 验证

尽管这部分未作改动，但在新环境中仍需确认其健康状态。

-   [ ] **Pod 状态验证**
    -   确认所有 Pod 都处于 `Running` 状态，没有 `CrashLoopBackOff`、`ImagePullBackOff` 或 `Error` 等异常状态。
    -   **方法**：`kubectl get pods -n <命名空间> -o wide`。

-   [ ] **应用日志验证**
    -   检查 Pod 的启动日志和运行时日志，确认应用本身没有因为环境变化（如网络策略、依赖服务地址等）而出现错误。
    -   **方法**：`kubectl logs <pod名称> -n <命名空间>`，可以加上 `-f` 参数实时查看。

### 4. 配置与依赖验证

-   [ ] **ConfigMap 验证**
    -   确认 ConfigMap 已被正确迁移，并且 Pod 成功加载了这些配置（作为环境变量或卷挂载）。
    -   **方法**：
        -   检查环境变量：`kubectl exec -it <pod名称> -n <命名空间> -- env`。
        -   检查挂载文件：`kubectl exec -it <pod名称> -n <命名空间> -- cat /path/to/config/file`。

-   [ ] **Secret 验证**
    -   确认 Secret（除证书外，如数据库密码、API Key 等）已正确迁移并被 Pod 加载。
    -   **方法**：与 ConfigMap 类似，通过 `exec` 进入 Pod 内部检查应用是否能读取到对应的 Secret 值（注意不要直接在日志中打印 Secret 内容）。

-   [ ] **服务间依赖验证**
    -   如果应用依赖其他内部服务，需要确认服务发现机制（K8s DNS）在新集群中工作正常。
    -   **方法**：`kubectl exec -it <pod名称> -n <命名空间> -- curl http://<依赖服务名称>.<命名空间>.svc.cluster.local`。

-   [ ] **持久化存储 (PersistentVolume) 验证 (如果涉及)**
    -   如果应用是状态服务，需要确认 PersistentVolumeClaim (PVC) 是否已成功绑定到新的 PersistentVolume (PV)。
    -   **方法**：`kubectl get pvc -n <命名空间>`，检查 `STATUS` 是否为 `Bound`。

### 5. 网络策略验证

-   [ ] **NetworkPolicy 验证**
    -   如果旧集群中定义了网络策略，需要确认它们已被迁移，并且没有错误地阻止 Ingress Controller 或其他合法流量访问 Pod。
    -   **方法**：`kubectl get networkpolicy -n <命名空间>`，检查策略规则是否适用于新集群的网络环境。可以临时删除策略进行测试，以判断是否是策略导致的问题。

---
