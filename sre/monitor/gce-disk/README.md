# GCE Squid 代理磁盘监控工具集

本目录包含用于监控和管理 GCE Squid 代理实例磁盘使用率的文档和脚本。

## 📁 文件说明

### 文档

- **`gce-disk-analyze.md`** - 完整的监控实施方案文档
  - 监控配置步骤
  - 告警响应流程
  - 手动处理指南
  - 常见问题解决

- **`GCE-instance-disk.md`** - 原始需求和多方案对比
  - ChatGPT 方案
  - Claude 方案
  - Gemini 方案

- **`proxy-monitor.md`** - 代理服务监控相关文档

### 脚本

- **`recreate-squid-instance.sh`** - 单实例重建脚本
  - 快速重建单个问题实例
  - 交互式确认
  - 实时状态监控

- **`rolling-recreate-instances.sh`** - 滚动重建脚本
  - 批量重建多个实例
  - 避免服务中断
  - 支持 dry-run 模式

---

## 🚀 快速开始

### 1. 配置监控告警

按照 `gce-disk-analyze.md` 中的步骤配置 Cloud Monitoring 告警：

```bash
# 创建告警策略
gcloud alpha monitoring policies create \
  --notification-channels=YOUR_CHANNEL_ID \
  --display-name="Squid Disk Alert (85%)" \
  --condition-threshold-value=85
```

### 2. 准备脚本

```bash
# 下载脚本
cd monitor/gce-disk

# 添加执行权限
chmod +x recreate-squid-instance.sh
chmod +x rolling-recreate-instances.sh

# 配置环境变量（可选）
export PROJECT_ID="your-project-id"
export MIG_NAME="squid-proxy-mig"
export ZONE="us-central1-a"
```

### 3. 响应告警

当收到磁盘告警时：

**方式 A: 重建单个实例**
```bash
./recreate-squid-instance.sh squid-proxy-mig-abcd
```

**方式 B: 批量滚动重建**
```bash
./rolling-recreate-instances.sh \
  --instances instance-1,instance-2,instance-3 \
  --batch-size 1 \
  --wait-time 300
```

---

## 📖 使用场景

### 场景 1: 单个实例磁盘告警

**问题**: 收到告警，实例 `squid-proxy-mig-abcd` 磁盘使用率 87%

**解决方案**:
```bash
./recreate-squid-instance.sh squid-proxy-mig-abcd
```

**预期结果**:
- 旧实例被删除（磁盘一并删除）
- 新实例创建（全新磁盘）
- 服务中断时间: 3-5 分钟

---

### 场景 2: 多个实例同时告警

**问题**: 3 个实例同时磁盘使用率超过 85%

**解决方案**:
```bash
./rolling-recreate-instances.sh \
  --instances squid-proxy-mig-abcd,squid-proxy-mig-efgh,squid-proxy-mig-ijkl \
  --batch-size 1 \
  --wait-time 300
```

**执行流程**:
1. 重建 instance-abcd → 等待 5 分钟
2. 重建 instance-efgh → 等待 5 分钟
3. 重建 instance-ijkl → 完成

**预期结果**:
- 每次只重建一个实例
- 服务持续可用
- 总耗时: ~20 分钟

---

### 场景 3: 定期维护（重建所有实例）

**问题**: 定期清理所有实例磁盘，预防性维护

**解决方案**:
```bash
# 先模拟运行
./rolling-recreate-instances.sh --all --dry-run

# 确认无误后执行
./rolling-recreate-instances.sh \
  --all \
  --batch-size 2 \
  --wait-time 600
```

**执行流程**:
- 每批重建 2 个实例
- 批次间隔 10 分钟
- 自动等待 MIG 稳定

---

## 🛠️ 脚本详细说明

### recreate-squid-instance.sh

**用途**: 快速重建单个实例

**参数**:
```bash
./recreate-squid-instance.sh <instance-name>
```

**示例**:
```bash
./recreate-squid-instance.sh squid-proxy-mig-abcd
```

**特点**:
- ✅ 简单直接
- ✅ 交互式确认
- ✅ 实时监控
- ⚠️ 会导致短暂服务中断

---

### rolling-recreate-instances.sh

**用途**: 批量滚动重建实例，避免服务中断

**完整参数**:
```bash
./rolling-recreate-instances.sh [选项]

选项:
  -p, --project PROJECT_ID        GCP 项目 ID
  -m, --mig MIG_NAME              MIG 名称
  -z, --zone ZONE                 Zone 名称
  -b, --batch-size SIZE           每批次重建实例数量 (默认: 1)
  -w, --wait-time SECONDS         批次间等待时间/秒 (默认: 300)
  -i, --instances INSTANCE_LIST   指定要重建的实例列表（逗号分隔）
  -a, --all                       重建所有实例
  --dry-run                       模拟运行，不实际执行
  -h, --help                      显示帮助信息
```

**示例 1: 重建指定实例**
```bash
./rolling-recreate-instances.sh \
  -p your-project-id \
  -m squid-proxy-mig \
  -z us-central1-a \
  -i instance-1,instance-2,instance-3
```

**示例 2: 重建所有实例（每批 2 个）**
```bash
./rolling-recreate-instances.sh \
  --all \
  --batch-size 2 \
  --wait-time 600
```

**示例 3: 模拟运行**
```bash
./rolling-recreate-instances.sh --all --dry-run
```

**特点**:
- ✅ 分批次处理
- ✅ 自动等待 MIG 稳定
- ✅ 支持 dry-run
- ✅ 彩色日志输出
- ✅ 错误处理和重试
- ✅ 最小化服务中断

---

## ⚙️ 配置说明

### 方式 1: 修改脚本内的配置

编辑脚本文件，修改配置区域：

```bash
# ============================================
# 配置区域
# ============================================
PROJECT_ID="${PROJECT_ID:-your-project-id}"
MIG_NAME="${MIG_NAME:-squid-proxy-mig}"
ZONE="${ZONE:-us-central1-a}"
```

### 方式 2: 使用环境变量

```bash
export PROJECT_ID="your-project-id"
export MIG_NAME="squid-proxy-mig"
export ZONE="us-central1-a"

./rolling-recreate-instances.sh --all
```

### 方式 3: 使用命令行参数

```bash
./rolling-recreate-instances.sh \
  --project your-project-id \
  --mig squid-proxy-mig \
  --zone us-central1-a \
  --all
```

---

## 📊 监控和日志

### 实时监控 MIG 状态

```bash
# 监控实例列表
watch -n 10 'gcloud compute instance-groups managed list-instances squid-proxy-mig --zone=us-central1-a'

# 监控 MIG 状态
gcloud compute instance-groups managed describe squid-proxy-mig \
  --zone=us-central1-a \
  --format="value(status.isStable,currentActions)"
```

### 保存执行日志

```bash
./rolling-recreate-instances.sh --all 2>&1 | tee rolling-recreate-$(date +%Y%m%d-%H%M%S).log
```

### 查看磁盘使用率

通过 Cloud Monitoring Metrics Explorer:
```
Resource: VM Instance
Metric: agent.googleapis.com/disk/percent_used
Filter: resource.labels.instance_group = "squid-proxy-mig"
```

---

## ⚠️ 注意事项

### 前置条件

1. **Ops Agent 已安装**
   - 实例必须安装 Ops Agent 才能上报磁盘指标
   - 验证: 在 Metrics Explorer 中查看是否有数据

2. **磁盘删除策略**
   - 实例模板中的磁盘必须设置为"随实例删除"
   - 否则重建后会挂载旧磁盘，问题无法解决

3. **必要权限**
   - `compute.instanceGroupManagers.update`
   - `compute.instances.delete`
   - `compute.instances.create`

4. **必要工具**
   - `gcloud` CLI
   - `jq` (用于 JSON 解析)

### 最佳实践

1. **首次使用先 dry-run**
   ```bash
   ./rolling-recreate-instances.sh --all --dry-run
   ```

2. **小批次开始**
   - 生产环境建议 `--batch-size 1`
   - 确保服务最大可用性

3. **合理设置等待时间**
   - 默认 5 分钟通常足够
   - 实例启动慢可增加到 10 分钟

4. **避免高峰期操作**
   - 选择业务低峰期执行
   - 提前通知相关团队

5. **监控服务状态**
   - 在另一个终端监控服务健康状态
   - 如发现异常立即中断脚本

### 风险提示

⚠️ **不要同时重建所有实例**
- 会导致服务完全中断
- 使用 rolling 脚本分批处理

⚠️ **确认磁盘删除策略**
- 如果磁盘被保留，重建无效
- 必须在实例模板中确认配置

⚠️ **注意服务依赖**
- 如果有负载均衡，确认健康检查配置
- 确保新实例能正常加入服务

---

## 🔧 故障排查

### 问题 1: 脚本提示缺少命令

**错误信息**:
```
[ERROR] 缺少必要的命令: jq
```

**解决方法**:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

---

### 问题 2: 权限不足

**错误信息**:
```
ERROR: (gcloud.compute.instance-groups.managed.recreate-instances) Permission denied
```

**解决方法**:
1. 联系 GCP 项目管理员
2. 申请以下 IAM 角色:
   - `roles/compute.instanceAdmin.v1`
   - `roles/compute.instanceGroupManager`

---

### 问题 3: 实例重建后告警仍存在

**可能原因**:
- 磁盘未随实例删除
- 新实例挂载了旧磁盘

**解决方法**:
```bash
# 检查实例模板的磁盘配置
gcloud compute instance-templates describe TEMPLATE_NAME \
  --format="value(properties.disks[].autoDelete)"

# 应该返回 True
```

---

### 问题 4: MIG 一直不稳定

**可能原因**:
- 健康检查配置问题
- 实例启动失败

**解决方法**:
```bash
# 查看 MIG 状态详情
gcloud compute instance-groups managed describe squid-proxy-mig \
  --zone=us-central1-a

# 查看实例启动日志
gcloud compute instances get-serial-port-output INSTANCE_NAME \
  --zone=us-central1-a
```

---

## 📚 相关文档

- [Cloud Monitoring 文档](https://cloud.google.com/monitoring/docs)
- [MIG 管理文档](https://cloud.google.com/compute/docs/instance-groups)
- [Ops Agent 安装](https://cloud.google.com/stackdriver/docs/solutions/agents/ops-agent)
- [gcloud CLI 参考](https://cloud.google.com/sdk/gcloud/reference)

---

## 🤝 贡献

如有问题或建议，请联系 SRE 团队。

---

**文档版本**: v1.0  
**最后更新**: 2025-11-16  
**维护团队**: SRE Team
