# mTLS 全局入口架构文件描述

本文档旨在为 `public-mtls-global-ingress` 的架构设计解释三张核心交付物，以确保跨项目 mTLS 实施的完整理解。

## 1. `shared-glb-cn-a.html` (Sequence Flow)
**主题:** **端到端请求流 (Request Flow)**
**内容:** 展示了客户端请求从外部进入到最终服务消费的完整路径。
**重点:** 描绘了请求如何在 **GLB** 层面由 **URL Map** 路径规则进行路由，以及如何通过 **Nginx/Gateway** 在中间进行 **mTLS 证书校验**（URI-SAN 注入）以实现租户隔离。
**用途:** 理解 **请求的路径隔离** 和 **证书注入** 机制。

## 2. `shared-glb-cn-b.html` (Lifecycle State Machine)
**主题:** **mTLS 证书生命周期与防漂移 (Certificate Lifecycle & Drift Prevention)**
**内容:** 这是一个状态机图，描述了客户端证书（Client Cert）从**签发 (Issued)**、**有效验证 (Valid Cert)**，到**GLB mTLS 验证**，再到**URI-SAN 门禁**，最终**服务访问 (team-svc)** 的完整状态变化，以及**漂移 (Drift)** 触发的**安全拒绝 (404)** 流程。
**用途:** 理解**安全策略**如何驱动**流量控制**，以及**漂移检测**的防漂移机制。

## 3. `mtls-architecture.html` (Architecture Topology)
**主题:** **平台拓扑 (Platform Topology)**
**内容:** 展示了跨项目的整体架构关系，聚焦于**负载均衡、服务发现和安全边界**。
**重点:** 包含 **GLB**、**K8s Gateway**、**PSC NEG** 的关系，以及多个 **Backend Service (BS)** 如何通过 **PSC** 暴露给外部，并如何通过 **HTTPRoute** 机制实现租户级别的路由和隔离。
**用途:** 理解 **跨项目网络连接** 的物理关系，以及 **服务边界** 的划分。

---
**核心洞察:**
这三张图共同描述了在一个**共享的外部入口 (GLB)** 下，如何通过**路径路由 (A)**、**证书状态管理 (B)** 和**网络拓扑 (C)** 来实现**多租户隔离 (Multi-tenancy)** 和**强安全验证**的完整闭环。
