# 22 · Resource Hooks 与同步阶段

> **直接回答**：「能不能把校验放到集群里做，而不是只在 GitHub 上做？」
> 「同一批资源里，哪些先上、哪些后上、失败了怎么停？」
>
> **一句话结论**
> ★ Argo CD 的同步不是"一次性 apply"，而是**四个阶段**：
> **PreSync → Sync → (SyncFail) → PostSync**。
> 每个阶段都可以挂 **hook 资源**（通常是 Job）。
> ★ **PreSync hook 就是一个"集群内门禁"**：它不成功，Sync 阶段**根本不会开始**。
> 这给了你第三种"手动"实现方式：**不靠 GitHub、不靠 driver，直接在集群里卡住**。

---

## 目录

| 章节 | 内容 |
|---|---|
| [`1](#1-四个同步阶段) | 阶段划分与执行顺序 |
| [`2](#2-hook-资源怎么写) | 注解、类型、删除策略 |
| [`3](#3-同步顺序三件套) | wave / phase / 依赖 |
| [`4](#4-用-presync-hook-做集群内门禁) | ★ 完整示例 + 与 GitHub 侧门禁的取舍 |
| [`5](#5-两种门禁的取舍矩阵) | GitHub 侧 vs 集群侧 |
| [`6](#6-坑清单) | 10 条坑 |

---

## 1. 四个同步阶段

**官方保证**（上游 `docs/user-guide/sync-waves.md`）：

| 阶段 | 何时执行 | 典型用途 | 失败后果 |
|---|---|---|---|
| **PreSync** | 同步**之前** | ★ 门禁校验、备份、迁移脚本 | ★ **Sync 阶段不执行**，整个同步失败 |
| **Sync** | 主同步阶段 | 真正的资源 apply | 按 `syncOptions` 决定行为 |
| **SyncFail** | 同步**失败**时 | 回滚脚本、告警、清理 | 只在失败时跑；它失败不影响主流程结论 |
| **PostSync** | 同步**成功**后 | 冒烟测试、通知、缓存预热 | 失败会让整个 operation 变成 failed（官方语义：PostSync 失败即同步失败） |

> ★ **关键**：**PreSync 失败 → 整个同步被拦下**，Application 的 operation 状态是 failed，
> **集群里的业务资源一个都不会变**。
> 这就是"集群内门禁"的原理。

> ⚠️ **PostSync 失败 ≠ 部署成功**。
> 如果你把"冒烟测试"放 PostSync，它失败会让 GitHub 上（通过 Notifications 回写）显示 **failure**，
> 尽管业务资源其实已经更新了。**要区分"资源已更新"和"验证已通过"，用两个不同的信号。**

---

## 2. hook 资源怎么写

**官方保证**（上游 `docs/user-guide/sync-waves.md` 与既有 [`app-of-apps`](../app-of-apps.md)）：

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: cr-compliance-gate
  annotations:
    argocd.argoproj.io/hook: PreSync          # ← 阶段
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
    argocd.argoproj.io/sync-wave: "-1"        # ← 顺序（比阶段更细）
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: gate
          image: <your-registry>/cr-gate:v1
          env:
            - name: APP_REVISION
              value: "{{.app.status.sync.revision}}"
```

| 注解 | 取值 | 作用 |
|---|---|---|
| `argocd.argoproj.io/hook` | `PreSync` / `Sync` / `PostSync` / `SyncFail` | 决定在哪个阶段执行 |
| `argocd.argoproj.io/hook-delete-policy` | `BeforeHookCreation` / `HookSucceeded` / `HookFailed` | hook 资源何时被删 |
| `argocd.argoproj.io/sync-wave` | 整数 | **同一阶段内**的执行顺序 |
| `argocd.argoproj.io/sync-wave-namespaces` | 列表 | 按 namespace 分波次（批量应用场景） |

**删除策略语义**：

| 值 | 何时删 | 典型用途 |
|---|---|---|
| `BeforeHookCreation` | 下次同步创建同名 hook 前 | 每次都跑一次的校验 Job（★ 最常用） |
| `HookSucceeded` | 成功后 | 成功后要清理的一次性任务 |
| `HookFailed` | 失败后 | 失败后要留证据的排查任务 |
| 不写 | **永久保留** | 需要事后审计的记录 |

> ⚠️ **不写删除策略 = hook 资源会一直留在集群里**。
> Job 留在集群里 → 下次同步时 Argo CD 认为它是"已存在"，
> **必须靠 `BeforeHookCreation` 才会被替换**。

---

## 3. 同步顺序三件套

### 3.1 阶段（phase）> 波次（wave）

- **phase** 决定"在哪个大阶段"（PreSync/Sync/PostSync）。
- **wave** 决定"同一阶段内谁先谁后"。
- **执行顺序**：按 phase 顺序 → phase 内按 wave 升序 → 同 wave 内并发。

> ★ 所以：想"先跑门禁，再上资源"，
> **门禁 wave = -1，资源 wave = 0**（或门禁放在 PreSync 阶段）。

### 3.2 典型分层

```yaml
# wave -1：PreSync 门禁
annotations:
  argocd.argoproj.io/hook: PreSync
  argocd.argoproj.io/sync-wave: "-1"
---
# wave 0：命名空间、配置、ServiceAccount
---
# wave 1：Deployment / StatefulSet
---
# wave 2：Service / Ingress
---
# wave 3：PostSync 冒烟测试
annotations:
  argocd.argoproj.io/hook: PostSync
  argocd.argoproj.io/sync-wave: "3"
```

> ★ 这正是既有 [`app-of-apps.md`](../app-of-apps.md) 里"部署顺序"的机制，
> 只不过那里是在**多个 Application 之间**用 wave，这里是在**同一个 Application 内**用 wave。

---

## 4. ★ 用 PreSync Hook 做集群内门禁

### 4.1 为什么值得做

| 维度 | GitHub 侧门禁（CR Check） | 集群内门禁（PreSync Hook） |
|---|---|---|
| 能判断的事 | PR 的**元信息**（分支、commit、CR 号、评审） | **实际要部署的内容**（渲染后的 YAML、目标集群的实时状态） |
| 能否看到集群 | ❌ | ✅ |
| 绕过路径 | 改仓库里的规则文件 | 需要能改集群（**权限更高**） |
| 失败时集群变了吗 | 没变 | ★ **没变**（PreSync 失败，Sync 不执行） |
| 适用 | "这次变更合不合规" | "这份 YAML 能不能安全落到这个集群" |

### 4.2 门禁 Job 能做什么（举例）

| 检查 | 实现方式 |
|---|---|
| 渲染后的 manifest 是否满足策略 | 门禁 Job 里读 `APP_REVISION` → 拉仓库 → 渲染 → 跑策略（OPA/Conftest） |
| 目标集群的现状是否允许这次变更 | 门禁 Job 用只读 SA 连集群，查配额/PDB/现有副本 |
| 变更单在 CR 平台是否仍然有效 | 门禁 Job 调 CR 平台 API（**与 GitHub 侧 CR Check 同一份规则**） |
| 依赖服务是否健康 | 门禁 Job 跑冒烟检查 |
| **变更前的快照/备份** | 门禁 Job 先备份，再放行 |

### 4.3 完整示例

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: "{{.app.metadata.name}}-presync-gate"
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    argocd.argoproj.io/sync-wave: "-1"
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: argo-cd-gate-runner
      containers:
        - name: gate
          image: <your-registry>/cr-gate:v1.2.3
          args: ["--mode=cluster", "--fail-on=policy"]
          env:
            - name: APP_NAME
              value: "{{.app.metadata.name}}"
            - name: APP_REVISION
              value: "{{.app.status.sync.revision}}"
            - name: DEST_NAMESPACE
              value: "{{.app.spec.destination.namespace}}"
            - name: CR_API
              valueFrom:
                secretKeyRef:
                  name: cr-platform
                  key: endpoint
```

> ★ **注意**：模板变量 `{{.app...}}` 是 **Argo CD 的 Go template**，
> 由 repo-server 在渲染时替换（与 Helm 的 `{{ }}` 是**两套不同的引擎**，见既有
> [`appset-helm-Rendering.md`](../appset-helm-Rendering.md)）。
> → **在 Helm chart 里写 hook 资源时必须转义**，否则两套引擎打架。

---

## 5. 两种门禁的取舍矩阵

| 需求 | GitHub 侧（CR Check） | 集群内（PreSync Hook） |
|---|---|---|
| PR 必须带合规 CR 号 | ✅ **唯一合适的位置** | ❌ 太晚了（已经 merge） |
| commit message 规范 | ✅ Ruleset 原生 | ❌ |
| 维护窗口内才允许部署 | ✅（CR 平台判定） | ✅（hook 里查窗口）→ **但两边都要有** |
| 渲染结果符合策略 | ⚠️ 需在 App 里复现渲染 | ✅ **天然正确**（用同一套渲染） |
| 目标集群资源够不够 | ❌ | ✅ |
| 部署前备份 | ❌ | ✅ |
| 阻止"绕过 Argo CD 直改集群" | ❌ | ✅（但这其实是 Gatekeeper 的活） |

> ★ **结论：两者是互补的，不是二选一。**
> - **GitHub 侧** 管"**流程与授权**"（谁改的、批没批、合不合规）；
> - **集群侧** 管"**这份变更能不能安全落地**"。
>
> ★ **但要警惕"规则双写"**：如果 CR 号校验同时在 GitHub 侧和集群侧实现，
> 就会出现两套实现不一致（既有 [`how-to-atomic-idempotency`](../how-to-atomic-idempotency.md) 与
> [`14`](../git-apps/14-rulesets-and-gitapp-gate.md) 讨论的"规则与代码分离"问题）。
> → **规则只写一份，判定逻辑只在一个地方实现**；集群侧门禁只做"GitHub 侧做不了的那部分"。

---

## 6. 坑清单

| # | 坑 | 后果 | 规避 |
|---|---|---|---|
| 1 | hook 不写删除策略 | Job 永久堆积；下次同步不重跑 | `BeforeHookCreation` |
| 2 | hook Job 的 SA 权限给太大 | 门禁变成提权通道 | 独立 SA、只读、必要时才写 |
| 3 | PreSync 失败后 Application 一直 failed | 需要人工重试 | 修好原因后重新同步；或让 driver 重试 |
| 4 | PostSync 失败被当成"部署失败" | GitHub 上显示红，但资源其实已更新 | 区分"更新成功"与"验证通过"两个信号 |
| 5 | 在 Helm chart 里写 hook 忘了转义 `{{ }}` | 渲染报错或被 Helm 提前求值 | 用字符串字面量转义（既有 [`appset-helm-Rendering.md`](../appset-helm-Rendering.md)） |
| 6 | wave 设成负数但资源没有 wave | 顺序不是预期的 | 明确给**每个**资源写 wave，或全部默认 0 |
| 7 | hook 里读 `{{.app.status.sync.revision}}` 拿不到值 | 拿到空 | 用 `.app.status.sync.revision`；必要时用 `.app.status.operationState.syncResult.revision` |
| 8 | 门禁逻辑在 GitHub 侧和集群侧各写一遍 | 规则不一致、绕过 | 规则单一来源 |
| 9 | hook 用了 `latest` 镜像 | 行为漂移、无法复现 | 固定 tag + digest |
| 10 | 应用被删时 hook 资源残留 | 集群里留垃圾 | 配 `HookFailed` / 由 Argo CD prune |

---

## 关联文档

- 上一级：[`18 总体框架`](./18-framework-github-first-gitops.md)
- 同步窗口（另一种"卡住"）：[`21 同步窗口与自动同步`](./21-sync-windows-and-auto-sync.md)
- 准入层（第三种"卡住"）：[`06 OPA 与 Gatekeeper`](../06-opa-gatekeeper-impact.md)
- 既有：[`app-of-apps.md`](../app-of-apps.md)（跨 Application 的 wave 与顺序）
- 既有：[`argocd-admin-guide.md `6 高级 GitOps 模式`](../../argocd-admin-guide.md)
