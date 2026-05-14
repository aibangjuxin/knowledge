# 为什么 PSC模式下 NetworkPolicy 需要允许 3306/3307 端口

## 概述

在使用 Private Service Connect (PSC) 连接 Cloud SQL MySQL 时，GKE Pod 的 NetworkPolicy 必须允许 3306 和 3307 两个端口出站。这不是过度配置，而是覆盖了 PSC 连接 Cloud SQL 的两种主要方式。

## Cloud SQL PSC 支持的连接方式

根据 [Cloud SQL PSC 文档](https://cloud.google.com/sql/docs/mysql/about-private-service-connect)，PSC 提供了两种连接端口：

| 端口     | 用途                                  | 说明                                    |
| -------- | ------------------------------------- | --------------------------------------- |
| **3306** | 直接连接 / Managed Connection Pooling | MySQL 默认端口，用于原生 MySQL 协议连接 |
| **3307** | Cloud SQL Auth Proxy                  | 通过 Auth Proxy 的连接端口              |

## 为什么需要同时允许两个端口

### 场景 1: 直接连接 (Port 3306)

```yaml
# 应用直连 PSC 端点
DB_HOST=10.1.1.x  # PSC Endpoint IP
DB_PORT=3306       # 直接连接
```

这种场景下，应用程序使用原生 MySQL 协议直接连接数据库。流量路径：

```
Pod → PSC Endpoint (:3306) → Service Attachment → Cloud SQL
```

### 场景 2: Cloud SQL Auth Proxy (Port 3307)

```yaml
# 应用通过 Auth Proxy 连接
# Auth Proxy sidecar 或独立代理
DB_HOST=localhost  # 本地代理
DB_PORT=3306       # 代理本地端口
```

如果使用 Cloud SQL Auth Proxy（Sidecar 模式或独立代理），Auth Proxy 会在 3307 端口监听，然后转发到 Cloud SQL：

```
Pod → Auth Proxy (:3307) → PSC Endpoint → Service Attachment → Cloud SQL
```

### 场景 3: Managed Connection Pooling (Port 3306)

Cloud SQL 的托管连接池功能也使用 3306 端口：

```
Pod → Connection Pool → PSC Endpoint (:3306) → Cloud SQL
```

## 网络流量示意图

```
                    +------------------+
                    |   Cloud SQL      |
                    |   (Producer)     |
                    +--------+---------+
                             | Port 3306 (MySQL)
                             |
                    +--------v---------+
                    | Service Attachment|
                    +--------+---------+
                             |
                    [PSC Endpoint IP]  ← Consumer VPC
                             |
                    +--------v---------+
                    | PSC Forwarding   |
                    | Rule (3306/3307) |
                    +--------+---------+
                             |
                    +--------v---------+
                    |   GKE Pod        |
                    |                  |
                    | +--------------+ |
                    | | db-app       | |
                    | |              | |
                    | | Port 3306 ◄--|--→ 直接连接
                    | | Port 3307 ◄--|--→ Auth Proxy 代理
                    | +--------------+ |
                    +-----------------+
```

## 实际环境中的发现

用户在生产环境中发现**必须允许 3307 端口**才能连接，这通常意味着：

1. **使用了 Cloud SQL Auth Proxy** - 代理在 Pod 内或 sidecar 模式运行
2. **连接池通过代理** - 应用连接通过代理再到达 PSC 端点
3. **混合架构** - 部分连接使用 Auth Proxy，部分直接连接

如果只允许 3306 端口而禁止 3307，那么所有通过 Auth Proxy 的连接都会被 NetworkPolicy 阻止，导致连接失败。

## NetworkPolicy 配置建议

根据 Google Cloud 官方建议，PSC 出站规则应该同时包含两个端口：

```yaml
egress:
  # 允许 DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53

  # Cloud SQL PSC 连接
  - to: []
    ports:
    - protocol: TCP
      port: 3306  # 直接连接 / Managed Connection Pooling
    - protocol: TCP
      port: 3307  # Cloud SQL Auth Proxy

  # 其他必要出站
  - to: []
    ports:
    - protocol: TCP
      port: 443
```

## 总结

| 问题               | 答案                                                                                                              |
| ------------------ | ----------------------------------------------------------------------------------------------------------------- |
| 为什么需要 3306？  | 直接连接和 Managed Connection Pooling 使用                                                                        |
| 为什么需要 3307？  | Cloud SQL Auth Proxy 使用                                                                                         |
| 必须两个都允许吗？ | 取决于你的连接方式。如果只用 Auth Proxy，只需 3307；如果只用直接连接，只需 3306。但同时允许两者可以应对所有场景。 |
| 禁止 3307 会怎样？ | 如果应用使用 Auth Proxy，连接会被 NetworkPolicy 拒绝                                                              |

## PostgreSQL PSC 端口说明

根据 [Cloud SQL PostgreSQL PSC 文档](https://cloud.google.com/sql/docs/postgres/about-private-service-connect)，PostgreSQL PSC 支持以下端口：

| 端口     | 用途                                   | 说明                                             |
| -------- | -------------------------------------- | ------------------------------------------------ |
| **5432** | 直接连接 / Managed Connection Pooling  | PostgreSQL 默认端口，原生协议连接                |
| **6432** | PgBouncer (Managed Connection Pooling) | PostgreSQL 托管连接池使用 PgBouncer，端口为 6432 |
| **3307** | Cloud SQL Auth Proxy                   | Auth Proxy 出站连接端口 (与 MySQL 相同)          |

### 关键发现：Auth Proxy 使用 3307 而非 5432

**重要**：Cloud SQL Auth Proxy 对 PostgreSQL 的出站连接使用 **TCP 3307** 端口，而不是 PostgreSQL 默认的 5432 端口。这意味着：

```
GKE Pod → Auth Proxy (本地:5432) → PSC Endpoint (:3307) → Service Attachment → Cloud SQL (:5432)
```

如果你的 NetworkPolicy 只允许 5432 端口，Auth Proxy 的出站连接会被阻止，因为 Auth Proxy 实际连接到 Cloud SQL PSC 端点的 **3307** 端口。

### PostgreSQL NetworkPolicy 配置建议

```yaml
egress:
  # DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53

  # Cloud SQL PSC 连接
  - to: []
    ports:
    - protocol: TCP
      port: 5432   # PostgreSQL 直接连接 / PgBouncer
    - protocol: TCP
      port: 6432   # PostgreSQL Managed Connection Pooling (PgBouncer)
    - protocol: TCP
      port: 3307   # Cloud SQL Auth Proxy (MySQL 和 PostgreSQL 通用)

  # 其他必要出站
  - to: []
    ports:
    - protocol: TCP
      port: 443
```

## 参考链接

- [Private Service Connect overview - Cloud SQL MySQL](https://cloud.google.com/sql/docs/mysql/about-private-service-connect)
- [Private Service Connect overview - Cloud SQL PostgreSQL](https://cloud.google.com/sql/docs/postgres/about-private-service-connect)
  - https://docs.cloud.google.com/sql/docs/postgres/about-private-service-connect#psc-backend
  - The supported serving ports for PostgreSQL are as follows:
  - TCP port 5432 for direct connections to PostgreSQL database server.
  - TCP port 6432 for direct connections to PgBouncer server when using Managed Connection Pooling.
  - TCP port 3307 for connections through Cloud SQL Auth Proxy.
    - https://docs.cloud.google.com/sql/docs/postgres/connect-kubernetes-engine
    - https://docs.cloud.google.com/sql/docs/postgres/connect-kubernetes-engine#proxy-sidecar-pattern
  - https://docs.cloud.google.com/sql/docs/postgres/sql-proxy
    - ![Cloud SQL Auth Proxy - PostgreSQL](https://docs.cloud.google.com/static/sql/images/proxyconnection.svg)
- [Connect to an instance using Private Service Connect](https://cloud.google.com/sql/docs/mysql/configure-private-service-connect)
- [Connect to an instance using Private Service Connect - PostgreSQL](https://cloud.google.com/sql/docs/postgres/configure-private-service-connect)
- [Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/mysql/sql-proxy)
- [Cloud SQL Auth Proxy - PostgreSQL](https://cloud.google.com/sql/docs/postgres/sql-proxy)
- [Managed Connection Pooling - MySQL](https://cloud.google.com/sql/docs/mysql/managed-connection-pooling)
- [Managed Connection Pooling - PostgreSQL](https://cloud.google.com/sql/docs/postgres/managed-connection-pooling)