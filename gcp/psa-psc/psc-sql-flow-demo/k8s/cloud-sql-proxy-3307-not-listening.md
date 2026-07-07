# Cloud SQL Auth Proxy Sidecar — 3307 真的在 Listen 吗？排查真相清单

> **本文核心结论(写在前头,让你不用读完就能动手)**:
>
> **3307 出现在网络策略里,不是因为 Pod 内有人 listen 它,而是因为目的端服务器真的在侦听 3307**。
>
> 链路图:
> ```
> Pod (app:db, listen=5432)  →  [NS NetworkPolicy 管控这一段]  →
>   auth-proxy 出 pod (dial)  →
>     PSCEP IP (192.168.64.104:3307) →
>       [目的端 = Cloud SQL PSC Service Attachment, 只 listen 3307]
> ```
>
> 所以 **`NS 的 egress 必须放行 3307`** —— 即便你的 Pod 内 listen 的可能是 5432 / 3306 / 其它。**NetworkPolicy 不是按"Pod 内 listen 谁"配置,是按"Pod 出 Pod 的目标 server 端口"配置。** 你的 `app=db` egress 没配 3307 = 客户端出不去 = `dial tcp ...:3307: i/o timeout`。
>
> ---
>
> 本文承接 [`why-psc-netpolicy-3307.md`](./why-psc-netpolicy-3307.md)（为什么 NetworkPolicy 要放 3307）和 [`sql-3307-template.md`](./sql-3307-template.md)（统一 3307 的模板设计），聚焦一个**老用户/新用户都会掉进去的认知陷阱**：
>
> **"我登陆 Pod 执行 `ss -nltp | grep 3307` 没看到 3307 端口 —— 那 3307 怎么工作的？"**
>
> 这是一篇**现场排查实录**。每一条真相都配了**复现命令**和**判断信号**，让你**30 秒内确诊**到底是哪一种情况。
>
> **Bonus 章 §B**:Auth Proxy 的"身份验证"不是 Cloud SQL 服务端做,而是 **cloud-sql-proxy 进程替你做** —— [§B:Auth Proxy 身份验证在哪儿做？](#b-身份验证-是在服务端吗--答案客户端做)

---

## A. 核心一句话：3307 在哪里 listen？(答案)

> **Lex 的人间清醒版总结**(用最朴素的本地-服务端二分):
>
> **本地端口随便(loopback)**,**服务端端口写死**(PSL Service Attachment 只 listen 3307),**所以 NS egress 必须放服务端那个端口** —— 即便你本地连 5432。
>
> 5432 vs 3307 看起来矛盾其实不矛盾 —— 5432 是源端 loopback 端口,3307 是出 pod 的目的端服务端口,两个数字出现在不同位置、不同语义。NetworkPolicy 永远只看后者。

| 位置 | 谁 listen 3307？ | 端口数 | 流量方向 |
| --- | --- | --- | --- |
| **Pod 内**(loopback) | **没有人**。proxy 在 pod 内 listen 的是 `--port=5432` / `3306` / 其它 | 不是 3307 | app → proxy |
| **Pod 出站 → PSCEP**(Consumer VPC 内)| **cloud-sql-proxy 进程**主动 dial,目标 port = 3307 | 3307 这一跳 | proxy → PSCEP |
| **PSCEP → Service Attachment → Cloud SQL** | **Cloud SQL PSC Service Attachment 服务端只 listen 3307** | **3307 是服务端唯一接受 Auth Proxy 流量的端口** | PSCEP → Cloud SQL |

**所以一句话总结**：

> **3307 这个端口号出现的原因 = Cloud SQL PSC 服务端(server side)在那个端口上 listen。** 它不接受任何其它端口的 Auth Proxy 流量(对 PostgreSQL)。客户端这边没法选 —— 必须 dial 3307,服务端才响应。
>
> 整条链路里,3307 这个 port number 是"目的端写死的",不是"客户端写死的",也不是"Pod 内 listen 写死的"。

### 你的现象 = 上面这张表第 2、3 行的实景

```
1. 你 Pod 内 ss -nltp | grep 3307
   → 结果:空。✅完全正常 — 因为 pod 内 proxy listen 的是 5432,不是 3307。

2. proxy 日志:dial tcp 192.168.64.104:3307: i/o timeout
   → 含义:proxy 试图去 dial Consumer VPC 里那个 PSC endpoint 的 3307,
          但包**出不去你的 Pod**。
   → 可能拦包的两层:
      a) Namespace NetworkPolicy (你 NS 是 deny-all 没配 3307)
      b) VPC firewall (拦了 192.168.64.104 出向 / 3307 出向)
      c) 没有路由能到那个 IP(罕见,VPC 没接 PSC attachment 那个 net)
   → 最常见 = a) 你的 NS NetworkPolicy egress 没配 3307。

3. "目的端 listen 3307"的现实证据:
   → cloud-sql-proxy 知道 3307 这个数字,只能通过 SQL Admin API
     pscConfig + proxy `--psc` 标志查出来。
   → 服务端不接受 dial 5432 / 6432 这种 Auth Proxy 流量 —— 你要么
     Auth Proxy 出 3307,要么 server reject。
```

### 一图把这个心智模型立住

```
                         ┌─ 一段 Pod 内的 listen(可 ss 看到) ─┐
                         │                                    │
   +----------------+    │    +----------------------+        │
   | 你的 app       | ───┼──▶ |  cloud-sql-proxy     |        │
   | (Pod 内)       |    │    |  --address=127.0.0.1 |        │
   |  listen=?      |    │    |  --port=5432         |        │
   +----------------+    │    |  --psc               |        │
                         │    +----------┬-----------+        │
                         └──────────────│────────────────────┘
                                        │
                                        │ Pod 出站
                                        │ NetworkPolicy 管控这一段(关键!)
                                        ▼
                         ┌──────────────────────────────┐
                         │ Consumer VPC 内部:           │
                         │   PSCEP IP: 192.168.64.104   │
                         │   Port: 3307 ←服务端写死     │
                         └──────────────┬───────────────┘
                                        │
                                        │ VPC 内部路由 / GCP-managed PSC
                                        ▼
                         ┌──────────────────────────────┐
                         │ Cloud SQL PSC                │
                         │ Service Attachment (服务端)  │
                         │                              │
                         │ listen port = 3307           │
                         │ 仅接受 Auth Proxy 流量       │
                         └──────────────────────────────┘
```

### 直接的修复(对应你 NS 配置现状)

**你的现状**:`NS 是 deny-all + app=db 的 egress 但端口没配置`。这是缺一段：

```yaml
# 缺的:app=db 的 egress 必须包含 3307
egress:
  - to:
      - ipBlock:
          cidr: 192.168.64.104/32      # ← 收紧到 PSCEP IP(从 gcloud sql instances describe 拿)
    ports:
      - protocol: TCP
        port: 3307                     # ← Cloud SQL PSC 服务端 listen 的端口
```

### 这个洞察的"反直觉"

很多人(也包括一开始的 Lex)会本能地以为:

> "**Pod 内的人都用 5432,为什么我要配 3307?** Pod 内 listen 5432 ≠ Pod 出流量目标 3307。**NetworkPolicy 不是配 Pod 内的端口,是配 Pod 出 Pod 的目的服务端端口。**

这个反直觉是 NetworkPolicy 里所有 "Pod listen 5432 但 egress 必须放 3307" 现象的统一解释。不是 bug,不是配置漂移,是 K8s NetworkPolicy **按目的端配置**(egress = 出 Pod 的目标),而不是按源端 listen 配置。

---

## B. 身份验证 是在服务端吗？ (答案:客户端做)

Lex 的核心疑问:

> "对于 Cloud SQL Auth 的代理进行身份验证的选项，那么所谓的这个身份验证其实是在服务端吗？"

**简短答案:身份验证的主操作是 cloud-sql-proxy 进程代替你的应用(client side)去做,Cloud SQL 服务端只负责"接收 token + 验证 token"。**

也就是说 **"Auth Proxy 做验证"** 里的"验证",**不是 Cloud SQL 数据库进程替你做**,**是 cloud-sql-proxy 这个 sidecar 进程在你 Pod 里替你做 token 申请+token 注入**。这点跟"3307 是服务端 listen"完全是两件事、但容易混淆。

### B.0 Lex 的人间清醒版总结(写在前面,把抽象具象化)

Lex 自己已经摸到了这个事实的本质 —— 用极朴素的话翻译成:

> **"我连我的本地 5432，但真正跳转到我的服务端的那个地址（192.168.64.104）的时候，我应该关心我服务端侦听的地址。** 假如说我连本地是 5432，但我服务端侦听的端口是 3307，那么我就必须允许我的 NetworkPolicy 允许流出到 3307 端口。"

把这段话拆成三句可操作的话,就对应到了 NetworkPolicy 配置的全部逻辑:

1. **本地端口随便** —— proxy 在 pod 里 listen 5432 也好、3307 也好、随便一个 65535 以下的数字都行（你 `--port` 配啥就是啥），app 连本地这个端口从来不卡 NetworkPolicy（因为是 loopback，永远 egress 不算到 NS）。
2. **服务端端口是写死的** —— Cloud SQL PSC Service Attachment 只 listen **3307**（对 Auth Proxy 流量）。这个数字**不是你想改就能改**，是 GCP 服务端焊死的。
3. **所以 NS egress 必须放服务端那个端口** —— 即便你本地连 5432 看起来很顺，但 **proxy 跳出 pod 那一刻就要去 dial 192.168.64.104:3307**，而 3307 不在 NS egress 白名单里 = `dial tcp ...:3307: i/o timeout`。

这就是 **§A 的简化版**：本地端口（Loopback）和出 pod 目标端口（远端 Server）是**两件完全独立的事**，NetworkPolicy 永远只看后者。所以 Lex 的"5432 vs 3307 看起来矛盾"其实根本不矛盾 —— **5432 是源端 loopback 端口，3307 是出 pod 的目的端服务端口，两个数字出现在不同位置、不同语义**。

下面把这套事实严格化、放进代码 / 文档链。

### B.0.5 双重角色总表:同一个数字 vs 完全不同语义

把 Lex 这次踩到的关键坑变成一张对照表,把可能混淆的所有"5432 / 3307 / 端口"全部列出来,每个数字在哪个位置、谁 listen/dial、写在哪里:

| 端口号 | 出现位置 | 角色 | 谁 listen 谁 dial | 怎么定的 |
| --- | --- | --- | --- | --- |
| **`5432`** | Pod 内 (loopback) | app → proxy 连接的目标 | **proxy** 在 `127.0.0.1:5432` listen | 你的 deployment `--port=5432` 参数(或 PG 默认) |
| **`5432`** | 出 pod → Cloud SQL | 直连 PG 用的端口(不用 Auth Proxy 场景) | **Cloud SQL** 在 PSCEP listen | Cloud SQL 服务端写死 |
| **`3307`** | 出 pod → Cloud SQL | Auth Proxy 流量的承载端口 | **Cloud SQL** 在 PSCEP listen | Cloud SQL 服务端写死 |
| **`3307`** | Pod 内 (loopback) | **不存在** —— Cloud SQL 没有任何约束要求 proxy 必须 listen 3307 | — | 你可以在 deployment 里让 proxy listen 任意端口(5432/6432/3306/3307 都行) |
| **`443`** | 出 pod → STS / SQL Admin API | proxy 拿 metadata、拿 OAuth token、拿 ephemeral cert | 多个 Google 服务 | 你 Google Cloud 的 metadata.googleapis.com 等 |

**所以**:

- **app 连 127.0.0.1:5432** → 这条线在 Pod 内部,不走 NetworkPolicy
- **proxy 连 192.168.64.104:3307** → 这条线出 Pod,被 NetworkPolicy 管控
- **proxy 还连 metadata.google.internal:443** → 这条线出 Pod,被 NetworkPolicy 管控

**Lex 现在踩的就是第二条没放出来**。第一条(本地 5432)从来没卡 NS。第三条(443),你大概率已经放过了(放 SQL Admin API 拿 cert 的需要),所以你之前没察觉。

### B.0.6 一句话"心智公式"

```
app 在 Pod 内连 本地端口    → NS 不参与 (loopback)
proxy 出 Pod 连 服务端端口  → NS 必须放行那个端口 (egress)
                        ↑
                你配的 NetworkPolicy
                永远只看这一跳
```

**Lex 的精简表达**:

> "**我应该关心我的服务端侦听的地址**(192.168.64.104:3307),**而不是关心我 Pod 内 listen 的端口**。"

用公式表达就是:**`NetworkPolicy.egress` ⊆ { 远端 server listen 端口集合 }**,跟本地 listen 端口没半毛钱关系。

### B.1 官方文档原话(关键)

Cloud SQL IAM Authentication 文档里的核心定义:

> "Automatic IAM database authentication lets you hand off requesting and managing access tokens to an intermediary Cloud SQL connector, such as the **Cloud SQL Auth Proxy** or one of the Cloud SQL Language Connectors. With automatic IAM database authentication, users need to pass only the IAM database username in a connection request from the client. **The connector submits the access token information for the password attribute on behalf of the client.**" —— [Cloud SQL IAM Authentication](https://cloud.google.com/sql/docs/postgres/iam-authentication)

翻译:Automatic IAM 鉴权把 "拿 token + 续 token" 这件事外包给了中间连接器(Cloud SQL Auth Proxy / language connectors)。客户端应用只需要传 IAM 用户名,**OAuth token 由 connector 代为提交,作为密码字段**。

> "IAM database authentication uses OAuth 2.0 access tokens, which are short-lived and valid for only one hour. **Cloud SQL connectors are able to request and refresh these tokens**, ensuring that long-lived processes or applications that rely on connection pooling can have stable connections."

翻译:Auth Proxy 还要负责 token 的 refresh,因为 token 1 小时过期。

### B.2 验证流程的"7 步走"

```
[应用 app]
    │
    │ 1. 启动时: app 启动 psql 连接 "127.0.0.1:5432 db=my_db user=iam-sa@dev.iam.gserviceaccount.com"
    │       ── 注意: app 只传 username,**不传 password**(或者写个 placeholder)
    ▼
[cloud-sql-proxy sidecar --auto-iam-authn]
    │
    │ 2. proxy 启动时,从 metadata server 拿 GSA 的 access token(OAuth 2.0)
    │       (egress 443 → metadata.google.internal) ✅ 你的 NetworkPolicy 必须放
    │
    │ 3. proxy 把这个 OAuth token 在 PostgreSQL/MySQL 协议层作为 PASSWORD 字段
    │       替 app 注入到下一跳 PG/MS 连接
    ▼
[PSCEP:192.168.64.104:3307]
    │
    │ 4. 包经 Consumer VPC 出 pod,经过 Egress NetworkPolicy(必须放 3307)
    │       到 PSC Service Attachment
    │
    │ 5. Cloud SQL PSC SA 把流量 forward 到 Cloud SQL 实例进程
    ▼
[Cloud SQL PostgreSQL/MySQL 实例]
    │
    │ 6. PG/MS 进程收到 OAuth token,
    │       它调用 Google IAM API 验证这个 token:
    │       "持有这个 token 的 GSA 是不是被允许 login 到这个 DB?"
    │       (egress 443 → iam.googleapis.com) ✅ Cloud SQL 服务端做的"验证"
    │
    │ 7. 验证通过 → DB 接受连接 → SET ROLE / GRANT 决定 DB-level 权限
```

**第 2、3 步在 Pod 里(客户端)** 第 6 步在 Cloud SQL 服务端(服务端)。**OAuth 2.0 token 不是密码,但在 PG/MS 协议层被当作"密码"用**。

### B.3 跟"3307 是服务端 listen"对照看(防止混淆)

| 概念 | 在哪发生? | 谁做? | 是配置在哪? |
| ---- | -------- | ----- | --------- |
| **3307 listen** | Cloud SQL PSC Service Attachment | **服务端** | GCP 服务端写死,客户端不能选 |
| **OAuth token 申请** | cloud-sql-proxy 进程(Google STS) | **客户端** | proxy 用 GSA 通过 metadata server 拿 |
| **Token 作为密码注入** | cloud-sql-proxy → Cloud SQL(TLS 上) | **客户端** | --auto-iam-authn 标志行为 |
| **Token 验证** | Cloud SQL 服务端(调 IAM API) | **服务端** | GCP 服务端行为,你看不到 |
| **DB-level GRANT** | Cloud SQL 服务端 | **服务端** | 你用 `gcloud sql users create` / `GRANT` 配 |

**所以"Auth Proxy 做身份验证"** 字面上看像服务端做的,但**实际机制是客户端做的一部分 + 服务端做的一部分**:

| 服务 | 客户端做 (App + Proxy) | 服务端做 (Cloud SQL) |
| --- | --- | --- |
| **TLS 握手** | 客户端 | ✅ |
| **OAuth token 申请** | 客户端 ✅ (proxy 用 WI/GSA 拿) | — |
| **OAuth token 装入连接** | 客户端 ✅ (proxy 注入 PG password 字段) | — |
| **Token 真伪验证** | — | 服务端 ✅ (调 IAM API) |
| **DB-level 权限** | — | 服务端 ✅ (gcloud sql users/GRANT) |

**这个分工就是为什么"Cloud SQL Auth Proxy 减少了 DB 密码泄漏"的核心原因** — 应用根本不需要持有 DB 密码,它甚至不知道 DB 密码是什么;它只持有自己的 GSA token,proxy 再去换 IAM token 提交给 Cloud SQL。

### B.4 客户端行为的具体代码链

如果用 proxy v2.x 源码看(从 `internal/proxy/proxy.go` 读到的 `Token`、`LoginToken` 字段):

```go
// 配置结构体定义
type Config struct {
    // ...
    // Token is the Bearer token used for authorization.
    Token string
    // LoginToken is the Bearer token used for Auto IAM AuthN. Used only in conjunction with Token.
    LoginToken string
    // ...
}
```

也就是说 **proxy 自己持有 2 个 token**:

| 字段 | 用途 |
| ---- | ---- |
| `Token` | proxy 用来调 SQL Admin API 拿 instance metadata + 拿 ephemeral client cert |
| `LoginToken` | proxy 注入到下一跳 PG/MySQL 连接的"密码字段",让 server 验证 IAM |

两个 token 都是 **proxy 自己 mint / refresh**,proxy 是一个 **有状态长跑进程**,每小时跑一次 refresh。

### B.5 "服务端做不做验证"的最终回答

**做,但只做最后一步** (token 真伪校验 + GRANT 级别的 DB 权限校验)。
**不做** 的是 "去申请新的 OAuth token" — 那是 client (proxy) 的工作。

如果你误以为 "Auth Proxy 做身份验证 = 服务端做",会得到这些误解:

| 误解 | 修正 |
| --- | --- |
| "我把 NetworkPolicy egress 设成只允许 443 给 Cloud SQL,就够 IAM 验证用" | 错。443 是 SQL Admin API 调的;3307 是 IAM 鉴权连接的目的端口。两条都得放。 |
| "我给 proxy 配 --auto-iam-authn 之后,Cloud SQL 服务端就去 IAM 拉 token 了" | 错。是 proxy 去 STS 拉 token,服务端只验证。 |
| "我只配 IAM 给 app,proxy 不需要 IAM 权限" | 错。proxy 必须有 GSA 上的 `cloudsql.client` 角色才能调 Admin API 拿 metadata。app 的 IAM 和 proxy 的 IAM 是两件事。 |
| "我去 Cloud SQL 服务端 db 用户的 GRANT 里看,能决定 Auth Proxy 怎么验证" | 错。GRANT 决定 **验证通过之后**给什么权限;**验证本身**靠 IAM,服务端做但不需要 GRANT 配置。 |
| "context-aware access policy 设了就死" | 对——见上面的 "Context-aware access and IAM database authentication" 段落,context-aware access 跟 Auth Proxy + IAM authn 不兼容,**只能用直连**。 |

### B.6 给 Lex 当前环境的直接结论

**Lex 这次踩到的事实跟身份验证的关系**:

```
1. proxy cmdline 里 --auto-iam-authn 在跑
   → proxy 在 Pod 里已经准备好去做 IAM 鉴权的 client 部分
   (OAuth token 申请 + token 注入 PG password)

2. proxy 报 dial tcp 192.168.64.104:3307: i/o timeout
   → 包根本没出 Pod,根本没走到 Cloud SQL 服务端
   → 谈不到"服务端验证 IAM"那一步了

3. 即使 NS 放 3307 通了,dial 成功后,身份验证流程才开跑:
   a) proxy 已经持有 token,直接用
   b) TLS 握手
   c) proxy 把 token 作为 password 发给 Cloud SQL
   d) 服务端调 IAM API 校验 token → 失败/成功
   e) 成功后才有 GRANT 决定的 DB-level 操作

4. 所以目前你**还没到身份验证那一步**,
   你卡在 step 3a 之前的网络层。
   整个验证链要 NS egress 放 3307 + 443 两条才能跑通。
```

NetworkPolicy 必须配置的端口(完整):

| 端口 | 用途 | 触发 | 没放的故障 |
| --- | --- | --- | --- |
| **TCP 443** | proxy 去 SQL Admin API + IAM 拿 metadata/token | proxy 启动 + token refresh 时 | proxy 启动失败 / token 拉不到 / connection refused |
| **TCP 3307** | proxy 去 Cloud SQL PSC endpoint **做身份验证的实际连接** | **每次新连接** | `dial tcp ...:3307: i/o timeout`(你这次的!) |
| (TCP 5432/3306) | optional——如果不用 Auth Proxy / 走直连 | 直连场景 | (不适用) |

**所以结论回答你的问题**:**身份验证不是"服务端一家做",是"客户端 proxy 负责 token 准备 + 服务端 Cloud SQL 负责 token 校验"分工。客户端做事占大头,服务端做事是最后一步的裁决**。而**让你触发"想配 3307"的那个报错,正是 proxy 这个客户端在网络层还没出去——根本都还没到服务端做"最后一步"那一步**。

### B.7 一图总结(client + server 两端各自的角色)

```
                     ┌─────────────────────────────┐
                     │ Pod (Consumer side)         │
                     │                             │
                     │  app  ──password?──→  proxy │
                     │                  │          │
                     │                  │ OAuth    │
                     │                  │ token    │
                     │                  │ mint +   │
                     │                  │ inject   │
                     │                  ▼          │
                     │              127.0.0.1:5432 │
                     │              (loopback)     │
                     │                  │          │
                     │                  │ (PSQL/MySQL handshake)
                     │                  │ over TLS │
                     │             NetworkPolicy   │
                     │             egress:3307     │
                     │             + egress:443    │
                     └──────────────────│──────────┘
                                        │
                                        │ 3307 + 443 egress
                                        ▼
                     ┌─────────────────────────────────────┐
                     │ Cloud SQL (Producer side)          │
                     │                                     │
                     │  PSC Service Attachment            │
                     │  listen 3307   ◄── 只这一条路       │
                     │              │                     │
                     │              ▼                     │
                     │  Cloud SQL 实例进程                │
                     │  ├── 收到 token                ◄───│── 服务端"验证"
                     │  ├── 调 IAM API 验 token 真伪     │   (最后一步)
                     │  ├── 验证 GSA 是否有 cloudsql    │
                     │  │   .instances.login 权限      │
                     │  └── 查 GRANT 表决定 DB-level    │
                     └─────────────────────────────────────┘
```

这段图最关键的两点:
- 左侧(客户端)做事多 — token 申请、token 注入、TLS 握手
- 右侧(服务端)做事少但关键 — token 验证、最终裁定
- **3307 这个 port = 是客户端去向服务端的"通道",决定了"传输层认证资料能不能送达"** —— 这就是为什么 NS egress 必须放 3307 才能让客户端做事到达服务端

---

## 0.0 灵异现象的"完整脸面"

把生产环境的两个直接观测摆在一起看，问题就清楚了：

```bash
# 观测 1：pod 内的 ps aux（你贴的）
USER  PID  COMMAND
65532 1    /cloud-sql-proxy --psc --structured-logs --auto-iam-authn \
                  --address=127.0.0.1 --port=5432 \
                  dev:asia-east2:sql-dev-01

# 观测 2：pod 内 cloud-sql-proxy 容器的报错日志（你贴的）
2026-07-06T11:02:56.494027231Z [dev:asia-east2:sql-dev-01] failed to connect to instance:
Dial error: failed to dial: dial tcp 192.168.64.104:3307: i/o timeout
```

把它们**拼起来看**得到问题的完整图景：

| 步骤 | 发生在哪里 | 谁在做 | 端口是什么 |
| ---- | -------- | ------ | --------- |
| **App → Proxy** | Pod **内部**（loopback） | 你的应用 | **5432**（proxy 听在 5432 是 `ss -nltp` 能看到的） |
| **Proxy → Cloud SQL** | Pod **外部**（Consumer VPC → PSC Endpoint → SA → Cloud SQL） | cloud-sql-proxy 进程 | **3307**（这是 proxy 出 Pod 的目标，pod 内 `ss` **永远看不到**） |

也就是说 **3307 这个端口出现两次、不同语义、不同位置**：

1. **应用 → proxy** 这段是**主动 listen** 的，所以 `ss -nltp` 能看到
2. **proxy → Cloud SQL via PSC** 这段是**主动 dial 的目标端口**，proxy 每次连接新连接都去 dial `192.168.64.104:3307`，日志里看到的就是这一步

**`ss` 看不到 3307 完全正常**——因为 3307 在 pod 内从来就不是 listen 端口，它是 proxy **出 Pod**去 PSC endpoint 的目标端口。

而你的网络防火墙拒绝 `192.168.64.104:3307` 出站时，proxy 就是这个报错（`i/o timeout` 或者 `connection refused`）。

---

## 0. 一个朴素但关键的事实

**Pod 内所有容器共享同一个 Linux Network Namespace**。这是 Kubernetes Pod 模型的基础设计：

> "Every container in a Pod shares the network namespace, including the IP address and network ports. Inside a Pod, containers can communicate with one another using `localhost`." —— [Kubernetes Docs: Pods](https://kubernetes.io/docs/concepts/workloads/pods/)

也就是说：

| 容器       | 看到的 `127.0.0.1` | 看到的 `eth0`（Pod IP） | 看到的 `ss -nltp` |
| ---------- | ------------------ | ----------------------- | ----------------- |
| `app`      | sidecar 的所有 listen 端口 | sidecar 的所有 listen 端口 | sidecar 的所有 listen 端口 |
| `cloud-sql-proxy` | 自己的 + `app` 的端口 | 自己的 + `app` 的端口 | 自己的 + `app` 的端口 |

**`ss` 在 `app` 容器里跑，应该看到 sidecar 的端口**（前提是 sidecar 真在那个端口 listen）。

所以 **`ss` 看不到 3307 这件事本身就是异常信号**。它一定意味着下面 5 个真相中的某一个。

---

## 1. 真相一：`--port` 没生效，proxy 跑在默认端口（5432/3306）

### 0.5. 你贴的 ps aux 已经把答案直接告诉了你 ⬇️

你贴的 `ps aux` 输出：

```
USER     PID  %CPU %MEM   VSZ   RSS   TTY  STAT  START  TIME  COMMAND
65532    1    0.0  0.0  1286584 32120 ?    Ssl   Jul05  0:02  /cloud-sql-proxy \
        --psc --structured-logs --auto-iam-authn \
        --address=127.0.0.1 \
        --port=5432 \
        caep-20118002-appuk-dev:europe-west2:appuk-20118002-sql-dev-01
```

**直接读 cmdline 这三个事实就清楚了：**

| 你以为是 | ps aux 实际写的是 | 后果 |
| -------- | ----------------- | ---- |
| `--port=3307`（你期望的） | `--port=5432` | proxy listen 在 5432，`ss` 永远看不到 3307 |
| `appuk-20118002-sql-dev-01` 看起来名字里有 sql（暗示 MySQL） | `-sql-` 是 PostgreSQL 实例，instance name 末尾 `-01` 是常见命名规约 | proxy 用 SQL Admin API 查 metadata 后确认是 POSTGRES → 走 PG 默认端口分支（即使没显式 `--port`，也会 5432；你又显式给了 `--port=5432`，互相印证） |
| 启动时间是 `Jul05 0:02`，pod 一直是 stable（Ssl 状态） | proxy 进程**稳得很**，没 crash、没在循环重启、不是真相 #4 | 真相 #4 排除 |

> **结论**：你的 Pod 命中了 **真相 #1**。Pod 里 listen 的就是 5432，应用要连 5432，**根本不存在 3307（作为 listen 端口）**。
>
> **但同时**：proxy 在另一端要 dial `192.168.64.104:3307` 去 PSC endpoint —— 这是 **3307 真正出现** 的地方（参见 §0.0）。

### ⭐§0.1 那 3307 到底是谁配的？—— 出 Pod 目标端口的来源

你的疑问是：

> "我没有任何地方在代码里配置 3307，但是 cloud-sql-proxy 报错说它去 dial `192.168.64.104:3307` 了。**这 3307 是哪来的？是 proxy 自己决定的还是 Cloud SQL 服务端配的？**"

简短答案：**是 Cloud SQL 服务端 + cloud-sql-proxy 协同约定，不需要你配。**

详细链路：

#### 出 Pod 的端口来源链

```
[你配的 deployment]
  --port=5432               ← pod 内 listen（应用看，ss 看得见）
  --psc                     ← 关键标志：走 PSC
  INSTANCE_CONNECTION_NAME   ← dev:asia-east2:sql-dev-01
                │
                ▼
[proxy 启动后会调 SQL Admin API]
  GET sqladmin.googleapis.com/sql/v1/projects/dev/instances/sql-dev-01
                │
                ▼
[Admin API 返回 instance metadata, 含 pscConfig]
  { pscConfig: {
      pscEnabled: true,
      pscAutoConnections: [{
        ipAddress: "192.168.64.104"     ← PSC endpoint IP
        ...
      }],
      ...
    },
    ipAddresses: [...]                   ← 还有 PRI/PRIVATE/PSC 三种类型
  }
                │
                ▼
[proxy 用 --psc 标志 → 选 PSC 这条路的 ip + 服务端约定的 port]
  ip   = 192.168.64.104     ← 来自 Admin API 的 pscAutoConnections.ipAddress
  port = ???                ← 来自 Cloud SQL **服务端固定约定**,不由用户配置
                │
                ▼
[proxy 每次新连接 dial 这个 endpoint]
  dial tcp 192.168.64.104:3307    ← 这就是日志里看到的 3307
```

#### 3307 这个 port 哪里来的

**Cloud SQL 服务端（Producer 侧）只接受三种 serving port**，对 PostgreSQL：

| Port | Serving | 配置方 |
| ---- | ------- | ------ |
| **5432** | 直连 PostgreSQL | 服务端固定 |
| **6432** | 直连 PgBouncer (Managed Connection Pooling) | 服务端固定 |
| **3307** | 直连 Cloud SQL Auth Proxy（这是 proxy 给它的"serving port"） | 服务端固定 |

**这三个端口对 Consumer 端（你）是不可选的** —— 它是 Cloud SQL PSC Service Attachment 上 NAG（Network Attachment Group）配置的固定值，跟 Cloud SQL 实例一起创建。

proxy 通过 `--psc` 标志自动选 `3307`（这是 GCP 的约定：PSC + Auth Proxy → 3307）。**你不需要、也没法配置这个端口**。

#### 关键洞察：同一个 `--port` 参数在不同位置是不同东西

| 参数 | 位置 | 谁 listen 谁 dial | 数字来源 |
| ---- | ---- | ----------------- | -------- |
| `--port=5432` 你配的 | **Pod 内** | proxy listen | 你部署侧硬编码 |
| `3307` 在 `dial tcp 192.168.64.104:3307` | **Pod 外** | proxy 去 dial Cloud SQL | Cloud SQL 服务端硬编码 |

简单说：**3307 在 Pod 内的应用层面毫无存在感，3307 只在 proxy → Cloud SQL 这条 Pod 出口流量上出现**。

#### 191.168.64.104 是 Private Service Connect Endpoint IP

你不需要直接 ping 它，但做诊断时要知道：

```bash
# 列出项目里所有 PSC endpoints (PscNetworkEndpointGroup API + addressing endpoint)
gcloud compute networks vpc-access connectors describe  # 跟 PSC 无关

# 直接看 SQL instance 的 PSC config — 里头就是 192.168.64.104 这种内网 IP
gcloud sql instances describe sql-dev-01 --project=dev --format=json \
  | jq '.settings.ipConfiguration.pscConfig'
```

期望输出：

```json
{
  "pscEnabled": true,
  "pscAutoConnections": [
    {
      "consumerNetwork": "projects/dev/global/networks/dev-vpc",
      "ipAddress": "192.168.64.104",        // ← 你看到的 IP 在这里
      "status": "..."
    }
  ]
}
```

如果 `ipAddress` 不是 `192.168.64.104`，说明这个 IP 是在**别的项目**的 VPC 里（不同 environment），proxy 会去找另一个 IP。

#### §0.2 你这次的 `i/o timeout` 报错怎么修

报错是：

```
Dial error: failed to dial: dial tcp 192.168.64.104:3307: i/o timeout
```

`i/o timeout` 在 K8s 出口场景里几乎只有一种意思：**包出了 Pod 到 VPC 路由，**但 Cloud SQL 的 PSC endpoint 没在**应到时间内 SYN-ACK**回来。可能的原因有三个：

| # | 根因 | 信号 | 修复 |
| | ---- | ---- | ---- |
| **A** | **NetworkPolicy 拦截了 3307 出站** | 你 NS 是 deny all，且端口没配 3307 ——**你最可能的根因** | 给应用 Pod 的 egress 加 `port: 3307`，参考 §A 章节 |
| **B** | GKE 节点到 PSC endpoint 的路由层防火墙拦了 | 同一 cluster / 不同 NS 跑出来同样的 dial err，看节点 `gke-xxx` | 检查 VPC firewall rules：有没有 rule 拦 192.168.64.0/24 → 192.168.64.104:3307 |
| **C** | PSC endpoint 被 deleted / 服务端没起来 | `gcloud sql instances describe sql-dev-01` 看 `pscConfig.status` 不是 READY | 等就绪 / 重新启用 PSC |

#### 速查：A 根因的 NetworkPolicy 修复

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-db-egress-3307
  namespace: <你应用的 ns>
spec:
  podSelector:
    matchLabels:
      app: db-app                              # ← 匹配你的 db-app
  policyTypes: ["Egress"]
  egress:
    # DNS
    - to: []
      ports:
        - {protocol: UDP, port: 53}
        - {protocol: TCP, port: 53}

    # Cloud SQL PSC endpoint:必须放 3307
    # IP 192.168.64.104 来自 instance pscConfig.pscAutoConnections.ipAddress
    # 如果同一个 endpoint 在多个 port 都能上,可以全部放(5432/6432/3307)
    - to:
        - ipBlock:
            cidr: 192.168.64.104/32            # ← 收紧到具体 IP(推荐)
            # 也可以放宽到 192.168.64.0/24,但不推荐
      ports:
        - {protocol: TCP, port: 3307}          # ← Cloud SQL proxy serving port

    # cloud-sql-proxy 上 SQL Admin API 拿证书:egress 443(几乎总是要放)
    - to: []
      ports:
        - {protocol: TCP, port: 443}
```

验证：

```bash
# 在 db-app 容器内直接试 TCP 三步握手,不用依赖 proxy 中继
kubectl exec -n <ns> db-app-xxx -c db-app -- \
  bash -c 'timeout 5 bash -c "echo > /dev/tcp/192.168.64.104/3307" && echo TCP_OK || echo TCP_BLOCKED'
```

期望 `TCP_OK` — 代表 NetworkPolicy 已放行。如果 `TCP_BLOCKED`，**NetworkPolicy 里少了 3307 egress**，加回去重 apply。

下面把真相 #1 怎么诊断、怎么修讲透。

### 这是最高频的根因

**官方 v2.x 的默认行为**（见 `GoogleCloudPlatform/cloud-sql-proxy` `cmd/root.go` 的帮助文字）：

> By default, the Proxy will determine the database engine and start a listener on localhost using the default database engine's port, i.e., **MySQL is 3306, Postgres is 5432, SQL Server is 1433**. If multiple instances are specified which all use the same database engine, the first will be started on the default database port and subsequent instances will be incremented from there (e.g., 3306, 3307, 3308, etc). **To disable this behavior (and reduce startup time), use the `--port` flag.**

也就是说：

- **如果你的 deployment 写法是：**

  ```yaml
  - name: cloud-sql-proxy
    image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4
    args:
      - "--psc"
      - "--structured-logs"
      - "--auto-iam-authn"
      - "--address=127.0.0.1"
      # ⚠️  没有 --port
      - "PROJECT:REGION:INSTANCE"
  ```

- **proxy 实际起的是** `127.0.0.1:5432`（如果是 PostgreSQL）或 `127.0.0.1:3306`（如果是 MySQL）。
- 你应用配 `DB_PORT=5432` 才能连上。如果你配 `DB_PORT=3307`，**应用连的是个空端口**——连接会立刻 RST 拒绝。

### 复现命令

```bash
NS=psc-demo
POD=db-app-xxx
kubectl exec -n $NS $POD -c cloud-sql-proxy -- ss -tnlp
```

**期望输出**（根据 engine）：

| 你以为的           | 实际看到的                  | 含义                             |
| ------------------ | --------------------------- | -------------------------------- |
| `LISTEN 0 128 127.0.0.1:3307` | `LISTEN 0 128 127.0.0.1:5432`  | proxy 跑了默认端口，**你的 `--port=3307` 没用上** |

### 触发场景

- **template 变量渲染错误**（`--port={{ .Values.dbPort }}` 因为 values 漏了字段渲染成空串，proxy 用了引擎默认值）
- **args 顺序错了**（cloud-sql-proxy 把 `--port` 当 boolean flag — 它不是，是需要 `=` 的 key-value，`--port 3307` 和 `--port=3307` 都接受，但**两个 `INSTANCE_CONNECTION_NAME` 之间写 `--port` 是非法语法**，见 [`why-psc-netpolicy-3307.md` §Sidecar 配置校验清单](./why-psc-netpolicy-3307.md#sidecar-配置安全校验清单cloud-sql-proxy-2114)）
- **多 instance 没显式 `?port=`**（第一个 instance 拿 5432，第二个 +1 = 5433，但很多 template 以为两个都拿显式 port）
- **平台的 template 漂移：你 template 里写了 `--port=3307`，但前一代 chart / 旧的 ConfigMap / 旧的 values 还在用 `--port=5432`，Pod 是旧版本渲染出来的**（这正是 Lex 这次踩到的）

### 源码级证据：cloud-sql-proxy 内部怎么决定 listen 端口

从 `cloud-sql-proxy` v2.x 源码 `internal/proxy/proxy.go` 直接读到的（v2.23.0 验证）：

```go
type portConfig struct {
    global    int     // ← 你 --port 传进来的值
    postgres  int     // ← 否则 fallback 到 5432
    mysql     int     // ← 否则 fallback 到 3306
    sqlserver int     // ← 否则 fallback 到 1433
}

func newPortConfig(global int) *portConfig {
    return &portConfig{
        global:    global,
        postgres:  5432,
        mysql:     3306,
        sqlserver: 1433,
    }
}

func (c *portConfig) nextDBPort(version string) int {
    switch {
    case strings.HasPrefix(version, "MYSQL"):
        p := c.mysql; c.mysql++; return p
    case strings.HasPrefix(version, "POSTGRES"):
        p := c.postgres; c.postgres++; return p   // ← PG 走这里
    ...
}
```

**这段代码给了三件事的确定性证据：**

1. `--port=5432` 是**强约束**，proxy 不会"如果 5432 被占就自动换 3307"——只听 5432
2. 即便你没传 `--port`，PG 实例也走 `postgres=5432` 的 fallback，永远不会出现 3307
3. 3307 这个数字在 proxy 行为里**只在多 instance 时当 increment counter 出现**（第二个 instance = 5433……），并非 reserved for "auth proxy"

也就是说：**你模板里"统一 3307"的设计选择是有团队语义的**，但 proxy 本身不会替你守这个约。你必须在 args 里显式 `--port=3307`，proxy 才会 listen 在 3307；你不写，proxy 听 5432（或 3306 MySQL），跟 3307 一点关系都没有。这就是 3307 在生产看不见的第一个根因。

### 修复

```yaml
- name: cloud-sql-proxy
  image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11.4
  args:
    - "--psc"
    - "--structured-logs"
    - "--auto-iam-authn"
    - "--address=127.0.0.1"
    - "--port=3307"                            # ✅ 显式指定
    - "PROJECT:REGION:INSTANCE"
  livenessProbe:
    tcpSocket: { port: 3307 }                  # ✅ 与 --port 一致
    initialDelaySeconds: 10
```

### ⭐ 重要：Pod 里 listen 在 5432 ≠ "3307 这条策略没用"

你的 NS 配置目前是：

> "允许 app=db 出站到 PSC 的 SQL，但端口没做配置"

这是**双解空间**，要看你的 NPB 设计选型：

**方案 A：不改 proxy——保持 5432，NetworkPolicy 也放 5432**

```yaml
egress:
  - to: []
    ports:
      - {protocol: TCP, port: 5432}    # ← 让 PG 5432 出站就完事了
```

✅ 优点：不用改任何 Deployment / template，省事
✅ 优点：跟 Lex 实际在跑的 proxy 一致（已经是 5432）
❌ 缺点：跟团队"统一 3307"的 template 不一致，老模板 / 新模板分裂

**方案 B：修 proxy——让所有 deployment 都用 `--port=3307`**

```yaml
- name: cloud-sql-proxy
  args:
    - "--port=3307"
    - "PROJECT:REGION:INSTANCE"
```

```yaml
# NetworkPolicy
egress:
  - to: []
    ports:
      - {protocol: TCP, port: 3307}
```

✅ 优点：统一 3307（详见 [`sql-3307-template.md`](./sql-3307-template.md) 的 Helm/Kustomize 模板）
✅ 优点：跟团队的 "统一规范" 对齐
❌ 缺点：必须全 team 老 deployment 一起改（前向兼容的话两个端口都放）

**方案 C（推荐）**：同时放 5432 和 3307，proxy 跑哪个端口都行

```yaml
egress:
  - to: []
    ports:
      - {protocol: TCP, port: 5432}    # ← 老 proxy / 老直连还能用
      - {protocol: TCP, port: 3307}    # ← 新 template / 升级后用
      - {protocol: TCP, port: 6432}    # ← Managed Connection Pooling
```

✅ 优点：不打破任何老 Pod，proxy 跑哪个端口都行
✅ 优点：跟 [`why-psc-netpolicy-3307.md` 现象补遗](./why-psc-netpolicy-3307.md#现象补遗老用户能连新用户必须开-3307) 里 "最大覆盖" 的推荐一致
❌ 缺点：多开了一个端口（安全性 vs 兼容性 trade-off）

**结论**：你这次的"为什么 3307 看不到"答案就是 **真相 #1 —— proxy 跑的是 5432**。但 **3307 的 NetworkPolicy 应该照常开**——**不是给当前这个 Pod 用，是给以后按新 template 部署的 Pod、或者团队别的同名 template 用**。

---

## 2. 真相二：proxy 用了 Unix Domain Socket，不是 TCP

### 第二个高频根因

如果你（或你们的 template）配的是 `--unix-socket` 而不是 `--port`：

```yaml
- name: cloud-sql-proxy
  args:
    - "--psc"
    - "--auto-iam-authn"
    - "--unix-socket=/cloudsql"
    - "PROJECT:REGION:INSTANCE"
  volumeMounts:
    - name: cloudsql-socket
      mountPath: /cloudsql
```

那么 **proxy 监听的是一个 Unix socket 文件（`/cloudsql/...`）**，**不是 TCP 端口**。

`ss -nltp` 默认**只显示 TCP 监听端口**，自然看不到任何 listen 项。

### 复现命令

```bash
NS=psc-demo; POD=db-app-xxx
kubectl exec -n $NS $POD -c cloud-sql-proxy -- sh -c 'ls -la /cloudsql/ 2>/dev/null && echo "---" && ss -alnp 2>/dev/null | grep -iE "(cloud|sql)" '
```

**期望输出（Unix socket 模式）：**

```
srw-rw---- 1 nonroot nonroot 0 Jul 6 19:00 /cloudsql/
srw-rw---- 1 nonroot nonroot 0 Jul 6 19:00 /cloudsql/PROJECT:REGION:INSTANCE
```

注意 `s` 开头 = socket 文件，不是 `LISTEN` 一行。

### 这种模式下 3307 是怎么"工作"的？

答案是 **3307 在这种模式下根本不存在**。应用应该这样连：

```yaml
env:
  - name: DB_HOST
    value: "/cloudsql/PROJECT:REGION:INSTANCE"     # 注意路径是 socket 文件
  - name: DB_PORT
    value: "5432"                                   # PG 的 native port,JDBC 需要这个字段但 socket 模式下被忽略
```

### 触发场景

- 跟着一份过时的 v1.x 教程写的（v1 默认是 Unix socket）
- 用了官方 Helm chart 的某些 variant
- 想避免 NetworkPolicy 多开端口 = 干脆全走 socket

### 修复（如果要保持 3307 + TCP）

把 args 改成 TCP 模式（见真相一的修复示例），并在 NetworkPolicy 中放行 `egress TCP/3307`。

### 修复（如果保留 socket 模式）

继续用 socket，不需要改任何 NetworkPolicy。但**template 一定要文档化**——很多人会预期 3307，结果 socket 路径不匹配。

---

## 3. 真相三：`ss` 跑错了容器，跑错了 namespace

### 第三个高频根因

**Pod 内的容器是隔离的进程，但共享 network namespace。** 所以 `ss -nltp` 在 Pod 内任一容器跑，**结果是一致的**（同一组 listen 端口）。

但是有两个例外会让你以为"看不到"：

### 3a. `ss` 命令在容器内不可用

`distroless` 镜像没有 `ss` / `netstat` / shell。

```bash
kubectl exec -n $NS $POD -c cloud-sql-proxy -- ss -tnlp
# 报错: "exec failed: container_linux.go:...: starting container process caused: exec: \"ss\": executable file not found in $PATH"
```

**这时候你以为"没 listen"，其实是 `ss` 没装。**

### 复现

```bash
kubectl exec -n $NS $POD -c cloud-sql-proxy -- which ss || echo "ss not installed in this image"

# 替代命令（pod 内任一容器都能跑 /proc/net/tcp）
kubectl exec -n $NS $POD -c cloud-sql-proxy -- sh -c '
  awk "NR>1 && \$4==\"0A\" {split(\$2,a,\":\"); printf \"listen: 127.0.0.1:%d (state=LISTEN)\n\", strtonum(\"0x\"a[2])}" /proc/net/tcp
'
```

或者直接 `apt-get install iproute2` 装 `ss`（前提是有 root）：

```bash
kubectl exec -n $NS $POD -c cloud-sql-proxy -- bash -c 'apt-get update -qq && apt-get install -y -qq iproute2 && ss -tnlp'
```

### 3b. `kubectl exec` 没指定 `-c`

如果你跑 `kubectl exec $POD -- ss -tnlp` 不带 `-c`，kubelet 会**默认进 `app` 容器**。这时如果 `app` 镜像也没有 `ss`，你又看到"命令不存在"的报错。

### 复现

```bash
# 看 Pod 里有几个容器
kubectl get pod -n $NS $POD -o jsonpath='{.spec.containers[*].name}'

# 在每个容器里都试一次
for c in $(kubectl get pod -n $NS $POD -o jsonpath='{.spec.containers[*].name}'); do
  echo "--- container: $c ---"
  kubectl exec -n $NS $POD -c $c -- ss -tnlp 2>&1 | head -5
done
```

### 触发场景

- `kubectl exec` 默认进 `app` 容器，但你看到的是 `app` 的报错
- `app` 用 alpine 但 `cloud-sql-proxy` 用 distroless，你习惯了 `ss` 在哪都可用

---

## 真相四（最关键）：proxy 进程 crash 了，根本没 listen

### **这是你生产环境最该先怀疑的真相**

`--port=3307` 是写在 args 里的，**但 cloud-sql-proxy 启动失败**：
- 拿不到 metadata server token（WI 没绑）
- `--port` 是个 boolean flag（写错语法）
- IAM role 没 `cloudsql.client`
- instance 连接名打错（比如 `:` 被 shell 吃掉了）

**proxy 进程反复 restart，每轮都 crashing**，循环里可能某次刚好 listen 了 3307 几秒又死了。

**`ss` 偏偏在你看的那一瞬没看到 = 因为这一秒它正在重启。**

### 复现

```bash
NS=psc-demo; POD=db-app-xxx
kubectl get pod -n $NS $POD
# 看 RESTARTS 列
kubectl describe pod -n $NS $POD | grep -A 5 "Conditions:"
kubectl logs -n $NS $POD -c cloud-sql-proxy --tail=50
```

**期望看到 logs 里的崩溃信号：**

| 错误关键字 | 含义 | 修复 |
| ---------- | ---- | ---- |
| `could not find default credentials` | WI 没绑到 Pod 上的 KSA | 看 `iam.gke.io/gcp-service-account` annotation + node pool `cloud-platform` scope |
| `400 Bad Request: Invalid instance connection name` | instance 名格式错 | `PROJECT:REGION:INSTANCE` |
| `permission denied for cloudsql.instances.get` | GSA 缺 `cloudsql.client` role | `gcloud projects add-iam-policy-binding` |
| `unknown flag: --port` | proxy 版本太老不识 `--port`（v2.0 之前） | 升 2.x |
| `dial tcp ...: connect: connection refused` | 节点到 PSC Service Attachment 没路 | 检查 PSC endpoint / VPC peering |

**看 secret 是被 mounted 的（distroless 模式下 WI 必须通过 metadata server，不能用 key file）：**

```bash
kubectl get pod -n $NS $POD -o jsonpath='{.spec.serviceAccountName}'
kubectl get sa -n $NS <SA-名> -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}'
```

### 还有一个高频触发：proxy "启动成功"但 listen 失败

distroless 镜像（默认镜像）里 proxy 以非 root 用户（UID 65532）跑。如果 `127.0.0.1:3307` 已经被别的进程占了，或者 proxy 试图 listen 在一个 reserved port，又或者 `securityContext` 限制 bind 权限…

但**最常见的是**：你的 proxy template 写了 `--address=0.0.0.0`，但 Pod 的 NetworkPolicy **只放行 loopback** 或 `127.0.0.1`，导致 bind 在 `0.0.0.0` 没问题但出向流量被 NetworkPolicy 拦了——这跟"3307 没 listen"是**两件事**，但很容易混淆。

### 触发场景

- template 配置漂移了（比如 `cloudSqlProxy.port` 在 values 里没填，自动渲染成 `--port=` 空字符串 — cloud-sql-proxy 会 reject）
- image tag 漂移到一个有 bug 的版本
- KSA/GSA 绑定漏配，刚刚改 NetworkPolicy 重启 Pod 后才暴露
- 用的不是 GKE，而是 GKE Autopilot，metadata server 走 `metadata.google.internal`，而 Autopilot 会强制注入 `GKE_METADATA` env 影响 token 获取路径

### 修复

定位 root cause — 上面的复现命令已经把所有 lead 列齐了。最实用的一句话：

```bash
# 这一条会告诉你"为什么 proxy 没起来"
kubectl logs -n $NS $POD -c cloud-sql-proxy --previous --tail=200
```

`--previous` 看**上一个 crashed container**的日志 = root cause 几乎都在里头。

---

## 真相五：你看错 Pod 了，这是 legacy 直连模式

### 容易被忽略的真相

Lex 的实际环境中**可能有多种部署形态混存**：

| 模式 | 容器 | listen | 怎么连 |
| ---- | ---- | ------ | ------- |
| **直连 (老)** | 只有 `app`，无 sidecar | `app` 自己 `127.0.0.1:5432/3306`，或者直接 `:5432` 去 Pod IP | 无 sidecar，应用直连 PSC EP |
| **Auth Proxy sidecar (新)** | `app` + `cloud-sql-proxy` | sidecar listen `127.0.0.1:3307` | `app → 127.0.0.1:3307` → proxy → `PSC EP:3307` |
| **混合 (Dynatrace/Envoy 等其他 sidecar)** | `app` + `cloud-sql-proxy` + `xxx-agent` | 多个端口都可能被 listen | 应用看自己环境变量 |

如果你不小心 `kubectl exec` 进了一个**没用 Auth Proxy 的老 Pod**，`ss -nltp | grep 3307` 自然没有任何结果 —— 这种 Pod 的应用是**直连 PSC IP**（不走 proxy）。

### 复现

```bash
# 看 Pod 是不是带 sidecar
kubectl get pod -n $NS $POD -o jsonpath='{.spec.containers[*].name}'

# 看应用 DB_HOST 是什么
kubectl exec -n $NS $POD -c <app-容器名> -- env | grep -E '^(DB_|PG|MYSQL)'
```

**判定矩阵**：

| 看到 | 模式 | 怎么连 |
| ---- | ---- | ------- |
| 容器列表只有 `app`，`DB_HOST=10.x.x.x` (PSC EP IP) | 直连 | 必须放 `egress TCP/5432/3306` |
| 容器列表有 `cloud-sql-proxy`，`DB_HOST=127.0.0.1` | Auth Proxy | 必须放 `egress TCP/3307` |
| 容器列表有 `cloud-sql-proxy`，但 `DB_HOST=10.x.x.x` | 配置错误 | 应用配错，应该改成 127.0.0.1 |

### 触发场景

- `kubectl get pod -l app=db-app` 选错了 instance（prod vs staging）
- replica sets 滚动升级，老的还在 running（你 `exec` 进了 old pod，新的还没起来）
- 同 namespace 里有两套 Deployment，一个用 sidecar 一个不用

---

## 五秒确诊法

把上面 5 个真相按"从最常见到最罕见"排个序：

| 排名 | 真相 | 30 秒内能跑的诊断 | 信号判定 |
| ---- | ---- | ----------------- | -------- |
| **#1** | `--port` 没生效，跑默认 5432/3306 | `ss -tnlp \| grep -E ':5432\|:3306\|:3307'` 在 cloud-sql-proxy 容器内跑 | 看到 5432/3306 但**没有 3307** = **真相一** |
| **#2** | proxy 用了 Unix socket 不是 TCP | `ls /cloudsql/`（如 mount 了） | 看到 socket 文件 = **真相二** |
| **#3** | ss 命令在镜像里没装 | `which ss` | 不存在 = **真相三 3a** |
| **#4** | proxy crash 循环，never stable | `kubectl get pod -o jsonpath='{.status.containerStatuses[?(@.name=="cloud-sql-proxy")].restartCount}'` | restartCount > 0 = **真相四** |
| **#5** | 看错 Pod，Pod 里根本没有 sidecar | `kubectl get pod -o jsonpath='{.spec.containers[*].name}'` | 不含 `cloud-sql-proxy` = **真相五** |

### 一键诊断脚本

把上面的判定矩阵写成一个脚本：

```bash
#!/usr/bin/env bash
# diagnose-3307-listen.sh
# 用法: ./diagnose-3307-listen.sh <namespace> <pod>

set -euo pipefail

NS="${1:?usage: $0 <ns> <pod>}"
POD="${2:?usage: $0 <ns> <pod>}"

echo "===================================================="
echo "  3307 Listening Truth-Diagnostic"
echo "  NS/POD: $NS / $POD"
echo "===================================================="

echo ""
echo "[1/5] Containers in this Pod:"
kubectl get pod -n "$NS" "$POD" \
  -o jsonpath='{range .spec.containers[*]}{"  - "}{.name}{" (image="}{.image}{")\n"}{end}'

echo ""
echo "[2/5] Is there a cloud-sql-proxy sidecar?"
HAS_PROXY=$(kubectl get pod -n "$NS" "$POD" \
  -o jsonpath='{.spec.containers[*].name}' 2>/dev/null \
  | grep -cE "(cloud-sql-proxy|cloudsql-proxy|auth-proxy)" || true)

if [[ "$HAS_PROXY" -eq 0 ]]; then
  echo "  ❌ NO Auth Proxy sidecar — this Pod is direct-connect or wrong pod"
  echo "     → This is Truth #5 (looked at wrong Pod / direct-connect)"
  exit 0
fi

echo "  ✅ Auth Proxy sidecar detected"

echo ""
echo "[3/5] Sidecar's actual listen ports (proxy container):"
LISTEN=$(kubectl exec -n "$NS" "$POD" -c cloud-sql-proxy -- \
  sh -c '(ss -tnlp 2>/dev/null || netstat -tnlp 2>/dev/null) \
    | grep -E ":330[67]|:5432|:6432"' 2>&1 || echo "(ss/netstat unavailable)")

echo "$LISTEN"

if echo "$LISTEN" | grep -q ":3307"; then
  echo ""
  echo "  ✅ 3307 IS listening — your 'not seeing' was caused by ss not installed (Truth #3) or wrong Pod"
  exit 0
fi

if echo "$LISTEN" | grep -qE ":5432|:3306"; then
  echo ""
  echo "  ❌ Proxy is listening on engine default port, NOT 3307"
  echo "     → Truth #1: --port argument is missing or not rendered correctly"
fi

if echo "$LISTEN" | grep -q "(ss/netstat unavailable)"; then
  echo ""
  echo "  ⚠️  ss/netstat not available in proxy image (distroless)"
  echo "     → Truth #3: use /proc/net/tcp or install iproute2"
  echo ""
  echo "  Checking /proc/net/tcp directly:"
  kubectl exec -n "$NS" "$POD" -c cloud-sql-proxy -- \
    sh -c '
      cat /proc/net/tcp | awk "
        NR>1 && \$4==\"0A\" {
          split(\$2,a,\":\");
          port=strtonum(\"0x\"a[2]);
          if (port==3307 || port==5432 || port==3306 || port==6432)
            printf \"    LISTEN port=%d (uid=%s)\n\", port, \$8
        }
      "
    ' 2>&1 || echo "(cannot read /proc/net/tcp either)"
fi

echo ""
echo "[4/5] Restart count of cloud-sql-proxy container:"
kubectl get pod -n "$NS" "$POD" \
  -o jsonpath='{.status.containerStatuses[?(@.name=="cloud-sql-proxy")].restartCount}{"\n"}' \
  2>/dev/null || echo "  (cannot determine)"

RESTARTS=$(kubectl get pod -n "$NS" "$POD" \
  -o jsonpath='{.status.containerStatuses[?(@.name=="cloud-sql-proxy")].restartCount}' \
  2>/dev/null || echo 0)
if [[ "${RESTARTS:-0}" -gt 0 ]]; then
  echo "  ⚠️  Restart count > 0 — proxy was crashing"
  echo "     → Truth #4: check logs with --previous flag"
fi

echo ""
echo "[5/5] Sidecar args (from Pod spec):"
kubectl get pod -n "$NS" "$POD" \
  -o jsonpath='{.spec.containers[?(@.name=="cloud-sql-proxy")].args}{"\n"}'

echo ""
echo "===================================================="
echo "  Next steps:"
echo "    kubectl logs -n $NS $POD -c cloud-sql-proxy --previous --tail=100"
echo "    kubectl describe pod -n $NS $POD"
echo "===================================================="
```

---

## 排查决策树（一步一步走）

```
start → ss -tnlp | grep 3307 没结果
  │
  ├─ Pod 里有没有 cloud-sql-proxy 容器？
  │   ├─ 没有 → 真相五（看错 Pod / 老直连模式）
  │   └─ 有 ↓
  │
  ├─ ss 命令本身能不能跑？
  │   ├─ 报错 "executable file not found" → 真相三 3a (distroless 镜像)
  │   │   └─ 用 /proc/net/tcp 或装 iproute2 看真实 listen
  │   └─ ss 能跑 ↓
  │
  ├─ 看到 5432/3306（engine 默认端口）但没看到 3307？
  │   ├─ 是 → 真相一（--port 没生效）
  │   │   └─ 检查 args 里 --port=3307 是否被正确渲染
  │   └─ 否 ↓
  │
  ├─ 看到 socket 文件（/cloudsql/...）但没 TCP listen？
  │   ├─ 是 → 真相二（Unix socket 模式）
  │   │   └─ 这时 3307 不存在，应用必须配 socket 路径连
  │   └─ 否 ↓
  │
  ├─ 看到 ls socket /proc/net/tcp 都是空的？
  │   └─ 真相四（proxy crash 循环）
  │       └─ 必看: kubectl logs ... -c cloud-sql-proxy --previous --tail=200
```

---

## NetworkPolicy 到底要不要放 3307？

**回到 Lex 的原问题**：NS 默认 netpol 都是 deny all，"允许 Pod 标签 app=db 出站到 PSC SQL，**但端口没做配置**"。

排查完真相一二三四五后，**NetworkPolicy 的端口配置**有三种正解：

### A. 如果是真相一（proxy 在 5432 listen）

```yaml
egress:
  - to: []
    ports:
      - {protocol: TCP, port: 3307}    # Auth Proxy → PSC EP 必须放
```

### B. 如果是真相二（Unix socket 模式）

```yaml
egress:
  - to: []
    ports:
      - {protocol: TCP, port: 443}     # Auth Proxy 到 SQL Admin API
      - {protocol: TCP, port: 3307}    # 也可能需要 — 即使你用 socket，proxy 还要到 SQL Admin API 注册
```

> 即使 socket 模式下，**cloud-sql-proxy 进程仍要 outbound 流量到 SQL Admin API（TCP 443）和 Cloud SQL 实例（TCP 3307）**。否则 proxy 拿不到 ephemeral cert，连不上 DB。

### C. 如果是真四五（Pod 是直连，或 proxy 已 crash）

```yaml
# 真相五（直连）：放 PSC EP 端口
egress:
  - to: []
    ports:
      - {protocol: TCP, port: 5432}    # PostgreSQL
      - {protocol: TCP, port: 6432}    # Managed Connection Pooling
      - {protocol: TCP, port: 3307}    # 容错（如果后续切到 Auth Proxy）

# 真相四（crash）：网络放通对，但 Pod 健康检查失败，跟 netpol 无关
```

### 推荐配置（覆盖所有真相）

**生产推荐 "最大覆盖"**——同时放 5432 / 6432 / 3307 / 443，理由见 [`why-psc-netpolicy-3307.md` §现象补遗](./why-psc-netpolicy-3307.md#现象补遗老用户能连新用户必须开-3307)：

```yaml
egress:
  # DNS
  - to: []
    ports:
      - {protocol: UDP, port: 53}
      - {protocol: TCP, port: 53}

  # Cloud SQL PSC（直连 + Auth Proxy + Managed Pooling 全覆盖）
  - to:
      - ipBlock:
          cidr: <PSC_ENDPOINT_CIDR>/32      # Consumer VPC 的 PSC EP 段
    ports:
      - {protocol: TCP, port: 5432}         # PG 直连
      - {protocol: TCP, port: 6432}         # Managed Pooling PgBouncer
      - {protocol: TCP, port: 3307}         # Auth Proxy → PSC EP
      - {protocol: TCP, port: 3306}         # MySQL 直连（如果也用 MySQL）

  # cloud-sql-proxy → SQL Admin API（拿 ephemeral cert）
  - to: []
    ports:
      - {protocol: TCP, port: 443}
```

---

## 一句话结论

> **`ss` 看不到 3307 不等于 proxy 不 listen。** 大多数情况下 proxy 在 listen，只是 (`--port` 配置错了) / (用了 Unix socket) / (`ss` 命令不存在) / (proxy crash 循环) / (你 `exec` 错了 Pod)。
>
> **真正的"3307 怎么工作"**：app 连 `127.0.0.1:3307`（或 socket 路径），proxy 在 Pod 内转发，proxy 再出 Pod 到 PSC EP 的 3307。NetworkPolicy 控制的是**第三跳**——proxy → PSC EP 的 egress。
>
> **30 秒确诊**：跑 `diagnose-3307-listen.sh <ns> <pod>`，按上面决策树走完就知道是哪个真相。

---

## 附录：本文档依赖

- 上游规范：[`why-psc-netpolicy-3307.md`](./why-psc-netpolicy-3307.md)（为什么 3307 + 老用户能连/新用户必开的根因）
- 上游设计：[`sql-3307-template.md`](./sql-3307-template.md)（平台级统一 3307 的 Helm/Kustomize 模板）
- 官方文档：
  - [cloud-sql-proxy README](https://github.com/GoogleCloudPlatform/cloud-sql-proxy)（`--port` 默认行为、Unix socket、K8s sidecar）
  - [Connect to Cloud SQL from GKE](https://cloud.google.com/sql/docs/postgres/connect-kubernetes-engine)
  - [Cloud SQL Private Service Connect](https://cloud.google.com/sql/docs/postgres/about-private-service-connect)（3307 是 PSC serving port）
  - [Kubernetes Pod network namespace](https://kubernetes.io/docs/concepts/workloads/pods/)（同 Pod 内多 container 共享）
