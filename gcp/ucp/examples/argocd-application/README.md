# Application 示例集

每个文件的用途、适用场景和风险见 [`../../argocd-application-guide.md`](../../argocd-application-guide.md) 第 7 节。

| 文件 | 主题 | 关键点 |
|---|---|---|
| `01-minimal-xr.yaml` | 最小 XR 应用 | UCP 日常形态；`prune: false` |
| `02-prod-automated.yaml` | 生产稳态 | `prune: true` + `selfHeal` + 重试退避 |
| `03-helm-chart.yaml` | Helm chart 来源 | 填 `chart` 就不填 `path` |
| `04-kustomize.yaml` | Kustomize | 环境差异用 overlay，不复制 YAML |
| `05-multi-source.yaml` | 多源 | `ref` / `name` 的引用关系 |
| `06-ignore-differences.yaml` | 忽略差异 | 必须配 `RespectIgnoreDifferences=true` |
| `07-hook-presync-smoke.yaml` | PreSync 冒烟门禁 | 含一个 hook Job |
| `08-cross-cluster.yaml` | 跨集群 | 三个前提缺一不可 |
| `09-applicationset-team.yaml` | ApplicationSet | UCP 正式做法，按目录批量生成 |

## 怎么用这些示例

```bash
# 1) 先干跑，看字段有没有问题（不会写集群）
kubectl apply --dry-run=server -f 01-minimal-xr.yaml

# 2) 真建一个（把 YOUR_ORG / repoURL / 路径改成你的）
kubectl -n argocd apply -f 01-minimal-xr.yaml

# 3) 看 Argo CD 拉到了什么、diff 是什么（此时先别开自动同步）
argocd app get team-a-project-a --show-operation
argocd app diff team-a-project-a

# 4) 手动同步一次，确认链路通了再交给 ApplicationSet
argocd app sync team-a-project-a

# 5) 确认 XR 落到目标 namespace
kubectl get gkeclusters.platform.example.org -A
```

## 改这些示例时的红线

- **不要**在 `teams/` 目录下放 `ManagedResource` / `Composition` / `Provider`——
  MR 由 Crossplane Composition 生成，Argo CD 直接 apply 会和 Composition 抢所有权。
  `scripts/ci-validate.sh` 会拦这种写法。
- **不要**在 PoC 阶段把 `prune` 打开：它意味着"删 Git 文件 = 删集群里的资源"。
- **不要**在 manifest 里写 `metadata.namespace`，它会盖掉 `destination.namespace`，
  造成资源散落在多个 namespace。
- 所有 `repoURL` 里的 `YOUR_ORG` 记得替换成真实组织名。
