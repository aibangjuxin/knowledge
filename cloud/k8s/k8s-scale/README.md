# Kubernetes Resource Optimization Tool

优化 GCP Kubernetes namespace 资源使用的工具，通过识别和缩减不健康的 deployment 来释放资源。

## 核心功能

1. **资源分析** - 统计 namespace 下所有 deployment 的 CPU 和 Memory limits/requests
2. **健康检查** - 区分健康和不健康的 deployment（replicas > 0 但 ready = 0）
3. **自动缩减** - 将不健康的 deployment scale to 0，并保存原始 replicas 用于恢复
4. **配额生成** - 基于健康 deployment 生成 ResourceQuota YAML（带 buffer）
5. **详细报告** - 生成包含资源使用情况和优化建议的报告

## 使用方法

### 1. 分析模式（只查看，不修改）

```bash
./optimize_k8s_resources_v2.sh --namespace my-app
```

这会生成报告，显示：
- 总资源使用量
- 健康 vs 不健康的 deployment
- 潜在节省的资源
- 推荐的 ResourceQuota

### 2. Dry-run 模式（预览操作）

```bash
./optimize_k8s_resources_v2.sh --namespace my-app --dry-run
```

显示将要执行的操作，但不实际执行。

### 3. 应用模式（执行缩减）

```bash
./optimize_k8s_resources_v2.sh --namespace my-app --apply
```

这会：
- 将不健康的 deployment scale to 0
- 添加 annotation 保存原始 replicas
- 生成 ResourceQuota YAML 文件

### 4. 恢复模式

```bash
./optimize_k8s_resources_v2.sh --namespace my-app --restore
```

恢复之前被缩减的 deployment 到原始 replicas。

### 5. 自定义 Buffer

```bash
./optimize_k8s_resources_v2.sh --namespace my-app --apply --buffer 20
```

设置 ResourceQuota 的 buffer 为 20%（默认 10%）。

## 输出文件

所有输出文件保存在 `./k8s-optimization-reports/` 目录：

- `{namespace}_report_{timestamp}.txt` - 详细分析报告
- `{namespace}_quota_{timestamp}.yaml` - ResourceQuota 配置文件

## 工作原理

### 资源优先级

脚本按以下优先级获取资源配置：
1. `limits.cpu` / `limits.memory`（优先）
2. `requests.cpu` / `requests.memory`（如果没有 limits）
3. 0（如果都没有）

### 健康判断

Deployment 被认为是**不健康**的条件：
- `spec.replicas > 0`（期望有 pod 运行）
- `status.readyReplicas == 0`（但没有 pod ready）

这些 deployment 会被标记为缩减候选。

### ResourceQuota 计算

```
推荐配额 = 健康 deployment 总资源 × (1 + buffer%)
```

默认 buffer 为 10%，可以通过 `--buffer` 参数调整。

## 示例场景

### 场景 1: 快速释放资源

你的 namespace 有很多失败的 deployment 占用资源配额，导致新的 deployment 无法启动：

```bash
# 1. 先分析
./optimize_k8s_resources_v2.sh --namespace production

# 2. 查看报告，确认要缩减的 deployment

# 3. 应用缩减
./optimize_k8s_resources_v2.sh --namespace production --apply

# 4. 应用 ResourceQuota
kubectl apply -f k8s-optimization-reports/production_quota_*.yaml
```

### 场景 2: 临时缩减后恢复

```bash
# 缩减不健康的 deployment
./optimize_k8s_resources_v2.sh --namespace staging --apply

# 修复问题后恢复
./optimize_k8s_resources_v2.sh --namespace staging --restore
```

### 场景 3: 定期审计

```bash
# 每周运行分析，生成报告
./optimize_k8s_resources_v2.sh --namespace production > weekly_audit.txt
```

## 安全特性

1. **Annotation 追踪** - 使用 `k8s-optimizer/original-replicas` 保存原始值
2. **时间戳记录** - 记录缩减时间 `k8s-optimizer/scaled-down-at`
3. **Dry-run 支持** - 可以预览操作
4. **报告存档** - 所有操作都有详细报告

## 依赖

- `kubectl` - Kubernetes CLI
- `jq` - JSON 处理工具
- `bash` 4.0+

## 注意事项

1. **权限要求** - 需要对 namespace 有 get/list/update deployment 的权限
2. **生产环境** - 建议先在测试环境验证
3. **监控** - 应用 ResourceQuota 后，监控是否有 deployment 因配额不足而失败
4. **Buffer 调整** - 如果经常遇到配额不足，增加 buffer 百分比

## 最佳实践

### 评估最佳配额上限

1. **初始分析**
   ```bash
   ./optimize_k8s_resources_v2.sh --namespace prod
   ```
   查看健康 deployment 的实际使用量

2. **设置保守配额**（20% buffer）
   ```bash
   ./optimize_k8s_resources_v2.sh --namespace prod --apply --buffer 20
   ```

3. **监控一周**
   - 观察是否有资源不足的情况
   - 检查实际使用率

4. **调整优化**
   - 如果配额充足：降低 buffer 到 15% 或 10%
   - 如果配额紧张：增加 buffer 到 25% 或 30%

### 定期维护

```bash
# 每周一次清理
0 2 * * 1 /path/to/optimize_k8s_resources_v2.sh --namespace prod --apply
```

## 故障排查

### 问题：脚本报告没有不健康的 deployment，但资源仍然紧张

**原因**：可能有 deployment 的 pod 处于 Pending 或 CrashLoopBackOff 状态，但 replicas 设置为 0。

**解决**：检查 pod 状态：
```bash
kubectl get pods -n <namespace> --field-selector=status.phase!=Running
```

### 问题：恢复后 deployment 仍然无法启动

**原因**：可能是 ResourceQuota 限制或其他资源问题。

**解决**：
1. 检查 ResourceQuota：`kubectl describe quota -n <namespace>`
2. 检查 pod events：`kubectl describe pod <pod-name> -n <namespace>`
3. 临时增加配额或删除配额进行测试

## 版本对比

### v2 相比 v1 的改进

- ✅ 更高效的 jq 处理（单次调用）
- ✅ 彩色输出，更易读
- ✅ 详细的报告格式
- ✅ 时间戳和标签追踪
- ✅ 更好的错误处理
- ✅ 支持自定义 buffer
- ✅ 完整的使用文档
