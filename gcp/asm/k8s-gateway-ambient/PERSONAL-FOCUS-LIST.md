# 个人关注清单 — Ambient / Revision / Policy 探索中的核心问题

> **文档定位**:从 14 篇探索文档 + ADR-LOCAL-001 中摘录**我个人最关注**的点。每条都给出:**原文摘录 → 我的解读 → 待解决问题 → 关联文档引用**。
>
> **用途**:通读后反复翻这份清单,**对每个待解决问题有进展时回填**。
>
> **维护方式**:当某个问题已解决 → 在"状态"列打 ✅ 并注明决议;当有变化 → 追加新关注点。

---

## 0. 元数据

- **维护者**:architect-gcp(架构师视角)
- **创建时间**:2026-09-17
- **关联目录**:`k8s-gateway-ambient/`
- **关联 ADR**:`ADR-LOCAL-001-migrate-minimal-to-ambient.md`(本清单被 ADR §9 引用)
- **状态字段约定**:
  - 🔴 **未解** — 还需进一步验证或确认
  - 🟡 **进行中** — 已开始探索,部分解决
  - 🟢 **已决议** — 已锁定答案(看"决议"列)
  - ⚪ **低优** — 不阻塞主线

---

## 1. 个人关注清单(按文档归类)

### 📄 来自 `01-ambient-vs-sidecar.md`

#### 关注 1.1 — Gateway 切换决策

| 字段 | 内容 |
|---|---|
| **原文摘录** | "How to switch Gateway. Current is `gatewayClassName: istio` ==> `gatewayClassName: istio-waypoint` 显式声明 OR `enterprise-agentgateway`?" |
| **我的解读** | 这是**入口 Gateway 是否切到 ambient 模式**的决策。三种选项:(a) 保留 `istio` 不动;(b) 切 `istio-waypoint`(但 10 文已说 waypoint 是东西向 / L7 拦截器,不适合南北向入口);(c) Solo 企业版的 `enterprise-agentgateway`(Alpha,1.30+ Solo 分发才有)。 |
| **待解决问题** | 本场景是否需要切?如果切,切到哪个 GatewayClass? |
| **状态** | 🔴 未解 |
| **建议方向** | 详见 `10-waypoint-gateway-coexistence.md` §3 — **本场景推荐保留 `gatewayClassName: istio` 不动**(waypoint 不适合做南北向入口;agentgateway 是 Alpha,不生产)。 |
| **决议** | 待 Lex 与 infra-gcp / devops-gcp 确认:dev 集群入口 Gateway 是否永远 sidecar? |

#### 关注 1.2 — targetRefs 取代 selector 的写入纪律

| 字段 | 内容 |
|---|---|
| **原文摘录** | "AuthorizationPolicy / PeerAuthentication ==> ambient 下推荐 targetRefs 代替 selector" |
| **我的解读** | 这是**未来写 policy 的纪律**。ambient 下 `selector.matchLabels` 仍可用但粒度受限;推荐用 `targetRefs` 绑 Service / Gateway(waypoint)。`targetRefs` 与 `selector` 在同一 spec 互斥。 |
| **待解决问题** | 当前 dev 集群**没有 AuthZ/PA**(06 文是知识储备),所以**当前无需修改**;但需确立未来写入规则。 |
| **状态** | 🟡 已决议(写入规则)— 见 ADR §2.4 与 06 文 |
| **决议** | 未来所有 AuthZ/PA 必须用 `targetRefs`,**不写 selector 版本**;若旧 selector 版本存在,必须手动改写 |

---

### 📄 来自 `02-install-ambient-helm.md`

#### 关注 2.1 — minimal vs ambient 的 profile 扩展性边界

| 字段 | 内容 |
|---|---|
| **原文摘录** | "`istioctl install --set profile=minimal` 装不全 ambient — ambient 需要额外 3 个 chart:`istio-cni` + `ztunnel`" |
| **我的解读** | **minimal profile 不能 `--set` 扩展出 ambient**。这是 02 文的核心架构判断。必须显式用 `profile=ambient` 或 Helm 拆 4 release。 |
| **待解决问题** | 无(架构判断已锁定) |
| **状态** | 🟢 已决议 |
| **决议** | Helm 拆 4 release:base / istiod / cni / ztunnel(详见 ADR §2.1 + 02 文 §4) |

#### 关注 2.2 — istioctl install --set profile=ambient vs Helm 拆分

| 字段 | 内容 |
|---|---|
| **原文摘录** | "`istioctl install --set profile=ambient` istiod + cni + ztunnel ✅ 但不能拆开升级(一个 release 整体);Helm 拆分安装 4 个独立 release ✅ 可单独升 ztunnel、单独升 istiod" |
| **我的解读** | 这是**安装工具选型**。两种方式底层都是同一份 chart,但渲染路径不同,不能混用。 |
| **待解决问题** | 无(选型已锁) |
| **状态** | 🟢 已决议 |
| **决议** | Helm 拆 4 release(详见 ADR §2.1 + 02 文 §6) |

#### 关注 2.3 — Helm 拆分安装的具体命令与 values

| 字段 | 内容 |
|---|---|
| **原文摘录** | "values/cni.yaml — CNI 插件 CNI ambient: dnsCapture: true # ambient 关键:抓 DNS 解析;Step 1:base / Step 2:istiod / Step 3:istio-cni / Step 4:ztunnel helm upgrade --install 命令序列" |
| **我的解读** | **完整的 Helm 拆分安装 4 步命令**已写明,values 骨架已落(目录 `values/`)。 |
| **待解决问题** | 是否需要补 `ztunnel:1.30.3-distroless` 与 `install-cni:1.30.3-distroless` 到 GAR(02 文 §3)? |
| **状态** | 🔴 未解(需 Lex 与 infra-gcp 确认 GAR 镜像是否齐备) |
| **关联** | 02 文 §3 镜像策略 + ADR §6.3 上下游依赖 |

---

### 📄 来自 `03-waypoint-design.md`

#### 关注 3.1 — waypoint 资源的存在性核对

| 字段 | 内容 |
|---|---|
| **原文摘录** | "对于我们现在布置的环境,是不是没有这个定义资源?需要去核对一下。" |
| **我的解读** | 这是**架构师的自检问题** — 当前 dev 集群是否真的装了 waypoint Gateway?如果没装,本目录某些讨论是假设性的。 |
| **待解决问题** | (a) 当前 dev 集群是否已装 `gatewayClassName: istio-waypoint` 的 Gateway?(b) 如果没装,何时装、装在哪些 ns? |
| **状态** | 🔴 未解 — **必须在 Phase 1 装 ambient 控制面后立刻核对** |
| **核对命令** | `kubectl get gatewayclass`(应见 `istio` + `istio-waypoint` 两个 class);`kubectl get gateway -A`(看现有 waypoint Gateway) |
| **关联** | 03 文 §6 部署方式 + 02 文 §5 验证清单 |

#### 关注 3.2 — waypoint 的角色定位(不是入口 Gateway)

| 字段 | 内容 |
|---|---|
| **原文摘录** | "Waypoint 是 ambient 的 L7 策略执行器(AuthorizationPolicy / VirtualService / HTTPRoute 等);组件矩阵:K8s Gateway API Gateway / waypoint / ztunnel 角色对比" |
| **我的解读** | **waypoint ≠ 入口 Gateway**。waypoint 是东西向 L7 策略执行器(per-namespace 或 per-service);入口 Gateway 是南北向 L7 + TLS 终止。 |
| **待解决问题** | 无(角色定位已清) |
| **状态** | 🟢 已决议 |
| **决议** | dev 集群入口 Gateway(`gatewayClassName: istio`)不动,继续做南北向;**未来业务 ns 需要 L7 时再装 waypoint**(详见 10 文 + ADR §2.2) |

#### 关注 3.3 — waypoint 的 podAntiAffinity 自动行为

| 字段 | 内容 |
|---|---|
| **原文摘录** | "waypoint 由 Istio controller 根据 Gateway 自动生成 Deployment,但 controller 1.27+ 已经默认加 podAntiAffinity" |
| **我的解读** | waypoint Deployment 的反亲和是 controller 自动加的,**无需手动配置**(除非用 Helm 自管 Deployment)。 |
| **待解决问题** | 无 |
| **状态** | 🟢 已决议 |

#### 关注 3.4 — 何时不装 waypoint

| 字段 | 内容 |
|---|---|
| **原文摘录** | "业务 ns 完全无 L7 需求,只需要 mTLS:可不部署 waypoint,ztunnel 直连更轻" |
| **我的解读** | **本场景当前结论** — dev 集群**没装 waypoint**(无 L7 需求)。 |
| **待解决问题** | 何时触发"装 waypoint"?业务方需要 AuthZ / HTTPRoute 路由时。 |
| **状态** | 🟡 已决议(暂不装)— 见 ADR §2.2 + 03 文 §8 |

---

### 📄 来自 `04-runtime-migration.md`

#### 关注 4.1 — namespace label 的"平滑"切换问题 ⭐

| 字段 | 内容 |
|---|---|
| **原文摘录** | "NS Labels istio.io/dataplane-mode=ambient。其实我关心的一点是,无论打什么 label,在打上 label 时如何确保它是平滑起算的?业务 pod 必须重启 才能应用这个 ambient feature,那么我怎么去往这平滑的呢?" |
| **我的解读** | 这是**最关键的实操问题**。当前文档给的方案是:`kubectl label ns ... ambient` + `kubectl rollout restart deployment` — 这个过程**不是真正零中断**,而是依赖 K8s Deployment 滚动重启的"短暂窗口内中断"。 |
| **待解决问题** | 怎么让"切 ns label → 业务感知新模式"的窗口期尽可能短? |
| **当前已知手段** | (a) `kubectl rollout restart`(Deployment 滚动,默认 25% maxUnavailable + 25% maxSurge);(b) K8s `maxSurge=100%` + `maxUnavailable=0`(双倍副本窗口期零中断);(c) 用 Istio 的 `istio.io/rev` label 配合双 control plane(可避免重启 pod,见 05 文) |
| **状态** | 🔴 未解 — 需要确认 Lex 期望的"平滑"具体指什么(零中断 / 滚动 / 蓝绿) |
| **关联** | 04 文 §4 Step 4 + 05 文 §6 双 revision canary |
| **建议下一步** | 下一轮探索产出"滚动切换方式论"小节,具体说明:(a) Deployment 滚动 vs 双副本蓝绿;(b) 用 readiness probe 兜底;(d) 用 Service mesh 让流量切到 ambient 模式后再滚旧副本 |

#### 关注 4.2 — istio.io/dataplane-mode label 是否要重启 pod

| 字段 | 内容 |
|---|---|
| **原文摘录** | "业务 pod 必须重启才能应用这个 ambient feature" |
| **我的解读** | 硬限制 — Istio 文档原话 "The dataplane-mode label is checked at pod creation"。 |
| **待解决问题** | 无(硬限制,接受) |
| **状态** | 🟢 已决议 |
| **缓解手段** | canary ns 灰度 + Deployment 滚动 + readiness probe 兜底 |

---

### 📄 来自 `05-upgrade-strategies.md`

#### 关注 5.1 — Helm 拆分升级的优势

| 字段 | 内容 |
|---|---|
| **原文摘录** | "通过这个来看,好像赫尔的管理方式会更好;istiod 是 整个 mesh 配置的大脑,所有 sidecar / ztunnel / waypoint 都从 istiod 拉配置;istiod 重启 = 配置分发的'心跳'短暂中断" |
| **我的解读** | **Helm 拆分的核心价值是"独立升级"** — 升 ztunnel 不动 istiod,反之亦然。istiod 重启期间"新路由配置短暂不生效"(已建立连接不断)。 |
| **待解决问题** | 无(架构判断已锁) |
| **状态** | 🟢 已决议 |
| **决议** | Helm 拆 4 release + 双 revision canary 升级(详见 ADR §2.1 + 05 文 §6) |

#### 关注 5.2 — 双 revision 升级的"零中断"成立条件

| 字段 | 内容 |
|---|---|
| **原文摘录** | "双 revision canary = 新 revision 与老 revision 并存,namespace label 切流验证,零中断" |
| **我的解读** | "零中断"成立的前提是**老 revision 不退役**(新旧并存)+ namespace 通过 `istio.io/rev` label 切流。退役老 revision 时仍需重启 pod。 |
| **待解决问题** | 无 |
| **状态** | 🟢 已决议 |

---

### 📄 来自 `06-policy-capabilities.md`

#### 关注 6.1 — Policy 能力矩阵作为知识储备

| 字段 | 内容 |
|---|---|
| **原文摘录** | "在这里可以做对应的上传下载的一些 Policy 控制" |
| **我的解读** | 06 文是**知识储备** — 当前 dev 集群**不引入 policy**,但业务方未来有需求时(上传 / 下载 / header / JWT / 多租户隔离),可按 06 文落地。 |
| **待解决问题** | 业务方何时触发"需要 policy"?需要哪类场景? |
| **状态** | ⚪ 低优(业务需求驱动,不在本目录主线) |
| **关键约束**(回看) | 11 文 — 引入时**必须用 targetRefs**,**接受维护窗口** |

---

### 📄 来自 `08-ambient-networkpolicy.md`

#### 关注 7.1 — NetworkPolicy 必须做的工作

| 字段 | 内容 |
|---|---|
| **原文摘录** | "这里提到了一些对应的 network 调整,我也看到了,我们应该要做这一部分工作" |
| **我的解读** | 08 文是 NetworkPolicy 适配清单 — 任何 NP 必须 allow 15008 + `169.254.7.127` link-local IP(kubelet 探针)。 |
| **待解决问题** | (a) 当前 `k8s-gateway/02-namespaces/netpol-rule.md` 是命名规范,不是具体规则;**实际部署时每条 NP 必须按 08 文 §7 调整**;(b) 谁来调整?(c) 何时调整? |
| **状态** | 🔴 未解 — 需要 infra-gcp 与 devops-gcp 协作 |
| **关联** | 08 文 §7 本场景迁移前必改的 NetworkPolicy 清单 |
| **下一步** | 起草一份 NetworkPolicy 适配 checklist 文档(可作为 ADR-LOCAL-002) |

---

### 📄 来自 `10-waypoint-gateway-coexistence.md`

#### 关注 8.1 — 入口 Gateway 流量绕过 waypoint 的边界 ⭐

| 字段 | 内容 |
|---|---|
| **原文摘录** | "这部分提到一些东西,流量和南北流量的一些问题,但是在我们的实际过程中好像并没有看到一个这样的场景,所以说需要去询问一下是不是需要去支持或者是怎么支持" |
| **我的解读** | 10 文讲的关键问题:**入口 Gateway(sidecar)来的流量默认绕过 waypoint**。本场景目前**不需要让 ingress 走 waypoint**(没 L7 AuthZ 拦截需求),所以这个边界"没看到场景"是正常的。 |
| **待解决问题** | (a) 未来是否要让 ingress 走 waypoint?(b) 如果会,什么时候挂入。**结论:绝大多数情况都不需要做**。 |
| **状态** | 🔴 未解(场景未明) |
| **建议方向** | **默认不动** — 入口 Gateway 继续 sidecar 模式,业务 L7 拦截通过业务 ns 的 waypoint 实现;**只有当业务要求 ingress 流量也走 AuthZ / header 路由时才设 `istio.io/ingress-use-waypoint=true`** |
| **关联** | 10 文 §1 + ADR §2.2 |

---

### 📄 来自 `11-l7-zero-downtime-constraint.md`

#### 关注 9.1 — L7 zero-downtime 不可得的硬约束

| 字段 | 内容 |
|---|---|
| **原文摘录** | "官方原话:'Zero-downtime migration with L7 policies is **not currently supported**. Plan a maintenance window.'" |
| **我的解读** | 1.30 的**硬约束**,不是 best practice,是未实现功能。本场景**当前不卡**(没 L7 AuthZ),但未来引入时必须接受维护窗口。 |
| **待解决问题** | 无(硬约束已清) |
| **状态** | 🟢 已决议 |
| **缓解** | 用 `istio.io/dry-run=true` 演练;`targetRefs` 取代 `selector`;接受维护窗口 |

---

### 📄 来自 `12-revision-canary-mtls-compat.md`

#### 关注 10.1 — 双 revision 共存时的证书拓扑

| 字段 | 内容 |
|---|---|
| **原文摘录** | "但 不同 revision 的 istiod 用不同 Service name(如 istiod-1-30 vs istiod-1-31-canary),namespace 通过 istio.io/rev 选不同 Service" |
| **我的解读** | 双 revision 升级的 Service 隔离机制 — 老 revision `istiod-1-30` 与 canary revision `istiod-1-31-canary` 是**两个独立 Service**,namespace 通过 `istio.io/rev` label 选哪个。 |
| **待解决问题** | 无(拓扑已清) |
| **状态** | 🟢 已决议 |
| **关键事实** | 同 trust domain 下证书完全兼容(12 文 §1) |

---

## 2. 个人关注的"待解决"问题汇总(按优先级)

| # | 问题 | 优先级 | 阻塞哪阶段 |
|---|---|---|---|
| **Q1** | 当前 dev 集群是否已装 `istio-waypoint` GatewayClass? | 🔴 高 | Phase 1 实施前必须确认 |
| **Q2** | "平滑切换 ns label"的期望是哪种(零中断 / 滚动 / 蓝绿)? | 🔴 高 | Phase 2 实施前必须确认 |
| **Q3** | 入口 Gateway(`gatewayClassName: istio`)永远 sidecar?还是未来要切? | 🔴 中 | 决策 ADR §2.2 |
| **Q4** | GAR 镜像是否齐备(需要补 `ztunnel:1.30.3-distroless` 与 `install-cni:1.30.3-distroless`)? | 🔴 中 | Phase 1 实施前 |
| **Q5** | ingress 流量是否需要走 waypoint? | 🟡 低(默认不动) | Phase 4 L7 引入时 |
| **Q6** | NetworkPolicy 适配清单谁来做?何时做? | 🟡 中 | Phase 2 实施前 |
| **Q7** | Policy 知识库何时落地为实际 policy? | ⚪ 低 | 业务驱动 |

---

## 3. 待解决的问题 — 我建议的下一步动作

| # | 问题 | 建议下一步 |
|---|---|---|
| **Q1** | waypoint 存在性核对 | 起草一份"Phase 1 实施前 checklist"小节,包含 `kubectl get gatewayclass` / `kubectl get gateway -A` 等核对命令;或在 Phase 1 实施前直接确认 |
| **Q2** | 平滑切换期望 | 起草"滚动切换 vs 双 revision 蓝绿 vs 灰度切流"的对比小节;Lex 选定后回填 |
| **Q3** | 入口 Gateway 切换 | 默认锁"不动",但 Lex 需确认是否有未来切 `enterprise-agentgateway` 的需求(企业版时) |
| **Q4** | GAR 镜像补推 | 给 infra-gcp 发消息请求补推 2 个镜像;同时记录镜像清单到 ADR §6.3 |
| **Q5** | ingress 流量走 waypoint | 默认锁"不动";只在 Phase 4 引入 L7 时重新评估 |
| **Q6** | NetworkPolicy 适配 | 起草 ADR-LOCAL-002(NetworkPolicy 适配 checklist);infra-gcp 协作 |
| **Q7** | Policy 落地 | 等业务需求触发;06 文作为知识储备 |

---

## 4. ADR-LOCAL-001 调整建议(本清单驱动)

| ADR 章节 | 当前内容 | 调整建议 |
|---|---|---|
| §0 TL;DR | 已写 6 条 | ✅ 不变 |
| §2.2 决策 2(数据面模式) | "入口保留 sidecar,业务 ns 逐个迁 ambient" | **新增注脚**:Lex 个人关注点见 PERSONAL-FOCUS-LIST §关注 8.1(入口流量走 waypoint 默认不动) |
| §3 实施步骤 Phase 1 | "装 ambient 控制面" | **新增前置核对**:waypoint GatewayClass 是否已注册(Q1)+ GAR 镜像是否齐备(Q4) |
| §3 实施步骤 Phase 2 | "业务 ns 迁 ambient" | **新增平滑切换细节**:滚动 vs 蓝绿对比(Q2),写入 04 文 §6 |
| §6 blast radius 6.3 上下游 | GAR 镜像需求 | **新增明确动作**:需补推 `ztunnel:1.30.3-distroless` + `install-cni:1.30.3-distroless` 到 GAR |
| §8 交叉引用 | ADR-008 + ADR-LOCAL-002/003 候选 | **新增**:引用本清单 `PERSONAL-FOCUS-LIST.md`,作为 ADR 的"个人关注"附录 |

---

## 5. References

- 本目录所有 14 篇探索文档(已交叉引用)
- `ADR-LOCAL-001-migrate-minimal-to-ambient.md` §9(被本清单引用)
- 同仓库 `k8s-gateway/k8s-Gateay-README.md` — 已落地的 Gateway + ListenerSet 多租户架构
- 同仓库 `k8s-gateway/02-namespaces/netpol-rule.md` — 现有 NP 命名规范
- 同仓库 `~/git/knowledge/gcp/adr/008-static-pod-no-secret-configmap-k8s-137.md` — ADR 风格参考