# Golang 应用适配平台 ConfigMap 配置指南

## 1. 背景

平台为 Java SpringBoot 应用统一注入了 `mycoat-common-sprint-conf` ConfigMap，实现：
- 强制 HTTPS（端口 8443）
- 统一 Context Path：`/${apiName}/v${minorVersion}`
- 统一证书管理（PKCS12 格式）

现在需要让 Golang 应用也能使用相同的配置机制，实现多语言统一管理。

---

## 2. 平台配置映射关系

### Java 配置（现有）
```properties
server.port=8443
server.ssl.enabled=true
server.ssl.key-store=/opt/keystore/mycoat-sbrt.p12
server.ssl.key-store-type=PKCS12
server.ssl.key-store-password=${KEY_STORE_PWD}
server.servlet.context-path=/${apiName}/v${minorVersion}
spring.webflux.base-path=/${apiName}/v${minorVersion}
```

### Golang 等价配置（需要实现）
```bash
# 从 ConfigMap 挂载的配置文件读取
APP_PORT=8443
ENABLE_TLS=true
TLS_CERT_PATH=/opt/keystore/tls.crt
TLS_KEY_PATH=/opt/keystore/tls.key
APP_CONTEXT_PATH=/${apiName}/v${minorVersion}
```

---

## 3. Golang 应用最小化改动方案

### 方案 A：直接读取 Properties 文件（推荐）

Golang 应用读取平台注入的 `server-conf.properties`，解析出需要的配置。

**优点**：
- 与 Java 应用使用完全相同的 ConfigMap
- 平台无需维护两套配置
- 配置变更对所有语言生效

**实现**：参考 `platform-config-loader.go`

### 方案 B：平台为 Golang 单独注入环境变量

平台在 Deployment 中为 Golang 应用额外注入环境变量。

**优点**：
- Golang 应用无需解析 properties 文件
- 代码更简洁

**缺点**：
- 平台需要维护两套配置逻辑
- 配置不一致风险

---

## 4. 证书格式转换

### 问题
Java 使用 PKCS12 格式（`.p12`），Golang 需要 PEM 格式（`.crt` + `.key`）

### 解决方案

#### 方案 1：平台统一提供两种格式（推荐）

ConfigMap 同时挂载：
```yaml
data:
  mycoat-sbrt.p12: <base64>      # Java 使用
  tls.crt: <base64>              # Golang 使用
  tls.key: <base64>              # Golang 使用
```

#### 方案 2：Golang 应用启动时转换

使用 InitContainer 或应用启动脚本转换：
```bash
openssl pkcs12 -in /opt/keystore/mycoat-sbrt.p12 \
  -passin env:KEY_STORE_PWD \
  -out /tmp/tls.crt -clcerts -nokeys

openssl pkcs12 -in /opt/keystore/mycoat-sbrt.p12 \
  -passin env:KEY_STORE_PWD \
  -out /tmp/tls.key -nocerts -nodes
```

---

## 5. 完整实现示例

### 5.1 配置加载器（推荐使用）

参考：`platform-config-loader.go`

核心功能：
- 读取 `/opt/config/server-conf.properties`
- 解析 `server.port`、`server.servlet.context-path` 等
- 支持环境变量替换（`${apiName}`、`${minorVersion}`）
- 处理证书路径

### 5.2 应用主程序

参考：`main.go`

核心功能：
- 使用配置加载器读取平台配置
- 基于 Gin 框架实现 Context Path
- 支持 HTTPS（TLS 1.2+）
- 健康检查端点

---

## 6. Kubernetes 部署配置

### 6.1 ConfigMap 挂载（与 Java 相同）

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: ${namespace}
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

### 6.2 Deployment 配置

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: golang-app
  namespace: ${namespace}
spec:
  template:
    spec:
      containers:
      - name: app
        image: your-golang-app:latest
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
          readOnly: true
        - name: keystore
          mountPath: /opt/keystore
          readOnly: true
        ports:
        - containerPort: 8443
          protocol: TCP
        readinessProbe:
          httpGet:
            path: /${apiName}/v${minorVersion}/health
            port: 8443
            scheme: HTTPS
          initialDelaySeconds: 10
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: mycoat-common-sprint-conf
      - name: keystore
        secret:
          secretName: mycoat-keystore
```

### 6.3 Service 配置

```yaml
apiVersion: v1
kind: Service
metadata:
  name: golang-app
  namespace: ${namespace}
spec:
  ports:
  - port: 8443
    targetPort: 8443
    protocol: TCP
    name: https
  selector:
    app: golang-app
```

---

## 7. 平台需要做的改动

### 最小化改动（推荐）

1. **证书格式支持**
   - 在 Secret 中同时提供 PKCS12 和 PEM 格式
   - 或提供 InitContainer 模板用于格式转换

2. **ConfigMap 保持不变**
   - Golang 应用直接读取现有的 `server-conf.properties`
   - 无需额外配置

3. **文档更新**
   - 提供 Golang 应用接入指南
   - 提供代码模板（本文档提供）

### 可选增强

1. **统一配置库**
   - 提供 Golang SDK：`mycoat-config-go`
   - 封装配置读取逻辑
   - 各团队直接引用

2. **配置验证**
   - 平台在部署时验证 Golang 应用是否正确读取配置
   - 检查端口、Context Path 是否符合规范

---

## 8. 应用开发者需要做的事情

### 步骤 1：引入配置加载器

将 `platform-config-loader.go` 复制到项目中：
```bash
cp platform-config-loader.go your-project/pkg/config/
```

### 步骤 2：修改 main.go

```go
import "your-project/pkg/config"

func main() {
    cfg, err := config.LoadPlatformConfig()
    if err != nil {
        log.Fatal(err)
    }
    
    // 使用配置启动服务
    // 参考 main.go 示例
}
```

### 步骤 3：更新 Dockerfile

确保应用能读取挂载的配置：
```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o app .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/app .
# 配置和证书由 K8S 挂载，无需 COPY
CMD ["./app"]
```

### 步骤 4：测试

本地测试：
```bash
# 模拟平台配置
mkdir -p /opt/config /opt/keystore
cat > /opt/config/server-conf.properties <<EOF
server.port=8443
server.ssl.enabled=true
server.servlet.context-path=/user-service/v1
EOF

# 生成测试证书
openssl req -x509 -newkey rsa:4096 -keyout /opt/keystore/tls.key \
  -out /opt/keystore/tls.crt -days 365 -nodes -subj "/CN=localhost"

# 设置环境变量
export apiName=user-service
export minorVersion=1

# 运行应用
go run main.go
```

访问测试：
```bash
curl -k https://localhost:8443/user-service/v1/health
```

---

## 9. 注意事项

1. **证书路径**
   - Java 使用 PKCS12：`/opt/keystore/mycoat-sbrt.p12`
   - Golang 需要 PEM：`/opt/keystore/tls.crt` + `/opt/keystore/tls.key`
   - 平台需要同时提供或提供转换机制

2. **环境变量替换**
   - `${apiName}` 和 `${minorVersion}` 必须在 Deployment ��定义
   - 配置加载器会自动替换

3. **健康检查路径**
   - 必须包含 Context Path
   - 示例：`/user-service/v1/health`

4. **TLS 版本**
   - 建议使用 TLS 1.2+
   - 代码示例已配置

5. **日志输出**
   - 启动时打印配置信息（脱敏）
   - 便于排查问题

---

## 10. 对比总结

| 项目 | Java SpringBoot | Golang（本方案） |
|------|----------------|-----------------|
| 配置文件 | server-conf.properties | 相同 |
| 端口 | 8443 | 8443 |
| Context Path | 自动注入 | 路由 Group 实现 |
| 证书格式 | PKCS12 | PEM（需转换） |
| 配置读取 | Spring 自动 | 手动解析（提供工具） |
| 部署复杂度 | 低 | 低（使用本方案） |

---

## 11. 后续优化建议

1. **统一配置 SDK**
   - 封装为 `mycoat-config-go` 库
   - 支持热更新（监听 ConfigMap 变化）

2. **证书自动转换**
   - 提供平台级 InitContainer
   - 自动将 PKCS12 转为 PEM

3. **配置校验工具**
   - 提供 CLI 工具验证应用是否正确读取配置
   - 集成到 CI/CD

4. **多语言支持**
   - 扩展到 Node.js、Python 等
   - 统一配置规范

---

## 12. 相关文件

- `platform-config-loader.go` - 配置加载器
- `main.go` - 应用示例
- `Dockerfile` - 容器构建示例
- `deployment.yaml` - K8S 部署示例

---

**文档版本**：v1.0  
**更新日期**：2025-11-30  
**维护团队**：平台工程团队
