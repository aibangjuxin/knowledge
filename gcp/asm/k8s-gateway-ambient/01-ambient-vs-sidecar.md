# Ambient vs Sidecar — 本场景下的本质差异与选型

> **TL;DR**:
> - 你当前 `istioctl install --set profile=minimal` = **sidecar 模式**(pod 内注入 envoy)
> - **ambient 模式** = 节点级 `ztunnel`(L4 mTLS) + 命名空间级 `waypoint`(L7 策略,按需)
> - **核心区别**:ambient 把"代理"从 pod 内挪到 pod 外,代价 = 要装 3 个新组件、放弃 per-pod 隔离
> - **本场景是否值得迁** = 看你的 L7 策略密度 + pod 数量(详见 §5 决策树)

---

## 1. Sidecar 模式:现状是什么样

```text
┌──── Pod (业务 ns) ────────────────────────┐
│                                            │
│  ┌────────────┐    ┌────────────────────┐ │
│  │ app 容器    │ →  │ istio-proxy        │ │   ← 你现在每个 Pod 都有
│  │ (业务代码)  │    │ (envoy, ~50m CPU)  │ │
│  └────────────┘    └────────────────────┘ │
│                                            │
└────────────────────────────────────────────┘
```

**特征**:
- `istio-injection=enabled` 的 namespace,**每个 pod 启动时自动注入 istio-proxy**
- envoy 做:L4 mTLS + L7 路由 + L7 策略(AuthorizationPolicy 等)+ 可观测性
- 当前 K8s Gateway 通过 `gatewayClassName: istio` 部署的 ingress gateway 也是 sidecar 模式

**痛点**(本场景里已经隐含,只是还没爆):
1. **资源浪费**:N 个 pod = N 个 envoy,内存常驻 ≈ 60-80Mi/Pod × pod 数
2. **启动延迟**:每次 pod 启动要等 envoy 起来并连上 istiod 才能接流量
3. **升级炸面广**:升 istio 版本 = 所有 pod 都得重启(除非 revision 切流)
4. **侵入性**:业务 pod 的 readiness probe 要绕 envoy 的 15020 端口(我们 `04-secrets/` 那块 nginx HTTPS 配置就是这么处理的)

---

## 2. Ambient 模式:完全不同的拓扑

```text
                    节点 A                    节点 B
                ┌──────────┐            ┌──────────┐
┌──── Pod ──────│  ztunnel │── HBONE ──│  ztunnel │───── Pod ────┐
│ app 容器       │ (DaemonSet)         (DaemonSet)│ app 容器       │
│ (无 envoy)     │ L4 mTLS             L4 mTLS  │ (无 envoy)     │
└──── Pod ──────│                       │         └──── Pod ────┘
                └──────────┘            └──────────┘
                       │                       │
                       ▼ (按需)                ▼
                ┌──────────────────────────────┐
                │   waypoint (Deployment, 2 rep) │  ← 只有需要 L7 的 ns 才部署
                │   (L7 路由/策略/可观测)         │
                └──────────────────────────────┘
```

**特征**:
- 业务 pod **不再注入 envoy** = 纯净应用容器
- **`ztunnel`** = 节点级 Rust 编写的轻量 mTLS 代理(DaemonSet,每节点 1 pod)
- **`waypoint`** = Envoy 实现的 L7 代理,按 namespace 或 service 级别部署
- 需要 namespace 加 label:`istio.io/dataplane-mode=ambient`

**关键限定**(Istio 1.27+,我们用 1.30 完全满足):

| 维度 | 行为 | 来源 |
|---|---|---|
| ztunnel 与 ztunnel 之间 | L4 mTLS,默认加密 | [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/) |
| ztunnel → waypoint | 走 HBONE(HTTP-Based Overlay Network Environment) | 同上 |
| waypoint → 业务 pod | 解 mTLS,转发明文 | 同上 |
| 加密默认开 | DISABLE 模式在 ambient 不支持 | [Istio PeerAuthentication ambient 差异](https://istio.io/latest/docs/ambient/security/) |
| 升级 ztunnel | **不影响业务 pod 长连接** | 节点级守护,改 DaemonSet 即可 |

---

## 3. 严格定义 vs 简化解释(分两栏)

| 概念 | 简化解释 | 严格定义(Istio 官方原文 / 链接) |
|---|---|---|
| **ztunnel** | 节点级 mTLS 代理 | "ztunnel is a per-node mTLS data plane component, implemented in Rust, that handles L4 encrypted traffic between workloads in the mesh." — [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/) |
| **waypoint** | 命名空间级 L7 代理 | "A waypoint proxy is a deployment of an Envoy proxy that handles L7 processing for workloads in a namespace or service." — [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/) |
| **HBONE** | 一种隧道协议 | "HBONE (HTTP-Based Overlay Network Environment) is the tunneling protocol used by ztunnel to establish mTLS-protected connections between proxies." — [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/) |
| **ambient profile** | 一种安装配置 | "The ambient profile installs istiod, istio-cni, and ztunnel. Sidecar injection is disabled by default." — [Istio Ambient Install](https://istio.io/latest/docs/ambient/install/) |
| **namespace 标签** | "加入 ambient" | "Namespaces labeled with `istio.io/dataplane-mode=ambient` opt into ambient mesh; workloads in those namespaces do not require sidecar injection." — [Istio Ambient](https://istio.io/latest/docs/ambient/) |

---

## 4. 详细对比矩阵

| 维度 | Sidecar(现状) | Ambient(目标) | 切换代价 |
|---|---|---|---|
| **数据面位置** | Pod 内(envoy 容器) | 节点级 ztunnel + ns 级 waypoint | **新装 3 个组件** |
| **L4 mTLS** | 每 pod envoy | 节点 ztunnel | 中(改造 mesh config) |
| **L7 策略** | 每 pod envoy | waypoint(按需部署) | 小(策略无需改写,只换 selector → targetRefs) |
| **资源消耗** | O(N pods) 个 envoy | O(1) ztunnel/节点 + O(M) waypoint/ns | **降低** |
| **升 istio 版本影响** | 滚动重启所有 pod | 节点级 ztunnel 守护更新;waypoint Deployment 滚动;**业务 pod 零重启** | 需要 revision 机制 |
| **L7 适用性** | 每个 pod 都具备 | 需要显式 enroll 到 waypoint | 业务改造 |
| **故障域** | 单 pod 故障 | 节点故障 | 单点风险评估 |
| **遥测** | 每个 pod 独立 metric | ztunnel/waypoint 集中 metric | 改造采集配置 |
| **PeerAuthentication DISABLE** | ✅ 支持 | ❌ 不支持(ambient 默认加密) | 极端兼容场景无法做 |
| **selector vs targetRefs** | 两者都支持 | **`targetRefs` 必走**(API ≥ 1.22) | 改造 policy 写法 |

---

## 5. 本场景要不要迁?**决策树**

```
你的业务规模?
  ├─ 集群 ≤ 5 pod (你 dev 集群现状)
  │   ├─ 是否计划未来加大量 workload?
  │   │   ├─ 否 → 不值得迁,sidecar 简单可控
  │   │   └─ 是 → 值得迁,但可以等负载上来再做

  └─ 集群 ≥ 20 pod,且有 5+ ns
      ├─ L7 策略覆盖密度?
      │   ├─ ≤ 30% ns 需要 AuthorizationPolicy / VirtualService L7
      │   │   → 值得迁(waypoint 只在需要时部署)
      │   └─ > 80% ns 都需要 L7 策略
      │       → **不一定值得**(每个 ns 都要 waypoint = 失去 ambient 资源节省意义)

      └─ 升级频率?
          ├─ 季度升一次 istio + 可接受短暂中断 → sidecar + revision
          └─ 月度升一次 + 不能中断 → **ambient + 双 revision canary**(本目录 05 文)
```

### 本场景的诚实结论

- 你 dev 集群:**ambient 不强制**(pod 数量小),但**探索价值高**(生产必然迁)
- 推荐路径:**先在 dev 集群把 ambient 跑通**(本目录 02-04 文),验证 waypoint L7 策略行为,再考虑生产
- **不要在生产没跑通之前,先动 AuthorizationPolicy**(你已锁决策:policy 暂不动,只做知识储备)

---

## 6. 切 ambient 的硬性前置条件

> 来自 `~/git/knowledge/gcp/asm/gloo/gke-ambient-waypoint-single.md` §5.4 + Istio 官方:
> - [ ] Istio ≥ 1.19(我们 1.30 ✅)
- [ ] K8s Gateway API CRD v1.0+(你已 v1.5.1 ✅)
- [ ] GatewayClass `istio-waypoint` 已注册(ambient install 自动注册)
- [ ] 节点 OS 支持 CNI 拦截(COS / Ubuntu / cos_containerd ✅;GKE 官方推荐 `cos_containerd`)
- [ ] 集群有足够资源装 ztunnel DaemonSet(每节点 ~100m CPU + 128Mi mem)

---

## 7. 切 ambient 后会发生什么(对现有架构的影响)

| 影响点 | 行为 |
|---|---|
| 业务 pod | **去掉 sidecar**,启动更快,镜像层不再需要 istio-proxy |
| 入口 Gateway | **仍是 sidecar**(`istio-ingressgateway` Deployment 跑 envoy 容器),不会自动变 ambient |
| K8s Gateway API Gateway | **仍是 sidecar 模式**,除非你用 `gatewayClassName: istio-waypoint` 显式声明 |
| ListenerSet 多租户 | **不变**(Gateway API 层面与数据面模式无关) |
| AuthorizationPolicy / PeerAuthentication | **可用**,但 ambient 下推荐 `targetRefs` 代替 `selector` |
| 可观测性 | ztunnel 默认输出 access log 到 stdout;Prometheus 抓 waypoint 与 ztunnel |
| 证书签发 | 不变(仍是 istiod 通过 SPIFFE 签发,只是颁发对象从 envoy 改成 ztunnel) |

---

## 8. 反向:为什么可能**不**迁

- ambient 还在快速演进(Istio 1.20 才正式 GA,1.27 增加 L7 features,1.30 进一步稳定)
- 大量 Istio 文档默认还是 sidecar 模式,踩坑资料少
- Gloo/Solo 商业版支持更成熟(你的 `gke-ambient-waypoint.md` 就是基于企业版)
- 多集群 ambient 在 1.30 仍处于 preview 阶段([Istio multicluster ambient](https://istio.io/latest/docs/ambient/multicluster/))

---

## 9. References(权威来源)

- [Istio Ambient 总览](https://istio.io/latest/docs/ambient/) — Istio 官方入口
- [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/) — ztunnel/waypoint/HBONE 权威定义
- [Istio Ambient Install](https://istio.io/latest/docs/ambient/install/) — ambient profile 与 minimal 区别
- [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/) — waypoint 部署权威指南
- [Istio Ambient Security](https://istio.io/latest/docs/ambient/security/) — ambient 下 PeerAuthentication 差异
- [Istio Ambient vs Sidecar(对比)](https://istio.io/latest/docs/ambient/overview/ambient-vs-sidecar/) — 官方对比页
- 同仓库 `~/git/knowledge/gcp/asm/gloo/Ambient.md` — 已有科普版基础概念(可作为本篇的"非技术读者版")
- 同仓库 `~/git/knowledge/gcp/asm/gloo/waypoint.md` — Waypoint 详解(本目录 03 文详细展开)
- 同仓库 `~/git/knowledge/gcp/asm/gloo/gke-ambient-waypoint-single.md` — Gloo 视角的 ambient 单集群实施