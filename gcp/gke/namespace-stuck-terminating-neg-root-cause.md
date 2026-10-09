# GKE Namespace 卡在 Terminating：NEG 视角的根因分析

> **配套图**：[`namespace-stuck-terminating-neg-root-cause-architecture.html`](./namespace-stuck-terminating-neg-root-cause-architecture.html) — finalizer 阻塞链路的深色架构图（K8s 侧 ↔ GCE 侧对照）
> **文档类型**：探索性架构分析（design/exploration，非 runbook）
> **日期**：2026-10-09
> **作者**：architect-gcp
> **核心问题**：在 GKE 中，什么情况下 Namespace 会卡在 `Terminating` 无法删除？其中 **NEG 做了什么"特殊设置"导致这个问题**？
> **范围声明**：本文**排除**纯策略/配额类原因（RBAC、Gatekeeper 准入策略、命名规范等"人为设置"），只聚焦于**控制器机制**层面的卡死根因。

---

## 0. TL;DR（先给结论）

| 问题 | 结论 |
|---|---|
| **有 NEG 就不让删 Namespace 吗？** | **不是。** NEG 不会"禁止"删除 Namespace，而是**在 Namespace 内部放置了一个带 finalizer 的 CR（DONT 删 ServiceNetworkEndpointGroup/SvcNeg），使 Namespace 生命周期控制器必须等它先消失**。Namespace 是被"间接拖住"的。 |
| **NEG 做了什么"特殊设置"？** | ① 在 Namespace 内创建了 **CRD 资源 `ServiceNetworkEndpointGroup`（SvcNeg）**；② 给它打上 finalizer **`networking.gke.io/neg-finalizer`**；③ 这个 finalizer 的**语义是"必须先删掉 GCE 侧的 NEG 实例，才能删掉这个 CR"**，而 GCE 侧的 NEG 只要还被任何 backend service 引用就删不掉。 |
| **所以"什么情况下"会卡？** | 当 **GCE 侧的 NEG 删不掉**时 → SvcNeg CR 的 finalizer 清不掉 → Namespace 一直 `Terminating`。GCE NEG 删不掉的**根因只有一个**：`NEG is still referenced by a backend service`（以及少数"描述冲突/跨项目残留"等边缘情况，见 §4）。 |
| **典型症状** | `NamespaceFinalizersRemaining` 报 `networking.gke.io/neg-finalizer in N resource instances`；或 `NamespaceContentRemaining` 报 `servicenetworkendpointgroups.networking.gke.io has N resource instances`。[5] |
| **"用 NEG 就会慢"是预期行为吗？** | **是设计使然（by design）**。ingress-gce 维护者明确答复：NEG finalizer 的存在正是为了保证 SvcNeg CR 会持续存在、直到对应的 GCE NEG 被删除，这是保护性设计而非 bug。[5] |

**一句话**：NEG 没有禁止删除 Namespace；NEG 只是在自己的 CR 上挂了一个"必须等 GCE NEG 删成功才放行"的 finalizer，于是把 Namespace 的删除顺延了。**当 GCE NEG 因为还被 backend service 引用而删不掉时，这个等待就变成永久卡死。**

---

## 1. 背景：Namespace 删除的底层机制（为什么 finalizer 会拖住 Namespace）

### 1.1 简化解释

Namespace 不是"一个删了就立刻消失的文件夹"。它内部有一个**生命周期控制器**，删除时会做两轮：

1. **发现（Discover）**：把该 Namespace 下所有能列举的资源类型全列一遍，准备删。
2. **清空（Content Deleted）**：把资源一个个删掉。
3. **等待（Finalization）**：等待所有资源的 finalizer 都清空。
4. 只有全部完成，`kubernetes` 这个 Namespace 自身的 finalizer 才被清掉，Namespace 才真正消失。

只要内部**任何一个对象还带着 finalizer 且不放手**，Namespace 就一直挂在 `Terminating`。[1]

### 1.2 严格原话（权威证据）

> "Namespaces use Kubernetes finalizers to prevent deletion if one or more resources within a namespace still exist. ... The namespace stays in the `Terminating` state until Kubernetes deletes its dependent resources and clears all finalizers."[1]

> 真实卡死现场（来自 ingress-gce issue #1720，Namespace 的 `status.conditions`）[5]：

```yaml
status:
  conditions:
  - reason: SomeFinalizersRemain
    status: "True"
    type: NamespaceFinalizersRemaining
    message: 'Some content in the namespace has finalizers remaining:
              networking.gke.io/ingress-finalizer-V2 in 2 resource instances,
              networking.gke.io/neg-finalizer in 1 resource instances'
  - reason: SomeResourcesRemain
    status: "True"
    type: NamespaceContentRemaining
    message: 'Some resources are remaining: ...
              servicenetworkendpointgroups.networking.gke.io has 1 resource instances'
  phase: Terminating
```

### 1.3 与本次分析的关系

上面这段 `message` 就是**最直接的证据**：卡住的 Namespace 里，除了 Ingress 的 `ingress-finalizer-V2`，明确出现了 **`networking.gke.io/neg-finalizer`（NEG 的 finalizer）**。这说明 NEG 确实是"拖住 Namespace"的元凶之一。

**因此，把范围缩小到：NEG 的 finalizer 为什么清不掉？**

---

## 2. NEG 做了什么"特殊设置"？——拆解到代码级

这一节是全文的核心。我把 ingress-gce（Google 官方的 GKE LB 控制器）的**源码**拉下来逐行确认。

### 2.1 设置一：在 Namespace 内创建了一个 CRD —— `ServiceNetworkEndpointGroup`（简称 SvcNeg）

GKE 的 NEG controller 不是"凭空"管理 NEG 的，它在 Namespace 内为每个 NEG 端口创建一个 CR 叫 `ServiceNetworkEndpointGroup`（API group `networking.gke.io`）。这个 CR 是"状态型"（status-only）的，它记录对应 GCE NEG 的 selfLink、zone、状态。

源码（`pkg/neg/manager.go`，创建 SvcNeg CR 的地方）[4]：

```go
newCR := negv1beta1.ServiceNetworkEndpointGroup{
    ObjectMeta: metav1.ObjectMeta{
        Name:            portInfo.NegName,
        Namespace:       svcKey.namespace,
        OwnerReferences: []metav1.OwnerReference{*ownerReference},
        Labels:          labels,
        Finalizers:      []string{common.NegFinalizerKey},   // ← 关键：创建时就带上 finalizer
    },
}
```

> `OwnerReferences` 指向 Service。所以 Service 删掉时，K8s 的 GC 会级联删这个 SvcNeg CR；**但因为它有 finalizer，GC 不会真的把它删掉，而是把它卡在"待删除"状态，直到 NEG controller 清掉 finalizer。**

### 2.2 设置二：给 SvcNeg CR 打上 finalizer `networking.gke.io/neg-finalizer`

finalizer 名称的官方定义（`pkg/utils/common/finalizer.go`）[3][8]：

```go
// NegFinalizerKey is the finalizer used by neg controller to ensure NEG CRs are
// deleted after corresponding negs are deleted
NegFinalizerKey = "networking.gke.io/neg-finalizer"
```

**严格原话**：这个 finalizer 的作用是"**确保 NEG CR 在对应的 GCE NEG 被删除之后才被删除**"。

这就是"特殊设置"的核心语义：**它把"K8s 侧 CR 的删除"和"GCE 侧 NEG 的删除"串成了一个有序依赖——GCE NEG 没删掉，CR（进而 Namespace）就不许删。**

### 2.3 设置三：finalizer 的清理由 NEG controller 的 GC 循环驱动，且**只有 GCE NEG 删成功才清**

这是本文要论证的**最关键**的一点。我追踪了 `processNEGDeletionCandidate`（`pkg/neg/manager.go`）[4]：

```go
func (manager *syncerManager) processNEGDeletionCandidate(candidate deletionCandidate, zones []string) []error {
    svcNegCR := candidate.neg
    shouldDeleteNegCR := true
    ...
    for _, negRef := range svcNegCR.Status.NetworkEndpointGroups {
        negDeleted := manager.deleteNegOrReportErr(resourceID.Key.Name, resourceID.Key.Zone, svcNegCR, &errList)
        if negDeleted { ... }
        shouldDeleteNegCR = shouldDeleteNegCR && negDeleted   // ← 只要有一个 NEG 没删掉，整个 CR 就不删
    }
    ...
    if !shouldDeleteNegCR || candidate.tbdOnly {
        // CR 不删，只把已删 NEG 的引用从 status 清掉，保留 CR + finalizer
        ...
        return errList
    }
    // 走到这里 = 所有 NEG 都删成功了 → 才会走到下面去清 finalizer、删 CR
    ...
    err := deleteSvcNegCR(manager.svcNegClient, svcNegCR, ...)  // 清 finalizer + 删 CR
}
```

而真正去 GCE 删除 NEG 的函数 `deleteNegOrReportErr`（同一文件）[4]：

```go
func (manager *syncerManager) deleteNegOrReportErr(name, zone string, svcNegCR *..., errList *[]error) bool {
    if err := manager.ensureDeleteNetworkEndpointGroup(name, zone, expectedDesc); err != nil {
        err = fmt.Errorf("failed to delete NEG %s in %s: %s", name, zone, err)
        manager.recorder.Event(svcNegCR, v1.EventTypeWarning, negtypes.NegGCError, err.Error())  // 只发 Event
        *errList = append(*errList, err)
        return false   // ← 删除失败：返回 false，CR/finalizer 原封不动
    }
    return true
}
```

**结论（源码级）**：

- 删除 GCE NEG 失败 → `deleteNegOrReportErr` 返回 `false` → `shouldDeleteNegCR = false` → **不清 finalizer、不删 CR**。
- Namespace 内的这个 SvcNeg CR 永远存在 → **Namespace 永远 Terminating**。
- controller 不会"放弃"或"超时强删"——它每一轮 GC 都重试，失败就继续等，**没有退避上限的最终放弃机制**。

### 2.4 GC 循环的驱动周期

GC 由 `gcPeriod` 定时触发（`garbageCollectNEGWithCRD` → `processNEGDeletionCandidate`）。维护者在 issue 里给的量级是"**每 2 分钟**跑一次 NEG GC"[5]。

> 这解释了为什么即使你把 Ingress/Service 都删干净了，Namespace 删除**仍然会慢几分钟**——你删完的瞬间，GC 还没到下一轮，finalizer 还没被清。**这是"延迟"而非"永久卡死"。**

**区分"慢" vs "永久卡死"（重要认知）**：

| 现象 | 判定 | 根因 |
|---|---|---|
| 删除耗时几分钟到十几分钟，**最终自己好了** | **正常延迟**（GC 周期 + 逐个删 NEG） | finalizer 设计 + GC 周期 |
| 一直 `Terminating`，几小时/几天不消失 | **永久卡死** | GCE NEG **删不掉**（被引用 / 描述冲突） |

---

## 3. 那 GCE NEG 为什么删不掉？——唯一的真凶

**核心命题**：NEG 的 GC 之所以会卡死，根源都在"GCE 侧的 NEG 实例删不掉"。而 GCE NEG 删不掉，**有一个压倒性的、也是官方明确写出来的原因**：

> ### 官方原话（一手）
> "When a GKE service is deleted, the associated NEG **won't be garbage collected if the NEG is still referenced by a backend service**. Dereference the NEG from the backend service to allow NEG deletion."[2]

> **Compute Engine API 层面的硬规则**："Deletes the specified network endpoint group. **Note that the NEG cannot be deleted if it is configured as a backend of a backend service.**"[6]

这就是 §2.3 那段源码里 `ensureDeleteNetworkEndpointGroup` 最终会失败、`deleteNegOrReportErr` 返回 false 的**最主要触发源**。

### 3.1 什么情况下 NEG 会被 backend service 引用？（导致删不掉）

NEG 被引用的情况很多，结合 GKE 常见架构，典型有：

1. **Ingress / Gateway 托管的 backend service**（最常见）：Ingress 建的 backend service 挂了 NEG。你删了 Service 但 Ingress/其他 backend service 还在引用这个 NEG。
2. **Standalone NEG 被手工/外部创建的 backend service 引用**（你实际遇到的场景很可能就是这类）：standalone NEG 的 backend service 是**你自己（或 IaC 流水线）用 gcloud/Terraform 手工建的**，它的生命周期不受 GKE 管。只要 backend service 还在（或 IaC 的 destroy 顺序没先拆引用），NEG 就删不掉。
3. **跨项目 backend service 引用**：backend service 在**另一个 project**，引用了本 cluster 的 NEG。删除顺序/权限问题会额外复杂化。
4. **Ingress 与 standalone NEG 混用**：官方明确说 standalone NEG 和 Ingress 托管的 NEG 可以共存、互不冲突，但**如果同一个 NEG 被两条链路同时引用**，拆除时必须两边都先解引用。

### 3.2 症状与排查（官方 troubleshooting）

官方给出了明确的排查路径 [2]：

> **NEG is not garbage collected**
> Symptom: A NEG that should have been deleted still exists.
> Potential Resolution: The NEG is not garbage collected if the NEG is referenced by a backend service. See Preventing leaked NEGs for details.
> · If using 1.18 or later, you can check for events in the ServiceNetworkEndpointGroup resource using the service neg procedure.
> · Check to see if the NEG is still needed by a service. Check the svcneg resource for the service that corresponds to the NEG and check if a Service annotation exists.

对应命令（本文整理）：

```bash
# 1) 找到卡住的 Namespace 里的 SvcNeg CR 及其状态
kubectl get svcneg -n <stuck-ns> -o wide
kubectl get svcneg -n <stuck-ns> -o yaml        # 看 status.conditions / status.networkEndpointGroups

# 2) 看 SvcNeg 的 Event（GC 失败时 controller 会打 Warning Event）
kubectl get svcneg -n <stuck-ns> --watch        # 或
kubectl describe svcneg -n <stuck-ns> <name>    # 关注 NegCRError 事件

# 3) 关键：确认 NEG 是否还被 backend service 引用
#    从 SvcNeg status 拿到 NEG 的 selfLink（含 zone、project、name）
#    然后：
gcloud compute network-endpoint-groups describe <NEG_NAME> --zone=<ZONE> --project=<PROJECT>

# 4) 反查哪些 backend service 在用这个 NEG
gcloud compute backend-services list --project=<PROJECT> --filter="..." 
# 或用 gcloud 查引用：
gcloud compute network-endpoint-groups describe <NEG_NAME> --zone=<ZONE> --format="value(selfLink)"
# 然后在 LB 侧查引用该 NEG 的 backend service（gcloud / Console / Traffic Director / CSM）

# 5) 官方建议的"列出 Namespace 内所有资源"命令（含 CRD，kubectl get all 看不到 SvcNeg）
kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n 1 kubectl get --show-kind --ignore-not-found -n <stuck-ns>
```

### 3.3 一个 GKE 特有的"描述冲突"失败模式（容易被忽略）

源码里 `ensureDeleteNetworkEndpointGroup` 有一段"描述校验"逻辑 [4]：

```go
if matches, err := expectedDesc.MatchesString(neg.Description, name, zone); !matches {
    manager.logger.V(2).Info("Skipping deletion of Neg because of conflicting description", ...)
    return nil
}
```

`StandardNEGDescription` 里包含 **cluster-uid / namespace / service-name / port**。如果 GCE 侧 NEG 的 description 与当前 controller 预期不一致（典型于：集群重建后 cluster-uid 变了、跨集群复用了同名 NEG、集群删除重建），controller 会**主动跳过删除**（"Skipping deletion ... conflicting description"），返回 nil 但实际没删——**这也会让 NEG 残留、进而卡住 Namespace**。

（社区里有对应的真实案例：集群 UUID 变更导致 `neg is already in use, found conflicting description`，NEG 状态卡在 `NegSyncFailed` / `NegInitializationFailed`。[unverified——该细节来自社区案例，机制本身已由上面的源码证实]）

---

## 4. 归纳：NEG 导致 Namespace 无法删除的"故障树"

```
Namespace 卡在 Terminating
└── 内部有对象带 finalizer 不放手            [1]
    └── networking.gke.io/neg-finalizer 不清  ← 本次核心        [5]
        └── NEG controller GC 想清它，但前提是"GCE NEG 已删"     [4]
            └── GCE NEG 删不掉  →  deleteNegOrReportErr=false  → 永不放行  [4]
                ├── (主因) NEG 仍被某个 backend service 引用      [2][6]
                ├── (边缘) NEG description 与预期冲突，controller 跳过删  [4]
                ├── (边缘) NEG 处于 TO_BE_DELETED 但 selfLink 解析失败，需人工介入  [4]
                └── (集群级) 集群删除时 controller 先被关停，NEG 遗留  [2]
```

**"什么情况下会出现"** —— 直接回答你的问题：主要是**NEG 与 backend service 的引用关系没有在删除前解除**，而你排除了"人为策略"，那么在真实环境里最常见的触发组合是：

1. **拆除顺序错**：先删 Service/Namespace，后删（或忘了删）引用 NEG 的 backend service / Ingress / Gateway。
2. **IaC 编排顺序**：`terraform destroy` / `gcloud` 脚本里，backend service 的拆除晚于或遗漏于 SvcNeg/NEG。
3. **多控制面并存**：同一 NEG 被 Ingress 托管 backend service 和手工/standalone backend service 同时引用，拆一边不够。
4. **跨项目**：backend service 在别的 project，拆除/权限时序更脆。

---

## 5. 除此之外：其他（非 NEG）会让 Namespace 卡死的机制

你明确说**排除策略/配额类**问题（RBAC、Gatekeeper 准入等人为设置）。但在真实集群里，Namespace 卡死还有几个**机制性**（非人为策略）的原因，一并列出，便于你做"排除法"（这些与 NEG 无关）：

1. **自定义 API / APIService 不可达（最经典的"非人为"卡死）**：
   集群里有 metrics-server、GitOps、某个 CRD 的 apiextensions server 等，如果它挂了导致对应 APIService `Available=False`，Namespace 控制器就无法"发现"并删除该类型的资源，Namespace 一直 Terminating。这是"控制面 API 不健康"导致的，不是策略。

2. **CRD 删除卡住（CRD 自身的 finalizer / apiextensions 调谐失败）**：集群级 CRD 上有 finalizer，或 CRD 的对象调谐超时，删除时阻塞。

3. **Pod 处于 `Unknown` / `NodeLost`（节点失联）**：节点被删/失联后，Pod 永远停在 `Unknown`，Namespace 里的"未完全删除"对象无法收敛，Namespace 卡死。

4. **`foregroundDeletion` finalizer 残留（GC 竞态）**：删 Namespace 触发了前台级联删除，GC 在处理 owner 依赖链时若遇到异常/竞态，`foregroundDeletion` finalizer 可能残留，导致空 Namespace 也删不掉。

5. **Ingress 自身 finalizer**（`networking.gke.io/ingress-finalizer[-V2]`）：如果 LB 资源删不掉，Ingress 的 finalizer 不清，同样拖住 Namespace（与 NEG 同源问题：GCE 资源删不掉）。[5]

> 上面 1、3、4 属于 Kubernetes 社区经典的 non-policy 卡死原因，本文点到为止，不展开（你的重点是 NEG）。**关键认知**：**所有"因外部云资源删不掉而卡住"的机制，本质都是同一个模式——finalizer 把"K8s 对象删除"绑定到了"外部资源删除"上。NEG 只是这个问题在 GCP 上最常见的一个实例。**

---

## 6. 排查决策树（实操导向）

当遇到 GKE Namespace 卡 `Terminating`，按这个顺序做"排除法"（不涉及任何策略检查，符合你的范围）：

```
Namespace 长期 Terminating
│
├─ 1) 看 Namespace status.conditions 里的 message
│     ├─ 出现 "networking.gke.io/neg-finalizer"  → 是 NEG 问题，走第 2 步
│     ├─ 出现 "servicenetworkendpointgroups... has N instances" → 是 NEG CR 残留，走第 2 步
│     ├─ 出现 "ingress-finalizer"              → 是 Ingress/LB 问题（同类：GCE 资源删不掉）
│     └─ 出现 "APIService/ParseGroupVersion" 相关 → 控制面 API 不健康，排查 metrics/GitOps 等
│
├─ 2) [NEG 专属] 确认 SvcNeg CR 及其 Event
│     kubectl get svcneg -n <ns> -o yaml ; kubectl describe svcneg ...
│     └─ 看有没有 NegCRError 事件（controller 每次 GC 失败都会打）
│
├─ 3) [NEG 专属] 确认 GCE NEG 是否仍被 backend service 引用   ← 决定性一步
│     gcloud compute network-endpoint-groups describe <NEG> --zone
│     反查 backend service 引用关系
│     └─ 找到引用方 → 先把引用解除（删/解绑 backend service），NEG 才会变可删
│
├─ 4) 若 NEG 没有被引用却仍删不掉 → 查 description 冲突 / selfLink 解析失败（§3.3 边缘情况）
│
└─ 5) 若都不是 → 回到 §5 的非-NEG 卡死原因（APIService / NodeLost / foregroundDeletion 等）
```

**一个实用建议**：把"删除前先解引用"写进 IaC 的 teardown 顺序——**先拆 backend service 引用 → 再删 Service/Ingress → 最后删 Namespace**。这是从架构/编排层面消除该卡死的最有效手段（属于 IaC 设计，不涉及集群策略）。

---

## 7. 一句话回答你的三个问题

1. **什么情况下 Namespace 无法删除？**（机制层面，剔除策略类）→ 当 Namespace 内某个对象带 finalizer 且其"对应的外部资源删不掉"时。NEG 的典型场景是"GCE NEG 仍被 backend service 引用"。此外还有控制面 API 不健康、节点失联、GC 竞态等其他机制性原因（§5）。

2. **NEG 做了什么"特殊设置"？** → 它在 Namespace 内创建 CRD `ServiceNetworkEndpointGroup`，并给它打上 finalizer `networking.gke.io/neg-finalizer`；该 finalizer 的语义是"必须等 GCE 侧 NEG 删成功，才放行这个 CR（进而 Namespace）的删除"。[3][4]

3. **在有 NEG 的情况下，Namespace 就不让删除吗？** → **不是"不让删"，而是"要等"**。NEG 不禁止删除，它只是把删除顺延了。如果 GCE NEG 能顺利删掉（引用已解除），Namespace 会在下一轮 GC（量级 ~2 分钟）后正常消失（可能整体慢几分钟）。**只有当 GCE NEG 永久删不掉时，才变成真正的永久卡死。**

---

## 8. 关于本文的证据与置信度

- **一手源码**（本文最强证据）：ingress-gce `pkg/neg/manager.go`、`pkg/utils/common/finalizer.go`，我已逐行核对删除路径与 finalizer 语义。[3][4][8]
- **一手官方文档**：GKE Namespace Terminating 故障排查、GKE standalone NEG（含"Preventing leaked NEGs"与"NEG is not garbage collected"故障排查）。[1][2][7]
- **官方 API 契约**：Compute Engine API `regionNetworkEndpointGroups.delete` 明确"NEG 被 backend service 引用时不可删"。[6]
- **真实故障案例**：ingress-gce issue #1720（含真实的 `neg-finalizer` 造成的 `NamespaceFinalizersRemaining` condition 现场 + 维护者确认"这是预期行为"）。[5]
- **`[unverified]` 标记**：§3.3 提到的"集群 UUID 变更导致 description 冲突"这一具体社区案例的触发细节，机制已由源码（描述校验跳过删除）证实，但"集群 UUID 变更"这个具体诱因来自社区经验，未找到一手文档确认 → 已标注。

---

## 参考来源

> 以下链接由引用账本自动生成，与正文中的 `[n]` 标记一一对应；每条含义详见 §8 证据说明。

Sources:
[1] https://cloud.google.com/kubernetes-engine/docs/troubleshooting/terminating-namespaces — GKE Docs — Troubleshoot namespace stuck in the Terminating state
[2] https://docs.cloud.google.com/kubernetes-engine/docs/how-to/standalone-neg — GKE Docs — Container-native load balancing through standalone zonal NEGs
[3] https://raw.githubusercontent.com/kubernetes/ingress-gce/master/pkg/utils/common/finalizer.go — ingress-gce source — pkg/utils/common/finalizer.go
[4] https://raw.githubusercontent.com/kubernetes/ingress-gce/master/pkg/neg/manager.go — ingress-gce source — pkg/neg/manager.go
[5] https://github.com/kubernetes/ingress-gce/issues/1720 — ingress-gce issue #1720 — NEG finalizers make namespaces take 10+ mins to delete
[6] https://developers.google.com/resources/api-libraries/documentation/compute/alpha/python/latest/compute_alpha.regionNetworkEndpointGroups.html — Compute Engine API — regionNetworkEndpointGroups.delete: NEG cannot be deleted if configured as a backend
[7] https://docs.cloud.google.com/kubernetes-engine/docs/concepts/container-native-load-balancing — GKE Docs — Container-native load balancing concepts
[8] https://raw.githubusercontent.com/kubernetes/ingress-gce/v1.40.2/pkg/utils/common/finalizer.go — ingress-gce v1.40.2 — finalizer.go (pinned version)
