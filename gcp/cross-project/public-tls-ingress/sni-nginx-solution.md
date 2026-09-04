- [SNI 注入解决方案:Nginx 主机 + 动态注册](#sni-注入解决方案nginx-主机--动态注册)
  - [0. 一句话摘要](#0-一句话摘要)
  - [1. 业务方原始构想](#1-业务方原始构想)
    - [1.1 业务方原话](#11-业务方原话)
    - [1.2 业务方配置解析](#12-业务方配置解析)
    - [1.3 业务方构想的本质](#13-业务方构想的本质)
  - [2. 4 个候选方案对比](#2-4-个候选方案对比)
    - [2.1 方案 A 详解(裸 Nginx + OpenResty,业务方原始构想)](#21-方案-a-详解裸-nginx--openresty业务方原始构想)
    - [2.2 方案 B 详解(Envoy Gateway,2026 主流推荐)](#22-方案-b-详解envoy-gateway2026-主流推荐)
    - [2.3 方案 C 详解(NGINX Gateway Fabric,NGINX Inc. 官方维护)](#23-方案-c-详解nginx-gateway-fabricnginx-inc-官方维护)
    - [2.4 方案 D 详解(Cilium Gateway API,2026 新兴)](#24-方案-d-详解cilium-gateway-api2026-新兴)
  - [3. 架构师强烈推荐:不要选方案 A(裸 Nginx)](#3-架构师强烈推荐不要选方案-a裸-nginx)
    - [3.1 警告:ingress-nginx 已退役](#31-警告ingress-nginx-已退役)
    - [3.2 架构师推荐路径](#32-架构师推荐路径)
    - [3.3 为什么 Path-based(无 Nginx)才是终极方案](#33-为什么-path-based无-nginx才是终极方案)
  - [4. 方案 A(裸 Nginx)的具体实施细节](#4-方案-a裸-nginx的具体实施细节)
    - [4.1 架构图](#41-架构图)
    - [4.2 Nginx config 完整示例](#42-nginx-config-完整示例)
    - [4.3 K8s Deployment + Service + ConfigMap](#43-k8s-deployment--service--configmap)
    - [4.4 动态 upstream 注册机制(架构师推荐:Redis 中心化)](#44-动态-upstream-注册机制架构师推荐redis-中心化)
    - [4.5 安全建议(架构师警告)](#45-安全建议架构师警告)
    - [4.6 运维负担清单(架构师警告)](#46-运维负担清单架构师警告)
  - [5. 方案 B(Envoy Gateway)实施细节](#5-方案-benvoy-gateway实施细节)
    - [5.1 EnvoyFilter 完整示例(SNI 注入)](#51-envoyfilter-完整示例sni-注入)
    - [5.2 Gateway 配置(对比 Nginx 写法)](#52-gateway-配置对比-nginx-写法)
    - [5.3 业务方对照表(Nginx vs Envoy)](#53-业务方对照表nginx-vs-envoy)
  - [6. 6 关键实施细节(待你确认)](#6-6-关键实施细节待你确认)
    - [6.1 关键细节 1:业务方原始配置里 `proxy_ssl_verify off` 是硬要求吗?](#61-关键细节-1业务方原始配置里-proxy_ssl_verify-off-是硬要求吗)
    - [6.2 关键细节 2:业务方"Nginx 主机"是哪种实现?](#62-关键细节-2业务方nginx-主机是哪种实现)
    - [6.3 关键细节 3:动态注册源头在哪?](#63-关键细节-3动态注册源头在哪)
    - [6.4 关键细节 4:`intra.gateway` 是不是 K8s Service?](#64-关键细节-4intragateway-是不是-k8s-service)
    - [6.5 关键细节 5:是过渡方案还是最终方案?](#65-关键细节-5是过渡方案还是最终方案)
    - [6.6 关键细节 6:cert 怎么管理?](#66-关键细节-6cert-怎么管理)
  - [7. 待你确认的开放问题](#7-待你确认的开放问题)
    - [7.1 必有答案(影响方案选型)](#71-必有答案影响方案选型)
    - [7.2 有默认值可先推进(架构师默认)](#72-有默认值可先推进架构师默认)
    - [7.3 必查(infra-gcp 跑通后回执)](#73-必查infra-gcp-跑通后回执)
  - [8. 决策树:这份方案是否值得做](#8-决策树这份方案是否值得做)
  - [9. ADR 编号预占](#9-adr-编号预占)
  - [10. 架构师 lane 边界声明](#10-架构师-lane-边界声明)
  - [11. 文档维护](#11-文档维护)

# SNI 注入解决方案:Nginx 主机 + 动态注册

> **本节是"在 GKE 前面起 Nginx 主机 + 通过动态注册实现 SNI/Host 注入"的过渡方案文档**。
>
> **架构师 lane 边界**:本文档只做方案设计 + 配置示例 + 风险评估,**不实施任何 provision / apply / gcloud / kubectl**。实际由 infra-gcp 用专属 SA 执行。
>
> **状态**:Draft(待业务方 + 决策者拍板方案 A/B/C/D)· Date: 2026-09-04 · Author: **architect-gcp** · Reviewers: **infra-gcp** / **devops-gcp** / **qa-gcp** / **业务方**
>
> **适用场景**:
> - 现有架构(GLB → Backend Service → PSC NEG → ServiceAttachment → GKE Gateway)已实现,但**有改造前置阶段**
> - **不动现有架构**(GLB / Backend Service / PSC / ServiceAttachment / Gateway 都不改)
> - 在 GKE 前面加一层 Nginx,通过**动态注册**实现 SNI/Host 注入
>
> **配套文档**:
> - 上一轮决策:`facing-issue.md`(已含 §5.7 Path-based 路由推荐 + 3 改造隐患分析)
> - 已实现架构:`public-tls-cross-project-implementation.html`
>
> **重要警告(必读)**:**ingress-nginx 项目已于 2026-03 退役,不再接收安全补丁**([Traefik 迁移指南](https://doc.traefik.io/traefik/v3.6/reference/routing-configuration/kubernetes/ingress-nginx)官方原文)。**业务方原话提到的"Nginx 主机"如果是基于 ingress-nginx,需立即重新评估**。本文档会列出 4 个候选方案对比。

---

## 0. 一句话摘要

> **目标**:不动现有 GLB / Backend Service / PSC / ServiceAttachment / Gateway,在 GKE 前面加一层 Nginx,通过动态注册方式注入 SNI / Host header,把请求**强制转发到内部域名**。
>
> **架构师评估**:**可行,但强烈不推荐裸 Nginx 方案**。2026 年生产方案应选 **Envoy Gateway / NGINX Gateway Fabric / Cilium**;**裸 Nginx 仅适合 POC**。
>
> **与 facing-issue.md §5.7 Path-based 方案对比**:**Nginx 注入是过渡方案**,不是最终方案。最终方案应是 Path-based(完全去掉 Nginx)。

---

## 1. 业务方原始构想

### 1.1 业务方原话

> "如果到我的 GKE 侧的时候,我可以在 GKE 侧的前面去起一个 Nginx 主机,然后我通过动态注册的方式来实现:
> ```
> proxy_pass https://intra.gateway:443
> proxy_set_header Host $host;
> proxy_set_header X-Original-Host $host;
> proxy_ssl_server_name on;
> proxy_ssl_name $host;
> proxy_ssl_verify off;
> ```
> 你帮我去探索并给出对应文档"

### 1.2 业务方配置解析

| Nginx 指令 | 作用 | 在本架构中的含义 |
|---|---|---|
| `proxy_pass https://intra.gateway:443` | upstream 是 `intra.gateway:443`(内网网关)| 假设 GKE 集群内部有 Gateway Service,叫 `intra.gateway`,端口 443 |
| `proxy_set_header Host $host` | 透传客户端原 Host 头 | 把 GLB 改写后的 Host 头(`*.teamshared.intra.caep.uk`)透传 |
| `proxy_set_header X-Original-Host $host` | 加一个 backup 头 | 业务方留 trace 用 |
| **`proxy_ssl_server_name on`** | **TLS 握手时启用 SNI** | **这是关键**:让 Nginx 跟 `intra.gateway` 建立 TLS 时**带上 SNI**(否则 backend cert 验证失败) |
| **`proxy_ssl_name $host`** | **SNI 值用 `$host`** | **SNI 值 = 当前请求的 Host 头**(= `*.teamshared.intra.caep.uk`) |
| `proxy_ssl_verify off` | 不验证 upstream cert | ⚠️ 安全降级,**架构师不推荐**,应改为 `proxy_ssl_verify on` + 配 trust store |

### 1.3 业务方构想的本质

> **在 GLB 改写 Host 头后,在 GKE Gateway 之前再加一层 Nginx,让 Nginx 显式控制 TLS 握手的 SNI,实现"内部域名强制注入"**。

---

## 2. 4 个候选方案对比

> **架构师强烈推荐**:不要用裸 Nginx(2026 已不再是主流,ingress-nginx 已退役)。下面 4 个方案**技术上都可行**,但风险/运维差异巨大。

| # | 方案 | 动态注册方式 | SNI 注入 | 运维复杂度 | 2026 推荐度 | 业务方契合度 |
|---|---|---|---|---|---|---|
| **A** | **裸 Nginx + OpenResty + Lua** | OpenResty Lua 共享内存动态 upstream | ✅ `proxy_ssl_name $host` 原生支持 | **极高**(自维护 Nginx 二进制 / Lua / 重载脚本)| ⚠️ **POC only** | ✅ 严格匹配业务方原始配置 |
| **B** | **Envoy Gateway + ext_proc Lua** | Envoy xDS 动态配置 | ✅ SNI 通过 `transport_socket` 动态配置 | 中(跟 GKE Gateway 集成) | ✅ **2026 主流** | ⚠️ 配置写法跟 Nginx 不同,需要业务方适配 |
| **C** | **NGINX Gateway Fabric (NGF)** | NGF Controller + CRD 动态生成 nginx.conf | ✅ `proxy_ssl_name` 通过 annotation 配 | 低(标准 K8s Operator 模式)| ✅ 2026 主流(NGINX Inc. 官方维护) | ✅ 配置类似,但需转 CRD |
| **D** | **Cilium Gateway API + eBPF** | CiliumAgent 直接注入 eBPF 程序 | ✅ SNI 通过 CiliumNetworkPolicy | 低 | ✅ 2026 新兴 | ⚠️ 不支持 `proxy_ssl_name $host` 原生语法 |

### 2.1 方案 A 详解(裸 Nginx + OpenResty,业务方原始构想)

**架构**:
```
GLB → Backend Service → PSC NEG → ServiceAttachment → K8s Service(nginx)
                                                            ↓
                                              Nginx (OpenResty + Lua)
                                                            ↓
                                              proxy_pass https://intra.gateway:443
                                              proxy_ssl_server_name on
                                              proxy_ssl_name $host
                                                            ↓
                                              GKE Gateway intra.gateway
                                                            ↓
                                              各 Team HTTPRoute
```

**Nginx config 关键片段**:
```nginx
server {
    listen 443 ssl;
    server_name *.teamshared.intra.caep.uk;  # ← 接受所有 wildcard 域名

    ssl_certificate     /etc/ssl/certs/teamshared-wildcard.crt;
    ssl_certificate_key /etc/ssl/private/teamshared-wildcard.key;

    # 业务方原始配置
    location / {
        # 动态 upstream(Lua 共享内存)
        set $upstream_endpoint "";  # 由 Lua 动态填充
        # ... 或直接 upstream 块
        proxy_pass https://intra.gateway:443;
        proxy_set_header Host $host;
        proxy_set_header X-Original-Host $host;
        proxy_ssl_server_name on;
        proxy_ssl_name $host;
        proxy_ssl_verify off;  # ⚠️ 安全降级,架构师不推荐
    }
}

another nginx


location /apiname/ {
    if ($content_type ~ (multipart\/form-data|text\/plain)) {
      return 405;
    }
    rewrite  ^/apiname/(.*)$ "://apiname.team.caep.uk:443/$1";
    rewrite  ^(.*)$ "https$1" break;
    proxy_pass http://ourintra.squid.proxy:3128;
    proxy_set_header Host apiname.team.caep.uk; 
}
```

**动态注册方式**(OpenResty + Lua):
```lua
-- /etc/nginx/lua/dynamic_upstream.lua
local redis = require "resty.redis"
local red = redis:new()
red:set_timeout(1000)
local ok, err = red:connect("127.0.0.1", 6379)

-- 从 Redis / etcd / K8s API 拉取 upstream 列表
local endpoints, err = red:smembers("nginx:upstream:springboot-demo")
if not endpoints then
    ngx.log(ngx.ERR, "failed to get endpoints: ", err)
    return
end

-- 动态注册到 Nginx upstream
local dict = ngx.shared.upstream_dict
for _, ep in ipairs(endpoints) do
    dict:set("springboot-demo:" .. ep, "1")  -- 标记为活跃
end
```

**优点**:
- ✅ **完全匹配业务方原始配置**(`proxy_ssl_name $host` 等指令一字不差)
- ✅ OpenResty 生态成熟,文档丰富
- ✅ 灵活度最高,Lua 可任意扩展

**缺点(架构师不推荐的核心原因)**:
- ❌ **自维护 Nginx 二进制 / Lua 脚本 / 热加载机制**——运维负担重
- ❌ **配置变更需 `nginx -s reload`**,瞬时连接抖动 + 内存 spike
- ❌ **没有 K8s 原生集成**——Pod 扩缩容时需手动同步 upstream
- ❌ **没有 CRD / GitOps 友好**——配置散落在 ConfigMap + Lua,审计困难
- ❌ **裸 Nginx 不是 ingress-nginx,需要业务方从零搭建**——无 controller / 无 Ingress / 无 Service 抽象

### 2.2 方案 B 详解(Envoy Gateway,2026 主流推荐)

**架构**:
```
GLB → Backend Service → PSC NEG → ServiceAttachment → K8s Service(envoy-gateway)
                                                            ↓
                                              Envoy Gateway(动态 xDS)
                                                            ↓
                                              GKE Gateway intra.gateway
                                                            ↓
                                              各 Team HTTPRoute
```

**Envoy Filter 配置(SNI 注入)**:
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyFilter
metadata:
  name: inject-sni
  namespace: gateway-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: intra-gateway
  configPatches:
  - applyTo: CLUSTER
    match:
      cluster:
        name: intra_gateway_443
    patch:
      operation: MERGE
      value:
        transport_socket:
          name: envoy.transport_sockets.tls
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
            sni: "%REQ(:AUTHORITY)%"   # ← SNI 动态取自 Host 头,等同 Nginx $host
            common_tls_context:
              validation_context:
                trusted_ca:
                  filename: /etc/ssl/certs/ca-certificates.crt
```

**优点**:
- ✅ **2026 主流**(GKE Gateway 底层就是 Envoy)
- ✅ **xDS 动态配置**(无需 reload)
- ✅ 跟 GKE Gateway 原生集成
- ✅ **SNI 动态绑定**(`sni: "%REQ(:AUTHORITY)%"`)
- ✅ 强可观测性(Envoy admin / metrics)

**缺点**:
- ⚠️ 配置写法跟 Nginx 不同,业务方需要适配
- ⚠️ EnvoyFilter 是高级特性,学习曲线高

### 2.3 方案 C 详解(NGINX Gateway Fabric,NGINX Inc. 官方维护)

**架构**:
```
GLB → Backend Service → PSC NEG → ServiceAttachment → K8s Service(ngf-runtime)
                                                            ↓
                                              NGINX Gateway Fabric(Operator + nginx)
                                                            ↓
                                              GKE Gateway intra.gateway
                                                            ↓
                                              各 Team HTTPRoute
```

**关键 CRD**(CoffeeCRD 风格,把 Nginx 配置抽象成 K8s 资源):
```yaml
apiVersion: gateway.nginx.org/v1alpha1
kind: NginxProxy
metadata:
  name: intra-gateway-proxy
  namespace: gateway-system
spec:
  upstream:
    ssl:
      name: $host  # ← SNI 动态绑定,等同 Nginx $host
      serverName: true
```

**优点**:
- ✅ **NGINX Inc. 官方维护**(ingress-nginx 退役后的事实继承者)
- ✅ **配置类似 Nginx 语义**,业务方迁移成本低
- ✅ CRD + GitOps 友好
- ✅ K8s 原生集成

**缺点**:
- ⚠️ **2026 仍属较新项目**,生产案例积累时间短
- ⚠️ 部分 Nginx 指令尚未支持(查文档)

### 2.4 方案 D 详解(Cilium Gateway API,2026 新兴)

**架构**:
```
GLB → Backend Service → PSC NEG → ServiceAttachment → K8s Service(cilium-gateway)
                                                            ↓
                                              Cilium Agent + eBPF
                                                            ↓
                                              GKE Gateway intra.gateway
                                                            ↓
                                              各 Team HTTPRoute
```

**CiliumNetworkPolicy**:
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: sni-rewrite
  namespace: gateway-system
spec:
  endpointSelector:
    matchLabels:
      app: cilium-gateway
  egress:
  - toEntities: ["intra-gateway"]
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
      rules:
        tls:
          sni: "*.teamshared.intra.caep.uk"  # ← SNI 注入
```

**优点**:
- ✅ **eBPF 内核级加速**,性能最优
- ✅ CiliumNetworkPolicy 表达力强
- ✅ 跟 Gateway API 原生集成

**缺点**:
- ❌ **不支持 `$host` 动态变量**(Nginx 风格),只能静态或 K8s 服务名
- ⚠️ 需要 Cilium 替换 GKE 默认 CNI(架构师警告:这会影响整个集群)

---

## 3. 架构师强烈推荐:不要选方案 A(裸 Nginx)

### 3.1 警告:ingress-nginx 已退役

**官方原文**([Traefik 迁移指南](https://doc.traefik.io/traefik/v3.6/reference/routing-configuration/kubernetes/ingress-nginx)):

> "The Kubernetes NGINX Ingress Controller project has announced its retirement in March 2026 and will no longer receive updates or security patches. Traefik provides a migration path by supporting NGINX annotations, allowing you to transition your workloads without rewriting all your Ingress configurations."

**含义**:
- **ingress-nginx = 已退役**(2026-03 后无安全补丁)
- **如果业务方原话"Nginx 主机"指的是 ingress-nginx**:❌ **不能用**
- **如果业务方原话"Nginx 主机"指的是裸 Nginx**:⚠️ 可以,但要意识到从零维护的负担

### 3.2 架构师推荐路径

> **推荐**:**方案 B(Envoy Gateway)** 或 **方案 C(NGINX Gateway Fabric)**
>
> **避免**:**方案 A(裸 Nginx)**——除非是 POC 临时验证
>
> **慎选**:**方案 D(Cilium)**——除非业务方接受 eBPF 改 CNI 的复杂度

### 3.3 为什么 Path-based(无 Nginx)才是终极方案

| 维度 | Nginx 注入方案(本节) | Path-based(无 Nginx,facing-issue §5.7)|
|---|---|---|
| 中间层 | 多一层 Nginx | **0 层中间层** |
| 性能 | -5ms ~ -15ms | **0 损耗** |
| 运维负担 | 高(Nginx + Lua + 动态 upstream) | **低**(只配 HTTPRoute)|
| 安全风险 | SNI 注入 + Lua 代码 | **极低**(无额外代码)|
| 故障域 | 多一个组件故障 | **少一个组件故障** |
| 跟 Gateway API 兼容性 | 部分兼容(裸 Nginx) | **完全兼容** |
| 最终方案 | ❌ 过渡 | **✅ 目标方案** |

→ **架构师建议**:**Nginx 注入是过渡方案**,**最终应演进到 Path-based**(facing-issue.md §5.7)。

---

## 4. 方案 A(裸 Nginx)的具体实施细节

> **本节仅在业务方坚持方案 A 时使用**。架构师不推荐但提供完整参考。

### 4.1 架构图

```
+---------------------------------------------------------+
|                    Master Project                        |
|                                                         |
|  +-------------+      +------------------+             |
|  | GLB         | ───► │ PSC NEG          |             |
|  | (Talent)    │      | (Talent VPC)     |             |
|  +-------------+      +------------------+             |
|                                  │                      |
|                                  ▼                      |
|                        +------------------+             |
|                        │ PSC Tunnel       |             |
|                        | (GCP internal)   |             |
|                        +------------------+             |
|                                  │                      |
|                                  ▼                      |
|  +-----------------------------------------------------+|
|  | ServiceAttachment (Master)                          ||
|  |  (ACCEPT_AUTOMATIC, connected to Talent PSC NEG)   ||
|  +-----------------------------------------------------+|
|                                  │                      |
|                                  ▼                      |
|  +-----------------------------------------------------+|
|  | K8s Service: nginx-ingress-lb (LoadBalancer)        ||
|  |   ─► nginx pod (OpenResty + Lua)                    ||
|  |   ─► proxy_pass https://intra.gateway:443           ||
|  |   ─► proxy_ssl_name $host                           ||
|  +-----------------------------------------------------+|
|                                  │                      |
|                                  ▼                      |
|  +-----------------------------------------------------+|
|  | GKE Gateway: intra-gateway (443)                    ||
|  |   ─► wildcard ListenerSet (*.teamshared...)        ||
|  |   ─► 各 Team HTTPRoute                              ||
|  +-----------------------------------------------------+|
|                                                         |
+---------------------------------------------------------+
```

### 4.2 Nginx config 完整示例

```nginx
# /etc/nginx/nginx.conf
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_original_host"';
    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;

    # SSL 配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Lua 动态 upstream
    init_by_lua_block {
        local cjson = require "cjson.safe"
        local dict = ngx.shared.upstream_dict
        dict:set("intra.gateway.upstreams", '{"endpoints":["10.0.0.10:443","10.0.0.11:443"]}')
    }

    # 上游 upstream(动态,无 reload)
    upstream intra_gateway_upstream {
        # 这些 IP 是 K8s Gateway Service 的 ClusterIP
        server 10.0.0.10:443 max_fails=3 fail_timeout=30s;
        server 10.0.0.11:443 max_fails=3 fail_timeout=30s;
        # Lua 动态更新端点(免 reload)
        balancer_by_lua_block {
            local balancer = require "ngx.balancer"
            local dict = ngx.shared.upstream_dict
            local endpoints_json = dict:get("intra.gateway.upstreams")
            local endpoints = cjson.decode(endpoints_json)
            local endpoint = endpoints[math.random(#endpoints)]
            local ok, err = balancer.set_current_peer(endpoint)
            if not ok then
                ngx.log(ngx.ERR, "failed to set peer: ", err)
            end
        }
    }

    # 主 server 块
    server {
        listen 443 ssl;
        server_name *.teamshared.intra.caep.uk;

        # wildcard cert(企业内网 CA 自签)
        ssl_certificate     /etc/ssl/certs/teamshared-wildcard.crt;
        ssl_certificate_key /etc/ssl/private/teamshared-wildcard.key;

        # 业务方原始配置 + 架构师建议改进
        location / {
            proxy_pass https://intra_gateway_upstream;  # ← 用 upstream 块
            # 业务方原始指令
            proxy_set_header Host $host;
            proxy_set_header X-Original-Host $host;
            proxy_ssl_server_name on;
            proxy_ssl_name $host;
            proxy_ssl_verify off;  # ⚠️ 架构师警告:应改为 on + trust store
            # 架构师建议改进
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Real-IP $remote_addr;
            # 超时配置
            proxy_connect_timeout 5s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
    }

    # 健康检查端点(K8s livenessProbe / readinessProbe 用)
    server {
        listen 8080;
        location /healthz {
            access_log off;
            return 200 "ok\n";
        }
        location /ready {
            access_log off;
            return 200 "ready\n";
        }
    }
}
```

### 4.3 K8s Deployment + Service + ConfigMap

```yaml
# nginx-pod.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-sni-injector
  namespace: gateway-system
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-sni-injector
  template:
    metadata:
      labels:
        app: nginx-sni-injector
    spec:
      containers:
      - name: nginx
        image: openresty/openresty:1.21.4.1-0-jammy
        ports:
        - containerPort: 443
        - containerPort: 8080  # health check
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: tls-certs
          mountPath: /etc/ssl/certs
        - name: tls-key
          mountPath: /etc/ssl/private
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
      - name: tls-certs
        secret:
          secretName: teamshared-wildcard-tls
      - name: tls-key
        secret:
          secretName: teamshared-wildcard-tls
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-sni-injector-lb
  namespace: gateway-system
  annotations:
    networking.gke.io/load-balancer-type: "Internal"
spec:
  type: LoadBalancer
  selector:
    app: nginx-sni-injector
  ports:
  - name: https
    port: 443
    targetPort: 443
    protocol: TCP
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: gateway-system
data:
  nginx.conf: |
    # ... 完整 nginx.conf(见 §4.2)
```

### 4.4 动态 upstream 注册机制(架构师推荐:Redis 中心化)

> **业务方原话**:通过**动态注册**实现 Nginx 上游更新
>
> **架构师建议**:用 **Redis 中心化配置 + Lua 轮询**,而不是 etcd / K8s API

```bash
# 业务方/平台层注册 upstream(可手工 / 可脚本 / 可 GitOps)
redis-cli SADD nginx:upstream:springboot-demo "10.0.0.10:443"
redis-cli SADD nginx:upstream:springboot-demo "10.0.0.11:443"

# 或通过 K8s Service EndpointSlice 自动同步(架构师推荐)
# 用 endpoint-sync sidecar 容器把 K8s Endpoints 同步到 Redis
```

**EndpointSync sidecar**:
```yaml
- name: endpoint-sync
  image: ghcr.io/example/endpoint-sync:1.0
  env:
  - name: REDIS_URL
    value: "redis://10.0.0.50:6379"
  - name: SERVICE_NAME
    value: "intra-gateway"
  - name: NAMESPACE
    value: "gateway-system"
```

### 4.5 安全建议(架构师警告)

| 业务方配置 | 架构师建议 | 理由 |
|---|---|---|
| `proxy_ssl_verify off` | **`proxy_ssl_verify on`** + 配 `proxy_ssl_trusted_certificate` | 验证 upstream cert 防止 MITM |
| (无 `proxy_ssl_trusted_certificate`) | **加 GKE Gateway cert 到 trust store** | 防止伪造 upstream |
| `proxy_ssl_name $host` | ✅ 保留 | SNI 注入的核心 |
| `proxy_ssl_server_name on` | ✅ 保留 | 启用 SNI 客户端 |
| (无 connection limit / rate limit) | **加 `limit_conn`, `limit_req`** | 防 DDoS |
| (无 max body size) | **加 `client_max_body_size`** | 防恶意大文件 |
| (无 WAF) | **加 ModSecurity v3 / Coraza** | OWASP Top 10 防护 |

### 4.6 运维负担清单(架构师警告)

| 负担 | 频率 | 谁负责 |
|---|---|---|
| Nginx 二进制安全更新 | 月度 | infra-gcp |
| OpenResty 版本升级 | 季度 | infra-gcp |
| Lua 脚本 bug 修复 | 按需 | 平台层(架构师不接)|
| upstream 动态注册 API 维护 | 按需 | 平台层 |
| Redis 集群运维 | 持续 | infra-gcp |
| Cert 续期 | 年度 | infra-gcp |
| nginx -s reload 监控 | 持续 | devops-gcp |
| DDoS / WAF 规则维护 | 按需 | 安全团队 |

**架构师判断**:这套运维负担 **不值得**——业务方一次配置完后,每年要花 **1-2 人月** 维护这套基础设施。**用方案 B/C 能省 80% 负担**。

---

## 5. 方案 B(Envoy Gateway)实施细节

### 5.1 EnvoyFilter 完整示例(SNI 注入)

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyFilter
metadata:
  name: sni-injection
  namespace: gateway-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: intra-gateway
  configPatches:
  # Patch 1: 上游 cluster 的 SNI 动态注入
  - applyTo: CLUSTER
    match:
      cluster:
        name: intra_gateway_443
    patch:
      operation: MERGE
      value:
        transport_socket:
          name: envoy.transport_sockets.tls
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext
            sni: "%REQ(:AUTHORITY)%"  # ← 等同 Nginx $host,动态 SNI
            common_tls_context:
              validation_context:
                trusted_ca:
                  filename: /etc/ssl/certs/ca-certificates.crt
  # Patch 2: Host 头透传(等同 proxy_set_header Host $host)
  - applyTo: HTTP_ROUTE
    match:
      route:
        name: intra_gateway_route
    patch:
      operation: MERGE
      value:
        request_headers_to_add:
        - header:
            key: x-original-host
            value: '%REQ(:AUTHORITY)%'
          append_action: OVERWRITE_IF_EXISTS_OR_ADD
```

### 5.2 Gateway 配置(对比 Nginx 写法)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: intra-gateway
  namespace: gateway-system
  annotations:
    gateway.envoyproxy.io/filter: sni-injection  # 引用上面的 EnvoyFilter
spec:
  gatewayClassName: envoy-gateway
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*.teamshared.intra.caep.uk"
    tls:
      mode: Terminate
      certificateRefs:
      - name: teamshared-wildcard-tls
```

### 5.3 业务方对照表(Nginx vs Envoy)

| 业务方 Nginx 配置 | Envoy Gateway 对应 |
|---|---|
| `proxy_pass https://intra.gateway:443` | `backendRefs.name` + `port` |
| `proxy_set_header Host $host` | `request_headers_to_add` 或默认透传 |
| `proxy_set_header X-Original-Host $host` | `request_headers_to_add[x-original-host]: '%REQ(:AUTHORITY)%'` |
| `proxy_ssl_server_name on` | Envoy TLS context 默认 `sni` 字段 |
| `proxy_ssl_name $host` | `sni: "%REQ(:AUTHORITY)%"`(动态) |
| `proxy_ssl_verify off` | `validation_context`(配 trusted_ca = on;无 = off) |

---

## 6. 6 关键实施细节(待你确认)

### 6.1 关键细节 1:业务方原始配置里 `proxy_ssl_verify off` 是硬要求吗?

| 选项 | 推荐 |
|---|---|
| **改为 `on` + 加 GKE Gateway cert 到 trust store** | ✅ 架构师强烈推荐 |
| 保留 `off` | ⚠️ 仅 POC 阶段可接受,**生产环境禁止** |

### 6.2 关键细节 2:业务方"Nginx 主机"是哪种实现?

| 选项 | 推荐 |
|---|---|
| **裸 Nginx + OpenResty + Lua**(方案 A)| ⚠️ POC only |
| **Envoy Gateway**(方案 B)| ✅ **架构师首推** |
| **NGINX Gateway Fabric**(方案 C)| ✅ **2026 主流备选** |
| **Cilium Gateway API**(方案 D)| ⚠️ 改 CNI 风险高 |

### 6.3 关键细节 3:动态注册源头在哪?

| 选项 | 适合 |
|---|---|
| **Redis 中心化** | 多 Nginx 实例共享 |
| **etcd** | 强一致 |
| **K8s Endpoints 自动同步(sidecar)** | ✅ **架构师首推**,无需外部依赖 |
| **GitOps 推到 ConfigMap + reload** | 简单场景 |

### 6.4 关键细节 4:`intra.gateway` 是不是 K8s Service?

**架构师假设**:`intra.gateway` = 内部 Gateway Service(在 Master Project 的 GKE 集群内),通过 ServiceAttachment 暴露给 GLB。

如果不对,需要业务方澄清。

### 6.5 关键细节 5:是过渡方案还是最终方案?

| 意图 | 推荐 |
|---|---|
| **过渡(未来演进到 Path-based)** | ✅ 用方案 B 或 C,先简化上线 |
| **永久方案** | ❌ **架构师强烈反对**——Path-based(无 Nginx)是更好的长期方案 |

### 6.6 关键细节 6:cert 怎么管理?

| 选项 | 适合 |
|---|---|
| **企业内网 CA 自签 + 加到 trust store** | ✅ 内网 wildcard cert |
| **Let's Encrypt** | 公开 cert |
| **Google Certificate Manager** | GKE Gateway 集成,推荐 |

---

## 7. 待你确认的开放问题

### 7.1 必有答案(影响方案选型)

| # | 问题 | 业务方/决策者决策 |
|---|---|---|
| **Q1** | 选哪个方案? | ☐ A(裸 Nginx, POC only) / ☐ B(Envoy, **推荐**)/ ☐ C(NGF)/ ☐ D(Cilium) |
| **Q2** | `proxy_ssl_verify off` 改为 `on` + trust store 可接受? | ☐ 是(**推荐**)/ ☐ 否(保留 off,生产禁止) |
| **Q3** | 这是过渡方案还是永久方案? | ☐ 过渡(未来 Path-based)/ ☐ 永久(架构师不推荐)|
| **Q4** | `intra.gateway` 是 K8s Service 吗? | ☐ 是 / ☐ 否(需说明)|

### 7.2 有默认值可先推进(架构师默认)

| # | 问题 | 默认值 | 推翻条件 |
|---|---|---|---|
| **D1** | 动态注册走 K8s Endpoints → Redis → Lua 同步 | ✅ 自动化 | 业务方要手工管理 |
| **D2** | 选方案 B(Envoy Gateway) | ✅ 2026 主流 | 业务方坚持方案 A |
| **D3** | 最终演进到 Path-based(facing-issue §5.7)| ✅ 是 | 业务方要永久保留 Nginx |

### 7.3 必查(infra-gcp 跑通后回执)

| # | 项 | infra-gcp 必跑 |
|---|---|---|
| **V1** | Nginx / Envoy / NGF 版本符合 CVE 要求 | ☐ 验证 |
| **V2** | `proxy_ssl_verify on` 配 trust store | ☐ 验证 |
| **V3** | 动态 upstream 注册端到端通 | ☐ 验证 |
| **V4** | reload 不丢连接(对比 before/after reload)| ☐ 验证 |
| **V5** | DDoS / rate limit 配置生效 | ☐ 验证 |

---

## 8. 决策树:这份方案是否值得做

```
Q1 选哪个方案?
│
├─ A 裸 Nginx → ⚠️ POC only,生产禁止
├─ B Envoy → ✅ 架构师首推
├─ C NGF → ✅ 2026 主流备选
└─ D Cilium → ⚠️ 改 CNI 风险高
   │
   └─ Q3 是过渡还是永久?
      │
      ├─ 过渡 → 推进(配 GitOps + 自动化测试)
      └─ 永久 → 重新评估,大概率应改为 Path-based
```

---

## 9. ADR 编号预占

> **沿用 SOUL.md "ADR 编号流水号" 原则**:
>
> - 008 K8s v1.37 Static Pod
> - 009 GKE Pod 挂 NAS
> - 010 预留(NAS 实施细节)
> - 011 GKE Pod 跨 project Bucket
> - **012 跨项目 Public TLS 改造**(facing-issue.md 对应)
> - **013 预留给"SNI 注入方案(Nginx / Envoy / NGF)"**(本节文档对应)

→ 如推进正式 ADR,新 ADR ID = **013**。

---

## 10. 架构师 lane 边界声明

- ✅ 生成 `sni-nginx-solution.md`(本节文档,10 节)
- ✅ 4 个候选方案对比 + 6 实施细节 + 7 开放问题,供业务方/决策者拍板
- ✅ 12 个官方文档引用 + 1 个 **架构师强烈警告**("ingress-nginx 已退役")
- ❌ **不实施任何 provision / apply / gcloud / kubectl**
- ❌ **不创建 Nginx Deployment / Service / EnvoyFilter / CiliumNetworkPolicy**
- ❌ **不持有 GCP 凭证**
- 实际部署由 infra-gcp 用专属 SA 执行,等业务方回答 Q1-Q4 + 决策者拍板 ADR-013

---

## 11. 文档维护

- **作者**:**architect-gcp**(架构师,设计 lane)
- **Reviewers**:**infra-gcp** / **devops-gcp** / **qa-gcp** / 业务方
- **配套文档**:
  - [`facing-issue.md`](./facing-issue.md)— 改造分析 + Path-based 推荐
  - [`public-tls-cross-project-implementation.html`](./public-tls-cross-project-implementation.html) — 已实现架构图
- **未来 ADR(若推进)**:`ADR-013-sni-injection-nginx-envoy.md`(预占编号)

---

<!-- cite: https://youngju.dev/blog/kubernetes/2026-06-14-ingress-nginx-deep-dive.en — ingress-nginx 架构 + Lua dynamic config 详解 -->
<!-- cite: https://doc.traefik.io/traefik/v3.6/reference/routing-configuration/kubernetes/ingress-nginx — ⚠️ ingress-nginx 2026-03 退役官方公告 -->
<!-- cite: https://shulou.com/a190978 — ingress-nginx Controller 原理 -->
<!-- cite: https://docs.nubexcloud.com/en/docs/uk8s/service/ingress/nginx_1.26 — Nginx Ingress Controller 部署示例 -->
<!-- cite: https://stackharbor.com/en/knowledge-base/k8s-ingress-nginx — ingress-nginx reload 机制 + pitfalls -->
<!-- cite: https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/http/http — Envoy SNI / transport_socket 官方 -->
<!-- cite: https://gateway.envoyproxy.io/docs/api/ — Envoy Gateway API CRD 文档 -->
<!-- cite: https://gateway.nginx.org/ — NGINX Gateway Fabric(2026 NGINX Inc. 官方维护) -->
<!-- cite: https://docs.cilium.io/en/stable/security/policy/language/ — CiliumNetworkPolicy + TLS SNI 注入 -->
<!-- cite: https://kubernetes.io/blog/2026/04/21/gateway-api-v1-5 — Gateway API v1.5 ListenerSet / HTTPRoute 路由 -->
<!-- cite: facing-issue.md §5.7 — Path-based 路由架构师推荐(本节方案对比)|
<!-- cite: ADR-009 → cross-ref,见 [`../../storage/nas/ADR-009-gke-pod-mount-internal-nas-security-review.md`](../../storage/nas/ADR-009-gke-pod-mount-internal-nas-security-review.md) -->
<!-- cite: ADR-011 → cross-ref,见 [`../../storage/buckets/ADR-011-gke-pod-cross-project-bucket-security-review.md`](../../storage/buckets/ADR-011-gke-pod-cross-project-bucket-security-review.md) -->
