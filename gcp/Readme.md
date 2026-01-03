# GCP (Google Cloud Platform) 知识库

## 目录描述
本目录包含Google Cloud Platform云服务相关的知识、实践经验和服务使用指南。

## 目录结构
```
gcp/
├── asm/                      # Anthos Service Mesh相关
├── bigquery/                 # BigQuery数据分析服务
├── buckets/                  # Cloud Storage存储桶相关
├── cloud-armor/              # Cloud Armor安全防护
├── cloud-run/                # Cloud Run无服务器计算
├── cost/                     # 成本管理相关
├── gce/                      # Google Compute Engine
├── gke/                      # Google Kubernetes Engine
├── housekeep/                # GCP资源整理和维护
├── ingress/                  # 入口控制器相关
├── lb/                       # 负载均衡服务
├── logs/                     # 日志服务相关
├── migrate-gcp/              # GCP迁移相关内容
├── misc/                     # 杂项GCP相关内容
├── mtls/                     # mTLS安全认证
├── network/                  # 网络配置相关
├── psa/                      # Private Service Access
├── pub-sub/                  # Pub/Sub消息服务
├── recaptcha/                # reCAPTCHA服务
├── sa/                       # 服务账号相关
├── secret-manage/            # 密钥管理服务
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
- 数据分析: 查看 `bigquery/` 目录
- 存储服务: 查看 `buckets/`, `storage/` 目录
- 网络安全: 查看 `cloud-armor/`, `mtls/`, `network/` 目录
- 数据库: 查看 `sql/` 目录
- 消息服务: 查看 `pub-sub/` 目录
- 认证授权: 查看 `sa/`, `secret-manage/` 目录