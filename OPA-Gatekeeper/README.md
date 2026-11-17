# OPA-Gatekeeper
## 目录结构
```OPA-Gatekeeper/├── docs/├── Rego/├── constraint-explorers/├── demo-yaml/├── diagrams/├── docs/├── gatekeeperyaml/├── README.md```
## 子目录内容
- `Rego/`: 子目录: docs
- `constraint-explorers/`: 文件: README.md, allowed-repos.md, block-loadbalancer-services.md, block-nodeport-services.md, containerlimits.md ... (共 14 个文件)
- `demo-yaml/`: 文件: demo-app.yaml
- `diagrams/`: 图表目录
- `docs/`: 文档目录
- `gatekeeperyaml/`: 文件: backup-constraints.yaml, gatekeeper.yaml
- `merged-scripts.md`: 合并的 shell 脚本合集(verify-gatekeeper.sh / source.sh / check-status.sh),2026-08-02 自 `gcp/gke/opa-gatekeeper/` 同步
- `policy-controller-vs-open-source-comparison.md`: OPA Gatekeeper 开源版 vs GKE Policy Controller 商业版对比
- `docs/opa-report-cronjob-design.md`: GKE Gatekeeper 月度报告 CronJob 方案设计文档(CronJob + GAR 镜像 + KSA 只读 RBAC + GitHub Pages),2026-11-02 自 ChatGPT 共享会话整理
- `docs/opa-report-cronjob-conversation.md`: 上述方案的完整会话记录(需求 + 评估 + 最终产物),2026-11-02
