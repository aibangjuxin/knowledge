# GCP Secret Manager 权限审计脚本

## 脚本概览

本目录包含三个用于审计 GCP Secret Manager 权限的脚本：

| 脚本 | 功能 | 适用场景 |
|------|------|---------|
| `verify-gcp-secretmanage.sh` | 验证单个 Deployment 的权限链路 | 排查特定应用的权限问题 |
| `list-secrets-groups-sa.sh` | 快速列出所有 Secret 的 Groups 和 SA | 快速查看权限概览 |
| `list-all-secrets-permissions.sh` | 完整的权限审计报告 | 生成详细的审计文档 |

## 1. verify-gcp-secretmanage.sh

### 功能
验证 Kubernetes Deployment 到 GCP Secret Manager 的完整权限链路。

### 使用方法
```bash
bash verify-gcp-secretmanage.sh <deployment-name> <namespace>
```

### 示例
```bash
bash verify-gcp-secretmanage.sh my-api-deployment production
```

### 验证内容
1. ✅ Deployment 使用的 Kubernetes ServiceAccount (KSA)
2. ✅ KSA 绑定的 GCP ServiceAccount (GSA)
3. ✅ GSA 的 IAM 角色
4. ✅ Secret Manager 权限
5. ✅ Workload Identity 绑定

### 输出示例
```
开始验证 Deployment my-api-deployment 的权限链路...

1. 获取 Deployment 的 ServiceAccount...
Kubernetes ServiceAccount: my-api-ksa

2. 获取 KSA 绑定的 GCP ServiceAccount...
GCP ServiceAccount: my-api-rt-sa@project-id.iam.gserviceaccount.com

3. 检查 GCP ServiceAccount 的 IAM 角色...
ROLE
roles/secretmanager.secretAccessor

4. 检查 Secret Manager 的权限...
Secret: my-api-secret
  serviceAccount:my-api-rt-sa@project-id.iam.gserviceaccount.com

5. 验证 Workload Identity 绑定...
serviceAccount:project-id.svc.id.goog[namespace/my-api-ksa]
```

---

## 2. list-secrets-groups-sa.sh

### 功能
快速列出项目中所有 Secret 及其绑定的 Groups 和 ServiceAccounts。

### 使用方法
```bash
# 使用当前项目
bash list-secrets-groups-sa.sh

# 指定项目
bash list-secrets-groups-sa.sh my-project-id
```

### 输出内容
- 每个 Secret 的 Groups 列表
- 每个 Secret 的 ServiceAccounts 列表
- 统计汇总
- 唯一的 Groups 和 ServiceAccounts 列表

### 输出示例
```
=========================================
Secret Manager - Groups & ServiceAccounts
=========================================
项目: my-project-id
时间: 2024-11-14 10:30:00
=========================================

找到 15 个 Secret

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Secret: api-v1-secret
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  👥 Groups:
    - dev-team@company.com
      角色: roles/secretmanager.secretAccessor
    - ops-team@company.com
      角色: roles/secretmanager.secretAccessor

  🤖 ServiceAccounts:
    - api-v1-rt-sa@project-id.iam.gserviceaccount.com
      角色: roles/secretmanager.secretAccessor

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Secret: api-v2-secret
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🤖 ServiceAccounts:
    - api-v2-rt-sa@project-id.iam.gserviceaccount.com
      角色: roles/secretmanager.secretAccessor

=========================================
汇总统计
=========================================
Secret 总数: 15
包含 Groups 的 Secret: 8
包含 ServiceAccounts 的 Secret: 15
Groups 总数: 12
ServiceAccounts 总数: 15

所有唯一的 Groups:
     1  dev-team@company.com
     2  ops-team@company.com
     3  security-team@company.com
唯一 Groups 数量: 3

所有唯一的 ServiceAccounts:
     1  api-v1-rt-sa@project-id.iam.gserviceaccount.com
     2  api-v2-rt-sa@project-id.iam.gserviceaccount.com
     ...
唯一 ServiceAccounts 数量: 15

=========================================
输出文件:
  📄 详细报告: secrets-groups-sa-20241114-103000.txt
  📊 CSV 文件: secrets-groups-sa-20241114-103000.csv
=========================================
```

### 生成的文件
- `secrets-groups-sa-YYYYMMDD-HHMMSS.txt` - 详细文本报告
- `secrets-groups-sa-YYYYMMDD-HHMMSS.csv` - CSV 格式数据

### CSV 格式
```csv
Secret Name,Type,Member,Role
api-v1-secret,Group,dev-team@company.com,roles/secretmanager.secretAccessor
api-v1-secret,ServiceAccount,api-v1-rt-sa@project-id.iam.gserviceaccount.com,roles/secretmanager.secretAccessor
```

---

## 3. list-all-secrets-permissions.sh

### 功能
生成完整的 Secret Manager 权限审计报告，包括所有类型的成员（Groups、ServiceAccounts、Users、Domains 等）。

### 使用方法
```bash
# 使用当前项目
bash list-all-secrets-permissions.sh

# 指定项目
bash list-all-secrets-permissions.sh my-project-id
```

### 输出内容
生成一个包含多个文件的审计报告目录：

```
secret-audit-20241114-103000/
├── summary.txt           # 汇总报告
├── details.txt           # 详细信息
├── secrets-permissions.csv   # CSV 数据
├── secrets-permissions.json  # JSON 数据
├── report.md            # Markdown 报告
└── report.html          # HTML 可视化报告
```

### 报告内容
1. **权限绑定统计**
   - Groups 数量
   - ServiceAccounts 数量
   - Users 数量
   - Domains 数量
   - Others 数量

2. **按角色统计**
   - 每个角色的绑定数量

3. **所有 Groups 列表**
   - 项目中所有唯一的 Groups

4. **所有 ServiceAccounts 列表**
   - 项目中所有唯一的 ServiceAccounts

5. **按 Secret 详细列表**
   - 每个 Secret 的完整权限配置

### HTML 报告特点
- 📊 可视化统计卡片
- 📋 交互式表格
- 🎨 美观的界面设计
- 🔍 易于浏览和搜索

### 输出示例
```
=========================================
GCP Secret Manager 权限审计
=========================================
项目 ID: my-project-id
时间: 2024-11-14 10:30:00
=========================================

[1/4] 获取所有 Secret...
找到 15 个 Secret

[2/4] 分析每个 Secret 的权限...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Secret: api-v1-secret
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
创建时间: 2024-01-15T10:30:00Z

  角色: roles/secretmanager.secretAccessor
    ✓ Group: dev-team@company.com
    ✓ Group: ops-team@company.com
    ✓ ServiceAccount: api-v1-rt-sa@project-id.iam.gserviceaccount.com

  统计:
    Groups: 2
    ServiceAccounts: 1
    Users: 0
    Others: 0

[3/4] 生成汇总报告...
[4/4] 生成 Markdown 报告...

=========================================
审计完成！
=========================================

生成的文件:
  📄 汇总报告: secret-audit-20241114-103000/summary.txt
  📊 CSV 文件: secret-audit-20241114-103000/secrets-permissions.csv
  📦 JSON 文件: secret-audit-20241114-103000/secrets-permissions.json
  📝 Markdown 报告: secret-audit-20241114-103000/report.md
  🌐 HTML 报告: secret-audit-20241114-103000/report.html

输出目录: secret-audit-20241114-103000

提示:
  - 使用 'cat summary.txt' 查看汇总报告
  - 使用 Excel 打开 CSV 文件进行数据分析
  - 在浏览器中打开 HTML 文件查看可视化报告
```

---

## 使用场景对比

### 场景 1: 排查单个应用的权限问题
**使用脚本:** `verify-gcp-secretmanage.sh`

```bash
# 应用无法访问 Secret，需要验证权限链路
bash verify-gcp-secretmanage.sh my-api production
```

**优点:**
- 快速定位问题
- 验证完整的权限链路
- 适合故障排查

---

### 场景 2: 快速查看所有 Secret 的 Groups 和 SA
**使用脚本:** `list-secrets-groups-sa.sh`

```bash
# 需要快速了解哪些 Groups 和 SA 有权限
bash list-secrets-groups-sa.sh
```

**优点:**
- 输出简洁清晰
- 专注于 Groups 和 ServiceAccounts
- 生成 CSV 便于分析
- 执行速度快

---

### 场景 3: 完整的权限审计和合规检查
**使用脚本:** `list-all-secrets-permissions.sh`

```bash
# 需要生成完整的审计报告
bash list-all-secrets-permissions.sh
```

**优点:**
- 包含所有类型的成员
- 多种格式输出（TXT、CSV、JSON、Markdown、HTML）
- 适合审计和合规检查
- 可视化报告易于分享

---

## 常见问题

### Q1: 如何筛选特定的 Secret？

**方法 1: 使用 grep**
```bash
bash list-secrets-groups-sa.sh | grep "api-v1"
```

**方法 2: 修改脚本添加过滤**
```bash
# 在脚本中添加过滤条件
SECRETS=$(gcloud secrets list --filter="name~api-v1" --format="value(name)")
```

### Q2: 如何导出到 Excel？

生成的 CSV 文件可以直接在 Excel 中打开：
```bash
# macOS
open secrets-groups-sa-*.csv

# Windows
start secrets-groups-sa-*.csv

# Linux
libreoffice secrets-groups-sa-*.csv
```

### Q3: 如何查看特定 Group 有权限访问哪些 Secret？

```bash
# 从 CSV 文件中查询
grep "dev-team@company.com" secrets-groups-sa-*.csv
```

### Q4: 如何定期运行审计？

**方法 1: Cron Job**
```bash
# 每周一早上 9 点运行
0 9 * * 1 /path/to/list-all-secrets-permissions.sh my-project-id
```

**方法 2: Cloud Scheduler**
```bash
# 创建 Cloud Scheduler 任务
gcloud scheduler jobs create http secret-audit \
  --schedule="0 9 * * 1" \
  --uri="https://your-function-url" \
  --http-method=POST
```

### Q5: 如何比较两次审计的差异？

```bash
# 使用 diff 比较两个 CSV 文件
diff secrets-groups-sa-20241114.csv secrets-groups-sa-20241121.csv

# 或使用 git
git diff secrets-groups-sa-20241114.csv secrets-groups-sa-20241121.csv
```

---

## 最佳实践

### 1. 定期审计
- 每周运行一次完整审计
- 每月生成合规报告
- 保存历史记录便于对比

### 2. 权限最小化原则
- 定期检查不必要的权限
- 移除不再使用的 Groups 和 ServiceAccounts
- 使用最小权限角色

### 3. 文档化
- 记录每个 Secret 的用途
- 记录 Groups 和 ServiceAccounts 的所有者
- 维护权限变更日志

### 4. 自动化
- 集成到 CI/CD Pipeline
- 权限变更时自动审计
- 异常情况自动告警

---

## 权限要求

运行这些脚本需要以下权限：

### 对于 verify-gcp-secretmanage.sh
```yaml
# Kubernetes 权限
- get deployments
- get serviceaccounts

# GCP 权限
- resourcemanager.projects.getIamPolicy
- iam.serviceAccounts.getIamPolicy
- secretmanager.secrets.getIamPolicy
- secretmanager.secrets.list
```

### 对于 list-secrets-groups-sa.sh 和 list-all-secrets-permissions.sh
```yaml
# GCP 权限
- secretmanager.secrets.list
- secretmanager.secrets.getIamPolicy
- secretmanager.secrets.get
```

### 授予权限示例
```bash
# 授予 Secret Manager Admin 角色（包含所有必要权限）
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:your-email@company.com" \
  --role="roles/secretmanager.admin"

# 或使用只读角色
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:your-email@company.com" \
  --role="roles/secretmanager.viewer"
```

---

## 故障排查

### 问题 1: 权限不足
```
ERROR: (gcloud.secrets.list) User does not have permission to access projects
```

**解决方案:**
```bash
# 检查当前用户
gcloud auth list

# 切换到有权限的账号
gcloud auth login

# 或使用 Service Account
gcloud auth activate-service-account --key-file=key.json
```

### 问题 2: jq 命令未找到
```
bash: jq: command not found
```

**解决方案:**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

### 问题 3: 输出乱码
```
# 设置正确的字符编码
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

---

## 参考资源

- [GCP Secret Manager 文档](https://cloud.google.com/secret-manager/docs)
- [IAM 角色参考](https://cloud.google.com/iam/docs/understanding-roles)
- [Workload Identity 文档](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [gcloud secrets 命令参考](https://cloud.google.com/sdk/gcloud/reference/secrets)

---

## 更新日志

- **2024-11-14**: 初始版本
  - 创建三个审计脚本
  - 支持多种输出格式
  - 添加 HTML 可视化报告
