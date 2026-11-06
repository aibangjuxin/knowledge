# Argo CD 专题文档

Kubernetes 原生 GitOps 落地指南 —— 从架构选型到生产运维的完整参考。

> **设计前提**
> - 全部方案基于 **Kubernetes 原生 CRD + Operator + GitOps**，**不使用 Crossplane**
> - 权威事实来源是本仓库的 `install.yaml`（Argo CD 官方清单）与上游源码/文档
> - 每个结论标注了来源性质：**官方保证** / **当前清单事实** / **推荐实现** / **部署前验证项**

---

## 阅读顺序

### 第一次看这套文档

```
00 → 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10
```

### 只想解决一个具体问题

| 你的问题 | 看哪篇 |
|---|---|
| 为什么不用 Crossplane？整体架构长什么样？ | [00](./00-architecture-no-crossplane.md) |
| Redis 到底要不要持久化？业务 Redis 怎么改？ | [01](./01-redis-persistence.md) |
| 高可用怎么配？副本数、Redis HA、坑在哪？ | [02](./02-ha.md) |
| Dex 接 LDAP、组怎么进 Token、怎么禁用 admin？ | [03](./03-dex-ldap-sso.md) |
| AppProject 边界、RBAC 角色、K8s ServiceAccount？ | [04](./04-appproject-rbac.md) |
| ApplicationSet 批量分发怎么写？各 generator 边界？ | [05](./05-appset.md) |
| ApplicationSet 和 Application 到底什么关系？ | [对比速查：ApplicationSet vs Application](../argocd-applicationset-vs-application.md) |
| 用了 OPA/Gatekeeper 会影响 Argo CD 吗？ | [06](./06-opa-gatekeeper-impact.md) |
| GitHub App 凭据怎么配？**想改分支改哪里？** | [07](./07-repository-githubapp.md) |
| 从零到生产的实施顺序和回滚步骤？ | [08](./08-implementation-playbook.md) |
| 出问题了怎么查？ | [09](./09-troubleshooting.md) |
| 要不要引入 Argo Workflows？结论是什么？ | [10](./10-argo-workflows-evaluation.md) |

---

## 文档清单

### [00 · 架构选型：不使用 Crossplane](./00-architecture-no-crossplane.md)

Kubernetes 原生 GitOps 的能力边界、为什么拒绝 Crossplane、
CRD/Operator 的落地方式、方案对比表、被否决方案记录。

**适合**：架构评审、方案选型答疑。

---

### [01 · Redis 与持久化](./01-redis-persistence.md)

**核心澄清**：三种 Redis 是三件不同的事。

| 类型 | 是什么 | 要持久化吗 |
|---|---|---|
| `argocd-redis` | Argo CD 内部缓存 | **不要** —— 官方设计如此 |
| Argo CD HA Redis | 3 master + 3 sentinel + HAProxy | **不要** —— 同上 |
| 业务 Redis | 你的应用通过 YAML 部署在 GKE 上的 | **要** —— 除非确认是纯缓存 |

含：`install.yaml` 事实核对、GKE StorageClass 选择、
StatefulSet + `volumeClaimTemplates` 改造、Memorystore 方案对比。

---

### [02 · 高可用部署](./02-ha.md)

副本数配置、三个必须记住的约束：

1. `ARGOCD_API_SERVER_REPLICAS` 必须 == `argocd-server` 的 `replicas`
2. `dex-server` **必须 1 副本**（内存数据库）
3. 官方 Redis HA 的 sentinel **不支持扩缩容**

含：滚动更新、gRPC 消息上限、登录限流误拒的排障。

---

### [03 · Dex / LDAP / SSO](./03-dex-ldap-sso.md)

三个**相互独立**的动作，缺一不可：

```
① 禁用内置 admin 账号
② LDAP 组进入 OIDC Token
③ 组映射为 Argo CD 角色
```

含：`dex.config` 完整配置、`insecureEnableGroups` + `scopes` 双开关、
`bindPW` 的 `$` 转义陷阱、组名大小写敏感、离职人员权限回收、
**锁死后的 break-glass 恢复路径**。

---

### [04 · AppProject 与 RBAC](./04-appproject-rbac.md)

三层权限模型：

```
Argo CD RBAC（谁能操作 Application）
   × AppProject（能操作哪些资源）
   × K8s RBAC / ServiceAccount（Argo CD 实际写集群的权限）
```

含：内置角色表、`policy.csv` 语法、`proj:<project>:<role>` 格式、
`policy.default` 无法被 deny 收回的陷阱、
项目名 `-` 触发继承的坑、ServiceAccount 最小权限清单。

---

### [05 · ApplicationSet 批量分发](./05-appset.md)

替代「每个环境手工建 Application」。

| Generator | 输入 | 输出 |
|---|---|---|
| `git` | 仓库目录 | `.path.path` / `.path.basename` |
| `clusters` | 已注册集群 | `.name` / `.server` |
| `list` | 静态元素 | 任意键值 |
| `matrix` | 多个生成器 | 笛卡尔积 |
| `merge` | 多个生成器 | 按 `mergeKeys` 合并 |

含：`goTemplate` + `missingkey=error` 的必要性、
**`template.spec.project` 必须显式写**（否则落到 `default` 最宽松项目）、
Merge 生成器的数组结构陷阱、批量改分支的正确入口。

---

### [06 · OPA 与 Gatekeeper 对 Argo CD 的影响面](./06-opa-gatekeeper-impact.md)

三个层次要分清，混为一谈会导致方案选错：

| 层次 | 触发时机 | 失败后果 |
|---|---|---|
| Argo CD 同步前 OPA 检查 | sync 之前 | 拒绝同步，Application 停在 OutOfSync |
| 外部策略引擎 | 独立触发 | 与 Argo CD 无直接关系 |
| Admission Webhook / Gatekeeper | K8s API 写入时 | 拒绝资源写入，同步报 403 |

含：CR 的 health check 配置（否则 `selfHeal` 空转）、
`excludedNamespaces` 排除 `argocd` 自身、
`failurePolicy` 从 `Ignore` 切 `Fail` 的观察期流程。

---

### [07 · Repository 凭据与 GitHub App](./07-repository-githubapp.md)

**直接回答**：「创建了 GitHub App 类型的 Repository 后，为什么没法编辑 Branch？」

**因为分支不是 Repository 的属性。** 它属于 `Application.spec.source.targetRevision`。

含：Repository 对象完整字段表（来自上游 `util/db/repository_secrets.go`）、
GitHub App 三要素（App ID / Installation ID / Private Key）、
声明式管理 Repository Secret、凭据轮换流程、
GitHub App 私钥的正确注入方式。

---

### [08 · 实施顺序与验收手册](./08-implementation-playbook.md)

9 个阶段，每阶段有：前置条件 → 命令 → 验收标准 → 回滚方式。

**两个硬性依赖**：
- 阶段 3（组映射）验证通过 → 才能做阶段 4（禁用 admin），否则会锁死
- 阶段 5（AppProject 边界）→ 才能做阶段 6（批量分发）

---

### [09 · 排障手册](./09-troubleshooting.md)

按**现象**索引，10 个类别：身份 / 同步 / ApplicationSet / 凭据 /
OPA / Diff / 权限 / Redis / HA。

附一键体检脚本 `argocd-health.sh`（见文末 §10）。

---

### [10 · Argo Workflows 概念梳理与引入评估](./10-argo-workflows-evaluation.md)

**核心结论**：**不引入** Argo Workflows 作为我们 API 交付链路的发布执行器。

含：Argo Workflows 的对象模型与 9 种模板类型、执行模型（每 step 一个 Pod）、
组件拓扑、与 Argo CD 的正交关系（声明式收敛 vs 命令式执行）、
特性清单、局限性（controller 不能水平扩展 / v4 引入 DB / CRD 需 server-side apply / 双控制环风险）、
「受治理发布执行器」12 项能力映射表、A/B/C 三个方案、
复评触发条件清单、部署前验证项。

---

## 可复制示例

全部位于 [`examples/`](./examples/)，可直接 `kubectl apply`。

| 文件 | 用途 | 关键注意事项 |
|---|---|---|
| [`dex-ldap-config.yaml`](./examples/dex-ldap-config.yaml) | Dex + LDAP 完整配置 | `insecureEnableGroups: true` + `scopes` 必须同时有 |
| [`argocd-rbac-cm.yaml`](./examples/argocd-rbac-cm.yaml) | 组 → 角色映射 | `scopes` 必须含 `groups`；`policy.default` 不能被 deny 收回 |
| [`appproject-multi-env.yaml`](./examples/appproject-multi-env.yaml) | 多环境项目边界 | 收紧 `default` 是破坏性操作 |
| [`applicationset-matrix.yaml`](./examples/applicationset-matrix.yaml) | 批量分发（Matrix/List/Merge） | `template.spec.project` 必须显式写 |
| [`argocd-repositories-githubapp.yaml`](./examples/argocd-repositories-githubapp.yaml) | Repository Secret | 目标分支**不在这里** |
| [`redis-statefulset-pvc.yaml`](./examples/redis-statefulset-pvc.yaml) | 业务 Redis 持久化改造 | 这是**业务** Redis，不是 Argo CD 内部 Redis |
| [`ha-values-override.yaml`](./examples/ha-values-override.yaml) | HA 升级 values | `ARGOCD_API_SERVER_REPLICAS` 必须与副本数一致 |
| [`argocd-health.sh`](./examples/argocd-health.sh) | 一键体检脚本（只读） | 退出码 0=正常，1=有异常，2=环境不可用 |
| [`session-token-usage.md`](./session-token-usage.md) | 本次会话的 Token 用量报告 | 300 次 API 调用 / 约 16.4M token，含优化诊断 |

> ⚠️ **所有示例中的凭据均为 `[REDACTED]`**。
> 实际部署请用 Sealed Secrets / SOPS / External Secrets。

---

## 关键事实速查

### Argo CD 内部 Redis（`install.yaml:32441-32522`）

```yaml
# 实测事实：
#   volumes:      无
#   volumeMounts: 无
#   args:         --save "" --appendonly no
```

**准确表述**：未挂载持久卷，且**未配置 `emptyDir`**。
不是「用的是 emptyDir」——这两者不同，且结论**不能**推广到 HA Redis 或业务 Redis。

### 目标分支归属

```
Repository Secret  →  仓库地址 + 访问凭据 + 归属项目
Application        →  spec.source.targetRevision  ← 分支在这里
ApplicationSet     →  template.spec.source.targetRevision  ← 批量改这里
```

### 三个必须记住的 HA 约束

1. `ARGOCD_API_SERVER_REPLICAS` == `argocd-server.replicas`
2. `dex-server` 保持 1 副本
3. Redis sentinel 固定 3 副本

---

## 关联资源

| 资源 | 位置 | 说明 |
|---|---|---|
| Gatekeeper 完整部署资料 | [`../../gke/opa-gatekeeper/`](../../gke/opa-gatekeeper/) | **优先复用**，不要另建一套 |
| Argo CD 官方清单 | [`../install.yaml`](../install.yaml) | Redis 事实来源 |
| 上游调研缓存 | `~/.hermes/profiles/architecture/cache/scratch/upstream/argocd-research/` | 上游 RBAC / ConfigMap / Repository 源码提取结果（**本地缓存，不在仓库内**） |
| Argo CD 管理员指南 | [`../argocd-admin-guide.md`](../argocd-admin-guide.md) | 已有总览文档 |
| Application 字段详解 | [`../argocd-application-guide.md`](../argocd-application-guide.md) | |
| CLI 指南 | [`../argocd-cli-guide.md`](../argocd-cli-guide.md) | |

---

## 使用约定

文档中的内容按以下四类标注，实施前请按需验证：

| 标注 | 含义 | 验证方式 |
|---|---|---|
| **官方保证** | 上游文档或源码明确写明 | 已核对上游 `master` 分支 |
| **当前清单事实** | 从本仓库 `install.yaml` 实测提取 | 可用 `grep`/`kubectl` 复核 |
| **推荐实现** | 本文档给出的方案建议 | 按示例 apply 后验证 |
| **部署前验证项** | 因环境差异需自行核对 | 见文档内标注的官方链接 |
