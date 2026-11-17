# GCP Cross-Project Service Referencing 深度解析

根据 Google Cloud 最新官方博客发布的 [Cloud Load Balancing gets cross-project service referencing](https://cloud.google.com/blog/products/networking/cloud-load-balancing-gets-cross-project-service-referencing) 文章分析，以下是该新特性的核心功能总结，以及它与你现有 `cross-project-mig.md` 文档中理解的架构的区别。

---

## 1. 这篇文章发布了什么？

文章宣发了 **Cross-Project Service Referencing（跨项目服务引用）** 功能在**内部 HTTP(S) 负载均衡**（Internal HTTP(S) LB）和**区域级外部 HTTP(S) 负载均衡**（Regional External HTTP(S) LB）中正式达到 GA (General Availability)。

### 核心能力：
它允许组织通过一个极其灵活的方式建立中央负载均衡器（Central Load Balancer）：
*   **集中在一个项目 (如项目 A)** 中配置所有的入口前端资源：转发规则（Forwarding Rules）、代理（Target Proxy）和统一的路由表（URL Map / SSL证书）。
*   **分散在多个服务项目 (如项目 B, C, D)** 中配置其独立的 **后端服务（Backend Service）** 和实际承载流量的后端实例（Backends / MIG）。

## 2. 它与你想要的 Cross-Project 架构有什么区别？

在你的 `cross-project-mig.md` 知识库中，你主要描述了将 MIG 跨项目挂载给 LB 的方式。新出台的 Cross-Project Service Referencing 与传统 Shared VPC 方案最大的区别在于**资源控制权（职权边界）的划分**：

### 传统 Shared VPC 方案 (你文档里的方案 1)
*   **配置层级**：LB 的前端组件、路由表（URL Map）、**以及后端服务（Backend Service）**，全部都在网络中心项目（Host Project）中。
*   **跨越方式**：由中心项目的 `Backend Service` 跨项目去挂载服务项目的 `Instance Group (MIG)`。
*   **痛点缺点**：**应用团队失去了对服务的控制权。** 如果项目 B 的研发团队想要改一下应用健康检查（Health check）路径、调整异常检测、或者开启后端超时时间（Timeout/Session Affinity），他们必须去求助管理项目 A 的网络团队，大大增加了运维摩擦。

### 新特性方案：Cross-Project Service Referencing (博客文章描述)
*   **配置层级**：中心项目 A **只保留前端、URL Map 和证书**。服务项目 B 不仅创建自己的 MIG，而且在自己的项目中**创建自己的 Backend Service**。
*   **跨越方式**：中心项目 A 的 `URL Map` 路由，直接跨项目指向 服务项目 B 里的 `Backend Service`。
*   **核心优势：真正的职责分离（Separation of Roles）。**
    *   **中心网络团队** 专注于全局流量入口、SSL/TLS证书管理和 URL 路由下发。
    *   **业务研发团队 (Service Owners)** 继续掌管所有应用级别的负载均衡策略（这都是挂在 Backend Service 层面的配置），比如会话保持、健康检查标准、限流控制等。安全且互不干扰。

## 3. 功能关键亮点与安全性管控

1.  **极度降低成本和操作复杂度**：全公司可以复用一条转发规则（Forwarding Rule）和一张多域名 SSL 证书，不再需要为了各部门的不同微服务单独买证书或浪费单独的 IP 和转发资源。
2.  **细粒度的 IAM 权限控制**：业务团队若想将自己的微服务接入中央 LB，并不是 LB 团队想引就能引的。业务团队可以通过赋予特定的 IAM 角色 `roles/compute.loadBalancerServiceUser`，精准决定哪些外部项目的 LB 可以引用自己的 Backend Service，确保了服务曝光的可控性。
3.  **组织策略管控 (Organizational Policies)**：安全团队能利用 GCP 的组织策略约束，限制这种“跨项目引用”只能存在于特定的 Folder，或者禁止某些高密级项目对外开放后端。

## 4. 纠正一点你的既有认知（重要前提）

在你此前的 `cross-project-mig.md` 文档中，提到“如果你不想用 Shared VPC……可以使用跨项目后端服务引用”。

根据这篇官方博客的权威说明，这是个微小的误区。文章明确提到：
> *(this project has to be within a Shared VPC setup using host and service projects... and backend services and backends in different service projects, in the same shared VPC setup.)*

**即：Cross-Project Service Referencing 依然强制依赖基于 Shared VPC 的网络连通架构！**

**总结就是**：这个新功能解决的**不是底层 VPC 网络怎么通**的问题，而是解决的 GCP Load Balancer 上层资源组件的**管理权限解耦**问题。您依然必须有 Shared VPC 提供底层支撑。
