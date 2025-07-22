在 GKE 中运行 Java 应用（Spring Boot 尤其是 WebFlux 模式）时，使用 server-conf.properties 作为配置文件并通过 ConfigMap 挂载是一种常见做法。以下是对你提到的关键参数的详细解释，以及相关联的其他参数说明（尤其是关于 HTTPS SSL 相关配置）：

✅

server-conf.properties

中常见参数详解
```bash
server.port=443

server.ssl.enabled=true

server.servlet.context-path=/api

spring.webflux.base-path=/v1
```

|                             |         |                                                                                   |
| --------------------------- | ------- | --------------------------------------------------------------------------------- |
| 参数                        | 类型    | 含义                                                                              |
| server.port                 | int     | 应用监听的端口，通常 80（HTTP）或 443（HTTPS）                                    |
| server.ssl.enabled          | boolean | 是否启用 SSL（即 HTTPS）                                                          |
| server.servlet.context-path | string  | 仅在 Spring MVC 模式下有效，定义所有 controller 的统一前缀路径                    |
| spring.webflux.base-path    | string  | 仅在 Spring WebFlux 模式下有效，定义所有 RouterFunction/controller 的统一路径前缀 |

⚠️ 注意：Spring Boot 2.1+ 支持 WebFlux 的 base-path，适用于响应式编程模型，类似于 context-path 的作用。

🔐 SSL/TLS 配置相关参数（用于 HTTPS）
启用 server.ssl.enabled=true 后，以下参数需要一并配置：

```bash
server.ssl.key-store=classpath:keystore.p12

server.ssl.key-store-password=your-password

server.ssl.key-store-type=PKCS12

server.ssl.key-alias=your-cert-alias
```

|                                 |                |                                                                                     |
| ------------------------------- | -------------- | ----------------------------------------------------------------------------------- |
| 参数                            | 类型           | 含义                                                                                |
| server.ssl.key-store            | string         | 指定密钥库的位置，支持 classpath 或文件系统路径（例如：file:/etc/certs/server.p12） |
| server.ssl.key-store-password   | string         | 密钥库的密码                                                                        |
| server.ssl.key-store-type       | string         | 密钥库类型，常见值为 JKS 或 PKCS12                                                  |
| server.ssl.key-alias            | string         | 密钥库中的别名，用于定位具体证书                                                    |
| server.ssl.trust-store          | string（可选） | 如果需要双向 TLS（mTLS），指定信任库位置                                            |
| server.ssl.trust-store-password | string（可选） | 信任库的密码                                                                        |
| server.ssl.trust-store-type     | string（可选） | 信任库类型，常为 JKS 或 PKCS12                                                      |
| server.ssl.client-auth          | string（可选） | 设置客户端认证方式：none、want 或 need（mTLS 场景下使用）                           |

🧠 例子说明

配置文件结构

# server-conf.properties
```bash
server.port=443

server.ssl.enabled=true

server.ssl.key-store=classpath:keystore.p12

server.ssl.key-store-password=changeit

server.ssl.key-store-type=PKCS12

server.ssl.key-alias=app

spring.webflux.base-path=/v1
```
如果你使用 Kubernetes ConfigMap：
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
name: app-config
data:
server-conf.properties: |
server.port=443
server.ssl.enabled=true
server.ssl.key-store=classpath:keystore.p12
server.ssl.key-store-password=changeit
server.ssl.key-store-type=PKCS12
server.ssl.key-alias=app
spring.webflux.base-path=/v1
```
然后挂载至 Pod：
```yaml
volumeMounts:
- name: config-volume
mountPath: /app/config
volumes:
- name: config-volume
configMap:
name: app-config
```
并在启动命令或 application.properties 中引用：

spring.config.additional-location=file:/app/config/

🧩 小贴士

- server.port=443 需要 root 权限，建议在容器中使用非 root 用户运行服务时使用 8443 或 8444，并通过 LB 或 Nginx 转发。
- server.servlet.context-path 与 spring.webflux.base-path 互不通用，使用哪一个取决于你使用的是 MVC 还是 WebFlux。
- 在 WebFlux 模式下，如果需要统一路径前缀，务必使用 spring.webflux.base-path。

📋 常用配置参数对比表

|         |                               |                        |                      |
| ------- | ----------------------------- | ---------------------- | -------------------- |
| 模块    | 参数                          | 示例值                 | 说明                 |
| 通用    | server.port                   | 443                    | 监听端口             |
| 通用    | server.ssl.enabled            | true                   | 启用 HTTPS           |
| MVC     | server.servlet.context-path   | /api                   | MVC 模式统一路径     |
| WebFlux | spring.webflux.base-path      | /v1                    | WebFlux 模式统一路径 |
| SSL     | server.ssl.key-store          | classpath:keystore.p12 | 密钥路径             |
| SSL     | server.ssl.key-store-password | xxx                    | 密钥密码             |
| SSL     | server.ssl.key-store-type     | PKCS12                 | 类型                 |
| SSL     | server.ssl.key-alias          | app                    | 别名                 |

如果你还希望我补充一个完整的 Spring Boot WebFlux 配置样板（适用于 GKE ConfigMap + Secret 挂载），我可以继续为你生成。需要的话请告知。

# How to debug listen 8443

如果我的实际环境中配置文件中端口使用8443.但是用户部署的服务没有正常监听,而是看到日志启动中是8080,那么我如何Debug这个过程?

这是一个典型的配置文件加载优先级问题。当你在配置文件中设置了 server.port=8443，但应用启动时显示 8080，说明有其他配置源覆盖了你的设置。

让我帮你系统化地排查这个问题：

1. 检查 Spring Boot 配置加载顺序
Spring Boot 配置有严格的优先级顺序（从高到低）：

# 1. 命令行参数（最高优先级）
java -jar app.jar --server.port=8080

# 2. 环境变量
export SERVER_PORT=8080

# 3. application-{profile}.properties
# 4. application.properties
# 5. server-conf.properties（如果通过 @PropertySource 加载）
2. Debug 步骤
检查环境变量
# 在 Pod 中执行
kubectl exec -it <pod-name> -- env | grep -i port
kubectl exec -it <pod-name> -- env | grep -i server

# 或者查看 ConfigMap 和 Secret
kubectl describe configmap <configmap-name>
kubectl get pod <pod-name> -o yaml | grep -A 10 -B 10 env
检查 Dockerfile/启动命令
# 查看容器启动命令
kubectl describe pod <pod-name>
kubectl logs <pod-name> | head -20

# 检查是否有硬编码的端口参数
docker inspect <image-name> | grep -i cmd
验证 ConfigMap 挂载
# 进入容器检查配置文件内容
kubectl exec -it <pod-name> -- cat /path/to/server-conf.properties
kubectl exec -it <pod-name> -- ls -la /path/to/config/

# 确认文件权限和内容
kubectl exec -it <pod-name> -- cat /etc/config/server-conf.properties
3. 应用层面排查
添加调试日志
在你的 Spring Boot 应用中添加：
```java
@Component
public class ConfigDebugger implements ApplicationListener<ApplicationReadyEvent> {
    
    @Value("${server.port:default}")
    private String serverPort;
    
    @Autowired
    private Environment env;
    
    @Override
    public void onApplicationEvent(ApplicationReadyEvent event) {
        log.info("=== Configuration Debug ===");
        log.info("server.port from @Value: {}", serverPort);
        log.info("server.port from Environment: {}", env.getProperty("server.port"));
        
        // 打印所有 server.* 相关配置
        ((ConfigurableEnvironment) env).getPropertySources().forEach(ps -> {
            log.info("PropertySource: {} - Class: {}", ps.getName(), ps.getClass().getSimpleName());
        });
    }
}
检查配置文件加载
@Configuration
public class ConfigurationDebug {
    
    @PostConstruct
    public void debugConfig() {
        System.out.println("=== Active Profiles ===");
        Arrays.stream(env.getActiveProfiles()).forEach(System.out::println);
        
        System.out.println("=== server.port sources ===");
        if (env instanceof ConfigurableEnvironment) {
            ConfigurableEnvironment configurableEnv = (ConfigurableEnvironment) env;
            configurableEnv.getPropertySources().forEach(source -> {
                if (source.containsProperty("server.port")) {
                    System.out.println("Found server.port in: " + source.getName() + 
                                     " = " + source.getProperty("server.port"));
                }
            });
        }
    }
}
```
4. 常见原因和解决方案
Kubernetes 环境变量覆盖
# deployment.yaml 中可能有：
spec:
  containers:
  - name: app
    env:
    - name: SERVER_PORT  # 这会覆盖配置文件
      value: "8080"
    - name: server.port  # 或者这种格式
      value: "8080"
Profile 配置冲突
# 检查是否有 application-prod.properties 等文件覆盖
kubectl exec -it <pod-name> -- find /app -name "application*.properties" -exec cat {} \;

ConfigMap 挂载路径问题
# 确保 ConfigMap 正确挂载到应用能读取的位置
volumeMounts:
- name: config-volume
  mountPath: /app/config  # 确保路径正确
  
# 并且应用启动时指定配置路径
args: ["--spring.config.location=classpath:/,file:/app/config/"]
5. 快速验证方法


# 1. 直接在容器内测试端口监听
kubectl exec -it <pod-name> -- netstat -tlnp | grep :8443
kubectl exec -it <pod-name> -- ss -tlnp | grep :8443

# 2. 检查应用健康检查端点
kubectl exec -it <pod-name> -- curl localhost:8443/actuator/health
kubectl exec -it <pod-name> -- curl localhost:8080/actuator/health

# 3. 查看完整的环境配置
kubectl exec -it <pod-name> -- curl localhost:8080/actuator/env | jq '.propertySources'