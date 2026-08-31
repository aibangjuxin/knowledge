# GCP Architecture Decision Records (ADR)

> 本目录存放 GCP / GKE 架构决策记录。每篇 ADR 一事一议，遵循 Michael Nygard 的 ADR 模板（Context / Decision / Consequences / Alternatives）。
>
> 命名规范：`NNN-<kebab-case-title>.md`，编号三位，从 `001` 起。

---

## ADR 是什么?(给不熟悉术语的同事)

> **ADR = Architecture Decision Record(架构决策记录)**

### 一句话

> ADR 是一种**轻量级文档模式**,记录"我们做了什么决定 + 为什么 + 拒绝什么方案 + 后果",目的是**防止未来重复讨论已决定的事**。

### 解决什么问题?

| 没有 ADR | 有 ADR |
|---|---|
| 工程师 A 做了"为什么用 X 而不是 Y"的决定 | 决定 + 理由 + 拒绝项全写在 ADR-009.md |
| 6 个月后工程师 B 接手 | 工程师 B 看一眼 ADR 知道原因 |
| 翻聊天记录 / git log 找不到,重新讨论 2 周 | **不用重新讨论**,直接基于现有决定继续推进 |

### ADR 通常包含什么?

| 章节 | 内容 |
|---|---|
| **状态** | Proposed / Accepted / Superseded / Deprecated |
| **日期 + 作者 + Reviewers** | 谁拍板,谁评审 |
| **背景** | 当时面对什么问题 |
| **决策** | 最后选了什么 |
| **理由** | 为什么选这个 |
| **替代方案** | 考虑过但放弃的(对比表) — **最值钱的部分** |
| **后果** | 好的 + 坏的影响(blessing + curse) |
| **引用** | 关联 ADR / 文档 / 一手来源 |

### ADR vs 普通设计文档

| 维度 | 普通设计文档 | ADR |
|---|---|---|
| **目的** | 描述系统怎么设计 | 记录"为什么这么设计" |
| **重点** | 怎么做 | 为什么 + 拒绝什么 + 后果 |
| **生命周期** | 写一次,可能过时 | 永久保留,有新决策就开 ADR-N+1 |
| **编号** | 任意 | 顺序编号,不可重命名 |
| **状态** | 不变 | Proposed → Accepted → Superseded |
| **读者** | 新人 onboarding | 新人 + **未来自己** |

### ADR 的关键规则

1. **编号顺序,不重命名** — ADR-009 永远是 ADR-009,即使决定错了也是新建 ADR-010 supersedes ADR-009
2. **决策一旦写就锁定** — 不在原 ADR 里改,改了就开新 ADR(避免历史失真)
3. **拒绝的方案也要写** — "我们排除了 A/B/C 因为 X/Y/Z",这是 ADR 最值钱的部分
4. **一事一议** — 不是每个小决定都写 ADR,只看跨时间 + 跨人员影响力的"重要的"

### 业务方视角的实操

| 你在做 | 该做什么 |
|---|---|
| Review 同事的 ADR | 看 "决策 + 理由 + 拒绝项",判断是否同意 |
| 跟 Manager 沟通决策 | 引用 ADR 编号 + 章节,不重新解释 |
| 业务有变化需重新评估 | **开新 ADR**(010+),不修改旧 ADR |
| 新人 onboarding | 先读 README(本文档),再看相关 ADR |

### 一句话答复(可复制)

> ADR = Architecture Decision Record,记录"我们做了什么决定 + 为什么 + 拒绝什么 + 后果",目的是防止未来重复讨论已决定的事。ADR-N 一旦写就锁定,变化开 ADR-N+1 supersedes 旧 ADR。

### 延伸阅读

- [Michael Nygard 原始 ADR 文章](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
- [GCP ADR 体系使用实践](https://cloud.google.com/architecture/devops/devops-tech-continuous-delivery)
- [Kubernetes ADR 实践](https://github.com/kubernetes/kubernetes/tree/master/architecture-decisions)

---

## 当前 ADR 索引

| 编号 | 标题 | 状态 | 日期 |
|------|------|------|------|
| [008](./008-static-pod-no-secret-configmap-k8s-137.md) | 应对 Kubernetes v1.37 Static Pod 禁止引用 Secret/ConfigMap 的架构变更 | Proposed | 2026-08-25 |
| 009 | GKE Pod 挂载公司 NAS 安全 + 架构影响评估 | Proposed | 2026-08-28 |

> **ADR-009 主体不在本目录** — 它在 `gcp/storage/nas/ADR-009-gke-pod-mount-internal-nas-security-review.md`,配套 8 个衍生文档(架构图 / 决策树 / 概念澄清 / eli5 / 部署参考集等)。ADR-009 跨多个目录,因为涉及 storage / network / security / 多租户多个领域。

---

## 🚨 ADR-008 综合入口 · K8s v1.37 Static Pod Compliance

> **TL;DR**：v1.37（**2026-08-26 周三 GA**）起，static pod 不能引用 Secret/ConfigMap，绕过开关已彻底移除。如果集群里有手写的控制面 manifest 用了 `configMapRef` / `secretRef` 等字段，升级就是事故。
>
> 详情见 [ADR-008 正文](./008-static-pod-no-secret-configmap-k8s-137.md)。

### 这次任务所有改动的文件 / 文档（收工汇总）

| # | 路径 | 类型 | 大小 | 改动说明 |
|---|---|---|---|---|
| 1 | [`gcp/adr/008-static-pod-no-secret-configmap-k8s-137.md`](./008-static-pod-no-secret-configmap-k8s-137.md) | **ADR 正文** | 19.8 KB / 353 行 | 新建 · 9 章节 · 双语分栏 · 一手来源已列 |
| 2 | [`gcp/adr/008-static-pod-compliance-architecture.html`](./008-static-pod-compliance-architecture.html) | **架构图**（深色 SVG） | 26.3 KB / 422 行 | 新建 · 问题域 / 解决域两栏 · ID 可追溯 |
| 3 | [`gcp/adr/README.md`](./README.md) | 目录索引 + 综合入口 | — | **本文档** · 从纯索引升级为 ADR-008 入口 |
| 4 | [`gcp/gke/script/audit-static-pod-refs.sh`](../../gke/script/audit-static-pod-refs.sh) | **审计脚本** | 19.9 KB / 563 行 · `0755` | 新建 · 6 类违规字段检测 · `--self-test` 内置 |
| 5 | [`gcp/gke/docs/gke-upgrade.md`](../../gke/docs/gke-upgrade.md) | **升级 runbook** | 17.2 KB / 374 行（+121） | 修改 · 加 `Pre-Upgrade: Static Pod Audit` + `Post-Upgrade Verification` |
| 6 | `~/.hermes/profiles/architect-gcp/MEMORY.md` | 持久化记忆 | +1 条目 | 已更新 · 跨会话可用 |

### 文档之间的交叉引用（已闭环）

```
┌─────────────────────────────────────────────────────────────────┐
│  README.md（本入口）                                            │
│   └── ADR-008 正文 (.md)                                        │
│        ├── 引用 #140226 (GitHub) + sneak peek blog + Secrets doc│
│        ├── 引用 gke-upgrade.md §Pre-Upgrade                    │
│        └── 引用 audit-static-pod-refs.sh                       │
│                                                                  │
│  gke-upgrade.md (runbook)                                        │
│   ├── 引用 ADR-008 §5.4 / §6 / §4                               │
│   └── 引用 audit-static-pod-refs.sh (line 170)                  │
│                                                                  │
│  audit-static-pod-refs.sh (脚本)                                │
│   └── 头部注释引用 ADR-008 §6 step 2 + #140226                  │
│                                                                  │
│  架构图 (.html)                                                  │
│   └── 标注 ADR-008 + 三个交付物的路径                           │
└─────────────────────────────────────────────────────────────────┘
```

### 一行体检命令（任何控制面节点执行）

```bash
# 自管 kubeadm / GKE on bare-metal / attached cluster 用户必跑
bash ~/git/knowledge/gcp/gke/script/audit-static-pod-refs.sh

# 或一行命令等效（脚本可用之前/不想用脚本时）
grep -rE "configMapRef|secretRef" /etc/kubernetes/manifests/
```

### 适用矩阵（按集群类型分流）

| 集群类型 | 是否需要审计 | 动作 |
|---|---|---|
| **GKE Standard / Autopilot**（Lex 当前所在） | ❌ 跳过 manifest 审计 | 改用 `kubectl -n kube-system get pod -l tier=control-plane -o yaml \| grep -E 'configMapRef\|secretRef'`，预期空 |
| **GKE on bare-metal / GKE attached** | ✅ 必须 | 跑 `audit-static-pod-refs.sh`，修 [HIT] 再升 |
| **自建 kubeadm / Kubespray / Cluster API** | ✅ 必须 | 同上 |

### 升级时间窗（按当前 GKE 版本）

| 你现在跑 | 距离 1.37 自动到你头上的窗口 | 建议 |
|---|---|---|
| 1.33.x（已 maintenance） | 90 天内强制 | 优先升 1.34 / 1.35 |
| 1.34.x | 6-12 个月 | Rapid channel 先开 dev cluster 试 1.37 |
| 1.35.x | 3-6 个月 | 现在就能在 dev 集群试 |
| 1.36.x | 1-3 个月 | 重点关注 static pod manifest 合规 |
| 1.37 alpha（Rapid） | 你已经在 | 跑 §5.4 smoke test |

> **GKE 跳版限制**：1.34 不能直跳 1.36，必须经 1.35 中转。

### 这次没做（明确越界，留给下次）

- **CI gate（GitHub Actions pre-merge check）**：ADR §6 step 4 — 未实现，需要 devops-gcp 后续处理
- **imagePullSecrets 是否被拦截的具体测试**：ADR §3 模糊地带 — 需要 qa-gcp 在 dev cluster 跑实测
- **GKE on bare-metal / attached 在 1.37 上的 release window**：等 GKE 未来数周更新官方文档

### 一手来源（核查链）

| 来源 | 用途 |
|---|---|
| [Kubernetes v1.37 Sneak Peek blog](https://kubernetes.io/blog/2026/07/31/kubernetes-v1-37-sneak-peek/) | 变更最权威公告 |
| [kubernetes/kubernetes#140226](https://github.com/kubernetes/kubernetes/issues/140226) | feature gate 移除的 PR |
| [kubernetes/kubernetes#131837](https://github.com/kubernetes/kubernetes/pull/131837) | v1.34 引入 gate 的原始 PR（历史背景） |
| [Kubernetes Feature Gates 官方文档](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/) | feature gate 当前状态 |
| [Secrets 官方文档 — "Using Secrets with static pods"](https://kubernetes.io/docs/concepts/configuration/secret/) | "You cannot use ConfigMaps or Secrets with static pods" 原文 |
| [kubeadm implementation details](https://kubernetes.io/docs/reference/setup-tools/kubeadm/implementation-details/) | static pod manifest 在 kubeadm 里的标准写法 |
| [kubernetes.dev release info](https://www.kubernetes.dev/resources/release) | v1.37 GA 日期 2026-08-26 |
| [GKE release notes 2026-08-21](https://docs.cloud.google.com/kubernetes-engine/docs/release-notes) | GKE 1.37 alpha Rapid channel 上线时间 |
| [GKE 升级文档](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/upgrading-a-cluster) | GKE 跳版限制 |

---

## 阅读路径建议

- **新成员入门**：先读本 README 的 ADR-008 入口，按表格顺序点开正文 + 架构图
- **遇到升级问题**：直接跳 [runbook §Pre-Upgrade](../../gke/docs/gke-upgrade.md) 跑审计脚本
- **写自己的 ADR**：仿照 [008](./008-static-pod-no-secret-configmap-k8s-137.md) 的章节结构

## ADR-008 变更日志

| 日期 | 版本 | 改动 |
|---|---|---|
| 2026-08-25 | v1.0 | 初稿，基于 v1.37 sneak peek + GKE release notes |
| 2026-08-25 | v1.1 | 关联资产落盘后：审计脚本 + runbook 更新 + 架构图，README 升级为综合入口 |
