# GCP Secret Manager 审计脚本 - 快速参考

## 🚀 快速开始

```bash
# 1. 验证单个应用权限
bash verify-gcp-secretmanage.sh <deployment> <namespace>

# 2. 查看所有 Secret 的 Groups 和 SA（推荐）
bash list-secrets-groups-sa.sh

# 3. 生成完整审计报告
bash list-all-secrets-permissions.sh
```

## 📊 脚本对比

| 特性 | verify | list-groups-sa | list-all |
|------|--------|----------------|----------|
| 速度 | ⚡⚡⚡ | ⚡⚡ | ⚡ |
| 详细程度 | 单个应用 | 中等 | 完整 |
| 输出格式 | 终端 | TXT + CSV | TXT + CSV + JSON + MD + HTML |
| 适用场景 | 故障排查 | 日常检查 | 审计报告 |

## 🎯 使用场景

### 场景 1: 应用无法访问 Secret
```bash
bash verify-gcp-secretmanage.sh my-api production
```
**检查内容:**
- ✅ KSA → GSA 绑定
- ✅ GSA IAM 角色
- ✅ Secret 权限
- ✅ Workload Identity

---

### 场景 2: 查看哪些 Groups 有权限
```bash
bash list-secrets-groups-sa.sh

# 输出示例:
# 所有唯一的 Groups:
#      1  dev-team@company.com
#      2  ops-team@company.com
```

---

### 场景 3: 月度审计报告
```bash
bash list-all-secrets-permissions.sh

# 生成:
# - summary.txt (汇总)
# - report.html (可视化)
# - secrets-permissions.csv (数据分析)
```

## 📋 常用命令

### 查询特定 Secret
```bash
# 方法 1: 使用 grep
bash list-secrets-groups-sa.sh | grep "api-v1"

# 方法 2: 从 CSV 查询
grep "api-v1" secrets-groups-sa-*.csv
```

### 查询特定 Group
```bash
# 查看某个 Group 有权限访问哪些 Secret
grep "dev-team@company.com" secrets-groups-sa-*.csv
```

### 查询特定 ServiceAccount
```bash
# 查看某个 SA 有权限访问哪些 Secret
grep "my-api-rt-sa" secrets-groups-sa-*.csv
```

### 统计分析
```bash
# 统计每个 Secret 的权限数量
cut -d',' -f1 secrets-groups-sa-*.csv | sort | uniq -c | sort -rn

# 统计 Groups 出现次数
grep ",Group," secrets-groups-sa-*.csv | cut -d',' -f3 | sort | uniq -c | sort -rn

# 统计 ServiceAccounts 出现次数
grep ",ServiceAccount," secrets-groups-sa-*.csv | cut -d',' -f3 | sort | uniq -c | sort -rn
```

## 🔍 输出文件说明

### list-secrets-groups-sa.sh 输出
```
secrets-groups-sa-20241114-103000.txt  # 详细文本报告
secrets-groups-sa-20241114-103000.csv  # CSV 数据
```

**CSV 格式:**
```csv
Secret Name,Type,Member,Role
api-v1-secret,Group,dev-team@company.com,roles/secretmanager.secretAccessor
api-v1-secret,ServiceAccount,api-v1-rt-sa@project.iam.gserviceaccount.com,roles/secretmanager.secretAccessor
```

### list-all-secrets-permissions.sh 输出
```
secret-audit-20241114-103000/
├── summary.txt                    # 📄 汇总报告
├── secrets-permissions.csv        # 📊 CSV 数据（包含所有成员类型）
├── secrets-permissions.json       # 📦 JSON 数据
├── report.md                      # 📝 Markdown 报告
└── report.html                    # 🌐 HTML 可视化报告（推荐）
```

## 💡 实用技巧

### 1. 定期审计
```bash
# 添加到 crontab（每周一早上 9 点）
0 9 * * 1 cd /path/to/scripts && bash list-secrets-groups-sa.sh
```

### 2. 比较两次审计差异
```bash
# 使用 diff
diff secrets-groups-sa-20241114.csv secrets-groups-sa-20241121.csv

# 使用 git
git diff --no-index secrets-groups-sa-20241114.csv secrets-groups-sa-20241121.csv
```

### 3. 导出到 Excel
```bash
# macOS
open secrets-groups-sa-*.csv

# Windows
start secrets-groups-sa-*.csv

# Linux
libreoffice secrets-groups-sa-*.csv
```

### 4. 发送报告邮件
```bash
# 生成报告并发送
bash list-all-secrets-permissions.sh
echo "请查看附件" | mail -s "Secret Manager 审计报告" \
  -a secret-audit-*/report.html \
  team@company.com
```

### 5. 集成到 CI/CD
```yaml
# GitLab CI 示例
audit-secrets:
  stage: audit
  script:
    - bash list-secrets-groups-sa.sh
  artifacts:
    paths:
      - secrets-groups-sa-*.csv
      - secrets-groups-sa-*.txt
    expire_in: 30 days
  only:
    - schedules
```

## ⚠️ 常见问题

### Q: 权限不足
```bash
# 检查当前用户
gcloud auth list

# 切换账号
gcloud auth login

# 或使用 Service Account
gcloud auth activate-service-account --key-file=key.json
```

### Q: jq 未安装
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

### Q: 输出乱码
```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

## 📊 CSV 数据分析示例

### 使用 awk 分析
```bash
# 统计每个 Secret 的权限数量
awk -F',' 'NR>1 {count[$1]++} END {for (secret in count) print secret, count[secret]}' \
  secrets-groups-sa-*.csv | sort -k2 -rn

# 列出所有 Groups
awk -F',' '$2=="\"Group\"" {print $3}' secrets-groups-sa-*.csv | sort -u

# 列出所有 ServiceAccounts
awk -F',' '$2=="\"ServiceAccount\"" {print $3}' secrets-groups-sa-*.csv | sort -u
```

### 使用 Python 分析
```python
import pandas as pd

# 读取 CSV
df = pd.read_csv('secrets-groups-sa-20241114-103000.csv')

# 统计每个 Secret 的权限数量
print(df.groupby('Secret Name').size().sort_values(ascending=False))

# 统计每种类型的数量
print(df['Type'].value_counts())

# 列出所有唯一的 Groups
print(df[df['Type'] == 'Group']['Member'].unique())

# 找出权限最多的 Secret
print(df.groupby('Secret Name').size().idxmax())
```

## 🎨 HTML 报告预览

HTML 报告包含：
- 📊 统计卡片（Secret 总数、Groups、ServiceAccounts 等）
- 📈 按角色统计表格
- 📋 详细的 Secret 列表
- 🎨 美观的界面设计
- 🔍 易于浏览和搜索

**打开方式:**
```bash
# macOS
open secret-audit-*/report.html

# Windows
start secret-audit-*/report.html

# Linux
xdg-open secret-audit-*/report.html
```

## 🔐 权限要求

### 最小权限（只读）
```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:your-email@company.com" \
  --role="roles/secretmanager.viewer"
```

### 完整权限（管理）
```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:your-email@company.com" \
  --role="roles/secretmanager.admin"
```

## 📚 相关文档

- [完整文档](./README-audit-scripts.md)
- [GCP Secret Manager 文档](https://cloud.google.com/secret-manager/docs)
- [IAM 角色参考](https://cloud.google.com/iam/docs/understanding-roles)

---

**提示:** 推荐使用 `list-secrets-groups-sa.sh` 进行日常检查，使用 `list-all-secrets-permissions.sh` 生成月度审计报告。
