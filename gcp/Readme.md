# GCP (Google Cloud Platform) 知识库

## 目录描述
本目录包含Google Cloud Platform云服务相关的知识、实践经验和服务使用指南。

## 目录结构
```
gcp/
├── asm/                      # Anthos Service Mesh相关
│   ├── diagram/              # ASM/Istio 架构流程图
│   ├── gloo/                 # Gloo Mesh 相关
│   └── istio-egress/         # Istio Egress Gateway
├── bigquery/                 # BigQuery数据分析服务
├── buckets/                  # Cloud Storage存储桶相关
├── cloud-armor/              # Cloud Armor安全防护
│   ├── armor-python/         # Cloud Armor Python SDK
│   └── dedicated-armor/      # Dedicated Armor 配置
├── cloud-run/                # Cloud Run无服务器计算
│   ├── cloud-run-automation/ # Cloud Run 自动化
│   ├── cloud-run-debug/      # Cloud Run 调试
│   ├── cloud-run-spec/       # Cloud Run 规格说明
│   ├── cloud-run-violation/  # Cloud Run 违规处理
│   ├── container-validation/ # 容器镜像验证
│   ├── onboarding/          # Cloud Run 上手指南
│   └── verify/              # Cloud Run 验证方法
├── cost/                     # 成本管理相关
├── cross-project/            # 跨项目网络配置
│   └── cross-project-gateway/
├── gce/                      # Google Compute Engine
│   └── rolling/              # 实例滚动更新
├── gcp-cloud-build/          # Cloud Build CI/CD
├── gcp-infor/                # GCP信息汇总
│   ├── assistant/           # AI助手集成
│   └── linux-scripts/       # Linux脚本
├── gke/                      # Google Kubernetes Engine
├── glb/                      # Global Load Balancer
├── housekeep/                # GCP资源整理和维护
├── ingress/                  # 入口控制器相关
├── lb/                       # 负载均衡服务
├── logs/                     # 日志服务相关
├── migrate-gcp/              # GCP迁移相关内容
│   ├── migrate-dns/         # DNS迁移
│   ├── migrate-secret-manage/ # 密钥管理迁移
│   ├── migration-info/      # 迁移信息
│   └── pop-migrate/         # PoP迁移
├── misc/                     # 杂项GCP相关内容
├── mtls/                     # mTLS安全认证
│   ├── mtls-test/           # mTLS测试用例和证书
│   └── trust-config/        # Trust Config配置
├── network/                  # 网络配置相关
│   ├── psc-sre/             # PSC SRE监控
│   └── psc-subnet/          # PSC子网配置
├── psa-psc/                  # Private Service Access / PSC
│   └── psa-sql/             # PSC Cloud SQL
├── pub-sub/                  # Pub/Sub消息服务
│   ├── css2/                # CSS2相关
│   └── pub-sub-cmek/        # CMEK配置
├── recaptcha/                # reCAPTCHA服务
├── sa/                       # 服务账号相关
├── secret-manage/            # 密钥管理服务
│   ├── java-examples/       # Java SDK示例
│   └── list-secret/        # 密钥列表管理
├── sql/                      # Cloud SQL数据库服务
├── storage/                  # 存储服务相关
├── tools/                    # GCP相关工具
├── gsutil.md                 # Gsutil命令行工具指南
├── Readme.md                 # GCP目录主说明文件
└── README.md                 # 本说明文件
```

## 文件说明
- `gsutil.md`: Gsutil命令行工具的使用指南
- `Readme.md`: GCP目录的主说明文件

## 快速检索
- 命令行工具: 查看 `gsutil.md`
- 容器服务: 查看 `gke/` 目录
- 服务网格: 查看 `asm/` 目录（含架构图 `asm/diagram/`）
- 数据分析: 查看 `bigquery/` 目录
- 存储服务: 查看 `buckets/`, `storage/` 目录
- 网络安全: 查看 `cloud-armor/`, `mtls/`, `network/` 目录
- 数据库: 查看 `sql/` 目录
- 消息服务: 查看 `pub-sub/` 目录
- 认证授权: 查看 `sa/`, `secret-manage/` 目录
- 负载均衡: 查看 `lb/`, `glb/` 目录
- 入口网关: 查看 `ingress/` 目录
- 跨项目网络: 查看 `cross-project/`, `psa-psc/` 目录