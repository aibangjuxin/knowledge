# Reference
https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-multi-cluster-gateways?hl=zh-cn#blue-green




# Step
## 启用多集群 Gateway 
[启用多集群 Gateway](https://cloud.google.com/kubernetes-engine/docs/how-to/enabling-multi-cluster-gateways?hl=zh-cn)
https://cloud.google.com/kubernetes-engine/docs/how-to/enabling-multi-cluster-gateways?hl=zh-cn


在舰队中启用多集群 Gateway
https://cloud.google.com/kubernetes-engine/docs/how-to/enabling-multi-cluster-gateways?hl=zh-cn#enable_multi-cluster_gateway_in_the_fleet


多集群 Gateway 要求
除了 GKE Gateway Controller 要求之外，对于多集群 Gateway 部署，请确保您已执行以下任务：

在配置集群上启用 Gateway API。
在集群上启用 GKE 的工作负载身份联合。
完成关于注册集群的舰队常规前提条件。
在项目中启用以下多集群 Gateway 所需的 API：

- Traffic Director API
    Traffic Director 用作后端基础架构，负责传播多集群 Service 的端点，但 MCS 控制器创建的 Traffic Director 资源不会计入您的项目费用，因为 MCS 包含在 GKE 的费用中。
- Multi-cluster Services API
- Multi Cluster Ingress API
运行以下命令可启用所需的 API（如果尚未启用）：
```bash
gcloud services enable \
  trafficdirector.googleapis.com \
  multiclusterservicediscovery.googleapis.com \
  multiclusteringress.googleapis.com \
  --project=PROJECT_ID
```
将 PROJECT_ID 替换为在其中运行 GKE 集群的项目的 ID。

## 部署多集群 Gateway 
[部署多集群 Gateway](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-multi-cluster-gateways?hl=zh-cn)


[多集群 Gateway](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-multi-cluster-gateways?hl=zh-cn#multi-cluster-gateway)
多集群 Gateway 是一种 Gateway 资源，用于跨多个 Kubernetes 集群进行流量负载均衡。在 GKE 中，gke-l7-global-external-managed-mc、gke-l7-regional-external-managed-mc、gke-l7-rilb-mc 和 gke-l7-gxlb-mc GatewayClass 会部署多集群 Gateway，这些 Gateway 跨不同 GKE 集群、Kubernetes 命名空间和不同区域提供 HTTP 路由、流量分配、流量镜像、基于健康状况的故障切换等。通过多集群 Gateway，基础架构管理员能够跨多个集群和团队轻松、安全、可扩缩地管理应用网络。

本页面介绍了三个示例，教您如何使用 GKE Gateway Controller 控制器部署多集群 Gateway：

示例 1：外部多集群 Gateway，用于跨两个 GKE 集群为互联网流量提供负载均衡。
示例 2：跨两个 GKE 集群对内部 VPC 流量进行基于权重的蓝绿流量分配和流量镜像。
示例 3：基于容量的 Gateway，用于根据后端的最大容量为发往不同后端的请求提供负载均衡。
### 使用 Gateway 进行蓝绿多集群路由 
[使用 Gateway 进行蓝绿多集群路由](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-multi-cluster-gateways?hl=zh-cn#blue-green)
Explorer 
示例 2：跨两个 GKE 集群对内部 VPC 流量进行基于权重的蓝绿流量分配和流量镜像

使用 Gateway 进行蓝绿多集群路由
跨两个 GKE 集群对内部 VPC 流量进行基于权重的蓝绿流量分配和流量镜像
https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-multi-cluster-gateways?hl=zh-cn#blue-green



