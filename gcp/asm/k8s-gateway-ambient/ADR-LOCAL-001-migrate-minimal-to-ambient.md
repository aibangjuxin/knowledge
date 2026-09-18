# ADR-LOCAL-001: 从 Istio minimal profile 迁移到 ambient 模式的架构决策

> **Status**: Proposed · **Date**: 2026-09-17 · **Author**: architect-gcp · **Reviewers**: infra-gcp / devops-gcp / qa-gcp
>
> **配套文档**:
> - **`PERSONAL-FOCUS-LIST.md`** — Lex 个人关注清单(本 ADR 的"个人关切"附录,17KB,记录 10 个关注点与 7 个待解决问题)
> - 本目录其他 14 篇探索文档
>
> **作用域说明**:
> - 本 ADR 是 **`k8s-gateway-ambient/` 探索目录的本地 ADR**(编号前缀 `ADR-LOCAL-`)
> - **不占用主知识库 ADR 流水**(主 ADR 编号在 `~/git/knowledge/gcp/adr/`,目前到 ADR-008)
> - 后续若被正式批准,可重命名为 `ADR-009` 进入主 ADR 流
>
> **关联文档**(本目录 14 篇):
> - `01-ambient-vs-sidecar.md` — 本场景适配分析
> - `02-install-ambient-helm.md` — Helm 拆分安装步骤
> - `03-waypoint-design.md` — waypoint per-namespace 设计
> - `04-runtime-migration.md` — 业务 ns 迁移步骤
> - `05-upgrade-strategies.md` — 双 revision canary 升级
> - `06-policy-capabilities.md` — ambient 下 policy 能力矩阵
> - `07-13` — 7 篇深度探测
>
> **前置事实锁定**(用户已确认):
> - 当前集群运行 Istio **1.30.3**(不是 1.30.0,镜像 `1.30.3-distroless`)
> - 路由模型统一用 **HTTPRoute + K8s Gateway API**,**从未使用 VirtualService**
> - 入口架构用 **1 Gateway + N ListenerSet** 多租户模式(`k8s-gateway/03-gateway/abjx-gw-int.yaml`)
> - 集群是 GKE Standard `dev-lon-cluster-xxxxxx` @ `europe-west2`

---

## 0. TL;DR(30 秒读完)

| 简化解释 | 严格原话(一手来源) |
|---|---|
| **现状 = Istio 1.30.3 minimal profile,只装 istiod,镜像在 GAR 跑着。** | "minimal profile installs only the Istiod service." — [Istio Installation Profiles](https://istio.io/latest/docs/setup/install/multicluster/multi-primary/#customize-the-control-plane) |
| **ambient 模式 = 在 minimal 基础上加 3 个 chart:`istio-cni` + `ztunnel` (+ 可选 `waypoint`)** | "The ambient profile installs istiod, istio-cni, and ztunnel. Sidecar injection is disabled by default." — [Istio Ambient Install](https://istio.io/latest/docs/ambient/install/) |
| **你不能用 `istioctl install --set profile=minimal` 扩出 ambient — minimal profile 不支持 ambient** | minimal profile 只包含 istiod;切换到 ambient 必须显式安装 istio-cni / ztunnel,无法通过 `--set` 扩展 — 来源:`gke-ambient-waypoint-single.md` §4.5(Gloo 视角验证) + Istio chart 结构验证 |
| **本场景推荐 Helm 拆分 4 release:base + istiod + istio-cni + ztunnel** | "When installing with Helm, each chart is deployed as an independent release, enabling independent upgrades." — [Istio Helm Installation](https://istio.io/latest/docs/setup/install/helm/) |
| **入口 Gateway(sidecar) + 业务 ns(ambient)可混合共存** | "sidecar and ambient workloads can coexist during the process" — [Istio 1.30 release notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30/) |
| **L7 策略 zero-downtime 迁移不支持** | "Zero-downtime migration with L7 policies is **not currently supported**. Plan a maintenance window." — [Istio Sidecar to Ambient Migration](https://istio.io/latest/docs/ambient/install/migrate-from-sidecar/) |

**核心决策**:本场景采用 **Helm 拆分 4 release** + **双 revision canary 升级路径** + **入口 Gateway 不迁 ambient(保留 sidecar)** + **业务 ns 逐个迁 ambient**。

---

## 1. 背景 — 这到底在说什么

### 1.1 现状画像

```text
dev-lon-cluster-xxxxxx (GKE Standard @ europe-west2)
├─ istio-system
│  └─ istiod (2 副本, 100m-500m CPU, GAR 镜像 1.30.3-distroless)
├─ abjx-gw-int namespace
│  ├─ K8s Gateway API Gateway (gatewayClassName: istio)
│  │  └─ ListenerSet 多租户 (1 Gateway + N ListenerSet)
│  └─ HTTPRoute + TCPRoute (未使用 VirtualService)
└─ team-*-runtime namespaces
   └─ 业务 Pod (sidecar 注入)
      └─ 含 istio-proxy (proxyv2:1.30.3-distroless)
```

**当前安装命令**(摘自 `k8s-gateway/01-platform/install-istio.sh`):
```bash
istioctl install \
  --set profile=minimal \
  --set components.cni.enabled=false \
  --set values.global.platform=gke \
  --set hub="${HUB}" \
  --set tag=1.30.3-distroless \
  --set components.pilot.k8s.replicaCount=2 \
  ...
```

### 1.2 为什么想迁 ambient

| 驱动力 | 详情 |
|---|---|
| **资源效率** | sidecar 每个 pod 占 ~60-80Mi 内存 + ~10m CPU;ambient 把数据面挪到节点级 ztunnel,业务 pod 干净 |
| **零中断升级** | ambient + Helm 拆分 + 双 revision canary 实现控制面零中断升级 |
| **可演进性** | ambient 是官方主推方向,1.30 核心组件全 Stable;继续留在 sidecar = 长期技术债 |
| **架构对齐** | ambient 与 K8s Gateway API 设计哲学一致(都是 declarative + 标准 API);与 ListenerSet 多租户天然兼容 |

### 1.3 为什么**不**立即迁(约束)

| 约束 | 详情 |
|---|---|
| **L7 zero-downtime 不支持** | 1.30 官方明示硬约束 — 本场景目前没用 L7 AuthZ,所以**不卡**,但生产前必须重新评估 |
| **Multicluster ambient 仍 Alpha** | 1.30 Single-network multicluster ambient 是 Alpha,Multi-network 是 Beta — dev 集群是单集群,不卡 |
| **VirtualService 仍 Alpha** | 1.30 waypoint 下 VirtualService 仍 Alpha — 本场景用 HTTPRoute,不卡 |
| **`.istio.io/dataplane-mode=ambient` 与 `istio-injection=enabled` 互斥** | 同 ns 不能既有 ambient 又有 sidecar(否则未定义行为) — 需逐 ns 迁移 |

---

## 2. 决策 — 我们选了什么

### 2.1 决策 1:安装工具 — Helm 拆分 4 release

| 选项 | 评估 | 决策 |
|---|---|---|
| A. `istioctl install --set profile=ambient`(单 release) | 简单,但**不可拆开升级** — 升 ztunnel 必须重装 istiod | ❌ |
| B. Helm 拆分 `istio-base` / `istiod` / `istio-cni` / `ztunnel`(4 个独立 release) | **每组件独立升级**,可单独回滚,可加 revision label 做 canary | ✅ |
| C. Helm 装 istio-base + istio-cni + ztunnel,`istioctl` 装 istiod | 工具混用 → CRD 来源混乱 → 升级路径不清晰 | ❌ |

**最终决策**:**B. Helm 拆分 4 release**。

**理由**:
- 升 istiod 时不动 ztunnel(节点流量不重启)
- 升 ztunnel 时不动 istiod(配置分发不中断)
- 装新组件(如 waypoint chart)时不动 base(CRD 不变)
- 4 个独立 release 名 → 加 revision label → 双 canary 升级自然衔接

### 2.2 决策 2:数据面模式 — 入口保留 sidecar,业务 ns 迁 ambient

| 组件 | 决策 | 理由 |
|---|---|---|
| **入口 Gateway**(`gatewayClassName: istio`) | **保留 sidecar 模式** | 与 ListenerSet 多租户兼容;1.30 没有"ambient ingress gateway"标准做法;改动风险大 |
| **业务 namespace** | **逐 ns 迁 ambient** | 1.30 sidecar + ambient 可共存;可灰度、可回滚 |
| **waypoint** | **per-namespace 模式**,仅给需要 L7 策略的 ns 部署 | dev 集群当前无 L7 策略 = **暂不装 waypoint**;后续按需引入 |

**理由**:
- 入口 Gateway 不动 = 不破坏 ListenerSet 多租户架构
- 业务 ns 逐个迁 = 出问题只影响单个 ns
- waypoint 不预装 = 避免过度设计(07 文 §1 决策树)

### 2.3 决策 3:升级机制 — 双 revision canary

| 选项 | 评估 | 决策 |
|---|---|---|
| A. `istioctl upgrade`(单 revision 原地升) | 简单但 istiod 滚动重启期间新路由配置短暂不生效 | ❌ 生产不可接受 |
| B. Helm 单 release `--reuse-values --set tag=1.30.4` | 同 A,本质是原地升 | ❌ 同上 |
| C. Helm 双 release 不同 revision(`revision=1-30` + `revision=1-31-canary`) | **新旧并存**,namespace 通过 `istio.io/rev` label 切流,**零中断** | ✅ |
| D. `istioctl install --revision 1-31-canary` | 同 C 效果,但破坏 Helm 拆分原则 | ❌ 工具混用 |

**最终决策**:**C. Helm 双 release 不同 revision label**。

**理由**:
- 同 trust domain 下证书完全兼容(无 mTLS 断点,12 文已验证)
- 退役老 revision 前确认无 pod 引用即可
- 工具统一 = 维护简单

### 2.4 决策 4:L7 策略规划

| 子决策 | 决策 |
|---|---|
| 本次迁移**不**引入 L7 AuthZ | dev 集群当前无需求,先固化 ambient 模式 + 收集需求 |
| 未来引入时**必须**用 `targetRefs` 绑 Service / Gateway(waypoint) | `selector.matchLabels` 在 ambient 下失效;11 文硬约束 |
| 文件上传 / header 限制 / JWT 验证 | 06 文已规划能力矩阵,实际落地时按需引入 |
| **绝不**写 selector-based AuthZ 然后迁移 | 11 文硬约束 — L7 zero-downtime 不支持 |

---

## 3. 实施步骤 — 何时做什么

### 3.1 Phase 0(当前)— 准备

| 步骤 | 状态 |
|---|---|
| 探索 ambient / revision / L7 边界 | ✅ 本目录 14 篇文档 |
| 镜像 tag 统一为 `1.30.3-distroless` | ✅ 已统一 |
| 把 `k8s-gateway/01-platform/install-istio.sh` 标记为"ambient 迁移完成前不可删除" | ⏳ 待做 |

### 3.2 Phase 1 — 装 ambient 控制面(单 revision)

**前置**:`ambient` profile 需额外安装 3 个 chart(`istio-cni` + `ztunnel` + 可选 `waypoint`),不能从 minimal 扩出。

**操作**(详见 `02-install-ambient-helm.md` §9):

```bash
# Step 1: istio-base
helm upgrade --install istio-base \
  oci://gcr.io/istio-release/charts/base \
  --namespace istio-system --version 1.30.3 \
  -f values/base.yaml

# Step 2: istiod(覆盖原 minimal 装的那个)
helm upgrade --install istiod \
  oci://gcr.io/istio-release/charts/istiod \
  --namespace istio-system --version 1.30.3 \
  -f values/istiod.yaml

# Step 3: istio-cni
helm upgrade --install istio-cni \
  oci://gcr.io/istio-release/charts/cni \
  --namespace istio-system --version 1.30.3 \
  -f values/cni.yaml

# Step 4: ztunnel
helm upgrade --install ztunnel \
  oci://gcr.io/istio-release/charts/ztunnel \
  --namespace istio-system --version 1.30.3 \
  -f values/ztunnel.yaml
```

**验证**:04 文 §7 验证清单(ztunnel DaemonSet 每节点 1 pod + istio-cni DaemonSet + `istio-waypoint` GatewayClass 注册)。

**回滚**:`helm uninstall` 4 个 release,`bash install-istio.sh` 回到 minimal。

### 3.3 Phase 2 — 业务 ns 迁 ambient

**前置**:
- 选 canary ns(非关键业务)
- NetworkPolicy 检查(08 文 §7 — 必须 allow 15008)
- 业务 readiness probe 检查(04 文 §3.1 — 不能硬编码 15020)

**操作**(详见 `04-runtime-migration.md`):

```bash
# Step 1: 选 canary ns
CANARY_NS="team-canary-runtime"

# Step 2: 改 dataplane-mode label
kubectl label namespace ${CANARY_NS} \
  istio.io/dataplane-mode=ambient --overwrite

# Step 3: 移除 sidecar 注入
kubectl label namespace ${CANARY_NS} \
  istio-injection- --overwrite

# Step 4: 滚动重启(必须,业务 pod 必须重建才感知新模式)
kubectl rollout restart deployment -n ${CANARY_NS}

# Step 5: 验证(04 文 §7 验证清单)
kubectl get pod -n ${CANARY_NS} -o jsonpath='{.items[0].spec.containers[*].name}'
# 预期:只有业务容器,无 "istio-proxy"
```

**观察期**:1-2 周,监控 pod 启动延迟 / 错误率 / mTLS 握手成功率。

**回滚**:
```bash
kubectl label namespace ${CANARY_NS} \
  istio.io/dataplane-mode- \
  istio-injection=enabled --overwrite
kubectl rollout restart deployment -n ${CANARY_NS}
```

### 3.4 Phase 3 — 双 revision canary 升级(预留,1.31 升版时启用)

**前置**:dev 集群 ambient 跑通至少 1 个月。

**操作**(详见 `05-upgrade-strategies.md` §6):

```bash
# Step 1: 装 canary revision
helm upgrade --install istiod-1-31-canary \
  oci://gcr.io/istio-release/charts/istiod \
  --namespace istio-system --version 1.31.3 \
  -f values/istiod-1-31.yaml    # 含 revision: "1-31-canary"

# Step 2: canary ns 切到新 revision
kubectl label namespace ${CANARY_NS} istio.io/rev=1-31-canary --overwrite
kubectl rollout restart deployment -n ${CANARY_NS}

# Step 3: 观察 1-2 周
# Step 4: 全量切流
for ns in $(kubectl get ns -l istio.io/dataplane-mode=ambient -o name | cut -d/ -f2); do
  kubectl label "$ns" istio.io/rev=1-31-canary --overwrite
  kubectl rollout restart deployment -n "$ns"
  sleep 60
done

# Step 5: 退役老 revision
helm uninstall istiod -n istio-system
```

### 3.5 Phase 4 — 引入 L7 策略(按需,触发条件)

**触发条件**:任何业务需求出现以下场景之一:
- 文件上传 / 下载限制(06 文 §4)
- Header 路由 / API key / JWT(06 文 §5/§7)
- 跨 namespace 隔离(06 文 §6)

**前置硬约束**(11 文):
- 所有 AuthZ 必须用 `targetRefs`,**不写 `selector` 版本**
- 切换 ambient 时的 L7 AuthZ 必须做 `istio.io/dry-run=true` 演练
- 接受 L7 zero-downtime 不可得,有变更窗口

---

## 4. 不选的方案 — 我们排除了什么

### 4.1 不选 A — `istioctl install --set profile=ambient`

| 理由 | 详情 |
|---|---|
| **不可拆开升级** | istioctl 单 release 管理整个控制面;升 ztunnel 必须重装 istiod |
| **不可双 revision** | istioctl 装多 revision 时,只支持同 chart 不同 revision label;但其他组件(cni/ztunnel)的管理归属混乱 |
| **不符合 02 文架构** | 本目录已确立 Helm 拆分原则 |

### 4.2 不选 C — 工具混用(istioctl 装 istiod,Helm 装其他)

| 理由 | 详情 |
|---|---|
| **CRD 来源混乱** | 同一集群的 CRD 可能来自 istioctl 或 Helm,后续升级时无法判断归属 |
| **故障排查复杂** | 出问题时要先判断"这个 CRD 是谁装的" |
| **违背单一管理工具原则** | 后续所有团队成员都要懂两套工具 |

### 4.3 不选 VirtualService

**前置事实**:本场景从来没用过 VirtualService,统一用 HTTPRoute。

| 理由 | 详情 |
|---|---|
| **VirtualService ambient 下仍 Alpha** | 1.30 Waypoints:VirtualService 状态是 Alpha — 不生产 |
| **HTTPRoute 是 K8s 标准 API** | K8s Gateway API 的 Stable channel,符合云原生趋势 |
| **ListenerSet 多租户与 HTTPRoute 兼容** | 已验证 |
| **不需要切换成本** | 当前 0 个 VirtualService = 0 切换工作 |

### 4.4 不选 Multicluster ambient(目前)

| 理由 | 详情 |
|---|---|
| **Single-network multicluster ambient 仍 Alpha** | 1.30 状态 |
| **Multi-network multicluster ambient Beta 但官方说"not ready for production"** | 13 文 §0 引用 |
| **dev 集群是单集群** | 当前无 multicluster 需求 |

---

## 5. 后果 — 这么做会换来什么、失去什么

### 5.1 收益

| 收益 | 量化 |
|---|---|
| **业务 pod 内存节省** | 每个 pod 省 ~60-80Mi sidecar 内存 |
| **业务 pod 启动加速** | 不再等 envoy 启动 |
| **控制面零中断升级** | 双 revision canary 实现 |
| **L7 能力按需部署** | waypoint 只在需要 ns 装 |
| **架构与社区方向对齐** | ambient 是 Istio 主推方向 |
| **HTTPRoute + ListenerSet 不破坏** | 决策与现有架构完全兼容 |

### 5.2 代价

| 代价 | 详情 |
|---|---|
| **首次部署复杂度上升** | 从单 istioctl 命令 → 4 个 Helm release |
| **每个组件都要维护 values** | 02 文已提供 4 个 values 骨架 |
| **升级流程变长** | 从 `istioctl upgrade` → 双 revision canary(5 步) |
| **NetworkPolicy 必须改** | 任何 NP 必须 allow 15008 + 169.254.7.127 |
| **业务 readiness probe 可能要改** | 不能 hardcode 15020(envoy admin port) |
| **L7 zero-downtime 不支持** | 未来引入 L7 时必须有变更窗口 |
| **入口 Gateway 仍 sidecar** | 集群内数据面模式不统一(可接受,但运维要理解) |

### 5.3 风险

| 风险 | 缓解 |
|---|---|
| **ztunnel 升级影响长连接** | 节点级守护更新,影响限于节点内连接;不重启业务 pod |
| **waypoint 滚动升级 L7 短暂失效** | PDB + 滚动策略;后续引入 L7 时再细看 |
| **业务 pod 改 ambient 后启动失败** | 04 文 §6 回滚预案;canary ns 选择降低爆炸半径 |
| **未来 1.31+ ambient 行为变化** | 07 文跟踪;Phase 4 引入 L7 前重新评估 1.30.3 GA |
| **业务代码假设 15020 / 15001 等 mesh 端口** | 09 文 §1.2 — 应用代码不应 listen 这些端口;04 文 §3.1 readiness probe 检查 |

---

## 6. blast radius — 这影响谁、影响什么

### 6.1 集群范围

| 集群/namespace | 影响 |
|---|---|
| **`dev-lon-cluster-xxxxxx`** | **唯一**目标集群 |
| **`istio-system`** | 控制面变更(装 ambient 组件) |
| **`abjx-gw-int`**(ingress ns) | **不变**(保留 sidecar) |
| **`abjx-listenerset-int`** | **不变**(ListenerSet 多租户架构不动) |
| **`team-*-runtime`**(业务 ns) | **逐 ns 迁移** ambient |

### 6.2 业务影响窗口

| 阶段 | 业务影响 | 时长 |
|---|---|---|
| Phase 1(装 ambient 控制面) | **零业务影响**(控制面扩组件,入口 Gateway + 业务 pod 不动) | 0 |
| Phase 2(业务 ns 迁 ambient) | **canary ns 业务 pod 短暂重启**(滚动,每 pod 几秒中断) | 每个 ns 几十分钟 |
| Phase 3(双 revision 升级) | **零业务影响**(只是控制面切流) | 0 |
| Phase 4(引入 L7) | **按 L7 复杂度**(目前不涉及) | 待定 |

### 6.3 上下游依赖

| 依赖 | 影响 |
|---|---|
| **GAR 镜像** | 已有 `proxyv2:1.30.3-distroless` / `pilot:1.30.3-distroless`;**可能需要补 `ztunnel:1.30.3-distroless` 与 `install-cni:1.30.3-distroless`** |
| **Helm 仓库访问** | 需访问 `gcr.io/istio-release/charts` |
| **K8s Gateway API CRDs** | 已有 v1.5.1 |
| **GKE 节点 OS** | `cos_containerd`(默认)— 支持 |

---

## 7. 验证 — 怎么证明做对了

### 7.1 Phase 1 验证清单

```bash
# 控制面
kubectl get pods -n istio-system
# 预期:istiod (2 副本) + istio-cni DaemonSet (每节点) + ztunnel DaemonSet (每节点)

# GatewayClass
kubectl get gatewayclass
# 预期:istio (原 sidecar) + istio-waypoint (新增)

# ambient 关键 CRD
kubectl get crd | grep -E "waypoint|ztunnel"
```

### 7.2 Phase 2 验证清单

```bash
# canary ns 业务 pod 无 sidecar
kubectl get pod -n ${CANARY_NS} -o jsonpath='{.items[0].spec.containers[*].name}'
# 预期:只有业务容器

# pod 内 iptables(zu tunn 注入的规则)
kubectl debug <pod> -it --image docker.io/istio-base --profile=netadmin \
  -n ${CANARY_NS} -- iptables-save | grep -E "ISTIO|15008"

# mTLS 生效(抓包应见密文)
kubectl exec <pod-a> -n ${CANARY_NS} -- tcpdump -i any -nn port 8080 2>&1 | head

# 证书签发
istioctl proxy-config secret <ztunnel-pod> -n istio-system
```

### 7.3 Phase 3 验证清单

```bash
# 双 revision 并存
kubectl get pods -n istio-system -l app=istiod
# 预期:istiod-1-30 + istiod-1-31-canary 双 2 副本

# canary ns 切流验证
istioctl proxy-config endpoint <pod>.<canary-ns> | grep istiod
# 预期显示 istiod-1-31-canary

# 退役前确认无 pod 引用老 revision
kubectl get pods -A -o json | jq -r '.items[].metadata.labels["istio.io/rev"] // "<none>"' | sort | uniq -c
# 预期:全部 1-31-canary
```

---

## 8. 关联决策记录(交叉引用)

| 已存在的相关 ADR | 关联点 |
|---|---|
| (主知识库) ADR-008:Static Pod + Secret/ConfigMap K8s 1.37 | 不直接关联(我们用 GKE Standard,Google 维护控制面) |

| 本目录其他 ADR 候选 | 状态 |
|---|---|
| ADR-LOCAL-002:业务 namespace 从 sidecar 迁 ambient 的运维手册 | 待起草 |
| ADR-LOCAL-003:HTTPRoute vs VirtualService 选型记录 | 待起草(本场景默认 HTTPRoute,可作为 ADR 形式固化) |
| **PERSONAL-FOCUS-LIST.md**(本 ADR 的"个人关切"附录) | ✅ **已建立** — 10 个关注点 + 7 个待解决问题(Q1-Q7) |
| ADR-LOCAL-004(候选):Phase 1 实施前 checklist(waypoint 存在性核对 + GAR 镜像补推) | 待起草(Q1 + Q4) |
| ADR-LOCAL-005(候选):NetworkPolicy 适配 checklist(08 文 §7 工作清单) | 待起草(Q6,需 infra-gcp 协作) |

### 8.1 个人关注点摘要(摘自 PERSONAL-FOCUS-LIST)

| # | 关注点 | 状态 | 决策 / 行动 |
|---|---|---|---|
| 1.1 | 入口 Gateway 是否切 `istio-waypoint` 或 `enterprise-agentgateway`? | 🔴 未解 | **默认不动**(`gatewayClassName: istio` 保留,详见 10 文 §3) |
| 1.2 | AuthZ/PA 用 `targetRefs` 取代 `selector` | 🟢 已决议 | 未来所有 policy 必须 `targetRefs` |
| 2.1 | minimal 不能扩 ambient | 🟢 已决议 | Helm 拆 4 release |
| 2.2 | istioctl profile=ambient vs Helm 拆分 | 🟢 已决议 | Helm 拆 4 release |
| 2.3 | Helm 拆 4 步安装命令 + values 骨架 | 🟡 已写待镜像 | 需补推 `ztunnel:1.30.3-distroless` 与 `install-cni:1.30.3-distroless` 到 GAR |
| 3.1 | waypoint 资源存在性核对 | 🔴 未解 | Phase 1 实施前 `kubectl get gatewayclass` 确认 |
| 3.2 | waypoint ≠ 入口 Gateway(角色定位) | 🟢 已决议 | 见 03 文 + 10 文 |
| 3.3 | waypoint podAntiAffinity 自动 | 🟢 已决议 | controller 1.27+ 默认加,无需手动 |
| 3.4 | 何时不装 waypoint | 🟡 已决议(暂不装) | 当前 dev 集群无 L7 需求,暂不装 |
| 4.1 | ns label "平滑"切换 ⭐ | 🔴 未解 | 见 PERSONAL-FOCUS-LIST §关注 4.1(关键问题) |
| 4.2 | dataplane-mode 必须重启 pod | 🟢 已决议 | 硬限制,接受;Deployment 滚动 + readiness probe 兜底 |
| 5.1 | Helm 拆分升级优势 | 🟢 已决议 | 独立升级控制面组件 |
| 5.2 | 双 revision 零中断成立条件 | 🟢 已决议 | 老 revision 不退役 + label 切流 |
| **5.3** | **revision 在 K8s 资源层是什么?(完整链路)** | 🟢 **已澄清** | **见 15 文 §2-4** — Deployment + Service + Webhook + Revision Tag 四件套 |
| 6.1 | Policy 能力矩阵作为知识储备 | ⚪ 低优 | 业务驱动,06 文为知识储备 |
| 7.1 | NetworkPolicy 适配工作 | 🔴 未解 | 起草 ADR-LOCAL-005 + infra-gcp 协作 |
| 8.1 | 入口 Gateway 流量绕过 waypoint ⭐ | 🟡 默认不动 | 见 10 文 §1;除非未来 ingress 也需 L7 拦截 |
| 9.1 | L7 zero-downtime 不可得 | 🟢 已决议 | 硬约束,接受维护窗口 |
| 10.1 | 双 revision 共存证书拓扑 | 🟢 已决议 | 同 trust domain 兼容 |

---

## 9. 严格定义 vs 简化解释(关键限定)

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **Ambient mode** | "无 sidecar 的 mesh" | "Ambient mode is a mesh data plane mode that uses node-level ztunnel proxies for L4 mesh encryption and namespace/service-level waypoint proxies for L7 processing, removing the need for per-pod sidecar injection." — [Istio Ambient docs](https://istio.io/latest/docs/ambient/) |
| **ztunnel** | "节点级 mTLS 代理" | "ztunnel is a per-node mTLS data plane component, implemented in Rust, that handles L4 encrypted traffic between workloads in the mesh." — [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/) |
| **waypoint** | "namespace 级 L7 代理" | "A waypoint proxy is a deployment of an Envoy proxy that handles L7 processing for workloads in a namespace or service." — [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/) |
| **HBONE** | "ztunnel 之间隧道协议" | "HBONE (HTTP-Based Overlay Network Environment) is the HTTP/2 CONNECT-based tunneling protocol used by ztunnel." — Istio docs |
| **Revision** | "istiod 的版本标签" | "A revision is a label applied to istiod (and dependent charts) that namespaces opt into via the `istio.io/rev` label." — [Istio Canary Upgrades](https://istio.io/latest/docs/setup/upgrade/canary/) |
| **`istio.io/dataplane-mode=ambient`** | "加入 ambient" | "Namespaces labeled with `istio.io/dataplane-mode=ambient` opt into ambient mesh; workloads in those namespaces do not require sidecar injection." — Istio Ambient docs |
| **`istio.io/use-waypoint`** | "ns 走 waypoint" | "The `istio.io/use-waypoint` label governs east-west traffic; requests from other pods in the mesh to the labeled namespace/service/workload are sent through the destination waypoint." — [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/) |
| **`istio.io/ingress-use-waypoint`** | "ingress 走 waypoint" | "Set `istio.io/ingress-use-waypoint=true` to direct ingress traffic through the same waypoint as mesh traffic." — Istio Waypoint docs |

---

## 10. 时间线

| 日期 | 事件 |
|---|---|
| 2026-09-17 | 本 ADR 起草,本目录 14 篇探索文档完成 |
| (未来)Phase 1 | 装 ambient 控制面(02 文) |
| (未来)Phase 2 | 业务 ns 逐个迁 ambient(04 文) |
| (未来)Phase 3 | 1.31 升级时启用双 revision canary(05 文) |
| (未来)Phase 4 | 按需引入 L7 策略(06 文),用 targetRefs |

---

## 11. References

### 11.1 官方权威来源

- [Istio Ambient 总览](https://istio.io/latest/docs/ambient/)
- [Istio Ambient Install](https://istio.io/latest/docs/ambient/install/)
- [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/)
- [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/)
- [Istio Sidecar to Ambient Migration](https://istio.io/latest/docs/ambient/install/migrate-from-sidecar/)
- [Istio Ambient and Kubernetes NetworkPolicy](https://istio.io/latest/docs/ambient/usage/networkpolicy/)
- [Istio Ztunnel Traffic Redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/)
- [Istio Helm Installation](https://istio.io/latest/docs/setup/install/helm/)
- [Istio Canary Upgrades](https://istio.io/latest/docs/setup/upgrade/canary/)
- [Istio 1.30.3 Patch Notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.3)
- [Istio 1.30 Feature Status](https://istio.io/latest/docs/releases/feature-status/)
- [Istio Ambient Multi-Network Multicluster Blog](https://istio.io/latest/blog/2026/ambient-multinetwork-multicluster-beta/)
- [Istio AuthorizationPolicy reference](https://istio.io/latest/docs/reference/config/security/authorization-policy/)
- [Istio PeerAuthentication reference](https://istio.io/latest/docs/reference/config/security/peer_authentication/)

### 11.2 本目录关联文档

- `k8s-gateway-ambient/01-ambient-vs-sidecar.md` — 概览
- `k8s-gateway-ambient/02-install-ambient-helm.md` — Phase 1 详细步骤
- `k8s-gateway-ambient/03-waypoint-design.md` — waypoint 设计
- `k8s-gateway-ambient/04-runtime-migration.md` — Phase 2 详细步骤
- `k8s-gateway-ambient/05-upgrade-strategies.md` — Phase 3 详细步骤
- `k8s-gateway-ambient/06-policy-capabilities.md` — Phase 4 规划
- `k8s-gateway-ambient/07-feature-status-1.30.3.md` — GA/Beta/Alpha 状态矩阵
- `k8s-gateway-ambient/08-ambient-networkpolicy.md` — NetworkPolicy 协同
- `k8s-gateway-ambient/09-ztunnel-redirection-app-compat.md` — 应用代码兼容
- `k8s-gateway-ambient/10-waypoint-gateway-coexistence.md` — Gateway + waypoint 共存
- `k8s-gateway-ambient/11-l7-zero-downtime-constraint.md` — 🚨 硬约束
- `k8s-gateway-ambient/12-revision-canary-mtls-compat.md` — 双 revision 证书兼容
- `k8s-gateway-ambient/13-multicluster-ambient-status.md` — 多集群状态
- `k8s-gateway-ambient/14-parametersRef-vs-targetRefs-concept-clarity.md` — 两个 Refs 字段概念澄清
- `k8s-gateway-ambient/15-istio-revision-mechanism-explained.md` — revision 机制详解(K8s 资源管理视角)
- `k8s-gateway-ambient/16-revision-like-patterns-cloud-native.md` — revision 类机制横向对比(6+ 种云原生模式)

### 11.3 现有架构

- `k8s-gateway/01-platform/install-istio.sh` — 现状 minimal install 脚本
- `k8s-gateway/k8s-Gateay-README.md` — 已落地的 Gateway + ListenerSet 多租户架构
- `k8s-gateway/03-gateway/abjx-gw-int.yaml` — 入口 Gateway 配置
- `k8s-gateway/02-namespaces/netpol-rule.md` — NetworkPolicy 命名规范
- `~/git/knowledge/gcp/asm/authorizationPolicy-capabilities-and-use-cases.md` — sidecar 模式 AuthZ 能力矩阵
- `~/git/knowledge/gcp/asm/peerAuthentication-capabilities-and-use-cases.md` — sidecar 模式 PA 能力矩阵
- `~/git/knowledge/gcp/asm/gloo/gke-ambient-waypoint-single.md` — Gloo 视角单集群 ambient 探索
- `~/git/knowledge/gcp/asm/gloo/gke-ambient-waypoint-multip.md` — Gloo 视角多集群 ambient 探索
- `~/git/knowledge/gcp/asm/gloo/waypoint.md` — Waypoint 详解
- `~/git/knowledge/gcp/adr/008-static-pod-no-secret-configmap-k8s-137.md` — 主知识库 ADR 风格参考

---

## 12. 决策者签字(模板)

| Role | Name | Date | Decision |
|---|---|---|---|
| Architect | <DECISION_MAKER> | 2026-09-17 | Proposed |
| Infra Lead | <YOUR_USER_ACCOUNT>@<YOUR_DOMAIN> | | ⬜ Approved / ⬜ Rejected |
| DevOps Lead | | | |
| QA Lead | | | |