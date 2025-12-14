# 探针配置实战示例

本文档提供真实场景下的探针配置示例和测量过程。

## 场景 1：Nginx 快速启动应用

### 测量过程

```bash
$ ./pod_measure_startup_fixed.sh -n lex nginx-deployment-854b5bc678-m428j

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
测量 Pod 启动时间: nginx-deployment-854b5bc678-m428j (命名空间: lex)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 步骤 1: 获取 Pod 基本信息
   Pod 创建时间: 2025-10-29T10:58:34Z
   容器启动时间: 2025-11-30T05:07:28Z

📋 步骤 2: 分析就绪探针配置
   就绪探针配置:
   {
     "failureThreshold": 3,
     "httpGet": {
       "path": "/",
       "port": 80,
       "scheme": "HTTP"
     },
     "periodSeconds": 20,
     "successThreshold": 1,
     "timeoutSeconds": 3
   }

⏱️  步骤 3: 检查 Pod Ready 状态
   Pod 已处于 Ready 状态
   Ready 时间: 2025-11-30T05:07:38Z

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 最终结果 (Result)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 应用程序启动耗时: 10 秒
   (基于 Kubernetes Ready 状态)

📋 当前探针配置分析:
   - 当前配置允许的最大启动时间: 60 秒
   - 实际启动时间: 10 秒
   ✓ 当前配置足够
```

### 优化后的配置

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: lex
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        
        # 启动探针：快速启动应用可以使用较小的 failureThreshold
        startupProbe:
          httpGet:
            path: /
            port: 80
            scheme: HTTP
          initialDelaySeconds: 0
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 2  # 10s × 2 = 20秒窗口（实际只需 10 秒）
          successThreshold: 1
        
        # 就绪探针：快速检测流量就绪状态
        readinessProbe:
          httpGet:
            path: /
            port: 80
            scheme: HTTP
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 2
          failureThreshold: 3
        
        # 存活探针：保守策略
        livenessProbe:
          httpGet:
            path: /
            port: 80
            scheme: HTTP
          initialDelaySeconds: 0
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
```

---

## 场景 2：Spring Boot 应用（中等启动时间）

### 测量过程

假设我们测量了一个 Spring Boot 应用 5 次：

```bash
# 测量 1
$ ./pod_measure_startup_fixed.sh -n production spring-api-pod-abc123
✅ 应用程序启动耗时: 35 秒

# 测量 2
$ ./pod_measure_startup_fixed.sh -n production spring-api-pod-def456
✅ 应用程序启动耗时: 42 秒

# 测量 3
$ ./pod_measure_startup_fixed.sh -n production spring-api-pod-ghi789
✅ 应用程序启动耗时: 38 秒

# 测量 4
$ ./pod_measure_startup_fixed.sh -n production spring-api-pod-jkl012
✅ 应用程序启动耗时: 40 秒

# 测量 5
$ ./pod_measure_startup_fixed.sh -n production spring-api-pod-mno345
✅ 应用程序启动耗时: 55 秒  ← P99，使用这个值
```

### 参数计算

```
P99 启动时间: 55 秒
安全系数: 1.5
目标保护时长: 55 × 1.5 = 82.5 秒
periodSeconds: 10 秒
failureThreshold: 82.5 / 10 = 8.25 ≈ 9 次

推荐配置: failureThreshold = 9 (提供 90 秒窗口)
```

### 配置示例

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-api
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: spring-api
  template:
    metadata:
      labels:
        app: spring-api
    spec:
      containers:
      - name: api
        image: my-spring-api:v1.0
        ports:
        - containerPort: 8080
        
        # 启动探针：保护 Spring Boot 启动
        startupProbe:
          httpGet:
            path: /actuator/health
            port: 8080
            scheme: HTTPS
          initialDelaySeconds: 0
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 9  # 10s × 9 = 90秒窗口
          successThreshold: 1
        
        # 就绪探针：快速检测
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
            scheme: HTTPS
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 2
          failureThreshold: 3
        
        # 存活探针：检测死锁
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8080
            scheme: HTTPS
          initialDelaySeconds: 0
          periodSeconds: 20
          timeoutSeconds: 5
          failureThreshold: 3
        
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
```

---

## 场景 3：慢启动应用（AI/ML 模型加载）

### 测量过程

```bash
$ ./pod_measure_startup_fixed.sh -n ml-platform model-server-pod-xyz789

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 最终结果 (Result)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 应用程序启动耗时: 180 秒
   (基于 Kubernetes Ready 状态)

📋 当前探针配置分析:
   - 当前配置允许的最大启动时间: 120 秒
   - 实际启动时间: 180 秒
   ⚠️  警告: 实际启动时间超过当前配置!

💡 建议的优化配置:
   startupProbe:
     periodSeconds: 10
     failureThreshold: 27  # (180 × 1.5) / 10 = 27
```

### 参数计算

```
P99 启动时间: 180 秒
安全系数: 1.5
目标保护时长: 180 × 1.5 = 270 秒
periodSeconds: 10 秒
failureThreshold: 270 / 10 = 27 次

推荐配置: failureThreshold = 27 (提供 270 秒窗口)
```

### 配置示例

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-model-server
  namespace: ml-platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app: model-server
  template:
    metadata:
      labels:
        app: model-server
    spec:
      containers:
      - name: model-server
        image: ml-model-server:v2.0
        ports:
        - containerPort: 8080
        
        # 启动探针：为模型加载提供足够时间
        startupProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 0
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 27  # 10s × 27 = 270秒窗口
          successThreshold: 1
        
        # 就绪探针：检测模型是否可以处理请求
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 0
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        
        # 存活探针：检测服务是否假死
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 0
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        
        resources:
          requests:
            memory: "4Gi"
            cpu: "2000m"
          limits:
            memory: "8Gi"
            cpu: "4000m"
```

---

## 场景 4：带 Init Container 的应用

### 重要提示

Init Container 的耗时**不计入**探针时间！

### 测量过程

```bash
$ kubectl get pod my-app-pod-abc123 -n production
NAME                  READY   STATUS     RESTARTS   AGE
my-app-pod-abc123     0/1     Init:0/1   0          45s

# Init Container 运行了 45 秒，但这不影响探针配置

$ kubectl get pod my-app-pod-abc123 -n production
NAME                  READY   STATUS    RESTARTS   AGE
my-app-pod-abc123     0/1     Running   0          50s

# 主容器启动后，探针才开始工作

$ ./pod_measure_startup_fixed.sh -n production my-app-pod-abc123
✅ 应用程序启动耗时: 30 秒
   (基于 Kubernetes Ready 状态)
```

### 配置示例

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: production
spec:
  template:
    spec:
      # Init Container：复制 APPD Agent（耗时不计入探针）
      initContainers:
      - name: appd-init
        image: appd-agent:latest
        command: ['sh', '-c', 'cp -r /opt/appd /shared']
        volumeMounts:
        - name: appd-volume
          mountPath: /shared
      
      # 主容器：探针从这里开始计时
      containers:
      - name: app
        image: my-app:v1.0
        ports:
        - containerPort: 8080
        
        # 启动探针：只需考虑主容器启动时间（30秒）
        startupProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTPS
          initialDelaySeconds: 0
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 5  # 10s × 5 = 50秒（30秒 × 1.5 = 45秒）
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
        
        volumeMounts:
        - name: appd-volume
          mountPath: /opt/appd
      
      volumes:
      - name: appd-volume
        emptyDir: {}
```

---

## 故障排查示例

### 问题 1：Pod 一直 CrashLoopBackOff

```bash
$ kubectl get pod spring-api-pod-abc123 -n production
NAME                    READY   STATUS             RESTARTS   AGE
spring-api-pod-abc123   0/1     CrashLoopBackOff   5          5m

$ kubectl describe pod spring-api-pod-abc123 -n production
...
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Warning  Unhealthy  2m (x12 over 5m)   kubelet            Startup probe failed: Get "https://10.0.1.5:8080/health": context deadline exceeded
  Normal   Killing    2m                 kubelet            Container app failed startup probe, will be restarted
```

**原因**：启动时间超过配置的窗口

**解决方案**：
1. 测量实际启动时间
2. 增加 `failureThreshold`

```yaml
# 修改前
startupProbe:
  failureThreshold: 6  # 60秒窗口

# 修改后
startupProbe:
  failureThreshold: 12  # 120秒窗口
```

### 问题 2：健康检查接口超时

```bash
$ kubectl describe pod spring-api-pod-abc123 -n production
...
Events:
  Warning  Unhealthy  1m (x20 over 5m)   kubelet   Startup probe failed: Get "https://10.0.1.5:8080/health": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

**原因**：`/health` 接口响应太慢（>3秒）

**解决方案**：优化健康检查接口

```java
// 修改前：重逻辑
@GetMapping("/health")
public ResponseEntity<String> health() {
    // ❌ 查询数据库
    userRepository.count();
    // ❌ 调用外部服务
    externalService.ping();
    // ❌ 复杂计算
    calculateMetrics();
    
    return ResponseEntity.ok("OK");
}

// 修改后：轻量级
@GetMapping("/health")
public ResponseEntity<String> health() {
    // ✅ 仅检查应用本身状态
    return ResponseEntity.ok("OK");
}

// 或者使用 Spring Boot Actuator
@GetMapping("/actuator/health/liveness")
public ResponseEntity<String> liveness() {
    // ✅ 仅检查进程是否存活
    return ResponseEntity.ok("OK");
}
```

---

## 总结

### 关键步骤

1. **测量** → 使用脚本获取真实启动时间
2. **计算** → 根据 P99 计算 failureThreshold
3. **应用** → 更新 Deployment 配置
4. **验证** → 观察 Pod 启动是否正常
5. **优化** → 确保 /health 接口轻量

### 记住这些数字

- **periodSeconds**: 固定 10 秒
- **timeoutSeconds**: 3 秒（健康检查接口必须快速响应）
- **failureThreshold**: 根据启动时间计算
  - 快速启动（<30s）: 5-6
  - 中等启动（30-60s）: 9-12
  - 慢启动（>60s）: 18-30

### 避免这些错误

❌ 不要增加 `timeoutSeconds` 来解决启动慢的问题  
✅ 应该增加 `failureThreshold`

❌ 不要在 `/health` 接口里做重逻辑  
✅ 应该保持接口轻量（<100ms）

❌ 不要忘记 Init Container 的时间不计入探针  
✅ 只需考虑主容器的启动时间
