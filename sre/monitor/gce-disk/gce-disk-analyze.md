# GCE Squid 代理磁盘监控实施方案

## 场景概述

### 核心约束条件
- **资源归属**: MIG 及 Image 由其他团队维护，无修改权限
- **访问限制**: 无法 SSH 登录到 GCE 实例
- **业务影响**: Squid 代理磁盘满载会导致用户访问中断（Downtime）
- **处理方式**: 手动介入，通过 MIG 操作解决问题

### 解决思路
利用 **Cloud Monitoring** 监控磁盘使用率 → 触发告警 → 通过 **MIG Recreate** 操作重建实例（获得全新磁盘）

---

## 方案架构

```
┌─────────────────┐
│ GCE Instance    │
│ (Squid Proxy)   │
│                 │
│ Ops Agent       │ ──► 上报磁盘指标
└─────────────────┘
         │
         ▼
┌─────────────────────────┐
│ Cloud Monitoring        │
│ agent.googleapis.com/   │
│ disk/percent_used       │
└─────────────────────────┘
         │
         ▼ 磁盘使用率 ≥ 85%
┌─────────────────────────┐
│ Alert Policy            │
│ 持续 5 分钟触发告警      │
└─────────────────────────┘
         │
         ▼
┌─────────────────────────┐
│ Notification Channel    │
│ (Email/Slack/PagerDuty) │
└─────────────────────────┘
         │
         ▼
┌─────────────────────────┐
│ 运维人员接收告警         │
└─────────────────────────┘
         │
         ▼
┌─────────────────────────┐
│ 手动执行 MIG Recreate   │
│ 重建问题实例            │
└─────────────────────────┘
```

---

## 前置条件检查

### 1. 确认 Ops Agent 已安装

由于无法 SSH 登录，需要通过 Cloud Monitoring 验证指标是否存在。

**验证步骤**:

1. 进入 GCP Console → **Monitoring** → **Metrics Explorer**
2. 在 "Select a metric" 中搜索: `agent.googleapis.com/disk/percent_used`
3. 在 Filter 中添加: `resource.labels.instance_group = "YOUR_MIG_NAME"`
4. 查看是否有数据点显示

**结果判断**:
- ✅ **有数据**: Ops Agent 已安装，可以继续配置监控
- ❌ **无数据**: 需要联系 Image 维护团队在镜像中安装 Ops Agent

### 2. 确认磁盘删除策略

这是**最关键**的前置条件，决定方案是否可行。

**检查步骤**:

1. 进入 **Compute Engine** → **Instance groups**
2. 点击你的 MIG 名称
3. 点击 **Instance template** 链接
4. 查看 **Boot disk** 或 **Additional disks** 配置
5. 确认 **Deletion rule** 设置为: `Delete disk on instance deletion`

**⚠️ 重要警告**:
- 如果磁盘设置为 "Keep disk"（保留磁盘），重建实例后会挂载**同一个满载的旧磁盘**
- 这会导致告警持续触发，问题无法解决
- 必须确保磁盘随实例删除

---

## 监控配置步骤

### 方式一: 通过 GCP Console 配置（推荐）

#### Step 1: 创建告警策略

1. 导航到 **Monitoring** → **Alerting**
2. 点击 **Create Policy**

#### Step 2: 配置监控指标

**Target 配置**:
```
Resource type: VM Instance
Metric: agent.googleapis.com/disk/percent_used
```

**Filter 配置**:
```
resource.labels.instance_group = "YOUR_MIG_NAME"
```

**可选 - 指定磁盘设备**:
```
metric.labels.device = "sda1"  # 根据实际情况调整
```

**Aggregation**:
- Aligner: `mean`
- Period: `5 minutes`

#### Step 3: 配置告警条件

| 配置项 | 值 |
|--------|-----|
| **Condition type** | Threshold |
| **Alert trigger** | Any time series violates |
| **Threshold position** | Above threshold |
| **Threshold value** | 85 |
| **For** | 5 minutes |

**解释**: 当任何实例的磁盘使用率持续 5 分钟超过 85% 时触发告警

#### Step 4: 配置通知渠道

1. 选择或创建 Notification Channel:
   - Email
   - Slack
   - PagerDuty
   - Webhook

2. 设置告警名称: `Squid Proxy MIG - Disk Usage > 85%`

3. 添加文档链接（可选）:
   ```
   Documentation: 参考 gce-disk-analyze.md 进行手动处理
   ```

4. 保存策略

---

### 方式二: 通过 gcloud CLI 配置

#### 创建告警策略配置文件

```bash
cat > squid-disk-alert-policy.yaml <<'EOF'
displayName: "Squid Proxy MIG - Disk Usage Alert"
documentation:
  content: "磁盘使用率超过 85%，请参考 gce-disk-analyze.md 执行 MIG Recreate 操作"
  mimeType: "text/markdown"

conditions:
  - displayName: "Disk usage above 85% for 5 minutes"
    conditionThreshold:
      filter: |
        resource.type = "gce_instance"
        AND resource.labels.instance_group = "YOUR_MIG_NAME"
        AND metric.type = "agent.googleapis.com/disk/percent_used"
      comparison: COMPARISON_GT
      thresholdValue: 85
      duration: 300s
      aggregations:
        - alignmentPeriod: 60s
          perSeriesAligner: ALIGN_MEAN

notificationChannels:
  - projects/YOUR_PROJECT_ID/notificationChannels/YOUR_CHANNEL_ID

alertStrategy:
  autoClose: 604800s  # 7 天后自动关闭
  notificationRateLimit:
    period: 3600s  # 每小时最多发送一次通知
EOF
```

#### 应用配置

```bash
# 替换配置文件中的变量
sed -i 's/YOUR_MIG_NAME/squid-proxy-mig/g' squid-disk-alert-policy.yaml
sed -i 's/YOUR_PROJECT_ID/your-project-id/g' squid-disk-alert-policy.yaml
sed -i 's/YOUR_CHANNEL_ID/1234567890/g' squid-disk-alert-policy.yaml

# 创建告警策略
gcloud alpha monitoring policies create --policy-from-file=squid-disk-alert-policy.yaml
```

#### 查看已创建的告警策略

```bash
# 列出所有告警策略
gcloud alpha monitoring policies list

# 查看特定策略详情
gcloud alpha monitoring policies describe POLICY_ID
```

---

## 通知渠道配置

### 创建 Email 通知渠道

```bash
gcloud alpha monitoring channels create \
  --display-name="Ops Team - Squid Alerts" \
  --type=email \
  --channel-labels=email_address=ops-team@example.com
```

### 创建 Slack 通知渠道

```bash
gcloud alpha monitoring channels create \
  --display-name="Ops Slack - Squid Alerts" \
  --type=slack \
  --channel-labels=url=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

### 列出现有通知渠道

```bash
gcloud alpha monitoring channels list --format="table(name,displayName,type)"
```

---

## 告警响应流程

### 完整处理流程图

```
收到告警
    │
    ▼
验证告警信息
    │
    ├─► 识别问题实例名称
    ├─► 确认磁盘使用率
    └─► 检查业务影响
    │
    ▼
进入 GCP Console
    │
    ▼
定位 MIG 和问题实例
    │
    ▼
执行 Recreate 操作
    │
    ├─► 选中问题实例
    ├─► 点击 RECREATE 按钮
    └─► 确认操作
    │
    ▼
等待实例重建
    │
    ├─► 旧实例终止（磁盘删除）
    ├─► 新实例创建（全新磁盘）
    └─► 新实例加入服务
    │
    ▼
验证问题解决
    │
    ├─► 检查新实例状态
    ├─► 确认告警自动清除
    └─► 记录处理结果
```

---

### 详细操作步骤

#### Step 1: 接收并分析告警

**告警邮件包含的关键信息**:
- 实例名称: `squid-proxy-mig-abcd`
- MIG 名称: `squid-proxy-mig`
- 磁盘使用率: `87%`
- 触发时间: `2025-11-16 10:30:00 UTC`

#### Step 2: 登录 GCP Console

```
https://console.cloud.google.com/
```

导航路径:
```
Compute Engine → Instance groups → [选择你的 MIG]
```

#### Step 3: 定位问题实例

1. 在 MIG 详情页面，点击 **Instances** 标签
2. 在实例列表中找到告警中提到的实例名称
3. 确认实例状态为 `RUNNING`

#### Step 4: 执行 Recreate 操作

**通过 Console 操作**:

1. ☑️ 勾选问题实例前的复选框
2. 点击页面顶部的 **RECREATE** 按钮
3. 在确认对话框中点击 **RECREATE**

**通过 gcloud 命令操作**:

```bash
gcloud compute instance-groups managed recreate-instances INSTANCE_GROUP_NAME \
  --instances=INSTANCE_NAME \
  --zone=ZONE
```

**示例**:
```bash
gcloud compute instance-groups managed recreate-instances squid-proxy-mig \
  --instances=squid-proxy-mig-abcd \
  --zone=us-central1-a
```

#### Step 5: 监控重建过程

**预期时间线**:
- **0-2 分钟**: 旧实例进入 `STOPPING` 状态
- **2-3 分钟**: 旧实例被删除，磁盘同时删除
- **3-5 分钟**: 新实例创建并启动
- **5-7 分钟**: 新实例通过健康检查，加入服务

**监控命令**:
```bash
# 实时查看 MIG 实例状态
watch -n 5 'gcloud compute instance-groups managed list-instances squid-proxy-mig --zone=us-central1-a'
```

#### Step 6: 验证问题解决

**检查项**:

1. **新实例状态**:
   ```bash
   gcloud compute instances describe NEW_INSTANCE_NAME --zone=ZONE --format="value(status)"
   ```
   预期输出: `RUNNING`

2. **磁盘使用率**:
   - 返回 **Monitoring** → **Metrics Explorer**
   - 查看新实例的 `disk/percent_used` 指标
   - 预期值: < 20%（全新实例）

3. **告警状态**:
   - 进入 **Monitoring** → **Alerting**
   - 确认告警自动解除（通常 5-10 分钟内）

4. **服务可用性**:
   - 如果配置了负载均衡，检查后端健康状态
   - 确认新实例已接收流量

---

### 记录处理结果

**建议使用的记录模板**:

```markdown
## 磁盘告警处理记录

**告警信息**:
- 告警时间: 2025-11-16 10:30:00 UTC
- MIG 名称: squid-proxy-mig
- 问题实例: squid-proxy-mig-abcd
- 磁盘使用率: 87%

**处理操作**:
- 操作时间: 2025-11-16 10:35:00 UTC
- 操作人员: [Your Name]
- 执行动作: MIG Recreate Instance
- 操作命令:
  ```bash
  gcloud compute instance-groups managed recreate-instances squid-proxy-mig \
    --instances=squid-proxy-mig-abcd \
    --zone=us-central1-a
  ```

**处理结果**:
- 新实例名称: squid-proxy-mig-wxyz
- 新实例磁盘使用率: 15%
- 服务中断时间: ~3 分钟（在 LB 后端切换期间）
- 告警解除时间: 2025-11-16 10:45:00 UTC

**后续建议**:
- [ ] 如果频繁触发告警，考虑与 Image 维护团队协调增加磁盘容量
- [ ] 评估是否需要添加自动化清理机制
```

---

## 常见问题处理

### Q1: 告警触发后，发现多个实例同时磁盘满载

**处理策略**:

**不要同时 Recreate 所有实例**，这会导致服务完全中断。

**推荐做法**:
1. 按批次处理，每次 Recreate 1-2 个实例
2. 等待新实例完全启动并通过健康检查
3. 再处理下一批

**批量操作示例**:
```bash
# 第一批
gcloud compute instance-groups managed recreate-instances squid-proxy-mig \
  --instances=instance-1,instance-2 \
  --zone=us-central1-a

# 等待 5-10 分钟

# 第二批
gcloud compute instance-groups managed recreate-instances squid-proxy-mig \
  --instances=instance-3,instance-4 \
  --zone=us-central1-a
```

---

### Q2: Recreate 后告警仍然存在

**可能原因**:

1. **磁盘未随实例删除**
   - 检查实例模板的磁盘删除策略
   - 如果磁盘被保留，需要手动删除旧磁盘

2. **新实例挂载了旧磁盘**
   - 查看新实例的磁盘配置
   - 确认是否挂载了错误的磁盘

**解决方法**:
```bash
# 查看实例的磁盘
gcloud compute instances describe INSTANCE_NAME --zone=ZONE \
  --format="value(disks[].source)"

# 如果发现旧磁盘，需要：
# 1. 删除实例
# 2. 手动删除旧磁盘
# 3. 让 MIG 自动创建新实例
```

---

### Q3: 无法执行 Recreate 操作（权限不足）

**错误信息**:
```
ERROR: (gcloud.compute.instance-groups.managed.recreate-instances) 
Permission denied
```

**所需权限**:
- `compute.instanceGroupManagers.update`
- `compute.instances.delete`
- `compute.instances.create`

**解决方法**:
1. 联系 GCP 项目管理员
2. 申请以下 IAM 角色之一:
   - `roles/compute.instanceAdmin.v1`
   - `roles/compute.instanceGroupManager`

---

### Q4: 如何避免频繁触发告警

**短期方案**:
- 调整告警阈值: 85% → 90%
- 增加持续时间: 5 分钟 → 10 分钟

**长期方案**:

与 Image 维护团队协调以下优化:

1. **增加磁盘容量**
   - 当前: 50GB
   - 建议: 100GB 或更大

2. **配置日志轮转**
   ```bash
   # /etc/logrotate.d/squid
   /var/log/squid/*.log {
       daily
       rotate 7
       compress
       delaycompress
       notifempty
       postrotate
           /usr/sbin/squid -k rotate
       endscript
   }
   ```

3. **限制 Squid 缓存大小**
   ```bash
   # /etc/squid/squid.conf
   cache_dir ufs /var/spool/squid 20480 16 256  # 限制为 20GB
   ```

4. **添加定期清理脚本**
   ```bash
   # 每天凌晨清理 7 天前的日志
   0 2 * * * find /var/log/squid -name "*.log.*" -mtime +7 -delete
   ```

---

## 多级告警策略（可选）

为了更好地预警和响应，可以配置多级告警:

| 告警级别 | 磁盘使用率 | 持续时间 | 通知对象 | 响应时间 |
|---------|-----------|---------|---------|---------|
| **Info** | 70% | 10 分钟 | 运维团队 | 24 小时内关注 |
| **Warning** | 80% | 5 分钟 | 运维团队 | 4 小时内处理 |
| **Critical** | 85% | 5 分钟 | 运维团队 + 值班 | 立即处理 |
| **Emergency** | 95% | 1 分钟 | 全员 | 立即处理 |

**配置示例**:

```bash
# Warning 级别 (80%)
gcloud alpha monitoring policies create \
  --notification-channels=CHANNEL_ID \
  --display-name="Squid Disk Warning (80%)" \
  --condition-display-name="Disk > 80%" \
  --condition-threshold-value=80 \
  --condition-threshold-duration=300s

# Critical 级别 (85%)
gcloud alpha monitoring policies create \
  --notification-channels=CHANNEL_ID,ONCALL_CHANNEL_ID \
  --display-name="Squid Disk Critical (85%)" \
  --condition-display-name="Disk > 85%" \
  --condition-threshold-value=85 \
  --condition-threshold-duration=300s
```

---

## 监控 Dashboard（可选）

创建一个专门的 Dashboard 用于可视化监控:

### 通过 Console 创建

1. 进入 **Monitoring** → **Dashboards**
2. 点击 **Create Dashboard**
3. 添加以下 Charts:

**Chart 1: 磁盘使用率趋势**
```
Resource: VM Instance
Metric: agent.googleapis.com/disk/percent_used
Filter: resource.labels.instance_group = "squid-proxy-mig"
Chart Type: Line Chart
```

**Chart 2: 各实例磁盘使用率对比**
```
Resource: VM Instance
Metric: agent.googleapis.com/disk/percent_used
Filter: resource.labels.instance_group = "squid-proxy-mig"
Chart Type: Stacked Bar Chart
Group By: resource.instance_id
```

**Chart 3: 告警历史**
```
Resource: Alerting Policy
Metric: monitoring.googleapis.com/uptime_check/check_passed
Filter: policy_name = "Squid Disk Alert"
Chart Type: Heatmap
```

---

## 自动化脚本（可选）

虽然你提到不需要高级用法，但这里提供两个脚本用于简化操作：

### 脚本 1: 单实例重建脚本

用于快速重建单个实例：

```bash
#!/bin/bash
# recreate-squid-instance.sh

set -e

# 配置变量
PROJECT_ID="your-project-id"
MIG_NAME="squid-proxy-mig"
ZONE="us-central1-a"

# 从命令行参数获取实例名称
INSTANCE_NAME="$1"

if [ -z "$INSTANCE_NAME" ]; then
    echo "用法: $0 <instance-name>"
    echo "示例: $0 squid-proxy-mig-abcd"
    exit 1
fi

echo "========================================="
echo "准备重建实例: $INSTANCE_NAME"
echo "MIG: $MIG_NAME"
echo "Zone: $ZONE"
echo "========================================="

# 确认操作
read -p "确认执行 Recreate 操作? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "操作已取消"
    exit 0
fi

# 执行 Recreate
echo "正在执行 Recreate..."
gcloud compute instance-groups managed recreate-instances "$MIG_NAME" \
    --instances="$INSTANCE_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID"

echo "========================================="
echo "Recreate 操作已提交"
echo "请等待 5-10 分钟让新实例完全启动"
echo "========================================="

# 监控新实例状态
echo "监控 MIG 实例状态 (按 Ctrl+C 退出)..."
watch -n 10 "gcloud compute instance-groups managed list-instances $MIG_NAME --zone=$ZONE --project=$PROJECT_ID"
```

**使用方法**:
```bash
chmod +x recreate-squid-instance.sh
./recreate-squid-instance.sh squid-proxy-mig-abcd
```

---

### 脚本 2: 滚动重建脚本（Rolling Recreate）

用于批量重建多个实例，避免服务中断。完整脚本见 `rolling-recreate-instances.sh`。

**主要特性**:
- ✅ 分批次重建实例，避免服务完全中断
- ✅ 可配置批次大小和等待时间
- ✅ 自动等待 MIG 稳定后再处理下一批
- ✅ 支持指定实例列表或重建所有实例
- ✅ 支持 dry-run 模式（模拟运行）
- ✅ 彩色日志输出，清晰易读

**使用场景**:

1. **重建指定的多个实例**:
   ```bash
   ./rolling-recreate-instances.sh \
     --project your-project-id \
     --mig squid-proxy-mig \
     --zone us-central1-a \
     --instances instance-1,instance-2,instance-3
   ```

2. **重建所有实例（每批 2 个，间隔 10 分钟）**:
   ```bash
   ./rolling-recreate-instances.sh \
     --project your-project-id \
     --mig squid-proxy-mig \
     --zone us-central1-a \
     --all \
     --batch-size 2 \
     --wait-time 600
   ```

3. **模拟运行（不实际执行）**:
   ```bash
   ./rolling-recreate-instances.sh \
     --project your-project-id \
     --mig squid-proxy-mig \
     --zone us-central1-a \
     --all \
     --dry-run
   ```

4. **使用环境变量简化命令**:
   ```bash
   export PROJECT_ID="your-project-id"
   export MIG_NAME="squid-proxy-mig"
   export ZONE="us-central1-a"
   
   ./rolling-recreate-instances.sh --all --batch-size 2
   ```

**参数说明**:

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-p, --project` | GCP 项目 ID | 环境变量或脚本配置 |
| `-m, --mig` | MIG 名称 | 环境变量或脚本配置 |
| `-z, --zone` | Zone 名称 | 环境变量或脚本配置 |
| `-b, --batch-size` | 每批次重建实例数量 | 1 |
| `-w, --wait-time` | 批次间等待时间（秒） | 300 (5分钟) |
| `-i, --instances` | 指定实例列表（逗号分隔） | - |
| `-a, --all` | 重建所有实例 | - |
| `-d, --disk-threshold` | 只重建磁盘使用率超过阈值的实例 | - |
| `--dry-run` | 模拟运行，不实际执行 | false |
| `-h, --help` | 显示帮助信息 | - |

**执行流程**:

```
1. 检查前置条件 (gcloud, jq)
   │
   ▼
2. 获取实例列表
   │
   ▼
3. 显示待重建实例并确认
   │
   ▼
4. 开始滚动重建
   │
   ├─► 批次 1: 重建 instance-1
   │   └─► 等待 MIG 稳定
   │   └─► 等待 5 分钟
   │
   ├─► 批次 2: 重建 instance-2
   │   └─► 等待 MIG 稳定
   │   └─► 等待 5 分钟
   │
   └─► 批次 3: 重建 instance-3
       └─► 等待 MIG 稳定
   │
   ▼
5. 输出执行总结
```

**输出示例**:

```
[INFO] 2025-11-16 10:30:00 - =========================================
[INFO] 2025-11-16 10:30:00 - 配置信息
[INFO] 2025-11-16 10:30:00 - =========================================
[INFO] 2025-11-16 10:30:00 - 项目 ID: your-project-id
[INFO] 2025-11-16 10:30:00 - MIG 名称: squid-proxy-mig
[INFO] 2025-11-16 10:30:00 - Zone: us-central1-a
[INFO] 2025-11-16 10:30:00 - 批次大小: 2
[INFO] 2025-11-16 10:30:00 - 等待时间: 600s
[INFO] 2025-11-16 10:30:00 - =========================================

[INFO] 2025-11-16 10:30:05 - 待重建实例列表:
[INFO] 2025-11-16 10:30:05 -   - squid-proxy-mig-abcd
[INFO] 2025-11-16 10:30:05 -   - squid-proxy-mig-efgh
[INFO] 2025-11-16 10:30:05 -   - squid-proxy-mig-ijkl

[INFO] 2025-11-16 10:30:10 - =========================================
[INFO] 2025-11-16 10:30:10 - 批次 1 / 2
[INFO] 2025-11-16 10:30:10 - 实例: squid-proxy-mig-abcd squid-proxy-mig-efgh
[INFO] 2025-11-16 10:30:10 - =========================================
[INFO] 2025-11-16 10:30:10 - [1/3] 重建实例: squid-proxy-mig-abcd
[SUCCESS] 2025-11-16 10:30:15 - 实例 [squid-proxy-mig-abcd] 重建命令已提交
[INFO] 2025-11-16 10:30:15 - [2/3] 重建实例: squid-proxy-mig-efgh
[SUCCESS] 2025-11-16 10:30:20 - 实例 [squid-proxy-mig-efgh] 重建命令已提交
[INFO] 2025-11-16 10:30:20 - 等待 MIG 稳定...
[SUCCESS] 2025-11-16 10:32:30 - MIG 已稳定
[INFO] 2025-11-16 10:32:30 - 等待 600s 后处理下一批次...

[SUCCESS] 2025-11-16 10:45:00 - 所有实例重建完成！
```

**最佳实践**:

1. **首次使用先 dry-run**:
   ```bash
   ./rolling-recreate-instances.sh --all --dry-run
   ```

2. **小批次开始**:
   - 对于生产环境，建议 `--batch-size 1`
   - 确保每次只重建一个实例，最大化服务可用性

3. **合理设置等待时间**:
   - 默认 5 分钟通常足够
   - 如果实例启动较慢，可增加到 10 分钟 (`--wait-time 600`)

4. **监控服务状态**:
   - 在另一个终端监控服务健康状态
   - 如发现异常，可随时 Ctrl+C 中断脚本

5. **记录执行日志**:
   ```bash
   ./rolling-recreate-instances.sh --all 2>&1 | tee rolling-recreate-$(date +%Y%m%d-%H%M%S).log
   ```

---

## 总结

### 方案优势

✅ **无需 SSH 访问**: 完全通过 GCP 平台操作  
✅ **无需修改镜像**: 利用现有监控能力  
✅ **最小化权限**: 只需 MIG 操作权限  
✅ **符合云原生**: 利用 MIG 的自愈能力  
✅ **可追溯性**: 完整的操作记录  

### 关键要点

1. **前置条件必须满足**:
   - Ops Agent 已安装
   - 磁盘随实例删除

2. **告警配置要合理**:
   - 阈值: 85%
   - 持续时间: 5 分钟
   - 避免误报

3. **操作要谨慎**:
   - 不要同时重建多个实例
   - 等待新实例完全启动
   - 验证问题解决

4. **长期优化**:
   - 与 Image 团队协调
   - 增加磁盘容量
   - 配置日志清理

---

## 快速参考

### 常用命令

```bash
# 查看 MIG 实例列表
gcloud compute instance-groups managed list-instances MIG_NAME --zone=ZONE

# 重建单个实例
gcloud compute instance-groups managed recreate-instances MIG_NAME \
  --instances=INSTANCE_NAME --zone=ZONE

# 查看实例详情
gcloud compute instances describe INSTANCE_NAME --zone=ZONE

# 查看告警策略
gcloud alpha monitoring policies list

# 查看通知渠道
gcloud alpha monitoring channels list
```

### 重要链接

- [Cloud Monitoring 文档](https://cloud.google.com/monitoring/docs)
- [MIG 管理文档](https://cloud.google.com/compute/docs/instance-groups)
- [Ops Agent 安装](https://cloud.google.com/stackdriver/docs/solutions/agents/ops-agent)

---

**文档版本**: v1.0  
**最后更新**: 2025-11-16  
**维护团队**: SRE Team
