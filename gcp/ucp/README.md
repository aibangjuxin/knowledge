# UCP · 统一控制平面（Argo CD × Crossplane）

> ## ⚠️ 方案状态变更：Crossplane 已停用
>
> **Crossplane 被严格禁止使用**，本目录的 Argo CD 相关专题已全部改为
> **Kubernetes 原生 GitOps**（CRD + Operator + 资源清单），不依赖 Crossplane。
>
> 本 README 中**仍带 Crossplane 的历史文档**（`poc.md`、`poc-minimax.md`、
> `poc-argocd-integration.md`、`next-steps-roadmap.md` 等）仅作为
> **已废弃方案的背景记录**保留，不代表当前方向。
>
> 👉 **当前有效方案见 [`argocd-topics/`](./argocd-topics/README.md)**（10 篇专题 + 7 个可复制示例）。

本目录是 UCP（Unified Cloud Platform）的方案与知识沉淀，主题是
**Argo CD（GitOps 交付）** 的生产化落地（跨云编排部分原设计基于 Crossplane，现已停用）。

## 怎么读

### 👉 当前有效方案（无 Crossplane）

| 你想做的事 | 看这篇 |
|---|---|
| **从零开始落地这套方案** | [`argocd-topics/README.md`](./argocd-topics/README.md) |
| 架构选型 / 为什么不用 Crossplane | [`argocd-topics/00-architecture-no-crossplane.md`](./argocd-topics/00-architecture-no-crossplane.md) |
| Redis 持久化、高可用部署 | [`argocd-topics/01-redis-persistence.md`](./argocd-topics/01-redis-persistence.md) · [`02-ha.md`](./argocd-topics/02-ha.md) |
| Dex/LDAP、权限模型、AppProject | [`argocd-topics/03-dex-ldap-sso.md`](./argocd-topics/03-dex-ldap-sso.md) · [`04-appproject-rbac.md`](./argocd-topics/04-appproject-rbac.md) |
| ApplicationSet 批量分发、Gatekeeper | [`argocd-topics/05-appset.md`](./argocd-topics/05-appset.md) · [`06-opa-gatekeeper-impact.md`](./argocd-topics/06-opa-gatekeeper-impact.md) |
| 仓库凭据、实施顺序、排障 | [`argocd-topics/07-repository-githubapp.md`](./argocd-topics/07-repository-githubapp.md) · [`08`](./argocd-topics/08-implementation-playbook.md) · [`09`](./argocd-topics/09-troubleshooting.md) |

### 历史文档（含 Crossplane，仅作背景参考）

| 你想做的事 | 先看这篇 | 再看这篇 |
|---|---|---|
| 理解原始需求与推进节奏 | [`poc-minimax.md`](./poc-minimax.md) | [`requirement.md`](./requirement.md) |
| 搞懂 Argo CD 怎么用起来 | [`poc-argocd-integration.md`](./poc-argocd-integration.md) | [`poc-argocd-git-to-apply-trigger.md`](./poc-argocd-git-to-apply-trigger.md) |
| 查 Argo CD 的管理、运维、排障 | [`argocd-admin-guide.md`](./argocd-admin-guide.md) | — |
| **搞懂并创建一个 `Application`** | [`argocd-application-guide.md`](./argocd-application-guide.md) | [`examples/argocd-application/`](./examples/argocd-application/README.md) |
| 查 CLI / REST API | [`argocd-cli-guide.md`](./argocd-cli-guide.md) | [`argocd-api.md`](./argocd-api.md) |
| 给非工程师讲这件事 | [`eli5/index.html`](./eli5/index.html) | — |

## 文档清单

| 文档 | 定位 |
|---|---|
| **[`argocd-topics/`](./argocd-topics/README.md)** | **✅ 当前有效方案**：Argo CD 生产化落地 10 篇专题 + 7 个可复制示例（无 Crossplane） |
| [`requirement.md`](./requirement.md) | 平台方 / 开发方边界、ownership 表、跨云控制面原始需求 |
| [`poc.md`](./poc.md) | Crossplane 最小 PoC：一个控制集群管理其他 Project 的 GKE |
| [`poc-minimax.md`](./poc-minimax.md) | **主线**：UCP 总体方案（架构、版本矩阵、RACI、资源、9 步实施） |
| [`poc-argocd-integration.md`](./poc-argocd-integration.md) | 控制面分工、字段所有权、prune/selfHeal、namespace 规则 |
| [`poc-argocd-git-to-apply-trigger.md`](./poc-argocd-git-to-apply-trigger.md) | Git 变更 → apply 的逐阶段链路与三条触发路径 |
| [`argocd-admin-guide.md`](./argocd-admin-guide.md) | Argo CD 管理员手册：RBAC / AppProject / 同步语义 / 跨集群 / 通知 / 排障 |
| [`argocd-cli-guide.md`](./argocd-cli-guide.md) | CLI 实战手册（v3.5.6） |
| [`argocd-api.md`](./argocd-api.md) | REST / gRPC API 参考（v3.5.6） |
| [`argocd-application-guide.md`](./argocd-application-guide.md) | **`Application` 资源详解**：字段逐个解释、9 个示例、四种创建方式、坑位速查 |
| [`Kustomize.md`](./Kustomize.md) | **Kustomize × Argo CD**：Kustomize 做什么、Argo CD 四层集成机制、版本/buildOptions、10 个常见坑 |
| [`examples/argocd-application/`](./examples/argocd-application/README.md) | 可直接改造的 `Application` / `ApplicationSet` 示例 YAML（9 个） |
| [`argo-api-claude.md`](./argo-api-claude.md) | API 清单的另一份整理，与 `argocd-api.md` 内容高度重叠 |
| [`next-steps-roadmap.md`](./next-steps-roadmap.md) | **下一步知识探索路线图**：缺口清单、优先级、两周日历 |
| [`eli5/`](./eli5/index.html) | 四张给非工程师看的图解 HTML |
| [`scripts/verify-poc.sh`](./scripts/verify-poc.sh) | PoC 端到端验收脚本（只读，8 项检查） |
| [`scripts/ci-validate.sh`](./scripts/ci-validate.sh) | PR 门禁：YAML 语法 / 版本固定 / 只同步 XR / 命名一致性 |
| `install.yaml` | Argo CD v3.5.6 官方安装清单 |

## 脚本

```bash
# 对活集群跑 PoC 验收（只读，不改任何资源）
./scripts/verify-poc.sh --team team-a

# 对 manifests 目录跑 PR 门禁（静态，不需要集群）
./scripts/ci-validate.sh ucp/manifests
```

> 两个脚本目前都没有在真实集群 / 真实仓库上跑过（生成时环境无集群），
> 首次使用时先看脚本输出里的 WARN 逐条确认降级行为。

## 版本基线

| 组件 | 版本 |
|---|---|
| Argo CD | v3.5.6 |
| Crossplane Core | v2.4.3 |
| provider-gcp-container | v3.1.0 |
| function-go-templating | v0.13.2 |
| function-auto-ready | v0.7.3 |

> 版本不一致时以本表为准；`poc-minimax.md` 早期章节里出现的"≥ 2.4.8"是官方下限，非目标版本。
