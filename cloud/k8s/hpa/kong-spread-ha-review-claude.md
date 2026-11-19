# Kong PRD 拓扑配置评审（忽略 Node 数量瓶颈）

> 配置：`required podAntiAffinity(hostname)` + `topologySpread(zone, maxSkew:1, DoNotSchedule, Honor/Honor)` + `HPA 2~5` + `PDB maxUnavailable:1` + `RollingUpdate 1/0`
> 前提：集群有 3 个可用 Zone（a/b/c），Node 充足。

---


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
  maxUnavailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/component: app
      app.kubernetes.io/instance: clienta-int-kdp-prd
      app.kubernetes.io/name: kong
```

## 1. 原文档结论核对

| # | 原文档结论 | 判定 | 说明 |
|:--|:---|:--:|:---|
| 1 | hostname 反亲和 `required` = 不同 Node 硬保证 | ✅ 正确 | 不满足则 Pending |
| 2 | Zone 用 `DoNotSchedule` = 硬保证，强度超出"尽量"的需求 | ✅ 正确 | 想要"尽量"应改 `ScheduleAnyway` |
| 3 | PDB `maxUnavailable:1` 在 2 副本时底线是 1，不是 2 | ✅ 正确 | 要保 2 个必须 3 副本 + `minAvailable:2` |
| 4 | PDB 不阻止 Deployment 滚动更新，发布闸门是 `maxUnavailable:0` | ✅ 正确 | PDB 只拦 Eviction API |
| 5 | 副本 ≤ Zone 数时"必然"每 Zone 至多 1 个 | ⚠️ 不严谨 | 只在**调度时**保证；**缩容后**可能漂移（见第 3 节） |
| 6 | §5 表：单 Zone 故障时"2 个 Pod 同处该 Zone，两个一起死，有 downtime" | ❌ 错误 | 与自己的结论矛盾。稳态下 2 个 Pod 在 2 个不同 Zone，单 Zone 故障只掉 1 个，剩 1 个继续服务（容量减半）。只有缩容漂移后两个 Pod 同 Zone 才会全灭 |
| 7 | R1 标题"单 Zone 故障导致全量 downtime" | ⚠️ 夸大 | 应为"容量减半，单 Pod 扛不住才 downtime" |
| 8 | 3 副本"单 Zone 故障容量不降" | ⚠️ 夸大 | 3 个变 2 个，容量降 1/3；准确说法是"仍有 2 个 Pod，且 HPA 会在存活 Zone 补容量" |
| 9 | "不要加 `minDomains`" | ✅ 结论对，❌ 理由错 | `minDomains` 在可用 Zone 数不足时是把全局最小值当 0，约束**更严**（多出的 Pod Pending），不是"放弃约束退化为挤同一 Zone"。Zone 数 ≥3 时它不起作用，所以没必要加 |
| 10 | "`Honor` 只在 Pod 定义了 nodeAffinity/tolerations 时才有区别" | ❌ 错误 | `nodeTaintsPolicy: Honor` 会排除带污点且 Pod 不容忍的 Node，Pod 没写 tolerations 也一样。Zone 故障时 Node 带 `unreachable` 污点，Honor 会把该 Zone 排出 skew 计算，替补 Pod 才能调度到存活 Zone。若用默认的 `Ignore`，故障 Zone 仍按 0 个 Pod 计入，替补 Pod 可能 Pending |
| 11 | R8"HPA 缩容 + `maxUnavailable:0` 会让 rollout 挂起" | ⚠️ 依据不足 | 通常不会挂起，可降级为观察项 |
| 12 | "HPA 缩容后，下次新建 Pod 时 skew 自动回正" | ⚠️ 不严谨 | 只有新建 Pod 才会校正，缩容本身不会重新平衡 |

---

## 2. 配置能达到的分布结果（核心表）

| 期望副本数 | 可达到的分布（a/b/c） | 后续要求及含义 | 可能的隐患 |
|:---:|:---|:---|:---|
| **2**<br>（HPA min） | `1/1/0`（任意两个 Zone 各 1 个）<br>每个 Pod 独占 1 个 Node | • 2 个 Pod 必在 2 个不同 Zone（调度时硬保证）<br>• 单 Node 或单 Zone 故障：剩 1 个 Pod，不中断但容量减半<br>• 替补 Pod 会补到缺失的 Zone | • PDB 底线是 1，维护期间可能变成单 Pod<br>• 第 3 个 Zone 没有 Pod<br>• 缩容漂移后两个 Pod 可能同 Zone，该 Zone 故障即全灭 |
| **3** | `1/1/1` | • 3 个 Zone 各 1 个，**Zone 容灾完整**<br>• 单 Zone 故障剩 2 个，容量降 1/3<br>• 推荐的目标态 | • 需 `minReplicas:3`，多 1 个 Pod 成本<br>• 缩容漂移后可能出现 `2/1/0` |
| **4** | `2/1/1` | • skew=1，满足约束<br>• 某 Zone 有 2 个 Pod，该 Zone 故障一次掉 2 个 | • 缩容或节点回收后可能漂移为 `2/2/0`，某个 Zone 为空 |
| **5**<br>（HPA max） | `2/2/1` | • skew 恒 ≤1，分布均衡<br>• 单 Zone 故障剩 3 个（掉 1 个或 2 个） | • 同上，缩容漂移风险 |
| **滚动更新中**<br>（副本数 +1） | 新 Pod 只能落在当前 Pod 最少的 Zone | • 如 2 副本 `1/1/0`：surge Pod 只能去 zone-c（去 a/b 会 skew=2）<br>• `maxUnavailable:0` 旧 Pod 全程在线，零 downtime | • 目标 Zone 无可调度 Node（升级中、满载、有污点）则 surge Pod Pending，**发布卡住**，旧版本继续服务<br>• 旧 Pod 被删后可能暂时偏斜，下一个新 Pod 只能补到缺的那个 Zone |

> 只有 2 个可用 Zone 时：2→`1/1`，3→`2/1`，4→`2/2`，5→`3/2`，仍无 downtime，但没有第 3 个 Zone 的冗余。
> 只有 1 个可用 Zone 时：约束**不报错也不告警**，所有 Pod 落同一个 Zone，会静默失去 Zone 冗余。

---

## 3. 原文档遗漏的关键隐患：缩容漂移

约束只在**调度时**生效，不会主动重新平衡。ReplicaSet 缩容选哪个 Pod 删时不看 Zone。

| 场景 | 可能的结果 | 影响 |
|:---|:---|:---|
| HPA 从 5 缩到 2（`2/2/1`） | 可能变成 `0/2/0`，两个 Pod 在同一 Zone | 该 Zone 故障 → **全灭 downtime** |
| HPA 从 5 缩到 3 | 可能变成 `2/1/0` | zone-c 无 Pod |
| 节点回收 / drain 后重建 | 新 Pod 受 skew 约束，会补到缺的 Zone | 自动修复，最安全 |

缓解方式：

| 方式 | 说明 |
|:---|:---|
| 部署 Descheduler | 启用 `RemovePodsViolatingTopologySpreadConstraint`，定期把违规 Pod 重新调度 |
| `minReplicas: 3` | 稳态每 Zone 各 1 个，缩容后最差也只是 `1/1/0` 型漂移 |
| 告警 | `max(zoneCount) - min(zoneCount) > 1` 时告警 |

---

## 4. 针对原需求的最终回答

| 原始需求 | 当前配置实际效果 | 结论 |
|:---|:---|:---|
| Pod 落不同 Node | `required` + hostname，硬保证 | ✅ 达成 |
| Zone 尽量分布 | `DoNotSchedule` + `maxSkew:1`，调度时硬保证 | ✅ 达成，强度高于需求 |
| 保留至少 2 个副本 | HPA min=2，但 PDB 底线是 1 | ❌ 口径不符 |
| 单 Zone 故障不降容 | 需要 `minReplicas≥3`，当前 2 个副本会掉一半容量 | ⚠️ 需决策 |

---

## 5. 建议

| 优先级 | 动作 | 理由 |
|:--:|:---|:---|
| P0 | 保持 `DoNotSchedule`、`required` hostname、`Honor/Honor`，不加 `minDomains` | 当前拓扑设计正确，`Honor` 对 Zone 故障恢复有实际作用 |
| P0 | 加告警：Zone 分布失衡、可用 Zone 数 <3、Kong Pod Pending | 失去 Zone 冗余是静默的 |
| P1 | `minReplicas: 2 → 3`，PDB 改为 `minAvailable: 2` | 对齐"至少 2 个可用"和"每 Zone 一个" |
| P1 | 部署 Descheduler 或定期巡检 Zone 分布 | 解决缩容漂移 |

## 6. 验证命令

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

> 注意：Pod 本身没有 `topology.kubernetes.io/zone` 标签，原文档 §9.1 的第 1 条命令直接读 Pod 标签会得到空结果，需要像上面这样通过 Node 反查。