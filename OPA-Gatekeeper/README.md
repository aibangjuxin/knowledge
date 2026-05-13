# OPA Gatekeeper

Kubernetes 策略控制（OPA Gatekeeper / GKE Policy Controller）知识库。

## 目录结构

```
OPA-Gatekeeper/
├── constraint-explorers/   # ConstraintTemplate 探索示例
├── demo-yaml/             # 示例 YAML
├── diagrams/              # 架构/流程图（HTML）
├── docs/                  # 文档（22个 .md 文件，已从根目录迁移）
├── gatekeeperyaml/        # Gatekeeper 部署配置
└── README.md
```

## 核心文档（docs/）

Dynamic-context-aware-policy.md, Join-Fleet.md, create.md, gatekeeper-best-practices-resource-mapping.md, gatekeeper-concepts.md, gatekeeper-release-3.14.yaml, gke-policy-control-with-tep.md, gke-policy-controller-requirement.md, gke-policy-controller-with-gatekeeper.md, gke-setup-policy-controller.md, how-to-control-template.md, how-to-using-gpc.md, k8srequiredlabels.md, multi-tenant-resource-quota-exception-handling.md, opa-design.md, policy-layer.md, rego-concept.md, setup-log.md, single-cluster-opa-gatekeeper-setup.md, step-by-step-install.md, why-using-gke-policy-controller.md, why-using-open-gatekeeper.md

## 其他子目录

- `constraint-explorers/`: 14 文件
- `diagrams/`: 01-fleet-architecture.html, 02-policy-hierarchy.html, 03-onboarding-workflow.html, 04-gitops-pipeline.html, 05-policy-lifecycle.html
- `gatekeeperyaml/`: backup-constraints.yaml, gatekeeper.yaml
- `demo-yaml/`: demo-app.yaml
