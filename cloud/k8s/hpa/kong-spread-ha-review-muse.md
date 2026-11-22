# Kong PRD 高可用配置评审：分布结果（Muse 修正版）

> 评审对象：Kong 网关 Deployment（namespace `clienta-int-kdp`，instance `clienta-int-kdp-prd`）
> 来源：`kong-spread-ha-review.md`（原文档）+ `kong-spread-ha-review-claude.md`（Claude 评审）
> + `pdb-multi-zone-spread-ha.md`（通用方法论）
> 本文件是 Muse 在上述三份文档基础上重新核算的结论，修正了原文档 §5 的两处错误。
> 日期：2026-11-19

> **结论先行（最终配置，详见 §12）**
>
> **这是成本最低、底线最稳的组合：低负载时每 Zone 各 1 个 Pod，任意时刻（包括维护期间）至少 2 个 Pod 可用。**
>
> 配置：`HPA minReplicas: 3 / maxReplicas: 5` + `PDB maxUnavailable: 1`，其他配置（`required` hostname 反亲和、`topologySpread maxSkew: 1 + DoNotSchedule + Honor/Honor`、`RollingUpdate maxSurge: 1 / maxUnavailable: 0`）不变。
> 数字：低负载 3 副本时分布 `1/1/1`，自愿中断最少可用 2 个，单 Zone 故障剩 2 个（-33%）；4 副本 `2/1/1`、5 副本 `2/2/1`，底线分别为 3 个和 4 个。代价是低负载比原来多 1 个 Pod，升级仍一次只动 1 个 Pod。

---

## 0. 被评审的 YAML（核心配置）

```yaml
# ── Deployment ────────────────────────────────────────────────────────
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1            # 更新时最多多起 1 个 Pod
      maxUnavailable: 0      # 更新时不主动减少可用副本（先起新的，再删旧的）
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app.kubernetes.io/component: app
                  app.kubernetes.io/instance: clienta-int-kdp-prd
                  app.kubernetes.io/name: kong
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          nodeAffinityPolicy: Honor
          nodeTaintsPolicy: Honor
          labelSelector:
            matchLabels:
              app.kubernetes.io/component: app
              app.kubernetes.io/instance: clienta-int-kdp-prd
              app.kubernetes.io/name: kong
---
# ── HorizontalPodAutoscaler ───────────────────────────────────────────
spec:
  minReplicas: 2
  maxReplicas: 5
---
# ── PodDisruptionBudget ──────────────────────────────────────────────
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: clienta-int-kdp-prd-kong
  namespace: clienta-int-kdp
spec:
  maxUnavailable: 1    # 最大不可用数：自愿中断时一次最多 1 个 Pod 不可用；不是越小越好，见 §2.5
  selector:
    matchLabels:
      app.kubernetes.io/component: app
      app.kubernetes.io/instance: clienta-int-kdp-prd
      app.kubernetes.io/name: kong
```

**前提：** 集群有 3 个可用 Zone（a/b/c），Node 充足（稳态 Node 数 ≥ 副本数，滚动更新期 ≥ 副本数 + 1）。

---

## 1. 配置能达到的分布结果（核心表）

| 副本数 | 稳态分布 a/b/c | 每个 Pod | 单 Zone 故障后剩几个 | 容量变化 | 单 Node 故障后 |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **2**（HPA min） | **1/1/0** | 各独占 1 个 Node | 剩 **1** 个 | **-50%** | 剩 1 个 |
| **3** | **1/1/1** | 各独占 1 个 Node | 剩 **2** 个 | **-33%** | 剩 2 个 |
| **4** | **2/1/1** | 各独占 1 个 Node | 剩 **2~3** 个，最差剩 2 个（丢了那个有 2 个的 Zone） | -25% ~ -50% | 剩 3 个 |
| **5**（HPA max） | **2/2/1** | 各独占 1 个 Node | 剩 **3~4** 个，最差剩 3 个 | -20% ~ -40% | 剩 4 个 |
| **滚动更新中** | 副本数 +1 | 各独占 1 个 Node | 旧 Pod 全程在线 | 0 | 0 |

滚动更新的瞬时分布（`maxSurge: 1`）：

| 副本数 | 更新前 | Surge Pod 落点 | 瞬时分布 |
| :---: | :---: | :---: | :---: |
| 2 | `1/1/0` | **只能去空着的 zone-c**（去 a/b 会让 skew 变成 2，被 `DoNotSchedule` 拒绝） | `1/1/1` |
| 3 | `1/1/1` | 任一 Zone 均可（skew 仍 ≤1） | `2/1/1` |
| 4 | `2/1/1` | 当前最少的 Zone | `2/2/1` |
| 5 | `2/2/1` | 当前最少的 Zone | `2/2/2`，需要 6 个 Node |

Zone 数不足时的退化：

| 可用 Zone 数 | 2 副本 | 3 副本 | 4 副本 | 5 副本 |
| :---: | :---: | :---: | :---: | :---: |
| 2 个 Zone | `1/1` | `2/1` | `2/2` | `3/2` |
| 1 个 Zone | 全部落同一 Zone，skew=0，**约束不报错也不告警**，静默失去 Zone 冗余 | 同左 | 同左 | 同左 |

---

## 2. 每一条 YAML 到底起了什么作用

### 2.1 `podAntiAffinity: required + hostname` —— Node 隔离，硬保证

只要有匹配标签的 Pod 落在某个 Node 上，这个 Node 就不能再放 Kong Pod。不满足就 Pending，不会降级。这是这份配置里最强的一项。

### 2.2 `topologySpreadConstraints: maxSkew: 1 + zone + DoNotSchedule` —— Zone 均衡，硬保证

这不是原来需求里写的“尽量”，强度已经超过“尽量”了。只要调度时能满足，任意两个 Zone 的 Pod 数差值 ≤ 1。副本 ≤ Zone 数时，每 Zone 至多 1 个；副本 > Zone 数时，也不会出现一个 Zone 塞 3 个、另一个空着的情况。

### 2.3 `nodeAffinityPolicy: Honor / nodeTaintsPolicy: Honor` —— Zone 故障后替补 Pod 能调度出去

`nodeTaintsPolicy: Honor` 会把带污点且 Pod 不容忍的 Node 排除在 skew 计算之外，Pod 没写 tolerations 也一样。Zone 故障时 Node 会带 `unreachable` 污点，Honor 会把该 Zone 排出计算，替补 Pod 才能落到存活 Zone；用默认的 `Ignore`，故障 Zone 仍按 0 个 Pod 计入，替补 Pod 可能 Pending。

### 2.4 `RollingUpdate: maxSurge: 1 / maxUnavailable: 0` —— 发布零中断的闸门是它，不是 PDB

先起新 Pod 再删旧 Pod，旧 Pod 全程在线。但代价是：surge Pod 只能落在当前最少的 Zone，如果那个 Zone 没有可调度 Node，surge Pod Pending，发布会卡住，旧版本继续服务——没有 downtime，但新版本上不去。

### 2.5 `PDB: maxUnavailable: 1` —— 只管自愿中断，不管故障和发布

它只拦截 Eviction API，也就是 `kubectl drain`、GKE 节点升级、Cluster Autoscaler 缩容。Pod 自己挂掉、Zone 故障，PDB 不参与；Deployment 滚动更新走 delete，也不经过 PDB。所以 2 副本时，维护期间 PDB 允许驱逐到只剩 **1** 个 Pod。

#### `maxUnavailable` 是越小越好吗？——不是，只看一半就错了

你的理解前半句是对的：`maxUnavailable` 的字面意思就是**自愿中断期间，允许同时不可用的 Pod 数量上限**，数值越小，允许同时掉的 Pod 越少，可用底线就越高：

```
最少可用数 = 副本数 - maxUnavailable
```

| `maxUnavailable` | 2 副本时最少可用 | 3 副本时最少可用 | 5 副本时最少可用 |
| :---: | :---: | :---: | :---: |
| 0 | 2 | 3 | 5 |
| **1（当前配置）** | **1** | **2** | **4** |
| 2 | 0 | 1 | 3 |

但“越小越好”只在**可用性**这一个维度上成立，换到**可运维性**这个维度就反过来了：

- **`maxUnavailable: 0` 看起来最安全，实际上基本不可用。** 它意味着一次也不允许驱逐，`disruptionsAllowed` 恒为 0，`kubectl drain` 会被 PDB 一直挡住，GKE 节点升级、节点缩容都会卡死，只能先手动删掉 PDB 再升级——等于把保护关掉了。
- **数值越小，升级 / drain 越慢，也越容易被卡住。** `maxUnavailable: 1` 只能逐个节点推进；如果已经有 1 个 Pod 不 Ready（还没恢复），`disruptionsAllowed` 就变成 0，下一次驱逐直接被挡住，升级窗口会被拉长。
- **数值越大，升级越快，但底线越低。** `maxUnavailable: 2` 一次可动 2 个 Pod，升级快、不容易卡，但底线要再降 1 个（见 §10）。

所以正确的理解不是“越小越好”，而是：**在“维护能正常进行”的前提下，取能保住底线的最小值**。对 2~5 副本这个量级来说，`1` 通常就是这个平衡点——允许维护逐个进行，同时底线是 `副本数 - 1`。如果把副本数提到 3~4，再配 `maxUnavailable: 1`，底线就是 2~3，这才是 §7、§11 推荐的组合。

注意不要和 Deployment 的 `maxUnavailable: 0`（§2.4）混淆：那个 0 是对的，因为滚动更新是先起 surge Pod 再删旧 Pod，不需要走 Eviction API，0 不会卡住发布；PDB 的 0 却会卡住 drain，机制完全不同。

### 2.6 `HPA: 2~5` —— 副本数的上下界

2 是下限，5 是上限。第 1 节的 2~5 档都是它决定的。

---

## 3. 原文档的两处错误（已修正）

| # | 原文档说法 | 判定 | 正确说法 |
| :--- | :--- | :---: | :--- |
| 1 | §5：2 副本时“单 Zone 故障，2 个 Pod 同处该 Zone，两个一起死，有 downtime” | ❌ 错误 | 稳态下 2 副本是 `1/1/0`，单 Zone 故障只掉 1 个，剩 1 个继续服务，只是容量减半。除非缩容漂移后两个 Pod 恰好同 Zone，才会全灭 |
| 2 | “3 副本单 Zone 故障容量不降” | ⚠️ 夸大 | 3 个变 2 个，容量降 1/3；准确说法是“仍有 2 个 Pod，且 HPA 会在存活 Zone 补容量” |
| 3 | “不要加 `minDomains`，因为它会在 Zone 不足时放弃约束、退化为挤同一 Zone” | ❌ 理由错，结论对 | `minDomains` 在可用 Zone 数不足时是把全局最小值当 0，约束**更严**（多出的 Pod Pending），不是放弃约束。Zone 数 ≥ 3 时它不起作用，所以没必要加 |

---

## 4. 这份 YAML 达不到的三个效果

| 你可能想要的效果 | 实际效果 | 结论 |
| :--- | :--- | :--- |
| Pod 落不同 Node | `required` + hostname，硬保证 | ✅ 达成 |
| Zone 尽量分布 | `DoNotSchedule` + `maxSkew: 1`，调度时硬保证 | ✅ 达成，强度高于需求 |
| 保留至少 2 个副本 | HPA min=2，但 PDB 底线是 1 | ❌ 口径不符 |
| 单 Zone 故障不降容 | 2 副本掉一半，3 副本掉 1/3 | ⚠️ 需要决策 |

要真正做到“任意时刻至少 2 个可用 + 每 Zone 一个”，要改成 **`minReplicas: 3` + PDB `minAvailable: 2`**。但即使这样，“容量一点不降”也是做不到的——丢了一个 Zone 就丢了那个 Zone 的 Pod，只能靠 HPA 事后在存活 Zone 补回来。

---

## 5. 静默风险：缩容漂移

topologySpread 只在**调度时**生效，不会主动重新平衡。HPA 从 5 缩到 2（`2/2/1`），ReplicaSet 删 Pod 时不看 Zone，理论上可能变成 `2/0/0`，两个 Pod 同 Zone，那个 Zone 一故障就全灭。

缓解方式：

| 方式 | 说明 |
| :--- | :--- |
| 部署 Descheduler | 启用 `RemovePodsViolatingTopologySpreadConstraint`，定期把违规 Pod 重新调度 |
| `minReplicas: 3` | 稳态每 Zone 各 1 个，缩容后最差也只是 `1/1/0` 型漂移 |
| 告警 | `max(zoneCount) - min(zoneCount) > 1` 时告警 |

---

## 6. 不要加 `minDomains`

3 个 Zone 时它不起作用；Zone 数不足时，它不是“放弃约束”，而是把全局最小值当 0 来算 skew，约束**更严**，多出的 Pod 会 Pending。Kubernetes 官方语义：可用域数小于 `minDomains` 时，全局最小值按 0 计算；大于等于时则无影响。所以加 `minDomains: 3` 反而会在 Zone 故障恢复时卡住替补 Pod。

---

## 7. 建议

| 优先级 | 动作 | 理由 |
| :---: | :---: | :---: |
| P0 | 保持 `DoNotSchedule`、`required` hostname、`Honor/Honor`，不加 `minDomains` | 当前拓扑设计正确，`Honor` 对 Zone 故障恢复有实际作用 |
| P0 | 加告警：Zone 分布失衡、可用 Zone 数 < 3、Kong Pod Pending | 失去 Zone 冗余是静默的 |
| P1 | `minReplicas: 2 → 3`，PDB 改为 `minAvailable: 2` | 对齐“至少 2 个可用”和“每 Zone 一个” |
| P1 | 部署 Descheduler 或定期巡检 Zone 分布 | 解决缩容漂移 |

---

## 8. 验证命令

```bash
NS=clienta-int-kdp
SEL='app.kubernetes.io/component=app,app.kubernetes.io/instance=clienta-int-kdp-prd,app.kubernetes.io/name=kong'

# Pod 所在 Node 及其 Zone（先确认 Node 的 zone 标签）
kubectl get pod -n $NS -l "$SEL" -o wide
kubectl get node -L topology.kubernetes.io/zone

# 按 Zone 统计 Pod 数（逐个 Node 反查 Zone）
for n in $(kubectl get pod -n $NS -l "$SEL" -o jsonpath='{.items[*].spec.nodeName}'); do
  kubectl get node $n -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}'
done | sort | uniq -c

# PDB 状态
kubectl get pdb -n $NS clienta-int-kdp-prd-kong
```

> 注意：Pod 本身没有 `topology.kubernetes.io/zone` 标签，直接读 Pod 标签会得到空结果，需要像上面这样通过 Node 反查。

---

## 9. 一句话总结

> 稳态下，2 副本就是 `1/1/0`，3 副本就是 `1/1/1`，4 副本 `2/1/1`，5 副本 `2/2/1`，skew 恒 ≤ 1，每个 Pod 独占 Node，单 Node / 单 Zone 故障都不中断，只是容量会掉；真正的短板不在拓扑约束，而在 **PDB 底线只有 1、缩容后分布可能漂移、以及 Node 数够不够滚动更新**。

---

## 关联文档

- `kong-spread-ha-review.md` —— 原文档评审
- `kong-spread-ha-review-claude.md` —— Claude 评审（修正了原文档 §5 的错误）
- `pdb-multi-zone-spread-ha.md` —— 通用方法论：Zone 分布约束选型、`required` vs `topologySpread`、`minDomains` 语义

---

## 10. 补充（2026-11-19）：PDB `maxUnavailable: 1 → 2` 的影响

> 只改 PDB 这一行：`spec.maxUnavailable: 1` 改为 `2`，其他配置（HPA 2~5、RollingUpdate `maxSurge: 1 / maxUnavailable: 0`、反亲和、topologySpread）不变。

### 10.1 一句话结论

**可用性底线整体下调 1 个 Pod，换来节点升级 / drain 更快、更不容易被 PDB 卡住。**
在 HPA 下限 2 副本时这个交换不划算：维护期间可能跌到 **0 个可用 Pod，全量 downtime**。

### 10.2 按副本数的数字对比

PDB 的底线公式是：`最少可用数 = 副本数 - maxUnavailable`（`disruptionsAllowed` 就是这个差值对应的可驱逐数）。

| 副本数 | `maxUnavailable: 1` 时最少可用 | `maxUnavailable: 2` 时最少可用 | 变化 |
| :---: | :---: | :---: | :---: |
| **2**（HPA min） | **1** | **0** | -1，**可能全灭** |
| **3** | **2** | **1** | -1，变成单点 |
| **4** | **3** | **2** | -1，仍保 2 个 |
| **5**（HPA max） | **4** | **3** | -1，仍保 3 个 |

### 10.3 对 Zone 分布的影响：维护窗口内 Zone 冗余会丢

PDB 只看全局可用 Pod 数，**不感知 Zone**。一次允许驱逐 2 个，drain 的顺序又是按 Node 走的，不是按 Zone 走的，所以维护期间的分布可能变成：

| 副本数 | 稳态分布 | 改为 `maxUnavailable: 2` 后，维护期间可能变成 |
| :---: | :---: | :---: |
| 2 | `1/1/0` | `0/0/0` —— 两个 Pod 都被驱逐，**全量 downtime** |
| 3 | `1/1/1` | `1/0/0` —— 只剩 1 个 Zone、1 个 Pod，单点；这个 Zone 再出故障即 downtime |
| 4 | `2/1/1` | 最差剩 2 个 Pod，例如 `0/1/1` 或 `1/0/1`，仍有 2 个 Zone |
| 5 | `2/2/1` | 最差剩 3 个 Pod，例如 `1/1/1` 或 `2/1/0` |

注意：上面是**底线（保证值）**，不是每次都会跌到那个值。如果 drain 是严格逐节点、且替补 Pod 变 Ready 后才驱逐下一个，实际可用数可能高于底线。但 PDB 改成 2 之后，**底线本身就允许**第二 个驱逐在第一个替补 Pod 还没 Ready 时就发生，所以这个窗口是真实存在的，不能靠“一般不会同时”来兜底。

### 10.4 带来的好处：升级 / drain 更快、更少被卡住

| 方面 | `maxUnavailable: 1` | `maxUnavailable: 2` |
| :--- | :--- | :--- |
| GKE 节点升级 / `kubectl drain` 并行度 | 一次只动 1 个 Pod，逐节点推进 | 一次可动 2 个 Pod，升级窗口缩短 |
| 已有 1 个 Pod 不 Ready 时 | `disruptionsAllowed = 0`，drain 被 PDB 挡住 | 还允许再驱逐 1 个，不容易卡住升级 |
| Cluster Autoscaler 缩节点 | 一次只缩 1 个相关 Pod | 可并行缩 2 个 |

### 10.5 没有影响的三件事（容易误解）

| 事项 | 有没有影响 | 原因 |
| :--- | :--- | :---: |
| Deployment 滚动更新速度 / 零中断 | ❌ 没有 | 滚动更新走 delete，不经过 Eviction API，PDB 不拦它；闸门是 Deployment 自己的 `maxUnavailable: 0`，不是 PDB |
| Pod 自己挂掉、Node / Zone 非自愿故障 | ❌ 没有 | PDB 只管自愿中断（drain / 升级 / 主动驱逐），非自愿故障它不参与 |
| 稳态分布（`1/1/0`、`1/1/1` 等） | ❌ 没有 | PDB 不参与调度，分布由反亲和 + topologySpread 决定；改 PDB 不会让稳态分布变好或变差 |
| HPA 缩容 | ❌ 没有 | HPA 缩容是 Deployment 直接删 Pod，同样不走 Eviction API |

### 10.6 建议

| 场景 | 建议 |
| :--- | :--- |
| 当前状态（HPA min=2） | **不要改成 2**。底线变 0，等于在维护窗口主动放弃高可用 |
| 想加快节点升级，又想保底线 ≥ 2 | 先把 `minReplicas` 提到 **4**，再改 `maxUnavailable: 2`，这样底线仍是 2；或者保持 `maxUnavailable: 1`，改用 GKE surge upgrade 让替补 Pod 先起来 |
| 副本数长期在 4~5 档 | 改成 2 的代价相对小（底线 2~3），可以接受，但仍要接受维护窗口内 Zone 冗余可能只剩 2 个 Zone |
| 不要用 `minAvailable: 2` 来“等价替代” | 在 3 副本时它等价于 `maxUnavailable: 1`，但在 5 副本时它允许同时驱逐 3 个，比 `maxUnavailable: 2` 还松，用之前要按最大副本数算一遍底线 |

### 10.7 改完后如何验证

```bash
NS=clienta-int-kdp

# PDB 状态：看 Allowed disruptions 是否变成 2
kubectl get pdb -n $NS clienta-int-kdp-prd-kong
kubectl describe pdb -n $NS clienta-int-kdp-prd-kong | grep -E 'Allowed disruptions|Current|Desired'

# 升级 / drain 前预演（不改任何状态）
kubectl drain <node> --dry-run=server --ignore-daemonsets
```

---

## 11. 补充（2026-11-19）：`HPA min=3` + PDB `maxUnavailable: 2` 能不能完美解决所有问题？

> 提案：`HPA minReplicas: 2 → 3`，同时 `PDB maxUnavailable: 1 → 2`，其他配置不变。

### 11.1 一句话结论

**不能完美解决。这个组合只解决了一半问题，另一半反而被它自己削弱了。**

它确实让稳态分布变好了（3 副本 `1/1/1`，每 Zone 一个），但在最常待的低负载稳态（恰好 3 副本）下，自愿中断的底线仍然是 **1 个 Pod**，和原来 `min=2 + maxUnavailable: 1` 的底线一样——维护窗口内还是单点。

### 11.2 先算数：底线公式不变

最少可用数 = 副本数 - `maxUnavailable`。`min=3` 只是把副本数的起点抬高了 1，`maxUnavailable=2` 又把底线拉低了 1，两者正好抵消。

| 组合 | 副本数 3 时最少可用 | 副本数 4 时 | 副本数 5 时 | 稳态分布（低负载） |
| :--- | :---: | :---: | :---: | :---: |
| 现状：`min=2` + `maxUnavailable: 1` | 2（当副本=3 时）/ **1（当副本=2 时）** | 3 | 4 | `1/1/0` |
| 提案：`min=3` + `maxUnavailable: 2` | **1** | 2 | 3 | `1/1/1` |
| 对照：`min=3` + `maxUnavailable: 1` | **2** | 3 | 4 | `1/1/1` |
| 对照：`min=4` + `maxUnavailable: 2` | —（副本数 ≥4） | **2** | 3 | `2/1/1` |

读表要点：

- 提案在 3 副本时的底线是 **1**，不是 2。要“任意时刻至少 2 个可用”，需要满足 `副本数 - maxUnavailable ≥ 2`，即 `maxUnavailable: 2` 时副本数至少要 **4**。
- 提案的唯一优势在稳态分布：低负载时从 `1/1/0` 变成 `1/1/1`，单 Zone 故障后剩 2 个 Pod（-33%），而不是剩 1 个（-50%）。这个收益来自 `min=3`，不是来自 `maxUnavailable: 2`。
- 同样是 `min=3`，配 `maxUnavailable: 1` 时底线是 2，配 `maxUnavailable: 2` 时底线是 1。**`maxUnavailable: 2` 在这里没有带来任何可用性收益，它带来的是更快的 drain / 升级速度，代价是底线更低。**

### 11.3 维护窗口内会发生什么

PDB 只看全局可用 Pod 数，不感知 Zone。`1/1/1` 的分布下一次允许驱逐 2 个，drain 按 Node 顺序走，可能变成：

| 场景 | 分布变化 | 后果 |
| :--- | :---: | :---: |
| 驱逐 2 个 Pod | `1/1/1` → `1/0/0` | 只剩 1 个 Zone、1 个 Pod，单点；这个 Zone 再出故障即 downtime |
| 驱逐 1 个 Pod（`maxUnavailable: 1` 时） | `1/1/1` → `1/1/0` | 剩 2 个 Zone、2 个 Pod，仍有 Zone 冗余 |

所以提案的组合是：**平时（稳态）Zone 冗余是满的，一到维护窗口，Zone 冗余就可能只剩 1 个 Zone**。而维护窗口恰恰是节点升级、drain 最频繁的时候。

### 11.4 即使换成 `min=4 + maxUnavailable: 2`，也不能“完美”

`min=4 + maxUnavailable: 2` 确实同时做到了“底线 ≥ 2”和“一次可驱逐 2 个”，是“又要快、又要保 2 个”这个目标下最便宜的组合。但它仍然解决不了这些问题：

| 问题 | 为什么解决不了 |
| :--- | :--- |
| 单 Zone 故障容量下降 | 4 副本 `2/1/1`，丢了有 2 个 Pod 的 Zone 就剩 2 个（-50%）；任何有限副本数都一样，丢一个 Zone 就丢那个 Zone 的 Pod，只能靠 HPA 事后补 |
| 非自愿故障（Pod 挂掉、Node / Zone 故障） | PDB 只管自愿中断，非自愿故障它不参与 |
| 缩容漂移 | topologySpread 只在调度时生效，HPA 缩容删 Pod 时不看 Zone，分布可能漂移（见 §5） |
| 滚动更新卡住 | surge Pod 只能去当前最少的 Zone，那个 Zone 没 Node 就 Pending，PDB 改不改都不影响 |
| 只有 1~2 个可用 Zone 时静默失去冗余 | 约束不报错也不告警，只能靠监控发现 |

“完美”在数学上就不存在：要单 Zone 故障容量一点不降，需要无限副本；要任何时刻都不降，需要零中断的维护——这两者都不可能。能做到的只是**把底线、容量损失、升级速度、成本这四者之间的取舍写清楚**。

### 11.5 四种组合的取舍表

| 组合 | 低负载稳态分布 | 自愿中断底线（低负载） | 单 Zone 故障后剩几个 | drain / 升级速度 | 成本（低负载 Pod 数） |
| :--- | :---: | :---: | :---: | :---: | :---: |
| 现状：`min=2` + `maxU: 1` | `1/1/0` | 1 | 1（-50%） | 慢（一次 1 个） | 2 |
| 提案：`min=3` + `maxU: 2` | `1/1/1` | **1** | 2（-33%） | 快（一次 2 个） | 3 |
| **推荐：`min=3` + `maxU: 1`** | `1/1/1` | **2** | 2（-33%） | 慢（一次 1 个） | 3 |
| 又要快又要保 2：`min=4` + `maxU: 2` | `2/1/1` | **2** | 最差 2（-50%） | 快（一次 2 个） | 4 |

### 11.6 建议

| 你的优先级 | 选哪个组合 |
| :--- | :--- |
| **高可用优先**（最在意“任意时刻至少 2 个可用”） | **`min=3` + `maxUnavailable: 1`**。这是成本最低、底线最稳的组合，和 §7 的 P1 建议一致 |
| **升级速度也重要，又要保 2 个** | **`min=4` + `maxUnavailable: 2`**。多 1 个 Pod 的成本，换来 drain 并行度翻倍且底线仍是 2 |
| **升级速度优先，能接受维护窗口单点** | 提案的 `min=3` + `maxUnavailable: 2` 可以接受，但要明确写下来：维护窗口内允许只剩 1 个 Pod、1 个 Zone，并配好告警 |
| **不要选** | `min=3` + `maxUnavailable: 2` 却以为它“完美解决了所有问题”——它在 3 副本时的底线和现状一样，都是 1 |

---

## 12. 总结（2026-11-19）：最终配置 `HPA min=3 / max=5` + PDB `maxUnavailable: 1`

> 最终定稿配置（只改两处，其他不变）：
>
> ```yaml
> # ── HorizontalPodAutoscaler ───────────────────────────────────────────
> spec:
>   minReplicas: 3
>   maxReplicas: 5
> ---
> # ── PodDisruptionBudget ──────────────────────────────────────────────
> spec:
>   maxUnavailable: 1
> ```
>
> 其他配置保持原样：`podAntiAffinity: required + hostname`、`topologySpreadConstraints: maxSkew: 1 + zone + DoNotSchedule + Honor/Honor`、`RollingUpdate: maxSurge: 1 / maxUnavailable: 0`。

### 12.1 一句话结论

**这是成本最低、底线最稳的组合：低负载时每 Zone 各 1 个 Pod，任意时刻（包括维护期间）至少 2 个 Pod 可用。**

### 12.2 数字总表：这个配置能达到什么

| 副本数 | 稳态分布 a/b/c | 自愿中断时最少可用 | 单 Zone 故障后剩几个 | 单 Node 故障后剩几个 | 滚动更新瞬时分布 |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **3**（HPA min，最常待的状态） | **1/1/1** | **2** | **2**（-33%） | 2 | `2/1/1` |
| **4** | **2/1/1** | **3** | **2~3**（最差 -50%） | 3 | `2/2/1` |
| **5**（HPA max） | **2/2/1** | **4** | **3~4**（最差 -40%） | 4 | `2/2/2`，需 6 个 Node |

底线公式：最少可用数 = 副本数 - `maxUnavailable` = 副本数 - 1，所以在这个配置下**底线恒 ≥ 2**。

### 12.3 和原来配置（`min=2` + `maxUnavailable: 1`）的对比

| 维度 | 原来：`min=2` + `maxU: 1` | 现在：`min=3` + `maxU: 1` | 变化 |
| :--- | :---: | :---: | :---: |
| 低负载稳态分布 | `1/1/0`，第 3 个 Zone 空着 | `1/1/1`，每 Zone 各 1 个 | ✅ Zone 容灾完整 |
| 自愿中断时最少可用 | 1 | **2** | ✅ 不再是单点 |
| 单 Zone 故障后剩几个 | 1（-50%） | **2**（-33%） | ✅ 容量损失更小 |
| 维护期间 Zone 冗余 | 驱逐 1 个 → 只剩 1 个 Zone | 驱逐 1 个 → `1/1/0`，仍剩 2 个 Zone | ✅ 维护期间仍有 Zone 冗余 |
| 升级 / drain 速度 | 一次 1 个 | 一次 1 个 | — 没变，仍是逐个推进 |
| 低负载成本 | 2 个 Pod | 3 个 Pod | +1 个 Pod |

### 12.4 这个配置解决了什么、没解决什么

**解决了：**

- ✅ “保留至少 2 个副本”——现在 PDB 语义下也成立了，任意时刻最少可用 2 个，不再是原来底线只有 1 的口径不符
- ✅ “每 Zone 一个 Pod”——低负载稳态就是 `1/1/1`，单 Zone 故障后仍剩 2 个 Pod
- ✅ 维护期间的 Zone 冗余——一次只驱逐 1 个，`1/1/1` 变成 `1/1/0`，仍有 2 个 Zone 在服务
- ✅ 缩容漂移的危害大幅降低——HPA 从 5 缩到 3 时，即使删 Pod 不看 Zone，剩下的 3 个 Pod 也不可能挤在同一个 Zone（每 Zone 最多 2 个），至少分布在 2 个 Zone

**没解决（仍需接受或另外处理）：**

- ⚠️ 单 Zone 故障容量仍会下降——3 副本时掉 1/3，4 副本最差掉一半；“容量一点不降”在任何有限副本数下都不可能，只能靠 HPA 事后在存活 Zone 补容量
- ⚠️ 升级 / drain 仍是一次 1 个 Pod，速度没有变快——这是 `maxUnavailable: 1` 的代价，换来的是底线更高；如果以后升级速度成了瓶颈，再考虑 `min=4` + `maxUnavailable: 2`（见 §11.5）
- ⚠️ 非自愿故障（Pod 挂掉、Node / Zone 故障）PDB 不参与，仍靠拓扑分布本身兜底
- ⚠️ 只有 1~2 个可用 Zone 时，约束不报错也不告警，仍需靠监控发现（见 §1 末尾的退化表）

### 12.5 落地后验证

```bash
NS=clienta-int-kdp
SEL='app.kubernetes.io/component=app,app.kubernetes.io/instance=clienta-int-kdp-prd,app.kubernetes.io/name=kong'

# 1. HPA 下限已是 3
kubectl get hpa -n $NS

# 2. 稳态分布应为 1/1/1（低负载时）
kubectl get pod -n $NS -l "$SEL" -o wide

# 3. PDB：Allowed disruptions 应为 1，最少可用为 2
kubectl get pdb -n $NS clienta-int-kdp-prd-kong
kubectl describe pdb -n $NS clienta-int-kdp-prd-kong | grep -E 'Allowed disruptions|Current|Desired'

# 4. Node 数：峰值滚动更新需 6 个可调度 Node
kubectl get node --no-headers | wc -l
```



这份分析报告的核心结论非常扎实，工程逻辑也很清晰（将 minReplicas 从 2 提到 3，配合 PDB maxUnavailable: 1 消除单点风险，这是生产环境中 Kong 这类核心网关的标准最佳实践）。

但如果你拿着这份文档做架构评审，里面有 3 个技术细节不严谨甚至存在潜在生产隐患的地方，建议修正或补充说明：

1. 滚动更新与 PDB 的“叠加效应”（文档漏算的最坏情况）

⚬ 原文问题：结论中提到“任意时刻（包括维护期间）至少 2 个 Pod 可用”，并在 §1 中假设“滚动更新中，旧 Pod 全程在线，容量变化 0”。
⚬ 实际情况：RollingUpdate（Deployment 控制器控制）和 PDB（只限制外部自愿驱逐如 Node Drain，不管 Deployment 自己的滚动更新）是两套独立机制。
  ⚬ 如果你在滚动更新的瞬间（新 Pod 刚 Ready 准备删旧 Pod，或者刚起 Surge 还没 Ready），恰好遇上节点缩容/维护（触发 PDB 驱逐），或者旧 Pod 正在经历 terminationGracePeriodSeconds 优雅退出但新 Pod 刚过 Readiness Probe 还没完全预热好，实际有效承载流量的 Pod 可能会短暂波动。
  ⚬ 更关键的是（HPA + RollingUpdate 交互）：当 minReplicas: 3 且处于滚动更新时，瞬时会有 4 个 Pod 都在跑，此时 HPA 计算平均 CPU/内存利用率的分母变成了 4（如果新旧 Pod 都在分担流量），会导致 HPA 误判负载降低；反之，如果刚扩容完又缩容，ReplicaSet 缩容删除 Pod 时不受 maxUnavailable: 0 保护，而是直接按 topologySpreadConstraints 的逆向逻辑删减，可能打破局部均衡（虽然最终仍满足 maxSkew: 1）。

2. topologySpreadConstraints 在“缩容/删除 Pod”时的盲区（严重隐患）

⚬ 原文问题：默认只要配了 maxSkew: 1，无论是扩缩容还是滚动更新，分布永远是完美的 1/1/1 或 2/1/1。
⚬ 实际情况：topologySpreadConstraints 只在调度（Create/Schedule）时生效，在删除（Scale Down / RollingUpdate 删旧 Pod）时完全不生效！
  ⚬ 翻车场景推演（3 副本滚动更新）：
    1. 更新前：a:1, b:1, c:1（共 3 个旧 Pod）。
    2. maxSurge: 1 启动第 1 个新 Pod，调度器选了 zone-a，此时分布为 a:2 (1旧1新), b:1 (1旧), c:1 (1旧)。
    3. 新 Pod Ready 后，Deployment 控制器需要删除 1 个旧 Pod。默认删除策略是按 Pod 创建时间/状态随机挑一个旧 Pod 删掉。
    4. 如果控制器删掉了 zone-b 的旧 Pod（而不是 zone-a 的旧 Pod），分布就变成了 a:2, b:0, c:1！
    5. 注意：虽然 a:2, b:0, c:1 的 skew 变成了 2，违反了 maxSkew: 1，但已经运行的 Pod 不会被驱逐，而且下一个 Surge Pod 必须去 zone-b，中间这段时间你就短暂失去了 zone-b 的容灾能力！
  ⚬ 修复建议：必须在 topologySpreadConstraints 中加上 matchLabelKeys: ["pod-template-hash"]（K8s 1.27+ 特性）。加上它之后，新旧版本的 Pod 会分开计算 Skew，新版本一定会严格按 1/1/1 调度，彻底解决滚动更新期间分布歪斜的问题。

3. “单 Zone 故障”的表述与实际行为偏差

⚬ 原文问题：表格中写“单 Zone 故障后剩 2 个（-33%）”，似乎默认这 2 个剩下的 Pod 依然是“可用”的。
⚬ 实际情况：
  1. Kong 网关的无状态/有状态边界：如果是 DB-less 模式，剩 2 个 Pod 确实直接能扛流量；但如果是传统连数据库模式，或者依赖本地缓存/限流计数器（如 rate-limiting 插件的 local 策略），单 Zone 故障后剩余 2 个 Pod 不仅要瞬间承接 +50% 的流量激增（从每人扛 33% 变成每人扛 50%），还会导致局部限流阈值失效。
  2. 跨 Zone 流量与负载均衡器摘除延迟：云厂商的 LB（如 GCP/AWS/阿里云 SLB）或上游 Ingress 在感知到整个 Zone 失联（黑洞/网络分区而非 Pod 优雅退出）时，健康检查通常有 10~30 秒的探测超时。在这几十秒内，打向故障 Zone 的 33% 流量是直接丢包/502的，并不是无感切换。
  3. HPA 抢救反噬：单 Zone 故障后，剩下 2 个 Pod 负载飙升，HPA 会立刻尝试扩容第 3 个 Pod。由于故障 Zone 不可用，新 Pod 会被调度到剩下的两个 Zone（变成 2/1/0）。前提是那两个 Zone 里还有空闲的 Node（因为你配了 kubernetes.io/hostname 的硬反亲和 requiredDuringScheduling）。如果集群开启了 Cluster Autoscaler，等新 Node 弹出来通常需要 1~3 分钟，这期间只有 2 个 Pod 硬扛。

总结：给你的评审修改建议

原文的 90% 都是正确的，配置方向完全没问题。只需在文档中补充以下 3 条“防坑补丁”，这份设计文档就无懈可击了：

1. YAML 补丁：在 topologySpreadConstraints 中增加 matchLabelKeys: ["pod-template-hash"]（如果集群版本 ≥ 1.27），防止滚动更新删旧 Pod 时把某一个 Zone 删空。
2. 前置条件补充：明确写出 Cluster Autoscaler / Node Pool 冗余要求——因为配置了 hostname 硬反亲和，单 Zone 故障后，另外两个 Zone 必须预留足够的闲置 Node 槽位，否则 HPA 扩容出的新 Pod 会直接 Pending。
3. 术语微调：将“任意时刻至少 2 个 Pod 可用”修正为“在非极端级联故障（如滚动更新与节点维护同时发生）下，至少 2 个 Pod 可用”，避免架构评审时被挑战边界条件。