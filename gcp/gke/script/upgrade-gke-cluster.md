## 脚本功能说明
### 🚀 用法示例

```bash
# 使用当前激活的 gcloud project，轮询所有集群
./verify-gke-cluster-upgrade.sh

# 指定 Project（不指定则用当前激活的）
./verify-gke-cluster-upgrade.sh --project my-project-id

# 指定某个集群
./verify-gke-cluster-upgrade.sh --project my-project --cluster my-cluster

# 指定区域（Regional cluster / Autopilot）
./verify-gke-cluster-upgrade.sh --project my-project --location us-central1

# 只看最近 30 天
./verify-gke-cluster-upgrade.sh --days 30

# 详细模式（显示完整版本变化信息）
./verify-gke-cluster-upgrade.sh --verbose

# 导出为 CSV
./verify-gke-cluster-upgrade.sh --format csv > upgrade-report.csv
```

### ✨ 核心能力

| 功能 | 说明 |
|------|------|
| **自动 Project 探测** | 无需 `--project` 时读取 `gcloud config` 当前激活项目 |
| **多集群轮询** | 自动枚举项目下所有集群逐一检查 |
| **版本变化摘要** | 从 operation `detail` 字段提取 `A版本 -> B版本` 的变化记录 |
| **时间范围过滤** | `--days N` 控制查看最近 N 天（默认 90 天） |
| **操作类型识别** | 区分 Master 升级、Node 升级、自动升级、自动修复等 |
| **耗时统计** | 自动计算每个操作的耗时（分/时） |
| **多格式输出** | `table`（默认）/ `json` / `csv` |
| **macOS/Linux 兼容** | `date` 命令自动识别 GNU/BSD 差异 |

> **依赖**: `gcloud`（必须）、`jq`（可选，建议安装）