# 06 · OPA 与 Gatekeeper 对 Argo CD 的影响面

> 核心问题：**"我们上了 OPA" 到底意味着什么？Argo CD 会被影响吗？**
> 答案取决于 OPA 装在**哪个层次**。有三个完全不同的东西，常被混为一谈。

---

## 1. 先分清三层

```
┌─────────────────────────────────────────────────────────────────┐
│ 第 3 层：集群准入（Admission Webhook / Gatekeeper）             │
│ 位置：K8s API Server 前面                                        │
│ 时机：资源写入 API Server 的那一刻                                │
│ 作用：不合规资源根本进不了集群                                    │
│ 对 Argo CD 的影响：**间接但强烈** —— 同步"成功"≠ 资源"创建成功"     │
├─────────────────────────────────────────────────────────────────┤
│ 第 2 层：Argo CD 同步前策略检查（自建 hook / extension）           │
│ 位置：Argo CD 内部，sync 之前                                    │
│ 时机：点同步 / 自动同步触发后，apply 之前                          │
│ 作用：不合规就不发起同步                                          │
│ 对 Argo CD 的影响：**直接** —— 同步会被阻塞，Application 停在 pending│
├─────────────────────────────────────────────────────────────────┤
│ 第 1 层：Argo CD 自身授权（Casbin `policy.csv`）                  │
│ 位置：Argo CD API Server                                         │
│ 时机：任何 API 调用时                                             │
│ 作用：谁能不能做这个操作                                          │
│ 对 Argo CD 的影响：**直接** —— 403。**这跟 OPA 没关系**           │
└─────────────────────────────────────────────────────────────────┘
```

> **常见误解**：「Argo CD 里打开 OPA 开关就能拦住不合规资源」
> —— Argo CD **没有**这个开关。OPA 在这个架构里是三个独立的东西。

---

## 2. 第 1 层：Argo CD 自身授权（不是 OPA）

这是最常被误认为"OPA"的东西，实际上是 **Casbin RBAC**：

```yaml
# argocd-rbac-cm
data:
  policy.csv: |
    p, devops-admin, applications, *, *, allow
    g, devops-admin, role:admin
```

**失败表现**：API 返回 **403 Forbidden**。
**与 Gatekeeper 无关**，与 OPA 无关。详见 [`04-appproject-rbac.md`](./04-appproject-rbac.md)。

---

## 3. 第 2 层：Argo CD 同步前策略检查

### 3.1 实现方式

Argo CD 没有内置的 OPA 集成。要做"同步前检查"，两种路子：

**方式 A：PreSync Hook（推荐，最常用）**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
spec:
  source:
    repoURL: https://github.com/example/platform.git
    path: apps/myapp
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
  syncPolicy:
    syncOptions:
    - Validate=true
    - PruneLast=true
    - RespectIgnoreDifferences=true
  syncHooks:                       # ← 同步前执行
  - name: policy-check
    hookTypes:
    - PreSync
    env:
    - name: POLICY_DIR
      value: ./policy
    volumes:
    - name: policy
      configMap:
        name: myapp-opa-policy
    script: |
      #!/bin/sh
      set -e
      # 用 opa eval 校验渲染后的 manifest
      opa eval --fail \
        --input <(kubectl create --dry-run=client -f rendered.yaml -o json) \
        --data /policy/ \
        "data.gatekeeper.main.deny"
```

**方式 B：Argo CD Extension（外部策略引擎）**

在 `argocd-cm` 里配置：

```yaml
data:
  extensions: |
    - name: policy-check
      extension:
        url: https://policy-engine.example.com/validate
        headers:
        - name: Authorization
          value: "[REDACTED]"
        timeout: 10
```

**同步链路中的位置**（上游 `extensions` 语义）：

```
检测到差异 → 渲染 manifest → 调用 extension → extension 返回 allow/deny
  → allow: 继续 apply
  → deny:  同步失败，Application 状态显示错误
```

### 3.2 失败表现

| 情况 | 表现 |
|---|---|
| 策略判定不合规 | 同步被阻塞，Application 停在 `Operation Failed` / `Pending`，**集群里什么都没变** |
| extension 超时 | 同步失败（取决于 extension 的 `timeout` 配置） |
| extension 服务挂了 | 同步失败，且**每次重试都会失败** → Application 无限重试 |

### 3.3 关键局限

> **同步前检查只覆盖走 Argo CD 同步链路的变更。**

绕过路径：
- 人直接 `kubectl apply`
- 其他 CI/CD 工具直接 apply
- GitOps 之外的手工操作
- Argo CD 之外的其他 controller 写入

**所以第 2 层是"锦上添花"，不是安全边界。**

---

## 4. 第 3 层：集群准入（Gatekeeper）—— 影响最大的一层

### 4.1 工作位置

```
kubectl / Argo CD / 任何客户端
            │
            ▼
    ┌───────────────┐
    │  API Server   │
    └───────┬───────┘
            │  POST /api/v1/namespaces/x/deployments
            ▼
   ┌─────────────────┐
   │ Validating      │  ← Gatekeeper Webhook
   │ Webhook         │     校验约束模板
   └────────┬────────┘
            │ allow / deny
            ▼
      etcd（写入）
```

### 4.2 对 Argo CD 的影响：**这是关键**

**Argo CD 的"同步成功"不等于"资源创建成功"。**

Argo CD 的同步流程是：
1. 渲染 manifest
2. 向 API Server 提交
3. **提交成功 = 同步成功**

Gatekeeper 在第 2 步拦截时：
- API Server 返回 **403 / 拒绝原因**
- Argo CD 收到错误 → Application 变成 **OutOfSync** 或 **Degraded**
- Argo CD 会**不断重试**（如果是自动同步）

**结果**：Application 永远 OutOfSync，UI 上刷错误，但资源一个都没建。

### 4.3 三种典型失败模式

| 模式 | 场景 | 表现 | 处理 |
|---|---|---|---|
| **策略不匹配** | manifest 确实违反约束 | 同步报 webhook denied | 修 manifest（这是预期行为） |
| **Webhook 不可用** | Gatekeeper Pod 挂了 / 网络不通 | 所有资源写入被拒（`failurePolicy: Fail`） | 恢复 Gatekeeper；紧急可临时改 `failurePolicy: Ignore` |
| **超时** | Gatekeeper 响应慢 | API 请求超时 | 调大 `--disable-webhook-rules`... 实际上应调 Gatekeeper 的 `--operation-timeout` 和 webhook `timeoutSeconds` |

### 4.4 `failurePolicy` 的选择

| 值 | Webhook 挂掉时 | 适用 |
|---|---|---|
| `Fail` | **拒绝所有写入** | 严格合规环境。**但 Gatekeeper 挂了 = 整个集群写入中断** |
| `Ignore` | 放行所有写入 | 过渡期、观察期。风险：绕过策略 |

**推荐路径**：
1. 部署时用 `Ignore` 跑一段观察期（收集违规报告，不阻断）
2. 策略调优完成后切 `Fail`
3. **确保 Gatekeeper 有 ≥2 副本 + PDB + 合理的 `timeoutSeconds`**

> ⚠️ `Ignore` 期间的行为：Gatekeeper 仍会记录违规（`status` 里有 audit 信息），
> 但**不阻断**。可以用 `kubectl get constraints -o yaml` 看违规统计。

### 4.5 Gatekeeper 与 AppProject 的关系

**两者是互补的，不是替代关系。**

| | AppProject | Gatekeeper |
|---|---|---|
| 管什么资源 | Argo CD **同步的**资源 | 集群里**所有**资源写入 |
| 覆盖绕过路径 | ❌ 不能 | ✅ 能 |
| 判定依据 | 源/目标/资源类型 | 任意 Rego 逻辑（可查标签、配额、镜像来源等） |
| 生效范围 | 仅 Argo CD | 全集群 |

**组合起来才完整**：
- AppProject 挡住"越界同步"（哪来的仓库、到哪去）
- Gatekeeper 挡住"违规资源"（不管谁写的）

**已有的 OPA 资料库**（本仓库，不要重复造轮子）：

| 文档 | 内容 |
|---|---|
| [`../../gke/opa-gatekeeper/README.md`](../../gke/opa-gatekeeper/README.md) | 目录总览与快速场景索引 |
| [`../../gke/opa-gatekeeper/policy-controller-vs-open-source-comparison.md`](../../gke/opa-gatekeeper/policy-controller-vs-open-source-comparison.md) | GKE Policy Controller vs 开源 Gatekeeper 选型 |
| [`../../gke/opa-gatekeeper/gke-policy-controller-with-gatekeeper.md`](../../gke/opa-gatekeeper/gke-policy-controller-with-gatekeeper.md) | GKE 上用 Policy Controller 的方案 |
| [`../../gke/opa-gatekeeper/gatekeeper-concepts.md`](../../gke/opa-gatekeeper/gatekeeper-concepts.md) | 概念说明 |
| [`../../gke/opa-gatekeeper/single-cluster-opa-gatekeeper-setup.md`](../../gke/opa-gatekeeper/single-cluster-opa-gatekeeper-setup.md) | 单集群安装步骤 |
| [`../../gke/opa-gatekeeper/verify-gatekeeper.sh`](../../gke/opa-gatekeeper/verify-gatekeeper.sh) | **可执行验证脚本** |
| [`../../gke/opa-gatekeeper/gatekeeper-release-3.14.yaml`](../../gke/opa-gatekeeper/gatekeeper-release-3.14.yaml) | Release 3.14 完整清单 |
| [`../../gke/opa-gatekeeper/dynamic-context-aware-policy.md`](../../gke/opa-gatekeeper/dynamic-context-aware-policy.md) | 动态上下文感知策略 |
| [`../../gke/opa-gatekeeper/multi-tenant-resource-quota-exception-handling.md`](../../gke/opa-gatekeeper/multi-tenant-resource-quota-exception-handling.md) | 多租户配额异常处理 |

**本文档不重复 Gatekeeper 的安装和 Constraint 模板细节**，只讲它对 Argo CD 的影响。

---

## 5. `resource.customizations` —— 让 Argo CD 理解被 Gatekeeper 拒绝的资源

Gatekeeper 拒绝资源时，Argo CD 只会显示原始的 webhook 错误。
**自定义 health check 可以把错误翻译成人类可读的信息**：

```yaml
# argocd-cm
data:
  resource.customizations.health.deployments.apps: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.conditions ~= nil then
        for i, c in ipairs(obj.status.conditions) do
          if c.type == "Rejected" and c.reason == "FailedDeny" then
            msg = c.message
            hs.status = "Suspended"
            hs.message = "Gatekeeper 拒绝: " .. msg
          end
        end
      end
    end
    hs = hs
```

**效果**：UI 上直接显示"Gatekeeper 拒绝：xxx"，而不是一坨 webhook JSON。

### 5.1 其他有用的 customization

```yaml
data:
  # 忽略某些字段，避免无意义的 diff
  resource.customizations.ignoreDifferences.all: |
    jqPathExpressions:
      - '.metadata.managedFields[]'
      - '.spec.template.metadata.annotations."kubectl.kubernetes.io/restartedAt"'

  # 自定义资源健康检查（CRD 场景必做）
  resource.customizations.health.<group>.<version>.<kind>: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.phase == "Ready" then
        hs.status = "Healthy"
        hs.message = "Ready"
      else
        hs.status = "Progressing"
        hs.message = obj.status.phase
      end
    end
    hs = hs
```

> **CRD 场景提醒**：Argo CD 默认不知道你的 CRD 的健康状态。
> 不配 `resource.customizations.health.*` 的话，所有 CR 会显示
> `Progressing` 或 `Healthy`（取决于是否有 `status`），
> **`selfHeal` 会对健康状态反复触发**。这是 CRD 场景的常见坑。

---

## 6. 三层怎么配合（完整链路）

```
① 用户点同步 / 自动同步触发
        │
        ▼
② Argo CD 渲染 manifest（Kustomize / Helm）
        │
        ▼
③ Extension 检查（可选，同步前策略）  ──deny──▶ 同步失败，Application Pending
        │ allow
        ▼
④ 提交到目标集群 API Server
        │
        ▼
⑤ Gatekeeper Webhook 校验  ──deny──▶ API 403，Application OutOfSync，集群无变化
        │ allow
        ▼
⑥ 资源写入 etcd
        │
        ▼
⑦ Argo CD 下次 reconcile 读取实际状态，算 diff
        │
        ▼
⑧ 健康检查（可用 resource.customizations.health.*）→ Healthy / Progressing / Suspended
```

**注意第 ④→⑤ 步**：Argo CD 提交的请求和任何人 `kubectl apply` 提交的请求
**走的是同一条路径**。这就是 Gatekeeper 能覆盖所有路径的原因。

---

## 7. 验证

```bash
# ① Gatekeeper 是否在跑
kubectl get pods -n gatekeeper-system
kubectl get validatingwebhookconfiguration | grep -i gatekeeper

# ② webhook 的 failurePolicy（Fail 还是 Ignore）
kubectl get validatingwebhookconfiguration gatekeeper-validating-webhook-configuration \
  -o jsonpath='{.webhooks[*].failurePolicy}{"\n"}'

# ③ 用仓库自带的验证脚本（推荐）
./gke/opa-gatekeeper/verify-gatekeeper.sh

# ④ 故意提交一个违规资源，看是否被拒
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: no-required-label
  namespace: default
spec:
  containers:
  - name: c
    image: nginx
EOF
# 期望：被拒绝，报 constraint 违规

# ⑤ 在 Argo CD 里看失败信息是否可读
kubectl -n argocd get application <app> -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}{"\n"}'
kubectl -n argocd get application <app> -o jsonpath='{.status.resources[0].health.message}{"\n"}'

# ⑥ 检查 Argo CD 的 operation 状态（区分是策略拒绝还是同步失败）
kubectl -n argocd get application <app> -o jsonpath='{.status.operationState.phase}{"\n"}'
kubectl -n argocd get application <app> -o jsonpath='{.status.operationState.message}{"\n"}'
```

---

## 8. 排障

| 现象 | 层 | 根因 | 处理 |
|---|---|---|---|
| Argo CD 同步报 403 `admission webhook ... denied the request` | 第 3 层 | Gatekeeper 拒绝 | 读拒绝原因（通常在 `status.conditions[].message`），修 manifest |
| 集群所有写入都失败 | 第 3 层 | Webhook 挂了且 `failurePolicy: Fail` | 恢复 Gatekeeper；紧急 `kubectl patch` 改 `Ignore` |
| Application 一直 OutOfSync 但集群里啥也没有 | 第 3 层 | 同上 | 同上 |
| 同步卡在 Pending，提示 extension 错误 | 第 2 层 | 策略引擎拒绝 | 看 extension 日志；确认 `timeout` 设置 |
| Application 一直 OutOfSync，**集群里资源是新的** | — | Argo CD 算出了 diff（常见于 `ignoreDifferences` 没配） | 用 `argocd app diff` 看具体 diff |
| CR 一直显示 `Progressing`，`selfHeal` 反复触发 | — | 没配 CR 的 health check | 配 `resource.customizations.health.<g>.<v>.<k>` |
| Argo CD API 返回 403 | 第 1 层 | Casbin RBAC，不是 OPA | 查 `argocd-rbac-cm`；见 [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| Gatekeeper 拒绝 Argo CD 自己创建的资源 | 第 3 层 | 约束太严（比如要求所有资源带特定 label） | 用 `excludedNamespaces` 排除 `argocd` 命名空间 |
| 策略违规但资源已存在 | 第 3 层 | 存量资源未重新校验 | Gatekeeper 有 audit 模式，先跑审计再收紧 |

---

## 9. 落地建议

1. **先上 Gatekeeper，用 `failurePolicy: Ignore` 跑观察期**（收集违规，不阻断）
2. **同时给 Argo CD 装 CR 健康检查**（`resource.customizations.health.*`）——
   这和 OPA 无关，但 CR 场景必做，否则 `selfHeal` 空转
3. **给 Argo CD 自身 namespace 加豁免**（`excludedNamespaces: [argocd]`），
   否则 Argo CD 自己的资源可能触发约束
4. **同步前检查（第 2 层）作为补充**，不作为安全边界
5. **AppProject（第 2 层的资源约束）+ Gatekeeper（第 3 层）组合使用**
6. 收紧 `failurePolicy` 前，**确保 Gatekeeper ≥2 副本 + PDB**

---

## 10. 关联文档

| 主题 | 文档 |
|---|---|
| Gatekeeper 完整资料 | [`../../gke/opa-gatekeeper/`](../../gke/opa-gatekeeper/) |
| 三层权限边界 | [`04-appproject-rbac.md`](./04-appproject-rbac.md) |
| `resource.customizations` 其他用法 | [`../argocd-admin-guide.md`](../argocd-admin-guide.md) |
| 排障总表 | [`09-troubleshooting.md`](./09-troubleshooting.md) |
