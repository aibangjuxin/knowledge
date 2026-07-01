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
| 为什么需要 3307？  | Cloud SQL Auth Proxy 使用（MySQL 和 PostgreSQL 通用，3307 是 Auth Proxy 专用端口，与底层 DB 类型无关）              |
| 必须两个都允许吗？ | 取决于你的连接方式。如果只用 Auth Proxy，只需 3307；如果只用直接连接，只需 3306。但同时允许两者可以应对所有场景。 |
| 禁止 3307 会怎样？ | 如果应用使用 Auth Proxy，连接会被 NetworkPolicy 拒绝                                                              |
| 老用户能连、新用户不能连？ | 不是目的端（Cloud SQL）改了模式，是 Consumer 端从 IAM 直连（5432/3306）切换到了 Auth Proxy Sidecar（3307）。详见下文。 |

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

---

## 现象补遗：老用户能连、新用户必须开 3307

> 这一节是文档已发布后，根据生产环境的真实踩坑补充的"现象解释"，对应一个非常常见的认知误区：**以为是目的端（Cloud SQL）改了配置或模式，其实是 Consumer 端的连接客户端模式发生了变化。**

### 现象描述

同一套 GKE 集群、同一套 NetworkPolicy、同一组 PSC Forwarding Rule，运维反馈：

- **老用户/老应用**（以前一直能连）：从未放开过 3307，照样可以连接 PostgreSQL。
- **新用户/新应用**（同样未放开 3307）：连接 PostgreSQL 失败，必须把 NetworkPolicy 的出站规则加上 3307 端口才能恢复。
- **本地 GKE Pod 用 IAM Base 直连 PostgreSQL**（PostgreSQL PSC 直连方式）：以前没问题，现在不开 3307 也不行了。

### 根因：不是目的端改了，是 Consumer 端连接模式变了

Cloud SQL 这一侧（PSC Service Attachment 端）长期只接受三个端口的入站：PostgreSQL 是 `5432 / 6432 / 3307`。它不会"偷偷把入站端口改成 3307"。

变化的来源在 **Consumer（Pod/客户端）一侧的连接方式**：

| 维度              | 老用户 / 以前的工作模式                                              | 新用户 / 现在的故障模式                                          |
| ----------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------- |
| 连接客户端        | **Cloud SQL Connector（go-sql-driver/mysql、pgx 等原生驱动直连）**    | **Cloud SQL Auth Proxy**（Sidecar 或独立 Deployment）            |
| 鉴权方式          | IAM Database Authentication（IAM Base）                              | IAM / OAuth Token（Auth Proxy 自己持有/refresh token）           |
| Pod → PSC 出站端口 | **5432 / 3306**（原生协议）                                          | **3307**（Auth Proxy 固定使用 3307，不管底层是 MySQL 还是 PG）   |
| NetworkPolicy 要求 | 允许 5432/3306                                                      | 必须允许 3307                                                    |
| 连接链路示例       | `Pod → PSC EP(:5432) → SA → Cloud SQL`                              | `Pod → Auth Proxy(:5432 localhost) → PSC EP(:3307) → SA → Cloud SQL` |

**所以本质上：老用户能连，是因为他们走的是直连路径，出站是 5432/3306；新用户不能连，是因为他们切到了 Auth Proxy，Auth Proxy 固定从 Pod 出 3307。NetworkPolicy 把 3307 拦了，于是新用户的 Pod 内的 Auth Proxy 就连不上 PSC 端点了。**

### 为什么 IAM Base 直连（5432）现在也开始要求 3307？

如果你的"老应用"以前确实是 IAM Base 直连 PostgreSQL（5432）并且一直可用，但现在它所在的命名空间把 NetworkPolicy 加严了，**并且这个命名空间里同时还有走 Auth Proxy 的新应用**：

- 平台/安全策略往往会做"**最大覆盖原则**"：为了避免漏放，把同一个命名空间里所有已知 Cloud SQL 相关端口（5432 / 6432 / 3307）一起允许。
- 反过来，如果你为了**收紧**而把 NetworkPolicy 改成"只放 5432，移除 3307"，那么这个命名空间里跑 Auth Proxy 的应用就会立即断。
- 如果是**新建命名空间**并且沿用了旧模板（只放 5432），那么所有走 Auth Proxy 的新应用都会断。

因此：
- **直连 IAM Base 的应用，单独看仍然只需要 5432/3306**。
- **但如果所在命名空间里有任何应用走 Auth Proxy，命名空间级别的 egress 必须放 3307**。
- 现象上看到的"本地 GKE Pod IAM Base 直连以前可以、现在不开 3307 不行"，**往往是 NetworkPolicy 的范围（namespace/podSelector）已经覆盖了 Auth Proxy Pod**，而不是 IAM Base 直连本身需要 3307。

### 排查方法（如何快速判断到底是哪条路径）

在故障 Pod 上执行：

```bash
# 1. 看 Pod 里有没有 cloud-sql-auth-proxy 这个 container
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].name}'
# 期望输出含 cloud-sql-auth-proxy 或类似的 Auth Proxy 容器名

# 2. 看应用配置是连 localhost 还是直连 PSC IP
kubectl exec <pod> -n <ns> -- env | grep -E '^(DB_|PG|MYSQL|INSTANCE_CONNECTION_NAME)'

# 3. 看连接是走哪个端口
kubectl exec <pod> -n <ns> -- sh -c "cat /etc/config/* 2>/dev/null; printenv | grep -i port"

# 4. 看 Pod 当前的 NetworkPolicy 是否生效（谁拦了 3307）
kubectl get netpol -n <ns>
```

判定矩阵：

| 看到的现象                                                | 实际连接模式                          | 需要放行的端口                |
| --------------------------------------------------------- | ------------------------------------- | ----------------------------- |
| Pod 没有 Auth Proxy sidecar，DB_HOST 是 PSC IP            | IAM Base 直连                         | 5432（PostgreSQL）/ 3306（MySQL） |
| Pod 里有 Auth Proxy sidecar，DB_HOST 是 localhost/127.0.0.1 | 走 Auth Proxy，再由 Proxy 出 3307    | **必须 3307**                 |
| 命名空间里两种应用混部                                    | 两种模式共存                          | 5432 / 3306 / 3307 都放       |

### 结论

- **3307 不是数据库端口，是 Auth Proxy 端口**。MySQL/PostgreSQL 的 Auth Proxy 都用 3307。
- 所谓的"目的端改了工作模式"是个误判——**Cloud SQL 这一侧从来没有改过它的入站端口列表**，变的始终是 Consumer 端把连接方式从直连切换到了 Auth Proxy。
- NetworkPolicy 在 Cloud SQL PSC 场景下的**最小公分母**就是 `5432/3306 + 6432（PG Managed Pooling） + 3307`。生产推荐直接照抄"全放"，省事且不会踩新应用迁移的坑。