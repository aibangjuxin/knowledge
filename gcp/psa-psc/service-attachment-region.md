https://docs.cloud.google.com/sdk/gcloud/reference/compute/service-attachments/create

用于创建服务附加组件。服务提供者创建服务附加组件，使服务可供消费者使用。服务消费者使用私有服务连接端点将流量私下转发到服务附加组件。

## 深度探索：Service Attachment 的暴露方式与前提条件

按照官方 API 和命令行的定义（正如上面的 `gcloud` 链接所示），Private Service Connect (PSC) **Service Attachment 的底层物理目标永远且只有一个：那就是内部负载均衡器的前端关联规则（Forwarding Rule）**。

但在实际的云原生架构和工程部署中，我们作为服务提供方（Producer）会根据业务部署形态的不同，看到**两种截然不同的暴露资源和操作路径**：

### 1. IaaS 层 / 原生暴露方式：直接对接 Forwarding Rule
这是一种基础设施层面的基础发布方式。当你的业务跑在虚拟机 (GCE)、代管实例组 (MIG) 或直接自己维护的传统负载均衡器后方时，你会直接和 Forwarding Rule 打交道。

**前置创建条件与步骤：**
要在这种模式下成功暴露出 PSC 服务，必须严格按照以下顺序满足前提：
1. **就绪的后端 (Backend)**：你必须有一个承载实际服务的后端，比如 Zonal NEG 或 Region backend service。
2. **专属的内部负载均衡器 (ILB)**：你必须前置创建一个区域级的内部负载均衡器（可以是 L7 Internal ALB，或者是 L4 Internal Proxy / Passthrough NLB）。
    *   **最容易踩坑的条件**：这个负载均衡器的 `load_balancing_scheme` 必须是 `INTERNAL` 或 `INTERNAL_MANAGED`。它绝不能是全局的或外部的。
    *   **连通性条件**：如果你希望消费方（Consumer）能从其他 Region 跨区访问（或者像你之前报错那样被 Global ALB 消费），那么在创建这个 ILB 的 Forwarding Rule 时，**必须加上 `--allow-global-access` (开启全局访问)**，否则默认情况下只允许同 Region 访问。
3. **分配 PSC NAT 子网**：在 LB 所在的同一 VPC 和 Region 下，必须创建一个用途标记为 `--purpose=PRIVATE_SERVICE_CONNECT` 的专用子网。
4. **绑定规则**：最后，你才能使用 `gcloud compute service-attachments create` 命令，通过 `--producer-forwarding-rule` 参数将上方创建的规则与 NAT 子网组合在一起，完成最终的服务暴露。

---

### 2. PaaS 层 / 云原生暴露方式：基于 GKE 的抽象资源 (GKE Gateway / Service)
在现代架构中，如果你的业务跑在 GKE 集群里，你通常**不需要也不应该**去直接用 `gcloud` 手工敲击命令创建那条底层的 Forwarding Rule。GCP 提供了一套由 Kubernetes 控制器自动代管的云原生方案。

在这个场景中，你看到的暴露手段变成了 Kubernetes 的 YAML 资源（如 `Service` 和 `Gateway`），由 GKE 的 Cloud Controller Manager 在后台帮你“组装”上述的第一种模式。

**前置创建条件与抽象步骤：**
在这种模式下，你需要满足的是 Kubernetes 层面的抽象环境要求：
1. **集群网络要求**：必须是一个启用了 VPC 原生路由 (VPC-native) 的 GKE 集群。
2. **提前准备 PSC NAT 子网**：虽然很多东西可以自动化，但作为基础设施的 PSC NAT 子网依然需要提前在 GCP VPC 内划分好，并带上 `purpose=PRIVATE_SERVICE_CONNECT` 属性。
3. **应用声明或特定 CRD**：
    *   **旧形态 (Service) 方式**：你需要创建一个 `type: LoadBalancer` 的标准 Kubernetes Service，加上关键注解 `networking.gke.io/load-balancer-type: "Internal"`，同时再配套应用 GCP 专用的 CRD 资源 `ServiceAttachment` (属于 `networking.gke.io/v1` API 组)，在里面指定上一步的子网名称。GKE 控制器会去底层创建带 Forwarding Rule 的 ILB 以及绑定。
    *   **新形态 (Gateway API) 方式**：你创建标准的 Kubernetes `Gateway`，指定 Class 为内部网关类。**为了修复全局无法访问的问题（满足之前提到的跨区/GLB 消费条件）**，你需要挂载一个名为 `GCPGatewayPolicy` 的扩展策略，在策略文件内写入 `allowGlobalAccess: true`。提交后，系统会自动帮你把底层重建出一个打通了全局访问权限的 Forwarding Rule，并对接回 Service Attachment。

> **核心逻辑总结**：无论你是用 Terraform/命令行 手撕 `Forwarding Rule`，还是在 GKE 里丢一个优雅的 `Gateway` 或 `ServiceAttachment` YAML，它们最后在 GCP 骨干网上生成的“暴露点”本质都是相同的。这解释了为什么即使在 GKE 里，报错提示仍然是“Producer load balancer 需要开启 AllowGlobalAccess”。

---

### 明确结论

**是的。Service Attachment 必须是区域级（Regional）资源，GCP 不存在全局（Global）的 Service Attachment。**

您可以放心按照“区域级资源”的模型来做您的基础架构设计。以下为您深度解析背后的逻辑以及如何处理“全局可达性”。

---

### 原理解析：为什么 Service Attachment 是区域级的？

在 Private Service Connect (PSC) 的架构中，Service Attachment 扮演的是 **服务发布方 (Producer)** 的暴露网关角色。它的本质决定了它的资源层级：

1. **底层强依赖区域级网元**：Service Attachment 必须挂载在（Target 指向）一个区域内部负载均衡器 (Regional Internal Application/Network Load Balancer) 的 Forwarding Rule 上。
2. **跟子网 (Subnet) 强绑定**：创建 Service Attachment 时，您必须为其分配一个专用的 PSC NAT Subnet（`--nat-subnets`），而 Subnet 在 GCP 中是严格的区域级 (Regional) 资源。
3. **流量本地化与隔离**：GCP 的设计哲学是让内部流量尽量保持在 Region 内部，以保证极低的延迟和极高的故障隔离度（一个 Region 挂了，不会牵连全球）。

---

### 进阶思考：既然是区域资源，前文的 `AllowGlobalAccess` 是什么？

我们在前面排查外部全局负载均衡 (Global External ALB) 接入 PSC NEG 的报错时，提到了 `AllowGlobalAccess`。很多开发者会在这里产生概念混淆：**既然资源是 Regional 的，这个 Global 从何而来？**

这里的逻辑是：**资源实体在区域内，但访问范围可以扩展到全局。**

#### 1. 资源位置 vs. 访问可达性
- **资源位置**：Service Attachment 部署在 `europe-west2`，它是一个实体，不可动摇。
- **访问可达性**：只要背后的 Internal Load Balancer 开启了全局访问（`allowGlobalAccess=true`），那么全球任何地方（甚至包括 Global ALB 的跨区域边缘节点）都可以把流量路由到这个位于 `europe-west2` 的 Service Attachment。

#### 2. “全局”在 PSC 中的两种常见形态

结合您的实际场景，如果您想要实现跨区域访问，您需要关注两个层面的“全局开启”：

*   **Producer 侧（您的前面那个报错场景）**：
    Service Attachment 背后挂载的 **ILB Forwarding Rule** 必须配置 `--allow-global-access`。这允许 GCP 全局外部负载均衡器（Global Consumer）的流量跨区域打通并送达您的 Service Attachment。
*   **Consumer 侧（如果是纯内网端点访问）**：
    如果 Consumer 侧不是用负载均衡器，而是直接在 VPC 里创建一个 **PSC Endpoint (也是一种 Forwarding Rule)** 指向上述 Service Attachment。默认情况下，只有 Consumer 中同 Region 的 VM 能访问这个 Endpoint。如果想要 Consumer VPC 中其他 Region 的 VM 也能访问，则需要在 Consumer 的 Forwarding Rule 上开启 `--allow-psc-global-access`。

---

### 架构设计总结

| 资源 / 属性                 | 类型级别               | 说明                                                                         |
| :-------------------------- | :--------------------- | :--------------------------------------------------------------------------- |
| **Service Attachment**      | 📍 **Regional**         | 永远是区域级资源，受到内网和底层 ILB 的区域限制。                            |
| **PSC NAT Subnet**          | 📍 **Regional**         | Service Attachment 强依赖的 NAT 地址池，属于区域资源。                       |
| **ILB `AllowGlobalAccess`** | 🌐 **Global (能力)**    | 控制区域内的 ILB 是否允许来自其他区域的 Consumer 或 Global ALB 的流量流入。  |
| **PSC NEG (Consumer端)**    | 📍 **Regional / Zonal** | 指向对应区域的 Service Attachment，但作为 Backend 可被挂载到 Global ALB 上。 |

**一句话总结**：发布出去的“接头点 (Service Attachment)”只能建在某个具体的区域里，但您可以通过开启开关，允许全球各地的服务顺着网线过来找这个“接头点”。