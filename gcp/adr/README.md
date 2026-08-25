# GCP Architecture Decision Records (ADR)

> 本目录存放 GCP / GKE 架构决策记录。每篇 ADR 一事一议，遵循 Michael Nygard 的 ADR 模板（Context / Decision / Consequences / Alternatives）。

## 索引

| 编号 | 标题 | 状态 | 日期 |
|------|------|------|------|
| [008](./008-static-pod-no-secret-configmap-k8s-137.md) | 应对 Kubernetes v1.37 Static Pod 禁止引用 Secret/ConfigMap 的架构变更 | Proposed | 2026-08-25 |

## 命名规范

- `NNN-<kebab-case-title>.md`
- 编号三位，从 `001` 起，每篇独立递增
- 文件名 kebab-case，标题用自然语言

## 阅读路径建议

- 新成员入门：先读 `008`（最新的）
- 跨项目 PSC 模式相关：在 `cross-project/` 下另有专题
- 架构图（HTML + SVG）放在每个 ADR 同一目录或 `gcp/` 子目录
