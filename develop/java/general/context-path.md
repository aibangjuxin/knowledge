# GKE Java 应用配置与调试指南

在 GKE 中运行 Java 应用（尤其是 Spring Boot）时，正确配置服务并有效调试是确保应用稳定运行的关键。本文档旨在提供一份全面的指南，涵盖从基础配置、HTTPS 设置到复杂场景下的问题排查。

---

## 第一部分：Spring Boot 核心配置

### 1.1 `server-conf.properties` 关键参数

使用 `.properties` 文件并通过 ConfigMap 挂载是常见的配置方式。

```bash
server.port=443
server.ssl.enabled=true
server.servlet.context-path=/api
spring.webflux.base-path=/v1
```

**参数详解表：**

| 参数 | 类型 | 含义 |
| :--- | :--- | :--- |
| `server.port` | `int` | 应用监听的端口，通常 80 (HTTP) 或 443 (HTTPS)。 |
| `server.ssl.enabled` | `boolean` | 是否启用 SSL (即 HTTPS)。 |
| `server.servlet.context-path` | `string` | **Spring MVC 专用**，定义所有 Controller 的统一前缀路径。 |
| `spring.webflux.base-path` | `string` | **Spring WebFlux 专用**，定义所有路由的统一前缀路径。 |

> ⚠️ **注意**：`context-path` 和 `base-path` 分别对应不同的 Spring Web 模块，不可混用。

### 1.2 🔐 SSL/TLS 详细配置 (HTTPS)

当 `server.ssl.enabled=true` 时，你需要提供证书和密钥库信息。

```bash
server.ssl.key-store=classpath:keystore.p12
server.ssl.key-store-password=your-password
server.ssl.key-store-type=PKCS12
server.ssl.key-alias=your-cert-alias
```

**SSL/TLS 参数详解表：**

| 参数 | 类型 | 含义 |
| :--- | :--- | :--- |
| `server.ssl.key-store` | `string` | 密钥库位置，支持 `classpath:` 或 `file:` 路径。 |
| `server.ssl.key-store-password` | `string` | 密钥库的密码。 |
| `server.ssl.key-store-type` | `string` | 密钥库类型，常用 `JKS` 或 `PKCS12`。 |
| `server.ssl.key-alias` | `string` | 密钥库中证书的别名。 |
| `server.ssl.trust-store` | `string` (可选) | 信任库位置，用于双向 TLS (mTLS)。 |
| `server.ssl.trust-store-password` | `string` (可选) | 信任库的密码。 |
| `server.ssl.client-auth` | `string` (可选) | 客户端认证方式：`none`, `want`, 或 `need` (用于 mTLS)。 |

---

## 第二部分：Kubernetes 集成示例

### 2.1 🧠 使用 ConfigMap 管理配置

#### 配置文件 (`server-conf.properties`)

```bash
server.port=443
server.ssl.enabled=true
server.ssl.key-store=classpath:keystore.p12
server.ssl.key-store-password=changeit
server.ssl.key-store-type=PKCS12
server.ssl.key-alias=app
spring.webflux.base-path=/v1
```

#### Kubernetes ConfigMap 定义

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

#### Pod 挂载配置

```yaml
# In your deployment.yaml
spec:
  template:
    spec:
      containers:
      - name: my-app
        volumeMounts:
        - name: config-volume
          mountPath: /app/config # 挂载到容器的这个路径
      volumes:
      - name: config-volume
        configMap:
          name: app-config
```

#### 应用启动时引用配置

```bash
# Spring Boot 启动参数
--spring.config.additional-location=file:/app/config/
```

### 2.2 🧩 小贴士

*   **端口权限**: 在容器中以非 root 用户运行时，监听 1024 以下的端口（如 443）会失败。建议使用 `8443` 等高位端口，并通过 Kubernetes Service 或 Ingress 转发。
*   **路径选择**: `server.servlet.context-path` (MVC) 与 `spring.webflux.base-path` (WebFlux) 互不通用，请根据项目技术栈选择。

### 2.3 📋 常用配置参数速查表

| 模块 | 参数 | 示例值 | 说明 |
| :--- | :--- | :--- | :--- |
| 通用 | `server.port` | `443` | 监听端口 |
| 通用 | `server.ssl.enabled` | `true` | 启用 HTTPS |
| MVC | `server.servlet.context-path` | `/api` | MVC 模式统一路径 |
| WebFlux | `spring.webflux.base-path` | `/v1` | WebFlux 模式统一路径 |
| SSL | `server.ssl.key-store` | `classpath:keystore.p12` | 密钥库路径 |
| SSL | `server.ssl.key-store-password` | `changeit` | 密钥库密码 |
| SSL | `server.ssl.key-store-type` | `PKCS12` | 密钥库类型 |
| SSL | `server.ssl.key-alias` | `app` | 证书别名 |

---

## 第三部分：调试指南：端口与健康检查

### 场景一：端口监听不正确或被占用

**问题描述：** 配置文件中设置 `server.port=8443`，但应用启动日志显示 `8080`，或提示 `Port 8443 was already in use`。

**核心原因：** 这是一个典型的配置加载优先级问题。高优先级的配置源覆盖了你的文件配置。

#### 步骤 1：理解 Spring Boot 配置加载顺序

| 优先级 | 配置源 | 示例 |
| :--- | :--- | :--- |
| **最高** | 1. 命令行参数 | `java -jar app.jar --server.port=8080` |
| | 2. 环境变量 | `export SERVER_PORT=8080` |
| | 3. `application-{profile}.properties` | `application-prod.properties` |
| **最低** | 4. `application.properties` | `src/main/resources/application.properties` |

#### 步骤 2：排查运行时环境

*   **检查环境变量和启动命令：**

    ```bash
    # 查看 Pod 的详细描述，重点关注 spec.containers.args 和 spec.containers.env
    kubectl describe pod <pod-name>

    # 直接在容器内检查环境变量
    kubectl exec -it <pod-name> -- env | grep -i "port\|server"
    ```

*   **验证 ConfigMap 挂载：**

    ```bash
    # 进入容器检查配置文件内容
    kubectl exec -it <pod-name> -- cat /app/config/server-conf.properties
    ```

#### 步骤 3：在应用层面排查 (代码调试)

如果环境检查无法定位问题，可以在代码中打印最终生效的配置。

```java
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.ApplicationListener;
import org.springframework.stereotype.Component;
import lombok.extern.slf4j.Slf4j;

@Slf4j
@Component
public class ConfigDebugger implements ApplicationListener<ApplicationReadyEvent> {
    @Value("${server.port:default}")
    private String serverPort;

    @Override
    public void onApplicationEvent(ApplicationReadyEvent event) {
        log.info("================ Configuration Debug ================");
        log.info("Final effective server.port is: {}", serverPort);
        log.info("=====================================================");
    }
}
```

#### 步骤 4：快速验证端口监听

```bash
# 进入容器内，使用 netstat 或 ss 命令检查端口监听情况
kubectl exec -it <pod-name> -- netstat -tlnp | grep java
kubectl exec -it <pod-name> -- ss -tlnp | grep java
```

### 场景二：健康检查 (Probe) 失败

**问题描述：** 应用正常启动，但 Pod 因健康检查失败被 Kubernetes 不断重启。

**核心原因：** Probe 配置的 `path` 与应用实际提供的健康检查 URL 不匹配。

#### 步骤 1：确认 Probe 配置

```bash
# 获取 Deployment 的 YAML 配置，并过滤出 Probe 相关部分
kubectl get deployment <deployment-name> -o yaml | grep -A 10 "readinessProbe"
```
示例配置：
```yaml
readinessProbe:
  httpGet:
    path: /apiname/v1.0.3/.well-known/health # <-- 关键路径
    port: 8443
    scheme: HTTPS
```

#### 步骤 2：在容器内验证 Probe 路径

```bash
# 使用 curl 在容器内部直接测试 Probe URL 是否能访问成功
# -k: 忽略 HTTPS 证书验证
# -v: 显示详细的请求和响应信息
kubectl exec -it <pod-name> -- curl -kv https://localhost:8443/apiname/v1.0.3/.well-known/health
```
*   **200 OK**: 路径正确。
*   **404 Not Found**: 应用没有在这个路径上提供服务。

#### 步骤 3：查找或添加正确的健康检查端点

*   **方案 A (推荐): 修改 Probe 路径**
    如果应用使用 Spring Boot Actuator，默认路径通常是 `/actuator/health`。应将 Probe 的 `path` 修改为此。

*   **方案 B: 在代码中添加自定义端点**
    如果必须使用自定义路径，请在代码中添加一个 Controller 来处理它。

    ```java
    import org.springframework.http.ResponseEntity;
    import org.springframework.web.bind.annotation.GetMapping;
    import org.springframework.web.bind.annotation.RestController;
    import java.util.Map;

    @RestController
    public class CustomHealthController {
        @GetMapping("/apiname/v1.0.3/.well-known/health")
        public ResponseEntity<Map<String, String>> customHealth() {
            return ResponseEntity.ok(Map.of("status", "UP"));
        }
    }
```

### 场景三：从运行的 JAR 文件中查找配置

**问题描述：** 需要确认打包在 `app.jar` 内部的配置文件（如 `apiname.yaml`）的内容。

#### 步骤 1：从容器复制 JAR 文件到本地

```bash
# 1. 在 Pod 中找到 JAR 文件的路径
JAR_PATH=$(kubectl exec -it <pod-name> -- find / -name "*.jar" 2>/dev/null | head -n 1)
echo "Found JAR at: $JAR_PATH"

# 2. 将 JAR 文件复制到本地
kubectl cp <namespace>/<pod-name>:$JAR_PATH ./app.jar
```

#### 步骤 2：解压并查看 JAR 内容

JAR 文件本质上是 ZIP 格式，可直接用 `unzip` 或 `jar` 命令操作。

```bash
# 列出 JAR 包中的所有 YAML 文件
unzip -l app.jar | grep -E "\\.yaml|\\.yml"

# 提取特定的文件到当前目录
unzip app.jar "BOOT-INF/classes/apiname.yaml"

# 查看文件内容
cat BOOT-INF/classes/apiname.yaml
```

#### 步骤 3：直接在容器内操作 (推荐)

如果不想复制大文件，可以直接在容器内完成解压和查看。

```bash
kubectl exec -it <pod-name> -- sh -c '
  JAR_PATH=$(find / -name "*.jar" 2>/dev/null | head -n 1) && \
  cd /tmp && \
  unzip -l $JAR_PATH | grep "apiname.yaml" && \
  unzip $JAR_PATH "BOOT-INF/classes/apiname.yaml" && \
  cat BOOT-INF/classes/apiname.yaml
'
```
