# Solo Istio Ambient 长期维护与零停机升级 —— 策略探索

> **性质**：探索文档。不含可直接执行的实施方案，命令仅用于说明机制与风险点，实施前需在 staging 复核。
> **适用基线**：GKE + Solo 分发版 Istio ambient，`us-docker.pkg.dev/soloio-img/istio`，tag `1.30.3-distroless`（standard 发行版，不带 `-solo`，无需 license）
> **事实核验日期**：2026-10-11。文中所有"官方原文"均为当日从一手来源抓取，非本地文档转述。

---

## 1. 先纠正三个认知偏差

探索前我原本持有的三个判断，在核验一手来源后**全部不成立**。这三条直接决定策略选择，所以放在最前面。

### 1.1 「Solo 文档 = 你能用的东西」——错，你用的是 standard 发行版

Solo 文档站上大量"增强升级能力"的描述，**是 `-solo` 后缀版本专有的**，与你无关：

| Solo 文档的描述 | 适用发行版 | 你（无 `-solo`）是否可用 |
|---|---|---|
| `istio-cni` 升级时创建 **stub CNI plug-in**（`AGENT_UPGRADE_ID` 机制），阻塞节点上 pod 启动直到新 CNI 就绪 | `-solo` | **否** —— 见 §1.1.1 |
| `n-4` 安全补丁支持窗口 | `-solo` | **否** —— 社区 Istio 的 `n-1` + 6 周适用 |
| 多集群 ambient peering（`ServiceEntry` 远端） | `-solo` + Enterprise license | **否** |
| Gloo Operator / SPIRE CA / Solo UI / HTTP observability | `-solo` + license | **否** |

Solo 官方对 `-solo` 的定义：

> **Solo**: An enterprise distribution of the community Istio project with additional security patches, as well as certain Envoy filters to enable Solo Enterprise for Istio features, such as support for deploying Istio service meshes in ambient mode. You must use the `solo` image to use these features. — [docs.solo.io/istio/1.30.x](https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/)

注意 "You **must** use the `solo` image"。而你用的是 `1.30.3-distroless`（无 `-solo`）。

**这张表就是全文最重要的一张表。** 它意味着：升级策略必须按**社区 Istio 1.30 ambient** 的规则设计，任何"Solo 有个更安全的升级机制"的想法在你这套镜像上都是空的。

#### 1.1.1 stub CNI plug-in 在开源源码里不存在（源码级验证）

Solo 文档 [Upgrade → Considerations](https://docs.solo.io/istio/1.30.x/ambient/operations/upgrade/manual/) 原文：

> **CNI upgrades** — In an ambient installation, the `istio-cni` pods are enhanced for safe in-place upgrades. When `istio-cni` is scheduled for removal, it determines whether an upgrade is in process by checking the value of `AGENT_UPGRADE_ID` in the `istio-cni` ConfigMap against its internal upgrade ID. If the removal is due to an upgrade, `istio-cni` creates a "stub" CNI plug-in in its place on the node.

我在 `istio/istio` **`release-1.30` 分支源码**中检索该机制：

```
$ grep -rn 'AGENT_UPGRADE_ID' istio-release-1.30/          # 全树，零命中
$ grep -rni 'upgrade.id|upgradeID' istio-release-1.30/cni/ # 零命中
```

同时，release-1.30 的 CNI chart 渲染的 ConfigMap 全部 key 为：

```
CURRENT_AGENT_VERSION / AMBIENT_ENABLED / AMBIENT_ENABLEMENT_SELECTOR / AMBIENT_DNS_CAPTURE /
AMBIENT_IPV6 / AMBIENT_RECONCILE_POD_RULES_ON_STARTUP / ENABLE_AMBIENT_DETECTION_RETRY /
CNI_CONF_NAME / ISTIO_OWNED_CNI_CONFIG / CHAINED_CNI_PLUGIN / EXCLUDE_NAMESPACES /
REPAIR_* / NATIVE_NFTABLES
```

**没有 `AGENT_UPGRADE_ID`**，也没有任何 stub plug-in 逻辑。这是 `-solo` 分支独有的 backport。

**实际影响**：升级 istio-cni 时，DaemonSet 会在**没有 stub 保护的情况下**滚动重启。任一节点上恰好有新 pod 调度，会命中 `istio-cni` 已被删除、CNI 链里无 Istio 插件的窗口 → 该 pod 可能**不被注入 iptables 规则** → 加入 ambient mesh 但流量不经 ztunnel。这是你的环境里一个真实的、当前没有任何防护的故障模式。

---

### 1.2 「ambient 升级 = 标准 Istio revision canary」——错，ztunnel 无法 revision 蓝绿

社区 Istio 提供了 well-worn 的 [revision canary](https://istio.io/v1.30/docs/setup/upgrade/canary/) 机制：并存两套控制面，`istio.io/rev` label 决定每个工作负载归哪个控制面管，逐 namespace 灰度。

**但这个机制在 ambient 下的数据面部分被釜底抽薪了。** release-1.30 的 ztunnel chart 源码：

```yaml
# manifests/charts/ztunnel/templates/daemonset.yaml
metadata:
  name: {{ include "ztunnel.release-name" . }}      # 默认字面量 "ztunnel" —— 资源名不含 revision
  labels:
    app.kubernetes.io/name: ztunnel
spec:
  selector:
    matchLabels:
      app: ztunnel                                   # ← selector 不含 revision
```

`resourceName` 默认值为空，`_helpers.tpl` 中为 `.Values.resourceName | default "ztunnel"`。**DS 名固定为 `ztunnel`，label selector 固定为 `app: ztunnel`，两者都不含 revision。**

这意味着第二个 DaemonSet 若以 `--set revision=1-31-0` 安装，会**与第一个 DaemonSet 的 selector 完全重叠**——K8s 报 `selector does not match template labels` 或直接互相抢占节点。**ztunnel 在架构上无法蓝绿。**

对比 istiod（同一个 chart 家族）：

```yaml
# istio-discovery/templates/deployment.yaml:7
name: istiod{{- if not (eq .Values.revision "") }}-{{ .Values.revision }}{{- end }}
```

istiod 的资源名和 selector **都带 revision**，所以控制面可以并存。**控制面能灰度，数据面不能。**

> 一句话：**ambient 模式下 revision canary 只能保护 istiod 和 waypoint/gateway；ztunnel 是"一刀切"的。**

这直接决定了 §4 的策略矩阵。

---

### 1.3 「Helm 更方便」——对控制面成立，对 ztunnel 不成立

社区 ambient 升级指南 [Upgrade with Helm](https://istio.io/v1.30/docs/ambient/upgrade/helm/) 和 Solo 的 in-place 指南都只覆盖 `helm upgrade`（原地覆盖同一个 release），**没有任何一页文档提供 ztunnel 蓝绿步骤**。这与 §1.2 的源码事实一致：文档没有，是因为做不到。

对 ztunnel，Helm 唯一能调的旋钮是 `terminationGracePeriodSeconds`（values.yaml 中定义其语义）：

```yaml
# manifests/charts/ztunnel/values.yaml:97-101
# This value defines:
# 1. how many seconds kube waits for ztunnel pod to gracefully exit before forcibly terminating it (this value)
# 2. how many seconds ztunnel waits to drain its own connections (this value - 1 sec)
# Default K8S value is 30 seconds
terminationGracePeriodSeconds: 30
```

以及已默认开启的滚动策略（values.yaml:142-146）：

```yaml
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
```

`maxUnavailable: 0` 保证了**不会有两个 ztunnel 同时缺席**——但它管不了"单个节点上长连接被硬切"这件事。这是**排空**问题，不是**调度**问题。

> 注意：**ztunnel chart 不渲染 PodDisruptionBudget**（`templates/` 目录仅 7 个文件，无 `poddisruptionbudget.yaml`），而 istiod chart **有**（`istio-discovery/templates/poddisruptionbudget.yaml`，默认 `minAvailable: 1`）。这个不对称是 §4.2 判断的依据之一。

---

## 2. 组件与影响面

| 组件 | 部署形态 | revision 隔离 | Chart 内置 PDB | 升级中断模型 |
|---|---|---|---|---|
| istio-base（CRD） | Cluster-scoped | ❌ 全局单份 | N/A | 只增不删，风险低；标准回退手段 |
| Gateway API CRD | Cluster-scoped | ❌ 全局单份 | N/A | 同上 |
| istiod | Deployment | ✅ 名+selector 带 rev | ✅ `minAvailable: 1` | 滚动，无状态，可灰度 |
| istio-cni | DaemonSet | ❌ 名字固定 | ❌ | **窗口内新 pod 可能漏注入**（§1.1.1） |
| ztunnel | DaemonSet | ❌ 名+selector 固定 | ❌ | **节点上所有长连接被硬切** |
| waypoint | Deployment | ✅ 由 istiod 依 `istio.io/rev` 渲染 | 需自建 | 滚动，受控 |
| ingress gateway | Deployment | ✅ 同上 | 需自建 | 滚动，受控 |

`istio.io/dataplane-mode: ambient` 与三个 waypoint label（`istio.io/use-waypoint`、`istio.io/ingress-use-waypoint`）都是**纯 label 驱动**，不绑定任何版本。升级不需要动它们——**但它们是你后续做 revision 灰度的抓手**（见 §5.3）。

---

## 3. 版本生命周期：先确认你的紧迫度

从 [Solo 版本矩阵](https://docs.solo.io/istio/1.30.x/ambient/about/images/versions/) 与 [Istio 官方支持周期](https://istio.io/v1.30/docs/releases/supported-releases/)：

| 版本 | 社区是否支持 | 发布日期 | EOL | 支持的 K8s |
|---|---|---|---|---|
| 1.30 | **Yes** | 2026-05-14 | ~Dec 2026 | 1.32–1.36 |
| 1.29 | Yes | 2026-02-16 | ~Oct 2026 | 1.31–1.35 |
| 1.28 | No | 2025-11-05 | 2026-07-01 | — |

**两个对长期维护至关重要的事实：**

1. **1.30 当前是最新稳定版，社区仍支持。** 不是被淘汰的版本。你没有"急着跑在 unsupported 上"的压力。
2. **但你没有 Solo 的 `n-4` 缓冲。** `-solo` 后缀带来 9 个月额外补丁窗口；`standard` 发行版只能享受社区的 `n-1` + 6 周。**按社区节奏，1.30 大约在 1.32 发布后 6 周（约 2026 年 12 月前后）失去补丁。** 这意味着你的升级节奏应该是 **"紧跟最新"而非"两年一次大跳"**。

**推论：长期维护策略的核心不是"如何一次性安全升级"，而是"如何把升级变成一个可重复、低风险、每季度一次的例行动作"。** 后半篇文章都服务于这个目标。

---

## 4. 策略矩阵

你问的三个问题——蓝绿、金丝雀、Helm——在这套架构下的真实答案：

### 4.1 总览

| 策略 | 覆盖组件 | 能否零停机 | 官方是否推荐 | 结论 |
|---|---|---|---|---|
| **原地 Helm 升级**（in-place） | 全部 | ⚠️ 控制面可以，ztunnel 不行 | ✅ 两者均推荐 | **主干路线** |
| **revision 金丝雀** | istiod / waypoint / gateway | ✅ 是 | ✅ 社区推荐 | **控制面灰度手段**，无法覆盖 ztunnel |
| **节点池蓝绿** | ztunnel | ✅ 是（真正的） | Solo 明确提及 | **ztunnel 的唯一可行零停机手段** |
| **Gloo Operator** | 全部 | — | ✅ 可用 | ❌ 你用不了（需 `-solo`） |
| **istioctl upgrade** | 全部 | — | 上游在弱化 | 见 §6.2 |

### 4.2 为什么主干选原地 Helm 升级

三条理由：

1. **官方两处都推荐它。** 社区 ambient 升级指南把 `helm upgrade` 作为 ambient 安装的对应升级路径；Solo 文档在 Considerations 里写得更直接：

   > The upgrade guides in this documentation show you how to perform **in-place upgrades** for your Istio components, which is the **recommended upgrade strategy**. — [docs.solo.io](https://docs.solo.io/istio/1.30.x/ambient/operations/upgrade/manual/)

2. **istiod 部分天然无状态、可灰度。** istiod 滚动升级期间新旧 Pod 共存，配置推送不中断。这部分是真零停机。

3. **Helm 的"就地覆盖"对 ztunnel 不是缺陷而是优势——前提是你配合节点池。** Helm 就地覆盖意味着同一时刻只存在一个 ztunnel DS，配合节点池逐批 cordon/drain，就把"全集群同时断长连接"降级成"少数节点同时断"。详见 §5.4。

### 4.3 为什么 Gloo Operator 在你这里不可用

Gloo Operator 是 Solo Enterprise 的一部分，需要 `-solo` 镜像 + license。**你在 standard 发行版上无法使用它。** 这一点值得单独强调——如果未来有人建议"用 Operator 来做无损升级"，那是基于错误的发行版假设。

---

## 5. 分组件的零停机机制探索

### 5.1 istiod — 唯一真正"优雅"的部分

社区指南给出的两条路：

```
# 原地（in-place）
helm upgrade istiod istio/istiod -n istio-system --wait

# revision（金丝雀）
helm install istiod-1-30-3 istio/istiod -n istio-system --set revision=1-30-3 --set profile=ambient --wait
```

istiod chart 内置 PDB（`minAvailable: 1` 默认开启），配合 `--wait`，这一步基本不构成停机风险。

**这里的"金丝雀"对 ambient 有额外意义**：两个 istiod 并存时，每个 ztunnel 通过 `istio.io/rev` annotation 连到对应控制面（daemonset.yaml:12-14、37-39 确认该 annotation 存在）。**这给了你一个真实存在的两版共存窗口**，可以在里面观察新版本的配置推送行为、监控指标、AuthZ 生效情况。

**但请务必记住边界：这个共存窗口覆盖不了 ztunnel 版本切换。** 控制面两版共存 ≠ 数据面两版共存。

### 5.2 istio-cni — 你环境里最被忽视的风险

§1.1.1 已经把机制说清了。这里补防控方向（探索层面）：

- 升级期间**主动降低新 pod 调度密度**——扩容、滚动发布、批处理任务全部避开窗口。实质是把"可能命中空窗的 pod"数量压到最低。
- 升级后**验证规则注入完整性**，而不只是"Pod 起来了"。规则缺失的 pod 状态是 Running、健康检查正常，但 mesh 行为静默失效——这是最难发现的一类故障。
- 考虑过用 `-solo` 镜像换取 stub plug-in 保护？§3 已经说明：`-solo` 需要 license，与你"用无 license 版本"的既定选择直接冲突。**这是发行版选择的必然代价，不是配置能绕过的。**

### 5.3 waypoint / ingress gateway — 你的 label 是灰度抓手

因为 `istio.io/use-waypoint` / `istio.io/ingress-use-waypoint` 是**纯 label 驱动**（`pilot/pkg/config/kube/gateway/conversion.go:573-615` 解析这些 label；`pkg/workloadapi/workload.proto:99` 明确 `ingress-use-waypoint` 作用于 Service 或其 namespace），它们天然是**最细粒度的灰度单位**。

社区指南提供的 tag 切换命令：

```bash
# 把 tag 指向新 revision
helm template istiod istio/istiod -s templates/revision-tags-mwc.yaml \
  --set revisionTags="{$MYTAG}" --set revision="$REVISION" -n istio-system | kubectl apply -f -

# 回滚：把 tag 指回旧 revision
helm template istiod istio/istiod -s templates/revision-tags-mwc.yaml \
  --set revisionTags="{$MYTAG}" --set revision="$OLD_REVISION" -n istio-system | kubectl apply -f -
```

**回滚成本极低——一条命令改回去。** 这是全部组件里回滚最容易的。

waypoint 是 Deployment 而非 DaemonSet，滚动升级只影响单个 namespace 的 L7 流量路径，完全在控制范围内。

### 5.4 ztunnel — 唯一的硬骨头，也是唯一需要架构手段的

Solo 文档把这个问题讲得非常坦白：

> **ztunnel upgrades** — As Kubernetes dynamically upgrades the ztunnel deployment by restarting the old ztunnel pods, **all long-lived connections on the node are dropped.** You can influence the duration of the downtime with the termination grace period of the ztunnel pod, which determines the drain period. Any TCP connections that are longer than the grace period are dropped. Alternatively, you might **cordon nodes and use blue/green node pools to limit the number of active pods** that are in the process of upgrading. — [docs.solo.io](https://docs.solo.io/istio/1.30.x/ambient/operations/upgrade/manual/)

这段话包含三个必须拆开看的事实：

**事实 A：无法消除，只能缩短。** "Any TCP connections that longer than the grace period are dropped" —— 只要有连接超过 grace period，它就会断。调大 grace period 是**缓解**，不是**解决**。

**事实 B：只有长连接受影响。** 短请求（每次新建连接）在 ztunnel 重启期间失败率极低。所以**真正的 downtime 暴露面 = 你的应用的连接复用模式**。长轮询、WebSocket、gRPC streaming、数据库连接池、消息队列消费者——这些是暴露面；普通 HTTP 请求不是。

**事实 C：官方给的替代方案是节点池蓝绿，不是进程级蓝绿。** "cordon nodes and use blue/green node pools" —— 注意用词是 **node pools**，不是 ztunnel pods。这与 §1.2 的源码事实完全一致：ztunnel 的 DS 名和 selector 都不带 revision，进程级蓝绿在架构上不存在。

**探索结论——三层防御，按代价从低到高：**

| 层级 | 手段 | 消除的 downtime | 代价 | 适用判断 |
|---|---|---|---|---|
| L1 | `terminationGracePeriodSeconds` 调到覆盖 P99 连接时长 | 大部分 | 极低（一个 values 字段） | **必做，无条件** |
| L2 | 滚动窗口内控制长连接应用的重启节奏 | 大部分 | 低（发布流程约定） | **必做，无条件** |
| L3 | 节点池 cordon + drain，逐池升级 | 剩余暴露面 | 高（需预留节点池容量） | 有长连接 SLA 时**值得** |

**L1 的 sizing 方法**：`terminationGracePeriodSeconds` 同时是 K8s 强杀时间和 ztunnel 自身排空时间（排空 = 该值 - 1 秒）。要覆盖你的应用 P99 长连接时长。代价是升级窗口变长（每节点多等一个 grace period）。

**L3 的容量代价必须说清**：为保证任意时刻有足够节点承载全部业务，需要**额外预留一整个节点池的容量**（因为升级中的节点已 cordon，不接新 pod）。这是个真实的、持续的、只为升级而存在的成本。要不要付这个成本，取决于你们对长连接中断的 SLA 有多严。

**还有一件事值得单独说**：Solo 文档的 ztunnel 段还有一句"TCP keepalive 调优"的建议（提到大规模场景下 keepalive 与 grace period 的配合）。这属于 `-solo` 文档内容，我**没有在 release-1.30 源码中找到对应实现**，无法确认它在 standard 发行版上是否可用。**列为待验证项，不作为方案依据。**

---

## 6. 工具链选择：Helm vs istioctl vs Operator

### 6.1 选 Helm，且理由具体

| 方案 | 是否适用于你的环境 | 理由 |
|---|---|---|
| **Helm** | ✅ **推荐** | 你已用 Helm 装（Solo manual 指南即 Helm 流程）；istio-base / istiod / cni / ztunnel 四个 release 边界清晰；`helm get values` 提供天然的升级前后 diff 基线；社区 ambient 指南以 Helm 为唯一覆盖 |
| istioctl upgrade | ⚠️ 可用但边缘 | 1.30 release note 提到 istioctl 有改进（含 `ztunnel-config` 命令精化、`--tls-min-version`），说明工具仍在维护；Solo 指南里"升级 istioctl CLI"只是准备工作步骤，真正的升级动作仍用 Helm。**工具在，但主路径已让给 Helm。** |
| Gloo Operator | ❌ 不可用 | 需 `-solo` + license |

### 6.2 一个 Helm 特有的好消息

Istio 1.30 release note：

> Istio 1.30 adds support for **Helm v4 (server-side apply)**. A long-standing issue with webhook `failurePolicy` field ownership during upgrades has also been addressed. Users running Helm v4 should upgrade smoothly without the previous workarounds.

**这条对你有实际价值**：`failurePolicy` 字段归属问题在过去的 Helm 升级中是个反复出现的痛点（典型报错 `Rendered manifests contain a resource that already exists`），1.30 已经修复。**如果你打算升级 Helm 到 v4，这本身是一个应当安排的时机。**

---

## 7. 长期维护视角

### 7.1 节奏：紧跟，而非跳跃

§3 已论证：standard 发行版没有 Solo 的 `n-4`，只能吃社区 `n-1` + 6 周。**所以是"每季度跟一次 minor"，不是"攒两年跳一次"。** 这个区别决定了整个维护体系是"例行流水线"还是"年度大工程"。

**具体的版本推进约束**：

- 社区支持：控制面可领先数据面一个版本；数据面不能领先控制面。**先 istiod，后 ztunnel。** 社区 ambient Helm 指南明确：

  > The ztunnel at version 1.x is compatible with the control plane at version 1.x+1 and 1.x. This means **the control plane must be upgraded before ztunnel**, as long as their version difference is within one minor version.

- ztunnel 1.x 兼容控制面 1.x 和 1.x+1 —— 意味着你有一个 minor 版本的缓冲带（先升 istiod，ztunnel 暂不动，此时 1.x ztunnel 对 1.x+1 控制面仍兼容）。

- **不建议跨 minor 跳跃**（如 1.30 → 1.32）。跳过 1.31 会同时跳出 ztunnel 的兼容窗口，也会错过中间版本的行为变更信息。

### 7.2 现在就值得做的一件事

**为 ztunnel 建立长连接暴露面的清单。** 这是 §5.4 L2 的前置条件，也是判断"是否需要 L3 节点池蓝绿"的唯一依据。**没有这份清单，L3 的成本无法论证，L1 的 sizing 也无从谈起。** 这是零停机升级里唯一必须靠业务知识、无法靠技术手段自动得出的输入。

### 7.3 待验证项（官方未覆盖 / 我未能确认）

| # | 待验证 | 原因 |
|---|---|---|
| 1 | `1.30.3-distroless` 对应的 Helm chart 版本号写法 | 需实际 `helm search` / 访问 Artifact Registry 确认；Solo 文档示例统一用 `-solo`，无 license 版本的 chart tag 命名需实测 |
| 2 | ztunnel TCP keepalive 调优建议 | 出现在 `-solo` 文档，release-1.30 开源源码中未找到对应实现，standard 发行版是否可用未知 |
| 3 | ztunnel 长连接中断在你们业务上的实际影响面 | 依赖业务连接模式，需实测 |
| 4 | Helm v4 在你们的 CI 流水线中是否已就绪 | 影响是否借机升级 |

---

## 8. 结论

**三条主线，建议的优先级顺序：**

1. **主干走原地 Helm 升级**（官方推荐），**istiod 用 revision 做两版共存的验证窗口**（成本低、收益明确），**waypoint/gateway 用现有 label 逐个灰度**（回滚就是一条命令）。

2. **ztunnel 是唯一的硬约束，且架构上无法用 revision 绕过。** 三层防御：调大 grace period（必做）→ 控制长连接应用的重启节奏（必做）→ 节点池 cordon/drain（按长连接 SLA 决定是否值得预留容量）。

3. **你现在用的 standard 发行版（无 `-solo`）在升级这件事上是有代价的**，而且这个代价此前被文档掩盖了：没有 stub CNI plug-in 保护、没有 `n-4` 补丁窗口、没有 Operator。**这不是要你现在换发行版——是要你在排期时把这些成本显式计入，而不是等出事了才发现。**

**最该立刻做的一件事**：盘出业务侧的长连接清单。它是所有零停机措施中唯一无法从技术侧推导的输入，也是决定是否值得为升级预留一整个节点池容量的唯一依据。

---

## 附录：本文档的一手来源

| 结论来源 | 引用位置 |
|---|---|
| ztunnel 版本兼容规则、控制面须先升级 | [istio.io/v1.30 ambient upgrade/helm](https://istio.io/v1.30/docs/ambient/upgrade/helm/) |
| revision / tag 机制与回滚命令 | [istio.io/v1.30 canary upgrade](https://istio.io/v1.30/docs/setup/upgrade/canary/) |
| ztunnel 长连接被切断、grace period、节点池蓝绿建议 | [docs.solo.io 1.30.x upgrade/manual](https://docs.solo.io/istio/1.30.x/ambient/operations/upgrade/manual/) |
| in-place 为推荐策略 | 同上（Considerations 节） |
| `-solo` 发行版定义与 license 要求 | [docs.solo.io images/overview](https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/) |
| n-4 仅限 `-solo` | [docs.solo.io images/versions](https://docs.solo.io/istio/1.30.x/ambient/about/images/versions/) |
| 版本 EOL 与 K8s 兼容矩阵 | [istio.io supported-releases](https://istio.io/v1.30/docs/releases/supported-releases/) |
| ztunnel chart 无 revision 隔离 / 无 PDB / grace period 语义 | `istio/istio` **`release-1.30`** 分支源码 |
| stub CNI plug-in 不存在于开源分支 | `istio/istio` `release-1.30` 全树检索 + CNI ConfigMap 模板逐 key 核对 |
| istiod chart 资源名带 revision + 内置 PDB | release-1.30 `istio-discovery` chart 源码 |
| waypoint label 语义与解析位置 | release-1.30 `pilot/pkg/config/kube/gateway/conversion.go:573-615`、`pkg/workloadapi/workload.proto:99` |
| Helm v4 / server-side apply 支持 | [istio.io/v1.30 announcing 1.30](https://istio.io/v1.30/news/releases/1.30.x/announcing-1.30/) |

> **版本核验方法说明**：本文档中所有源码级结论均在 `istio/istio` `release-1.30` 分支上实际检索验证，非记忆推断。若将来升级到新 minor 版本，§1.2（ztunnel 无 revision 隔离）和 §1.1.1（无 stub plug-in）**两条结论需要在目标版本上重新验证**——它们是架构约束，可能随版本变化。
