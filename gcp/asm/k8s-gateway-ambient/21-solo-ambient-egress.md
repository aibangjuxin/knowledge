# Ambient 模式下 GKE Pod Egress 实现 — Internal + Public(含 Namespace-level 公共出网白名单)

> **TL;DR**:
> - Ambient mesh 下,ztunnel **默认捕获所有出站流量并 passthrough(allow-all)**,无任何出网策略控制 — 与 sidecar 的 `outboundTrafficPolicy: REGISTRY_ONLY` **不生效**(ztunnel 不读该字段)
> - 你现有的两套 egress 模型在 Ambient 下**有不同的演进路径**:**Internal Egress(NHF)** 通过 GCP 路由 + 双 NIC MIG,与 ztunnel 完全解耦,**几乎零改造**;**Public Egress(Squid allowlist)** 必须从 Pod→Nginx→Squid 链路迁到 **`ServiceEntry + istio.io/use-waypoint`** + egress waypoint
> - **Namespace-level 公共出网白名单**这一核心诉求 = **`AuthorizationPolicy` 绑 waypoint egress**,按 `namespaces` / `principals` 决定谁能调哪个外部 host,**白名单收敛到 ServiceEntry 一层**(每加一个域名 1 条 ServiceEntry)
> - 公共出网推荐 **L7 waypoint egress**(Istio 1.24.3+,社区 GA,无需 Enterprise license);L4 ztunnel-native / L7 agentgateway 是 Solo Enterprise **alpha** 特性,**本场景不用**
> - 这篇是**架构探索 + 落地配方**混合文档,从“为什么 Ambient 下 egress 默认不安全”讲到“如何用最少的 ServiceEntry + AuthorizationPolicy 拿到 Namespace 粒度的公共出网治理”

---

## 0. 文档定位

> **起点问题**(承接 `20-solo-ambient-kong.md`):
> 现有架构:**Istio Ingress Gateway ➔ KongDP ➔ Ambient Runtime**(Ingress 方向已闭环)。
> 但 Ambient 模式下 **egress(出网)** 方向在前面 01-20 篇**完全没有覆盖**。
> 而 Lex 团队的真实诉求是:
> 1. **Internal Egress**(走 NHF 去公司办公网 / on-prem) — 现状是 deny 一切 + GCP 路由表 fallback
> 2. **Public Egress**(公共 Internet) — 现状是 deny all + 显式 allow 域名,通过 Pod→Nginx→Squid 链路
> 3. **Namespace-level 公共出网白名单** — 哪个 team / 哪个 ns 能出网到哪些域名?

> **来源引用**(全部直接基于官方原文):
> - [Solo.io Istio 1.30.x Ambient Egress Overview](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/overview.md) — 3 种 egress 方案对比
> - [Solo.io Istio 1.30.x Ambient Egress L7 waypoint](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/egress.md) — 社区 L7 waypoint 落地步骤
> - [ambientmesh.io — Controlling mesh egress](https://ambientmesh.io/docs/traffic/mesh-egress) — 社区文档总览 + ztunnel egress policies(Solo Enterprise)
> - [Solo.io — Migrate egress controls from sidecar to ambient](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/migrate-sidecar.md) — 行为差异(`outboundTrafficPolicy: REGISTRY_ONLY` / `exportTo` / VirtualService 改造)
> - [ambientmesh.io — Authorization policies with ztunnel](https://ambientmesh.io/docs/security/ztunnel-authz) — ztunnel L4 AuthZ + 默认 DENY
> - [ambientmesh.io — Authorization policy with waypoint proxies](https://ambientmesh.io/docs/security/waypoint-authz) — waypoint L7 AuthZ
> - [ambientmesh.io — NetworkPolicy considerations](https://ambientmesh.io/docs/security/configure-networkpolicies) — 必须放行 15008 / kubelet 169.254.7.127
> - 同目录 `06-policy-capabilities.md` §5.4 — SNI 限制 egress 写法(本篇引用 + 扩展)
> - 同目录 `09-ztunnel-redirection-app-compat.md` §0.4 — DNS capture + 解析行为
> - 同目录 `04-runtime-migration.md` — Runtime 迁 ambient 的硬约束
> - 旧参考 `/Users/lex/git/gcp/linux/networking/nhf.md` — Internal egress 现状
> - 旧参考 `/Users/lex/git/knowledge/safe/docs/saasp-pod-nginx-squid.md` — Public egress 现状

---

## 1. 为什么 Ambient 模式下 Egress 默认是“不安全”的

### 1.1 Ambient 默认行为 — ztunnel passthrough

> 严格原话(Istio 1.30 Ambient):
> "**In an ambient mesh, ztunnel captures outbound traffic from every pod on the node.** For traffic destined for external services, you configure an egress gateway that ztunnel routes matched traffic through before releasing connections from the cluster."
> — [Solo.io Istio 1.30.x Ambient Egress Overview](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/overview.md)

**含义**:
- ztunnel 在**节点级**拦截所有出站流量,目的是把集群内流量走 HBONE 加密
- 但**对外部目的地**,ztunnel 默认 **passthrough**(直接放出去到原始目的 IP)
- **没有任何默认的 deny 或白名单控制**
- 任何 ambient ns 的 pod,只要节点网络可达(经过 GKE VPC 路由表),就可以直接出公网

### 1.2 `outboundTrafficPolicy: REGISTRY_ONLY` 在 ambient **不生效**

> 严格原话:
> "**In sidecar mode, setting `outboundTrafficPolicy: REGISTRY_ONLY` in `MeshConfig` blocks traffic from sidecar proxies to any external destination not registered in the service registry. In an ambient mesh, ztunnel does not read `outboundTrafficPolicy`. Traffic to unregistered destinations passes through by default.**"
> — [Solo.io — Migrate egress controls from sidecar to ambient](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/migrate-sidecar.md) §"Behavioral differences"

**对 Lex 团队的含义**:
- 旧 sidecar 模式下,你们如果配过 `outboundTrafficPolicy: REGISTRY_ONLY`,那 Pod **默认**调不到任何未在 K8s Service + ServiceEntry 注册的目的地
- Ambient 切完**这条保护就消失了**,pod 可以直连任意 IP
- **如果你认为“封了 sidecar 入口 = 业务就出不去网”是默认安全假设,这个假设在 ambient 下需要被重新打补丁**

### 1.3 `exportTo` 不支持

> 严格原话:
> "In ambient mode, `exportTo` is ignored. All ServiceEntry resources are globally visible regardless of the `exportTo` field. Namespace-scoped access control must be expressed through AuthorizationPolicy resources that target the ServiceEntry or the egress gateway."
> — [Solo.io — Migrate egress controls from sidecar to ambient](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/migrate-sidecar.md) §"Behavioral differences"

**含义**: 你之前如果用 `exportTo: ["."]` 让 ServiceEntry 只在某个 ns 可见,这在 ambient 下**完全无效**,必须改用 `AuthorizationPolicy` 控制谁能调它。

### 1.4 与 Lex 现有安全模型的对比

| 维度 | 旧(sidecar + 现有 egress) | 新(ambient) |
|---|---|---|
| **集群内东西向加密** | Sidecar envoy mTLS | ztunnel HBONE mTLS ✅(自动) |
| **集群外(public)默认行为** | REGISTRY_ONLY:pod 只能调已注册服务 | **passthrough**:pod 可调任意外部 IP ⚠️ |
| **NHF(Internal Egress)** | GCP 路由表 128/2 → NHF ILB → 办公网 | **不变**(GCP 路由与 Istio 解耦)|
| **Public 域名 allowlist** | Pod→Nginx→Squid + CA trust | **必须迁**到 ServiceEntry + AuthorizationPolicy |
| **Namespace 粒度公共出网** | NetworkPolicy 限 source IP + Pod→Nginx IP allowlist | **直接用 `AuthorizationPolicy` + `namespaces` selector** |

---

## 2. 三种 Ambient Egress 方案 — 选型决策

> 来源:[Solo.io 1.30.x Ambient Egress Overview](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/overview.md)

|| 方案 | GatewayClass | 数据面 | License 要求 | 适用场景 | 本场景适用度 |
|---|---|---|---|---|---|---|
| **L4 ztunnel-native** | `solo-ztunnel-egress` | **无新 pod**,复用 ztunnel DaemonSet | **Solo Enterprise license** | TCP/TLS 外部连接,只需 source identity 校验,**不支持 HTTP 路径/header 策略** | ❌ Alpha + 需要 Enterprise + 不能配 HTTP 策略 → **不用** |
| **L7 waypoint** ⭐⭐⭐ | `istio-waypoint` | **新增 Envoy waypoint pod** | **社区版(无 license)** | HTTP 路径/header/method 策略、**TLS origination**、**rate limiting** | ✅ **本场景推荐** |
| **L7 agentgateway waypoint** | `enterprise-agentgateway-waypoint` | 新增 agentgateway pod | **Solo Enterprise + agentgateway license** | CEL 表达式做 source identity + HTTP attribute 联合判定 | ❌ 需要双重 license → **不用** |

**本场景推荐:L7 waypoint egress**(理由):
1. **不需要 Enterprise license**(Lex 团队用的是 Solo Standard 分发镜像,无 Enterprise)
2. **支持 namespace-level 公共出网白名单**(对应 Lex 核心诉求)
3. **支持 HTTP 路径/header 限制**(e.g. 只允许 GET、限制 user-agent、对响应头做脱敏)
4. **支持 TLS origination**(waypoint 把 Pod 的明文 HTTP 升级成 HTTPS 出网,对外**身份干净**)
5. **Istio 1.24.3+** 社区版 GA,不是 alpha

### 2.1 严格定义 vs 简化解释

|| 概念 | 简化解释 | 严格定义 |
|---|---|---|---|
| **L7 waypoint egress** | "加一个 waypoint 做出口网关" | "A waypoint proxy deployed with `gatewayClassName: istio-waypoint` acts as the egress gateway; ServiceEntries labeled `istio.io/use-waypoint: <name>` route matched traffic through this waypoint before exiting the cluster." — Solo.io 1.30.x egress overview §"L7 waypoint egress" |
| **`istio.io/use-waypoint` label** | "绑 waypoint" | "Used on a ServiceEntry to bind it to a specific waypoint; ztunnel intercepts matching outbound connections and forwards them through the waypoint via HBONE." — Solo.io 1.30.x egress docs §"Step 2" |
| **`PILOT_ENABLE_IP_AUTOALLOCATE=true`** | "ambient egress 必须开" | "Required for ServiceEntry resources to receive stable virtual IPs (240.240.x.x range); without it, DNS capture cannot route external traffic to the waypoint." — Solo.io 1.30.x egress §"Before you begin" |
| **DNS capture** | "DNS 走 ztunnel" | "istio-cni redirects DNS queries from pods to ztunnel for resolution; with autoallocation enabled, external hosts get a stable 240.240.x.x IP that maps to a ServiceEntry." — Solo.io 1.30.x egress §"Before you begin" + `09-ztunnel-redirection-app-compat.md` §0.4 |

---

## 3. Internal Egress(NHF)在 Ambient 下的演进 — **几乎零改造**

### 3.1 NHF 的本质与 Istio Ambient 完全解耦

> 核心观察:`/Users/lex/git/gcp/linux/networking/nhf.md` 实现的 NHF(Next-Hop Forwarder)机制,本质是:
> 1. **GCP VPC 路由表**:`128.0.0.0/2` + `10.0.0.0/8` 的 next-hop = NHF ILB Forwarding Rule
> 2. **NHF MIG**(GCE)做 iptables SNAT + 双 NIC
> 3. **防火墙 tag**:client source tag → NHF ingress tag → NHF egress tag

**这套机制在 L3 网络层,与 Istio 模式无关**:
- sidecar 模式下 Pod 出网走节点 → NHF ILB
- ambient 模式下 Pod 出网走 ztunnel → 节点 → NHF ILB(ztunnel 内部解开 HBONE 后,裸 TCP 出节点)

**结论**:**NHF 在 Ambient 下完全不变,自动继续工作**。

### 3.2 Ambient 下的 Internal Egress 数据流

```text
┌─────────────────────┐
│ Ambient Runtime Pod │ (sidecar 已卸载,明文 HTTP 出站)
│  app:port 80        │
└──────────┬──────────┘
           │ ① 应用明文 HTTP 出站
           ▼
┌─────────────────────┐
│ pod netns:iptables  │ REDIRECT → 15001 (Outbound)
│   (ztunnel 注入)     │
└──────────┬──────────┘
           │ ② ztunnel 拦截出站 → HBONE 隧道
           ▼
┌─────────────────────┐
│ 本节点 ztunnel pod  │ 解 HBONE → 还原原始 IP 包 → 出节点
│   (DaemonSet)       │
└──────────┬──────────┘
           │ ③ 出节点,标准 IP 包(src=Pod IP, dst=on-prem)
           ▼
┌─────────────────────┐
│ GKE Node            │
│   192.168.x.x       │
└──────────┬──────────┘
           │ ④ 节点查 GCP 路由表
           │    命中 128.0.0.0/2 → NHF ILB FR (192.168.0.55)
           ▼
┌─────────────────────┐
│ NHF ILB FR          │
│ (192.168.0.55)      │
└──────────┬──────────┘
           │ ⑤ ILB 分发到 NHF MIG 健康实例
           ▼
┌─────────────────────┐
│ NHF 实例(ens5+ens4)│ iptables SNAT:Pod IP → Shared VPC IP
└──────────┬──────────┘
           │ ⑥ src=Shared VPC IP, dst=on-prem
           ▼
   on-prem DRN / SCC
   (公司办公网出口统一管控)
```

**关键差异 vs sidecar 模式**:**第 ① → ② 步多了一次 ztunnel HBONE 封装/解封装**,但**对外可见的 IP 包(src/dst)完全一样**——GCP 路由表依然看到 `Pod IP → on-prem IP`,NHF 完全感知不到 Istio 模式的变化。

### 3.3 NHF 现状配置**不需要改任何东西**

| 资源 | sidecar 模式 | ambient 模式 | 是否改 |
|---|---|---|---|
| NHF MIG 实例配置 | iptables + 双 NIC | 同 | ❌ 不变 |
| NHF ILB Forwarding Rule | `192.168.0.55` | 同 | ❌ 不变 |
| GCP VPC 路由 `128.0.0.0/2 → NHF ILB` | priority=1000 | 同 | ❌ 不变 |
| 防火墙 tag(client / NHF ingress / NHF egress) | 已有 | 同 | ❌ 不变 |
| `100.64.0.0/10` Pod CIDR 静态路由 | NHF 实例上加 | 同 | ❌ 不变 |

**唯一的可观察变化**:ztunnel 流量日志会显示 ambient Pod → on-prem IP 的出站访问记录(`src.workload=<pod-name>, src.namespace=<ns>, dst.addr=<on-prem>`)。这是**可观测性增强**,不是改造点。

### 3.4 NHF vs Ambient 加密的关系

**反直觉点**:**NHF 看不到任何 Istio 协议层信息**。对 NHF 来说,Pod 出来就是普通的 IP 包:
- sidecar 模式:`Pod IP → on-prem IP`(原 IP 包,可能从 sidecar envoy 出来)
- ambient 模式:`Pod IP → on-prem IP`(从 ztunnel 出来后,HBONE 已被解包)

**NHF 的 SNAT + 双 NIC 与 ztunnel 的 HBONE 是两个完全独立的层**:
- HBONE 只保护 pod-to-pod(GKE 节点之间)
- NHF SNAT 解决跨 VPC / on-prem 回程路由
- 两者**串行工作,不冲突**

---

## 4. Public Egress(Squid allowlist)在 Ambient 下的迁移

### 4.1 旧链路:Pod → Nginx → Squid → 目标

> 来源:`/Users/lex/git/knowledge/safe/docs/saasp-pod-nginx-squid.md`
>
> 链路:
> ```text
> GKE Pod (Java应用) → Nginx (first hop) → Squid (HTTP 代理) → www.abc.com
> ```
>
> 控制机制:
> 1. **Default Deny**: 集群默认 deny all 出网,只有显式 allow 的 IP/域名能出
> 2. **Squid allowlist**: Squid 配置 ACL,按域名放行/拒绝
> 3. **CA trust 分散**:Nginx 信任 www.abc.com 的 CA,Java 应用 trust Nginx cert
> 4. **责任分工**:Nginx 真正建立 HTTPS 连接,Squid 透明转发,Java 几乎不感知

### 4.2 新链路:Pod → ztunnel → Egress Waypoint → 目标

```text
┌─────────────────────┐
│ Ambient Runtime Pod │ 应用发请求 http://api.saas1.com/data
│ app:80              │ (明文 HTTP / 或 HTTPS,均可)
└──────────┬──────────┘
           │ ① 应用出站,getaddrinfo() 解析 api.saas1.com
           ▼
┌─────────────────────┐
│ pod netns:DNS       │ UDP:53 → 15053 (ztunnel DNS proxy)
│ iptables            │
└──────────┬──────────┘
           │ ② ztunnel DNS proxy:解析 api.saas1.com
           │    命中 ServiceEntry 240.240.x.x(IP autoallocate)
           ▼
┌─────────────────────┐
│ 本节点 ztunnel pod  │ 应用 → 240.240.0.x:80
│   (DaemonSet)       │ ztunnel 查 ServiceEntry label: istio.io/use-waypoint: egress-waypoint
│                     │ HBONE 隧道 → egress waypoint pod
└──────────┬──────────┘
           │ ③ HBONE 隧道跨节点
           ▼
┌─────────────────────┐
│ Egress Waypoint     │ istio-waypoint GatewayClass
│ (istio-system/egress)│ Envoy 接收,按 ServiceEntry 配置:
│                     │  - VirtualService: 改 header、限 method
│                     │  - DestinationRule: HTTP → HTTPS 升级 (TLS origination)
│                     │  - 出口直接连外网 api.saas1.com:443
└──────────┬──────────┘
           │ ④ HTTPS 出网
           ▼
   api.saas1.com
   (公网目的地)
```

### 4.3 新旧链路关键差异

| 维度 | 旧(Pod→Nginx→Squid) | 新(Pod→ztunnel→Egress Waypoint) |
|---|---|---|
| **CA 信任位置** | Nginx 上 trust 目标 CA | **应用 Pod 自己 trust**(或 waypoint 配 DestinationRule TLS origination) |
| **域名白名单位置** | Squid ACL | **ServiceEntry**(每个域名 1 条) + **AuthorizationPolicy**(namespace 级) |
| **协议终止/升级** | Nginx 终止应用 TLS,重建到 Squid | waypoint 终止+可选 Liberty 升级 TLS 出网 |
| **审计位置** | Squid access log | ztunnel 日志(`src.workload, src.namespace, dst.addr`)+ waypoint access log |
| **部署成本** | 1 个 Nginx + 1 个 Squid 双 VM/MIG | **0 额外 VM**,waypoint 是集群内 Envoy pod |
| **多租户隔离** | Squid ACL 按 src IP 区分 team | AuthorizationPolicy `namespaces` selector |

### 4.4 责任分工对照(架构双向对称)

**正向(谁来连谁)**:
- Pod 出站到 `api.saas1.com` → **ztunnel 拦截 + DNS 解析 → 走 ServiceEntry → HBONE 到 egress waypoint**
- egress waypoint 出口直连公网 → **证书由 waypoint 配置**(可选 DestinationRule TLS origination)

**反向(谁授权 / 谁审计)**:
- **授权**:`AuthorizationPolicy` 绑 ServiceEntry + waypoint,**按 namespace / SA 决定谁能调**
- **审计**:ztunnel 日志(`src.workload, src.namespace, dst.addr, direction=outbound`)+ waypoint Envoy access log
- **凭证**:公网目的地如果需要 mTLS client 身份,waypoint 用 **DestinationRule `tls.mode: MUTUAL`** 配证书
- **KMS/凭据存储**:**waypoint 用 K8s Secret 存公网客户端证书**,Secret 由 cert-manager / 外部 CA 管理

---

## 5. Namespace-level 公共出网白名单 — 落地全貌(L7 Waypoint)

### 5.1 完整组件清单

```
模型         资源类型                                    命名空间                  数量    作用
───────────────────────────────────────────────────────────────────────────────────────────────
基础设施     Namespace + labels                          istio-egress              1       egress 资源承载 ns
基础设施     Gateway (istio-waypoint class)              istio-egress              1       egress waypoint 代理
基础设施     AuthorizationPolicy (default-deny)         istio-egress              1       waypoint 级白名单默认拒绝
安全/治理    ServiceEntry (每域名 1 条)                  istio-egress              N       注册外部目的地
安全/治理    AuthorizationPolicy (per-ServiceEntry)     istio-egress              N       按 ns 决定谁能调该 SE
可选 L7      VirtualService                                可在 istio-egress         N       header 重写 / 路径改写
可选 TLS     DestinationRule                              可在 istio-egress         N       TLS origination
```

### 5.2 Step-by-step 落地

#### Step 1:在 istiod 启用 DNS capture + IP autoallocate

> 严格原话:
> "Ensure that DNS capture and IP autoallocation are enabled in your ambient mesh, which are required for ServiceEntry resources to receive stable virtual IPs. If you followed the quickstart guide, these are already configured. **For Helm installations, add the following flags to your Helm install or upgrade command for the istiod Helm chart: `--set cni.ambient.dnsCapture=true --set pilot.env.PILOT_ENABLE_IP_AUTOALLOCATE=true`**"
> — [Solo.io 1.30.x egress §"Before you begin"](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/egress.md)

```bash
# 升级 istiod Helm release
helm upgrade istiod oci://gcr.io/istio-release/charts/istiod \
  --namespace istio-system \
  --reuse-values \
  --set cni.ambient.dnsCapture=true \
  --set pilot.env.PILOT_ENABLE_IP_AUTOALLOCATE=true
```

**验证**:
```bash
# 1. dnsCapture 生效(ztunnel 在每个 pod 内启动 DNS proxy)
kubectl get pods -n istio-system -l k8s-app=ztunnel -o yaml | grep -A2 "DNS"
# 或在业务 pod 内看 iptables
kubectl debug <pod> -it --image docker.io/istio/base --profile=netadmin \
  -n <ns> -- iptables-save | grep -E "15053|DNS"

# 2. IP autoallocate 生效(pilot 配置)
kubectl get configmap istio -n istio-system -o yaml | grep -E "IP_AUTOALLOCATE"
# 预期:  PILOT_ENABLE_IP_AUTOALLOCATE: "true"
```

#### Step 2:创建 egress ns 和 waypoint

```bash
# 1. 创建承载 egress 资源的 ns,本身加入 ambient
kubectl create namespace istio-egress
kubectl label ns istio-egress istio.io/dataplane-mode=ambient
kubectl label ns istio-egress istio.io/use-waypoint=egress-waypoint
```

```yaml
# 2. egress waypoint Gateway
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: egress-waypoint
  namespace: istio-egress
spec:
  gatewayClassName: istio-waypoint
  listeners:
    - name: mesh
      port: 15008
      protocol: HBONE
      allowedRoutes:
        namespaces:
          from: All    # 允许任意 ns 的 ServiceEntry 路由过来
  # replicas: 2     # HA 可选(Istio 1.30 controller 默认 2 副本)
```

```bash
# 3. 等待 waypoint 部署就绪
kubectl -n istio-egress rollout status deployment/egress-waypoint

# 4. 验证
kubectl get pods -n istio-egress
# 预期: egress-waypoint-xxx  1/1 Running
```

#### Step 3:为每个公共域名创建 ServiceEntry + AuthorizationPolicy

> 严格原话(关键):
> "**Create a ServiceEntry that represents the external service. Label it with `istio.io/use-waypoint` to route all traffic for that host through the egress gateway.**"
> "**Wildcard hostnames are not supported in ServiceEntry resources used with egress waypoints.**"
> — [Solo.io 1.30.x egress §"Step 2"](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/egress.md)

**示例:让 `team-a-runtime` 能调 `api.saas1.com`,且仅 `team-a-runtime` 能调**:

```yaml
# ServiceEntry — 注册外部目的地 + 绑定 waypoint
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: api-saas1-com
  namespace: istio-egress
  labels:
    istio.io/use-waypoint: egress-waypoint     # ← 关键 label,绑 egress waypoint
spec:
  hosts:
    - api.saas1.com                           # ← 单域名(不支持 wildcard)
  ports:
    - name: https
      number: 443
      protocol: HTTPS
      targetPort: 443
  resolution: DNS
  location: MESH_EXTERNAL
---
# AuthorizationPolicy — Namespace-level 白名单
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-team-a-to-saas1
  namespace: istio-egress
spec:
  targetRefs:
    - kind: ServiceEntry                      # ← 绑 ServiceEntry (而非 Service)
      group: networking.istio.io
      name: api-saas1-com
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces: ["team-a-runtime"]    # ← 仅 team-a ns 的 pod 能调
```

**验证 ServiceEntry 绑到了 waypoint**:
```bash
kubectl get serviceentry api-saas1-com -n istio-egress -o yaml
# 预期 status:
#   status:
#     addresses:
#     - host: api.saas1.com
#       value: 240.240.0.2        ← autoallocate 分配的稳定 IP
#     - host: api.saas1.com
#       value: 2001:2::2
#     conditions:
#     - lastTransitionTime: ...
#       message: Successfully attached to waypoint egress/egress-waypoint
#       reason: WaypointAccepted
#       status: "True"
#       type: istio.io/WaypointBound
```

#### Step 4:验证(从 team-a-runtime pod 出网到 api.saas1.com)

```bash
# 在 team-a-runtime ns 的 pod 内执行
kubectl exec -n team-a-runtime <pod> -- curl -vik https://api.saas1.com/data
# 预期: HTTP 200,且响应头含 server: istio-envoy (证明走了 waypoint)

# 反向验证:在 team-b-runtime ns 执行同样的命令
kubectl exec -n team-b-runtime <pod> -- curl -vik https://api.saas1.com/data
# 预期: 拒绝(RBAC: access denied) 或 DNS 解析不到
```

**ztunnel 日志确认**:
```bash
kubectl logs -n istio-system -l k8s-app=ztunnel --tail=20 | grep api.saas1.com
# 预期看到:
# info access connection complete src.addr=10.244.x.x:xxx
#   src.workload="<pod-name>" src.namespace="team-a-runtime"
#   dst.addr=240.240.0.2:443 (autoallocate IP,不是真实公网 IP)
#   direction="outbound" duration="..."
```

### 5.3 多域名批量模板(给团队加白名单的脚本)

```bash
#!/bin/bash
# add-public-egress-allowlist.sh
# 用法: add-public-egress-allowlist.sh <tenant-namespace> <algorithm>
# 例:   add-public-egress-allowlist.sh team-a-runtime api-saas1-com
#
# 前提: ServiceEntry + waypoint 已建好(见 21 文 §5.2 Step 2)
#       只需给一个 ns 授权调用一个已经注册的外部域名

set -euo pipefail

TENANT_NS="$1"
SE_NAME="$2"

cat <<YAML | kubectl apply -f -
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: "allow-${TENANT_NS}-to-${SE_NAME}"
  namespace: istio-egress
  labels:
    managed-by: egress-allowlist-script
    tenant-namespace: "${TENANT_NS}"
spec:
  targetRefs:
    - kind: ServiceEntry
      group: networking.istio.io
      name: "${SE_NAME}"
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces: ["${TENANT_NS}"]
YAML

echo "✅ AuthorizationPolicy 已创建: allow-${TENANT_NS}-to-${SE_NAME}"
echo "验证:"
kubectl get authorizationpolicy "allow-${TENANT_NS}-to-${SE_NAME}" -n istio-egress
```

### 5.4 跨 ns 共享 ServiceEntry(共享白名单池)

> 场景:多个 team 都需要调 `api.saas1.com`,但不想每个 team 各注册一条 ServiceEntry。

> 严格原话:
> "To create the ServiceEntry in a different namespace, [label it for cross-namespace use](https://docs.solo.io/istio/1.30.x/ambient/waypoints/configuration/#use-waypoints-across-namespaces)."
> — [Solo.io 1.30.x egress §"Step 2"](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/egress.md)

```yaml
# 在 istio-egress ns 注册共享 SE
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: api-saas1-com
  namespace: istio-egress
  labels:
    istio.io/use-waypoint: egress-waypoint
    istio.io/use-waypoint-namespace: istio-egress   # ← 跨 ns 共享时,waypoint 所在 ns
spec:
  hosts: [api.saas1.com]
  ports:
    - number: 443
      protocol: HTTPS
      targetPort: 443
  resolution: DNS
  location: MESH_EXTERNAL
---
# 给多个 team 各加一条 AuthorizationPolicy,共享同一条 SE
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-team-a-to-saas1
  namespace: istio-egress
spec:
  targetRefs:
    - kind: ServiceEntry
      group: networking.istio.io
      name: api-saas1-com
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces: ["team-a-runtime"]
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-team-b-to-saas1
  namespace: istio-egress
spec:
  targetRefs:
    - kind: ServiceEntry
      group: networking.istio.io
      name: api-saas1-com
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces: ["team-b-runtime"]
```

---

## 6. 落地全貌 — 公共出网关的 L7 增强能力

### 6.1 TLS origination — 应用发明文 HTTP,waypoint 升级 HTTPS 出网

> 严格原话:
> "**By default, all traffic within the ambient mesh is secured via mutual TLS. However, when routing traffic through an egress gateway, the egress gateway terminates the TLS connection and forwards the unencrypted request to the external service. With TLS origination, you instruct the egress gateway to re-encrypt the request before it is forwarded to the external service.**"
> — [Solo.io 1.30.x egress §"TLS origination"](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/egress.md)

**场景**:应用代码不想管 HTTPS 证书,只发明文 HTTP,waypoint 帮它升级成 HTTPS 出网。

```yaml
# ServiceEntry: 应用发 HTTP (80),waypoint 出 HTTPS (443)
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: api-saas1-com
  namespace: istio-egress
  labels:
    istio.io/use-waypoint: egress-waypoint
spec:
  hosts: [api.saas1.com]
  ports:
    - number: 80                  # ← 应用访问 80 (明文 HTTP)
      name: http
      protocol: HTTP
      targetPort: 443             # ← waypoint 出网用 443 (HTTPS)
  resolution: DNS
  location: MESH_EXTERNAL
---
# DestinationRule: 告诉 waypoint 出网时 TLS origination
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: api-saas1-com-tls
  namespace: istio-egress
spec:
  host: api.saas1.com
  trafficPolicy:
    tls:
      mode: SIMPLE                # ← 单边 TLS(信任目标服务器证书即可)
      # mode: MUTUAL              # ← 如目标要求 mTLS,需配 clientCertificates
      # clientCertificate: /etc/certs/client.pem
```

**应用代码写法**(零改动):
```bash
# 应用只管发明文 HTTP
curl http://api.saas1.com/data    # 应用到 waypoint: HTTP
# waypoint 出网:                 HTTP → HTTPS 升级 + TLS 终止 → 出网
```

### 6.2 HTTP 路径/Header 限制(L7 增强白名单)

> 来源:同目录 `06-policy-capabilities.md` §5.4(SNI 限制)

```yaml
# 限制 team-a 只能调 saas1 的 /api/v1/* 路径,不能调 /admin/*
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-team-a-saas1-v1-only
  namespace: istio-egress
spec:
  targetRefs:
    - kind: ServiceEntry
      group: networking.istio.io
      name: api-saas1-com
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces: ["team-a-runtime"]
      to:
        - operation:
            paths: ["/api/v1/*"]     # ← 路径白名单
            methods: ["GET", "POST"]
---
# 同时拒绝 /admin/* 路径(防止路径绕过)
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-team-a-saas1-admin
  namespace: istio-egress
spec:
  targetRefs:
    - kind: ServiceEntry
      group: networking.istio.io
      name: api-saas1-com
  action: DENY
  rules:
    - to:
        - operation:
            paths: ["/admin/*"]      # ← /admin 一律拒绝
```

### 6.3 SNI 限制(防"假装访问 saas1 实际访问 saas2")

```yaml
# 防止 SNI 欺骗
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: egress-allow-saas1-only
  namespace: istio-egress
spec:
  targetRefs:
    - kind: Gateway                 # ← 绑 egress waypoint(而非 ServiceEntry)
      group: gateway.networking.k8s.io
      name: egress-waypoint
  action: ALLOW
  rules:
    - to:
        - operation:
            hosts: ["api.saas1.com"]
            ports: ["443"]
      when:
        - key: connection.sni       # ← 强制 SNI 必须匹配
          values: ["api.saas1.com"]
```

---

## 7. 默认安全防护 — 三层 deny 纵深防御

> **核心思想**:Ambient 默认 passthrough 是危险的。Lex 团队必须显式分层 deny,即使被穿透也只能打到最窄的入口。

### 7.1 第一层:NetworkPolicy 锁业务 Pod 出网 IP

```yaml
# Runtime ns: 默认 deny egress,只放行 egress waypoint 和 NHF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress-allow-waypoint
  namespace: team-a-runtime
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # 1. 放行 kube-dns(业务解析域名)
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # 2. 放行 ztunnel 健康检查(必须!否则 mesh 断)
    - to:
        - ipBlock:
            cidr: 169.254.7.127/32   # kubelet health probe link-local
        - ipBlock:
            cidr: 10.0.0.0/8         # 集群内部 + NHF 目的网段
      ports:
        - protocol: TCP
          port: 15008                # HBONE
        - protocol: TCP
          port: 15006                # ztunnel inbound
    # 3. 放行 istiod (xDS 配置拉取)
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
      ports:
        - protocol: TCP
          port: 15012
        - protocol: TCP
          port: 15017
    # ❌ 不放行任何公网 IP!pod 必须通过 ServiceEntry → waypoint 走
```

### 7.2 第二层:egress waypoint 默认 deny,白名单由 AuthorizationPolicy 控制

> 严格原话:
> "Set up a default DENY policy to deny all traffic by default, then explicitly allow only the traffic that you want to permit."
> — [ambientmesh.io — Default DENY](https://ambientmesh.io/docs/security/ztunnel-authz/#default-deny)

```yaml
# egress ns 的 waypoint 级 default deny
# 部署在 istio-system,因为 GatewayClass 是 cluster-scoped
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: default-deny-all-waypoints
  namespace: istio-system
spec:
  targetRefs:
    - kind: GatewayClass           # ← 绑整个 istio-waypoint class
      group: gateway.networking.k8s.io
      name: istio-waypoint
# 空 spec: 没有任何规则,等于 deny all
```

**含义**:任何 waypoint(包括 ingress waypoint / 业务 ns waypoint / egress waypoint)默认拒绝所有 L7 流量。要让流量过,必须显式加 ALLOW。

> 注意:这是 L7 deny(L4 ztunnel 还会允许集群内东西向)。L4 层 deny 见 §7.3。

### 7.3 第三层:ztunnel L4 AuthZ 兜底(防 waypoint 绕过)

> 严格原话:
> "**Ambient mesh routes traffic through waypoints when traffic is sent to a service. The ztunnel for a destination workload continues to accept connections from any endpoint. To ensure all traffic received by a workload comes from an in-mesh source, enable `STRICT` peer authentication.**"
> "To prevent waypoint policy enforcement from being bypassed, **create a ztunnel policy that only allows connections from the workload's waypoint**."
> — [ambientmesh.io — Restricting workloads to only accept traffic from waypoints](https://ambientmesh.io/docs/security/waypoint-authz/#restricting-workloads-to-only-accept-traffic-from-waypoints)

```yaml
# 在 team-a-runtime ns: 业务 pod 只接受来自 waypoint + egress waypoint 的连接
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-only-waypoint-and-istio
  namespace: team-a-runtime
spec:
  selector:
    matchLabels:
      app: api-a                  # ← 业务 pod label
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - cluster.local/ns/team-a-runtime/sa/waypoint
              - cluster.local/ns/istio-egress/sa/waypoint
              - cluster.local/ns/istio-system/sa/istio-ingressgateway
---
# 配合 PeerAuthentication STRICT(强制 mTLS)
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: strict-mtls
  namespace: team-a-runtime
spec:
  mtls:
    mode: STRICT                   # ← 必须走 mesh (HBONE),不接受明文
```

### 7.4 纵深防御链(汇总表)

| 层 | 防御对象 | 配置位置 | 失败时的兜底 |
|---|---|---|---|
| **L7 waypoint AuthZ** | HTTP 路径/header/host 校验 | AuthorizationPolicy `targetRefs: Gateway egress-waypoint` | waypoint pod 不可达 → NetworkPolicy 兜底 |
| **L4 ztunnel AuthZ** | source IP / namespace / port | AuthorizationPolicy `selector: matchLabels` | ztunnel 失效 → PeerAuthentication STRICT 兜底 |
| **NetworkPolicy** | IP/port 防火墙 | `networking.k8s.io/v1 NetworkPolicy` | NetworkPolicy 失效 → GCP VPC Firewall 兜底 |
| **GCP VPC Firewall** | IP 段 + tag-based | GCP `gcloud compute firewall-rules` | 防火墙被绕 → 物理隔离不可能 |

---

## 8. 迁移路径:从 Squid allowlist 到 Ambient Egress

### 8.1 迁移前清单(必读)

- [ ] ambient 控制面已装(同目录 `02-install-ambient-helm.md` ✅)
- [ ] ztunnel + istio-cni DaemonSet 全部 Running
- [ ] Helm 已加 `--set cni.ambient.dnsCapture=true --set pilot.env.PILOT_ENABLE_IP_AUTOALLOCATE=true`(本篇 §5.2 Step 1)
- [ ] 业务 Runtime ns 已迁 ambient(同目录 `04-runtime-migration.md` ✅)
- [ ] 旧 Squid allowlist 名单已盘点(导出为域名列表)
- [ ] 旧 Pod→Nginx 链路已识别(哪些 Pod 在用)
- [ ] 公网客户端证书盘点(如目标需要 mTLS)

### 8.2 迁移顺序(按 ns 渐进)

```text
Week 1: 准备
├─ 在 istio-egress ns 装 waypoint(§5.2 Step 2)
├─ 把旧 Squid allowlist 清单转换为 ServiceEntry 列表(批量脚本)
└─ 选 canary ns:建议非关键业务(如 team-canary-runtime)

Week 2: Canary 验证
├─ 给 canary ns 的常用域名注册 ServiceEntry
├─ 配 AuthorizationPolicy 白名单(只放 canary)
├─ canary pod 改 hosts: curl/saas1.com 走新链路
├─ 监控:ztunnel 日志 + waypoint Envoy access log
└─ 双跑期:旧链路 + 新链路同时存在,旧 Squid 仍在

Week 3: 渐进推广
├─ 切 team-a-runtime(常用业务)
├─ 切 team-b-runtime(多租户验证)
└─ 拆掉旧 Squid allowlist(每个域名从 Squid 移除后,确认新链路 200)

Week 4: 收口
├─ 拆掉旧 Pod→Nginx pod + Service
├─ 拆掉旧 Squid(保留 read-only access log 一段时间)
└─ 文档化:teama-egress allowlist runbook
```

### 8.3 双运行期共存期的 NetworkPolicy 写法

**关键**:迁移期间,Pod 必须**同时能走旧链路和新链路**,否则会有 downtime。

```yaml
# Runtime ns 在迁移期间:同时放行 old-nginx 和 egress-waypoint
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-old-and-new-egress
  namespace: team-a-runtime
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    # kube-dns
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
    # 旧链路 Pod → Nginx (old-nginx 标签)
    - to:
        - podSelector:
            matchLabels:
              app: old-nginx-proxy
      ports:
        - protocol: TCP
          port: 3128                     # ← Squid 端口,旧链路终点
    # 新链路:ztunnel 内部
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8             # ← 集群内全部,HBONE 自动处理
      ports:
        - protocol: TCP
          port: 15008
```

### 8.4 切换验证脚本(每个 domain 必跑)

```bash
#!/bin/bash
# verify-egress-cutover.sh
# 用法: verify-egress-cutover.sh <namespace> <domain> <expected-status>
# 例:   verify-egress-cutover.sh team-a-runtime api.saas1.com 200

set -euo pipefail

NS="$1"
DOMAIN="$2"
EXPECTED="${3:-200}"

# 选一个 ambient pod(任意一个)
POD=$(kubectl get pod -n "$NS" -l istio.io/dataplane-mode=ambient -o name | head -1)
[ -z "$POD" ] && { echo "❌ 没找到 ambient pod"; exit 1; }

echo "=== 测试 $POD → $DOMAIN ==="

# 1. curl 测试
HTTP_CODE=$(kubectl exec -n "$NS" "$POD" -- \
  curl -sk -o /dev/null -w "%{http_code}" \
  --max-time 10 "https://$DOMAIN/" 2>/dev/null || echo "FAIL")

echo "HTTP code: $HTTP_CODE (expected: $EXPECTED)"

# 2. 验证确实走了 waypoint (响应头 server: istio-envoy)
SERVER=$(kubectl exec -n "$NS" "$POD" -- \
  curl -sk -I --max-time 10 "https://$DOMAIN/" 2>/dev/null | grep -i "^server:" | awk '{print $2}' || echo "")

echo "Server header: $SERVER"
if [[ "$SERVER" == "istio-envoy" ]]; then echo "✅ 走了 egress waypoint"; else echo "❌ 没走 waypoint(可能走了旧链路)"; fi

# 3. ztunnel 日志确认
echo "--- ztunnel 日志 ---"
kubectl logs -n istio-system -l k8s-app=ztunnel --tail=5 | grep "$DOMAIN" || echo "(没找到匹配日志)"

if [ "$HTTP_CODE" = "$EXPECTED" ]; then
  echo "✅ 验证通过"; exit 0
else
  echo "❌ 验证失败"; exit 1
fi
```

---

## 9. 网络策略适配(NetworkPolicy — Ambient 特殊性)

> 来源:同目录 `20-solo-ambient-kong.md` §networkpolicy + [ambientmesh.io NetworkPolicy docs](https://ambientmesh.io/docs/security/configure-networkpolicies)

### 9.1 关键端口必须放行(否则 Ambient 失败)

| 端口 | 方向 | 用途 | 严格原话 |
|---|---|---|---|
| **15008** | pod → ztunnel + 反向 | **HBONE 隧道**(Ambient 数据面核心)| "ztunnel operates at port 15008 for HBONE tunneling" — Istio docs |
| **15006** | ztunnel → pod | Inbound plaintext(ztunnel 解密后) | "ztunnel listens on 15006 for inbound traffic after decryption" |
| **15001** | pod → ztunnel | Outbound capture | 同上 |
| **169.254.7.127** | kubelet → pod | kubelet health probe link-local | "ambient SNATs kubelet probes to 169.254.7.127 to bypass NetworkPolicy" — ambientmesh.io |
| **15012** | pod → istiod | xDS 配置拉取 | istiod xDS port |
| **15017** | pod → istiod | xDS (mTLS) | istiod xDS port |
| **15020** | pod → ztunnel | Envoy admin(ambient 下由 ztunnel 暴露)| "In ambient mode, 15020 is the ztunnel admin port (not envoy)" |

### 9.2 Runtime ns NetworkPolicy 完整样例

> 注意:这与 `20-solo-ambient-kong.md` §networkpolicy §2 略有差异 — 这里加了**explicit egress to egress-waypoint**(公共出网白名单启用后)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ambient-runtime-allowlist
  namespace: team-a-runtime
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # 1. 放行 ztunnel 拦截(HBONE tunnel)
    - ports:
        - protocol: TCP
          port: 15008
        - protocol: TCP
          port: 15006
    # 2. 放行 kubelet 健康检查(link-local SNAT)
    - from:
        - ipBlock:
            cidr: 169.254.7.127/32
    # 3. 放行 ingress gateway(南北向入口)
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
          podSelector:
            matchLabels:
              app: istio-ingressgateway
      ports:
        - protocol: TCP
          port: 80
    # 4. 放行 KongDP(走 Kong 链路)
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kong-system
      ports:
        - protocol: TCP
          port: 80
  egress:
    # 1. kube-dns
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # 2. ztunnel / istiod (mesh 控制)
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8
      ports:
        - protocol: TCP
          port: 15008
        - protocol: TCP
          port: 15012
        - protocol: TCP
          port: 15017
    # 3. egress waypoint(公共出网必须经它)
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-egress
          podSelector:
            matchLabels:
              app.kubernetes.io/name: waypoint
      ports:
        - protocol: TCP
          port: 15008                   # ← HBONE to waypoint
    # ❌ 不放行任何公网 IP!pod 必须通过 ServiceEntry → waypoint 走
```

### 9.3 Egress waypoint ns 的 NetworkPolicy

```yaml
# egress-waypoint pod 出网到公网目的地
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: egress-waypoint-allow-public
  namespace: istio-egress
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: waypoint
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # 1. 接收 ztunnel HBONE
    - ports:
        - protocol: TCP
          port: 15008
    # 2. 接收 kubelet 健康检查
    - from:
        - ipBlock:
            cidr: 169.254.7.127/32
  egress:
    # 1. kube-dns
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
    # 2. istiod
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
      ports:
        - protocol: TCP
          port: 15012
    # 3. ✅ 公网(waypoint 是唯一能出公网的角色)
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 80
```

---

## 10. 严格定义 vs 简化解释 — 关键限定

| 边界 | 说明 | 来源 |
|---|---|---|
| **ztunnel 默认 passthrough(allow-all)** | "ztunnel captures outbound traffic and forwards without modification" — Solo.io 1.30.x egress overview | Solo.io |
| **`outboundTrafficPolicy: REGISTRY_ONLY` 在 ambient 不生效** | "ztunnel does not read `outboundTrafficPolicy`" | Solo.io migrate-sidecar §Behavioral differences |
| **ServiceEntry 不支持 wildcard hosts** | "Wildcard hostnames are not supported in ServiceEntry resources used with egress waypoints" | Solo.io 1.30.x egress §Step 2 |
| **`exportTo` 在 ambient 不生效** | "In ambient mode, `exportTo` is ignored. All ServiceEntry resources are globally visible" | Solo.io migrate-sidecar §Behavioral differences |
| **每个域名 1 条 ServiceEntry** | 没找到合并机制 — wildcard 不支持是核心原因 | Solo.io 1.30.x egress §Step 2 |
| **AuthorizationPolicy 绑 ServiceEntry 用 `targetRefs` (group: networking.istio.io)** | 不是传统 Service 的 group: "" | ambientmesh.io waypoint-authz |
| **L4 ztunnel AuthZ 用 `selector` (pod label),L7 waypoint AuthZ 用 `targetRefs`** | "Policies attached to waypoints use the `targetRef` field instead" | ambientmesh.io ztunnel-authz footnote |
| **L4 AuthZ 不支持 HTTP attributes(method/path/header)** | "ztunnel operates at L4, only L4 attributes supported" | ambientmesh.io ztunnel-authz §Allowed attributes |
| **ALLOW policy 含 L7 attrs 绑 ztunnel = 空匹配(全 deny)** | "fails safe: ALLOW policies with L7 attributes are empty and never match" | ambientmesh.io ztunnel-authz §Disallowed attributes |
| **DENY policy 含 L7 attrs 绑 ztunnel = 不带 HTTP 部分执行(更严)** | "DENY policies with L7 attributes are enforced without their HTTP components" | ambientmesh.io ztunnel-authz §Disallowed attributes |
| **kubelet health probe 在 ambient 下 SNAT 到 169.254.7.127** | "ambient uses the link-local address 169.254.7.127 to identify and correctly allow kubelet health probe packets" | ambientmesh.io networkpolicy docs |
| **必须显式放行 15008 / 15006 端口** | "NetworkPolicy must allow port 15008 (HBONE) and 15006 (ztunnel inbound)" | ambientmesh.io networkpolicy docs |
| **业务 pod 不应 listen 15001/15006/15008/15080** | "If app container binds to 15008 it conflicts with ztunnel" | 同目录 `09-ztunnel-redirection-app-compat.md` §2.2 |
| **ztunnel egressPolicies 是 Solo Enterprise alpha(本场景不用)** | "L4 ztunnel-native egress is alpha feature in Solo 1.30+ requires Enterprise license" | Solo.io 1.30.x egress overview |

---

## 11. 反向:Ambient Egress 不适用的情况

- **业务用大量 UDP 协议做 Egress**(e.g. QUIC / 自定义 UDP 服务):ztunnel 部分支持,DNS 强制 capture 但其他 UDP 默认不进 mesh
- **业务用 HTTP/3 / QUIC 出网**:ztunnel 不支持 QUIC
- **Egress 是企业内部大量域名(PaaS 类,几百个域名)**:每个域名 1 条 SE 不实际,可考虑做 SE 模板批量脚本,但需评估 istiod 规模
- **业务需要 mTLS client cert 出网到大量外部服务**:DestinationRule 配 clientCertificates 可行,但 Secret 维护成本高
- **集群完全没有公网入口/出口**(纯内网):Ambient Egress 是 over-engineering,直接用 NetworkPolicy 即可

---

## 12. 验证清单(egress 案例)

```bash
# 1. ambient mesh 跑通
kubectl get pods -n istio-system -l k8s-app=ztunnel -o wide
# 预期:每个节点 1 个 ztunnel pod Running

# 2. DNS capture + IP autoallocate 已开
kubectl get cm istio -n istio-system -o jsonpath='{.data.mesh}' | grep -E "dnsCapture|AUTOALLOCATE"
# 预期: mesh: ... dnsCapture: true ... PILOT_ENABLE_IP_AUTOALLOCATE: true

# 3. egress waypoint 跑通
kubectl get pods -n istio-egress
# 预期: egress-waypoint-xxx  1/1 Running

# 4. ServiceEntry 注册成功
kubectl get serviceentry -n istio-egress
# 预期: api-saas1-com  Status: ... addresses: 240.240.0.x

# 5. AuthorizationPolicy 允许/拒绝符合预期
# 允许: team-a pod → api.saas1.com 200
kubectl exec -n team-a-runtime <pod> -- curl -sk https://api.saas1.com/ -w "%{http_code}\n"
# 拒绝: team-b pod → api.saas1.com 拒绝
kubectl exec -n team-b-runtime <pod> -- curl -sk https://api.saas1.com/ -w "%{http_code}\n"

# 6. NetworkPolicy 阻挡未授权 IP
kubectl exec -n team-a-runtime <pod> -- curl -v --connect-timeout 5 https://8.8.8.8/ 2>&1 | head -10
# 预期: connect timeout 或 no route to host

# 7. ztunnel 日志确认流量经过 waypoint
kubectl logs -n istio-system -l k8s-app=ztunnel --tail=20 | grep -E "outbound.*api.saas1.com|240.240.0"
# 预期:看到 dst.addr=240.240.x.x(waypoint VIP,不是真实公网 IP)

# 8. waypoint access log 确认 L7 处理
kubectl logs -n istio-egress -l app.kubernetes.io/name=waypoint --tail=20 | grep api.saas1.com
# 预期:看到 HTTP 200 + server: istio-envoy 响应头标识
```

---

## 13. 推荐落地顺序(本场景 Lex 团队)

```text
Phase 0(1 周): 准备
├─ 升级 istiod Helm,加 dnsCapture + IP autoallocate
├─ 创建 istio-egress ns + waypoint Gateway
└─ 盘点旧 Squid allowlist 域名清单

Phase 1(1-2 周): Canary 验证
├─ 选 team-canary-runtime(非关键业务)
├─ 注册 5-10 个常用域名的 ServiceEntry
├─ 配 AuthorizationPolicy 允许 canary ns
├─ 双跑期:旧 Squid + 新 egress 同时存在
└─ 验证 + 监控

Phase 2(2-3 周): 渐进推广
├─ 切 team-a-runtime(常用业务)
├─ 切 team-b-runtime(多租户)
└─ 持续注册新域名(按业务需求)

Phase 3(1 周): 收口
├─ 拆旧 Nginx pod + Service
├─ 拆旧 Squid(保留 access log 一段时间)
└─ 文档化 + runbook
```

---

## 14. 与同目录其他文档的关系

| 文档 | 与本篇关系 |
|---|---|
| `02-install-ambient-helm.md` | 装 ambient 控制面;**本篇依赖其前提**,并扩展 istiod Helm 加 dnsCapture + IP autoallocate |
| `03-waypoint-design.md` | 业务 ns 内 waypoint 设计;**本篇是同一个 waypoint 机制但用作 egress 出口** |
| `04-runtime-migration.md` | 业务 ns 迁 ambient;**本篇依赖其前提** |
| `06-policy-capabilities.md` | L7 AuthZ 写法大全;本篇 §6.2 L7 增强白名单是其精简版 |
| `08-ambient-networkpolicy.md` | NetworkPolicy 与 ambient 协同;本篇 §9 是其在 egress 场景下的具体落地 |
| `09-ztunnel-redirection-app-compat.md` | ztunnel 拦截机制 + DNS capture 原理;**本篇 §5.2 Step 1 的前置** |
| `20-solo-ambient-kong.md` | Ingress 方向 Istio Gateway → KongDP → Runtime 闭环;**本篇是其 egress 方向的对称闭环** |

---

## 15. References(权威证据 + 来源日期)

### 15.1 官方文档

- [Solo.io Istio 1.30.x Ambient Egress Overview](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/overview.md) — 3 种 egress 方案对比 + 选型指南 — **来源日期:2025-01 官方**
- [Solo.io Istio 1.30.x L7 waypoint egress](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/egress.md) — 社区 L7 waypoint 完整步骤 — **来源日期:2025-01 官方**
- [Solo.io Migrate egress from sidecar to ambient](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/migrate-sidecar.md) — 行为差异(`outboundTrafficPolicy: REGISTRY_ONLY` 不生效 / `exportTo` 不支持) — **来源日期:2025-01 官方**
- [ambientmesh.io — Controlling mesh egress](https://ambientmesh.io/docs/traffic/mesh-egress) — 社区 egress 总览 + ztunnel egressPolicies(Solo Enterprise alpha)— **来源日期:2024-10 社区**
- [ambientmesh.io — Authorization policies with ztunnel](https://ambientmesh.io/docs/security/ztunnel-authz) — ztunnel L4 AuthZ + 默认 DENY + L7 attrs fail-safe — **来源日期:2024-12 社区**
- [ambientmesh.io — Authorization policy with waypoint proxies](https://ambientmesh.io/docs/security/waypoint-authz) — waypoint L7 AuthZ + 绑 GatewayClass 做 default-deny-all-waypoints — **来源日期:2024-12 社区**
- [ambientmesh.io — NetworkPolicy considerations](https://ambientmesh.io/docs/security/configure-networkpolicies) — kubelet probe SNAT 到 169.254.7.127 — **来源日期:2024-12 社区**
- [ambientmesh.io — Security 总览](https://ambientmesh.io/docs/security) — ambient 默认 PERMISSIVE / STRICT / DISABLE 不支持 — **来源日期:2024-12 社区**

### 15.2 同目录其他文档

- `01-ambient-vs-sidecar.md` — Ambient vs Sidecar 本质差异
- `02-install-ambient-helm.md` — Helm 安装 ambient
- `03-waypoint-design.md` — waypoint 设计决策
- `04-runtime-migration.md` — Runtime 迁 ambient
- `06-policy-capabilities.md` — AuthZ / PA 能力矩阵
- `08-ambient-networkpolicy.md` — Ambient + NetworkPolicy
- `09-ztunnel-redirection-app-compat.md` — ztunnel 拦截机制
- `20-solo-ambient-kong.md` — Ingress 方向闭环

### 15.3 旧参考(项目内现有 egress 实现)

- `/Users/lex/git/gcp/linux/networking/nhf.md` — Internal Egress (NHF + GCP 路由表)
- `/Users/lex/git/knowledge/safe/docs/saasp-pod-nginx-squid.md` — Public Egress (Pod → Nginx → Squid)

### 15.4 反向引用

本篇是 `20-solo-ambient-kong.md` 在 **egress 方向的对称闭环**(20 是 Ingress 方向,本篇是 Egress 方向)。
同目录 `README.md` 文档清单应在本篇提交后加一行。


```txt

已根据 [21-solo-ambient-egress.md](file:///Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/21-solo-ambient-egress.md) 的架构设计与实操规范，使用 [Archify](file:///Users/lex/git/gcp/skills/archify/SKILL.md) 技能生成了同名架构图 HTML 交互页面：

* **交互式架构图 HTML**：[21-solo-ambient-egress-architecture.html](file:///Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/21-solo-ambient-egress-architecture.html)
* **架构规范定义 JSON**：[21-solo-ambient-egress-architecture.json](file:///Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/21-solo-ambient-egress-architecture.json)
* **目录索引同步**：已在 [README.md](file:///Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/README.md#L59) 中更新关联引用。

---

### 架构拓扑与链路流向设计

针对文档中核心探讨的 **Internal（企业内网 NHF）** 与 **Public（公网 L7 Waypoint 租户白名单）** 双轨出网体系，整体图景划分为三层清晰的逻辑与数据面链路：

Row 1: [管控面与授权策略]
       [Istio 控制面 istiod] ──下发虚拟IP/xDS──► (ztunnel)              [租户授权策略 AuthZPolicy] ──租户白名单校验──► (waypoint)
       (IP Autoallocate 240.240.x.x)                                   (ALLOW: team-a-runtime 独占)
                                                                                   │
Row 2: [公共出网 Public Egress — L7 Waypoint 集中白名单链路]                         ▼
       [业务 Pod (team-a)] ──公网出网请求──► [节点 L4 代理 ztunnel] ──DNS映射虚拟IP──► [ServiceEntry 外部服务] ──HBONE隧道:15008──► [Egress Waypoint] ──HTTPS 443出网──► [公网 SaaS 目的地]
       (已授权租户)                          (DNS Proxy: 15053)                (api.saas1.com: 240.240.0.2)             (Envoy / TLS Origination)          (api.saas1.com:443)
                                                     │
                                             解包为原生IP(非Mesh)
                                                     ▼
Row 3: [内部出网 Internal Egress — NHF 双网卡 SNAT 兼容链路]
       [业务 Pod (team-b)] ──内部出网请求──► [GKE 节点路由 (LPM)] ────LPM选路(下一跳)────► [NHF ILB 转发规则] ──送入健康实例──► [NHF 双网卡 SNAT 实例] ──SNAT出网──► [公司内网 DRN / SCC]
       (未授权公网访问)                      (命中 128.0.0.0/2 & 10/8)             (VIP: 192.168.0.55)              (ens5 ➔ iptables ➔ ens4)         (128.171.x.x 统一审计)


---

### 架构核心要点呈现

1. **双轨分流决策（Internal vs Public）**：
   * **Internal 出网（NHF 零改造）**：非 Mesh 目标经 ztunnel 还原为原生 IP 包出节点，由 GCP VPC 路由表根据最长前缀匹配（LPM）命中 `128.0.0.0/2` 与 `10.0.0.0/8`，统一丢给 NHF ILB（`192.168.0.55`），与 Istio Ambient 完全解耦；
   * **Public 出网（替代 Squid）**：通过 `ServiceEntry` + `istio-waypoint` 托管集群外部域名，终结传统 Pod→Nginx→Squid 多跳架构。
2. **Namespace-level 公共出网白名单机制**：
   * `ServiceEntry` 配置 `istio.io/use-waypoint: egress-waypoint` 标签，由 Istiod 自动分配 `240.240.x.x` 虚拟 IP；
   * `AuthorizationPolicy` 精确限定 `namespaces: ["team-a-runtime"]`；未授权的 `team-b-runtime` 发起的出站流量在 Waypoint 处被 RBAC 严格拦截。
3. **Ambient 默认风险与三层纵深防御**：
   * 破除“封 sidecar 入口即安全”假设（ztunnel 默认 passthrough 且不读取 `REGISTRY_ONLY`）；
   * 通过 **NetworkPolicy 出口限制 + Waypoint 级 Default-Deny + ztunnel STRICT mTLS** 构筑三重防御体系。

---

### 验收与浏览器渲染指标

* **交付命令**：`archify deliver`（Showcase 质量配置文件）
* **架构规范验证**：9 项静态架构检查全部通过（单一 SVG 容器、正交布线、标签零遮挡、5 大边界容器零重叠）。
* **自动化视觉验收（`visual-check`）**：
  * 在 `1440×900`、`1600×1000`、`1920×1080` 及 `2048×1320` 四档标准分辨率与明暗双主题下，**无任何横向/纵向滚动溢出**（`overflowX: false`, `overflowY: false`），首屏完全平衡自洽；
  * 支持动态轨迹追踪（Trace Motion）、明暗主题切换及 4 大聚焦点（Overview / Public / Internal / Control Plane）导览。可以直接在浏览器中打开 [21-solo-ambient-egress-architecture.html](file:///Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/21-solo-ambient-egress-architecture.html) 进行体验。
```