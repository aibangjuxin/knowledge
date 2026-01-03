# Ali (Alibaba Cloud) 知识库

## 目录描述
本目录包含阿里云（Alibaba Cloud）相关的知识、Kubernetes迁移、DNS配置和最佳实践。

## 目录结构
```
ali/
├── ali-dns/                      # 阿里云DNS相关配置
├── docs/                         # Markdown文档
├── k8s-cluster-migration/        # K8s集群迁移相关内容
├── k8s-migration-proxy/          # K8s迁移代理相关内容
├── max-computer/                 # 阿里云MaxCompute相关内容
├── migrate-plan/                 # 迁移计划相关内容
├── scripts/                      # Shell脚本
├── secrets-backup/               # 密钥备份相关内容
└── README.md                     # 本说明文件
```

## 子目录说明 (按功能分类)
### docs/ - 文档
- `a-call-b-debug.md`: A调用B调试相关
- `Ali-Logstore.md`: 阿里云日志服务相关
- `imagepullsecret.md`: 镜像拉取密钥相关
- `k8s-resources.md`: K8s资源相关
- `merged-scripts.md`: 合并的脚本
- `migrate-exclude-secret.md`: 迁移排除密钥相关
- `migrate.TODO`: 迁移待办事项
- `namespace-status.md`: 命名空间状态相关
- `slb-binding-ingress.md`: SLB绑定Ingress相关
- `v*.md`: 版本相关文档
- `verify-e2e.md`: 端到端验证相关

### scripts/ - 脚本
- `k8s-resources.sh`: K8s资源相关脚本
- `migrate-exclude-secret.sh`: 迁移排除密钥相关脚本
- `namespace-status.sh`: 命名空间状态相关脚本
- `verify-e2e.sh`: 端到端验证相关脚本

## 快速检索
- K8s迁移: 查看 `k8s-cluster-migration/` 和 `migrate-plan/` 目录
- 阿里云DNS: 查看 `ali-dns/` 目录
- SLB配置: 查看 `docs/` 目录中的 `slb-binding-ingress.md`
- 密钥管理: 查看 `secrets-backup/` 目录及 `docs/` 目录中的 `imagepullsecret.md`
- 迁移计划: 查看 `docs/` 目录中的 `migrate.TODO` 和 `migrate-plan/` 目录
- 脚本: 查看 `scripts/` 目录