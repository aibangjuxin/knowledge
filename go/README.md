# Golang 应用平台适配指南

本目录包含 Golang 应用适配平台 ConfigMap 配置的完整解决方案。

## 📖 文档导航

### 快速开始
- **[QUICK-START.md](QUICK-START.md)** - 5 分钟快速开始 ⚡

### 方案选择
- **[go-and-java-using-different-cm.md](go-and-java-using-different-cm.md)** - 独立 ConfigMap 方案（推荐）⭐⭐⭐⭐⭐
- **[platform-configmap-adapter.md](platform-configmap-adapter.md)** - 共享 ConfigMap + InitContainer 方案 ⭐⭐⭐⭐

### 详细文档
- **[INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md)** - 详细集成指南 📘
- **[JAVA-GOLANG-COMPARISON.md](JAVA-GOLANG-COMPARISON.md)** - Java 对比文档 🔄
- **[INDEX.md](INDEX.md)** - 完整文档索引 📑

## 文件说明

### 核心代码
- `platform-config-loader.go` - 配置加载器（核心组件）
- `platform-config-loader_test.go` - 单元测试
- `main.go` - 应用示例代码
- `go.mod` - Go 模块依赖

### 部署配置
- `Dockerfile` - 容器构建文件
- `deployment.yaml` - Kubernetes 部署配置（PEM 证书）
- `deployment-with-initcontainer.yaml` - K8S 部署配置（PKCS12 转换）

### 工具脚本
- `cert-management.sh` - 平台证书管理脚本（生成 PKCS12 + PEM）
- `configmap-management.sh` - ConfigMap 管理脚本
- `convert-cert.sh` - 证书格式转换脚本
- `test-local.sh` - 本地测试脚本

## 快速开始

### 1. 本地测试

```bash
# 安装依赖
go mod download

# 运行本地测试
chmod +x test-local.sh
./test-local.sh
```

### 2. 测试 API

在另一个终端：

```bash
# 健康检查
curl -k https://localhost:8443/user-service/v1/health

# 业务接口
curl -k https://localhost:8443/user-service/v1/hello

# POST 接口
curl -k -X POST https://localhost:8443/user-service/v1/data \
  -H "Content-Type: application/json" \
  -d '{"key":"value"}'
```

### 3. 构建镜像

```bash
docker build -t your-registry/golang-app:latest .
```

### 4. 部署到 K8S

```bash
# 替换变量
export namespace=your-namespace

# 应用配置
kubectl apply -f deployment.yaml
```

## 核心特性

✅ 与 Java 应用使用相同的 ConfigMap  
✅ 自动读取平台配置（端口、Context Path、SSL）  
✅ 支持环境变量替换（`${apiName}`、`${minorVersion}`）  
✅ 支持 HTTPS（TLS 1.2+）  
✅ 健康检查和就绪检查  
✅ 配置验证和错误处理  

## 集成到你的项目

### 步骤 1：复制配置加载器

```bash
mkdir -p your-project/pkg/config
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
    
    // 使用配置...
}
```

### 步骤 3：更新 go.mod

```bash
cd your-project
go mod tidy
```

### 步骤 4：构建和部署

参考 `Dockerfile` 和 `deployment.yaml`

## 证书格式转换

如果平台只提供 PKCS12 格式证书，使用转换脚本：

```bash
chmod +x convert-cert.sh
./convert-cert.sh /opt/keystore/mycoat-sbrt.p12 your-password
```

或在 Kubernetes 中使用 InitContainer（参考文档）。

## 常见问题

### Q: 如何验证配置是否正确加载？

A: 应用启动时会打印配置信息（脱敏）：
```
Starting with config: PlatformConfig{Port:8443, SSL:true, ContextPath:/user-service/v1, ...}
```

### Q: 健康检查失败怎么办？

A: 检查：
1. Context Path 是否正确（包含在路径中）
2. 证书文件是否存在
3. 端口是否正确

### Q: 如何支持其他路由框架？

A: 配置加载器与框架无关，可以用于：
- Gin（示例）
- Chi
- Echo
- net/http 标准库

只需在路由注册时使用 `cfg.ContextPath` 作为前缀。

## 更多信息

详细说明请参考 `platform-configmap-adapter.md`

## 联系方式

如有问题，请联系平台工程团队。
