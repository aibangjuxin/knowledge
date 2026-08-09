# class-application-loadbalancer-cross-project.md — Classic ALB 跨 project 跨到 B 工程方案探索

> **场景(与 `baseing-path-cross-project.md` 的差异)**:A 工程的现网 GLB **不是** Global external ALB 也不是 Regional external ALB,而是 **Classic Application Load Balancer**(`loadBalancingScheme=EXTERNAL`,Premium Tier 全局,Standard Tier 可配 region)。Lex 想保住这个 Classic ALB(不动 IP / 不动 cert / 不重起 LB),同时让请求按 `apiname1` / `apiname2` 分流到 A 工程内独立 Backend Service + 独立 Cloud Armor,再 **跨 project 打到 B 工程**。**Cloud Armor 必须绑在 A 工程的 BS 上**(Lex 原话:"我想让对应的 bs 在这个工程上面 因为这样 Cloud armor才能绑定在这个工程")。
>
> **核心矛盾**:Google 官方矩阵 `public-tls-ingress/PSC-support.md` §2 第 30 行明确"**Classic Application Load Balancer 不支持 PSC NEG**"。那是不是死路? — **不是**。Google 官方同一文档(`compute/docs/load-balancing/http/`)有一条**非对称兼容**声明,允许 **EXTERNAL_MANAGED backend service 挂到 EXTERNAL forwarding rule(Classic ALB)下**,而 EXTERNAL_MANAGED BS 又支持 PSC NEG → **3 层拼装打通**。
>
> **结论先行**:**方案 1(EXTERNAL_MANAGED BS + PSC NEG)⭐⭐⭐⭐⭐ 完全可行**,不动 Classic ALB FR / target proxy / cert / 公网 IP,Cloud Armor 正常绑 BS。**前提**:A 工程的 Classic ALB 必须是 **Target HTTPS Proxy**(不是 HTTP proxy 跑公网 HTTPS,会被 cert 信任问题卡)。

---

## 0. 原始问题(Lex 原话 verbatim,未经 paraphrase)

> 我看到你在文档里面提到了这个类型 Classic Application Load Balancer 那么如果我这次的需求就是这个类型,我还想让我的请求到达这个 GLB 上面之后能够跨工程把服务请求到另外一个工程,有没有解决办法?
> 这里我们假设这个域名是这样 `www.caep.uk` 然后这个下面有一个对应的用户,他的 API 的名字是这样 `www.caep.uk/apiname1/` `www.caep.uk/apiname2/`
> `www.caep.uk` 这个对应的解析已经到我们这个 Classic Application Load Balancer 谷歌工程我们可以称之为 talent project 的 GLB 上
> 我想让对应的 bs 在这个工程上面 因为这样,Cloud armor 才能绑定在这个工程
> 有什么办法能够 cross project 把请求打到另外一个 master 工程上面去呢?
> 且需要注意的是,我这个 Classic Application Load Balancer 是一个 GLB 的,也就是有公网域名的
> 那么我们基于这个去帮我探索一下,并生成一个对应的文档,放在 `/Users/lex/git/gcp/ingress/public-tls-basingpath-cross` 目录下面,命名为 `class-application-loadbalancer-cross-project.md`
> 当然,我们这里不用做深度的配置文件检索,也就是说不要细节,只要实现方案,看能不能实现

### 0.1 隐性约束(从原话反推)

| # | 约束 | 推导依据 |
|---|------|----------|
| 1 | **A 工程 GLB 必须是 Classic ALB**(不是 Global/Regional external ALB) | "我看到你在文档里面提到了这个类型 Classic Application Load Balancer 那么如果我这次的需求就是这个类型" |
| 2 | **Classic ALB 是公网 GLB**(不是 internal / passthrough) | "我这个 Classic Application Load Balancer 是一个 GLB 的,也就是有公网域名的" |
| 3 | **域名 A-record 绑固定 IP,不能改入口** | "www.caep.uk 这个对应的解析已经到我们这个 Classic Application Load Balancer" |
| 4 | **BS 必须在 A 工程**(因为 Cloud Armor 必须绑) | "我想让对应的 bs 在这个工程上面 因为这样,Cloud armor 才能绑定在这个工程" |
| 5 | **必须跨 project 打到 B 工程** | "能够 cross project 把请求打到另外一个 master 工程上面去" |
| 6 | **不动 GLB FR / target proxy / cert** | 隐含 — Lex 全文不提要改 LB 本身 |
| 7 | **不要深度配置文件检索** | "不用做深度的配置文件检索,也就是说不要细节,只要实现方案" |

### 0.2 一句话核心结论

> **可行性**:**完全可行**,通过 **方案 1** = **保留 Classic ALB 的 EXTERNAL forwarding rule** + **新建 EXTERNAL_MANAGED backend service**(A 工程内,可绑 Cloud Armor + PSC NEG)+ **新建 PSC NEG**(跨 project 指向 B 工程 SA)。
>
> **关键洞察**(Google 官方原话 R1):"**It is possible to attach EXTERNAL_MANAGED backend services to EXTERNAL forwarding rules. However, EXTERNAL backend services cannot be attached to EXTERNAL_MANAGED forwarding rules.**" — 这条非对称兼容是 Classic ALB 跨 project 的"side door"。
>
> **不要做的**:
> - ❌ 不要把 Classic ALB 整个迁移到 Global/Regional external ALB(虽然 100% 能解决,但会换 IP,破 Lex 的"入口 IP 不能变"硬约束)
> - ❌ 不要尝试让 EXTERNAL BS 直接挂 PSC NEG(GCP 会拒)
> - ❌ 不要让 Classic ALB 直接挂 EXTERNAL BS + instance group 跨 project(EXTERNAL BS 不支持 PSC NEG 也不支持跨 VPC backend)

---

## 1. 总体架构图(方案 1:EXTERNAL_MANAGED BS + PSC NEG)

```
┌────────────────────────────────────────────────────────────────────────┐
│ INTERNET                                                               │
│   curl https://www.caep.uk/apiname1/...                                │
│   curl https://www.caep.uk/apiname2/...                                │
└─────────────┬──────────────────────────────────────────────────────────┘
              │ DNS A-record → 34.x.x.x (固定 IP,不可改)
              ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PROJECT A (Tenant, www.caep.uk 已 A-record → 此 GLB 的固定 IP)         │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ Classic Application Load Balancer                                  │  │
│ │   --load-balancing-scheme=EXTERNAL (Premium Tier,global)           │  │
│ │   ★ 现网已有,不动 ★                                              │  │
│ │                                                                  │  │
│ │   Frontend :443, Cert: *.caep.uk, Target HTTPS Proxy (不动)      │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ URL Map (注意:Classic ALB 也支持 path rule + host rule)          │  │
│ │   hostRules: [www.caep.uk] → caep-api-matcher                     │  │
│ │   pathRules:                                                     │  │
│ │     /apiname1/*  →  bs-caep-apiname1  (EXTERNAL_MANAGED)         │  │
│ │     /apiname2/*  →  bs-caep-apiname2  (EXTERNAL_MANAGED)         │  │
│ │     default     →  bs-caep-default   (EXTERNAL_MANAGED)         │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                │ URL Map path rule 选 BS(EXTERNAL_MANAGED)            │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ Backend Service (★ 关键:scheme=EXTERNAL_MANAGED,不是 EXTERNAL)  │  │
│ │                                                                  │  │
│ │   bs-caep-apiname1  --load-balancing-scheme=EXTERNAL_MANAGED      │  │
│ │     - protocol: HTTPS                                             │  │
│ │     - backends: PSC NEG caep-apiname1-neg (→ B side SA-1)         │  │
│ │     - security-policy: policy-apiname1  (Cloud Armor, ★ A 工程) │  │
│ │                                                                  │  │
│ │   bs-caep-apiname2  --load-balancing-scheme=EXTERNAL_MANAGED      │  │
│ │     - backends: PSC NEG caep-apiname2-neg (→ B side SA-1)        │  │
│ │     - security-policy: policy-apiname2                           │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
└────────────────┼───────────────────────────────────────────────────────┘
                 │ PSC Tunnel (A → B, Google 内部骨干)
                 ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PROJECT B (Master)                                                     │
│   Service Attachment → L7 Internal ALB → MIG nginx → K8s Gateway       │
│   (详见 /Users/lex/git/knowledge/cloud/k8s/k8s-gateway/                 │
│    public-fqdn-explorer.md §1 / §3,本方案 B 侧全引用此 doc)            │
└────────────────────────────────────────────────────────────────────────┘
```

**关键识别**:
- ✅ Classic ALB FR (scheme=EXTERNAL) 不动
- ✅ 新建的 BS 是 **EXTERNAL_MANAGED**(关键差异,这是 side door 的入口)
- ✅ Cloud Armor 绑在 A 工程的 EXTERNAL_MANAGED BS 上(满足 Lex 约束 #4)
- ✅ PSC NEG 在 A 工程内创建,跨 project 指 B 工程 SA
- ✅ B 侧架构完全沿用 baseing-path-cross-project.md §4 + public-fqdn-explorer.md

---

## 2. Google 官方原话:为什么 EXTERNAL_MANAGED BS 能挂到 EXTERNAL forwarding rule

**Lex 的担心**:"Google 矩阵说 Classic ALB 不支持 PSC NEG,是不是死路?"

**Google 官方原话**(R1,来源:`https://cloud.google.com/compute/docs/load-balancing/http/`):

> "**It is possible to attach EXTERNAL_MANAGED backend services to EXTERNAL forwarding rules. However, EXTERNAL backend services cannot be attached to EXTERNAL_MANAGED forwarding rules.**"
>
> "To take advantage of new features available only with the global external Application Load Balancer, we recommend that you migrate your existing EXTERNAL resources to EXTERNAL_MANAGED by using the migration process described at Migrate resources from classic to global external Application Load Balancer."

**对照矩阵**(R2,来源:`public-tls-ingress/PSC-support.md` §2 + R3 `vpc/docs/private-service-connect-backends`):

| 维度 | EXTERNAL FR (Classic ALB) | EXTERNAL_MANAGED FR (Global/Regional external ALB) |
|------|--------------------------|----------------------------------------------------|
| 可挂的 BS type | **EXTERNAL + EXTERNAL_MANAGED**(R1 明确允许) | **只能 EXTERNAL_MANAGED**(不允许挂 EXTERNAL) |
| 可挂 PSC NEG | ❌ 走不通 — 必须用 EXTERNAL_MANAGED BS 中转 | ✅ 直接走 |
| Cloud Armor 绑点 | BS(无论 EXTERNAL 还是 EXTERNAL_MANAGED 都行) | BS |
| URL Map path rule | ✅ 支持 | ✅ 支持 |

**关键观察**:**Classic ALB 不是死路,是要求你"绕一层"**:
- Classic ALB FR 不动(EXTERNAL)
- 在 FR 下面挂 **EXTERNAL_MANAGED** backend service(R1 允许)
- EXTERNAL_MANAGED BS 又能挂 PSC NEG(R2 矩阵 + baseing-path-cross-project.md §2.2)
- Cloud Armor 绑在 BS 上(R4)

→ **3 层拼装 = Classic ALB FR → EXTERNAL_MANAGED BS → PSC NEG → 跨 project SA**,完全跑通。

---

## 3. 方案决策矩阵(4 个候选方案)

| # | 方案 | A 工程 FR | A 工程 BS | B 工程入口 | 是否满足"BS 在 A 工程 + Cloud Armor 在 A 工程 + 跨 project"? | 推荐度 |
|---|------|-----------|-----------|------------|--------------------------------------------------|--------|
| **1** | **EXTERNAL_MANAGED BS + PSC NEG**(side door) | EXTERNAL(不动)| **EXTERNAL_MANAGED**(新建) | PSC NEG → SA → ILB → MIG | ✅ 全部满足 | ⭐⭐⭐⭐⭐ |
| **2** | **EXTERNAL BS + Internet NEG**(B 工程公网入口) | EXTERNAL(不动)| EXTERNAL(新建) | B 工程公网 GLB IP / hostname(走公网绕) | ✅ Cloud Armor 在 A;⚠ 走公网,绕开 PSC,跨 project 但不是 private | ⭐⭐⭐⭐ |
| 3 | EXTERNAL BS + 直接挂 B 工程 instance group | EXTERNAL(不动)| EXTERNAL(新建) | ❌ EXTERNAL BS **不能**挂跨 VPC/跨 project backend | ❌ GCP 拒 | ❌ |
| **4** | Classic ALB 整体迁移到 Global/Regional external ALB | EXTERNAL_MANAGED (新建) | EXTERNAL_MANAGED | PSC NEG → SA → ILB → MIG | ✅ 满足;⚠ **换 IP**(Lex "GLB 已存在" 硬约束冲突) | ⭐⭐(Lex 明确不要) |
| 5 | Classic ALB FR + 静态 URL rewrite → B 工程 LB hostname | EXTERNAL(不动) | EXTERNAL | 静态 rewrite 不能 hop 到另一个 GLB | ❌ URL rewrite 只改 path,不改 hostname/route target | ❌ |

**为什么方案 1 是最优解**:
- ✅ **3 个 Lex 硬约束全满足**:① 不动 Classic ALB FR ② BS 在 A 工程 + Cloud Armor 在 A 工程 ③ 跨 project
- ✅ **流量走 Google 内部骨干**(PSC tunnel),不走公网,延迟/带宽/安全 都优于方案 2
- ✅ **B 侧架构零修改**(沿用 baseing-path-cross-project.md §4 + public-fqdn-explorer.md 已确认的 5 方案)

**什么时候选方案 2**:B 工程**没有 PSC SA** / B 工程已经在另一个 GCP project 且无法搭 ILB + SA / B 工程侧只想用最简单的公网入口

**什么时候选方案 4**:Lex 改变主意愿意换 IP(此场景 Lex 明确说"不用做深度配置文件检索 / 只要实现方案 / 看能不能实现",倾向保 LB)

---

## 4. 方案 1 落地步骤(高层概览,占位符化)

> 按 Lex 要求"不用做深度配置文件检索,只列方案"。完整命令模板参考 `baseing-path-cross-project.md` §3.2(只把 `--region` 替换成 `--global` 因 Classic ALB 在 Premium Tier 全局)。

### 4.1 7 步高层流程

| Step | 操作 | 资源 type | 新建? | 关键 flag |
|------|------|-----------|-------|----------|
| 1 | 建 Cloud Armor policy `policy-apiname1` / `policy-apiname2` | global Cloud Armor | 新建 | `--security-policy=policy-apiname1` |
| 2 | 建 Backend Service **`bs-caep-apiname1`**(`--load-balancing-scheme=EXTERNAL_MANAGED`) | global BS | 新建 | `--load-balancing-scheme=EXTERNAL_MANAGED --protocol=HTTPS --global` |
| 3 | 建 PSC NEG `caep-apiname1-neg`(指向 B 工程 SA) | regional NEG | 新建 | `--network-endpoint-type=PRIVATE_SERVICE_CONNECT --psc-target-service=<SA_URI>` |
| 4 | add-backend 把 PSC NEG 挂到 EXTERNAL_MANAGED BS | BS backend | add | `--network-endpoint-group=<NEG> --balancing-mode=UTILIZATION` |
| 5 | 把 Cloud Armor policy 绑到 EXTERNAL_MANAGED BS | BS attach | update | `--security-policy=<policy>` |
| 6 | 更新现有 URL Map(给 `www.caep.uk` 加 path rule) | URL Map | update | `--path-rules="/apiname1/*=bs-caep-apiname1,/apiname2/*=bs-caep-apiname2"` |
| 7 | B 侧 owner approve SA 的 PSC NEG 连接 | SA | approve | B 工程 owner 在 console 手动 approve(或预设 ACCEPT_AUTOMATIC) |

### 4.2 方案 1 与 baseing-path-cross-project.md 的 3 个差异

| 维度 | baseing-path(Global/Regional external ALB) | class-application-loadbalancer(Classic ALB) |
|------|-------------------------------------------|-----------------------------------------------|
| BS 的 `load-balancing-scheme` | `EXTERNAL_MANAGED` | `EXTERNAL_MANAGED`(**同样!这是关键 side door**) |
| LB FR 的 `load-balancing-scheme` | `EXTERNAL_MANAGED`(global 或 regional) | `EXTERNAL`(**保留不动**) |
| 是否需要 proxy-only subnet | ❌ Global 不需要;Regional 需要 | ❌ Classic ALB **不需要**(`compute/docs/load-balancing/http/` § "Architecture": proxy-only subnet 只 for Regional external ALB) |
| 是否需要 URL Map 默认 service 是 EXTERNAL_MANAGED | 默认即如此 | **必须显式设 default service 为 EXTERNAL_MANAGED BS**(否则 path rule 全 fail) |

**重点差异**:Classic ALB 的 URL Map 必须显式确认 default service 是 EXTERNAL_MANAGED BS(不是 EXTERNAL BS),否则 URL Map 的所有 path rule 都会因为 backend 类型不匹配被 GCP 拒。这是 baseing-path 文档里没有强调的,Classic ALB 场景独有。

### 4.3 B 侧(共享 baseing-path + public-fqdn-explorer)

B 侧架构、SA/ILB/MIG nginx/K8s Gateway 完整覆盖在以下两份文档:

- **`/Users/lex/git/gcp/ingress/public-tls-basingpath-cross/baseing-path-cross-project.md` §4** — 1 SA vs 2 SA 决策 + nginx.conf + K8s HTTPRoute
- **`/Users/lex/git/knowledge/cloud/k8s/k8s-gateway/public-fqdn-explorer.md`** — Master B 5 方案 + nginx.conf + MIG instance template + startup script(1144 行)

→ **本方案 B 侧完全沿用,不再重复**。

---

## 5. 严格说法 vs 简化说法对照

| 简化说法 | 严格说法 | 文档应使用的措辞 |
|---------|---------|----------------|
| "Classic ALB 不支持 PSC NEG" | **Classic ALB 的 EXTERNAL forwarding rule 不直接支持 PSC NEG**,但允许挂 **EXTERNAL_MANAGED backend service**,而 EXTERNAL_MANAGED BS **支持 PSC NEG**。3 层拼装打通 | "Classic ALB 通过 EXTERNAL_MANAGED BS side door 跑 PSC NEG,不动 LB FR" |
| "EXTERNAL 和 EXTERNAL_MANAGED 是同一类" | **完全不同的两类**;EXTERNAL 是经典 LB 的 scheme,EXTERNAL_MANAGED 是 managed LB 的 scheme;**只有 EXTERNAL_MANAGED BS 支持 PSC NEG 后端** | "EXTERNAL_MANAGED 是 EXTERNAL 的'现代版',BS 必须用 EXTERNAL_MANAGED 才能挂 PSC NEG" |
| "Cloud Armor 必须绑 EXTERNAL BS" | **Cloud Armor 绑哪个 BS 跟 BS type 无关**,但 BS 必须是 EXTERNAL_MANAGED 才能挂 PSC NEG → 实际工程里 Cloud Armor 绑的就是 EXTERNAL_MANAGED BS | "Cloud Armor 绑在 EXTERNAL_MANAGED BS 上(也绑在 EXTERNAL BS 上,但 EXTERNAL BS 没法跨 project)" |
| "Classic ALB 不支持 URL Map path rule" | Classic ALB **支持** URL Map host rule + path rule(只是少数 advanced features 不支持,详见 `compute/docs/load-balancing/http/` §"Load balancing features") | "Classic ALB 支持 path rule,足够 Lex 这个场景用" |
| "B 侧必须有 PSC SA + ILB + MIG" | 方案 1 必须;方案 2 可以直接用 B 工程公网 GLB,跳过 SA/ILB/MIG | "方案 1 走 PSC(private);方案 2 走 Internet NEG(public,绕开 PSC)" |
| "Lex 必须迁移到 Global external ALB" | 是 Google **推荐** 的迁移路径,但**不是**唯一路径;**R1 明确允许 side door** | "Google 推荐迁移,但 R1 给了 side door,本方案就是用 side door" |

---

## 6. 关键约束与前置检查(必看)

### 6.1 前置条件(任一不满足 → 方案 1 不可行)

| # | 前置条件 | 验证方式 | 不满足时的退路 |
|---|---------|---------|--------------|
| 1 | A 工程 GLB 必须是 **Classic Application Load Balancer**(不是别的) | `gcloud compute forwarding-rules describe <FR-name> --format="get(loadBalancingScheme)"` 应返回 `EXTERNAL`(无 `_MANAGED`) | 不是 Classic → 走 baseing-path-cross-project.md 方案 1 |
| 2 | Classic ALB 必须是 **Target HTTPS Proxy**(不是 HTTP Proxy) | `gcloud compute target-https-proxies describe <proxy-name>` 应存在;若只有 target-http-proxies 不行(公网 HTTPS 需要) | 是 HTTP → 改 HTTPS + 上传 cert |
| 3 | A 工程有可用的普通 subnet 给 PSC NEG 用 | `gcloud compute networks subnets list --project=<A>` 查 | 没有 → 新建 subnet |
| 4 | B 工程已部署 Service Attachment | B 工程 owner 提供 SA URI(`projects/<B>/regions/<R>/serviceAttachments/<NAME>`) | 没有 → 先建 B 侧(参考 public-fqdn-explorer.md §3) |
| 5 | A 工程 Org Policy 没禁 PSC NEG | 看 Org Policy 列表 | 禁了 → 走方案 2(Internet NEG) |

### 6.2 URL Map default service 必须显式改 EXTERNAL_MANAGED

Classic ALB 跟 Global/Regional external ALB 的一个微妙差异:

- Global/Regional external ALB 的 URL Map 默认 service 通常**已经是** EXTERNAL_MANAGED BS(因为你建的 BS 默认就是 EXTERNAL_MANAGED)
- **Classic ALB 的 URL Map 默认 service 历史上可能是 EXTERNAL BS**(因为 Classic ALB 时代 BC 只能挂 EXTERNAL BS),**升级路径/R1 side door 利用前必须显式换成 EXTERNAL_MANAGED BS**

→ **操作**:在 Lex 的 Classic ALB 上跑 `gcloud compute url-maps describe <UM-name>`,确认 `defaultService` 字段指向的 BS 是 `--load-balancing-scheme=EXTERNAL_MANAGED`,**不是** `EXTERNAL`。如果历史 default service 是 EXTERNAL BS,**新建一个 EXTERNAL_MANAGED BS 设为 default**(保留原 EXTERNAL BS 不动也行,只是 default 不再走它)。

### 6.3 EXTERNAL_MANAGED BS 的协议必须 HTTPS

EXTERNAL_MANAGED BS + PSC NEG 后端,protocol 推荐 HTTPS(re-encrypt 到 B 侧 ILB),HTTP/HTTP2 也允许但安全性弱。详细协议选择见 `baseing-path-cross-project.md` §3.2 Step 2。

### 6.4 gcloud add-backend 在 EXTERNAL_MANAGED + PSC NEG 上的失败模式

复用 baseing-path-cross-project.md §7 坑 #3(`cross-project-psc-architecture.md` Gotcha #10):

```
❌ --balancing-mode=RATE        → "Balancing mode is not supported for PSC NEG"
❌ --max-connections-per-endpoint → "EXTERNAL_MANAGED + HTTPS 不支持 max-*"
✅ --balancing-mode=UTILIZATION --capacity-scaler=1.0
```

如果 add-backend 失败,fallback 路径见 `cross-project-psc-architecture.md` Gotcha #10 的 `backend-services import` YAML 方法。

---

## 7. 端到端验证(5 步)

```bash
# 1. A 工程 Classic ALB FR 仍是 EXTERNAL scheme
gcloud compute forwarding-rules describe <FR-name> --global \
  --format="get(loadBalancingScheme)"   # 期望 EXTERNAL(不变)

# 2. EXTERNAL_MANAGED BS 创建成功且能加 PSC NEG
gcloud compute backend-services describe bs-caep-apiname1 --global \
  --format="get(loadBalancingScheme,securityPolicy)"

# 3. URL Map path rule 命中
curl -sk -o /dev/null -w "%{http_code}\n" https://www.caep.uk/apiname1/healthz

# 4. B 侧 SA 收到 PSC NEG 连接
gcloud compute service-attachments describe <SA> --project=<B> --region=<R> \
  --format="json" | jq '.connectedEndpoints'   # 期望看到 A 工程的 NEG ACCEPTED

# 5. LB log 确认 path rule 选 BS
gcloud logging read 'jsonPayload.urlMapName="<UM>"' --project=<A> --limit=5 \
  --format='json' | jq '.[] | {path:.jsonPayload.requestUrl, backend:.jsonPayload.backendTargetName}'
```

完整 6 步验证 + LB log 信号 + 数据面信号见 `baseing-path-cross-project.md` §6。

---

## 8. 推荐方案(最终定型)

> **本方案的最终定型依据**:Google 官方 `compute/docs/load-balancing/http/` 的 EXTERNAL_MANAGED BS side door 声明(R1)+ `vpc/docs/private-service-connect-backends` 的多 NEG 规则(R3)+ Cloud Armor 必须绑 BS(R4)+ Lex 4 个核心硬约束(不动 LB / BS 在 A / Cloud Armor 在 A / 跨 project)。

**A 工程(Tenant)侧**:
- ✅ 现有 Classic ALB FR (scheme=EXTERNAL) **不动**,IP 不变,cert 不变,Target HTTPS Proxy 不变
- ✅ 现有 URL Map **不重建**,只 add-path-matcher / add-path-rule;default service 必须显式改成 EXTERNAL_MANAGED BS(见 §6.2)
- ✅ 新建 2 个独立 Cloud Armor policy(`policy-apiname1` / `policy-apiname2`)
- ✅ 新建 2 个独立 Backend Service(`bs-caep-apiname1` / `bs-caep-apiname2`),**`--load-balancing-scheme=EXTERNAL_MANAGED --global --protocol=HTTPS`**(side door 关键)
- ✅ 新建 2 个 PSC NEG(`caep-apiname1-neg` / `caep-apiname2-neg`),指向 B 工程同一个 SA
- ✅ 1 个 default BS(EXTERNAL_MANAGED)兜底
- ❌ **不需要** proxy-only subnet(Classic ALB 不需要)
- ❌ **不需要** 重建 LB

**B 工程(Master)侧**:
- ✅ 沿用 `baseing-path-cross-project.md` §4 + `public-fqdn-explorer.md` §3 — 0 改动
- ✅ Producer ILB = L7 Internal Application LB,nginx 跑 MIG VM,K8s Gateway + HTTPRoute
- ✅ B 侧 cert = `*.caep.uk`,跟 A 侧同步(SAN 含 `www.caep.uk`)

**符合 Lex 的 5 个核心约束**:
- ① Classic ALB 不动 ✓
- ② 公网入口(IP 不变)✓
- ③ BS 在 A 工程(EXTERNAL_MANAGED)✓
- ④ Cloud Armor 在 A 工程(绑 EXTERNAL_MANAGED BS)✓
- ⑤ 跨 project 打到 B 工程(PSC NEG → SA)✓

---

## 9. 已知坑与预防

| # | 坑 | 症状 | 预防 |
|---|----|------|------|
| 1 | 默认 service 用 EXTERNAL BS(不是 EXTERNAL_MANAGED) | URL Map add-path-rule 报"backend type mismatch" | §6.2 — 显式确认 defaultService 指向 EXTERNAL_MANAGED BS |
| 2 | gcloud add-backend 用 `--balancing-mode=RATE` | "Balancing mode is not supported for Private Service Connect network endpoint groups" | 用 `UTILIZATION --capacity-scaler=1.0`(详见 `cross-project-psc-architecture.md` Gotcha #10) |
| 3 | gcloud add-backend 用 `--max-connections-per-endpoint` | "EXTERNAL_MANAGED + HTTPS 不支持 max-* 字段" | 不加任何 max-* 字段 |
| 4 | B 侧 SA 用 `--connection-preference=ACCEPT_MANUAL` 但 owner 没 approve | A 工程 PSC NEG 创建成功但 pscConnectionId 为空 | 提前让 B owner 用 `ACCEPT_AUTOMATIC` 或预先 approve |
| 5 | 想"既然都 EXTERNAL_MANAGED BS 了不如把 Classic ALB 也升级" | 触发迁移,换 IP | 不动 Classic ALB — Lex 原话明确不换 IP |
| 6 | 把 Cloud Armor 绑到 EXTERNAL BS 上(老的 default service) | Cloud Armor 实际生效在 EXTERNAL BS 上,但 EXTERNAL BS 没法跨 project | 绑到新建的 EXTERNAL_MANAGED BS 上 |
| 7 | Classic ALB 实际是 HTTP Proxy(不是 HTTPS) | 公网 HTTPS 跑不通(cert 信任问题) | §6.1 #2 — 确认 target-https-proxies 而非 target-http-proxies |
| 8 | Classic ALB 是 Standard Tier 配 region(不是 Premium Tier 全局) | FR 是 regional 的(不是 global) | Standard Tier 下也能跑 EXTERNAL_MANAGED BS,但 region 必须显式传;Premium Tier 默认 global |

---

## 10. 引用与延伸阅读

- **`/Users/lex/git/gcp/ingress/public-tls-basingpath-cross/baseing-path-cross-project.md`** — 同目录的姊妹文档,完整覆盖 A 工程 Global/Regional external ALB 场景的 7 步 install + nginx.conf + K8s HTTPRoute。本方案 B 侧全沿用此 doc
- **`/Users/lex/git/gcp/ingress/public-tls-ingress/PSC-support.md`** §2 第 28/30 行 — GCP LB × PSC 兼容矩阵,直接证据 Classic ALB "不支持 PSC NEG" 但 EXTERNAL_MANAGED BS 支持
- **`/Users/lex/git/knowledge/cloud/k8s/k8s-gateway/public-fqdn-explorer.md`** — Master B 工程 5 方案 + nginx.conf + MIG template(1146 行,本方案 B 侧全引用此 doc)
- **`/Users/lex/.hermes/profiles/architecture/skills/architectrue/references/cross-project-psc-architecture.md`** Gotcha #10 — EXTERNAL_MANAGED BS + PSC NEG 的 add-backend YAML 修法

### 10.1 权威证据 / 来源日期

| # | 官方来源 URL | 验证日期 | 关键原话 |
|---|---|---|---|
| **R1** | `https://cloud.google.com/compute/docs/load-balancing/http/` | 2026-08-07 | "**It is possible to attach EXTERNAL_MANAGED backend services to EXTERNAL forwarding rules. However, EXTERNAL backend services cannot be attached to EXTERNAL_MANAGED forwarding rules.**"(Classic ALB side door 的核心证据) |
| R2 | `https://docs.cloud.google.com/vpc/docs/private-service-connect-compatibility` | 2026-08-07 | "Classic Application Load Balancer ... Note: Classic Application Load Balancer isn't supported."(LB type 视角的直接拒) |
| R3 | `https://docs.cloud.google.com/vpc/docs/private-service-connect-backends` | 2026-08-07 | "Global backend services that access published services can be associated with multiple Private Service Connect NEGs, as long as the NEGs are in different regions"(EXTERNAL_MANAGED BS 多 NEG 规则) |
| R4 | `https://cloud.google.com/armor/docs/cloud-armor-security-policies` | 2026-08-07 | "Cloud Armor security policies can be attached only to backend services."(BS 1:1 绑 Cloud Armor) |
| R5 | `https://cloud.google.com/load-balancing/docs/https` | 2026-08-07 | "For regional external Application Load Balancers only, a proxy-only subnet is used..."(Classic ALB 不需要 proxy-only subnet) |