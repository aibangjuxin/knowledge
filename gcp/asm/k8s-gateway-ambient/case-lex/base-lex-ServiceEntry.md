# base-lex-ServiceEntry.md — case-lex 场景下的 ServiceEntry + 双轨 Egress 治理

> **文档定位**: 基于 `case-lex/` 已实现场景(ambient waypoint + 9 条 NetPol + 3 条 mesh security),
> 探索**如何结合 Istio `ServiceEntry` 实现 Public Egress 的域名级访问控制**。
>
> **不修改 `case-lex/` 下任何现有文件**。本篇是探索文档 + 配方,落地时新增独立文件。
>
> ---
>
> **v2 修订说明(2026-10-02)** — 基于 Lex 补充的业务背景做了**实质性重写**:
>
> | v1 的判断 | v2 的修正 | 原因 |
> |---|---|---|
> | "NP-3 的 `128.0.0.0/2` 算错了,是阻塞级缺陷" | ❌ **撤回**。这是**设计意图**,不是 bug | 公司申请的公网段恰好落在 128/2 内,这个网段**就是**允许的出网范围 |
> | "L3/L4 粗放 + L7 精白名单 是正确职责划分" | ❌ **撤回**为普遍原则 | 公司策略是"**内部 DRN 能 L3 走通就默认不控**;public egress 必须按域名控" |
> | "egress waypoint 专属 NetPol 放最大 `0.0.0.0/0`" | ❌ **撤回**。改为**只放实际需要的** | 默认 deny 是策略,waypoint 出网也应最小放行 |
> | "出向 L7 完全空白" | ⚠️ **降级**为"L4 deny 基线已建立,缺 L7 开口" | NP-1 + NP-3 的 deny 结构**已在执行** deny all public |
> | "必须修 NP-3 才能防绕过" | ❌ **撤回**。**NP-3 就是那道防线** | v1 误判导致结论反向 |
> | 新增 | ✅ | **Squid 两级代理链路** 是 Lex 的现行方案,本文档给出其在 ambient 下的演进路径(§7) |
> | 新增 | ✅ | 明确 **"L3 可达即不控"是公司的有意策略**(§2.1) |
> | 新增 | ✅ | **大厂 SaaS 的 IP 白名单不可持续**这一现实约束(§6.3.1 / R1) |
>
> v1 的完整内容保留在 §16 修订对照表,便于追溯判断的变化。

---

## 0. TL;DR

### 0.1 核心结论(4 条)

**1. ServiceEntry 完全适合你的场景,而且在物理上是唯一解。**

你要的"public egress 必须走内部代理 + 按域名放行",L3(NHF)和 L4(NetPol)**做不到** ——
它们只看 IP 和端口,**看不到域名**。只有 L7 层能读 SNI / Host header。

**2. NP-3 的 `128.0.0.0/2` 是对的 —— v1 把它误判为缺陷,现撤回。**

这与你的公司策略**完全自洽**:

| 轨道 | 目标网段 | 落在 128/2? | NP-3 判定 | 符合公司策略? |
|---|---|---|---|---|
| A 内部 DRN / 办公网 | `128.171.x` 等公司段 | ✅ 在 | **ALLOW** | ✅ "能 L3 走通就默认不控" |
| B Public egress | `1.x` / `34.x` / `52.x` | ❌ 不在 | **DENY** | ✅ "public 必须走代理" |

→ **你要的 "deny all public" 基线,NP-3 现在就已经在执行了。**

**3. ServiceEntry 的作用是"在 deny 基线上精确开口",不是"从宽放行里收紧"。**

这改变了方案起点:v1 假设"先宽放行,再用 L7 收紧";你的实际形态是
**默认全拒 → 按需逐个开白名单**。ServiceEntry 就是那个"开口"。

**4. 现行 Squid 两级代理方案思路可保留,但在 ambient 下需要重新选型。**

- 现行:`Cloud DNS 别名 → ClusterIP:3128 → GKE Squid → GCE VM Squid → 公网`
- 问题:Squid 若入 mesh,ztunnel 会拦截,CONNECT 隧道被破坏;且 Squid ACL 依赖源 IP,语义会变
- **推荐**:`ServiceEntry + egress waypoint` 替代第一级 GKE Squid,保留第二级 GCE VM Squid(§7.5)

### 0.2 "ServiceEntry 能否达成目的"的直接回答

> **能**,但必须配合三件事,缺一不可:

| # | 组件 | 作用 | 缺了会怎样 |
|---|---|---|---|
| ① | `ServiceEntry` + `istio.io/use-waypoint` | 让 ztunnel 认识目标 + 强制走 L7 | 流量 passthrough 直连,无 L7 管控 |
| ② | `AuthorizationPolicy` 绑 `ServiceEntry` | 租户 + 域名 + method/path 白名单 | 任何 ns 任何 pod 都能访问 |
| ③ | **`NetworkPolicy` 收窄到"只允许经 waypoint"** | **防止静默绕过** | **waypoint 挂掉时流量静默直通,管控失效** |

> **③ 在你的场景里已经天然满足** —— NP-3 已经 DENY 了公网段(§10.3)。
> ServiceEntry 的工作是**新增**通往 egress waypoint 的合法通道,而不是**修改**现有规则。

---

## 1. 版本基线 —— `1.30.3-distroless` 是什么

### 1.1 你对 distroless 的理解正确,但它和 standard/solo 是两个正交维度

> **`distroless` 和 `standard`/`solo` 是两个正交的维度。**
> `1.30.3-distroless` = **Standard 发行版** + distroless 基础镜像。
> distroless 只影响**镜像瘦身**,不提供任何 mesh 功能。

### 1.2 Solo 官方原文(权威依据)

> **"Solo provides two main distributions of Istio as follows.**
> - **Standard**: A copy of the community Istio distribution. This distribution does not contain
>   Solo.io's enterprise features or extended Istio support. Example: `1.30.5`
> - **Solo**: An enterprise distribution of the community Istio project with additional security
>   patches, as well as certain Envoy filters to enable Solo Enterprise for Istio features, such as
>   support for deploying Istio service meshes in ambient mode. **You must use the `solo` image to
>   use these features.** Example: `1.30.5-solo`
>
> **Both Solo's `standard` and `solo` distributions of Istio come in the following optional varieties.**
> - **FIPS**: ... Examples: `1.30.5-fips`, `1.30.5-solo-fips`
> - **Distroless**: An image that is tagged with `distroless` is a slimmed down distribution with the
>   minimum set of binary dependencies to run the image, for enhanced performance and security. ...
>   Examples: `1.30.5-distroless`, `1.30.5-solo-distroless`
>
> An image might be tagged to meet multiple use cases, such as `1.30.5-solo-fips-distroless`."
>
> — [Solo Enterprise for Istio 1.30.x — Distributions](https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/)

> **Distroless 的本质**(与你引用的表述一致):
> "An image that is tagged with `distroless` is a slimmed down distribution with the minimum set of
> binary dependencies to run the image, to improve performance and security. Note that if your
> application depends on package management, a shell, or other operating system tools such as `pip`,
> `apt`, `ls`, `grep`, or `bash`, you must find another way to install these dependencies."

> **对你的环境的结论**:
> 1. 你跑的是 **社区 Istio 1.30.3 的代码路径**,行为与上游 `istio.io` 1.30 完全一致
>    → 本篇引用上游 Istio 文档的地方都成立。
> 2. **没有 n-4 CVE 回补**。需跟进社区 patch 版本
>    (Solo 1.30.x 支持 K8s 1.32–1.36,Gateway API 1.5.0)。
> 3. **Solo 企业 egress 功能全部不可用**:
>    - ❌ `solo-ztunnel-egress` GatewayClass(需 `-solo` + **Enterprise license**,且是 **Alpha**)
>    - ❌ agentgateway waypoint egress(Enterprise Alpha)
>    - ❌ Advanced mTLS egress(Enterprise Alpha)
>    - ❌ `solo.io/sidecar-skip-waypoint` annotation
>    - ✅ **L7 waypoint egress 无 license 要求** —— 就是上游 `istio.io/use-waypoint` + waypoint

### 1.3 distroless 对排障的实际影响

```bash
# ❌ distroless pod 里执行这些会报 "executable file not found in $PATH"
kubectl exec -n istio-system deploy/istiod -- ls /usr/local/bin
kubectl exec -n istio-system deploy/istiod -- grep -i fips /usr/local/bin/pilot-discovery

# ✅ 排障的正确姿势(全在集群外完成)
istioctl version
istioctl proxy-status
kubectl get pod -n istio-system -l app=istiod -o jsonpath='{.items[0].spec.containers[0].image}'
kubectl logs -n istio-system -l app=ztunnel --tail=100
istioctl ztunnel-config services | grep -i <host>
```

Solo 官方给的 FIPS 验证方式本身就承认了这点:

> "For distroless images, **copy the binary from the pod to your local machine first**."
> — [Solo 1.30.x — Installing and verifying FIPS-compliant Istio images](https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/)

```bash
# 确实需要进容器时,用 kubectl cp 拿到本地再看
kubectl cp -n istio-system \
  $(kubectl get pod -n istio-system -l app=istiod -o jsonpath="{.items[0].metadata.name}"):/usr/local/bin/pilot-discovery \
  ./pilot-discovery
strings ./pilot-discovery | grep -i fips
```

---

## 2. ★ case-lex 现状盘点(基于业务背景重写)

### 2.1 公司 Egress 策略(两轨制)—— 理解全篇的前提

```
┌───────────────────────────────────────────────────────────────────────────────┐
│  公司 Egress 策略                                                              │
│                                                                               │
│  A. 内部 DRN / 办公网出口          ← 网段恰好落在 NP-3 的 128.0.0.0/2 内      │
│     ├─ 目标:公司申请到的公网段 + on-prem 数据中心(DRN/SCC)                    │
│     ├─ 规则:★ 能走 L3 出去就默认不控 ★                                        │
│     └─ 实现:GCP 路由 LPM → NHF ILB(192.168.0.55)→ SNAT → 办公网统一审计       │
│                                                                               │
│  B. Public Egress(百度 / 搜狐 / 微软 / M365 ...)   ← 网段不在 128/2 内         │
│     ├─ 目标:真正的公网 SaaS                                                    │
│     ├─ 规则:★ 必须走内部代理,按域名放行,默认 deny all ★                       │
│     └─ 现状:Cloud DNS 别名 → GKE Squid:3128 → GCE VM Squid → 公网              │
└───────────────────────────────────────────────────────────────────────────────┘
```

> **这是理解全篇的关键**。v1 把 NP-3 判为"缺陷"是因为只看了 CIDR 语义,
> 没看到它承载的是**公司策略 A 的精确映射**。
>
> 「L3 可达即不控」是**有意的策略选择**,不是技术债 —— 公司出口已有统一审计
> (Squid ACL / 办公网防火墙),Istio 层没必要重复管控,只需保证"不该走的走不出去"。

### 2.2 轨道 B 的现行两图(Lex 提供)

#### 2.2.1 HTTP CONNECT 请求流程

```
API Pod            Cloud DNS       GKE Squid       GCE VM Squid      Microsoft
   │                  │               │                │                │
   │─1. DNS query microsoft.intra.aibang.local─────▶│                │
   │◀─2. A = 10.68.x.x (Squid Service ClusterIP)─────┘                │
   │                                                                     │
   │─3. CONNECT login.microsoft.com:443 (HTTP/1.1)──────────────────────▶│
   │                  │   ACL: src IP ∈ localnet                            │
   │                  │        ∧ domain ∈ allowed_domains                   │
   │                  │        ∧ port 443 ∈ Safe_ports                      │
   │                  │────────4. CONNECT forward ────────────────────────▶│
   │                  │               │   ACL: src IP ∈ gke_cluster         │
   │                  │               │        ∧ domain ∈ microsoft_domains  │
   │                  │               │        ∧ business hours (optional)   │
   │                  │               │────5. TCP connect ─────────────────▶│
   │                  │               │◀───6. Connection established────────│
   │◀──8. 200 Connection established──────────────────────────────────────│
   │──9. encrypted HTTPS data(TCP tunnel 已建立,全程加密字节流转发)───────▶│
```

**要点**:
- 第 3→4 步的 `CONNECT` 是 **HTTP 方法**,Squid 靠它知道"目标域名"
- 第 9-14 步是**加密字节流**,Squid 只转发不解密
- **两级 ACL 各自独立**:GKE Squid 校验"来源可信",GCE VM Squid 校验"域名合规"

#### 2.2.2 Cloud DNS 别名解析流程

```
API Pod ──1. nslookup microsoft.intra.aibang.local──▶ Cloud DNS
                                                      │ 查 Zone → A Record
API Pod ◀──2. A = 10.68.x.x (Squid Service ClusterIP)──┘
API Pod ──3. HTTP Request to 10.68.x.x:3128──▶ Squid Service
                                                    │ K8s Service 负载均衡
                                                    ▼
                                               Squid Pod(健康实例)
```

> **这个设计的精妙之处**:应用代码里只需要知道 `microsoft.intra.aibang.local` 这个内部域名,
> 它的 DNS 记录直接指向 Squid 的 ClusterIP。**应用完全无感** ——
> 不需要知道 Squid 存在,也不需要配 `HTTPS_PROXY` 环境变量。
>
> **但它在 ambient 下有一个致命问题** —— 见 §7.2。

### 2.3 现有三层管控 —— 修正后的责任矩阵

| 层 | 机制 | 现有配置 | 轨道 A(内部 DRN) | 轨道 B(public) |
|---|---|---|---|---|
| **L3** | GCP 路由 LPM + NHF ILB | 外部(不在本目录) | ✅ **主通道,默认不控** | ⛔ 不经过 |
| **L4** | K8s NetworkPolicy | NP-1 ~ NP-9 | ✅ `128.0.0.0/2` 放行 | ✅ **已 DENY**(基线生效中) |
| **L4** | mTLS / 身份 | PA STRICT + ztunnel | ✅ | ⚠️ 见 §2.5 |
| **L7** | waypoint + AuthZ | `waypoint-int` + 2 AuthZ | ❌ 按策略不需要 | ❌ **未启用(要补的就是这个)** |

> **与 v1 的关键差异**:v1 说"outbound L7 完全空白"过于绝对。准确表述:
> **L4 层的 deny 基线已建立并正在生效**,缺的是"**在 deny 基线上精确开出白名单**"的 L7 层。

### 2.4 现有 NetPol 中真正影响出网的规则

| NetPol | podSelector | 出向效果 | 对轨道 B 的意义 |
|---|---|---|---|
| NP-1 `default-deny-all` | `{}` 全 ns | ✅ 全部出向默认拒绝 | ⭐ **deny 基线的法律基础** |
| NP-2 `default-allow-egress-dns` | `{}` 全 ns | ✅ CoreDNS 53/UDP+TCP | DNS 必须保留 |
| NP-3 `default-allow-egress-public-cidr-block` | `{}` 全 ns | ✅ 放行 `128.0.0.0/2` + `10.0.0.0/8` | ⭐ **轨道 A 的实现;轨道 B 被排除在外** |
| NP-8 `default-allow-same-namespace` | `{}` 全 ns | ✅ 东西向 | 与 egress 无关 |
| NP-4/NP-5/NP-6/NP-7/NP-9 | waypoint / 探针 | 入向为主 | 与 egress 无关 |

**NP-3 的 `except` 清单逐条解读**:

```yaml
cidr: 128.0.0.0/2
except:
  - 10.0.0.0/8          # 单独由规则 2 放行(轨道 A 私网部分)
  - 172.16.0.0/12       # RFC1918,本场景不用
  - 192.168.0.0/16      # RFC1918,本场景不用
  - 169.254.0.0/16      # link-local,探针走 NP-9 单独放
  - 127.0.0.0/8         # loopback
  - 224.0.0.0/4         # 组播
  - 0.0.0.0/8           # RFC1122 "this network"
  - 100.64.0.0/10       # GKE Pod CIDR(★ 重要,见 §10.3)
```

> `except` 里**没有任何一条是"排除公网"** —— 因为 `128.0.0.0/2` 本身就**不含主流公网段**。
> 这不是遗漏,是**隐式的 deny**。真正的 deny 来自"未命中任何 allow 规则"。
>
> **v1 在这里犯了两个错**:
> 1. 把"只覆盖 24.97% 的 IPv4"当成缺陷 —— 实际上**覆盖 24.97% 正是你要的**(公司段)
> 2. 说"注释意图不符" —— 实际注释"允许到公网 + 私网"里的"公网"指的是**公司申请的公网段**

### 2.5 现有 AuthZ 的方向性(精确分析)

`03-mesh-security.yaml` 三条 policy 全部是**入向**语义:

| 资源 | 绑定对象 | 方向 | 对 egress 的影响 |
|---|---|---|---|
| `PeerAuthentication/default-strict-mtls` | 全 ns(无 selector) | 双向 mTLS | mesh 内流量加密,但**不限制出网目的地** |
| `AuthorizationPolicy/deny-all` | 全 ns(无 selector) | **入向** deny-all | ❌ 不管出向 |
| `AuthorizationPolicy/allow-ingress-gateway-to-waypoint` | `targetRefs: [Gateway/waypoint-int]` | **入向** ingress GW → waypoint | ❌ 不管出向 |
| `AuthorizationPolicy/allow-from-waypoint-to-workloads` | 全 ns | **入向** waypoint → 业务 pod | ❌ 不管出向 |

> **Istio RBAC 的方向性规则**:
> - `selector` / `targetRefs` 指向 **workload** → 作用于该 workload 的 **inbound**
> - `selector` / `targetRefs` 指向 **Gateway**(waypoint)→ 同时影响该 waypoint 的 in/outbound
> - `to.operation.hosts/paths/methods` 只在 **L7 可用**(waypoint 或 sidecar)
>
> **官方原文**:
> "Sidecar mode and L4 policies in ambient are _targeted_ in the same fashion: they are scoped by
> the namespace in which the policy object resides, and an optional `selector` in the `spec`."
> — [Istio — Use Layer 4 security policy](https://istio.io/latest/docs/ambient/usage/l4-policy/)

> **重要陷阱 —— ztunnel 的 fail-safe 行为**:
> "The ztunnel cannot enforce L7 policies. **If a policy with rules matching L7 attributes is
> targeted such that it will be enforced by a receiving ztunnel, it will fail safe by becoming a
> `DENY` policy.**"
> — 同上
>
> → 写 AuthorizationPolicy 时,`methods` / `paths` / `hosts` 只能配 `targetRefs: [ServiceEntry|Gateway|Service]`,
> 配 workload `selector` 会让 ztunnel 直接 DENY 全部流量。

> **另一条容易被忽略的规则**:
> "**Waypoint proxies do not impersonate the identity of the source workload.** Once you have
> introduced a waypoint to the traffic path, the destination ztunnel will see traffic with the
> _waypoint's_ identity, not the source identity. This means that when a waypoint is installed,
> **the ideal place to enforce policy shifts**."
> — 同上
>
> → 这解释了 `03-mesh-security.yaml` 里 `allow-from-waypoint-to-workloads` 的存在:
> **加了 waypoint 后,入向 AuthZ 必须认 waypoint 的身份,不能认原始调用方**。

### 2.6 现状总结:两轨各自的状态

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 轨道 A(内部 DRN)  ✅ 已闭环                                                 │
│   pod ──▶ GCP 路由 LPM ──▶ NHF ILB ──▶ SNAT ──▶ 办公网出口(已审计)         │
│   NetPol NP-3 已放行 128/2 + 10/8                                          │
│   ★ 按公司策略"能 L3 走通就默认不控" → 不需要 L7                           │
│   ★ 本篇不动这一轨                                                          │
├─────────────────────────────────────────────────────────────────────────┤
│ 轨道 B(public)     ❌ 需要补齐                                              │
│   pod ──▶ NetPol DENY(现状,符合预期)                                       │
│   ★ 但"业务需要访问微软/百度"时 → 无路可走                                  │
│   ★ 目标:deny 基线 + 按域名逐个开口                                        │
│   缺口:ServiceEntry + egress waypoint + AuthZ                              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. ServiceEntry 在这个场景里到底解决什么

### 3.1 一句话定位

> **ServiceEntry 把"外部目的地"变成网格内的一等公民,让 ztunnel / waypoint 知道:
> 这个 host 需要被拦截、需要走 L7、需要一个身份来做 AuthZ 决策。**

### 3.2 四个具体职责

| 职责 | 怎么实现 | 解决什么 |
|---|---|---|
| **① 让 ztunnel 认识目的地** | `hosts` + `resolution: DNS` | 应用 DNS 拿到 `240.240.0.x`,ztunnel 才能识别 |
| **② 强制 L7 出口** | `labels: istio.io/use-waypoint: <name>` | 流量必须经 waypoint,才能上 AuthZ / HTTPRoute |
| **③ 承载 L7 策略绑定点** | `AuthorizationPolicy.targetRefs: [ServiceEntry]` | 白名单从 IP 网段升级到**域名** |
| **④ 稳定 VIP(TCP 场景)** | `addresses` 显式指定 | TCP 无 SNI/Host,只能靠 IP |

### 3.3 ServiceEntry **不**做的事

- ❌ 不创建 K8s Service VIP —— 它是服务注册表条目
- ❌ **不拦截流量** —— 拦截是 ztunnel/istio-cni 的事
- ❌ 不控制加密 —— 那是 `PeerAuthentication` / `DestinationRule`
- ❌ **`exportTo` 在 ambient 无效** —— 别指望它做 ns 隔离
- ❌ 不支持 wildcard hosts(ztunnel/waypoint 层)—— 唯一例外见 §8.2

> **官方原文**:
> `hosts` 字段 — "**NOTE 3: Ztunnel and Waypoint proxies do not support wildcard hosts.**"
> `exportTo` 字段 — "**Note: Ztunnel and Waypoint proxies not support this field and will read it at `*`.**"
> — [ServiceEntry — Istio reference](https://istio.io/latest/docs/reference/config/networking/service-entry/)

### 3.4 Ambient 下的两个硬约束(必须先接受)

> **约束 1 — `outboundTrafficPolicy: REGISTRY_ONLY` 在 ambient 无效**
> "In sidecar mode, setting `outboundTrafficPolicy: REGISTRY_ONLY` in `MeshConfig` blocks traffic
> from sidecar proxies to any external destination not registered in the service registry.
> **In an ambient mesh, ztunnel does not read `outboundTrafficPolicy`. Traffic to unregistered
> destinations passes through by default.**"
> — [Solo 1.30.x — Migrate egress controls from sidecar to ambient](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/migrate-sidecar/)

> **约束 2 — `exportTo` 在 ambient 无效**
> "In ambient mode, `exportTo` is ignored. All `ServiceEntry` resources are globally visible regardless
> of the `exportTo` field. Namespace-scoped access control must be expressed through
> `AuthorizationPolicy` resources that target the `ServiceEntry` or the egress gateway."
> — 同上

**推论:隔离手段只剩 ① `AuthorizationPolicy`(需 waypoint 提供 L7)+ ② `NetworkPolicy`(L4)。**

---

## 4. 双轨 Egress 的分层决策框架

### 4.1 判定树

```
                    业务 pod 发起出网请求
                              │
                   ┌──────────┴──────────┐
                   ↓                     ↓
        目的地 IP 落在 128.0.0.0/2       目的地是公网 SaaS
        或 10.0.0.0/8?                    (百度/微软/M365...)
                   │                     │
                   ↓                     ↓
              轨道 A                  轨道 B
        ★ 默认不控(公司策略)      ★ 必须走 L7 管控
                   │                     │
                   ↓                     ↓
          GCP 路由 LPM              NetPol DENY(现状)
                   │                     │
                   ↓                     ↓
           NHF ILB → SNAT      ServiceEntry + egress waypoint
                   │                     │
                   ↓                     ↓
            办公网出口审计        AuthorizationPolicy 白名单
                                        │
                                        ↓
                                 目标 SaaS
```

### 4.2 分层职责表(修正版)

| 需求 | 落地层 | 机制 | case-lex 现状 |
|---|---|---|---|
| 出口 IP 固定 / 公司统一审计 | L3 | GCP 路由 + NHF ILB + SNAT | ✅ **轨道 A 已就绪** |
| 内部 DRN 默认不控 | L3 | 路由可达即放行 | ✅ **已实现(公司策略)** |
| 禁止 pod 直连公网 | L4 | NetworkPolicy | ✅ **NP-1 + NP-3 已在执行** |
| DNS 解析 | L4 | NetPol 放行 CoreDNS | ✅ NP-2 |
| mesh 内 mTLS + 身份 | L4 | ztunnel + PA STRICT | ✅ 已就绪 |
| **public egress 按域名放行** | **L7** | **ServiceEntry + AuthZ** | ❌ **本篇要补的** |
| **public egress 强制经内部代理** | **L7** | **egress waypoint** | ❌ **本篇要补的** |
| **按租户限制出网** | L7 | AuthZ `from.source.namespaces` | ❌ 空白 |
| **HTTP method/path 限制** | L7 | AuthZ `to.operation` | ❌ 空白 |
| **header 注入 / 改写** | L7 | VirtualService | ❌ 空白 |
| **TLS origination 集中化** | L7 | ServiceEntry `targetPort` + DR `SIMPLE` | ❌ 空白 |
| **出向审计(谁访问了哪个域名)** | L7 | ztunnel access log `dst.service` | ❌ 空白(现在只有 IP) |

### 4.3 为什么"public 必须走 L7"是能力边界,不是设计选择

| 需求 | L3(NHF) | L4(NetPol) | L7(ServiceEntry+AuthZ) |
|---|---|---|---|
| 按**域名**放行 | ❌ 只看 IP | ❌ 只看 IP | ✅ SNI / Host |
| 按 **HTTP method/path** | ❌ | ❌ | ✅ |
| 强制经内部代理 | ❌ | ⚠️ 只能按 IP | ✅ 按域名精确 |
| 注入认证 header | ❌ | ❌ | ✅ VirtualService |
| 集中 TLS 凭证 | ❌ | ❌ | ✅ DR `SIMPLE` |
| 审计"谁访问了哪个域名" | ❌ | ⚠️ 只有 IP | ✅ L7 log |
| 限流 / 熔断 | ❌ | ❌ | ✅ |

→ **轨道 B 必须 L7,是能力边界的必然结果。** 轨道 A 不需要 L7,是因为它按公司策略"不控"。

---

## 5. 轨道 B 的 ServiceEntry 设计

### 5.1 域名白名单的粒度决策

| 粒度 | 例子 | 评价 |
|---|---|---|
| 单域名 | `login.microsoftonline.com` | ✅ **推荐** —— 精确,可审计 |
| 服务族 | `*.microsoftonline.com` | ⚠️ 需确认无失控子域 |
| 整域 wildcard | `*.microsoft.com` | ❌ 风险大,见 §8.2 |

> **建议**:从**单域名**起步。微软认证通常只需要少数几个:
> `login.microsoftonline.com` / `graph.microsoft.com` / `*.blob.core.windows.net` 等。
> 逐个加比整域放行更容易审计和收敛。
>
> **起点建议**:先从**现有 GKE Squid 的 access.log** 统计真实需要的域名集合(§13.3 Phase 0),
> 而不是凭经验猜一个清单。

### 5.2 三种协议形态的选择

```
应用发什么          ServiceEntry protocol    waypoint 能做什么
─────────────────────────────────────────────────────────────────────
明文 HTTP           HTTP                     全部 L7 + TLS origination
应用自己 HTTPS      TLS (SNI 透传)            只做 L4 判定 + 审计,不能改 header
gRPC / HTTP2        GRPC / HTTP2             全部 L7
裸 TCP(无 SNI)      TCP + addresses 必填      只能 L4
```

> **`protocol: TLS` vs `HTTPS` 的区别**(极易踩):
> - `TLS` = Envoy **只读 SNI,不终结 TLS**,加密字节流原样转发 → 应用自己的证书链完整
> - `HTTPS` = Envoy 假定应用发明文 HTTP,尝试解析 → 应用已加密时解析失败
>
> **官方原文**: `ServicePort.protocol` — "TLS implies the connection will be routed based on the
> SNI header to the destination **without terminating the TLS connection**."
> — [ServiceEntry — Istio reference](https://istio.io/latest/docs/reference/config/networking/service-entry/)
>
> **规则**:应用自己管 TLS → `TLS`;需要 waypoint 帮它加密 → `HTTP` + `targetPort` + DR。

### 5.3 ★ DNS 命名策略 —— 与现有 Cloud DNS 别名方案的衔接

你有两条路可选:

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **A. 保留 Cloud DNS 别名(推荐)** | 应用仍访问 `microsoft.intra.aibang.local` → Cloud DNS 指到 `240.240.0.x` | 应用零改造,延续现状 | 需维护 DNS Zone;`operation.hosts` 要写**真实域名** |
| **B. 改用真实域名** | 应用直接访问 `login.microsoftonline.com` | ServiceEntry 语义最自然;审计日志直接显示真实域名 | 应用需改配置 |

> **推荐 A**(与你的现状一致,迁移成本最低)。关键技巧是
> **`resolution: STATIC` + `endpoints[].address` 填真实域名**:
> 应用连的是内部别名(可被 Cloud DNS / ztunnel DNS 代理接管),
> 但 ServiceEntry 把上游 endpoint 指向真实公网域名,waypoint 出网时由 Envoy 解析。
>
> ⚠️ **但要注意 `operation.hosts` 写的是哪个名字**:
> 写**真实目的地**(`login.microsoftonline.com`),因为 Envoy 看到的是解析后的
> `Host` header / SNI。**写 Cloud DNS 别名会匹配不上。** 这是本方案最容易出错的地方。

### 5.4 DNS auto-allocation 前置条件

```bash
# 验证 1:istiod 是否开了 IP autoallocate
kubectl get configmap istio -n istio-system -o yaml | grep -E "IP_AUTOALLOCATE"
# 期望:PILOT_ENABLE_IP_AUTOALLOCATE: "true"

# 验证 2:ztunnel 是否开了 DNS capture
kubectl get ds ztunnel -n istio-system -o yaml | grep -E "DNS_CAPTURE"
# ambient 1.25+ 默认开启

# 验证 3:实际看分配的 VIP
kubectl get serviceentry <name> -n <ns> -o jsonpath='{.status.addresses}'
# 期望:[{"host":"...","value":"240.240.0.2"}]
```

> **官方提醒(ztunnel 出网最常见故障)**:
> "In ambient mode, the ztunnel only sees traffic at Layer 4, and does not have access to HTTP
> headers. Therefore, **DNS proxying is required to enable resolution of `ServiceEntry` addresses,
> especially in the case of sending egress traffic to waypoints**."
> — [Istio — DNS Proxying](https://istio.io/latest/docs/ops/configuration/traffic-management/dns-proxy/)

> "Istio will automatically allocate non-routable VIPs (from the **Class E subnet**) to such services
> **as long as they do not use a wildcard host**."
> — 同上

---

## 6. egress waypoint 落地

### 6.1 ★ 为什么放独立 namespace(而非同 ns)

| 维度 | 同 ns | 独立 `istio-egress` ns ★ |
|---|---|---|
| 与轨道 A 的 NetPol 关系 | ⚠️ NP-3 `podSelector: {}` 覆盖全 ns,waypoint **继承 128/2 放行** | ✅ **完全隔离** |
| 白名单治理位置 | 业务 ns(租户可见可改) | 平台 ns(租户改不了)★ |
| 误配影响半径 | 全租户 | 仅 egress |
| 跨租户复用 | ❌ 做不到 | ✅ 天然支持 |
| 需理解 NetPol 并集语义 | 需(易踩坑) | 全新写,清晰 |

> **关键理由**:NP-3 的 `podSelector: {}` 意味着同 ns 的 egress waypoint 会
> **继承 `128.0.0.0/2` 的放行** —— 这本身符合公司策略(轨道 A),
> 但如果 waypoint 需要访问的公网段恰好也在 128/2 内,就会出现"两条路都通"的歧义。
> 独立 ns 可以完全绕开这个耦合。

### 6.2 Namespace + Waypoint

```yaml
# 10-egress-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: istio-egress
  labels:
    # 加入 ambient 数据面(waypoint 自己要收发 HBONE)
    istio.io/dataplane-mode: ambient
    # ★ 本 ns 内所有服务的流量都走 egress-waypoint
    #   包括这里的 ServiceEntry → 所以不需要在每个 SE 上重复打 label
    istio.io/use-waypoint: egress-waypoint
    gateway-access: platform-egress      # 平台层标识,业务租户不应触碰
    role: egress
---
# 10-egress-waypoint.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: egress-waypoint
  namespace: istio-egress
  labels:
    istio.io/waypoint-for: all
    gateway-access: platform-egress
    role: egress
spec:
  gatewayClassName: istio-waypoint
  replicas: 2
  infrastructure:
    labels:
      gateway-access: platform-egress
      role: egress
  listeners:
    - name: mesh
      port: 15008                       # HBONE,Istio 强制不可改
      protocol: HBONE
      allowedRoutes:
        namespaces:
          from: All                     # ★ 接受任意 ns 的 ServiceEntry 挂上来
          # 生产收敛版:
          # from: Selector
          # selector:
          #   matchLabels:
          #     gateway-access: <approved-tenant-list>
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: egress-waypoint
  namespace: istio-egress
spec:
  minAvailable: 1
  selector:
    matchLabels:
      gateway.networking.k8s.io/gateway-name: egress-waypoint
```

> ★ **不要给业务 ns 打 `istio.io/use-waypoint: egress-waypoint`** ——
> 你的 `00-namespace-*.yaml` 已有 `istio.io/use-waypoint: waypoint`(指向 `waypoint-int`),
> 那是给**入向**用的。ns 级的 `use-waypoint` 是粗粒度全量语义,
> 精确控制要打在 **Service / ServiceEntry** 上。

### 6.3 ★ `istio-egress` ns 的 NetPol —— 只放实际需要的

**这是 v2 相对 v1 的核心修正。** v1 建议 `0.0.0.0/0`,那是错的思路 ——
既然默认 deny 是策略,waypoint 出网也应该**最小放行**。

```yaml
# 10-egress-netpol.yaml
# ── ① 默认拒绝 ──
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: istio-egress
  labels:
    gateway-access: platform-egress
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
# ── ② egress waypoint 出向:最小放行 ──
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: egress-waypoint-minimal-egress
  namespace: istio-egress
  labels:
    gateway-access: platform-egress
spec:
  podSelector:
    matchLabels:
      gateway.networking.k8s.io/gateway-name: egress-waypoint
  policyTypes: [Egress]
  egress:
    # 2.1 ✅ waypoint 自身需要 xDS / 证书
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
      ports:
        - protocol: TCP
          port: 15012        # xDS
        - protocol: TCP
          port: 15017        # SDS / Citadel

    # 2.2 ✅ waypoint 需要 DNS(解析 ServiceEntry 的真实 endpoint)
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

    # 2.3 ★ 白名单域名的实际落地网段 —— 见 §6.3.1 的重要警告
    #     这是一个"必须由数据驱动、且可能不可持续"的位置
    #     ⚠️ 下面用示例网段占位,必须替换为 §6.3.1 统计出的真实网段
    - to:
        - ipBlock:
            cidr: 203.0.113.0/24        # ★ 占位示例,必须替换
      ports:
        - protocol: TCP
          port: 443

    # 2.4 (可选)轨道 A 的公司段 —— 若 waypoint 也代理轨道 A 流量
    - to:
        - ipBlock:
            cidr: 128.0.0.0/2
            except:
              - 169.254.0.0/16
              - 127.0.0.0/8
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 80
---
# ── ③ egress waypoint 入向:来自业务 pod 的 HBONE ──
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: egress-waypoint-allow-hbone-in
  namespace: istio-egress
  labels:
    gateway-access: platform-egress
spec:
  podSelector:
    matchLabels:
      gateway.networking.k8s.io/gateway-name: egress-waypoint
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              businessId: ba000000      # 你的租户业务标签(见 00-namespace-*.yaml)
      ports:
        - protocol: TCP
          port: 15008
```

#### 6.3.1 ★★ 重要警告:大厂 SaaS 的 IP 白名单在实践中不可持续

**这是 v1 的严重疏漏,也是本方案最关键的一处现实约束。**

微软 / Google / AWS / 百度 / 搜狐 的公网段是 **CDN,IP 段每天变化,数量以千计**。
基于 IP 的 NetPol 白名单在实践中**无法长期维护**。

**先看数据,再决定**:

```bash
# 方法 1:统计某个域名当前解析到的 IP 数量
dig +short login.microsoftonline.com | grep -E '^[0-9]+\.' | wc -l
# 典型输出:4~20,但 CDN 切换后会变

# 方法 2:★ 从现有 GKE Squid 的 access.log 统计真实需求(最准确)
# Squid 日志格式:CONNECT login.microsoftonline.com:443 ...
kubectl logs -n <squid-ns> deploy/squid --tail=100000 2>/dev/null | \
  grep -oE 'CONNECT [a-zA-Z0-9.-]+' | awk '{print $2}' | sort | uniq -c | sort -rn
# 输出:真实被访问的域名 + 频次 → 这就是你的白名单起点

# 方法 3:从 GCE VM 上的 Squid 日志统计(第二级 ACL 看到的更完整)
ssh <gce-vm> "sudo tail -100000 /var/log/squid/access.log" | \
  grep -oE 'CONNECT [a-zA-Z0-9.-]+' | awk '{print $2}' | sort -u

# 方法 4:从 ztunnel access log 反推(已有 egress 流量时)
kubectl logs -n istio-system -l app=ztunnel --tail=100000 | \
  grep -oE 'dst\.addr=[0-9.]+:[0-9]+' | sort -u
```

**基于统计结果的三种处理策略**:

| 策略 | 做法 | 适用 | 评价 |
|---|---|---|---|
| **① 精确保留网段白名单** | NetPol 只放行统计出的网段 | 域名少且稳定(内部 API、自建服务) | ✅ 最严格,但需定期复查 |
| **② NetPol 放宽到 443,域名交给 AuthZ** | NetPol 放行公网 443(或不加公网规则),<br>`AuthorizationPolicy.to.operation.hosts` 做真正白名单 | **微软/M365 等大厂** | ✅ **推荐** —— 职责分层正确 |
| **③ 走 forward proxy(保留 Squid)** | 见 §7.3 方案 A/C | 已有 Squid 基础设施 | ✅ 迁移成本最低 |

> **我的建议(针对你的场景)**:采用 **②**。
>
> 理由:NetPol 是 **netns 级**的粗边界,它的正确粒度是"**允许哪些端口类型出网**",
> 而不是"允许哪个 CDN 段出网"。后者注定失败。
> 真正的域名白名单由 `AuthorizationPolicy` 的 `operation.hosts` 承担 ——
> **这正是 L7 存在的意义,也是 ServiceEntry 的价值所在。**
>
> 换句话说:**如果你的方案依赖维护一个 SaaS 的 IP 白名单,方案就是错的。**
> 正确的分工是:NetPol 管"能不能出网 + 走哪个端口",AuthZ 管"能访问哪个域名"。

### 6.4 ServiceEntry 配置模板

```yaml
# 11-serviceentry-microsoft-login.yaml
# 轨道 B:微软认证 —— 单域名白名单 + 租户隔离
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: microsoft-login
  namespace: istio-egress
  labels:
    gateway-access: platform-egress
spec:
  hosts:
    - microsoft.intra.aibang.local          # ★ Cloud DNS 别名(与你的现状一致)
  ports:
    - number: 443
      name: https
      protocol: TLS                        # ★ 应用自己发 HTTPS → TLS 透传
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: login.microsoftonline.com   # ★ 真实目的地,waypoint 出网时解析
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: microsoft-login-allow
  namespace: istio-egress
  labels:
    gateway-access: platform-egress
spec:
  # ★ targetRefs 绑 ServiceEntry —— 这是 waypoint 的 L7 绑定点
  # ⚠️ 不能用 workload selector(外部服务无 workload,且 ztunnel 会 L7 fail-safe → DENY)
  targetRefs:
    - kind: ServiceEntry
      group: networking.istio.io
      name: microsoft-login
  action: ALLOW
  rules:
    - from:
        - source:
            # ★ 租户级隔离,替代失效的 exportTo
            namespaces: ["ba000000-lex-int"]
            principals:
              - "cluster.local/ns/ba000000-lex-int/sa/app-ksa"   # 更细:绑到 KSA
      to:
        - operation:
            hosts: ["login.microsoftonline.com"]    # ★ 真实域名(不是别名)
            ports: ["443"]
```

#### 6.4.1 变体 —— 需要 TLS origination(应用发明文 HTTP)

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: internal-api-plaintext
  namespace: istio-egress
  labels:
    gateway-access: platform-egress
spec:
  hosts:
    - internal-api.intra.aibang.local
  ports:
    - number: 80
      name: http
      protocol: HTTP                 # ★ 应用发明文
      targetPort: 443                # ★ waypoint 实际用 443 出去
  location: MESH_EXTERNAL
  resolution: DNS
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: internal-api-tls
  namespace: istio-egress
spec:
  host: internal-api.intra.aibang.local
  trafficPolicy:
    tls:
      mode: SIMPLE                   # ★ waypoint 侧发起 TLS
    connectionPool:
      http:
        maxRequestsPerConnection: 100
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 60s
```

> **官方依据**:
> "Application pods can send plaintext HTTP to the egress gateway; the gateway upgrades to HTTPS
> before forwarding to the external host. This concentrates TLS credential management at the gateway
> and avoids distributing certificates to each application pod. ... Update the `ServiceEntry` to map
> the plaintext port to the TLS port, and add a `DestinationRule` to originate the TLS connection."
> — [Istio — Egress gateways (ambient) §Originate TLS at the egress gateway](https://istio.io/latest/docs/ambient/usage/egress-gateway/)

#### 6.4.2 变体 —— 裸 TCP 外部服务(轨道 A 的 on-prem DB)

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: onprem-sql-drn
  namespace: istio-egress
  labels:
    gateway-access: platform-egress
  annotations:
    # ⚠️ 见 §9.1 —— 多子网 SQL 连接策略,1.30.3 可能不生效,先验证再用
    # ambient.istio.io/connect-strategy: FIRST_HEALTHY_RACE
spec:
  hosts:
    - sql-onprem.drn.internal      # 合成域名,业务代码用它
  addresses:
    - 10.72.1.50/32                 # ★ TCP 场景必须显式 VIP
  ports:
    - number: 1433
      name: mssql
      protocol: TCP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: 10.72.1.50
      ports:
        mssql: 1433
      locality: eu-west2
```

> **`addresses` 必填的原因**(官方原文):
> "If the Addresses field is empty, traffic will be identified **solely based on the destination
> port**. In such scenarios, the port on which the service is being accessed must not be shared
> by any other service in the mesh. ... **the sidecar will behave as a simple TCP proxy**"
> — ServiceEntry reference,`addresses` 字段
>
> 在 ambient 下,ztunnel 只有 L4。`protocol: TCP` 没有 SNI / Host 可匹配,**只能靠目的 IP**。

### 6.5 验证

```bash
# 1. waypoint 就绪
kubectl get gateway -n istio-egress
istioctl waypoint list -n istio-egress

# 2. ServiceEntry 绑定状态
kubectl get serviceentry microsoft-login -n istio-egress -o yaml | grep -A5 'WaypointBound'
# 期望:type: istio.io/WaypointBound
#       status: "True"
#       message: Successfully attached to waypoint istio-egress/egress-waypoint

# 3. 应用侧 DNS 解析
kubectl exec -n ba000000-lex-int deploy/app -- getent hosts microsoft.intra.aibang.local
# 期望:240.240.0.x(不是 ClusterIP,不是真实公网 IP)

# 4. ztunnel 侧确认走了 waypoint
kubectl logs -n istio-system -l app=ztunnel --tail=200 | grep 'egress-waypoint'
# 期望:dst.workload="egress-waypoint-xxx"
#       dst.hbone_addr=240.240.0.2:443
#       dst.identity="spiffe://<cluster>/ns/istio-egress/sa/egress-waypoint"

# 5. waypoint 侧确认真的转发出去
kubectl exec -n istio-egress deploy/egress-waypoint -c istio-proxy -- \
  pilot-agent request GET stats | grep upstream_rq_total
# 期望:非零
```

---

## 7. ★ 现行 Squid 两级代理方案在 ambient 下的演进

### 7.1 现行方案的优点(应保留的部分)

```
Cloud DNS 别名 → GKE Squid:3128 → GCE VM Squid → 公网
```

| 优点 | 说明 |
|---|---|
| ✅ **应用零改造** | 应用只知道 `microsoft.intra.aibang.local`,不需要 `HTTPS_PROXY` |
| ✅ **ACL 表达力强** | Squid ACL 可按 `src IP ∧ dst domain ∧ port ∧ time` 组合 |
| ✅ **两级独立审计** | GKE 侧校验来源,GCE 侧校验域名,任一侧可单独收紧 |
| ✅ **已有 access.log** | 审计格式成熟 |
| ✅ **固定出口 IP** | 对某些对端有 IP 白名单要求时必要 |

### 7.2 ambient 下的三个冲突

| # | 冲突 | 症状 | 根因 |
|---|---|---|---|
| **1** | GKE Squid 入 mesh 后被 ztunnel 拦截 | CONNECT 隧道建立失败 / 流量被重定向 | ztunnel 拦截所有出网 TCP;`CONNECT` 是应用层语义,ztunnel 看不懂 |
| **2** | **ACL 依赖源 IP,入 mesh 后语义被破坏** | `src IP in localnet` 匹配失败 | 经 ztunnel 转发后,源 IP 变成 node/ztunnel 身份 |
| **3** | Squid ACL 与 Istio AuthZ **职责重叠** | 两套策略要同步维护,容易漂移 | 都在做"谁能访问哪个域名" |

> **冲突 2 是最隐蔽的**:`CONNECT` 请求**不带 `X-Forwarded-For`**,
> 所以 Squid **无法还原原始源 IP**。你的 ACL 里 `src IP in localnet` /
> `src IP in gke_cluster` 在入 mesh 后会**完全失效**(或误匹配)。
> → **这是"Squid 不能入 mesh"的硬性技术理由,不是偏好问题。**

### 7.3 三方案对比

| 维度 | **A. 保留 Squid(摘出 mesh)** | **B. Istio egress waypoint(推荐)** | **C. 保留 Squid + Istio 分层** |
|---|---|---|---|
| 代理实现 | Squid `dataplane-mode: none` | Envoy waypoint | Squid(不摘出)+ waypoint 前置 |
| 域名白名单 | Squid ACL | `AuthorizationPolicy` | 两层都有 |
| 应用改造 | ❌ 无 | ❌ 无 | ❌ 无 |
| ambient 兼容性 | ✅ 摘出即隔离 | ✅ 原生 | ⚠️ 需仔细配 |
| 策略一致性 | ⚠️ 与 Istio 割裂 | ✅ 单一控制面 | ⚠️ 两套需同步 |
| 租户级隔离 | ❌ 无 | ✅ `from.source.namespaces` | ✅ |
| 审计 | Squid access.log | ztunnel `dst.service` + Envoy | 两者都有 |
| 固定出口 IP | ✅ Squid | ⚠️ 需另配(见 §7.5) | ✅ |
| 资源开销 | Squid pod | waypoint pod(多域名共享) | Squid + waypoint |
| 升级维护 | 独立(与 Istio 版本解耦) | 随 Istio 升级 | 两者都要 |
| **推荐度** | ⭐⭐⭐ 可行 | ⭐⭐⭐⭐⭐ **推荐** | ⭐⭐ 复杂度高 |

### 7.4 方案 A 细节 —— 保留 Squid 但摘出 mesh

如果因为业务连续性必须保留 Squid,**必须把它摘出 ambient**:

```yaml
# Squid 部署在独立 ns,且该 ns 不加 ambient label
apiVersion: v1
kind: Namespace
metadata:
  name: egress-proxy
  labels:
    # ⚠️ 关键:不加 istio.io/dataplane-mode,ztunnel 不接管
    role: egress-proxy
---
# Squid Pod 显式标 none(双重保险,即使 ns 以后被误加 label 也安全)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: squid
  namespace: egress-proxy
spec:
  template:
    metadata:
      labels:
        app: squid
        istio.io/dataplane-mode: none      # ★ pod 级摘出
```

```yaml
# ServiceEntry 让 ztunnel 认识 Squid(TCP,按官方要求)
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: squid-proxy
  namespace: istio-egress
spec:
  hosts:
    - squid-proxy.intra.aibang.local
  addresses:
    - 10.68.x.x/32            # ★ Squid Service ClusterIP
  ports:
    - number: 3128
      name: http-proxy
      protocol: TCP           # ★ 必须是 TCP,不是 HTTP(见下方说明)
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: 10.68.x.x
      ports:
        http-proxy: 3128
```

> ★ **关键设计:只为 Squid 建一个 ServiceEntry,不为微软建。**
>
> **官方原文**:
> "**Note that you must not create service entries for the external services you access through the
> external proxy, like wikipedia.org. This is because from Istio's point of view the requests are
> sent to the external proxy only; Istio is not aware of the fact that the external proxy forwards the
> requests further.**"
> — [Istio — Using an External HTTPS Proxy](https://istio.io/latest/docs/tasks/traffic-management/egress/http-proxy/)
>
> **同一份文档的另一个关键要求**:
> "**Define a TCP (not HTTP!) Service Entry for the HTTPS proxy.** Although applications use the HTTP
> CONNECT method to establish connections with HTTPS proxies, you must configure the proxy for TCP
> traffic, instead of HTTP. Once the connection is established, the proxy simply acts as a TCP tunnel."
> — 同上
>
> → **所以:应用侧流量是 TCP(到 Squid:3128),Istio 完全不知道 CONNECT 里是哪个域名。**
> → **这意味着"按域名放行"在这个方案里完全由 Squid ACL 负责,Istio 侧做不到。**

> ⚠️ **方案 A 的核心局限**:Istio 只能管控"谁能连 Squid",
> **管不了"哪个域名被允许"**。域名白名单 100% 依赖 Squid ACL。
> 好处是**与你的现状一致,风险低**;代价是**Istio 的 L7 能力完全用不上**。

### 7.5 ★ 方案 B 细节 —— 用 waypoint 替代第一级 GKE Squid(推荐)

**保留 GCE VM Squid 作为第二级(公司出口 IP + 统一审计),把第一级换成 waypoint**:

```
应用 → ztunnel → egress waypoint(Envoy,L7 管控)──┐
                    └─ AuthorizationPolicy: hosts 白名单│
                                                       │ 或
应用 → ztunnel → egress waypoint ────────────────────┴─▶ GCE VM Squid → 公网
                                                       └─ 保留公司 ACL + 固定出口 IP
```

| 能力 | 原(两级 Squid) | 新(waypoint + 一级 Squid) |
|---|---|---|
| 第一级 ACL(来源可信) | GKE Squid | ✅ **waypoint `AuthorizationPolicy`** |
| 第二级 ACL(域名合规) | GCE VM Squid | ✅ **保留不变** |
| 出口 IP 固定 | GCE VM | ✅ 保留 |
| 域名白名单可见性 | Squid 日志 | ✅ **waypoint 日志 + ztunnel `dst.service`** |
| 租户级隔离 | ❌ 无 | ✅ `from.source.namespaces` |
| 跨 ns 复用 | ❌ 每套 K8s 集群一套 | ✅ 所有租户共享一个 waypoint |

> **推荐路径**(保留 GCE VM Squid 的理由:公司可能对某些对端有**出口 IP 白名单**要求,
> 这是 waypoint 单独做不到的):
>
> ```
> 应用 ──▶ ztunnel ──▶ egress waypoint(L7 域名白名单)──▶ GCE VM Squid ──▶ 公网
>                   └── 新增 ──┘                       └── 保留不变 ──┘
> ```
>
> - waypoint 负责:**按域名 / 租户 / method/path 放行** + 结构化审计
> - GCE VM Squid 负责:**域名 ACL(第二道)+ 固定出口 IP + 公司既有合规要求**
> - 两层独立校验,**互为纵深防御**

> **如果你不需要固定出口 IP**(对端没有 IP 白名单要求),
> 那 GCE VM Squid 就可以完全退役,waypoint 直连公网 —— 结构最简:
> ```
> 应用 ──▶ ztunnel ──▶ egress waypoint(L7 域名白名单)──▶ 公网
> ```

### 7.6 方案 C —— 保留 Squid 且入 mesh(不推荐)

需要 Squid Pod 在 mesh 内并接受 ztunnel 代理。**技术上可行但会破坏 ACL 语义**:
- Squid 收到的是已解密的 TCP 流,需确认它不依赖原始源 IP 做 ACL
- 你的 ACL 里有 `src IP in localnet` / `src IP in gke_cluster` —— **经 ztunnel 转发后源 IP 会变**
- `CONNECT` 请求不带 `X-Forwarded-For`,Squid **无法还原原始源 IP**
- → **ACL 语义被破坏**。除非把 ACL 全部改写成基于域名的形式(那又为什么要 Squid?)

> **结论:方案 C 不推荐。** 若必须保留 Squid,至少有方案 A(摘出 mesh)作为退路。

### 7.7 三方案的最终建议

```
Phase 0(前置,零风险)—— ★ 这一步决定后续所有工作量
  ├─ 确认 istiod IP autoallocate 开关
  ├─ 确认 NP-3 的 128/2 是公司策略需要(不动它)
  └─ ★ 从现有 GKE Squid access.log 统计真实需要的域名清单

Phase 1(只读验证,零风险)
  ├─ 起 istio-egress ns + waypoint,先不绑任何流量
  └─ 验证 waypoint ready / ztunnel 能拿到配置

Phase 2(单域名影子验证)
  ├─ 1 个 ServiceEntry(如 microsoft-login),§6.3.1 策略②
  ├─ waypoint 侧先只开审计,不开拦截
  ├─ 对比 waypoint 日志 vs Squid 日志,确认流量路径符合预期
  └─ 跑 1~2 周,确认无遗漏

Phase 3(收口 —— 关键,做完才算"强制")
  ├─ waypoint 上 AuthZ 拦截(仅放行 SE 白名单)
  └─ 复跑 §11.3 第 6 步安全断言

Phase 4(评估是否下线 GKE Squid 第一级)
  ├─ 若无固定出口 IP 要求 → 可完全退役
  └─ 若有 → 降级为"仅固定出口 IP"的二跳中转
```

---

## 8. L4 vs L7 选型速查

### 8.1 决策表

| 目的地 | 走哪条 | 落地方式 | 状态 |
|---|---|---|---|
| on-prem DRN / 公司申请段 | **L3 NHF** | 现状保持,零改造 | ✅ 已就绪 |
| 微软 M365 / Entra ID | **L7 waypoint** | ServiceEntry + AuthZ | 📋 本篇 |
| 内部需中继的系统 | **L7 waypoint** | 同上 | 📋 本篇 |
| 裸 TCP(on-prem DB) | ⚠️ 见 §9.1 | 可能需摘出 mesh | ⚠️ 需评估 |
| 高频长连接,低延迟 | **L3 NHF** | 避免多一跳 Envoy | ✅ |

### 8.2 wildcard hosts 在 ambient 的处理

**默认不支持**:

> "**NOTE 3:** Ztunnel and Waypoint proxies do not support wildcard hosts."
> — [ServiceEntry — Istio reference](https://istio.io/latest/docs/reference/config/networking/service-entry/)

> Solo 侧同样提示:
> "**Wildcard hostnames are not supported in ServiceEntry resources used with egress waypoints.**"
> — [Solo 1.30.x — L7 waypoint egress, Step 2](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/egress/)

**唯一出路 —— `resolution: DYNAMIC_DNS`**(1.30 可用,ambient 下仅 `MESH_EXTERNAL` + 绑 waypoint):

```yaml
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: microsoft-wildcard
  namespace: istio-egress
  labels:
    istio.io/use-waypoint: egress-waypoint
spec:
  hosts:
    - "*.microsoftonline.com"
  location: MESH_EXTERNAL
  ports:
    - name: tls
      number: 443
      protocol: TLS
  resolution: DYNAMIC_DNS
```

> **官方 `DYNAMIC_DNS` 定义**:
> "`DYNAMIC_DNS` will attempt to resolve the host name specified in the Host header or SNI to an IP
> address when handling traffic. This allows multiple DNS addresses to be represented by a single
> wildcard `host` entry without having to explicitly enumerate all possible endpoints. ... This method
> of handling wildcard traffic is **not compatible with raw TCP traffic** where the original host
> cannot be recovered. `DYNAMIC_DNS` is only supported for wildcard hosts, both `MESH_INTERNAL` and
> `MESH_EXTERNAL` locations in sidecar mode and **only `MESH_EXTERNAL` in ambient mode (bound to a
> waypoint)**. Specified endpoints will be ignored."
> — ServiceEntry reference,`resolution` 字段

> ⚠️ **安全代价**:一条 `*.microsoftonline.com` 覆盖该域名下**所有子域**。
> 失控域 / 用户可控子域会被一并放通。
> **必须**在 AuthZ 里用 `to.operation.hosts` 精确收窄回具体子域。
>
> **本场景建议**:微软认证优先用**精确 host 列表**(§5.1),而非 DYNAMIC_DNS。

---

## 9. 1.30.3-distroless(Standard)专属坑位

### 9.1 ★ 多子网 SQL 连接被 ztunnel 乐观握手打断

**这条直接命中 NHF 架构图里的 on-prem DRN / SCC。**

Solo 官方在 Supported versions 页的 "Known Istio issues and version restrictions" 明确列出:

> "**Multi-subnet cluster connection failures** (upstream issue
> [ztunnel#1456](https://github.com/istio/ztunnel/issues/1456)): When a workload in an ambient mesh
> connects to a multi-subnet cluster (such as an SQL Server Multi-Subnet Cluster), **ztunnel's TCP
> proxy optimistically completes the TCP handshake for all connection attempts before verifying the
> upstream connection.** Depending on race conditions, the client can complete a TCP handshake with an
> inactive server instance. When the client then sends data, the connection fails because the upstream
> connection cannot be established. **As a workaround, opt the affected workloads out of the mesh** by
> adding the `istio.io/dataplane-mode: none` label to the pod or namespace. **A fix is available in
> upstream Istio and will be included in a future Solo release.** The fix introduces an
> `ambient.istio.io/connect-strategy: FIRST_HEALTHY_RACE` **annotation on a `ServiceEntry`** that
> instructs istiod to use a healthy-first connection strategy for the affected external service.
> See [istio#59083](https://github.com/istio/istio/pull/59083) for details."
>
> — [Solo 1.30.x — Supported versions](https://docs.solo.io/istio/1.30.x/ambient/about/images/versions/)

> ⚠️ **三处限定必须注意**:
> 1. "**A fix is available in upstream Istio** and **will be included in a future Solo release**"
>    → 你跑的 Standard `1.30.3` **大概率没有这个修复**。
> 2. PR #59083 状态标签为 **`needs-rebase` / `size-XL` / `size-L`**(2026-04-08 提交),
>    Solo 页只承诺 "future release"。
> 3. **落地策略不能依赖这个 annotation**,必须以实测为准。

**三档处理方案**:

| 方案 | 做法 | 适用 | 代价 |
|---|---|---|---|
| **A(推荐)** | 摘出 mesh:`istio.io/dataplane-mode: none` | SCC 多子网 TCP 场景 | 失去该 pod 的 mTLS/waypoint;但其流量本来走轨道 A(L3),**实际损失很小** |
| **B** | 试 `ambient.istio.io/connect-strategy: FIRST_HEALTHY_RACE` | 愿意尝鲜 | **1.30.3 可能不生效**,需实测 |
| **C** | `protocol: TCP` + 固定 `addresses` + 多 endpoint | 让 ztunnel 有多健康实例可选 | endpoint 需人工维护 |

> **建议直接上 A。** 理由:SCC 多子网 SQL 是纯 L3 场景(轨道 A),
> ServiceEntry 的 L7 治理对它**毫无价值**(TCP 没有 method/path),
> 而 ztunnel 的 L4 代理引入的乐观握手反而制造了新故障。
> **让 `dataplane-mode: none` + NHF 跑,反而更稳。**
> ServiceEntry 留给真正需要 L7 的轨道 B(public SaaS).

### 9.2 变更生效需要重启顺序

```bash
# 1. 改 ServiceEntry / Waypoint 后
kubectl rollout restart deployment/istiod -n istio-system
# 2. 等 istiod ready 且 xDS 推送完成
kubectl rollout status deployment/istiod -n istio-system
# 3. 重启业务 pod,让其 ztunnel 重新拉配置
kubectl rollout restart deployment/app -n ba000000-lex-int
```

> **诊断依据**:`serviceEntry-capabilities-and-use-cases.md` §6.11 记录 Issue #54896
> —— 开启 `PILOT_ENABLE_IP_AUTOALLOCATE` 后流量仍直连公网,根因是**重启顺序错误**.

### 9.3 Standard 发行版用不了的功能(明确边界)

| 功能 | 需要 | 你能用吗 |
|---|---|---|
| `solo-ztunnel-egress` GatewayClass | `-solo` + **Enterprise license** + `enableEgressGateway=true` | ❌ |
| agentgateway waypoint egress | `-solo` + Enterprise | ❌ |
| Advanced mTLS egress(source principal 路由) | `-solo` + Enterprise | ❌ |
| `solo.io/sidecar-skip-waypoint` annotation | `-solo` | ❌ |
| L7 waypoint egress | **上游原生** | ✅ |
| `DYNAMIC_DNS` | 上游原生(1.30) | ✅ |
| `serviceEntryVisibility` mesh config | **1.31+** | ❌(见 §9.4) |

> 即使将来换到 `-solo` 镜像,`solo-ztunnel-egress` 仍需 **Enterprise license**,
> 且是 **Alpha**("not supported for production")。
> **不要因为"升到 solo 了"就去用它。** 本篇方案在 Standard 上是完整的。

### 9.4 `serviceEntryVisibility` 在 1.30 不可用

Istio 1.31 引入 mesh 级 `serviceEntryVisibility`(`PUBLIC` / `NAMESPACE` / `NONE`),
本意是解决 ambient 下 `exportTo` 失效导致的跨 ns 配置污染。

> "When `serviceEntryVisibility` is configured, the ambient data plane always honors it. ...
> A `NAMESPACE` service can be discovered and resolved by workloads in its own namespace. For workloads
> in every other namespace, it is as if the `ServiceEntry` does not exist."
> — [Istio — ServiceEntry visibility](https://istio.io/latest/docs/ambient/usage/serviceentry-visibility/)

> ⚠️ 该页面 "Edit this Page" 链接指向 `release-1.31` 分支。
> **你跑 1.30.3,不要依赖此特性。** 1.30 下的唯一隔离手段是
> `AuthorizationPolicy` 的 `from.source.namespaces` / `principals`(需 waypoint 提供 L7 评估点).

### 9.5 混合集群的 404 陷阱(仅当未来引入 sidecar)

> "In the Solo distribution of Istio 1.30, sidecar-injected clients may get 404 errors after the
> ServiceEntry becomes `WaypointBound`. When a sidecar client is already connected to istiod at the
> time the ServiceEntry's `WaypointBound` status is set, istiod does not push the corrected route to
> the already-connected proxy. The sidecar keeps a stale config and 404s until its proxy reconnects.
> **Roll the sidecar client Deployments** after you confirm `WaypointBound` status. This issue is
> resolved in 1.31."
> — [Solo 1.30.x — L4 ztunnel-native egress](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/ztunnel-egress/)

→ case-lex 里 `lex-gw-int` 是 **sidecar 模式 Gateway**(`gatewayClassName: istio`).
若给它加访问外部域名的 ServiceEntry,**可能撞上这个 404**。
**排查时先看 `WaypointBound` 状态,再 rollout 相关 sidecar Deployment。**

---

## 10. ★ "不能绕过 waypoint" —— 强制出口的真实现状

### 10.1 官方承认的绕过场景

> "The `istio.io/use-waypoint` label records your intent to send traffic through a waypoint, but
> **on its own it does not guarantee that this happens**. ztunnel routes traffic directly to the
> destination, rather than failing the request, when:
> - the named waypoint does not exist or has no address; or
> - the traffic type does not match the traffic the waypoint handles; for example, a request sent
>   directly to a workload (a pod or VM IP) when the waypoint only handles service traffic, which is
>   the default.
>
> In either case, **any Layer 7 policy that the waypoint would have enforced never takes effect**,
> and traffic flows as though no waypoint were configured."
> — [Istio — Configure waypoint proxies §Require traffic to traverse the waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/#require-waypoint)

### 10.2 官方的解法与它对 ServiceEntry 目标的局限

官方给的解法是 `require-waypoint` AuthorizationPolicy,**用 workload `selector`**,由 ztunnel 在 L4 强制:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: require-waypoint
  namespace: default
spec:
  selector:                      # ★ workload selector,不是 targetRef
    matchLabels:
      app: reviews
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - cluster.local/ns/default/sa/reviews-svc-waypoint
```

> "This policy uses a **workload selector rather than a targetRef**, so it is enforced at **Layer 4
> by ztunnel**. It therefore takes effect in both bypass cases: when the waypoint is unavailable, and
> when a client dials the workload directly."
> — 同上

> ⚠️ **对 ServiceEntry 目标不适用**:
> 外部服务**没有 workload**(没有 pod label 可以 select),`selector` 无从下手。
> `targetRefs: [ServiceEntry]` 是 waypoint 的 **L7** 绑定点,waypoint 挂了它就不评估.
>
> **所以:ServiceEntry 目标的"强制经 waypoint"在 1.30 ambient 下没有官方 L4 兜底机制。**

### 10.3 ★★ 关键修正:NP-3 就是那道防线

这是 v2 相对 v1 最重要的认知修正:

```
┌──────────────────────────────────────────────────────────────────────┐
│  ServiceEntry 目标的强制出口,靠 NetPol 而非 AuthZ:                     │
│                                                                       │
│   业务 pod  ──✗──▶  真实公网 IP:443          (NP-3 已 DENY) ✅         │
│      │                                                                │
│      └──✓──▶  egress-waypoint ClusterIP:15008  (NP-3 规则 2 放行)    │
│                        │                                              │
│                        └─✓─▶ 真实公网 IP:443  (waypoint 的 NP 放行)   │
│                                                                       │
│   ⇒ NP-3 已经 DENY 了公网段,waypoint 就是唯一路径。                    │
│     waypoint 挂掉时:业务 pod 拿不到流量(而非静默 passthrough)。       │
└──────────────────────────────────────────────────────────────────────┘
```

> **v1 说"必须修 NP-3 才能防绕过"是错的。**
>
> 正确的理解是:
> - NP-3 的 `128.0.0.0/2` **已经**把公网段排除在外 → **防线本来就存在**
> - ServiceEntry 的工作是**新增**通往 egress waypoint 的合法通道
> - **不是**去"修改"NP-3
>
> → **你不应该动 NP-3。** 唯一需要确认的是:业务 pod 到 egress waypoint 的 HBONE 路径
> (走 ClusterIP,在 `10.0.0.0/8` service CIDR 内)是否被 NP-3 规则 2 放行 —— **默认是放行的**。

**唯一的真实风险**(v1 的 R2 依然有效,但方向相反):

| 风险 | 表现 | 缓解 |
|---|---|---|
| **有人把 NP-3 改成 `0.0.0.0/0`** | 业务 pod 可直连公网 → 绕过 waypoint | §11.3 第 6 步安全断言纳入 CI / 定期巡检 |

```yaml
# 确认业务 pod → egress waypoint 的 HBONE 路径已通
# (这条是"新增"而非"修改",符合 NetPol 并集语义)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-egress-via-egress-waypoint
  namespace: ba000000-lex-int
  labels:
    gateway-access: ba000000-lex-int
spec:
  podSelector:
    matchLabels:
      app: app                 # ★ 只针对业务 pod
  policyTypes: [Egress]
  egress:
    # ✅ 轨道 B:只允许经 egress waypoint 的 HBONE
    - to:
        - namespaceSelector:
            matchLabels:
              gateway-access: platform-egress
          podSelector:
            matchLabels:
              gateway.networking.k8s.io/gateway-name: egress-waypoint
      ports:
        - protocol: TCP
          port: 15008
```

> ⚠️ **NetPol 是并集(additive)语义**。
> 这条规则**只增加**允许项,**不会减去** NP-3 已允许的 `128.0.0.0/2`。
> **这正是你要的** —— 轨道 A 保持"能 L3 走通就默认不控",轨道 B 走 waypoint。

### 10.4 三层兜底对照

| 防线 | 机制 | 防什么 | 绕过可能性 |
|---|---|---|---|
| 第 1 道 | **NP-1 + NP-3**(已存在) | 业务 pod 直连公网 | ⭐⭐⭐⭐ 最强(netns 级,应用无法绕过) |
| 第 2 道 | egress waypoint 上的 `AuthorizationPolicy` | 未授权 namespace / SA / method / path | ⭐⭐ waypoint 挂掉则失效 |
| 第 3 道 | PA STRICT + ztunnel mTLS | 伪装成 mesh 成员 | ⭐⭐⭐ 中等 |
| 第 4 道 | **GCE VM Squid ACL**(若保留方案 A/B) | 域名合规 + 业务时间 | ⭐⭐⭐⭐ 不在 mesh 内,ztunnel 管不到 |

> **第 4 道的价值**:保留 GCE VM Squid 意味着**即使 Istio 侧全部失效**,
> 仍有公司级的 ACL 兜底。这是**纵深防御**,不是冗余。

---

## 11. 完整落地清单

### 11.1 文件清单

> 新增到 `case-lex/`,**不改动**现有 00–09 文件.

| 文件 | 资源 | 说明 |
|---|---|---|
| `10-egress-namespace.yaml` | 1 NS | `istio-egress` + ambient + use-waypoint |
| `10-egress-waypoint.yaml` | 1 Gateway + 1 PDB | egress waypoint |
| `10-egress-netpol.yaml` | 3 NP | egress ns 的 L4 边界(最小放行) |
| `11-serviceentry-microsoft-login.yaml` | 1 SE + 1 AuthZ | 单域名白名单 |
| `11-serviceentry-tls-origin.yaml` | 1 SE + 1 DR | 变体:TLS origination |
| `12-require-waypoint-netpol.yaml` | 1 NP | 业务 pod → waypoint 的合法通道(§10.3) |
| `12-egress-audit-log.md` | — | ztunnel / waypoint 日志字段说明 |

### 11.2 Apply 顺序

```bash
# ====== 前置(平台侧,不在本目录)======
# 1. 确认 istiod 开了 IP autoallocate
kubectl get configmap istio -n istio-system -o yaml | grep IP_AUTOALLOCATE
# 2. ★ 确认 NP-3 的 128/2 是公司策略需要 —— 不要动它
# 3. 统计现有 Squid 日志,得出真实域名清单(§6.3.1)

# ====== 平台层(新增)======
kubectl apply -f 10-egress-namespace.yaml
kubectl apply -f 10-egress-waypoint.yaml
kubectl apply -f 10-egress-netpol.yaml
kubectl -n istio-egress rollout status deployment/egress-waypoint

# ====== 业务层(按需,每加一个域名 = 1 组)======
kubectl apply -f 11-serviceentry-microsoft-login.yaml
kubectl apply -f 11-serviceentry-tls-origin.yaml

# ====== 打通通道 ======
kubectl apply -f 12-require-waypoint-netpol.yaml
```

### 11.3 端到端验证脚本

```bash
#!/usr/bin/env bash
# verify-egress.sh —— 放在 case-lex/ 下,逐条跑,任何一条 FAIL 都停下来查
set -uo pipefail
NS=ba000000-lex-int
EGRESS_NS=istio-egress
SE=microsoft-login

echo "### 1. ServiceEntry 绑定状态"
kubectl get serviceentry "$SE" -n "$EGRESS_NS" -o jsonpath='{.status.conditions}' | jq .
# PASS: 存在 type=istio.io/WaypointBound, status="True"

echo "### 2. VIP 已分配"
VIP=$(kubectl get serviceentry "$SE" -n "$EGRESS_NS" -o jsonpath='{.status.addresses[0].value}')
echo "VIP=$VIP"; [ -n "$VIP" ] && echo PASS || echo FAIL

echo "### 3. 应用侧 DNS 解析到 VIP"
kubectl exec -n "$NS" deploy/app -- getent hosts microsoft.intra.aibang.local
# PASS: 返回 $VIP

echo "### 4. ztunnel 侧确认走 waypoint"
kubectl logs -n istio-system -l app=ztunnel --tail=500 | grep 'egress-waypoint'
# PASS: dst.workload="egress-waypoint-xxx"  且  dst.hbone_addr=$VIP:443

echo "### 5. waypoint 侧确认转发出去"
kubectl exec -n "$EGRESS_NS" deploy/egress-waypoint -c istio-proxy -- \
  pilot-agent request GET stats | grep -q 'upstream_rq_total.*[1-9]' && echo PASS || echo FAIL

echo "### 6. ★ 安全断言:waypoint 挂掉时不应静默放行"
kubectl scale deploy/egress-waypoint -n "$EGRESS_NS" --replicas=0
sleep 20
kubectl exec -n "$NS" deploy/app -- \
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 https://microsoft.intra.aibang.local/
# PASS: 连接失败(000/超时)—— 说明 NP-3 的 deny 基线生效,没有 passthrough 绕过
# FAIL: 返回 200 —— ⚠️ 说明业务 pod 能直连公网,NP-3 被改坏了
kubectl scale deploy/egress-waypoint -n "$EGRESS_NS" --replicas=2
```

> **第 6 步是本方案的安全核心断言。** 官方明确 ztunnel 在 waypoint 不可用时会
> passthrough 直连(§10.1)。**唯一能让它失败而不是放行的,就是 NetPol。**
>
> **对你的场景的具体含义**:NP-3 已经 DENY 了公网段,所以这个断言**理论上应该通过**。
> 但必须实测 —— 一旦 NP-3 被误改成 `0.0.0.0/0`,这个防线就塌了。
> **建议纳入 CI 或定期巡检。**

### 11.4 审计可观测性

```bash
# ztunnel 的 L4 access log
kubectl logs -n istio-system -l app=ztunnel -f | grep 'direction="outbound"'

# 关键字段解读
#   src.identity="spiffe://.../ns/ba000000-lex-int/sa/app-ksa"   ← 谁发的
#   dst.hbone_addr=240.240.0.2:443                                 ← 命中哪个 ServiceEntry
#   dst.service="microsoft.intra.aibang.local"                    ← 目标(L7 才有)
#   dst.identity="spiffe://.../ns/istio-egress/sa/egress-waypoint" ← 经过了 egress waypoint
```

> **这是 case-lex 现有配置里完全缺失的能力** —— 目前只能从 ztunnel 日志看到
> `dst.addr=128.171.x.x`(纯 IP),**无法回答"哪个租户访问了哪个域名"**。
> 加上 ServiceEntry + waypoint 后才有 `dst.service` 字段.

---

## 12. 风险清单

| # | 风险 | 等级 | 缓解 |
|---|---|---|---|
| R1 | **微软/大厂 SaaS 的 IP 段不可持续维护**(§6.3.1) | 🔴 高 | **NetPol 只管端口级边界,域名白名单交给 AuthZ** |
| R2 | 有人把 NP-3 改成 `0.0.0.0/0` → 公网直连防线塌 | 🔴 高 | §11.3 第 6 步安全断言纳入 CI |
| R3 | SCC 多子网 SQL 乐观握手(ztunnel#1456) | 🟠 中 | §9.1 方案 A:`dataplane-mode: none` |
| R4 | waypoint 挂掉 → ztunnel passthrough 静默绕过 L7 | 🟠 中 | **靠 NP-1 + NP-3 兜底**(§10.3)—— 你的配置已满足 |
| R5 | Squid ACL 依赖源 IP,若入 mesh 语义被破坏 | 🟠 中 | 方案 A/C 必须 `dataplane-mode: none`(§7.4) |
| R6 | `operation.hosts` 写成 Cloud DNS 别名而非真实域名 | 🟡 低 | §5.3 / §6.4 已标注;测试时验证 |
| R7 | `exportTo` 失效 → ServiceEntry 全局可见 | 🟡 低 | AuthZ `from.source.namespaces` 收口 |
| R8 | 1.30.3 无 `serviceEntryVisibility` | 🟡 低 | 用 AuthZ;1.31 升级后重评 |
| R9 | sidecar 网关 404(WaypointBound 后不重推) | 🟢 低 | rollout 相关 sidecar Deployment |
| R10 | distroless 无 shell → 无法进容器排障 | 🟢 低 | `istioctl` + `kubectl logs` + `kubectl cp` |
| R11 | Standard 发行版无 n-4 CVE 回补 | 🟡 低 | 跟进社区 patch;或评估切 `-solo-distroless` |
| R12 | `DYNAMIC_DNS` wildcard 覆盖整个域 | 🟡 低 | 优先精确 host;必须用时 `operation.hosts` 收窄 |

---

## 13. 待验证项 / 建议下一步

### 13.1 本篇无法证实的部分(诚实标注)

| 项 | 为什么没验证 | 怎么验 |
|---|---|---|
| 集群上 `PILOT_ENABLE_IP_AUTOALLOCATE` 实际值 | 无集群访问 | `kubectl get cm istio -n istio-system -o yaml \| grep IP_AUTOALLOCATE` |
| **真实需要的域名清单** | 需访问现有 Squid 日志 | **§6.3.1 方法 2** —— ★ 这是 Phase 0 的必做项 |
| 微软各域名的**真实 IP 段** | CDN 动态变化 | §6.3.1 方法 1;**但结论是不该依赖它**(R1) |
| HBONE 源地址形态(NetPol 匹配用) | 依赖 ztunnel 版本 | ztunnel 日志看 `src.addr` / `src.workload` |
| `DYNAMIC_DNS` 在 ztunnel 侧的实际解析行为 | 1.30 较新特性 | 配 `*.example.com` → `istioctl ztunnel-config service` |
| `dataplane-mode: none` 对 SCC 的实际效果 | 无 SCC 环境 | 建测试 SCC → 挂 SE → 压测 |
| `FIRST_HEALTHY_RACE` 在 1.30.3 是否生效 | PR 处于 needs-rebase | 打 annotation → `kubectl describe se` |

### 13.2 关于是否升级到 `-solo` 的建议

当前 `1.30.3-distroless`(Standard)的代价是**没有 n-4 CVE 回补**。

> "Solo Enterprise for Istio offers `n-4` security patching support **only with a `-solo`
> distribution of Istio**, not community Istio versions."
> — [Solo 1.30.x — Supported versions](https://docs.solo.io/istio/1.30.x/ambient/about/images/versions/)

**如果只为 n-4 而切 `-solo`,本篇方案完全不受影响** ——
§5–§11 用到的全是上游 Istio 原生能力(`ServiceEntry` / `use-waypoint` / waypoint / AuthZ / DR),
**没有一条依赖 Solo 专有特性**。切换只需改 Helm values 的 image tag.

**不切也能用。** 切的好处是安全补丁窗口,坏处是需要 Solo license(以及 license 的合规审查成本).
但注意:切到 `-solo` 后,`solo-ztunnel-egress` 仍需 **Enterprise license** 且是 **Alpha**,
**不要因为"升到 solo 了"就用它。**

### 13.3 建议的推进顺序

```
Phase 0(前置,零风险)—— ★ 这一步决定后续所有工作量
  ├─ 确认 istiod IP autoallocate 开关
  ├─ 确认 NP-3 的 128/2 是公司策略需要(不动它)
  └─ ★ 从现有 GKE Squid access.log 统计真实需要的域名清单(§6.3.1 方法 2)

Phase 1(只读验证,零风险)
  ├─ 起 istio-egress ns + waypoint,先不绑任何流量
  └─ 验证 waypoint ready / ztunnel 能拿到配置

Phase 2(单域名影子验证)
  ├─ 1 个 ServiceEntry(如 microsoft-login),NetPol 用 §6.3.1 策略②
  ├─ waypoint 侧先只开审计,不开拦截
  ├─ 对比 waypoint 日志 vs Squid 日志
  └─ 跑 1~2 周确认无遗漏

Phase 3(收口 —— 关键,做完才算"强制")
  ├─ waypoint 上 AuthZ 拦截(仅放行 SE 白名单)
  └─ 复跑 §11.3 第 6 步安全断言

Phase 4(评估是否下线 GKE Squid 第一级)
  ├─ 无固定出口 IP 要求 → GCE VM Squid 可完全退役
  └─ 有固定出口 IP 要求 → 降级为"仅固定出口 IP"的二跳中转
```

---

## 14. 权威证据

### 14.1 Solo 官方(与你的运行版本严格对齐)

| 主题 | 链接 | 本文引用的关键原话 |
|---|---|---|
| **发行版定义**(Standard/Solo × FIPS/Distroless) | [images/overview](https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/) | "Standard: A copy of the community Istio distribution... **You must use the `solo` image to use these features.**"; "Distroless: An image that is tagged with `distroless` is a slimmed down distribution with the minimum set of binary dependencies" |
| **版本支持矩阵 + 已知问题** | [images/versions](https://docs.solo.io/istio/1.30.x/ambient/about/images/versions/) | "n-4 security patching support **only with a `-solo` distribution**"; **多子网 SQL 失败(ztunnel#1456)** + `dataplane-mode: none` 变通 + `ambient.istio.io/connect-strategy: FIRST_HEALTHY_RACE`(istio#59083,"future Solo release") |
| **L7 waypoint egress**(本篇主方案) | [traffic-management/egress/egress](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/egress/) | "**Wildcard hostnames are not supported in ServiceEntry resources used with egress waypoints.**"; DNS capture + `PILOT_ENABLE_IP_AUTOALLOCATE` 前置;`WaypointBound` 状态验证;`targetPort: 443` + DR `SIMPLE` 做 TLS origination;ztunnel access log 样例含 `dst.service` / `dst.hbone_addr` |
| **L4 ztunnel-native egress**(Standard 不可用) | [traffic-management/egress/ztunnel-egress](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/ztunnel-egress/) | "This feature requires... **an Enterprise-level license**"; "Alpha features... **not supported for production**"; sidecar 404 陷阱("resolved in 1.31") |
| **sidecar → ambient egress 迁移差异** | [traffic-management/egress/migrate-sidecar](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/egress/migrate-sidecar/) | "**In an ambient mesh, ztunnel does not read `outboundTrafficPolicy`.**"; "**In ambient mode, `exportTo` is ignored.**... Namespace-scoped access control must be expressed through `AuthorizationPolicy`" |

### 14.2 上游 Istio(1.30 行为基准 —— 你跑的是社区代码路径)

| 主题 | 链接 | 关键原话 |
|---|---|---|
| **ServiceEntry 字段全表** | [reference/config/networking/service-entry](https://istio.io/latest/docs/reference/config/networking/service-entry/) | "**NOTE 3: Ztunnel and Waypoint proxies do not support wildcard hosts.**"; "**Note: Ztunnel and Waypoint proxies not support this field [`exportTo`] and will read it at `*`.**"; `addresses` 空时"the sidecar will behave as a simple TCP proxy"; `DYNAMIC_DNS` 定义("only `MESH_EXTERNAL` in ambient mode (bound to a waypoint)"); `protocol` "TLS implies... without terminating the TLS connection" |
| **Ambient egress gateways** | [ambient/usage/egress-gateway](https://istio.io/latest/docs/ambient/usage/egress-gateway/) | "In ambient mode, **a waypoint proxy naturally acts as an egress gateway**... no extra routing rules required"; "Enrolling a namespace routes traffic through the waypoint **but does not prevent direct paths if the waypoint is unavailable**... add an AuthorizationPolicy that allows only the waypoint's identity, **enforced at L4 by ztunnel**" |
| **waypoint 强制经过** | [ambient/usage/waypoint#require-waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/#require-waypoint) | "**on its own it does not guarantee that this happens**. ztunnel routes traffic directly to the destination... the named waypoint does not exist or has no address"; 解法"uses a **workload selector rather than a targetRef**, so it is enforced at Layer 4 by ztunnel" |
| **L4 策略与 ztunnel fail-safe** | [ambient/usage/l4-policy](https://istio.io/latest/docs/ambient/usage/l4-policy/) | "The ztunnel cannot enforce L7 policies. **If a policy with rules matching L7 attributes is targeted such that it will be enforced by a receiving ztunnel, it will fail safe by becoming a `DENY` policy.**"; "Waypoint proxies **do not impersonate the identity of the source workload**... the ideal place to enforce policy shifts" |
| **L7 功能与 waypoint** | [ambient/usage/l7-features](https://istio.io/latest/docs/ambient/usage/l7-features/) | "A policy attached to a waypoint is only enforced for traffic that actually reaches the waypoint. Traffic can bypass the waypoint... To require that traffic traverses the waypoint, pair the waypoint policy with an `AuthorizationPolicy` enforced by ztunnel" |
| **DNS Proxying / auto-allocation** | [ops/configuration/traffic-management/dns-proxy](https://istio.io/latest/docs/ops/configuration/traffic-management/dns-proxy/) | "In ambient mode, **DNS proxying is required** to enable resolution of `ServiceEntry` addresses, **especially in the case of sending egress traffic to waypoints**"; "Istio will automatically allocate non-routable VIPs (from the **Class E subnet**)... as long as they do not use a wildcard host" |
| **使用外部 HTTPS 代理**(§7.4 方案 A 的官方依据) | [tasks/traffic-management/egress/http-proxy](https://istio.io/latest/docs/tasks/traffic-management/egress/http-proxy/) | "**Define a TCP (not HTTP!) Service Entry for the HTTPS proxy.** Although applications use the HTTP CONNECT method... you must configure the proxy for TCP traffic"; "**you must not create service entries for the external services you access through the external proxy**... Istio is not aware of the fact that the external proxy forwards the requests further" |
| **DYNAMIC_DNS / wildcard egress** | [blog/2026/egress-dynamic-dns](https://istio.io/latest/blog/2026/egress-dynamic-dns/) | wildcard + DYNAMIC_DNS → Envoy **dynamic forward proxy (DFP)** cluster;ambient 侧给 ServiceEntry 打 `istio.io/use-waypoint` 的官方示例(**位于 `release-1.30` 分支**) |
| **ServiceEntry visibility**(1.31+) | [ambient/usage/serviceentry-visibility](https://istio.io/latest/docs/ambient/usage/serviceentry-visibility/) | `PUBLIC` / `NAMESPACE` / `NONE` 三态;**"Edit this Page" 指向 `release-1.31`** → 1.30 不可用 |
| **ztunnel 排障 wiki** | [wiki/Troubleshooting-Istio-Ambient](https://github.com/istio/istio/wiki/Troubleshooting-Istio-Ambient) | "Scenario: ztunnel is not sending egress traffic to waypoints"(DNS proxy 官方推荐的排查入口) |

### 14.3 case-lex 内部文档 + 本地实证

| 文档 | 本篇引用的内容 |
|---|---|
| `02-network-policies.yaml` | NP-1 ~ NP-9 全部 9 条;`128.0.0.0/2` + `10.0.0.0/8` 的 `except` 清单 |
| `03-mesh-security.yaml` | 1 PA + 2 AuthZ;`targetRefs` vs `selector` 的用法 |
| `00-namespace-ba000000-lex-int.yaml` | ns labels(`businessId: ba000000` 等) |
| `../21-solo-ambient-egress.md` | Ambient egress 架构探索(Internal NHF + Public L7 Waypoint) |
| `../08-ambient-networkpolicy.md` | 15008 必须显式放行;kubelet 探针走 link-local |
| `/Users/lex/git/gcp/linux/networking/nhf-flow-enhance.html` | NHF 出网机制全景(L3 侧) |
| `/Users/lex/git/knowledge/gcp/asm/serviceEntry-capabilities-and-use-cases.md` | ServiceEntry 能力矩阵(字段全表) |
| **本地实证**:`128.0.0.0/2` 实算 | Python `ipaddress`:= `128.0.0.0`–`191.255.255.255`;扣 except 后剩 19 段,合计 **24.9741%** of IPv4。**该结果证明公网段(34.x/52.x/1.1.1.1)被 DENY** —— 即 deny 基线已生效 |

---

## 15. 附录 —— v1 → v2 修订对照(完整记录)

保留修订痕迹,便于追溯判断的变化.

| 章节 | v1 说法 | v2 说法 | 修订原因 |
|---|---|---|---|
| §2(NP-3 CIDR) | "🔴 阻塞级发现:NP-3 算错了" | "✅ 是设计意图,不要改" | Lex 澄清:公司申请的公网段恰在 128/2 内 |
| §6.3(waypoint NetPol) | `0.0.0.0/0` + except 私网 | **只放白名单域名的实际落地网段** | 默认 deny 是策略,waypoint 也应最小放行 |
| §4(职责划分) | "L3/L4 粗放 + L7 精白名单 是正确职责划分" | "内部 DRN 能 L3 走通就默认不控;public 才按域名控" | 公司策略是**两轨制**,不是单一原则 |
| §2(现状盘点) | "出向 L7 完全空白" | "L4 deny 基线已建立并生效,缺 L7 开口" | NP-1 + NP-3 已在执行 deny all public |
| §10(强制出口) | "必须修 NP-3 才能防绕过" | "**NP-3 已经就是那道防线,别动它**" | v1 误判导致结论反向 |
| §5(命名策略) | 3 个通用模板 | 保留,但**改用 Cloud DNS 别名 + 真实域名双名策略**(§5.3) | 对齐你的现有架构,降低迁移成本 |
| 新增 §7 | 无 | **Squid 两级代理在 ambient 下的三方案对比** | v1 完全没考虑你现有的 Squid 链路 |
| 新增 §2.1/2.2 | 无 | **公司两轨策略 + 现行两图解析** | v1 缺少业务前提 |
| 新增 §6.3.1 | 无 | **如何查白名单域名的真实网段 + 为什么不该依赖它** | v1 假设 IP 白名单可持续,实际不可持续 |
| 新增 R1 | 无 | **大厂 SaaS IP 段不可持续维护** | v1 的严重疏漏 |
| 删除 §6(形态 A 同 ns) | 独立成章 | **降级为 §6.1 的一行对比** | 独立 ns 明显更优(避免继承 NP-3 耦合) |

---

*Generated by architect-gcp Bot —— 探索文档,未部署。*
*v2 基于 Lex 补充的业务背景(两轨 egress 策略 + Squid 两级代理架构)重写。*
*本文不修改 `case-lex/` 下任何现有文件。*
*所有 Istio 行为断言均已对照 Solo 1.30.x 官方文档 + 上游 Istio reference,引用见 §14。*
*所有 CIDR 结论均由 Python `ipaddress` 实算得出,非估算。*
