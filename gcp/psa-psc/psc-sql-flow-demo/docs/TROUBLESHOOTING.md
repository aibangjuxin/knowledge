# 故障排除指南

## 常见问题和解决方案

### 1. PSC 连接问题

#### 问题：无法连接到 PSC 端点

**症状**:
- Pod 日志显示数据库连接超时
- `nc -zv <PSC_IP> 3306` 失败

**排查步骤**:

1. 检查 PSC 端点状态
```bash
gcloud compute forwarding-rules describe sql-psc-endpoint \
  --region=asia-east2 \
  --project=${CONSUMER_PROJECT_ID}
```

2. 检查服务附件状态
```bash
gcloud sql instances describe ${SQL_INSTANCE_NAME} \
  --project=${PRODUCER_PROJECT_ID} \
  --format="value(pscServiceAttachmentLink)"
```

3. 验证 Consumer 项目授权
```bash
gcloud sql instances describe ${SQL_INSTANCE_NAME} \
  --project=${PRODUCER_PROJECT_ID} \
  --format="value(settings.pscConfig.allowedConsumerProjects[])"
```

**解决方案**:
- 确保 Consumer 项目在 Producer 的授权列表中
- 检查 PSC 端点配置是否正确
- 验证网络配置

#### 问题：PSC 端点创建失败

**症状**:
- `gcloud compute forwarding-rules create` 命令失败
- 错误信息提示权限或配额问题

**解决方案**:
1. 检查 API 是否启用
```bash
gcloud services list --enabled --project=${CONSUMER_PROJECT_ID} | grep privateconnect
```

2. 检查配额
```bash
gcloud compute project-info describe --project=${CONSUMER_PROJECT_ID}
```

3. 检查 IAM 权限
```bash
gcloud projects get-iam-policy ${CONSUMER_PROJECT_ID}
```

### 2. GKE 集群问题

#### 问题：Pod 无法调度

**症状**:
- Pod 处于 `Pending` 状态
- 事件显示资源不足

**排查步骤**:
```bash
kubectl describe pod <pod-name> -n psc-demo
kubectl get nodes
kubectl top nodes
```

**解决方案**:
1. 增加节点数量
```bash
gcloud container clusters resize ${GKE_CLUSTER_NAME} \
  --num-nodes=3 \
  --zone=${ZONE} \
  --project=${CONSUMER_PROJECT_ID}
```

2. 调整资源请求
```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
```

#### 问题：Workload Identity 配置错误

**症状**:
- Pod 无法访问 Google Cloud 服务
- 权限被拒绝错误

**排查步骤**:
1. 检查 Service Account 注解
```bash
kubectl describe sa db-app-sa -n psc-demo
```

2. 检查 IAM 绑定
```bash
gcloud iam service-accounts get-iam-policy \
  db-app-gsa@${CONSUMER_PROJECT_ID}.iam.gserviceaccount.com
```

**解决方案**:
1. 重新配置 Workload Identity
```bash
gcloud iam service-accounts add-iam-policy-binding \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${CONSUMER_PROJECT_ID}.svc.id.goog[psc-demo/db-app-sa]" \
  db-app-gsa@${CONSUMER_PROJECT_ID}.iam.gserviceaccount.com
```

2. 更新 Service Account 注解
```bash
kubectl annotate serviceaccount db-app-sa -n psc-demo \
  iam.gke.io/gcp-service-account=db-app-gsa@${CONSUMER_PROJECT_ID}.iam.gserviceaccount.com
```

### 3. 应用程序问题

#### 问题：应用启动失败

**症状**:
- Pod 处于 `CrashLoopBackOff` 状态
- 启动探针失败

**排查步骤**:
```bash
kubectl logs <pod-name> -n psc-demo
kubectl describe pod <pod-name> -n psc-demo
```

**常见原因和解决方案**:

1. **数据库连接配置错误**
```bash
# 检查配置
kubectl get configmap db-config -n psc-demo -o yaml

# 更新配置
kubectl patch configmap db-config -n psc-demo --patch '
data:
  DB_HOST: "10.1.1.100"  # 正确的 PSC IP
'
```

2. **密码错误**
```bash
# 检查密码
kubectl get secret db-credentials -n psc-demo -o yaml

# 更新密码
kubectl patch secret db-credentials -n psc-demo --patch '
data:
  DB_PASSWORD: <base64-encoded-password>
'
```

3. **资源限制过低**
```yaml
resources:
  limits:
    memory: "512Mi"  # 增加内存限制
    cpu: "500m"      # 增加 CPU 限制
```

#### 问题：健康检查失败

**症状**:
- Liveness 或 Readiness 探针失败
- Pod 频繁重启

**解决方案**:
1. 调整探针配置
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 60  # 增加初始延迟
  periodSeconds: 30
  timeoutSeconds: 10       # 增加超时时间
  failureThreshold: 5      # 增加失败阈值
```

2. 检查应用日志
```bash
kubectl logs <pod-name> -n psc-demo --previous
```

### 4. 网络问题

#### 问题：防火墙规则阻止连接

**症状**:
- 网络连通性测试失败
- 连接被拒绝

**排查步骤**:
```bash
# 检查防火墙规则
gcloud compute firewall-rules list --project=${CONSUMER_PROJECT_ID}

# 测试连接
kubectl exec deployment/db-app -n psc-demo -- nc -zv <PSC_IP> 3306
```

**解决方案**:
1. 创建或更新防火墙规则
```bash
gcloud compute firewall-rules create allow-sql-psc-egress \
  --project=${CONSUMER_PROJECT_ID} \
  --network=${CONSUMER_VPC} \
  --direction=EGRESS \
  --destination-ranges=<PSC_IP>/32 \
  --action=ALLOW \
  --rules=tcp:3306
```

#### 问题：网络策略过于严格

**症状**:
- Pod 间通信失败
- 无法访问外部服务

**解决方案**:
1. 临时禁用网络策略进行测试
```bash
kubectl delete networkpolicy db-app-network-policy -n psc-demo
```

2. 调整网络策略规则
```yaml
spec:
  egress:
  - to: []  # 允许所有出站流量 (仅用于调试)
```

### 5. 数据库问题

#### 问题：Cloud SQL 连接数耗尽

**症状**:
- 应用日志显示 "too many connections"
- 数据库连接失败

**解决方案**:
1. 调整连接池配置
```yaml
data:
  DB_MAX_CONNECTIONS: "5"      # 减少最大连接数
  DB_MAX_IDLE_CONNECTIONS: "2" # 减少空闲连接数
```

2. 升级 Cloud SQL 实例
```bash
gcloud sql instances patch ${SQL_INSTANCE_NAME} \
  --project=${PRODUCER_PROJECT_ID} \
  --tier=db-n1-standard-4
```

#### 问题：数据库权限不足

**症状**:
- 应用可以连接但无法执行查询
- 权限被拒绝错误

**解决方案**:
1. 检查用户权限
```sql
SHOW GRANTS FOR 'appuser'@'%';
```

2. 授予必要权限
```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON appdb.* TO 'appuser'@'%';
FLUSH PRIVILEGES;
```

### 6. 监控和调试工具

#### 实时监控
```bash
# 使用监控脚本
./scripts/monitor.sh

# 或者使用 kubectl
watch kubectl get pods -n psc-demo -o wide
```

#### 日志收集
```bash
# 收集所有 Pod 日志
kubectl logs -l app=db-app -n psc-demo --all-containers=true

# 持续监控日志
kubectl logs -f deployment/db-app -n psc-demo
```

#### 网络调试
```bash
# 进入 Pod 进行网络调试
kubectl exec -it deployment/db-app -n psc-demo -- /bin/sh

# 在 Pod 内测试
ping <PSC_IP>
nc -zv <PSC_IP> 3306
nslookup google.com
```

#### 性能分析
```bash
# 查看资源使用情况
kubectl top pods -n psc-demo
kubectl top nodes

# 查看 HPA 状态
kubectl describe hpa db-app-hpa -n psc-demo
```

### 7. 紧急恢复步骤

#### 快速重启应用
```bash
kubectl rollout restart deployment/db-app -n psc-demo
```

#### 回滚到上一个版本
```bash
kubectl rollout undo deployment/db-app -n psc-demo
```

#### 扩容应用
```bash
kubectl scale deployment db-app --replicas=5 -n psc-demo
```

#### 临时禁用健康检查
```bash
kubectl patch deployment db-app -n psc-demo --patch '
spec:
  template:
    spec:
      containers:
      - name: db-app
        livenessProbe: null
        readinessProbe: null
'
```

### 8. 预防措施

#### 监控告警
- 设置 Pod 重启告警
- 监控数据库连接数
- 设置资源使用告警

#### 定期检查
- 定期测试 PSC 连接
- 检查证书过期时间
- 验证备份和恢复流程

#### 文档维护
- 更新运维文档
- 记录已知问题和解决方案
- 维护联系人信息

## 获取帮助

如果问题仍然存在，请收集以下信息：

1. **环境信息**
```bash
kubectl version
gcloud version
kubectl get nodes -o wide
```

2. **应用状态**
```bash
kubectl get all -n psc-demo
kubectl describe deployment db-app -n psc-demo
```

3. **日志信息**
```bash
kubectl logs deployment/db-app -n psc-demo --tail=100
kubectl get events -n psc-demo --sort-by='.lastTimestamp'
```

4. **网络配置**
```bash
gcloud compute forwarding-rules list --project=${CONSUMER_PROJECT_ID}
gcloud compute firewall-rules list --project=${CONSUMER_PROJECT_ID}
```