# 深入探索 Kubernetes Deployment 中的环境变量

## 概述

本文档将深入探讨 Kubernetes Deployment 中环境变量（env）的使用方式，以及它们如何与容器内的应用程序协作。我们将以 `api-name-spring-samples` 部署为例，详细分析环境变量在实际应用中的工作原理。

## 环境变量在容器中的工作原理
- https://api-name-spring-samples-svc:8443/api-name-spring-samples/v2025.11.24/well-known/health
- https://spring-samples-svc:8443/api-name-spring-samples/v2025.11.24/well-known/health
### 1. 环境变量的注入机制

当 Kubernetes 创建 Pod 时，它会将 Deployment 配置中定义的环境变量注入到容器的运行时环境中。这些变量在容器启动时就可用，应用程序可以通过标准的环境变量访问方法获取它们的值。

在 Spring Boot 应用中，环境变量可以通过以下方式访问：
- 使用 `@Value` 注解注入到 Bean 中
- 通过 `Environment` 对象动态获取
- 在配置文件中引用（如 application.properties 或 application.yml）

### 2. 实际应用示例

#### 示例 1：apiName 环境变量的使用

**Deployment 配置：**
```yaml
- name: apiName
  value: api-name-spring-samples
```

**在 Spring Boot 应用中的使用：**
```java
@RestController
public class ApiController {
    
    @Value("${apiName:default-api}")
    private String apiName;
    
    @Autowired
    private Environment env;
    
    @GetMapping("/info")
    public ResponseEntity<String> getApiInfo() {
        // 通过 @Value 注解获取
        String apiNameFromAnnotation = this.apiName;
        
        // 通过 Environment 对象获取
        String apiNameFromEnv = env.getProperty("apiName");
        
        return ResponseEntity.ok("API Name: " + apiNameFromAnnotation);
    }
}
```

**实际应用场景：**
- 日志记录：在日志中包含 API 名称以便识别
- 监控指标：将 API 名称作为监控标签的一部分
- 配置管理：根据 API 名称加载特定的配置

#### 示例 2：minorVersion 环境变量的使用

**Deployment 配置：**
```yaml
- name: minorVersion
  value: 2025.11.24 # 模拟用的版本标识
```

**在 Spring Boot 应用中的使用：**
```java
@Component
public class VersionManager {
    
    @Value("${minorVersion:1.0.0}")
    private String minorVersion;
    
    public boolean isFeatureEnabled(String featureName) {
        // 根据版本号决定是否启用特定功能
        if ("new-feature".equals(featureName)) {
            // 假设新功能只在 2025.11.24 及以上版本启用
            return compareVersions(minorVersion, "2025.11.24") >= 0;
        }
        return true;
    }
    
    private int compareVersions(String version1, String version2) {
        // 版本比较逻辑
        String[] parts1 = version1.split("\\.");
        String[] parts2 = version2.split("\\.");
        
        for (int i = 0; i < Math.min(parts1.length, parts2.length); i++) {
            int part1 = Integer.parseInt(parts1[i]);
            int part2 = Integer.parseInt(parts2[i]);
            if (part1 != part2) {
                return Integer.compare(part1, part2);
            }
        }
        return Integer.compare(parts1.length, parts2.length);
    }
}

@RestController
public class FeatureController {
    
    @Autowired
    private VersionManager versionManager;
    
    @GetMapping("/feature/new-feature")
    public ResponseEntity<String> getNewFeature() {
        if (versionManager.isFeatureEnabled("new-feature")) {
            return ResponseEntity.ok("New feature is available in version " + 
                                   versionManager.getCurrentVersion());
        } else {
            return ResponseEntity.status(HttpStatus.NOT_IMPLEMENTED)
                               .body("Feature not available in this version");
        }
    }
}
```

**实际应用场景：**
- 功能开关：根据版本号启用或禁用特定功能
- A/B 测试：在不同版本间进行功能对比测试
- 渐进式发布：逐步向新版本用户开放新功能

#### 示例 3：BASE_PATH 环境变量的使用

**Deployment 配置：**
```yaml
- name: BASE_PATH
  value: /api-name-spring-samples/v2025.11.24 # 对应健康检查路径的版本
```

**在 Spring Boot 应用中的使用：**
```java
@Configuration
public class WebConfig implements WebMvcConfigurer {
    
    @Value("${BASE_PATH:/api}")
    private String basePath;
    
    @Override
    public void addViewControllers(ViewControllerRegistry registry) {
        // 根据 BASE_PATH 配置重定向
        registry.addRedirectViewController(basePath + "/", basePath + "/index.html");
    }
    
    @Bean
    public ServletWebServerFactory servletContainer() {
        TomcatServletWebServerFactory tomcat = new TomcatServletWebServerFactory();
        return tomcat;
    }
}

@RestController
public class BaseController {
    
    @Value("${BASE_PATH}")
    private String basePath;
    
    @GetMapping("${BASE_PATH}/status")
    public ResponseEntity<String> getStatus() {
        return ResponseEntity.ok("Service is running at " + basePath);
    }
    
    // 健康检查端点
    @GetMapping("${BASE_PATH}/.well-known/health")
    public ResponseEntity<Map<String, Object>> healthCheck() {
        Map<String, Object> response = new HashMap<>();
        response.put("status", "UP");
        response.put("basePath", basePath);
        response.put("timestamp", System.currentTimeMillis());
        return ResponseEntity.ok(response);
    }
}
```

**实际应用场景：**
- API 路由：根据版本号设置不同的 API 基础路径
- 健康检查：确保健康检查端点与版本路径一致
- 静态资源：根据版本路径提供对应的静态资源

#### 示例 4：HTTPS_CERT_PWD 环境变量的使用

**Deployment 配置：**
```yaml
- name: HTTPS_CERT_PWD
  valueFrom:
    secretKeyRef:
      key: abj-sprintruntime.p12.pwd
      name: env-region-secret-sprintruntime-local
```

**在 Spring Boot 应用中的使用：**
```java
@Configuration
public class SecurityConfig {
    
    @Value("${HTTPS_CERT_PWD}")
    private String certPassword;
    
    @Bean
    public TomcatServletWebServerFactory servletContainer() {
        TomcatServletWebServerFactory tomcat = new TomcatServletWebServerFactory();
        
        // 配置 HTTPS
        tomcat.addAdditionalTomcatConnectors(httpsConnector());
        return tomcat;
    }
    
    private Connector httpsConnector() {
        Connector connector = new Connector(TomcatServletWebServerFactory.DEFAULT_PROTOCOL);
        connector.setScheme("https");
        connector.setSecure(true);
        connector.setPort(8443);
        
        // 使用环境变量中的密码配置 SSL
        connector.setAttribute("keystoreFile", "/opt/certs/keystore.p12");
        connector.setAttribute("keystorePass", certPassword);
        connector.setAttribute("keystoreType", "PKCS12");
        connector.setAttribute("clientAuth", "false");
        connector.setAttribute("sslProtocol", "TLS");
        
        return connector;
    }
}
```

**实际应用场景：**
- SSL/TLS 配置：使用安全的密码配置 HTTPS 连接
- 认证凭据：安全地管理各种认证凭据
- 加密密钥：安全地管理加密和解密所需的密钥

#### 示例 5：APPDYNAMICS_AGENT_NODE_NAME 环境变量的使用

**Deployment 配置：**
```yaml
- name: APPDYNAMICS_AGENT_NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
```

**在 Spring Boot 应用中的使用：**
```java
@Component
public class MonitoringConfig {
    
    @Value("${APPDYNAMICS_AGENT_NODE_NAME:#{environment.getProperty('HOSTNAME')}}")
    private String nodeName;
    
    @PostConstruct
    public void initMonitoring() {
        // 使用节点名称配置监控代理
        System.setProperty("appdynamics.agent.nodeName", nodeName);
        
        // 在应用日志中包含节点信息
        System.out.println("AppDynamics agent configured for node: " + nodeName);
    }
}
```

**实际应用场景：**
- 应用性能监控：为每个 Pod 设置唯一的监控节点名称
- 日志追踪：在日志中包含 Pod 信息以便调试
- 指标收集：为每个实例收集独立的性能指标

#### 示例 6：JAVA_TOOL_OPTIONS 环境变量的使用

**Deployment 配置：**
```yaml
- name: JAVA_TOOL_OPTIONS
  value: -javaagent:/opt/appdynamics/javaagent.jar -Dappagent.start.timeout=5...
```

**实际应用场景：**
- JVM 参数配置：在不修改应用代码的情况下配置 JVM 参数
- 监控代理：自动加载应用性能监控代理
- 调试选项：启用 JVM 调试和性能分析选项

## 环境变量的类型和来源

### 1. 直接值（value）

直接在 YAML 中指定值，适用于非敏感信息：
```yaml
- name: API_NAME
  value: "my-api-service"
```

### 2. 从 Secret 引用（secretKeyRef）

用于安全地引用敏感信息，如密码、密钥等：
```yaml
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: database-credentials
      key: password
```

### 3. 从 ConfigMap 引用（configMapKeyRef）

用于引用配置信息：
```yaml
- name: CONFIG_VALUE
  valueFrom:
    configMapKeyRef:
      name: app-config
      key: some-config-key
```

### 4. 从字段引用（fieldRef）

用于引用 Pod 或容器的元数据：
```yaml
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
```

### 5. 从资源引用（resourceFieldRef）

用于引用容器的资源限制：
```yaml
- name: REQUEST_MEMORY
  valueFrom:
    resourceFieldRef:
      containerName: my-container
      resource: requests.memory
```

## 最佳实践

### 1. 敏感信息管理

对于敏感信息（如密码、密钥），始终使用 Secret：
```yaml
- name: DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: database-secret
      key: password
```

### 2. 环境区分

使用不同的 ConfigMap 或环境变量来区分不同环境（开发、测试、生产）：
```yaml
- name: ENVIRONMENT
  value: "production"
```

### 3. 默认值处理

在应用程序中提供默认值以处理环境变量未设置的情况：
```java
@Value("${optional.config.value:default-value}")
private String optionalConfig;
```

### 4. 变量命名规范

使用大写字母和下划线的命名约定：
```yaml
- name: DATABASE_URL
- name: API_TIMEOUT_SECONDS
```

## 总结

环境变量是 Kubernetes 中配置应用程序的重要机制，它们提供了一种灵活且安全的方式来管理应用程序的配置。通过合理使用不同类型的环境变量来源（直接值、Secret、ConfigMap、字段引用等），我们可以实现配置与代码的分离，提高应用的可移植性和安全性。

在实际应用中，环境变量与容器内的应用程序紧密协作，通过标准的环境变量访问接口，应用程序可以动态地获取配置信息并根据这些信息调整其行为。这种机制特别适用于微服务架构，其中每个服务都需要根据部署环境进行相应的配置调整。