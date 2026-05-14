# GKE (Google Kubernetes Engine) 知识库

## 目录描述
本目录包含Google Kubernetes Engine相关的知识、集群管理、部署策略和最佳实践。

## 目录结构
```
gke/
├── docs/                     # Markdown文档
└── README.md                 # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `Blue-Green-design.md`: 蓝绿部署设计
- `Blue-Green.md`: 蓝绿部署实现
- `connect-GKE.md`: 连接GKE集群
- `gke-blue-green.md`: GKE蓝绿部署
- `GKE-Labels.md`: GKE标签管理
- `GKE-Master.md`: GKE主节点相关
- `gke-node-version.md`: GKE节点版本管理
- `GKE-Pod-Disk.md`: GKE Pod磁盘相关
- `gke-sa-gcp-sa-addbinding*.md`: GKE服务账号与GCP服务账号绑定
- `gke-service-protection.md`: GKE服务保护
- `gke-upgrade.md`: GKE升级相关
- `grafana-gke.md`: Grafana监控GKE
- `Kong-canary.md`: Kong金丝雀部署
- `multi-tenant-cluster.md`: 多租户集群
- `Multi-tenant.md`: 多租户相关
- `node-pool-describe.md`: 节点池描述

## 快速检索
- 蓝绿部署: 查看 `docs/` 目录中的 `Blue-Green*.md` 和 `gke-blue-green.md`
- 集群升级: 查看 `docs/` 目录中的 `gke-upgrade.md`
- 服务账号: 查看 `docs/` 目录中的 `gke-sa-gcp-sa-addbinding*.md`
- 多租户: 查看 `docs/` 目录中的 `multi-tenant*.md` 文件
- 节点管理: 查看 `docs/` 目录中的 `gke-node-version.md`, `node-pool-describe.md`
- 监控: 查看 `docs/` 目录中的 `grafana-gke.md`