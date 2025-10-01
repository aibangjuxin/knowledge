# GCP Cloud Run Java 超时问题调试指南

## 问题概述

当 GKE Pod 调用 Cloud Run 服务时出现 500 错误，同时客户端显示 `AsyncRequestTimeoutException`。这是一个典型的异步请求超时问题。

## 错误分析

### 客户端错误信息
```
org.springframework.web.context.request.async.AsyncRequestTimeoutException
```

这个异常表明：
- Spring Boot 应用使用了异步处理（DeferredResult 或 Callable）
- 异步请求在指定时间内没有完成
- 默认超时时间到达后触发了超时处理

### 可能的根本原因

1. **Cloud Run 服务响应慢**
   - 冷启动延迟
   - 业务逻辑处理时间过长
   - 数据库查询缓慢

2. **网络问题**
   - GKE 到 Cloud Run 的网络延迟
   - 网络丢包或不稳定

3. **超时配置不匹配**
   - 客户端超时设置过短
   - Cloud Run 服务超时设置

## 调试步骤

### 1. 检查 Cloud Run 服务端日志

```bash
# 查看 Cloud Run 服务日志
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=YOUR_SERVICE_NAME" --limit=50 --format="table(timestamp,severity,textPayload)"
```

**关键检查点：**
- 是否有对应的请求日志
- 请求处理时间
- 是否有 500 错误记录
- 冷启动日志

### 2. 分析客户端配置

检查 Spring Boot 应用的异步配置：

```java
@Configuration
public class AsyncConfig implements WebMvcConfigurer {
    
    @Override
    public void configureAsyncSupport(AsyncSupportConfigurer configurer) {
        // 检查超时设置
        configurer.setDefaultTimeout(30000); // 30秒
    }
}
```

### 3. 检查 HTTP 客户端配置

```java
@Bean
public RestTemplate restTemplate() {
    HttpComponentsClientHttpRequestFactory factory = new HttpComponentsClientHttpRequestFactory();
    factory.setConnectTimeout(5000);    // 连接超时
    factory.setReadTimeout(30000);      // 读取超时
    return new RestTemplate(factory);
}
```

### 4. Cloud Run 服务配置检查

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  annotations:
    run.googleapis.com/execution-environment: gen2
    run.googleapis.com/timeout: "300"  # 5分钟超时
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/maxScale: "10"
        run.googleapis.com/cpu-throttling: "false"
    spec:
      containerConcurrency: 80
      timeoutSeconds: 300
```

## 解决方案

### 1. 优化超时配置

**客户端（GKE Pod）：**
```properties
# application.properties
spring.mvc.async.request-timeout=60000
server.tomcat.connection-timeout=20000
```

**HTTP 客户端：**
```java
@Bean
public WebClient webClient() {
    return WebClient.builder()
        .clientConnector(new ReactorClientHttpConnector(
            HttpClient.create()
                .responseTimeout(Duration.ofSeconds(60))
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, 10000)
        ))
        .build();
}
```

### 2. 实现重试机制

```java
@Retryable(value = {Exception.class}, maxAttempts = 3, backoff = @Backoff(delay = 1000))
public ResponseEntity<String> callCloudRunService(String url) {
    return restTemplate.getForEntity(url, String.class);
}
```

### 3. 添加监控和日志

```java
@RestController
public class CloudRunController {
    
    private static final Logger logger = LoggerFactory.getLogger(CloudRunController.class);
    
    @GetMapping("/call-service")
    public DeferredResult<ResponseEntity<String>> callService() {
        DeferredResult<ResponseEntity<String>> deferredResult = new DeferredResult<>(30000L);
        
        deferredResult.onTimeout(() -> {
            logger.error("Request timeout when calling Cloud Run service");
            deferredResult.setErrorResult(ResponseEntity.status(HttpStatus.REQUEST_TIMEOUT).build());
        });
        
        // 异步调用逻辑
        CompletableFuture.supplyAsync(() -> {
            long startTime = System.currentTimeMillis();
            try {
                ResponseEntity<String> response = restTemplate.getForEntity("https://abcd.a.run.app/", String.class);
                logger.info("Cloud Run service responded in {}ms", System.currentTimeMillis() - startTime);
                return response;
            } catch (Exception e) {
                logger.error("Error calling Cloud Run service: {}", e.getMessage());
                throw new RuntimeException(e);
            }
        }).whenComplete((result, throwable) -> {
            if (throwable != null) {
                deferredResult.setErrorResult(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build());
            } else {
                deferredResult.setResult(result);
            }
        });
        
        return deferredResult;
    }
}
```

### 4. Cloud Run 优化

```yaml
# 减少冷启动影响
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  annotations:
    run.googleapis.com/execution-environment: gen2
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "1"  # 保持至少1个实例
        run.googleapis.com/startup-cpu-boost: "true"
    spec:
      containers:
      - image: gcr.io/project/image
        resources:
          limits:
            cpu: "2"
            memory: "2Gi"
        startupProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 0
          timeoutSeconds: 1
          periodSeconds: 3
          successThreshold: 1
          failureThreshold: 3
```

## 监控和告警

### 1. 设置 Cloud Monitoring 告警

```bash
# 创建超时告警策略
gcloud alpha monitoring policies create --policy-from-file=timeout-alert-policy.yaml
```

### 2. 添加自定义指标

```java
@Component
public class CloudRunMetrics {
    
    private final MeterRegistry meterRegistry;
    private final Timer.Sample sample;
    
    public CloudRunMetrics(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
    }
    
    public void recordCallDuration(long duration, boolean success) {
        Timer.builder("cloudrun.call.duration")
            .tag("success", String.valueOf(success))
            .register(meterRegistry)
            .record(duration, TimeUnit.MILLISECONDS);
    }
}
```

## 最佳实践

1. **合理设置超时时间**：客户端超时 > Cloud Run 超时
2. **实现熔断器**：防止级联故障
3. **使用连接池**：复用 HTTP 连接
4. **监控关键指标**：响应时间、错误率、超时率
5. **实现优雅降级**：超时时返回默认值或缓存数据

## 问题排查清单

- [ ] 检查 Cloud Run 服务日志是否有 500 错误
- [ ] 验证 Cloud Run 服务是否正常启动
- [ ] 检查客户端超时配置
- [ ] 测试网络连通性
- [ ] 监控 Cloud Run 性能指标
- [ ] 验证认证和权限配置
- [ ] 检查资源限制和配额

## 常见错误模式

| 错误类型 | 客户端日志 | Cloud Run 日志 | 解决方案 |
|---------|-----------|---------------|----------|
| 超时 | AsyncRequestTimeoutException | 无错误或处理中 | 增加超时时间 |
| 冷启动 | 连接超时 | 启动日志 | 设置最小实例数 |
| 服务错误 | 500 响应 | 应用异常 | 修复业务逻辑 |
| 网络问题 | 连接失败 | 无请求日志 | 检查网络配置 |

通过系统性的排查和优化，可以有效解决 GKE Pod 调用 Cloud Run 服务的超时问题。