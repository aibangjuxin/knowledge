# public-fqdn-explorer — Tenant→Master 跨项目 + Nginx 路径分流全栈探索

> **场景**：用户在 Tenant 工程 (Project A) 上有 `https://team1.caep.uk/apiname1` + `https://team1.caep.uk/apiname2`,
> 希望:
> ① 请求先被 A 工程内的 GCP LB 终结 TLS;
> ② 通过 PSC 进入 Master 工程 (Project B);
> ③ 在 B 工程内部署一个 **Nginx 反向代理**,按 URL 路径 (`/apiname1`、`/apiname2`) 分流到 K8s Gateway;
> ④ K8s Gateway 监听到对应 path 路由后,转发到后端 GKE Namespace 或 Deployment。
>
> **本质问题**:在 PSC 边界后的 Master 侧,**是否一定要 Nginx 才能实现"按 path 分流到不同 Gateway"?**
> 还是说 Gateway/HTTPRoute/GLB URL Map 本身就能 cover 这件事?
>
> **目录位置**: `/Users/lex/git/knowledge/cloud/k8s/k8s-gateway/`
> (本目录已有 5 个 working doc:`tenant-namespace-k8s-gateway.md` / `tenant-namespace-newapi-team1-appdev-aibang.md` /
> `k8s-gateway-timeout.md` / `DestinationRule.md` / `k8s-gateway-netpol.md`,本文件是 `public-fqdn-explorer` 综合探索记录)

---

## 0. 原始问题(Lex 原话 verbatim,未经 paraphrase)

> 按照我们目前的架构,所有的用户请求都到 tenant project。假如说现在有个域名叫
> `team1.caep.uk`,我们想针对这个用户不同这个用户肯定有不同的 API,比如说叫
> `APIname1`、`APIname2`。
> `https://team1.caep.uk/apiname1`
> `https://team1.caep.uk/apiname2`
> 架构实现参考 `/Users/lex/git/gcp/ingress/public-tls-ingress/tenant-tls-idmz-https-architecture.html`
> 而且按照我们目前的实现,是通过 cross project,以 PSC 的方式将请求跳转到另一个 gcp 工程上面。
> 我们可以把这个工程称之为 B 工程,或者叫 master project。我想在这个工程上配置一个对应的
> **Nginx**,它会侦听该域名,并根据不同的用户 location 路径,将请求转发到后面对应的我的一个
> **Gateway**,当然这个 gateway 不是给这一个 team 来提供服务的,会侦探 httproute 来完成对应的服务侦听,
> 我们把这个 Gateway 称之为 **K8S Gateway**。关于 K8S Gateway 可以参考我的实现在这里
> `/Users/lex/git/gcp/gateway-2.0/k8s-gateway/k8s-gateway-arch-flow.html`
> 然后,我会针对该 Team 请求的域名进行不同的转发。然后将请求转发到后端对应的
> **GKE Namespace 或 Deployment**。
>
> 我理解配置 nginx proxy pass to my Gatewaay
> 如果从最终结果来看就是要确保用户请求能到达最终的 Deployment 确保路径做对应处理就可可以了?
> 或者或者还有其他可能的实现方法。我需要你基于这些背景信息,帮我探索如何实现,以及可能的对应的
> nginx 配置或者 httproute
> 帮我把上面需求和探索结果都放在目录 `/Users/lex/git/knowledge/cloud/k8s/k8s-gateway/` 目录下
> 命名为 `public-fqdn-explorer.md`

### 0.1 Lex 已经在心里但没说出来的 5 个隐性约束(从原话反推)

| # | 隐性约束 | 推导依据 |
|---|---------|----------|
| 1 | **PSC 边界已存在,Master 侧能拿到的入口是 ILB/FR 上的某个 internal IP**(不是公网 IP) | "通过 cross project,以 PSC 的方式将请求跳转到另一个 gcp 工程上面" |
| 2 | **Master 侧 K8s Gateway 是多 team 共享的**(不是只服务 team1) | "这个 gateway 不是给这一个 team 来提供服务的,会侦探 httproute 来完成对应的服务侦听" |
| 3 | **K8s Gateway 已经会解析 HTTPRoute**,只是缺一个"按 path 路由"的入口机制 | "会侦探 httproute 来完成对应的服务侦听" |
| 4 | **目标域名是 wildcard + 子域名模式**(`*.team1.caep.uk`),否则 API 路径会被两个层级的 hostname 同时考虑 | "域名 team1.caep.uk,用户不同 API 不同 → 实际是 `*.team1.caep.uk/apinameN` |
| 5 | **Lex 假设"一定要 Nginx"**,所以需要被告知"Nginx 是其中一种实现,不是唯一" | "我想在这个工程上配置一个对应的 Nginx" |

### 0.2 一句话核心结论(对 Lex 提问的直接回答)

> **"一定要 Nginx 吗?"——不是。**
> 这条流至少有 **5 种实现路径**,Nginx 只是其中最经典、最易调试的一种。
> 选择取决于三个维度:
> ① Master 工程是否已有共享 K8s Gateway(已有 → 用 HTTPRoute rewrite path;没有 → 必须先建一个);
> ② 是否需要在 Master 侧做 path-based 路由以外的额外逻辑(灰度/限流/认证);
> ③ 是否接受 GCLB URL Map 的 path rule(它能做 path match,但 hostname 通配需手工维护)。
>
> **如果只是"按 path 路由到不同后端",K8s Gateway + HTTPRoute 的 path matcher 足以 cover,不需要 Nginx。**
> Nginx 的真正价值是当你要在 Master 侧做"GLB / Gateway 都不擅长的逻辑"(请求重写、协议转换、header 注入、统一限流)时。

---

## 1. 总体架构图(Tenant → Master → MIG(Nginx) → K8s Gateway → Deployment)

```
┌────────────────────────────────────────────────────────────────────────┐
│ INTERNET                                                               │
│   curl https://team1.caep.uk/apiname1                                  │
│   curl https://team1.caep.uk/apiname2                                  │
└─────────────┬──────────────────────────────────────────────────────────┘
              │ DNS → 34.x.x.x (Tenant A 的 EXTERNAL_MANAGED GLB IP)
              ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PROJECT A (Tenant) — Cert: *.team1.caep.uk (Tenant GLB 已就位)        │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ GLB (EXTERNAL_MANAGED, regional)                                 │  │
│ │   - Frontend: HTTPS :443                                          │  │
│ │   - URL Map: default → PSC NEG                                   │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                │                                                       │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ Backend Service (EXTERNAL_MANAGED)                               │  │
│ │   backend: PSC NEG (cross-project target → Master B)              │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
└────────────────┼───────────────────────────────────────────────────────┘
                 │ PSC Tunnel (Tenant A → Producer B)
                 │ consumer VPC subnet (B side) ↔ producer SA (B side)
                 ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PROJECT B (Master)                                                     │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ Service Attachment (Producer)                                     │  │
│ │   target: ILB INTERNAL_MANAGED (10.0.1.4:443)                    │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                │                                                       │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ L7 Internal HTTPS ILB (10.0.1.4:443)                            │  │
│ │   TLS #2 terminate here (ILB cert = wildcard team1.caep.uk)       │  │
│ │   backend NEG → MIG instances                                    │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                │                                                       │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ ★★★ Master B MIG: 1+ VM instances,内部跑 nginx (Lex 已确认)    │  │
│ │   nginx listen 443, ssl_certificate *.team1.caep.uk              │  │
│ │   server {                                                        │  │
│ │     location /apiname1/ → proxy_pass https://<k8s-gw>:443        │  │
│ │     location /apiname2/ → proxy_pass https://<k8s-gw>:443        │  │
│ │   }                                                               │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                │                                                       │
│                │  ★ <k8s-gw> 可达地址(三选一,见 §3.2.1):              │
│                │  (a) GKE Gateway controller 创建的 ILB VIP          │
│                │  (b) K8s Gateway Envoy pod ClusterIP/FQDN           │  │
│                │  (c) K8s Gateway 暴露的 NEG IP                       │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ GKE Cluster (B 工程内, Lex 已确认存在 K8s Gateway)              │  │
│ │   K8s Gateway (istio class)                                       │  │
│ │     ListenerSet: 多个 team 共享                                   │  │
│ │       team1-listenerset hostname=*.team1.caep.uk                   │  │
│ │       team2-listenerset hostname=*.team2.caep.uk                   │  │
│ │     HTTPRoute (tenant NS):                                         │  │
│ │       team1/apiname1-route PathPrefix=/apiname1 → apiname1-svc   │  │
│ │       team1/apiname2-route PathPrefix=/apiname2 → apiname2-svc   │  │
│ └─────────────┬────────────────────────────────────────────────────┘  │
│                │                                                       │
│                ▼                                                       │
│ ┌──────────────────────────────────────────────────────────────────┐  │
│ │ Backend Deployments (Lex 已确认存在)                              │  │
│ │   team1/apiname1 (port 8080)                                       │  │
│ │   team1/apiname2 (port 8080)                                       │  │
│ └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

**关键事实(基于 Lex 2026-08-06 confirm)**:
- **Master B 已经有 K8s Gateway + GCLB-based 入口**(✓ 假设 1 确认)
- **K8s Gateway 支持 cross-project PSC**(GCLB-based Gateway controller 已支持,nginx 只需 proxy_pass 到 K8s Gateway 可达地址)
- **Master B 入口组件是 MIG(VM),不是 K8s Pod**——nginx 跑在 VM 上,由 startup script 拉配置
- **Tenant GLB cert 已就位**(`.team1.caep.uk`)
- **apiname1 / apiname2 后端 Deployment 已存在**
- **适配的 cert 已存在**(Tenant cert 是 source of truth,Master B 的 ILB cert / MIG nginx cert 都是它的副本)

**Nginx 的真实定位**:**Master B 的 L7 入口边缘**,负责按 path 分流 + (可选)做 Gateway 不擅长的协议转换/限流/header 注入。它的 upstream 是 K8s Gateway,不是直接到后端 Deployment——K8s Gateway 才是"侦探 httproute"的那一层。

---

## 2. 5 种实现方案对比矩阵

### 2.1 决策矩阵(看完就能选)

| 维度 | 方案 A:Nginx Pod | 方案 B:K8s GW + HTTPRoute path | 方案 C:HTTPRoute rewrite path | 方案 D:GLB URL Map path rule | 方案 E:Nginx sidecar |
|------|------------------|------------------------------|------------------------------|------------------------------|----------------------|
| **核心思路** | Nginx 反代 → Gateway | Gateway 直接看 path | Gateway 看 path + 重写 | GLB 看 path → 不同 backend | Nginx 在 GW pod 内 |
| **新增组件** | Nginx Deployment + ConfigMap | 仅 HTTPRoute | HTTPRoute (rewrite filter) | GLB + URL Map + 多 BS | 修改 Gateway Deployment |
| **Master 侧入口** | ILB → Nginx NodePort | ILB → K8s Gateway (GCLB) | ILB → K8s Gateway (GCLB) | 自建 EXTERNAL_MANAGED GLB | ILB → K8s Gateway |
| **path match 在哪** | Nginx `location` | HTTPRoute `rules.matches[].path` | HTTPRoute `rules[].filters.urlRewrite` | URL Map `pathMatcher` | Nginx `location` |
| **多 team 复用** | ✅ Nginx 按 Host + Path 分 | ✅ ListenerSet 隔离 | ✅ ListenerSet 隔离 | ✅ URL Map path rule | ❌ 绑死在某个 GW pod |
| **配置复杂度** | 中(Nginx conf + 4 个 YAML) | 低(2 个 YAML per team) | 低(2 个 YAML per team) | 高(GLB + URL Map + 多个 BS + cert) | 中-高(改 deployment) |
| **运维负担** | Nginx 版本升级 / conf drift | 纯 K8s 资源 | 纯 K8s 资源 | GLB/URL Map 是 gcloud resource | 升级耦合 Gateway |
| **协议转换能力** | ✅ 强(HTTP/HTTPS/gRPC 都行) | ⚠️ 中(主要 HTTP/HTTPS) | ⚠️ 中(主要 HTTP/HTTPS) | ❌ 弱(只能 HTTP/HTTPS) | ✅ 强 |
| **header 注入** | ✅ proxy_set_header | ✅ HTTPRoute filter | ✅ HTTPRoute filter | ❌ 需 BackendService 自定义 header | ✅ proxy_set_header |
| **限流/灰度** | ✅ Lua / limit_req | ✅ HTTPRoute weight | ✅ HTTPRoute weight | ❌ 不支持 | ✅ Lua |
| **mTLS 终结** | ✅ ssl_certificate | ⚠️ Gateway ListenerSet TLS | ⚠️ Gateway ListenerSet TLS | ✅ GLB 自带 | ✅ ssl_certificate |
| **跨 namespace backend** | ✅ proxy_pass to any upstream | ✅ HTTPRoute + ReferenceGrant | ✅ HTTPRoute + ReferenceGrant | ❌ 受限 | ✅ |
| **故障定位难度** | 中(Nginx + GW + Pod) | 低(单层 GW) | 低(单层 GW) | 中(GLB + GW + Pod) | 高(耦合) |
| **是否要新增 GCLB** | ❌(复用 ILB) | ❌(Gateway 自管 GCLB) | ❌(Gateway 自管 GCLB) | ✅(必须建 GLB) | ❌ |
| **是否要新增 SSL** | ✅ Nginx 自管 cert | ⚠️ ListenerSet 引用 secret | ⚠️ ListenerSet 引用 secret | ✅ GLB cert | ✅ Nginx 自管 cert |
| **Lex 当前架构兼容性** | ✅ 直接 fit | ✅ 直接 fit | ✅ 直接 fit | ⚠️ 要重建 GLB(可能破坏 PSC 拓扑) | ❌ 要改 Gateway deployment |
| **推荐度(纯 path 路由)** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐ |

### 2.2 决策树(3 步选方案)

```
START: Master 侧有 K8s Gateway 吗?
│
├─ ❌ 没有 ──────────→ 必须先建 Gateway,然后走 B/C/E
│
└─ ✅ 有
   │
   ├─ 只需要 path 路由到不同 service?
   │  │
   │  ├─ 后端要求去掉 path 前缀(如 /apiname1/xxx 实际打 /xxx)?
   │  │  └─ ✅ 选方案 C (HTTPRoute rewrite)
   │  │
   │  └─ 后端能接受 path 前缀保留?
   │     └─ ✅ 选方案 B (HTTPRoute path match,最简)
   │
   ├─ 需要做 Nginx 才能做的事(Lua 限流/协议转换/特殊 header 处理)?
   │  └─ ✅ 选方案 A (Nginx Pod)
   │
   └─ 想在 Master 侧完全摆脱 K8s Gateway(只用 GCP 原生)?
      └─ ⚠️ 方案 D (GLB URL Map),但要付出"维护 hostname 列表"的代价
```

### 2.3 三个最常见误区的反例

| 反模式 | 为什么错 | 正确做法 |
|--------|---------|---------|
| "Nginx 是必须的,否则 path 路由做不了" | K8s Gateway API `HTTPRoute.spec.rules[].matches[].path` 本身就是 path 匹配器,完全能做 | 用方案 B,4-YAML 模式(本目录已有模板) |
| "在 Tenant GLB URL Map 上做 path rule,Master 侧就不用再处理" | 但 Tenant GLB 看到 `*.team1.caep.uk` 的请求,如果不 strip path 就把 `/apiname1` 也带到 Master → 后端要重新处理 | path rule 在 Master 侧做(Gateway/Nginx),不在 Tenant GLB |
| "Nginx 转发到 Gateway 时,Gateway 要不要重新 TLS 终结?" | Gateway 是 `class: istio`,会接受 HTTPS。Nginx 用 `proxy_pass https://gateway:443` 即可 | Nginx 用 `proxy_set_header Host team1.caep.uk` 让 Gateway 知道原始 Host |

---

## 3. 方案 A:Master B 侧 MIG VM 跑 Nginx 反向代理(Lex 实际架构)

> **Lex 2026-08-06 confirm**:Master 工程 B 的入口层是 1 个或多个 MIG(VM 实例),
> VM 内跑 nginx(由 startup script 拉 nginx.conf + cert),
> nginx proxy_pass 到 K8s Gateway,K8s Gateway 通过 HTTPRoute 分流到后端 Deployment。

### 3.1 架构图(MIG 视角)

```
[ILB :443] ──→ [MIG NEG (zone)]
                       │
                       ▼
┌────────────────────────────────────────────────────────┐
│ MIG VM instance (e.g. e2-medium, debian-12 / cos-stable)│
│  ┌──────────────────────────────────────────────────┐  │
│  │ nginx (system service, listen :443)               │  │
│  │   - /etc/nginx/conf.d/team1-caep-uk.conf          │  │
│  │   - /etc/nginx/certs/team1-caep-uk.{crt,key}      │  │
│  │   - ssl_certificate (wildcard team1.caep.uk)      │  │
│  │                                                   │  │
│  │   server {                                         │  │
│  │     server_name team1.caep.uk;                     │  │
│  │     location /apiname1/ {                          │  │
│  │       proxy_pass https://<k8s-gw>:443;            │  │
│  │       proxy_set_header Host team1.caep.uk;        │  │
│  │       rewrite ^/apiname1/(.*)$ /$1 break;         │  │
│  │     }                                              │  │
│  │     location /apiname2/ {                          │  │
│  │       proxy_pass https://<k8s-gw>:443;            │  │
│  │       proxy_set_header Host team1.caep.uk;        │  │
│  │       rewrite ^/apiname2/(.*)$ /$1 break;         │  │
│  │     }                                              │  │
│  │   }                                                │  │
│  └────────────────────┬─────────────────────────────┘  │
└───────────────────────┼─────────────────────────────────┘
                        │
                        │ <k8s-gw>:443 (HTTPS, SNI=team1.caep.uk)
                        ▼
┌────────────────────────────────────────────────────────┐
│ GKE Cluster (B 工程内)                                  │
│   K8s Gateway Envoy (istio Gateway controller 管理的   │
│   Service "abjx-gw-int-istio" 或者 NEG IP)             │
│     HTTPRoute team1/apiname1-route PathPrefix=/apiname1│
│       → apiname1 Deployment                            │
│     HTTPRoute team1/apiname2-route PathPrefix=/apiname2│
│       → apiname2 Deployment                            │
└────────────────────────────────────────────────────────┘
```

### 3.2 Nginx ConfigMap(完整可部署)

#### 3.2.1 upstream 地址选择(三选一)

nginx 怎么"找到"K8s Gateway?核心问题:**MIG VM 跟 K8s Gateway Envoy 在哪个网络**?

| 方案 | upstream 写法 | 适用场景 | 注意事项 |
|------|---------------|----------|----------|
| **(a) GCLB-created ILB VIP** | `server 10.0.5.10:443;` | MIG 在 B 工程,跟 K8s Gateway ILB 同 VPC | 这是 Gateway controller 自动创建的 ILB,最稳 |
| **(b) Envoy pod ClusterIP/FQDN** | `server abjx-gw-int-istio.abjx-gw-int.svc.cluster.local:443;` | MIG 在 GKE 节点上(同一节点或同 subnet) | 需要 MIG VM 能解析 K8s DNS,通常不行 |
| **(c) NEG IP** | `server 10.0.7.5:443;` | 混合部署 | NEG IP 是 Gateway 自动创建的 |

**推荐 (a)**:GCLB-based Gateway controller 自动创建的 ILB VIP。

**验证方法**:
```bash
# 找 K8s Gateway 对应的 ILB VIP
kubectl get gateway -n abjx-gw-int abjx-gw-int -o jsonpath='{.status.addresses[0].value}'
# 期望: 10.0.5.10 (或其他 internal VIP)
```

#### 3.2.2 nginx.conf(VM 上 `/etc/nginx/conf.d/team1-caep-uk.conf`)

```nginx
# /etc/nginx/conf.d/team1-caep-uk.conf
# 适用:Master B MIG VM,由 startup script 从 GCS bucket 拉下来
#
# upstream: K8s Gateway (GCLB-based Gateway controller 管理的 ILB)
# ★ Lex 在 production 替换 <K8S_GW_VIP> 为实际 ILB VIP (e.g. 10.0.5.10)
upstream k8s_gateway {
    server <K8S_GW_VIP>:443;
    keepalive 32;

    # 如果 K8s Gateway 暴露 NEG IP 池,这里可以加多个 server + keepalive
    # server 10.0.5.10:443;
    # server 10.0.5.11:443;
}

# HTTPS server (Nginx 自己终结 TLS,然后用 HTTPS 转给 Gateway)
server {
    listen 443 ssl;
    server_name team1.caep.uk *.team1.caep.uk;

    # SSL cert: 跟 Tenant GLB 同源的 wildcard team1.caep.uk cert
    # ★ Lex 已确认 cert 存在;production 替换为实际路径
    ssl_certificate     /etc/nginx/certs/team1-caep-uk.crt;
    ssl_certificate_key /etc/nginx/certs/team1-caep-uk.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # 安全 + 性能
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_prefer_server_ciphers on;

    # 健康检查
    location = /healthz {
        access_log off;
        return 200 "nginx ok\n";
        add_header Content-Type text/plain;
    }

    # ===== 路径分流核心 =====

    # /apiname1 → K8s Gateway → HTTPRoute team1/apiname1-route → apiname1 Deployment
    location /apiname1/ {
        proxy_pass https://k8s_gateway;
        proxy_ssl_server_name on;            # SNI = team1.caep.uk
        proxy_set_header Host team1.caep.uk;   # ★ Gateway 看 Host 头做 hostname match
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Original-URI $request_uri;

        # ★ strip path prefix(让后端看到 /users 而不是 /apiname1/users)
        #   - 如果后端能接受保留前缀,删掉这一行
        #   - 如果只想改写而非 strip,改成 rewrite ^/apiname1/(.*)$ /v2/$1 break;
        rewrite ^/apiname1/(.*)$ /$1 break;

        proxy_http_version 1.1;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

    # /apiname2 → K8s Gateway → HTTPRoute team1/apiname2-route → apiname2 Deployment
    location /apiname2/ {
        proxy_pass https://k8s_gateway;
        proxy_ssl_server_name on;
        proxy_set_header Host team1.caep.uk;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Original-URI $request_uri;

        rewrite ^/apiname2/(.*)$ /$1 break;

        proxy_http_version 1.1;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

    # 兜底:任何非 /apiname1 / /apiname2 的请求
    location / {
        return 404 "path not found\n";
        add_header Content-Type text/plain;
    }
}

# HTTP (80) → HTTPS (443) 重定向(可选)
server {
    listen 80;
    server_name team1.caep.uk *.team1.caep.uk;
    return 301 https://$host$request_uri;
}
```

**关于 `rewrite` 的两种语义**(踩坑必读):

```nginx
# (1) break — Nginx 内部重写,proxy_pass 用重写后的 URI
location /apiname1/ {
    rewrite ^/apiname1/(.*)$ /$1 break;     # ← 改写后 proxy_pass 拿到 /
    proxy_pass https://k8s_gateway;          # ← 实际请求 /xxx
}

# (2) 不 rewrite — proxy_pass 收到完整 /apiname1/xxx
location /apiname1/ {
    proxy_pass https://k8s_gateway;          # ← 实际请求 /apiname1/xxx
}
```

**`proxy_pass` 末尾带不带 `/` 的差异**(Lex 反复困惑):

```nginx
# 写法 1:不带 / → Nginx 把 location 完整拼接到 upstream
location /apiname1/ {
    proxy_pass https://k8s_gateway;          # 请求 /apiname1/xxx → 上游也打 /apiname1/xxx
}

# 写法 2:带 / → Nginx 用 / 替换 location 前缀
location /apiname1/ {
    proxy_pass https://k8s_gateway/;         # 请求 /apiname1/xxx → 上游打 /xxx
}

# 写法 3:带 URI → 同写法 2
location /apiname1/ {
    proxy_pass https://k8s_gateway/api/;     # 请求 /apiname1/xxx → 上游打 /api/xxx
}
```

**组合策略**(推荐):

```nginx
# 想 strip 前缀 + 重写 URI → rewrite break + proxy_pass https://upstream
# 想保留前缀 → 不 rewrite + proxy_pass https://upstream
# 想 strip 前缀但重写到 /api/ → rewrite break + proxy_pass https://upstream/api/
```

### 3.3 MIG instance template + startup script(完整可部署)

> 整套部署是 **gcloud compute instance-templates create** + **managed instance group**,
> VM 启动时由 startup script 从 GCS bucket 拉 nginx.conf + cert,
> 然后 `systemctl enable --now nginx`。

#### 3.3.1 startup script(VM 启动时跑)

```bash
#!/bin/bash
# /tmp/startup.sh (由 MIG instance template 引用)
# 适用:Master B MIG VM (e2-medium / cos-stable)
# 用途:从 GCS bucket 拉 nginx.conf + cert,启动 nginx

set -euxo pipefail

# 1. 安装 nginx (Debian 12 / Ubuntu 22.04 LTS)
apt-get update -y
apt-get install -y nginx

# 2. 从 GCS bucket 拉 nginx.conf
# ★ 实际替换 <BUCKET_NAME> 为 Master B 工程的 nginx config bucket
gcloud storage cp gs://<BUCKET_NAME>/nginx/team1-caep-uk.conf \
  /etc/nginx/conf.d/team1-caep-uk.conf

# 3. 从 GCS bucket 拉 cert
mkdir -p /etc/nginx/certs
gcloud storage cp gs://<BUCKET_NAME>/certs/team1-caep-uk.crt \
  /etc/nginx/certs/team1-caep-uk.crt
gcloud storage cp gs://<BUCKET_NAME>/certs/team1-caep-uk.key \
  /etc/nginx/certs/team1-caep-uk.key
chmod 600 /etc/nginx/certs/team1-caep-uk.key

# 4. 验证配置 + 启动 nginx
nginx -t
systemctl enable nginx
systemctl restart nginx

# 5. 输出 ready 标记(LB health check 看 /healthz)
echo "nginx startup complete"
```

#### 3.3.2 MIG instance template(完整 gcloud 命令)

```bash
# 创建 MIG instance template
gcloud compute instance-templates create nginx-team1-proxy-tmpl \
  --project=<B> \
  --region=<REGION> \
  --machine-type=e2-medium \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --network=<B_VPC> \
  --subnet=<B_PROXY_SUBNET> \
  --no-address \
  --tags=nginx-team1-proxy,https-443 \
  --metadata-from-file=startup-script=./startup.sh \
  --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write \
  --service-account=<NGINX_SA>@<B>.iam.gserviceaccount.com

# 创建 managed instance group
gcloud compute instance-groups managed create nginx-team1-proxy-mig \
  --project=<B> \
  --base-instance-name=nginx-team1-proxy \
  --template=nginx-team1-proxy-tmpl \
  --size=2 \
  --zone=<ZONE>

# 创建 standalone NEG(zonal 或 regional)给 ILB 用
gcloud compute network-endpoint-groups create nginx-team1-neg \
  --project=<B> \
  --network-endpoint-type=GCE_VM_IP_PORT \
  --zone=<ZONE> \
  --network=<B_VPC> \
  --subnet=<B_PROXY_SUBNET>

# 把 MIG 实例加进 NEG
gcloud compute network-endpoint-groups update nginx-team1-neg \
  --project=<B> \
  --zone=<ZONE> \
  --add-endpoint="instance=nginx-team1-proxy-mig-xxxx,port=443"

# 给 LB health check 创建 firewall rule(LB HC IP 段)
gcloud compute firewall-rules create nginx-team1-allow-lb-hc \
  --project=<B> \
  --network=<B_VPC> \
  --direction=INGRESS \
  --action=ALLOW \
  --source-ranges=35.191.0.0/16,130.211.0.0/22 \
  --target-tags=https-443 \
  --rules=tcp:443
```

#### 3.3.3 cert 同步流程(从 Tenant GLB 拉到 GCS bucket)

> **Lex 已确认 cert 存在**(Tenant GLB 已就位)。
> 但 Master B 的 MIG nginx 也要同一份 cert(不然 nginx TLS 终结失败)。
> 推荐流程:**从 Tenant A 拉的 cert 推到 Master B 的 GCS bucket**。

```bash
# 在 Master B 工程,定时任务(cron 或 Cloud Scheduler)从 Tenant A 拉 cert
# 例:用 gcloud + workload identity
gcloud storage cp gs://<A_BUCKET>/certs/team1-caep-uk.crt \
  gs://<B_BUCKET>/certs/team1-caep-uk.crt

gcloud storage cp gs://<A_BUCKET>/certs/team1-caep-uk.key \
  gs://<B_BUCKET>/certs/team1-caep-uk.key
```

**生产改进**:
- **cert 自动化**:Cloud Scheduler + Cloud Run job,每天从 Tenant A Secret Manager 拉 → 推到 GCS
- **nginx reload**:cert 推到 GCS 后,MIG 实例自动 reload(可选:用 inotifywait 或 systemd path unit)
- **验证 modulus 匹配**(参考 `cert-format-preflight` skill):cert 跟 key 的 modulus 必须匹配

#### 3.3.4 HTTPRoute 侧(K8s Gateway 内部的路由规则)

> 这部分由 tenant team apply,跟 MIG 部署无关。完整 4-YAML 模式见
> 本目录 `tenant-namespace-newapi-team1-appdev-aibang.md`。

```yaml
# 在 tenant NS (team1) 里 apply,HTTPRoute 已经按 path match 路由
# (详细 YAML 见 §3.4)
```

### 3.4 K8s Gateway 侧 HTTPRoute(配套)

```yaml
# K8s Gateway 已经按 *.team1.caep.uk hostname 接受请求
# HTTPRoute 由 tenant team1 apply,BackendRef 指向各自 service
# 这部分由团队 apply,跟 Nginx 无关
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: apiname1-route
  namespace: team1
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listenerset
      namespace: abjx-listenerset-int
      sectionName: https
  hostnames:
    - team1.caep.uk
  rules:
    # ★ 关键:接收 strip 后的路径(如果 Nginx 用 rewrite break)
    # 或者接收完整路径(如果 Nginx 不 rewrite)
    # 这里假设 Nginx 已 strip,所以 Gateway 看到 /
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: apiname1-svc
          port: 8080
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: apiname2-route
  namespace: team1
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listenerset
      namespace: abjx-listenerset-int
      sectionName: https
  hostnames:
    - team1.caep.uk
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: apiname2-svc
          port: 8080
```

### 3.5 验证 5 步法(方案 A · MIG nginx 视角)

```bash
# ==== 1. MIG 实例就绪 ====
gcloud compute instance-groups managed list-instances nginx-team1-proxy-mig \
  --project=<B> --zone=<ZONE>
# 期望:2 instances, status=RUNNING

# ==== 2. nginx 服务在 VM 上跑 ====
gcloud compute ssh nginx-team1-proxy-mig-xxxx \
  --project=<B> --zone=<ZONE> --command="systemctl status nginx"
# 期望:active (running)

# ==== 3. 集群外 curl MIG 的 internal IP(模拟 LB health check)====
MIG_IP=$(gcloud compute instances list \
  --project=<B> --filter="name~nginx-team1-proxy-mig" \
  --format="value(EXTERNAL_IP,INTERNAL_IP)" | head -1)
curl -k -v --resolve "team1.caep.uk:443:${MIG_IP}" \
  "https://team1.caep.uk/healthz"
# 期望:HTTP/2 200, body "nginx ok"

# ==== 4. 集群内 curl K8s Gateway(确认 Gateway 也能通) ====
GATEWAY_IP=$(kubectl get gateway -n abjx-gw-int abjx-gw-int \
  -o jsonpath='{.status.addresses[0].value}')
# 在 GKE cluster 内跑:
kubectl run curl-test --rm -it --restart=Never \
  --image=curlimages/curl:8.10.1 -n team1 -- \
  curl -k --resolve "team1.caep.uk:443:${GATEWAY_IP}" \
  "https://team1.caep.uk/apiname1/healthz"

# ==== 5. 走完整链路:外部 → Tenant GLB → PSC → Master ILB → MIG nginx → K8s Gateway → Deployment ====
# (DNS 必须已就绪)
curl -k -v "https://team1.caep.uk/apiname1/healthz"
# 期望:HTTP/2 200, body 来自 apiname1 Deployment
```

---

## 4. 方案 B:K8s Gateway + HTTPRoute path match(推荐,Lex 最简方案)

### 4.1 架构图

```
[ILB :443] ──→ [K8s Gateway (istio)]
                       │
        ┌──────────────┴──────────────┐
        │                             │
        ▼                             ▼
[HR: apiname1-route]          [HR: apiname2-route]
   /apiname1 → svc:8080         /apiname2 → svc:8080
        │                             │
        ▼                             ▼
[Deployment apiname1]         [Deployment apiname2]
```

### 4.2 HTTPRoute(直接按 path 分流,无 Nginx)

```yaml
# 适用:Master 工程已有 K8s Gateway,不需要 Nginx
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: apiname1-route
  namespace: team1
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listenerset
      namespace: abjx-listenerset-int
      sectionName: https
  hostnames:
    - team1.caep.uk
  rules:
    - matches:
        # ★ 核心 path match
        - path:
            type: PathPrefix
            value: /apiname1
      backendRefs:
        - name: apiname1-svc
          port: 8080
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: apiname2-route
  namespace: team1
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listenerset
      namespace: abjx-listenerset-int
      sectionName: https
  hostnames:
    - team1.caep.uk
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /apiname2
      backendRefs:
        - name: apiname2-svc
          port: 8080
```

**这个方案不需要任何 Master 侧额外资源**——只需要 apply HTTPRoute 到 team1 NS。

### 4.3 验证 5 步法(方案 B)

```bash
# 1. HTTPRoute 状态:必须 Accepted=True
kubectl get httproute -n team1 apiname1-route -o yaml | grep -A 20 'status:'
kubectl get httproute -n team1 apiname2-route -o yaml | grep -A 20 'status:'

# 期望:
#   parents:
#   - conditions:
#     - lastTransitionTime: ...
#       status: "True"
#       type: Accepted
#     - status: "True"
#       type: ResolvedRefs

# 2. 集群内直接 curl Gateway
GATEWAY_SVC_IP=$(kubectl get svc -n abjx-gw-int abjx-gw-int-istio -o jsonpath='{.spec.clusterIP}')
curl -k -v --resolve "team1.caep.uk:443:${GATEWAY_SVC_IP}" \
  "https://team1.caep.uk/apiname1/healthz"

# 3. 走 ILB(模拟 PSC 入口)
ILB_IP=$(gcloud compute forwarding-rules describe <FR_NAME> --region=<REGION> --project=<B> --format='value(IPAddress)')
curl -k -v --resolve "team1.caep.uk:443:${ILB_IP}" \
  "https://team1.caep.uk/apiname1/healthz"

# 4. 模拟跨 project 走 PSC(Tenant → Master)
TENANT_IP=$(gcloud compute addresses describe <IP_NAME> --region=<REGION> --project=<A> --format='value(address)')
curl -k -v -H "Host: team1.caep.uk" "https://${TENANT_IP}/apiname1/healthz"

# 5. 外部 HTTPS(模拟真实用户)
curl -k -v "https://team1.caep.uk/apiname1/healthz"
```

### 4.4 失败模式速查(方案 B 专项)

| 现象 | 根因 | 修复 |
|------|------|------|
| `HTTPRoute.status.parents[Accepted]=False, reason=NotAllowedByListeners` | tenant NS 缺 ListenerSet 要求的 label | `kubectl label ns team1 gateway-access=ajbx-int` |
| `404` from curl | ListenerSet hostname pattern 不覆盖 `team1.caep.uk` | 改 ListenerSet hostname 为 `*.team1.caep.uk` |
| `404` for `/apiname1` 但 `200` for `/` | HTTPRoute path match 路径写错 | 检查 `matches[].path.value` 是否是 `/apiname1` 而非 `/apiname1/` |
| `502 Bad Gateway` | BackendRef 的 Service 不存在 / Pod NotReady | `kubectl get svc,ep -n team1` |
| `503 Service Unavailable` | Envoy EDS 还没发现 endpoint | 等 10-30s,istiod 下发 xDS |

---

## 5. 方案 C:HTTPRoute rewrite path(后端不接受 path 前缀时)

### 5.1 适用场景

- 后端应用是 Spring Boot / FastAPI / Express,**只在 `/` 上 serve,不识别 `/apiname1/xxx`**
- 用户想要 `https://team1.caep.uk/apiname1/users` 打到后端 `/users`

### 5.2 HTTPRoute(带 rewrite filter)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: apiname1-route
  namespace: team1
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listenerset
      namespace: abjx-listenerset-int
      sectionName: https
  hostnames:
    - team1.caep.uk
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /apiname1
      filters:
        # ★ 关键:rewrite path,把 /apiname1/xxx 改成 /xxx
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacement: /
      backendRefs:
        - name: apiname1-svc
          port: 8080
```

**注意**:`ReplacePrefixMatch` 把匹配的 prefix 整段替换为 `/`。如果想保留一部分:

```yaml
filters:
  - type: URLRewrite
    urlRewrite:
      path:
        type: ReplacePrefixMatch
        replacement: /v2    # /apiname1/xxx → /v2/xxx
```

---

## 6. 方案 D:Master 侧自建 GLB URL Map path rule(放弃 K8s Gateway)

### 6.1 适用场景

- 团队完全不熟悉 K8s Gateway API
- 想用纯 gcloud 命令管理
- **不推荐**:破坏 Lex 现有 PSC 拓扑,要在 Tenant GLB 之外再建一个 GLB

### 6.2 GLB URL Map path rule(概览)

```bash
# gcloud example (not full)
gcloud compute url-maps create team1-caep-uk-um \
  --default-service team1-caep-uk-default-bs

gcloud compute url-maps add-path-matcher team1-caep-uk-um \
  --path-matcher-name=apiname-matcher \
  --default-service team1-caep-uk-default-bs \
  --path-rules="^/apiname1/.*=team1-apiname1-bs" \
  --path-rules="^/apiname2/.*=team1-apiname2-bs"
```

**两个核心缺陷**:
1. **hostname 通配**:GLB URL Map 不能"按 hostname + path 组合 match",只支持 `hostRules` 包含多个 `pathMatchers`,模式固定。
2. **后端灵活性**:GLB 后端是 NEG(VM/Pod/GCLB),不能直接对接 K8s Service + HTTPRoute path 的能力(灰度/权重/header filter)。

**结论**:除非团队对 K8s Gateway API 强烈抵触,否则**不要选方案 D**。

---

## 7. Master 侧入口层配置(ILB + PSC ServiceAttachment)

无论选哪个方案,Master 侧都需要:

```
Tenant A GLB ──(PSC)──→ Master B ServiceAttachment ──→ Master B ILB ──→ [Nginx Pod / Gateway]
```

### 7.1 Master B 侧 ServiceAttachment(对接 Tenant GLB 的 PSC NEG)

```yaml
# Master B 已有的 SA(参考 tenant-tls-idmz-https-architecture.html)
# 关键:SA 的 target 是 INTERNAL_MANAGED ILB (10.0.1.4:443)
# 这个 ILB 把流量打到 Nginx Pod (方案 A) 或 K8s Gateway (方案 B/C/E)
```

### 7.2 Master B 侧 ILB(SSL 终结点)

方案 A:ILB 后端是 Nginx Pod(用 NEG 连接)

```bash
# 创建 standalone NEG(zonal 或 regional),让 ILB 指向 Nginx Pod
gcloud compute network-endpoint-groups create nginx-team1-neg \
  --network-endpoint-type=GCLE_IPV4_PORT \
  --zone=<ZONE> \
  --project=<B>

# 把 Nginx Pod IP 加进 NEG
# Pod IP 由 K8s Service ClusterIP 派生... 实际生产用 NEG controller:
# https://cloud.google.com/kubernetes-engine/docs/concepts/network-endpoint-groups
# 推荐:用 standalone NEG + Service 的 NEG annotation
kubectl annotate svc nginx-team1-proxy -n master-proxy \
  cloud.google.com/neg='{"exposed_ports":{"443":{"name":"nginx-team1-neg"}}}'
```

方案 B/C/E:ILB 后端是 K8s Gateway(由 Gateway controller 自动创建 NEG)

```
Gateway controller 自动:
  - 创建 ILB (10.0.1.4)
  - 创建 NEG (指向 Gateway Envoy pod)
  - 配置 BackendService + URL Map
```

---

## 8. 跨 Project 端到端验证(A → B)

### 8.1 5 段链路验证(全链路)

```
用户 curl https://team1.caep.uk/apiname1/healthz
        ↓
[Tenant A] DNS → 34.x.x.x (Tenant GLB IP)
        ↓
[Tenant A] GLB TLS terminate #1 (Cert: *.team1.caep.uk)
        ↓
[Tenant A] URL Map → BackendService → PSC NEG
        ↓
[PSC Tunnel] Tenant A subnet → Producer B subnet
        ↓
[Master B] ServiceAttachment → ILB (10.0.1.4:443)
        ↓
[Master B] ILB TLS terminate #2
        ↓
[方案 A] Nginx Pod [方案 B/C/E] K8s Gateway Envoy
        ↓
[方案 A] Nginx location /apiname1/ → upstream gateway
[方案 B]   HTTPRoute path /apiname1 → service
[方案 C]   HTTPRoute path /apiname1 → rewrite / → service
        ↓
[Service → Deployment] backend Pod
        ↓
返回 /healthz = "ok"
```

### 8.2 端到端验证命令

```bash
# 1. DNS 解析
dig +short team1.caep.uk
# 期望:34.x.x.x (Tenant GLB IP)

# 2. TLS cert 校验
openssl s_client -connect team1.caep.uk:443 -servername team1.caep.uk < /dev/null 2>/dev/null | openssl x509 -noout -subject -issuer
# 期望:subject=CN = *.team1.caep.uk

# 3. 走完整链路 curl
curl -k -v "https://team1.caep.uk/apiname1/healthz"
# 期望:HTTP/2 200, body "ok"

# 4. 验证 path 分流
curl -k -v "https://team1.caep.uk/apiname2/healthz"
# 期望:HTTP/2 200, 打到 apiname2 Deployment (响应内容应该不同)

# 5. 验证 404
curl -k -v "https://team1.caep.uk/unknown"
# 期望:HTTP/2 404
```

### 8.3 三段独立验证(故障定位)

```bash
# === 段 1:Tenant GLB → PSC ===
# 在 Tenant A 集群外的 client 上,直接 curl Tenant GLB IP,绕过 DNS
TENANT_IP=$(gcloud compute addresses describe <IP_NAME> --region=<REGION> --project=<A> --format='value(address)')
curl -k -v --resolve "team1.caep.uk:443:${TENANT_IP}" "https://team1.caep.uk/apiname1/healthz"
# 如果这步 404/502,问题在 Tenant GLB 或 PSC

# === 段 2:PSC → Master ILB ===
# 在 Master B 集群内,curl ILB IP(已经是内部 IP)
ILB_IP=$(gcloud compute forwarding-rules describe <FR_NAME> --region=<REGION> --project=<B> --format='value(IPAddress)')
curl -k -v --resolve "team1.caep.uk:443:${ILB_IP}" "https://team1.caep.uk/apiname1/healthz"
# 如果这步 200 而段 1 失败,问题在 Tenant GLB

# === 段 3:Master 内部 Nginx/Gateway → Backend ===
# 在 K8s 集群内,直接 curl Gateway Service
kubectl run curl-test --rm -it --restart=Never \
  --image=curlimages/curl:8.10.1 -n team1 -- \
  curl -k "http://apiname1-svc.team1.svc.cluster.local:8080/healthz"
# 如果这步 200 而段 2 失败,问题在 Nginx / Gateway 配置
```

---

## 9. FAQ(Lex 反复追问的 8 个问题)

### Q1:Master 侧一定要 Nginx 吗?

**A:不是**。三种更轻量的方案:
- **方案 B**:直接让 K8s Gateway + HTTPRoute path match 处理(最简,推荐)
- **方案 C**:HTTPRoute rewrite path(后端不接受 path 前缀时)
- **方案 D**:自建 GLB URL Map(放弃 K8s Gateway)

Nginx 只在需要做"Gateway 不擅长的逻辑"时才必要(协议转换、Lua 限流、特殊 header 处理)。

### Q2:Nginx 转发到 Gateway 时,要重新 TLS 吗?

**A:看部署模式**:
- Nginx 和 Gateway 同集群内部:可以用 plaintext `proxy_pass http://gateway:80`,但 Gateway 通常 listen 443
- 推荐:`proxy_pass https://gateway:443` + `proxy_ssl_server_name on` + 设置 SNI

Gateway 已经是 Envoy data plane,默认 listen 443 + TLS terminate。

### Q3:`/apiname1` 的 prefix 要在 Nginx 上 strip 吗?

**A:看后端是否接受 path 前缀**:
- **接受** → Nginx 不 rewrite,Gateway 看到 `/apiname1/xxx`,HTTPRoute match `PathPrefix: /apiname1`
- **不接受** → Nginx 用 `rewrite ^/apiname1/(.*)$ /$1 break` strip,Gateway 看到 `/xxx`,HTTPRoute match `PathPrefix: /`

两种都合法,选哪种取决于后端实现。

### Q4:多 team 复用同一个 Gateway,nginx 怎么配?

**A:Nginx 按 Host + Path 双重 match**:
```nginx
server {
    listen 443 ssl;
    server_name team1.caep.uk *.team1.caep.uk;
    location /apiname1/ { proxy_pass https://k8s_gateway; }
}

server {
    listen 443 ssl;
    server_name team2.caep.uk *.team2.caep.uk;
    location /apinameX/ { proxy_pass https://k8s_gateway; }
}
```
每个 team 一个 ConfigMap + 同一个 Deployment(挂多个 conf)。

或者**更优雅**:直接用 K8s Gateway(方案 B),Nginx 都不需要。

### Q5:Nginx 部署模式?Deployment 还是 DaemonSet?

**A:Deployment + 2-3 副本足够**:
- Deployment:易扩缩容,适合流量均匀
- DaemonSet:每节点一个,适合"必须本地转发"场景
- 边车(sidecar):特殊场景(每个 Gateway Pod 配一个 Nginx)

默认 **Deployment + HPA**。

### Q6:K8s Gateway 看到的 Host 头是什么?

**A:`proxy_set_header Host team1.caep.uk`** 让 Gateway 看到原始 Host。如果忘了设,Gateway 看到的是 Nginx 的 Service FQDN(如 `abjx-gw-int-istio.abjx-gw-int.svc.cluster.local`),ListenerSet hostname match 会失败。

### Q7:跨 project 怎么调试?

**A:三段独立调试**(§8.3):
1. 段 1:Tenant GLB → PSC(在 Tenant 集群外 curl Tenant GLB IP)
2. 段 2:PSC → Master ILB(在 Master 集群内 curl ILB IP)
3. 段 3:Master 内部 Nginx/Gateway → Backend(K8s 内 curl Service)

每段独立 verify,定位故障在哪一段。

### Q8:cert 怎么管?Master 侧要不要再签一次?

**A:取决于方案**:
- **方案 A(Nginx)**:Tenant GLB 终结 TLS #1,Nginx 终结 TLS #2(用同样的 `*.team1.caep.uk` cert),Gateway 终结 TLS #3(同 cert)
- **方案 B/C/E(无 Nginx)**:Tenant GLB 终结 TLS #1,Gateway ListenerSet 终结 TLS #2(用同样的 cert)

**cert 复用**:Master 侧 cert 可以是 Tenant 侧 cert 的 copy(字节相同),由 K8s Secret 持有。Secret 必须跟 ListenerSet 在同一 NS,或者用 ReferenceGrant 跨 NS 引用(本目录 `tenant-namespace-k8s-gateway.md` §3.5 有详细规则)。

---

## 10. Lex 已选定的方案 + 备选方案对比

### 10.1 既定选择:方案 A(MIG nginx + K8s Gateway)

**Lex 2026-08-06 confirm 后的实际情况**:
- **方案 A 是 Lex 已经选定的入口架构**——Master B 的入口层是 MIG(VM 跑 nginx)
- Master B 已经有 K8s Gateway(K8s 支持 GCLB-based PSC)
- Tenant GLB cert 已就位
- apiname1/apiname2 是 Deployment
- 适配 cert 存在

**方案 A 的真实价值**:
- **MIG nginx** 是 L7 边缘,负责按 path 分流 + 终结 TLS + (可选)做 Gateway 不擅长的逻辑
- **K8s Gateway** 是动态路由层,负责按 HTTPRoute 分发到具体 Service/Pod,支持热更新/灰度/权重

两层分工清晰:**nginx 管 path,Gateway 管 route**。

### 10.2 不推荐的备选(Lex 不用,但留作对比)

**对比方案**(供未来某个 team / 某个迁移窗口参考):

| 备选 | 适用场景 | 不选的理由 |
|------|---------|-----------|
| **方案 B**:K8s Gateway + HTTPRoute path match | 未来想"省掉 nginx 这层" | Lex 当前架构已经有 MIG,移除 nginx 是 redundant 重构;但可以作为"nginx 退役后"的路径规划 |
| **方案 C**:HTTPRoute rewrite path | 后端不接受 path prefix | 仅当后端限制强时才需要;现网大多数 K8s 后端能接受 path prefix |
| **方案 D**:GLB URL Map path rule | 不想用 K8s Gateway | 破坏 PSC 拓扑,维护负担重 |
| **方案 E**:Nginx sidecar + Gateway | 协议转换 | 罕见,仅在 Envoy 不能 cover 的协议时才用 |

### 10.3 最终结论

```
Lex 原话:"我理解配置 nginx proxy pass to my Gatewaay,确保用户请求能到达最终的 Deployment
确保路径做对应处理就可可以了?或者或者还有其他可能的实现方法。"

回答(基于 Lex 2026-08-06 confirm 后):
1. ✅ 你的理解对:Lex 选方案 A(MIG nginx proxy_pass → K8s Gateway → HTTPRoute → Deployment)
2. ✅ 还有 4 种其他实现方法,但你不需要换
3. 真正的实施工作集中在 nginx.conf + MIG 部署 + cert 同步 + HTTPRoute
```

---

## 11. 配套参考文档(本目录已有)

| 文档 | 用途 |
|------|------|
| `tenant-namespace-k8s-gateway.md` | K8s Gateway + ListenerSet 完整指南 |
| `tenant-namespace-newapi-team1-appdev-aibang.md` | 4-YAML 最小集模式 + 命名假设表 |
| `k8s-gateway-timeout.md` | HTTPRoute + DestinationRule 超时配置 |
| `k8s-gateway-netpol.md` | NetworkPolicy 多租户隔离 |
| `DestinationRule.md` / `DestinationRule-insecureSkipVerify.md` | DestinationRule 详细配置 |
| `k8s-gateway-e2e/k8s-gateway-fqdn-minimax.sh` | E2E 链路探查脚本 |

**关键 reference**(其他目录):
- `/Users/lex/git/gcp/ingress/public-tls-ingress/tenant-tls-idmz-https-architecture.html` — Tenant→Master PSC + IDMZ 架构图
- `/Users/lex/git/gcp/gateway-2.0/k8s-gateway/k8s-gateway-arch-flow.html` — K8s Gateway + ListenerSet 多租户架构图
- `architectrue` skill: `k8s-gateway-listener-tenant-api` 子主题 — 4-YAML 模板 + ReferenceGrant 决策表

---

## 12. 一句话总结

> **Master 侧不一定要 Nginx。** 如果已有 K8s Gateway + ListenerSet 多租户架构,
> 直接用 **HTTPRoute path match**(方案 B)就能完成"按 `/apiname1` vs `/apiname2` 分流"的需求,
> 不需要新增任何 Master 侧基础设施;只有当 Gateway 不擅长的逻辑(Lua 限流、特殊 header、协议转换)
> 才上 Nginx(方案 A)。

---

## 13. 验证状态(基于 Lex 2026-08-06 confirm)

### 13.1 已确认的事实(原 5 条 unverified assumptions 全部 verified)

| # | 原假设 | confirm 结果 |
|---|--------|--------------|
| 1 | Master B 工程已经有 K8s Gateway + ListenerSet | ✅ **确认有** |
| 2 | K8s Gateway 支持 GCLB-based PSC | ✅ **确认支持**(K8s Gateway controller 自动管理 GCLB) |
| 3 | `team1.caep.uk` 已在 Tenant A GLB cert 里 | ✅ **确认在**(Tenant GLB cert 已就位) |
| 4 | apiname1/apiname2 是 Deployment | ✅ **确认是**(后端部署形态已确定) |
| 5 | 适配的 cert 存在 | ✅ **确认存在** |

### 13.2 新增的 3 条仍待验证细节(实施前确认)

| # | 待验证项 | 验证方法 |
|---|---------|----------|
| A | **K8s Gateway 对应 ILB VIP 实际地址**(`<K8S_GW_VIP>` 占位符值) | `kubectl get gateway -n <GATEWAY_NS> <GATEWAY_NAME> -o jsonpath='{.status.addresses[0].value}'` |
| B | **nginx.conf 推到 GCS 的路径**(`<BUCKET_NAME>` 占位符值) | `gcloud storage buckets list --project=<B> | grep nginx` |
| C | **cert 同步策略**(手动 cp / Cloud Scheduler / Secret Manager export) | 跟 platform 团队 confirm cert lifecycle 流程 |

### 13.3 关键架构信息(Lex 已确认)

- **Master B 入口 = MIG(VM 实例)**,nginx 跑在 VM 上,startup script 拉 conf + cert
- **K8s Gateway 在 B 工程内**,GCLB-based(自动管理 ILB)
- **MIG nginx → K8s Gateway** 通过 HTTPS + SNI = `team1.caep.uk` 通信
- **Tenant GLB cert 是 source of truth**,Master B 的 ILB cert / MIG nginx cert 都是它的副本

---

## 14. 变更日志

- **2026-08-06**:初版(Lex 2026-08-06 探索请求),§0 原话 + §N 探索结构,5 方案对比矩阵 + 决策树,方案 A Nginx conf + Deployment,方案 B/C/D/E 完整 YAML,8 FAQ,推荐方案 B(K8s Gateway + HTTPRoute path match)