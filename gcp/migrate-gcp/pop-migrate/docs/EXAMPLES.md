# 使用示例

本文档提供了各种场景下的具体使用示例。

## 基础示例

### 1. 简单的单 Namespace 迁移

```bash
# 迁移一个简单的应用 namespace
./migrate.sh -n my-web-app

# 输出示例：
# [INFO] 开始 GKE Namespace 迁移
# [INFO] 连接到源集群...
# [INFO] 导出 namespace my-web-app 的资源...
# [INFO] 成功导出 3 个 deployments 资源
# [INFO] 成功导出 2 个 services 资源
# [INFO] 成功导出 5 个 configmaps 资源
# [INFO] 连接到目标集群...
# [INFO] 创建 namespace: my-web-app
# [INFO] 导入 deployments 资源...
# [INFO] 导入完成: 10/10 个资源类型成功
```

### 2. 干运行模式检查

```bash
# 在实际迁移前先检查
./migrate.sh -n my-web-app --dry-run

# 输出示例：
# [INFO] 运行模式: 干运行 (不会实际执行迁移)
# [INFO] 导出 namespace my-web-app 的资源...
# [INFO] 干运行模式: 跳过实际导入
# [INFO] 验证完成
```

## 高级示例

### 3. 选择性资源迁移

```bash
# 只迁移核心工作负载，不包括配置
./migrate.sh -n my-app --resources deployments,services,ingresses

# 排除敏感资源
./migrate.sh -n my-app --exclude secrets,persistentvolumeclaims
```

### 4. 批量迁移多个 Namespace

```bash
# 迁移多个相关的 namespace
./migrate.sh -n frontend,backend,database

# 或者使用循环批量处理
for ns in app1 app2 app3; do
    echo "迁移 namespace: $ns"
    ./migrate.sh -n $ns
    if [ $? -eq 0 ]; then
        echo "✅ $ns 迁移成功"
    else
        echo "❌ $ns 迁移失败"
    fi
done
```

### 5. 大型应用迁移

```bash
# 对于包含大量资源的应用，分阶段迁移
echo "阶段 1: 迁移基础配置"
./migrate.sh -n large-app --resources configmaps,secrets --timeout 600

echo "阶段 2: 迁移存储资源"
./migrate.sh -n large-app --resources persistentvolumeclaims --timeout 900

echo "阶段 3: 迁移工作负载"
./migrate.sh -n large-app --resources deployments,statefulsets,daemonsets --timeout 1200

echo "阶段 4: 迁移网络资源"
./migrate.sh -n large-app --resources services,ingresses,networkpolicies --timeout 600

echo "阶段 5: 迁移策略资源"
./migrate.sh -n large-app --resources horizontalpodautoscalers,poddisruptionbudgets --timeout 300
```

## 特殊场景示例

### 6. 跨区域迁移

```bash
# 配置文件示例 (config/config.yaml)
cat > config/config.yaml << 'EOF'
source:
  project: "source-project-us"
  cluster: "source-cluster"
  zone: "us-central1-a"

target:
  project: "target-project-asia"
  cluster: "target-cluster"
  zone: "asia-east1-a"

migration:
  backup_enabled: true
  timeout: 600
EOF

# 执行跨区域迁移
./migrate.sh -n global-app
```

### 7. 开发环境到生产环境迁移

```bash
# 开发到生产的配置
cat > config/dev-to-prod.yaml << 'EOF'
source:
  project: "dev-project"
  cluster: "dev-cluster"
  zone: "us-central1-a"

target:
  project: "prod-project"
  cluster: "prod-cluster"
  zone: "us-central1-a"

migration:
  backup_enabled: true
  skip_existing: false
  force_overwrite: false
  timeout: 300
EOF

# 使用自定义配置文件
cp config/dev-to-prod.yaml config/config.yaml
./migrate.sh -n my-app --force
```

### 8. 灾难恢复场景

```bash
# 紧急迁移脚本
cat > emergency-migrate.sh << 'EOF'
#!/bin/bash

NAMESPACES="critical-app1 critical-app2 payment-service user-service"
FAILED_NS=""

echo "🚨 开始紧急迁移..."

for ns in $NAMESPACES; do
    echo "迁移关键服务: $ns"
    
    # 跳过备份以加快速度，强制覆盖
    if ./migrate.sh -n $ns --no-backup --force --timeout 900; then
        echo "✅ $ns 迁移成功"
    else
        echo "❌ $ns 迁移失败"
        FAILED_NS="$FAILED_NS $ns"
    fi
done

if [ -n "$FAILED_NS" ]; then
    echo "⚠️  以下服务迁移失败，需要手动处理: $FAILED_NS"
    exit 1
else
    echo "🎉 所有关键服务迁移完成"
fi
EOF

chmod +x emergency-migrate.sh
./emergency-migrate.sh
```

## 自动化集成示例

### 9. CI/CD 流水线集成

```yaml
# .github/workflows/migrate.yml
name: Namespace Migration

on:
  workflow_dispatch:
    inputs:
      namespace:
        description: 'Namespace to migrate'
        required: true
      dry_run:
        description: 'Dry run mode'
        type: boolean
        default: true

jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup gcloud
      uses: google-github-actions/setup-gcloud@v1
      with:
        service_account_key: ${{ secrets.GCP_SA_KEY }}
        project_id: ${{ secrets.GCP_PROJECT_ID }}
    
    - name: Get GKE credentials
      run: |
        gcloud container clusters get-credentials source-cluster --zone us-central1-a --project source-project
        gcloud container clusters get-credentials target-cluster --zone us-central1-a --project target-project
    
    - name: Run migration
      run: |
        cd pop-migrate
        if [ "${{ github.event.inputs.dry_run }}" = "true" ]; then
          ./migrate.sh -n ${{ github.event.inputs.namespace }} --dry-run
        else
          ./migrate.sh -n ${{ github.event.inputs.namespace }}
        fi
    
    - name: Upload logs
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: migration-logs
        path: pop-migrate/logs/
```

### 10. Terraform 集成

```hcl
# terraform/migration.tf
resource "null_resource" "namespace_migration" {
  for_each = var.namespaces_to_migrate

  triggers = {
    namespace = each.value
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.module}/../pop-migrate
      ./migrate.sh -n ${each.value}
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Namespace ${each.value} migration cleanup"
      # 添加清理逻辑
    EOT
  }
}

variable "namespaces_to_migrate" {
  description = "List of namespaces to migrate"
  type        = set(string)
  default     = ["app1", "app2", "app3"]
}
```

## 监控和告警示例

### 11. 迁移状态监控

```bash
# 创建监控脚本
cat > monitor-migration.sh << 'EOF'
#!/bin/bash

NAMESPACE=$1
CHECK_INTERVAL=30
MAX_WAIT=1800  # 30 minutes

echo "监控 namespace $NAMESPACE 的迁移状态..."

start_time=$(date +%s)

while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [ $elapsed -gt $MAX_WAIT ]; then
        echo "❌ 监控超时 (${MAX_WAIT}s)"
        exit 1
    fi
    
    # 检查 Pod 状态
    running_pods=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Running --no-headers | wc -l)
    total_pods=$(kubectl get pods -n $NAMESPACE --no-headers | wc -l)
    
    # 检查 Deployment 状态
    ready_deployments=$(kubectl get deployments -n $NAMESPACE -o jsonpath='{.items[?(@.status.readyReplicas==@.status.replicas)].metadata.name}' | wc -w)
    total_deployments=$(kubectl get deployments -n $NAMESPACE --no-headers | wc -l)
    
    echo "[$(date '+%H:%M:%S')] Pods: $running_pods/$total_pods Running, Deployments: $ready_deployments/$total_deployments Ready"
    
    # 检查是否全部就绪
    if [ $running_pods -eq $total_pods ] && [ $ready_deployments -eq $total_deployments ] && [ $total_pods -gt 0 ]; then
        echo "✅ 迁移完成，所有资源就绪"
        break
    fi
    
    sleep $CHECK_INTERVAL
done
EOF

chmod +x monitor-migration.sh

# 使用方法
./migrate.sh -n my-app &
./monitor-migration.sh my-app
```

### 12. Slack 通知集成

```bash
# 创建带通知的迁移脚本
cat > migrate-with-notification.sh << 'EOF'
#!/bin/bash

NAMESPACE=$1
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

send_slack_message() {
    local message=$1
    local color=$2
    
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\"}]}" \
        $SLACK_WEBHOOK
}

echo "开始迁移 namespace: $NAMESPACE"
send_slack_message "🚀 开始迁移 namespace: $NAMESPACE" "good"

if ./migrate.sh -n $NAMESPACE; then
    send_slack_message "✅ Namespace $NAMESPACE 迁移成功" "good"
    echo "迁移成功"
else
    send_slack_message "❌ Namespace $NAMESPACE 迁移失败，请检查日志" "danger"
    echo "迁移失败"
    exit 1
fi
EOF

chmod +x migrate-with-notification.sh
./migrate-with-notification.sh my-app
```

## 测试和验证示例

### 13. 迁移后验证脚本

```bash
# 创建全面的验证脚本
cat > validate-migration.sh << 'EOF'
#!/bin/bash

NAMESPACE=$1
VALIDATION_FAILED=0

echo "🔍 开始验证 namespace $NAMESPACE 的迁移结果..."

# 1. 检查 Namespace 是否存在
if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
    echo "❌ Namespace $NAMESPACE 不存在"
    exit 1
fi

# 2. 检查 Pod 状态
echo "检查 Pod 状态..."
failed_pods=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Failed --no-headers | wc -l)
pending_pods=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Pending --no-headers | wc -l)

if [ $failed_pods -gt 0 ]; then
    echo "❌ 发现 $failed_pods 个失败的 Pod"
    kubectl get pods -n $NAMESPACE --field-selector=status.phase=Failed
    VALIDATION_FAILED=1
fi

if [ $pending_pods -gt 0 ]; then
    echo "⚠️  发现 $pending_pods 个 Pending 的 Pod"
    kubectl get pods -n $NAMESPACE --field-selector=status.phase=Pending
fi

# 3. 检查 Service 端点
echo "检查 Service 端点..."
services=$(kubectl get services -n $NAMESPACE --no-headers | awk '{print $1}')
for svc in $services; do
    endpoints=$(kubectl get endpoints $svc -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    if [ -z "$endpoints" ]; then
        echo "⚠️  Service $svc 没有端点"
    else
        echo "✅ Service $svc 有端点: $(echo $endpoints | wc -w) 个"
    fi
done

# 4. 检查 Ingress 状态
echo "检查 Ingress 状态..."
ingresses=$(kubectl get ingresses -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $1}')
for ing in $ingresses; do
    address=$(kubectl get ingress $ing -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -z "$address" ]; then
        echo "⚠️  Ingress $ing 没有分配地址"
    else
        echo "✅ Ingress $ing 地址: $address"
    fi
done

# 5. 检查 PVC 状态
echo "检查 PVC 状态..."
unbound_pvcs=$(kubectl get pvc -n $NAMESPACE --field-selector=status.phase!=Bound --no-headers 2>/dev/null | wc -l)
if [ $unbound_pvcs -gt 0 ]; then
    echo "⚠️  发现 $unbound_pvcs 个未绑定的 PVC"
    kubectl get pvc -n $NAMESPACE --field-selector=status.phase!=Bound
fi

# 6. 应用功能测试
echo "执行应用功能测试..."
# 这里可以添加特定的应用测试逻辑

if [ $VALIDATION_FAILED -eq 0 ]; then
    echo "🎉 验证通过，迁移成功"
else
    echo "❌ 验证失败，需要手动检查"
    exit 1
fi
EOF

chmod +x validate-migration.sh
./validate-migration.sh my-app
```

### 14. 性能对比测试

```bash
# 创建性能对比脚本
cat > performance-test.sh << 'EOF'
#!/bin/bash

NAMESPACE=$1
SERVICE_NAME=$2
TEST_DURATION=60

echo "对 namespace $NAMESPACE 中的服务 $SERVICE_NAME 进行性能测试..."

# 获取服务 IP
SERVICE_IP=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
SERVICE_PORT=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}')

echo "测试目标: $SERVICE_IP:$SERVICE_PORT"

# 创建测试 Pod
kubectl run perf-test --image=busybox --rm -it --restart=Never -- /bin/sh -c "
echo '开始性能测试...'
start_time=\$(date +%s)
success_count=0
total_count=0

while [ \$(($(date +%s) - start_time)) -lt $TEST_DURATION ]; do
    if wget -q -O- --timeout=5 http://$SERVICE_IP:$SERVICE_PORT/health >/dev/null 2>&1; then
        success_count=\$((success_count + 1))
    fi
    total_count=\$((total_count + 1))
    sleep 1
done

success_rate=\$((success_count * 100 / total_count))
echo \"测试结果: \$success_count/\$total_count 成功 (成功率: \$success_rate%)\"
"
EOF

chmod +x performance-test.sh
./performance-test.sh my-app my-service
```

## 故障恢复示例

### 15. 自动回滚脚本

```bash
# 创建自动回滚脚本
cat > auto-rollback.sh << 'EOF'
#!/bin/bash

NAMESPACE=$1
BACKUP_DIR="exports/${NAMESPACE}_latest"

echo "🔄 开始自动回滚 namespace $NAMESPACE..."

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ 找不到备份目录: $BACKUP_DIR"
    exit 1
fi

# 1. 删除当前 namespace
echo "删除当前 namespace..."
kubectl delete namespace $NAMESPACE --ignore-not-found=true

# 2. 等待 namespace 完全删除
echo "等待 namespace 删除完成..."
while kubectl get namespace $NAMESPACE >/dev/null 2>&1; do
    echo "等待中..."
    sleep 5
done

# 3. 从备份恢复
echo "从备份恢复..."
kubectl apply -f $BACKUP_DIR/namespace.yaml

# 按依赖顺序恢复资源
resource_order=(
    "configmaps"
    "secrets"
    "persistentvolumeclaims"
    "serviceaccounts"
    "roles"
    "rolebindings"
    "services"
    "deployments"
    "statefulsets"
    "daemonsets"
    "ingresses"
    "networkpolicies"
    "horizontalpodautoscalers"
    "poddisruptionbudgets"
)

for resource in "${resource_order[@]}"; do
    if [ -f "$BACKUP_DIR/${resource}.yaml" ]; then
        echo "恢复 $resource..."
        kubectl apply -f "$BACKUP_DIR/${resource}.yaml"
        sleep 5
    fi
done

echo "✅ 回滚完成"
EOF

chmod +x auto-rollback.sh
./auto-rollback.sh my-app
```

这些示例涵盖了从基础使用到高级场景的各种情况，可以根据实际需求进行调整和扩展。每个示例都包含了详细的说明和错误处理，确保在实际使用中的可靠性。