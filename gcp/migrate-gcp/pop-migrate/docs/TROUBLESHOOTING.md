# 故障排除指南

## 常见问题和解决方案

### 1. 权限相关问题

#### 问题：无法访问源集群
```
Error: You must be logged in to the server (Unauthorized)
```

**解决方案：**
```bash
# 重新获取集群凭据
gcloud container clusters get-credentials SOURCE_CLUSTER \
    --zone SOURCE_ZONE \
    --project SOURCE_PROJECT

# 检查当前上下文
kubectl config current-context

# 验证权限
kubectl auth can-i get pods --namespace=NAMESPACE
```

#### 问题：权限不足
```
Error: User "user@company.com" cannot get resource "deployments" in API group "apps"
```

**解决方案：**
```bash
# 检查当前用户权限
kubectl auth can-i --list --namespace=NAMESPACE

# 需要的最小权限
kubectl create clusterrolebinding migration-admin \
    --clusterrole=cluster-admin \
    --user=user@company.com
```

#### 问题：工具依赖警告
```
Warning: yq 未安装，使用 grep/awk 解析配置文件
```

**说明：**
这是正常的警告信息，不影响基本功能。工具会自动使用备用方案。

**可选优化：**
```bash
# 选项 1: 安装 yq (推荐)
brew install yq  # macOS
# 或下载二进制文件到 Linux

# 选项 2: 确保 Python3 可用
python3 --version
pip3 install PyYAML  # 如果 yaml 模块不可用

# 选项 3: 继续使用备用方案（基本功能正常）
```

### 2. 网络连接问题

#### 问题：无法连接到集群
```
Error: Unable to connect to the server: dial tcp: lookup xxx on xxx: no such host
```

**解决方案：**
```bash
# 检查网络连接
ping google.com

# 检查 gcloud 配置
gcloud config list

# 重新认证
gcloud auth login

# 检查集群状态
gcloud container clusters list --project=PROJECT_ID
```

#### 问题：超时错误
```
Error: context deadline exceeded
```

**解决方案：**
```bash
# 增加超时时间
./migrate.sh -n NAMESPACE --timeout 600

# 检查网络延迟
kubectl get nodes
```

### 3. 资源冲突问题

#### 问题：资源已存在
```
Error: deployments.apps "my-app" already exists
```

**解决方案：**
```bash
# 使用强制覆盖
./migrate.sh -n NAMESPACE --force

# 或者手动删除冲突资源
kubectl delete deployment my-app -n NAMESPACE

# 然后重新运行迁移
./migrate.sh -n NAMESPACE
```

#### 问题：Namespace 已存在
```
Error: namespaces "my-app" already exists
```

**解决方案：**
```bash
# 检查现有 namespace 内容
kubectl get all -n my-app

# 如果可以清空，删除现有 namespace
kubectl delete namespace my-app

# 等待删除完成后重新迁移
kubectl get namespace my-app
# 应该返回 "not found"

./migrate.sh -n my-app
```

### 4. 资源依赖问题

#### 问题：PVC 创建失败
```
Error: PersistentVolumeClaim "data-pvc" is invalid: spec.storageClassName: Invalid value
```

**解决方案：**
```bash
# 检查目标集群的 StorageClass
kubectl get storageclass

# 如果 StorageClass 不存在，创建或修改 PVC
kubectl get pvc data-pvc -n NAMESPACE -o yaml > pvc.yaml
# 编辑 pvc.yaml 修改 storageClassName
kubectl apply -f pvc.yaml
```

#### 问题：Secret 类型不支持
```
Error: Secret "my-secret" is invalid: type: Invalid value
```

**解决方案：**
```bash
# 检查 Secret 类型
kubectl get secret my-secret -n NAMESPACE -o yaml

# 手动创建支持的 Secret 类型
kubectl create secret generic my-secret \
    --from-literal=key=value \
    -n NAMESPACE
```

### 5. 镜像拉取问题

#### 问题：镜像拉取失败
```
Error: ErrImagePull or ImagePullBackOff
```

**解决方案：**
```bash
# 检查镜像是否存在
docker pull IMAGE_NAME

# 检查镜像仓库权限
kubectl get secret -n NAMESPACE | grep docker

# 创建镜像拉取密钥
kubectl create secret docker-registry regcred \
    --docker-server=REGISTRY_SERVER \
    --docker-username=USERNAME \
    --docker-password=PASSWORD \
    --docker-email=EMAIL \
    -n NAMESPACE

# 更新 Deployment 使用镜像拉取密钥
kubectl patch deployment DEPLOYMENT_NAME \
    -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"regcred"}]}}}}' \
    -n NAMESPACE
```

### 6. 资源配额问题

#### 问题：资源配额超限
```
Error: exceeded quota: compute-quota, requested: requests.cpu=2, used: requests.cpu=8, limited: requests.cpu=10
```

**解决方案：**
```bash
# 检查当前资源使用情况
kubectl describe quota -n NAMESPACE

# 检查节点资源
kubectl top nodes

# 增加资源配额或清理不需要的资源
kubectl delete deployment unused-app -n NAMESPACE

# 或者修改资源请求
kubectl patch deployment my-app \
    -p '{"spec":{"template":{"spec":{"containers":[{"name":"container","resources":{"requests":{"cpu":"100m"}}}]}}}}' \
    -n NAMESPACE
```

### 7. 存储相关问题

#### 问题：PV 绑定失败
```
Error: PersistentVolumeClaim is in Pending state
```

**解决方案：**
```bash
# 检查 PVC 状态
kubectl describe pvc PVC_NAME -n NAMESPACE

# 检查可用的 PV
kubectl get pv

# 检查 StorageClass
kubectl describe storageclass STORAGE_CLASS_NAME

# 如果是动态供应问题，检查存储驱动
kubectl get pods -n kube-system | grep storage
```

### 8. 网络策略问题

#### 问题：Pod 无法通信
```
Error: Connection refused or timeout
```

**解决方案：**
```bash
# 检查 NetworkPolicy
kubectl get networkpolicy -n NAMESPACE

# 临时删除 NetworkPolicy 进行测试
kubectl delete networkpolicy --all -n NAMESPACE

# 测试 Pod 间连通性
kubectl exec -it POD_NAME -n NAMESPACE -- nc -zv SERVICE_NAME PORT

# 重新创建适当的 NetworkPolicy
```

### 9. 服务发现问题

#### 问题：服务无法访问
```
Error: Service endpoints not found
```

**解决方案：**
```bash
# 检查 Service 和 Endpoints
kubectl get svc,endpoints -n NAMESPACE

# 检查 Pod 标签是否匹配 Service 选择器
kubectl get pods --show-labels -n NAMESPACE
kubectl describe svc SERVICE_NAME -n NAMESPACE

# 修复标签不匹配问题
kubectl label pod POD_NAME app=SERVICE_LABEL -n NAMESPACE
```

### 10. 配置相关问题

#### 问题：ConfigMap 或 Secret 挂载失败
```
Error: couldn't find key KEY_NAME in ConfigMap NAMESPACE/CONFIG_NAME
```

**解决方案：**
```bash
# 检查 ConfigMap 内容
kubectl describe configmap CONFIG_NAME -n NAMESPACE

# 检查 Pod 中的挂载配置
kubectl describe pod POD_NAME -n NAMESPACE

# 更新 ConfigMap
kubectl patch configmap CONFIG_NAME \
    -p '{"data":{"KEY_NAME":"VALUE"}}' \
    -n NAMESPACE

# 重启相关 Pod
kubectl rollout restart deployment DEPLOYMENT_NAME -n NAMESPACE
```

## 调试工具和技巧

### 1. 日志分析

```bash
# 查看迁移日志
tail -f logs/migration-*.log

# 过滤错误信息
grep -i error logs/migration-*.log

# 查看特定资源的日志
grep "deployments" logs/migration-*.log
```

### 2. 资源状态检查

```bash
# 检查所有资源状态
kubectl get all -n NAMESPACE

# 检查 Pod 详细信息
kubectl describe pod POD_NAME -n NAMESPACE

# 查看 Pod 日志
kubectl logs POD_NAME -n NAMESPACE

# 查看事件
kubectl get events -n NAMESPACE --sort-by='.lastTimestamp'
```

### 3. 网络调试

```bash
# 测试 DNS 解析
kubectl exec -it POD_NAME -n NAMESPACE -- nslookup SERVICE_NAME

# 测试服务连通性
kubectl exec -it POD_NAME -n NAMESPACE -- curl SERVICE_NAME:PORT

# 检查网络策略
kubectl describe networkpolicy -n NAMESPACE
```

### 4. 存储调试

```bash
# 检查存储类
kubectl get storageclass

# 检查 PV 和 PVC
kubectl get pv,pvc -n NAMESPACE

# 检查存储驱动
kubectl get pods -n kube-system | grep -E "(csi|storage)"
```

## 预防措施

### 1. 迁移前检查

```bash
# 创建预检查脚本
cat > pre-check.sh << 'EOF'
#!/bin/bash
NAMESPACE=$1

echo "检查源集群连接..."
kubectl cluster-info

echo "检查 namespace 是否存在..."
kubectl get namespace $NAMESPACE

echo "检查资源数量..."
kubectl get all -n $NAMESPACE

echo "检查存储资源..."
kubectl get pvc -n $NAMESPACE

echo "检查网络策略..."
kubectl get networkpolicy -n $NAMESPACE

echo "检查资源配额..."
kubectl describe quota -n $NAMESPACE
EOF

chmod +x pre-check.sh
./pre-check.sh NAMESPACE
```

### 2. 目标集群准备

```bash
# 检查目标集群资源
kubectl top nodes
kubectl describe nodes

# 检查存储类
kubectl get storageclass

# 检查网络插件
kubectl get pods -n kube-system | grep -E "(calico|flannel|weave)"

# 检查 RBAC 配置
kubectl get clusterroles | grep -E "(admin|edit|view)"
```

### 3. 备份策略

```bash
# 创建备份脚本
cat > backup.sh << 'EOF'
#!/bin/bash
NAMESPACE=$1
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"

mkdir -p $BACKUP_DIR

echo "备份 namespace $NAMESPACE 到 $BACKUP_DIR"
kubectl get all -n $NAMESPACE -o yaml > $BACKUP_DIR/all-resources.yaml
kubectl get pvc -n $NAMESPACE -o yaml > $BACKUP_DIR/pvcs.yaml
kubectl get secrets -n $NAMESPACE -o yaml > $BACKUP_DIR/secrets.yaml
kubectl get configmaps -n $NAMESPACE -o yaml > $BACKUP_DIR/configmaps.yaml

echo "备份完成: $BACKUP_DIR"
EOF

chmod +x backup.sh
./backup.sh NAMESPACE
```

## 恢复和回滚

### 1. 快速回滚

```bash
# 删除迁移的 namespace
kubectl delete namespace NAMESPACE

# 从备份恢复
kubectl apply -f backups/BACKUP_DIR/all-resources.yaml
```

### 2. 部分回滚

```bash
# 只回滚特定资源类型
kubectl delete deployments --all -n NAMESPACE
kubectl apply -f backups/BACKUP_DIR/deployments.yaml
```

### 3. 数据恢复

```bash
# 如果 PVC 数据丢失，从快照恢复
gcloud compute disks create recovered-disk \
    --source-snapshot=SNAPSHOT_NAME \
    --zone=ZONE

# 创建新的 PV 指向恢复的磁盘
kubectl apply -f recovered-pv.yaml
```

## 性能优化

### 1. 大规模迁移优化

```bash
# 分批处理大量资源
./migrate.sh -n large-namespace --resources deployments
./migrate.sh -n large-namespace --resources services,configmaps
./migrate.sh -n large-namespace --resources secrets,persistentvolumeclaims

# 并行处理多个 namespace
./migrate.sh -n ns1 &
./migrate.sh -n ns2 &
./migrate.sh -n ns3 &
wait
```

### 2. 网络优化

```bash
# 使用相同区域的集群
gcloud container clusters list --filter="location:asia-east1"

# 检查网络延迟
kubectl exec -it test-pod -- ping TARGET_CLUSTER_IP
```

## 监控和告警

### 1. 设置监控

```bash
# 监控迁移进度
watch kubectl get pods -n NAMESPACE

# 监控资源使用
kubectl top pods -n NAMESPACE
kubectl top nodes
```

### 2. 设置告警

```bash
# 创建告警脚本
cat > alert.sh << 'EOF'
#!/bin/bash
NAMESPACE=$1

# 检查失败的 Pod
FAILED_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Failed --no-headers | wc -l)
if [ $FAILED_PODS -gt 0 ]; then
    echo "警告: 发现 $FAILED_PODS 个失败的 Pod"
    kubectl get pods -n $NAMESPACE --field-selector=status.phase=Failed
fi

# 检查 Pending 的 Pod
PENDING_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Pending --no-headers | wc -l)
if [ $PENDING_PODS -gt 0 ]; then
    echo "警告: 发现 $PENDING_PODS 个 Pending 的 Pod"
    kubectl get pods -n $NAMESPACE --field-selector=status.phase=Pending
fi
EOF

chmod +x alert.sh
./alert.sh NAMESPACE
```

## 获取帮助

如果以上解决方案都无法解决问题：

1. **收集诊断信息：**
   ```bash
   # 生成诊断报告
   kubectl cluster-info dump > cluster-info.txt
   kubectl get events --all-namespaces > events.txt
   ```

2. **查看详细日志：**
   ```bash
   ./migrate.sh -n NAMESPACE -v > detailed.log 2>&1
   ```

3. **联系支持团队：**
   - 提供错误信息和日志
   - 描述迁移环境和步骤
   - 包含集群和资源信息

4. **社区支持：**
   - 查看项目文档和 FAQ
   - 搜索已知问题
   - 提交 Issue 或参与讨论