# Cloud Load Balancing 跨项目服务引用功能详解

> 原文：[Cloud Load Balancing gets cross-project service referencing](https://cloud.google.com/blog/products/networking/cloud-load-balancing-gets-cross-project-service-referencing)

---

## 一、功能概述

**跨项目服务引用 (Cross-Project Service Referencing)** 是 Google Cloud Load Balancing 的一项通用发布 (GA) 功能，允许你配置一个**中央负载均衡器**，将流量路由到分布在**多个不同项目**中的数百个服务。

### 支持的负载均衡类型

| 类型 | 状态 |
|------|------|
| Internal HTTP(S) Load Balancing (内部 HTTP(S) 负载均衡) | ✅ 已支持 |
| Regional External HTTP(S) Load Balancing (区域外部 HTTP(S) 负载均衡) | ✅ 已支持 |
| Global External HTTP(S) Load Balancing (全局外部 HTTP(S) 负载均衡) | ⏳ 即将推出 |

### 核心价值

- **集中管理**：所有流量路由规则可在**一个 URL map** 中统一管理
- **跨项目路由**：单个负载均衡器可路由到多个项目中的后端服务
- **职责分离**：服务团队和网络团队可独立管理各自资源

---

## 二、解决的问题

在传统多项目架构中，你面临以下挑战：

| 传统架构问题 | 跨项目服务引用解决方案 |
|-------------|---------------------|
| 每个项目的服务需要独立的负载均衡器 | **单个中央负载均衡器**即可覆盖所有项目 |
| 需要管理多个主机名和 SSL 证书 | 只需**一个转发规则**，统一关联主机名和 SSL 证书 |
| 需要链接多个 VPC 网络，防火墙规则复杂 | 使用 **Shared VPC**，无需链接多个 VPC |
| 运维成本高，配额限制紧张 | **减少负载均衡器数量**，降低配额需求 |
| 团队职责分离困难 | 服务团队和网络团队可**独立管理**各自资源 |
| 服务暴露权限控制粒度不足 | 通过 **IAM 角色**和**组织策略**实现细粒度访问控制 |

---

## 三、架构设计

### 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                    Host Project (Shared VPC)                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              中央负载均衡器资源                            │   │
│  │  • Forwarding Rules (转发规则)                            │   │
│  │  • Target Proxy (目标代理)                                │   │
│  │  • URL Map (统一路由规则)                                 │   │
│  │  • Hostnames & SSL Certificates (主机名和证书)            │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│         ┌────────────────────┼────────────────────┐             │
│         │                    │                    │             │
└─────────┼────────────────────┼────────────────────┼─────────────┘
          │                    │                    │
          ▼                    ▼                    ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  Service Project │ │  Service Project │ │  Service Project │
│       A          │ │       B          │ │       C          │
│  ┌────────────┐  │ │  ┌────────────┐  │ │  ┌────────────┐  │
│  │ Backend    │  │ │  │ Backend    │  │ │  │ Backend    │  │
│  │ Service    │  │ │  │ Service    │  │ │  │ Service    │  │
│  │ + Backends │  │ │  │ + Backends │  │ │  │ + Backends │  │
│  └────────────┘  │ │  └────────────┘  │ │  └────────────┘  │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

### 流量流程

1. **用户请求** → 中央负载均衡器 (Host Project)
2. **URL Map** 根据路由规则匹配目标后端服务
3. **跨项目路由** → 流量分发到 Service Project 中的 Backend Service
4. **后端分发** → Backend Service 根据会话亲和性、健康检查等策略分发到后端实例

---

## 四、实现步骤（详细配置流程）

### 前置条件

- **必须使用 Shared VPC 设置**（包含 Host Project 和 Service Projects）
- 所有项目必须在同一组织内

---

### Step 1: Shared VPC 和网络管理员配置

**角色**：Shared VPC Administrator / Network Administrator  
**操作项目**：Host Project

```
1. 在 Host Project 上启用 Shared VPC

2. 附加 Service Projects 到 Shared VPC
   - 将需要共享网络的项目添加为 Service Project

3. 在 Host Project 中创建网络基础设施：
   • Network (网络)
   • Subnetworks (子网)
   • Firewall Rules (防火墙规则)

4. 授予权限：
   • 授予 Service Administrator 子网权限
   • 授予 Load Balancer Administrator 子网权限
```

**关键配置**：
- 防火墙规则需要在 Host Project 中配置
- 所有 Service Projects 使用同一 Shared VPC 网络

---

### Step 2: 服务所有者配置后端服务

**角色**：Service Owner / Administrator  
**操作项目**：Service Project

```
1. 在 Service Project 中创建 Backend Service (后端服务)

2. 附加 Backends (后端实例)
   - 可以是 GCE 实例、MIG、NEG 等

3. 配置 Backend Service 级别的流量管理策略：
   • Session Affinity (会话亲和性)
   • Health Checks (健康检查)
   • Identity-based Access (基于身份的访问)
   • Outlier Detection (异常检测)

4. 授予 Load Balancer Administrator IAM 权限以访问后端服务
   - 使用 Load Balancer Service User 角色
```

**关键点**：
- 服务所有者对 Backend Service 有**独占控制权**
- 必须**主动授予**负载均衡器管理员访问权限

---

### Step 3: 负载均衡器管理员创建中央负载均衡器

**角色**：Load Balancer Administrator  
**操作项目**：Service Project 或 Host Project

```
1. 创建负载均衡器

2. 配置转发规则 (Forwarding Rules)
   - 定义 IP 地址、端口、协议

3. 配置 Target Proxy
   - Target HTTP(S) Proxy

4. 配置 URL Map (可引用跨项目后端服务)
   - 定义路由规则
   - 指向跨项目的 Backend Service

5. 将流量导向跨项目 Backend Service
   - 在 URL Map 中引用 Service Project 的后端服务
```

**URL Map 配置示例**（概念）：
```yaml
urlMap:
  name: central-url-map
  hostRules:
    - hosts:
        - api.example.com
      pathMatcher: all-services
  pathMatchers:
    - name: all-services
      defaultService: projects/{service-project-a}/global/backendServices/service-a
      pathRules:
        - paths:
            - /service-a/*
          service: projects/{service-project-a}/global/backendServices/service-a
        - paths:
            - /service-b/*
          service: projects/{service-project-b}/global/backendServices/service-b
        - paths:
            - /service-c/*
          service: projects/{service-project-c}/global/backendServices/service-c
```

---

## 五、使用场景

### 场景 1: 多团队微服务架构

```
组织结构：
├── 网络团队 (管理 Host Project)
├── 团队 A (Service Project A - 用户服务)
├── 团队 B (Service Project B - 订单服务)
└── 团队 C (Service Project C - 支付服务)

优势：
- 网络团队集中管理负载均衡和网络安全
- 各团队独立开发、部署自己的服务
- 统一入口，统一 SSL 证书管理
```

### 场景 2: 多租户平台

```
平台架构：
├── 平台 Host Project (中央负载均衡器)
├── 租户 A Project (独立后端服务)
├── 租户 B Project (独立后端服务)
├── 租户 C Project (独立后端服务)
└── ... 数百个租户项目

优势：
- 单个负载均衡器支持数百个租户
- 租户间资源隔离
- 统一流量管理和监控
```

### 场景 3: 企业级应用部署

```
企业部署：
├── 网络中心 Project (共享 VPC + 负载均衡)
├── 开发环境 Project
├── 测试环境 Project
├── 生产环境 Project
└── 数据项目 Project

优势：
- 环境隔离 + 统一入口
- 开发和运维职责分离
- 安全边界清晰
```

---

## 六、核心优势详解

### 优势 1: 降低运维复杂度和成本

| 传统架构 | 跨项目服务引用 |
|---------|--------------|
| N 个负载均衡器 | 1 个中央负载均衡器 |
| N 个转发规则 | 1 个转发规则 |
| N 套主机名和 SSL 证书 | 1 套主机名和 SSL 证书 |
| N 倍配额消耗 | 1 倍配额消耗 |
| N 倍运维工作量 | 集中管理，工作量大幅降低 |

### 优势 2: 实现团队职责分离

```
权限边界：
┌─────────────────────────────────────┐
│         网络团队                     │
│  • Host Project                     │
│  • Shared VPC 配置                  │
│  • 负载均衡器配置                   │
│  • 防火墙规则                       │
│  • 无法修改 Service Project 资源    │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│         服务团队                     │
│  • Service Project                  │
│  • Backend Service 配置             │
│  • 后端实例管理                     │
│  • 服务级流量策略                   │
│  • 无法修改负载均衡器配置           │
└─────────────────────────────────────┘
```

### 优势 3: 服务所有者独占控制权

服务所有者可以独立配置 Backend Service 级别的高级流量管理：

- **Session Affinity** (会话亲和性)
- **Health Checks** (健康检查)
- **Identity-based Access** (基于身份的访问)
- **Outlier Detection** (异常检测)
- **其他高级流量管理能力**

### 优势 4: 细粒度访问控制

#### IAM 角色控制

```
Load Balancer Service User 角色：
- 只有被授予此角色的用户/服务账号才能访问跨项目服务
- 服务所有者主动授予负载均衡器管理员此权限
- 实现最小权限原则
```

#### 组织策略约束

```
Organizational Policy Constraints：
- 可完全禁用跨项目引用功能
- 可限制到特定项目范围
- 可限制到特定文件夹范围
- 企业级安全管控
```

---

## 七、限制和注意事项

### 7.1 网络架构限制

| 限制项 | 说明 |
|-------|------|
| **Shared VPC 强制要求** | 必须使用 Shared VPC 设置 |
| **同一 VPC 网络** | Host Project 和 Service Projects 必须在同一 Shared VPC 内 |
| **无法跨独立 VPC** | 不能跨多个独立 VPC 网络使用 |

### 7.2 项目位置限制

| 限制项 | 说明 |
|-------|------|
| **同一组织** | 所有项目必须在同一组织内 |
| **前端资源位置** | 负载均衡器前端资源必须在 Host Project 或同一 Shared VPC 的 Service Project 中 |

### 7.3 IAM 权限要求

```
必需配置：
✓ Load Balancer Service User 角色必须正确授予
✓ 服务所有者必须主动授予负载均衡器管理员访问后端服务的权限
✓ 网络管理员需要 Shared VPC Administrator 权限
```

### 7.4 组织策略约束

```
可配置策略：
• 完全禁用跨项目引用功能
• 限制到特定项目范围
• 限制到特定文件夹范围
```

### 7.5 网络配置要求

```
防火墙规则：
- 必须在 Host Project 中配置
- 需要允许负载均衡器健康检查和流量转发到 Service Projects
- 所有 Service Projects 使用同一 Shared VPC 网络
```

---

## 八、参考文档

- [Internal HTTP(S) Load Balancing 设置指南](https://cloud.google.com/load-balancing/docs/l7-internal/setup-guide)
- [Regional External HTTP(S) Load Balancing 设置指南](https://cloud.google.com/load-balancing/docs/regional-ext-http-backend-service)
- [Shared VPC 文档](https://cloud.google.com/vpc/docs/shared-vpc)
- [Load Balancer Service User 角色文档](https://cloud.google.com/load-balancing/docs/iam-roles)

---

## 九、总结

### 功能定位

跨项目服务引用是 Google Cloud 为**企业级多项目架构**设计的关键功能，解决了传统架构中负载均衡器分散管理、运维复杂、职责不清的核心痛点。

### 适用场景

✅ 推荐使用：
- 多团队微服务架构
- 多租户 SaaS 平台
- 企业级多环境部署
- 需要集中流量管理的场景

❌ 不适用：
- 单项目简单应用
- 没有 Shared VPC 需求的场景
- 需要跨独立 VPC 网络负载均衡

### 实施建议

1. **优先规划 Shared VPC 架构**
2. **明确团队职责边界和 IAM 权限**
3. **设计统一的 URL Map 路由策略**
4. **配置组织策略进行安全管控**
5. **建立跨团队协作流程**

---

*文档生成时间：2026 年 3 月 16 日*  
*原文发布日期：2022 年 9 月 21 日*  
*原文作者：Anusheel Pareek, Senior Product Manager, Vertex AI*
