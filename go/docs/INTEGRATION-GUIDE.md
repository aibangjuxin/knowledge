# Golang 应用集成平台配置 - 快速指南

## 概述

本指南帮助你快速将现有 Golang 应用集成到平台的统一配置管理体系中。

## 前置条件

- Go 1.21+
- 应用使用 Gin / Chi / Echo 或标准 net/http
- 了解基本的 Kubernetes 概念

## 集成步骤

### 第 1 步：添加配置加载器

将 `platform-config-loader.go` 复制到你的项目：

```bash
# 创建配置包目录
mkdir -p your-project/pkg/config

# 复制配置加载器
cp platform-config-loader.go your-project/pkg/config/

# 如果需要，也复制测试文件
cp platform-config-loader_test.go your-project/pkg/config/
```

### 第 2 步：修改应用入口

在你的 `main.go` 中：

```go
package main

import (
    "log"
    "your-project/pkg/config"
    "github.com/gin-gonic/gin"
)

func main() {
    // 加载平台配置
    cfg, err := config.LoadPlatformConfig()
    if err != nil {
        log.Fatalf("Failed to load platform config: %v", err)
    }

    // 验证配置
    if err := cfg.Validate(); err != nil {
        log.Fatalf("Invalid config: %v", err)
    }

    log.Printf("Starting with config: %s", cfg.String())

    // 创建路由
    r := gin.Default()

    // 使用 Context Path
    api := r.Group(cfg.ContextPath)
    {
        api.GET("/health", healthHandler)
        api.GET("/ready", readyHandler)
        // 你的其他路由...
    }

    // 启动服务
    addr := ":" + cfg.Port
    if cfg.SSLEnabled {
        log.Fatal(r.RunTLS(addr, cfg.TLSCertPath, cfg.TLSKeyPath))
    } else {
        log.Fatal(r.Run(addr))
    }
}
```

### 第 3 步：更新 Dockerfile

确保你的 Dockerfile 支持配置和证书挂载：

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o app .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/app .
# 配置和证书由 K8S 挂载
EXPOSE 8443
CMD ["./app"]
```

### 第 4 步：准备 Kubernetes 配置

使用提供的 `deployment.yaml` 或 `deployment-with-initcontainer.yaml`：

**选项 A：平台提供 PEM 证书**
```bash
kubectl apply -f deployment.yaml
```

**选项 B：使用 InitContainer 转换证书**
```bash
kubectl apply -f deployment-with-initcontainer.yaml
```

### 第 5 步：本地测试

```bash
# 运行测试脚本
chmod +x test-local.sh
./test-local.sh

# 在另一个终端测试
curl -k https://localhost:8443/user-service/v1/health
```

## 配置说明

### 环境变量

应用会读取以下环境变量：

| 变量名 | 说明 | 示例 | 必需 |
|--------|------|------|------|
| `PLATFORM_CONFIG_PATH` | 配置文件路径 | `/opt/config/server-conf.properties` | 否（有默认值） |
| `KEY_STORE_PWD` | 证书密码 | `secret123` | 是（如果启用 SSL） |
| `apiName` | API 名称 | `user-service` | 是 |
| `minorVersion` | API 版本 | `1` | 是 |
| `TLS_CERT_PATH` | TLS 证书路径 | `/opt/keystore/tls.crt` | 否（有默认值） |
| `TLS_KEY_PATH` | TLS 私钥路径 | `/opt/keystore/tls.key` | 否（有默认值） |

### 配置文件格式

平台注入的 `server-conf.properties`：

```properties
server.port=8443
server.ssl.enabled=true
server.ssl.key-store=/opt/keystore/mycoat-sbrt.p12
server.ssl.key-store-type=PKCS12
server.ssl.key-store-password=${KEY_STORE_PWD}
server.servlet.context-path=/${apiName}/v${minorVersion}
```

## 常见场景

### 场景 1：使用 Chi 路由器

```go
import "github.com/go-chi/chi/v5"

r := chi.NewRouter()
r.Route(cfg.ContextPath, func(r chi.Router) {
    r.Get("/health", healthHandler)
    r.Get("/hello", helloHandler)
})
```

### 场景 2：使用标准 net/http

```go
import "net/http"

mux := http.NewServeMux()
mux.HandleFunc(cfg.ContextPath+"/health", healthHandler)
mux.HandleFunc(cfg.ContextPath+"/hello", helloHandler)

if cfg.SSLEnabled {
    http.ListenAndServeTLS(":"+cfg.Port, cfg.TLSCertPath, cfg.TLSKeyPath, mux)
} else {
    http.ListenAndServe(":"+cfg.Port, mux)
}
```

### 场景 3：添加中间件

```go
api := r.Group(cfg.ContextPath)
api.Use(loggingMiddleware)
api.Use(authMiddleware)
{
    api.GET("/health", healthHandler)
    // ...
}
```

## 故障排查

### 问题 1：配置文件读取失败

**错误**：`Failed to load config: open /opt/config/server-conf.properties: no such file or directory`

**解决**：
1. 检查 ConfigMap 是否正确挂载
2. 检查 volumeMounts 配置
3. 使用 `kubectl exec` 进入 Pod 验证文件存在

```bash
kubectl exec -it <pod-name> -- ls -la /opt/config/
```

### 问题 2：证书文件不存在

**错误**：`TLS cert file not found: /opt/keystore/tls.crt`

**解决**：
1. 如果平台只提供 PKCS12，使用 InitContainer 方案
2. 检查 Secret 是否正确挂载
3. 验证证书文件权限

### 问题 3：健康检查失败

**错误**：`Readiness probe failed: HTTP probe failed`

**解决**：
1. 确认健康检查路径包含 Context Path
2. 检查端口是否正确（8443）
3. 确认使用 HTTPS scheme

```yaml
readinessProbe:
  httpGet:
    path: /user-service/v1/health  # 必须包含 Context Path
    port: 8443
    scheme: HTTPS  # 必须是 HTTPS
```

### 问题 4：Context Path 不生效

**症状**：访问 `/user-service/v1/health` 返回 404

**解决**：
1. 检查环境变量 `apiName` 和 `minorVersion` 是否设置
2. 查看应用启动日志，确认 Context Path 正确解析
3. 确认所有路由都挂载在 Group 下

## 性能优化

### 1. 配置缓存

配置加载器已经在应用启动时一次性加载，无需额外缓存。

### 2. TLS 优化

代码示例已包含 TLS 1.2+ 和推荐的加密套件配置。

### 3. 健康检查优化

```go
// 使用轻量级健康检查
api.GET("/health", func(c *gin.Context) {
    c.String(200, "OK")  // 比 JSON 更快
})
```

## 安全建议

1. **证书管理**
   - 使用 Kubernetes Secret 存储证书
   - 定期轮换证书
   - 使用 cert-manager 自动化证书管理

2. **密码管理**
   - 永远不要在代码中硬编码密码
   - 使用 Secret 注入环境变量
   - 考虑使用 Vault 等密钥管理系统

3. **日志脱敏**
   - 配置加载器已自动脱敏密码
   - 确保业务日志不输出敏感信息

## 测试清单

部署前确认：

- [ ] 本地测试通过（使用 `test-local.sh`）
- [ ] 单元测试通过（`go test ./...`）
- [ ] 配置文件正确挂载
- [ ] 证书文件可访问
- [ ] 环境变量正确设置
- [ ] 健康检查路径正确
- [ ] Context Path 符合规范
- [ ] TLS 配置正确

## 下一步

1. 阅读完整文档：`platform-configmap-adapter.md`
2. 查看代码示例：`main.go`
3. 了解部署配置：`deployment.yaml`
4. 运行单元测试：`platform-config-loader_test.go`

## 获取帮助

- 技术问题：联系平台工程团队
- 文档问题：提交 Issue
- 紧急支持：查看团队 Wiki

---

**版本**：v1.0  
**更新**：2025-11-30
