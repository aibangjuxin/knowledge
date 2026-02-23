# GCPFetch - GCP Platform Information Tool

gcp/gcpfetch - 主要工具，类似 neofetch 的 GCP 信息展示

显示项目、账号、区域等基础配置
GCE 实例、GKE 集群/节点/部署数量
Secret Manager、存储桶、VPC、子网等
--full 模式显示更多资源（防火墙、LB、Cloud SQL、Cloud Run 等）
gcp-explore.sh
 - 探索脚本，全面扫描 GCP 资源

21 个资源类别的详细列表
包括 Compute、GKE、网络、存储、数据库、安全、监控等
适合做平台审计和资源盘点
gcp-functions.sh
 - 函数库（50+ 函数）

可被其他脚本 source 复用
涵盖所有主要 GCP 服务的查询函数
包含工具函数（颜色输出、分隔符等）
gcpfetch-README.md
 - 完整文档

类似 `neofetch` 风格的 GCP 平台信息获取工具，快速展示当前 GCP 项目的配置和资源概览。

## 功能特性

### 基础信息（默认显示）
- **Project**: 当前活动的 GCP 项目名称
- **Account**: 当前登录的 GCP 账号
- **Region**: 默认计算区域
- **Zone**: 默认计算可用区
- **GCE Instances**: 计算引擎实例数量和名称（显示前 5 个）
- **Secrets**: Secret Manager 中的密钥数量和名称（显示前 10 个）
- **GKE Clusters**: GKE 集群数量和名称
- **GKE Nodes**: 所有 GKE 集群的节点总数
- **GKE Deployments**: 所有 GKE 集群中的 Deployment 总数
- **Storage Buckets**: Cloud Storage 存储桶数量
- **VPCs**: VPC 网络数量和名称
- **Subnets**: 子网总数

### 扩展信息（--full 模式）
- **Firewall Rules**: 防火墙规则总数
- **Load Balancers**: 负载均衡器（转发规则）数量
- **Service Accounts**: 服务账号数量
- **Cloud SQL**: Cloud SQL 实例数量和名称
- **Cloud Run**: Cloud Run 服务数量
- **Cloud Functions**: Cloud Functions 函数数量

## 使用方法

### 基本用法
```bash
./gcpfetch
```

### 显示完整信息
```bash
./gcpfetch --full
```

### 不显示 Logo
```bash
./gcpfetch --no-logo
```

### 强制使用颜色
```bash
./gcpfetch --color
```

### 禁用颜色
```bash
./gcpfetch --no-color
```

### 显示帮助
```bash
./gcpfetch --help
```

## 前置要求

1. 安装 Google Cloud SDK
   ```bash
   # macOS (Homebrew)
   brew install --cask google-cloud-sdk
   
   # 或者下载安装包
   # https://cloud.google.com/sdk/docs/install
   ```

2. 配置 gcloud 认证
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

3. 如果需要查看 GKE Deployments，确保安装了 kubectl
   ```bash
   brew install kubectl
   ```

## 实现的函数

脚本中封装了以下函数，可以单独调用：

- `get_project()` - 获取当前项目
- `get_account()` - 获取当前账号
- `get_region()` - 获取默认区域
- `get_zone()` - 获取默认可用区
- `get_gce_instances()` - 获取 GCE 实例信息
- `get_secrets()` - 获取 Secret Manager 密钥列表
- `get_gke_clusters()` - 获取 GKE 集群信息
- `get_gke_nodes()` - 获取 GKE 节点总数
- `get_gke_deployments()` - 获取 GKE Deployment 总数
- `get_buckets()` - 获取存储桶数量
- `get_vpcs()` - 获取 VPC 网络信息
- `get_subnets()` - 获取子网数量
- `get_firewall_rules()` - 获取防火墙规则数量
- `get_load_balancers()` - 获取负载均衡器数量
- `get_service_accounts()` - 获取服务账号数量
- `get_cloud_sql()` - 获取 Cloud SQL 实例信息
- `get_cloud_run()` - 获取 Cloud Run 服务数量
- `get_cloud_functions()` - 获取 Cloud Functions 数量

## 示例输出

```
        ___           ___        GCP Platform Info
       /  /\         /  /\       ------------------
      /  /:/_       /  /:/       Project: my-gcp-project
     /  /:/ /\     /  /:/        Account: user@example.com
    /  /:/_/::\   /  /:/  ___    Region: us-central1
   /__/:/__\/\:\ /__/:/  /  /\   Zone: us-central1-a
   \  \:\ /~~/:/ \  \:\ /  /:/   
    \  \:\  /:/   \  \:\  /:/    GCE Instances: 3 (web-1, web-2, db-1)
     \  \:\/:/     \  \:\/:/     Secrets: 5 (api-key, db-pass, ...)
      \  \::/       \  \::/      GKE Clusters: 2 (prod-cluster, dev-cluster)
       \__\/         \__\/       GKE Nodes: 12
                                 GKE Deployments: 25
   Google Cloud Platform         Storage Buckets: 8
                                 VPCs: 3 (default, prod-vpc, dev-vpc)
                                 Subnets: 15
```

## 性能优化建议

由于 `gcloud` 命令需要网络请求，某些操作可能较慢：

1. GKE Nodes 和 Deployments 查询需要遍历所有集群
2. 使用 `--full` 模式会执行更多 API 调用
3. 建议在稳定网络环境下使用

## 扩展建议

可以根据需要添加更多功能：

- Cloud Armor 策略数量
- Pub/Sub 主题和订阅
- BigQuery 数据集
- Cloud DNS 区域
- IAM 策略绑定
- Billing 账户信息
- API 启用状态
- 配额使用情况

## 故障排查

如果遇到权限问题：
```bash
# 检查当前认证状态
gcloud auth list

# 重新认证
gcloud auth login

# 检查项目配置
gcloud config list
```

如果 GKE 信息无法获取：
```bash
# 确保有 container.clusters.get 权限
gcloud projects get-iam-policy PROJECT_ID

# 手动获取集群凭证
gcloud container clusters get-credentials CLUSTER_NAME --zone ZONE
```
