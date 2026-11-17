# Sidecar → Ambient 迁移硬约束 — L7 策略 Zero-Downtime 不支持

> **TL;DR**:
> - **官方原话**:"Zero-downtime migration with L7 policies is **not currently supported**. Plan a maintenance window."
> - 这是 Istio 1.30 文档**明示的硬限制** — 不是 best practice,是 **未实现的功能**
> - 原因:sidecar 的 `selector.matchLabels` 与 ambient waypoint 的 `targetRefs` 没有"原子切换"路径
> - 本场景的应对:**用 namespace 切换 + 应用 readiness probe 兜底**(本目录 04 文已涵盖)

---

## 0. 官方原话与出处

> 来源:
> - [Istio Sidecar to Ambient Migration](https://istio.io/latest/docs/ambient/install/migrate-from-sidecar/) — Before you begin
> - [Istio Migration Policies](https://istio.io/latest/docs/ambient/install/migrate-from-sidecar/migrate-policies/)

**官方原话**(Before you begin 章节):

> "If your workloads use L7 policies, migration is not straightforward and currently has known limitations:
>
> - During migration, there is a window where L7 policies may not be enforced, old selector-based policies must be removed, and new waypoint-based equivalents must take their place. There is no atomic handoff between the two.
> - While some source workloads are still in sidecar mode, traffic from those workloads bypasses waypoints entirely. L7 policies on the waypoint are not enforced for that traffic path until the source is also migrated.
>
> **Zero-downtime migration with L7 policies is not currently supported. Plan a maintenance window.** This is a known limitation being tracked for improvement in a future release."

→ **这是 1.30 的硬约束**,**没有 workaround**。

---

## 1. 为什么没有 atomic handoff

### 1.1 selector vs targetRefs 的本质差异

```
sidecar 模式:
─────────────────────────────────────────────────
spec:
  selector:
    matchLabels:
      app: api-a    ← 绑 pod label

  ↑ envoy 在 pod 启动时拉这个策略配置

ambient 模式:
─────────────────────────────────────────────────
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-a   ← 绑 Service / Gateway

  ↑ waypoint 在 ns enroll 时拉这个策略配置
```

**关键差异**:
- sidecar 模式下,策略**在 pod 启动时加载**到 envoy 内存
- ambient 模式下,策略**在 waypoint 创建时加载**到 waypoint envoy 内存
- pod 重启 ≠ 立刻应用新策略;**waypoint 看不到这个 pod**

**没有"pod 重启时同时切换生效的策略集"这种原子动作**。

### 1.2 切换时序中 L7 策略失效窗口

```
T0:  sidecar 模式,policy A 用 selector,生效中
T2:  加 waypoint,policy B 用 targetRefs,waypoint 还没装好
T3:  ns 加 ambient label
T4:  业务 pod 重启 → sidecar 移除,pod 无 sidecar
T5:  waypoint 装好,policy B 加载到 waypoint
─────────────────────────────────────────────────
   T3→T5 期间:L7 策略完全失效 ❌
```

具体表现:
- T3 时刻起,pod 不再注入,但 waypoint 还在创建中
- T4 时刻起,pod 内没有 sidecar,ns 内没有 waypoint → **mesh 仅有 L4 mTLS,无 L7 策略**
- T5 时刻起,waypoint 接管 L7,但需 pod 重连才会用新路径

→ 这个窗口期**没有任何机制能保证 L7 策略执行**。

---

## 2. selector → targetRefs 的迁移步骤(必须手工)

### 2.1 step 1:发现所有 selector-based L7 策略

```bash
# 列出所有 selector-based AuthorizationPolicy
kubectl get authorizationpolicy -A -o yaml | \
  grep -B 5 -A 5 "selector:" | \
  grep -E "name:|namespace:|selector:|targetRefs:"
```

### 2.2 step 2:识别哪些是 L7(用 `to.operation` 或 `when` 字段)

```bash
# L7 策略特征:
# - spec.rules[*].to[*].operation.hosts/methods/paths/ports
# - spec.rules[*].when[*]
# - spec.action = ALLOW/DENY/AUDIT/CUSTOM

# L4-only 策略(selector 仍可用):
# - 只用 from.source.ipBlocks / principals
# - 没 when,没 operation
```

### 2.3 step 3:为每个 L7 策略生成 targetRefs 版本

```yaml
# 原始(sidecar)
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-a-allow-internal
  namespace: team-a-runtime
spec:
  selector:
    matchLabels:
      app: api-a
  action: ALLOW
  rules:
    - from:
        - source:
            serviceAccounts: ["team-a-runtime/frontend-sa"]
```

```yaml
# 目标(ambient)
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-a-allow-internal
  namespace: team-a-runtime
spec:
  targetRefs:                          # ← selector 改 targetRefs
    - kind: Service
      group: ""
      name: api-a
  action: ALLOW
  rules:
    - from:
        - source:
            serviceAccounts: ["team-a-runtime/frontend-sa"]
```

**注意**:`selector.matchLabels` 与 `targetRefs` **互斥**,同 spec 只能选其一。

### 2.4 step 4:移除旧策略 + 应用新策略(顺序敏感)

```
❌ 错(同时改):
   kubectl apply targetRefs 版本 (立即覆盖)
   ↓
   L7 失效窗口立刻开始

✅ 对(A/B 切换 + 旧 policy 保留):
   1. 加新 targetRefs policy,但 action: AUDIT (演练模式,不真生效)
   2. 看 istioctl experimental authz check,确认新策略能匹配相同请求
   3. 把原 selector policy 删掉
   4. 把新 targetRefs policy action 改为 ALLOW/DENY
```

> Istio 官方迁移文档的 [Migrate Policies](https://istio.io/latest/docs/ambient/install/migrate-from-sidecar/migrate-policies/) 章节给了详细步骤。

---

## 3. 维护窗口策略(本场景的推荐做法)

### 3.1 你 dev 集群的最优做法

| 选项 | 适用 |
|---|---|
| **A. 选择低峰时段切 + readiness probe 兜底** | dev 集群可选;接受 L7 失效 5-15 分钟 |
| **B. 用 dry-run 演练切** | 先 AUDIT 模式观察,后切 ALLOW |

```bash
# Step 1: 加 dry-run annotation(演练)
kubectl annotate authorizationpolicy api-a-allow-internal \
  istio.io/dry-run=true --overwrite -n team-a-runtime

# Step 2: 观察(用 istioctl experimental authz check 看命中)
istioctl experimental authz check <pod-name> -n team-a-runtime

# Step 3: 切到 ambient mode(04 文流程)
# 此时 dry-run 仍生效,但请求被 waypoint 处理

# Step 4: 移除 dry-run annotation,真生效
kubectl annotate authorizationpolicy api-a-allow-internal istio.io/dry-run- -n team-a-runtime
```

### 3.2 生产环境的额外考量(目前不适用,但记下)

| 考量 | 建议 |
|---|---|
| **金丝雀切流** | 先 1 ns,观察 1-2 周,再切第二个 ns |
| **rollback 预案** | 切之前 export 所有 AuthorizationPolicy,出问题立即 kubectl apply 回滚 |
| **可观测性** | 切前 baseline 错误率,切中监控,异常立即回滚 |
| **变更窗口** | 安排业务低峰时段,通知所有依赖方 |

---

## 4. 反向:什么情况下 zero-downtime 成立

| 场景 | zero-downtime? |
|---|---|
| **没有 L7 策略**(只用 PeerAuthentication / NetworkPolicy) | ✅ **可行** — L4 永远在 mesh |
| **只有 waypoint targetRefs 策略**(新建,无 selector 老版本) | ✅ **可行** — 没有迁移期 |
| **有 selector L7 policy 待迁移** | ❌ **不可行** — 必须维护窗口 |
| **多语言微服务,但只有 1 个 team 用 L7** | ✅ 那个 team 切 ambient 时单独做 |

**本场景**:你 dev 集群现状是 **minimal profile + 没有 L7 policy 落地**(只 Gateway API,无 AuthorizationPolicy),所以 L7 zero-downtime 约束**目前不限制你**。

---

## 5. 关联约束:`VirtualService` Alpha 状态

> 来源:[Istio 1.30 Feature Status](https://istio.io/latest/docs/releases/feature-status/)

| 资源 | ambient 状态 |
|---|---|
| `HTTPRoute`(K8s Gateway API) | **Stable** ✅ |
| `GRPCRoute`(K8s Gateway API) | **Stable** ✅ |
| `TLSRoute` / `TCPRoute` | Alpha ⚠️ |
| `VirtualService`(Istio 传统) | **Alpha** ⚠️ |
| `DestinationRule` | Stable ✅ |

**结论**:任何 L7 路由 / 重试 / 切流,**用 `HTTPRoute` 而不是 `VirtualService`**。

---

## 6. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **Zero-downtime migration** | 切换不停机 | "Zero-downtime migration with L7 policies is not currently supported. Plan a maintenance window." — [Istio Migration](https://istio.io/latest/docs/ambient/install/migrate-from-sidecar/) |
| **Selector handoff** | "无原子切换" | "There is no atomic handoff between the two" — Istio Migration |
| **Audit mode (dry-run)** | "只看不真生效" | "When the `istio.io/dry-run=true` annotation is set, the policy is loaded but not enforced; istiod reports what would be matched." — [Istio AuthZ](https://istio.io/latest/docs/reference/config/security/authorization-policy/) |

---

## 7. 给本场景的硬建议

| 建议 | 理由 |
|---|---|
| **01-04 文的迁移步骤加一段 "维护窗口"说明** | 现有 04 文没明说这个硬约束 |
| **本目录加 README.md 提示** | 让所有读者看到 1.30 的 L7 zero-downtime 限制 |
| **dev 集群可以激进切**(L7 失效影响小) | dev 没生产负载 |
| **生产集群切 ambient 前先做完整 dry-run** | 用 `istio.io/dry-run=true` 演练 1-2 周 |
| **所有 L7 AuthZ 必须有 targetRefs 版本** | 切之前就准备好,不卡切流 |

---

## 8. References

- [Istio Sidecar to Ambient Migration: Before you begin](https://istio.io/latest/docs/ambient/install/migrate-from-sidecar/) — L7 zero-downtime 限制原话
- [Istio Migrate Policies](https://istio.io/latest/docs/ambient/install/migrate-from-sidecar/migrate-policies/) — selector → targetRefs 步骤
- [Istio AuthorizationPolicy reference](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — selector vs targetRefs 互斥
- [Istio 1.30 Feature Status](https://istio.io/latest/docs/releases/feature-status/) — VirtualService Alpha 状态
- [Istio Authorization dry-run](https://istio.io/latest/docs/tasks/security/authorization/authz-dry-run/) — audit mode 演练