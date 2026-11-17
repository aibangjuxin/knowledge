# 5 分钟快速开始

## 🎯 目标

让你的 Golang 应用在 5 分钟内适配平台的 ConfigMap 配置。

## ✅ 前置条件

- Go 1.21+
- 已有 Golang 应用（使用 Gin/Chi/Echo 或 net/http）

## 🚀 三步集成

### 第 1 步：复制配置加载器（30 秒）

```bash
# 在你的项目根目录
mkdir -p pkg/config
cp platform-config-loader.go pkg/config/
```

### 第 2 步：修改 main.go（2 分钟）

```go
package main

import (
    "log"
    "your-project/pkg/config"  // 修改为你的项目路径
    "github.com/gin-gonic/gin"
)

func main() {
    // 加载平台配置
    cfg, _ := config.LoadPlatformConfig()
    
    r := gin.Default()
    
    // 使用 Context Path（关键！）
    api := r.Group(cfg.ContextPath)
    {
        api.GET("/health", func(c *gin.Context) {
            c.JSON(200, gin.H{"status": "ok"})
        })
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

### 第 3 步：测试（2 分钟）

```bash
# 本地测试
./test-local.sh

# 在另一个终端
curl -k https://localhost:8443/user-service/v1/health
```

## ✨ 完成！

你的应用现在已经：
- ✅ 读取平台 ConfigMap 配置
- ✅ 支持统一的 Context Path
- ✅ 支持 HTTPS
- ✅ 与 Java 应用使用相同配置

## 📦 部署到 K8S

```bash
# 构建镜像
docker build -t your-registry/your-app:latest .

# 部署（选择一个）
kubectl apply -f deployment.yaml  # 如果平台提供 PEM 证书
# 或
kubectl apply -f deployment-with-initcontainer.yaml  # 如果只有 PKCS12
```

## 🔍 验证部署

```bash
# 查看 Pod
kubectl get pods

# 查看日志
kubectl logs <pod-name>

# 测试健康检查
kubectl exec -it <pod-name> -- curl -k https://localhost:8443/user-service/v1/health
```

## 📚 下一步

- 详细集成指南：[INTEGRATION-GUIDE.md](INTEGRATION-GUIDE.md)
- 完整技术方案：[platform-configmap-adapter.md](platform-configmap-adapter.md)
- Java 对比：[JAVA-GOLANG-COMPARISON.md](JAVA-GOLANG-COMPARISON.md)

## ❓ 遇到问题？

| 问题 | 解决方案 |
|------|----------|
| 配置文件读取失败 | 检查 ConfigMap 是否挂载到 `/opt/config` |
| 证书文件不存在 | 使用 `deployment-with-initcontainer.yaml` |
| 健康检查失败 | 确认路径包含 Context Path |
| 404 错误 | 确认所有路由都在 `api.Group()` 下 |

查看完整故障排查：[INTEGRATION-GUIDE.md#故障排查](INTEGRATION-GUIDE.md)

---

**用时**：5 分钟  
**难度**：⭐⭐ (简单)  
**维护**：平台工程团队
