# Artifact Registry

## 文档

| 文件 | 内容 |
|:--|:--|
| [cleanup-policy-assessment.md](cleanup-policy-assessment.md) | Cleanup policy 评估报告：参数模型、调整方式（CLI/控制台/Terraform）、删除时间逻辑、镜像使用情况判定、风险矩阵与 Runbook |

## 脚本

| 文件 | 用途 |
|:--|:--|
| [scripts/cleanup-policy-audit.sh](scripts/cleanup-policy-audit.sh) | 只读评估脚本：导出仓库策略 → 盘点版本 → 离线推演"谁会被删/何时删" → 与 GKE 工作负载镜像引用交叉比对（标 ⚠ 仍被引用） |

```bash
gcp/artifact-registry/scripts/cleanup-policy-audit.sh \
  --project example-project --location us-central1 --repository example-repo \
  --kube-context my-cluster --json
```
