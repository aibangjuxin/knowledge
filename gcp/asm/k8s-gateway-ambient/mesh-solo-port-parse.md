# mesh-solo-port-parse.md — Istio Ambient / Solo Mesh 全端口对照表

> **作者**: architect-gcp Bot
> **日期**: 2026-09-25
> **范围**: Istio ambient mesh + Solo Istio 1.30+ 全端口清单 + 在 NetworkPolicy 中的角色
> **触发**: `grep -rnE '\b15[0-9]{3}\b' /Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/` 拿到的端口,加上官方文档补全
> **来源**:
>   - ztunnel 官方 ARCHITECTURE.md (`github.com/istio/ztunnel`)
>   - Istio 官方 Application Requirements (`istio.io/latest/docs/ops/deployment/application-requirements/`)
>   - Istio Ambient Architecture (`istio.io/latest/docs/ambient/architecture/traffic-redirection/`)
>   - Tetrate blog 端口详解 (`tetrate.io/blog/istio-component-ports-and-functions-in-detail`)
>   - 本目录 22-ztunnel-mtls-and-cert-rotation.html / 09-ztunnel-redirection-app-compat.md / ztunnel-l4-mtls.md

---

## 0. TL;DR — 一句话总结

| 组件 | 端口范围 | 用途分类 | 是否需要 NetworkPolicy allow |
|---|---|---|---|
| **ztunnel** (节点级 Rust 代理) | 15001 / 15006 / 15008 / 15053 / 15080 / 15000 / 15020 / 15021 | L4 mesh 流量拦截 + metrics | **15008 必须** (HBONE 入口) |
| **waypoint** (per-ns envoy) | 15008 + 业务端口 | L7 mesh 拦截 (HTTPRoute / AuthZ) | **15008 必须** (HBONE 入口) |
| **Istiod** (控制面) | 15010 / 15012 / 15014 / 15017 / 8080 / 443 | xDS + CA + webhook + metrics | **15012 / 15017 必须** (业务 pod / waypoint pod 调) |
| **Envoy** (sidecar / ingress) | 15000 / 15020 / 15021 / 15090 / 80 / 443 / 8443 | admin + health + metrics + 数据面 | 80/443 看场景 |
| **kubelet** | 169.254.7.127/32 (link-local IP) | ambient 健康探针 (不是端口) | **必须** allow |

---

## 1. ztunnel 端口(节点级 ambient L4 代理)

ztunnel 是 ambient 模式核心 — 节点级 Rust 进程,在 pod 的 network namespace 里 bind 几个 socket,通过 iptables redirect 拦截进出 pod 的流量。

| Port | Protocol | Direction | Purpose | Pod NetNS Bound | NP 必须 allow? | 严格定义 |
|------|----------|-----------|---------|-----------------|----------------|----------|
| **15001** | TCP | Egress | Pod 出站流量捕获 (iptables REDIRECT → 127.0.0.1:15001) | ✅ Yes | ⭐ Optional (iptables redirect 通常不需要 explicit allow) | "All traffic egressing a pod in the mesh should be redirected to the node-local ztunnel on port 15001." — ztunnel ARCHITECTURE.md |
| **15006** | TCP | Ingress (plaintext) | 入站明文捕获 (PERMISSIVE 模式或 mesh 外调用方) | ✅ Yes | ⭐ Optional | "Traffic entering a pod that is not transmitted over HBONE (i.e. destination port != 15008) is handled by the 'inbound passthrough' code path, on ztunnel's port 15006." — ztunnel ARCHITECTURE.md |
| **15008** | TCP | Ingress (HBONE) | **入站 HBONE 隧道入口 (mTLS over HTTP/2 CONNECT)** | ✅ Yes | ✅ **MUST allow** (若被 NP 拦截, mesh 流量全断) | "All traffic ingressing a pod on port 15008 in the mesh is assumed to be HBONE, and should be redirected to the node-local ztunnel on port 15008." — ztunnel ARCHITECTURE.md |
| **15053** | UDP | Egress (DNS) | Pod 出站 DNS 捕获 (`ISTIO_META_DNS_CAPTURE=true` 时启用) | ✅ Yes | ⭐ Optional | "Pod outbound DNS traffic capture" — ztunnel ARCHITECTURE.md |
| **15080** | TCP | Egress (socks5) | Pod 出站 SOCKS5 代理 (用于 tcp proxy / debug) | ✅ Yes | ⭐ Optional | "Pod outbound socks5 traffic" — ztunnel ARCHITECTURE.md |
| **15000** | TCP | Admin (localhost) | ztunnel admin interface (commands/diagnostics) | ❌ No (loopback only) | ❌ No | "Admin (Admin thread) (Localhost)" — ztunnel ARCHITECTURE.md |
| **15020** | HTTP | Metrics | Prometheus scrape 端点 (`/stats`) | ❌ No | ⭐ Optional | "Metrics (Admin thread)" — ztunnel ARCHITECTURE.md |
| **15021** | HTTP | Health | readiness / liveness probe (ztunnel pod 自身) | ❌ No | ⭐ Optional | "Readiness" — ztunnel ARCHITECTURE.md |

### 1.1 ztunnel 数据流核心(来自 ztunnel 官方文档)

```
Pod 发出 TCP → pod 内 iptables (ISTIO_OUTPUT) → 127.0.0.1:15001 (ztunnel outbound)
Pod 接收 TCP → pod 内 iptables (ISTIO_PRERT)
    ├── dst port == 15008 → TPROXY 0.0.0.0:15008 (HBONE tunnel 入口)
    └── dst port != 15008 → TPROXY 0.0.0.0:15006 (plaintext passthrough)
```

**关键观察**:
- 15001 / 15006 / 15008 / 15053 / 15080 都是 **Pod 内 iptables redirect 入口**,物理上 ztunnel 在 pod 的 network namespace bind 这些 socket
- 业务容器**不应该 listen 这些端口**(端口冲突,启动失败)
- 15008 是**唯一需要 NetworkPolicy 显式 allow** 的 ztunnel 端口(其他在 pod 内自动被 iptables 处理)

---

## 2. waypoint 端口(per-ns ambient L7 envoy)

waypoint 是 K8s Gateway API Gateway 资源, gatewayClassName: istio-waypoint,istio controller 自动生成 envoy Deployment。

| Port | Protocol | Purpose | NP 必须 allow? | 严格定义 |
|------|----------|---------|----------------|----------|
| **15008** | TCP (HBONE) | **入站 HBONE 隧道入口** (从 ztunnel 收到) | ✅ **MUST allow** | "waypoint listens on port 15008 for HBONE connections from ztunnel." — Istio Ambient docs |
| 业务端口 (80/8080/8443/9090 等) | TCP | L7 拦截处理后转发到目标 Service | ✅ by NP-8 (same ns) | 由用户 HTTPRoute.backendRefs 决定 |
| 15090 / 15020 / 15021 | HTTP | envoy admin / metrics / health | Optional (跟 envoy 同) | 跟 ingress Gateway 一致 |

### 2.1 waypoint 跟 ingress Gateway 的端口对比

| 维度 | waypoint | ingress Gateway |
|---|---|---|
| **gatewayClassName** | `istio-waypoint` | `istio` |
| **数据面模式** | ambient (ztunnel 转) | sidecar (envoy in pod) |
| **HBONE 端口** | 15008 (从 ztunnel 接) | 不 listen 15008 (sidecar 模式) |
| **业务端口** | 不 listen (envoy 收到 L7 处理后**转发**到 Service) | listen (TLS Terminate + 路由) |
| **mTLS 入口** | HBONE mTLS (envoy → envoy) | TLS 终止 (envoy 处理 client cert) |
| **mTLS 出口** | HBONE (再 encrypt 到下一跳 ztunnel) | mTLS 到 ztunnel (经 waypoint) |

---

## 3. Istiod 端口(控制面)

istiod 是 Istio 控制面进程,在 `istio-system` ns 里跑,所有 mesh 组件都连它。

| Port | Protocol | Purpose | NP 必须 allow? | 严格定义 |
|------|----------|---------|----------------|----------|
| **15010** | GRPC (Plaintext) | XDS + CA services (明文, 仅安全网络) | ⚠️ 不推荐生产 (plaintext) | "XDS and CA services (Plaintext, only for secure networks)" — Istio 官方 |
| **15012** | GRPC (TLS/mTLS) | **XDS + CA services (生产推荐)** | ✅ **MUST allow** (业务 pod / waypoint / ztunnel 都要连) | "XDS and CA services (TLS and mTLS, recommended for production use)" — Istio 官方 |
| **15014** | HTTP | 控制面 metrics (Prometheus) | Optional | "Control plane monitoring" — Istio 官方 |
| **15017** | HTTPS | Webhook 容器端口 (从 443 forward 过来) | ✅ **MUST allow** (validation webhook) | "Webhook container port, forwarded from 443" — Istio 官方 |
| **443** | HTTPS | Webhook 入口 | (同上, 转发到 15017) | Istio 官方 |
| **8080** | HTTP | Debug interface | ❌ No (debug only) | Istio 官方 |

### 3.1 谁连 istiod 什么端口?

| 客户端 | 15010 (xDS plaintext) | **15012** (xDS TLS) | 15014 (metrics) | **15017** (webhook) |
|---|---|---|---|---|
| ztunnel (Rust) | ❌ | ✅ (gRPC CreateCertificate + xDS) | ⚠️ Prometheus 拉 | ❌ |
| waypoint envoy | ❌ | ✅ (xDS 配置下发) | ⚠️ Prometheus 拉 | ❌ |
| ingress Gateway envoy | ❌ | ✅ (xDS) | ⚠️ Prometheus 拉 | ❌ |
| K8s API server (mutating webhook) | ❌ | ❌ | ❌ | ✅ (pod injection) |
| K8s API server (validating webhook) | ❌ | ❌ | ❌ | ✅ (validate policy) |

### 3.2 case-lex/02 NP-4 验证

你原 NP-4 `default-allow-egress-istiod` 配的是:
```yaml
ports:
  - port: 15012     # ✓ xDS
  - port: 15017     # ✓ webhook
  - port: 15021     # ❌ 错! 这是 envoy health check, 不是 istiod 端口
```

**评估**: 15012 ✅ + 15017 ✅,但 15021 是**错的**:
- 15021 是 Envoy / ztunnel 的 health check 端口,不是 istiod 的
- Istio 官方表里 istiod 没列 15021
- 应改为 443 (webhook 入口) 或直接删 15021

→ **建议**: 从 NP-4 的 ports 里**删掉 15021**(或保留作为其他用途,但不要标作 istiod 端口)

---

## 4. Envoy / Sidecar / Ingress Gateway 端口(envoy 标准)

所有 envoy proxy(无论 sidecar 还是 ingress Gateway 还是 waypoint)都用同一套约定端口。

| Port | Protocol | Purpose | NP 必须 allow? | 严格定义 |
|------|----------|---------|----------------|----------|
| **15000** | TCP | Envoy admin (commands/diagnostics) | Optional (loopback) | "Envoy admin port (commands/diagnostics)" — Istio 官方 |
| **15001** | TCP | Envoy outbound | (略,见 §1) | "Envoy Outbound" — Istio 官方 |
| **15006** | TCP | Envoy inbound | (略,见 §1) | "Envoy Inbound" — Istio 官方 |
| **15020** | HTTP | Merged Prometheus telemetry (envoy + istio-agent + app) | Optional (Prometheus 拉) | "Merged Prometheus telemetry from Istio agent, Envoy, and application" — Istio 官方 |
| **15021** | HTTP | Envoy health check (readiness / liveness) | Optional (K8s probe) | "Health checks" — Istio 官方 |
| **15090** | HTTP | Envoy Prometheus telemetry (envoy 原生) | Optional (Prometheus 拉) | "Envoy Prometheus telemetry" — Istio 官方 |
| **80** | TCP | Ingress Gateway HTTP | ✅ by K8s Service / NP | Istio Operator 默认 |
| **443** | TCP | Ingress Gateway HTTPS | ✅ by K8s Service / NP | Istio Operator 默认 |
| **8443** | TCP | Ingress Gateway HTTPS (side-by-side with 443) | ✅ by K8s Service | Istio Operator 默认 |
| **31400** | TCP | Ingress Gateway SNI fallback (legacy) | Optional | Istio Operator 默认 |
| **15443** | TLS | Ingress/Egress GW SNI | Optional | Istio 官方 |

### 4.1 Envoy admin / metrics / health 端口对照

| Envoy 端口 | 内容 | 谁访问 |
|---|---|---|
| 15000 | Envoy admin (raw config dump / stats / clusters / listeners / etc) | 运维 (curl `localhost:15000/...`) |
| 15020 | Istio agent 合并的 metrics (envoy + istio-agent + app process) | Prometheus scrape |
| 15021 | Envoy health (readiness + liveness, K8s probe 目标) | kubelet |
| 15090 | Envoy 原生 Prometheus metrics (subset of 15020) | Prometheus scrape |

### 4.2 Ingress Gateway 标准端口清单 (istio-ingressgateway Deployment)

```yaml
ports:
  - containerPort: 15021  # status port / health
  - containerPort: 8080   # HTTP (mapped to K8s Service port 80)
  - containerPort: 8443   # HTTPS (mapped to K8s Service port 443)
  - containerPort: 31400  # SNI (legacy)
  - containerPort: 15443  # TLS SNI
  - containerPort: 15090  # Envoy Prometheus
```

---

## 5. K8s 业务端口 vs Ambient 端口 — 严格区分

| 类型 | 端口范围 | 谁 listen | 谁访问 |
|---|---|---|---|
| **K8s Service 业务端口** | 80, 443, 8080, 8443, 9090 等 | 业务容器 | 客户端 / waypoint / ingress |
| **Mesh 端口** | 15001, 15006, 15008, 15053, 15080 | ztunnel / waypoint | ztunnel (内部) |
| **Control plane 端口** | 15010, 15012, 15014, 15017 | Istiod | ztunnel / envoy |
| **Envoy admin/metrics** | 15000, 15020, 15021, 15090 | envoy / ztunnel | 运维 / Prometheus / kubelet |
| **Ingress Gateway 端口** | 80, 443, 8443, 31400, 15443 | ingress envoy | LB / 客户端 |
| **kubelet 探针 (NOT 端口, 是 IP)** | 169.254.7.127/32 | kubelet | istio-cni SNAT 探针包 |

---

## 6. case-lex/02-network-policies.yaml 中实际配的端口

按 NP 顺序:

| NP | 配的端口 | 实际对应 mesh 端口 | 评估 |
|---|---|---|---|
| NP-1 | (无规则, default deny) | - | ✅ |
| NP-2 | 53/UDP+TCP | kube-dns | ✅ |
| NP-3 | (CIDR, 无端口限制) | - | ✅ |
| **NP-4** | **15012 / 15017 / 15021** | **15012 istiod xDS, 15017 webhook, 15021 ❌ 错 (envoy health, 不是 istiod)** | ⚠️ **15021 应删** |
| NP-5 | 15008/TCP | waypoint ingress HBONE | ✅ |
| NP-6 | 15008/TCP | waypoint egress HBONE | ✅ |
| NP-7 | 15008/TCP | waypoint ingress from ingress GW | ✅ |
| NP-8 | (无端口限制, 同 ns 全开) | - | ✅ 但**风险**: 15006/15001 也开放 |
| NP-9 | 8080/TCP from 169.254.7.127 | kubelet 探针 | ✅ |

### 6.1 ⚠️ NP-4 错配发现

```yaml
# case-lex/02-network-policies.yaml NP-4 第 184-189 行
ports:
  - protocol: TCP
    port: 15012    # ✅ istiod xDS
  - protocol: TCP
    port: 15017    # ✅ istiod webhook
  - protocol: TCP
    port: 15021    # ❌ 错! 15021 是 envoy health, 不是 istiod 端口
```

**应该**: 删 15021(或确认是给其他目的保留,但不要标作 istiod)。

### 6.2 ⚠️ NP-8 风险

`default-allow-same-namespace` 没限制端口, 业务 pod 可以同 ns 内访问**任何端口**。这包括 15006 (plaintext inbound) / 15001 (outbound) / 15008 (HBONE)。

- **同 ns 内**业务 pod 之间**不应该**走 plaintext 15006 (STRICT 模式会拒绝), 实际只走 15008 (HBONE)
- 但因为 NP-8 没限定, **业务 pod 可以监听任何端口**(包括 mesh 端口 15006/15001)— 这是端口冲突风险
- **建议**: NP-8 应该显式 allow mesh 端口 15008, 其他端口按业务需要另开

---

## 7. NetworkPolicy 必须 allow 的端口清单 (case-lex 多租户视角)

按 traffic flow 顺序:

| # | 流量方向 | 协议 | 源 → 目的 | 必须 allow 的端口 | NP 编号 |
|---|---|---|---|---|---|
| 1 | 业务 pod → kube-dns | UDP+TCP | pod → kube-system/kube-dns | 53 | NP-2 |
| 2 | 业务 pod → istiod | TCP | pod → istio-system/istiod | 15012, ~~15021~~ | NP-4 |
| 3 | waypoint pod → istiod | TCP | waypoint → istio-system/istiod | 15012, ~~15021~~ | NP-4 |
| 4 | 业务 pod → 公网 | TCP | pod → 任意 IP | (无端口限制) | NP-3 |
| 5 | ztunnel (src) → ztunnel (dst) | TCP | node → node | **15008 (HBONE)** | (隐式由 pod 内 iptables + ztunnel 处理,但 NP 层**主机网络命名空间**需要 allow) |
| 6 | ingress GW → waypoint (HBONE) | TCP | ingress GW → waypoint pod | **15008** | NP-7 |
| 7 | waypoint → 业务 pod (HBONE 解密后转) | TCP | waypoint → 业务 pod | 业务端口 + **15008** | NP-6 + NP-8 |
| 8 | 业务 pod ↔ 业务 pod (同 ns) | TCP | pod → pod | (无端口限制) | NP-8 |
| 9 | kubelet → 业务 pod | TCP | kubelet (169.254.7.127/32) → pod | 8080 | NP-9 |

---

## 8. 集群视角的全端口表 (合并自各官方源)

| Port | Protocol | 组件 | 用途 | Pod 内 only | NP allow 必需 |
|------|----------|------|------|-------------|---------------|
| **53** | UDP+TCP | kube-dns | DNS 解析 | ❌ | ✅ (业务 pod 用) |
| **80** | TCP | Ingress GW | HTTP | ❌ | ✅ (场景相关) |
| **443** | TCP | Ingress GW / Istiod | HTTPS / webhook 入口 | ❌ | ✅ |
| 8080 | HTTP | Istiod / 业务 | Debug / 业务 | ❌ | Optional |
| 8443 | HTTPS | Ingress GW | HTTPS (side-by-side with 443) | ❌ | ✅ |
| 15000 | TCP | Envoy admin | admin/diagnostics | Y (loopback) | ❌ |
| **15001** | TCP | ztunnel / Envoy | Pod outbound 捕获 | Y | Optional |
| **15006** | TCP | ztunnel / Envoy | Pod inbound plaintext 捕获 | Y | Optional |
| **15008** | TCP | ztunnel / waypoint / Envoy | **HBONE 隧道 (mesh 关键)** | Y | ✅ **MUST** |
| **15010** | GRPC | Istiod | XDS+CA plaintext | ❌ | (生产不用) |
| **15012** | GRPC | Istiod | XDS+CA TLS | ❌ | ✅ (ztunnel/envoy 调) |
| **15014** | HTTP | Istiod | Control plane monitoring | ❌ | Optional |
| **15017** | HTTPS | Istiod | Webhook container | ❌ | ✅ |
| **15020** | HTTP | Envoy / ztunnel | Merged Prometheus telemetry | ❌ | Optional |
| **15021** | HTTP | Envoy / ztunnel | Health check | ❌ | Optional |
| **15053** | UDP | ztunnel | Pod outbound DNS 捕获 | Y | Optional |
| **15080** | TCP | ztunnel | Pod outbound socks5 | Y | Optional |
| **15090** | HTTP | Envoy | Envoy Prometheus | ❌ | Optional |
| 15443 | TLS | Ingress/Egress GW | SNI | ❌ | Optional |
| 31400 | TCP | Ingress GW | SNI fallback | ❌ | Optional |
| 169.254.7.127/32 | IP | kubelet (via istio-cni SNAT) | kubelet → pod 探针 | - | ✅ (是 IP 不是端口) |

---

## 9. 易错点 / 反向警告

### 9.1 业务容器不要 listen 这些端口

| Port | 谁占 | 业务 listen 后果 |
|---|---|---|
| 15001 | ztunnel outbound | 端口冲突, 启动失败 |
| 15006 | ztunnel inbound plaintext | 端口冲突, 启动失败 |
| 15008 | ztunnel/waypoint HBONE | 端口冲突, 启动失败 |
| 15080 | ztunnel socks5 | 端口冲突, 启动失败 |
| 15021 | Envoy health (waypoint/GW) | 端口冲突 |

**实务**: 业务代码永远不需要 listen 这些端口。调试时 (`nc -l 15001`) 会失败, 可作诊断信号。

### 9.2 STRICT mTLS = 关 15006

`PeerAuthentication mode: STRICT` 下, ztunnel 拒绝 15006 明文入连接, 只接受 15008 HBONE。

**部署顺序陷阱**:
- 部署时必须**先把 mesh 内所有调用方纳管**, **再开 STRICT**
- 否则: 任何不在 ambient mesh 里的调用方都连不上 Runtime — 部署顺序不对会断线
- case-lex 当前配的是 STRICT (见 `03-mesh-security.yaml` line 6: `name: default-strict-mtls`),需要确认所有调用方已纳管

### 9.3 NetworkPolicy 在主机网络命名空间早于 pod 内重定向

NetPol 在主机网络命名空间 (iptables 层) 生效, **早于** pod 内 ztunnel redirect。

**结果**:
- 若 NP 没 allow 15008, **mesh 流量在到达 ztunnel 之前就被 CNI 拦截**
- 这就是为什么 `02-network-policies.yaml` 必须显式 allow 15008 的多个 NP (NP-5/6/7)
- **ztunnel 报错时**, 注意这条消息: `"maybe a NetworkPolicy is blocking HBONE port 15008"` — 这是 ztunnel 自检提示

### 9.4 多个 NetPol 累积(AND, 不是 OR)

K8s NetPol 是**累加的**(additive), 多个 NP 同时作用于 pod 时, **任一 NP allow 就 allow**。

**case-lex 实践**:
- NP-1 (deny all) + NP-5/6/7 (allow 15008) = 业务 pod 可以走 15008
- NP-1 (deny all) + NP-8 (allow same ns) = 业务 pod 同 ns 内任意端口可通
- **叠加效果**: 业务 pod 既能 15008 (HBONE), 又能同 ns 任意端口

---

## 10. 验证命令 (5 条 kubectl)

```bash
# 1. 集群内所有 istiod Service 端口
kubectl -n istio-system get svc istiod -o jsonpath='{.spec.ports}' | jq

# 2. ztunnel pod 实际 listen 端口
kubectl -n istio-system get pods -l app=ztunnel -o name | \
  head -1 | xargs -I{} kubectl -n istio-system exec {} -- ss -ntlp
# 预期: 15001, 15006, 15008, 15020, 15021, 15053, 15080

# 3. waypoint pod 实际 listen 端口
kubectl -n ba000000-lex-int get pods -l gateway.networking.k8s.io/gateway-name=waypoint-int \
  -o name | head -1 | xargs -I{} kubectl -n ba000000-lex-int exec {} -- ss -ntlp
# 预期: 15008 (HBONE) + 15090 (Prometheus) + 15021 (health)

# 4. ingress GW pod 实际 listen 端口
kubectl -n lex-gw-int get pods -o name | \
  xargs -I{} kubectl -n lex-gw-int exec {} -- ss -ntlp
# 预期: 80, 443, 15021, 15090 (无 15006/15001/15008, sidecar 模式不需这些)

# 5. 业务 pod 内 iptables redirect 规则
kubectl -n ba000000-lex-int exec <pod> -- iptables-save | grep -E '1500[0-9]|15053'
# 预期: ISTIO_OUTPUT → REDIRECT to-ports 15001
#        ISTIO_PRERT → TPROXY on-port 15008 (HBONE)
#        ISTIO_PRERT → TPROXY on-port 15006 (plaintext)
```

---

## 11. 一句话总结

> **Istio ambient + Solo mesh 的核心端口 = 3 类**:
> 1. **Mesh 端口** (ztunnel: 15001/15006/15008/15053/15080; waypoint: 15008) — pod 内 iptables redirect 入口, NP 必须 allow 15008
> 2. **Control plane 端口** (istiod: 15012 xDS/CA + 15017 webhook + 15014 metrics) — 业务 pod / waypoint / ztunnel 必连 15012
> 3. **Envoy admin/metrics 端口** (15000/15020/15021/15090) — 运维/Prometheus/kubelet 用
>
> **NetworkPolicy 视角**: **15008 必 allow**(mesh HBONE 入口), **15012 必 allow**(istiod xDS), 其他按需。

---

## 12. 参考链接

### Istio 官方
- [Application Requirements - Ports used by Istio](https://istio.io/latest/docs/ops/deployment/application-requirements/) — 完整端口官方表
- [Ztunnel traffic redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/) — iptables redirect 规则
- [Ambient architecture overview](https://istio.io/latest/docs/ambient/architecture/) — ztunnel / istio-cni / waypoint 关系

### ztunnel 官方 GitHub
- [ztunnel ARCHITECTURE.md](https://github.com/istio/ztunnel/blob/master/ARCHITECTURE.md) — **8 个端口完整表 (15001/15006/15008/15053/15080/15000/15020/15021)**
- [Istio ambient ztunnel.md](https://github.com/istio/istio/blob/master/architecture/ambient/ztunnel.md) — 端口用途 + iptables 规则

### Solo / Tetrate
- [Istio component ports and functions in detail (Tetrate)](https://tetrate.io/blog/istio-component-ports-and-functions-in-detail) — istiod 端口详解
- [How to Configure Istio Gateway with Custom Ports](https://oneuptime.com/blog/post/2026-02-24-how-to-configure-istio-gateway-with-custom-ports/view) — Envoy 端口冲突警告

### K8s NetworkPolicy
- [NetworkPolicy spec](https://kubernetes.io/docs/concepts/services-networking/network-policies/) — podSelector / namespaceSelector / ipBlock 语义

### 同目录
- `case-lex/02-network-policies.yaml` — case-lex 的 9 条 NetPol (含本表 §6 的 NP-4 错配发现)
- `case-lex/analyze-waypoint.md` — waypoint 工作原理 + HA + sizing
- `09-ztunnel-redirection-app-compat.md` — iptables redirect 规则详解
- `22-ztunnel-mtls-and-cert-rotation.html` — ztunnel mTLS + 端口图解
- `ztunnel-l4-mtls.md` — ztunnel L4 mTLS 工作流

---

*Generated by architect-gcp Bot — 2026-09-25.*
*触发: `grep -rnE '\b15[0-9]{3}\b' k8s-gateway-ambient/` 拿到的端口 + 网络检索官方定义补全。*
*全端口表覆盖 5 个组件层 (ztunnel / waypoint / istiod / Envoy / ingress GW)。*