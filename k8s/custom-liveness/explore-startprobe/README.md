# Kubernetes 探针配置最佳实践

本目录包含 Kubernetes Pod 启动探针（Probe）配置的完整指南和工具。

## 📁 文件说明

### 文档
- **`probe-best-practices.md`** - 完整的探针配置最佳实践指南
  - 核心概念和原理
  - 参数计算公式
  - 配置模板
  - 可视化流程图
  - 详细时序分析
  - 故障排查指南

### 工具
- **`pod_measure_startup_fixed.sh`** - Pod 启动时间测量脚本
  - 自动测量 Pod 启动耗时
  - 分析当前探针配置
  - 提供优化建议

## 🚀 快速开始

### 1. 测量 Pod 启动时间

```bash
# 基本用法
./pod_measure_startup_fixed.sh -n <namespace> <pod-name>

# 示例
./pod_measure_startup_fixed.sh -n production my-api-pod-abc123
```

### 2. 查看测量结果

脚本会输出：
- Pod 创建时间和容器启动时间
- 当前探针配置
- 实际启动耗时
- 配置分析（是否足够）
- 优化建议

### 3. 应用推荐配置

根据脚本输出的建议，更新你的 Deployment YAML：

```yaml
# 推荐配置示例
startupProbe:
  httpGet:
    path: /health
    port: 8080
    scheme: HTTPS
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 12  # 根据实际启动时间调整
  successThreshold: 1

readinessProbe:
  httpGet:
    path: /health
    port: 8080
    scheme: HTTPS
  initialDelaySeconds: 0
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /health
    port: 8080
    scheme: HTTPS
  initialDelaySeconds: 0
  periodSeconds: 20
  timeoutSeconds: 5
  failureThreshold: 3
```

## 📊 测量最佳实践

### 获取 P99 启动时间

为了获得准确的配置，建议多次测量：

```bash
# 1. 删除 Pod 让其重建
kubectl delete pod <pod-name> -n <namespace>

# 2. 等待新 Pod 创建
kubectl get pods -n <namespace> -w

# 3. 测量新 Pod
./pod_measure_startup_fixed.sh -n <namespace> <new-pod-name>

# 4. 重复 3-5 次
```

记录所有测量结果，使用最慢的那次（P99）作为配置依据。

### 示例测量结果

```
测量 1: 15 秒
测量 2: 25 秒
测量 3: 22 秒
测量 4: 18 秒
测量 5: 40 秒 ← P99，使用这个值
```

## 🔧 脚本依赖

脚本需要以下工具：
- `kubectl` - Kubernetes 命令行工具
- `jq` - JSON 处理工具
- `bc` - 计算器（用于数学计算）

### 安装依赖

**macOS:**
```bash
brew install kubectl jq bc
```

**Linux (Ubuntu/Debian):**
```bash
apt-get install kubectl jq bc
```

**Linux (RHEL/CentOS):**
```bash
yum install kubectl jq bc
```

## 📖 详细文档

完整的探针配置指南请查看：[probe-best-practices.md](./probe-best-practices.md)

文档包含：
- ✅ 核心概念和原理
- ✅ 参数计算公式
- ✅ 配置模板（复制即用）
- ✅ 可视化流程图
- ✅ 详细时序分析
- ✅ 故障排查决策树
- ✅ 常见问题解答
- ✅ 快速参考表

## 🎯 核心要点

### 黄金法则

1. **启动窗口 = periodSeconds × failureThreshold**
   - 例如: 10s × 12 = 120秒启动保护

2. **periodSeconds 从本次探测【开始】到下次探测【开始】**
   - 不是从本次探测结束开始计时

3. **timeoutSeconds 是对 /health 接口响应速度的要求**
   - 不是给应用启动的时间

### 快速配置决策

| 应用启动时间 | failureThreshold | 总窗口 |
|------------|-----------------|--------|
| < 60秒 | 12 | 120秒 |
| 60-120秒 | 12 | 120秒 ⚠️ |
| 120-180秒 | 18 | 180秒 |
| 180-300秒 | 30 | 300秒 |

## 🐛 故障排查

### Pod 无法启动？

1. **检查 Pod 状态**
   ```bash
   kubectl get pod <pod-name> -n <namespace>
   kubectl describe pod <pod-name> -n <namespace>
   ```

2. **查看探针失败原因**
   ```bash
   kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name>
   ```

3. **常见问题**
   - `Init:0/1` → Init Container 问题，与探针无关
   - `CrashLoopBackOff` + StartupProbe failed → 增加 failureThreshold
   - `CrashLoopBackOff` + 探针超时 → 优化 /health 接口
   - Pod Running 但无流量 → ReadinessProbe 失败

## 📞 支持

如有问题或建议，请：
1. 查看完整文档：[probe-best-practices.md](./probe-best-practices.md)
2. 查看 FAQ 部分
3. 提交 Issue 或 PR

---

**版本**: v2.0  
**最后更新**: 2024-12  
**维护者**: GKE Platform Team
