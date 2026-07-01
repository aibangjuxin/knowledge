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
- **NetworkPolicy 在 Cloud SQL PSC 场景下的**最小公分母**就是 `5432/3306 + 6432（PG Managed Pooling） + 3307`。生产推荐直接照抄"全放"，省事且不会踩新应用迁移的坑。

---

## Java 代码层到底改了啥（IAM 直连 → Auth Proxy）

上面是从"基础设施视角"看的（端口 / NetworkPolicy）。这一节从 **Java 应用代码**视角回答一个更落地的问题：**老应用（IAM Base 直连）和新应用（Auth Proxy）在 Java 里到底改了哪几行代码？**

### 一句话总结

> 老应用是 **JDBC 走 IAM 直连 Cloud SQL**（5432/3306），新应用是 **JDBC 走 localhost:5432 → Auth Proxy → PSC → Cloud SQL:3307**。**业务代码几乎不变，变的全是连接字符串、Credential Provider 和 Pod 部署形态。**

### PostgreSQL JDBC 对照（最小代码差异）

#### 老用户：IAM Base 直连（`5432`）

```java
// 老应用：IAM Base 直连 PSC 端点
String jdbcUrl = "jdbc:postgresql://10.1.1.50:5432/mydb"
    + "?sslmode=require"
    + "&cloudSqlInstance=my-project:asia-east1:my-pg"
    + "&enableIamAuth=true"
    + "&socketTimeout=30";

Properties props = new Properties();
props.setProperty("user", "iam-user@app.iam.gserviceaccount.com");
// 注意：没有 password 字段 — IAM Base 走 ADC（Application Default Credentials）

try (Connection conn = DriverManager.getConnection(jdbcUrl, props)) {
    // 业务代码不变
    try (PreparedStatement ps = conn.prepareStatement("select 1")) {
        ps.executeQuery();
    }
}
```

依赖（`pom.xml`）：

```xml
<!-- 老应用：标准 PostgreSQL JDBC -->
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <version>42.7.3</version>
</dependency>
```

#### 新用户：Auth Proxy Sidecar（`localhost:5432`，但出站走 `3307`）

```java
// 新应用：连本地 Auth Proxy，DB_HOST 永远是 127.0.0.1
String jdbcUrl = "jdbc:postgresql://127.0.0.1:5432/mydb"
    + "?sslmode=disable";   // 注：到 Proxy 这段是明文，不需要 SSL

Properties props = new Properties();
props.setProperty("user", "my-app-user");     // 业务库用户，不再是 IAM principal
props.setProperty("password", System.getenv("DB_PASSWORD"));  // 由 Secret 注入
// 或者用 IAM principal（Auth Proxy 也支持传 instance-unix-socket 或 token，但更常见是直接用 DB 用户密码）

try (Connection conn = DriverManager.getConnection(jdbcUrl, props)) {
    // 业务代码完全不变 — 这就是关键卖点
    try (PreparedStatement ps = conn.prepareStatement("select 1")) {
        ps.executeQuery();
    }
}
```

依赖（`pom.xml`）**不变**：

```xml
<!-- 新应用：还是标准 PostgreSQL JDBC，没换驱动 -->
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <version>42.7.3</version>
</dependency>
```

### 关键差异表（Java 视角）

| 维度                | 老应用：IAM Base 直连                                  | 新应用：Auth Proxy Sidecar                          |
| ------------------- | ------------------------------------------------------ | --------------------------------------------------- |
| **JDBC URL**        | `jdbc:postgresql://<PSC-IP>:5432/...`                  | `jdbc:postgresql://127.0.0.1:5432/...`              |
| **端口（应用视角）** | 5432                                                   | 5432（localhost）                                    |
| **端口（Pod 出站）** | 5432                                                   | **3307**（Auth Proxy → PSC）                         |
| **用户**            | `iam-user@app.iam.gserviceaccount.com`（IAM principal） | 真实 DB 用户，如 `my-app-user`                      |
| **认证凭据**        | ADC / Workload Identity 自动注入                       | Secret 注入的密码，或由 Auth Proxy 用 IAM 自动续期  |
| **SSL**             | `sslmode=require`（直接到 Cloud SQL）                  | `sslmode=disable`（到 Proxy 是内网明文，Proxy→DB 才加密）|
| **驱动**            | 标准 `org.postgresql:postgresql`                       | 标准 `org.postgresql:postgresql`（**没换**）         |
| **业务代码**        | —                                                     | **完全不变**                                        |
| **Pod 多了一个 container** | ❌ 无                                                | ✅ `cloud-sql-auth-proxy` sidecar                  |
| **Workload Identity** | 必须绑在应用 Pod 上                                  | 绑在 Auth Proxy sidecar 上（应用本身不需要）        |
| **NetworkPolicy 出站** | 5432                                                 | **3307**                                            |

### 真正改动的代码量

从 Java 代码角度看，**真正改了 3 行 + 1 个 env 变量**：

```diff
- String host = "10.1.1.50";                  // 老：PSC IP
- String port = "5432";                       // 老：直连端口
- String user = "iam-user@app.iam.gserviceaccount.com";
- String password = null;                     // 老：IAM Base，没密码
+ String host = "127.0.0.1";                  // 新：连本地 Proxy
+ String port = "5432";                       // 新：本地端口（业务看不变）
+ String user = "my-app-user";                // 新：业务库用户
+ String password = System.getenv("DB_PASSWORD");  // 新：从 Secret 注入

// JDBC URL 拼接差异
- String url = "jdbc:postgresql://" + host + ":" + port + "/mydb?sslmode=require&cloudSqlInstance=...&enableIamAuth=true";
+ String url = "jdbc:postgresql://" + host + ":" + port + "/mydb?sslmode=disable";
```

**其他改动都是部署形态，不在 Java 源码里：**

- `Deployment.yaml` 多了一个 `cloud-sql-auth-proxy` sidecar container
- `ServiceAccount.yaml` 多了一段 `iam.gke.io/gcp-service-account: proxy-sa@...iam.gserviceaccount.com` 注解（绑在 Auth Proxy 上）
- `Secret` 里多了 `DB_PASSWORD`

### MySQL 的情况（JPA / HikariCP 视角）

如果你的栈是 Spring Boot + JPA + HikariCP，改动本质上一样，只是配置文件变了：

```yaml
# 老应用 application.yml — IAM Base 直连 MySQL PSC
spring:
  datasource:
    url: jdbc:mysql://10.1.1.60:3306/mydb?sslMode=REQUIRED&cloudSqlInstance=my-project:asia-east1:my-mysql&enableIamAuth=true
    username: iam-user@app.iam.gserviceaccount.com
    password:           # 留空
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      maximum-pool-size: 10

# 新应用 application.yml — 走 Auth Proxy
spring:
  datasource:
    url: jdbc:mysql://127.0.0.1:3306/mydb?sslMode=DISABLED
    username: my-app-user
    password: ${DB_PASSWORD}
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      maximum-pool-size: 10
```

JPA Entity / Repository / Service / Controller **一行都不动**。

### 为什么要这么改？——业务驱动力

| 驱动力                              | 直连模式够用吗 | 走 Auth Proxy 收益                                 |
| ----------------------------------- | -------------- | -------------------------------------------------- |
| 一个集群几百个应用都要连同一个 Cloud SQL | 每个应用都要 Workload Identity + IAM 用户 | Auth Proxy **集中管连接池**，应用只需普通 DB 用户 |
| 短连接 / 突发流量                   | HikariCP 反复 TLS 握手、IAM token 刷新 | Proxy **复用后端长连接**                           |
| 需要在 Cloud Run / Cloud Build / 本地也连同一个 DB | IAM ADC 在 Cloud Run 上要费劲 | Proxy 统一 `INSTANCE_CONNECTION_NAME`，跨环境无差别 |
| 安全合规要求"DB 密码统一轮换"       | IAM 没有密码，绕开需求 | Secret Manager → Proxy → DB，可以做**轮换生效**     |
| 想开 Managed Connection Pooling     | 跟直连冲突   | Proxy 可以跟 PgBouncer 协同                          |

如果你的新用户是被推动切到 Auth Proxy，**大概率是其中一个或多个原因**——而不是基础设施的强制要求。

---

## 验证脚本：到底连的是哪条路径？

下面这段 shell 脚本可以挂在故障 Pod 上运行（或在本地用 `kubectl exec` 远程跑），用于**一次性确认应用当前走的是 IAM 直连还是 Auth Proxy**：

```bash
#!/usr/bin/env bash
# verify-3307-iam-vs-proxy.sh
# 在故障 Pod 所在的节点 / Pod 内运行
# 用法: ./verify-3307-iam-vs-proxy.sh <namespace> <pod-name>

set -euo pipefail

NS="${1:-default}"
POD="${2:?usage: $0 <namespace> <pod-name>}"

echo "===================================================="
echo "  3307 Connection Mode Diagnostic"
echo "  Namespace: ${NS}"
echo "  Pod:       ${POD}"
echo "===================================================="

echo ""
echo "[1/5] Pod containers:"
kubectl get pod "${POD}" -n "${NS}" \
  -o jsonpath='{range .spec.containers[*]}{"  - "}{.name}{" (image="}{.image}{")\n"}{end}'

echo ""
echo "[2/5] Database-related env vars:"
kubectl exec -n "${NS}" "${POD}" -- sh -c \
  'env 2>/dev/null | grep -E "^(DB_|PG|MYSQL|INSTANCE_CONNECTION_NAME|GOOGLE_APPLICATION_CREDENTIALS|KSA_|GKE_METADATA_)" \
    | sort' \
  || echo "  (unable to read env — try with auth-proxy sidecar namespace)"

echo ""
echo "[3/5] Active TCP connections from the Pod (PostgreSQL/MySQL):"
kubectl exec -n "${NS}" "${POD}" -- sh -c \
  '(ss -tnp 2>/dev/null || netstat -tnp 2>/dev/null) \
    | grep -E ":(3306|3307|5432|6432)" \
    | head -20' \
  || echo "  (ss/netstat not available in this image)"

echo ""
echo "[4/5] Detecting Auth Proxy presence:"
HAS_PROXY=$(kubectl get pod "${POD}" -n "${NS}" \
  -o jsonpath='{.spec.containers[*].name}' 2>/dev/null \
  | grep -E "(cloud-sql-auth-proxy|cloudsql-proxy|auth-proxy)" || true)

if [[ -n "${HAS_PROXY}" ]]; then
  echo "  ✅ Auth Proxy sidecar detected: ${HAS_PROXY}"
  echo "     → Connection path is: app → 127.0.0.1:5432 → proxy → PSC:3307 → Cloud SQL"
  echo "     → NetworkPolicy MUST allow egress TCP/3307"
else
  echo "  ❌ No Auth Proxy sidecar in this Pod."
  echo "     → If DB_HOST is PSC IP, connection is IAM Base direct (5432/3306)."
  echo "     → If DB_HOST is 127.0.0.1, you are missing the sidecar — connection will fail."
fi

echo ""
echo "[5/5] NetworkPolicy in this namespace:"
kubectl get netpol -n "${NS}" \
  -o custom-columns='NAME:.metadata.name,POD-SELECTOR:.spec.podSelector,EGRESS-PORTS:.spec.egress[*].to[*].ports[*].port' \
  2>/dev/null || echo "  (no NetworkPolicy in namespace, or rbac denied)"

echo ""
echo "===================================================="
echo "  Decision:"
if [[ -n "${HAS_PROXY}" ]]; then
  echo "    ✅ NetworkPolicy egress MUST include TCP/3307"
else
  echo "    ℹ️  NetworkPolicy egress only needs TCP/5432 (PG) or TCP/3306 (MySQL)"
  echo "        unless other Pods in this namespace use Auth Proxy."
fi
echo "===================================================="
```

### 一行速查版（贴在故障排查群里）

```bash
# 一眼看出 Pod 走的什么模式
POD=mypod; NS=myns
echo "Containers: $(kubectl get pod $POD -n $NS -o jsonpath='{.spec.containers[*].name}')"
echo "DB_HOST:    $(kubectl exec -n $NS $POD -- sh -c 'echo ${DB_HOST:-${PGHOST:-${MYSQL_HOST:-unset}}}')"
echo "DB_PORT:    $(kubectl exec -n $NS $POD -- sh -c 'echo ${DB_PORT:-${PGPORT:-${MYSQL_PORT:-unset}}}')"
echo "→ 如果 Containers 含 cloud-sql-auth-proxy + DB_HOST=127.0.0.1：走 Proxy，必须放 3307"
echo "→ 如果 Containers 没有 proxy + DB_HOST=PSC IP：直连，只需放 5432/3306"
```

### Java 验证代码：跑一次就懂

下面这段 Java 程序可以在 IDE / 容器里直接跑（前提是 `psql` / `mysql` client 装好），用来**直观看到 5432 vs 3307 出站端口的实际行为差异**：

```java
// VerifyPort3307.java
// 编译: javac VerifyPort3307.java && java VerifyPort3307
// 作用: 用 Socket 直连两种模式的 endpoint，把"出站用的是哪个端口"打印出来

import java.io.*;
import java.net.*;

public class VerifyPort3307 {
    public static void main(String[] args) throws Exception {
        // 模拟两种场景
        String[][] cases = {
            // {label, host, port}
            {"IAM 直连 PG (老)", System.getenv().getOrDefault("PSC_IP_PG", "10.1.1.50"), "5432"},
            {"Auth Proxy PG (新)", "127.0.0.1", "5432"},     // 应用视角是 5432
            // 真实出站的 3307 由 Auth Proxy 进程完成（不在 Java JVM 里）
        };

        for (String[] c : cases) {
            String label = c[0], host = c[1], port = c[2];
            System.out.println("\n=== " + label + " ===");
            System.out.println("  target: " + host + ":" + port);
            try (Socket s = new Socket()) {
                s.connect(new InetSocketAddress(host, Integer.parseInt(port)), 3000);
                System.out.println("  ✅ TCP connect OK — JVM 出站端口 = " + s.getLocalPort());
                System.out.println("     → 这一步 IAM Base 直连就结束了 (5432)");
                System.out.println("     → Auth Proxy 模式下 JVM 是到这里 (5432)");
                System.out.println("     → 真正的 3307 出站发生在 Auth Proxy 进程，JVM 看不到");
            } catch (Exception e) {
                System.out.println("  ❌ " + e.getClass().getSimpleName() + ": " + e.getMessage());
            }
        }

        System.out.println("\n=== 关键结论 ===");
        System.out.println("Java JVM 出站永远是 5432/3306（应用配置的端口）。");
        System.out.println("Auth Proxy 进程才是出 3307 的那一跳。");
        System.out.println("NetworkPolicy 看不到 JVM 内的连接，它看的是 Pod 内所有进程的出站——");
        System.out.println("只要 Pod 内跑了 Auth Proxy，就必须在 Pod 级别放 3307。");
    }
}
```

> 真正能"证明 3307 出站"的方式不是 Java，而是 **Pod 内的 Auth Proxy 进程 + `ss -tnp`**。Java 只负责连 `127.0.0.1:5432`，它自己永远不出 3307。

---

## Sidecar 配置安全校验清单（cloud-sql-proxy 2.11.4）

这一节针对一个非常常见的**生产反模式**——也是我们实际提供给老用户的模板里**真实存在**的问题：

```yaml
# 我们的旧模板（有缺陷）
cloudSqlProxy:
  image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4
  args:
    - "--psc"
    - "--structured-logs"
    - "--auto-iam-authn"
    - "--address=0.0.0.0"                       # ⚠️ 隐患 1：监听所有接口
    - "--port=[DB_PORT1]"                       # ⚠️ 隐患 2：模板里 --port 写了两次
    - "[INSTANCE_PROJECT:REGION:SQL_INSTANCE_NAME]"
    - "--port=[DB_PORT2]"                       # （cloud-sql-proxy 不支持这种语法）
    - "[INSTANCE_PROJECT:REGION:SQL_INSTANCE_NAME]"
```

老用户替换占位符后的**实际配置**：

```yaml
cloudSqlProxy:
  image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4
  args:
    - "--psc"
    - "--structured-logs"
    - "--auto-iam-authn"
    - "--address=0.0.0.0"
    - "--port=5432"                             # PostgreSQL 原生端口
    - "my-project:asia-east1:my-pg"
    - "--port=5433"                             # 第二个端口
    - "my-project:asia-east1:my-pg2"
```

**这一节会逐项校验每个 flag，给出反推出来的"为什么老用户能连、新用户不能连"根因，并给出统一走 3307 的新模板。**

### 1. 模板的 4 个具体隐患

#### 隐患 1：`--port` 出现两次是非法用法

根据 [cloud-sql-proxy 官方 README](https://github.com/GoogleCloudPlatform/cloud-sql-proxy#configuring-port)：

> *"When specifying multiple instances, the **port will increment from the flag value**."*

也就是说 cloud-sql-proxy **只承认第一个 `--port`**，多 instance 时后续 instance 端口 = `--port + 1`、`--port + 2`...

```bash
# 官方示例：--port 5432 + 2 个 instance → 5432 / 5433
cloud-sql-proxy --port 5432 instance-a instance-b
# 等价于
cloud-sql-proxy instance-a?port=5432 instance-b?port=5433
```

**所以你那个模板里写两次 `--port` 的行为是未定义的**——取决于 cloud-sql-proxy 版本，可能（a）只认第一个，5433 完全无效；（b）启动报错；（c）以不可预测方式工作。无论哪种，**模板本身就不该这么写**。

正确写法是 **`?port=` query param**（每 instance 独立配置端口）：

```yaml
args:
  - "--psc"
  - "--structured-logs"
  - "--auto-iam-authn"
  - "--address=127.0.0.1"
  - "my-project:asia-east1:my-pg?port=5432"      # ✅ 用 ?port= 指定
  - "my-project:asia-east1:my-pg2?port=5433"     # ✅ 而不是 --port 写两次
```

#### 隐患 2：`--address=0.0.0.0` 在 Sidecar 模式下不必要且不安全

详见上文（"同 Pod 多容器扩展性"那一段）。Sidecar 模式下应用只需 `127.0.0.1`，`0.0.0.0` 等于把 DB 入口暴露给 Pod 内所有进程。

#### 隐患 3（隐藏的最严重一条）：模板让 proxy 监听在**数据库原生端口**，绕过了 3307 约定

这是**老用户能连、新用户不能连的真正根因**。

老用户的 proxy 配置：`--port=5432` + `--port=5433`，**监听的是 PostgreSQL 原生端口**。这意味着：

```
老用户：
  app (java) → 127.0.0.1:5432 → proxy (Pod 内 5432) → Cloud SQL PG 原生协议
  
新用户（官方推荐）：
  app (java) → 127.0.0.1:3307 → proxy (Pod 内 3307) → Cloud SQL
```

**对 NetworkPolicy 来说：**
- 老应用的 Pod 出站端口 = **5432**（app → proxy）→ NetworkPolicy 只需放 5432
- 新应用的 Pod 出站端口 = **3307**（app → proxy）→ NetworkPolicy 必须放 3307

如果同一 NS 里两种模式混部，运维按"老规则"只放 5432，新应用就立刻断。

**这就是你说的"老用户能连、新用户不能连"——不是 Cloud SQL 改了模式，不是 NetworkPolicy 改严了，而是老模板让 proxy 模拟了"原生数据库端口"，绕过了行业统一的 3307 约定。** 模板的不一致是表象，**端口选择的不一致**才是根因。

#### 隐患 4：`--auto-iam-authn` 配 `--port=5432` 在语义上是错位

`--auto-iam-authn` 的设计目的是让 proxy **代表应用去换取 IAM token**，替代用户密码。这一行为**与监听端口无关**，但**和"对外暴露的协议"强相关**：

- proxy 监听在 `3307` → 这是 Cloud SQL Auth Proxy 标准端口，对外是 **Cloud SQL Auth Proxy 协议**（本质是 PostgreSQL 原生协议 + TLS 包装 + IAM 鉴权握手）。
- proxy 监听在 `5432` → 对外是 **PostgreSQL 原生协议**，客户端用 `psql` / `pgx` 直连，proxy 在背后"假装成 PostgreSQL 服务器"，把 IAM token 注入到 startup packet 里。

**这两种模式都能工作**，但：
1. 3307 模式是 Cloud SQL 团队**官方推荐**路径，文档、SLA、故障排查路径都围绕它设计。
2. 5432 模式让应用代码"看起来跟直连一模一样"——但底层其实是 proxy 在做 IAM 注入，对**应用透明**。

你的老模板选择了"5432 透明模式"，**短期内业务代码改动最少**；但**长期让团队失去了"通过端口判断连接模式"这一诊断信号**——NS 里所有 Pod 出站都是 5432，运维永远不知道 proxy 在不在 Pod 里，直到出故障。

### 2. 反推：老用户能连、新用户不能连的完整因果链

```
┌─────────────────────────────────────────────────────────────────┐
│ 老用户 (旧模板生成的 Pod)                                        │
│  app --(5432)--> proxy(127.0.0.1:5432) --(3307)--> PSC --(5432)--> Cloud SQL PG│
│                                       ▲                                  │
│                                       │                                  │
│                              Pod 内端口 (5432)                           │
│                              Pod 出站 (5432)                            │
│                              → NetworkPolicy 放 5432 ✅                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 新用户 (官方推荐 3307 模式 Pod)                                  │
│  app --(3307)--> proxy(127.0.0.1:3307) --(3307)--> PSC --(5432)--> Cloud SQL PG│
│                                       ▲                                  │
│                              Pod 内端口 (3307)                           │
│                              Pod 出站 (3307)                            │
│                              → NetworkPolicy 必须放 3307 ❌ 如果只放 5432 则断 │
└─────────────────────────────────────────────────────────────────┘
```

| 维度              | 老用户 (旧模板 5432)         | 新用户 (官方 3307)            |
| ----------------- | ---------------------------- | ----------------------------- |
| Pod 内 app→proxy  | 5432                         | 3307                          |
| Pod 出站 (NetworkPolicy 看的) | 5432                | **3307**                      |
| proxy→PSC         | 3307                         | 3307                          |
| 业务代码差异       | JDBC URL = 5432              | JDBC URL = 3307              |
| 监听地址           | `0.0.0.0:5432` (旧模板)      | `127.0.0.1:3307` (新模板)    |
| 多 instance 端口配置 | `--port` 写两次 (非法)     | `?port=` query param (合法)  |

**现象总结**：
1. 旧模板让所有老应用**统一走 5432** → NetworkPolicy 永远只需 5432 → 团队形成"Cloud SQL = 5432"的肌肉记忆。
2. 新应用按官方走 3307 → 出站端口变成 3307 → 老 NetworkPolicy 模板漏掉 → 新应用断。
3. 运维的第一反应是"NetworkPolicy 是不是改严了 / Cloud SQL 是不是改了模式"——**真正的根因是模板让老应用绕过了 3307 约定**。

### 3. 你的 4 个具体问题的回答

#### Q1：模板这样写是不是就不对？

**是的，三层都不对：**

| 层级 | 问题 |
|------|------|
| 语法 | `--port` 写两次是 cloud-sql-proxy 不支持的语法，应改用 `?port=` query param |
| 监听 | `--address=0.0.0.0` 在 Sidecar 模式下不必要且不安全 |
| 架构 | **让 proxy 监听在 5432 这种"原生端口"上，绕过了 3307 这个统一约定**，导致团队无法用端口判断连接模式 |

#### Q2：如果要使用 3307 端口，模板应该怎么定义？

新模板：

```yaml
cloudSqlProxy:
  image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4
  args:
    - "--psc"
    - "--structured-logs"
    - "--auto-iam-authn"
    - "--address=127.0.0.1"            # ✅ Sidecar 模式必备
    - "--port=3307"                     # ✅ 唯一端口（多 instance 自动 +1，不推荐生产用多 instance）
    - "my-project:asia-east1:my-pg"     # ✅ 只连一个 instance
    # 如果确实需要多 instance：
    # - "my-project:asia-east1:my-pg?port=3307"
    # - "my-project:asia-east1:my-pg2?port=3308"   # 第二个端口 = 3307+1
```

**单一 instance 优先**——一个 sidecar 只连一个 Cloud SQL 实例。如果要连多个，**应该用多个 sidecar 容器**而不是一个 sidecar 监听多个端口。

#### Q3：用户代码/部署模式应该怎么改才能走 3307？

**Java 业务代码侧**（最小改动）：

```yaml
# 老：5432 直连老 proxy
env:
  - name: DB_HOST
    value: "127.0.0.1"
  - name: DB_PORT
    value: "5432"
```

```yaml
# 新：3307 走 Auth Proxy
env:
  - name: DB_HOST
    value: "127.0.0.1"
  - name: DB_PORT
    value: "3307"           # ← 改这一行
  # 其他 (DB_USER / DB_PASSWORD / SSL 模式) 跟之前一样
```

**NetworkPolicy 侧**（统一放行规则）：

```yaml
egress:
  - to: []
    ports:
    - protocol: TCP
      port: 3307            # 必须放：Auth Proxy → PSC
      # 如果还有非 proxy 直连的旧应用，再加 5432
      # - protocol: TCP
      #   port: 5432
```

**强烈建议**：**所有应用统一走 3307**，老应用也把 DB_PORT 改成 3307。这样 NetworkPolicy 只需要一套规则，不再有"5432 vs 3307"的混乱。

#### Q4：3307 + 127.0.0.1 是否更安全 + 解决了问题？

**是的，三个层面的安全收益：**

| 收益维度          | 5432 + 0.0.0.0 (旧)        | 3307 + 127.0.0.1 (新)       |
| ----------------- | -------------------------- | --------------------------- |
| **Pod 内暴露面**  | Pod 内任意进程可访问 5432  | 仅 loopback，业务容器独占   |
| **多容器隔离**    | 同 Pod 其他 sidecar 可访问 | 同 Pod 其他 sidecar 不可访问 |
| **运维可观测性**  | 端口看不出有 proxy 在运行 | 端口 = "我用的是 Auth Proxy" |
| **NetworkPolicy 统一性** | 每个 NS 配置可能不同 | 全公司统一一条 egress 3307 |
| **故障排查信号**  | 5432 是 PostgreSQL 还是 proxy？傻傻分不清 | 3307 = 一眼判断是 Auth Proxy |

**结论：是的，把 proxy 监听在 `127.0.0.1:3307` 一次性解决了三个问题：**

1. **Pod 内 DB 入口最小暴露**（loopback only）
2. **统一 NetworkPolicy 规则**（所有 NS 一条 egress 3307）
3. **运维诊断信号统一**（3307 = 一定有 Auth Proxy）

### 4. 推荐行动清单（按优先级）

1. **【紧急】** 新模板立即改成 `127.0.0.1:3307`，禁止使用 `--port` 写两次的语法
2. **【高优】** NetworkPolicy 模板统一加 `egress TCP/3307`（无论 NS 里是否有 Auth Proxy，统一放行）
3. **【中优】** 老应用灰度把 `DB_PORT` 从 5432/5433 改成 3307，让所有走 proxy 的应用统一端口
4. **【中优】** 启用 `?port=` query param 替代 `--port`，让多 instance 配置显式且可读
5. **【低优】** 补齐 Security Context + Resource Limit + Liveness/Readiness Probe（见下文模板）

### 5. 完整生产模板（修正版：3307 + 127.0.0.1 + 单 instance）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: app-ns
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: app-sa
      containers:
        - name: app
          image: my-app:1.2.3
          ports:
            - containerPort: 8080
          env:
            - name: DB_HOST
              value: "127.0.0.1"
            - name: DB_PORT
              value: "3307"                          # ✅ 统一 Auth Proxy 端口
            - name: DB_USER
              value: "my-app-user@app.iam.gserviceaccount.com"
          securityContext:
            runAsNonRoot: true
            runAsUser: 10001
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            requests: {cpu: 100m, memory: 256Mi}
            limits:   {cpu: 1000m, memory: 1Gi}

        - name: cloud-sql-proxy
          image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4
          args:
            - "--psc"
            - "--structured-logs"
            - "--auto-iam-authn"
            - "--address=127.0.0.1"                  # ✅ Sidecar 模式：loopback only
            - "--port=3307"                          # ✅ 统一 Auth Proxy 端口
            - "my-project:asia-east1:my-pg"          # ✅ 单 instance
          securityContext:
            runAsNonRoot: true
            runAsUser: 1337
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits:   {cpu: 200m, memory: 256Mi}
          livenessProbe:
            tcpSocket: {port: 3307}
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            tcpSocket: {port: 3307}
            initialDelaySeconds: 5
            periodSeconds: 10
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: app-ns
  annotations:
    iam.gke.io/gcp-service-account: app-gsa@my-project.iam.gserviceaccount.com
```

### 6. 旧模板 vs 新模板 对照速查表

| 项目                  | 旧模板（淘汰）                          | 新模板（推荐）                        |
| --------------------- | --------------------------------------- | ------------------------------------- |
| `--address`           | `0.0.0.0`                               | **`127.0.0.1`**                       |
| `--port`              | 写两次（非法）                          | **写一次** + 多 instance 用 `?port=`  |
| 监听端口              | 5432 / 5433（PostgreSQL 原生）           | **3307**（Auth Proxy）                |
| 多 instance           | 不支持                                  | `instance?port=N` 显式                |
| app JDBC URL          | `5432`                                  | **`3307`**                            |
| 业务代码改动          | —                                       | 改 `DB_PORT=3307`                     |
| NetworkPolicy 统一性  | 每 NS 不同                              | **全公司统一 egress 3307**            |
| Pod 内安全            | 任意进程可访问 5432                     | **loopback only**                     |
| 运维诊断信号          | "5432 是不是有 proxy？" 模糊            | **"3307 = 一定有 proxy" 明确**        |
| 老用户能连、新用户不能连？ | ✅ 旧模板下都能连                  | ✅ 新模板下都能连（且端口一致）        |

### 7. 一句话结论

> 旧模板的真正问题不是"配置不优雅"，而是**让 proxy 监听在 PostgreSQL 原生端口 (5432/5433) 上**，**绕过了 Cloud SQL Auth Proxy 的统一端口约定 3307**。这导致：
>
> 1. 老应用的 Pod 出站端口 = 5432，NetworkPolicy 只需要放 5432
> 2. 新应用按官方走 3307，Pod 出站端口 = 3307，NetworkPolicy 必须放 3307
> 3. 同一 NS 混部时，**两种端口规则互相打架**，新应用断连
>
> **解决方式不是"放行更多端口"，而是"统一端口"**：所有应用 + 所有模板都改用 `127.0.0.1:3307`，NetworkPolicy 全公司只放一条 egress 3307，问题一次性消失。

---

## 附：原 Sidecar 配置校验清单（保留作历史对照）

> 上一节完整重写后，下面这一段是**第一次追加时的初版校验清单**，保留作为历史对照，方便你 diff 看迭代轨迹。如果不需要可以删掉。

### 1. 逐项 Flag 评估（初版）

```yaml
cloudSqlProxy:
  image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4
  args:
    - "--psc"                      # PSC 模式（不是 Service Attachment / Private IP）
    - "--structured-logs"
    - "--auto-iam-authn"           # 用 IAM token 鉴权
    - "--address=0.0.0.0"          # ⚠️ 监听所有接口
    - "--port=3307"
    - "my-project:asia-east1:my-pg"
```

**这一节会逐项校验每个 flag，并给出一个生产可用的"安全模板"。**

### 1. 逐项 Flag 评估

| Flag | 你的值 | 评估 | 说明 |
|------|--------|------|------|
| `--psc` | ✅ 启用 | **正确** | PSC 模式下，proxy 必须通过 Service Attachment / Endpoint IP 连 Cloud SQL，不能用 Private IP。这跟本文档主场景一致。 |
| `--structured-logs` | ✅ 启用 | **推荐** | 输出 JSON 结构化日志，方便 Cloud Logging / Loki 解析。生产必开。 |
| `--auto-iam-authn` | ✅ 启用 | **正确**（前提条件见下） | 让 proxy 自动用 ADC token 鉴权 DB 用户。但**生效前提**：GKE Pod 必须有 Workload Identity，KSA 绑了 `roles/cloudsql.client` 的 GSA。 |
| `--address=0.0.0.0` | ⚠️ **不建议** | **风险** | 监听 Pod 内所有网络接口。Sidecar 模式下，**改成 `127.0.0.1`（默认）更安全**。`0.0.0.0` 会让 Pod 内其他非应用进程也能访问 DB 代理端口，违反最小权限。 |
| `--port=3307` | ✅ 启用 | **正确** | Auth Proxy 端口 3307。**注意**：这跟 `--address` 是配套的，监听在 `0.0.0.0:3307` 还是 `127.0.0.1:3307`，本质不同。 |
| instance 连接名 | ✅ 正确 | **正确** | `project:region:instance` 三段式。 |
| `--private-ip` | ❌ 没加 | **正确（不要加）** | 你走的是 PSC，加 `--private-ip` 会让 proxy 尝试走 Private IP 路径，跟 PSC 冲突。 |

### 2. ⚠️ 关键风险：`--address=0.0.0.0` 在 Sidecar 模式下

这是这一节**最重要的一行**，值得单独展开：

**Sidecar 模式下，`--address=0.0.0.0` 是不安全的默认。**

为什么？

```
┌──────────────────────────────────────────────────────────┐
│ Pod                                                       │
│                                                            │
│   ┌────────────────┐         ┌──────────────────────┐    │
│   │  app (java)    │         │ cloud-sql-proxy      │    │
│   │  connects to   │────────▶│ listens on:          │    │
│   │  127.0.0.1:3307│         │  ❌ 0.0.0.0:3307     │    │
│   └────────────────┘         └──────────────────────┘    │
│                                          ▲                 │
│                                          │                 │
│                              ┌───────────┴──────────┐     │
│                              │ 任意同 Pod 进程     │     │
│                              │ (调试 sidecar、     │     │
│                              │  exec 进去的 shell) │     │
│                              │ 都能访问 3307        │     │
│                              └──────────────────────┘     │
└──────────────────────────────────────────────────────────┘
```

具体风险：

1. **Pod 内横向移动**：如果攻击者通过 RCE、SSRF、`kubectl exec` 权限失陷等手段进入 Pod 内任意一个进程（包括 sidecar、init container、未来加入的调试容器），都能直接访问 DB 代理端口，绕过应用层认证。
2. **同 Pod 多容器扩展性问题**：今天你"每个 Deployment 自带 sidecar"，未来如果有运维 Pod（debugger / network-tooling）跟应用 Pod 同 Pod，`0.0.0.0` 会暴露 DB 入口给这些非业务容器。
3. **违背最小权限原则**：Sidecar 模式的整个设计假设就是"应用 ↔ 本地 proxy"，地址应严格限制在 loopback。

**正确做法**：

```yaml
- "--address=127.0.0.1"   # ✅ Sidecar 模式下：只允许 loopback 访问
```

> **什么时候 `0.0.0.0` 是合理的？**
> 当 proxy 跑在**独立 Deployment / DaemonSet** 里，被同 NS 内多个 Pod **共享**时（"共享 proxy"模式）。这种情况下同 NS 的 Pod 通过 ClusterIP / DNS 访问 proxy 服务，必须监听非 loopback 地址。
>
> 但你已经确认"每个 Deployment 自带 sidecar"——所以这条不适用于你。**`127.0.0.1` 才是正确选择。**

### 3. 其他安全检查项

#### 3.1 Workload Identity 是否真的配了？

`--auto-iam-authn` 不会自己工作，必须满足：

```yaml
# ServiceAccount 上必须有这个 annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  annotations:
    iam.gke.io/gcp-service-account: app-gsa@my-project.iam.gserviceaccount.com
---
# GSA 必须有 Cloud SQL Client 角色
# gcloud projects add-iam-policy-binding my-project \
#   --member="serviceAccount:app-gsa@my-project.iam.gserviceaccount.com" \
#   --role="roles/cloudsql.client"
```

> 既然走的是 `--auto-iam-authn`，DB 用户应该是 IAM 用户（不是密码用户）。验证方法：`gcloud sql users list --instance=my-pg`，应该能看到一个 IAM 类型的服务账号用户。

#### 3.2 Pod 安全上下文（Security Context）

sidecar 容器本身需要最小权限运行：

```yaml
securityContext:
  runAsNonRoot: true              # 必须：cloud-sql-proxy 默认 UID 1337
  runAsUser: 1337                 # 镜像内置非 root 用户
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true    # proxy 是 stateless，可开启
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
```

**缺失这一段，Pod 可能被 trivially 提权**——这跟 proxy 监听地址无关，但属于同一份"sidecar 配置审计"。

#### 3.3 Resource Limit

cloud-sql-proxy 自身很轻量，但**必须设 limit**，否则在节点压力下会被 OOM kill 而不会重启：

```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
  cpu: 200m
  memory: 256Mi
```

#### 3.4 Liveness / Readiness Probe

proxy 是 stateless 的，可以加：

```yaml
livenessProbe:
  tcpSocket:
    port: 3307
  initialDelaySeconds: 10
  periodSeconds: 30
readinessProbe:
  tcpSocket:
    port: 3307
  initialDelaySeconds: 5
  periodSeconds: 10
```

否则 proxy 进程挂了不会自动重启（除非 `restartPolicy: Always` 配合 K8s 自动重启整个 Pod，但 TCP probe 更精准）。

### 4. 完整生产模板（可直接复用）

把上面所有检查点合并，给一份"开箱即用"模板：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: app-ns
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: app-sa                    # ← 必须有 WI 注解
      containers:
        # ─── 应用容器 ───
        - name: app
          image: my-app:1.2.3
          ports:
            - containerPort: 8080
          env:
            - name: DB_HOST
              value: "127.0.0.1"                   # ← 永远连本地 proxy
            - name: DB_PORT
              value: "3307"
            - name: DB_USER
              value: "my-app-user@app.iam.gserviceaccount.com"  # IAM 用户
            # 注意：没有 DB_PASSWORD，--auto-iam-authn 自动注入 token
          securityContext:
            runAsNonRoot: true
            runAsUser: 10001
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi

        # ─── cloud-sql-proxy sidecar ───
        - name: cloud-sql-proxy
          image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4
          args:
            - "--psc"                                # PSC 模式
            - "--structured-logs"                    # JSON 日志
            - "--auto-iam-authn"                     # IAM 鉴权
            - "--address=127.0.0.1"                  # ✅ 只监听 loopback
            - "--port=3307"                          # Auth Proxy 端口
            - "--max-sessions=200"                   # 可选：限并发
            - "--max-conn-age=30m"                   # 可选：定期重连
            - "my-project:asia-east1:my-pg"          # instance 连接名
          securityContext:
            runAsNonRoot: true
            runAsUser: 1337                          # proxy 镜像内置 UID
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
          livenessProbe:
            tcpSocket:
              port: 3307
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            tcpSocket:
              port: 3307
            initialDelaySeconds: 5
            periodSeconds: 10
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: app-ns
  annotations:
    iam.gke.io/gcp-service-account: app-gsa@my-project.iam.gserviceaccount.com
```

### 5. 同 NS 内 Pod 间互访的风险评估

你提到了 **"API 之间同一个 NS 下面的 Pod 侦听方式"**——这其实是你提的另一个独立问题：**当 Proxy 监听在 `0.0.0.0` 时，同 NS 内其他 Pod 能不能访问这个 Proxy？**

简短答案：**默认不能**，但有边界条件：

```
Pod A (app + proxy @ 0.0.0.0:3307)  ← 同 NS 的 Pod B 能否访问？
                                       │
                                       ▼
                            Pod B → Pod A IP:3307
                                       │
                                       ▼
                              通常 ❌ 被 NetworkPolicy 拦
```

默认情况下：
- **同一 Pod 内容器共享 network namespace**（loopback 可达，Pod IP 也可达）。所以 `0.0.0.0` 让**同 Pod 的其他容器**也能访问。
- **同 NS 但不同 Pod**：通过 Pod IP 访问，需要 NetworkPolicy 允许 + 没有 NetworkPolicy 时默认允许。
- **不同 NS**：需要 NetworkPolicy + NetworkPolicy 默认拒绝才拦得住。

**因此**：

| 部署形态                                | `0.0.0.0` 是否安全 | 理由 |
| --------------------------------------- | ------------------- | ---- |
| Sidecar（每 Pod 一个 proxy），默认       | ❌ 不安全           | 同 Pod 其他容器 + 调试进程可访问 |
| 独立 Deployment proxy，被多个应用共享   | ✅ 可以             | 这就是设计意图 |
| DaemonSet proxy，节点级共享             | ⚠️ 需配合 NetworkPolicy 严格限制 | 监听 `0.0.0.0` 是必要的，但要靠 NP 控制谁可以访问 |

**对你的场景（每个 Deployment 自带 sidecar）**：必须用 `127.0.0.1`，别用 `0.0.0.0`。

### 6. 速查决策表

| 配置项 | Sidecar 模式（你） | 共享 Proxy 模式 | DaemonSet 模式 |
|--------|--------------------|----------------|----------------|
| `--address` | **`127.0.0.1`** ✅ | `0.0.0.0` | `0.0.0.0` |
| `--port` | `3307` | `3307` 或自定义 | `3307` |
| NetworkPolicy egress | 必须放 3307 | 必须放 3307 | 必须放 3307 |
| NetworkPolicy ingress | 通常不需要 | 必须限制来源 Pod | 必须限制来源 Pod |
| Workload Identity | 必备 | 必备 | 必备 |
| Security Context | 必须有 | 必须有 | 必须有 |
| Resource Limit | 必须有 | 必须有 | 必须有 |

### 7. 一句话结论

> 你贴的配置里 `--psc / --structured-logs / --auto-iam-authn / --port=3307` 这四项**都是正确的**，**唯一需要修改的就是 `--address=0.0.0.0` 改成 `--address=127.0.0.1`**，因为你的部署形态是 Sidecar（每个 Deployment 自带 proxy），不是共享 Proxy。
>
> 另外强烈建议补齐 **Security Context + Resource Limit + Liveness/Readiness Probe** 三件套——否则即使监听地址对了，Pod 仍可能在被入侵时缺乏纵深防御。