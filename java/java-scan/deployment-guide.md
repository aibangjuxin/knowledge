# 部署指南

## 1. 本地开发环境部署

### 构建和测试
```bash
# 克隆项目
git clone <repository-url>
cd java-scan

# 构建项目
mvn clean package

# 运行测试
mvn test

# 测试扫描功能
java -jar target/auth-scanner.jar examples/sample-app.jar
```

## 2. CI/CD 环境集成

### GitLab CI 部署

1. 将扫描器构建为 Docker 镜像：
```bash
docker build -t your-registry/auth-scanner:latest -f docker/Dockerfile .
docker push your-registry/auth-scanner:latest
```

2. 在项目中添加 `.gitlab-ci.yml`：
```yaml
include:
  - local: 'java/java-scan/examples/gitlab-ci.yml'
```

### Jenkins 部署

1. 安装必要插件：
   - Docker Pipeline Plugin
   - HTML Publisher Plugin

2. 创建 Pipeline 任务，使用 `examples/jenkins-pipeline.groovy`

## 3. Kubernetes 环境部署

### 部署扫描器服务

```bash
# 创建 ConfigMap 存储扫描配置
kubectl create configmap auth-scanner-config \
  --from-file=config/scanner-rules.yaml

# 部署扫描器 Job
kubectl apply -f examples/kubernetes-job.yaml

# 查看扫描结果
kubectl logs job/auth-scanner-job
```

### 集成到部署流程

```yaml
# 在应用部署前添加扫描步骤
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: app-deploy-with-scan
spec:
  templates:
  - name: security-scan
    container:
      image: your-registry/auth-scanner:latest
      command: ["/app/pipeline-integration.sh"]
      args: ["{{inputs.parameters.jar-path}}"]
```

## 4. GCP/GKE 特定配置

### 使用 Cloud Build

```yaml
# cloudbuild.yaml
steps:
- name: 'maven:3.8-openjdk-11'
  entrypoint: 'mvn'
  args: ['clean', 'package']

- name: 'your-registry/auth-scanner:latest'
  entrypoint: '/app/pipeline-integration.sh'
  args: ['target/app.jar', 'src/main/resources', 'reports', 'true']

- name: 'gcr.io/cloud-builders/gsutil'
  args: ['cp', 'reports/*.json', 'gs://your-bucket/scan-reports/']
```

### 集成到 GKE Gateway

```yaml
# 在 Gateway 配置中添加认证检查
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: app-route
spec:
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    filters:
    - type: ExtensionRef
      extensionRef:
        group: security.example.com
        kind: AuthValidator
        name: auth-scanner-validator
```

## 5. 监控和告警

### Prometheus 指标

```yaml
# 添加自定义指标收集
apiVersion: v1
kind: ConfigMap
metadata:
  name: scanner-metrics
data:
  metrics.yaml: |
    auth_scan_total: 计数器 - 总扫描次数
    auth_scan_failures: 计数器 - 扫描失败次数
    auth_scan_duration: 直方图 - 扫描耗时
```

### Grafana 仪表板

```json
{
  "dashboard": {
    "title": "认证扫描监控",
    "panels": [
      {
        "title": "扫描成功率",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(auth_scan_total[5m]) - rate(auth_scan_failures[5m])"
          }
        ]
      }
    ]
  }
}
```

## 6. 生产环境最佳实践

### 安全配置

1. **镜像安全**：
```bash
# 使用非 root 用户
FROM openjdk:11-jre-slim
RUN adduser --disabled-password --gecos '' scanner
USER scanner
```

2. **资源限制**：
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### 性能优化

1. **并行扫描**：
```bash
# 对多个 JAR 文件并行扫描
parallel -j4 java -jar auth-scanner.jar {} ::: *.jar
```

2. **缓存优化**：
```yaml
# 使用 Redis 缓存扫描结果
cache:
  type: redis
  host: redis-service
  ttl: 3600
```

## 7. 故障排除

### 常见问题解决

1. **内存不足**：
```bash
export JAVA_OPTS="-Xmx1g -XX:+UseG1GC"
java $JAVA_OPTS -jar auth-scanner.jar app.jar
```

2. **扫描超时**：
```bash
# 增加超时时间
timeout 300 java -jar auth-scanner.jar app.jar
```

3. **权限问题**：
```bash
# 确保扫描器有读取权限
chmod +r target/*.jar
```

### 日志配置

```properties
# logback.xml
<configuration>
  <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder>
      <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
    </encoder>
  </appender>
  
  <logger name="com.aibang.scanner" level="DEBUG"/>
  <root level="INFO">
    <appender-ref ref="STDOUT"/>
  </root>
</configuration>
```

## 8. 扩展和定制

### 添加自定义规则

```java
// 扩展 AuthValidator
public class CustomAuthValidator extends AuthValidator {
    @Override
    public boolean validate(ScanResult result, boolean strictMode) {
        // 添加自定义验证逻辑
        boolean customCheck = validateCustomSecurity(result);
        return super.validate(result, strictMode) && customCheck;
    }
}
```

### 集成外部安全工具

```bash
# 与 OWASP Dependency Check 集成
mvn org.owasp:dependency-check-maven:check
java -jar auth-scanner.jar app.jar --dependency-report target/dependency-check-report.xml
```

这个部署指南涵盖了从开发到生产的完整部署流程，特别针对你的 GCP/GKE 环境进行了优化。