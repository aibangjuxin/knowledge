https://cloud.google.com/wiz?hl=en#see-and-secure-every-workload-with-wiz-on-google-cloud

https://console.cloud.google.com/marketplace/product/wiz-public/wiz-gcp-marketplace?project=gen-lang-client-0775319228


https://app.wiz.io/login?redirect=%2Fdocs%2Fkubernets-connectors


https://docs.wiz.io/docs/kubernetes-connectors#required-access-and-permissions


https://cloud.google.com/architecture/partners/id-prioritize-security-risks-with-wiz


wiz capabilities available to My project 

# summary 
 - 需要评估模式选择
	 - **仅API扫描** 和 **启用Runtime Sensor** 两种模式
	 - Wiz 是一款**无代理（agentless）**的云安全平台，它通过读取云环境 API（如 GCP/GKE）来扫描整个云架构，而无需在主机或容器内安装代理。同时，它也支持在 GKE 集群部署**轻量级 sensor（Runtime Sensor）**以提供运行时监控
- 在 GKE 中的应用：扫描会覆盖 GKE 集群的镜像仓库（如 Artifact Registry），检查 deployment 中的容器镜像。无需代理，所以对性能影响最小
- Wiz 通过云 API（而非直接登录节点）读取 Kubernetes 资源、配置、镜像信息等，如果控制平面是**完全私有**的，Wiz 可能无法直接访问。
- 对于开启 **私有集群** 的情况，需通过 **VPC Peering、Private Service Connect** 或 **代理（如 Cloud NAT + Proxy Pod）** 提供访问路径
- 如果允许公共端点访问
	- 通过 **Master Authorized Networks** 限制 Wiz 出站 IP，安全性更高。
	- 减少 Sensor 部署需求，降低 DaemonSet 维护成本
- Our Status GKE  is private network 


- Need to evaluate mode selection  
	- Two available modes: **Only API Scan** and **Enable Runtime Sensor**  
	- Wiz is an **agentless** cloud security platform. It scans the entire cloud architecture by reading cloud environment APIs (such as GCP/GKE), without requiring the installation of agents on hosts or containers. Additionally, Wiz supports deploying a **lightweight sensor (Runtime Sensor)** within GKE clusters to provide real-time monitoring.  
-  In GKE use case:  
	  - Scans cover GKE cluster image repositories (e.g., Artifact Registry) and inspect container images in Deployments.  No agents are required, resulting in minimal performance impact.  
-  Wiz reads Kubernetes resources, configurations, and image information via cloud APIs—rather than directly logging into nodes.  
  - If the control plane is **fully private**, Wiz may not be able to access it directly.  
-  For **private clusters**:  
  - Access must be provided via **VPC Peering**, **Private Service Connect**, or **proxy solutions** (such as Cloud NAT + Proxy Pod).  
-  If public endpoints are allowed:  
	  - Restrict Wiz’s outbound IP addresses using **Master Authorized Networks**—this enhances security.  
	  - Reduces the need for Runtime Sensor deployment, thereby lowering the operational overhead of maintaining DaemonSet pods.  

---




- (1) 搜寻关于Wiz安全工具的总体介绍，包括其核心功能、主要优势以及在云安全领域的定位。 
- (2) 查找Wiz与Google Cloud Platform (GCP) 集成的官方文档和技术指南，了解在GCP环境中部署Wiz的先决条件和标准连接流程。 
- (3) 深入研究Wiz针对Google Kubernetes Engine (GKE) 的具体应用方法，包括如何扫描GKE集群、Deployments以及容器镜像的安全状况。 
- (4) 详细分析Wiz无代理扫描（Agentless Scanning）的工作原理，并列出它在GCP和GKE环境中能够收集到的具体信息类型，例如漏洞、配置错误、网络暴露和敏感数据等。 
- (5) 详细分析Wiz运行时传感器（Runtime Sensor）的功能和部署方式，特别是如何在GKE集群中部署该传感器，以及它能监控哪些实时活动。 
- (6) 综合比较无代理扫描和运行时传感器在部署方式、资源占用、扫描范围（静态分析 vs. 动态监控）以及能够检测的安全威胁类型上的具体区别。 
- (7) 调查Wiz提供的API接口及其功能，研究如何通过API调用来自动化执行扫描任务和获取扫描结果。 
- (8) 寻找将Wiz集成到CI/CD流水线（pipeline）中的最佳实践或案例，了解如何在开发和部署流程中实现自动化的安全扫描。