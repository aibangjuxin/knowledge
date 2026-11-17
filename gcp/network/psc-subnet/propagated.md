# 传播连接简介 (Propagated Connections)

> **Source:** [Google Cloud VPC - About propagated connections](https://docs.cloud.google.com/vpc/docs/about-propagated-connections)

---

## 概述

**传播连接 (Propagated Connections)** 是 Private Service Connect (PSC) 的一项功能，允许一个使用方 VPC spoke 中可通过 PSC 端点访问的服务，由连接到同一 Network Connectivity Center hub 的其他使用方 VPC spoke 以私密方式访问。

### 核心价值

传播连接让使用方 VPC spoke 可以访问提供方 VPC 网络中的托管式服务，**就像两个 VPC 网络通过端点直接连接一样**。

---

## 工作原理图解

```
                         Network Connectivity Center Hub
                                    │
                    ┌───────────────┼───────────────┐
                    │   (启用连接传播)                    │
                    ▼               ▼               ▼
            ┌───────────┐   ┌───────────┐   ┌───────────┐
            │  Consumer │   │  Consumer │   │  Producer │
            │   VPC 2   │   │   VPC 3   │   │   VPC 1   │
            │           │   │           │   │           │
            │ Endpoint1 │   │ Endpoint4 │   │ 托管式服务 │
            │ Endpoint2 │   │ Endpoint5 │   └───────────┘
            └───────────┘   └───────────┘
                    ▲               ▲
                    │ 传播的连接     │ 传播的连接
                    │   (2个)        │   (2个)
                    └───────────────┘
                     VPC Spoke 之间的连接传播
```

**说明：**
- `VPC Spoke Common services VPC` 包含两个端点
- 其他两个 VPC spoke 连接到同一 NCC hub
- 由于 hub 启用了连接传播，Consumer VPC 2 和 Consumer VPC 3 各有 2 个传播连接
- Consumer VPC 2 和 Consumer VPC 3 中的工作负载可以访问 Producer VPC 1 中的托管式服务

> **注意：** Endpoint 3 不会创建传播连接，因为其子网的 IP 范围被排除在导出之外。

---

## 传播连接的优势

1. **简化部署** — 可以使用通用服务 VPC 网络来简化 Private Service Connect 端点的部署
2. **集中管理** — 可以通过 Network Connectivity Center hub 管理各个 VPC spoke 可以访问哪些服务

---

## 触发连接传播的事件

系统在以下操作时**自动建立**传播连接：

| 触发事件 | 说明 |
|---------|------|
| 启用连接传播 | hub 管理员为 hub 启用连接传播时，NCC 为现有端点创建传播连接 |
| 添加新 spoke | 将 VPC spoke 添加到启用连接传播的 hub 时，NCC 在新 spoke 中为其他 spoke 的现有端点创建传播连接 |
| 创建新端点 | 在已连接 spoke 中创建端点时，NCC 在其他已连接的 VPC spoke 中为该端点创建传播连接 |
| 提高限制 | 提供方管理员提高服务的传播连接数限制时，NCC 创建之前因限制被阻止的传播连接 |

> ⚠️ **异步特性：** 连接会异步传播，可能无法立即使用。

---

## 排除子网 (Subnet Exclusion)

在创建 VPC spoke 时，可以将子网的 IP 地址范围**排除在导出范围之外**，使其不导出到 NCC hub。

**被排除子网的限制：**
- 该子网中的工作负载**无法访问**传播连接
- 该子网中的端点**不会创建**传播连接

---

## 终止传播连接

以下操作会**间接控制**传播连接的删除：

| 操作 | 效果 |
|------|------|
| 删除关联的端点 | 端点的传播连接终止 |
| 删除包含端点的 spoke | 该 spoke 的所有传播连接终止 |
| 在 hub 上停用连接传播 | 所有传播连接终止 |

> ⚠️ 终止过程是**异步的**，可能不会立即发生。

---

## 规格与限制

### 支持的端点类型

| 端点类型 | 支持传播 |
|---------|---------|
| 访问已发布服务的端点 | ✅ |
| 访问区域级 Google API 的端点 | ✅ |
| 访问全球 Google API 的端点 | ❌ |

### 关键规格

- **前提条件：** PSC 端点必须具有 `Accepted` 连接状态才会传播连接
- **默认范围：** 与传播连接位于同一区域和 VPC 网络中的工作负载可以访问传播连接
- **全球访问：** 可以在端点上配置全球访问权限，使传播连接可供所有区域的工作负载使用

### 配额与限制

| 配额类型 | 说明 |
|---------|------|
| **使用方配额** | 每个 VPC 网络的 PSC 传播连接数配额限制可以在使用方 VPC 网络中提供的传播连接数 |
| **提供方配额** | 每个提供方 VPC 网络的 PSC ILB 使用方转发规则数配额限制可以连接的端点和传播连接数 |
| **提供方连接数限制** | 每个已发布服务有传播连接数限制，限制单个使用方可以与服务建立的传播连接数（默认 250） |

### 硬性限制

- ❌ 传播的连接**不支持 IPv6** 地址的端点
- ❌ **不支持**访问全球 Google API 的端点
- ❌ 系统**不会为混合 spoke** 创建传播连接
- ❌ 系统**不会为提供方 VPC spoke** 创建传播连接

---

## 与 PSC NAT IP 消耗的关系

根据 [PSC NAT Subnet 利用率](./psc-subnet-utilization.md) 文档：

```
NAT IP In Use = Σ(1 per Endpoint) + Σ(1 per Propagation Spoke) + GCP Reserved
```

**传播连接会增加 NAT IP 消耗：**
- 1 个端点 + 3 个 VPC spokes（连接传播到） = **4 个 NAT IPs**
- 传播的连接会被视为"额外的 spoke"，每个传播的连接消耗 1 个 NAT IP

---

## 适用场景

1. **多 VPC 共享服务** — 多个业务 VPC 通过共享服务 VPC 访问后端服务，无需在每个 VPC 中部署端点
2. **集中化服务访问** — 通过 NCC hub 集中管理哪些 VPC 可以访问哪些服务
3. **简化端点管理** — 减少端点数量，降低管理复杂度

---

## 问题排查

如果无法访问传播端点，请联系 **Network Connectivity Center hub 管理员**协助排查。hub 管理员拥有排查 PSC 连接传播错误所需的访问权限。

---

## 相关文档

- [PSC NAT Subnet 利用率分析](./psc-subnet-utilization.md)
- [配置 Private Service Connect 提供方](https://docs.cloud.google.com/vpc/docs/configure-private-service-connect-producer)
- [通过 NCC 的 PSC 传播连接](https://docs.cloud.google.com/network-connectivity/docs/concepts/ncc-about#psc_propagated_connections)
- [控制已发布服务的访问](https://docs.cloud.google.com/vpc/docs/about-controlling-access-published-services)
