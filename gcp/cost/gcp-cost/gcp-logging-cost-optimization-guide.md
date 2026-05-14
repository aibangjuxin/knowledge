# GCP 日志成本优化完整指南

## 概述

本指南提供了一套系统性的 GCP 日志成本优化方案，重点关注在保持测试环境和生产环境日志内容一致性的前提下，通过精细化的保留策略和过滤规则来控制成本。

## 1. 日志成本来源分析

### 1.1 成本构成
GCP Cloud Logging 的成本主要由以下部分组成：

- **注入成本 (Ingestion Cost)**: $0.50/GiB - 日志写入 Cloud Logging 时的一次性费用
- **存储成本 (Retention Cost)**: $0.01/GiB/月 - 超过默认保留期的存储费用
- **免费配额**: 每月前 50 GiB 免费

### 1.2 主要成本驱动因素

1. **审计日志 (Audit Logs)**
   - 管理员活动日志 (Admin Activity) - 强制启用，无法禁用
   - 数据访问日志 (Data Access) - 可选，是最大的成本来源
   - 系统事件日志 (System Events) - 强制启用

2. **GKE 日志**
   - 系统日志 (SYSTEM) - kubelet, containerd 等
   - 工作负载日志 (WORKLOAD) - 应用容器日志

3. **应用日志**
   - 不同严重性级别的日志量差异巨大

### 1.3 成本优化原则

**核心原则**: 阻止 1GB 无用日志注入比缩短 1GB 已注入日志的保留时间节省 50 倍成本。

优先级排序：
1. 减少注入量（排除过滤器）
2. 优化保留策略
3. 合理使用归档

## 2. 日志生命周期与保留策略

### 2.1 分环境保留策略设计

| 环境类型 | 保留天数 | 日志级别 | 审计日志策略 | 预期节省 |
|----------|----------|----------|--------------|----------|
| 生产环境 | 90-365天 | INFO+ | 完整保留 | 基准 |
| 预生产环境 | 30-60天 | INFO+ | 选择性保留 | 30-40% |
| 测试环境 | 7-14天 | WARNING+ | 最小保留 | 60-70% |
| 开发环境 | 3-7天 | ERROR+ | 禁用非关键 | 70-80% |

### 2.2 自定义日志桶策略

```bash
# 创建不同环境的自定义日志桶
# 开发环境 - 7天保留
gcloud logging buckets create dev-logs-bucket \
  --location=global \
  --retention-days=7 \
  --description="Development environment logs with 7-day retention"

# 测试环境 - 14天保留
gcloud logging buckets create test-logs-bucket \
  --location=global \
  --retention-days=14 \
  --description="Test environment logs with 14-day retention"

# 生产环境 - 90天保留
gcloud logging buckets create prod-logs-bucket \
  --location=global \
  --retention-days=90 \
  --description="Production environment logs with 90-day retention"
```

### 2.3 日志路由配置

```bash
# 创建环境特定的日志接收器
# 开发环境接收器
gcloud logging sinks create dev-env-sink \
  logging.googleapis.com/projects/PROJECT_ID/locations/global/buckets/dev-logs-bucket \
  --log-filter='resource.labels.project_id="dev-project-id"'

# 测试环境接收器
gcloud logging sinks create test-env-sink \
  logging.googleapis.com/projects/PROJECT_ID/locations/global/buckets/test-logs-bucket \
  --log-filter='resource.labels.project_id="test-project-id"'
```

## 3. GKE 排除过滤器实用配方

### 3.1 健康检查日志过滤

```sql
-- 过滤器名称: exclude-k8s-health-checks
-- 描述: 排除 Kubernetes 健康检查产生的日志
resource.type="k8s_container" AND httpRequest.userAgent =~ "kube-probe"
```

### 3.2 低严重性日志过滤（非生产环境）

```sql
-- 过滤器名称: exclude-low-severity-logs
-- 描述: 在非生产环境中排除 WARNING 以下级别的日志
resource.type="k8s_container" AND severity < WARNING AND resource.labels.project_id!="prod-project-id"
```

### 3.3 特定容器日志过滤

```sql
-- 过滤器名称: exclude-istio-proxy
-- 描述: 排除 Istio 代理容器的日志
resource.type="k8s_container" AND resource.labels.container_name="istio-proxy"
```

### 3.4 采样过滤器

```sql
-- 过滤器名称: sample-high-traffic-logs
-- 描述: 对高频日志进行采样，只保留 5% 的样本
resource.type="k8s_container" AND jsonPayload.message =~ "User login successful" AND sample(insertId, 0.05)
```

### 3.5 系统组件日志过滤

```sql
-- 过滤器名称: exclude-system-noise
-- 描述: 排除系统组件的噪音日志
(resource.type="k8s_container" AND resource.labels.namespace_name="kube-system" AND severity < ERROR) OR
(resource.type="gce_instance" AND jsonPayload.message =~ ".*systemd.*started.*")
```

## 4. 审计日志优化策略

### 4.1 数据访问日志控制

```bash
# 检查当前审计日志配置
gcloud logging read "protoPayload.serviceName:*.googleapis.com" --limit=10 --format="table(protoPayload.serviceName, protoPayload.methodName)"

# 在 IAM 策略中禁用非必要的数据访问日志
# 导航到 GCP Console > IAM & Admin > Audit Logs
# 取消勾选非生产环境中不需要的服务的 Data Read/Write 日志
```

### 4.2 服务特定的审计日志过滤

```sql
-- 过滤器名称: exclude-compute-list-operations
-- 描述: 排除 Compute Engine 的列表操作审计日志
protoPayload.serviceName="compute.googleapis.com" AND protoPayload.methodName =~ ".*list.*"
```

## 5. 归档策略

### 5.1 冷存储归档

```bash
# 创建 GCS 存储桶用于长期归档
gsutil mb -c ARCHIVE -l us-central1 gs://your-project-log-archive

# 创建归档接收器
gcloud logging sinks create archive-to-gcs \
  storage.googleapis.com/your-project-log-archive \
  --log-filter='severity>=INFO'

# 设置生命周期策略
cat > lifecycle.json << EOF
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "ARCHIVE"},
      "condition": {"age": 30}
    }
  ]
}
EOF

gsutil lifecycle set lifecycle.json gs://your-project-log-archive
```

## 6. 监控和告警

### 6.1 成本监控指标

```bash
# 创建基于日志的指标来监控日志量
gcloud logging metrics create log_volume_by_project \
  --description="Monitor log volume by project for cost control" \
  --log-filter='resource.type="k8s_container"' \
  --value-extractor='EXTRACT(resource.labels.project_id)'
```

### 6.2 成本异常告警

```bash
# 创建告警策略
gcloud alpha monitoring policies create --policy-from-file=log-cost-alert-policy.yaml
```

## 7. 实施检查清单

### 7.1 项目级检查
- [ ] 审查并禁用非必要的数据访问审计日志
- [ ] 为不同环境创建自定义日志桶
- [ ] 配置环境特定的保留策略
- [ ] 实施日志排除过滤器

### 7.2 GKE 集群级检查
- [ ] 配置集群日志收集范围（SYSTEM vs WORKLOAD）
- [ ] 实施容器级日志过滤
- [ ] 优化应用日志级别配置
- [ ] 配置日志轮转策略

### 7.3 监控和维护
- [ ] 设置成本监控指标
- [ ] 配置成本异常告警
- [ ] 建立定期审查流程
- [ ] 文档化所有配置变更

## 8. 成本估算

### 8.1 优化前后对比

假设一个中等规模的项目每月产生 500 GiB 日志：

**优化前成本**:
- 注入成本: 500 GiB × $0.50 = $250
- 存储成本: 500 GiB × $0.01 × 12个月 = $60
- 总计: $310/月

**优化后成本**（应用本指南策略）:
- 通过过滤减少 60% 注入: 200 GiB × $0.50 = $100
- 缩短保留期减少存储成本: 200 GiB × $0.01 × 3个月 = $6
- 总计: $106/月

**节省**: $204/月 (66% 成本削减)

## 9. 最佳实践总结

1. **优先级**: 减少注入 > 缩短保留 > 优化归档
2. **环境差异化**: 非生产环境采用更激进的成本控制策略
3. **渐进式实施**: 从开发环境开始，逐步推广到生产环境
4. **持续监控**: 建立成本监控和告警机制
5. **定期审查**: 每季度审查和调整策略

## 10. 故障排除

### 10.1 常见问题
- 日志突然消失：检查排除过滤器配置
- 成本未如预期下降：验证过滤器是否生效
- 合规性问题：确保关键审计日志未被过度过滤

### 10.2 回滚策略
- 保留原始配置的备份
- 分阶段实施，便于快速回滚
- 监控关键业务指标，确保优化不影响运营