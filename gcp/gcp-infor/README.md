# GCP-Infor - GCP Platform Information Tools

快速获取 GCP 平台配置和资源信息的工具集，类似 `neofetch` 风格，专为 GCP 平台管理员和 SRE 设计。

## 快速开始

```bash
# 1. 验证环境
./linux-scripts/gcp-validate.sh --fix

# 2. 运行前置检查
./assistant/gcp-preflight.sh

# 3. 获取 GCP 信息
./assistant/gcpfetch-safe --full
```

---

## 工具概览

### 核心工具

| 工具 | 用途 | 推荐场景 |
|------|------|----------|
| `gcpfetch` | 快速展示 GCP 资源信息 | 日常查看、开发环境 |
| `assistant/gcpfetch-safe` | 容错版本，生产就绪 | 生产环境、CI/CD |
| `gcp-explore.sh` | 详细扫描 21 类资源 | 平台审计、资源盘点 |
| `gcp-functions.sh` | 50+ 可复用函数库 | 自定义脚本开发 |

### 辅助工具

| 工具 | 用途 |
|------|------|
| `assistant/gcp-preflight.sh` | 部署前环境检查 |
| `assistant/run-verify.sh` | 一键验证所有功能 |
| `linux-scripts/gcp-linux-env.sh` | Linux 环境诊断 |
| `linux-scripts/gcp-validate.sh` | 脚本语法验证 |

---

## 使用示例

### 1. 基础信息查看

```bash
# 快速查看（带 logo）
./gcpfetch

# 完整信息
./gcpfetch --full

# 无 logo 纯文本
./gcpfetch --no-logo --no-color
```

**输出示例**:
```
        ___           ___        GCP Platform Info
       /  /\         /  /\       ------------------
      /  /:/_       /  /:/       Project: my-project
     /  /:/ /\     /  /:/        Account: user@example.com
    /  /:/_/::\   /  /:/  ___    Region: us-central1
   /__/:/__\/\:\ /__/:/  /  /\   Zone: us-central1-a
   
   Google Cloud Platform         GCE Instances: 5 (web-1, web-2, ...)
                                 GKE Clusters: 2 (prod, dev)
                                 GKE Nodes: 12
                                 GKE Deployments: 25
                                 Storage Buckets: 8
                                 VPCs: 3 (default, prod-vpc, dev-vpc)
```

### 2. 生产环境使用（推荐）

```bash
# 使用安全版本，指定项目（不修改 gcloud 配置）
./assistant/gcpfetch-safe --project my-project-id --full

# 生成报告
./assistant/gcpfetch-safe --no-logo --no-color --full > gcp-report-$(date +%Y%m%d).txt
```

### 3. 详细资源探索

```bash
# 扫描所有资源类型
./gcp-explore.sh

# 只查看特定部分
./gcp-explore.sh | grep -A 10 "GKE"
```

### 4. 使用函数库

```bash
# 在自定义脚本中使用
source ./gcp-functions.sh

# 调用函数
project=$(gcp_get_project)
clusters=$(gcp_count_gke_clusters)
nodes=$(gcp_count_gke_nodes)

echo "Project: $project"
echo "Clusters: $clusters"
echo "Total Nodes: $nodes"

# 列出资源
gcp_list_gke_clusters
gcp_list_vpcs
```

---

## 部署指南

### Linux 服务器部署

```bash
# 1. 克隆或复制到服务器
cd /opt/gcp-tools
git clone <repo> .

# 2. 验证脚本
cd gcp/gcp-infor
./linux-scripts/gcp-validate.sh --fix

# 3. 检查环境
./linux-scripts/gcp-linux-env.sh --diagnose

# 4. 配置 gcloud
gcloud auth login
# 或使用服务账号
gcloud auth activate-service-account --key-file=/path/to/key.json
gcloud config set project YOUR_PROJECT_ID

# 5. 运行前置检查
./assistant/gcp-preflight.sh

# 6. 测试
./assistant/gcpfetch-safe --full
```

### CI/CD 集成

```yaml
# GitLab CI 示例
gcp-inventory:
  stage: report
  script:
    - gcloud auth activate-service-account --key-file="${GCP_SA_KEY}"
    - cd gcp/gcp-infor
    - ./assistant/gcpfetch-safe --project "${GCP_PROJECT_ID}" --no-logo --no-color --full > inventory.txt
  artifacts:
    paths:
      - inventory.txt
    expire_in: 30 days
```

```yaml
# GitHub Actions 示例
- name: Generate GCP Inventory
  run: |
    gcloud auth activate-service-account --key-file="${{ secrets.GCP_SA_KEY }}"
    cd gcp/gcp-infor
    ./assistant/gcpfetch-safe --project "${{ secrets.GCP_PROJECT_ID }}" --full > inventory.txt
```

### 定时任务

```bash
# crontab -e
# 每天早上 8 点生成报告
0 8 * * * /opt/gcp-tools/gcp/gcp-infor/assistant/gcpfetch-safe --full --no-logo > /var/log/gcp-daily-$(date +\%Y\%m\%d).txt

# 每周一生成详细审计报告
0 9 * * 1 /opt/gcp-tools/gcp/gcp-infor/gcp-explore.sh > /var/log/gcp-audit-$(date +\%Y\%m\%d).txt
```

---

## 功能说明

### gcpfetch / gcpfetch-safe

**基础信息**:
- Project, Account, Region, Zone
- GCE Instances (数量 + 名称)
- Secret Manager (数量 + 前 10 个)
- GKE Clusters (数量 + 名称)
- GKE Nodes (总数)
- GKE Deployments (总数)
- Storage Buckets (数量)
- VPCs (数量 + 名称)
- Subnets (数量)

**扩展信息** (`--full`):
- Firewall Rules
- Load Balancers
- Service Accounts
- Cloud SQL
- Cloud Run
- Cloud Functions

**区别**:
- `gcpfetch`: 标准版本，快速但 API 失败时会报错
- `gcpfetch-safe`: 容错版本，API 失败时显示 N/A，支持 `--project` 参数

### gcp-explore.sh

扫描 21 类资源:
1. Compute Engine (Instances, Instance Groups, Disks)
2. GKE (Clusters)
3. Networking (VPCs, Subnets, Firewall Rules, Routes, Peerings)
4. Load Balancing (Forwarding Rules, Backend Services, Health Checks)
5. Cloud Armor (Security Policies)
6. Storage (Buckets)
7. Cloud SQL
8. Secret Manager
9. IAM (Service Accounts)
10. Cloud Run
11. Cloud Functions
12. Pub/Sub (Topics, Subscriptions)
13. Cloud DNS
14. BigQuery
15. APIs (Enabled APIs)
16. Billing
17. Organization (Projects)
18. Monitoring (Uptime Checks)
19. Logging (Log Sinks)
20. SSL Certificates
21. Quotas

### gcp-functions.sh

**50+ 函数分类**:

**基础配置**:
- `gcp_get_project()`, `gcp_get_account()`, `gcp_get_region()`, `gcp_get_zone()`

**Compute Engine**:
- `gcp_count_instances()`, `gcp_list_instances()`, `gcp_describe_instance()`

**GKE**:
- `gcp_count_gke_clusters()`, `gcp_list_gke_clusters()`
- `gcp_count_gke_nodes()`, `gcp_count_gke_deployments()`

**Networking**:
- `gcp_count_vpcs()`, `gcp_list_vpcs()`, `gcp_count_subnets()`
- `gcp_count_firewall_rules()`, `gcp_list_vpc_peerings()`

**其他服务**:
- Storage, Cloud SQL, Secret Manager, IAM, Cloud Run, Cloud Functions
- Pub/Sub, Cloud DNS, SSL Certificates, Monitoring, Logging, APIs

**工具函数**:
- `print_color()`, `print_separator()`, `print_header()`

---

## 前置要求

### 必需
- **gcloud CLI** - Google Cloud SDK
- **bash** 4.0+
- **基础工具**: `wc`, `tr`, `sed`, `awk`, `grep`

### 可选
- **kubectl** - 查看 GKE Deployments
- **gsutil** - 查看 Storage Buckets
- **bq** - 查看 BigQuery

### 权限要求

**最小权限**:
```
roles/viewer  # 项目查看者（推荐）
```

**或自定义角色包含**:
- `resourcemanager.projects.get`
- `compute.instances.list`
- `container.clusters.list`
- `container.clusters.get`
- `secretmanager.secrets.list`
- `storage.buckets.list`

### API 启用

```bash
# 启用必需的 API
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable storage-api.googleapis.com
```

---

## 故障排查

### 问题 1: gcloud not found

```bash
# 检查安装
which gcloud

# 安装 (Ubuntu/Debian)
sudo apt-get install google-cloud-sdk

# 安装 (CentOS/RHEL)
sudo yum install google-cloud-sdk

# 或使用通用安装
curl https://sdk.cloud.google.com | bash
```

### 问题 2: No active account

```bash
# 交互式登录
gcloud auth login

# 或使用服务账号
gcloud auth activate-service-account --key-file=/path/to/key.json
```

### 问题 3: No active project

```bash
# 设置项目
gcloud config set project YOUR_PROJECT_ID

# 或使用 --project 参数（推荐）
./assistant/gcpfetch-safe --project YOUR_PROJECT_ID
```

### 问题 4: Permission denied

```bash
# 检查当前权限
gcloud projects get-iam-policy PROJECT_ID --flatten="bindings[].members" --filter="bindings.members:user:YOUR_EMAIL"

# 需要至少 roles/viewer 角色
```

### 问题 5: API not enabled

```bash
# 查看已启用的 API
gcloud services list --enabled

# 启用缺失的 API
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
```

### 问题 6: kubectl context 被修改

**解决方案**: 使用修复后的版本（已自动保存/恢复 context）

```bash
# 手动恢复 context
kubectl config get-contexts
kubectl config use-context YOUR_CONTEXT
```

---

## 性能优化

### 慢速操作

1. **GKE Nodes 查询** - 需要遍历所有集群
2. **GKE Deployments 查询** - 需要获取每个集群凭证
3. **存储桶列表** - 大量存储桶时较慢

### 优化建议

```bash
# 1. 使用基础模式（不加 --full）
./gcpfetch

# 2. 缓存结果
./gcpfetch --full > /tmp/gcp-cache.txt
cat /tmp/gcp-cache.txt

# 3. 并行查询（自定义脚本）
source ./gcp-functions.sh
gcp_count_instances &
gcp_count_gke_clusters &
wait
```

---

## 高级用法

### 1. 多项目对比

```bash
#!/bin/bash
for project in project-a project-b project-c; do
  echo "=== $project ==="
  ./assistant/gcpfetch-safe --project "$project" --no-logo
  echo ""
done
```

### 2. 生成 JSON 报告

```bash
#!/bin/bash
source ./gcp-functions.sh

cat > report.json <<EOF
{
  "project": "$(gcp_get_project)",
  "timestamp": "$(date -Iseconds)",
  "resources": {
    "gce_instances": $(gcp_count_instances),
    "gke_clusters": $(gcp_count_gke_clusters),
    "gke_nodes": $(gcp_count_gke_nodes),
    "vpcs": $(gcp_count_vpcs),
    "buckets": $(gcp_count_buckets)
  }
}
EOF
```

### 3. 告警集成

```bash
#!/bin/bash
source ./gcp-functions.sh

nodes=$(gcp_count_gke_nodes)
if [[ $nodes -lt 10 ]]; then
  echo "WARNING: Only $nodes GKE nodes running!" | mail -s "GKE Alert" admin@example.com
fi
```

### 4. Prometheus Exporter

```bash
#!/bin/bash
# gcp_exporter.sh - 导出 Prometheus 格式指标
source ./gcp-functions.sh

cat <<EOF
# HELP gcp_gke_clusters Total number of GKE clusters
# TYPE gcp_gke_clusters gauge
gcp_gke_clusters $(gcp_count_gke_clusters)

# HELP gcp_gke_nodes Total number of GKE nodes
# TYPE gcp_gke_nodes gauge
gcp_gke_nodes $(gcp_count_gke_nodes)

# HELP gcp_gce_instances Total number of GCE instances
# TYPE gcp_gce_instances gauge
gcp_gce_instances $(gcp_count_instances)
EOF
```

---

## 文档

- **gcpfetch-README.md** - gcpfetch 详细文档
- **REVIEW-REPORT.md** - 完整的代码审查报告
- **assistant/README.md** - Assistant 工具说明
- **linux-scripts/gcp-knowledge.md** - Linux 知识库

---

## 支持的 Linux 发行版

- ✅ Ubuntu 20.04, 22.04, 24.04
- ✅ Debian 11, 12
- ✅ CentOS 7, 8
- ✅ RHEL 8, 9
- ✅ Amazon Linux 2, 2023
- ✅ AlmaLinux 8, 9
- ✅ Rocky Linux 8, 9

---

## 贡献

欢迎提交 Issue 和 Pull Request！

**开发指南**:
1. 所有脚本使用 `#!/usr/bin/env bash`
2. 使用 `set -euo pipefail` 严格模式
3. 函数命名: `gcp_*` 或 `get_*`
4. 添加错误处理和 fallback
5. 运行 `./linux-scripts/gcp-validate.sh` 验证

---

## 许可证

根据项目主许可证

---

## 快速参考

```bash
# 环境检查
./linux-scripts/gcp-linux-env.sh --diagnose
./assistant/gcp-preflight.sh

# 快速查看
./gcpfetch
./assistant/gcpfetch-safe

# 完整信息
./gcpfetch --full
./assistant/gcpfetch-safe --full

# 详细探索
./gcp-explore.sh

# 指定项目
./assistant/gcpfetch-safe --project PROJECT_ID

# 使用函数库
source ./gcp-functions.sh
gcp_count_gke_nodes

# 验证所有功能
./assistant/run-verify.sh

# 脚本验证
./linux-scripts/gcp-validate.sh --fix
```

---

## 联系方式

如有问题或建议，请通过项目 Issue 反馈。
