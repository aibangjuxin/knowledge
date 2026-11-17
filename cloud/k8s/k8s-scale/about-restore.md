./optimize_k8s_resources_v2.sh --namespace my-app --restore

Restore 的数据来源
--restore 是从 Kubernetes deployment 的 annotations（注解） 中获取数据来恢复的，而不是从本地文件。

工作流程
1. 应用缩减时（--apply）

./optimize_k8s_resources_v2.sh --namespace my-app --apply
脚本会在缩减 deployment 之前，先给它添加 annotations：

kubectl annotate deploy <deployment-name> -n my-app \
    "k8s-optimizer/original-replicas=3" \
    "k8s-optimizer/scaled-down-at=2025-12-05T10:30:00Z" \
    --overwrite

kubectl scale deploy <deployment-name> -n my-app --replicas=0
这样，原始的 replicas 数量（比如 3）就被保存在 deployment 的 metadata 中了。

2. 恢复时（--restore）

脚本查询 namespace 中所有带有 k8s-optimizer/original-replicas annotation 的 deployment：

kubectl get deploy -n my-app -o json | \
    jq -r '.items[] | 
    select(.metadata.annotations["k8s-optimizer/original-replicas"] != null) | 
    "\(.metadata.name) \(.metadata.annotations["k8s-optimizer/original-replicas"])"'
然后恢复每个 deployment 到原始 replicas，并删除 annotation：

kubectl scale deploy <deployment-name> -n my-app --replicas=3
kubectl annotate deploy <deployment-name> -n my-app k8s-optimizer/original-replicas-
查看保存的数据
你可以手动查看哪些 deployment 被标记了：

# 查看所有被缩减的 deployment
kubectl get deploy -n my-app -o json | \
    jq -r '.items[] | 
    select(.metadata.annotations["k8s-optimizer/original-replicas"] != null) | 
    "\(.metadata.name): replicas=\(.metadata.annotations["k8s-optimizer/original-replicas"]), scaled-down-at=\(.metadata.annotations["k8s-optimizer/scaled-down-at"])"'

# 或者查看单个 deployment 的 annotations
kubectl get deploy <deployment-name> -n my-app -o jsonpath='{.metadata.annotations}'
优点
这种方式的好处是：

✅ 无需本地文件 - 数据存储在 Kubernetes 中，不依赖本地文件系统
✅ 集群级别 - 任何有权限的人都可以在任何机器上执行恢复
✅ 持久化 - 即使脚本被删除，annotation 仍然保留在集群中
✅ 可追溯 - 可以看到什么时候被缩减的
注意事项
⚠️ 如果 deployment 被删除后重建，annotation 会丢失，无法恢复原始 replicas。

⚠️ 如果手动修改了 annotation，恢复时会使用修改后的值。

需要我创建一个辅助脚本来查看当前有哪些 deployment 可以被恢复吗？

# add 添加 annotations Risk
添加 annotations 总体来说是相对安全的，但确实有一些需要注意的风险和最佳实践。

风险评估
✅ 低风险（一般情况）
不触发重启 - 添加/修改 annotations 到 deployment 的 metadata 不会触发 pod 重启
不影响运行 - annotations 只是元数据，不影响 deployment 的实际运行
可以删除 - 随时可以删除 annotation，没有副作用
⚠️ 潜在风险
1. 与其他工具冲突
如果你的集群中有其他自动化工具（如 GitOps、Helm、Terraform）管理 deployment：

# 场景：使用 ArgoCD/Flux 等 GitOps 工具
# 风险：GitOps 可能检测到 drift，尝试移除你添加的 annotation
解决方案：

使用特定的 annotation 前缀（如 k8s-optimizer/）
在 GitOps 工具中配置忽略这些 annotation
# ArgoCD 示例
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /metadata/annotations/k8s-optimizer~1original-replicas
    - /metadata/annotations/k8s-optimizer~1scaled-down-at
2. Annotation 大小限制
Kubernetes 对 annotations 有大小限制：

单个 annotation：最大 256KB
所有 annotations 总和：最大 256KB
我们的 annotation 很小（几十字节），不会有问题。

3. 权限问题
# 如果没有 update deployment 权限，会失败
Error from server (Forbidden): deployments.apps "my-app" is forbidden: 
User "user@example.com" cannot update resource "deployments" in API group "apps"
4. 覆盖现有 annotation
使用 --overwrite 会覆盖同名的 annotation：

# 如果已经存在 k8s-optimizer/original-replicas=5
# 执行后会变成 k8s-optimizer/original-replicas=3
kubectl annotate deploy my-app k8s-optimizer/original-replicas=3 --overwrite
最佳实践建议
1. 添加保护检查
我可以改进脚本，在添加 annotation 前先检查是否已存在：

# 检查是否已经有 annotation
EXISTING=$(kubectl get deploy "$name" -n "$NAMESPACE" \
    -o jsonpath='{.metadata.annotations.k8s-optimizer/original-replicas}' 2>/dev/null)

if [[ -n "$EXISTING" ]]; then
    warn "Deployment $name already has annotation (original-replicas=$EXISTING), skipping..."
    continue
fi
2. 使用命名空间前缀
当前使用的 k8s-optimizer/ 前缀是好的做法，避免与其他工具冲突。

3. 添加更多元数据
可以添加更多追踪信息：

kubectl annotate deploy "$name" -n "$NAMESPACE" \
    "k8s-optimizer/original-replicas=$replicas" \
    "k8s-optimizer/scaled-down-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "k8s-optimizer/scaled-down-by=$(whoami)" \
    "k8s-optimizer/reason=unhealthy-pods" \
    --overwrite
4. 备份到本地（双保险）
除了 annotation，也可以保存到本地文件作为备份：

# 在缩减时同时保存到本地
echo "$name|$replicas|$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> \
    "$OUTPUT_DIR/${NAMESPACE}_backup_${TIMESTAMP}.txt"
改进建议
我可以为你创建一个更安全的版本，包含：

检查现有 annotation - 避免覆盖
本地备份 - 双重保险
审计日志 - 记录所有操作
冲突检测 - 检测 GitOps 工具
需要我实现这些改进吗？

实际风险总结
对于你的使用场景（GCP GKE，临时缩减不健康的 deployment）：

✅ 风险很低 - annotation 是标准的 Kubernetes 功能
✅ 可恢复 - 即使出问题，可以手动删除 annotation
✅ 不影响运行 - 不会导致服务中断
唯一需要注意的：如果你使用 GitOps（ArgoCD/Flux），需要配置忽略这些 annotation。








