# Jev-explorer-solo-ambient — Ambient 网关接管后的实施细节与风险清单

> **TL;DR**:
> - 上游规划文档 `20-solo-ambient-kong.md` 给出**方案 A**(Kong 在 Mesh 外)和**方案 B**(Kong 也加 Ambient)的迁移路径
> - 本文档用 TypeSafe Jev 模型做**speculative fan-out 风险评估**(13 个问题,并行打分),把方案 B 上生产前必须确认的细节摊开
> - **核心结论**:**先方案 A → 验证 → 再升级方案 B**(Jev 评分 0.92 confidence);Waypoint 部署是**可选且条件性**(0.92);`DestinationRule` 必须**选择性清理**(0.49 conf → 必须人审);`NetworkPolicy` 15008/15006/15001 三端口**全开**+ link-local 探针 `169.254.7.127` 必须显式 allow
> - **Jev 综合就绪度评分:0.68/4** — 落在"partially ready — needs validation"档,**不可裸奔上生产**

---

## 0. 文档定位

| 维度 | 内容 |
|---|---|
| **上游参考** | `20-solo-ambient-kong.md`(本目录)— 旧模式回顾、方案 A/B 拆解、NetworkPolicy 模板 |
| **评估方法** | TypeSafe Jev(`jev-1.13.0`)+ Istio 官方 Ambient 架构文档(repo `cache/web/` + 实时 `docs.istio.io`) |
| **目标读者** | 准备把 Kong 也搬进 Ambient mesh 的 SRE / 平台架构师 |
| **本文回答** | "按方案 B 实施前,有哪些**细节必须先验证 / 哪些坑不能踩**?" |
| **不回答** | 安装步骤(→ `02-install-ambient-helm.md`)、Waypoint 设计(→ `03-waypoint-design.md`)、Runtime 迁移(→ `04-runtime-migration.md`)、NetworkPolicy 基础(→ `08-ambient-networkpolicy.md`) |

---

## 1. Jev Speculative Fan-Out — 13 问评估结果

> 调用:`POST https://api.typesafe.ai/v1/systemone`,model=`jev-latest`(实际命中 `jev-1.13.0`),tokens=2259 input / 366 output。
> 方法:13 个独立问题**并行**(spec fan-out),每问用最匹配的 primitive(Noul=yes/no / Choice=多选一 / Score=有序等级),同时获取每个回答的 confidence。
> 完整响应存于 `/tmp/jev_fanout_response.json`(本次会话 session 内可用)。

### 1.1 评分汇总表

| # | 问题 | Primitive | Jev 答案 | Confidence | 决策意义 |
|---|---|---|---|---|---|
| Q1 | Kong 出 Mesh 后,Kong → 非 Mesh 目标(Postgres/Redis/license)会被 ztunnel 拦截导致 mTLS 失败? | Noul | **0.57**(模棱两可) | — | ⚠️ **必须实机验证**,不可猜 |
| Q2 | HBONE 是否只是 HTTP CONNECT over mTLS(非 HTTP 协议作 L4 不透明 TCP)? | Noul | **0.79**(基本是真) | — | ✅ 与上游文档一致 |
| Q3 | Kong Pod 内 `127.0.0.1` Admin API 被 ztunnel 拦截的风险? | Score(0–4) | **1.45 / 4** | 0.50 | ⚠️ 中等风险,需查 ztunnel netns 规则是否豁免 lo |
| Q4 | Kong 的 Header rewrite(X-Tenant / X-Gateway-Source)是否被 ztunnel 保留? | Noul | **0.78**(保留) | — | ✅ 与上游文档 §3 "租户 Context 保持" 一致 |
| Q5 | Kong Namespace 是否必须部署 Waypoint? | Choice | **conditional** | **0.92** | ✅ 仅当你需要 L7 AuthZ / HTTP 方法级策略时才部署 |
| Q6 | `DestinationRule` 旧 `tls.mode: SIMPLE` 怎么处理? | Choice | **delete_selectively** | 0.49 | ⚠️ **置信度低,必须人工审清单** |
| Q7 | NetworkPolicy 在 Plan B 下是否需要同时满足 (a) 放行 ztunnel (b) Kong 出非 Mesh (c) Gateway 入 Kong 三个条件? | Noul | **0.41**(假) | — | ❌ Jev 认为不全需要;但**官方文档说要**,跟随官方 |
| Q8 | Kong Pod 内 Admin API / Manager UI(8001/8002) 在 Pod 处于 Ambient 时仍能用? | Noul | **0.65** | — | ⚠️ 倾向于能用,但需实机验证 |
| Q9 | Kong(ambient) → Postgres / Redis(非 ambient)能连? | Noul | **0.79** | — | ✅ 倾向于能,ztunnel 出 Mesh 时做 pass-through |
| Q10 | 观测性变化 — Kong `/metrics` 还能 scrape 吗?需要新增 ztunnel 日志吗? | Score(0–4) | **1.51 / 4** | 0.50 | ⚠️ 倾向"叠加"(Kong metrics + ztunnel 日志),**两套都要保留** |
| Q11 | 零停机迁移顺序? | Choice | **runtime_first_plan_a_then_b** | **0.92** | ✅ 先方案 A → 验证 → 再升方案 B |
| Q12 | "ztunnel 解密后明文 IP 包投递给 Pod 真实端口" 这说法是否对**所有 TCP** 都成立? | Noul | **0.83** | — | ✅ 对(Postgres/Redis/Mongo 走 L4 不透明加密) |
| Q13 | **综合就绪度** | Score(0–4) | **0.68 / 4** | 0.73 | ⚠️ **"partially ready"** — 缺验证,不可裸上生产 |

### 1.2 阅读 Jev 答案的正确姿势(技能方法论)

> 摘自 `typesafe-ai/SKILL.md` "Compose and verify" 章节:
>
> *"Choice/Score confidence summarizes distribution concentration, **not overall workflow correctness or permission to act**. A Noul near 0.5 means similar probability for yes and no, not medium intensity."*

翻译:
- **conf < 0.7 的回答一律视为"必须人审/必须实机验证"**(本表 Q1 0.57, Q3 0.50, Q6 0.49, Q7 0.41 全部落入此区)
- **conf ≥ 0.9 的回答可以视为强信号**(Q5 / Q11 都在 0.92)
- **Score 的 N 维不代表"intensity"**,而是"概率加权位置";`1.45` 是 level 1 53% + level 2 28% + level 0 8% + level 3 10% 的加权结果,不是"风险 36%"

---

## 2. 必须显式验证的 7 个细节(按优先级)

### 2.1 【P0】NetworkPolicy 三个端口必须全开 — 不可省略 15008

**依据**:`08-ambient-networkpolicy.md` §1.1 + Istio 官方 [Ztunnel traffic redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/)。

ztunnel DaemonSet 在 Pod 网络命名空间内建立三个 listener:

| 端口 | 用途 |
|---|---|
| **15008** | HBONE 隧道入口(mTLS CONNECT) |
| **15006** | 入站明文 → 校验后投递真实端口 |
| **15001** | 出站明文 → ztunnel 拦截 → 出 Mesh 重新封装 |

**NetworkPolicy 在主机网络命名空间早于 ztunnel 生效**,若 NP 不放行 15008,mesh 流量在到达 ztunnel 之前就被 CNI 拦截。

```yaml
# ✅ 必须显式 allow 三个端口
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ztunnel-and-business-ports
  namespace: 110139-int
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  ingress:
    - ports:
        - {protocol: TCP, port: 15008}   # HBONE — 关键
        - {protocol: TCP, port: 15006}   # inbound plaintext
        - {protocol: TCP, port: 80}      # 业务端口
  egress:
    - ports:
        - {protocol: TCP, port: 15001}   # outbound listener
        - {protocol: TCP, port: 53}      # DNS
        - {protocol: UDP, port: 53}
```

> **Jev Q7 误判**:Jev 答"条件 (a) 可省略,ztunnel 隐式处理"。**官方文档明确反对**。**官方文档 > 模型判断**,必须三件套全开。

### 2.2 【P0】Kubelet 探针 link-local `169.254.7.127` 必须显式 allow

**依据**:`08-ambient-networkpolicy.md` §1.2 + Istio in-pod redirection 博客(2024)。

Ambient 下,istio-cni 把 kubelet 探针包的源 IP **SNAT 重写为 link-local**:

| 协议 | SNAT 后源 IP |
|---|---|
| IPv4 | `169.254.7.127` |
| IPv6 | `fd16:9254:7127:1337:ffff:ffff:ffff:ffff` |

```yaml
ingress:
  - from:
      - ipBlock:
          cidr: 169.254.7.127/32   # kubelet probe 源 — 必须 allow
    ports:
      - {protocol: TCP, port: 8080}
```

**漏掉这条 = Readiness Probe 失败 = Pod 永远 NotReady = 服务 100% 不可用**。

### 2.3 【P1】Kong → 非 Mesh 目标(Plan B 下的关键不确定性)

**Jev Q1 答 0.57** — 接近"不知道"。

按 Istio 官方架构文档,ztunnel 对**出 Mesh 流量**的处理:

> *For traffic to unknown addresses, or to workloads that are not a part of the mesh, the traffic will just be passed through as is. To make ztunnel more transparent, the original source IP address will be spoofed.*
> — [architecture/ambient/ztunnel.md](https://github.com/istio/istio/blob/master/architecture/ambient/ztunnel.md)

**官方态度是 pass-through**(通过 `splice()` 高效转发,源 IP spoof 保持透明)。但 Kong 的特殊情况:

- Kong → **Postgres**(DNS 解析后是 ClusterIP,但 Postgres Pod 本身若不在 ambient)→ 出 Mesh 时 ztunnel 是否仍做 SPIFFE 校验?
- Kong → **Redis / license agent to konghq.com**(完全 Mesh 外,IP 不在 cluster 内)→ ztunnel 看到目标 IP 不在 mesh,pass-through

**实施前验证脚本**:

```bash
# 1. 临时给 kong-system 打 ambient 标签(只读测试)
kubectl label namespace kong-system istio.io/dataplane-mode=ambient --dry-run=server

# 2. 在 Kong Pod 内手动测连通性
kubectl exec -n kong-system deploy/kong-kong -- \
  curl -v telnet://kong-database.kong-system.svc:5432  # 若 Kong 没装 telnet,改 nc
kubectl exec -n kong-system deploy/kong-kong -- \
  curl -v https://license.api.konghq.com/  # 出集群测

# 3. 看 ztunnel 日志有没有 "pass-through" 字样
kubectl logs -n istio-system -l app=ztunnel --tail=200 | grep -E "(kong|pass-through|splice)"
```

**判定标准**:Postgres / license 全连通 + ztunnel 日志显式打 "pass-through" 才算验证通过。

### 2.4 【P1】Kong Pod loopback Admin API 风险(Jev Q3 score 1.45/4)

**Jev 评分含义**:
- level 0(impossible): 8%
- level 1(unlikely): 53%
- level 2(possible): 28%
- level 3(likely): 10%
- level 4(certain): 1%

按 Istio 官方 ztunnel 架构:

> *All TCP traffic coming into the pod is redirected to the ztunnel proxy for ingress processing. If the traffic is plaintext (destination port != 15008), it will be redirected to the in-pod ztunnel plaintext listening port 15006.*

**理论上**:Pod 内 `127.0.0.1:8001` 的 TCP 流量**目标端口不是 15008**,应被重定向到 15006(inbound plaintext)。Kong Admin 流量是明文 HTTP,会被 ztunnel 截获。

**实际情况**:Kong Admin 通常是**Kong 进程自己内部监听**(`admin_listen = 127.0.0.1:8001 http`),其他进程通过 `localhost` 访问。`localhost` 流量在大多数 iptables 实现中是**豁免的**(OUTPUT chain 在 lo 接口早返回)。

**验证脚本**:

```bash
# 在 Kong Pod 内(打 ambient 标签前 vs 后对比)
kubectl exec -n kong-system deploy/kong-kong -- curl -s http://127.0.0.1:8001/ | head -20

# 看 ztunnel 日志有没有捕获 127.0.0.1:8001 流量
kubectl logs -n istio-system -l app=ztunnel --tail=500 | grep "127.0.0.1"
```

**判定**:Kong Admin 返回正常 JSON + ztunnel 日志**不出现** 127.0.0.1 → 安全。若 ztunnel 出现 127.0.0.1 流量,需在 Kong 配置中把 `admin_listen` 改 `off` 或 `0.0.0.0` + 加 IP allowlist。

### 2.5 【P1】DestinationRule 必须**选择性**清理(Jev conf 0.49 → 必须人审)

**Jev 答 `delete_selectively` 但 conf 仅 0.49**。这意味着模型自己也不确定。

按 Istio 1.30 文档(`07-feature-status-1.30.3.md` §1.1):

> *AuthorizationPolicy: Stable, **但 DISABLE 在 ambient 下无效***
> *PeerAuthentication: Stable*

**操作清单**(人工逐条审):

| 旧 DestinationRule | 旧目标 | Plan B 下处理 |
|---|---|---|
| `kong-dp-tls-dr`(指向 `kong-dp-service.kong-system.svc`, port 8443) | KongDP | **Kong 进入 Mesh 后,Kong 不再需要外部 TLS → 删除 DR** |
| `app2-runtime-tls-dr`(指向 `app2-runtime-service.110139-int.svc`, port 8443) | Runtime | Runtime 早就是 ambient 明文 80 → **DR 已失效,删除** |
| 任何**指向非 Mesh 目标**的 DR(legacy external services) | Mesh 外 | **保留**,但确认 `tls.mode: DISABLE` 或 `ISTIO_MUTUAL`(非 Mesh) |

**验证脚本**:

```bash
# 列出所有 DR
kubectl get destinationrule -A

# 过滤出指向已 ambient 标签的 backend service 的 DR(可疑需删)
for dr in $(kubectl get dr -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{" "}{end}'); do
  ns=$(echo $dr | cut -d/ -f1)
  name=$(echo $dr | cut -d/ -f2)
  host=$(kubectl get dr -n $ns $name -o jsonpath='{.spec.host}')
  ns_of_host=$(echo $host | cut -d. -f2)
  if kubectl get ns $ns_of_host -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}' 2>/dev/null | grep -q ambient; then
    echo "STALE: $ns/$name -> $host (backend namespace is ambient)"
  fi
done
```

输出非空 → 人工逐条确认后 `kubectl delete dr -n <ns> <name>`。

### 2.6 【P2】Waypoint 部署是**可选且条件性**(Jev conf 0.92,强信号)

**Jev 答 `conditional` conf 0.92**。含义:**L4 ztunnel 已经给你 mTLS + L4 AuthZ,只有需要 L7 才上 Waypoint**。

**何时部署**(满足任一):

1. 想要 `AuthorizationPolicy` 在 HTTP 方法 / header / path 级别生效(非 SPIFFE 级别的 L4)
2. 想要 `RequestAuthentication`(JWT 验证)在 Ingress Gateway 之外拦截
3. 想要 L7 灰度 / 流量切分(类似 VirtualService 行为)
4. 想要 waypoint 自动注入 Telemetry / WasmPlugin(WasmPlugin 当前 Alpha,见 `07-feature-status-1.30.3.md` §1.1)

**何时不部署**:

- 只要 mTLS + L4 SPIFFE AuthZ
- 只想降低 Istio 资源开销(Ambient 核心卖点)

**Plan B 下 Waypoint 部署选项**:

```yaml
# 选项 A:Waypoint for kong-system(让 Kong 自己有 L7 治理)
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: kong-waypoint
  namespace: kong-system
  labels:
    istio.io/for-service: kong-kong   # 或 kong-dp-svc
spec:
  gatewayClassName: istio-waypoint
  listeners:
    - name: mesh
      port: 15008
      protocol: HBONE

# 选项 B:Waypoint for 110139-int(让 Runtime 有 L7 治理,已有或后续部署)
# 见 03-waypoint-design.md §X
```

### 2.7 【P2】观测性双栈 — Kong `/metrics` + ztunnel access log 都保留

**Jev Q10 score 1.51/4**(倾向"叠加")。

具体含义:

- ✅ **Kong Prometheus `/metrics` 继续工作**(Kong 自己进程的 metrics,与 mesh 无关)
- ✅ **ztunnel access log 新增一层** — 可看到 SPIFFE identity 维度的 east-west 流量

**启用 ztunnel access log**:

```yaml
# istio install overlay 或 Helm values
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio-config
  namespace: istio-system
data:
  mesh: |-
    defaultConfig:
      proxyMetadata:
        ISTIO_META_ENABLE_HBONE: "true"
    extensionProviders:
      - name: otel-tracing
        envoyOtelAls:
          service: otel-collector.observability.svc.cluster.local
          port: 4317
# ztunnel 日志默认 info 级别,access 日志已开启
```

**Grafana 查询示例**(east-west 按 SPIFFE 聚合):

```promql
sum by (src_identity, dst_identity) (
  rate(ztunnel_connection_total{
    src_namespace="kong-system", dst_namespace="110139-int"
  }[5m])
)
```

---

## 3. 零停机迁移顺序(Jev Q11 conf 0.92)

> *Jev 答 `runtime_first_plan_a_then_b` conf 0.92 — 强信号*

```
Phase 0: 当前状态(Sidecar 模式或无 Mesh)
  - Runtime Pod 自建 TLS,监听 8443
  - DestinationRule: tls.mode: SIMPLE
  - Kong 在 kong-system,听 HTTPS 8443
  - Istio Ingress Gateway 解外层 TLS

       ↓ Phase 1 — 上 Ambient(方案 A)
       ↓ 把 Runtime Namespace 打 ambient 标签
       ↓ Runtime 切回明文 80,删 DestinationRule,删 Runtime 自建 TLS
       ↓ Kong 保持 Mesh 外,改 upstream 为 http://...:80:8000

Phase 1: 方案 A(Kong 在 Mesh 外)
  - Runtime: 110139-int (ambient) — 明文 80
  - Kong: kong-system (非 Mesh) — HTTP 8000 入 → http://...:80 出
  - Istio Ingress Gateway: 解 TLS → HTTP 明文转发 Kong 或 Runtime
  - DestinationRule: 全删
  - NetworkPolicy: Runtime NS 放行 ztunnel 15008/15006 + Istio Gateway 源 + Kong 源
  - 验证: 跑通业务流量 + Prometheus metrics 正常 + ztunnel 日志看到 SPIFFE 流量

       ↓ Phase 2 — 升级到方案 B(Plan B 落地)
       ↓ 给 kong-system 打 ambient 标签
       ↓ 验证 Kong → Postgres / license / Admin API 不受影响

Phase 2: 方案 B(Kong 也入 Mesh)
  - Runtime: 110139-int (ambient) — 明文 80
  - Kong: kong-system (ambient) — HTTP 8000 → 内部 HBONE → Runtime 明文 80
  - Istio Ingress Gateway: 同 Phase 1
  - DestinationRule: 同 Phase 1(全无)
  - NetworkPolicy: 同步扩到 kong-system 放行 ztunnel + Gateway 源
  - 可选:Waypoint for kong-system(若需要 L7 策略)
  - 验证: 同 Phase 1 + Kong Admin API 正常 + Kong → Postgres / license 连通
```

**Phase 1 → Phase 2 切换的 hard gate**(全部 ✅ 才执行):

- [ ] Phase 1 流量稳定 ≥ 7 天
- [ ] Kong → Postgres / Redis / license agent 全连通(§2.3 脚本过)
- [ ] Kong Admin API / Manager UI 在 Kong Pod 内 loopback 工作(§2.4 脚本过)
- [ ] DestinationRule 全部清理或显式豁免(§2.5 脚本无 STALE 输出)
- [ ] NetworkPolicy 三端口 + link-local 探针放行(§2.1 + §2.2 YAML)
- [ ] Prometheus + ztunnel 日志采集双栈就绪(§2.7 Grafana 看板)

---

## 4. 上线后必须监控的 SLO / SRE 信号

| 信号 | 阈值 | 含义 |
|---|---|---|
| `ztunnel_connection_total{result="success"}` / 总连接数 | < 99% | mTLS 握手失败率上升 → Kong/Runtime SPIFFE 证书过期或 PeerAuth 误配 |
| `kubelet_probe_failed_total{pod=~"kong-.*"}` | > 0 持续 5min | §2.2 link-local 未放行 → 探针失败 |
| Kong Pod `admin_listen` 8001 可用性 | < 99% | §2.4 loopback 被 ztunnel 截 |
| `kong_upstream_health{upstream=~"app1.*"}` | 健康 backend 数 = 期望 | §2.3 出 Mesh 失败 |
| Waypoint(若部署)`envoy_cluster_upstream_cx_connect_fail` | > 0.5% | Kong 到 Waypoint 握手失败,检查 15008 |

---

## 5. 置信度与未知项 — 不要假装确定

| 项 | 状态 | 处理 |
|---|---|---|
| Kong → Postgres(非 ambient)连通 | Jev 0.79 + 官方 pass-through 表述 | **§2.3 实机验证** |
| Kong Admin loopback 不被 ztunnel 截 | Jev 1.45/4 + 50% conf | **§2.4 实机验证** |
| DestinationRule 全删 vs 选择性删 | Jev 0.49 conf | **§2.5 人工审清单** |
| NetworkPolicy 三条件是否都必要 | Jev 0.41(答"不全必要")vs 官方"全必要" | **跟随官方,§2.1 + §2.2** |
| Plan B 后 Istio 1.30.3 是否支持所有细节 | `07-feature-status-1.30.3.md` §1.1(Stale/Beta/Alpha 矩阵) | Multicluster ambient 仍 Beta,生产多集群**仍建议等 1.31+** |

---

## 6. 权威证据 / 来源日期

- **Istio Ambient 架构文档**(`https://istio.io/latest/docs/ambient/architecture/`):官方权威,定义 ztunnel 三端口(15001/15006/15008)+ HBONE=HTTP CONNECT over mTLS
- **Ztunnel Traffic Redirection**(`https://istio.io/latest/docs/ambient/architecture/traffic-redirection/`):官方,描述 in-pod iptables 重定向 + 排除 lo 的规则
- **Istio repo `architecture/ambient/ztunnel.md`**(`https://github.com/istio/istio/blob/master/architecture/ambient/ztunnel.md`):架构 ADR 文档,定义 pass-through / splice() / source IP spoof 行为
- **TypeSafe Jev docs**(`https://docs.typesafe.ai/`):fan-out / confidence / composite scoring 方法论
- **本仓库**:
  - `20-solo-ambient-kong.md`(上游方案 A/B 拆解)
  - `08-ambient-networkpolicy.md`(§1.1 三端口 + §1.2 link-local)
  - `07-feature-status-1.30.3.md`(Istio 1.30.3 feature 矩阵)
  - `02-install-ambient-helm.md`(Helm 安装步骤,本文不重复)
  - `03-waypoint-design.md`(Waypoint 设计,本文仅引用)
- **Jev 评估响应**:`/tmp/jev_fanout_response.json`,13 问 fan-out,model=`jev-1.13.0`,调用日期 2026-09-19
- **本文创建日期**:2026-09-19
- **审查周期**:Istio minor release 时(1.30 → 1.31 → 1.32)+ Ambient 单网络 multicluster 转 Stable 时

---

## 7. TL;DR 操作 checklist(打印贴工位)

```
□ Phase 1 (方案 A) 流量稳定 ≥ 7 天
□ Phase 2 切换前(全部 ✅ 才执行):
    □ Kong → Postgres / Redis / license 实机连通测试
    □ Kong Admin 8001 / Manager 8002 在 Pod 内 loopback 可用
    □ DestinationRule STALE 清单为空
    □ NetworkPolicy 15008/15006/15001 + link-local 169.254.7.127 全 allow
    □ Prometheus + ztunnel access log 双栈看板就绪
    □ (可选)Waypoint for kong-system 就绪
□ Phase 2 切换后:
    □ Kong Pod 启动成功
    □ Kong → Runtime 经 HBONE 隧道连通(ztunnel 日志看到 SPIFFE 双向)
    □ Kong → Postgres / license 仍连通(§2.3 验证)
    □ Kong Admin loopback 仍可用(§2.4 验证)
    □ Kubelet 探针全过(否则 169.254.7.127 没放行)
    □ 监控 SLO(§4) 7 天绿色
```
