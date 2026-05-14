# Java SpringBoot vs Golang 平台配置对比

## 配置对比表

| 配置项 | Java SpringBoot | Golang（本方案） | 说明 |
|--------|----------------|-----------------|------|
| **配置文件** | server-conf.properties | 相同 | 使用同一个 ConfigMap |
| **端口配置** | `server.port=8443` | 读取并使用 | 自动读取 |
| **SSL 开关** | `server.ssl.enabled=true` | 读取并使用 | 自动读取 |
| **Context Path** | `server.servlet.context-path` | 路由 Group 实现 | 需要手动挂载 |
| **证书格式** | PKCS12 (.p12) | PEM (.crt + .key) | 需要转换 |
| **证书加载** | Spring 自动 | 手动指定路径 | 使用 TLS 配置 |
| **环境变量替换** | Spring 自动 | 手动实现 | 配置加载器已实现 |
| **配置验证** | Spring 自动 | 手动实现 | 配置加载器已实现 |
| **热更新** | 支持（Spring Cloud Config） | 不支持（需重启） | 可扩展实现 |

## 代码对比

### Java SpringBoot

```java
// application.properties 或 ConfigMap 注入
// 无需代码，Spring 自动处理

@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}

@RestController
public class HealthController {
    // Context Path 自动生效
    @GetMapping("/health")
    public ResponseEntity<String> health() {
        return ResponseEntity.ok("OK");
    }
}
```

### Golang（本方案）

```go
package main

import (
    "log"
    "your-project/pkg/config"
    "github.com/gin-gonic/gin"
)

func main() {
    // 手动加载配置
    cfg, err := config.LoadPlatformConfig()
    if err != nil {
        log.Fatal(err)
    }

    r := gin.Default()
    
    // 手动挂载 Context Path
    api := r.Group(cfg.ContextPath)
    {
        api.GET("/health", func(c *gin.Context) {
            c.JSON(200, gin.H{"status": "ok"})
        })
    }

    // 手动启动 HTTPS
    addr := ":" + cfg.Port
    if cfg.SSLEnabled {
        log.Fatal(r.RunTLS(addr, cfg.TLSCertPath, cfg.TLSKeyPath))
    } else {
        log.Fatal(r.Run(addr))
    }
}
```

## 部署配置对比

### ConfigMap（完全相同）

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mycoat-common-sprint-conf
data:
  server-conf.properties: |
    server.port=8443
    server.ssl.enabled=true
    server.ssl.key-store=/opt/keystore/mycoat-sbrt.p12
    server.ssl.key-store-type=PKCS12
    server.ssl.key-store-password=${KEY_STORE_PWD}
    server.servlet.context-path=/${apiName}/v${minorVersion}
```

### Deployment 差异

#### Java SpringBoot

```yaml
spec:
  containers:
  - name: app
    image: java-app:latest
    env:
    - name: KEY_STORE_PWD
      valueFrom:
        secretKeyRef:
          name: keystore-secret
          key: password
    - name: apiName
      value: "user-service"
    - name: minorVersion
      value: "1"
    volumeMounts:
    - name: config
      mountPath: /opt/config
    - name: keystore
      mountPath: /opt/keystore  # PKCS12 证书
  volumes:
  - name: keystore
    secret:
      secretName: mycoat-keystore  # 包含 .p12 文件
```

#### Golang（方案 A：平台提供 PEM）

```yaml
spec:
  containers:
  - name: app
    image: golang-app:latest
    env:
    - name: KEY_STORE_PWD
      valueFrom:
        secretKeyRef:
          name: keystore-secret
          key: password
    - name: apiName
      value: "user-service"
    - name: minorVersion
      value: "1"
    - name: TLS_CERT_PATH
      value: "/opt/keystore/tls.crt"
    - name: TLS_KEY_PATH
      value: "/opt/keystore/tls.key"
    volumeMounts:
    - name: config
      mountPath: /opt/config
    - name: keystore
      mountPath: /opt/keystore  # PEM 证书
  volumes:
  - name: keystore
    secret:
      secretName: mycoat-keystore-pem  # 包含 .crt 和 .key
```

#### Golang（方案 B：InitContainer 转换）

```yaml
spec:
  initContainers:
  - name: cert-converter
    image: alpine:latest
    command: ["/bin/sh", "-c"]
    args:
    - |
      apk add --no-cache openssl
      openssl pkcs12 -in /opt/keystore-p12/mycoat-sbrt.p12 \
        -passin env:KEY_STORE_PWD \
        -out /opt/keystore-pem/tls.crt -clcerts -nokeys
      openssl pkcs12 -in /opt/keystore-p12/mycoat-sbrt.p12 \
        -passin env:KEY_STORE_PWD \
        -out /opt/keystore-pem/tls.key -nocerts -nodes
    volumeMounts:
    - name: keystore-p12
      mountPath: /opt/keystore-p12
    - name: keystore-pem
      mountPath: /opt/keystore-pem
  containers:
  - name: app
    image: golang-app:latest
    volumeMounts:
    - name: keystore-pem
      mountPath: /opt/keystore
  volumes:
  - name: keystore-p12
    secret:
      secretName: mycoat-keystore  # PKCS12（与 Java 相同）
  - name: keystore-pem
    emptyDir: {}  # InitContainer 生成
```

## 功能对比

### 配置读取

| 功能 | Java | Golang |
|------|------|--------|
| 读取 properties 文件 | ✅ 自动 | ✅ 手动（已提供工具） |
| 环境变量替换 | ✅ 自动 | ✅ 手动（已提供工具） |
| 配置验证 | ✅ 自动 | ✅ 手动（已提供工具） |
| 类型转换 | ✅ 自动 | ✅ 手动 |
| 默认值 | ✅ 注解 | ✅ 代码 |

### Context Path

| 功能 | Java | Golang |
|------|------|--------|
| 自动注入 | ✅ | ❌ |
| 路由前缀 | ✅ 自动 | ✅ 手动（Group） |
| 静态资源 | ✅ 自动 | ⚠️ 需手动配置 |
| Swagger UI | ✅ 自动 | ⚠️ 需手动配置 |

### SSL/TLS

| 功能 | Java | Golang |
|------|------|--------|
| PKCS12 支持 | ✅ 原生 | ❌ 需转换 |
| PEM 支持 | ⚠️ 需配置 | ✅ 原生 |
| 自动证书加载 | ✅ | ✅ |
| TLS 版本控制 | ✅ 配置 | ✅ 代码 |
| 加密套件 | ✅ 配置 | ✅ 代码 |

### 健康检查

| 功能 | Java | Golang |
|------|------|--------|
| 自动端点 | ✅ Actuator | ❌ 需手动实现 |
| Context Path 感知 | ✅ 自动 | ✅ 手动 |
| 详细信息 | ✅ 丰富 | ⚠️ 需自定义 |

## 开发体验对比

### Java SpringBoot

**优点**：
- 零配置，开箱即用
- 自动处理 Context Path
- 丰富的生态和工具
- 热更新支持

**缺点**：
- 启动时间较长
- 内存占用较大
- 镜像体积大

### Golang

**优点**：
- 启动速度快
- 内存占用小
- 镜像体积小
- 性能优秀

**缺点**：
- 需要手动实现配置加载
- 需要手动挂载 Context Path
- 证书格式需要转换
- 生态相对较小

## 迁移建议

### 从 Java 迁移到 Golang

1. **使用本方案的配置加载器**
   - 无需修改 ConfigMap
   - 自动兼容 Java 配置格式

2. **处理证书格式**
   - 方案 A：平台提供 PEM 格式
   - 方案 B：使用 InitContainer 转换

3. **实现 Context Path**
   - 使用路由 Group
   - 确保所有路由都挂载在 Group 下

4. **实现健康检查**
   - 添加 `/health` 和 `/ready` 端点
   - 确保路径包含 Context Path

### 新应用选择建议

**选择 Java SpringBoot 如果**：
- 团队熟悉 Java 生态
- 需要丰富的企业级功能
- 对启动时间和内存不敏感
- 需要热更新等高级特性

**选择 Golang 如果**：
- 追求高性能和低资源占用
- 需要快速启动（适合 Serverless）
- 团队熟悉 Go 语言
- 应用逻辑相对简单

## 成本对比

### 资源消耗（典型场景）

| 指标 | Java SpringBoot | Golang | 节省 |
|------|----------------|--------|------|
| 内存（空闲） | 256MB | 32MB | 87.5% |
| 内存（负载） | 512MB | 128MB | 75% |
| CPU（空闲） | 0.1 core | 0.01 core | 90% |
| 启动时间 | 30s | 1s | 96.7% |
| 镜像大小 | 200MB | 20MB | 90% |

### 成本估算（100 个实例）

假设：
- 云服务器：$0.05/GB/月（内存）
- 存储：$0.10/GB/月

| 项目 | Java | Golang | 月节省 |
|------|------|--------|--------|
| 内存成本 | $2,560 | $640 | $1,920 |
| 存储成本 | $200 | $20 | $180 |
| **总计** | **$2,760** | **$660** | **$2,100** |

**年节省**：$25,200

## 总结

### 配置兼容性

✅ **完全兼容**：Golang 应用可以使用与 Java 相同的 ConfigMap  
✅ **最小改动**：只需添加配置加载器和调整路由  
⚠️ **证书处理**：需要额外处理证书格式转换  

### 推荐方案

1. **短期**：使用 InitContainer 方案，与 Java 共享 PKCS12 证书
2. **长期**：平台统一提供 PEM 格式证书，简化部署

### 平台改进建议

1. **证书管理**
   - Secret 同时包含 PKCS12 和 PEM 格式
   - 或提供统一的 InitContainer 模板

2. **配置 SDK**
   - 提供官方 Golang SDK：`mycoat-config-go`
   - 封装配置加载逻辑
   - 支持多种语言（Node.js、Python 等）

3. **文档和工具**
   - 提供各语言接入指南
   - 提供配置验证工具
   - 集成到 CI/CD

---

**文档版本**：v1.0  
**更新日期**：2025-11-30
