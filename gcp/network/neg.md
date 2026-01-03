
# NEG 
以下是对 Google Cloud 中 **NEG（Network Endpoint Group）** 的详细介绍，特别是它在 GKE Gateway、Backend Service 等场景下的作用。

---

## **什么是 NEG（Network Endpoint Group）**

  

**NEG（Network Endpoint Group）** 是 Google Cloud 中的一种资源类型，用于表示一组网络终端（Endpoint），这些终端可以是 VM、容器、Cloud Run 服务，或者是 Internet 上的地址。NEG 提供了一种细粒度的方式将请求流量路由到特定的 backend 实体上。

  

NEG 的引入，主要是为了支持负载均衡器更精确地控制和识别后端服务实例的位置和类型。

---

## **NEG 的类型分类**

|**NEG 类型**|**描述**|
|---|---|
|GCE VM NEG|将单个 VM 实例的网络接口作为 Endpoint|
|GCE Zonal NEG|将 GCE VM 或实例组中的实例作为 Endpoint（L4负载均衡常用）|
|GKE NEG（容器 NEG）|与 GKE 集群中的 Pod 直接绑定，允许负载均衡器直达 Pod|
|Serverless NEG|表示 Cloud Run、App Engine、Cloud Functions 等 serverless 服务|
|Internet NEG|代表 Internet 上的 FQDN/IP Endpoint，适用于 Hybrid Cloud|

---

## **GKE 中的 NEG（容器 NEG）**

  

当你使用 GKE 并启用 Gateway API（或 Ingress）时，必须启用容器级别的 NEG。这是因为 Google 的 HTTP(S) 负载均衡器（GLB）无法直接识别 Pod，需要借助 NEG 将 Load Balancer 与具体 Pod 建立映射。

  

### **开启 NEG 的方式（GKE）**

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
```

在 Gateway API 中你无需显式写 Annotation，但 Controller 会自动为你创建 NEG。

---

## **NEG 与 Backend Service 的关系**

  

**Backend Service** 是 GLB 中的核心资源之一，它决定了请求如何被转发到后端。而 **NEG 就是 Backend Service 的 backend target。**

  

### **示意图**

```mermaid
graph TD;
    Client --> GLB[Google Load Balancer];
    GLB --> BackendService;
    BackendService --> NEG;
    NEG --> Pod1;
    NEG --> Pod2;
```

### **一个 Backend Service 可以绑定多个 NEG：**

- 每个 NEG 位于不同的 zone / region（用于 Multi-Zone 部署）
    
- Backend Service 会基于负载策略（如 round robin、connection balancing）将流量分配到这些 NEG 上
    

---

## **为什么在 GKE Gateway 中需要 NEG？**

- GKE Gateway（或 Ingress）会动态生成一个 GLB
    
- GLB 不知道 Pod 的存在，需要 NEG 来作为桥梁
    
- NEG 中注册的 Endpoint 是具体的 Pod IP 和 port
    
- NEG 可以与 **健康检查** 配合，自动移除不健康的 Pod
    

---

## **NEG 示例（通过** 

## **gcloud**

##  **查看）**

```
gcloud compute network-endpoint-groups list
```

```
gcloud compute network-endpoint-groups describe my-neg \
  --region=us-central1
```

输出会包含 Pod 或 VM 的 IP、端口等信息。

---

## **总结表格**

|**资源类型**|**说明**|
|---|---|
|NEG（容器）|映射到 Pod 的 endpoint，支持 GLB 直接到 Pod|
|Backend Service|将流量发送到 NEG 的路由规则配置实体|
|GLB|通过 URL Map 和 Backend Service 将请求路由到 NEG|
|GKE Gateway|自动生成并管理 NEG 和 Backend Service 资源|

---

### **补充：Serverless NEG 用于 Cloud Run 场景**

  

在 Cloud Run 中，你会看到如下结构：

```mermaid
graph TD;
    Client --> GLB;
    GLB --> BackendService;
    BackendService --> ServerlessNEG;
    ServerlessNEG --> CloudRun[Cloud Run 实例];
```

你可以在配置 Load Balancer 的 backend 时直接引用 Cloud Run 服务名，此时后台会自动创建 serverless NEG。

---

如你在规划多租户、统一域名入口、基于 path 分发到不同 Cloud Run/GKE 服务的架构时，NEG 是后端服务注册的关键资源。是否需要我进一步展示 GKE Gateway + NEG 的部署示例 YAML？


# NEG GKE  

使用网络端点组（Network Endpoint Group，NEG）实现容器原生负载均衡相较于直接使用GKE External Load Balancer有几个显著的优点：

### 优点

1. **更细粒度的流量控制**
   - **NEG**允许将流量直接发送到特定的容器实例，而不仅仅是虚拟机实例。这使得流量分发更精确，可以更好地利用容器化应用的灵活性和扩展能力。

2. **直接集成服务发现**
   - **NEG**与GKE深度集成，可以自动发现和管理Pod的生命周期。它可以确保负载均衡器始终知道哪些容器正在运行，哪些已经终止，避免将流量发送到无效的容器。

3. **支持多端点类型**
   - **NEG**支持多种类型的端点，包括GCE虚拟机实例、GKE容器、服务器集群等。这使得它在多种场景下都能灵活应用，满足复杂的流量分发需求。

4. **简化的运维**
   - 使用**NEG**后，运维人员不再需要手动更新负载均衡器配置来反映后端的变化。GKE和NEG会自动同步Pod的健康状况和IP地址变化，简化了运维工作。

5. **优化的性能**
   - **NEG**通过直接将流量路由到容器级别，减少了中间层的流量处理和延迟，从而提升了应用的响应速度和性能。

6. **更好的健康检查**
   - **NEG**支持更细粒度的健康检查，能够针对每个Pod进行独立的健康监测。这确保了只有健康的实例会接收流量，提高了应用的可用性。

### 图示说明

以下是使用NEG与GKE External Load Balancer的架构对比示意图：

```mermaid
graph TD
  subgraph GKE External Load Balancer
    A[External Load Balancer]
    B[GKE Cluster]
    C[VM Instances]
    A --> B
    B --> C
  end
  
  subgraph Container-Native Load Balancing with NEG
    D[External Load Balancer]
    E[GKE Cluster with NEG]
    F[Containers Pods]
    D --> E
    E --> F
  end
```

### 总结

使用网络端点组（NEG）进行容器原生负载均衡能够更好地利用GKE的容器化特性，提供更细粒度的流量控制、更好的性能以及简化的运维体验，是相较于传统的GKE External Load Balancer更为先进和灵活的
选择。

使用网络端点组（NEG）后，观察到Kong Data Plane（DP）对应的CPU压力减少，这确实可能符合预期，原因如下：

### 1. **更高效的流量路由**

NEG允许流量直接路由到具体的容器实例，而不是先经过虚拟机。这减少了流量处理的中间层，从而降低了CPU负载。Kong作为一个API网关和负载均衡器，处理的流量量级较大时，如果减少了中间的转发和处理步骤，自然会减轻其负载。

### 2. **减少了不必要的网络开销**

使用NEG可以更高效地进行负载均衡，直接将流量分配到Pod级别。传统的负载均衡方式可能需要更多的网络转发和处理步骤，这些步骤会增加Kong的CPU开销。NEG的直接流量分发方式减少了不必要的网络开销，降低了CPU使用率。

### 3. **更精准的健康检查**

NEG提供更细粒度的健康检查能力，可以针对每个Pod进行独立的健康检查。这意味着Kong不需要再执行额外的健康检查操作，从而减少了CPU消耗。

### 4. **更好的资源分配和管理**

通过NEG，GKE能够更高效地管理和分配资源，确保流量分配更加合理和优化。这减少了Kong处理负载不均衡情况时的压力。

### 图示说明

以下是使用NEG和传统方法在流量处理路径上的对比：

```mermaid
graph TD
  subgraph 传统方法
    A[External Load Balancer]
    B[GKE Cluster]
    C[VM Instances]
    D[Kong]
    E[Pods]
    A --> B
    B --> C
    C --> D
    D --> E
  end
  
  subgraph 使用NEG方法
    F[External Load Balancer]
    G[GKE Cluster with NEG]
    H[Kong]
    I[Pods]
    F --> G
    G --> I
    H --> I
  end
```

### 结论

使用NEG后，流量路由更加直接、高效，减少了中间步骤和不必要的网络开销，从而降低了Kong DP的CPU压力。这种改进符合预期，并且是由于NEG优化了流量处理路径和资源管理。



# claude
关于在 Google Cloud Platform (GCP) 中使用网络端点组 (NEG) 实现容器原生负载均衡与直接使用 GKE 外部负载均衡器的比较。让我们逐步分析这个问题:

1. NEG vs GKE 外部负载均衡器的优点:

   使用 NEG 实现容器原生负载均衡相比直接使用 GKE 外部负载均衡器确实有一些优势:

   a) 更细粒度的流量控制: NEG 允许您直接将流量路由到特定的 Pod IP 和端口,而不是通过 NodePort 或 ClusterIP。

   b) 更高的性能: 由于流量直接到达 Pod,减少了网络跳数,可能会降低延迟。

   c) 更好的可扩展性: NEG 可以支持更多的后端实例,适合大规模部署。

   d) 更灵活的部署模式: 支持多区域部署,可以跨多个区域均衡流量。

   e) 更好的健康检查: 可以直接检查 Pod 的健康状态,而不是节点的健康状态。

2. CPU 压力减少的原因:

   您观察到使用 NEG 后,Kong 数据平面 (DP) 的 CPU 压力减少了。这很可能与 NEG 的工作方式有关:

   a) 直接路由: NEG 允许流量直接路由到 Pod,绕过了 kube-proxy。这减少了网络栈的复杂性,可能导致 CPU 使用率降低。

   b) 减少 SNAT: 使用 NEG 时,通常不需要源网络地址转换 (SNAT),这可能会减少 CPU 开销。

   c) 负载分散: NEG 可能更有效地分散负载,使单个 Kong DP 实例承受的压力减小。

   d) 更高效的健康检查: NEG 的健康检查机制可能比传统的 Kubernetes 服务更高效,减少了不必要的流量和处理。

3. 预期结果:

   您观察到的 CPU 压力减少确实符合使用 NEG 的预期结果。NEG 的设计目标之一就是提高性能和效率,所以看到 CPU 使用率降低是合理的。

4. 与 NEG 的关系:

   是的,您观察到的变化很可能与使用 NEG 直接相关。NEG 通过优化流量路径、减少网络复杂性和提高负载均衡效率,可以显著影响系统性能,包括降低 CPU 使用率。

总结来说,您观察到的 CPU 压力减少是使用 NEG 的一个常见好处,这源于其更直接、更高效的流量路由和负载均衡机制。如果您的应用程序对性能和可扩展性有较高要求,使用 NEG 实现容器原生负载均衡可能是一个很好的选择。

如果您需要更深入地了解这些变化或者想探讨如何进一步优化您的架构,我很乐意继续讨论。​​​​​​​​​​​​​​​​

当然,我很乐意为您创建一些 Mermaid 图表来帮助您更好地理解这个对比。我们将创建两个图表:一个展示传统的 GKE 外部负载均衡,另一个展示使用 NEG 的容器原生负载均衡。这样的可视化对比应该能帮助您更清晰地看到两种方法的区别。



首先,让我们创建一个展示传统 GKE 外部负载均衡的图表:

```mermaid
graph TD
    A[客户端] -->|1. 请求| B(GKE 外部负载均衡器)
    B -->|2. 转发到 NodePort| C{Kubernetes 节点}
    C -->|3. kube-proxy| D[Pod 1]
    C -->|3. kube-proxy| E[Pod 2]
    C -->|3. kube-proxy| F[Pod 3]
    D -->|4. 处理请求| G[Kong DP]
    E -->|4. 处理请求| G
    F -->|4. 处理请求| G
```

这个图表展示了传统 GKE 外部负载均衡的流程:
1. 客户端请求首先到达 GKE 外部负载均衡器。
2. 负载均衡器将请求转发到 Kubernetes 节点的 NodePort。
3. 在节点内,kube-proxy 负责将流量路由到正确的 Pod。
4. 最后,请求被路由到 Kong DP 进行处理。

现在,让我们创建一个使用 NEG 的容器原生负载均衡的图表:

```mermaid
graph TD
    A[客户端] -->|1. 请求| B(GCP 负载均衡器 with NEG)
    B -->|2. 直接转发到 Pod IP| C[Pod 1 / Kong DP]
    B -->|2. 直接转发到 Pod IP| D[Pod 2 / Kong DP]
    B -->|2. 直接转发到 Pod IP| E[Pod 3 / Kong DP]
    F[NEG 控制器] -.->|更新 Pod IP| B
```

这个图表展示了使用 NEG 的容器原生负载均衡流程:
1. 客户端请求到达 GCP 负载均衡器,该负载均衡器配置了 NEG。
2. 负载均衡器直接将请求转发到特定 Pod 的 IP 和端口,无需经过 NodePort 或 kube-proxy。
3. NEG 控制器持续更新 Pod 的 IP 信息到负载均衡器。

通过比较这两个图表,我们可以看到以下几个关键差异:

1. 路由路径: NEG 方案的路由路径更短,直接从负载均衡器到 Pod。
2. kube-proxy: 传统方案中 kube-proxy 参与了路由过程,而 NEG 方案绕过了 kube-proxy。
3. 网络跳数: NEG 方案减少了网络跳数,可能导致更低的延迟。
4. Pod 识别: NEG 方案直接识别 Pod IP,而不是通过节点和服务进行间接路由。

这些差异解释了为什么您在使用 NEG 后观察到 Kong DP 的 CPU 压力减少。直接路由减少了网络复杂性和处理开销,从而降低了 CPU 使用率。

希望这些图表和解释能帮助您更好地理解两种负载均衡方案的区别。如果您还有任何问题或需要进一步澄清,请随时告诉我。​​​​​​​​​​​​​​​​


您提出了一个很好的观点。让我们深入探讨一下通过 GKE Ingress 配置请求直接转发到 ClusterIP Service 的情况。



首先，让我们通过一个图表来可视化这种配置：

```mermaid
graph TD
    A[客户端] -->|1. 请求| B(GKE Ingress)
    B -->|2. 转发到 ClusterIP| C{ClusterIP Service}
    C -->|3. 负载均衡| D[Pod 1]
    C -->|3. 负载均衡| E[Pod 2]
    C -->|3. 负载均衡| F[Pod 3]
    G[kube-proxy] -.->|维护转发规则| C
```

这个图表展示了通过 GKE Ingress 直接转发到 ClusterIP Service 的流程：

1. 客户端请求首先到达 GKE Ingress。
2. Ingress 直接将请求转发到 ClusterIP Service。
3. ClusterIP Service 使用内部负载均衡将请求分发到后端 Pods。

现在，让我们分析这种方法：

1. 是否直接定位到 Pod？
   - 严格来说，这种方法并不是直接定位到 Pod。请求仍然通过 ClusterIP Service 进行路由。
   - 但是，相比于使用 NodePort 或 LoadBalancer 类型的服务，这种方法确实减少了一些网络跳数。

2. 性能提升的原因：
   - 减少网络跳数：相比于先经过外部负载均衡器再到 NodePort，这种方式减少了网络跳数。
   - GKE Ingress 优化：GKE Ingress 控制器经过优化，可以高效地处理流量。
   - 内部流量：流量在集群内部路由，可能benefiting不需要额外的 NAT 或跨节点通信。
   - 高效的服务发现：ClusterIP Service 提供了高效的服务发现和负载均衡机制。

3. 与 NEG 的比较：
   - NEG 仍然提供更直接的路由，直接到 Pod IP。
   - 但是，GKE Ingress 到 ClusterIP 的方式可以被视为一个很好的折中方案，在易用性和性能之间取得平衡。

4. 为什么性能有所提升：
   - 减少了外部负载均衡器的依赖。
   - 利用了 Kubernetes 内部的高效网络模型。
   - GKE Ingress 可能应用了一些特定的优化。

总结：
虽然这种方法不像 NEG 那样直接定位到 Pod，但它确实提供了一种相对高效的路由方式。您观察到的性能提升很可能是由于减少了网络复杂性，以及利用了 GKE 和 Kubernetes 的内部优化。

这种方法可以被视为在易用性、灵活性和性能之间的一个很好的平衡点。它不需要像 NEG 那样的额外配置，但仍然能够提供显著的性能改进。

如果您想进一步优化，您可以考虑：
1. 使用容器原生负载均衡（如 NEG）来获得更直接的路由。
2. 优化您的 ClusterIP Service 的配置，如调整会话亲和性设置。
3. 监控和调整 GKE Ingress 的配置，以确保最佳性能。

您是否还有其他特定的性能指标或配置细节想讨论？我们可以更深入地分析您的具体场景。​​​​​​​​​​​​​​​​
